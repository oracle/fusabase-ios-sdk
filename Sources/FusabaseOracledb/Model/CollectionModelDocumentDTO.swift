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
import FusabaseOracledb

/// Data Transfer Object for Collection Model Document responses.
/// Represents the structure of collection query responses that contain document information.
struct CollectionModelDocumentDTO: Codable, CustomStringConvertible {

    /// The document data containing field values.
    public let document: [String: Any]?

    /// The creation timestamp of the document.
    public let created: String?

    /// The last modified timestamp of the document.
    public let lastModified: String?

    /// The version number of the document.
    public let version: Int64

    /// Information about subcollections (can be null).
    public let subcollection: Any?

    /// The parent document's object identifier.
    public let parentOid: String?

    /// The unique object identifier of the document.
    public let oid: String

    /// Coding keys for JSON encoding/decoding.
    private enum CodingKeys: String, CodingKey {
        case document = "DOCUMENT"
        case created = "CREATED"
        case lastModified = "LAST_MODIFIED"
        case version = "VERSION"
        case subcollection = "SUBCOLLECTION"
        case parentOid = "PARENT_OID"
        case oid = "OID"
    }

    /// Initializes a new CollectionModelDocumentDTO with the provided parameters.
    ///
    /// - Parameters:
    ///   - document: The document data containing field values.
    ///   - created: The creation timestamp of the document.
    ///   - lastModified: The last modified timestamp of the document.
    ///   - version: The version number of the document.
    ///   - subcollection: Information about subcollections.
    ///   - parentOid: The parent document's object identifier.
    ///   - oid: The unique object identifier of the document.
    public init(document: [String: Any]? = nil,
                created: String? = nil,
                lastModified: String? = nil,
                version: Int64,
                subcollection: Any? = nil,
                parentOid: String? = nil,
                oid: String) {
        self.document = document
        self.created = created
        self.lastModified = lastModified
        self.version = version
        self.subcollection = subcollection
        self.parentOid = parentOid
        self.oid = oid
    }

    /// Creates a CollectionModelDocumentDTO instance from JSON data.
    ///
    /// - Parameter jsonData: The JSON data containing the document information.
    /// - Returns: A new CollectionModelDocumentDTO instance, or nil if decoding fails.
    public static func fromJSON(_ jsonData: Data) -> CollectionModelDocumentDTO? {
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(CollectionModelDocumentDTO.self, from: jsonData)
        } catch {
            OracledbLogger.error("Failed to decode CollectionModelDocumentDTO from JSON: \(error)")
            return nil
        }
    }

    /// Creates a CollectionModelDocumentDTO instance from a JSON dictionary.
    ///
    /// - Parameter jsonDictionary: The dictionary containing the document data.
    /// - Returns: A new CollectionModelDocumentDTO instance, or nil if required fields are missing.
    public static func fromDictionary(_ jsonDictionary: [String: Any]) -> CollectionModelDocumentDTO? {
        guard let oid = jsonDictionary["OID"] as? String,
              let version = jsonDictionary["VERSION"] as? Int64 else {
            return nil
        }

        let document = jsonDictionary["DOCUMENT"] as? [String: Any]
        let created = jsonDictionary["CREATED"] as? String
        let lastModified = jsonDictionary["LAST_MODIFIED"] as? String
        let subcollection = jsonDictionary["SUBCOLLECTION"]
        let parentOid = jsonDictionary["PARENT_OID"] as? String

        return CollectionModelDocumentDTO(
            document: document,
            created: created,
            lastModified: lastModified,
            version: version,
            subcollection: subcollection,
            parentOid: parentOid,
            oid: oid
        )
    }

    /// Encodes this CollectionModelDocumentDTO to JSON data.
    ///
    /// - Returns: The JSON data representation, or nil if encoding fails.
    public func toJSON() -> Data? {
        let encoder = JSONEncoder()
        do {
            return try encoder.encode(self)
        } catch {
            OracledbLogger.error("Failed to encode CollectionModelDocumentDTO to JSON: \(error)")
            return nil
        }
    }

    /// Gets a specific field value from the document data.
    ///
    /// - Parameter fieldName: The name of the field to retrieve.
    /// - Returns: The field value, or nil if the field doesn't exist or document is nil.
    public func getField(_ fieldName: String) -> Any? {
        return document?[fieldName]
    }

    /// Gets a field value as a String.
    ///
    /// - Parameter fieldName: The name of the field to retrieve.
    /// - Returns: The field value as a String, or nil if not found or not a String.
    public func getStringField(_ fieldName: String) -> String? {
        return getField(fieldName) as? String
    }

    /// Gets a field value as an Int.
    ///
    /// - Parameter fieldName: The name of the field to retrieve.
    /// - Returns: The field value as an Int, or nil if not found or not numeric.
    public func getIntField(_ fieldName: String) -> Int? {
        return getField(fieldName) as? Int
    }

    /// Gets a field value as an Int64.
    ///
    /// - Parameter fieldName: The name of the field to retrieve.
    /// - Returns: The field value as an Int64, or nil if not found or not numeric.
    public func getInt64Field(_ fieldName: String) -> Int64? {
        return getField(fieldName) as? Int64
    }

    /// Gets a field value as a Double.
    ///
    /// - Parameter fieldName: The name of the field to retrieve.
    /// - Returns: The field value as a Double, or nil if not found or not numeric.
    public func getDoubleField(_ fieldName: String) -> Double? {
        return getField(fieldName) as? Double
    }

    /// Gets a field value as a Bool.
    ///
    /// - Parameter fieldName: The name of the field to retrieve.
    /// - Returns: The field value as a Bool, or nil if not found or not a Bool.
    public func getBoolField(_ fieldName: String) -> Bool? {
        return getField(fieldName) as? Bool
    }

    /// Checks if the document contains a value for the given key.
    ///
    /// - Parameter key: The key to check.
    /// - Returns: True if the key exists in the document data, false otherwise.
    public func contains(_ key: String) -> Bool {
        return document?.keys.contains(key) ?? false
    }

    /// Returns the number of fields in the document data.
    ///
    /// - Returns: The count of key-value pairs in the document data.
    public var count: Int {
        return document?.count ?? 0
    }

    /// Checks if the document data is empty.
    ///
    /// - Returns: True if the document contains no data, false otherwise.
    public var isEmpty: Bool {
        return document?.isEmpty ?? true
    }

    /// Returns a string representation of the CollectionModelDocumentDTO.
    public var description: String {
        return "CollectionModelDocumentDTO(document: \(String(describing: document)), created: \(String(describing: created)), lastModified: \(String(describing: lastModified)), version: \(version), subcollection: \(String(describing: subcollection)), parentOid: \(String(describing: parentOid)), oid: \(oid))"
    }

    // MARK: - Codable Implementation

    /// Creates a new instance by decoding from the given decoder.
    ///
    /// - Parameter decoder: The decoder to read data from.
    /// - Throws: An error if decoding fails.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Decode optional fields
        self.created = try container.decodeIfPresent(String.self, forKey: .created)
        self.lastModified = try container.decodeIfPresent(String.self, forKey: .lastModified)
        self.parentOid = try container.decodeIfPresent(String.self, forKey: .parentOid)
        self.oid = try container.decode(String.self, forKey: .oid)
        self.version = try container.decode(Int64.self, forKey: .version)

        // Decode the document dictionary - handle dynamic types
        if let documentDict = try container.decodeIfPresent([String: AnyCodable].self, forKey: .document) {
            self.document = documentDict.mapValues { $0.value }
        } else {
            self.document = nil
        }

        // Decode subcollection - can be any type
        if let subcollectionValue = try container.decodeIfPresent(AnyCodable.self, forKey: .subcollection) {
            self.subcollection = subcollectionValue.value
        } else {
            self.subcollection = nil
        }
    }

    /// Encodes this CollectionModelDocumentDTO into the given encoder.
    ///
    /// - Parameter encoder: The encoder to write data to.
    /// - Throws: An error if encoding fails.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encodeIfPresent(created, forKey: .created)
        try container.encodeIfPresent(lastModified, forKey: .lastModified)
        try container.encodeIfPresent(parentOid, forKey: .parentOid)
        try container.encode(oid, forKey: .oid)
        try container.encode(version, forKey: .version)

        // Encode the document dictionary
        if let document = document {
            let codableDocument = document.mapValues { AnyCodable($0) }
            try container.encode(codableDocument, forKey: .document)
        }

        // Encode subcollection
        if let subcollection = subcollection {
            try container.encode(AnyCodable(subcollection), forKey: .subcollection)
        }
    }
}

/// Helper struct for encoding/decoding Any values in Codable types.
private struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) {
            value = intValue
        } else if let int64Value = try? container.decode(Int64.self) {
            value = int64Value
        } else if let doubleValue = try? container.decode(Double.self) {
            value = doubleValue
        } else if let stringValue = try? container.decode(String.self) {
            value = stringValue
        } else if let boolValue = try? container.decode(Bool.self) {
            value = boolValue
        } else if let arrayValue = try? container.decode([AnyCodable].self) {
            value = arrayValue.map { $0.value }
        } else if let dictValue = try? container.decode([String: AnyCodable].self) {
            value = dictValue.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported type")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let intValue as Int:
            try container.encode(intValue)
        case let int64Value as Int64:
            try container.encode(int64Value)
        case let doubleValue as Double:
            try container.encode(doubleValue)
        case let stringValue as String:
            try container.encode(stringValue)
        case let boolValue as Bool:
            try container.encode(boolValue)
        case let arrayValue as [Any]:
            try container.encode(arrayValue.map { AnyCodable($0) })
        case let dictValue as [String: Any]:
            try container.encode(dictValue.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Unsupported type"))
        }
    }
}
