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

/// Data Transfer Object for Join View Document responses.
/// Represents the structure of join view query responses that contain combined data
/// from multiple joined tables or views.
struct JoinView: Codable {

    /// The joined data containing fields from multiple tables/views.
    public let data: [String: Any]?

    /// Coding keys for JSON encoding/decoding.
    private enum CodingKeys: String, CodingKey {
        case data
    }

    /// Initializes a new JoinView with the provided data.
    ///
    /// - Parameter data: The joined data containing fields from multiple tables/views.
    public init(data: [String: Any]? = nil) {
        self.data = data
    }

    /// Creates a JoinView instance from JSON data.
    ///
    /// - Parameter jsonData: The JSON data containing the joined view information.
    /// - Returns: A new JoinView instance, or nil if decoding fails.
    public static func fromJSON(_ jsonData: Data) -> JoinView? {
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(JoinView.self, from: jsonData)
        } catch {
            OracledbLogger.error("Failed to decode JoinView from JSON: \(error)")
            return nil
        }
    }

    /// Creates a JoinView instance from a JSON dictionary.
    ///
    /// - Parameter jsonDictionary: The dictionary containing the joined data.
    /// - Returns: A new JoinView instance.
    public static func fromDictionary(_ jsonDictionary: [String: Any]) -> JoinView {
        return JoinView(data: jsonDictionary)
    }

    /// Encodes this JoinView to JSON data.
    ///
    /// - Returns: The JSON data representation, or nil if encoding fails.
    public func toJSON() -> Data? {
        let encoder = JSONEncoder()
        do {
            return try encoder.encode(self)
        } catch {
            OracledbLogger.error("Failed to encode JoinView to JSON: \(error)")
            return nil
        }
    }

    /// Gets a specific field value from the joined data.
    ///
    /// - Parameter fieldName: The name of the field to retrieve.
    /// - Returns: The field value, or nil if the field doesn't exist or data is nil.
    public func getField(_ fieldName: String) -> Any? {
        return data?[fieldName]
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

    /// Gets the OID (Object Identifier) from the joined data.
    ///
    /// - Returns: The OID string, or nil if not present.
    public func getOid() -> String? {
        return getStringField("OID")
    }

    /// Gets the UUID from the joined data.
    ///
    /// - Returns: The UUID as Int64, or nil if not present.
    public func getUuid() -> Int64? {
        return getInt64Field("uuid")
    }

    /// Gets the PUUID (Parent UUID) from the joined data.
    ///
    /// - Returns: The PUUID as Int64, or nil if not present.
    public func getPuuid() -> Int64? {
        return getInt64Field("puuid")
    }

    /// Gets the PID from the joined data.
    ///
    /// - Returns: The PID as Int64, or nil if not present.
    public func getPid() -> Int64? {
        return getInt64Field("pid")
    }

    /// Gets the name field from the joined data.
    ///
    /// - Returns: The name string, or nil if not present.
    public func getName() -> String? {
        return getStringField("name")
    }

    /// Gets the uname (username) field from the joined data.
    ///
    /// - Returns: The uname string, or nil if not present.
    public func getUname() -> String? {
        return getStringField("uname")
    }

    /// Checks if the join view contains a value for the given key.
    ///
    /// - Parameter key: The key to check.
    /// - Returns: True if the key exists in the data, false otherwise.
    public func contains(_ key: String) -> Bool {
        return data?.keys.contains(key) ?? false
    }

    /// Returns the number of fields in the joined data.
    ///
    /// - Returns: The count of key-value pairs in the data.
    public var count: Int {
        return data?.count ?? 0
    }

    /// Checks if the joined data is empty.
    ///
    /// - Returns: True if the data contains no fields, false otherwise.
    public var isEmpty: Bool {
        return data?.isEmpty ?? true
    }

    /// Returns a string representation of the JoinView.
    public var description: String {
        return "JoinView(data: \(String(describing: data)))"
    }

    // MARK: - Codable Implementation

    /// Creates a new instance by decoding from the given decoder.
    ///
    /// - Parameter decoder: The decoder to read data from.
    /// - Throws: An error if decoding fails.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Decode the data dictionary - handle dynamic types
        if let dataDict = try container.decodeIfPresent([String: AnyCodable].self, forKey: .data) {
            self.data = dataDict.mapValues { $0.value }
        } else {
            self.data = nil
        }
    }

    /// Encodes this JoinView into the given encoder.
    ///
    /// - Parameter encoder: The encoder to write data to.
    /// - Throws: An error if encoding fails.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        // Encode the data dictionary
        if let data = data {
            let codableData = data.mapValues { AnyCodable($0) }
            try container.encode(codableData, forKey: .data)
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
