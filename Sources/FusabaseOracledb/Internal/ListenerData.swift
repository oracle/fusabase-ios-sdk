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

/// A data container class that holds information about a single listener registration.
/// This class encapsulates all the necessary data and state for managing an event listener
/// attached to a database reference, including lifecycle management, execution context,
/// and synchronization state.
class ListenerData<K: Reference, T: Snapshot> {

    /// The executor for running the listener callback.
    private var executor: Executor

    /// Unique identifier for this listener.
    private var listenerId: Int

    /// The event listener callback.
    private var listener: any EventListener<T>

    /// The listener registration object.
    private var registration: ListenerRegistrationImpl!

    /// The listener manager that manages this listener.
    private var manager: ListenerManager<K, T>

    /// Metadata changes configuration.
    private var metadataChanges: MetadataChanges?

    /// The reference this listener is attached to.
    var ref: K

    /// Whether this listener has been synchronized.
    private var _isSynchronized: Bool

    /// The previous result snapshot.
    var previousResult: T?

    /// Whether we have delivered at least one event to the application's listener.
    ///
    /// This is used by long-polling mode to guarantee WebSocket-like semantics:
    /// after registration, the listener must receive an initial callback
    /// (snapshot or error) even if the polled result matches the previous one.
    var hasDeliveredInitialEvent: Bool
    private var active = true
    private var initialRemoteSnapshotLoading = false

    /// Constructs a new ListenerData instance with the provided parameters.
    ///
    /// - Parameters:
    ///   - listener: The event listener that will be called when data changes
    ///   - ref: The database reference this listener is attached to
    ///   - listenerId: Unique identifier for this listener
    ///   - manager: The ListenerManager that manages this listener
    ///   - executor: Executor for running the listener callback
    ///   - metadataChanges: Configuration for metadata change notifications
    init(listener: any EventListener<T>,
         ref: K,
         listenerId: Int,
         manager: ListenerManager<K, T>,
         executor: Executor,
         metadataChanges: MetadataChanges?) {

        self.listenerId = listenerId
        self.listener = listener
        self.executor = executor
        self.manager = manager
        self.metadataChanges = metadataChanges
        self.ref = ref
        self._isSynchronized = false
        self.previousResult = nil
        self.hasDeliveredInitialEvent = false

        // Initialize registration after all properties are set
        self.registration = ListenerRegistrationImpl(removeAction: { [weak self] in
            guard let self = self else { return }
            self.manager.removeListener(self)
        })
    }

    /// Gets the unique identifier for this listener.
    ///
    /// - Returns: The listener ID
    func getListenerId() -> Int {
        return self.listenerId
    }

    /// Gets the executor for this listener.
    ///
    /// - Returns: The executor
    func getExecutor() -> Executor {
        return executor
    }

    /// Gets the metadata changes configuration.
    ///
    /// - Returns: The metadata changes configuration, or nil
    func getMetadataChanges() -> MetadataChanges? {
        return metadataChanges
    }

    /// Gets the event listener callback.
    ///
    /// - Returns: The event listener
    func getListener() -> any EventListener<T> {
        return listener
    }

    /// Gets the listener registration object.
    ///
    /// - Returns: The listener registration
    func getListenerRegistration() -> ListenerRegistration {
        return self.registration
    }

    /// Gets the reference this listener is attached to.
    ///
    /// - Returns: The reference
    func getReference() -> Reference {
        return ref
    }

    /// Executes the event listener on the specified executor with the given snapshot value and error.
    /// Updates the previous result before triggering the listener callback.
    ///
    /// - Parameters:
    ///   - value: The snapshot value to pass to the listener
    ///   - error: Any error that occurred, or nil if successful
    func executeListener(_ value: Snapshot?, _ error: Error?) {
        guard active else { return }
        // Set the current result as previous result
        self.previousResult = value as? T

        // Mark that the app-level listener has received its first event.
        // (We do this even for error deliveries.)
        self.hasDeliveredInitialEvent = true

        self.executor.execute {
            guard self.active else { return }
            self.listener.onEvent(value as? T, error)
        }
    }

    func deactivate() { active = false }
    func isActive() -> Bool { active }
    func beginInitialRemoteSnapshotLoad() -> Bool {
        guard !hasDeliveredInitialEvent && !initialRemoteSnapshotLoading else { return false }
        initialRemoteSnapshotLoading = true
        return true
    }
    func clearInitialRemoteSnapshotLoad() { initialRemoteSnapshotLoading = false }

    /// A new WebSocket connection needs a new authoritative server baseline before
    /// it can safely accept notification deltas.
    func resetRealtimeBaseline() {
        previousResult = nil
        hasDeliveredInitialEvent = false
        initialRemoteSnapshotLoading = false
    }

    /// Gets the previous result snapshot.
    ///
    /// - Returns: The previous result, or nil
    func getPreviousResult() -> T? {
        return self.previousResult
    }

    /// Sets the previous result snapshot.
    ///
    /// - Parameter currentResult: The result to set as previous
    /// - Returns: The set result
    func setPreviousResult(_ currentResult: T) -> T {
        self.previousResult = currentResult
        return currentResult
    }

    /// Sets this listener as synchronized.
    func setSynchronized() {
        self._isSynchronized = true
    }

    /// Checks if this listener has been synchronized.
    ///
    /// - Returns: True if synchronized, false otherwise
    func isSynchronized() -> Bool {
        return _isSynchronized
    }
}
