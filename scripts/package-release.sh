#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
RELEASE_VERSION=${1:?Usage: scripts/package-release.sh VERSION}
if [[ ! "$RELEASE_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo 'Expected a version such as 0.6.2.' >&2
  exit 1
fi
SDK_VERSION=$(xcrun --sdk macosx --show-sdk-version)
if (( ${SDK_VERSION%%.*} < 27 )); then
  echo 'A macOS 27 or newer SDK is required.' >&2
  exit 1
fi
xcodebuild -project MenuBarCompact.xcodeproj -scheme MenuBarCompact \
  -configuration Release -derivedDataPath build/ReleaseDerivedData \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= DEVELOPMENT_TEAM= build
RELEASE_APP=build/ReleaseDerivedData/Build/Products/Release/MenuBarCompact.app
APP_VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$RELEASE_APP/Contents/Info.plist")
if [[ "$APP_VERSION" != "$RELEASE_VERSION" ]]; then
  echo "Release version $RELEASE_VERSION does not match app version $APP_VERSION." >&2
  exit 1
fi
test -x "$RELEASE_APP/Contents/MacOS/MenuBarCompact"
test -f "$RELEASE_APP/Contents/Resources/istat_workaround.py"
xcrun lipo -verify_arch arm64 "$RELEASE_APP/Contents/MacOS/MenuBarCompact"
# The arm64 linker may embed its mandatory ad-hoc code seal. No certificate,
# provisioning profile, Developer ID signing, or notarization is used here.
SIGNATURE_INFO=$(codesign -dvv "$RELEASE_APP" 2>&1 || true)
if [[ "$SIGNATURE_INFO" == *Authority=* ]]; then
  echo 'Unexpected certificate signature in the unsigned release build.' >&2
  exit 1
fi
mkdir -p dist
RELEASE_ARCHIVE="MenuBarCompact-${RELEASE_VERSION}-macOS-arm64.zip"
ditto -c -k --sequesterRsrc --keepParent "$RELEASE_APP" "dist/$RELEASE_ARCHIVE"
(cd dist && shasum -a 256 "$RELEASE_ARCHIVE" > "$RELEASE_ARCHIVE.sha256")
printf 'Packaged: dist/%s\n' "$RELEASE_ARCHIVE"
