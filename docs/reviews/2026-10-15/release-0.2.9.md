# OpenNoType 0.2.9 (45) 배포·설치 검증

2026-10-15 사용자 요청에 따라 **0.2.9 (45)**로 올려 이 Mac 설치, main 커밋·푸시, `v0.2.9` 공개 Latest 배포를 완료했다. 메인 포함 4개 에이전트의 실제 병렬 작업과 독립 검토 결과를 기록한다.

## 배포 범위

기존 미커밋 기능 개선과 옵션별 도움말 UI를 함께 포함한다. 메인과 서브에이전트 3개가 변경 완결성, 배포·다운로드 경로, 서명·사용자 데이터 보존을 실제 병렬로 검토했다. 기본 설정·실험 기능의 기본 꺼짐을 유지한다.

- 버전: `0.2.9 (45)`, 태그: `v0.2.9`.
- 작업 시작 소스: `f223adc544dc9e69dbb91e10627782538054d29b`.
- 이전 공개 Latest: `v0.2.3 (35)`.
- 이전 설치 앱: `/Applications/OpenNoType.app`, `0.2.8 (44)`.
- 작업 전 소스 보존 사본: `/Users/techjuice/Documents/Codex/Backups/OpenNoType/2026-10-15-release-0.2.9-072219/`.
- 공개 배포: 기존 community(ad-hoc 앱 서명·Sparkle Ed25519 업데이트 서명), Apple 공증 없음, arm64·macOS 14 이상.
- 이 Mac 설치: 기존 `TechJuice Local Code Signing` identity 유지. 공개 자산과 로컬 설치 앱은 서명이 다르며 동일 소스·버전의 산출물로 각각 검증한다.
- 로컬 설치품과 공개 CI 산출물은 빌드 환경과 서명이 다르므로 바이너리 동일성을 주장하지 않는다. 공개 ZIP·DMG 사이의 파일 트리 일치는 별도로 검증했다.
- 추적된 공개 업데이트 키는 이전 공개 릴리스와 GitHub Variable에서 확인한 동일 키이다. 개인 키를 읽거나 새로 발급하지 않는다.

## 완료 상태와 테스트

로컬 Swift 테스트는 Platform 581개·Core 638개, 합계 **1,219개 통과 / 모델 통합 선택 실행 2개 제외 / 실패 0개**다. Python 배포 계약 테스트 **209개**도 통과했다. 원격 main·태그 CI와 공개 배포 워크플로도 성공했다. 실제 설치 앱, 보존 데이터, 익명 공개 다운로드까지 각기 확인했다.

## 검증 경계

VoiceOver 음성 낭독, 새 Mac의 최초 Gatekeeper 허용, 실물 마이크·자연 한영 혼용 정확도, 모든 외부 앱의 자동 입력, Intel 지원을 검증한 것으로 확대하지 않는다. 이 Mac의 로컬 인증서 유지 설치는 공개 ad-hoc 빌드의 실기기 Sparkle 교체 성공과 별개다.

## 이 Mac 설치 결과

- `CONFIGURATION=release DEVELOPMENT_SIGNING_IDENTITY='TechJuice Local Code Signing' scripts/build-app.sh`로 빌드하고 strict 코드 서명을 검증했다.
- 이전 앱과 새 앱의 designated requirement는 같은 leaf 인증서 `009d748a8eae4491a615a4d80edf8c7f89d89243`로 일치한다. Bundle ID와 arm64를 유지했다.
- 기존 PID `1194`를 정상 종료하고, 사용자 데이터의 최신 보존 사본을 만든 뒤 같은 파일시스템의 staging에서 앱을 교체했다.
- 새 PID `37769`의 실행 경로는 `/Applications/OpenNoType.app/Contents/MacOS/OpenNoType`이며, 설치 실행 파일은 빌드한 실행 파일과 SHA-256이 같다.
- 네이티브 UI에서 `0.2.9 (45)`, 새 옵션 도움말 열기·Escape·포커스 복원, 마이크와 손쉬운 사용 `허용됨`을 확인했다.
- 공개 후 앱의 `업데이트 확인…`을 실행했고 마지막 확인 시각이 오전 7:46으로 갱신되며 기존 오류 문구가 사라진 것을 확인했다. 이는 업데이트 확인 UI 관측이며, 실제 Sparkle 앱 교체 시험은 아니다.
- Application Support의 **146개 파일**은 변경·추가·삭제 없이 해시가 같다. 모델과 암호화 vault도 포함한다.
- `preferences.v1`, `preferences.v1.last-known-good`는 JSON 재직렬화로 바이트 순서가 달라졌지만 디코딩한 내용은 완전히 같다. 추가·삭제·변경된 설정 필드는 없다. 창 위치와 Sparkle 첫 실행·확인 시각 메타데이터만 별도로 변했다.
- 이전 앱은 작업 전 백업과 `/Applications/.opennotype-0.2.9-967dtctp/previous.app`에 보존했다.
- API 요청·실제 녹음·외부 앱 입력은 수행하지 않았다. 새 앱의 저장 키 표시는 Groq·TypeSafe 준비, OpenRouter 미등록이다. Keychain 값은 직접 읽거나 저장·삭제하지 않고 항목 존재 메타데이터만 확인했다. 실제 연결 성공으로 확대하지 않는다.

실행 파일 SHA-256: `2dc27fe5bf6807b58ee6c2bb5efd9afcf18dcdbdfaed85e6218663026d9867f3`.

## 원격 배포와 다운로드 검증

배포 소스 커밋은 `0e659046cf62575602e417581f2c7cc305b7e4aa`이며 main과 annotated `v0.2.9` 태그에 반영했다. 태그가 가리키는 실제 소스 SHA도 일치한다. 후속 검증 문서는 별도 커밋이며 배포 소스·Resources를 변경하지 않는다.

- [main Build and test](https://github.com/techjuicelab/opennotype/actions/runs/38647483596): 성공.
- [태그 Build and test](https://github.com/techjuicelab/opennotype/actions/runs/38648389498): 성공.
- [Publish verified stable release](https://github.com/techjuicelab/opennotype/actions/runs/38648389642): 성공. 배포 중에도 Swift 1,219개·Python 209개 통과, 선택 실행 2개 제외.
- 공개 시각: **2026-10-15 07:44:02 KST**, release ID `413247673`, draft·prerelease 모두 `false`.
- [Latest](https://github.com/techjuicelab/opennotype/releases/latest)는 [v0.2.9](https://github.com/techjuicelab/opennotype/releases/tag/v0.2.9)로 이동하고 [릴리스 목록](https://github.com/techjuicelab/opennotype/releases) 최상단에도 표시된다.
- ZIP·DMG·각 SHA-256 파일·`appcast.xml`·`release-metadata.json`, **총 6개**를 인증 없이 다운로드해 HTTP 200, 크기, API digest와 실제 SHA-256을 확인했다.
- ZIP Ed25519 서명과 기존 공개 `v0.2.3` 키 연속성, 양쪽 앱 strict 코드 서명, `0.2.9 (45)`·arm64·macOS 14·피드 설정을 확인했다.
- DMG를 실제 읽기 전용으로 마운트해 ZIP과 전체 **99개 파일·9개 링크·69개 디렉터리**의 내용·모드가 일치함을 확인하고 정상 해제했다. 소유자·타임스탬프·xattr은 비교 범위에서 제외했다.
- 공개 후 Latest 피드·메타데이터도 고정 버전 자산과 일치했다. 상세 해시·명령 결과·검증 경계는 [공개 자산 검증 JSON](release-0.2.9-verification.json)에 있다.
- 원격 README와 TechJuiceLab의 실제 배포 데이터는 모두 릴리스 목록을 다운로드 경로로 사용한다. 이미 그 목록의 최신 항목이 `v0.2.9`여서 사이트 코드 변경·재배포는 필요하지 않았다.

공개 자산 검증은 07:44:24~07:44:37 KST에 독립 에이전트가 수행했다. 다른 에이전트가 Latest·README·사이트 배포 데이터 경로를 독립 확인했고, 또 다른 에이전트가 설치 앱의 서명·프로세스·데이터 보존과 태그 소스를 재검토했다.
