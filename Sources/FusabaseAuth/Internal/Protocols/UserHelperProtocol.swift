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


/**
  # protocol UserHelperProtocol
     This internal protocol allows to define a variable in the Auth class that could contain either OnPremUserHelper or IDCSUserHelper.
     Additionally, it provides default implementations for functions that are exclusive to certain classes.
 */
@available(iOS 15, tvOS 13, macOS 10.15, watchOS 7, *)
protocol UserHelperProtocol {
    // helper to format profile operations
    func _getOperations(_ currentUser: FusabaseUser, newUserProfile: UserProfile) -> [[String: Any]]
    // helper to refresh a user's access token if possible
    func refreshAccessToken(refreshToken: String) async throws -> BearerTokenResponse
    // helper to update a user's password
    func updatePasswordHelper(_ user: FusabaseUser, oldPassword: String, newPassword: String) async throws
    // helper to update a user's profile
    func updateProfileHelper(_ user: FusabaseUser, newUserProfile: UserProfile) async throws
    // helper to send an email verification
    func sendEmailVerificationHelper(_ user: FusabaseUser, withEmail: String, uid: Any) async throws
    // link with auth credential helper
    func linkWithCredential(_ user: FusabaseUser, credential: AuthCredential) async throws
    // link with auth provider helper
    func linkWithCredential(_ user: FusabaseUser, provider: AuthProvider) async throws
}

