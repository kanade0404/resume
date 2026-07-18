# Mutation Recipes

`scripts/mutate_and_run.py` injects a small, bounded set of **safe, regex-based**
mutations — not a full Stryker/mutmut-style AST mutation matrix. This file
lists what each language's mutations look like, what must never be mutated,
and the fallback when a seam simply can't be mutated this way.

## Safe mutation patterns by language

All three kinds below apply the same way across Python / TypeScript /
JavaScript / Go; only the literal spellings differ.

| kind | Python | TS/JS | Go |
|---|---|---|---|
| bool-flip | `True`↔`False` | `true`↔`false` | `true`↔`false` |
| comparison-flip | `==`↔`!=`, `<`→`<=`, `>`→`>=`, `<=`→`<`, `>=`→`>` | same | same |
| off-by-one | integer literal `N` adjacent to a comparison → `N+1` | same | same |

Examples:

- Python: `if total >= 1000:` → `if total > 1000:` (comparison-flip) or
  `if total >= 1001:` (off-by-one).
- TS: `if (retries === 3)` → `if (retries !== 3)`.
- Go: `if n <= max {` → `if n < max {`.

A mutant that **survives** (test suite stays GREEN) means the test doesn't
actually exercise that branch/boundary — the point of the smoke check.

## What must never be mutated

- **String literal contents** — `"total >= 1000"` inside a log message or
  docstring is text, not logic. The script masks quoted spans (single/double/
  backtick) on each line before searching for mutation targets.
- **Comments** — `# if total >= 1000` (Python) or `// if (a === b)` (TS/JS/Go)
  is documentation, not code. Masked the same way as strings.
- **Log / error messages** — a literal that only appears inside a
  `raise`/`throw`/`panic`/`log.*`/`console.*` call is a message, not a value
  under test; mutating it would produce noise, not signal.
- **Type annotations** — `def f(x: bool = True) -> bool` — the `bool` in the
  annotation position is a type, not a runtime bool literal (Python type
  hints are never mutated: `bool` is not `True`/`False`, so `BOOL_RE` never
  matches them). For TS, only the narrow case of a **type-alias declaration
  line** (`type Flag = true | false;`, optionally `export`/`declare`
  prefixed) has its bool literals excluded from bool-flip — this is
  `TS_TYPE_ALIAS_LINE_RE` in `mutate_and_run.py`. Bool literals in
  interface fields or parameter type positions (`interface X { flag: true }`)
  are **not** distinguished from runtime literals and can still be mutated —
  deliberately, because a regex heuristic broad enough to exclude those
  would also suppress real runtime literals like `{ enabled: true }` in an
  object literal, which are far more common and exactly what this smoke
  check exists to catch. See "Known regex-vs-AST gaps" below.
- **Block comments (`/* ... */`) on TS/JS/Go/C-family** — masked the same
  way as strings/line-comments when they open and close on the same line;
  code that follows `*/` later on that line is still scanned normally.

## Known regex-vs-AST gaps (always disclosed in `notes`)

The masking above is **line-based**, not a real tokenizer:

- Multi-line strings (Python triple-quoted docstrings, JS/TS template
  literals spanning lines) are not tracked across line boundaries — a
  mutation-looking token inside one could theoretically be touched.
- Multi-line comments (`/* ... */` in TS/JS/Go/C-family) are only masked
  when the `/*` and `*/` are on the same line; a block comment that opens
  on one line and closes on a later one is not tracked across the boundary.
- Go's `<-` channel operator, `->`-style return-type arrows, and TS/JS `=>`
  arrow functions are excluded from the comparison-flip regex via
  lookaround, but this is a pattern-level dodge, not a parser — unusual
  spacing or novel operators can still slip through.
- TS type positions other than a `type X = ...` alias declaration line
  (interface fields, function parameter/return type annotations using
  literal booleans) are not distinguished from runtime bool literals — see
  "What must never be mutated" above for why this is a deliberate,
  conservative trade-off rather than an oversight.

None of this is silently swallowed: `mutate_and_run.py` always emits this
limitation in its `notes` array, whether the run is PASS, BLOCK, or SKIP.

## Fallback when a seam can't be mutated

Some code has no mutable surface for this smoke check even though it's
worth testing — e.g. a thin wrapper around a platform type, or wiring that
only calls an external API with no branching/comparison of its own:

1. **Extract a pure function.** Pull the actual decision logic (the
   comparison, the boolean, the boundary) out of the platform/API-wiring
   code into a small pure function with no I/O. This is a **structural**
   change — route it through `tidy-first` as its own commit, separate from
   any behavioral change, so the extraction alone can be reviewed and the
   mutation smoke can then run against the extracted function.
2. **If extraction genuinely isn't possible** (the seam *is* the platform
   type or external wiring itself, with no decision logic to pull out),
   stop and use a waiver instead of forcing a mutation. See
   `references/waiver-fallback.md`.

Do not reach for a waiver before trying step 1 — most "unmutable" seams
turn out to have a small pure decision buried inside the wiring.
