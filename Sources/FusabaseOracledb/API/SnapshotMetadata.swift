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

/// Metadata about the state of a snapshot.
/// Indicates whether the data was served from cache and whether there are
/// uncommitted local writes reflected in the snapshot.
public class SnapshotMetadata {
    /// True if the data for this snapshot was retrieved from the local cache.
    public let isFromCache: Bool
    /// True if the snapshot includes local changes that have not yet been
    /// committed to the server.
    public let hasPendingWrites: Bool

    /// Initializes a new SnapshotMetadata value.
    /// - Parameters:
    ///   - fromCache: Whether the data was served from local cache.
    ///   - hasPendingWrites: Whether there are uncommitted local writes.
    public init(fromCache: Bool, hasPendingWrites: Bool) {
        self.isFromCache = fromCache
        self.hasPendingWrites = hasPendingWrites
    }
}
