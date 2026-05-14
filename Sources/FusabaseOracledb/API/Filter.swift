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
 Represents a query filter condition.

 A Filter encapsulates a field, an operator (such as ==, !=, >, >=, <, <=,
 array-contains, in, like, etc.), and a value to compare against. Filters are
 composed into Query objects to constrain result sets.
 */
public class Filter: Equatable {
    var field: String
    var op: String
    var value: Any

    public init(field: String, op: String, value: Any) {
        self.field = field
        self.op = op
        self.value = value
    }
    
    func copy() -> Filter {
        return Filter(field: self.field, op: self.op, value: self.value)
    }
    
    func toDictionary() -> [String: Any] {
        return [
            "field": field,
            "op": op,
            "value": value
        ]
    }
    
    public static func == (lhs: Filter, rhs: Filter) -> Bool {
        guard lhs.field == rhs.field, lhs.op == rhs.op else {
            return false
        }
        
        if type(of: lhs.value) == type(of: rhs.value) {
            // Compare values if the types are the same
            return "\(lhs.value)" == "\(rhs.value)" // Fallback to string interpolation comparison
        }
        return false
    }
    
    /**
     Creates a filter where the field is equal to the specified value.
     - Parameter field: The name of the field to filter.
     - Parameter value: The value to compare against.
     - Returns: A `Filter` object representing the equality condition.
    */
    public class func whereField(_ field: String, isEqualTo value: Any) -> Filter {
        return Filter(field: field, op: "==", value: value)
    }
    
    /**
     Creates a filter where the field is not equal to the specified value.
     - Parameter field: The name of the field to filter.
     - Parameter value: The value to compare against.
     - Returns: A `Filter` object representing the inequality condition.
    */
    public class func whereField(_ field: String, isNotEqualTo value: Any) -> Filter {
        return Filter(field: field, op: "!=", value: value)
    }
    
    /**
     Creates a filter where the field is greater than the specified value.
     - Parameter field: The name of the field to filter.
     - Parameter value: The value to compare against.
     - Returns: A `Filter` object representing the "greater than" condition.
    */
    public class func whereField(_ field: String, isGreaterThan value: Any) -> Filter {
        return Filter(field: field, op: ">", value: value)
    }
    
    /**
     Creates a filter where the field is greater than or equal to the specified value.
     - Parameter field: The name of the field to filter.
     - Parameter value: The value to compare against.
     - Returns: A `Filter` object representing the "greater than or equal to" condition.
    */
    public class func whereField(_ field: String, isGreaterOrEqualTo value: Any) -> Filter {
        return Filter(field: field, op: ">=", value: value)
    }
    
    /**
     Creates a filter where the field is less than the specified value.
     - Parameter field: The name of the field to filter.
     - Parameter value: The value to compare against.
     - Returns: A `Filter` object representing the "less than" condition.
    */
    public class func whereField(_ field: String, isLessThan value: Any) -> Filter {
        return Filter(field: field, op: "<", value: value)
    }
    
    /**
     Creates a filter where the field is less than or equal to the specified value.
     - Parameter field: The name of the field to filter.
     - Parameter value: The value to compare against.
     - Returns: A `Filter` object representing the "less than or equal to" condition.
    */
    public class func whereField(_ field: String, isLessThanOrEqualTo value: Any) -> Filter {
        return Filter(field: field, op: "<=", value: value)
    }
    
    /**
     Creates a filter where the array field contains the specified value.
     - Parameter field: The name of the array field to filter.
     - Parameter value: The value that must be contained in the array field.
     - Returns: A `Filter` object representing the "array contains" condition.
    */
    public class func whereField(_ field: String, arrayContains value: Any) -> Filter {
        return Filter(field: field, op: "array-contains", value: value)
    }
    
    /**
     Creates a filter where the array field contains any of the specified values.
     - Parameter field: The name of the array field to filter.
     - Parameter values: The list of values to match against the array field.
     - Returns: A `Filter` object representing the "array contains any" condition.
    */
    public class func whereField(_ field: String, arrayContainsAny values: [Any]) -> Filter {
        return Filter(field: field, op: "array-contains-any", value: values)
    }
    
    /**
     Creates a filter where the field's value matches any value in the specified list.
     - Parameter field: The name of the field to filter.
     - Parameter values: The list of values to match against.
     - Returns: A `Filter` object representing the "in" condition.
    */
    public class func whereField(_ field: String, in values: [Any]) -> Filter {
        return Filter(field: field, op: "in", value: values)
    }
    
    /**
     Creates a filter where the field's value does not match any value in the specified list.
     - Parameter field: The name of the field to filter.
     - Parameter values: The list of values to exclude.
     - Returns: A `Filter` object representing the "not-in" condition.
    */
    public class func whereField(_ field: String, notIn values: [Any]) -> Filter {
        return Filter(field: field, op: "not-in", value: values)
    }
    
    /**
     Creates a filter where the field value matches a pattern using SQL-like semantics.
     - Parameter field: The name of the field to filter.
     - Parameter value: The pattern to match against (e.g., "%foo%").
     - Returns: A `Filter` object representing the "like" condition.
    */
    public class func whereField(_ field: String, like value: Any) -> Filter {
        return Filter(field: field, op: "like", value: value)
    }
    
    /**
     Creates a filter that checks if the specified field is null.
     - Parameter field: The name of the field to check for null.
     - Returns: A `Filter` object representing the "is null" condition.
    */
    public class func whereFieldIsNull(_ field: String) -> Filter {
        // Represent null explicitly for payloads that always include a "value" key.
        return Filter(field: field, op: "is Null", value: NSNull())
    }
    
    /**
         Creates a composite filter that performs a logical OR operation on the provided filters.
         
         - Parameter filters: An array of `Filter` objects to combine using a logical OR.
         - Returns: A `Filter` object representing the combined OR condition.
         */
//        class func orFilter(_ filters: [Filter]) -> Filter {
//            return Filter(field: "__or__", op: "OR", value: filters.map { $0.toDictionary() })
//        }
    
    /**
         Creates a composite filter that performs a logical AND operation on the provided filters.
         
         - Parameter filters: An array of `Filter` objects to combine using a logical AND.
         - Returns: A `Filter` object representing the combined AND condition.
         */
//        class func andFilter(_ filters: [Filter]) -> Filter {
//            return Filter(field: "__and__", op: "AND", value: filters.map { $0.toDictionary() })
//        }

    // MARK: - FieldPath overloads

    /**
     Creates a filter where the field path is equal to the specified value.
     - Parameter path: The FieldPath of the field to filter.
     - Parameter value: The value to compare against.
     - Returns: A `Filter` object representing the equality condition.
    */
    public class func whereField(path: FieldPath, isEqualTo value: Any) -> Filter {
        return Filter(field: path.path, op: "==", value: value)
    }

    /**
     Creates a filter where the field path is not equal to the specified value.
     - Parameter path: The FieldPath of the field to filter.
     - Parameter value: The value to compare against.
     - Returns: A `Filter` object representing the inequality condition.
    */
    public class func whereField(path: FieldPath, isNotEqualTo value: Any) -> Filter {
        return Filter(field: path.path, op: "!=", value: value)
    }

    /**
     Creates a filter where the field path is greater than the specified value.
     - Parameter path: The FieldPath of the field to filter.
     - Parameter value: The value to compare against.
     - Returns: A `Filter` object representing the "greater than" condition.
    */
    public class func whereField(path: FieldPath, isGreaterThan value: Any) -> Filter {
        return Filter(field: path.path, op: ">", value: value)
    }

    /**
     Creates a filter where the field path is greater than or equal to the specified value.
     - Parameter path: The FieldPath of the field to filter.
     - Parameter value: The value to compare against.
     - Returns: A `Filter` object representing the "greater than or equal to" condition.
    */
    public class func whereField(path: FieldPath, isGreaterOrEqualTo value: Any) -> Filter {
        return Filter(field: path.path, op: ">=", value: value)
    }

    /**
     Creates a filter where the field path is less than the specified value.
     - Parameter path: The FieldPath of the field to filter.
     - Parameter value: The value to compare against.
     - Returns: A `Filter` object representing the "less than" condition.
    */
    public class func whereField(path: FieldPath, isLessThan value: Any) -> Filter {
        return Filter(field: path.path, op: "<", value: value)
    }

    /**
     Creates a filter where the field path is less than or equal to the specified value.
     - Parameter path: The FieldPath of the field to filter.
     - Parameter value: The value to compare against.
     - Returns: A `Filter` object representing the "less than or equal to" condition.
    */
    public class func whereField(path: FieldPath, isLessThanOrEqualTo value: Any) -> Filter {
        return Filter(field: path.path, op: "<=", value: value)
    }

    /**
     Creates a filter where the array field at the given path contains the specified value.
     - Parameter path: The FieldPath of the array field to filter.
     - Parameter value: The value that must be contained in the array field.
     - Returns: A `Filter` object representing the "array contains" condition.
    */
    public class func whereField(path: FieldPath, arrayContains value: Any) -> Filter {
        return Filter(field: path.path, op: "array-contains", value: value)
    }

    /**
     Creates a filter where the array field at the given path contains any of the specified values.
     - Parameter path: The FieldPath of the array field to filter.
     - Parameter values: The list of values to match against the array field.
     - Returns: A `Filter` object representing the "array contains any" condition.
    */
    public class func whereField(path: FieldPath, arrayContainsAny values: [Any]) -> Filter {
        return Filter(field: path.path, op: "array-contains-any", value: values)
    }

    /**
     Creates a filter where the field path's value matches any value in the specified list.
     - Parameter path: The FieldPath of the field to filter.
     - Parameter values: The list of values to match against.
     - Returns: A `Filter` object representing the "in" condition.
    */
    public class func whereField(path: FieldPath, in values: [Any]) -> Filter {
        return Filter(field: path.path, op: "in", value: values)
    }

    /**
     Creates a filter where the field path's value does not match any value in the specified list.
     - Parameter path: The FieldPath of the field to filter.
     - Parameter values: The list of values to exclude.
     - Returns: A `Filter` object representing the "not-in" condition.
    */
    public class func whereField(path: FieldPath, notIn values: [Any]) -> Filter {
        return Filter(field: path.path, op: "not-in", value: values)
    }

    /**
     Creates a filter where the field path value matches a pattern using SQL-like semantics.
     - Parameter path: The FieldPath of the field to filter.
     - Parameter value: The pattern to match against (e.g., "%foo%").
     - Returns: A `Filter` object representing the "like" condition.
    */
    public class func whereField(path: FieldPath, like value: Any) -> Filter {
        return Filter(field: path.path, op: "like", value: value)
    }

    /**
     Creates a filter that checks if the specified field path is null.
     - Parameter path: The FieldPath of the field to check for null.
     - Returns: A `Filter` object representing the "is null" condition.
    */
    public class func whereFieldIsNull(path: FieldPath) -> Filter {
        // Represent null explicitly for payloads that always include a "value" key.
        return Filter(field: path.path, op: "is Null", value: NSNull())
    }
}
