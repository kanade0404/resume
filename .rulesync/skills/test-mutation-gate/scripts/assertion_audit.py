#!/usr/bin/env python3
"""Static assertion audit for test-mutation-gate.

Reads a unified diff, splits added (+) lines into "test file" vs
"implementation file" buckets, and runs four regex-based checks:

1. tautology-literal-sharing (critical) - a literal that appears anywhere in
   an added test-file line (assertion or setup, e.g. `expected = "..."`)
   also appears in an implementation addition, suggesting the test was
   written by copying the (possibly buggy) implementation value rather than
   asserting an independently-derived expectation. Literals that only appear
   on an implementation line in exception/error, log/print, or comment
   context (e.g. `raise ValueError("...")`, `# ... "READY" ...`) are
   excluded from the comparison pool - asserting on an error message is
   legitimate state verification, and a comment isn't executable
   implementation logic, so neither is a copy-pasted tautology. Exclusions
   are always recorded in summary.notes.
2. assertion-roulette (warn)            - too many *messageless* assertions
   in one test function to tell which one failed. Assertions that already
   carry an explicit failure message (Python `assert expr, "msg"`, Go
   `t.Errorf`/`t.Fatalf` format strings, `assertEqual(a, b, "msg")` third
   arg) are excluded from the count.
3. overstated-coverage (warn)           - the test name claims a behavior
   (raises/returns/...) that the added test body doesn't actually check for.
4. boundary-gap (warn)                  - an added date/time/parse-like
   implementation function has no boundary-value evidence in the test
   file(s) related to it (scoped by file, not the whole diff's test
   additions pooled together).

stdlib only. Python 3.9+ compatible (no PEP 604/585 syntax, no typing
annotations relied upon at runtime).

Exit codes: PASS=0, BLOCK=1, input/parse error=2.
"""
import argparse
import collections
import json
import re
import sys
from pathlib import Path

# ---------------------------------------------------------------------------
# Regexes
# ---------------------------------------------------------------------------

# Which added lines count as "an assertion" across Python/JS/TS/Go.
# `assert[A-Z]\w*\(` covers unittest-style camelCase assertion methods
# (assertTrue, assertIn, assertIsNone, assertRaises, ...) beyond the single
# `assertEqual` name called out explicitly below; `\bassert\b` alone doesn't
# match them because "assert" is immediately followed by a word character
# (no boundary) in e.g. "assertTrue".
ASSERTION_RE = re.compile(
    r"\bassert\b|expect\s*\(|assert[A-Z]\w*\s*\(|toBe\(|toEqual\(|require\.\w+\(|assert\.\w+\("
    r"|t\.Errorf\(|t\.Fatalf\(",
    re.IGNORECASE,
)

# Test-function/test-case openers we can recognize well enough to scope
# assertions to a single test. Each pattern has exactly one capture group
# holding the test's "name" (a Python def name, a Go func name, or the
# string description passed to it()/test()).
TEST_FUNC_DEFS = (
    re.compile(r"^\s*def\s+(test_\w+)\s*\("),
    re.compile(r"^\s*async\s+def\s+(test_\w+)\s*\("),
    re.compile(r"^\s*(?:it|test)\s*\(\s*['\"](.+?)['\"]"),
    re.compile(r"^\s*(?:it|test)\.(?:only|skip|concurrent)\s*\(\s*['\"](.+?)['\"]"),
    re.compile(r"^\s*(?:it|test)\.each\(.*?\)\s*\(\s*['\"](.+?)['\"]"),
    re.compile(r"^\s*func\s+(Test\w+)\s*\("),
)

# `it.each`/`test.each` openers whose table spans multiple lines, e.g.:
#   test.each([
#     [1, 2, 3],
#   ])('adds %i + %i to equal %i', (a, b, expected) => { ... });
# TEST_FUNC_DEFS's single-line `.each(...)(...)` pattern can't see the title
# in this common Jest/Vitest shape because the array and the title aren't on
# the same added line. These two patterns bracket that shape: the opener
# marks "we're inside a pending parameter table", and the closer (matched
# once we're pending) extracts the title the same way a single-line match
# would.
MULTILINE_EACH_OPEN_RE = re.compile(r"^\s*(?:it|test)\.each\(\s*\[\s*$")
MULTILINE_EACH_CLOSE_RE = re.compile(r"^\s*\]\s*\)\s*\(\s*['\"](.+?)['\"]")

# Implementation-side function openers (Python/JS/Go + JS arrow-const form,
# plus their `export`/`async` variants). The arrow-const alternatives allow
# an optional `: ReturnType` annotation between the params and `=>` (e.g.
# `export const parseDate = (s: string): Date => ...`) - `[^=]+?` stops
# before the `=` in `=>` itself so it can't run past the arrow.
IMPL_FUNC_RE = re.compile(
    r"^\s*def\s+(\w+)\s*\("
    r"|^\s*async\s+def\s+(\w+)\s*\("
    r"|^\s*function\s+(\w+)\s*\("
    r"|^\s*func\s+(\w+)\s*\("
    r"|^\s*const\s+(\w+)\s*=\s*(?:\([^)]*\)(?:\s*:\s*[^=]+?)?|\w+)\s*=>"
    r"|^\s*export\s+const\s+(\w+)\s*=\s*(?:\([^)]*\)(?:\s*:\s*[^=]+?)?|\w+)\s*=>"
    r"|^\s*export\s+function\s+(\w+)\s*\("
    r"|^\s*export\s+async\s+function\s+(\w+)\s*\("
    r"|^\s*export\s+default\s+function\s+(\w+)?\s*\("
)

# Implementation-side lines whose literals are exception/error-message
# context (raise/throw/panic, or constructing an Error/Exception). A literal
# that only ever appears in such a line isn't a copy-pasted implementation
# value being locked into a test - it's the error message itself, and a test
# asserting on it is legitimate state verification.
EXCEPTION_CONTEXT_RE = re.compile(
    r"\braise\b|\bthrow\b|Error\s*\(|Exception\s*\(|panic\s*\(",
    re.IGNORECASE,
)

# Implementation-side lines whose literals are log/print output context.
# Same rationale as EXCEPTION_CONTEXT_RE: a log message literal reappearing
# in a test isn't a tautological copy of implementation logic.
LOG_CONTEXT_RE = re.compile(
    r"\blog\.|\blogger\.|\bconsole\.|\bprint\s*\(",
    re.IGNORECASE,
)

# Implementation-side lines that are pure comments/docstring decoration
# (Python/shell `#`, JS/TS/Go `//`, or inside a `/* ... */` block). A
# literal that only ever appears in a comment (e.g. `# The UI used to show
# "READY" here.`) isn't executable implementation logic being copy-pasted -
# comments often carry examples or stale/legacy values, so this would
# otherwise create false-positive criticals that users have to waive.
COMMENT_CONTEXT_RE = re.compile(r"^\s*(?:#|//|/\*|\*(?!/))")

# Assertion lines that already carry an explicit failure message, and so are
# excluded from the assertion-roulette messageless count: Python
# `assert expr, "msg"`, Go `t.Errorf(...)`/`t.Fatalf(...)` (whose first arg
# is inherently a format string), and `assertEqual(a, b, "msg")`'s 3rd arg.
PY_ASSERT_MSG_RE = re.compile(r"^\s*assert\s+.+,\s*(?:f|rb|br|r|b)?[\"'].*[\"']\s*$")
GO_FORMATTED_ASSERT_RE = re.compile(r"\bt\.(?:Errorf|Fatalf)\s*\(")
JS_ASSERT_EQUAL_MSG_RE = re.compile(
    r"assertEqual\s*\([^()]*,[^()]*,\s*[\"'][^\"']*[\"']\s*\)"
)

# Claim words we look for in a test's name/description.
CLAIM_WORD_RE = re.compile(
    r"returns|raises|rejects|throws|validates|callable|handles|errors|fails|empty|null|none",
    re.IGNORECASE,
)

# For each claim word, the pattern that must appear somewhere in the test's
# added body lines for the claim to be considered backed up. Words that
# aren't reliably checkable (e.g. "validates", "handles" - too vague to map
# to one code shape without generating false positives) are intentionally
# left out of this dict; overstated-coverage skips judgment for any claim
# word not present here, per spec ("辞書に無い主張語は判定しない").
CLAIM_PATTERNS = {
    "returns": re.compile(r"assert.*==|toBe\(|toEqual\("),
    "raises": re.compile(r"pytest\.raises|toThrow|assertRaises"),
    "throws": re.compile(r"pytest\.raises|toThrow|assertRaises"),
    "rejects": re.compile(r"pytest\.raises|toThrow|assertRaises|\.rejects"),
    "callable": re.compile(r"callable\(|typeof.*function"),
    "empty": re.compile(
        r"len\([^)]*\)\s*==\s*0|\.length\s*==\s*0|toHaveLength\(0\)|==\s*\[\]|==\s*(?:\"\"|'')"
    ),
    "null": re.compile(r"is None|toBeNull|==\s*null|===\s*null"),
    "none": re.compile(r"is None|toBeNull|==\s*null|===\s*null"),
    "errors": re.compile(r"pytest\.raises|toThrow|assertRaises|error"),
    "fails": re.compile(r"pytest\.raises|toThrow|assertRaises|fail"),
}

# Implementation function names that smell like they handle date/time or
# (de)serialization-ish data, where boundary values matter most.
BOUNDARY_NAME_RE = re.compile(
    r"date|time|parse|format|serialize|deserialize|convert|normalize|encode|decode",
    re.IGNORECASE,
)

# Evidence that a boundary value is exercised somewhere in the added test
# lines: empty string, a negative number, timezone-ish keywords, sub-second
# precision markers, parametrize/table-driven context, or - only when
# adjacent to a comparison operator (==/!=/is/</>/<=/>=) so a bare "0" or
# "None" appearing incidentally in unrelated code doesn't count - 0 or
# None/null/nil/undefined. "is not None" deliberately does NOT count: it
# tests the absence of the boundary state, not the boundary state itself.
BOUNDARY_EVIDENCE_RE = re.compile(
    r"\"\"|''"
    r"|(?<![\w.-])-\d+\b"
    r"|\b(?:==|!=|<=|>=|===|!==)\s*(?:0\b|None\b|null\b|nil\b|undefined\b)"
    r"|\b(?:0|None|null|nil|undefined)\b\s*(?:==|!=|<=|>=|===|!==)"
    r"|\bis\s+(?:0\b|None\b|null\b|nil\b|undefined\b)"
    r"|\b(?:0|None|null|nil|undefined)\b\s+is\b"
    r"|parametrize|\.each\("
    r"|timezone|UTC|offset|Z\""
    r"|\.999|millisecond|ミリ秒",
    re.IGNORECASE,
)

STRING_LITERAL_RE = re.compile(r'"([^"\\]{3,})"|\'([^\'\\]{3,})\'')
NUMERIC_LITERAL_RE = re.compile(r"(?<![\w.])-?\d+(?:\.\d+)?(?![\w.])")

# Numeric values excluded from literal-sharing comparisons: common indices,
# counts, and booleans-as-int that coincidentally show up in both test and
# implementation code without indicating a real copy-pasted tautology. This
# specific set (rather than "all small numbers") is called out by the gate
# spec itself, so we keep it as an explicit, named constant.
TRIVIAL_NUMERIC_LITERALS = {"0", "1", "-1", "2", "10", "100"}

CHECK_NAMES = (
    "tautology-literal-sharing",
    "assertion-roulette",
    "overstated-coverage",
    "boundary-gap",
)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def is_test_file(path):
    """Classify a diff path as a test file vs. an implementation file."""
    basename = path.rsplit("/", 1)[-1]
    if "_test." in basename:
        return True
    if ".test." in basename:
        return True
    if ".spec." in basename:
        return True
    if basename.startswith("test_"):
        return True
    if "/tests/" in path or path.startswith("tests/"):
        return True
    if "/__tests__/" in path or path.startswith("__tests__/"):
        return True
    return False


def try_match_test_func(line):
    for pattern in TEST_FUNC_DEFS:
        m = pattern.match(line)
        if m:
            return m.group(1)
    return None


def try_match_impl_func(line):
    m = IMPL_FUNC_RE.match(line)
    if not m:
        return None
    for group in m.groups():
        if group:
            return group
    return None


def _blank_string_spans(line):
    """Replace quoted-string contents (including the quotes) with spaces of
    the same length, so numeric-literal extraction never picks up digits
    that live *inside* a string literal as an independent numeric literal."""
    return STRING_LITERAL_RE.sub(lambda m: " " * len(m.group(0)), line)


def extract_literals(line):
    """Return the set of "interesting" literals (quoted strings length>=3,
    non-trivial numbers) found in a single line of code. Numeric extraction
    runs against a copy of `line` with string-literal spans blanked out, so
    a number embedded inside a string (e.g. "released-in-2024") isn't also
    recorded as the standalone numeric literal "2024" - two unrelated
    strings that merely share an embedded year/version/id shouldn't
    false-positive as a shared numeric literal."""
    literals = set()
    for m in STRING_LITERAL_RE.finditer(line):
        literal = m.group(1) if m.group(1) is not None else m.group(2)
        literals.add(literal)
    numeric_scan_line = _blank_string_spans(line)
    for m in NUMERIC_LITERAL_RE.finditer(numeric_scan_line):
        num = m.group(0)
        if num in TRIVIAL_NUMERIC_LITERALS:
            continue
        literals.add(num)
    return literals


def is_excluded_literal_context(line):
    """True if `line` is exception/error-message, log/print output, or
    comment context, in which case any literal on it is excluded from
    tautology-literal-sharing comparisons (see EXCEPTION_CONTEXT_RE /
    LOG_CONTEXT_RE / COMMENT_CONTEXT_RE docstrings)."""
    return bool(
        EXCEPTION_CONTEXT_RE.search(line)
        or LOG_CONTEXT_RE.search(line)
        or COMMENT_CONTEXT_RE.match(line)
    )


def assertion_has_message(line):
    """True if an assertion line already carries an explicit failure message
    and should therefore be excluded from the assertion-roulette messageless
    count (Python `assert expr, "msg"`, Go `t.Errorf`/`t.Fatalf` format
    strings, or `assertEqual(a, b, "msg")`'s 3rd argument)."""
    if GO_FORMATTED_ASSERT_RE.search(line):
        return True
    if JS_ASSERT_EQUAL_MSG_RE.search(line):
        return True
    if PY_ASSERT_MSG_RE.search(line):
        return True
    return False


def file_stem(path):
    """Return a path's basename without its final extension."""
    base = path.rsplit("/", 1)[-1]
    if "." in base:
        base = base.rsplit(".", 1)[0]
    return base


def test_related_stem(test_path):
    """Strip common test-file naming affixes so a test file's "subject" stem
    can be compared against an implementation file's stem, e.g.
    tests/test_format_utils.py -> "format_utils", src/format_utils.test.ts
    -> "format_utils". Used to scope boundary-gap evidence search to the
    test file(s) that actually relate to a given implementation file, rather
    than pooling every test file added in the diff together."""
    base = test_path.rsplit("/", 1)[-1]
    for suffix in (".test", ".spec"):
        idx = base.find(suffix)
        if idx != -1:
            base = base[:idx]
            break
    else:
        if "." in base:
            base = base.rsplit(".", 1)[0]
    if base.startswith("test_"):
        base = base[len("test_"):]
    if base.endswith("_test"):
        base = base[: -len("_test")]
    return base


def looks_like_unified_diff(text):
    """True if `text` contains at least one unified-diff structural marker
    (`+++ `, `--- `, or `diff --git `). Used to fail closed (exit 2) on raw
    file content passed in place of a diff, instead of silently returning a
    findings-free PASS - `parse_diff()` can't tell "an empty/no-op diff" from
    "not a diff at all" on its own, since both produce an empty `files` dict."""
    for line in text.splitlines():
        if (
            line.startswith("+++ ")
            or line.startswith("--- ")
            or line.startswith("diff --git ")
        ):
            return True
    return False


# ---------------------------------------------------------------------------
# Diff parsing
# ---------------------------------------------------------------------------

def parse_diff(text):
    """Parse a unified diff into per-file added-line data.

    Returns an OrderedDict: path -> {
        "is_test": bool,
        "added_lines": [line, ...],                       # in diff order
        "funcs": OrderedDict(name -> {"all_lines": [...], "assert_lines": [...]}),
        "literal_scan_records": [(line, func_name_or_None), ...],
    }

    `literal_scan_records` holds every added line in a test file (not just
    ones that match ASSERTION_RE) so tautology-literal-sharing can catch a
    literal introduced in test *setup* (e.g. `expected = "buggy-value"`
    followed by `assert actual == expected`), not only literals that appear
    directly inside an assertion line.
    """
    files = collections.OrderedDict()
    current_path = None
    current_func_name = None
    pending_each = False

    def start_func(name, info):
        if name not in info["funcs"]:
            info["funcs"][name] = {"all_lines": [], "assert_lines": []}

    for raw_line in text.splitlines():
        if raw_line.startswith("+++ "):
            path = raw_line[4:].strip()
            if path.startswith("b/"):
                path = path[2:]
            if path in ("/dev/null", ""):
                current_path = None
                current_func_name = None
                pending_each = False
                continue
            current_path = path
            current_func_name = None
            pending_each = False
            if current_path not in files:
                files[current_path] = {
                    "is_test": is_test_file(current_path),
                    "added_lines": [],
                    "funcs": collections.OrderedDict(),
                    "literal_scan_records": [],
                }
            continue

        if (
            raw_line.startswith("--- ")
            or raw_line.startswith("diff --git")
            or raw_line.startswith("index ")
            or raw_line.startswith("@@")
        ):
            continue

        if current_path is None:
            continue

        info = files[current_path]

        if raw_line.startswith("+"):
            content = raw_line[1:]
            info["added_lines"].append(content)

            if info["is_test"]:
                if pending_each:
                    m = MULTILINE_EACH_CLOSE_RE.match(content)
                    if m:
                        current_func_name = m.group(1)
                        start_func(current_func_name, info)
                        pending_each = False
                elif MULTILINE_EACH_OPEN_RE.match(content):
                    pending_each = True
                    # Clear scope immediately: rows inside the pending
                    # table (and any line if the table never closes within
                    # this diff) must not keep being attributed to whatever
                    # test preceded this opener. MULTILINE_EACH_CLOSE_RE
                    # re-establishes the real scope once the title is seen.
                    current_func_name = None
                else:
                    matched_func = try_match_test_func(content)
                    if matched_func is not None:
                        current_func_name = matched_func
                        start_func(current_func_name, info)

                if current_func_name is not None:
                    info["funcs"][current_func_name]["all_lines"].append(content)
                    if ASSERTION_RE.search(content):
                        info["funcs"][current_func_name]["assert_lines"].append(content)
                info["literal_scan_records"].append((content, current_func_name))
            continue

        if raw_line.startswith(" ") and info["is_test"] and not pending_each:
            # Context line: never an added line, so it never contributes to
            # literal-sharing / assertion-roulette / overstated-coverage
            # bodies. But when it's the (unmodified) `def test_foo(...):`
            # line enclosing an edit deeper in the function - the common
            # shape when only an existing test's assertions are rewritten -
            # it's still needed to scope subsequently ADDED lines to the
            # right function. Without this, editing assertions inside an
            # existing test (without also touching the def line itself)
            # leaves current_func_name at None/stale and silently drops
            # those added assertions from assertion-roulette /
            # overstated-coverage (tautology-literal-sharing is unaffected -
            # it doesn't require func scoping).
            content = raw_line[1:]
            matched_func = try_match_test_func(content)
            if matched_func is not None:
                current_func_name = matched_func
                start_func(current_func_name, info)
            continue

        # Removed ("-") lines don't affect added-line collection; diff
        # metadata lines are already handled above.
        continue

    return files


# ---------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------

def check_tautology_literal_sharing(files, findings, notes):
    impl_lines = []
    for path, info in files.items():
        if not info["is_test"]:
            for line in info["added_lines"]:
                impl_lines.append((path, line))

    if not impl_lines:
        notes.append(
            "no implementation-file added lines present in diff; "
            "tautology-literal-sharing check skipped (cannot judge a test-only diff)"
        )
        return

    # literal -> [(path, line, is_excluded_context), ...] across every impl
    # addition where it appears.
    impl_literal_sources = collections.defaultdict(list)
    for path, line in impl_lines:
        excluded_ctx = is_excluded_literal_context(line)
        for literal in extract_literals(line):
            impl_literal_sources[literal].append((path, line, excluded_ctx))

    # A literal is a real tautology candidate only if it appears on at least
    # one impl line that ISN'T exception/log-message/comment context. A
    # literal that appears exclusively inside raise/throw/Error(/log/print/
    # comment lines is a legitimate error-message/log-message value being
    # verified (or just comment prose), not a copy-pasted implementation
    # value - exclude it from the comparison pool (but always record the
    # exclusion in notes; never a silent skip).
    impl_literals = {}
    excluded_only_literals = set()
    for literal, sources in impl_literal_sources.items():
        usable = [(p, l) for (p, l, ctx) in sources if not ctx]
        if usable:
            impl_literals[literal] = usable[0]
        else:
            excluded_only_literals.add(literal)

    seen = set()
    excluded_shared = set()
    for path, info in files.items():
        if not info["is_test"]:
            continue
        for line, func_name in info["literal_scan_records"]:
            for literal in extract_literals(line):
                if literal in excluded_only_literals:
                    excluded_shared.add(literal)
                    continue
                if literal not in impl_literals:
                    continue
                impl_path, impl_line = impl_literals[literal]
                dedup_key = (path, impl_path, literal)
                if dedup_key in seen:
                    continue
                seen.add(dedup_key)
                findings.append(
                    {
                        "check": "tautology-literal-sharing",
                        "severity": "critical",
                        "file": path,
                        "test_name": func_name,
                        "message": (
                            "literal {!r} appears in both a test addition in {} and an "
                            "implementation addition in {} - the test may be locking in a "
                            "copy-pasted value instead of independently verifying behavior"
                        ).format(literal, path, impl_path),
                        "evidence": {
                            "literal": literal,
                            "test_line": line.strip(),
                            "impl_line": impl_line.strip(),
                        },
                    }
                )

    if excluded_shared:
        notes.append(
            "excluded {} shared literal(s) in exception/log/comment context".format(
                len(excluded_shared)
            )
        )


def check_assertion_roulette(files, findings, max_asserts):
    for path, info in files.items():
        if not info["is_test"]:
            continue
        for func_name, data in info["funcs"].items():
            messageless = [
                line for line in data["assert_lines"] if not assertion_has_message(line)
            ]
            count = len(messageless)
            if count > max_asserts:
                findings.append(
                    {
                        "check": "assertion-roulette",
                        "severity": "warn",
                        "file": path,
                        "test_name": func_name,
                        "message": (
                            "test function has {} assertions without a failure message "
                            "(> threshold {}); a failure here won't identify which "
                            "expectation broke"
                        ).format(count, max_asserts),
                        "evidence": {
                            "assert_count": count,
                            "threshold": max_asserts,
                            "total_assert_lines": len(data["assert_lines"]),
                        },
                    }
                )


def check_overstated_coverage(files, findings):
    for path, info in files.items():
        if not info["is_test"]:
            continue
        for func_name, data in info["funcs"].items():
            matched_words = {w.lower() for w in CLAIM_WORD_RE.findall(func_name)}
            body_text = "\n".join(data["all_lines"])
            for word in sorted(matched_words):
                pattern = CLAIM_PATTERNS.get(word)
                if pattern is None:
                    # Unmapped claim word: skip judgment to avoid false positives.
                    continue
                if not pattern.search(body_text):
                    findings.append(
                        {
                            "check": "overstated-coverage",
                            "severity": "warn",
                            "file": path,
                            "test_name": func_name,
                            "message": (
                                "test name claims '{}' but no matching assertion pattern "
                                "was found in the added test body"
                            ).format(word),
                            "evidence": {"claim_word": word},
                        }
                    )


def check_boundary_gap(files, findings):
    boundary_funcs = []
    for path, info in files.items():
        if info["is_test"]:
            continue
        for line in info["added_lines"]:
            name = try_match_impl_func(line)
            if name and BOUNDARY_NAME_RE.search(name):
                boundary_funcs.append((path, name))

    if not boundary_funcs:
        return

    # Evidence lines are kept per test file (not flattened into one pool)
    # so each boundary function can be checked against the test file(s) that
    # actually relate to it by name, instead of "any test file anywhere in
    # the diff" - an unrelated test file's boilerplate assertions shouldn't
    # be able to silence a boundary-gap warning for a function it never
    # exercises.
    test_lines_by_file = collections.OrderedDict()
    for path, info in files.items():
        if info["is_test"]:
            test_lines_by_file[path] = info["added_lines"]

    seen = set()
    for impl_path, func_name in boundary_funcs:
        key = (impl_path, func_name)
        if key in seen:
            continue
        seen.add(key)

        impl_stem = file_stem(impl_path).lower()
        related_files = [
            p
            for p in test_lines_by_file
            if impl_stem and test_related_stem(p).lower() == impl_stem
        ]
        # If no test file's name can be matched to this implementation
        # file's stem, fall back to every test file added in the diff -
        # still scoped per file internally, just without a name-based
        # restriction (best-effort degrade, not a silent skip).
        scoped_files = related_files or list(test_lines_by_file.keys())

        evidence_found = any(
            BOUNDARY_EVIDENCE_RE.search(line)
            for p in scoped_files
            for line in test_lines_by_file[p]
        )
        if evidence_found:
            continue

        findings.append(
            {
                "check": "boundary-gap",
                "severity": "warn",
                "file": impl_path,
                "test_name": None,
                "message": (
                    "function '{}' in {} looks like it handles date/time/parsing data but "
                    "no boundary-value evidence (empty/negative/None/timezone/etc.) was "
                    "found in the diff's test additions"
                ).format(func_name, impl_path),
                "evidence": None,
            }
        )


# ---------------------------------------------------------------------------
# Top-level analysis
# ---------------------------------------------------------------------------

def analyze(text, max_asserts):
    files = parse_diff(text)
    findings = []
    notes = []

    check_tautology_literal_sharing(files, findings, notes)
    check_assertion_roulette(files, findings, max_asserts)
    check_overstated_coverage(files, findings)
    check_boundary_gap(files, findings)

    critical_count = sum(1 for f in findings if f["severity"] == "critical")
    warn_count = sum(1 for f in findings if f["severity"] == "warn")

    by_check = collections.OrderedDict()
    for name in CHECK_NAMES:
        by_check[name] = sum(1 for f in findings if f["check"] == name)

    verdict = "BLOCK" if critical_count >= 1 else "PASS"

    return {
        "version": 1,
        "verdict": verdict,
        "findings": findings,
        "summary": {
            "critical": critical_count,
            "warn": warn_count,
            "by_check": by_check,
            "notes": notes,
        },
    }


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Static assertion audit for test-mutation-gate"
    )
    parser.add_argument(
        "--diff-file",
        default="-",
        help="path to a unified diff, or - to read from stdin (default: -)",
    )
    parser.add_argument(
        "--max-asserts",
        type=int,
        default=2,  # spec-mandated default threshold for assertion-roulette
        help="warn threshold for assertions per test function (default: 2)",
    )
    args = parser.parse_args(argv)

    try:
        if args.diff_file == "-":
            text = sys.stdin.read()
        else:
            text = Path(args.diff_file).read_text(encoding="utf-8", errors="replace")
    except OSError as exc:
        print("assertion_audit: failed to read diff file: {}".format(exc), file=sys.stderr)
        return 2

    if text.strip() and not looks_like_unified_diff(text):
        print(
            "assertion_audit: input does not look like a unified diff (no +++/---/"
            "diff --git markers found); refusing to silently PASS on what may be raw "
            "file content. Convert untracked files to a unified diff first, e.g. "
            "`git diff --no-index /dev/null <file>`.",
            file=sys.stderr,
        )
        return 2

    try:
        result = analyze(text, args.max_asserts)
    except Exception as exc:  # noqa: BLE001 - defensive: never leak a bare traceback
        print("assertion_audit: failed to analyze diff: {}".format(exc), file=sys.stderr)
        return 2

    print(json.dumps(result, ensure_ascii=False))
    return 0 if result["verdict"] == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
