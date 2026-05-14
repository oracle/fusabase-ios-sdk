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

extension StorageReference {
    
    /// Multipart upload routine for in-memory Data using MultipartRequest chunker.
    /// - Parameters:
    ///   - data: The full payload to upload.
    ///   - mimeType: The MIME type of the payload.
    ///   - preAuthUrl: Base pre-auth URL returned by genPreAuth(ObjectWrite).
    ///   - uploadTask: The associated upload task for pause/cancel/progress handling.
    internal func multiPartUploadRoutine(data: Data,
                                         mimeType: String,
                                         preAuthUrl: URL,
                                         uploadTask: StorageUploadTask) async {
        
        let chunker = MultipartRequest(preAuthUrl.absoluteString, mimeType, data, self.CHUNK_SIZE)
        let totalChunks = chunker.getTotalNumberOfChunks()
        var progress = Progress(totalUnitCount: Int64(totalChunks))
        
        while true {
            // Cancel/Failure check
            let canceledPre = await uploadTask.isCanceled()
            let failedPre = await uploadTask.isFailed()
            if canceledPre || failedPre {
                await self.storageHelper.abortForMultiPart(url: preAuthUrl, storageRef: self)
                StorageLogger.info("🚫 Upload canceled/failed at chunk index \(chunker.getCurrIndex())")
                return
            }
            
            // Pause handling
            await pauseIfNeeded(uploadTask)
            
            // Fetch next chunk
            let nextChunk = chunker.getNextChunk()
            if nextChunk.isEmpty {
                break
            }
            
            // Upload current chunk (index is 1-based)
            let currIdx = chunker.getCurrIndex()
            let uploadUrl = preAuthUrl.appendingPathComponent(String(currIdx))
            await self.storageHelper.putDataForMultiPart(url: uploadUrl,
                                                         storageRef: self,
                                                         data: nextChunk,
                                                         mimeType: mimeType,
                                                         uploadTask: uploadTask)

            // After upload, check for cancel/failure to avoid racing into next iteration/commit
            let canceledPost1 = await uploadTask.isCanceled()
            let failedPost1 = await uploadTask.isFailed()
            var shouldAbort = canceledPost1 || failedPost1
            if !shouldAbort {
                // brief backoff to allow async cancel to take effect
                for _ in 0..<3 {
                    let c = await uploadTask.isCanceled()
                    let f = await uploadTask.isFailed()
                    if c || f {
                        shouldAbort = true
                        break
                    }
                    try? await Task.sleep(nanoseconds: 2_000_000) // 2ms
                }
            }
            if shouldAbort {
                await self.storageHelper.abortForMultiPart(url: preAuthUrl, storageRef: self)
                StorageLogger.info("🚫 Upload canceled/failed at chunk index \(currIdx)")
                return
            }
            
            // Update progress and advance
            progress.completedUnitCount = Int64(currIdx)
            await uploadTask.notify(newProgress: progress)
            
            StorageLogger.debug("Uploaded chunk \(currIdx)/\(totalChunks)")
            chunker.updateRequestForNextChunk()
        }
    }
}
