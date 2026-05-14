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


class OnPremConfigHelper {
    
    var AUTHENTICATE_REST_EP = "authenticate"
    var SELF_REGISTER_EP = "useradd"
    var UPDATE_PASSWORD_HELPER = "changePassword"
    var UPDATE_PROFILE_HELPER = "updateProfile"
    var REVOKE_REFRESH_TOKEN = "rf/revoke"
    var SEND_EMAIL_VERIFICATION = "sendemail"
    var SEND_PASSWORD_RESET_EMAIL = "sendemail"
    var CONFIRM_PASSWORD_RESET = "resetpwd"
    var VERIFY_PASSWORD_RESET_CODE = "verifycode"
    var SIGN_IN_WITH_CREDENTIAL = "getcredential"
    var SOCIAL_UNLINK = "socialunlink"
    var REDIRECT_RESULT_EP = "redirectResult"

    // constants for social login
    var CODE_VERIFIER = "CODE_VERIFIER"

    
    var domainURL: String
    var _appID: String

    
    init(_domainURL: String, _appID: String) {
        self.domainURL = _domainURL
        self._appID = _appID
        
        // we add the app id to all constants
        AUTHENTICATE_REST_EP += "?apiKey=" + _appID
        SEND_PASSWORD_RESET_EMAIL += "?apiKey=" + _appID
        CONFIRM_PASSWORD_RESET += "?apiKey=" + _appID
        VERIFY_PASSWORD_RESET_CODE += "?apiKey=" + _appID
        UPDATE_PASSWORD_HELPER += "?apiKey=" + _appID
        SEND_EMAIL_VERIFICATION += "?apiKey=" + _appID
        SELF_REGISTER_EP += "?apiKey=" + _appID
        UPDATE_PROFILE_HELPER += "?apiKey=" + _appID
        REVOKE_REFRESH_TOKEN += "?apiKey=" + _appID

        SIGN_IN_WITH_CREDENTIAL += "?apiKey=" + _appID
        SOCIAL_UNLINK += "?apiKey=" + _appID
        REDIRECT_RESULT_EP += "?apiKey=" + _appID
        
        
    }
    
    // MARK: convenience methods to get URL's
    
    /**
        Method that retrieves the sign in with redirect URL string
     */
    func getSignInWithRedirectURL(providerID: String, challenge: String, link: Bool = false) -> String {
        return self.domainURL + "socialidp?method=\(providerID)&device=mobile&apiKey=\(_appID)&code_challenge=\(challenge)&code_challenge_method=S256&link=\(link ? 1 : 0)"
    }

    /**
        Method that retrieves the sign-in with credential URL String
     */
    
    
    
}
