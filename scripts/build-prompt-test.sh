#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "$PROJECT_ROOT"

TEST_ROOT="$PROJECT_ROOT/build/prompt-test"
STAGING_ROOT="$TEST_ROOT/.staging"
STAGED_APP="$STAGING_ROOT/OpenNoType Prompt Test.app"
PREVIOUS_APP="$STAGING_ROOT/Previous OpenNoType Prompt Test.app"
FINAL_APP="$TEST_ROOT/OpenNoType Prompt Test.app"
TEST_BUNDLE_ID="app.opennotype.prompt-test"

fail() { printf '%s\n' "$1" >&2; exit 1; }

# Only fixed paths inside this checkout are used, including for cleanup.
for path in "$PROJECT_ROOT/build" "$PROJECT_ROOT/build/.staging" "$PROJECT_ROOT/build/.staging/OpenNoType.app" \
    "$TEST_ROOT" "$STAGING_ROOT" "$STAGED_APP" "$PREVIOUS_APP" "$FINAL_APP"; do
    [ ! -L "$path" ] || fail "Refusing a symlink at a test packaging path: $path"
done
[ ! -e "$PREVIOUS_APP" ] || fail 'A previous test bundle remains in staging. Recover it before rebuilding.'
if [ -e "$FINAL_APP" ]; then
    existing_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$FINAL_APP/Contents/Info.plist" 2>/dev/null)" \
        || fail 'The existing destination is not a readable test app bundle.'
    [ "$existing_id" = "$TEST_BUNDLE_ID" ] || fail 'Refusing to replace an app with a different bundle identifier.'
fi

assert_test_not_running() {
    local status
    # Match the identity at every location, including a bundle opened from staging.
    status="$(/usr/bin/osascript -l JavaScript <<'JXA'
ObjC.import('AppKit');
function run() {
    var applications = $.NSWorkspace.sharedWorkspace.runningApplications;
    for (var index = 0; index < applications.count; index++) {
        var application = applications.objectAtIndex(index);
        if (ObjC.unwrap(application.bundleIdentifier) === 'app.opennotype.prompt-test') {
            return 'running';
        }
    }
    return 'stopped';
}
JXA
    )" || fail 'Could not verify whether the test app is running.'
    [ "$status" = 'stopped' ] || fail 'Quit OpenNoType Prompt Test before rebuilding it.'
}

assert_test_not_running
SOURCE_COMMIT="$(git rev-parse --verify HEAD)"
SOURCE_DIRTY=false
if [ -n "$(git status --porcelain --untracked-files=normal)" ]; then SOURCE_DIRTY=true; fi
BUILT_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Keep the standard build contract and executable name. Release update overrides
# must not turn this local test bundle into a production update client.
env -u SPARKLE_FEED_URL -u SPARKLE_PUBLIC_ED_KEY \
    CONFIGURATION=debug REQUIRE_SIGNED_UPDATES=0 ./scripts/build-app.sh

mkdir -p "$STAGING_ROOT"
rm -rf "$STAGED_APP"
ditto "$PROJECT_ROOT/build/OpenNoType.app" "$STAGED_APP"

[ "$(git rev-parse --verify HEAD)" = "$SOURCE_COMMIT" ] \
    || fail 'The source commit changed during the test build. Rebuild from the intended commit.'
if [ -n "$(git status --porcelain --untracked-files=normal)" ]; then SOURCE_DIRTY=true; fi
python3 scripts/configure-prompt-test.py "$STAGED_APP" Resources/PromptTestVersion.plist \
    "$SOURCE_COMMIT" "$SOURCE_DIRTY" "$BUILT_AT"

/usr/bin/plutil -lint "$STAGED_APP/Contents/Info.plist"
test -x "$STAGED_APP/Contents/MacOS/OpenNoType"
# Frameworks were signed inside out by build-app.sh; only the edited app is re-signed.
codesign --force --timestamp=none --sign "${DEVELOPMENT_SIGNING_IDENTITY:--}" \
    --entitlements Resources/OpenNoType.entitlements "$STAGED_APP"
codesign --verify --deep --strict "$STAGED_APP"

assert_test_not_running
restore_previous_on_failure() {
    local status=$?
    if [ "$status" -ne 0 ] && [ -d "$PREVIOUS_APP" ] && [ ! -e "$FINAL_APP" ]; then
        mv "$PREVIOUS_APP" "$FINAL_APP" || true
    fi
}
trap restore_previous_on_failure EXIT
if [ -e "$FINAL_APP" ]; then mv "$FINAL_APP" "$PREVIOUS_APP"; fi
mv "$STAGED_APP" "$FINAL_APP"
if [ -d "$PREVIOUS_APP" ]; then rm -rf "$PREVIOUS_APP"; fi
rmdir "$STAGING_ROOT" 2>/dev/null || true
printf '%s\n' "$FINAL_APP"
