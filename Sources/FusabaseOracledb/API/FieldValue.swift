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

/// A sentinel/operation value used to express special field transformations in write operations.
/// This mirrors the Java design but uses Swift API signatures consistent with Fusabase Swift SDK.
public final class FieldValue: CustomStringConvertible {

    // MARK: - Operation
    public enum Operation {
        case arrayRemove
        case arrayUnion
        case delete
        case increment
        case serverTimestamp

        /// String identifier for each operation (like Java's getOperationInString()).
        public var operationString: String {
            switch self {
            case .arrayRemove:     return "arrayRemove"
            case .arrayUnion:      return "arrayUnion"
            case .delete:          return "delete"
            case .increment:       return "increment"
            case .serverTimestamp: return "servertimestamp"
            }
        }
    }

    // MARK: - Stored Properties
    public let operation: Operation
    public let values: [Any]
    // values isn't necessarily an array.
    // it could be an array of elements or an integer value

    // MARK: - Init
    private init(_ operation: Operation, _ values: [Any]) {
        self.operation = operation
        self.values = values
    }

    // MARK: - Factory APIs (aligned with Swift official API signatures)

    /// Returns a unique value for use with set()/update(), removing the specified elements from an array.
    public class func arrayRemove(_ elements: [Any]) -> Self {
        return Self(.arrayRemove, elements)
    }

    /// Returns a unique value for use with set()/update(), merging the specified elements into an array.
    public class func arrayUnion(_ elements: [Any]) -> Self {
        return Self(.arrayUnion, elements)
    }

    /// Returns a special marker for use with set()/update(), indicating a field should be deleted.
    public class func delete() -> Self {
        return Self(.delete, [])
    }

    /// Returns a unique value for use with set()/update(), incrementing the numeric field by Int64.
    public class func increment(_ l: Int64) -> Self {
        return Self(.increment, [l])
    }

    /// Returns a unique value for use with set()/update(), incrementing the numeric field by Double.
    public class func increment(_ d: Double) -> Self {
        return Self(.increment, [d])
    }

    /// Returns a special marker for use with set()/update(), inserting a server-generated timestamp.
    public class func serverTimestamp() -> Self {
        return Self(.serverTimestamp, [])
    }

    // MARK: - Accessors (parity with Java)
    public func getOperation() -> Operation { operation }
    public func getValues() -> [Any] { values }
    public var operationString: String { operation.operationString }

    // MARK: - Debug / Logging
    public var description: String {
        return "FieldValue(op: \(operation.operationString), values: \(values))"
    }
}
