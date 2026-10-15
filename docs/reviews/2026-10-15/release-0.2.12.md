# OpenNoType 0.2.12 (48) 검증 보고서

## 변경 범위

메인 포함 4개 에이전트가 실제 병렬로 공통 선택기와 상태·음성/문장 카탈로그와 가격·비교 화면·통합과 배포를 맡았다. 최근 미커밋 OpenAI 모델·요청 정책·가격 작업을 원본 백업 후 포함했다. [릴리스 노트](../../releases/v0.2.12.md), [카탈로그 근거](model-selection-0.2.12-catalog.md), [기존 OpenAI 작업 기록](openai-model-picker.md)을 참고한다.

## 검증 상태

- Swift 전체 검사: 플랫폼 609개 + Core 659개, 합계 1,268개 중 1,266개 통과·기존 opt-in 2개 제외·실패 0.
- Python 전체 배포/도구 검사: 209개 전부 통과. 실제 Sparkle 도구 경로를 지정했다.
- 첫 Python 검사에서 독립 비교 하네스의 명시적 소스 목록에 새 OpenAITextPolicy와 가격의 TextModelCatalog 의존성이 누락된 컴파일 오류를 확인했다. 두 비교 도구의 컴파일 목록을 연결하고 해당 20개와 전체 209개가 통과했다. 제품 요청 계약이나 검증 조건을 완화하지 않았다.
- 교차 리뷰에서 catalog 선택의 owner 저장 거절 후 메뉴 오표시 한 건과 기존 비교 모델 1개 저장 상태의 재열기 경계를 보완했다. 공통 선택 상태 16개·비교 행 바인딩 7개 테스트를 포함한다.
- 별도 DEBUG 합성 앱의 실제 창에서 OpenAI/Claude 목록과 마지막 Custom, 선택만으로 기존 ID 유지, 초안 미적용, Apply·Return 적용, 빈 값 차단, 제공자 전환, 외부 저장값 동기화, 잠금 시 menu/field/apply 비활성을 확인했다. 사용자 설정·키·유료 API와 분리된 로컬 상태로 검증했다.
- 온라인 음성은 파일 전사 지원 목록을 사용하고 토큰 가격을 표시하지 않는다. 로컬 음성·Jev 검토의 고정 지원 계약은 유지한다.

소스·설치·공개 배포·다운로드의 근거를 아래에서 구분한다. 소스 버전만으로 배포나 설치 완료를 판단하지 않는다.

## 소스·태그와 원격 검사

승인 소스는 `150878419e77819c8e6ca832c97e977d30b3a388`이며 main과 `v0.2.12` 태그를 푸시했다. 버전·build 증가·main 포함·이전 정식 배포 이력을 검사하는 release-preflight가 통과했다.

[main CI 38665561855](https://github.com/techjuicelab/opennotype/actions/runs/38665561855)와 [태그 CI 38665602345](https://github.com/techjuicelab/opennotype/actions/runs/38665602345)가 모두 성공했다. 두 실제 로그에서 Swift 1,268개 중 1,266개 통과·기존 opt-in 2개 제외·실패 0, Python 209개 전부 통과, 일반 앱과 별도 Prompt Test 앱 패키징·업로드 성공을 확인했다.

## 이 Mac 설치·실행

정상 대기 중이던 0.2.11 (47)을 종료하고 **설치 직전의 최신** 데이터 146개·665,677,804바이트를 별도 복사·전체 해시 대조했다. 기존 OpenAI 키도 존재하므로 과거 배포 백업 대신 이번 직전 상태를 기준으로 삼았다. `openAI`, `groq`, `anthropic`, `openRouter`, `typesafe` 5개 계정의 존재와 반환 코드만 조회했으며 키 값은 읽거나 출력하지 않았다.

기존 인증서의 designated requirement·entitlements와 후보가 같은지, strict 서명과 0.2.12 (48) 정보를 확인한 뒤 같은 볼륨에서 원자적으로 `/Applications/OpenNoType.app`을 교체했다. 기존 앱·rollback 사본을 보존했다. 로컬 release 빌드와 strict 코드 서명 검증은 성공했다.

실제 앱은 PID **39532**, `/Applications/OpenNoType.app/Contents/MacOS/OpenNoType`, SHA256 **d69e5f5b25f0a8b8d8ba63ae31d4c4be850e84b8042cd54db32012961716b89a**다. ps·lsof로 설치 경로의 바이너리가 실행 중임을 확인했다. 소스 provenance는 빌드 절차와 동결된 소스를 근거로 하며, 앱 바이너리에 커밋 SHA를 내장해 읽은 결과는 아니다.

최초 실행은 관리 창이 숨겨져 getApp timeout을 반환했으며 Finder에서 앱을 재열어 실제 창을 확인했다. macOS Keychain이 기존 암호화 기록을 여는 승인을 기다리는 상태를 SecItemCopyMatching 호출 스택으로 확인했다. 화면 도구가 SecurityAgent 조작을 허용하지 않아 사용자에게 직접 처리를 요청했고, 사용자가 승인 완료를 알렸다. 이후 앱 준비 배너가 사라지고 세 연결의 ‘API 키 저장됨’과 홈 ‘준비됨’을 확인했다. 에이전트는 Keychain ACL이나 시스템 보안 설정을 직접 수정하지 않았다. 사용자의 시스템 승인에 따른 ACL 변화 여부는 별도로 조사하지 않았다.

설치본의 음성 목록 끝 Custom, 비교의 기본 2행·선택 3행 추가/제거·닫기까지 실제 창에서 확인했다. 사용자에게 저장된 음성·문장 모델 설정은 바꾸지 않았고 녹음·비교 API 요청은 시작하지 않았다. 사용자 키와 분리된 합성 앱에서는 Apply·Return·초안·빈 값·제공자 전환·잠금 동작을 확인했다.

[독립 설치 검증](release-0.2.12-installation.json)은 설치 직전→복사 직후→준비 완료 후→실제 파일 재해시를 비교했다. **146개 경로·크기·SHA256 동일, 추가·삭제·변경 0개**다. 보호 설정 JSON 2개는 바이트 순서 변화와 의미를 구분했으며 의미가 동일했다. 창 위치·크기 메타데이터 1개만 바뀌었다. 5계정의 존재·반환 코드가 실제 재조회와 일치했고 키 값은 읽거나 출력하지 않았다. PID·설치 경로·실행파일 해시·strict 서명·기존 designated requirement·entitlements도 독립 확인했다. Keychain 값의 동일성이나 실제 API 인증 성공을 메타데이터만으로 증명한 것은 아니다.

## 공개 배포·기본 다운로드

[공개 배포 CI 38665602502](https://github.com/techjuicelab/opennotype/actions/runs/38665602502)의 build/release job이 모두 성공했다. 실제 로그에서 Swift 1,268개 중 1,266개 통과·기존 opt-in 2개 제외·실패 0과 Python 209개 전부 통과를 확인했다. 서명·패키징·태그/버전/이력 검증을 거친 후 자산을 다시 내려받아 업로드 전 원본과 바이트 대조하고 Latest로 공개했다.

**2026-10-15 01:35:50 UTC / 10:35:50 KST**에 [v0.2.12](https://github.com/techjuicelab/opennotype/releases/tag/v0.2.12)를 게시했다. release ID **413332017**, `draft=false`, `prerelease=false`다. 공개 자산 6개와 태그 소스 SHA가 승인 소스와 일치했다.

[익명 공개 자산 검증](release-0.2.12-verification.json)은 **01:36:59 UTC / 10:36:59 KST**에 전부 통과했다. 인증 없이 6개 자산의 HTTP 200·GitHub digest·크기·SHA256·별도 체크섬을 확인했다. ZIP Ed25519 서명과 v0.2.11→현재 공개 키 연속성, 앱·DMG strict 서명, community 계약을 확인했다. 공개 앱은 **0.2.12 (48), arm64, 최소 macOS 14.0**이며 Info.plist와 Mach-O를 모두 검사했다. ZIP과 읽기 전용 DMG의 트리는 파일 99개·링크 9개·루트 포함 디렉터리 69개가 일치했고 DMG를 정상 해제했다. 최신 피드·metadata가 고정 버전 자산과 같았다. 공개 증거의 로컬 검증 폴더 경로는 익명화하고 원본은 비공개 백업에 보존했다.

| 파일 | SHA256 |
| --- | --- |
| `OpenNoType-0.2.12.zip` | `e5d6c9980c7e4512e317ddbad37d7b4c7416e79c65dbb6a1638d2438cd52ba24` |
| `OpenNoType-0.2.12.dmg` | `95a10729233f47ed41168608560ee7e468b117821277f4f8dffc80aed36c84f4` |

[다운로드 경로 독립 검증](release-0.2.12-downloads.json)은 **01:36:51 UTC / 10:36:51 KST**에 12개 검사를 통과했다. [Latest](https://github.com/techjuicelab/opennotype/releases/latest)는 v0.2.12로 이동하며 [릴리스 목록](https://github.com/techjuicelab/opennotype/releases)의 첫 항목·Latest 표시도 v0.2.12다. 공식 사이트의 실제 SSR 주소와 배포 클라이언트 catalog는 같은 릴리스 목록을 가리킨다. 버전 고정 링크 없이 최신 버전이 기본 다운로드 진입 목록 최상단에 놓였으므로 사이트 변경·재배포는 필요 없었다. SSR 주소 텍스트, 로컬 CTA href 소스, 실제 배포 catalog는 구분해 검증했으며 모달 버튼을 실제 클릭한 검증은 아니다. 자산 6개 canonical URL도 익명 HEAD 200을 확인했다.

공개 community 패키지는 ad-hoc 앱 서명·Sparkle Ed25519 서명이며 Apple 공증은 없다. 이 Mac의 앱은 동일 소스·버전을 기존 로컬 인증서로 서명했다. 둘의 SDK·서명·바이너리 해시가 같다는 주장은 하지 않는다.

## 최종 문서 기록

검증 보고서·카탈로그 링크·증거 JSON·현재 설치/공개 안내만 문서 커밋으로 정리한다. 태그 이후 Sources·Resources·빌드/배포 스크립트·Package·워크플로 차이가 없음을 확인한다. 앱 검사 근거는 위 소스/태그/공개 배포 CI이며 문서 전용 기록에는 `[skip ci]`를 사용한다. 문서 커밋의 앱 CI를 통과했다고 표시하지 않는다.

## 검증 경계

실제 유료 API·음성 인식 정확도·모든 외부 앱 입력·새 Mac Gatekeeper·Intel·VoiceOver 전수 검증은 이번 모델 선택 정비 범위에 포함하지 않는다. 사용자 키 값은 읽거나 출력하지 않는다. 공개 community 산출물은 ad-hoc 앱 서명·Sparkle Ed25519 서명이며 Apple 공증은 없다. 이 Mac에는 권한 연속성을 위해 동일 소스·버전을 기존 로컬 인증서로 서명해 설치한다. 공개·로컬 바이너리 해시가 같다는 주장은 하지 않는다.
