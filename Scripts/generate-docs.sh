
#!/usr/bin/env bash
set -euo pipefail

# Generate DocC documentation as a static site (no 3rd-party tools).
# Output: ./docs

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="$ROOT_DIR/docs"
DOC_TITLE='Oracle® Backend for Firebase Swift SDK Reference, Release 26.1.0'

cd "$ROOT_DIR"

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

swift package \
  --allow-writing-to-directory "$OUTPUT_DIR" \
  generate-documentation \
  --output-path "$OUTPUT_DIR" \
  --transform-for-static-hosting \
  --experimental-enable-custom-templates \
  --fallback-display-name "$DOC_TITLE" \
  --enable-experimental-combined-documentation \
  --target FusabaseCore \
  --target FusabaseAuth \
  --target FusabaseOracledb \
  --target FusabaseStorage \


echo "✅ DocC site generated at: $OUTPUT_DIR"

# When hosting the generated site from the `docs/` directory (e.g. `python -m http.server`),
# make the root path (`/`) redirect to DocC's default entry point at `/documentation/`.
cat > "$OUTPUT_DIR/index.html" <<'HTML'
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta http-equiv="refresh" content="0; url=documentation/">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Redirecting…</title>
    <link rel="canonical" href="documentation/">
  </head>
  <body>
    <p>Redirecting to <a href="documentation/">documentation/</a>…</p>
  </body>
</html>
HTML

# Rewrite titles in module/combined entry points (where present).
for f in \
  "$OUTPUT_DIR/documentation/fusabasecore/index.html" \
  "$OUTPUT_DIR/documentation/fusabaseauth/index.html" \
  "$OUTPUT_DIR/documentation/fusabaseoracledb/index.html" \
  "$OUTPUT_DIR/documentation/fusabasestorage/index.html" \
  "$OUTPUT_DIR/documentation/index.html"; do
  if [[ -f "$f" ]]; then
    sed -i '' "s|<title>Documentation</title>|<title>${DOC_TITLE}</title>|" "$f" || true
  fi
done

if command -v open >/dev/null 2>&1; then
  echo "Tip: open docs/index.html"
fi
