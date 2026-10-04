# Normalizer for `prr fetch` (fetch_threads.sh).
#
# Pure transformation: raw GitHub API payloads in, normalized JSON out. Kept in
# its own file so it can be exercised with fixtures without calling GitHub
# (see tests/test_pr_review_respond_fetch.py in the skills repo).
#
# Invocation (all inputs via --slurpfile, so each $x is a 1-element array):
#   jq -n -f normalize_fetch.jq \
#     --slurpfile meta <pr-meta.json> \
#     --slurpfile threads <review-threads.json> \
#     --slurpfile issue_comments <issue-comments.json> \
#     --slurpfile reviews <reviews.json> \
#     --arg pr_author <login>

def vendor(login):
  (login // "" | ascii_downcase) as $l
  | if   ($l | startswith("coderabbit")) then "coderabbit"
    elif ($l | startswith("devin")) or ($l | contains("devin-ai")) then "devin"
    else "human" end;

def nonblank: (. // "") | test("\\S");

def trim_ws: sub("^\\s+"; "") | sub("\\s+$"; "");

def count_of(re): [match(re; "g")] | length;

# CodeRabbit section headers that carry actionable findings *outside* any
# inline review thread. Anything else ("Review info", "Review details",
# "Additional context used", "Prompt for AI Agents", ...) is NOT a findings
# section.
def finding_category:
  if   test("Outside diff range"; "i")        then "outside_diff_range"
  elif test("Nitpick comments?"; "i")         then "nitpick"
  elif test("Duplicate comments?"; "i")       then "duplicate"
  elif test("Additional comments?"; "i")      then "additional"
  else null end;

# "<em>🟡 Minor</em> · Lay out the page first. · <code>headless.ts:23-26</code>"
#   -> "Lay out the page first."
def summary_title:
  gsub("<code>.*?</code>"; "") | gsub("<em>.*?</em>"; "") | gsub("<[^>]+>"; "")
  | split("·") | map(trim_ws) | map(select(length > 0)) | join(" · ");

def flush:
  if .cur == null then .
  else
    (.cur.body | join("\n") | gsub("</?blockquote>"; "") | trim_ws) as $b
    | (if (.cur.title // "") != "" then .cur.title
       else
         (([.cur.body[] | capture("^\\s*\\*\\*(?<t>.+?)\\*\\*\\s*$") | .t] | first)
          // ([.cur.body[] | trim_ws | select(length > 0 and (startswith("_") | not))] | first // "" | .[0:120]))
       end) as $title
    | .findings += [ .cur | del(.body) | . + { title: $title, body: $b } ]
    | .cur = null
  end;

def start_finding($path; $s; $e; $title):
  flush
  | .cur = {
      category: .cat,
      path: $path,
      start_line: ($s | tonumber),
      end_line: (($e // $s) | tonumber),
      title: $title,
      body: []
    };

# Best-effort decomposition of a review body into findings. Two CodeRabbit
# layouts are recognized (both observed in the wild):
#
# (A) nested — category <details> > per-file <details> > "`range`: **Title**" items
#   <details><summary>⚠️ Outside diff range comments (2)</summary><blockquote>
#     <details><summary>src/foo.ts (2)</summary><blockquote>
#       `10-15`: **Title**
#       body ... (may contain nested <details>, e.g. "Prompt for AI Agents")
#       ---
#       `42`: **Next title**
#     </blockquote></details>
#   </blockquote></details>
#
# (B) flat — bold header (often inside a "> [!CAUTION]" callout) > one
#     <details> per finding whose first line is "`path:range`"
#   > **⚠️ Outside diff range comments (1)**
#   > <details>
#   > <summary><em>🟡 Minor</em> · Title · <code>foo.ts:23-26</code></summary><blockquote>
#   > `src/foo.ts:23-26`
#   > body ...
#   > </blockquote></details>
#
# Leading "> " quote markers are stripped first. Depth is tracked per line by
# counting <details> opens/closes, so nested <details> inside a finding body are
# never mistaken for category/file headers. Anything that does not fit is
# simply not decomposed — the caller always keeps the full review body.
def embedded_findings:
  (split("\n")
   | reduce (.[] | sub("^\\s*(>\\s?)+"; "")) as $line (
       {depth: 0, cat: null, cat_depth: null, file: null, cont_depth: null,
        cont_title: null, cur: null, findings: []};
       ($line | count_of("<details\\b")) as $opens
       | ($line | count_of("</details>")) as $closes
       | (($line | capture("<summary>(?<s>.*?)</summary>") | .s) // null) as $sum
       | (($line | capture("^\\s*\\*\\*(?<s>.+?)\\*\\*\\s*$") | .s) // null) as $bold
       | .depth += $opens
       | (if $sum != null and ($sum | finding_category) != null
              and (.cat == null or .depth <= .cat_depth) then
            # (A) category header
            flush | .cat = ($sum | finding_category) | .cat_depth = .depth
            | .file = null | .cont_depth = null
          elif $bold != null and ($bold | finding_category) != null
              and (.cat == null or .depth <= .cat_depth) then
            # (B) category header
            flush | .cat = ($bold | finding_category) | .cat_depth = .depth
            | .file = null | .cont_depth = null
          elif $sum != null and .cat != null and .depth == .cat_depth + 1 then
            # container directly under a category: per-file block (A) or per-finding block (B)
            flush | .cont_depth = .depth
            | if ($sum | test("<code>")) or (($sum | test("^[^<>]+\\(\\d+\\)\\s*$")) | not) then
                .file = null | .cont_title = ($sum | summary_title)
              else
                .file = ($sum | sub("\\s*\\(\\d+\\)\\s*$"; "") | trim_ws) | .cont_title = null
              end
          elif .cat != null and .cont_depth != null and .depth == .cont_depth
               and ($line | test("^\\s*`[^`]+:\\d+(-\\d+)?`\\s*$")) then
            # (B) finding start: `path:start-end`
            ($line | capture("^\\s*`(?<p>[^`]+):(?<s>\\d+)(-(?<e>\\d+))?`")) as $m
            | start_finding($m.p; $m.s; $m.e; .cont_title)
          elif .file != null and .depth == .cont_depth
               and ($line | test("^\\s*`\\d+(-\\d+)?`\\s*:")) then
            # (A) finding start: `start-end`: **Title**
            ($line | capture("^\\s*`(?<s>\\d+)(-(?<e>\\d+))?`\\s*:\\s*(?<rest>.*)$")) as $m
            | start_finding(.file; $m.s; $m.e; (($m.rest | capture("\\*\\*(?<t>.+?)\\*\\*") | .t) // null))
          elif .cat != null and .cont_depth == null and .depth == .cat_depth
               and ($line | test("^\\s*---\\s*$")) then
            # (B) a rule at category level ends the section
            flush | .cat = null | .cat_depth = null
          elif .cur != null and .depth == .cont_depth and ($line | test("^\\s*---\\s*$")) then
            .
          elif .cur != null and (.depth - $closes) >= .cont_depth then
            # a line that closes the container itself is layout, not finding text
            .cur.body += [$line]
          else . end)
       | .depth -= $closes
       | (if .cont_depth != null and .depth < .cont_depth then
            flush | .file = null | .cont_depth = null | .cont_title = null
          else . end)
       | (if .cat != null and .depth < .cat_depth then flush | .cat = null | .cat_depth = null else . end)
     )
   | flush
   | .findings);

($meta[0]) as $meta
| ($threads[0] // []) as $threads
| ($issue_comments[0] // []) as $issue_comments
| ($reviews[0] // []) as $reviews
| {
    pr: $meta,
    threads: [
      $threads[]
      | . as $t
      | ($t.comments.nodes[0]) as $root
      | {
          thread_id: $t.id,
          is_resolved: $t.isResolved,
          is_outdated: $t.isOutdated,
          root_comment: {
            id: $root.databaseId,
            author: $root.author.login,
            vendor: vendor($root.author.login),
            path: $root.path,
            line: $root.line,
            start_line: $root.startLine,
            original_line: $root.originalLine,
            body: $root.body,
            url: $root.url,
            created_at: $root.createdAt
          },
          self_replied: ([$t.comments.nodes[1:][] | select(.author.login == $pr_author)] | length > 0)
        }
    ],
    review_bodies: [
      $reviews[]
      | select(.state != "PENDING")
      | select(.body | nonblank)
      | {
          id: .id,
          author: .user.login,
          vendor: vendor(.user.login),
          state: .state,
          body: .body,
          submitted_at: .submitted_at,
          url: .html_url,
          commit_id: .commit_id,
          embedded_findings: (.body | embedded_findings)
        }
    ],
    issue_comments: [
      $issue_comments[]
      | {id, author: .user.login, vendor: vendor(.user.login), body, url: .html_url, created_at}
    ]
  }
| .counts = {
    threads: (.threads | length),
    unresolved_threads: ([.threads[] | select(.is_resolved | not)] | length),
    # Phase A triages only these: unresolved, not outdated, not already
    # answered by the PR author. The final gate reconciles against this.
    eligible_threads: ([.threads[] | select((.is_resolved | not) and (.is_outdated | not) and (.self_replied | not))] | length),
    # unresolved but skipped by Phase A (outdated or self-replied) — reported separately
    skipped_threads: ([.threads[] | select((.is_resolved | not) and (.is_outdated or .self_replied))] | length),
    review_bodies: (.review_bodies | length),
    embedded_findings: ([.review_bodies[].embedded_findings[]] | length),
    issue_comments: (.issue_comments | length)
  }
