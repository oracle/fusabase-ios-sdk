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

/**
 A read-only query over a collection of documents.

 Query lets you compose filters, ordering, and limits, and then fetch the
 matching documents. It provides convenience predicate methods mirroring the
 Java API for familiarity, while following Swift naming conventions.

 - Important: Query is immutable. Each mutating-style method (e.g. whereField,
              order, limit) returns a new `Query` instance with the added
              constraint.
 */
public class Query: Reference {

    // MARK: - Storage

    /// The segments that compose the path for this reference.
    var _pathSegArr: [String] = []

    /// Underlying Oracledb instance.
    private var _Oracledb: FusabaseOracledb

    /// Helper responsible for executing query operations.
    private var _queryHelper: QueryHelper

    /// Accumulated filter constraints.
    private var _filterArr: [Filter] = []

    /// Accumulated ordering constraints.
    private var _orderArr: [Order] = []

    /// Result limit. A value of 0 means "no explicit limit".
    private var _limit: Int = 0

    /// Accumulated aggregate fields to compute.
    var _aggFieldArr: [AggregateField] = []

    /// Join view names added via `FusabaseOracledb.join` or `Query.join`.
    var _joins: [String] = []

    /// Column names to select in the query.
    var _columns: [String] = []

    /// Whether this query is for a collection group (searches across all collections with the given ID).
    var _isColGroup: Bool = false

    /// Vector similarity search payload (API v2 only). Serialized as `vectorSearch` in runQuery.
    ///
    /// Stored as JSON-compatible dictionary to plug directly into JSONSerialization.
    var _vectorSearch: [String: Any]? = nil
    
    // Listener manager for Query -> QuerySnapshot events
    private lazy var listenerManager: ListenerManager<Query, QuerySnapshot> = {
        return ListenerManager(oradb: self._Oracledb, ref: self)
    }()
    
    // Closure-backed EventListener adapter for QuerySnapshot
    private final class QueryClosureListener: EventListener {
        typealias T = QuerySnapshot
        private let onEventBlock: (QuerySnapshot?, Error?) -> Void
        
        init(_ onEvent: @escaping (QuerySnapshot?, Error?) -> Void) {
            self.onEventBlock = onEvent
        }
        
        func onEvent(_ value: QuerySnapshot?, _ error: Error?) {
            onEventBlock(value, error)
        }
    }

    // MARK: - Reference conformance

    /// The absolute path of this reference.
    public var path: String {
        return _pathSegArr.joined(separator: "/")
    }

    /// The database instance associated with this query.
    public var oracledb: FusabaseOracledb {
        return _Oracledb
    }

    // MARK: - Internal getters

    /// The internal query helper used for RPC/HTTP/WebSocket operations.
    var queryHelper: QueryHelper {
        return _queryHelper
    }

    /// The set of filters applied to this query.
    var filterArr: [Filter] {
        return _filterArr
    }

    /// The ordering applied to this query.
    var orderArr: [Order] {
        return _orderArr
    }

    /// The limit applied to this query, or 0 if none.
    var limit: Int {
        return _limit
    }

    // MARK: - Init

    /// Creates a new Query for the provided database.
    /// - Parameter oracledb: Database instance to execute against.
    /// - Parameter path: The path string for the query
    /// - Parameter isColGroup: Whether this is a collection group query
    init(oracledb: FusabaseOracledb, path: String = "", isColGroup: Bool = false) {
        self._Oracledb = oracledb
        self._pathSegArr = path.components(separatedBy: "/")
        self._queryHelper = QueryHelper(options: oracledb.app.options, oradb: oracledb)
        self._isColGroup = isColGroup
    }

    // MARK: - Vector search

    /// Adds a vector similarity search constraint to the query (API v2 only).
    ///
    /// - Parameters:
    ///   - field: Vector field name.
    ///   - query: Dense or sparse query input.
    ///   - metric: Similarity metric.
    ///   - topK: Number of nearest results to fetch (must be > 0).
    ///   - threshold: Optional score/distance threshold.
    /// - Returns: A new Query with vector search configured.
    public func findNearest(
        _ field: String,
        _ query: VectorSearchQuery,
        metric: VectorMetric? = nil,
        topK: Int? = nil,
        threshold: Double? = nil
    ) throws -> Query {
        let trimmed = field.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw OracledbErrorUtilities.invalidArgumentError(message: "Invalid vector search field")
        }
        if let topK, topK <= 0 {
            throw OracledbErrorUtilities.invalidArgumentError(message: "findNearest topK must be a positive integer")
        }
        if let threshold, !threshold.isFinite {
            throw OracledbErrorUtilities.invalidArgumentError(message: "findNearest threshold must be a finite number")
        }

        // Validate query payload.
        switch query {
        case .dense(let values):
            try validateDenseVector(values, message: "Vector search query.vector must be a numeric array.")
        case .sparse(let sparse):
            try validateSparseVector(sparse)
        }

        let newQuery = self.copy()
        var payload: [String: Any] = [
            "field": trimmed,
            "query": encodeVectorSearchQuery(query),
        ]
        if let metric {
            payload["metric"] = metric.rawValue
        }
        if let topK {
            payload["topK"] = topK
        }
        if let threshold {
            payload["threshold"] = threshold
        }
        newQuery._vectorSearch = payload
        return newQuery
    }

    /// Backward-compatible alias for `findNearest`.
    ///
    /// Web modular originally shipped this API as `vectorSearch` and later renamed it.
    /// Keeping an alias in Swift reduces churn for early adopters.
    public func vectorSearch(
        _ field: String,
        _ query: VectorSearchQuery,
        metric: VectorMetric? = nil,
        topK: Int? = nil,
        threshold: Double? = nil
    ) throws -> Query {
        return try findNearest(field, query, metric: metric, topK: topK, threshold: threshold)
    }

    // MARK: - Retrieving Data

    /// Fetches multiple documents as a `QuerySnapshot` with explicit source and snapshot parameters.
    ///
    /// Mirrors the Java get(Source source, boolean snapshot) method but adopts Swift's async/await.
    /// - Parameters:
    ///   - source: Desired fetch source. Currently used for API parity; server selection is not altered.
    ///   - snapshot: Whether to request server-side snapshot processing.
    /// - Returns: A `QuerySnapshot` containing the fetched documents.
    /// - Throws: An error if the document retrieval fails.
    @available(iOS 15.0, macOS 10.15, *)
    public func getDocuments(source: FusabaseSource, snapshot: Bool = false) async throws -> QuerySnapshot {
        let promJson = try await self.queryHelper.fetchDocuments(ref: self, snapshot: snapshot)
        return parseQuerySnapshot(from: promJson)
    }

    /// Parses the backend response dictionary into a `QuerySnapshot`.
    /// - Parameter promJson: The JSON dictionary returned by the backend.
    /// - Returns: A `QuerySnapshot` built from the response.
    private func parseQuerySnapshot(from promJson: [String: Any]) -> QuerySnapshot {
        let metadata1 = SnapshotMetadata(fromCache: false, hasPendingWrites: false)

        if !promJson.isEmpty,
           let retArr = promJson["ret"] as? [[String: Any]] {

            let colRef = CollectionReference(oracledb: self.oracledb, path: self._pathSegArr.joined(separator: "/"))
            var docSnapArr: [QueryDocumentSnapshot] = []

            for elem in retArr {
                if !elem.isEmpty {
                    if let osonsData = elem["osons"] as? [String: Any] {
                        let metadata2 = SnapshotMetadata(fromCache: false, hasPendingWrites: false)
                        if let docId = osonsData["OID"] as? String {
                            let docRef = DocumentReference(oracledb: self.oracledb, path: colRef.path + "/" + docId, parent: colRef)
                            let docSnap = QueryDocumentSnapshot(data: osonsData, docRef: docRef, metadata: metadata2)
                            docSnapArr.append(docSnap)
                        } else {
                            OracledbLogger.error("Missing OID in osons payload")
                        }
                    } else {
                        OracledbLogger.error("osons not a key, or not a [String: Any] dict")
                    }
                } else {
                    OracledbLogger.error("firstElem is empty")
                }
            }

            return QuerySnapshot(snaps: docSnapArr, query: self, metadata: metadata1)
        } else {
            OracledbLogger.error("'ret' key is missing, not an array of dictionaries, or empty.")
        }

        return QuerySnapshot(snaps: [], query: self, metadata: metadata1)
    }

    /**
     Fetches multiple documents as a `QuerySnapshot`.

     This is an asynchronous function that performs the network request,
     decodes the response and returns an in-memory `QuerySnapshot`.

     - Throws: An error if the document retrieval fails.
     - Returns: A `QuerySnapshot` containing the fetched documents.
     */
    @available(iOS 15.0, macOS 10.15, *)
    public func getDocuments() async throws -> QuerySnapshot {
        return try await getDocuments(source: .default)
    }

    // MARK: - Snapshot Listeners

    /**
     Registers a listener that is notified of changes to the results of this query.
     
     The callback is executed on the main thread by default. Use the overload
     that accepts `SnapshotListenOptions` to customize behavior such as executor
     and metadata change delivery.
     
     - Parameter listener: A closure invoked with the latest `QuerySnapshot` or an error.
     - Returns: A `ListenerRegistration` that can be used to remove the listener.
     */
    public func addSnapshotListener(
        _ listener: @escaping (QuerySnapshot?, (any Error)?) -> Void
    ) -> any ListenerRegistration {
        let options = SnapshotListenOptions.Builder()
            .build()
        return addSnapshotListener(options: options, listener: listener)
    }

    /**
     Registers a listener with a simple toggle for metadata change notifications.
     
     - Parameters:
       - includeMetadataChanges: When true, metadata-only changes will trigger callbacks.
       - listener: A closure invoked with the latest `QuerySnapshot` or an error.
     - Returns: A `ListenerRegistration` that can be used to remove the listener.
     */
    public func addSnapshotListener(
        includeMetadataChanges: Bool,
        listener: @escaping (QuerySnapshot?, (any Error)?) -> Void
    ) -> any ListenerRegistration {
        let options = SnapshotListenOptions.Builder()
            .setMetadataChanges(includeMetadataChanges ? .include : .exclude)
            .build()
        return addSnapshotListener(options: options, listener: listener)
    }

    /**
     Registers a listener with the provided `SnapshotListenOptions`.
     
     - Parameters:
       - options: Listener configuration (executor, metadata change delivery).
       - listener: A closure invoked with the latest `QuerySnapshot` or an error.
     - Returns: A `ListenerRegistration` that can be used to remove the listener.
     */
    public func addSnapshotListener(
        options: SnapshotListenOptions,
        listener: @escaping (QuerySnapshot?, (any Error)?) -> Void
    ) -> any ListenerRegistration {
        let wrapped = QueryClosureListener(listener)
        return listenerManager.registerListener(wrapped, options: options)
    }

    // MARK: - Filtering

    /**
     Returns a new query with the provided filter appended.

     - Parameter filter: A filter to apply.
     - Returns: A new `Query` that includes the filter.
     */
    public func whereFilter(_ filter: Filter) -> Query {
        let newQuery = self.copy()
        newQuery._filterArr.append(filter)
        return newQuery
    }

    // MARK: whereField convenience APIs (String-based)

    /// Matches documents where the given field is equal to the provided value.
    public func whereField(_ field: String, isEqualTo value: Any) -> Query {
        return self.whereFilter(Filter.whereField(field, isEqualTo: value))
    }

    /// Matches documents where the given field is not equal to the provided value.
    public func whereField(_ field: String, isNotEqualTo value: Any) -> Query {
        return self.whereFilter(Filter.whereField(field, isNotEqualTo: value))
    }

    /// Matches documents where the given field is greater than the provided value (exclusive).
    public func whereField(_ field: String, isGreaterThan value: Any) -> Query {
        return self.whereFilter(Filter.whereField(field, isGreaterThan: value))
    }

    /// Matches documents where the given field is greater than or equal to the provided value (inclusive).
    public func whereField(_ field: String, isGreaterOrEqualTo value: Any) -> Query {
        return self.whereFilter(Filter.whereField(field, isGreaterOrEqualTo: value))
    }

    /// Matches documents where the given field is less than the provided value (exclusive).
    public func whereField(_ field: String, isLessThan value: Any) -> Query {
        return self.whereFilter(Filter.whereField(field, isLessThan: value))
    }

    /// Matches documents where the given field is less than or equal to the provided value (inclusive).
    public func whereField(_ field: String, isLessThanOrEqualTo value: Any) -> Query {
        return self.whereFilter(Filter.whereField(field, isLessThanOrEqualTo: value))
    }

    /// Matches documents where the given field's value is any of the specified values.
    public func whereField(_ field: String, in values: [Any]) -> Query {
        return self.whereFilter(Filter.whereField(field, in: values))
    }

    /// Matches documents where the given field's value is none of the specified values. 
    public func whereField(_ field: String, notIn values: [Any]) -> Query {
        return self.whereFilter(Filter.whereField(field, notIn: values))
    }

    /// Matches documents where the array field contains the specified value.
    public func whereField(_ field: String, arrayContains value: Any) -> Query {
        return self.whereFilter(Filter.whereField(field, arrayContains: value))
    }

    /// Matches documents where the array field contains any of the specified values.
    public func whereField(_ field: String, arrayContainsAny values: [Any]) -> Query {
        return self.whereFilter(Filter.whereField(field, arrayContainsAny: values))
    }

    /// Matches documents where the field value matches the provided SQL-like pattern (e.g., "%foo%").
    public func whereField(_ field: String, like value: Any) -> Query {
        return self.whereFilter(Filter.whereField(field, like: value))
    }

    /**
     Matches documents where the given field is null.

     The `isNull` flag is provided for readability; its value is ignored.
     */
    public func whereField(_ field: String, isNull: Bool = true) -> Query {
        return self.whereFilter(Filter.whereFieldIsNull(field))
    }

    // MARK: whereField convenience APIs (FieldPath-based)

    /// Matches documents where the given field path is equal to the provided value.
    public func whereField(_ path: FieldPath, isEqualTo value: Any) -> Query {
        return self.whereFilter(Filter.whereField(path.path, isEqualTo: value))
    }

    /// Matches documents where the given field path is not equal to the provided value.
    public func whereField(_ path: FieldPath, isNotEqualTo value: Any) -> Query {
        return self.whereFilter(Filter.whereField(path.path, isNotEqualTo: value))
    }

    /// Matches documents where the given field path is greater than the provided value (exclusive).
    public func whereField(_ path: FieldPath, isGreaterThan value: Any) -> Query {
        return self.whereFilter(Filter.whereField(path.path, isGreaterThan: value))
    }

    /// Matches documents where the given field path is greater than or equal to the provided value (inclusive).
    public func whereField(_ path: FieldPath, isGreaterOrEqualTo value: Any) -> Query {
        return self.whereFilter(Filter.whereField(path.path, isGreaterOrEqualTo: value))
    }

    /// Matches documents where the given field path is less than the provided value (exclusive).
    public func whereField(_ path: FieldPath, isLessThan value: Any) -> Query {
        return self.whereFilter(Filter.whereField(path.path, isLessThan: value))
    }

    /// Matches documents where the given field path is less than or equal to the provided value (inclusive).
    public func whereField(_ path: FieldPath, isLessThanOrEqualTo value: Any) -> Query {
        return self.whereFilter(Filter.whereField(path.path, isLessThanOrEqualTo: value))
    }

    /// Matches documents where the given field path's value is any of the specified values.
    public func whereField(_ path: FieldPath, in values: [Any]) -> Query {
        return self.whereFilter(Filter.whereField(path.path, in: values))
    }

    /// Matches documents where the given field path's value is none of the specified values.
    public func whereField(_ path: FieldPath, notIn values: [Any]) -> Query {
        return self.whereFilter(Filter.whereField(path.path, notIn: values))
    }

    /// Matches documents where the array at the given field path contains the specified value.
    public func whereField(_ path: FieldPath, arrayContains value: Any) -> Query {
        return self.whereFilter(Filter.whereField(path.path, arrayContains: value))
    }

    /// Matches documents where the array at the given field path contains any of the specified values.
    public func whereField(_ path: FieldPath, arrayContainsAny values: [Any]) -> Query {
        return self.whereFilter(Filter.whereField(path.path, arrayContainsAny: values))
    }

    /// Matches documents where the given field path's value matches the provided SQL-like pattern (e.g., "%foo%").
    public func whereField(_ path: FieldPath, like value: Any) -> Query {
        return self.whereFilter(Filter.whereField(path.path, like: value))
    }

    /**
     Matches documents where the given field path is null.

     The `isNull` flag is provided for readability; its value is ignored.
     */
    public func whereField(_ path: FieldPath, isNull: Bool = true) -> Query {
        return self.whereFilter(Filter.whereFieldIsNull(path.path))
    }

    // MARK: - Ordering

    /**
     Returns a query that orders results by the given field (ascending).
     - Parameter field: The field name to order by.
     - Returns: A new `Query` ordered ascending by `field`.
     */
    public func order(by field: String) -> Query {
        let newQuery = self.copy()
        newQuery._orderArr.append(Order(field: field, direction: "asc"))
        return newQuery
    }

    /**
     Returns a query that orders results by the given field.
     - Parameters:
       - field: The field name to order by.
       - descending: When true, results are ordered descending; otherwise ascending.
     - Returns: A new `Query` ordered by `field` with the specified direction.
     */
    public func order(by field: String, descending: Bool) -> Query {
        let newQuery = self.copy()
        let dir = descending ? "desc" : "asc"
        newQuery._orderArr.append(Order(field: field, direction: dir))
        return newQuery
    }

    /**
     Returns a query that orders results by the given field path (ascending).
     - Parameter path: The field path to order by.
     - Returns: A new `Query` ordered ascending by `path`.
     */
    public func order(by path: FieldPath) -> Query {
        let newQuery = self.copy()
        newQuery._orderArr.append(Order(field: path.path, direction: "asc"))
        return newQuery
    }

    /**
     Returns a query that orders results by the given field path.
     - Parameters:
       - path: The field path to order by.
       - descending: When true, results are ordered descending; otherwise ascending.
     - Returns: A new `Query` ordered by `path` with the specified direction.
     */
    public func order(by path: FieldPath, descending: Bool) -> Query {
        let newQuery = self.copy()
        let dir = descending ? "desc" : "asc"
        newQuery._orderArr.append(Order(field: path.path, direction: dir))
        return newQuery
    }

    // MARK: - Limiting

    /**
     Returns a query that limits the number of results.
     - Parameter limit: Maximum number of results to return.
     - Returns: A new `Query` with the limit applied.
     */
    public func limit(to limit: Int) -> Query {
        let newQuery = self.copy()
        newQuery._limit = limit
        return newQuery
    }

    /**
     Returns a query that limits to the last results by reversing sort directions.

     The method inverts the current order array (asc <-> desc) and then applies
     the provided limit.
     - Parameter limit: Maximum number of results to return from the end.
     - Returns: A new `Query` configured to return the final `limit` results.
     */
    public func limitToLast(_ limit: Int) -> Query {
        let newQuery = self.copy()
        newQuery._orderArr = newQuery._orderArr.map { ord in
            let dir = (ord.direction.lowercased() == "asc") ? "desc" : "asc"
            return Order(field: ord.field, direction: dir)
        }
        newQuery._limit = limit
        return newQuery
    }

    // MARK: - Choosing Endpoints

    /**
     Returns a query that starts at the provided document (inclusive).

     - Parameter document: A document whose ordered field value determines the start.
     - Returns: A new `Query` starting at the given document.
     */
    public func start(atDocument document: DocumentSnapshot) -> Query {
        let newQuery = self.copy()

        let field = newQuery._orderArr[0].field
        if let fieldValue = document.get(field) {
            let filter: Filter = Filter(field: field, op: ">=", value: fieldValue)
            newQuery._filterArr.append(filter)
        }
        return newQuery
    }

    /**
     Returns a query that starts at the provided ordered values (inclusive).

     Each value corresponds to the field at the same position in the current
     ordering array.
     - Parameter fieldValues: Ordered values to start at.
     - Returns: A new `Query` starting at the given values.
     */
    public func start(at fieldValues: [Any]) -> Query {
        let newQuery = self.copy()

        for (index, fieldValue) in fieldValues.enumerated() {
            let field = newQuery._orderArr[index].field
            let filter: Filter = Filter(field: field, op: ">=", value: fieldValue)
            newQuery._filterArr.append(filter)
        }
        return newQuery
    }

    /**
     Returns a query that starts strictly after the provided ordered values.

     Each value corresponds to the field at the same position in the current
     ordering array.
     - Parameter fieldValues: Ordered values to start strictly after.
     - Returns: A new `Query` starting after the given values.
     */
    public func start(after fieldValues: [Any]) -> Query {
        let newQuery = self.copy()
        for (index, fieldValue) in fieldValues.enumerated() {
            let field = newQuery._orderArr[index].field
            let filter: Filter = Filter(field: field, op: ">", value: fieldValue)
            newQuery._filterArr.append(filter)
        }
        return newQuery
    }

    /**
     Returns a query that starts strictly after the provided document.

     - Parameter document: A document whose ordered field value determines the start-after point.
     - Returns: A new `Query` starting after the given document.
     */
    public func start(afterDocument document: DocumentSnapshot) -> Query {
        let newQuery = self.copy()
        let field = newQuery._orderArr[0].field
        if let fieldValue = document.get(field) {
            newQuery._filterArr.append(Filter(field: field, op: ">", value: fieldValue))
        }
        return newQuery
    }

    /**
     Returns a query that ends at the provided document (inclusive).

     - Parameter document: A document whose ordered field value determines the end.
     - Returns: A new `Query` ending at the given document.
     */
    public func end(atDocument document: DocumentSnapshot) -> Query {
        let newQuery = self.copy()

        let field = newQuery._orderArr[0].field
        if let fieldValue = document.get(field) {
            let filter: Filter = Filter(field: field, op: "<=", value: fieldValue)
            newQuery._filterArr.append(filter)
        }
        return newQuery
    }

    /**
     Returns a query that ends at the provided ordered values (inclusive).

     Each value corresponds to the field at the same position in the current
     ordering array.
     - Parameter fieldValues: Ordered values to end at.
     - Returns: A new `Query` ending at the given values.
     */
    public func end(at fieldValues: [Any]) -> Query {
        let newQuery = self.copy()

        for (index, fieldValue) in fieldValues.enumerated() {
            let field = newQuery._orderArr[index].field
            let filter: Filter = Filter(field: field, op: "<=", value: fieldValue)
            newQuery._filterArr.append(filter)
        }
        return newQuery
    }

    /**
     Returns a query that ends strictly before the provided ordered values.

     Each value corresponds to the field at the same position in the current
     ordering array.
     - Parameter fieldValues: Ordered values to end strictly before.
     - Returns: A new `Query` ending before the given values.
     */
    public func end(before fieldValues: [Any]) -> Query {
        let newQuery = self.copy()
        for (index, fieldValue) in fieldValues.enumerated() {
            let field = newQuery._orderArr[index].field
            let filter: Filter = Filter(field: field, op: "<", value: fieldValue)
            newQuery._filterArr.append(filter)
        }
        return newQuery
    }

    /**
     Returns a query that ends strictly before the provided document.

     - Parameter document: A document whose ordered field value determines the end-before point.
     - Returns: A new `Query` ending before the given document.
     */
    public func end(beforeDocument document: DocumentSnapshot) -> Query {
        let newQuery = self.copy()
        let field = newQuery._orderArr[0].field
        if let fieldValue = document.get(field) {
            newQuery._filterArr.append(Filter(field: field, op: "<", value: fieldValue))
        }
        return newQuery
    }

    // MARK: - Aggregation

    /**
     A convenience to compute the count of documents matching this query.

     - Returns: An `AggregateQuery` configured to compute the count.
     */
    public var count: AggregateQuery {
        let newQuery = self.copy()
        newQuery._aggFieldArr.append(AggregateField.count())
        return AggregateQuery(query: newQuery)
    }

    /**
     Returns an aggregate query that computes the provided aggregate fields.

     - Parameter aggregateFields: The set of aggregate fields to compute.
     - Returns: An `AggregateQuery` with the provided computations.
     */
    public func aggregate(_ aggregateFields: [AggregateField]) -> AggregateQuery {
        let newQuery = self.copy()
        for elem in aggregateFields {
            newQuery._aggFieldArr.append(elem)
        }
        return AggregateQuery(query: newQuery)
    }

    // MARK: - Copying / Equality

    /**
     Creates a deep copy of this query, including arrays of filters, orderings,
     aggregates, joins, and columns.
     - Returns: A new `Query` with identical configuration.
     */
    func copy() -> Query {
        let newQuery = Query(oracledb: self._Oracledb)

        newQuery._pathSegArr = self._pathSegArr
        newQuery._filterArr = self._filterArr.map { $0.copy() }
        newQuery._orderArr = self._orderArr.map { $0.copy() }
        newQuery._limit = self._limit
        newQuery._aggFieldArr = self._aggFieldArr.map { $0.copy() }
        newQuery._vectorSearch = self._vectorSearch
        newQuery._joins = self._joins
        newQuery._columns = self._columns
        newQuery._isColGroup = self._isColGroup

        return newQuery
    }

    /**
     Compares two queries for structural equality, considering path, filters,
     ordering, joins, columns, and limit.
     */
    static func == (lhs: Query, rhs: Query) -> Bool {
        if lhs._pathSegArr.count != rhs._pathSegArr.count ||
            lhs._filterArr.count != rhs._filterArr.count ||
            lhs._orderArr.count != rhs._orderArr.count ||
            lhs._joins.count != rhs._joins.count ||
            lhs._columns.count != rhs._columns.count {
            return false
        }

        for i in 0..<lhs._pathSegArr.count {
            if lhs._pathSegArr[i] != rhs._pathSegArr[i] {
                return false
            }
        }

        for i in 0..<lhs._filterArr.count {
            if lhs._filterArr[i] != rhs._filterArr[i] {
                return false
            }
        }

        for i in 0..<lhs._orderArr.count {
            if lhs._orderArr[i] != rhs._orderArr[i] {
                return false
            }
        }

        for i in 0..<lhs._joins.count {
            if lhs._joins[i] != rhs._joins[i] {
                return false
            }
        }

        for i in 0..<lhs._columns.count {
            if lhs._columns[i] != rhs._columns[i] {
                return false
            }
        }

        return lhs._limit == rhs._limit
    }

    // MARK: - Joins

    /**
     Returns a query that includes the provided join view name.

    - Parameter viewName: The backend view name to join with.
    - Returns: A new `Query` including the join.
     */
    public func join(viewName: String) -> Query {
        let newQuery = self.copy()
        newQuery._joins.append(viewName)
        return newQuery
    }

    // MARK: - Columns

    /**
     Specifies columns to return in the query.

     - Parameter fields: The list of column names to select.
     - Returns: A new Query with the specified columns.
     */
    public func column(_ fields: [String]) -> Query {
        let newQuery = self.copy()
        newQuery._columns = fields
        return newQuery
    }
}
