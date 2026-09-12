#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"
# Missing mode preserves the Developer ID/notarization contract. No failure path
# ever downgrades to community signing; that mode must be selected explicitly.
RELEASE_SIGNING_MODE="${RELEASE_SIGNING_MODE-notarized}"
export RELEASE_SIGNING_MODE
case "$RELEASE_SIGNING_MODE" in
    community)
        SIGNING_IDENTITY=-
        # Ad-hoc code has no Team ID for hardened runtime library validation.
        SIGNING_OPTIONS=0
        TIMESTAMP_ARGUMENT=--timestamp=none
        ;;
    notarized)
        : "${DEVELOPER_ID_APPLICATION:?Set a Developer ID Application signing identity}"
        : "${NOTARY_PROFILE:?Set an existing notarytool Keychain profile}"
        case "$DEVELOPER_ID_APPLICATION" in
            'Developer ID Application: '*) ;;
            *) printf '%s\n' 'A local or ad-hoc identity cannot produce a notarized public release.' >&2; exit 1 ;;
        esac
        SIGNING_IDENTITY="$DEVELOPER_ID_APPLICATION"
        SIGNING_OPTIONS=runtime
        TIMESTAMP_ARGUMENT=--timestamp
        NOTARY_ARGUMENTS=(--keychain-profile "$NOTARY_PROFILE" --wait)
        if [ -n "${NOTARY_KEYCHAIN:-}" ]; then
            NOTARY_ARGUMENTS+=(--keychain "$NOTARY_KEYCHAIN")
        fi
        ;;
    *) printf '%s\n' 'RELEASE_SIGNING_MODE must be community or notarized.' >&2; exit 1 ;;
esac
: "${RELEASE_TAG:?Set the exact version tag, for example v0.1.10}"
: "${SPARKLE_PRIVATE_KEY_FILE:?Set a runtime 0600 Sparkle private-key file}"
# Keep previous releases intact and reject mixed artifacts before packaging.
python3 - <<'PY'
from pathlib import Path
output = Path('dist')
if output.is_symlink() or (output.exists() and (not output.is_dir() or any(output.iterdir()))):
    raise SystemExit('dist must be an empty directory. Move existing release artifacts to an archive before packaging again.')
PY
# Both modes require a valid public channel and the persistent update-signing key.
python3 scripts/generate-update-feed.py configure --info-plist Resources/Info.plist --release
python3 scripts/generate-update-feed.py validate-key-file
CONFIGURATION=release DEVELOPMENT_SIGNING_IDENTITY=- REQUIRE_SIGNED_UPDATES=1 scripts/build-app.sh
APP="$PROJECT_ROOT/build/OpenNoType.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
mkdir -p dist
# Sparkle's Autoupdate is a standalone executable, so bundle-only discovery misses it.
# Keep this order aligned with https://sparkle-project.org/documentation/sandboxing/#code-signing.
FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
SPARKLE_CONTENTS="$FRAMEWORK/Versions/Current"
test -d "$SPARKLE_CONTENTS/XPCServices/Installer.xpc"
test -d "$SPARKLE_CONTENTS/XPCServices/Downloader.xpc"
test -x "$SPARKLE_CONTENTS/Autoupdate"
test -d "$SPARKLE_CONTENTS/Updater.app"
# codesign silently ignores --options when it precedes --sign.
codesign --force --sign "$SIGNING_IDENTITY" --options "$SIGNING_OPTIONS" "$TIMESTAMP_ARGUMENT" "$SPARKLE_CONTENTS/XPCServices/Installer.xpc"
codesign --force --sign "$SIGNING_IDENTITY" --options "$SIGNING_OPTIONS" "$TIMESTAMP_ARGUMENT" --preserve-metadata=entitlements "$SPARKLE_CONTENTS/XPCServices/Downloader.xpc"
codesign --force --sign "$SIGNING_IDENTITY" --options "$SIGNING_OPTIONS" "$TIMESTAMP_ARGUMENT" "$SPARKLE_CONTENTS/Autoupdate"
codesign --force --sign "$SIGNING_IDENTITY" --options "$SIGNING_OPTIONS" "$TIMESTAMP_ARGUMENT" "$SPARKLE_CONTENTS/Updater.app"
codesign --force --sign "$SIGNING_IDENTITY" --options "$SIGNING_OPTIONS" "$TIMESTAMP_ARGUMENT" "$FRAMEWORK"
codesign --force --sign "$SIGNING_IDENTITY" --options "$SIGNING_OPTIONS" "$TIMESTAMP_ARGUMENT" --entitlements Resources/OpenNoType.entitlements "$APP"
codesign --verify --deep --strict "$APP"
ZIP="$PROJECT_ROOT/dist/OpenNoType-$VERSION.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
if [ "$RELEASE_SIGNING_MODE" = notarized ]; then
    xcrun notarytool submit "$ZIP" "${NOTARY_ARGUMENTS[@]}"
    xcrun stapler staple "$APP"
    xcrun stapler validate "$APP"
    # Recreate the final archive after stapling the notarization ticket.
    ditto -c -k --keepParent "$APP" "$ZIP"
fi
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/opennotype-dmg.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING/OpenNoType.app"
ln -s /Applications "$STAGING/Applications"
DMG="$PROJECT_ROOT/dist/OpenNoType-$VERSION.dmg"
hdiutil create -volname OpenNoType -srcfolder "$STAGING" -ov -format UDZO "$DMG"
codesign --force --sign "$SIGNING_IDENTITY" "$TIMESTAMP_ARGUMENT" "$DMG"
codesign --verify --strict "$DMG"
if [ "$RELEASE_SIGNING_MODE" = notarized ]; then
    xcrun notarytool submit "$DMG" "${NOTARY_ARGUMENTS[@]}"
    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG"
    spctl --assess --type execute --verbose "$APP"
fi
# Verify actual signatures against the declared distribution, then sign the
# final ZIP bytes. Both paths require Sparkle + bundled-public-key verification.
python3 scripts/generate-update-feed.py validate-signing --path "$DMG" --distribution "$RELEASE_SIGNING_MODE"
python3 scripts/generate-update-feed.py generate --app "$APP" --zip "$ZIP" --output-dir "$PROJECT_ROOT/dist"
(cd "$PROJECT_ROOT/dist" && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")
printf '%s\n' "$DMG"
