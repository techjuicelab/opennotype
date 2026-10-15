# OpenNoType 0.2.10 (46) 전체 UI 재디자인·설치·배포 검증

2026-10-15 사용자 요청에 따라 전체 설계를 실제 SwiftUI에 적용하고 **0.2.10 (46)의 이 Mac 설치·main 커밋/푸시·공개 배포·Latest 및 기본 다운로드 전환을 완료했다.** 실제 구현·네이티브 화면·설치 보존·공개 배포 검증을 각각 구분해 기록한다.

## 기준과 보존

- 시작 HEAD: `d620ada3bf849f8ecae4948716089cedb08fa5a5`.
- 이전 설치·공개 Latest: `0.2.9 (45)` / `v0.2.9`.
- 기존 설계 산출물은 보존하고 함께 버전 관리한다.
- 작업 전 백업: `/Users/techjuice/Documents/Codex/Backups/OpenNoType/2026-10-15-redesign-0.2.10-082614`.
- 기존 소스·설치 앱·서명 requirement·entitlements·설정·Keychain 항목 존재 메타데이터·사용자 데이터 146개 파일을 보존했다. 실행 중 초기 사본과 실제 교체 직전의 최신 사본을 구분한다.
- 연결 항목 존재 메타데이터는 비공개 백업에 보관해 설치 전후 비교한다. 실제 키 값은 읽거나 저장·삭제하지 않는다.

## 실제 4개 병렬 구현

| 담당 | 구현 범위 |
|---|---|
| 메인 | 공통 DesignSystem·앱 셸·탐색·도움말·파일 추출·버전·통합·검증·설치·배포 |
| A `ux_primary_flow` | 홈·녹음/결과·프롬프트·검토/교정·이름 후보·HUD·부속 UI |
| B `ux_settings_architecture` | 전체 설정 6분류·모델·화자·연결·권한·예시·Jev 설정 |
| C `ux_visual_copy` | 기록·사전·복구·사용량·음성/문장 비교실 |

공유 파일 충돌을 피하려고 HomeView와 Jev 설정 구조체를 독립 파일로 추출한 뒤 각각 소유했다. 구현 후 다른 담당의 기능 보존·레이아웃을 교차 검토한다.

## 실제 적용 범위

공통 규격은 `DesignSystem.swift`에 모았다. 페이지 제목 22pt, 본문 13pt, 설명/보조 정보 12pt, 설정 기본 행 44pt, 상태 행 56pt, 일반 컨트롤 32pt, 주요 행동 36pt, 도움말 터치 영역 28pt, 패널 안쪽 여백 16pt, 패널 간격 16pt, 본문 여백 24pt를 사용한다. 기본 창은 1120×760pt, 최소 창은 960×680pt다.

- 셸: 사이드바 208pt·상단 도구막대 52pt, 현재 연결은 버튼에서 상세 확인. 복구는 기록의 탭으로 통합한다.
- 받아쓰기: 준비 상태 한 줄과 필요한 조치, 최근 결과, 단축키 행, 프롬프트 한 행. 일반 설명과 모델 상세는 도움말/접기로 옮긴다.
- 설정: 받아쓰기 / 녹음·단축키 / AI 연결 / 개인정보 / 앱 관리 / 고급 도구 6분류. 기본 받아쓰기 설정은 9개 행으로 묶고 모델·키·권한·예시·진단의 자세한 조작은 별도 창에서 제공한다.
- 기록: 검색·목록·선택 상세 구조. 원문 비교·검토·재처리는 선택 항목에 연결한다.
- 사전: 단어 목록을 우선하고 추가·수정은 편집 시트. 단어 / 교정 학습 / 이름 후보를 분리한다.
- 복구·사용량·모델·음성/문장 비교실·프롬프트·Jev 검토/교정·결과·HUD에도 공통 크기와 정보 우선순위를 적용한다.

`design/uiux/2026-10-15-redesign-v2/`와 ZIP은 구현 전 설계 스냅샷으로 보존한다. 그 안의 “앱을 변경하지 않는다”와 0.2.9 소스 기준은 설계 당시의 범위를 뜻한다. 후속 사용자 승인으로 진행한 실제 0.2.10 적용·설치·배포의 근거는 이 보고서다. 시안의 106개 화면/상태는 독립 SwiftUI 타입 106개를 추가했다는 뜻이 아니다.

## 구현 검증

컴파일·기존 테스트·실제 네이티브 화면·설치/보존·원격 CI·공개 다운로드를 각각 확인하고 아래에 기록했다. HTML 시안의 636 렌더 결과는 이번 네이티브 구현의 검증 결과로 재사용하지 않는다.

- 첫 통합 빌드에서 `UsageView`의 괄호 오류를 확인해 수정했고, 두 번째 통합 앱 빌드를 통과했다.
- Python 오프라인 배포/SDK 계약 테스트: **209개, 실패 0개**. 실제 Sparkle 테스트 도구를 지정했으며 출시용 개인 키는 로컬 테스트에 사용하지 않았다.
- Swift 테스트: **1,221개 중 1,219개 통과, 기존 선택형 2개 제외, 실패 0개**(Platform 581개 + Core 640개). UI 픽셀·실제 음성/API·모든 앱 입력 성공을 검증하는 테스트로 해석하지 않는다.
- 검증 후 남아 있던 설정 경로 문구 3개와 파일 끝 공백을 정리했다. 미리보기 패키징에서 앱을 다시 컴파일·서명했다.
- 최초 main 커밋 `90e124bbda0c3ab59ed90ce0d9eb0c0936ff02fa`를 푸시했다. [최초 CI](https://github.com/techjuicelab/opennotype/actions/runs/38655754901)는 테스트 기대값에 옛 “입력·단축키”가 남아 1개 실패했다. 동일 단일 테스트를 로컬에서 재현하고, 의도한 새 명칭 “녹음·단축키”로 기대 문자열만 갱신한 뒤 통과를 확인했다. 충돌 알림 한 번 표시·녹음 상태·무전송 검증은 유지한다.
- 실제 화면에서 기록/복구 본문 여백, 홈 단축키 행, 사용량 모델 행의 중복 간격을 추가 보완했다. 언어/표현 예시와 모델 다운로드의 주요 버튼도 공통 36pt 스타일로 맞췄다.
- 네이티브 QA·설치·원격 배포는 아래처럼 구분한다.

## 네이티브 화면 확인

별도 식별자 `app.opennotype.usage-preview`의 DEBUG 합성 앱에서 사용자 데이터·Keychain·녹음·API 전송 없이 확인했다. 실제 음성이나 Jev 품질을 평가한 결과가 아니다.

- 기록의 목록 선택에 따라 번역 결과·당시 출력 언어·원문이 같은 항목으로 바뀜을 확인했다. 원문에만 있는 단어 검색은 1개, 없는 검색어는 0개, 검색 지우기로 목록이 복귀했다.
- 사전 목록 8개, 단어 편집 시트의 올바른 쌍과 길이 표시, 미리보기의 저장/삭제 비활성, 도움말 열기/닫기, Escape 시트 닫기를 확인했다.
- 설정 6분류를 모두 전환했다. 기본 9개 행과 그룹, 녹음·단축키·키/모델·개인정보·업데이트·고급 도구를 확인했다. 비활성 설정의 `?`는 열리고 값은 바뀌지 않았다.
- 홈·사용량·음성 모델·음성 비교 시트의 실제 표시와 비교 녹음/전송 비활성을 확인했다.
- 다크 합성 Jev 결과에서 결과·검토 항목·표기 제안·비용·도움말의 가독성을 확인했다.
- 최종 간격 보완본에서 기록의 본문 24pt 여백, 홈의 44pt 결과 없음 행·단축키 4개, 검색 0개→지우기→4개 및 같은 선택 항목 복귀, 녹음 복구 빈 탭을 다시 확인했다. 최소 크기의 창과 확장된 창을 확인했으며 1120×760pt 정확한 치수의 수동 검증으로 기록하지 않는다.
- 활성 목록의 파란 선택 배경에 상위 고정 글자색이 상속되어 어둡게 보이는 문제를 실제 화면에서 발견했다. 셸의 고정 foregroundStyle 한 줄을 제거해 macOS 시스템 선택 글자색을 복원했고, 합성 기록의 활성 선택 행이 흰 글자로 표시됨을 다시 확인했다. 별도의 선택/저장 상태나 수동 색 판별 로직은 추가하지 않았다.
- 위 점검은 네이티브 대표 화면의 수동 확인이다. HTML의 636조건 또는 전체 기능 E2E를 통과했다는 뜻이 아니다.

## 이 Mac 설치

- 기존 앱이 대기 상태임을 네이티브 창에서 확인한 뒤 정상 종료했다. 최신 사용자 데이터 146개/665,677,804bytes를 다시 백업하고 복사본의 전체 SHA256을 대조했다.
- 0.2.10 (46) arm64 release 앱은 기존 `TechJuice Local Code Signing`으로 서명했다. 기존 앱의 designated requirement를 만족하고 strict/deep 코드 서명을 통과한 사본을 `/Applications/OpenNoType.app`으로 교체했다. 이전 앱과 실패 시 되돌릴 사본을 보존했다.
- 설치 앱의 실제 0.2.10 (46) 표시와 새 홈·설정 6분류/9개 기본 행을 확인했다. 마이크·외부 앱 입력·단축키·Jev 준비 상태는 설치 전처럼 유지됐다. 기존 연결 항목의 준비 필요도 설치 전부터 있던 상태로 구분한다.
- 최초 설치본의 실제 실행 PID 74868·실행 경로와 후보 바이너리 SHA256 `a4d67d5db11876856e65e28464946e8781b6c5d1e7c5fb2a81da9df683a94047`을 확인했다. 이 첫 설치의 소스는 `bde3b956a5d46d5e885a13f5b7beb902a15c00b5`다. 이후 선택색 한 줄 보완본을 다시 설치한 최종 실행 증거와 구분한다.
- 최초 교체 뒤 데이터 146개 전체 파일 해시와 연결 항목 존재/오류 메타데이터가 일치했다. [최초 설치 독립 증거](release-0.2.10-installation.json)는 이 첫 설치 사건을 보존한다.
- 선택색 보완까지 포함한 최종 소스 **`5a9ec4eb1da0cef1ebc1007df6056ff0e12cd1fb`**의 release 앱을 다시 서명·교체하고 실행했다. **PID 77889**, `/Applications/OpenNoType.app/Contents/MacOS/OpenNoType`, SHA256 **`be14b770cc0850a3438499dd4df3f0fc3b6e8e7dae37b5e12c220326b6462b00`**을 확인했다.
- 최종 설치본의 0.2.10 (46) 표시·설정 기본 9개 행·도움말 열기/닫기와 도움말 버튼으로의 포커스 복귀를 확인했다. 마이크·외부 앱 입력·단축키·Jev 준비 상태도 다시 확인했다.
- [최종 설치 독립 증거](release-0.2.10-installation-final.json): 원래 0.2.9 설치 전→최종 설치 후, 마지막 교체 직전→직후, 실제 저장 파일 재해시 모두 **146개 경로·크기·SHA256 동일**, 추가·삭제·변경 0개. 보호 설정 JSON 2개는 직렬화 바이트가 달라도 **의미가 동일**하다. 설정 키 추가·삭제는 없고 창 위치·크기 메타데이터 한 항목만 바뀌었다.
- 연결 항목 3개의 존재/반환 코드 메타데이터, 기존 designated requirement·entitlements를 독립 대조했다. 실제 키 값을 읽어 동일성을 검사한 것이 아니며, TCC DB를 읽거나 권한을 재설정하지 않았다.

## 소스와 배포 준비

최종 앱 소스와 로컬 `v0.2.10` 태그는 `5a9ec4eb1da0cef1ebc1007df6056ff0e12cd1fb`로 일치한다. `release-preflight.py --tag v0.2.10 --check-git --check-remote`가 버전·빌드 증가와 main 포함 여부를 통과했다. [최종 소스 CI](https://github.com/techjuicelab/opennotype/actions/runs/38657010872)가 Swift 1,221개 중 1,219개 통과·2개 제외·실패 0, Python 209개 통과, 일반 앱·별도 테스트 앱 빌드까지 성공했다. 이후 v0.2.10 태그를 푸시했으며 [공개 배포 CI](https://github.com/techjuicelab/opennotype/actions/runs/38657721131)와 [태그 일반 CI](https://github.com/techjuicelab/opennotype/actions/runs/38657721138)도 동일 소스로 성공했다. 각각 Swift 1,221개 중 1,219개 통과·2개 제외·실패 0, Python 209개 통과를 로그에서 확인했다.

| 실제 구현 | 최종 소스 근거 |
|---|---|
| 공통 크기·간격·색·행·버튼 | [DesignSystem.swift](https://github.com/techjuicelab/opennotype/blob/5a9ec4eb1da0cef1ebc1007df6056ff0e12cd1fb/Sources/OpenNoType/Views/DesignSystem.swift) |
| 셸·사이드바·기록 여백·native 선택색 | [MainView.swift](https://github.com/techjuicelab/opennotype/blob/5a9ec4eb1da0cef1ebc1007df6056ff0e12cd1fb/Sources/OpenNoType/Views/MainView.swift) |
| 홈·준비·결과·단축키 | [HomeView.swift](https://github.com/techjuicelab/opennotype/blob/5a9ec4eb1da0cef1ebc1007df6056ff0e12cd1fb/Sources/OpenNoType/Views/HomeView.swift) |
| 기록·사전·편집·복구 | [DataViews.swift](https://github.com/techjuicelab/opennotype/blob/5a9ec4eb1da0cef1ebc1007df6056ff0e12cd1fb/Sources/OpenNoType/Views/DataViews.swift) |
| 설정 6분류·상세 시트 | [SettingsView.swift](https://github.com/techjuicelab/opennotype/blob/5a9ec4eb1da0cef1ebc1007df6056ff0e12cd1fb/Sources/OpenNoType/Views/SettingsView.swift) |

## 공개 배포·다운로드

**2026-10-15 00:12:32 UTC / 09:12:32 KST**에 [v0.2.10](https://github.com/techjuicelab/opennotype/releases/tag/v0.2.10)을 공개했다. `draft=false`, `prerelease=false`, release ID `413291668`이며 태그의 실제 커밋이 승인 소스 `5a9ec4eb1da0cef1ebc1007df6056ff0e12cd1fb`와 일치한다.

[익명 공개 파일 검증](release-0.2.10-verification.json)은 09:13:05 KST에 전부 통과했다.

- 정확히 6개 자산을 인증 없이 HTTP 200으로 내려받아 GitHub digest·크기·SHA256·별도 checksum 파일을 대조했다.
- ZIP Ed25519 서명, v0.2.9→현재 추적 채널→공개 앱의 공개키 연속성, 앱·DMG strict 서명과 community 계약을 확인했다.
- 공개 앱은 0.2.10 (46), arm64, macOS 14.0 이상이다. DMG를 읽기 전용으로 검증하고 정상 해제했다.
- ZIP/DMG 앱 트리의 파일 99개·링크 9개·루트 포함 디렉터리 69개가 일치했다. 소유자·시간·xattrs는 비교에서 제외했다.
- Latest 페이지/API와 최신 appcast·metadata가 이 버전의 고정 자산으로 일치한다.

| 파일 | SHA256 |
|---|---|
| `OpenNoType-0.2.10.zip` | `10fc931cccfd34b4b5f3a19a87b4ec1c5b2db1170e23ee7741c1742275dbfe33` |
| `OpenNoType-0.2.10.dmg` | `f2b89ca7a26fbbe44ddeb4542d53b79fa9bef73eb0f56f8cb8b3cd2baa51b528` |

[다운로드 진입 독립 검증](release-0.2.10-downloads.json)은 09:12:56 KST에 확인했다. [Latest](https://github.com/techjuicelab/opennotype/releases/latest)는 v0.2.10으로 연결되고, [릴리스 목록](https://github.com/techjuicelab/opennotype/releases)의 첫 버전과 Latest 표시도 v0.2.10이다. 공식 사이트의 실제 배포 catalog·SSR은 이 릴리스 목록에 연결되며 v0.2.9 고정 다운로드 URL은 없다. 사이트 재배포 없이 새 버전이 기본 진입 목록의 최상단에 놓였다. 클라이언트 모달 버튼의 실제 클릭은 수행하지 않았고, 배포 catalog URL과 컴포넌트의 href 경로 대조로 확인한 범위를 구분한다.

공개 community 산출물은 ad-hoc 앱 서명·Sparkle Ed25519 서명을 사용하며 **Apple 공증 없음**을 유지한다. 이 Mac은 기존 권한 연속성을 위해 로컬 인증서로 서명한 동일 소스·버전을 설치했다. 공개 ZIP과 설치 앱의 바이너리 해시·서명·SDK가 동일하다는 주장은 하지 않는다.

## 마무리 문서 커밋

최종 검증 결과·증거 JSON·현재 배포 안내만 문서 커밋으로 추가한다. 태그 이후 `Sources`, `Resources`, `scripts`, `Package.swift`, `Package.resolved`, `.github`의 차이가 없음을 확인했다. 앱 코드 CI·태그 CI·배포 CI는 위 실제 성공 실행을 근거로 사용하고, 코드 변경이 없는 결과 문서 커밋은 `[skip ci]`로 중복 실행하지 않는다. [GitHub의 커밋 메시지 기반 실행 생략 문서](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/skip-workflow-runs)를 따르며, 문서 커밋 자체의 CI가 실행·통과했다는 뜻이 아니다. JSON 파싱·문서 링크·공백 검사는 따로 수행한다.

## 검증 경계

실제 자연 발화의 한영 인식 정확도, 모든 외부 앱의 입력 성공률, 새 Mac Gatekeeper, Intel, 네이티브 VoiceOver 낭독을 수행하지 않고 통과한 것으로 표시하지 않는다. 공개 community 산출물과 기존 로컬 인증서로 설치한 산출물은 같은 소스·버전으로 검증하되 바이너리 동일성을 주장하지 않는다.
