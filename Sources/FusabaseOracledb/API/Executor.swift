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

/// Protocol for executing tasks asynchronously.
/// Executors provide a way to run blocks of code on different threads or queues.
protocol Executor {
    /// Executes the given block of code.
    ///
    /// - Parameter block: The block of code to execute.
    func execute(_ block: @escaping () -> Void)
}

/// Default executor that runs tasks on the main dispatch queue.
class MainThreadExecutor: Executor {
    func execute(_ block: @escaping () -> Void) {
        DispatchQueue.main.async(execute: block)
    }
}

/// Executes callbacks on a caller-supplied dispatch queue.
final class DispatchQueueExecutor: Executor {
    private let queue: DispatchQueue

    init(_ queue: DispatchQueue) {
        self.queue = queue
    }

    func execute(_ block: @escaping () -> Void) {
        queue.async(execute: block)
    }
}

/// Executor that runs tasks on a background dispatch queue.
class BackgroundExecutor: Executor {
    private let queue: DispatchQueue

    init(queue: DispatchQueue = DispatchQueue.global(qos: .default)) {
        self.queue = queue
    }

    func execute(_ block: @escaping () -> Void) {
        queue.async(execute: block)
    }
}

/// Executor that runs tasks synchronously on the current thread.
class SynchronousExecutor: Executor {
    func execute(_ block: @escaping () -> Void) {
        block()
    }
}
