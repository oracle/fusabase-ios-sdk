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

/// A read-only view of the results of an aggregate query.
/// 
/// Instances of AggregateQuerySnapshot contain server-computed aggregation
/// results for a corresponding Query (for example, count, sum, or average).
/// Values are returned without loss of precision where supported by the backend.
public class AggregateQuerySnapshot {
    /// Internal implementation handling the aggregation snapshot logic.
    private var impl: AggregateQuerySnapshotInternal

    init(query: Query, data: [String: Any]) {
        self.impl = AggregateQuerySnapshotInternal(query: query, data: data)
    }

    /// The number of documents in the result set of the underlying query.
    public var count: NSNumber {
        return impl.count
    }

    /// The aggregate query that produced this snapshot.
    public var query: Query {
        return impl.query
    }
    
    /**
     Gets the aggregate result for the specified aggregate field without loss of precision.

      - Throws: Throws an InvalidArgument exception if the aggregate field was not requested in the AggregateQuery.
      - Returns: Returns the aggregate result from the server without loss of precision.
    */
    public func get(_ aggregateField: AggregateField) -> Any {
        return impl.get(opKey: aggregateField.opKey)
    }
}
