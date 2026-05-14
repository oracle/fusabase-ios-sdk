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

/// An enumeration that specifies the source from which to retrieve document data.
public enum OracledbSource {
    /// Retrieve data from the server. This is the default behavior.
    case server
    /// Attempt to retrieve data from the server, but fall back to the cache if the server is unavailable.
    case `default`
}

/// A reference to a single document within a collection.
///
/// DocumentReference provides CRUD operations (set, update, delete),
/// read operations (get), and snapshot listener registration to observe
/// real-time updates to the targeted document.
public class DocumentReference : @unchecked Sendable, Equatable {

    /// Identifies the reference type for diagnostics and debugging.
    var type: String = "document"

    // -------------  Storage

    /// The associated database instance.
    private var _Oracledb: FusabaseOracledb
    /// The parent collection of this document reference.
    private var _parent: CollectionReference
    /// The absolute slash-separated path for this document.
    private var _path: String
    /// The document identifier (OID).
    private var _documentID: String
    /// The document version.
    private var _version: String?
    /// Helper responsible for executing RPC/HTTP/WebSocket operations.
    private var _queryHelper: QueryHelper


    // Listener manager for DocumentReference -> DocumentSnapshot events.
    private lazy var listenerManager: ListenerManager<DocumentReference, DocumentSnapshot> = {
        return ListenerManager(oradb: self._Oracledb, ref: self)
    }()

    /// Closure-backed adapter to turn a simple closure into an EventListener<DocumentSnapshot>.
    private final class DocumentClosureListener: EventListener {
        typealias T = DocumentSnapshot
        private let onEventBlock: (DocumentSnapshot?, Error?) -> Void

        init(_ onEvent: @escaping (DocumentSnapshot?, Error?) -> Void) {
            self.onEventBlock = onEvent
        }

        func onEvent(_ value: DocumentSnapshot?, _ error: Error?) {
            onEventBlock(value, error)
        }
    }

    // -------------  Public getters

    /// The parent collection reference of this document reference.
    public var parent: CollectionReference {
        get {
            return _parent
        }
    }

    /// The database instance associated with this document reference.
    public var oracledb: FusabaseOracledb {
        get {
            return _Oracledb
        }
    }

    /// The absolute path of this document reference (e.g., "collection/OID").
    public var path: String {
        get {
            return _path
        }
    }

    /// The document identifier (OID) for this reference.
    public var documentID: String {
        get {
            return _documentID
        }
    }

    /// The internal query helper used to perform operations for this reference.
    internal var queryHelper: QueryHelper {
        get {
            return _queryHelper
        }
    }

    // MARK: - Internal metadata propagation

    /// Applies server-returned metadata from a write response.
    ///
    /// The backend may return:
    /// - `OID` (required on success)
    /// - `VERSION` (optional)
    /// - `_metadata.etag` (optional; preferred over VERSION when present)
    ///
    /// This method is intentionally tolerant to value types (`String`, `Int`, `NSNumber`, `Double`).
    internal func applyWriteResult(_ result: [String: Any]) {
        // OID can be returned as OID or oid
        if let oid = DocumentReference.parseFlexibleString(result["OID"] ?? result["oid"]) {
            if oid != self._documentID {
                self._documentID = oid

                // Android parity path sync:
                // - If the current path ends with a temp id (BAAS_DOC_TEMP_ID=...), replace that segment with oid.
                // - Else if the current path already looks like a document path, replace the last segment.
                // - Else (collection-only path), append oid.
                var segments = self._path.split(separator: "/").map(String.init)
                if segments.isEmpty {
                    self._path = oid
                } else if let last = segments.last, last.contains("BAAS_DOC_TEMP_ID=") {
                    segments[segments.count - 1] = oid
                    self._path = segments.joined(separator: "/")
                } else if segments.count % 2 == 0 {
                    // Document-shaped path (collection/doc/...)
                    segments[segments.count - 1] = oid
                    self._path = segments.joined(separator: "/")
                } else {
                    // Collection-shaped path (collection/subcollection/...)
                    segments.append(oid)
                    self._path = segments.joined(separator: "/")
                }
            }
        }

        // Prefer _metadata.etag if present, otherwise VERSION/version
        var versionCandidate: Any?
        if let meta = result["_metadata"] as? [String: Any], let etag = meta["etag"] {
            versionCandidate = etag
        } else {
            versionCandidate = result["VERSION"] ?? result["version"]
        }
        if let versionStr = DocumentReference.parseFlexibleString(versionCandidate) {
            self._version = versionStr
        }
    }

    /// Parses a loosely-typed JSON value into a String.
    /// - Note: For `Double`, if the value is integer-like, it is formatted without a decimal.
    private static func parseFlexibleString(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let s = value as? String { return s }
        if let i = value as? Int { return String(i) }
        if let i64 = value as? Int64 { return String(i64) }
        if let n = value as? NSNumber {
            // NSNumber can represent Bool too; avoid turning true/false into 1/0 for OID/version
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return nil }
            return n.stringValue
        }
        if let d = value as? Double {
            if d.rounded(.towardZero) == d {
                return String(Int64(d))
            }
            return String(d)
        }
        return String(describing: value)
    }

    // -------------  Init

    /**
     Initializes a new DocumentReference instance.

     This initializer expects a valid document path. If a parent collection is not provided,
     one is derived from the path.

     - Parameters:
       - oracledb: The database instance to associate with this reference.
       - path: The absolute path for the document reference (e.g., "collection/OID").
       - parent: Optional parent collection reference. If omitted, a CollectionReference is derived from `path`.
     */
    init(oracledb: FusabaseOracledb, path: String, parent: CollectionReference? = nil) {

        // If the user is not providing any OID, we can use '$_random_$' for auto-id generation
        // let checkedPath = path.isEmpty ? "$_random_$" : path
        // let trimmedPath = checkedPath.trimmingCharacters(in: .whitespacesAndNewlines)
        // var tokens = trimmedPath.components(separatedBy: "/")

        var tokens = path.components(separatedBy: "/")
        OracledbLogger.debug("DocumentReference init with tokens: \(tokens)")

        // Path shape validation (disabled by design at the moment)
        // if (tokens.count % 2 == 1) {
        //     fatalError("Invalid path. Path should point to a valid Document Reference")
        // }

        self._Oracledb = oracledb
        self._documentID = tokens.removeLast()

        // If a parent is passed, assign it. Otherwise derive a collection reference.
        if (parent != nil) {
            self._parent = parent!
        } else {
            self._parent = CollectionReference(oracledb: oracledb, path: path)
        }

        self._path = path
        self._queryHelper = QueryHelper(options: oracledb.app.options, oradb: oracledb)
    }

    // MARK: - Equality

    /**
     Determines whether this document reference points to the same document as another.

     - Parameter docRef: The other document reference to compare against.
     - Returns: `true` if both references point to the same path and document id; otherwise `false`.
     */
    public func isEqual(to docRef: DocumentReference) -> Bool {
        return self.documentID == docRef.documentID && self.path == docRef.path
    }

    // MARK: - Hierarchy

    /**
     Gets a `CollectionReference` referring to the specified path, relative to this document.

     - Parameter collectionPath: The subcollection path relative to this document.
     - Returns: A `CollectionReference` for the specified subcollection.
     */
    public func collection(_ collectionPath: String) -> CollectionReference {
        return CollectionReference(oracledb: self.oracledb, path: self.path + "/" + collectionPath, parent: self)
    }

    // MARK: - Deletes

    /**
     Deletes the document referred to by this DocumentReference.

     Executes asynchronously using Swift Concurrency. The completion handler is invoked
     on task completion.

     - Parameter completion: A closure receiving an optional error if the operation fails.
     */
    @available(macOS 10.15.0, *)
    public func delete(completion: @escaping (Error?) -> Void) {
        Task {
            do {
                try await self.delete()
                completion(nil)
            } catch let err as NSError {
                completion(err)
            } catch {
                completion(NSError(domain: "oracledb", code: 9999, userInfo: nil))
            }
        }
    }

    /**
     Deletes the document referred to by this DocumentReference.

     - Throws: An error if the delete operation fails.
     */
    @available(macOS 10.15.0, *)
    public func delete() async throws {
        let result = try await self.queryHelper.deleteDocument(docRef: self)
        self.applyWriteResult(result)
    }

    // MARK: - Writes (Async)

    /**
     Sanitizes document data by converting nil values to NSNull.
     */
    private func sanitizeDocumentData(_ data: [String: Any?]) -> [String: Any] {
        return data.mapValues { $0 != nil ? $0! : NSNull() }
    }

    /**
     Writes to the document referred to by this DocumentReference.

     If the document doesn't yet exist, this method creates it and then sets the data.
     If the document exists, this method overwrites the document data with the new values.

     - Parameter documentData: A dictionary with the fields and data to write. Nil values are converted to NSNull.
     - Throws: An error if the operation fails.
     */
    @available(macOS 10.15.0, *)
    public func setData(_ documentData: [String : Any?]) async throws {
        let sanitizedData = sanitizeDocumentData(documentData)
        let result = try await self.queryHelper.setDocument(docRef: self, docData: sanitizedData, merge: false)
        self.applyWriteResult(result)
    }

    /**
     Writes to the document referred to by this DocumentReference.

     If the document does not yet exist, it will be created. If you pass `merge: true`,
     the provided data will be merged into any existing document.

     - Parameters:
       - documentData: A dictionary with the fields and data to write. Nil values are converted to NSNull.
       - merge: When `true`, merge into the existing document; otherwise overwrite.
     - Throws: An error if the operation fails.
     */
    @available(macOS 10.15.0, *)
    public func setData(_ documentData: [String : Any?], merge: Bool) async throws {
        let sanitizedData = sanitizeDocumentData(documentData)
        let result = try await self.queryHelper.setDocument(docRef: self, docData: sanitizedData, merge: merge)
        self.applyWriteResult(result)
    }

    /**
     Writes to the document referred to by this DocumentReference and only replaces the fields specified under `mergeFields`.

     Any field that is not specified in `mergeFields` is ignored and remains untouched.
     If the document doesn't yet exist, this method creates it and then sets the data.

     - Parameters:
       - documentData: A dictionary with the fields and data to write. Nil values are converted to NSNull.
       - mergeFields: An array of field names (String) specifying which fields to merge.
     - Throws: An error if the operation fails.
     */
    @available(macOS 10.15.0, *)
    public func setData(_ documentData: [String : Any?], mergeFields: [Any]) async throws {
        let sanitizedData = sanitizeDocumentData(documentData)
        let stringMergeFields = mergeFields.compactMap { $0 as? String }
        let result = try await self.queryHelper.setDocument(docRef: self, docData: sanitizedData, merge: true, mergeFields: stringMergeFields)
        self.applyWriteResult(result)
    }

    // MARK: - Reads (Async)

    /**
     Retrieves the document snapshot with a source option.

     At present, `source` is accepted for API parity and may not alter server selection.

     - Parameter source: Desired fetch source.
     - Returns: A `DocumentSnapshot` for this document.
     - Throws: An error if the fetch fails.
     */
    @available(macOS 10.15.0, *)
    func getDocument(source: OracledbSource) async throws -> DocumentSnapshot {
        // For now, ignore source and just fetch
        return try await getDocument()
    }

    // MARK: - Writes (Fire-and-forget wrappers)

    /**
     Writes to the document referred to by this DocumentReference (overwrites).

     This is a convenience wrapper around the async API. Errors are logged.

     - Parameter documentData: A dictionary that contains the fields and data to write.
     */
    @available(macOS 10.15.0, *)
    public func setData(_ documentData: [String: Any]) {
        Task {
            do {
                let result = try await self.queryHelper.setDocument(docRef: self, docData: documentData, merge: false)
                self.applyWriteResult(result)
            } catch {
                // Handle error - in a real implementation, this might need error handling
                OracledbLogger.error("Failed to set document data: \(error)")
            }
        }
    }

    /**
     Writes to the document referred to by this DocumentReference (merge or overwrite).

     This is a convenience wrapper around the async API. Errors are logged.

     - Parameters:
       - documentData: A dictionary that contains the fields and data to write.
       - merge: Whether to merge the provided data into any existing document.
     */
    @available(macOS 10.15.0, *)
    public func setData(_ documentData: [String : Any], merge: Bool) {
        Task {
            do {
                let result = try await self.queryHelper.setDocument(docRef: self, docData: documentData, merge: merge)
                self.applyWriteResult(result)
            } catch {
                OracledbLogger.error("Failed to set document data with merge: \(error)")
            }
        }
    }

    /**
     Writes to the document referred to by this DocumentReference (mergeFields).

     This is a convenience wrapper around the async API. Errors are logged.

     - Parameters:
       - documentData: A dictionary containing the fields to write.
       - mergeFields: An array of String or FieldPath elements specifying which fields to merge.
     */
    @available(macOS 10.15.0, *)
    public func setData(_ documentData: [String : Any], mergeFields: [Any]) {
        // Convert [Any] to [String] for merge fields, filtering out non-string values
        let stringMergeFields = mergeFields.compactMap { $0 as? String }

        Task {
            do {
                let result = try await self.queryHelper.setDocument(docRef: self, docData: documentData, merge: true, mergeFields: stringMergeFields)
                self.applyWriteResult(result)
            } catch {
                OracledbLogger.error("Failed to set document data with merge fields: \(error)")
            }
        }
    }

    // MARK: - Updates

    /**
     Updates fields in the document referred to by this DocumentReference.

     If the document does not exist, the update fails.

     - Parameter fields: A dictionary of field/value pairs to update. Keys may be `String` or `FieldPath`.
     - Throws: An error if the update fails.
     */
    @available(macOS 10.15.0, *)
    public func updateData(_ fields: [AnyHashable : Any]) async throws {
        let result = try await self.queryHelper.updateDocument(docRef: self, fields: fields)
        self.applyWriteResult(result)
    }

    // MARK: - Retrieving Data

    /**
     Retrieves the document snapshot from Oracledb.

     - Note: This is an asynchronous function.
     - Returns: A `DocumentSnapshot` representing the fetched document. Returns an empty snapshot if not found.
     - Throws: An error if the document retrieval fails.
     */
    @available(macOS 10.15.0, *)
    public func getDocument() async throws -> DocumentSnapshot {
        do {
            let promJson = try await self.queryHelper.fetchDocuments(ref: self)
            let metadata = SnapshotMetadata(fromCache: false, hasPendingWrites: false)

            OracledbLogger.debug("Fetched promJson: \(promJson)")

            if !promJson.isEmpty {
                if let retArr = promJson["ret"] as? [[String: Any]], let firstElem = retArr.first {
                    if !firstElem.isEmpty {
                        if let osonsData = firstElem["osons"] as? [String: Any] {
                            // Unwrap the DOCUMENT key for standard documents
                            var docData = osonsData
                            if let documentDict = osonsData["DOCUMENT"] as? [String: Any] {
                                docData = documentDict
                            }
                            return DocumentSnapshot(data: docData, docRef: self, metadata: metadata)
                        } else {
                            OracledbLogger.error("osons not a key, or not a [String: Any] dict")
                        }
                    } else {
                        OracledbLogger.error("firstElem is empty")
                    }
                } else {
                    OracledbLogger.error("'ret' key is missing, not an array of dictionaries, or empty.")
                }
            }
            return DocumentSnapshot(data: nil, docRef: self, exists: false)
        } catch let err as NSError {
            // Map 403 (unauthorized) and 404 (not found) to an empty snapshot with exists == false
            if err.domain == OracledbErrors.OracledbErrorDomain &&
                (err.code == OracledbErrorCode.unauthorized.rawValue || err.code == OracledbErrorCode.notFound.rawValue) {
                OracledbLogger.info("getDocument: returning empty snapshot for HTTP status \(err.code)")
                return DocumentSnapshot(data: nil, docRef: self, exists: false)
            }
            throw err
        }
    }

    // MARK: - Utilities

    /**
     Safely wraps a DocumentReference into a specific subclass.

     - Parameter documentReference: The reference to cast.
     - Returns: The casted reference as `Self`.
     - Throws: `DocumentReferenceError.invalidDocumentReferencePath` if the cast fails.
     */
    public func wrap(_ documentReference: DocumentReference) throws -> Self {
        guard let casted = documentReference as? Self else {
            throw DocumentReferenceError.invalidDocumentReferencePath
        }
        return casted
    }

    // MARK: - Snapshot Listeners

    /**
     Registers a listener for this document with a simple toggle for metadata change notifications.

     The callback is executed on the main thread by default.

     - Parameters:
       - includeMetadataChanges: When `true`, metadata-only changes will trigger callbacks.
       - listener: A closure invoked with the latest `DocumentSnapshot` or an error.
     - Returns: A `ListenerRegistration` that can be used to remove the listener.
     */
    public func addSnapshotListener(includeMetadataChanges: Bool, listener: @escaping (DocumentSnapshot?, (any Error)?) -> Void) -> any ListenerRegistration {
        let options = SnapshotListenOptions.Builder()
            .setMetadataChanges(includeMetadataChanges ? .include : .exclude)
            .build()
        return addSnapshotListener(options: options, listener: listener)
    }

    /**
     Registers a listener for this document using the provided `SnapshotListenOptions`.

     - Parameters:
       - options: Listener configuration (executor, metadata change delivery).
       - listener: A closure invoked with the latest `DocumentSnapshot` or an error.
     - Returns: A `ListenerRegistration` that can be used to remove the listener.
     */
    public func addSnapshotListener(options: SnapshotListenOptions, listener: @escaping (DocumentSnapshot?, (any Error)?) -> Void) -> any ListenerRegistration {
        let wrapped = DocumentClosureListener(listener)
        return listenerManager.registerListener(wrapped, options: options)
    }

    // MARK: - Static

    /**
     Compares two DocumentReference instances for equality.

     Two references are equal if their parent, path, and document ID match.

     - Parameters:
       - lhs: The left-hand side reference.
       - rhs: The right-hand side reference.
     - Returns: `true` if both references are equal; otherwise, `false`.
     */
    public static func == (lhs: DocumentReference, rhs: DocumentReference) -> Bool {
        return lhs._parent == rhs._parent && lhs._path == rhs._path && lhs._documentID == rhs._documentID
    }
}

/// Conformance to `Reference` protocol exposing the `path` property.
extension DocumentReference: Reference {}
