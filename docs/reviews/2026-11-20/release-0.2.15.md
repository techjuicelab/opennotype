# OpenNoType 0.2.15 (51) 검증 보고서

## 변경 범위

0.2.14 (50) 이후 UI/UX 4단계 개선(`VoiceBar` HUD, 메뉴바 빠른 전환, 관리 화면 레이아웃·키보드 단축키, 기록 모드 필터·디프 하이라이트·캐싱, 사전 분류·삭제 되돌리기, 사용량 차트 툴팁, 음성 모델 직접 관리·2열 예시 비교)과 로그인 항목 실행 시 AppKit 대체 관리 창 폴백 및 안정화 수정(안내 토스트/경고 배너 분리, 창 가시성 기반 자동 닫힘, 사전 삭제 되돌리기 충돌 방지, CJK·줄바꿈 디프, 중복 창 지연 정리·프레임 자동 저장, `TextEditor` `⌘F` 위임)을 묶어 0.2.15 (51)로 배포한다. [릴리스 노트](../../releases/v0.2.15.md)를 참고한다.

## 공개 전 검증

- 로컬 Mac(Command Line Tools, `MacOSX26.5.sdk`)에서 `OpenNoType` 디버그 빌드(Swift 경고 0건) 및 변경 영역 8개 테스트 스위트 45개 케이스 스텁 실행 통과.
- 로컬 직접 실행으로 `Edit` 메뉴 `⌘F` 중복 없음 및 `RecoveryView` `TextEditor` 찾기 막대 위임, 전체 화면 창(`.fullScreenPrimary` + `.moveToActiveSpace`)의 메뉴바 재오픈 복귀, 대체 창 `frameAutosaveName` 크기 복원을 확인했다.
- 전체 Swift 테스트 스위트(1,300개+) 및 Python 스크립트 테스트는 GitHub Actions CI(Xcode 26, `macos-15`)에서 확인한다.

공개 결과·Latest·자산 6개·익명 `appcast.xml`·이 Mac 설치 결과는 완료 후 아래에 기록한다.

## 검증 경계

실제 macOS 로그아웃 후 재로그인을 통한 로그인 항목 자동 실행 시나리오, 실제 마이크 녹음, 다른 앱 자동 입력은 이 배포 검증 범위에 포함하지 않는다. 공개 community 산출물은 ad-hoc 앱 서명·Sparkle Ed25519 서명이며 Apple 공증은 없다.
