# OpenNoType 0.2.16 (52) 검증 보고서

## 변경 범위

0.2.15 (51) 이후 AirPods 마이크 녹음 실패를 고친 수정 배포다(`AudioRecorder`, `AudioDevices`, 새 `OpenNoTypeObjC` 대상). [릴리스 노트](../../releases/v0.2.16.md)를 참고한다.

## 원인

- 2026-11-20 이 Mac에서 AirPods 녹음을 세 번 시도했고(13:16, 13:17, 13:19), 세 번 모두 시작하고 약 5초 뒤 `captureTimedOut`으로 끝났다.
- macOS 로그에는 `Format mismatch: input hw 24000 Hz, client format 48000 Hz`와 `Failed to create tap, config change pending!`가 남았다.
- 마이크 설정은 시스템 기본값이었지만, 앱이 기본 장치를 입력 유닛에 직접 지정했다. 이 경로에서는 AirPods가 헤드셋 프로필(24 kHz)로 바뀌어도 엔진의 클라이언트 형식이 48 kHz에 머문다.
- 녹음 코드는 0.2.13 이후 바뀌지 않았으므로 0.2.15의 회귀가 아니다. 이전 버전에서 AirPods 녹음이 됐는지는 로그 보존 기간(약 1일) 때문에 확인하지 못했다.

## 공개 전 검증

- 앱의 녹음 코드(`AudioRecorder`·`AudioCapture`·`AudioDevices` 등)를 그대로 컴파일한 프로브로 실제 AirPods를 낀 상태에서 확인했다.
  - 기본값 경로: 9/9 성공, 준비 약 0.68초.
  - AirPods 직접 선택: 최종 수정 후 11/11 성공, 준비 약 1.1초.
  - 마이크를 25초 이상 쓰지 않은 뒤 첫 녹음: 4/4 성공.
  - 기존 코드는 같은 조건에서 무음으로 끝나거나 `installTap` 예외로 종료됐다.
- Insta360 Link 2(USB) 기본값 경로는 기존과 같은 약 0.67초에 준비되고 정상 녹음된다.
- 임시 WAV 권한은 600으로 유지된다.
- 로컬 `scripts/build-app.sh` 빌드 통과(Command Line Tools, `MacOSX26.5.sdk`). 이 Mac에는 전체 Xcode가 없어 `swift test`는 GitHub Actions CI(Xcode 26, `macos-15`)에서 확인한다.

## 공개 결과

- `main` 푸시 후 Build and test(run 44679924770)가 성공했다. 전체 `swift test`가 여기서 실행됐다.
- 태그 `v0.2.16` → Publish verified stable release(run 44680561182)가 성공했다. 2026-11-20T05:33:09Z에 공개됐고 draft·prerelease가 아니다.
- `releases/latest`가 `v0.2.16`을 가리킨다. 자산 6개(`appcast.xml`, DMG·ZIP과 각 `.sha256`, `release-metadata.json`)를 확인했고, 익명 `appcast.xml`의 `sparkle:version`은 52다.

## 이 Mac 설치

- 실행 중이던 0.2.15를 정상 종료하고 `scripts/install-release.sh`로 설치했다. 공개 ZIP의 SHA-256·bundle·arm64·코드 서명 검증을 통과했다.
- 설치본은 0.2.16 (52)이고 `codesign --verify --deep --strict`를 통과했다. 다시 실행해 프로세스가 뜨는 것만 확인했으며, 앱은 App Translocation 경로에서 실행 중이다.
- 이전 앱 백업은 `/Applications/.opennotype-backup.VeB2Qh/previous.app`에 있다.
- 설치된 앱에서 AirPods로 받아쓰기·입력을 하는 확인은 사용자 확인 전이다.

## 검증 경계

- 설치된 앱에서 AirPods로 받아쓰기·입력까지 하는 확인은 배포 후 사용자 확인 전이다.
- AirPods가 연결된 동안 설정에서 Insta360을 직접 고르면 무음에 가까운 녹음이 된다. 이 동작은 0.2.15 코드에서도 같았고 이번 범위에서 다루지 않았다.
- 공개 community 산출물은 ad-hoc 앱 서명·Sparkle Ed25519 서명이며 Apple 공증은 없다.
