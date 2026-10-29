#!/bin/bash
# Builds build/AppSwitcher.app. App Installer (~/main/dev/repos/app-installer) copies it into
# /Applications.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/AppSwitcher.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

swiftc -O -swift-version 5 \
    -o "$APP/Contents/MacOS/AppSwitcher" \
    Sources/*.swift \
    -framework AppKit -framework Carbon

cp Info.plist "$APP/Contents/Info.plist"
# Ad-hoc signatures change with every build, and macOS ties privacy grants to the
# signature. Pinning the requirement to the bundle ID keeps the Accessibility grant
# valid across rebuilds.
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" Info.plist)
codesign --force --sign - --requirements "=designated => identifier \"$BUNDLE_ID\"" "$APP"

echo "Built $APP"
