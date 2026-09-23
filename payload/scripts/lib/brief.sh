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
#   lift_contract_fields <brief text> [<subagent_type>]   -> `kind=value` lines
#   brief_field <lifted> <kind>        -> one kind's value, bounded as the roster row stores it
#   brief_validate_fields <lifted> <subagent_type> <root> <sink>
#       -> rc 0: no finding · rc 1: at least one · rc 2: the derivation overran its bound, so
#          the suite set was never built (its finding is already in the sink)
#       sets BRIEF_SUITES_ALLOWED and BRIEF_SUITES_SOURCE (`declared`, `derived` or empty), the
#       two values the roster row records
#       calls `<sink> finding <fact> <fix> <detail>` once per fault, in the order the dispatch
#       wall reports them, and `<sink> warn <line>` for a loud pass
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

# ---------- the re-execution cap is the auditor's (wave-20 T4; REQ-7, Δ3, Δ9) ----------
#
# THREE IS THE AUDITOR'S NUMBER. Its source is the auditor mandate — "One auditor, one pass,
# <=3 re-executions" (skills/canonical-sdlc/steps/5.md) — and it used to bind every role's
# `Re-executes:`, so a test-runner re-running a jest, pytest and go floor split it into two
# dispatches for a rule written about auditors (triage-B D3). Chris moved it (Δ3): the
# auditor keeps three; every other role is bounded by SUITES_MAX (Δ9), the count that
# already bounds `Suites:`, so the two spellings of one statement share one ceiling and no
# new number exists.
#
# THE ROLE IS MATCHED WHOLE, as the auditor arm below matches it: the prefixed name the
# harness sends and the bare word a hand-written brief uses. The answer is handed to the
# lift's awk as `-v RUNS_CAP`; the refusal texts below read the same function, so the
# number a refusal prints is the number the lift applied.
DP_AUDITOR_RUNS_MAX=3
DP_SUITES_MAX=200
dp_runs_cap() {  # <subagent_type> -> how many runs that role's Re-executes: may declare
  case "${1-}" in
    bionic:auditor|auditor) printf '%s' "$DP_AUDITOR_RUNS_MAX" ;;
    *) printf '%s' "$DP_SUITES_MAX" ;;
  esac
}
# dp_runs_cap_words <subagent_type> -> the cap as the refusal texts say it.
dp_runs_cap_words() {
  case "${1-}" in
    bionic:auditor|auditor) printf 'three' ;;
    *) printf '%s' "$DP_SUITES_MAX" ;;
  esac
}

lift_contract_fields() {  # <brief text> [<subagent_type>] -> `kind=value` lines, absent kinds omitted
  printf '%s' "$1" | awk -v LEAD="$LEAD_CHARS" -v TRAIL="$TRAIL_CHARS" -v QUOTES="$QUOTE_CHARS" \
    -v RUNS_CAP="$(dp_runs_cap "${2-}")" -v SUITES_CAP="$DP_SUITES_MAX" "$CMD_RUN_NORM_AWK"'
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
    # FOUR REFUSALS AT THE LIFT, each naming the token (REQ-1 AC-1.4, ADR-029; wave-16 T25).
    # An UNQUOTED `|` is shell plumbing, and plumbing is not one run; a newline means the
    # marks never closed on their own line; an unexpanded `$name` is a budget entry no
    # command can equal (see the same rule on the `Suites:` span above); and an angle bracket
    # that is not a whole slot is a shell redirection, which used to be dropped in silence.
    # The refusal is made on the bash side — this prints the fact.
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
    # inside it can never run as plumbing either. Refusing it here would invent a fifth
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
    function marked_runs(s,   i, j, tok, out, c, dropped, why) {
      out = ""; c = 0; dropped = ""
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
        if (tok ~ /[<>]/) { print "re_executes_bad=a redirection: " tok; continue }
        # STORED THROUGH THE ONE RUN RULE (wave-20 T4; REQ-7, D7). The refusals above run
        # first and on the text as written — a declaration naming a redirection is still told
        # so (16ld3, Chris D14) — so what reaches here carries no redirection, no unquoted
        # pipe, and this is the identity today. It is here so the rule that builds the claim
        # is, by construction, the rule that built the declaration.
        tok = collapse(tok, 1)
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
      if (dropped != "") {
        print "re_executes_dropped=" dropped
      }
      return out
    }
    function paths(s, maxn, warnlabel,   n, arr, i, t, out, seen, c, dropped) {
      n = split(s, arr, /[ \t\r\n]+/); out = ""; c = 0; dropped = ""
      for (i = 1; i <= n; i++) {
        t = trimtok(arr[i])
        if (!ispath(t) || seen[t]) continue
        seen[t] = 1
        if (c < maxn) { out = (out == "" ? t : out "," t); c++ }
        else if (warnlabel != "") { dropped = (dropped == "" ? t : dropped " " t) }
      }
      if (warnlabel != "" && dropped != "") {
        print "files_capwarn=" warnlabel " line exceeds the " maxn "-path cap — dropped: " dropped
      }
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
      # The ROLE decides, on the bash side (`dp_runs_cap`, above this function): three for an
      # auditor, whose mandate states "<=3 re-executions" (skills/canonical-sdlc/steps/5.md),
      # and SUITES_MAX for every other role. Unlike FILES_MAX/SUITES_MAX this is not a bound
      # on the width of a row field — it is the ceiling of the declaration itself — so
      # hitting it is a fact about the brief, and loud: see marked_runs() above. A caller that
      # passes no cap gets SUITES_MAX, never an unbounded lift.
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
      h = firsthit("claims");      if (h > 0) { v = claimpat(spanof(h));      if (v != "") print "claims=" v }
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
      if (h > 0) { v = paths(spanof(h), FILES_MAX, "Files:"); if (v != "") print "files=" v }
      # THE SUITES THE BRIEF DECLARES, NORMALISED TO BASENAMES at the moment they
      # are lifted, so the declared spelling and the derived one are the same
      # spelling on the row and the writer-side guard compares one alphabet. The
      # explicit waiver `Suites: none` lifts as the literal token `none`, which is
      # a DECLARED empty set — distinguishable on the row from a brief that stated
      # no budget at all, and refused by the guard for every suite.
      h = firsthit("suites")
      if (h > 0) { v = suite_names(spanof(h)); if (v != "") print "suites=" v }
      # THE RUNS THE BRIEF DECLARES, MARKS AND ALL (REQ-1 AC-1.1/AC-1.6). List-valued and
      # self-delimiting: the value is the author-marked runs, space-joined, so the roster row
      # carries the same spelling the author wrote and the writer-side budget arm can compare
      # a real command against an exact marked run. There is no `none` waiver here — the
      # absence of the label IS the absence of the declaration, and `Suites: none` remains the
      # one way a brief waives a budget outright.
      h = firsthit("runs")
      if (h > 0) { v = marked_runs(spanof(h)); if (v != "") print "re_executes=" v }
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
#   re_executes_dropped          REQ-8), so the refusal can name it
#   suites_commented             a Suites: span that was entirely a comment (T35, critic C9)
#   anything else                the raw value
brief_field() {
  local v
  v=$(printf '%s\n' "${1-}" | grep -m1 "^$2=" | cut -d= -f2-)
  case "$2" in
    files)            sanitize "$v" 900 files ;;
    suites)           sanitize "$v" 900 suites_allowed ;;
    re_executes)      sanitize "$v" 900 re_executes ;;
    re_executes_bad)  sanitize "$v" 300 re_executes ;;
    suites_bad|suites_dropped|re_executes_dropped) sanitize "$v" 300 ;;
    suites_commented) sanitize "$v" 8 ;;
    *)                printf '%s' "$v" ;;
  esac
}

# brief_validate_fields <lifted> <subagent_type> <root> <sink> — every check the contract
# fields feed, in the dispatch wall's order. See the header for the rc and the sink calls.
brief_validate_fields() {
  local lifted="${1-}" role="${2-}" root="${3-}" sink="${4-}"
  local files suites re_executes runs_bad suites_bad suites_dropped runs_dropped suites_commented
  local cap capw detail suites_comment impact_cmd found=0
  local _impact_out _impact_tmp _impact_pid _impact_overran _old_ifs
  files=$(brief_field "$lifted" files)
  suites=$(brief_field "$lifted" suites)
  re_executes=$(brief_field "$lifted" re_executes)
  runs_bad=$(brief_field "$lifted" re_executes_bad)
  suites_bad=$(brief_field "$lifted" suites_bad)
  suites_dropped=$(brief_field "$lifted" suites_dropped)
  runs_dropped=$(brief_field "$lifted" re_executes_dropped)
  suites_commented=$(brief_field "$lifted" suites_commented)
  # THE ROLE DECIDES THE RUN CAP (wave-20 T4; REQ-7, Δ3, Δ9), and the refusal texts print the
  # number the lift applied, from the same function.
  cap=$(dp_runs_cap "$role")
  capw=$(dp_runs_cap_words "$role")

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
  # never closed on their own line), or on an angle bracket that is not a whole slot (a
  # redirection — wave-16 T25, walk §W7).
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
rewriting. An unfilled \`<slot>\` on its own is guidance and is ignored, but a bracket
anywhere else in the run is read as redirection.

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
  if [ -n "$runs_dropped" ]; then
    detail="The Re-executes: span named more runs than the ${cap}-run cap admits for
this role (${role:-unnamed}), and this one was dropped:
    ${runs_dropped}

Every declared run goes on the roster row, and the writer-side budget arm compares the
agent's own command against exactly that set — a run dropped here is a command that would
be refused there 40 minutes later, for running exactly what its own brief had named.

The cap of three is the auditor's, from its mandate's \"<=3 re-executions\"; every other
role may declare as many runs as a Suites: line may name suites (${DP_SUITES_MAX}).

Fix: mark at most ${capw} runs with backticks, one line —
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
  # A BRIEF THAT NAMED A DROPPED TOKEN DECLARED SOMETHING (T3, REQ-8). `suites_dropped`
  # is checked here too, so a `Suites:` line that lost ANY token to the filter above — not
  # only one that lost every token — never falls through to this arm's "declares no Files:
  # and no Suites:" (walk W4b). That refusal is the suite-drop arm's above, named by the
  # actual token, not this one's guess that nothing was declared at all.
  if [ -z "$files" ] && [ -z "$suites" ] && [ -z "$re_executes" ] && [ -z "$suites_dropped" ]; then
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
  case "$role" in
    bionic:auditor|auditor)
      # THE PREDICATE IS NOW "NO SUITES AND NO DECLARED RUNS" (epic-23 wave-16, REQ-1 AC-1.2,
      # D1, ADR-029). An auditor in a jest, pytest or go repository has a real re-execution to
      # declare and no shell suite to name it with; refusing that brief was this arm asking for
      # a spelling the repository does not have, and the fix text it printed named the only
      # spelling that could not answer. `Suites: none` beside a non-empty `Re-executes:` is an
      # auditor that waived the shell-suite budget and declared what it will actually re-run,
      # which is the whole of what this arm exists to require.
      if [ "$suites" = "none" ] && [ -z "$re_executes" ]; then
        found=1; "$sink" finding "an auditor names no suites" "name the suites to re-execute" \
          "Role: ${role}

An auditor's Step-5 verdict is a re-run of the evidence, not a read of it — a hermetic-tier
row in the matrix is falsified by running the suite the row names, and a brief that waives
every suite gives the auditor nothing to run.

Fix: name what the matrix binds this auditor to re-execute, on a line of its own. For
shell suites —
    Suites: tests/one.test.sh, tests/two.test.sh

  For any other runner, name the commands themselves, each marked with backticks, at
  most three —
    Re-executes: \`npx jest --testPathPatterns 'x'\`, \`pytest tests/unit\`

Then retry the dispatch."
      fi
      ;;
  esac

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
  if [ -n "$suites" ]; then
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
    _impact_out=""
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
        found=1; "$sink" finding "the impact command did not answer" "fix impact-command in config.yaml" "$detail"
        # NOTHING DERIVED MEANS NOTHING TO JUDGE AGAINST (AC-8.2). The walls that read the suite
        # set (the dispatch wall's one-regression and floor-once arms) are the caller's, so the
        # caller is told the set was never built — rc 2 — and says `not checked` for them itself.
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
      "$sink" warn "the impact command derived no suites from the declared files; the row records an empty budget: $impact_cmd"
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
    found=1; "$sink" finding "no impact command is configured here" "set impact-command in config.yaml" "$detail"
  fi

  return "$found"
}
