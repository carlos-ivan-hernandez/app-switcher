#!/bin/bash
# Builds AppSwitcher.app and installs it to /Applications, replacing any older copy.
# A copy that was running is quit and reopened. Pass --run to open it even if it wasn't running.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/AppSwitcher.app"
INSTALLED="/Applications/AppSwitcher.app"
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

# Quit the running copy before replacing it, so the old version doesn't keep running.
WAS_RUNNING=false
if pgrep -x AppSwitcher >/dev/null; then
    WAS_RUNNING=true
    pkill -x AppSwitcher || true
    while pgrep -x AppSwitcher >/dev/null; do sleep 0.1; done
fi

rm -rf "$INSTALLED"
ditto "$APP" "$INSTALLED"
echo "Installed $INSTALLED"

if [[ "$WAS_RUNNING" == true || "${1:-}" == "--run" ]]; then
    open "$INSTALLED"
fi
