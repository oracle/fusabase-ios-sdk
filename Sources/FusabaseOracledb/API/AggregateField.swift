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

/// Represents an aggregate field used in database aggregation queries.
/// This class encapsulates information about aggregation operations such as count, sum, and average
/// that can be applied to fields in a collection or query.
public class AggregateField {
    /// Internal implementation handling the aggregation logic.
    private var impl: AggregateFieldInternal

    /// The aggregation operation to perform (e.g., "count", "sum", "avg").
    var operation: String {
        get { impl.operation }
        set { impl.operation = newValue }
    }
    /// The field path to apply the aggregation operation on. Empty for operations like count.
    var field: FieldPath {
        get { impl.field }
        set { impl.field = newValue }
    }
    /// A unique key combining the operation and field path for identification.
    var opKey: String {
        return impl.opKey
    }

    /// Initializes an AggregateField with the given operation and optional field.
    ///
    /// - Parameters:
    ///   - operation: The aggregation operation (e.g., "count", "sum", "avg").
    ///   - field: The field path to apply the operation on (if applicable). Defaults to empty field path.
    required init(operation: String, field: FieldPath = FieldPath([""])) {
        self.impl = AggregateFieldInternal(operation: operation, field: field)
    }

    /// Creates a copy of this AggregateField instance.
    ///
    /// - Returns: A new AggregateField with the same operation and field values.
    func copy() -> AggregateField {
        return AggregateField(operation: self.operation, field: self.field)
    }
    
    /// Creates an aggregate field for counting documents.
    ///
    /// - Returns: An `AggregateField` representing the count operation.
    public class func count() -> Self {
        return Self(operation: "count")
    }

    /// Creates an aggregate field for summing values of a specific field.
    ///
    /// - Parameter field: The name of the field to sum.
    /// - Returns: An `AggregateField` representing the sum operation.
    public class func sum(_ field: String) -> Self {
        return Self(operation: "sum", field: FieldPath(dotPath: field))
    }

    /// Creates an aggregate field for summing values of a specific field using a FieldPath.
    ///
    /// - Parameter field: The FieldPath representing the field to sum.
    /// - Returns: An `AggregateField` representing the sum operation.
    public class func sum(_ field: FieldPath) -> Self {
        return Self(operation: "sum", field: field)
    }

    /// Creates an aggregate field for calculating the average value of a specific field.
    ///
    /// - Parameter field: The name of the field to average.
    /// - Returns: An `AggregateField` representing the average operation.
    public class func average(_ field: String) -> Self {
        return Self(operation: "avg", field: FieldPath(dotPath: field))
    }

    /// Creates an aggregate field for calculating the average value of a specific field using a FieldPath.
    ///
    /// - Parameter field: The FieldPath representing the field to average.
    /// - Returns: An `AggregateField` representing the average operation.
    public class func average(_ field: FieldPath) -> Self {
        return Self(operation: "avg", field: field)
    }
    

    /// Converts the AggregateField to a dictionary for serialization.
    ///
    /// - Returns: A `[String: Any]` representation of the aggregate field containing
    ///           the operation ("func"), field path, and operation key.
    func toDictionary() -> [String: Any] {
        return [
            "func": self.operation,
            "field": self.field.path,
            "op_key": self.opKey
        ]
    }
}
