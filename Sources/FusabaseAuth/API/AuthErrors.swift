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
 A utility class providing constants for error domains and user info keys used in authentication errors.
 */
open class AuthErrors {
    /// The domain string for authentication-related errors.
    public static let AuthErrorDomain: String = "AuthErrorDomain"
    /// Key for the name in error user info dictionary.
    public static let userInfoNameKey: String = "AuthErrorUserInfoNameKey"
    /// Key for the email in error user info dictionary.
    public static let userInfoEmailKey: String = "AuthErrorUserInfoEmailKey"
    /// Key for the updated credential in error user info dictionary.
    public static let userInfoUpdatedCredentialKey: String = "AuthErrorUserInfoUpdatedCredentialKey"
    /// Key for the multi-factor resolver in error user info dictionary (not used yet).
    public static let userInfoMultiFactorResolverKey: String = "AuthErrorUserInfoMultiFactorResolverKey" // this won't be used yet
}
