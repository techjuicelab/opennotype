# GitHub Releases와 Sparkle 업데이트 운영

OpenNoType의 정식 배포는 `vX.Y.Z` 태그를 GitHub에 push하면 macOS 테스트, Developer ID 서명, Apple 공증, Sparkle 업데이트 서명·검증을 거쳐 GitHub Release를 공개하는 흐름이다. 업데이트 확인 주소는 `https://github.com/techjuicelab/opennotype/releases/latest/download/appcast.xml`로 고정하고, 실제 ZIP 주소는 해당 버전의 `/releases/download/vX.Y.Z/` 아래에 둔다.

2026-09-12 작업 시작 시 GitHub 저장소는 공개 상태였지만 Releases와 Actions Secrets는 각각 0개였다. 로컬에는 배포용 Developer ID가 없고 개발용 `TechJuice Local Code Signing`만 확인되었다. 워크플로 파일을 추가하는 것만으로 계정·키가 설정되거나 릴리스가 공개되지는 않는다. 실제 Developer ID 서명, Apple 공증, GitHub 공개, 다른 Mac에서의 Sparkle 교체까지는 첫 배포 후 별도로 확인해야 한다.

기존 `0.1.9 (10)` 개발 설치본에는 유효한 업데이트 피드와 공개 키가 없으므로 첫 정식 배포본을 한 번 내려받아 `/Applications/OpenNoType.app`으로 교체해야 한다. 이후부터 같은 앱에 포함된 피드와 공개 키로 업데이트를 받을 수 있다. 초기 지원 대상은 Apple silicon과 macOS 14 이상이다.

## 최초 설정

배포 운영자는 다음 값을 준비한다. Apple 인증서와 공증 자격은 Apple Developer 계정에서 발급·관리하고, Sparkle 키는 해당 앱을 위해 한 번 준비한 뒤 안전하게 보관한다. 이 저장소에는 개인 키를 생성하거나 비밀을 GitHub에 등록하는 자동 작업이 없다.

| 저장 위치 | 이름 | 내용 |
| --- | --- | --- |
| GitHub Actions Secret | `DEVELOPER_ID_P12_BASE64` | 개인 키가 포함된, 비밀번호로 보호된 Developer ID Application P12 파일의 base64 배포 복사본 |
| GitHub Actions Secret | `DEVELOPER_ID_P12_PASSWORD` | 해당 P12의 비어 있지 않은 비밀번호 |
| GitHub Actions Secret | `APPLE_NOTARY_KEY_P8` | 공증에 사용할 App Store Connect 팀 API 키의 원래 PEM 텍스트 |
| GitHub Actions Secret | `SPARKLE_PRIVATE_KEY` | Sparkle `generate_keys`가 내보낸 base64 Ed25519 개인 키 텍스트 |
| GitHub Actions Variable | `DEVELOPER_ID_APPLICATION` | `Developer ID Application: 이름 (TEAMID)` 형식의 정확한 공개 인증서 identity |
| GitHub Actions Variable | `APPLE_NOTARY_KEY_ID` | 위 팀 API 키의 공개 Key ID |
| GitHub Actions Variable | `APPLE_NOTARY_ISSUER` | 위 팀 API 키의 공개 Issuer ID |
| GitHub Actions Variable 또는 추적 파일 | `SPARKLE_PUBLIC_ED_KEY` | 개인 키와 짝을 이루는 32바이트 base64 공개 키. 변수 대신 `Resources/UpdateChannel.plist`의 `SUPublicEDKey` 사용 가능 |

P12, P12 비밀번호, 공증 P8, Sparkle 개인 키의 원본과 회전 기록은 **1Password**에 둔다. GitHub Secrets는 CI 배포용 복사본이다. 개인 키·비밀번호를 Git, 이슈, PR, 채팅, 명령행 인자 또는 로그에 넣지 않는다. 값을 등록할 때는 1Password에서 실행 시 주입해 표준 입력으로 전달하거나 승인된 관리 UI를 사용한다. 실제 값을 담은 `.env` 파일을 추적하지 않는다. 비밀 파일이 도구 입력에 필요하면 권한 `0600`으로 만들고 사용 즉시 제거한다.

`APPLE_NOTARY_ISSUER`를 쓰는 이 워크플로는 App Store Connect **팀 API 키** 계약이다. 다른 인증 방식으로 바꾸려면 워크플로와 운영 문서를 함께 검토한다. 앱별 비밀번호를 `--password`에 직접 전달하는 경로는 제공하지 않는다.

GitHub 공식 인증서 예시는 `security import -P`에 P12 비밀번호를 넘기지만, 이 저장소는 `scripts/import-release-certificate.swift`가 비밀번호를 환경에서 읽어 Security API에 메모리로 전달한다. CI 전용 임시 keychain은 권한 `0700` 폴더 안에서 비어 있는 비밀번호로 만들며, P12 원본의 비밀번호 보호는 유지한다. 이 때문에 partition ACL의 `-k ''`에는 실제 비밀 값이 들어가지 않는다. 개인 키 파일, 임시 keychain, 기존 keychain 검색 목록은 `always()` 단계에서 삭제·복원한다. 강제 러너 종료 시에는 GitHub 호스팅 러너의 폐기에도 의존하므로 이 워크플로를 장기 실행 self-hosted 러너로 그대로 옮기지 않는다.

기본 구성은 repository Secrets/Variables를 사용하며 이름을 추측한 GitHub Environment를 만들거나 승인 대기를 추가하지 않는다. 조직에서 보호된 배포 환경이 필요하면 관리자가 먼저 환경과 `v*` 태그 허용 규칙을 만들고, 비밀을 사용하는 `build` job에 해당 `environment`를 명시한다. 환경의 승인 정책을 켜면 태그 자동 실행이 그 승인에서 대기한다. 키 발급과 저장소 쓰기 권한을 가진 사람은 배포할 코드를 바꿀 수 있으므로 `main`과 `v*` 태그에 적절한 저장소 규칙을 설정한다.

## 배포 전 준비와 실행

1. 기능 변경을 검토하고 `Resources/Info.plist`의 `CFBundleShortVersionString`을 정식 `X.Y.Z`로, `CFBundleVersion`을 이전보다 큰 양의 정수 문자열로 올린다. 예를 들어 최초 `0.1.9 (10)` 이후에는 버전과 빌드 번호 모두 증가시킨다.
2. 릴리스 워크플로를 포함한 변경을 `main`에 반영하고 일반 CI를 확인한다. 릴리스 태그는 원격 `main`에 포함된 커밋이어야 한다.
3. plist 버전과 정확히 같은 `vX.Y.Z` 태그를 만든 뒤 해당 태그를 push한다. 공개된 태그를 이동하거나 기존 Release의 파일을 덮어쓰지 않는다.
4. GitHub Actions의 `Publish signed stable release`를 확인한다. 필요한 비밀이 누락되면 공개 전에 실패한다. API 오류를 첫 배포의 빈 릴리스 목록으로 취급하지 않는다.

로컬에서 `scripts/package-release.sh`를 실행할 경우 `dist`는 비어 있어야 한다. 이전 배포 또는 실패한 시도의 산출물은 별도 보관 폴더로 옮긴 뒤 다시 실행한다. 기존 파일은 자동 삭제하지 않으며, 파일이 남아 있으면 빌드·공증 전에 중단한다.

`v*` push가 실행 조건이지만 `v1.2`, `v01.2.3`, `v1.2.3-beta`, `v1.2.3+4`는 검사에서 거부한다. 릴리스 버전은 정식 세 자리 숫자 버전만 사용한다. 모든 공개 정식 릴리스보다 버전과 빌드가 커야 하며, 이전 정식 태그의 plist 빌드 번호도 초과해야 한다. 과거 릴리스에 빌드 메타데이터가 없으면 추측해서 공개하지 않는다.

## 공개까지의 검증 순서

| 단계 | 검사와 결과 |
| --- | --- |
| 소스 검사 | 태그와 plist 일치, 체크아웃과 태그 커밋 일치, `main` 포함 여부, 이전 태그·공개 릴리스보다 증가한 버전·빌드 |
| 테스트 | Xcode 26 선택 후 Swift 테스트와 Python 오프라인 배포 계약 테스트. 이 단계에는 서명 키를 주입하지 않음 |
| 배포 서명 | 임시 keychain으로 정확한 Developer ID identity 가져오기, Sparkle 내부 실행 파일부터 앱까지 서명 |
| Apple 공증 | 앱 ZIP 및 배포 DMG 공증, 티켓 부착·검증, Gatekeeper 평가. ZIP은 티켓이 부착된 앱에서 다시 생성 |
| Sparkle 검증 | 최종 ZIP 바이트로 Ed25519 서명 생성, 검증, 앱에 주입된 공개 키와의 짝 확인. 실패하면 공개용 산출물 완성 실패 |
| 산출물 검사 | 버전·빌드·주소·크기·해시·서명 메타데이터와 appcast의 일치, 예상한 파일 6개만 허용 |
| 비공개 업로드 | GitHub Release를 draft로 만들고 파일 업로드. 파일을 다시 내려받아 원래 산출물과 모든 SHA-256 비교 |
| 공개 | 직전에 공개 릴리스 목록을 재검사하고, 이번 실행에서 검증한 draft를 정식 최신 릴리스로 전환 |

워크플로 전체가 같은 concurrency group으로 직렬 실행되며 `cancel-in-progress: false`, `queue: max`를 사용한다. 실행 중인 배포를 새 태그 때문에 취소하지 않고 최대 100개 대기열을 허용한다. 실제 대기 진입 순서는 태그 버전 순서와 다를 수 있으므로 단조 증가 검사를 별도로 유지한다. 일반 테스트·서명 job에는 `contents: read`, 공개 job에만 `contents: write`를 부여한다. checkout은 Git 자격을 저장하지 않는다.

릴리스가 이미 있으면 공개·초안 여부와 무관하게 새 실행에서 덮어쓰지 않는다. 업로드 또는 재검증 중 실패하면 초안이 남을 수 있다. 운영자가 원인과 초안의 소유 실행을 확인한 뒤 그 미공개 초안을 삭제하고 실패한 워크플로를 재실행할 수 있다. 이미 공개된 릴리스는 수정 대신 버전·빌드를 올려 새로 배포한다. 수동 공개나 다른 워크플로는 이 concurrency group의 보호를 자동으로 받지 않으므로 정식 배포 경로를 하나로 유지한다.

## 배포 산출물

| 파일 | 용도 |
| --- | --- |
| `OpenNoType-X.Y.Z.zip` | Sparkle가 내려받는 최종 서명·공증 앱 ZIP |
| `OpenNoType-X.Y.Z.dmg` | 최초 설치와 수동 설치용 DMG |
| 위 두 파일의 `.sha256` | 파일명만 포함하는 이식 가능한 SHA-256 확인 파일 |
| `appcast.xml` | 현재 정식 버전 한 건을 가리키는 Sparkle 피드 |
| `release-metadata.json` | 공개 버전·빌드·ZIP 해시·크기·Ed25519 서명·공개 키·피드·최소 OS·아키텍처 |

이 버전은 전체 ZIP 업데이트를 제공한다. 델타 업데이트, 베타 채널, 여러 최소 OS 계열을 동시에 유지하는 피드, appcast 자체의 별도 서명은 구현 범위에 포함하지 않는다. ZIP의 Ed25519 서명과 앱의 Developer ID 서명은 검증하며, HTTPS GitHub 주소를 사용한다. 나중에 최소 OS를 올릴 경우 최신 항목 하나만 있는 피드는 이전 OS에 마지막 호환 버전을 제시하지 못하므로 그 전에 피드 보관 정책을 확장해야 한다.

## 첫 배포의 실제 확인

오프라인 테스트와 패키징 검사는 공개 경로와 사용자 기기의 실제 업데이트 성공을 대신하지 않는다. 첫 배포 운영자는 다음을 별도 기록한다.

- GitHub Release가 draft·prerelease가 아니며, ZIP·DMG·appcast·메타데이터가 모두 공개 다운로드되는지 확인한다.
- 인증되지 않은 상태에서 `releases/latest/download/appcast.xml`이 의도한 최신 버전과 고정 버전 ZIP URL을 제공하는지 확인한다.
- 첫 배포본을 설치한 Mac에서 앱의 업데이트 설정·현재 버전·업데이트 확인 동작을 확인한다.
- 다음 정식 버전에서 실제 다운로드, 검증, 교체, 재실행을 완료하고 기존 설정·기록·권한 유지 여부를 확인한다. 같은 공개 키와 서명 주체를 유지하더라도 macOS 권한 상태를 실제 기기에서 확인한다.
- 네트워크 오류, 없는 피드, 잘못된 서명, 최신 버전 상태를 사용자에게 구분해 알리는지 확인한다.

초기 코드 검증만 끝난 시점에는 마지막 두 버전 간 자동 교체가 아직 검증되지 않은 상태로 기록한다. Developer ID 또는 Sparkle 키를 회전할 때는 두 신뢰 근거를 동시에 바꾸지 않고 Sparkle의 공식 키 교체 절차를 따른다.

## 구현 검증 기록 (2026-09-12)

- `swift test`: 316개 중 314개 통과, 기존 선택 실행 통합 테스트 2개 제외, 실패 0개. 업데이트 상태·설정 보존·종료 차단·녹음 취소 후 재허용·Sparkle delegate 연결 검사를 포함한다.
- `SPARKLE_TEST_ARTIFACT_DIR`를 지정한 Python 배포 도구 테스트: 99개 모두 통과. 실제 Sparkle 2.9.6 도구와 공개 시험용 Ed25519 키로 appcast 생성·서명 검증·변조 거부를 확인했다. 출시용 개인 키는 사용하지 않았다.
- 임시 자기서명 P12 가져오기·무인 `codesign`·오류 시 삭제를 확인하고 기존 keychain 검색 목록을 복원했다. 실제 Developer ID 인증서의 신뢰 체인과 Apple 공증 검증은 아직 남아 있다.
- 워크플로 YAML·각 shell block·패키징 shell 구문 및 기존 `dist`를 공증 전에 거부하는 경계를 확인했다.
- 일반 push·pull request CI에서도 Swift 테스트 뒤에 Python 배포 계약 테스트와 실제 Sparkle 시험키 연동 검사를 실행한다. 배포용 비밀 설정 없이도 이 경로를 검증할 수 있다.
- 별도 debug 미리보기 앱에서 `설정 › Mac·일반 › 앱 업데이트`의 버전·확인 버튼·자동 확인·준비 상태 안내 배치를 확인했다. 미리보기는 업데이트 서버에 연결하지 않는다.
- debug 및 최적화 release 앱 빌드와 기존 로컬 개발 인증서의 `codesign --verify --deep --strict` 검증을 통과했다. 개발 빌드에서는 공개 키가 비어 있으면 피드도 번들에 넣지 않는 것을 확인했다.
- 실제 GitHub Actions 실행·공개 릴리스 다운로드·버전 간 앱 교체는 자격 설정과 첫 배포 후 확인할 항목이다. 현재 사용하는 `0.1.9 (10)` 설치본은 이 작업에서 교체하지 않았다.

## 공식 근거

- [Sparkle 업데이트 게시와 버전·빌드·아키텍처](https://sparkle-project.org/documentation/publishing/): ZIP 보관, Ed25519 서명, appcast 항목 구조와 내부 빌드 번호.
- [Sparkle 초기 설정과 공개 키](https://sparkle-project.org/documentation/): `SUPublicEDKey`, 키 보관·이동과 키 교체 조건.
- [Apple: Identity 가져오기](https://developer.apple.com/documentation/security/importing-an-identity): 비밀번호로 보호된 PKCS #12와 Security API의 passphrase 전달.
- [Apple: 공증 워크플로](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow): `notarytool`, 공증 자격과 티켓 부착.
- [GitHub: macOS 러너에서 Apple 인증서 설치](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications): CI 배포 복사본과 임시 keychain 운영.
- [GitHub: 비밀 사용](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets): 최소 범위 주입과 로그·명령행 노출 방지.
- [GitHub: concurrency 제어](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency): `queue: max`, 취소와 대기열 동작.
- [GitHub Releases API](https://docs.github.com/en/rest/releases/releases): 초안·정식·최신 릴리스 상태 및 자산 목록.

공식 문서 확인일: 2026-09-12. 문서의 제품 기능 설명과 이 저장소에서 실제 실행한 검증 결과는 구분해서 기록한다.
