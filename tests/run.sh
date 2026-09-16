#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
/usr/bin/python3 -m unittest discover -s tests -v
TEST_BUILD_DIR=$(mktemp -d "${TMPDIR:-/tmp}/menubarcompact-tests.XXXXXX")
trap 'rm -rf "$TEST_BUILD_DIR"' EXIT
xcrun clang -O2 -fobjc-arc -Wall -Wextra -c RestrictionBridge.m -o "$TEST_BUILD_DIR/RestrictionBridge.o"
# Compile the production Swift sources, excluding only the NSApplication entry point.
SOURCES=()
for source in *.swift; do [[ "$source" == main.swift ]] || SOURCES+=("$source"); done
xcrun swiftc -O -whole-module-optimization -warnings-as-errors -import-objc-header RestrictionBridge.h \
  "${SOURCES[@]}" tests/RegressionTests.swift "$TEST_BUILD_DIR/RestrictionBridge.o" \
  -o "$TEST_BUILD_DIR/regressions"
"$TEST_BUILD_DIR/regressions"
