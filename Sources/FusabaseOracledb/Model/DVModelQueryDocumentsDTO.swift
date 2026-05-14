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
// Note: This file is part of the FusabaseOracledb module; no need to import itself.

/// Data Transfer Object for Duality View (DV) Model Query Documents responses.
/// Represents the structure of duality view query responses that contain multiple documents
/// with nested relational and document structures.
struct DVModelQueryDocumentsDTO: Codable, CustomStringConvertible {

    /// The list of document DTOs returned by the query.
    public let documents: [DVModelDocumentDTO]

    /// Coding keys for JSON encoding/decoding.
    private enum CodingKeys: String, CodingKey {
        case documents = "ret"
    }

    /// Initializes a new DVModelQueryDocumentsDTO with the provided documents.
    ///
    /// - Parameter documents: The list of document DTOs returned by the query.
    public init(documents: [DVModelDocumentDTO] = []) {
        self.documents = documents
    }

    /// Creates a DVModelQueryDocumentsDTO instance from JSON data.
    ///
    /// - Parameter jsonData: The JSON data containing the query response.
    /// - Returns: A new DVModelQueryDocumentsDTO instance, or nil if decoding fails.
    public static func fromJSON(_ jsonData: Data) -> DVModelQueryDocumentsDTO? {
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(DVModelQueryDocumentsDTO.self, from: jsonData)
        } catch {
            OracledbLogger.error("Failed to decode DVModelQueryDocumentsDTO from JSON: \(error)")
            return nil
        }
    }

    /// Creates a DVModelQueryDocumentsDTO instance from a JSON dictionary.
    ///
    /// - Parameter jsonDictionary: The dictionary containing the query response.
    /// - Returns: A new DVModelQueryDocumentsDTO instance.
    public static func fromDictionary(_ jsonDictionary: [String: Any]) -> DVModelQueryDocumentsDTO {
        var documents: [DVModelDocumentDTO] = []

        if let retArray = jsonDictionary["ret"] as? [[String: Any]] {
            for item in retArray {
                if let osonsDict = item["osons"] as? [String: Any],
                   let document = DVModelDocumentDTO.fromDictionary(osonsDict) {
                    documents.append(document)
                }
            }
        }

        return DVModelQueryDocumentsDTO(documents: documents)
    }

    /// Encodes this DVModelQueryDocumentsDTO to JSON data.
    ///
    /// - Returns: The JSON data representation, or nil if encoding fails.
    public func toJSON() -> Data? {
        let encoder = JSONEncoder()
        do {
            return try encoder.encode(self)
        } catch {
            OracledbLogger.error("Failed to encode DVModelQueryDocumentsDTO to JSON: \(error)")
            return nil
        }
    }

    /// Gets the number of documents in the result.
    ///
    /// - Returns: The count of documents.
    public var count: Int {
        return documents.count
    }

    /// Gets a specific document by index.
    ///
    /// - Parameter index: The index of the document to retrieve.
    /// - Returns: The document DTO at the specified index.
    /// - Throws: An error if the index is out of range (in debug builds only).
    public func getDocument(at index: Int) -> DVModelDocumentDTO {
        precondition(index >= 0 && index < documents.count, "Index out of range")
        return documents[index]
    }

    /// Finds a document by its OID.
    ///
    /// - Parameter oid: The object identifier to search for.
    /// - Returns: The document DTO with the matching OID, or nil if not found.
    public func findByOid(_ oid: String) -> DVModelDocumentDTO? {
        return documents.first { $0.oid == oid }
    }

    /// Finds documents by a specific field value.
    /// Useful for searching duality view documents by common fields like departmentName.
    ///
    /// - Parameter fieldName: The name of the field to search.
    /// - Parameter value: The value to match.
    /// - Returns: A list of documents that match the field value, or empty list if none found.
    public func findByField(_ fieldName: String, value: Any) -> [DVModelDocumentDTO] {
        return documents.filter { document in
            if let fieldValue = document.getField(fieldName) {
                return fieldValue as? NSObject == value as? NSObject
            }
            return false
        }
    }

    /// Gets all unique values for a specific field across all documents.
    /// Useful for getting distinct values like department names or locations.
    ///
    /// - Parameter fieldName: The name of the field to extract values from.
    /// - Returns: A list of unique field values.
    public func getDistinctFieldValues(_ fieldName: String) -> [Any] {
        var uniqueValues = Set<NSObject>()
        for document in documents {
            if let fieldValue = document.getField(fieldName) as? NSObject {
                uniqueValues.insert(fieldValue)
            }
        }
        return Array(uniqueValues)
    }

    /// Checks if the result is empty.
    ///
    /// - Returns: True if there are no documents, false otherwise.
    public var isEmpty: Bool {
        return documents.isEmpty
    }

    /// Returns a string representation of the DVModelQueryDocumentsDTO.
    public var description: String {
        return "DVModelQueryDocumentsDTO(documents: \(documents), count: \(count))"
    }

    // MARK: - Codable Implementation

    /// Creates a new instance by decoding from the given decoder.
    ///
    /// - Parameter decoder: The decoder to read data from.
    /// - Throws: An error if decoding fails.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Decode the ret array
        var documents: [DVModelDocumentDTO] = []
        if let retArray = try container.decodeIfPresent([[String: AnyCodable]].self, forKey: .documents) {
            for item in retArray {
                if let osonsDict = item["osons"] as? [String: AnyCodable],
                   let documentData = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(osonsDict), options: []) as? [String: Any],
                   let document = DVModelDocumentDTO.fromDictionary(documentData) {
                    documents.append(document)
                }
            }
        }
        self.documents = documents
    }

    /// Encodes this DVModelQueryDocumentsDTO into the given encoder.
    ///
    /// - Parameter encoder: The encoder to write data to.
    /// - Throws: An error if encoding fails.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        // Encode documents as ret array with osons structure
        let retArray: [[String: [String: AnyCodable]]] = documents.map { document in
            var osonsDict: [String: AnyCodable] = [:]

            // Add OID
            osonsDict["OID"] = AnyCodable(document.oid)

            // Add metadata if present
            if let metadata = document.metadata {
                osonsDict["_metadata"] = AnyCodable(metadata)
            }

            // Add document data fields
            if let documentData = document.documentData {
                for (key, value) in documentData {
                    osonsDict[key] = AnyCodable(value)
                }
            }

            return ["osons": osonsDict]
        }

        try container.encode(retArray, forKey: .documents)
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
