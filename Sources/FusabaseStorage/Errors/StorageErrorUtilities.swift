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

/**
 Internal class that provides useful methods for triggering specific Storage error messages.
 */
@available(iOS 15, tvOS 13, macOS 10.15, macCatalyst 13, watchOS 7, *)
class StorageErrorUtilities {
    
    /**
        Internal method used to handle URLErrors
        - Parameter error: URLError
        - Returns: string containing error message
     */
    static func handleURLError(_ error: URLError) -> String {
        switch error.code {
        case .notConnectedToInternet:
            return "No internet connection."
        case .timedOut:
            return "The request timed out."
        case .cannotFindHost:
            return "Cannot find host."
        case .cannotConnectToHost:
            return "Can not connect to host."
        case .networkConnectionLost:
            return "Network connection was lost."
        case .secureConnectionFailed:
            return "SSL/TLS error."
        case .cancelled:
            return "The request was cancelled."
        default:
            return "Other URLError: \(error.localizedDescription)"
        }
    }
    
    /**
        Method that returns an NSError containing the error domain, the error code and the error description.
        - Parameter code: StorageErrorCode
        - Parameter userInfo: [String: Any]? = nil
        - Returns: NSError containing the needed information
     */
    static func error(code: StorageErrorCode, userInfo: [String: Any]? = nil) -> Error {
        var errorUserInfo: [String: Any] = userInfo ?? [:]
        
        if errorUserInfo[NSLocalizedDescriptionKey] == nil {
            errorUserInfo[NSLocalizedDescriptionKey] = code.errorDescription
        }
        
        if let localizedDescription = errorUserInfo[NSLocalizedDescriptionKey] as? String,
           localizedDescription.isEmpty {
            errorUserInfo[NSLocalizedDescriptionKey] = code.errorDescription
        }
        
        errorUserInfo[StorageErrors.userInfoNameKey] = code.errorCodeString
        
        return NSError(
            domain: StorageErrors.StorageErrorDomain,
            code: code.rawValue,
            userInfo: errorUserInfo
        )
    }
    
    /**
        Method that returns an NSError containing the error domain, the error code and the error description.
        ## This serves as a helper that receives a string and converts it into a userInfo object.
        - Parameter code: StorageErrorCode
        - Parameter message: String?
        - Returns: NSError containing the needed information
     */
    static func error(code: StorageErrorCode, message: String?) -> Error {
        let userInfo: [String: Any]?
        if let message {
            userInfo = [NSLocalizedDescriptionKey: message]
        } else {
            userInfo = nil
        }
        return error(code: code, userInfo: userInfo)
    }
    
    // MARK: - Convenience creators per StorageErrorCode
    
    static func unknownError(message: String? = nil) -> Error {
        return error(code: .unknown, message: message)
    }
    static func objectNotFoundError(message: String? = nil) -> Error {
        return error(code: .objectNotFound, message: message)
    }
    static func bucketNotFoundError(message: String? = nil) -> Error {
        return error(code: .bucketNotFound, message: message)
    }
    static func projectNotFoundError(message: String? = nil) -> Error {
        return error(code: .projectNotFound, message: message)
    }
    static func quotaExceededError(message: String? = nil) -> Error {
        return error(code: .quotaExceeded, message: message)
    }
    static func unauthenticatedError(message: String? = nil) -> Error {
        return error(code: .unauthenticated, message: message)
    }
    static func unauthorizedError(message: String? = nil) -> Error {
        return error(code: .unauthorized, message: message)
    }
    static func retryLimitExceededError(message: String? = nil) -> Error {
        return error(code: .retryLimitExceeded, message: message)
    }
    static func nonMatchingChecksumError(message: String? = nil) -> Error {
        return error(code: .nonMatchingChecksum, message: message)
    }
    static func downloadSizeExceededError(message: String? = nil) -> Error {
        return error(code: .downloadSizeExceeded, message: message)
    }
    static func cancelledError(message: String? = nil) -> Error {
        return error(code: .cancelled, message: message)
    }
    static func invalidArgumentError(message: String? = nil) -> Error {
        return error(code: .invalidArgument, message: message)
    }
    static func bucketMismatchError(message: String? = nil) -> Error {
        return error(code: .bucketMismatch, message: message)
    }
    static func internalError(message: String? = nil) -> Error {
        return error(code: .internalError, message: message)
    }
    static func pathError(message: String? = nil) -> Error {
        return error(code: .pathError, message: message)
    }
}
