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

/// An enumeration that specifies the type of change that occurred in a document change event.
public enum DocumentChangeType {
    /// Indicates that the document was added to the result set.
    case added
    /// Indicates that the document was modified in the result set.
    case modified
    /// Indicates that the document was removed from the result set.
    case removed
}

/// A DocumentChange represents a change to the documents matching a query.
/// It contains the document affected and the type of change that occurred (added, modified, or removed).
public class DocumentChange: NSObject, @unchecked Sendable {

    /// The type of change that occurred (added, modified, or removed).
    public let type: DocumentChangeType

    /// The document affected by this change.
    public let document: QueryDocumentSnapshot

    /// The index of the changed document in the result set immediately prior to this DocumentChange
    /// (i.e. supposing that all prior DocumentChange objects have been applied).
    /// Returns UInt.max (equivalent to NSNotFound) for DocumentChangeType.added events.
    public let oldIndex: UInt

    /// The index of the changed document in the result set immediately after this DocumentChange
    /// (i.e. supposing that all prior DocumentChange objects and the current DocumentChange object have been applied).
    /// Returns UInt.max (equivalent to NSNotFound) for DocumentChangeType.removed events.
    public let newIndex: UInt

    /// Initializes a new DocumentChange instance.
    ///
    /// - Parameters:
    ///   - type: The type of change that occurred.
    ///   - document: The document affected by this change.
    ///   - oldIndex: The index of the document before the change (UInt.max for added events).
    ///   - newIndex: The index of the document after the change (UInt.max for removed events).
    init(type: DocumentChangeType, document: QueryDocumentSnapshot, oldIndex: UInt, newIndex: UInt) {
        self.type = type
        self.document = document
        self.oldIndex = oldIndex
        self.newIndex = newIndex
        super.init()
    }
}
