**OpenNoType 전반 재검토 · 2026-09-09**

현재 앱은 기능의 폭과 기본 보호 장치는 잘 갖췄습니다. 다음 개선의 중심은 **입력 대상의 일관성, 잘못된 자동 학습 방지, 실패 복구, 실제 사용 검증**이어야 합니다. 기능 추가보다 이 부분을 먼저 다듬는 편이 일상 사용의 신뢰도를 높입니다.

대상은 OpenNoType 저장소의 HEAD `12910c1`과 현재 미커밋 변경입니다. 별도 저장소인 notype의 구현이나 과거 검증 결과를 이 앱의 현재 상태로 간주하지 않았습니다. 메인 검토와 세 독립 검토를 병행하고, 주요 발견을 다시 코드·격리 실험으로 교차 확인했습니다. 앱 소스와 사용자 설정·개인 데이터는 수정하지 않았으며, 이 보고서와 합성 재현 자료만 추가했습니다.

**확인 범위와 결과**

| 확인 항목 | 이번 결과 | 해석 범위 |
| --- | --- | --- |
| 전체 테스트 | 161개 발견, 160개 통과, 모델 통합 테스트 1개 제외, 실패 0 | 실제 마이크·유료 API·외부 앱 입력 성공을 뜻하지 않음 |
| 앱 컴파일 | `swift build --product OpenNoType` 성공 | 서명·공증·업데이트 검증과 별개 |
| 실행 중인 UI | 시작하기·설정·음성 모델의 AX 상태, 시작하기·음성 모델 화면 확인 | 현재 실행된 개발 앱의 관찰이며 새 소스로 교체하거나 재시작하지 않음 |
| 삽입 지연 실험 | 지연 AX와 추가 paste가 겹쳐 결과가 두 번 들어가는 조건 재현 | 실제 대상 앱을 느리게 만든 E2E가 아닌 production 전달 로직의 시간 주입 실험 |
| 자동 학습 | 의미가 바뀐 단어를 영구 사전 후보로 만드는 사례 재현 | 실제 외부 앱 교정 감시는 실행하지 않음 |
| 저장소 | 합성 실패 원음 0·1·3개 성능, 오래된 배열 저장, 미완성 임시 파일 검사 | 실제 사용자 저장소·Keychain에 접근하지 않은 격리 실험 |
| 외부 계약 | OpenRouter 공식 STT 라우팅 설명 확인 | 라이브 모델 호출·과금은 미실행 |

환경: Apple M2 Max, 메모리 32 GiB, macOS 26.6.2, Swift 6.3.3. 단위 테스트 중 CoreData/XPC 진단이 출력되었지만 관련 assertion과 전체 suite는 통과했습니다. 로그는 [swift-test.log](/Users/techjuice/Documents/Dev/AI/opennotype/docs/reviews/2026-09-09/evidence/swift-test.log)에 보존했습니다.

여기서 **P1은 데이터 덮어쓰기·문맥 허용 경계 때문에 우선 수정할 항목**, **P2는 신뢰성과 실사용을 개선할 항목**입니다. “코드 경로 확인”, “격리 재현”, “실행 화면 관찰”을 서로 구분했습니다.

| 순서 | 우선순위 | 개선 항목 | 근거 수준 |
| --- | --- | --- | --- |
| 1 | P1 | 선택 문장 수정 직전에 원문·선택 영역 재검증 | 코드 경로 확인 |
| 2 | P1 | 포커스 element의 실제 앱 PID 검증 | 코드상의 조건부 경쟁 상태 |
| 3 | P2 | 지연 AX 결과에 자동 paste를 더하지 않기 | 격리 재현 |
| 4 | P2 | 자동 학습에서 의미 변경과 표기 교정 구분 | 격리 재현 |
| 5 | P2 | 실패 녹음을 변경한 모델·필터 설정으로 복구 | 코드 경로 확인 |
| 6 | P2 | 이미 받은 로컬 모델을 재실행 후 자동 준비 | 코드 및 준비 화면 확인 |
| 7 | P2 | 실패 원음과 텍스트 저장소 분리 | 합성 부하 측정 |
| 8 | P2 | 기록·사전 변경을 저장소 안에서 원자적으로 수행 | 오래된 배열 저장 시나리오 재현 |
| 9 | P2 | 시작 작업을 첫 await 전에 점유 | 코드상의 재진입 경로 |
| 10 | P2 | OpenRouter의 지원하지 않는 라우팅 보장 제거 | 공식 문서와 현재 코드 대조 |

**1. 선택 문장 수정은 대상이 바뀌었을 때 자동 입력을 멈춰야 합니다.**

문장 A를 선택하고 음성 수정 요청을 시작한 뒤, AI가 처리하는 동안 같은 편집기의 문장 B를 선택하는 경우입니다. AI에는 캡처한 A가 전달되지만, `AXSelectedText` 쓰기나 ⌘V는 실제 삽입 시점의 선택 영역에 작용합니다. 이 때문에 B가 A의 수정 결과로 바뀔 수 있습니다. 사후 결과 검증은 이미 덮어쓴 B를 보호하지 못합니다.

근거: [요청 원문 생성](/Users/techjuice/Documents/Dev/AI/opennotype/Sources/OpenNoType/App/AppModel.swift:381), [현재 대상 판단](/Users/techjuice/Documents/Dev/AI/opennotype/Sources/OpenNoType/Platform/TextInsertion.swift:328), [AX 쓰기](/Users/techjuice/Documents/Dev/AI/opennotype/Sources/OpenNoType/Platform/TextInsertion.swift:342), [paste 전 확인](/Users/techjuice/Documents/Dev/AI/opennotype/Sources/OpenNoType/Platform/TextInsertion.swift:424). [원문·선택 일치 검사](/Users/techjuice/Documents/Dev/AI/opennotype/Sources/OpenNoType/Platform/TextInsertion.swift:247)는 이미 있지만 실제 삽입 경로에서 사용하지 않습니다.

개선은 모드별 전달 정책을 분리하는 것입니다. 수정 모드는 쓰기 직전 PID·필드·원문·선택 범위가 캡처와 일치해야 합니다. 달라졌다면 결과를 남기고 사용자가 적용 위치를 선택하게 합니다. 일반 받아쓰기에서 현재 커서를 따르는 기존 동작은 별도로 유지할 수 있습니다.

완료 조건: A 선택 → 수정 시작 → B 선택 / 같은 앱 다른 입력창 이동 / 원문 직접 편집의 세 경우 모두 B를 변경하지 않고 결과가 남아야 합니다. 이번에는 개인 문장을 실제 덮어쓰는 재현은 하지 않았습니다.

**2. 앱별 문맥 허용을 element 소유 PID로 보장해야 합니다.**

[focused(in:)](/Users/techjuice/Documents/Dev/AI/opennotype/Sources/OpenNoType/Platform/TextInsertion.swift:157)은 요청한 PID보다 system-wide 포커스 결과를 먼저 사용하며 element의 실제 PID를 검사하지 않습니다. 첫 조회 실패 후 40ms 대기 중 A에서 B로 전환되면 B의 필드를 반환할 수 있습니다. [capture](/Users/techjuice/Documents/Dev/AI/opennotype/Sources/OpenNoType/Platform/TextInsertion.swift:190)는 여전히 A의 bundle ID로 허용목록을 판단하므로, A만 문맥 사용을 허용한 경우에도 B의 커서 앞 문자열이 요청에 포함될 수 있습니다.

문맥은 기본 꺼짐이라 모든 사용자에게 항상 발생하는 문제는 아닙니다. **A에 문맥 사용을 허용했고, AX 재시도 중 다른 앱으로 전환되는 조건**의 개인정보 경계 문제입니다. 잘못 결합한 앱 식별자와 element는 입력 대상도 어긋나게 할 수 있습니다.

개선: `AXUIElementGetPid`로 element의 소유 PID를 검증하고, 캡처 완료 시 앞에 있는 앱도 재검증합니다. 일관된 한 앱의 스냅샷을 얻지 못하면 다시 캡처하거나 중단합니다.

완료 조건: 주입 가능한 포커스 환경으로 “A 조회 실패 → B로 전환 → 재시도”를 만들어 B의 원문·선택·문맥이 A의 데이터로 반환되지 않는지 검증합니다. 실제 개인 문맥을 읽거나 외부로 보내는 실험은 하지 않았습니다.

**3. 1초 동안 보이지 않은 AX 입력을 영구 실패로 간주하면 중복됩니다.**

[전달 분기](/Users/techjuice/Documents/Dev/AI/opennotype/Sources/OpenNoType/Platform/InsertionOutcome.swift:98)는 AX 전송 후 1초 안에 변경이 보이지 않으면 원문·커서가 그대로인 경우 paste를 추가합니다. 그러나 기존 AX 요청이 그 직후 도착할 수 있습니다. [AX 상태 처리](/Users/techjuice/Documents/Dev/AI/opennotype/Sources/OpenNoType/Platform/TextInsertion.swift:350)는 `.success`와 `.cannotComplete`를 같은 accepted로 취급합니다. paste 직전의 늦은 변경 검사도 그 검사 이후 도착하는 AX는 막지 못합니다.

실제 production 전달·검증 코드에 AX 도착을 1.05초로 지연시킨 실험 결과:

`outcome=submittedUnverified.paste.timedOut pasteCount=1 resultingCopies=2`

개선: 전송 여부가 불확실한 AX에는 자동으로 두 번째 전송을 하지 않습니다. 직접 쓰기를 무시하는 앱은 기존처럼 사전에 pasteOnly로 분류하고, 명시적 거절과 전송 여부 불명 상태를 구분합니다. 사용자에게 전달 불확실성을 알려야 하며, 확인 시간만 늘리는 것은 근본 해결이 아닙니다.

완료 조건: AX 지연 0.9·1.05·2초, 취소가 겹치는 경우에도 결과가 최대 한 번만 제출되어야 합니다. [재현 소스](/Users/techjuice/Documents/Dev/AI/opennotype/docs/reviews/2026-09-09/evidence/insertion-delay-probe.swift), [결과](/Users/techjuice/Documents/Dev/AI/opennotype/docs/reviews/2026-09-09/evidence/insertion-delay-output.txt).

**4. 자동 사전 학습이 일반 내용 변경까지 기억합니다.**

[CorrectionLearner](/Users/techjuice/Documents/Dev/AI/opennotype/Sources/OpenNoTypeCore/Storage/CorrectionLearner.swift:35)는 한글↔영문 전환을 표기 교정으로 간주하고, 영문은 대문자가 하나라도 있으면 이름 신호로 인정합니다. 문장 첫 단어의 대문자도 이 조건을 통과합니다.

합성 사례에서 다음이 확인됐습니다.

| 사용자가 바꾼 문장 | 현재 자동 학습 후보 | 문제 |
| --- | --- | --- |
| `Cat is here.` → `Car is here.` | `Cat → Car` | 고양이에서 자동차로 내용이 바뀐 것을 철자 교정으로 판단 |
| `사과를 먹어요` → `banana를 먹어요` | `사과 → banana` | 언어 표기 교정이 아닌 다른 과일로의 변경 |

후보는 [AppModel](/Users/techjuice/Documents/Dev/AI/opennotype/Sources/OpenNoType/App/AppModel.swift:586)에서 확인 없이 개인 사전에 저장됩니다. 이후 음성 인식과 문장 정리에 잘못된 힌트가 전달될 수 있습니다. 모델이 항상 잘못 바꾼다는 의미는 아니지만, 잘못된 교정을 장기적으로 강화할 수 있습니다.

개선: 문장 첫 대문자만으로 이름을 판단하지 않고, 언어가 바뀌었다는 사실만으로 동일한 단어라고 단정하지 않습니다. 불확실한 항목은 검토 후보로 돌리고 “방금 학습 되돌리기”와 별도의 자동 학습 토글을 둡니다. `GR5Q → GROQ` 같은 기존 유용한 사례를 유지하는 회귀 검사도 필요합니다.

완료 조건: 위 의미변경 사례는 자동 등록하지 않고, 명확한 이름 표기 교정은 계속 후보가 되어야 합니다. [재현 결과](/Users/techjuice/Documents/Dev/AI/opennotype/docs/reviews/2026-09-09/evidence/core-probe-output.txt).

**5. 재처리에서 실패 당시 설정을 고정하면 복구가 막힙니다.**

[retry](/Users/techjuice/Documents/Dev/AI/opennotype/Sources/OpenNoType/App/AppModel.swift:528)는 현재 키를 읽은 뒤 모델 ID·로컬 인식·목소리 필터를 실패 당시 값으로 다시 설정합니다. 따라서 없는 모델 ID를 수정해도 실패 녹음은 이전 모델로 다시 요청합니다. 목소리 필터가 본인 음성을 놓친 경우에도 설정에서 필터를 꺼도 기존 실패 녹음의 재처리에는 계속 적용됩니다.

이는 현재 문서화된 “녹음 당시 설정으로 재처리”와 일치하므로 동작 자체가 문서와 다른 버그는 아닙니다. 다만 영구 오류를 빠져나오는 복구 선택지가 없습니다.

개선: “같은 설정으로 재시도”와 “설정을 바꿔 복구”를 함께 제공합니다. 후자는 모델, 로컬 인식 여부, 필터 해제를 선택하고 실제 전송 제공자를 명확히 보여 줍니다. 음성 인식 성공 후 문장 정리만 실패한 경우에는 암호화된 중간 전사문에서 재개하는 방식도 시간과 중복 호출을 줄일 수 있습니다.

완료 조건: 잘못된 모델 ID, 화자 미검출, 로컬 모델 미준비 각각에서 재녹음 없이 복구할 수 있어야 합니다.

**6. 로컬 모델의 다운로드와 매 실행 시 로딩을 구분해야 합니다.**

[초기 상태](/Users/techjuice/Documents/Dev/AI/opennotype/Sources/OpenNoType/App/AppModel.swift:39)는 매번 `.notPrepared`이고, [시작 검사](/Users/techjuice/Documents/Dev/AI/opennotype/Sources/OpenNoType/App/AppModel.swift:186)는 준비되지 않으면 녹음을 거절합니다. [모델 준비](/Users/techjuice/Documents/Dev/AI/opennotype/Sources/OpenNoType/App/AppModel.swift:546)는 버튼으로만 시작합니다. 이미 다운로드한 사용자도 앱을 다시 켠 뒤 수동 준비 과정을 거쳐야 합니다.

개선: 모델이 없는 상태, 다운로드되어 있지만 아직 메모리에 없는 상태, 준비 중, 준비 완료를 나눕니다. 사용하기로 설정한 로컬 모델은 캐시만 자동 로딩하거나 첫 단축키에서 준비합니다. 최초 대용량 다운로드의 명시적 시작 원칙은 유지합니다. 준비 작업은 취소할 수 있어야 합니다.

Claude에서는 실제로 로컬 처리가 강제되지만 [토글](/Users/techjuice/Documents/Dev/AI/opennotype/Sources/OpenNoType/Views/SettingsView.swift:29)은 별도 저장 Bool에 연결돼 꺼진 채 비활성으로 표시될 수 있습니다. “이 Mac에서 음성 인식 · Claude 사용 시 필수”처럼 실제 유효 상태로 표현하는 것이 좋습니다.

완료 조건: 캐시가 있는 상태에서 재실행 → 첫 단축키가 다시 다운로드 버튼을 찾는 과정 없이 준비·녹음으로 이어지고, 처음 다운로드와 진행 중 취소도 구분되어야 합니다.

**7. 실패 원음을 한 vault에 넣어 작은 조회도 무거워집니다.**

[FailurePayload](/Users/techjuice/Documents/Dev/AI/opennotype/Sources/OpenNoTypeCore/Storage/SecureStore.swift:48)는 원음 Data를 기록·사전과 같은 JSON vault에 넣습니다. [transaction](/Users/techjuice/Documents/Dev/AI/opennotype/Sources/OpenNoTypeCore/Storage/SecureStore.swift:200)은 매번 전체 복호화·디코딩 및 변경 전후 전체 JSON 인코딩을 합니다. 따라서 실패 목록이나 사전만 필요한 경우에도 모든 실패 원음이 처리됩니다. 앱은 [1분 간격](/Users/techjuice/Documents/Dev/AI/opennotype/Sources/OpenNoType/App/AppModel.swift:100)으로 snapshot을 조회합니다.

실제 SecureStore 소스를 `swiftc -O`로 컴파일하고, 한 건당 9분 분량에 해당하는 17.28MB 합성 Data로 측정했습니다.

| 실패 원음 수 | 원음 합계 | snapshot 1회 · 3회 관측 범위 | 격리 프로세스 최대 RSS |
| --- | --- | --- | --- |
| 0 | 0MB | 1ms 미만 | 약 7.8MB |
| 1 | 17.28MB | 126–128ms | 약 204MB |
| 3 | 51.84MB | 370–374ms | 약 1,015MB |

**RSS는 합성 데이터 저장과 snapshot 3회를 포함한 전체 격리 프로세스의 최고값입니다. 실행 중인 UI 앱의 메모리 사용량을 직접 잰 결과가 아닙니다.** 단위는 decimal MB입니다. 이 결과만으로 앱 UI가 370ms 멈춘다고 단정하지 않습니다. 저장소 actor의 비용과 메모리 압력이 커지는 것은 확인했습니다.

개선: 실패 음성은 개별 암호화 blob으로 분리하고, 메타데이터 조회는 원음을 읽지 않게 합니다. 실패 원음 총량 제한과 남은 보관 용량을 제공하고, 만료 정리도 개별 파일 기준으로 수행합니다.

완료 조건: 실패 원음 0·3·10건에서 메타데이터 조회 비용이 원음 총량에 비례해 증가하지 않아야 합니다. 분리 이후에도 24시간 만료, 원자 저장, 누락·손상·비정상 종료 시 원본 보존을 다시 확인합니다. [측정 코드](/Users/techjuice/Documents/Dev/AI/opennotype/docs/reviews/2026-09-09/evidence/storage-benchmark.swift), [3건 시간](/Users/techjuice/Documents/Dev/AI/opennotype/docs/reviews/2026-09-09/evidence/bench-3.txt), [3건 RSS](/Users/techjuice/Documents/Dev/AI/opennotype/docs/reviews/2026-09-09/evidence/bench-3-time.txt).

**8. 사전·기록의 읽기-수정-쓰기를 한 저장소 연산으로 묶어야 합니다.**

[사전 병합](/Users/techjuice/Documents/Dev/AI/opennotype/Sources/OpenNoType/App/AppModel.swift:480)과 [기록 추가](/Users/techjuice/Documents/Dev/AI/opennotype/Sources/OpenNoType/App/AppModel.swift:396)는 AppModel 메모리 배열을 복사한 뒤 전체 배열을 저장합니다. 자동 학습과 사용자의 사전 변경, 또는 새 기록 저장과 삭제가 await 사이에 겹치면 오래된 배열이 더 최신 변경을 덮을 수 있습니다. SecureStore의 lock은 각 저장을 보호하지만 두 호출자가 만든 오래된 배열을 자동 병합하지는 않습니다.

실제 저장 API에 오래된 동일 스냅샷으로 두 번 저장하는 순서를 주입한 결과:

- 사전은 기본 1개 + 수동 1개 + 학습 1개를 기대했지만 최종 2개였고 수동 항목이 사라졌습니다.
- 기록 전체 삭제 후 오래된 스냅샷으로 새 기록을 추가하면 삭제한 항목이 다시 나타났습니다.

이는 UI 이벤트 경합을 실제로 발생시킨 재현이 아니라 **AppModel이 사용하는 전체 배열 저장 계약에서 가능한 순서를 검증한 실험**입니다.

개선: `upsertDictionaryEntry`, `deleteDictionaryEntry(id:)`, `appendHistory`, `deleteHistory(id:)`처럼 변경 의도를 저장소에 전달하고 transaction 내부의 최신 상태에 적용합니다. 새 상태 또는 revision을 반환받아 UI도 갱신합니다.

완료 조건: 사전 자동 학습 + 수동 편집, 처리 완료 + 기록 삭제를 의도적으로 엇갈리게 실행해 등록 유실·삭제 부활이 없어야 합니다. [재현 코드](/Users/techjuice/Documents/Dev/AI/opennotype/docs/reviews/2026-09-09/evidence/store-concurrency-probe.swift), [결과](/Users/techjuice/Documents/Dev/AI/opennotype/docs/reviews/2026-09-09/evidence/store-concurrency-output.txt).

**9. 단축키 시작은 첫 비동기 대기 전에 한 작업이 점유해야 합니다.**

[AppModel.toggle](/Users/techjuice/Documents/Dev/AI/opennotype/Sources/OpenNoType/App/AppModel.swift:173)은 idle 확인 후 포커스 캡처를 기다리고 나서야 starting으로 바꿉니다. 캡처 중에는 두 번째 단축키도 시작 경로에 들어갈 수 있습니다. 더구나 [target 대입](/Users/techjuice/Documents/Dev/AI/opennotype/Sources/OpenNoType/App/AppModel.swift:197)이 generation 확인보다 먼저라 오래된 작업이 뒤늦게 최신 target을 덮을 수 있습니다.

개선: 첫 await 전에 starting과 job을 확정합니다. capture 결과는 지역 변수로 받고 generation이 일치할 때만 공유 상태에 반영합니다. 입력 테스트도 같은 시작 작업 소유 규칙을 적용합니다.

완료 조건: capture 지연, 빠른 단축키 연타, 준비 중 취소, 입력 테스트와 시작 겹침에서 recorder·target·snapshot이 모두 같은 job에 속해야 합니다.

**10. OpenRouter STT의 fallback 차단은 현재 요청 값만으로 보장되지 않습니다.**

[현재 요청](/Users/techjuice/Documents/Dev/AI/opennotype/Sources/OpenNoTypeCore/AI/ProviderClient.swift:70)은 `provider.allow_fallbacks:false`를 보내며 테스트 이름도 fallback 차단을 전제합니다. 그러나 2026-09-09 조회한 OpenRouter 공식 설명은 STT endpoint에서 `order`, `only`, `allow_fallbacks`, `data_collection`, `sort`가 적용되지 않으며, 여러 upstream 사이에 자동 분산할 수 있다고 명시합니다. [OpenRouter 공식 설명](https://openrouter.ai/blog/tutorials/transcription-on-openrouter/).

앱이 OpenRouter 대신 다른 API 제공자로 직접 전환한다는 뜻은 아닙니다. **OpenRouter 내부의 실제 음성 처리 사업자를 요청 값으로 고정할 수 있다는 보장**이 성립하지 않는 것입니다.

개선: 무효한 보장과 테스트 표현을 정리하고, OpenRouter가 중개한다는 전송 안내를 표시합니다. 직접 사업자 고정이 필요한 선택은 제공자 직접 연결 또는 로컬 인식으로 구분합니다. API mock은 요청 모양을 검증할 뿐 서버가 그 옵션을 지키는지 증명하지 않는다는 점을 유지해야 합니다.

**추가 사용성·복구 개선**

| 항목 | 현재 상태와 구체적 개선 |
| --- | --- |
| 권한 거부 복구 | [requestMicrophone](/Users/techjuice/Documents/Dev/AI/opennotype/Sources/OpenNoType/App/AppModel.swift:111)은 Bool만 갱신합니다. 미결정·허용·거부·제한을 구분하고 거부 상태는 시스템 설정 안내와 재확인으로 연결합니다. |
| 실제 준비 상태 | 홈은 키 저장 여부·마이크·AX만 체크합니다. “키 저장됨”과 “연결 확인됨”, 모델 준비와 단축키 충돌을 구분하고 첫 성공 뒤 준비 카드는 접습니다. |
| 첫 입력 연습 | 이미 있는 무음·무 API 입력 테스트를 온보딩 마지막 단계에 연결합니다. 음성을 녹음하기 전에 실제 입력 대상과 권한을 확인할 수 있습니다. |
| 페이지별 스크롤 | 실제 설정 화면에서 음성 모델로 이동했을 때 스크롤이 하단에 남아 로컬 모델 준비 카드가 위로 숨었습니다. [공통 ScrollView](/Users/techjuice/Documents/Dev/AI/opennotype/Sources/OpenNoType/Views/MainView.swift:26)의 위치를 페이지별로 관리하거나 새 페이지 첫 방문은 맨 위로 이동합니다. |
| 로그인 자동 실행 | [설정 저장](/Users/techjuice/Documents/Dev/AI/opennotype/Sources/OpenNoType/App/AppModel.swift:155)은 register 성공과 저장 Bool만 사용합니다. 실제 `SMAppService.mainApp.status`를 조회해 승인 필요·사용 가능·꺼짐을 구분합니다. [Apple requiresApproval](https://developer.apple.com/documentation/servicemanagement/smappservice/status-swift.enum/requiresapproval?language=objc). |
| 손상된 설정 | [hotkeys 디코딩](/Users/techjuice/Documents/Dev/AI/opennotype/Sources/OpenNoType/App/Preferences.swift:40)은 빈 배열을 수용하지만 홈·메뉴·설정은 0–2번을 직접 읽습니다. 정상 UI로 생성되는 값은 아니므로 방어 공백으로 분류하며, 개수·중복 검증과 해당 필드만 복구하는 경로를 둡니다. |
| 임시 vault 복구 | 정상 vault와 불완전한 staging 파일이 함께 있으면 읽기까지 중단합니다. 합성 3바이트 staging 파일에서 `corruptedStorage`와 정상 vault 보존을 확인했습니다. 보존 정책은 유지하되 정상 파일 검증 후 임시 파일 격리와 복구 안내를 제공합니다. [정리 경로](/Users/techjuice/Documents/Dev/AI/opennotype/Sources/OpenNoTypeCore/Storage/SecureStore.swift:207). |
| 처리 상태 | 현재 포괄적인 “정리 중”을 음성 인식·문장 정리·입력 확인으로 나눕니다. 이미 있는 단계별 처리 시간과 연결해 지연 원인을 이해하게 합니다. |
| 비용·품질 기록 | HistoryEntry에는 실제 모델·음성 길이·단계별 사용량·재시도·오류 단계가 없습니다. 원문을 추가 수집하지 않고도 모델별 지연·실패율·API usage를 비교할 수 있는 진단 메타데이터를 둡니다. 고정 단가 추정보다 실제 usage가 있으면 우선 사용합니다. |
| 학습·삭제 제어 | 자동 학습 토글과 최근 학습 되돌리기, 개별 삭제의 짧은 실행 취소, 보관 기간 단축 시 영향 설명을 추가합니다. |
| 오디오 장치 오류 | 녹음 완료 delegate의 성공 여부·encode 오류를 별도로 처리하고 마이크 분리·절전·입력 장치 변경에서 실제 중단과 실패 복구를 확인합니다. 현재 특정 장치의 오류를 재현한 것은 아닙니다. |

**품질 검증을 어떻게 바꿀지**

현재 [16개 의미 보존 fixture](/Users/techjuice/Documents/Dev/AI/opennotype/docs/fixtures/dictation-quality.json)는 유용한 기대 결과 명세입니다. 하지만 프롬프트가 그 기대를 담았다는 테스트와 실제 발화가 기대 결과로 변환된다는 평가는 다릅니다.

첫 평가 묶음은 40–60개의 비개인·동의된 발화로 구성하는 방안을 권합니다. 짧은 한국어, 한영 혼용 고유명사, 숫자·날짜·부정, 명확한 자기수정, 미완성 발화, 한국어↔영어 번역, 선택 문장 수정, 무음·소음·긴 발화를 포함합니다. 실제 음성 평가와 합성 파이프라인 평가 결과를 분리합니다.

같은 음성을 같은 설정으로 반복 평가하고 다음을 기록합니다. 숫자는 실제 측정 후 채워야 하며 이번에 성능 우위를 추정하지 않았습니다.

| 측정 | 필요한 이유 |
| --- | --- |
| 의미 보존·숫자·부정·이름 보존 | 단순 글자 오류율만으로 업무상 큰 오류를 놓치지 않기 위해 |
| 고유명사 정확도와 말하지 않은 내용 삽입 | 사전과 예시 프롬프트가 유용한지, 오히려 편향을 만드는지 확인 |
| 번역 자연스러움과 의도·높임말 유지 | 유창하지만 뜻이 달라지는 실패 구분 |
| 종료 후 첫 결과·최종 입력의 p50/p95 | 인식·정리·입력 확인 중 실제 병목 구분 |
| 정확한 위치·중복 없이 한 번 입력 | API 200이나 JSON 파싱 성공을 사용자 성공과 구분 |
| 실제 사용량·재시도 비용 | 모델 선택과 실패 복구 비용 비교 |
| 타인 음성 잔류·본인 음성 누락 | 화자 필터의 양쪽 오류를 따로 평가 |

외부 앱은 우선 Claude·Codex·Antigravity의 실제 빈 시험 입력창에서 받아쓰기·번역·선택 수정을 검증한 뒤 나머지 앱으로 넓히는 순서가 적절합니다. 각 흐름에는 선택 변경, 다른 앱 활성화, 취소, 클립보드 보존, 재처리를 넣습니다. [대상 앱 9개 × 5개 항목](/Users/techjuice/Documents/Dev/AI/opennotype/docs/verification.md:118)은 문서상 모두 Pending입니다. 과거 일부 입력 성공 기록이나 사용자의 해결 피드백과 이 전체 매트릭스 완료는 구분해야 합니다. 제공자 검증 목록에는 새 Groq 경로도 포함해야 합니다.

접근성은 코드에 여러 버튼 라벨이 있고 기본 구조도 갖췄습니다. 다음에는 키보드만으로 모든 주요 흐름을 완료하고, VoiceOver에서 현재 페이지·녹음 시작/종료·실패 결과를 알 수 있는지 확인해야 합니다. 9–11pt 설명, 라이트/다크 대비, 확대·작은 작업 영역을 실측 대상으로 둡니다. 이번에 VoiceOver나 색상 대비 통과·실패를 판정하지 않았습니다.

**권장 작업 순서와 완료 기준**

| 묶음 | 범위 | 완료 기준 |
| --- | --- | --- |
| 첫 수정 | 1·2번 입력 대상 일관성, 3번 중복 전송, 9번 시작 작업 경합 | 선택 변경·앱 변경·지연 AX·연타·취소 주입 검사 통과, 기존 pasteOnly 앱 입력 유지 |
| 두 번째 수정 | 4번 학습, 5번 복구, 6번 모델 준비 및 권한 안내 | 잘못된 학습 방지, 영구 모델 오류와 필터 오류 복구, 캐시가 있는 재실행 흐름 완료 |
| 세 번째 수정 | 7·8번 저장소와 임시 파일 복구 | 오래된 변경 유실 방지, 원음 규모에 좌우되지 않는 메타데이터 조회, 만료·손상 보존 검증 |
| 실사용 검증 | 실제 음성·제공자·대상 앱 매트릭스, 접근성 | 소스/앱 버전·모델·앱·성공 여부·지연·남은 제한을 기록 |
| 배포 검증 | 실제 서명·공증·다른 Mac 설치·이전 버전 업데이트 | 다운로드한 배포물에서 권한·Keychain·입력·Sparkle 업데이트 확인 |

현재는 **개발 미리보기** 표시를 유지하는 것이 타당합니다. [CI](/Users/techjuice/Documents/Dev/AI/opennotype/.github/workflows/ci.yml:18)는 단위 테스트와 개발 앱 ZIP을 만들고, [출시 안내](/Users/techjuice/Documents/Dev/AI/opennotype/docs/verification.md:153)는 Developer ID·공증·Gatekeeper·업데이트를 별도 미완료로 구분합니다. 이 보고서에서는 이를 출시 완료나 실사용 호환성 입증으로 바꾸지 않았습니다.

**보존한 근거**

[재현 자료와 실행 방법](/Users/techjuice/Documents/Dev/AI/opennotype/docs/reviews/2026-09-09/evidence/README.md)에 전체 테스트 로그, 합성 probe 4개, 지연 입력 결과, 오래된 스냅샷 저장 결과, 저장소 측정 결과를 모았습니다. API 키·개인 음성·실사용 vault는 포함하지 않았습니다.

