# 반복 정리 개선판 검증 증거

2026-09-12, `codex/typeless-faithful-cleanup` worktree에서 수집했다. 합성 문장·테스트·요청 계획만 포함한다. 사용자 녹음이나 기록, API 키, 새로운 실제 모델 응답은 포함하지 않는다.

| 파일 | 출처와 확인 범위 |
| --- | --- |
| `baseline-swift-test.log` | 기준 보존 커밋 `08dfc0b`의 전체 Swift 테스트: 275개 중 273개 통과, 선택 실행 2개 생략 |
| `improved-swift-test.log` | 최종 정리 규칙을 반영한 전체 Swift 테스트: 278개 중 276개 통과, 선택 실행 2개 생략. 최종 프롬프트 export 테스트 포함 |
| `python-tests.log` | 비교 도구의 오프라인 단위 테스트. 키·실제 네트워크 접근 없이 실행 |
| `build-app.log` | 최종 0.1.8 (9) 개발 앱 패키징과 기존 로컬 인증서를 사용한 strict codesign 검증. 앱 실행·설치·공개 공증 증거는 아님 |
| `cleanup-before.json.gz` | 기준 보존 커밋의 실제 `ProcessingPrompt.build` 출력. `prompt_source_sha256`을 `08dfc0b`의 소스와 대조함 |
| `cleanup-after.json.gz` | 최종 코드의 동일 함수 출력. 전체 Swift 테스트의 export 옵션으로 생성했으며 파일별·사례별 지침 SHA-256도 포함 |
| `comparison-dry-run.json`, `.md` | 대표 13개 사례, 두 버전의 26건 요청 계획. 실제 완료 0건이며 비용 예약은 실측 비용이 아님 |

전후 export의 32개 사례는 fixture와 입력 JSON이 모두 동일하다. fixture SHA-256을 원본 `docs/fixtures/faithful-cleanup.json`과 대조했고, 최종 소스·지침 해시도 확인했다. 기준선 export는 최종 해시 메타데이터 확장 전 형식이므로 `source_sha256` 맵과 사례별 `instructions_sha256`은 없지만, `ProcessingPrompt.swift` 해시와 모든 실제 요청은 보존한다.

합성 사례와 export 보조 테스트를 기준 프롬프트가 유지된 상태에서 먼저 준비한 뒤 전후 요청을 생성했다. 기준선 전체 테스트 수에 새 보조 테스트가 포함되었다고 계산하지 않는다. gzip은 `mtime=0`으로 고정했으며 압축 크기로 토큰이나 비용을 계산하지 않는다.

재현 명령은 [구현 보고서](../faithful-cleanup-implementation.md)의 전후 비교 실행 항목을 따른다. JSON의 원문과 기대 문장은 판정 자료이며 모델 출력이 아니다. Markdown의 기대 문장 일치 여부도 의미 보존의 자동 품질 점수로 사용하지 않는다.
