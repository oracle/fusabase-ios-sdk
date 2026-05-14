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
 Internal class that provides useful methods for triggering specific Oracledb error messages.
 */
@available(iOS 15, tvOS 13, macOS 10.15, macCatalyst 13, watchOS 7, *)
class OracledbErrorUtilities {
    
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
        - Parameter code: OracledbErrorCode
        - Parameter userInfo: [String: Any]? = nil
        - Returns: NSError containing the needed information
     */
    static func error(code: OracledbErrorCode, userInfo: [String: Any]? = nil) -> Error {
        var errorUserInfo: [String: Any] = userInfo ?? [:]
        
        if errorUserInfo[NSLocalizedDescriptionKey] == nil {
            errorUserInfo[NSLocalizedDescriptionKey] = code.errorDescription
        }
        
        if let localizedDescription = errorUserInfo[NSLocalizedDescriptionKey] as? String,
           localizedDescription.isEmpty {
            errorUserInfo[NSLocalizedDescriptionKey] = code.errorDescription
        }
        
        errorUserInfo[OracledbErrors.userInfoNameKey] = code.errorCodeString
        
        return NSError(
            domain: OracledbErrors.OracledbErrorDomain,
            code: code.rawValue,
            userInfo: errorUserInfo
        )
    }
    
    /**
        Method that returns an NSError containing the error domain, the error code and the error description.
        ## This serves as a helper that receives a string and converts it into a userInfo object.
        - Parameter code: OracledbErrorCode
        - Parameter message: String?
        - Returns: NSError containing the needed information
     */
    static func error(code: OracledbErrorCode, message: String?) -> Error {
        let userInfo: [String: Any]?
        if let message {
            userInfo = [NSLocalizedDescriptionKey: message]
        } else {
            userInfo = nil
        }
        return error(code: code, userInfo: userInfo)
    }
    
    // MARK: - Convenience creators per OracledbErrorCode
    
    static func unknownError(message: String? = nil) -> Error {
        return error(code: .unknown, message: message)
    }
    static func invalidArgumentError(message: String? = nil) -> Error {
        return error(code: .invalidArgument, message: message)
    }
    static func invalidPathError(message: String? = nil) -> Error {
        return error(code: .invalidPath, message: message)
    }
    static func invalidRefTypeError(message: String? = nil) -> Error {
        return error(code: .invalidRefType, message: message)
    }
    static func invalidURLError(message: String? = nil) -> Error {
        return error(code: .invalidURL, message: message)
    }
    static func jsonSerializationFailed(message: String? = nil) -> Error {
        return error(code: .jsonSerializationFailed, message: message)
    }
    static func unauthenticatedError(message: String? = nil) -> Error {
        return error(code: .unauthenticated, message: message)
    }
    static func unauthorizedError(message: String? = nil) -> Error {
        return error(code: .unauthorized, message: message)
    }
    static func networkError(message: String? = nil) -> Error {
        return error(code: .networkError, message: message)
    }
    static func invalidResponse(message: String? = nil) -> Error {
        return error(code: .invalidResponse, message: message)
    }
    static func invalidJSON(message: String? = nil) -> Error {
        return error(code: .invalidJSON, message: message)
    }
    static func notFound(message: String? = nil) -> Error {
        return error(code: .notFound, message: message)
    }
    static func internalError(message: String? = nil) -> Error {
        return error(code: .internalError, message: message)
    }
    static func preconditionFailed(message: String? = nil) -> Error {
        return error(code: .preconditionFailed, message: message)
    }
    static func emptyAccessToken(message: String? = nil) -> Error {
        return error(code: .emptyAccessToken, message: message)
    }
}
