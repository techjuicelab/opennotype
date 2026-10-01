#!/bin/bash
set -euo pipefail
REPOSITORY='techjuicelab/opennotype'
BUNDLE_ID='app.opennotype.mac'
DESTINATION='/Applications'
VERIFY_ONLY=0
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --destination)
            [[ "$#" -ge 2 ]] || { printf '%s\n' '--destination에는 폴더 경로가 필요합니다.' >&2; exit 1; }
            DESTINATION="$2"; shift 2 ;;
        --verify-only) VERIFY_ONLY=1; shift ;;
        --help)
            printf '%s\n' '사용법: scripts/install-release.sh [--destination /Applications] [--verify-only]' \
                '공식 최신 릴리스를 검증해 설치합니다. 실행·권한 변경·보안 우회는 하지 않습니다.'; exit 0 ;;
        *) printf '알 수 없는 옵션: %s\n' "$1" >&2; exit 1 ;;
    esac
done
fail() { printf '설치 중단: %s\n' "$1" >&2; exit 1; }
for tool in sw_vers sysctl curl plutil shasum unzip ditto file codesign pgrep osascript xattr; do
    command -v "$tool" >/dev/null || fail "macOS 기본 도구 $tool를 찾을 수 없습니다."
done
[[ "$(uname -s)" == Darwin ]] || fail 'macOS 전용 설치 스크립트입니다.'
[[ "$(sysctl -n hw.optional.arm64 2>/dev/null || true)" == 1 ]] || fail 'Apple Silicon(M1 이상) Mac이 필요합니다. Intel Mac은 지원하지 않습니다.'
HOST_VERSION="$(sw_vers -productVersion)"
[[ "$HOST_VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || fail 'macOS 버전을 확인하지 못했습니다.'
[[ "${HOST_VERSION%%.*}" -ge 14 ]] || fail 'macOS 14 이상이 필요합니다.'
[[ "$DESTINATION" == /* ]] || fail '설치 폴더는 절대 경로로 지정해 주세요.'
if [[ "$VERIFY_ONLY" -eq 0 ]]; then
    if [[ ! -d "$DESTINATION" || ! -w "$DESTINATION" ]]; then
        printf '%s\n' '사용자 폴더에 설치하려면 먼저 mkdir -p "$HOME/Applications"를 실행하고,' \
            '이 스크립트를 --destination "$HOME/Applications" 옵션으로 다시 실행해 주세요.' >&2
        fail "설치 폴더에 쓸 수 없습니다: $DESTINATION"
    fi
    if pgrep -x OpenNoType >/dev/null; then fail '실행 중인 OpenNoType을 종료한 뒤 다시 설치해 주세요.'; fi
fi
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/opennotype-release-install.XXXXXX")"
STAGE_DIR=''
OLD_MOVED=0
NEW_MOVED=0
SUCCEEDED=0
APP_PATH="$DESTINATION/OpenNoType.app"
cleanup() {
    local status="$?"
    local keep_stage=0
    if [[ "$SUCCEEDED" -eq 0 && -n "$STAGE_DIR" ]]; then
        if [[ "$NEW_MOVED" -eq 1 && -e "$APP_PATH" ]]; then
            mv "$APP_PATH" "$STAGE_DIR/rejected.app" || keep_stage=1
        fi
        if [[ "$OLD_MOVED" -eq 1 ]]; then
            if [[ ! -e "$APP_PATH" ]] && mv "$STAGE_DIR/previous.app" "$APP_PATH"; then
                printf '%s\n' '이전 앱으로 되돌렸습니다.' >&2
            else
                keep_stage=1
                printf '이전 앱을 자동으로 복원하지 못했습니다. 백업을 보존했습니다: %s/previous.app\n' "$STAGE_DIR" >&2
            fi
        fi
    fi
    rm -rf "$WORK_DIR"
    if [[ -n "$STAGE_DIR" && "$keep_stage" -eq 0 ]]; then rm -rf "$STAGE_DIR"; fi
    return "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
download() {
    curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' --tlsv1.2 \
        --connect-timeout 15 --max-time 300 --retry 2 -o "$2" "$1" || fail 'GitHub 다운로드에 실패했습니다. 기존 앱은 교체하지 않았습니다.'
}
RELEASE_JSON="$WORK_DIR/release.json"
download "https://api.github.com/repos/$REPOSITORY/releases/latest" "$RELEASE_JSON"
[[ "$(plutil -extract draft raw -o - "$RELEASE_JSON")" == false && \
   "$(plutil -extract prerelease raw -o - "$RELEASE_JSON")" == false ]] || fail '공개 정식 릴리스가 아닙니다.'
TAG="$(plutil -extract tag_name raw -o - "$RELEASE_JSON")"
[[ "$TAG" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || fail '지원하지 않는 릴리스 태그입니다.'
VERSION="${TAG#v}"
ZIP_NAME="OpenNoType-$VERSION.zip"
RELEASE_BASE="https://github.com/$REPOSITORY/releases/download/$TAG"
ZIP_FOUND=0
SHA_FOUND=0
INDEX=0
while ASSET_NAME="$(plutil -extract "assets.$INDEX.name" raw -o - "$RELEASE_JSON" 2>/dev/null)"; do
    if [[ "$ASSET_NAME" == "$ZIP_NAME" || "$ASSET_NAME" == "$ZIP_NAME.sha256" ]]; then
        ASSET_URL="$(plutil -extract "assets.$INDEX.browser_download_url" raw -o - "$RELEASE_JSON")"
        [[ "$ASSET_URL" == "$RELEASE_BASE/$ASSET_NAME" ]] || fail '공식 고정 버전 다운로드 주소와 일치하지 않습니다.'
        if [[ "$ASSET_NAME" == "$ZIP_NAME" ]]; then ZIP_FOUND=$((ZIP_FOUND + 1)); else SHA_FOUND=$((SHA_FOUND + 1)); fi
    fi
    INDEX=$((INDEX + 1))
    [[ "$INDEX" -le 100 ]] || fail '릴리스 자산 목록이 지원 범위를 벗어났습니다.'
done
[[ "$ZIP_FOUND" -eq 1 && "$SHA_FOUND" -eq 1 ]] || fail '릴리스 ZIP과 SHA-256 확인 파일이 없거나 중복되었습니다.'
download "$RELEASE_BASE/$ZIP_NAME" "$WORK_DIR/$ZIP_NAME"
download "$RELEASE_BASE/$ZIP_NAME.sha256" "$WORK_DIR/checksum"
EXPECTED_SHA="$(awk -v name="$ZIP_NAME" 'NR == 1 { sub(/^\*/, "", $2); if (NF != 2 || length($1) != 64 || $1 ~ /[^0-9a-fA-F]/ || $2 != name) exit 1; sha=tolower($1) } NR > 1 { exit 1 } END { if (sha == "") exit 1; print sha }' "$WORK_DIR/checksum")" || fail 'SHA-256 확인 파일 형식이 올바르지 않습니다.'
ACTUAL_SHA="$(shasum -a 256 "$WORK_DIR/$ZIP_NAME" | awk '{print $1}')"
[[ "$EXPECTED_SHA" == "$ACTUAL_SHA" ]] || fail 'ZIP SHA-256이 일치하지 않습니다. 기존 앱은 교체하지 않았습니다.'
unzip -Z -1 "$WORK_DIR/$ZIP_NAME" > "$WORK_DIR/entries" || fail 'ZIP 목록을 읽을 수 없습니다.'
while IFS= read -r entry; do
    case "$entry" in
        /*|*\\*|../*|*/../*|*/..) fail 'ZIP에 안전하지 않은 경로가 포함되어 있습니다.' ;;
        OpenNoType.app|OpenNoType.app/*|__MACOSX|__MACOSX/*) ;;
        *) fail 'ZIP에 예상하지 않은 최상위 항목이 포함되어 있습니다.' ;;
    esac
done < "$WORK_DIR/entries"
ditto -x -k "$WORK_DIR/$ZIP_NAME" "$WORK_DIR/unpacked" || fail 'ZIP 추출에 실패했습니다.'
RELEASE_APP="$WORK_DIR/unpacked/OpenNoType.app"
plist_value() { /usr/libexec/PlistBuddy -c "Print :$2" "$1/Contents/Info.plist"; }
validate_app() {
    local app="$1"
    [[ -d "$app" && ! -L "$app" ]] || fail '정상적인 OpenNoType.app 폴더가 아닙니다.'
    [[ "$(plist_value "$app" CFBundleIdentifier)" == "$BUNDLE_ID" ]] || fail '앱 bundle ID가 일치하지 않습니다.'
    [[ "$(plist_value "$app" CFBundleExecutable)" == OpenNoType ]] || fail '앱 실행 파일 이름이 일치하지 않습니다.'
    [[ "$(plist_value "$app" CFBundleShortVersionString)" == "$VERSION" ]] || fail '앱 버전과 릴리스 태그가 다릅니다.'
    [[ "$(plist_value "$app" CFBundleVersion)" =~ ^[1-9][0-9]*$ ]] || fail '앱 build 번호가 올바르지 않습니다.'
    [[ "$(plist_value "$app" CFBundlePackageType)" == APPL ]] || fail 'macOS 앱 bundle이 아닙니다.'
    local min_os
    min_os="$(plist_value "$app" LSMinimumSystemVersion)"
    [[ "$min_os" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || fail '앱 최소 macOS 버전이 올바르지 않습니다.'
    awk -v host="$HOST_VERSION" -v required="$min_os" 'BEGIN { split(host,h,"."); split(required,r,"."); for(i=1;i<=3;i++){ if(h[i]+0>r[i]+0) exit 0; if(h[i]+0<r[i]+0) exit 1; } }' || fail "이 릴리스에는 macOS $min_os 이상이 필요합니다."
    [[ -f "$app/Contents/MacOS/OpenNoType" && -x "$app/Contents/MacOS/OpenNoType" ]] || fail '앱 실행 파일이 없습니다.'
    local architecture
    architecture="$(file -b "$app/Contents/MacOS/OpenNoType")"
    [[ "$architecture" == *Mach-O* && "$architecture" == *arm64* ]] || fail '앱에 arm64 Mach-O 실행 파일이 없습니다.'
    codesign --verify --deep --strict "$app" >/dev/null 2>&1 || fail '앱 코드 서명 검증에 실패했습니다.'
}
validate_app "$RELEASE_APP"
printf '공식 %s ZIP: SHA-256·bundle·arm64·코드 서명 검증 통과\n' "$TAG"
if [[ "$VERIFY_ONLY" -eq 1 ]]; then
    printf '%s\n' '검증만 완료했습니다. 앱 설치나 실행은 하지 않았습니다.'
    SUCCEEDED=1; exit 0
fi
[[ ! -L "$APP_PATH" ]] || fail '기존 앱 경로가 심볼릭 링크이므로 교체하지 않습니다.'
if [[ -e "$APP_PATH" ]]; then
    [[ -d "$APP_PATH" && "$(plist_value "$APP_PATH" CFBundleIdentifier)" == "$BUNDLE_ID" ]] || fail '동일한 위치의 다른 앱은 교체하지 않습니다.'
    EXISTING_VERSION="$(plist_value "$APP_PATH" CFBundleShortVersionString)" || fail '기존 앱 버전을 확인하지 못해 교체하지 않습니다.'
    EXISTING_BUILD="$(plist_value "$APP_PATH" CFBundleVersion)" || fail '기존 앱 build 번호를 확인하지 못해 교체하지 않습니다.'
    [[ "$EXISTING_VERSION" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ && "$EXISTING_BUILD" =~ ^[1-9][0-9]*$ ]] || fail '기존 앱 버전 형식을 확인하지 못해 교체하지 않습니다.'
    RELEASE_BUILD="$(plist_value "$RELEASE_APP" CFBundleVersion)"
    awk -v old="$EXISTING_VERSION" -v release="$VERSION" -v oldBuild="$EXISTING_BUILD" -v newBuild="$RELEASE_BUILD" \
        'BEGIN { split(old,o,"."); split(release,r,"."); for(i=1;i<=3;i++){ if(o[i]+0>r[i]+0) exit 1; if(o[i]+0<r[i]+0) exit 0; } exit (oldBuild+0>newBuild+0) }' || fail '설치된 앱이 공개 최신 릴리스보다 새 버전입니다. 이전 버전으로 내리지 않았습니다.'
fi
if pgrep -x OpenNoType >/dev/null; then fail '설치 중 OpenNoType이 실행되었습니다. 앱을 종료하고 다시 시도해 주세요.'; fi
STAGE_DIR="$(mktemp -d "$DESTINATION/.opennotype-install.XXXXXX")"
ditto "$RELEASE_APP" "$STAGE_DIR/OpenNoType.app" || fail '설치 폴더에 앱을 준비하지 못했습니다.'
validate_app "$STAGE_DIR/OpenNoType.app"
# curl has no browser download agent. Add the OS's documented quarantine metadata;
# never remove quarantine, disable Gatekeeper, or grant/reset TCC permissions.
if ! osascript -l JavaScript - "$STAGE_DIR/OpenNoType.app" \
    "$RELEASE_BASE/$ZIP_NAME" "https://github.com/$REPOSITORY/releases/tag/$TAG" >/dev/null <<'JXA'
// File metadata only: no application control, permissions, or UI automation.
// NSURLQuarantinePropertiesKey and LSQuarantine.h define the public dictionary.
// Let Foundation encode it rather than guessing com.apple.quarantine flags.
ObjC.import("Foundation");
ObjC.import("CoreServices");
function run(argv) {
    if (argv.length !== 3) throw new Error("Expected bundle path and source URLs");
    var url = $.NSURL.fileURLWithPath(argv[0]);
    var properties = $.NSMutableDictionary.alloc.init;
    // CoreServices exports CFStringRef; bridge it to NSString for NSDictionary.
    function string(value) { return ObjC.castRefToObject(value); }
    properties.setObjectForKey("OpenNoType Installer", string($.kLSQuarantineAgentNameKey));
    properties.setObjectForKey($.NSDate.date, string($.kLSQuarantineTimeStampKey));
    properties.setObjectForKey(string($.kLSQuarantineTypeOtherDownload), string($.kLSQuarantineTypeKey));
    // Use source strings as Chromium's macOS quarantine implementation does.
    // Some OS versions omit them from readback; quarantine itself is required.
    properties.setObjectForKey(argv[1], string($.kLSQuarantineDataURLKey));
    properties.setObjectForKey(argv[2], string($.kLSQuarantineOriginURLKey));
    var error = Ref();
    if (!url.setResourceValueForKeyError(properties, $.NSURLQuarantinePropertiesKey, error)) {
        throw new Error("Could not set download quarantine metadata");
    }
    var stored = Ref();
    if (!url.getResourceValueForKeyError(stored, $.NSURLQuarantinePropertiesKey, error) ||
        ObjC.unwrap(stored[0].objectForKey(string($.kLSQuarantineAgentNameKey))) !== "OpenNoType Installer" ||
        ObjC.unwrap(stored[0].objectForKey(string($.kLSQuarantineTypeKey))) !== ObjC.unwrap(string($.kLSQuarantineTypeOtherDownload))) {
        throw new Error("Download quarantine metadata was not retained");
    }
}
JXA
then
    fail '다운로드 보안 속성을 기록하지 못했습니다.'
fi
xattr -p com.apple.quarantine "$STAGE_DIR/OpenNoType.app" >/dev/null 2>&1 || fail '다운로드 quarantine 속성이 확인되지 않습니다.'
if pgrep -x OpenNoType >/dev/null; then fail '앱 준비 중 OpenNoType이 실행되었습니다. 앱을 종료하고 다시 시도해 주세요.'; fi
if [[ -e "$APP_PATH" ]]; then
    mv "$APP_PATH" "$STAGE_DIR/previous.app" || fail '이전 앱을 안전하게 보관하지 못했습니다.'
    OLD_MOVED=1
fi
mv "$STAGE_DIR/OpenNoType.app" "$APP_PATH" || fail '새 앱으로 교체하지 못했습니다.'
NEW_MOVED=1
validate_app "$APP_PATH"
SUCCEEDED=1
printf '설치 완료: %s (%s)\n' "$APP_PATH" "$VERSION"
printf '%s\n' '앱을 열고 macOS의 앱별 허용·마이크·손쉬운 사용 안내를 따라 주세요. 설정·기록·Keychain 데이터는 변경하지 않았습니다.'
