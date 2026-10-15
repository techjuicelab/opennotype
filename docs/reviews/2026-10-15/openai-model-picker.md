# OpenAI 문장 모델 목록 추가

기준: `118c73b`의 0.2.11 작업 트리. 사용자가 OpenAI 제공자 화면에도 OpenRouter처럼 GPT-6 Luna를 포함한 모델 선택 목록을 요청했다.

## 원인과 구현

기존 `TextModelCatalog.entries(.openAI)`는 비어 있었고 `SettingsView.textConnection`은 Groq/OpenRouter에만 모델 Picker를 표시했다. OpenAI는 자유 입력 필드로만 제공했다. 직접 OpenAI 클라이언트는 이미 Responses API와 strict JSON schema를 사용하며, `gpt-6-luna` ID를 차단하지 않았다. 따라서 모델 자체의 미지원이 아니라 목록·선택 UI 연결의 누락이었다.

- OpenAI에도 기존 `ProviderModelPicker`를 사용한다. 다른 UI 구조는 유지한다.
- 아래 7개 모델을 가격 순으로 표시하고, 직접 입력 경로도 유지한다.
- OpenAI 직접 ID `gpt-6-luna`와 OpenRouter ID `openai/gpt-6-luna`를 구분한다.
- 기본 `gpt-4.1-mini`와 기존 사용자 모델 설정은 자동으로 교체하지 않는다. 제공자·화면 언어 전환에서도 값과 가격을 보존한다.
- Luna의 일반 받아쓰기·수정·프롬프트는 추론 `none`, 번역은 `medium`으로 기존 OpenRouter 정책과 일치시킨다. Responses endpoint, strict schema, `store:false`는 유지한다.
- 신규 OpenAI 모델을 사용량 비용·모델 비교·입력 전 교정 예산 계산에도 연결했다. 입력/출력 단가는 카탈로그를 공유하고 캐시 요율은 공식 값으로 적용한다. GPT-6의 272,000 입력 토큰 초과 요율도 반영한다.
- 확인된 snapshot만 같은 요율로 계산한다. 미확인 모델과 별도 과금 항목(cache write/audio), 잘못된 토큰 내역은 추정하지 않는다. Reasoning 토큰은 출력에 포함되므로 이중 합산하지 않는다.

## 목록과 공식 확인

가격은 2026-10-15 확인한 Standard, 비캐시, 입력 272K 이하 기준 USD/100만 토큰이다. 계정별 접근 권한이나 품질을 보장하는 목록은 아니다.

| 표시 이름 | 직접 OpenAI 모델 ID | 입력 / 출력 |
| --- | --- | --- |
| GPT-6 Luna | `gpt-6-luna` | $0.10 / $0.50 |
| GPT-5.4 Nano | `gpt-5.4-nano` | $0.20 / $1.25 |
| GPT-4.1 Mini · 기본 | `gpt-4.1-mini` | $0.40 / $1.60 |
| GPT-4.1 | `gpt-4.1` | $2.00 / $8.00 |
| GPT-6 Sol | `gpt-6-sol` | $2.00 / $10.00 |
| GPT-6.1 Sol | `gpt-6.1-sol` | $2.00 / $10.00 |
| GPT-6 Astra | `gpt-6-astra` | $10.00 / $50.00 |

GPT-6 Astra와 6.1 Sol은 추론을 끌 수 없다는 안내를 모델 정보에 표시한다. 종료 예정 모델은 공식 종료일도 표시한다: GPT-4.1/full·mini는 2027-01-14, GPT-5.4 Nano는 2027-04-01. 2026-10-23 종료 예정인 GPT-4.1 Nano는 새 목록에 넣지 않았다.

공식 OpenAI 문서를 검색하고 해당 본문을 가져와 확인했다.

- [GPT-6 Luna 모델](https://developers.openai.com/api/docs/models/gpt-6-luna): 직접 ID, Responses·structured outputs, reasoning 범위.
- [공식 가격](https://developers.openai.com/api/docs/pricing): 표준 입력·출력·캐시 단가와 긴 문맥 조건.
- [모델 종료 일정](https://developers.openai.com/api/docs/deprecations): 새 추천 제외와 종료일 안내 근거.
- [GPT-5.4 Nano](https://developers.openai.com/api/docs/models/gpt-5.4-nano): Responses와 strict structured outputs 지원, 기본 reasoning none.

## 검증과 경계

- 하위 에이전트 4개를 활용했다: 직접 API 정책, UI 연결, 공식 모델·가격 확인, 독립 통합 리뷰. 메인 포함 최대 4개가 동시에 실행했다.
- 변경 전 사본: `/private/tmp/opennotype-before-openai-models-20261015T100109`.
- 기존 파일 519개 중 범위 내 10개만 수정했고, 나머지 509개는 바이트 동일하며 누락은 없다. 신규 정책·가격 테스트·본 보고서는 별도 추가했다.
- 관련 필터 77개, 실패 0.
- 전체 `swift test`: Platform 586 + Core 650 = 1,236개, 실패 0, opt-in 모델 통합 생략 2.
- 마지막 지원 종료일 안내 추가 후 카탈로그·언어 전환 회귀 8개, 실패 0.
- `git diff --check` 통과.
- 유료 API, API 키 읽기, 계정별 모델 접근 확인은 수행하지 않았다. 응답·요청 계약은 주입된 HTTP 응답으로 검증했다.
- 실제 앱과 Finder 창 접근이 모두 `cgWindowNotFound`를 반환했다. 실제 Picker 클릭·화면 검증은 수행하지 못했다. 실행 중인 설치 앱 PID 510의 대기 상태를 확인할 수 없어 앱 교체·재실행은 하지 않았다.
- `DEVELOPMENT_SIGNING_IDENTITY="TechJuice Local Code Signing" scripts/build-app.sh` 통과. 결과는 `build/OpenNoType.app`의 로컬 개발 빌드다.
- 최종 앱 경로에서 `codesign --verify --deep --strict --verbose=2` 통과.
- 개발 빌드 실행 파일 SHA-256: `6efe18a9277704f848bd384e392f6bb9eb59ada6891a8c6174a308aabfbb6f7f`.
- 설치된 실행 파일은 기존 SHA-256 `d3aa84165e1de864ca5fff29b240e531549a73998fa804fdc4951e9f285e93f8` 그대로다. 공개 릴리스, 버전 증가, 커밋·푸시는 수행하지 않았다.

로그:

- `/private/tmp/opennotype-openai-models-focused.log`
- `/private/tmp/opennotype-openai-models-swift-final.log`
- `/private/tmp/opennotype-openai-models-metadata-final.log`
- `/private/tmp/opennotype-openai-models-build.log`
