# AI 제공자 연결과 검증 상태

2026-09-09 기준. 직접 HTTPS 요청 경로와 키 없는 네트워크 계약 테스트를 구현했다. 실제 API 키 호출, 사용자 녹음 평가, 자연스러운 번역 평가를 완료했다는 뜻은 아니다.

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
| OpenRouter | `/api/v1/audio/transcriptions`, `input_audio.data` base64 JSON | `/api/v1/chat/completions`, JSON Schema 출력 | `openai/gpt-transcribe` + `openai/gpt-4.1-mini` |
| Claude | 기기 내 전사 결과를 전달해야 함 | `/v1/messages`, 별도 `system`, JSON 결과 검사 | `claude-haiku-4-5-20251001` |

OpenAI와 OpenRouter에는 각 서비스의 사용자 API 키 하나로 두 단계를 요청한다. Claude API 키는 음성 전사 API로 사용하지 않는다. `transcribe`에 Claude 설정을 넘기면 네트워크 요청 전에 `localTranscriptionRequired`를 반환한다.

OpenRouter STT는 OpenAI STT와 endpoint 이름이 비슷하지만 **multipart 계약이 아니다**. 전사 모델 목록은 일반 `/models` 응답과 분리될 수 있으므로 `/models?output_modalities=transcription`으로 확인한다. 2026-09-09 이 공개 endpoint에서 `openai/gpt-transcribe`를 확인했고, 일반 공개 모델 목록에서 `openai/gpt-4.1-mini`를 확인했다. 키 없이 조회한 목록은 개별 사용자 계정의 실제 접근 가능성을 보장하지 않는다.

기본 모델은 설정에서 변경 가능하다. OpenAI/OpenRouter 텍스트 모델은 요청하는 JSON Schema 형식을 지원해야 한다. Claude는 JSON을 프롬프트로 요구하고 앱에서 엄격히 검사하므로 다른 모델이 설명·코드 블록을 출력하면 입력하지 않고 오류로 처리한다. 모델 변경 후 품질과 응답 계약을 다시 평가해야 한다.

## 받아쓰기·번역·선택 문장 수정

- 받아쓰기는 말투·의미·원문 언어와 혼합 표기를 보존한다. 추임새·실수로 반복한 말·명확히 번복한 내용만 정리하도록 요청한다. 최종 결론이 없으면 불확실성을 보존한다.
- 번역 목표는 한국어, 영어, 일본어, 중국어 간체·번체다. 한국어↔영어를 우선 평가한다. 모국어 화자의 자연스러운 표현을 지시하지만 실제 품질은 별도 평가 대상이다.
- 선택 문장 수정은 `original_text`, `edit_instruction`, `cursor_context`를 각각 다른 JSON 필드로 보낸다. 사전·문맥·원문을 시스템 지시로 합치지 않는다.
- 사용자 입력은 JSON으로 직렬화된 데이터다. 프롬프트 내 역할 변경 요청은 따르지 않도록 지시한다. 이 분리만으로 모델의 프롬프트 공격 내성을 검증했다고 주장하지 않는다.
- 커서 문맥은 호출자가 허용한 경우에만 전달하며 마지막 1,000자로 제한한다. 전송 코드가 앱별 동의를 대신 결정하지 않는다.
- OpenAI의 지원 STT 모델에는 범용 견본과 제한된 개인 사전·앱별 용어를 전달한다. `gpt-transcribe`에는 `keywords[]`도 전달하고 다른 모델에는 일괄 적용하지 않는다. 로컬 STT는 같은 견본·용어를 제한된 토큰으로 참고한다. OpenRouter는 현재 전사 후 문장 처리 단계에서 사전·프로필을 적용한다.
- 받아쓰기·번역에는 녹음 시작 시 선택한 앱별 형식과 말투 enum을 전달한다. 앱 이름은 전송하지 않으며 주변 문맥 동의는 별도다. 선택 문장 수정에는 자동 프로필을 적용하지 않는다. [추가 인터뷰 결과와 견본](dictation-baseline.md)을 참고한다.

## 실패·취소·개인정보

- 오디오 파일 25 MB 상한과 확장자, 빈 입력을 전송 전에 확인한다. 지원 녹음 최대 시간은 상위 녹음 정책에서 관리한다.
- 제공자가 보고한 불완전 출력, 토큰 상한 도달, 거절, 빈 문장, 깨진 JSON, 도구 호출은 삽입 결과로 반환하지 않는다.
- STT 응답이 잘림 정보를 주지 않고 정상 `text`만 반환하면 전송 계층만으로 조용한 전사 누락을 검출할 수 없다. 최대 540초 녹음을 포함한 길이별 실제 음성 검증이 필요하다.
- HTTP 429/502/503/504만 같은 endpoint로 최대 1회 재시도한다. `Retry-After`가 2초보다 길거나 HTTP 날짜이면 자동 재시도를 하지 않는다. 네트워크 연결 끊김 등 처리 여부가 불명확한 오류는 자동 재전송하지 않는다.
- 재시도도 제공자 정책에 따라 비용이 생길 수 있다. 앱에서 다른 AI 제공자로 자동 변경하지 않으며 OpenRouter에도 `allow_fallbacks:false`를 전달한다.
- HTTP 리다이렉트를 거부한다. 키와 콘텐츠가 다른 URL로 따라가지 않는다. HTTP 응답 원문·API 키·녹음·문맥·텍스트를 로그나 오류 메시지에 포함하지 않는다.
- OpenAI `store:false` 및 캐시 억제는 해당 API 응답의 저장 요청을 줄이는 설정이다. 제공자의 운영·보안 보관 정책이나 학습 정책을 대신 보장하지 않는다.
- API 키는 호출자가 사용자 Keychain에서 제공해야 한다. 이 모듈은 다른 앱의 키, 환경 변수, 프로젝트 secret을 탐색하지 않는다.

## 테스트와 미검증 항목

`AIProviderClientTests`는 URLProtocol로 공급자별 실제 요청 계약, 원문/지시 분리, OpenRouter JSON STT, 오류 원문 비노출, 출력 잘림·거절·빈 결과 거부, 재시도 횟수와 취소를 검사한다. 네트워크로 실제 AI 제공자를 호출하지 않는다.

2026-09-09 `Models.swift`와 AI 소스·AI 테스트만 분리한 임시 Swift 패키지에서 `swift test --filter AI`: **16개 테스트 통과**. 이 결과는 전체 앱 의존성 빌드·실행 검증을 대신하지 않는다.

`AIQualityFixture.cases`는 자기수정, 미결정 상태, 부정·조건, 혼합 문자, 받아쓴 질문·명령, 자연스러운 번역, 선택 문장 수정의 사람이 작성한 기대 사례다. 기대 결과가 있다는 사실을 모델 품질 통과로 표시하면 안 된다. 실제 전사→처리 결과를 기대 사례와 비교하고, 자연스러운 번역은 별도 사람 검토가 필요하다.

음성 등록과 화자 필터는 다른 모듈의 책임이다. 클라우드 STT/API 키만으로 주변 사람·TV·겹말 배제가 제공된다고 표시하지 않는다. 실제 키 호출·개인 음성·TV/타인/겹말·540초 녹음·다른 앱 삽입은 아직 이 모듈의 검증 결과에 포함되지 않는다.

## 확인한 공식 출처

- [OpenAI 파일 전사](https://developers.openai.com/api/docs/guides/speech-to-text)
- [OpenAI GPT-Transcribe 모델](https://developers.openai.com/api/docs/models/gpt-transcribe)
- [OpenAI GPT-4.1 Mini 모델](https://developers.openai.com/api/docs/models/gpt-4.1-mini)
- [OpenAI 텍스트 생성](https://developers.openai.com/api/docs/guides/text)
- [OpenRouter 전용 STT 계약](https://openrouter.ai/docs/guides/overview/multimodal/stt)
- [OpenRouter 전사 모델 공개 API](https://openrouter.ai/api/v1/models?output_modalities=transcription)
- [OpenRouter 텍스트 모델 공개 API](https://openrouter.ai/api/v1/models)
- [Claude Messages API](https://platform.claude.com/docs/en/api/messages/create)
- [Claude 모델 목록](https://platform.claude.com/docs/en/models/overview)

ChatGPT 또는 Claude의 유료 채팅 구독과 직접 API 키 과금은 별도다. 이 앱은 사용자의 API 사용료를 결제하거나 API 크레딧을 제공하지 않는다.
