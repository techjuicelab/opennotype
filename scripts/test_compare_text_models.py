#!/usr/bin/env python3
import base64
from contextlib import redirect_stdout
from decimal import Decimal
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

SPEC = importlib.util.spec_from_file_location("text_bench", Path(__file__).with_name("compare-text-models.py"))
bench = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(bench)
FIXTURE = bench.ROOT / "docs/fixtures/text-model-value.json"
CATALOG = bench.ROOT / "docs/reviews/2026-10-01/text-model-prices.json"


class TextBenchTests(unittest.TestCase):
    def test_sixteen_cases_cover_languages_names_and_meaning_constraints(self):
        cases, _ = bench.load_cases(FIXTURE, None)
        self.assertEqual(16, len(cases))
        categories = {case["category"] for case in cases}
        self.assertTrue({"product_names", "english_preservation", "mixed_languages", "negation", "conditions", "numbers", "self_correction", "dictated_question", "literal_override"} <= categories)
        for case in cases:
            checks = bench.quality_checks(case, case["expected_text"])
            self.assertTrue(all(check["passed"] for check in checks), case["id"])
        source = "\n".join((bench.ROOT / name).read_text() for name in ("Sources/OpenNoTypeCore/AI/ProcessingPrompt.swift", "Sources/OpenNoTypeCore/AI/DictationCleanupInstructions.swift"))
        normalized = "".join(source.split())
        for case in cases:
            self.assertNotIn("".join(case["stt_input"].split()), normalized)

    def test_probe_one_case_for_every_model(self):
        cases, _ = bench.load_cases(FIXTURE, 1)
        self.assertEqual(["T01"], [case["id"] for case in cases])
        models, _ = bench.load_models(CATALOG, bench.DEFAULT_MODELS)
        self.assertEqual(8, len(models))
        self.assertEqual(len(bench.SOURCES), len(set(bench.SOURCES)))

    def test_unknown_negative_and_duplicate_models_not_priced_as_free(self):
        for names in (["unknown/model"], ["typesafe/jev-router"], bench.DEFAULT_MODELS + [bench.DEFAULT_MODELS[0]]):
            with self.assertRaises(bench.BenchError):
                bench.load_models(CATALOG, names)
        with tempfile.TemporaryDirectory() as scratch:
            path = Path(scratch) / "catalog.json"
            path.write_text(json.dumps({"data": [{"id": "unknown-price/model", "pricing": {"prompt": "-1", "completion": "-1"}}]}))
            with self.assertRaisesRegex(bench.BenchError, "unknown_model_price"):
                bench.load_models(path, ["unknown-price/model"])

    def test_only_output_token_field_changes_from_captured_production(self):
        body = {"model": "test/model", "max_tokens": 16384, "provider": {"allow_fallbacks": False, "require_parameters": True},
                "messages": [], "response_format": {"type": "json_object"}, "reasoning": {"enabled": False, "exclude": True}}
        raw = bench.json_bytes(body)
        exported = [{"id": "T01", "model": "test/model", "endpoint": bench.ENDPOINT, "body_base64": base64.b64encode(raw).decode()}]
        with mock.patch.object(bench, "harness", return_value=exported):
            result = bench.export_requests(Path("unused"), [{"id": "T01"}], {"test/model": {}})
        bounded = json.loads(result[("T01", "test/model")]["body"])
        self.assertEqual(1024, bounded.pop("max_tokens"))
        body.pop("max_tokens")
        self.assertEqual(body, bounded)
        self.assertEqual(bench.digest(raw), result[("T01", "test/model")]["production_sha256"])

    def test_request_endpoint_cannot_be_changed_to_a_secret_destination(self):
        body = {"model": "test/model", "max_tokens": 16384, "provider": {"allow_fallbacks": False, "require_parameters": True}}
        exported = [{"id": "T01", "model": "test/model", "endpoint": "https://example.test/collect", "body_base64": base64.b64encode(bench.json_bytes(body)).decode()}]
        with mock.patch.object(bench, "harness", return_value=exported), self.assertRaises(bench.BenchError):
            bench.export_requests(Path("unused"), [{"id": "T01"}], {"test/model": {}})

    def test_wire_bytes_schema_and_tier_are_in_reserved_budget(self):
        model = {"context_length": 100000, "pricing": {"prompt": "0.0000001", "completion": "0.0000003", "overrides": [
            {"min_prompt_tokens": 32000, "prompt": "0.0000002", "completion": "0.0000005"}]}}
        upper, cost = bench.reserve({"body": b'x' * 100}, model)
        self.assertEqual(2148, upper)
        self.assertEqual(Decimal(2148) * Decimal("0.0000001") + Decimal(1024) * Decimal("0.0000003"), cost)
        upper, cost = bench.reserve({"body": b'x' * 32000}, model)
        self.assertEqual(Decimal(upper) * Decimal("0.0000002") + Decimal(1024) * Decimal("0.0000005"), cost)

    def test_budget_limit_half_dollar_finite_positive(self):
        for value in ("0", "-1", "NaN", "Infinity", "0.5001"):
            with self.assertRaises(Exception):
                bench.amount(value)
        self.assertEqual(Decimal("0.5"), bench.amount("0.5"))

    def test_dry_run_does_not_read_key_or_open_network(self):
        class Env(dict):
            def get(self, name, default=None):
                if name.endswith("API_KEY"):
                    raise AssertionError("key access")
                return default
        cases, _ = bench.load_cases(FIXTURE, 1)
        names = bench.DEFAULT_MODELS
        exported = {(case["id"], name): {"body": b'{}', "production_sha256": "synthetic", "request_sha256": "synthetic",
                     "production_max_tokens": 16384, "benchmark_max_tokens": 1024, "response_format": {}, "reasoning": None} for case in cases for name in names}
        with tempfile.TemporaryDirectory() as scratch, \
             mock.patch.object(bench, "compile_harness", return_value=(Path("unused"), {})), \
             mock.patch.object(bench, "export_requests", return_value=exported), \
             mock.patch.object(bench.os, "environ", Env()), \
             mock.patch.object(bench, "evaluate", side_effect=AssertionError("network access")), redirect_stdout(io.StringIO()):
            self.assertEqual(0, bench.main(["--limit", "1", "--output", str(Path(scratch) / "dry.json")]))

    def test_unknown_cost_and_missing_reasoning_tokens_are_not_zero(self):
        report = bench.summary(["test/model"], [{"model": "test/model", "ok": False, "error": "empty_output", "elapsed_seconds": .5,
                                                "usage": {}, "content_empty_or_missing": True}])
        self.assertIsNone(report["test/model"]["reported_cost_usd"])
        self.assertEqual(1, report["test/model"]["cost_unknown_requests"])
        self.assertEqual(1, report["test/model"]["reasoning_tokens_unknown_requests"])
        self.assertEqual(1, report["test/model"]["content_empty_or_missing"])


if __name__ == "__main__":
    unittest.main()
