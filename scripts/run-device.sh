#!/usr/bin/env bash
# Put CURRENT code on the paired iPhone: build, install, relaunch, print the
# commit it built. Companion to run-ios.sh (simulator).
#
# Why (2026-09-05): the phone was running a build from the previous afternoon
# with none of that day's fixes — and there is no way to tell from the phone.
# The phone must be reachable: cable, or on the same Wi-Fi with
# "Connect via network" on in Xcode's Devices window. If devicectl says
# "A connection to this device could not be established", that is the fix.
set -euo pipefail
cd "$(dirname "$0")/.."
DEV="${DEV:-E859651D-E4AB-570F-BA63-24F9E752E66B}"   # iPhone 16 Pro
APP_ID="com.postrundrip.app"

say() { printf '\033[1m▸ %s\033[0m\n' "$*"; }

say "Checking the phone is reachable"
if ! xcrun devicectl device info details --device "$DEV" 2>&1 | grep -q "tunnelState: connected"; then
  echo "  iPhone $DEV is paired but not connected. Plug it in (or enable"
  echo "  'Connect via network' in Xcode ▸ Devices) and re-run."
  xcrun devicectl device info details --device "$DEV" 2>&1 | grep -E "lastConnectionDate|tunnelState" | sed 's/^/  /'
  exit 2
fi

# Two identifiers for one phone (2026-09-05): devicectl addresses it by the
# CoreDevice id ($DEV); xcodebuild only knows the hardware UDID. Handing
# xcodebuild the CoreDevice id fails with "Unable to find a device matching
# the provided destination specifier" and a list of simulators — twice today.
UDID=$(xcrun devicectl device info details --device "$DEV" 2>/dev/null | awk '/udid:/ {print $NF}')
[ -n "$UDID" ] || { echo "could not read the phone's UDID from devicectl"; exit 1; }

say "Building for device $UDID ($(git rev-parse --short HEAD)$(git diff --quiet || echo '+dirty'))"
DD=$(mktemp -d)
xcodebuild -project RunningLog/RunningLog.xcodeproj -scheme RunningLog \
  -destination "platform=iOS,id=$UDID" -derivedDataPath "$DD" -allowProvisioningUpdates build -quiet
APP=$(find "$DD/Build/Products" -maxdepth 2 -name "RunningLog.app" | head -1)
[ -n "$APP" ] || { echo "no .app produced"; exit 1; }

say "Installing"
xcrun devicectl device install app --device "$DEV" "$APP"

say "Relaunching"
xcrun devicectl device process launch --device "$DEV" --terminate-existing "$APP_ID"
echo "  installed $(date '+%H:%M:%S') · $(git rev-parse --short HEAD)"
