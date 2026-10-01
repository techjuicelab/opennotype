# 새 Mac의 단축키 진단과 자동 입력 검증

검토일: 2026-10-01. 검증 환경은 Apple M5 MacBook, macOS 27, Command Line Tools의 Swift 6.4, macOS SDK 26.5다. 이 기록은 입력 경로와 단축키 진단을 다룬다. API 키, 실제 녹음, 사용자 문장, 계정 식별자, 전체 설정 파일과 원문 로그는 포함하지 않는다.

## 확인 결과

| 문제 | 확인 근거 | 처리 및 남은 범위 |
| --- | --- | --- |
| ⌥Space와 임시 ⌃⌥D가 다른 단축키처럼 보임 | 최초 사용자 보고. 이후 사용자는 단축키가 반응하지만 자동 입력이 동작하지 않는다고 정정했다. 두 조합 모두 OpenNoType 입력 테스트에서 TextEdit을 대상으로 포착했다. | 다른 앱이 두 키를 가로챘다는 원인은 확정하지 않았다. 타 앱 단축키나 Karabiner 규칙을 끄지 않았다. |
| 테스트가 끝나도 문장이 들어가지 않음 | `paste.posted` 이후 확인 제한 시간이 끝났고 본문 변화가 관찰되지 않았다. 사용자가 직접 수행한 5초 타이머 시험에서는 한글 `ㅍ` 한 글자가 들어갔다. | V 키 이벤트의 전달과 Command 수식어 누락을 구분했다. 합성 키 이벤트 프로토콜을 수정했다. |
| Karabiner와 합성 붙여넣기의 호환성 | 실행 중인 Karabiner-Core-Service 16.3.0과 `enable_cgeventtap_fallback=true`를 읽기 전용으로 확인했다. 해당 버전 공식 코드가 일반 keyDown/keyUp과 flagsChanged를 별도로 재구성한다. | Command 누름·뗌을 포함한 네 이벤트를 전달한다. Karabiner 서비스, 보안 필터, 이벤트 탭 설정은 변경하지 않았다. |
| 수정 뒤 실제 설치 앱의 입력 | 사용자가 설치 앱을 사용한 뒤 TextEdit 대상 `confirmed.paste`가 세 차례 기록됐다. 첫 번째는 `pasteThenAccessibility`, 이후 두 번은 `pasteOnly` 경로였고, 클립보드 복원도 성공했다. | 실제 설치 앱의 본문 입력 성공 근거다. 이 로그만으로 물리 마이크부터 전사·문장 정리까지 전체 음성 흐름이 검증됐다고 단정하지 않는다. |
| 설정만 보고 단축키 충돌을 확정할 위험 | 기존 진단은 실행 중인 ChatGPT와 이전 앱 notype의 알려진 저장 단축키를 읽었다. 이번 Karabiner 선택 프로필에는 ⌥Space·⌃⌥D를 바꾸는 `from` 규칙이 없었다. | Karabiner의 제한된 읽기 전용 탐지를 추가했다. 설정의 일치 가능성을 알려 주며 실제 키를 처리한 앱을 확정하지 않는다. |
| 개발 빌드의 권한 유지 | 로컬 앱은 ad-hoc 서명이며 이 Mac에 사용할 수 있는 코드 서명 identity가 없었다. Developer ID 서명·공증 배포가 아니다. | 이 소스 수정만으로 향후 재빌드·재설치 때 TCC 권한이 유지된다고 보장할 수 없다. 안정된 서명 identity로 빌드하고 업데이트 후 실제 권한을 다시 확인해야 한다. |

## 입력 실패의 기술 원인과 수정

기존 붙여넣기는 V 누름·뗌 이벤트에 Command 플래그만 붙였다. CGEventPost 호출의 완료는 대상 앱이 Command+V를 받았거나 붙여넣기를 완료했다는 증거가 아니다. `ㅍ` 한 글자가 나타난 시험은 V가 대상까지 도착했지만 Command 의미가 유지되지 않은 경우와 일치한다. 한국어 두벌식에서 해당 물리 키가 `ㅍ`을 만든다.

Karabiner 16.3.0의 CGEvent fallback은 일반 키의 keyDown/keyUp에서 키 코드를 변환하고, flagsChanged에서 수식어 상태를 따로 갱신한다. 따라서 일반 V 이벤트에만 Command 플래그를 넣은 합성 입력이 재구성 과정에서 일반 V로 처리될 수 있다. 이는 실제 관찰과 공식 구현을 연결한 원인 판단이다. 다른 이벤트 탭이 존재한다는 사실만으로 그 탭을 원인으로 지목하지 않았다. [키 이벤트 변환 코드](https://github.com/pqrs-org/Karabiner-Elements/blob/v16.3.0/src/share/event_tap_utility.hpp), [fallback 처리 코드](https://github.com/pqrs-org/Karabiner-Elements/blob/v16.3.0/src/share/monitor/event_tap_monitor.hpp).

`PasteKeyEvents.make()`는 독립된 `.privateState`에서 다음 네 이벤트를 먼저 모두 만든다.

1. 왼쪽 Command 누름 (`flagsChanged`).
2. V 누름 (`keyDown`).
3. V 뗌 (`keyUp`).
4. 왼쪽 Command 뗌 (`flagsChanged`).

Command 이벤트가 원래 생성하는 수식어와 왼쪽 장치 비트 `0x8`을 보존하고, V의 두 이벤트에도 같은 플래그를 쓴다. 단순 `.maskCommand` 대입으로 왼쪽 장치 비트를 지우지 않는다. `TextInsertion`은 네 이벤트를 `.cghidEventTap`에 중간 `await` 없이 연속 전달해 취소가 Command 누름·뗌 사이에서 끼어들지 않게 한다. Apple 문서도 단축키를 합성할 때 수식어를 포함한 모든 누름·뗌 이벤트를 만들도록 안내한다. [CGEvent 키보드 이벤트 생성 문서](https://developer.apple.com/documentation/coregraphics/cgevent/init%28keyboardeventsource%3Avirtualkey%3Akeydown%3A%29).

전달 후 기존 본문 관찰, 대상 포커스 검사와 클립보드 임대·복원을 유지한다. 이미 붙여넣기를 보냈으나 관찰에 실패한 경우에는 자동 Accessibility 쓰기나 재전달을 하지 않는다. 지연된 붙여넣기와 추가 쓰기가 겹쳐 중복 입력될 수 있기 때문이다. 권한 거부나 잘못된 포커스처럼 전송 전에 확인할 수 있는 실패와 전송 후 미확인을 구분한다.

## 단축키 경고의 범위

`HotkeyConflicts`는 실행 중인 알려진 앱의 저장 조합과 OpenNoType의 조합이 겹칠 때 설명을 표시한다. 기존 ChatGPT·notype 탐지는 유지한다. Karabiner는 설정 창이 닫혀도 동작할 수 있으므로 `org.pqrs.Karabiner-Core-Service`의 실행 여부를 기준으로 한다.

새 Karabiner 탐지는 기본 경로 `~/.config/karabiner/karabiner.json`을 최대 4 MB까지 읽는다. 선택된 프로필이 정확히 하나이고, 조건 없는 `basic` 규칙의 문자·Space·Return 키와 방향 구분 없는 Command·Option·Control·Shift 필수 수식어가 정확하게 정의된 경우만 비교한다. 꺼진 규칙은 제외한다. 경고에는 OpenNoType의 키 표시와 고정 안내문만 넣으며 규칙 설명, `shell_command`, 프로필 이름이나 전체 설정을 표시하지 않는다.

장치·앱·변수 조건, 동시 키 입력, 좌우 수식어 지정, optional·wildcard 수식어, Simple Modifications, 다른 키 종류, 사용자 지정 설정 경로는 탐지 범위 밖이다. `enable_cgeventtap_fallback`이 켜져 있다는 사실도 단축키 충돌 경고로 만들지 않는다. 범위를 벗어난 규칙이나 경고가 없는 상태는 충돌이 전혀 없다는 증명이 아니다. [Karabiner 수식어 규칙](https://karabiner-elements.pqrs.org/docs/json/complex-modifications-manipulator-definition/from/modifiers/), [조건 목록](https://karabiner-elements.pqrs.org/docs/json/complex-modifications-manipulator-definition/conditions/).

사용자에게 다른 앱이 앞으로 나왔다는 증거가 있으면 해당 앱의 실제 설정과 실행 상태를 함께 확인한다. 저장된 조합의 일치, 사용자의 초기 표현, 이벤트 탭의 존재만으로 특정 앱을 원인이라고 기록하지 않는다. 다른 앱의 설정은 자동으로 끄지 않는다.

## 새 Mac에서의 재현과 확인

1. 설치할 동일 앱의 마이크·손쉬운 사용 권한을 확인한다. macOS의 인증이나 권한 요청은 시스템 절차로 허용한다. 재빌드 후에는 이전 앱 항목이 보인다는 이유만으로 새 바이너리의 권한을 가정하지 않는다.
2. TextEdit의 임시 문서를 만들고 빈 본문을 직접 클릭한다. 비공개 문서나 비밀번호 입력창을 사용하지 않는다.
3. OpenNoType 설정 › 입력·단축키 › 입력 문제 확인에서 입력 테스트를 준비한다. 선택한 받아쓰기 단축키를 누르면 합성 문장 `OpenNoType 입력 테스트입니다.`가 나타나야 한다.
4. 단축키 자체와 삽입을 분리하려면 5초 뒤 입력 버튼을 누른 뒤 TextEdit 본문으로 이동한다. 이것은 음성·API를 쓰지 않는 동일 삽입 경로의 시험이다. 아무 변화가 없는지, V/`ㅍ` 한 글자만 생기는지, 문장이 한 번만 들어가는지 구분한다.
5. 진단의 대상 앱, 입력 경로, `confirmed.paste`, 클립보드 복원 결과를 확인한다. `paste.posted`만으로 성공 처리하지 않는다. 본문 내용을 원문 로그나 이슈에 첨부하지 않는다.
6. 텍스트 입력이 성공하면 합성 문장으로 음성을 시작·종료해 전사와 문장 처리까지 별도로 검증한다. 예: “내일 회의는 오후 세 시에 시작해 주세요.” 대상 본문 입력과 종료 뒤 결과를 사람이 확인한다.
7. 업데이트를 설치한 뒤 같은 단계를 다시 수행한다. API 설정·기본 단축키 유지, 마이크·손쉬운 사용 권한과 실제 입력을 함께 확인한다.

## 검증과 배포 한계

`PasteKeyEventsTests`는 네 이벤트의 순서, keyDown/keyUp과 flagsChanged 유형, Command 상태와 왼쪽 비트, 뗌 뒤 상태를 검사한다. 생성만 검사하며 사용자 입력이나 보안 필터를 조작하지 않는다. 실제 설치 앱의 세 차례 `confirmed.paste`는 별도의 실행 근거다.

`HotkeyConflictsTests`에는 선택·비선택 프로필, ⌥Space·⌃⌥D 일치, 중복 제거, 조건·wildcard·좌우 수식어 제외, CGEvent fallback만 켜진 설정의 무경고, 잘못된 프로필, 서비스 종료 시 파일 미조회와 비공개 규칙 내용 미노출 사례를 추가했다. SDK 26.5에서 production `HotkeyManager.swift`와 `HotkeyConflicts.swift`를 직접 컴파일한 합성 fixture 검사 16개가 통과했다. 이 검사는 사용자 설정이나 UI를 조회하지 않는 주입된 설정·실행 상태로 수행했다. 로컬 CLT에는 XCTest 모듈이 없어 전체 `swift test` 성공으로 보고하지 않는다. 이 검사와 release 앱 빌드, 실제 입력 확인은 서로 다른 검증 근거다.

현재 개발 설치는 ad-hoc 서명이다. Sparkle의 Ed25519 업데이트 서명은 업데이트 패키지 검증에 쓰이며 Developer ID 코드 서명·공증이나 TCC identity 유지의 대체 수단이 아니다. 설치 때 발생한 권한 문제를 최소화하는 최종 배포 경로에는 안정된 개발자 서명, 공증, 동일 identity의 업데이트와 새 Mac·업데이트 이후 권한 검증이 필요하다. 이 검토에서 Developer ID 인증서나 개인 키를 설치·교체하지 않았다.
