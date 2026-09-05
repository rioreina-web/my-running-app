#!/usr/bin/env bash
# Fresh run: build current code, replace what is on the simulator, relaunch,
# and tail the app's own log.
#
# Why this exists (2026-09-05): a debugging session burned on an app process
# that had been running 23 hours. It predated every fix that had shipped, was
# stuck on a sheet from the previous afternoon, and looked exactly like a
# backend failure. Nothing in the simulator tells you the binary is stale.
# `./scripts/run-ios.sh` makes "am I testing current code" a non-question.
set -euo pipefail

SIM="${SIM:-iPhone 17 Pro}"
APP_ID="com.postrundrip.app"
PROJ="RunningLog/RunningLog.xcodeproj"
cd "$(dirname "$0")/.."

say() { printf '\033[1m▸ %s\033[0m\n' "$*"; }

say "Booting $SIM"
xcrun simctl boot "$SIM" 2>/dev/null || true
open -a Simulator

say "Building"
DD=$(mktemp -d)
xcodebuild -project "$PROJ" -scheme RunningLog \
  -destination "platform=iOS Simulator,name=$SIM" \
  -derivedDataPath "$DD" build -quiet
APP=$(find "$DD/Build/Products" -maxdepth 2 -name "RunningLog.app" | head -1)
[ -n "$APP" ] || { echo "no .app produced"; exit 1; }

# Terminate + reinstall rather than launch-over-the-top: an install alone
# leaves the OLD process running, which is the exact failure this prevents.
say "Replacing the installed app"
xcrun simctl terminate "$SIM" "$APP_ID" 2>/dev/null || true
xcrun simctl install "$SIM" "$APP"

say "Launching"
PID=$(xcrun simctl launch "$SIM" "$APP_ID" | awk -F': ' '{print $2}')
echo "  pid $PID · built $(date '+%H:%M:%S') · $(git rev-parse --short HEAD)$(git diff --quiet || echo '+dirty')"

say "Log (ctrl-C to stop)"
xcrun simctl spawn "$SIM" log stream \
  --predicate "subsystem == \"$APP_ID\"" --level info --style compact
