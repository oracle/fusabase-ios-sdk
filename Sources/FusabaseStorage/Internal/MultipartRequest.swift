// Copyright (c) 2015, 2025, Oracle and/or its affiliates.
//
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

/// Internal multipart upload request state, translated from the Android implementation.
/// Mirrors fields and behavior of the Java class:
/// - Maintains current chunk index and bytesTransferred
/// - Exposes helpers to compute next chunk and number of total chunks
/// - Provides navigation methods for next, retry, and previous chunk
internal final class MultipartRequest {

    private let bytes: Data
    private var currIndex: Int
    private let chunkSize: Int
    private let totalBytes: Int
    private var bytesTransferred: Int
    private let accessURL: String
    private let mimeType: String

    /// Initialize multipart request state
    /// - Parameters:
    ///   - accessURL: Pre-authenticated base URL to use for chunk operations
    ///   - mimeType: MIME type for the upload
    ///   - bytes: Full payload to be chunked
    ///   - chunkSize: Desired chunk size (in bytes)
    internal init(_ accessURL: String, _ mimeType: String, _ bytes: Data, _ chunkSize: Int) {
        self.bytes = bytes
        self.currIndex = 1
        self.chunkSize = chunkSize
        self.totalBytes = bytes.count
        self.accessURL = accessURL
        self.bytesTransferred = 0
        self.mimeType = mimeType
    }

    internal func getMimeType() -> String {
        return self.mimeType
    }

    internal func getBytesTransferred() -> Int {
        return self.bytesTransferred
    }

    internal func getTotalBytes() -> Int {
        return self.totalBytes
    }

    /// Returns the next chunk of data to upload.
    /// If already at or beyond the end of data, returns empty Data.
    internal func getNextChunk() -> Data {
        let start = bytesTransferred
        if start >= totalBytes { return Data() }
        let end = min(bytesTransferred + chunkSize, totalBytes)
        return bytes.subdata(in: start..<end)
    }

    internal func getTotalNumberOfChunks() -> Int {
        return (totalBytes + chunkSize - 1) / chunkSize
    }

    internal func getCurrIndex() -> Int {
        return self.currIndex
    }

    /// Move forward to the next chunk.
    internal func updateRequestForNextChunk() {
        self.bytesTransferred = min(self.totalBytes, self.bytesTransferred + self.chunkSize)
        if self.currIndex == 0 {
            // In retry/reset state, currIndex represents the "next chunk index".
            // Recompute the next index based on progress so it aligns with Java semantics and tests.
            let totalChunks = self.getTotalNumberOfChunks()
            let nextIdx = min(totalChunks + 1,
                              (self.bytesTransferred + self.chunkSize - 1) / self.chunkSize + 1)
            self.currIndex = nextIdx
        } else {
            self.currIndex += 1
        }
    }

    /// Adjust state for retrying the last chunk.
    /// Mirrors Java logic where currIndex is set to 0 to indicate reset.
    internal func updateRequestForRetry() {
        self.bytesTransferred = self.bytesTransferred > self.chunkSize ? (self.bytesTransferred - self.chunkSize) : 0
        self.currIndex = 0
    }

    /// Move back to the previous chunk if possible.
    internal func updateRequestForPreviousChunk() {
        self.bytesTransferred = self.bytesTransferred > self.chunkSize ? (self.bytesTransferred - self.chunkSize) : 0
        self.currIndex = self.currIndex == 0 ? self.currIndex : (self.currIndex - 1)
    }

    internal func getAccessURL() -> String {
        return self.accessURL
    }
}
