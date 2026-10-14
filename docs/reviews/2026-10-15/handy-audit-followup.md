# Handy 코드 감사 후속 개선과 검증

기준 문서: [2026-10-15-handy-code-audit.md](../../research/2026-10-15-handy-code-audit.md).

2026-10-15의 실제 작업 트리를 다시 확인한 뒤 기존 미커밋 작업 위에 범위를 좁혀 구현했다. 원본 조사 문서와 기존 기능 도입 보고서는 수정하지 않았다.

## 병렬 검토와 기존 작업 보존

- 메인과 하위 에이전트 3개를 동시에 운영했다. 동시 실행 한도는 메인 포함 4개다.
- 하위 에이전트는 총 4개를 활용했다: `capture_integrity`, `recording_watchdog`, `keyboard_layout`, `independent_review`.
- 앞의 3개는 독립 감사와 담당 파일 구현, 네 번째는 교차 검토와 통합 경계 검토를 맡았다. 메인은 AppModel 복구 연결, 비교실 종료 경계, 회귀 재현과 전체 검증을 맡았다.
- 변경 전 사본: `/private/tmp/opennotype-before-handy-followup-20261015T064205`.
- 사본에 있던 473개 파일 중 이번 범위의 10개 파일만 변경했다. 나머지 463개는 바이트 동일하다. 브랜딩·메뉴 막대·앱 수명주기·기존 다른 작업을 보존했다.

## 문서 후보의 현재 판정

| 후보 | 착수 시 확인 | 이번 변경 | 남는 경계 |
| --- | --- | --- | --- |
| ready 이후 진행 정지 감시 | 최초 준비 timeout, 장치 변경, willSleep 처리는 이미 존재 | callback과 delivery를 독립적으로 감시하고 stop 직전에 재검사 | 영구 정지한 writer의 비동기 종료·복구는 미구현 |
| 고정 용량 전달·누락 계수 | 대기 buffer 32개 상한과 초과 failure가 이미 존재 | frame 계수, 오류 latch, 종료 결과 계약, writer와 독립된 metrics 조회 | 사전 할당 ring/pool과 callback 할당 제거는 보류 |
| 배열별 Command+V | 물리 ANSI V 고정 | 현재 배열의 Command layer를 역매핑해 게시 직전 사용 | 실제 배열별 외부 앱 입력은 미검증 |

## 수정한 핵심 결함

### 종료 중 실패가 정상 입력으로 통과하는 경계

기존 경로는 `enqueue/consume/flush failure → writer queue → MainActor Task`였다. MainActor가 먼저 `stop()`에 들어가면 queue drain 중 오류가 발생해도 `sessionID=nil` 이후 도착한 이벤트는 무시됐다. AppModel도 종료 결과를 확인하지 않아 불완전 파일을 전사·자동 입력할 수 있었다.

이를 실제 AppModel 경로의 회귀 테스트로 재현했다. 종료 함수에서 오류를 확정했는데도 인식 함수·입력 함수가 호출되고, 복구 기록은 없어서 3개 assertion이 실패했다. 테스트는 시스템 경계를 주입하므로 실제 마이크나 외부 앱 입력 재현은 아니다.

현재 동작:

1. `AudioCapture.finish() -> Error?`가 admission, 변환, 저장, flush 오류를 보존해 반환한다.
2. `AudioRecorder`가 `lastFailure`에 이를 반영한다.
3. `AppModel.stop()`은 음성 감지·화자 등록·전사보다 먼저 이를 검사한다.
4. 이미 마감한 URL을 재사용해 이중 stop 없이 기존 암호화 복구로 연결한다. 불완전 녹음은 자동 입력하지 않는다.
5. `SpeechComparisonLab`도 stop 이후 오류를 검사해 불완전 sample을 비교에 사용하지 않는다.

복구 Task 시작 전 취소와 실제 원자 커밋 도중 취소를 검증했다. 이미 시작한 커밋이 취소 후 끝나면 별도 취소되지 않은 Task로 이번 item.id만 삭제한다. 기존 복구 녹음은 보존하며 화면의 해당 항목도 제거한다.

### 진행 감시와 전달 계수

- ready 이후 250ms 간격으로 확인한다. callback 5초, pending input이 있는 delivery 10초를 초기 임계값으로 사용한다. 기기 실측으로 최적화한 수치는 아니다.
- `ContinuousClock`으로 잠자기 시간을 포함하고 callback 사이 최대 공백도 보존한다. 재개 직후 timer보다 stop이 먼저 와도 검사한다.
- 0값 PCM도 frame 수신으로 인정한다. MainActor timer가 늦어졌다는 이유만으로 실패 처리하지 않는다.
- 기존 session ID 검사와 sleep observer를 유지했다. 최대 길이 도달 후 의도적인 callback 종료는 구분한다.
- callback/accepted/dropped/delivered/pending 계수는 channel 수와 독립된 **입력 frame** 기준이다. drain 후 `callbackFrames == deliveredFrames + droppedFrames` 관계를 검증한다.
- `deliveredFrames`는 변환·저장 단계에서 처리한 입력 frame 수다. 최대 길이에서 마지막 출력이 잘릴 수 있으므로 실제 WAV sample 보존량과 같다는 뜻은 아니다. WAV 길이는 output metrics와 파일 길이로 확인한다.
- 복사·flush buffer 할당 실패와 flush drain 상한 초과도 조용한 성공으로 처리하지 않는다.
- `currentMetrics()`와 `progressSnapshot()`은 writer queue.sync를 기다리지 않는다. callback의 NSLock·buffer 할당·복사는 남아 있다.

### 배열별 붙여넣기

MainActor에서 `TISCopyCurrentKeyboardLayoutInputSource`의 Unicode layout과 Command modifier를 사용해 `UCKeyTranslate`로 V의 물리 키를 찾는다. IME의 기반 배열을 사용하며 해석 실패 때 기존 ANSI V로 돌아간다. [Apple UCKeyTranslate 문서](https://developer.apple.com/documentation/coreservices/1390584-uckeytranslate?language=objc).

사용자 입력 소스를 선택·전환하지 않고 설치된 배열 데이터를 검사했다: ABC → 9, Dvorak → 47, Dvorak-QWERTY ⌘ → 9, layout 없음 → 9. 기존 Command press/release, native device flag, private event source와 클립보드 복원·취소·secure input·대상 검사를 유지했다.

## 자동 검증

- 변경 전 `swift test`: Platform 563 + Core 640 = 1,203개, 실패 0, 조건부 생략 2.
- 전용 필터: 오디오·watchdog·배열·키 이벤트·빠른 받아쓰기 30개, 실패 0.
- Python CI: `SPARKLE_TEST_ARTIFACT_DIR="$PWD/.build/artifacts/sparkle/Sparkle" python3 -m unittest discover -s scripts -p 'test*.py'`: 209개, 실패·생략 0.
- 최종 `swift test`: Platform 581 + Core 640 = 1,221개, 실패 0, 조건부 생략 2. 생략은 opt-in 모델 다운로드·캐시 전사 통합 테스트다.
- `git diff --check` 통과.

## 개발용 앱 빌드

- `DEVELOPMENT_SIGNING_IDENTITY="TechJuice Local Code Signing" scripts/build-app.sh` 통과.
- 결과: `build/OpenNoType.app`, Apple Silicon arm64, bundle ID `app.opennotype.mac`.
- 최종 경로에서 `codesign --verify --deep --strict --verbose=2` 통과. 서명 주체 `TechJuice Local Code Signing` 확인.
- 실행 파일 SHA-256: `35d3bf8b6f6b4424ed49dd2ae51717c04c07cc589bc03daa2605b647a8254749`.
- 로컬 개발 빌드만 생성했다. `/Applications/OpenNoType.app` 교체, 앱 실행, 실제 입력 테스트, 커밋·푸시는 수행하지 않았다.

검증 로그:

- `/private/tmp/opennotype-handy-followup-baseline.log`
- `/private/tmp/opennotype-handy-followup-red.log`
- `/private/tmp/opennotype-handy-followup-focused.log`
- `/private/tmp/opennotype-handy-followup-swift.log`
- `/private/tmp/opennotype-handy-followup-python.log`
- `/private/tmp/opennotype-handy-followup-build.log`

## 남은 개선과 실기기 경계

1. **종료·snapshot의 비동기화:** writer가 영구 정지하면 `finish()`의 queue.sync는 여전히 기다린다. preview의 snapshot도 같은 큐를 MainActor에서 동기 대기한다. 따라서 이번 watchdog가 영구 writer 정지에서도 UI 응답·복구 완료를 보장하지는 않는다. 단일 소유자와 session 계약을 유지하고, 파일 writer와 복구 reader가 동시에 접근하지 않는 비동기 종료 설계가 다음 우선순위다.
2. **사전 할당 buffer pool/ring:** 기존 32개 상한을 유지했다. 실제 callback 지연·메모리·disk pressure를 측정한 뒤 교체 여부를 판단한다. frame 계수만으로 장치나 OS 이전 단계의 모든 손실을 확인할 수는 없다.
3. **물리 검증:** 내장·USB·Bluetooth 마이크, 권한 철회, 실제 sleep/wake, 장치 전환, 자연 발화는 확인하지 않았다. Recorder 자체의 장치/세션 경쟁 테스트 seam도 아직 없다.
4. **실제 외부 입력:** ABC·한국어 2벌식·Dvorak·Dvorak-QWERTY ⌘에서 TextEdit·Chromium 입력과 녹음 중 배열 전환은 별도 확인해야 한다. 키 remapper와 앱별 사용자 단축키 해결을 보장하지 않는다.
5. 정상 녹음의 한영 혼용 인식률, 숫자·고유명사 정확도, 체감 지연 개선은 주장하지 않는다. 설치된 앱의 동작과 소스/빌드 검증도 구분한다.
