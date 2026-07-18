#!/usr/bin/env python3
"""Mutation smoke for test-mutation-gate (Phase 2).

Injects a small, bounded number of "safe" textual mutations into a single
implementation file, re-runs a caller-supplied test command once per
mutation, and reports whether the test suite actually goes RED (mutation
caught) or stays GREEN (mutant survived -> the test suite has a detection
gap around that line).

This is a *smoke* check, not a full mutation-testing tool (Stryker/mutmut
equivalents run every operator against every AST node and compute a
whole-suite mutation score; this script is intentionally line/regex based
and only touches the one impl file passed on the CLI - see
references/mutation-recipes.md for the language coverage and the
seams this approach cannot mutate).

Mutation kinds (regex-based, stdlib only):
  (a) bool-flip        True<->False / true<->false
  (b) comparison-flip  ==<->!=, <->=  , >->=  , <=->< , >=->>
  (c) off-by-one       an integer literal immediately adjacent to a
                        comparison operator, N -> N+1

Safety:
  - The impl file is always restored from a tempfile backup, via try/finally
    AND a SIGTERM/SIGINT/SIGHUP handler (SIGTERM's default disposition does
    not raise a catchable Python exception, so try/finally alone is not
    enough to survive it).
  - Exactly one mutation is on disk at a time; the file is restored to the
    pristine backup before the next mutation is applied and again before
    this process exits.
  - After the last restore, the impl file's bytes are compared against the
    backup; a mismatch is a hard error (exit 2), never a silent partial
    mutation left behind.
  - Before scoring any mutant, --test-cmd is run once against the pristine
    (unmutated) impl file; a non-zero baseline aborts with exit 2 instead of
    silently reporting every mutation as "caught" against a suite that was
    never green in the first place.
  - --test-cmd runs in its own process group (start_new_session=True); a
    timeout kills the whole group, not just the shell's own PID, so a
    command that forks/backgrounds a child before hanging doesn't leave
    that child running past the timeout.

Known limitation (documented in notes, always): string/comment detection is
line-based and regex-driven, not a real tokenizer/AST. Multi-line
constructs - Python triple-quoted strings, C-style block comments spanning
several lines - are NOT masked and could theoretically be mutated inside.
See references/mutation-recipes.md for the fallback (extract a pure
function so the seam becomes single-line/testable) and
references/waiver-fallback.md for when mutation truly cannot apply.

Exit codes: PASS=0, BLOCK=1, SKIP=0, error=2.
"""
import argparse
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile
from pathlib import Path

# ---------------------------------------------------------------------------
# Regexes
# ---------------------------------------------------------------------------

BOOL_RE = re.compile(r"\b(True|False|true|false)\b")
BOOL_FLIP = {"True": "False", "False": "True", "true": "false", "false": "true"}

# Longest-alternative-first so "==", "!=", "<=", ">=" are consumed before the
# single-char "<"/">" alternatives are tried at the same position. The
# lookarounds on the single-char forms avoid mutating Go's "<-" channel
# operator, "->" return-type arrows, and "=>" arrow functions (TS/JS) - a
# known regex-vs-AST gap, not a full fix (see references/mutation-recipes.md).
COMPARISON_RE = re.compile(r"==|!=|<=|>=|<(?!-)|(?<![=-])>")
COMPARISON_FLIP = {"==": "!=", "!=": "==", "<=": "<", ">=": ">", "<": "<=", ">": ">="}

INT_RIGHT_RE = re.compile(r"\s*(-?\d+)")
INT_LEFT_RE = re.compile(r"(-?\d+)\s*$")

# Narrow heuristic for TS/TSX type-alias declarations, e.g.
# `type Flag = true | false;` or `export type X = { a: true } | { a: false }`.
# Only used to guard bool-flip (see discover_candidates' skip_type_alias_bools
# docstring for why this doesn't attempt to cover interface/parameter type
# positions too).
TS_TYPE_ALIAS_LINE_RE = re.compile(r"^\s*(export\s+)?(declare\s+)?type\s+\w+\b[^=]*=")

# Generic, cross-language markers that a non-zero exit was a syntax/parse
# failure caused by the mutation breaking the file, rather than a real
# assertion catching the behavioral change. Still counted as "caught" (the
# gate cares about non-zero vs. zero), but called out separately in notes
# per the spec ("ビルドエラーは caught と区別され notes に記録").
SYNTAX_ERROR_MARKERS_RE = re.compile(
    r"SyntaxError|IndentationError|TabError|unexpected token|parse error|"
    r"syntax error|cannot find symbol|expected expression",
    re.IGNORECASE,
)


# ---------------------------------------------------------------------------
# Line masking (string/comment detection, single-line only - see module
# docstring "Known limitation")
# ---------------------------------------------------------------------------

BLOCK_COMMENT_EXTS = (".js", ".jsx", ".ts", ".tsx", ".go", ".java", ".c", ".cc", ".cpp", ".rs")


def comment_prefixes_for(path):
    """Return the comment-start token(s) to treat as "rest of line is a
    comment" for this file's extension. Unknown extensions get both '#' and
    '//' as a conservative superset (masks more, never mutates less safely)."""
    ext = Path(path).suffix.lower()
    if ext in (".py", ".rb", ".sh", ".bash", ".yml", ".yaml"):
        return ("#",)
    if ext in BLOCK_COMMENT_EXTS:
        return ("//",)
    return ("#", "//")


def block_comment_markers_for(path):
    """Return the (start, end) marker pair for C-style block comments
    (`/* ... */`) for this file's extension, or None if the language has no
    such construct (Python/Ruby/shell/YAML use only line comments).
    Unknown extensions get the markers too, matching the conservative
    "masks more, never mutates less safely" policy of comment_prefixes_for."""
    ext = Path(path).suffix.lower()
    if ext in (".py", ".rb", ".sh", ".bash", ".yml", ".yaml"):
        return None
    return ("/*", "*/")


def mask_line(line, comment_prefixes, block_comment=None):
    """Return a same-length copy of `line` where string-literal interiors
    become 'x' and comment text becomes '#', so mutation regexes never match
    inside a string or comment. Quote/comment delimiters and all other
    characters keep their original position and value, so match spans found
    on the masked line can be applied directly to the original line.

    `block_comment`, if given, is a (start, end) marker pair (e.g.
    `("/*", "*/")`) for C-style block comments. A block comment that opens
    and closes on this same line is masked in place, without ending the
    scan, so code following `*/` on the same line is still scanned. One
    that opens but never closes on this line is treated the same as a line
    comment (rest of line masked) - the conservative, single-line-only
    behavior documented below.

    Single-line only: a string or comment that started on a previous line
    (Python triple-quoted strings, C-style /* */ spanning lines) is NOT
    tracked across lines - this is the documented regex-vs-AST limitation.
    """
    chars = list(line)
    n = len(chars)
    in_string = False
    quote_char = None
    i = 0
    while i < n:
        ch = chars[i]
        if in_string:
            if ch == "\\" and i + 1 < n:
                chars[i] = "x"
                chars[i + 1] = "x"
                i += 2
                continue
            if ch == quote_char:
                in_string = False
            else:
                chars[i] = "x"
            i += 1
            continue
        if block_comment is not None:
            start_marker, end_marker = block_comment
            if line[i:i + len(start_marker)] == start_marker:
                end_idx = line.find(end_marker, i + len(start_marker))
                if end_idx != -1:
                    span_end = end_idx + len(end_marker)
                    for j in range(i, span_end):
                        chars[j] = "#"
                    i = span_end
                    continue
                for j in range(i, n):
                    chars[j] = "#"
                break
        if any(line[i:i + len(p)] == p for p in comment_prefixes):
            for j in range(i, n):
                chars[j] = "#"
            break
        if ch in ("'", '"', "`"):
            in_string = True
            quote_char = ch
            i += 1
            continue
        i += 1
    return "".join(chars)


# ---------------------------------------------------------------------------
# Candidate discovery
# ---------------------------------------------------------------------------

def find_adjacent_int(masked_line, op_start, op_end):
    """Look for an integer literal immediately adjacent (modulo whitespace)
    to a comparison operator at masked_line[op_start:op_end]. Right side is
    preferred; falls back to the left side. Returns (start, end, digits) or
    None. Works off the masked line so a digit-looking substring inside a
    string literal never becomes a candidate."""
    m = INT_RIGHT_RE.match(masked_line, op_end)
    if m:
        return m.start(1), m.end(1), m.group(1)
    m = INT_LEFT_RE.search(masked_line[:op_start])
    if m:
        return m.start(1), m.end(1), m.group(1)
    return None


def discover_candidates(lines, comment_prefixes, block_comment=None, skip_type_alias_bools=False):
    """Scan every added-nothing (this is a whole-file scan, not a diff) line
    of `lines` (as returned by readlines(), terminators included) and return
    an ordered, deduplicated list of mutation candidate dicts:
    {"line": 1-based int, "kind": ..., "col": 0-based int, "before": ..., "after": ...}

    `skip_type_alias_bools`, when True (TS/TSX files only - see call site),
    skips bool-flip candidates on lines that are TypeScript type-alias
    declarations (`type Flag = true | false;`). Bool literals there are
    compile-time type positions, not runtime values: mutating them either
    produces a harmless type-level no-op (survived mutant, false BLOCK) or,
    if the test command also typechecks, a compiler error indistinguishable
    from a real assertion catching a behavioral change. This is a narrow,
    line-level heuristic (see references/mutation-recipes.md) - it does not
    attempt to distinguish object/interface field type positions from
    runtime literals, since that would risk suppressing real runtime bool
    literals (e.g. `{ enabled: true }`) which are far more common.
    """
    candidates = []
    seen = set()
    for lineno, raw in enumerate(lines, start=1):
        line = raw.rstrip("\r\n")
        masked = mask_line(line, comment_prefixes, block_comment)

        skip_bools = skip_type_alias_bools and TS_TYPE_ALIAS_LINE_RE.match(line)
        for m in BOOL_RE.finditer(masked):
            if skip_bools:
                continue
            key = (lineno, "bool-flip", m.start())
            if key in seen:
                continue
            seen.add(key)
            old = m.group(1)
            candidates.append(
                {
                    "line": lineno,
                    "kind": "bool-flip",
                    "col": m.start(),
                    "before": old,
                    "after": BOOL_FLIP[old],
                }
            )

        for m in COMPARISON_RE.finditer(masked):
            old_op = m.group(0)
            key = (lineno, "comparison-flip", m.start())
            if key not in seen:
                seen.add(key)
                candidates.append(
                    {
                        "line": lineno,
                        "kind": "comparison-flip",
                        "col": m.start(),
                        "before": old_op,
                        "after": COMPARISON_FLIP[old_op],
                    }
                )

            adjacent = find_adjacent_int(masked, m.start(), m.end())
            if adjacent:
                val_start, val_end, digits = adjacent
                key2 = (lineno, "off-by-one", val_start)
                if key2 not in seen:
                    seen.add(key2)
                    candidates.append(
                        {
                            "line": lineno,
                            "kind": "off-by-one",
                            "col": val_start,
                            "before": digits,
                            "after": str(int(digits) + 1),
                        }
                    )

    return candidates


# ---------------------------------------------------------------------------
# Mutation application
# ---------------------------------------------------------------------------

def split_line_ending(raw):
    if raw.endswith("\r\n"):
        return raw[:-2], "\r\n"
    if raw.endswith("\n"):
        return raw[:-1], "\n"
    if raw.endswith("\r"):
        return raw[:-1], "\r"
    return raw, ""


def apply_candidate(original_lines, candidate):
    """Return a new list of lines with exactly one candidate mutation
    applied to the pristine `original_lines` (never accumulates mutations)."""
    idx = candidate["line"] - 1
    body, ending = split_line_ending(original_lines[idx])
    col = candidate["col"]
    before = candidate["before"]
    after = candidate["after"]
    actual = body[col:col + len(before)]
    if actual != before:
        raise RuntimeError(
            "mutation position mismatch at line {}: expected {!r}, found {!r} "
            "(file changed between discovery and application?)".format(
                candidate["line"], before, actual
            )
        )
    new_body = body[:col] + after + body[col + len(before):]
    mutated = list(original_lines)
    mutated[idx] = new_body + ending
    return mutated


# ---------------------------------------------------------------------------
# Backup / restore
# ---------------------------------------------------------------------------

class Backup:
    def __init__(self, impl_path):
        self.impl_path = Path(impl_path)
        fd, self.backup_path = tempfile.mkstemp(prefix="mutate_and_run-", suffix=".bak")
        with os.fdopen(fd, "wb") as f:
            f.write(self.impl_path.read_bytes())

    def restore(self):
        shutil.copyfile(self.backup_path, self.impl_path)

    def matches_current(self):
        return self.impl_path.read_bytes() == Path(self.backup_path).read_bytes()

    def cleanup(self):
        try:
            Path(self.backup_path).unlink()
        except OSError:
            pass


def install_signal_restorer(backup):
    """Install handlers so SIGTERM/SIGINT/SIGHUP restore the impl file before
    the process dies. SIGINT already raises KeyboardInterrupt (caught by the
    surrounding try/finally), but SIGTERM's default disposition terminates
    the process immediately without running Python cleanup code, so it needs
    an explicit handler."""

    def _handler(signum, _frame):
        try:
            backup.restore()
        finally:
            sys.exit(128 + signum)

    for name in ("SIGTERM", "SIGINT", "SIGHUP"):
        sig = getattr(signal, name, None)
        if sig is None:
            continue
        try:
            signal.signal(sig, _handler)
        except (ValueError, OSError):
            pass  # e.g. not the main thread - best-effort only


# ---------------------------------------------------------------------------
# Test execution
# ---------------------------------------------------------------------------

def _kill_process_group(proc):
    """Best-effort: terminate the whole process group `proc`'s shell was
    started in (not just the shell's own PID). If test_cmd forks/backgrounds
    a child before its own foreground command hangs, killing only the shell
    leaves that child running past the timeout - corrupting later mutation
    results (stale process still touching files/ports) and leaking
    processes. Falls back to proc.kill() on platforms without process
    groups (e.g. Windows) or if the group is already gone."""
    killpg = getattr(os, "killpg", None)
    if killpg is None:
        proc.kill()
        return
    try:
        killpg(os.getpgid(proc.pid), signal.SIGKILL)
    except (ProcessLookupError, PermissionError, OSError):
        proc.kill()


def run_test_cmd(test_cmd, timeout_sec):
    """Run test_cmd via the shell, in its own process group. Returns
    (returncode, stderr_text). A timeout is treated as a caught mutation
    (the run did not cleanly finish GREEN) with a synthetic returncode of
    124 (matches the common `timeout(1)` convention) and is called out in
    notes by the caller.

    `start_new_session=True` puts the shell (and anything it forks) in a
    fresh process group so a timeout can kill the whole tree via
    _kill_process_group instead of just the shell's own PID."""
    proc = subprocess.Popen(
        test_cmd,
        shell=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        start_new_session=True,
    )
    try:
        _, stderr = proc.communicate(timeout=timeout_sec)
        return proc.returncode, stderr.decode("utf-8", errors="replace")
    except subprocess.TimeoutExpired:
        pass

    _kill_process_group(proc)
    try:
        _, stderr = proc.communicate(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
        _, stderr = proc.communicate()
    return 124, stderr.decode("utf-8", errors="replace") if isinstance(stderr, bytes) else ""


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main(argv=None):
    parser = argparse.ArgumentParser(description="Mutation smoke for test-mutation-gate")
    parser.add_argument("--impl-file", required=True, help="implementation file to mutate")
    parser.add_argument("--test-cmd", required=True, help="shell command that runs the test(s)")
    parser.add_argument("--max-mutations", type=int, default=3, help="max mutations to try (default: 3)")
    parser.add_argument("--timeout-sec", type=int, default=120, help="per-mutation test-cmd timeout (default: 120)")
    args = parser.parse_args(argv)

    impl_path = Path(args.impl_file)
    if not impl_path.is_file():
        print(
            "mutate_and_run: impl file not found: {}".format(args.impl_file),
            file=sys.stderr,
        )
        return 2

    notes = [
        "string/comment detection is line-based (regex), not a tokenizer or AST; "
        "multi-line strings (e.g. Python triple-quoted docstrings) and block "
        "comments spanning multiple lines are not masked and could theoretically "
        "be mutated inside - see references/mutation-recipes.md for the fallback."
    ]

    try:
        backup = Backup(impl_path)
    except OSError as exc:
        print("mutate_and_run: failed to back up impl file: {}".format(exc), file=sys.stderr)
        return 2

    install_signal_restorer(backup)

    try:
        with open(impl_path, "r", encoding="utf-8", newline="") as f:
            original_lines = f.readlines()

        comment_prefixes = comment_prefixes_for(impl_path)
        block_comment = block_comment_markers_for(impl_path)
        skip_type_alias_bools = impl_path.suffix.lower() in (".ts", ".tsx")
        all_candidates = discover_candidates(
            original_lines, comment_prefixes, block_comment, skip_type_alias_bools
        )
        selected = all_candidates[: args.max_mutations]

        if not selected:
            notes.append(
                "no mutation candidates found (no bool literal, comparison operator, "
                "or comparison-adjacent integer literal outside strings/comments) - "
                "treat this as a signal to consider a waiver "
                "(references/waiver-fallback.md) if this file is a seam that should "
                "have mutable logic."
            )
            result = {
                "version": 1,
                "verdict": "SKIP",
                "mutations_total": 0,
                "caught": 0,
                "survived": [],
                "notes": notes,
            }
            print(json.dumps(result, ensure_ascii=False))
            return 0

        baseline_rc, baseline_stderr = run_test_cmd(args.test_cmd, args.timeout_sec)
        if baseline_rc != 0:
            print(
                "mutate_and_run: baseline --test-cmd failed against the "
                "*unmutated* impl file (exit {}) - refusing to score mutants "
                "against a suite that was never green (every mutation would "
                "trivially count as 'caught' and the gate would report a "
                "false PASS). Fix --test-cmd or the suite itself first. "
                "stderr: {}".format(baseline_rc, baseline_stderr.strip()[:2000]),
                file=sys.stderr,
            )
            return 2

        survived = []
        caught = 0
        for candidate in selected:
            try:
                mutated_lines = apply_candidate(original_lines, candidate)
                with open(impl_path, "w", encoding="utf-8", newline="") as f:
                    f.writelines(mutated_lines)

                returncode, stderr_text = run_test_cmd(args.test_cmd, args.timeout_sec)
            finally:
                backup.restore()

            if returncode == 0:
                survived.append(
                    {
                        "line": candidate["line"],
                        "kind": candidate["kind"],
                        "before": candidate["before"],
                        "after": candidate["after"],
                    }
                )
            else:
                caught += 1
                if returncode == 124:
                    notes.append(
                        "line {} ({}): test-cmd timed out after {}s - counted as "
                        "caught, but this may indicate the mutation caused a hang "
                        "rather than a real test failure".format(
                            candidate["line"], candidate["kind"], args.timeout_sec
                        )
                    )
                elif SYNTAX_ERROR_MARKERS_RE.search(stderr_text):
                    notes.append(
                        "line {} ({}): non-zero exit looks like a syntax/build error "
                        "(not a real assertion failure) - counted as caught, but the "
                        "regex-based mutation may have produced invalid code rather "
                        "than a legitimately mutated behavior".format(
                            candidate["line"], candidate["kind"]
                        )
                    )

        verdict = "BLOCK" if survived else "PASS"
        result = {
            "version": 1,
            "verdict": verdict,
            "mutations_total": len(selected),
            "caught": caught,
            "survived": survived,
            "notes": notes,
        }
        print(json.dumps(result, ensure_ascii=False))
        return 1 if verdict == "BLOCK" else 0

    except Exception as exc:  # noqa: BLE001 - never leak a bare traceback; always restore first
        try:
            backup.restore()
        except OSError:
            pass
        print("mutate_and_run: unexpected error: {}".format(exc), file=sys.stderr)
        return 2

    finally:
        try:
            backup.restore()
        except OSError as exc:
            print(
                "mutate_and_run: FAILED to restore impl file from backup: {}".format(exc),
                file=sys.stderr,
            )
            sys.exit(2)
        if not backup.matches_current():
            print(
                "mutate_and_run: impl file does not match backup after restore - "
                "refusing to exit cleanly, manual recovery needed. backup kept at: "
                "{}".format(backup.backup_path),
                file=sys.stderr,
            )
            sys.exit(2)
        backup.cleanup()


if __name__ == "__main__":
    sys.exit(main())
