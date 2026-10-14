# Handy 코드 조사: OpenNoType에 도입할 신규 개선 후보

> 다른 채팅에서 개선 작업의 출발점으로 사용할 조사·인계 문서입니다.
> **구현 완료 보고서가 아닙니다.** 코드 관찰, 예상 효과, 검증할 가설을 구분합니다.
> OpenNoType 비교 기준은 **2026-10-15 00:16:58 KST의 미커밋 변경을 포함한 소스**입니다.
> 조사 중 다른 개발 작업이 진행됐으므로, 개선에 착수하기 전에 현재 코드를 다시 확인하고 이미 구현된 부분은 제외해야 합니다.

## 1. 결론과 추천 순서

신규 가치가 분명한 후보는 다음 3개입니다.

| 우선순위 | 후보 | 해결하는 상황 | OpenNoType 판정 | 추천 |
| --- | --- | --- | --- | --- |
| 1 | 녹음 준비 이후의 샘플 정지·처리 정지·잠자기 공백 감시 | 녹음 표시가 유지되지만 실제 음성 수신이나 처리가 멎음 | 일부 구현되어 강화 가능. 최초 준비 timeout은 이미 구현 | 실험 후 판단 |
| 2 | 고정 용량 오디오 전달과 누락 frame 계수 | callback은 계속 오지만 변환·파일 저장이 따라가지 못함 | 일부 구현되어 강화 가능. 큐 점유 상한·누락 계수·완전성 계약은 신규 | 실험 후 판단 |
| 3 | 활성 키보드 배열에 맞는 Command+V 키 해석 | 전사는 정상이나 Dvorak 등의 배열에서 붙여넣기 명령이 잘못 전달됨 | 붙여넣기는 구현됨. 배열 역매핑은 없음 | 실험 후 판단 |

**Handy에 한영 혼용·고유명사·숫자 인식을 더 정확하게 만드는 독자적인 알고리즘이 있다는 근거는 확인하지 못했습니다.** 이번에 가져올 가치가 큰 부분은 인식 모델 자체보다 모델에 도달하는 음성과 외부 앱 입력의 신뢰성입니다.

정확도 개선율, 시작 지연 감소량, 종료→입력 단축량은 측정하지 않았습니다. 바로 채택을 권할 정도의 실기기 근거도 확보하지 않았습니다.

## 2. 사용자 목표와 조사 방법

사용자 우선순위:

1. 한국어·영어가 섞인 발화의 인식 정확도.
2. 고유명사·개발 용어·숫자·날짜·버전의 정확한 보존.
3. 녹음 시작 반응과 종료부터 실제 입력까지의 속도.
4. 사용 편의와 입력 성공률.
5. 말투와 의미를 유지하는 충실한 받아쓰기.

대상:

- [Handy 저장소](https://github.com/cjpais/Handy)
- [Handy 공식 사이트](https://handy.computer/)
- OpenNoType 체크아웃: `/Users/techjuice/Documents/Dev/AI/opennotype`

README 요약이 아니라 실제 호출 경로, 상태 전이, 실패 처리, 테스트를 읽었습니다. 공식 사이트의 오프라인·간편 입력 설명은 제품 의도 확인에만 사용했으며, 정확도 증거로 취급하지 않았습니다.

실제로 메인과 서브에이전트 3개를 동시에 실행했습니다.

| 담당 | 조사축 | 최종 발견 |
| --- | --- | --- |
| 메인 | A. 인식 정확도·한영 혼용: 전처리, 샘플링, 디코딩, 언어 판단, 숫자·고유명사 보존 | 직접 채택할 신규 정확도 후보 없음 |
| `latency_resources` | B. 반응속도·자원 사용: 녹음 시작, 스케줄링, 복사, 저장·추론 관계, 대기 | 고정 용량 전달·누락 계수 |
| `input_shortcuts` | C. 외부 앱 입력·단축키: 포커스, 권한, 대상 추적, 취소·경쟁 상태 | 키보드 배열별 Command+V 해석 |
| `recovery_state_ux` | D. 복구·상태·사용 경험: 장치 오류, 잠자기, 중단, 설정, 피드백 | 녹음 진행 중 정지 감시 |

B와 C는 서로의 입력·실행기 발견을 독립적으로 검토했고, D는 A의 언어 근거·후처리 판단을 교차 검토했습니다. 메인도 핵심 호출 경로와 테스트를 다시 읽었습니다. PCM 직통 등 중복 후보는 최종 신규 목록에서 제거했습니다.

조사에서는 원본 코드 수정·커밋·설치·앱 실행을 하지 않았으며, 테스트도 실행하지 않고 내용을 읽었습니다. Handy clone, 의존 라이브러리 소스 확인, 조사 기준 소스 사본 생성만 임시 디렉터리에서 수행했습니다. 이 문서는 이후 사용자의 별도 요청으로 저장했습니다.

## 3. 버전과 증거의 시점

| 대상 | 조사 당시 최신 공개 배포판 | 조사 당시 main SHA |
| --- | --- | --- |
| Handy | [v0.9.8](https://github.com/cjpais/Handy/releases/tag/v0.9.8), 2026-10-03 배포. 태그 commit `14f6f0d31cb22a4268acfbddba3052820fd0a06e` | `cfcb650758899d96392ab6248cb2c1c03e50aa93` |
| OpenNoType | [v0.2.3](https://github.com/techjuicelab/opennotype/releases/tag/v0.2.3), 2026-10-07 배포 | `f223adc544dc9e69dbb91e10627782538054d29b` |

OpenNoType 소스 비교 기준:

- 비교 대상은 위 HEAD에 미커밋 변경을 더한 작업 트리입니다. HEAD나 공개 배포판만 비교한 것이 아닙니다.
- 조사 중 `AudioCapture.swift`가 추가되고 `AudioRecorder.swift`가 AVAudioEngine 경로로 갱신됐습니다. 초기 관찰의 “AVAudioRecorder 경로”, “AudioCapture 미연결”은 최종 판단에 사용하지 않았습니다.
- 비교 기준은 **2026-10-15 00:16:58 KST**에 고정했습니다. 이 시점에는 `installTap → AudioCapture.enqueue`가 연결되어 있습니다.
- Handy 링크는 commit SHA에 고정한 permalink입니다.
- OpenNoType 상대 링크는 현재 파일로 이동합니다. 본문의 행 번호는 조사 시점 기준이므로 변경 후에는 함수명으로 다시 찾아야 합니다.
- 미커밋 부분에는 GitHub permalink가 없습니다. 단일 Markdown만으로도 근거를 확인할 수 있도록 부록에 핵심 코드 발췌와 SHA-256을 수록했습니다. 임시 디렉터리의 존속을 전제하지 않습니다.

Handy main의 `handy-recorder`는 **0.1.0**입니다. crate archive의 SHA-256은 `Cargo.lock` checksum `4a734d6d16eb8eb485548d75f383fa0c09d65b037a20e648c19730860f7a8a3f`와 일치했습니다. `.cargo_vcs_info.json`의 원본 commit은 `1d975fe8c10f9a69d778cf16955c7e0699b4b8e1`이었습니다. 아래 의존 라이브러리 permalink는 이 대응을 확인한 것입니다. [Cargo.lock:2663–2668](https://github.com/cjpais/Handy/blob/cfcb650758899d96392ab6248cb2c1c03e50aa93/src-tauri/Cargo.lock#L2663-L2668)

## 4. 신규 후보에서 제외할 기존 발견

다음은 사용자가 이전 조사에서 확인한 항목입니다. 설정명 변경이나 작은 변형을 신규 후보로 세지 않습니다.

- 누르기·길게 누르기 혼합 단축키, hold/toggle 선택.
- 마이크·입력 채널 지정, 녹음 중 시스템 소리 음소거.
- 녹음 준비 완료 신호와 시작·종료 효과음.
- 마이크 스트림 잠시 유지, Always-on microphone.
- AI 후처리 없는 빠른 받아쓰기와 정리해서 입력하는 모드 분리.
- 선택적 AI 후처리, 사용자 프롬프트와 로컬 endpoint.
- 녹음 중 추론, streaming 모델, 실시간 전사 미리보기.
- 모델 선택·언어 필터·다운로드 진행 표시.
- 다운로드 취소·재개·해시 검증·로컬 모델 탐색.
- 모델 미리 준비와 일정 시간 후 메모리 해제.
- 개인 단어를 인식 힌트로 전달하는 기능과 퍼지 교정.
- Handy의 사전 후교정이 한국어/CJK를 제외한다는 한계.
- Parakeet V3의 한국어 미지원.
- VAD와 발화 앞뒤 여유 구간 보존.
- 녹음 기록·음성 재생·실패 재시도·현재 모델로 재인식.
- 같은 녹음으로 엔진을 비교하는 한영 혼용 음성 테스트실.
- CLI·Raycast 등 외부 조작과 WAV 파일 전사.
- Reliable Paste, 클립보드 읽기 통지 기반 복원, 붙여넣기 지연과 클립보드 소유권 보호.
- 별도 추론 프로세스, engine supervisor, CPU fallback, ONNX→GGUF 이전 흐름.

## 5. OpenNoType 기존 기능과 정확도 조사 결과

### 5.1 기존 기능의 중복 확인

| 기능 | 판정 | 실제 연결과 근거 |
| --- | --- | --- |
| 개인 사전·제한적 교정 학습 | 이미 구현됨 | `DataViews.swift:192`의 사전 화면과 교정 검토 UI, `AppModel.saveReviewedCorrection:3729`의 저장 경로 |
| 앱별 문체 | 이미 구현됨 | `AppModel.swift:1046`에서 입력 대상 bundle ID에 해당하는 문체를 처리 snapshot에 저장 |
| 번역·선택 텍스트 음성 수정 | 이미 구현됨 | `AppModel.swift:1035–1044`의 선택 텍스트·출력 언어 설정, `1457`의 처리 요청과 외부 입력 연결 |
| 암호화 기록·실패 녹음 복구 | 이미 구현됨 | `AppModel.recordingFailed:1242`, `SecureStore.saveFailure:456`, AES-GCM seal/open `703–729` |
| 처리 시간 진단 | 이미 구현됨 | `SettingsView.swift:376–380`에서 `lastProcessingTimings` 표시 |
| Jev 검토·텍스트 모델 비교 | 이미 구현됨 | `SettingsView.swift:174–177`의 비교 진입점, `JevModelComparison.swift:112–144`의 생성·평가 요청 |

관련 파일: [DataViews.swift](../../Sources/OpenNoType/Views/DataViews.swift), [AppModel.swift](../../Sources/OpenNoType/App/AppModel.swift), [SecureStore.swift](../../Sources/OpenNoTypeCore/Storage/SecureStore.swift), [SettingsView.swift](../../Sources/OpenNoType/Views/SettingsView.swift), [JevModelComparison.swift](../../Sources/OpenNoType/App/JevModelComparison.swift).

“문서만 있고 앱에서는 제공되지 않음”으로 확인된 항목은 최종 신규 후보에 포함하지 않았습니다. 구현됨 판정은 소스상 UI·요청·저장·입력의 연결에 대한 것이며, 설치된 앱에서의 실제 동작 증명은 아닙니다.

### 5.2 A축: Handy 후처리를 그대로 채택하지 않는 이유

Handy는 실제 적용한 언어 힌트, 모델 감지, 텍스트 감지를 `OutputLanguageEvidence`로 구분합니다. 그러나 용도는 filler 삭제나 문자 체계 변환의 규칙 선택이며, 한영 혼용 구간을 더 정확하게 디코딩하는 알고리즘은 아닙니다. [resolve_output_language_evidence:1669–1719](https://github.com/cjpais/Handy/blob/cfcb650758899d96392ab6248cb2c1c03e50aa93/src-tauri/src/managers/transcription.rs#L1669-L1719)

`whatlang`의 신뢰도 문턱과 모델 지원 언어 allowlist도 문장 전체의 후처리 판단용입니다. 각 code-switching 구간의 신뢰도나 한영 혼용 개선 증거로 취급할 수 없습니다. 주석에 있는 보정 수치도 이번 조사에서 재측정하지 않았습니다. [detect_output_language:57–84](https://github.com/cjpais/Handy/blob/cfcb650758899d96392ab6248cb2c1c03e50aa93/src-tauri/src/audio_toolkit/lang_id.rs#L57-L84)

OpenNoType의 `LocalTranscriber.infer:318–339`는 `task: .transcribe`, `language: nil`, `temperature: 0`, `detectLanguage: true`, 어휘 prompt, `suppressBlank: true`를 실제 WhisperKit에 전달합니다. `DictationCleanupInstructions.swift:57–84`에는 의도적 반복·인용·고유명사·발화 중 철자 정정 보호가 있으며, `JevRepairPolicy.literalConstraintFailures:76–97`은 지원하는 literal의 보존 조건을 로컬에서 검사합니다.

관련 파일: [LocalTranscriber.swift](../../Sources/OpenNoTypeCore/LocalAudio/LocalTranscriber.swift), [DictationCleanupInstructions.swift](../../Sources/OpenNoTypeCore/AI/DictationCleanupInstructions.swift), [JevRepairPolicy.swift](../../Sources/OpenNoTypeCore/AI/JevRepairPolicy.swift).

이 지침·검사도 정확도를 보장하지 않습니다. 기존 `LocalAudioTests.swift:82–108`은 합성 한국어·영어 문장의 주제어 등을 검사하며 자연스러운 한영 혼용, 고유명사, 날짜, 버전 보존율을 검증하지 않습니다. `DisfluencyPolicyTests.swift:5–11`도 명시적으로 규격·입력 경계 검사이며 모델 출력의 증거가 아니라고 설명합니다. [LocalAudioTests.swift](../../Tests/OpenNoTypeCoreTests/LocalAudioTests.swift), [DisfluencyPolicyTests.swift](../../Tests/OpenNoTypeCoreTests/DisfluencyPolicyTests.swift)

## 6. 후보 1: 준비된 녹음이 도중에 멎었는지 지속 감시

**추천: 실험 후 판단. 분류: 일부 구현되어 강화 가능.**

### 아이디어와 사용자가 체감하는 변화

“녹음 중” 표시와 실제 음성 수신·처리의 불일치를 줄입니다. 최초 준비 성공 뒤에도 callback과 delivery 진행을 별도로 감시하고, 도중에 생긴 공백을 불완전 녹음으로 취급합니다.

구체적 상황과 적용 전·후 목표:

- 발화: “10월 15일 배포하고…v2.3.1은 보류해 주세요.”
- 적용 전 위험 상황: 앞부분 뒤에 음성 공급이 멎었는데 후반 발화 동안 녹음 표시가 계속됨.
- 적용 후 목표: 앞부분만 인식한 결과를 완성본처럼 자동 입력하지 않고 “마이크 신호가 중단되어 앞부분만 보관했습니다”라고 알린 뒤 기존 복구로 연결.

위 누락을 실제 OpenNoType에서 재현했다는 주장은 아닙니다.

### Handy에서 확인한 사실과 배포 범위

- **main에만 있음.** `handy-recorder 0.1.0`의 `Watchdog::check:37–134`는 callback 수와 처리 thread heartbeat를 독립적으로 감시합니다. [구현](https://github.com/handy-computer/handy-recorder/blob/1d975fe8c10f9a69d778cf16955c7e0699b4b8e1/crates/handy-recorder/src/capture/watchdog.rs#L37-L134)
- 녹음 중 callback 정지는 녹음 시작과 마지막 callback 중 늦은 시점부터 계산합니다. idle 정지와 녹음을 가로지르는 프로세스 suspension을 구분합니다. `stop()`이 watchdog보다 먼저 실행되는 경우에도 suspension을 검사합니다. [fail_if_suspended:137–163](https://github.com/handy-computer/handy-recorder/blob/1d975fe8c10f9a69d778cf16955c7e0699b4b8e1/crates/handy-recorder/src/capture/watchdog.rs#L137-L163)
- 값이 0인 sample도 frame이 도착하면 진행으로 셉니다. 조용히 생각하는 상태와 sample callback 자체의 부재를 구분합니다. [write_input_to_ring:54–67](https://github.com/handy-computer/handy-recorder/blob/1d975fe8c10f9a69d778cf16955c7e0699b4b8e1/crates/handy-recorder/src/capture/transport.rs#L54-L67)
- 라이브러리 기본값은 callback 정지 5초, delivery 정지 10초 등입니다. OpenNoType에 적합한 값이라는 측정 증거는 없습니다. [Timeouts:41–77](https://github.com/handy-computer/handy-recorder/blob/1d975fe8c10f9a69d778cf16955c7e0699b4b8e1/crates/handy-recorder/src/capture/engine.rs#L41-L77)
- **앱 수준의 한계:** `open_microphone:392–400`은 failure atomic을 설정하고 다음 시작 때 stream을 재구성합니다. 즉시 UI 경고·자동 입력 보류까지 완성된 기능은 아닙니다. [Handy 앱 구현](https://github.com/cjpais/Handy/blob/cfcb650758899d96392ab6248cb2c1c03e50aa93/src-tauri/src/managers/audio.rs#L392-L400)

### OpenNoType 차이와 기존 발견과의 구분

조사 시점에 이미 구현·연결된 부분:

- `AudioRecorder.start:39–104`: 최초 유효 PCM 대기와 5초 timeout.
- `AudioRecorder:76–82`: engine configuration change 때 engine 정지 상태이면 failure 처리.
- `AudioRecorder.handle:145–171` → `AppModel.recordingFailed:1242–1278`: 준비 이후 failure를 기존 암호화 복구로 연결.

신규 차이는 **ready 이후 지속적인 callback 정지·delivery 정지·녹음 중 suspension 판별**입니다. 최초 무수신, 준비 신호, 일반 장치 변경 오류, 실패 원음 보관을 신규 기능으로 세지 않습니다.

`AudioRecorder.elapsed:29–33`은 sample 시간과 monotonic 시간의 최대를 쓰므로 표시 시간이 흐르는 것은 sample 수신 증거가 아닙니다. `AudioCapture.currentMetrics:67`은 writer와 같은 queue에 `sync`하므로 이를 유일한 감시 수단으로 쓰면 감시자도 함께 멈출 수 있습니다. [AudioRecorder.swift](../../Sources/OpenNoType/Platform/AudioRecorder.swift), [AudioCapture.swift](../../Sources/OpenNoType/Platform/AudioCapture.swift)

### 기대 효과·검증할 가설·난도와 영향

- **예상 효과:** 누락된 받아쓰기의 자동 입력 감소, 중단 원인의 이해, 기존 복구로의 확실한 연결.
- **직접 개선으로 주장하지 않는 항목:** 정상 녹음의 한영 인식률, 평상시 녹음 시작·입력 속도.
- **검증할 가설:** 기존 configuration-change 처리가 놓치는 중단이 실기기에 존재하는지. 기존 보호로 충분하면 추가 효과는 작아집니다.
- **난도:** 중간~높음. callback 계수와 delivery heartbeat를 독립적으로 읽고, 감시를 멈출 수 있는 작업 큐에 의존하지 않는 설계가 필요합니다.
- **기존 기능 영향:** session ID·취소 generation·화자 등록·최대 녹음 시간·암호화 복구를 유지해야 합니다. 오래된 failure가 다음 녹음을 중단하면 안 됩니다.

### 테스트 근거와 최소 검증

Handy의 fake backend 테스트는 callback 부재·정지·중단 전 sample 보존 등을 검사합니다. AirPods, macOS 권한 철회, 물리적 sleep/wake의 성공 증거는 아닙니다. [failures.rs:228–266](https://github.com/handy-computer/handy-recorder/blob/1d975fe8c10f9a69d778cf16955c7e0699b4b8e1/crates/handy-recorder/src/tests/failures.rs#L228-L266), [잠자기 경계 관련:811–857](https://github.com/handy-computer/handy-recorder/blob/1d975fe8c10f9a69d778cf16955c7e0699b4b8e1/crates/handy-recorder/src/tests/failures.rs#L811-L857)

최소 검증:

1. ready 후 callback 정지와 delivery queue 정지를 별도로 주입해 식별.
2. 0값 PCM이 정상적으로 계속 들어오는 침묵은 실패로 판정하지 않기.
3. idle 잠자기→깨우기→새 녹음과 녹음을 가로지른 잠자기를 구분.
4. 늦은 failure·취소·재시작 경쟁 상태 검사.
5. 불완전 녹음은 자동 입력하지 않고 기존 복구로 연결하며, 취소한 녹음은 보관하지 않기.
6. 내장·USB·AirPods에서 기존 보호와의 차이를 실측.

## 7. 후보 2: 고정 용량 오디오 전달과 누락 frame 계수

**추천: 실험 후 판단. 분류: capture 분리는 일부 구현됨. 용량 상한·누락 계수·완전성 계약은 신규.**

### 아이디어와 사용자가 체감하는 변화

마이크 callback과 변환·저장 사이를 사전 할당한 고정 용량 ring buffer 또는 buffer pool로 연결합니다. callback 작업량을 제한하고 소비자가 밀려 오디오를 보존하지 못한 경우 누락을 명시합니다.

후보 1은 공급이나 처리 자체가 멈춘 상황입니다. 이 후보는 **callback은 계속 오지만 소비자가 따라가지 못하는 상황**입니다.

구체적 상황과 적용 전·후 목표:

- 발화: “PostgreSQL 17.2로 바꾸고, 10월 18일에 배포해 주세요.”
- 적용 전 위험 상황: 변환·WAV 저장 backlog나 callback 부하로 생긴 누락을 인식 모델 오류와 구분하기 어려움.
- 적용 후 목표: 정상 부하에서는 같은 음성을 전달하고, 상한 초과로 누락되면 숫자·날짜가 빠진 짧은 결과를 조용히 성공 입력하지 않고 경고·검토로 전환.

위 누락을 현재 OpenNoType에서 재현했다는 뜻은 아닙니다.

### Handy 구현과 배포 범위

고정 용량 전달과 bounded drain은 **v0.9.8에도 있습니다.**

- `AudioRecorder::build_stream:438–468`: stream 시작 전에 ring buffer 생성. [구현](https://github.com/cjpais/Handy/blob/14f6f0d31cb22a4268acfbddba3052820fd0a06e/src-tauri/src/audio_toolkit/audio/recorder.rs#L438-L468)
- `write_input_to_ring:483–546`: writable slot만큼 쓰고 초과를 atomic `overrun_samples`에 계수. 함수 본문에 동적 buffer 할당·mutex·로그·sleep이 없습니다. [구현](https://github.com/cjpais/Handy/blob/14f6f0d31cb22a4268acfbddba3052820fd0a06e/src-tauri/src/audio_toolkit/audio/recorder.rs#L483-L546)
- `run_consumer:924–938`: backlog가 있어도 다음 bounded drain 전 명령 확인. [구현](https://github.com/cjpais/Handy/blob/14f6f0d31cb22a4268acfbddba3052820fd0a06e/src-tauri/src/audio_toolkit/audio/recorder.rs#L924-L938)

main의 의존 라이브러리는 반환 계약을 강화했습니다.

- `engine.rs:672–688`: 입력 sample rate와 channel 수에 맞춰 ring을 미리 만들고 callback 실행 전에 페이지를 touch. [구현](https://github.com/handy-computer/handy-recorder/blob/1d975fe8c10f9a69d778cf16955c7e0699b4b8e1/crates/handy-recorder/src/capture/engine.rs#L672-L688)
- `write_input_to_ring:76–123`: 다채널에서도 frame 전체 단위로 전달·drop하고 `overrun_frames`에 계수. [구현](https://github.com/handy-computer/handy-recorder/blob/1d975fe8c10f9a69d778cf16955c7e0699b4b8e1/crates/handy-recorder/src/capture/transport.rs#L76-L123)
- `Stopped` / `is_complete:170–184`: 종료 이유와 `dropped_frames`를 반환하고, 정상 stop이며 ring 누락이 없을 때만 complete. [구현](https://github.com/handy-computer/handy-recorder/blob/1d975fe8c10f9a69d778cf16955c7e0699b4b8e1/crates/handy-recorder/src/lib.rs#L170-L184)

**한계:** ring은 음성을 반드시 보존하는 장치가 아닙니다. 상한 초과 때 버리고 계수합니다. Handy 앱도 누락을 로그로 남긴 뒤 PCM을 계속 반환합니다. 사용자 경고·자동 입력 보류는 OpenNoType에서 발전시킬 제안입니다. [collect_recording:913–934](https://github.com/cjpais/Handy/blob/cfcb650758899d96392ab6248cb2c1c03e50aa93/src-tauri/src/managers/audio.rs#L913-L934)

platform xrun은 로그만 남기므로 `is_complete()`도 라이브러리에 도달하기 전 모든 손실을 증명하지는 않습니다. [delivery.rs:453–459](https://github.com/handy-computer/handy-recorder/blob/1d975fe8c10f9a69d778cf16955c7e0699b4b8e1/crates/handy-recorder/src/capture/delivery.rs#L453-L459)

### OpenNoType 차이와 기존 발견과의 구분

조사 시점에 `AudioRecorder.installTap:71 → AudioCapture.enqueue:45–57`이 연결되어 있습니다. callback마다 `NSLock`, 새 `AVAudioPCMBuffer`, `memcpy`, `queue.async`를 사용합니다.

- 녹음 시간 제한은 있지만 대기 buffer의 개수·byte 상한이나 overrun 계수는 없습니다.
- `AudioCapture.consume:75–108`은 변환·WAV 쓰기·PCM 축적·metrics 갱신을 같은 serial queue에서 수행합니다.
- `snapshot:60–64`, `currentMetrics:67`, `finish:70–72`는 `queue.sync`입니다.
- `AudioRecorder:29–33,120–129,175–185`가 MainActor에서 호출하므로 저장·변환 backlog를 기다리는 경로가 있습니다.

관련 파일: [AudioCapture.swift](../../Sources/OpenNoType/Platform/AudioCapture.swift), [AudioRecorder.swift](../../Sources/OpenNoType/Platform/AudioRecorder.swift).

VAD는 남길 소리의 판별, streaming은 추론 시점, engine supervisor는 추론 장애 격리입니다. 이 후보는 **producer/consumer 속도 차이와 전달 frame의 보존 관계**를 다루므로 독립적입니다. 기존 처리 시간 진단과도 달리 오디오 누락을 기록합니다.

### 기대 효과·가설·난도와 영향

- **예상 효과:** callback 부하와 임시 buffer 사용량 제한, 누락과 인식 오류 구분, backlog 상황에서 stop/cancel 응답 개선 가능성.
- **검증할 가설:** 현재 기기·녹음 길이에서 callback 할당과 writer backlog가 유의미한 문제를 만드는지. 정상 부하에서 한영 인식률이나 속도가 개선되는지는 미확인입니다.
- **한계:** 명령을 우선 확인해도 이미 실행 중인 느린 sink 호출을 즉시 중단할 수 있는 것은 아닙니다.
- **난도:** 중간~높음. SPSC ring / pool, 소유권, stop 경계, frame 계수, 결과 metadata 설계가 필요합니다.
- **기존 기능 영향:** 암호화 복구·preview·화자 filter·최대 길이가 같은 session과 음성 구간을 다뤄야 합니다. 용량 제한만 넣고 경고 없이 음성을 버리는 변경이 되어서는 안 됩니다.

### 테스트 근거와 최소 검증

v0.9.8 테스트는 용량 부족 때 보존 sample과 누락량, drain 상한, wraparound 순서를 검사합니다. [recorder/tests.rs:172–232](https://github.com/cjpais/Handy/blob/14f6f0d31cb22a4268acfbddba3052820fd0a06e/src-tauri/src/audio_toolkit/audio/recorder/tests.rs#L172-L232)

main 의존 라이브러리의 `an_overrun_is_counted_in_whole_frames_and_keeps_channels_aligned:135–183`은 느린 sink를 의도적으로 멈추고 ring보다 많은 음성을 공급해 다음을 검사합니다. [테스트](https://github.com/handy-computer/handy-recorder/blob/1d975fe8c10f9a69d778cf16955c7e0699b4b8e1/crates/handy-recorder/src/tests/formats.rs#L135-L183)

- `delivered + dropped == pushed`
- channel frame 정렬 보존
- `is_complete == false`

합성 공급기 검증이며 실제 macOS callback 지연·disk pressure·자연 발화 정확도를 증명하지 않습니다. 조사 기준 OpenNoType `Tests`에서 큐 상한·누락 계수 검증은 찾지 못했습니다. 조사 이후 추가된 테스트는 재확인이 필요합니다.

최소 검증:

1. 느린 converter / writer를 주입하면서 callback 공급 유지.
2. 메모리 상한, 전달·누락 합계, stop/cancel 응답, session 사이 오염 확인.
3. 누락 때 경고·자동 입력 보류·기존 복구 연결 확인.
4. 실제 녹음·모델 부하·disk 부하에서 누락량과 종료→추론 시작·실제 입력 시간을 측정.

## 8. 후보 3: 키보드 배열에 맞춰 Command+V 해석

**추천: 실험 후 판단. 분류: 붙여넣기는 구현되어 강화 가능. 배열 역매핑은 미구현.**

### 아이디어·구체적 예시·기대 효과

전사는 정상인데 Dvorak 등의 배열에서 입력만 실패하거나 다른 편집 명령이 실행되는 상황이 대상입니다.

- 적용 전: 항상 ANSI V의 물리 keycode `9` 전송.
- 적용 후: 현재 배열에서 **Command를 누른 상태로 `v`가 되는 물리 키**를 찾아 전송.

예상 효과는 해당 배열 사용자의 입력 성공률입니다. 한국어 2벌식·ABC에서 추가 이득이 있다는 증거는 없으며, 인식 정확도·지연 개선은 주장하지 않습니다.

### Handy 구현과 배포 범위

**v0.9.8과 main에 동일 구현이 있습니다.** `input.rs`의 blob SHA가 양쪽 모두 `f479f8b0e145215e7fecab29de1e6cf10fe749b7`입니다.

- `resolve_command_v_keycode:77–130`: `TISCopyCurrentKeyboardLayoutInputSource`에서 layout을 얻고 Command modifier 상태와 물리 키보드 종류를 전달한 `UCKeyTranslate`로 `0..<128`을 역탐색. [구현](https://github.com/cjpais/Handy/blob/14f6f0d31cb22a4268acfbddba3052820fd0a06e/src-tauri/src/input.rs#L77-L130)
- `command_v_key:133–145`: layout data 부재·해석 실패 때 경고 후 ANSI V fallback. [구현](https://github.com/cjpais/Handy/blob/14f6f0d31cb22a4268acfbddba3052820fd0a06e/src-tauri/src/input.rs#L133-L145)
- `send_paste_ctrl_v:179–200`: 실제 paste가 해석 결과를 사용. [구현](https://github.com/cjpais/Handy/blob/14f6f0d31cb22a4268acfbddba3052820fd0a06e/src-tauri/src/input.rs#L179-L200)
- `TranscribeAction::stop:737–761`에서 main thread로 들어와 paste 경로에 연결하므로 TIS API를 main thread에서 호출합니다. [호출 경로](https://github.com/cjpais/Handy/blob/cfcb650758899d96392ab6248cb2c1c03e50aa93/src-tauri/src/actions.rs#L737-L761)

### OpenNoType 차이와 기존 발견과의 구분

`PasteKeyEvents.make:6–17`은 Command 전이·native device flag·독립 `privateState`를 보호하지만 V는 `kVK_ANSI_V` 고정입니다. `TextInsertion.paste:588–654`는 이 event를 만들고 클립보드·취소·secure input·전면 앱·입력 대상을 검사한 뒤 게시합니다.

[PasteKeyEvents.swift](../../Sources/OpenNoType/Platform/PasteKeyEvents.swift), [TextInsertion.swift](../../Sources/OpenNoType/Platform/TextInsertion.swift). 이 두 파일은 조사 시점 HEAD와 동일했습니다. [고정 permalink](https://github.com/techjuicelab/opennotype/blob/f223adc544dc9e69dbb91e10627782538054d29b/Sources/OpenNoType/Platform/PasteKeyEvents.swift#L6-L17)

Reliable Paste가 클립보드 읽기·복원 시점을 다룬다면, 이 후보는 **붙여넣기 명령 자체를 올바른 키로 보내는 문제**입니다.

### 가설·난도·기존 기능 영향·테스트

- **검증할 가설:** Dvorak-QWERTY ⌘처럼 Command 때 배열이 달라지는 변형도 해당 매핑을 따를 것으로 예상되지만, 실제 반환 keycode·앱 반응은 미검증입니다.
- **한계:** 키 remapper와 앱별 단축키까지 해결한다는 보장은 없습니다.
- **난도:** 낮음~중간. 기존 Command flags, event source, 대상·권한 검사, clipboard transaction을 유지하는 범위입니다.
- **기존 기능 영향:** 입력 직전 배열 전환, mapping 실패 fallback, TIS thread 조건을 고려해야 합니다. 해석한 키가 전송 시점에도 유효한지 확인해야 합니다.
- **기존 테스트:** `PasteKeyEventsTests:7–28`은 `[55,9,9,55]`와 flags/source를 검사하고 배열별 실제 입력은 검증하지 않습니다. Handy의 역매핑 테스트도 찾지 못했습니다. [OpenNoType 테스트](../../Tests/OpenNoTypePlatformTests/PasteKeyEventsTests.swift)

최소 검증은 ABC·한국어 2벌식·Dvorak·Dvorak-QWERTY ⌘에서 TextEdit·Chromium에 같은 문구를 입력하고 잘못된 명령·누락·중복을 확인하는 것입니다. 녹음 중 배열 전환과 해석 실패 주입도 포함합니다.

## 9. Handy를 참고해 OpenNoType에 맞게 발전시킬 설계

### 9.1 녹음 완전성 정보를 끝까지 유지

PCM만 넘기지 않고 session, 종료 이유, 공급·전달·누락 frame을 같은 결과에 유지하는 계약이 유망합니다. 다음은 개념안이며 그대로 구현하라는 요구는 아닙니다.

```text
CapturedAudio
  sessionID
  samples 또는 원음 참조
  deliveredFrames
  droppedFrames
  interruption / endReason
```

Handy 라이브러리가 제공하지만 앱 경계에서 일부 잃는 정보를, OpenNoType의 기존 자동 입력 보류·암호화 복구에 연결합니다. ring 누락 0만으로 장치 이전 단계의 모든 손실까지 보장하지 않습니다.

### 9.2 UI가 장치 작업·녹음 큐를 동기 대기하지 않기

독립 신규 기능으로 세기보다는 진행 중인 오디오 개편의 강화·완료 기준으로 삼는 것이 적절합니다.

- Handy는 coordinator 전용 thread에서 시작을 실행하고 UI 녹음 상태 조회는 atomic을 사용합니다. v0.9.8에도 있습니다. [coordinator:545–589](https://github.com/cjpais/Handy/blob/14f6f0d31cb22a4268acfbddba3052820fd0a06e/src-tauri/src/transcription_coordinator.rs#L545-L589), [atomic:1060–1066](https://github.com/cjpais/Handy/blob/14f6f0d31cb22a4268acfbddba3052820fd0a06e/src-tauri/src/managers/audio.rs#L1060-L1066)
- OpenNoType는 새 capture queue를 연결했지만 `AudioRecorder:55–85`의 장치 선택·prepare/start와 `175–185`의 removeTap/stop/drain은 MainActor입니다. metrics도 writer queue에 `sync`합니다.
- 장치 시작·종료가 느려도 UI와 취소 요청이 응답하는 구조가 목표입니다. 실제 UI 멈춤을 측정한 것은 아니며 실제 녹음 개시 자체의 단축도 보장하지 않습니다.
- start/stop/discard를 서로 다른 detached task로 보내기보다 단일 직렬 소유자와 session 검사를 유지해야 합니다. 취소 뒤 늦게 start에 성공한 recorder를 확실히 정지·폐기해야 합니다.
- 내장·USB·Bluetooth의 장치 처리 시간, MainActor 지연, 시작→취소→재시작, 오래된 callback 도착 순서를 검증해야 합니다. 기존 stub 테스트만으로 실제 장치 대기를 검증할 수는 없습니다.

### 9.3 언어 판단의 출처 보존

Handy처럼 실제 적용한 hint와 모델 감지 결과를 구분하는 설계는 참고할 만합니다. 다만 문장 전체의 언어 판단을 혼용 문장 속 각 약어·고유명사를 변경할 권한으로 사용하면 안 됩니다. 한영 혼용 정확도를 높이는 독립 신규 후보로는 채택하지 않았습니다.

## 10. 좋아 보이지만 현재 가져오지 않는 편이 나은 요소

| 요소 | 판단과 이유 | 근거 |
| --- | --- | --- |
| regex filler 삭제·3회 이상 반복 축약 | 보류. 의도적 강조나 literal을 잃을 수 있어 기존 의미 보존 처리를 대체할 이유가 약함 | [collapse_stutters:325–361](https://github.com/cjpais/Handy/blob/cfcb650758899d96392ab6248cb2c1c03e50aa93/src-tauri/src/audio_toolkit/text.rs#L325-L361) |
| 처리 중 시작 요청을 기억했다가 나중에 자동 녹음 | 보류. 마이크가 열리기 전 발화 누락과 지연 사이 입력 대상 변경을 해결하는 근거가 부족 | [on_processing_finished:475–488](https://github.com/cjpais/Handy/blob/cfcb650758899d96392ab6248cb2c1c03e50aa93/src-tauri/src/transcription_coordinator.rs#L475-L488) |
| 자동 Enter 전송 | 보류. 고유명사·숫자·의미 확인 기회를 줄임 | [send_return_key:727–765](https://github.com/cjpais/Handy/blob/cfcb650758899d96392ab6248cb2c1c03e50aa93/src-tauri/src/clipboard.rs#L727-L765) |
| Secure Input용 Carbon shadow fallback | 신규에서 제외. OpenNoType 기본 hotkey가 이미 Carbon이며 시작·입력 때 secure input 검사 | [Handy secure_input.rs](https://github.com/cjpais/Handy/blob/cfcb650758899d96392ab6248cb2c1c03e50aa93/src-tauri/src/secure_input.rs#L294-L359), [HotkeyManager.swift](../../Sources/OpenNoType/Platform/HotkeyManager.swift) |
| PCM 직통을 독립 신규 기능으로 추가 | 신규에서 제외. 기존 PCM API와 새 capture/preview가 있으며 병행 개발과 겹침 | `LocalTranscriber.swift:253–259`, `AppModel.swift:1367–1372` |

PCM 경로에는 개선 여지가 남아 있습니다. 조사 시점의 기본 최종 로컬 추론은 `audioURL`을 재읽고 화자 filter 경로만 PCM을 직접 전달합니다. 하지만 이미 capture 개편이 진행되므로 현재 코드를 재확인하고 그 작업의 검증 항목으로 다뤄야 합니다.

Handy도 PCM 추론과 WAV 저장을 병렬화하지만 ASR 뒤 WAV 완료를 await하고 history 저장도 paste보다 먼저 수행합니다. “저장이 느려도 입력은 전혀 기다리지 않는다”는 주장은 불가능합니다. [actions.rs:630–677](https://github.com/cjpais/Handy/blob/cfcb650758899d96392ab6248cb2c1c03e50aa93/src-tauri/src/actions.rs#L630-L677), [720–742](https://github.com/cjpais/Handy/blob/cfcb650758899d96392ab6248cb2c1c03e50aa93/src-tauri/src/actions.rs#L720-L742)

## 11. 다음 채팅을 위한 개선 작업 인계

### 작업 전 재확인

1. 현재 `git status --short`, HEAD, 적용되는 `AGENTS.md`를 확인하고 다른 작업의 변경을 보존합니다.
2. 아래 파일을 현재 코드에서 다시 읽어 이 문서의 관찰 이후 달라진 부분을 확인합니다.
3. 후보를 “이미 구현됨 / 일부 구현되어 강화 가능 / 실제로 없는 신규 / 문서만 존재”로 재분류합니다.
4. 병행 작업 문서는 구현 상황의 단서로 읽되 그 설명만으로 완료·실기기 성공을 단정하지 않습니다.

관련 병행 작업 문서: [docs/handy-adoption.md](../handy-adoption.md). 이 파일은 본 조사 제안서가 아니라 별도로 진행된 기능 구현 메모입니다. 서로 혼동하거나 덮어쓰지 않습니다.

현재 코드 재확인 위치:

| 대상 | 파일·함수 |
| --- | --- |
| sample 공급·변환·저장 | `Sources/OpenNoType/Platform/AudioCapture.swift`: `enqueue`, `consume`, `snapshot`, `currentMetrics`, `finish` |
| 준비·정지·중단 | `Sources/OpenNoType/Platform/AudioRecorder.swift`: `start`, `handle`, `finish`, `elapsed` |
| 복구·최종 입력 | `Sources/OpenNoType/App/AppModel.swift`: `recordingFailed`, `stop`, `process` |
| 배열별 붙여넣기 | `Sources/OpenNoType/Platform/PasteKeyEvents.swift`: `make`; `TextInsertion.swift`: `paste` |
| 로컬 최종 인식·preview | `Sources/OpenNoTypeCore/LocalAudio/LocalTranscriber.swift`: `transcribe`, `preview`, `infer` |
| 관련 테스트 | `Tests/OpenNoTypePlatformTests`, `Tests/OpenNoTypeCoreTests`. 조사 이후 추가분까지 확인 |

### 가장 먼저 적용을 검토할 3개

1. **녹음 진행 중 정지 감시:** 불완전 받아쓰기를 성공으로 입력하지 않는 것을 우선.
2. **고정 용량 전달·누락 계수:** 진행 중 오디오 개편의 부하 내성과 완전성을 확인 가능하게 만들기.
3. **배열별 Command+V:** 변경 범위가 작음. Dvorak·사용자 배열을 쓰면 우선순위를 높일 가치가 있음.

### 검증 결과를 보고할 때 구분할 증거

- 소스에 구조가 존재함.
- fake clock/backend·buffer 테스트가 통과함.
- 빌드가 통과함.
- 설치·실행 중인 빌드가 변경을 포함함.
- 실기기 마이크·자연 발화·실제 외부 입력이 성공함.

이들은 서로 다른 증거입니다. 음성 비교에서는 자연 발화의 한영 혼용, 고유명사, 숫자, 날짜, 버전, 말투와 의미를 확인하고, 인식 문자열뿐 아니라 종료→실제 입력까지 측정해야 합니다. 기존 음성 비교실을 신규 기능으로 다시 제안할 필요는 없습니다.

이 문서를 저장하는 요청에서는 구현을 시작하지 않았습니다. 실제 개선 범위는 다음 채팅의 사용자 지시에 따릅니다.

## 부록 A. 조사 시점 OpenNoType 소스 식별자

시점: **2026-10-15 00:16:58 KST**. SHA-256은 발췌문이 아니라 해당 파일 전체의 값입니다. 현재 파일과 다르면 다른 작업의 정상적인 갱신일 수 있으므로 변경 자체를 문제로 취급하지 않습니다.

| 파일 | SHA-256 |
| --- | --- |
| `Sources/OpenNoType/Platform/AudioRecorder.swift` | `2c1c2751d68447c333c91565abb37e41bb64e42c5dce0300864f8622a659e351` |
| `Sources/OpenNoType/Platform/AudioCapture.swift` | `766bcbfa9dbe9b37b56e403a1e34d2d033f32ee42f9276433ab46622584e94b2` |
| `Sources/OpenNoType/Platform/PasteKeyEvents.swift` | `bcca66bb4433a967c36810d59d2823dbd11fde0076cd4e0fe49c3eea9b897b41` |
| `Sources/OpenNoTypeCore/LocalAudio/LocalTranscriber.swift` | `524512bb9ac9938bf6d2b9cd5dced7bdb8c15bd8738b4e0978d62c256efea641` |
| `Sources/OpenNoType/App/AppModel.swift` | `cdce8a816c2669737958de4065ebdbee9f8537edccc4d48d5b03ebd3f9d1330a` |

## 부록 B. 미커밋 핵심 근거의 보존용 코드 발췌

아래는 조사 시점 코드이며 현행 코드나 채택할 구현 예제가 아닙니다. 생략 위치는 `// …`로 표시했습니다. 상대 링크가 바뀌거나 조사용 임시 디렉터리가 사라져도 핵심 관찰을 확인할 수 있도록 수록합니다.

### B.1 `AudioCapture.swift:14,45–72`: callback마다 할당과 동기 대기

```swift
private let queue = DispatchQueue(label: "app.opennotype.audio-capture", qos: .userInitiated)
// …
func enqueue(_ buffer: AVAudioPCMBuffer) {
    admission.lock(); defer { admission.unlock() }
    guard accepting, buffer.frameLength > 0,
          let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else { return }
    copy.frameLength = buffer.frameLength
    let source = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
    let destination = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
    for (from, to) in zip(source, destination) {
        if let fromData = from.mData, let toData = to.mData {
            memcpy(toData, fromData, Int(from.mDataByteSize))
        }
    }
    queue.async { [self] in consume(copy) }
}

func snapshot(maximumSamples: Int? = nil) -> [Float] {
    queue.sync {
        guard let maximumSamples else { return samples }
        return Array(samples.suffix(max(0, maximumSamples)))
    }
}

func currentMetrics() -> Metrics { queue.sync { metrics } }

func finish() {
    admission.lock(); accepting = false; admission.unlock()
    queue.sync { terminal = true; file = nil }
}
```

### B.2 `AudioRecorder.swift:6,71,84–96`: 연결된 capture와 최초 timeout

선언·함수 내부의 일부 구문을 이어 붙인 발췌이며, 독립적으로 컴파일하는 예제는 아닙니다.

```swift
@MainActor
final class AudioRecorder: NSObject {
    // …
    // start():
    input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in capture.enqueue(buffer) }
    // …
    engine.prepare()
    try engine.start()
    // withCheckedThrowingContinuation:
    readiness = continuation
    readinessTimeout = Task { @MainActor [weak self] in
        try? await Task.sleep(for: .seconds(5))
        guard !Task.isCancelled, let self, self.sessionID == session, !self.captureReady else { return }
        self.handle(.failure(RecordingError.captureTimedOut), session: session)
    }
    // …
}
```

### B.3 `AudioRecorder.swift:175–185`: MainActor에서 장치 정지와 drain

```swift
private func finish(playSound: Bool, readinessError: Error = CancellationError()) {
    readinessTimeout?.cancel(); readinessTimeout = nil
    durationTask?.cancel(); durationTask = nil
    if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
    configurationObserver = nil
    let shouldPlaySound = playSound && captureReady && audioFeedback
    lastElapsed = elapsed
    engine?.inputNode.removeTap(onBus: 0)
    engine?.stop()
    capture?.finish()
    lastElapsed = min(durationLimit, max(lastElapsed, capture?.currentMetrics().elapsed ?? 0))
    // …
}
```

### B.4 `PasteKeyEvents.swift:8–12`: V 물리 keycode 고정

```swift
guard let source = CGEventSource(stateID: .privateState),
      let commandDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Command), keyDown: true),
      let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
      let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false),
      let commandUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Command), keyDown: false) else { return nil }
```

### B.5 `LocalTranscriber.swift:324–338`: 자동 언어 감지와 text 반환

```swift
let options = DecodingOptions(
    task: .transcribe,
    language: nil,
    temperature: 0,
    detectLanguage: true,
    skipSpecialTokens: true,
    promptTokens: prompt,
    suppressBlank: true,
    concurrentWorkerCount: 2
)
let results: [TranscriptionResult] = try await engine.transcribe(audioArray: samples, decodeOptions: options,
    callback: { _ in cancellation?.isCancelled == true ? false : nil })
try Task.checkCancellation()
if cancellation?.isCancelled == true { throw CancellationError() }
let text = results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
```
