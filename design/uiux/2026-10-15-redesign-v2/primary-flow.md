# 기본 작업 흐름과 부속 화면 재설계

2026-10-15 · OpenNoType 0.2.9 (45) · 기준 `d620ada3bf849f8ecae4948716089cedb08fa5a5`

담당 A `ux_primary_flow`. 이 문서는 [클릭 시안](index.html)의 홈·첫 사용·녹음·처리·결과·프롬프트·검토·편집·HUD·메뉴바를 설명한다. [primary-screens.js](primary-screens.js)의 고정 가상 문장으로만 상태를 표현한다. 앱 소스, 설치 앱, 설정, 기록, 키, 권한과 실제 입력 경로는 변경하지 않는다. 공통 규격은 [design-system.md](design-system.md)를 따른다.

## 현재 화면에서 확인한 문제

사용자가 제공한 `Screenshot 2026-10-15 at 7.49.40 AM.png`와 현재 소스를 함께 봤다. 스크린샷은 처음 사용하거나 연결 준비가 안 된 홈에서 큰 준비 점검 영역·세 개 작업 카드·프롬프트 카드가 이어지는 모습을 보여 준다. 아래 치수는 소스의 pt 값이며 스크린샷 픽셀을 환산한 측정값이 아니다.

| 관찰 | 실제 근거 | 재설계 방향 |
|---|---|---|
| 관리 셸과 큰 패널 여백이 누적된다 | `MainView.body`의 사이드바 212, 툴바 56, 본문 여백 30, 최대 폭 920 ([MainView.swift](../../../Sources/OpenNoType/Views/MainView.swift), 19–56행). `Surface`의 여백 22·간격 18·반경 14 (175–185행) | 셸 208/52/24, 패널 16/16/10으로 통일한다. 옵션은 행, 독립 결과는 패널로 구분한다. |
| 홈에서 제목·준비 설명·모드 설명이 작업 결과와 경쟁한다 | `HomeView.body`는 소개·프롬프트·최근 결과·검토·준비·모드·모델·보조 작업·복구를 연달아 구성한다. 소개 제목 30pt, 모드 카드 여백 17 ([MainView.swift](../../../Sources/OpenNoType/Views/MainView.swift), 214–235·303–319·610–620행) | 제목을 한 번만 표시한다. 현재 문제/작업 → 최근 결과 → 다음 받아쓰기 → 보조 작업 순서로 읽힌다. 모드 소개 세 카드를 한 작업 행으로 줄인다. |
| 준비가 안 되면 점검 목록 전체가 기본으로 펼쳐진다 | `readyForInput`은 권한·키·로컬/화자 준비를 함께 판정하고, `inputReadiness.onAppear`가 준비 전 목록을 펼친다 ([MainView.swift](../../../Sources/OpenNoType/Views/MainView.swift), 208–211·250–300행) | 준비 필요 항목과 해결 버튼만 먼저 보여 준다. 정상 항목의 자세한 내용은 `준비 상태 확인`에서 읽는다. 키 저장과 실제 연결 성공은 별도 상태로 유지한다. |
| 원문·초안·최종 후보·검토·원문 재처리가 한 결과 영역에 모인다 | `PromptCompositionResultView`는 복사 가능 결과, 보류, 원문/최종 후보/중간 초안, 검토, 원문 편집을 조건부 표시한다 ([PromptCompositionResultView.swift](../../../Sources/OpenNoType/Views/PromptCompositionResultView.swift), 5–154행) | 결과 읽기/복사를 기본으로 두고 원문·후보·검토는 펼침, 편집은 별도 표면으로 분리한다. 복사 가능 여부는 그대로 따른다. |
| 작은 HUD에서 경고가 정상 상태·시간을 대체한다 | `VoiceBar`는 450×80, 미리보기 때 높이 140인 비활성 패널이고, 일시 안내가 있으면 기본 상태와 시간을 대신 표시한다 ([VoiceBar.swift](../../../Sources/OpenNoType/Views/VoiceBar.swift), 9–23·39–85행) | 경고와 관계없이 단계·시간·끝내기·취소 위치를 고정한다. 경고와 미리보기는 보조 줄로 늘린다. 감지 알고리즘이나 포커스 정책은 바꾸지 않는다. |

## 크기와 간격

| 요소 | 현재 소스 | 새 규격 |
|---|---|---|
| 관리 창 최소 크기 | 900×640 | 검토 기준 최소 960×680, 기본 1120×760 |
| 사이드바 / 툴바 | 212 / 56 | 208 / 52 |
| 본문 여백 / 콘텐츠 최대 폭 | 30 / 920 | 24 / 1184 |
| 일반 패널 여백 / 간격 / 반경 | 22 / 18 / 14 | 16 / 16 / 10 |
| 홈 제목 / 본문 | 30 / 14 | 22 / 13 |
| 섹션 / 부가 정보 | 각 화면 10~15 혼용 | 15 / 12, 핵심 값을 12보다 작게 표시하지 않음 |
| 행 / 설명 동반 행 | 내용마다 다름 | 최소 44 / 최소 56, 줄바꿈 시 자동 증가 |
| 보조 버튼 / 주요 버튼 | 위치별 고유 크기 | 32 / 36, 긴 문구는 폭 또는 높이 확장 |
| HUD 취소 / 종료 | 26×30 / 36×36 | 둘 다 최소 32 클릭 영역, 종료 36 유지 |
| HUD 폭 / 기본 높이 | 450 / 80 | 네이티브 이식 시 폭 448 기준, 높이는 80부터 내용에 맞춰 증가 |
| 프롬프트 원문 편집 | 최소 100~최대 180 높이 | 최소 5줄, 기본 160, 긴 내용은 편집 영역 내부 스크롤 |

HUD 시안은 실제 떠 있는 창을 실행하지 않고 각 상태를 표본 패널로 보여 준다. 최종 네이티브 높이는 경고·두 줄 미리보기·한국어/영어 줄바꿈을 함께 검증한 뒤 결정한다. 32 높이를 유지하려고 글자를 줄이거나 경고를 자르지 않는다.

## 홈과 첫 사용

일반 홈에는 녹음 시작 버튼을 추가하지 않는다. 원하는 외부 앱 입력창에서 단축키로 시작하는 기존 동작과 입력 대상 보호를 유지한다. 홈에는 `준비됨/준비 필요`, 현재 처리 방식, 입력 단축키, 최근 결과가 보인다. `음성 이 Mac · 문장 AI 정리 · 자동 검토 꺼짐`처럼 실제 적용 경로를 한 줄로 요약하며 자세한 모델·전송 범위는 `?`에서 확인한다.

홈 순서는 **현재 작업/보류/실패 → 최신 결과 → 다음 받아쓰기 안내 → 보조 작업**이다. 과거 성공 결과보다 지금 보류된 결과가 위에 온다. 준비가 끝나지 않은 첫 사용에는 현재 부족한 연결/권한/모델과 그 항목을 여는 버튼을 먼저 보여 준다. 정상 항목과 전체 준비 근거는 펼침으로 제공한다. 빠른 로컬 받아쓰기에서는 AI 키를 필수 준비로 표시하지 않는다.

기록이 없는 홈은 `아직 결과가 없습니다`와 외부 입력 단축키만 안내한다. 입력 연습은 별도 화면에서 시험 문장과 단축키를 보여 준다. 실제 앱의 두 방식인 `단축키를 기다림`과 `5초 뒤 입력`을 보존하되, 클릭 시안에서는 실행하지 않는다. 시험 문장은 실제 글을 입력하는 작업이므로 실행 직전에 `녹음·API 호출 없음 / 시험 문장 입력`을 표시한다.

실제 준비 조건은 [HomeView.readyForInput](../../../Sources/OpenNoType/Views/MainView.swift) 208–211행, 시작 보호는 [AppModel.toggle](../../../Sources/OpenNoType/App/AppModel.swift) 955–1093행, 입력 연습은 같은 파일 1124–1188행에 연결된다. 준비 완료를 API 실제 연결 성공이나 외부 입력 성공으로 확장 해석하지 않는다.

## 실제 상태와 화면 상태를 구분하기

`AppModel.Phase`는 `idle / starting / recording / enrolling / processing`이다 ([AppModel.swift](../../../Sources/OpenNoType/App/AppModel.swift), 9행). 아래 `보류/실패/결과 있음/확인 불가`는 새 엔진 상태가 아니라 기존 결과·입력 판정·검토·복구 정보를 조합한 **표시 상태**다. 앱 준비 상태는 `startupState`, 설정 복구는 별도 gate다.

| 실제 근거 | 표시 상태 | 기본 안내와 행동 |
|---|---|---|
| `.idle` + 필요한 준비 완료 | `home-ready` | 현재 방식 한 줄, 최신 결과/복사, 외부 앱 단축키 |
| `.idle` + 결과 없음 | `home-empty` | 결과 빈 상태, 외부 앱 단축키 |
| `.idle` + 준비 조건 부족 | `home-first` | 부족한 항목과 해당 설정 열기 |
| `.starting` | `home-starting` | `마이크 준비 중`, 아직 듣는 중 아님, 취소 |
| `.recording` | `home-recording` | `듣고 있어요`, 경과, 끝내기/취소, 현재 경고 |
| `.processing` + 실제 stage | `home-processing` | 인식/정리/활성 검토 단계, 입력 전, 취소. 가짜 진행률·완료 예상시간 없음 |
| `.idle` + 의미 검토/번역 결과 보류 | `home-held` | 입력하지 않은 이유, 원문/결과 나란히, 수동 복사/검토 |
| 입력 이벤트 제출 + 확인 불가 | `home-unverified` | `입력창을 먼저 확인`, 중복 입력 방지, 수동 복사 |
| 처리 실패 + 실제 원음 복구 저장 성공 | `home-failed` | 실패 단계, 실제 보관 상태, 실패 녹음 보기 |
| 실패 + 원음 저장 없음 | `home-failed`의 다른 실패 상태 | 보관됨 배지 제거, 다시 녹음/연결 확인 |
| 설정 복구 gate | `home-storage-recovery` | 변경 일시 중지, 이전 정상 설정/복구안 확인 |
| startup loading/failed 또는 Keychain 미사용 | 앱 준비 표시 | root의 시스템 화면과 연결, 기본 작업 활성화 조건 유지 |
| `.enrolling` | 화자 등록 표시 | B의 `speaker-enrolling`, 일반 받아쓰기와 구분 |

`starting`에서 실제 녹음 데이터를 받기 전까지 듣는 중으로 표시하지 않는 근거는 [AppModel.toggle](../../../Sources/OpenNoType/App/AppModel.swift) 1074–1085행이다. 종료·취소는 같은 파일 `stop` 1207행·`cancel` 1306행의 기존 의미를 따른다. 취소를 이미 외부 앱에 입력된 글의 되돌리기로 표현하지 않는다. 일반 protect, repair, 번역 보호, 번역 다듬기의 서로 다른 실패·보류 계약도 UI를 단순화하면서 합치지 않는다.

## 프롬프트 작업

홈의 `다른 작업 → 프롬프트 만들기`에서 복사용 녹음을 시작한다. 외부 앱에서 프롬프트 단축키를 쓸 때는 원래 입력창에 완성 결과를 입력하고 AI에는 자동 제출하지 않는다. 이 구분은 실행 요약에 짧게 남기며 자세한 목적·범위·예외는 `?`로 옮긴다. 기존 홈 문구의 `목표·맥락·제약·원하는 결과`, `코드나 직접 설계안을 만들지 않음`, 기존 지침 관련 차단은 도움말에 보존한다 ([MainView.swift](../../../Sources/OpenNoType/Views/MainView.swift), 336–373행).

`prompt-progress`는 실제 `drafting / reviewingDraft / polishing / reviewingFinal`만 사용한다. 다듬기는 필요한 경우에만 실행한다. 화면에는 생성·검토 단계와 취소, `생성 1~2회·검토 2회 / 추가 비용`을 표시한다. 완료되면 결과 복사를 우선하고 원문·중간 초안·최종 후보·검토를 펼침으로 제공한다. `참고 경고`와 `기존 지침 관련 차단`을 같은 위험 배지로 뭉개지 않는다.

차단·생성 실패·검토 실패·사용자 취소에서는 새 결과를 자동 입력하지 않는다. `canCopyOutput`이 허용한 결과만 완료 결과 복사 버튼을 제공한다. 차단된 후보는 최종 결과라고 부르지 않는다. 확인 가능한 원문/초안/후보의 기존 별도 표시와 복사 가능 범위는 유지한다 ([PromptCompositionPresentation.swift](../../../Sources/OpenNoType/App/PromptCompositionPresentation.swift), 43–45·67–78행; [PromptCompositionResultView.swift](../../../Sources/OpenNoType/Views/PromptCompositionResultView.swift), 51–99행).

원문 재작성은 `prompt-edit-source`로 분리한다. 편집할 원문·추가 비용·자동 입력 없음·실행/취소만 먼저 보인다. 기존 텍스트만 다시 보내고 음성을 재전송하지 않으며 원본 기록/실패 녹음을 덮어쓰지 않는다. 소스 식별자·크기/빈값 검사는 유지한다 ([AppModel.regeneratePrompt](../../../Sources/OpenNoType/App/AppModel.swift), 1958행; [PromptCompositionResultView.sourceEditor](../../../Sources/OpenNoType/Views/PromptCompositionResultView.swift), 121–154행).

## 검토·표기·편집

직접 검토는 `review-confirm → review`로 연결한다. 전송 확인에는 대상·서비스·전송할 텍스트·보내지 않는 녹음·추가 비용을 짧게 남긴다. 목적은 받아쓰기/번역/선택 수정/프롬프트별 기존 값으로 가져온다. 확인을 열고 나서 결과가 바뀌면 원래 요청 식별자를 다시 확인하는 기존 보호가 필요하다 ([JevReviewRequestButton](../../../Sources/OpenNoType/Views/JevReviewView.swift), 5–63행). 번역 직접 검토는 당시 언어·말투를 쓰고, 사전 표기 후보는 받아쓰기 경로에만 붙인다 ([AppModel.beginManualDecisionReview](../../../Sources/OpenNoType/App/AppModel.swift), 2600–2618행).

검토 결과는 원문/현재 결과 비교, 확인 필요한 신호, 표기 제안 순서다. 점수를 인식 정확도나 성공률로 표현하지 않는다. 로컬 문자 차이는 `변경됨`이라는 사실이고, 모델 위험 판단과 분리한다. `강한 신호 없음`을 의미 보존 보장으로 설명하지 않는다 ([JevReviewView](../../../Sources/OpenNoType/Views/JevReviewView.swift), 68–151행; `JevComparisonView` 214–264행).

| 보조 작업 | 새 표면 | 유지해야 하는 구분 |
|---|---|---|
| 직접 검토 실패 | `review-failed` | 원래 받아쓰기 결과/이미 입력한 글은 유지, 다시 검토는 새 전송 확인 |
| 표기 제안 저장 | `review-proposal` | 기존 매핑·근거 확인 후 사전에 저장, 현재 결과 자동 변경 없음, 추가 API 없음 |
| 직접 교정의 후보 검토 | `candidate-review-confirm → candidate-review → candidate-save-confirm` | 일반 결과 검토와 별도. 같은 교정 전·후 문장과 표기 한 쌍을 전송하고 판정 후 저장을 따로 확인 |
| 마지막 Jev 저장 되돌리기 | 저장 이후 보조 상태 | 자동 학습 되돌리기와 별도 행동 유지 |
| 등록 이름으로 표기 찾기 | `name-discovery-confirm` | 현재 문장의 후보 카탈로그·원문·결과를 별도 확인 후 전송, 자동 적용/저장 없음 |
| 개선안 생성 | `alternative-confirm → alternative` | 별도 생성 1회+검토 1회, 현재 결과·기록·외부 글을 덮어쓰지 않고 비교/복사 |
| 모호한 음성 수정 지시 | `edit-clarify` | 선택 원문/처음 지시 보존, 새 지시 전송 확인, 결과 복사용 |
| 다른 음성 인식문 비교 | `rerecognition` | 두 인식문 직접 비교/복사, 자동 교체 없음, 텍스트 정리는 별도 요청 확인 |
| 사전/학습 후보/이름 관리 | C의 사전 화면 | 현재 결과 수정과 다음 인식/정리 규칙 저장을 구분 |
| 문장/음성 모델 비교 | C의 `text-lab / speech-lab` | 단일 결과 보조 개선안과 실험실을 구분 |

근거: [JevReviewView.swift](../../../Sources/OpenNoType/Views/JevReviewView.swift) 123–210행; [JevWorkflowView.swift](../../../Sources/OpenNoType/Views/JevWorkflowView.swift) `JevImprovementView` 4–57행·`JevCorrectionReviewView` 60–113행; [JevAssistanceViews.swift](../../../Sources/OpenNoType/Views/JevAssistanceViews.swift) 이름 찾기 237–271행·수정 지시 287–341행·재인식 비교 343–388행. 실제 비용/전송 항목은 현재 provider와 목적에서 가져오며 예시의 서비스 이름을 하드코딩하지 않는다.

## HUD·메뉴바·도움말

HUD는 원래 앱의 포커스를 빼앗지 않는 `nonactivatingPanel`을 유지한다. 취소·현재 상태·시간·끝내기는 기본 줄에 고정한다. 준비 중은 녹음 전, 처리 중은 입력 전을 표시한다. 단축키 충돌 경고는 기본 상태를 대신하지 않고 추가 줄에 보인다. 실험 미리보기는 `확정 결과 아님`을 표시하고 두 줄까지만 제공한다. 모션 감소 설정을 보존한다 ([VoiceBar.swift](../../../Sources/OpenNoType/Views/VoiceBar.swift), 9–87행).

메뉴바는 상태, 네 작업의 현재 단축키, 작업 중 취소, 관리 창 열기, 사용량, 실패 녹음 수, 설정, 종료를 유지한다. 녹음 중 다른 모드 항목을 눌러도 기존 종료 동작을 유지한다. 관리 창 닫기는 앱 종료가 아니며 명시적으로 열 때만 활성화한다 ([StatusBarController.swift](../../../Sources/OpenNoType/App/StatusBarController.swift), 26–53·79–105·115–131행; [AppWindows.swift](../../../Sources/OpenNoType/App/AppWindows.swift), 49–55행). 시안의 메뉴는 상태 검토용이며 macOS 메뉴를 브라우저에서 구현한 것이 아니다.

일반 설명은 라벨 옆 `?` 하나로 읽는다. 제목·요약·현재값·활성 오류·보류 이유·추가 비용·전송 직전 요약은 화면에 남긴다. 원문·후보·표기 근거처럼 실제 내용을 읽는 펼침과 단순 사용법 도움말은 구분한다. 도움말은 한 번에 하나, 닫기·Escape 지원, 키보드로 닫을 때 진입 버튼으로 포커스 복원, 다른 컨트롤 클릭으로 닫을 때 새 컨트롤 포커스 유지가 원칙이다. 녹음 중 경고를 `?` 안에 숨기지 않는다. HTML 도움말은 실제 macOS 포커스/접근성 동작을 검증한 결과가 아니다.

## 모든 상태와 부속 표면 누락 대조

아래는 A의 실제 등록 화면 33개와 다른 담당으로 연결한 표면이다. 같은 실제 상태의 모든 문구를 새 페이지로 만들지는 않고 결과/오류 변형으로 표시한다. C/B/root 화면의 최종 ID는 통합 후 다시 확인한다.

| 범위 | 시안 ID/접근 | 원본 연결 | 포함 상태 |
|---|---|---|---|
| 일반 홈 | `home-ready / home-empty / home-first` | HomeView | 준비 완료, 결과 없음, 준비 필요 |
| 녹음 준비/작업 | `home-starting / home-recording / home-processing` | AppModel + VoiceBar | 시작 전, 녹음, 처리, 취소, 경고, 미리보기 |
| 입력 결과 | `home-held / home-unverified / home-failed` | recent result + delivery result | 보류, 제출 확인 불가, 보관 성공/없음, 무음, 대상 변경 |
| 설정 복구 | `home-storage-recovery` | preferencesRecovery | 이전 정상 설정, 복구안, 보관기간 확인 |
| 입력 연습 | `input-test` | arm/schedule/cancelInputTest | 단축키 대기, 5초 예약, 취소 |
| 번역 결과 | `translation-result` | latestResult + TranslationRefinementResultView | 당시 목표 언어, 초안/보류 구분, 수동 복사 |
| 번역 직접 검토 | `translation-review-confirm / translation-review` | JevReviewRequestButton의 translation 목적 | 원문/번역·당시 언어/말투 확인, 받아쓰기와 다른 비교, 이미 입력된 번역 유지 |
| 프롬프트 | `prompt-compose / prompt-progress / prompt-result / prompt-held / prompt-edit-source` | PromptCompositionResultView | 홈 복사용, 외부 입력 구분, 진행 네 단계, 중단/차단, 후보/원문, 재생성 |
| Jev 직접 검토 | `review-confirm / review / review-failed` | JevReviewRequestButton + JevReviewView | 전송 확인, 진행/실패 규칙, 결과/위험/차이 |
| 표기 제안 | `review-proposal` + 상세/되돌리기 | proposal + JevDictionaryUndoView | 기존 매핑, 확인 저장, 별도 되돌리기 |
| 직접 교정 후보 검토 | `candidate-review-confirm / candidate-review / candidate-save-confirm` | JevCorrectionReviewView | Type Script 후보의 교정 전·후 문장/한 쌍, 검토와 저장 각각 확인 |
| 등록 이름 찾기 | `name-discovery-confirm` | JevNameDiscoveryButton | 현재 원문/결과/등록 이름, 비용, 대상/provider/카탈로그 identity |
| 별도 개선안 | `alternative-confirm / alternative` | JevImprovementView | 생성/검토 전송 확인, 두 결과 비교, 복사 |
| 수정 지시 확인 | `edit-clarify` | JevEditClarificationView | 선택 원문, 새 지시, 확인, 실패/취소/복사 규칙 |
| 재인식 비교 | `rerecognition` | JevReRecognitionView | 원본/다른 인식, 복사, 별도 정리 확인 |
| 플로팅 패널 | `hud` | VoiceBarController/VoiceBarView | 준비/녹음/경고+미리보기/처리/완료 안내 |
| 메뉴 | `menubar` | StatusBarController | 대기/녹음/처리와 조건부 항목 |
| 화자 등록/모델/권한/AI 키 | B 화면으로 연결 | 각 Settings/Model View | A 중복 설계 없음 |
| 기록·복구·사전·사용량·모델 비교 | C 화면으로 연결 | DataViews/History/Jev view | A 결과에서 접근 보존 |
| 앱 준비·종료/업데이트·공통 모달 | root 시스템 화면 | App lifecycle/Update View | A 중복 설계 없음 |

브라우저 시안의 진행/복사/저장 버튼은 고정 화면 전환이나 안내만 수행한다. 실제 비동기 요청, 자동 저장, 기록 변경, 키 저장, 클립보드, 마이크, 권한 요청은 연결하지 않는다. 확인 창이 있다고 해서 API 요청이 수행되는 것으로 보이면 안 된다.

기록의 받아쓰기 직접 검토는 C가 `data-review-source/result/origin`으로 넘긴 **선택 행의 합성 원문·결과·표시 이름**을 A의 확인/검토 화면에 이어 표시한다. 클릭 캡처에서 등록 화면의 HTML만 갱신하고 값은 모두 escape한다. 다른 기록/홈에서 새 검토를 열면 해당 대상으로 바꾼다. 번역·프롬프트 검토는 각각 고정 상태 표본이며 모든 기록 모드에 동적 시뮬레이션을 연결했다는 뜻은 아니다. 선택 수정 기록은 당시 선택 원문이 없어 기존 앱처럼 직접 검토를 허용하지 않는다. 실앱에서는 이 HTML 속성 대신 기존 기록/검토 식별자와 목적 guard를 그대로 사용한다.

보류 결과의 `이 결과 검토…`도 같은 합성 원문·결과를 이 확인 흐름으로 넘기고 `data-review-return=home-held`로 원래 표면에 돌아온다. 보류 결과의 개선안 버튼은 실제 생성 대신 다른 고정 문장의 상태 표본이라는 안내만 표시한다. 개선안 생성/검토/비교의 전체 설계는 화면·상태 메뉴에 유지하며, 해당 보류 문장의 개선안을 만들었다고 표시하지 않는다.

## 좁은 창·긴 영어·접근성 계약

960×680에서 제목/상태/주행동/최근 결과가 먼저 읽히게 한다. 원문/결과 두 열은 본문 폭이 부족하면 위아래로 전환하고 비교 순서는 원문 → 결과를 유지한다. 작업 행 버튼은 줄바꿈하되 단축키 한 덩어리와 짧은 상태 배지는 쪼개지 않는다. 긴 앱 이름·모델명·영어 옵션은 최소 폭을 강제하지 않고 줄바꿈한다. `API v2.3.1`, 날짜, 코드 경로 등 결과 본문은 임의로 수정하거나 줄임표로 숨기지 않으며 긴 토큰에만 시각적 줄바꿈을 허용한다.

키보드 순서는 제목 다음 주행동, 결과, 보조 행동, 도움말/펼침 순서다. 도움말 버튼의 접근성 이름은 해당 항목명+도움말이다. HUD의 `×/■`도 각각 취소/녹음 끝내기 이름을 제공한다. 색만으로 성공·주의·실패를 구분하지 않고 텍스트를 붙인다. 상태 변경 시 보조기기 공지는 실제 중요 전이만 알리고, 1초 경과 시간이나 미리보기 갱신을 계속 낭독하지 않는다. 포커스가 있는 편집기/펼침은 상태 갱신 때문에 사라지거나 상단으로 되돌아가지 않아야 한다.

## 기능 보존과 이식 검증표

아래는 다음 구현 작업의 검증 항목이다. 이번 설계가 네이티브 동작을 완료/검증했다는 뜻이 아니다.

- [ ] 홈의 준비 조건이 `startupState`, 설정 복구, 실제 권한·단축키·현재 엔진 경로를 그대로 사용한다.
- [ ] 키 저장/연결 미확인/연결 실패/현재 사용 준비를 별도로 표시한다.
- [ ] 일반 받아쓰기는 외부 앱 단축키로 시작하며 홈 클릭이 입력 대상 포커스를 바꾸지 않는다.
- [ ] `.starting`은 실제 준비 완료 전 듣는 중이라고 표시하지 않는다.
- [ ] 진행·취소·단축키 충돌·미리보기의 기존 guard와 실험 기능 꺼짐 기본값을 보존한다.
- [ ] 외부 입력 확인/제출 확인 불가/미전달을 합치지 않고 중복 입력 위험을 안내한다.
- [ ] 보류가 상단에 오되 현재 결과의 원문·번역 당시 언어·선택 수정 원문/지시를 바꾸지 않는다.
- [ ] 복구 저장 성공 때만 보관됨을 표시하고 24시간/동일설정·현재설정 재처리 계약을 보존한다.
- [ ] 프롬프트의 홈/외부/재처리 전달 정책, `canCopyOutput`, 지침 차단과 내용 참고 경고를 유지한다.
- [ ] 직접 Jev 검토/이름 찾기/개선안/수정 재지시/재인식 후 정리는 각각 필요한 전송 확인을 유지한다.
- [ ] 미완료 검토에 통과 점수/제안을 만들어 표시하지 않고 검토 신호를 정확도라고 부르지 않는다.
- [ ] 사전 저장·제한적 학습·Jev 저장 되돌리기와 현재 결과 복사를 혼동하지 않는다.
- [ ] 시트가 열린 뒤 원본 결과/대상/provider가 바뀌는 stale 작업을 기존 identity guard로 막는다.
- [ ] 설정 복구/미리보기/처리 중 gate가 실제 mutation에 남고 `?`는 읽을 수 있다.
- [ ] HUD가 nonactivating이며 관리 창 닫기/메뉴 열기/도움말 닫기가 외부 입력 대상을 탈취하지 않는다.
- [ ] 960/1120/1440, 긴 영어/긴 버전·경로, 다크 모드, 키보드/Escape/VoiceOver, 모션 감소를 별도로 확인한다.

정적 시안의 링크/도움말/지역 전환은 메인의 [verification.md](verification.md)에 통합 기록한다. 앱 빌드·실제 녹음·실제 붙여넣기·API 비용·네이티브 접근성·실제 macOS 작은 창 검증은 후속 구현의 책임이다.
