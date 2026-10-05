# 0.1.26 커뮤니티 공개 배포 검증

2026-10-05 14:30:34 UTC에 [OpenNoType 0.1.26 (28)](https://github.com/techjuicelab/opennotype/releases/tag/v0.1.26)을 공개했다. 공개 상태는 `draft=false`, `prerelease=false`이며 GitHub 최신 릴리스와 최신 Sparkle 피드가 이 버전을 가리킨다. Apple Silicon · macOS 14 이상을 지원한다.

## 소스와 배포 실행

- 배포 코드: [`dcb7b9d`](https://github.com/techjuicelab/opennotype/commit/dcb7b9d8edd1dc7b9e911a2e4f9344d692a29226), main에 포함된 커밋의 `v0.1.26` 태그.
- [PR #19](https://github.com/techjuicelab/opennotype/pull/19)의 입력·교정 학습·Jev 사례 삭제·수량 판정·저장 복구 등 확인된 오류 수정을 포함한다. `0.2.1`의 별도 개발 기능은 포함하지 않는다.
- [main CI](https://github.com/techjuicelab/opennotype/actions/runs/37323136601): Swift 783개 중 781개 통과·선택 실행 2개 제외·실패 0개, Python 196개 통과, 개발 앱 빌드·산출물 업로드 성공.
- [배포 CI](https://github.com/techjuicelab/opennotype/actions/runs/37324052798): 같은 Swift/Python 검사, 최적화 community 패키징, 서명 검증, 초안 업로드·전체 파일 재다운로드 비교, 최신 공개 전환 및 임시 서명 키 삭제 성공.
- 배포 방식은 `community`다. 앱과 DMG는 ad-hoc 코드 서명, 업데이트 ZIP은 기존 Sparkle 키의 Ed25519 서명을 사용한다. Developer ID·Apple 공증 단계는 실행하지 않았다.

## 공개 파일의 독립 검증

인증 없이 최신 릴리스 API와 고정 버전 주소에서 파일 6개를 내려받았다. 공개 자산 목록·크기·GitHub digest와 실제 SHA-256을 대조했으며 다음 검사를 통과했다.

- `OpenNoType-0.1.26.zip`, `OpenNoType-0.1.26.dmg`, 두 파일의 `.sha256`, `appcast.xml`, `release-metadata.json`만 존재한다.
- ZIP·DMG 체크섬, 메타데이터·appcast·ZIP 내부 Info.plist의 버전 `0.1.26`, build `28`, 배포 방식 `community`, 최소 OS `14.0`, 채널과 고정 버전 URL이 일치한다.
- 인증 없는 `releases/latest/download/appcast.xml` GET 결과가 `v0.1.26`의 appcast와 바이트 단위로 일치한다.
- 기존 공개 `v0.1.10`과 GitHub의 예상 공개 키가 일치하며, 새 배포본도 같은 공개 키를 사용한다. 32바이트 공개 키의 SHA-256은 `2c022b5a44a020821d6ef792bb89262fdd381798bd613bfc4f9287a1cacf7572`다. 키를 새로 발급하거나 교체하지 않았다.
- 독립 CryptoKit 실행으로 최종 공개 ZIP의 Ed25519 서명을 검증했다. 개인 키는 이 검증에 사용하지 않았다.
- 추출 앱의 `codesign --verify --deep --strict`, 실제 ad-hoc 서명·hardened runtime 플래그 없음, arm64 단일 아키텍처를 확인했다.
- DMG의 `hdiutil verify`, `codesign --verify --strict`, 실제 ad-hoc 서명을 확인했다.
- 앱 번들에 업데이트 피드와 공개 키, 자동 확인 허용·자동 설치 비활성 기본값이 들어 있다.
- 공식 `scripts/install-release.sh --verify-only`도 익명 최신 ZIP 다운로드와 SHA-256·bundle·arm64·코드 서명 검증을 통과했다. 이 검증 모드는 앱을 설치하거나 실행하지 않는다.

| 파일 | 바이트 | SHA-256 |
| --- | ---: | --- |
| `OpenNoType-0.1.26.dmg` | 10,764,183 | `97cb4373f99438988311cee839fef894290420be1cb9a6b5d2f6bd2076afbadb` |
| `OpenNoType-0.1.26.zip` | 9,828,703 | `b73f55eba43fd90f299c84cbc5adf5cd4e7b90396999f9b27feb1e8910e6880d` |

## 실제 사용 검증의 범위

이번 기록은 공개 파일·서명·피드와 배포 실행의 검증이다. 공개 앱의 실제 설치·실행, OpenNoType 두 공개 버전 사이 Sparkle 교체·재실행, 기존 설정·기록·마이크·손쉬운 사용 권한·Keychain 접근 보존은 별도 실기기 검증이 필요하다. 자연 발화 품질과 대상 앱 9개의 전체 입력 흐름도 이 배포 검사로 검증된 것은 아니다. 이전 합성·설치 결과는 각 보고서의 당시 범위를 유지한다.

기존 설치 앱은 교체하거나 실행하지 않았고 보안 설정·사용자 데이터·Keychain을 변경하지 않았다. 로컬 개발 설치본은 버전이 같은 `0.1.26 (28)`이어도 피드·공개 키가 없을 수 있다. 해당 개발 설치본은 최초 한 번 공개본을 수동 설치해야 한다.

## 다운로드와 최초 설치

[공개 DMG](https://github.com/techjuicelab/opennotype/releases/download/v0.1.26/OpenNoType-0.1.26.dmg)에서 앱을 Applications로 복사해 사용한다. 커뮤니티 배포이므로 macOS 최초 실행이 차단되면 [Apple의 앱별 수동 허용 안내](https://support.apple.com/102445)를 참고한다. 서명 방식 변경 뒤 권한이나 Keychain 접근을 다시 허용해야 할 수 있다. [설치 안내](../../mac-installation.md)와 [업데이트 운영 안내](../../updates.md)에 절차와 한계를 기록한다.
