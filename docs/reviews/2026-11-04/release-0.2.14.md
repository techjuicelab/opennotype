# OpenNoType 0.2.14 (50) 검증 보고서

## 변경 범위

0.2.13 (49) 설치 후 사용자가 영어 화면의 설정 → App settings에서 화면이 깨지는 것을 보고했다. 설정 분류 segmented 선택기가 모든 칸을 가장 긴 영어 이름 폭에 맞춰 약 1,109pt가 필요했고, 기본 창(1,120pt)의 설정 페이지 폭 864pt를 넘어 페이지 전체가 넘쳤다. 0.2.11에서 영어 분류 이름을 정한 뒤부터 있던 문제다. #35에서 선택기에 짧은 이름을 쓰고(영어 합계 683pt, 한국어 504pt), 들어가지 않는 좁은 창에서는 메뉴 선택기로 바꾸게 했다. [릴리스 노트](../../releases/v0.2.14.md)를 참고한다.

## 공개 전 검증

- #35 GitHub CI(Xcode 26): Swift 1,282개 중 opt-in 2개 제외·실패 0. 두 언어 분류 이름이 기본 페이지 폭에 들어가는지 측정하는 회귀 시험을 추가했으며 이전 영어 이름에서는 실패한다.
- 같은 글꼴로 분류 이름 폭을 계산해 원인과 수정 결과를 확인했다. 실제 창의 표시는 설치 후 사용자 확인이 필요하다.

## 공개 결과

- `v0.2.14` 태그(`dbeebfe`)의 [공개 배포 실행](https://github.com/techjuicelab/opennotype/actions/runs/41738842525)이 성공했다. 실행 안의 Swift 1,282개 중 opt-in 2개 제외·실패 0, Python 214개 통과 뒤 community 서명·Sparkle 서명·자산 왕복 검증을 거쳐 공개했다.
- **2026-11-04 08:34:27 KST**에 [v0.2.14](https://github.com/techjuicelab/opennotype/releases/tag/v0.2.14)가 Latest로 공개됐다(자산 6개). 익명 `appcast.xml`은 build 50, 0.2.14를 가리킨다.

## 이 Mac 설치

- 실행 중이던 0.2.13을 정상 종료한 뒤 `scripts/install-release.sh`로 공개 ZIP의 SHA-256·bundle·arm64·코드 서명을 검증하고 `/Applications/OpenNoType.app`을 0.2.14 (50)로 교체했다. 설치본 `codesign --verify --deep --strict` 통과.
- 이전 0.2.13 (49)은 `/Applications/.opennotype-backup.*/previous.app`에 보존했다(0.2.12 백업도 남아 있음). 설정·기록·Keychain 데이터는 바꾸지 않았다.
- 설치 스크립트가 붙이는 다운로드 격리 속성 때문에 Finder로 옮기기 전에는 macOS가 앱을 임시 위치(App Translocation)에서 실행한다. 영어 설정 화면 표시, 첫 실행 허용, 권한, 실제 녹음·입력은 사용자 확인 전이다.

## 검증 경계

실제 마이크 녹음, 다른 앱 자동 입력, 다른 설정 화면의 모든 창 크기·언어 조합은 이 배포 검증 범위에 포함하지 않는다. 공개 community 산출물은 ad-hoc 앱 서명·Sparkle Ed25519 서명이며 Apple 공증은 없다.
