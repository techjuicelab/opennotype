# Prompt Test 추가 위험 점검 — 2026-10-09

기준 소스는 `a45f9fbf4684b7789e703533a82cc8720a8a8bde`이다. 생성·검토, 입력·취소, 저장·복구, 독립 반증을 네 전문 에이전트가 분담하고 통합 담당이 패키징·버전·앱 식별 경계를 점검했다. 실행 슬롯은 통합 담당을 포함해 최대 네 개를 병렬로 사용했다. 실제 사용자 데이터·키·마이크·대상 앱에는 쓰지 않았다.

## 발견과 수정

| 우선순위 | 재현한 조건과 영향 | 대응 |
| --- | --- | --- |
| P1 · 원음 손실 | 일반 받아쓰기·번역·문장 수정의 실패 녹음을 재처리한 뒤 기록 저장이 한 번 실패한다. 오류 안내 뒤에도 복구 항목과 원음이 삭제된다. 프롬프트 모드는 이 조건에서 원음을 보존했다. | 요청된 기록 저장이 실패하면 복구 원음을 유지한다. 기록 보관을 끈 정상 완료는 기존처럼 복구 항목을 정리한다. |
| P1 · 이전 보관 정책 재적용 | 기록 재처리를 시작할 때 1일 보관이었다가, 응답 대기 중 계속 보관으로 바꾸고 저장소에 적용한다. 만료 경계 뒤 도착한 응답이 이전 1일 정책을 되적용해 기록을 삭제한다. | 기록 재처리의 확인은 저장소에 적용된 현재 정책으로 정상 만료를 처리하며 정책을 다시 설정하지 않는다. 보관 설정이 그대로인 경우의 만료 삭제는 유지한다. |
| P2 · 상충 판정 형식 | 모의 HTTP 응답의 같은 객체에 `harnessBoundary` 이름을 pass/fail로 중복 제공한다. Foundation이 하나를 버린 뒤 유효 판정처럼 검증되어 실제 Runner가 ready를 반환했다. | 원시 응답에서 객체별 중복 이름을 거절한다. 문자열·escape와 서로 다른 객체를 구분하며 기존 내용 검토 기준은 바꾸지 않는다. |

두 데이터 손실은 실제 `AppModel`·`SecureStore` caller와 임시 암호화 저장소에서 재현했고 독립 검토자가 red 바이너리를 다시 실행해 확인했다. 이것이 사용자가 과거 겪은 프롬프트 전체 소실과 같은 원인이라는 증거는 없다. 원음 저장 실패 재현에서 프롬프트 분기는 보존 대조군으로 통과했다.

중복 판정은 OpenRouter·TypeSafe를 모의한 URLProtocol과 실제 `DecisionClient`·Runner를 사용했다. 정상 제공자가 실제로 이런 응답을 반환했거나 지침 우회가 실행됐다는 증거는 없다.

## 검증 근거

수정 전 재현과 통과한 기존 경계는 `build/prompt-risk-audit-2026-10-09/`에 보존한다. 이 디렉터리는 Git에 포함하지 않는다.

- `storage/red/platform-tests.log`: 6개 메서드·115 assertion 중 7개 실패. 세 일반 모드의 원음/복구 항목 손실 6개와 보관 정책 복원에 따른 기록 손실 1개이다. prompt 보존·변경 없는 정상 만료 대조군은 통과했다.
- `core/raw-json-checks.log`, `core/raw-json-repeat.log`: 3개 메서드·34 assertion 중 같은 5개 실패를 반복했다. 두 제공자·두 순서의 상충 응답 거절과 Runner ready 반환을 확인한다.
- `core/stored-checks.log`: 기준 소스의 관련 기존 167개 메서드·6,390 assertion 통과.
- `input/report.md`: 기준 소스의 실제 입력·취소 caller 56개 메서드·908 assertion, 가상 클립보드·제출 경계 10개 메서드·159 assertion 통과.
- 패키징 기존 Python 시험 11개 통과. 설치된 `0.2.5 (41)`은 기준 커밋·SourceDirty=false·별도 ID·업데이트 주소/키 없음·엄격 서명 통과를 읽기 전용으로 확인했다. 일반 앱은 기존 실행 파일 SHA와 같다.

### 수정 후 회귀

- 저장·복구: tracked 회귀를 제품 수정 전에 실행해 7개 메서드·139 assertion 중 7개 실패를 확인했다. 수정 뒤 기존 두 플랫폼 테스트 파일 전체 48개 메서드·994 assertion이 통과했다. 저장·마이그레이션 관련 61개 메서드·376 assertion도 통과했다.
- 검토 응답: tracked 실제 HTTP 회귀를 제품 수정 전 실행해 14개 assertion 실패를 확인했다. 수정 뒤 관련 기존 회귀와 새 8개 메서드, 총 175개 메서드·6,590 assertion이 통과했다. 객체별 중복·escape 동등 이름·한글/이모지·정상 pass/fail·인용 본문·사용량·취소·HTTP 오류·기존 Foundation 인코딩 호환을 확인했다. UTF32LE+BOM을 기존 Foundation도 지원한다고 가정한 시험 전제 한 건은 선행 파싱 결과와 대조해 정정했으며, 정상 입력을 추가 거절하는 제품 결함으로 분류하지 않는다.
- 독립 반증: 수정 전 두 데이터 손실과 상충 판정을 직접 반복했다. 수정 뒤 플랫폼 바이너리를 다시 실행했으며, 두 SecureStore actor의 공유 vault 정책·원음의 24시간 만료·유한 보관·0일 보관의 별도 검사도 통과했다. 최종 Core 바이너리도 다시 실행해 통과했고, Foundation이 문법을 허용한 독립 JSON 819개 사례에서 scanner 반례가 없었다.
- 최종 로컬 Python: 하네스 소스 등록까지 반영한 뒤 Sparkle 실도구 경로를 지정하여 전체 209개를 다시 실행했다. 208개 통과·1개 skip·실패 0이다(`python-final-tests.log`). 남은 skip은 CLT 선택 환경에서 full Xcode가 필요한 XCTest 컴파일 검사다.

위 Swift 수치는 실제 제품 소스와 저장된 테스트를 직접 컴파일한 로컬 하네스 결과이며, 정식 XCTest 실행이나 실제 마이크 통합 시험과 구분한다. 최종 커밋의 정식 XCTest·일반 앱 및 테스트 앱 패키징은 [PR #28의 Checks](https://github.com/techjuicelab/opennotype/pull/28/checks)에서 확인하며, 서로 다른 소스 커밋의 통과 결과를 합쳐 일반적인 의미 품질 증거로 쓰지 않는다.

### 통합 CI에서 찾은 하네스 등록 누락

첫 통합 커밋 `3f6c0ac`의 정식 XCTest는 두 실행 모두 총 1,110개 중 1,108개 실행·선택적 음성 검사 2개 skip·실패 0이었다. 그러나 Python의 실제 Core 컴파일 검사는 새 `JSONDuplicateObjectNames.swift`를 찾지 못해 실패했고, 뒤의 앱 빌드·아티팩트 업로드는 실행되지 않았다. 이 실패를 앱 패키징 성공으로 간주하지 않는다.

같은 `ExpressionProductionHarnessTests`를 로컬에서 실행해 컴파일 오류를 재현한 뒤 `scripts/compare-decisions.py`의 공통 `SOURCES` 목록에 helper를 등록했다. `compare-text-models.py`도 이 목록을 상속하므로 양쪽 비교 하네스와 소스 SHA 추적에 함께 반영된다. 제품 소스·의미 정책·테스트 앱 버전은 이 통합 보완에서 변경하지 않는다. 실패 로그는 `compare-harness-red.log`와 `ci-final/failed-3f6c0ac/`에 보존한다. 독립 검토에서 양쪽 도구의 컴파일 인수와 소스 SHA 추적에 helper가 정확히 한 번 들어가고, 다른 명시적 `DecisionClient.swift` 컴파일 목록의 누락이 없음을 확인했다.

구현과 회귀: [AppModel](../../../Sources/OpenNoType/App/AppModel.swift), [SecureStore](../../../Sources/OpenNoTypeCore/Storage/SecureStore.swift), [DecisionClient](../../../Sources/OpenNoTypeCore/AI/DecisionClient.swift), [원시 JSON 이름 검사](../../../Sources/OpenNoTypeCore/AI/JSONDuplicateObjectNames.swift), [복구 흐름 회귀](../../../Tests/OpenNoTypePlatformTests/PromptCompositionFlowTests.swift), [보관 정책 회귀](../../../Tests/OpenNoTypePlatformTests/HistoryReprocessingTests.swift), [검토 응답 회귀](../../../Tests/OpenNoTypeCoreTests/PromptCompositionReviewTests.swift).

## 남은 위험과 검증 한계

- 생성문에서 모호한 “문구”를 “요청 문구”로 좁히거나 음성 언급 조건을 일반 입력 조건으로 넓히는 문제는 이미 확인한 의미 품질 후속 항목이다. [기존 대비 시험 계획](../../prompt-test-changelog.md#추가-개선-우선순위)을 유지한다. 문장 ID·수치·CI 통과가 의미 보존을 증명하지 않는다.
- 물리 마이크로 말한 내용부터 실제 편집기에 정확히 한 번 입력되고 기록에 남는 통합 시험은 이번 점검에서 실행하지 않았다. AX 요소를 제공하지 않는 앱은 기존 정책에 따라 앱 수준 확인만 가능하다.
- 빌드 스크립트는 checkout 내 고정 staging 경로를 공유하며 동시 빌드 잠금이 없다. 같은 checkout에서 동시에 빌드하면 간섭할 여지가 있지만 이번 사용자 프롬프트 처리 문제로 재현된 결함은 아니다. CI와 이번 검증은 순차 빌드한다. 빌드 시점 HEAD/dirty 메타데이터는 빌드 내내 파일이 불변이었다는 byte 단위 증명은 아니다.
- 이번 보관 수정은 이미 저장소에 적용된 새 정책을 늦은 재처리가 덮어쓰는 경계를 해결한다. 설정 저장 자체가 실패했거나 아직 적용 중인 순간까지 보장하는 의미는 아니다.

수정 소스는 테스트 버전 `0.2.6 (42)`로 관리한다. 일반 앱 버전·공개 태그·릴리스·설치 앱 교체는 이 점검에 포함하지 않는다.
