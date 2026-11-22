#!/bin/bash
set -euo pipefail

source_dir="$(cd "$(dirname "$0")" && pwd)"
destination="${1:?Pass the absolute path to a new .app bundle}"
signing_identity="${2:?Pass an Apple-issued signing identity for WidgetKit}"

if [[ "$destination" != /*.app || -e "$destination" ]]; then
    echo "Choose a new absolute .app path" >&2
    exit 1
fi

build_dir="$(mktemp -d /private/tmp/codex-radar-build.XXXXXX)"
finish() {
    local result=$?
    if (( result == 0 )); then
        rm -rf -- "$build_dir"
    else
        echo "Build retained for diagnostics at $build_dir" >&2
    fi
}
trap finish EXIT
app="$build_dir/Codex Radar.app"
extension="$app/Contents/PlugIns/CodexRadarWidget.appex"
mkdir -p "$app/Contents/MacOS" "$extension/Contents/MacOS"

python3 - "$app" "$extension" "$build_dir/sandbox.plist" <<'PY'
from pathlib import Path
import plistlib
import sys

app, extension, entitlements = map(Path, sys.argv[1:])
shared = {
    "CFBundleDisplayName": "Codex Radar",
    "CFBundleDevelopmentRegion": "en",
    "CFBundleInfoDictionaryVersion": "6.0",
    "CFBundleShortVersionString": "1.0.0",
    "CFBundleSupportedPlatforms": ["MacOSX"],
    "CFBundleVersion": "4",
    "LSMinimumSystemVersion": "14.0",
}
containers = [
    (app, {
        "CFBundleIdentifier": "local.codexradar.desktop",
        "CFBundleName": "Codex Radar",
        "CFBundlePackageType": "APPL",
        "CFBundleExecutable": "CodexRadar",
        "LSApplicationCategoryType": "public.app-category.productivity",
        "NSHighResolutionCapable": True,
    }),
    (extension, {
        "CFBundleIdentifier": "local.codexradar.desktop.widget",
        "CFBundleName": "Codex Radar Widget",
        "CFBundlePackageType": "XPC!",
        "CFBundleExecutable": "CodexRadarWidget",
        "NSExtension": {
            "NSExtensionPointIdentifier": "com.apple.widgetkit-extension",
        },
    }),
]
for bundle, keys in containers:
    (bundle / "Contents/Info.plist").write_bytes(plistlib.dumps({**shared, **keys}))
entitlements.write_bytes(plistlib.dumps({
    "com.apple.security.app-sandbox": True,
    "com.apple.security.network.client": True,
}))
PY

sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
architecture="$(uname -m)"
compiler_options=(-sdk "$sdk_path" -target "$architecture-apple-macos14.0" -swift-version 5 -O -parse-as-library)

xcrun swiftc "${compiler_options[@]}" "$source_dir/RadarData.swift" "$source_dir/RadarFace.swift" \
    "$source_dir/RadarWidget.swift" -application-extension -framework Foundation \
    -Xlinker -e -Xlinker _NSExtensionMain -o "$extension/Contents/MacOS/CodexRadarWidget"
xcrun swiftc "${compiler_options[@]}" "$source_dir/RadarData.swift" "$source_dir/RadarFace.swift" \
    "$source_dir/RadarApp.swift" -o "$app/Contents/MacOS/CodexRadar"

plutil -lint "$app/Contents/Info.plist" "$extension/Contents/Info.plist"
remove_finder_metadata() {
    # Code signing rejects these Finder attributes on newly created app-bundle files.
    while IFS= read -r -d '' item; do
        for attribute in com.apple.FinderInfo com.apple.ResourceFork; do
            if xattr -p "$attribute" "$item" >/dev/null 2>&1; then
                xattr -d "$attribute" "$item"
            fi
        done
    done < <(find "$app" -print0)
}
remove_finder_metadata
codesign --force --sign "$signing_identity" --timestamp=none --entitlements "$build_dir/sandbox.plist" "$extension"
remove_finder_metadata
codesign --force --sign "$signing_identity" --timestamp=none --entitlements "$build_dir/sandbox.plist" "$app"
codesign --verify --deep --strict "$app"

mv "$app" "$destination"
echo "Built and verified Codex Radar.app"
