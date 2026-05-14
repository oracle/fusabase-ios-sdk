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


/// An immutable snapshot of a StorageTask’s current state.
///
/// A snapshot captures status, progress, metadata, and any error at a moment in time.
/// You receive snapshots via observers registered on StorageTask, or by querying `snapshot()`.
@available(iOS 15, tvOS 13, macOS 10.15, watchOS 7, *)
/**
 Represents a snapshot of a storage task's current state, including progress and metadata.
 */
public class StorageTaskSnapshot {

    // MARK: - Public properties
    /// The task that produced this snapshot.
    public let task: StorageTask
    
    /// The metadata associated with the task result, if available (typically after successful uploads).
    public let metadata: StorageMetadata?
    /// The storage reference the task operates on.
    public let reference: StorageReference
    /// The current transfer progress, if the operation reports it.
    public let progress: Progress?
    /// The error that caused task failure or cancellation, if any.
    public let error: Error?
    /// The current status of the task at the time this snapshot was created.
    public let status: StorageTaskStatus

    // MARK: - Init
    /// Creates a snapshot instance.
    /// - Parameters:
    ///   - task: The task that produced this snapshot.
    ///   - metadata: The server-returned metadata, if available.
    ///   - reference: The storage reference the task operates on.
    ///   - progress: The current transfer progress, if available.
    ///   - error: The error that caused failure or cancellation, if any.
    ///   - status: The current status of the task.
    public init(task: StorageTask,
                metadata: StorageMetadata? = nil,
                reference: StorageReference,
                progress: Progress? = nil,
                error: Error? = nil,
                status: StorageTaskStatus) {
        self.task = task
        self.metadata = metadata
        self.reference = reference
        self.progress = progress
        self.error = error
        self.status = status
    }
    
    func withUpdated(progress: Progress? = nil,
                     metadata: StorageMetadata? = nil,
                     error: Error? = nil,
                     status: StorageTaskStatus? = nil) -> StorageTaskSnapshot {
        
        return StorageTaskSnapshot(task: self.task,
                                metadata: metadata ?? self.metadata,
                                reference: self.reference,
                                progress: progress ?? self.progress,
                                error: error ?? self.error,
                                status: status ?? self.status)
    }
}

actor SnapshotBox {
    private var snapshot: StorageTaskSnapshot
        
    init(task: StorageTask, reference: StorageReference) {
        self.snapshot = StorageTaskSnapshot(
            task: task,
            metadata: nil,
            reference: reference,
            progress: nil,
            error: nil,
            status: .unknown
        )
    }

    func setStatus(_ newStatus: StorageTaskStatus) {
        self.snapshot = self.snapshot.withUpdated(status: newStatus)
    }

    func getStatus() -> StorageTaskStatus {
        return self.snapshot.status
    }

    func setError(_ err: Error) {
        self.snapshot = self.snapshot.withUpdated(error: err, status: .failure)
    }

    func getError() -> Error? {
        return self.snapshot.error
    }

    func updateSnapshot(bytesTransferred: Int64, totalBytes: Int64) {
        let progress = Progress(totalUnitCount: totalBytes)
        progress.completedUnitCount = bytesTransferred
        self.snapshot = self.snapshot.withUpdated(progress: progress)
    }
    
    func setProgress(_ progress: Progress) {
        self.snapshot = self.snapshot.withUpdated(progress: progress)
    }
    
    func setMetadata(_ metadata: StorageMetadata) {
        self.snapshot = self.snapshot.withUpdated(metadata: metadata)
    }

    func getSnapshot() -> StorageTaskSnapshot {
        return self.snapshot
    }

    var isCanceled: Bool {
        self.snapshot.status == .failure && (self.snapshot.error as NSError?)?.code == StorageErrorCode.cancelled.rawValue
    }
    var isPaused: Bool { self.snapshot.status == .pause }
    var isResumed: Bool { self.snapshot.status == .resume }
    
    
    var isComplete: Bool { self.snapshot.status == .success || self.snapshot.status == .failure }
    var isInProgress: Bool { self.snapshot.status == .progress }
    var isSuccessful: Bool { self.snapshot.status == .success }
    var isFailed: Bool { self.snapshot.status == .failure }
}
