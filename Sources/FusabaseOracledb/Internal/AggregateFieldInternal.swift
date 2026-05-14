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

//-----------------------------------------------------------------------------

import Foundation

/// Internal representation of an aggregate field used in database aggregation queries.
/// This class encapsulates the internal logic for aggregation operations.
internal class AggregateFieldInternal {
    /// The aggregation operation to perform (e.g., "count", "sum", "avg").
    internal var operation: String
    /// The field path to apply the aggregation operation on. Empty for operations like count.
    internal var field: FieldPath
    /// A unique key combining the operation and field path for identification.
    internal var opKey: String {
        if field.fieldNames.isEmpty {
            return operation
        } else {
            return operation + "_" + field.path
        }
    }

    /// Initializes an AggregateFieldInternal with the given operation and optional field.
    ///
    /// - Parameters:
    ///   - operation: The aggregation operation (e.g., "count", "sum", "avg").
    ///   - field: The field path to apply the operation on (if applicable). Defaults to empty field path.
    internal init(operation: String, field: FieldPath = FieldPath([])) {
        self.operation = operation
        self.field = field
    }

    /// Creates a copy of this AggregateFieldInternal instance.
    ///
    /// - Returns: A new AggregateFieldInternal with the same operation and field values.
    internal func copy() -> AggregateFieldInternal {
        return AggregateFieldInternal(operation: self.operation, field: self.field)
    }
    
    /// Creates an internal aggregate field for counting documents.
    ///
    /// - Returns: An `AggregateFieldInternal` representing the count operation.
    internal class func count() -> AggregateFieldInternal {
        return AggregateFieldInternal(operation: "count")
    }

    /// Creates an internal aggregate field for summing values of a specific field.
    ///
    /// - Parameter field: The field path to sum.
    /// - Returns: An `AggregateFieldInternal` representing the sum operation.
    internal class func sum(_ field: FieldPath) -> AggregateFieldInternal {
        return AggregateFieldInternal(operation: "sum", field: field)
    }

    /// Creates an internal aggregate field for calculating the average value of a specific field.
    ///
    /// - Parameter field: The field path to average.
    /// - Returns: An `AggregateFieldInternal` representing the average operation.
    internal class func average(_ field: FieldPath) -> AggregateFieldInternal {
        return AggregateFieldInternal(operation: "avg", field: field)
    }

    /// Converts the AggregateFieldInternal to a dictionary for serialization.
    ///
    /// - Returns: A `[String: Any]` representation of the aggregate field containing
    ///           the operation ("func"), field path, and operation key.
    internal func toDictionary() -> [String: Any] {
        return [
            "func": self.operation,
            "field": self.field.path,
            "op_key": self.opKey
        ]
    }
}
