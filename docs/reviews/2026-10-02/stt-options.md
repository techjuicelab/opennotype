# 한국어·영어 받아쓰기 STT 후보 조사

공식 자료 확인일: **2026-10-02 미국 동부 시간**. 사용자는 현재 **Groq Whisper Large v3 Turbo**를 유지하기로 했다. 이번 조사는 실제 사용자 녹음의 API 비교·모델 다운로드·추가 제공자 구현을 하지 않았다.

## 현재 선택과 비교 후보

| 후보 | 정규 단가 | 단순 10시간 비용 | 현재 앱에서 사용 |
|---|---:|---:|---|
| Groq Whisper Large v3 Turbo | $0.04/시간 | $0.40 | 현재 설정 |
| Groq Whisper Large v3 | $0.111/시간 | $1.11 | 같은 Groq 키로 선택 가능 |
| WhisperKit 로컬 | API 이용료 없음 | API 비용 $0 | 별도 모델 다운로드 필요 |
| Voxtral Mini Transcribe 2 | $0.003/분 | $1.80 | 새 제공자 연결 필요 |
| Qwen-Audio-3.1-ASR-Flash | 입력 $0.15 / 출력 $0.47, 100만 토큰당 | 음성 길이의 토큰 환산 미확인 | 새 제공자 연결 필요 |

10시간 비용은 단가의 단순 환산이며 무료 크레딧·Batch 할인·요청별 최소 청구 길이·추가 기능 비용은 포함하지 않는다. Groq는 요청마다 최소 10초를 청구하므로 짧은 받아쓰기를 많이 하면 실제 녹음 길이 합계와 청구 길이가 다르다. [Groq 공식 STT 문서](https://console.groq.com/docs/speech-to-text)

이번에 확인한 클라우드 후보 중 Groq Turbo보다 확실히 저렴하고 한국어·영어 혼합 정확도가 더 좋다고 검증된 모델은 없다. 다른 모델이 이 사용자의 고유명사를 더 잘 듣는지는 같은 녹음으로 확인해야 한다.

## 후보별 판단

**Groq full Large v3**는 연결을 추가하지 않고 비교할 첫 후보다. Groq 문서는 정확도가 중요한 다국어 작업에 full v3를 권한다. 그러나 이 사용자의 `JEV`·`OpenNoType` 발음에서 Turbo보다 낫다는 실제 결과는 아직 없다. [공식 모델 선택 안내](https://console.groq.com/docs/speech-to-text)

**로컬 WhisperKit**은 API 비용을 없애는 선택이다. 현재 앱은 한영 자동 인식과 사전 힌트를 제공하지만 모델 다운로드·저장 공간·Mac 연산이 필요하다. 현재 기본 다운로드 ID `openai_whisper-large-v3-v20240930_626MB`는 압축한 **Turbo** 모델이며 full v3로 해석하면 안 된다. 실행 속도·배터리·실제 발음 정확도는 이번에 측정하지 않았다. [Argmax 공식 구현](https://github.com/argmaxinc/argmax-oss-swift), [공식 Turbo 모델 설정](https://huggingface.co/argmaxinc/whisperkit-coreml/blob/main/openai_whisper-large-v3-v20240930_626MB/config.json), [4-bit 압축 모델 등록](https://huggingface.co/argmaxinc/whisperkit-coreml/commit/7cef198a6853ab5a017a76304d56d5e704fcc99a), [기존 로컬 오디오 설명](../../local-audio.md)

**Voxtral Mini Transcribe 2**는 녹음 파일을 처리하며 한국어·영어를 포함한 13언어와 최대 100개 이름 힌트를 지원한다. 모델 ID는 `voxtral-mini-2602`다. 이름 힌트는 영어에 최적화되어 있고 다른 언어는 실험 단계이므로 한국어 문장 안 영문 이름의 개선을 보장할 수 없다. [공식 출시문](https://mistral.ai/news/voxtral-transcribe-2/), [모델 문서](https://docs.mistral.ai/models/voxtral-mini-transcribe-26-02), [공식 요금](https://docs.mistral.ai/inference/pricing)

**Qwen-Audio-3.1-ASR-Flash**는 한국어·영어 언어 힌트를 함께 지정하고 고유명사 가중 힌트를 줄 수 있어 후속 시험 가치가 있다. 동기 HTTP의 Base64 입력은 최대 5분 녹음을 처리한다. 국제/Singapore 기본 Flash 요금은 위 표의 토큰 단가이며 Streaming 요금과 다르다. 전사 API의 음성 초→입력 토큰 환산을 확인하지 못해 시간당 가격이나 Groq보다 저렴하다는 결론을 내리지 않았다. [모델·언어·입력 사양](https://www.alibabacloud.com/help/en/model-studio/asr-model), [녹음 HTTP API](https://www.alibabacloud.com/help/en/model-studio/fun-asr-flash-recorded-speech-recognition-http-api), [공식 요금](https://www.alibabacloud.com/help/en/model-studio/model-pricing)

Deepgram Nova-3의 한국어 단일 언어 지원과 `multi` 혼합 언어 지원은 별개이며, 확인한 혼합 언어 목록에는 한국어가 없었다. AssemblyAI의 최신 3.6 Pro Realtime은 한국어·영어를 지원하지만 $0.45/세션시간이며 현재 파일 전사 구조에 스트리밍 구현을 추가해야 한다. 따라서 현재 구성의 저비용 대체 후보로 우선하지 않았다. [Deepgram 언어 지원](https://developers.deepgram.com/docs/models-languages-overview), [혼합 언어 목록](https://developers.deepgram.com/docs/multilingual-code-switching), [AssemblyAI 최신 출시문](https://www.assemblyai.com/blog/universal-3-6-pro-realtime), [공식 요금](https://www.assemblyai.com/pricing)

STT는 녹음을 글로 바꾸는 단계다. Luna 문장 정리와 Jev 검토는 그 이후의 텍스트를 대상으로 한다. 후속 음성 비교에서는 STT 결과의 한영 이름·숫자·부정·자기 정정, 응답 시간, 실제 과금 길이/토큰을 먼저 비교하고 문장 정리·Jev의 결과를 별도로 기록해야 한다.
