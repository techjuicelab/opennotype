# OpenNoType 0.2.17 (53) 검증 보고서

## 변경 범위

0.2.16 (52) 이후 설정 화면을 다시 설계한 배포다. `feat/settings-redesign` 브랜치의 커밋 5개(39083b1–dbb7d2a)를 main에 fast-forward로 합쳤다. [릴리스 노트](../../releases/v0.2.17.md)를 참고한다.

- 설정 5개 탭(`SettingsNavigation`, `SettingsView`, `SettingsComponents`), AI 탭(`SettingsAIModelsPage`, `SettingsCostViews`).
- 기능별 모델 저장(`Preferences.taskModels`, `monthlyBudgetUSD`)과 처리 경로별 모델 선택(`AppModel`).
- 모델 검색·호환성 테스트(`ModelDiscovery`, `ModelCatalogState`), 비용 요약·예상(`UsageCostSummary`, `UsagePricing.transcriptionRate`).
- Jev 검토의 OpenRouter 키 조건 완화(`JevPreflight`, `AppModel`).

## 공개 전 검증

- 브랜치의 모든 커밋에서 GitHub Actions Build and test가 성공했다(마지막 run 44712003078, dbb7d2a). 새 테스트 `SettingsNavigationTests`, `TaskModelPreferencesTests`, `UsageCostSummaryTests`, `ModelDiscoveryTests`와 갱신한 `PreferencesWritingProfileTests`가 여기서 실행됐다.
- 미리보기 앱(`scripts/build-usage-preview.sh`, 합성 데이터)으로 한국어·영어, 라이트·다크 화면을 캡처해 배치와 문구를 확인했다.
- OpenRouter 공개 모델 목록을 실제로 받아 파싱해 318개 후보가 나오는 것을 확인했다(`:free`·`:batch` 같은 변형과 `openrouter/` 라우팅 ID 제외).
- dbb7d2a로 만든 개발 빌드(release 설정, ad-hoc 서명)를 이 Mac의 /Applications에 임시로 설치했다. 사용자가 실제 앱에서 설정 화면을 직접 눌러 보고 문제없다고 확인했다(2026-11-20). 확인 항목으로 안내한 것은 키 확인·저장, 기능별 모델 저장, 호환성 테스트, 새 모델 검색, 비용 카드다. 항목별 결과는 따로 기록하지 않았다.
- 로컬 `scripts/build-app.sh` 빌드 통과(Command Line Tools, `MacOSX26.5.sdk`). 이 Mac에는 전체 Xcode가 없어 `swift test`는 CI에서 확인한다.

## 공개 결과

- 진행 중.

## 이 Mac 설치

- 진행 중.

## 검증 경계

- 모델 단가는 내장 가격표와 OpenRouter 목록 값이며, 제공자의 실제 청구액과 다를 수 있다.
- 호환성 테스트는 짧은 합성 요청 하나로 형식과 응답만 확인한다. 실제 받아쓰기 품질을 보장하지 않는다.
- 공개 community 산출물은 ad-hoc 앱 서명·Sparkle Ed25519 서명이며 Apple 공증은 없다.
