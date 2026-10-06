# 0.2.2 커뮤니티 배포 검증

`v0.2.2` / build34 / macOS14 이상 / arm64를 2026-10-06 21:57:47 UTC에 공개했다. 사용자의 main 병합·공개 배포 요청에 따라 [PR24](https://github.com/techjuicelab/opennotype/pull/24)를 병합했다. [공개 릴리스](https://github.com/techjuicelab/opennotype/releases/tag/v0.2.2)는 Latest이며 draft와 prerelease가 모두 false다. 이전 공개본 `v0.1.26`(28)은 역사로 보존한다.

## 소스와 자동 검증

최종 브랜치 소스는 `8f230df13f3c9fc8f5687f0ac2bb5aae80d04111`, squash 병합 main과 릴리스 태그 소스는 `e1adf0e01e363f482eedc4ef7d9c658672523cb1`이다. 두 커밋의 전체 Git tree가 동일함을 확인했다. `v0.2.2^{commit}`도 해당 main 커밋과 같다. 배포 후 보고서·링크 정리는 문서만 변경하며 태그 소스를 바꾸지 않는다.

| 실제 실행 | Swift | Python | 결과 |
| --- | --- | --- | --- |
| [최종 브랜치 push](https://github.com/techjuicelab/opennotype/actions/runs/37535724680) | 864개 중 862 통과 / 기존 LocalAudio 2 skip / 실패0 | 196 통과 / skip0 | 앱 빌드·artifact 업로드까지 성공 |
| [최종 PR](https://github.com/techjuicelab/opennotype/actions/runs/37535732490) | 864개 중 862 통과 / 2 skip / 실패0 | 196 통과 / skip0 | 전 단계 성공 |
| [병합 main](https://github.com/techjuicelab/opennotype/actions/runs/37536646158) | 864개 중 862 통과 / 2 skip / 실패0 | 196 통과 / skip0 | 전 단계 성공 |
| [태그 일반 빌드](https://github.com/techjuicelab/opennotype/actions/runs/37536704116) | 864개 중 862 통과 / 2 skip / 실패0 | 196 통과 / skip0 | 전 단계 성공 |
| [태그 배포](https://github.com/techjuicelab/opennotype/actions/runs/37536704258) | 864개 중 862 통과 / 2 skip / 실패0 | 196 통과 / skip0 | 패키징·서명·draft 왕복 대조·게시 성공 |

메뉴바 회귀 6개는 단일 항목 유지, 저장된 숨김 상태 초기화, 닫힌 관리창과 상태 항목 수명 분리, 재열기 콜백, 언어·녹음 표시, preview 비활성화와 종료 경로를 확인한다. `NSStatusItem.autosaveName`의 null_resettable 계약에 따라 nil 설정은 저장 상태를 초기화하지만 getter가 nil일 것을 요구하지 않는다. 초기 build34의 잘못된 getter 가정 테스트 실패를 수정하고 위 최종 소스로 전체 검증했다.

배포 워크플로는 전체 테스트가 성공한 뒤 임시 Sparkle 키를 준비했다. 명시적 `community` 모드, 태그·main 계보·버전 단조 증가, ZIP 서명, GitHub draft의 6개 파일 재다운로드 대조, 최신 이력 재검사를 통과한 뒤 게시했다. Apple 인증서·공증용 3단계만 의도적으로 건너뛰었다.

## 공개 파일 검증

로그인 없는 고정 버전 다운로드 6개 모두 HTTP200이며 크기와 SHA-256이 GitHub asset digest 및 checksum·metadata·appcast와 일치한다. Latest API도 같은 릴리스이고 최신 feed는 고정 버전 `appcast.xml`과 바이트가 같다.

| 파일 | 바이트 | SHA-256 |
| --- | ---: | --- |
| `OpenNoType-0.2.2.dmg` | 10,896,718 | `84b3146a6e4fafb3e2ebd3d96c0ab6001444223639ff67fe30bb4d47a00ab3f8` |
| `OpenNoType-0.2.2.dmg.sha256` | 87 | `c07a1c4b97a11af961584e5cc4044adfab1f8545bfd69cadc2408520218806f4` |
| `OpenNoType-0.2.2.zip` | 9,934,584 | `f8e249c9e32624fd287b5968c773c11edce9a065e00452fdcb9e606b33000788` |
| `OpenNoType-0.2.2.zip.sha256` | 87 | `db86ef5095158c62ba65851a7fc82149283e5cbf9948edc7730db99ecf425b59` |
| `appcast.xml` | 1,375 | `bc6446b0117af5749830ffc02d5fa9e5b2a517682585dca4f3e4381d88f81282` |
| `release-metadata.json` | 790 | `af20c4ced7679cade8dc62848c5ecf7ce053d265263cc81967d17ae0745c76eb` |

- 공개 ZIP의 Sparkle Ed25519 서명을 CryptoKit으로 검증했다. `v0.1.26` 공개 metadata와 같은 공개 키를 사용한다. 기존 이 Mac의 개발 설치본에 키가 없었던 사실과 공개 키 연속성은 별개다.
- ZIP 앱과 Sparkle.framework의 strict 코드 서명을 확인했다. 실행 파일은 arm64이며 SHA-256은 `ac72e8f5a2368a25584b7b841a6ea1d2cc15486e486114efa08b921ec640bfd2`다. Info.plist는 0.2.2(34), `app.opennotype.mac`, `LSUIElement=true`, 공개 feed·공개 키가 metadata와 일치한다.
- DMG 자체의 컨테이너 무결성을 확인한 뒤 readonly/nobrowse/noautoopen으로 고유 경로에 실제 마운트했다. 읽기 전용 filesystem도 관측했고 내부 앱의 Info 값, 모든 일반 파일 바이트·모드, 심볼릭 링크 대상, 디렉터리 모드가 ZIP과 동일하다. 총 99 파일 / 9 링크 / 69 디렉터리, canonical tree SHA-256 `aabb2fa18acdb6829acd09dc36e0333593f7d2ebf04b98dbb2f0dc5242e08452`다. 앱과 Sparkle의 strict 서명을 확인하고 강제 종료 없이 정상 detach했다. 확장 속성·소유자·시각은 tree 비교 범위에서 제외한다.
- `python3 scripts/release-preflight.py --tag v0.2.2 --distribution community --artifacts <public-assets>`와 `bash scripts/install-release.sh --verify-only`가 통과했다. 익명 release page·DMG·main 번역 안내·설치 안내 링크도 HTTP200이다.

## 이 Mac 설치와 첫 실행

작업 시작 당시 `/Applications`에는 0.1.26(28)이 있었고 실행 앱은 build 폴더의 개발 시험본이었다. 설치본에는 공개 업데이트 feed·키가 없어 이번에는 공개 앱을 직접 교체했다. 시험 앱을 정상 종료하고 설정·암호화 기록을 권한 제한 비공개 백업에 보존했다. Keychain 값은 내보내지 않았다.

첫 설치 직후 2026-10-06 21:59:24 UTC에 공개 ZIP과 설치 앱의 전체 file/link/mode tree, 실행 파일, feed·키, strict 서명과 quarantine를 확인했다. 설치 전후 설정과 암호화 기록이 같았고 기존 0.1.26 앱도 0700 백업 폴더에 남겨 동일 Info·실행 파일·서명을 확인했다.

첫 실행에서는 macOS가 앱별 승인 경고를 표시했고 앱이 휴지통으로 이동했다. 사용자는 경고를 읽지 않고 버튼을 눌렀다고 설명했다. 휴지통에 있던 정확한 OpenNoType.app은 공개 ZIP과 같은 바이트·모드·링크였다. 이후 공식 설치 스크립트로 다시 설치했고 22:03:39 UTC에 동일한 설치·데이터 보존 검증을 통과했다. 휴지통 앱과 이전 앱 백업은 삭제하지 않았다.

재실행 때 사용자가 보낸 경고는 **Apple could not verify OpenNoType.app is free of malware**였으며 Move to Trash / Done 버튼이 있었다. 이는 공증되지 않은 커뮤니티 앱에 대한 실행 승인 대기로 기록한다. 당시 PID가 생성됐다 사라진 사실만으로 소스 crash나 악성코드 검출을 확정하지 않는다. 사용자·시스템 DiagnosticReports에서 OpenNoType 충돌 보고서는 발견하지 못했다.

사용자가 Done → 시스템 설정의 개인정보 보호 및 보안 → Open Anyway에서 앱별 허용과 Mac 인증을 직접 완료하고 앱이 열렸다고 답했다. 실제 실행 PID의 bundle Info는 0.2.2(34)이고 실행 파일 SHA-256은 공개 ZIP과 동일하다. 설정 화면의 마이크·손쉬운 사용은 모두 ‘허용됨’으로 관측했다. 권한·보안 예외를 자동 승인하거나 quarantine를 제거하지 않았다. [Apple의 앱별 수동 허용 안내](https://support.apple.com/ko-kr/102445)를 따른다.

다만 실행 경로는 `/Applications`가 아니라 macOS의 임시 `AppTranslocation` 아래였다. 업데이트 확인 버튼은 활성화되어 있었으나 실제 클릭하면 ‘다운로드한 위치에서 실행 중이므로 업데이트할 수 없음’ 경고가 나왔다. 경고를 취소하고 앱을 정상 종료했다. 설치 파일의 무결성 통과와 업데이트 실행 성공은 별개다. [Sparkle 유지 관리자의 안내](https://github.com/sparkle-project/Sparkle/discussions/2688)에 따라 Finder에서 다른 폴더로 옮겼다가 Applications로 되돌리는 절차를 안내했다. 자동 드래그 도구가 Finder 창을 찾지 못해 사용자에게 이동과 재실행을 요청했으며, 해당 답변을 기다린다.

최종 공개 앱의 정상 Applications 실행 경로·업데이트 검사 성공·창 닫기/재열기·메뉴바 아이콘 클릭·녹음 없는 고정 문장 입력은 아직 확인하지 않았다. 검증 도구는 Keychain 값을 읽거나 내보내지 않았고, 실제 API 인증이나 재부팅 후 자동 실행·버전 간 Sparkle 교체도 이번 설치 확인의 완료 범위에 포함하지 않는다.

하단 ‘개발 미리보기’는 이 버전 MainView의 고정 문구다. 실제 preview 동작 여부나 공개 설치 여부를 판정하는 값이 아니다. 실제 경로·Info·공개 파일 SHA·feed/키로 구분한다. 이 표시 문구는 알려진 개선 사항으로 남는다.

## 배포 기능과 품질 한계

받아쓰기 출력 언어 선택, 별도 번역 단축키, 원문·번역·당시 목표 언어 확인, 의미와 문장 흐름 보강 및 선택형 입력 전 번역 검토를 포함한다. Dock을 숨기고 delegate가 단일 AppKit NSStatusItem을 유지한다. 자동화된 상태 항목 수명 검증과 화면에 실제 표시된 아이콘 클릭 검증은 구분한다.

실제 생성 비교는 272 HTTP200 / 268 텍스트 / 4 리터럴 보호 차단 / 재시도0이다. 같은 42사례의 후속 비교는 알려진 회귀 시험이며 기술 합계를 품질 합격률로 해석하지 않는다. Luna의 일반 합계를 금액으로 좁힌 의미 오류와 Mini의 정정 흔적·표현 주의가 남는다.

번역 Jev 검토는 기본 꺼짐인 실험 기능이다. 원문·번역·목표 언어·선택 말투를 추가 전송하고 비용·시간이 추가된다. 새 상세8질문·기본3질문에 같은8사례를 실제 요청한 16응답은 모두 typed/HTTP200이지만 선택한 보수 기준에서 두 경로 모두 허용0/보류8이며 정상6도 전부 보류했다. 판별력·정확도 보정 완료나 자동 재번역을 주장하지 않는다. 사용자 일본어 예시는 자연스럽게 읽혔지만 최종 공개 빌드의 모든 자연 발화·원어민 사람 검수·다른 앱 자동 입력을 보장하지 않는다. [번역 검증 기록](native-translation-0.2.2.md)을 참고한다.

배포 방식은 기존 community다. 앱은 ad-hoc 코드 서명, 업데이트 ZIP은 Sparkle Ed25519 서명을 사용하며 Developer ID·Apple 공증은 사용하지 않는다. 공개 파일 무결성 검증, 이 Mac 첫 실행, 버전 간 실제 Sparkle 자동 교체, 권한·Keychain 유지와 번역 품질은 각각 별도 확인 범위다. [배포 운영 안내](../../updates.md)를 참고한다.
