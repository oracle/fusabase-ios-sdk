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

/// Data Transfer Object for Relational Model Query Documents responses.
/// Represents the structure of relational database query responses that contain multiple documents.
struct RelationalModelQueryDocumentsDTO: CustomStringConvertible {

    /// The list of document DTOs returned by the query.
    public let documents: [RelationalModelDocumentDTO]

    /// Coding keys for JSON encoding/decoding.
    private enum CodingKeys: String, CodingKey {
        case documents = "ret"
    }

    /// Initializes a new RelationalModelQueryDocumentsDTO with the provided documents.
    ///
    /// - Parameter documents: The list of document DTOs returned by the query.
    public init(documents: [RelationalModelDocumentDTO] = []) {
        self.documents = documents
    }


    /// Creates a RelationalModelQueryDocumentsDTO instance from a JSON dictionary.
    ///
    /// - Parameter jsonDictionary: The dictionary containing the query response.
    /// - Returns: A new RelationalModelQueryDocumentsDTO instance.
    public static func fromDictionary(_ jsonDictionary: [String: Any]) -> RelationalModelQueryDocumentsDTO {
        var documents: [RelationalModelDocumentDTO] = []

        if let retArray = jsonDictionary["ret"] as? [[String: Any]] {
            for item in retArray {
                if let osonsDict = item["osons"] as? [String: Any],
                   let document = RelationalModelDocumentDTO.fromDictionary(osonsDict) {
                    documents.append(document)
                }
            }
        }

        return RelationalModelQueryDocumentsDTO(documents: documents)
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
    public func getDocument(at index: Int) -> RelationalModelDocumentDTO {
        precondition(index >= 0 && index < documents.count, "Index out of range")
        return documents[index]
    }

    /// Finds a document by its OID.
    ///
    /// - Parameter oid: The object identifier to search for.
    /// - Returns: The document DTO with the matching OID, or nil if not found.
    public func findByOid(_ oid: String) -> RelationalModelDocumentDTO? {
        return documents.first { $0.oid == oid }
    }

    /// Checks if the result is empty.
    ///
    /// - Returns: True if there are no documents, false otherwise.
    public var isEmpty: Bool {
        return documents.isEmpty
    }

    /// Returns a string representation of the RelationalModelQueryDocumentsDTO.
    public var description: String {
        return "RelationalModelQueryDocumentsDTO(documents: \(documents), count: \(count))"
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
