#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
xcodebuild -project MenuBarCompact.xcodeproj -scheme MenuBarCompact \
  -configuration Debug -derivedDataPath build/Xcode build
ditto build/Xcode/Build/Products/Debug/MenuBarCompact.app build/MenuBarCompact.app
codesign --verify --strict build/MenuBarCompact.app
printf 'Built: %s/build/MenuBarCompact.app\n' "$PWD"
