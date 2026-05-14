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
    Internal class that provides useful methods for triggering specifc error messages.
 */
@available(iOS 15, tvOS 13, macOS 10.15, macCatalyst 13, watchOS 7, *)
class AuthErrorUtilities {
    
    /**
        Internal method used to handle URLErrors
        - Parameter error: URLError
        - Returns : string containing error message
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
        - Parameter code: AuthErrorCode
        - Parameter userInfo: [String: Any]? = nil
        - Returns : NSError containing the needed information
     */
    static func error(code: AuthErrorCode, userInfo: [String: Any]? = nil) -> Error {
        var errorUserInfo: [String: Any] = userInfo ?? [:]
        
        if errorUserInfo[NSLocalizedDescriptionKey] == nil {
            errorUserInfo[NSLocalizedDescriptionKey] = code.errorDescription
        }
        
        if let localizedDescription = errorUserInfo[NSLocalizedDescriptionKey] as? String,
           localizedDescription == "" {
            errorUserInfo[NSLocalizedDescriptionKey] = code.errorDescription
        }
        
        errorUserInfo[AuthErrors.userInfoNameKey] = code.errorCodeString
        
        return NSError(
            domain: AuthErrors.AuthErrorDomain, code: code.rawValue, userInfo: userInfo
        )
    }
    
    /**
        Method that returns an NSError containing the error domain, the error code and the error description.
        ## This serves as a helper that receives a string and converts it into a userInfo object.
        - Parameter code: AuthErrorCode
        - Parameter message: String?
        - Returns : NSError containing the needed information
     */
    static func error(code: AuthErrorCode, message: String?) -> Error {
        let userInfo: [String: Any]?
        if let message {
            userInfo = [NSLocalizedDescriptionKey: message]
        } else {
            userInfo = nil
        }
        
        return error(code: code, userInfo: userInfo)
    }
    
    // MARK: - All methods below are individual implementations of the error method for each AuthErrorCode
    
    static func wrongPasswordError(message: String?) -> Error {
        return error(code: .wrongPassword, message: message)
    }

    static func invalidEmailError(message: String?) -> Error {
        return error(code: .invalidEmail, message: message)
    }
    
    static func noSuchProviderError() -> Error {
        return error(code: .noSuchProvider, message: nil)
    }

    static func operationNotAllowed(message: String?) -> Error {
        return error(code: .operationNotAllowed, message: message)
    }

    static func networkError(message: String?) -> Error {
        return error(code: .networkError, message: message)
    }
    
    static func invalidCredential(message: String?) -> Error {
        return error(code: .invalidCredential, message: message)
    }
    
    static func emailAlreadyInUse(message: String?) -> Error {
        return error(code: .emailAlreadyInUse, message: message)
    }
    
    static func userTokenExpired() -> Error {
        return error(code: .userTokenExpired)
    }
    
    static func invalidAPIKey() -> Error {
        return error(code: .invalidAPIKey)
    }
    
    static func weakPasswordError(message: String?) -> Error {
        return error(code: .weakPassword, message: message)
    }
    
    static func missingEmail(message: String?) -> Error {
        return error(code: .missingEmail, message: message)
    }
    
    static func missingIosBundleID() -> Error {
        return error(code: .missingIosBundleID)
    }
    
    static func nullUser() -> Error {
        return error(code: .nullUser)
    }
    
    static func internalError(message: String?) -> Error {
        return error(code: .internalError, message: message)
    }
    
    static func malformedJWT(message: String?) -> Error {
        return error(code: .malformedJWT, message: message)
    }
    
    static func resourceNotFound(message: String?) -> Error {
        return error(code: .resourceNotFound, message: message)
    }
}
