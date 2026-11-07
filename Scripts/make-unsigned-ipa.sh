#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v xcodebuild >/dev/null || { echo 'Run on macOS with Xcode.' >&2; exit 1; }
xcodebuild -project GlassType.xcodeproj -scheme GlassType -configuration Release \
  -destination 'generic/platform=iOS' -archivePath build/GlassType.xcarchive \
  CODE_SIGNING_ALLOWED=NO archive
app='build/GlassType.xcarchive/Products/Applications/GlassType.app'
test -d "$app/PlugIns/GlassTypeKeyboard.appex"
for language in en ru uk; do
  resource="$app/PlugIns/GlassTypeKeyboard.appex/KeyboardCore_KeyboardCore.bundle/lexicon_${language}.txt"
  test -s "$resource" || { echo "Missing keyboard lexicon: $resource" >&2; exit 1; }
done
stage="$(mktemp -d "${TMPDIR:-/tmp}/glasstype-ipa.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
mkdir "$stage/Payload"
ditto "$app" "$stage/Payload/GlassType.app"
output="$PWD/build/GlassType-unsigned.ipa"
# ditto preserves bundle layout, resource forks and symlinks.
ditto -c -k --keepParent "$stage/Payload" "$output"
echo "Created unsigned IPA for re-signing: $output"
