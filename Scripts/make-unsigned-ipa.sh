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
python3 - "$app" <<'PY'
import json
from pathlib import Path
import plistlib
import subprocess
import sys

app = Path(sys.argv[1])
info = plistlib.loads((app / 'Info.plist').read_bytes())
primary = info.get('CFBundleIcons', {}).get('CFBundlePrimaryIcon', {})
assert primary.get('CFBundleIconName') == 'AppIcon', 'Compiled primary app icon missing'
assert primary.get('CFBundleIconFiles'), 'Legacy app icon fallbacks missing'
catalog = app / 'Assets.car'
assert catalog.is_file() and catalog.stat().st_size > 0, 'Compiled app icon catalog missing'
assets = json.loads(subprocess.check_output(['/usr/bin/assetutil', '--info', str(catalog)], text=True))
assert 'dark' in json.dumps(assets).lower(), 'Compiled dark appearance missing'
print('Verified primary AppIcon, fallback files and dark appearance in Assets.car')
PY
stage="$(mktemp -d "${TMPDIR:-/tmp}/glasstype-ipa.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
mkdir "$stage/Payload"
ditto "$app" "$stage/Payload/GlassType.app"
output="$PWD/build/GlassType-unsigned.ipa"
# ditto preserves bundle layout, resource forks and symlinks.
ditto -c -k --keepParent "$stage/Payload" "$output"
echo "Created unsigned IPA for re-signing: $output"
