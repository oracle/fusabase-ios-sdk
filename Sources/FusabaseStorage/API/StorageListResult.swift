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


/// Represents a page of list results returned from StorageReference list operations.
///
/// StorageListResult contains item references (files), prefix references (folders),
/// and an optional page token that can be used to request subsequent pages.
@available(iOS 15, tvOS 13, macOS 10.15, watchOS 7, *)
/**
 Contains the result of a list operation, including items and prefixes.
 */
public class StorageListResult {
    
    /// A list of items (files) in the bucket.
    public let items: [StorageReference]
    
    /// A list of prefixes (folders) in the bucket.
    public let prefixes: [StorageReference]
    
    /// The page token to retrieve the next page of results. Nil if there are no more pages.
    public let pageToken: String?
    
    /// Initializes a StorageListResult with items, prefixes, and pageToken.
    /// - Parameters:
    ///   - items: Array of StorageReference representing files.
    ///   - prefixes: Array of StorageReference representing folders.
    ///   - pageToken: Optional page token for pagination.
    public init(items: [StorageReference], prefixes: [StorageReference], pageToken: String? = nil) {
        self.items = items
        self.prefixes = prefixes
        self.pageToken = pageToken
    }
}
