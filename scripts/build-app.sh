#!/bin/bash
# Builds build/Reponomi.app. With --install, also copies it to /Applications
# and (re)launches it.
set -euo pipefail
cd "$(dirname "$0")/.."

# Fall back to the standalone Command Line Tools when Xcode can't run swift,
# e.g. because its license hasn't been accepted yet.
if ! swift --version >/dev/null 2>&1 && [ -d /Library/Developer/CommandLineTools ]; then
  export DEVELOPER_DIR=/Library/Developer/CommandLineTools
fi

swift build -c release
bin="$(swift build -c release --show-bin-path)/Reponomi"

app=build/Reponomi.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$bin" "$app/Contents/MacOS/Reponomi"
cp Support/Info.plist "$app/Contents/Info.plist"
# The hardened runtime stops other processes from loading code into the app
# (and so from using its keychain item or its permission to control iTerm).
codesign --force --sign - --options runtime --entitlements Support/Reponomi.entitlements "$app"
echo "Built $app"

if [ "${1:-}" = "--install" ]; then
  pkill -x Reponomi || true
  rm -rf /Applications/Reponomi.app
  ditto "$app" /Applications/Reponomi.app
  open /Applications/Reponomi.app
  echo "Installed and launched /Applications/Reponomi.app"
fi
