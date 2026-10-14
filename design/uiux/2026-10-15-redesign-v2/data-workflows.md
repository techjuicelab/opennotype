# 기록·사전·복구·사용량·비교실 재설계

작성일: 2026-10-15. 범위는 현재 체크아웃을 읽고 만든 설계와 합성 데이터 HTML 시안이다. 앱 코드·설정·권한·실제 기록·API 키·설치 상태는 변경하지 않는다. 시안의 버튼은 화면 이동 또는 시안 안내만 수행하며 파일·마이크·API·클립보드에 접근하지 않는다.

## 재설계의 중심

기록은 **목록에서 찾고 한 항목의 상세만 확인**한다. 개인 사전은 **등록된 단어 목록이 먼저** 보이고 추가·수정은 작은 별도 폼에서 한다. 학습과 이름 후보는 사전 안의 탭으로 옮긴다. 사용량은 비용·요청·토큰을 동일한 크기의 요약으로 보고 상세를 펼친다. 두 비교실은 준비·진행·결과를 구분한다.

페이지 제목 아래 설명 문단은 모두 제목 옆 `?`로 옮겼다. 상한·동작 원리·학습 범위·보관 원칙은 해당 제목 또는 옵션의 도움말로 제공한다. 다음 내용은 기본 화면에 짧게 남긴다.

- 현재 꺼짐·처리 중·오류·보류·미확인·만료 상태
- 필수 원문 누락과 입력 길이 등 지금 행동을 막는 조건
- 전송 직전의 대상·내용·추가 비용과 삭제 직전의 정확한 범위
- 결과를 확정하지 못한 초안, 복사 불가, 보관되지 않는 미리보기

도움말 자체를 상태 표시의 대체물로 쓰지 않는다. 일반 설명을 다시 큰 안내 카드로 만들지 않는다.

## 현재 문제와 치수 변경

스크린샷의 사전은 이름 후보·자동 학습·등록 폼이 목록보다 먼저 보인다. 기록은 각 항목에 제목·결과·원문 비교·검토·재처리를 반복해, 제공된 화면에 약 세 카드만 보인다. 이는 제공된 화면의 관찰이며 모든 창 크기의 측정 결과는 아니다. 사용자 실제 원문은 시안에 재사용하지 않았다.

| 요소 | 현재 코드에서 확인 | 새 설계 기준 |
| --- | --- | --- |
| 본문 외곽 | `MainView` 간격 24pt, 패딩 30pt, 최대 폭 920pt | 패딩 24pt, 최대 1184pt. 여유 공간을 카드 확대보다 목록·상세 분할에 사용 |
| 카드 | `Surface` 내부 간격 18pt, 패딩 22pt, 모서리 14pt | 패딩 16pt, 간격 16pt, 모서리 10pt. 서로 같은 목록은 한 패널로 묶음 |
| 페이지 제목 | `DataPageHeading` 25pt + 12pt 설명, 간격 10pt | 제목 22pt/30pt + 옆 `?`. 기본 화면 설명 문단 없음 |
| 정보 글자 | 기록 metadata 10~11pt, 사전 학습 배지 9pt | 본문 13pt, 보조 12pt. 작은 글자로 많은 설명을 밀어 넣지 않음 |
| 기록 반복 단위 | 항목별 높이 가변 카드, 카드 사이 14pt | 목록 요약 최대 2줄 + metadata 1줄. 56pt가 최소이며 긴 요약이면 필요한 높이 허용. 상세는 한 항목만 |
| 사전 반복 단위 | 사전 행 사이 `Divider`에 상하 13pt, 등록 폼 상시 표시 | 기본 행 44pt, 두 줄이면 56pt. 목록 위 검색·개수·더보기와 단일 `+ 단어 추가` |
| 입력·행동 | 화면별 폰트·패딩 혼용 | 일반 컨트롤 32pt, 주요 행동 36pt, `?` 28pt. 긴 문구는 잘라 숨기지 않음 |
| 복구 원문 입력 | 88~140pt + 별도 8pt 패딩 | 상세 안에 필수 입력을 바로 노출. 임의로 도움말·더보기 안에 숨기지 않음 |
| 비교실 입력 | 음성 정답 80~160pt, 문장 사례 76~110pt | 준비의 2열 입력, 좁으면 1열. 기본 120pt인 HTML 컨트롤은 공통 CSS 기준이며 네이티브 구현에서 96~120pt로 조정 가능 |
| 사용량 비용 | 36pt 비용, 패딩 24pt, 별도 3개 지표 카드 | 제목·요청·토큰과 같은 요약 크기, 수치 22pt. 비용 미확인과 보고/추정 구분은 유지 |

현재 치수 근거: [MainView 본문](../../../Sources/OpenNoType/Views/MainView.swift#L34) 34~55행, [Surface](../../../Sources/OpenNoType/Views/MainView.swift#L175) 175~185행, [기록 카드](../../../Sources/OpenNoType/Views/DataViews.swift#L49) 49~196행, [사전 행](../../../Sources/OpenNoType/Views/DataViews.swift#L297) 297~336행, [DataPageHeading](../../../Sources/OpenNoType/Views/DataViews.swift#L562) 562~598행, [사용량 비용](../../../Sources/OpenNoType/Views/UsageView.swift#L157) 157~192행. 밀도 개선과 탐색 시간은 아직 네이티브 앱에서 측정하지 않았다.

## 기존 요소의 새 위치

### 기록과 재처리

| 현재 소스·기능 | 새 위치 | 보존할 동작·상태 |
| --- | --- | --- |
| `HistoryView.matches`, [12행](../../../Sources/OpenNoType/Views/DataViews.swift#L12) | `history` 상단 검색 | 결과·인식 원문 모두 검색, 대소문자 무시, 최신순. 날짜별 새 필터를 기능처럼 추가하지 않음 |
| `HistoryView.body`, [19행](../../../Sources/OpenNoType/Views/DataViews.swift#L19) | `history`, `history-empty`, `history-search-empty` | 저장 꺼짐/기록 없음/검색 결과 없음 분리. 현재 보관 기간·직접 삭제까지 보관 설정은 동적 표시 |
| `HistoryEntryCard`, [65행](../../../Sources/OpenNoType/Views/DataViews.swift#L65) | 목록의 모드·날짜 + 상세의 배지·처리 정보 | 받아쓰기의 실제 번역 모드, 당시 출력 언어, 앱 bundle ID, 빠른 로컬 상태와 프롬프트 검토 요약을 잃지 않음 |
| `textBlock`, [184행](../../../Sources/OpenNoType/Views/DataViews.swift#L184) | 상세 결과·`결과 복사` | 전문은 선택·복사 가능. 프롬프트 `blocked`이면 기존 복사 금지 유지 |
| 원문 비교, [89행](../../../Sources/OpenNoType/Views/DataViews.swift#L89) | 상세 `인식 원문과 비교` 펼침 | 선택 문장 수정에서는 `음성 수정 지시`라고 정확히 표시. 결과와 원문이 같으면 중복이라는 상태 표시 |
| 직접 Jev 검토, [97행](../../../Sources/OpenNoType/Views/DataViews.swift#L97) | 상세 더보기 → A의 `review-confirm` | 기록 ID와 검토 목적을 고정. 당시 번역 언어를 알 수 없으면 직접 검토 불가 이유를 노출 |
| AI 재처리, [110행](../../../Sources/OpenNoType/Views/DataViews.swift#L110) | 더보기 → `history-reprocess` | 사용 불가 이유, 실제 현재 제공자·모델·출력 언어·이 기록 앱의 현재 프로필 표시. 인식 원문만 전송, 당시 주변 문맥은 없음 |
| 재처리 미리보기, [133행](../../../Sources/OpenNoType/Views/DataViews.swift#L133) | 상세의 일시 결과 → `history-reprocess-preview`, `history-reprocess-held` | 실행 중 취소, 오류 원문, 새 결과/번역 초안 구분, 기존 기록 유지, 별도 미리보기 보관 안 됨, 검토·다듬기 결과 연계 |
| 단일 삭제, [74행](../../../Sources/OpenNoType/Views/DataViews.swift#L74) / 전체 삭제, [37행](../../../Sources/OpenNoType/Views/DataViews.swift#L37) | 단일은 더보기, 전체는 목록 더보기 → `history-delete` | 단일 삭제는 현재 즉시 삭제 계약. 전체 삭제 확인은 기록·학습한 Jev 오류 유형·진행 검토·진단 삭제와 사전·실패 녹음 유지 범위 그대로 |

목록 선택이 바뀌면 상세와 일시 검토가 어느 기록에 속하는지 식별자를 유지한다. 삭제·검색으로 선택 항목이 사라졌을 때 다른 결과를 같은 항목인 것처럼 보여 주지 않는다. 재처리 요청 시점에 사용자가 확인한 대상·설정과 실제 실행 대상이 일치해야 한다. UI 분할은 기존 취소·epoch·request identity 방어를 약화할 이유가 아니다.

현재 HTML은 합성 목록의 선택에 따라 결과·원문·모드·상세 정보를 바꾸며, 합성 결과·원문 검색과 개수·검색 결과 없음도 동작한다. 선택 수정의 재처리/직접 검토 불가를 노출한다. 받아쓰기 기록의 직접 검토는 합성 원문·결과·출처 속성으로 A 확인 화면에 연결한다. 번역·프롬프트 검토와 프롬프트 기록 재생성 버튼은 시안 범위 안내만 표시하며 다른 목적의 문장으로 연결하지 않는다. 일반 기록 재처리 확인에는 선택한 항목의 합성 원문을 전달한다. 당시 번역 언어 누락·프롬프트 차단 조건은 위 계약으로 보존하며 모든 모드의 실제 처리 구현 완료를 뜻하지 않는다.

### 개인 사전과 후보

| 현재 소스·기능 | 새 위치 | 보존할 동작·상태 |
| --- | --- | --- |
| `DictionaryView.matches`, [210행](../../../Sources/OpenNoType/Views/DataViews.swift#L210) | `dictionary`, `dictionary-search-empty` | 두 표기 검색, 원하는 표기 기준 정렬, 개수·검색 지우기 |
| 상시 등록 카드, [264행](../../../Sources/OpenNoType/Views/DataViews.swift#L264) | `+ 단어 추가` → `dictionary-entry`, 수정 → `dictionary-edit` | 1~100자, trim 후 빈 값 저장 불가. 첫 필드 Return은 다음 필드, 다음 Return은 유효한 경우 저장. 저장 중 중복·닫힌 폼의 늦은 쓰기 방어 |
| `dictionaryRow`, [322행](../../../Sources/OpenNoType/Views/DataViews.swift#L322) | 단어 표 + 행의 수정/더보기 | 인식 표기→원하는 표기, 직접/학습 구분, 선택 가능 전문. 단일 삭제는 현재 즉시 수행 |
| 자동 학습·되돌리기, [230행](../../../Sources/OpenNoType/Views/DataViews.swift#L230) | `dictionary-learning` | toggle·실제 마지막 학습이 있을 때 되돌리기. 30초 관찰·약3초 안정·좁은 교정·숫자/버전/날짜 제외 등은 `?` |
| 확인할 후보·Jev, [243행](../../../Sources/OpenNoType/Views/DataViews.swift#L243) | `dictionary-learning` 후보 상세 → A의 `candidate-review-confirm` | 원래/고친 글 전문, Jev 검토, 표기 검토 후 추가 폼, 직접 등록, 검토하지 않기. 후보를 확인 없이 사전에 저장하지 않음 |
| Jev 사전 저장·되돌리기, [225행](../../../Sources/OpenNoType/Views/DataViews.swift#L225) | 학습 탭의 최근 저장 상태 + A 검토 결과 | 실제 저장 상태와 되돌릴 수 있음은 기본 화면. 도움말에만 숨기지 않음 |
| `JevNameCatalogView`, [157행](../../../Sources/OpenNoType/Views/JevAssistanceViews.swift#L157) | `dictionary-names` | 사전 매핑과 별도, 64개/2~100자·허용 문자 검증, 중복/상한은 짧게 표시. 앱 선택은 이름만 채우고 명시적 추가 필요 |
| `importDictionary`·`applyImport`, [372행](../../../Sources/OpenNoType/Views/DataViews.swift#L372) | 목록 더보기 → 파일 선택 → `dictionary-import` / `dictionary-import-error` | JSON 1MB/1~5,000개/버전/필드 길이 검증, 대소문자 중복 정규화, 같은 인식 표기 교체 개수의 기존 확인, 오류 시 미적용 |
| `exportDictionary`, [355행](../../../Sources/OpenNoType/Views/DataViews.swift#L355) | 목록 더보기 → 네이티브 저장 패널 | 사용자 선택 위치에 JSON 내보내기. **내보낸 파일은 암호화되지 않음**을 저장 직전 유지. 저장 실패·완료는 실제 결과로 표시 |

등록 폼은 제안된 새 sheet이다. 기존 편집 중인 항목 ID·저장 비동기 작업·포커스를 sheet로 옮기되 사전 저장 규칙을 새로 만들지 않는다. 취소/닫기는 작성 중 폼을 버리고 원래 목록으로 포커스를 돌린다. 학습 탭은 단어 추가 기능을 숨기는 장소가 아니라 기존 자동 학습·후보·되돌리기를 모은 장소이다.

### 녹음 복구

| 현재 소스·기능 | 새 위치 | 보존할 동작·상태 |
| --- | --- | --- |
| `RecoveryView`, [420행](../../../Sources/OpenNoType/Views/DataViews.swift#L420) | 기록 안 `녹음 복구` 탭: `recovery`, `recovery-empty` | 실패 녹음만 암호화 보관. `min(expiresAt, createdAt+24h)` 기준 목록·만료 계산, 30초 갱신 |
| `recoveryCard`, [471행](../../../Sources/OpenNoType/Views/DataViews.swift#L471) | 목록의 모드·남은 시간 + 선택 상세 | 실제 음성·문장 처리 경로, 빠른 로컬/번역 여부, 당시 모델·언어, 삭제 시점 표시 |
| 수정 원문, [497행](../../../Sources/OpenNoType/Views/DataViews.swift#L497) | `recovery-rewrite` 필수 입력을 바로 노출 | 저장되지 않은 수정 원문을 붙여넣어야 실행. 공백이면 같은/현재 설정 모두 비활성. 원문은 재처리 시 문장 제공자에게 전송 |
| 현재 설정 확인, [454행](../../../Sources/OpenNoType/Views/DataViews.swift#L454)·`currentSettingsRetryDescription` [525행](../../../Sources/OpenNoType/Views/DataViews.swift#L525) | `recovery-current` | 실제 전송 대상·모델·출력 언어·내 목소리 필터·OpenRouter 경유를 실행 직전 표시. 빠른 로컬이면 음성·인식문 외부 AI 전송 없음 |
| `startRetry`, [547행](../../../Sources/OpenNoType/Views/DataViews.swift#L547)·busy/cancel [428행](../../../Sources/OpenNoType/Views/DataViews.swift#L428) | `recovery-processing` | 중복 처리·녹음 삭제 차단, 취소, 실제 상태 표시. 수정 원문은 해당 실패 녹음의 ID와 연결 |
| 복구 완료, [436행](../../../Sources/OpenNoType/Views/DataViews.swift#L436) | `recovery-result` | 성공한 녹음은 목록에서 제거, 결과 확인·복사. 자동 외부 앱 입력으로 바꾸지 않음 |
| 최근 프롬프트, [422행](../../../Sources/OpenNoType/Views/DataViews.swift#L422) | 복구 완료 상단의 A 프롬프트 결과 표면 | 기존 프롬프트 검토·재생성·전달 차단을 일반 결과 복사 버튼으로 우회하지 않음 |

‘같은 설정’은 보관된 음성·문장 모델·출력 언어·말투를 사용하고 번역 다듬기·Jev·사전은 현재 설정을 쓰는 기존 계약이다. ‘현재 설정’은 만료 시각을 연장하지 않는다. 삭제 확인이 없는 단일 녹음 삭제에 새 보관·되돌리기 기능을 이미 있는 기능처럼 표시하지 않는다. 원음 보관 정책을 텍스트 기록 보관 정책과 합치지 않는다.

### 사용량과 진단

| 현재 소스·기능 | 새 위치 | 보존할 동작·상태 |
| --- | --- | --- |
| `UsageView.body`, [19행](../../../Sources/OpenNoType/Views/UsageView.swift#L19) | `usage` 필터 + 동일 크기 요약 | 기간/제공자, 기록 꺼짐, 저장 불완전, 보고/추정/미확인 비용을 구분 |
| 빈 상태, [141행](../../../Sources/OpenNoType/Views/UsageView.swift#L141) | `usage-empty`, `usage-off`, `usage-filter-empty`, `usage-storage-error` | 요청 없음/꺼짐/필터 결과 없음/저장 오류를 비용 0 또는 같은 문구로 합치지 않음 |
| 비용·지표, [157행](../../../Sources/OpenNoType/Views/UsageView.swift#L157) | 요약 + 비용 도움말/상세 | 미확인 요청 합계 제외, 공급자 보고와 단가 추정 분리, 로컬 API 비용 없음, 청구액 아님 |
| 일별 활동, [194행](../../../Sources/OpenNoType/Views/UsageView.swift#L194) | `usage`의 `일별 활동` 펼침 | 최대 최근30일 기존 범위, 음성/문장/검토 단계를 구분. 새 예측 그래프 추가 없음 |
| 모델별 집계, [211행](../../../Sources/OpenNoType/Views/UsageView.swift#L211) | 모델별 표 | 실제 응답 모델 기준, 요청·단계·비용, 요청 모델과 다를 수 있음을 상세에서 표시 |
| 최근 요청·상세, [232행](../../../Sources/OpenNoType/Views/UsageView.swift#L232) | 최근20개 compact 행 → 펼침 | 실패·취소도 집계. 요청/실제 모델, 캐시·오디오·추론 토큰, 음성 길이, 단가 확인일·HTTPS 근거 유지 |
| `qualityComparison`·`qualityModelRow`, [72행](../../../Sources/OpenNoType/Views/UsageView.swift#L72) | `이번 실행의 문장 모델 집계` 펼침 | 별도 세션 집계. 기간 필터 미적용/제공자만 적용. 완료/시도·실패/취소·단계별 p50/p95·보류·개선안 생성/첫 복사 유지. Jev 판단은 정확도/순위 아님 |
| `accountingNotes`, [269행](../../../Sources/OpenNoType/Views/UsageView.swift#L269) | 제목 옆 `?` + 현재 상태 flag + 설정 링크 | 내용·원음·키 미저장, 암호화 최근10,000건, 기록 시작일·보관 상한 제외·저장 오류는 현재 값 표시 |
| 통계 초기화, [287행](../../../Sources/OpenNoType/Views/UsageView.swift#L287) | 더보기 → `usage-reset` | 기존 확인 유지. 사용량/세션Jev 삭제, 텍스트 기록/사전/녹음/실청구 유지. busy·preview·삭제 대상 없음 gate 유지 |

기간별 사용량과 이번 실행의 검토 품질 집계를 같은 표의 정확도 수치로 섞지 않는다. 처리 시간은 현재 집계 범위와 실패·취소 포함 여부를 도움말에 보존한다. 그래프·요청 상세·세션 상세는 기본 화면을 늘리는 카드 대신 펼침이다.

### 두 모델 비교실

| 현재 소스·기능 | 새 위치 | 보존할 동작·상태 |
| --- | --- | --- |
| `SpeechComparisonLabView`, [9행](../../../Sources/OpenNoType/Views/SpeechComparisonLabView.swift#L9) | `speech-lab`, `speech-lab-recording`, `speech-lab-running`, `speech-lab-error` | 실제 상태·warning·error를 그대로 노출. 일반 음성 작업 중/비교 중 gate, 취소·clear·화면 이탈 정리 |
| 음성·정답·모델, [34행](../../../Sources/OpenNoType/Views/SpeechComparisonLabView.swift#L34) | 준비의 2열 음성/모델 + 정답 | 15/30/60초, 음성 파일 선택, 새 다운로드 없음, 기기에 있는 모델만 선택. 샘플 없음·모델 미선택 시 비교 불가. 모델 파일 존재는 추론 준비 완료라는 뜻이 아님 |
| 결과, [107행](../../../Sources/OpenNoType/Views/SpeechComparisonLabView.swift#L107) | `speech-lab-results` 요약 표 + 선택 모델 상세 | 준비/인식 시간 분리, 비교 당시 정답 고정, CER없음/실패 구분, 숫자 원문·인식문 비교, 수동 검토·3종 오류0~99 |
| `SpeechComparisonLab.cancel/clear/close`, [215행](../../../Sources/OpenNoType/App/SpeechComparisonLab.swift#L215) | 모든 종료·취소 경로 | 메모리 음성 비우기, 원음 파일 정리 실패 상태는 별도 안내. 취소해도 음성을 유지하는 새 계약을 만들지 않음 |
| `JevModelComparisonView`, [24행](../../../Sources/OpenNoType/Views/JevModelComparisonView.swift#L24) | `text-lab` 사례 입력 + 모델/예산 | 직접 승인1~5쌍, 모델2~3개, 사례 수정 시 재승인, 준비/실행 중 입력 잠금, 가격 확인 모델 부족 안내 |
| 예산·확인, [71행](../../../Sources/OpenNoType/Views/JevModelComparisonView.swift#L71)·[125행](../../../Sources/OpenNoType/Views/JevModelComparisonView.swift#L125) | `text-lab-confirm` | 4개 예산 선택, 참고 단가·날짜·예약액, 최종 청구 보장 상한 아님. 원문+사전힌트→생성, 정답+결과→Jev를 구분. 최대30요청/60초, 별도 비용 동의 |
| 진행·중단, [87행](../../../Sources/OpenNoType/Views/JevModelComparisonView.swift#L87) | `text-lab-running`, `text-lab-error` | 연결 준비/실행·취소 구분, 비용 미확인/실패/시간 초과면 잔여 중단. 이미 처리된 요청은 과금 가능 |
| 결과·추천, [97행](../../../Sources/OpenNoType/Views/JevModelComparisonView.swift#L97) | `text-lab-results` | 검토 완료/조건 통과/비용/생성 시간과 사례별 문장·문제. 모든 사례 통과 모델 중 기존 추천 규칙. 버튼을 눌러야 모델 적용 |
| `onDisappear`, [121행](../../../Sources/OpenNoType/Views/JevModelComparisonView.swift#L121) | 비교실 닫기 | 실행 취소 + 민감한 사례/결과 메모리 정리. 전체 기록을 자동 채우거나 학습 자료로 수집하지 않음 |

CER은 공백 제거·정규화 후 Unicode scalar 편집 거리/정답 길이이며 대소문자·문장부호를 포함한다. 점수는 의미나 한영 혼용의 일반 정확도 보장이 아니다. 문장 비교 통과 수도 정확도 백분율이 아니다. 시안은 이 주의를 `?`로 제공하고 현재 결과의 정답 변경·실패·미확인 상태만 기본에 표시한다.

## 시안의 상태 범위

`data-screens.js`는 38개 화면을 등록한다. 경로가 바뀌면 `window.DESIGN_SCREENS`의 실제 ID를 기준으로 갱신한다.

| 묶음 | 화면 ID |
| --- | --- |
| 기록 | `history`, `history-empty`, `history-search-empty`, `history-reprocess`, `history-delete`, `history-reprocess-preview`, `history-reprocess-held` |
| 사전 | `dictionary`, `dictionary-empty`, `dictionary-search-empty`, `dictionary-entry`, `dictionary-edit`, `dictionary-learning`, `dictionary-names`, `dictionary-import`, `dictionary-import-error` |
| 복구 | `recovery`, `recovery-empty`, `recovery-current`, `recovery-rewrite`, `recovery-processing`, `recovery-result` |
| 사용량 | `usage`, `usage-empty`, `usage-reset`, `usage-off`, `usage-filter-empty`, `usage-storage-error` |
| 음성 비교 | `speech-lab`, `speech-lab-recording`, `speech-lab-running`, `speech-lab-error`, `speech-lab-results` |
| 문장 비교 | `text-lab`, `text-lab-confirm`, `text-lab-running`, `text-lab-error`, `text-lab-results` |

진행·오류 화면은 상태의 크기와 행동 경계를 확인하는 합성 장면이다. 가상의 CER·성능·모델 정확도·비용 측정값을 만들지 않았다. 문장 비교 결과 적용 버튼은 미완료 상태에서 비활성으로 표시한다. 파일 선택·저장·삭제·클립보드 복사는 시안 안내만 낸다. 화면 중 `... · 예시`, `—` 값은 실제 사용자 데이터가 아니다.

HTML에서 모든 기존 비동기·포커스 경쟁 상태를 실행한 것은 아니다. 별도 화면을 만들지 않은 기록 재처리 진행/오류, 사전 저장 중/실패, 모델 미선택/샘플 없음, 사례5개/모델3개 상한, 검토 불가 모드는 위 매핑의 상태 계약을 구현 단계에서 반드시 반영한다. 이 설계 범위를 앱 구현 완료로 보고하지 않는다.

## 좁은 창·키보드·접근성 계약

- 기본 콘텐츠는 공통 4/8/12/16/24/32pt 간격, 헤더52pt·사이드바208pt·최대1184pt를 따른다. 960px 창에서도 검색·개수·더보기를 한 줄에 억지로 고정하지 않는다. 매우 좁으면 목록/상세와 입력 두 열을 한 열로 쌓는다. 네이티브 최소900×640 정책 변경은 별도 판단이다.
- 기록 목록은 요약만 두 줄로 제한하고 상세 전문은 잘라 숨기지 않는다. 한영 혼용·긴 개발 식별자·URL·100자 사전 표기도 줄바꿈·선택·복사가 가능해야 한다. 다중 열 표의 긴 내용은 행 높이를 늘리고 가로 오버플로를 창 전체로 전파하지 않는다.
- 목록은 선택된 행을 색 외에 접근성 선택 상태로 알린다. 네이티브 구현에서는 `List`의 방향키·선택 동작을 유지하고, `Tab`은 검색→목록→상세의 실제 작업 순서로 이동한다. 검색을 지우거나 sheet를 닫으면 원래 제어로 포커스를 돌린다.
- `?`는 28~32pt 버튼, `옵션명 도움말` 접근성 이름, 눈에 보이는 포커스, 클릭/키보드로 열기, Escape 닫기·포커스 복귀, 화면 경계 제한을 공통 계약으로 사용한다. hover는 보조로만 쓴다. 동시에 하나만 연다.
- 상태 변경은 텍스트와 짧은 상태 배지로 표현한다. 녹음/처리 중 알림은 과도하게 매 프레임 읽지 않는다. 오류는 원인을 선택해 복사할 수 있게 하고 취소·실패·만료를 같은 ‘완료’ 문구로 합치지 않는다.
- 잠긴 control의 이유와 도움말은 읽을 수 있어야 한다. 실제 수정/저장/전송/삭제 gate는 preview·설정 복구 필요·busy·상한·검증 상태에 따라 보존한다. 도움말을 읽게 하려고 부모 전체 disabled를 해제한 뒤 쓰기 action을 열어 두지 않는다.
- 이 문서는 색상 대비나 VoiceOver 실측 통과를 주장하지 않는다. 기본/다크·키보드·긴 문구/좁은 창의 실제 네이티브 검증은 구현 단계에 필요하다.

## 검증과 인계

본 담당이 완료한 정적 검사: JavaScript 구문, 중복 화면 ID 없음, 제목 아래 설명 문단 없음, 모든 `data-help` 버튼에 접근성 이름 존재. 받아쓰기 기록의 검토 연결은 `data-review-source/result/origin` 합성 속성을 A가 읽는 로컬 시안 계약이다. 외부 화면 연결은 A/B 소유 `home-ready`, `review-confirm`, `candidate-review-confirm`, `models`, `settings-privacy`이다. 공통 CSS·라우팅·실제 브라우저 크기 및 포커스 검증은 메인 담당이다.

구현 순서는 데이터 저장·처리 모델을 유지한 채 ① 사전 목록 우선/등록 sheet ② 기록 목록·상세 분할 ③ 사용량 및 비교실 밀도 통일이 적절하다. 다른 AI의 기능 변경이 진행 중이므로 기능 reducer/저장 코드를 동시에 바꾸지 않고 기존 View에서 상태와 action을 그대로 새 배치에 연결한다. 각 단계의 검토 기준은 ‘기능 수’가 아니라 기본 화면에서 먼저 찾는 요소, 필수 상태의 가시성, 기존 승인·보관·취소 계약 보존이다.
