#!/usr/bin/env python3
"""합성 라벨, 비용 예약, 전송 제한, 완료율을 검증합니다. 실제 API 호출 없음."""
import argparse
from contextlib import redirect_stdout
from decimal import Decimal
import importlib.util
import io
import json
from pathlib import Path
import socket
import tempfile
import unittest
from unittest import mock

SPEC = importlib.util.spec_from_file_location("compare_decisions", Path(__file__).with_name("compare-decisions.py"))
bench = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(bench)
FIXTURES = bench.ROOT / "docs/fixtures/decision-quality.json"


class NoSecretEnv(dict):
    def get(self, name, default=None):
        if name == "OPENROUTER_API_KEY":
            raise AssertionError("secret accessed")
        return default

    def __getitem__(self, name):
        if name == "OPENROUTER_API_KEY":
            raise AssertionError("secret accessed")
        raise KeyError(name)


class FakeResponse:
    def __init__(self, status=200, data=b'{}', headers=None):
        self.status = status
        self.data = data
        self.headers = headers or {}
        self.reads = 0

    def getheader(self, key, default=None):
        return self.headers.get(key, default)

    def read1(self, limit):
        self.reads += 1
        chunk, self.data = self.data[:limit], self.data[limit:]
        return chunk


class FakeConnection:
    def __init__(self, response):
        self.response = response
        self.sock = mock.Mock()
        self.requests = []
        self.closed = False

    def request(self, *args, **kwargs):
        self.requests.append((args, kwargs))

    def getresponse(self):
        return self.response

    def close(self):
        self.closed = True


class DecisionFixtureTests(unittest.TestCase):
    def setUp(self):
        self.document, _ = bench.load_fixtures(FIXTURES)

    def test_balanced_curated_good_bad_pairs(self):
        cases = self.document["cases"]
        self.assertEqual(72, len(cases))
        for category in bench.CATEGORIES:
            selected = [c for c in cases if c["category"] == category]
            self.assertEqual(8, len(selected))
            self.assertEqual(4, sum(c["quality"] == "good" for c in selected))
        for axis in bench.AXES:
            self.assertTrue(any(c["expected"][axis] for c in cases))
            self.assertTrue(any(not c["expected"][axis] for c in cases))
        all_choices = {choice for c in cases for choice in c["expected"]["terms"].values()}
        self.assertEqual(bench.CHOICES, all_choices)

    def test_loanword_style_error_is_not_labelled_as_semantic_error(self):
        cases = [c for c in self.document["cases"] if c["category"] == "ordinary_loanwords" and c["quality"] == "bad"]
        for case in cases:
            self.assertFalse(any(case["expected"][axis] for axis in bench.AXES))
            self.assertEqual({"keep_original"}, set(case["expected"]["terms"].values()))

    def test_label_validation_rejects_ambiguous_term_and_unpaired_case(self):
        self.document["cases"][0]["expected"]["terms"]["router"] = "generated_new_spelling"
        with tempfile.TemporaryDirectory() as scratch:
            file = Path(scratch) / "fixtures.json"
            file.write_text(json.dumps(self.document))
            with self.assertRaisesRegex(bench.BenchmarkError, "term_expectations"):
                bench.load_fixtures(file)
        self.document, _ = bench.load_fixtures(FIXTURES)
        self.document["cases"][0]["pair_id"] = "orphan"
        with tempfile.TemporaryDirectory() as scratch:
            file = Path(scratch) / "fixtures.json"
            file.write_text(json.dumps(self.document))
            with self.assertRaisesRegex(bench.BenchmarkError, "good_bad_pair"):
                bench.load_fixtures(file)


class DecisionBudgetTests(unittest.TestCase):
    def test_request_questions_are_included_and_utf8_is_conservative(self):
        short = json.dumps({"state": "한글", "questions": {"noul": "검사"}}, ensure_ascii=False).encode()
        long = json.dumps({"state": "한글", "questions": {"noul": "검사" * 100}}, ensure_ascii=False).encode()
        self.assertGreater(bench.reserve_usd(long), bench.reserve_usd(short))
        self.assertEqual(Decimal(len(short) + 4096) * Decimal("0.042") / 1_000_000, bench.reserve_usd(short))

    def test_budget_requires_finite_positive_small_amount(self):
        for value in ("0", "-1", "NaN", "Infinity", "1.01", "nonsense"):
            with self.subTest(value=value), self.assertRaises(argparse.ArgumentTypeError):
                bench.max_usd(value)
        self.assertEqual(Decimal("0.10"), bench.max_usd("0.10"))

    def test_dry_run_never_reads_key_or_opens_network(self):
        document, _ = bench.load_fixtures(FIXTURES)
        exported = {c["id"]: json.dumps({"model": bench.MODEL, "state": c["transcript"], "questions": {}}).encode() for c in document["cases"]}
        with mock.patch.object(bench, "build_harness", return_value=(Path("unused"), {})), \
             mock.patch.object(bench, "export_requests", return_value=exported), \
             mock.patch.object(bench.os, "environ", NoSecretEnv()), \
             mock.patch.object(bench, "post_once", side_effect=AssertionError("network opened")), redirect_stdout(io.StringIO()):
            self.assertEqual(0, bench.main([]))

    def test_over_budget_stops_before_key_lookup_and_network(self):
        document, _ = bench.load_fixtures(FIXTURES)
        exported = {c["id"]: b'{"question":"synthetic"}' for c in document["cases"]}
        with mock.patch.object(bench, "build_harness", return_value=(Path("unused"), {})), \
             mock.patch.object(bench, "export_requests", return_value=exported), \
             mock.patch.object(bench.os, "environ", NoSecretEnv()), \
             mock.patch.object(bench, "post_once", side_effect=AssertionError("network opened")), redirect_stdout(io.StringIO()):
            self.assertEqual(1, bench.main(["--live", "--max-usd", "0.00000001"]))


class DecisionTransportTests(unittest.TestCase):
    def test_single_fixed_endpoint_request_has_no_retry(self):
        connection = FakeConnection(FakeResponse(data=b'{"synthetic":true}'))
        factory = mock.Mock(return_value=connection)
        result = bench.post_once(b'{"questions":{}}', "synthetic-test-key", 10, factory)
        self.assertEqual({"synthetic": True}, result["response"])
        factory.assert_called_once()
        self.assertEqual(1, len(connection.requests))
        self.assertEqual(("POST", "/api/alpha/decisions"), connection.requests[0][0])
        self.assertTrue(connection.closed)

    def test_redirect_is_rejected_without_read_or_follow(self):
        response = FakeResponse(status=307, headers={"Location": "https://example.test/collect"})
        connection = FakeConnection(response)
        result = bench.post_once(b'{}', "synthetic-test-key", 10, lambda *a, **k: connection)
        self.assertEqual("redirect_rejected", result["error"])
        self.assertEqual(0, response.reads)
        self.assertEqual(1, len(connection.requests))

    def test_declared_or_streamed_oversized_response_is_bounded(self):
        for response in (FakeResponse(headers={"Content-Length": "128001"}), FakeResponse(data=b'x' * 128001)):
            connection = FakeConnection(response)
            result = bench.post_once(b'{}', "synthetic-test-key", 10, lambda *a, **k: connection)
            self.assertEqual("response_too_large", result["error"])
            self.assertTrue(connection.closed)

    def test_timeout_is_not_retried_or_returned_as_pass(self):
        connection = FakeConnection(FakeResponse())
        connection.getresponse = mock.Mock(side_effect=socket.timeout())
        factory = mock.Mock(return_value=connection)
        result = bench.post_once(b'{}', "synthetic-test-key", 1.5, factory)
        self.assertEqual("timed_out", result["error"])
        factory.assert_called_once()
        self.assertEqual(1, len(connection.requests))

    def test_nonfinite_and_compressed_response_are_not_accepted(self):
        self.assertIsNone(bench.decode_json(b'{"noul": NaN}'))
        self.assertIsNone(bench.decode_json(b'not json'))
        response = FakeResponse(headers={"Content-Encoding": "gzip"})
        result = bench.post_once(b'{}', "synthetic-test-key", 10, lambda *a, **k: FakeConnection(response))
        self.assertEqual("unsupported_response_encoding", result["error"])


class DecisionMetricsTests(unittest.TestCase):
    def test_incomplete_requests_not_counted_as_correct_and_missing_cost_not_zero(self):
        cases = [{"id": "good", "category": "technical_names", "expected": dict.fromkeys(bench.AXES, False) | {"terms": {"term": "use_candidate"}}},
                 {"id": "bad", "category": "technical_names", "expected": {"meaning_changed": True, "content_added": False, "content_omitted": False, "terms": {}}},
                 {"id": "failed", "category": "technical_names", "expected": {"meaning_changed": True, "content_added": False, "content_omitted": False, "terms": {}}}]
        records = {"good": {"ok": True, "risk": dict.fromkeys(bench.AXES, .01), "elapsed_seconds": .5,
                            "terms": [{"id": "term", "choice": "use_candidate"}], "usage": {"provider_reported_cost_usd": 0}},
                   "bad": {"ok": True, "risk": {"meaning_changed": .8, "content_added": .01, "content_omitted": .01},
                           "elapsed_seconds": 2, "terms": [], "usage": {"provider_reported_cost_usd": .0001}},
                   "failed": {"ok": False, "error": "timed_out", "elapsed_seconds": 10, "usage": {}}}
        result = bench.metrics(cases, records)
        self.assertEqual(2 / 3, result["inspection_completion_rate"])
        self.assertEqual(1 / 3, result["runtime_inspection_completion_rate"])
        self.assertEqual(2 / 3, result["runtime_deadline_exceeded_rate"])
        self.assertEqual(1, result["provider_cost"]["unknown_cost_requests"])
        self.assertEqual(2, result["provider_cost"]["known_cost_requests"])
        self.assertEqual("0.0001", result["provider_cost"]["reported_total_usd"])
        self.assertEqual(1, result["semantic_thresholds"]["0.7"]["meaning_changed"]["tp"])
        self.assertEqual(1, result["semantic_thresholds"]["0.9"]["meaning_changed"]["fn"])
        self.assertEqual(1, result["terms"]["accuracy"])
        self.assertEqual({"timed_out": 1}, result["errors"])

    def test_all_cost_unknown_remains_null(self):
        result = bench.metrics([], {"one": {"ok": False, "error": "connection_failed", "usage": {}}})
        self.assertIsNone(result["provider_cost"]["reported_total_usd"])
        self.assertIsNone(result["latency_seconds"]["validated_p95"])
        self.assertIsNone(result["semantic_thresholds"]["0.9"]["meaning_changed"]["sensitivity"])


if __name__ == "__main__":
    unittest.main()
