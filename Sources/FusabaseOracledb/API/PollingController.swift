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

/**
 * Controller responsible for managing long polling operations for database listeners.
 *
 * This class handles the polling mechanism when WebSocket connections are not available
 * or preferred. It periodically polls the database for changes and notifies registered
 * listeners when data updates occur. The polling interval and behavior can be configured
 * to balance between real-time updates and resource usage.
 *
 * The controller consults the ListenerManager for active listeners. For each listener,
 * it fetches the latest data from the server and delivers an event only when a change
 * is detected compared to the previous result kept by ListenerData.
 *
 * Notes:
 * - Polling is implemented for:
 *   - DocumentReference -> DocumentSnapshot
 *   - Query -> QuerySnapshot
 * - Updates are emitted only when resultHasUpdated detects changes in the document
 *   data (for DocumentSnapshot) or in the set/content of documents (for QuerySnapshot).
 */
final class PollingController<K: Reference, T: Snapshot> {

    // MARK: - Types

    enum PollingControllerError: Error {
        case unsupportedReferenceType(String)
        case internalError(String)
    }

    // MARK: - Constants

    /// Polling interval in seconds between database checks (from settings)
    private let pollingInterval: TimeInterval

    // MARK: - Properties

    /// The listener manager that coordinates listener registrations
    private weak var listenerManager: ListenerManager<K, T>?

    /// GCD timer for periodic polling
    private var timer: DispatchSourceTimer?

    /// Flag indicating whether polling is currently active
    private var isPolling: Bool = false

    /// Logger
    private let logger = FusabaseLogger(category: "PollingController")

    // MARK: - Init

    /// Constructs a new PollingController with the specified listener manager and settings.
    ///
    /// - Parameters:
    ///   - manager: The ListenerManager that coordinates listener operations
    ///   - settings: The database settings containing polling configuration
    init(manager: ListenerManager<K, T>, settings: FusabaseOracledbSettings) {
        self.listenerManager = manager
        self.pollingInterval = TimeInterval(settings.longPollingTimeout) / 1000.0  // Convert ms to seconds
        logger.info("Initialized with polling interval: \(self.pollingInterval)s")
    }

    // MARK: - Listener count hook

    /// Called when the listener count changes. Automatically starts or stops polling
    /// based on whether there are active listeners.
    func listenersUpdated() {
        logger.info("listenersUpdated()")
        guard let manager = self.listenerManager else {
            stopPolling()
            return
        }
        if manager.listenerCount() > 0 {
            startPolling()
        } else {
            stopPolling()
        }
    }

    // MARK: - Polling lifecycle

    /// Starts the polling process by scheduling periodic database checks.
    /// The polling runs at fixed intervals defined by POLLING_INTERVAL.
    private func startPolling() {
        if isPolling { return }
        logger.info("Polling started")

        isPolling = true

        let queue = DispatchQueue(label: "com.oracle.database.fusabase.polling", qos: .background)
        let newTimer = DispatchSource.makeTimerSource(queue: queue)
        newTimer.schedule(deadline: .now(), repeating: self.pollingInterval)
        newTimer.setEventHandler { [weak self] in
            self?.poll()
        }
        newTimer.resume()
        self.timer = newTimer
    }

    /// Stops the polling process and cancels the scheduler.
    /// This method should be called when there are no more active listeners.
    private func stopPolling() {
        guard isPolling else { return }
        logger.info("Polling stopping")
        isPolling = false
        timer?.cancel()
        timer = nil
    }

    // MARK: - Update detection

    /// Determines if the provided snapshot contains updated data compared to the previous result.
    /// For DocumentSnapshot, compares the document data content.
    /// For QuerySnapshot, compares the set of documents (by path) and their data.
    ///
    /// - Parameters:
    ///   - current: The newly fetched snapshot
    ///   - previous: The previously delivered snapshot (if any)
    /// - Returns: true if the snapshot contains new or updated data, false otherwise
    private func resultHasUpdated(current: Snapshot, previous: Snapshot?) -> Bool {
        // DocumentSnapshot path
        if let currDoc = current as? DocumentSnapshot {
            let currData = currDoc.data() as NSDictionary?
            let prevData = (previous as? DocumentSnapshot)?.data() as NSDictionary?
            // If previous is nil and current has data, that's an update. If both nil, not updated.
            if currData == nil, prevData == nil { return false }
            return !(currData?.isEqual(to: prevData as? [AnyHashable: Any] ?? [:]) ?? (prevData != nil ? false : true))
        }

        // QuerySnapshot path
        if let currQuerySnap = current as? QuerySnapshot {
            guard let prevQuerySnap = previous as? QuerySnapshot else {
                // No previous snapshot to compare with
                return true
            }

            // Quick check: document count changed
            if currQuerySnap.count != prevQuerySnap.count {
                return true
            }

            // Build [docPath: NSDictionary(data)]
            func mapDocs(_ docs: [QueryDocumentSnapshot]) -> [String: NSDictionary] {
                var map: [String: NSDictionary] = [:]
                for d in docs {
                    let key = d.reference.path
                    let data = (d.data() ?? [:]) as NSDictionary
                    map[key] = data
                }
                return map
            }

            let currMap = mapDocs(currQuerySnap.documents)
            let prevMap = mapDocs(prevQuerySnap.documents)

            // Keys (document paths) changed
            if Set(currMap.keys) != Set(prevMap.keys) {
                return true
            }

            // Compare each document's data
            for (path, currData) in currMap {
                guard let prevData = prevMap[path] else { return true }
                if !(currData.isEqual(to: (prevData as? [AnyHashable: Any]) ?? [:])) {
                    return true
                }
            }
            return false
        }

        // As a safe default for unknown snapshot types, assume there is an update only when previous is nil.
        return previous == nil
    }

    // MARK: - Polling

    /// Performs a polling operation by querying all registered listeners' references.
    /// For each listener, fetches the latest data from the server and notifies listeners
    /// if changes are detected. Handles both successful responses and error conditions.
    private func poll() {
        guard let manager = self.listenerManager else {
            logger.warning("Listener manager deallocated; stopping polling")
            stopPolling()
            return
        }

        // Snapshot current listeners atomically
        let listeners = manager.allListenersSnapshot()

        for listenerData in listeners {
            logger.info("Sending polling request")

            // Support Query -> QuerySnapshot polling
            if let query = listenerData.getReference() as? Query {
                Task.detached { [weak self, weak listenerData] in
                    guard let self = self, let listenerData = listenerData else { return }
                    do {
                        if #available(macOS 10.15.0, *) {
                            let snap = try await query.getDocuments(source: .server, snapshot: true)
                            let prev = listenerData.getPreviousResult()
                            if !listenerData.hasDeliveredInitialEvent || self.resultHasUpdated(current: snap, previous: prev) {
                                OracledbLogger.info("Polling request succeeded for query \(query.path)")
                                listenerData.executeListener(snap, nil)
                            }
                        } else {
                            listenerData.executeListener(nil, PollingControllerError.internalError("Async getDocuments requires macOS 10.15+"))
                        }
                    } catch {
                        OracledbLogger.error("Polling request failed for query \(query.path)")
                        listenerData.executeListener(nil, error)
                    }
                }

            // Support DocumentReference -> DocumentSnapshot polling
            } else if let docRef = listenerData.getReference() as? DocumentReference {
                Task.detached { [weak self, weak listenerData] in
                    guard let self = self, let listenerData = listenerData else { return }
                    do {
                        // macOS 10.15+ async API
                        if #available(macOS 10.15.0, *) {
                            let snap = try await docRef.getDocument(source: .server, snapshot: true)
                            let prev = listenerData.getPreviousResult()
                            if !listenerData.hasDeliveredInitialEvent || self.resultHasUpdated(current: snap, previous: prev) {
                                OracledbLogger.info("Polling request succeeded for \(docRef.path)")
                                listenerData.executeListener(snap, nil)
                            }
                        } else {
                            // Fallback not supported; deliver error
                            listenerData.executeListener(nil, PollingControllerError.internalError("Async getDocument requires macOS 10.15+"))
                        }
                    } catch {
                        OracledbLogger.error("Polling request failed for \(docRef.path)")
                        listenerData.executeListener(nil, error)
                    }
                }
            } else {
                // Unsupported reference type for now
                let refPath: String = (listenerData.getReference() as? Reference)?.path ?? "<unknown>"
                listenerData.executeListener(nil, PollingControllerError.unsupportedReferenceType("Unsupported reference type for polling at \(refPath)"))
            }
        }
    }
}
