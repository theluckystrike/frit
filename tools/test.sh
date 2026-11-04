#!/bin/bash
# Run the GlazeCore tests with the Command Line Tools toolchain (no Xcode).
# CLT ships Testing.framework outside the default search path, so the flags are passed here
# (not in Package.swift: with manifest-only flags SwiftPM builds the tests but silently runs none).
set -euo pipefail
cd "$(dirname "$0")/.."
F=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
L=/Library/Developer/CommandLineTools/Library/Developer/usr/lib
exec timeout "${GLAZE_TEST_TIMEOUT:-900}" "$HOME/bin/buildslot" swift test \
  -Xswiftc -F -Xswiftc "$F" \
  -Xlinker -rpath -Xlinker "$F" -Xlinker -rpath -Xlinker "$L" "$@"
