#!/usr/bin/env bash
# Runs the test suite. With full Xcode installed, plain `swift test` works too;
# with only the Command Line Tools, Swift Testing has to be located explicitly.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ "$(xcode-select -p)" == *CommandLineTools* ]]; then
  FW=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
  LIB=/Library/Developer/CommandLineTools/Library/Developer/usr/lib
  exec swift test \
    -Xswiftc -F -Xswiftc "$FW" \
    -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays \
    -Xlinker -F -Xlinker "$FW" \
    -Xlinker -rpath -Xlinker "$FW" \
    -Xlinker -rpath -Xlinker "$LIB" \
    "$@"
fi
exec swift test "$@"
