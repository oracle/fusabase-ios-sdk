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


import Security
import Foundation

@available(iOS 15, tvOS 13, macOS 10.15, watchOS 7, *)
package class PersistenceUtils {
    
    public static let logger = FusabaseLogger(category: "core.persistence")
    
    // Keychain configuration
    private static let keychainService: String = {
        // Prefer the host app's bundle identifier to scope Keychain items
        return Bundle.main.bundleIdentifier ?? "com.oracle.database.fusabase"
    }()
    // Accessibility attribute only applies on iOS/tvOS/watchOS
    #if os(iOS) || os(tvOS) || os(watchOS)
    private static let keychainAccessible: CFString? = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    #else
    private static let keychainAccessible: CFString? = nil
    #endif

    /**
        Save a string value for a key.
        Stored in Keychain, preserving the same interface.
     */
    public static func saveItem(_ value: String, forKey key: String) {
        do {
            let _ = try saveInKeyChain(key: key, value)
            logger.debug("Saved item in Keychain for key: \(key)")
        } catch {
            logger.error("Keychain save failed for key: \(key). Error: \(error)")
        }
    }
    
    /**
        Load a string value for a key.
        Behavior preserved: returns empty string when not found.
     */
    public static func loadItem(forKey key: String) -> String {
        do {
            if let value = try readFromKeyChain(key: key) {
                return value
            }
        } catch {
            logger.error("Keychain read failed for key: \(key). Error: \(error)")
        }
        return ""
    }
    
    /**
        Delete a value for a key.
        Deletes from Keychain.
     */
    public static func deleteItem(forKey key: String) {
        deleteFromKeyChain(forKey: key)
        logger.debug("Deleted item for key: \(key) from Keychain")
    }
    
    // MARK: - Keychain methods
    
    class func saveInKeyChain(key: String, _ value: String) throws -> Bool {
        guard let data = value.data(using: .utf8) else {
            throw NSError(domain: "KeyChain utilities", code: 90000, userInfo: ["Error": "Couldn't create data object."])
        }
        
        var baseQuery: [String: Any] = [
            kSecClass as String             : kSecClassGenericPassword,
            kSecAttrAccount as String       : key,
            kSecAttrService as String       : keychainService
        ]
        if let accessible = keychainAccessible {
            baseQuery[kSecAttrAccessible as String] = accessible
        }

        // Delete existing item (if any), then add fresh value
        SecItemDelete(baseQuery as CFDictionary)
        
        var addQuery = baseQuery
        addQuery[kSecValueData as String] = data
        
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status != errSecSuccess {
            throw NSError(
                domain: "KeyChain utilities",
                code: Int(status),
                userInfo: ["Error": "Couldn't save information into the keychain. \(status)"]
            )
        }
        return true
    }
    
    // Returns nil when not found, throws on other errors
    class func readFromKeyChain(key: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String             : kSecClassGenericPassword,
            kSecAttrAccount as String       : key,
            kSecAttrService as String       : keychainService,
            kSecReturnData as String        : true,
            kSecMatchLimit as String        : kSecMatchLimitOne
        ]

        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)

        switch status {
        case errSecSuccess:
            if let data = dataTypeRef as? Data {
                return String(data: data, encoding: .utf8)
            }
            return nil
        case errSecItemNotFound:
            return nil
        default:
            throw NSError(
                domain: "KeyChain utilities",
                code: Int(status),
                userInfo: ["Error": "Couldn't read information from the keychain. \(status)"]
            )
        }
    }
    
    class func deleteFromKeyChain(forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String          : kSecClassGenericPassword,
            kSecAttrAccount as String    : key,
            kSecAttrService as String    : keychainService
        ]
        SecItemDelete(query as CFDictionary)
    }
}
