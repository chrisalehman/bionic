#!/bin/bash
# payload/scripts/lib/plan.sh — the plan's integration branch, read once (wave-39 T16; D18, REQ-12 AC-12.1).
#
# WHAT IT OWNS. Two questions: which branch does this run integrate into, and how does it stand against the goals
# its plan declares?
#
#     plan_integration_branch <plan>
#                        the value of `integration-branch:` under the plan's `## SDLC State`, else the same key in
#                        its leading frontmatter; nothing when neither names one, or <plan> is no file. Always rc 0.
#     plan_goals, plan_goals_read, plan_one_file_median, plan_goal_slug
#                        the goals and their readings, below; the situation report, the release approval card and the
#                        tick read them here, so no page measures a goal its own way.
#     plan_scale, plan_requirements_file, plan_themes
#                        the requirements document's theme sections, the goals a wave or an epic reads first; at task
#                        scale the one theme, the run, over every criterion the matrix measures.
#     plan_goal_paragraph, plan_goal_status, plan_goal_declared_red
#                        what a document is for, one goal's status word, and whether the plan declared the red that
#                        missed a suite goal.
#
# THE ONE READER (burns debt integration-branch-reader; critic-structure-2). Two orders stood: close-out.sh read
# ## SDLC State and refused a plan whose frontmatter alone named the branch, its `closed-form` then fell back to the
# frontmatter, and session-poker.sh `handoff` read the frontmatter first with an awk of its own, while `release-check`
# read the frontmatter alone. D18 rules ## SDLC State first, the frontmatter as the fallback: the order lib/run.sh
# `plan_working_branch` already reads the working branch in. close-out.sh and every session-poker.sh reader of the key
# call this; tests/close-out-1.test.sh and tests/handoff-file.test.sh §BRANCH-AGREE hold them to one answer.
#
# THE GRAMMAR IS THE WORKING BRANCH'S. The section is `##` and blanks, then `SDLC State`; fenced lines are not read;
# the key may be indented; the value is its first word, one leading and one trailing quote of either kind dropped. A
# branch name holds no blank, so the first word is the whole of every value a plan carries; close-out's old reader
# took the rest of the line, trimmed, which differs only on a line no branch can be.
#
# NEEDS lib/run.sh (`_run_lines`, the newline rule: CRLF and a lone CR both end a line). Both callers source it first.
# The goal readers also ask lib/units.sh `units_rows` and lib/proof.sh `proof_last_line` when loaded; without them a
# one-file landing or a whole run reads as not measured.
# Sourced, never executed; bash 3.2.

_PLAN_IB_SDLC_AWK='
  /^[[:space:]]*```/ { fence = !fence; next }
  fence { next }
  /^##[[:space:]]/ { insdlc = ($0 ~ /^##[[:space:]]+SDLC State/); next }
  insdlc && /^[[:space:]]*integration-branch[[:space:]]*:/ {
    v = $0; sub(/^[[:space:]]*integration-branch[[:space:]]*:[[:space:]]*/, "", v); sub(/[[:space:]].*$/, "", v)
    gsub(/^["\047]|["\047]$/, "", v); print v; exit }'
_PLAN_IB_FM_AWK='
  NR == 1 && $0 == "---" { f = 1; next }
  f && $0 == "---" { exit }
  f && /^[[:space:]]*integration-branch[[:space:]]*:/ {
    v = $0; sub(/^[[:space:]]*integration-branch[[:space:]]*:[[:space:]]*/, "", v); sub(/[[:space:]].*$/, "", v)
    gsub(/^["\047]|["\047]$/, "", v); print v; exit }'
plan_integration_branch() {  # <plan>
  local plan="${1:-}" ib
  [ -n "$plan" ] && [ -f "$plan" ] || return 0
  ib="$(_run_lines "$plan" | awk "$_PLAN_IB_SDLC_AWK")"
  [ -n "$ib" ] || ib="$(_run_lines "$plan" | awk "$_PLAN_IB_FM_AWK")"
  printf '%s' "$ib"
  return 0
}

# ---------------------------------------------------------------- the plan's goals and their readings
#
# A GOAL IS A TARGET THE PLAN DECLARES IN ITS FRONTMATTER, read from the record and never typed. Each `goals:` line of
# the leading frontmatter holds one goal or several, `;` between them; a goal is
#
#     <theme> · <measure> (<reader>)
#
# the reader being the last parenthesis. The reader names where the measurement comes from, and four are read:
#   landing-report   the measure's `median under <n>m` (or `<n> min`) over the queue landings, the one-file ones
#                    alone when the measure says one-file; reached below the target, missed at or above it. A goal
#                    whose words say hand-holds reads the hand-holds window instead (hooks/poker/line.sh
#                    `hand_holds_ends`, `hand_holds_report`): the total from the last build landing to the release
#                    approval card, or to now before the card has rendered, against the measure's count (`zero` is
#                    0); reached at or under it, missed over it. A count only grows, so a miss before the card stands.
#   run log          the newest whole-run proof line's log and its `Wall: <n>s`, against `under <n> min`.
#   record/<f>.md    a reader-test record beside the run's landing record (else under the docs root): its first
#                    `verdict:` or `result:` line, pass (or passed, reached) reached, fail (or failed, missed) missed.
#   <suite> §<name>  the suite's newest verdict in the landing record (the section is the reader's, the record keys
#                    by suite): green reached, red missed.
# A measure with no target to compare is unmeasured, and says so. A reader of any other form, or none, is unreadable:
# no record will ever move it, so it never reads as a goal not measured yet, and its reading names the forms read.
# A goal reads reached only with a record behind it.
#
# AT WAVE AND EPIC SCALE THE REQUIREMENTS' THEMES ARE THE FIRST GOALS, read and never typed. A theme is a `## ` section
# of the plan's requirements file that holds a `### REQ-` heading (the governing-skill hook holds the document to three
# to six); its criteria are the plan's matrix rows whose AC belongs to one of its REQs, AC-<req>.<n> to REQ-<req>. A
# theme is reached when none of its rows is pending; pending while one is and the plan is before Step 6; overdue at
# Step 6 or later with one still pending, since the advance from 5 to 6 demands a verdict on every row; unmeasured
# when the matrix holds none of its criteria. Its measure is `<d> of <n> criteria discharged`, `, <w> waived` added
# when any is, and its reading names at most two open REQs. The `goals:` line is optional beside them and carries
# measured goals only; theme rows come first. A theme's row carries its opener last, the first sentence under its
# heading, so a reader that prints the goal can say what the theme is for. A task-scale plan reads one theme, `the run`,
# over every REQ its matrix measures, its opener the first sentence of the plan's own Goal. A theme is on course while
# it is pending with at least one criterion discharged.

# plan_scale <plan> -> the plan's `scale:`, from its leading frontmatter, else from `## SDLC State`; nothing when
# neither names one. Always rc 0.
plan_scale() {
  local plan="${1:-}" sc
  [ -n "$plan" ] && [ -f "$plan" ] || return 0
  sc="$(plan_frontmatter_get "$plan" scale)"
  [ -n "$sc" ] || sc="$(_run_lines "$plan" | awk '
    /^[[:space:]]*```/ { fence = !fence; next }
    fence { next }
    /^##[[:space:]]/ { s = ($0 ~ /^##[[:space:]]+SDLC State/); next }
    s && /^[[:space:]]*scale[[:space:]]*:/ { v = $0; sub(/^[^:]*:[[:space:]]*/, "", v); sub(/[[:space:]].*$/, "", v); print v; exit }')"
  printf '%s' "$sc"
  return 0
}

# plan_requirements_file <plan> -> the requirements file the plan reads: the `requirements:` path its Step-1 line
# names under the docs root (the plan sits at <docs>/plans/<epic>/<slug>.plan.md), else the sibling
# <docs>/specs/<epic>/<slug>.requirements.md; nothing when neither is a file. Always rc 0.
plan_requirements_file() {
  local plan="${1:-}" docs epic slug rel f
  [ -n "$plan" ] && [ -f "$plan" ] || return 0
  docs="${plan%/*}"; epic="${docs##*/}"; docs="${docs%/*}"; docs="${docs%/*}"
  slug="${plan##*/}"; slug="${slug%.plan.md}"
  rel="$(_run_lines "$plan" | awk '
    /^[[:space:]]*```/ { fence = !fence; next }
    fence { next }
    /^[[:space:]]*-[[:space:]]*Step 1:/ && match($0, /requirements:[ \t]*[^ \t;]+/) {
      s = substr($0, RSTART, RLENGTH); sub(/^requirements:[ \t]*/, "", s); print s; exit }')"
  for f in ${rel:+"$docs/$rel"} "$docs/specs/$epic/$slug.requirements.md"; do
    if [ -f "$f" ]; then printf '%s\n' "$f"; return 0; fi
  done
  return 0
}

# plan_goal_paragraph <file> -> the first paragraph of the file's `## Goal` section on one line: the lines joined by a
# blank, backticks and tabs dropped, the leading frontmatter and the section's `###` headings not read; nothing when the
# file is no file or has no Goal text. The one reader of what a document is for: the Step-1 and Step-3 cards print it
# and the sitrep's sheet carries it, so a card and a sheet cannot read one paragraph two ways. Always rc 0.
plan_goal_paragraph() {
  local f="${1:-}"
  [ -n "$f" ] && [ -f "$f" ] || return 0
  _run_lines "$f" | awk '
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    function clean(s) { gsub(/`/, "", s); gsub(/\t/, " ", s); return trim(s) }
    NR == 1 && $0 == "---" { fm = 1; next }
    fm == 1 && $0 == "---" { fm = 0; next }
    fm == 1 { next }
    /^## / { sec = (substr($0, 4) == "Goal"); next }
    /^### / { next }
    sec && !done {
      if (trim($0) == "") { if (g != "") done = 1 }
      else g = g (g == "" ? "" : " ") clean($0)
      next }
    END { if (g != "") print g }'
  return 0
}

# _plan_first_sentence <text> -> the text up to and including its first sentence end (a full stop and a blank), else
# the whole text. Stdin-free; prints nothing for no text.
_plan_first_sentence() {
  printf '%s\n' "${1:-}" | awk 'NF { if (match($0, /\. /)) print substr($0, 1, RSTART); else print; exit }'
}

# _plan_matrix_acs <plan> -> `M<TAB><AC id><TAB><status, lower case>` per row of the plan's `## Verification Matrix`
# table, the status column found by the header's own name; fenced lines are not read.
_plan_matrix_acs() {
  _run_lines "${1:-}" | awk -F'|' '
    /^[[:space:]]*```/ { fence = !fence; next }
    fence { next }
    /^## / { m = ($0 ~ /^## Verification Matrix/); col = 0; next }
    m && /^\|[ \t]*AC[ \t]*\|/ { for (i = 2; i < NF; i++) { c = $i; gsub(/^[ \t]+|[ \t]+$/, "", c); if (tolower(c) == "status") col = i }; next }
    m && col && /^\|[ \t]*AC-/ { a = $2; s = $col; gsub(/^[ \t]+|[ \t]+$/, "", a); gsub(/^[ \t]+|[ \t]+$/, "", s); print "M\t" a "\t" tolower(s) }'
}

# _plan_task_theme <plan> -> the one theme a task-scale plan reads, `the run<TAB><REQ ids><TAB><opener>`: the REQs are the
# `### REQ-` headings of the plan's requirements file (else of the plan itself) that have at least one matrix row, in the
# document's order; a plan whose documents hold no REQ heading reads the REQs its matrix rows name. The opener is the
# first sentence of the plan's own `## Goal`. Nothing when the matrix holds no row of any such REQ.
_plan_task_theme() {
  local plan="$1" q ids heads goal
  q="$(plan_requirements_file "$plan")"
  heads="$([ -z "$q" ] || _run_lines "$q" | awk '
    /^[[:space:]]*```/ { fence = !fence; next }
    fence { next }
    /^### REQ-/ { id = substr($0, 9); if (match(id, /^[A-Za-z0-9]+/)) print "R\t" substr(id, 1, RLENGTH) }')"
  [ -n "$heads" ] || heads="$(_run_lines "$plan" | awk '
    /^[[:space:]]*```/ { fence = !fence; next }
    fence { next }
    /^### REQ-/ { id = substr($0, 9); if (match(id, /^[A-Za-z0-9]+/)) print "R\t" substr(id, 1, RLENGTH) }')"
  ids="$({ printf '%s\n' "$heads"; _plan_matrix_acs "$plan" | awk -F'\t' '{ r = $2; sub(/^AC-/, "", r); sub(/\.[^.]*$/, "", r); print "M\t" r }'; } | awk -F'\t' '
    $1 == "R" { if (!($2 in rs)) { rs[$2] = 1; ro[++rn] = $2 }; next }
    $1 == "M" { if (!($2 in ms)) { ms[$2] = 1; mo[++mn] = $2 } }
    END { if (rn) { for (i = 1; i <= rn; i++) if (ro[i] in ms) printf "%s%s", (c++ ? " " : ""), ro[i] }
          else { for (i = 1; i <= mn; i++) printf "%s%s", (i > 1 ? " " : ""), mo[i] }
          if (c || (!rn && mn)) print "" }')"
  [ -n "$ids" ] || return 0
  goal="$(_plan_first_sentence "$(plan_goal_paragraph "$plan")")"
  printf 'the run\t%s\t%s\n' "$ids" "$goal"
}

# plan_themes <plan> -> `<theme><TAB><REQ ids, space-separated><TAB><opener>` per theme of the plan's requirements file,
# in the document's order (the id is the word after `### REQ-`); the opener is the first sentence of the first body line
# under the `## ` heading, empty when a heading or no text follows it. Nothing when no requirements file is found or
# when it holds no REQ under a `## ` section. At task scale there is one theme, `the run`, over every REQ the matrix
# measures (`_plan_task_theme`). Fenced lines are not read. Always rc 0.
plan_themes() {
  local plan="${1:-}" q
  case "$(plan_scale "$plan")" in
    wave|epic) ;;
    task) _plan_task_theme "$plan"; return 0 ;;
    *) return 0 ;;
  esac
  q="$(plan_requirements_file "$plan")"
  [ -n "$q" ] || return 0
  _run_lines "$q" | awk '
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    /^[[:space:]]*```/ { fence = !fence; next }
    fence { next }
    /^## / { h = substr($0, 4); sub(/[ \t]+$/, "", h); oh = 1; next }
    /^#/ { oh = 0 }
    /^### REQ-/ && h != "" {
      id = substr($0, 9); if (!match(id, /^[A-Za-z0-9]+/)) next; id = substr(id, 1, RLENGTH)
      if (!(h in seen)) { seen[h] = 1; ord[++n] = h }
      ids[h] = ids[h] (ids[h] == "" ? "" : " ") id; next }
    oh && h != "" && $0 ~ /[^ \t]/ {
      oh = 0; t = $0; gsub(/`/, "", t); gsub(/\t/, " ", t); t = trim(t)
      if (match(t, /\. /)) t = substr(t, 1, RSTART)
      if (!(h in op)) op[h] = t }
    END { for (i = 1; i <= n; i++) print ord[i] "\t" ids[ord[i]] "\t" op[ord[i]] }'
  return 0
}

# _plan_theme_reads <plan> -> one plan_goals_read row per theme, `<state><TAB><theme><TAB><measure><TAB><reading>` and, when
# the theme has an opener, `<TAB><opener>`. The state is unmeasured, reached, pending (nothing discharged yet), oncourse
# (pending with at least one criterion discharged) or overdue (open at step 6 or later).
_plan_theme_reads() {
  local plan="$1" themes cur
  themes="$(plan_themes "$plan")"
  [ -n "$themes" ] || return 0
  cur=""; declare -F _fill_current_field >/dev/null 2>&1 && { fill_current_forget; cur="$(_fill_current_field "$plan")"; }
  { printf '%s\n' "$themes" | awk -F'\t' 'NF { print "T\t" $1 "\t" $2 "\t" $3 }'
    # the matrix table's rows, each AC with its status cell
    _plan_matrix_acs "$plan"
  } | awk -F'\t' -v cur="$cur" '
    $1 == "T" { n++; nm[n] = $2; fr[n] = $4; k[n] = split($3, r, " "); for (i = 1; i <= k[n]; i++) { own[r[i]] = n; rq[n, i] = r[i] }; next }
    $1 == "M" { req = $2; sub(/^AC-/, "", req); sub(/\.[^.]*$/, "", req); t = own[req]; if (!t) next
      tot[t]++
      if ($3 == "discharged") d[t]++; else if ($3 == "waived") w[t]++; else { p[t]++; op[t, req] = 1 } }
    END {
      step = cur; sub(/[^0-9].*$/, "", step)
      for (t = 1; t <= n; t++) {
        m = (d[t] + 0) " of " (tot[t] + 0) " criteria discharged" (w[t] ? ", " w[t] " waived" : "")
        f = (fr[t] != "" ? "\t" fr[t] : "")
        if (!tot[t]) { print "unmeasured\t" nm[t] "\t" m "\tthe matrix holds none of its criteria" f; continue }
        if (!p[t]) { print "reached\t" nm[t] "\t" m "\tnone open" f; continue }
        o = ""; c = 0
        for (i = 1; i <= k[t]; i++) if ((t, rq[t, i]) in op) { c++; if (c <= 2) o = o (c > 1 ? ", " : "") "REQ-" rq[t, i] }
        if (c > 2) o = o " and " (c - 2) " more"
        print ((step != "" && step + 0 >= 6) ? "overdue" : (d[t] ? "oncourse" : "pending")) "\t" nm[t] "\t" m "\topen: " o f }
    }'
}

# plan_goals <plan> -> `<theme><TAB><measure><TAB><reader>` per goal, in the order the plan declares them; the reader
# is `-` when the goal names none. Nothing when the plan declares none or is no file. Always rc 0.
plan_goals() {
  local plan="${1:-}"
  [ -n "$plan" ] && [ -f "$plan" ] || return 0
  _run_lines "$plan" | awk '
    NR == 1 && $0 == "---" { f = 1; next }
    f && $0 == "---" { exit }
    f && /^[[:space:]]*goals[[:space:]]*:/ {
      v = $0; sub(/^[[:space:]]*goals[[:space:]]*:[[:space:]]*/, "", v)
      n = split(v, g, /;/)
      for (i = 1; i <= n; i++) {
        s = g[i]; gsub(/^[ \t]+|[ \t]+$/, "", s); if (s == "") continue
        j = index(s, " · "); if (j == 0) { t = s; m = "" } else { t = substr(s, 1, j - 1); m = substr(s, j + length(" · ")) }
        r = "-"
        if (match(m, /[ \t]*\([^()]*\)$/)) { r = substr(m, RSTART, RLENGTH); m = substr(m, 1, RSTART - 1); sub(/^[ \t]*\(/, "", r); sub(/\)$/, "", r) }
        print t "\t" m "\t" r
      }
    }'
  return 0
}

# plan_goal_slug <theme> -> the theme as a key word: lower case, every run of other characters one `-`, none at
# either end (`fast landings` is `fast-landings`). The person's ledger opens `decide:goal:<slug>` on a first miss.
plan_goal_slug() {
  printf '%s\n' "${1:-}" | LC_ALL=C awk '{ s = tolower($0); gsub(/[^a-z0-9._]+/, "-", s); gsub(/^-+|-+$/, "", s); print s }'
}

# plan_one_file_median <plan> <landing report with rows> -> `<median minutes><TAB><landings>` over the queue landings
# whose task's Files cell names exactly one path outside the run's own record tree; nothing when there is none. The
# median is the middle value, the mean of the middle two for an even count. A task of more files moves nothing here.
plan_one_file_median() {
  local plan="${1:-}" rep="${2:-}"
  { printf '%s\n' "$rep" | awk 'NR > 1 && $2 == "queue" { for (i = 3; i <= NF; i++) if (index($i, "minutes=") == 1 && $i != "minutes=-") print "L\t" $1 "\t" substr($i, 9) }'
    declare -F units_rows >/dev/null 2>&1 && units_rows "$plan" 2>/dev/null | awk -F'\t' '{ print "R\t" $1 "\t" $9 }'
  } | awk -F'\t' '
    $1 == "R" { n = split($3, a, ","); c = 0
      for (i = 1; i <= n; i++) { x = a[i]; gsub(/^[ \t`]+|[ \t`]+$/, "", x)
        if (x == "" || x == "—" || x == "-" || tolower(x) == "none" || index(x, ".bionic/") == 1) continue; c++ }
      one[$2] = (c == 1); next }
    $1 == "L" { k++; id[k] = $2; mn[k] = $3 + 0 }
    END {
      for (i = 1; i <= k; i++) if (one[id[i]]) v[++m] = mn[i]
      if (m == 0) exit
      for (i = 2; i <= m; i++) { t = v[i]; for (j = i - 1; j >= 1 && v[j] > t; j--) v[j + 1] = v[j]; v[j + 1] = t }
      d = (m % 2) ? v[(m + 1) / 2] : (v[m / 2] + v[m / 2 + 1]) / 2
      printf "%.1f\t%d\n", d, m }'
}

# plan_goal_status <state> -> the goal's status as every surface prints it, from `plan_goals_read`'s state word: reached
# is `met`; missed, and a theme overdue past Step 6 with criteria open, `not met`; a theme pending with at least one
# criterion discharged (`oncourse`) `on course`; unreadable `unreadable`; pending with none discharged, unmeasured or any
# other word `not measured`. The one reading of a goal: the sitrep's sheet and the release approval card both call it,
# so the same plan cannot give one goal two statuses.
plan_goal_status() {
  case "${1:-}" in
    reached) printf 'met\n' ;;
    missed|overdue) printf 'not met\n' ;;
    oncourse) printf 'on course\n' ;;
    unreadable) printf 'unreadable\n' ;;
    *) printf 'not measured\n' ;;
  esac
}

# plan_goal_declared_red <landing record> <reading> -> rc 0 when a suite goal's reading, `<suite>.test.sh red at <sha>`,
# names a suite the record holds a standing `debt:` line for: the line a landing of a `Lands-red:` row writes at its
# publish (lib/line.sh `_line_debt_write`), not voided by a `void:` line. The plan declared that red, so the miss it
# causes is no new decision for the person. rc 1 for any other reading or suite, and for no record.
plan_goal_declared_red() {
  local rec="${1:-}" suite="${2:-}"
  suite="${suite%% red at *}"
  case "$suite" in *.test.sh) ;; *) return 1 ;; esac
  [ -n "$rec" ] && [ -f "$rec" ] || return 1
  awk -v s="${suite##*/}" '
    /^debt: / { id = ""; su = ""; n = split($0, a, " ")
      for (i = 2; i <= n; i++) { if (index(a[i], "id=") == 1) id = substr(a[i], 4); else if (index(a[i], "suite=") == 1) su = substr(a[i], 7) }
      b = su; sub(/.*\//, "", b); if (id != "" && b == s) debt[id] = 1; next }
    /^void: / { n = split($0, a, " "); for (i = 2; i <= n; i++) if (index(a[i], "id=") == 1) void[substr(a[i], 4)] = 1; next }
    END { for (i in debt) if (!(i in void)) exit 0; exit 1 }' "$rec" 2>/dev/null
}

# plan_goals_read <plan> <landing record> <landing report with rows> -> `<state><TAB><theme><TAB><measure><TAB><reading>`
# per goal: the requirements' themes first (`_plan_theme_reads`), then the `goals:` line's in the plan's order. A theme's
# state is reached, pending, oncourse, overdue or unmeasured, and its row ends in a fifth column, the opener, when it has
# one; a measured goal's state is reached, missed, unmeasured or unreadable and its row has four; the reading says in
# words what was read. The record's directory is the run's record directory; the docs root is two above it.
# Always rc 0.
plan_goals_read() {
  local plan="${1:-}" rec="${2:-}" rep="${3:-}" recdir docs t m r st rd tgt v n line ev f h s hs hrow hu hst
  recdir="${rec%/*}"; docs="${recdir%/*}"; docs="${docs%/*}"
  _plan_theme_reads "$plan"
  while IFS='	' read -r t m r; do
    [ -n "$t" ] || continue
    st=unmeasured; rd=""
    tgt="$(printf '%s\n' "$m" | awk 'match($0, /under [0-9]+(\.[0-9]+)? ?(m|min|minutes)([^a-z]|$)/) { s = substr($0, RSTART + 6); sub(/[^0-9.].*/, "", s); print s + 0; exit }')"
    case "$r" in
      *landing-report*)
        case "$t $m" in *[Hh]and-hold*) r=hand-holds ;; esac ;;
    esac
    case "$r" in
      hand-holds)
        # the count the measure names, its first number, `zero`, `none` or `no` read as 0
        tgt="$(printf '%s\n' "$m" | awk '{ s = tolower($0) } s ~ /^(zero|none|no)([^a-z]|$)/ { print 0; exit } match(s, /[0-9]+/) { print substr(s, RSTART, RLENGTH) + 0; exit }')"
        if [ -z "$tgt" ]; then rd="the measure names no target count"
        elif ! declare -F hand_holds_ends >/dev/null 2>&1 || ! declare -F hand_holds_report >/dev/null 2>&1; then rd="the hand-holds count is not loaded"
        else
          h="$(project_root "${plan%/*}" 2>/dev/null)"
          # read into a variable first: a here-string of the call would run it under the tab IFS, and its own read
          # of the landing record splits on blanks
          v="$(hand_holds_ends "$rec" "$h" "$plan")"
          IFS='	' read -r hs hrow hu hst <<< "$v"
          [ "$hs" != - ] || hs=""
          [ "$hst" = page ] || hu=""
          v="$(hand_holds_report "$rec" "$h" "$plan" ${hs:+--since "$hs"} ${hu:+--until "$hu"} | awk '{ for (i = 1; i <= NF; i++) if (index($i, "total=") == 1) { print substr($i, 7) + 0; exit } }')"
          if [ -z "$v" ]; then rd="the hand-holds report printed no total"
          else
            st="$(awk -v a="$v" -v b="$tgt" 'BEGIN { print (a + 0 <= b + 0) ? "reached" : "missed" }')"
            rd="$v hand-hold$([ "$v" = 1 ] || echo s) from $([ -n "$hs" ] && echo "the last build landing ($hrow)" || echo "the first line")"
            case "$hst" in
              page) rd="$rd to the release approval card" ;;
              stale) rd="$rd to now: the card has not rendered since the last build landing" ;;
              *) rd="$rd to now: the card has not rendered" ;;
            esac
          fi
        fi ;;
      *landing-report*)
        if [ -z "$tgt" ]; then rd="the measure names no target in minutes"
        else
          case "$m" in
            *one-file*) v="$(plan_one_file_median "$plan" "$rep")"; s="one-file " ;;
            *) v="$(printf '%s\n' "$rep" | awk 'NR > 1 && $2 == "queue" { for (i = 3; i <= NF; i++) if (index($i, "minutes=") == 1 && $i != "minutes=-") { n++; x[n] = substr($i, 9) + 0 } }
                 END { if (!n) exit; for (i = 2; i <= n; i++) { t = x[i]; for (j = i - 1; j >= 1 && x[j] > t; j--) x[j + 1] = x[j]; x[j + 1] = t }
                       printf "%.1f\t%d\n", (n % 2) ? x[(n + 1) / 2] : (x[n / 2] + x[n / 2 + 1]) / 2, n }')"; s="" ;;
          esac
          if [ -z "$v" ]; then rd="no ${s}landing yet"
          else
            n="${v#*	}"; v="${v%%	*}"
            st="$(awk -v a="$v" -v b="$tgt" 'BEGIN { print (a + 0 < b + 0) ? "reached" : "missed" }')"
            rd="the ${s}median is $(awk -v a="$v" 'BEGIN { printf "%d", a + 0.5 }') min over $n landing$([ "$n" = 1 ] || echo s)"
          fi
        fi ;;
      *'run log'*)
        line=""; declare -F proof_last_line >/dev/null 2>&1 && line="$(proof_last_line "$plan" regression 2>/dev/null)"
        ev="$(printf '%s\n' "$line" | tr ' ' '\n' | sed -n 's/^evidence=//p' | head -1)"
        h="$(printf '%s\n' "$line" | tr ' ' '\n' | sed -n 's/^head=//p' | head -1)"
        if [ -z "$line" ]; then rd="no whole run on record"
        elif [ -z "$tgt" ]; then rd="the measure names no target in minutes"
        else
          v="$(awk '/^Wall: [0-9]+s/ { s = $2; sub(/s.*/, "", s); print s }' "$docs/$ev" 2>/dev/null | tail -1)"
          if [ -z "$v" ]; then rd="the whole run's log holds no time"
          else
            v=$(( (v + 30) / 60 ))
            st="$(awk -v a="$v" -v b="$tgt" 'BEGIN { print (a + 0 < b + 0) ? "reached" : "missed" }')"
            rd="the whole run took $v min at ${h:0:8}"
          fi
        fi ;;
      *record/*.md*)
        f="$(printf '%s\n' "$r" | /usr/bin/grep -oE 'record/[^ ()]+\.md' | head -1)"
        if [ -f "$recdir/${f#record/}" ]; then f="$recdir/${f#record/}"; elif [ -f "$docs/$f" ]; then f="$docs/$f"; else f=""; fi
        if [ -z "$f" ]; then rd="no record yet"
        else
          v="$(awk 'tolower($0) ~ /^(verdict|result):/ { s = tolower($0); sub(/^[a-z]+:[ \t]*/, "", s); print s; exit }' "$f" 2>/dev/null)"
          case "$v" in
            pass*|reached*) st=reached; rd="the record says ${v%% *}" ;;
            fail*|missed*) st=missed; rd="the record says ${v%% *}" ;;
            *) rd="the record holds no verdict yet" ;;
          esac
        fi ;;
      *' §'*)
        s="${r%% §*}"; s="${s##* }"; case "$s" in *.test.sh) ;; *) s="$s.test.sh" ;; esac
        [ -n "${_LINE_FIELDS_AWK:-}" ] || { [ -r "${BASH_SOURCE[0]%/*}/line.sh" ] && . "${BASH_SOURCE[0]%/*}/line.sh"; } >/dev/null 2>&1
        v="$(awk -F'|' -v s="$s" "${_LINE_FIELDS_AWK:-}"'line_ev() == "verdict" && line_kv("suite") == s {
               r = line_kv("result"); if (r == "green" || r == "red") l = r "\t" substr(line_kv("commit"), 1, 8) } END { if (l != "") print l }' "$rec" 2>/dev/null)"
        case "${v%%	*}" in
          green) st=reached; rd="$s green at ${v#*	}" ;;
          red) st=missed; rd="$s red at ${v#*	}" ;;
          *) rd="$s not run on the line yet" ;;
        esac ;;
      *) st=unreadable
         rd="the sitrep reads no measure of this form: name a record/<file>.md with a verdict: line, a <suite> §<section>, the run log, the landing report or the hand-holds count" ;;
    esac
    printf '%s\t%s\t%s\t%s\n' "$st" "$t" "$m" "$rd"
  done <<PLAN_GOALS_EOF
$(plan_goals "$plan")
PLAN_GOALS_EOF
  return 0
}
