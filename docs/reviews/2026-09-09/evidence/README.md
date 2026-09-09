**2026-09-09 재검토 재현 자료**

모든 probe는 합성 문자열·합성 원음 Data·별도 임시 디렉터리·메모리 Keychain 대역을 사용합니다. 실제 Keychain, 사용자 vault, 마이크, 유료 API를 사용하지 않습니다. 앱 소스를 직접 함께 컴파일하므로 해당 시점의 source revision과 함께 해석해야 합니다.

- `swift-test.log`: 161개 테스트, 160개 통과·선택 실행 모델 통합 테스트 1개 제외·실패 0. 표준 XCTest 결과를 기준으로 읽습니다. 마지막 Swift Testing의 0 tests 줄은 별도 runner이며 XCTest 결과를 대체하지 않습니다.
- `insertion-delay-probe.swift`: 실제 InsertionDelivery/InsertionVerification에 시간을 주입합니다. 실제 AX API나 클립보드에 쓰지 않습니다.
- `store-concurrency-probe.swift`: 같은 초기 배열을 갖고 있는 두 변경과 삭제 후 오래된 배열 저장을 순서대로 수행합니다. UI 이벤트 경합 재현이 아닙니다.
- `core-probe.swift`: 의미 변경 학습, 합성 원음 저장/조회, 불완전 staging 파일의 차단과 기존 vault 보존을 확인합니다.
- `storage-benchmark.swift`: 실패 원음 수를 인자로 받아 독립 프로세스에서 합성 원음 저장 후 snapshot을 세 번 측정합니다.
- `bench-*-time.txt`: 원래 실행에서 /usr/bin/time -l로 기록한 최고 RSS입니다. 실행 중인 OpenNoType 앱의 측정값이 아닙니다.
- `core-probe.swift`, `storage-benchmark.swift`는 보존 시 임시 경로를 실행별 UUID로 바꾸고 종료 시 자기 fixture를 정리하도록 했습니다. 측정 로직은 같으며 보고서의 성능 표는 원래 실행 로그를 사용합니다.

프로젝트 루트에서 실행합니다. Swift 도구 모음과 macOS가 필요합니다. 아래 명령은 합성 fixture만 생성·정리합니다.

```sh
cd /Users/techjuice/Documents/Dev/AI/opennotype
swift test
swift build --product OpenNoType
```

지연 입력 재현:

```sh
swiftc -O -parse-as-library \
  Sources/OpenNoType/Platform/InsertionOutcome.swift \
  docs/reviews/2026-09-09/evidence/insertion-delay-probe.swift \
  -o /tmp/opennotype-review-insertion
/tmp/opennotype-review-insertion
```

예상 결과는 `pasteCount=1 resultingCopies=2`입니다. 이 probe는 현재 결함이 존재함을 assertion으로 확인하므로 수정 후 assertion 변경이 필요합니다.

저장소의 오래된 스냅샷 재현:

```sh
swiftc -O -parse-as-library \
  Sources/OpenNoTypeCore/Models.swift \
  Sources/OpenNoTypeCore/AI/WritingProfile.swift \
  Sources/OpenNoTypeCore/Storage/CorrectionLearner.swift \
  Sources/OpenNoTypeCore/Storage/KeychainSecrets.swift \
  Sources/OpenNoTypeCore/Storage/SecureStore.swift \
  docs/reviews/2026-09-09/evidence/store-concurrency-probe.swift \
  -o /tmp/opennotype-review-store
/tmp/opennotype-review-store
```

자동 학습·손상 재현은 마지막 Swift 파일을 `core-probe.swift`로, 출력 경로를 `/tmp/opennotype-review-core`로 바꿔 컴파일한 뒤 실행합니다. 저장소 성능 측정은 마지막 Swift 파일을 `storage-benchmark.swift`로, 출력 경로를 `/tmp/opennotype-review-benchmark`로 바꿉니다.

```sh
/usr/bin/time -l /tmp/opennotype-review-benchmark 0
/usr/bin/time -l /tmp/opennotype-review-benchmark 1
/usr/bin/time -l /tmp/opennotype-review-benchmark 3
```

각 count는 별도 프로세스입니다. 최대 RSS는 저장과 조회 전체 workload의 최고값이며, snapshot 한 번의 추가 메모리 할당량이 아닙니다. 9분 원음은 16,000 Hz × 2 bytes × 540초 = 17,280,000 bytes의 합성 Data로 표현합니다. WAV 해석이나 음성 인식 품질을 검사하는 입력은 아닙니다.

