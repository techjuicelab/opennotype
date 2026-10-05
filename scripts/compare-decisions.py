#!/usr/bin/env python3
"""합성 Jev 벤치마크. 기본 dry run; 실제 호출은 --live --max-usd가 필요합니다."""
import argparse
import base64
from collections import Counter
from concurrent.futures import ThreadPoolExecutor, as_completed
from decimal import Decimal, InvalidOperation
import hashlib
import http.client
import json
import math
import os
from pathlib import Path
import socket
import ssl
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
MODEL = "typesafe/jev-1.13"
HOST = "openrouter.ai"
ENDPOINT = "https://openrouter.ai/api/alpha/decisions"
ENDPOINT_PATH = "/api/alpha/decisions"
INPUT_USD_PER_MILLION = Decimal("0.042")
OUTPUT_USD_PER_MILLION = Decimal("0")
PRICE_URL = "https://openrouter.ai/typesafe/jev-1.13"
PROVIDERS = {
    "openrouter": {"model": MODEL, "host": HOST, "endpoint": ENDPOINT, "path": ENDPOINT_PATH,
                   "key_env": "OPENROUTER_API_KEY", "price_url": PRICE_URL},
    "typesafe": {"model": "jev-1.13.0", "host": "api.typesafe.ai", "endpoint": "https://api.typesafe.ai/v1/systemone",
                 "path": "/v1/systemone", "key_env": "TYPESAFE_API_KEY", "price_url": "https://docs.typesafe.ai/models"},
}
RUNTIME_DEADLINE = 10.0
MAX_RESPONSE_BYTES = 128_000
MAX_REQUEST_BYTES = 64_000
FRAMING_TOKEN_ALLOWANCE = 4_096
AXES = ("meaning_changed", "content_added", "content_omitted")
CHOICES = {"use_candidate", "keep_original", "uncertain"}
CATEGORIES = {"technical_names", "ordinary_loanwords", "negation_conditions", "self_correction",
              "content_added", "content_omitted", "quotations_identifiers", "retain_hangul", "adversarial_input"}
SOURCES = ["Sources/OpenNoTypeCore/Localization.swift", "Sources/OpenNoTypeCore/Models.swift", "Sources/OpenNoTypeCore/AI/JevRepairIssue.swift", "Sources/OpenNoTypeCore/AI/ProviderDefaults.swift",
           "Sources/OpenNoTypeCore/AI/WritingProfile.swift", "Sources/OpenNoTypeCore/AI/DictationExpression.swift",
           "Sources/OpenNoTypeCore/AI/DictationOutputLanguage.swift", "Sources/OpenNoTypeCore/AI/NativeTranslationInstructions.swift",
           "Sources/OpenNoTypeCore/AI/DictionaryHints.swift",
           "Sources/OpenNoTypeCore/AI/DictationCleanupInstructions.swift", "Sources/OpenNoTypeCore/AI/ProcessingPrompt.swift",
           "Sources/OpenNoTypeCore/AI/TranscriptionHints.swift", "Sources/OpenNoTypeCore/AI/OpenRouterTextPolicy.swift",
           "Sources/OpenNoTypeCore/AI/ProviderClient.swift",
           "Sources/OpenNoTypeCore/AI/TranslationOutputGuard.swift", "Sources/OpenNoTypeCore/AI/ProtectedLiteralPatterns.swift",
           "Sources/OpenNoTypeCore/AI/BoundedProviderResponse.swift",
           "Sources/OpenNoTypeCore/AI/DecisionModels.swift", "Sources/OpenNoTypeCore/AI/DecisionClient.swift",
           "Sources/OpenNoTypeCore/Usage/UsageModels.swift", "Sources/OpenNoTypeCore/Usage/UsagePricing.swift",
           "Tools/DecisionBench/main.swift"]


class BenchmarkError(Exception):
    pass


def provider_config(provider):
    if provider not in PROVIDERS:
        raise BenchmarkError("unsupported_provider")
    return PROVIDERS[provider]


def load_fixtures(path):
    data = Path(path).read_bytes()
    if len(data) > 1_000_000:
        raise BenchmarkError("fixture_too_large")
    document = json.loads(data)
    cases = document.get("cases")
    if document.get("schema_version") != 1 or not isinstance(cases, list) or not 60 <= len(cases) <= 100:
        raise BenchmarkError("invalid_fixture_document")
    ids, pairs, counts = set(), {}, Counter()
    for case in cases:
        if not isinstance(case, dict) or not isinstance(case.get("id"), str) or case["id"] in ids:
            raise BenchmarkError("invalid_fixture_id")
        ids.add(case["id"])
        if case.get("category") not in CATEGORIES or case.get("quality") not in ("good", "bad"):
            raise BenchmarkError("invalid_fixture_category")
        if not isinstance(case.get("pair_id"), str) or not isinstance(case.get("rationale"), str) or not case["rationale"]:
            raise BenchmarkError("missing_fixture_rationale")
        pair = pairs.setdefault(case["pair_id"], [])
        pair.append(case)
        counts[case["category"]] += 1
        if any(not isinstance(case.get(key), str) or not case[key].strip() for key in ("transcript", "cleaned_text")):
            raise BenchmarkError("invalid_fixture_text")
        if len(case["transcript"].encode()) + len(case["cleaned_text"].encode()) > 24_000:
            raise BenchmarkError("fixture_text_too_large")
        expected = case.get("expected", {})
        if set(expected) != set(AXES) | {"terms"} or any(type(expected[axis]) is not bool for axis in AXES):
            raise BenchmarkError("invalid_fixture_risks")
        terms = case.get("term_candidates")
        if not isinstance(terms, list) or len(terms) > 16 or not isinstance(expected["terms"], dict):
            raise BenchmarkError("invalid_fixture_terms")
        term_ids = []
        for term in terms:
            if set(term) != {"id", "original", "candidate"} or any(not isinstance(v, str) or not v.strip() for v in term.values()):
                raise BenchmarkError("invalid_fixture_term")
            if term["original"] not in case["transcript"]:
                raise BenchmarkError("term_missing_from_transcript")
            term_ids.append(term["id"])
        if len(set(term_ids)) != len(term_ids) or set(expected["terms"]) != set(term_ids) or any(v not in CHOICES for v in expected["terms"].values()):
            raise BenchmarkError("invalid_fixture_term_expectations")
    if set(counts) != CATEGORIES or min(counts.values()) < 6:
        raise BenchmarkError("fixture_category_coverage")
    for pair in pairs.values():
        if len(pair) != 2 or {c["quality"] for c in pair} != {"good", "bad"} or pair[0]["transcript"] != pair[1]["transcript"]:
            raise BenchmarkError("invalid_good_bad_pair")
        good = next(c for c in pair if c["quality"] == "good")
        if any(good["expected"][axis] for axis in AXES):
            raise BenchmarkError("good_fixture_has_semantic_error")
    return document, hashlib.sha256(data).hexdigest()


def source_hashes():
    return {source: hashlib.sha256((ROOT / source).read_bytes()).hexdigest() for source in SOURCES}


def build_harness(scratch):
    before = source_hashes()
    binary = Path(scratch) / "decision-bench"
    args = ["swiftc", "-swift-version", "5"]
    # Core-only compilation works with CLT; no SwiftUI or XCTest is needed.
    sdk = os.environ.get("MACOS_SDK_PATH")
    compatible_sdk = Path("/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk")
    if sdk:
        args += ["-sdk", sdk]
    elif compatible_sdk.exists():
        args += ["-sdk", str(compatible_sdk)]
    args += ["-module-cache-path", str(Path(scratch) / "module-cache")]
    args += [str(ROOT / source) for source in SOURCES] + ["-o", str(binary)]
    completed = subprocess.run(args, capture_output=True, timeout=120)
    if completed.returncode:
        # Compiler diagnostics contain source only; no environment/HTTP data is read here.
        (Path(scratch) / "compile-errors.txt").write_bytes(completed.stderr)
        raise BenchmarkError("core_compile_failed: " + completed.stderr.decode(errors="replace")[-2_000:])
    if before != source_hashes():
        raise BenchmarkError("core_source_changed_during_compile")
    return binary, before


def export_requests(binary, fixtures, provider="openrouter"):
    configuration = provider_config(provider)
    completed = subprocess.run([str(binary), "export", str(fixtures), provider], capture_output=True, timeout=15)
    if completed.returncode:
        raise BenchmarkError("production_request_export_failed")
    result = {}
    for item in json.loads(completed.stdout):
        body = base64.b64decode(item["body_base64"], validate=True)
        if item["endpoint"] != configuration["endpoint"] or item["runtime_deadline_seconds"] != RUNTIME_DEADLINE:
            raise BenchmarkError("production_contract_changed")
        if len(body) != item["request_bytes"] or len(body) > MAX_REQUEST_BYTES:
            raise BenchmarkError("invalid_exported_request")
        decoded = json.loads(body)
        if decoded["model"] != configuration["model"]:
            raise BenchmarkError("production_contract_changed")
        if provider == "openrouter" and decoded.get("provider") != {"allow_fallbacks": False}:
            raise BenchmarkError("production_contract_changed")
        if provider == "typesafe" and set(decoded) != {"model", "state", "questions"}:
            raise BenchmarkError("production_contract_changed")
        if item["id"] in result:
            raise BenchmarkError("duplicate_exported_request")
        result[item["id"]] = body
    return result


def reserve_usd(body):
    # Every UTF-8 wire byte is reserved as one input token: includes ALL question text,
    # state, candidate criteria and JSON overhead. Add hidden framing allowance.
    # Output is explicitly zero-priced on this fixed model, never assumed missing=zero.
    return Decimal(len(body) + FRAMING_TOKEN_ALLOWANCE) * INPUT_USD_PER_MILLION / Decimal(1_000_000)


def max_usd(value):
    try:
        amount = Decimal(value)
    except InvalidOperation:
        raise argparse.ArgumentTypeError("--max-usd는 유한한 양수여야 합니다.")
    if not amount.is_finite() or amount <= 0 or amount > 1:
        raise argparse.ArgumentTypeError("--max-usd는 0 초과 1 USD 이하여야 합니다.")
    return amount


def safe_api_key(value):
    if not isinstance(value, str) or not value.strip() or len(value.encode()) > 4_096 or any(ord(c) < 32 or ord(c) == 127 for c in value):
        raise BenchmarkError("missing_or_invalid_api_key")
    return value.strip()


def decode_json(data):
    # Match JSONSerialization's refusal of NaN/Infinity; never echo malformed bytes.
    try:
        return json.loads(data, parse_constant=lambda _: (_ for _ in ()).throw(ValueError()))
    except (ValueError, UnicodeDecodeError):
        return None


def post_once(body, key, deadline, connection_factory=http.client.HTTPSConnection, provider="openrouter"):
    configuration = provider_config(provider)
    started = time.monotonic()
    connection = None
    try:
        connection = connection_factory(configuration["host"], timeout=deadline, context=ssl.create_default_context())
        connection.request("POST", configuration["path"], body=body, headers={
            "Authorization": "Bearer " + key, "Content-Type": "application/json", "Accept": "application/json",
            "Cache-Control": "no-store", "Connection": "close", "Accept-Encoding": "identity"})
        # getresponse() may detach the socket for a Connection: close response.
        # Retain its transport so each bounded read uses the remaining wall deadline.
        transport = connection.sock
        remaining = deadline - (time.monotonic() - started)
        if remaining <= 0:
            return {"error": "timed_out", "elapsed_seconds": time.monotonic() - started}
        if transport:
            transport.settimeout(remaining)
        response = connection.getresponse()
        if 300 <= response.status < 400:
            return {"error": "redirect_rejected", "http_status": response.status, "elapsed_seconds": time.monotonic() - started}
        length = response.getheader("Content-Length")
        if length is not None:
            try:
                if int(length) < 0 or int(length) > MAX_RESPONSE_BYTES:
                    return {"error": "response_too_large", "http_status": response.status, "elapsed_seconds": time.monotonic() - started}
            except ValueError:
                return {"error": "invalid_response", "http_status": response.status, "elapsed_seconds": time.monotonic() - started}
        if response.getheader("Content-Encoding", "identity").lower() not in ("identity", ""):
            return {"error": "unsupported_response_encoding", "http_status": response.status, "elapsed_seconds": time.monotonic() - started}
        data = bytearray()
        while True:
            # read1() closes the response after consuming Content-Length. The
            # retained transport can then be closed too; do not touch it again.
            if response.isclosed():
                break
            remaining = deadline - (time.monotonic() - started)
            if remaining <= 0:
                return {"error": "timed_out", "http_status": response.status, "elapsed_seconds": time.monotonic() - started}
            if transport:
                transport.settimeout(remaining)
            chunk = response.read1(min(8_192, MAX_RESPONSE_BYTES + 1 - len(data)))
            if not chunk:
                break
            data.extend(chunk)
            if len(data) > MAX_RESPONSE_BYTES:
                return {"error": "response_too_large", "http_status": response.status, "elapsed_seconds": time.monotonic() - started}
        elapsed = time.monotonic() - started
        if elapsed > deadline:
            return {"error": "timed_out", "http_status": response.status, "elapsed_seconds": elapsed}
        return {"response": decode_json(data), "http_status": response.status, "elapsed_seconds": elapsed}
    except (socket.timeout, TimeoutError):
        return {"error": "timed_out", "elapsed_seconds": time.monotonic() - started}
    except (OSError, http.client.HTTPException):
        return {"error": "connection_failed", "elapsed_seconds": time.monotonic() - started}
    finally:
        if connection is not None:
            connection.close()


def estimated_input_cost(usage, provider):
    # The real Core pricing policy validates model/status/token metadata before
    # exporting this estimate. Do not reproduce that policy or relabel it billed cost.
    tokens = usage.get("input_tokens")
    estimate = usage.get("estimated_from_input_tokens_usd")
    if provider == "typesafe" and type(tokens) is int and tokens >= 0 and numeric(estimate):
        return str(Decimal(str(estimate)))
    return None


def parse_response(binary, case, wire, provider="openrouter"):
    if "error" in wire:
        return {"ok": False, "error": wire["error"], "usage": {"provider_reported_cost_usd": None}}
    payload = {"fixture": case, "response": wire["response"], "http_status": wire["http_status"], "provider": provider}
    completed = subprocess.run([str(binary), "parse"], input=json.dumps(payload, ensure_ascii=False, allow_nan=False).encode(),
                               capture_output=True, timeout=10)
    if completed.returncode:
        return {"ok": False, "error": "production_parser_failed", "usage": {"provider_reported_cost_usd": None}}
    result = json.loads(completed.stdout)
    result["usage"]["estimated_from_input_tokens_usd"] = estimated_input_cost(result["usage"], provider)
    return result


def numeric(value):
    return type(value) in (int, float) and math.isfinite(value) and value >= 0


def percentile(values, fraction):
    if not values:
        return None
    ordered = sorted(values)
    index = (len(ordered) - 1) * fraction
    lower = math.floor(index)
    upper = math.ceil(index)
    return ordered[lower] + (ordered[upper] - ordered[lower]) * (index - lower)


def ratio(numerator, denominator):
    return numerator / denominator if denominator else None


def confusion(cases, records, axis, threshold):
    counts = Counter(tp=0, tn=0, fp=0, fn=0)
    for case in cases:
        result = records.get(case["id"], {})
        if not result.get("ok"):
            continue
        expected = case["expected"][axis] if axis != "any_semantic_error" else any(case["expected"][a] for a in AXES)
        score = result["risk"][axis] if axis != "any_semantic_error" else max(result["risk"].values())
        predicted = score >= threshold
        counts["tp" if expected and predicted else "fn" if expected else "fp" if predicted else "tn"] += 1
    return dict(counts, sensitivity=ratio(counts["tp"], counts["tp"] + counts["fn"]),
                false_positive_rate=ratio(counts["fp"], counts["fp"] + counts["tn"]),
                accuracy=ratio(counts["tp"] + counts["tn"], sum(counts.values())))


def metrics(cases, records):
    selected = len(cases)
    completed = [records[c["id"]] for c in cases if records.get(c["id"], {}).get("ok")]
    timings = [r["elapsed_seconds"] for r in records.values() if numeric(r.get("elapsed_seconds"))]
    success_timings = [r["elapsed_seconds"] for r in completed]
    errors = Counter(r.get("error", "unknown_error") for r in records.values() if not r.get("ok"))
    cost_values = [r.get("usage", {}).get("provider_reported_cost_usd") for r in records.values()]
    known = [Decimal(str(value)) for value in cost_values if numeric(value)]
    estimates = []
    for record in records.values():
        value = record.get("usage", {}).get("estimated_from_input_tokens_usd")
        if value is not None:
            try:
                amount = Decimal(str(value))
                if amount.is_finite() and amount >= 0:
                    estimates.append(amount)
            except InvalidOperation:
                pass
    term_total, term_correct, term_by_choice = 0, 0, {}
    runtime_complete = [r for r in completed if r["elapsed_seconds"] <= RUNTIME_DEADLINE]
    for case in cases:
        result = records.get(case["id"], {})
        if not result.get("ok"):
            continue
        actual = {term["id"]: term["choice"] for term in result["terms"]}
        for id, expected in case["expected"]["terms"].items():
            term_total += 1
            correct = actual.get(id) == expected
            term_correct += correct
            item = term_by_choice.setdefault(expected, {"total": 0, "correct": 0})
            item["total"] += 1
            item["correct"] += correct
    return {
        "selected_cases": selected, "attempted_cases": len(records), "validated_complete_cases": len(completed),
        "inspection_completion_rate": ratio(len(completed), selected),
        "latency_seconds": {"all_attempts_p50": percentile(timings, .5), "all_attempts_p95": percentile(timings, .95),
                            "validated_p50": percentile(success_timings, .5), "validated_p95": percentile(success_timings, .95)},
        "runtime_deadline_seconds": RUNTIME_DEADLINE,
        "runtime_deadline_exceeded_count": sum(t > RUNTIME_DEADLINE for t in timings),
        "runtime_deadline_exceeded_rate": ratio(sum(t > RUNTIME_DEADLINE for t in timings), len(timings)),
        "validated_within_runtime_deadline": len(runtime_complete),
        "runtime_inspection_completion_rate": ratio(len(runtime_complete), selected),
        "errors": dict(errors),
        "coverage": {category: {"selected": sum(c["category"] == category for c in cases),
                               "validated": sum(c["category"] == category and records.get(c["id"], {}).get("ok", False) for c in cases)}
                     for category in sorted(CATEGORIES)},
        "semantic_thresholds": {str(threshold): {axis: confusion(cases, records, axis, threshold)
                                               for axis in AXES + ("any_semantic_error",)} for threshold in (.5, .7, .9)},
        "terms": {"total_completed": term_total, "correct": term_correct, "accuracy": ratio(term_correct, term_total),
                  "by_expected_choice": term_by_choice,
                  "expected_total_selected": sum(len(c["expected"]["terms"]) for c in cases)},
        "provider_cost": {"reported_total_usd": str(sum(known)) if known else None,
                          "known_cost_requests": len(known), "unknown_cost_requests": len(cost_values) - len(known),
                          "unknown_is_zero": False},
        "estimated_cost": {"from_reported_input_tokens_total_usd": str(sum(estimates)) if estimates else None,
                           "estimated_requests": len(estimates), "unknown_requests": len(records) - len(estimates),
                           "provider_reported": False},
        "tokens": {key: {"reported_total": sum(r.get("usage", {}).get(key) for r in records.values() if numeric(r.get("usage", {}).get(key))),
                         "unknown_requests": sum(not numeric(r.get("usage", {}).get(key)) for r in records.values())}
                   for key in ("input_tokens", "output_tokens")},
        "interpretation": "의미 지표의 분모는 검증 완료 사례만 포함합니다. 미완료는 통과로 간주하지 않습니다. 현재 앱의 10초 완료율은 전체 선택 사례가 분모입니다."}


def run_case(binary, case, body, key, deadline, provider="openrouter"):
    wire = post_once(body, key, deadline, provider=provider)
    result = parse_response(binary, case, wire, provider=provider)
    return dict(result, id=case["id"], category=case["category"], elapsed_seconds=wire["elapsed_seconds"],
                http_status=wire.get("http_status"), request_sha256=hashlib.sha256(body).hexdigest(),
                reserved_upper_usd=str(reserve_usd(body)))


def write_report(report, output):
    if output:
        path = Path(output)
        path.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=path.parent, delete=False) as file:
            temporary = Path(file.name)
            json.dump(report, file, ensure_ascii=False, indent=2, allow_nan=False)
            file.write("\n")
        temporary.replace(path)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fixtures", type=Path, default=ROOT / "docs/fixtures/decision-quality.json")
    parser.add_argument("--provider", choices=tuple(PROVIDERS), default="openrouter")
    parser.add_argument("--live", action="store_true")
    parser.add_argument("--max-usd", type=max_usd)
    parser.add_argument("--deadline", type=float, choices=(1.5, 10.0), default=10.0)
    parser.add_argument("--workers", type=int, choices=range(1, 5), default=1)
    parser.add_argument("--limit", type=int)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args(argv)
    if args.live and args.max_usd is None:
        parser.error("실제 호출에는 --max-usd가 필요합니다.")
    if args.limit is not None and args.limit <= 0:
        parser.error("--limit는 양수여야 합니다.")
    try:
        document, fixture_hash = load_fixtures(args.fixtures)
        configuration = provider_config(args.provider)
        cases = document["cases"][:args.limit]
        with tempfile.TemporaryDirectory(prefix="opennotype-decision-bench-") as scratch:
            binary, hashes = build_harness(scratch)
            exported = export_requests(binary, args.fixtures, provider=args.provider)
            if set(exported) != {c["id"] for c in document["cases"]}:
                raise BenchmarkError("export_fixture_mismatch")
            total_reserve = sum((reserve_usd(exported[c["id"]]) for c in cases), Decimal(0))
            if args.live and total_reserve > args.max_usd:
                raise BenchmarkError("planned_reserve_exceeds_budget; --limit로 사례 수를 줄이세요")
            report = {"schema_version": 1, "mode": "live" if args.live else "dry_run_no_network_no_key_access",
                      "provider": args.provider, "model": configuration["model"], "endpoint": configuration["endpoint"],
                      "fixture_sha256": fixture_hash, "source_sha256": hashes,
                      "deadline_seconds": args.deadline, "workers": args.workers, "selected_cases": len(cases),
                      "price": {"input_usd_per_million": str(INPUT_USD_PER_MILLION), "output_usd_per_million": str(OUTPUT_USD_PER_MILLION),
                                "source": configuration["price_url"], "checked_at": "2026-10-01"},
                      "budget": {"planned_reserved_upper_usd": str(total_reserve), "max_usd": str(args.max_usd) if args.max_usd else None,
                                 "input_bound": "actual Core wire UTF8 bytes plus 4096 framing tokens; questions included",
                                 "no_retry": True, "redirects_rejected": True,
                                 "limitation": "공개 토큰 단가와 상한에 근거한 예약이며 공급자의 계정 청구 한도를 대신하지 않습니다."},
                      "selected": [{"id": c["id"], "category": c["category"], "quality": c["quality"],
                                    "request_bytes": len(exported[c["id"]]), "request_sha256": hashlib.sha256(exported[c["id"]]).hexdigest(),
                                    "reserved_upper_usd": str(reserve_usd(exported[c["id"]]))} for c in cases],
                      "notes": ["72개 합성 사례의 사전 라벨이며 모델 결과를 보고 정답을 조정하지 않습니다.",
                                "동시성 2~4의 지연에는 동시 요청 자체의 영향이 포함됩니다.",
                                "현재 앱의 검토 제한은 10초입니다. --deadline 10은 현재 제한을, --deadline 1.5는 이전 버전의 짧은 제한을 비교합니다.",
                                "원문 API 응답, Authorization 헤더, 키 또는 사용자 발화를 기록하지 않습니다."]}
            if args.live:
                # The only credential lookup; dry run never reaches it.
                key = safe_api_key(os.environ.get(configuration["key_env"]))
                started = time.monotonic()
                records = {}
                # Reserve every selected request before scheduling; unknown costs are never refunded.
                with ThreadPoolExecutor(max_workers=args.workers) as pool:
                    pending = {pool.submit(run_case, binary, case, exported[case["id"]], key, args.deadline, args.provider): case for case in cases}
                    for future in as_completed(pending):
                        case = pending[future]
                        try:
                            result = future.result()
                        except Exception:
                            result = {"id": case["id"], "ok": False, "error": "benchmark_worker_failed",
                                      "usage": {"provider_reported_cost_usd": None}}
                        records[case["id"]] = result
                report["wall_seconds"] = time.monotonic() - started
                report["results"] = [records[c["id"]] for c in cases]
                report["metrics"] = metrics(cases, records)
            write_report(report, args.output)
            print(json.dumps({key: report[key] for key in ("mode", "provider", "model", "selected_cases", "deadline_seconds", "workers", "budget")},
                             ensure_ascii=False, indent=2))
            if args.live:
                print(json.dumps(report["metrics"], ensure_ascii=False, indent=2))
            else:
                print("Core 요청 생성 검증 완료. 네트워크와 API 키에 접근하지 않았습니다.")
        return 0
    except (BenchmarkError, OSError, ValueError, subprocess.TimeoutExpired) as error:
        # Only our fixed error codes and compiler diagnostics can reach this handler.
        print("벤치마크 중단: " + (str(error) if isinstance(error, BenchmarkError) else type(error).__name__))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
