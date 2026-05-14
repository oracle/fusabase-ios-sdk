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
 A protocol for authentication providers, requiring a provider ID.
 */
public protocol AuthProvider {
    /// The ID of the authentication provider.
    var providerID: String { get set }
}

/**
    Public enumeration of available auth provider IDs.
 */
public struct AuthProviderID: Equatable {
    /// Variable representing the Auth Provider ID
    public let rawValue:String
    
    /// Private initialization method
    /// - Parameter rawValue: String containing the provider ID
    private init(rawValue: String) {
        self.rawValue = rawValue
    }
}

/**
    Extension used for the AuthProviderID
 */
public extension AuthProviderID {
    
    /// ID representing email & password
    static var email: Self {
        Self(rawValue: "epw")
    }
    
    /// ID representing the facebook provider
    static var facebook: Self {
        Self(rawValue: "facebook")
    }
    
    /// ID representing the Google provider
    static var google: Self {
        Self(rawValue: "google")
    }
    
    /// ID representing the Phone provider
    /// PHONE IS NOT SUPPORTED
    static var github: Self {
        Self(rawValue: "github")
    }
    
    /// Convenience method for adding a custom AuthProvider
    static func custom(_ value: String) -> Self {
        Self(rawValue: value)
    }
}
