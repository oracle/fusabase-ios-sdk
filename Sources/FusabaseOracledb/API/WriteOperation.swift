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

/**
 Types of write operations that can be enqueued in transactions and batches.
 - set: Create or overwrite a document.
 - del: Delete a document.
 - upd: Update specific fields of a document.
 */
enum WriteOperationType {
    case set
    case del
    case upd
}

/**
 Internal model representing a single write operation.

 A WriteOperation couples an operation type (set, update, delete) with a target
 DocumentReference, optional payload data, and an optional optimistic concurrency
 version. It is used by Transaction and WriteBatch to stage atomic writes.
 */
class WriteOperation {

    private let operation: WriteOperationType
    private let docRef: DocumentReference
    private let data: Any?
    private let merge: Bool?
    private let mergeFields: [Any]?
    private let version: String?

    /// Initializes a new write operation description.
    /// - Parameters:
    ///   - operation: The kind of write operation (set, upd, del).
    ///   - docRef: The target document reference.
    ///   - data: Operation payload. For set, this is [String: Any]. For update, this is [AnyHashable: Any]. For delete, nil.
    ///   - version: Optional document version for optimistic concurrency control.
    init(
        operation: WriteOperationType,
        docRef: DocumentReference,
        data: Any? = nil,
        merge: Bool? = nil,
        mergeFields: [Any]? = nil,
        version: String? = nil
    ) {
        self.operation = operation
        self.docRef = docRef
        self.data = data
        self.merge = merge
        self.mergeFields = mergeFields
        self.version = version
    }

    /// The kind of write operation represented by this instance.
    var getOperation: WriteOperationType {
        return operation
    }
    
    /// The target document reference of this operation.
    var getDocRef: DocumentReference {
        return docRef
    }

    /// The operation data payload, if any.
    /// - Note: For set operations this is [String: Any]; for update it is [AnyHashable: Any]; for delete it is nil.
    var getData: Any? {
        return data
    }

//    var getOptions: SetOptions? {
//        return options
//    }

    /// Optional document version used for optimistic concurrency checks.
    var getVersion: String? {
        return version
    }

    var getMerge: Bool? {
        return merge
    }

    var getMergeFields: [Any]? {
        return mergeFields
    }
}
