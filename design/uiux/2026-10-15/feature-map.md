# OpenNoType UI/UX 재정비 — 기능 이동표와 동작 보존 기준

작성일: 2026-10-15
조사 담당: 병렬 조사 에이전트 `ux_settings_architecture`
상태: 설계 제안. 앱 구현·설정 변경·설치·앱 실행·테스트 실행은 하지 않음.

추가 반영: 각 옵션의 긴 설명은 라벨 옆 `?` 버튼을 눌러 별도로 읽는 방식으로 정리한다. 설정 기본 화면은 라벨·현재값·필요한 상태만 간결하게 표시한다. 구체적인 도움말 내용과 예외 노출 기준은 10절을 따른다.

## 1. 문서 목적과 사용 범위

기능 개선 작업이 병행되는 상황에서, 기존 기능과 설정을 빠뜨리지 않고 화면 구조를 정리하기 위한 인계 문서다. 현재 체크아웃의 SwiftUI 화면과 Preferences 연결을 읽어 작성했다. 실제 실행 화면의 시각적 품질이나 사용성 테스트 결과를 의미하지 않는다.

이 문서의 소스 행 번호는 조사 시점 기준이며 병행 개발로 이동할 수 있다. 구현할 때는 함수·속성 이름과 현재 호출 경로를 다시 확인해야 한다. 상대 링크의 `#L`은 행 번호를 표시한다. 로컬 Markdown 뷰어에서 행 이동을 지원하지 않으면 파일을 열어 해당 행을 확인한다.

이번 설계에서 바꾸려는 것은 탐색·묶음·표시 우선순위·설명 문구다. 음성 처리, 단축키, 붙여넣기, Jev 실패 정책, 비용 한도, 기록 보관, 암호화와 기본 설정은 별도 동작 변경으로 취급한다.

## 2. 현재 구조에서 확인한 핵심 문제

| 문제 | 코드에서 확인한 사실 | 사용자가 겪을 수 있는 혼란 | 정리 방향 |
|---|---|---|---|
| 한 작업의 준비가 여러 화면에 분산 | 처리 방식은 [VoiceInputOptionsView:7–16](../../../Sources/OpenNoType/Views/VoiceInputOptionsView.swift#L7), 로컬/API 선택은 [SettingsView:207–249](../../../Sources/OpenNoType/Views/SettingsView.swift#L207), 모델 준비는 별도 [VoiceSettingsView:668–688](../../../Sources/OpenNoType/Views/SettingsView.swift#L668) | ‘빠른 받아쓰기’를 고른 뒤 어디서 모델을 준비하고 실제로 적용되는지 찾아야 함 | 받아쓰기 설정에서 현재 유효 상태를 요약하고, 모델 준비는 AI 연결의 음성 모델과 동일한 목적지로 연결 |
| 저장된 선택과 현재 적용 상태가 다름 | [Preferences:300–303](../../../Sources/OpenNoType/App/Preferences.swift#L300)의 빠른 로컬 조건은 번역에서 false. 표현 설정은 [번역 시 중지](../../../Sources/OpenNoType/Views/DictationExpressionSettingsView.swift#L11). 미리보기는 [화자 필터와 함께 사용 불가](../../../Sources/OpenNoType/Views/VoiceInputOptionsView.swift#L82) | 켜진 옵션이 실제로도 작동한다고 오해 | 저장값을 지우지 않고 ‘적용 중 / 현재 미적용’ 상태와 이유를 표시 |
| 다른 학습 기능의 의미가 섞임 | 같은 `automaticLearningEnabled`가 [개인정보](../../../Sources/OpenNoType/Views/SettingsView.swift#L419)와 [개인 사전](../../../Sources/OpenNoType/Views/DataViews.swift#L230)에 중복 노출. 별도 [Jev 오류 유형 학습](../../../Sources/OpenNoType/Views/JevAssistanceViews.swift#L21)도 있음 | 표기 사전, 검토에서 기억한 오류 유형, 모델 재학습을 혼동 | 개인 사전 학습의 관리 위치를 개인 사전으로 일원화하고, Jev 오류 유형 학습은 별도 실험 상세로 구분 |
| Jev 연결 화면에 도구·실험·결과가 집중 | [SettingsView:79–203](../../../Sources/OpenNoType/Views/SettingsView.swift#L79)에 연결, 4개 모드, 번역 보호, 학습, 보조 모델, 비교, 추가 도움, 연결 테스트, 최근 결과가 함께 있음 | 기본 받아쓰기 설정과 실험 도구의 중요도가 비슷하게 보임 | 연결은 AI 연결, 모드는 받아쓰기 자세히, 실험은 고급 도구, 테스트는 진단, 결과는 해당 결과 화면으로 이동 |
| 단축키 안내가 선택과 맞지 않음 | [활성화 동작](../../../Sources/OpenNoType/Views/VoiceInputOptionsView.swift#L17)은 hold/toggle/혼합인데 [단축키 안내](../../../Sources/OpenNoType/Views/SettingsView.swift#L320)는 항상 toggle 설명 | 누르는 동안 녹음으로 바꾸어도 ‘다시 눌러 종료’로 이해 | 활성화 설정에서 안내를 파생하고 실제 방식별로 표시 |

기존 UI에서 보존할 장점은 다음과 같다.

- [API 키 상세의 자동 펼침](../../../Sources/OpenNoType/Views/SettingsView.swift#L650): 키가 없거나 변경·준비 중일 때 필요한 정보가 드러난다.
- [번역 예시](../../../Sources/OpenNoType/Views/DictationTranslationSettingsView.swift#L18)와 [표현 예시](../../../Sources/OpenNoType/Views/DictationExpressionSettingsView.swift#L21): 예시를 보는 것과 실제 적용을 구분한다.
- [모델 삭제 확인](../../../Sources/OpenNoType/Views/VoiceInputOptionsView.swift#L87): 삭제 범위와 재다운로드 필요를 알린다.
- [텍스트 비교 모델 직접 적용](../../../Sources/OpenNoType/Views/JevModelComparisonView.swift#L100): 추천이 설정을 자동으로 바꾸지 않는다.

## 3. 확정할 탐색 구조

주 탐색은 네 개로 줄이되 내부 기능은 유지한다.

| 주 탐색 | 역할 | 기존 화면을 포함하는 방식 |
|---|---|---|
| 받아쓰기 | 현재 준비 상태, 기본 작업 진입, 최근 결과 | 기존 home. 번역·선택 문장 음성 수정·프롬프트 만들기는 작업 선택 안에 유지 |
| 기록 | 저장된 결과와 다시 처리할 녹음 | 기존 history + recovery. 복구할 녹음이 있을 때 홈 알림과 기록 배지로 연결 |
| 개인 사전 | 정확한 표기, 교정 검토, 학습 관리 | 기존 dictionary. 일반 사전과 검토 참고 이름을 구분 |
| 설정 | 목적별 여섯 분류 | 아래 구조. 사용량·모델 준비·실험·진단을 내부 목적지로 이동 |

현재 주 탐색은 [MainView:123–125](../../../Sources/OpenNoType/Views/MainView.swift#L123), 내부 AppPage는 [Preferences:312–319](../../../Sources/OpenNoType/App/Preferences.swift#L312)에 있다. 탐색 재정비만으로 enum rawValue나 기존 내부 라우트를 바꿀 필요는 없다. 첫 구현에서는 표시 구조와 내부 라우트를 연결하는 어댑터를 사용하고, 이전 목적지로 이동하는 기존 액션을 보존한다.

설정은 다음 여섯 분류를 사용한다.

| 분류 | 기본 노출 | 자세히 또는 연결 목적지 |
|---|---|---|
| 받아쓰기 | 입력 방식, 출력 언어, 이번 작업에 적용되는 상태 | 표현·편집 강도·예시, 앱별 작성 방식, 별도 번역 출력 언어, 자동 문장 검토 |
| 녹음·단축키 | 마이크, 단축키 동작, 작업별 단축키 | 녹음 알림음·시스템 소리 음소거·충돌 확인 |
| AI 연결 | 음성 인식 위치와 준비 상태, 문장 처리 연결 | 제공자·키·모델, 로컬 모델 관리, Jev 연결, 사용량·비용 |
| 개인정보 | 전송 정보 요약, 기록 여부와 보관 기간 | 앱별 문맥 허용, 사용량 기록, 학습 관리 링크 |
| 앱 관리 | 앱 언어·화면 모드·로그인 실행·업데이트 | 로그인 항목 시스템 설정, 모델 출처·라이선스 |
| 고급 도구 | ‘실험 기능’과 ‘문제 해결’ 두 그룹 | 실험의 활성 상태와 진단 도구를 섞지 않음 |

`모델 준비`는 받아쓰기 처리 방식 선택과 AI 연결의 음성 모델에서 **같은 목적지**로 이어져야 한다. 같은 설정을 복제하여 서로 다른 화면에서 따로 저장하지 않는다.

## 4. 기본·상세·실험·문제 해결 노출 원칙

| 수준 | 보여줄 것 | 노출 조건과 보존 규칙 |
|---|---|---|
| 기본 | 옵션 라벨·현재값·짧은 유효 상태·필요한 다음 행동 | 긴 설명문을 반복하지 않음. 라벨 옆 `?`는 항상 접근 가능 |
| 옵션 도움말 | 기능 설명·적용 범위·일반적인 실패 계약·전송과 비용 | 해당 옵션의 `?`를 눌러 팝오버로 읽음. 설명을 열어도 설정은 바뀌지 않음 |
| 자세히 | 자주 바꾸지 않는 설정과 세부 연결 | 켜진 고급 옵션은 접혀 있어도 요약·개수·상태를 남김. 기능 설명은 여기에서도 옵션별 `?`로 구분 |
| 실험 기능 | 추가 비용·처리·실험 모델 기능 | 고급 도구 안에 분리. 기본 꺼짐 유지. 사용 중이면 기본 요약에서도 알림 |
| 문제 해결 | 권한·연결·입력 확인·처리 시간 | 준비가 막혔을 때 해당 문제로 바로 연결. 정상 사용 중 긴 진단 로그를 먼저 보여주지 않음 |

구체적인 표시 규칙:

1. 저장된 옵션과 실제 적용 여부를 구분한다. 번역 중 표현 설정, 화자 필터 중 미리보기 등의 저장값을 UI가 자동으로 삭제하거나 끄지 않는다.
2. 키·모델·권한이 준비되지 않은 경우 해당 상세만 자동으로 연다. 필요한 준비 작업을 찾아다니지 않게 한다.
3. 모델·제공자 이름은 숨기지 않되, ‘이 Mac에서 인식 / 온라인으로 인식’이라는 처리 의미를 먼저 보여준다. PCM, decoder, CPU fallback 등의 구현 용어는 기본 화면에 넣지 않는다.
4. 일반적인 기능 설명·적용 범위·실패 계약·전송/비용 상세는 라벨 옆 `?` 도움말로 이동한다. 현재 입력 보류 원인·키 없음·미적용 이유·켜진 추가 요청 표식은 기본 화면에 남긴다. 실제 삭제·유료 전송 실행의 기존 확인창은 도움말로 대체하지 않는다.
5. 말투·표현·번역·검토는 하나의 ‘정확도’ 슬라이더로 합치지 않는다. 서로 다른 계약과 영향을 가진다.
6. 변경이 다음 녹음부터 적용되는지, 즉시 적용되는지, 진행 중 처리에 영향을 주는지는 기존 계약대로 표시한다.
7. 실험 기능과 문제 해결은 같은 고급 도구 안에서도 별도 그룹으로 나눈다. ‘실험’이 꺼져 있어도 입력 테스트·권한 확인은 찾을 수 있어야 한다.

## 5. 기존 기능 전체 이동표

아래는 화면에서 제공되는 기능을 기준으로 묶은 이동표다. 같은 preference를 여러 위치에서 노출하던 경우 주 관리 위치와 이동 링크를 구분했다. 신규 기능을 추가하자는 목록은 아니다.

### 5.1 일상 작업·결과·기록·개인 사전

| 기존 기능 | 새 위치 | 노출·보존 계약 | 근거 |
|---|---|---|---|
| 받아쓰기·번역·선택 문장 음성 수정·프롬프트 만들기 | 받아쓰기의 작업 선택 | 기존 단축키와 작업 종류 유지. 주 화면 이름이 받아쓰기라고 다른 작업을 제거하지 않음 | [MainView:202](../../../Sources/OpenNoType/Views/MainView.swift#L202), [작업 카드:608](../../../Sources/OpenNoType/Views/MainView.swift#L608) |
| 연결·권한·단축키 준비 상태와 입력 연습 | 받아쓰기의 준비 요약 → 고급 도구 / 문제 해결 | 필요한 경우에만 상세로 연결 | [MainView:250–297](../../../Sources/OpenNoType/Views/MainView.swift#L250) |
| 최근 결과·원문 복사·원문 비교 | 받아쓰기 / 최근 결과 | 입력 결과·미리보기·번역 초안을 구분 | [MainView:375–418](../../../Sources/OpenNoType/Views/MainView.swift#L375) |
| 최근 결과의 직접 Jev 검토 | 받아쓰기 / 최근 결과의 자세히 | 전송·비용 확인을 유지 | [MainView:412](../../../Sources/OpenNoType/Views/MainView.swift#L412), [JevReviewRequestButton:24–39](../../../Sources/OpenNoType/Views/JevReviewView.swift#L24) |
| Jev 결과·원문 차이·표기 제안 확인·사전 저장·저장 되돌리기 | 해당 최근 결과 또는 기록의 검토 상세 | 제안과 사전에 저장된 교정을 구별, 명시적 저장 | [JevReviewView:68–208](../../../Sources/OpenNoType/Views/JevReviewView.swift#L68) |
| 개선안 생성·검토·취소·복사 | 해당 결과의 검토 상세 | 자동으로 입력 결과 대체하지 않음 | [JevWorkflowView:4–54](../../../Sources/OpenNoType/Views/JevWorkflowView.swift#L4) |
| 모호한 수정 지시 확인과 다른 인식문 비교 결과 | 해당 작업의 결과 상세 | 해결을 위한 추가 입력·생성·복사·취소 경로 유지 | [JevAssistanceViews:232–317](../../../Sources/OpenNoType/Views/JevAssistanceViews.swift#L232) |
| 프롬프트 생성 결과·검토·원문 수정 후 다시 만들기·복사 | 받아쓰기의 프롬프트 작업 결과 | 홈 시작·재처리·원문 수정은 복사용. 다른 앱 단축키 경로의 기존 입력 계약과 구별 | [MainView:336–369](../../../Sources/OpenNoType/Views/MainView.swift#L336), [PromptCompositionResultView:33](../../../Sources/OpenNoType/Views/PromptCompositionResultView.swift#L33) |
| 기록 검색·날짜·작업·결과·원문·복사·개별/전체 삭제 | 기록 / 보관한 결과 | 암호화·보관 정책과 전체 삭제의 연동 효과 유지 | [DataViews:6–45](../../../Sources/OpenNoType/Views/DataViews.swift#L6), [HistoryEntryCard:49–190](../../../Sources/OpenNoType/Views/DataViews.swift#L49) |
| 기록 원문을 AI로 다시 처리·취소·미리보기·직접 검토 | 기록 / 항목의 자세히 | 현재 설정으로 텍스트만 다시 처리. 원래 기록은 유지, 결과 미리보기는 자동 입력·별도 보관하지 않음 | [DataViews:110–174](../../../Sources/OpenNoType/Views/DataViews.swift#L110) |
| 실패 녹음·만료 시각·삭제·같은 설정/현재 설정 복구·취소·복사 | 기록 / 다시 처리 | 홈 실패 알림도 동일 목적지. 원음 최대 24시간, 성공 시 삭제, 자동 입력 없음 | [DataViews:420–452](../../../Sources/OpenNoType/Views/DataViews.swift#L420), [복구 카드:471–520](../../../Sources/OpenNoType/Views/DataViews.swift#L471) |
| 실패한 선택 문장 수정의 원문 다시 제공 | 기록 / 다시 처리 항목 | 저장하지 않았던 원문을 다시 입력받음. 누락된 원문을 자동 추정하지 않음 | [DataViews:497–506](../../../Sources/OpenNoType/Views/DataViews.swift#L497) |
| 단어 검색·등록·수정·삭제·JSON 가져오기/내보내기 | 개인 사전 | 기존 데이터·가져오기 확인·중복 처리 보존 | [DataViews:199–309](../../../Sources/OpenNoType/Views/DataViews.swift#L199) |
| 교정한 표기 자동 학습·학습 후보 확인·직접 등록·무시·최근 되돌리기 | 개인 사전 / 학습 관리 | 개인정보에서는 상태·이동 링크. 같은 preference의 별도 사본 금지 | [DataViews:230–259](../../../Sources/OpenNoType/Views/DataViews.swift#L230) |
| Jev 교정 후보 검토·확인한 교정 저장 | 개인 사전 / 확인할 교정 | 검토와 사전 저장을 구분하고 명시적 동의 유지 | [JevWorkflowView:60–108](../../../Sources/OpenNoType/Views/JevWorkflowView.swift#L60) |
| 앱·프로젝트 이름 후보·앱 이름 가져오기·추가·삭제 | 개인 사전 / 자세히의 ‘검토에 참고할 이름’ | 일반 사전 매핑과 구별. 설치 앱 자동 수집 없음, 최대 64개 | [JevNameCatalogView:92–168](../../../Sources/OpenNoType/Views/JevAssistanceViews.swift#L92) |
| 등록한 이름에서 표기 찾기 | 해당 결과의 검토 상세 | 등록된 후보를 참고하는 명시적 외부 요청이며 자동 사전 등록 아님 | [JevAssistanceViews:171–203](../../../Sources/OpenNoType/Views/JevAssistanceViews.swift#L171) |

### 5.2 받아쓰기·녹음·단축키 설정

| 기존 기능 / 값 | 새 위치 | 노출·보존 계약 | 근거 |
|---|---|---|---|
| `dictationProcessing` | 설정 / 받아쓰기 / 기본 | AI 정리와 빠른 로컬 처리의 차이, 유효 상태를 표시 | [VoiceInputOptions:7–16](../../../Sources/OpenNoType/Views/VoiceInputOptionsView.swift#L7) |
| `dictationOutputLanguage`와 언어 예시·적용 | 설정 / 받아쓰기 / 기본 → 언어 선택창 | 예시만 보고 값이 바뀌지 않음 | [DictationTranslationSettingsView:10–39](../../../Sources/OpenNoType/Views/DictationTranslationSettingsView.swift#L10) |
| `dictationExpression`의 방식·강도·예시·복원 | 설정 / 받아쓰기 / 자세히 | faithful/0의 기존 정리 유지. 번역 시 일시 미적용 | [DictationExpressionSettingsView:10–60](../../../Sources/OpenNoType/Views/DictationExpressionSettingsView.swift#L10) |
| `writingProfiles`의 앱 추가·형식·말투·복원 | 설정 / 받아쓰기 / 앱별 작성 방식 | 앱 단위, 주변 문맥 허용과 독립 | [SettingsView:527–564](../../../Sources/OpenNoType/Views/SettingsView.swift#L527) |
| 별도 번역 단축키의 `targetLanguage` | 설정 / 받아쓰기 / 자세히 | 받아쓰기 출력 언어와 별도 값 | [SettingsView:294–305](../../../Sources/OpenNoType/Views/SettingsView.swift#L294) |
| `shortcutActivation` | 설정 / 녹음·단축키 / 기본 | hold/toggle/혼합. 안내 문구도 해당 값에서 파생 | [VoiceInputOptions:17–20](../../../Sources/OpenNoType/Views/VoiceInputOptionsView.swift#L17) |
| 작업별 `hotkeys` 변경 | 설정 / 녹음·단축키 / 기본 | 기존 4개 작업과 충돌 보호 유지 | [SettingsView:309–329](../../../Sources/OpenNoType/Views/SettingsView.swift#L309) |
| 단축키 충돌 확인 | 설정 / 녹음·단축키 / 자세히, 문제 해결의 링크 | 같은 진단 액션 재사용 | [SettingsView:324–329](../../../Sources/OpenNoType/Views/SettingsView.swift#L324) |
| `inputDeviceUID`, 연결 끊김, 마이크 새로고침 | 설정 / 녹음·단축키 / 기본 | 시스템 기본과 지정 장치 구별 | [VoiceInputOptions:22–32](../../../Sources/OpenNoType/Views/VoiceInputOptionsView.swift#L22) |
| `recordingAudioFeedback` | 설정 / 녹음·단축키 / 자세히 | 준비·종료 알림음, 기본 꺼짐 | [VoiceInputOptions:33](../../../Sources/OpenNoType/Views/VoiceInputOptionsView.swift#L33) |
| `muteWhileRecording` | 설정 / 녹음·단축키 / 자세히 | 이전 상태 복원·사용자 수동 변경 존중·알림음 상호 영향 | [VoiceInputOptions:34–36](../../../Sources/OpenNoType/Views/VoiceInputOptionsView.swift#L34) |
| `decisionReviewMode` | 설정 / 받아쓰기 / 자세히의 ‘자동 문장 검토 · 실험’ | 네 모드 계약을 합치지 않음. 연결 상세는 AI 연결 | [SettingsView:113–149](../../../Sources/OpenNoType/Views/SettingsView.swift#L113) |

### 5.3 AI 연결·음성 모델·사용량

| 기존 기능 / 값 | 새 위치 | 노출·보존 계약 | 근거 |
|---|---|---|---|
| `provider`, `useLocalTranscription` | 설정 / AI 연결 / 음성 인식 | Anthropic 로컬 조건, 빠른 받아쓰기의 유효 로컬 조건과 구별 | [SettingsView:207–249](../../../Sources/OpenNoType/Views/SettingsView.swift#L207), [Preferences:300–303](../../../Sources/OpenNoType/App/Preferences.swift#L300) |
| 음성 인식 API 키 저장·삭제·상태 | 설정 / AI 연결 / 음성 인식 자세히 | Keychain 저장은 명시적. 준비 필요 시 펼침 | [SettingsView:221–244](../../../Sources/OpenNoType/Views/SettingsView.swift#L221) |
| `transcriptionModels`, 모델 ID/목록·제공자 안내 | 위 음성 인식 자세히 | 제공자별 값 유지, 빈 값은 기존 기본값 | [SettingsView:233–241](../../../Sources/OpenNoType/Views/SettingsView.swift#L233), [Preferences:287–293](../../../Sources/OpenNoType/App/Preferences.swift#L287) |
| `textProvider`, 문장 처리 API 키·모델 선택/ID | 설정 / AI 연결 / 문장 처리 | 키 공유 조건과 독립 제공자 선택 유지 | [SettingsView:251–289](../../../Sources/OpenNoType/Views/SettingsView.swift#L251) |
| 로컬 모델 준비 상태·인식 방식 변경 이동 | 설정 / AI 연결 / 음성 모델 | 받아쓰기의 모델 준비도 이 목적지로 연결 | [VoiceSettingsView:676–685](../../../Sources/OpenNoType/Views/SettingsView.swift#L676) |
| `localSpeechModel` 선택·다운로드/준비·취소 | 위 음성 모델 / 기본 | 한국어·영어 지원과 혼용 정확도 보장 구별 | [LocalModelOptions:57–67](../../../Sources/OpenNoType/Views/VoiceInputOptionsView.swift#L57) |
| 선택 모델 파일 삭제·다운로드 용량·준비 상태 | 위 음성 모델 / 파일 관리 자세히 | 확인 후 삭제, 다른 모델·기록·사전 유지 | [LocalModelOptions:68–90](../../../Sources/OpenNoType/Views/VoiceInputOptionsView.swift#L68) |
| `localModelUnloadPolicy` | 위 음성 모델 / 자세히 | never/5/15/30분, 재준비의 반응 영향 | [LocalModelOptions:77–81](../../../Sources/OpenNoType/Views/VoiceInputOptionsView.swift#L77) |
| `decisionProvider`, 직접 Jev API 키·재사용 키·다시 확인 | 설정 / AI 연결 / 문장 검토 연결 | 실제 전송 목적지·준비 상태 표시 | [SettingsView:79–119](../../../Sources/OpenNoType/Views/SettingsView.swift#L79) |
| `improvementModels`, 현재 문장 모델과 같게 복원 | 위 문장 검토 연결 / 자세히 | 명시적 개선안과 protect 보조안에만 사용되는 차이 | [SettingsView:163–174](../../../Sources/OpenNoType/Views/SettingsView.swift#L163) |
| 모델별 사용량·비용 화면 | 설정 / AI 연결 / 사용량·비용 | 개인정보의 통계 설정에서도 같은 목적지로 연결 | [SettingsView:49–52](../../../Sources/OpenNoType/Views/SettingsView.swift#L49), [UsageView:6–58](../../../Sources/OpenNoType/Views/UsageView.swift#L6) |
| 사용량 기간·제공자 필터, 요약·모델별·일별·최근 요청·비용 설명 | 위 사용량·비용 | 비용의 추정·보고 단가 차이와 기록 누락 상태 유지 | [UsageView:25](../../../Sources/OpenNoType/Views/UsageView.swift#L25), [일별:195](../../../Sources/OpenNoType/Views/UsageView.swift#L195), [최근 요청:233](../../../Sources/OpenNoType/Views/UsageView.swift#L233), [설명:269](../../../Sources/OpenNoType/Views/UsageView.swift#L269) |
| 이번 실행의 텍스트 모델 비교 요약 | 위 사용량·비용 / 자세히 | 전체 정확도 수치처럼 보이지 않게 함 | [UsageView:74](../../../Sources/OpenNoType/Views/UsageView.swift#L74) |
| 사용량 기록 초기화 | 위 사용량·비용 / 관리 자세히 | 명시적 삭제 확인, 텍스트 기록과 다른 데이터 | [UsageView:284–289](../../../Sources/OpenNoType/Views/UsageView.swift#L284) |

### 5.4 개인정보·앱 관리

| 기존 기능 / 값 | 새 위치 | 노출·보존 계약 | 근거 |
|---|---|---|---|
| AI로 보내는 정보 요약 | 설정 / 개인정보 / 기본 | 빠른 로컬·번역·선택 수정·프롬프트·검토·다듬기의 차이 유지 | [SettingsView:387–416](../../../Sources/OpenNoType/Views/SettingsView.swift#L387) |
| `allowedContextApps` 추가·해제·목록 | 설정 / 개인정보 / 주변 문맥 자세히 | allowlist·보안 입력 제외·최대 1,000자·비보관 | [SettingsView:332–345](../../../Sources/OpenNoType/Views/SettingsView.swift#L332) |
| 개인 사전 자동 학습 요약·관리 이동 | 설정 / 개인정보 / 학습 자세히 | 사전이 주 관리 위치. 동일한 값 사용 | [SettingsView:419–430](../../../Sources/OpenNoType/Views/SettingsView.swift#L419) |
| `historyEnabled`, `retentionDays` | 설정 / 개인정보 / 기본 | 기록 끔과 기존 기록 삭제의 차이, 보관 기간 정책 | [SettingsView:349–360](../../../Sources/OpenNoType/Views/SettingsView.swift#L349) |
| 실패 원음·복구 보관 설명 | 설정 / 개인정보 / 보관 자세히 | 최대 24시간 암호화, 성공 원음 즉시 삭제 | [SettingsView:359](../../../Sources/OpenNoType/Views/SettingsView.swift#L359) |
| `usageTrackingEnabled`, 통계 관리 이동 | 설정 / 개인정보 / 사용량 자세히 | 최대 10,000건·내용/원음 제외·off가 기존 통계 삭제는 아님 | [SettingsView:433–440](../../../Sources/OpenNoType/Views/SettingsView.swift#L433) |
| `interfaceLanguage` | 설정 / 앱 관리 / 기본 | 출력 언어·인식 방식과 독립 | [SettingsView:446–451](../../../Sources/OpenNoType/Views/SettingsView.swift#L446) |
| 로그인 실행·상태·시스템 설정 | 설정 / 앱 관리 / 기본 | 창 없이 메뉴바 대기 | [SettingsView:453–460](../../../Sources/OpenNoType/Views/SettingsView.swift#L453) |
| `appearance` | 설정 / 앱 관리 / 기본 | system/light/dark | [SettingsView:462–467](../../../Sources/OpenNoType/Views/SettingsView.swift#L462) |
| 현재 버전·자동 업데이트 확인·수동 확인·릴리스·설치 재개 | 설정 / 앱 관리 / 업데이트 | 녹음·문장 처리 중 업데이트 보호 유지 | [UpdateSettingsView:8–47](../../../Sources/OpenNoType/Views/UpdateSettingsView.swift#L8) |
| 모델 출처·라이선스 | 설정 / 앱 관리 / 정보 | 음성/화자 모델별 원래 고지 유지 | [VoiceSettingsView:717–721](../../../Sources/OpenNoType/Views/SettingsView.swift#L717) |
| 손상된 설정 복구·이전 정상 설정 복원·복구안 승인 | 앱 전역 준비/복구 화면 | 고급 도구 안으로 숨기지 않음. 녹음·데이터 변경 정지·원본 보존 | [MainView:57–80](../../../Sources/OpenNoType/Views/MainView.swift#L57) |
| 앱 시작·Keychain 준비 실패와 재시도 | 앱 전역 준비 화면 | 일반 설정 상세가 아니라 작업 불가 이유로 표시 | [MainView:88–102](../../../Sources/OpenNoType/Views/MainView.swift#L88) |

### 5.5 고급 도구 — 실험 기능

| 기존 기능 / 값 | 고급 도구 안 위치 | 노출·보존 계약 | 근거 |
|---|---|---|---|
| `localPreviewEnabled` | 실험 기능 / 녹음 중 미리보기 | 최근 12초 반복 인식, 확정 입력은 전체 재인식, 화자 필터 제약 | [LocalModelOptions:82–84](../../../Sources/OpenNoType/Views/VoiceInputOptionsView.swift#L82) |
| `speakerFilterEnabled`와 화자 모델·등록·재등록·삭제 | 실험 기능 / 내 목소리 구분 | 실사용 미검증·기본 off·모델과 목소리 등록 선행 | [VoiceSettingsView:689–715](../../../Sources/OpenNoType/Views/SettingsView.swift#L689) |
| 음성 비교: 정답 문장·15/30/60초 녹음·파일 선택·지우기 | 실험 기능 / 인식 모델 비교 | 로컬·API 없음·화면 수명 동안 음성 메모리 유지 | [SpeechComparisonLabView:34–79](../../../Sources/OpenNoType/Views/SpeechComparisonLabView.swift#L34) |
| 음성 비교: 모델 선택·상태 새로고침·비교·취소 | 위 인식 모델 비교 | 다운로드된 모델만 순차 비교, 일반 음성 입력과 동시 실행 제한 | [SpeechComparisonLabView:82–103](../../../Sources/OpenNoType/Views/SpeechComparisonLabView.swift#L82) |
| 음성 비교 결과: 준비/인식 시간·CER·숫자·수동 오류 | 위 인식 모델 비교 / 결과 | 정답 없으면 CER 없음. 개인 샘플의 종합 정확도 보장 아님 | [SpeechComparisonLabView:126–155](../../../Sources/OpenNoType/Views/SpeechComparisonLabView.swift#L126) |
| 텍스트 비교: 승인 예시·합성 예시·모델·예산·비교·취소·직접 적용 | 실험 기능 / 정리 모델 비교 | 1–5사례·2–3모델·전송/비용 확인·자동 적용 없음 | [JevModelComparisonView:24–132](../../../Sources/OpenNoType/Views/JevModelComparisonView.swift#L24) |
| `translationRefinementEnabled` | 실험 기능 / 번역 문장 다듬기 | 추가 문장 요청·추가 비용/시간·실패 시 보류 | [TranslationRefinementSettingsView:9–18](../../../Sources/OpenNoType/Views/TranslationRefinementSettingsView.swift#L9) |
| `translationProtectionEnabled` | 실험 기능 / 번역 입력 전 검토 | protect에서만 동작, 다듬기와 독립, 실패 시 보류 | [SettingsView:125–134](../../../Sources/OpenNoType/Views/SettingsView.swift#L125) |
| `jevDetailedReviewEnabled` | 실험 기능 / 문장 검토 자세히 | 숫자·부정·조건·요청·이름 질문 추가 | [JevAssistanceViews:63–65](../../../Sources/OpenNoType/Views/JevAssistanceViews.swift#L63) |
| `jevEconomyEnabled` | 위 문장 검토 자세히 | 원문·결과 완전 동일 등 조건에서 생략. 생략은 검토 통과 아님 | [JevAssistanceViews:66–68](../../../Sources/OpenNoType/Views/JevAssistanceViews.swift#L66) |
| `jevAutomaticImprovementEnabled` | 위 문장 검토 자세히 | protect의 원래 언어 받아쓰기, 보조 모델 별도안, 확인 후 복사 | [JevAssistanceViews:69–71](../../../Sources/OpenNoType/Views/JevAssistanceViews.swift#L69) |
| `jevClarifyEditsEnabled` | 실험 기능 / 음성 수정 도움 | 모호한 지시 확인, 추가 전송·생성 비용, 결과 확인 후 복사 | [JevAssistanceViews:72–74](../../../Sources/OpenNoType/Views/JevAssistanceViews.swift#L72) |
| `jevReRecognitionEnabled` | 실험 기능 / 음성 인식 도움 | 동일 녹음 외부 재전송·비교, 자동 대체 없음. observe도 입력 전 대기 가능 | [JevAssistanceViews:75–77](../../../Sources/OpenNoType/Views/JevAssistanceViews.swift#L75), [SettingsView:136–139](../../../Sources/OpenNoType/Views/SettingsView.swift#L136) |
| `jevFeedbackLearningEnabled`, 저장 유형·삭제 | 실험 기능 / 문장 검토의 학습 자세히 | 암호화된 오류 유형만, 모델별 범위, 개인 사전과 별개 | [JevAssistanceViews:21–53](../../../Sources/OpenNoType/Views/JevAssistanceViews.swift#L21) |
| 검토·교정·비용 한도·보관 정책 안내 | 각 실험 상세의 처리·보관 안내 | 아래 네 모드 차이를 단순화로 지우지 않음 | [SettingsView:141–150](../../../Sources/OpenNoType/Views/SettingsView.swift#L141) |

### 5.6 고급 도구 — 문제 해결

| 기존 기능 | 문제 해결 안 위치 | 노출·보존 계약 | 근거 |
|---|---|---|---|
| 마이크 권한 요청·시스템 설정·상태 | 권한 확인 | 준비가 막히면 홈에서 직접 연결 | [SettingsView:472–480](../../../Sources/OpenNoType/Views/SettingsView.swift#L472) |
| 손쉬운 사용 권한·시스템 설정·새로고침 | 권한 확인 | 실제 관리는 System Settings, 앱 활성화 시 재확인 | [SettingsView:482–496](../../../Sources/OpenNoType/Views/SettingsView.swift#L482) |
| 입력 테스트 준비·5초 뒤 테스트·취소 | 다른 앱 입력 확인 | 실제 테스트 문구 입력 안내, 녹음/API/메시지 전송 없음 | [SettingsView:364–373](../../../Sources/OpenNoType/Views/SettingsView.swift#L364) |
| 입력 진단·최근 처리 시간 | 입력·속도 진단 자세히 | 붙여넣기 뒤 확인 대기를 실제 표시 시각과 구별 | [SettingsView:374–382](../../../Sources/OpenNoType/Views/SettingsView.swift#L374) |
| 단축키 충돌 새로고침 | 단축키 확인 | 녹음·단축키 설정의 같은 액션 재사용 | [SettingsView:324–329](../../../Sources/OpenNoType/Views/SettingsView.swift#L324) |
| Jev 연결 테스트·상태 | AI 연결 확인 | 고정 합성 문장, 비용·사용량 기록 가능, 자동 입력 없음 | [SettingsView:184–189](../../../Sources/OpenNoType/Views/SettingsView.swift#L184) |
| 연결부터 입력까지 확인 | 준비 상태로 이동 | 새 테스트 흐름을 추가하지 않고 기존 준비 경로 재사용 | [SettingsView:493](../../../Sources/OpenNoType/Views/SettingsView.swift#L493) |

## 6. Jev 네 모드와 실패 계약 — UI 단순화 시 변경 금지

[DecisionReviewMode](../../../Sources/OpenNoType/App/Preferences.swift#L4)와 [JevRepairPresentation](../../../Sources/OpenNoType/Views/JevAssistanceViews.swift#L6)의 코드상 안내 계약을 요약했다. 실제 구현 단계에는 `AppModel`의 처리 경로와 함께 재확인해야 하며, 아래 표는 실행 검증 결과가 아니다.

| 저장 값 | 현재 사용자 명칭 | 입력·교정 시점 | 실패·시간 초과·주의 신호 | UI에서 드러낼 차이 |
|---|---|---|---|---|
| `off` | 사용 안 함 | 자동 검토·교정 안 함. 직접 검토와 사전 기능은 가능 | 자동 검토의 실패 정책 없음 | ‘검토 안 함’이 직접 검토 불가라는 뜻이 아님 |
| `observe` | 입력 후 검토·학습 | 음성 재인식 off면 먼저 입력, 뒤에서 검토·강한 신호 시 교정안 한 개와 재검토 | 이미 입력한 글은 바꾸지 않음. 학습은 별도 opt-in | ‘학습’이 무조건 켜진 것으로 보이지 않게 함. 음성 재인식 on이면 첫 판단·필요 재인식을 입력 전에 기다릴 수 있음 |
| `protect` | 입력 전 보호 | 입력 전 최대 `DecisionClient.timeout`초 검토. 자동 교정하지 않음 | 강한 의미 변경은 입력 보류. **일반 받아쓰기의 검토 실패·시간 초과는 기존 결과 입력 + 검토 미완료 표시** | ‘보호’가 모든 실패를 보류하거나 정확도를 보장한다는 의미로 읽히지 않게 함 |
| `repair` | 입력 전 교정 | 입력 전 검토, 강한 오류는 교정 한 번·재검토. 현재 문장 모델 사용 | 키 누락·실패·시간 초과·미해결은 **자동 입력 보류**. 교정 생성 최대 8초, 검토·재검토 각각 timeout | protect와 다른 실패 계약. 최대 한 번 교정·한 번 재검토·비용 한도 보존 |

별도 계약:

- `translationProtectionEnabled`는 **protect에서만** 사용하는 번역 검토이며, 일반 받아쓰기 protect와 달리 **검토 실패·미확인에도 번역 입력을 보류**한다. 번역 결과를 자동 교정하지 않는다. [근거](../../../Sources/OpenNoType/Views/SettingsView.swift#L125)
- `translationRefinementEnabled`는 Jev 검토와 독립인 **추가 문장 생성 요청**이다. 완료하지 못하면 원문·초안을 대신 자동 입력하지 않고 보류한다. Jev 번역 검토와 함께 켜면 다듬은 결과를 검토한다. [근거](../../../Sources/OpenNoType/Views/TranslationRefinementSettingsView.swift#L12)
- 빠른 로컬 받아쓰기는 말한 언어 유지일 때 AI 정리·자동 Jev를 건너뛴다. 번역을 고르면 빠른 로컬이 실제로 적용되지 않는다. [근거](../../../Sources/OpenNoType/App/Preferences.swift#L300)
- 동일 원문/결과의 검토 생략은 검토를 통과한 상태가 아니다. [근거](../../../Sources/OpenNoType/Views/JevAssistanceViews.swift#L66)
- 문장 검토 옵션을 ‘안전/빠름’ 한 개로 합치면 위 계약이 소실된다. UI를 묶더라도 네 저장 값과 동작은 유지한다.

## 7. 기본값·데이터·마이그레이션 보존

기본값의 근거는 [Preferences:33–75](../../../Sources/OpenNoType/App/Preferences.swift#L33)다. UI 정리에서는 신규 설치 기본값도 임의로 변경하지 않는다.

| 항목 | 현재 기본값 | 보존 이유 |
|---|---|---|
| 음성/문장 제공자 | `provider = .openAI`, `textProvider = nil` | nil은 음성 제공자 재사용이라는 기존 의미 |
| 받아쓰기·번역 | `.aiCleanup`, 출력 `.original`, 별도 번역 `English (United States)` | 빠른 모드나 번역으로 자동 전환하지 않음 |
| 단축키·마이크 | `.toggle`, `inputDeviceUID = nil` | 기존 조작·시스템 기본 장치 의미 유지 |
| 알림음·시스템 음소거 | 모두 false | UI 정리만으로 소리/시스템 상태를 변경하지 않음 |
| 로컬 모델·메모리 | `.largeV3`, `.never` | 모델 선택·반응·자원 정책은 별도 결정 |
| 녹음 중 미리보기·화자 필터 | false | 미검증 실험을 기본 동작으로 만들지 않음 |
| 주변 문맥 | 빈 allowlist | 화면 재배치가 외부 전송 권한 확대가 되지 않음 |
| 앱별 설정·표현 | 빈 writingProfiles, `.faithful`/강도 0 | 저장된 사용자 값과 앱별 기존 기본 정책 모두 보존 |
| 기록·자동 사전 학습·사용량 | 모두 true, 보관 30일 | 화면 간 토글 복제로 서로 다른 값 만들지 않음 |
| 자동 Jev·번역 보호·번역 다듬기 | `.off`, false, false | 추가 비용·대기·외부 전송을 자동 활성화하지 않음 |
| Jev 제공자 | `.openRouter` | 명시적으로 선택한 전송 목적지 유지 |
| Jev 상세/절약/개선안/수정 확인/재인식/오류 학습 | 모두 false | 독립된 opt-in을 하나로 묶어 켜지 않음 |
| Jev 이름 후보·보조 모델 | 빈 목록/빈 맵 | 보조 모델 미지정은 현재 문장 모델 재사용 |
| 로그인 실행·화면 | false, `system` | 메뉴바 시작 계약과 기존 화면 값 유지 |
| 앱 언어 | 새 설치 영어, 구형 기존 설정 한국어 | [기존 설정 언어 호환 분기](../../../Sources/OpenNoType/App/Preferences.swift#L101) 보존 |

손상 복구와 보관 정책도 유지한다.

- [필드별 복구](../../../Sources/OpenNoType/App/Preferences.swift#L90): 한 필드가 읽히지 않는다고 전체 설정을 초기화하지 않는다.
- [손상된 보관 기간](../../../Sources/OpenNoType/App/Preferences.swift#L137): 임의의 30일 삭제 정책으로 바뀌지 않고 `-1`로 보호된다.
- [알 수 없는 검토 목적지](../../../Sources/OpenNoType/App/Preferences.swift#L157): 자동 외부 전송을 막기 위해 검토·관련 opt-in이 해제되는 보호를 유지한다.
- `usageAccountingIncomplete`, `recoveryState`, 원본 복구 데이터는 사용자에게 새로운 설정처럼 노출하지 않는다. 필요한 상태 안내로만 연결한다.
- [CodingKeys](../../../Sources/OpenNoType/App/Preferences.swift#L77), enum rawValue, 제공자별 모델 저장, Keychain 식별자를 탐색 개편과 함께 변경하지 않는다.
- 기록 off·전체 삭제의 Jev/진단/학습 연동과, 개인 사전·실패 녹음·사용량의 독립 삭제 범위를 단순화 명목으로 바꾸지 않는다.

## 8. 명칭 제안과 의미 차이

아래는 표시 문구 제안이다. 식별자와 저장값을 변경하는 제안이 아니다.

| 현재 명칭 | 제안 | 피해야 할 오해 |
|---|---|---|
| 빠른 로컬 받아쓰기 | 빠르게 입력 · 이 Mac | 혼용 정확도·숫자 보존이 보장된다는 표현 금지 |
| 정리해서 입력 | 문장 정리 후 입력 | 음성 인식 위치와 문장 API 처리를 구별 |
| 현재 받아쓰기(표현) | 말한 내용 유지 | raw/verbatim은 아님. 기존 말실수·반복 정리 유지 |
| Jev 문장 검토 | 문장 검토 · 실험 | 상세에서는 실제 Jev/제공자·전송 목적지 표시 |
| 입력 후 검토·학습 | 입력 후 검토 | 학습은 별도, 재인식에 따른 사전 대기 예외 표시 |
| 입력 전 보호 | 입력 전 확인 | 일반 검토 실패 시 기존 결과가 입력될 수 있음 |
| 입력 전 교정 | 입력 전 검토·교정 | 완료 못 하면 자동 입력 보류 |
| 앱·프로젝트 이름 후보 | 검토에 참고할 이름 | 실제 개인 사전 매핑과 구별 |
| 음성 모델 / 내 음성으로 모델 비교 | 음성 인식 / 인식 모델 비교 | 일상 설정과 실험 비교를 구별 |
| 내 문장으로 모델 비교 | 정리 모델 비교 | 음성 인식 정확도 비교가 아님 |

## 9. 병행 작업과 충돌을 줄이는 적용 경계

현재 문서는 설계 산출물이며 구현을 시작한 것이 아니다. 후속 구현은 다음 경계를 추천한다.

1. **화면 담당**은 새 섹션 View·공통 행·상태 요약·탐색 어댑터를 맡는다. 기존 preference와 action을 읽고 호출하는 얇은 화면으로 만든다.
2. **기능 담당**은 `Preferences`, `AppModel`, 오디오·단축키·전사·붙여넣기·Jev 계약을 계속 맡는다. UI 재정비 때문에 같은 파일의 광범위한 정리나 이름 변경을 함께 하지 않는다.
3. `SettingsView.swift`, `VoiceInputOptionsView.swift`, `MainView.swift` 등 이미 기능 개발과 겹치는 파일은 변경 주체를 먼저 정한다. 새 View 추출을 준비하되 연결 지점 수정은 소유자와 합의한 시점에 한다.
4. 설계 시안은 UI의 선택·탐색을 검토하는 자료다. 시안의 연결 상태·결과·비용·시간은 실제 앱 기능의 동작 증거가 아니다.
5. 실제 연결 후에는 기존 데이터가 있는 상태에서 네 주요 탐색과 모든 이동표 목적지에 도달하는지 확인한다. 모델 다운로드나 유료 요청이 단순 화면 진입만으로 발생해서는 안 된다.
6. 최소 검증은 ‘설정 변경 전후 값 보존’, ‘키 준비 필요 상세 노출’, ‘번역/빠른 모드/표현/검토 적용 상태’, ‘네 Jev 실패 계약 문구’, ‘복구·사용량·실험 도구 접근 유지’, ‘hold/toggle 안내 일치’로 잡는다. 실제 기능별 테스트는 해당 기능 담당의 기존 검증에 연결한다.

가장 먼저 할 정리는 **받아쓰기의 유효 상태를 짧게 보여주는 것**, **모델 준비를 하나의 목적지로 연결하는 것**, **실험과 진단을 고급 도구의 별도 두 그룹으로 분리하는 것**이다. 이 세 변화는 동작 계약을 바꾸지 않으면서 화면의 목적을 선명하게 만들 수 있다.

## 10. 사용자 추가 방향 — 옵션별 `?` 도움말

사용자는 설정의 긴 설명을 매번 읽기보다, 필요한 옵션의 라벨 옆 `?` 버튼을 눌러 별도로 보기를 원한다. 이에 따라 설정은 짧은 그룹별 행으로 구성하고, 각 행은 **라벨 → `?` → 현재값/조작 → 짧은 상태** 순서로 읽히게 한다. 이 변경은 설명의 위치를 바꾸는 것이며 기존 옵션의 적용 조건·기본값·실패 계약을 변경하는 것이 아니다.

### 10.1 기본 화면과 도움말의 세부 분리

| 정보 | 기본 화면 | `?` 도움말 또는 기존 확인창 | 예시와 예외 |
|---|---|---|---|
| 옵션 이름·현재값 | 항상 표시 | 도움말에도 같은 제목 사용 | `받아쓰기 언어  ?     말한 언어 유지` |
| 기능의 일반 설명 | 반복 문단 제거 | 짧은 목적 설명 | 받아쓰기 출력 언어와 인터페이스 언어가 다른 개념임을 도움말에서 설명 |
| 적용 범위 | 상태에 필요한 부분만 한 줄 | 전체 작업 범위와 적용 시점 | ‘다음 녹음부터 적용’은 변경 직후 짧게 표시 가능 |
| 현재 미적용 이유 | **기본 화면에 남김** | 원인·설정 관계의 상세 | `번역 중에는 표현 설정을 적용하지 않아요`, `빠르게 입력에는 AI 표현을 적용하지 않아요` |
| 입력 보류·실패의 현재 원인 | **기본 화면/작업 결과에 남김** | 일반 실패 정책과 복구 상세 | `Jev 키가 없어 입력을 보류했어요`를 `?`를 열어야 알 수 있게 만들지 않음 |
| 키·모델·권한 준비 안 됨 | **기본 화면에 짧은 상태와 준비 동작** | 연결 방법·조건의 상세 | `모델 준비 필요 · 준비`, `API 키 필요 · 연결 설정` |
| 추가 요청 발생 여부 | 켜진 옵션 옆 **추가 요청** 표식 | 횟수·전송 내용·대상·비용과 시간 영향 | 번역 다듬기 on이면 `실험 · 추가 요청`; 비용액이나 정확도 개선 수치를 만들어 표시하지 않음 |
| 일반적인 실패 계약 | 실제 실패 중이 아닐 때 긴 문단 제거 | 모드별 정확한 처리와 입력 보류/기존 결과 입력의 차이 | protect와 repair를 같은 말로 설명하지 않음 |
| 데이터 전송·보관의 일반 설명 | 상태 요약만 | 기능에 필요한 전송·보관 범위 | 개인정보 페이지는 전송 정보 요약을 별도로 유지 |
| 실제 유료 전송·삭제 동의 | 실행 직전 기존 확인을 유지 | 도움말은 참고일 뿐 승인 대체 아님 | Jev 수동 검토·모델 비교·파일 삭제 확인창 유지 |
| 현재 진행·취소·오류 | **기본 화면에 남김** | 원인 상세가 필요하면 추가 도움말 제공 | 처리 중이라는 사실과 취소 버튼을 `?` 안으로 옮기지 않음 |
| 예시 비교·실제 설정 변경 | 별도의 명시적 동작 | `?` 안에서 설명하고 기존 예시창으로 이동 가능 | `?`를 누르는 행위 자체가 적용·다운로드·API 요청을 실행하지 않음 |

### 10.2 현재 받아쓰기 설정에 적용할 도움말 6개

다음 여섯 항목은 사용자가 제시한 설정 화면을 간결하게 만드는 우선 대상이다. 각 팝오버는 필요할 때만 **무엇을 하는지 / 언제 적용되는지 / 실패하면 어떻게 되는지 / 전송·추가 비용** 순서로 설명한다. 해당하지 않는 항목은 억지로 채우지 않는다. 탐색 구조의 주 관리 위치는 5절 이동표를 유지하며, 다른 화면의 요약행도 같은 상태를 읽고 같은 도움말로 연결한다.

| 옵션의 `?` 제목 | 기본 행에 남길 것 | 눌렀을 때 읽을 내용 | 상태 표시와 주의 |
|---|---|---|---|
| 받아쓰기 언어란? | 현재 언어·언어 선택/예시 동작 | 평소 받아쓰기 단축키의 출력 언어. 말한 언어 유지와 번역의 차이, 별도 번역 단축키 언어와의 구분. 번역은 AI 문장 처리를 사용하며 다음 녹음부터 적용 | 번역 선택으로 빠른 로컬·표현 설정이 미적용이면 관련 행에 짧은 이유 표시. 예시만 보아도 적용된다고 오해하지 않게 함 |
| 번역 문장 다듬기란? | on/off·실험·켜진 경우 추가 요청 | 받아쓰기 번역과 별도 번역에 적용. 원문·초안·목표 언어·말투·사전 힌트를 현재 문장 서비스로 한 번 더 보냄. 추가 시간·비용 가능. Jev 검토와 독립이며 실패하면 원문/초안을 대신 자동 입력하지 않고 보류 | 현재 다듬기 실패로 보류한 상태는 팝오버에만 숨기지 않음. 꺼짐이라는 이유로 기능 설명까지 비활성화하지 않음 |
| 표현 방식이란? | 선택 방식·예시 비교 | 원래 언어 받아쓰기에 적용하는 문장 표현 방향. ‘말한 내용 유지’는 기존 정리 방식이며 raw 전사가 아님. 요약/간결/명확/자세/창의 표현의 차이와 새 사실을 추가하지 않는 계약 | 번역 중 또는 빠른 로컬이면 적용되지 않는 이유를 기본 행에 표시하고 저장된 선택은 유지 |
| AI 편집 강도란? | 슬라이더·현재 수치·간단한 단계명 | 선택한 표현 방향 안에서 표현을 바꾸는 정도. 음성 인식 정확도나 모델 선택을 바꾸는 값이 아님. 0 또는 faithful는 기존 정리 유지. 방향을 새로 고를 때 기존 40 진입 동작 유지 | faithful에서 강도를 사용할 수 없는 이유를 기본 화면에 짧게 표시. 강도가 높아도 숫자·이름·조건·의도를 바꿀 권한은 생기지 않음 |
| 번역 단축키 언어란? | 별도 번역 단축키의 현재 대상 언어 | 별도 번역 단축키로 녹음할 때 사용하는 언어이며 평소 받아쓰기 출력 언어와 독립. 문장 AI 처리를 사용하고 번역 다듬기·Jev 번역 검토가 켜져 있으면 해당 추가 처리 적용 | 두 언어 값을 자동으로 동기화하지 않음. 관련 추가 처리가 켜져 있으면 짧은 현재 상태 표시 |
| 앱별 작성 방식이란? | 사용자 설정 개수·앱별 설정 열기/추가 | 녹음을 시작한 앱에 맞는 형식·말투. 기본은 말한 반말/존댓말 유지. 브라우저 사이트·대화 상대를 판단하지 않으며 주변 문맥 허용과 독립. 번역/프롬프트 등의 적용 범위는 해당 작업 계약을 따름 | “설정한 앱이 없음”과 “기존 앱별 기본 정책이 없음”을 같게 설명하지 않음. 이 화면 진입만으로 주변 텍스트 접근을 허용하지 않음 |

### 10.3 도움말 상호작용·접근성

- 마우스 hover에만 의존하지 않는다. `?`는 실제 버튼이며 클릭·키보드 Space/Enter·VoiceOver로 연다. 접근성 이름은 `받아쓰기 언어 도움말`처럼 옵션을 포함한다.
- 버튼은 라벨 바로 옆 같은 위치에 두고 충분한 클릭 영역과 명확한 키보드 포커스를 제공한다. 값 조작과 혼동되지 않게 한다.
- 팝오버는 해당 행에 붙여 열고 제목과 본문을 읽을 수 있게 한다. Esc·바깥 클릭·닫기로 닫으며 닫힌 뒤 해당 `?`로 포커스를 돌린다.
- 다른 옵션 도움말을 열면 이전 것은 닫는다. 한 번에 한 설명만 읽을 수 있게 한다.
- 비활성화된 설정도 **도움말은 열 수 있어야 한다**. 예를 들어 번역 때문에 표현 설정 조작이 중지되어도 `?`는 비활성화하지 않는다. 행 전체를 disable해 설명까지 막는 방식은 피한다.
- 도움말을 열거나 닫는 행위는 설정 저장·모델 준비·다운로드·외부 전송·비용 발생·녹음 시작을 수행하지 않는다.
- 예시 비교는 기존 별도 창을 재사용한다. 설명 팝오버에서 예시창으로 이동하더라도 미리보기와 실제 적용은 구분한다.

### 10.4 후속 구현의 최소 확인 항목

1. 받아쓰기 옵션 아래에 긴 상시 설명이 남지 않고 각 `?`에서 필요한 설명을 읽을 수 있다.
2. 현재값·미적용 이유·키/모델 준비 필요·입력 보류·추가 요청 표식은 도움말을 열지 않아도 보인다.
3. 키보드와 VoiceOver로 비활성화된 옵션의 도움말까지 열고 닫을 수 있다.
4. 팝오버 열기·닫기로 preference 값이나 네트워크 요청 수가 변하지 않는다.
5. 일반 실패 계약은 읽기 쉬워지되 6절의 네 Jev 모드·번역 보호·다듬기의 차이를 잃지 않는다.
6. 설명의 문구·현재 상태 요약·실제 조건은 같은 기능 계약에서 파생하여 서로 모순되지 않게 한다.
