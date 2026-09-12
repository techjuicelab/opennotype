#!/usr/bin/env python3
"""Offline named-variant routing, reservation, identity and resume tests."""

import contextlib
import copy
from decimal import Decimal
import importlib.util
import io
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest import mock


SPEC = importlib.util.spec_from_file_location("cleanup_variants", Path(__file__).with_name("compare-cleanup-variants.py"))
variants_runner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(variants_runner)
core = variants_runner.core


class NoKeyAccess(dict):
    def get(self, key, default=None):
        if key == "GROQ_API_KEY":
            raise AssertionError("키를 읽으면 안 되는 경로입니다")
        return default


class NamedVariantTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.labels = ["codex", "claude", "integrated"]
        self.paths = {}
        for label in self.labels:
            cases = []
            for index in range(1, 4):
                fixture = {"id": f"FC{index:02}", "mode": "dictation", "stt_input": f"어 자료 {index}을 보내 줘",
                           "expected_text": f"자료 {index}을 보내 줘.", "preservation_conditions": ["자료 전송 부탁"],
                           "forbidden_changes": ["실제 전송 실행"], "dictionary": [],
                           "writing_profile": {"kind": "general", "tone": "preserve"}}
                cases.append({"fixture": fixture, "instructions": f"{label}-FC{index:02} 정리 지시",
                              "input": json.dumps({"mode": "dictation", "spoken_text": fixture["stt_input"],
                                                   "dictionary": [], "writing_profile": fixture["writing_profile"]},
                                                  ensure_ascii=False, sort_keys=True)})
            document = {"schema_version": 1, "status": core.EXPORT_STATUS,
                        "fixture_sha256": "a" * 64, "prompt_source_sha256": core.sha256(label.encode()),
                        "source_sha256": core.sha256((label + "-source").encode()), "cases": cases}
            path = self.root / f"{label}.json"
            path.write_text(json.dumps(document, ensure_ascii=False), encoding="utf-8")
            self.paths[label] = path
        self.args = [f"{label}={path}" for label, path in self.paths.items()]
        self.variants, _ = variants_runner.load_variants(self.args)

    def plan(self, **kwargs):
        options = {"model": "openai/gpt-oss-120b", "ids": None, "max_usd": Decimal("0.10")}
        options.update(kwargs)
        return variants_runner.make_variant_plan(self.variants, **options)

    def cli(self, extra=(), variant_args=None):
        args = []
        for value in self.args if variant_args is None else variant_args:
            args.extend(["--variant", value])
        args += ["--output", str(self.root / "report.json"), *extra]
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            return variants_runner.main(args)

    def response(self, case, model, key):
        return {"http_status": 200, "object": {"model": model, "choices": [{"finish_reason": "stop",
                "message": {"content": json.dumps({"text": case["fixture"]["expected_text"]}, ensure_ascii=False)}}]}}

    def test_three_variants_are_once_each_per_case_with_rotating_order(self):
        requests = self.plan()["requests"]
        self.assertEqual(len(requests), 9)
        self.assertEqual([r["variant"] for r in requests],
                         ["codex", "claude", "integrated", "claude", "integrated", "codex", "integrated", "codex", "claude"])
        self.assertEqual(len({(r["id"], r["variant"], r["run"]) for r in requests}), 9)
        self.assertTrue(all(r["run"] == 1 for r in requests))

    def test_full_aggregate_reservation_is_used_not_two_way_subtotal(self):
        plan = self.plan()
        total = sum(Decimal(r["reserved_usd"]) for r in plan["requests"])
        pair = core.make_plan(self.variants["codex"], self.variants["claude"], plan["model"], None, 1, Decimal("0.10"))
        limit = (Decimal(pair["reserved_total_usd"]) + total) / 2
        self.assertGreater(total, limit)
        with mock.patch.object(core.os, "environ", NoKeyAccess()), \
                mock.patch.object(core.http.client, "HTTPSConnection", side_effect=AssertionError("network")):
            self.assertEqual(self.cli(["--max-usd", str(limit)]), 0)
            self.assertEqual(self.cli(["--execute", "--max-usd", str(limit)]), 2)
        report = json.loads((self.root / "report.json").read_text())
        self.assertFalse(report["budget_allows_execution"])
        self.assertEqual(Decimal(report["reserved_total_usd"]), total)

    def test_default_dry_run_reads_no_key_or_network(self):
        with mock.patch.object(core.os, "environ", NoKeyAccess()), \
                mock.patch.object(core.http.client, "HTTPSConnection", side_effect=AssertionError("network")):
            self.assertEqual(self.cli(), 0)
        report = json.loads((self.root / "report.json").read_text())
        self.assertEqual(report["mode"], "dry_run")
        self.assertEqual(report["results"], [])
        self.assertEqual(set(report["variant_exports"]), set(self.labels))

    def test_execution_routes_all_requests_to_their_exact_source(self):
        plan = self.plan()
        observed = []
        def sender(case, model, key):
            observed.append((case["instructions"], case["input"]))
            return self.response(case, model, key)
        core.execute_plan(plan, None, None, "offline-test-key", sender=sender, variants=self.variants)
        expected = [(self.variants[r["variant"]]["cases"][r["id"]]["instructions"],
                     self.variants[r["variant"]]["cases"][r["id"]]["input"]) for r in plan["requests"]]
        self.assertEqual(observed, expected)
        self.assertEqual(len(plan["results"]), 9)

    def test_labels_paths_symlinks_and_hardlinks_cannot_duplicate(self):
        symlink = self.root / "symlink.json"
        symlink.symlink_to(self.paths["codex"])
        hardlink = self.root / "hardlink.json"
        os.link(self.paths["codex"], hardlink)
        for args in ([self.args[0], f"codex={self.paths['claude']}"],
                     [self.args[0], f"other={self.paths['codex']}"],
                     [self.args[0], f"other={symlink}"], [self.args[0], f"other={hardlink}"],
                     [], [self.args[0], f"bad label={self.paths['claude']}"]):
            with self.subTest(args=args), self.assertRaises(core.EvaluationError):
                variants_runner.load_variants(args)

    def test_zero_variants_are_rejected_before_planning(self):
        with self.assertRaises(core.EvaluationError):
            variants_runner.load_variants([])
        with self.assertRaises(core.EvaluationError):
            variants_runner.make_variant_plan({}, "openai/gpt-oss-120b", None, Decimal("0.10"))

    def test_single_variant_reserves_and_executes_each_case_only_once(self):
        sources, paths = variants_runner.load_variants([self.args[2]])
        self.assertEqual(set(sources), {"integrated"})
        self.assertEqual(paths, {self.paths["integrated"].resolve()})
        expected_cost = sum(core.reservation(case, "openai/gpt-oss-120b")[1]
                            for case in sources["integrated"]["cases"].values())
        plan = variants_runner.make_variant_plan(sources, "openai/gpt-oss-120b", None, expected_cost)
        self.assertEqual(len(plan["requests"]), 3)
        self.assertEqual(Decimal(plan["reserved_total_usd"]), expected_cost)
        self.assertTrue(plan["budget_allows_execution"], "임시 비교 쌍의 두 배 비용을 예약하면 안 됩니다")
        self.assertEqual([(r["id"], r["variant"], r["run"]) for r in plan["requests"]],
                         [("FC01", "integrated", 1), ("FC02", "integrated", 1), ("FC03", "integrated", 1)])
        sender = mock.Mock(side_effect=self.response)
        core.execute_plan(plan, None, None, "offline-test-key", variants=sources, sender=sender)
        self.assertEqual(sender.call_count, 3)
        self.assertEqual([call.args[0]["instructions"] for call in sender.call_args_list],
                         [f"integrated-FC{i:02} 정리 지시" for i in range(1, 4)])
        single_case = variants_runner.make_variant_plan(sources, "openai/gpt-oss-120b", "FC02", Decimal("0.10"))
        sender.reset_mock()
        core.execute_plan(single_case, None, None, "offline-test-key", variants=sources, sender=sender)
        self.assertEqual(sender.call_count, 1)

    def test_single_variant_dry_run_and_over_budget_never_read_key(self):
        with mock.patch.object(core.os, "environ", NoKeyAccess()), \
                mock.patch.object(core.http.client, "HTTPSConnection", side_effect=AssertionError("network")):
            self.assertEqual(self.cli(variant_args=[self.args[2]]), 0)
            report = json.loads((self.root / "report.json").read_text())
            self.assertEqual(len(report["requests"]), 3)
            self.assertEqual(set(report["variant_exports"]), {"integrated"})
            self.assertEqual(self.cli(["--execute", "--max-usd", "0.0000001"], variant_args=[self.args[2]]), 2)

    def test_single_variant_resume_only_sends_unstarted_cases(self):
        sources, _ = variants_runner.load_variants([self.args[2]])
        def planned():
            return variants_runner.make_variant_plan(sources, "openai/gpt-oss-120b", None, Decimal("0.10"))
        plan = planned()
        path = self.root / "single-resume.json"
        with self.assertRaises(RuntimeError):
            core.execute_plan(plan, None, None, "offline-test-key", variants=sources,
                              sender=mock.Mock(side_effect=RuntimeError("interrupted")),
                              save=lambda value: core.write_report(value, path))
        resumed = core.resume_plan(path, planned())
        first = copy.deepcopy(resumed["results"][0])
        sender = mock.Mock(side_effect=self.response)
        core.execute_plan(resumed, None, None, "offline-test-key", variants=sources, sender=sender)
        self.assertEqual(sender.call_count, 2)
        self.assertEqual([call.args[0]["fixture"]["id"] for call in sender.call_args_list], ["FC02", "FC03"])
        self.assertEqual(resumed["results"][0], first)
        self.assertEqual(first["status"], "request_started_result_unknown")
        self.assertEqual(resumed["reserved_total_usd"], plan["reserved_total_usd"])
        core.execute_plan(resumed, None, None, "offline-test-key", variants=sources, sender=sender)
        self.assertEqual(sender.call_count, 2)

    def test_mismatched_exports_are_rejected_even_in_unselected_cases(self):
        for mutation in ("fixture_hash", "fixture", "input", "missing_case"):
            altered = copy.deepcopy(self.variants)
            source = altered["integrated"]
            if mutation == "fixture_hash":
                source["document"]["fixture_sha256"] = "c" * 64
            elif mutation == "fixture":
                source["cases"]["FC03"]["fixture"]["expected_text"] = "다른 명세"
            elif mutation == "input":
                source["cases"]["FC03"]["input"] += " "
            else:
                del source["cases"]["FC03"]
            with self.subTest(mutation=mutation), self.assertRaises(core.EvaluationError):
                variants_runner.make_variant_plan(altered, "openai/gpt-oss-120b", "FC01", Decimal("0.10"))

    def test_mutated_source_is_rejected_before_any_request(self):
        plan = self.plan()
        for mutation in ("instructions", "hash", "swapped_variant"):
            altered = copy.deepcopy(self.variants)
            if mutation == "instructions":
                altered["integrated"]["cases"]["FC03"]["instructions"] = "변경"
            elif mutation == "hash":
                altered["integrated"]["sha256"] = "c" * 64
            else:
                altered["codex"], altered["claude"] = altered["claude"], altered["codex"]
            sender = mock.Mock(side_effect=AssertionError("변이된 export로 실행하면 안 됩니다"))
            with self.subTest(mutation=mutation), self.assertRaises(core.EvaluationError):
                core.execute_plan(copy.deepcopy(plan), None, None, "offline-test-key", sender=sender, variants=altered)
            sender.assert_not_called()

    def test_variant_sources_participate_in_hash_and_resume_validation(self):
        plan = self.plan()
        core.execute_plan(plan, None, None, "offline-test-key", variants=self.variants,
                          sender=mock.Mock(return_value={"http_status": 429, "error": "http_error"}))
        path = self.root / "resume.json"
        core.write_report(plan, path)
        modified = self.plan()
        modified["variant_exports"]["integrated"]["source_sha256"] = "c" * 64
        self.assertNotEqual(core.plan_hash(modified), core.plan_hash(self.plan()))
        with self.assertRaises(core.EvaluationError):
            core.resume_plan(path, modified)
        with self.assertRaises(core.EvaluationError):
            core.resume_plan(path, self.plan(ids="FC01"))

    def test_resume_keeps_failed_attempt_and_only_sends_remaining_sources(self):
        plan = self.plan()
        core.execute_plan(plan, None, None, "offline-test-key", variants=self.variants,
                          sender=mock.Mock(return_value={"http_status": 429, "error": "http_error"}))
        first = copy.deepcopy(plan["results"][0])
        reserved = plan["reserved_total_usd"]
        path = self.root / "resume.json"
        core.write_report(plan, path)
        resumed = core.resume_plan(path, self.plan())
        sent = []
        def sender(case, model, key):
            sent.append(case["instructions"])
            return self.response(case, model, key)
        core.execute_plan(resumed, None, None, "offline-test-key", sender=sender, variants=self.variants)
        self.assertEqual(len(sent), 8)
        self.assertNotIn("codex-FC01 정리 지시", sent)
        self.assertEqual(resumed["results"][0], first)
        self.assertEqual(resumed["reserved_total_usd"], reserved)
        core.execute_plan(resumed, None, None, "offline-test-key", sender=sender, variants=self.variants)
        self.assertEqual(len(sent), 8)

    def test_interrupted_attempt_is_never_repeated_on_resume(self):
        plan = self.plan(ids="FC01")
        path = self.root / "interrupted.json"
        with self.assertRaises(RuntimeError):
            core.execute_plan(plan, None, None, "offline-test-key", variants=self.variants,
                              sender=mock.Mock(side_effect=RuntimeError("interrupted")),
                              save=lambda value: core.write_report(value, path))
        resumed = core.resume_plan(path, self.plan(ids="FC01"))
        sender = mock.Mock(side_effect=self.response)
        core.execute_plan(resumed, None, None, "offline-test-key", variants=self.variants, sender=sender)
        self.assertEqual(sender.call_count, 2)
        self.assertEqual(resumed["results"][0]["status"], "request_started_result_unknown")

    def test_completed_cli_resume_needs_no_key_and_preserves_results(self):
        plan = self.plan()
        core.execute_plan(plan, None, None, "offline-test-key", variants=self.variants, sender=self.response)
        core.write_report(plan, self.root / "report.json")
        with mock.patch.object(core.os, "environ", NoKeyAccess()):
            self.assertEqual(self.cli(), 2)
            self.assertEqual(self.cli(["--execute"]), 2)
            self.assertEqual(self.cli(["--execute", "--resume"]), 0)
        self.assertEqual(json.loads((self.root / "report.json").read_text())["results"], plan["results"])

    def test_report_cannot_overwrite_any_variant_export(self):
        original = self.paths["integrated"].read_bytes()
        self.assertEqual(self.cli(["--output", str(self.paths["integrated"])]), 2)
        self.assertEqual(self.paths["integrated"].read_bytes(), original)

    def test_invalid_budget_model_ids_and_interval_fail_without_key(self):
        for limit in ("0", "-1", "NaN", "Infinity", "0.10001"):
            with self.subTest(limit=limit), self.assertRaises(core.EvaluationError):
                self.plan(max_usd=Decimal(limit))
        for ids in ("FC01,FC01", "missing", "FC01,", ""):
            with self.subTest(ids=ids), self.assertRaises(core.EvaluationError):
                self.plan(ids=ids)
        with self.assertRaises(core.EvaluationError):
            self.plan(model="unpriced-model")
        with mock.patch.object(core.os, "environ", NoKeyAccess()):
            self.assertEqual(self.cli(["--execute", "--interval-seconds", "61"]), 2)


if __name__ == "__main__":
    unittest.main()
