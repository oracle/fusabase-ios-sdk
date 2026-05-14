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

/**
 Represents an ordering constraint for a query result set.

 An Order pairs a field name with a direction string ("asc" or "desc")
 to express how results should be sorted.
 */
class Order: Equatable {
    /// The field name to order by.
    var field: String
    /// Sort direction: "asc" for ascending or "desc" for descending.
    var direction: String
    
    init(field: String, direction: String) {
        self.field = field
        self.direction = direction
    }
    
    /// Creates a value copy of this ordering constraint.
    func copy() -> Order {
        return Order(field: self.field, direction: self.direction)
    }
    
    /// Serializes this ordering constraint to a dictionary payload.
    func toDictionary() -> [String: Any] {
        return [
            "field": field,
            "direction": direction
        ]
    }
    
    static func == (lhs: Order, rhs: Order) -> Bool {
        return lhs.field == rhs.field && lhs.direction == rhs.direction
    }
}
