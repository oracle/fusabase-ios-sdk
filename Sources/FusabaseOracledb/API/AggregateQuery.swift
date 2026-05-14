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
import os

/// A class that represents an aggregate query for performing aggregation operations on database collections.
/// This class encapsulates the logic for executing aggregate queries and processing the results.
/// AggregateQuery is created from a Query and provides methods to execute aggregation operations.
public class AggregateQuery {

    /// The underlying query object that defines the data source for aggregation.
    private let _query: Query

    /// Helper object for executing query operations.
    private let _queryHelper: QueryHelper

    /// Logger instance for debugging and error reporting.
    private static let logger = Logger(subsystem: "com.oracle.database.fusabase.oracledb", category: "AggregateQuery")

    /// The query object associated with this aggregate query.
    public var query: Query {
        return _query
    }

    /// The query helper used for executing database operations.
    internal var queryHelper: QueryHelper {
        return _queryHelper
    }

    /// Initializes a new AggregateQuery with the specified query.
    ///
    /// - Parameter query: The base query to perform aggregation on.
    init(query: Query) {
        self._query = query
        self._queryHelper = QueryHelper(options: query.oracledb.app.options, oradb: query.oracledb)
    }

    /// Executes the aggregate query and returns the results.
    ///
    /// - Returns: An AggregateQuerySnapshot containing the aggregated results.
    /// - Throws: An error if the aggregation execution fails.
    ///
    /// - Note: This method requires macOS 10.15.0 or later.
    @available(macOS 10.15.0, *)
    public func getAggregate(source: AggregateSource) async throws -> AggregateQuerySnapshot {
        do {
            let response = try await self.queryHelper.fetchDocuments(ref: self.query)
            OracledbLogger.debug("Fetched aggregation response: \(response)")

            // Parse the aggregation result from the response
            if let result = Self.parseAggregationResult(from: response) {
                return AggregateQuerySnapshot(query: self.query, data: result)
            } else {
                OracledbLogger.warning("No aggregation results found, returning empty snapshot")
                return AggregateQuerySnapshot(query: self.query, data: [:])
            }
        } catch {
            OracledbLogger.error("Failed to execute aggregate query: \(error.localizedDescription)")
            throw error
        }
    }

    /// Parses the aggregation result from the server response.
    ///
    /// - Parameter response: The JSON response from the server.
    /// - Returns: The parsed aggregation data, or nil if parsing fails.
    private static func parseAggregationResult(from response: [String: Any]) -> [String: Any]? {
        guard let retArray = response["ret"] as? [[String: Any]],
              let firstElement = retArray.first else {
            OracledbLogger.error("Invalid response structure: missing 'ret' array or empty array")
            return nil
        }

        // Try to extract result data from different possible keys
        if let resultString = firstElement["result"] as? String {
            // Result is a JSON string that needs to be parsed
            return parseResultString(resultString)
        } else if let resultData = firstElement["result"] as? [String: Any] {
            // Result is already a dictionary
            return resultData
        } else {
            OracledbLogger.error("No valid 'result' field found in response element")
            return nil
        }
    }

    /// Parses a JSON string result into a dictionary.
    ///
    /// - Parameter resultString: The JSON string to parse.
    /// - Returns: The parsed dictionary, or nil if parsing fails.
    private static func parseResultString(_ resultString: String) -> [String: Any]? {
        guard let jsonData = resultString.data(using: .utf8) else {
            OracledbLogger.error("Failed to convert result string to data")
            return nil
        }

        do {
            guard let jsonDict = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any] else {
                OracledbLogger.error("Result string did not parse to dictionary")
                return nil
            }
            OracledbLogger.debug("Successfully parsed aggregation result: \(jsonDict)")
            return jsonDict
        } catch {
            OracledbLogger.error("Failed to parse result JSON: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Equatable

    /// Compares two AggregateQuery instances for equality.
    ///
    /// - Parameters:
    ///   - lhs: The left-hand side AggregateQuery.
    ///   - rhs: The right-hand side AggregateQuery.
    /// - Returns: True if the queries are equal, false otherwise.
    static func == (lhs: AggregateQuery, rhs: AggregateQuery) -> Bool {
        return lhs.query == rhs.query
    }
}
