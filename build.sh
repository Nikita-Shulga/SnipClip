#!/bin/zsh
# Builds SnipClip.app into ./build.  Pass "install" to also copy it to /Applications and launch it.
set -euo pipefail
cd "${0:A:h}"

APP=build/SnipClip.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -swift-version 5 -target "$(uname -m)-apple-macos13.0" \
    Sources/*.swift -o "$APP/Contents/MacOS/SnipClip"
cp Info.plist "$APP/Contents/Info.plist"

swift Tools/make_icon.swift build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

# Sign with the local "SnipClip Local Signing" certificate when it's in the keychain, so the
# Screen Recording permission survives rebuilds. Without it, fall back to an ad-hoc signature,
# which macOS ties to this exact build (the permission must then be granted again).
IDENTITY="SnipClip Local Signing"
if security find-identity -p codesigning | grep -q "\"$IDENTITY\""; then
    codesign --force --sign "$IDENTITY" "$APP"
else
    echo "Note: \"$IDENTITY\" certificate not found, signing ad-hoc"
    codesign --force --sign - "$APP"
fi
echo "Built $APP"

if [[ "${1:-}" == "install" ]]; then
    pkill -x SnipClip || true
    rm -rf /Applications/SnipClip.app
    cp -R "$APP" /Applications/
    open /Applications/SnipClip.app
    echo "Installed to /Applications and launched"
fi
