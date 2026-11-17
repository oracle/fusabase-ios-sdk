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
import Network
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
    func isAnyActive() -> Bool
    func beginAnyInitialRemoteSnapshotLoad() -> Bool
    func clearAnyInitialRemoteSnapshotLoad()
    func deactivateAny()
    func removeAnyRegistration()
    func resetAnyRealtimeBaseline()
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
    func isAnyActive() -> Bool { isActive() }
    func beginAnyInitialRemoteSnapshotLoad() -> Bool { beginInitialRemoteSnapshotLoad() }
    func clearAnyInitialRemoteSnapshotLoad() { clearInitialRemoteSnapshotLoad() }
    func deactivateAny() { deactivate() }
    func removeAnyRegistration() { getListenerRegistration().remove() }
    func resetAnyRealtimeBaseline() { resetRealtimeBaseline() }
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
    private var messageQueueBytes = 0
    private static let maxQueuedMessageCount = 1000
    private static let maxQueuedMessageBytes = 1024 * 1024
    /// Outbound frames collected while URLSession is still completing the WebSocket handshake.
    private var pendingOutboundMessages: [[String: Any]] = []
    /// Map of queryId to registered listeners. Protected by syncQueue.
    private var registeredQuery: [Int: [AnyListenerData]] = [:]
    private var registrationPayloads: [Int: [String: Any]] = [:]
    private var retryAttempt = 0
    private var retryWorkItem: DispatchWorkItem?
    private var closingByClient = false
    private var authListenerHandle: NSObjectProtocol?
    private var authenticatedUID: String?
    private let pathMonitor = NWPathMonitor()
    private let pathMonitorQueue = DispatchQueue(label: "com.oracle.fusabase.realtime.network")
    private var networkAvailable = true

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
    /// Incoming frames must not be handled from the URLSession/state queue: message
    /// handling reads the controller state synchronously to take a listener snapshot.
    private let inboundMessageQueue = DispatchQueue(label: "com.oracle.database.fusabase.websocket.inbound")

    // MARK: - Init

    private init(oracledb: FusabaseOracledb) {
        self.oracledb = oracledb
        super.init()
        // Observe the already-configured auth singleton; never replace it while installing
        // a database listener, since doing so would discard existing auth state/listeners.
        let auth = FusabaseAuth.auth()
        authenticatedUID = auth.currentUser?.uid
        authListenerHandle = auth.addIDTokenDidChangeListener { [weak self] _, user in
            self?.handleAuthStateChange(user?.uid)
        }
        pathMonitor.pathUpdateHandler = { [weak self] path in
            self?.syncQueue.async(flags: .barrier) {
                guard let self else { return }
                self.networkAvailable = path.status == .satisfied
                if self.networkAvailable { self.scheduleReconnectIfNeeded() }
                else { self.retryWorkItem?.cancel(); self.retryWorkItem = nil }
            }
        }
        pathMonitor.start(queue: pathMonitorQueue)
        OracledbLogger.info("Initialized")
    }

    private func handleAuthStateChange(_ uid: String?) {
        syncQueue.async(flags: .barrier) {
            guard self.authenticatedUID != uid else { return }
            self.authenticatedUID = uid
            let listeners = self.registeredQuery.values.flatMap { $0 }
            self.registeredQuery.removeAll()
            self.registrationPayloads.removeAll()
            self.messageQueue.removeAll()
            self.messageQueueBytes = 0
            self.retryWorkItem?.cancel()
            self.retryWorkItem = nil
            self.closingByClient = true
            // Deactivation prevents a stale in-flight callback; removal also updates the
            // owning ListenerManager so it cannot retain an invalid auth-session listener.
            for listener in listeners {
                listener.deactivateAny()
                listener.removeAnyRegistration()
            }
            self.webSocketTask?.cancel(with: .goingAway, reason: nil)
            self.webSocketTask = nil
            self.session?.invalidateAndCancel()
            self.session = nil
        }
    }

    // MARK: - Public registration API

    /// Registers a query listener with the WebSocket controller.
    ///
    /// - Parameters:
    ///   - queryId: The ID of the query to register
    ///   - listenerData: The listener data to register
    func registerQueryWithController<K: Reference, T: Snapshot>(_ queryId: Int, listenerData: ListenerData<K, T>) {
        // Registration must complete before a server acknowledgement can be
        // processed; otherwise the `success` frame has no local listener to
        // initialize and is discarded.
        syncQueue.sync(flags: .barrier) {
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
        syncQueue.sync(flags: .barrier) {
            self.enqueueMessage(message)
        }
    }

    // MARK: - WebSocket lifecycle

    /// Establishes a WebSocket connection for real-time updates.
    /// Retrieves authentication token and connects to the ORDS real-time service.
    /// - Returns: true if a connection attempt was initiated or already exists; false if WebSocket
    ///            cannot be used (e.g. missing auth token, authorizeSnapshot failure, unsupported OS).
    @discardableResult
    func establishWebSocketConnection() -> Bool {
        var shouldStartConnection = false
        syncQueue.sync(flags: .barrier) {
            if !self.isConnected && !self.webSocketConnectionInProgress {
                self.webSocketConnectionInProgress = true
                shouldStartConnection = true
            }
        }
        if !shouldStartConnection {
            logger.debug("WebSocket connection already established or connecting")
            return true
        }

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

        logger.info("Created WS URI \(wsURL.scheme ?? "ws")://\(wsURL.host ?? "<unknown>")\(wsURL.path)")

        if #available(macOS 10.15, iOS 15.0, *) {
            let config = SecureNetworking.secureDefaultConfiguration()
            // No cookies or persistent caches for WS
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            self.session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
            self.webSocketTask = self.session?.webSocketTask(with: wsURL)
            syncQueue.sync(flags: .barrier) {
                self.shouldContinueReceiving = true
                self.lastReceiveErrorKey = nil
            }
            self.webSocketTask?.resume()
            logger.info("WebSocket connection attempt started")

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
        closingByClient = true
        retryWorkItem?.cancel()
        retryWorkItem = nil
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
                self.pendingOutboundMessages.removeAll()
                self.messageQueue.removeAll()
                self.messageQueueBytes = 0
            }
            logger.debug("Connection with ords-baas-server closed.")
        }
    }

    // MARK: - Message handling

    /// JSONSerialization represents ORDS JSON numbers as NSNumber on some
    /// Apple runtime paths. Normalize the wire value before using it as a
    /// dictionary key, otherwise a valid registration acknowledgement can be
    /// ignored even when its printed value looks like an Int.
    private func messageQueryId(_ message: [String: Any]) -> Int? {
        if let queryId = message["queryId"] as? Int {
            return queryId
        }
        if let queryId = message["queryId"] as? NSNumber {
            return queryId.intValue
        }
        return nil
    }

    /// Enqueues an inbound frame while bounding memory used before the initial server snapshot.
    private func enqueueMessage(_ message: [String: Any]) {
        let bytes = (try? JSONSerialization.data(withJSONObject: message).count) ?? 0
        guard bytes <= Self.maxQueuedMessageBytes,
              messageQueue.count < Self.maxQueuedMessageCount,
              messageQueueBytes + bytes <= Self.maxQueuedMessageBytes else {
            if let queryId = messageQueryId(message) {
                let error = ControllerError.internalError("Realtime initial snapshot event queue limit exceeded.")
                for listener in registeredQuery[queryId] ?? [] { listener.executeAny(nil, error) }
            }
            return
        }
        messageQueue.append(message)
        messageQueueBytes += bytes
    }

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
                if let mid = self.messageQueryId(msg), mid == queryId {
                    toProcess.append(msg)
                    self.messageQueueBytes -= (try? JSONSerialization.data(withJSONObject: msg).count) ?? 0
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
        guard let queryId = messageQueryId(messageObject) else {
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
                if listenerData.anyPreviousResult == nil && listenerData.beginAnyInitialRemoteSnapshotLoad() {
                    fetchAndEmitInitialSnapshot(for: listenerData, queryId: queryId)
                }
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
                        // Keep notification ordering deterministic while the first
                        // server snapshot is loading.
                        syncQueue.sync(flags: .barrier) { self.enqueueMessage(messageObject) }
                        queued = true
                    }
                    continue
                }

                applyNotificationDelta(messageObject, to: listenerData)
            }
        }
    }

    // MARK: - Snapshot helpers

    private func fetchAndEmitInitialSnapshot(for listenerData: AnyListenerData, queryId: Int) {
        if #available(macOS 10.15.0, iOS 15.0, *) {
            Task.detached { [weak self] in
                guard let self = self, listenerData.isAnyActive() else { return }
                do {
                    if let docRef = listenerData.anyReference as? DocumentReference {
                        let snap = try await docRef.getDocument(source: .server, snapshot: true)
                        guard listenerData.isAnyActive() else { return }
                        listenerData.executeAny(snap, nil)
                        // Process any queued notifications now that initial snapshot exists
                        self.processQueue(queryId)
                    } else if let query = listenerData.anyReference as? Query {
                        let snap = try await query.getDocuments(source: .server, snapshot: true)
                        guard listenerData.isAnyActive() else { return }
                        listenerData.executeAny(snap, nil)
                        self.processQueue(queryId)
                    } else {
                        listenerData.executeAny(nil, ControllerError.internalError("Unsupported reference type for initial snapshot"))
                    }
                } catch {
                    listenerData.clearAnyInitialRemoteSnapshotLoad()
                    listenerData.executeAny(nil, error)
                }
            }
        } else {
            listenerData.executeAny(nil, ControllerError.internalError("Async initial fetch requires macOS 10.15+/iOS 15+"))
        }
    }

    /// Applies ORDS `changedData` directly to the last delivered snapshot, matching Android's
    /// realtime path and avoiding a second HTTP read for every socket notification.
    private func applyNotificationDelta(_ message: [String: Any], to listenerData: AnyListenerData) {
        guard listenerData.isAnyActive(), let previous = listenerData.anyPreviousResult else { return }
        guard message["rowId"] != nil, message["changedData"] != nil else {
            listenerData.executeAny(nil, ControllerError.internalError("Invalid response received from BAAS Server"))
            return
        }
        do {
            if let ref = listenerData.anyReference as? DocumentReference,
               let snapshot = previous as? DocumentSnapshot {
                guard let next = try notificationDocument(message, reference: ref, previous: snapshot) else { return }
                listenerData.executeAny(next, nil)
            } else if let query = listenerData.anyReference as? Query,
                      let snapshot = previous as? QuerySnapshot {
                guard let next = try notificationQuery(message, query: query, previous: snapshot) else { return }
                listenerData.executeAny(next, nil)
            } else {
                listenerData.executeAny(nil, ControllerError.internalError("Unsupported reference type for change notification"))
            }
        } catch {
            listenerData.executeAny(nil, error)
        }
    }

    private func notificationDocument(_ message: [String: Any], reference: DocumentReference,
                                      previous: DocumentSnapshot) throws -> DocumentSnapshot? {
        let rowId = message["rowId"] as? String ?? ""
        var notificationMetadata = (message["_metadata"] as? [String: Any])
            ?? (message["metadata"] as? [String: Any])
            ?? [:]
        guard var changed = message["changedData"] as? [String: Any] else {
            throw ControllerError.internalError("Invalid changedData payload")
        }
        // ORDS collection notifications use DOCUMENT, while relational-style
        // envelopes use DATA. Both contain the actual changed fields and may
        // carry OID/etag metadata inside the nested object.
        if let document = changed["DOCUMENT"] as? [String: Any] {
            changed = document
        } else if let data = changed["DATA"] as? [String: Any] {
            changed = data
        }
        if let nestedMetadata = changed["_metadata"] as? [String: Any] {
            notificationMetadata.merge(nestedMetadata) { _, nested in nested }
        }
        let version = String(describing: message["VERSION"] ?? message["version"] ?? notificationMetadata["VERSION"] ?? notificationMetadata["etag"] ?? "")
        if !previous.realtimeRowID().isEmpty && previous.realtimeRowID() != rowId { return nil }
        if !previous.realtimeVersion().isEmpty && !version.isEmpty && compareVersion(previous.realtimeVersion(), version) > 0 { return nil }
        let operations = (message["operations"] as? [Any])?.compactMap { $0 as? String } ?? ["UPDATE"]
        let operation = (operations.last ?? "UPDATE").uppercased()
        if operation == "DELETE" {
            return DocumentSnapshot(data: nil, docRef: reference, exists: false)
        }
        // ORDS may emit only changed fields. Merge them into the authoritative baseline,
        // recursively for nested maps, before materializing the next snapshot.
        var data = previous.data() ?? [:]
        merge(changed, into: &data)
        data["OID"] = data["OID"] ?? message["OID"] ?? notificationMetadata["OID"] ?? reference.documentID
        data["ROWID"] = rowId
        data["VERSION"] = version
        data["LAST_MODIFIED"] = message["LAST_MODIFIED"] ?? notificationMetadata["LAST_MODIFIED"] ?? data["LAST_MODIFIED"] ?? ""
        data["CREATED"] = message["CREATED"] ?? notificationMetadata["CREATED"] ?? data["CREATED"] ?? ""
        return DocumentSnapshot(data: data, docRef: reference)
    }

    private func merge(_ changed: [String: Any], into target: inout [String: Any]) {
        for (key, value) in changed {
            if value is NSNull {
                target.removeValue(forKey: key)
            } else if let nested = value as? [String: Any], var existing = target[key] as? [String: Any] {
                merge(nested, into: &existing)
                target[key] = existing
            } else {
                target[key] = value
            }
        }
    }

    private func compareVersion(_ lhs: String, _ rhs: String) -> Int {
        // ORDS collection notifications use numeric VERSION values, while
        // relational notifications use opaque hexadecimal etags. Only numeric
        // values have an ordering relationship; treating digit runs inside an
        // etag as a version incorrectly discards valid updates as stale.
        let numericVersion = CharacterSet(charactersIn: "0123456789.")
        guard !lhs.isEmpty, !rhs.isEmpty,
              lhs.unicodeScalars.allSatisfy(numericVersion.contains),
              rhs.unicodeScalars.allSatisfy(numericVersion.contains) else {
            return lhs == rhs ? 0 : -1
        }
        let left = lhs.split(whereSeparator: { !$0.isNumber }).compactMap { UInt64($0) }
        let right = rhs.split(whereSeparator: { !$0.isNumber }).compactMap { UInt64($0) }
        if !left.isEmpty || !right.isEmpty {
            for index in 0..<max(left.count, right.count) {
                let l = index < left.count ? left[index] : 0
                let r = index < right.count ? right[index] : 0
                if l != r { return l < r ? -1 : 1 }
            }
            return 0
        }
        return lhs == rhs ? 0 : (lhs < rhs ? -1 : 1)
    }

    private func notificationQuery(_ message: [String: Any], query: Query,
                                   previous: QuerySnapshot) throws -> QuerySnapshot? {
        let rowId = message["rowId"] as? String ?? ""
        let operation = ((message["operations"] as? [String])?.last ?? "UPDATE").uppercased()
        var documents = previous.documents
        let existingIndex = documents.firstIndex { $0.realtimeRowID() == rowId }
        if operation == "DELETE" {
            guard let existingIndex else { return nil }
            documents.remove(at: existingIndex)
        } else {
            let notificationMetadata = (message["_metadata"] as? [String: Any])
                ?? (message["metadata"] as? [String: Any])
                ?? [:]
            let changedData = message["changedData"] as? [String: Any] ?? [:]
            let nestedData = (changedData["DOCUMENT"] as? [String: Any])
                ?? (changedData["DATA"] as? [String: Any])
                ?? changedData
            let nestedMetadata = nestedData["_metadata"] as? [String: Any] ?? [:]
            let objectID = (changedData["OID"] as? String)
                ?? (nestedData["OID"] as? String)
                ?? (message["OID"] as? String)
                ?? (notificationMetadata["OID"] as? String)
                ?? (nestedMetadata["OID"] as? String)
                ?? existingIndex.map { documents[$0].documentID }
            guard let objectID, !objectID.isEmpty else {
                throw ControllerError.internalError("Realtime notification is missing OID")
            }
            let ref = DocumentReference(oracledb: query.oracledb, path: query.path + "/" + objectID)
            guard let changed = try notificationDocument(message, reference: ref,
                                                      previous: existingIndex.map { documents[$0] }
                                                        ?? DocumentSnapshot(data: nil, docRef: ref, exists: false)) else { return nil }
            // DocumentSnapshot.data() intentionally exposes only user fields.
            // Preserve ORDS realtime identity in the raw materialized input so
            // a later UPDATE or DELETE (which identifies the row only by rowId)
            // can find this document again.
            var nextData = changed.data() ?? [:]
            nextData["OID"] = objectID
            nextData["ROWID"] = changed.realtimeRowID()
            nextData["VERSION"] = changed.realtimeVersion()
            let next = QueryDocumentSnapshot(data: nextData, docRef: ref)
            if let existingIndex { documents[existingIndex] = next } else { documents.append(next) }
        }
        documents = order(documents, for: query)
        let next = QuerySnapshot(snaps: documents, query: query,
                                 metadata: SnapshotMetadata(fromCache: false, hasPendingWrites: false),
                                 previous: previous)
        return next.documentChanges().isEmpty ? nil : next
    }

    private func reconcile(_ documents: [QueryDocumentSnapshot], for query: Query) -> [QueryDocumentSnapshot] {
        var result = documents.filter { snapshot in
            query.filterArr.allSatisfy { matches(snapshot.get($0.field), filter: $0) }
        }
        if !query.orderArr.isEmpty {
            result.sort { lhs, rhs in
                for order in query.orderArr {
                    let comparison = compare(lhs.get(order.field), rhs.get(order.field))
                    if comparison != 0 { return order.direction.lowercased() == "desc" ? comparison > 0 : comparison < 0 }
                }
                return lhs.documentID < rhs.documentID
            }
        }
        return query.limit > 0 ? Array(result.prefix(query.limit)) : result
    }

    /// Realtime membership is server-owned; ordering is applied locally so document
    /// changes expose correct old/new indexes without re-fetching the query.
    private func order(_ documents: [QueryDocumentSnapshot], for query: Query) -> [QueryDocumentSnapshot] {
        guard !query.orderArr.isEmpty else { return documents }
        return documents.sorted { lhs, rhs in
            for order in query.orderArr {
                let comparison = compare(lhs.get(order.field), rhs.get(order.field))
                if comparison != 0 {
                    return order.direction.lowercased() == "desc" ? comparison > 0 : comparison < 0
                }
            }
            return lhs.documentID < rhs.documentID
        }
    }

    private func matches(_ actual: Any?, filter: Filter) -> Bool {
        switch filter.op.lowercased() {
        case "==": return equal(actual, filter.value)
        case "!=": return !equal(actual, filter.value)
        case ">": return compare(actual, filter.value) > 0
        case ">=": return compare(actual, filter.value) >= 0
        case "<": return compare(actual, filter.value) < 0
        case "<=": return compare(actual, filter.value) <= 0
        case "in": return (filter.value as? [Any])?.contains { equal(actual, $0) } ?? false
        case "not-in": return !((filter.value as? [Any])?.contains { equal(actual, $0) } ?? false)
        case "array-contains": return (actual as? [Any])?.contains { equal($0, filter.value) } ?? false
        case "array-contains-any":
            guard let values = filter.value as? [Any], let array = actual as? [Any] else { return false }
            return array.contains { item in values.contains { equal(item, $0) } }
        case "like":
            guard let value = actual as? String, let pattern = filter.value as? String else { return false }
            let escaped = NSRegularExpression.escapedPattern(for: pattern).replacingOccurrences(of: "%", with: ".*").replacingOccurrences(of: "_", with: ".")
            return value.range(of: "^\(escaped)$", options: .regularExpression) != nil
        case "is null": return actual == nil || actual is NSNull
        default: return false
        }
    }

    private func equal(_ lhs: Any?, _ rhs: Any?) -> Bool { compare(lhs, rhs) == 0 }

    private func compare(_ lhs: Any?, _ rhs: Any?) -> Int {
        if lhs == nil { return rhs == nil ? 0 : -1 }
        if rhs == nil { return 1 }
        if let l = lhs as? NSNumber, let r = rhs as? NSNumber { return l.doubleValue == r.doubleValue ? 0 : (l.doubleValue < r.doubleValue ? -1 : 1) }
        let l = String(describing: lhs!), r = String(describing: rhs!)
        return l == r ? 0 : (l < r ? -1 : 1)
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
                // URLSession does not always invoke didClose/didComplete for a
                // transport-level receive failure. Schedule here as well so a
                // new short-lived authorizeSnapshot ticket is fetched and all
                // active registrations are replayed.
                self.scheduleReconnectIfNeeded()
                return
            case .success(let message):
                switch message {
                case .string(let text):
                    OracledbLogger.debug("WS recv (string): \(text)")
                    if let obj = self.parseJSONString(text) {
                        OracledbLogger.debug("WS recv parsed JSON: \(obj)")
                        if let qid = self.messageQueryId(obj) {
                            OracledbLogger.debug("WS recv queryId=\(qid)")
                            // Process an incoming frame immediately. Change frames received
                            // before the baseline are retained by processMessage itself.
                            // A second enqueue/drain hop can race and lose `success`, which
                            // prevents the initial snapshot callback from being delivered.
                            self.inboundMessageQueue.async { [weak self] in
                                self?.processMessage(obj)
                            }
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
                        if let qid = self.messageQueryId(obj) {
                            OracledbLogger.debug("WS recv queryId=\(qid)")
                            self.inboundMessageQueue.async { [weak self] in
                                self?.processMessage(obj)
                            }
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

    // Reuse the app-configured trust policy while retaining WebSocket lifecycle callbacks.
    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let delegate = SecureNetworking.secureSession.delegate,
              let handleChallenge = delegate.urlSession(_:didReceive:completionHandler:) else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        handleChallenge(session, challenge, completionHandler)
    }

    // URLSessionWebSocketDelegate
    /// Delegate callback fired when the WebSocket handshake completes.
    /// Sets connection flags and starts keepalive ping.
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        OracledbLogger.info("Connection with ords-baas-server established.")
        syncQueue.async(flags: .barrier) {
            self.isConnected = true
            self.webSocketConnectionInProgress = false
            self.shouldContinueReceiving = true
            self.lastReceiveErrorKey = nil
            self.closingByClient = false
            self.retryAttempt = 0

            // A reconnect cannot assume the server will replay every missed frame.
            // Require a new initial server snapshot for every active listener.
            for listeners in self.registeredQuery.values {
                for listener in listeners { listener.resetAnyRealtimeBaseline() }
            }

            let pending = self.pendingOutboundMessages
            self.pendingOutboundMessages.removeAll()
            if !pending.isEmpty {
                OracledbLogger.debug("Flushing \(pending.count) queued WebSocket message(s)")
                DispatchQueue.global(qos: .utility).async {
                    for message in pending {
                        self.sendFrame(message, using: webSocketTask)
                    }
                }
            } else {
                // On reconnect there are no handshake-queued frames, so replay
                // each active subscription exactly once. On a first connection,
                // `pending` already contains the subscribe frame; replaying it
                // would cause ORDS to report "Query already subscribed".
                let frames = self.registrationPayloads.map { queryId, payload in
                    ["payload": payload, "queryId": queryId, "status": 1] as [String: Any]
                }
                DispatchQueue.global(qos: .utility).async {
                    for frame in frames {
                        self.sendFrame(frame, using: webSocketTask)
                    }
                }
            }
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
            self.pendingOutboundMessages.removeAll()
        }
        scheduleReconnectIfNeeded()
    }

    // URLSessionTaskDelegate
    /// Delegate callback fired when the underlying URLSessionTask completes, optionally with an error.
    /// Resets connection flags and stops keepalive ping.
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            OracledbLogger.error("Connection with ords-baas-server failed: \(error.localizedDescription)")
        }
        stopPingTimer()
        syncQueue.async(flags: .barrier) {
            self.isConnected = false
            self.webSocketConnectionInProgress = false
            self.shouldContinueReceiving = false
            self.pendingOutboundMessages.removeAll()
        }
        scheduleReconnectIfNeeded()
    }

    /// Android-compatible jittered exponential reconnect while listeners remain registered.
    private func scheduleReconnectIfNeeded() {
        syncQueue.async(flags: .barrier) {
            guard self.networkAvailable, !self.closingByClient, !self.registeredQuery.isEmpty, self.retryWorkItem == nil else { return }
            self.retryAttempt += 1
            let cap = min(30.0, pow(2.0, Double(min(self.retryAttempt - 1, 4))))
            let delay = Double.random(in: max(0.5, cap / 2)...cap)
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.syncQueue.async(flags: .barrier) { self.retryWorkItem = nil }
                _ = self.establishWebSocketConnection()
            }
            self.retryWorkItem = work
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay, execute: work)
        }
    }

    // MARK: - Send helpers (registration/deregistration)

    private func sendMessage(_ message: [String: Any]) {
        guard #available(macOS 10.15, iOS 15.0, *) else { return }
        var action: SendAction = .skip("connection not available")
        syncQueue.sync(flags: .barrier) {
            if self.isConnected {
                if let task = self.webSocketTask {
                    action = .send(task)
                } else {
                    action = .skip("no active task")
                }
            } else if self.webSocketConnectionInProgress {
                self.pendingOutboundMessages.append(message)
                action = .queued
            } else if !self.shouldContinueReceiving {
                action = .skip("connection not available")
            } else {
                action = .skip("connection not open")
            }
        }

        switch action {
        case .send(let task):
            sendFrame(message, using: task)
        case .queued:
            OracledbLogger.debug("WebSocket send queued until connection opens")
        case .skip(let reason):
            OracledbLogger.warning("WebSocket send skipped: \(reason)")
            return
        }
    }

    @available(macOS 10.15, iOS 15.0, *)
    private enum SendAction {
        case send(URLSessionWebSocketTask)
        case queued
        case skip(String)
    }

    @available(macOS 10.15, iOS 15.0, *)
    private func sendFrame(_ message: [String: Any], using task: URLSessionWebSocketTask) {
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
        // This method is also called by the socket-open replay block, which
        // already runs on syncQueue. Do not synchronously re-enter that queue.
        syncQueue.async(flags: .barrier) { self.registrationPayloads[queryId] = payload }
        let frame: [String: Any] = [
            "payload": payload,
            "queryId": queryId,
            "status": 1
        ]
        sendMessage(frame)
    }

    /// Sends a deregistration frame for the specified queryId and payload to the server.
    func deregisterQueryOnServer(payload: [String: Any], queryId: Int) {
        syncQueue.async(flags: .barrier) { self.registrationPayloads.removeValue(forKey: queryId) }
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
            guard !token.isEmpty else { return }
            authHeader = "Bearer " + token
        }
        return authHeader
    }

    private func getSnapshotToken(forAuthPath authPath: String) throws -> [String: Any] {
        let options = oracledb.app.options

        // Build URL from the ORDS base exactly as configured.
        let normalizedAuthPath = authPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let urlStr = options.ordsBaseURL
            + "_/baas-services/idm/"
            + normalizedAuthPath
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
            OracledbLogger.warning("authorizeSnapshot for \(authPath) failed with response message \(msg)")
            throw ControllerError.internalError("authorizeSnapshot failed: \(msg)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data, options: []),
              let dict = json as? [String: Any] else {
            throw ControllerError.internalError("Invalid JSON from authorizeSnapshot")
        }

        OracledbLogger.info("authorizeSnapshot for \(authPath)")
        return dict
    }

    private func getBaseSnapshotToken() throws -> [String: Any] {
        try getSnapshotToken(forAuthPath: QueryHelper.ONPREM)
    }

    private func getIDCSSnapshotToken() throws -> [String: Any] {
        try getSnapshotToken(forAuthPath: QueryHelper.IDCS)
    }

    /// Retrieves the snapshot token required for WebSocket authentication.
    private func getSnapshotToken() throws -> [String: Any] {
        if oracledb.app.options.authType == "idcs" {
            return try getIDCSSnapshotToken()
        }
        return try getBaseSnapshotToken()
    }

    /// Builds the realtime WebSocket URL from the configured ORDS base and the
    /// provided snapshot credential.
    /// - Parameter snapshotCredential: Dictionary containing "access_token" or "accessToken".
    /// - Returns: A URL for establishing the realtime WebSocket connection or nil if invalid components.
    private func buildWebSocketURL(snapshotCredential: [String: Any]) -> URL? {
        let options = oracledb.app.options

        guard let baseURL = URL(string: options.ordsBaseURL),
              let host = baseURL.host else {
            return nil
        }
        let isSecure = (baseURL.scheme?.lowercased() == "https")
        let wsScheme = isSecure ? "wss" : "ws"
        let port = baseURL.port

        // The configured base normally ends in `/ords/{schema}/`. Reuse that
        // path's schema segment instead of reading the separate `schema` config.
        let pathSegments = baseURL.path.split(separator: "/").map(String.init)
        guard let ordsIndex = pathSegments.firstIndex(of: "ords"),
              pathSegments.indices.contains(ordsIndex + 1) else {
            return nil
        }
        let configuredSchema = pathSegments[ordsIndex + 1]

        // Build final WS URL: {ws|wss}://host:port/ords/baas-realtime/{configuredSchema}?authToken=...
        var comps = URLComponents()
        comps.scheme = wsScheme
        comps.host = host
        comps.port = port
        comps.path = Self.ORDS_REALTIME_PATH + configuredSchema

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
