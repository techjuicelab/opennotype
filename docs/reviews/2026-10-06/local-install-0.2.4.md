# 0.2.4 메인·로컬 설치 확인

사용자의 메인·설치 앱 반영 요청에 따라 [PR #26](https://github.com/techjuicelab/opennotype/pull/26)을 2026-10-07 03:19:41 UTC(현지 2026-10-06)에 squash 병합했습니다. 기능 병합 커밋은 `c91e37d84082222849e9adbd8aaf969eb66a4660`이며 최종 검증 브랜치 `53c19bf68c61960a233a63024523fb3855b46178`와 전체 Git tree가 같습니다. 이 Mac에는 **0.2.4(36)**을 설치·실행했습니다. 공개 다운로드와 태그는 **v0.2.3(35)**로 유지하며 새 공개 릴리스를 게시하지 않았습니다.

## 기능과 품질 범위

원문과 동일 번역 초안을 대조해 한 번 다듬는 선택형 단계가 포함됩니다. 기본값은 꺼짐이며 설정 → 입력·단축키에서 선택합니다. 선택형 Jev 번역 보호를 켠 경우 최종 번역안을 검토합니다. 추가 요청은 최대 한 번·30초·재시도 없음이고, 실패·유효하지 않은 응답·로컬 보존 검사 실패는 자동 입력을 보류합니다. 옵션을 켜고 처리와 기존 입력 조건을 통과하면 최종안을 자동 입력할 수 있으며 미리보기 전용은 아닙니다.

[총 35회 모델 호출의 비교](translation-refinement-round2.md)에서 특정 주체·약속/의무 표현은 개선했으나 영어·일본어의 일부 어색한 구조는 남았습니다. 메인·설치 반영이 일반적인 자연스러움 향상이나 원어민 수준의 정확성을 입증하지는 않습니다. 당시 평가와 적용 보류 기록은 과거 시점의 근거로 보존합니다. 모델 기본값·Jev 기준·메뉴바 전용 정책은 변경하지 않았습니다.

## 빌드와 설치

- 버전 후보 `53c19bf`의 [PR CI](https://github.com/techjuicelab/opennotype/actions/runs/37565710521)와 [브랜치 CI](https://github.com/techjuicelab/opennotype/actions/runs/37565706596)는 각각 Swift 899개 중 897개 통과·기존 LocalAudio 선택 실행 2개 제외·실패 0, Python 198개 통과입니다. 신규 35개도 개별 실행·통과했고 개발 앱 빌드·업로드가 성공했습니다.
- 병합 커밋 `c91e37d`의 [main CI](https://github.com/techjuicelab/opennotype/actions/runs/37566227553)도 같은 899개 중 897개 통과·2개 제외·실패 0, 신규 35개 통과, Python 198개 통과이며 앱 빌드·업로드가 성공했습니다. 원본 로그에 대한 독립 검사 proof SHA-256은 `5cedbb7d6f74f54608b3d218033bb8473714c481553180951616850f3f946916`입니다.
- 이 Mac의 기본 SDK는 SwiftUI 매크로 검사에 실패했으나 설치된 SDK 26.5가 실제 검사에 성공해 release 앱을 빌드했습니다. 로컬 XCTest 환경은 불완전하므로 위 정식 Xcode CI와 구분합니다.
- 설치 후보와 실제 `/Applications/OpenNoType.app`은 0.2.4(36)·arm64·최소 macOS14·`LSUIElement=true`이며 전체 파일·링크·모드가 같습니다. 실행 파일 SHA-256은 `55497740a32037244edcb9d1e39e44d7990b2171f180ab91698c63f475350ec5`입니다.
- 앱과 Sparkle 내부 도구 6개의 strict 서명을 검증했습니다. 기존 공개 설치본과 같은 ad-hoc·runtime flag 없음으로 서명했으며 Developer ID·Apple 공증은 없습니다. 기존 공개 업데이트 피드·공개 키를 유지했고 새 개인 서명 키를 읽지 않았습니다. 공개 build35보다 로컬 build36이 높으므로 현재 공개0.2.3으로 내려가는 업데이트를 기대하지 않습니다.
- 교체 전 기존 앱의 대기 상태를 확인해 정상 종료했습니다. 설정과 암호화 기록은 비공개 백업에 보존했고 Keychain 값은 내보내지 않았습니다. 이전0.2.3 앱을 보존하는 롤백 가능한 2단계 rename으로 교체했으며, 첫 실행 전에 설정 값·암호화 데이터 해시가 같음을 확인했습니다. quarantine 제거·Gatekeeper/TCC 변경은 하지 않았습니다.

## 실제 실행과 남은 확인

새 앱은 `/Applications/OpenNoType.app/Contents/MacOS/OpenNoType`에서 단일 PID15572로 실행했습니다. 이전 PID75016과 다르고 AppTranslocation 경로도 아닙니다. `NSRunningApplication`의 시작 완료·accessory 정책과 실제 화면의 `0.2.4 (36)`을 확인했습니다. 이는 Dock 숨김 정책의 근거이며 메뉴바 아이콘을 실제 클릭한 증거와는 구분합니다.

실제 화면에서 기존 Groq·OpenRouter·TypeSafe 키가 저장된 상태와 업데이트 확인 버튼을 확인했습니다. 설정 → 입력·단축키의 번역 문장 다듬기 체크박스는 꺼짐(`Value: 0`), 번역 출력 언어는 기존 일본어 설정임을 확인했습니다. 키 값을 읽거나 새 API 호출을 보내지는 않았습니다. 마이크는 허용됨이지만 손쉬운 사용은 허용 필요로 표시돼 사용자에게 macOS의 앱별 재승인을 요청했습니다. 자동 입력·자연 발화·버전 간 Sparkle 자동 교체 성공은 아직 이 설치 확인의 성과로 기록하지 않습니다.

앱 파일 백업은 `/Applications/.opennotype-backup-eztvvi83/previous.app`에 보존했습니다. 상세 로컬 증거는 무시된 `build/local-install-0.2.4/`에 있습니다. 독립 후보/설치 bundle의 동일 canonical tree SHA-256은 `af95bf3866d6f5a091993664d56c563359d377b59a44b34c88dc637f9a7a97d3`이며 확장 속성·소유자·시각은 이 tree 비교에 포함하지 않습니다. 설치 독립 proof SHA-256은 `06c412bc8693d3547a9811f1467b3a72af4dddaf7b0424b41d395debef9ca910`입니다.
