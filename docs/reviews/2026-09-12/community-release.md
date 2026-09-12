# 0.1.10 커뮤니티 배포 검증

2026-09-12 16:19 KST에 [OpenNoType 0.1.10 (11)](https://github.com/techjuicelab/opennotype/releases/tag/v0.1.10)을 공개했다. **Apple 공증 없이** ad-hoc 앱 코드 서명과 Sparkle Ed25519 업데이트 서명을 사용하는 배포본이다. 공개 상태는 draft=false, prerelease=false이며 latest 피드가 이 버전을 가리킨다.

## 소스와 실행 근거

- 코드 커밋: [`657634f`](https://github.com/techjuicelab/opennotype/commit/657634fb68e8db65e20c2de86ae28f4ff151e8dd), 메인 반영 후 `v0.1.10` 태그 배포.
- [메인 CI](https://github.com/techjuicelab/opennotype/actions/runs/34679968192): Swift 317개 중 315개 통과·기존 선택 실행 2개 제외, Python 115개 통과, 개발 앱 빌드·서명·산출물 업로드 성공.
- [배포 실행](https://github.com/techjuicelab/opennotype/actions/runs/34680131298): 테스트, community 패키징, 서명 검증, 초안 업로드·재다운로드 검증, 최신 릴리스 공개 및 임시 키 삭제 성공. Apple 자격 준비·인증서 가져오기·공증 자격 설정은 건너뛰었다.

## 공개 파일 검증

인증 헤더 없이 GitHub 최신 릴리스 API와 고정 버전 다운로드 주소를 조회했다. 공개 파일 6개와 GitHub API의 크기·해시를 대조하고 아래 검사를 통과했다. 기계 판독 결과는 [community-release-verification.json](community-release-verification.json)에 보존했다.

- `latest/download/appcast.xml`과 `v0.1.10`의 appcast 바이트 일치.
- ZIP·DMG SHA-256과 체크섬 파일 일치, 메타데이터·appcast·앱 Info.plist의 버전·빌드·배포 방식·피드·고정 다운로드 주소 일치.
- 배포 산출물과 독립적으로 읽은 저장소의 예상 공개 키 일치 및 CryptoKit Ed25519 ZIP 검증.
- 추출한 앱의 `codesign --verify --deep --strict`, 실제 ad-hoc 서명, hardened runtime 플래그 없음, 실행 파일 arm64 확인.
- DMG의 `hdiutil verify`, 코드 서명 무결성과 ad-hoc 서명 확인.

| 파일 | 바이트 | SHA-256 |
| --- | ---: | --- |
| `OpenNoType-0.1.10.dmg` | 9,389,674 | `4f9f66a430598a00116d906acd25702a84f1767fec4ca20c66b4f185eb2a1d19` |
| `OpenNoType-0.1.10.zip` | 8,607,815 | `ca73ff734a5f6873e80cfcbbb7c9aedc856c1e5eaaadee0bdf1a93ca15e5239b` |

## 실제 업데이트 시험의 범위

[격리 하네스](../../../scripts/sparkle-harness/README.md)에서 공개 시험 키·임의 bundle ID·localhost 피드로 실제 Sparkle 2.9.6의 다운로드·서명 확인·시험 호스트 1→2 교체·별도 드라이버 종료 및 재실행을 확인했다. 서명 뒤 ZIP을 변조하면 EdDSA 불일치로 거부하고 빌드 1을 유지했다. 시험 프로세스와 서버 종료, 해당 임의 ID의 설정·캐시 정리도 확인했다.

이 결과는 실제 OpenNoType 두 버전의 설치·재실행이나 기존 사용자 기록·권한·Keychain 호환성 검증을 대신하지 않는다. 공개 ZIP은 실행하거나 설치하지 않았으며 Gatekeeper·quarantine·시스템 보안 설정을 변경하지 않았다. 기존 `0.1.9 (10)` 앱도 교체하지 않았다.

## 최초 설치

[DMG를 내려받아](https://github.com/techjuicelab/opennotype/releases/download/v0.1.10/OpenNoType-0.1.10.dmg) 기존 앱을 종료한 뒤 Applications 폴더에 설치한다. 피드·공개 키가 없는 기존 개발 설치본은 최초 한 번 수동 설치해야 하며, 새 배포본에는 이후 업데이트를 확인할 채널과 공개 키가 포함되어 있다.

최초 실행이 차단되면 출처를 확인한 뒤 [Apple의 앱별 수동 허용 안내](https://support.apple.com/102445)를 따른다. 서명 방식 변경으로 권한이나 Keychain 접근을 다시 허용해야 할 수 있다. 접근 오류가 생기면 원본 기록과 키를 보존한다. 저장소 코드는 Keychain 접근 오류를 키 없음으로 바꾸지 않고 전파하며, 기존 데이터가 있으면 새 암호화 키 생성 없이 중단한다.
