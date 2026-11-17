#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p .build/cache .build/AppIcon.iconset
source source-files.sh
app_path=".build/Battery Run.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
xcrun swiftc -swift-version 6 -O -whole-module-optimization -target arm64-apple-macos27.0 -module-cache-path .build/cache -parse-as-library "${core_sources[@]}" "${appkit_sources[@]}" Sources/AppKitApp.swift -Xlinker -dead_strip -o "$app_path/Contents/MacOS/BatteryRun"
cp Info.plist "$app_path/Contents/Info.plist"
if [ ! -f .build/AppIcon.icns ]; then
    xcrun swiftc -swift-version 6 -O -module-cache-path .build/cache Tools/DrawIcon.swift -o .build/DrawIcon
    .build/DrawIcon .build/Icon1024.png
    for icon_size in 16 32 128 256 512; do
        sips -z "$icon_size" "$icon_size" .build/Icon1024.png --out ".build/AppIcon.iconset/icon_${icon_size}x${icon_size}.png" >/dev/null
        retina_size=$((icon_size * 2))
        sips -z "$retina_size" "$retina_size" .build/Icon1024.png --out ".build/AppIcon.iconset/icon_${icon_size}x${icon_size}@2x.png" >/dev/null
    done
    iconutil -c icns .build/AppIcon.iconset -o .build/AppIcon.icns
fi
cp .build/AppIcon.icns "$app_path/Contents/Resources/AppIcon.icns"
strip -x "$app_path/Contents/MacOS/BatteryRun"
codesign --force --sign - --timestamp=none --entitlements Sandbox.entitlements "$app_path"
codesign --verify --deep --strict --verbose=2 "$app_path"
printf '%s\n' "$PWD/$app_path"
