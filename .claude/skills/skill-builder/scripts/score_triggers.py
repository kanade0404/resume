# ruff: noqa: T201, INP001, D103
"""Score trigger predictions for a target skill.

Inputs:
  --cases   evals/<skill>-trigger.json
  --preds   evals/<skill>-trigger-results-<date>.jsonl

Each prediction line: {"id": "...", "predicted": bool, "reason": "..."}

Outputs to stdout: per-tag breakdown plus overall confusion matrix and F1.
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import defaultdict
from pathlib import Path


def load_cases(path: Path) -> dict[str, dict]:
    data = json.loads(path.read_text(encoding="utf-8"))
    return {c["id"]: c for c in data["cases"]}


def load_preds(path: Path) -> dict[str, dict]:
    preds: dict[str, dict] = {}
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        stripped = raw_line.strip()
        if not stripped:
            continue
        obj = json.loads(stripped)
        preds[obj["id"]] = obj
    return preds


def confusion(cases: dict, preds: dict) -> dict:
    tp = fp = tn = fn = 0
    failures: list[tuple[str, str, str]] = []
    missing: list[tuple[str, str]] = []
    for cid, case in cases.items():
        pred = preds.get(cid)
        if pred is None:
            missing.append((cid, case["prompt"]))
            continue
        actual = bool(case["should_trigger"])
        predicted = bool(pred["predicted"])
        if actual and predicted:
            tp += 1
        elif actual and not predicted:
            fn += 1
            failures.append(("FN", cid, case["prompt"]))
        elif (not actual) and predicted:
            fp += 1
            failures.append(("FP", cid, case["prompt"]))
        else:
            tn += 1
    return {"tp": tp, "fp": fp, "tn": tn, "fn": fn, "failures": failures, "missing": missing}


def metrics(c: dict) -> dict:
    tp, fp, fn = c["tp"], c["fp"], c["fn"]
    precision = tp / (tp + fp) if (tp + fp) else 0.0
    recall = tp / (tp + fn) if (tp + fn) else 0.0
    f1 = 2 * precision * recall / (precision + recall) if (precision + recall) else 0.0
    return {"precision": precision, "recall": recall, "f1": f1}


def per_tag(cases: dict, preds: dict) -> dict:
    by_tag: dict[str, dict] = defaultdict(lambda: {"tp": 0, "fp": 0, "tn": 0, "fn": 0})
    for cid, case in cases.items():
        pred = preds.get(cid)
        if pred is None:
            continue
        actual = bool(case["should_trigger"])
        predicted = bool(pred["predicted"])
        for tag in case.get("tags", ["_untagged"]):
            bucket = by_tag[tag]
            if actual and predicted:
                bucket["tp"] += 1
            elif actual and not predicted:
                bucket["fn"] += 1
            elif (not actual) and predicted:
                bucket["fp"] += 1
            else:
                bucket["tn"] += 1
    return by_tag


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--cases", required=True, type=Path)
    ap.add_argument("--preds", required=True, type=Path)
    ap.add_argument(
        "--fail-on-mismatch",
        action="store_true",
        help="Exit non-zero when predictions mismatch or are missing.",
    )
    args = ap.parse_args()

    cases = load_cases(args.cases)
    preds = load_preds(args.preds)

    overall = confusion(cases, preds)
    m = metrics(overall)

    total = sum(overall[k] for k in ("tp", "fp", "tn", "fn"))
    print(f"# Trigger scoring: {args.cases.name}")
    print(f"predictions: {args.preds.name}")
    print(f"cases scored: {total}")
    print()
    print("## Confusion matrix")
    print(f"  TP={overall['tp']}  FP={overall['fp']}")
    print(f"  FN={overall['fn']}  TN={overall['tn']}")
    print()
    print("## Metrics")
    print(f"  precision = {m['precision']:.3f}")
    print(f"  recall    = {m['recall']:.3f}")
    print(f"  F1        = {m['f1']:.3f}")
    print()
    print("## Per-tag")
    for tag, b in sorted(per_tag(cases, preds).items()):
        bm = metrics(b)
        n = b["tp"] + b["fp"] + b["tn"] + b["fn"]
        print(
            f"  {tag:<11} n={n}  "
            f"TP={b['tp']} FP={b['fp']} FN={b['fn']} TN={b['tn']}  "
            f"P={bm['precision']:.2f} R={bm['recall']:.2f} F1={bm['f1']:.2f}"
        )
    print()
    if overall["failures"]:
        print("## Failures")
        for kind, cid, prompt in overall["failures"]:
            print(f"  [{kind}] {cid}: {prompt}")

    if overall["missing"]:
        print("## Missing predictions")
        for cid, prompt in overall["missing"]:
            print(f"  [MISSING] {cid}: {prompt}")

    if args.fail_on_mismatch and (overall["failures"] or overall["missing"]):
        sys.exit(1)


if __name__ == "__main__":
    main()
