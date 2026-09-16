#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
# A certificate-backed identity preserves privacy grants across rebuilds.
# Override SIGNING_IDENTITY to choose a particular certificate or '-' for ad hoc.
BUILD_SIGNING_IDENTITY=${SIGNING_IDENTITY:-}
if [[ -z "$BUILD_SIGNING_IDENTITY" ]]; then
  BUILD_SIGNING_IDENTITY=$(security find-identity -v -p codesigning | sed -n '/"Apple Development:/s/.*) \([A-F0-9]*\) .*/\1/p' | head -1)
fi
BUILD_SIGNING_IDENTITY=${BUILD_SIGNING_IDENTITY:--}
xcodebuild -project MenuBarCompact.xcodeproj -scheme MenuBarCompact \
  -configuration Debug -derivedDataPath build/Xcode CODE_SIGN_IDENTITY="$BUILD_SIGNING_IDENTITY" build
ditto build/Xcode/Build/Products/Debug/MenuBarCompact.app build/MenuBarCompact.app
codesign --verify --strict build/MenuBarCompact.app
printf 'Built: %s/build/MenuBarCompact.app\n' "$PWD"
