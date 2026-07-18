# ruff: noqa: T201, S603, INP001, D103, ANN001, ANN202, PLW1510
r"""Run a `claude -p` harness to measure real Skill activations on trigger eval cases.

For each case in evals/<skill>-trigger.json, invokes claude -p N times with
--output-format=stream-json and looks for tool_use events that activate the
target skill. Aggregates triggered_rate per case.

Usage:
  python run_harness.py \
    --cases evals/test-review-trigger.json \
    --target-skill test-review \
    --runs 3 \
    --budget 0.05 \
    --out evals/test-review-trigger-harness-2026-04-27.jsonl

Notes:
- --budget caps each individual claude -p invocation at $X (USD).
- Detection is strict: only tool_use blocks where name == "Skill" and the
  input references the target skill name.
- Set TRIGGER_THRESHOLD to convert triggered_rate to predicted bool.
- `ok` in each result row is the `claude -p` process exit status, NOT the
  eval verdict. A triggering case usually exits non-zero because it hits the
  --budget cap after the Skill activation was already observed, so `ok:false`
  is expected and benign. The authoritative trigger signal is `triggered`
  (stream scan), which is independent of `ok`. Do not chase `ok:true` by
  raising the budget: that only makes claude start *executing* the matched
  skill's workflow (dispatching subagents), which is wasteful and still caps.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

TRIGGER_THRESHOLD = 0.5  # majority of runs


def _walk_tool_uses(node):
    """Yield every dict that looks like a tool_use content block."""
    if isinstance(node, dict):
        if node.get("type") == "tool_use":
            yield node
        for v in node.values():
            yield from _walk_tool_uses(v)
    elif isinstance(node, list):
        for item in node:
            yield from _walk_tool_uses(item)


def _walk_string_values(node):
    """Yield every string value reachable from a JSON-like structure."""
    if isinstance(node, str):
        yield node
    elif isinstance(node, dict):
        for v in node.values():
            yield from _walk_string_values(v)
    elif isinstance(node, list):
        for item in node:
            yield from _walk_string_values(item)


def _input_references_skill(skill_input, target_skill: str) -> bool:
    """Return True iff a Skill tool_use input references exactly target_skill.

    The key holding the skill identifier may vary across Claude Code versions
    (`skill`, `name`, `command`, ...), so we accept a hit on any string value
    in the input. We require an *exact* match (after stripping whitespace) to
    avoid substring false positives — e.g. searching for `"test"` should not
    match `"test-review"`.
    """
    return any(value.strip() == target_skill for value in _walk_string_values(skill_input))


def detect_trigger(stream_text: str, target_skill: str) -> tuple[bool, list[dict]]:
    """Detect Skill(target_skill) activations in stream-json output.

    Strict: only counts tool_use blocks where name == "Skill" and the input
    references target_skill exactly (the key holding the skill identifier may
    vary across versions: skill, name, command — but the value must match
    target_skill exactly, not as a substring).
    """
    triggered = False
    matches: list[dict] = []
    for raw_line in stream_text.splitlines():
        stripped = raw_line.strip()
        if not stripped:
            continue
        try:
            event = json.loads(stripped)
        except json.JSONDecodeError:
            continue
        for tu in _walk_tool_uses(event):
            if tu.get("name") != "Skill":
                continue
            if _input_references_skill(tu.get("input", {}), target_skill):
                triggered = True
                matches.append({"name": tu.get("name"), "input": tu.get("input")})
    return triggered, matches


def run_one(prompt: str, budget: float, model: str | None) -> tuple[bool, str]:
    cmd = [
        "claude",
        "-p",
        prompt,
        "--output-format",
        "stream-json",
        "--verbose",
        "--max-budget-usd",
        str(budget),
        "--no-session-persistence",
        "--permission-mode",
        "bypassPermissions",
    ]
    if model:
        cmd += ["--model", model]
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=180)
    except subprocess.TimeoutExpired as exc:
        # Surface a per-run timeout as a failed run instead of crashing the
        # whole harness — keeps already-written results intact and lets
        # remaining cases continue.
        return False, _format_timeout_output(exc)
    return proc.returncode == 0, proc.stdout + "\n" + proc.stderr


def _format_timeout_output(exc: subprocess.TimeoutExpired) -> str:
    def _decode(buf: object) -> str:
        if isinstance(buf, bytes):
            return buf.decode("utf-8", errors="replace")
        if isinstance(buf, str):
            return buf
        return ""

    return f"{_decode(exc.stdout)}\n{_decode(exc.stderr)}\n[harness] subprocess.TimeoutExpired after 180s"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--cases", required=True, type=Path)
    ap.add_argument("--target-skill", required=True)
    ap.add_argument("--runs", type=int, default=3)
    ap.add_argument("--budget", type=float, default=0.05, help="USD cap per claude -p call")
    ap.add_argument("--model", default=None, help="Override model (e.g. haiku, sonnet)")
    ap.add_argument("--out", required=True, type=Path)
    ap.add_argument("--limit", type=int, default=None, help="Run only first N cases (smoke test)")
    args = ap.parse_args()

    data = json.loads(args.cases.read_text(encoding="utf-8"))
    cases = data["cases"]
    if args.limit:
        cases = cases[: args.limit]

    args.out.parent.mkdir(parents=True, exist_ok=True)
    with args.out.open("w", encoding="utf-8") as out_fp:
        for case in cases:
            cid = case["id"]
            prompt = case["prompt"]
            triggered_runs = 0
            run_details: list[dict] = []
            for run_idx in range(args.runs):
                print(f"  {cid} run {run_idx + 1}/{args.runs}: {prompt[:60]}...", file=sys.stderr)
                ok, output = run_one(prompt, args.budget, args.model)
                triggered, matches = detect_trigger(output, args.target_skill)
                run_details.append(
                    {
                        "run": run_idx,
                        "ok": ok,
                        "triggered": triggered,
                        "match_count": len(matches),
                    }
                )
                if triggered:
                    triggered_runs += 1
            rate = triggered_runs / args.runs if args.runs else 0.0
            predicted = rate >= TRIGGER_THRESHOLD
            record = {
                "id": cid,
                "predicted": predicted,
                "triggered_rate": rate,
                "runs": run_details,
                "reason": f"observed by claude -p ({triggered_runs}/{args.runs} runs triggered)",
            }
            out_fp.write(json.dumps(record, ensure_ascii=False) + "\n")
            out_fp.flush()
            print(f"  -> rate={rate:.2f} predicted={predicted}", file=sys.stderr)

    print(f"Wrote {args.out}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
