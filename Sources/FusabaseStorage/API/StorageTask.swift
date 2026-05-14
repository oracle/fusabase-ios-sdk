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


/// Base class for long‑running storage operations such as uploads and downloads.
///
/// StorageTask exposes lifecycle control (pause, resume, cancel), state inspection,
/// and an observer API to receive progress and completion callbacks. Instances are
/// created by StorageReference operations and should not be instantiated directly.
@available(iOS 15, tvOS 13, macOS 10.15, watchOS 7, *)
/**
 Represents an asynchronous operation to upload or download data to/from cloud storage.

 You can observe the task's progress, pause, resume, or cancel it.
 */
public class StorageTask {
    public let reference: StorageReference
    
    // Use lazy to delay self capture until after init completes
    private lazy var snapshotBox: SnapshotBox = {
        return SnapshotBox(task: self, reference: reference)
    }()

    /// Creates a new task bound to the given storage reference.
    /// - Parameter reference: The storage reference the task operates on.
    public init(reference: StorageReference) {
        self.reference = reference
    }

    // MARK: - Snapshot

    /// Returns the latest known snapshot for this task.
    /// - Returns: A snapshot containing status, progress, metadata, and any error information.
    public func snapshot() async -> StorageTaskSnapshot {
        return await snapshotBox.getSnapshot()
    }

    /// Updates the task's progress snapshot.
    /// - Parameters:
    ///   - bytesTransferred: The number of bytes transferred so far.
    ///   - totalBytes: The total number of bytes expected for the operation.
    /// - Note: Intended for internal use by the SDK.
    public func updateSnapshot(bytesTransferred: Int64, totalBytes: Int64) async {
        await snapshotBox.updateSnapshot(bytesTransferred: bytesTransferred, totalBytes: totalBytes)
    }

    // MARK: - Control Flow

    /// Attempts to pause the task.
    ///
    /// The task can only be paused when it is currently in the `.resume` state.
    /// If the task is not resumable, this method has no effect.
    open func pause() {
        Task {
            let status = await snapshotBox.getStatus()
            guard status == .resume else {
                StorageLogger.warning("Cannot pause: task is not resume. Current state: \(status)")
                return
            }
            
            await notify(newStatus: .pause)

            await snapshotBox.setStatus(.pause)
            StorageLogger.info("Upload task paused.")
        }
    }

    /// Attempts to resume the task after it has been paused.
    ///
    /// The task can only be resumed when it is currently in the `.pause` state.
    open func resume() {
        Task {
            let status = await snapshotBox.getStatus()
            guard status == .pause else {
                StorageLogger.warning("Cannot resume: task is not paused. Current status: \(status)")
                return
            }
            
            await notify(newStatus: .resume)

            await snapshotBox.setStatus(.resume)
            StorageLogger.info("Upload task resumed.")
        }
    }

    /// Attempts to cancel the task.
    ///
    /// Cancellation transitions the task to `.failure` with a cancelled error and notifies observers.
    /// If the task is already complete, this method has no effect.
    open func cancel() {
        Task {
            let status = await snapshotBox.getStatus()
            if status == .success || status == .failure {
                StorageLogger.warning("Cannot cancel: task already completed. Current status: \(status)")
                return
            }
            
            await notify(newStatus: .failure, error: StorageErrorUtilities.cancelledError())

            await snapshotBox.setStatus(.failure)
            await snapshotBox.setError(StorageErrorUtilities.cancelledError())
            StorageLogger.info("Upload task canceled.")
        }
    }

    // MARK: - Result/Error

    internal func setResumed() async {
        await snapshotBox.setStatus(.resume)
    }

    internal func isCanceled() async -> Bool {
        return await snapshotBox.isCanceled
    }

    internal func isPaused() async -> Bool {
        return await snapshotBox.isPaused
    }
    
    internal func isResumed() async -> Bool {
        return await snapshotBox.isResumed
    }

    internal func setSuccessful() async {
        await snapshotBox.setStatus(.success)
    }

    /// Marks the task as failed.
    /// - Note: Intended for internal use by the SDK.
    public func setFailed() async {
        await snapshotBox.setStatus(.failure)
    }

    /// Associates an error with the task's snapshot.
    /// - Parameter error: The error that caused failure.
    /// - Note: Intended for internal use by the SDK.
    public func setError(_ error: Error) async {
        await snapshotBox.setError(error)
    }
    
    /// Returns the last error associated with this task, if any.
    /// - Returns: The error if the task failed or was cancelled; otherwise nil.
    public func getError() async -> Error? {
        return await snapshotBox.getError()
    }
    
    /// Attaches server‑returned metadata to the task's snapshot.
    /// - Parameter metadata: The metadata returned by the service.
    /// - Note: Intended for internal use by the SDK.
    public func setMetadata(_ metadata: StorageMetadata) async {
        await snapshotBox.setMetadata(metadata)
    }


    // MARK: - External state queries

    /// Indicates whether the task has completed (either success or failure).
    /// - Returns: True if the task finished; otherwise false.
    public func isComplete() async -> Bool { await snapshotBox.isComplete }
    /// Indicates whether the task finished with failure.
    /// - Returns: True if the task failed; otherwise false.
    public func isFailed() async -> Bool { await snapshotBox.isFailed }
    /// Indicates whether the task finished successfully.
    /// - Returns: True if the task succeeded; otherwise false.
    public func isSuccessful() async -> Bool { await snapshotBox.isSuccessful }
    
    // MARK: - Observer Utility
    private var state2id2handler: [StorageTaskStatus: [String: (StorageTaskSnapshot) -> Void]] = [:]
        
    /// Register an observer for a given task status. Returns the observer ID.
    @discardableResult
    open func observe(_ status: StorageTaskStatus,
                      handler: @escaping (StorageTaskSnapshot) -> Void) -> String {
        let id = UUID().uuidString
        if self.state2id2handler[status] == nil {
            self.state2id2handler[status] = [:]
        }
        self.state2id2handler[status]![id] = handler
        
        StorageLogger.debug("\(status) observer registered.")
        return id
    }
    
    // todo: thread-safe
    /// Removes a previously registered observer by its handle.
    /// - Parameter handle: The identifier returned from `observe(_:handler:)`.
    open func removeObserver(withHandle handle: String) {
        
        for (status, handlers) in self.state2id2handler {
            if handlers[handle] != nil {
                self.state2id2handler[status]?.removeValue(forKey: handle)
                StorageLogger.debug("Removed observer \(handle) for status \(status)")
                return
            }
        }
        // Optional: comment out to silence
        StorageLogger.warning("No observer found for handle \(handle)")
    }
    
    /// Removes all observers for a specific status.
    /// - Parameter status: The task status whose observers should be removed.
    open func removeAllObservers(for status: StorageTaskStatus) {
        
        if let handlers = self.state2id2handler[status], !handlers.isEmpty {
            self.state2id2handler[status]?.removeAll()
            StorageLogger.debug("Removed all observers for status \(status)")
        } else {
            // Optional: comment out to silence
            StorageLogger.warning("No observers found for status \(status)")
        }
    }

    /// Removes all observers for all statuses.
    open func removeAllObservers() {
        
        if !self.state2id2handler.isEmpty {
            self.state2id2handler.removeAll()
            StorageLogger.debug("Removed all observers for all statuses")
        } else {
            // Optional: comment out to silence
            StorageLogger.warning("No observers to remove.")
        }
    }
    
    /// Notify all observers for a given status.
    internal func notify(newStatus: StorageTaskStatus, error: Error? = nil) async {

        await self.snapshotBox.setStatus(newStatus)
        
        if newStatus == .failure {
            assert (error != nil)
            await self.snapshotBox.setError(error!)
        }
        
        guard let id2handler = self.state2id2handler[newStatus] else { return }
        let snapshot = await self.snapshotBox.getSnapshot()
        
        for handler in id2handler.values {
            handler(snapshot)
        }
    }
    
    internal func notify(newProgress: Progress) async {
        
        await self.snapshotBox.setProgress(newProgress)
        
        guard let id2handler = self.state2id2handler[.progress] else { return }
        let snapshot = await self.snapshotBox.getSnapshot()
        
        for handler in id2handler.values {
            handler(snapshot)
        }
    }
}
