# AI 제공자 연결과 검증 상태

구현 설명은 2026-09-10 소스에 맞춰 갱신했다. 아래 모델 목록 조회와 이전 실행 기록은 각각 표시된 날짜의 증거다. HTTPS 요청 경로와 키 없는 계약 테스트의 구현이 실제 API 키 호출, 사용자 녹음 평가, 자연스러운 번역 평가의 완료를 뜻하지는 않는다. 최신 실행 결과는 [검증 상태](verification.md)에서 확인한다.


사용량 수집과 모델별 가격·캐시·재시도 계산은 [사용량과 비용 통계](usage.md)를 참고한다. 통계는 이 앱의 요청 응답에서 수집하며 계정 전체 청구 API를 조회하지 않는다.

## 공개 API

```swift
let defaults = ProviderDefaults.forProvider(.openAI)
let client = ProviderClient(session: .shared)
let transcript = try await client.transcribe(audioURL: fileURL, configuration: configuration, dictionary: dictionary)
let result = try await client.process(request, configuration: configuration)
```

`ProviderDefaults`의 공개 속성은 `transcriptionModel`, `textModel`, `requiresLocalTranscription`이다. `ProviderError`는 콘텐츠와 키를 포함하지 않는 한국어 오류 메시지를 제공한다. Task 취소는 `CancellationError`로 전달한다.

## 기본 모델과 실제 요청 계약

| 선택한 제공자 | 음성 전사 | 텍스트 처리 | 기본 모델 |
| --- | --- | --- | --- |
| OpenAI | `/v1/audio/transcriptions`, multipart 파일 | `/v1/responses`, JSON Schema 출력, `store:false` | `gpt-transcribe` + `gpt-4.1-mini` |
| Groq | `/openai/v1/audio/transcriptions`, multipart 파일 | `/openai/v1/chat/completions`, GPT OSS는 엄격한 JSON Schema, 다른 모델은 JSON Object | `whisper-large-v3-turbo` + `openai/gpt-oss-120b` |
| OpenRouter | `/api/v1/audio/transcriptions`, `input_audio.data` base64 JSON | `/api/v1/chat/completions`, JSON Schema 출력 | `openai/gpt-transcribe` + `openai/gpt-4.1-mini` |
| Claude | 기기 내 전사 결과를 전달해야 함 | `/v1/messages`, 별도 `system`, JSON 결과 검사 | `claude-haiku-4-5-20251001` |

OpenAI·Groq·OpenRouter에는 각 서비스의 사용자 API 키 하나로 두 단계를 요청한다. Claude API 키는 음성 전사 API로 사용하지 않는다. `transcribe`에 Claude 설정을 넘기면 네트워크 요청 전에 `localTranscriptionRequired`를 반환한다.

Groq 설정은 음성 모델 `whisper-large-v3-turbo` / `whisper-large-v3`, 문장 모델 `openai/gpt-oss-120b` / `openai/gpt-oss-20b`를 선택 메뉴로 제공한다. 다른 모델은 직접 입력할 수 있으며, 텍스트 모델은 JSON Object 출력을 지원해야 한다. 이 목록은 2026-09-09 공식 production 모델 중 앱에서 사용하는 종류를 선별한 것이며 계정의 사용 권한을 조회한 결과가 아니다. Llama 3.3 70B는 현재 Enterprise로 표시되어 기본 메뉴에서 제외했다.

Groq GPT OSS 요청은 `reasoning_effort:low`, `include_reasoning:false`를 사용한다. 후자는 추론 내용을 응답에 포함하지 않도록 하는 설정이며 추론 연산이나 청구 자체를 없앤다는 의미는 아니다. Groq Whisper, OpenAI `whisper-1`, 목록에 없는 모델에는 OpenAI 전용 `keywords[]`를 보내지 않고, 전사문 형식의 `prompt`(개인 사전·개발 용어를 쉼표로 나열한 뒤 짧은 한국어 상황 문장 한 줄)만 224토큰 추정치 안에서 전달한다. Whisper 계열은 prompt를 지시문이 아니라 직전 텍스트로 취급하므로 영문 지시문이나 완성 예문은 보내지 않는다. Groq를 선택해도 로컬 음성 인식 토글을 켤 수 있으며, 이때 음성 API 없이 전사 결과만 Groq 문장 모델로 보낸다.

이 앱의 OpenRouter STT 요청은 `input_audio.data`와 `input_audio.format`을 담은 **base64 JSON**이다. OpenRouter 서비스 자체는 25 MB 이하의 OpenAI-style multipart도 지원하므로, 앱의 구현 방식을 서비스의 유일한 계약으로 해석하면 안 된다. 전사 모델은 `/models?output_modalities=transcription`으로 확인한다. 2026-09-09 이 공개 endpoint에서 `openai/gpt-transcribe`, 일반 공개 모델 목록에서 `openai/gpt-4.1-mini`를 확인했다. 키 없이 조회한 목록은 개별 계정의 실제 접근 가능성을 보장하지 않는다. [공식 전사 요청 안내](https://openrouter.ai/blog/tutorials/transcription-on-openrouter/)

OpenRouter는 실제 모델 공급자로 요청을 중개한다. 전사 endpoint에서는 채팅용 `order`, `only`, `allow_fallbacks`, `data_collection`, `sort`가 적용되지 않는다. 따라서 STT 요청에서 무효한 `provider.allow_fallbacks:false`를 제거했으며, 특정 공급자 고정이나 요청별 데이터 정책 적용을 보장하지 않는다. 채팅 요청에는 여전히 `allow_fallbacks:false`와 `require_parameters:true`를 보내지만, 이것도 모든 요청을 항상 같은 공급자로 고정하는 설정은 아니다. 같은 모델이어도 실제 처리 공급자는 달라질 수 있다. [공식 공급자 라우팅 설명](https://openrouter.ai/blog/tutorials/transcription-on-openrouter/#how-does-provider-routing-work-for-transcription)

기본 모델은 설정에서 변경 가능하다. 비운 모델 ID는 기본 모델로 처리하며, 키 입력란을 바꿨다면 Keychain에 저장해야 적용된다. 키의 저장 여부와 실제 연결 성공은 구분한다. OpenAI/OpenRouter 텍스트 모델은 요청하는 JSON Schema 형식을 지원해야 한다. Claude는 JSON을 프롬프트로 요구하고 앱에서 엄격히 검사하므로 다른 모델이 설명·코드 블록을 출력하면 입력하지 않고 오류로 처리한다. 모델 변경 후 품질과 응답 계약을 다시 평가해야 한다.

## 받아쓰기·번역·선택 문장 수정

- 받아쓰기는 말투·의미·원문 언어와 혼합 표기를 보존한다. 추임새·실수로 반복한 말·명확히 번복한 내용만 정리하도록 요청한다. 최종 결론이 없으면 불확실성을 보존한다.
- 번역 목표는 한국어, 영어, 일본어, 중국어 간체·번체다. 한국어↔영어를 우선 평가한다. 모국어 화자의 자연스러운 표현을 지시하지만 실제 품질은 별도 평가 대상이다.
- 선택 문장 수정은 `original_text`, `edit_instruction`, `cursor_context`를 각각 다른 JSON 필드로 보낸다. 사전·문맥·원문을 시스템 지시로 합치지 않는다.
- 선택 문장 수정의 결과는 원래 입력란·텍스트·선택 범위를 반영 직전에 다시 확인한 경우에만 자동 입력한다. 달라졌거나 읽어 확인할 수 없으면 복사할 결과를 보여 준다. 다른 입력란에 수정 결과를 쓰지 않는다.
- 사용자 입력은 JSON으로 직렬화된 데이터다. 프롬프트 내 역할 변경 요청은 따르지 않도록 지시한다. 이 분리만으로 모델의 프롬프트 공격 내성을 검증했다고 주장하지 않는다.
- 커서 문맥은 호출자가 허용한 경우에만 전달하며 마지막 1,000자로 제한한다. 전송 코드가 앱별 동의를 대신 결정하지 않는다.
- OpenAI의 지원 STT 모델에는 범용 견본과 제한된 개인 사전·앱별 용어를 전달한다. `gpt-transcribe`에는 `keywords[]`도 전달하고 다른 모델에는 일괄 적용하지 않는다. 로컬 STT는 같은 견본·용어를 제한된 토큰으로 참고한다. OpenRouter는 현재 전사 후 문장 처리 단계에서 사전·프로필을 적용한다.
- 받아쓰기·번역에는 녹음 시작 시 선택한 앱별 형식과 말투 enum을 전달한다. 앱 이름은 전송하지 않으며 주변 문맥 동의는 별도다. 선택 문장 수정에는 자동 프로필을 적용하지 않는다. [추가 인터뷰 결과와 견본](dictation-baseline.md)을 참고한다.

## 실패·취소·개인정보

- 오디오 파일 25 MB 상한과 확장자, 빈 입력을 전송 전에 확인한다. 지원 녹음 최대 시간은 상위 녹음 정책에서 관리한다.
- 제공자가 보고한 불완전 출력, 토큰 상한 도달, 거절, 빈 문장, 깨진 JSON, 도구 호출은 삽입 결과로 반환하지 않는다.
- STT 응답이 잘림 정보를 주지 않고 정상 `text`만 반환하면 전송 계층만으로 조용한 전사 누락을 검출할 수 없다. 최대 540초 녹음을 포함한 길이별 실제 음성 검증이 필요하다.
- OpenRouter는 전사 upstream 처리 제한을 약 60초로 설명한다. 이는 녹음 길이 60초 제한이 아니며, 앱의 9분 녹음 지원이 모든 모델의 9분 전사 성공을 보장하지 않는다. 현재 앱은 전사 파일을 자동 분할하지 않는다. [공식 전사 제한](https://openrouter.ai/blog/tutorials/transcription-on-openrouter/#what-are-the-limits-to-plan-around)
- HTTP 429/502/503/504만 같은 endpoint로 최대 1회 재시도한다. `Retry-After`가 2초보다 길거나 HTTP 날짜이면 자동 재시도를 하지 않는다. 네트워크 연결 끊김 등 처리 여부가 불명확한 오류는 자동 재전송하지 않는다.
- 재시도도 제공자 정책에 따라 비용이 생길 수 있다. 앱이 선택한 API 서비스 자체를 자동으로 바꾸지는 않는다. OpenRouter 내부 공급자 선택은 위의 STT·채팅 계약을 각각 따른다.
- 실패 녹음의 ‘같은 설정’ 재처리는 저장된 제공자·모델·로컬 여부·필터·번역 언어를 사용한다. ‘현재 설정으로 복구’는 전송 대상과 변경 내용을 확인한 뒤 현재 값을 사용한다. 두 경로의 사전은 현재값, 작성 프로필은 녹음 당시 값이며 원래 만료 시각은 유지한다. 재처리 결과는 복사하도록 표시하고 자동 입력하지 않는다.
- 손쉬운 사용 쓰기가 수락되었거나 전달 여부가 불확실하면 확인 시간이 지나도 자동 붙여넣기를 추가하지 않는다. 이 삽입 정책과 HTTP 재시도는 서로 다른 단계다.
- HTTP 리다이렉트를 거부한다. 키와 콘텐츠가 다른 URL로 따라가지 않는다. HTTP 응답 원문·API 키·녹음·문맥·텍스트를 로그나 오류 메시지에 포함하지 않는다.
- OpenAI `store:false` 및 캐시 억제는 해당 API 응답의 저장 요청을 줄이는 설정이다. 제공자의 운영·보안 보관 정책이나 학습 정책을 대신 보장하지 않는다.
- API 키는 호출자가 사용자 Keychain에서 제공해야 한다. 이 모듈은 다른 앱의 키, 환경 변수, 프로젝트 secret을 탐색하지 않는다.

## 테스트와 미검증 항목

`AIProviderClientTests`는 URLProtocol로 공급자별 실제 요청 계약, 원문/지시 분리, OpenRouter JSON STT, 오류 원문 비노출, 출력 잘림·거절·빈 결과 거부, 재시도 횟수와 취소를 검사한다. 네트워크로 실제 AI 제공자를 호출하지 않는다.

다음 두 문단은 이번 안정성 변경 **이전의 실행 기록**이다. 이번 변경의 통과 수·빌드·화면 검증 상태를 대신하지 않는다.

2026-09-09 Groq 연결과 후속 검토 반영 후 전체 패키지에서 `swift test`: **166개 실행, 1개 건너뜀, 실패 0개**. Groq의 두 Whisper 모델 요청, 두 GPT OSS 모델의 구조화 출력, 직접 입력 모델의 JSON mode, 오류 처리와 재시도, 제공자별 키·설정 보존을 포함한다. 실제 제공자 API 호출이나 음성 품질 검증 결과는 아니다.

같은 날 기존 `TechJuice Local Code Signing` 서명으로 앱을 빌드하고 엄격한 서명 검증을 통과했다. 실행한 앱에서 Groq 선택 시 키 입력란 분리, 음성·문장 모델 메뉴, 직접 입력값의 제공자 전환 후 복원, 로컬 음성 토글 안내를 확인했다. 검증 후 Groq 모델은 기본값으로, 활성 제공자는 기존 OpenAI로 복원했다. Groq 키 저장·실제 요청은 아직 검증하지 않았다.

`AIQualityFixture.cases`는 자기수정, 미결정 상태, 부정·조건, 혼합 문자, 받아쓴 질문·명령, 자연스러운 번역, 선택 문장 수정의 사람이 작성한 기대 사례다. 기대 결과가 있다는 사실을 모델 품질 통과로 표시하면 안 된다. 실제 전사→처리 결과를 기대 사례와 비교하고, 자연스러운 번역은 별도 사람 검토가 필요하다.

음성 등록과 화자 필터는 다른 모듈의 책임이다. 클라우드 STT/API 키만으로 주변 사람·TV·겹말 배제가 제공된다고 표시하지 않는다. 실제 키 호출·개인 음성·TV/타인/겹말·540초 녹음·다른 앱 삽입은 아직 이 모듈의 검증 결과에 포함되지 않는다.

## 확인한 공식 출처

- [OpenAI 파일 전사](https://developers.openai.com/api/docs/guides/speech-to-text)
- [OpenAI GPT-Transcribe 모델](https://developers.openai.com/api/docs/models/gpt-transcribe)
- [OpenAI GPT-4.1 Mini 모델](https://developers.openai.com/api/docs/models/gpt-4.1-mini)
- [OpenAI 텍스트 생성](https://developers.openai.com/api/docs/guides/text)
- [Groq 모델 목록](https://console.groq.com/docs/models)
- [Groq 음성 인식](https://console.groq.com/docs/speech-to-text)
- [Groq 구조화 출력](https://console.groq.com/docs/structured-outputs)
- [Groq 추론 모델](https://console.groq.com/docs/reasoning)
- [OpenRouter 전용 STT 계약](https://openrouter.ai/docs/guides/overview/multimodal/stt)
- [OpenRouter 전사·공급자 라우팅·제한 안내](https://openrouter.ai/blog/tutorials/transcription-on-openrouter/)
- [OpenRouter 전사 모델 공개 API](https://openrouter.ai/api/v1/models?output_modalities=transcription)
- [OpenRouter 텍스트 모델 공개 API](https://openrouter.ai/api/v1/models)
- [Claude Messages API](https://platform.claude.com/docs/en/api/messages/create)
- [Claude 모델 목록](https://platform.claude.com/docs/en/models/overview)

ChatGPT 또는 Claude의 유료 채팅 구독과 직접 API 키 과금은 별도다. 이 앱은 사용자의 API 사용료를 결제하거나 API 크레딧을 제공하지 않는다.
