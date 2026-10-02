#!/usr/bin/env python3
import base64
from contextlib import redirect_stdout
from decimal import Decimal
import importlib.util
import io
import json
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest import mock

SPEC = importlib.util.spec_from_file_location("text_bench", Path(__file__).with_name("compare-text-models.py"))
bench = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(bench)
FIXTURE = bench.ROOT / "docs/fixtures/text-model-value.json"
EXPRESSION_FIXTURE = bench.ROOT / "docs/fixtures/dictation-expression-quality.json"
CATALOG = bench.ROOT / "docs/reviews/2026-10-01/text-model-prices.json"


class TextBenchTests(unittest.TestCase):
    def test_expression_specification_covers_every_direction_and_disabled_controls(self):
        cases, _ = bench.load_cases(EXPRESSION_FIXTURE, None)
        self.assertEqual(16, len(cases))
        self.assertEqual(bench.EXPRESSION_STYLES, {case["writing_profile"]["expression"]["style"] for case in cases[:6]})
        settings = [case["writing_profile"]["expression"] for case in cases]
        self.assertIn({"style": "summary", "strength": 0}, settings)
        self.assertIn({"style": "faithful", "strength": 100}, settings)
        for case in cases:
            self.assertTrue(all(check["passed"] for check in bench.quality_checks(case, case["expected_text"])), case["id"])
        self.assertTrue({"english_summary_conditions", "mixed_identifiers_literal_summary", "creative_unsettled_intent"}
                        <= {case["category"] for case in cases})

    def test_expression_checks_catch_observed_wish_to_command_and_request_weakening(self):
        cases, _ = bench.load_cases(EXPRESSION_FIXTURE, None)
        indexed = {case["id"]: case for case in cases}
        failures = {
            "EX10": "JEV로 OpenNoType을 개선하고, 이름 오류를 검토한 뒤 내일 3시에 결과를 보내 주세요. 지금은 배포하지 마세요.",
            "EX13": "JEV를 활용해 OpenNoType 문장을 더 읽기 쉽게 다듬고 싶어요. 뜻은 그대로 유지해 주세요.",
            "EX14": "Improve OpenNoType with JEV. First, review the names. If approved, send the result at 3 p.m. on Friday. Do not publish it before approval."
        }
        for case_id, output in failures.items():
            with self.subTest(case=case_id):
                checks = bench.quality_checks(indexed[case_id], output)
                self.assertFalse(all(check["passed"] for check in checks))
                self.assertTrue(any(not check["passed"] and ("wish" in check["name"] or "request" in check["name"])
                                    for check in checks))

    def test_intent_checks_allow_equivalent_phrasing_without_one_required_literal(self):
        cases, _ = bench.load_cases(EXPRESSION_FIXTURE, None)
        indexed = {case["id"]: case for case in cases}
        alternatives = {
            "EX10": "JEV로 OpenNoType을 개선하기를 바랍니다. 이름 오류는 먼저 검토 부탁드려요. 검토가 끝나면 내일 3시에 결과를 전달해 주세요. 지금은 배포하지 마세요.",
            "EX11": "OpenNoType을 개선하기 위해 JEV로 이름 오류부터 확인 부탁드려요. 확인이 끝나면 내일 3시에 결과를 받기를 원해요. 지금은 배포하지 마세요.",
            "EX13": "JEV로 OpenNoType 문장을 다듬기를 원해요. 뜻은 유지하면서 읽기 편한 표현으로 바꿔 주시겠어요?",
            "EX14": "I would like JEV to improve OpenNoType. Review the names first. If approved, send the result at 3 pm on Friday. Do not publish it before approval."
        }
        for case_id, output in alternatives.items():
            with self.subTest(case=case_id):
                self.assertTrue(all(check["passed"] for check in bench.quality_checks(indexed[case_id], output)))

    def test_name_review_request_allows_explicit_action_chains(self):
        cases, _ = bench.load_cases(EXPRESSION_FIXTURE, None)
        case = next(case for case in cases if case["id"] == "EX10")
        actions = ["검토한 뒤", "검토하고", "검토한 다음", "확인한 후", "살펴본 뒤"]
        for action in actions:
            output = ("JEV로 OpenNoType을 개선하고 싶어요. 이름 오류를 먼저 " + action
                      + ", 검토가 끝나면 내일 3시에 결과를 보내 주세요. 지금은 배포하지 마세요.")
            with self.subTest(action=action):
                self.assertTrue(all(check["passed"] for check in bench.quality_checks(case, output)))

    def test_name_review_condition_alone_does_not_preserve_the_review_request(self):
        cases, _ = bench.load_cases(EXPRESSION_FIXTURE, None)
        case = next(case for case in cases if case["id"] == "EX10")
        conditions = ["검토가 끝나면", "검토를 마치면", "확인이 끝나면", "검토가 끝난 뒤"]
        deliveries = ["보내 주세요", "전달해 주세요", "공유 부탁드려요"]
        for condition in conditions:
            for delivery in deliveries:
                output = ("JEV로 OpenNoType을 개선하고 싶어요. 이름 오류 " + condition
                          + ", 내일 3시에 결과를 " + delivery + ". 지금은 배포하지 마세요.")
                with self.subTest(condition=condition, delivery=delivery):
                    checks = bench.quality_checks(case, output)
                    failed = {check["name"] for check in checks if not check["passed"]}
                    self.assertIn("Name review remains a request", failed)
                    self.assertNotIn("Improvement remains a wish", failed)
                    self.assertNotIn("Sending result remains a request", failed)

    def test_expression_request_cannot_be_absorbed_into_a_personal_wish(self):
        cases, _ = bench.load_cases(EXPRESSION_FIXTURE, None)
        case = next(case for case in cases if case["id"] == "EX06")
        output = "JEV로 OpenNoType 문장을 의미는 유지하면서 더 읽기 쉽게 다듬고 싶어요."
        failed = {check["name"] for check in bench.quality_checks(case, output) if not check["passed"]}
        self.assertEqual({"Expression change remains a request"}, failed)

    def test_optional_expression_keeps_old_profiles_and_disabled_settings_inactive(self):
        cases, _ = bench.load_cases(FIXTURE, None)
        self.assertTrue(all(bench.fixture_expression(case) is None for case in cases))
        for setting in [None, {"style": "faithful", "strength": 100}, {"style": "summary", "strength": 0}]:
            case = {"writing_profile": {"kind": "notes", "tone": "preserve", "expression": setting}}
            self.assertIsNone(bench.fixture_expression(case))
        self.assertEqual({"style": "summary", "strength": 75}, bench.fixture_expression(
            {"writing_profile": {"kind": "general", "tone": "preserve", "expression": {"style": "summary", "strength": 75}}}))

    def test_invalid_explicit_expression_never_silently_runs_a_different_policy(self):
        for setting in ["summary", {}, {"style": "unknown", "strength": 50}, {"style": [], "strength": 50},
                        {"style": "summary", "strength": -1}, {"style": "summary", "strength": 101},
                        {"style": "summary", "strength": True}, {"style": "summary", "strength": 50.5},
                        {"style": "summary", "strength": "50"}]:
            with self.subTest(setting=setting), self.assertRaisesRegex(bench.BenchError, "invalid_dictation_expression"):
                bench.fixture_expression({"writing_profile": {"kind": "general", "tone": "preserve", "expression": setting}})

    def test_export_rejects_a_harness_that_dropped_the_requested_expression(self):
        case = {"id": "EX", "writing_profile": {"kind": "general", "tone": "preserve",
                                                 "expression": {"style": "summary", "strength": 75}}}
        body = {"model": "test/model", "max_tokens": 16384, "provider": {"allow_fallbacks": False, "require_parameters": True},
                "messages": [{"role": "user", "content": json.dumps({"spoken_text": "synthetic"})}]}
        exported = [{"id": "EX", "model": "test/model", "endpoint": bench.ENDPOINT,
                     "body_base64": base64.b64encode(bench.json_bytes(body)).decode()}]
        with mock.patch.object(bench, "harness", return_value=exported), self.assertRaisesRegex(bench.BenchError, "production_expression_mismatch"):
            bench.export_requests(Path("unused"), [case], {"test/model": {}})

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


@unittest.skipUnless(shutil.which("swiftc"), "Standalone Core export requires swiftc")
class ExpressionProductionHarnessTests(unittest.TestCase):
    """No key or external request. ReplayProtocol captures the actual production request builder."""
    @classmethod
    def setUpClass(cls):
        cls.scratch = tempfile.TemporaryDirectory(prefix="opennotype-expression-export-test-")
        try:
            cls.binary, _ = bench.compile_harness(cls.scratch.name)
        except Exception:
            cls.scratch.cleanup()
            raise

    @classmethod
    def tearDownClass(cls):
        cls.scratch.cleanup()

    def export_payloads(self, cases):
        model = "openai/gpt-6-luna"
        exported = bench.export_requests(self.binary, cases, {model: {}})
        return {case["id"]: json.loads(json.loads(exported[(case["id"], model)]["body"])["messages"][-1]["content"])
                for case in cases}

    def test_actual_core_export_preserves_active_styles_and_recognition_sources(self):
        cases, _ = bench.load_cases(EXPRESSION_FIXTURE, None)
        payloads = self.export_payloads(cases)
        for case in cases:
            payload = payloads[case["id"]]
            self.assertEqual(case["stt_input"], payload["spoken_text"])
            self.assertEqual(bench.fixture_expression(case), payload.get("dictation_expression"))
            self.assertEqual({key: case["writing_profile"][key] for key in ("kind", "tone")}, payload["writing_profile"])

    def test_actual_core_export_keeps_legacy_profile_and_zero_strength_requests_identical(self):
        cases, _ = bench.load_cases(FIXTURE, 1)
        original = cases[0]
        disabled = json.loads(json.dumps(original))
        disabled["id"] = "zero-strength"
        disabled["writing_profile"]["expression"] = {"style": "summary", "strength": 0}
        model = "openai/gpt-6-luna"
        exported = bench.export_requests(self.binary, [original, disabled], {model: {}})
        self.assertEqual(exported[(original["id"], model)]["body"], exported[(disabled["id"], model)]["body"])


if __name__ == "__main__":
    unittest.main()
