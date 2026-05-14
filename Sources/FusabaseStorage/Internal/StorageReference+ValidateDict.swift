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

    /// Parses an RFC 3339/ RFC 2616 / ISO-8601 timestamp into epoch milliseconds.
    private func parseToEpochMillis(_ timestamp: String) -> Int64 {
        let isoFormatter = DateFormatter()
        isoFormatter.locale = Locale(identifier: "en_US_POSIX")
        isoFormatter.timeZone = TimeZone(identifier: "UTC")

        // 1. Try ISO-8601 with microseconds (common in getMetadata responses)
        isoFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
        if let date = isoFormatter.date(from: timestamp) {
            return Int64(date.timeIntervalSince1970 * 1000)
        }

        if let date = ISO8601DateFormatter().date(from: timestamp) {
            return Int64(date.timeIntervalSince1970 * 1000)
        }

        // 7. Try ISO_LOCAL_DATE_TIME (assume UTC)
        isoFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        if let date = isoFormatter.date(from: timestamp) {
            return Int64(date.timeIntervalSince1970 * 1000)
        }

        // 4. Oracle TIMESTAMP without AM/PM
        isoFormatter.dateFormat = "dd-MMM-yy HH.mm.ss.SSSSSS"
        isoFormatter.locale = Locale(identifier: "en_US_POSIX")
        if let date = isoFormatter.date(from: timestamp) {
            return Int64(date.timeIntervalSince1970 * 1000)
        }

        // 5. Oracle TIMESTAMP with AM/PM
        isoFormatter.dateFormat = "dd-MMM-yy hh.mm.ss.SSSSSS a"
        if let date = isoFormatter.date(from: timestamp) {
            return Int64(date.timeIntervalSince1970 * 1000)
        }

        // 6. Human format
        isoFormatter.dateFormat = "EEE MMM dd HH:mm:ss zzz yyyy"
        isoFormatter.locale = Locale(identifier: "en_US_POSIX")
        if let date = isoFormatter.date(from: timestamp) {
            return Int64(date.timeIntervalSince1970 * 1000)
        }

        // 7. RFC 1123 format
        isoFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        if let date = isoFormatter.date(from: timestamp) {
            return Int64(date.timeIntervalSince1970 * 1000)
        }

        StorageLogger.error("Failed to parse timestamp: \(timestamp)")
        return 0
    }
    
    internal func validatePreAuthDictForRead(preAuthDict: [String: Any]) -> URL? {
        // Required keys list
        let requiredKeys = ["PAR_ID", "URL"]
        
        // Check if all required keys exist
        for key in requiredKeys {
            if preAuthDict[key] == nil {
                StorageLogger.error("Missing required preAuth key: \(key)")
                return nil
            }
        }
        
        // Parse URL
        if let preAuthUrlStr = preAuthDict["URL"] as? String {
            let urlStr = self.storageHelper.endWithParProjectId + "/" + preAuthUrlStr
            
            StorageLogger.debug("PreAuth READ URL: \(urlStr)")
            return URL(string: urlStr)
        } else {
            StorageLogger.error("URL key is missing or not a valid string URL")
            return nil
        }
    }
    
    internal func validatePreAuthDictForWrite(preAuthDict: [String: Any]) -> URL? {
        // Try to get the URL from different possible keys
        // For DBFS: accessUri, for OCI: might be URL or accessUri
        var urlKey: String? = nil
        var preAuthUrlStr: String? = nil

        if let accessUri = preAuthDict["accessUri"] as? String {
            urlKey = "accessUri"
            preAuthUrlStr = accessUri
        } else if let url = preAuthDict["URL"] as? String {
            urlKey = "URL"
            preAuthUrlStr = url
        }

        guard let key = urlKey, let urlStr = preAuthUrlStr else {
            StorageLogger.error("Missing URL key (tried 'accessUri' and 'URL') in pre-auth response: \(preAuthDict)")
            return nil
        }

        // For DBFS, construct the full PAR URL; for OCI, might be direct URL
        let fullUrlStr: String
        if key == "accessUri" {
            // DBFS style - construct PAR URL
            fullUrlStr = self.storageHelper.endWithParProjectId + "/" + urlStr
        } else {
            // OCI style - might be direct URL
            fullUrlStr = urlStr
        }

        StorageLogger.debug("PreAuth WRITE URL (\(key)): \(fullUrlStr)")
        return URL(string: fullUrlStr)
    }
    
    internal func validateMetadataDict(metadataDict: [String: Any]) -> StorageMetadata? {
        // Handle different key variations like Android does
        let timeCreatedStr = (metadataDict["timeCreated"] as? String) ??
                            (metadataDict["time-created"] as? String) ?? ""
        let updatedStr = (metadataDict["updated"] as? String) ??
                        (metadataDict["last-modified"] as? String) ?? ""

        guard
            let bucket = metadataDict["bucket"] as? String,
            let fullPath = metadataDict["fullPath"] as? String,
            let size = (metadataDict["size"] as? Int64)
                ?? (metadataDict["size"] as? Int).map(Int64.init)
                ?? (metadataDict["size"] as? String).flatMap({ Int64($0) }),
            let name = metadataDict["name"] as? String,
            let contentType = metadataDict["contentType"] as? String,
            !timeCreatedStr.isEmpty,
            !updatedStr.isEmpty
        else {
            StorageLogger.error("Missing required metadata fields")
            return nil
        }

        let md5Hash = (metadataDict["md5Hash"] as? String)
            ?? (metadataDict["md5sum"] as? String)
            ?? (metadataDict["opc-multipart-md5"] as? String)
            ?? ""

        guard !md5Hash.isEmpty else {
            StorageLogger.error("Missing MD5 hash in any expected format")
            return nil
        }

        // Parse dates with multiple format support like Android
        let updatedMillis = parseToEpochMillis(updatedStr)
        let timeCreatedMillis = parseToEpochMillis(timeCreatedStr)

        guard updatedMillis != 0, timeCreatedMillis != 0 else {
            StorageLogger.error("Failed to parse date fields")
            return nil
        }

        let updated = Date(timeIntervalSince1970: TimeInterval(updatedMillis / 1000))
        let timeCreated = Date(timeIntervalSince1970: TimeInterval(timeCreatedMillis / 1000))

        return StorageMetadata(
            bucket: bucket,
            fullPath: fullPath,
            size: size,
            updated: updated,
            timeCreated: timeCreated,
            name: name,
            contentType: contentType,
            md5Hash: md5Hash
        )
    }

    
    internal func validateListResDict(listResDict: [String: Any]) -> StorageListResult? {

        var items: [StorageReference] = []
        var prefixes: [StorageReference] = []
        var pageToken: String? = nil

        // Parse 'items' - can be array of strings, array of dictionaries, or missing (treated as empty)
        if let itemsArray = listResDict["items"] as? [[String: Any]] {
            for itemDict in itemsArray {
                guard let name = itemDict["name"] as? String else {
                    StorageLogger.error("Item dictionary missing 'name' key or not a string: \(itemDict)")
                    return nil
                }
                let itemRef = StorageReference(storage: self.storage, path: name)
                items.append(itemRef)
            }
        } else if let itemsArray = listResDict["items"] as? [String] {
            for name in itemsArray {
                let itemRef = StorageReference(storage: self.storage, path: name)
                items.append(itemRef)
            }
        } else if listResDict["items"] != nil {
            StorageLogger.error("'items' key present but not an array of dictionaries or strings")
            return nil
        }
        // If 'items' key is missing, treat as empty array

        // Parse 'prefixes' - can be array of strings, array of dictionaries, or missing (treated as empty)
        if let prefixesArray = listResDict["prefixes"] as? [[String: Any]] {
            for prefixDict in prefixesArray {
                guard let name = prefixDict["name"] as? String, !name.isEmpty else {
                    // Skip empty or invalid prefix names
                    continue
                }
                let prefixRef = StorageReference(storage: self.storage, path: name)
                prefixes.append(prefixRef)
            }
        } else if let prefixesArray = listResDict["prefixes"] as? [String] {
            for name in prefixesArray where !name.isEmpty {
                let prefixRef = StorageReference(storage: self.storage, path: name)
                prefixes.append(prefixRef)
            }
        } else if let prefixesArray = listResDict["prefixes"] as? [Any] {
            // Handle malformed responses where server returns array of empty strings or mixed types
            for item in prefixesArray {
                if let name = item as? String, !name.isEmpty {
                    let prefixRef = StorageReference(storage: self.storage, path: name)
                    prefixes.append(prefixRef)
                }
                // Skip non-string items or empty strings
            }
        } else if listResDict["prefixes"] != nil {
            StorageLogger.error("'prefixes' key present but not an array of dictionaries or strings")
            return nil
        }
        // If 'prefixes' key is missing, treat as empty array

        // Parse 'nextPageToken'
        if let nextPage = listResDict["nextPageToken"] {
            if let nextPageInt = nextPage as? Int, nextPageInt != -1 {
                pageToken = String(nextPageInt)
            } else if let nextPageStr = nextPage as? String, nextPageStr != "-1" {
                pageToken = nextPageStr
            }
        }

        return StorageListResult(items: items, prefixes: prefixes, pageToken: pageToken)
    }

}
