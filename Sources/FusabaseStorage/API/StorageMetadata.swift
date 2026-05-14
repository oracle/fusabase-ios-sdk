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


/// Describes metadata associated with a stored object.
///
/// StorageMetadata includes both read-only fields returned by the service (such as size,
/// timestamps, and identifiers) and writable fields you may set before an upload (such as
/// contentType or customMetadata). Instances are value containers only; they do not
/// perform network requests by themselves.
@available(iOS 15, tvOS 13, macOS 10.15, watchOS 7, *)
/**
 Contains metadata for a storage object, including size, content type, and custom metadata.
 */
public class StorageMetadata {
    
    // MARK: - Read-only Properties
    
    /// The bucket containing this object. (No)
    public private(set) var bucket: String?
    
    /// The object's generation. (No)
    public private(set) var generation: String?
    
    /// Versioning for metadata changes. (No)
    public private(set) var metageneration: String?
    
    /// Full path of the object. (No)
    public private(set) var fullPath: String?
    
    /// Name of the object. (No)
    public private(set) var name: String?
    
    /// Size of the object in bytes. (No)
    public private(set) var size: Int64?
    
    /// Creation time of the object. (No)
    public private(set) var timeCreated: Date?
    
    /// Last updated time of the object. (No)
    public private(set) var updated: Date?
    
    // MARK: - Writable Properties
    
    /// MD5 hash of the object, base64 encoded. (Yes)
    public var md5Hash: String?
    
    /// Cache-Control header. (Yes)
    public var cacheControl: String?
    
    /// Content-Disposition header. (Yes)
    public var contentDisposition: String?
    
    /// Content-Encoding header. (Yes)
    public var contentEncoding: String?
    
    /// Content-Language header. (Yes)
    public var contentLanguage: String?
    
    /// Content-Type header. (Yes)
    /// Must be a valid MIME type in the format "type/subtype".
    public var contentType: String? {
        didSet {
            if let contentType = contentType, !isValidContentType(contentType) {
                StorageLogger.warning("Invalid contentType format: \(contentType). Expected format: type/subtype (e.g., 'text/plain', 'image/jpeg')")
            }
        }
    }
    
    /// User-provided custom metadata. (Yes)
    public var customMetadata: [String: String]?
    
    // MARK: - Initializer
    
    /// Creates an empty metadata container.
    public init() {
        
    }
    
    /// Creates a populated metadata container.
    /// - Parameters:
    ///   - bucket: The bucket containing the object.
    ///   - fullPath: The full path of the object within the bucket.
    ///   - size: Size of the object in bytes.
    ///   - updated: The last updated timestamp.
    ///   - timeCreated: The creation timestamp.
    ///   - name: The object's name (last path component).
    ///   - contentType: The MIME type of the object.
    ///   - md5Hash: The base64-encoded MD5 hash of the object contents.
    public init(bucket: String,
                fullPath: String,
                size: Int64,
                updated: Date,
                timeCreated: Date,
                name: String,
                contentType: String,
                md5Hash: String) {
        
        self.bucket = bucket
        self.fullPath = fullPath
        self.size = size
        self.updated = updated
        self.timeCreated = timeCreated
        self.name = name
        self.contentType = contentType
        self.md5Hash = md5Hash
    }
    
    /// Returns a dictionary representation of the metadata, omitting nil fields.
    /// Dates are formatted as "yyyy-MM-dd'T'HH:mm:ss.SSSSSS" to match validation/parsing.
    /// - Returns: A dictionary containing non-nil metadata fields suitable for transmission or logging.
    public func dictionaryRepresentation() -> [String: Any] {
        var dict: [String: Any] = [:]
        
        if let bucket = self.bucket { dict["bucket"] = bucket }
        if let fullPath = self.fullPath { dict["fullPath"] = fullPath }
        if let name = self.name { dict["name"] = name }
        if let size = self.size { dict["size"] = size }
        
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
        if let updated = self.updated { dict["updated"] = formatter.string(from: updated) }
        if let timeCreated = self.timeCreated { dict["timeCreated"] = formatter.string(from: timeCreated) }
        
        if let contentType = self.contentType { dict["contentType"] = contentType }
        if let md5Hash = self.md5Hash { dict["md5Hash"] = md5Hash }
        
        if let generation = self.generation { dict["generation"] = generation }
        if let metageneration = self.metageneration { dict["metageneration"] = metageneration }
        if let cacheControl = self.cacheControl { dict["cacheControl"] = cacheControl }
        if let contentDisposition = self.contentDisposition { dict["contentDisposition"] = contentDisposition }
        if let contentEncoding = self.contentEncoding { dict["contentEncoding"] = contentEncoding }
        if let contentLanguage = self.contentLanguage { dict["contentLanguage"] = contentLanguage }
        if let customMetadata = self.customMetadata { dict["customMetadata"] = customMetadata }
        
        return dict
    }

    // MARK: - Private Methods

    /// Validates that the content type follows MIME type format (type/subtype).
    /// - Parameter contentType: The content type string to validate.
    /// - Returns: True if the content type is valid, false otherwise.
    private func isValidContentType(_ contentType: String) -> Bool {
        // Basic MIME type validation: type/subtype
        // Allows alphanumeric characters, hyphens, and dots
        let mimeTypeRegex = "^[a-zA-Z0-9][a-zA-Z0-9\\-\\.]*\\/[a-zA-Z0-9][a-zA-Z0-9\\-\\.]*$"
        let regex = try? NSRegularExpression(pattern: mimeTypeRegex, options: [])
        let range = NSRange(location: 0, length: contentType.count)
        return regex?.firstMatch(in: contentType, options: [], range: range) != nil
    }
}
