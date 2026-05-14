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
// Licensed under the Apache License, Version 2.0 (the \"License\");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an \"AS IS\" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
//-----------------------------------------------------------------------------

import Foundation

@available(iOS 15, tvOS 13, macOS 10.15, watchOS 7, *)
public extension OracledbErrorCode {
    
    var errorDescription: String {
        switch self {
        case .unknown:
            return kOrdbErrorUnknown
        case .invalidArgument:
            return kOrdbErrorInvalidArgument
        case .invalidPath:
            return kOrdbErrorInvalidPath
        case .invalidRefType:
            return kOrdbErrorInvalidRefType
        case .invalidURL:
            return kOrdbErrorInvalidURL
        case .jsonSerializationFailed:
            return kOrdbErrorJsonSerializationFailed
        case .unauthenticated:
            return kOrdbErrorUnauthenticated
        case .unauthorized:
            return kOrdbErrorUnauthorized
        case .networkError:
            return kOrdbErrorNetwork
        case .invalidResponse:
            return kOrdbErrorInvalidResponse
        case .invalidJSON:
            return kOrdbErrorInvalidJSON
        case .notFound:
            return kOrdbErrorNotFound
        case .internalError:
            return kOrdbErrorInternal
        case .preconditionFailed:
            return kOrdbErrorPreconditionFailed
        case .emptyAccessToken:
            return kOrdbErrorEmptyAccessToken
        }
    }
    
    var errorCodeString: String {
        switch self {
        case .unknown:
            return "ERROR_ORACLEDB_UNKNOWN"
        case .invalidArgument:
            return "ERROR_ORACLEDB_INVALID_ARGUMENT"
        case .invalidPath:
            return "ERROR_ORACLEDB_INVALID_PATH"
        case .invalidRefType:
            return "ERROR_ORACLEDB_INVALID_REF_TYPE"
        case .invalidURL:
            return "ERROR_ORACLEDB_INVALID_URL"
        case .jsonSerializationFailed:
            return "ERROR_ORACLEDB_JSON_SERIALIZATION_FAILED"
        case .unauthenticated:
            return "ERROR_ORACLEDB_UNAUTHENTICATED"
        case .unauthorized:
            return "ERROR_ORACLEDB_UNAUTHORIZED"
        case .networkError:
            return "ERROR_ORACLEDB_NETWORK_ERROR"
        case .invalidResponse:
            return "ERROR_ORACLEDB_INVALID_RESPONSE"
        case .invalidJSON:
            return "ERROR_ORACLEDB_INVALID_JSON"
        case .notFound:
            return "ERROR_ORACLEDB_NOT_FOUND"
        case .internalError:
            return "ERROR_ORACLEDB_INTERNAL_ERROR"
        case .preconditionFailed:
            return "ERROR_ORACLEDB_PRECONDITION_FAILED"
        case .emptyAccessToken:
            return "ERROR_ORACLEDB_EMPTY_ACCESS_TOKEN"
        }
    }
}

// MARK: - Strings

private let kOrdbErrorUnknown = "An unknown database error occurred."
private let kOrdbErrorInvalidArgument = "The argument passed to the function is invalid."
private let kOrdbErrorInvalidPath = "Invalid path specified for the database reference."
private let kOrdbErrorInvalidRefType = "The provided reference type is not supported."
private let kOrdbErrorInvalidURL = "Invalid URL constructed for the request."
private let kOrdbErrorJsonSerializationFailed = "Failed to serialize JSON payload for the request."
private let kOrdbErrorUnauthenticated = "User is not authenticated. Please authenticate and try again."
private let kOrdbErrorUnauthorized = "User does not have permission to access the desired resource."
private let kOrdbErrorNetwork = "A network error occurred during the request."
private let kOrdbErrorInvalidResponse = "Received an invalid response from the server."
private let kOrdbErrorInvalidJSON = "The server response is not valid JSON."
private let kOrdbErrorNotFound = "The requested resource was not found."
private let kOrdbErrorInternal = "An internal error occurred. Please try again."
private let kOrdbErrorPreconditionFailed = "A precondition for this operation failed."
private let kOrdbErrorEmptyAccessToken = "The access token is empty."
