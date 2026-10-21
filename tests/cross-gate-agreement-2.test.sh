#!/bin/bash
# tests/cross-gate-agreement-2.test.sh — CROSS-COMPONENT INSTRUMENT PROOFS, part 2 of 2: sections §CG through §WIDTH.
#
# THE SUITE IS TWO PARTS (wave-39 T36; D1, D13, REQ-3 AC-3.3). One cross-gate-agreement.test.sh promised more than
# half the suite bar, ten minutes of the gate's promise, so it runs as two suites cut at a section boundary. Its
# governing header, its sandbox, its parties and the fixture builders and helpers both parts share are in
# tests/cross-gate-agreement.prelude.sh, sourced below after the framework.
#
# Usage: bash tests/cross-gate-agreement-2.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/plan-fixture.sh"
. "$(dirname "$0")/lib/assert.sh"
. "$(dirname "$0")/cross-gate-agreement.prelude.sh"

# THE CORE SCRIPT'S TEXT. hooks/session-poker.sh is the dispatcher of eight files: it loads its seven parts from poker/
# beside it. A reader below that asks the core script's text reads all eight, the dispatcher first; a mutation is
# made in the part that holds the line it doctors.
CG2_PARTS="$(dirname "$PARTY_PK")/poker"
CG2_POKER_TEXT="$SANDBOX/cg2-poker-text.sh"
cat "$PARTY_PK" "$CG2_PARTS"/*.sh > "$CG2_POKER_TEXT"
expect_eq "CG2 precondition: the core script's text holds the dispatcher and its seven parts" "8" \
  "$( { printf '%s\n' "$PARTY_PK"; ls "$CG2_PARTS"/*.sh; } | /usr/bin/grep -c '\.sh$' | tr -d ' ')"

# ============================================================
section "CG — the current: GRAMMAR: sched_plan_current agrees with run.sh's run_open step-read (epic-21 T6)"
# ============================================================
#
# TWO READERS OF ONE FIELD, deliberately duplicated rather than shared (hooks/session-poker.sh
# names the reason at sched_plan_current's definition: folding the FILL gate's read into
# run_state would couple the DISARM decision to the FILL decision). Duplication without an
# agreement test is exactly the shape review-b's finding (c) describes: `run_state` (this
# file's RUN_LIB, function `run_open`) strips a trailing a/b sub-step letter before reading
# digits; `sched_plan_current` used to reject that same letter outright, so `current: 3b`
# read as UNREADABLE to the gate and fell through to a FILL — the bug T6 fixes. This section
# is the smaller of T6's two remediation choices (share one function vs. bind the two readers
# with a test): the callers answer genuinely different questions off genuinely different
# inputs (a session's roster vs. a plan path alone), so a shared function would be an
# awkward abstraction over two unrelated call shapes. An agreement test is the fit.
#
# Both parties are called FOR REAL, not compared as text — sched_plan_current's own body
# calls _sched_plan_current_field, so the poker's two are extracted and eval'd together
# (§I.1's precedent, `q_poker` above). Since wave-19 (REQ-6, D7) the extracted
# `_sched_plan_current_field` is a one-line wrapper over fill.sh's `_fill_current_field`, the
# one parser of the field, so FILL_LIB is sourced beside RUN_LIB; the grammar this section
# binds to `run_open` is that parser's. `normalize_newlines` is no longer
# among them: since epic-23 wave-12-fixit-171 (REQ-8, spec D6) it has ONE definition, in
# payload/scripts/lib/run.sh, which this section already had in hand as RUN_LIB — so it is
# sourced rather than extracted, which is also what the shipped poker does. run_open is
# sourced from the same RUN_LIB exactly as §PC below sources it.
cg_extract_fn() {  # <fn-name> -> that function's body text, from the core script's text (the tick holds these two)
  awk -v n="$1" '$0 ~ "^" n "\\(\\)" {f=1} f{print; if ($0=="}") exit}' "$CG2_POKER_TEXT"
}
cg_sched_current() {  # <plan path> -> sched_plan_current's real answer, called for real
  ( . "$RUN_LIB" >/dev/null 2>&1            # normalize_newlines is run.sh's since REQ-8/D6
    . "$FILL_LIB" >/dev/null 2>&1           # the reader the wrapper delegates to (REQ-6, D7)
    eval "$(cg_extract_fn _sched_plan_current_field)"
    eval "$(cg_extract_fn sched_plan_current)"
    sched_plan_current "$1" ) 2>/dev/null
}
cg_run_open() {  # <plan path> -> "0" (open) or "1" (not a recognized open state), run_open
                 # called for real off RUN_LIB
  ( . "$RUN_LIB" >/dev/null 2>&1; run_open "$1" ) >/dev/null 2>&1
  printf '%s' "$?"
}
cg_plan() {  # <current: value, or "" for none> -> a fixture plan path carrying it
  local cur="$1"
  local safe; safe="$(printf '%s' "${cur:-none}" | tr -c 'A-Za-z0-9' '_')"
  local f="$SANDBOX/fx/cg/current-${safe}.plan.md"
  mkdir -p "$(dirname "$f")"
  {
    printf '# cg fixture plan\n\n## SDLC State\n\n'
    [ -n "$cur" ] && printf 'current: %s\n\n' "$cur"
    printf -- '- Step %s: in progress\n' "${cur:-0}"
  } > "$f"
  printf '%s' "$f"
}

# ── CG.1 the a/b sub-step letter: both readers strip it and land on the SAME numbered step ──
for CG_STEP in 3 4 8; do
  for CG_LETTER in '' a b; do
    CG_VAL="${CG_STEP}${CG_LETTER}"
    CG_PLAN="$(cg_plan "$CG_VAL")"
    expect_eq "CG.1 sched_plan_current(current: $CG_VAL) reads the step, letter stripped" \
      "$CG_STEP" "$(cg_sched_current "$CG_PLAN")"
    expect_eq "CG.1 …and run.sh's run_open agrees this is a live, in-range step" \
      "0" "$(cg_run_open "$CG_PLAN")"
  done
done

# ── CG.2 an unparseable current: is never mistaken for an active step by EITHER reader ──
for CG_BAD in "abc" "3 (Step-3 review)" "3c"; do
  CG_PLAN="$(cg_plan "$CG_BAD")"
  expect_eq "CG.2 sched_plan_current withholds on '$CG_BAD'" "" "$(cg_sched_current "$CG_PLAN")"
  expect_eq "CG.2 …and run.sh's run_open agrees this plan is not a recognized open state" \
    "1" "$(cg_run_open "$CG_PLAN")"
done
# no current: line at all — same non-agreement: both give up on the field, neither fills it in
CG_NOLINE="$SANDBOX/fx/cg/no-current.plan.md"
mkdir -p "$(dirname "$CG_NOLINE")"
printf '# cg fixture plan\n\n## SDLC State\n\n- Step 3: in progress\n' > "$CG_NOLINE"
expect_eq "CG.2 no current: line at all — sched_plan_current withholds" \
  "" "$(cg_sched_current "$CG_NOLINE")"
expect_eq "CG.2 …and run_open agrees (no current: field is not an open state)" \
  "1" "$(cg_run_open "$CG_NOLINE")"

# ── CG.3 the retired task-scale `current: T<n>`: the divergence that routes it to its refusal ──
# run_open calls `T<n>` an open run while the FILL gate withholds on it. Since wave-31 (one ledger
# shape, D2; A-orch-52) `T<n>` is no step at any scale, and the pair answer two questions on
# purpose: run_open keeps the retired plan OPEN so launch-sync, the stop wall and the tick reach it
# and refuse it by name (AC-1.2's `NOT-RECORDED … is not numeric`), and the FILL gate, which has no
# number to compare, fills nothing. A change that closed it would skip such a plan in silence, so
# it must turn this red.
for CG_T in T1 T5 T23; do
  CG_PLAN="$(cg_plan "$CG_T")"
  expect_eq "CG.3 sched_plan_current withholds on the retired task pointer '$CG_T' (no numbered step)" \
    "" "$(cg_sched_current "$CG_PLAN")"
  expect_eq "CG.3 …while run.sh's run_open keeps '$CG_T' an OPEN run, so its readers refuse it by name" \
    "0" "$(cg_run_open "$CG_PLAN")"
done

# ── CG.4 the discriminator: reverting the letter-strip splits the pair (proves CG.1 can go red) ──
# The pre-fix bug, planted. A copy of session-poker.sh with ONLY the a/b-strip line reverted
# to a bare assignment — the exact shape this section would have caught before T6.
CG_MUT="$SANDBOX/fx/cg/session-poker-nostrip.sh"
anchor insert hooks/poker/tick.sh '  step="${current%[ab]}"'
LC_ALL=C awk '{
  if ($0 == "  step=\"${current%[ab]}\"") { print "  step=\"$current\"" } else { print }
}' "$CG2_PARTS/tick.sh" > "$CG_MUT"
expect_eq "CG.4 the mutant differs from the shipped tick by exactly the strip line" \
  "1" "$(diff "$CG2_PARTS/tick.sh" "$CG_MUT" | grep -c '^< ')"
cg_sched_current_mut() {  # <plan path> -> sched_plan_current's answer off the MUTANT copy
  ( . "$RUN_LIB" >/dev/null 2>&1            # ditto: the mutant is a poker copy, not a lib copy
    . "$FILL_LIB" >/dev/null 2>&1
    eval "$(awk -v n=_sched_plan_current_field \
      '$0 ~ "^" n "\\(\\)" {f=1} f{print; if ($0=="}") exit}' "$CG_MUT")"
    eval "$(awk -v n=sched_plan_current \
      '$0 ~ "^" n "\\(\\)" {f=1} f{print; if ($0=="}") exit}' "$CG_MUT")"
    sched_plan_current "$1" ) 2>/dev/null
}
CG_PLAN_3B="$(cg_plan 3b)"
expect_eq "CG.4 …the mutant copy rejects current: 3b as unreadable (the pre-fix bug)" \
  "" "$(cg_sched_current_mut "$CG_PLAN_3B")"
expect_eq "CG.4 …while the shipped file still reads it as step 3 — CG.1 discriminates" \
  "3" "$(cg_sched_current "$CG_PLAN_3B")"


# ============================================================
section "S15 — landing-swept/v1: one writer, pinned to a captured marker"
# ============================================================
#
# THE OWNERSHIP-TABLE ROW (spec AC-26; research-code-map §2.c): hooks/landing-gate.sh's
# originator, `swept_marker_write`, is pinned here against tests/fixtures/landing-swept.captured
# — a real marker taken from a live sweep on this machine
# (roster-84f06e58-9262-4c7f-a199-ca77c24a332e.state, name=research-code-map, MET).
# hooks/session-poker.sh's `adopt_copy_marker` never calls the writer (its job is to relay a
# line the originator already wrote, verbatim) — what it shares is the `SWEPT_SCHEMA`
# constant, so §S15b below pins the two hooks' copies of that constant to agree, byte for
# byte, rather than sourcing one file: two separate hook PROCESSES have no shared memory to
# source an in-process value from, the same reason payload/scripts/lib/loader.sh's own block
# is duplicated-but-pinned rather than sourced.
#
# EXTRACTED, NOT SOURCED FROM A LIB (see tests/lib/swept-marker.sh's own header for why: a
# hook copied out of the tree, as several sections above already do, resolves its
# BIONIC_LIB_WANT files through the loader's registry/cache fallback — whatever was last
# LANDED, not this worktree's uncommitted tree). The real source, `eval`'d, real call — the
# same `field1_via`/`field2_via` idiom this file already uses.
#
# BY KEY, NEVER BY POSITION. The captured line's five fields are read out with the same
# by-key idiom every production reader uses, so a reordering upstream cannot pass this pin
# by accident — only the shared writer producing the identical byte sequence can.

S15_LG="$PARTY_LG_SRC"
S15_PK="$PARTY_PK"
S15_CAPTURED="$REPO_ROOT/tests/fixtures/landing-swept.captured"
S15_LINE="$(cat "$S15_CAPTURED")"

s15_field() { printf '%s' "$1" | tr '|' '\n' | grep "^$2=" | head -1 | cut -d= -f2-; }
S15_AT="$(s15_field "$S15_LINE" at)"
S15_SID="$(s15_field "$S15_LINE" session)"
S15_NAME="$(s15_field "$S15_LINE" name)"
S15_AID="$(s15_field "$S15_LINE" agent_id)"
S15_STATE="$(s15_field "$S15_LINE" state)"

s15_write() {  # <hook file> <roster file> <at> <session> <name> <agent id> <state>
  ( eval "$(grep -m1 '^SWEPT_SCHEMA=' "$1")"
    eval "$(awk '/^swept_marker_write\(\)/,/^\}/' "$1")"
    swept_marker_write "$2" "$3" "$4" "$5" "$6" "$7" ) 2>/dev/null
}

S15_OUT="$SANDBOX/s15-roster.state"
s15_write "$S15_LG" "$S15_OUT" "$S15_AT" "$S15_SID" "$S15_NAME" "$S15_AID" "$S15_STATE"
expect_eq "S15 the shared writer reproduces the captured marker byte for byte" \
  "$S15_LINE" "$(cat "$S15_OUT" 2>/dev/null)"

# THE DISCRIMINATOR — one field doctored, and the pin must go red. A copy of the hook with
# `state=%s` in the writer's printf format replaced by the literal `state=MUTATED`, so every
# marker it writes carries the wrong state regardless of what it is called with — a
# plausible schema drift, not damage. The shipped hook is never touched.
S15_MUT="$SANDBOX/s15-landing-gate-mutant.sh"
anchor file payload/scripts/lib/stop.sh 'state=%s'
awk '{ gsub(/state=%s/, "state=MUTATED"); print }' "$S15_LG" > "$S15_MUT"

S15_MUT_OUT="$SANDBOX/s15-roster-mutant.state"
s15_write "$S15_MUT" "$S15_MUT_OUT" "$S15_AT" "$S15_SID" "$S15_NAME" "$S15_AID" "$S15_STATE"
expect_eq "S15 …the mutant's output is NOT the captured shape (the pin discriminates)" \
  "no" "$([ "$(cat "$S15_MUT_OUT" 2>/dev/null)" = "$S15_LINE" ] && echo yes || echo no)"
expect_contains "S15 …the real state value nowhere survives the mutant — it is truly overwritten" \
  "state=MUTATED" "$(cat "$S15_MUT_OUT" 2>/dev/null)"

# ---- §S15b — the constant the two hooks share, pinned to agree ----
#
# hooks/session-poker.sh's `adopt_copy_marker` never calls the writer above; it shares only
# the schema NAME, each hook carrying its own `SWEPT_SCHEMA=` assignment line. A rename on
# one side and not the other is exactly the drift research-code-map §2.c warned a
# constant-by-NAME grep can miss — this pins the two LINES, not just the grep, to agree.
S15_LG_SCHEMA_LINE="$(grep -m1 '^SWEPT_SCHEMA=' "$S15_LG")"
S15_PK_SCHEMA_LINE="$(grep -m1 '^SWEPT_SCHEMA=' "$S15_PK")"
expect_eq "S15b payload/scripts/lib/stop.sh declares the constant" \
  'SWEPT_SCHEMA="landing-swept/v1"' "$S15_LG_SCHEMA_LINE"
expect_eq "S15b …and hooks/session-poker.sh's copy agrees, byte for byte" \
  "$S15_LG_SCHEMA_LINE" "$S15_PK_SCHEMA_LINE"

# ============================================================
section "S13 — the suite budget: the brief's own set, one row writer, one alphabet"
# ============================================================
#
# (wave-01 verification-cannot-lie, S13; spec AC-20/AC-21; design ledger D2. The derivation
# side is gone: wave-31 T2, REQ-4 AC-4.2 deleted the file-to-suite map, and the budget is the
# set the brief names.)
#
# TWO FILES HAVE TO AGREE ABOUT ONE SET, and neither can see the other:
#
#   payload/scripts/lib/brief.sh        RECORDS it, the brief's `Suites:` tokens as basenames
#   payload/scripts/lib/walls.sh        ENFORCES it, against basenames read out of a command
#
# What is pinned here is the SEAM: the grammar's own lift, driven over a `Suites:` line in
# every spelling a brief uses, answering in the alphabet the guard compares in.

S13_DP="$BIONIC_HOOKS_DIR/dispatch-preflight.sh"
# THE BUDGET ARM'S READER IS IN THE LIBRARY NOW (T23) — `wall_background_suite_guard` in
# payload/scripts/lib/walls.sh, at column zero like the rest of the carried bodies, so the
# `^`-anchored extractions below still find it.
S13_BG="$BIONIC_HOOKS_DIR/../payload/scripts/lib/walls.sh"
[ -r "$S13_BG" ] || S13_BG="$BIONIC_HOOKS_DIR/../scripts/lib/walls.sh"
S13_ROSTER_LIB="$BIONIC_HOOKS_DIR/../payload/scripts/lib/roster.sh"
[ -r "$S13_ROSTER_LIB" ] || S13_ROSTER_LIB="$BIONIC_HOOKS_DIR/../scripts/lib/roster.sh"
S13_CMDCLASS="$BIONIC_HOOKS_DIR/../payload/scripts/lib/cmd-class.sh"
[ -r "$S13_CMDCLASS" ] || S13_CMDCLASS="$BIONIC_HOOKS_DIR/../scripts/lib/cmd-class.sh"
# THE CONTRACT GRAMMAR (wave-20 T6; REQ-4, Δ10): the dispatch wall, `amend` and `task-add` all
# record the set `brief_validate_fields` builds, so that is the file this pin drives.
S13_HOOK="$BIONIC_HOOKS_DIR/../payload/scripts/lib/brief.sh"
[ -r "$S13_HOOK" ] || S13_HOOK="$BIONIC_HOOKS_DIR/../scripts/lib/brief.sh"
expect_eq "S13.2 the library this section reads is present" "yes" \
  "$([ -r "$S13_HOOK" ] && echo yes || echo no)"

# --- §S13.2 the set the row records is the brief's own tokens, as basenames ---
#
# Driven through the grammar the dispatch wall calls, over one `Suites:` line carrying the
# three spellings a brief uses for a suite (path-relative, `./`-prefixed, absolute). The set
# `brief_validate_fields` hands the row writer is the lift's, once each, as basenames.
s13_set() {  # <Suites: span> -> "<BRIEF_SUITES_ALLOWED>|<BRIEF_SUITES_SOURCE>"
  bash -c '
    . "$1" || exit 9
    sink() { :; }
    brief_validate_fields "$(lift_contract_fields "Suites: $2" implementor)" implementor "$3" sink >/dev/null 2>&1
    printf "%s|%s" "${BRIEF_SUITES_ALLOWED-}" "${BRIEF_SUITES_SOURCE-}"
  ' _ "$S13_HOOK" "$1" "$SANDBOX" 2>/dev/null
}
S13_GOT="$(s13_set "tests/cmd-class.test.sh, ./tests/walls.test.sh, $REPO_ROOT/tests/brief-x.test.sh, tests/cmd-class.test.sh")"
expect_eq "S13.2 the recorded set is the brief's tokens as basenames, once each, declared" \
  "cmd-class.test.sh walls.test.sh brief-x.test.sh|declared" "$S13_GOT"
S13_SET="${S13_GOT%%|*}"
expect_eq "S13.2 …carrying no path, no tab and no duplicate" "0" \
  "$(printf '%s\n' "$S13_SET" | tr ' ' '\n' | awk '/\// || /\t/ { n++ } END { print n + 0 }')"
# THE MUTATION: a different Suites: line lands a different set, so the row above is the brief's
# answer and not a constant.
expect_eq "S13.2 …and a different Suites: line records a different set" \
  "gamma.test.sh|declared" "$(s13_set "tests/gamma.test.sh")"

# --- §S13.3 the guard compares in that same alphabet ---
#
# `cmd_suite_targets` is the reader on the enforcement side. Every basename the grammar
# just recorded must be a name it can produce too, from the command a writer would type —
# otherwise a suite on the budget is refused by the wall that granted it.
S13_TARGETS_OK=0
for _s13_b in $S13_SET; do
  _s13_got=$(bash -c '
    set -uo pipefail
    . "$1" || exit 1
    cmd_suite_targets "bash tests/$2"
  ' _ "$S13_CMDCLASS" "$_s13_b" 2>/dev/null)
  [ "$_s13_got" = "$_s13_b" ] || S13_TARGETS_OK=$((S13_TARGETS_OK + 1))
done
expect_eq "S13.3 every recorded basename round-trips through cmd_suite_targets" "0" "$S13_TARGETS_OK"
# NON-VACUITY: the loop really ran over a non-empty set.
expect_eq "S13.3 …over a set with something in it" "0" \
  "$([ -n "$S13_SET" ] && echo 0 || echo 1)"

# --- §S13.4 the three fields go through the ONE row writer, from both call sites ---
#
# §RA.2 pins that the row has one writer. This pins that the fields S13 added did not
# quietly acquire a second one: neither hook may hold a `suites_allowed=` ASSEMBLER of its
# own, and the library must know all three keys. A hook that built the field into a
# format string beside the call would pass §RA.2 (the captured rows carry none of the
# three) and be invisible until a reader met a row with the key in the wrong place.
#
# THREE FILES, NAMED INDIVIDUALLY — this is not a directory scan, and a fourth file could
# spell the assembler shape and this pin would never see it:
#   hooks/dispatch-preflight.sh ($S13_DP)                 must not assemble the row segment
#   hooks/session-poker.sh                                must not assemble the row segment
#   payload/scripts/lib/roster.sh ($S13_ROSTER_LIB)        is the one file that may
# THE ROW-BUILDING SPELLING IS `|suites_allowed=[$%]` — the pipe-prefixed key immediately
# followed by the sigil that opens a splice, either `$` (a variable/command-substitution
# assembler, e.g. `out="$out|suites_allowed=$suites_allowed"`) or `%` (a printf format-string
# assembler, e.g. `printf '|suites_allowed=%s' "$x"`). A plain literal-substring grep for
# `|suites_allowed=` cannot tell any of these apart from a `case`/substring PRESENCE test
# spelling the same key — `*"|suites_allowed="*`, no trailing sigil — and T7's `extend`
# tripped exactly that false positive and had to route its own presence check through a
# generic, indirected helper (`row_has_key`, session-poker.sh) purely to dodge this pin
# (ideas row 11). The shape-aware grep below reads 0 on a presence test and 1 on either
# assembler shape, so the dodge is no longer needed — `row_has_key` keeps its shape on its
# own merits, not because of this pin.
# SPELLING WIDENED (T9, R4): the prior spelling, `=[^=]*\|suites_allowed=\$`, required an
# `=` sign somewhere before the pipe as well as a literal `$` right after the key — a shape
# that a concatenation assembler (`row="${row}|suites_allowed=$sa"`) happens to have but a
# `printf` assembler does not (`printf '|suites_allowed=%s' "$x"` has no `=` before the pipe
# and closes with `%`, not `$`). That left two of the three legitimate assembler shapes
# invisible to the pin (AC-13.1's own eval fixture pins a `printf` assembler at 1, and the
# old grep read 0 on it). The new spelling drops the leading `=[^=]*` requirement and widens
# the trailing sigil to `[$%]`, so it reads 1 on all three assembler shapes — concatenation,
# `$(...)`  variable splice, and `printf` — while still reading 0 on the presence test, whose
# trailing character is a quote, not a sigil.
# The paired POSITIVE: both writers do pass the key by name, so the two zeros above are
# "no second speller" and not "nobody writes it".
# SPELLING UPDATED (T9, REQ-9/D7): `clean()` now takes the field name so the two
# LIST-valued fields it exempts from the 400-char cut (`suites_allowed=`, `files=`) survive
# whole; the call site's literal text changed, the property this pin checks (one group,
# one call) did not.
# SPELLING UPDATED AGAIN (wave-37 T7, D11): the list fields are the set `ROSTER_LIST_FIELDS` names
# once, and `adopt_write_row` passes each one the source row carries by name through the same
# `clean` in one loop; the group rule (a stated group lacking `files=` or `suites_allowed=` gets the
# empty member, and `suites_source=` goes with them) is two lines beside it. Both are counted.

# MUTATION (§N-shaped, :3572-3588) — the shape-aware grep must actually REJECT a planted
# assembler, not merely fail to see one that was never there. TWO copies of
# dispatch-preflight.sh are doctored in the SANDBOX — never in the tree — one appending a
# second, illegitimate `suites_allowed=` CONCATENATION assembler line and one appending a
# `printf` FORMAT-STRING assembler line (R4: the shape the widened grep exists to catch);
# the same grep that reads 0 on the real tree above must read 1 on both doctored copies.
mkdir -p "$SANDBOX/fx"
S13_MUT_DP="$SANDBOX/fx/dispatch-preflight-planted-assembler.sh"
{ cat "$S13_DP"; printf '%s\n' 'out="$out|suites_allowed=$suites_allowed"'; } > "$S13_MUT_DP"
S13_MUT_DP_PRINTF="$SANDBOX/fx/dispatch-preflight-planted-printf-assembler.sh"
{ cat "$S13_DP"; printf '%s\n' 'printf '"'"'|suites_allowed=%s'"'"' "$suites_allowed"'; } > "$S13_MUT_DP_PRINTF"
expect_ne "S13.4 mutation: the planted copy really differs (not a byte-identical copy)" \
  "$(cat "$S13_DP")" "$(cat "$S13_MUT_DP")"
expect_ne "S13.4 mutation: …and so does the printf-assembler copy" \
  "$(cat "$S13_DP")" "$(cat "$S13_MUT_DP_PRINTF")"
expect_eq "S13.4 mutation: the shape-aware grep is red on the concatenation copy" "1" \
  "$(grep -cE '\|suites_allowed=[$%]' "$S13_MUT_DP")"
expect_eq "S13.4 mutation: …and red on the printf copy too (R4)" "1" \
  "$(grep -cE '\|suites_allowed=[$%]' "$S13_MUT_DP_PRINTF")"

# --- §S13.5 the field the wall writes is the field the guard reads ---
#
# One key name, two files, neither able to see the other. A rename on either side is the
# whole failure mode, and it is silent: the guard would find no budget and stand aside for
# every named suite in the fleet.
expect_eq "S13.5 the guard reads the key the wall writes" "0" \
  "$(grep -qF 'suites_allowed=' "$S13_BG" && echo 0 || echo 1)"
# DROPPED (wave-22 T9, review fix candidate 7; critic Scope). A second row here counted the
# source text of the arm's prefix strip (`${_bseg#suites_allowed=}`). It pinned how the arm
# spells the read, not what the arm does: a rename of the strip's variable turned it red with
# no change in behaviour. That the arm reads the key the wall writes is proven behaviourally,
# by bash-walls §15 and by §AM2 here (an amended `suites_allowed=` is admitted by the arm).

# ============================================================
# --- S18 — landing-gate.sh reconciles the diff against Files:, once (spec AC-22) ---
#
# ONE reader of a row's `files=` for reconciliation, ONE place that computes the diff, ONE
# row -> worktree mapping (never re-derived). Neither side reads an `impact-command` key any
# more (wave-31 T2 the dispatch side, T23 the landing side; REQ-4 AC-4.2): S18.3 pins both.
# The reconciliation is `stop_landing_gate`'s now (epic-23 wave-11, T12): the diff and the
# shared mapping moved into payload/scripts/lib/stop.sh with the rest of the sweep. One owner
# still, at a new address.
S18_LG="${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/stop.sh"
S18_WT_LIB_DIR="$BIONIC_HOOKS_DIR/../payload/scripts/lib"

# --- §S18.1 exactly one file reconciles a diff against a row's files=, and it is lib/stop.sh ---
# The claim is unchanged — ONE owner of the reconciliation — and the address moved with the
# sweep at T12, so the files are counted over the library and a stray copy left behind under
# hooks/ fails the second row below.
# A RECONCILER IS A FILE THAT DOES BOTH HALVES (review 9 follow-up, widened at review 11 S2): it
# lists changed paths, by any of git's forms for it (`diff --name-only`, `--name-status`,
# `--numstat`, `diff --stat`, `status --porcelain`), AND it READS a roster row's `files=` key, by any of the
# repo's read forms (the quoted literal a row reader compares against, a `files=*)` case arm, or a
# `*_field … files` key reader). Writing the key is not reading it, so brief.sh's
# `print "files=" v` counts only because brief.sh lists no changed paths, and worktree.sh's
# `printf 'files=%s'` matches no read form. A path list alone is not one either: worktree.sh
# diffs a tree against the landed work to find the files both changed, and never reads a row.
# WHAT A TEXT CHECK PER FILE CANNOT SEE (review 15 F5): a reconciler whose two halves sit in two
# files (the path list from a helper in one, the key read in the other, review 15's case E), and
# a key read in a spelling none of the read forms lists (an awk `index($i, "files=")`). Neither
# file then does both halves. Review is what catches those; the rows below do not pretend to.
# A TREE LISTING IS NOT A CHANGE LIST (wave-38 T33, A-T33-3). `git ls-tree --name-only` and `git ls-files` list the
# paths a tree holds, so their words are dropped up to the next | ; & or ) before the forms are read: T21's
# `ls-tree -r --name-only --full-tree HEAD -- "$rel"` in hooks/dispatch-preflight.sh asks whether a path is tracked,
# and a `git diff --name-only` later on the same line is still read.
S18_DIFF_RE='--name-only|--name-status|--numstat|diff --stat|status --porcelain'
S18_READ_RE='"files="|files=\*\)|_field[^)]*[ "]files([^=_A-Za-z0-9]|$)'
s18_changed_lines() {  # <file> -> its lines that list changed paths, by any of the forms, tree listings dropped
  /usr/bin/sed -E 's/ls-(tree|files)[^|;&)]*//g' "$1" | /usr/bin/grep -E -- "$S18_DIFF_RE"
  return 0
}
s18_reconcilers() {  # <dir> -> the .sh files under it that do both halves, one per line
  local _f
  for _f in "$1"/*.sh; do
    [ -f "$_f" ] || continue
    [ -n "$(s18_changed_lines "$_f")" ] && /usr/bin/grep -qE -- "$S18_READ_RE" "$_f" && printf '%s\n' "$_f"
  done
  return 0
}
S18_LIB_DIR="${BIONIC_SCRIPTS_DIR}/payload/scripts/lib"
# No hook computes a name-only diff at all: the reconciliation's diff left hooks/ with the sweep.
# And no hook reconciles by any of the library row's diff forms (review 15 F5): a hook written
# with `--name-status` or `--numstat` passes the --name-only row, and is caught by this one, as
# the planted hook copy below proves.
expect_ne "S18.1 the hooks are read: at least one hook file is there" "0" \
  "$(ls "$BIONIC_HOOKS_DIR"/*.sh 2>/dev/null | grep -c . | tr -d ' ')"
s18_name_only_files() {  # <dir> -> the .sh files under it with a --name-only list of changed paths, one per line
  local _f
  for _f in "$1"/*.sh; do
    [ -f "$_f" ] || continue
    s18_changed_lines "$_f" | /usr/bin/grep -qF -- '--name-only' && printf '%s\n' "$_f"
  done
  return 0
}
expect_eq "S18.1 …and no hook file carries a --name-only diff" "" "$(s18_name_only_files "$BIONIC_HOOKS_DIR")"
# The extractor on one planted copy of hooks/: a --name-only diff is read, and a tree listing beside it is not.
S18_HK="$SANDBOX/s18-hooks"; rm -rf "$S18_HK"; mkdir -p "$S18_HK"; cp "$BIONIC_HOOKS_DIR"/*.sh "$S18_HK/"
printf '#!/bin/bash\nchanged="$(git diff --name-only "$1..HEAD")"\n' > "$S18_HK/planted-diff.sh"
printf '#!/bin/bash\ngit ls-tree -r --name-only --full-tree HEAD -- "$1" | head -1\n' > "$S18_HK/planted-listing.sh"
expect_eq "S18.1 the --name-only extractor reads a planted diff in a copy of hooks/ (its positive)" \
  "$S18_HK/planted-diff.sh" "$(s18_name_only_files "$S18_HK")"
expect_eq "S18.1 …and the planted tree listing in that copy is not read (it lists no change)" "" \
  "$(s18_name_only_files "$S18_HK" | /usr/bin/grep -F planted-listing)"
expect_eq "S18.1 …and no hook file reconciles, by any of the library row's diff forms" "" \
  "$(s18_reconcilers "$BIONIC_HOOKS_DIR")"

# A SECOND RECONCILIATION IS RED, written the ways a real one would be (review 11 S2, cases A to
# C), never in the detector's own spelling: each is one added file in a copy of the library, and
# the exactly-one row asked of that copy reads 2. No source is doctored, so there is no source
# line for §S19.4's anchor to hold: the added file is written through `$s18_new`, a name its
# cross-gate site pattern does not read as a mutant.
s18_second() {  # <label> <body> [dir] -> "<parses> <count>" for a copy of <dir> (the library) plus recon2.sh
  local s18_new="$S18_MUT/recon2.sh"
  rm -rf "$S18_MUT"; mkdir -p "$S18_MUT"; cp "${3:-$S18_LIB_DIR}"/*.sh "$S18_MUT/"
  printf '#!/bin/bash\n%s\n' "$2" > "$s18_new"
  printf '%s %s' "$(bash -n "$s18_new" 2>/dev/null && echo yes || echo no)" \
    "$(s18_reconcilers "$S18_MUT" | grep -c . | tr -d ' ')"
}
S18_MUT="$SANDBOX/s18-lib"
expect_eq "S18.1 a second reconciler through the repo's own key reader (case A) reads 2" "yes 2" \
  "$(s18_second A 'recon2() { local decl changed; decl="$(brief_field "$1" files)"; changed="$(git diff --name-only "$2..HEAD")"; printf "%s\n" $changed | grep -vxF "$decl"; }')"
expect_eq "S18.1 …through a --name-status diff and a quoted-key read (case B) reads 2" "yes 2" \
  "$(s18_second B 'recon2() { local row="$1" decl; decl="${row##*"files="}"; git diff --name-status "$2..HEAD" | cut -f2 | grep -vxF "$decl"; }')"
expect_eq "S18.1 …through status --porcelain (case C) reads 2" "yes 2" \
  "$(s18_second C 'recon2() { local row="$1" decl; decl="${row##*"files="}"; git status --porcelain | cut -c4- | grep -vxF "$decl"; }')"
expect_eq "S18.1 …through a --numstat diff (review 15 F5) reads 2" "yes 2" \
  "$(s18_second N 'recon2() { local decl; decl="${1##*"files="}"; git diff --numstat "$2..HEAD" | cut -f3 | grep -vxF "$decl"; }')"
# The hooks row on a planted hook: a copy of hooks/ plus one --name-status reconciler (case B,
# which carries no --name-only) is read as one reconciler, where the real hooks read none.
expect_eq "S18.1 a hook reconciler through a --name-status diff is caught by the hooks row" "yes 1" \
  "$(s18_second HB 'recon2() { local row="$1" decl; decl="${row##*"files="}"; git diff --name-status "$2..HEAD" | cut -f2 | grep -vxF "$decl"; }' "$BIONIC_HOOKS_DIR")"
# The same copy with a file that only WRITES the key stays at 1.
expect_eq "S18.1 …while a file that lists changed paths and only writes the key reads 1" "yes 1" \
  "$(s18_second W 'recon2() { git diff --name-only "$1..HEAD" | while read -r f; do printf "files=%s\n" "$f"; done; }')"

# --- §S18.2 the row -> worktree mapping has ONE definition (worktree.sh's `worktree_for_row`,
# payload/scripts/lib/worktree.sh's own docblock: "a second spelling of it there is a second
# definition of which tree belongs to whom") and landing-gate.sh calls it rather than
# re-deriving the mapping itself ---
expect_eq "S18.2 worktree_for_row is defined in exactly one library file" "1" \
  "$(grep -l '^worktree_for_row()' "$S18_WT_LIB_DIR"/*.sh | wc -l | tr -d ' ')"
expect_eq "S18.2 …and it is worktree.sh" "1" \
  "$(grep -l '^worktree_for_row()' "$S18_WT_LIB_DIR"/*.sh | grep -c 'worktree\.sh$')"
# RE-POINTED (epic-23 wave-11-lean-spine, REQ-1f). This was the only BYTE-EXACT
# BIONIC_LIB_WANT string in the tree, and it broke the moment the gate declared one more
# library — which is the wrong thing for it to be sensitive to. What S18.2 owns is that the
# dependency it just proved the gate CALLS is also DECLARED, so the line is re-derived from
# the file and the membership of `worktree.sh` in it is the assertion. The anchor keeps it
# honest: a gate with no WANT line at all fails loudly rather than comparing empty strings.
# THE DECLARATION IS THE HOOK'S, THE CALL IS THE LIBRARY'S (T12). `BIONIC_LIB_WANT` is
# what the loader reads, so it lives in the process — hooks/stop.sh — while the call it
# has to cover lives in the function the process runs.
S18_WANT=$(sed -n 's/^BIONIC_LIB_WANT="\(.*\)"$/\1/p' "$BIONIC_HOOKS_DIR/stop.sh" | head -1)
expect_nonempty "S18.2 hooks/stop.sh declares a BIONIC_LIB_WANT line at all" "$S18_WANT"

# --- §S18.3 no reader of the map's key, on either side (wave-31 T2, T23; REQ-4 AC-4.2) ---
# The map is deleted: a brief names its suites, so neither the dispatch wall nor the landing
# path asks `impact-command:` for any. ONE EXTRACTOR, a `config_value` read of a named key in
# either spelling (quoted or bare), proved on a read that stays — the landing's release-check —
# before it is asked for the deleted key's reads. proof.sh's floor read is T25's (D3) and is
# not counted here.
s18_config_reads() {  # <file> <key> -> how many lines read that key through config_value
  /usr/bin/grep -cE "config_value .*[[:space:]]\"?$2\"?[[:space:]]+\"\"" "$1" 2>/dev/null | tr -d ' '
}
# ============================================================
section "S13b — one run normaliser on both sides of the row (wave-20 T4; REQ-7, D7)"
# ============================================================
#
# THE SAME SEAM AS S13, FOR THE OTHER BUDGET FIELD. `re_executes=` is WRITTEN by the
# dispatch lift (`lift_contract_fields`, its `collapse()`) and COMPARED by the budget arm to
# the run the claim reader built (payload/scripts/lib/cmd-class.sh, LAST_RUN). Each side has
# its own suite and each can pass while the two spell one run two ways — which is exactly how
# `npx jest x 2>&1 | tee log` came to be refused for the run its brief declared (triage-B
# B1). Pinned here: the lift, run with the library it loads, stores the run the claim reader
# reads off every redirected spelling of it.
#
# THE LIFT IS A LIBRARY NOW (wave-20 T6; REQ-4, Δ10), so this section sources
# payload/scripts/lib/brief.sh — the one file every contract door calls — where it used to
# lift the function's text out of hooks/dispatch-preflight.sh between two anchors. Sourcing
# it alone also proves it brings in cmd-class.sh for itself: nothing else is loaded here.
S13B_LIB="$BIONIC_HOOKS_DIR/../payload/scripts/lib/brief.sh"
[ -r "$S13B_LIB" ] || S13B_LIB="$BIONIC_HOOKS_DIR/../scripts/lib/brief.sh"
s13b_lift_runs() {  # <brief text> -> the lifted re_executes= value
  bash -c '. "$1" || exit 1; lift_contract_fields "$2" | sed -n "s/^re_executes=//p"' \
    _ "$S13B_LIB" "$1" 2>&1
}
s13b_claim_run() {  # <command> -> the first claim's run column
  bash -c '. "$1" || exit 1; cmd_suite_claims "$2" | awk -F"\t" "NR == 1 { print \$3 }"' \
    _ "$S13_CMDCLASS" "$1" 2>&1
}
S13B_BT='`'
S13B_RUN="npx jest --testPathPatterns 'x'"
S13B_STORED=$(s13b_lift_runs "Re-executes: ${S13B_BT}npx    jest  --testPathPatterns 'x'${S13B_BT}")
expect_eq "S13b the lift stores the declared run, collapsed, marks kept (non-vacuity)" \
  "${S13B_BT}${S13B_RUN}${S13B_BT}" "$S13B_STORED"
for _sp in "2>&1" "> /tmp/s13b.log 2>&1" "&> /tmp/s13b.log" "2>&1 | tee /tmp/s13b.log" "|& tee /tmp/s13b.log" "|| true"; do
  expect_eq "S13b the claim of the run redirected [$_sp] is the run the lift stored" \
    "$S13B_STORED" "${S13B_BT}$(s13b_claim_run "$S13B_RUN $_sp")${S13B_BT}"
done
# THE DISCRIMINATOR: a different run, however redirected, is a different stored value.
expect_ne "S13b …and a narrower run redirected the same way is NOT the stored one" \
  "$S13B_STORED" "${S13B_BT}$(s13b_claim_run 'npx jest 2>&1 | tee /tmp/s13b.log')${S13B_BT}"
# AND THE DECLARED SIDE'S DECODE (walls.sh) HOLDS THE SAME RULE: a stored field is already
# normal, so normalising it again changes nothing.
expect_eq "S13b the walls-side normaliser leaves a lifted field byte-identical" "$S13B_STORED" \
  "$(bash -c '. "$1" || exit 1; cmd_runs_norm "$2"' _ "$S13_CMDCLASS" "$S13B_STORED" 2>&1)"

# ============================================================
section "S19 — THE MUTATION ANCHOR: one call, every doctoring site (AC-29/AC-30/AC-31)"
# ============================================================
#
# WHAT THIS SECTION OWNS. A suite that proves an assertion discriminates builds a
# mutant by stripping or rewriting one line of a shipped source with `grep -v` or
# `sed`. The pattern it strips is the anchor, and when the anchored line moves the
# "mutant" comes out byte-identical to the shipped file — every behavioural row
# under it then goes green against a fixture that was never mutated. Before this
# wave every one of these sites carried its own precondition or none: a `cmp -s`
# against the doctored copy, a count-difference row, or nothing at all. The
# research code map's census found 24 of them; the real number in this tree is 49
# call sites over four suites, because the census read only `grep -v` in this suite
# and missed every `sed`/`awk` mutant tree here plus
# the doctoring `agent-context-guard` and `landing-gate` each carry. Every one of
# them now goes through ONE spelling — the framework's `anchor` — and this section
# is the wall that keeps them there.
#
# THE BRACKETS IN THE PATTERN BELOW ARE DELIBERATE. This file is itself one of the
# files the absence sweep reads, so a pattern spelling the idiom literally would
# match its own definition and could never go green. `[a]nchor` matches "anchor"
# and does not match "[a]nchor", which is what lets the sweep name the idiom out
# loud and still be a real sweep.

S19_TESTS_DIR="$REPO_ROOT/tests"
S19_ASSERT="$S19_TESTS_DIR/lib/assert.sh"

# The four hand-rolled precondition idioms this wave removed, as one ERE.
S19_HANDROLLED='cmp -[s] [^;]*DOCTORED|the [a]nchor has not moved|the (sed|grep -v) targets? matched [n]othing|mutation [a]pplies'

# --- §S19.1 the framework owns `anchor`, once ---
expect_eq "S19.1 anchor is defined in exactly one file under tests/" "1" \
  "$(/usr/bin/grep -lE '^anchor\(\)' "$S19_TESTS_DIR"/lib/*.sh "$S19_TESTS_DIR"/*.test.sh 2>/dev/null | wc -l | tr -d ' ')"

# --- §S19.2 ABSENCE: no suite hand-rolls its own mutation precondition ---
#
# NO EXCEPTIONS, AND NO NARROWED PATTERN. This row carried a named waiver while two
# doctoring sites the code map's 24-site census never found — `mutate_guard` in
# `tests/agent-context-guard.test.sh` and the inverted-guard awk in
# `tests/landing-gate.test.sh` — sat outside the declared set of the task that
# built `anchor`. Both are routed now, so the waiver is deleted and the expectation
# is EMPTY: the sweep reads every suite in tests/, and a hand-rolled precondition
# reappearing ANYWHERE turns this row red and names the file and the hit count.
S19_HAND_HITS="$(cd "$S19_TESTS_DIR" && /usr/bin/grep -cE -- "$S19_HANDROLLED" ./*.test.sh 2>/dev/null \
  | /usr/bin/grep -v ':0$' | sed 's|^\./||' | tr '\n' ' ' | sed 's/ $//')"

# THE PAIRED POSITIVE, and the discriminating one: the same sweep over a file with ONE of
# those idioms planted must name that file. Without this row, §S19.2 would pass just as
# loudly against a pattern that matches nothing at all.
S19_SB="$SANDBOX/s19"
mkdir -p "$S19_SB"
# built with %s so this line does not itself spell the idiom it plants
printf 'if cmp -%s "$SKILL_MD" "$DOCTORED_REPLANTED"; then no "x" "the %s target matched nothing"; fi\n' \
  s sed >> "$S19_SB/replanted.test.sh"

# --- §S19.3 retired (wave-24): six exact-count pins on `anchor` calls (per-suite sites and calls,
# this suite, agent-context-guard, landing-gate, and their total). An exact count goes red on
# every legitimate new mutant and is repaired by retyping the number, so it tested the author's
# memory, not the tree. The relation it stood for is derived below, in §S19.4, with its paired
# positive; §S19.2 holds the absence side across every suite.

# --- §S19.4 every doctored copy is anchored, suite by suite ---
# Each doctoring suite gets its own site pattern, and a pattern that finds no site is RED
# here rather than a silent pass of the relation below it.
#
# THE ANCHOR MAY SIT ANYWHERE EARLIER IN THE SITE'S BLOCK (the lines since the last
# blank one), not within a fixed distance: one anchor legitimately guards several
# mutants written back to back, and a multi-line sed or awk puts the site line far
# below the call it belongs to. Comment lines are never sites.
s19_block_sites() {  # s19_block_sites <suite> <site-ERE> -> "<sites> <unanchored>"
  S19_SITE_RE="$2" awk '
    /^[ \t]*$/ { anchored = 0; next }
    /^[ \t]*#/ { next }
    /^[ \t]*anchor[ \t]/ { anchored = 1 }
    $0 ~ ENVIRON["S19_SITE_RE"] { sites++; if (!anchored) bare++ }
    END { print sites + 0, bare + 0 }
  ' "$1"
}

# --- §S19.4 landing-gate: every doctored copy of the gate is anchored ---
# landing-gate doctors one source, the gate it loads, so a site is any line writing a
# copy of "$GATE_SRC" to a file. THE PLANTED DEFECTS, on copies: a bare site, a doctored
# copy with no anchor in its block, must be named; and a copy whose sites no longer carry
# the pattern's target must report no site, which is what turns the at-least-one row RED.
S19_LG="$S19_TESTS_DIR/landing-gate.test.sh"
S19_LG_SITE='"\$GATE_SRC" > "'
S19_LG_REAL="$(s19_block_sites "$S19_LG" "$S19_LG_SITE")"
S19_LG_REAL_SITES="${S19_LG_REAL%% *}"
expect_eq "S19.4 the landing-gate site pattern finds at least one doctored site" "yes" \
  "$([ "${S19_LG_REAL_SITES:-0}" -ge 1 ] 2>/dev/null && echo yes || echo no)"
expect_eq "S19.4 every landing-gate doctoring site is anchored" "0" \
  "${S19_LG_REAL#* }"
cp "$S19_LG" "$S19_SB/lg-bare.test.sh"
# built with %s so this file does not itself carry the site it plants
printf '\nsed %s "$GATE_SRC" %s "$SUPDIR/scripts/lib/bare.sh"\n' "'s/x/y/'" '>' >> "$S19_SB/lg-bare.test.sh"
S19_LG_BARE="$(s19_block_sites "$S19_SB/lg-bare.test.sh" "$S19_LG_SITE")"
expect_eq "S19.4 …and the derivation names a planted bare landing-gate site" "$(( ${S19_LG_REAL#* } + 1 ))" \
  "${S19_LG_BARE#* }"
S19_LG_BARE_SITES="${S19_LG_BARE%% *}"
expect_eq "S19.4 …which the landing-gate pattern counted as one more site (not vacuous)" "1" \
  "$(( ${S19_LG_BARE_SITES:-0} - ${S19_LG_REAL_SITES:-0} ))"
sed 's/"\$GATE_SRC" > "/"$GATE_SRC_GONE" > "/' "$S19_LG" > "$S19_SB/lg-nosite.test.sh"
S19_LG_NONE="$(s19_block_sites "$S19_SB/lg-nosite.test.sh" "$S19_LG_SITE")"
expect_eq "S19.4 …and on it the landing-gate pattern finds no site, so its at-least-one row goes RED" "0" \
  "${S19_LG_NONE%% *}"

# --- §S19.4 cross-gate (this suite): every doctored copy is anchored ---
# This suite doctors many sources, so a site is keyed on the mutant it writes: a quoted
# source redirected into a variable whose name says mutant, doctored or lib (`> "$…MUT…"`,
# `> "$…lib"`). The suite reads ITSELF here, so no line in this section may carry that
# shape: the planted line spells `>` through %s, the sandbox paths go to "$S19_SB/…",
# and the no-site copy rewrites the redirect rather than any one name.
# THE SUITE IS THREE FILES NOW (wave-39 T36): its fixture and its two parts. The scan reads them as the one
# text they were, a blank line between so that no block spans two files.
S19_CG="$S19_SB/cg-all.test.sh"
for _s19f in cross-gate-agreement.prelude.sh cross-gate-agreement-1.test.sh cross-gate-agreement-2.test.sh; do
  cat "$S19_TESTS_DIR/$_s19f"; printf '\n'
done > "$S19_CG"
S19_CG_SITE='"[^"]*" > "\$[A-Za-z0-9_]*(MUT|mut|DOCTOR|lib")'
S19_CG_REAL="$(s19_block_sites "$S19_CG" "$S19_CG_SITE")"
S19_CG_REAL_SITES="${S19_CG_REAL%% *}"
expect_eq "S19.4 the cross-gate site pattern finds at least one doctored site" "yes" \
  "$([ "${S19_CG_REAL_SITES:-0}" -ge 1 ] 2>/dev/null && echo yes || echo no)"
expect_eq "S19.4 every cross-gate doctoring site is anchored" "0" \
  "${S19_CG_REAL#* }"
cp "$S19_CG" "$S19_SB/cg-bare.test.sh"
# built with %s so this file does not itself carry the site it plants
printf '\nsed %s "$PARTY_ER" %s "$S19_PLANT_MUT"\n' "'s/x/y/'" '>' >> "$S19_SB/cg-bare.test.sh"
S19_CG_BARE="$(s19_block_sites "$S19_SB/cg-bare.test.sh" "$S19_CG_SITE")"
expect_eq "S19.4 …and the derivation names a planted bare cross-gate site" "$(( ${S19_CG_REAL#* } + 1 ))" \
  "${S19_CG_BARE#* }"
S19_CG_BARE_SITES="${S19_CG_BARE%% *}"
expect_eq "S19.4 …which the cross-gate pattern counted as one more site (not vacuous)" "1" \
  "$(( ${S19_CG_BARE_SITES:-0} - ${S19_CG_REAL_SITES:-0} ))"
sed 's/" > "/" >> "/g' "$S19_CG" > "$S19_SB/cg-nosite.test.sh"
S19_CG_NONE="$(s19_block_sites "$S19_SB/cg-nosite.test.sh" "$S19_CG_SITE")"
expect_eq "S19.4 …and on it the cross-gate pattern finds no site, so its at-least-one row goes RED" "0" \
  "${S19_CG_NONE%% *}"

# ============================================================
finish
