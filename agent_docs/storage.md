# Storage Module

Use `FusabaseStorage` for storage clients, references, uploads, downloads, metadata access, listing, and task lifecycle APIs.

## Primary Types

- `Storage`
- `StorageReference`
- `StorageMetadata`
- `StorageListResult`
- `StorageUploadTask`
- `StorageDownloadTask`
- `StorageTaskSnapshot`
- `StorageTaskStatus`

## Common Patterns

### Get the storage client

```swift
import FusabaseStorage

let storage = Storage.storage()
```

Or bind storage to a specific app:

```swift
let storage = Storage.storage(app: app)
```

### Create references

```swift
let root = storage.reference()
let imageRef = storage.reference(withPath: "recipes/tea.png")
let childRef = root.child("recipes/tea.png")
```

### Upload data

```swift
let uploadTask = imageRef.putData(fileData)
```

### Upload from file

```swift
let uploadTask = imageRef.putFile(from: fileURL)
```

### Download URL and metadata

```swift
let url = try await imageRef.downloadURL()
let metadata = try await imageRef.getMetadata()
```

### Listing and delete

```swift
let page = try await imageRef.parent()?.listAll()
try await imageRef.delete()
```

### Upload task lifecycle

```swift
let task = imageRef.putData(fileData)

let progressHandle = task.observe(.progress) { snapshot in
    print("\(snapshot.bytesTransferred) / \(snapshot.totalBytes)")
}
task.observe(.success) { _ in print("done") }
task.observe(.failure) { snapshot in print(snapshot.status) }

task.pause()
task.resume()
task.cancel()

task.removeObserver(withHandle: progressHandle)
```

`observe(_:handler:)` accepts a `StorageTaskStatus` (`.progress`, `.success`, `.failure`, `.pause`, `.resume`) and returns a `String` handle for `removeObserver(withHandle:)` / `removeAllObservers()`.

## Notes

- The module supports async and completion-handler styles.
- `StorageReference` is the main handle for object paths.
- `Storage` exposes retry timing properties such as `maxOperationRetryTime`, `maxUploadRetryTime`, and `maxDownloadRetryTime`.

## Related Docs

- `agent_docs/core.md`
