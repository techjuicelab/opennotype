# 로컬 0.2.4(40) 설치 기록

2026-10-07, main `64efdd78556a741eb6976cd75476322db137d553` 반영 후 `/Applications/OpenNoType.app`을 로컬 0.2.4(36)에서 **0.2.4(40)**으로 교체했다. 설치 파일과 첫 실행 전 보존 검증을 마친 뒤 **정확한 `/Applications` 경로의 실행과 창의 0.2.4(40) 표시를 확인했다.** Keychain·설정 준비는 아직 진행 중이며 사용자 인증 완료·권한 재확인·실제 입력은 대기다. 공개 다운로드는 v0.2.3(35)로 유지하며 새 공개 태그·릴리스를 게시한 결과가 아니다.

[5차 품질 결과](translation-idiomatic-polish-round5-results.md)를 근거로 한정 채택한 지침이 포함되어 있다. 이전 HOLD·잠긴 판독은 변경하지 않았으며, 파일 설치나 CI 통과를 모든 번역의 의미·자연스러움 합격으로 해석하지 않는다. [기능 안내](../../translation-refinement.md)의 기본 꺼짐과 선택형 추가 요청 정책을 유지한다.

## 소스·CI·설치 연결

- 실제 빌드 소스: `4261228f002ae74449cdc8e5f84afba4ecdc0249`.
- main 반영: `64efdd78556a741eb6976cd75476322db137d553`.
- 후속 CI 소스: `2d6a9ff90c60e989749d559d1b30783eddf0bb2f`. 빌드 이후 변경은 기존 `Tests/OpenNoTypeCoreTests/DictationTranslationTests.swift` assertion 한 줄뿐이며 제품 빌드 입력은 같다.
- [PR CI 37636889016](https://github.com/techjuicelab/opennotype/actions/runs/37636889016)·[push CI 37636881157](https://github.com/techjuicelab/opennotype/actions/runs/37636881157): 각각 고유 XCTest 899개(897 통과·기존 LocalAudio 2개 건너뜀·실패 0개), Python 198개 통과·건너뜀 0개. 최초426의 옛 assertion 실패 기록도 보존한다.

설치 보조 도구는 실행 중 앱이 없는지 확인하는 게이트와 동시 작업 잠금을 통과한 뒤 진행했다. 기존36 앱은 별도 `/Applications/.opennotype-backup-*/previous.app`에 보존했고, 설정과 암호화 데이터의 사전 백업을 두었다. 이 보고서에는 백업 본문·키 값·개인 기록을 노출하지 않는다. 보존 확인은 설치기의 내부 비교 결과를 사용한다. 설치 proof는 **첫 실행 전 설정·암호화 데이터가 변경되지 않았음**, Keychain export 없음, 보안 설정 변경 없음을 기록한다. 프로세스 정지 게이트 통과와 종료 방법·직접 exit code 관측은 별개의 근거다.

이미 만든 후보40의 후속 변경 허용 범위는 `docs/`와 정확한 테스트 한 파일이다. rename을 끈 NUL 경로 검사 및 `Sources`·`Resources`·패키지·`scripts`·라이선스 등 제품 빌드 입력 동일성 검사를 통과했다. 실제 변경이 테스트를 포함하므로 `post_build_changes_docs_only=false`로 기록했다. 후보를 새 코드로 다시 빌드한 것처럼 표현하지 않는다.

교체는 스테이징 복사 뒤 두 번의 rename과 예외 시 롤백을 사용한다. 예외 복구 경로가 있다는 뜻이며 전원 중단에도 완전한 원자성을 보장하는 설치 방식은 아니다. 보안 승인·강제 종료·권한 리셋을 설치 성공의 전제로 자동 수행하지 않았다.

## 설치 파일의 독립 읽기 검증

| 항목 | 확인 결과 |
| --- | --- |
| 경로·버전 | `/Applications/OpenNoType.app`, 0.2.4(40) |
| 실행파일 SHA-256 | `5c1c41edf1bf100e3ec822df0fe39eae74cbf372e84c63faea618ac1eb431e11` |
| 구조 | arm64, 최소 macOS 14.0, `app.opennotype.mac`, `LSUIElement=true` |
| 서명 | 6개 구성요소 strict ad-hoc 검증; Developer ID·Apple 공증 아님 |
| 권한·업데이트 메타데이터 | 6개 entitlements와 업데이트 4개 정책 필드가 이전36과 동일 |
| 소스 연결 | 동결 소스28·커밋·빌드 로그 SHA 일치; 바이너리 내 Git commit 암호학적 증명은 아님 |
| 전체 번들 | 후보와 설치본 101파일·9링크·73디렉터리 동일 |
| 첫 실행 전 보존 | 설정·암호화 데이터 동일, Keychain export·보안 설정 변경 없음 |

설치기 자체 tree SHA는 `f737f2974aa95cf0fdd8c389fe88e8c6f05d83d719377ac381363057fb81f98d`이며 후보·설치본에 같은 알고리즘을 적용했다. 독립 감사 도구의 tree SHA는 `a13c0d241eb129f7359be0a1c1a395a298db11bbcc6c745ca5e88a073a45bc57`로 설치 전 후보 proof와 같다. 두 도구의 직렬화 형식이 달라 해시 문자열끼리 일치를 요구하지 않는다. 비교 범위는 파일 바이트·모드, 링크 대상, 디렉터리 모드이며 xattr·소유자·시각은 제외한다.

독립 감사 도구는 설치·실행을 수행하지 않고 이미 교체된 `/Applications` 번들을 읽었다. 해당 proof의 작업 미수행 필드를 앱이 설치되지 않았다는 의미로 읽지 않는다. 실제 교체는 별도 installation proof에 연결한다.

## 실제 실행과 남은 확인

root가 CUA로 정확한 `/Applications/OpenNoType.app`을 선택해 실행한 뒤 `2026-10-07T14:45:17.646110+00:00`에 다음을 기록했다.

| 항목 | 실제 관측 |
| --- | --- |
| 실행 경로·PID | PID2061, `/Applications/OpenNoType.app/Contents/MacOS/OpenNoType` |
| 실행파일 | 설치 proof와 같은 SHA `5c1c41edf1bf100e3ec822df0fe39eae74cbf372e84c63faea618ac1eb431e11` |
| 창 | 설정 창이 열렸고 0.2.4(40) 표시 확인 |
| 활성화 정책 | AppKit accessory, raw1 |
| 초기화 | Keychain·설정 준비 중; 완료 확인 없음 |
| 권한 표시 | 준비 중 화면에서 마이크·손쉬운 사용 모두 ‘허용 필요’ |
| 실제 사용 | 마이크·모델 호출·Jev·대상 앱 입력 시험 없음 |

초기화 중 권한 표시만으로 기존 권한이나 저장 키가 유실됐다고 판단하지 않는다. SecurityAgent 프로세스는 있었으나 CUA에서 인증 UI를 선택하지 못했다. 사용자에게 보이는 macOS 인증창을 직접 완료하도록 요청했고 답변을 기다리는 상태다. 인증창을 실제 확인했거나 Keychain 준비·입력 준비가 완료됐다고 주장하지 않는다. macOS 보안 승인을 자동 클릭하거나 보안 설정을 바꾸지 않았으며 앱은 실행 상태로 두었다.

Finder 캡처가 비어 있어 전역 Dock·메뉴바의 시각 관측과 상태 아이콘 클릭을 확인하지 못했다. accessory 메타데이터와 `LSUIElement=true`, 메뉴바 코드·서명은 실제 아이콘 관측을 대체하지 않는다. 창 닫기·재열기, 번역 다듬기 토글의 현재 값, 초기화 뒤 권한, 실제 대상 앱 입력과 업데이트 교체도 미확인이다. 사용자 응답 이후 관측이 생기면 별도 후속 기록으로 추가한다. 초기 준비 화면·창 부재·CUA 인벤토리만으로 crash·미실행·idle을 단정하지 않는다.

## 로컬 증거

아래 파일은 ignored 로컬 증거이며 공개 배포 자산이 아니다. 사전 백업의 실제 내용이나 비밀 값을 포함하지 않는다.

| 파일 | SHA-256 |
| --- | --- |
| `build/local-install-0.2.4-build40/installation-proof.json` | `16ef1730ec4337100789af4c750765d8b246b4816d128d981455f0424a36ee37` |
| `build/local-install-0.2.4-build40/independent-installed-bundle-proof.json` | `1fc2834b8f935a2495e584c30d5050108ce7597d3a80bab081b69b76ca96029a` |
| `build/local-install-0.2.4-build40/independent-bundle-proof.json` | `c239bfbdace2d1eade8cdaa4952aca0fdefaaacab4fba09bf521513cc68454e5` |
| `build/local-install-0.2.4-build40/test-only-bridge-proof.json` | `bd2fc662ee9299be73a21b9f5e3aca443460562ba3edbdebb3faa36051de33e3` |
| `build/local-install-0.2.4-build40/runtime-launch-proof.json` | `b7e41778be76da15ac093df8d0d0cdabbe63fe695df6911617110cf94a01d5dd` |
| `build/native-translation/idiomatic-polish-round5-2026-10-07/ci-test-contract/independent-ci-final-audit.json` | `54ba67d645896c82ab887ff092d60691a404d60f3bb6d378ee1b260d5e64406b` |

이 설치 기록은 [5차 결과](translation-idiomatic-polish-round5-results.md)의 당시 설치 전 상태나 과거 잠긴 판독을 덮어쓰지 않는다.
