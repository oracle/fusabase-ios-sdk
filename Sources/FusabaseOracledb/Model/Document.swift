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

/// Represents a document entity in the Oracledb database.
/// A document encapsulates the data content, metadata, and location information for database operations.
/// Documents are the basic units of data storage and retrieval in the Oracledb system, containing
/// key-value pairs of data along with system-managed metadata such as timestamps and version information.
class Document {

    /// The document data as key-value pairs.
    private let data: [String: Any]?

    /// The timestamp when the document was created.
    private let created: String

    /// The timestamp when the document was last modified.
    private let lastModified: String

    /// The version identifier of the document.
    private let version: String

    /// The unique object identifier for the document.
    private let objectId: String

    /// The path segments representing the document's location in the database.
    private let path: [String]

    /// The index position of the document in query results.
    private let index: Int?

    /// The row identifier for database operations.
    private let rowId: String

    /// Constructs a Document instance.
    ///
    /// - Parameters:
    ///   - data: the document data as key-value pairs
    ///   - objectId: the unique object identifier
    ///   - created: the creation timestamp
    ///   - lastModified: the last modification timestamp
    ///   - version: the version identifier
    ///   - index: the index position in query results
    ///   - path: the path segments to the document
    ///   - rowId: the row identifier for database operations
    init(data: [String: Any]?,
         objectId: String,
         created: String,
         lastModified: String,
         version: String,
         index: Int?,
         path: [String],
         rowId: String) {
        self.data = data
        self.objectId = objectId
        self.created = created
        self.lastModified = lastModified
        self.version = version
        self.path = path
        self.index = index
        self.rowId = rowId
    }

    /// Gets a field value from the document using a field path.
    /// Supports nested field access using dot notation.
    ///
    /// - Parameter path: the field path to access
    /// - Returns: the field value, or nil if not found
    func getField(_ fieldPath: FieldPath) -> Any? {
        let segments = fieldPath.fieldNames
        var innerData: Any? = data
        for segment in segments {
            if let dict = innerData as? [String: Any] {
                innerData = dict[segment]
            } else {
                return nil
            }
        }
        return innerData
    }

    /// Gets the document data as a map of key-value pairs.
    ///
    /// - Returns: the document data
    func getData() -> [String: Any]? {
        return data
    }

    /// Gets the unique identifier of the document.
    ///
    /// - Returns: the document ID
    func getId() -> String {
        return objectId
    }

    /// Gets the version identifier of the document.
    ///
    /// - Returns: the document version
    func getVersion() -> String {
        return version
    }

    /// Gets the creation timestamp of the document.
    ///
    /// - Returns: the creation timestamp
    func getCreated() -> String {
        return created
    }

    /// Gets the last modification timestamp of the document.
    ///
    /// - Returns: the last modification timestamp
    func getLastModified() -> String {
        return lastModified
    }

    /// Gets the row identifier for database operations.
    ///
    /// - Returns: the row ID
    func getRowId() -> String {
        return rowId
    }

    /// Gets the index position of the document in query results.
    ///
    /// - Returns: the document index
    func getIndex() -> Int? {
        return index
    }
}
