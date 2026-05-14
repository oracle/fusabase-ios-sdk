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

internal class AggregateQuerySnapshotInternal {
    internal var query: Query
    internal var data: [String: Any]

    internal init(query: Query, data: [String: Any]) {
        self.query = query
        self.data = data
    }

    /// The number of documents in the result set of the underlying query.
    internal var count: NSNumber {
        // Try to get count from the aggregate data, defaulting to 0 if not found
        if let countValue = data["count"] as? NSNumber {
            return countValue
        } else if let countValue = data["count"] as? Int {
            return NSNumber(value: countValue)
        } else if let countValue = data["count"] as? Double {
            return NSNumber(value: countValue)
        }
        return NSNumber(value: 0)
    }
    
    /**
     Gets the aggregate result for the specified aggregate field without loss of precision.

      - Throws: Throws an InvalidArgument exception if the aggregate field was not requested in the AggregateQuery.
      - Returns: Returns the aggregate result from the server without loss of precision.
    */
    internal func get(opKey: String) -> Any {
        if self.data.contains(where: { (key, _) in key == opKey }) {
            return self.data[opKey]!
        } else {
            // tmp error value
            return -1
        }
    }
}
