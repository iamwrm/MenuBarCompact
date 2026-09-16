#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
/usr/bin/python3 -m unittest discover -s tests -v
TEST_BUILD_DIR=$(mktemp -d "${TMPDIR:-/tmp}/menubarcompact-tests.XXXXXX")
trap 'rm -rf "$TEST_BUILD_DIR"' EXIT
xcrun clang -fobjc-arc -Wall -Wextra -framework Foundation tests/visibility_policy.m -o "$TEST_BUILD_DIR/visibility-policy"
"$TEST_BUILD_DIR/visibility-policy"
xcrun clang -fobjc-arc -Wall -Wextra -Wno-unused-function -framework Cocoa -framework ApplicationServices tests/menu_activation.m -o "$TEST_BUILD_DIR/menu-activation"
"$TEST_BUILD_DIR/menu-activation"
xcrun swiftc SystemDiscovery.swift tests/runtime_discovery.swift -o "$TEST_BUILD_DIR/runtime-discovery"
"$TEST_BUILD_DIR/runtime-discovery"
