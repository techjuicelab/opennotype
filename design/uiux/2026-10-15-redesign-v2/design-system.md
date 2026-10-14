# 공통 크기·간격·컴포넌트 규격

## 설계 방향

키보드로 빠르게 사용하는 macOS 음성 입력 도구다. 웹 서비스의 큰 소개 영역 대신 **조용한 도구 창, 정렬된 값 열, 결과 중심 작업 공간**을 사용한다. 현재 브랜드의 녹색과 마이크의 주황색을 유지하되 색은 선택·진행·문제 상태를 구분하는 데 쓴다. 장식 카드·큰 제목·불필요한 설명을 반복하지 않는다.

서체는 macOS 시스템 서체(SF / Apple SD Gothic Neo)를 유지한다. 이름·문장 보존이 중요한 제품이므로 긴 고유명사와 숫자를 과도한 자간·전용 장식 서체로 흐리지 않는다. 숫자·버전·시간·단축키는 시스템 고정폭 서체를 쓴다.

## 실제 기존 소스 근거

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

## 토큰

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

### 색상

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

## 화면 구조와 줄바꿈

- 툴바에는 짧은 현재 위치와 연결 설정 진입만 둔다. 페이지 제목은 본문에 한 번, 일반 소개 문구는 필요할 때 `?`로 제공한다. 본문 위의 중복 분류·소개 레이블(eyebrow)은 표시하지 않는다.
- 좌측 메뉴는 받아쓰기 / 기록 / 개인 사전 / 음성 모델 / 사용량 / 설정. 복구는 기록 안의 별도 탭으로 옮기되 실패 원음의 별도 수명·권한을 유지한다. 실험실은 음성 모델·고급 설정에서 진입한다.
- 모든 화면은 같은 왼쪽·오른쪽 기준선과 제목 위치를 쓴다. 빈 화면도 현재 목적과 다음 행동을 같은 위치에 둔다.
- 설정 기본 행은 label + `?` + value/control. 부가 버튼도 값 영역 안에 두어 행마다 선택창 폭이 달라지지 않게 한다.
- 기본 최소 창 960에서 레이블을 1줄로 강제하거나 잘라내지 않는다. 행은 자동으로 높아지고, 필요한 경우 값 영역을 다음 줄에 둔다.
- 기록의 master/detail은 창 공간에 따라 280~320 + 나머지. 실제 앱 최소 폭에서 긴 결과가 읽히지 않으면 상세를 독립 뷰로 열고 뒤로 돌아가도 선택·검색·스크롤을 유지한다.
- 제목·설명은 축소(scaleEffect/minimumScaleFactor)하지 않는다. 긴 URL·개발 식별자는 결과 본문에서 줄바꿈하되 복사되는 원문은 그대로다.
- 1440 이상의 큰 창에서도 모든 레이블과 컨트롤을 바깥 끝으로 흩어 놓지 않는다. 페이지는 최대 1184이며 결과 본문은 65~80ch 정도의 읽기 폭을 권장한다.
- 브라우저의 760px 이하 대체 레이아웃은 검토 도구의 편의 기능이다. 이를 macOS 최소 창 지원 구현 완료로 주장하지 않는다.

## 모든 요소의 상태

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

## 설명을 `?`에 넣는 기준

**도움말로 이동:** 일반 기능 설명, 적용 범위, 예외, 예시, 내부 처리 순서, 한도와 학습 상세, 제공자별 지원 배경.

**기본 화면에 남김:** 현재값, 지금 미적용인 이유, 준비되지 않은 키·모델·권한, 현재 오류·보류·확인 불가, 켜진 기능의 추가 요청·비용 요약, 전송/삭제 직전의 대상·효과.

도움말을 읽게 하려고 제품 화면에 긴 “자세한 설명을 보려면…” 문구를 쓰지 않는다. 아이콘의 접근성 이름은 `녹음 마이크 도움말`처럼 항목을 포함한다. 도움말 표시가 외부 API 호출이나 설정 저장을 유발해서는 안 된다.

## SwiftUI 공통 요소 제안

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
