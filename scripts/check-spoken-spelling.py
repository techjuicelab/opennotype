#!/usr/bin/env python3
"""저장된 철자 정리 평가 보고서를 추가 API 호출 없이 검사합니다."""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "docs/fixtures/spoken-spelling.json"
FIXTURE_SHA256 = "6c58bce8de30e39d650c72b7dbc992865c11842b820878e3924b356684e23d1b"
MODEL = "qwen/qwen3-30b-a3b-instruct-2507"
UPPERCASE_CASES = {"S01_user_utterance", "S02_stt_homophone", "S03_explicit_spelling",
                   "S04_explicit_correction", "S05_inline_latin_letters", "S06_shared_particle",
                   "S08_dictionary_conflict"}


def load_report(path):
    opener = gzip.open if path.suffix == ".gz" else open
    with opener(path, "rb") as stream:
        raw = stream.read(2_000_001)
    if len(raw) > 2_000_000:
        raise ValueError("report_too_large")
    return json.loads(raw)


def validate_report(report):
    raw = FIXTURE.read_bytes()
    if hashlib.sha256(raw).hexdigest() != FIXTURE_SHA256:
        raise ValueError("frozen_fixture_changed")
    cases = json.loads(raw)["cases"]
    ids = {case["id"] for case in cases}
    if len(cases) != 16 or len(ids) != 16:
        raise ValueError("invalid_fixture_count")
    if (report.get("mode") != "live" or report.get("models") != [MODEL]
            or report.get("planned_requests") != 16 or report.get("fixture_sha256") != FIXTURE_SHA256
            or report.get("fixtures") != cases):
        raise ValueError("report_does_not_match_frozen_live_evaluation")
    for field in ("requests", "results"):
        rows = report.get(field)
        if (not isinstance(rows, list) or len(rows) != 16
                or any(not isinstance(row, dict) or row.get("model") != MODEL for row in rows)
                or [row.get("id") for row in rows].count(None)
                or {row["id"] for row in rows} != ids):
            raise ValueError("incomplete_or_duplicate_" + field)
    by_id = {row["id"]: row for row in report["results"]}
    failures = {}
    for case in cases:
        row = by_id[case["id"]]
        reasons = []
        text = row.get("text")
        if row.get("ok") is not True or not isinstance(text, str) or not text.strip():
            failures[case["id"]] = ["API_or_parser_failed"]
            continue
        recomputed = [{"name": check["name"], "passed":
                       bool(re.search(check["regex"], text, re.I | re.S)) == check["must_match"]}
                      for check in case["checks"]]
        base_pass = all(check["passed"] for check in recomputed)
        if row.get("checks") != recomputed or row.get("automatic_checks_passed") is not base_pass:
            reasons.append("recorded_checks_disagree_with_output")
        reasons += [check["name"] for check in recomputed if not check["passed"]]
        if case["id"] in UPPERCASE_CASES:
            matches = re.findall(r"(?<![A-Za-z])jev(?![A-Za-z])", text, re.I)
            if not matches or any(value != "JEV" for value in matches):
                reasons.append("Exact_uppercase_JEV_required")
        if case["id"] == "S07_unfamiliar_user_named_term" and "루멕스" in text:
            reasons.append("No_duplicate_RUMEX_phonetic_name")
        if case["id"] == "S08_dictionary_conflict" and re.search(r"제브|제부", text):
            reasons.append("No_duplicate_JEV_phonetic_name")
        if case["id"] == "S13_keep_code_identifier":
            matches = re.findall(r"(?<![A-Za-z0-9_])j_e_v(?![A-Za-z0-9_])", text, re.I)
            if not matches or any(value != "j_e_v" for value in matches):
                reasons.append("Exact_case_sensitive_identifier_required")
        if reasons:
            failures[case["id"]] = reasons
    return len(cases), failures


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", type=Path, help="compare-text-models.py의 JSON 또는 JSON.gz 결과")
    args = parser.parse_args(argv)
    try:
        count, failures = validate_report(load_report(args.report))
    except (OSError, ValueError, TypeError, KeyError, AttributeError, EOFError) as error:
        print("FAIL: " + str(error), file=sys.stderr)
        return 1
    for case_id, reasons in failures.items():
        print("FAIL " + case_id + ": " + ", ".join(reasons))
    print(f"CHECKS: {count - len(failures)}/{count} passing; manual semantic review still required")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
