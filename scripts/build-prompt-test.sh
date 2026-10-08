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

# Keep the standard build contract and executable name. Release update overrides
# must not turn this local test bundle into a production update client.
env -u SPARKLE_FEED_URL -u SPARKLE_PUBLIC_ED_KEY \
    CONFIGURATION=debug REQUIRE_SIGNED_UPDATES=0 ./scripts/build-app.sh

mkdir -p "$STAGING_ROOT"
rm -rf "$STAGED_APP"
ditto "$PROJECT_ROOT/build/OpenNoType.app" "$STAGED_APP"

python3 - "$STAGED_APP" "$SOURCE_COMMIT" <<'PY'
import json
import plistlib
import re
import sys
from pathlib import Path

app = Path(sys.argv[1])
commit = sys.argv[2]
if not re.fullmatch(r"(?:[0-9a-f]{40}|[0-9a-f]{64})", commit):
    raise SystemExit("Could not identify the test source commit.")
info_path = app / "Contents/Info.plist"
info = plistlib.loads(info_path.read_bytes())
if info.get("CFBundleIdentifier") != "app.opennotype.mac" or info.get("CFBundleExecutable") != "OpenNoType":
    raise SystemExit("Expected a freshly built OpenNoType app bundle.")
info.update({
    "CFBundleIdentifier": "app.opennotype.prompt-test",
    "CFBundleName": "OpenNoType Prompt Test",
    "CFBundleDisplayName": "OpenNoType Prompt Test",
    "OpenNoTypeTestSourceCommit": commit,
    "SUEnableAutomaticChecks": False,
    "SUAutomaticallyUpdate": False,
})
for key in list(info):
    if key in ("SUFeedURL", "SUPublicEDKey", "OpenNoTypeDistribution") or key.startswith("OpenNoTypePreview"):
        del info[key]
messages = {
    "en": {
        "NSMicrophoneUsageDescription": "OpenNoType Prompt Test uses the microphone to turn your speech into text and enroll your voice.",
        "NSSpeechRecognitionUsageDescription": "OpenNoType Prompt Test converts speech to text on this Mac.",
    },
    "ko": {
        "NSMicrophoneUsageDescription": "OpenNoType Prompt Test에서 말씀하신 내용을 글로 입력하고 내 목소리를 등록하기 위해 마이크를 사용합니다.",
        "NSSpeechRecognitionUsageDescription": "OpenNoType Prompt Test에서 기기의 음성을 글로 변환합니다.",
    },
}
info.update(messages["en"])
info_path.write_bytes(plistlib.dumps(info, sort_keys=False))

# Localized privacy strings override Info.plist; rename those in the staged copy too.
for language, values in messages.items():
    strings_path = app / "Contents/Resources" / f"{language}.lproj/InfoPlist.strings"
    text = strings_path.read_text(encoding="utf-8")
    for key, value in values.items():
        pattern = r'^"' + re.escape(key) + r'"\s*=\s*"(?:\\.|[^"\\])*"\s*;'
        replacement = json.dumps(key) + " = " + json.dumps(value, ensure_ascii=False) + ";"
        text, count = re.subn(pattern, lambda match: replacement, text, flags=re.MULTILINE)
        if count != 1:
            raise SystemExit(f"Expected one localized {key} in {language}.")
    strings_path.write_text(text, encoding="utf-8")
PY

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
