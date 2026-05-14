# Core Module

Use `FusabaseCore` for app configuration, app lookup, and shared types used across the Swift SDK.

## Primary Types

- `FusabaseApp`
- `FusabaseOptions`
- `Timestamp`
- `TokenStore`
- `PersistenceUtils`

## Common Pattern

```swift
import FusabaseCore

let options = FusabaseOptions(jsonName: "fusabase-config")
FusabaseApp.configure(options: options)

guard let app = FusabaseApp.app() else {
    fatalError("FusabaseApp is not configured.")
}
```

## Named Apps

```swift
import FusabaseCore

let options = FusabaseOptions(jsonName: "fusabase-config")
FusabaseApp.configure(name: "reporting", options: options)
let reportingApp = FusabaseApp.app(name: "reporting")
```

## Notes

- `FusabaseApp` is the shared entrypoint for other modules.
- Other modules commonly bind to the default configured app unless you pass an app explicitly.

## Related Docs

- `agent_docs/configuration.md`
- `agent_docs/auth.md`
- `agent_docs/oracledb.md`
- `agent_docs/storage.md`
