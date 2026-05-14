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
import ObjectiveC

/**
 A helper object that encapsulates the result of a successful authentication operation, including the user, credential, and additional information.
 */
@available(iOS 15, tvOS 13, macOS 10.15, watchOS 7, *)
public class AuthDataResult: NSObject {
    /// The authenticated user.
    public let user: FusabaseUser
    /// The credential used for authentication, if applicable.
    public let credential: AuthCredential?
    /// Additional information about the user.
    public let additionalUserInfo: AdditionalUserInfo?
    
    /// Initializes an `AuthDataResult` with the authenticated user and optional credential.
    ///
    /// - Parameters:
    ///   - user: The authenticated user.
    ///   - credential: The credential used for authentication, if applicable.
    ///   - isNewUser: Whether this is a newly created user.
    init(user: FusabaseUser, credential: AuthCredential? = nil, isNewUser: Bool = false) {
        self.user = user
        self.credential = credential

        // we form additionalUserInfo from the user object provided
        additionalUserInfo = AdditionalUserInfo(providerID: user.providerID, profile: ["user": user], username: user.email, isNewUser: isNewUser)

        super.init()
    }
}
