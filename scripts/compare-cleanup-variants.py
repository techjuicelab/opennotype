#!/usr/bin/env python3
"""Compare named prompt exports once per case, using the existing bounded runner."""

import argparse
from decimal import Decimal, InvalidOperation
import importlib.util
import json
from pathlib import Path
import re
import sys


SPEC = importlib.util.spec_from_file_location("cleanup_comparison_core", Path(__file__).with_name("compare-cleanup.py"))
core = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(core)


def load_variants(values):
    if not 1 <= len(values) <= 8:
        raise core.EvaluationError("--variant는 서로 다른 이름과 파일로 1~8개 지정해 주세요.")
    variants, paths, file_ids = {}, set(), set()
    for value in values:
        label, separator, filename = value.partition("=")
        if not separator or not re.fullmatch(r"[A-Za-z][A-Za-z0-9_-]{0,31}", label) or not filename:
            raise core.EvaluationError("--variant는 영문 label=export.json 형식으로 지정해 주세요.")
        path = Path(filename).resolve()
        if label in variants or path in paths:
            raise core.EvaluationError("variant 이름이나 export 파일이 중복되었습니다.")
        try:
            stat = path.stat()
        except OSError as error:
            raise core.EvaluationError("variant export 파일을 읽을 수 없습니다.") from error
        file_id = (stat.st_dev, stat.st_ino)
        if file_id in file_ids:
            raise core.EvaluationError("같은 export 파일의 다른 링크를 중복 지정할 수 없습니다.")
        variants[label] = core.read_export(path)
        paths.add(path)
        file_ids.add(file_id)
    return variants, paths


def make_variant_plan(variants, model, ids, max_usd):
    labels = list(variants)
    if not 1 <= len(labels) <= 8 or any(not re.fullmatch(r"[A-Za-z][A-Za-z0-9_-]{0,31}", label) for label in labels):
        raise core.EvaluationError("유효한 variant 이름을 1~8개 지정해 주세요.")
    reference = variants[labels[0]]
    # Reuse the legacy validation, pricing and report contract; its paired
    # requests are replaced, never executed or appended to the named requests.
    # A single source is validated against itself. The temporary pair is only
    # scaffolding; its requests and reservation are fully replaced below.
    comparison = variants[labels[1]] if len(labels) > 1 else reference
    plan = core.make_plan(reference, comparison, model, ids, 1, max_usd)
    for label in labels[2:]:
        core.paired_cases(reference, variants[label], ids)
    chosen = [fixture["id"] for fixture in plan["fixtures"]]
    requests, total = [], Decimal("0")
    for case_index, case_id in enumerate(chosen):
        offset = case_index % len(labels)
        order = labels[offset:] + labels[:offset]
        for label in order:
            case = variants[label]["cases"][case_id]
            upper, cost = core.reservation(case, model)
            total += cost
            requests.append({"id": case_id, "variant": label, "run": 1,
                             "input_token_upper_bound": upper, "reserved_usd": str(cost),
                             "prompt_sha256": core.sha256(core.encoded({
                                 "instructions": case["instructions"], "input": case["input"]}))})
    plan["requests"] = requests
    plan["reserved_total_usd"] = str(total)
    plan["budget_allows_execution"] = total <= max_usd
    plan["exports"] = {"fixture_sha256": reference["document"]["fixture_sha256"]}
    plan["variant_exports"] = {
        label: {"sha256": source["sha256"], "fixture_sha256": source["document"]["fixture_sha256"],
                "prompt_source_sha256": source["document"]["prompt_source_sha256"],
                "source_sha256": source["document"].get("source_sha256")}
        for label, source in variants.items()
    }
    return plan


def main(argv=None):
    parser = argparse.ArgumentParser(description="1~8개 프롬프트를 같은 합성 입력으로 각 1회 평가합니다. 기본은 키·API 접근 없는 계획입니다.")
    parser.add_argument("--variant", action="append", required=True, help="label=export.json 또는 label=export.json.gz; 반복 지정")
    parser.add_argument("--model", choices=tuple(core.RATES), default="openai/gpt-oss-120b")
    parser.add_argument("--ids", help="평가할 ID를 쉼표로 구분; 기본 전체")
    parser.add_argument("--max-usd", default="0.10", help="전체 요청 예약 합계의 상한, 최대 US$0.10")
    parser.add_argument("--output", default="cleanup-variants.json")
    parser.add_argument("--execute", action="store_true", help="Groq 유료 API를 실제 호출")
    parser.add_argument("--resume", action="store_true", help="기존 --output의 미실행 요청만 재개; --execute 필요")
    parser.add_argument("--interval-seconds", type=float, default=25, help="요청 시작 간 최소 간격, 기본 25초")
    args = parser.parse_args(argv)
    try:
        variants, source_paths = load_variants(args.variant)
        plan = make_variant_plan(variants, args.model, args.ids, Decimal(args.max_usd))
        interval = core.validate_interval(args.interval_seconds)
        output = Path(args.output)
        if output.suffix != ".json":
            raise core.EvaluationError("--output에는 .json 파일 경로를 지정해 주세요.")
        if {output.resolve(), output.with_suffix(".md").resolve()} & source_paths:
            raise core.EvaluationError("보고서로 원본 export를 덮어쓸 수 없습니다.")
        for target in (output, output.with_suffix(".md")):
            if target.exists() and any(target.samefile(source) for source in source_paths):
                raise core.EvaluationError("보고서가 원본 export의 링크를 덮어쓸 수 없습니다.")
        if args.resume:
            if not args.execute:
                raise core.EvaluationError("--resume은 --execute와 함께 지정해 주세요.")
            plan = core.resume_plan(output, plan)
        else:
            if output.exists():
                try:
                    previous = json.loads(output.read_bytes())
                except (OSError, ValueError) as error:
                    raise core.EvaluationError("기존 보고서를 확인할 수 없어 덮어쓰지 않습니다.") from error
                if isinstance(previous, dict) and previous.get("mode") == "executed":
                    raise core.EvaluationError("기존 실제 실행 보고서는 --execute --resume으로만 재개할 수 있습니다.")
            core.write_report(plan, output)
        if args.execute:
            # All variants and their complete aggregate reservation are checked
            # before touching the environment; an over-budget plan cannot read a key.
            if not plan["budget_allows_execution"]:
                raise core.EvaluationError("전체 variant 예약액이 --max-usd를 넘습니다. 사례 수를 줄여 주세요.")
            if len(plan["results"]) < len(plan["requests"]):
                core.execute_plan(plan, None, None, core.os.environ.get("GROQ_API_KEY"), variants=variants,
                                  save=lambda value: core.write_report(value, output), interval_seconds=interval)
            core.write_report(plan, output)
        print(f"{'실행' if args.execute else '실행 전 계획'}: {len(plan['results'])}/{len(plan['requests'])}건, "
              f"전체 예약 US${plan['reserved_total_usd']}; {args.output}")
        return 0
    except (core.EvaluationError, InvalidOperation) as error:
        print(str(error) if isinstance(error, core.EvaluationError) else "--max-usd는 올바른 숫자여야 합니다.", file=sys.stderr)
        return 2
    except OSError:
        print("평가 파일을 읽거나 보고서를 저장할 수 없습니다.", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
