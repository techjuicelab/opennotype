# OpenNoType 0.2.11 설정·탐색 일관성 점검

작성일: 2026-10-15  
상태: 구현·소스 교차 검토·로컬 검사·선택한 네이티브 경로·이 Mac 설치 보존 검증을 마쳤습니다. 소스 CI도 성공했습니다. 태그/배포 CI·익명 공개 자산·Latest 검증도 통과했으며 최종 결과는 [릴리스 검증 보고서](release-0.2.11.md)에서 관리합니다.

## 목적과 범위

설정·메뉴·버튼을 실제 동작의 목적에 맞게 정리합니다. 같은 기능이 여러 화면에 보이더라도 정식 설정 위치는 하나로 두고, 다른 화면은 현재 상태나 정확한 설정 링크를 제공합니다. 설정 열기, 내용 조회, 녹음·API 실행, 저장·삭제를 버튼 이름으로 구별합니다.

조사 시작 체크아웃은 `452df2b05f42e1caceb278f6a1b8be8497a5f656`이고, 최종 앱 소스는 `d4e54ce2249c4ed7a2e9e79729518c3d63cc7e26`입니다. 아래 기존 문제와 수정 후 목적지를 대조했으며, 소스 링크는 최종 커밋에 고정했습니다.

기록·사전·복구·사용량·두 모델 비교 도구의 기존 기능을 유지합니다. 음성 인식·문장 생성·검토 알고리즘, 모델·키 선택값, API 전송·예산·승인, 저장 스키마, 기록 삭제 범위, 복구 만료 정책은 이번 정리의 변경 대상이 아닙니다. 키 값이나 개인 기록 내용을 점검 문서에 담지 않습니다.

## 실제 병렬 구성

메인 포함 4개 에이전트가 실제로 병렬 조사·구현하고 서로 교차 검토했습니다.

| 역할 | 실제 에이전트 | 담당·소유 범위 | 확인한 상태 |
|---|---|---|---|
| 메인 | `/root` | 중앙 `SettingsSection`·`SettingsDetail` 목적지 계약, `AppModel.openSettings`, 사이드바·앱 메뉴·메뉴바 정식명, 통합·테스트·네이티브 검증·후속 릴리스 | 중앙 API·로컬/원격 검사·선택한 네이티브 경로·설치·공개 배포 검증 완료 |
| A | `/root/ux_primary_flow` | Home의 준비 상태·권한·Jev·화자 설정 진입과 입력 테스트 명명. 실제 수정은 `HomeView.swift` | 저장·parse·diff 검수 완료. 메인이 Home 권한 상세 진입 확인 |
| B | `/root/ux_settings_architecture` | 설정 6탭과 보조 설정 화면의 정식 소유 위치, AI 연결·자동 검토·개인정보·권한·진단 목적 분리 | 저장·parse·diff 검수 완료. C 독립 소스 검토와 메인 선택 경로의 네이티브 확인 |
| C | `/root/ux_visual_copy` | 전체 탐색·명명 횡단 조사, `DataViews`·`UsageView`·음성/문장 모델 비교. CaseBindings는 소유 범위지만 이번 변경 없음 | 4파일 저장·parse·diff 검수 완료. 독립 설치 보존 검증과 문서 정리 |

## 기존 문제와 최종 목적지

| 실제 확인한 문제 | 최종 목적지·동작 계약 | 상태·근거 |
|---|---|---|
| 동일한 `.usage`에 ‘사용량’, ‘사용량과 비용’, ‘사용량과 비용 보기’, ‘사용량·비용’, ‘사용량 보기’가 혼재했습니다. | 페이지·사이드바 정식명은 **사용량·비용**, 조회 버튼은 **사용량·비용 보기**. 사용량 화면 헤더는 `AppPage.usage.title`을 참조합니다. | C 헤더 반영. 메인·B 정식명 반영. 설치 앱 View 메뉴의 정식명 확인. [UsageView](https://github.com/techjuicelab/opennotype/blob/d4e54ce2249c4ed7a2e9e79729518c3d63cc7e26/Sources/OpenNoType/Views/UsageView.swift#L22) |
| 사용량 수집 토글은 ‘사용량 기록’인데 해당 설정 진입은 ‘통계 기록 설정’이었습니다. 빈 화면의 ‘모델 설정 보기’는 음성 모델 페이지가 아니라 AI 연결 탭을 열었습니다. | **사용량 기록 설정… → 개인정보**. 빈 사용량 화면의 연결 안내는 **AI 연결 설정… → AI 연결**. 필터만 해제하는 동작은 **전체 사용량 보기**입니다. | C 반영. [UsageView](https://github.com/techjuicelab/opennotype/blob/d4e54ce2249c4ed7a2e9e79729518c3d63cc7e26/Sources/OpenNoType/Views/UsageView.swift#L39), [빈 화면](https://github.com/techjuicelab/opennotype/blob/d4e54ce2249c4ed7a2e9e79729518c3d63cc7e26/Sources/OpenNoType/Views/UsageView.swift#L157) |
| 개인정보와 개인 사전에서 `automaticLearningEnabled`를 각각 토글했습니다. 사전의 교정 학습과 Jev 오류 유형 학습은 다른 데이터를 다루는데 이름만으로 구분하기 어려웠습니다. | 자동 표기 학습의 정식 설정은 **개인정보**. 개인 사전 **교정 학습** 탭은 켜짐/꺼짐, 확인할 후보, 되돌리기와 **학습 설정…** 링크를 제공합니다. Jev **오류 유형 학습**은 별도 항목으로 유지합니다. | C 중복 토글 제거. B 개인정보의 정식 토글 유지와 C 중복 토글 제거를 소스 대조. 메인이 사전 교정 학습→개인정보 이동 확인. [사전 현황](https://github.com/techjuicelab/opennotype/blob/d4e54ce2249c4ed7a2e9e79729518c3d63cc7e26/Sources/OpenNoType/Views/DataViews.swift#L355), [별도 학습 모델](https://github.com/techjuicelab/opennotype/blob/d4e54ce2249c4ed7a2e9e79729518c3d63cc7e26/Sources/OpenNoType/Views/JevAssistanceSettingsViews.swift#L12) |
| ‘같은 음성 비교’·‘승인 문장 비교’가 실행처럼 보이지만 실제로는 비교 sheet를 열었습니다. 문장 비교는 Jev 상세와 실험 탭 양쪽에 있었습니다. | 정식 도구 위치는 **실험·진단**. 화면 진입은 **비교 도구 열기…**. 음성 비교의 실행은 **비교 시작**, 문장 비교의 전송 확인 진입은 **비교 시작…**, 최종 승인은 **전송하고 비교**입니다. 음성 모델 페이지는 같은 음성 비교 도구로 이어지는 관련 도구 링크를 유지할 수 있습니다. | C 실행 이름 반영. B 실험·진단으로 정식 진입 정리 확인. 비교 녹음·API 실행은 미실시. [음성 실행](https://github.com/techjuicelab/opennotype/blob/d4e54ce2249c4ed7a2e9e79729518c3d63cc7e26/Sources/OpenNoType/Views/SpeechComparisonLabView.swift#L107), [문장 확인](https://github.com/techjuicelab/opennotype/blob/d4e54ce2249c4ed7a2e9e79729518c3d63cc7e26/Sources/OpenNoType/Views/JevModelComparisonView.swift#L140), [전송 승인](https://github.com/techjuicelab/opennotype/blob/d4e54ce2249c4ed7a2e9e79729518c3d63cc7e26/Sources/OpenNoType/Views/JevModelComparisonView.swift#L75) |
| Jev 연결·자동 검토 설정·보조 기능·실제 결과 조회가 하나의 상세 화면에 섞여 여러 탭에서 진입했습니다. | **AI 연결 → 문장 검토 연결 · Jev**, **받아쓰기 → 자동 문장 검토·검토 도움 설정**, **개인정보 → 오류 유형 학습**, **실험·진단 → 문장 모델 비교**. 실제 결과는 Home·기록·교정 후보 맥락에서 조회합니다. | 중앙 enum과 B 상세 분리 일치 확인. 메인이 정책/연결 분리와 공유 키 상세 이동·복귀 확인. [SettingsDetail](https://github.com/techjuicelab/opennotype/blob/d4e54ce2249c4ed7a2e9e79729518c3d63cc7e26/Sources/OpenNoType/App/SettingsNavigation.swift#L32) |
| 설정의 ‘결과·표기 제안’은 `.history`만 열어 오래된 검토 대상의 `sourceHistoryID`를 선택하지 않았습니다. 기록의 선택은 로컬 상태이며 기본값은 최신 기록이므로 엉뚱한 기록에 도착할 수 있었습니다. | 설정에서 결과 조회 링크를 제거합니다. 기록·최근 결과·교정 후보의 해당 원문과 결과에 붙은 검토 UI를 사용합니다. 이번 정리에서 새로운 기록 선택 상태를 추가하지 않습니다. | 문제 소스 확인 후 B 최종 소스에서 해당 설정 결과 링크 제거 확인. [기록 선택 상태](https://github.com/techjuicelab/opennotype/blob/d4e54ce2249c4ed7a2e9e79729518c3d63cc7e26/Sources/OpenNoType/Views/DataViews.swift#L29), [선택 조정](https://github.com/techjuicelab/opennotype/blob/d4e54ce2249c4ed7a2e9e79729518c3d63cc7e26/Sources/OpenNoType/Views/DataViews.swift#L103), [기록별 검토](https://github.com/techjuicelab/opennotype/blob/d4e54ce2249c4ed7a2e9e79729518c3d63cc7e26/Sources/OpenNoType/Views/DataViews.swift#L165) |
| ‘단어 추가’, ‘표기 확인하고 등록’, ‘현재 설정으로 복구’는 즉시 저장·처리하는 듯 보이지만 각각 편집 sheet·확인 대화상자를 열었습니다. | **단어 추가…**, **표기 확인…**, **현재 설정으로 다시 처리…**로 다음 단계가 있음을 표시합니다. 실제 저장·처리의 기존 버튼과 실행 조건은 유지합니다. | C 반영. [단어 추가](https://github.com/techjuicelab/opennotype/blob/d4e54ce2249c4ed7a2e9e79729518c3d63cc7e26/Sources/OpenNoType/Views/DataViews.swift#L294), [표기 확인](https://github.com/techjuicelab/opennotype/blob/d4e54ce2249c4ed7a2e9e79729518c3d63cc7e26/Sources/OpenNoType/Views/DataViews.swift#L397), [재처리 확인 진입](https://github.com/techjuicelab/opennotype/blob/d4e54ce2249c4ed7a2e9e79729518c3d63cc7e26/Sources/OpenNoType/Views/DataViews.swift#L700) |
| Home의 ‘Mac 권한’은 실험·진단의 전체 탭을, ‘Jev 연결 설정’은 AI 연결 전체 탭을 열었습니다. | 권한 부족은 **Mac 접근 권한** 상세, Jev 연결 부족은 **문장 검토 연결 · Jev** 상세를 직접 엽니다. 자동 검토 동작 변경은 연결 설정과 구분합니다. | A 반영과 중앙 매핑 확인. 메인이 Home의 Mac 접근 권한 버튼이 정확한 상세를 여는 것을 확인. [HomeView](https://github.com/techjuicelab/opennotype/blob/d4e54ce2249c4ed7a2e9e79729518c3d63cc7e26/Sources/OpenNoType/Views/HomeView.swift#L106), [중앙 매핑](https://github.com/techjuicelab/opennotype/blob/d4e54ce2249c4ed7a2e9e79729518c3d63cc7e26/Sources/OpenNoType/App/SettingsNavigation.swift#L37) |

### 학습·사전·이름의 서로 다른 계약

- **고친 표기 자동 학습**: 입력 완료 후 같은 입력창에서 관찰한 제한적인 교정을 개인 사전에 반영합니다. 개인정보에서 설정하고 사전에서 현황·후보·되돌리기를 확인합니다.
- **교정 후보 확인**: 자동 등록하기 어려운 표기를 사람이 확인합니다. Jev 검토와 사전 저장은 별도 승인입니다. 검토만으로 사전이나 이미 입력한 글을 바꾸지 않습니다.
- **Jev 오류 유형 학습**: 정해진 오류 범주만 문장 제공자·모델별로 기억하며 개인 사전의 표기 쌍과 별개입니다. 과거 원문·교정문을 저장하는 기능이나 AI 모델 재학습이 아닙니다.
- **이름 후보**: 앱·프로젝트 이름 카탈로그입니다. 개인 사전의 인식 표기→원하는 표기 쌍과 다릅니다. 이름 후보 등록과, 특정 문장의 이름을 찾기 위해 전송하는 실행도 구분합니다.

근거: [개인 사전의 학습·후보](https://github.com/techjuicelab/opennotype/blob/d4e54ce2249c4ed7a2e9e79729518c3d63cc7e26/Sources/OpenNoType/Views/DataViews.swift#L355), [Jev 오류 유형](https://github.com/techjuicelab/opennotype/blob/d4e54ce2249c4ed7a2e9e79729518c3d63cc7e26/Sources/OpenNoType/Views/JevAssistanceSettingsViews.swift#L12), [이름 후보 카탈로그](https://github.com/techjuicelab/opennotype/blob/d4e54ce2249c4ed7a2e9e79729518c3d63cc7e26/Sources/OpenNoType/Views/JevAssistanceViews.swift#L21), [이름 찾기 확인](https://github.com/techjuicelab/opennotype/blob/d4e54ce2249c4ed7a2e9e79729518c3d63cc7e26/Sources/OpenNoType/Views/JevAssistanceViews.swift#L140).

## 6개 설정 탭과 보조 화면의 정식 소유 위치

아래는 중앙 enum에 반영된 공통 계약입니다. B 최종 6탭과 15상세의 소스·호출 대조에서 소유 관계가 일치함을 확인했습니다. 메인이 6탭과 아래에 열거한 상세 이동·복귀를 실제 창에서 확인했습니다. 15상세 전체의 모든 동작을 실행한 결과는 아닙니다. 기존 `rawValue`는 유지합니다.

| 탭 | 정식 책임 | 소유 상세 화면 |
|---|---|---|
| 받아쓰기 | 입력 처리·출력 언어·표현·말투·번역·자동 검토 동작 | `jev`, `assistance`, `profiles` |
| 녹음·단축키 | 마이크 선택·녹음 피드백·단축키 조합과 동작 | 녹음·단축키 행. 권한 관리는 앱 설정으로 연결 |
| AI 연결 | 음성 인식·문장 처리·문장 검토의 제공자·API 키·모델·연결 확인 | `speech`, `text`, `reviewConnection` |
| 개인정보 | 외부 문맥 허용·기록 보관·표기 자동 학습·오류 유형 기억·사용량 수집 | `context`, `learning` |
| 앱 설정 | 앱 언어·화면·로그인 실행·업데이트·Mac 권한·실제 입력 테스트·고지 | `permissions`, `typingTest`, `licenses` |
| 실험·진단 | 실험적 인식·화자 기능·비교 도구·처리 시간 | `speaker`, `comparison`, `speechComparison`, `diagnostics` |

근거: [탭 이름](https://github.com/techjuicelab/opennotype/blob/d4e54ce2249c4ed7a2e9e79729518c3d63cc7e26/Sources/OpenNoType/App/SettingsNavigation.swift#L4), [상세 소유 관계](https://github.com/techjuicelab/opennotype/blob/d4e54ce2249c4ed7a2e9e79729518c3d63cc7e26/Sources/OpenNoType/App/SettingsNavigation.swift#L37).

### 상세 화면 진입 inventory

아래 15개는 별도 설정 목적지입니다. ‘같은 버튼 이름’만으로 합치지 않고 행 제목·소유 탭을 함께 읽어 목적을 구별합니다. 표는 15개 전체의 소스 대조 결과이며, 실제로 연 네이티브 경로의 범위는 뒤의 검증 표에 별도로 기록했습니다.

| 상세 ID·제목 | 진입하는 실제 행·버튼 | 도착 후 제공하는 동작 |
|---|---|---|
| `speech` · 음성 인식 연결 | AI 연결의 음성 인식 **연결 설정…**; 공유 음성 키의 **공유 키 설정…** | 인식 위치·제공자·키·음성 모델. 로컬이면 음성 모델 관리로 이동 |
| `text` · 문장 처리 연결 | AI 연결의 문장 처리 **연결 설정…**; Jev 공유 키의 **공유 키 설정…** | 문장 제공자·공유/독립 키·모델 |
| `reviewConnection` · 문장 검토 연결 · Jev | AI 연결의 문장 검토 **연결 설정…**; 부족 상태의 연결 설정 | Jev 제공자·키·고정 검토 모델·합성 문장 연결 테스트 |
| `jev` · 자동 문장 검토 | 받아쓰기의 자동 문장 검토 **설정…**; 개인정보 **검토 설정…** | 자동 검토 모드·번역 보호·보조 모델. 키 설정과 분리 |
| `assistance` · 검토 도움 설정 | 자동 문장 검토 상세의 추가 도움 기능 **설정…** | Jev 보조 옵션. 실제 결과를 보내 검토하는 버튼은 아님 |
| `learning` · 오류 유형 학습 | 개인정보의 검토 오류 유형 학습 **학습 설정…**; 자동 검토 상세의 **학습 설정…** | 오류 범주 기억·현재 상태·오류 유형 삭제 |
| `profiles` · 앱별 작성 방식 | 받아쓰기의 앱별 작성 방식 **설정…** | 앱별 형식·말투·기본값 복원 |
| `context` · 주변 문맥 허용 | 개인정보의 앱별 주변 문맥 **설정…** | 허용 앱 추가·해제. 허용된 앱의 주변 글 추가 전송 |
| `permissions` · Mac 접근 권한 | 앱 설정 **권한 설정…**; Home의 권한 부족 진입 | 권한 상태·마이크 사용 요청·각 시스템 설정 열기 |
| `typingTest` · 입력 테스트 | 앱 설정 **입력 테스트…**; Home 준비 상세의 해당 설정 | 녹음·API 없는 실제 입력 테스트 준비·예약·취소 |
| `diagnostics` · 처리 진단 | 실험·진단 **진단 보기…** | 최근 입력 로그·처리 시간 조회. 테스트 실행은 앱 설정 소유 |
| `comparison` · 문장 모델 비교 | 실험·진단 **비교 도구 열기…** | 사례·정답·모델·예산 승인 후 외부 전송 비교. 모델 적용은 수동 |
| `speechComparison` · 음성 모델 비교 | 실험·진단·음성 모델 관련 도구 **비교 도구 열기…** | 비교 녹음·파일 선택·정답·다운로드된 로컬 모델 선택과 실행 |
| `speaker` · 내 목소리 구분 | 실험·진단·음성 모델 관련 도구 **설정…**; Home 화자 준비 진입 | 화자 모델 준비·목소리 등록·삭제·필터. 실사용 성능 미검증 상태 유지 |
| `licenses` · 모델·라이선스 | 앱 설정의 모델·오픈소스 고지 **라이선스** | 고지·모델 출처 링크 조회 |

근거: [상세 렌더링 switch](https://github.com/techjuicelab/opennotype/blob/d4e54ce2249c4ed7a2e9e79729518c3d63cc7e26/Sources/OpenNoType/Views/SettingsView.swift#L613), [중앙 상세 이름·소유](https://github.com/techjuicelab/opennotype/blob/d4e54ce2249c4ed7a2e9e79729518c3d63cc7e26/Sources/OpenNoType/App/SettingsNavigation.swift#L32). 공유 키 상세는 **뒤로**, 일반 상세는 **닫기**로 이동/종료하며 키 저장·모델 선택 자체를 대신하지 않습니다. [상세 뒤로 경로](https://github.com/techjuicelab/opennotype/blob/d4e54ce2249c4ed7a2e9e79729518c3d63cc7e26/Sources/OpenNoType/Views/SettingsView.swift#L636), [공통 sheet](https://github.com/techjuicelab/opennotype/blob/d4e54ce2249c4ed7a2e9e79729518c3d63cc7e26/Sources/OpenNoType/Views/SettingsView.swift#L754)

## 사이드바·메뉴·내부 경로 inventory

| 진입면 | 항목 | 실제 목적지·계약 |
|---|---|---|
| 사이드바 | 받아쓰기 / 기록 / 개인 사전 / 음성 모델 / 사용량·비용 / 설정 | 각각 `AppPage.home/history/dictionary/voice/usage/settings`. 실패 녹음은 기록 안 **녹음 복구** 탭이며 `.recovery`일 때 기록 사이드바를 선택 표시 |
| 기록 탭 | 처리 기록 / 녹음 복구 | `.history` / `.recovery`. 텍스트 보관 기간과 실패 원음 최대 24시간 보관을 분리 |
| 개인 사전 탭 | 단어 / 교정 학습 / 이름 후보 | `$model.dictionarySection`. 학습 정식 설정은 개인정보로 연결하며 후보·되돌리기는 사전 맥락 유지 |
| 메인 상단 | AI 연결 설정 진입 | 중앙 `openSettings(.connection)` 계약. 이전 상세가 남아 있으면 초기화 |
| 사이드바 하단 | 이 Mac에 보관 | 중앙 `openSettings(.privacy)` 계약 |
| 앱 메뉴 | 설정… / 사용량·비용 / 음성 모델 / 업데이트 확인… | 설정, 사용량 조회, 음성 모델 관리, updater 확인 동작. 설치 앱 View 메뉴의 사용량·비용/음성 모델 명칭 확인; 업데이트 실행은 미실시 |
| 메뉴바 | 작업별 입력 모드 + 단축키 | `model.toggle(mode)` 실행. 설정 화면 링크가 아니며 녹음 중 같은 모드의 종료 동작 유지 |
| 메뉴바 | 현재 작업 취소 | `model.cancel()` 실행. busy 또는 기록 재처리 중에 표시 |
| 메뉴바 | OpenNoType 열기 | 현재 페이지를 다시 열고 앱 활성화 |
| 메뉴바 | 사용량·비용 | `.usage` 조회. 정식 페이지 이름 재사용 |
| 메뉴바 | 실패한 녹음 다시 처리 · n개 | `.recovery` 조회. 실패 항목이 있을 때만 표시 |
| 메뉴바 | 설정… / 종료 | 설정 창 열기 / 앱 종료 요청. 기존 preview·작업 중 종료 보호 유지 |
| Home 준비 상태 | 권한·Jev 연결·화자·모델 부족 | 중앙 detail/section 경로로 문제에 해당하는 상세 또는 모델 페이지에 도착. A 변경 통합. Home의 Mac 권한 상세 직행을 메인이 확인 |
| 결과에서 개인 사전 | 개인 사전 열기 / 앱·프로젝트 이름 후보 등록 | 각각 `.dictionary`의 `.words` / `.names`를 명시 선택 |
| 사용량의 설정 링크 | 사용량 기록 설정… / AI 연결 설정… | 중앙 `openSettings(.privacy)` / `.connection` |
| 모델 관련 도구 | 음성 모델 비교·내 목소리 구분 | 같은 비교 도구·같은 화자 상세를 여는 관련 링크. 별도 정책·중복 모델 설정을 만들지 않음 |

근거: [사이드바·페이지](https://github.com/techjuicelab/opennotype/blob/d4e54ce2249c4ed7a2e9e79729518c3d63cc7e26/Sources/OpenNoType/Views/MainView.swift#L140), [기록 탭](https://github.com/techjuicelab/opennotype/blob/d4e54ce2249c4ed7a2e9e79729518c3d63cc7e26/Sources/OpenNoType/Views/DataViews.swift#L6), [사전 탭](https://github.com/techjuicelab/opennotype/blob/d4e54ce2249c4ed7a2e9e79729518c3d63cc7e26/Sources/OpenNoType/Views/DataViews.swift#L298), [앱 메뉴](https://github.com/techjuicelab/opennotype/blob/d4e54ce2249c4ed7a2e9e79729518c3d63cc7e26/Sources/OpenNoType/App/OpenNoTypeApp.swift#L116), [메뉴바 구성](https://github.com/techjuicelab/opennotype/blob/d4e54ce2249c4ed7a2e9e79729518c3d63cc7e26/Sources/OpenNoType/App/StatusBarController.swift#L79), [메뉴바 실제 selector](https://github.com/techjuicelab/opennotype/blob/d4e54ce2249c4ed7a2e9e79729518c3d63cc7e26/Sources/OpenNoType/App/StatusBarController.swift#L115), [사전 단어 진입](https://github.com/techjuicelab/opennotype/blob/d4e54ce2249c4ed7a2e9e79729518c3d63cc7e26/Sources/OpenNoType/Views/JevReviewView.swift#L127), [이름 후보 진입](https://github.com/techjuicelab/opennotype/blob/d4e54ce2249c4ed7a2e9e79729518c3d63cc7e26/Sources/OpenNoType/Views/JevAssistanceViews.swift#L133).

이 문서에서 딥링크는 앱 내부의 정확한 탭·상세 화면 이동을 뜻합니다. 현재 소스에서 사용자 정의 URL scheme 등록(`CFBundleURLTypes`)이나 `onOpenURL` 처리 경로는 확인되지 않았습니다. 새 외부 URL/CLI 진입 기능을 추가하는 작업이 아닙니다. [Info.plist](https://github.com/techjuicelab/opennotype/blob/d4e54ce2249c4ed7a2e9e79729518c3d63cc7e26/Resources/Info.plist#L1)

중앙 `openSettings(section)`은 기존 상세를 닫고 해당 탭을 엽니다. `openSettings(detail)`은 상세의 정식 소유 탭을 먼저 선택한 뒤 상세를 엽니다. 설정값·vault를 변경하는 API가 아닙니다. [AppModel](https://github.com/techjuicelab/opennotype/blob/d4e54ce2249c4ed7a2e9e79729518c3d63cc7e26/Sources/OpenNoType/App/AppModel.swift#L1126)

## 버튼 이름 규칙

| 목적 | 규칙 | 예 |
|---|---|---|
| 페이지·탭 이름 | 짧은 명사, 같은 정식명 재사용 | 사용량·비용, AI 연결, 음성 모델 |
| 설정·편집 sheet 열기 | 대상 + 설정/관리/추가 + `…`; 실행으로 오인될 동사 피하기 | 학습 설정…, 단어 추가…, 연결 설정… |
| 도구 열기 | 실행과 분리한 진입명 | 비교 도구 열기… |
| 로컬 조회·필터 이동 | 대상 + 보기 | 사용량·비용 보기, 전체 사용량 보기, 비교 설정 보기 |
| 실제 시작·종료·취소 | 실행 동사와 필요한 대상 | 비교 시작, 비교용 녹음 시작, 녹음 종료, 비교 취소 |
| 외부 전송 확인 다음 단계 | 진입에는 `…`, 최종 확인에는 전송 동사 | 비교 시작… → 전송하고 비교 |
| 직접 저장·적용 | 저장 대상·효과를 명시 | 사전에 등록, 변경 저장, 이 문장 모델 적용 |
| 되돌리기·삭제 | 서로 다른 데이터 범위를 이름에 유지 | 마지막 자동 학습 되돌리기, 마지막 Jev 사전 저장 되돌리기, 사용량 기록 초기화 |
| 일반 설명 | 옵션 옆 `?`; 필수 비용·미적용·보류·권한 상태는 화면 유지 | 추가 API 비용, 준비 필요, 검토 실패 시 보류 |

`…`는 추가 입력·선택·확인이 필요하다는 표시입니다. 모든 클릭에 일괄적으로 붙이지 않습니다. 이미 승인한 동작을 바로 실행하는 버튼과, 단순 조회·필터 버튼에는 붙이지 않습니다. ‘검토’라는 말이 사람이 내용을 확인하는 동작인지 Jev에 전송하는 동작인지도 제목과 확인 단계로 구분합니다.

## C 범위의 보존 확인

C 변경 diff는 4개 View의 문구·설정 진입과 중복 자동학습 토글 제거에 한정됩니다. `JevModelComparisonCaseBindings.swift`는 변경하지 않았습니다.

- 녹음·파일 가져오기·비교 실행·취소 action과 `disabled` 조건은 유지했습니다.
- 문장 비교의 사례 승인, 예산·단가 설명, 전송 확인 대화상자, 수동 모델 적용 guard를 유지했습니다.
- 사전 편집·후보 처리·되돌리기·삭제·가져오기·내보내기의 기존 저장 guard를 유지했습니다. 조회에서 설정으로 이동하는 링크는 설정값을 쓰지 않습니다.
- 실패 녹음의 만료·원문 필수 조건·당시/현재 설정 구분과 개인정보 확인은 유지했습니다. ‘현재 설정으로 다시 처리…’는 기존 확인 대화상자를 엽니다.
- 사용량 집계·보고/추정/미확인 비용 구분·초기화 확인과 저장 보호를 유지했습니다.
- C는 UI 구현과 소스 검토에서 앱 실행·마이크 녹음·API 요청·외부 앱 입력·설정값 저장을 하지 않았습니다. 후속 설치 보존 검증에서는 비밀 값을 반환하는 옵션 없이 Keychain 존재 메타데이터만 조회하고 새 검증 JSON을 작성했습니다. 키 값과 개인 기록 내용은 읽거나 공개하지 않았습니다.

보존 근거: [복구 조건](https://github.com/techjuicelab/opennotype/blob/d4e54ce2249c4ed7a2e9e79729518c3d63cc7e26/Sources/OpenNoType/Views/DataViews.swift#L680), [문장 비교 승인·전송](https://github.com/techjuicelab/opennotype/blob/d4e54ce2249c4ed7a2e9e79729518c3d63cc7e26/Sources/OpenNoType/Views/JevModelComparisonView.swift#L75), [비교 예산](https://github.com/techjuicelab/opennotype/blob/d4e54ce2249c4ed7a2e9e79729518c3d63cc7e26/Sources/OpenNoType/Views/JevModelComparisonView.swift#L127), [사용량 초기화](https://github.com/techjuicelab/opennotype/blob/d4e54ce2249c4ed7a2e9e79729518c3d63cc7e26/Sources/OpenNoType/Views/UsageView.swift#L290).

## B 최종 소스 교차 검토

C가 B 저장·동결 통보 후 최종 `SettingsView`를 읽어 중앙 매핑과 대조했습니다. 기존 설정의 preferences 참조 필드는 모두 남아 있었고, 6탭·15상세에 연결·정책·실행·조회가 분리되어 있었습니다. 사용량의 AI 연결 탭 중복 진입, 번역 다듬기의 실험 탭 중복 토글, 잘못된 최근 검토 결과 링크가 제거된 것도 확인했습니다. 키의 공유·명시 저장·삭제, 검토 모드별 실패 정책, 비교의 전송·예산 승인, 권한과 저장 guard의 차단 결함은 발견하지 못했습니다. 이는 소스 교차 검토이며 실제 UI·API 동작의 성공 판정은 아닙니다.

메인·A·B의 후속 검토로 아래 보완이 반영됐고 C가 최종 소스를 다시 확인했습니다. 메인이 아래에 명시한 네이티브 경로를 추가 확인했습니다.

| 후속 보완 | 확인한 최종 코드·효과 | 소스 |
|---|---|---|
| 입력 테스트의 준비·권한 경계 | `canStartInputTest`가 preview·설정 복구 차단, `startupState == .ready`, 손쉬운 사용 허용, 작업 중 아님을 모두 요구합니다. 테스트 준비와 5초 예약 버튼에 같은 조건을 사용하고, 권한이 없으면 권한 설정으로 직접 연결합니다. 설정 화면을 여는 것만으로 테스트를 예약하지 않습니다. | [입력 테스트 조건](https://github.com/techjuicelab/opennotype/blob/d4e54ce2249c4ed7a2e9e79729518c3d63cc7e26/Sources/OpenNoType/Views/SettingsView.swift#L15), [입력 테스트 실행 행](https://github.com/techjuicelab/opennotype/blob/d4e54ce2249c4ed7a2e9e79729518c3d63cc7e26/Sources/OpenNoType/Views/SettingsView.swift#L542) |
| Home으로 복귀할 때 열린 상세 정리 | 권한 상세의 ‘처음부터 확인’은 `settingsDetail = nil` 후 `.home`으로 이동합니다. 이전 설정 상세가 다음 진입 때 남는 것을 막습니다. | [Home 복귀](https://github.com/techjuicelab/opennotype/blob/d4e54ce2249c4ed7a2e9e79729518c3d63cc7e26/Sources/OpenNoType/Views/SettingsView.swift#L590) |
| 사전 조회 명명 | 개인정보에서 사전 `.learning` 탭으로 이동하는 버튼은 ‘교정 학습 보기’입니다. Jev 전송 검토 실행과 구별합니다. | [교정 학습 조회](https://github.com/techjuicelab/opennotype/blob/d4e54ce2249c4ed7a2e9e79729518c3d63cc7e26/Sources/OpenNoType/Views/SettingsView.swift#L486) |
| 현재 값과 이동 동작 분리 | 받아쓰기의 로컬 모델과 음성 모델의 현재 인식은 `Text`로 값을 보여주고, 별도 ‘모델 보기’·‘연결 설정…’ 버튼으로 이동합니다. | [로컬 모델 값·동작](https://github.com/techjuicelab/opennotype/blob/d4e54ce2249c4ed7a2e9e79729518c3d63cc7e26/Sources/OpenNoType/Views/SettingsView.swift), [현재 인식 값·동작](https://github.com/techjuicelab/opennotype/blob/d4e54ce2249c4ed7a2e9e79729518c3d63cc7e26/Sources/OpenNoType/Views/SettingsView.swift#L794) |
| 앱 설정과 앱별 문체 구분 | ‘앱 설정’ 6탭 이름과 충돌하던 문체 상세의 패널 이름을 ‘앱별 작성 규칙’으로 바꿨습니다. 정식 `profiles` 상세 이름 ‘앱별 작성 방식’과 기능 계약은 유지합니다. | [앱별 작성 규칙](https://github.com/techjuicelab/opennotype/blob/d4e54ce2249c4ed7a2e9e79729518c3d63cc7e26/Sources/OpenNoType/Views/SettingsView.swift#L595) |
| 녹음 중 미리보기 중복 토글 제거 | 정식 토글은 실험·진단에만 있습니다. 모델 상세에는 현재 사용 여부와 ‘실험 설정…’ 링크를 두고, 기존 미적용 상태·추가 연산 설명을 유지합니다. | [모델 상세의 현황·링크](https://github.com/techjuicelab/opennotype/blob/d4e54ce2249c4ed7a2e9e79729518c3d63cc7e26/Sources/OpenNoType/Views/VoiceInputOptionsView.swift#L141), [정식 실험 토글](https://github.com/techjuicelab/opennotype/blob/d4e54ce2249c4ed7a2e9e79729518c3d63cc7e26/Sources/OpenNoType/Views/VoiceInputOptionsView.swift#L159) |

새 `SettingsNavigationTests` 3개는 메인이 단일 검사 **3/3 통과**와 이후 전체 검사 통과를 보고했습니다. C는 테스트 소스를 읽어 권한 목적지의 소유 탭·이전 상세 교체, 연결 설정과 검토 동작의 서로 다른 소유 탭, 탭 이동 시 상세 초기화 및 입력 테스트 미예약을 검증함을 확인했습니다. fixture는 `useCachedKeys: true`이고 실제 credential 읽기 closure는 `XCTFail`로 막습니다. 이 테스트 자체는 네이티브 sheet 렌더링·뒤로·닫기·Escape·실제 외부 앱 입력 성공을 증명하지 않습니다. 네이티브 이동·복귀 관찰은 아래에 별도 기록했습니다. [격리 fixture](https://github.com/techjuicelab/opennotype/blob/d4e54ce2249c4ed7a2e9e79729518c3d63cc7e26/Tests/OpenNoTypePlatformTests/SettingsNavigationTests.swift#L8), [경로 테스트](https://github.com/techjuicelab/opennotype/blob/d4e54ce2249c4ed7a2e9e79729518c3d63cc7e26/Tests/OpenNoTypePlatformTests/SettingsNavigationTests.swift#L19)

## 검증 결과와 경계

| 검증 | 확인한 결과 | 증거 범위·제한 |
|---|---|---|
| 소스·구문·diff | C 소유 5파일 parse, C 변경 diff 검수 통과. A/B 저장·parse·diff 검수 보고. C가 설정 6탭·15상세의 소스와 중앙 owner를 독립 대조해 기존 preferences 참조 필드 누락 0, 차단 결함 미발견 | 소스 정합성 확인이며 모든 UI 동작의 실행 증거가 아님 |
| 로컬 Swift 전체 검사 | 메인 보고: **1,224개 중 1,222개 통과·기존 opt-in 2개 제외·실패 0** | 실제 음성 정확도·유료 API·모든 앱 입력을 검증한 수치가 아님 |
| 로컬 Python 전체 검사 | 메인 보고: **209개 중 207개 통과·환경 조건 2개 제외·실패 0** | 원격 Python 전체 통과와 구분 |
| 소스 CI | 메인이 [CI 38660778369](https://github.com/techjuicelab/opennotype/actions/runs/38660778369) 성공과 실제 로그의 Swift **1,222개 통과·2개 제외**, Python **209개 전부 통과**, 일반/Prompt Test 앱 빌드를 확인 | 태그/공개 배포 CI 및 익명 다운로드 검증과 별개 |
| 빌드·서명 | 메인이 DEBUG 합성 앱과 로컬 인증서의 arm64 release 앱 빌드·strict 서명 통과를 확인 | 공개 배포품과 로컬 설치품은 서명·SDK·바이너리 해시가 같다는 주장이 아님 |
| 네이티브 설정 구조 | 메인이 별도 식별자의 합성 앱에서 **6탭, AI 연결 3개 공통 카드, 검토 정책과 연결 분리**를 확인 | 폭 960pt 미리보기 창에서 확인. 창 높이와 1120×760pt는 정확히 수동 측정하지 않음 |
| 네이티브 이동·복귀 | **reviewConnection → 공유 문장 키 → 공유 음성 키 → 뒤로 두 번**, 닫기·Escape·다른 탭 선택, 비활성 권한 옵션의 `?` 열기·닫기와 도움말 버튼 포커스 복귀를 메인이 확인 | 키 변경·저장·연결 테스트를 실행한 것이 아님 |
| 네이티브 목적지 | **Mac 권한·입력 테스트 상세**, **사전 교정 학습→개인정보**, **Home Mac 권한→정확한 상세**, **모델 파일 sheet→실험 설정 이동 시 이전 sheet 닫힘**을 메인이 확인 | 실제 입력 테스트·녹음·비교 API는 미실시. 모든 15상세의 모든 동작을 전수 실행하지 않음 |
| 실제 설치 앱 UI | 메인이 **0.2.11(47), 준비됨, 세 연결의 저장 상태, 마이크·손쉬운 사용 허용, View 메뉴의 사용량·비용/음성 모델**을 CUA로 확인 | 저장됨·권한 허용과 API 인증·실제 외부 앱 입력 성공은 서로 다른 증거 |
| 설치 보존 독립 검증 | C가 이번 설치 직전→복사 직후→실행 후→실제 저장 파일 재해시를 대조해 **146파일 동일·추가/삭제/변경 0**, 보호 JSON 2개 의미 동일, 창 메타데이터 1개만 변경, 최신 Keychain 존재 메타데이터·서명 요구조건·entitlements 유지 확인 | 과거 0.2.10 백업은 기준으로 사용하지 않음. 키 값 미접근. [독립 설치 JSON](release-0.2.11-installation.json) |
| 공개 배포 | 태그/배포 CI 성공, 익명 6자산·해시·서명·키 연속성·ZIP/DMG·Latest·사이트 다운로드 진입 검증 통과 | 시간·자산별 해시와 실제 검증 경계는 [릴리스 검증 보고서](release-0.2.11.md)에 기록 |

소스·자동 검사·합성 네이티브 관찰·실제 설치와 보존은 각각 다른 증거입니다. 이번 정리에서는 실제 마이크 녹음, 유료 API 처리·인증, 외부 앱 입력, 입력 테스트 실행을 하지 않았습니다. 새 Mac Gatekeeper·TCC 재승인·Intel·VoiceOver 전수 검증도 수행하지 않았습니다.

메뉴바 테스트는 창을 닫아도 상태 항목과 재열기 경로가 유지되는 것, 설정 페이지 진입, 현재 작업 취소 표시, 한국어 변경, preview 입력 차단·종료를 검증합니다. 모든 6탭·보조 sheet의 목적지나 실제 사용자 입력 성공을 포괄하지 않습니다. [StatusBarControllerTests](https://github.com/techjuicelab/opennotype/blob/d4e54ce2249c4ed7a2e9e79729518c3d63cc7e26/Tests/OpenNoTypePlatformTests/StatusBarControllerTests.swift#L90), [메뉴 상태 테스트](https://github.com/techjuicelab/opennotype/blob/d4e54ce2249c4ed7a2e9e79729518c3d63cc7e26/Tests/OpenNoTypePlatformTests/StatusBarControllerTests.swift#L139).
