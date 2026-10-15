# 모델 선택 통일: 카탈로그와 지원 경계

조사·구현 기준일: 2026-10-15. 이 문서는 모델 목록·공식 가격·선택 지원 범위를 설명한다. 설치·공개·다운로드 완료 근거는 [0.2.12 검증 보고서](release-0.2.12.md)에서 구분해 확인한다.

## 기존 작업 보존

다른 에이전트가 먼저 추가한 OpenAI 문장 모델 7개, `OpenAITextPolicy`, 요청·회귀 테스트와 사용량 계산 변경을 출발점으로 삼았다. OpenAI 목록과 기본값을 덮어쓰지 않았다. Groq와 OpenRouter의 기존 문장 목록·가격 snapshot·확인일도 유지했다. 기본 모델 변경, API 키 조회, 유료 API 요청은 수행하지 않았다.

## 온라인 음성 모델

[SpeechModelCatalog.swift](https://github.com/techjuicelab/opennotype/blob/v0.2.12/Sources/OpenNoTypeCore/AI/SpeechModelCatalog.swift#L5)는 `id`, `title`, `note`, `sourceURL`, `asOf`를 제공한다. 음성 요금의 시간·오디오 토큰 단위가 서로 달라 문장 토큰 가격 타입을 재사용하지 않는다. 각 제공자에서 기존 기본값을 첫 항목으로 유지하며, UI의 Custom 입력은 목록 외 ID를 위한 별도 경로다.

| 제공자 | 카탈로그 ID | 기존 기본값 |
| --- | --- | --- |
| OpenAI | `gpt-transcribe`, `gpt-4o-mini-transcribe`, `gpt-4o-transcribe`, `whisper-1` | `gpt-transcribe` |
| Groq | `whisper-large-v3-turbo`, `whisper-large-v3` | `whisper-large-v3-turbo` |
| OpenRouter | `openai/gpt-transcribe`, `openai/gpt-4o-mini-transcribe`, `openai/gpt-4o-transcribe`, `openai/whisper-1`, `openai/whisper-large-v3`, `openai/whisper-large-v3-turbo` | `openai/gpt-transcribe` |
| Claude | 온라인 음성 목록 없음. 기존 로컬 전사 경로 사용 | 로컬 강제 |

근거: [OpenAI 파일 전사](https://developers.openai.com/api/docs/guides/speech-to-text), [Groq STT](https://console.groq.com/docs/speech-to-text), [OpenRouter STT](https://openrouter.ai/docs/guides/overview/multimodal/stt). OpenRouter ID는 [공식 STT 모델 조회 API](https://openrouter.ai/api/v1/models?output_modalities=transcription)의 무인증 응답에서 확인했다. 일반 `/models` 응답과 STT 목록은 별개다. 목록에 있다는 사실이 계정별 접근이나 한영 혼용 품질을 보장하지 않는다.

OpenAI의 `whisper-1`, `gpt-4o-transcribe`, `gpt-4o-mini-transcribe`는 [2027-02-26 종료 예정](https://developers.openai.com/api/docs/deprecations)이므로 모델 정보에 표시한다. 이 직접 API 일정이 OpenRouter의 제공 일정과 같다고 단정하지 않으며 경로별 확인을 안내한다. `gpt-4o-transcribe-diarize`와 Realtime 전용 모델은 기존 파일 전사 요청과 요구 조건이 달라 목록에 넣지 않는다.

## 문장·보조 모델

[TextModelCatalog.swift](https://github.com/techjuicelab/opennotype/blob/v0.2.12/Sources/OpenNoTypeCore/AI/TextModelCatalog.swift#L41)는 4개 제공자의 공통 목록을 제공한다. 문장 처리와 보조 모델 UI가 이를 함께 사용한다. OpenAI 7개, Groq 2개, OpenRouter 20개 기존 항목을 유지하고 Claude 7개를 추가했다. 목록은 동일 입력·출력 토큰 수를 가정한 참고 단가 합계 순이며, 사용자가 저장한 모델이나 기본 모델을 자동 교체하지 않는다.

Claude 가격은 Standard·Global routing·비캐시 입력과 출력의 USD/100만 토큰 기준이다. 캐시 읽기는 실제 사용량 추정에 별도로 적용한다.

| 직접 API 모델 ID | 입력 | 출력 | 캐시 읽기 | 조건 |
| --- | ---: | ---: | ---: | --- |
| `claude-haiku-4-5-20251001` | 1.00 | 5.00 | 0.10 | 기존 기본값, 사용 가능한 이전 세대 |
| `claude-sonnet-4-6` | 3.00 | 15.00 | 0.30 | 사용 가능한 이전 세대 |
| `claude-opus-4-6` | 5.00 | 25.00 | 0.50 | 사용 가능한 이전 세대 |
| `claude-haiku-5-5` | 0.10 | 0.50 | 0.01 | 전체 입력 100,000토큰 이하 |
| `claude-haiku-5-5` | 0.50 | 2.50 | 0.05 | 전체 입력 100,000토큰 초과 |
| `claude-sonnet-5-5` | 2.00 | 10.00 | 0.10 | 기본 적응형 추론 |
| `claude-opus-5-5` | 4.00 | 20.00 | 0.20 | 추론 항상 사용 |
| `claude-fable-5-1` | 10.00 | 50.00 | 0.25 | 추론 항상 사용 |

공식 근거: [전체 가격·긴 문맥 조건](https://platform.claude.com/docs/en/about-claude/pricing), [Haiku 4.5 ID](https://platform.claude.com/docs/en/models/haiku-4-5/overview), [Sonnet 4.6](https://platform.claude.com/docs/en/models/sonnet-4-6/overview), [Opus 4.6](https://platform.claude.com/docs/en/models/opus-4-6/overview), [Haiku 5.5](https://platform.claude.com/docs/en/models/haiku-5-5/overview), [Sonnet 5.5](https://platform.claude.com/docs/en/models/sonnet-5-5/overview), [Opus 5.5](https://platform.claude.com/docs/en/models/opus-5-5/overview), [Fable 5.1](https://platform.claude.com/docs/en/models/fable-5-1/overview). 확인일은 각 가격에 `2026-10-15`로 저장한다.

[UsagePricing.swift](https://github.com/techjuicelab/opennotype/blob/v0.2.12/Sources/OpenNoTypeCore/Usage/UsagePricing.swift#L114)는 같은 문장 카탈로그의 입력·출력 가격을 사용해 모델 비교 예약과 실제 사용량 추정의 알려진 모델 범위를 일치시킨다. Claude `input_tokens`에는 캐시 읽기가 빠져 있으므로 두 수를 더해 비용을 계산하며, Haiku 5.5의 100K 경계도 합계로 판정한다. 경계를 넘으면 해당 요청 전체에 높은 입력·출력·캐시 읽기 요율을 적용한다. 추론 토큰은 출력에 이미 포함되어 이중 합산하지 않는다.

캐시 쓰기는 5분·1시간 가격이 서로 다르지만 현재 사용량 기록은 그 기간을 구분하지 않는다. 따라서 캐시 쓰기가 있는 요청은 기존대로 비용 미확인으로 남긴다. 알 수 없는 모델·미확인 snapshot·잘못된 토큰·실패 요청도 무료로 추정하지 않는다. 기존 Haiku 4.5 별칭과 Sonnet 4.5 요율 지원은 보존한다. 실제 공급자 보고 금액의 우선순위와 OpenRouter 무보고 비용의 미확인 정책도 유지한다.

새 Claude 모델은 추론으로 시간·비용이 늘 수 있다는 note를 제공한다. 요청·추론 정책과 응답 파서는 변경하지 않았다. 현재 파서는 `thinking` 블록을 제외하고 최종 `text`를 읽지만, 이것이 실제 한국어 품질이나 속도 검증을 대신하지 않는다. [공식 Haiku 5.5 이전 안내](https://platform.claude.com/docs/en/models/haiku-5-5/migration-guide)

## Jev·로컬 모델의 Custom 예외

Jev는 일반 문장 생성 모델이 아닌 typed decisions 서비스다. 현재 [DecisionProvider](https://github.com/techjuicelab/opennotype/blob/v0.2.12/Sources/OpenNoTypeCore/AI/DecisionModels.swift#L12)가 OpenRouter `typesafe/jev-1.13`, 직접 API `jev-1.13.0`을 고정하며, [DecisionConfiguration](https://github.com/techjuicelab/opennotype/blob/v0.2.12/Sources/OpenNoTypeCore/AI/DecisionModels.swift#L24)에는 모델 저장필드가 없다. [요청 생성](https://github.com/techjuicelab/opennotype/blob/v0.2.12/Sources/OpenNoTypeCore/AI/DecisionClient.swift#L417), [응답 모델 확인](https://github.com/techjuicelab/opennotype/blob/v0.2.12/Sources/OpenNoTypeCore/AI/DecisionClient.swift#L596), 직접 서비스 비용 계산도 이 고정 계약을 사용한다. 이 화면에 임의 Custom 입력만 붙이면 해당 값이 요청에 반영되지 않거나 검증·회계 계약과 어긋난다.

공식적으로 OpenRouter는 `~typesafe/jev-latest`, 직접 API는 `jev-latest`·`jev-preview` 별칭도 제공한다. 이를 지원하려면 저장·요청·응답 모델·버전·가격 검증을 함께 확장해야 한다. 이번에는 고정 ID와 사유를 표시하며 일반 문장 모델을 Jev 대체 모델로 제안하지 않는다. [OpenRouter 공식 Jev 안내](https://openrouter.ai/docs/guides/community/jev), [직접 API 공식 참조](https://typesafe-jev.com/en/guides/api/)

로컬 음성도 [세 개 enum](https://github.com/techjuicelab/opennotype/blob/v0.2.12/Sources/OpenNoTypeCore/LocalAudio/LocalTranscriber.swift#L23)에 모델 variant와 다운로드 크기가 묶이며 [토크나이저·캐시 삭제 경로](https://github.com/techjuicelab/opennotype/blob/v0.2.12/Sources/OpenNoTypeCore/LocalAudio/LocalModelPolicy.swift#L55)가 모델별로 정해져 있다. 임의 ID는 기존 다운로드·준비·삭제 계약을 통과할 수 없다. 기존 목록을 유지하고 Custom 미지원 사유를 도움말에서 설명한다.

## 검증 범위

- `SpeechModelCatalogTests`: 제공자별 정확한 ID·중복 방지·default-first·출처·직접/라우터 종료일 구분·지원하지 않는 Realtime/diarize 제외를 검증한다.
- `AnthropicModelCatalogTests`: Claude 7개·기존 pinned 기본값·가격 출처·확인일·가격 순서·100K/추론 주의 metadata를 검증한다.
- `AnthropicUsagePricingTests`: 7개 실제 요율과 UI 가격 정합·캐시 읽기 별도 합산·100K 경계 전후·요청 전체의 고요율 적용·미확인 보호·모델 비교/교정 예약 경로를 검증한다.
- 기존 `TextModelCatalogTests`의 Claude 빈 목록 assert 하나를 새 기본 Claude 포함 검증으로 갱신했다. 앞서 추가된 OpenAI 검증은 유지했다.
- 이 담당 범위에서는 구문·diff 검사를 수행하며, Swift 통합 테스트는 메인이 실행한다. 유료 API·키 접근·실제 음성 정확도·계정별 모델 접근 검증은 수행하지 않았다.

OpenRouter 일부 공개 가격이 기존 snapshot과 달라진 사실을 조사에서 확인했지만, 이번 작업에서 일괄 최신화하지 않았다. 가격은 각 항목의 확인일과 출처를 함께 읽어야 한다.
