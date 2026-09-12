#!/usr/bin/env python3
"""Offline safety/contract tests for compare-cleanup.py; never call a provider."""

import contextlib
from decimal import Decimal
import gzip
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock


SPEC = importlib.util.spec_from_file_location("compare_cleanup", Path(__file__).with_name("compare-cleanup.py"))
evaluation = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(evaluation)


class NoKeyAccess(dict):
    def get(self, key, default=None):
        if key == "GROQ_API_KEY":
            raise AssertionError("This path must not read an API key")
        return default


class CleanupEvaluationTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.before_path = self.root / "before.json"
        self.after_path = self.root / "after.json"
        self.fixture = {
            "id": "FC01", "mode": "dictation", "stt_input": "어 자료를 자료를 보내 줘",
            "writing_profile": {"kind": "general", "tone": "preserve"}, "dictionary": [],
            "expected_text": "자료를 보내 줘.",
            "preservation_conditions": ["자료 전송 요청"], "forbidden_changes": ["전송 완료라고 답변"],
        }
        self.before_path.write_text(json.dumps(self.document("before"), ensure_ascii=False), encoding="utf-8")
        self.after_path.write_text(json.dumps(self.document("after"), ensure_ascii=False), encoding="utf-8")
        self.before = evaluation.read_export(self.before_path)
        self.after = evaluation.read_export(self.after_path)

    def document(self, instructions):
        return {
            "schema_version": 1, "status": evaluation.EXPORT_STATUS,
            "fixture_sha256": "a" * 64, "prompt_source_sha256": "b" * 64,
            "cases": [{"fixture": dict(self.fixture), "instructions": instructions,
                       "input": json.dumps({"mode": "dictation", "spoken_text": self.fixture["stt_input"],
                                            "dictionary": [], "writing_profile": self.fixture["writing_profile"]},
                                           ensure_ascii=False, sort_keys=True)}],
        }

    def plan(self, **kwargs):
        defaults = {"model": "openai/gpt-oss-120b", "ids": None, "repetitions": 1, "max_usd": Decimal("0.10")}
        defaults.update(kwargs)
        return evaluation.make_plan(self.before, self.after, **defaults)

    def cli(self, extra=()):
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            return evaluation.main(["--before", str(self.before_path), "--after", str(self.after_path),
                                    "--output", str(self.root / "report.json"), *extra])

    def response(self, usage=None, text=None, model="openai/gpt-oss-120b", finish="stop"):
        obj = {"model": model, "choices": [{"finish_reason": finish, "message": {
            "content": json.dumps({"text": self.fixture["expected_text"] if text is None else text}, ensure_ascii=False)}}]}
        if usage is not None:
            obj["usage"] = usage
        return {"http_status": 200, "object": obj}

    def test_default_dry_run_reads_neither_keys_nor_network(self):
        with mock.patch.object(evaluation.os, "environ", NoKeyAccess()), \
                mock.patch.object(evaluation.http.client, "HTTPSConnection", side_effect=AssertionError("network")):
            self.assertEqual(self.cli(), 0)
        report = json.loads((self.root / "report.json").read_text())
        self.assertEqual(report["mode"], "dry_run")
        self.assertEqual(report["results"], [])
        self.assertEqual(len(report["requests"]), 2)
        self.assertIn("의미 품질 점수가 아닙니다", (self.root / "report.md").read_text())

    def test_over_budget_dry_run_reports_plan_but_execute_reads_no_key(self):
        with mock.patch.object(evaluation.os, "environ", NoKeyAccess()), \
                mock.patch.object(evaluation.http.client, "HTTPSConnection", side_effect=AssertionError("network")):
            self.assertEqual(self.cli(["--max-usd", "0.0000001"]), 0)
            self.assertFalse(json.loads((self.root / "report.json").read_text())["budget_allows_execution"])
            self.assertEqual(self.cli(["--execute", "--max-usd", "0.0000001"]), 2)

    def test_execute_requires_key_before_network(self):
        with mock.patch.dict(evaluation.os.environ, {}, clear=True), \
                mock.patch.object(evaluation.http.client, "HTTPSConnection", side_effect=AssertionError("network")):
            self.assertEqual(self.cli(["--execute"]), 2)

    def test_budget_rejects_invalid_numbers_and_hard_cap(self):
        for limit in ("0", "-1", "NaN", "Infinity", "0.10001"):
            with self.subTest(limit=limit), self.assertRaises(evaluation.EvaluationError):
                self.plan(max_usd=Decimal(limit))
        for repeats in (0, -1, 101, True):
            with self.subTest(repeats=repeats), self.assertRaises(evaluation.EvaluationError):
                self.plan(repetitions=repeats)

    def test_fixture_ids_reject_unknown_empty_and_duplicates(self):
        for ids in ("missing", "FC01,FC01", "FC01,", ""):
            with self.subTest(ids=ids), self.assertRaises(evaluation.EvaluationError):
                self.plan(ids=ids)
        self.assertEqual(len(self.plan(ids="FC01")["requests"]), 2)

    def test_pairing_rejects_changed_input_fixture_or_fixture_hash(self):
        for mutation in ("input", "fixture", "fixture_sha256"):
            modified = json.loads(json.dumps(self.after))
            if mutation == "input":
                modified["cases"]["FC01"]["input"] += " "
            elif mutation == "fixture":
                modified["cases"]["FC01"]["fixture"]["expected_text"] = "다른 기준"
            else:
                modified["document"][mutation] = "c" * 64
            with self.subTest(mutation=mutation), self.assertRaises(evaluation.EvaluationError):
                evaluation.paired_cases(self.before, modified)

    def test_reader_rejects_duplicate_id_and_nonfixture_input(self):
        duplicate = self.document("prompt")
        duplicate["cases"].append(duplicate["cases"][0])
        changed = self.document("prompt")
        changed["cases"][0]["input"] = json.dumps({"mode": "dictation", "spoken_text": "다른 입력"})
        for document in (duplicate, changed):
            self.after_path.write_text(json.dumps(document), encoding="utf-8")
            with self.assertRaises(evaluation.EvaluationError):
                evaluation.read_export(self.after_path)

    def test_gzip_has_identical_request_budget_and_uncompressed_hash(self):
        compressed = self.root / "before.json.gz"
        with gzip.open(compressed, "wb") as output:
            output.write(self.before_path.read_bytes())
        first = evaluation.read_export(compressed)
        self.assertEqual(first["sha256"], self.before["sha256"])
        plan = evaluation.make_plan(first, self.after, "openai/gpt-oss-120b", None, 1, Decimal("0.10"))
        self.assertEqual(plan["reserved_total_usd"], self.plan()["reserved_total_usd"])
        self.assertGreater(plan["requests"][0]["input_token_upper_bound"], len(first["cases"]["FC01"]["input"].encode()))

    def test_optional_prompt_hash_rejects_changed_instructions_and_accepts_legacy_export(self):
        self.assertEqual(len(evaluation.read_export(self.before_path)["cases"]), 1)
        document = self.document("prompt")
        document["cases"][0]["instructions_sha256"] = "c" * 64
        self.after_path.write_text(json.dumps(document), encoding="utf-8")
        with self.assertRaises(evaluation.EvaluationError):
            evaluation.read_export(self.after_path)
        document["cases"][0]["instructions_sha256"] = evaluation.sha256(b"prompt")
        self.after_path.write_text(json.dumps(document), encoding="utf-8")
        self.assertEqual(len(evaluation.read_export(self.after_path)["cases"]), 1)

    def test_report_cannot_overwrite_an_export(self):
        original = self.before_path.read_bytes()
        with contextlib.redirect_stderr(io.StringIO()):
            result = evaluation.main(["--before", str(self.before_path), "--after", str(self.after_path),
                                      "--output", str(self.before_path)])
        self.assertEqual(result, 2)
        self.assertEqual(self.before_path.read_bytes(), original)

    def test_missing_usage_stays_unknown_but_real_zero_is_zero(self):
        result = evaluation.analyze_response(self.response(), self.fixture, "openai/gpt-oss-120b")
        self.assertIsNone(result["input_tokens"])
        self.assertIsNone(result["output_tokens"])
        self.assertIsNone(result["estimated_uncached_cost_usd"])
        self.assertTrue(result["exact_expected_match"])
        self.assertTrue(result["manual_review_required"])
        zero = evaluation.analyze_response(self.response({"prompt_tokens": 0, "completion_tokens": 0}), self.fixture, "openai/gpt-oss-120b")
        self.assertEqual(Decimal(zero["estimated_uncached_cost_usd"]), Decimal(0))

    def test_invalid_usage_counters_do_not_become_billable_zero(self):
        for invalid in (True, -1, 1.5, "10", float("nan")):
            result = evaluation.analyze_response(self.response({"prompt_tokens": invalid, "completion_tokens": 10}), self.fixture, "openai/gpt-oss-120b")
            self.assertIsNone(result["input_tokens"])
            self.assertIsNone(result["estimated_uncached_cost_usd"])

    def test_incomplete_output_keeps_usage_but_is_not_quality_success(self):
        result = evaluation.analyze_response(self.response({"prompt_tokens": 40, "completion_tokens": 1024}, finish="length"),
                                             self.fixture, "openai/gpt-oss-120b")
        self.assertEqual(result["status"], "incomplete_output")
        self.assertIsNone(result["exact_expected_match"])
        self.assertIsNotNone(result["estimated_uncached_cost_usd"])

    def test_expected_empty_and_unexpected_empty_are_different(self):
        expected = dict(self.fixture, expected_text="")
        result = evaluation.analyze_response(self.response(text=""), expected, "openai/gpt-oss-120b")
        self.assertEqual(result["status"], "expected_empty")
        lost = evaluation.analyze_response(self.response(text=""), self.fixture, "openai/gpt-oss-120b")
        self.assertEqual(lost["status"], "unexpected_empty")

    def test_http_redirect_is_rejected_without_following_or_reading_error_body(self):
        connection = mock.Mock()
        connection.getresponse.return_value.status = 302
        connection.getresponse.return_value.getheaders.return_value = []
        with mock.patch.object(evaluation.http.client, "HTTPSConnection", return_value=connection) as factory:
            result = evaluation.send_request(self.before["cases"]["FC01"], "openai/gpt-oss-120b", "test-secret")
        self.assertEqual(factory.call_count, 1)
        self.assertEqual(factory.call_args.args[0], "api.groq.com")
        self.assertEqual(connection.request.call_args.args[:2], ("POST", "/openai/v1/chat/completions"))
        self.assertEqual(result, {"http_status": 302, "error": "redirect_rejected", "rate_limits": {}})
        connection.getresponse.return_value.read.assert_not_called()
        connection.close.assert_called_once()

    def test_429_stops_without_retry_and_keeps_all_reservations(self):
        plan = self.plan(repetitions=2)
        reserved = plan["reserved_total_usd"]
        sender = mock.Mock(return_value={"http_status": 429, "error": "http_error"})
        evaluation.execute_plan(plan, self.before, self.after, "test-key", sender=sender)
        self.assertEqual(sender.call_count, 1)
        self.assertEqual(plan["reserved_total_usd"], reserved)
        self.assertEqual(plan["stop_reason"], "rate_limited_no_retry")
        self.assertIsNone(plan["results"][0]["estimated_uncached_cost_usd"])

    def test_missing_usage_does_not_refund_reserved_budget(self):
        plan = self.plan()
        reserved = plan["reserved_total_usd"]
        sender = mock.Mock(return_value=self.response())
        evaluation.execute_plan(plan, self.before, self.after, "test-key", sender=sender)
        self.assertEqual(sender.call_count, 2)
        self.assertEqual(plan["reserved_total_usd"], reserved)
        self.assertTrue(all(result["estimated_uncached_cost_usd"] is None for result in plan["results"]))

    def test_unexpected_model_or_exceeded_token_bound_stops_remaining_requests(self):
        for response in (self.response(model="unexpected-model"), self.response({"prompt_tokens": 1_000_000, "completion_tokens": 10})):
            plan = self.plan()
            sender = mock.Mock(return_value=response)
            evaluation.execute_plan(plan, self.before, self.after, "test-key", sender=sender)
            self.assertEqual(sender.call_count, 1)
            self.assertIsNotNone(plan["stop_reason"])

    def test_safe_network_error_and_report_do_not_reveal_key(self):
        connection = mock.Mock()
        connection.request.side_effect = OSError("Authorization Bearer test-secret")
        with mock.patch.object(evaluation.http.client, "HTTPSConnection", return_value=connection):
            result = evaluation.send_request(self.before["cases"]["FC01"], "openai/gpt-oss-120b", "test-secret")
        self.assertNotIn("test-secret", json.dumps(result))
        plan = self.plan()
        evaluation.execute_plan(plan, self.before, self.after, "test-secret", sender=mock.Mock(return_value=self.response(text="test-secret")))
        self.assertNotIn("test-secret", json.dumps(plan))
        self.assertNotIn("test-secret", evaluation.markdown(plan))

    def test_markdown_data_escapes_literal_syntax_pipes_and_line_breaks(self):
        source = "\\path `count != 0 && code < 3` **bold** _word_ [link](target) | end\r\nnext"
        expected = r"\\path \`count \!= 0 &amp;&amp; code &lt; 3\` \*\*bold\*\* \_word\_ \[link\]\(target\) \| end<br>next"
        plan = self.plan()
        plan["fixtures"][0]["stt_input"] = source
        result = dict(plan["requests"][0], **evaluation.analyze_response(
            self.response(text=source), self.fixture, "openai/gpt-oss-120b"))
        result["latency_ms"] = 1.0
        plan["results"] = [result]
        report = evaluation.markdown(plan)
        self.assertEqual(report.count(expected), 2, "Both table output and fixture list must preserve literal text")
        self.assertNotIn("**bold**", report)
        self.assertNotIn("[link](target)", report)

    def test_resume_preserves_failed_prefix_and_reserved_budget_without_repeating(self):
        plan = self.plan(repetitions=2)
        reserved = plan["reserved_total_usd"]
        evaluation.execute_plan(plan, self.before, self.after, "test-key",
                                sender=mock.Mock(return_value={"http_status": 429, "error": "http_error"}))
        output = self.root / "resume.json"
        evaluation.write_report(plan, output)
        resumed = evaluation.resume_plan(output, self.plan(repetitions=2))
        original = dict(resumed["results"][0])
        sender = mock.Mock(return_value=self.response())
        evaluation.execute_plan(resumed, self.before, self.after, "test-key", sender=sender)
        self.assertEqual(sender.call_count, 3)
        self.assertEqual(resumed["results"][0], original)
        self.assertEqual(resumed["reserved_total_usd"], reserved)
        self.assertEqual(len(resumed["results"]), 4)
        sender.reset_mock()
        evaluation.execute_plan(resumed, self.before, self.after, "test-key", sender=sender)
        sender.assert_not_called()

    def test_resume_rejects_plan_mismatch_and_nonprefix_results(self):
        plan = self.plan(repetitions=2)
        evaluation.execute_plan(plan, self.before, self.after, "test-key",
                                sender=mock.Mock(return_value={"http_status": 429, "error": "http_error"}))
        output = self.root / "resume.json"
        evaluation.write_report(plan, output)
        for candidate in (self.plan(), self.plan(repetitions=2, model="openai/gpt-oss-20b"),
                          self.plan(repetitions=2, max_usd=Decimal("0.09"))):
            with self.assertRaises(evaluation.EvaluationError):
                evaluation.resume_plan(output, candidate)
        for mutation in ("wrong_order", "duplicate", "hash"):
            altered = json.loads(json.dumps(plan))
            if mutation == "wrong_order":
                altered["results"][0]["variant"] = "after"
            elif mutation == "duplicate":
                altered["results"].append(altered["results"][0])
            else:
                altered["plan_sha256"] = "c" * 64
            evaluation.write_report(altered, output)
            with self.subTest(mutation=mutation), self.assertRaises(evaluation.EvaluationError):
                evaluation.resume_plan(output, self.plan(repetitions=2))

    def test_resume_rejects_exceeded_token_reservation_before_key_or_network_access(self):
        for field in ("prompt_tokens", "completion_tokens"):
            plan = self.plan()
            bound = (plan["requests"][0]["input_token_upper_bound"] if field == "prompt_tokens"
                     else evaluation.MAX_COMPLETION_TOKENS)
            response = self.response({"prompt_tokens": 10, "completion_tokens": 10, field: bound + 1})
            sender = mock.Mock(return_value=response)
            evaluation.execute_plan(plan, self.before, self.after, "test-key", sender=sender)
            self.assertEqual(plan["stop_reason"], "provider_exceeded_reserved_token_bound")
            self.assertEqual(sender.call_count, 1)
            output = self.root / "report.json"
            evaluation.write_report(plan, output)
            saved = output.read_bytes()
            with self.subTest(field=field), self.assertRaises(evaluation.EvaluationError):
                evaluation.resume_plan(output, self.plan())
            with mock.patch.object(evaluation.os, "environ", NoKeyAccess()), \
                    mock.patch.object(evaluation.http.client, "HTTPSConnection", side_effect=AssertionError("network")):
                self.assertEqual(self.cli(["--execute", "--resume"]), 2)
            self.assertEqual(output.read_bytes(), saved)

    def test_resume_rejects_different_reported_model_before_key_or_network_access(self):
        plan = self.plan()
        sender = mock.Mock(return_value=self.response(model="unexpected-model"))
        evaluation.execute_plan(plan, self.before, self.after, "test-key", sender=sender)
        self.assertEqual(plan["stop_reason"], "unexpected_reported_model")
        self.assertEqual(sender.call_count, 1)
        output = self.root / "report.json"
        evaluation.write_report(plan, output)
        saved = output.read_bytes()
        with self.assertRaises(evaluation.EvaluationError):
            evaluation.resume_plan(output, self.plan())
        with mock.patch.object(evaluation.os, "environ", NoKeyAccess()), \
                mock.patch.object(evaluation.http.client, "HTTPSConnection", side_effect=AssertionError("network")):
            self.assertEqual(self.cli(["--execute", "--resume"]), 2)
        self.assertEqual(output.read_bytes(), saved)

    def test_interrupted_request_is_saved_as_unknown_and_never_replayed(self):
        plan = self.plan()
        output = self.root / "resume.json"
        with self.assertRaises(RuntimeError):
            evaluation.execute_plan(plan, self.before, self.after, "test-key",
                sender=mock.Mock(side_effect=RuntimeError("interrupted")), save=lambda value: evaluation.write_report(value, output))
        resumed = evaluation.resume_plan(output, self.plan())
        self.assertEqual(resumed["results"][0]["status"], "request_started_result_unknown")
        sender = mock.Mock(return_value=self.response())
        evaluation.execute_plan(resumed, self.before, self.after, "test-key", sender=sender)
        self.assertEqual(sender.call_count, 1)
        self.assertEqual(resumed["results"][0]["status"], "request_started_result_unknown")

    def test_request_start_interval_excludes_wait_from_latency(self):
        now = [0.0]
        starts, waits = [], []
        def sleep(seconds):
            waits.append(seconds)
            now[0] += seconds
        def sender(*args):
            starts.append(now[0])
            now[0] += 2.0
            return self.response()
        plan = self.plan()
        evaluation.execute_plan(plan, self.before, self.after, "test-key", sender=sender,
                                interval_seconds=25, clock=lambda: now[0], sleeper=sleep)
        self.assertEqual(starts, [0.0, 25.0])
        self.assertEqual(waits, [23.0])
        self.assertEqual([result["latency_ms"] for result in plan["results"]], [2000.0, 2000.0])
        for value in (-1, 61, float("nan"), float("inf"), True):
            with self.assertRaises(evaluation.EvaluationError):
                evaluation.validate_interval(value)
        self.assertEqual(evaluation.validate_interval(0), 0)
        self.assertEqual(evaluation.validate_interval(60), 60)

    def test_rate_limit_headers_allowlist_excludes_sensitive_headers(self):
        response = mock.Mock()
        response.getheaders.return_value = [("Retry-After", "25"), ("X-RateLimit-Remaining-Tokens", "50"),
            ("Authorization", "secret"), ("Set-Cookie", "secret"), ("X-Request-Id", "secret"),
            ("x-ratelimit-reset-tokens", "x" * 201)]
        self.assertEqual(evaluation.rate_limit_headers(response),
                         {"retry-after": "25", "x-ratelimit-remaining-tokens": "50"})

    def test_existing_execution_cannot_be_overwritten_without_explicit_resume(self):
        plan = self.plan()
        evaluation.execute_plan(plan, self.before, self.after, "test-key", sender=mock.Mock(return_value=self.response()))
        output = self.root / "report.json"
        evaluation.write_report(plan, output)
        original = output.read_bytes()
        with mock.patch.object(evaluation.os, "environ", NoKeyAccess()):
            self.assertEqual(self.cli(), 2)
            self.assertEqual(self.cli(["--execute"]), 2)
            self.assertEqual(self.cli(["--execute", "--resume"]), 0)
        self.assertEqual(json.loads(original)["results"], json.loads(output.read_bytes())["results"])


if __name__ == "__main__":
    unittest.main()
