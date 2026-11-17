#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p .build/cache
source source-files.sh
xcrun swiftc -swift-version 6 -target arm64-apple-macos27.0 -module-cache-path .build/cache "${core_sources[@]}" "${appkit_sources[@]}" Tests/*.swift -o .build/BatteryRunTests
if [ "$#" -gt 1 ] || { [ "$#" -eq 1 ] && [ "$1" != "--without-battery" ]; }; then
    printf 'Usage: bash run-tests.sh [--without-battery]\n' >&2
    exit 2
fi
.build/BatteryRunTests "$@"
