#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"
CONFIGURATION="${CONFIGURATION:-debug}"
SPARKLE_FEED_URL="${SPARKLE_FEED_URL:-}"
SPARKLE_PUBLIC_ED_KEY="${SPARKLE_PUBLIC_ED_KEY:-}"
if [ -n "$SPARKLE_FEED_URL" ] || [ -n "$SPARKLE_PUBLIC_ED_KEY" ]; then
    # These are public release settings, never the private update-signing key.
    if [[ ! "$SPARKLE_FEED_URL" =~ ^https://[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?(:[0-9]+)?(/[^[:space:][:cntrl:]]*)?$ ]]; then
        printf '%s\n' 'SPARKLE_FEED_URL must be an HTTPS URL with a host and no credentials or whitespace.' >&2
        exit 1
    fi
    # A canonical base64-encoded 32-byte Ed25519 public key.
    if [[ ! "$SPARKLE_PUBLIC_ED_KEY" =~ ^[A-Za-z0-9+/]{42}[AEIMQUYcgkosw048]=$ ]]; then
        printf '%s\n' 'Set SPARKLE_PUBLIC_ED_KEY to the matching 32-byte base64 public key; both Sparkle settings are required together.' >&2
        exit 1
    fi
fi
swift build --product OpenNoType --configuration "$CONFIGURATION" --arch arm64
BIN_DIR="$(swift build --show-bin-path --configuration "$CONFIGURATION" --arch arm64)"
APP="$PROJECT_ROOT/build/OpenNoType.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN_DIR/OpenNoType" "$APP/Contents/MacOS/OpenNoType"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [ -n "$SPARKLE_FEED_URL" ]; then
    /usr/bin/plutil -replace SUFeedURL -string "$SPARKLE_FEED_URL" "$APP/Contents/Info.plist"
    /usr/bin/plutil -replace SUPublicEDKey -string "$SPARKLE_PUBLIC_ED_KEY" "$APP/Contents/Info.plist"
fi
cp LICENSE "$APP/Contents/Resources/LICENSE"
if [ -f THIRD_PARTY_NOTICES.md ]; then cp THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/THIRD_PARTY_NOTICES.md"; fi
for resource in "$BIN_DIR"/*.bundle; do
    [ -d "$resource" ] || continue
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
codesign --force --options runtime --timestamp=none --sign "$DEVELOPMENT_SIGNING_IDENTITY" "$SPARKLE_CONTENTS/XPCServices/Installer.xpc"
codesign --force --options runtime --timestamp=none --preserve-metadata=entitlements --sign "$DEVELOPMENT_SIGNING_IDENTITY" "$SPARKLE_CONTENTS/XPCServices/Downloader.xpc"
codesign --force --options runtime --timestamp=none --sign "$DEVELOPMENT_SIGNING_IDENTITY" "$SPARKLE_CONTENTS/Autoupdate"
codesign --force --options runtime --timestamp=none --sign "$DEVELOPMENT_SIGNING_IDENTITY" "$SPARKLE_CONTENTS/Updater.app"
codesign --force --options runtime --timestamp=none --sign "$DEVELOPMENT_SIGNING_IDENTITY" "$FRAMEWORK"
codesign --force --timestamp=none --sign "$DEVELOPMENT_SIGNING_IDENTITY" --entitlements Resources/OpenNoType.entitlements "$APP"
codesign --verify --deep --strict "$APP"
printf '%s\n' "$APP"
