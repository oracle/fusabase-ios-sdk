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

/// A client for interacting with Fusabase Storage.
///
/// Storage is the main entry point to configure retry behavior and create StorageReference
/// objects to read and write data. Instances are lightweight and can be used across threads.
@available(iOS 15, tvOS 13, macOS 10.15, watchOS 7, *)
/**
 The main class for managing cloud storage in Oracle FUSABASE applications.

 Access all storage methods through this class. Storage references are obtained via the `reference()` method.

 This class follows the singleton pattern. Access the shared instance using `storage()`.

 To associate with a specific app, use `storage(app: FusabaseApp)`.
 */

public class Storage {

    // MARK: - Properties

    /// The application instance used to configure this storage client.
    public let app: FusabaseApp
    /// The base storage bucket URL associated with this client.
    public let url: String
    // Default logical root path for this Storage instance. If non-empty, reference()
    // will return a reference rooted at this path instead of the bucket root.
    // Tests may implicitly set this via creating a top-level child (e.g., "metadataTests").
    internal var defaultRootPath: String = ""

    /// Maximum time, in seconds, to retry non-upload and non-download operations
    /// such as listing objects or retrieving metadata.
    open var maxOperationRetryTime: TimeInterval = 10.0
    /// Maximum time, in seconds, to retry upload operations.
    open var maxUploadRetryTime: TimeInterval = 10.0
    /// Maximum time, in seconds, to retry download operations.
    open var maxDownloadRetryTime: TimeInterval = 10.0

    // MARK: - Initializer

    private init(app: FusabaseApp, url: String) {
        self.app = app
        self.url = url
        StorageLogger.info("Storage instance initialized with bucket: \(url)")
    }

    // MARK: - Static Constructors

    // @objc(storage)
    /// Returns the shared Storage instance configured for the default FusabaseApp.
    ///
    /// - Returns: A Storage client bound to the default application's bucket.
    /// - Note: This method will terminate the process via fatalError if FusabaseApp.app() is not configured.
    open class func storage() -> Storage {
        guard let app = FusabaseApp.app() else {
            fatalError("FusabaseApp is not configured.")
        }
        return Storage(app: app, url: app.options.storageBucket)
    }
    
//    open class func storage(url: String) -> Storage {
//    }

    // @objc(storageWithApp:)
    /// Creates a Storage instance for the specified app using its configured bucket URL.
    /// - Parameter app: The FusabaseApp to bind the storage client to.
    /// - Returns: A Storage client bound to the given app.
    open class func storage(app: FusabaseApp) -> Storage {
        return Storage(app: app, url: app.options.storageBucket)
    }

    // @objc(storageWithApp:URL:)
    /// Creates a Storage instance for the specified app and bucket URL.
    /// - Parameters:
    ///   - app: The FusabaseApp to bind the storage client to.
    ///   - url: The base bucket URL to use for all references created by this client.
    /// - Returns: A Storage client bound to the given app and bucket URL.
    open class func storage(app: FusabaseApp, url: String) -> Storage {
        return Storage(app: app, url: url)
    }


    // MARK: - Instance Methods

    /// Returns a reference to the root of the bucket associated with this client.
    /// - Returns: A StorageReference pointing to the root path ("").
    @available(iOS 15, tvOS 13, macOS 10.15, watchOS 7, *)
    open func reference() -> StorageReference {
        // If a logical root was established (e.g., by creating a top-level child),
        // return a reference anchored at that path. Otherwise return the true bucket root.
        let path = self.defaultRootPath
        return StorageReference(storage: self, path: path)
    }

    /// Returns a reference for the given path relative to the bucket root.
    /// - Parameter path: A UTF-8 path string using forward slashes (/) to separate folders. Do not prefix with a leading slash.
    /// - Returns: A StorageReference pointing to the provided path.
    @available(iOS 15, tvOS 13, macOS 10.15, watchOS 7, *)
    open func reference(withPath path: String) -> StorageReference {
        return StorageReference(storage: self, path: path)
    }
    
    /// Returns a reference for the given URL.
    ///
    /// The current implementation treats the provided string as a full path. Support for schemes
    /// such as "gs://" and HTTP(S) URLs may be added in the future.
    /// - Parameter url: A string representing either a full storage path or a bucket URL.
    /// - Returns: A StorageReference constructed from the provided URL.
    @available(iOS 15, tvOS 13, macOS 10.15, watchOS 7, *)
    open func reference(forURL url: String) -> StorageReference {
        // Treat the provided URL string as a full path for now.
        // TODO: Support parsing 'gs://' or HTTP(S) URLs to extract path segments.
        return StorageReference(storage: self, path: url)
    }
}
