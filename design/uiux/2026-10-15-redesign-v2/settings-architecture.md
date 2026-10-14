# 설정·음성 모델 전체 재설계 명세

작성일: 2026-10-15. 대상은 현재 체크아웃의 실제 앱이다. 이 문서는 설계와 브라우저 시안 명세이며 앱 구현 완료를 뜻하지 않는다. 앱 코드·설정·저장소 데이터·설치·배포는 변경하지 않았다. [시안 화면 코드](settings-screens.js), [공통 설계 시스템](design-system.md), [검토 안내](README.md)를 함께 본다.

## 이번 설계의 범위와 판단 근거

0.2.9는 긴 문단을 도움말로 옮겼지만, 공통 `Surface`가 22pt 패딩·18pt 내부 간격·14pt 모서리를 쓰고, 메인 콘텐츠에 다시 30pt 패딩을 준다. 설정 제목·분류 설명·카드 제목·옵션 도움말이 겹쳐 화면당 옵션이 적게 보인다. 예시 시트도 고정 760×610pt 안에 큰 여백과 설명을 반복한다. 이름만 줄이는 것으로 해결하지 않고 창·행·컨트롤·부속 화면의 치수를 함께 재정의한다.

실제 근거: [MainView.swift:21](../../../Sources/OpenNoType/Views/MainView.swift#L21), [MainView.swift:175](../../../Sources/OpenNoType/Views/MainView.swift#L175), [SettingsView.swift:47](../../../Sources/OpenNoType/Views/SettingsView.swift#L47), [DictationTranslationExamplesView.swift:78](../../../Sources/OpenNoType/Views/DictationTranslationExamplesView.swift#L78), [DictationExpressionExamplesView.swift:71](../../../Sources/OpenNoType/Views/DictationExpressionExamplesView.swift#L71). 사용자가 제공한 2026-10-15 07:48:59 스크린샷에서도 넓은 선택 메뉴와 카드 사이 간격을 확인했다.

설계 원칙은 옵션마다 `이름 + ? + 현재 값/컨트롤`을 같은 행에 두는 것이다. 일반 설명은 ?로 이동한다. 현재 작업을 막는 이유, 설정이 켜져 있으나 미적용인 이유, 추가 요청·비용·외부 전송은 짧게 기본 화면에 남긴다. 설명을 접는 것과 실패 계약을 숨기는 것을 구분한다.

## 치수와 밀도

| 요소 | 현재 코드 | v2 명세 | 이유 |
|---|---|---|---|
| 앱 사이드바 | 212pt | 208pt | 창의 작업 영역 확보 |
| 앱 툴바 | 높이 56pt, 가로 패딩 30pt | 높이 52pt, 가로 패딩 24pt | 전체 앱의 기준선 통일 |
| 콘텐츠 | 패딩 30pt, 최대 920pt | 패딩 24pt, 최대 1184pt | 목록·비교·부속 화면까지 같은 규칙 적용 |
| 큰 설정 제목 | 24pt, 모델 화면 23pt | 22pt | 페이지 제목 한 번만 표시 |
| 섹션 제목 | Surface 14pt + 독립 카드 헤더 | 기본 15pt, 묶음 내부 소제목 12pt | 카드 수를 늘리지 않고 관련 옵션 구분 |
| 패널 | 패딩 22pt, 간격 18pt, 반경 14pt | 패딩 16pt, 패널 간격 16pt, 반경 10pt | 한 옵션당 카드 금지 |
| 기본 옵션 행 | Surface의 18pt 간격과 컨트롤 높이의 합 | 최소 44pt | 행을 훑기 쉬운 일정한 리듬 |
| 현재 경고가 있는 행 | 문단 길이에 따라 가변 | 최소 56pt, 경고는 한 줄 우선 | 실수 방지 정보는 접지 않음 |
| 컨트롤 | 화면별 임의 폭 | 높이 32pt, 주요 실행 36pt | 옵션과 실행 버튼의 위계 분리 |
| 메뉴·입력 열 | 일부 메뉴 폭 무제한, 일부 180/100/160pt | 값 열 240pt, 메뉴 최대 280pt | 긴 선택지 때문에 모든 행 폭이 변하지 않음 |
| 메뉴 + 예시 버튼 | 서로 독립된 넓은 요소 | 메뉴 168pt + 예시 약 64pt + 간격 8pt | 240pt 값 열에서 한 줄 유지 |
| 도움말 | 새 공통 컴포넌트가 있으나 배치 혼재 | 투명 28×28pt 버튼, 라벨과 4pt 간격 | 버튼은 키보드·VoiceOver로도 접근 |
| 강도 슬라이더 | 행 안에서 숫자가 줄바꿈될 수 있음 | 240pt의 nowrap 묶음, 숫자 24pt | 값이 다음 행으로 내려가지 않음 |
| 예시 시트 | 고정 760×610pt | 목표 720×520pt, 최소 640×480pt, 본문만 스크롤 | 예시 선택·비교·적용이 한 구조로 보임 |

4/8/12/16/24/32pt 간격 토큰을 사용한다. 고정 행 높이는 긴 앱 이름·영어·확대 글꼴을 잘라 버리라는 뜻이 아니다. 라벨이 길거나 현재 오류가 길면 행을 늘리되 컨트롤 열은 유지한다. HTML은 각 시트를 화면 단위로 검토하게 펼쳐 두었으며 실제 SwiftUI에서는 위의 시트 크기와 고정 하단 액션을 사용한다. 브라우저 CSS px는 시안 측정값이며 native pt 결과는 실제 앱 적용 후 별도 확인해야 한다.

`settings-dictation`은 9개 행을 카드 하나의 3개 소그룹으로 묶는다. 정상 상태의 상단 요약 callout·설정 eyebrow·꺼짐 중복 설명을 없앤다. 선택 메뉴 자체로 현재 값을 파악한다. 활성 검토의 실패 계약과 fast+번역 미적용은 계속 해당 행에 표시한다.

## 목적별 설정 구조

| 목적지 | 기본 화면에서 보이는 그룹 | 상세·실험·진단 경로 |
|---|---|---|
| 받아쓰기 | 입력 방식 / 문장과 말투 / 번역과 검토 | 언어 예시, 표현 예시, 앱별 작성 방식, Jev 검토, 현재 로컬 모델 |
| 녹음·단축키 | 녹음 / 작업별 단축키 | 새 단축키 입력·충돌, 입력 진단 |
| AI 연결 | 음성 인식 / 문장 처리 / 검토와 비용 | 각 서비스 키·모델, 로컬 모델, Jev 연결, 사용량 |
| 개인정보 | 기록과 보관 / 전송과 문맥 / 학습과 통계 | 주변 문맥 허용 앱, 개인 사전의 교정 학습, 녹음 복구, 추가 전송 옵션 |
| 앱 관리 | 앱과 화면 / 업데이트 / 정보 | 로그인 항목 시스템 설정, 공개 릴리스, 업데이트 상태, 모델 라이선스 |
| 고급 도구 | **실험 기능** / **문제 해결** | 실험: 미리보기·화자·번역 다듬기·Jev 추가 도움·두 모델 비교. 문제 해결: 권한·입력 테스트·시간 진단·Jev 연결 테스트 |

같은 설정을 여러 화면에서 찾더라도 저장값·상세 목적지는 하나다. 예: 받아쓰기 처리의 모델 준비 링크와 AI 연결의 로컬 모델 링크는 같은 모델 상세로 이동한다. 번역 다듬기는 받아쓰기와 고급 도구에 진입점이 있지만 동일한 `translationRefinementEnabled`를 사용한다. 주변 문맥과 앱별 작성 방식은 별개로 유지한다.

## 전체 옵션·행동의 새 위치 매핑

아래에는 설정과 음성 모델 영역의 모든 저장 필드 및 실제 액션을 포함한다. 사전·기록·사용량·검토 결과·두 비교 화면의 세부 설계는 다른 담당 화면에 연결하고, 이 문서에서는 진입을 보장한다. 근거의 행 번호는 설계 시점의 현재 소스 기준이다.

| 현재 필드·실제 기능 | 새 위치 / 접근 경로 | 화면·상태 규칙 | 실제 근거 |
|---|---|---|---|
| `dictationProcessing` AI 정리 / 빠른 로컬 | 설정 → 받아쓰기 → 처리 | 원래 언어일 때만 fast 유효. 번역 시 저장된 fast를 지우지 않음 | [VoiceInputOptionsView:17](../../../Sources/OpenNoType/Views/VoiceInputOptionsView.swift#L17) |
| `dictationOutputLanguage` 원래 언어 + 6종 출력 | 받아쓰기 → 출력 언어 | 말한 언어 유지·미국/영국 영어·한국어·일본어·간/번체. 번역 단축키 값과 독립 | [SettingsView:86](../../../Sources/OpenNoType/Views/SettingsView.swift#L86) |
| 출력 언어 예시·선택·취소·명시 적용 | 출력 언어 → 예시 | 미리보기만으로 값 변경 금지. 적용할 때만 현재 설정 변경 | [언어 예시:68](../../../Sources/OpenNoType/Views/DictationTranslationExamplesView.swift#L68) |
| `dictationExpression.style` 6종 | 받아쓰기 → 표현 방식 | fast·번역에는 컨트롤 비활성, 기존 선택은 보존, ?는 활성 | [표현 설정:68](../../../Sources/OpenNoType/Views/DictationExpressionSettingsView.swift#L68) |
| `dictationExpression.strength` 0~100 | 받아쓰기 → AI 편집 강도 | faithful는 0, 다른 표현을 0에서 고르면 40. 0은 AI 정리 전체 끄기가 아님 | [표현 설정:90](../../../Sources/OpenNoType/Views/DictationExpressionSettingsView.swift#L90) |
| 표현 예시·선택·취소·명시 적용 | 표현 방식 → 예시 | 비활성 상태에서도 읽기 가능, 적용 버튼만 비활성. 예시 값은 로컬 보류값 | [표현 예시:74](../../../Sources/OpenNoType/Views/DictationExpressionExamplesView.swift#L74) |
| `targetLanguage` 별도 번역 단축키 6종 | 받아쓰기 → 번역 단축키 언어 | 일반 받아쓰기 출력 언어와 독립 | [SettingsView:348](../../../Sources/OpenNoType/Views/SettingsView.swift#L348) |
| `translationRefinementEnabled` | 받아쓰기 → 번역 문장 다듬기 / 고급 도구 → 실험 | 동일 설정. ON이면 추가 요청 1회·실패 시 보류 노출 | [SettingsView:88](../../../Sources/OpenNoType/Views/SettingsView.swift#L88), [TranslationRefinementSettingsView](../../../Sources/OpenNoType/Views/TranslationRefinementSettingsView.swift) |
| `writingProfiles` 앱 목록·추가·형식5종·말투4종·복원 | 받아쓰기 → 앱별 작성 방식 | 녹음 시작 앱 기준, 원래 말투 기본. fast 미적용, 번역은 말투 적용. 브라우저 사이트 판단 없음 | [SettingsView:616](../../../Sources/OpenNoType/Views/SettingsView.swift#L616), [WritingProfile:3](../../../Sources/OpenNoTypeCore/AI/WritingProfile.swift#L3) |
| `shortcutActivation` toggle/hold/hybrid | 녹음·단축키 → 단축키 동작 | 기존 세 동작 유지, 일반 설명은 ? | [VoiceInputOptionsView:39](../../../Sources/OpenNoType/Views/VoiceInputOptionsView.swift#L39) |
| `inputDeviceUID` 지정/기본 마이크 | 녹음·단축키 → 녹음 마이크 | 미연결 UID를 보존해 연결 끊김으로 표시 | [VoiceInputOptionsView:48](../../../Sources/OpenNoType/Views/VoiceInputOptionsView.swift#L48) |
| 마이크 목록 새로고침 | 같은 행의 새로고침 | 작업 중·복구·preview 보호 유지 | [VoiceInputOptionsView:61](../../../Sources/OpenNoType/Views/VoiceInputOptionsView.swift#L61) |
| `recordingAudioFeedback` | 녹음·단축키 → 준비·종료 알림음 | 준비 완료 시점의 기존 알림 유지 | [VoiceInputOptionsView:72](../../../Sources/OpenNoType/Views/VoiceInputOptionsView.swift#L72) |
| `muteWhileRecording` | 녹음·단축키 → 시스템 음소거 | 알림음과 동시 ON이면 들리지 않을 수 있음을 한 줄 노출 | [VoiceInputOptionsView:75](../../../Sources/OpenNoType/Views/VoiceInputOptionsView.swift#L75) |
| `hotkeys` 받아쓰기·번역·선택 수정·프롬프트 4개 | 녹음·단축키 → 작업별 단축키 | 변경 캡처·잘못된 조합·중복·다른 앱 충돌 분리. 이동 시 캡처 해제 | [SettingsView:366](../../../Sources/OpenNoType/Views/SettingsView.swift#L366) |
| `provider` 음성 제공자 4종 | AI 연결 → 음성 제공자 | 제공자별 키·모델 유지. Anthropic은 로컬 음성 필요 | [SettingsView:253](../../../Sources/OpenNoType/Views/SettingsView.swift#L253) |
| `useLocalTranscription` | AI 연결 → 인식 위치 | 음성만 로컬과 문장 AI는 독립. Anthropic 선택 중 로컬 조건 설명 | [SettingsView:264](../../../Sources/OpenNoType/Views/SettingsView.swift#L264) |
| 음성 API 키 입력·명시 저장·삭제·저장 상태 | AI 연결 → 음성 연결 → 키 관리 | 저장됨과 연결 성공 분리. 복구·preview·startup guard 유지 | [SettingsView:270](../../../Sources/OpenNoType/Views/SettingsView.swift#L270) |
| `transcriptionModels` 제공자별 모델 | AI 연결 → 음성 연결 → 모델 | Groq 기존 2종 목록+직접 입력. 다른 제공자 직접 ID 유지 | [SettingsView:284](../../../Sources/OpenNoType/Views/SettingsView.swift#L284) |
| `textProvider` 재사용/독립 4종 | AI 연결 → 문장 제공자 | nil/같은 제공자의 기존 키 공유 조건 유지 | [SettingsView:304](../../../Sources/OpenNoType/Views/SettingsView.swift#L304) |
| 문장 API 키 입력·명시 저장·삭제 | AI 연결 → 문장 연결 → 키 관리 | 공유 키인 경우 공유되는 키라는 사실과 실제 관리 위치 표시 | [SettingsView:311](../../../Sources/OpenNoType/Views/SettingsView.swift#L311) |
| `textModels` 제공자별 모델 | 문장 연결 → 모델 | OpenRouter·Groq 카탈로그/직접 ID. 다른 제공자 직접 ID. 목록이 계정 사용 가능성 보증 아님 | [SettingsView:324](../../../Sources/OpenNoType/Views/SettingsView.swift#L324) |
| 가격 참고 단가·기준일·출처·모델 노트·직접 모델 가격 미확인 | 문장 모델 → 가격 기준·모델 정보 | 기존 가격 근거를 유지, 시안에서 수치 창작 금지. 실제 비용과 참고 단가 구분 | [ProviderModelPicker:82](../../../Sources/OpenNoType/Views/ProviderModelPicker.swift#L82) |
| `localSpeechModel` Large v3/Small/Base | 음성 모델 → 사용할 모델 | 선택과 다운로드와 메모리 준비 분리 | [VoiceInputOptionsView:106](../../../Sources/OpenNoType/Views/VoiceInputOptionsView.swift#L106) |
| 모델 준비·진행·취소·실패/재시도 | 모델 상세 → 파일과 준비 | ready는 다시 준비하지 않음. 준비 중 취소, 파일 삭제 비활성. 실패 이유를 기본 노출 | [VoiceInputOptionsView:118](../../../Sources/OpenNoType/Views/VoiceInputOptionsView.swift#L118) |
| 선택 모델 캐시·토크나이저·파일 삭제 확인 | 모델 상세 → 선택 모델 파일 | 다른 모델·사전·기록 보존. 삭제 확인과 실제 action guard 유지 | [VoiceInputOptionsView:127](../../../Sources/OpenNoType/Views/VoiceInputOptionsView.swift#L127), [VoiceInputOptionsView:164](../../../Sources/OpenNoType/Views/VoiceInputOptionsView.swift#L164) |
| `localModelUnloadPolicy` never/5/15/30분 | 모델 상세 → 메모리 유지 | 파일 삭제와 다름. 첫 준비 비용은 ?에서 설명 | [VoiceInputOptionsView:139](../../../Sources/OpenNoType/Views/VoiceInputOptionsView.swift#L139) |
| `localPreviewEnabled` | 고급 도구 → 실험 / 모델 상세 | 같은 값. local 미사용·화자필터 ON이면 미적용. ON이면 추가 연산·미확정 노출 | [VoiceInputOptionsView:147](../../../Sources/OpenNoType/Views/VoiceInputOptionsView.swift#L147) |
| 화자 모델 준비·취소·오류 | 음성 모델 → 내 목소리 구분 | 약14MB 모델 별도 준비. working일 때만 취소, ready면 취소 숨김 | [SettingsView:796](../../../Sources/OpenNoType/Views/SettingsView.swift#L796) |
| 목소리 등록·재등록·등록 종료·특징 삭제 | 내 목소리 구분 → 등록 | 미등록이면 재등록/삭제 비활성. 모델 ready 후 등록, enrolling이면 녹음 종료. 원음 삭제·특징 암호화 유지 | [SettingsView:801](../../../Sources/OpenNoType/Views/SettingsView.swift#L801) |
| `speakerFilterEnabled` | 내 목소리 구분 → 필터 | 모델·프로필 없으면 활성화 불가. 실험·실사용 미검증 노출. 저장된 preview는 보존 | [SettingsView:814](../../../Sources/OpenNoType/Views/SettingsView.swift#L814) |
| 음성 비교 진입 | 모델 → 비교 / 고급 도구 → 음성 모델 비교 | `speech-lab`, 세부 화면 C 소유. 기존 녹음·파일·모델 선택·CER·수동 검토 보존 | [SettingsView:788](../../../Sources/OpenNoType/Views/SettingsView.swift#L788) |
| `historyEnabled` | 개인정보 → 처리 결과 기록 | OFF의 현재 결과·검토/진단 정리와 기존 기록 보관 정책 구별 | [SettingsView:410](../../../Sources/OpenNoType/Views/SettingsView.swift#L410) |
| `retentionDays` 1/7/30/90/계속 | 개인정보 → 텍스트 보관 기간 | 손상된 값은 임의 30일 삭제로 바꾸지 않음. 실패 원음24h와 별개 | [SettingsView:418](../../../Sources/OpenNoType/Views/SettingsView.swift#L418), [Preferences:137](../../../Sources/OpenNoType/App/Preferences.swift#L137) |
| 실패 녹음 복구 진입 | 개인정보 → 실패 녹음 / 기록 → 녹음 복구 | `recovery`, 원래 만료 시각·암호화·성공시 제거 정책 유지 | [DataViews](../../../Sources/OpenNoType/Views/DataViews.swift) |
| `allowedContextApps` 앱 추가·목록·허용 해제 | 개인정보 → 주변 문맥 허용 | 빈 상태/허용된 앱 상태 별도. 커서 앞1000자·보안입력 제외·미보관 | [SettingsView:389](../../../Sources/OpenNoType/Views/SettingsView.swift#L389) |
| 현재 음성/문장 전송 요약 | 개인정보 → 현재 받아쓰기 전송 | 실제 유효 fast 여부 기준. 번역·선택 수정·프롬프트는 별도 처리임을 ? 설명 | [SettingsView:456](../../../Sources/OpenNoType/Views/SettingsView.swift#L456) |
| 번역/Jev/교정 재검토/오류유형의 추가 전송 안내 | 개인정보 → 추가 전송 → 해당 실험·검토 설정 | ON인 옵션의 짧은 추가 전송·비용 표식을 해당 행에도 유지 | [SettingsView:465](../../../Sources/OpenNoType/Views/SettingsView.swift#L465) |
| `automaticLearningEnabled`·최근 자동 학습 되돌리기·후보 검토 | 개인정보 → 고친 표기 기억 → 개인 사전 → 교정 학습 | `dictionary-learning`, C 소유. 제한적 학습 범위·되돌리기 보존 | [SettingsView:493](../../../Sources/OpenNoType/Views/SettingsView.swift#L493) |
| `usageTrackingEnabled` | 개인정보 → 사용량 기록 | OFF는 신규 수집 중단이며 기존 통계 유지. 이미 저장 중 요청의 뒤늦은 반영 가능 | [SettingsView:509](../../../Sources/OpenNoType/Views/SettingsView.swift#L509), [UsageView:36](../../../Sources/OpenNoType/Views/UsageView.swift#L36) |
| `usageAccountingIncomplete` | 사용량 → 저장 불완전 상태 | 내부 상태이며 새 사용자 토글로 만들지 않음. 비용0/요청없음으로 대체 금지 | [Preferences:56](../../../Sources/OpenNoType/App/Preferences.swift#L56), [UsageView:44](../../../Sources/OpenNoType/Views/UsageView.swift#L44) |
| 사용량 보기·기간/제공자·초기화·세션 집계 | AI 연결/개인정보 → 사용량 | `usage`, C 소유. 20개 최근 요청·기간/세션 범위 구분 보존 | [UsageView:23](../../../Sources/OpenNoType/Views/UsageView.swift#L23) |
| `decisionProvider` OpenRouter 재사용/TypeSafe 직접 | Jev → 검토 서비스 | 재사용은 문장 제공자 OpenRouter 필요. 직접은 독립 키 | [SettingsView:114](../../../Sources/OpenNoType/Views/SettingsView.swift#L114) |
| Jev 키 입력·명시 저장·삭제·저장된 키 재확인 | Jev → 키 관리 | 재사용 시 별도 Jev 키 폼 대신 문장 키 관리 위치 표시 | [SettingsView:124](../../../Sources/OpenNoType/Views/SettingsView.swift#L124) |
| `decisionReviewMode` off/observe/protect/repair | 받아쓰기 → 자동 문장 검토 → Jev | 아래 네 계약을 동일하게 유지. 번역/fast 미적용 이유는 접지 않음 | [SettingsView:20](../../../Sources/OpenNoType/Views/SettingsView.swift#L20) |
| `translationProtectionEnabled` | Jev → 번역도 입력 전 검토 | protect와 함께 켜져야 유효. OFF/다른 모드에서도 저장된 선택 보존 | [SettingsView:162](../../../Sources/OpenNoType/Views/SettingsView.swift#L162) |
| `improvementModels` 카탈로그/직접ID/현재모델로 복원 | Jev → 보조 모델 | 제공자별 별도 값. 직접 개선안·protect 별도 개선안용, repair/observe는 현재 모델 | [SettingsView:209](../../../Sources/OpenNoType/Views/SettingsView.swift#L209) |
| 문장 모델 비교 진입 | Jev/고급 도구 → 문장 모델 비교 | `text-lab`, C 소유. 승인사례·예산·전송확인·수동 적용 보존 | [SettingsView:219](../../../Sources/OpenNoType/Views/SettingsView.swift#L219) |
| `jevDetailedReviewEnabled` | Jev → 추가 도움 → 중요한 변경 세부 검토 | 기존 요청의 질문 추가. 별도 요청1회라고 표시하지 않음 | [JevAssistanceViews:90](../../../Sources/OpenNoType/Views/JevAssistanceViews.swift#L90) |
| `jevEconomyEnabled` | 같은 화면 → 단순 받아쓰기 검토 절약 | 엄격한 동일문장·후보없음 조건에서 생략. 생략은 통과 아님 | [JevAssistanceViews:97](../../../Sources/OpenNoType/Views/JevAssistanceViews.swift#L97) |
| `jevAutomaticImprovementEnabled` | 같은 화면 → 주의 신호 시 개선안 준비 | protect+원래 언어+AI정리만. 추가 생성/검토·직접 복사, 자동 교체 없음 | [JevAssistanceViews:104](../../../Sources/OpenNoType/Views/JevAssistanceViews.swift#L104) |
| `jevClarifyEditsEnabled` | 같은 화면 → 모호한 수정 지시 확인 | 선택 원문+지시 추가 전송·보류/구체화·직접 복사 | [JevAssistanceViews:111](../../../Sources/OpenNoType/Views/JevAssistanceViews.swift#L111) |
| `jevReRecognitionEnabled` | 같은 화면 → 헷갈리는 음성 재인식 | 지원경로에서 녹음 Groq/OpenAI 재전송+Jev비교. observe도 입력 전 대기 가능 | [JevAssistanceViews:118](../../../Sources/OpenNoType/Views/JevAssistanceViews.swift#L118) |
| `jevFeedbackLearningEnabled`·현재모델 유형수/요약·전체모델 유형 삭제 확인 | Jev → 오류 유형 학습 | 암호화된 정해진 오류유형만, 과거문장 저장·AI재학습 아님. 기존 확인삭제 범위 유지 | [JevAssistanceViews:21](../../../Sources/OpenNoType/Views/JevAssistanceViews.swift#L21) |
| `jevNameCatalog` 추가·앱 선택·목록·삭제 | 개인 사전 → 이름 후보 | `dictionary-names`, C 소유. 개인 사전 매핑과 별도 후보 목록 유지 | [JevAssistanceViews:157](../../../Sources/OpenNoType/Views/JevAssistanceViews.swift#L157) |
| Jev 합성 연결 테스트·진행·실패 | 고급 도구/Jev → 연결 테스트 | 녹음·자동입력 없음. OFF상태에서도 시험 가능, API 비용·사용량 기록 노출 | [SettingsView:229](../../../Sources/OpenNoType/Views/SettingsView.swift#L229) |
| 최근 Jev 결과·표기 제안 | Jev → 최근 검토 결과 | `review`, A 소유. 이전결과가 없는 상태/작업 중 guard 보존 | [SettingsView:245](../../../Sources/OpenNoType/Views/SettingsView.swift#L245) |
| 녹음 없는 단축키 입력 테스트 준비·5초 예약·취소 | 고급 도구 → 다른 앱 입력 | 준비 전 취소 비활성. 실제 전달과 실제 입력확인 별개 | [SettingsView:431](../../../Sources/OpenNoType/Views/SettingsView.swift#L431) |
| 최근 입력·처리 시간 진단 | 같은 화면 → 최근 진단 | stage 실측/미확인 표시. 이벤트발송을 입력완료로 표시하지 않음 | [SettingsView:443](../../../Sources/OpenNoType/Views/SettingsView.swift#L443) |
| 마이크 허용 요청·마이크 시스템 설정 | 고급 도구 → Mac 접근 권한 | 미요청/거부/허용 구분. 거부면 시스템 설정 안내 | [SettingsView:557](../../../Sources/OpenNoType/Views/SettingsView.swift#L557) |
| 손쉬운 사용 시스템 설정·권한 다시 확인·처음부터 입력 확인 | 같은 화면 → 손쉬운 사용 / 상태 / 입력 테스트 | 권한 허용을 실제 앱 입력 성공으로 간주하지 않음 | [SettingsView:570](../../../Sources/OpenNoType/Views/SettingsView.swift#L570) |
| `interfaceLanguage` 영어/한국어 | 앱 관리 → 앱 언어 | UI만 변경, 음성·번역 설정 그대로 | [SettingsView:524](../../../Sources/OpenNoType/Views/SettingsView.swift#L524) |
| `launchAtLogin` 실제등록 토글·오류·시스템 설정 | 앱 관리 → 로그인 실행 / 로그인 항목 | 저장된 bool보다 실제 서비스 상태 우선, 오류는 기본 노출 | [SettingsView:532](../../../Sources/OpenNoType/Views/SettingsView.swift#L532) |
| `appearance` system/light/dark | 앱 관리 → 화면 모드 | 기존 값과 자동 저장 보존 | [SettingsView:544](../../../Sources/OpenNoType/Views/SettingsView.swift#L544) |
| 현재버전·커뮤니티 안내·업데이트 확인·공개릴리스·마지막확인 | 앱 관리 → 업데이트 | 서명/공증 안내를 지원 상세 ?로, 구성오류는 기본 노출 | [UpdateSettingsView:9](../../../Sources/OpenNoType/Views/UpdateSettingsView.swift#L9) |
| 새 버전 자동 확인·작업 중 보류·설치 후 재실행 | 같은 그룹 | 자동 확인 ≠ 자동 설치. busy/install guard·오류 보존 | [UpdateSettingsView:21](../../../Sources/OpenNoType/Views/UpdateSettingsView.swift#L21) |
| Whisper·FluidAudio·화자모델 고지·출처 | 앱 관리 → 모델·오픈소스 고지 | 기존 라이선스와 출처 링크 보존 | [SettingsView:817](../../../Sources/OpenNoType/Views/SettingsView.swift#L817) |
| 설정 손상/부분복구 보호·preview 읽기전용 | 앱 준비의 복구 화면 / 해당 옵션의 현재 상태 | A의 `home-storage-recovery`와 연결. 기존 스냅샷·일반설정·기록 보존, ?/닫기는 사용 가능 | [SettingsView:16](../../../Sources/OpenNoType/Views/SettingsView.swift#L16), [Preferences:90](../../../Sources/OpenNoType/App/Preferences.swift#L90) |

## 유지해야 하는 실패·적용 계약

| 모드 | 기본 행의 짧은 상태 | 기존 입력 계약 |
|---|---|---|
| off | 선택값만 표시 | 자동 Jev 요청 없음. 수동 검토·연결 시험은 별도 |
| observe | 입력 후 검토 · 입력한 글 유지 | 이미 입력한 글을 바꾸지 않음. 음성 재인식 ON이면 입력 전 대기가 생길 수 있음 |
| protect | 위험 신호 시 보류 · 검토 실패 시 기존 결과 입력 | 의미 변경 등 강한 신호에는 보류. 일반 검토 실패·시간 초과에는 기존 결과 입력. 항상 안전하게 검증됐다는 보장 아님 |
| repair | 검토·교정 실패 또는 미해결 시 입력 보류 | 최대 한 번 교정하고 재검토. 검토를 완료한 결과만 입력 |

번역 보호는 일반 protect와 실패 정책이 다르다. `translationProtectionEnabled && decisionReviewMode == .protect`일 때 번역을 검토하며 실패·미확인에도 입력을 보류하고 자동 번역 교정은 하지 않는다. 번역 다듬기는 독립적인 추가 문장 요청이며 다듬기 실패에도 초안을 대신 자동 입력하지 않는다. 두 옵션 ON이면 다듬은 결과를 검토한다. 이 차이는 ?에서 풀어 설명하되 ON인 행에는 `추가 요청 · 실패 시 보류`를 남긴다.

`usesFastDictation`은 저장값이 fast인 것만으로 성립하지 않는다. **fast 저장 + 받아쓰기 출력 언어 original**이어야 유효하다([Preferences:300](../../../Sources/OpenNoType/App/Preferences.swift#L300)). 번역으로 바꿔도 fast·표현·Jev 저장값을 초기화하지 않는다. 다시 원래 언어로 돌아왔을 때 기존 선택을 그대로 사용한다. 표현 강도 0은 기존 AI 정리이며 fast로 변경하는 동작이 아니다.

## 기본 노출과 도움말의 경계

| 내용 | 기본 화면 | ? 도움말·상세 |
|---|---|---|
| 라벨·현재 선택·토글·실행 버튼 | 항상 | 불필요한 중복 없음 |
| 기능의 원리·예시·적용 작업 설명 | 생략 | 기능 설명 / 적용 범위 |
| 현재 입력 보류·오류·키 없음·장치 끊김 | 한 줄, 필요한 복구 액션 | 원인별 자세한 설명 |
| ON이지만 fast·번역·온라인·화자 때문에 미적용 | 해당 행에 한 줄 | 조건과 저장값 보존 설명 |
| 추가 요청·비용·음성/원문 외부 재전송 | 켜진 옵션에 한 줄 | 실제 전송 대상·내용·실패 계약 |
| 모드별 실패 동작 | 활성 모드에 짧게 | 네 모드 전체 비교 |
| 실험적 화자·미확정 미리보기 | 실험/미검증 표시 | 한계·등록/처리 방식 |
| 보관 기간·삭제 범위·비용 승인 | 현재 값/확인 단계에 유지 | 자세한 범위·예외 |
| 일반 Mac 권한 설명 | 현재 허용 상태와 필요한 액션 | System Settings 경로·목적 |
| 참고 모델 가격 | 실제 값은 선택 메뉴/가격 상세 유지 | 기준일·출처·변동/미확인 설명 |

도움말은 마우스 hover 전용이 아니다. 클릭·키보드로 열고 Escape/닫기로 닫는다. 호출 라벨과 접근성 제목을 연결하고 포커스를 돌려준다. 기존 `.disabled`를 섹션 전체에 붙여 ?·닫기까지 막지 않는다. 값 변경·다운로드·삭제·전송 등 실제 제어에만 원래 guard를 적용한다.

## 기본값·호환성 보존

[Preferences.swift:33–75](../../../Sources/OpenNoType/App/Preferences.swift#L33)의 값을 UI 재배치 때문에 바꾸지 않는다.

| 범위 | 유지할 기본값 |
|---|---|
| 인터페이스 | 신규 설치 영어, 언어 필드가 없는 기존 설정은 한국어. 시안은 사용자 검토를 위해 한국어로 표시하며 기본값 변경 제안이 아님 |
| 처리 | OpenAI 음성, 문장 제공자 nil/재사용, 제공자별 모델 맵 비어 있음, 온라인 음성, AI 정리, 원래 언어 유지, 별도 번역 미국 영어 |
| 녹음 | toggle, 시스템 기본 마이크(nil), 알림음 OFF, 음소거 OFF |
| 로컬 | Large v3, 메모리 계속 유지, 미리보기 OFF, 화자필터 OFF |
| 표현·앱 | faithful/0, 사용자 작성 프로필 빈 맵, 알려진 앱 기본 형식 유지, 기본 말투 preserve |
| 보관·학습 | 결과 기록 ON, 30일, 안전한 교정 학습 ON, 사용량 기록 ON. 내부 불완전집계 상태 false |
| Jev | off, OpenRouter 재사용, 번역 보호 OFF, 다듬기 OFF, 6개 세부/학습 토글 모두 OFF, 이름 후보 빈 목록, 보조 모델 맵 비어 있음 |
| 앱 | 로그인 실행 OFF, 화면 system. 업데이트 자동 확인 값은 `Updater`의 기존 저장·시작 정책을 따름 |
| 단축키 | 받아쓰기 ⌥Space / 번역 ⌥⇧Space / 선택수정 ⌃⌥Space / 프롬프트 ⌃⌥⇧Space. 기존 사용자 변경과 레거시 추가 규칙 유지 |

필드별 디코드·손상 복구를 그대로 사용한다. 손상된 보관 기간은 -1 보존으로 처리하고, 알 수 없는 검토 전송대상을 임의 OpenRouter로 바꾸며 opt-in을 유지하지 않는다([Preferences:137](../../../Sources/OpenNoType/App/Preferences.swift#L137), [Preferences:157](../../../Sources/OpenNoType/App/Preferences.swift#L157)). 화면 이동을 이유로 settings를 다시 생성하거나 기본값을 저장하지 않는다. API 키는 일반 옵션 자동 저장과 달리 명시 저장·삭제를 유지한다.

## 부속 화면과 상태 표본

| 화면 ID | 실제 앱의 표시 목적 | 진입 |
|---|---|---|
| `models`, `model-detail` | 모델 선택/캐시/메모리/자원 설정 | 내비 음성 모델, AI 연결, 받아쓰기 모델 |
| `model-preparing`, `model-error`, `model-delete-confirm` | 준비중/실패/선택 파일 삭제 | 모델 상세·시안 상태 선택 |
| `api-connection`, `key-delete-confirm`, `api-save-error` | 역할별 키·모델·공유관계, 삭제/저장실패 | 음성/문장/Jev 연결·상태 검토 |
| `jev-settings`, `jev-assistance` | 검토 4모드·번역보호·보조모델·5개 추가 도움 | 받아쓰기/AI 연결/고급 도구 |
| `jev-learning`, `jev-clear-confirm` | 모델별 유형수·요약·전체모델 삭제확인 | Jev 설정·추가 도움 |
| `permissions`, `input-diagnostics` | 권한·단축키 테스트·예약/취소·최근 진단 | 고급 도구 |
| `hotkey-capture` | 새 조합·중복·취소 상태 | 녹음·단축키의 변경 상태 표본 |
| `context-apps`, `context-apps-allowed` | 문맥 허용 없음/목록·해제·추가 | 개인정보 |
| `writing-profiles` | 앱별 형식5종·말투4종·복원·추가 | 받아쓰기 |
| `speaker-setup`, `speaker-enrolled`, `speaker-enrolling` | 미등록/등록됨/등록중 | 모델·고급 도구 |
| `speaker-preparing`, `speaker-error` | 모델 준비중·취소/실패·재시도 | 화자 상태 표본 |
| `language-examples`, `expression-examples` | 합성 예시·보류 선택·명시 적용 | 받아쓰기 |
| `login-item-error`, `licenses` | 로그인 등록오류/라이선스 | 앱 관리 |
| `usage`, `speech-lab`, `text-lab` | 사용량 / 음성 비교 / 승인 문장 비교 | 공유 진입, C 담당 |
| `dictionary`, `dictionary-learning`, `dictionary-names`, `recovery` | 사전·학습·이름 후보·복구 | 공유 진입, C 담당 |
| `review`, `home-storage-recovery` | 최근 검토·설정 복구 | 공유 진입, A 담당 |

상태 표본은 가상 장면을 명시적으로 고르는 검토용이다. 브라우저의 준비중→완료 클릭이 실제 다운로드·녹음·Keychain·입력 성공을 뜻하지 않는다. API 키 입력에는 실제 키를 쓰지 않는다. 모델·서비스 목록은 현재 소스의 선택 예시이며 계정별 서비스 사용 가능 여부를 검증한 결과가 아니다.

추가 구현 시 빠뜨리면 안 될 상태: API 로드중/미저장/저장됨/저장오류/공유키/연결실패, 권한 미요청/거부/허용, 로그인 등록 보류/실패, 단축키 캡처 해제, 모델 캐시만 있음/메모리 ready/토크나이저 없음/준비 취소, 등록 프로필 있지만 모델 미준비, Jev 연결 시험중/실패, 업데이트 확인중/구성오류/실패/작업중 보류/설치 재개. 모든 상태를 실제로 일으킨 검증은 이번 범위에 포함하지 않는다.

## 컴포넌트 호출 소유권과 후속 SwiftUI 적용 순서

| 영역 | 현재 소유 파일·호출 | 후속 구현에서 맡을 일 |
|---|---|---|
| 창·내비·공통 토큰 | `MainView`, `Surface`, `OptionHelp` | `SettingsRow`/묶음 패널/값열/상태caption/도움말 토큰을 공통화. 실제 app window와 focus 유지 |
| 설정 목적별 분할 | `SettingsView.sectionContent` | 여섯 분류를 표시 전용 View로 분리, 기존 `AppModel`·Preferences Binding과 액션 재사용 |
| 녹음·로컬 | `VoiceInputOptionsView`, `LocalModelOptionsView` | 공통 row로 배치, guard·download/cancel/delete 확인은 그대로 |
| 언어·표현·다듬기 | 세 SettingsView + 두 ExamplesView | 옵션 행과 통일된 bounded sheet. local pending value와 명시 적용 보존 |
| 키·모델 | `SettingsView.connectionSection`, `ProviderModelPicker` | 역할별 상세 진입, 공유키 표현, ID 직접 입력·가격/출처 상세 유지 |
| 앱 프로필·문맥 | `SettingsView.writingProfilesSection`, `contextSection` | 같은 행높이·목록/빈 상태, 기존 앱 식별·복원·허용 액션 재사용 |
| Jev 설정 | `decisionReviewSection`, `JevAssistanceSettingsView`, `JevFeedbackLearningSettingsView` | 네 모드 계약을 단일 표현 모델로 사용. 유형 삭제 확인·개수/요약·추가 전송 표식 보존 |
| 권한·진단·앱 관리 | `permissionsSection`, `diagnosticsSection`, `generalSection`, `UpdateSettingsView` | 실제 상태에서 짧은 caption, System Settings/업데이트 action guard 유지 |
| 비교·기록·사전·사용량 | 기존 각 View, A/C 담당 시안 | 공통 row/table/list/empty/confirm의 치수만 함께 적용. 기능 알고리즘·데이터 정책 변경 금지 |

실제 구현을 승인받은 뒤의 순서:

1. 공통 토큰·행·패널·도움말과 메인 창의 치수를 먼저 적용한다. 한 옵션씩 카드로 싸는 패턴을 중단한다.
2. 여섯 목적별 설정 View로 기존 Binding/액션을 옮긴다. `Preferences.CodingKeys`·엔진·전송·저장 로직은 그대로 둔다.
3. 키·모델·앱별 목록·예시 시트의 폭과 푸터를 정리한다. 읽기전용에서도 도움말·닫기는 작동하게 한다.
4. Jev 네 모드와 fast/번역/화자 조합의 상태 표현을 연결한다. guard는 실제 제어마다 유지한다.
5. 실패·빈 상태·진행·취소·삭제 확인·긴 영문·긴 앱 이름·작은 창·VoiceOver를 기존 작업 흐름으로 확인한다.

최소 회귀 확인은 UI 값의 보존과 실제 기존 정책에 초점을 둔다: fast→번역→original 전환 후 선택 복원, 표현 예시 취소 무변경, 4개 Jev 실패 정책, 번역 다듬기/보호 독립, 미등록 화자와 preparing 모델의 불가 액션, 설정 복구/preview에서 도움말 읽기 가능, 제공자 전환 시 기존 키·모델 유지. HTML 시안의 버튼 이동과 정적 검사는 이 native 동작 검증을 대신하지 않는다.
