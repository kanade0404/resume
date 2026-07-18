# Waiver Fallback

Use only after `references/mutation-recipes.md`'s fallback (extract a pure
function via `tidy-first`) genuinely doesn't apply — the seam itself *is*
the platform type or external wiring, with no decision logic to pull out.

## The waiver template

No dedicated tracking file. One line in the commit trailer or PR body:

```
mutation-gate: WAIVED - <seam> - <理由>
```

Example: `mutation-gate: WAIVED - aws_sdk_s3::Client::put_object wiring -
no comparison/boolean logic, pure I/O pass-through to the SDK call`

Keep `<seam>` `grep`-able (file/function name, not "the S3 stuff"); keep
`<理由>` honest about *why* extraction failed, not just "hard to test".

## Detection: 3rd waiver on the same seam → ADR

No counter file. Detection is a manual grep before waiving again:

```bash
git log --all --all-match -F \
  --grep='mutation-gate: WAIVED' \
  --grep='<seam>'
```

`<seam>` is text inside the commit message (the trailer template above), not
a file path — the `-- <pathspec>` form used previously filters commits by
*touched files*, so a function-name seam that doesn't literally appear in
any file path (e.g. `aws_sdk_s3::Client::put_object`) silently matches
nothing even when matching waiver commits exist. `--all-match -F` with two
`--grep` patterns instead ANDs both against the message text itself, which
is where `<seam>` actually lives.

On the **3rd** waiver for the same seam, stop and invoke `adr-writer` to
distill the platform constraint into an ADR instead of waiving a 4th time —
three waivers on one seam signals a structural (one-way-door) constraint.

## Known limitation

Depends on remembering the `git log --grep` check and on waiver text
consistently starting with `mutation-gate: WAIVED -`. A differently-worded
waiver, or one dropped by a squash-merge, won't be counted — treat the
count as a floor, not a precise total.
