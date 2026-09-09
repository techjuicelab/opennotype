# 2026-09-10 개선 검증 근거

- `swift-test.log`: 210개 테스트, 208개 통과·선택 실행 2개 제외·실패 0.
- `cached-local-integration.log`: 기존 캐시만으로 모델을 준비한 뒤 한국어 합성 음성을 전사한 1개 통합 테스트 통과. 74.268초에는 모델 준비가 포함된다.
- `build-app.log`: 개발 앱 패키징과 기존 로컬 인증서 서명. strict 서명 검증이 빌드 스크립트에 포함된다.
- `StorageBenchmark.swift`, `bench-*.txt`, `bench-*-time.txt`: 합성 원음 수 0/1/3개를 각 별도 최적화 프로세스에서 측정했다. 전날 동일 workload와 비교하며 원래 로그를 보존했다.

전체 테스트는 synthetic 키·오디오·임시 저장소를 사용한다. macOS의 CoreData/XPC 진단이 일부 출력되지만 XCTest 실패는 없다. 실제 사용자 Keychain, 마이크, 유료 제공자 API의 성공을 뜻하지 않는다. Swift Testing의 마지막 `0 tests` 줄과 앞선 XCTest 210개 결과를 혼동하지 않는다.

프로젝트 루트에서 실행:

```sh
swift test
OPENNOTYPE_RUN_CACHED_AUDIO_INTEGRATION=1 swift test --filter LocalAudioTests/testOptInCachedLocalTranscriptionIntegration
DEVELOPMENT_SIGNING_IDENTITY='TechJuice Local Code Signing' ./scripts/build-app.sh
```

캐시가 없으면 캐시 전용 통합 테스트는 다운로드하지 않고 제외한다. 일반 다운로드 통합 테스트는 이번에 실행하지 않았다. 다른 Mac에서는 해당 서명 인증서가 없을 수 있다.

저장소 측정:

```sh
swiftc -O -parse-as-library \
  Sources/OpenNoTypeCore/Models.swift \
  Sources/OpenNoTypeCore/AI/WritingProfile.swift \
  Sources/OpenNoTypeCore/Storage/CorrectionLearner.swift \
  Sources/OpenNoTypeCore/Storage/KeychainSecrets.swift \
  Sources/OpenNoTypeCore/Storage/SecureStorageFiles.swift \
  Sources/OpenNoTypeCore/Storage/FailureAudioFiles.swift \
  Sources/OpenNoTypeCore/Storage/SecureStore.swift \
  docs/reviews/2026-09-10/evidence/StorageBenchmark.swift \
  -o /tmp/opennotype-improved-storage-benchmark
/usr/bin/time -l /tmp/opennotype-improved-storage-benchmark 0
/usr/bin/time -l /tmp/opennotype-improved-storage-benchmark 1
/usr/bin/time -l /tmp/opennotype-improved-storage-benchmark 3
```

fixture는 이 스크립트 옆의 고유 임시 폴더에 생성되고 정상 종료 시 삭제된다. 실제 사용자 vault나 Keychain을 읽지 않는다. 최대 RSS는 조회 한 번의 추가 할당이 아니라 저장·조회 전체 과정의 최고값이다. 과거 `2026-09-09/evidence`의 결함 probe는 과거 API와 결함 존재를 전제로 하므로 새 코드의 회귀 테스트로 사용하지 않는다.
