# 0.2.3 커뮤니티 배포 검증

`v0.2.3` / build35 / macOS14 이상 / arm64를 **2026-10-07 01:51:55 UTC**(사용자 현지 2026-10-06)에 공개했다. [공개 릴리스](https://github.com/techjuicelab/opennotype/releases/tag/v0.2.3)는 Latest이며 draft·prerelease는 false다. [PR25](https://github.com/techjuicelab/opennotype/pull/25)를 사용자의 main 커밋·push·설치 요청에 따라 squash 병합했다. 이전 [0.2.2 보고서](community-release-0.2.2.md)는 당시 관측 기록으로 보존한다.

## 변경 범위와 소스

0.2.3은 실제 버전 표시와 배포 안내의 안정화 버전이다. 앱 하단의 고정 ‘개발 미리보기’를 실제 `0.2.3 (35)` 표시로 바꾸고, 릴리스의 첫 수동 설치 안내를 유효한 feed·공개 키가 없는 개발 설치본 전체에 적용하도록 정리했다. `LSUIElement=true`와 메뉴바 중심 동작을 유지한다.

두 새 번역 지침 후보는 28회·36회 실제 비교에서 일본어의 반복 확인 표현과 영어의 부자연스러운 이중 강조 표현이라는 목표 개선을 확인하지 못해 제외했다. **OpenNoTypeCore 전체와 번역 관련26소스는 공개 v0.2.2와 바이트가 같다.** NativeTranslationInstructions.swift SHA-256은 `9f7d964028e39c66135c3d1b8c6de9d9e4569b8554d94d2590d2433d86dc142a`다. 새 오프라인 사례·payload 격리 검사는 모델 품질 합격을 뜻하지 않는다. 모델·Jev 기본값·설정·호출 수를 바꾸지 않았으며 자세한 비교와 미해결 사항은 [번역 검토 기록](native-translation-0.2.3.md)에 남겼다.

최종 검증 브랜치 커밋은 `4ea4e6483f492b477e8dd7bf6fa9fe076cf79d52`, squash main과 태그 소스는 `0ab6d77c9ce265c0b15945d8e1d9c790f3784121`이다. 전체 Git tree가 같은 것을 확인했다. 이후 문서 커밋은 공개 다운로드와 실제 설치 기록만 정리하며 태그 소스를 변경하지 않는다.

## 자동 검증

| 실제 실행 | Swift | Python | 결과 |
| --- | --- | --- | --- |
| [최종 브랜치 push](https://github.com/techjuicelab/opennotype/actions/runs/37557862353) | 864 중862 통과 / 기존 선택형2 skip / 실패0 | 197 통과 / skip0 | 앱 빌드·artifact 업로드 성공 |
| [최종 PR](https://github.com/techjuicelab/opennotype/actions/runs/37557865879) | 862 통과 / 2 skip / 실패0 | 197 통과 | 성공 |
| [병합 main](https://github.com/techjuicelab/opennotype/actions/runs/37558407076) | 862 통과 / 2 skip / 실패0 | 197 통과 | 성공 |
| [태그 일반 빌드](https://github.com/techjuicelab/opennotype/actions/runs/37558438674) | 862 통과 / 2 skip / 실패0 | 197 통과 | 성공 |
| [태그 배포](https://github.com/techjuicelab/opennotype/actions/runs/37558438680) | 862 통과 / 2 skip / 실패0 | 197 통과 | 패키징·서명·초안 왕복 대조·게시 성공 |

전체 Swift864 테스트 식별자 집합은 다섯 실행에서 일치한다. 기존 LocalAudio 선택형2 skip과 community 조건에 따라 실행하지 않은 Apple 인증서·공증3단계는 구분한다. 실제 테스트 성공 뒤 임시 Sparkle 키를 준비했고, 패키징·공개 예정6파일 보존·임시 자료 정리·초안 재검증·초안 생성·재다운로드 바이트 대조·최신 이력 재검사·Latest 게시는 모두 성공했다.

## 공개 파일 검증

인증 없이 고정 버전 파일6개를 다시 내려받았다. 모두 HTTP200이며 실제 크기·SHA-256은 GitHub asset digest·checksum·metadata·appcast와 일치한다. Latest API의 release id는 `405294134`이고 고정 태그와 같다. 최신 feed도 고정 버전 `appcast.xml`과 바이트가 같다.

| 파일 | 바이트 | SHA-256 |
| --- | ---: | --- |
| `OpenNoType-0.2.3.dmg` | 10,896,717 | `ff2a02ecb97d8cde06cc165988b1432caba73d9a1b7f347713661767f00c2b53` |
| `OpenNoType-0.2.3.dmg.sha256` | 87 | `538ae56c907f04ba321b8749eff77abfd7b7def1c8d50b27274d4a386dc60ad3` |
| `OpenNoType-0.2.3.zip` | 9,934,598 | `9dec68cbde6346a90fb4c916286e8ef45888dfbf7489668b66a99de0c8181ef1` |
| `OpenNoType-0.2.3.zip.sha256` | 87 | `2039b8e358ca0e61375965618aa91db98e1c642e47f564c64a345357c40aeb7d` |
| `appcast.xml` | 1,375 | `1e6e6f771e9b8c06c400173c3d6b1bec2df139d4ddbdd2f512f25f00ec7fa1c5` |
| `release-metadata.json` | 790 | `00b86806d763b051c24bbea82b3c5663459ece45322df00b1b3be3710f934dcc` |

- ZIP Ed25519 서명을 CryptoKit으로 검증했다. 이전 공개 v0.2.2(34)와 Sparkle 공개 키가 같고 회전하지 않았다.
- ZIP 앱과 Sparkle.framework의 strict 코드 서명을 확인했다. arm64 실행 파일 SHA-256은 `b745315baa71d6ea90b132a9d5d9d78600088fa7486dffcf7ba52c7ad4c0ead8`이다. Info는 0.2.3(35), `app.opennotype.mac`, `LSUIElement=true`이며 feed·공개 키는 metadata와 일치한다.
- DMG 컨테이너 무결성 검증 후 고유 경로에 readonly/nobrowse/noautoopen으로 실제 마운트했다. DMG와 ZIP의 Info·전체 파일 바이트/모드·심볼릭 링크 대상·디렉터리 모드가 같다. 99파일 / 9링크 / 69디렉터리, canonical tree SHA-256은 `940b938fd788981e163a2c05b62225d6a7be2520fc9af2872d9cfd2e5810dc84`다. 실제 읽기 전용 filesystem과 strict 서명을 관측하고 정상 detach했다. 확장 속성·소유자·시각은 tree 비교 범위에서 제외한다.
- 공개 자산을 지정한 release-preflight와 공식 installer의 `--verify-only`를 통과했다. installer 자체는 최신 정식 버전 ZIP checksum·strict signature를 확인하므로, 위 고정0.2.3 다운로드와 Ed25519 검사 및 설치 후 대조를 함께 확인한다.

## 이 Mac 설치와 실행 확인

기존0.2.2(34)는 `/Applications`에 있었으나 실제 PID61768의 실행 경로는 AppTranslocation이었다. 녹음 대기 상태를 확인한 뒤 정상 종료했고, 기존 설정과 암호화 기록을0700 비공개 백업에 보존했다. Keychain 값은 내보내지 않았다.

공식 installer로 `/Applications/OpenNoType.app`을 교체하고 **2026-10-07 01:53:31 UTC**에 공개 ZIP과 설치 앱의 전체 file/link/mode tree·실행 파일·strict signature·0.2.3(35)/LSUIElement·quarantine를 대조했다. 교체 전후 설정 값과 암호화 기록 파일 해시는 같았다. 이전0.2.2(34) 앱도0700 backup폴더에 보존하고 Info·실행 파일SHA·strict signature를 확인했다.

[Sparkle의 실행 위치 안내](https://github.com/sparkle-project/Sparkle/discussions/2688)에 따라 Finder의 실제 이동 명령으로 새 앱을 고유 Downloads 임시 폴더에 옮겼다가 Applications로 되돌렸다. quarantine를 제거하거나 Gatekeeper/TCC를 바꾸지 않았다. Finder에서 Applications 앱을 실행하자 **Apple could not verify OpenNoType.app is free of malware** 경고가 나왔다. 사용자 스크린샷으로 확인했고 앱별 수동 승인을 요청했다.

처음 개인정보 보호 및 보안 화면에는 Open Anyway가 없었다. 사용자는 경고 창의 버튼을 물었고 Done을 안내했다. 설정의 General로 이동한 뒤 Privacy & Security를 다시 열자 **OpenNoType.app was blocked / Open Anyway** 항목이 실제 AX에 나타났다. 이 새 앱별 보안 예외와 Mac 인증은 사용자가 직접 완료해야 한다. [Apple의 앱별 수동 허용 안내](https://support.apple.com/102445)를 따른다.

**현재 실행 승인 대기다.** 새 앱의 실제 Applications 실행 경로·화면 버전·권한·고정 TextEdit 자동 입력·업데이트 확인·실제 상태 아이콘 클릭과 Dock 시각 관측은 아직 성공으로 기록하지 않는다. PID가 잠깐 관측됐거나 파일 검증이 통과한 것만으로 앱 실행 성공을 판정하지 않는다.

## 확인 범위

community 배포는 ad-hoc 앱 서명과 Sparkle Ed25519 ZIP 서명을 사용하며 Developer ID·Apple 공증이 없다. 공개 파일 무결성·설치 파일 일치·실제 실행·권한/Keychain 접근·자동 입력·버전 간 Sparkle 교체·자연 발화 번역 품질은 각각 별도 증거가 필요하다. 이번 안정화가 원어민 수준 번역, Jev의 정확도 보정 완료 또는 모든 앱에서의 입력 성공을 뜻하지 않는다.
