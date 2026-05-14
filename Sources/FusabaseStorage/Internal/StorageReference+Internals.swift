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
    
    
    internal func pauseIfNeeded(_ uploadTask: StorageUploadTask) async {

        while await uploadTask.isPaused() {

            StorageLogger.debug("Upload task paused — sleeping...")
            try? await Task.sleep(nanoseconds: 500_000_000)

            if await uploadTask.isCanceled() {
                return
            }
        }
    }
    
    internal func multiPartUploadRoutine(fileURL: URL, fileSize: UInt64, mimeType: String,
                                         preAuthUrl: URL,
                                         uploadTask: StorageUploadTask) async {
        
        guard let fileHandle = try? FileHandle(forReadingFrom: fileURL) else {
            StorageLogger.error("Failed to open file")
            return
        }

        let totalChunks = Int(ceil(Double(fileSize) / Double(self.CHUNK_SIZE)))
        var progress = Progress(totalUnitCount: Int64(totalChunks))
        
        do {
            for chunkIndex in 0..<totalChunks {
                
                // ✅ Cancel/Failure check
                let canceledPre = await uploadTask.isCanceled()
                let failedPre = await uploadTask.isFailed()
                if canceledPre || failedPre {
                    await self.storageHelper.abortForMultiPart(url: preAuthUrl, storageRef: self)
                    StorageLogger.debug("Upload canceled/failed at chunk \(chunkIndex + 1)")
                    return
                }
                
                // ✅ Pause check
                await pauseIfNeeded(uploadTask)
                
                let offset = UInt64(chunkIndex) * UInt64(self.CHUNK_SIZE)
                try fileHandle.seek(toOffset: offset)
                
                let remaining = fileSize - offset
                let currentChunkSize = min(UInt64(self.CHUNK_SIZE), remaining)
                
                let data = fileHandle.readData(ofLength: Int(currentChunkSize))
                
                let chunkNum = chunkIndex + 1
                let uploadUrl = preAuthUrl.appendingPathComponent(String(chunkNum))
                
                await self.storageHelper.putDataForMultiPart(url: uploadUrl, storageRef: self, data: data, mimeType: mimeType, uploadTask: uploadTask)
                
                // Post-upload quick guard for cancel/failure (allow state to propagate)
                var shouldAbort = false
                let canceled1 = await uploadTask.isCanceled()
                let failed1 = await uploadTask.isFailed()
                shouldAbort = canceled1 || failed1
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
                    StorageLogger.debug("Upload canceled/failed at chunk \(chunkNum)")
                    return
                }
                
                progress.completedUnitCount = Int64(chunkNum)
                await uploadTask.notify(newProgress: progress)
                
                StorageLogger.debug("Uploaded chunk \(chunkNum)/\(totalChunks)")
            }
            try fileHandle.close()
            
        } catch {
            StorageLogger.error("Upload failed.")
        }
    }
    
}
