# Jev 문장 검토 (실험 기능)

Jev는 문장을 생성하는 모델을 대체하지 않고, 받아쓰기 원문과 정리 결과를 비교한다. 현재 구현은 의미 변경·내용 추가·누락 검사와 제한된 영문 표기 제안이다. 음성 인식, 자동 모델 라우팅과 Jev의 무인 사전 학습은 이 기능의 범위가 아니다. 0.1.15는 사용자가 확인한 표기의 사전 저장·되돌리기와 기존 받아쓰기 결과의 명시적 재검토를 추가한다.

## 아이디어별 적용 현황 — 2026-10-01

현재 소스 기준으로 **의미 검토와 입력 보호를 중심으로 한 1차 기능이 구현되어 있다. 처음 검토한 확장 아이디어 대부분이 자동화된 상태는 아니다.** 아래의 ‘구현’은 기능 경로가 있다는 뜻이며, 현재 설치 앱에서 해당 설정이 켜져 있거나 정확도가 보장된다는 뜻은 아니다. 기존 앱 기능과 Jev가 새로 담당하는 기능을 구분한다.

| 활용 방향 | 현황 | 현재 동작과 남은 범위 | 코드 근거 |
| --- | --- | --- | --- |
| 의미 보존 검토·입력 보호 | 1차 구현 | 원문과 정리 결과의 의미 변경·내용 추가·누락을 세 개의 Noul 질문으로 검사한다. 입력 후 안내하거나, 입력 전에 최대 위험 점수 0.9 이상이면 보류하고 원문·결과를 복사할 수 있다. 오류 문장을 자동으로 고치지는 않는다. 시간 초과·검토 실패에는 기존 결과를 사용한다. 비교 대상은 인식된 텍스트이므로 음성 인식 자체의 오류를 검증하지는 못한다. | [DecisionClient](../Sources/OpenNoTypeCore/AI/DecisionClient.swift)의 `makeRequest`, [AppModel](../Sources/OpenNoType/App/AppModel.swift)의 `process`·`reviewDecision`, [흐름 검사](../Tests/OpenNoTypePlatformTests/DecisionReviewFlowTests.swift) |
| 한국어·영어 표기 판별 | 부분 구현 | 원문에 있는 앱 내 기술명·개인 사전 후보를 최대 네 개 골라 Choice로 사용·원문 유지·불확실을 판정한다. 영문 복원과 한글 유지 제안을 표시한다. 0.1.15에서는 영문 후보 사용 제안을 확인한 뒤 사전에 저장하고 되돌릴 수 있다. 현재 결과 자동 치환·새 표기 생성·무인 사전 저장은 없다. 한글 유지 제안은 문맥에 한정될 수 있어 전역 사전으로 역등록하지 않는다. | [AppModel](../Sources/OpenNoType/App/AppModel.swift)의 `decisionTermCandidates`·`decisionSuggestions`, [MainView](../Sources/OpenNoType/Views/MainView.swift)의 최근 문장 검토 |
| 사용자 교정 자동 학습 | 기존 기능 있음·Jev 연동 없음 | 앱이 확인한 삽입 결과에 대한 후속 수정을 제한적으로 관찰한다. 대소문자·제한된 이름 철자 교정은 로컬 규칙으로 학습하고, 넓은 변경은 검토 후보로 둔다. Jev 제안을 자동 저장하지는 않는다. 별도의 명시적 확인을 거친 사전 등록은 가능하며, 기존 로컬 자동 학습과 되돌리기 상태를 분리한다. | [CorrectionLearner](../Sources/OpenNoTypeCore/Storage/CorrectionLearner.swift), [AppModel](../Sources/OpenNoType/App/AppModel.swift)의 `watchCorrection`·`applyLearnedEntry` |
| 난도·비용에 따른 모델 자동 선택 | 미구현 | 사용자가 음성·문장 모델과 Jev 연결 방식을 선택한다. 모델·참고 가격 목록과 비교 자료는 있지만, Jev가 쉬운 문장은 저렴한 모델로 보내거나 위험한 결과를 더 강한 모델에 자동 재요청하지 않는다. | [ProviderModelPicker](../Sources/OpenNoType/Views/ProviderModelPicker.swift), [ProviderClient](../Sources/OpenNoTypeCore/AI/ProviderClient.swift), [Preferences](../Sources/OpenNoType/App/Preferences.swift) |
| 명령 의도 분류·선택 문장 수정 검증 | Jev에는 미구현 | 받아쓰기·번역·선택 문장 수정은 기존 명시적 모드로 구분한다. Jev 검토는 `mode == .dictation`일 때만 실행한다. 발화에서 실행할 명령을 자동 선택하거나 번역·선택 수정 결과의 의도 일치를 Jev로 검사하지 않는다. | [AppModel](../Sources/OpenNoType/App/AppModel.swift)의 `shouldReview`, [ProcessingPrompt](../Sources/OpenNoTypeCore/AI/ProcessingPrompt.swift), [미지원 모드 검사](../Tests/OpenNoTypePlatformTests/DecisionReviewFlowTests.swift)의 `testUnsupportedModesAndProvidersDoNotSendExtraText` |
| 지연·비용 줄이기 | 부분 구현 | 독립 질문을 요청 한 번에 묶고 네트워크 응답을 1.5초로 제한한다. 입력 후 검토는 입력 대기를 늘리지 않으며 TypeSafe 직접 연결도 제공한다. 쉬운 문장 검토 생략, 판정 캐시, Jev에 따른 모델 승격·재생성은 없다. 문장 생성 모델의 추론 제한은 별도 [OpenRouter 정책](../Sources/OpenNoTypeCore/AI/OpenRouterTextPolicy.swift)이며 Jev의 판단으로 제어하는 기능은 아니다. | [DecisionClient](../Sources/OpenNoTypeCore/AI/DecisionClient.swift), [AppModel](../Sources/OpenNoType/App/AppModel.swift)의 `reviewDecision`·입력 후 검토 작업 |
| 문제 문장 재검토·재처리 | 부분 구현 | 보류된 원문과 결과를 비교·복사할 수 있다. 기존 ‘원문 다시 처리’는 현재 문장 생성 모델로 미리보기를 만든다. 0.1.15에서는 최근 받아쓰기·저장된 받아쓰기 기록·재처리 미리보기를 사용자가 명시적으로 Jev에 다시 검토 요청할 수 있다. 실패한 녹음의 ‘다시 처리’는 전체 파이프라인을 거치므로 받아쓰기에는 현재 Jev 설정이 적용된다. 수동 재검토는 진단만 갱신한다. 오류 유형별 자동 재생성·판정 이력을 통한 학습은 없다. | [AppModel](../Sources/OpenNoType/App/AppModel.swift)의 `reprocessHistory`·`retry`·`process`, [기록 재처리 검사](../Tests/OpenNoTypePlatformTests/HistoryReprocessingTests.swift) |
| 개인정보 전송 통제 | 기본 통제 구현 | 기본 꺼짐, 명시적 연결 선택, Keychain 키 분리, 최소 텍스트 전송, 크기 제한, 리다이렉트·재시도 차단, 취소 후 늦은 결과 폐기를 적용했다. Jev에는 오디오·주변 문맥·앱 이름을 보내지 않는다. 개인정보 탐지·자동 마스킹, Jev의 온디바이스 실행, 제공자 측 보관 삭제를 보장하는 기능은 없다. | [DecisionClient](../Sources/OpenNoTypeCore/AI/DecisionClient.swift), [KeychainSecrets](../Sources/OpenNoTypeCore/Storage/KeychainSecrets.swift), [AppModel](../Sources/OpenNoType/App/AppModel.swift)의 `stopDecisionReview`, [Preferences](../Sources/OpenNoType/App/Preferences.swift) |

자동화 확대와 현재 검토 기능의 정확도는 별개다. [72개 합성 사례의 실제 비교](reviews/2026-10-01/jev-typesafe-direct.md)에서 현재 보호 기준의 의미 오류 탐지는 OpenRouter 21/30, TypeSafe 직접 19/30이었고, 표기 선택 일치는 두 방식 모두 39/52였다. 이 결과는 자동 치환·자동 사전 학습을 켜거나 Jev 판정만으로 결과의 안전성을 보장할 근거가 아니다. 현 단계는 **진단을 보여 주고 강한 위험 신호에서 입력을 보류하는 보조 기능**으로 설명하는 것이 정확하다.

최신 재검증과 main 병합 근거는 [0.1.14 최종 검증](reviews/2026-10-01/jev-final-verification.md)에 별도로 기록했다.

## 사용 방법

**설정 → AI 연결 → Jev 문장 검토 · 실험 기능**에서 연결 방식과 검토 모드를 선택한다. 별도 서버나 SDK 설치는 필요하지 않다. 기존 설치의 연결 방식은 **OpenRouter**, 검토 모드는 **꺼짐**을 유지한다.

| 연결 방식 | 사용할 키 | 전송 경로 |
| --- | --- | --- |
| OpenRouter 키 하나로 사용 | 문장 정리에 저장한 기존 OpenRouter 키 | OpenRouter → TypeSafe |
| Jev API 키로 직접 연결 | TypeSafe에서 발급한 Jev 전용 키 | TypeSafe에 직접 전송 |

OpenRouter 방식은 문장 정리 제공자도 OpenRouter로 선택해야 한다. 직접 연결은 문장 정리 제공자와 독립적이다. 예를 들어 Groq 음성 인식 + OpenRouter 문장 정리 + TypeSafe 검토를 함께 사용할 수 있다. TypeSafe 키는 Jev 설정의 전용 입력란에서 Keychain에 저장하며 OpenRouter 키와 교환하거나 덮어쓰지 않는다. 키를 입력만 한 초안은 실제 요청에 사용하지 않는다.

**Jev 연결 테스트**는 현재 연결 방식과 저장된 키로 고정된 합성 문장을 검사한다. 녹음·자동 입력·개인 기록 추가 없이 API 연결과 응답 형식을 확인한다. 검토 모드를 켜지 않고도 명시적으로 테스트할 수 있으며, 실제 받아쓰기 품질 검증과는 구분한다.

| 모드 | 입력 동작 | 검토 결과 |
| --- | --- | --- |
| 꺼짐 | 기존 받아쓰기 흐름 | 받아쓰기를 Jev에 전송하지 않음. 명시적 연결 테스트는 별도 |
| 입력 후 검토 | 입력과 기록 처리를 마친 뒤 비동기 검사 | 결과를 바꾸지 않고 시작하기 화면에 진단·표기 제안 표시 |
| 입력 전 보호 | 정리 결과를 검사한 뒤 입력 | 강한 의미 변경 신호가 있으면 자동 입력 보류, 원문과 결과 비교·복사 제공 |

입력 전 보호는 API 응답을 1.5초까지 기다린다. 사용량 저장 등 로컬 처리는 이 네트워크 제한과 별개다. 검토 실패·시간 초과에는 기존 결과로 입력하며, 검토를 완료하지 못했다고 표시한다. 이 동작은 미검사 문장을 차단하는 정책이 아니므로 검토 통과나 정확성을 보장하지 않는다. 번역·선택 문장 수정은 검사하지 않는다.

현재 보호 기준은 세 위험 점수 중 최댓값이 0.9 이상인 경우다. 실험을 위한 임계값이며 90% 정확도를 의미하지 않는다. Choice의 confidence도 정답률이 아니다. 모델과 기준을 변경할 때에는 오경보와 미탐지를 다시 측정해야 한다.

## 표기 제안

`오픈 라우터 → OpenRouter`, `원 패스워드 → 1Password` 같은 앱 내 기술명과 개인 사전에서 현재 원문에 나타나는 후보를 최대 네 개 고른다. 후보가 실제 문맥의 같은 대상을 가리키는지, 한글·인용·식별자를 유지해야 하는지 Jev의 Choice로 판정한다. 모델이 새 이름을 생성하게 하지 않는다.

자동 치환하지 않으며 사전에 자동 저장하지도 않는다. 원문 표기를 유지해야 하는데 정리 결과에 영문 후보가 들어갔다면 역방향 제안도 표시한다. 원문에 이미 있는 Latin 표기는 대소문자가 달라도 역방향 제안에서 보호한다. 일반 외래어와 고유명사를 혼동할 수 있으므로 제안을 확인한 뒤 반영한다.

## 제안 확인 후 사전 저장 · 0.1.15

영문 후보를 사용하라는 제안만 사전 저장 대상으로 제공한다. 원문과 후보, 기존 사전 매핑을 확인한 뒤 등록한다. 저장한 표기는 이후 음성 인식·문장 정리 요청의 사전 힌트로 사용하며, 현재 결과·이미 입력한 글·클립보드는 바꾸지 않는다. 사전 저장 자체에는 API 호출이 없다. 자동 학습이 꺼져 있어도 명시적 저장은 가능하다.

같은 매핑이 이미 있으면 중복 저장하지 않는다. 기존 매핑을 바꾸려면 변경 내용을 확인해야 하며, 확인 중 다른 창·작업에서 항목을 바꿨다면 덮어쓰지 않고 다시 확인하도록 한다. 저장과 비교는 암호화 저장소의 같은 트랜잭션에서 수행한다. 되돌리기는 이번 저장본과 현재 항목이 정확히 같을 때만 이전 상태를 복구한다. 나중의 수동 수정은 덮어쓰지 않으며 기존 자동 학습의 되돌리기와 별도로 관리한다.

한글 유지 제안은 인용이나 ‘이번 문장은 한글로’라는 문맥일 수 있다. 이 제안을 영문→한글 전역 사전 규칙으로 저장하는 버튼은 제공하지 않는다.

## 기존 결과를 명시적으로 재검토 · 0.1.15

최근 받아쓰기, 저장된 받아쓰기 기록, 다시 처리한 미리보기에서 원문·결과를 Jev에 비교 요청할 수 있다. 전송할 대상과 선택한 연결 제공자를 확인하고 실행한다. API 사용량·비용이 추가되며 자동 검토 모드가 꺼져 있어도 이 한 번의 명시적 요청은 가능하다. 자동 검토 설정은 바뀌지 않는다.

재검토는 문장을 새로 생성하지 않는다. 기존 결과·저장 기록·외부 앱 입력을 바꾸지 않고 해당 대상의 진단만 표시한다. 의미 변경·내용 추가·내용 누락 신호를 구분하며 신호 점수를 정답률로 표시하지 않는다. 같은 문장을 다시 평가해 다른 결과를 얻더라도 정확성이 개선됐다는 보장은 없다.

검토 문맥·진단·제안은 메모리에만 둔다. 새 작업·대상 전환·키/제공자 변경·기록 삭제·미리보기 닫기는 관련 작업을 취소하고 늦은 결과를 폐기한다. 번역과 선택 문장 수정은 현재 비교 질문의 범위가 아니므로 제외한다. 너무 긴 원문·결과는 몰래 잘라 보내지 않고 요청을 막는다.

## 전송·보관·비용

- OpenRouter 방식은 `typesafe/jev-1.13` 모델과 `/api/alpha/decisions`를 사용한다. 직접 연결은 `jev-1.13.0` 모델과 `https://api.typesafe.ai/v1/systemone`을 사용한다. 두 방식 모두 원문·정리 결과·표기 후보가 검토 대상이다. 키는 선택한 서비스의 고정된 주소에만 보내며 다른 서비스로 자동 전환하지 않는다.
- 이 검토에는 녹음 파일, 주변 앱의 문맥, 앱 이름을 보내지 않는다. 기존 음성·문장 처리의 전송은 각각의 설정을 따른다.
- 검토 진단은 메모리에만 둔다. 원문·정리 결과는 기존 기록 보관 설정을 따른다. 기록을 꺼도 검토를 별도로 선택할 수 있다.
- 새 작업·취소·검토 해제·기록 해제 또는 삭제 시 진행 중인 검토를 취소하고 진단을 지운다. 이미 전송한 데이터가 제공자에서 삭제되었다는 뜻은 아니다. 기록 해제 이후 새 받아쓰기는 선택한 검토 설정을 적용한다.
- HTTP 리다이렉트와 자동 재시도는 사용하지 않는다. 요청·응답 크기를 제한하고, 응답의 유형·확률·모델을 검사한다.
- 사용량 통계가 켜져 있으면 **Jev 검토** 단계로 요청·토큰·비용을 따로 기록한다. OpenRouter는 공급자 보고 비용을 사용하고, 없으면 미확인이다. TypeSafe는 보고 비용이 없을 때 유효한 입력 토큰과 공식 요금(2026-10-01 기준 입력 100만 토큰당 $0.042, 출력 무료)으로 **추정**하며, 토큰이 없거나 실패·취소되면 미확인으로 남긴다. TypeSafe 요청은 로컬 무료 처리로 집계하지 않는다.

## 재현 가능한 평가

`docs/fixtures/decision-quality.json`은 개인정보가 없는 한국어·영어 혼합 합성 문장 묶음이다. 정상 정리와 오류가 있는 정리 결과를 쌍으로 평가한다. production Swift의 요청 생성기·응답 파서를 공유하며, 음성 인식이나 문장 생성 모델의 정확도를 측정하는 시험은 아니다.

```sh
python3 scripts/compare-decisions.py
# 비용 상한을 명시한 실제 호출. 키는 1Password 등에서 환경 변수로 주입한다.
python3 scripts/compare-decisions.py --live --max-usd 0.10 --workers 4 --deadline 10 \
  --output build/decision-bench-live.json
# TypeSafe 직접 연결
python3 scripts/compare-decisions.py --provider typesafe --live --max-usd 0.10 --workers 1 --deadline 10 \
  --output build/decision-bench-typesafe.json
```

기본 실행은 네트워크 없는 dry run이다. 실제 호출은 선택에 따라 `OPENROUTER_API_KEY` 또는 `TYPESAFE_API_KEY`만 사용하며 응답 원문이나 키를 결과 파일에 저장하지 않는다. 응답 성공률·유효 판정률, 오류 미탐지·정상 문장 오경보, 표기 선택 일치율, p50/p95 지연과 앱의 1.5초 제한 내 응답률, 보고 비용·추정 비용·미확인 비용 건수를 구분한다. 긴 평가 제한에서 받은 판정을 실제 앱이 그 시간까지 기다린다고 해석하면 안 된다.

공식 근거: [OpenRouter Jev 안내](https://openrouter.ai/docs/guides/community/jev), [Decisions API 계약](https://openrouter.ai/docs/api/api-reference/alphadecisions/submit-a-decisions-request), [Jev 1.13 모델·가격](https://openrouter.ai/typesafe/jev-1.13), [TypeSafe 직접 API](https://docs.typesafe.ai/api), [TypeSafe 모델·가격](https://docs.typesafe.ai/models), [TypeSafe confidence](https://docs.typesafe.ai/confidence).
