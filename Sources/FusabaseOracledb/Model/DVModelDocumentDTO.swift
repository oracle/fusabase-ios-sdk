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

/// Data Transfer Object for Duality View (DV) Model Document responses.
/// Represents the structure of duality view query responses that combine relational and document models.
/// Duality views allow nested structures within relational data.
struct DVModelDocumentDTO: CustomStringConvertible {

    /// The document data containing all field values (can include nested structures).
    public let documentData: [String: Any]?

    /// The unique object identifier of the document.
    public let oid: String

    /// The metadata containing etag and asof information.
    public let metadata: [String: Any]?

    /// Coding keys for JSON encoding/decoding.
    private enum CodingKeys: String, CodingKey {
        case oid = "OID"
        case metadata = "_metadata"
    }

    /// Initializes a new DVModelDocumentDTO with the provided parameters.
    ///
    /// - Parameters:
    ///   - documentData: The document data containing all field values (can include nested structures).
    ///   - oid: The unique object identifier of the document.
    ///   - metadata: The metadata containing etag and asof information.
    public init(documentData: [String: Any]? = nil,
                oid: String,
                metadata: [String: Any]? = nil) {
        self.documentData = documentData
        self.oid = oid
        self.metadata = metadata
    }


    /// Creates a DVModelDocumentDTO instance from a JSON dictionary.
    ///
    /// - Parameter jsonDictionary: The dictionary containing the document data.
    /// - Returns: A new DVModelDocumentDTO instance, or nil if required fields are missing.
    public static func fromDictionary(_ jsonDictionary: [String: Any]) -> DVModelDocumentDTO? {
        guard let oid = jsonDictionary["OID"] as? String else {
            return nil
        }

        var documentData: [String: Any] = [:]
        var metadata: [String: Any]?

        // Extract fields, separating special fields from document data
        for (key, value) in jsonDictionary {
            switch key {
            case "OID":
                // Already extracted
                break
            case "_metadata":
                metadata = value as? [String: Any]
            default:
                // All other fields go into documentData
                documentData[key] = value
            }
        }

        return DVModelDocumentDTO(
            documentData: documentData.isEmpty ? nil : documentData,
            oid: oid,
            metadata: metadata
        )
    }

    /// Gets a specific field value from the document data.
    /// Can return nested structures like arrays or objects.
    ///
    /// - Parameter fieldName: The name of the field to retrieve.
    /// - Returns: The field value, or nil if the field doesn't exist or documentData is nil.
    public func getField(_ fieldName: String) -> Any? {
        return documentData?[fieldName]
    }

    /// Gets a field value as a String.
    ///
    /// - Parameter fieldName: The name of the field to retrieve.
    /// - Returns: The field value as a String, or nil if not found or not a String.
    public func getStringField(_ fieldName: String) -> String? {
        return getField(fieldName) as? String
    }

    /// Gets a field value as a Long.
    ///
    /// - Parameter fieldName: The name of the field to retrieve.
    /// - Returns: The field value as a Long, or nil if not found or not numeric.
    public func getLongField(_ fieldName: String) -> Int64? {
        return getField(fieldName) as? Int64
    }

    /// Gets a field value as an Integer.
    ///
    /// - Parameter fieldName: The name of the field to retrieve.
    /// - Returns: The field value as an Integer, or nil if not found or not numeric.
    public func getIntField(_ fieldName: String) -> Int? {
        return getField(fieldName) as? Int
    }

    /// Gets a field value as a nested structure (Map or List).
    /// Useful for accessing nested duality view structures.
    ///
    /// - Parameter fieldName: The name of the field to retrieve.
    /// - Parameter type: The expected type of the nested structure.
    /// - Returns: The field value as a nested structure, or nil if not found.
    public func getNestedField<T>(_ fieldName: String, type: T.Type) -> T? {
        return getField(fieldName) as? T
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

    /// Returns a string representation of the DVModelDocumentDTO.
    public var description: String {
        return "DVModelDocumentDTO(documentData: \(String(describing: documentData)), oid: \(oid), metadata: \(String(describing: metadata)))"
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

/// Helper struct for dynamic coding keys.
private struct AnyCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}
