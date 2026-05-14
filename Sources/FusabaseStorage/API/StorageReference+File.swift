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
    
    /// Uploads the contents of a local file to this storage reference.
    ///
    /// The method chooses between single-part and multipart uploads based on the file size
    /// relative to `CHUNK_SIZE`. On completion, the returned task will publish its final
    /// `StorageMetadata` via the `.success` snapshot.
    ///
    /// - Parameters:
    ///   - fileURL: Local file URL to upload.
    ///   - metadata: Optional metadata to associate with the uploaded object.
    /// - Returns: A `StorageUploadTask` you can observe or cancel.
    @discardableResult
    open func putFile(from fileURL: URL, metadata: StorageMetadata? = nil) -> StorageUploadTask {

        let uploadTask = StorageUploadTask(reference: self)
        Task {

            await uploadTask.setResumed()
            do {
                // Determine MIME type based on file extension
                var mimeType = "application/octet-stream"
                if #available(iOS 14.0, *) {
                    if let fileUTType = UTType(filenameExtension: fileURL.pathExtension),
                       let preferredMIME = fileUTType.preferredMIMEType {
                        mimeType = preferredMIME
                    }
                }
                // TODO: iOS 15 fallback (use MobileCoreServices)

                // Get file size
                let fileSize = try FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as! UInt64

                if fileSize > 2 * UInt64(self.CHUNK_SIZE) {
                    // Multipart upload path
                    let preAuthDict = try await self.storageHelper.genPreAuth(storageRef: self, accessType: "ObjectWrite", mimeType: mimeType, metadata: metadata)
                    guard let preAuthUrl: URL = validatePreAuthDictForWrite(preAuthDict: preAuthDict) else {
                        let error = StorageErrorUtilities.internalError(message: "Failed to validate pre-auth response for multipart upload")
                        await uploadTask.notify(newStatus: .failure, error: error)
                        return
                    }

                    // upload chunk one by one
                    await multiPartUploadRoutine(fileURL: fileURL, fileSize: fileSize, mimeType: mimeType,
                                                 preAuthUrl: preAuthUrl, uploadTask: uploadTask)
                    
                    // check cancel again, avoid race
                    if await uploadTask.isCanceled() {
                        await self.storageHelper.abortForMultiPart(url: preAuthUrl, storageRef: self)
                        StorageLogger.debug("Upload task canceled. Skipping commit step.")
                        return
                    }
                    
                    /// need Atomic ?
                    await self.storageHelper.commitForMultiPart(url: preAuthUrl, storageRef: self)

                                        // After committing multipart upload, finalize by fetching metadata and notifying success
                    do {
                        let metadata = try await self.getMetadata()
                        await uploadTask.setMetadata(metadata)
                        await uploadTask.setSuccessful()
                        await uploadTask.notify(newStatus: .success)
                    } catch {
                        StorageLogger.error("Failed to finalize multipart upload: \(error)")
                        await uploadTask.notify(newStatus: .failure, error: error)
                        return
                    }

StorageLogger.info("Multipart upload completed successfully")
                } else {
                    // Single upload path
                    let uploadResult = try await self.storageHelper.putFile(storageRef: self, fileURL: fileURL, mimeType: mimeType, uploadTask: uploadTask, metadata: metadata)

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
                }

            } catch {
                StorageLogger.error("Failed to upload file: \(error)")
                await uploadTask.notify(newStatus: .failure, error: error)
            }
        }
        return uploadTask
    }
    
    /// Uploads the contents of a local file and invokes a completion handler when finished.
    ///
    /// The completion is dispatched on the main queue after success or failure.
    /// - Parameters:
    ///   - fileURL: Local file URL to upload.
    ///   - metadata: Optional metadata to associate with the uploaded object.
    ///   - completion: Called with the server-returned metadata on success, or an error on failure.
    /// - Returns: The underlying `StorageUploadTask`.
    @discardableResult
    open func putFile(from fileURL: URL,
                      metadata: StorageMetadata? = nil,
                      completion: ((_: StorageMetadata?, _: Error?) -> Void)?) -> StorageUploadTask {
        
        let uploadTask = putFile(from: fileURL, metadata: metadata)

        // if a completion handler is provided, attach observers for it
        if let completion = completion {
            uploadTask.observe(.success) { snapshot in
//                completion(snapshot.metadata, nil)
                DispatchQueue.main.async { completion(snapshot.metadata, nil) }
            }
            
            uploadTask.observe(.failure) { snapshot in
//                completion(nil, snapshot.error)
                DispatchQueue.main.async { completion(nil, snapshot.error) }
            }
        }
        // todo: when to rm the 2 handles?

        return uploadTask
    }
    
    /// Internal helper for tests to invoke `putFile(from:)` with default parameters.
    /// - Parameter fileURL: Local file URL to upload.
    /// - Returns: The created `StorageUploadTask`.
    public func __putFile(from fileURL: URL) -> StorageUploadTask {
        return self.putFile(from: fileURL)
    }
    
    /// Downloads the object and writes it to a local file.
    ///
    /// - Parameter fileURL: Target file URL where the object should be written.
    /// - Returns: A `StorageDownloadTask` that begins immediately and can be observed or canceled.
    @discardableResult
    public func write(toFile fileURL: URL) -> StorageDownloadTask {
        
        let downloadTask = StorageDownloadTask(reference: self)
        Task {
            await downloadTask.setResumed()
            do {
                try await self.storageHelper.downloadToFile(storageRef: self, fileURL: fileURL)
                
                await downloadTask.setSuccessful()
                await downloadTask.notify(newStatus: .success)
                
            } catch {
                StorageLogger.error("Failed to write data to file: \(error)")
                // Notify observers of failure so completion handlers are invoked
                await downloadTask.notify(newStatus: .failure, error: error)
            }
        }
        
        return downloadTask
    }
    
    /// Downloads the object to a local file and invokes a completion handler when finished.
    ///
    /// The completion is dispatched on the main queue.
    /// - Parameters:
    ///   - fileURL: Target file URL where the object should be written.
    ///   - completion: Called with the file URL on success, or an error on failure.
    /// - Returns: The underlying `StorageDownloadTask`.
    @discardableResult
    open func write(toFile fileURL: URL,
                    completion: ((_: URL?, _: Error?) -> Void)?) -> StorageDownloadTask {
        
        let downloadTask = write(toFile: fileURL)
        
        if let completion = completion {
            downloadTask.observe(.success) { snapshot in
                DispatchQueue.main.async { completion(fileURL, nil) }
            }
            
            downloadTask.observe(.failure) { snapshot in
                DispatchQueue.main.async { completion(nil, snapshot.error) }
            }
        }
        
        return downloadTask
    }
}
