# Handy 참고 기능 적용 검증

- 기준: main `f223adc544dc9e69dbb91e10627782538054d29b` + 기존 사용자 미커밋 작업 + 이번 기능 변경.
- 구성: 메인 1개와 서브에이전트 3개가 병렬로 구현·검토.
- 기존 변경 사본: `/private/tmp/opennotype-before-handy-20261015`. 독립적인 기존 앱 수명주기·브랜딩·메뉴 막대·관련 테스트 수정은 바이트 일치 확인.
- Swift 전체: 1,203개, 실패 0, 조건부 생략 2(Platform 563 / Core 640).
- 별도 캐시 통합 포함 전체 실행: Platform 563 / Core 640, 실패 0, 생략 1. 기존 Whisper Large v3 캐시만 로드하고 Yuna 합성 한국어에서 실제 인식 결과 확인. 모델 다운로드 없음.
- Python CI: 209개, 실패 0, Sparkle artifact 미설정으로 2개 생략.
- Swift 매크로·quarantine·임시 인증서 테스트는 sandbox 외부에서 동일 명령으로 통과. 테스트 기대를 완화하지 않고 실행 환경을 분리.
- 오디오: 48 kHz stereo → 16 kHz mono 변환에서 converter priming을 `.normal`로 지정한 후 정확한 길이와 마지막 10 ms 신호 보존 회귀 검사 통과.
- 취소: UI idle 전환과 비동기 원음 정리는 다른 시점이므로 취소 테스트는 실제 파일 삭제를 기다려 확인.
- 설정: 새 기본값을 명시 검증한 뒤 기존 필드 전체의 의미 동등성을 비교.

자연 발화·물리 마이크·Bluetooth 장치 전환·실제 단축키 제스처·외부 앱 자동 입력·체감 속도는 이 자동 검증의 범위 밖입니다. 앱 빌드·설치·화면 검증 결과는 아래에 추가합니다.

## 설치와 실행

- 로컬 `TechJuice Local Code Signing` 서명, strict/deep 검증 통과.
- `/Applications/OpenNoType.app` 교체 전 이전 앱·Application Support·preferences를 비공개 임시 폴더에 백업.
- 설치 직후 Application Support 144개 파일과 preferences 파일 바이트 동일, 설치 바이너리와 빌드 바이너리 SHA256 동일.
- 실행 후 기존 설정 필드의 값 모두 보존, 신규 기본 설정 필드만 추가. Application Support 144개 파일 해시 모두 동일.
- 실제 앱에서 기존 Groq/TypeSafe 연결·마이크·손쉬운 사용·단축키 준비 확인. 새 받아쓰기·제스처·음소거·알림음 옵션과 실제 마이크 목록 확인.
- 실제 앱에서 Large v3 캐시(629.5 MB) 탐지, Small/Base 미준비 상태 표시와 비교 제한 확인.
- 설치 백업: `/private/tmp/opennotype-handy-install-20261015T003451`.

## 설치 앱의 실제 비교실 실행

- 마이크 대신 Yuna로 생성한 한영 혼용 합성 파일 8.403447초를 파일 선택 UI로 가져옴.
- 설치된 앱에서 캐시된 Large v3만 실행: 준비 86,067 ms, 인식 2,108 ms, CER 23.1%. 이 한 샘플의 관측값이며 일반 성능 수치가 아님.
- 원문 대비 고유명사가 `OpenO Type A`, 버전이 `0.2.8.2`로 인식된 오류를 확인. 숫자 표기 변환도 CER에 포함되므로 CER과 의미 오류는 구분해야 함.
- 실제 결과·준비/인식 시간·CER·숫자 대조·수동 검토 컨트롤 표시 확인.
- 추가 모델 다운로드·클라우드 요청·기록/사용량 쓰기 없이 실행.
- 이 결과는 자연 발화의 정확도 향상이나 Handy 대비 우위를 입증하지 않음. 기존 AI 정리 기본값과 Large v3 기본 모델 유지.
- 비교 중 상단 문구를 실제 비교 진행 상태로 표시하도록 최종 빌드에서 보완.

최종 설치 실행 파일 SHA256: `3b85af870eacdceb255c4fa9ea90390e257fcf917b06d4f4ec44e6fd6de1b6e1`.
최종 설치 백업: `/private/tmp/opennotype-handy-install-20261015T004348`.
실행·비교 후에도 Application Support 144개 파일이 동일합니다. 기존 설정 필드의 값은 유지하고 새 기본 설정 필드만 추가했습니다. 최종 설치 앱을 다시 열어 새 입력 컨트롤을 확인했습니다.
