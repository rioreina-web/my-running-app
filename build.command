#!/bin/bash
# Double-clickable build for the RunningLog app.
# Written by Claude so the build can be triggered without typing in Terminal.
# Everything goes to build.log, which Claude reads back over the file bridge.
cd "$(dirname "$0")" || exit 1
{
  echo "=== BUILD START $(date) ==="
  xcodebuild \
    -project RunningLog/RunningLog.xcodeproj \
    -scheme RunningLog \
    -destination 'generic/platform=iOS Simulator' \
    -configuration Debug \
    CODE_SIGNING_ALLOWED=NO \
    build 2>&1
  echo "=== EXIT $? ==="
  echo "=== BUILD END $(date) ==="
} > build.log 2>&1
echo "Done. Wrote build.log"
