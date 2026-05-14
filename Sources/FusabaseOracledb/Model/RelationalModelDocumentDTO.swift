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

/// Data Transfer Object for Relational Model Document responses.
/// Represents the structure of relational database query responses that contain flattened document data.
internal struct RelationalModelDocumentDTO: CustomStringConvertible {

    /// The document data containing all field values (flattened structure).
    public let documentData: [String: Any]?

    /// The unique object identifier of the document.
    public let oid: String

    /// The parent document's object identifier.
    public let parentOid: String?

    /// The metadata containing etag and asof information.
    public let metadata: [String: Any]?

    /// Coding keys for JSON encoding/decoding.
    private enum CodingKeys: String, CodingKey {
        case oid = "OID"
        case parentOid = "parent_oid"
        case metadata = "_metadata"
    }

    /// Initializes a new RelationalModelDocumentDTO with the provided parameters.
    ///
    /// - Parameters:
    ///   - documentData: The document data containing all field values (flattened structure).
    ///   - oid: The unique object identifier of the document.
    ///   - parentOid: The parent document's object identifier.
    ///   - metadata: The metadata containing etag and asof information.
    public init(documentData: [String: Any]? = nil,
                oid: String,
                parentOid: String? = nil,
                metadata: [String: Any]? = nil) {
        self.documentData = documentData
        self.oid = oid
        self.parentOid = parentOid
        self.metadata = metadata
    }

    /// Creates a RelationalModelDocumentDTO instance from JSON data.
    ///
    /// - Parameter jsonData: The JSON data containing the document information.
    /// - Returns: A new RelationalModelDocumentDTO instance, or nil if decoding fails.
    public static func fromJSON(_ jsonData: Data) -> RelationalModelDocumentDTO? {
        guard let jsonDict = try? JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any] else {
            return nil
        }
        return fromDictionary(jsonDict)
    }

    /// Creates a RelationalModelDocumentDTO instance from a JSON dictionary.
    ///
    /// - Parameter jsonDictionary: The dictionary containing the document data.
    /// - Returns: A new RelationalModelDocumentDTO instance, or nil if required fields are missing.
    public static func fromDictionary(_ jsonDictionary: [String: Any]) -> RelationalModelDocumentDTO? {
        guard let oid = jsonDictionary["OID"] as? String else {
            return nil
        }

        var documentData: [String: Any] = [:]
        var metadata: [String: Any]?
        var parentOid: String?

        // Extract fields, separating special fields from document data
        for (key, value) in jsonDictionary {
            switch key {
            case "OID":
                // Already extracted
                break
            case "parent_oid":
                parentOid = value as? String
            case "_metadata":
                metadata = value as? [String: Any]
            default:
                // All other fields go into documentData
                documentData[key] = value
            }
        }

        return RelationalModelDocumentDTO(
            documentData: documentData.isEmpty ? nil : documentData,
            oid: oid,
            parentOid: parentOid,
            metadata: metadata
        )
    }

    /// Encodes this RelationalModelDocumentDTO to JSON data.
    ///
    /// - Returns: The JSON data representation, or nil if encoding fails.
    public func toJSON() -> Data? {
        var jsonDict: [String: Any] = ["OID": oid]
        if let parentOid = parentOid {
            jsonDict["parent_oid"] = parentOid
        }
        if let metadata = metadata {
            jsonDict["_metadata"] = metadata
        }
        if let documentData = documentData {
            jsonDict.merge(documentData) { (_, new) in new }
        }
        return try? JSONSerialization.data(withJSONObject: jsonDict, options: [])
    }

    /// Gets a specific field value from the document data.
    ///
    /// - Parameter fieldName: The name of the field to retrieve.
    /// - Returns: The field value, or nil if the field doesn't exist or documentData is nil.
    public func getField(_ fieldName: String) -> Any? {
        return documentData?[fieldName]
    }

    /// Gets the etag from metadata.
    ///
    /// - Returns: The etag string, or nil if not present.
    public func getEtag() -> String? {
        return metadata?["etag"] as? String
    }

    /// Gets the asof value from metadata.
    ///
    /// - Returns: The asof string, or nil if not present.
    public func getAsof() -> String? {
        return metadata?["asof"] as? String
    }

    /// Checks if the document contains a value for the given key.
    ///
    /// - Parameter key: The key to check.
    /// - Returns: True if the key exists in the document data, false otherwise.
    public func contains(_ key: String) -> Bool {
        return documentData?.keys.contains(key) ?? false
    }

    /// Returns the number of fields in the document data.
    ///
    /// - Returns: The count of key-value pairs in the document data.
    public var count: Int {
        return documentData?.count ?? 0
    }

    /// Checks if the document data is empty.
    ///
    /// - Returns: True if the document contains no data, false otherwise.
    public var isEmpty: Bool {
        return documentData?.isEmpty ?? true
    }

    /// Returns a string representation of the RelationalModelDocumentDTO.
    public var description: String {
        return "RelationalModelDocumentDTO(documentData: \(String(describing: documentData)), oid: \(oid), parentOid: \(String(describing: parentOid)), metadata: \(String(describing: metadata)))"
    }

}
