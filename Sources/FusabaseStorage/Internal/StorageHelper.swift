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
import FusabaseCore


enum StorageHelperFunc {
    case putObj
    case getObj
    case delObj
    case lstObjs
    case getMetadata
    case genPreAuth
}

@available(iOS 15, tvOS 13, macOS 10.15, watchOS 7, *)
/// StorageHelper
/// Internal helper responsible for building and executing HTTP requests to the Storage backend.
/// It maintains base endpoints derived from FusabaseOptions and provides high-level helpers for:
/// - Single-part uploads (putData)
/// - Multipart upload helpers (putDataForMultiPart, commitForMultiPart, abortForMultiPart)
/// - Downloads (getData)
/// - Deletes (delData)
/// - Listings (listObjs)
/// - Metadata retrieval (getMetadata)
/// - Pre-auth URL generation (genPreAuth)
/// Networking errors are mapped via StorageErrorUtilities and responses are validated using handleHttpResponse.
class StorageHelper {

    private static let maxErrorResponseBodyBytes = 1_048_576

    private final class URLSessionBox {
        var session: URLSession?
    }

    private final class BoundedDataDownloadDelegate: NSObject, URLSessionDataDelegate {
        private let maxSize: Int64
        private let completion: (Result<(Data, URLResponse), Error>) -> Void
        private var response: URLResponse?
        private var statusCode: Int = -1
        private var data = Data()
        private var terminalError: Error?
        private var didComplete = false

        init(maxSize: Int64,
             completion: @escaping (Result<(Data, URLResponse), Error>) -> Void) {
            self.maxSize = maxSize
            self.completion = completion
        }

        func urlSession(_ session: URLSession,
                        dataTask: URLSessionDataTask,
                        didReceive response: URLResponse,
                        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
            self.response = response
            self.statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            completionHandler(.allow)
        }

        func urlSession(_ session: URLSession,
                        dataTask: URLSessionDataTask,
                        didReceive data: Data) {
            guard terminalError == nil else { return }

            if (200...299).contains(statusCode) {
                if Int64(self.data.count) + Int64(data.count) > maxSize {
                    terminalError = StorageErrorUtilities.error(
                        code: .downloadSizeExceeded,
                        message: "Data size exceeds maxSize limit."
                    )
                    dataTask.cancel()
                    return
                }
                self.data.append(data)
            } else {
                // Keep only a bounded error body for error mapping.
                let maxErrorBytes = StorageHelper.maxErrorResponseBodyBytes
                if self.data.count < maxErrorBytes {
                    self.data.append(data.prefix(maxErrorBytes - self.data.count))
                }
            }
        }

        func urlSession(_ session: URLSession,
                        task: URLSessionTask,
                        didCompleteWithError error: Error?) {
            guard !didComplete else { return }
            didComplete = true

            if let terminalError {
                completion(.failure(terminalError))
                return
            }

            if let error {
                completion(.failure(error))
                return
            }

            guard let response else {
                completion(.failure(StorageErrorUtilities.internalError(message: "Obtained a non-valid HTTP response.")))
                return
            }

            completion(.success((data, response)))
        }
    }

    private final class FileStreamingDownloadDelegate: NSObject, URLSessionDataDelegate {
        private let destinationURL: URL
        private let completion: (Result<(Data, URLResponse), Error>) -> Void
        private var response: URLResponse?
        private var statusCode: Int = -1
        private var errorData = Data()
        private var outputStream: OutputStream?
        private var terminalError: Error?
        private var didComplete = false

        init(destinationURL: URL,
             completion: @escaping (Result<(Data, URLResponse), Error>) -> Void) {
            self.destinationURL = destinationURL
            self.completion = completion
        }

        func urlSession(_ session: URLSession,
                        dataTask: URLSessionDataTask,
                        didReceive response: URLResponse,
                        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
            self.response = response
            self.statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1

            if (200...299).contains(statusCode) {
                do {
                    if FileManager.default.fileExists(atPath: destinationURL.path) {
                        try FileManager.default.removeItem(at: destinationURL)
                    }
                    FileManager.default.createFile(atPath: destinationURL.path, contents: nil)
                    outputStream = OutputStream(url: destinationURL, append: false)
                    outputStream?.open()
                } catch {
                    terminalError = error
                    completionHandler(.cancel)
                    return
                }
            }

            completionHandler(.allow)
        }

        func urlSession(_ session: URLSession,
                        dataTask: URLSessionDataTask,
                        didReceive data: Data) {
            guard terminalError == nil else { return }

            if (200...299).contains(statusCode) {
                guard let outputStream else {
                    terminalError = StorageErrorUtilities.internalError(message: "Unable to open destination file stream.")
                    dataTask.cancel()
                    return
                }

                let wroteSuccessfully = data.withUnsafeBytes { rawBuffer -> Bool in
                    guard let baseAddress = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                        return true
                    }

                    var bytesRemaining = data.count
                    var writePointer = baseAddress
                    while bytesRemaining > 0 {
                        let bytesWritten = outputStream.write(writePointer, maxLength: bytesRemaining)
                        if bytesWritten <= 0 {
                            return false
                        }
                        bytesRemaining -= bytesWritten
                        writePointer += bytesWritten
                    }
                    return true
                }

                if !wroteSuccessfully {
                    terminalError = outputStream.streamError ?? StorageErrorUtilities.internalError(message: "Failed to write downloaded bytes to file.")
                    dataTask.cancel()
                }
            } else {
                // Keep only a bounded error body for error mapping.
                let maxErrorBytes = StorageHelper.maxErrorResponseBodyBytes
                if errorData.count < maxErrorBytes {
                    errorData.append(data.prefix(maxErrorBytes - errorData.count))
                }
            }
        }

        func urlSession(_ session: URLSession,
                        task: URLSessionTask,
                        didCompleteWithError error: Error?) {
            guard !didComplete else { return }
            didComplete = true
            outputStream?.close()

            if let terminalError {
                try? FileManager.default.removeItem(at: destinationURL)
                completion(.failure(terminalError))
                return
            }

            if let error {
                try? FileManager.default.removeItem(at: destinationURL)
                completion(.failure(error))
                return
            }

            guard let response else {
                try? FileManager.default.removeItem(at: destinationURL)
                completion(.failure(StorageErrorUtilities.internalError(message: "Obtained a non-valid HTTP response.")))
                return
            }

            completion(.success((errorData, response)))
        }
    }

    private var storage: Storage

    internal var host: String
    internal var port: String
    internal var schema: String
    internal var projectId: String
    internal var appId: String
    internal var bucket: String


    public var endWithProjectId: String
    public var endWithParProjectId: String

    init (storage: Storage) {
        self.storage = storage

        self.host = self.storage.app.options.ordsHost
        self.port = self.storage.app.options.ordsPort
        self.schema = self.storage.app.options.schema
        self.projectId = self.storage.app.options.projectId
        self.appId = self.storage.app.options.appId
        self.bucket = self.storage.app.options.storageBucket

        let objType = self.storage.app.options.objsType == "dbfs" ? "dbfs" : "oci-objs"
        self.endWithProjectId = self.storage.app.options.ordsBaseURL + "_/baas-services/\(objType)/\(self.projectId)"
        self.endWithParProjectId = self.storage.app.options.ordsBaseURL + "_/baas-services/\(objType)/par/\(self.projectId)"
    }

    private func parseObjectSize(from metadataDict: [String: Any]) -> Int64? {
        guard let rawSize = metadataDict["size"] else { return nil }

        if let size = rawSize as? Int64 {
            return size >= 0 ? size : nil
        }

        if let size = rawSize as? Int {
            return size >= 0 ? Int64(size) : nil
        }

        if let size = rawSize as? UInt64 {
            return size <= UInt64(Int64.max) ? Int64(size) : nil
        }

        if let size = rawSize as? UInt {
            return size <= UInt(Int64.max) ? Int64(size) : nil
        }

        if let number = rawSize as? NSNumber {
            let size = number.int64Value
            return size >= 0 ? size : nil
        }

        if let sizeString = rawSize as? String, let size = Int64(sizeString) {
            return size >= 0 ? size : nil
        }

        return nil
    }

    private func assertMetadataSizeWithinLimit(storageRef: StorageReference, maxSize: Int64) async throws {
        guard maxSize >= 0 else {
            throw StorageErrorUtilities.invalidArgumentError(message: "Invalid maxSize provided.")
        }

        let metadataDict = try await self.getMetadata(storageRef: storageRef)
        if let objectSize = parseObjectSize(from: metadataDict), objectSize > maxSize {
            throw StorageErrorUtilities.error(
                code: .downloadSizeExceeded,
                message: "Download size \(objectSize) exceeds maxSize \(maxSize)."
            )
        }
    }

    private func readBoundedData(from fileURL: URL, maxBytes: Int = StorageHelper.maxErrorResponseBodyBytes) throws -> Data {
        guard maxBytes > 0 else { return Data() }

        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        return try handle.read(upToCount: maxBytes) ?? Data()
    }

    private func downloadDataWithLimit(request: URLRequest, maxSize: Int64) async throws -> Data {
        let (data, response) = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Data, URLResponse), Error>) in
            let sessionBox = URLSessionBox()
            let delegate = BoundedDataDownloadDelegate(maxSize: maxSize) { result in
                sessionBox.session?.invalidateAndCancel()
                sessionBox.session = nil
                continuation.resume(with: result)
            }

            let session = URLSession(configuration: SecureNetworking.secureDefaultConfiguration(), delegate: delegate, delegateQueue: nil)
            sessionBox.session = session
            session.dataTask(with: request).resume()
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw StorageErrorUtilities.internalError(message: "Obtained a non-valid HTTP response.")
        }

        if !(200...299).contains(httpResponse.statusCode) {
            _ = try handleHttpResponse(data: data, response: response)
            throw StorageErrorUtilities.internalError(message: "Unexpected HTTP response status: \(httpResponse.statusCode)")
        }

        return data
    }

    private func streamDownloadToFile(request: URLRequest, fileURL: URL) async throws {
        let (errorData, response) = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Data, URLResponse), Error>) in
            let sessionBox = URLSessionBox()
            let delegate = FileStreamingDownloadDelegate(destinationURL: fileURL) { result in
                sessionBox.session?.invalidateAndCancel()
                sessionBox.session = nil
                continuation.resume(with: result)
            }

            let session = URLSession(configuration: SecureNetworking.secureDefaultConfiguration(), delegate: delegate, delegateQueue: nil)
            sessionBox.session = session
            session.dataTask(with: request).resume()
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw StorageErrorUtilities.internalError(message: "Obtained a non-valid HTTP response.")
        }

        if !(200...299).contains(httpResponse.statusCode) {
            _ = try handleHttpResponse(data: errorData, response: response)
            throw StorageErrorUtilities.internalError(message: "Unexpected HTTP response status: \(httpResponse.statusCode)")
        }
    }

    /// Uploads raw bytes to the given storage reference in a single request (non-multipart path).
    /// - Parameters:
    ///   - storageRef: Target storage reference.
    ///   - data: Raw data to upload.
    ///   - mimeType: MIME type for the upload.
    ///   - uploadTask: The associated upload task used for observers and pause/cancel checks (not used here directly).
    ///   - metadata: Optional metadata to associate with the uploaded object.
    /// - Returns: Response dictionary containing upload result metadata.
    /// - Throws: Storage errors mapped via StorageErrorUtilities if the request fails.
    func putData(storageRef: StorageReference, data: Data, mimeType: String = "", uploadTask: StorageUploadTask, metadata: StorageMetadata? = nil) async throws -> [String: Any] {

        let req = self.setHttpRequest(storageHelperFunc: .putObj, storageRef: storageRef, data: data, mimeType: mimeType, metadata: metadata)
        do {
            let (data, resp) = try await SecureNetworking.secureSession.data(for: req)
            let result = try handleHttpResponse(data: data, response: resp)
            StorageLogger.info("Single-part upload completed for \(storageRef.fullPath)")
            return result
        } catch let urlErr as URLError {
            let message = StorageErrorUtilities.handleURLError(urlErr)
            StorageLogger.error("Upload failed for \(storageRef.fullPath): \(message)")
            throw StorageErrorUtilities.internalError(message: message)
        } catch {
            StorageLogger.error("Upload failed for \(storageRef.fullPath): \(error.localizedDescription)")
            throw error
        }
    }

    /// Uploads a single multipart chunk.
    /// Non-throwing; errors are logged.
    func putDataForMultiPart(url: URL,
                             storageRef: StorageReference,
                             data: Data, mimeType: String,
                             uploadTask: StorageUploadTask) async {

        let req = self.setHttpRequestForMultiPart(url: url, op: MultiPartOp.putData, storageRef: storageRef, data: data, mimeType: mimeType)
        do {
            let _ = try await SecureNetworking.secureSession.data(for: req)
            StorageLogger.debug("Multipart chunk uploaded for \(storageRef.fullPath)")
        } catch let urlErr as URLError {
            let message = StorageErrorUtilities.handleURLError(urlErr)
            StorageLogger.error("Multipart chunk upload failed for \(storageRef.fullPath): \(message)")
        } catch {
            StorageLogger.error("Multipart chunk upload failed for \(storageRef.fullPath): \(error.localizedDescription)")
        }
    }

    /// Commits a multipart upload session.
    /// Non-throwing; errors are logged.
    func commitForMultiPart(url: URL, storageRef: StorageReference) async {

        let req = self.setHttpRequestForMultiPart(url: url, op: MultiPartOp.commit, storageRef: storageRef)
        do {
            let _ = try await SecureNetworking.secureSession.data(for: req)
            StorageLogger.info("Multipart commit successful for \(storageRef.fullPath)")
        } catch let urlErr as URLError {
            let message = StorageErrorUtilities.handleURLError(urlErr)
            StorageLogger.error("Multipart commit failed for \(storageRef.fullPath): \(message)")
        } catch {
            StorageLogger.error("Multipart commit failed for \(storageRef.fullPath): \(error.localizedDescription)")
        }
    }

    /// Aborts a multipart upload session.
    /// Non-throwing; errors are logged.
    func abortForMultiPart(url: URL, storageRef: StorageReference) async {
        let req = self.setHttpRequestForMultiPart(url: url, op: MultiPartOp.abort, storageRef: storageRef)
        do {
            let _ = try await SecureNetworking.secureSession.data(for: req)
            StorageLogger.info("Multipart abort successful for \(storageRef.fullPath)")
        } catch let urlErr as URLError {
            let message = StorageErrorUtilities.handleURLError(urlErr)
            StorageLogger.error("Multipart abort failed for \(storageRef.fullPath): \(message)")
        } catch {
            StorageLogger.error("Multipart abort failed for \(storageRef.fullPath): \(error.localizedDescription)")
        }
    }

    /// Downloads the data for the given storage reference.
    /// - Parameter storageRef: Target storage reference.
    /// - Returns: Raw data for the object.
    /// - Throws: Storage errors mapped via StorageErrorUtilities if the request fails.
    func getData(storageRef: StorageReference) async throws -> Data {
        let req = self.setHttpRequest(storageHelperFunc: .getObj, storageRef: storageRef)

        do {
            let (data, resp) = try await SecureNetworking.secureSession.data(for: req)
            // Validate HTTP status; if not success, map and throw using robust handler
            if let httpResp = resp as? HTTPURLResponse, !(200...299).contains(httpResp.statusCode) {
                do {
                    _ = try handleHttpResponse(data: data, response: resp)
                } catch {
                    throw error
                }
            }
            StorageLogger.info("Downloaded object \(storageRef.fullPath) (\(data.count) bytes)")
            return data
        } catch let urlErr as URLError {
            let message = StorageErrorUtilities.handleURLError(urlErr)
            StorageLogger.error("Download failed for \(storageRef.fullPath): \(message)")
            throw StorageErrorUtilities.internalError(message: message)
        } catch {
            StorageLogger.error("Download failed for \(storageRef.fullPath): \(error.localizedDescription)")
            throw error
        }
    }

    /// Downloads the data for the given storage reference while enforcing a maximum size during transfer.
    /// - Parameters:
    ///   - storageRef: Target storage reference.
    ///   - maxSize: Maximum number of bytes allowed to be buffered in memory.
    /// - Returns: Downloaded data when within max size.
    /// - Throws: `downloadSizeExceeded` if the response exceeds maxSize, or mapped Storage errors.
    func getData(storageRef: StorageReference, maxSize: Int64) async throws -> Data {
        let req = self.setHttpRequest(storageHelperFunc: .getObj, storageRef: storageRef)

        do {
            try await assertMetadataSizeWithinLimit(storageRef: storageRef, maxSize: maxSize)

            let data = try await self.downloadDataWithLimit(request: req, maxSize: maxSize)
            StorageLogger.info("Downloaded object \(storageRef.fullPath) (\(data.count) bytes, max \(maxSize))")
            return data
        } catch let urlErr as URLError {
            let message = StorageErrorUtilities.handleURLError(urlErr)
            StorageLogger.error("Download failed for \(storageRef.fullPath): \(message)")
            throw StorageErrorUtilities.internalError(message: message)
        } catch {
            StorageLogger.error("Download failed for \(storageRef.fullPath): \(error.localizedDescription)")
            throw error
        }
    }

    /// Streams an object download directly to disk.
    /// - Parameters:
    ///   - storageRef: Target storage reference.
    ///   - fileURL: Destination file URL.
    /// - Throws: Storage errors mapped via StorageErrorUtilities if the request fails.
    func downloadToFile(storageRef: StorageReference, fileURL: URL) async throws {
        let req = self.setHttpRequest(storageHelperFunc: .getObj, storageRef: storageRef)

        do {
            if #available(iOS 15.0, tvOS 15.0, watchOS 8.0, macOS 12.0, *) {
                let (tmpURL, resp) = try await SecureNetworking.secureSession.download(for: req)

                guard let httpResp = resp as? HTTPURLResponse else {
                    throw StorageErrorUtilities.internalError(message: "Obtained a non-valid HTTP response.")
                }

                if !(200...299).contains(httpResp.statusCode) {
                    let errData = (try? readBoundedData(from: tmpURL)) ?? Data()
                    _ = try handleHttpResponse(data: errData, response: resp)
                    throw StorageErrorUtilities.internalError(message: "Unexpected HTTP response status: \(httpResp.statusCode)")
                }

                if FileManager.default.fileExists(atPath: fileURL.path) {
                    try FileManager.default.removeItem(at: fileURL)
                }
                try FileManager.default.moveItem(at: tmpURL, to: fileURL)
                StorageLogger.info("Downloaded object \(storageRef.fullPath) to \(fileURL.path)")
            } else {
                // Fallback for older macOS SDKs.
                // Stream directly to disk instead of buffering the full object in memory.
                try await self.streamDownloadToFile(request: req, fileURL: fileURL)
            }
        } catch let urlErr as URLError {
            let message = StorageErrorUtilities.handleURLError(urlErr)
            StorageLogger.error("Download-to-file failed for \(storageRef.fullPath): \(message)")
            throw StorageErrorUtilities.internalError(message: message)
        } catch {
            StorageLogger.error("Download-to-file failed for \(storageRef.fullPath): \(error.localizedDescription)")
            throw error
        }
    }

    /// Uploads a local file in a single request without buffering the entire file in app memory.
    /// - Parameters:
    ///   - storageRef: Target storage reference.
    ///   - fileURL: Local file URL.
    ///   - mimeType: MIME type for the upload.
    ///   - uploadTask: The associated upload task.
    ///   - metadata: Optional metadata to associate with the uploaded object.
    /// - Returns: Response dictionary containing upload result metadata.
    /// - Throws: Storage errors mapped via StorageErrorUtilities if the request fails.
    func putFile(storageRef: StorageReference, fileURL: URL, mimeType: String = "", uploadTask: StorageUploadTask, metadata: StorageMetadata? = nil) async throws -> [String: Any] {
        let req = self.setHttpRequest(storageHelperFunc: .putObj, storageRef: storageRef, data: nil, mimeType: mimeType, metadata: metadata)
        do {
            let (data, resp) = try await SecureNetworking.secureSession.upload(for: req, fromFile: fileURL)
            let result = try handleHttpResponse(data: data, response: resp)
            StorageLogger.info("Single-part file upload completed for \(storageRef.fullPath)")
            return result
        } catch let urlErr as URLError {
            let message = StorageErrorUtilities.handleURLError(urlErr)
            StorageLogger.error("File upload failed for \(storageRef.fullPath): \(message)")
            throw StorageErrorUtilities.internalError(message: message)
        } catch {
            StorageLogger.error("File upload failed for \(storageRef.fullPath): \(error.localizedDescription)")
            throw error
        }
    }

    /// Deletes the object referenced by storageRef.
    /// - Parameter storageRef: Target storage reference.
    /// - Throws: Storage errors mapped via StorageErrorUtilities if the request fails.
    func delData(storageRef: StorageReference) async throws {
        let req = self.setHttpRequest(storageHelperFunc: .delObj, storageRef: storageRef)

        do {
            let (data, resp) = try await SecureNetworking.secureSession.data(for: req)
            if let httpResp = resp as? HTTPURLResponse, !(200...299).contains(httpResp.statusCode) {
                do {
                    _ = try handleHttpResponse(data: data, response: resp)
                } catch {
                    throw error
                }
            }
            StorageLogger.info("Deleted object \(storageRef.fullPath)")
        } catch let urlErr as URLError {
            let message = StorageErrorUtilities.handleURLError(urlErr)
            StorageLogger.error("Delete failed for \(storageRef.fullPath): \(message)")
            throw StorageErrorUtilities.internalError(message: message)
        } catch {
            StorageLogger.error("Delete failed for \(storageRef.fullPath): \(error.localizedDescription)")
            throw error
        }
    }

    /// Lists objects under the given path.
    /// - Parameters:
    ///   - storageRef: Target storage reference (prefix).
    ///   - maxResults: Maximum number of results to return.
    ///   - pageToken: Page token for pagination. If nil, defaults to "0".
    /// - Returns: A response dictionary suitable for validation by StorageReference.validateListResDict.
    /// - Throws: Storage errors mapped via StorageErrorUtilities if the request fails.
    func listObjs(storageRef: StorageReference, maxResults: Int, pageToken: String?, recurse: Bool = false) async throws -> [String: Any] {

        let req = self.setHttpRequest(storageHelperFunc: .lstObjs, storageRef: storageRef, maxResults: maxResults, pageToken: pageToken, accessType: nil, recurse: recurse)
        do {
            let (data, resp) = try await SecureNetworking.secureSession.data(for: req)
            let res = try handleHttpResponse(data: data, response: resp)
            StorageLogger.info("Listed objects under \(storageRef.fullPath)")
            return res
        } catch let urlErr as URLError {
            let message = StorageErrorUtilities.handleURLError(urlErr)
            StorageLogger.error("List objects failed for \(storageRef.fullPath): \(message)")
            throw StorageErrorUtilities.internalError(message: message)
        } catch {
            StorageLogger.error("List objects failed for \(storageRef.fullPath): \(error.localizedDescription)")
            throw error
        }
    }

    /// Retrieves metadata for the given object.
    /// - Parameter storageRef: Target storage reference.
    /// - Returns: A response dictionary suitable for validation by StorageReference.validateMetadataDict.
    /// - Throws: Storage errors mapped via StorageErrorUtilities if the request fails.
    func getMetadata(storageRef: StorageReference) async throws -> [String: Any] {
        let req = self.setHttpRequest(storageHelperFunc: .getMetadata, storageRef: storageRef)
        do {
            let (data, resp) = try await SecureNetworking.secureSession.data(for: req)
            let res = try handleHttpResponse(data: data, response: resp)
            StorageLogger.info("Fetched metadata for \(storageRef.fullPath)")
            return res
        } catch let urlErr as URLError {
            let message = StorageErrorUtilities.handleURLError(urlErr)
            StorageLogger.error("Get metadata failed for \(storageRef.fullPath): \(message)")
            throw StorageErrorUtilities.internalError(message: message)
        } catch {
            StorageLogger.error("Get metadata failed for \(storageRef.fullPath): \(error.localizedDescription)")
            throw error
        }
    }

    /// Generates a pre-auth URL for read/write operations.
    /// - Parameters:
    ///   - storageRef: Target storage reference.
    ///   - accessType: "ObjectRead" or "ObjectWrite".
    ///   - mimeType: Required when accessType == "ObjectWrite".
    ///   - metadata: Full metadata object to include in pre-auth request.
    /// - Returns: Response dictionary containing URL/PAR data.
    /// - Throws: Storage errors mapped via StorageErrorUtilities if the request fails.
    func genPreAuth(storageRef: StorageReference, accessType: String, mimeType: String? = nil, metadata: StorageMetadata? = nil) async throws -> [String: Any] {

        if accessType == "ObjectRead" {
            assert (mimeType == nil)
        } else if accessType == "ObjectWrite" {
            assert (mimeType != nil)
        }

        let req = self.setHttpRequest(storageHelperFunc: .genPreAuth,
                                      storageRef: storageRef,
                                      mimeType: mimeType,
                                      accessType: accessType,
                                      metadata: metadata)
        do {
            let (data, resp) = try await SecureNetworking.secureSession.data(for: req)
            let res = try handleHttpResponse(data: data, response: resp)
            StorageLogger.info("Generated pre-auth for \(storageRef.fullPath) [\(accessType)]")
            return res
        } catch let urlErr as URLError {
            let message = StorageErrorUtilities.handleURLError(urlErr)
            StorageLogger.error("Generate pre-auth failed for \(storageRef.fullPath) [\(accessType)]: \(message)")
            throw StorageErrorUtilities.internalError(message: message)
        } catch {
            StorageLogger.error("Generate pre-auth failed for \(storageRef.fullPath) [\(accessType)]: \(error.localizedDescription)")
            throw error
        }
    }
}
