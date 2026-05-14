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
 Defines error codes and messages for authentication-related errors.
 */
public enum AuthErrorCode: Int, Error {
//    case invalidCustomToken = 17000
//    case customTokenMismatch = 17002
    /// The supplied auth credential is malformed or has expired.
    case invalidCredential = 17004
//    case userDisabled = 17005
    /// The given sign-in provider is disabled for this project.
    case operationNotAllowed = 17006
    /// The email address is already in use by another account.
    case emailAlreadyInUse = 17007
    /// The email address is badly formatted.
    case invalidEmail = 17008
    /// The password is invalid or the user does not have a password.
    case wrongPassword = 17009
//    case tooManyRequests = 17010
//    case userNotFound = 17011
//    case accountExistsWithDifferentCredential = 17012
//    case requiresRecentLogin = 17014
//    case providerAlreadyLinked = 17015
    case noSuchProvider = 17016
//    case invalidUserToken = 17017
    case networkError = 17020
    case userTokenExpired = 17021
    case invalidAPIKey = 17023
//    case userMismatch = 17024
//    case credentialAlreadyInUse = 17025
    case weakPassword = 17026
//    case appNotAuthorized = 17028
//    case expiredActionCode = 17029
//    case invalidActionCode = 17030
//    case invalidMessagePayload = 17031
//    case invalidSender = 17032
//    case invalidRecipientEmail = 17033
    case missingEmail = 17034
    case missingIosBundleID = 17036
//    case missingAndroidPackageName = 17037
//    case unauthorizedDomain = 17038
//    case invalidContinueURI = 17039
//    case missingContinueURI = 17040
//    case missingPhoneNumber = 17041
//    case invalidPhoneNumber = 17042
//    case missingVerificationCode = 17043
//    case invalidVerificationCode = 17044
//    case missingVerificationID = 17045
//    case invalidVerificationID = 17046
//    case missingAppCredential = 17047
//    case invalidAppCredential = 17048
//    case sessionExpired = 17051
//    case quotaExceeded = 17052
//    case missingAppToken = 17053
//    case notificationNotForwarded = 17054
//    case appNotVerified = 17055
//    case captchaCheckFailed = 17056
//    case webContextAlreadyPresented = 17057
//    case webContextCancelled = 17058
//    case appVerificationUserInteractionFailure = 17059
//    case invalidClientID = 17060
//    case webNetworkRequestFailed = 17061
//    case webInternalError = 17062
//    case webSignInUserInteractionFailure = 17063
//    case localPlayerNotAuthenticated = 17066
    case nullUser = 17067
//    case dynamicLinkNotActivated = 17068
//    case invalidProviderID = 17071
//    case tenantIDMismatch = 17072
//    case unsupportedTenantOperation = 17073
//    case invalidDynamicLinkDomain = 17074
//    case invalidHostingLinkDomain = 17214
//    case rejectedCredential = 17075
//    case gameKitNotLinked = 17076
//    case secondFactorRequired = 17078
//    case missingMultiFactorSession = 17081
//    case missingMultiFactorInfo = 17082
//    case invalidMultiFactorSession = 17083
//    case multiFactorInfoNotFound = 17084
//    case adminRestrictedOperation = 17085
//    case unverifiedEmail = 17086
//    case secondFactorAlreadyEnrolled = 17087
//    case maximumSecondFactorCountExceeded = 17088
//    case unsupportedFirstFactor = 17089
//    case emailChangeNeedsVerification = 17090
//    case missingClientIdentifier = 17093
//    case missingOrInvalidNonce = 17094
//    case blockingCloudFunctionError = 17105
//    case recaptchaNotEnabled = 17200
//    case missingRecaptchaToken = 17201
//    case invalidRecaptchaToken = 17202
//    case invalidRecaptchaAction = 17203
//    case missingClientType = 17204
//    case missingRecaptchaVersion = 17205
//    case invalidRecaptchaVersion = 17206
//    case invalidReqType = 17207
//    case recaptchaSDKNotLinked = 17208
//    case recaptchaSiteKeyMissing = 17209
//    case recaptchaActionCreationFailed = 17210
//    case keychainError = 17995
    case internalError = 17999
    case malformedJWT = 18000
    
    // ords specific codes
    case resourceNotFound = 19000
    
    var errorDescription: String {
        switch self {
        case .invalidEmail:
            return kErrorInvalidEmail
        case .invalidCredential:
            return kErrorInvalidCredential
        case .emailAlreadyInUse:
            return kErrorAlreadyInUse
        case .internalError:
            return kInternalError
        case .invalidAPIKey:
            return kErrorInvalidAPIKey
        case .malformedJWT:
            return kErrorMalformedJWT
        case .operationNotAllowed:
            return kErrorOperationNotAllowed
        case .wrongPassword:
            return kErrorWrongPWD
        case .noSuchProvider:
            return kErrorNoSuchProvider
        case .networkError:
            return kNetworkError
        case .userTokenExpired:
            return kErrorUserTokenExpired
        case .weakPassword:
            return kErrorWeakPWD
        case .missingEmail:
            return kErrorMissingEmail
        case .missingIosBundleID:
            return kErrorMissingIosBundleID
        case .nullUser:
            return kErrorNullUser
        case .resourceNotFound:
            return kResourceNotFound
        }
    }
    
    var errorCodeString: String {
        switch self {
        case .invalidCredential:
            return "ERROR_INVALID_CREDENTIAL "
        case .operationNotAllowed:
            return "ERROR_OPERATION_NOT_ALLOWED"
        case .emailAlreadyInUse:
            return "ERROR_EMAIL_ALREADY_IN_USE"
        case .invalidEmail:
            return "ERROR_INVALID_EMAIL"
        case .wrongPassword:
            return "ERROR_WRONG_PASSWORD"
        case .noSuchProvider:
            return "ERROR_NO_SUCH_PROVIDER"
        case .networkError:
            return "ERROR_NETWORK_REQUEST_FAILED"
        case .userTokenExpired:
            return "ERROR_USER_TOKEN_EXPIRED"
        case .invalidAPIKey:
            return "ERROR_INVALID_API_KEY"
        case .weakPassword:
            return "ERROR_WEAK_PASSWORD"
        case .missingEmail:
            return "ERROR_MISSING_EMAIL"
        case .missingIosBundleID:
            return "ERROR_MISSING_BUNDLE_ID"
        case .nullUser:
            return "ERROR_NULL_USER_PROVIDED"
        case .internalError:
            return "ERROR_INTERNAL_ERROR"
        case .malformedJWT:
            return "ERROR_MALFORMED_JWT"
        case .resourceNotFound:
            return "ERROR_RESOURCE_NOT_FOUND"
        }
    }
    
}


// MARK: -  at the moment, I'll define only necessary errors

private let kErrorInvalidEmail = "The email address is badly formatted."
private let kErrorInvalidCredential = "The supplied auth credential is malformed or expired."
private let kErrorAlreadyInUse = "The email address is already in use by another account."
private let kErrorWrongPWD = "The password is invalid or the user does not have a password."
private let kErrorNoSuchProvider = "User wasn't linked to an account with this provider."
private let kNetworkError = "A network error (could be either timeout, interrupted connection or unreacheable host) has occurred."
private let kErrorUserTokenExpired = "The user's credential is no longer valid."
private let kErrorInvalidAPIKey = "An invalid API key was supplied in the request."
private let kErrorOperationNotAllowed = "The given sign-in provider is disabled for this fusabase project. Enable it from the console."
private let kErrorWeakPWD = "The provided password wasn't secure enough for your authentication type."
private let kErrorMissingIosBundleID = "An iOS Bundle ID must be provided if an App Store ID is provided."
private let kErrorMissingEmail = "An email address must be provided."
private let kErrorWebRequestFailed = "A network error (could be either timeout, interrupted connection or unreacheable host) has occurred."
private let kErrorNullUser = "A null user was provided as the argument for an operation which requires a non-null user object."
private let kErrorMalformedJWT = "Failed to parse JWT token."
private let kInternalError = "An internal error happened. Please try again."
private let kResourceNotFound = "Couldn't find the resource you're requesting. This can happen because the project or app you're referencing does not exist. Please verify your credentials and try again."
