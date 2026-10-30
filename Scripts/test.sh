#!/usr/bin/env bash
# Build with warnings as errors and run the tests on the newest available iPhone simulator.
set -euo pipefail
device=$(xcrun simctl list devices available --json | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
runtimes = sorted((r for r in devices if "iOS" in r), reverse=True)
print(next(d["udid"] for r in runtimes for d in devices[r] if d["name"].startswith("iPhone")))')
xcodebuild test -project GCPAPISync.xcodeproj -scheme GCPAPISyncApp \
    -destination "id=${device}" -derivedDataPath .build/derived -collect-test-diagnostics never \
    -quiet "$@"
