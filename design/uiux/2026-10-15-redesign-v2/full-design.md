# OpenNoType 전체 UI/UX 재디자인 설계 v2 — 통합본

2026-10-15. 메인 포함 4개 에이전트 병렬 설계·교차 검토 결과. **설계와 HTML 시안이며 현재 설치 앱에 적용된 버전이 아니다.**

이 한 파일에 전체 규격·화면 설계·소스 매핑·적용 계획·검증 경계를 모았다. 대표 화면은 [gallery.html](gallery.html), 직접 조작은 [index.html](index.html)에서 확인한다.

---

원본 문서: `README.md`

## OpenNoType 전체 재디자인 v2

2026-10-15 · 기준 소스 `d620ada3bf849f8ecae4948716089cedb08fa5a5` · 앱 0.2.9 (45)

**앱 전체의 크기·간격·정보 구조를 다시 설계한 결과물이다.** 기존 0.2.9의 설정 도움말 일부 적용과 구분한다. 이번 산출물은 설계 문서와 독립 HTML 시안이며, SwiftUI 소스·사용자 설정·설치 앱·공개 배포는 변경하지 않는다.

사용자가 제공한 설정·개인 사전·기록·시작하기 스크린샷 4장과 현재 소스의 모든 View 및 부속 UI를 기준으로 작성했다. 사용자 기록의 원문이나 API 키는 시안에 사용하지 않는다.

### 바로 검토하기

[대표 4화면 한눈에 보기](gallery.html) · [전체 설계 한 파일 MD](full-design.md) · [전체 클릭 시안 열기](index.html) · [공통 크기·간격 규격](design-system.md) · [전체 적용·인수인계](implementation-plan.md) · [화면·소스 누락 대조](source-coverage.md) · [실제 검증 기록](verification.md)

HTML을 브라우저로 열면 서버·패키지 설치 없이 작동한다. 기본 화면은 새 **설정 → 받아쓰기**다. 왼쪽 메뉴로 주요 화면을, 시안 바깥 상단의 `화면·상태` 선택으로 모든 부속 화면과 상태를 볼 수 있다. 같은 도구에서 960/1120/1440 창 크기, 다크 모드, 치수 표시를 확인한다.

시안의 버튼·입력은 브라우저 메모리의 가상 데이터에만 작용한다. 녹음·실제 붙여넣기·클립보드·키·API 호출·실제 파일 삭제는 수행하지 않는다. `키 저장됨`, `입력 확인됨` 등의 값도 디자인 상태를 설명하는 예시이며 현재 사용자의 준비 상태를 진단한 결과가 아니다.

최종 시안은 **106개 화면·상태**를 포함한다. 현재 소스에서 추출한 **49개 View 선언·23개 파일**을 대조했고, 브라우저에서는 3개 창 크기 × 라이트·다크의 **636개 렌더 조건**을 확인했다. 이는 HTML 시안 검증이며 실제 앱 적용·성능·인식 정확도의 증거가 아니다.

대표 화면: [설정](settings-light.png) / [개인 사전](dictionary-light.png) / [기록](history-light.png) / [홈](home-light.png) / [음성 모델](models-light.png) / [다크](settings-dark.png) / [도움말](help.png).

### 이번에 바뀌는 전체 구조

| 영역 | 기존 0.2.9에서 보이는 문제 | 새 설계 |
|---|---|---|
| 앱 전체 | 큰 카드 여백·제목·설명이 각 화면에 중복 | 208 사이드바 / 52 툴바 / 24 본문 여백 / 공통 타입·행·버튼 규격 |
| 설정 | 옵션마다 폭이 늘어나는 선택창, 많은 카드, 긴 스크롤 | 6개 목적별 하위 분류 / 관련 옵션 그룹 / 44행 / 240 값 영역 / 상세 설명 `?` |
| 개인 사전 | 목록보다 이름 후보·학습 설명·등록 카드가 먼저 표시 | 검색·표·단어 추가 우선 / 이름 후보·학습은 보조 탭 / 등록은 별도 편집 표면 |
| 기록 | 각 카드에 원문·복사·Jev·재처리 반복 | 56~72 목록 행 + 선택한 1건의 상세 / 복사 우선 / 고급 작업은 더보기 |
| 홈 | 긴 준비 체크와 큰 작업 카드가 본문 대부분을 차지 | 준비 상태 한 줄 / 단축키 요약 / 최신 결과 중심 / 문제 있는 준비 항목만 펼침 |
| 음성 모델 | 다운로드·메모리·옵션·화자 기능의 위계 혼합 | 사용 모델 요약 / 상태별 모델 목록 / 선택 모델 상세 / 고급 옵션 분리 |
| 복구·사용량·실험실 | 각자 다른 카드·설명·표 규격 | 같은 검색·목록·상세·표·진행·빈 상태 규칙 적용 |
| 팝오버·예시·검토·HUD | 본문 개편에서 빠지기 쉬운 부속 표면 | 같은 크기·도움말·상태·버튼 규격으로 별도 설계하고 소스 대조 |

### 한눈에 읽히는 규칙

1. 기본 화면은 **항목명 · 현재값 · 주요 행동**부터 보인다. 일반 설명·적용 범위·예외·배경·상한은 항목 옆 `?`로 읽는다.
2. 지금 필요한 **오류 / 미적용 이유 / 입력 보류 / 추가 비용 / 전송 직전 요약**만 짧게 직접 표시한다. 도움말을 읽지 않아도 다음 행동을 선택할 수 있어야 한다.
3. 화면별 주요 행동은 하나를 우선한다. 기록은 복사, 사전은 단어 추가, 실패는 다시 시도, 모델은 현재 상태에 맞는 다운로드/준비를 강조한다.
4. 옵션 하나마다 큰 카드를 만들지 않는다. 같은 목적의 3~7개 행을 묶고 구분선·레이블·값 열로 읽는다. 독립적인 작업 결과와 경고에만 별도 패널을 쓴다.
5. 화면별 새 크기를 임의로 만들지 않는다. 새 기능도 아래 공통 규격과 컴포넌트를 먼저 사용한다.

### 공통 규격 요약

| 요소 | 새 기본 규격 (macOS pt / 시안 100% CSS px) |
|---|---|
| 기본 창 / 최소 검토 창 | 1120×760 / 960×680 (브라우저 축소·시스템 글자 확대는 별도 검토) |
| 사이드바 / 앱 툴바 | 208 / 52 |
| 본문 바깥 여백 / 콘텐츠 최대 폭 | 24 / 1184 |
| 기본 설정 행 / 보조 상태 행 | 최소 44 / 최소 56, 긴 문구는 높이 증가 |
| 선택창·입력창 / 보조 버튼 / 주요 버튼 | 32 / 32 / 36 |
| 도움말 클릭 영역 / 아이콘 | 28 / 16~18 |
| 패널 안쪽 여백 / 패널 간격 / 모서리 | 16 / 16 / 10 |
| 페이지 제목 / 섹션 / 본문 / 부가 정보 | 22 / 15 / 13 / 12 |
| 목록 행 / 표 행 | 56~72 / 최소 44 |

기존 크기는 현재 소스의 `MainView` 본문 여백 30·최대 폭 920, `Surface` 안쪽 여백 22·내부 간격 18·반경 14에서 확인했다. 스크린샷 픽셀을 네이티브 pt로 추정해 측정값처럼 제시하지 않는다. 자세한 근거와 예외는 [규격서](design-system.md)에 있다.

### 실제 4개 에이전트 병렬 구성

| 담당 | 실제 소유 산출물 | 책임 |
|---|---|---|
| 메인 | index.html / system.css / prototype.js / system-screens.js / 공통 규격·커버리지·인수인계·검증 | 전체 구조와 토큰, 통합, 전체 화면 대조, 시안 검증 |
| A `ux_primary_flow` | primary-flow.md / primary-screens.js | 홈·첫 사용·녹음·처리·입력 결과·프롬프트·검토·HUD·메뉴바 |
| B `ux_settings_architecture` | settings-architecture.md / settings-screens.js | 전체 설정·음성 모델·권한·연결·예시·고급 옵션 |
| C `ux_visual_copy` | data-workflows.md / data-screens.js | 기록·개인 사전·복구·사용량·음성 및 문장 모델 테스트실 |

세 담당은 같은 시간에 각자 현재 코드를 읽고 소유 파일을 작성한다. 통합 후에는 다른 담당의 결과를 교차 검토하고 메인이 공통 스타일과 누락을 수정한다. 이름만 역할 분담한 단일 분석이 아니다.

### 이어서 구현할 때

이 시안을 화면 하나만 선택해 부분 적용하는 것이 완료 조건이 아니다. [implementation-plan.md](implementation-plan.md)의 전체 화면 체크리스트와 소스 대조표를 사용해 **공통 셸·요소 → 모든 주요 화면 → 모든 부속 표면·상태**를 같은 작업 범위에서 완성한다. 기능 코드의 binding·상태·권한·입력 대상·저장 정책은 보존하고 UI 구조만 옮긴다.

자세한 화면별 근거는 [기본 작업 흐름](primary-flow.md), [설정·모델 설계](settings-architecture.md), [데이터 작업 설계](data-workflows.md)에서 확인한다.

### 다른 채팅에서 이어가기

전체 내용을 한 파일로 읽으려면 [full-design.md](full-design.md)를 전달한다. HTML 시안은 폴더 전체를 함께 전달해야 한다.

다음 구현 작업의 요청 예시:

> 이 전체 설계 문서와 v2 시안을 기준으로 OpenNoType의 모든 화면·부속 UI를 구현해 주세요. 메인 포함 최소 4개 에이전트를 실제 병렬 실행하고, 공통 크기·간격·도움말 규격을 전체에 적용하세요. 기존 기능·설정·기록·권한·외부 입력 계약을 보존하고, 소스 대조표의 전 화면을 완료 기준으로 삼으세요. 실제 SwiftUI와 네이티브 창을 검증하고 부분 적용을 전체 완료로 보고하지 마세요. 버전업·설치·배포는 그 작업의 명시된 범위에 따르세요.

시안 묶음은 설계·이미지·HTML만 포함한다. 소스 링크는 원래 OpenNoType 저장소 경로 기준이며 앱 소스 자체는 묶음에 포함하지 않는다.

---

원본 문서: `design-system.md`

## 공통 크기·간격·컴포넌트 규격

### 설계 방향

키보드로 빠르게 사용하는 macOS 음성 입력 도구다. 웹 서비스의 큰 소개 영역 대신 **조용한 도구 창, 정렬된 값 열, 결과 중심 작업 공간**을 사용한다. 현재 브랜드의 녹색과 마이크의 주황색을 유지하되 색은 선택·진행·문제 상태를 구분하는 데 쓴다. 장식 카드·큰 제목·불필요한 설명을 반복하지 않는다.

서체는 macOS 시스템 서체(SF / Apple SD Gothic Neo)를 유지한다. 이름·문장 보존이 중요한 제품이므로 긴 고유명사와 숫자를 과도한 자간·전용 장식 서체로 흐리지 않는다. 숫자·버전·시간·단축키는 시스템 고정폭 서체를 쓴다.

### 실제 기존 소스 근거

기준 커밋 `d620ada3bf849f8ecae4948716089cedb08fa5a5`.

- [MainView.swift](../../../Sources/OpenNoType/Views/MainView.swift:21): 사이드바 212.
- [MainView.swift](../../../Sources/OpenNoType/Views/MainView.swift:32): 툴바 56, 가로 여백 30.
- [MainView.swift](../../../Sources/OpenNoType/Views/MainView.swift:36): 본문 요소 간격 24.
- [MainView.swift](../../../Sources/OpenNoType/Views/MainView.swift:42): 본문 여백 30, 콘텐츠 최대 폭 920.
- [MainView.swift](../../../Sources/OpenNoType/Views/MainView.swift:175): 공통 `Surface` 내부 간격 18, 여백 22, 반경 14.
- [MainView.swift](../../../Sources/OpenNoType/Views/MainView.swift:231): 홈의 별도 큰 제목·설명.
- [OpenNoTypeApp.swift](../../../Sources/OpenNoType/App/OpenNoTypeApp.swift:39): 기본 창 1010×730, 현재 최소 창은 MainView 900×640.
- [VoiceBar.swift](../../../Sources/OpenNoType/Views/VoiceBar.swift:9): HUD 450×80, 미리보기 상태 450×140, 비활성 패널.

위 값은 코드에서 확인한 사실이다. 새 치수는 **디자인 제안**이며 인식 속도·정확도 개선 수치가 아니다. 목록에 더 많은 항목이 보이는지는 시안과 네이티브 적용 후 창 크기별로 확인한다.

### 토큰

| 분류 | 토큰 | 값 | 적용 |
|---|---|---|---|
| 여백 | space.1 / .2 / .3 / .4 / .6 / .8 | 4 / 8 / 12 / 16 / 24 / 32 | 아이콘·연결 요소 / 버튼 묶음 / 그룹 머리 / 패널 / 본문 / 큰 상태 공간 |
| 창 | window.default / minimum / large | 1120×760 / 960×680 / 1440×900 | 관리 창 검토 기준. min 변경은 실제 긴문구·키보드 검증 후 확정 |
| 셸 | sidebar.width / toolbar.height | 208 / 52 | 고정 탐색·상태 영역 |
| 본문 | page.inset / page.maxWidth | 24 / 1184 | 창 확대 시 가독성을 지키는 전체 콘텐츠 폭 |
| 패널 | inset / gap / radius / border | 16 / 16 / 10 / 1 | 같은 목적의 행을 묶는 표면 |
| 행 | row.normal / status / list / table | 최소 44 / 56 / 56~72 / 44 | 높이 상한이 아님. 여러 줄이면 자동 증가 |
| 컨트롤 | field.height / secondary / primary | 최소 32 / 32 / 36 | 텍스트 확대 시 최소값만 사용 |
| 도움말 | hitArea / glyph | 28×28 / 13~14 | 항목명 바로 뒤, 버튼이 값의 hit area와 겹치지 않음 |
| 아이콘 | navigation / inline / major | 18 / 16 / 24 | 대부분 같은 두께의 SF Symbols |
| 제목 | page / section / emphasis | 22/30 semibold / 15/22 semibold / 13/20 medium | 글자 크기/줄 높이 |
| 본문 | body / secondary / utility | 13/21 regular / 12/18 regular / 12 monospaced | 본문·상태 / 부가 / 숫자·버전·시간 |
| 열 | setting.label / setting.value | 가변, 권장 208~280 / 240, 최대 280 | 값은 같은 오른쪽 열에, 예시 버튼이 있으면 그 안에서 분할 |
| 목록 | history.master / dictionary.columns | 280~320 / 원문·원하는 표기·상태·더보기 | 가로 공간이 충분할 때만 나란히 |
| 모달 | small / medium / comparison | 400 / 560 / 760~880 | 확인 / 편집 / 비교. 화면 높이를 넘으면 본문만 스크롤 |
| 팝오버 | width / inset / line | 320~360 / 16 / 21 | 제목·설명·닫기. 네이티브는 anchor popover, HTML은 안전한 modal 시연 |
| 전환 | state / page | 120~160ms / 0~120ms | reduce motion이면 이동·파형 애니메이션 축소 |

#### 색상

| 역할 | 라이트 | 다크 |
|---|---|---|
| 창 바깥 / 본문 바탕 | #EDF0F3 / #F8F9FA | #151A20 / #1E262E |
| 패널 | #FFFFFF | #232C35 |
| 사이드바 | #F5F6F7 | #1B222A |
| 주 텍스트 | #222A31 | #EDF2F6 |
| 보조 텍스트 | #58646F | #B0BDC8 |
| 선 | #DCE1E6 | #3B4856 |
| 선택·주요 행동 / 선택 배경 | #326B58 / #E8F1ED | #A0D8BC / #2A453B |
| 경고 / 배경 | #8B5219 / #FFF4E6 | #F2BE80 / #403226 |
| 오류·삭제 / 배경 | #B93838 / #FFF0EF | #FFA8A8 / #442A30 |
| 포커스 | #216DA3 | #87C8F3 |

기본 본문 색과 배경의 대비는 검증 문서에서 확인한다. 색상만으로 연결·입력 성공을 구분하지 않고 텍스트 레이블과 아이콘을 함께 사용한다. 선택 배경의 연한 색은 장식이며 상태의 유일한 표현이 아니다.

### 화면 구조와 줄바꿈

- 툴바에는 짧은 현재 위치와 연결 설정 진입만 둔다. 페이지 제목은 본문에 한 번, 일반 소개 문구는 필요할 때 `?`로 제공한다. 본문 위의 중복 분류·소개 레이블(eyebrow)은 표시하지 않는다.
- 좌측 메뉴는 받아쓰기 / 기록 / 개인 사전 / 음성 모델 / 사용량 / 설정. 복구는 기록 안의 별도 탭으로 옮기되 실패 원음의 별도 수명·권한을 유지한다. 실험실은 음성 모델·고급 설정에서 진입한다.
- 모든 화면은 같은 왼쪽·오른쪽 기준선과 제목 위치를 쓴다. 빈 화면도 현재 목적과 다음 행동을 같은 위치에 둔다.
- 설정 기본 행은 label + `?` + value/control. 부가 버튼도 값 영역 안에 두어 행마다 선택창 폭이 달라지지 않게 한다.
- 기본 최소 창 960에서 레이블을 1줄로 강제하거나 잘라내지 않는다. 행은 자동으로 높아지고, 필요한 경우 값 영역을 다음 줄에 둔다.
- 기록의 master/detail은 창 공간에 따라 280~320 + 나머지. 실제 앱 최소 폭에서 긴 결과가 읽히지 않으면 상세를 독립 뷰로 열고 뒤로 돌아가도 선택·검색·스크롤을 유지한다.
- 제목·설명은 축소(scaleEffect/minimumScaleFactor)하지 않는다. 긴 URL·개발 식별자는 결과 본문에서 줄바꿈하되 복사되는 원문은 그대로다.
- 1440 이상의 큰 창에서도 모든 레이블과 컨트롤을 바깥 끝으로 흩어 놓지 않는다. 페이지는 최대 1184이며 결과 본문은 65~80ch 정도의 읽기 폭을 권장한다.
- 브라우저의 760px 이하 대체 레이아웃은 검토 도구의 편의 기능이다. 이를 macOS 최소 창 지원 구현 완료로 주장하지 않는다.

### 모든 요소의 상태

| 요소 | 필수 상태와 규칙 |
|---|---|
| 버튼 | 기본·hover·pressed·focus·disabled·loading. 주요 행동은 화면당 하나 우선, 로딩으로 폭이 흔들리지 않음 |
| 입력창 | 비어 있음·입력 중·유효·오류·읽기 전용·disabled. 오류는 바로 아래 1줄, 제약 배경은 `?` |
| 선택창 | 현재값·검색/목록·전체 긴 이름·disabled. 열린 목록은 시스템 동작 유지 |
| 토글 | 켜짐·꺼짐·처리 중 변경 불가·현재 미적용. 저장값과 지금의 적용 여부를 분리 |
| 도움말 | 기본·hover·focus·열림·닫힘. 값이 disabled여도 읽힘. Escape·닫기·원래 버튼 포커스 복원 |
| 목록·표 | 기본·선택·hover·검색·빈 결과·처리 중·실패. 선택이 바뀌어도 사용 중인 상세 작업을 몰래 취소하지 않음 |
| 상세·편집 | 읽기·수정·저장 가능·오류·확인 필요·취소. 닫기와 취소는 저장을 의미하지 않음 |
| 모달·시트 | 제목/현재대상·본문·유일한 주요 행동·취소·외부 전송/삭제 요약. 긴 내용은 본문 스크롤, 행동은 고정 |
| 상태 배지 | 키 저장/연결 미확인·연결 성공/실패·모델 파일 있음/메모리 준비·입력 확인/확인불가/보류를 구분 |
| 알림 | 짧은 상태 요약+다음 행동. 녹음·처리 상태/종료/취소를 가리지 않음 |
| 진행 | 작업 이름·확인 가능한 진행만 표시. 처리시간을 거짓 카운트다운으로 만들지 않음 |
| HUD | 비활성 창, 녹음·처리·경고·카운트다운·미리보기·완료. 외부 입력 포커스 보존 |
| 메뉴바 | 기본·녹음·처리·권한/복구 필요·일시적 결과. 메뉴 정렬·기존 shortcut/종료 차단 계약 유지 |

### 설명을 `?`에 넣는 기준

**도움말로 이동:** 일반 기능 설명, 적용 범위, 예외, 예시, 내부 처리 순서, 한도와 학습 상세, 제공자별 지원 배경.

**기본 화면에 남김:** 현재값, 지금 미적용인 이유, 준비되지 않은 키·모델·권한, 현재 오류·보류·확인 불가, 켜진 기능의 추가 요청·비용 요약, 전송/삭제 직전의 대상·효과.

도움말을 읽게 하려고 제품 화면에 긴 “자세한 설명을 보려면…” 문구를 쓰지 않는다. 아이콘의 접근성 이름은 `녹음 마이크 도움말`처럼 항목을 포함한다. 도움말 표시가 외부 API 호출이나 설정 저장을 유발해서는 안 된다.

### SwiftUI 공통 요소 제안

구현은 이 문서 다음 작업이며 현재 앱 코드는 변경하지 않았다.

- `AppLayout` / `AppTypography` / `AppSpacing` / `AppColor`: 전역 토큰. 기존 `AppTheme`와 관계를 한 군데에서 정리.
- `ManagerShell`: 사이드바·툴바·scroll ownership. 목록 화면은 전체 페이지 ScrollView에 중첩하지 않음.
- `PageHeader`: 제목·주요 행동·선택적 도움말.
- `SettingsGroup` / `SettingsRow`: 같은 설정 페이지는 한 패널 안의 12/18 그룹 레이블과 얇은 구분선으로 묶는다. 레이블·help·currentValue·control·stateReason. 네이티브 `Grid`로 열 정렬, `ViewThatFits` 등으로 좁은 창 처리.
- `ActionButton` / `IconButton` / `StatusBadge`: 높이·크기·상태·접근성 공통.
- `MasterDetailPage` / `CompactListRow` / `DataTable` / `ResultInspector`: 기록·모델·복구 공통.
- `FormSheet` / `ConfirmationSheet` / `ComparisonSheet`: 입력·확인·비교 본문과 고정 footer.
- `InlineState` / `EmptyState` / `ProgressState`: 오류·빈 결과·진행의 같은 구조.
- 기존 `OptionHelp`의 Coordinator·포커스 복원·disabled 분리 계약을 유지하되 토큰과 본문 규격에 통합.

설정 데이터 모델·Keychain·추론·녹음·외부 입력 알고리즘은 공통 UI 컴포넌트 안으로 옮기지 않는다.

---

원본 문서: `primary-flow.md`

## 기본 작업 흐름과 부속 화면 재설계

2026-10-15 · OpenNoType 0.2.9 (45) · 기준 `d620ada3bf849f8ecae4948716089cedb08fa5a5`

담당 A `ux_primary_flow`. 이 문서는 [클릭 시안](index.html)의 홈·첫 사용·녹음·처리·결과·프롬프트·검토·편집·HUD·메뉴바를 설명한다. [primary-screens.js](primary-screens.js)의 고정 가상 문장으로만 상태를 표현한다. 앱 소스, 설치 앱, 설정, 기록, 키, 권한과 실제 입력 경로는 변경하지 않는다. 공통 규격은 [design-system.md](design-system.md)를 따른다.

### 현재 화면에서 확인한 문제

사용자가 제공한 `Screenshot 2026-10-15 at 7.49.40 AM.png`와 현재 소스를 함께 봤다. 스크린샷은 처음 사용하거나 연결 준비가 안 된 홈에서 큰 준비 점검 영역·세 개 작업 카드·프롬프트 카드가 이어지는 모습을 보여 준다. 아래 치수는 소스의 pt 값이며 스크린샷 픽셀을 환산한 측정값이 아니다.

| 관찰 | 실제 근거 | 재설계 방향 |
|---|---|---|
| 관리 셸과 큰 패널 여백이 누적된다 | `MainView.body`의 사이드바 212, 툴바 56, 본문 여백 30, 최대 폭 920 ([MainView.swift](../../../Sources/OpenNoType/Views/MainView.swift), 19–56행). `Surface`의 여백 22·간격 18·반경 14 (175–185행) | 셸 208/52/24, 패널 16/16/10으로 통일한다. 옵션은 행, 독립 결과는 패널로 구분한다. |
| 홈에서 제목·준비 설명·모드 설명이 작업 결과와 경쟁한다 | `HomeView.body`는 소개·프롬프트·최근 결과·검토·준비·모드·모델·보조 작업·복구를 연달아 구성한다. 소개 제목 30pt, 모드 카드 여백 17 ([MainView.swift](../../../Sources/OpenNoType/Views/MainView.swift), 214–235·303–319·610–620행) | 제목을 한 번만 표시한다. 현재 문제/작업 → 최근 결과 → 다음 받아쓰기 → 보조 작업 순서로 읽힌다. 모드 소개 세 카드를 한 작업 행으로 줄인다. |
| 준비가 안 되면 점검 목록 전체가 기본으로 펼쳐진다 | `readyForInput`은 권한·키·로컬/화자 준비를 함께 판정하고, `inputReadiness.onAppear`가 준비 전 목록을 펼친다 ([MainView.swift](../../../Sources/OpenNoType/Views/MainView.swift), 208–211·250–300행) | 준비 필요 항목과 해결 버튼만 먼저 보여 준다. 정상 항목의 자세한 내용은 `준비 상태 확인`에서 읽는다. 키 저장과 실제 연결 성공은 별도 상태로 유지한다. |
| 원문·초안·최종 후보·검토·원문 재처리가 한 결과 영역에 모인다 | `PromptCompositionResultView`는 복사 가능 결과, 보류, 원문/최종 후보/중간 초안, 검토, 원문 편집을 조건부 표시한다 ([PromptCompositionResultView.swift](../../../Sources/OpenNoType/Views/PromptCompositionResultView.swift), 5–154행) | 결과 읽기/복사를 기본으로 두고 원문·후보·검토는 펼침, 편집은 별도 표면으로 분리한다. 복사 가능 여부는 그대로 따른다. |
| 작은 HUD에서 경고가 정상 상태·시간을 대체한다 | `VoiceBar`는 450×80, 미리보기 때 높이 140인 비활성 패널이고, 일시 안내가 있으면 기본 상태와 시간을 대신 표시한다 ([VoiceBar.swift](../../../Sources/OpenNoType/Views/VoiceBar.swift), 9–23·39–85행) | 경고와 관계없이 단계·시간·끝내기·취소 위치를 고정한다. 경고와 미리보기는 보조 줄로 늘린다. 감지 알고리즘이나 포커스 정책은 바꾸지 않는다. |

### 크기와 간격

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

### 홈과 첫 사용

일반 홈에는 녹음 시작 버튼을 추가하지 않는다. 원하는 외부 앱 입력창에서 단축키로 시작하는 기존 동작과 입력 대상 보호를 유지한다. 홈에는 `준비됨/준비 필요`, 현재 처리 방식, 입력 단축키, 최근 결과가 보인다. `음성 이 Mac · 문장 AI 정리 · 자동 검토 꺼짐`처럼 실제 적용 경로를 한 줄로 요약하며 자세한 모델·전송 범위는 `?`에서 확인한다.

홈 순서는 **현재 작업/보류/실패 → 최신 결과 → 다음 받아쓰기 안내 → 보조 작업**이다. 과거 성공 결과보다 지금 보류된 결과가 위에 온다. 준비가 끝나지 않은 첫 사용에는 현재 부족한 연결/권한/모델과 그 항목을 여는 버튼을 먼저 보여 준다. 정상 항목과 전체 준비 근거는 펼침으로 제공한다. 빠른 로컬 받아쓰기에서는 AI 키를 필수 준비로 표시하지 않는다.

기록이 없는 홈은 `아직 결과가 없습니다`와 외부 입력 단축키만 안내한다. 입력 연습은 별도 화면에서 시험 문장과 단축키를 보여 준다. 실제 앱의 두 방식인 `단축키를 기다림`과 `5초 뒤 입력`을 보존하되, 클릭 시안에서는 실행하지 않는다. 시험 문장은 실제 글을 입력하는 작업이므로 실행 직전에 `녹음·API 호출 없음 / 시험 문장 입력`을 표시한다.

실제 준비 조건은 [HomeView.readyForInput](../../../Sources/OpenNoType/Views/MainView.swift) 208–211행, 시작 보호는 [AppModel.toggle](../../../Sources/OpenNoType/App/AppModel.swift) 955–1093행, 입력 연습은 같은 파일 1124–1188행에 연결된다. 준비 완료를 API 실제 연결 성공이나 외부 입력 성공으로 확장 해석하지 않는다.

### 실제 상태와 화면 상태를 구분하기

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

### 프롬프트 작업

홈의 `다른 작업 → 프롬프트 만들기`에서 복사용 녹음을 시작한다. 외부 앱에서 프롬프트 단축키를 쓸 때는 원래 입력창에 완성 결과를 입력하고 AI에는 자동 제출하지 않는다. 이 구분은 실행 요약에 짧게 남기며 자세한 목적·범위·예외는 `?`로 옮긴다. 기존 홈 문구의 `목표·맥락·제약·원하는 결과`, `코드나 직접 설계안을 만들지 않음`, 기존 지침 관련 차단은 도움말에 보존한다 ([MainView.swift](../../../Sources/OpenNoType/Views/MainView.swift), 336–373행).

`prompt-progress`는 실제 `drafting / reviewingDraft / polishing / reviewingFinal`만 사용한다. 다듬기는 필요한 경우에만 실행한다. 화면에는 생성·검토 단계와 취소, `생성 1~2회·검토 2회 / 추가 비용`을 표시한다. 완료되면 결과 복사를 우선하고 원문·중간 초안·최종 후보·검토를 펼침으로 제공한다. `참고 경고`와 `기존 지침 관련 차단`을 같은 위험 배지로 뭉개지 않는다.

차단·생성 실패·검토 실패·사용자 취소에서는 새 결과를 자동 입력하지 않는다. `canCopyOutput`이 허용한 결과만 완료 결과 복사 버튼을 제공한다. 차단된 후보는 최종 결과라고 부르지 않는다. 확인 가능한 원문/초안/후보의 기존 별도 표시와 복사 가능 범위는 유지한다 ([PromptCompositionPresentation.swift](../../../Sources/OpenNoType/App/PromptCompositionPresentation.swift), 43–45·67–78행; [PromptCompositionResultView.swift](../../../Sources/OpenNoType/Views/PromptCompositionResultView.swift), 51–99행).

원문 재작성은 `prompt-edit-source`로 분리한다. 편집할 원문·추가 비용·자동 입력 없음·실행/취소만 먼저 보인다. 기존 텍스트만 다시 보내고 음성을 재전송하지 않으며 원본 기록/실패 녹음을 덮어쓰지 않는다. 소스 식별자·크기/빈값 검사는 유지한다 ([AppModel.regeneratePrompt](../../../Sources/OpenNoType/App/AppModel.swift), 1958행; [PromptCompositionResultView.sourceEditor](../../../Sources/OpenNoType/Views/PromptCompositionResultView.swift), 121–154행).

### 검토·표기·편집

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

### HUD·메뉴바·도움말

HUD는 원래 앱의 포커스를 빼앗지 않는 `nonactivatingPanel`을 유지한다. 취소·현재 상태·시간·끝내기는 기본 줄에 고정한다. 준비 중은 녹음 전, 처리 중은 입력 전을 표시한다. 단축키 충돌 경고는 기본 상태를 대신하지 않고 추가 줄에 보인다. 실험 미리보기는 `확정 결과 아님`을 표시하고 두 줄까지만 제공한다. 모션 감소 설정을 보존한다 ([VoiceBar.swift](../../../Sources/OpenNoType/Views/VoiceBar.swift), 9–87행).

메뉴바는 상태, 네 작업의 현재 단축키, 작업 중 취소, 관리 창 열기, 사용량, 실패 녹음 수, 설정, 종료를 유지한다. 녹음 중 다른 모드 항목을 눌러도 기존 종료 동작을 유지한다. 관리 창 닫기는 앱 종료가 아니며 명시적으로 열 때만 활성화한다 ([StatusBarController.swift](../../../Sources/OpenNoType/App/StatusBarController.swift), 26–53·79–105·115–131행; [AppWindows.swift](../../../Sources/OpenNoType/App/AppWindows.swift), 49–55행). 시안의 메뉴는 상태 검토용이며 macOS 메뉴를 브라우저에서 구현한 것이 아니다.

일반 설명은 라벨 옆 `?` 하나로 읽는다. 제목·요약·현재값·활성 오류·보류 이유·추가 비용·전송 직전 요약은 화면에 남긴다. 원문·후보·표기 근거처럼 실제 내용을 읽는 펼침과 단순 사용법 도움말은 구분한다. 도움말은 한 번에 하나, 닫기·Escape 지원, 키보드로 닫을 때 진입 버튼으로 포커스 복원, 다른 컨트롤 클릭으로 닫을 때 새 컨트롤 포커스 유지가 원칙이다. 녹음 중 경고를 `?` 안에 숨기지 않는다. HTML 도움말은 실제 macOS 포커스/접근성 동작을 검증한 결과가 아니다.

### 모든 상태와 부속 표면 누락 대조

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

### 좁은 창·긴 영어·접근성 계약

960×680에서 제목/상태/주행동/최근 결과가 먼저 읽히게 한다. 원문/결과 두 열은 본문 폭이 부족하면 위아래로 전환하고 비교 순서는 원문 → 결과를 유지한다. 작업 행 버튼은 줄바꿈하되 단축키 한 덩어리와 짧은 상태 배지는 쪼개지 않는다. 긴 앱 이름·모델명·영어 옵션은 최소 폭을 강제하지 않고 줄바꿈한다. `API v2.3.1`, 날짜, 코드 경로 등 결과 본문은 임의로 수정하거나 줄임표로 숨기지 않으며 긴 토큰에만 시각적 줄바꿈을 허용한다.

키보드 순서는 제목 다음 주행동, 결과, 보조 행동, 도움말/펼침 순서다. 도움말 버튼의 접근성 이름은 해당 항목명+도움말이다. HUD의 `×/■`도 각각 취소/녹음 끝내기 이름을 제공한다. 색만으로 성공·주의·실패를 구분하지 않고 텍스트를 붙인다. 상태 변경 시 보조기기 공지는 실제 중요 전이만 알리고, 1초 경과 시간이나 미리보기 갱신을 계속 낭독하지 않는다. 포커스가 있는 편집기/펼침은 상태 갱신 때문에 사라지거나 상단으로 되돌아가지 않아야 한다.

### 기능 보존과 이식 검증표

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

---

원본 문서: `settings-architecture.md`

## 설정·음성 모델 전체 재설계 명세

작성일: 2026-10-15. 대상은 현재 체크아웃의 실제 앱이다. 이 문서는 설계와 브라우저 시안 명세이며 앱 구현 완료를 뜻하지 않는다. 앱 코드·설정·저장소 데이터·설치·배포는 변경하지 않았다. [시안 화면 코드](settings-screens.js), [공통 설계 시스템](design-system.md), [검토 안내](README.md)를 함께 본다.

### 이번 설계의 범위와 판단 근거

0.2.9는 긴 문단을 도움말로 옮겼지만, 공통 `Surface`가 22pt 패딩·18pt 내부 간격·14pt 모서리를 쓰고, 메인 콘텐츠에 다시 30pt 패딩을 준다. 설정 제목·분류 설명·카드 제목·옵션 도움말이 겹쳐 화면당 옵션이 적게 보인다. 예시 시트도 고정 760×610pt 안에 큰 여백과 설명을 반복한다. 이름만 줄이는 것으로 해결하지 않고 창·행·컨트롤·부속 화면의 치수를 함께 재정의한다.

실제 근거: [MainView.swift:21](../../../Sources/OpenNoType/Views/MainView.swift#L21), [MainView.swift:175](../../../Sources/OpenNoType/Views/MainView.swift#L175), [SettingsView.swift:47](../../../Sources/OpenNoType/Views/SettingsView.swift#L47), [DictationTranslationExamplesView.swift:78](../../../Sources/OpenNoType/Views/DictationTranslationExamplesView.swift#L78), [DictationExpressionExamplesView.swift:71](../../../Sources/OpenNoType/Views/DictationExpressionExamplesView.swift#L71). 사용자가 제공한 2026-10-15 07:48:59 스크린샷에서도 넓은 선택 메뉴와 카드 사이 간격을 확인했다.

설계 원칙은 옵션마다 `이름 + ? + 현재 값/컨트롤`을 같은 행에 두는 것이다. 일반 설명은 ?로 이동한다. 현재 작업을 막는 이유, 설정이 켜져 있으나 미적용인 이유, 추가 요청·비용·외부 전송은 짧게 기본 화면에 남긴다. 설명을 접는 것과 실패 계약을 숨기는 것을 구분한다.

### 치수와 밀도

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

### 목적별 설정 구조

| 목적지 | 기본 화면에서 보이는 그룹 | 상세·실험·진단 경로 |
|---|---|---|
| 받아쓰기 | 입력 방식 / 문장과 말투 / 번역과 검토 | 언어 예시, 표현 예시, 앱별 작성 방식, Jev 검토, 현재 로컬 모델 |
| 녹음·단축키 | 녹음 / 작업별 단축키 | 새 단축키 입력·충돌, 입력 진단 |
| AI 연결 | 음성 인식 / 문장 처리 / 검토와 비용 | 각 서비스 키·모델, 로컬 모델, Jev 연결, 사용량 |
| 개인정보 | 기록과 보관 / 전송과 문맥 / 학습과 통계 | 주변 문맥 허용 앱, 개인 사전의 교정 학습, 녹음 복구, 추가 전송 옵션 |
| 앱 관리 | 앱과 화면 / 업데이트 / 정보 | 로그인 항목 시스템 설정, 공개 릴리스, 업데이트 상태, 모델 라이선스 |
| 고급 도구 | **실험 기능** / **문제 해결** | 실험: 미리보기·화자·번역 다듬기·Jev 추가 도움·두 모델 비교. 문제 해결: 권한·입력 테스트·시간 진단·Jev 연결 테스트 |

같은 설정을 여러 화면에서 찾더라도 저장값·상세 목적지는 하나다. 예: 받아쓰기 처리의 모델 준비 링크와 AI 연결의 로컬 모델 링크는 같은 모델 상세로 이동한다. 번역 다듬기는 받아쓰기와 고급 도구에 진입점이 있지만 동일한 `translationRefinementEnabled`를 사용한다. 주변 문맥과 앱별 작성 방식은 별개로 유지한다.

### 전체 옵션·행동의 새 위치 매핑

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

### 유지해야 하는 실패·적용 계약

| 모드 | 기본 행의 짧은 상태 | 기존 입력 계약 |
|---|---|---|
| off | 선택값만 표시 | 자동 Jev 요청 없음. 수동 검토·연결 시험은 별도 |
| observe | 입력 후 검토 · 입력한 글 유지 | 이미 입력한 글을 바꾸지 않음. 음성 재인식 ON이면 입력 전 대기가 생길 수 있음 |
| protect | 위험 신호 시 보류 · 검토 실패 시 기존 결과 입력 | 의미 변경 등 강한 신호에는 보류. 일반 검토 실패·시간 초과에는 기존 결과 입력. 항상 안전하게 검증됐다는 보장 아님 |
| repair | 검토·교정 실패 또는 미해결 시 입력 보류 | 최대 한 번 교정하고 재검토. 검토를 완료한 결과만 입력 |

번역 보호는 일반 protect와 실패 정책이 다르다. `translationProtectionEnabled && decisionReviewMode == .protect`일 때 번역을 검토하며 실패·미확인에도 입력을 보류하고 자동 번역 교정은 하지 않는다. 번역 다듬기는 독립적인 추가 문장 요청이며 다듬기 실패에도 초안을 대신 자동 입력하지 않는다. 두 옵션 ON이면 다듬은 결과를 검토한다. 이 차이는 ?에서 풀어 설명하되 ON인 행에는 `추가 요청 · 실패 시 보류`를 남긴다.

`usesFastDictation`은 저장값이 fast인 것만으로 성립하지 않는다. **fast 저장 + 받아쓰기 출력 언어 original**이어야 유효하다([Preferences:300](../../../Sources/OpenNoType/App/Preferences.swift#L300)). 번역으로 바꿔도 fast·표현·Jev 저장값을 초기화하지 않는다. 다시 원래 언어로 돌아왔을 때 기존 선택을 그대로 사용한다. 표현 강도 0은 기존 AI 정리이며 fast로 변경하는 동작이 아니다.

### 기본 노출과 도움말의 경계

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

### 기본값·호환성 보존

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

### 부속 화면과 상태 표본

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

### 컴포넌트 호출 소유권과 후속 SwiftUI 적용 순서

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

---

원본 문서: `data-workflows.md`

## 기록·사전·복구·사용량·비교실 재설계

작성일: 2026-10-15. 범위는 현재 체크아웃을 읽고 만든 설계와 합성 데이터 HTML 시안이다. 앱 코드·설정·권한·실제 기록·API 키·설치 상태는 변경하지 않는다. 시안의 버튼은 화면 이동 또는 시안 안내만 수행하며 파일·마이크·API·클립보드에 접근하지 않는다.

### 재설계의 중심

기록은 **목록에서 찾고 한 항목의 상세만 확인**한다. 개인 사전은 **등록된 단어 목록이 먼저** 보이고 추가·수정은 작은 별도 폼에서 한다. 학습과 이름 후보는 사전 안의 탭으로 옮긴다. 사용량은 비용·요청·토큰을 동일한 크기의 요약으로 보고 상세를 펼친다. 두 비교실은 준비·진행·결과를 구분한다.

페이지 제목 아래 설명 문단은 모두 제목 옆 `?`로 옮겼다. 상한·동작 원리·학습 범위·보관 원칙은 해당 제목 또는 옵션의 도움말로 제공한다. 다음 내용은 기본 화면에 짧게 남긴다.

- 현재 꺼짐·처리 중·오류·보류·미확인·만료 상태
- 필수 원문 누락과 입력 길이 등 지금 행동을 막는 조건
- 전송 직전의 대상·내용·추가 비용과 삭제 직전의 정확한 범위
- 결과를 확정하지 못한 초안, 복사 불가, 보관되지 않는 미리보기

도움말 자체를 상태 표시의 대체물로 쓰지 않는다. 일반 설명을 다시 큰 안내 카드로 만들지 않는다.

### 현재 문제와 치수 변경

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

### 기존 요소의 새 위치

#### 기록과 재처리

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

#### 개인 사전과 후보

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

#### 녹음 복구

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

#### 사용량과 진단

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

#### 두 모델 비교실

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

### 시안의 상태 범위

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

### 좁은 창·키보드·접근성 계약

- 기본 콘텐츠는 공통 4/8/12/16/24/32pt 간격, 헤더52pt·사이드바208pt·최대1184pt를 따른다. 960px 창에서도 검색·개수·더보기를 한 줄에 억지로 고정하지 않는다. 매우 좁으면 목록/상세와 입력 두 열을 한 열로 쌓는다. 네이티브 최소900×640 정책 변경은 별도 판단이다.
- 기록 목록은 요약만 두 줄로 제한하고 상세 전문은 잘라 숨기지 않는다. 한영 혼용·긴 개발 식별자·URL·100자 사전 표기도 줄바꿈·선택·복사가 가능해야 한다. 다중 열 표의 긴 내용은 행 높이를 늘리고 가로 오버플로를 창 전체로 전파하지 않는다.
- 목록은 선택된 행을 색 외에 접근성 선택 상태로 알린다. 네이티브 구현에서는 `List`의 방향키·선택 동작을 유지하고, `Tab`은 검색→목록→상세의 실제 작업 순서로 이동한다. 검색을 지우거나 sheet를 닫으면 원래 제어로 포커스를 돌린다.
- `?`는 28~32pt 버튼, `옵션명 도움말` 접근성 이름, 눈에 보이는 포커스, 클릭/키보드로 열기, Escape 닫기·포커스 복귀, 화면 경계 제한을 공통 계약으로 사용한다. hover는 보조로만 쓴다. 동시에 하나만 연다.
- 상태 변경은 텍스트와 짧은 상태 배지로 표현한다. 녹음/처리 중 알림은 과도하게 매 프레임 읽지 않는다. 오류는 원인을 선택해 복사할 수 있게 하고 취소·실패·만료를 같은 ‘완료’ 문구로 합치지 않는다.
- 잠긴 control의 이유와 도움말은 읽을 수 있어야 한다. 실제 수정/저장/전송/삭제 gate는 preview·설정 복구 필요·busy·상한·검증 상태에 따라 보존한다. 도움말을 읽게 하려고 부모 전체 disabled를 해제한 뒤 쓰기 action을 열어 두지 않는다.
- 이 문서는 색상 대비나 VoiceOver 실측 통과를 주장하지 않는다. 기본/다크·키보드·긴 문구/좁은 창의 실제 네이티브 검증은 구현 단계에 필요하다.

### 검증과 인계

본 담당이 완료한 정적 검사: JavaScript 구문, 중복 화면 ID 없음, 제목 아래 설명 문단 없음, 모든 `data-help` 버튼에 접근성 이름 존재. 받아쓰기 기록의 검토 연결은 `data-review-source/result/origin` 합성 속성을 A가 읽는 로컬 시안 계약이다. 외부 화면 연결은 A/B 소유 `home-ready`, `review-confirm`, `candidate-review-confirm`, `models`, `settings-privacy`이다. 공통 CSS·라우팅·실제 브라우저 크기 및 포커스 검증은 메인 담당이다.

구현 순서는 데이터 저장·처리 모델을 유지한 채 ① 사전 목록 우선/등록 sheet ② 기록 목록·상세 분할 ③ 사용량 및 비교실 밀도 통일이 적절하다. 다른 AI의 기능 변경이 진행 중이므로 기능 reducer/저장 코드를 동시에 바꾸지 않고 기존 View에서 상태와 action을 그대로 새 배치에 연결한다. 각 단계의 검토 기준은 ‘기능 수’가 아니라 기본 화면에서 먼저 찾는 요소, 필수 상태의 가시성, 기존 승인·보관·취소 계약 보존이다.

---

원본 문서: `source-coverage.md`

## 전체 화면·소스 대조표

기준 커밋 `d620ada3bf849f8ecae4948716089cedb08fa5a5`. 현재 주요 UI View와 부속 표현을 소스에서 추출해 새 설계에 대응시켰다. 이 표의 “매핑”은 설계 대상 포함을 뜻하며 실제 SwiftUI 구현 완료가 아니다.

### View 전체 매핑

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

### View 외 UI 계약과 부속 표면

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

### 확인·동의·편집 대상

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

### 상태 누락을 막는 검토

- 주요 페이지의 기본/빈 값/검색 결과 없음과 첫 사용/준비/작업/보류/오류/확인 불가를 구분한다.

- 모델 준비·다운로드·파일 삭제·메모리 해제는 서로 다른 작업이며 다운로드 중간 상태·중단·재개·저장 모델 탐색은 설정 문서의 행별 목록으로 확인한다.

- 원음·문장·통계·비교 결과의 저장 수명과 전송 여부를 같은 “기록” 레이블로 합치지 않는다.

- 한영 긴 문구·다크·작은 창·키보드·도움말의 실제 검증은 verification.md에 적은 범위만 증거로 취급한다.

기본 화면·부속 상태 전체 목록은 [screen-catalog.json](screen-catalog.json), 분야별 세부 기능 매핑은 [A](primary-flow.md) / [B](settings-architecture.md) / [C](data-workflows.md) 문서를 참조한다.

---

원본 문서: `implementation-plan.md`

## 전체 적용·인수인계 계획

### 현재 상태

이 문서는 **전체 재디자인 설계**의 구현 인수인계다. 현재 설치 앱은 0.2.9이며, 이 설계를 SwiftUI에 적용하거나 새 버전으로 배포한 상태가 아니다. 현재 작업에서는 `design/uiux/2026-10-15-redesign-v2/`만 작성한다. 다음 작업자는 이 차이를 사용자에게 분명히 알리고 현재 checkout을 다시 확인한다.

핵심 기준은 [README](README.md), [공통 규격](design-system.md), [클릭 시안](index.html), [소스 대조](source-coverage.md), [검증 기록](verification.md)이다. 이전 `2026-10-15/` 시안의 부분 적용 계획을 이번 전체 완료 기준으로 사용하지 않는다.

### 기존 기능 보존 계약

- `AppModel`·`Preferences`의 기능 정책, 저장 키, 기본값, API·Keychain·암호화 기록·모델 경로를 디자인 때문에 바꾸지 않는다.
- 파일/메모리 준비, 키 저장/연결 확인, 입력 제출/실제 확인, 일반 결과/보류 결과를 한 상태로 단순화하지 않는다.
- 홈에 일반 받아쓰기 녹음 버튼을 새로 만들어 외부 입력 대상 보호를 우회하지 않는다. 프롬프트의 복사용 홈 녹음은 원래 의미를 유지한다.
- 빠른 로컬, 정리해서 입력, 번역, 선택 수정, 프롬프트에 적용되는 서로 다른 설정 범위를 유지한다. 비활성 컨트롤을 숨겨 저장값을 바꾸지 않는다.
- Jev 일반 protect/repair, 번역 검토, 번역 다듬기의 서로 다른 실패·보류 계약을 유지한다.
- 긴 설명은 도움말로 이동하지만 활성 비용·전송 대상·입력 보류 이유·삭제 확인은 없애지 않는다.
- 복구 녹음과 문장 기록을 같은 정책으로 합치지 않는다. 24시간 원음 만료, 당시/현재 설정 구분, 재처리의 자동 입력 금지를 유지한다.
- 사전 자동 학습과 사용자가 확인해야 하는 후보를 구분한다. 사전 JSON 가져오기 미리보기·확인, 이름 후보의 수동 등록, 학습 되돌리기를 보존한다.
- 메뉴바·비활성 HUD·외부 앱 포커스·녹음 중 종료 차단·단축키·딥링크·설정 복구 경로를 유지한다.

### 구현의 순서와 완료 조건

순서는 의존성을 위한 것이며 일부 화면만 구현하고 전체 개편 완료로 발표하기 위한 단계 구분이 아니다.

| 작업 묶음 | 실제 적용 범위 | 완료 증거 |
|---|---|---|
| 1. 공통 기반 | AppTheme 확장, 토큰, Shell, Header, Row, Panel, Button, Badge, Help, Sheet | 공통 요소 갤러리와 실제 네이티브 값·색·focus 대조 |
| 2. 전체 탐색 | 현재 7 AppPage의 진입 보존, 복구를 기록 하위로, 설정 목적 6개 정리, 메뉴바·메뉴 명령·설정 바로가기 매핑 | 모든 기존 진입점에서 동일 기능 도달, 검색·선택·scroll 보존 |
| 3. 모든 주요 화면 | 받아쓰기, 기록, 사전, 복구, 사용량, 음성 모델, 모든 설정 | 같은 창 크기의 Before/After 1장씩, 커버리지 표의 모든 행 완료 |
| 4. 모든 부속 표면 | 예시·등록·편집·검토·재인식·비교·전송·삭제 확인·HUD·메뉴바 | 시트/팝오버/확인/메뉴 상태 행까지 누락 없음 |
| 5. 상태·유효성 | 첫 사용·준비·녹음·처리·보류·확인불가·실패·빈 검색·복구·권한·다운로드 | 상태를 강제로 표현하는 격리 preview와 실제 필요한 경로 확인 |
| 6. 전체 검증 | 라이트·다크, 기본·최소·큰 창, 긴 한국어·영어·모델명, 키보드·VoiceOver | 아래 인수 기준과 테스트·빌드·실앱 증거를 구분한 보고 |

### 4명 병렬 구현 시 파일 소유권

다음 구현도 메인 포함 최소 4개 에이전트 병렬을 유지한다. 파일 경계가 겹치는 `MainView.swift`와 `DataViews.swift`는 먼저 분리하거나 메인만 통합 편집한다.

| 담당 | 독립 구현 | 공통 파일 통합 원칙 |
|---|---|---|
| 메인 | 토큰/공통 컴포넌트/앱 셸/탐색/통합/검증 | `MainView` 셸, `AppPage`, `SettingsSection`, 전체 scroll 계약 소유 |
| A | 분리한 HomeView, 결과·프롬프트·검토·편집·HUD·메뉴바 View | MainView 안 HomeView를 별도 파일로 옮기는 첫 추출은 메인과 순차 수행 |
| B | 설정 6분류, 언어·표현·녹음·업데이트, 모델·화자·연결·권한·예시 | SettingsView와 공통 컴포넌트 API는 고정한 뒤 병렬 적용 |
| C | 기록/사전/복구/사용량/음성·문장 테스트실 | DataViews를 목적별 View로 추출한 뒤 C가 소유 |

작업 시작 시 git status·현재 SHA·다른 작업자의 변경 경계를 확인한다. 원본 변경을 백업하고 `source-baseline.json`과 비교하되 옛 파일로 덮어쓰지 않는다. UI와 기능이 한 파일에 섞였으면 바인딩·action을 지키는 구조 추출을 먼저 검토한다.

### 탐색 변경의 호환성

외부 API나 저장 식별자를 UI 이름에 맞춰 바꾸지 않는다. 기존 `.home`, `.history`, `.dictionary`, `.recovery`, `.usage`, `.voice`, `.settings`는 새 목적지로 라우팅할 수 있다. `.recovery` 진입은 새 기록 화면의 ‘녹음 복구’ 탭을 선택하고, 이전 설정 `.connection/.input/.privacy/.general`은 현재 관련 하위 분류로 매핑한다. 네비게이션 임시 상태를 사용자 설정 저장 데이터와 섞지 않는다.

모델 비교와 Jev 추가 기능을 고급 영역으로 옮겨도 기존 버튼의 전송 확인·비용 예산·결과 수명과 추천 적용 버튼은 유지한다. 명칭 변경만으로 새 기능으로 세지 않는다.

### 인수 기준

- [ ] 각 주요 화면의 제목·여백·그룹·행·값 열·버튼·입력창이 공통 토큰에서 나온다. `.padding(22)` 등의 옛 값이 임의로 남은 View가 없는지 예외 목록으로 확인한다.
- [ ] 기본 화면에 긴 일반 설명이 없다. 현재값·상태·행동과 짧은 조건만 남고 자세한 내용은 항목 옆 `?`에서 읽는다.
- [ ] 사전은 검색·목록·추가가 첫 화면에, 기록은 목록·선택 상세가 첫 화면에 들어온다. 큰 설명 카드가 목록보다 앞서지 않는다.
- [ ] 관련 설정이 한 그룹의 정렬된 행에 모여 있고 선택창이 빈 공간 전체로 늘어나지 않는다.
- [ ] 960×680 / 1120×760 / 1440×900, 라이트·다크에서 주요 행동과 값이 잘리지 않는다. 100%와 사용자 글자 확대 조건을 구분해 확인한다.
- [ ] 긴 한국어/영어 이름·고유명사·URL·날짜·버전·숫자 줄바꿈이 읽히고 결과 복사 내용이 바뀌지 않는다.
- [ ] 모든 `?`는 disabled 값에서도 열림, 키보드 Enter·Space·Escape, 단일 팝오버·포커스 복원이 된다.
- [ ] Tab 순서가 시각 순서와 맞고, VO가 옵션명·현재값·상태·도움말을 읽는다. 색상만으로 상태를 전달하지 않는다.
- [ ] 검색·선택·상세·뒤로·시트 닫기·취소에서 기존 작업과 데이터가 보존된다. 처리 중 작업이 레이아웃 변화 때문에 취소되지 않는다.
- [ ] 목록형 페이지는 MainView의 전체 ScrollView 안에 중첩된 독립 스크롤 두 개를 무심코 만들지 않는다.
- [ ] 실제 API 전송·파일 삭제·설정 복구·모델 변경은 기존 확인과 권한을 유지한다.
- [ ] 외부 앱 입력 포커스·비활성 HUD·메뉴바만 시작·창 다시 열기·잠자기 복구를 UI 검증과 분리해 확인한다.
- [ ] source-coverage.md의 전체 View·부속 표면·상태를 대조한다. 일부 화면 검증만으로 전체 완료를 선언하지 않는다.

### 검증과 설치의 구분

HTML 렌더링은 시안 검증이다. SwiftUI 컴파일·단위 테스트는 실제 창 간격·키보드·VoiceOver·외부 입력 성공을 대신하지 않는다. 네이티브 isolated preview → 소스 테스트/빌드 → 실제 창 검증 → 필요한 외부 입력 테스트 → 데이터 보존 설치 → 사용자 승인 범위의 커밋·배포 순서로 각각 증거를 남긴다.

이번 사용자 요청은 전체 재디자인 **설계**이며, 이전 배포 요청을 근거로 새 설계안을 자동으로 버전업·설치·공개하지 않는다. 설계 파일을 다른 채팅에 전달하면 다음 작업자가 전체 범위와 기존 기능 계약을 그대로 이어받을 수 있다.

---

원본 문서: `verification.md`

## 전체 재디자인 시안 검증

검증일: 2026-10-15 KST. 현재 앱 0.2.9를 기준으로 한 **설계·HTML 시안 검증**이다. 실제 SwiftUI 적용·설치·공개 배포·실물 입력 검증이 아니다.

### 실제 병렬 작업과 교차 검토

메인과 A `ux_primary_flow`, B `ux_settings_architecture`, C `ux_visual_copy`를 동시에 실행했다. A→B, B→C, C→A로 서로의 담당 결과를 읽고 메인이 통합했다. 추가로 A가 메인 문서·소스 커버리지·키보드 전환을 독립 검토했다.

교차 검토에서 수정한 항목:

- 설정의 반복 분류·소개·정상 상태 요약을 없애고, 받아쓰기 기본 9행을 한 그룹 패널로 묶음.
- 강도 슬라이더와 숫자의 줄바꿈, 숫자 caption 때문에 행이 불필요하게 커지는 문제 수정.
- 화자 모델 준비·프로필 등록·삭제의 활성 조건, 모델 선택창의 한글 접근성 이름 수정.
- 교정 후보·이름 찾기의 전송/저장 확인을 일반 문장 검토와 분리.
- 기록·보류 결과의 수동 검토에서 선택한 합성 원문·결과·복귀 대상을 보존.
- 이름 후보 관리 진입을 단어 탭 대신 이름 후보 탭으로 연결.
- 본문 이동 뒤 새 제목에 포커스 이동, 도움말 닫기 후 원래 버튼 복원.
- 목록 버튼의 브라우저 기본 배경/테두리, flex 영역의 최소 높이, 동의 checkbox와 switch 크기 충돌 수정.

### 정적 대조

- **49개 View/NSViewRepresentable 선언 / 23개 파일**을 직접 추출해 새 설계에 매핑. A가 독립 재추출해 이름 누락 0개 확인.
- 실제 `.confirmationDialog` 선언 **16개**, View 외 메뉴바·창·HUD·시스템 패널 진입도 별도 표로 대조.
- 최종 시안 **106개 화면·상태**, 중복 ID 0개, `data-go`의 없는 목적지 0개.
- `primary-screens.js`, `settings-screens.js`, `data-screens.js`, `system-screens.js`, `prototype.js`의 Node 구문 검사 통과.
- MD 상대 링크와 HTML 자산 경로 확인. 현재 소스·Resources 116개 파일의 SHA-256은 [source-baseline.json](source-baseline.json)과 동일함을 마지막에 비교한다.

### 브라우저에서 실제 확인

`ego-browser`의 이번 작업 전용 TaskSpace 2, p1에서 로컬 파일을 열었다. 외부 웹 서비스 로그인·마이크·권한 요청·API 호출은 하지 않았다.

| 확인 | 실제 관측 |
|---|---|
| 106 화면 × 960/1120/1440 실제 창 폭 × 라이트·다크 | **636 렌더 조건**, 요청 폭과 실제 폭 일치. 가로 스크롤 넘침·컨트롤/패널의 좌우 경계 이탈 0개 |
| 도움말 | 전체 렌더에서 접근성 이름·enabled·최소 28×28 클릭 영역 확인, 문제 0개 |
| 기본 받아쓰기 | 1120×760에서 9행 모두 **44px**, viewport 높이와 content 높이 모두 **678px**, 세로 스크롤 없음 |
| switch | **32×20px**, 동의용 checkbox는 별도 16px 규격 |
| 도움말 열기·닫기 | 클릭으로 열고 Escape로 닫힘, 원래 `받아쓰기 처리 도움말` 버튼에 포커스 복원 |
| disabled 설정의 도움말 | 편집 강도 값이 disabled여도 Enter로 도움말 열림 |
| 본문 전환 포커스 | 기록 상세→검토 확인에서 새 H1에 포커스 이동 |
| 기록 선택·검색 | 다른 행 선택 시 해당 TypeScript 합성 결과 표시, 없는 검색어는 0개·빈 상태, 검색 제거 후 목록 복원 |
| 기록 검토 문맥 | 선택 PostgreSQL 기록의 원문·결과가 같은 검토 확인에 표시됨 |
| 보류 검토 문맥 | 표시된 원문·결과가 확인 화면에도 그대로 남고 취소로 원래 보류 화면 복귀 |
| 빠른 로컬 + 번역 | 저장된 fast 선택은 유지하고 번역의 AI 처리·현재 미적용 이유 표시 |
| 언어 예시 | 예시만 한국어로 바꿔도 저장된 출력 언어 en-US 유지. 직접 적용 전 설정 불변 |
| 텍스트 색 대비 | 라이트·다크의 지정 12쌍 계산, 최소 **5.14:1**. 전체 접근성 인증으로 확대하지 않음 |

기계 판독 증거: [렌더 조건](layout-audit.json), [대표 상호작용·치수](interaction-check.json), [텍스트 대비](contrast-check.json), [전체 화면 목록](screen-catalog.json).

이 수치는 HTML 디자인 시안의 관측이다. 스크린샷의 픽셀을 실제 macOS pt로 추정한 결과가 아니다. 네이티브 적용은 같은 수치를 pt 토큰으로 구현한 다음 별도로 확인해야 한다.

### 대표 화면을 눈으로 확인

[설정](settings-light.png), [개인 사전](dictionary-light.png), [기록](history-light.png), [받아쓰기](home-light.png)를 실제 브라우저에서 캡처해 여백·크기·설명 노출을 확인했다. [음성 모델](models-light.png), [다크](settings-dark.png), [도움말](help.png) 캡처도 포함한다. [한눈에 보기](gallery.html)는 네 대표 화면을 모은 검토용 페이지다.

### 확인하지 않은 범위

- 실제 SwiftUI View의 렌더링·시트 실제 크기·네이티브 키보드/VoiceOver 낭독·시스템 글자 확대.
- 실제 마이크 녹음·한영 정확도·API 연결·외부 앱 입력·HUD 비활성 포커스·Sparkle 업데이트.
- 각 시스템 NSOpenPanel/NSSavePanel/권한/Sparkle 창 자체의 재디자인. 시스템 표준 표면은 보존 대상이다.
- 모든 기록 모드의 실제 비동기 처리 시뮬레이션. 합성 받아쓰기의 선택·검토 맥락만 이어지고 나머지는 별도 고정 상태 또는 시안 안내다.
- 비교실의 실측 시간·비용·정확도. 시안은 표의 구조만 보여 주고 성능 점수를 만들어 내지 않는다.

현재 앱 코드·설정·키·기록·모델·설치·배포는 변경하지 않았다. 다음 구현의 전체 완료 기준은 [implementation-plan.md](implementation-plan.md)이다.

