# 통합 선택의 검증 증거

2026-09-12의 합성 문장·검증용 샘플만 포함한다. 실제 사용자 녹음·기록·키·인증 헤더·앱 저장소는 포함하지 않는다. 모델의 실제 출력과 기대 문장, 원본 후보와 채택 코드를 구별한다.

- `evaluation-summary.json`: 두 독립 평가자의 판정, 익명 라벨→버전 대응, 동일 사례의 토큰·지연·비용, 최종 채택 결정.
- `budget-ledger.json`: 이전 인터뷰 단계까지 포함한 총 US$0.10 예약 한도. 이미 시도한 실패 요청은 환급하지 않고 취소한 미시작분만 재배정했다.
- `live-round1*.json.gz`: 인터뷰 전에 일부 실행한 기존 전후 비교와 첫 429 중단 상태. 최종 후보 점수에 합산하지 않는다.
- `integration-live.json.gz`: 최초 세 버전 계획 30건 중 17건 실행 후 후보 수정을 위해 중단. Codex 6건, Claude 5건, 첫 통합 6건이다. 결과가 없는 항목은 미시작이다.
- `integration-final-live.json.gz`: 이름의 final은 당시 마지막 실험 후보를 뜻한다. **채택한 프로덕션 프롬프트가 아니다.** 개정 후보 10건 모두 실행했다.
- `codex-completion-live.json.gz`: 아직 호출하지 않았던 Codex FC32·MC01·MC02 각 1건. 앞서 받은 Codex 6건과 합쳐 서로 다른 9사례다.
- `threeway-codex.json.gz`, `threeway-claude.json.gz`: `233fd1f`, `ff9082e`의 실제 Swift 구현에서 추출한 요청과 출처 해시.
- `threeway-integrated.json.gz`, `integrated-final.json.gz`: 첫 통합·개정 후보의 정확한 요청. 파일명으로 채택 여부를 추측하지 않는다.
- `adopted-production.json.gz`: **최종 채택 코드**의 실제 요청. source 해시 및 모든 10개 요청이 Codex `233fd1f` export와 동일하다. 이 가운데 9개에 실제 Codex 응답이 있다.
- `candidate-sources/*.swift.txt`: 개정 후보의 소스 2개. 현재 앱에는 적용하지 않았다. 최초 후보는 해당 요청 export에 완전한 지시문·입력을 보존했다.
- `*-blind-batch*.json`, `*-review-*.json`, `*-blind-mapping*.json`: 익명 입력, 독립 채점, 별도 매핑. 평가자는 매핑·상대 채점을 읽지 않았다. 재검토에 다시 표시한 이전 응답은 새로운 모델 호출이나 독립 사례가 아니다.
- `integration-review-policy.json`: 의미 보존·정리 분리 및 FC04 지시어 보완. 출력 판독 전에 정한 공통 보완이며 실제 API에 보낸 동결 fixture를 수정하지 않았다.
- `swift-test.log`, `build-app.log`: 채택 코드의 전체 테스트와 0.1.9 개발 앱 서명 빌드 로그. Swift 300개 중 298개 통과, 선택 실행 2개 제외, 실패 0개.
- `candidate-swift-test.log`, `candidate-build-app.log`: 프롬프트 후보가 코드 검사에는 통과해도 실제 언어 평가에서는 채택되지 않을 수 있음을 보여 주는 별도 로그.
- `python-tests.txt`: 도구 실행 결과에서 보존한 비교 도구 45개 테스트 통과 기록. 이 테스트는 네트워크를 사용하지 않는다.
- `ui-checks.md`: 합성 기록으로 수행한 네이티브 라이트·다크 화면 확인 범위. 실제 사용자 데이터나 공급자 호출까지 검증했다고 해석하지 않는다.
- `manifest.sha256`: 이 폴더 파일의 SHA-256 목록.

JSON 압축은 `gzip -dc 파일.json.gz`로 읽을 수 있다. 프롬프트의 출처 해시와 실제 요청을 함께 확인할 수 있으며, 기본 비교 명령은 새 키·API 호출 없는 계획만 만든다. 자세한 결과와 재현 명령은 [실제 모델 비교 보고서](../faithful-cleanup-live-comparison.md)를 참고한다.
