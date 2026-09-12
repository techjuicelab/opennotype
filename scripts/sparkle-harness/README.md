# 격리된 Sparkle 설치 검증

이 하네스는 OpenNoType의 코드·실제 설치 앱·사용자 기록·키체인을 사용하지 않습니다. 매 실행마다 새 임시 폴더, 임의의 `app.opennotype.sparkle-harness.<UUID>.host` / `.driver` ID, 합성 앱 빌드 1과 2를 만듭니다. 서명은 공개 RFC 8032 테스트 벡터로 만든 ZIP과 ad-hoc 코드 서명만 사용합니다. 테스트 키 파일은 서명 직후 지웁니다. 이 벡터를 제품 서명 키로 사용하면 안 됩니다.

기본 모드는 준비만 수행합니다. 실제 동작은 `--execute`가 있어야 시작합니다.

```sh
# 합성 앱, 드라이버, 서명된 ZIP 준비만: 서버 및 앱 실행 없음
python3 scripts/sparkle-harness/run.py

# 실제 Sparkle 다운로드 → 서명 확인 → Target.app 1→2 교체 → Driver.app 재실행
python3 scripts/sparkle-harness/run.py --execute

# 서명한 뒤 ZIP 바이트를 변조: 서명 불일치로 거부되고 빌드 1을 유지해야 통과
python3 scripts/sparkle-harness/run.py --execute --tamper
```

준비된 Sparkle 2.9.6 아티팩트와 macOS arm64 컴파일 도구가 필요합니다. 기본 아티팩트 경로는 저장소의 `.build/artifacts/sparkle/Sparkle`이며 `--sparkle-artifact`로 다른 로컬 아티팩트를 지정할 수 있습니다. 패키지 다운로드는 수행하지 않습니다. 실행 모드는 `127.0.0.1`의 임시 포트만 열고 두 합성 파일만 제공합니다. 제한 시간은 기본 180초이며 `--timeout-seconds 30..300`으로 지정합니다.

재실행된 드라이버는 Sparkle를 다시 시작하지 않고 교체 결과를 기록한 뒤 종료합니다. 검사 항목은 다음과 같습니다.

- 합성 피드와 ZIP에 대한 실제 로컬 HTTP 요청
- Sparkle의 업데이트 발견·다운로드·설치 이벤트
- 대상 앱 빌드·payload·실행 파일 SHA-256 교체
- 서로 다른 PID로 드라이버가 정확히 두 번 실행됐는지와 종료 요청
- 드라이버 실행 파일 SHA-256 보존
- `UNEXPECTED-TARGET-EXECUTION` 표시가 없어 대상 실행 파일은 실행되지 않았는지
- 변조 시 Sparkle의 실제 서명 검증 오류 체인, 빌드 1 보존
- 기록된 테스트 드라이버 PID의 종료, 해당 임의 ID의 설정·캐시 정리

증거 경로는 시작 시 출력됩니다. `prepared.json`, `report.json`, `events.jsonl`, `http-requests.jsonl`, `cleanup.json`, 준비 로그와 합성 앱은 검토를 위해 남깁니다. 시간 초과나 OS 거부는 실패로 보고하며 다른 프로세스를 강제로 종료하지 않습니다. Gatekeeper, quarantine, 시스템 보안 설정을 바꾸거나 전역 라이브러리 검증을 해제하지 않습니다. 로컬에서 만든 ad-hoc 드라이버에는 Hardened Runtime을 켜지 않습니다.

## 검증 범위

[공식 SPUUpdater API](https://sparkle-project.org/documentation/api-reference/Classes/SPUUpdater.html)의 `hostBundle`은 교체 대상, `applicationBundle`은 종료·재실행 대상을 정합니다. 이 하네스는 이를 다른 합성 번들로 지정합니다. Sparkle 2.9.6 소스의 `SPUInstallerDriver.m`은 `_applicationBundle.bundlePath`를 relaunch 경로로 보내며, `Autoupdate/AppInstaller.m`은 그 경로의 앱 종료를 기다립니다.

단순히 생산 앱을 임시 경로로 복사하고 별도 드라이버를 지정하는 것은 충분한 격리가 아닙니다. Sparkle의 설정 및 설치 XPC 서비스는 **host bundle ID**도 사용하므로 `app.opennotype.mac`을 그대로 쓰면 실제 앱의 설정·설치 세션과 겹칠 수 있습니다. 하네스 드라이버는 생산 ID와 임의 외부 설치 경로를 받지 않습니다.

따라서 이 결과는 실제 Sparkle 프레임워크의 다운로드·서명 검증·교체·재실행 경로에 대한 합성 검증입니다. 공개 GitHub ZIP의 설치, HTTPS 리디렉션, Gatekeeper 최초 실행, 실제 OpenNoType의 데이터·키체인 호환성을 검증했다는 뜻은 아닙니다. 그 범위는 별도 macOS 사용자 또는 가상 머신에서 실제 배포 파일과 이전 버전으로 검증해야 합니다. 업데이트 피드가 없는 기존 0.1.9 앱에는 먼저 새 배포본의 수동 설치가 필요합니다.
