# OracleDB Module

Use `FusabaseOracledb` for document-style data access, queries, listeners, transactions, write batches, aggregates, vector search, and duality-view operations.

## Primary Types

- `FusabaseOracledb`
- `CollectionReference`
- `DocumentReference`
- `Query`
- `QuerySnapshot`
- `DocumentSnapshot`
- `WriteBatch`
- `Transaction`
- `FieldValue`
- `FieldPath`
- `Filter`
- `SetOptions`
- `SnapshotListenOptions`
- `ListenerRegistration`
- `AggregateQuery`
- `AggregateQuerySnapshot`
- `VectorMetric`
- `SparseVector`
- `VectorSearchQuery`
- `VectorSentinel`
- `DualityViewColReference`
- `DualityViewDocReference`

## Common Patterns

### Get the database instance

```swift
import FusabaseOracledb

let db = FusabaseOracledb.oracledb()
```

Or bind to a specific app:

```swift
let db = FusabaseOracledb.oracledb(app: app)
```

### Collections and documents

```swift
let recipes = db.collection("recipes")
let recipe = recipes.document("tea")
let detail = try await recipe.getDocument()
```

### Add and update documents

```swift
let created = try await recipes.addDocument(data: [
    "title": "Tea",
    "category": "Drinks"
])

try await created.updateData([
    "category": "Hot Drinks"
])
```

### Set with merge

```swift
try await recipe.setData(["title": "Tea"], merge: true)

try await recipe.setData(
    ["title": "Tea", "category": "Hot Drinks"],
    mergeFields: ["category"]
)
```

Use `merge: true` to merge every supplied field. Use `mergeFields:` to merge only the listed paths.

### Queries

```swift
let drinks = recipes
    .whereField("category", isEqualTo: "Drinks")
    .whereField("rating", isGreaterThan: 4.0)
    .whereField("tags", arrayContains: "vegan")
    .whereField("title", like: "Iced%")
    .order(by: "title")

let results = try await drinks.getDocuments(source: .default)
print(results.documents.count)
```

Available operators: `isEqualTo`, `isNotEqualTo`, `isGreaterThan`, `isGreaterOrEqualTo`, `isLessThan`, `isLessThanOrEqualTo`, `in:`, `notIn:`, `arrayContains:`, `arrayContainsAny:`, `like:`, `isNull:`. Each has a `FieldPath` overload as well as a `String` overload.

### Vector search

```swift
// Write a dense embedding via a sentinel.
let sentinel = try denseVector([0.12, -0.91, 0.44])
try await recipe.setData(["EMB": sentinel], merge: true)

// Query nearest neighbours.
let nearest = try recipes.findNearest(
    "EMB",
    .dense([0.22, 0.93, -0.1]),
    metric: .cosine,
    topK: 10
)
let results = try await nearest.getDocuments()

// Sparse alternative.
let sparse = try SparseVector(dimension: 1000, indices: [3, 40, 777], values: [0.5, 0.8, 0.33])
let sparseQuery = try recipes.findNearest("EMB", .sparse(sparse), metric: .dot, topK: 5)

// Delete an embedding key.
try await recipe.setData(["EMB": deleteVector()], merge: true)
```

`Query.vectorSearch(_:_:metric:topK:threshold:)` is a backward-compatible alias for `findNearest`.

### Snapshot listeners

```swift
let registration: ListenerRegistration = recipe.addSnapshotListener(includeMetadataChanges: false) { snapshot, error in
    print(snapshot?.data() ?? [:])
}

// Detach when finished.
registration.remove()
```

Pass `SnapshotListenOptions` (or use the convenience overloads) to control metadata changes and dispatch executor.

### Transactions and batches

```swift
db.runTransaction({ transaction, errorPointer in
    let _ = try? transaction.getDocument(recipe)
    transaction.updateData(["views": 1], forDocument: recipe)
    return nil
}, completion: { _, error in
    print(error as Any)
})

let batch = db.batch()
batch.updateData(["published": true], forDocument: recipe)
try await batch.commit()
```

## Other Public Areas

- `collectionGroup(_:)`
- `join(viewName:)`
- `dualityViewCollection(collectionPath:)`
- `bulkUpdate(_:)`
- aggregate and vector-search APIs on `Query`

## Notes

- The query API is immutable. Chaining methods returns a new `Query`.
- Both async and callback-based APIs exist across the module.

## Related Docs

- `agent_docs/storage.md`
