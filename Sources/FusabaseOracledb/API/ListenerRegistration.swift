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

/// Represents a registration for a listener that can be used to remove the listener.
/// Listener registrations provide a way to stop listening to database changes.
public protocol ListenerRegistration {
    /// Removes the listener that this registration represents.
    /// After calling this method, the listener will no longer receive events.
    func remove()
}

/// Default implementation of ListenerRegistration that takes a remove action.
class ListenerRegistrationImpl: ListenerRegistration {
    private let removeAction: () -> Void

    /// Creates a new listener registration with the specified remove action.
    ///
    /// - Parameter removeAction: The action to execute when the listener is removed.
    init(removeAction: @escaping () -> Void) {
        self.removeAction = removeAction
    }

    public func remove() {
        removeAction()
    }
}
