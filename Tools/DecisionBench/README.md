# Jev 판정 벤치마크

사전에 작성한 72개의 합성 사례를 비교한다. 사용자 발화와 녹음은 포함하지 않는다. 9개 범주마다 동일 원문의 정상 정리문 4개와 고의 오류 정리문 4개를 둔다. 라벨은 모델 결과를 보기 전에 작성했으며, 의미 변화·추가·누락은 독립 축이다. 일반 외래어의 불필요한 영문화는 의미 오류로 단정하지 않고 후보 표기 선택으로 검사한다.

`main.swift`는 실제 Core 소스와 같은 모듈로 컴파일한다. `DecisionClient.makeRequest`가 생성한 바이트를 전송하고 `DecisionClient.parse`가 응답 전체를 검증한다. 벤치마크에 질문이나 판정 파서를 복제하지 않는다. 출력에는 사용한 소스·fixture·요청의 SHA-256을 기록한다.

```sh
python3 scripts/test_compare_decisions.py
python3 scripts/compare-decisions.py --output build/decision-bench-dry-run.json
```

기본 실행은 네트워크와 API 키에 접근하지 않는다. 실제 호출은 `OPENROUTER_API_KEY`를 런타임 환경에 주입한 뒤 다음과 같이 실행한다. 키 값을 명령행 인수로 전달하지 않는다.

```sh
python3 scripts/compare-decisions.py --live --max-usd 0.10 --workers 4 --deadline 10 \
  --output build/decision-bench-live-10s.json
```

10초 실행에서 완료 응답의 1.5초 초과율과 앱의 제한 시간 내 검사 완료율을 함께 보고한다. 이는 동일 요청의 지연을 관찰하는 비교이다. 별도의 짧은 제한 실행은 `--deadline 1.5`로 수행한다. 동시 요청 자체의 지연 영향을 구분하려면 `--workers 1`을 사용한다. 빠른 smoke 검사는 `--limit 2`로 정상·오류 첫 쌍만 호출한다.

공개 단가는 [OpenRouter Jev 1.13](https://openrouter.ai/typesafe/jev-1.13)의 입력 100만 토큰당 $0.042, 출력 $0이다(2026-10-01 확인). 질문과 후보 기준을 포함한 실제 요청의 UTF-8 바이트 수를 모두 입력 토큰으로 예약하고, 요청마다 4,096개의 framing 토큰 여유를 더한다. 선택한 전체 요청의 예약 합계가 `--max-usd`를 넘으면 키 조회와 HTTP 요청 전에 중단한다. 예약은 공개 가격에 근거한 보수적 상한이며 공급자의 계정 청구 한도는 별도로 관리한다.

자동 재시도와 redirect는 없으며 응답은 128,000바이트까지 읽는다. 반환된 확률과 후보 선택, 수치형 사용량, 오류 종류만 기록한다. 원문 응답, Authorization 헤더, 키는 출력하거나 파일에 저장하지 않는다. 비용이 없는 응답을 $0로 집계하지 않는다.

Noul 확률의 0.5·0.7·0.9별 sensitivity와 false-positive rate를 보고한다. 앱의 보류 기준은 현재 0.9이다. 이 수치와 Choice confidence는 정답 보증이 아니다. 의미·표기 정확도의 분모에는 Core 검증을 완료한 사례만 포함하며, 전체 사례 대비 완료율을 함께 봐야 한다. 72개 합성 사례는 한국어 실제 사용 분포를 대표하는 대규모 평가가 아니다.
