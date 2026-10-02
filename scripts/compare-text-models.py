#!/usr/bin/env python3
"""실제 Core 요청·파서로 합성 문장 정리 모델을 비교합니다. 기본 dry run."""
import argparse
import base64
from collections import Counter
from concurrent.futures import ThreadPoolExecutor, as_completed
from decimal import Decimal, InvalidOperation
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import re
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("bounded_decision_transport", ROOT / "scripts/compare-decisions.py")
transport = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(transport)
ENDPOINT = "https://openrouter.ai/api/v1/chat/completions"
transport.PROVIDERS["textbench"] = {"host": "openrouter.ai", "path": "/api/v1/chat/completions"}
DEFAULT_MODELS = ["qwen/qwen3-30b-a3b-instruct-2507", "upstage/solar-mini4", "upstage/solar-pro4",
                  "qwen/qwen3.7-flash", "qwen/qwen3.8-flash", "openai/gpt-6-luna",
                  "deepseek/deepseek-v4.1-flash", "xiaomi/mimo-v2.6-flash"]
MAX_TOKENS = 1024
FRAMING = 2048
MAX_USD = Decimal("0.5")
EXPRESSION_STYLES = {"faithful", "concise", "summary", "clear", "expanded", "creative"}
SOURCES = list(dict.fromkeys([s for s in transport.SOURCES if s != "Tools/DecisionBench/main.swift"] + [
    "Sources/OpenNoTypeCore/AI/DictationExpression.swift", "Sources/OpenNoTypeCore/AI/OpenRouterTextPolicy.swift", "Tools/TextModelBench/main.swift"]))


class BenchError(Exception):
    pass


def digest(data):
    return hashlib.sha256(data).hexdigest()


def json_bytes(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()


def fixture_expression(case):
    profile = case.get("writing_profile")
    if not isinstance(profile, dict) or profile.get("kind") not in ("general", "conversation", "notes", "development", "email") \
            or profile.get("tone") not in ("preserve", "casual", "polite", "formal"):
        raise BenchError("invalid_writing_profile")
    expression = profile.get("expression")
    if expression is None:
        return None
    if not isinstance(expression, dict) or not isinstance(expression.get("style"), str) or expression.get("style") not in EXPRESSION_STYLES \
            or type(expression.get("strength")) is not int or not 0 <= expression["strength"] <= 100:
        raise BenchError("invalid_dictation_expression")
    if expression["style"] == "faithful" or expression["strength"] == 0:
        return None
    return {"style": expression["style"], "strength": expression["strength"]}


def load_cases(path, limit):
    raw = Path(path).read_bytes()
    if len(raw) > 500_000:
        raise BenchError("fixture_too_large")
    cases = json.loads(raw)["cases"]
    if not 12 <= len(cases) <= 20 or limit is not None and not 1 <= limit <= len(cases):
        raise BenchError("invalid_case_limit")
    seen = set()
    for case in cases:
        if case.get("id") in seen or not re.fullmatch(r"[A-Za-z0-9_-]{1,100}", case.get("id", "")):
            raise BenchError("invalid_fixture_id")
        seen.add(case["id"])
        if case.get("mode") != "dictation" or not isinstance(case.get("stt_input"), str) or not case["stt_input"].strip():
            raise BenchError("invalid_fixture_text")
        fixture_expression(case)
        if not case.get("preservation_conditions") or not case.get("forbidden_changes") or not case.get("checks"):
            raise BenchError("missing_quality_conditions")
        for check in case["checks"]:
            if type(check.get("must_match")) is not bool:
                raise BenchError("invalid_quality_check")
            re.compile(check["regex"])
    return cases[:limit], digest(raw)


def load_models(path, names):
    raw = Path(path).read_bytes()
    if len(raw) > 10_000_000:
        raise BenchError("catalog_too_large")
    catalog = {model["id"]: model for model in json.loads(raw)["data"]}
    if not 1 <= len(names) <= 32 or len(set(names)) != len(names):
        raise BenchError("invalid_model_list")
    selected = {}
    for name in names:
        if name not in catalog:
            raise BenchError("model_absent_from_verified_catalog")
        model = catalog[name]
        prices = model.get("pricing", {})
        for key in ("prompt", "completion"):
            try:
                value = Decimal(prices[key])
            except (KeyError, InvalidOperation):
                raise BenchError("unknown_model_price")
            if not value.is_finite() or value < 0:
                raise BenchError("unknown_model_price")
        selected[name] = model
    return selected, digest(raw)


def hashes():
    result = {source: digest((ROOT / source).read_bytes()) for source in SOURCES}
    for source in ("scripts/compare-text-models.py", "scripts/compare-decisions.py"):
        result[source] = digest((ROOT / source).read_bytes())
    return result


def compile_harness(folder):
    before = hashes()
    binary = Path(folder) / "text-model-bench"
    args = ["swiftc", "-swift-version", "5", "-parse-as-library", "-module-cache-path", str(Path(folder) / "module-cache")]
    sdk = os.environ.get("MACOS_SDK_PATH")
    compatible = Path("/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk")
    if sdk or compatible.exists():
        args += ["-sdk", sdk or str(compatible)]
    args += [str(ROOT / source) for source in SOURCES] + ["-o", str(binary)]
    completed = subprocess.run(args, capture_output=True, timeout=120)
    if completed.returncode:
        raise BenchError("core_compile_failed: " + completed.stderr.decode(errors="replace")[-2_000:])
    if hashes() != before:
        raise BenchError("source_changed_during_compile")
    return binary, before


def harness(binary, command, payload):
    completed = subprocess.run([str(binary), command], input=json_bytes(payload), capture_output=True, timeout=30)
    if completed.returncode:
        raise BenchError("production_harness_failed")
    return json.loads(completed.stdout)


def export_requests(binary, cases, models):
    exported = harness(binary, "export", {"fixtures": cases, "models": list(models)})
    output = {}
    indexed = {case["id"]: case for case in cases}
    for item in exported:
        original = base64.b64decode(item["body_base64"], validate=True)
        body = json.loads(original)
        if item["endpoint"] != ENDPOINT or body.get("model") != item["model"]:
            raise BenchError("unexpected_production_endpoint_or_model")
        if body.get("max_tokens") != 16_384 or body.get("provider") != {"allow_fallbacks": False, "require_parameters": True}:
            raise BenchError("production_contract_changed")
        case = indexed.get(item["id"], {})
        if "writing_profile" in case:
            try:
                user_message = next(message for message in reversed(body["messages"]) if message["role"] == "user")
                payload = json.loads(user_message["content"])
            except (KeyError, StopIteration, TypeError, ValueError):
                raise BenchError("production_expression_payload_missing")
            if payload.get("dictation_expression") != fixture_expression(case):
                raise BenchError("production_expression_mismatch")
        # The only benchmark request change: reserve and send at most 1024 output tokens.
        body["max_tokens"] = MAX_TOKENS
        bounded = json_bytes(body)
        if len(bounded) > 64_000:
            raise BenchError("request_too_large")
        key = (item["id"], item["model"])
        if key in output:
            raise BenchError("duplicate_export")
        output[key] = {"body": bounded, "production_sha256": digest(original), "request_sha256": digest(bounded),
                       "production_max_tokens": 16_384, "benchmark_max_tokens": MAX_TOKENS,
                       "response_format": body.get("response_format"), "reasoning": body.get("reasoning")}
    if set(output) != {(case["id"], model) for case in cases for model in models}:
        raise BenchError("export_fixture_model_mismatch")
    return output


def reserve(request, model):
    upper = len(request["body"]) + FRAMING
    if upper + MAX_TOKENS > model.get("context_length", 0):
        raise BenchError("conservative_context_bound_exceeded")
    rates = dict(model["pricing"])
    # Only use a long-context price if this conservative input upper bound can reach it.
    for tier in rates.get("overrides", []):
        if upper >= tier.get("min_prompt_tokens", math.inf):
            rates["prompt"] = str(max(Decimal(rates["prompt"]), Decimal(tier["prompt"])))
            rates["completion"] = str(max(Decimal(rates["completion"]), Decimal(tier["completion"])))
    charge = Decimal(upper) * Decimal(rates["prompt"]) + Decimal(MAX_TOKENS) * Decimal(rates["completion"])
    # Catalog prices are a public snapshot; no cache discount or unknown token refund.
    return upper, charge


def quality_checks(case, text):
    return [{"name": check["name"], "passed": bool(re.search(check["regex"], text, re.I | re.S)) == check["must_match"]}
            for check in case["checks"]]


def safe_label(value):
    return value if isinstance(value, str) and re.fullmatch(r"[A-Za-z0-9 ._/:+-]{1,200}", value) else None


def evaluate(binary, case, model, request, key, deadline):
    wire = transport.post_once(request["body"], key, deadline, provider="textbench")
    metadata = {"id": case["id"], "model": model, "elapsed_seconds": wire["elapsed_seconds"],
                "http_status": wire.get("http_status"), "request_sha256": request["request_sha256"], "manual_review_required": True}
    if "error" in wire:
        return dict(metadata, ok=False, error=wire["error"], usage={})
    parsed = harness(binary, "parse", {"fixture": case, "model": model, "http_status": wire["http_status"], "response": wire["response"]})
    obj = wire["response"] if isinstance(wire["response"], dict) else {}
    metadata["actual_provider"] = safe_label(obj.get("provider"))
    choice = obj.get("choices", [{}])[0] if isinstance(obj.get("choices"), list) and obj["choices"] else {}
    if isinstance(choice, dict):
        metadata["finish_reason"] = safe_label(choice.get("finish_reason"))
        message = choice.get("message", {})
        content = message.get("content") if isinstance(message, dict) else None
        metadata["content_empty_or_missing"] = not isinstance(content, str) or not content.strip()
    if parsed.get("ok"):
        parsed["checks"] = quality_checks(case, parsed["text"])
        parsed["automatic_checks_passed"] = all(check["passed"] for check in parsed["checks"])
    return dict(parsed, **metadata)


def summary(models, results):
    summaries = {}
    for model in models:
        rows = [row for row in results if row["model"] == model]
        complete = [row for row in rows if row.get("ok")]
        times = [row["elapsed_seconds"] for row in rows]
        costs = [row.get("usage", {}).get("provider_reported_cost_usd") for row in rows]
        known = [Decimal(str(value)) for value in costs if transport.numeric(value)]
        summaries[model] = {"attempted": len(rows), "parsed": len(complete),
            "automatic_condition_checks_passed": sum(row.get("automatic_checks_passed", False) for row in rows),
            "latency_p50_seconds": transport.percentile(times, .5), "latency_p95_seconds": transport.percentile(times, .95),
            "errors": dict(Counter(row.get("error", "unknown_error") for row in rows if not row.get("ok"))),
            "reported_cost_usd": str(sum(known)) if known else None, "cost_unknown_requests": len(costs) - len(known),
            "input_tokens_reported": sum(row.get("usage", {}).get("input_tokens") for row in rows if transport.numeric(row.get("usage", {}).get("input_tokens"))),
            "output_tokens_reported": sum(row.get("usage", {}).get("output_tokens") for row in rows if transport.numeric(row.get("usage", {}).get("output_tokens"))),
            "reasoning_tokens_reported": sum(row.get("usage", {}).get("reasoning_tokens") for row in rows if transport.numeric(row.get("usage", {}).get("reasoning_tokens"))),
            "reasoning_tokens_unknown_requests": sum(not transport.numeric(row.get("usage", {}).get("reasoning_tokens")) for row in rows),
            "content_empty_or_missing": sum(row.get("content_empty_or_missing", False) for row in rows),
            "actual_providers": dict(Counter(row["actual_provider"] for row in rows if row.get("actual_provider")))}
    return summaries


def amount(value):
    try:
        value = Decimal(value)
    except InvalidOperation:
        raise argparse.ArgumentTypeError("invalid_budget")
    if not value.is_finite() or not 0 < value <= MAX_USD:
        raise argparse.ArgumentTypeError("budget_must_be_positive_and_at_most_0.5")
    return value


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--models", help="쉼표로 구분한 catalog model IDs; 기본 8개")
    parser.add_argument("--catalog", type=Path, default=ROOT / "docs/reviews/2026-10-01/text-model-prices.json")
    parser.add_argument("--fixtures", type=Path, default=ROOT / "docs/fixtures/text-model-value.json")
    parser.add_argument("--limit", type=int, help="모델마다 평가할 fixture 수; 1이면 호환 probe")
    parser.add_argument("--live", action="store_true")
    parser.add_argument("--max-usd", type=amount, default=MAX_USD)
    parser.add_argument("--deadline", type=float, default=30)
    parser.add_argument("--workers", type=int, choices=range(1, 5), default=4)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(argv)
    if not math.isfinite(args.deadline) or not 0 < args.deadline <= 60:
        parser.error("deadline_must_be_positive_and_at_most_60")
    try:
        names = [name.strip() for name in args.models.split(",")] if args.models else DEFAULT_MODELS
        models, catalog_hash = load_models(args.catalog, names)
        cases, fixture_hash = load_cases(args.fixtures, args.limit)
        with tempfile.TemporaryDirectory(prefix="opennotype-text-bench-") as scratch:
            binary, source_hashes = compile_harness(scratch)
            requests = export_requests(binary, cases, models)
            plan = []
            total = Decimal(0)
            for index, case in enumerate(cases):
                ordered = names[index % len(names):] + names[:index % len(names)]
                for name in ordered:
                    request = requests[(case["id"], name)]
                    upper, cost = reserve(request, models[name]); total += cost
                    plan.append({"id": case["id"], "model": name, "reserved_usd": str(cost), "input_token_upper_bound": upper,
                                 **{k: v for k, v in request.items() if k != "body"}})
            if total > args.max_usd:
                raise BenchError("planned_reservation_exceeds_max_usd")
            report = {"schema_version": 1, "mode": "live" if args.live else "dry_run_no_key_no_network",
                "endpoint": ENDPOINT, "catalog_sha256": catalog_hash, "fixture_sha256": fixture_hash, "source_sha256": source_hashes,
                "models": names, "fixtures": cases, "model_metadata": {name: {key: models[name].get(key) for key in ("id", "canonical_slug", "pricing", "reasoning", "supported_parameters")} for name in names},
                "deadline_seconds": args.deadline, "workers": args.workers, "max_usd": str(args.max_usd),
                "reserved_total_usd": str(total), "planned_requests": len(plan), "requests": plan, "results": [],
                "request_difference": {"only_field": "max_tokens", "production": 16_384, "benchmark": MAX_TOKENS},
                "notice": "합성 regex 보존 검사는 의미 정확도나 exact-text 정답률이 아닙니다. 보존 조건·금지 변화를 수동 검토하세요.",
                "reservation_policy": "실제 bounded wire UTF8 bytes + 2048 framing; 1024 output including reasoning, uncached catalog rates, no refunds; 공개가격스냅샷 예약이며 계정청구한도는 별도입니다."}
            if args.live:
                key = transport.safe_api_key(os.environ.get("OPENROUTER_API_KEY"))
                indexed = {case["id"]: case for case in cases}
                records = {}
                with ThreadPoolExecutor(max_workers=args.workers) as pool:
                    jobs = {pool.submit(evaluate, binary, indexed[item["id"]], item["model"], requests[(item["id"], item["model"])], key, args.deadline): item for item in plan}
                    for future in as_completed(jobs):
                        item = jobs[future]
                        try:
                            result = future.result()
                        except Exception:
                            result = {"id": item["id"], "model": item["model"], "ok": False, "error": "benchmark_worker_failed", "elapsed_seconds": 0, "usage": {}, "manual_review_required": True}
                        records[(item["id"], item["model"])] = result
                report["results"] = [records[(item["id"], item["model"])] for item in plan]
                report["summary"] = summary(models, report["results"])
            transport.write_report(report, args.output)
            print(json.dumps({k: report[k] for k in ("mode", "models", "planned_requests", "reserved_total_usd", "max_usd", "request_difference")}, ensure_ascii=False, indent=2))
            if args.live:
                print(json.dumps(report["summary"], ensure_ascii=False, indent=2))
        return 0
    except (BenchError, transport.BenchmarkError, OSError, ValueError, subprocess.TimeoutExpired, KeyError) as error:
        print("벤치마크 중단: " + (str(error) if isinstance(error, BenchError) else type(error).__name__))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
