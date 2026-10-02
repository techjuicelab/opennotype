# Jev 연결 방식 선택 및 실측 — 2026-10-01

## 변경

0.1.12 빌드 14는 설정에서 **OpenRouter 키 하나로 사용** 또는 **Jev API 키로 직접 연결**을 선택한다. 기존 설치는 OpenRouter 경로와 기존 검토 모드를 유지한다. TypeSafe 직접 연결은 별도 Keychain 계정에 저장하며, 음성·문장 제공자와 독립적이다. 연결 방식·키 변경은 이전 검토를 취소하고 새 녹음부터 적용한다. 늦은 TypeSafe 키 저장·읽기가 새 OpenRouter 검토를 취소하던 경합도 회귀 검사와 함께 수정했다.

**Jev 연결 테스트**는 검토 모드가 꺼져 있어도 명시적으로 합성 문장 한 건을 보낸다. 녹음·자동 입력·문장 기록은 만들지 않으며 사용량 수집 설정을 따른다. 직접 연결 사용량은 클라우드로 표시하고, TypeSafe의 토큰 기반 추정 비용을 실제 보고 비용과 구분한다.

## 검증

- 실제 Core 소스와 XCTest 본문을 headless adapter로 실행: 44/44 통과.
- 실제 AppModel/Core/Runtime 및 사용량·설정 마이그레이션 headless 검사: 46/46 통과.
- Python 전체: 162개 실행, 161 통과, 환경에 따른 1개 건너뜀. 벤치마크 검사는 19개.
- macOS 26.5 SDK release SwiftUI 빌드 및 `codesign --verify --deep --strict` 통과. 로컬 CLT에는 XCTest가 없어 정식 XCTest는 GitHub의 Xcode CI에서 별도로 확인한다.
- `/Applications/OpenNoType.app`에 0.1.12(14)를 설치하고 이전 앱을 백업했다. 실행 파일 SHA-256: `11be17ae557a37d96d827972dd7382e54277d5da7d197e65ad8899607493602b`. Developer ID 서명·공증·공개 릴리스는 하지 않았다.
- 설치 앱의 **Jev 연결 테스트**에서 OpenRouter(`typesafe/jev-1.13-20260917`)와 TypeSafe 직접(`jev-1.13.0`) 모두 성공했다. 직접 연결 완료 표시는 0.22초였다. 첫 OpenRouter 테스트의 앱 전체 완료 표시는 사용량 저장 등 로컬 작업을 포함해 6.16초였으며, 이를 API 지연으로 해석하지 않는다. 사용량 화면의 TypeSafe 클라우드 분류·입력 962/출력 57 토큰·추정 비용 표시도 확인했다. 최종 설정은 TypeSafe 직접 연결 + 입력 후 검토이며 Groq 음성 인식과 OpenRouter 문장 정리를 유지했다. 실제 사용자 발화·다른 앱 자동 입력은 이번 연결 시험에 포함하지 않았다.

## 같은 72개 합성 사례의 실제 API 결과

production Swift 요청 생성기·응답 파서·요금 계산을 공유했다. 원문 36개에 정상/오류 정리 결과를 짝지은 72건이며, 동일 fixture와 질문을 두 경로에서 사용했다. 순차 호출, 자동 재시도 없음, 평가 제한 10초로 실행하고 앱의 1.5초 제한 내 완료 건수를 별도로 집계했다.

| 지표 | OpenRouter | TypeSafe 직접 |
| --- | ---: | ---: |
| 유효 판정 / 요청 | 72 / 72 | 72 / 72 |
| 1.5초 내 유효 판정 | 72 / 72 | 72 / 72 |
| 응답 중앙값 | 0.210초 | 0.176초 |
| 응답 p95 | 0.693초 | 0.236초 |
| 현재 보호 기준 0.9의 의미 오류 탐지 | 21 / 30 | 19 / 30 |
| 정상 의미 문장 오경보 | 0 / 42 | 0 / 42 |
| 표기 선택 일치 | 39 / 52 (75%) | 39 / 52 (75%) |
| 72건 비용 | $0.003649338 공급자 보고 | 약 $0.003649338 추정 |

모델 응답 식별자는 각각 `typesafe/jev-1.13-20260917`, `jev-1.13.0`이다. 이번 측정에서는 직접 연결이 더 빨랐지만 표기 일치율은 같았고, 보호 기준에서 의미 오류 11개를 놓쳤다. 직접 연결이 더 정확하다고 결론 내리거나 자동 치환·자동 사전 학습을 켤 근거가 아니다. 임계값을 이번 결과에 맞춰 변경하지 않았다. 사용자는 우선 **입력 후 검토**로 결과를 확인할 수 있다.

평가 한계: 정상 사례 36개 중 23개는 마침표 외 원문과 같고, `uncertain`은 독립 상황 하나뿐이다. 한국어 전체 정확도·실제 음성 인식·문장 생성·자동 입력의 종단 품질을 대표하지 않는다. confidence와 위험 점수는 정답률이 아니다.

초기 TypeSafe 72건은 평가 도구가 완료된 응답 소켓에 timeout을 다시 설정해 `connection_failed`로 기록했다. 실제 서버 처리 여부·청구는 미확인이므로 무료 또는 요청되지 않음으로 간주하지 않는다. Content-Length + Connection: close를 사용하는 실제 합성 HTTP 서버 회귀 검사를 추가한 후 72건을 다시 실행했으며, 표는 수정 후 결과다. 앱의 URLSession 통신 경로에는 이 Python 오류가 없다.

증거: [OpenRouter 원자료](jev-direct-evidence/openrouter.json.gz), [TypeSafe 원자료](jev-direct-evidence/typesafe.json.gz). 키·개인 발화·원시 HTTP 응답은 포함하지 않는다. fixture SHA-256은 `805363c07b4dbbb7e9c5d9e35ec96e929441018e738a32ca249f71cdb7018ff1`이다.

계약 및 단가: [TypeSafe API](https://docs.typesafe.ai/api), [TypeSafe 모델](https://docs.typesafe.ai/models), [OpenRouter Jev 모델](https://openrouter.ai/typesafe/jev-1.13). 사용 방법은 [Jev 문장 검토](../../jev-review.md)를 따른다.
