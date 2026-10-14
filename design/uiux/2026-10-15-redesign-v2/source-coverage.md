# 전체 화면·소스 대조표

기준 커밋 `d620ada3bf849f8ecae4948716089cedb08fa5a5`. 현재 주요 UI View와 부속 표현을 소스에서 추출해 새 설계에 대응시켰다. 이 표의 “매핑”은 설계 대상 포함을 뜻하며 실제 SwiftUI 구현 완료가 아니다.

## View 전체 매핑

현재 추출된 **49개 View/NSViewRepresentable 선언**, **23개 소스 파일**을 빠짐없이 배정했다. 내부 state binding·예시 데이터·플랫폼 처리 파일은 아래 별도 보존 대상이다.

| 현재 소스·선언 | 담당 | 새 화면·공통 요소 |
|---|---|---|
| [HistoryView](../../../Sources/OpenNoType/Views/DataViews.swift:6) | C | `history, history-empty, history-search-empty` |
| [HistoryEntryCard](../../../Sources/OpenNoType/Views/DataViews.swift:49) | C | `history, history-reprocess, history-delete` |
| [DictionaryView](../../../Sources/OpenNoType/Views/DataViews.swift:198) | C | `dictionary, dictionary-entry, dictionary-learning, dictionary-names, dictionary-import` |
| [RecoveryView](../../../Sources/OpenNoType/Views/DataViews.swift:413) | C | `recovery, recovery-empty, recovery-current` |
| [DataPageHeading](../../../Sources/OpenNoType/Views/DataViews.swift:562) | 메인/C | `공통 PageHeader` |
| [DataSearchField](../../../Sources/OpenNoType/Views/DataViews.swift:573) | 메인/C | `history, dictionary` |
| [DataEmptyState](../../../Sources/OpenNoType/Views/DataViews.swift:589) | 메인/C | `*-empty` |
| [DictationExpressionExamplesView](../../../Sources/OpenNoType/Views/DictationExpressionExamplesView.swift:5) | B | `expression-examples` |
| [DictationExpressionSettingsView](../../../Sources/OpenNoType/Views/DictationExpressionSettingsView.swift:4) | B | `settings-dictation` |
| [DictationTranslationExamplesView](../../../Sources/OpenNoType/Views/DictationTranslationExamplesView.swift:5) | B | `language-examples` |
| [DictationTranslationSettingsView](../../../Sources/OpenNoType/Views/DictationTranslationSettingsView.swift:4) | B | `settings-dictation` |
| [JevFeedbackLearningSettingsView](../../../Sources/OpenNoType/Views/JevAssistanceViews.swift:21) | B | `jev-learning, jev-clear-confirm` |
| [JevAssistanceSettingsView](../../../Sources/OpenNoType/Views/JevAssistanceViews.swift:78) | B | `jev-assistance` |
| [JevNameCatalogView](../../../Sources/OpenNoType/Views/JevAssistanceViews.swift:157) | C | `dictionary-names, name-discovery-confirm` |
| [JevNameDiscoveryButton](../../../Sources/OpenNoType/Views/JevAssistanceViews.swift:237) | C | `dictionary-names, name-discovery-confirm` |
| [JevAssistanceResultsView](../../../Sources/OpenNoType/Views/JevAssistanceViews.swift:274) | A | `edit-clarify, rerecognition, alternative` |
| [JevEditClarificationView](../../../Sources/OpenNoType/Views/JevAssistanceViews.swift:287) | A | `edit-clarify` |
| [JevReRecognitionView](../../../Sources/OpenNoType/Views/JevAssistanceViews.swift:343) | A | `rerecognition` |
| [JevModelComparisonView](../../../Sources/OpenNoType/Views/JevModelComparisonView.swift:5) | C | `text-lab, text-lab-confirm, text-lab-results` |
| [JevReviewRequestButton](../../../Sources/OpenNoType/Views/JevReviewView.swift:5) | A | `review-confirm, translation-review-confirm` |
| [JevReviewView](../../../Sources/OpenNoType/Views/JevReviewView.swift:68) | A | `review, review-failed, translation-review` |
| [JevDictionaryUndoView](../../../Sources/OpenNoType/Views/JevReviewView.swift:194) | A | `review` |
| [JevComparisonView](../../../Sources/OpenNoType/Views/JevReviewView.swift:214) | A | `review, review-proposal` |
| [JevImprovementView](../../../Sources/OpenNoType/Views/JevWorkflowView.swift:4) | A | `alternative-confirm, alternative` |
| [JevCorrectionReviewView](../../../Sources/OpenNoType/Views/JevWorkflowView.swift:60) | A | `candidate-review-confirm, candidate-review, candidate-save-confirm` |
| [MainView](../../../Sources/OpenNoType/Views/MainView.swift:16) | 메인 | `모든 화면 셸` |
| [Surface](../../../Sources/OpenNoType/Views/MainView.swift:175) | 메인 | `system-components` |
| [NoticeView](../../../Sources/OpenNoType/Views/MainView.swift:189) | 메인 | `system-components, home-failed` |
| [HomeView](../../../Sources/OpenNoType/Views/MainView.swift:203) | A | `home-*` |
| [OptionHelp](../../../Sources/OpenNoType/Views/OptionHelp.swift:13) | 메인 | `모든 data-help` |
| [OptionHelpLabel](../../../Sources/OpenNoType/Views/OptionHelp.swift:132) | 메인 | `system-components` |
| [OptionToggle](../../../Sources/OpenNoType/Views/OptionHelp.swift:150) | 메인 | `system-components` |
| [PromptCompositionResultView](../../../Sources/OpenNoType/Views/PromptCompositionResultView.swift:5) | A | `prompt-result, prompt-held, prompt-edit-source` |
| [PromptCompositionReviewSummaryView](../../../Sources/OpenNoType/Views/PromptCompositionResultView.swift:211) | A | `prompt-result, prompt-held` |
| [ProviderModelPicker](../../../Sources/OpenNoType/Views/ProviderModelPicker.swift:47) | B | `api-connection, models` |
| [SettingsView](../../../Sources/OpenNoType/Views/SettingsView.swift:6) | B | `settings-*` |
| [KeyManagementDisclosure](../../../Sources/OpenNoType/Views/SettingsView.swift:750) | B | `api-connection, key-delete-confirm` |
| [VoiceSettingsView](../../../Sources/OpenNoType/Views/SettingsView.swift:768) | B | `models, speaker-setup` |
| [SpeechComparisonLabView](../../../Sources/OpenNoType/Views/SpeechComparisonLabView.swift:4) | C | `speech-lab, speech-lab-results` |
| [SpeechComparisonResultView](../../../Sources/OpenNoType/Views/SpeechComparisonLabView.swift:126) | C | `speech-lab-results` |
| [TranslationRefinementResultView](../../../Sources/OpenNoType/Views/TranslationRefinementResultView.swift:4) | A | `translation-result, translation-review` |
| [TranslationRefinementSettingsView](../../../Sources/OpenNoType/Views/TranslationRefinementSettingsView.swift:4) | B | `settings-dictation` |
| [UpdateSettingsView](../../../Sources/OpenNoType/Views/UpdateSettingsView.swift:4) | B | `settings-general` |
| [UsageView](../../../Sources/OpenNoType/Views/UsageView.swift:6) | C | `usage, usage-empty, usage-reset` |
| [VoiceBar](../../../Sources/OpenNoType/Views/VoiceBar.swift:27) | A | `hud` |
| [VoiceInputOptionsView](../../../Sources/OpenNoType/Views/VoiceInputOptionsView.swift:4) | B | `settings-recording, settings-dictation` |
| [LocalModelOptionsView](../../../Sources/OpenNoType/Views/VoiceInputOptionsView.swift:94) | B | `models, model-detail, model-delete-confirm` |
| [ManagerWindowContent](../../../Sources/OpenNoType/App/OpenNoTypeApp.swift:102) | 메인 | `모든 화면 셸` |
| [ManagerWindowAccessor](../../../Sources/OpenNoType/App/AppWindows.swift:86) | 메인 | `창 시작·다시 열기` |

## View 외 UI 계약과 부속 표면

| 현재 근거 | 새 설계 위치·보존할 동작 |
|---|---|
| [StatusBarController.rebuildMenu](../../../Sources/OpenNoType/App/StatusBarController.swift:79) | `menubar` · 메뉴 항목·상태·현재 작업 취소·설정 진입·종료 계약 |
| [OpenNoTypeApp.Scene / Commands](../../../Sources/OpenNoType/App/OpenNoTypeApp.swift:29) | 공통 셸 · 창 기본 크기·메뉴 명령·다시 열기·메뉴바만 시작 |
| [VoiceBarController](../../../Sources/OpenNoType/Views/VoiceBar.swift:6) | `hud` · 비활성 패널·모든 Space·미리보기·카운트다운·경고 |
| [MainView.preferencesRecovery](../../../Sources/OpenNoType/Views/MainView.swift:65) | `home-storage-recovery` · 설정 복구·보관 정책 확인·원본 보존 |
| [MainView.startupStatus](../../../Sources/OpenNoType/Views/MainView.swift:90) | 준비 중/실패 표시 · 실제 Keychain·잠금·복구 중 데이터 변경 금지 |
| [SettingsNavigation](../../../Sources/OpenNoType/App/SettingsNavigation.swift) | 기존 설정 진입을 새 6분류로 매핑, 저장 데이터 형식 보존 |
| [JevModelComparisonCaseBindings](../../../Sources/OpenNoType/Views/JevModelComparisonCaseBindings.swift) | `text-lab` · 사례 수정 시 정답 승인 무효화·실행 중 수정 제한 |
| [DictationExpressionExamples](../../../Sources/OpenNoType/Views/DictationExpressionExamples.swift) / [DictationTranslationExamples](../../../Sources/OpenNoType/Views/DictationTranslationExamples.swift) | 언어·표현 비교 · 실제 정적 예시와 적용 범위 유지 |
| `.confirmationDialog` 16개 선언 (코드 기준) | 아래 확인·동의 대상 표로 대조. HTML 시안은 전송/삭제하지 않음 |
| NSOpenPanel / NSSavePanel / 시스템 권한 / Sparkle 표준 창 | 시스템 고유 표면을 커스텀 웹 폼으로 대체하지 않음. 앱 쪽 진입·설명·진행·오류 규격만 통일 |

## 확인·동의·편집 대상

설계 시안의 부속 화면은 비교하기 쉽도록 같은 관리 창 안에 표시된다. 실제 구현에서는 규격서의 sheet/popover 크기와 원래 확인 정책을 사용한다. 모든 HTML 부속 화면을 독립 네이티브 윈도로 만드는 제안이 아니다.

| 대상 | 새 설계의 진입/상태 |
|---|---|
| 전체 기록 삭제 | `history-delete` · 개수와 되돌릴 수 없음 명시 |
| 단일 기록/녹음 삭제 | 해당 상세 더보기 · 기존 확인 범위 유지, 새 확인의 필요성은 기존 동작에 맞춤 |
| 사전 가져오기 | `dictionary-import` · 유효/제외/기존 유지·확인 |
| 사전 추가/수정·학습 되돌리기·이름 후보 | `dictionary-entry`, `dictionary-learning`, `dictionary-names`, `review` |
| 당시/현재 설정으로 녹음 재처리 | `recovery`, `recovery-current` · 전송·보존 기간 차이 |
| 로컬 모델 파일 삭제 | `model-delete-confirm` · 파일과 메모리, 재다운로드·실행 중 제한 |
| 저장 키 삭제 | `key-delete-confirm` · 제공자와 영향 |
| 오류 유형 학습 초기화 | `jev-clear-confirm` · 사전·문장 기록과 구분 |
| Jev 수동 검토·교정·개선안·재인식·이름 찾기 | `review-confirm`, `review-proposal`, `alternative-confirm`, `rerecognition`, `dictionary-names, name-discovery-confirm` |
| 번역 수동 검토 | `translation-review-confirm`, `translation-review` · 번역 목적과 문장 보존 |
| 문장 모델 비교 전송 | `text-lab-confirm` · 승인 정답·서비스·비용·예산·중단 |
| 사용량 초기화 | `usage-reset` · 통계와 실제 청구 내역·기록 분리 |
| 복구 설정 저장 | `home-storage-recovery` · 실제 복구안·보관 기간 확인 |

## 상태 누락을 막는 검토

- 주요 페이지의 기본/빈 값/검색 결과 없음과 첫 사용/준비/작업/보류/오류/확인 불가를 구분한다.

- 모델 준비·다운로드·파일 삭제·메모리 해제는 서로 다른 작업이며 다운로드 중간 상태·중단·재개·저장 모델 탐색은 설정 문서의 행별 목록으로 확인한다.

- 원음·문장·통계·비교 결과의 저장 수명과 전송 여부를 같은 “기록” 레이블로 합치지 않는다.

- 한영 긴 문구·다크·작은 창·키보드·도움말의 실제 검증은 verification.md에 적은 범위만 증거로 취급한다.

기본 화면·부속 상태 전체 목록은 [screen-catalog.json](screen-catalog.json), 분야별 세부 기능 매핑은 [A](primary-flow.md) / [B](settings-architecture.md) / [C](data-workflows.md) 문서를 참조한다.
