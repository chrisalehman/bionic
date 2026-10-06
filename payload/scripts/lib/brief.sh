#!/bin/bash
# payload/scripts/lib/brief.sh — THE CONTRACT GRAMMAR, DEFINED ONCE
# (epic-23 wave-20-fixit-187 T6; REQ-4, spec D4, design ledger Δ10.)
#
# WHAT IT OWNS. What a valid Files:/Suites:/Re-executes: contract is: the lift that reads a
# brief's labelled fields (`lift_contract_fields`), the value filter every field passes
# (`sanitize`), the run caps (`DP_AUDITOR_RUNS_MAX`, `DP_SUITES_MAX`, `dp_runs_cap`), and
# every check the three instrument fields feed, down to the suite set the row records
# (`brief_validate_fields`). Until wave-20 all of it lived inside hooks/dispatch-preflight.sh,
# which made the dispatch the only door a contract could be judged at.
#
# THREE DOORS, ONE BODY (Δ10). A contract enters by a dispatch (hooks/dispatch-preflight.sh),
# by `session-poker.sh amend` (T9), which widens a live row, or by `session-poker.sh task-add`,
# which adds one. Each validates through this file, so an amended contract is held to exactly
# a fresh dispatch's standard. The rejected alternative was a cheap bounds check in `amend`,
# which would have put the weakest check on the one door that widens permissions.
#
# NO BEHAVIOUR MOVED. Everything below `sanitize` down to the end of `lift_contract_fields`
# is the hook's text, carried over verbatim. `brief_validate_fields` is the hook's arms from
# "A DECLARATION IS LITERAL TEXT" through the derivation, with four mechanical changes:
#
#   1. `dp_finding <fact> <fix> <detail>` -> `"$sink" finding <fact> <fix> <detail>`
#   2. `warn <line>`                      -> `"$sink" warn <line>`
#   3. the hook's globals (C_FILES, DP_RUNS_CAP, BIONIC_ROOT, SUITES_ALLOWED, …) -> locals,
#      the arguments, and the two BRIEF_SUITES_* results
#   4. the derivation overrun's early spend -> `return 2`; the hook spends it
#
# The comments inside that function were written from the dispatch wall's seat, and "this
# hook" in them means hooks/dispatch-preflight.sh. The derivation's bound is that hook's too
# (lib/bounds.sh, IMPACT_BOUND_S under its 15 s registration); a door whose host registers a
# shorter timeout must say so where it calls.
#
# THE INTERFACE.
#
#   lift_contract_fields <brief text> [<subagent_type>]   -> `kind=value` lines,
#       `questions=` among them: a reader's `Questions:` set (wave-27 T15)
#   dp_runs_cap <subagent_type> [<questions>] -> the runs a Re-executes: may declare, housekeeping aside
#   brief_files_entry <entry>          -> the spelling a Files: line stores for <entry>
#       (wave-27 T29, T42; D21): as written when the one reader records it, else `./<entry>`
#       when that is recorded, else nothing it can be spelt as (rc 2)
#   brief_field <lifted> <kind>        -> one kind's value, bounded as the roster row stores it
#   brief_validate_fields <lifted> <subagent_type> <root> <sink>
#       -> rc 0: no finding · rc 1: at least one · rc 2: the derivation overran its bound, so
#          the suite set was never built (its finding is already in the sink)
#       sets BRIEF_SUITES_ALLOWED and BRIEF_SUITES_SOURCE (`declared`, `derived` or empty), the
#       two values the roster row records
#       calls `<sink> finding <fact> <fix> <detail>` once per fault, in the order the dispatch
#       wall reports them, and `<sink> warn <line>` for a loud pass
#   brief_body_advisories <brief text> <name> <files> <suites-allowed> <re-executes> <poker>
#       -> one line per ADVISORY on stdout (an undeclared `bash tests/x.test.sh` in the body, an
#          edit of a path outside `Files:`), each ending in the `amend` line that declares it;
#          never a finding, always rc 0 (wave-24 T14, D13)
#
# A door with no brief builds one: `amend` hands `lift_contract_fields` a span of its own
# (`Files: …`, `Suites: …`, `Re-executes: …`), so what it validates is exactly what a
# dispatch carrying those lines would have been judged by.
#
# <root> is the repository root: `.bionic/config.yaml`'s `impact-command:` is read there and
# the derivation runs there.
#
# BASH 3.2. SOURCED, NEVER EXECUTED, AND SILENT AT SOURCE TIME.
#
# [WALL: tests/dispatch-preflight.test.sh]
# [WALL: tests/cross-gate-agreement.test.sh]

_brief_self_dir() {
  local self="${BASH_SOURCE[0]}"
  case "$self" in */*) echo "${self%/*}" ;; *) echo "." ;; esac
}
_BRIEF_LIB_DIR="$(cd "$(_brief_self_dir)" && pwd -P)"

# THE ONE RUN RULE ON BOTH SIDES OF THE ROW (wave-20 T4; REQ-7, D7). The lift's `collapse()`
# pastes CMD_RUN_NORM_AWK in and runs `cmdnorm_run` before a declared run is stored, the rule
# the writer-side budget arm builds its claim with. Guarded on the variable, so a caller that
# has already sourced cmd-class.sh pays nothing.
if [ -z "${CMD_RUN_NORM_AWK:-}" ]; then
  # shellcheck source=/dev/null
  . "$_BRIEF_LIB_DIR/cmd-class.sh"
fi

# `config_value` reads the `impact-command:` key; lib/roots.sh is its one definition.
if ! declare -F config_value >/dev/null 2>&1; then
  # shellcheck source=/dev/null
  . "$_BRIEF_LIB_DIR/roots.sh"
fi

# Values are pipe-delimited on one line, so a field carrying a newline or a `|`
# would forge a row. Never a refusal — the ledger normalizes and records.
#
# THE THIRD ARGUMENT IS THE FIELD NAME (T18, REQ-9/D7 — the write-side half of the fix
# `hooks/session-poker.sh`'s `clean()` already carries for the reader side, task T9).
# `files=` and `suites_allowed=` are LIST-valued — a space- or comma-joined set — and a
# dispatch declaring enough files or naming enough suites overflows even this file's
# widest cap (900) on a perfectly ordinary brief: a 70-suite `Suites:` line runs to
# 1.7-1.8 KB. The cut then silently drops suites off the end, narrowing a budget the wall
# never agreed to. Every OTHER field this hook sanitizes — name, deliverable, duration,
# progress, cadence, claims, waiver, the ambiguity candidates, the plan path — is prose or
# a single path, where even the smallest existing cap is already more than any real value
# needs, so they keep the cut. Callers that pass no field name (every one but the two
# `C_FILES`/`C_SUITES` call sites) get today's behaviour exactly, caps unchanged.
#
# AND `re_executes=` KEEPS ITS PIPE (T4, REQ-7, D4). This filter runs on the value that is
# then handed to `roster_row`, which is the ONE writer of the row and the one place that
# knows how the row holds a `|` — it escapes the character for this field
# (`payload/scripts/lib/roster.sh`, `roster_pipe_escape`) rather than folding it. Folding
# here would destroy the pipe before the writer ever saw it, and the quote-aware lift above
# would be admitting a command the row could not carry. Every OTHER field still folds: none
# of them is read back and compared to text a human typed, so for them a forged segment is
# the only risk worth pricing and the fold is still the right answer.
sanitize() {  # <value> <max-chars> [<field name>]
  local out _s1='\n\r\t|' _s2='    '
  case "${3:-}" in re_executes) _s1='\n\r\t'; _s2='   ' ;; esac
  out="$(printf '%s' "$1" \
    | tr "$_s1" "$_s2" \
    | sed -e 's/[[:cntrl:]]/ /g' -e 's/  */ /g' -e 's/^ *//' -e 's/ *$//')"
  case "${3:-}" in
    files|suites_allowed|re_executes) printf '%s' "$out" ;;
    *) printf '%s' "$out" | cut -c "1-$2" ;;
  esac
}

# ---------- contract-state extraction ----------
#
# The anchors are the labeled fields the dispatch brief already carries — the
# seven-field sentence in skills/canonical-sdlc/SKILL.md §Dispatch, span-pinned
# by tests/dispatch-spans.test.sh §5d, with the exemplar brief recorded at
# .bionic/docs/record/w2-ac3-run.md. This lifts the BRIEF's reading, never the
# orchestrator's restatement (spec §Design invariant).
#
# Two properties earn the awk pass over a line-oriented grep:
#   * a raw label span reaches the NEXT LABEL, not the newline — real briefs put
#     two fields on one line ("Expected duration: ~35 minutes. Progress: <path>")
#     and a line-scoped reader swallows the second into the first. That span is then
#     BOUNDED per field before use (epic-16 wave-02 R1): the deliverable takes the
#     first path-shaped token inside the label's own first sentence (never a
#     following input path — Step-6 review C-2), and duration/cadence take a value
#     bounded at the first clause boundary (never a run-on — C-1/F-3). Progress,
#     claims and the waiver reason still consume their whole span;
#   * labels nest ("progress" inside "progress artifact", "duration" inside
#     "expected duration"), so labels are matched longest-first and a shorter
#     one overlapping an accepted longer one is discarded. Without that, the
#     inner match becomes a terminator for its own outer span and every value
#     lifts empty.
# Deliverable and progress values are reduced to path-shaped tokens, because
# their consumers (tasks 4/5, 4/6) stat them; a slash-bearing token with no
# letter is a fraction ("task 4/3"), not a path.
#
# THE LIVENESS FIELDS (`cadence`, `claims`) join the same table, because task
# 4/7 shipped them into the same §Dispatch prose the labels above anchor on:
# "The progress-artifact path carries a `cadence` alongside it" and "A subprocess
# claim — a process pattern plus its output file — is conditional-required". They
# were prose-only for one task — hooks/stop-check.sh read `claims=` off a row no
# writer could produce, which the Step-6 six-axis review called for what it was
# (axis-3 FAIL: a shipped reader with no producer, its only test hand-writing an
# impossible row). Two grammar notes, both forced by that ratified sentence:
#
#   * `cadence` may be introduced by whitespace instead of a colon, because the
#     contract puts it ALONGSIDE the progress path inside one sentence
#     ("Progress: <path>, cadence ~6m") rather than on a labeled line of its own.
#     It is the only label with a relaxed separator, and the separator still has
#     to be there — `cadences` is not a hit. That relaxation is also why the hit
#     is POSITIONAL: a lexical match alone turned every prose use of the word
#     into a declaration (Step-6 critic F-2), so END additionally requires the
#     hit to fall inside the span the progress label owns — which is exactly
#     where the sentence above puts it.
#   * the subprocess claim is spelled in the contract's own words — "A subprocess
#     claim" — and those are the only two labels that lift it. A bare `claims`
#     label was tried and withdrawn: it matched "verify every claim the report
#     claims:" in an ordinary review brief and invented a subprocess for it,
#     which the P2 display then reports as `live: no`, the alarm direction.
#   * the subprocess claim declares two things in one span, and only one of them
#     has a consumer: the PATTERN, which hooks/stop-check.sh existence-checks.
#     So the pattern is what the row carries — the backticked or quoted run when
#     the author marks one, else the text up to the first comma or arrow.
LEAD_CHARS="(\"[<\`$(printf '\047')"
TRAIL_CHARS=")\"]>\`,;:!?.$(printf '\047')"
QUOTE_CHARS="\`\"$(printf '\047')"

# ---------- the re-execution cap is the evidence question's (wave-20 T4; wave-27 T15, F4) ----------
#
# THREE IS THE EVIDENCE QUESTION'S NUMBER. Its source is the evidence checks file —
# "Re-execute at least one evidence command per tier used (cap 3 total)"
# (payload/context/checks-evidence.md) — and it used to bind every role's `Re-executes:`, so a
# test-runner re-running a jest, pytest and go floor split it into two dispatches for a rule
# written about one reading (triage-B D3). Chris moved it (Δ3): the evidence reader keeps
# three; every other brief is bounded by SUITES_MAX (Δ9), the count that already bounds
# `Suites:`, so the two spellings of one statement share one ceiling and no new number exists.
#
# THE QUESTION DECIDES, NOT THE ROLE (wave-27 T15; review pass 15, F4). The rule was keyed to
# `bionic:auditor`, and at `tested` the dealing gives `evidence` to the critic, which escaped it.
# A reader role (auditor, critic, reviewer) whose brief's `Questions:` holds `evidence` is held
# to it, and so is the auditor whatever its line says: with no bound plan the dealing is not
# checked, and an auditor brief keeps today's rule there. The role is matched whole, in the
# prefixed name the harness sends and the bare word a hand-written brief uses.
#
# THE CAP COUNTS EVERY DECLARED RUN BUT FILE HOUSEKEEPING (a field report against 1.11.0; wave-27
# T49, review pass 24). It first counted only the runs the classifier (lib/cmd-class.sh
# `cmd_class`) calls a suite run, so a test runner the classifier does not know, such as
# `python -m pytest`, was recorded and counted nothing: six of them passed an auditor's cap of three.
# Every declared command counts except one that only clears or stages files, so the cleanup of a
# stale build directory is recorded and counts nothing: no `;`, `&`, `|`, backquote, `$(`, `<(`,
# `>(` or line break in it (T57), and its first WORD one of `DP_HOUSEKEEPING_WORDS`. The list lives here, once; `rm` is
# matched as a whole word, so `rmx` and `./rm` count as runs. `lift_contract_fields` applies the
# cap after its awk pass, so every door that lifts a contract — a dispatch, `amend`, `task-add` —
# counts the same way, and the refusal texts read these same functions, so the number a refusal
# prints is the number the lift applied.
DP_AUDITOR_RUNS_MAX=3
DP_SUITES_MAX=200
DP_HOUSEKEEPING_WORDS="rm rmdir mkdir touch cp mv"
# ANY `&` MAKES A RUN (wave-27 T57; review pass 35 B1). The list above named `&&` and left a lone
# `&` out, so `rm -rf dist & pytest` ran pytest and counted nothing: an evidence reader declared
# four runs and was admitted. The rule is the character, not what follows it, so a trailing
# `rm -rf dist &` is a run too; and `<(`, `>(` and a line break end housekeeping as `$(` does.
# This one predicate is the construction the dispatch wall and the `amend` door both read.
dp_run_counts() {  # <one declared run, unmarked> -> 0 when it counts against the cap, 1 when it is housekeeping
  local run="${1-}" first w
  case "$run" in *';'*|*'&'*|*'|'*|*'`'*|*'$('*|*'<('*|*'>('*|*$'\n'*) return 0 ;; esac
  run="${run#"${run%%[![:space:]]*}"}"
  first="${run%%[[:space:]]*}"
  for w in $DP_HOUSEKEEPING_WORDS; do
    [ "$first" = "$w" ] && return 1
  done
  return 0
}
# dp_counted_runs <the re_executes field, runs marked with backticks> -> how many of them count.
dp_counted_runs() {
  local rest="${1-}" run n=0
  while :; do
    case "$rest" in *'`'*'`'*) : ;; *) break ;; esac
    rest="${rest#*\`}"; run="${rest%%\`*}"; rest="${rest#*\`}"
    dp_run_counts "$run" && n=$((n + 1))
  done
  printf '%s' "$n"
}
dp_reads_evidence() {  # <subagent_type> [<questions, comma-joined>] -> 0 when the cap of three binds
  case "${1-}" in
    bionic:auditor|auditor) return 0 ;;
    bionic:critic|critic|bionic:reviewer|reviewer)
      case ",${2-}," in *,evidence,*) return 0 ;; esac ;;
  esac
  return 1
}
# dp_is_reader <subagent_type> -> 0 for the three reader roles, prefixed or bare (wave-27 T57).
dp_is_reader() {
  case "${1-}" in bionic:auditor|auditor|bionic:critic|critic|bionic:reviewer|reviewer) return 0 ;; esac
  return 1
}
dp_runs_cap() {  # <subagent_type> [<questions>] -> how many suite runs that brief's Re-executes: may declare
  if dp_reads_evidence "${1-}" "${2-}"; then printf '%s' "$DP_AUDITOR_RUNS_MAX"
  else printf '%s' "$DP_SUITES_MAX"; fi
}
# dp_runs_cap_words <subagent_type> [<questions>] -> the cap as the refusal texts say it.
dp_runs_cap_words() {
  if dp_reads_evidence "${1-}" "${2-}"; then printf 'three'
  else printf '%s' "$DP_SUITES_MAX"; fi
}
# _brief_cap_suite_runs <cap> — the lift's lines on stdin, the same lines out with the
# `re_executes=` runs past the <cap>th counted run moved to `re_executes_dropped=`. A housekeeping
# command (`dp_run_counts`) stays where the author put it and counts nothing.
_brief_cap_suite_runs() {
  local cap="$1" lines runs dropped="" kept="" n=0 rest run tok
  lines="$(cat)"
  runs="$(printf '%s\n' "$lines" | sed -n 's/^re_executes=//p' | head -1)"
  if [ -z "$runs" ]; then printf '%s\n' "$lines"; return 0; fi
  # A marked run holds no backtick (a backtick ends one), so the field splits on its marks.
  rest="$runs"
  while :; do
    case "$rest" in *'`'*'`'*) : ;; *) break ;; esac
    rest="${rest#*\`}"; run="${rest%%\`*}"; rest="${rest#*\`}"
    tok="\`${run}\`"
    if dp_run_counts "$run"; then
      n=$((n + 1))
      if [ "$n" -gt "$cap" ]; then dropped="${dropped:+$dropped }$tok"; continue; fi
    fi
    kept="${kept:+$kept }$tok"
  done
  # Through the environment, so no backslash in a run is read as an awk escape.
  printf '%s\n' "$lines" | BRIEF_KEPT="$kept" BRIEF_DROPPED="$dropped" awk '
    BEGIN { kept = ENVIRON["BRIEF_KEPT"]; dropped = ENVIRON["BRIEF_DROPPED"] }
    /^re_executes=/ { if (kept != "") print "re_executes=" kept; next }
    /^re_executes_dropped=/ { if (dropped != "") { print $0 " " dropped; dropped = "" } else print; next }
    { print }
    END { if (dropped != "") print "re_executes_dropped=" dropped }'
}

# THE RUN CAP IS APPLIED IN TWO PASSES (wave-27 T15). The awk lift bounds `Re-executes:` at
# SUITES_MAX for every brief, the row field's width. Whether the cap of three binds depends on
# the brief's own `Questions:` line, which only the lift reads, so it is applied after the awk
# pass, counting every run but housekeeping (`dp_runs_cap`, `_brief_cap_suite_runs` above).
lift_contract_fields() {  # <brief text> [<subagent_type>] -> `kind=value` lines, absent kinds omitted
  local _lifted _cap
  _lifted="$(_brief_lift_awk "$@")"
  _cap="$(dp_runs_cap "${2-}" "$(printf '%s\n' "$_lifted" | sed -n 's/^questions=//p' | head -1)")"
  if [ "$_cap" -lt "$DP_SUITES_MAX" ]; then
    printf '%s\n' "$_lifted" | _brief_cap_suite_runs "$_cap"
  elif [ -n "$_lifted" ]; then
    printf '%s\n' "$_lifted"
  fi
}
_brief_lift_awk() {  # <brief text> [<subagent_type>] -> the awk pass of the lift
  printf '%s' "$1" | \
    awk -v LEAD="$LEAD_CHARS" -v TRAIL="$TRAIL_CHARS" -v QUOTES="$QUOTE_CHARS" \
    -v RUNS_CAP="$DP_SUITES_MAX" -v SUITES_CAP="$DP_SUITES_MAX" "$CMD_RUN_NORM_AWK"'
    # <sep> is the regex between the label and its value; the default is the
    # colon every labeled brief field uses. <bol> marks a label that only counts
    # at the START of a line — see the waiver note in BEGIN.
    function addlabel(txt, kind, sep, bol) {
      NL++; LTXT[NL] = txt; LKIND[NL] = kind
      LSEP[NL] = (sep == "" ? "[ \t]*:" : sep)
      LBOL[NL] = (bol == "" ? 0 : 1)
    }
    # True iff position p is the first non-blank thing on its line. Leading
    # whitespace still counts as a line start (an indented brief field is a
    # field); anything else before it on the line does not.
    function at_line_start(p,   k, ch) {
      k = p - 1
      while (k >= 1) {
        ch = substr(lc, k, 1)
        if (ch == " " || ch == "\t") { k--; continue }
        return (ch == "\n")
      }
      return 1
    }
    function trimtok(t,   ch) {
      while (length(t) > 0) { ch = substr(t, 1, 1);         if (index(LEAD,  ch) > 0) t = substr(t, 2);                    else break }
      while (length(t) > 0) { ch = substr(t, length(t), 1); if (index(TRAIL, ch) > 0) t = substr(t, 1, length(t) - 1);     else break }
      return t
    }
    # A token carrying an unfilled `<...>` slot is a TEMPLATE, not a path. The wall
    # message hands the author a label example and briefs in this repo quote it, so a
    # slot must never lift as a real contract — nothing could ever satisfy it
    # (Step-6 review C-1, second shape). The rule lives in `ispath()`, the one
    # predicate every declared token runs through.
    #
    # WHAT FOLLOWS FROM REJECTING IT (epic-16 wave-02 R1, inference withdrawn): a
    # template is not a concrete path, so a brief whose only deliverable is a slot
    # yields nothing and the absent-deliverable wall REFUSES it, telling the author at
    # dispatch to name it exactly. Wave-02 R4 briefly filled the slot from the agent
    # name and recorded `source=inferred`; the Step-6 critic (N-1) showed that fill is
    # a GUESS enforced with a declared fact weight, so it was withdrawn — the wall
    # never guesses a deliverable, and declaring one is the cheap, robust fix.
    #
    # The unterminated form (`<name` after trimtok has eaten a trailing `>`) counts
    # as a template too. Without that clause `.bionic/tmp/<name>` passed the four
    # shape checks and lifted as a literal path — a contract with a bracket in its
    # basename, which nothing would ever satisfy.
    # The unterminated forms are counted too, in BOTH directions, because trimtok
    # runs first and its LEAD/TRAIL sets contain both brackets: `<name>` alone comes
    # out as `name`, and `<somewhere>/out.md` comes out as `somewhere>/out.md`,
    # which passes all four shape checks and would lift as a literal path with a
    # bracket in it. An orphaned bracket on either side is the residue of a slot,
    # never a filename anyone typed.
    function istemplate(t) {
      if (t ~ /<[^<>]*>/)  return 1     # a whole slot
      if (t ~ /<[^<>]*$/)  return 1     # opening bracket, closer eaten by trimtok
      if (t ~ /^[^<>]*>/)  return 1     # closing bracket, opener eaten by trimtok
      return 0
    }
    # THE SAME QUESTION ASKED OF A TOKEN THAT NEVER MET trimtok (wave-16 T25, walk §W7).
    # The two residue arms in `istemplate` are correct for the callers it has — `ispath()`
    # and `suite_names()` both trim the token first, and the LEAD/TRAIL sets trimtok carries
    # contain both brackets, so `<somewhere>/out.md` really does arrive there as
    # `somewhere>/out.md`.
    # `marked_runs()` does NOT trim: a run is taken verbatim between its marks, so those two
    # arms meet shell redirections instead of residue and used to swallow `> out`, `2>&1`
    # and `<in` as "guidance". This predicate asks the only question that is meaningful on an
    # untrimmed run: is the token NOTHING BUT a slot. Anchored, because a run that merely
    # CONTAINS one — `cmd <in >out` matches `<[^<>]*>` — is a redirection, not a placeholder,
    # and reading it as guidance is the silent drop this closes.
    function wholeslot(t) { return (t ~ /^<[^<>]*>$/) }
    function pathshaped(t) {
      if (length(t) < 3)        return 0
      if (index(t, "/") == 0)   return 0
      if (t !~ /[A-Za-z]/)      return 0
      if (substr(t, 1, 1) == "-") return 0
      return 1
    }
    function ispath(t) { return (pathshaped(t) && !istemplate(t)) }
    # THE ONE READER OF A Files: SPAN (wave-27 T29, T42; REQ-12, D21 as amended by A-orch-46).
    # The dispatch wall, `amend`, `task-add` and the stop wall remedy all read Files: here: the
    # lift for a span, and `brief_files_entry` below for one entry. Until T29 an entry was a path
    # only when it carried a `/` (`ispath`), so `Files: CONTEXT.md, a/b.ts` recorded `a/b.ts`
    # alone, in silence, and the writer was refused at its stop for editing the file its brief
    # named. Until T42 the span split on white space, so the trailing comment the scaffold
    # ships and any prose in the span were read word by word, each word refused with advice to
    # spell it `./<word>`, which then recorded the word as a path (review pass 11 F1).
    #
    # files_split <span> <arr> -> the items, in order, empties dropped. THE SPAN IS A LIST: split
    # on commas and on line ends (a list one item per line). A trailing ` # …` comment comes off
    # each line first, as `claimpat` takes it off `Subprocess claim:`, then a leading list marker
    # (`- `, `* `, `1. `), a trailing `;` and ONE surrounding pair of backticks, double quotes,
    # single quotes, parentheses or square brackets off each item (wave-27 T49; review pass 19
    # should-fix 1: `Files: "lib/a.sh"` recorded the quotes as part of the path). What is left is
    # judged as any item, so an unmatched mark stays on the item and `(("a/b"))` loses its outer
    # pair only; a pair around prose is stripped and the prose is still refused as prose.
    function strip_pair(t,   n, a, b) {
      n = length(t)
      if (n < 2) return t
      a = substr(t, 1, 1); b = substr(t, n, 1)
      if ((a == DQ && b == DQ) || (a == SQ && b == SQ) || (a == "(" && b == ")") || (a == "[" && b == "]"))
        return substr(t, 2, n - 2)
      return t
    }
    function files_split(s, arr,   nl, lines, i, j, line, np, parts, it, n) {
      n = 0
      nl = split(s, lines, "\n")
      for (i = 1; i <= nl; i++) {
        line = lines[i]
        if (match(line, /(^|[ \t])#/)) line = substr(line, 1, RSTART - 1)
        np = split(line, parts, ",")
        for (j = 1; j <= np; j++) {
          it = parts[j]
          gsub(/^[ \t\r]+|[ \t\r]+$/, "", it)
          sub(/^([-*]|[0-9]+\.)[ \t]+/, "", it)
          sub(/;+[ \t]*$/, "", it)
          if (it ~ /^`[^`]*`$/) it = substr(it, 2, length(it) - 2)
          else it = strip_pair(it)
          gsub(/^[ \t]+|[ \t]+$/, "", it)
          if (it != "") arr[++n] = it
        }
      }
      return n
    }
    # files_entry <item> -> what the item is. The answer is
    #   2  a path, stored as written: it carries a `/`, or an extension, a final dot followed by
    #      a letter-led run of letters and digits on a stem that holds a letter (`CONTEXT.md`,
    #      never `v1.2`, `1.11.0` or `.gitignore`)
    #   1  a bare word: refused, naming `./<item>`, which carries a `/` and so is read
    #   3  not a path in any spelling: an item holding white space is prose, and one ending in
    #      `.` or holding no letter or digit names no file. Refused with no spelling advice
    #   0  not an item: a one-token unfilled slot (`<paths>`), which is guidance
    # Nothing here reads the disk. The third arm T29 wrote, "names a file at the project root",
    # made two walls list the root, the fetch the hook-authoring freeze forbids; `./Makefile`
    # says the same with no listing (A-orch-46). Every other path field keeps `ispath`.
    function files_entry(t,   stem) {
      if (t ~ /[ \t]/)                       return 3
      if (istemplate(t))                     return 0
      if (t !~ /[A-Za-z0-9]/ || t ~ /\.$/)   return 3
      if (index(t, "/") > 0)                 return 2
      if (t ~ /\.[A-Za-z][A-Za-z0-9]*$/) {
        stem = t; sub(/\.[A-Za-z][A-Za-z0-9]*$/, "", stem)
        if (stem ~ /[A-Za-z]/)               return 2
      }
      return 1
    }
    # ONE COLLAPSE, TWO STRENGTHS, BOTH OUT OF payload/scripts/lib/cmd-class.sh (wave-20 T4;
    # REQ-7, D7). Every caller but one wants whitespace collapsed and nothing else — a
    # waiver reason, a claim pattern, a deliverable. The one that stores a DECLARED RUN
    # passes `run` and gets `cmdnorm_run`, the rule the writer-side budget arm builds its
    # claim with (CMD_RUN_NORM_AWK, pasted in front of this program), so the two ends of
    # the row are one rule and not two collapses that happen to agree today.
    function collapse(s, run) { return (run ? cmdnorm_run(s) : cmdnorm_ws(s)) }
    # The claimed PROCESS PATTERN out of a subprocess-claim span. Author-marked
    # first (a backticked or quoted run is unambiguous), then the punctuation the
    # sentence uses to separate the pattern from its output file.
    function claimpat(s,   i, q, a, b) {
      s = collapse(s)
      for (i = 1; i <= length(QUOTES); i++) {
        q = substr(QUOTES, i, 1)
        a = index(s, q)
        if (a == 0) continue
        b = index(substr(s, a + 1), q)
        if (b > 1) return substr(s, a + 1, b - 1)
      }
      # A TRAILING ` # ...` IS A COMMENT FROM THE SCAFFOLD, NOT THE PATTERN (wave-21 T7, D7).
      # The shipped `Subprocess claim:` line ends in one, and `pgrep -f` with the comment
      # glued on matches no process, which the P2 display reads as `live: no`.
      a = index(s, " #"); if (a > 0) s = substr(s, 1, a - 1)
      a = index(s, ",");  if (a > 0) s = substr(s, 1, a - 1)
      a = index(s, "->"); if (a > 0) s = substr(s, 1, a - 1)
      a = index(s, "→");  if (a > 0) s = substr(s, 1, a - 1)
      return collapse(s)
    }
    function firsthit(kind,   j, best) {
      best = 0
      for (j = 1; j <= nh; j++) if (HK[j] == kind && (best == 0 || HLS[j] < HLS[best])) best = j
      return best
    }
    # EVERY hit of a label, in position order, as a space-joined list of hit numbers (wave-22
    # T3, D5). The runs lift reads every `Re-executes:` span, not only the first.
    #
    # A HIT IN A CODE BLOCK IS AN EXAMPLE, NOT A DECLARATION (wave-22 T10; review 1, critic C2).
    # At base only the first hit counted, so a quoted `Re-executes:` line after the real one was
    # harmless; the union reads them all, so a line inside a ``` fence, or indented four spaces
    # or a tab (a Markdown code block), would widen the run contract with a command the author
    # only showed. The callers of firsthit are untouched.
    # A FENCE IS ``` OR ~~~, AND ONLY ITS OWN CHARACTER CLOSES IT (wave-22 T13; critic-3598752
    # I2b): a ``` line inside a ~~~ block is content of that block, as in CommonMark.
    # `fonly` (wave-27 T49): a nonzero second argument asks about a fence alone, so an indented
    # line is not a code block. The Questions: reader asks it that way, since a reader brief
    # indented whole still declares its questions.
    function in_code_block(p, fonly,   pre, n, i, ls, fence, k, w, ch, t) {
      pre = substr(lc, 1, p - 1); n = split(pre, ls, "\n"); fence = ""
      for (i = 1; i < n; i++) {
        t = ls[i]; sub(/^[ \t]*/, "", t)
        if (fence == "" && (t ~ /^```/ || t ~ /^~~~/)) fence = substr(t, 1, 3)
        else if (fence != "" && index(t, fence) == 1) fence = ""
      }
      if (fence != "") return 1
      if (fonly) return 0
      w = 0
      for (k = length(ls[n]); k >= 1; k--) {
        ch = substr(ls[n], k, 1)
        if (ch == "\t") w += 4; else if (ch == " ") w++; else return 0
      }
      return (w >= 4)
    }
    # A LABEL WHOSE EVERY HIT SITS IN A CODE BLOCK STILL DECLARES (wave-22 T13; critic-3598752 I2). A brief
    # indented whole, tab-indented, or after one unbalanced ``` line has its only real line in
    # what reads as a block; dropping it lifted no run while Files: and Suites: still lifted, and
    # the budget wall refused the declared run later. Such a label falls back (see below).
    # WHEN PARITY MEANS NOTHING, EVERY HIT COUNTS (wave-22 T15; critic-f9c2c8d N1, auditor finding,
    # A-orch-13). One stray ``` before the real line flips every later line, so a brief whose
    # fences end open cannot say which hits are examples; and a label whose every hit sits in a
    # code block (an indented contract) has no hit left to trust. Both lift the UNION of ALL
    # hits in position order, never the first alone: a first-hit fallback dropped every run
    # after the first, the silent drop REQ-2 exists to remove. ACCEPTED TRADE: in those
    # malformed shapes a fenced example lifts beside the real runs. An over-admitted run shows
    # on the roster row; a dropped real run does not. Handled by parity: A-J, N, O. Union
    # fallback: D, E, H, M, P1-P3, P5, K (a balanced fenced example as the only hit lifts, as at
    # 12574e2) and L (a fenced example before a wholly indented contract lifts beside the real run).
    function fences_unbalanced(   n, i, ls, fence, t) {
      n = split(lc, ls, "\n"); fence = ""
      for (i = 1; i <= n; i++) {
        t = ls[i]; sub(/^[ \t]*/, "", t)
        if (fence == "" && (t ~ /^```/ || t ~ /^~~~/)) fence = substr(t, 1, 3)
        else if (fence != "" && index(t, fence) == 1) fence = ""
      }
      return (fence != "")
    }
    function allhits(kind,   j, k, n, idx, t, out) {
      n = 0
      if (!fences_unbalanced())
        for (j = 1; j <= nh; j++) if (HK[j] == kind && !in_code_block(HLS[j])) idx[++n] = j
      if (n == 0)
        for (j = 1; j <= nh; j++) if (HK[j] == kind) idx[++n] = j
      for (j = 2; j <= n; j++) {
        t = idx[j]
        for (k = j - 1; k >= 1 && HLS[idx[k]] > HLS[t]; k--) idx[k + 1] = idx[k]
        idx[k + 1] = t
      }
      out = ""
      for (j = 1; j <= n; j++) out = (out == "" ? idx[j] : out " " idx[j])
      return out
    }
    # The last character index of the span belonging to hit h. `skip` names one
    # hit to IGNORE when looking for the terminator, which the cadence rule in
    # END needs: it asks where the PROGRESS span would end if the cadence label
    # were not sitting inside it, and without the skip that span would end at the
    # very label whose membership is the question. (No apostrophes in here — the
    # whole program is one single-quoted shell word.)
    # The last index within s (1-based) before the first FOLLOWING line that opens a
    # short `<Word>:` head, or 0 when no such line follows. A field ends where the next
    # one begins, and the wall must not need the label table to know that a new line
    # beginning `Evidence log:` is a different field from the one above it. Bounded to
    # three words and no punctuation before the colon, so a prose sentence that merely
    # contains a colon ("it runs in three steps: first...") is not mistaken for a head;
    # written without interval expressions, which not every awk implements.
    # THE SKIPPED HIT KEEPS ITS LINE. `skipabs` is the absolute offset of the one label
    # hit this call is pretending does not exist (the cadence rule in END asks where the
    # PROGRESS span would end if the cadence label were not inside it). The contract
    # writes `Cadence:` on a line of its own beneath `Progress:`, so bounding at that
    # line would answer the question the caller is asking with the fact it is asking
    # about, and every colon-form cadence would stop lifting.
    function labelline(s, base, skipabs,   i, j, k, line, ls, le) {
      i = 1
      while ((j = index(substr(s, i), "\n")) > 0) {
        j = i + j - 1
        k = index(substr(s, j + 1), "\n")
        line = (k > 0 ? substr(s, j + 1, k - 1) : substr(s, j + 1))
        if (line ~ /^[ \t]*[A-Za-z][A-Za-z0-9_-]*([ \t][A-Za-z0-9_-]+)?([ \t][A-Za-z0-9_-]+)?:[ \t]/) {
          ls = base + j
          le = ls + length(line) - 1
          if (!(skipabs > 0 && skipabs >= ls && skipabs <= le)) return j - 1
        }
        i = j + 1
      }
      return 0
    }
    function spanend(h, skip,   j, e, s, bl, ll) {
      e = length(text)
      for (j = 1; j <= nh; j++) if (j != skip && HLS[j] > HLS[h] && HLS[j] - 1 < e) e = HLS[j] - 1
      s = substr(text, HVS[h], e - HVS[h] + 1)
      bl = index(s, "\n\n")            # a blank line ends a field, whatever follows
      if (bl > 0) e = HVS[h] + bl - 2
      # ...and so does the next LABELLED LINE, registered label or not. Before this bound
      # a brief carrying `Evidence log: <path>` on the line after `Expected artifact:
      # <path>` put both paths in one deliverable span and was refused as ambiguous, for
      # naming exactly one deliverable and one input on lines of their own
      # (wave-bionic-1.3.2, found at dispatch). A prose continuation line has no head and
      # stays inside the span, so the R6-4 window is unchanged.
      s = substr(text, HVS[h], e - HVS[h] + 1)
      ll = labelline(s, HVS[h], (skip > 0 ? HLS[skip] : 0))
      if (ll > 0 && HVS[h] + ll - 1 < e) e = HVS[h] + ll - 1
      return e
    }
    function spanof(h) { return substr(text, HVS[h], spanend(h, 0) - HVS[h] + 1) }
    # ---- bounded field extraction (epic-16 wave-02 R1) ----
    # A field value ends at the first CLAUSE boundary, never at "the next label or a
    # blank line". That run-on reading (the old spanof value) let cadence or duration
    # swallow the prose after it. On cadence= it fed parse_seconds a value it refuses,
    # flipping a visibly-alive agent to UNMET (Step-6 review C-1/F-3); on duration= it
    # silently exempted a row from overdue notification (A-2). A sentence terminator
    # (. ? !) counts only when followed by whitespace or the end, so a period inside a
    # value is never a false boundary. A comma or a bracket ends the clause too — the
    # same restraint claimpat() already applies, and the exact shape the live specimen
    # corrupted ("2m) claims=...").
    #
    # BOTH brackets, not just the closing one (Step-6 R6 critic R6-3). With `(` absent
    # from this set a balanced parenthetical truncated mid-phrase and left the bracket
    # dangling — "~45 minutes (phase 1 only" — which hooks/session-poker.sh parse_seconds
    # refuses, because it accounts for every number and the parentheticals own digit has
    # no unit. An unreadable duration silently exempts the row from overdue notification,
    # which is A-2 read from the writer side. Ending the value at the bracket yields the
    # clean "~45 minutes" the author meant.
    function bound_field(s,   i, ch, nx, out) {
      out = ""
      i = 1
      while (i <= length(s)) {
        ch = substr(s, i, 1)
        if (ch == "\n" || ch == "\r") break
        if (ch == "," || ch == ")" || ch == "(") break
        out = out ch
        if (ch == "." || ch == "?" || ch == "!") {
          nx = substr(s, i + 1, 1)
          if (nx == "" || nx == " " || nx == "\t" || nx == "\r" || nx == "\n") break
        }
        i++
      }
      return collapse(out)
    }
    # EVERY distinct path-shaped token DECLARED under a deliverable label, in position
    # order, across the WHOLE span of the label — comma-joined, so one path is a bare
    # value and two or more is the ambiguity the caller refuses on.
    #
    # WHY NOT THE FIRST ONE (Step-6 R6 critic R6-1, plan assumption 71). R1 read the
    # FIRST SENTENCE of the label and took the FIRST path in it. That is still a guess,
    # only with a smaller window: "Expected artifact: same shape as A, written to B"
    # contracted A, and "read A first, then produce B" contracted A — the F-RD harm
    # verbatim, now recorded source=declared, so the landing gate orders the agent to
    # write A, which for that second brief means overwriting the report it was told to
    # read.
    # The extra paths in a deliverable sentence are usually INPUTS, so picking by position
    # picks the wrong file more often than the right one. Assumption 48 says the wall
    # never guesses: it declares or it refuses, and choosing among candidates is guessing.
    # So the span must yield EXACTLY ONE path, and the caller refuses on zero or on many.
    #
    # AND WHY THE WHOLE SPAN. The first-sentence bound was the R1 containment for the
    # trailing-input case; with ambiguity fatal it buys nothing and costs a false block —
    # "Expected artifact: a written report. Put it at PATH when done." named a path under
    # a canonical label and was refused for naming none (R6-4). The span is the one the
    # label owns, bounded at the next label or a blank line as every other field is.
    function span_paths(h) { return paths(spanof(h), DELIV_MAX, "") }
    # The declared deliverable: walk EVERY deliverable-kind label hit in position order
    # and return the paths of the first that yields any. Iterating (rather than taking
    # only firsthit) recovers a real labeled line that an earlier, pathless
    # deliverable-kind hit shadows — a brief quoting landing-verdict prose ("...per
    # deliverable:") ahead of its real "Expected artifact:" line. A hit that yields
    # SEVERAL paths ends the walk rather than being skipped for a cleaner later one:
    # ambiguity is a fact about the brief the author must resolve, not a hit to route
    # around. The wall never guesses a deliverable from prose (epic-16 wave-02 R1, plan
    # assumption 48); a template <slot> is not a concrete path (ispath rejects it), so a
    # brief that declares only a slot yields nothing here and the absent-deliverable wall
    # refuses it.
    #
    # EVERY HIT, NOT THE FIRST THAT ANSWERS (carry-over 14, research R3 row 35; REQ-12
    # AC-12.1). The walk used to RETURN at the first deliverable-kind hit that yielded a
    # path, so the rule was POSITION and nothing else: a brief carrying
    # `Expected artifact: a.md` and, lower down, a real `Deliverable: b.md` line was
    # contracted to whichever came first, recorded `source=declared` as though a human had
    # chosen, with the other path discarded in silence. `Expected artifact` holds no
    # precedence over `Deliverable` and never did — and the ambiguity wall could not see the
    # conflict, because each hit owns its own span and each span held exactly one path.
    #
    # SO THE PATHS OF EVERY HIT ARE UNIONED, DISTINCT, IN POSITION ORDER. Two labels naming
    # two paths now reach `deliverable_ambiguous=` exactly as one label naming two paths
    # always has: one refusal, both candidates handed back, no guess — assumption 48 applied
    # to the case where the second path is under a second label instead of beside the first.
    # The same path under both labels is ONE path and is admitted: an author who repeated
    # themselves has not created an ambiguity, and refusing that would be a wall with no
    # fault to name. A pathless hit still contributes nothing, which is what kept the
    # "...per deliverable:" prose specimen from shadowing a real labelled line.
    function decl_deliverable(   j, best, t, visited, out, seen, m, k, arr) {
      out = ""
      for (;;) {
        best = 0
        for (j = 1; j <= nh; j++) {
          if (HK[j] != "deliverable") continue
          if (visited[j]) continue
          if (best == 0 || HLS[j] < HLS[best]) best = j
        }
        if (best == 0) break
        visited[best] = 1
        t = span_paths(best)
        if (t == "") continue
        m = split(t, arr, ",")
        for (k = 1; k <= m; k++) {
          if (arr[k] == "") continue
          if (arr[k] in seen) continue
          seen[arr[k]] = 1
          out = (out == "" ? arr[k] : out "," arr[k])
        }
      }
      return out
    }
    # A waiver REASON that is the angle-bracketed slot out of the wall message,
    # copied rather than filled in. A real reason never opens with one.
    function isplaceholder(v) { return (v ~ /^<[^<>]*>/) }
    # THE SUITE BASENAMES named in a span, space-joined, in position order and
    # without duplicates — or the literal `none` when the span waives the budget.
    #
    # A SUITE IS RECOGNISED BY ITS BASENAME, never by the directory in front of it:
    # `tests/x.test.sh`, `./tests/x.test.sh` and an absolute spelling are one suite,
    # and it is the basename the derived set (`tests/lib/impact.sh | cut -f1`) prints
    # too. `run.sh` is admitted ONLY with a path component, because the bare word is
    # not a suite anywhere in this repo and briefs use it in prose constantly; the
    # same restraint payload/scripts/lib/cmd-class.sh applies to argv[0].
    #
    # THE WAIVER IS A WHOLE WORD, matched on the collapsed span rather than anywhere
    # in it: a brief reading `Suites: none` waives, and one reading
    # `Suites: tests/a.test.sh — none of the others` declares one suite and does not.
    # A CAP HIT IS LOUD (T19, A-orch-19.1). SUITES_MAX/FILES_MAX bound a ROW FIELD, not a
    # judgment, and this repo has grown past the old 60-token bound on its own suite roster —
    # so the count cap silently dropping the 61st-and-up suite reproduced the exact "your own
    # suite is off your budget" refusal T9/T18 already fixed on the CHAR side.
    #
    # THE WARNING RIDES THE SAME PIPE AS EVERY OTHER LIFTED FIELD, never awks own stderr:
    # this whole awk program is invoked under a trailing 2>/dev/null (below) so a malformed
    # brief cannot leak an awk runtime diagnostic onto the real hook stderr, and that redirect
    # would silence a print to /dev/stderr here just as thoroughly (both resolve to the SAME
    # underlying fd 2 the shell already pointed at /dev/null). Printing a `<kind>_capwarn=`
    # line instead puts it on stdout, where the bash side field_of and warn() -- the same
    # path the ABSENT-field warning already uses -- carry it to the real stderr untouched.
    function suite_names(s,   nl, lines, li, n, arr, i, t, b, out, seen, c, dropped, baddrop, cmt, real) {
      nl = split(s, lines, /\n/); out = ""; c = 0; dropped = ""; baddrop = ""; cmt = 0; real = 0
      for (li = 1; li <= nl; li++) {
      n = split(lines[li], arr, /[ \t\r]+/)
      for (i = 1; i <= n; i++) {
        t = trimtok(arr[i])
        # A COMMENT ENDS ITS OWN LINE (T23, Step-6 review R1; line-scoped by T35, critic C8).
        # The brief scaffold this repo ships reads `Suites: none    # *.test.sh names or a
        # path-qualified run.sh; other runners: Re-executes:`, and an author who fills that
        # scaffold in keeps the comment.
        # Every word after the `#` is a whitespace-separated token like any other, so the drop
        # refusal below scored `#`, `read-only` and `brief;` as suites the shell runner cannot
        # run and refused briefs the base admitted — with a message pointing at `Re-executes:`
        # that never mentioned the comment, so the repair was not discoverable from it. `#`
        # STOPS THE SCAN rather than being skipped: skipping would let a word inside prose
        # ("# see tests/other.test.sh") lift onto the row as a budget entry its author never
        # declared, and the writer-side guard would then hold the agent to it.
        #
        # WHAT IT STOPS IS THE LINE, NOT THE SPAN. A span is `spanof()`: everything up to the
        # next labelled line or the next blank one, so a roster wrapped across lines is ONE
        # span and a comment on its first line used to discard every suite declared below —
        # silently, no `suites_dropped=`, nothing on the row, the loud drop arm turned into a
        # quiet budget cut (critic C8). A comment runs to end of LINE, which is what `#` means
        # everywhere else a shell reader meets it; the scan resumes at the next line, and a
        # comment that opens a continuation line contributes nothing from that line alone.
        if (substr(t, 1, 1) == "#") break
        if (t == "" || istemplate(t)) continue
        # SOMETHING REAL WAS READ. Recorded for the all-comment case below, and set here —
        # before the shape filters — because an unexpanded name and a dropped token are both
        # declarations the author made, however the arms downstream answer them.
        real = 1
        # AN UNEXPANDED NAME IS NOT A SUITE, AND NOW SAYS SO HERE (REQ-1 AC-1.4, ADR-029).
        # The refusal prose at the suite-allowance wall has promised "one path per token, no
        # shell variables" since wave-01, and nothing at dispatch enforced it: `istemplate`
        # rejects `<slot>` forms only, so `tests/$X.test.sh` was basenamed to `$X.test.sh`,
        # matched the filter and lifted onto the row as a budget entry no command could ever
        # equal. The run-time twin already exists and already says why
        # (payload/scripts/lib/walls.sh budget_refuse: "unexpanded name; allowed: …"), so
        # this is the same rule read at the moment the author can still fix it. A bare `$`
        # (a regex anchor inside a quoted pattern) is not a variable — the token must be a
        # `$` followed by a name character or a brace.
        if (t ~ /[$][A-Za-z_{]/) { print "suites_bad=" t; continue }
        b = t; sub(/.*\//, "", b)
        if (b !~ /\.test\.sh$/ && !(b == "run.sh" && index(t, "/") > 0)) {
          # A DROPPED TOKEN IS NOW A REFUSAL (T3, REQ-8; wave-17, research R3 §C1.4 option 3
          # — a repair of THIS existing check, no new I/O, D11-compliant). Until now a token
          # whose basename was neither `*.test.sh` nor a path-qualified `run.sh` — a jest
          # spec, a pytest module, a bare `run.sh` — fell off in total silence: `suites=`
          # ended up empty, and the brief then met the UNRELATED no-instrument arm below for
          # "declaring no Files: and no Suites:", forty minutes before the writer-side guard
          # refused the exact command the brief had named. `none` is the waiver (checked
          # below, on the collapsed whole span) and is never a drop.
          if (tolower(b) != "none") { baddrop = (baddrop == "" ? t : baddrop " " t) }
          continue
        }
        if (seen[b]) continue
        seen[b] = 1
        if (c < SUITES_MAX) { out = (out == "" ? b : out " " b); c++ }
        else { dropped = (dropped == "" ? b : dropped " " b) }
      }
      # The inner loop LEFT EARLY iff it met a `#`, and `i` holds that token index.
      if (i <= n) cmt = 1
      }
      if (dropped != "") {
        print "suites_capwarn=Suites: line exceeds the " SUITES_MAX "-suite cap — dropped: " dropped
      }
      if (baddrop != "") { print "suites_dropped=" baddrop }
      if (out != "") return out
      if (tolower(collapse(s)) ~ /^none([^a-z0-9]|$)/) return "none"
      # A SPAN THAT IS ALL COMMENT DECLARED A LABEL AND NOTHING ELSE (critic C9). It lifts
      # no suites, no drop and no waiver, so all four guards of the no-instrument arm read
      # empty and the brief is refused for "declaring no Files: and no Suites:" — of a brief
      # that declares `Suites:` in as many words, the self-refuting shape C3 was fixed for.
      # The refusal is right (there is no budget for the row to carry) and stays where it is;
      # this fact is what lets its DETAIL say which of the two things happened.
      if (cmt && !real) { print "suites_commented=1" }
      return ""
    }
    # THE AUTHOR-MARKED RUNS on a `Re-executes:` span — each backtick-delimited command, in
    # position order, marks KEPT, space-joined, at most RUNS_MAX of them.
    #
    # WHY THE AUTHOR MARKS THEM (D3; research R1 open question 2). A run holds spaces, and
    # commas, and quotes, so token-splitting is wrong and any punctuation separator is
    # ambiguous with a command that contains it. `claimpat()` above already prefers an
    # author-marked run for exactly this reason; this is that precedent applied to a list.
    # Text OUTSIDE the marks is not a run — a brief that writes prose on the span has
    # declared nothing, which is the honest reading and the one the cap can bound.
    #
    # THE MARKS STAY ON THE VALUE. The roster field is what the writer-side budget arm
    # compares a real command against, and "the exact marked run" is only a thing to compare
    # when the row still carries the marks. It also makes the field self-delimiting: a
    # backtick cannot occur inside a run, because a backtick is what ends one.
    #
    # FIVE REFUSALS AT THE LIFT, each naming the token (REQ-1 AC-1.4, ADR-029; wave-16 T25;
    # wave-21 T7). An UNQUOTED `|` is shell plumbing, and plumbing is not one run; a newline
    # means the marks never closed on their own line; an unexpanded `$name` is a budget entry
    # no command can equal (see the same rule on the `Suites:` span above); a `<name>` glued
    # to a neighbour is an unfilled placeholder, the same budget entry by another spelling;
    # and any other angle bracket that is not a whole slot is a shell redirection, which used
    # to be dropped in silence. The refusal is made on the bash side — this prints the fact.
    #
    # THE PIPE TEST READS QUOTES (T4, REQ-7, D4). It was `index(tok, "|") > 0`, a whole-token
    # scan, so a quoted regex alternation — the ordinary way a jest repository names two
    # suites with --testPathPattern — was refused as plumbing, and its author was told to
    # leave the shell plumbing off the span about a character that was never plumbing. The
    # spelling cannot be shown in this comment: the whole awk program is one single-quoted
    # shell word. tests/dispatch-preflight.test.sh 18T4a carries it. The delimiter problem
    # that reading was defending against is solved where it lives, in the row
    # (`payload/scripts/lib/roster.sh` escapes the field), not by refusing the command.
    #
    # A CAP HIT IS A REFUSAL, NOT A WARNING (T5, REQ-8, D12). The bad-token drop on
    # `suite_names()` above (`suites_dropped=`, two screens up) is the precedent this
    # follows, not its own cap-warn sibling: a run dropped here is a run the author
    # declared and the writer-side budget arm would then refuse at run time, 40 minutes
    # later, for a reason the author was never told at dispatch — so admitting the
    # dispatch with three of the four runs on the roster is the same hole `suites_dropped=`
    # closed for `Suites:`, reopened for `Re-executes:`. `RUNS_MAX` (3) is unchanged; it is
    # the ceiling on the declaration, never a bound the field silently narrows to.
    # WHETHER A TOKEN CARRIES A PIPE THE SHELL WOULD READ AS PLUMBING (T4; REQ-7, D4).
    #
    # THE STATE MACHINE IS THE ONE THE SHELL USES, minus what a `|` cannot escape into: a single
    # quote ends only at the next single quote, a double quote only at the next double
    # quote, and outside both a backslash protects the character after it. A `|` met while
    # any of those hold is a literal character in an argument — a regex alternation, a
    # bracket expression, an awk program — and a run carrying one is still one run.
    #
    # AN UNBALANCED QUOTE ADMITS THE REST OF THE TOKEN, and that is the honest answer rather
    # than a hole: a command whose quote never closes is a shell SYNTAX error, so the pipe
    # inside it can never run as plumbing either. Refusing it here would invent a sixth
    # fault word for a brief whose real fault the shell will name the moment it is typed.
    #
    # THE QUOTE CHARACTERS ARE READ OFF `QUOTES`, never spelled, for the reason the BEGIN
    # block records beside `BT`: this whole program is one single-quoted shell word, so a
    # bare apostrophe anywhere in it — even in a comment — ends the word before awk sees it.
    function unquoted_pipe(t,   n, k, ch, q) {
      n = length(t); q = ""
      for (k = 1; k <= n; k++) {
        ch = substr(t, k, 1)
        if (q != "") { if (ch == q) q = ""; continue }
        if (ch == BS) { k++; continue }
        if (ch == SQ || ch == DQ) { q = ch; continue }
        if (ch == "|") return 1
      }
      return 0
    }
    # THE FIRST `<name>` IN A RUN THAT TOUCHES A NEIGHBOUR, or "" (wave-21 T7; REQ-6, D6).
    # A name in brackets with a non-space character on either side is a slot an author
    # forgot to fill — `jobs/<id>/logs`, `<ver>.tar.gz` — and no shell spelling of a
    # redirection puts a bare word in brackets against a path. A name standing alone between
    # spaces is not judged here: the shell reads that shape as two redirections, and the
    # redirect test below keeps it.
    function glued_slot(t,   rest, off, a, b, pre, post) {
      rest = t; off = 0
      while (match(rest, /<[A-Za-z_][A-Za-z0-9_-]*>/)) {
        a = off + RSTART; b = a + RLENGTH - 1
        pre  = (a > 1)         ? substr(t, a - 1, 1) : " "
        post = (b < length(t)) ? substr(t, b + 1, 1) : " "
        if (pre !~ /[ \t]/ || post !~ /[ \t]/) return substr(t, a, RLENGTH)
        off = b; rest = substr(t, b + 1)
      }
      return ""
    }
    function marked_runs(s,   i, j, tok, out, c, dropped, why) {
      # THE UNION OF SEVERAL SPANS (wave-22 T3, D5). The caller resets MRprev, MRc, MRout and
      # MRdropped once per brief; a run an EARLIER span already carried is skipped, first-seen
      # order kept, and the cap counts the union. One span behaves as it always did.
      out = MRout; c = MRc; dropped = MRdropped
      i = 1
      for (;;) {
        j = index(substr(s, i), BT)
        if (j == 0) break
        i = i + j                              # first character after the opening mark
        j = index(substr(s, i), BT)
        if (j == 0) break                      # an unclosed mark is not a run
        tok = substr(s, i, j - 1)
        i = i + j                              # first character after the closing mark
        why = ""
        if (index(tok, "\n") > 0)       why = "a newline"
        else if (unquoted_pipe(tok))    why = "a pipe"
        else if (tok ~ /[$][A-Za-z_{]/) why = "an unexpanded shell variable"
        if (why != "") { print "re_executes_bad=" why ": " collapse(tok); continue }
        tok = collapse(tok)
        # A TEMPLATE LIFTS NOTHING (epic-23 wave-16 T20; walk finding 1). The brief scaffold
        # carries its own guidance line, `` Re-executes: `<cmd>` ``, an unfilled slot —
        # the identical shape `istemplate()` already rejects on the `Files:` and `Suites:`
        # readers (`ispath()` and `suite_names()` both call it). Without this check a brief
        # that pasted the scaffold unfilled satisfied the suite-allowance wall on a budget
        # entry no real command could ever equal, and `dp_scaffold_marked` read the
        # placeholder as a real declaration and left the whole instrument triple unmarked. A
        # template is silently skipped here exactly as on the other two readers, never a
        # `re_executes_bad` fault: the author wrote guidance, not a mistake.
        #
        # A WHOLE SLOT ONLY (wave-16 T25, walk §W7). Anything else carrying a bracket is a
        # redirection and is REFUSED with the token named, the same way `|` and `$name` are
        # one and two lines up — it used to `continue` here, and the dispatch was admitted
        # with an empty or truncated `re_executes=` that the writer-side budget arm then
        # refused at run time as undeclared, 40 minutes after the author could have fixed it.
        if (tok == "" || wholeslot(tok)) continue
        # A PLACEHOLDER BEFORE A REDIRECTION (wave-21 T7; REQ-6, D6; triage-B §3). The
        # bracket test below read `gh api repos/o/r/actions/jobs/<id>/logs` as a
        # redirection, and its author rewrote a correct command looking for one. The run
        # is still refused — `<id>` is a budget entry no typed command can equal, the
        # `$name` rule — but under the fault it has. A run carrying both is told the
        # placeholder first; filling it leaves the redirection to be named on the retry.
        if (glued_slot(tok) != "") { print "re_executes_bad=an unfilled placeholder: " tok; continue }
        if (tok ~ /[<>]/) { print "re_executes_bad=a redirection: " tok; continue }
        # STORED THROUGH THE ONE RUN RULE (wave-20 T4; REQ-7, D7). The refusals above run
        # first and on the text as written — a declaration naming a redirection is still told
        # so (16ld3, Chris D14) — so what reaches here carries no redirection, no unquoted
        # pipe, and this is the identity today. It is here so the rule that builds the claim
        # is, by construction, the rule that built the declaration.
        tok = collapse(tok, 1)
        if ((tok in MRprev) && MRprev[tok] != MRspan) continue
        MRprev[tok] = MRspan
        if (c < RUNS_MAX) {
          out = (out == "" ? BT tok BT : out " " BT tok BT)
          c++
        } else {
          dropped = (dropped == "" ? BT tok BT : dropped " " BT tok BT)
        }
      }
      # NAMED, NOT WARNED (T5, REQ-8, D12): `re_executes_dropped=` reaches the same refusal
      # channel `suites_dropped=` does — read by the bash side below, which turns a non-empty
      # value into a `dp_finding` — never `warn()`, which is the several-fault ADMIT wire the
      # old `re_executes_capwarn=` field used.
      MRout = out; MRc = c; MRdropped = dropped
      return out
    }
    # <files> set: the span is a Files: span, split into items by `files_split` and read item by
    # item by `files_entry`. `none` alone is no files. A bare word prints as `files_unread=`
    # (space-joined) and an item that is no path in any spelling as `files_bad=` (comma-joined,
    # since an item holds no comma), for `brief_validate_fields` to refuse.
    function paths(s, maxn, warnlabel, files,   n, arr, i, t, k, out, seen, c, dropped, unread, bad) {
      out = ""; c = 0; dropped = ""; unread = ""; bad = ""
      if (files) {
        n = files_split(s, arr)
        if (n == 1 && tolower(arr[1]) == "none") return ""
      } else n = split(s, arr, /[ \t\r\n]+/)
      for (i = 1; i <= n; i++) {
        t = (files ? arr[i] : trimtok(arr[i]))
        k = (files ? files_entry(t) : 2 * ispath(t))
        if (k == 0 || seen[t]) continue
        seen[t] = 1
        if (k == 1) { unread = (unread == "" ? t : unread " " t); continue }
        if (k == 3) { bad = (bad == "" ? t : bad "," t); continue }
        if (c < maxn) { out = (out == "" ? t : out "," t); c++ }
        else if (warnlabel != "") { dropped = (dropped == "" ? t : dropped " " t) }
      }
      if (warnlabel != "" && dropped != "") {
        print "files_capwarn=" warnlabel " line exceeds the " maxn "-path cap — dropped: " dropped
      }
      if (unread != "") print "files_unread=" unread
      if (bad != "") print "files_bad=" bad
      return out
    }
    BEGIN {
      NL = 0
      # How many candidate paths a deliverable span reports before it stops counting.
      # One is the contract; anything above one is refused, and the number only has to
      # be large enough for the refusal to show the author what it saw.
      DELIV_MAX = 12
      # How many paths a `Files:` span reports and how many basenames a `Suites:`
      # span reports. Both are bounds on a ROW FIELD, not on a judgment: the row is
      # one line the fleet parses by key, and a brief that names a hundred files has
      # a problem the wall cannot fix.
      #
      # RAISED 60 -> 200 (T19, A-orch-19.1): the old 60-token bound silently dropped the
      # 61st-and-up suite of a real budget — this repo carries 70+ suites of its own, so 60
      # was already narrower than the whole roster with no headroom left. 200 holds the
      # whole roster with room to grow, and hitting IT is loud: see warncap() below, never a
      # silent exit 0.
      FILES_MAX = 200
      SUITES_MAX = SUITES_CAP + 0
      # HOW MANY RUNS A `Re-executes:` SPAN DECLARES (D3; REQ-1 AC-1.6; wave-20 T4, Δ3, Δ9).
      # Here, SUITES_MAX for every brief. The cap of three a reader of the evidence question is
      # held to (payload/context/checks-evidence.md, "cap 3 total") is applied on the bash side
      # after this pass, counting all but housekeeping (`dp_runs_cap`, wave-27 T49). Either way it is
      # the ceiling of the declaration itself, not only the width of a row field, so hitting it
      # is a fact about the brief, and loud: see marked_runs() above. A caller that passes no
      # cap gets SUITES_MAX, never an unbounded lift.
      RUNS_MAX = RUNS_CAP + 0
      if (RUNS_MAX <= 0) RUNS_MAX = SUITES_MAX
      # THE MARK THE AUTHOR WRITES, NAMED RATHER THAN SPELT. This whole program is one single-quoted
      # shell word, so a backtick literal inside it would be one more character the shell
      # reads before awk does; `QUOTE_CHARS` is assembled above this function with the
      # backtick first, for claimpat(), and this is the same character read off the same
      # source.
      BT = substr(QUOTES, 1, 1)
      # THE OTHER TWO, off the same source and for the same reason (T4). `QUOTE_CHARS` is
      # assembled backtick, double quote, single quote — the order claimpat() reads it in.
      # `BS` is a single backslash: in an awk string literal it is written doubled.
      DQ = substr(QUOTES, 2, 1)
      SQ = substr(QUOTES, 3, 1)
      BS = "\\"
      # LONGEST FIRST — see the nesting note above. `-` marks a label that only
      # BOUNDS a span; it is a real brief field, just not one the roster lifts.
      #
      # `input` is a second non-lifting kind. Since inference was withdrawn (R1) it
      # bounds spans exactly as `-` does — no prose path is ever lifted, and `read first`
      # / `scope constraint` are not deliverable labels, so a path under one of them is
      # out of every deliverable span and cannot become the contract. The kind is kept
      # distinct only to keep these two headings legible as inputs; nothing reads it.
      #
      # THE STATEMENT THIS COMMENT USED TO MAKE — "a path a brief tells the agent to read
      # is never taken as the deliverable" — was false while R1 shipped, and is now true
      # for a different reason than it claimed (R6 critic R6-1). An input named INSIDE the
      # deliverable label span is not out of reach of the extractor; what saves it is that
      # a span holding two paths refuses the dispatch instead of picking one. The fix for
      # such a brief is to move the reference out to its own line, which is what these
      # input headings are for and what the ambiguity refusal tells the author to do.
      #
      # `deliverable-waiver` heads the table because it is the longest label AND
      # because it nests the shortest-but-one: a brief line reading
      # `Deliverable-waiver: <reason>` must never lift as a `deliverable`. The
      # separator rule already keeps them apart (`deliverable` requires a colon,
      # and the next character here is a hyphen), but the ordering makes the
      # intent structural rather than incidental.
      #
      # It is also pinned to LINE START, and — since final-audit A-1 — so are the
      # six deliverable-kind labels below (expected artifact(s), deliverable(s),
      # artifact(s)). It is the only label that OPENS a wall rather than filling
      # a field, and briefs in this repo quote the wall message that names it
      # constantly — so a mid-sentence occurrence is documentation, not a
      # declaration (Step-6 review S-1: one quoted line silenced the landing
      # contract for the whole dispatch).
      #
      # THE SAME HAZARD REACHES THE DELIVERABLE LABELS (final-audit A-1,
      # record/w2-r7-audit.md). Every refusal this wall prints recommends the
      # same concrete, copy-paste example — Expected artifact:
      # .bionic/docs/record/my-task-notes.md — and a brief that quotes that
      # line in prose ahead of its real, later label puts each occurrence in its
      # OWN span, one path apiece, so the ambiguity wall below never sees two
      # paths in one span. decl_deliverable() then takes the FIRST hit that
      # yields any path and silently contracts the agent to a file it will never
      # write, recorded source=declared as though a human named it — the one
      # shape that routes around the ambiguity wall entirely. Pinning the six
      # deliverable-kind spellings to line start closes it the same way S-1
      # closed it for the waiver: a mid-sentence occurrence never becomes a hit.
      #
      # THE REMAINING LABELS ARE DELIBERATELY LEFT UNPINNED (cadence, duration,
      # progress, subprocess claim). None of them is quoted as a copy-paste
      # example in any wall message, so the bait mechanism above does not reach
      # them. cadence is also POSITIONAL by design (S10L) — it is meant to sit
      # mid-sentence inside the progress span (Progress: PATH, cadence ~5m), and
      # pinning it to line start would break that grammar outright. A wrong
      # duration or progress value is a misread number or path the watcher acts
      # on; a wrong deliverable is a file-write contract the landing gate later
      # enforces by ordering the agent to overwrite whatever it names. The harms
      # are not the same size, and the fix is scoped to the one that is.
      addlabel("deliverable-waiver", "waiver", "", 1)
      addlabel("subprocess claims", "claims")
      addlabel("subprocess claim",  "claims")
      addlabel("expected artifacts", "deliverable", "", 1)
      addlabel("expected artifact",  "deliverable", "", 1)
      addlabel("progress artifact",  "progress")
      # THE DONE MARKER (wave-24 T9, D3): an optional path the agent writes when it is done,
      # one of the completion signals the landing verdict reads. Pinned to line start like the
      # deliverable labels: a marker is a path the verdict judges, so a prose mention of one
      # must not declare it.
      addlabel("done marker",        "done", "", 1)
      addlabel("expected duration",  "duration")
      addlabel("scope constraint",   "input")
      addlabel("exit condition",     "-")
      addlabel("progress path",      "progress")
      addlabel("deliverables",       "deliverable", "", 1)
      addlabel("current step",       "-")
      addlabel("deliverable",        "deliverable", "", 1)
      addlabel("constraints",        "-")
      addlabel("your task",         "-")
      addlabel("read first",         "input")
      addlabel("artifacts",          "deliverable", "", 1)
      addlabel("artifact",           "deliverable", "", 1)
      addlabel("progress",           "progress")
      addlabel("duration",           "duration")
      addlabel("cadence",            "cadence", "([ \t]*:|[ \t])[ \t]*")
      # THE TWO INSTRUMENT LABELS (wave-01 S13, spec AC-20), BOTH PINNED TO LINE
      # START. `Files:` declares the intent — what this task will touch — and
      # `Suites:` declares the consequence directly, for a repository where no
      # impact command is configured. Both are pinned for the reason the six
      # deliverable-kind labels are: every refusal below quotes them back as a
      # copy-paste example, and a brief that repeats the example mid-sentence has
      # documented the wall, not declared a field.
      # THE THIRD INSTRUMENT LABEL (epic-23 wave-16, REQ-1, D1, ADR-029), PINNED TO LINE
      # START like the other two and for the same reason: the refusals below quote it back as
      # a copy-paste example. `Files:` declares intent and `Suites:` the shell-suite
      # consequence; `Re-executes:` declares the consequence for every OTHER runner — jest,
      # pytest, go test, a live read — which had no spelling at all until now, so a brief in
      # such a repository could declare nothing true and the walls held nothing (research R1
      # section 9.1). It sits above `suites` because the table runs longest label first.
      addlabel("re-executes",        "runs",   "", 1)
      # THE QUESTIONS OF A READER (wave-27 T15; REQ-5, D5), pinned to line start: the line is
      # `Questions: <q>[, <q>]` on a line of its own, and the refusals quote it back.
      addlabel("questions",          "questions", "", 1)
      # A DECLARED DEBT (wave-27 T31; REQ-14, D23), pinned to line start like the questions:
      # `Lands-red: <suite> until <token>` and `Red-evidence: <path under record/>`, each on a
      # line of its own. The longer label first, as the table runs.
      addlabel("red-evidence",       "red_evidence", "", 1)
      addlabel("lands-red",          "lands_red", "", 1)
      addlabel("suites",             "suites", "", 1)
      addlabel("files",              "files",  "", 1)
      addlabel("scope",              "-")
      addlabel("model",              "-")
      addlabel("exit",               "-")
    }
    { text = text $0 "\n" }
    END {
      lc = tolower(text); nh = 0
      for (i = 1; i <= NL; i++) {
        lab = LTXT[i]; from = 1
        while (from <= length(lc)) {
          rest = substr(lc, from)
          if (match(rest, "(^|[^a-z])" lab LSEP[i]) == 0) break
          p = from + RSTART - 1
          vend = p + RLENGTH                                  # first char AFTER the colon
          ls = p
          if (substr(lc, ls, length(lab)) != lab) ls = p + 1  # the guard char matched too
          from = vend
          if (LBOL[i] && !at_line_start(ls)) continue
          clash = 0
          for (j = 1; j <= nh; j++) if (ls <= HVS[j] - 1 && vend - 1 >= HLS[j]) { clash = 1; break }
          if (clash) continue
          nh++; HLS[nh] = ls; HVS[nh] = vend; HK[nh] = LKIND[i]
        }
      }
      # THE DELIVERABLE — declared only, and EXACTLY ONE (epic-16 wave-02 R1 + R7, plan
      # assumptions 48 and 71). The wall never guesses a deliverable: not from prose, and
      # not from among the paths a declared label happens to contain. decl_deliverable()
      # walks every deliverable-kind label hit and returns the paths of the first that
      # yields any; iterating (rather than stopping at firsthit) recovers a real labeled
      # line an earlier pathless deliverable-kind hit shadows — the "...per deliverable:"
      # live specimen.
      #
      # TWO FIELDS OUT, NEVER BOTH. A single path is the contract and prints as
      # `deliverable=`. Several is an ambiguity no reader downstream could detect once a
      # winner was picked (the row would say `declared` either way), so it prints as
      # `deliverable_ambiguous=` — a value nothing lifts onto a row, read by one wall
      # below that refuses the dispatch and hands the author back every candidate. A brief
      # that declares no concrete path prints neither, and the absent-deliverable wall
      # refuses that instead. There is no inference rung and no template fill: a guessed
      # fact is a not-fact, and the whole point of the wall is that it holds only stated
      # facts.
      v = decl_deliverable()
      if (v != "") {
        if (index(v, ",") > 0) print "deliverable_ambiguous=" v
        else                   print "deliverable=" v
      }
      # Duration lifts a BOUNDED value, never a run-on span (Step-6 review C-1/F-3 +
      # A-2): the value ends at its first clause boundary. See bound_field().
      h = firsthit("duration");    if (h > 0) { v = bound_field(spanof(h));    if (v != "") print "duration=" v }
      # The progress path is the first path in its label span. Advisory only — an
      # absent one warns — so a templated or missing progress path lifts nothing and is
      # warned, never filled (the deliverable rule applied to the field with no wall).
      h = firsthit("progress")
      if (h > 0) { v = paths(spanof(h), 1, ""); if (v != "") print "progress=" v }
      # The Done marker is the first path in its span, as the progress path is; a slot lifts
      # nothing (ispath), so the scaffold line pasted unfilled declares no marker.
      h = firsthit("done")
      if (h > 0) { v = paths(spanof(h), 1, ""); if (v != "") print "done=" v }
      # CADENCE IS POSITIONAL, not merely lexical (Step-6 critic F-2). It is the one
      # label with a relaxed separator — whitespace will do, because the contract writes
      # it inside the progress sentence rather than on a line of its own — and that
      # relaxation made every prose occurrence of the word a declaration. So the hit
      # must fall where the contract puts it: after the progress label, inside the span
      # that label owns. The value is bounded, so a run-on ("cadence 2m) claims=...", the
      # live specimen) lifts the duration token alone and never corrupts the field.
      h = firsthit("cadence")
      if (h > 0) {
        ph = firsthit("progress")
        if (ph > 0 && HLS[h] > HLS[ph] && HLS[h] <= spanend(ph, h)) {
          v = bound_field(spanof(h)); if (v != "") print "cadence=" v
        }
      }
      # AN UNFILLED SLOT CLAIMS NOTHING (wave-21 T7, D7): the line the scaffold ships,
      # `Subprocess claim: <process pattern>`, pasted as shipped, is guidance — the same
      # rule the waiver below applies to `<reason>`.
      h = firsthit("claims")
      if (h > 0) { v = claimpat(spanof(h)); if (v != "" && !isplaceholder(v)) print "claims=" v }
      # The waiver is free text — a REASON, never a path — so it lifts collapsed
      # and whole, ending where the next labelled field begins. An EMPTY value is
      # not printed, which is the whole of the "a reasonless waiver is not a
      # waiver" rule: the wall below reads presence, and presence means a reason.
      # A PLACEHOLDER value is not printed for the same reason read one step
      # further: the wall message hands the author a slot to fill, and a brief
      # that quotes the slot back unfilled has given no reason at all (S-1).
      h = firsthit("waiver")
      if (h > 0) { v = collapse(spanof(h)); if (v != "" && !isplaceholder(v)) print "waiver=" v }
      # THE FILES THE TASK DECLARES IT WILL TOUCH — every distinct path-shaped
      # token in the span, comma-joined, exactly as the deliverable label lifts
      # its candidates. Several paths is the ORDINARY case here rather than an
      # ambiguity: a task touches a set, and the wall does not have to choose
      # among them, it hands the whole set to the impact command.
      h = firsthit("files")
      if (h > 0) { v = paths(spanof(h), FILES_MAX, "Files:", 1); if (v != "") print "files=" v }
      # THE SUITES THE BRIEF DECLARES, NORMALISED TO BASENAMES at the moment they
      # are lifted, so the declared spelling and the derived one are the same
      # spelling on the row and the writer-side guard compares one alphabet. The
      # explicit waiver `Suites: none` lifts as the literal token `none`, which is
      # a DECLARED empty set — distinguishable on the row from a brief that stated
      # no budget at all, and refused by the guard for every suite.
      h = firsthit("suites")
      if (h > 0) { v = suite_names(spanof(h)); if (v != "") print "suites=" v }
      # THE QUESTIONS A READER BRIEF NAMES (wave-27 T15; REQ-5, D5): a SET, read off the line the
      # label opens, split on commas and blanks, so order and spacing do not matter. It prints in
      # the one order the row and the recorder use, evidence, adversarial, structure, and a word
      # outside the three prints as `questions_bad=` for the dispatch wall to refuse by name. An
      # unfilled slot is guidance and declares nothing. Which roles must carry it, and the set
      # each may carry, the dispatch wall judges; the lift only reads.
      #
      # THE LABEL IS READ AS THE OTHER LABELS ARE (wave-27 T49; review pass 24): a Questions: line
      # inside a fenced block is an example and not the label, so a brief whose only line is fenced
      # has none (while the fences are unbalanced no line can be told from an example, and every
      # line counts, as for Re-executes:); a trailing ` # ...` comment comes off the line, as on
      # Files:; and the label is given ONCE. A second line is not read: it prints its line number
      # beside the first as `questions_dup=` for the dispatch wall to refuse by name.
      nqh = 0; split("", QH)
      for (j = 1; j <= nh; j++)
        if (HK[j] == "questions" && (fences_unbalanced() || !in_code_block(HLS[j], 1))) QH[++nqh] = j
      h = (nqh > 0 ? QH[1] : 0)
      if (nqh > 1) {
        qdup = ""
        for (j = 1; j <= nqh; j++) {
          v = substr(text, 1, HLS[QH[j]] - 1)
          qdup = (qdup == "" ? "" : qdup " ") (gsub(/\n/, "\n", v) + 1)
        }
        print "questions_dup=" qdup
      }
      if (h > 0) {
        v = spanof(h); k = index(v, "\n"); if (k > 0) v = substr(v, 1, k - 1)
        if (match(v, /(^|[ \t])#/)) v = substr(v, 1, RSTART - 1)
        nq = split(tolower(v), QW, /[ \t\r,]+/); qbad = ""; split("", QS)
        for (i = 1; i <= nq; i++) {
          if (istemplate(QW[i])) continue
          t = trimtok(QW[i]); if (t == "" || istemplate(t)) continue
          if (t == "evidence" || t == "adversarial" || t == "structure") QS[t] = 1
          else if (index(" " qbad " ", " " t " ") == 0) qbad = (qbad == "" ? t : qbad " " t)
        }
        v = ""
        if ("evidence" in QS)    v = "evidence"
        if ("adversarial" in QS) v = (v == "" ? "" : v ",") "adversarial"
        if ("structure" in QS)   v = (v == "" ? "" : v ",") "structure"
        if (v != "") print "questions=" v
        if (qbad != "") print "questions_bad=" qbad
      }
      # THE DECLARED DEBT (wave-27 T31; REQ-14, D23): the rest of the line each label opens, blanks
      # folded; `Red-evidence:` is its first word. The dispatch wall judges the shape; the lift only
      # reads, and an unfilled scaffold slot declares nothing. A trailing ` # ...` comment comes off
      # the line, as on Questions: and Files:, so the scaffold line filled with its comment kept, or
      # left with only its comment, declares only what precedes the comment.
      h = firsthit("lands_red")
      if (h > 0) {
        v = spanof(h); k = index(v, "\n"); if (k > 0) v = substr(v, 1, k - 1)
        if (match(v, /(^|[ \t])#/)) v = substr(v, 1, RSTART - 1)
        gsub(/[ \t\r]+/, " ", v); sub(/^ /, "", v); sub(/ $/, "", v)
        if (v != "" && !istemplate(v)) print "lands_red=" v
      }
      # ONE DECLARATION (wave-27 T67; review pass 46 N2): the lift reads the first line, so a second
      # filled Lands-red: line would be dropped without a word. Their count prints as `lands_red_n=`
      # for the dispatch wall to refuse; an unfilled scaffold slot or an example is not counted.
      nlr = split(allhits("lands_red"), LRH, " "); clr = 0
      for (j = 1; j <= nlr; j++) {
        v = spanof(LRH[j]); k = index(v, "\n"); if (k > 0) v = substr(v, 1, k - 1)
        if (match(v, /(^|[ \t])#/)) v = substr(v, 1, RSTART - 1)
        gsub(/[ \t\r]+/, " ", v); sub(/^ /, "", v); sub(/ $/, "", v)
        if (v != "" && !istemplate(v)) clr++
      }
      if (clr > 1) print "lands_red_n=" clr
      h = firsthit("red_evidence")
      if (h > 0) {
        v = spanof(h); k = index(v, "\n"); if (k > 0) v = substr(v, 1, k - 1)
        if (match(v, /(^|[ \t])#/)) v = substr(v, 1, RSTART - 1)
        if (istemplate(v)) v = ""
        split(v, RW, /[ \t\r]+/); v = ""
        for (i = 1; i in RW; i++) if (RW[i] != "") { v = trimtok(RW[i]); break }
        if (v != "" && !istemplate(v)) print "red_evidence=" v
      }
      # THE RUNS THE BRIEF DECLARES, MARKS AND ALL (REQ-1 AC-1.1/AC-1.6). List-valued and
      # self-delimiting: the value is the author-marked runs, space-joined, so the roster row
      # carries the same spelling the author wrote and the writer-side budget arm can compare
      # a real command against an exact marked run. There is no `none` waiver here — the
      # absence of the label IS the absence of the declaration, and `Suites: none` remains the
      # one way a brief waives a budget outright.
      nr = split(allhits("runs"), RH, " ")
      split("", MRprev); MRout = ""; MRc = 0; MRdropped = ""; v = ""
      for (r = 1; r <= nr; r++) { MRspan = r; v = marked_runs(spanof(RH[r])) }
      if (MRdropped != "") print "re_executes_dropped=" MRdropped
      if (v != "") print "re_executes=" v
    }
  ' 2>/dev/null
}

# brief_field <lifted> <kind> -> the first `<kind>=` value of a lift, bounded as the roster
# row stores it. The three instrument fields and the lift's fault fields go through here, so
# the value a door records and the value `brief_validate_fields` judges are one reading.
#
#   files, suites, re_executes   LIST-valued, and never cut (T18, REQ-9/D7). A 70-suite
#                                Suites: line runs to 1.7-1.8 KB, and a cut there silently
#                                narrows a budget the wall never agreed to; the field name in
#                                `sanitize`'s third argument is what exempts them, the 900 is
#                                only positional. The write-side half of the fix
#                                `hooks/session-poker.sh`'s `clean()` carries on adopt.
#   re_executes_bad              one command, keeping its `|` (T5): the fault it names is
#                                often the pipe, and the evidence must show the character
#   suites_bad, suites_dropped,  the exact token the lift refused or dropped (T3, T5,
#   re_executes_dropped,         REQ-8; wave-27 T29, T42), so the refusal can name it
#   files_unread, files_bad
#   suites_commented             a Suites: span that was entirely a comment (T35, critic C9)
#   questions, questions_bad     a reader's questions, comma-joined in the table's order, and
#                                the words outside the three (wave-27 T15); questions_dup, the
#                                line numbers of a Questions: label given more than once (T49)
#   lands_red, red_evidence      a declared debt's two lines (wave-27 T31), cut at 300
#   anything else                the raw value
brief_field() {
  local v
  v=$(printf '%s\n' "${1-}" | grep -m1 "^$2=" | cut -d= -f2-)
  case "$2" in
    questions)        sanitize "$v" 40 ;;
    questions_bad)    sanitize "$v" 300 ;;
    # Cut at a whole number (wave-27 T57; review pass 35 N2): a cut at 40 characters could land
    # inside one and print a line that does not exist. The count is the raw field's, read apart.
    questions_dup)    v="$(sanitize "$v" 300)"
                      while [ "${#v}" -gt 40 ] && [ "${v% *}" != "$v" ]; do v="${v% *}"; done
                      printf '%s' "$v" ;;
    lands_red|red_evidence) sanitize "$v" 300 ;;
    files)            sanitize "$v" 900 files ;;
    suites)           sanitize "$v" 900 suites_allowed ;;
    re_executes)      sanitize "$v" 900 re_executes ;;
    re_executes_bad)  sanitize "$v" 300 re_executes ;;
    suites_bad|suites_dropped|re_executes_dropped|files_unread|files_bad) sanitize "$v" 300 ;;
    suites_commented) sanitize "$v" 8 ;;
    *)                printf '%s' "$v" ;;
  esac
}

# brief_files_entry <entry> -> the spelling of <entry> that a Files: line, a dispatch or
# `amend --files+`, stores (wave-27 T29, T42; REQ-12, D21). It asks the lift, so it is the one
# reader, `files_entry`, and never a second copy of its rule. The answer is decided by what the
# lift RECORDED, never by what it left unread (review pass 11 F6):
#   rc 0  the lift records <entry> itself: prints <entry> as written (or as recorded, where the
#         reader strips a surrounding pair of quotes or brackets or a trailing `;`)
#   rc 1  the lift records `./<entry>`: prints that spelling
#   rc 2  neither (white space, a comma, a trailing `.`, no letter or digit, a slot): prints
#         <entry> as written, since no spelling of it is recorded whole
brief_files_entry() {
  local entry="${1-}" rec
  case "$entry" in ''|*[[:space:]]*|*,*) printf '%s' "$entry"; return 2 ;; esac
  # THE ENTRY AS THE LIFT RECORDS IT, which is the entry itself except where the reader strips
  # punctuation (wave-27 T49): `"lib/a.sh"` and `lib/a.sh;` are stored as `lib/a.sh`, and `./` in
  # front of the quoted spelling would record the quotes.
  rec="$(brief_field "$(lift_contract_fields "Files: $entry")" files)"
  case "$rec" in ''|*,*) : ;; *) printf '%s' "$rec"; return 0 ;; esac
  if [ "$(brief_field "$(lift_contract_fields "Files: ./$entry")" files)" = "./$entry" ]; then
    printf './%s' "$entry"; return 1
  fi
  printf '%s' "$entry"
  return 2
}

# brief_body_advisories <brief text> <name> <files> <suites-allowed> <re-executes> <poker>
#   -> zero or more one-line advisories on stdout; always rc 0
# (wave-24 T14; REQ-8, D13.)
#
# THE BODY IS READ HERE AND NOWHERE ELSE. `lift_contract_fields` takes labelled lines, so a brief
# that says "run bash tests/foo.test.sh" under `Suites: tests/widget.test.sh` was admitted, and
# the agent met the budget wall at its first command. This reads the prose for the two shapes
# that meet a wall later — a RUN the contract never declared and a WRITE outside `Files:` — and
# says so at dispatch, with the `amend` line that would declare it.
#
# STRICT, BECAUSE IT IS ONLY AN ADVISORY. Over 202 real briefs the loose readings fired on
# 36 and 70 of them and every strict-predicate hit was an example or a negation (research R5
# item 5: 0 true positives), so each predicate below errs toward silence. A line is NOT read
# when it sits in a `Read first:` span (the label line and what follows it up to a blank line
# or the next label), inside a ``` / ~~~ fence, in a 4-space or tab indented block (Markdown
# code), under a contract label that already declares it, on a never / do-not / must-not line,
# or on an e.g. / for example / such as line (an example is not an instruction).
#   (a) RUN: `bash …tests/<x>.test.sh|run.sh` where the `bash` opens the line (after a bullet
#       and an optional `cd <dir> &&`) or follows a backtick, and <x> is in neither the suite set
#       (declared or derived) nor the declared runs.
#   (b) WRITE: a sentence opening with Edit / Change / Fix / Update / Patch / Rewrite / Modify
#       whose object — the first word after any of the, a, an, file, script, hook, test, suite —
#       is a path (has a `/`), is not under a `record/` directory, and is not in `Files:`
#       (an entry that equals it, prefixes it as a directory, or matches it as a glob).
# Each finding is ONE line (the declaring line is cut at 100 columns, control and non-ASCII
# bytes dropped) so the caller can hand it to its `warn` verbatim. <poker> is the command that
# prefixes `amend`, printed verbatim, so the caller passes it already one shell word
# (`refuse_shell_word`; wave-24 T29, critic I2); <name> the dispatched name (empty reads as `<name>`).
brief_body_advisories() {
  printf '%s\n' "${1-}" | awk -v NAME="${2-}" -v FILES="${3-}" -v SUITES="${4-}" -v RUNS="${5-}" -v POKER="${6-}" '
    BEGIN { Q = "\047" }
    function trim(t) { sub(/^[ \t]+/, "", t); sub(/[ \t]+$/, "", t); return t }
    function show(t) { gsub(/[^ -~]/, "", t); gsub(/"/, Q, t); if (length(t) > 100) t = substr(t, 1, 97) "..."; return t }
    function cleantok(t) {
      gsub(/[`"]/, "", t); gsub(Q, "", t); sub(/[,.;:)]+$/, "", t); sub(/^[(]+/, "", t)
      return t
    }
    function suite_declared(b,   n, parts, i) {
      n = split(SUITES, parts, /[ \t,]+/)
      for (i = 1; i <= n; i++) if (parts[i] == b) return 1
      return (index(RUNS, b) > 0)
    }
    function glob_re(g) {
      # A BRACKET IS A PLAIN CHARACTER (review 7 F4), as units.sh reads one: left unescaped it
      # opened a class awk could not close, and the whole advisory program died with rc 2.
      gsub(/[.+^$(){}|\\]/, "\\\\&", g); gsub(/\[/, "\\\\&", g); gsub(/\*/, ".*", g); gsub(/\?/, ".", g)
      return "^" g "$"
    }
    function in_files(p,   n, parts, i, e, ls, lp) {
      n = split(FILES, parts, /[ \t]*,[ \t]*/)
      sub(/^\.\//, "", p)
      for (i = 1; i <= n; i++) {
        e = parts[i]; sub(/^\.\//, "", e); if (e == "") continue
        if (e == p) return 1
        if (index(e, "*") > 0 || index(e, "?") > 0) { if (p ~ glob_re(e)) return 1; continue }
        if (substr(e, length(e)) == "/" && index(p, e) == 1) return 1
        if (index(p, e "/") == 1) return 1
        ls = length(e); lp = length(p)
        if (ls > lp && substr(e, ls - lp) == "/" p) return 1
        if (lp > ls && substr(p, lp - ls) == "/" e) return 1
      }
      return 0
    }
    function emit(key, msg) { if (key in SEEN) return; SEEN[key] = 1; print msg }
    function amend(flag, val) {
      return "bash " (POKER == "" ? "session-poker.sh" : POKER) " amend " (NAME == "" ? "<name>" : NAME) " " flag " " val " --reason \"<why>\""
    }
    # (a) every `bash …` that is command-shaped: at the line start, or right after a backtick.
    function scan_runs(s, ln,   rest, p, pre, cmd, n, tk, i, b, e) {
      rest = s
      while ((p = index(rest, "bash ")) > 0) {
        pre = substr(rest, 1, p - 1)
        if (pre == "" || substr(pre, length(pre), 1) == "`" || pre ~ /^cd [^;&|`]*(&&|;)[ \t]*$/) {
          cmd = substr(rest, p + 5)
          e = match(cmd, /[`;|&]/); if (e > 0) cmd = substr(cmd, 1, e - 1)
          n = split(cmd, tk, /[ \t]+/)
          for (i = 1; i <= n; i++) {
            b = cleantok(tk[i])
            if (b ~ /(^|\/)tests\/([A-Za-z0-9_.-]+\/)*[A-Za-z0-9_.-]+\.sh$/) {
              sub(/^.*\//, "", b)
              if (b ~ /\.test\.sh$/ || b == "run.sh") {
                if (!suite_declared(b))
                  emit("S:" b, "the brief body runs " b " (\"" show(ln) "\") but Suites:, Re-executes: and the derived suite set do not name it; to declare it: " amend("--suites+", b))
              }
              break
            }
          }
        }
        rest = substr(rest, p + 5)
      }
    }
    # (b) a sentence opening with an edit verb whose object is a non-record path outside Files:.
    function scan_edits(s, ln,   n, sent, i, w, nw, j, v, o) {
      n = split(s, sent, /(\. +|; +)/)
      for (i = 1; i <= n; i++) {
        nw = split(trim(sent[i]), w, /[ \t]+/)
        v = tolower(w[1])
        if (v !~ /^(edit|change|fix|update|patch|rewrite|modify)$/) continue
        for (j = 2; j <= nw; j++) {
          o = tolower(w[j])
          if (o ~ /^(the|a|an|file|files|script|hook|test|suite)$/) continue
          break
        }
        if (j > nw) continue
        o = cleantok(w[j])
        if (o !~ /^[A-Za-z0-9_.\/-]+$/ || index(o, "/") == 0 || o !~ /[A-Za-z]/) continue
        if (substr(o, 1, 1) == "-" || o ~ /^https?:/ || o ~ /(^|\/)record\//) continue
        if (in_files(o)) continue
        emit("F:" o, "the brief body asks the agent to " v " " o " (\"" show(ln) "\") but Files: does not list it; to declare it: " amend("--files+", o))
      }
    }
    {
      line = $0; sub(/\r$/, "", line)
      t = trim(line)
      if (t ~ /^```/ || t ~ /^~~~/) {
        f = substr(t, 1, 3)
        if (fence == "") fence = f; else if (fence == f) fence = ""
        next
      }
      if (fence != "") next
      if (line ~ /^(    |\t)/) next
      lt = tolower(t)
      if (inrf) {
        if (t == "") { inrf = 0; next }
        if (t ~ /^[A-Z][A-Za-z -]{0,30}:/) inrf = 0; else next
      }
      if (lt ~ /^read first:/) { inrf = 1; next }
      if (lt ~ /^(files|suites|re-executes|subprocess claim):/) next
      if (lt ~ /(^|[^a-z])(never|do not|don.t|must not|mustn.t)([^a-z]|$)/) next
      if (lt ~ /(e\.g\.|for example|such as)/) next
      sub(/^([-*+]|[0-9]+[.)])[ \t]+/, "", t)
      scan_runs(t, t)
      scan_edits(t, t)
    }
  '
}

# brief_validate_fields <lifted> <subagent_type> <root> <sink> — every check the contract
# fields feed, in the dispatch wall's order. See the header for the rc and the sink calls.
brief_validate_fields() {
  local lifted="${1-}" role="${2-}" root="${3-}" sink="${4-}"
  local files suites re_executes runs_bad suites_bad suites_dropped runs_dropped suites_commented
  local files_unread files_bad entry fact fix questions no_instrument=""
  local cap capw detail suites_comment impact_cmd found=0
  local _impact_out _impact_tmp _impact_pid _impact_overran _impact_rc _old_ifs
  files=$(brief_field "$lifted" files)
  suites=$(brief_field "$lifted" suites)
  re_executes=$(brief_field "$lifted" re_executes)
  runs_bad=$(brief_field "$lifted" re_executes_bad)
  suites_bad=$(brief_field "$lifted" suites_bad)
  suites_dropped=$(brief_field "$lifted" suites_dropped)
  runs_dropped=$(brief_field "$lifted" re_executes_dropped)
  suites_commented=$(brief_field "$lifted" suites_commented)
  files_unread=$(brief_field "$lifted" files_unread)
  files_bad=$(brief_field "$lifted" files_bad)
  questions=$(brief_field "$lifted" questions)
  # THE ROLE AND ITS QUESTIONS DECIDE THE RUN CAP (wave-20 T4; wave-27 T15, F4), and the refusal
  # texts print the number the lift applied, from the same function.
  cap=$(dp_runs_cap "$role" "$questions")
  capw=$(dp_runs_cap_words "$role" "$questions")

  # ===================================== A Files: ITEM IS A PATH OR A REFUSAL (wave-27 T29, T42)
  # (REQ-12 AC-12.2, D21 as amended by A-orch-46.)
  #
  # NEVER DROPPED. The lift reads each Files: item with `files_entry`, and an item that is not a
  # path comes here by name. Until T29 it fell off the row in silence: `Files: CONTEXT.md, a/b.ts`
  # recorded `a/b.ts` alone, and the writer was refused at its stop for editing the file its
  # brief named. One finding per item, so each refusal line names its item. A bare word is told
  # the spelling `./<word>`; an item no spelling reads (prose, a trailing `.`, no letter or
  # digit) is told to go, since advice to respell it would record it (review pass 11 F1).
  #
  # THE FIRST LINE FITS refuse.sh's BUDGETS: a fix of at most six words and 40 columns, a line of
  # 100. A word of up to 16 characters is named in full and in its `./` spelling; a longer one is
  # cut to 15 and `…` and told the prefix; an item no spelling reads is cut past 42 the same way,
  # the cut the loader makes of a hook name. The detail carries the whole item either way. Past those lengths refuse.sh refused its own call,
  # and the dispatch wall exited 2 with no refusal line (found at T42 GREEN).
  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    if [ "${#entry}" -le 16 ]; then
      fact="Files: names ${entry}, not a path"; fix="spell it ./${entry}"
    else
      fact="Files: names ${entry:0:15}…, not a path"; fix="spell it with a leading ./"
    fi
    detail="The Files: line offered this word, and it is not read as a path:
    ${entry}

A Files: item is a path when it carries a /, or an extension (a final dot and a run of
letters and digits that starts with a letter, as in .md or .sh). This one does neither, and
a file the row does not hold is one the writer is refused for at its stop.

Fix: if it is a file, spell it with ./ —
    Files: ./${entry}
If it is not a file, remove it from the Files: line.

Then retry the dispatch."
    found=1; "$sink" finding "$fact" "$fix" "$detail"
  done <<EOF
$(printf '%s' "$files_unread" | tr ' ' '\n')
EOF
  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    fact="Files: ${entry} is not a path"
    [ "${#entry}" -le 42 ] || fact="Files: ${entry:0:41}… is not a path"
    detail="The Files: line offered this item, and no spelling of it is read as a path:
    ${entry}

A Files: line is a comma-separated list of paths. An item holding a space is prose, and an
item ending in . or holding no letter or digit names no file. A note about the files goes
after a trailing # on the line, or outside the Files: line.

Fix: remove the item, or replace it with the paths it means, comma-separated.

Then retry the dispatch."
    found=1; "$sink" finding "$fact" "drop it" "$detail"
  done <<EOF
$(printf '%s' "$files_bad" | tr ',' '\n')
EOF

  # ===================================== A DECLARATION IS LITERAL TEXT (REQ-1 AC-1.4)
  # (epic-23 wave-16, D1/D3, ADR-029.)
  #
  # THE RULE THE PROSE HAS PROMISED SINCE WAVE-01, now enforced. The suite-allowance
  # refusal below has always ended "one path per token, no shell variables … a name that
  # is still a variable when a hook sees it can be neither derived from nor checked
  # against anything" — and nothing at dispatch checked it (research R1 Q3). A token
  # `tests/$X.test.sh` was basenamed to `$X.test.sh` and lifted onto the roster row as a
  # budget entry, where the writer-side guard then refused every command the agent ran,
  # with its own honest message about an unexpanded name, 40 minutes after the moment the
  # author could have fixed it in a word.
  #
  # BOTH SPELLINGS, ONE ARM. `Re-executes:` gains the rule at birth and `Suites:` gains it
  # here, because a wall whose prose is true for one of two spellings of one idea is a wall
  # nobody can read. A run also refuses on an UNQUOTED `|` (shell plumbing is not one run; a
  # quoted one is an ordinary argument and is admitted — T4, REQ-7), on a newline (the marks
  # never closed on their own line), on a `<name>` glued to a neighbour (an unfilled
  # placeholder — wave-21 T7, REQ-6), or on any other angle bracket that is not a whole slot
  # (a redirection — wave-16 T25, walk §W7).
  #
  # THE TOKEN IS IN THE DETAIL, NOT THE ONE LINE. A command is arbitrarily long and the
  # refusal line is bounded at 100 columns (AC-E1.3); the fact fits the line, the evidence
  # goes where the rest of every Fix block goes.
  if [ -n "$runs_bad" ]; then
    detail="The span offered this, and it is not a command that can be re-run:
    ${runs_bad}

A declared run is matched against what the agent actually types, before any shell has
expanded anything — so a name that is still a variable here can be neither derived from
nor checked against anything, and a run holding an unquoted pipe, a redirection, or a line
break is not one run. Declare the command; leave the shell plumbing off the span. A pipe
INSIDE quotes is an ordinary argument and is admitted, so a regex alternation needs no
rewriting. An unfilled \`<slot>\` on its own is guidance and is ignored. A placeholder
inside a run, such as \`jobs/<id>/logs\`, is filled with a real value, the same as a
variable. Any other bracket in the run is read as redirection.

Fix: mark each run with backticks, on a line of its own, at most ${capw} —
    Re-executes: \`npx jest --testPathPatterns 'x'\`, \`pytest tests/unit\`

Then retry the dispatch."
    found=1; "$sink" finding "a declared run is not a literal command" "spell each run literally" "$detail"
  fi

  # AN OVER-CAP Re-executes: BRIEF IS REFUSED (T5, REQ-8, D12; mirrors the Suites: dropped-
  # token refusal directly below, wave-17 T3). Until now a fourth backtick-marked run fell
  # off `marked_runs()` with a loud `warn()` line but the dispatch was still ADMITTED — the
  # roster row carried three of the four runs the author declared, and the fourth was refused
  # by the writer-side budget arm 40 minutes later as undeclared, for a fact the author was
  # never told at dispatch. `RUNS_MAX` (3) is unchanged; a brief within the cap never reaches
  # this arm.
  #
  # FOR A READER OF THE EVIDENCE QUESTION THE THREE IS A TOTAL (wave-27 T57; review pass 35 N4).
  # Its checks file says "Re-execute at least one evidence command per tier used (cap 3 total)",
  # and a suite named under Suites: is re-executed as surely as a marked run, so the two count
  # together: four suites, or three suites and one run, is over. The suites are the Suites: line's
  # own (`$suites`, before any derivation); the runs are the kept and the dropped ones, counted
  # by `dp_counted_runs` off the lift's whole line, so housekeeping stays free and the total is
  # true however many were dropped. One finding names the total and the cap; the over-cap arm
  # below keeps every other brief's words.
  local ev_total=0 ev_suites=() ev_dropped=""
  if dp_reads_evidence "$role" "$questions"; then
    case "$suites" in ''|none) : ;; *) read -r -a ev_suites <<< "$suites" ;; esac
    ev_dropped="$(printf '%s\n' "$lifted" | sed -n 's/^re_executes_dropped=//p' | head -1)"
    ev_total=$(( ${#ev_suites[@]} + $(dp_counted_runs "$re_executes") + $(dp_counted_runs "$ev_dropped") ))
  fi
  if [ "$ev_total" -gt "$cap" ]; then
    detail="The Suites: and Re-executes: lines name ${ev_total} runs in total (${#ev_suites[@]} suites, $(( ev_total - ${#ev_suites[@]} )) runs), more than the ${cap}-run cap admits for
this brief (${role:-unnamed}${questions:+, Questions: ${questions}})."
    [ -n "$runs_dropped" ] && detail="${detail}
The Re-executes: lines name more runs than the ${cap}-run cap admits on their own, and these
were dropped:
    ${runs_dropped}"
    detail="${detail}

The cap of three is the evidence question's, from payload/context/checks-evidence.md
(\"cap 3 total\"), and binds whichever reader holds that question. Each suite named under
Suites: and each run under Re-executes: is one re-execution of it; file housekeeping
(${DP_HOUSEKEEPING_WORDS}) counts nothing unless it holds one of ; & | \` \$( <( >( or a
line break, quoted or not.

Fix: name at most three in all, across Suites: and Re-executes: —
    Suites: tests/one.test.sh, tests/two.test.sh
    Re-executes: \`pytest tests/unit\`

Then retry the dispatch."
    found=1; "$sink" finding "the total of ${ev_total} runs exceeds the ${cap}-run cap" "declare three at most" "$detail"
  elif [ -n "$runs_dropped" ]; then
    detail="The Re-executes: lines name more runs than the ${cap}-run cap admits for
this brief (${role:-unnamed}${questions:+, Questions: ${questions}}), and this one was dropped:
    ${runs_dropped}

Every declared run goes on the roster row, and the writer-side budget arm compares the
agent's own command against exactly that set — a run dropped here is a command that would
be refused there 40 minutes later, for running exactly what its own brief had named.

The cap of three is the evidence question's, from payload/context/checks-evidence.md
(\"cap 3 total\"), and binds whichever reader holds that question; it counts every run
but file housekeeping (${DP_HOUSEKEEPING_WORDS}), so a cleanup beside them is free.
Every other brief may declare as many runs as a Suites: line may name suites (${DP_SUITES_MAX}).

Fix: mark at most ${capw} runs with backticks, across all your Re-executes: lines —
    Re-executes: \`npx jest --testPathPatterns 'x'\`, \`pytest tests/unit\`, \`go test ./...\`

Then retry the dispatch."
    found=1; "$sink" finding "Re-executes: line exceeds the ${cap}-run cap" "declare at most ${capw} runs" "$detail"
  fi

  if [ -n "$suites_bad" ]; then
    detail="The Suites: span offered this token, and it is not a suite name:
    ${suites_bad}

The declared set goes on the roster row and the writer-side guard compares the agent's own
command against it, both of them as literal text — so a token that is still a variable when
a hook sees it can be neither derived from nor checked against anything.

Fix: spell each suite literally, one path per token —
    Suites: tests/one.test.sh, tests/two.test.sh

Then retry the dispatch."
    found=1; "$sink" finding "a declared suite is not a literal name" "spell each suite literally" "$detail"
  fi

  # A DROPPED Suites: TOKEN IS A REFUSAL (T3, REQ-8; wave-17, research R3 §C1.4 option 3 — a
  # repair of the EXISTING basename filter above, no new I/O, D11-compliant). Until now a
  # token whose basename was neither `*.test.sh` nor a path-qualified `run.sh` — a jest spec,
  # a pytest module, a bare `run.sh` — fell off `suite_names()` in total silence: `suites=`
  # ended up empty, and a brief naming only such tokens then met the UNRELATED no-instrument
  # arm below ("this brief declares no Files: and no Suites:") for having declared something
  # real. This puts the drop on the SAME channel the unexpanded-variable arm above already
  # uses, named, and — because the guard on the no-instrument arm below also checks this
  # field — that arm is never reached by a brief that named a token here.
  #
  # ONE DROPPED TOKEN IS ENOUGH; THE WHOLE SPAN NEED NOT BE DROPPED (walk W4b — the code was
  # always stricter than this note). `Suites: tests/one.test.sh tests/unit/foo.spec.ts`
  # refuses, and should: a half-dropped line is a line whose budget is not what its author
  # wrote, and the writer-side guard would refuse the jest run 40 minutes later anyway.
  # What is NOT a dropped token: the literal waiver `none`, and anything from the first `#`
  # onwards — `suite_names()` stops the scan there (T23, review R1), so a trailing scaffold
  # comment reaches neither this arm nor the roster row.
  if [ -n "$suites_dropped" ]; then
    detail="The Suites: span offered this, and its basename is not one this repo's shell
suite runner can run — neither \`*.test.sh\` nor a path-qualified \`run.sh\`:
    ${suites_dropped}

A jest spec, a pytest module or any other non-shell test file is never run by this label;
it dropped off the row in silence until now, and the writer's own command was then refused
40 minutes later for running exactly what its brief had named.

Fix: where the tests are not shell suites, name the command itself under Re-executes:,
marked with backticks —
    Re-executes: \`npx jest --testPathPatterns 'x'\`, \`pytest tests/unit\`

Or, where they are shell suites, spell the *.test.sh path —
    Suites: tests/one.test.sh

Then retry the dispatch."
    found=1; "$sink" finding "Suites: names a file the shell runner cannot run" "use Re-executes:" "$detail"
  fi

  # ============================================== THE SUITE-ALLOWANCE WALL (AC-20)
  # (seed .bionic/docs/ideas/suite-allowance-wall.md items 1-2; design ledger D2,
  # Chris 2026-09-05 "Option 2": a brief declares INTENT, the machine derives the
  # consequences.)
  #
  # THE INCIDENT. Two writers finished their own hooks green at ~45 minutes and then
  # spent 40 more re-running the entire test tree one suite at a time, in parallel, on
  # an 8 GB machine at load 10. Their briefs said "run impacted suites only; never
  # tests/run.sh; run X, Y, Z as consumers", and "consumers" was read as "everything".
  # Prose in a brief is a wish. Only a wall binds a writer.
  #
  # WHAT THE BRIEF DECLARES. `Files:` — the paths this task will touch. That is intent,
  # and it is the only thing the author reliably knows at dispatch. The CONSEQUENCE (which
  # suites read those paths) is a fact about the tree, and D2 gave the tree ownership of it:
  # `impact-command:` in .bionic/config.yaml names the derivation, the wall runs it over the
  # declared paths, and the answer goes on the roster row for the writer-side guard to hold
  # the agent to.
  #
  # `Suites:` IS THE OTHER HALF, not a legacy spelling. bionic runs in repositories that
  # have no impact command and never will, and there the author is the only one who can
  # state the set — so a declared list is a first-class input, recorded as
  # `suites_source=declared` so no reader downstream mistakes a stated set for a derived
  # one. It also WINS over a derivation when a brief carries both: `Suites: none` is the
  # waiver, and a waiver that a derivation could overrule is not a waiver.
  #
  # A BRIEF WITH NEITHER IS REFUSED, and that is the whole wall. Everything else here is
  # bookkeeping: without one of the two labels there is no budget on the row, and a guard
  # with no budget to enforce is the prose the incident already proved does not bind.
  #
  # `Re-executes:` IS THE THIRD WAY THROUGH (REQ-1 AC-1.3, D1). The field is a budget
  # declaration in exactly the sense this wall means: a closed set of commands, on the roster
  # row, for the writer-side guard to hold the agent to. It is the only declaration available
  # to an agent in a repository whose tests are not shell suites, so refusing a brief that
  # carries it for "declaring no instrument" would be the wall contradicting itself.
  #
  # A BRIEF WHOSE INSTRUMENT WAS REFUSED DECLARED SOMETHING (T3, REQ-8; wave-21 T7, REQ-6
  # AC-6.2). Four lift faults are checked here — `suites_dropped`, `suites_bad`, `runs_bad`
  # and `runs_dropped` — so a `Suites:` or `Re-executes:` span that lost ANY token to a
  # refusal above never falls through to this arm's "declares no Files: and no Suites:"
  # (walk W4b). That refusal is the arm's above that refused the token, named by the actual
  # token, not this one's guess that nothing was declared at all. Until wave-21 only
  # `suites_dropped` was here, so a brief whose one `Re-executes:` run was refused drew two
  # faults, the second false (triage-B §4.2).
  if [ -z "$files" ] && [ -z "$suites" ] && [ -z "$re_executes" ] && \
     [ -z "$suites_dropped" ] && [ -z "$suites_bad" ] && \
     [ -z "$runs_bad" ] && [ -z "$runs_dropped" ] && [ -z "$files_unread" ] && [ -z "$files_bad" ]; then
    # THE CLAUSE GOES FIRST, NOT LAST (critic C9). refuse.sh folds a detail to twelve lines on
    # the channel that hands it to a reader who did not ask for it, and this detail is already
    # longer than that, so a sentence appended at the end is bytes nobody sees. One clause, at
    # the top, where the fold cannot reach it; the verdict and the fix line are untouched.
    suites_comment=""
    if [ -n "$suites_commented" ]; then
      suites_comment="Suites: was declared, but its span is a comment, so it named nothing — write \`none\` to waive.

"
    fi
    detail="${suites_comment}An agent with no declared instrument runs whatever it decides to run. Two writers
read \"run the impacted suites\" as the whole tree and spent 40 minutes each
re-proving the world; the budget only binds when it is on the roster row.

Fix: declare the files this task will touch, on a line of its own —
    Files: path/one.sh, path/two.sh
  The impact command named in .bionic/config.yaml derives the suites from them.

Where no impact command is configured, name the closed set yourself —
    Suites: tests/one.test.sh, tests/two.test.sh

Where the tests are not shell suites, name the commands themselves instead — each marked
with backticks, at most ${capw} —
    Re-executes: \`npx jest --testPathPatterns 'x'\`, \`pytest tests/unit\`

Or waive the budget for a brief that runs no suite at all —
    Suites: none

Either way: one path per token, no shell variables. Both labels are read out of the
brief TEXT, before any shell has expanded anything, and the writer-side guard reads
its command the same way — a name that is still a variable when a hook sees it can
be neither derived from nor checked against anything.

Then retry the dispatch."
    no_instrument=1
    found=1; "$sink" finding "this brief declares no Files: and no Suites:" "declare Files: or Suites:" "$detail"
  fi

  # AN AUDITOR MAY WAIVE NOTHING (T6, REQ-4 AC-4.3/4.4; D6). `Suites: none` is a legitimate
  # waiver for a role that never runs a suite — a researcher reads, a test-runner reports,
  # and both pass through unchanged (AC-4.4). An auditor's whole job at Step 5 is to
  # FALSIFY the matrix's evidence, which for a hermetic-tier row means re-running the named
  # suite (spec §Eval design, `## Verification Matrix` "auditor" column) — a `Suites: none`
  # auditor brief cannot do the one thing its role requires, so the waiver that is silence
  # for every other reading role is a defect here.
  #
  # ROLE MATCHED WHOLE, ON `subagent_type`, THE SAME WAY THE WRITER-CLASS ARM ABOVE DOES —
  # never on the brief's prose, which is a wish, not a wall. Both the fully-qualified name
  # this repo's roster actually carries (`bionic:auditor`) and the bare role word are
  # matched, since a brief authored by hand routinely drops the `bionic:` prefix the harness
  # itself never does.
  #
  # `$suites` IS THE LIFTED FIELD, ALREADY NORMALISED. `suite_names()` (above) prints the
  # literal token `none` for a whole-word waiver and nothing else ever equals it — a brief
  # that both waives and lists suites cannot reach this arm, because `Suites:` is a single
  # labelled span and its lift is one value, the waiver or the list, never both.
  #
  # KEYED TO THE EVIDENCE QUESTION (wave-27 T15; review pass 15, F4): `dp_reads_evidence`, the
  # predicate the cap of three reads, so a critic dealt `evidence` at `tested` is held here as an
  # auditor is. The auditor keeps its own words; another reader is named by its role.
  if dp_reads_evidence "$role" "$questions"; then
      # THE PREDICATE IS NOW "NO SUITES AND NO DECLARED RUNS" (epic-23 wave-16, REQ-1 AC-1.2,
      # D1, ADR-029). An auditor in a jest, pytest or go repository has a real re-execution to
      # declare and no shell suite to name it with; refusing that brief was this arm asking for
      # a spelling the repository does not have, and the fix text it printed named the only
      # spelling that could not answer. `Suites: none` beside a non-empty `Re-executes:` is an
      # auditor that waived the shell-suite budget and declared what it will actually re-run,
      # which is the whole of what this arm exists to require.
      # A RUN THAT ONLY CLEARS OR STAGES FILES IS NO RUN (wave-27 T49, review pass 24): `rm -rf dist`
      # beside `Suites: none` gave the reader nothing to re-execute and was admitted as one.
      #
      # WITH OR WITHOUT A Suites: LINE (wave-27 T57; review pass 35 N7). The arm read only the
      # `none` waiver, so an auditor with no Suites: line and only `rm -rf dist` under
      # Re-executes: was admitted. A reader dealt evidence that names no suite and no counted run
      # declares nothing to re-execute, and is told so in its own words. A brief that declared no
      # instrument at all, or whose suite or run was refused, is already refused above for that,
      # so this arm stays quiet there: one finding for one fault.
      if { [ -z "$suites" ] || [ "$suites" = "none" ]; } && [ "$(dp_counted_runs "$re_executes")" -eq 0 ] \
         && [ -z "$no_instrument" ] && [ -z "$runs_bad$suites_bad$suites_dropped" ]; then
        found=1; "$sink" finding "the ${role#bionic:} declares nothing to re-execute" "name one suite or run" \
          "Role: ${role}${questions:+ (Questions: ${questions})}

A verdict on the evidence question is a re-run of the evidence, not a read of it — a
hermetic-tier row in the matrix is falsified by running the suite the row names, and a
brief that waives every suite gives its reader nothing to run.

Fix: name what the matrix binds this reader to re-execute, on a line of its own. For
shell suites —
    Suites: tests/one.test.sh, tests/two.test.sh

  For any other runner, name the commands themselves, each marked with backticks, at
  most three —
    Re-executes: \`npx jest --testPathPatterns 'x'\`, \`pytest tests/unit\`

Then retry the dispatch."
      fi
  fi

  # ---------- the derivation ----------
  #
  # THE COMMAND IS CONFIGURATION, THE PATHS ARE THE BRIEF. The command is word-split (it is
  # `bash tests/lib/impact.sh` — a runner and a script, not one word) and the declared paths
  # go in as separate arguments, quoted. Nothing is eval'd: a path lifted out of a brief is
  # author-supplied text, and word-splitting it into a command line is how a `Files:` line
  # carrying a semicolon becomes a command. `ispath` has already rejected anything without a
  # slash, but the shape of the guard here does not depend on that check holding.
  #
  # THE COMMITTED DEFAULT IS ABSENCE (plan A-8). `.bionic/config.yaml` is machine-local, so a
  # fresh clone and every other repository bionic runs in take the declared path.
  #
  # A DERIVATION THAT FAILS OR ANSWERS NOTHING LEAVES `suites_allowed=` EMPTY, and empty is
  # the third state: not a set, and not the `none` waiver either. The writer-side guard reads
  # it as "no budget was stated" and stands aside for a named suite while still refusing
  # tests/run.sh, so a broken impact command costs an over-wide instrument rather than an
  # agent that can run nothing. The operator is told at dispatch, which is the moment the
  # config is still fixable.
  impact_cmd=$(config_value "$root" "impact-command" "")
  BRIEF_SUITES_ALLOWED=""
  BRIEF_SUITES_SOURCE=""
  # A READER'S SUITES ARE THE TOKENS ITS Suites: LINE NAMES (wave-27 T72; review pass 49 B1,
  # A-orch-134). A reader's Files: line lists its records and a reader edits no tracked file, so
  # nothing is derived from it and "no impact command is configured" is never its answer. The
  # ROLE decides, here, ahead of the derivation: a line that is all comment, `#` alone, blank or
  # absent names no token, and that is `Suites: none`. T57 tested which fields were empty instead,
  # and left the line that is all comment to the writer's derivation (eight suites beside a run).
  # The evidence rules above have already judged the runs, and a refused or dropped token above.
  if dp_is_reader "$role"; then
    BRIEF_SUITES_ALLOWED="${suites:-none}"
    BRIEF_SUITES_SOURCE="declared"
  elif [ -n "$suites" ]; then
    BRIEF_SUITES_ALLOWED="$suites"
    BRIEF_SUITES_SOURCE="declared"
  elif [ -z "$files" ]; then
    # NOTHING TO DERIVE FROM, AND THE ABSENCE IS ALREADY A FINDING. Before the arms
    # collected, this branch was unreachable: the wall above exited on a brief carrying
    # neither label, so anything past it held at least one of them. It is reachable now,
    # and it must stay silent — running the derivation over an empty argument list would
    # warn that "the impact command derived no suites" (it was never asked), and falling
    # into the arm below would report a missing `impact-command:` as a SECOND fault when
    # the brief's own missing `Files:` is the one the author fixes. One fault, one finding.
    :
  elif [ -n "$impact_cmd" ]; then
    _old_ifs="$IFS"; IFS=','; set -f
    # shellcheck disable=SC2086
    set -- $files
    set +f; IFS="$_old_ifs"
    _impact_out=""; _impact_rc=0
    if [ "$#" -gt 0 ]; then
      # A BOUND THE HOOK BUILDS ITSELF (review-c C-16). The derivation is the whole of the
      # gate's cost: ~0.3 s without it, ~2.9-3.1 s with it on an idle tree, and 5.06-6.51 s
      # measured while this wave's own writers were running — which is exactly the condition
      # under which a wave dispatches.
      #
      # WHY THE BOUND IS A REFUSAL AND NOT A FALLBACK. A PreToolUse hook killed on the CLI's
      # timeout does NOT exit 2. The dispatch proceeds, no roster row is written, and the
      # writer runs with no budget at all — the wall defeated by the cost of the wall. That is
      # the one failure this arm cannot have, so the overrun is refused here, in time, with a
      # message. The other derivation failures stay as they were (empty budget + a warning):
      # a command that answers nothing has still answered.
      #
      # WHICH IS WHY THE BOUND MUST SIT STRICTLY UNDER THIS HOOK'S REGISTRATION, MARGIN NAMED
      # (wave-14 D2, ratified; D1 moved both numbers). hooks/hooks.json registers this hook at
      # `"timeout": 15` and `IMPACT_BOUND_S` is 10, five seconds clear. A bound above the
      # registration cannot refuse anything in production, however many times this file's
      # suite drives it to a refusal — the suite has no CLI timeout and the machine does
      # (A-T6.5). The pair is pinned where the two files meet: cross-gate-agreement §L.4c.
      #
      # BUILT, NOT BORROWED. bionic's command discipline forbids a `timeout`/`gtimeout` binary
      # and macOS ships neither, so the bound is a backgrounded child and a `kill -0` poll.
      # THE BOUND IS NOT THIS FILE'S (wave-14 REQ-7, D4). `IMPACT_BOUND_S` lives in
      # lib/bounds.sh and is read by both legs of the fleet — this wall, once per dispatch,
      # and lib/stop.sh's landing sweep, once per sweep. Both carried their own `6` under
      # their own header, and two copies of a constant do not disagree loudly: they disagree
      # the next time a wave moves one of them, and what ships is a tree whose two legs mean
      # different things by "bounded" while every message quotes its own half (R2 Q8 found the
      # twin). Read the library's header before touching the number — it is a HANG GUARD now,
      # not a cost budget, and the answer to a slow derivation is the cache, never this.
      #
      # SOURCED THE WAY lib/stop.sh SOURCES IT, guarded on the thing it defines so a caller
      # that already has it pays nothing, and LAZILY — here, at the one arm that spends it,
      # rather than at file scope beside the loader's own seven libraries. Every dispatch that
      # declares `Suites:` outright reaches neither this branch nor this read.
      if [ -z "${IMPACT_BOUND_S:-}" ]; then
        # shellcheck source=/dev/null
        . "$_BRIEF_LIB_DIR/bounds.sh"
      fi
      # THE WAIT ENDS ON A CLOCK, NOT ON A COUNT OF POLLS (wave-14 T34). This loop used to
      # spend a tick budget — `IMPACT_BOUND_TICKS=$(( IMPACT_BOUND_S * 10 ))`, one tick per
      # `sleep 0.1` — and call the budget the bound. It is not the bound. `sleep` is an
      # external binary, so every tick pays a fork and an exec on top of the 100 ms it
      # sleeps: measured at 115.3 ms a tick on a quiet Mac (T34 §2), which makes a stated
      # 20 s bound a 23.0-23.2 s wait and a stated 5 s bound a 5.77 s wait, while the
      # refusal below quotes the stated number. That is the same lie the derived budget was
      # written to prevent, one layer down — the literal was fixed, the RATE was not.
      #
      # AND THE ERROR IS PROPORTIONAL, WHICH IS THE PART THAT MATTERS. A fixed 15% would
      # only be untidy. Under the load 8-12 a wave actually dispatches at, each tick costs
      # more and the realized wait grows with it — so the one guard whose job is to stop a
      # wedged session waiting gets slower exactly when the session is wedged. A hang guard
      # cannot be denominated in a unit that stretches under the condition it guards.
      #
      # `SECONDS` IS THE CLOCK, AND IT COSTS NOTHING. Assigning it zeroes bash's own
      # elapsed-time counter and reading it is a shell builtin — no second fork per tick, on
      # a path this wave is measuring for latency. /bin/bash is 3.2 on a Mac, which has
      # neither `EPOCHREALTIME` nor `printf %(%s)T`, and bionic's command discipline forbids
      # a `timeout` binary; `date +%s` would cost a fork per tick to buy the same
      # whole-second resolution `SECONDS` gives free. Nothing else in this hook or in the
      # libraries it sources reads `SECONDS`, so zeroing it here takes nothing from anyone.
      #
      # THE RESOLUTION IS A WHOLE SECOND, AND IT ROUNDS TOWARD WAITING LESS. `SECONDS` is
      # integer, and the assignment below lands at an arbitrary point inside a second, so the
      # wait ends somewhere in [bound-1, bound] — never past the number the refusal quotes.
      # For a hang guard that is the correct direction to be wrong in: a guard that fires a
      # little early costs a re-dispatch, and one that fires late costs the thing the guard
      # exists for. The bound itself is NOT this file's to move (lib/bounds.sh, D4); this
      # changes only whether the wait honours it.
      #
      # `sleep 0.1` STAYS the poll cadence. It is what makes a prompt derivation noticed
      # promptly, and with the clock deciding, its cost no longer accumulates into the bound.
      _impact_tmp="${TMPDIR:-/tmp}/bionic-impact-$$-${RANDOM}.out"
      # shellcheck disable=SC2086  # the COMMAND is configuration and is meant to split
      ( cd "$root" 2>/dev/null && $impact_cmd "$@" >"$_impact_tmp" 2>/dev/null ) &
      _impact_pid=$!
      SECONDS=0
      _impact_overran=0
      while kill -0 "$_impact_pid" 2>/dev/null; do
        if [ "$SECONDS" -ge "$IMPACT_BOUND_S" ]; then
          kill -TERM "$_impact_pid" 2>/dev/null
          _impact_overran=1
          break
        fi
        sleep 0.1
      done
      wait "$_impact_pid" 2>/dev/null
      _impact_rc=$?
      if [ "$_impact_overran" -eq 1 ]; then
        rm -f "$_impact_tmp"
        detail="The command named by \`impact-command:\` in .bionic/config.yaml turns the paths this
brief declared into the set of suites the agent may run. This hook is registered with a
timeout of its own in hooks/hooks.json, and a hook killed on that timeout does NOT refuse:
the dispatch would proceed with no roster row at all, and the writer would run with no
budget — the wall defeated by the cost of the wall. So the derivation is bounded here,
strictly under that registration.

  command: $impact_cmd
  paths:   $*
  bound:   ${IMPACT_BOUND_S}s

Fix: narrow \`Files:\` to the paths this task really writes, or name the closed set
directly with \`Suites:\` — a declared set needs no derivation at all. If the command
itself has become slow, that is the thing to fix: it runs on every dispatch."
        # A TIMEOUT IS NOT A BROKEN COMMAND (wave-24 T13, D10, AC-6.7). The bound expired, so
        # the fact says that and for how long, and the fix is the brief's: a narrower `Files:` or
        # a declared `Suites:` needs less derivation or none. A command that FAILED is the warn
        # below, which names its exit status; the two never share a sentence.
        found=1; "$sink" finding "the impact command timed out after ${IMPACT_BOUND_S} s" "declare Suites:, narrow Files:" "$detail"
        # NOTHING DERIVED MEANS NOTHING TO JUDGE AGAINST (AC-8.2). The wall that reads the suite
        # set (the dispatch wall's full-run arm) is the caller's, so the
        # caller is told the set was never built — rc 2 — and says `not checked` for it itself.
        # rc 2 IS ALSO AN EARLY SPEND for the dispatch wall (Step-6 architecture review §2.2):
        # there is nothing below this branch but checks that depend on the derivation, so an
        # arm added after it that does NOT must be pooled above the derivation instead.
        return 2
      fi
      _impact_out=$(cat "$_impact_tmp" 2>/dev/null) || _impact_out=""
      rm -f "$_impact_tmp"
    fi
    BRIEF_SUITES_ALLOWED=$(printf '%s\n' "$_impact_out" | awk -F'\t' '$1 != "" { print $1 }' | sort -u | tr '\n' ' ')
    BRIEF_SUITES_ALLOWED="${BRIEF_SUITES_ALLOWED% }"
    BRIEF_SUITES_SOURCE="derived"
    if [ -z "$BRIEF_SUITES_ALLOWED" ]; then
      if [ "${_impact_rc:-0}" -ne 0 ]; then
        "$sink" warn "the impact command failed (exit ${_impact_rc}) and derived no suites from the declared files; the row records an empty budget: $impact_cmd"
      else
        "$sink" warn "the impact command derived no suites from the declared files; the row records an empty budget: $impact_cmd"
      fi
    fi
  else
    # `Files:` alone in a repository with no impact command states an intent nothing can turn
    # into a budget. AC-20: where no impact command is configured the wall requires the
    # explicit list. Refused rather than passed with an empty set, because the author is
    # holding the brief and one line fixes it.
    detail="\`Files:\` states which paths the task will touch. Turning that into the set of
suites the agent may run is the tree's job, and this repository has not named the
command that asks it.

Fix: name the closed set in the brief instead —
    Suites: tests/one.test.sh, tests/two.test.sh

Or configure the derivation once, in .bionic/config.yaml —
    impact-command: bash tests/lib/impact.sh

Then retry the dispatch."
    if [ -n "$re_executes" ]; then
      detail="\`Files:\` states which paths the task will touch. Turning that into the set of
suites the agent may run is the tree's job, and this repository has not named the
command that asks it.

Fix: your runs are declared under Re-executes:; waive the suite set with \`Suites: none\` beside it —
    Suites: none

Or name the closed set in the brief instead —
    Suites: tests/one.test.sh, tests/two.test.sh

Or configure the derivation once, in .bionic/config.yaml —
    impact-command: bash tests/lib/impact.sh

Then retry the dispatch."
    fi
    # THE SHORT FIX IS THE ONE THAT APPLIES (wave-22 T10; critic C3). On a several-fault brief the
    # detail block above is dropped and only this line reaches the author.
    local short_fix="set impact-command in config.yaml"
    # THE CAPPED USER LINE (wave-22 T13; critic-3598752 I1): on a one-fault brief this short fix
    # ends the 100-column line, so it stays at 98 columns or refuse.sh refuses its own call.
    if [ -n "$re_executes" ]; then short_fix="Suites: none beside Re-executes:"; fi
    found=1; "$sink" finding "no impact command is configured here" "$short_fix" "$detail"
  fi

  return "$found"
}
