#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PRINT_SDK=0
REQUIRE_TESTS=0
case "${1:-}" in
    '') ;;
    --print-sdk) PRINT_SDK=1 ;;
    --tests) REQUIRE_TESTS=1 ;;
    *) printf '%s\n' '사용법: scripts/macos-preflight.sh [--print-sdk | --tests]' >&2; exit 1 ;;
esac
for tool in swiftc xcrun xcode-select; do
    command -v "$tool" >/dev/null || { printf '소스 빌드에 필요한 %s가 없습니다. Xcode 또는 Swift 6 Command Line Tools를 설치해 주세요.\n' "$tool" >&2; exit 1; }
done
SWIFT_MAJOR="$(swiftc --version 2>/dev/null | sed -n 's/.*Swift version \([0-9][0-9]*\).*/\1/p' | head -n 1)"
if [[ ! "$SWIFT_MAJOR" =~ ^[0-9]+$ ]] || [[ "$SWIFT_MAJOR" -lt 6 ]]; then
    printf '%s\n' 'Swift 6 이상이 필요합니다. 현재 선택된 Swift 도구를 확인해 주세요.' >&2
    exit 1
fi
PROBE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/opennotype-sdk-probe.XXXXXX")"
trap 'rm -rf "$PROBE_DIR"' EXIT
show_diagnostic() {
    # Keep actionable compiler errors on screen; full compiler output can be long.
    if ! awk '/error:/ { print; count++; if (count == 3) exit } END { exit (count == 0) }' "$1" >&2; then
        sed -n '1,4p' "$1" >&2
    fi
}
compile_sdk() {
    swiftc -swift-version 5 -target arm64-apple-macos14.0 -sdk "$1" -parse-as-library \
        -emit-object "$SCRIPT_DIR/probes/build-sdk.swift" -o "$PROBE_DIR/build.o" >"$PROBE_DIR/build.log" 2>&1
}
if [[ -n "${MACOS_SDK_PATH:-}" ]]; then
    SELECTED_SDK="$MACOS_SDK_PATH"
    [[ -d "$SELECTED_SDK" ]] || { printf '지정한 SDK가 없습니다: %s\n' "$SELECTED_SDK" >&2; exit 1; }
    if ! compile_sdk "$SELECTED_SDK"; then
        printf '지정한 SDK에서 SwiftUI/Observation 컴파일이 실패했습니다: %s\n' "$SELECTED_SDK" >&2
        show_diagnostic "$PROBE_DIR/build.log"
        printf '%s\n' 'MACOS_SDK_PATH를 명시했으므로 다른 SDK로 바꾸지 않았습니다.' >&2
        exit 1
    fi
else
    DEFAULT_SDK="$(xcrun --sdk macosx --show-sdk-path)"
    [[ -d "$DEFAULT_SDK" ]] || { printf '%s\n' 'macOS SDK 경로를 찾을 수 없습니다.' >&2; exit 1; }
    SELECTED_SDK="$DEFAULT_SDK"
    if ! compile_sdk "$DEFAULT_SDK"; then
        printf '기본 SDK에서 SwiftUI/Observation 컴파일이 실패했습니다: %s\n' "$DEFAULT_SDK" >&2
        show_diagnostic "$PROBE_DIR/build.log"
        FALLBACK_SDK="$(dirname "$DEFAULT_SDK")/MacOSX26.5.sdk"
        if [[ "$FALLBACK_SDK" != "$DEFAULT_SDK" && -d "$FALLBACK_SDK" ]] && compile_sdk "$FALLBACK_SDK"; then
            SELECTED_SDK="$FALLBACK_SDK"
            printf '실제 컴파일을 통과한 SDK를 선택했습니다: %s\n' "$SELECTED_SDK" >&2
        else
            printf '%s\n' '사용 가능한 SDK로 SwiftUI/Observation을 컴파일하지 못했습니다. Xcode/Command Line Tools 업데이트와 xcode-select 경로를 확인해 주세요.' >&2
            show_diagnostic "$PROBE_DIR/build.log"
            exit 1
        fi
    fi
fi
DEVELOPER_DIR_PATH="$(xcode-select -p)"
# Test the host toolchain as swift test does, independently of the arm64 app target.
TEST_COMMAND=(swiftc -swift-version 5 -sdk "$SELECTED_SDK")
TEST_FRAMEWORKS="$DEVELOPER_DIR_PATH/Platforms/MacOSX.platform/Developer/Library/Frameworks"
[[ ! -d "$TEST_FRAMEWORKS" ]] || TEST_COMMAND+=(-F "$TEST_FRAMEWORKS")
TEST_LIBRARIES="$DEVELOPER_DIR_PATH/Platforms/MacOSX.platform/Developer/usr/lib"
# XCTest imports XCTestSwiftSupport from the platform's developer libraries.
[[ ! -d "$TEST_LIBRARIES" ]] || TEST_COMMAND+=(-I "$TEST_LIBRARIES")
if "${TEST_COMMAND[@]}" \
    -parse-as-library -emit-object "$SCRIPT_DIR/probes/xctest.swift" -o "$PROBE_DIR/tests.o" >"$PROBE_DIR/tests.log" 2>&1; then
    TEST_STATUS='XCTest import/컴파일 통과 — 전체 테스트 실행은 별도입니다.'
else
    TEST_STATUS='XCTest import/컴파일 실패 — 앱 빌드는 가능하지만 swift test에는 전체 Xcode가 필요할 수 있습니다.'
    printf '%s\n' "$TEST_STATUS" >&2
    if [[ "$REQUIRE_TESTS" -eq 1 ]]; then
        show_diagnostic "$PROBE_DIR/tests.log"
        printf '%s\n' '전체 Xcode를 설치·선택한 뒤 scripts/macos-preflight.sh --tests를 다시 실행해 주세요.' >&2
        exit 2
    fi
fi
if [[ "$PRINT_SDK" -eq 1 ]]; then
    printf '%s\n' "$SELECTED_SDK"
else
    printf '선택 SDK: %s\nSwiftUI/Observation 컴파일: 통과\n%s\n' "$SELECTED_SDK" "$TEST_STATUS"
fi
