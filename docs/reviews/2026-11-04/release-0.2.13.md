# OpenNoType 0.2.13 (49) 검증 보고서

## 변경 범위

main에 머지한 #30–#33을 공개 버전으로 묶는다: 입력 전 사용량 저장 지연 제거, 복호화한 저장소 재사용, 녹음 종료 대기 제한, 로컬 모델 버전 고정·SHA-256 검증, 비공개 보안 제보 경로. 설계·측정·시험은 [2026-11-03 개선 기록](../2026-11-03/improvement-pass.md), 사용자 안내는 [릴리스 노트](../../releases/v0.2.13.md)를 참고한다.

## 공개 전 검증

- 각 PR의 GitHub CI(Xcode 26): 마지막 #33 기준 Swift 1,281개 중 opt-in 2개 제외·실패 0, Python 214개 통과. main의 머지 커밋 CI도 모두 통과했다.
- 로컬(Xcode 없음, swift-corelibs-xctest)에서 같은 시험 소스 전체 통과, `scripts/build-app.sh`와 `codesign --verify --deep --strict` 통과.
- 공개 전 최종 검토로 v0.2.12 이후 소스 변경(사용량 작성기, 저장소 캐시와 파일 식별, 녹음 종료 포기 경로, 모델 다운로드·검증·설치 경로)을 다시 확인했다.
- 실제 네트워크로 Base 모델·토크나이저·화자 모델의 고정 커밋 다운로드·검증·로드와 합성 한국어 인식을 확인했다(임시 폴더).

## 공개 결과

- `v0.2.13` 태그(`002f4e1`)의 [공개 배포 실행](https://github.com/techjuicelab/opennotype/actions/runs/41732906192)이 성공했다. 실행 안의 Swift 1,281개 중 opt-in 2개 제외·실패 0, Python 214개 통과 뒤 community 서명·Sparkle 서명·자산 왕복 검증을 거쳐 공개했다. 같은 태그·main의 Build and test도 성공했다.
- **2026-11-04 07:51:27 KST**에 [v0.2.13](https://github.com/techjuicelab/opennotype/releases/tag/v0.2.13)이 draft·prerelease가 아닌 Latest로 공개됐다. 자산은 DMG·ZIP·각 SHA-256·`appcast.xml`·`release-metadata.json` 6개다.
- 로그인 없이 받은 `releases/latest/download/appcast.xml`은 `sparkle:version` 49, `shortVersionString` 0.2.13, 버전 고정 ZIP 주소를 가리킨다.

## 이 Mac 설치

- `scripts/install-release.sh`로 공개 ZIP을 받아 SHA-256·bundle·arm64·코드 서명을 검증한 뒤 `/Applications/OpenNoType.app`을 0.2.13 (49) community 빌드로 교체했다. 설치본의 `codesign --verify --deep --strict`가 통과했고 ad-hoc 서명, 다운로드 격리 속성을 확인했다.
- 기존 0.2.12 (48)은 `/Applications/.opennotype-backup.*/previous.app`에 보존했다. 설정·기록·Keychain 데이터는 바꾸지 않았다.
- 앱 실행, macOS 앱별 허용, 마이크·손쉬운 사용 권한 재확인, Keychain 접근 재승인, 실제 녹음·입력은 사용자 확인 전이다. 서명이 바뀐 ad-hoc 빌드라 첫 실행 때 허용과 Keychain 인증을 다시 요청할 수 있다.

## 검증 경계

실제 마이크 녹음, 다른 앱 자동 입력, 유료 API 품질, 저장 작업이 실제로 멈추는 상황, Large v3·Small 모델의 실제 다운로드, 새 Mac Gatekeeper는 이 배포 검증 범위에 포함하지 않는다. 공개 community 산출물은 ad-hoc 앱 서명·Sparkle Ed25519 서명이며 Apple 공증은 없다.
