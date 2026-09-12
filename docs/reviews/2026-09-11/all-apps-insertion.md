# 모든 앱 자동 입력과 이전 버전 충돌 — 2026-09-11

사용자 보고: Claude 데스크톱(Code 탭) 입력창에 커서를 두고 단축키로 받아쓰기했더니 결과가 클립보드에 복사되기만 하고 입력창에는 붙지 않았다. 조사 결과 **OpenNoType은 실행 중이 아니었고**, 로그인 항목으로 자동 실행된 이전 버전 `notype` 0.3.4(`space.techjuicelab.notype`, `/Applications/notype.app`)가 같은 ⌥Space 단축키로 녹음·처리했다. 8월 21일 빌드인 그 바이너리는 손쉬운 사용 쓰기가 `.success`를 돌려주면 실제 반영 여부와 무관하게 "주입 성공"으로 처리하고(`~/Library/Logs/notype/app.log` 13:20:50·13:21:53 "주입 결과: 성공"), 결과는 주입 전에 항상 클립보드에 복사해 둔다. Electron 앱은 그 쓰기를 무시하므로 "복사만 되고 입력은 안 되는" 증상이 됐다. 세 명의 반박 검토 에이전트가 프로세스 목록, 통합 로그, notype 진단 파일, 두 저장소의 소스로 이 결론을 독립 재검증했다.

이후 사용자가 "Claude뿐 아니라 Ghostty 같은 터미널, 노트 앱 등 글자를 입력할 수 있는 모든 앱"을 요구해 입력 경로를 붙여넣기 우선으로 바꿨다. 새 개발 빌드는 **0.1.7 (8)**이다. 커밋·push는 하지 않았다.

## 바뀐 점

| 영역 | 반영된 변경 | 확인 |
| --- | --- | --- |
| 입력 경로 | 모든 앱에서 ⌘V 붙여넣기를 먼저 보낸다(`pasteThenAccessibility`). 손쉬운 사용 직접 쓰기는 클립보드 보존 불가·키 이벤트 생성 불가·원래 앱을 앞으로 못 가져온 경우에만 대신 쓰고, 이미 보낸 붙여넣기 뒤에는 절대 겹쳐 쓰지 않는다. Electron/Chromium·터미널은 붙여넣기 전용(`pasteOnly`) 그대로다. | `InsertionOutcomeTests` 전달 순서·대체 조건 검사, 아래 실제 앱 매트릭스 |
| 붙여넣기 확인 | Chromium은 빈 입력창의 placeholder("Type / for commands")를 AXValue로 노출해 앞뒤 문자열 정확 비교가 절대 맞지 않는다. 붙여넣기 전용 대상은 "값이 바뀌었고 결과를 포함" 조건으로 확인한다. | 0.1.6은 Claude에서 `submittedUnverified.paste.timedOut`, 0.1.7은 `confirmed.paste` |
| 포커스 보호 | 커서가 버튼·링크·메뉴 등 글자를 받지 않는 요소에 있으면 붙여넣지 않고 이유(`noTextField`)와 함께 결과를 보여 준다. 포커스 요소를 전혀 노출하지 않는 앱(Zed)은 같은 앱이 앞에 있으면 같은 대상으로 보고 붙여넣는다. | 역할 분류 단위 검사. Claude에서 작성창에 글이 남은 채 앱을 활성화하면 포커스가 전송 버튼으로 가는 상황을 재현 |
| 클립보드 | 붙여넣기용 항목에 nspasteboard.org `TransientType`·`ConcealedType`를 붙여 Alfred 등 클립보드 관리자가 기록하지 않게 한다. 입력 확인 뒤 원래 내용을 복원하는 동작은 그대로다. | 코드 검토 |
| 이전 버전 충돌 경고 | `HotkeyConflicts`가 notype의 `shortcutBindings.v1`(JSONEncoder가 쓰는 평면 배열, notype의 all-or-nothing 검증 규칙 그대로)과 기본값(⌥Space·⌥⇧T·⌥⇧Space)을 읽어 경고한다. 앱 시작, 녹음 시작, 해당 앱 실행·종료(`NSWorkspace.runningApplications` KVO — 메뉴 막대 전용 앱에는 didLaunch 알림이 오지 않았다) 시점에 갱신하고, 홈 화면·설정·플로팅 바에 표시한다. | `HotkeyConflictsTests` 6건, `AppModelFlowTests` 2건. notype을 실행·종료하며 홈 화면 경고 2건(⌥Space·⌥⇧Space)이 나타나고 사라지는 것을 확인 |
| 플로팅 바 | 작업 중에도 `transientMessage`를 그린다. 기존의 "다른 앱이 단축키에 반응" 알림도 이제 실제로 보인다. | 코드 검토(리뷰 에이전트 지적) |

## 실제 앱 입력 매트릭스 (0.1.7 개발 빌드, "5초 뒤 입력 테스트")

각 앱을 앞으로 가져와 입력창에 커서를 둔 뒤 OpenNoType의 무녹음 입력 테스트를 접근성 API로 눌렀고, 대상 앱의 AXValue(없으면 파일·화면)로 문구 도착을 확인했다.

| 앱 | 번들 | 정책 | 결과 | 비고 |
| --- | --- | --- | --- | --- |
| TextEdit | `com.apple.TextEdit` | pasteThenAccessibility | `confirmed.paste` | 새 문서, 정확 비교 |
| 메모 | `com.apple.Notes` | pasteThenAccessibility | `confirmed.paste` | 새 노트 본문(AXTextArea). 테스트 노트는 삭제 |
| Ghostty | `com.mitchellh.ghostty` | pasteOnly | `confirmed.paste` | 터미널이 화면을 AXTextArea 값으로 노출 |
| Chrome | `com.google.Chrome` | pasteOnly | `confirmed.paste` | `data:` URL의 textarea |
| Claude 데스크톱 | `com.anthropic.claudefordesktop` | pasteOnly(Chromium 감지) | `confirmed.paste` | Code 탭 작성창(AXTextArea "Prompt") |
| Zed | `dev.zed.Zed` | pasteOnly(요소 없음) | `submittedUnverified.paste` | AX가 창만 노출. ⌘S 뒤 파일에서 문구 확인 → 실제 입력은 성공, 확인만 불가 |

Obsidian·Notion은 사용자의 iCloud 볼트·워크스페이스에 문서를 만들어야 해서 자동 시험에서 제외했다(같은 Electron 경로). 메신저 앱은 전송 위험 때문에 제외했다.

## 남은 일

- notype은 여전히 로그인 항목이다. 시스템 설정 › 일반 › 로그인 항목에서 제거하거나 `/Applications/notype.app`을 지워야 다음 로그인 때 다시 ⌥Space를 잡지 않는다. OpenNoType은 이제 경고만 한다.
- 접근성 값을 노출하지 않는 앱(Zed 등)에서는 입력이 돼도 "확인하지 못했습니다" 안내가 매번 뜬다. 정직한 표시이지만 사용자가 앱별로 끌 수 있게 하는 방안은 검토하지 않았다.
- 터미널에 줄바꿈이 있는 결과를 붙여넣으면 명령이 실행될 수 있고 Ghostty·iTerm2는 안전 붙여넣기 확인창을 띄울 수 있다. 앱별 작성 프로필로 줄바꿈을 정리하는 것은 별도 작업이다.
- 개발 빌드는 실행할 때마다 Keychain 확인창(금고 키·API 키)이 뜬다. 확인창이 떠 있는 동안은 보안 입력 상태라 붙여넣기를 거부한다(`notSubmitted.secureInput`).
