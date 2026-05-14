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
#if canImport(CoreFoundation)
import CoreFoundation
#endif

/// Utility class for reading and converting data between different formats,
/// including POJOs, Maps, and JSON values.
class DataReader {

    /// Converts the provided data into a Dictionary, handling nested structures and POJOs.
    ///
    /// - Parameter data: the data to convert
    /// - Returns: the converted Dictionary
    static func convertDataInHashMap(_ data: Any) -> [String: Any] {
        var updatedData = [String: Any]()

        if let dataMap = data as? [String: Any] {
            for (key, value) in dataMap {
                if value == nil {
                    updatedData[key] = nil
                } else if let hashMap = value as? [String: Any] {
                    updatedData[key] = convertDataInHashMap(hashMap)
                } else if value is String || value is Int || value is Double ||
                          value is Date || value is Bool || value is FieldValue {
                    updatedData[key] = value
                } else if let list = value as? [Any] {
                    let processedList = list.map { item -> Any? in
                        if item == nil {
                            return nil
                        } else if item is String || item is Int || item is Double ||
                                  item is Date || item is Bool || item is FieldValue {
                            return item
                        } else if let map = item as? [String: Any] {
                            return convertDataInHashMap(map)
                        }
                        return item
                    }
                    updatedData[key] = processedList
                } else {
                    updatedData[key] = value
                }
            }
        } else if data is [String: Any] {
            return convertDataInHashMap(data)
        }

        return updatedData
    }

    /// Converts data into a JSON-compatible value.
    ///
    /// - Parameter data: the data to convert
    /// - Returns: the JSON-compatible value
    static func getDataInJsonValue(_ data: Any) -> Any {
        if data is NSNull {
            return NSNull()
        } else if let dict = data as? [String: Any] {
            return getJsonValueForObject(dict)
        } else if let array = data as? [Any] {
            return array.map { getJsonValueForObject($0) }
        } else if data is Int {
            return data
        } else if data is Double {
            return data
        } else if data is String {
            return data
        } else if data is Bool {
            return data
        } else if let date = data as? Date {
            let formatter = ISO8601DateFormatter()
            return formatter.string(from: date)
        } else {
            return String(describing: data)
        }
    }

    /// Helper method to convert an object to JSON-compatible value.
    ///
    /// - Parameter data: the object to convert
    /// - Returns: the JSON-compatible value
    private static func getJsonValueForObject(_ data: Any) -> Any {
        if data is NSNull {
            return NSNull()
        } else if let dict = data as? [String: Any] {
            var result = [String: Any]()
            for (key, value) in dict {
                result[key] = getJsonValueForObject(value)
            }
            return result
        } else if let array = data as? [Any] {
            return array.map { getJsonValueForObject($0) }
        } else if data is Int || data is Double || data is String || data is Bool {
            return data
        } else if let date = data as? Date {
            let formatter = ISO8601DateFormatter()
            return formatter.string(from: date)
        } else {
            return String(describing: data)
        }
    }

    /// Converts a JSON object into a Dictionary.
    ///
    /// - Parameter data: the JSON object to convert
    /// - Returns: the Dictionary representation
    static func getJsonObjectDataInMap(_ data: [String: Any]) -> [String: Any] {
        var resultMap = [String: Any]()

        for (key, value) in data {
            resultMap[key] = getJsonValue(value)
        }

        return resultMap
    }

    /// Converts a JSON value into an Object.
    ///
    /// - Parameter value: the JSON value to convert
    /// - Returns: the Object representation
    private static func getJsonValue(_ value: Any) -> Any {
    if let dict = value as? [String: Any] {
        return getJsonObjectDataInMap(dict)
    } else if let array = value as? [Any] {
        return array.map { getJsonValue($0) }
    } 
    
    // 1. Handle NSNumber FIRST (this covers Int, Double, and Bool)
    else if let num = value as? NSNumber {
        #if canImport(CoreFoundation)
        // Check if the underlying type is actually a Boolean
        if CFGetTypeID(num) == CFBooleanGetTypeID() {
            return num.boolValue
        }
        #endif

        // 2. Check if it's an Integer vs a Double
        // We check if the number has a remainder when divided by 1
        if num.doubleValue.truncatingRemainder(dividingBy: 1) == 0 {
            return num.intValue
        } else {
            return num.doubleValue
        }
    } 
    
    else if let str = value as? String {
        return str
    }
    
    return value
}

    /// Checks if the string is a valid timestamp.
    ///
    /// - Parameter timestamp: the string to check
    /// - Returns: true if it's a timestamp, false otherwise
    static func isTimestamp(_ timestamp: String) -> Bool {
        let isoFormatter = ISO8601DateFormatter()
        return isoFormatter.date(from: timestamp) != nil
    }

    /// Converts a JsonValue into an Object with type preservation hints.
    ///
    /// - Parameter value: the JSON value to convert
    /// - Parameter fieldName: the field name (used for type hints)
    /// - Returns: the Object representation
    static func getJsonValueWithTypeHint(_ value: Any, _ fieldName: String?) -> Any {
        // Simplified implementation
        return getJsonValue(value)
    }
}
