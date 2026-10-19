#!/bin/sh
# Builds build/OpenMessages.app from the Swift package.
# Usage: scripts/build-app.sh [path/to/GoogleService-Info.plist]
set -eu
cd "$(dirname "$0")/.."

PLIST="${1:-GoogleService-Info.plist}"
APP="build/OpenMessages.app"

swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/OpenMessagesMac"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/OpenMessagesMac"
cp Support/Info.plist "$APP/Contents/Info.plist"
if [ -f "$PLIST" ]; then
    cp "$PLIST" "$APP/Contents/Resources/GoogleService-Info.plist"
else
    echo "note: $PLIST not found; the app will look in ~/Library/Application Support/OpenMessages/ instead" >&2
fi

# Ad-hoc signature so it runs locally. Use a Developer ID and notarize before distributing.
codesign --force --sign - --options runtime "$APP"
echo "Built $APP"
