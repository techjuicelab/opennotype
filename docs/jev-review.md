# Jev 문장 검토 (실험 기능)

Jev는 문장을 생성하는 모델을 대체하지 않고, 받아쓰기 원문과 정리 결과를 비교한다. 현재 구현은 의미 변경·내용 추가·누락 검사와 제한된 영문 표기 제안이다. 음성 인식, 자동 모델 라우팅, 자동 사전 학습은 이 기능의 범위가 아니다.

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

아직 자동 치환하지 않으며 사전에 자동 저장하지도 않는다. 원문 표기를 유지해야 하는데 정리 결과에 영문 후보가 들어갔다면 역방향 제안도 표시한다. 일반 외래어와 고유명사를 혼동할 수 있으므로 제안을 확인한 뒤 반영한다.

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
