#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"
CONFIGURATION="${CONFIGURATION:-debug}"
# Public defaults come from the checked-in channel. Explicit overrides must be a
# complete pair; a development channel with no public key keeps updates disabled.
UPDATE_ARGUMENTS=(--channel-plist "$PROJECT_ROOT/Resources/UpdateChannel.plist")
if [ "${REQUIRE_SIGNED_UPDATES:-0}" = "1" ]; then
    UPDATE_ARGUMENTS+=(--release)
fi
python3 scripts/generate-update-feed.py configure --info-plist Resources/Info.plist "${UPDATE_ARGUMENTS[@]}"
swift build --product OpenNoType --configuration "$CONFIGURATION" --arch arm64
BIN_DIR="$(swift build --show-bin-path --configuration "$CONFIGURATION" --arch arm64)"
FINAL_APP="$PROJECT_ROOT/build/OpenNoType.app"
# Assemble in a staging directory and swap at the end: a running copy of the app keeps the files it
# already mapped, whereas overwriting its executable in place would kill it.
APP="$PROJECT_ROOT/build/.staging/OpenNoType.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN_DIR/OpenNoType" "$APP/Contents/MacOS/OpenNoType"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Sources/OpenNoType/Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
python3 scripts/generate-update-feed.py configure --info-plist "$APP/Contents/Info.plist" --write "${UPDATE_ARGUMENTS[@]}"
cp LICENSE "$APP/Contents/Resources/LICENSE"
if [ -f THIRD_PARTY_NOTICES.md ]; then cp THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/THIRD_PARTY_NOTICES.md"; fi
for resource in "$BIN_DIR"/*.bundle; do
    [ -d "$resource" ] || continue
    # The app's own SwiftPM resource bundle only duplicates AppIcon.icns, which is copied above and
    # read through Bundle.main; Bundle.module would not look in Contents/Resources anyway.
    [ "$(basename "$resource")" = "OpenNoType_OpenNoType.bundle" ] && continue
    ditto "$resource" "$APP/Contents/Resources/$(basename "$resource")"
done
SPARKLE="$PROJECT_ROOT/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [ ! -d "$SPARKLE" ]; then
    SPARKLE="$(find "$PROJECT_ROOT/.build/artifacts" -type d -name Sparkle.framework -path '*macos*' -print -quit)"
fi
test -d "$SPARKLE"
ditto "$SPARKLE" "$APP/Contents/Frameworks/Sparkle.framework"
if ! otool -l "$APP/Contents/MacOS/OpenNoType" | grep -q '@executable_path/../Frameworks'; then
    install_name_tool -add_rpath '@executable_path/../Frameworks' "$APP/Contents/MacOS/OpenNoType"
fi
# Local development signature only. Public release signing is a separate operation.
DEVELOPMENT_SIGNING_IDENTITY="${DEVELOPMENT_SIGNING_IDENTITY:--}"
FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
SPARKLE_CONTENTS="$FRAMEWORK/Versions/Current"
test -d "$SPARKLE_CONTENTS/XPCServices/Installer.xpc"
test -d "$SPARKLE_CONTENTS/XPCServices/Downloader.xpc"
test -x "$SPARKLE_CONTENTS/Autoupdate"
test -d "$SPARKLE_CONTENTS/Updater.app"
# Sign from the inside out; --deep would apply the app's entitlements to helpers.
codesign --force --sign "$DEVELOPMENT_SIGNING_IDENTITY" --options runtime --timestamp=none "$SPARKLE_CONTENTS/XPCServices/Installer.xpc"
codesign --force --sign "$DEVELOPMENT_SIGNING_IDENTITY" --options runtime --timestamp=none --preserve-metadata=entitlements "$SPARKLE_CONTENTS/XPCServices/Downloader.xpc"
codesign --force --sign "$DEVELOPMENT_SIGNING_IDENTITY" --options runtime --timestamp=none "$SPARKLE_CONTENTS/Autoupdate"
codesign --force --sign "$DEVELOPMENT_SIGNING_IDENTITY" --options runtime --timestamp=none "$SPARKLE_CONTENTS/Updater.app"
codesign --force --sign "$DEVELOPMENT_SIGNING_IDENTITY" --options runtime --timestamp=none "$FRAMEWORK"
codesign --force --sign "$DEVELOPMENT_SIGNING_IDENTITY" --timestamp=none --entitlements Resources/OpenNoType.entitlements "$APP"
codesign --verify --deep --strict "$APP"
rm -rf "$FINAL_APP"
mv "$APP" "$FINAL_APP"
rmdir "$PROJECT_ROOT/build/.staging" 2>/dev/null || true
printf '%s\n' "$FINAL_APP"
