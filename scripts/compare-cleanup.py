#!/usr/bin/env python3
"""Compare exported production prompts on synthetic fixtures; dry-run is the default.

No third-party packages, key-store access, retries, or redirect following. This is
an opt-in evaluation utility, not part of the app's production dictation pipeline.
"""

import argparse
import gzip
import hashlib
import http.client
import json
import math
import os
from pathlib import Path
import re
import ssl
import sys
import tempfile
import time
from datetime import datetime, timezone
from decimal import Decimal, InvalidOperation


ENDPOINT = "https://api.groq.com/openai/v1/chat/completions"
PRICING_URL = "https://console.groq.com/docs/models"
PRICING_CHECKED_AT = "2026-09-12"
RATES = {
    "openai/gpt-oss-120b": (Decimal("0.15"), Decimal("0.60")),
    "openai/gpt-oss-20b": (Decimal("0.075"), Decimal("0.30")),
}
MAX_BUDGET = Decimal("0.10")
MAX_COMPLETION_TOKENS = 1024
# Count each UTF-8 byte as a token, including the schema, with ample framing
# allowance. This intentionally over-reserves; it is not a tokenizer estimate.
INPUT_FRAMING_ALLOWANCE = 2048
MAX_RESPONSE_BYTES = 1_000_000
EXPORT_STATUS = "synthetic_fixture_prompts_not_live_model_results"
RESULT_SCHEMA = {
    "type": "object", "properties": {"text": {"type": "string"}},
    "required": ["text"], "additionalProperties": False,
}
REVIEW_NOTICE = (
    "기대 문장과의 완전 일치는 의미 품질 점수가 아닙니다. 자연스러운 다른 표현도 가능하며, "
    "보존 조건과 금지 변화를 사람이 별도로 검토해야 합니다. 합성 텍스트 평가이며 "
    "실제 음성 인식·앱 입력·Typeless 실측 결과가 아닙니다."
)
RATE_LIMIT_HEADERS = {
    "retry-after", "x-ratelimit-limit-requests", "x-ratelimit-limit-tokens",
    "x-ratelimit-remaining-requests", "x-ratelimit-remaining-tokens",
    "x-ratelimit-reset-requests", "x-ratelimit-reset-tokens",
}


class EvaluationError(Exception):
    """A safe user-facing error; never include keys or raw provider errors."""


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def encoded(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")


def read_export(path):
    try:
        if Path(path).suffix == ".gz":
            with gzip.open(path, "rb") as source:
                data = source.read(10_000_001)
        else:
            data = Path(path).read_bytes()
        if len(data) > 10_000_000:
            raise EvaluationError("프롬프트 export 파일의 압축 해제 크기가 너무 큽니다.")
        document = json.loads(data)
    except (OSError, ValueError) as error:
        raise EvaluationError("프롬프트 export JSON 파일을 읽을 수 없습니다.") from error
    if not isinstance(document, dict) or document.get("schema_version") != 1 or document.get("status") != EXPORT_STATUS:
        raise EvaluationError("지원하는 합성 fixture export 형식이 아닙니다.")
    for key in ("fixture_sha256", "prompt_source_sha256"):
        if not isinstance(document.get(key), str) or not re.fullmatch(r"[0-9a-f]{64}", document[key]):
            raise EvaluationError("export의 SHA-256 출처 정보가 없습니다.")
    cases = document.get("cases")
    if not isinstance(cases, list) or not cases:
        raise EvaluationError("export에 평가 사례가 없습니다.")
    indexed = {}
    for case in cases:
        if not isinstance(case, dict) or not isinstance(case.get("fixture"), dict):
            raise EvaluationError("평가 사례의 fixture 형식이 올바르지 않습니다.")
        fixture = case["fixture"]
        case_id = fixture.get("id")
        if not isinstance(case_id, str) or not re.fullmatch(r"[A-Za-z0-9_-]{1,100}", case_id) or case_id in indexed:
            raise EvaluationError("평가 사례 ID가 잘못되었거나 중복되었습니다.")
        if not isinstance(fixture.get("expected_text"), str):
            raise EvaluationError("평가 사례의 기대 문장이 없습니다.")
        for key in ("preservation_conditions", "forbidden_changes"):
            if not isinstance(fixture.get(key), list) or not all(isinstance(value, str) for value in fixture[key]):
                raise EvaluationError("평가 사례의 사람이 검토할 조건이 없습니다.")
        if not isinstance(case.get("instructions"), str) or not case["instructions"].strip():
            raise EvaluationError("평가 사례의 시스템 프롬프트가 비어 있습니다.")
        if "instructions_sha256" in case and case["instructions_sha256"] != sha256(case["instructions"].encode("utf-8")):
            raise EvaluationError("평가 사례의 시스템 프롬프트와 SHA-256이 일치하지 않습니다.")
        if not isinstance(case.get("input"), str):
            raise EvaluationError("평가 사례의 입력이 JSON 문자열이 아닙니다.")
        try:
            payload = json.loads(case["input"])
        except ValueError as error:
            raise EvaluationError("평가 사례의 입력 JSON이 올바르지 않습니다.") from error
        mode = fixture.get("mode")
        field = "edit_instruction" if mode == "rewrite" else "spoken_text"
        if (mode not in ("dictation", "translation", "rewrite") or not isinstance(payload, dict)
                or payload.get("mode") != mode or payload.get(field) != fixture.get("stt_input")
                or not isinstance(fixture.get("stt_input"), str)):
            raise EvaluationError("export 입력이 fixture의 원문 또는 모드와 다릅니다.")
        if mode == "rewrite" and payload.get("original_text") != fixture.get("selected_text"):
            raise EvaluationError("선택 문장 수정의 원문이 fixture와 다릅니다.")
        indexed[case_id] = case
    return {"document": document, "cases": indexed, "sha256": sha256(data)}


def paired_cases(before, after, ids=None):
    if before["document"]["fixture_sha256"] != after["document"]["fixture_sha256"]:
        raise EvaluationError("기존/개선 export의 fixture SHA가 다릅니다. 같은 fixture로 다시 export해 주세요.")
    if set(before["cases"]) != set(after["cases"]):
        raise EvaluationError("기존/개선 export의 사례 ID가 서로 다릅니다.")
    for case_id, first in before["cases"].items():
        second = after["cases"][case_id]
        if first["fixture"] != second["fixture"] or first["input"] != second["input"]:
            raise EvaluationError("기존/개선 export의 fixture 또는 입력이 다릅니다. 프롬프트만 비교할 수 있습니다.")
    chosen = list(before["cases"])
    if ids is not None:
        chosen = [value.strip() for value in ids.split(",")]
        if not all(chosen) or len(set(chosen)) != len(chosen) or any(value not in before["cases"] for value in chosen):
            raise EvaluationError("--ids에는 존재하는 사례 ID를 중복 없이 쉼표로 구분해 주세요.")
    return [(case_id, before["cases"][case_id], after["cases"][case_id]) for case_id in chosen]


def request_body(case, model):
    return {
        "model": model, "stream": False, "max_completion_tokens": MAX_COMPLETION_TOKENS,
        "messages": [{"role": "system", "content": case["instructions"]},
                     {"role": "user", "content": case["input"]}],
        "response_format": {"type": "json_schema", "json_schema": {
            "name": "dictation_result", "strict": True, "schema": RESULT_SCHEMA}},
        "include_reasoning": False, "reasoning_effort": "low",
    }


def reservation(case, model):
    # Counting the entire wire JSON also covers schema and message metadata.
    upper_input = len(encoded(request_body(case, model))) + INPUT_FRAMING_ALLOWANCE
    if upper_input + MAX_COMPLETION_TOKENS > 131_072:
        raise EvaluationError("평가 입력의 보수적 상한이 모델 문맥 한도를 넘습니다.")
    input_rate, output_rate = RATES[model]
    cost = (Decimal(upper_input) * input_rate + Decimal(MAX_COMPLETION_TOKENS) * output_rate) / 1_000_000
    return upper_input, cost


def make_plan(before, after, model, ids, repetitions, max_usd):
    if model not in RATES:
        raise EvaluationError("가격을 확인한 GPT-OSS 모델만 평가할 수 있습니다.")
    if isinstance(repetitions, bool) or not isinstance(repetitions, int) or not 1 <= repetitions <= 100:
        raise EvaluationError("--repetitions는 1~100 사이 정수여야 합니다.")
    if not max_usd.is_finite() or not Decimal("0") < max_usd <= MAX_BUDGET:
        raise EvaluationError("--max-usd는 0보다 크고 0.10 이하인 값이어야 합니다.")
    pairs = paired_cases(before, after, ids)
    requests = []
    total = Decimal("0")
    for run in range(1, repetitions + 1):
        for case_id, first, second in pairs:
            # Alternate A/B order to reduce a fixed cache/order advantage.
            variants = [("before", first), ("after", second)]
            if run % 2 == 0:
                variants.reverse()
            for variant, case in variants:
                upper_input, cost = reservation(case, model)
                total += cost
                requests.append({"id": case_id, "variant": variant, "run": run,
                                 "input_token_upper_bound": upper_input,
                                 "reserved_usd": str(cost), "prompt_sha256": sha256(encoded({
                                     "instructions": case["instructions"], "input": case["input"]}))})
    return {
        "schema_version": 1, "mode": "dry_run", "notice": REVIEW_NOTICE,
        "endpoint": ENDPOINT, "model": model, "repetitions": repetitions,
        "max_completion_tokens": MAX_COMPLETION_TOKENS,
        "max_usd": str(max_usd), "reserved_total_usd": str(total), "budget_allows_execution": total <= max_usd,
        "reservation_policy": "UTF-8 wire bytes + 2048 framing tokens, uncached input rates, 1024 completion tokens; reservations never refunded",
        "pricing": {"checked_at": PRICING_CHECKED_AT, "source": PRICING_URL,
                    "input_per_million_usd": str(RATES[model][0]), "output_per_million_usd": str(RATES[model][1]),
                    "note": "공개 가격 기준 추정. 캐시 할인·세금·크레딧 제외. 공급자의 실제 청구 한도를 설정하는 기능은 아닙니다."},
        "exports": {"before_sha256": before["sha256"], "after_sha256": after["sha256"],
                    "fixture_sha256": before["document"]["fixture_sha256"],
                    "before_prompt_source_sha256": before["document"]["prompt_source_sha256"],
                    "after_prompt_source_sha256": after["document"]["prompt_source_sha256"],
                    "before_source_sha256": before["document"].get("source_sha256"),
                    "after_source_sha256": after["document"].get("source_sha256")},
        "fixtures": [first["fixture"] for _, first, _ in pairs], "requests": requests, "results": [],
    }


def plan_hash(plan):
    keys = ("schema_version", "endpoint", "model", "repetitions", "max_completion_tokens", "max_usd",
            "reserved_total_usd", "budget_allows_execution", "pricing", "exports", "fixtures", "requests")
    try:
        identity = {key: plan[key] for key in keys}
        if "variant_exports" in plan:
            identity["variant_exports"] = plan["variant_exports"]
        identity["max_usd"] = str(Decimal(identity["max_usd"]).normalize())
        return sha256(encoded(identity))
    except (KeyError, InvalidOperation, TypeError, ValueError) as error:
        raise EvaluationError("실행 계획의 식별 정보를 확인할 수 없습니다.") from error


def resume_plan(path, planned):
    try:
        previous = json.loads(Path(path).read_bytes())
    except (OSError, ValueError) as error:
        raise EvaluationError("재개할 기존 실행 보고서를 읽을 수 없습니다.") from error
    if not isinstance(previous, dict) or previous.get("mode") != "executed":
        raise EvaluationError("--resume에는 실제 실행한 기존 보고서가 필요합니다.")
    if previous.get("stop_reason") in ("provider_exceeded_reserved_token_bound", "unexpected_reported_model"):
        # The original reservation no longer bounds the attempts already sent.
        # Keeping their old reservation while sending the remainder is unsafe.
        raise EvaluationError("응답 토큰 상한 초과 또는 다른 모델 응답으로 비용 예약의 전제가 깨졌습니다. 실제 사용 비용을 확인하기 전에는 이 보고서를 재개할 수 없습니다.")
    previous_hash = plan_hash(previous)
    if previous.get("plan_sha256", previous_hash) != previous_hash or previous_hash != plan_hash(planned):
        raise EvaluationError("재개 계획이 기존 export·모델·ID·회차·예산·요청 계획과 다릅니다.")
    results = previous.get("results")
    requests = planned["requests"]
    if not isinstance(results, list) or len(results) > len(requests):
        raise EvaluationError("기존 결과가 실행 계획의 연속된 앞부분이 아닙니다.")
    for result, request in zip(results, requests):
        if (not isinstance(result, dict) or any(result.get(key) != value for key, value in request.items())
                or not isinstance(result.get("status"), str) or not result["status"]
                or result.get("manual_review_required") is not True):
            raise EvaluationError("기존 결과의 순서·요청 식별자·예약액이 계획과 다릅니다. 재실행하지 않습니다.")
    previous["plan_sha256"] = previous_hash
    return previous


def validate_interval(value):
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or not 0 <= value <= 60:
        raise EvaluationError("--interval-seconds는 0~60 사이의 유한한 숫자여야 합니다.")
    return float(value)


def rate_limit_headers(response):
    headers = {}
    for name, value in response.getheaders():
        name = name.lower()
        if name in RATE_LIMIT_HEADERS and isinstance(value, str) and len(value) <= 200 and "\r" not in value and "\n" not in value:
            headers[name] = value
    return headers


def send_request(case, model, api_key):
    """One direct HTTPS request. http.client never follows redirects."""
    connection = http.client.HTTPSConnection("api.groq.com", timeout=120, context=ssl.create_default_context())
    try:
        connection.request("POST", "/openai/v1/chat/completions", body=encoded(request_body(case, model)),
                           headers={"Authorization": "Bearer " + api_key, "Content-Type": "application/json",
                                    "Accept": "application/json", "Cache-Control": "no-store"})
        response = connection.getresponse()
        status = response.status
        limits = rate_limit_headers(response)
        if not 200 <= status < 300:
            # Never expose an error body; it can echo authentication or input.
            return {"http_status": status, "error": "redirect_rejected" if 300 <= status < 400 else "http_error", "rate_limits": limits}
        body = response.read(MAX_RESPONSE_BYTES + 1)
        if len(body) > MAX_RESPONSE_BYTES:
            return {"http_status": status, "error": "response_too_large", "rate_limits": limits}
        try:
            obj = json.loads(body)
        except (ValueError, UnicodeDecodeError):
            return {"http_status": status, "error": "invalid_response_json", "rate_limits": limits}
        if not isinstance(obj, dict):
            return {"http_status": status, "error": "invalid_response_json", "rate_limits": limits}
        return {"http_status": status, "object": obj, "rate_limits": limits}
    except (OSError, http.client.HTTPException):
        return {"http_status": None, "error": "transport_error"}
    finally:
        connection.close()


def counter(value):
    return value if isinstance(value, int) and not isinstance(value, bool) and value >= 0 else None


def analyze_response(response, fixture, model):
    result = {"http_status": response.get("http_status"), "status": response.get("error", "ok"),
              "text": None, "exact_expected_match": None, "manual_review_required": True,
              "input_tokens": None, "output_tokens": None, "cached_input_tokens": None,
              "reasoning_tokens": None, "estimated_uncached_cost_usd": None, "reported_model": None,
              "rate_limits": response.get("rate_limits", {})}
    obj = response.get("object")
    if not isinstance(obj, dict):
        return result
    reported = obj.get("model")
    if isinstance(reported, str) and re.fullmatch(r"[A-Za-z0-9_./:-]{1,200}", reported):
        result["reported_model"] = reported
    usage = obj.get("usage") if isinstance(obj.get("usage"), dict) else {}
    result["input_tokens"] = counter(usage.get("prompt_tokens"))
    result["output_tokens"] = counter(usage.get("completion_tokens"))
    input_details = usage.get("prompt_tokens_details")
    output_details = usage.get("completion_tokens_details")
    if isinstance(input_details, dict):
        result["cached_input_tokens"] = counter(input_details.get("cached_tokens"))
    if isinstance(output_details, dict):
        result["reasoning_tokens"] = counter(output_details.get("reasoning_tokens"))
    inp, out = result["input_tokens"], result["output_tokens"]
    if inp is not None and out is not None and (reported is None or reported == model):
        result["estimated_uncached_cost_usd"] = str((Decimal(inp) * RATES[model][0] + Decimal(out) * RATES[model][1]) / 1_000_000)
    choices = obj.get("choices")
    if not isinstance(choices, list) or len(choices) != 1 or not isinstance(choices[0], dict):
        result["status"] = "invalid_choices"
        return result
    choice = choices[0]
    message = choice.get("message")
    if choice.get("finish_reason") != "stop":
        result["status"] = "incomplete_output"
        return result
    if not isinstance(message, dict) or message.get("refusal") or message.get("tool_calls"):
        result["status"] = "refusal_or_tools"
        return result
    try:
        text_object = json.loads(message.get("content", ""))
    except (ValueError, TypeError):
        result["status"] = "invalid_text_json"
        return result
    if not isinstance(text_object, dict) or set(text_object) != {"text"} or not isinstance(text_object["text"], str):
        result["status"] = "invalid_text_schema"
        return result
    result["text"] = text_object["text"]
    result["exact_expected_match"] = result["text"] == fixture["expected_text"]
    if not result["text"].strip():
        result["status"] = "expected_empty" if not fixture["expected_text"].strip() else "unexpected_empty"
    return result


def execute_plan(plan, before, after, api_key, sender=send_request, save=None,
                 interval_seconds=0, clock=time.monotonic, sleeper=time.sleep, variants=None):
    interval_seconds = validate_interval(interval_seconds)
    if not plan["budget_allows_execution"]:
        raise EvaluationError("최악 비용 예약액이 --max-usd를 넘습니다. --ids로 사례를 줄여 주세요.")
    sources = {"before": before, "after": after} if variants is None else variants
    if "variant_exports" in plan or variants is not None:
        metadata = plan.get("variant_exports")
        if not isinstance(sources, dict) or not isinstance(metadata, dict) or set(sources) != set(metadata):
            raise EvaluationError("실행 계획과 variant export 구성이 다릅니다.")
        fixtures = {fixture["id"]: fixture for fixture in plan["fixtures"]}
        for label, source in sources.items():
            expected = {"sha256": source["sha256"],
                        "fixture_sha256": source["document"]["fixture_sha256"],
                        "prompt_source_sha256": source["document"]["prompt_source_sha256"],
                        "source_sha256": source["document"].get("source_sha256")}
            if metadata[label] != expected:
                raise EvaluationError("실행 계획 이후 variant export의 출처가 바뀌었습니다.")
        # Validate every request before sending any, including requests after a resume boundary.
        for item in plan["requests"]:
            source = sources.get(item["variant"])
            case = source["cases"].get(item["id"]) if source else None
            if case is None or case["fixture"] != fixtures.get(item["id"]):
                raise EvaluationError("variant 요청의 사례가 실행 계획과 다릅니다.")
            upper, cost = reservation(case, plan["model"])
            if (item["prompt_sha256"] != sha256(encoded({"instructions": case["instructions"], "input": case["input"]}))
                    or item["input_token_upper_bound"] != upper or Decimal(item["reserved_usd"]) != cost):
                raise EvaluationError("variant 요청의 프롬프트 또는 예약액이 실행 계획과 다릅니다.")
    if not isinstance(api_key, str) or not api_key.strip() or "\r" in api_key or "\n" in api_key:
        raise EvaluationError("--execute에는 유효한 GROQ_API_KEY 환경변수가 필요합니다.")
    api_key = api_key.strip()
    completed = len(plan["results"])
    if completed:
        plan.setdefault("resume_events", []).append({"at": datetime.now(timezone.utc).isoformat(),
            "after_requests": completed, "previous_stop_reason": plan.get("stop_reason"), "interval_seconds": interval_seconds})
    plan["mode"] = "executed"
    plan.setdefault("started_at", datetime.now(timezone.utc).isoformat())
    plan["plan_sha256"] = plan_hash(plan)
    plan["interval_seconds"] = interval_seconds
    plan["stop_reason"] = None
    # On resume conservatively wait a full interval before the first new request;
    # older reports lack a reusable monotonic start time. Completed and uncertain
    # attempts remain reserved and are never submitted again.
    last_start = clock() if completed else None
    for item in plan["requests"][completed:]:
        case = sources[item["variant"]]["cases"][item["id"]]
        if last_start is not None:
            remaining = interval_seconds - (clock() - last_start)
            if remaining > 0:
                sleeper(remaining)
        pending = dict(item, **analyze_response({"error": "request_started_result_unknown"}, case["fixture"], plan["model"]))
        pending["latency_ms"] = None
        pending["request_started_at"] = datetime.now(timezone.utc).isoformat()
        plan["results"].append(pending)
        if save is not None:
            save(plan)
        started = clock()
        last_start = started
        response = sender(case, plan["model"], api_key)
        result = dict(item, **analyze_response(response, case["fixture"], plan["model"]))
        result["latency_ms"] = round((clock() - started) * 1000, 1)
        result["request_started_at"] = pending["request_started_at"]
        if result["text"] is not None:
            result["text"] = result["text"].replace(api_key, "[REDACTED]")
        result["rate_limits"] = {name: value.replace(api_key, "[REDACTED]") for name, value in result["rate_limits"].items()}
        plan["results"][-1] = result
        # Do not release reservations for errors or missing usage. Stop if the
        # provider contradicts a bound, routes a different model, or rate-limits.
        if ((result["input_tokens"] or 0) > item["input_token_upper_bound"]
                or (result["output_tokens"] or 0) > MAX_COMPLETION_TOKENS):
            plan["stop_reason"] = "provider_exceeded_reserved_token_bound"
        elif result["reported_model"] is not None and result["reported_model"] != plan["model"]:
            plan["stop_reason"] = "unexpected_reported_model"
        elif result["http_status"] == 429:
            plan["stop_reason"] = "rate_limited_no_retry"
        elif result["status"] in ("redirect_rejected", "transport_error") or result["http_status"] in (401, 403):
            plan["stop_reason"] = "request_failed_no_retry"
        if result["reported_model"] is not None:
            result["reported_model"] = result["reported_model"].replace(api_key, "[REDACTED]")
        if save is not None:
            save(plan)
        if plan["stop_reason"] is not None:
            break
    return plan


def markdown(document):
    def cell(value):
        # Keep fixture/provider text literal; escaped backticks must not create
        # code spans where HTML entities would display without being decoded.
        text = re.sub(r"([\\`*_{}\[\]()#+.!|~-])", r"\\\1", str(value))
        return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\r\n", "\n").replace("\r", "\n").replace("\n", "<br>")

    lines = ["# 받아쓰기 정리 프롬프트 비교", "", document["notice"], "",
             f"- 상태: {'실행 전 계획 — API 호출 없음' if document['mode'] == 'dry_run' else '합성 문장 API 평가'}",
             f"- 모델: `{document['model']}`", f"- 계획 요청: {len(document['requests'])}건 / 완료: {len(document['results'])}건",
             f"- 비용 한도: US${document['max_usd']} / 최악 예약: US${document['reserved_total_usd']}",
             f"- 예산 범위 내: {'예' if document['budget_allows_execution'] else '아니요 — 실행 차단'}",
             f"- 가격 근거: [Groq 공식 모델 가격]({PRICING_URL}), 확인 {PRICING_CHECKED_AT}",
             "- 비용은 캐시 할인 없는 공개 단가 추정입니다. usage 누락은 미확인으로 표시하며 예약 예산을 환급하지 않습니다.",
             "- 앱과 같은 strict JSON schema·reasoning_effort=low를 사용합니다. 평가의 출력 한도는 1024로 앱의 16384보다 작습니다.", ""]
    if "interval_seconds" in document:
        lines.extend([f"- 요청 시작 간 최소 간격: {document['interval_seconds']}초 (대기 시간은 지연 측정에서 제외)", ""])
    if document.get("stop_reason"):
        lines.extend([f"- 중단: `{document['stop_reason']}`", ""])
    if document["results"]:
        lines.extend(["| ID | 구분 | 회차 | 상태 | 결과 | 기대 문장 완전 일치 | 입력/출력 토큰 | 추정 USD | 지연 ms |",
                      "| --- | --- | --- | --- | --- | --- | --- | --- | --- |"])
        for result in document["results"]:
            tokens = "/".join(str(result[key]) if result[key] is not None else "미확인" for key in ("input_tokens", "output_tokens"))
            values = [result["id"], result["variant"], result["run"], result["status"],
                      result["text"] if result["text"] is not None else "출력 없음",
                      "미평가" if result["exact_expected_match"] is None else ("일치" if result["exact_expected_match"] else "불일치"),
                      tokens, result["estimated_uncached_cost_usd"] if result["estimated_uncached_cost_usd"] is not None else "미확인",
                      result["latency_ms"]]
            lines.append("| " + " | ".join(cell(value) for value in values) + " |")
    for fixture in document["fixtures"]:
        lines.extend(["", f"## {fixture['id']}", "", f"- 원문: {cell(fixture['stt_input'])}",
                      f"- 기대 문장(유일한 정답 아님): {cell(fixture['expected_text']) or '(빈 문자열)'}",
                      "- 보존 조건: " + "; ".join(cell(value) for value in fixture["preservation_conditions"]),
                      "- 제거 대상: " + ("; ".join(cell(value) for value in fixture.get("remove", [])) or "없음"),
                      "- 금지 변화: " + "; ".join(cell(value) for value in fixture["forbidden_changes"]),
                      "- 사람 검토: 미실시"])
    return "\n".join(lines) + "\n"


def write_report(document, output):
    output = Path(output)
    if output.suffix != ".json":
        raise EvaluationError("--output에는 .json 파일 경로를 지정해 주세요.")
    output.parent.mkdir(parents=True, exist_ok=True)
    for target, content in ((output, json.dumps(document, ensure_ascii=False, indent=2) + "\n"),
                            (output.with_suffix(".md"), markdown(document))):
        temporary = None
        try:
            with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=target.parent, delete=False) as file:
                temporary = file.name
                file.write(content)
            os.replace(temporary, target)
        finally:
            if temporary is not None and os.path.exists(temporary):
                os.unlink(temporary)


def main(argv=None):
    parser = argparse.ArgumentParser(description="실제 앱 프롬프트의 합성 문장 A/B 평가. 기본은 API 호출과 키 접근이 없는 실행 전 계획입니다.")
    parser.add_argument("--before", required=True, help="기존 ProcessingPrompt export JSON")
    parser.add_argument("--after", required=True, help="개선 ProcessingPrompt export JSON")
    parser.add_argument("--model", choices=tuple(RATES), default="openai/gpt-oss-120b")
    parser.add_argument("--ids", help="비교할 fixture ID (쉼표 구분, 기본 전체)")
    parser.add_argument("--repetitions", type=int, default=1)
    parser.add_argument("--max-usd", default="0.10", help="비용 예약 상한 USD (0 초과, 최대 0.10)")
    parser.add_argument("--output", default="cleanup-comparison.json")
    parser.add_argument("--execute", action="store_true", help="합성 데이터를 Groq에 전송하고 유료 API를 실제 호출")
    parser.add_argument("--resume", action="store_true", help="--execute와 함께 기존 --output의 미실행 요청만 재개")
    parser.add_argument("--interval-seconds", type=float, default=0, help="요청 시작 간 최소 간격(0~60초, 측정 지연에서 제외)")
    args = parser.parse_args(argv)
    try:
        before, after = read_export(args.before), read_export(args.after)
        plan = make_plan(before, after, args.model, args.ids, args.repetitions, Decimal(args.max_usd))
        interval = validate_interval(args.interval_seconds)
        sources = {Path(args.before).resolve(), Path(args.after).resolve()}
        if {Path(args.output).resolve(), Path(args.output).with_suffix(".md").resolve()} & sources:
            raise EvaluationError("보고서로 원본 export를 덮어쓸 수 없습니다.")
        if args.resume:
            if not args.execute:
                raise EvaluationError("--resume은 --execute와 함께 지정해 주세요. 기존 결과는 다시 실행하지 않습니다.")
            plan = resume_plan(args.output, plan)
        else:
            if Path(args.output).exists():
                try:
                    previous = json.loads(Path(args.output).read_bytes())
                except (OSError, ValueError) as error:
                    raise EvaluationError("기존 보고서를 확인할 수 없어 덮어쓰지 않습니다.") from error
                if isinstance(previous, dict) and previous.get("mode") == "executed":
                    raise EvaluationError("기존 실제 실행 보고서는 덮어쓸 수 없습니다. --execute --resume으로 미실행 요청만 재개하세요.")
            write_report(plan, args.output)
        if args.execute:
            if not plan["budget_allows_execution"]:
                raise EvaluationError("최악 비용 예약액이 --max-usd를 넘습니다. --ids로 사례를 줄여 주세요.")
            # No environment/key read occurs on the default dry-run path.
            if len(plan["results"]) < len(plan["requests"]):
                execute_plan(plan, before, after, os.environ.get("GROQ_API_KEY"),
                             save=lambda value: write_report(value, args.output), interval_seconds=interval)
            write_report(plan, args.output)
        print(f"{'실행' if args.execute else '실행 전 계획'}: {len(plan['results'])}/{len(plan['requests'])}건, "
              f"최악 예약 US${plan['reserved_total_usd']}; {args.output}")
        return 0
    except (EvaluationError, InvalidOperation) as error:
        print(str(error) if isinstance(error, EvaluationError) else "--max-usd는 올바른 숫자여야 합니다.", file=sys.stderr)
        return 2
    except OSError:
        print("평가 보고서를 저장할 수 없습니다.", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
