#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v xcodebuild >/dev/null || ! command -v swift >/dev/null; then
  echo 'Required: macOS, Xcode selected with xcode-select, Swift and iOS Simulator SDK.' >&2
  exit 1
fi
swift test -c release --package-path Core
xcodebuild -project GlassType.xcodeproj -scheme GlassType -configuration Debug \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO build
