# API Reference

Use the generated DocC site when you need a fuller view of the public Swift SDK surface.

## Generate the Docs

From the SDK root:

```bash
./Scripts/generate-docs.sh
```

That script generates a static DocC site under:

```text
docs/
```

The generated site includes documentation for:

- `FusabaseCore`
- `FusabaseAuth`
- `FusabaseOracledb`
- `FusabaseStorage`

## Notes

- The Swift package already includes DocC bundles under each public module, such as `Sources/FusabaseCore/FusabaseCore.docc`.
- The docs script uses `swift package generate-documentation` and writes a static-hosting-friendly site into `docs/`.
- The generated `docs/index.html` redirects to the DocC entry point under `documentation/`.

## Useful Local Source Anchors

- `Package.swift`
- `Sources/FusabaseCore/API/`
- `Sources/FusabaseAuth/API/`
- `Sources/FusabaseOracledb/API/`
- `Sources/FusabaseStorage/API/`
- `Scripts/generate-docs.sh`
