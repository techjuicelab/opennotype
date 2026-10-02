# 문장 정리 모델과 비용

0.1.13의 **설정 → AI 연결 → 문장 정리 → 모델**에서 OpenRouter 모델 20개를 선택할 수 있다. 메뉴의 `$입력 / $출력`은 각각 **100만 토큰당 USD**다. 제공자를 Groq로 바꾸면 기존 GPT OSS 2개에도 가격을 표시한다. 직접 입력한 모델 ID와 기존 선택은 그대로 유지된다.

## 이번 비교에서의 선택

**한국어·영어를 함께 쓰는 받아쓰기는 GPT-6 Luna를 먼저 권한다.** 아래 16개 합성 사례에서 의미·표기·정리 조건을 모두 충족했고, 문장 API 응답 중앙값이 약 1.02초였다. 입력/출력 단가는 `$0.10 / $0.50`으로 현재 모델 목록에서 충분히 저렴한 편이다.

- **GPT-6 Luna:** 이번 표본의 균형 추천. 16/16 정상 응답, 16/16 조건별 검토 충족.
- **DeepSeek V4.1 Flash:** 같은 16/16 조건 충족. 입력 단가 `$0.03`은 더 낮지만 응답 중앙값은 약 3.75초였다.
- **Qwen3.7 Flash:** `$0.03 / $0.13`, 중앙값 약 0.96초. 16/16 정상 응답이지만 GitHub 영문 복원과 반복 제거가 각각 한 사례에서 부족했다. 최저 비용을 우선할 때 비교할 후보다.
- **Qwen3.8 Flash:** 더 최신이나 이번 표본에서는 Qwen3.7보다 비싸고 느렸다. 한 사례에서 군말이 남았다.
- **Solar Mini/Pro 4, Ling 3.0 Flash, GPT OSS 20B:** 낮은 단가만으로 추천하지 않는다. 이번 조건에서는 영문 표기·정리 누락, 빈 응답 또는 의미 변화가 관찰됐다.

입력 1,000토큰·출력 200토큰을 1,000회 처리한다고 가정하면, 캐시·할인·추론을 제외한 문장 처리 비용은 GPT-6 Luna **$0.20**, Qwen3.7 Flash **$0.056**, DeepSeek V4.1 Flash **$0.13**이다. 실제 입력에는 앱의 정리 지시문·사전도 포함된다. 음성 인식과 Jev 비용은 별도다.

각 모델을 한 번씩 확인한 20건과, 11개 모델을 16문장씩 비교한 176건의 [실측 보고서](reviews/2026-10-01/text-model-value-comparison.md)를 참고한다. **작은 합성 표본에 대한 조건별 검토 확인이며 일반적인 정확도나 실제 음성 품질을 보장하지 않는다.** 지연 시간은 문장 API만 측정하며 음성 인식·자동 입력·Jev는 포함하지 않는다. 기존 사용자의 선택은 자동 변경하지 않았다.

## 가격과 최신성의 기준

아래는 **2026-10-01 미국 동부 시간**에 확인한 [OpenRouter 공개 API](https://openrouter.ai/api/v1/models)의 공시 참고 단가다. 등록일은 OpenRouter 카탈로그에 추가된 날짜이며, 제조사의 출시일과 다를 수 있다. 모든 최신 모델을 포괄한 순위가 아니라, 저가 문장 처리에 적합한 후보와 기존 비교용 모델을 선별했다. 무료·preview·자동 라우터·코딩 전용 모델은 제외했다.

공급자, 일시 할인, 캐시, 컨텍스트 길이, 추론 토큰에 따라 실제 청구액이 다르다. 카탈로그 단가와 모델 소개 페이지의 최저 공급자 가격이 다를 수도 있다. 앱은 카탈로그 조회일과 공식 링크를 표시하며 실제 사용량 화면에서는 응답이 보고한 비용을 우선한다. 현재 Solar Mini/Pro 4와 Ling 3.0 Flash에는 할인이 적용되어 있다.

| 모델 ID | OpenRouter 등록일 (UTC) | 입력 / 100만 토큰 | 출력 / 100만 토큰 |
|---|---|---:|---:|
| [upstage/solar-mini4](https://openrouter.ai/upstage/solar-mini4) | 2026-09-23 | $0.05 | $0.2 |
| [upstage/solar-pro4](https://openrouter.ai/upstage/solar-pro4) | 2026-08-10 | $0.09 | $0.36 |
| [qwen/qwen3.7-flash](https://openrouter.ai/qwen/qwen3.7-flash) | 2026-07-27 | $0.03 | $0.13 |
| [qwen/qwen3.8-flash](https://openrouter.ai/qwen/qwen3.8-flash) | 2026-08-26 | $0.15 | $0.47 |
| [deepseek/deepseek-v4.1-flash](https://openrouter.ai/deepseek/deepseek-v4.1-flash) | 2026-09-10 | $0.03 | $0.5 |
| [deepseek/deepseek-v4-flash](https://openrouter.ai/deepseek/deepseek-v4-flash) | 2026-04-24 | $0.042 | $0.084 |
| [xiaomi/mimo-v2.6-flash](https://openrouter.ai/xiaomi/mimo-v2.6-flash) | 2026-09-21 | $0.14 | $0.28 |
| [z-ai/glm-5.3-flash](https://openrouter.ai/z-ai/glm-5.3-flash) | 2026-08-26 | $0.15 | $0.5 |
| [openai/gpt-6-luna](https://openrouter.ai/openai/gpt-6-luna) | 2026-09-22 | $0.1 | $0.5 |
| [google/gemini-3.5-flash-lite](https://openrouter.ai/google/gemini-3.5-flash-lite) | 2026-07-21 | $0.3 | $2.5 |
| [google/gemini-3.1-flash-lite](https://openrouter.ai/google/gemini-3.1-flash-lite) | 2026-05-07 | $0.25 | $1.5 |
| [google/gemma-4-26b-a4b-it](https://openrouter.ai/google/gemma-4-26b-a4b-it) | 2026-04-03 | $0.0765 | $0.255 |
| [google/gemma-4-31b-it](https://openrouter.ai/google/gemma-4-31b-it) | 2026-04-02 | $0.09 | $0.34 |
| [openai/gpt-oss-120b](https://openrouter.ai/openai/gpt-oss-120b) | 2025-08-05 | $0.037 | $0.17 |
| [openai/gpt-oss-20b](https://openrouter.ai/openai/gpt-oss-20b) | 2025-08-05 | $0.018 | $0.09 |
| [qwen/qwen3-30b-a3b-instruct-2507](https://openrouter.ai/qwen/qwen3-30b-a3b-instruct-2507) | 2025-07-29 | $0.1 | $0.3 |
| [cohere/command-a-plus](https://openrouter.ai/cohere/command-a-plus) | 2026-09-22 | $0.3 | $1.5 |
| [mistralai/mistral-small-2603](https://openrouter.ai/mistralai/mistral-small-2603) | 2026-03-16 | $0.15 | $0.6 |
| [inclusionai/ling-3.0-flash](https://openrouter.ai/inclusionai/ling-3.0-flash) | 2026-07-23 | $0.021 | $0.063 |
| [openai/gpt-4.1-mini](https://openrouter.ai/openai/gpt-4.1-mini) | 2025-04-14 | $0.4 | $1.6 |

[검증에 사용한 가격·지원 기능 스냅샷](reviews/2026-10-01/text-model-prices.json)을 함께 보관한다. Groq는 [공식 모델 목록](https://console.groq.com/docs/models)의 GPT OSS 120B `$0.15 / $0.60`, 20B `$0.075 / $0.30`을 표시한다.

## 짧은 받아쓰기에 맞춘 요청

문장 정리에서는 불필요한 추론을 줄인다. Solar 4와 GPT-6 Luna는 `none`, Qwen Flash·DeepSeek Flash·MiMo Flash·Ling Flash는 `enabled:false`를 요청한다. 추론을 없애기 어려운 GPT OSS·GLM은 `low`, Gemini Flash Lite는 `minimal`을 요청한다. 추론 응답을 숨기는 `exclude:true` 자체가 비용을 없애지는 않는다. 목록에 없는 사용자 지정 모델에는 이 옵션을 일괄 적용하지 않는다.

Qwen3.7 Flash와 Ling 3.0 Flash는 JSON Object만 지원하므로 해당 형식을 요청하고, 다른 목록 모델은 엄격한 JSON Schema를 요청한다. 앱은 어느 경로든 빈 결과·추가 필드·잘린 응답을 거부한다. 선택한 모델/공급자의 계정 이용 가능 여부는 실제 요청 시 확인된다.

## 비교 방법

`scripts/compare-text-models.py`는 기본적으로 키 없이 dry run한다. `--live`를 명시하면 합성 문장만 OpenRouter에 보낸다. 실제 앱의 `ProviderClient`에서 요청을 캡처하고 같은 파서로 응답을 검증한다. 비교에 한해 출력 상한을 16,384에서 **1,024 토큰**으로 낮추며, 나머지 프롬프트·형식·추론 설정은 앱과 같다. 따라서 긴 발화나 기본 상한에서의 성능을 이 결과로 단정하면 안 된다.

모델당 같은 16개 합성 문장을 사용한다. 한국어·영어 혼합, 브랜드 표기, 한글 유지 예외, 식별자, 부정·조건·숫자·자기수정, 질문·명령·인용을 포함한다. 자동 정규식 검사는 보조 지표이며 의미 정확도가 아니다. 모델 이름을 가린 출력으로 의미 보존·표기 적합·정리 완성도를 별도 검토한다. 실제 사용자 음성 인식 품질은 이 평가에 포함하지 않는다.

각 요청은 자동 재시도 없이 한 번만 보내며, 기본 제한은 30초·동시 4개다. 실행 전에 공개 가격과 보수적인 입력 바이트 상한으로 비용을 예약한다. 가격 스냅샷은 계정 청구 한도를 대신하지 않는다. API 키는 환경변수로만 받고 결과에는 저장하지 않는다.
