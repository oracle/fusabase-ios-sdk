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


/// Describes error conditions that can occur when using Fusabase Storage APIs.
///
/// These values are surfaced in thrown errors (and can be bridged to NSError with
/// `StorageErrors.StorageErrorDomain`). Use `errorDescription` for a human‑readable
/// message and `errorCodeString` for a stable string identifier suitable for logging
/// and analytics.
@available(iOS 15, tvOS 13, macOS 10.15, watchOS 7, *)
/**
 Error codes for storage operations.
 */
public enum StorageErrorCode : Int, Swift.Error {
    
    case unknown = -13000
    case objectNotFound = -13010
    case bucketNotFound = -13011
    case projectNotFound = -13012
    case quotaExceeded = -13013
    
    case unauthenticated = -13020
    case unauthorized = -13021
    
    case retryLimitExceeded = -13030
    case nonMatchingChecksum = -13031
    case downloadSizeExceeded = -13032
    
    case cancelled = -13040
    
    case invalidArgument = -13050
    case bucketMismatch = -13051
    case internalError = -13052
    case pathError = -13053
}
