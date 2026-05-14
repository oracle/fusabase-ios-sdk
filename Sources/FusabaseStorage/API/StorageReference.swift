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
import UniformTypeIdentifiers


/// A reference to an object or folder path in Fusabase Storage.
///
/// StorageReference is a lightweight handle to a location within a storage bucket. It provides
/// methods to navigate the hierarchy (root/parent/child), generate download URLs, list items,
/// and read or update metadata. Instances are safe to pass across threads.
@available(iOS 15, tvOS 13, macOS 10.15, watchOS 7, *)
/**
 A StorageReference represents a reference to an OCI Storage / DBFS object.

 You can use it to upload, download, and delete objects, as well as get/set object metadata.
 */

public class StorageReference {
    
    /// The Storage client that created or owns this reference.
    public private(set) var storage: Storage
    /// The parent reference of this location, or nil if this is the root.
    public private(set) var _parent: StorageReference? = nil
    /// The full path of this location, relative to the bucket root. Never begins with a leading slash.
    public private(set) var fullPath: String = ""
    /// The bucket name associated with this reference, when available.
    public private(set) var bucket: String = ""
    /// The last path component for this reference (for example, the object's file name).
    public private(set) var name: String = ""
    
    private var MAX_RESULTS = 1000
    private static let defaultUploadChunkSize = 1024 * 1024
    /// Default page token used to begin pagination when listing items.
    public var DEFAULT_NEXT_PAGE_TOKEN = "0"
    
    /// Upload chunk size in bytes used by multipart/resumable uploads. Tests may override this value.
    public var CHUNK_SIZE = StorageReference.defaultUploadChunkSize
    
    internal var storageHelper: StorageHelper
    
    
    init (storage: Storage, path: String) {
        
        
        self.storage = storage
        self.storageHelper = StorageHelper(storage: self.storage)
        // Initialize chunk size from app options to keep client and backend expectations aligned.
        // Tests may still override per-reference via ref.CHUNK_SIZE.
        let configuredChunkSize = self.storage.app.options.uploadChunkSize
        self.CHUNK_SIZE = configuredChunkSize > 0 ? configuredChunkSize : StorageReference.defaultUploadChunkSize
        
        // this is the root ref
        if path.isEmpty {
            return
        }
        
        self.fullPath = path
        if self.fullPath.hasPrefix("/") {
            self.fullPath = String(self.fullPath.dropFirst())
        }
        
        var pathArr = self.fullPath.components(separatedBy: "/")
        
        self.name = pathArr.removeLast()
        self._parent = StorageReference(storage: self.storage, path: pathArr.joined(separator: "/"))
        
        // If this reference is a top-level child (e.g., "metadataTests") and no logical root
        // has been set yet, set the default logical root so that storage.reference() resolves
        // to this path for subsequent calls in the same Storage instance.
        if pathArr.isEmpty && self.storage.defaultRootPath.isEmpty {
            self.storage.defaultRootPath = self.fullPath
        }
        
    }
    
    
    /// Returns a reference to the bucket root.
    /// - Returns: A StorageReference pointing to the root path.
    open func root() -> StorageReference {
        return self.storage.reference()
    }
    
    /// Returns the parent reference of this location.
    /// - Returns: The parent StorageReference, or nil if this is already the root.
    open func parent() -> StorageReference? {
        return self._parent
    }
    
    /// Creates a child reference relative to this location.
    /// - Parameter path: A UTF-8 path string using forward slashes (/) to separate folders. Do not prefix with a leading slash.
    /// - Returns: A StorageReference pointing to the provided child path.
    open func child(_ path: String) -> StorageReference {
        let childRef = StorageReference(storage: self.storage, path: self.fullPath + "/" + path)
        childRef.CHUNK_SIZE = self.CHUNK_SIZE   // inherit parent effective chunk size
        return childRef
    }
    
    
    /// Retrieves a long‑lived, revocable download URL for the object at this reference.
    ///
    /// The returned URL can be shared with others to download the object and may be revoked
    /// by an administrator in the Fusabase Console.
    /// - Returns: A URL that can be used to download the object.
    /// - Throws: An error if the download URL could not be generated.
    open func downloadURL() async throws -> URL {
        
        let preAuthDict = try await self.storageHelper.genPreAuth(storageRef: self, accessType: "ObjectRead")
        return validatePreAuthDictForRead(preAuthDict: preAuthDict)!
    }
    
    /// Asynchronously retrieves a long‑lived, revocable download URL using a completion handler.
    /// - Parameter completion: A closure invoked with the URL on success or an error on failure.
    open func downloadURL(completion: @escaping (URL?, Error?) -> Void) {
        Task {
            do {
                let preAuthDict = try await self.storageHelper.genPreAuth(storageRef: self, accessType: "ObjectRead")
                let val = validatePreAuthDictForRead(preAuthDict: preAuthDict)!
                completion( val, nil)
            } catch let err as NSError {
                completion(nil, err)
            } catch {
                completion(nil, StorageErrorUtilities.internalError(message: "Couldn't fetch download URL."))
            }
        }
    }
    
    // MARK: - Delete
    /// Deletes the object at this reference.
    /// - Throws: An error if the delete operation fails.
    open func delete() async throws {
        
        try await self.storageHelper.delData(storageRef: self)
    }
    
    // MARK: - List Support
    /// Lists items and prefixes under this reference.
    ///
    /// This method fetches up to a server-defined maximum (usually 1000) items/prefixes
    /// beneath the current path.
    /// - Returns: A StorageListResult containing items, prefixes, and an optional page token.
    /// - Throws: An error if the list operation fails.
    open func listAll() async throws -> StorageListResult {
        
        let ListResDict = try await self.storageHelper.listObjs(storageRef: self, maxResults: MAX_RESULTS, pageToken: DEFAULT_NEXT_PAGE_TOKEN, recurse: true)
        return validateListResDict(listResDict: ListResDict)!
    }
    
    /// Lists items and prefixes under this reference using a completion handler.
    /// - Parameter completion: A closure invoked with a StorageListResult on success, or an error on failure.
    open func listAll(completion: @escaping (StorageListResult?, Error?) -> Void) {
        Task {
            do {
                let res = try await self.listAll()
                completion(res, nil)
            } catch let err as NSError {
                completion(nil, err)
            } catch {
                completion(nil, StorageErrorUtilities.internalError(message: "Couldn't retrieve StorageListResult object from server."))
            }
        }
    }
    
    /// Lists items and prefixes under this reference with pagination.
    /// - Parameters:
    ///   - maxResults: Maximum number of results to return (1...1000).
    ///   - pageToken: A page token from a previous result to continue listing, or nil to start from the beginning.
    ///   - completion: Closure delivering the page of results on success, or an error on failure.
    open func list(maxResults: Int64, pageToken: String?, completion: @escaping ((_: StorageListResult?, _: Error?) -> Void)) {

        Task {
            do {
                let listResDict = try await self.storageHelper.listObjs(storageRef: self, maxResults: Int(maxResults), pageToken: pageToken)

                guard let result = validateListResDict(listResDict: listResDict) else {
                    let error = StorageErrorUtilities.error(code: .internalError, message: "Invalid list() response")
                    completion(nil, error)
                    return
                }
                completion(result, nil)

            } catch {
                // Forward error to completion handler
                completion(nil, error)
            }
        }
    }

    // MARK: - Metadata Operations
    /// Retrieves the object's metadata.
    /// - Returns: A StorageMetadata describing the object on the server.
    /// - Throws: An error if the metadata could not be retrieved.
    open func getMetadata() async throws -> StorageMetadata {
        let metadataDict = try await self.storageHelper.getMetadata(storageRef: self)

        // Populate missing fields for getMetadata responses (similar to upload)
        var completeMetadataDict = metadataDict
        if completeMetadataDict["bucket"] == nil {
            completeMetadataDict["bucket"] = self.bucket
        }
        if completeMetadataDict["fullPath"] == nil {
            completeMetadataDict["fullPath"] = self.fullPath
        }
        if completeMetadataDict["name"] == nil {
            completeMetadataDict["name"] = self.name
        }
        if completeMetadataDict["timeCreated"] == nil && completeMetadataDict["time-created"] == nil {
            // Use updated time as creation time for getMetadata
            if let updated = completeMetadataDict["updated"] as? String {
                completeMetadataDict["timeCreated"] = updated
            }
        }

        guard let metadata = validateMetadataDict(metadataDict: completeMetadataDict) else {
            throw StorageErrorUtilities.internalError(message: "Failed to validate metadata response")
        }
        return metadata
    }
    
    /// Retrieves the object's metadata using a completion handler.
    /// - Parameter completion: Closure invoked with the object's metadata on success, or an error on failure.
    open func getMetadata(completion: @escaping (StorageMetadata?, Error?) -> Void) {
        Task {
            do {
                let res = try await self.getMetadata()
                completion(res, nil)
            } catch let err as NSError {
                completion(nil, err)
            } catch {
                completion(nil, StorageErrorUtilities.internalError(message: "Couldn't retrieve StorageListResult object from server."))
            }
        }
    }
    
    /// Updates the object's metadata.
    ///
    /// - Parameter metadata: The new metadata to apply on the object.
    /// - Returns: The updated metadata as stored on the server.
    /// - Throws: Currently not supported and will always throw an internal error.
    open func updateMetadata(_ metadata: StorageMetadata) async throws -> StorageMetadata {
        throw StorageErrorUtilities.internalError(message: "This method is not supported yet.")
    }
    
    /// Attempts to update the object's metadata using a completion handler.
    ///
    /// - Parameters:
    ///   - metadata: The metadata to apply to the object.
    ///   - completion: Called with the updated metadata on success, or an error. Currently always returns an error since this method is not supported.
    open func updateMetadata(_ metadata: StorageMetadata,
                             completion: @escaping ( _: StorageMetadata?, _: Error?) -> Void ) {
        let err = StorageErrorUtilities.internalError(message: "This method is not supported yet.")
        completion(nil, err)
    }
    
}
