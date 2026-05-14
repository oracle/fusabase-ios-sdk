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

/// Distance metric to use for vector similarity.
public enum VectorMetric: String {
    case cosine = "COSINE"
    case euclidean = "EUCLIDEAN"
    case dot = "DOT"
}

/// Sparse vector representation.
public struct SparseVector: Equatable {
    public let dimension: Int
    public let indices: [Int]
    public let values: [Double]

    public init(dimension: Int, indices: [Int], values: [Double]) throws {
        guard dimension > 0 else {
            throw OracledbErrorUtilities.invalidArgumentError(message: "Sparse vector dimension must be > 0")
        }
        guard indices.count == values.count else {
            throw OracledbErrorUtilities.invalidArgumentError(message: "Sparse vector indices and values must have the same length")
        }
        self.dimension = dimension
        self.indices = indices
        self.values = values
    }
}

/// Query input used for vector similarity search.
public enum VectorSearchQuery: Equatable {
    case dense([Double])
    case sparse(SparseVector)
}

/// Sentinel used in write operations to set/delete an embedding key.
public enum VectorSentinel: Equatable {
    case dense([Double])
    case sparse(SparseVector)
    case delete
}

/// Creates a dense vector sentinel.
public func denseVector(_ values: [Double]) throws -> VectorSentinel {
    try validateDenseVector(values, message: "denseVector values must be a numeric array.")
    return .dense(values)
}

/// Creates a sparse vector sentinel.
public func sparseVector(dimension: Int, indices: [Int], values: [Double]) throws -> VectorSentinel {
    let sparse = try SparseVector(dimension: dimension, indices: indices, values: values)
    try validateSparseVector(sparse)
    return .sparse(sparse)
}

/// Creates a sentinel indicating the embedding key should be removed.
public func deleteVector() -> VectorSentinel {
    return .delete
}

// MARK: - Internal encoding helpers

internal func validateDenseVector(_ values: [Double], message: String) throws {
    if values.contains(where: { $0.isNaN || !$0.isFinite }) {
        throw OracledbErrorUtilities.invalidArgumentError(message: message)
    }
}

internal func validateSparseVector(_ sparse: SparseVector) throws {
    guard sparse.dimension > 0 else {
        throw OracledbErrorUtilities.invalidArgumentError(message: "Sparse vector dimension must be > 0")
    }
    guard sparse.indices.count == sparse.values.count else {
        throw OracledbErrorUtilities.invalidArgumentError(message: "Sparse vector indices and values must have the same length")
    }
    // Indices are Ints; validate values are finite.
    if sparse.values.contains(where: { $0.isNaN || !$0.isFinite }) {
        throw OracledbErrorUtilities.invalidArgumentError(message: "Sparse vector values must be finite numbers")
    }
}

internal func encodeDenseVectorPayload(_ values: [Double]) -> [String: Any] {
    return ["type": "dense", "values": values]
}

internal func encodeSparseVectorPayload(_ sparse: SparseVector) -> [String: Any] {
    return [
        "type": "sparse",
        "dimension": sparse.dimension,
        "indices": sparse.indices,
        "values": sparse.values,
    ]
}

internal func encodeVectorSearchQuery(_ query: VectorSearchQuery) -> [String: Any] {
    switch query {
    case .dense(let values):
        return ["vector": values]
    case .sparse(let sparse):
        return ["sparse": encodeSparseVectorPayload(sparse)]
    }
}
