# GitHub Releases와 Sparkle 업데이트 운영

OpenNoType은 `vX.Y.Z` 태그를 GitHub에 push하면 macOS 테스트, 선택한 방식의 앱 서명, Sparkle 업데이트 서명·검증을 거쳐 GitHub Release를 공개한다. 현재 `.github/workflows/release.yml`은 `RELEASE_SIGNING_MODE: community`를 명시한다. **커뮤니티 배포 · Apple 공증 없음**이 현재 배포 방식이며, Developer ID 없이 ad-hoc 코드 서명과 Sparkle Ed25519 서명을 사용한다.

업데이트 확인 주소는 `https://github.com/techjuicelab/opennotype/releases/latest/download/appcast.xml`로 고정하고, 실제 ZIP 주소는 해당 버전의 `/releases/download/vX.Y.Z/` 아래에 둔다. 커뮤니티 배포도 이 채널의 최신 버전으로 공개하므로 GitHub의 `prerelease`는 `false`이다. 여기서 정식 버전·Latest는 버전 형식과 업데이트 채널을 뜻하며 Apple 공증이나 전체 실사용 검증 완료를 뜻하지 않는다.

2026-09-12 작업 시작 시 GitHub 저장소는 공개 상태였지만 Releases와 Actions Secrets는 각각 0개였다. 이후 커뮤니티 배포용 Sparkle 키의 1Password 원본과 GitHub Secret·공개 키 Variable을 준비했다. Developer ID와 Apple 공증 자격은 준비하지 않았으며 커뮤니티 모드에서 요구하지 않는다. 키 준비와 워크플로 작성은 공개 배포·실제 업데이트 성공의 증거가 아니므로 아래 검증 기록과 구분한다.

기존 `0.1.9 (10)` 개발 설치본에는 유효한 업데이트 피드와 공개 키가 없으므로 첫 배포본을 한 번 내려받아 `/Applications/OpenNoType.app`으로 교체해야 한다. 새 배포본에는 이후 업데이트를 확인할 피드와 공개 키가 포함된다. 실제 버전 간 다운로드·교체·재실행은 별도 검증 대상이다. 초기 지원 대상은 Apple silicon과 macOS 14 이상이다.

## 커뮤니티 배포 설치

GitHub Release에서 DMG를 내려받고 앱을 Applications 폴더로 복사한 뒤 실행한다. Apple 공증을 받지 않은 앱이므로 macOS가 최초 실행을 차단할 수 있다. 출처와 내용을 확인하고 설치하기로 결정했다면 [Apple의 앱별 수동 허용 안내](https://support.apple.com/102445)에 따라 시스템 설정의 개인정보 보호 및 보안에서 해당 앱을 허용한다. 기기 관리 정책에 따라 사용자가 허용할 수 없는 환경도 있다.

기존 로컬 인증서에서 ad-hoc 서명으로 바뀌면 마이크·손쉬운 사용 권한과 Keychain 접근을 다시 허용해야 할 수 있다. 암호화 기록은 기존 Keychain 암호화 키가 필요하므로 접근 오류가 나면 원본 파일과 키를 유지한 채 확인한다. 기존 설정·기록·권한·Keychain 접근 유지와 다음 버전의 자동 교체는 아직 실기기 검증 전이다.

Sparkle는 기존 공개 키로 검증되는 Ed25519 업데이트와 유효한 ad-hoc 앱 서명을 허용한다. 이 서명은 업데이트 무결성 검증에 사용되며 Apple의 개발자 신원 확인·공증을 대신하지 않는다. [Sparkle 공식 검증 소스](https://github.com/sparkle-project/Sparkle/blob/2.9.0/Sparkle/SUUpdateValidator.m)

## 배포 방식 선택

| `RELEASE_SIGNING_MODE` | 앱 서명과 Apple 공증 | 필요한 비밀 |
| --- | --- | --- |
| `community` — 현재 워크플로 설정 | ad-hoc 코드 서명, Apple 공증·티켓 부착 없음 | Sparkle 개인 키 |
| `notarized` | Developer ID 코드 서명, 앱 ZIP·DMG 공증과 티켓 검증 | Sparkle 개인 키, Developer ID P12·비밀번호, 공증 P8 |

두 방식 모두 최종 ZIP의 Ed25519 서명과 앱 공개 키의 일치, 코드 서명 무결성, 버전 증가 및 공개 자산 검증을 통과해야 한다. 공증이 실패하면 배포를 중단하며 커뮤니티 모드로 자동 전환하지 않는다. 배포 방식을 바꾸려면 워크플로의 명시적 값을 코드 리뷰로 변경한다. 로컬 패키징에서 모드를 생략하면 기존 `notarized` 경로를 사용하므로 커뮤니티 배포는 반드시 `RELEASE_SIGNING_MODE=community`를 지정한다.

## 최초 설정

배포 운영자는 선택한 모드에 해당하는 값을 준비한다. Sparkle 키는 두 모드에서 필수다. Apple 인증서와 공증 자격은 `notarized`를 사용할 때만 Apple Developer 계정에서 발급·관리한다. 이 워크플로에는 개인 키를 생성하거나 비밀을 GitHub에 등록하는 자동 작업이 없다.

| 저장 위치 | 이름 | 필요 모드와 내용 |
| --- | --- | --- |
| GitHub Actions Secret | `SPARKLE_PRIVATE_KEY` | 두 모드 — Sparkle `generate_keys`가 내보낸 base64 Ed25519 개인 키 텍스트 |
| GitHub Actions Variable 또는 추적 파일 | `SPARKLE_PUBLIC_ED_KEY` | 두 모드 — 개인 키와 짝을 이루는 32바이트 base64 공개 키. 변수 대신 `Resources/UpdateChannel.plist`의 `SUPublicEDKey` 사용 가능 |
| GitHub Actions Secret | `DEVELOPER_ID_P12_BASE64` | `notarized`만 — 개인 키가 포함된, 비밀번호로 보호된 Developer ID Application P12 파일의 base64 배포 복사본 |
| GitHub Actions Secret | `DEVELOPER_ID_P12_PASSWORD` | `notarized`만 — 해당 P12의 비어 있지 않은 비밀번호 |
| GitHub Actions Secret | `APPLE_NOTARY_KEY_P8` | `notarized`만 — 공증에 사용할 App Store Connect 팀 API 키의 원래 PEM 텍스트 |
| GitHub Actions Variable | `DEVELOPER_ID_APPLICATION` | `notarized`만 — `Developer ID Application: 이름 (TEAMID)` 형식의 정확한 공개 인증서 identity |
| GitHub Actions Variable | `APPLE_NOTARY_KEY_ID` | `notarized`만 — 위 팀 API 키의 공개 Key ID |
| GitHub Actions Variable | `APPLE_NOTARY_ISSUER` | `notarized`만 — 위 팀 API 키의 공개 Issuer ID |

P12, P12 비밀번호, 공증 P8, Sparkle 개인 키의 원본과 회전 기록은 **1Password**에 둔다. GitHub Secrets는 CI 배포용 복사본이다. 개인 키·비밀번호를 Git, 이슈, PR, 채팅, 명령행 인자 또는 로그에 넣지 않는다. 값을 등록할 때는 1Password에서 실행 시 주입해 표준 입력으로 전달하거나 승인된 관리 UI를 사용한다. 실제 값을 담은 `.env` 파일을 추적하지 않는다. 비밀 파일이 도구 입력에 필요하면 권한 `0600`으로 만들고 사용 즉시 제거한다.

커뮤니티 모드는 Sparkle 개인 키만 임시 파일로 만들고 삭제한다. Apple 비밀을 확인·파일화하거나 keychain·공증 프로필을 만들지 않는다. `notarized` 모드에서 `APPLE_NOTARY_ISSUER`를 쓰는 경로는 App Store Connect **팀 API 키** 계약이다. 다른 인증 방식으로 바꾸려면 워크플로와 운영 문서를 함께 검토한다. 앱별 비밀번호를 `--password`에 직접 전달하는 경로는 제공하지 않는다.

`notarized` 모드에서 `scripts/import-release-certificate.swift`는 비밀번호를 환경에서 읽어 Security API에 메모리로 전달한다. CI 전용 임시 keychain은 권한 `0700` 폴더 안에서 비어 있는 비밀번호로 만들며, P12 원본의 비밀번호 보호는 유지한다. 이 때문에 partition ACL의 `-k ''`에는 실제 비밀 값이 들어가지 않는다. 두 모드의 개인 키 파일 및 공증 모드에서 만든 임시 keychain·검색 목록 변경은 `always()` 단계에서 삭제·복원한다. 강제 러너 종료 시에는 GitHub 호스팅 러너의 폐기에도 의존하므로 이 워크플로를 장기 실행 self-hosted 러너로 그대로 옮기지 않는다.

기본 구성은 repository Secrets/Variables를 사용하며 이름을 추측한 GitHub Environment를 만들거나 승인 대기를 추가하지 않는다. 조직에서 보호된 배포 환경이 필요하면 관리자가 먼저 환경과 `v*` 태그 허용 규칙을 만들고, 비밀을 사용하는 `build` job에 해당 `environment`를 명시한다. 환경의 승인 정책을 켜면 태그 자동 실행이 그 승인에서 대기한다. 키 발급과 저장소 쓰기 권한을 가진 사람은 배포할 코드를 바꿀 수 있으므로 `main`과 `v*` 태그에 적절한 저장소 규칙을 설정한다.

## 배포 전 준비와 실행

1. 기능 변경을 검토하고 `Resources/Info.plist`의 `CFBundleShortVersionString`을 정식 `X.Y.Z`로, `CFBundleVersion`을 이전보다 큰 양의 정수 문자열로 올린다. 예를 들어 최초 `0.1.9 (10)` 이후에는 버전과 빌드 번호 모두 증가시킨다.
2. 릴리스 워크플로를 포함한 변경을 `main`에 반영하고 일반 CI를 확인한다. 릴리스 태그는 원격 `main`에 포함된 커밋이어야 한다.
3. plist 버전과 정확히 같은 `vX.Y.Z` 태그를 만든 뒤 해당 태그를 push한다. 공개된 태그를 이동하거나 기존 Release의 파일을 덮어쓰지 않는다.
4. GitHub Actions의 `Publish verified stable release`를 확인한다. 선택한 모드에 필요한 비밀이 누락되면 공개 전에 실패한다. API 오류를 첫 배포의 빈 릴리스 목록으로 취급하지 않는다.

로컬에서 `scripts/package-release.sh`를 실행할 경우 `dist`는 비어 있어야 한다. 이전 배포 또는 실패한 시도의 산출물은 별도 보관 폴더로 옮긴 뒤 다시 실행한다. 기존 파일은 자동 삭제하지 않으며, 파일이 남아 있으면 빌드·공증 전에 중단한다.

`v*` push가 실행 조건이지만 `v1.2`, `v01.2.3`, `v1.2.3-beta`, `v1.2.3+4`는 검사에서 거부한다. 릴리스 버전은 정식 세 자리 숫자 버전만 사용한다. 모든 공개 정식 릴리스보다 버전과 빌드가 커야 하며, 이전 정식 태그의 plist 빌드 번호도 초과해야 한다. 과거 릴리스에 빌드 메타데이터가 없으면 추측해서 공개하지 않는다.

## 공개까지의 검증 순서

| 단계 | 검사와 결과 |
| --- | --- |
| 소스 검사 | 태그와 plist 일치, 체크아웃과 태그 커밋 일치, `main` 포함 여부, 이전 태그·공개 릴리스보다 증가한 버전·빌드 |
| 테스트 | Xcode 26 선택 후 Swift 테스트와 Python 오프라인 배포 계약 테스트. 이 단계에는 서명 키를 주입하지 않음 |
| 배포 서명 | `community`는 ad-hoc, `notarized`는 임시 keychain의 정확한 Developer ID identity로 Sparkle 내부 실행 파일부터 앱까지 서명·검증 |
| Apple 공증 | `notarized`에서만 앱 ZIP·배포 DMG 공증, 티켓 부착·검증, Gatekeeper 평가. ZIP은 티켓이 부착된 앱에서 다시 생성. `community`는 이 절차를 실행하지 않으며 공증 성공으로 표시하지 않음 |
| Sparkle 검증 | 최종 ZIP 바이트로 Ed25519 서명 생성, 검증, 앱에 주입된 공개 키와의 짝 확인. 실패하면 공개용 산출물 완성 실패 |
| 산출물 검사 | 선택한 배포 모드와 `distribution` 일치, 버전·빌드·주소·크기·해시·서명 메타데이터와 appcast의 일치, 예상한 파일 6개만 허용 |
| 비공개 업로드 | GitHub Release를 draft로 만들고 파일 업로드. 파일을 다시 내려받아 원래 산출물과 모든 SHA-256 비교 |
| 공개 | 직전에 공개 릴리스 목록을 재검사하고, 이번 실행에서 검증한 draft를 최신 릴리스로 전환. 제목·본문에 배포 방식을 명시하며 커뮤니티 배포는 Apple 공증 없음 표시 |

워크플로 전체가 같은 concurrency group으로 직렬 실행되며 `cancel-in-progress: false`, `queue: max`를 사용한다. 실행 중인 배포를 새 태그 때문에 취소하지 않고 최대 100개 대기열을 허용한다. 실제 대기 진입 순서는 태그 버전 순서와 다를 수 있으므로 단조 증가 검사를 별도로 유지한다. 일반 테스트·서명 job에는 `contents: read`, 공개 job에만 `contents: write`를 부여한다. checkout은 Git 자격을 저장하지 않는다.

릴리스가 이미 있으면 공개·초안 여부와 무관하게 새 실행에서 덮어쓰지 않는다. 업로드 또는 재검증 중 실패하면 초안이 남을 수 있다. 운영자가 원인과 초안의 소유 실행을 확인한 뒤 그 미공개 초안을 삭제하고 실패한 워크플로를 재실행할 수 있다. 이미 공개된 릴리스는 수정 대신 버전·빌드를 올려 새로 배포한다. 수동 공개나 다른 워크플로는 이 concurrency group의 보호를 자동으로 받지 않으므로 정식 배포 경로를 하나로 유지한다.

## 배포 산출물

| 파일 | 용도 |
| --- | --- |
| `OpenNoType-X.Y.Z.zip` | Sparkle가 내려받는 최종 서명 앱 ZIP. Apple 공증은 `notarized`에만 적용 |
| `OpenNoType-X.Y.Z.dmg` | 최초 설치와 수동 설치용 DMG |
| 위 두 파일의 `.sha256` | 파일명만 포함하는 이식 가능한 SHA-256 확인 파일 |
| `appcast.xml` | 현재 정식 버전 한 건을 가리키는 Sparkle 피드 |
| `release-metadata.json` | 공개 버전·빌드·ZIP 해시·크기·Ed25519 서명·공개 키·피드·최소 OS·아키텍처 및 `distribution` (`community` 또는 `notarized`) |

이 버전은 전체 ZIP 업데이트를 제공한다. 델타 업데이트, 베타 채널, 여러 최소 OS 계열을 동시에 유지하는 피드, appcast 자체의 별도 서명은 구현 범위에 포함하지 않는다. ZIP의 Ed25519 서명과 선택한 방식의 앱 코드 서명을 검증하며 HTTPS GitHub 주소를 사용한다. 나중에 최소 OS를 올릴 경우 최신 항목 하나만 있는 피드는 이전 OS에 마지막 호환 버전을 제시하지 못하므로 그 전에 피드 보관 정책을 확장해야 한다.

## 첫 배포의 실제 확인

오프라인 테스트와 패키징 검사는 공개 경로와 사용자 기기의 실제 업데이트 성공을 대신하지 않는다. 첫 배포 운영자는 다음을 별도 기록한다.

- GitHub Release가 draft·prerelease가 아니며, ZIP·DMG·appcast·메타데이터가 모두 공개 다운로드되는지 확인한다.
- 인증되지 않은 상태에서 `releases/latest/download/appcast.xml`이 의도한 최신 버전과 고정 버전 ZIP URL을 제공하는지 확인한다.
- 첫 배포본을 설치한 Mac에서 앱의 업데이트 설정·현재 버전·업데이트 확인 동작을 확인한다.
- 다음 버전에서 실제 다운로드, 검증, 교체, 재실행을 완료하고 기존 설정·기록·마이크·손쉬운 사용 권한·Keychain 접근 유지 여부를 확인한다. 같은 Sparkle 공개 키를 유지해도 ad-hoc 빌드의 앱 신원 변화가 권한에 미치는 영향은 실제 기기에서 확인한다.
- 네트워크 오류, 없는 피드, 잘못된 서명, 최신 버전 상태를 사용자에게 구분해 알리는지 확인한다.

초기 코드 검증만 끝난 시점에는 마지막 두 버전 간 자동 교체가 아직 검증되지 않은 상태로 기록한다. 커뮤니티 업데이트의 신뢰 연결에는 기존 앱의 Sparkle 공개 키가 필요하다. 개인 키를 잃으면 Developer ID의 동일 서명 주체를 이용한 대체 교체 경로도 없으므로 수동 재설치가 필요할 수 있다. 향후 Developer ID를 도입하거나 Sparkle 키를 회전할 때는 두 신뢰 근거를 동시에 바꾸지 않고 Sparkle의 공식 키 교체 절차를 따른다.

## 공증 경로의 초기 구현 검증 기록 (2026-09-12)

아래 수치는 커뮤니티 경로 추가 전 구현에 대한 기록이다. 신규 경로의 CI·패키징·공개·설치 결과로 재사용하지 않는다.

- `swift test`: 316개 중 314개 통과, 기존 선택 실행 통합 테스트 2개 제외, 실패 0개. 업데이트 상태·설정 보존·종료 차단·녹음 취소 후 재허용·Sparkle delegate 연결 검사를 포함한다.
- `SPARKLE_TEST_ARTIFACT_DIR`를 지정한 Python 배포 도구 테스트: 99개 모두 통과. 실제 Sparkle 2.9.6 도구와 공개 시험용 Ed25519 키로 appcast 생성·서명 검증·변조 거부를 확인했다. 출시용 개인 키는 사용하지 않았다.
- 임시 자기서명 P12 가져오기·무인 `codesign`·오류 시 삭제를 확인하고 기존 keychain 검색 목록을 복원했다. 실제 Developer ID 인증서의 신뢰 체인과 Apple 공증 검증은 아직 남아 있다.
- 워크플로 YAML·각 shell block·패키징 shell 구문 및 기존 `dist`를 공증 전에 거부하는 경계를 확인했다.
- 일반 push·pull request CI에서도 Swift 테스트 뒤에 Python 배포 계약 테스트와 실제 Sparkle 시험키 연동 검사를 실행한다. 배포용 비밀 설정 없이도 이 경로를 검증할 수 있다.
- 별도 debug 미리보기 앱에서 `설정 › Mac·일반 › 앱 업데이트`의 버전·확인 버튼·자동 확인·준비 상태 안내 배치를 확인했다. 미리보기는 업데이트 서버에 연결하지 않는다.
- debug 및 최적화 release 앱 빌드와 기존 로컬 개발 인증서의 `codesign --verify --deep --strict` 검증을 통과했다. 개발 빌드에서는 공개 키가 비어 있으면 피드도 번들에 넣지 않는 것을 확인했다.
- 위 초기 기록 시점에는 실제 GitHub Actions 실행·공개 릴리스 다운로드·버전 간 앱 교체를 확인하지 않았다. 현재 커뮤니티 경로의 실제 배포·설치 결과는 확인 후 별도 기록해야 한다. 이 문서 수정에서 기존 `0.1.9 (10)` 설치본은 교체하지 않았다.

## 커뮤니티 경로의 워크플로 검증 기록 (2026-09-12)

- YAML, shell block 14개와 내장 Python 구문, Apple 비밀을 사용하는 단계의 `notarized` 조건을 확인했다.
- 실제 비밀 대신 단순 시험 문자열과 임시 폴더를 사용한 오프라인 검사 8개를 통과했다. 모드 허용·거부, 필수 값 누락, Sparkle 파일만 생성·권한 `0600`·삭제, Apple 값 누락 거부, 두 모드의 제목·여러 줄 본문, 모드와 메타데이터 불일치 시 공개 명령 미실행을 확인했다.
- 릴리스 명령은 네트워크를 호출하지 않는 시험용 대체 명령으로 검사했다. `--notes-file`로 안내문을 전달하고 `--generate-notes`를 한 번 추가하는 실제 CLI 동작은 [GitHub CLI 공식 소스](https://github.com/cli/cli/blob/v2.100.0/pkg/cmd/release/create/create.go)와 대조했다.
- 이 검사는 실제 앱 패키징·GitHub 공개·다른 Mac의 설치·두 버전 간 Sparkle 교체를 실행한 결과가 아니다. 해당 결과는 배포 후 별도 확인해야 한다.

## 커뮤니티 경로의 로컬 실행 검증 기록 (2026-09-12)

커뮤니티 구현의 로컬 실행 검증(2026-09-12): Swift 317개 중 315개 통과·기존 선택 실행 2개 제외, Python 배포 검사 115개 통과. 최적화 앱 빌드와 코드 서명, 별도 미리보기의 `0.1.10 (11)`·`커뮤니티 배포 · Apple 공증 없음` 표시를 확인했다. 실제 runtime 플래그가 있는 시험 앱을 커뮤니티 방식으로 다시 서명해 플래그 제거와 Sparkle 로드를 검증했다. 메타데이터·appcast의 고정 버전 URL 변조 거부 검사도 포함한다.

[`scripts/sparkle-harness`](../scripts/sparkle-harness/README.md)의 공개 시험 키·임의 bundle ID·localhost 피드로 실제 Sparkle 2.9.6의 다운로드, Ed25519 검증, 시험 호스트 1→2 교체, 별도 드라이버 종료·재실행을 확인했다. 서명 뒤 ZIP을 변조한 경우에는 설치가 거부되고 호스트 빌드 1이 유지됐다. 시험 프로세스와 서버를 종료하고 시험 ID의 설정·캐시만 정리했다. 이 결과는 실제 OpenNoType 공개 ZIP이나 기존 사용자 기록·권한·Keychain의 버전 간 이전 검증을 대신하지 않는다.

## 공식 근거

- [Sparkle 업데이트 게시와 버전·빌드·아키텍처](https://sparkle-project.org/documentation/publishing/): ZIP 보관, Ed25519 서명, appcast 항목 구조와 내부 빌드 번호.
- [Sparkle 초기 설정과 공개 키](https://sparkle-project.org/documentation/): `SUPublicEDKey`, 키 보관·이동과 키 교체 조건.
- [Sparkle 2.9 검증 소스](https://github.com/sparkle-project/Sparkle/blob/2.9.0/Sparkle/SUUpdateValidator.m): 기존 Ed25519 공개 키를 유지하는 업데이트와 유효한 ad-hoc 코드 서명 허용.
- [Apple: Mac에서 앱 안전하게 열기](https://support.apple.com/102445): 미확인·미공증 앱의 경고와 앱별 수동 허용 절차.
- [Apple: macOS 코드 서명 정책](https://developer.apple.com/library/archive/technotes/tn2206/_index.html): 코드 서명 요구사항과 Keychain 접근 제어의 관계.
- [Apple: Identity 가져오기](https://developer.apple.com/documentation/security/importing-an-identity): 비밀번호로 보호된 PKCS #12와 Security API의 passphrase 전달.
- [Apple: 공증 워크플로](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow): `notarytool`, 공증 자격과 티켓 부착.
- [GitHub: macOS 러너에서 Apple 인증서 설치](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications): CI 배포 복사본과 임시 keychain 운영.
- [GitHub: 비밀 사용](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets): 최소 범위 주입과 로그·명령행 노출 방지.
- [GitHub: concurrency 제어](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency): `queue: max`, 취소와 대기열 동작.
- [GitHub Releases API](https://docs.github.com/en/rest/releases/releases): 초안·정식·최신 릴리스 상태 및 자산 목록.

공식 문서 확인일: 2026-09-12. 문서의 제품 기능 설명과 이 저장소에서 실제 실행한 검증 결과는 구분해서 기록한다.
