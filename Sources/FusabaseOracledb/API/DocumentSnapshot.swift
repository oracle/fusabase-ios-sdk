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

/// An enumeration that specifies how server timestamps in the document are handled when decoding.
enum ServerTimestampBehavior: CustomStringConvertible {
    /// Server timestamps that have not yet been set to their final value will be returned as NSNull.
    case none

    var description: String {
        switch self {
        case .none: return "none"
        }
    }
}

/// A decoder for Oracledb documents that handles the conversion from document data to Decodable types.
class OracledbDecoder {
    /// Initializes a new Oracledb decoder.
    init() {}

    /// Decodes the given value to the specified type.
    /// - Parameters:
    ///   - type: The type to decode to.
    ///   - value: The value to decode.
    /// - Returns: The decoded value.
    /// - Throws: An error if decoding fails.
    func decode<T: Decodable>(_ type: T.Type, from value: Any) throws -> T {
        let jsonData: Data
        if let dict = value as? [String: Any] {
            jsonData = try JSONSerialization.data(withJSONObject: dict, options: [])
        } else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "Expected dictionary, got \(String(describing: value))"))
        }

        let decoder = JSONDecoder()
        return try decoder.decode(type, from: jsonData)
    }
}

/// A read-only snapshot of a single document's data and metadata.
///
/// DocumentSnapshot provides access to a document's fields at a specific
/// point in time along with associated SnapshotMetadata. When a document
/// does not exist, data() returns nil and exists is false.
/// Use get(_:) to read a single field by key, and data(as:) to decode
/// into a Decodable model.
///
/// Instances are normally produced by DocumentReference.getDocument(),
/// Query.getDocuments(), and listener events.
public class DocumentSnapshot: Snapshot {
    private var doc: Document? {
        didSet { self._exists = (self.doc != nil) }
    }
    private var _data: [String: Any]?
    private var _metadata: SnapshotMetadata
    private var _docRef: DocumentReference
    private var _exists: Bool = false

    private static let logger = Logger(subsystem: "com.oracle.database.fusabase.oracledb", category: "DocumentSnapshot")
    
    public var exists: Bool {
        get { _exists }
        set { _exists = newValue }
    }
    
    public var reference: DocumentReference {
        get {
            return self._docRef
        }
    }

    public var documentID: String {
        get {
            return self._docRef.documentID
        }
    }

    public var metadata: SnapshotMetadata {
        get {
            return self._metadata
        }
    }
    

    init(data: [String: Any]?, docRef: DocumentReference, metadata: SnapshotMetadata = SnapshotMetadata(fromCache: false, hasPendingWrites: false), exists: Bool = true) {
        self._docRef = docRef
        self._metadata = metadata
        self._exists = exists

        // Accept either Oracle "osons" payload (with a DOCUMENT key) or a flat document map.
        if let input = data {
            let normalized = DataReader.getJsonObjectDataInMap(input)

            if let documentMap = normalized["DOCUMENT"] as? [String: Any] {
                // osons-shaped payload
                let meta = normalized["_metadata"] as? [String: Any]
                let created = (normalized["CREATED"] as? String) ?? ""
                let lastModified = (normalized["LAST_MODIFIED"] as? String) ?? ""
                // Prefer _metadata.etag if present, otherwise fallback to VERSION
                let versionStr: String = (meta?["etag"] as? String)
                    ?? (normalized["VERSION"] as? String)
                    ?? ((normalized["VERSION"] as? Int).map { String($0) })
                    ?? ((normalized["VERSION"] as? Int64).map { String($0) })
                    ?? ""

                let oid = (normalized["OID"] as? String)
                    ?? (normalized["oid"] as? String)
                    ?? docRef.documentID
                let index = normalized["INDEX"] as? Int
                let pathSegments = docRef.path.split(separator: "/").map(String.init)
                let rowId = (normalized["ROWID"] as? String) ?? (normalized["rowId"] as? String) ?? ""

                self.doc = Document(
                    data: documentMap,
                    objectId: oid,
                    created: created,
                    lastModified: lastModified,
                    version: versionStr,
                    index: index,
                    path: pathSegments,
                    rowId: rowId
                )

                // Return only the document fields (no SDK-internal metadata).
                self._data = documentMap

                OracledbLogger.debug("Initialized DocumentSnapshot (osons) with Document id: \(oid)")
            } else {
                // Flat document map: absorb directly; infer metadata from well-known keys
                let meta = normalized["_metadata"] as? [String: Any]
                let created = (normalized["CREATED"] as? String) ?? ""
                let lastModified = (normalized["LAST_MODIFIED"] as? String) ?? ""
                // Prefer _metadata.etag if present
                let versionStr: String = (meta?["etag"] as? String)
                    ?? (normalized["VERSION"] as? String)
                    ?? ((normalized["VERSION"] as? Int).map { String($0) })
                    ?? ((normalized["VERSION"] as? Int64).map { String($0) })
                    ?? ""

                let oid = (normalized["oid"] as? String)
                    ?? (normalized["OID"] as? String)
                    ?? docRef.documentID
                let index = normalized["INDEX"] as? Int
                let pathSegments = docRef.path.split(separator: "/").map(String.init)
                let rowId = (normalized["ROWID"] as? String) ?? (normalized["rowId"] as? String) ?? ""

                // Build fields map by stripping reserved keys from the flat map
                var fields = normalized
                for k in ["oid", "OID", "CREATED", "LAST_MODIFIED", "_metadata", "VERSION", "INDEX", "ROWID", "rowId"] {
                    fields.removeValue(forKey: k)
                }

                self.doc = Document(
                    data: fields,
                    objectId: oid,
                    created: created,
                    lastModified: lastModified,
                    version: versionStr,
                    index: index,
                    path: pathSegments,
                    rowId: rowId
                )

                // Return only the document fields (no SDK-internal metadata).
                self._data = fields

                OracledbLogger.debug("Initialized DocumentSnapshot (flat) with Document id: \(oid)")
            }
        } else {
            OracledbLogger.error("osons data is nil, initializing empty snapshot")
            self.doc = nil
            self._data = nil
            // keep _exists value as passed-in (default true), caller should pass exists: false for non-existent docs
        }
    }
    
    /**
        Retrieves all fields in the document as a Dictionary object. Returns nil if the object doesn't exist.
        - Returns : Dictionary object containing all fields in the object.
     */
    public func data() -> [String: Any]? {
        return self._data
    }
    
    /**
    Retrieves the value associated with the given field key.
      - Note it suggests that the parameter isn't strictly limited to String. However, in Oracledb’s actual behavior, field names (keys) are always String

      - Parameter field: The key whose value needs to be fetched. Must be a `String`.
      - Returns: The value associated with the field, or `nil` if the key is invalid or doesn't exist.
    */
    public func get(_ field: Any) -> Any? {
        guard let key = field as? String else {
            OracledbLogger.error("Field key must be a String")
            return nil
        }
        // First try user document fields (supports dot paths)
        if let val = self.doc?.getField(FieldPath(dotPath: key)) {
            return val
        }
        // Fallback to augmented data (e.g., _documentInfo)
        return valueForDotPath(key, in: self._data)
    }

    /// Retrieves a specific field from the document.
    ///
    /// - Parameter key: The field to retrieve.
    /// - Returns: The value contained in the field or nil if the document or field doesn't exist.
    public subscript(key: Any) -> Any? {
        get {
            return get(key)
        }
    }

    /// Retrieves all fields in a document and converts them to an instance of caller-specified type.
    ///
    /// By default, server-provided timestamps that have not yet been set to their final value will be returned as NSNull. Pass serverTimestampBehavior to configure this behavior.
    ///
    /// See Oracledb.Decoder for more details about the decoding process.
    ///
    /// - Parameters:
    ///   - type: The type to convert the document to.
    ///   - serverTimestampBehavior: Configuration for how server timestamps are handled when decoding. Defaults to `.none`.
    ///   - decoder: The decoder instance to use for decoding. Defaults to a new Oracledb.Decoder instance.
    /// - Returns: An instance of the specified type containing the document data.
    /// - Throws: An error if decoding fails or if the document doesn't exist.
    func data<T: Decodable>(as type: T.Type,
                            with serverTimestampBehavior: ServerTimestampBehavior = .none,
                            decoder: OracledbDecoder = OracledbDecoder()) throws -> T {
        guard let documentData = doc?.getData() else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "Document does not exist"))
        }

        // Handle server timestamp behavior
        var processedData = documentData
        if serverTimestampBehavior != .none {
            // In a real implementation, this would process server timestamps based on the behavior
            // For now, we just pass through the data
            OracledbLogger.debug("Server timestamp behavior '\(serverTimestampBehavior)' specified but not fully implemented")
        }

        return try decoder.decode(type, from: processedData)
    }

    /// Internal accessor for lastModified metadata (not exposed via data()).
    internal func lastModifiedString() -> String {
        return self.doc?.getLastModified() ?? ""
    }

    /// Internal realtime identity used to reject stale notification frames.
    internal func realtimeRowID() -> String {
        return self.doc?.getRowId() ?? ""
    }

    internal func realtimeVersion() -> String {
        return self.doc?.getVersion() ?? ""
    }

    // MARK: - Helpers

    /// Returns a value from a nested dictionary (and arrays) using dot-path notation.
    /// Supports array indices in the path (e.g. "items.0.name").
    private func valueForDotPath(_ path: String, in dict: [String: Any]?) -> Any? {
        var current: Any? = dict
        let segments = path.split(separator: ".").map(String.init)
        for seg in segments {
            if let d = current as? [String: Any] {
                current = d[seg]
            } else if let arr = current as? [Any], let idx = Int(seg), idx >= 0, idx < arr.count {
                current = arr[idx]
            } else {
                return nil
            }
        }
        return current
    }
}
