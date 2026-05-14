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

@available(iOS 15, tvOS 13, macOS 10.15, watchOS 7, *)
public extension StorageErrorCode {
    
    /// Human‑readable description for the error code.
    ///
    /// This string is suitable for displaying to users or logging. It is localized
    /// only by convention in this SDK; if you need localization, wrap this value
    /// with your own localization mechanism.
    var errorDescription: String {
        switch self {
        case .unknown:
            return kStorageErrorUnknown
        case .objectNotFound:
            return kStorageErrorObjectNotFound
        case .bucketNotFound:
            return kStorageErrorBucketNotFound
        case .projectNotFound:
            return kStorageErrorProjectNotFound
        case .quotaExceeded:
            return kStorageErrorQuotaExceeded
        case .unauthenticated:
            return kStorageErrorUnauthenticated
        case .unauthorized:
            return kStorageErrorUnauthorized
        case .retryLimitExceeded:
            return kStorageErrorRetryLimitExceeded
        case .nonMatchingChecksum:
            return kStorageErrorNonMatchingChecksum
        case .downloadSizeExceeded:
            return kStorageErrorDownloadSizeExceeded
        case .cancelled:
            return kStorageErrorCancelled
        case .invalidArgument:
            return kStorageErrorInvalidArgument
        case .bucketMismatch:
            return kStorageErrorBucketMismatch
        case .internalError:
            return kStorageErrorInternal
        case .pathError:
            return kStorageErrorPath
        }
    }
    
    /// Stable, programmatic string identifier for the error code.
    ///
    /// Useful for analytics, feature flags, or switch statements that should not
    /// depend on localized text. The returned value is intended to remain stable
    /// across SDK versions.
    var errorCodeString: String {
        switch self {
        case .unknown:
            return "ERROR_STORAGE_UNKNOWN"
        case .objectNotFound:
            return "ERROR_STORAGE_OBJECT_NOT_FOUND"
        case .bucketNotFound:
            return "ERROR_STORAGE_BUCKET_NOT_FOUND"
        case .projectNotFound:
            return "ERROR_STORAGE_PROJECT_NOT_FOUND"
        case .quotaExceeded:
            return "ERROR_STORAGE_QUOTA_EXCEEDED"
        case .unauthenticated:
            return "ERROR_STORAGE_UNAUTHENTICATED"
        case .unauthorized:
            return "ERROR_STORAGE_UNAUTHORIZED"
        case .retryLimitExceeded:
            return "ERROR_STORAGE_RETRY_LIMIT_EXCEEDED"
        case .nonMatchingChecksum:
            return "ERROR_STORAGE_NON_MATCHING_CHECKSUM"
        case .downloadSizeExceeded:
            return "ERROR_STORAGE_DOWNLOAD_SIZE_EXCEEDED"
        case .cancelled:
            return "ERROR_STORAGE_CANCELLED"
        case .invalidArgument:
            return "ERROR_STORAGE_INVALID_ARGUMENT"
        case .bucketMismatch:
            return "ERROR_STORAGE_BUCKET_MISMATCH"
        case .internalError:
            return "ERROR_STORAGE_INTERNAL_ERROR"
        case .pathError:
            return "ERROR_STORAGE_PATH_ERROR"
        }
    }
}

// MARK: - Strings

private let kStorageErrorUnknown = "An unknown storage error occurred."
private let kStorageErrorObjectNotFound = "No object exists at the desired reference."
private let kStorageErrorBucketNotFound = "No bucket is configured for Cloud Storage."
private let kStorageErrorProjectNotFound = "No project is configured for Cloud Storage."
private let kStorageErrorQuotaExceeded = "Quota on your Cloud Storage bucket has been exceeded."
private let kStorageErrorUnauthenticated = "User is not authenticated. Please authenticate and try again."
private let kStorageErrorUnauthorized = "User does not have permission to access the desired resource."
private let kStorageErrorRetryLimitExceeded = "The operation could not be completed within the retry limit."
private let kStorageErrorNonMatchingChecksum = "The file checksum does not match the server's received file."
private let kStorageErrorDownloadSizeExceeded = "The size of the downloaded data exceeds the maximum allowed size."
private let kStorageErrorCancelled = "The operation was cancelled."
private let kStorageErrorInvalidArgument = "The argument passed to the function is invalid."
private let kStorageErrorBucketMismatch = "The supplied bucket does not match the configured bucket."
private let kStorageErrorInternal = "An internal error occurred. Please try again."
private let kStorageErrorPath = "Invalid path specified for the storage reference."
