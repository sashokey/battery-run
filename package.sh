#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)"
expected_version="${1:-$version}"
bash build.sh
mkdir -p dist

app_name='Battery Run.app'
verification="$(mktemp -d .build/verify.XXXXXXXX)"
zip_name="Battery-Run-$version.zip"
ditto -c -k --keepParent ".build/$app_name" "$verification/$zip_name"
ditto -x -k "$verification/$zip_name" "$verification/extracted"

app="$verification/extracted/$app_name"
codesign --verify --deep --strict --verbose=2 "$app"
codesign -dvv --entitlements :- "$app" > "$verification/entitlements.plist" 2> "$verification/signature.txt"

python3 - "$app" "$expected_version" "$verification" <<'PY'
from pathlib import Path
import plistlib
import subprocess
import sys

app, version, verification = Path(sys.argv[1]), sys.argv[2], Path(sys.argv[3])
with (app / "Contents/Info.plist").open("rb") as source:
    info = plistlib.load(source)
with (verification / "entitlements.plist").open("rb") as source:
    entitlements = plistlib.load(source)
binary = app / "Contents/MacOS/BatteryRun"
signature = (verification / "signature.txt").read_text().splitlines()
minimums = [
    line.split()[1]
    for line in subprocess.check_output(["xcrun", "vtool", "-show-build", binary], text=True).splitlines()
    if line.strip().startswith("minos ")
]
dependencies = subprocess.check_output(["xcrun", "otool", "-L", binary], text=True)
checks = [
    (info["CFBundleShortVersionString"] == version, "Package version does not match the expected release"),
    (info["LSMinimumSystemVersion"] == "27.0" and minimums == ["27.0"], "Expected a macOS 27.0 deployment target"),
    (subprocess.check_output(["xcrun", "lipo", "-archs", binary], text=True).strip() == "arm64", "Expected an arm64 executable"),
    ("SwiftUI" not in dependencies, "Unexpected SwiftUI dependency"),
    ("Signature=adhoc" in signature, "Expected an ad-hoc signature"),
    (entitlements.get("com.apple.security.app-sandbox") is True and entitlements == {
        "com.apple.security.app-sandbox": True,
        "com.apple.security.temporary-exception.iokit-user-client-class": ["AppleSMCClient"],
        "com.apple.security.temporary-exception.files.absolute-path.read-only": ["/private/var/log/powermanagement/"],
    }, "Unexpected signed entitlements"),
]
for passed, message in checks:
    if not passed:
        sys.exit(message)
print(f"Verified Battery Run {version}: arm64, macOS 27, ad-hoc signature, exact sandbox entitlements")
PY

cp "$verification/$zip_name" "dist/$zip_name"
printf '%s\n' "dist/$zip_name"
