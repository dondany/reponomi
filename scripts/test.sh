#!/bin/bash
# Runs the unit tests. Extra arguments are passed on to `swift test`.
set -euo pipefail
cd "$(dirname "$0")/.."

# Fall back to the standalone Command Line Tools when Xcode can't run swift,
# e.g. because its license hasn't been accepted yet. SwiftPM doesn't find
# their copy of Swift Testing on its own, so point it there.
flags=()
if ! swift --version >/dev/null 2>&1 && [ -d /Library/Developer/CommandLineTools ]; then
  export DEVELOPER_DIR=/Library/Developer/CommandLineTools
  developer="$DEVELOPER_DIR/Library/Developer"
  flags=(
    -Xswiftc -F"$developer/Frameworks"
    -Xlinker -F"$developer/Frameworks"
    -Xlinker -rpath -Xlinker "$developer/Frameworks"
    -Xlinker -rpath -Xlinker "$developer/usr/lib"
  )
fi

swift test ${flags[@]+"${flags[@]}"} "$@"
