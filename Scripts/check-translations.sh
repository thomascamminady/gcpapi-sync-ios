#!/usr/bin/env bash
# Export the strings the compiler finds and fail if any lacks a German translation.
set -euo pipefail
out=$(mktemp -d)
xcodebuild -exportLocalizations -project GCPAPISync.xcodeproj -scheme GCPAPISyncApp \
    -localizationPath "$out" -exportLanguage de -derivedDataPath .build/localization -quiet "$@"
python3 - "$out/de.xcloc/Localized Contents/de.xliff" <<'PY'
import sys
import xml.etree.ElementTree as ET

ns = {"x": "urn:oasis:names:tc:xliff:document:1.2"}
missing = []
for unit in ET.parse(sys.argv[1]).getroot().iterfind(".//x:trans-unit", ns):
    target = unit.find("x:target", ns)
    if unit.get("translate") != "no" and (target is None or target.get("state") != "translated"):
        missing.append(unit.get("id"))
for key in missing:
    print(f"::error title=Missing German translation::{key}")
print(f"{len(missing)} strings without a German translation")
sys.exit(1 if missing else 0)
PY
