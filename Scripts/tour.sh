#!/usr/bin/env bash
# Run the screenshot tour (AppUITests) on a new, empty simulator, so that it always shows the
# demo with default settings, and save the screenshots to .build/tour/<device>/.
#   Scripts/tour.sh                  # iPhone
#   Scripts/tour.sh "iPad Pro 13-inch (M5)"
set -euo pipefail
model=${1:-"iPhone 17 Pro"}
runtime=$(xcrun simctl list runtimes available --json | python3 -c '
import json, sys
print(sorted(r["identifier"] for r in json.load(sys.stdin)["runtimes"] if r["platform"] == "iOS")[-1])')
device=$(xcrun simctl create "Tour" "$model" "$runtime")
trap 'xcrun simctl delete "$device"' EXIT
out=".build/tour/${model// /-}"
rm -rf "$out" "$out.xcresult"
status=0
xcodebuild test -project GCPAPISync.xcodeproj -scheme GCPAPISyncApp -destination "id=${device}" \
    -derivedDataPath .build/derived -only-testing:GCPAPISyncAppUITests -resultBundlePath "$out.xcresult" \
    -collect-test-diagnostics never -quiet || status=$?
mkdir -p "$out"
xcrun xcresulttool export attachments --path "$out.xcresult" --output-path "$out" > /dev/null
python3 - "$out" <<'PY'
import json, pathlib, sys
out = pathlib.Path(sys.argv[1])
for test in json.loads((out / "manifest.json").read_text()):
    for attachment in test["attachments"]:
        name = attachment["suggestedHumanReadableName"].split("_")[0]
        (out / attachment["exportedFileName"]).rename(out / f"{name}.png")
(out / "manifest.json").unlink()
PY
echo "Screenshots in $out"
exit "$status"
