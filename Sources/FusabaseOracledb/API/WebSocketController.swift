// Copyright (c) 2015, 2025, Oracle and/or its affiliates.

//-----------------------------------------------------------------------------
//
// This software is dual-licensed to you under the Universal Permissive License
// (UPL) 1.0 as shown at https://oss.oracle.com/licenses/upl and Apache License
// 2.0 as shown at http://www.apache.org/licenses/LICENSE-2.0. You may choose
// either license.
//
// If you elect to accept the software under the Apache License, Version 2.0,
// the following applies:
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
//-----------------------------------------------------------------------------


import Foundation
import FusabaseCore
import FusabaseAuth

// Lightweight adapter to reuse existing 'logger.*' call sites with the centralized OracledbLogger.
private struct OracledbLoggerBridge {
    func debug(_ message: String) { OracledbLogger.debug(message) }
    func info(_ message: String) { OracledbLogger.info(message) }
    func warning(_ message: String) { OracledbLogger.warning(message) }
    func error(_ message: String) { OracledbLogger.error(message) }
}

// Type-erased listener wrapper used by WebSocketController to store heterogeneous listeners at runtime.
protocol AnyListenerData: AnyObject {
    var anyReference: Reference { get }
    var anyPreviousResult: Snapshot? { get }
    func executeAny(_ value: Snapshot?, _ error: Error?)
    func setAnyPreviousResult(_ current: Snapshot)
}

// Bridge all ListenerData<K,T> to AnyListenerData without storing extra state.
extension ListenerData: AnyListenerData {
    var anyReference: Reference { return self.getReference() }
    var anyPreviousResult: Snapshot? { return self.getPreviousResult() }
    func executeAny(_ value: Snapshot?, _ error: Error?) { self.executeListener(value, error) }
    func setAnyPreviousResult(_ current: Snapshot) {
        if let typed = current as? T {
            _ = self.setPreviousResult(typed)
        }
    }
}

/**
 * Manages WebSocket connections for real-time data synchronization.
 * Handles listener registration, message processing, and connection lifecycle
 * for snapshot listeners that require real-time updates.
 *
 * Notes:
 * - Since Swift Reference protocol does not expose a generic get(Source) API,
 *   this controller fetches initial/updated snapshots by branching on the
 *   concrete reference type (DocumentReference vs Query) and calling their
 *   async getters (getDocument/getDocuments).
 * - For change notifications after initial success, if the message does not
 *   contain a first-snapshot state, we re-fetch from the server to compute
 *   the up-to-date snapshot.
 */
final class WebSocketController: NSObject, URLSessionWebSocketDelegate {

    // MARK: - Types

    private enum ControllerError: Error {
        case internalError(String)
        case unauthenticated(String)
        case network(String)
    }

    // MARK: - Constants

    private static let TAG = "FusabaseOradb"
    private static let ORDS_REALTIME_PATH = "/ords/baas-realtime/"

    // MARK: - Singleton

    private static var instance: WebSocketController?
    /// Returns the shared WebSocketController bound to the supplied database instance.
    /// The instance is lazily created on first access.
    static func getInstance(_ oracledb: FusabaseOracledb) -> WebSocketController {
        if let inst = instance { return inst }
        let inst = WebSocketController(oracledb: oracledb)
        instance = inst
        return inst
    }

    // MARK: - Properties

    private let logger = OracledbLoggerBridge()

    private let oracledb: FusabaseOracledb

    // URLSession + task for WebSockets (macOS 10.15+)
    /// URLSession used to host the WebSocket connection lifecycle. Created on connect, invalidated on close.
    private var session: URLSession?
    /// The active URLSessionWebSocketTask associated with the current connection attempt or established socket.
    private var webSocketTask: URLSessionWebSocketTask?

    // Message queue and listener registry
    /// In-memory queue of inbound messages keyed by queryId pending initial snapshot availability.
    private var messageQueue: [[String: Any]] = []
    /// Map of queryId to registered listeners. Protected by syncQueue.
    private var registeredQuery: [Int: [AnyListenerData]] = [:]

    /// Guards against concurrent connection attempts; set true before dialing and reset on open/close/failure.
    private var webSocketConnectionInProgress: Bool = false
    /// True after didOpen fires; false after close/failure. Intended for diagnostics.
    private var isConnected: Bool = false
    /// Periodic ping timer to keep the connection alive on intermediaries.
    private var pingTimer: DispatchSourceTimer?

    /// Tracks whether the receive loop should continue.
    /// When a terminal error occurs (e.g. TLS trust failure), we stop re-receiving to avoid log spam.
    private var shouldContinueReceiving: Bool = false

    /// Last receive-loop error signature logged. Used to suppress duplicate spam.
    private var lastReceiveErrorKey: String?

    // Synchronization queue for internal state
    /// Synchronization queue for thread-safe mutations and reads of controller state.
    private let syncQueue = DispatchQueue(label: "com.oracle.databse.fusabase.websocket.controller", attributes: .concurrent)

    // MARK: - Init

    private init(oracledb: FusabaseOracledb) {
        self.oracledb = oracledb
        super.init()
        OracledbLogger.info("Initialized")
    }

    // MARK: - Public registration API

    /// Registers a query listener with the WebSocket controller.
    ///
    /// - Parameters:
    ///   - queryId: The ID of the query to register
    ///   - listenerData: The listener data to register
    func registerQueryWithController<K: Reference, T: Snapshot>(_ queryId: Int, listenerData: ListenerData<K, T>) {
        syncQueue.async(flags: .barrier) {
            var current = self.registeredQuery[queryId] ?? []
            current.append(listenerData as AnyListenerData)
            self.registeredQuery[queryId] = current

            OracledbLogger.debug("WS registerQueryWithController queryId=\(queryId) listenersForQuery=\(current.count) totalQueries=\(self.registeredQuery.keys.count)")
        }
    }

    /// Deregisters a query listener from the WebSocket controller.
    ///
    /// - Parameters:
    ///   - queryId: The ID of the query to deregister
    ///   - listenerData: The listener data to remove
    func deregisterQuery<K: Reference, T: Snapshot>(_ queryId: Int, listenerData: ListenerData<K, T>) {
        syncQueue.async(flags: .barrier) {
            guard var current = self.registeredQuery[queryId] else { return }
            // Identity-based remove
            current.removeAll { $0 === (listenerData as AnyListenerData) }
            if current.isEmpty {
                self.registeredQuery.removeValue(forKey: queryId)
            } else {
                self.registeredQuery[queryId] = current
            }

            OracledbLogger.debug("WS deregisterQuery queryId=\(queryId) remainingListeners=\(current.count) totalQueries=\(self.registeredQuery.keys.count)")
        }
    }

    /// Checks if a query should be deregistered based on listener count.
    /// Returns true when there are no listeners registered for the query (including when the entry is absent).
    func shouldDeregisterQuery(_ queryId: Int) -> Bool {
        var result = false
        syncQueue.sync {
            result = (self.registeredQuery[queryId]?.isEmpty ?? true)
        }
        return result
    }

    /// Checks if the WebSocket connection should be closed (no queries registered).
    func shouldCloseConnection() -> Bool {
        var result = false
        syncQueue.sync {
            result = self.registeredQuery.isEmpty
        }
        return result
    }

    /// Checks if a query should be registered (at least one listener).
    func shouldRegisterQuery(_ queryId: Int) -> Bool {
        return !shouldDeregisterQuery(queryId)
    }

    /// Adds a registration success message to the queue.
    func putRegistrationSuccessMessage(_ queryId: Int) {
        let message: [String: Any] = [
            "queryId": queryId,
            "success": 1
        ]
        syncQueue.async(flags: .barrier) {
            self.messageQueue.append(message)
        }
    }

    // MARK: - WebSocket lifecycle

    /// Establishes a WebSocket connection for real-time updates.
    /// Retrieves authentication token and connects to the ORDS real-time service.
    /// - Returns: true if a connection attempt was initiated or already exists; false if WebSocket
    ///            cannot be used (e.g. missing auth token, authorizeSnapshot failure, unsupported OS).
    @discardableResult
    func establishWebSocketConnection() -> Bool {
        var alreadyInProgress = false
        syncQueue.sync {
            alreadyInProgress = self.webSocketConnectionInProgress
            if !alreadyInProgress {
                self.webSocketConnectionInProgress = true
            }
        }
        if alreadyInProgress { return true }

        // If no access token, warn and skip establishing WS; HTTP path will continue with apiKey-only requests.
        var hasAccessToken = false
        KeychainTokenStore.shared.withSecureToken(.access) { token in
            hasAccessToken = !token.isEmpty
        }
        if !hasAccessToken {
            OracledbLogger.warning("No ACCESS_TOKEN found; skipping WebSocket connection. Proceeding without realtime updates.")
            syncQueue.async(flags: .barrier) {
                self.webSocketConnectionInProgress = false
            }
            return false
        }

        // Fetch snapshot token (synchronous for simplicity)
        let snapshotCredential: [String: Any]
        do {
            snapshotCredential = try getSnapshotToken()
        } catch {
            logger.error("authorizeSnapshot failed: \(error)")
            syncQueue.async(flags: .barrier) {
                self.webSocketConnectionInProgress = false
            }
            return false
        }

        // Build WS URL
        guard let wsURL = buildWebSocketURL(snapshotCredential: snapshotCredential) else {
            logger.error("Failed to build WebSocket URL")
            syncQueue.async(flags: .barrier) {
                self.webSocketConnectionInProgress = false
            }
            return false
        }

        logger.debug("Created WS URI \(wsURL.absoluteString)")

        if #available(macOS 10.15, iOS 15.0, *) {
            let config = URLSessionConfiguration.default
            // No cookies or persistent caches for WS
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            // Enforce TLS 1.2 minimum for security
            config.tlsMinimumSupportedProtocolVersion = .TLSv12
            self.session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
            self.webSocketTask = self.session?.webSocketTask(with: wsURL)
            self.webSocketTask?.resume()
            logger.debug("WebSocket connection attempt started")

            syncQueue.async(flags: .barrier) {
                self.shouldContinueReceiving = true
                self.lastReceiveErrorKey = nil
            }

            // Start receive loop
            self.receiveLoop()
            return true
        } else {
            logger.error("WebSockets require macOS 10.15+/iOS 15+")
            syncQueue.async(flags: .barrier) {
                self.webSocketConnectionInProgress = false
            }
            return false
        }

    }

    /// Closes the WebSocket connection.
    func closeWebSocketConnection() {
        if #available(macOS 10.15, iOS 15.0, *) {
            stopPingTimer()
            webSocketTask?.cancel(with: .goingAway, reason: nil)
            webSocketTask = nil
            session?.invalidateAndCancel()
            session = nil
            syncQueue.async(flags: .barrier) {
                self.isConnected = false
                self.webSocketConnectionInProgress = false
                self.shouldContinueReceiving = false
                self.lastReceiveErrorKey = nil
            }
            logger.debug("Connection with ords-baas-server closed.")
        }
    }

    // MARK: - Message handling

    /// Processes queued messages for a specific query.
    ///
    /// - Parameter queryId: the query ID to process messages for
    func processQueue(_ queryId: Int) {
        var toProcess: [[String: Any]] = []
        let sema = DispatchSemaphore(value: 0)
        syncQueue.async(flags: .barrier) {
            // Drain messages for this queryId atomically
            var remaining: [[String: Any]] = []
            for msg in self.messageQueue {
                if let mid = msg["queryId"] as? Int, mid == queryId {
                    toProcess.append(msg)
                } else {
                    remaining.append(msg)
                }
            }
            self.messageQueue = remaining
            sema.signal()
        }
        sema.wait()

        for msg in toProcess {
            processMessage(msg)
        }
    }

    /// Processes a WebSocket message and notifies appropriate listeners.
    ///
    /// - Parameter messageObject: the JSON message to process
    private func processMessage(_ messageObject: [String: Any]) {
        guard let queryId = messageObject["queryId"] as? Int else {
            logger.warning("Received message without queryId; ignoring")
            return
        }

        var listeners: [AnyListenerData] = []
        syncQueue.sync {
            listeners = self.registeredQuery[queryId] ?? []
        }

        if listeners.isEmpty {
            logger.warning("Unknown notification received which doesn't belong to any query.")
            return
        }

        if messageObject["success"] != nil {
            // After successful registration, we must emit a first snapshot
            for listenerData in listeners {
                fetchAndEmitInitialSnapshot(for: listenerData, queryId: queryId)
            }
        } else if let errorMessage = messageObject["error"] as? String {
            logger.error("Error received from ORDS \(errorMessage)")
            for listenerData in listeners {
                listenerData.executeAny(nil, ControllerError.internalError(errorMessage))
            }
        } else {
            // Change notifications
            var queued = false
            for listenerData in listeners {
                // Ensure first snapshot exists before processing notifications
                if listenerData.anyPreviousResult == nil {
                    if !queued {
                        syncQueue.async(flags: .barrier) {
                            self.messageQueue.append(messageObject)
                        }
                        queued = true
                    }
                    continue
                }

                // In Java, rowId and changedData are present and delta is applied to previous snapshot.
                // In Swift SDK we refetch and deliver current snapshot to keep behavior correct.
                refetchAndEmit(for: listenerData, queryId: queryId)
            }
        }
    }

    // MARK: - Snapshot helpers

    private func fetchAndEmitInitialSnapshot(for listenerData: AnyListenerData, queryId: Int) {
        if #available(macOS 10.15.0, iOS 15.0, *) {
            Task.detached { [weak self] in
                guard let self = self else { return }
                do {
                    if let docRef = listenerData.anyReference as? DocumentReference {
                        let snap = try await docRef.getDocument()
                        listenerData.executeAny(snap, nil)
                        // Process any queued notifications now that initial snapshot exists
                        self.processQueue(queryId)
                    } else if let query = listenerData.anyReference as? Query {
                        let snap = try await query.getDocuments()
                        listenerData.executeAny(snap, nil)
                        self.processQueue(queryId)
                    } else {
                        listenerData.executeAny(nil, ControllerError.internalError("Unsupported reference type for initial snapshot"))
                    }
                } catch {
                    listenerData.executeAny(nil, error)
                }
            }
        } else {
            listenerData.executeAny(nil, ControllerError.internalError("Async initial fetch requires macOS 10.15+/iOS 15+"))
        }
    }

    private func refetchAndEmit(for listenerData: AnyListenerData, queryId: Int) {
        if #available(macOS 10.15.0, iOS 15.0, *) {
            Task.detached { [weak self] in
                guard let _ = self else { return }
                do {
                    if let docRef = listenerData.anyReference as? DocumentReference {
                        let snap = try await docRef.getDocument()
                        listenerData.executeAny(snap, nil)
                    } else if let query = listenerData.anyReference as? Query {
                        let snap = try await query.getDocuments()
                        listenerData.executeAny(snap, nil)
                    } else {
                        listenerData.executeAny(nil, ControllerError.internalError("Unsupported reference type for change notification"))
                    }
                } catch {
                    listenerData.executeAny(nil, error)
                }
            }
        } else {
            listenerData.executeAny(nil, ControllerError.internalError("Async update fetch requires macOS 10.15+/iOS 15+"))
        }
    }

    // MARK: - WebSocket receive loop

    @available(macOS 10.15, iOS 15.0, *)
    /// Continuously receives WebSocket frames and dispatches JSON messages by queryId.
    /// On parse failure or missing queryId, messages are ignored.
    private func receiveLoop() {
        // Avoid tight loops when a terminal failure happens.
        var continueReceiving = false
        syncQueue.sync {
            continueReceiving = self.shouldContinueReceiving
        }
        if !continueReceiving { return }

        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure(let error):
                // If the socket is not usable (e.g. TLS trust failure), stop the loop to avoid spamming logs.
                let nsError = error as NSError
                let errorKey = "\(nsError.domain):\(nsError.code):\(nsError.localizedDescription)"

                // Treat expected cancellations as debug to avoid scary logs when the app removes listeners
                // and the socket is intentionally torn down.
                if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                    OracledbLogger.debug("Connection with ords-baas-server cancelled.")
                    self.syncQueue.async(flags: .barrier) {
                        self.shouldContinueReceiving = false
                        self.isConnected = false
                        self.webSocketConnectionInProgress = false
                    }
                    return
                }

                var shouldLog = true
                self.syncQueue.sync {
                    shouldLog = (self.lastReceiveErrorKey != errorKey)
                }
                if shouldLog {
                    OracledbLogger.error("Connection with ords-baas-server failed: \(error.localizedDescription)")
                    self.syncQueue.async(flags: .barrier) {
                        self.lastReceiveErrorKey = errorKey
                    }
                }

                // Stop receiving on terminal URLSession errors.
                // For transient errors, the app may call establishWebSocketConnection() again.
                self.syncQueue.async(flags: .barrier) {
                    self.shouldContinueReceiving = false
                    self.isConnected = false
                    self.webSocketConnectionInProgress = false
                }
                return
            case .success(let message):
                switch message {
                case .string(let text):
                    OracledbLogger.debug("WS recv (string): \(text)")
                    if let obj = self.parseJSONString(text) {
                        OracledbLogger.debug("WS recv parsed JSON: \(obj)")
                        // Enqueue and process this query's message
                        if let qid = obj["queryId"] as? Int {
                            OracledbLogger.debug("WS recv queryId=\(qid)")
                            self.syncQueue.async(flags: .barrier) {
                                self.messageQueue.append(obj)
                            }
                            self.processQueue(qid)
                        } else {
                            OracledbLogger.warning("Received WS message without queryId; ignoring")
                        }
                    } else {
                        OracledbLogger.warning("Ignoring received message. Failed to parse JSON.")
                    }
                case .data(let data):
                    // Try to parse as UTF-8 string
                    if let text = String(data: data, encoding: .utf8) {
                        OracledbLogger.debug("WS recv (data as utf8): \(text)")
                    } else {
                        OracledbLogger.debug("WS recv (data): \(data.count) bytes (non-utf8)")
                    }

                    if let text = String(data: data, encoding: .utf8), let obj = self.parseJSONString(text) {
                        OracledbLogger.debug("WS recv parsed JSON: \(obj)")
                        if let qid = obj["queryId"] as? Int {
                            OracledbLogger.debug("WS recv queryId=\(qid)")
                            self.syncQueue.async(flags: .barrier) {
                                self.messageQueue.append(obj)
                            }
                            self.processQueue(qid)
                        } else {
                            OracledbLogger.warning("Received WS binary message without queryId; ignoring")
                        }
                    } else {
                        OracledbLogger.warning("Ignoring received binary message. Failed to parse.")
                    }
                @unknown default:
                    OracledbLogger.warning("Unknown WebSocket message type received.")
                }
            }
            // Continue receiving
            self.receiveLoop()
        }
    }

    // MARK: - Connection state and delegate callbacks

    /// Starts a 20s periodic ping to keep the WebSocket connection healthy.
    private func startPingTimer() {
        stopPingTimer()
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .background))
        timer.schedule(deadline: .now() + 20, repeating: 20)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            if #available(macOS 10.15, iOS 15.0, *) {
                self.webSocketTask?.sendPing { error in
                    if let error = error {
                        OracledbLogger.error("WebSocket ping failed: \(error.localizedDescription)")
                    }
                }
            }
        }
        timer.resume()
        pingTimer = timer
    }

    /// Stops and clears the periodic ping timer.
    private func stopPingTimer() {
        pingTimer?.cancel()
        pingTimer = nil
    }

    // URLSessionWebSocketDelegate
    /// Delegate callback fired when the WebSocket handshake completes.
    /// Sets connection flags and starts keepalive ping.
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        OracledbLogger.debug("Connection with ords-baas-server established.")
        syncQueue.async(flags: .barrier) {
            self.isConnected = true
            self.webSocketConnectionInProgress = false
            self.shouldContinueReceiving = true
            self.lastReceiveErrorKey = nil
        }
        startPingTimer()
    }

    /// Delegate callback fired when the WebSocket closes.
    /// Resets connection flags and stops keepalive ping.
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        OracledbLogger.debug("Connection with ords-baas-server closed.")
        stopPingTimer()
        syncQueue.async(flags: .barrier) {
            self.isConnected = false
            self.webSocketConnectionInProgress = false
            self.shouldContinueReceiving = false
            self.lastReceiveErrorKey = nil
        }
    }

    // URLSessionTaskDelegate
    /// Delegate callback fired when the underlying URLSessionTask completes, optionally with an error.
    /// Resets connection flags and stops keepalive ping.
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            OracledbLogger.debug("Connection with ords-baas-server failed: \(error.localizedDescription)")
        }
        stopPingTimer()
        syncQueue.async(flags: .barrier) {
            self.isConnected = false
            self.webSocketConnectionInProgress = false
            self.shouldContinueReceiving = false
        }
    }

    // MARK: - URLSessionDelegate (TLS trust handling)

    /// Supports dev/test environments that use self-signed certificates, consistent with HTTP behavior.
    /// Controlled by `FusabaseOptions.allowsSelfSignedCertificates`.
    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {

        let allowsSelfSigned = oracledb.app.options.allowsSelfSignedCertificates
        if allowsSelfSigned,
           challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let serverTrust = challenge.protectionSpace.serverTrust {
            OracledbLogger.debug("WebSocket: Accepting self-signed certificate for \(challenge.protectionSpace.host)")
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }

    // MARK: - Send helpers (registration/deregistration)

    private func sendMessage(_ message: [String: Any]) {
        guard #available(macOS 10.15, iOS 15.0, *) else { return }
        // If we already encountered a terminal failure, don't keep trying to send frames.
        var continueReceiving = false
        syncQueue.sync {
            continueReceiving = self.shouldContinueReceiving
        }
        if !continueReceiving {
            OracledbLogger.warning("WebSocket send skipped: connection not available")
            return
        }
        guard let task = self.webSocketTask else {
            OracledbLogger.warning("WebSocket send skipped: no active task")
            return
        }
        guard let data = try? JSONSerialization.data(withJSONObject: message, options: []),
              let text = String(data: data, encoding: .utf8) else {
            OracledbLogger.error("Failed to serialize WebSocket message")
            return
        }
        task.send(.string(text)) { error in
            if let error = error {
                OracledbLogger.error("WebSocket send failed: \(error.localizedDescription)")
            } else {
                OracledbLogger.debug("WebSocket message sent")
            }
        }
    }

    /// Sends a registration frame for the specified queryId and payload to the server.
    func registerQueryOnServer(payload: [String: Any], queryId: Int) {
        let frame: [String: Any] = [
            "payload": payload,
            "queryId": queryId,
            "status": 1
        ]
        sendMessage(frame)
    }

    /// Sends a deregistration frame for the specified queryId and payload to the server.
    func deregisterQueryOnServer(payload: [String: Any], queryId: Int) {
        let frame: [String: Any] = [
            "payload": payload,
            "queryId": queryId,
            "status": 0
        ]
        sendMessage(frame)
    }

    // MARK: - Utilities

    private func parseJSONString(_ text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8) else { return nil }
        let obj = try? JSONSerialization.jsonObject(with: data, options: [])
        return obj as? [String: Any]
    }

    /// Retrieves the current user's bearer access token from persistence.
    /// If missing, logs a warning and returns an empty string (non-fatal).
    /// Uses secure token handling to prevent memory leaks.
    private func getAccessToken() throws -> String {
        var tokenValue = ""
        KeychainTokenStore.shared.withSecureToken(.access) { token in
            tokenValue = token
        }
        if tokenValue.isEmpty {
            OracledbLogger.warning("Empty ACCESS_TOKEN. Proceeding without WebSocket authorization.")
        }
        return tokenValue
    }

    /// Builds authorization header securely using token that gets cleared immediately after use
    private func buildAuthorizationHeader() throws -> String? {
        var authHeader: String?
        KeychainTokenStore.shared.withSecureToken(.access) { token in
            authHeader = "Bearer " + token
        }
        return authHeader
    }

    /// Retrieves the snapshot token required for WebSocket authentication.
    private func getSnapshotToken() throws -> [String: Any] {
        let options = oracledb.app.options

        // Build URL: {ordsHost}:{ordsPort}/ords/{schema}/_/baas-services/idm/onprem/{projectId}/authorizeSnapshot?apiKey={appId}
        let urlStr = options.ordsHost + ":" + options.ordsPort
            + "/ords/" + options.schema
            + QueryHelper.BAAS_SERVICE
            + QueryHelper.IDM
            + QueryHelper.ONPREM
            + "/" + options.projectId
            + QueryHelper.AUTHORIZE_SNAPSHOT
            + "?apiKey=" + options.appId

        guard let url = URL(string: urlStr) else {
            throw ControllerError.internalError("Invalid authorizeSnapshot URL")
        }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"

        // Header: Authorization with Bearer token
        guard let authHeader = try buildAuthorizationHeader() else {
            OracledbLogger.debug("Cannot retrieve accessToken. Please ensure you are logged in first in order to use Snapshot feature")
            throw ControllerError.unauthenticated("User Not logged in")
        }
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")

        // Execute synchronously (similar to QueryHelper.syncHttpRequest)
        var dataOut: Data?
        var respOut: URLResponse?
        var errOut: Error?
        let sem = DispatchSemaphore(value: 0)
        SecureNetworking.secureSession.dataTask(with: req) { data, resp, err in
            dataOut = data
            respOut = resp
            errOut = err
            sem.signal()
        }.resume()
        sem.wait()

        if let err = errOut {
            throw ControllerError.network(err.localizedDescription)
        }
        guard let data = dataOut, let resp = respOut as? HTTPURLResponse else {
            throw ControllerError.network("No response from authorizeSnapshot")
        }
        guard (200...299).contains(resp.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "<no body>"
            OracledbLogger.warning("authorizeSnapshot failed with response message \(msg)")
            throw ControllerError.internalError("authorizeSnapshot failed: \(msg)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data, options: []),
              let dict = json as? [String: Any] else {
            throw ControllerError.internalError("Invalid JSON from authorizeSnapshot")
        }

        OracledbLogger.info("authorizeSnapshot")
        return dict
    }

    /// Builds the realtime WebSocket URL based on configured ORDS host/port/schema and the provided snapshot credential.
    /// Result shape: {ws|wss}://host:port/ords/baas-realtime/{schema}?authToken={access_token}
    /// - Parameter snapshotCredential: Dictionary containing "access_token" or "accessToken".
    /// - Returns: A URL for establishing the realtime WebSocket connection or nil if invalid components.
    private func buildWebSocketURL(snapshotCredential: [String: Any]) -> URL? {
        let options = oracledb.app.options

        // Determine base scheme, host, port from options.ordsHost and options.ordsPort
        // options.ordsHost is expected to include http/https scheme, similar to QueryHelper usage.
        var base = options.ordsHost
        if !base.lowercased().hasPrefix("http") {
            base = "https://" + base
        }
        let composed = base + ":" + options.ordsPort
        guard let baseURL = URL(string: composed),
              let host = baseURL.host else {
            return nil
        }
        let isSecure = (baseURL.scheme?.lowercased() == "https")
        let wsScheme = isSecure ? "wss" : "ws"
        let port = baseURL.port

        // Build final WS URL: {ws|wss}://host:port/ords/baas-realtime/{schema}?authToken=...
        var comps = URLComponents()
        comps.scheme = wsScheme
        comps.host = host
        comps.port = port
        comps.path = Self.ORDS_REALTIME_PATH + options.schema

        var tokenValue: String = ""
        if let t = snapshotCredential["access_token"] as? String {
            tokenValue = t
        } else if let t = snapshotCredential["accessToken"] as? String {
            tokenValue = t
        }
        comps.queryItems = [ URLQueryItem(name: "authToken", value: tokenValue) ]

        return comps.url
    }
}
