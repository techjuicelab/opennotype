#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"
: "${DEVELOPER_ID_APPLICATION:?Set a Developer ID Application signing identity}"
: "${NOTARY_PROFILE:?Set an existing notarytool Keychain profile}"
: "${RELEASE_TAG:?Set the exact version tag, for example v0.1.9}"
: "${SPARKLE_PRIVATE_KEY_FILE:?Set a runtime 0600 Sparkle private-key file}"
# Keep previous releases intact and reject mixed artifacts before notarization.
python3 - <<'PY'
from pathlib import Path
output = Path('dist')
if output.is_symlink() or (output.exists() and (not output.is_dir() or any(output.iterdir()))):
    raise SystemExit('dist must be an empty directory. Move existing release artifacts to an archive before packaging again.')
PY
# Validate public configuration and the private file before building or contacting Apple.
python3 scripts/generate-update-feed.py configure --info-plist Resources/Info.plist --release
python3 scripts/generate-update-feed.py validate-key-file
NOTARY_ARGUMENTS=(--keychain-profile "$NOTARY_PROFILE" --wait)
if [ -n "${NOTARY_KEYCHAIN:-}" ]; then
    NOTARY_ARGUMENTS+=(--keychain "$NOTARY_KEYCHAIN")
fi
case "$DEVELOPER_ID_APPLICATION" in
    'Developer ID Application: '*) ;;
    *) printf '%s\n' 'A local or ad-hoc identity cannot produce a notarized public release.' >&2; exit 1 ;;
esac
# The initial bundle needs no access to a development signing identity.
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
codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID_APPLICATION" "$SPARKLE_CONTENTS/XPCServices/Installer.xpc"
codesign --force --options runtime --timestamp --preserve-metadata=entitlements --sign "$DEVELOPER_ID_APPLICATION" "$SPARKLE_CONTENTS/XPCServices/Downloader.xpc"
codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID_APPLICATION" "$SPARKLE_CONTENTS/Autoupdate"
codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID_APPLICATION" "$SPARKLE_CONTENTS/Updater.app"
codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID_APPLICATION" "$FRAMEWORK"
codesign --force --options runtime --timestamp --entitlements Resources/OpenNoType.entitlements --sign "$DEVELOPER_ID_APPLICATION" "$APP"
codesign --verify --deep --strict "$APP"
ZIP="$PROJECT_ROOT/dist/OpenNoType-$VERSION.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" "${NOTARY_ARGUMENTS[@]}"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
# Keep the ZIP distributable too: the first archive predates the stapled ticket.
ditto -c -k --keepParent "$APP" "$ZIP"
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/opennotype-dmg.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING/OpenNoType.app"
ln -s /Applications "$STAGING/Applications"
DMG="$PROJECT_ROOT/dist/OpenNoType-$VERSION.dmg"
hdiutil create -volname OpenNoType -srcfolder "$STAGING" -ov -format UDZO "$DMG"
codesign --force --timestamp --sign "$DEVELOPER_ID_APPLICATION" "$DMG"
xcrun notarytool submit "$DMG" "${NOTARY_ARGUMENTS[@]}"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl --assess --type execute --verbose "$APP"
# Sign only the final stapled ZIP bytes, then verify with Sparkle and the app's
# public key. The helper emits appcast.xml, ZIP.sha256, and public metadata.
python3 scripts/generate-update-feed.py generate --app "$APP" --zip "$ZIP" --output-dir "$PROJECT_ROOT/dist"
(cd "$PROJECT_ROOT/dist" && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")
printf '%s\n' "$DMG"
