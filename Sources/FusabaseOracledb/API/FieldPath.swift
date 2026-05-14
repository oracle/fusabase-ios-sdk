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

/// A FieldPath refers to a field (including nested) in a document.
/// Conforms to Hashable so it can be used as a key in [AnyHashable: Any].
public final class FieldPath: CustomStringConvertible, Hashable {

    /// The segments of the field path.
    public let fieldNames: [String]

    // MARK: - Init
    public init(_ fieldNames: [String]) {
        precondition(!fieldNames.isEmpty, "FieldPath must have at least one field name")
        self.fieldNames = fieldNames
    }

    /// Convenience: create from a dot-separated path like "address.zip".
    public convenience init(dotPath: String) {
        let parts = dotPath.split(separator: ".").map(String.init)
        self.init(parts)
    }

    // MARK: - Factory
    /// Returns a sentinel FieldPath to refer to the document ID.
    public class func documentID() -> Self {
        return Self(["__name__"]) // Oracledb's internal reserved field name for document ID
    }

    // MARK: - Hashable / Equatable
    /// Equality is based on path segments, not object identity.
    public static func == (lhs: FieldPath, rhs: FieldPath) -> Bool {
        return lhs.fieldNames == rhs.fieldNames
    }

    /// Hash is derived from the sequence of path segments.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(fieldNames.count)
        for segment in fieldNames {
            hasher.combine(segment)
        }
    }

    // MARK: - Convenience
    /// Returns the full path as a dot-separated string.
    public var path: String {
        return fieldNames.joined(separator: ".")
    }

    // MARK: - Debug / Logging
    public var description: String {
        return "FieldPath(\(path))"
    }
}
