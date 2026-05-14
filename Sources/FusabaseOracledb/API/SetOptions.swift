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

/// Options that control the behavior of set operations on documents.
/// Use SetOptions to request merge semantics or to restrict which fields
/// are merged when writing document data.
public final class SetOptions {
    
    /// When true, the provided data is merged into the existing document
    /// rather than overwriting it entirely.
    public let merge: Bool
    /// A subset of fields to merge. If provided, only these fields are merged
    /// into the document. Ignored unless merge is true.
    public let mergeFields: [String]?

    /// Initializes a new SetOptions value.
    /// - Parameters:
    ///   - merge: Pass true to merge the provided data into the existing document.
    ///            Pass false to overwrite the document entirely.
    ///   - mergeFields: Optional list of field names to merge selectively.
    ///                  Only used when `merge` is true.
    public init(merge: Bool, mergeFields: [String]? = nil) {
        self.merge = merge
        self.mergeFields = mergeFields
    }
}
