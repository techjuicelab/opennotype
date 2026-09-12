#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"
APPEARANCE="${1:-light}"
PAGE="${2:-usage}"
case "$APPEARANCE" in
    light|dark) ;;
    *) printf '%s\n' 'Usage: build-usage-preview.sh [light|dark] [usage|history]' >&2; exit 1 ;;
esac
case "$PAGE" in
    usage|history) ;;
    *) printf '%s\n' 'Usage: build-usage-preview.sh [light|dark] [usage|history]' >&2; exit 1 ;;
esac

# AppLaunch permits synthetic data only in this separately identified debug bundle.
# Rebuilding first prevents accidentally packaging a release binary as a preview.
CONFIGURATION=debug ./scripts/build-app.sh
PREVIEW="$PROJECT_ROOT/build/usage-preview/OpenNoTypeUsagePreview.app"
ditto build/OpenNoType.app "$PREVIEW"
plutil -replace CFBundleIdentifier -string app.opennotype.usage-preview "$PREVIEW/Contents/Info.plist"
plutil -replace CFBundleName -string OpenNoTypeUsagePreview "$PREVIEW/Contents/Info.plist"
plutil -replace OpenNoTypePreviewAppearance -string "$APPEARANCE" "$PREVIEW/Contents/Info.plist"
plutil -replace OpenNoTypePreviewPage -string "$PAGE" "$PREVIEW/Contents/Info.plist"
codesign --force --timestamp=none --sign "${DEVELOPMENT_SIGNING_IDENTITY:--}" --entitlements Resources/OpenNoType.entitlements "$PREVIEW"
codesign --verify --deep --strict "$PREVIEW"
printf '%s\n' "$PREVIEW"
