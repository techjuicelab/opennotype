# 로컬 음성 엔진

## 제공하는 경로

`LocalTranscriber`는 WhisperKit의 공개 Core ML Whisper 모델을 내려받아 기기 안에서 음성을 텍스트로 바꾼다. Claude API 키만 사용하는 사용자는 설정의 모델 준비 버튼을 먼저 눌러 이 경로를 사용한다. 앱이 음성을 WhisperKit/Argmax/Hugging Face 서버로 전송하지는 않는다. 최초 모델·토크나이저 다운로드에는 인터넷이 필요하며, 선택한 Claude 제공자에는 이후 텍스트 처리 요청이 전달된다.

기본 모델은 multilingual `openai_whisper-large-v3-v20240930_626MB`이다. `task: .transcribe`, 자동 언어 감지로 설정해 영어 번역 모드를 사용하지 않는다. 개인 사전의 최종 표기는 최근 등록·교정한 항목부터 최대 24개·총 384자로 선별하고, 개발 프로필의 참고 용어 및 공통 견본과 함께 최대 192토큰의 인식 힌트로 전달한다. 각 표기는 80자 이내여야 한다. STT 전에는 전사문이 없어 관련도를 판단할 수 없다. 사전에 저장한 모든 항목을 매번 보내지는 않으며 이 예산을 넘으면 뒤쪽 힌트는 제외된다. 이후 텍스트 처리에는 현재 전사문에 등장하는 항목, 허용한 주변 문맥에 등장하는 항목, 최근 등록·교정한 항목 순으로 최대 200개를 선별한다. 힌트는 강제 문자열 치환이 아니며 한영 혼용·고유명사 보존 정확도는 실제 발화로 별도 평가해야 한다.

| 선택 | 모델 파일 크기 | 성격 |
|---|---:|---|
| Large v3 (기본) | 626,718,238 bytes | 다국어 모델, 한국어 우선 기본값 |
| Small | 486,487,465 bytes | 다국어, 더 작은 모델 |
| Base | 146,719,453 bytes | 다국어, 가장 작은 제공 선택지 |

위 크기는 2026-09-09 Hugging Face 공식 파일 목록 합계이다. 토크나이저와 Core ML 기기별 캐시는 추가 공간을 사용한다. 모델은 앱 설치 파일에 포함하지 않는다. 영어 전용 `.en` 모델과는 다르다. 초기 Core ML 준비는 다운로드가 완료된 후에도 시간이 걸릴 수 있다.

```swift
let transcriber = LocalTranscriber()
try await transcriber.prepare { state in
    // Callback may arrive off the main actor; dispatch UI updates to MainActor.
}
let text = try await transcriber.transcribe(audioURL: recordingURL, dictionary: entries)
```

`prepare` 전의 변환은 명시적 오류다. 최대 녹음은 540초이며 입력은 내부적으로 mono 16 kHz PCM으로 변환한다. 사용자가 모델을 준비하는 명시적 동작 없이 수백 MB를 자동 다운로드하지 않는다.

## 목소리 등록과 실험 화자 필터

`LocalSpeakerRecognizer`는 FluidAudio의 Pyannote segmentation과 WeSpeaker v2 신경망을 사용한다. 단순 음량·주파수 통계를 사용자의 목소리 특징으로 표시하지 않는다. 임베딩은 L2 정규화한 256차원 벡터다.

```swift
let recognizer = LocalSpeakerRecognizer(profileStore: encryptedStore)
try await recognizer.prepare()
let profile = try await recognizer.enroll(consumingRecordingAt: disposableEnrollmentURL)
let filtered = try await recognizer.filter(audioURL: recordingURL)
let text = try await transcriber.transcribe(samples: filtered.samples, dictionary: entries)
```

등록에는 본인만 말하는 5~30초의 별도 녹음을 사용한다. 음성 구간이 4초 미만이거나 복수 화자로 분류되면 등록을 거절한다. 최대 세 개의 10초 창에서 추출한 임베딩을 평균·정규화한다. `consumingRecordingAt`은 성공·실패 모두 원본 파일을 삭제하는 API이므로 보존해야 하는 개인 파일을 직접 넘기면 안 된다. 원본 삭제 실패는 명시적 오류이며, 삭제 완료 후에만 새 프로필을 저장한다.

`SpeakerProfileStoring`은 앱의 암호화 저장소가 구현한다. 저장 대상은 프로필 ID·이름·등록일·모델 식별자·임베딩뿐이다. 원음은 프로필에 포함하지 않는다. 사용자 삭제는 `deleteProfile()`이다. 임베딩도 민감한 생체 특징으로 취급해야 한다.

필터는 화자 구간의 임베딩과 등록 벡터의 cosine similarity가 0.65 이상인 구간만 남긴다. 다른 화자로 분류된 구간과 겹치면 **그 후보 구간 전체를 제외**한다. 이 값은 아직 실제 사용자 데이터에 맞춰 보정한 임계값이 아니다. 구간 사이에는 최대 0.2초 무음을 삽입하되 원래 간격보다 길게 만들지 않는다. 필터 결과는 메모리에 반환하며 기본 원본 녹음의 삭제·실패 보관은 상위 녹음 파이프라인이 담당한다.

### 검증 전부터 반드시 표시할 한계

- **실험 기능이다.** 등록 성공이나 임베딩 생성 성공은 타인·TV 배제 품질 검증 완료를 뜻하지 않는다.
- 화자 구분은 `누가 언제 말했는가`에 대한 추정이며, 동시에 들리는 음원을 분리하는 기능이 아니다.
- 겹침이 감지되지 않거나 한 화자로 잘못 합쳐지면 다른 사람의 음성이 남을 수 있다. 반대로 내 말도 버려질 수 있다.
- 짧은 발화, 마이크 변경, 잔향, TV 재생, 비슷한 목소리, 녹음된 본인 음성에 대한 한계를 실측해야 한다. 인증·보안 접근 제어 용도가 아니다.
- 필터가 일치 구간을 찾지 못하면 오류를 반환한다. 조용히 원본 전체를 받아쓰는 방식으로 성공을 가장하지 않는다.

## 의존성과 라이선스

| 구성 요소 | 버전/출처 | 라이선스 |
|---|---|---|
| WhisperKit SDK | [Argmax WhisperKit 1.1.0](https://github.com/argmaxinc/WhisperKit/tree/v1.1.0) | [MIT](https://github.com/argmaxinc/WhisperKit/blob/v1.1.0/LICENSE) |
| Core ML Whisper 모델 | [argmaxinc/whisperkit-coreml](https://huggingface.co/argmaxinc/whisperkit-coreml) | 모델 카드 MIT |
| FluidAudio SDK | [FluidInference/FluidAudio 0.12.6](https://github.com/FluidInference/FluidAudio/tree/v0.12.6) | [Apache-2.0](https://github.com/FluidInference/FluidAudio/blob/v0.12.6/LICENSE) |
| 화자 모델 변환 | [FluidInference/speaker-diarization-coreml](https://huggingface.co/FluidInference/speaker-diarization-coreml) | 모델 카드 CC-BY-4.0, 별도 귀속 표시 필요 |

화자 모델 크기는 `pyannote_segmentation.mlmodelc` 5,766,532 bytes + `wespeaker_v2.mlmodelc` 7,954,144 bytes, 합계 약 14 MB다. 변환 모델의 출처는 FluidInference이며, 기반 화자 segmentation 저자는 Alexis Plaquet와 Hervé Bredin, WeSpeaker 연구 저자는 Hongji Wang 등이다. SDK가 Apache-2.0라는 이유로 모델도 동일 라이선스로 표시하면 안 된다. 본 앱의 MIT 라이선스가 외부 코드·모델의 라이선스를 대체하지 않는다.

Swift 6.3 도구 모음에서 FluidAudio 0.12.4는 `StreamingAsrManager`가 비동기 함수에 non-Sendable `AsrManager`를 전달하는 컴파일 오류를 낸다. 공식 0.12.6의 actor 변경을 사용한다. 이 버전이 요구하는 swift-transformers 1.2와 WhisperKit 0.18의 <1.2 제한이 충돌하므로, swift-transformers 의존성이 제거된 WhisperKit 1.x와 조합한다.

WhisperKit 1.0.0은 사전 `promptTokens`가 있는 음성 변환이 빈 결과로 끝나는 오류를 실제 합성 음성으로 재현했다. 입력 제어 토큰을 제외해도 해결되지 않았으며, 프롬프트를 강제 입력하는 중간 단계의 임시 종료 토큰 예측을 진짜 종료로 처리하는 SDK 버그였다. [공식 PR #514](https://github.com/argmaxinc/argmax-oss-swift/pull/514)의 수정이 포함된 **1.1.0**을 고정한다. `.build/checkouts` 수정이나 전역 동시성 검사 해제에 의존하지 않는다.

SDK 버전은 고정하지만 모델 다운로드는 공급자의 현재 공개 저장소에서 이루어진다. 현재 구현은 모델 revision/hash 고정 기능까지 제공하지 않는다. 공개 배포 전 모델 고정·무결성 검증과 모델 라이선스 고지 UI를 검토해야 한다.

## 검증

모델 없이 실행되는 정책 테스트:

```sh
swift test --filter LocalAudioTests
```

약 627 MB 다운로드와 실제 Core ML 인식을 실행하는 명시적 통합 테스트:

```sh
OPENNOTYPE_RUN_LOCAL_AUDIO_INTEGRATION=1 swift test --filter LocalAudioTests/testOptInLocalTranscriptionIntegration
```

통합 테스트는 macOS `say`의 Yuna·Samantha 합성 음성을 임시 파일로 만들고 변환 뒤 삭제한다. 출력은 합성 입력·결과를 함께 기록한다. 이것은 다운로드·모델 로드·STT 연결 검증이며 사용자 자연발화 정확도, 문장 내 한영 혼용 보존, TV·타인·겹말 배제 검증을 대체하지 않는다.

UI 빌드와 독립적으로 합성 음성을 검증하는 도구도 제공한다:

```sh
swift run LocalAudioBench --transcription
swift run LocalAudioBench --speakers
```

### 2026-09-09 실제 실행 결과

환경: Apple M2 Max / RAM 32 GB / macOS 26.6.2 / Swift 6.3.3. 최종 STT 실행은 WhisperKit 1.1.0, 사전 `API` 힌트를 포함한 `LocalTranscriber` 공개 API를 그대로 사용했다.

| 합성 입력 | 실제 출력 | 변환 시간 |
|---|---|---:|
| Yuna: 내일 오후 세 시에 회의가 있습니다. 회의 자료를 미리 준비해 주세요. | 내일 오후 3시에 회의가 있습니다. 회의 자료를 미리 준비해 주세요. | 1.201초 |
| Samantha: Please update the weather API and send the report tomorrow afternoon. | Please update the weather API and send the report tomorrow afternoon. | 1.032초 |

최종 실행의 모델 준비는 **71.636초**였다. 가중치가 이미 저장돼 있어도 Core ML 준비에 시간이 걸렸다. 위 변환 시간에 최초 다운로드와 준비 시간은 포함하지 않았다. 준비 완료 상태에서 짧은 합성 음성을 변환한 두 사례이며, 모든 Mac에서 같은 속도를 보장하지 않는다.

화자 엔진은 모델 약14 MB를 실제로 다운로드·로드했다. Samantha 합성 음성으로 256차원 임베딩을 만들었으며 등록 원본 삭제를 확인했다. 별도로 생성한 Samantha 발화 7.418625초는 채택했고, Daniel 발화는 `noMatchingSpeaker`로 거절했다. 이후 프로필 삭제도 확인했다. 테스트 저장소는 메모리를 사용했으므로 이 실험을 앱의 암호화 저장소 검증으로 혼동하면 안 된다.

정책 테스트에서는 사전 힌트의 길이·한영 표기, 제어 토큰 제한, 등록 실패 시 원본 삭제, 화자 불일치·겹침 제외, 중복 구간 병합, 비정상 임베딩 거절, 모델 미준비 오류를 확인한다. 모델 통합 테스트는 기본 실행에서 명시적으로 건너뛰며 위 벤치 명령으로 별도 실증했다.

**미검증:** 사용자 실제 음성, 한 문장 안의 자연스러운 한영 혼용, TV 발화, 실제 겹말, 마이크 전환·잔향·소음 환경, 9분 녹음 정확도와 처리 시간. 실제 겹말 제외를 검증한 것이 아니라 겹치는 구간이 입력된 경우 제외하는 정책을 단위 테스트한 것이다.
