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
import CryptoKit

/// Manages listeners for database references.
/// This class handles the lifecycle of listeners, including registration, removal, and notification.
class ListenerManager<K: Reference, T: Snapshot> {

    /// The database instance this manager belongs to.
    private let oradb: FusabaseOracledb

    /// The reference this manager is managing listeners for.
    private let ref: K

    /// Dictionary mapping listener IDs to their data.
    private var listeners: [Int: ListenerData<K, T>] = [:]

    /// Counter for generating unique listener IDs.
    private var listenerIdCounter = 0

    /// Serial queue for thread-safe access to listeners.
    private let queue = DispatchQueue(label: "com.oracle.database.fusabase.listenerManager")
    /// Specific-key to detect re-entrancy on our own queue (avoids deadlocks with sync).
    private let queueKey = DispatchSpecificKey<UInt8>()

    /// WebSocket controller for real-time communication.
    private let webSocketController: WebSocketController

    /// Polling controller for long polling fallback.
    private lazy var pollingController: PollingController<K, T> = {
        return PollingController(manager: self, settings: self.oradb.settings)
    }()

    /// Initializes a new listener manager.
    ///
    /// - Parameters:
    ///   - oradb: The database instance.
    ///   - ref: The reference to manage listeners for.
    init(oradb: FusabaseOracledb, ref: K) {
        self.oradb = oradb
        self.ref = ref
        self.webSocketController = WebSocketController.getInstance(oradb)
        // Mark our queue so we can detect calls made from within it and avoid sync deadlocks.
        queue.setSpecific(key: queueKey, value: 1)
    }

    /// Creates a canonical query payload for WebSocket communication.
    ///
    /// - Returns: A dictionary representing the query payload
    private func createWebSocketPayload() -> [String: Any] {
        let pathSegments = ref.path.components(separatedBy: "/")
        return [
            "path": pathSegments,
            "conditions": [],
            "explicitOrder": []
        ]
    }

    /// Computes a query ID from the canonical query payload.
    ///
    /// - Returns: The query ID as an integer hash
    private func computeQueryId() -> Int {
        let payload = createWebSocketPayload()

        // This produces a signed 32-bit int and has been observed to match ORDS WS queryId.
        let sortedPayload = sortJsonObject(payload)
        do {
            let canonicalData = try JSONSerialization.data(withJSONObject: sortedPayload, options: [.sortedKeys, .withoutEscapingSlashes])
            let canonicalStr = String(data: canonicalData, encoding: .utf8) ?? ""
            let javaHash = Self.javaStringHashCode(canonicalStr)
            OracledbLogger.debug("WS computeQueryId payload=\(canonicalStr) queryId=\(javaHash)")
            return Int(javaHash)
        } catch {
            let javaHash = Self.javaStringHashCode(ref.path)
            OracledbLogger.debug("WS computeQueryId fallback path=\(ref.path) queryId=\(javaHash)")
            return Int(javaHash)
        }
    }

    private static func javaStringHashCode(_ s: String) -> Int32 {
        var h: Int32 = 0
        // Java iterates UTF-16 code units.
        for cu in s.utf16 {
            h = Int32(bitPattern: UInt32(bitPattern: h) &* 31 &+ UInt32(cu))
        }
        return h
    }

    /// Sorts a JSON object recursively for consistent hashing.
    ///
    /// - Parameter obj: The object to sort
    /// - Returns: A sorted representation
    private func sortJsonObject(_ obj: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        for key in obj.keys.sorted() {
            if let dict = obj[key] as? [String: Any] {
                result[key] = sortJsonObject(dict)
            } else if let array = obj[key] as? [[String: Any]] {
                result[key] = array.map { sortJsonObject($0) }
            } else {
                result[key] = obj[key]
            }
        }
        return result
    }

    /// Registers a new listener for the reference.
    ///
    /// - Parameters:
    ///   - listener: The event listener to register.
    ///   - options: The options for the listener (optional).
    /// - Returns: A listener registration that can be used to remove the listener.
    func registerListener(_ listener: any EventListener<T>, options: SnapshotListenOptions? = nil) -> ListenerRegistration {
        return queue.sync {
            listenerIdCounter += 1
            let listenerId = listenerIdCounter

            // Deliver callbacks on the main thread by default. This avoids SwiftUI/Combine
            // warnings like "Publishing changes from background threads is not allowed"
            // when app code updates @Published / UI state from snapshot listeners.
            let executor = MainThreadExecutor()
            let metadataChanges = options?.metadataChanges ?? .exclude

            let listenerData = ListenerData(
                listener: listener,
                ref: ref,
                listenerId: listenerId,
                manager: self,
                executor: executor,
                metadataChanges: metadataChanges
            )

            listeners[listenerId] = listenerData

            // Start listening for changes if this is the first listener
            let queryId = computeQueryId()
            let useSocket = oradb.app.options.useSocket

            if useSocket {
                // WebSocket mode
                startWebSocketListening(for: listenerData, queryId: queryId)
            } else {
                // Long polling mode
                startPollingListening(for: listenerData)
            }

            return listenerData.getListenerRegistration()
        }
    }

    /// Removes a listener by its data.
    ///
    /// - Parameter listenerData: The listener data to remove.
    func removeListener(_ listenerData: ListenerData<K, T>) {
        queue.async {
            self.listeners.removeValue(forKey: listenerData.getListenerId())

            // Stop listening if this was the last listener
            let queryId = self.computeQueryId()
            let useSocket = self.oradb.app.options.useSocket

            if useSocket {
                // WebSocket mode - deregister query
                self.webSocketController.deregisterQuery(queryId, listenerData: listenerData)

                if self.webSocketController.shouldDeregisterQuery(queryId) {
                    let payload = self.createWebSocketPayload()
                    self.webSocketController.deregisterQueryOnServer(payload: payload, queryId: queryId)
                }

                if self.webSocketController.shouldCloseConnection() {
                    self.webSocketController.closeWebSocketConnection()
                }
            } else {
                // Long polling mode - update polling controller
                self.pollingController.listenersUpdated()
            }
        }
    }

    /// Removes all listeners.
    func removeAllListeners() {
        queue.async {
            let useSocket = self.oradb.app.options.useSocket

            if useSocket {
                // WebSocket mode - close connection if no more listeners
                if self.webSocketController.shouldCloseConnection() {
                    self.webSocketController.closeWebSocketConnection()
                }
            } else {
                // Long polling mode - stop polling
                self.pollingController.listenersUpdated()
            }

            self.listeners.removeAll()
        }
    }

    /// Notifies all registered listeners of a change.
    ///
    /// - Parameters:
    ///   - snapshot: The new snapshot.
    ///   - error: Any error that occurred.
    func notifyListeners(snapshot: T?, error: Error?) {
        queue.async {
            for listenerData in self.listeners.values {
                listenerData.executeListener(snapshot, error)
            }
        }
    }

    /// Gets the number of active listeners.
    ///
    /// - Returns: The number of listeners.
    func listenerCount() -> Int {
        // If we're already on our serial queue, avoid sync {} to prevent deadlock.
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            return listeners.count
        } else {
            return queue.sync { listeners.count }
        }
    }

    /// Returns a thread-safe snapshot copy of all registered listeners.
    /// This avoids exposing internal storage while allowing pollers to iterate safely.
    func allListenersSnapshot() -> [ListenerData<K, T>] {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            return Array(listeners.values)
        } else {
            return queue.sync { Array(listeners.values) }
        }
    }

    /// Starts WebSocket listening for the given listener data.
    ///
    /// - Parameters:
    ///   - listenerData: The listener data to start listening for
    ///   - queryId: The query ID for this listener
    private func startWebSocketListening(for listenerData: ListenerData<K, T>, queryId: Int) {
        // Establish WebSocket connection if not already connected
        // If WS can't be established (e.g. user not logged in / token missing), fall back to polling.
        if !webSocketController.establishWebSocketConnection() {
            OracledbLogger.warning("WebSocket connection not available; falling back to long polling")
            startPollingListening(for: listenerData)
            return
        }

        // Only the first local listener for a canonical query should subscribe
        // on the server. Additional listeners share that server subscription.
        let shouldSubscribeOnServer = webSocketController.shouldDeregisterQuery(queryId)

        webSocketController.registerQueryWithController(queryId, listenerData: listenerData)

        if shouldSubscribeOnServer {
            let payload = createWebSocketPayload()
            webSocketController.registerQueryOnServer(payload: payload, queryId: queryId)
        } else {
            webSocketController.putRegistrationSuccessMessage(queryId)
            webSocketController.processQueue(queryId)
        }
    }

    /// Starts polling listening for the given listener data.
    ///
    /// - Parameter listenerData: The listener data to start listening for
    private func startPollingListening(for listenerData: ListenerData<K, T>) {
        // Fetch initial snapshot and notify listener
        if #available(macOS 10.15, iOS 15.0, *) {
            Task {
                do {
                    if let docRef = listenerData.getReference() as? DocumentReference {
                        let snapshot = try await docRef.getDocument()
                        listenerData.executeListener(snapshot, nil)
                    } else if let query = listenerData.getReference() as? Query {
                        let snapshot = try await query.getDocuments()
                        listenerData.executeListener(snapshot, nil)
                    } else {
                        listenerData.executeListener(nil, NSError(domain: "ListenerManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unsupported reference type for initial snapshot"]))
                    }
                } catch {
                    listenerData.executeListener(nil, error)
                }

                // Start polling
                pollingController.listenersUpdated()
            }
        } else {
            listenerData.executeListener(nil, NSError(domain: "ListenerManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Async operations require macOS 10.15+/iOS 15+"]))
            pollingController.listenersUpdated()
        }
    }
}
