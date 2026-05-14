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

/// Represents the results of a query operation, containing a list of documents
/// that match the query along with metadata about the query execution.
/// Provides access to the documents and any changes since the last query execution.
public class QuerySnapshot: Snapshot {

    // MARK: - Stored properties

    /// The query that produced this snapshot.
    var _query: Query

    /// The metadata associated with this snapshot.
    var _metadata: SnapshotMetadata

    /// The list of document snapshots that match the query.
    var _documents: [QueryDocumentSnapshot]

    /// The list of document changes since the last snapshot (computed when created with an old snapshot).
    private var _documentChanges: [DocumentChange] = []

    // MARK: - Public accessors (Swift-Doc)

    /// The query that produced this snapshot.
    public var query: Query {
        return _query
    }

    /// The metadata associated with this snapshot.
    public var metadata: SnapshotMetadata {
        return _metadata
    }

    /// Indicates whether this snapshot contains no documents.
    public var isEmpty: Bool {
        return _documents.isEmpty
    }

    /// Gets the number of documents in this snapshot.
    public var count: Int {
        return _documents.count
    }

    /// Gets the list of all documents in this snapshot.
    public var documents: [QueryDocumentSnapshot] {
        return _documents
    }


    /// Returns the list of document changes since the previous snapshot (if provided at construction).
    /// - Returns: An array of DocumentChange entries describing additions, modifications, and removals.
    public func documentChanges() -> [DocumentChange] {
        return _documentChanges
    }

    // MARK: - Initializers

    /// Constructs a QuerySnapshot from an array of document snapshots (used by existing code paths).
    /// - Parameters:
    ///   - snaps: The list of query document snapshots.
    ///   - query: The query that produced this snapshot.
    ///   - metadata: The snapshot metadata.
    init(snaps: [QueryDocumentSnapshot], query: Query, metadata: SnapshotMetadata) {
        self._documents = snaps
        self._query = query
        self._metadata = metadata
        self._documentChanges = []
    }

    /// Constructs a QuerySnapshot from polling/query data. Computes document changes by comparing with an old snapshot if provided.
    ///
    /// - Parameters:
    ///   - query: The query that produced this snapshot.
    ///   - oldSnap: The previous snapshot for change detection, or nil.
    ///   - data: The backend response payload (e.g., contains "ret": [ { "osons": { ... } }, ... ]).
    init(query: Query, oldSnap: QuerySnapshot?, data: [String: Any]) {
        self._query = query
        self._metadata = SnapshotMetadata(fromCache: false, hasPendingWrites: false)
        self._documents = QuerySnapshot.buildQueryDocSnaps(from: data, query: query, metadata: self._metadata)
        self._documentChanges = QuerySnapshot.computeChanges(newDocs: self._documents, oldSnap: oldSnap)
    }

    // MARK: - Helpers (builders)

    /// Builds QueryDocumentSnapshot array from the backend payload.
    /// - Parameters:
    ///   - payload: The response dictionary.
    ///   - query: The query generating these documents.
    ///   - metadata: Metadata to attach to each document snapshot.
    /// - Returns: Array of QueryDocumentSnapshot.
    private static func buildQueryDocSnaps(from payload: [String: Any],
                                           query: Query,
                                           metadata: SnapshotMetadata) -> [QueryDocumentSnapshot] {
        var snaps: [QueryDocumentSnapshot] = []

        guard let retArr = payload["ret"] as? [[String: Any]] else {
            OracledbLogger.warning("QuerySnapshot: payload missing 'ret' array")
            return snaps
        }

        let colPath = query.path
        let colRef = CollectionReference(oracledb: query.oracledb, path: colPath)

        for elem in retArr {
            guard let osons = elem["osons"] as? [String: Any] else {
                OracledbLogger.warning("QuerySnapshot: 'osons' missing or invalid in element")
                continue
            }
            // OID may be under "OID" or "oid"
            let oid = (osons["OID"] as? String) ?? (osons["oid"] as? String) ?? ""
            if oid.isEmpty {
                OracledbLogger.warning("QuerySnapshot: missing document OID; skipping element")
                continue
            }

            let docRef = DocumentReference(oracledb: query.oracledb,
                                           path: colRef.path + "/" + oid,
                                           parent: colRef)
            let docSnap = QueryDocumentSnapshot(data: osons, docRef: docRef, metadata: metadata)
            snaps.append(docSnap)
        }

        return snaps
    }

    /// Computes document changes between an old and a new set of QueryDocumentSnapshots.
    /// - Parameters:
    ///   - newDocs: The new list of document snapshots.
    ///   - oldSnap: The previous snapshot or nil.
    /// - Returns: List of DocumentChange instances.
    private static func computeChanges(newDocs: [QueryDocumentSnapshot], oldSnap: QuerySnapshot?) -> [DocumentChange] {
        var changes: [DocumentChange] = []

        // Index maps for efficient lookups
        var newIndexById: [String: Int] = [:]
        var oldIndexById: [String: Int] = [:]
        var oldById: [String: QueryDocumentSnapshot] = [:]

        for (idx, doc) in newDocs.enumerated() {
            newIndexById[id(of: doc)] = idx
        }

        if let old = oldSnap {
            for (idx, doc) in old.documents.enumerated() {
                let docId = id(of: doc)
                oldIndexById[docId] = idx
                oldById[docId] = doc
            }
        }

        if oldSnap == nil {
            // No previous snapshot: all are ADDED
            for (idx, doc) in newDocs.enumerated() {
                let change = DocumentChange(type: .added,
                                            document: doc,
                                            oldIndex: UInt.max,
                                            newIndex: UInt(idx))
                changes.append(change)
            }
            return changes
        }

        // With previous snapshot, compute ADDED/MODIFIED and REMOVED
        for (idx, doc) in newDocs.enumerated() {
            let docId = id(of: doc)
            if let oldDoc = oldById[docId] {
                // Compare lastModified; fall back to data equality if needed
                let oldLM = lastModified(of: oldDoc)
                let newLM = lastModified(of: doc)
                if oldLM != newLM {
                    let oldIdx = oldIndexById[docId].map { UInt($0) } ?? UInt.max
                    let change = DocumentChange(type: .modified,
                                                document: doc,
                                                oldIndex: oldIdx,
                                                newIndex: UInt(idx))
                    changes.append(change)
                }
            } else {
                // Newly added
                let change = DocumentChange(type: .added,
                                            document: doc,
                                            oldIndex: UInt.max,
                                            newIndex: UInt(idx))
                changes.append(change)
            }
        }

        // Removed documents (present in old, missing in new)
        for (oldId, oldIdx) in oldIndexById {
            if newIndexById[oldId] == nil, let oldDoc = oldById[oldId] {
                let change = DocumentChange(type: .removed,
                                            document: oldDoc,
                                            oldIndex: UInt(oldIdx),
                                            newIndex: UInt.max)
                changes.append(change)
            }
        }

        return changes
    }

    /// Extracts the document identifier from a QueryDocumentSnapshot.
    private static func id(of snap: QueryDocumentSnapshot) -> String {
        // DocumentSnapshot.documentID is internal and accessible within the module
        return snap.documentID
    }

    /// Extracts the lastModified string from a QueryDocumentSnapshot if available.
    private static func lastModified(of snap: QueryDocumentSnapshot) -> String {
        return snap.lastModifiedString()
    }
}

// MARK: - Sequence conformance

extension QuerySnapshot: Sequence {
    public func makeIterator() -> IndexingIterator<[QueryDocumentSnapshot]> {
        return documents.makeIterator()
    }
}
