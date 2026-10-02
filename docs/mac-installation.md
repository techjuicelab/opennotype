# 새 Mac 설치와 빌드 사전 점검

일반 사용자는 공개 릴리스 앱을 설치하면 됩니다. Apple Silicon(M1 이상)과 macOS 14 이상을 지원하며, 설치에는 Xcode·Homebrew·Python·Swift가 필요하지 않습니다. Rosetta에서 실행한 터미널도 실제 하드웨어의 `hw.optional.arm64` 값을 확인합니다.

## 공식 릴리스 설치

저장소가 있으면 다음 명령으로 먼저 다운로드와 앱 검증만 할 수 있습니다. 실행 중인 앱과 설치 폴더는 변경하지 않습니다.

```bash
scripts/install-release.sh --verify-only
```

설치할 때는 OpenNoType을 종료한 뒤 실행합니다. 기본 위치는 `/Applications/OpenNoType.app`입니다.

```bash
scripts/install-release.sh
```

`/Applications`에 쓰기 권한이 없는 계정은 자신의 Applications 폴더를 사용합니다. 스크립트는 `sudo`를 실행하거나 권한을 바꾸지 않습니다.

```bash
mkdir -p "$HOME/Applications"
scripts/install-release.sh --destination "$HOME/Applications"
```

Git이나 저장소 없이 설치하려면 단독 shell 파일을 내려받아 같은 옵션으로 실행할 수 있습니다. 이 파일에 필요한 quarantine 처리가 포함되어 있습니다.

```bash
OPENNOTYPE_INSTALL_SCRIPT="$(mktemp -t opennotype-installer)"
curl --fail --location --proto '=https' --proto-redir '=https' \
  https://raw.githubusercontent.com/techjuicelab/opennotype/main/scripts/install-release.sh \
  -o "$OPENNOTYPE_INSTALL_SCRIPT"
bash "$OPENNOTYPE_INSTALL_SCRIPT" --verify-only
bash "$OPENNOTYPE_INSTALL_SCRIPT"
rm "$OPENNOTYPE_INSTALL_SCRIPT"
```

`--destination`은 이미 준비된 폴더의 절대 경로를 받으며, `--help`로 옵션을 확인할 수 있습니다. 사용자 폴더에 설치한 경우 마지막 명령에도 `--destination "$HOME/Applications"`을 붙입니다.

2026-10-01 확인 당시 공개 최신 릴리스는 `v0.1.10`입니다. 설치 스크립트는 실행 당시 GitHub에 공개된 최신 정식 릴리스를 설치합니다. 현재 소스의 입력·첫 실행·AI 제공자 분리 개선은 해당 공개 ZIP에 포함되어 있지 않으며, 새 릴리스가 공개되어야 이 경로로 받을 수 있습니다. 이미 설치된 앱의 버전이 공개 릴리스보다 높거나 같은 버전의 build 번호가 높으면 교체를 거부합니다.

현재 수정본의 소스 버전은 `0.1.17 (19)`입니다. 같은 녹음에서 이름 뒤에 읽은 영문 철자를 하나의 이름으로 정리하도록 개선했습니다. 예를 들어 `제브 제이 이 브이`를 `JEV`로 정리합니다. [문장 정리 검증과 한계](reviews/2026-10-01/spoken-spelling.md)를 참고하세요. 0.1.16의 문장 모델 비용순 정렬, 0.1.15의 Jev 표기 제안 저장·되돌리기·명시적 재검토와 0.1.14의 영어 기본 화면·한국어 선택도 포함합니다. 기존 커뮤니티 ad-hoc 서명 방식을 유지하며, 이번 작업에서는 Developer ID 서명과 Apple 공증을 진행하지 않습니다.

## 설치 스크립트가 확인하는 것

- 공식 `techjuicelab/opennotype`의 최신 정식 릴리스와 고정 버전 자산 주소
- ZIP의 SHA-256과 ZIP 내부 경로
- `app.opennotype.mac` bundle ID, 릴리스 버전, 양의 정수 build 번호, 최소 macOS 버전
- arm64 Mach-O 실행 파일과 `codesign --verify --deep --strict` 결과
- 기존 앱과의 버전·build 비교 및 앱 교체 직전의 실행 상태

앱을 설치 폴더와 같은 파일 시스템에 준비하고 검증한 뒤 기존 앱을 잠시 보관합니다. 교체 또는 최종 검증이 실패하면 이전 앱을 복원합니다. 복원 자체가 실패하면 이전 앱의 백업 경로를 출력하고 보존합니다. 정상 설치 이후 발생하는 실행 문제까지 자동으로 되돌리는 기능은 아닙니다.

앱 bundle만 교체합니다. 사용자 설정·기록·저장된 녹음·Keychain은 읽거나 삭제하거나 이전하지 않습니다. 여러 Mac의 API 키와 macOS 권한은 각 Mac에서 설정합니다.

코드 서명 검사는 bundle의 무결성 검사입니다. Apple 공증이나 Developer ID 신원 검증 성공을 뜻하지 않습니다. 공개 릴리스의 `community`/`notarized` 구분은 [업데이트 배포 문서](updates.md)를 확인하세요. SHA-256 파일도 같은 GitHub 릴리스에서 받으므로 독립적인 배포자 인증을 대신하지 않습니다.

`curl`로 받은 앱에도 다운로드 quarantine을 부여합니다. [Foundation의 quarantine property](https://developer.apple.com/documentation/foundation/urlresourcevalues/quarantineproperties)와 공개 SDK의 `LSQuarantine.h` dictionary를 사용하며, 별도의 파일 metadata 처리만 실행합니다. 검증 범위는 `com.apple.quarantine` 속성과 agent/type 유지입니다. 다운로드·출처 URL도 dictionary에 전달하지만 macOS가 다시 읽을 때 생략할 수 있어 그 보존을 검증했다고 주장하지 않습니다. quarantine 제거, Gatekeeper 비활성화, TCC 초기화·허용, 앱 자동 실행은 하지 않습니다.

## 첫 실행에서 필요한 설정

설치한 앱을 직접 열고 macOS의 앱별 실행 허용 안내를 따르세요. 앱의 설정에서 마이크와 손쉬운 사용 상태를 확인하고 요청하세요. macOS 권한 화면에서 승인한 뒤 앱으로 돌아와 상태를 확인합니다. 필요하면 앱을 종료하고 다시 엽니다.

다른 Mac에 설치해도 권한은 자동으로 복사되지 않습니다. 같은 bundle ID라도 서명이 바뀐 개발 앱과 공개 앱을 교체하면 기존 권한이나 Keychain 접근 승인을 다시 확인해야 할 수 있습니다. 설치 스크립트는 이 승인을 우회하지 않습니다.

그다음 음성 인식·문장 정리 제공자와 해당 API 키를 설정하고, TextEdit의 빈 문서에서 짧게 녹음해 실제 입력을 확인하세요. 입력이 안 되면 앱의 입력 테스트와 진단 결과를 확인합니다. 마이크 녹음 성공만으로 손쉬운 사용을 통한 입력 성공까지 확인한 것은 아닙니다.

## 소스 빌드할 때

소스 빌드는 Swift 6 이상과 macOS SDK가 필요하고, 기존 빌드 스크립트의 Python 3도 필요합니다. 먼저 다음 사전 점검을 실행합니다.

```bash
scripts/macos-preflight.sh
CONFIGURATION=release scripts/build-app.sh
```

사전 점검은 프로젝트에서 사용하는 `@Observable`, `@Bindable`, `@State`를 포함한 작은 SwiftUI 파일을 실제로 컴파일합니다. 기본 SDK가 실패할 때만 설치되어 있는 SDK 26.5를 시도하고, 그 SDK도 실제 컴파일에 성공해야 선택합니다. SDK를 내려받거나 `xcode-select` 설정을 바꾸지 않습니다.

명시한 SDK는 자동으로 다른 SDK로 대체하지 않습니다.

```bash
MACOS_SDK_PATH=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk \
  CONFIGURATION=release scripts/build-app.sh
```

이 Mac의 macOS 27.0 / Swift 6.4 CLT에서는 기본 SDK의 `SwiftUIMacros.StateMacro` 구현을 찾지 못하는 오류를 재현했습니다. 설치된 SDK 26.5가 컴파일에 성공해 자동 선택되었고 release 앱 빌드도 성공했습니다. 이 결과가 다른 Swift/SDK 조합의 성공을 보장하지는 않으므로 사전 점검을 매번 실행합니다.

XCTest 사용 가능 여부는 별도로 컴파일해서 확인합니다.

앱의 SwiftUI 검사는 arm64 target을 사용하며, XCTest 검사는 `swift test`처럼 현재 Mac의 아키텍처를 사용합니다. 전체 Xcode가 선택되어 있으면 해당 MacOSX 플랫폼의 developer frameworks와 Swift 지원 모듈 경로를 함께 탐색합니다.

```bash
scripts/macos-preflight.sh --tests
swift test --sdk "$(scripts/macos-preflight.sh --print-sdk)"
```

CLT에서 `no such module 'XCTest'`이면 앱 빌드와 테스트 환경을 구분해야 합니다. 사전 점검의 일반 모드는 이를 안내하고 앱 빌드를 계속할 수 있지만, `--tests`는 종료 코드 2로 실패합니다. 전체 Xcode를 설치·선택한 뒤 다시 점검하세요. XCTest import가 성공해도 전체 테스트가 실행된 것은 아니며 `swift test` 결과를 따로 확인해야 합니다.

## 회귀 검증

개발용 Python 테스트는 네트워크·실제 앱 실행·키 접근 없이 합성 릴리스와 임시 폴더에서 설치 과정을 검증합니다. 다운로드·하드웨어·서명 검사 결과는 모의 도구이고, ZIP 추출·plist·파일 교체·quarantine은 실제 macOS 기본 도구를 사용합니다.

```bash
python3 -m unittest scripts/test_install_release.py scripts/test_macos_preflight.py -v
```

검증 대상에는 체크섬·bundle·아키텍처·서명 거부, 더 새 앱 보호, 준비 중 앱 실행 거부, 교체 실패 및 최종 검증 실패의 복원, Rosetta 하드웨어 판단, 실제 quarantine 속성, SDK의 실제 컴파일 결과에 따른 선택과 명시한 SDK 보존이 포함됩니다. 실제 공개 ZIP에는 `--verify-only`를 별도로 실행합니다. 이것은 앱 첫 실행·마이크 녹음·다른 앱에 입력·실제 API 동작 검증을 대신하지 않습니다.

## 화면 언어

0.1.14부터 새 설치의 기본 화면 언어는 영어입니다. **Settings → Mac & general → App language**에서 **한국어**를 선택하면 즉시 전환됩니다. 이전 버전의 저장된 설정은 한국어로 이어 받고, 명시한 언어는 다음 실행과 업데이트에도 보존합니다. 받아쓰기 내용이나 번역 대상 언어는 바뀌지 않습니다. macOS 자체 권한 알림은 시스템 언어를 따릅니다.
