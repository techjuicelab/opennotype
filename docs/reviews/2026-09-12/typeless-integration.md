# 기본 프롬프트 선택과 기록 재처리

검증일: 2026-09-12. 버전: **0.1.9 (10)**. 기본 정리 프롬프트는 **Codex `233fd1f`를 그대로 유지**한다. 이번에 채택한 변경은 기록 비교·복사·수동 재처리 UI, 한국어 대조 명세와 평가 도구다. 자동 입력과 기존 사용량 수집을 유지하며 추가 자동 검증 모델은 호출하지 않는다.

## 최종 선택과 비교 근거

| 같은 사례끼리 비교한 범위 | Codex `233fd1f` | 비교 후보 |
| --- | --- | --- |
| Codex와 개정 통합 후보의 공통 9개 | 의미 9/9, 정리 7/9, 주요 손실 0 | 개정 후보: 의미 9/9, 정리 6/9, 주요 손실 0 |
| 세 버전 모두 응답한 공통 5개 | 정리 4/5 | Claude `ff9082e`: 정리 2/5, 1차 통합 후보: 정리 2/5 |

위 두 비교는 서로 다른 분모이며 합산하지 않는다. 작은 합성 표본이고 일부 후보 수정은 앞선 실패를 본 뒤 이뤄졌으므로 일반적인 품질 우위나 무손실을 입증하지 않는다. 이번 범위에서 후보를 기본값으로 바꿀 개선 근거가 없어 `ProcessingPrompt.swift`와 `DictationCleanupInstructions.swift`를 Codex `233fd1f`와 정확히 같은 내용으로 복원했다.

Claude 브랜치의 한국어 필러 기능 구분과 대조 사례는 평가 명세·추적 항목 검사에 반영했다. 해당 상세 정책을 합친 1차 후보와, 중복 병합·명제 취소 구분 및 필러 판정을 보완한 개정 후보는 모두 실험 기록으로 보존하며 기본 앱에는 적용하지 않는다. 후행 인사를 텍스트만 보고 삭제하지 않는 기대 사례도 명세로 남겼다. 명세 채택은 실제 출력의 통과를 뜻하지 않는다.

모델 요청은 기존 문장 처리 1회 안에서 이뤄진다. 별도 자동 검증·정규식 삭제·길이 기반 원문 복귀를 추가하지 않았다. 공급자 클라이언트에 원래 있던 전송 재시도와 사용자의 수동 재처리는 별개다. 기존 사용량·입력·실패 녹음 복구 기능도 유지한다.

실제 정리 품질과 단가·지연은 [실제 모델 비교 기록](faithful-cleanup-live-comparison.md)을 따른다. Typeless의 공식 설명과 코드 비교는 [비교 근거](../../typeless-comparison.md)에 정리했다.

이 비교 작업의 API 시도는 총 42건으로 정상 응답 41건과 이전 HTTP 429 1건이다. 모두 합성 텍스트이며 정상 응답 수는 품질 통과 수가 아니다. US$0.10 한도에서 최종 예약액은 US$0.09946845다. 정상 응답 41건의 보고 토큰 기준 비용 추정은 US$0.01746585이며, 429 1건의 비용은 미확인으로 별도 남긴다. 예약액과 실제 청구액은 다르다.

## 기록 화면과 사용량

기록 카드는 보관된 결과를 먼저 보여 준다. `인식 원문과 비교`를 펼치면 처음 인식한 텍스트와 전용 복사 버튼이 나온다. 원문이 결과와 같아도 확인할 수 있다.

`현재 설정으로 다시 처리`에서는 현재 제공자·모델·해당 앱 프로필·개인 사전·번역 언어와 API 비용 가능성을 먼저 표시한다. 버튼을 누르면 저장된 원문만 다시 처리하고 새 결과를 미리 보고 복사할 수 있다. 마이크·STT·외부 앱 입력·기존 기록 변경은 이 동작에 포함되지 않는다. 사용량은 기존 모델별 수집 경로로 기록되며 수집 끄기 설정도 따른다.

과거 번역 언어는 기록 스키마에 없으므로 현재 번역 언어를 표시하고 사용한다. 당시 입력창의 주변 문맥은 새로 읽지 않는다. 선택 문장 수정 기록은 음성 수정 지시만 저장되어 있어 재처리를 막고 이유를 안내한다. 저장 구조를 추측하여 불완전한 편집을 실행하지 않는다.

재처리 취소·새 녹음·개별/전체 기록 삭제 후 늦은 응답은 화면에 게시하지 않는다. 녹음을 실제로 시작하지 못한 경우 이미 완료된 재처리 결과는 유지한다. 독립 검토에서 이 완료 결과가 먼저 지워지는 문제를 발견해 수정했다.

## 검증

| 확인 | 결과와 경계 |
| --- | --- |
| 전체 Swift 테스트 | 300개 발견, 298개 통과, 선택 실행 모델 테스트 2개 제외, 실패 0개. 재처리 회귀 테스트 10개 포함. |
| 비교 도구 오프라인 테스트 | 45개 통과. 실행 전 예약 한도, 파일·출처·입력 변이, 실패·중단 요청의 재전송 방지, 한도 초과·응답 모델 불일치 후 재개 차단 포함. |
| 명세 | 의미 보존 32개, 한국어 대조 38개. 대조 명세 54개 추적 항목 확인. 별도 비교 명세 10개. 명세 수와 위 실측 비교의 공통 사례 분모를 구별하며 명세 검사 자체는 모델 품질 증거가 아니다. |
| 실제 프롬프트 재현 | 실제 Swift 소스와 의존 파일을 컴파일해 추출했다. 최종 채택한 두 소스 파일은 Codex `233fd1f`와 동일하며, 채택 export의 10개 요청도 평가한 Codex export와 완전히 일치한다. |
| 지시 길이 | 최종 채택한 Codex 프롬프트는 받아쓰기 형식·말투 20조합에서 최대 9,112 UTF-8 바이트, 테스트 상한 10,400 이내다. 바이트 수는 청구 토큰 수가 아니다. |
| 개발 앱 빌드 | 최종 채택 코드의 0.1.9 (10) 개발 빌드와 strict codesign 검증 통과. 로컬 개발 서명과 공개 배포 서명·공증을 구분한다. |
| 네이티브 화면 | 별도 debug 앱의 합성 기록으로 원문·결과, 재처리 설정, 현재 번역 언어, 선택문 수정 제한을 접근성 트리와 라이트·다크 화면으로 확인했다. 실제 사용자의 기록·키를 읽거나 마이크·API를 호출하지 않는 미리보기다. |

재처리 테스트는 주입한 HTTP·저장·녹음 경계로 요청 1회, 입력과 설정 스냅샷, 사용량, 오류, 취소·삭제·늦은 응답을 검증한다. 실제 공급자 비교는 별도 CLI에서 프롬프트를 평가한 것이므로 네이티브 앱에서 실제 키 저장·클릭·과금·삽입까지 한 번에 확인한 증거로 확대하지 않는다.

실제 음성·마이크·STT 및 Typeless 앱의 같은 오디오 결과는 이번에 측정하지 않았다. 외부 앱 입력은 기존 0.1.7 검증을 보존했으며 이번 통합에서 새로 전체 앱 행렬을 실행하지 않았다.

## 재현과 Git 보존

실제 평가에 사용한 요청과 후보 소스는 [integration-evidence](integration-evidence/)에 보존한다. 파일 이름에 `integrated-final`이 있어도 개정 실험 후보를 뜻하며 최종 채택 프롬프트는 아니다.

| 증거 | 파일 |
| --- | --- |
| 최종 앱에 채택한 실제 요청 | [adopted-production.json.gz](integration-evidence/adopted-production.json.gz) |
| Codex 비교 기준 요청 | [threeway-codex.json.gz](integration-evidence/threeway-codex.json.gz) |
| Claude 비교 요청 | [threeway-claude.json.gz](integration-evidence/threeway-claude.json.gz) |
| 1차 통합 후보 요청 | [threeway-integrated.json.gz](integration-evidence/threeway-integrated.json.gz) |
| 개정 통합 후보 요청 | [integrated-final.json.gz](integration-evidence/integrated-final.json.gz) |
| 개정 후보의 소스 스냅샷 | [ProcessingPrompt.swift.txt](integration-evidence/candidate-sources/ProcessingPrompt.swift.txt), [DictationCleanupInstructions.swift.txt](integration-evidence/candidate-sources/DictationCleanupInstructions.swift.txt) |
| 독립 채점 대응과 비용 집계 | [evaluation-summary.json](integration-evidence/evaluation-summary.json) |

정확한 요청 export와 소스별 해시로 채택 버전과 후보를 구별한다. 원본 평가 보고서와 HTTP 실패 기록도 같은 증거 폴더에 보존하며, 실행별 설명은 실제 모델 비교 기록을 따른다.

```sh
swift test
python3 -B -m unittest discover -s scripts -p 'test_compare_cleanup*.py'
DEVELOPMENT_SIGNING_IDENTITY='TechJuice Local Code Signing' ./scripts/build-usage-preview.sh dark history
```

`build-usage-preview.sh`의 두 번째 인자를 생략하면 기존 사용량 미리보기를 만든다. 합성 기록 미리보기는 DEBUG 및 별도 번들 ID에서만 활성화된다. 실제 앱의 데이터로 바뀌지 않는다.

작업 전 `git pull --ff-only`는 최신 상태임을 확인했다. 기존 미커밋 파일 19개는 `08dfc0b`에 보존했고, 새 `codex/typeless-integration`에서 원격 Claude 브랜치의 변경을 검토했다. 최종 선택은 Codex 기본 프롬프트 유지와 UI·명세·평가 도구 채택이다. 원래 작업 폴더의 19개 파일은 최종 병합 전에도 `08dfc0b`와 해시가 모두 일치함을 다시 확인했다. 추가 안전 백업은 stash `4638533762d3eb0044815b8370fbb494df024611` (`backup/typeless-integration-20260912…`)에 보존했다. 최종 합병 결과는 별도 Git 검증으로 남긴다.
