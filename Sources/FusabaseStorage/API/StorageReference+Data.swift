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


extension StorageReference {
    
    // MARK: - Uploads
    /// Uploads raw data to this reference.
    ///
    /// The method automatically chooses between a single-part upload and multipart (chunked) upload
    /// based on the size of the data relative to `CHUNK_SIZE`. On success, the task's snapshot
    /// will include the server-returned `StorageMetadata`.
    ///
    /// - Parameters:
    ///   - uploadData: The in-memory data to upload.
    ///   - metadata: Optional metadata to associate with the object. Currently used for content type.
    /// - Returns: A `StorageUploadTask` you can observe for progress, success, or failure.
    /// - Note: You can observe status changes via `observe(_:_:)` on the returned task.
    @discardableResult
    public func putData(_ uploadData: Data, metadata: StorageMetadata? = nil) -> StorageUploadTask {
        
        let uploadTask = StorageUploadTask(reference: self)
        Task {
            let mimeType = "application/octet-stream"
            if uploadData.count > 2 * self.CHUNK_SIZE {
                do {
                    let preAuthDict = try await self.storageHelper.genPreAuth(storageRef: self, accessType: "ObjectWrite", mimeType: mimeType, metadata: metadata)
                    guard let preAuthUrl: URL = validatePreAuthDictForWrite(preAuthDict: preAuthDict) else {
                        let error = StorageErrorUtilities.internalError(message: "Failed to validate pre-auth response for multipart upload")
                        await uploadTask.notify(newStatus: .failure, error: error)
                        return
                    }
                    
                    // Upload in chunks using MultipartRequest-based routine
                    await self.multiPartUploadRoutine(data: uploadData, mimeType: mimeType, preAuthUrl: preAuthUrl, uploadTask: uploadTask)
                    
                    // Check cancel/failure again with brief backoff to avoid race before commit
                    var shouldAbort = false
                    for _ in 0..<50 {
                        let canceled = await uploadTask.isCanceled()
                        let failed = await uploadTask.isFailed()
                        if canceled || failed {
                            shouldAbort = true
                            break
                        }
                        // yield briefly to allow cancel to propagate
                        try? await Task.sleep(nanoseconds: 5_000_000) // 5ms
                    }
                    if shouldAbort {
                        await self.storageHelper.abortForMultiPart(url: preAuthUrl, storageRef: self)
                        StorageLogger.debug("Upload task canceled or failed. Skipping commit step.")
                        return
                    }
                    
                    await self.storageHelper.commitForMultiPart(url: preAuthUrl, storageRef: self)
                                        // Finalize multipart data upload: fetch metadata and notify success
                    do {
                        let metadata = try await self.getMetadata()
                        await uploadTask.setMetadata(metadata)
                        await uploadTask.setSuccessful()
                        await uploadTask.notify(newStatus: .success)
                    } catch {
                        StorageLogger.error("Failed to finalize multipart data upload: \(error)")
                        await uploadTask.notify(newStatus: .failure, error: error)
                        return
                    }

                    StorageLogger.info("Multipart upload completed successfully")
                } catch {
                    StorageLogger.error("Failed to upload data (multipart): \(error)")
                    await uploadTask.notify(newStatus: .failure, error: error)
                    return
                }
            } else {
                do {
                    let uploadResult = try await self.storageHelper.putData(storageRef: self, data: uploadData, mimeType: mimeType, uploadTask: uploadTask, metadata: metadata)
                    StorageLogger.info("Single-part upload completed successfully")

                    // Extract metadata from upload response (handle nested structure like Android)
                    var metadataDict: [String: Any]
                    if let nestedMetadata = uploadResult["metadata"] as? [String: Any] {
                        metadataDict = nestedMetadata
                    } else {
                        metadataDict = uploadResult
                    }

                    // Populate missing fields for OCI upload responses
                    if metadataDict["bucket"] == nil {
                        metadataDict["bucket"] = self.bucket
                    }
                    if metadataDict["fullPath"] == nil {
                        metadataDict["fullPath"] = self.fullPath
                    }
                    if metadataDict["name"] == nil {
                        // Try to get name from root level response first
                        if let rootName = uploadResult["name"] as? String {
                            metadataDict["name"] = rootName
                        } else {
                            metadataDict["name"] = self.name
                        }
                    }
                    if metadataDict["timeCreated"] == nil && metadataDict["time-created"] == nil {
                        // Use updated time as creation time for uploads
                        if let updated = metadataDict["updated"] as? String {
                            metadataDict["timeCreated"] = updated
                        }
                    }

                    guard let metadata = validateMetadataDict(metadataDict: metadataDict) else {
                        let error = StorageErrorUtilities.internalError(message: "Failed to validate metadata response")
                        await uploadTask.notify(newStatus: .failure, error: error)
                        return
                    }
                    await uploadTask.setMetadata(metadata)

                    await uploadTask.setSuccessful()
                    await uploadTask.notify(newStatus: .success)
                } catch {
                    StorageLogger.error("Failed to upload data (single-part): \(error)")
                    await uploadTask.notify(newStatus: .failure, error: error)
                    return
                }
            }
        }
        return uploadTask
    }
    
    /// Uploads raw data to this reference and invokes a completion handler on finish.
    ///
    /// The completion is dispatched on the main queue after the task completes with success or failure.
    /// - Parameters:
    ///   - uploadData: The in-memory data to upload.
    ///   - metadata: Optional metadata to associate with the object.
    ///   - completion: Called with the server-returned metadata on success, or an error on failure.
    /// - Returns: The underlying `StorageUploadTask` for observation or cancellation.
    @discardableResult
    open func putData(_ uploadData: Data,
                      metadata: StorageMetadata? = nil,
                      completion: ((_: StorageMetadata?, _: Error?) -> Void)?) -> StorageUploadTask {
        
        let uploadTask = putData(uploadData, metadata: metadata)
        
        if let completion = completion {
            uploadTask.observe(.success) { snapshot in
                DispatchQueue.main.async { completion(snapshot.metadata, nil) }
            }
            uploadTask.observe(.failure) { snapshot in
                DispatchQueue.main.async { completion(nil, snapshot.error) }
            }
        }
        
        return uploadTask
    }
    
    /// Internal helper used by tests to invoke `putData(_:)` with default parameters.
    /// - Parameter uploadData: The data to upload.
    /// - Returns: The created `StorageUploadTask`.
    public func __putData(_ uploadData: Data) -> StorageUploadTask {
        return self.putData(uploadData)
    }
    
    // MARK: - Downloads
    /// Downloads the object data into memory and delivers it via completion.
    ///
    /// If the downloaded data exceeds `maxSize`, the operation fails with
    /// `StorageErrorCode.downloadSizeExceeded`.
    /// - Parameters:
    ///   - maxSize: The maximum allowed size in bytes for the downloaded data.
    ///   - completion: Called with the data on success, or an error on failure.
    /// - Returns: A `StorageDownloadTask` that begins immediately and can be observed or canceled.
    @discardableResult
    public func getData(maxSize: Int64,
                      completion: @escaping ((_: Data?, _: Error?) -> Void)) -> StorageDownloadTask {
        
        let downloadTask = StorageDownloadTask(reference: self)
        Task {
            await downloadTask.setResumed()
            do {
                let data = try await self.storageHelper.getData(storageRef: self, maxSize: maxSize)
                await downloadTask.setSuccessful()
                completion(data, nil)
            } catch {

                
                // set fail & error for task
                completion(nil, error)
            }
        }
        
        return downloadTask
    }
}
