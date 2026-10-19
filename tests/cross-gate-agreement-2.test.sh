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
cg_extract_fn() {  # <fn-name> -> that function's body text, from session-poker.sh (PARTY_PK)
  awk -v n="$1" '$0 ~ "^" n "\\(\\)" {f=1} f{print; if ($0=="}") exit}' "$PARTY_PK"
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
anchor insert hooks/session-poker.sh '  step="${current%[ab]}"'
LC_ALL=C awk '{
  if ($0 == "  step=\"${current%[ab]}\"") { print "  step=\"$current\"" } else { print }
}' "$PARTY_PK" > "$CG_MUT"
expect_eq "CG.4 the mutant differs from the shipped file by exactly the strip line" \
  "1" "$(diff "$PARTY_PK" "$CG_MUT" | grep -c '^< ')"
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
expect_eq "S15b …the copy is a named constant, not a literal in adopt_copy_marker's own grep" \
  "0" "$(awk '/^adopt_copy_marker\(\)/,/^\}/' "$S15_PK" | grep -cF "grep '^${SWEPT_SCHEMA}|'")"

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
for _s13_key in files suites_allowed suites_source; do
  expect_eq "S13.4 roster.sh knows the key [$_s13_key]" "1" \
    "$(awk '/^roster_row\(\)/,/^\}/' "$S13_ROSTER_LIB" | grep -cE "^ *${_s13_key}\)")"
done
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
expect_eq "S13.4 dispatch-preflight assembles no row segment of its own" "0" \
  "$(grep -cE '\|suites_allowed=[$%]' "$S13_DP")"
expect_eq "S13.4 …and neither does session-poker's adopt" "0" \
  "$(grep -cE '\|suites_allowed=[$%]' "$BIONIC_HOOKS_DIR/session-poker.sh")"
expect_eq "S13.4 …because the one library that may is the one that does" "1" \
  "$(grep -cE '\|suites_allowed=[$%]' "$S13_ROSTER_LIB")"
# The paired POSITIVE: both writers do pass the key by name, so the two zeros above are
# "no second speller" and not "nobody writes it".
expect_eq "S13.4 dispatch-preflight passes suites_allowed= to the writer" "1" \
  "$(grep -c '"suites_allowed=\${SUITES_ALLOWED}"' "$S13_DP")"
# SPELLING UPDATED (T9, REQ-9/D7): `clean()` now takes the field name so the two
# LIST-valued fields it exempts from the 400-char cut (`suites_allowed=`, `files=`) survive
# whole; the call site's literal text changed, the property this pin checks (one group,
# one call) did not.
# SPELLING UPDATED AGAIN (wave-37 T7, D11): the list fields are the set `ROSTER_LIST_FIELDS` names
# once, and `adopt_write_row` passes each one the source row carries by name through the same
# `clean` in one loop; the group rule (a stated group lacking `files=` or `suites_allowed=` gets the
# empty member, and `suites_source=` goes with them) is two lines beside it. Both are counted.
expect_eq "S13.4 …and session-poker builds its three as one group: every list field through clean by name, the group's missing members empty" "1 1 1" \
  "$(grep -c 'LIST_FIELDS_ARGS+=("\$lf=\$(clean "\$(line_field "\$src" "\$lf")" "\$lf")")' "$BIONIC_HOOKS_DIR/session-poker.sh") $(grep -c 'row_has_key "\$src" suites_allowed || LIST_FIELDS_ARGS+=("suites_allowed=")' "$BIONIC_HOOKS_DIR/session-poker.sh") $(grep -c 'LIST_FIELDS_ARGS+=("suites_source=\$(clean "\$ssrc")")' "$BIONIC_HOOKS_DIR/session-poker.sh")"

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
expect_eq "S13.4 mutation: …and stays green on the real tree" "0" \
  "$(grep -cE '\|suites_allowed=[$%]' "$S13_DP")"

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
expect_eq "S18.1 exactly one library file reconciles a diff against a row's files=" "1" \
  "$(s18_reconcilers "$S18_LIB_DIR" | grep -c . | tr -d ' ')"
expect_eq "S18.1 …and it is payload/scripts/lib/stop.sh" "1" \
  "$(s18_reconcilers "$S18_LIB_DIR" | grep -c '/stop\.sh$')"
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
expect_eq "S18.2 lib/stop.sh calls the shared mapping" "1" \
  "$(grep -cF 'worktree_for_row "$repo" "$name"' "$S18_LG")"
expect_eq "S18.2 …and never redefines it" "0" \
  "$(grep -c '^worktree_for_row()' "$S18_LG")"
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
expect_eq "S18.2 …declaring the dependency, per the loader contract" "1" \
  "$(printf '%s' " $S18_WANT " | /usr/bin/grep -c ' worktree\.sh ')"

# --- §S18.3 no reader of the map's key, on either side (wave-31 T2, T23; REQ-4 AC-4.2) ---
# The map is deleted: a brief names its suites, so neither the dispatch wall nor the landing
# path asks `impact-command:` for any. ONE EXTRACTOR, a `config_value` read of a named key in
# either spelling (quoted or bare), proved on a read that stays — the landing's release-check —
# before it is asked for the deleted key's reads. proof.sh's floor read is T25's (D3) and is
# not counted here.
s18_config_reads() {  # <file> <key> -> how many lines read that key through config_value
  /usr/bin/grep -cE "config_value .*[[:space:]]\"?$2\"?[[:space:]]+\"\"" "$1" 2>/dev/null | tr -d ' '
}
expect_eq "S18.3 the extractor finds the landing's release-check read (not comparing air)" "1" \
  "$(s18_config_reads "${S18_WT_LIB_DIR}/worktree.sh" release-check)"
for _s18_f in "$S18_LG" "${S18_WT_LIB_DIR}/line.sh" "${S18_WT_LIB_DIR}/worktree.sh" \
              "$BIONIC_HOOKS_DIR/session-poker.sh" "$S13_HOOK" "$S13_DP"; do
  expect_eq "S18.3 …and ${_s18_f##*/} reads impact-command nowhere" "0" \
    "$(s18_config_reads "$_s18_f" impact-command)"
done
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
section "S13c — one contract grammar, one verdict at every door (wave-20 T6; REQ-4, D4, Δ10)"
# ============================================================
#
# THE GRAMMAR HAS THREE DOORS AND ONE BODY. A dispatch, an `amend` (T9) and a `task-add` each
# hand Files:/Suites:/Re-executes: to payload/scripts/lib/brief.sh's `brief_validate_fields`,
# so an amended contract is held to exactly a fresh dispatch's standard (Δ10). This pins the
# door that exists today against the library the other two call: the same brief, driven
# through the real dispatch wall and through the library alone, names the same grammar faults
# — no fault the library finds is missing from the wall's refusal, and no grammar fault the
# library does NOT find appears there. The wall's other arms (arming, approval, budget) pool
# beside these and are not this section's; the comparison reads only the grammar's facts.
#
# THE FACT SET IS DERIVED, never typed: it is the union of what the library answered across
# the table, so a new check in the library joins the comparison without an edit here, and a
# clean brief in the table makes the "absent" half of the comparison carry weight.
S13C_LIB="$BIONIC_HOOKS_DIR/../payload/scripts/lib/brief.sh"
[ -r "$S13C_LIB" ] || S13C_LIB="$BIONIC_HOOKS_DIR/../scripts/lib/brief.sh"
S13C_R=$(s4_world "s13c-one-verdict")
s4_bind "$S13C_R" "$SID_A" "$S13C_R/.bionic/docs/plans/epic-99/run-b.md"
S13C_BT='`'
s13c_lib() {  # <repo> <role> <brief> -> one fact per line, sorted
  bash -c '
    . "$1" || exit 9
    sink() { [ "$1" = finding ] && printf "%s\n" "$2"; return 0; }
    brief_validate_fields "$(lift_contract_fields "$4" "$3")" "$3" "$2" sink
    exit 0
  ' _ "$S13C_LIB" "$1" "$2" "$3" 2>/dev/null | sort -u
}
s13c_dp() {  # <repo> <role> <name> <brief> -> the dispatch wall's whole channel
  jq -nc --arg s "$SID_A" --arg c "$1" --arg t "$1/s4-transcript.jsonl" \
         --arg r "$2" --arg n "$3" --arg p "$4" \
    '{session_id:$s, transcript_path:$t, cwd:$c, hook_event_name:"PreToolUse", tool_name:"Agent",
      tool_input:{description:"a dispatch", subagent_type:$r, name:$n, prompt:$p},
      tool_use_id:"toolu_S13C"}' \
    | env CLAUDE_CODE_SESSION_ID="$SID_A" bash "$PARTY_DP" 2>&1
  return 0
}
S13C_HEAD="Expected artifact: .bionic/docs/record/s13c.md
Expected duration: ~10 minutes.
Progress artifact: .bionic/tmp/s13c.progress, cadence ~5m"
# role|brief tail — one row per grammar fault, and one row with none.
S13C_CASES="implementor|Suites: tests/widget.test.sh
implementor|Suites: tests/\$X.test.sh
implementor|Suites: tests/unit/foo.spec.ts
implementor|Re-executes: ${S13C_BT}npx jest x | tee log${S13C_BT}
bionic:auditor|Re-executes: ${S13C_BT}go test ./a${S13C_BT}, ${S13C_BT}go test ./b${S13C_BT}, ${S13C_BT}go test ./c${S13C_BT}, ${S13C_BT}go test ./d${S13C_BT}
bionic:auditor|Suites: none
implementor|Notes: none of the three instrument labels
implementor|Files: payload/scripts/lib/widget.sh"
S13C_UNION=""
while IFS='|' read -r _s13c_role _s13c_tail; do
  S13C_UNION="${S13C_UNION}$(s13c_lib "$S13C_R" "$_s13c_role" "${S13C_HEAD}
${_s13c_tail}")
"
done <<< "$S13C_CASES"
S13C_UNION=$(printf '%s' "$S13C_UNION" | /usr/bin/grep -v '^$' | sort -u)
expect_eq "S13c the library answered a distinct grammar fact for each of the seven faulty briefs (non-vacuity)" \
  "7" "$(printf '%s\n' "$S13C_UNION" | /usr/bin/grep -c .)"
_s13c_i=0
while IFS='|' read -r _s13c_role _s13c_tail; do
  _s13c_i=$((_s13c_i + 1))
  _s13c_brief="${S13C_HEAD}
${_s13c_tail}"
  _s13c_want=$(s13c_lib "$S13C_R" "$_s13c_role" "$_s13c_brief" | tr '\n' '|')
  _s13c_out=$(s13c_dp "$S13C_R" "$_s13c_role" "s13c-${_s13c_i}" "$_s13c_brief")
  _s13c_got=""
  while IFS= read -r _s13c_fact; do
    [ -n "$_s13c_fact" ] || continue
    case "$_s13c_out" in *"$_s13c_fact"*) _s13c_got="${_s13c_got}${_s13c_fact}|" ;; esac
  done <<< "$S13C_UNION"
  expect_eq "S13c case ${_s13c_i} [${_s13c_role}] ${_s13c_tail%%:*}: the wall and the library name the same grammar faults" \
    "$_s13c_want" "$_s13c_got"
done <<< "$S13C_CASES"
# THE CLEAN ROW REALLY REACHED THE WALL: an empty want and an empty got would also agree for
# a wall that exited before reading the brief. So the clean brief must have been either
# refused by a named arm or journalled onto the roster, and either one is the wall at work.
_s13c_out=$(s13c_dp "$S13C_R" implementor s13c-clean "${S13C_HEAD}
Suites: tests/widget.test.sh")
expect_eq "S13c …and the wall answered the clean brief at all (the empty agreement is not silence)" "yes" \
  "$(if /usr/bin/grep -qE '^bionic: dispatch refused' <<< "$_s13c_out" \
        || /usr/bin/grep -qs 'name=s13c-clean' "$S13C_R/.bionic/tmp/roster-$SID_A.state"; then echo yes; else echo no; fi)"

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
expect_eq "S19.1 …and it is the framework" "1" \
  "$(/usr/bin/grep -cE '^anchor\(\)' "$S19_ASSERT")"

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
expect_empty "S19.2 no suite in tests/ hand-rolls a mutation precondition any more" \
  "$S19_HAND_HITS"

# THE PAIRED POSITIVE, and the discriminating one: the same sweep over a file with ONE of
# those idioms planted must name that file. Without this row, §S19.2 would pass just as
# loudly against a pattern that matches nothing at all.
S19_SB="$SANDBOX/s19"
mkdir -p "$S19_SB"
# built with %s so this line does not itself spell the idiom it plants
printf 'if cmp -%s "$SKILL_MD" "$DOCTORED_REPLANTED"; then no "x" "the %s target matched nothing"; fi\n' \
  s sed >> "$S19_SB/replanted.test.sh"
expect_eq "S19.2 …and the same sweep DOES fire on a copy with the idiom planted back" "1" \
  "$(/usr/bin/grep -cE -- "$S19_HANDROLLED" "$S19_SB/replanted.test.sh" | tr -d ' ')"

# --- §S19.3 retired (wave-24): six exact-count pins on `anchor` calls (per-suite sites and calls,
# this suite, agent-context-guard, landing-gate, and their total). An exact count goes red on
# every legitimate new mutant and is repaired by retyping the number, so it tested the author's
# memory, not the tree. The relation it stood for is derived below, in §S19.4, with its paired
# positive; §S19.2 holds the absence side across every suite.

# --- §S19.4 agent-context-guard: every doctored copy of the guard is anchored ---
# agent-context-guard builds its mutants through one helper, so a site is any line
# writing a copy of "$GUARD" to a file. The suite gets its own site pattern, and a
# pattern that finds no site is RED
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
S19_ACG="$S19_TESTS_DIR/agent-context-guard.test.sh"
S19_ACG_SITE='"\$GUARD" > "'
S19_ACG_REAL="$(s19_block_sites "$S19_ACG" "$S19_ACG_SITE")"
S19_ACG_REAL_SITES="${S19_ACG_REAL%% *}"
expect_eq "S19.4 the agent-context-guard site pattern finds at least one doctored site" "yes" \
  "$([ "${S19_ACG_REAL_SITES:-0}" -ge 1 ] 2>/dev/null && echo yes || echo no)"
expect_eq "S19.4 every agent-context-guard doctoring site is anchored" "0" \
  "${S19_ACG_REAL#* }"

# THE PLANTED DEFECTS, on copies. A bare site — a doctored copy of the guard with no
# anchor in its block — must be named; and a copy whose sites no longer carry the
# pattern's target must report no site, which is what turns the row above RED.
cp "$S19_ACG" "$S19_SB/acg-bare.test.sh"
# built with %s so this file does not itself carry the site it plants
printf '\nsed %s "$GUARD" %s "$MUTANT_TREE/hooks/mutant-bare.sh"\n' "'s/x/y/'" '>' >> "$S19_SB/acg-bare.test.sh"
S19_ACG_BARE="$(s19_block_sites "$S19_SB/acg-bare.test.sh" "$S19_ACG_SITE")"
expect_eq "S19.4 …and the derivation names a planted bare agent-context-guard site" "1" \
  "${S19_ACG_BARE#* }"
S19_ACG_BARE_SITES="${S19_ACG_BARE%% *}"
expect_eq "S19.4 …which the pattern counted as one more site (not vacuous)" "1" \
  "$(( ${S19_ACG_BARE_SITES:-0} - ${S19_ACG_REAL_SITES:-0} ))"
sed 's/"\$GUARD" > "/"$GUARD_GONE" > "/' "$S19_ACG" > "$S19_SB/acg-nosite.test.sh"
expect_eq "S19.4 …and a copy with the target renamed really changed (not vacuous)" "yes" \
  "$([ "$(/usr/bin/grep -c 'GUARD_GONE' "$S19_SB/acg-nosite.test.sh")" -ge 1 ] && echo yes || echo no)"
S19_ACG_NONE="$(s19_block_sites "$S19_SB/acg-nosite.test.sh" "$S19_ACG_SITE")"
expect_eq "S19.4 …and on it the site pattern finds no site, so the at-least-one row goes RED" "0" \
  "${S19_ACG_NONE%% *}"

# --- §S19.4 landing-gate: every doctored copy of the gate is anchored ---
# landing-gate doctors one source, the gate it loads, so a site is any line writing a
# copy of "$GATE_SRC" to a file. Same helper, same planted defects as above.
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
expect_eq "S19.4 …and a landing-gate copy with the target renamed really changed (not vacuous)" "yes" \
  "$([ "$(/usr/bin/grep -c 'GATE_SRC_GONE' "$S19_SB/lg-nosite.test.sh")" -ge 1 ] && echo yes || echo no)"
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
expect_eq "S19.4 …and a cross-gate copy with its redirects rewritten really changed (not vacuous)" "yes" \
  "$([ "$(/usr/bin/grep -c '" >> "' "$S19_SB/cg-nosite.test.sh")" -gt "$(/usr/bin/grep -c '" >> "' "$S19_CG")" ] && echo yes || echo no)"
S19_CG_NONE="$(s19_block_sites "$S19_SB/cg-nosite.test.sh" "$S19_CG_SITE")"
expect_eq "S19.4 …and on it the cross-gate pattern finds no site, so its at-least-one row goes RED" "0" \
  "${S19_CG_NONE%% *}"

# ============================================================
section "S17 — no private builder of a shared shape remains (AC-28)"
# ============================================================
#
# THE ABSENCE HALF AND THE POSITIVE HALF, TOGETHER (spec AC-28). Three shapes crossed this
# tree in sixty-three hand-written copies: the `roster-state/v1` row (16 suites), the
# `landing-swept/v1` marker (6), and the recorded ListAgents answer (8). S14/S15/S16 built
# the one builder for each; S17 removed the copies. An absence test alone would pass on a
# tree where the suites were deleted, so every absence below is paired with the positive
# that the former site now SOURCES the builder it was replaced by.
#
# THIS SECTION SPELLS NONE OF THE THREE LITERALS. Each is read back out of the writer that
# owns it — the row's token off `roster_row`'s own output, the marker's off the constant the
# two hooks share, the answer's off the committed corpus — so a suite cannot pass this by
# renaming the schema, and this file cannot match its own scan.
#
# WHAT COUNTS AS A HIT. The schema token followed by `|` is a row or marker being written or
# selected; the token alone is the VERSION being asserted, which several suites do on
# purpose (`the row's leading field is the schema version`) and which must stay. Full-line
# comments are skipped: naming the shape in prose is how these files stay readable, and a
# scan that forbade it would buy its zero by making the tree worse.
#
# THE ONE EXEMPTION, NAMED: tests/live-agents.test.sh. That suite is the PARSER's own, and
# its bodies are the parser's inputs — a doubled `Teammates` header, a forged block after
# `Peer sessions`, a garbled separator. A builder able to emit those would be able to emit
# them by accident, so they stay hand-written there and the exemption is held to that one
# file, with the paired positive that the file really does still carry them.

S17_TESTS_DIR="$REPO_ROOT/tests"
S17_ROW_TOKEN="${ROSTER_ROW_SCHEMA}|"
S17_MARK_TOKEN="${SWEPT_SCHEMA}|"
S17_LA_TOKEN="$(live_answer_block_header 1 | cut -d'(' -f1)("

# Non-vacuity of the three tokens themselves: a typo in any of them would make every
# absence assertion below pass over an untouched tree.
expect_contains "S17 the row token came off the writer" "roster-state/" "$S17_ROW_TOKEN"
expect_contains "S17 the marker token came off the hooks' shared constant" "landing-swept/" \
  "$S17_MARK_TOKEN"
expect_contains "S17 the answer token came off the corpus" "Teammates" "$S17_LA_TOKEN"

s17_hits() {  # <literal> [exempt basename] -> "<suite>:<count> …" for every suite still holding it
  local lit="$1" exempt="${2:-}" f b n out=""
  for f in "$S17_TESTS_DIR"/*.test.sh "$S17_TESTS_DIR"/*.prelude.sh; do   # a prelude is suite text too (wave-39 T36)
    b="$(basename "$f")"
    [ "$b" = "$exempt" ] && continue
    n="$(grep -v '^[[:space:]]*#' "$f" | grep -cF "$lit")" || n=0
    [ "$n" -gt 0 ] && out="${out}${b}:${n} "
  done
  printf '%s' "$out"
}

expect_eq "S17 no suite hand-writes or hand-selects the roster row any more" \
  "" "$(s17_hits "$S17_ROW_TOKEN")"
expect_eq "S17 no suite hand-writes or hand-selects the swept marker any more" \
  "" "$(s17_hits "$S17_MARK_TOKEN")"
expect_eq "S17 no suite hand-writes a ListAgents answer any more (the parser's own excepted)" \
  "" "$(s17_hits "$S17_LA_TOKEN" live-agents.test.sh)"

# THE EXEMPTION IS NOT A BLANK CHEQUE: it is one file, and that file is exempt because it
# genuinely still carries such bodies. If it ever stops, the exemption goes with it.
expect_true "S17 the exempt suite is the parser's own, and it does still hold answer bodies" \
  test "$(grep -v '^[[:space:]]*#' "$S17_TESTS_DIR/live-agents.test.sh" | grep -cF "$S17_LA_TOKEN")" -gt 0

# --- the paired positive: every former site sources the builder that replaced it ---

s17_sources() {  # <suite basename> <lib basename> -> 1 when the suite sources it
  local f="$S17_TESTS_DIR/$1.test.sh"
  [ -e "$f" ] || f="$S17_TESTS_DIR/$1.prelude.sh"   # a suite split in parts names its libraries in its prelude (wave-39 T36)
  grep -cF ". \"\$(dirname \"\$0\")/lib/$2\"" "$f" 2>/dev/null || printf '0'
}

for _s17 in cross-gate-agreement dispatch-preflight execution-recorder fail-direction-table \
            session-poker stop-check stop-guard stop-orders; do
  expect_eq "S17 [$_s17] sources the one ListAgents builder" \
    "1" "$(s17_sources "$_s17" live-answer.sh)"
done

for _s17 in cross-gate-agreement dispatch-preflight doctor-fleet doctor-patrol \
            execution-recorder fail-direction-table hook-adoption landing-gate \
            preflight-probe session-poker session-start session-sweeper stop-check \
            stop-guard stop-orders worktree; do
  expect_eq "S17 [$_s17] sources the one roster-row builder" \
    "1" "$(s17_sources "$_s17" roster-row.sh)"
done

for _s17 in dispatch-preflight doctor-fleet doctor-patrol landing-gate session-poker \
            session-start; do
  expect_eq "S17 [$_s17] sources the one swept-marker builder" \
    "1" "$(s17_sources "$_s17" swept-marker.sh)"
done

# --- §S17b the THIRD producer of the roster row, held to the writer's key set (A-15) ---
#
# hooks/execution-recorder.sh does not BUILD a row — it rewrites one field-wise with
# `RS = "|"`, which is why a row that grows a field anywhere still comes back out unchanged.
# But its `END` arm APPENDS `teammate_id=` when the launch row carried none, and that append
# is a from-scratch segment written by a file that is not the writer. Routing the whole
# rewrite through `roster_row` was rejected: the writer emits its optional fields
# present-if-passed, so re-emitting a pre-wall row through it would ADD `files=`,
# `suites_allowed=` and `suites_source=` empty and destroy the third state those keys'
# ABSENCE encodes (payload/scripts/lib/roster.sh's own header). What is pinned instead is
# that the two producers agree on the KEY SET and on every VALUE — the row's readers are by
# key, and position is the one thing they demonstrably do not read.
#
# The recorder's awk is not re-typed here: it is extracted from the shipped file and eval'd,
# the same `field1_via`/`field2_via` idiom this suite already uses.

s17_rewrite_via() {  # <hook file> <row> <agent id> <teammate id> <name> -> the completed row
  ( ROW="$2"; ROW_AGENT_ID="$3"; ROW_TEAMMATE_ID="$4"; ROW_NAME="$5"; PRIOR_LAUNCH=""
    eval "$(awk '/^  COMPLETED=\$\(printf/,/^    END \{ if \(tid/' "$1")"
    printf '%s\n' "$COMPLETED" ) 2>/dev/null
}

s17_keys() { printf '%s' "$1" | tr '|' '\n' | cut -d= -f1 | sort | tr '\n' ' '; }
s17_pairs() { printf '%s' "$1" | tr '|' '\n' | sort | tr '\n' ' '; }

S17_LAUNCH_ROW="$(roster_row_fixture status=intended session=s17sess name=s17-writer \
  agent_id= launched_at=2026-09-06T00:00:00Z deliverable=.bionic/docs/record/s17.md \
  tool_use_id=toolu_01S17)"
S17_TID="s17-writer@session-s17sess"
S17_DONE="$(s17_rewrite_via "$PARTY_ER" "$S17_LAUNCH_ROW" "as17-1111111111111111" "$S17_TID" "s17-writer")"

# What the ONE WRITER produces for the same facts, with the field named.
S17_WRITTEN="$(roster_row_fixture status=confirmed session=s17sess name=s17-writer \
  agent_id=as17-1111111111111111 launched_at=2026-09-06T00:00:00Z \
  deliverable=.bionic/docs/record/s17.md teammate_id="$S17_TID" tool_use_id=toolu_01S17)"

expect_eq "S17b the recorder's appended row carries the writer's key set, exactly" \
  "$(s17_keys "$S17_WRITTEN")" "$(s17_keys "$S17_DONE")"
expect_eq "S17b …and every key's value agrees, field for field" \
  "$(s17_pairs "$S17_WRITTEN")" "$(s17_pairs "$S17_DONE")"
expect_eq "S17b …with exactly one teammate_id on the row, never two" \
  "1" "$(printf '%s' "$S17_DONE" | tr '|' '\n' | grep -c '^teammate_id=')"

# THE DISCRIMINATOR — a copy of the recorder whose appended segment is spelled with a
# different key. Every reader in the fleet is by key, so this is precisely the drift the
# comparison above exists to catch, and it is invisible to every other assertion in the tree.
S17_ER_MUT="$SANDBOX/s17-execution-recorder-mutant.sh"
anchor file hooks/execution-recorder.sh '|teammate_id=%s'
awk '{ gsub(/\|teammate_id=%s/, "|teammate=%s"); print }' "$PARTY_ER" > "$S17_ER_MUT"
S17_DONE_MUT="$(s17_rewrite_via "$S17_ER_MUT" "$S17_LAUNCH_ROW" "as17-1111111111111111" "$S17_TID" "s17-writer")"
expect_eq "S17b …and the key-set pin goes red on it (the pin discriminates)" \
  "no" "$([ "$(s17_keys "$S17_WRITTEN")" = "$(s17_keys "$S17_DONE_MUT")" ] && echo yes || echo no)"

# --- §S17c the poker's third spelling of the marker schema is gone (A-14b) ---
#
# §S15b pins `adopt_copy_marker`. `youngest_suite_writer` was the OTHER function in the same
# file greping the bare literal, and it is the one whose failure mode is silent: no closing
# markers found reads there as "every row is still open", which fills the writer budget.
# RETIRED WITH THE EMERGENCY LINE (wave-28 T13; D14): the kill floor named a writer to stop,
# and the gate admits no run past memory's share, so the function and its two marker pins go.
expect_eq "S17c youngest_suite_writer is gone with the EMERGENCY line" "0" \
  "$(grep -c '^youngest_suite_writer()' "$PARTY_PK")"
expect_eq "S17c …while the marker's other reader stands (the count extractor reads the file)" "1" \
  "$(grep -c '^adopt_copy_marker()' "$PARTY_PK")"

# ============================================================
section "B — no backtick pair hides inside a double-quoted assertion name (AC-B.1/AC-B.2, epic-22 task 7)"
# ============================================================
#
# THE DEFECT CLASS (seed ideas/fixit-residue-names.md item 3, critic issue 3 / A-S18a-6).
# `expect_*` calls take their FIRST argument as a human-readable label, always inside double
# quotes. A label that wraps a literal token in backticks for readability — "the neighbour
# the `.` would have swallowed" — is not quoted text to bash: a double-quoted string still
# expands backtick command substitution, so the shell RUNS `.` (the `source` builtin, no
# argument) on every pass, corrupts the label to whatever it printed, and dumps a usage
# error to stderr. This landed three times in this wave alone and once executed `uv tool
# install --force omnigent` for real (critic issue 3) — a machine-mutating class of test
# defect, not a cosmetic one. The instance live on main is tests/stop-check.test.sh:298,
# fixed by 8727375 (this task's cherry-pick, landed in this same tree).
#
# THE SCAN. A per-line state machine, not a bare regex: it tracks single/double-quote state,
# stops at a `#` outside any quote (comments never execute), and skips heredoc BODY lines
# entirely between an opening `<<[-]DELIM` (quoted or not) and its closing delimiter line —
# heredoc text is never "inside a double-quoted string" as a shell grammar node. An escaped
# backtick (`\``) is consumed by its backslash, so no pair forms. THE ONE CASE THAT NEEDS ITS
# OWN RULE: a legitimate $(...) substitution nested inside a double-quoted string reopens
# ordinary shell quoting for its own body, so a backtick nested inside a SINGLE-quoted
# argument of a $(...) call — e.g. "$(printf '```markdown```')" — is inert there for the
# same reason it is inert anywhere else inside single quotes; the scanner re-enters its own
# state machine for a $(...) span instead of reading it as flat text. Without that rule, four
# genuine committed lines (fenced code blocks passed to `printf` inside $(...), in
# tests/canonical-sdlc-governing-skill.test.sh) false-positive and §B.2 could never be green
# on this tree. Left alone, by design: a bare backtick pair directly inside a $(...) body,
# not nested in further quotes, is real intentional legacy substitution nested in the modern
# form — a style question, not this defect class. A hit prints as `<file>:<line>`, one per
# PAIR found.
# A SINGLE-QUOTED STRING LEFT OPEN AT A LINE'S END IS CARRIED (wave-38 T33, A-T33-4). An awk
# program opened by `awk '` and closed lines later is one single-quoted word, so its
# `index(s, "`Plan`")` (T21's tests/dispatch-preflight-5.test.sh) is inert text, not a pair in
# a double-quoted string: the next line starts inside the quote, whichever context opened it
# (top level or a $(...) body), and is read from the closing quote on. A `<<` on a line that
# starts or ends inside a carried quote opens no heredoc.

B_AWK="$SANDBOX/backtick-scan.awk"
cat > "$B_AWK" <<'AWK_EOF'
function skip_squote(line, i, n,    c) {
  while (i <= n) { c = substr(line, i, 1); if (c == "'") { SQ_SHUT = 1; return i + 1 } i++ }
  SQ_SHUT = 0; IN_SQUOTE = 1; return n + 1
}
function scan_subshell(line, i, n,    c, r) {
  while (i <= n) {
    c = substr(line, i, 1)
    if (c == "\\") { i += 2; continue }
    if (c == "'") { i = skip_squote(line, i + 1, n); continue }
    if (c == "\"") { r = scan_dquote(line, i + 1, n); i = r + 1; continue }
    if (c == "$" && substr(line, i + 1, 1) == "(") { i = scan_subshell(line, i + 2, n); continue }
    if (c == ")") return i + 1
    i++
  }
  return n + 1
}
function find_second_backtick(line, i, n,    c) {
  while (i <= n) {
    c = substr(line, i, 1)
    if (c == "\\") { i += 2; continue }
    if (c == "`") return i
    if (c == "\"") return 0
    i++
  }
  return 0
}
function scan_dquote(line, i, n,    c, j) {
  while (i <= n) {
    c = substr(line, i, 1)
    if (c == "\\") { i += 2; continue }
    if (c == "\"") return i
    if (c == "$" && substr(line, i + 1, 1) == "(") { i = scan_subshell(line, i + 2, n); continue }
    if (c == "`") {
      j = find_second_backtick(line, i + 1, n)
      if (j > 0) { HIT = 1; i = j + 1; continue }
      i++; continue
    }
    i++
  }
  return n + 1
}
function scan_line(line,    i, n, c, r) {
  HIT = 0; i = 1; n = length(line)
  if (IN_SQUOTE) { IN_SQUOTE = 0; i = skip_squote(line, 1, n); if (!SQ_SHUT) return 0 }
  while (i <= n) {
    c = substr(line, i, 1)
    if (c == "#") return HIT
    if (c == "\\") { i += 2; continue }
    if (c == "'") { i = skip_squote(line, i + 1, n); continue }
    if (c == "\"") { r = scan_dquote(line, i + 1, n); i = r + 1; continue }
    i++
  }
  return HIT
}
function heredoc_start(line,    tmp) {
  if (match(line, /<<-?[ \t]*'[A-Za-z_][A-Za-z0-9_]*'/)) {
    tmp = substr(line, RSTART, RLENGTH); HD_STRIP = (tmp ~ /^<<-/) ? 1 : 0
    sub(/^<<-?[ \t]*'/, "", tmp); sub(/'$/, "", tmp); HD_DELIM = tmp; return 1
  }
  if (match(line, /<<-?[ \t]*"[A-Za-z_][A-Za-z0-9_]*"/)) {
    tmp = substr(line, RSTART, RLENGTH); HD_STRIP = (tmp ~ /^<<-/) ? 1 : 0
    sub(/^<<-?[ \t]*"/, "", tmp); sub(/"$/, "", tmp); HD_DELIM = tmp; return 1
  }
  if (match(line, /<<-?[ \t]*[A-Za-z_][A-Za-z0-9_]*/)) {
    tmp = substr(line, RSTART, RLENGTH); HD_STRIP = (tmp ~ /^<<-/) ? 1 : 0
    sub(/^<<-?[ \t]*/, "", tmp); HD_DELIM = tmp; return 1
  }
  return 0
}
function is_delim_line(line,    t) {
  t = line; if (HD_STRIP) sub(/^[ \t]+/, "", t); return (t == HD_DELIM)
}
FNR == 1 { IN_HEREDOC = 0; IN_SQUOTE = 0 }
{
  if (IN_HEREDOC) { if (is_delim_line($0)) IN_HEREDOC = 0; next }
  SQ_WAS = IN_SQUOTE
  if (scan_line($0)) print FILENAME ":" FNR
  if (!SQ_WAS && !IN_SQUOTE && heredoc_start($0)) IN_HEREDOC = 1
}
AWK_EOF

b_scan() { awk -f "$B_AWK" "$@" 2>/dev/null; }

# (a) §B.2 — GREEN ON THE COMMITTED TREE. The same two roots 8727375's own sweep grep named
# (minus tests/drill/, which does not exist on main, per plan Assumption A-6).
B_TESTS_HITS="$(b_scan "$REPO_ROOT"/tests/*.test.sh "$REPO_ROOT"/tests/lib/*.sh)"
expect_empty "§B.2 the scan is silent on the committed tree (the fix landed, nothing else hides)" \
  "$B_TESTS_HITS"

# (b) §B.1 — THE MUTATION, the discriminator. A scratch COPY of one suite (the shipped file
# is never touched), with a fresh backtick pair planted at a known line — line 2, right
# after the shebang, so no `anchor` precondition is needed: this is an INSERTION at a fixed
# offset, not a pattern-matched deletion that could silently miss its target.
B_MUT_DIR="$SANDBOX/backtick-mutant"; mkdir -p "$B_MUT_DIR"
{
  head -n 1 "$REPO_ROOT/tests/session-sweeper.test.sh"
  printf 'expect_eq "a planted `pair` right here" "x" "x"\n'
  tail -n +2 "$REPO_ROOT/tests/session-sweeper.test.sh"
} > "$B_MUT_DIR/session-sweeper.test.sh"

B_MUT_HITS="$(b_scan "$B_MUT_DIR/session-sweeper.test.sh")"
expect_eq "§B.1 a planted pair makes the scan RED naming file:line" \
  "$B_MUT_DIR/session-sweeper.test.sh:2" "$B_MUT_HITS"

# CONTROL — the same file, unplanted: still silent, or the RED above was the `cp`/`head`/
# `tail` reshuffle and not the plant.
B_CTRL_DIR="$SANDBOX/backtick-control"; mkdir -p "$B_CTRL_DIR"
cp "$REPO_ROOT/tests/session-sweeper.test.sh" "$B_CTRL_DIR/session-sweeper.test.sh"
expect_empty "…control: the unmutated copy stays silent" \
  "$(b_scan "$B_CTRL_DIR/session-sweeper.test.sh")"

# (c) THE EXCLUSIONS, individually named — one fixture line per shape, so a future edit that
# widens the scan (and starts flagging safe text) is caught here rather than being
# discovered as a false-positive drowning out a real hit. Five shapes: an ESCAPED pair
# (line 2), a legitimate $(...) with a nested SINGLE-quoted pair (line 3), a pair inside a
# COMMENT (line 4), a pair inside a bare SINGLE-quoted string (line 5), and a pair inside a
# HEREDOC body opened with a quoted delimiter (lines 6-8) — the fourth exclusion class
# 8727375's own commit message named. Only line 9, a real unescaped pair inside a plain
# double-quoted string, is a hit.
B_FX="$SANDBOX/backtick-exclusions.sh"
cat > "$B_FX" <<'FX_EOF'
#!/bin/bash
expect_eq "the \`escaped\` pair is inert" "yes" "yes"
expect_eq "fence" "$(printf '```markdown```')" "x"
# this comment mentions `a pair` right here
MSG='the `pair` is inert in single quotes'
cat <<'HEREDOC_EOF'
a heredoc body line with a `pair` in it, quoted delimiter
HEREDOC_EOF
expect_eq "the neighbour the `.` would have swallowed" "x" "y"
RES="$(awk '
  index($0, "`Explore`") { print "x" }
' "$f")"
expect_eq "a second `real` pair, after the program closes" "x" "y"
awk -v r="$(roles)" '
  index($0, "`Plan`") { print }' "$f"
FX_EOF
B_FX_HITS="$(b_scan "$B_FX")"
expect_eq "…the seven exclusions (escaped, \$(...) w/ nested single quotes, comment, single-quoted, heredoc body, a program opened in \$(...) and one opened at top level) stay silent; only the real pairs on lines 9 and 13 are hits" \
  "$(printf '%s:9\n%s:13' "$B_FX" "$B_FX")" "$B_FX_HITS"


# ============================================================
section "Refuse — no hook prints a refusal directly; refuse.sh is the only renderer (epic-22 wave-01, AC-E1.2)"
# ============================================================
#
# THE CRITERION. AC-E1.2: "no hook prints a refusal directly; all go through
# refuse.sh", fails-when "a hook prints directly". The renderer landed in task 11;
# the 21 hooks are migrated in task 13. So the wall this section builds cannot be
# "zero hooks print directly" yet — it would be red for the whole of task 11 and 12
# and would be turned off rather than fixed.
#
# THE SHAPE INSTEAD: A SHRINKING ALLOWLIST, ASSERTED BY EQUALITY. The roster below is
# every hook file that still emits a refusal of its own, measured 2026-09-07 at the
# head of wt/s11-refuse-lib, and the assertion is that the measured set EQUALS it. So:
#
#   - a NEW hook that prints its own refusal makes the measured set bigger and this
#     section goes red — the criterion's fails-when, held from the day the renderer
#     exists rather than from the day the last hook is migrated;
#   - a hook task 13 MIGRATES makes the measured set smaller and this section also
#     goes red, until its name is struck from the roster below. That is the point: the
#     roster shrinks by deliberate edit, one line per migrated hook, and when it is
#     empty the equality is the criterion itself with nothing left to except.
#
# An allowlist that only bounded the set from above would let task 13 finish without
# anyone editing this file, and the exception would outlive the thing it excepted.
#
# WHAT COUNTS AS PRINTING A REFUSAL DIRECTLY. A non-comment line carrying the string
# `BLOCKED` — the headline every one of the tree's 83 emitting sites uses (surfaces
# map §B.3). Comments are excluded by line shape, so the paragraph in a hook that
# EXPLAINS its wall is not counted as one; a heredoc body is counted, because a
# heredoc body is printed. The 21 shared `loader_fail_closed` walls are inside this
# count deliberately: they are 21 copies of one refusal, and they are the largest
# single block of text task 13 removes.

REFUSE_TREE="$(cd "$BIONIC_HOOKS_DIR/.." && pwd -P)"
REFUSE_LIB_DIR="$REFUSE_TREE/payload/scripts/lib"
[ -d "$REFUSE_LIB_DIR" ] || REFUSE_LIB_DIR="$REFUSE_TREE/scripts/lib"

# refuse_direct_files <hooks dir> -> the basename of every file in it that emits a
# refusal of its own, one per line, sorted.
#
# `grep -c`, NOT `grep -q`, ON THE RIGHT OF THE PIPE. A `producer | grep -q` pair
# under `pipefail` exits 141 when the producer outgrows the pipe buffer and grep
# leaves early — canonical-sdlc-evidence-gate.sh is 1500 lines and is exactly the
# producer that does it. `grep -c` reads its whole input, so the status is the
# match/no-match answer and nothing else.
refuse_direct_files() {
  local d="$1" f n
  for f in "$d"/*.sh; do
    [ -f "$f" ] || continue
    n="$(/usr/bin/grep -vE '^[[:space:]]*#' "$f" | /usr/bin/grep -c 'BLOCKED')"
    n="$(printf '%s' "${n:-0}" | tr -cd '0-9')"
    [ "${n:-0}" -gt 0 ] && printf '%s\n' "${f##*/}"
  done | sort
}

# THE ROSTER — the five CLI COMMANDS, and nothing else. Task 13 migrated every WALL
# in hooks/ to scripts/lib/refuse.sh; what remains on this list is exempt by RULING D-5
# (record/wave-01-plugin-only/s12-refusal-wording.md), and the reason is a boundary and
# not a carve-out:
#
#   A WALL refuses an act the platform was taking. The reader is interrupted, so the
#   refusal is an object rendered once, in one line, by one renderer.
#   A COMMAND answers a request the agent made. It speaks in its own voice, with its
#   own exit codes, to a caller that asked it a question.
#
# The five commands are `session-poker.sh`, `stop-orders.sh`, `stop-check.sh`,
# `preflight-probe.sh` and `payload/scripts/spawn-worktree.sh`. Four live in hooks/ and
# so fall inside this section's glob; spawn-worktree.sh does not and is named here for
# completeness rather than matched.
#
# WHY A SUBSET AND NOT AN EQUALITY. Only `preflight-probe.sh` still spells the scanner's
# word: measured after the migration, `session-poker.sh`, `stop-orders.sh` and
# `stop-check.sh` carry no `BLOCKED` at all, because their own voice never used it. An
# equality against the five would therefore be red for three names that are exempt and
# silent. The subset check plus the zero-walls check below says the thing that matters —
# no WALL prints its own refusal, and anything the scanner does find is one of the five.
REFUSE_ALLOWLIST='preflight-probe.sh
session-poker.sh
stop-check.sh
stop-orders.sh'

# --- (a) NON-VACUITY OF THE SEARCH SET. Every count below is over a real glob, and
# the renderer this section exists for is on disk. ---
# THE FLOOR MOVES WITH THE MERGES (epic-23 wave-11): T12 made four Stop hooks one and T23
# made five Bash walls one, so the tree carries fourteen hook files where it carried
# twenty-one. The number is a not-counting-over-air guard, not a roster, so it tracks the
# tree — and it is a floor rather than an equality for exactly that reason.
expect_eq "Refuse the hooks glob is non-empty (this section is not counting over air)" "yes" \
  "$([ "$(ls "$BIONIC_HOOKS_DIR"/*.sh 2>/dev/null | wc -l | tr -d ' ')" -ge 14 ] && echo yes || echo no)"
expect_eq "Refuse payload/scripts/lib/refuse.sh is on disk" "yes" \
  "$([ -r "$REFUSE_LIB_DIR/refuse.sh" ] && echo yes || echo no)"

# --- (b) THE SUBSET, AND THE ZERO. Everything the scanner finds is one of the five
# commands, and no wall is among them. A hook added to the tree that prints its own
# refusal fails the first; a wall that was never migrated fails the second. ---
REFUSE_FOUND="$(refuse_direct_files "$BIONIC_HOOKS_DIR")"
REFUSE_STRAY=""
while IFS= read -r _f; do
  [ -n "$_f" ] || continue
  case "
$REFUSE_ALLOWLIST
" in
    *"
$_f
"*) : ;;
    *) REFUSE_STRAY="$REFUSE_STRAY$_f " ;;
  esac
done <<REFUSE_FOUND_EOF
$REFUSE_FOUND
REFUSE_FOUND_EOF
expect_eq "Refuse every file still printing its own refusal is one of the five CLI commands" \
  "" "$REFUSE_STRAY"
expect_eq "Refuse …and no WALL is among them: the hooks-that-are-walls count is zero" "0" \
  "$(printf '%s\n' "$REFUSE_FOUND" | /usr/bin/grep -cE '^(agent-context-guard|bash-walls|canonical-sdlc-governing-skill|dispatch-preflight|engage|execution-recorder|session-start|session-sweeper|stop|stop-guard)\.sh$' || true)"
expect_eq "Refuse …and the set is what task 13 left: preflight-probe.sh alone still spells it" \
  "preflight-probe.sh" "$(printf '%s\n' "$REFUSE_FOUND" | tr -d ' ')"

# --- (c) THE SCANNER FINDS A PLANTED PRINT. Without this the equality above could be
# passing because the scanner matches nothing at all. A scratch copy of the hook
# directory takes one new file whose only content is a direct refusal print. ---
REFUSE_MUT="$SANDBOX/refuse-mut-hooks"
mkdir -p "$REFUSE_MUT"
cp "$BIONIC_HOOKS_DIR"/*.sh "$REFUSE_MUT/"
cat > "$REFUSE_MUT/aaa-planted-wall.sh" <<'PLANTED_EOF'
#!/bin/bash
# A comment mentioning BLOCKED, which must NOT be what the scanner catches.
echo "BLOCKED: this hook formats its own refusal instead of calling refuse" >&2
exit 2
PLANTED_EOF
REFUSE_MUT_FOUND="$(refuse_direct_files "$REFUSE_MUT")"
expect_contains "Refuse MUTANT a planted direct print is found by the scanner" \
  "aaa-planted-wall.sh" "$REFUSE_MUT_FOUND"
expect_ne "Refuse MUTANT …so the subset check above would go RED on a new direct printer" \
  "$REFUSE_ALLOWLIST" "$REFUSE_MUT_FOUND"

# A comment is not a print. The planted file's own first line says BLOCKED in a
# comment; a scanner that counted it would flag every hook that merely documents its
# wall, and the roster would stop shrinking when task 13 removes the code but keeps
# the explanation.
cat > "$REFUSE_MUT/aaa-comment-only.sh" <<'COMMENT_EOF'
#!/bin/bash
# This hook used to print BLOCKED here. It calls refuse now.
#   BLOCKED: the old text, kept in a comment for the reader.
exit 0
COMMENT_EOF
expect_absent "Refuse MUTANT a hook whose only BLOCKED is in a comment is NOT flagged" \
  "aaa-comment-only.sh" "$(refuse_direct_files "$REFUSE_MUT")"

# --- (d) THE OTHER DIRECTION: a MIGRATED hook shrinks the set and the equality goes
# red until the roster is edited. This is what makes the allowlist shrink rather than
# rot. protect-main.sh is the stand-in — the scratch copy has its refusal prints
# removed, the way task 13 will remove them for real. ---
REFUSE_MIG="$SANDBOX/refuse-mig-hooks"
mkdir -p "$REFUSE_MIG"
cp "$BIONIC_HOOKS_DIR"/*.sh "$REFUSE_MIG/"
# preflight-probe.sh is the stand-in now: protect-main.sh no longer prints the word at
# all, so stripping it from that file would mutate nothing and the arm would pass over
# an unmutated copy.
anchor file hooks/preflight-probe.sh 'die "BLOCKED — a blocking probe failed, and the prior attestation at $STATE_FILE could"'
anchor insert hooks/preflight-probe.sh '    die "BLOCKED — a blocking probe failed. No attestation was written, and any earlier"'
anchor insert hooks/preflight-probe.sh '  die "BLOCKED — a blocking probe failed. No attestation was written, and any earlier"'
/usr/bin/grep -vF -e 'die "BLOCKED — a blocking probe failed, and the prior attestation at $STATE_FILE could"' \
  -e 'die "BLOCKED — a blocking probe failed. No attestation was written, and any earlier"' "$BIONIC_HOOKS_DIR/preflight-probe.sh" > "$REFUSE_MIG/preflight-probe.sh"
REFUSE_MIG_FOUND="$(refuse_direct_files "$REFUSE_MIG")"
expect_absent "Refuse MUTANT a migrated hook drops out of the measured set" \
  "preflight-probe.sh" "$REFUSE_MIG_FOUND"
expect_ne "Refuse MUTANT …so the measured set moves when a file stops printing its own refusal" \
  "$REFUSE_ALLOWLIST" "$REFUSE_MIG_FOUND"

# --- (e) THE RENDERER ITSELF. One definition of `refuse` in the tree, and it does
# not print the word this section counts: the new user line is
# `bionic: <verb> refused — <fact> (<fix>)`, which is what replaces `BLOCKED`. ---
# THE NAME COLLISION IS GONE, AND THIS PIN IS WHAT KEEPS IT GONE. There used to be TWO
# `refuse()` definitions in the tree: the renderer, and a private one-line helper in
# payload/scripts/spawn-worktree.sh — one argument where the renderer takes five.
# Nothing sourced both, so nothing was broken; but the day that script needed a refusal
# and declared refuse.sh, the later definition would silently replace the earlier one
# and every existing call site would pass one argument to a function that refuses on
# arity — a wall that starts refusing everything, or a script that starts refusing
# nothing, depending which order the sourcing landed in. Invisible at the call site.
#
# Task 13 renamed the private one to `_wt_refuse` (ruling D-6). The count is ONE now,
# and a second definition anywhere turns this red.
expect_eq "Refuse refuse() is defined exactly once in the tree: the renderer" \
  "1" "$(/usr/bin/grep -lE '^refuse\(\)' "$REFUSE_TREE/hooks"/*.sh "$(dirname "$REFUSE_LIB_DIR")"/*.sh "$REFUSE_LIB_DIR"/*.sh 2>/dev/null | sort -u | wc -l | tr -d ' ')"
expect_eq "Refuse …and no HOOK defines one, which is the half AC-E1.2 is about" "0" \
  "$(/usr/bin/grep -lE '^refuse\(\)' "$REFUSE_TREE/hooks"/*.sh 2>/dev/null | wc -l | tr -d ' ')"
expect_eq "Refuse …spawn-worktree.sh's private helper is renamed and still one-argument" "1" \
  "$(/usr/bin/grep -cE '^_wt_refuse\(\) \{ contract ' "$(dirname "$REFUSE_LIB_DIR")/spawn-worktree.sh")"
expect_eq "Refuse …and it defines no bare refuse() any more" "0" \
  "$(/usr/bin/grep -cE '^refuse\(\)' "$(dirname "$REFUSE_LIB_DIR")/spawn-worktree.sh" || true)"
expect_eq "Refuse …and that one definition is refuse.sh's" "1" \
  "$(/usr/bin/grep -cE '^refuse\(\)' "$REFUSE_LIB_DIR/refuse.sh")"
expect_eq "Refuse the renderer prints no BLOCKED of its own" "0" \
  "$(/usr/bin/grep -vE '^[[:space:]]*#' "$REFUSE_LIB_DIR/refuse.sh" | /usr/bin/grep -c 'BLOCKED')"

# THE FORMAT STRING HAS ONE SITE. Two printf sites spelling the user line is how a
# renderer drifts from its own criterion — one of them gets the em dash and the other
# a hyphen, and AC-E1.3's regex passes on whichever the test happens to drive.
expect_eq "Refuse the user line's format string is written exactly once" "1" \
  "$(/usr/bin/grep -c 'refused — %s (%s)' "$REFUSE_LIB_DIR/refuse.sh")"


# ============================================================
section "AP — audit_path, normalize_newlines, log_finding: ONE definition each, tree-wide (epic-23 wave-12-fixit-171 REQ-8, D6)"
# ============================================================
#
# WHAT THIS SECTION USED TO SAY, AND WHY IT CHANGED. Until this wave it pinned three
# audit_path copies as AGREEING — one body by checksum, plus a mutation arm proving the
# comparison discriminated — because consolidation to one owner had been PROMOTED (A-69)
# rather than done, beside `normalize_newlines` ×2 and `log_finding` ×2. D6 does it. An
# agreement pin is the best available guarantee while copies exist; it is strictly weaker
# than the copies not existing, because copies that agree can always part again and the pin
# only reports it after the fact.
#
# WHERE THEY LIVE NOW, and why not walls.sh. The ownership table named
# `payload/scripts/lib/walls.sh` as the default owner. It is 3,461 lines and neither
# hooks/session-poker.sh nor hooks/canonical-sdlc-governing-skill.sh sources it or any of
# its prerequisites, so making it the owner would have added it to two more hooks'
# `BIONIC_LIB_WANT` — a FAIL-CLOSED list, where an absent library refuses everything the
# hook judges — and parsed 3,461 lines per tick and per Write for three small functions.
# `root.sh` (200 lines) and `run.sh` (602 lines) are already in the WANT of all four
# processes and already sourced ABOVE every use site, so nothing widened to get here:
#
#   audit_path          payload/scripts/lib/root.sh   — a pure function of a project root,
#                                                       beside project_root which resolves it
#   log_finding         payload/scripts/lib/root.sh   — audit_path's caller; the audit
#                                                       stream stays with the path that names it
#   normalize_newlines  payload/scripts/lib/run.sh    — a plan/document text read, beside
#                                                       _run_lines, which now delegates to it
#
# THE PIN IS A COUNT, NOT A COMPARISON. A copy that cannot exist cannot part. The three
# directories are named rather than globbed (§N.1's reason), and `payload/hooks` is
# deliberately NOT among them: it is a symlink to `hooks/`, so walking it would count every
# hook twice and turn "exactly one" into a number nobody could read.
#
# NON-VACUITY IS SEPARATE AND COMES FIRST. "Exactly one definition" is also satisfied by a
# tree where the function was deleted and one stub remains, so each function is CALLED FOR
# REAL off its owner below — the slug's arithmetic, both line-ending shapes, and a finding
# written to a fake $HOME — before the count is allowed to mean anything.

AP_TREE="$(cd "$BIONIC_HOOKS_DIR/.." && pwd -P)"
AP_LIB="$AP_TREE/payload/scripts/lib"
[ -d "$AP_LIB" ] || AP_LIB="$AP_TREE/scripts/lib"
AP_SCRIPTS="$(dirname "$AP_LIB")"
AP_H="$SANDBOX/ap-home"; mkdir -p "$AP_H"

ap_count() {  # <fn> <dir>… -> how many DISTINCT files in those dirs define <fn> at column zero
  local fn="$1"; shift
  local d pats=""
  for d in "$@"; do pats="$pats $d/*.sh"; done
  # shellcheck disable=SC2086
  /usr/bin/grep -lE "^$fn\\(\\)" $pats 2>/dev/null | sort -u | wc -l | tr -d " "
}
ap_where() {  # <fn> -> the one file defining it, or every one of them, newline-separated
  local fn="$1"
  /usr/bin/grep -lE "^$fn\(\)" \
    "$AP_TREE/hooks"/*.sh "$AP_SCRIPTS"/*.sh "$AP_LIB"/*.sh 2>/dev/null | sort -u
}

# --- (a) THE COUNT, one row per function, with the owner named. ---
expect_eq "AP.1 audit_path is defined in exactly one file under hooks/ + payload/" \
  "1" "$(ap_count audit_path "$AP_TREE/hooks" "$AP_SCRIPTS" "$AP_LIB")"
expect_eq "AP.1 …and that file is payload/scripts/lib/root.sh" \
  "$AP_LIB/root.sh" "$(ap_where audit_path)"
expect_eq "AP.1 normalize_newlines is defined in exactly one file under hooks/ + payload/" \
  "1" "$(ap_count normalize_newlines "$AP_TREE/hooks" "$AP_SCRIPTS" "$AP_LIB")"
expect_eq "AP.1 …and that file is payload/scripts/lib/run.sh" \
  "$AP_LIB/run.sh" "$(ap_where normalize_newlines)"
expect_eq "AP.1 log_finding is defined in exactly one file under hooks/ + payload/" \
  "1" "$(ap_count log_finding "$AP_TREE/hooks" "$AP_SCRIPTS" "$AP_LIB")"
expect_eq "AP.1 …and that file is payload/scripts/lib/root.sh" \
  "$AP_LIB/root.sh" "$(ap_where log_finding)"
# THE ANSWER LOG'S PAIR (wave-25 T4, spec D9) lives beside audit_path for the same reason
# audit_path does, and is held the same way: one definition each, owner named.
for _apfn in answers_path log_answer; do
  expect_eq "AP.1 $_apfn is defined in exactly one file under hooks/ + payload/" \
    "1" "$(ap_count "$_apfn" "$AP_TREE/hooks" "$AP_SCRIPTS" "$AP_LIB")"
  expect_eq "AP.1 …and that file is payload/scripts/lib/root.sh" \
    "$AP_LIB/root.sh" "$(ap_where "$_apfn")"
done

# --- (b) THE FORMER CARRIERS CARRY NOTHING. Named one by one rather than inferred from the
# count, so that a re-introduced copy says WHICH file grew it back. ---
expect_eq "AP.2 walls.sh defines none of the three" "0" \
  "$(/usr/bin/grep -cE '^(audit_path|normalize_newlines|log_finding)\(\)' "$AP_LIB/walls.sh")"
expect_eq "AP.2 lib/stop.sh defines none of the three" "0" \
  "$(/usr/bin/grep -cE '^(audit_path|normalize_newlines|log_finding)\(\)' "$AP_LIB/stop.sh")"
expect_eq "AP.2 canonical-sdlc-governing-skill.sh defines none of the three" "0" \
  "$(/usr/bin/grep -cE '^(audit_path|normalize_newlines|log_finding)\(\)' \
       "$AP_TREE/hooks/canonical-sdlc-governing-skill.sh")"
expect_eq "AP.2 session-poker.sh defines none of the three" "0" \
  "$(/usr/bin/grep -cE '^(audit_path|normalize_newlines|log_finding)\(\)' \
       "$AP_TREE/hooks/session-poker.sh")"

# --- (c) NON-VACUITY: each function CALLED FOR REAL off its owner. A count is satisfied by
# a stub; these are not. ---
AP_PROJ="/tmp/ap fixture/My Proj!"
AP_SUM="$(printf '%s' "$AP_PROJ" | cksum | cut -d' ' -f1)"
expect_eq "AP.3 audit_path slugs the basename and cksums the whole path" \
  "$AP_H/.claude/logs/My-Proj--$AP_SUM/sdlc-audit.md" \
  "$( ( HOME="$AP_H"; . "$AP_LIB/root.sh" >/dev/null 2>&1; audit_path "$AP_PROJ" ) 2>/dev/null )"
( HOME=""; . "$AP_LIB/root.sh" >/dev/null 2>&1; audit_path "$AP_PROJ" ) >/dev/null 2>&1
expect_eq "AP.3 …and with no \$HOME it withholds rather than naming a relative path" \
  "1" "$?"

printf 'a\r\nb\r\n' > "$SANDBOX/ap-crlf.txt"
printf 'a\rb\r'      > "$SANDBOX/ap-cr.txt"
expect_eq "AP.3 normalize_newlines TRANSLATES CRLF, file argument" "a|b|" \
  "$( ( . "$RUN_LIB" >/dev/null 2>&1; normalize_newlines "$SANDBOX/ap-crlf.txt" ) | tr '\n' '|' )"
expect_eq "AP.3 …and CR-only, which a deleting \`tr -d\` would collapse to one line" "a|b|" \
  "$( ( . "$RUN_LIB" >/dev/null 2>&1; normalize_newlines "$SANDBOX/ap-cr.txt" ) | tr '\n' '|' )"
expect_eq "AP.3 …and the same body serves the STDIN caller the governing hook is" "a|b|" \
  "$( ( . "$RUN_LIB" >/dev/null 2>&1; normalize_newlines < "$SANDBOX/ap-cr.txt" ) | tr '\n' '|' )"

AP_LF_ERR="$( ( HOME="$AP_H"
    . "$AP_LIB/root.sh" >/dev/null 2>&1
    BIONIC_FINDING_CHANNEL="ap-fixture"
    BIONIC_FINDING_SUBJECT="$AP_PROJ/plan.md"
    bionic_finding_root() { printf '%s' "$AP_PROJ"; }
    log_finding ap-check "a detail" ) 2>&1 >/dev/null )"
expect_contains "AP.3 log_finding echoes the finding to stderr" \
  "canonical-sdlc [ap-check]: a detail" "$AP_LF_ERR"
expect_contains "AP.3 …and appends it to the audit file the caller's contract addressed" \
  "ap-fixture ap-check: a detail ($AP_PROJ/plan.md)" \
  "$(cat "$AP_H/.claude/logs/My-Proj--$AP_SUM/sdlc-audit.md" 2>/dev/null)"
expect_eq "AP.3 answers_path names permission-answers.log in audit_path's own directory" \
  "$AP_H/.claude/logs/My-Proj--$AP_SUM/permission-answers.log" \
  "$( ( HOME="$AP_H"; . "$AP_LIB/root.sh" >/dev/null 2>&1; answers_path "$AP_PROJ" ) 2>/dev/null )"
AP_LA_ERR="$( ( HOME="$AP_H"; . "$AP_LIB/root.sh" >/dev/null 2>&1
    log_answer "$AP_PROJ" "an answer line" ) 2>&1 >/dev/null )"
expect_contains "AP.3 log_answer appends the line to that file" "an answer line" \
  "$(cat "$AP_H/.claude/logs/My-Proj--$AP_SUM/permission-answers.log" 2>/dev/null)"
expect_eq "AP.3 …and, unlike log_finding, says nothing on stderr (its caller owns stdout and stderr)" \
  "" "$AP_LA_ERR"
( HOME=""; . "$AP_LIB/root.sh" >/dev/null 2>&1; log_answer "$AP_PROJ" "x" ) >/dev/null 2>&1
expect_eq "AP.3 …and with no \$HOME it reports failure (rc 1) rather than writing anywhere" "1" "$?"

# --- (d) THE MUTATION ARM: the count discriminates. A throwaway tree laid out like the
# shipped one, with ONE extra carrier re-growing all three definitions — the exact drift
# this section replaced an agreement pin to prevent — must read 2, not 1. Without this arm
# a `grep` that silently matched nothing would report "exactly one" as a pass at zero. ---
AP_MUT="$SANDBOX/ap-second-definition-mutant"
rm -rf "$AP_MUT"; mkdir -p "$AP_MUT/hooks" "$AP_MUT/scripts/lib"
cp "$AP_LIB/root.sh" "$AP_LIB/run.sh" "$AP_MUT/scripts/lib/"
{ printf '#!/bin/bash\n'
  printf 'audit_path() {\n  :\n}\n'
  printf 'normalize_newlines() {\n  :\n}\n'
  printf 'log_finding() {\n  :\n}\n'
  printf 'answers_path() {\n  :\n}\n'
  printf 'log_answer() {\n  :\n}\n'
} > "$AP_MUT/hooks/a-carrier-that-grew-them-back.sh"
for _apfn in audit_path normalize_newlines log_finding answers_path log_answer; do
  expect_eq "AP.4 a second carrier of $_apfn reads as 2, so AP.1 can go red" \
    "2" "$(ap_count "$_apfn" "$AP_MUT/hooks" "$AP_MUT/scripts" "$AP_MUT/scripts/lib")"
done

# ============================================================
section "LC — THE LATEST-CONTRACT READING, retired in both walls: the recorder asks the one close predicate (epic-23 wave-12-fixit-171 T26; dispatch-wall half retired wave-20 T2, recorder half wave-20 T20, D10)"
# ============================================================
#
# WHAT THIS PINNED. hooks/dispatch-preflight.sh and hooks/execution-recorder.sh carried one
# awk text byte for byte — "is this name currently under an open contract, or did a
# `landing-swept/v1|…|state=MET` marker close the last one?" — because the recorder loaded no
# library that parses a roster and `BIONIC_LIB_WANT` is fail-closed on the SubagentStart path.
#
# WHAT CHANGED, TWICE. (1) epic-23 wave-20 T2 (REQ-10, D10; research D3-8): the dispatch wall
# stopped carrying the reading and asks the one close predicate, `roster_open_names`
# (payload/scripts/lib/roster.sh), under which a MET marker closes nothing and a post-launch
# ack is the one close (ADR-034 d1). T2 left the recorder's copy whole, on the view that its
# question was IDENTIFICATION rather than occupancy. (2) epic-23 wave-20 T20 (found by T17,
# approved by Chris): the recorder's question — is the contract this id started under still
# OPEN, so that a second start against it is a resumed copy — IS the close question, and its
# MET latch was the last reader but one that disagreed with the four (§CG-close T20 drives
# it). The recorder now sources roster.sh (on its WANT line and by a direct source line —
# tests/hook-adoption.test.sh's pin) and asks the predicate once, for the one name, and only
# when the id's last row already says it started: the first start of every id — the common
# path — pays nothing for it.
#
# SO THE PIN MOVED WITH THE READING. What was pinned whole below — the recorder's four-function
# awk span — is retired, and what is pinned whole in its place is the recorder's new
# open-contract block, byte for byte, with the dispatch wall still carrying no private copy.

LC_DP="$BIONIC_HOOKS_DIR/dispatch-preflight.sh"
LC_ER="$BIONIC_HOOKS_DIR/execution-recorder.sh"
lc_span() {  # <file> -> the delimited reading, BEGIN and END markers included
  sed -n '/---- BEGIN open-contract reading/,/---- END open-contract reading/p' "$1"
}
LC_SPAN_ER="$(lc_span "$LC_ER")"

# --- (a) THE RECORDER'S BLOCK IS WHOLE, BYTE FOR BYTE (re-authored at T20: it pinned one
# delimited latest-contract span holding four awk functions; the span is gone and this is the
# block that replaced it). ---
# READ, NOT SUBSTITUTED: the block carries `$'\t'` and nested `$( )`, and /bin/bash 3.2 mis-parses
# a quoted heredoc inside a command substitution. `read -d ''` returns 1 at EOF by design.
LC_WANT=""
IFS= read -r -d '' LC_WANT <<'LCBLOCK' || :
  # ---- BEGIN open-contract reading — the one close predicate, asked of one name (cross-gate §LC) ----
  if [ -n "$DUP_PRIOR" ]; then
    case "$DUP_PRIOR" in *"|name="*) DUP_NAME="${DUP_PRIOR#*|name=}"; DUP_NAME="${DUP_NAME%%|*}" ;; *) DUP_NAME="" ;; esac
    [ -n "$DUP_NAME" ] || DUP_NAME="(unnamed)"
    DUP_NAME="${DUP_NAME//$'\t'/ }"
    grep -qxF -- "$DUP_NAME" <<< "$(roster_open_names "$ROSTER_FILE" "$STATE_DIR/sweeper-${BIONIC_SID}.state" "$BIONIC_SID")" || DUP_PRIOR=""
  fi
  # ---- END open-contract reading ----
LCBLOCK
LC_WANT="${LC_WANT%$'\n'}"
expect_eq "LC.1 hooks/execution-recorder.sh carries the open-contract block, byte for byte (T20)" \
  "$LC_WANT" "$LC_SPAN_ER"
expect_eq "LC.1 …exactly one BEGIN marker in execution-recorder.sh" \
  "1" "$(/usr/bin/grep -c -- '---- BEGIN open-contract reading' "$LC_ER")"
expect_eq "LC.1 …and none of the four latest-contract functions survives (T20: was 'all four')" "0" \
  "$(/usr/bin/grep -cE '^ *function (live_status|contract_note|contract_closed)\(' "$LC_ER" || true)"
expect_eq "LC.1 …and no latest-contract span either (T20)" "0" \
  "$(/usr/bin/grep -c -- '---- BEGIN latest-contract reading' "$LC_ER" || true)"

# --- (b) THE DECISIVE LINE IS IN IT (re-authored at T20: it was "a live row retires the MET
# marker above it", the C1 latch fix). The predicate compares the ack against the name's
# LATEST launch, which is the same fix by construction — an ack older than a relaunch closes
# nothing — and the line that asks it is the one pinned. ---
expect_contains "LC.3 the recorder's block asks roster_open_names for the one name, over this session's ack ledger" \
  'grep -qxF -- "$DUP_NAME" <<< "$(roster_open_names "$ROSTER_FILE" "$STATE_DIR/sweeper-${BIONIC_SID}.state" "$BIONIC_SID")" || DUP_PRIOR=""' \
  "$LC_SPAN_ER"

# --- (c) THE RECORDER STILL ASKS IT (re-authored at T20: it counted two `contract_note($0)`
# calls and the `!contract_closed(nm)` decision). A block nobody reaches is a comment, so the
# block must sit between the candidate read and the journal write it gates. ---
expect_eq "LC.5 the recorder notes no row through a private reading any more (T20: was 2)" "0" \
  "$(/usr/bin/grep -c 'contract_note($0)' "$LC_ER" || true)"
lc_line() {  # <fixed string> -> the first line number of the recorder carrying it, or 0
  /usr/bin/grep -nF -- "$1" "$LC_ER" | head -1 | cut -d: -f1 | awk '{ print $1 + 0 } END { if (NR == 0) print 0 }'
}
LC_L_READ=$(lc_line '  DUP_PRIOR=$(awk ')
LC_L_BEGIN=$(lc_line '---- BEGIN open-contract reading')
LC_L_END=$(lc_line '---- END open-contract reading')
LC_L_WRITE=$(lc_line 'f = "status=duplicate-start"')
expect_true "LC.5 …and DECIDES on the block: candidate read ($LC_L_READ) < block (${LC_L_BEGIN}–${LC_L_END}) < journal write ($LC_L_WRITE)" \
  test "$LC_L_READ" -gt 0 -a "$LC_L_READ" -lt "$LC_L_BEGIN" -a "$LC_L_BEGIN" -lt "$LC_L_END" -a "$LC_L_END" -lt "$LC_L_WRITE"
expect_true "LC.5 …and the recorder sources the predicate's library" \
  /usr/bin/grep -qx '\. "\$BIONIC_LIB/roster.sh"' "$LC_ER"

# --- (d) THE DISPATCH WALL KEEPS NO COPY (D3-8). No span, no MET latch, no contract_closed:
# its one close is the library predicate, which §CG-close drives through the wall itself. ---
expect_eq "LC.6 the dispatch wall carries no latest-contract span any more" "0" \
  "$(/usr/bin/grep -c -- '---- BEGIN latest-contract reading' "$LC_DP" || true)"
expect_eq "LC.6 …and no private MET close of any spelling" "0" \
  "$(/usr/bin/grep -cE 'contract_closed|MET\[' "$LC_DP" || true)"
expect_true "LC.6 …because it asks the one close predicate instead" \
  /usr/bin/grep -q 'roster_open_names "' "$LC_DP"
expect_eq "LC.5 no private MET latch survives in either file (T20: the recorder's MET[] counted too)" "0" \
  "$(/usr/bin/grep -cE '!\(nm in met\)|&& !met\b|MET\[' "$LC_DP" "$LC_ER" | awk -F: '{t += $2} END { print t + 0 }')"

# ============================================================
section "BR — the bounded-runner copies: detect.sh and session-start.sh, CODE-identical (Step-6 duplication review F1, epic-23 wave-14 T27)"
# ============================================================
#
# hooks/session-start.sh:525-533 declares its own kill helpers "A DELIBERATE DUPLICATE of
# `_detect_bound_kill` / `_detect_bound_kill_tree` in payload/scripts/lib/detect.sh … The two
# copies are meant to stay in step — change one and change the other." Nothing anywhere
# compared them: this is the exact shape §O already exists to close, on a different pair of
# files (T22 fixed both faults in detect.sh; T23 then had to find and fix the SAME two faults
# in this copy by hand, as a separate floor fold-in — a pin at T22 would have made T23 a red
# row instead of a discovery).
DETECT="$BIONIC_SCRIPTS_DIR/payload/scripts/lib/detect.sh"
SSTART="$BIONIC_HOOKS_DIR/session-start.sh"

expect_nonempty "BR detect.sh's _detect_bound_kill_tree() body is extractable at all" \
  "$(fn_body "$DETECT" _detect_bound_kill_tree)"
expect_nonempty "BR session-start.sh's ss_bound_kill_tree() body is extractable at all" \
  "$(fn_body "$SSTART" ss_bound_kill_tree)"
expect_nonempty "BR detect.sh's _detect_bound_kill() body is extractable at all" \
  "$(fn_body "$DETECT" _detect_bound_kill)"
expect_nonempty "BR session-start.sh's ss_bound_kill() body is extractable at all" \
  "$(fn_body "$SSTART" ss_bound_kill)"

# br_code <file> <fn> -> §O's fn_code (pure-comment lines stripped, §O's own normalisation)
# PLUS the one normalisation §O's pair never needed: the function's own NAME PREFIX, so
# ss_bound_kill_tree's self-call inside ss_bound_kill lines up against
# _detect_bound_kill_tree's. Used for session-start.sh's two copies only — detect.sh, the
# original, is read through fn_code alone. NOTHING ELSE is touched: not whitespace beyond
# what fn_code already trims, not the executable text, not any other identifier.
br_code() {  # <file> <fn name as it is spelled IN THAT FILE>
  fn_code "$1" "$2" | sed 's/^ss_bound_kill/_detect_bound_kill/g'
}

expect_eq "BR the tree-walker: session-start's copy is detect.sh's, code for code" \
  "$(fn_code "$DETECT" _detect_bound_kill_tree)" "$(br_code "$SSTART" ss_bound_kill_tree)"
expect_eq "BR the kill primitive: session-start's copy is detect.sh's, code for code" \
  "$(fn_code "$DETECT" _detect_bound_kill)" "$(br_code "$SSTART" ss_bound_kill)"

# THE DISCRIMINATING HALF (§O's own shape, turned the other way): a pin over two strings that
# were ALREADY identical before normalisation proves nothing about the normalisation. The
# tree-walker is the pair that is not byte-identical — session-start.sh:547-549 re-wraps
# detect.sh:1414-1415's one rationale comment across three lines instead of two, a line-length
# artefact of the file it was copied into, not a content change — so it is the one driven
# here.
expect_ne "BR …the two tree-walker bodies are NOT byte-identical (session-start.sh re-wraps one comment)" \
  "$(fn_body "$DETECT" _detect_bound_kill_tree)" \
  "$(fn_body "$SSTART" ss_bound_kill_tree | sed 's/^ss_bound_kill/_detect_bound_kill/g')"
expect_eq "BR …and it IS code-identical, which is what the two expect_eq above compare" \
  "$(fn_code "$DETECT" _detect_bound_kill_tree)" "$(br_code "$SSTART" ss_bound_kill_tree)"
# …and the byte difference really is a comment, line for line: every line the two bodies
# differ by starts with `#`.
expect_empty "BR …and every line the two tree-walker bodies differ by is a comment line" \
  "$(diff <(fn_body "$DETECT" _detect_bound_kill_tree) \
          <(fn_body "$SSTART" ss_bound_kill_tree | sed 's/^ss_bound_kill/_detect_bound_kill/g') \
      | grep -E '^[<>]' | sed 's/^[<>] //' | grep -v '^#')"
expect_nonempty "BR …over a diff that really is non-empty (the filter is not eating it all)" \
  "$(diff <(fn_body "$DETECT" _detect_bound_kill_tree) \
          <(fn_body "$SSTART" ss_bound_kill_tree | sed 's/^ss_bound_kill/_detect_bound_kill/g') | grep -cE '^[<>]')"

# THE MUTATION ARM. A pin over two files that agree today passes just as loudly if the
# comparison itself is broken, so ONE copy of detect.sh is doctored in the SANDBOX — never
# the shipped file — and the SAME comparison is re-run against it. The needle is the
# generation cap `_detect_bound_kill_tree` walks the process table under, doctored from 16 to
# 1: a REAL drift shape (this exact family shipped it once — T22 fixed detect.sh's copy, T23
# found the same fault still live in session-start.sh's). At `-lt 1` the descendant walk stops
# one generation in, so a grandchild a `sweep` fork spawns survives the kill. `anchor` first
# (§S19's own precondition idiom): the needle must occur exactly once in detect.sh, or the
# `sed` below is a no-op and BR_MUT is a silent copy of the real file.
BR_NEEDLE='"$generations" -lt 16'
BR_MUT_NEEDLE='"$generations" -lt 1'
anchor file payload/scripts/lib/detect.sh '"$generations" -lt 16'
BR_MUT="$SANDBOX/br-mutant-detect.sh"
sed "s/-lt 16/-lt 1/" "$DETECT" > "$BR_MUT"

expect_ne "BR …and the SAME comparison calls the doctored copy a drift (the generation cap moved)" \
  "$(fn_code "$BR_MUT" _detect_bound_kill_tree)" "$(br_code "$SSTART" ss_bound_kill_tree)"
expect_eq "BR …while the OTHER primitive in the doctored copy still agrees (one function moved, not the file)" \
  "$(fn_code "$BR_MUT" _detect_bound_kill)" "$(br_code "$SSTART" ss_bound_kill)"

# ============================================================
section "PV — the Patrol verdict: ONE predicate, every reader (epic-23 wave-15 REQ-1 AC-1.4; wave-16 REQ-11 AC-11.2)"
# ============================================================
#
# THE DEFECT THIS SECTION EXISTS FOR. "How stale is stale" was a judgment call typed out at
# three sites. lib/patrol.sh exported PATROL_STALE_MULTIPLIER to hold two of them together;
# the third — the stop library's own death notice — typed `INTERVAL * 2` as a literal, so a
# change to the judgment moved two readers and left the one that BLOCKS A TURN measuring
# against a threshold nobody configured (research row 1, wave-15).
#
# ADR-028 replaced the threshold with an observation: the verdict is an idle-time predicate
# over the session transcript, and it lives in lib/patrol.sh as `patrol_verdict`. Both
# readers that can REFUSE on it — the stop library's revive notice and the dispatch wall's
# staleness half — call that one function. This section pins the pair the way §Roots pins a
# resolver: one definition, every caller, no private arithmetic.

PV_LIB="${BIONIC_SCRIPTS_DIR}/payload/scripts/lib"
[ -d "$PV_LIB" ] || PV_LIB="${BIONIC_SCRIPTS_DIR}/scripts/lib"
PV_PATROL="$PV_LIB/patrol.sh"
PV_STOP="$PV_LIB/stop.sh"
PV_DP="$BIONIC_HOOKS_DIR/dispatch-preflight.sh"

# ONE DEFINITION, and it is the library's. Counted over every shell file the payload ships,
# so a second copy grown in a hook is a failure here rather than a divergence discovered in
# the field.
PV_DEFS=$( { grep -l '^patrol_verdict()' "$PV_LIB"/*.sh 2>/dev/null
             grep -l '^patrol_verdict()' "$BIONIC_HOOKS_DIR"/*.sh 2>/dev/null
           } | sort -u | wc -l | tr -d ' ' )
expect_eq "PV patrol_verdict is defined exactly once in the tree" "1" "$PV_DEFS"
anchor insert payload/scripts/lib/patrol.sh 'patrol_verdict()'

# BOTH BLOCKING READERS CALL IT.
if grep -q 'patrol_verdict' "$PV_STOP"; then
  ok "PV the stop library's revive notice calls patrol_verdict"
else
  no "PV the stop library's revive notice calls patrol_verdict" "no call in $PV_STOP"
fi
if grep -q 'patrol_verdict' "$PV_DP"; then
  ok "PV …and so does the dispatch wall's staleness half"
else
  no "PV …and so does the dispatch wall's staleness half" "no call in $PV_DP"
fi

# AND THE TWO REPORTING READERS CALL IT TOO (wave-16 REQ-11, AC-11.2). Wave-15 moved the
# readers that can REFUSE; doctor's own reading — `patrol_stamp_state`, in this same library
# — and the session-start banner went on multiplying the interval by two, so the page a
# person reads and the wall that lets them work answered one question two ways, 1080s apart
# at a 1200s interval. Both are on the predicate now, and the multiplier they shared is
# deleted.
PV_SSTART="$BIONIC_HOOKS_DIR/session-start.sh"
# COUNTED AS A CALL, NOT A MENTION: the predicate is DEFINED in this file, so containment
# alone would pass on the definition.
expect_eq "PV the doctor's own reading of the stamp asks the predicate" "1" \
  "$(grep -c '\$(patrol_verdict ' "$PV_PATROL" || true)"
if grep -q 'patrol_verdict' "$PV_SSTART"; then
  ok "PV …and so does the session-start banner"
else
  no "PV …and so does the session-start banner" "no call in $PV_SSTART"
fi

# AND NOBODY TYPES A MULTIPLIER. The literal the stop library carried, and the exported
# constant the dispatch wall read: the arithmetic is inside the predicate now, so both are
# absent from every reader — and the constant itself has no definition left to read
# (tests/patrol-stale.test.sh §1 owns its retirement; the poker's `adopt` window, which
# multiplied a CADENCE rather than the interval, moves to `observe_class` under REQ-10).
expect_eq "PV the literal 2x multiplier is gone from the stop library" "0" \
  "$(grep -c 'INTERVAL \* 2' "$PV_STOP" || true)"
expect_eq "PV …and the dispatch wall no longer reads PATROL_STALE_MULTIPLIER either" "0" \
  "$(grep -c 'PATROL_STALE_MULTIPLIER' "$PV_DP" || true)"
expect_eq "PV …nor the banner that read it" "0" \
  "$(grep -c 'PATROL_STALE_MULTIPLIER' "$PV_SSTART" || true)"

# THE WAVE HEAD'S OWN ROW, and the only place the tree-wide absence is asserted (REQ-11
# AC-11.2). It takes TWO landings to go green and each is a different task's: the readers
# that graded a Patrol stamp had to move off the constant before the constant could be
# deleted, or a head in between would read an unset name under `set -u`, and the last
# reader of all was the poker's `adopt` window — which multiplies a ROW's cadence, a
# different question, and moves to `observe_class` with REQ-10. Counted over the shipped
# shell files by NAME rather than by `grep -r payload/`, where `hooks/` is a symlink a
# recursive grep never follows. CODE LINES, NOT PROSE: two files narrate the retirement in
# a comment — this library's own paragraph and the stop library's account of the three
# sites — and a row that counted narration would be a row against the history.
PV_NAMED=0
for _pv_f in "$PV_LIB"/*.sh "$BIONIC_HOOKS_DIR"/*.sh "${BIONIC_SCRIPTS_DIR}/payload/scripts"/*.sh; do
  [ -f "$_pv_f" ] || continue
  PV_NAMED=$(( PV_NAMED + $(grep -cE '^[[:space:]]*[^#[:space:]].*PATROL_STALE_MULTIPLIER' \
                            "$_pv_f" 2>/dev/null || true) ))
done
expect_eq "PV no shell file the payload ships defines or reads the retired multiplier" \
  "0" "$PV_NAMED"

# THE FIRE WINDOW IS THE LIBRARY'S ARITHMETIC, spelled once. A reader that recomputed it
# would be the literal back under another name.
expect_eq "PV the fire window is computed in exactly one place" "1" \
  "$(grep -c 'iv / 10' "$PV_PATROL" || true)"
expect_eq "PV …and neither reader recomputes it" "0" \
  "$(( $(grep -c '/ 10' "$PV_STOP" || true) + $(grep -c '/ 10' "$PV_DP" || true) ))"

# ============================================================
# ============================================================
section "R2 — the knob-unset harness, and the cell ADR-030 flipped (epic-23 wave-16 REQ-2, AC-2.3/AC-2.4)"
# ============================================================
#
# THE SEAM THIS SECTION GUARDS. Every detail assertion in the fleet reads a stream taken
# with `BIONIC_WALL_VERBOSE=1` — `expect_block` in the evidence-gate suite, the
# `HOOK_VSTDERR` pair in the governing-skill suite, `GATE_VERR` in the dispatch-preflight
# suite, and this very file's own `export` at :55. That is the substitution research R2
# found: the suites pinned "the detail names the offending id" on a channel no agent ever
# reads, so a wall that printed NOTHING to either reader stayed green for three releases
# (seed A §8a, carry-over 8). ADR-030's own tests therefore have to run on the other
# stream, and a later editor reaching for the familiar helper would quietly undo the fix
# while every row stayed green.
#
# So each of the three suites marks its ADR-030 span, and this file — the one that reads
# other suites rather than driving a component — holds the span to the rule. The mutation
# arm at the end proves the check can fail: the same greps over a doctored copy of one span
# find what the shipped spans do not have.
#
# fails-when: a marked span is missing or empty; or it sets the knob; or it calls
# `expect_block`, `HOOK_VSTDERR` or `GATE_VERR`; or the library stops naming ADR-030; or a
# pin of the old `detail_to_user=no` cell survives.

R2_TESTS_DIR="$(cd "$(dirname "$0")" && pwd -P)"
R2_LIB="${BIONIC_SCRIPTS_DIR}/payload/scripts/lib"
[ -d "$R2_LIB" ] || R2_LIB="${BIONIC_SCRIPTS_DIR}/scripts/lib"
R2_REFUSE="$R2_LIB/refuse.sh"
R2_BEGIN='# [REQ-2 AC-2.3 KNOB-UNSET SECTION: BEGIN]'
R2_END='# [REQ-2 AC-2.3 KNOB-UNSET SECTION: END]'

# r2_span <file> — the marked span, markers excluded. awk and not `sed -n '/a/,/b/p'`,
# because the markers carry `[` and `]` and a regex range would read them as a class.
r2_span() {
  awk -v b="$R2_BEGIN" -v e="$R2_END" '
    index($0, b) { f = 1; next }
    index($0, e) { f = 0 }
    f' "$1"
}
require_helpers r2_span

for _r2f in refuse.test.sh canonical-sdlc-evidence-gate.test.sh canonical-sdlc-governing-skill.test.sh; do
  _r2p="$R2_TESTS_DIR/$_r2f"
  # THE POSITIVE FIRST. Three greps for absence over an empty string all pass, which is
  # the vacuous shape this repo's own doctrine forbids: the span has to exist and carry
  # assertions before its absences mean anything.
  expect_eq "R2 $_r2f: carries exactly one ADR-030 span opener" "1" \
    "$(grep -cF "$R2_BEGIN" "$_r2p" || true)"
  expect_eq "R2 $_r2f: …and exactly one closer" "1" \
    "$(grep -cF "$R2_END" "$_r2p" || true)"
  expect_eq "R2 $_r2f: the marked span drives at least six assertions" "yes" \
    "$([ "$(r2_span "$_r2p" | grep -c '^expect_')" -ge 6 ] && echo yes || echo no)"
  # AND THE ABSENCES. A bare mention of the knob's NAME is allowed — `env -u
  # BIONIC_WALL_VERBOSE` is how a runner removes it — so what is forbidden is an
  # ASSIGNMENT of it, which is what turns the detail on.
  expect_eq "R2 $_r2f: …and never assigns BIONIC_WALL_VERBOSE" "0" \
    "$(r2_span "$_r2p" | grep -c 'BIONIC_WALL_VERBOSE=' || true)"
  expect_eq "R2 $_r2f: …nor calls expect_block, which takes the verbose drive" "0" \
    "$(r2_span "$_r2p" | grep -c 'expect_block' || true)"
  expect_eq "R2 $_r2f: …nor reads HOOK_VSTDERR" "0" \
    "$(r2_span "$_r2p" | grep -c 'HOOK_VSTDERR' || true)"
  expect_eq "R2 $_r2f: …nor GATE_VERR" "0" \
    "$(r2_span "$_r2p" | grep -c 'GATE_VERR' || true)"
done

# THE MUTATION ARM. The four greps above pass just as loudly if `r2_span` prints nothing,
# so one span is doctored IN THE SANDBOX — an `export BIONIC_WALL_VERBOSE=1` spliced in
# where a later editor would put it — and the same check is re-run against the copy.
R2_MUT="$SANDBOX/r2-knob-mutant.test.sh"
anchor file tests/refuse.test.sh '# [REQ-2 AC-2.3 KNOB-UNSET SECTION: BEGIN]'
awk -v b="$R2_BEGIN" '{ print } index($0, b) { print "export BIONIC_WALL_VERBOSE=1" }' \
  "$R2_TESTS_DIR/refuse.test.sh" > "$R2_MUT"
expect_eq "R2 MUTANT the doctored span DOES set the knob, so the check can fail" "1" \
  "$(r2_span "$R2_MUT" | grep -c 'BIONIC_WALL_VERBOSE=' || true)"
expect_eq "R2 MUTANT …and the shipped span still does not, over the same extractor" "0" \
  "$(r2_span "$R2_TESTS_DIR/refuse.test.sh" | grep -c 'BIONIC_WALL_VERBOSE=' || true)"

# AC-2.4 — THE LIBRARY'S SIDE. The cell is `yes` now, read back through the library's own
# accessor rather than grepped out of the table; the channel-table comment records the ADR
# that replaced ruling D-1, and keeps D-1 itself; and no pin of the old cell survives.
expect_eq "R2 the exit2 channel now puts detail on the user stream" "yes" \
  "$(bash -c '. "$1"; refuse_channel exit2 detail_to_user' _ "$R2_REFUSE" 2>/dev/null)"
expect_eq "R2 …while deny keeps its model-only split" "no" \
  "$(bash -c '. "$1"; refuse_channel deny detail_to_user' _ "$R2_REFUSE" 2>/dev/null)"
expect_eq "R2 …and block too" "no" \
  "$(bash -c '. "$1"; refuse_channel block detail_to_user' _ "$R2_REFUSE" 2>/dev/null)"
expect_eq "R2 the channel table names ADR-030 as the ruling that superseded D-1" "yes" \
  "$([ "$(grep -c 'ADR-030' "$R2_REFUSE")" -ge 1 ] && echo yes || echo no)"
expect_eq "R2 …and still carries D-1's own text, superseded rather than deleted" "yes" \
  "$([ "$(grep -c -i 'a refusal is a sentence with a pointer' "$R2_REFUSE")" -ge 1 ] && echo yes || echo no)"
expect_eq "R2 no pin of the old exit2 detail_to_user=no cell survives in refuse.test.sh" "0" \
  "$(grep -cF '"no" "$(cell exit2 detail_to_user)"' "$R2_TESTS_DIR/refuse.test.sh" || true)"
expect_eq "R2 …and the pin that replaced it asserts yes" "1" \
  "$(grep -cF '"yes" "$(cell exit2 detail_to_user)"' "$R2_TESTS_DIR/refuse.test.sh" || true)"

# ============================================================
section "§bring-forward — one source for the step both callers judge against (wave-16 T25, critic C1)"
# ============================================================
#
# THE DISAGREEMENT THIS PINS SHUT. `plan_bring_forward` used to take the step as an
# argument, and the two callers passed different facts: the evidence gate passed the plan
# body's `current:`, the governing-skill hook passed the frontmatter's `sdlc-step:`. A
# frontmatter stamp is written once at Step 0 and almost never moved — this repo's archive
# carries `sdlc-step: 3` beside `current: 9` — so the Write-side arm computed against step 3
# for the life of the plan and printed a SHORTER list than the gate would, silently. The
# predicate now derives the step from the plan text it already holds, and this section is
# the wall that keeps it that way: a caller that starts handing it one again is the exact
# regression, and no per-file suite can see it, because each call site reads fine alone.
#
# fails-when: a third caller appears unpinned, either caller hands the predicate an
# argument after the plan path, or the detector cannot catch one that does.
BF_LIB="$BIONIC_HOOKS_DIR/../payload/scripts/lib/walls.sh"
[ -r "$BF_LIB" ] || BF_LIB="$BIONIC_HOOKS_DIR/../scripts/lib/walls.sh"
BF_GSKILL="$BIONIC_HOOKS_DIR/canonical-sdlc-governing-skill.sh"

# EVERY CALL, definition and `declare -F` probe excluded: a call is the name followed by a
# quoted argument, which is how both sites spell it and how a third would.
bf_calls() {  # <file> -> the call lines, `file:line:text`
  grep -n 'plan_bring_forward "' "$1" 2>/dev/null | grep -v '^[0-9]*:[[:space:]]*#'
}
# A SECOND ARGUMENT, if one is ever passed: the plan path, then whitespace, then another
# quoted or `$`-led word. A trailing redirection (`2>/dev/null`) is not one and does not
# match — which is why this asks for the shape of an ARGUMENT rather than for "anything".
bf_second_arg() { grep -E 'plan_bring_forward "[^"]*"[[:space:]]+["$]' || true; }

# THE WHOLE TRACKED TREE, NOT TWO NAMED FILES (wave-16 T27, critic C9). `BF_LIB` and
# `BF_GSKILL` above name the two callers the section already knows about — a census built by
# reading only them cannot see a THIRD caller anywhere else, which is exactly the section's
# own `fails-when` clause below and was unpinnable by construction before this row (a third
# caller moved none of the old counts, because the old counts were grep hits inside files
# the count itself named). Real source only: `hooks/`, `payload/scripts/`, `payload/commands/`,
# `payload/skills/`, `agents/` — `payload/hooks` and `payload/agents` are symlinks onto
# `hooks/` and `agents/` (`ls -ld payload/*`), so grepping them too would double-count the
# same lines rather than widen the census; `tests/` stays out, same as `bf_calls` above, and
# comments/the definition are excluded by the same `#`-at-content-start rule, adapted for
# `grep -r`'s `file:line:text` shape (single-file `bf_calls` gets `line:text`).
BF_TREE_DIRS="$REPO_ROOT/hooks $REPO_ROOT/payload/scripts $REPO_ROOT/payload/commands $REPO_ROOT/payload/skills $REPO_ROOT/agents"
bf_tree_calls() {  # -> `file:line:text` across the real tree, comments/definition excluded
  grep -rn 'plan_bring_forward "' $BF_TREE_DIRS 2>/dev/null \
    | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#'
}

BF_TREE_CALLS="$(bf_tree_calls)"
expect_eq "the tree holds exactly two callers of plan_bring_forward" "2" \
  "$(printf '%s\n' "$BF_TREE_CALLS" | grep -c 'plan_bring_forward "')"
expect_eq "…the evidence gate is one of them" "1" \
  "$(bf_calls "$BF_LIB" | grep -c 'plan_bring_forward "')"
expect_eq "…and the governing-skill hook is the other" "1" \
  "$(bf_calls "$BF_GSKILL" | grep -c 'plan_bring_forward "')"
expect_empty "…and NEITHER hands it a step: the predicate reads current: itself" \
  "$(printf '%s\n' "$BF_TREE_CALLS" | bf_second_arg)"

# THE MUTATION, so the row above is not passing over a detector that can never fire: a COPY
# of the library with the gate caller handed a step again must be caught by the same shape.
BF_MUT_DIR="$SANDBOX/bring-forward-mutant"; mkdir -p "$BF_MUT_DIR"
anchor file payload/scripts/lib/walls.sh 'plan_bring_forward "$PLAN")'
sed 's/plan_bring_forward "$PLAN")/plan_bring_forward "$PLAN" "$CURRENT")/' \
  "$BF_LIB" > "$BF_MUT_DIR/walls.sh"
expect_nonempty "…and a doctored copy that hands the gate caller a step IS caught" \
  "$(bf_calls "$BF_MUT_DIR/walls.sh" | bf_second_arg)"
# CONTROL — the same copy machinery, unmutated, is still clean.
cp "$BF_LIB" "$BF_MUT_DIR/walls.clean.sh"
expect_empty "control: an UNMUTATED copy is still clean" \
  "$(bf_calls "$BF_MUT_DIR/walls.clean.sh" | bf_second_arg)"

# THE THIRD-CALLER MUTATION (critic C9's FIRST clause — "a third caller appears unpinned" —
# which the two-named-file census could never catch by construction, whichever two files it
# named). A scratch tree shaped like `BF_TREE_DIRS`, carrying the two real callers PLUS one
# extra file naming `plan_bring_forward "…"` in a spot the old census never read
# (`payload/commands/`), must move the whole-tree count from 2 to 3.
BF_3RD_DIR="$SANDBOX/bring-forward-third-caller"
mkdir -p "$BF_3RD_DIR/hooks" "$BF_3RD_DIR/payload/scripts/lib" "$BF_3RD_DIR/payload/commands" \
  "$BF_3RD_DIR/payload/skills" "$BF_3RD_DIR/agents"
cp "$BF_LIB" "$BF_3RD_DIR/payload/scripts/lib/walls.sh"
cp "$BF_GSKILL" "$BF_3RD_DIR/hooks/canonical-sdlc-governing-skill.sh"
printf 'planted_third_caller() {\n  plan_bring_forward "$1"\n}\n' \
  > "$BF_3RD_DIR/payload/commands/planted-third-caller.sh"
BF_3RD_TREE_DIRS="$BF_3RD_DIR/hooks $BF_3RD_DIR/payload/scripts $BF_3RD_DIR/payload/commands $BF_3RD_DIR/payload/skills $BF_3RD_DIR/agents"
bf_3rd_calls() {
  grep -rn 'plan_bring_forward "' $BF_3RD_TREE_DIRS 2>/dev/null | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#'
}
expect_eq "…and a planted THIRD caller elsewhere in the tree IS caught: the count moves to 3" "3" \
  "$(bf_3rd_calls | grep -c 'plan_bring_forward "')"
# CONTROL — the same scratch tree with the plant removed reads back to 2, so the row above
# is reading the plant and not a miscounted copy.
rm -f "$BF_3RD_DIR/payload/commands/planted-third-caller.sh"
expect_eq "control: the same scratch tree with the plant removed reads back to 2" "2" \
  "$(bf_3rd_calls | grep -c 'plan_bring_forward "')"

section "RC — THE READ-ONLY ROLE SET: role_is_readonly equals the role files that disallow Write and Edit, plus Explore and Plan (wave-20 T7, AC-9.1)"
#
# ONE SET, TWO FACTS THAT MUST AGREE. `role_is_readonly` (payload/scripts/lib/roster.sh) is a
# constant, read on the dispatch path and in the read-only commit arm, because reading the
# role files at run time would add a file read to every Bash call (research D3-7). The role
# files are the other fact: a role whose frontmatter disallows Write and Edit is read-only in
# the harness's own terms. This section holds the two equal, both directions, plus the
# harness's two no-write types — so a new read-only role file without a set entry, or a set
# entry whose role file gained Write, turns this red.
RC_LIB="$BIONIC_SCRIPTS_DIR/payload/scripts/lib/roster.sh"
rc_disallows_write_edit() {  # <role file> -> 0 when its frontmatter disallows both
  /usr/bin/awk 'NR == 1 && /^---$/ { fm = 1; next } fm && /^---$/ { exit }
                fm && /^disallowedTools:/ { sub(/^disallowedTools:[ \t]*/, ""); print }' "$1" \
    | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' > "$SANDBOX/rc-dis.txt"
  /usr/bin/grep -qx Write "$SANDBOX/rc-dis.txt" && /usr/bin/grep -qx Edit "$SANDBOX/rc-dis.txt"
}
rc_scan() {  # <agents dir> -> sets RC_WANT, RC_WRITERS, RC_FILES from the role files in it
  RC_WANT="Explore Plan"; RC_WRITERS=""; RC_FILES=0
  local _rc_f _rc_name
  for _rc_f in "$1"/*.md; do
    [ -f "$_rc_f" ] || continue
    RC_FILES=$((RC_FILES + 1))
    _rc_name="bionic:$(basename "$_rc_f" .md)"
    if rc_disallows_write_edit "$_rc_f"; then RC_WANT="$RC_WANT $_rc_name"
    else RC_WRITERS="$RC_WRITERS $_rc_name"; fi
  done
}
rc_roles_ok() {  # <agents dir> -> yes when the scan read at least one role file; the set
                 # relation below is vacuous over none. A file count is not asked.
  ( rc_scan "$1"; [ "$RC_FILES" -ge 1 ] && echo yes || echo no )
}
rc_scan "$BIONIC_SCRIPTS_DIR/agents"
rc_sorted() { printf '%s\n' $1 | /usr/bin/grep -v '^$' | LC_ALL=C sort | tr '\n' ' '; }
RC_GOT=$( ( . "$RC_LIB" >/dev/null 2>&1 || exit 1; printf '%s' "${ROLE_READONLY_SET:-}" ) )
expect_eq "RC the role files read at all: at least one role file (the set relation below is not vacuous)" "yes" \
  "$(rc_roles_ok "$BIONIC_SCRIPTS_DIR/agents")"
expect_eq "RC ROLE_READONLY_SET = role files disallowing Write+Edit ∪ {Explore, Plan}" \
  "$(rc_sorted "$RC_WANT")" "$(rc_sorted "$RC_GOT")"
# THE PREDICATE, NOT ONLY THE CONSTANT: every member answers yes, every writer role and every
# harness writer type answers no, and a bare or foreign spelling of a read-only role is not
# ours (a consumer's own `researcher` agent may carry Write).
RC_BAD=""
for _rc_t in $RC_WANT; do
  ( . "$RC_LIB" >/dev/null 2>&1; role_is_readonly "$_rc_t" ) || RC_BAD="$RC_BAD yes-expected:$_rc_t"
done
for _rc_t in $RC_WRITERS fork general-purpose claude researcher test-runner acme:researcher explore; do
  ( . "$RC_LIB" >/dev/null 2>&1; role_is_readonly "$_rc_t" ) && RC_BAD="$RC_BAD no-expected:$_rc_t"
done
( . "$RC_LIB" >/dev/null 2>&1; role_is_readonly "" ) && RC_BAD="$RC_BAD no-expected:<empty>"
( . "$RC_LIB" >/dev/null 2>&1; role_is_readonly "bionic:researcher bionic:critic" ) \
  && RC_BAD="$RC_BAD no-expected:<two-words>"
expect_eq "RC role_is_readonly answers yes for exactly the set and no for every other type" "" "$RC_BAD"
# ONE SET, NOT TWO: the read-only commit arm (walls.sh ARM C) asks the same predicate rather
# than spelling the roles again, and so does the dispatch approval checkpoint.
expect_absent "RC walls.sh carries no second spelling of the read-only role list" \
  "bionic:test-runner|bionic:researcher" "$(cat "$BIONIC_SCRIPTS_DIR/payload/scripts/lib/walls.sh")"
expect_contains "RC …ARM C asks role_is_readonly" "role_is_readonly" \
  "$(cat "$BIONIC_SCRIPTS_DIR/payload/scripts/lib/walls.sh")"
expect_contains "RC …and so does the dispatch approval checkpoint" "role_is_readonly" \
  "$(cat "$PARTY_DP")"

# ============================================================
section "CG-close — ONE close predicate, four readers, one answer (epic-23 wave-20 T2, REQ-10 AC-10.1; D10)"
# ============================================================
#
# THE DEFECT. "Is this name closed" had four spellings (research D3 §REQ-10, triage-C claim 4,
# driven both ways): dispatch preflight closed a name on a `landing-swept/v1|state=MET` marker
# OR an ack taken after the row's launch; the sweeper's `row_acked` and the stop wall's
# occupancy pass closed it on ANY ack of the name, ever; the tick's `adopt_fold` closed it on
# any ack or any MET marker. So a name acked and then dispatched again was open to preflight
# and closed to the other three, and a MET-but-unacked row was closed to preflight and adopt
# and open to the sweeper and the stop wall. D10 gives the question one owner —
# `roster_open_names` in payload/scripts/lib/roster.sh: a name is closed by an ack whose `at=`
# is later than its latest live row's `launched_at=`, and by nothing else (ADR-034 d1).
#
# THE FIXTURE is one world per name, so each reader answers for exactly one history:
#   again  dispatched, acked, dispatched again         -> OPEN
#   met    dispatched, a MET marker, never acked        -> OPEN
#   done   dispatched, then acked                       -> CLOSED
# `done` is the paired positive: without a name every reader closes, "all four say open"
# would pass on readers that never close anything.
#
# EACH READER IS ASKED THROUGH ITS OWN SURFACE, never through the library, because the
# question is whether each reader CALLS the one predicate. Asking the library four times
# would agree with itself by construction.
#   preflight   the name-in-flight arm: a dispatch under the name is refused iff it is open
#   sweeper     the `verdict` machine line's `acked=` (yes = closed)
#   stop wall   the fill occupancy: writers=1 and one ready row; an open name holds the one
#               slot and the turn passes, a closed name frees it and the turn is refused
#   adopt_fold  the tick's fold, run from its own source text: an open name is folded
#
# THE STAMPS ARE LEXICAL ISO-8601 Z, as both writers stamp them (`date -u
# +%Y-%m-%dT%H:%M:%SZ` in the sweeper's `iso_now` and in preflight's row).

CGC_POKER="$BIONIC_HOOKS_DIR/session-poker.sh"
CGC_STOP="$BIONIC_HOOKS_DIR/stop.sh"
CGC_LIBDIR="${BIONIC_SCRIPTS_DIR}/payload/scripts/lib"
CGC_RING="$SANDBOX/cgc/pressure.ring"
mkdir -p "$SANDBOX/cgc"
# A CLEAR RING, so the stop wall's rung is its ceiling and nothing but the roster moves the
# width (tests/patrol-duties-gate.test.sh's CLEAR_RING, the same five fields).
printf '1700000000|80|0|0.1|16\n' > "$CGC_RING"
# RESEEDED BEFORE EVERY DRIVE, AND THE SENSORS PINNED. A reader that finds the window empty
# samples the machine into this ring under the pinned clock — and this suite runs beside
# other suites, so an unpinned sample reads the runner's real load and a later median lands
# in the warning band, halving the width for a reason that is not the fixture (§RG's pins).
CGC_ENV=(BIONIC_PRESSURE_RING="$CGC_RING" BIONIC_NOW_EPOCH=1700000000
         BIONIC_PROBE_FREE_PCT=80 BIONIC_PROBE_SWAP_PCT=0 BIONIC_PROBE_LOAD_1M=0.1 BIONIC_PROBE_FREE_MB=8192)
cgc_ring() { printf '1700000000|80|0|0.1|16\n' > "$CGC_RING"; }

cgc_ack() {  # <ledger> <at> <name> — the sweeper ledger's ack line, in its writer's shape
  [ -f "$1" ] || printf '# bionic session sweeper ledger — schema sweeper-ledger/v1 — machine-local, safe to delete\n' > "$1"
  printf 'sweeper-ledger/v1|event=ack|at=%s|epoch=0|pid=1|session=%s|name=%s|by=patrol|reason=landed\n' \
    "$2" "$SID_A" "$3" >> "$1"
}
cgc_row() {  # <roster> <name> <launched_at> <tool_use_id>
  roster_row_fixture status=intended session="$SID_A" name="$2" agent_id= \
    launched_at="$3" tool_use_id="$4" deliverable= >> "$1"
}

# THE PLAN the stop wall and preflight read: a live ledger (current: 4) with the given budget
# line and the given number of ready rows.
cgc_plan() {  # <path> <budget line, verbatim, or empty> <ready rows>
  local i
  mkdir -p "$(dirname "$1")"
  {
    printf -- '---\ngoverning-skill: canonical-sdlc\ncanonical_sdlc_version: 14\n'
    printf 'intent: build\nrigor: double\nscale: wave\n'
    [ -z "$2" ] || printf '%s\n' "$2"
    printf -- '---\n\n# Fixture plan\n\n## SDLC State\n\nintegration-branch: main\n'
    printf 'current: 4\napproved-by: fixture\n\n- Step 3: prior evidence\n\n'
    printf '## Tasks\n\n'
    printf '| id | step | kind | task | agent | deps | size | serves | Files | status | worktree |\n'
    printf '|---|---|---|---|---|---|---|---|---|---|---|\n'
    for i in $(seq 1 "$3"); do
      printf '| R%s | 4 | build | ready row %s | implementor | — | 30m | REQ-x | r%s.sh | pending | — |\n' \
        "$i" "$i" "$i"
    done
  } > "$1"
}

# One world holding ONE name's history. The plan carries writers=1 and one ready row, which is
# the stop wall's whole instrument (the header above).
cgc_world() {  # <case: again|met|done> -> repo path
  local r ro le
  r=$(new_repo "cgc-$1")
  ro="$r/.bionic/tmp/roster-$SID_A.state"
  le="$r/.bionic/tmp/sweeper-$SID_A.state"
  roster_header > "$ro"
  case "$1" in
    again)
      cgc_row "$ro" cgc-again 2026-09-01T00:00:00Z toolu_01CGCAGAIN1
      cgc_ack "$le" 2026-09-01T01:00:00Z cgc-again
      cgc_row "$ro" cgc-again 2026-09-01T02:00:00Z toolu_01CGCAGAIN2
      ;;
    met)
      cgc_row "$ro" cgc-met 2026-09-01T00:00:00Z toolu_01CGCMET
      swept_marker_write "$ro" 2026-09-01T01:00:00Z "$SID_A" cgc-met "" MET
      ;;
    done)
      cgc_row "$ro" cgc-done 2026-09-01T00:00:00Z toolu_01CGCDONE
      cgc_ack "$le" 2026-09-01T01:00:00Z cgc-done
      ;;
  esac
  cgc_plan "$r/.bionic/docs/plans/epic-99/cgc.plan.md" \
    'parallel-budget: writers=1 suites=4 worktrees=32 test_jobs=8 source=user' 1
  s4_bind "$r" "$SID_A" "$r/.bionic/docs/plans/epic-99/cgc.plan.md"
  s4_attest "$r" "$SID_A"
  jq -nc '{type:"user",isMeta:true,isSidechain:false,userType:"external",
           message:{role:"user",content:"carry on"}}' > "$r/cgc-transcript.jsonl"
  printf '%s' "$r"
}

cgc_preflight() {  # <repo> <name> -> open | closed
  local out
  out=$(mk_agent_payload "$SID_A" "$1" \
    | jq -c --arg n "$2" --arg t "$1/cgc-transcript.jsonl" \
        '.tool_input.name = $n | .transcript_path = $t' \
    | env CLAUDE_CODE_SESSION_ID="$SID_A" bash "$PARTY_DP" 2>&1)
  case "$out" in *"that name is in flight"*) printf 'open' ;; *) printf 'closed' ;; esac
}
cgc_sweeper() {  # <repo> <name> -> open | closed | other:<line>
  local line
  line=$( ( cd "$1" && CLAUDE_CODE_SESSION_ID="$SID_A" bash "$SWEEPER" verdict "$2" 2>/dev/null ) \
    | grep -F 'landing-verdict/v1|' | head -1)
  case "$line" in
    *"|acked=yes|"*) printf 'closed' ;;
    *"|acked=no|"*)  printf 'open' ;;
    *) printf 'other:%s' "$line" ;;
  esac
}
cgc_stopwall() {  # <repo> -> open | closed | other:<reason>
  local out
  cgc_ring
  out=$(s4_stop_payload "$1" "$SID_A" "$1/cgc-transcript.jsonl" \
    | env CLAUDE_CODE_SESSION_ID="$SID_A" "${CGC_ENV[@]}" bash "$CGC_STOP" 2>/dev/null)
  case "$out" in
    *"ready with room:"*"R1"*) printf 'closed' ;;
    *"ready with room:"*|*"Fill budget unreadable"*) printf 'other:%s' "$out" ;;
    *) printf 'open' ;;
  esac
}
cgc_adopt() {  # <repo> <name> -> open | closed
  local out
  out=$( ( BIONIC_LIB_WANT=""
           . "$CGC_LIBDIR/roster.sh" >/dev/null 2>&1
           eval "$(awk '/^adopt_fold\(\) \{/,/^\}/' "$CGC_POKER")"
           adopt_fold "$1/.bionic/tmp/roster-$SID_A.state" "$1/.bionic/tmp/sweeper-$SID_A.state" ) 2>/dev/null \
         | cut -d'|' -f1)
  if grep -qxF -- "$2" <<< "$out"; then printf 'open'; else printf 'closed'; fi
}

expect_nonempty "CG-close meta: adopt_fold's source text is extractable" \
  "$(awk '/^adopt_fold\(\) \{/,/^\}/' "$CGC_POKER")"

for _cgc in again:open met:open done:closed; do
  _cgc_case="${_cgc%%:*}"; _cgc_want="${_cgc#*:}"; _cgc_name="cgc-$_cgc_case"
  _cgc_r=$(cgc_world "$_cgc_case")
  _cgc_sw=$(cgc_sweeper "$_cgc_r" "$_cgc_name")
  _cgc_st=$(cgc_stopwall "$_cgc_r")
  _cgc_ad=$(cgc_adopt "$_cgc_r" "$_cgc_name")
  # PREFLIGHT LAST: an admitted dispatch journals a row, and that row is a new history.
  _cgc_pf=$(cgc_preflight "$_cgc_r" "$_cgc_name")
  expect_eq "CG-close ${_cgc_case}: dispatch preflight answers ${_cgc_want}" "$_cgc_want" "$_cgc_pf"
  expect_eq "CG-close ${_cgc_case}: the sweeper's acked= answers ${_cgc_want}" "$_cgc_want" "$_cgc_sw"
  expect_eq "CG-close ${_cgc_case}: the stop wall's occupancy answers ${_cgc_want}" "$_cgc_want" "$_cgc_st"
  expect_eq "CG-close ${_cgc_case}: the tick's adopt_fold answers ${_cgc_want}" "$_cgc_want" "$_cgc_ad"
done

# ONE DEFINITION, AND EVERY READER CALLS IT. The behaviour above is the proof; this names the
# owner, so a fifth reader grown with a private ack set fails here rather than in the field.
expect_eq "CG-close roster_open_names is defined exactly once in the shipped tree" "1" \
  "$( { grep -l '^roster_open_names()' "$CGC_LIBDIR"/*.sh; grep -l '^roster_open_names()' "$BIONIC_HOOKS_DIR"/*.sh; } 2>/dev/null | sort -u | wc -l | tr -d ' ')"
for _cgc_f in "$PARTY_DP" "$SWEEPER" "$CGC_LIBDIR/stop.sh" "$CGC_POKER"; do
  expect_true "CG-close ${_cgc_f##*/} calls roster_open_names" \
    grep -q 'roster_open_names "' "$_cgc_f"
done
expect_eq "CG-close no reader keeps a private name-only ack set (acked[an] = 1)" "0" \
  "$(cat "$PARTY_DP" "$SWEEPER" "$CGC_LIBDIR/stop.sh" "$CGC_POKER" | grep -c 'acked\[an\] = 1' || true)"

# THE MUTATION PROOF (research D3 §CG-close): the stop wall's old name-only reading restored
# in a copy of the library, nothing else touched, must make `again` disagree again.
CGC_MUT="$SANDBOX/cgc-mut"
CGC_MUT_HOOK="$(plant_hook_tree "$CGC_MUT")"
cp "$CGC_STOP" "$CGC_MUT_HOOK/stop.sh"
anchor file payload/scripts/lib/stop.sh 'FILL_OPEN="$(roster_open_names '
awk '{
  if (index($0, "FILL_OPEN=\"$(roster_open_names ") > 0) {
    print "      FILL_OPEN=1  # mutant: the name-only reading, which reads the fixture as closed"
    print "      grep -q \"event=ack\" \"$FILL_ACKS\" 2>/dev/null && FILL_OPEN=0"
    next
  }
  print }' "$CGC_LIBDIR/stop.sh" > "$CGC_MUT/scripts/lib/stop.sh"
expect_eq "CG-close meta: the mutant planted its name-only line" "1" \
  "$(grep -c 'mutant: the name-only reading' "$CGC_MUT/scripts/lib/stop.sh")"
_cgc_r=$(cgc_world again)
cgc_ring
_cgc_mut=$(s4_stop_payload "$_cgc_r" "$SID_A" "$_cgc_r/cgc-transcript.jsonl" \
  | env CLAUDE_CODE_SESSION_ID="$SID_A" "${CGC_ENV[@]}" bash "$CGC_MUT_HOOK/stop.sh" 2>/dev/null)
expect_contains "CG-close MUTANT a name-only stop wall frees the re-dispatched name's slot (the row discriminates)" \
  "ready with room:" "$_cgc_mut"

# ============================================================
section "CG-close-all — the three remaining readers ask the one close predicate (epic-23 wave-20 T17, REQ-10 AC-10.1; D10)"
# ============================================================
#
# THE DEFECT (T2's carry-over, approved 2026-09-23). CG-close made the four readers D10 named
# agree. Three more readers of "is this name closed" still closed it on a
# `landing-swept/v1|…|state=MET` marker alone and never asked `roster_open_names`:
#   session-start   the post-/clear block's predecessor open-row count
#   live_ids        `live_ids_of_name`, the stop wall's ambiguity refusal and
#                   `adopt_write_row`'s "is this name already live here"
#   patrol          `patrol_roster_state`, doctor's and the Patrol report's `open=`
# So after a /clear a MET-but-unacked name read closed to all three and open to the four.
#
# ONE FIXTURE PER HISTORY, each reader asked through its own entry point, plus the sweeper's
# `acked=` (one of T2's four, driven as the hook) as the reference answer:
#   met    dispatched, a MET marker, never acked   -> OPEN   (the carry-over's case)
#   again  dispatched, acked, dispatched again     -> OPEN
#   done   dispatched, a MET marker, then acked    -> CLOSED (the paired positive)
# The rows carry agent ids (an intended row, then its identified row, one launch stamp), since
# `live_ids_of_name` answers ids and an id-less row is not an identity to it.

CGA_CLAUDE_HOME="$SANDBOX/cga-home"
mkdir -p "$CGA_CLAUDE_HOME"
cga_rows() {  # <roster> <name> <agent id> <launched_at>
  roster_row_fixture status=intended session="$SID_A" name="$2" agent_id= \
    launched_at="$4" tool_use_id=toolu_01CGA deliverable= >> "$1"
  roster_row_fixture status=identified session="$SID_A" name="$2" agent_id="$3" \
    launched_at="$4" tool_use_id=toolu_01CGA deliverable= >> "$1"
}
cga_world() {  # <case: met|again|done> [repo label] -> repo path
  local r ro le
  r=$(new_repo "${2:-cga-$1}")
  ro="$r/.bionic/tmp/roster-$SID_A.state"
  le="$r/.bionic/tmp/sweeper-$SID_A.state"
  roster_header > "$ro"
  case "$1" in
    met)
      cga_rows "$ro" cga-met acga-met-1 2026-09-01T00:00:00Z
      swept_marker_write "$ro" 2026-09-01T01:00:00Z "$SID_A" cga-met acga-met-1 MET
      ;;
    again)
      cga_rows "$ro" cga-again acga-again-1 2026-09-01T00:00:00Z
      cgc_ack "$le" 2026-09-01T01:00:00Z cga-again
      cga_rows "$ro" cga-again acga-again-2 2026-09-01T02:00:00Z
      ;;
    done)
      cga_rows "$ro" cga-done acga-done-1 2026-09-01T00:00:00Z
      swept_marker_write "$ro" 2026-09-01T00:30:00Z "$SID_A" cga-done acga-done-1 MET
      cgc_ack "$le" 2026-09-01T01:00:00Z cga-done
      ;;
  esac
  printf '%s' "$r"
}

# SESSION-START: the hook, driven as a /clear into SID_B, lists SID_A's roster iff it counts
# an open row there.
cga_session_start() {  # <repo> [hook] -> open | closed
  local out
  out=$( cd "$1" && printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s","hook_event_name":"SessionStart","source":"clear"}' \
           "$SID_B" "$CGA_CLAUDE_HOME/t.jsonl" "$1" \
         | env CLAUDE_CODE_SESSION_ID="$SID_B" BIONIC_CLAUDE_HOME="$CGA_CLAUDE_HOME" \
             bash "${2:-$BIONIC_HOOKS_DIR/session-start.sh}" 2>/dev/null )
  case "$out" in *"open row(s) — roster-$SID_A.state"*) printf 'open' ;; *) printf 'closed' ;; esac
}
# LIVE_IDS: the library function the two walls call, with the roster they set.
cga_live_ids() {  # <repo> <name> [lib dir] -> the live ids, space-joined
  ( BIONIC_LIB_WANT=""
    . "${3:-$CGC_LIBDIR}/roster.sh" >/dev/null 2>&1
    ROSTER_FILE="$1/.bionic/tmp/roster-$SID_A.state" live_ids_of_name "$2" ) 2>/dev/null \
    | tr '\n' ' ' | sed 's/ $//'
}
# PATROL: `patrol_roster_state`'s open= for SID_A (one name per world, so 1 or 0).
cga_patrol() {  # <repo> [lib dir] -> open | closed | other:<line>
  local line
  line=$( ( . "${2:-$CGC_LIBDIR}/patrol.sh" >/dev/null 2>&1 \
            && patrol_roster_state "$1" "$SID_A" ) 2>/dev/null )
  case "$line" in
    *"|open=1|"*) printf 'open' ;;
    *"|open=0|"*) printf 'closed' ;;
    *) printf 'other:%s' "$line" ;;
  esac
}

for _cga in met:open:acga-met-1 again:open:acga-again-2 done:closed:; do
  _cga_case="${_cga%%:*}"; _cga_rest="${_cga#*:}"; _cga_want="${_cga_rest%%:*}"; _cga_ids="${_cga_rest#*:}"
  _cga_name="cga-$_cga_case"
  _cga_r=$(cga_world "$_cga_case")
  _cga_sw=$(cgc_sweeper "$_cga_r" "$_cga_name")
  _cga_li=$(cga_live_ids "$_cga_r" "$_cga_name")
  _cga_lo=closed; [ -n "$_cga_li" ] && _cga_lo=open
  _cga_pa=$(cga_patrol "$_cga_r")
  # SESSION-START LAST: its sweep may tidy a dead predecessor's files on the way out.
  _cga_ss=$(cga_session_start "$_cga_r")
  expect_eq "CG-close-all ${_cga_case}: the sweeper's acked= (T2's reference) answers ${_cga_want}" "$_cga_want" "$_cga_sw"
  expect_eq "CG-close-all ${_cga_case}: session-start's predecessor count answers ${_cga_want}" "$_cga_want" "$_cga_ss"
  expect_eq "CG-close-all ${_cga_case}: live_ids_of_name answers ${_cga_want}" "$_cga_want" "$_cga_lo"
  expect_eq "CG-close-all ${_cga_case}: live_ids_of_name names only the undischarged id" "$_cga_ids" "$_cga_li"
  expect_eq "CG-close-all ${_cga_case}: patrol_roster_state answers ${_cga_want}" "$_cga_want" "$_cga_pa"
  expect_eq "CG-close-all ${_cga_case}: the four readers give ONE answer" "1" \
    "$(printf '%s\n' "$_cga_sw" "$_cga_ss" "$_cga_lo" "$_cga_pa" | sort -u | wc -l | tr -d ' ')"
done

# EVERY READER NAMES THE ONE PREDICATE, and none keeps a MET close of its own. The two
# `roster_open_names "` callers call it by name; session-start's count goes through
# `roster_open_counts`, which runs the same awk text over many rosters in one process (the
# REQ-6/P9 bound on predecessor files), so the pin there is that the two share `_ROSTER_OPEN_AWK`.
CGA_SS="$BIONIC_HOOKS_DIR/session-start.sh"
expect_true "CG-close-all patrol.sh's patrol_roster_state calls roster_open_names" \
  grep -q 'roster_open_names "' "$CGC_LIBDIR/patrol.sh"
expect_eq "CG-close-all live_ids_of_name calls roster_open_names" "1" \
  "$(awk '/^live_ids_of_name\(\) \{/,/^\}/' "$CGC_LIBDIR/roster.sh" | grep -c 'roster_open_names "' | tr -d ' ')"
expect_true "CG-close-all session-start.sh counts through roster_open_counts" \
  grep -q '| roster_open_counts' "$CGA_SS"
expect_eq "CG-close-all roster_open_names and roster_open_counts run one awk text" "2" \
  "$( { awk '/^roster_open_names\(\) \{/,/^\}/' "$CGC_LIBDIR/roster.sh"; awk '/^roster_open_counts\(\) \{/,/^\}/' "$CGC_LIBDIR/roster.sh"; } \
      | grep -c '_ROSTER_OPEN_AWK' | tr -d ' ')"
expect_eq "CG-close-all none of the three keeps a MET close (state == MET, or a state=MET field match)" "0" \
  "$(cat "$CGA_SS" "$CGC_LIBDIR/roster.sh" "$CGC_LIBDIR/patrol.sh" \
      | grep -v '^[[:space:]]*#' | grep -cE '"state"\) == "MET"|== "state=MET"' || true)"

# THE MUTATION PROOF: patrol_roster_state's old reading restored in a copy of the library —
# a name with a MET marker is dropped from the open set — nothing else touched. (The mutant
# selects the marker by its `state=MET` field alone: no roster row carries `state=`, and S17
# forbids a suite to spell the marker's schema token.) The one-answer
# row over the `met` world must go red: the mutant says closed where the other three say open.
CGA_MUT="$SANDBOX/cga-mut"
plant_hook_tree "$CGA_MUT" >/dev/null
anchor file payload/scripts/lib/patrol.sh 'open_names="$(roster_open_names '
awk '{
  if (index($0, "open_names=\"$(roster_open_names ") > 0) {
    print "  open_names=\"$(roster_open_names \"$f\" \"$ledger\" | grep -vxF -e \"$(grep \"|state=MET\" \"$f\" | tr \"|\" \"\\n\" | sed -n \"s/^name=//p\")\")\"  # mutant: a MET marker closes"
    next
  }
  print }' "$CGC_LIBDIR/patrol.sh" > "$CGA_MUT/scripts/lib/patrol.sh"
expect_eq "CG-close-all meta: the mutant planted its MET close" "1" \
  "$(grep -c 'mutant: a MET marker closes' "$CGA_MUT/scripts/lib/patrol.sh")"
_cga_r=$(cga_world met cga-mut-met)
_cga_mpa=$(cga_patrol "$_cga_r" "$CGA_MUT/scripts/lib")
_cga_msw=$(cgc_sweeper "$_cga_r" cga-met)
expect_eq "CG-close-all MUTANT a MET-closing patrol_roster_state answers closed on the met world" "closed" "$_cga_mpa"
expect_eq "CG-close-all MUTANT …so the one-answer row sees two answers (the row discriminates)" "2" \
  "$(printf '%s\n' "$_cga_msw" "$_cga_mpa" | sort -u | wc -l | tr -d ' ')"

# ============================================================
section "CG-close T20 — the last two MET-closing readers give the four's answer (epic-23 wave-20 T20, REQ-10 AC-10.1; D10)"
# ============================================================
#
# THE DEFECT (found by T17, approved by Chris). After T2 and T17 two readers still closed a
# name on a `landing-swept/v1|…|state=MET` marker alone, and never asked `roster_open_names`:
#   recorder     hooks/execution-recorder.sh's duplicate-start check (DUP_PRIOR): a second
#                SubagentStart for an `identified` id is journalled `duplicate-start` unless
#                the name's contract is closed — and a MET marker read as closed
#   kill floor   hooks/session-poker.sh's `youngest_suite_writer`: the EMERGENCY arm's one
#                stop address skipped every name carrying a MET marker (retired with the
#                EMERGENCY line, wave-28 T13: the two readers left are driven below)
# So on a MET-but-unacked name the recorder let a resumed copy start unjournalled and the
# kill floor named nobody, while the four readers CG-close drives called the same name open.
#
# ONE FIXTURE PER HISTORY, the two new readers and one of the four (adopt_fold, T2's cheapest
# surface) driven over it, each through its own surface:
#   met    a suite-claiming row, identified, a MET marker, never acked   -> OPEN
#   done   the same, then acked after its launch                          -> CLOSED
# `done` is the paired positive: without it, readers that never close anything would pass.
#   recorder     a second SubagentStart for the identified id: journalled = open
#   adopt_fold   CG-close's own driver (`cgc_adopt`)
# THE RECORDER IS DRIVEN LAST: the row it journals is a new history for the next reader.

cgt_world() {  # <case: met|done> -> repo path
  local r ro le nm="cgt-$1"
  r=$(new_repo "cgt-$1")
  ro="$r/.bionic/tmp/roster-$SID_A.state"
  le="$r/.bionic/tmp/sweeper-$SID_A.state"
  roster_header > "$ro"
  roster_row_fixture status=intended session="$SID_A" name="$nm" agent_id= \
    launched_at=2026-09-01T00:00:00Z claims="bash tests/run.sh" tool_use_id="toolu_01CGT$1" deliverable= >> "$ro"
  roster_row_fixture status=identified session="$SID_A" name="$nm" agent_id="acgt$1-5f0e3c2a9b7d4e61" \
    launched_at=2026-09-01T00:00:00Z claims="bash tests/run.sh" tool_use_id="toolu_01CGT$1" deliverable= >> "$ro"
  swept_marker_write "$ro" 2026-09-01T01:00:00Z "$SID_A" "$nm" "acgt$1-5f0e3c2a9b7d4e61" MET
  [ "$1" != done ] || cgc_ack "$le" 2026-09-01T01:00:00Z "$nm"
  cgc_plan "$r/.bionic/docs/plans/epic-99/cgt.plan.md" \
    'parallel-budget: writers=1 suites=4 worktrees=32 test_jobs=8 source=user' 1
  s4_bind "$r" "$SID_A" "$r/.bionic/docs/plans/epic-99/cgt.plan.md"
  s4_attest "$r" "$SID_A"
  jq -nc '{type:"user",isMeta:true,isSidechain:false,userType:"external",
           message:{role:"user",content:"carry on"}}' > "$r/cgc-transcript.jsonl"
  printf '%s' "$r"
}

cgt_recorder() {  # <repo> <case> [recorder] -> open | closed
  local ro="$1/.bionic/tmp/roster-$SID_A.state"
  mk_start_payload "$SID_A" "$1/cgc-transcript.jsonl" "$1" general-purpose "acgt$2-5f0e3c2a9b7d4e61" \
    | env CLAUDE_CODE_SESSION_ID="$SID_A" bash "${3:-$PARTY_ER}" >/dev/null 2>&1
  if grep -qF "|status=duplicate-start|" "$ro"; then printf 'open'; else printf 'closed'; fi
}
for _cgt in met:open done:closed; do
  _cgt_case="${_cgt%%:*}"; _cgt_want="${_cgt#*:}"; _cgt_name="cgt-$_cgt_case"
  _cgt_r=$(cgt_world "$_cgt_case")
  _cgt_ad=$(cgc_adopt "$_cgt_r" "$_cgt_name")
  _cgt_er=$(cgt_recorder "$_cgt_r" "$_cgt_case")
  expect_eq "CG-close T20 ${_cgt_case}: the tick's adopt_fold (one of the four) answers ${_cgt_want}" "$_cgt_want" "$_cgt_ad"
  expect_eq "CG-close T20 ${_cgt_case}: the recorder's duplicate-start check answers ${_cgt_want}" "$_cgt_want" "$_cgt_er"
  expect_eq "CG-close T20 ${_cgt_case}: ONE answer across the two readers" "1" \
    "$(printf '%s\n' "$_cgt_ad" "$_cgt_er" | sort -u | wc -l | tr -d ' ')"
done

# BOTH NEW READERS NAME THE ONE PREDICATE, and neither keeps a private MET close. The
# behaviour above is the proof; this names the owner, as CG-close does for the four.
for _cgt_f in "$PARTY_ER" "$CGC_POKER"; do
  expect_true "CG-close T20 ${_cgt_f##*/} calls roster_open_names" \
    grep -q 'roster_open_names "' "$_cgt_f"
done

# THE MUTATION PROOF: each new reader's old MET close restored in a copy, nothing else
# touched, must answer `closed` on `met` — the one-answer row above would then go red.
CGT_MUT="$SANDBOX/cgt-mut"
CGT_MUT_HOOK="$(plant_hook_tree "$CGT_MUT")"
cp "$SWEEPER" "$CGT_MUT_HOOK/session-sweeper.sh"   # the tick refuses without its sibling
# The marker token is read off the shared constant, never spelled (§S17's scan).
anchor file hooks/execution-recorder.sh 'grep -qxF -- "$DUP_NAME" <<< "$(roster_open_names '
awk -v mk="${SWEPT_SCHEMA}|" '{
  if (index($0, "grep -qxF -- \"$DUP_NAME\" <<< \"$(roster_open_names ") > 0) {
    print "    grep -F \"" mk "\" \"$ROSTER_FILE\" | grep -F \"|name=${DUP_NAME}|\" | grep -qF \"|state=MET\" && DUP_PRIOR=\"\"  # mutant: the MET close"
    next
  }
  print }' "$PARTY_ER" > "$CGT_MUT_HOOK/execution-recorder.sh"
expect_eq "CG-close T20 meta: the recorder mutant planted its MET close" "1" \
  "$(grep -c 'mutant: the MET close' "$CGT_MUT_HOOK/execution-recorder.sh")"
_cgt_r=$(cgt_world met)
expect_eq "CG-close T20 MUTANT a MET-closing recorder journals no duplicate on a MET-but-unacked name (the row discriminates)" \
  "closed" "$(cgt_recorder "$_cgt_r" met "$CGT_MUT_HOOK/execution-recorder.sh")"

# ============================================================
section "CG-close T20b — a restart after an ack is counted again by every occupancy reader (epic-23 wave-20 T20b, review R5)"
# ============================================================
#
# THE HISTORY. `done` above (identified, MET, then acked) proves the ack closes the name to
# all three readers. This proves the close is not permanent: the SAME agent id starts a THIRD
# time — a restart after the ack, which is exactly what messaging a stopped agent does (R2) —
# and T20b's fix stamps the fresh identification with its OWN launch time rather than the
# closed lineage's original one (review R5; walk §9b/9c). Afterwards `roster_open_names`, the
# recorder's own duplicate-start check on a FOURTH start, and the sweeper's `acked=` (against
# the reused name, T2's reference) must all agree the name is open again — while the sweeper's
# ledger still carries the old ack as history, unrewritten and unconsulted for anything but
# its stamp.
_cgtb_r=$(cgt_world done)
_cgtb_name="cgt-done"
_cgtb_id="acgtdone-5f0e3c2a9b7d4e61"
_cgtb_roster="$_cgtb_r/.bionic/tmp/roster-$SID_A.state"
_cgtb_ledger="$_cgtb_r/.bionic/tmp/sweeper-$SID_A.state"

# THE RESTART: a THIRD SubagentStart for the id `cgt_world done` already identified once
# (the world's own build is the first identification; `done`'s ack closes that lineage).
# THE PAYLOAD NAMES THE DISPATCH, not "general-purpose" as `cgt_recorder`'s own calls do:
# `cgt_world`'s `intended` row carries no agent_id (a teammate's own shape), so the
# fallthrough this restart drives can only re-identify through the NAME join — which reads
# `agent_type`, and needs it to equal the roster's `name=` to find that row at all.
mk_start_payload "$SID_A" "$_cgtb_r/cgc-transcript.jsonl" "$_cgtb_r" "$_cgtb_name" "$_cgtb_id" \
  | env CLAUDE_CODE_SESSION_ID="$SID_A" bash "$PARTY_ER" >/dev/null 2>&1
expect_eq "CG-close T20b: the restart is not journalled a duplicate (a reused, finished lineage)" \
  "0" "$(grep -c '|status=duplicate-start|' "$_cgtb_roster")"
expect_eq "CG-close T20b: …and it identifies a second time" \
  "2" "$(grep -c '|status=identified|' "$_cgtb_roster")"
# RE-AUTHORED (epic-23 wave-20 T20c, critic C2-2): the fresh time rides `restarted_at=`, and
# `launched_at` stays the contract's launch, which the sweeper dates the deliverable against.
_cgtb_row2=$(grep '|status=identified|' "$_cgtb_roster" | tail -1)
_cgtb_ra2=$(printf '%s' "$_cgtb_row2" | tr '|' '\n' | grep '^restarted_at=' | cut -d= -f2-)
expect_true "CG-close T20b: …carrying a FRESH restart stamp, later than the closed lineage's ack (T20c: was \"…carrying a FRESH launch, not the closed lineage's original\", expect_ne on launched_at)" \
  test "$_cgtb_ra2" \> "2026-09-01T01:00:00Z"
expect_contains "CG-close T20b: …while launched_at stays the contract's own launch (T20c)" \
  "|launched_at=2026-09-01T00:00:00Z|" "$_cgtb_row2"

_cgtb_open=$( ( BIONIC_LIB_WANT=""; . "$CGC_LIBDIR/roster.sh" >/dev/null 2>&1
                roster_open_names "$_cgtb_roster" "$_cgtb_ledger" "$SID_A" ) 2>/dev/null )
expect_contains "CG-close T20b: roster_open_names counts the restarted name open again" \
  "$_cgtb_name" "$_cgtb_open"

# A FOURTH START now against the OPEN name IS a live duplicate — proving the recorder's own
# check reads its own fresh row, not the finished lineage it just replaced.
mk_start_payload "$SID_A" "$_cgtb_r/cgc-transcript.jsonl" "$_cgtb_r" "$_cgtb_name" "$_cgtb_id" \
  | env CLAUDE_CODE_SESSION_ID="$SID_A" bash "$PARTY_ER" >/dev/null 2>&1
expect_eq "CG-close T20b: a start against the now-open name IS a live duplicate" \
  "1" "$(grep -c '|status=duplicate-start|' "$_cgtb_roster")"

# THE SWEEPER'S OWN VERDICT (T2's reference), against the reused name: the ack is history, not
# a lock — exactly the shape CG-close's own `again` case already proves for this reader.
expect_eq "CG-close T20b: the sweeper's acked= (T2's reference) agrees: open" \
  "open" "$(cgc_sweeper "$_cgtb_r" "$_cgtb_name")"

# ============================================================
section "CG-close T20c — after a restart, occupancy reads open and the contract reads MET, to every party (epic-23 wave-20 T20c, critic C2-2)"
# ============================================================
#
# THE HISTORY (critic C2-2). A contract with a real deliverable is launched, delivered and
# acked; then the SAME id starts again — the restart a message to a finished agent causes.
# Two questions, and each party answers both the same way:
#   occupancy  the name is open again: the recorder's own duplicate-start check (a further
#              start is journalled), `roster_open_names`, and the sweeper's acked=no
#   contract   MET: the deliverable written after the launch and before the ack still
#              satisfies it, because the restart moved no clock the sweeper dates it against
# Until T20c the recorder moved `launched_at` itself, so occupancy agreed and the contract
# read UNMET — the one row this section adds is the proof that the parties agree on BOTH.
_cgtc_r=$(new_repo cgtc-restart)
_cgtc_name="cgtc-w"
_cgtc_id="acgtc-7a1e0c3b5d9f2e64"
_cgtc_roster="$_cgtc_r/.bionic/tmp/roster-$SID_A.state"
_cgtc_ledger="$_cgtc_r/.bionic/tmp/sweeper-$SID_A.state"
_cgtc_del="$_cgtc_r/cgtc-report.md"
echo delivered > "$_cgtc_del"
touch -t 202609011200 "$_cgtc_del"      # after the launch below, in any zone within 12 h of UTC
roster_header > "$_cgtc_roster"
: > "$_cgtc_r/cgtc.done"                 # the agent said so (wave-24 T9, D3)
roster_row_fixture status=confirmed session="$SID_A" name="$_cgtc_name" agent_id="$_cgtc_id" \
  launched_at=2026-09-01T00:00:00Z deliverable="$_cgtc_del" "done=$_cgtc_r/cgtc.done" tool_use_id=toolu_01CGTC >> "$_cgtc_roster"
roster_row_fixture status=identified session="$SID_A" name="$_cgtc_name" agent_id="$_cgtc_id" \
  launched_at=2026-09-01T00:00:00Z deliverable="$_cgtc_del" "done=$_cgtc_r/cgtc.done" tool_use_id=toolu_01CGTC >> "$_cgtc_roster"
cgc_ack "$_cgtc_ledger" 2026-09-02T00:00:00Z "$_cgtc_name"
jq -nc '{type:"user",isMeta:true,isSidechain:false,userType:"external",
         message:{role:"user",content:"carry on"}}' > "$_cgtc_r/cgc-transcript.jsonl"
_cgtc_verdict() {
  ( cd "$_cgtc_r" && CLAUDE_CODE_SESSION_ID="$SID_A" bash "$SWEEPER" verdict "$_cgtc_name" 2>/dev/null ) \
    | grep -F 'landing-verdict/v1|' | head -1
}
expect_contains "CG-close T20c precondition: delivered and acked — MET, acked=yes" \
  "|state=MET|acked=yes|" "$(_cgtc_verdict)"

# THE RESTART, through the real recorder.
mk_start_payload "$SID_A" "$_cgtc_r/cgc-transcript.jsonl" "$_cgtc_r" general-purpose "$_cgtc_id" \
  | env CLAUDE_CODE_SESSION_ID="$SID_A" bash "$PARTY_ER" >/dev/null 2>&1
_cgtc_open=$( ( BIONIC_LIB_WANT=""; . "$CGC_LIBDIR/roster.sh" >/dev/null 2>&1
                roster_open_names "$_cgtc_roster" "$_cgtc_ledger" "$SID_A" ) 2>/dev/null )
_cgtc_line=$(_cgtc_verdict)
case "$_cgtc_line" in *"|acked=no|"*) _cgtc_sw_occ=open ;; *"|acked=yes|"*) _cgtc_sw_occ=closed ;; *) _cgtc_sw_occ="other:$_cgtc_line" ;; esac
if grep -qxF -- "$_cgtc_name" <<< "$_cgtc_open"; then _cgtc_pr_occ=open; else _cgtc_pr_occ=closed; fi
# The recorder's own occupancy answer: a FURTHER start against an open name is a live duplicate.
mk_start_payload "$SID_A" "$_cgtc_r/cgc-transcript.jsonl" "$_cgtc_r" general-purpose "$_cgtc_id" \
  | env CLAUDE_CODE_SESSION_ID="$SID_A" bash "$PARTY_ER" >/dev/null 2>&1
if grep -qF '|status=duplicate-start|' "$_cgtc_roster"; then _cgtc_er_occ=open; else _cgtc_er_occ=closed; fi
expect_eq "CG-close T20c occupancy: the recorder, roster_open_names and the sweeper's acked= all answer open" \
  "open open open" "$_cgtc_er_occ $_cgtc_pr_occ $_cgtc_sw_occ"
expect_contains "CG-close T20c contract: the sweeper reads the restarted row MET, not UNMET" \
  "|state=MET|acked=no|" "$_cgtc_line"
expect_contains "CG-close T20c contract: …because the restart row the recorder wrote keeps the contract's launch" \
  "|launched_at=2026-09-01T00:00:00Z|" "$(grep -F '|status=identified|' "$_cgtc_roster" | tail -1)"
expect_contains "CG-close T20c contract: …and the duplicate the further start journalled keeps it too" \
  "|launched_at=2026-09-01T00:00:00Z|" "$(grep -F '|status=duplicate-start|' "$_cgtc_roster" | tail -1)"

# ============================================================
section "CG-close T20d — a restarted id agrees between roster_open_names and live_ids_of_name (epic-23 wave-20 T20d, review R3-1)"
# ============================================================
#
# T20c proved the NAME reopens after a restart. R3-1 found the PER-ID reader —
# `live_ids_of_name`, the stop wall's ambiguity refusal and `adopt_write_row`'s same-name
# guard — never picked the new `restarted_at` field up, so the restarted id itself read
# discharged even while its name read open: the two halves of the one close predicate
# disagreed within the same commit that introduced the field. Same world as CG-close T20c: a
# real deliverable, launched, delivered, acked, then the SAME id restarts through the real
# recorder — and this time both readers are asked about the id, not only the name.
_cgtd_r=$(new_repo cgtd-restart)
_cgtd_name="cgtd-w"
_cgtd_id="acgtd-3b8f1e6a9c2d5074"
_cgtd_roster="$_cgtd_r/.bionic/tmp/roster-$SID_A.state"
_cgtd_ledger="$_cgtd_r/.bionic/tmp/sweeper-$SID_A.state"
_cgtd_del="$_cgtd_r/cgtd-report.md"
echo delivered > "$_cgtd_del"
touch -t 202609011200 "$_cgtd_del"
roster_header > "$_cgtd_roster"
roster_row_fixture status=confirmed session="$SID_A" name="$_cgtd_name" agent_id="$_cgtd_id" \
  launched_at=2026-09-01T00:00:00Z deliverable="$_cgtd_del" tool_use_id=toolu_01CGTD >> "$_cgtd_roster"
roster_row_fixture status=identified session="$SID_A" name="$_cgtd_name" agent_id="$_cgtd_id" \
  launched_at=2026-09-01T00:00:00Z deliverable="$_cgtd_del" tool_use_id=toolu_01CGTD >> "$_cgtd_roster"
cgc_ack "$_cgtd_ledger" 2026-09-02T00:00:00Z "$_cgtd_name"
jq -nc '{type:"user",isMeta:true,isSidechain:false,userType:"external",
         message:{role:"user",content:"carry on"}}' > "$_cgtd_r/cgc-transcript.jsonl"

# THE RESTART, through the real recorder — identical to CG-close T20c's own drive.
mk_start_payload "$SID_A" "$_cgtd_r/cgc-transcript.jsonl" "$_cgtd_r" general-purpose "$_cgtd_id" \
  | env CLAUDE_CODE_SESSION_ID="$SID_A" bash "$PARTY_ER" >/dev/null 2>&1

_cgtd_open=$( ( BIONIC_LIB_WANT=""; . "$CGC_LIBDIR/roster.sh" >/dev/null 2>&1
                roster_open_names "$_cgtd_roster" "$_cgtd_ledger" "$SID_A" ) 2>/dev/null )
_cgtd_live=$( ( BIONIC_LIB_WANT=""; ROSTER_FILE="$_cgtd_roster"
                . "$CGC_LIBDIR/roster.sh" >/dev/null 2>&1
                live_ids_of_name "$_cgtd_name" ) 2>/dev/null )
if grep -qxF -- "$_cgtd_name" <<< "$_cgtd_open"; then _cgtd_name_occ=open; else _cgtd_name_occ=closed; fi
if grep -qxF -- "$_cgtd_id" <<< "$_cgtd_live"; then _cgtd_id_occ=live; else _cgtd_id_occ=gone; fi
expect_eq "CG-close T20d: roster_open_names (the name) and live_ids_of_name (the id) agree on the SAME restart history" \
  "open live" "$_cgtd_name_occ $_cgtd_id_occ"

# ============================================================
section "CG-budget — ONE budget reader, four readers, one answer (epic-23 wave-20 T2, REQ-10 AC-10.2; D10)"
# ============================================================
#
# THE DEFECT (triage-D, driven 9 vs 3; research D3 §REQ-10). Four readers took `writers=` out
# of the plan's `parallel-budget:` line three ways. The governing-skill hook and the stop wall
# cut at the FIRST substring `writers=`, so `max_writers=9 writers=3` read 9; the stop wall
# also read the key leniently (`  parallel-budget:`, `parallel-budget :`) where every other
# reader read nothing; nobody read `writers=08` as the integer it is. D10: `plan_budget_line`
# and `budget_line_of` (strict `^parallel-budget:`) and `budget_field` (a whole field, a
# decimal integer) in payload/scripts/lib/run.sh, called by all four.
#
# A PERSON'S CAP, OR NONE (wave-28 T9; D15, REQ-2 AC-2.9/AC-2.10). The three width readers now
# read `budget_cap` (lib/run.sh): `writers=` only from a line whose `source=` is `user` or
# `override`. A probe's line and a line with no `source=` answer `-` in all three, and the
# governing-skill hook reads no line at all: no plan owes it, so every Write is admitted.
#
# THE ANSWER EACH READER GIVES is its writer count, `-` for none. With no cap the tick and the stop
# wall size the fill by the gate alone, which has room for all ten ready rows, so their answer for
# a `-` case is 10; preflight has no ceiling and answers `-`.
#   tick         how many of the ten ready rows its FILL names: the gate has room for all
#                ten, so the cap is the width (wave-28 T13: the rung line it used to read is gone)
#   preflight    the budget refusal's `writers: budget=<n>` (ten open rows, so any n refuses)
#   stop wall    the free slots its fill-ledger line records, over ten ready rows and an empty
#                roster (wave-36 T32: its refusal names every ready row while a slot is free,
#                so its width is read where it records it, never off the names)
#   gov hook     presence only (its one use is "does a writers= exist"): the Write is
#                refused on the budget arm iff it reads none
# and the governing-skill hook is driven over TEXT (the Write's content), the other three over
# a file — the one place the text-level reader exists for.

cgb_world() {  # <label> <budget line verbatim> -> repo path
  local r i ro
  r=$(new_repo "cgb-$1")
  ro="$r/.bionic/tmp/roster-$SID_A.state"
  cgc_plan "$r/.bionic/docs/plans/epic-99/cgb.plan.md" "$2" 10
  s4_bind "$r" "$SID_A" "$r/.bionic/docs/plans/epic-99/cgb.plan.md"
  s4_attest "$r" "$SID_A"
  jq -nc '{type:"user",isMeta:true,isSidechain:false,userType:"external",
           message:{role:"user",content:"carry on"}}' > "$r/cgc-transcript.jsonl"
  printf '%s' "$r"
}
cgb_open_rows() {  # <repo> — ten intended rows, none closed, for preflight's count
  local ro="$1/.bionic/tmp/roster-$SID_A.state" i
  [ -f "$ro" ] || roster_header > "$ro"
  for i in 1 2 3 4 5 6 7 8 9 10; do
    cgc_row "$ro" "cgb-w$i" 2026-09-01T00:00:00Z "toolu_01CGBW$i"
  done
}
cgb_tick() {  # <repo> -> writers
  local out
  cgc_ring
  out=$( ( cd "$1" && env CLAUDE_CODE_SESSION_ID="$SID_A" CLAUDE_CONFIG_DIR="$1/no-such-config" \
           "${CGC_ENV[@]}" bash "$PARTY_PK_S" tick 2>&1 ) )
  out=$(printf '%s\n' "$out" | sed -n 's/^poker: FILL //p' | head -1)
  [ -n "$out" ] || { printf '?'; return 0; }
  printf '%s' "$(printf '%s\n' $out | grep -c '^R[0-9]')"
}
# SETS GLOBALS, and is called bare — never inside `$( … )`, whose subshell would take the
# captured output with it (the first RED run died on exactly that, under `set -u`).
cgb_preflight() {  # <repo> -> sets CGB_PF_OUT (the wall's whole channel) and CGB_PF (writers)
  cgc_ring
  CGB_PF_OUT=$(mk_agent_payload "$SID_A" "$1" \
    | jq -c --arg t "$1/cgc-transcript.jsonl" '.tool_input.name = "cgb-new" | .transcript_path = $t' \
    | env CLAUDE_CODE_SESSION_ID="$SID_A" "${CGC_ENV[@]}" bash "$PARTY_DP" 2>&1)
  CGB_PF=$(printf '%s\n' "$CGB_PF_OUT" | sed -n 's/.*writers: budget=\([0-9]*\) .*/\1/p' | head -1)
  CGB_PF="${CGB_PF:--}"
}
cgb_stopwall() {  # <repo> -> writers
  local out ids
  cgc_ring
  out=$(s4_stop_payload "$1" "$SID_A" "$1/cgc-transcript.jsonl" \
    | env CLAUDE_CODE_SESSION_ID="$SID_A" "${CGC_ENV[@]}" bash "$CGC_STOP" 2>/dev/null)
  case "$out" in
    '') printf -- '-'; return 0 ;;
  esac
  case "$out" in *"ready with room:"*) ;; *) printf '?'; return 0 ;; esac
  cgb_wall_free "$1"
}
cgb_wall_free() {  # <repo> -> the free= of the stop wall's last fill-ledger line, or ?
  local free
  free=$(cat "$1"/.bionic/docs/record/*/fill-ledger.log 2>/dev/null | tail -1 | sed -n 's/.*|free=\([0-9]*\)|.*/\1/p')
  printf '%s' "${free:-?}"
}
cgb_govskill() {  # <budget line verbatim> -> present | absent (sets CGB_GS_OUT)
  local r plan content
  r=$(new_repo "cgb-gs-$RANDOM$RANDOM")
  plan="$r/.bionic/docs/plans/epic-99/cgb-gs.plan.md"
  mkdir -p "$(dirname "$plan")"
  content="---
governing-skill: superpowers:writing-plans
sdlc-step: 1
canonical_sdlc_version: 14
intent: build
rigor: double
scale: wave
cleanup_on_finish: true
use_worktree: false
surface_type: none
language: none
has_ui: false
multi_agent: false
deploy_target: none
model_plan: orchestrator=fable-5-high
${1}
---

## Goal

A fixture plan for the budget reader.
"
  CGB_GS_OUT=$(jq -n --arg p "$plan" --arg c "$content" --arg s "$SID_A" \
      '{session_id:$s, tool_name:"Write", tool_input:{file_path:$p, content:$c}}' \
    | env HOME="$r" CLAUDE_CODE_SESSION_ID="$SID_A" bash "$PARTY_SG_W" 2>&1)
  case "$CGB_GS_OUT" in
    *"parallel-budget"*) printf 'refused' ;;
    *) printf 'admitted' ;;
  esac
}

# <label>|<budget line, verbatim>|<the one answer>
CGB_CASES='max-writers|parallel-budget: max_writers=9 writers=3 suites=2 source=user|3
plain|parallel-budget: writers=3 suites=2 source=user|3
override|parallel-budget: writers=3 suites=2 source=override|3
probe|parallel-budget: writers=3 suites=2 source=probe|-
no-source|parallel-budget: writers=3 suites=2|-
leading-space|  parallel-budget: writers=3 suites=2 source=user|-
space-before-colon|parallel-budget : writers=3 suites=2 source=user|-
leading-zero|parallel-budget: writers=08 suites=2 source=user|8
empty-field|parallel-budget: writers= suites=2 source=user|-
no-writers|parallel-budget: suites=2 source=user|-'

# ROOM FOR ALL TEN (wave-33 T1; Δ10). The gate promises every writer one core, so the fixture's
# 8 cores at share 80 (6.4, a load of 1.0) hold five: the fill would be the gate's, and a cap of 8
# would read like no cap at all. This section's machine is 32 cores (25.6), so the fill is the
# cap's or the ten ready rows', as the readers' agreement needs; the fixture's 8 come back after.
CGB_CORES_SAVED="$BIONIC_PROBE_CORES"; export BIONIC_PROBE_CORES=32
while IFS='|' read -r _cgb_label _cgb_line _cgb_want; do
  [ -n "$_cgb_label" ] || continue
  _cgb_r=$(cgb_world "$_cgb_label" "$_cgb_line")
  _cgb_st=$(cgb_stopwall "$_cgb_r")
  # The tick reaches its report only with a roster carrying a row (§RG); one closed-by-ack
  # row is enough and holds no slot.
  cgc_row "$_cgb_r/.bionic/tmp/roster-$SID_A.state" cgb-tickrow 2026-09-01T00:00:00Z toolu_01CGBTICK
  cgc_ack "$_cgb_r/.bionic/tmp/sweeper-$SID_A.state" 2026-09-01T01:00:00Z cgb-tickrow
  _cgb_tk=$(cgb_tick "$_cgb_r")
  cgb_open_rows "$_cgb_r"
  cgb_preflight "$_cgb_r"; _cgb_pf="$CGB_PF"
  _cgb_gs=$(cgb_govskill "$_cgb_line")
  _cgb_w="$_cgb_want"; [ "$_cgb_want" = "-" ] && _cgb_w=10
  expect_eq "CG-budget ${_cgb_label}: the tick fills ${_cgb_w} (cap ${_cgb_want})" "$_cgb_w" "$_cgb_tk"
  expect_eq "CG-budget ${_cgb_label}: dispatch preflight reads writers=${_cgb_want}" "$_cgb_want" "$_cgb_pf"
  expect_eq "CG-budget ${_cgb_label}: the stop wall refuses with ${_cgb_w} free (cap ${_cgb_want})" "$_cgb_w" "$_cgb_st"
  expect_eq "CG-budget ${_cgb_label}: the governing-skill hook admits the Write (no plan owes the line)" \
    "admitted" "$_cgb_gs"
  if [ "$_cgb_want" = "-" ]; then
    # No cap is not a fault (D15): preflight passes with no ceiling and names no key. Until
    # wave-28 it named the missing key, citing ADR-035.
    expect_absent "CG-budget ${_cgb_label}: …and preflight names no budget line" \
      "parallel-budget" "$CGB_PF_OUT"
  fi
done <<< "$CGB_CASES"
export BIONIC_PROBE_CORES="$CGB_CORES_SAVED"

# ONE DEFINITION EACH, AND NO PRIVATE CUT SURVIVES.
for _cgb_fn in plan_budget_line budget_line_of budget_field; do
  expect_eq "CG-budget ${_cgb_fn} is defined exactly once, in run.sh" "run.sh" \
    "$( { grep -l "^${_cgb_fn}()" "$CGC_LIBDIR"/*.sh; grep -l "^[[:space:]]*${_cgb_fn}()" "$BIONIC_HOOKS_DIR"/*.sh; } 2>/dev/null | sed 's#.*/##' | sort -u | tr '\n' ' ' | sed 's/ $//')"
done
expect_eq "CG-budget no reader cuts writers= at its first substring any more" "0" \
  "$(cat "$PARTY_SG_W" "$CGC_LIBDIR/stop.sh" "$PARTY_DP" "$CGC_POKER" | grep -c '#\*writers=}' || true)"
expect_eq "CG-budget the stop wall no longer reads the budget through plan_frontmatter_get" "0" \
  "$(grep -c 'plan_frontmatter_get "$PLAN" parallel-budget' "$CGC_LIBDIR/stop.sh" || true)"


# ============================================================
section "§ROOM — the tick and the stop wall give one answer on width (wave-28 T13; REQ-2 AC-2.8, D14)"
# ============================================================
#
# THE ONE ANSWER. The tick offers a writer row for each `gate_room` that says yes and the stop
# wall owes the same rows, both through `fill_gate_width` (lib/fill.sh), so on one planted
# reading they name the same count. A gate store of this section's own, one run on record taking
# 1.0 core, ten ready rows and a person's cap of eight; the reading moves, the answer moves, and
# the two readers move together. The wall owes nothing when the gate gives no room — its HOLD —
# and that is the count 0, the tick's empty FILL.
# Each owed row is promised resources.sh's suite cost P (wave-38 T5; D21), lifted, never a literal:
# row k (from 0) is offered while load + k × P <= 6.4 cores. At P = 1.61:
#   quiet   a load of 1.0: 1.0 + k × 1.61 fits 6.4 cores for k = 0 … 3                -> 4
#   loaded  a load of 4.0 over both windows: 4.0 + k × 1.61 for k = 0 … 1              -> 2
#   5m      a quiet minute, a five-minute load of 7.0                                 -> 0
room_world() {  # <label> -> repo path, with ten ready rows under a cap of eight
  cgb_world "room-$1" 'parallel-budget: writers=8 suites=2 source=user'
}
room_stop() {  # <repo> -> the writer slots the stop wall finds free, 0 when it refuses nothing
  local out
  out=$(s4_stop_payload "$1" "$SID_A" "$1/cgc-transcript.jsonl" \
    | env CLAUDE_CODE_SESSION_ID="$SID_A" "${CGC_ENV[@]}" bash "$CGC_STOP" 2>/dev/null)
  # Its width is its ledger line's free= (wave-36 T32: the refusal names every ready row while a
  # slot is free, so the count of names is no longer the width).
  case "$out" in *"ready with room:"*) ;; *) printf '0'; return 0 ;; esac
  cgb_wall_free "$1"
}
room_tick() {  # <repo> — sets ROOM_TICK_OUT (the tick's channel) and ROOM_TK (rows its FILL names)
  local ids
  ROOM_TICK_OUT=$( ( cd "$1" && env CLAUDE_CODE_SESSION_ID="$SID_A" CLAUDE_CONFIG_DIR="$ROOM_CFG" \
           "${CGC_ENV[@]}" bash "$PARTY_PK_S" tick 2>&1 ) )
  ids=$(printf '%s\n' "$ROOM_TICK_OUT" | awk 'index($0, "poker: FILL ") == 1 && index($0, "poker: FILL —") != 1 { print substr($0, 13); exit }')
  ROOM_TK=$(printf '%s\n' $ids | grep -c '^R[0-9]')
}
# THE TICK'S OWN CONFIG DIR, with no transcript in it (it was `$1/no-such-config`, which the gate read as
# the default share, 92, while the stop wall read the suite's pin above: two readers, two shares). It holds
# the same share the suite's pin does, 80, and no `projects/`, so the tick still finds no panel to read.
ROOM_CFG="$SANDBOX/room-config"
mkdir -p "$ROOM_CFG/bionic"
printf '80\n' > "$ROOM_CFG/bionic/share"
ROOM_GATE="$SANDBOX/room-gate"
ROOM_GATE_SAVED="$BIONIC_GATE_DIR"
mkdir -p "$ROOM_GATE/requests" "$ROOM_GATE/cost"
printf '5:1.0:30:1000\n' > "$ROOM_GATE/cost/fixture.test.sh"
export BIONIC_GATE_DIR="$ROOM_GATE"
ROOM_P="$( . "$REPO_ROOT/payload/scripts/lib/resources.sh" 2>/dev/null; _res_suite_cores )"
room_want() {  # <load 1m> <load 5m> -> the rows offered: k from 0 while max(load) + k × P <= 6.4, under the cap of 8
  awk -v b1="$1" -v b5="$2" -v p="$ROOM_P" 'BEGIN { b = (b1 > b5 ? b1 : b5); k = 0
    while (k < 8 && b + k * p <= 80 * 8 / 100 + 1e-9) k++; print k }'
}
expect_true "ROOM precondition: the suite cost was lifted from resources.sh (${ROOM_P:-<empty>})" \
  test -n "$( printf '%s' "$ROOM_P" | grep -E '^[0-9]+(\.[0-9]+)?$' )"
expect_true "ROOM precondition: quiet offers more rows than loaded, and loaded more than none ($(room_want 1.0 1.0) > $(room_want 4.0 4.0) > 0)" \
  test "$(room_want 1.0 1.0)" -gt "$(room_want 4.0 4.0)" -a "$(room_want 4.0 4.0)" -gt 0
for _rm in quiet:1.0:1.0 loaded:4.0:4.0 5m:1.0:7.0; do
  IFS=: read -r _rm_case _rm_b1 _rm_b5 <<< "$_rm"
  _rm_want="$(room_want "$_rm_b1" "$_rm_b5")"
  _rm_r=$(room_world "$_rm_case")
  cgc_row "$_rm_r/.bionic/tmp/roster-$SID_A.state" room-tickrow 2026-09-01T00:00:00Z toolu_01ROOMTICK
  cgc_ack "$_rm_r/.bionic/tmp/sweeper-$SID_A.state" 2026-09-01T01:00:00Z room-tickrow
  export BIONIC_PROBE_BUSY_CORES="$_rm_b1" BIONIC_PROBE_BUSY_CORES_5M="$_rm_b5"
  room_tick "$_rm_r"; _rm_tk="$ROOM_TK"
  _rm_st=$(room_stop "$_rm_r")
  expect_eq "ROOM ${_rm_case}: the tick offers ${_rm_want} row(s)" "$_rm_want" "$_rm_tk"
  expect_eq "ROOM ${_rm_case}: the stop wall owes the same ${_rm_want}" "$_rm_want" "$_rm_st"
  expect_contains "ROOM ${_rm_case}: …and the tick printed its one gate line" "poker: gate share=80 used=30% load=${_rm_b1}/${_rm_b5} of 8 " "$ROOM_TICK_OUT"
done
export BIONIC_PROBE_BUSY_CORES=1.0 BIONIC_PROBE_BUSY_CORES_5M=1.0 BIONIC_GATE_DIR="$ROOM_GATE_SAVED"
# THE TWO READERS SIZE THEIR FILL BY THE ONE FUNCTION, and neither keeps a width of its own.
expect_true "ROOM the tick sizes its fill by fill_gate_width" grep -q 'fill_gate_width "' "$CGC_POKER"
expect_true "ROOM the stop wall sizes its fill by fill_gate_width" grep -q 'fill_gate_width "' "$CGC_LIBDIR/stop.sh"
expect_eq "ROOM neither reads a rung any more" "0" \
  "$(cat "$CGC_POKER" "$CGC_LIBDIR/stop.sh" | grep -c 'pressure_level\|resources_pressure' || true)"

# ============================================================
section "CG-standdown — the tick's printed stand-down set IS the stop wall's computed one (epic-23 wave-20 T19; REQ-5 AC-5.4's plants, on the stand-down)"
# ============================================================
#
# THE DEFECT (T11's carry-over 4). The stop wall's fourth duty read the stand-down SET off the
# tick's printed `poker: STANDDOWN <name>` lines in the transcript: the channel AC-5.4 closed
# for the FILL. It now computes the set from what the tick WROTE — this session's MET, unacked
# lineages carrying a `by=patrol` stop order stamped at or after this turn's tick stamp. Two
# readers, so one fixture: the REAL tick runs on a world with four rows,
#   sd-a, sd-b   MET, listed on a fresh panel     -> stood down (printed + ordered)
#   sd-gone      MET, absent from the panel        -> acked by the tick, never printed
#   sd-open      UNMET, listed                     -> left alone
# and then the REAL stop wall judges that tick's turn with the tick's STANDDOWN lines taken
# out of the transcript — so a wall that still read them would name nobody. The names each
# side gives must be the same set, and the precondition makes the set non-empty.
CGSD_POKER="$BIONIC_HOOKS_DIR/session-poker.sh"
CGSD_STOP="$BIONIC_HOOKS_DIR/stop.sh"
CGSD_R=$(new_repo cgsd)
CGSD_RO="$CGSD_R/.bionic/tmp/roster-$SID_A.state"
roster_header > "$CGSD_RO"
for _cgsd_n in sd-a sd-b sd-gone; do
  echo done > "$CGSD_R/landed-$_cgsd_n.md"; : > "$CGSD_R/$_cgsd_n.done"   # landed and said (T9, D3)
  roster_row_fixture status=intended session="$SID_A" name="$_cgsd_n" agent_id= \
    tool_use_id="toolu_01CGSD${_cgsd_n#sd-}" deliverable="$CGSD_R/landed-$_cgsd_n.md" \
    "done=$CGSD_R/$_cgsd_n.done" >> "$CGSD_RO"
done
roster_row_fixture status=intended session="$SID_A" name=sd-open agent_id= \
  tool_use_id=toolu_01CGSDOPEN deliverable="$CGSD_R/never-written.md" >> "$CGSD_RO"
# writers=1 and one ready row against three open rows: no fillable gap, so the stand-down is
# the only duty the wall can name.
cgc_plan "$CGSD_R/.bionic/docs/plans/epic-99/cgsd.plan.md" \
  'parallel-budget: writers=1 suites=4 worktrees=32 test_jobs=8 source=user' 1
s4_bind "$CGSD_R" "$SID_A" "$CGSD_R/.bionic/docs/plans/epic-99/cgsd.plan.md"
s4_attest "$CGSD_R" "$SID_A"
# THE TICK'S PANEL: a fresh ListAgents answer in this session's transcript, where the tick
# looks for it (CLAUDE_CONFIG_DIR/projects/<project>/<sid>.jsonl).
CGSD_CFG="$SANDBOX/cgsd-config"; mkdir -p "$CGSD_CFG/projects/-cgsd"
{
  jq -nc '{type:"user",timestamp:"2026-09-05T00:50:00.000Z",message:{role:"user",content:"go"}}'
  jq -nc '{type:"assistant",timestamp:"2026-09-05T00:51:00.000Z",message:{role:"assistant",content:[{type:"tool_use",id:"toolu_01CGSDLIST",name:"ListAgents",input:{}}]}}'
  jq -nc --arg b "$(live_answer_body "sd-a:idle" "sd-b:idle" "sd-open:running")" \
    '{type:"user",timestamp:"2026-09-05T00:52:23.349Z",message:{role:"user",content:[{type:"tool_result",tool_use_id:"toolu_01CGSDLIST",content:$b}]}}'
} > "$CGSD_CFG/projects/-cgsd/$SID_A.jsonl"
cgc_ring
CGSD_TICK=$( cd "$CGSD_R" && env CLAUDE_CODE_SESSION_ID="$SID_A" CLAUDE_CONFIG_DIR="$CGSD_CFG" \
  BIONIC_PRESSURE_RING="$CGC_RING" BIONIC_PROBE_FREE_PCT=80 BIONIC_PROBE_SWAP_PCT=0 \
  BIONIC_PROBE_LOAD_1M=0.1 BIONIC_PROBE_FREE_MB=8192 bash "$CGSD_POKER" tick 2>&1 )
CGSD_PRINTED=$(printf '%s\n' "$CGSD_TICK" | sed -n 's/^poker: STANDDOWN \([A-Za-z0-9_.-]*\) .*/\1/p' | LC_ALL=C sort -u | tr '\n' ' ')
expect_eq "CG-standdown precondition: the real tick stood down exactly the two listed MET rows" \
  "sd-a sd-b " "$CGSD_PRINTED"
# THE TICK'S TURN, as the wall reads it: the marker, the tick's Bash call, its output with every
# STANDDOWN line removed, and the task-list refresh — nothing else owed but the stand-down.
CGSD_TR="$CGSD_R/cgsd-transcript.jsonl"
{
  jq -nc --arg t "bionic-patrol session=${SID_A:0:8} — Patrol tick. Run: bash $CGSD_POKER tick" \
    '{type:"user",isMeta:true,isSidechain:false,userType:"external",message:{role:"user",content:$t}}'
  jq -nc --arg c "bash $CGSD_POKER tick" \
    '{type:"assistant",isSidechain:false,message:{role:"assistant",content:[{type:"tool_use",id:"toolu_01CGSDTICK",name:"Bash",input:{command:$c}}]}}'
  jq -nc --arg o "$(printf '%s\n' "$CGSD_TICK" | grep -v 'STANDDOWN')" \
    '{type:"user",isSidechain:false,message:{role:"user",content:[{type:"tool_result",tool_use_id:"toolu_01CGSDTICK",content:$o}]}}'
  jq -nc '{type:"assistant",isSidechain:false,message:{role:"assistant",content:[{type:"tool_use",id:"toolu_01CGSDTL",name:"TaskList",input:{}}]}}'
} > "$CGSD_TR"
cgc_ring
CGSD_OUT=$(s4_stop_payload "$CGSD_R" "$SID_A" "$CGSD_TR" \
  | env CLAUDE_CODE_SESSION_ID="$SID_A" BIONIC_PRESSURE_RING="$CGC_RING" BIONIC_PROBE_FREE_PCT=80 \
      BIONIC_PROBE_SWAP_PCT=0 BIONIC_PROBE_LOAD_1M=0.1 BIONIC_PROBE_FREE_MB=8192 bash "$CGSD_STOP" 2>/dev/null)
CGSD_REASON=$(printf '%s' "$CGSD_OUT" | jq -r '.reason // ""' 2>/dev/null)
CGSD_WALL=""
for _cgsd_n in sd-a sd-b sd-gone sd-open; do
  case " $(printf '%s' "$CGSD_REASON" | tr -c 'A-Za-z0-9_.-' ' ') " in
    *" $_cgsd_n "*) CGSD_WALL="${CGSD_WALL}${_cgsd_n} " ;;
  esac
done
expect_contains "CG-standdown the wall refuses the tick's turn for the stand-down" \
  "stand-down unanswered" "$CGSD_REASON"
expect_eq "CG-standdown the wall's computed set is the tick's printed set, with no line to read" \
  "$CGSD_PRINTED" "$CGSD_WALL"


# ============================================================
section "HD — a HELD row: the tick and the stop wall agree it owes nothing (wave-24 T7; REQ-4 AC-4.3; D1, ADR-041 d1/d3)"
# ============================================================
#
# The hold lives on the roster, the tick reads it and writes no order, and the stop wall computes
# its stand-down set from orders alone — so the wall needs no reading of the hold to agree. One
# fixture, both readers: CG-standdown's world with sd-a held through the REAL verb. The tick must
# print `held sd-a` and stand down sd-b alone, and the wall's computed set must be {sd-b}.
HD_R=$(new_repo hd)
HD_RO="$HD_R/.bionic/tmp/roster-$SID_A.state"
roster_header > "$HD_RO"
for _hd_n in sd-a sd-b; do
  echo done > "$HD_R/landed-$_hd_n.md"; : > "$HD_R/$_hd_n.done"   # landed and said (T9, D3)
  roster_row_fixture status=intended session="$SID_A" name="$_hd_n" agent_id= \
    tool_use_id="toolu_01HD${_hd_n#sd-}" deliverable="$HD_R/landed-$_hd_n.md" \
    "done=$HD_R/$_hd_n.done" >> "$HD_RO"
done
roster_row_fixture status=intended session="$SID_A" name=sd-open agent_id= \
  tool_use_id=toolu_01HDOPEN deliverable="$HD_R/never-written.md" >> "$HD_RO"
cgc_plan "$HD_R/.bionic/docs/plans/epic-99/hd.plan.md" \
  'parallel-budget: writers=1 suites=4 worktrees=32 test_jobs=8 source=user' 1
s4_bind "$HD_R" "$SID_A" "$HD_R/.bionic/docs/plans/epic-99/hd.plan.md"
s4_attest "$HD_R" "$SID_A"
HD_CFG="$SANDBOX/hd-config"; mkdir -p "$HD_CFG/projects/-hd"
{
  jq -nc '{type:"user",timestamp:"2026-09-05T00:50:00.000Z",message:{role:"user",content:"go"}}'
  jq -nc '{type:"assistant",timestamp:"2026-09-05T00:51:00.000Z",message:{role:"assistant",content:[{type:"tool_use",id:"toolu_01HDLIST",name:"ListAgents",input:{}}]}}'
  jq -nc --arg b "$(live_answer_body "sd-a:idle" "sd-b:idle" "sd-open:running")" \
    '{type:"user",timestamp:"2026-09-05T00:52:23.349Z",message:{role:"user",content:[{type:"tool_result",tool_use_id:"toolu_01HDLIST",content:$b}]}}'
} > "$HD_CFG/projects/-hd/$SID_A.jsonl"
hd_env() { env CLAUDE_CODE_SESSION_ID="$SID_A" CLAUDE_CONFIG_DIR="$HD_CFG" \
  BIONIC_PRESSURE_RING="$CGC_RING" BIONIC_PROBE_FREE_PCT=80 BIONIC_PROBE_SWAP_PCT=0 \
  BIONIC_PROBE_LOAD_1M=0.1 BIONIC_PROBE_FREE_MB=8192 "$@"; }
HD_HOLD=$( cd "$HD_R" && hd_env bash "$CGSD_POKER" hold sd-a "kept for a second pass" 2>&1 ); HD_HOLD_RC=$?
expect_eq "HD precondition: the hold verb took sd-a (rc 0)" "0" "$HD_HOLD_RC"
cgc_ring
HD_TICK=$( cd "$HD_R" && hd_env bash "$CGSD_POKER" tick 2>&1 )
HD_PRINTED=$(printf '%s\n' "$HD_TICK" | sed -n 's/^poker: STANDDOWN \([A-Za-z0-9_.-]*\) .*/\1/p' | LC_ALL=C sort -u | tr '\n' ' ')
expect_eq "HD the tick stands down the unheld MET row alone" "sd-b " "$HD_PRINTED"
expect_contains "HD2 …and prints the held one as held" "poker: held sd-a since " "$HD_TICK"
HD_TR="$HD_R/hd-transcript.jsonl"
{
  jq -nc --arg t "bionic-patrol session=${SID_A:0:8} — Patrol tick. Run: bash $CGSD_POKER tick" \
    '{type:"user",isMeta:true,isSidechain:false,userType:"external",message:{role:"user",content:$t}}'
  jq -nc --arg c "bash $CGSD_POKER tick" \
    '{type:"assistant",isSidechain:false,message:{role:"assistant",content:[{type:"tool_use",id:"toolu_01HDTICK",name:"Bash",input:{command:$c}}]}}'
  jq -nc --arg o "$HD_TICK" \
    '{type:"user",isSidechain:false,message:{role:"user",content:[{type:"tool_result",tool_use_id:"toolu_01HDTICK",content:$o}]}}'
  jq -nc '{type:"assistant",isSidechain:false,message:{role:"assistant",content:[{type:"tool_use",id:"toolu_01HDTL",name:"TaskList",input:{}}]}}'
} > "$HD_TR"
cgc_ring
HD_OUT=$(s4_stop_payload "$HD_R" "$SID_A" "$HD_TR" | hd_env bash "$CGSD_STOP" 2>/dev/null)
HD_REASON=$(printf '%s' "$HD_OUT" | jq -r '.reason // ""' 2>/dev/null)
HD_WALL=""
for _hd_n in sd-a sd-b sd-open; do
  case " $(printf '%s' "$HD_REASON" | tr -c 'A-Za-z0-9_.-' ' ') " in
    *" $_hd_n "*) HD_WALL="${HD_WALL}${_hd_n} " ;;
  esac
done
expect_contains "HD3 the wall refuses the turn for the one row the tick stood down" \
  "stand-down unanswered" "$HD_REASON"
expect_eq "HD4 the wall's computed set is the tick's: the held row is in neither" "$HD_PRINTED" "$HD_WALL"

# ============================================================
section "OCC — preflight's open count and the tick's occupancy agree on a mixed roster (wave-24 T10; REQ-7 AC-7.1; D11)"
# ============================================================
#
# One roster: a writer, two researchers and a test-runner, all unacked. A read-only role holds no
# WRITER slot, so the one writer is the whole occupancy at both readers. Preflight reads it as the
# `open=` of its writer refusal, the tick as the occupancy of its fill line, and the two numbers
# are asserted EQUAL and asserted ONE: equal alone is also what the unfixed code gives (it counts
# four at both), so the absolute figure is what makes this test fail on that code.
OCC_R=$(new_repo occ)
OCC_RO="$OCC_R/.bionic/tmp/roster-$SID_A.state"
roster_header > "$OCC_RO"
roster_row_fixture status=intended session="$SID_A" name=oc-w agent_id= \
  tool_use_id=toolu_01OCW deliverable="$OCC_R/never-oc-w.md" >> "$OCC_RO"
for _oc in oc-r1:bionic:researcher oc-r2:bionic:researcher oc-t:bionic:test-runner; do
  roster_row_fixture status=intended session="$SID_A" name="${_oc%%:*}" agent_id= \
    subagent_type="${_oc#*:}" tool_use_id="toolu_01OC${_oc%%:*}" \
    deliverable="$OCC_R/never-${_oc%%:*}.md" >> "$OCC_RO"
done
expect_eq "OCC precondition: the fixture roster holds four rows, three of them read-only" "4/3" \
  "$(grep -c '^roster-state/' "$OCC_RO")/$(grep -c 'subagent_type=bionic:' "$OCC_RO")"
cgc_plan "$OCC_R/.bionic/docs/plans/epic-99/occ.plan.md" \
  'parallel-budget: writers=1 suites=9 worktrees=32 test_jobs=8 source=user' 1
s4_bind "$OCC_R" "$SID_A" "$OCC_R/.bionic/docs/plans/epic-99/occ.plan.md"
s4_attest "$OCC_R" "$SID_A"
occ_env() { env CLAUDE_CODE_SESSION_ID="$SID_A" CLAUDE_CONFIG_DIR="$CLAUDE_CONFIG_DIR" \
  BIONIC_PRESSURE_RING="$CGC_RING" BIONIC_PROBE_FREE_PCT=80 BIONIC_PROBE_SWAP_PCT=0 \
  BIONIC_PROBE_LOAD_1M=0.1 BIONIC_PROBE_FREE_MB=8192 "$@"; }
OCC_PF=$( cd "$OCC_R" && mk_agent_payload "$SID_A" "$OCC_R" | occ_env bash "$PARTY_DP" 2>&1 )
OCC_PF_N=$(printf '%s\n' "$OCC_PF" | sed -n 's/.*writers: budget=1 open=\([0-9][0-9]*\) with-this-dispatch=.*/\1/p' | head -1)
cgc_ring
OCC_TICK=$( cd "$OCC_R" && occ_env bash "$CGSD_POKER" tick 2>&1 )
OCC_TICK_N=$(printf '%s\n' "$OCC_TICK" | sed -n -e 's/.* occupied=\([0-9][0-9]*\) gap=.*/\1/p' \
  -e 's/.* and \([0-9][0-9]*\) unacked roster row(s).*/\1/p' \
  -e 's/.* reached by \([0-9][0-9]*\) unacked roster row(s).*/\1/p' | head -1)
expect_eq "OCC1 preflight refuses a writer, counting ONE open writer" "1" "$OCC_PF_N"
expect_eq "OCC2 the tick's occupancy is ONE" "1" "$OCC_TICK_N"
expect_eq "OCC3 …and the two readers' numbers are equal" "$OCC_PF_N" "$OCC_TICK_N"
OCC_PF_RO=$( cd "$OCC_R" && mk_agent_payload "$SID_A" "$OCC_R" \
  | jq -c '.tool_input.subagent_type="bionic:researcher" | .tool_input.name="oc-r3"' \
  | occ_env bash "$PARTY_DP" 2>&1 ); OCC_PF_RO_RC=$?
expect_eq "OCC4 a read-only dispatch against the same full roster is admitted (rc 0)" "0" "$OCC_PF_RO_RC"
expect_absent "OCC4b …with no writer-budget refusal" "writers: budget=" "$OCC_PF_RO"

# THE THIRD READER, THE STOP WALL (wave-24 T27; Step-6 review U4). `stop.sh`'s fill collector
# counts the same open set through the same `budget_open_writers`, and records the count as the
# fill ledger's `open=`. Asked over the same roster and plan, its number must be the other two's.
# The mutation arm drives a planted tree whose collector counts every open row, the shape a
# caller that skipped the writer filter would take, and the pin must move.
occ_stop() {  # <stop hook> -> the `open=` of the ledger line that Stop wrote
  local tr="$OCC_R/occ-turn.jsonl"
  jq -nc '{type:"user",uuid:"u-occ",isSidechain:false,timestamp:"2026-10-03T00:00:00Z",message:{role:"user",content:"carry on"}}' > "$tr"
  cgc_ring
  s4_stop_payload "$OCC_R" "$SID_A" "$tr" | occ_env BIONIC_NOW_EPOCH=1700000000 bash "$1" >/dev/null 2>&1
  tail -1 "$OCC_R/.bionic/docs/record/occ/fill-ledger.log" 2>/dev/null | sed -n 's/.*|open=\([0-9]*\)|.*/\1/p'
}
OCC_STOP_N="$(occ_stop "$CGSD_STOP")"
expect_eq "OCC5 the stop wall's open count is ONE" "1" "$OCC_STOP_N"
expect_eq "OCC6 …and equal to preflight's and the tick's" "$OCC_PF_N/$OCC_TICK_N" "$OCC_STOP_N/$OCC_STOP_N"
OCC_MUT_HOOK="$(plant_lg_tree "$SANDBOX/fx/occ-mut")"
cp "$SWEEPER" "$(dirname "$OCC_MUT_HOOK")/session-sweeper.sh"
anchor file payload/scripts/lib/stop.sh \
  'FILL_OPEN="$(roster_open_names "$FILL_ROSTER" "$FILL_ACKS" "$BIONIC_SID" | budget_open_writers "$FILL_ROSTER")"'
sed 's/^\(  FILL_OPEN="\$(roster_open_names "\$FILL_ROSTER" "\$FILL_ACKS" "\$BIONIC_SID"\) | budget_open_writers "\$FILL_ROSTER")"$/\1 | grep -c .)"/' \
  "$(dirname "$OCC_MUT_HOOK")/../scripts/lib/stop.sh" > "$SANDBOX/fx/occ-mut/stop.sh.mut"
cp "$SANDBOX/fx/occ-mut/stop.sh.mut" "$(dirname "$OCC_MUT_HOOK")/../scripts/lib/stop.sh"
OCC_MUT_N="$(occ_stop "$OCC_MUT_HOOK")"
# FIVE: the fixture's four rows, and the researcher OCC4's admitted dispatch rostered.
expect_eq "OCC7 mutation: a stop wall that counts every open row reads five (the mutant ran)" "5" "$OCC_MUT_N"
expect_ne "OCC7b …and the agreement pin goes red on it" "$OCC_PF_N" "$OCC_MUT_N"

# ============================================================
section "CG-turn — the ledger writer and fill-report agree on what a turn is (epic-23 wave-20 T11b; Step-6 review R3, critic C1)"
# ============================================================
#
# TWO READERS OF ONE WORD. The stop hook's recorder keys each ledger line by the turn's prompt
# (`stop_turn_facts`), and `fill-report` counts turns by folding those keys. The CLI writes two
# user records that are not prompts: the Stop hook's refusal fed back ("Stop hook feedback:",
# isMeta) and a skill's body after a Skill call (turnCompanion, sourceToolUseID). If the writer
# opens a turn on either, the report counts turns nobody prompted. One transcript, two prompts:
#   turn A  launch W-R1, refused (R2 left out), feedback record, launch W-R2, re-entry Stop
#   turn B  a Skill call and its body, both rows now active, a clean Stop
# The writer's distinct keys, the report's turns= and the prompts in the transcript must all be 2.
CGT_STOP="$BIONIC_HOOKS_DIR/stop.sh"
CGT_POKER="$BIONIC_HOOKS_DIR/session-poker.sh"
CGT_R=$(new_repo cgturn)
CGT_PLAN="$CGT_R/.bionic/docs/plans/epic-99/cgturn.plan.md"
cgc_plan "$CGT_PLAN" 'parallel-budget: writers=8 suites=4 worktrees=32 test_jobs=8 source=user' 2
s4_bind "$CGT_R" "$SID_A" "$CGT_PLAN"
CGT_RO="$CGT_R/.bionic/tmp/roster-$SID_A.state"
roster_header > "$CGT_RO"
CGT_TR="$CGT_R/cgturn-transcript.jsonl"
cgt_agent() {  # <tool_use id> <name>
  jq -nc --arg i "$1" --arg n "$2" '{type:"assistant",isSidechain:false,message:{role:"assistant",content:[{type:"tool_use",id:$i,name:"Agent",input:{name:$n,description:"task",subagent_type:"bionic:implementor",prompt:"x"}}]}}' >> "$CGT_TR"
  jq -nc --arg i "$1" '{type:"user",isSidechain:false,message:{role:"user",content:[{type:"tool_result",tool_use_id:$i,is_error:false,content:"Spawned"}]}}' >> "$CGT_TR"
  cgc_row "$CGT_RO" "$2" 2026-09-23T10:00:00Z "$1"
}
cgt_stop() {  # <stop_hook_active true|false>
  cgc_ring
  jq -nc --arg c "$CGT_R" --arg s "$SID_A" --arg t "$CGT_TR" --argjson a "$1" \
    '{session_id:$s,transcript_path:$t,cwd:$c,hook_event_name:"Stop",stop_hook_active:$a}' \
    | env CLAUDE_CODE_SESSION_ID="$SID_A" BIONIC_PRESSURE_RING="$CGC_RING" BIONIC_PROBE_FREE_PCT=80 \
        BIONIC_PROBE_SWAP_PCT=0 BIONIC_PROBE_LOAD_1M=0.1 BIONIC_PROBE_FREE_MB=8192 bash "$CGT_STOP" 2>/dev/null
}
jq -nc '{type:"user",uuid:"u-cgt-A",timestamp:"2026-09-23T10:00:00.000Z",isSidechain:false,message:{role:"user",content:"dispatch the batch"}}' > "$CGT_TR"
cgt_agent toolu_01CGTA1 W-R1
CGT_OUT="$(cgt_stop false)"
expect_contains "CG-turn precondition: turn A's first Stop is refused, so the CLI feeds it back" "ready with room:" "$CGT_OUT"
# THE LAUNCHED SET IS THE RECORDER'S (wave-28 T38; REQ-13, D30). The task-entry duty that also read it
# went at wave-31 T32 (D6, AC-6.5): the Stop the recorder's line names is refused for the fill alone.
expect_contains "CG-entry the recorder's line for turn A's first Stop records the launch W-R1" "|launched=W-R1|" \
  "$(head -n 1 "$CGT_R/.bionic/docs/record/cgturn/fill-ledger.log" 2>/dev/null)"
expect_absent "CG-entry …and the same Stop owes no task entry for it (the refusal above is the fill's)" \
  "task entries set in progress" "$CGT_OUT"
jq -nc '{type:"user",isMeta:true,uuid:"u-cgt-fb",timestamp:"2026-09-23T10:00:30.000Z",isSidechain:false,userType:"external",message:{role:"user",content:"Stop hook feedback:\nbionic: stop refused — rows are ready"}}' >> "$CGT_TR"
cgt_agent toolu_01CGTA2 W-R2
cgt_stop true >/dev/null
sed -i.bak 's/| pending | — |$/| active | — |/' "$CGT_PLAN"
{
  jq -nc '{type:"user",uuid:"u-cgt-B",timestamp:"2026-09-23T10:10:00.000Z",isSidechain:false,message:{role:"user",content:"load the skill and carry on"}}'
  jq -nc '{type:"assistant",isSidechain:false,message:{role:"assistant",content:[{type:"tool_use",id:"toolu_01CGTSK",name:"Skill",input:{skill:"bionic:canonical-sdlc"}}]}}'
  jq -nc '{type:"user",isSidechain:false,message:{role:"user",content:[{type:"tool_result",tool_use_id:"toolu_01CGTSK",content:"Launching skill: bionic:canonical-sdlc"}]}}'
  jq -nc '{type:"user",isMeta:true,turnCompanion:true,sourceToolUseID:"toolu_01CGTSK",uuid:"u-cgt-skill",timestamp:"2026-09-23T10:10:02.000Z",isSidechain:false,message:{role:"user",content:[{type:"text",text:"Base directory for this skill: /abs/skills/canonical-sdlc"}]}}'
} >> "$CGT_TR"
cgt_stop false >/dev/null
CGT_LED="$CGT_R/.bionic/docs/record/cgturn/fill-ledger.log"
CGT_PROMPTS="$(jq -r 'select(.type=="user" and (.message.content|type)=="string" and ((.isMeta // false) | not)) | .uuid' "$CGT_TR" | wc -l | tr -d ' ')"
CGT_KEYS="$(sed -n 's/.*|turn=\([^|]*\)|.*/\1/p' "$CGT_LED" 2>/dev/null | LC_ALL=C sort -u | wc -l | tr -d ' ')"
CGT_REPORT="$( cd "$CGT_R" && CLAUDE_CODE_SESSION_ID="$SID_A" bash "$CGT_POKER" fill-report "$CGT_PLAN" 2>&1 )"
CGT_TURNS="$(printf '%s\n' "$CGT_REPORT" | sed -n 's/.*|turns=\([0-9]*\)|.*/\1/p' | head -1)"
expect_eq "CG-turn precondition: the fixture carries two prompts" "2" "$CGT_PROMPTS"
expect_eq "CG-turn precondition: three Stops, three ledger lines" "3" "$(grep -c '^fill-ledger/v1|' "$CGT_LED" 2>/dev/null)"
expect_eq "CG-turn the writer keys the three lines by the two prompts" "$CGT_PROMPTS" "$CGT_KEYS"
expect_eq "CG-turn fill-report counts the writer's turns, and they are the prompts" "$CGT_PROMPTS" "$CGT_TURNS"

# ============================================================
section "PIN-REL — a pin on the shipped tree is a relation, not a count: planted additions stay green, an emptied set is red (wave-26 T21, AC-8.1)"
#
# The two pins this section covers (the chips in hook-chain.svg, the role files under agents/)
# are exercised on COPIES under $SANDBOX; the shipped tree is never touched. Each pair of arms
# is the same row against two copies of one subject: one with an item PLANTED (a fourth chip, a
# seventh role file) and one with every item of the kind REMOVED.
PR_DIR="$SANDBOX/pin-rel"; rm -rf "$PR_DIR"; mkdir -p "$PR_DIR/agents-plus" "$PR_DIR/agents-none"
# the extractor reads real chips on the shipped file, or every arm below proves nothing
expect_eq "PIN-REL the chip extractor finds chips in the shipped hook-chain.svg (not vacuous)" "yes" \
  "$([ -n "$(v_hookchain_vals "$V_HOOKCHAIN")" ] && echo yes || echo no)"
PR_CHIPS_REAL="$(v_hookchain_vals "$V_HOOKCHAIN" | grep -c '[0-9]')"
# a fourth chip: the first chip line, repeated once
{ cat "$V_HOOKCHAIN"; grep -m1 '<text class="version-pin"' "$V_HOOKCHAIN"; } > "$PR_DIR/chips-plus.svg"
grep -v 'class="version-pin"' "$V_HOOKCHAIN" > "$PR_DIR/chips-none.svg"
expect_eq "PIN-REL the planted copy really carries one more chip than the shipped file" "$((PR_CHIPS_REAL + 1))" \
  "$(v_hookchain_vals "$PR_DIR/chips-plus.svg" | grep -c '[0-9]')"
expect_eq "PIN-REL the emptied copy still parses and carries no chip" "0 yes" \
  "$(v_hookchain_vals "$PR_DIR/chips-none.svg" | grep -c '[0-9]') $([ -s "$PR_DIR/chips-none.svg" ] && echo yes || echo no)"
expect_eq "PIN-REL a fourth chip: the non-empty row stays green" "yes" "$(v_hc_chips_ok "$PR_DIR/chips-plus.svg")"
expect_eq "PIN-REL …and the agreement relation stays green" "yes" "$(v_hc_agree "$PR_DIR/chips-plus.svg" "$V_ORIGIN_VAL")"
expect_eq "PIN-REL no chip at all: the non-empty row is red" "no" "$(v_hc_chips_ok "$PR_DIR/chips-none.svg")"

# one chip moved to the next version: the relation the live row asks must answer no (review 9 F2)
PR_CHIPS_MUT="$PR_DIR/chips-moved.svg"
anchor file skills/canonical-sdlc/diagrams/hook-chain.svg 'is the only value either hook accepts.'
anchor "$V_HOOKCHAIN" "canonical_sdlc_version: ${V_ORIGIN_VAL} is" 1
sed "s/canonical_sdlc_version: ${V_ORIGIN_VAL} is/canonical_sdlc_version: $((V_ORIGIN_VAL + 1)) is/" \
  "$V_HOOKCHAIN" > "$PR_CHIPS_MUT"
expect_eq "PIN-REL the moved copy keeps every chip and reads the next version on exactly one" \
  "$PR_CHIPS_REAL 1" \
  "$(v_hookchain_vals "$PR_CHIPS_MUT" | grep -c '[0-9]') $(v_hookchain_vals "$PR_CHIPS_MUT" | grep -c -x "$((V_ORIGIN_VAL + 1))")"
expect_eq "PIN-REL one chip on the next version: the agreement relation is red" "no" \
  "$(v_hc_agree "$PR_CHIPS_MUT" "$V_ORIGIN_VAL")"
# a seventh role file: a copy of a writer role under another name (no entry owed in the set)
cp "$BIONIC_SCRIPTS_DIR"/agents/*.md "$PR_DIR/agents-plus/"
cp "$BIONIC_SCRIPTS_DIR/agents/implementor.md" "$PR_DIR/agents-plus/seventh.md"
expect_eq "PIN-REL the planted copy really carries one more role file than the shipped tree" \
  "$(ls "$BIONIC_SCRIPTS_DIR"/agents/*.md | wc -l | tr -d ' ') plus1" \
  "$(($(ls "$PR_DIR"/agents-plus/*.md | wc -l) - 1)) plus1"
expect_eq "PIN-REL a seventh role file: the non-empty row stays green" "yes" "$(rc_roles_ok "$PR_DIR/agents-plus")"
expect_eq "PIN-REL …and the read-only set relation stays green" "$(rc_sorted "$RC_WANT")" \
  "$( rc_scan "$PR_DIR/agents-plus"; rc_sorted "$RC_WANT" )"
expect_eq "PIN-REL no role file at all: the non-empty row is red" "no" "$(rc_roles_ok "$PR_DIR/agents-none")"

section "RC-nest — ARM C and the delegation arm read ONE role and ONE agent context off the same nested payload (wave-20 T7b; review R15, critic C4)"
# ============================================================
#
# TWO READERS OF "WHO IS CALLING". The dispatch wall's delegation arm decides which types a
# subagent may launch (`role_is_readonly` of the launched type) and what an agent context is
# (`is_agent_context`); the verb wall's ARM C decides which callers may not commit. Δ12's
# promise is their composition: a type the delegation arm admits as read-only must be one ARM C
# holds read-only when that delegate — unrostered by AC-9.2 — runs git with its own payload.
# R15 found the composition open: ARM C read no role off an unrostered payload. C4 found the
# context split: an `agent_type`-only payload (a `claude --agent` main session) was a subagent
# to the dispatch wall and the orchestrator to ARM C.
#
# BOTH HOOKS ARE DRIVEN, never their functions: the dispatch wall on a nested Agent payload of
# the live shape (T12: `agent_id` plus the caller's `agent_type`), the verb wall on that
# delegate's own Bash payload (its `agent_id`, no roster row, its own `agent_type`). Each
# observable is the arm's own phrase, so the other arms the two hooks pool are not read.
RCN_R=$(s4_world "rc-nest")
s4_bind "$RCN_R" "$SID_A" "$RCN_R/.bionic/docs/plans/epic-99/run-b.md"
printf '# bionic session roster — fixture\n' > "$RCN_R/.bionic/tmp/roster-$SID_A.state"
RCN_ID="a8b824d95c81dd996"
# rcn_ctx <agent_id> <agent_type> — the caller half of a payload; an empty argument omits the key
rcn_ctx() { jq -c --arg a "$1" --arg t "$2" '. + (if $a == "" then {} else {agent_id:$a} end)
                                               + (if $t == "" then {} else {agent_type:$t} end)'; }
rcn_dp_admits() {  # <launched type> <caller agent_id> <caller agent_type> -> yes when the delegation arm is silent
  local out
  out=$(jq -nc --arg s "$SID_A" --arg c "$RCN_R" --arg t "$RCN_R/s4-transcript.jsonl" --arg y "$1" \
    '{session_id:$s, transcript_path:$t, cwd:$c, hook_event_name:"PreToolUse", tool_name:"Agent",
      tool_input:{description:"a nested dispatch", subagent_type:$y, name:"rcn-helper",
                  prompt:"Expected artifact: .bionic/docs/record/rcn.md\nExpected duration: ~10 minutes.\nProgress artifact: .bionic/tmp/rcn.progress, cadence ~5m\nSuites: tests/widget.test.sh"},
      tool_use_id:"toolu_RCNEST"}' | rcn_ctx "$2" "$3" \
    | env CLAUDE_CODE_SESSION_ID="$SID_A" bash "$PARTY_DP" 2>&1)
  case "$out" in *"a subagent may launch only read-only roles"*) echo no ;; *) echo yes ;; esac
}
rcn_eg_refuses() {  # <agent_id> <agent_type> -> yes when ARM C refuses that caller's `git commit`
  local out
  out=$(mk_bash_payload "$SID_A" "$RCN_R/s4-transcript.jsonl" "$RCN_R" "git commit -m x" | rcn_ctx "$1" "$2" \
    | env CLAUDE_CODE_SESSION_ID="$SID_A" bash "$PARTY_EG" 2>&1)
  case "$out" in *"a read-only role never commits"*) echo yes ;; *) echo no ;; esac
}

# ---- the role: the types the delegation arm lets a subagent launch = the types ARM C stops ----
# One type per line, read line by line, so no IFS a earlier section left behind can fuse them.
RCN_DP=""; RCN_EG=""; RCN_N=0
while IFS= read -r _rcn_t; do
  [ -n "$_rcn_t" ] || continue
  RCN_N=$((RCN_N + 1))
  [ "$(rcn_dp_admits "$_rcn_t" "$RCN_ID" general-purpose)" = yes ] && RCN_DP="${RCN_DP}${_rcn_t};"
  [ "$(rcn_eg_refuses "$RCN_ID" "$_rcn_t")" = yes ] && RCN_EG="${RCN_EG}${_rcn_t};"
done <<'RCNTYPES'
bionic:researcher
bionic:test-runner
bionic:auditor
bionic:critic
Explore
Plan
general-purpose
fork
claude
bionic:implementor
bionic:senior-implementor
acme:test-runner
researcher
RCNTYPES
expect_eq "RC-nest thirteen types driven through both hooks" "13" "$RCN_N"
expect_eq "RC-nest the delegation arm admits exactly the six read-only types from a subagent (non-vacuity)" \
  "bionic:researcher;bionic:test-runner;bionic:auditor;bionic:critic;Explore;Plan;" "$RCN_DP"
expect_eq "RC-nest ARM C refuses an unrostered delegate's commit for exactly the types the delegation arm admitted" \
  "$RCN_DP" "$RCN_EG"

# ---- the context: which payload shapes each hook reads as a subagent ----
# id+type is the nested delegate; type-only is a `claude --agent` main session; none is the
# plain main session. Each hook's reading is observed through its own refusal: the dispatch
# wall refusing a writer launch, ARM C refusing a bionic:test-runner-typed commit.
RCN_CTX_DP=""; RCN_CTX_EG=""
for _rcn_shape in id+type type-only none; do
  case "$_rcn_shape" in
    id+type)   _rcn_a="$RCN_ID"; _rcn_ty=bionic:test-runner ;;
    type-only) _rcn_a="";        _rcn_ty=bionic:test-runner ;;
    none)      _rcn_a="";        _rcn_ty="" ;;
  esac
  [ "$(rcn_dp_admits bionic:implementor "$_rcn_a" "$_rcn_ty")" = no ] && RCN_CTX_DP="${RCN_CTX_DP}${_rcn_shape};"
  [ "$(rcn_eg_refuses "$_rcn_a" "$_rcn_ty")" = yes ] && RCN_CTX_EG="${RCN_CTX_EG}${_rcn_shape};"
done
expect_eq "RC-nest the dispatch wall reads only the agent_id-carrying shape as a subagent" "id+type;" "$RCN_CTX_DP"
expect_eq "RC-nest …and ARM C reads the same shapes as a subagent" "$RCN_CTX_DP" "$RCN_CTX_EG"

# ============================================================
section "CG-followup — the sweeper's FOLLOW-UP reading and roster_open_names agree on a messaged name (epic-23 wave-20 T9b; review R2; D4, D10)"
# ============================================================
#
# THE DEFECT (review R2, walk §8c). FOLLOW-UP rewrote any MET row a SendMessage followed, so a
# row acked after its launch (closed to `roster_open_names`, the one close predicate) read
# FOLLOW-UP to the sweeper, and standdown held it for a reply that could never come. One
# fixture per history, each a MET row the orchestrator messaged after its last reply:
#   closed   launched, acked, then messaged              -> CLOSED to both readers
#   open     launched, never acked, then messaged        -> OPEN   (held FOLLOW-UP)
#   again    launched, acked, launched again, messaged   -> OPEN   (the relaunch reopens it)
# The sweeper's reading: FOLLOW-UP is a held row (open); MET with acked=yes is closed.
cgfu_world() {  # <case: closed|open|again> -> repo path
  local r ro le cfg n="cgfu-$1"
  r=$(new_repo "cgfu-$1")
  ro="$r/.bionic/tmp/roster-$SID_A.state"; le="$r/.bionic/tmp/sweeper-$SID_A.state"
  echo done > "$r/landed.md"
  roster_header > "$ro"
  roster_row_fixture status=identified session="$SID_A" name="$n" agent_id="a$n-1" \
    launched_at=2026-09-01T00:00:00Z tool_use_id=toolu_01CGFU deliverable="$r/landed.md" >> "$ro"
  case "$1" in
    closed) cgc_ack "$le" 2026-09-01T01:00:00Z "$n" ;;
    again)
      cgc_ack "$le" 2026-09-01T01:00:00Z "$n"
      roster_row_fixture status=identified session="$SID_A" name="$n" agent_id="a$n-2" \
        launched_at=2026-09-01T02:00:00Z tool_use_id=toolu_01CGFU deliverable="$r/landed.md" >> "$ro"
      ;;
  esac
  cfg="$SANDBOX/cgfu-cfg-$1"; mkdir -p "$cfg/projects/-cgfu"
  # Each hand-back names landed.md (wave-24 T29: a message that names no deliverable is no
  # completion signal).
  {
    jq -nc --arg n "$n" '{type:"user",isMeta:true,isSidechain:false,timestamp:"2026-09-01T00:30:00.000Z",message:{role:"user",content:("Another Claude session sent a message:\n<agent-message from=\"" + $n + "\">\n[Subagent hand-back] done: landed.md\n</agent-message>")}}'
    # The relaunched contract reports too, after its own launch (wave-24 T9, D3: MET needs it).
    [ "$1" = again ] && jq -nc --arg n "$n" '{type:"user",isMeta:true,isSidechain:false,timestamp:"2026-09-01T02:30:00.000Z",message:{role:"user",content:("Another Claude session sent a message:\n<agent-message from=\"" + $n + "\">\n[Subagent hand-back] done again: landed.md\n</agent-message>")}}'
    jq -nc --arg n "$n" '{type:"assistant",isSidechain:false,timestamp:"2026-09-01T03:00:00.000Z",message:{role:"assistant",content:[{type:"tool_use",id:"toolu_01CGFUSEND",name:"SendMessage",input:{to:$n,summary:"s",message:"one more thing"}}]}}'
  } > "$cfg/projects/-cgfu/$SID_A.jsonl"
  printf '%s' "$r"
}
cgfu_sweeper() {  # <repo> <name> <case> -> open | closed | other:<line>
  local line
  line=$( ( cd "$1" && CLAUDE_CODE_SESSION_ID="$SID_A" CLAUDE_CONFIG_DIR="$SANDBOX/cgfu-cfg-$3" \
            bash "$SWEEPER" verdict "$2" 2>/dev/null ) | grep -F 'landing-verdict/v1|' | head -1)
  case "$line" in
    *"|state=FOLLOW-UP|"*)          printf 'open' ;;
    *"|state=MET|acked=yes|"*)      printf 'closed' ;;
    *) printf 'other:%s' "$line" ;;
  esac
}
cgfu_open_names() {  # <repo> <name> -> open | closed
  local names
  names=$( ( BIONIC_LIB_WANT=""; . "$CGC_LIBDIR/roster.sh" >/dev/null 2>&1
             roster_open_names "$1/.bionic/tmp/roster-$SID_A.state" "$1/.bionic/tmp/sweeper-$SID_A.state" "$SID_A" ) 2>/dev/null )
  if grep -qxF -- "$2" <<< "$names"; then printf 'open'; else printf 'closed'; fi
}
for _cgfu in closed:closed open:open again:open; do
  _cgfu_case="${_cgfu%%:*}"; _cgfu_want="${_cgfu#*:}"
  _cgfu_r=$(cgfu_world "$_cgfu_case")
  _cgfu_sw=$(cgfu_sweeper "$_cgfu_r" "cgfu-$_cgfu_case" "$_cgfu_case")
  _cgfu_ro=$(cgfu_open_names "$_cgfu_r" "cgfu-$_cgfu_case")
  expect_eq "CG-followup ${_cgfu_case}: roster_open_names answers ${_cgfu_want}" "$_cgfu_want" "$_cgfu_ro"
  expect_eq "CG-followup ${_cgfu_case}: the sweeper's FOLLOW-UP reading answers ${_cgfu_want}" "$_cgfu_want" "$_cgfu_sw"
done
# ONE OWNER: the sweeper's follow-up path asks row_acked, which reads ACKED_OPEN, which is
# roster_open_names; it keeps no ack reading of its own.
CGFU_FN=$(awk '/^verdict_followup\(\)/{f=1} f{print} f && /^}/{exit}' "$SWEEPER")
expect_contains "CG-followup verdict_followup asks row_acked (the close predicate's answer)" "row_acked" "$CGFU_FN"
expect_eq "CG-followup verdict_followup reads no ledger itself" "0" \
  "$(grep -c 'LEDGER_FILE\|event=ack' <<< "$CGFU_FN")"


# ============================================================
section "CG-ledger — ONE ledger reader: the gate's refusal ids ARE the tick's LEDGER ids (epic-23 wave-21 T5; REQ-4 AC-4.1; D4, ADR-037 decision 3)"
# ============================================================
#
# TWO CALLERS, ONE READER. `units_findings` names every ledger defect; the commit gate refuses
# on it and the Patrol tick prints it as `poker: LEDGER <id> <kind> [<value>]`. AC-4.1 fails
# when a plan the gate refuses ticks clean, or a plan that ticks a finding commits. So one
# wave plan carrying all three kinds — a status off the enum (T1), a landed row with no line
# (T2), an active row whose agent cell names no roster row (T3) — beside a launched active row
# (T4) and a self-owned one (T5) that are NOT findings. The REAL tick reads it once; the REAL
# gate is then driven to a commit, one refusal at a time, each refused row repaired by the
# kind the tick named for it. The ids the gate refused on must be the ids the tick printed,
# and the repaired plan must both commit and tick clean.
#
# AND IN EVERY TICK STATE (wave-21 T13; the audit's refutation of AC-4.1 at 3b45d05). The tick
# printed its LEDGER lines only inside the FILL branch, while the gate reads the ledger in every
# state — so under HOLD, or on the first tick before any roster exists, a plan the gate refused
# ticked clean. `cgl_case` runs the whole agreement once per state: FILL (a healthy machine and
# a roster), NO ROOM (a five-minute load over the share; was HOLD) and NO ROSTER (armed, nothing dispatched:
# the first tick of every run). With no roster both readers take the no-roster rule, so T3's
# agent-named active row is an `evidence` finding there rather than a `launch` one, and the
# gate folds the two evidence rows into one refusal.
#
# AND OVER THE RUN'S ROSTERS (wave-36 T29; REQ-4 AC-4.1; D10). Both readers take one list,
# `units_run_rosters`: this session's roster, then every roster of the plan. `-run` keeps every launch
# row on session B's roster, dispatched under this plan, and this session's roster empty, so a reader
# that reads `roster-<sid>` alone names T4 too and the repaired plan never commits or ticks clean.
# cgl_case <label> <five-minute load> <roster: yes|no> <want kinds> <want refusals> [<launch rows: own|run>]
cgl_case() {
  local lbl="$1" load5="$2" roster="$3" want_kinds="$4" want_n="$5" home="${6:-own}"
  CGL_R=$(new_repo "cgl${lbl}")
  CGL_P="$CGL_R/.bionic/docs/plans/epic-99/cgl.plan.md"
  CGL_RO="$CGL_R/.bionic/tmp/roster-$SID_A.state"
  CGL_LOAD5="$load5"
  mkdir -p "$(dirname "$CGL_P")"
  cat > "$CGL_P" <<CGLEOF
---
governing-skill: canonical-sdlc
canonical_sdlc_version: 14
intent: build
rigor: double
scale: wave
multi_agent: true
use_worktree: true
parallel-budget: writers=8 suites=4 worktrees=8 test_jobs=8 source=user
---

# Fixture plan

## SDLC State

integration-branch: main
current: 4
Step 1: requirements: $CGL_P
approved-by: fixture 2026-10-01T00:00Z approved

- Step 3: prior evidence
Step 4:
  worktree: .worktrees/cgl
  base-sha: 0b9935d
  branch: wave/cgl

- T4: dispatched to w-T4

## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | status |
|---|---|---|---|---|---|---|---|---|---|
| T1 | 4 | build | a status off the enum | w-T1 | — | 30m | REQ-x | a.sh | doing |
| T2 | 4 | build | landed, no line | w-T2 | — | 30m | REQ-x | b.sh | landed |
| T3 | 4 | build | active, agent names no roster row | bionic:implementor | — | 30m | REQ-x | c.sh | active |
| T4 | 4 | build | active, launched | w-T4 | — | 30m | REQ-x | d.sh | active |
| T5 | 4 | build | active, self-owned | — | — | 30m | REQ-x | e.sh | active |
CGLEOF
  s4_bind "$CGL_R" "$SID_A" "$CGL_P"
  # WHERE THE LAUNCH ROWS GO: this session's roster, or session B's under this plan's binding.
  CGL_RL="$CGL_RO"; CGL_RSID="$SID_A"; CGL_RPLAN=none
  if [ "$home" = run ]; then
    CGL_RL="$CGL_R/.bionic/tmp/roster-$SID_B.state"; CGL_RSID="$SID_B"
    CGL_RPLAN="$(sed -n 's/^plan=//p' "$CGL_R/.bionic/tmp/engaged-$SID_A.state")"
    roster_header > "$CGL_RL"
  fi
  if [ "$roster" = yes ]; then
    roster_header > "$CGL_RO"
    roster_row_fixture status=identified session="$CGL_RSID" name=w-T4 agent_id=a-w-T4 \
      tool_use_id=toolu_01CGLT4 deliverable= plan="$CGL_RPLAN" >> "$CGL_RL"
  fi
  [ "$home" = own ] || expect_eq "CG-ledger${lbl} precondition: w-T4 is on session B's roster under this plan, none on this one" \
    "1 0" "$(/usr/bin/grep -cF "|plan=$CGL_RPLAN" "$CGL_RL") $(/usr/bin/grep -c '^roster-state/' "$CGL_RO")"
  s4_attest "$CGL_R" "$SID_A"
  # THE FIRST TICK OF A RUN IS AN ARMED ONE: with no roster file the tick answers QUIET only
  # for a session that armed here (session-poker.sh's AC-38 split), and refuses otherwise.
  [ "$roster" = yes ] || ( cd "$CGL_R" && env CLAUDE_CODE_SESSION_ID="$SID_A" bash "$CGC_POKER" arm >/dev/null 2>&1 )
  CGL_TICK="$(cgl_tick)"
  case "$lbl" in
    # The owed writer is promised resources.sh's suite cost (wave-38 T5; D21), lifted, never a literal.
    -hold) expect_contains "CG-ledger${lbl} precondition: the gate gives the tick no room" "load=1.0/${load5} of 8 promised=$( . "$REPO_ROOT/payload/scripts/lib/resources.sh" 2>/dev/null; _res_suite_cores ) admitted=0 waiting=0 room=no" "$CGL_TICK" ;;
    -noroster) expect_contains "CG-ledger${lbl} precondition: the tick is the armed first tick, QUIET" \
                 "poker: QUIET — armed, nothing dispatched yet on this session" "$CGL_TICK" ;;
  esac
  CGL_LEDGER="$(printf '%s\n' "$CGL_TICK" | sed -n 's/^poker: LEDGER //p')"
  CGL_TICK_IDS="$(printf '%s\n' "$CGL_LEDGER" | awk 'NF { print $1 }' | LC_ALL=C sort -u | tr '\n' ' ')"
  expect_eq "CG-ledger${lbl} precondition: the real tick names exactly the three defective rows" "T1 T2 T3 " "$CGL_TICK_IDS"
  expect_eq "CG-ledger${lbl} precondition: …one of each kind" "$want_kinds" \
    "$(printf '%s\n' "$CGL_LEDGER" | awk 'NF { print $2 }' | LC_ALL=C sort -u | tr '\n' ' ')"

  # THE GATE, TO A COMMIT. Each refusal's detail names its rows (`T1: status …` from the
  # validator, `- T2:` and `- T3: <agent>` from the two ledger arms); each named row is repaired
  # by the kind the tick printed for it. Bounded: three kinds, so a fifth refusal is a loop.
  CGL_GATE_IDS=""; CGL_N=0; CGL_RC=2; CGL_OUT=""
  while [ "$CGL_N" -lt 5 ]; do
    cgl_gate
    [ "$CGL_RC" -eq 2 ] || break
    CGL_N=$((CGL_N + 1))
    CGL_NAMED="$(printf '%s\n' "$CGL_OUT" | sed -n -E 's/^(- )?(T[0-9]+):.*/\2/p' | LC_ALL=C sort -u)"
    if [ -z "$CGL_NAMED" ]; then no "CG-ledger${lbl} refusal $CGL_N names no ledger row" "$CGL_OUT"; break; fi
    for _cgl_id in $CGL_NAMED; do
      CGL_GATE_IDS="${CGL_GATE_IDS}${_cgl_id}"$'\n'
      case "$(printf '%s\n' "$CGL_LEDGER" | awk -v id="$_cgl_id" '$1 == id { print $2; exit }')" in
        status)   sed -i.bak "s/| a.sh | doing |/| a.sh | pending |/" "$CGL_P" ;;
        evidence) awk -v id="$_cgl_id" '{ print } $0 == "- T4: dispatched to w-T4" { print "- " id ": bash suite 9/9 green" }' \
                    "$CGL_P" > "$CGL_P.new" && mv "$CGL_P.new" "$CGL_P" ;;
        launch)   sed -i.bak "s/| bionic:implementor |/| w-${_cgl_id} |/" "$CGL_P"
                  roster_row_fixture status=identified session="$CGL_RSID" name="w-${_cgl_id}" \
                    agent_id="a-w-${_cgl_id}" tool_use_id="toolu_01CGL${_cgl_id}" deliverable= plan="$CGL_RPLAN" >> "$CGL_RL" ;;
        *) no "CG-ledger${lbl} the gate refused $_cgl_id, which the tick never named" "$CGL_OUT" ;;
      esac
    done
  done
  rm -f "$CGL_P.bak"
  expect_eq "CG-ledger${lbl} AC-4.1 the gate's refusal ids are the tick's LEDGER ids" \
    "$CGL_TICK_IDS" "$(printf '%s' "$CGL_GATE_IDS" | LC_ALL=C sort -u | tr '\n' ' ')"
  expect_eq "CG-ledger${lbl} …one refusal per kind" "$want_n" "$CGL_N"
  expect_eq "CG-ledger${lbl} AC-4.1 the repaired plan commits" "0" "$CGL_RC"
  expect_absent "CG-ledger${lbl} AC-4.1 …and ticks clean" "poker: LEDGER" "$(cgl_tick)"
}
cgl_tick() {
  cgc_ring
  ( cd "$CGL_R" && env CLAUDE_CODE_SESSION_ID="$SID_A" BIONIC_PRESSURE_RING="$CGC_RING" \
      BIONIC_PROBE_FREE_PCT=80 BIONIC_PROBE_SWAP_PCT=0 BIONIC_PROBE_LOAD_1M=0.1 \
      BIONIC_PROBE_FREE_MB=8192 BIONIC_PROBE_BUSY_CORES_5M="${CGL_LOAD5:-1.0}" \
      bash "$CGC_POKER" tick 2>&1 )
}
# The gate's whole channel goes to CGL_OUT and its status to CGL_RC, in this shell: a
# `$( )` caller would lose the status with the subshell.
cgl_gate() {
  CGL_OUT=$(mk_bash_payload "$SID_A" "$SANDBOX/t.jsonl" "$CGL_R" "git commit -m x" \
    | env -u CLAUDE_PROJECT_DIR HOME="$CGL_R" CLAUDE_CODE_SESSION_ID="$SID_A" bash "$PARTY_EG" 2>&1)
  CGL_RC=$?
}
cgl_case ""          1.0 yes "evidence launch status " 3
cgl_case "-hold"     7.0 yes "evidence launch status " 3
cgl_case "-noroster" 1.0 no  "evidence status " 2
cgl_case "-run"      1.0 yes "evidence launch status " 3 run


# ============================================================
section "AM — an AMENDED contract on a TEAMMATE roster reaches every reader keyed on the agent id (epic-23 wave-22 T2; REQ-1 AC-1.1, AC-1.2, AC-1.4, AC-1.5; D1)"
# ============================================================
#
# THE DEFECT (wave-22 seed). A teammate's roster ends `intended` (no id) -> `identified` (the
# id, learned at SubagentStart) -> `confirmed` with `agent_id=` EMPTY (the recorder's copy of
# the launch row, written after the spawn returns). `session-poker.sh amend` used to copy the
# NAME's latest row, empty id and all, so the budget arm of hooks/bash-walls.sh, which keys
# on the payload's `agent_id`, never saw the widened contract and refused the added run right
# after `poker: amended` printed. T1 made the successor carry the identity triple of the
# agent's latest id-bearing row (same dispatch cycle), and made the arm and the verb read ONE
# pick, `roster_row_for_id`.
#
# THIS SECTION IS THE CHAIN, not the unit. tests/roster.test.sh R11 and tests/session-poker.test.sh
# 30t pin the helper and the verb; what no per-script suite asserts is that the verb's ROW is
# the one every OTHER reader of the id then reads. Each case below names the components it
# chains, and builds ONE roster of its own:
#   AM1  poker amend  ->  bash-walls budget arm (re_executes=)
#   AM2  poker amend  ->  bash-walls budget arm (suites_allowed=)
#   AM3  poker amend  ->  execution-recorder SubagentStart  ->  bash-walls budget arm
#   AM4  poker amend  ->  stop-guard (TaskStop by id), stop-check observation (by id), poker tick
#   AM5  poker amend  ->  sweeper ack  ->  execution-recorder SubagentStart (restart)  ->  bash-walls budget arm
#   AM5b poker amend  ->  recorder start (open)  ->  ack  ->  recorder start (restart)  ->  budget arm
#   AM6  async roster (confirmed WITH the id)  ->  poker amend  ->  bash-walls budget arm
# The roster's shape is T1's §30 teammate fixture (tests/session-poker.test.sh `s30_teammate`:
# the identified row, then a `confirmed` row with an empty id, one tool_use_id), preceded by
# the launch's `intended` row. Rows are written by roster_row_fixture, the writer's own.
#
# THE REFUSAL HALF IS THE BASE PIN. Every case first drives the arm over the roster as the
# recorder left it, BEFORE the amend: it must refuse the added run naming only the original.
# That is the defect's own observable, and it is what makes each ALLOW below a change rather
# than a wall that never refused anything.

# ITS OWN SESSION ID. The tick finds the session transcript by scanning the config dir for
# `<session>.jsonl` across every project, so under `$SID_A` it could land on the transcript a
# much earlier section planted for the same id, and answer from THAT section's live set.
AM_SID="3b9e5a71-6d20-4c48-9e1f-5a7c0d4b8e12"
AM_ID="aw1-3000000000000001"
AM_RUN_A="npx jest --testPathPatterns gadget"
AM_RUN_B="npx jest --testPathPatterns widget"
AM_RE_A='`'"$AM_RUN_A"'`'
# A declared run is stored with its author marks, backticks kept (T1 A-T1.4): an unmarked run
# is prose to the arm, not a declaration.

am_world() {  # <label> -> repo path (a teammate roster for w1, session $AM_SID, engaged)
  local r ro
  r=$(new_repo "am-$1")
  # THE PROJECT HAS THE RUNNER'S DOOR (wave-28 T54): the one door fires only where tests/run.sh says --only,
  # so this world plants the same runner as tests/bash-walls.test.sh's bw_door, committed with the seed.
  mkdir -p "$r/tests"; printf '#!/bin/bash\n# usage: tests/run.sh [--only <suite>.test.sh ...]\ncase "${1:-}" in --only) shift ;; esac\n' > "$r/tests/run.sh"
  arm_patrol "$r" "$AM_SID"; engage_sids "$r" "$AM_SID"
  ro="$r/.bionic/tmp/roster-$AM_SID.state"
  roster_header > "$ro"
  roster_row_fixture status=intended session="$AM_SID" name=w1 agent_id= \
    launched_at=2026-09-01T00:00:00Z subagent_type=bionic:implementor source=declared \
    deliverable="$r/never-yet.md" duration="2 hours" files=hooks/a.sh \
    suites_allowed=a.test.sh suites_source=declared re_executes="$AM_RE_A" \
    tool_use_id=toolu_am_w1 >> "$ro"
  roster_row_fixture status=identified session="$AM_SID" name=w1 agent_id="$AM_ID" \
    launched_at=2026-09-01T00:00:00Z subagent_type=bionic:implementor source=declared \
    deliverable="$r/never-yet.md" duration="2 hours" files=hooks/a.sh \
    suites_allowed=a.test.sh suites_source=declared re_executes="$AM_RE_A" \
    teammate_id=w1@session-8a41c2e0 tool_use_id=toolu_am_w1 >> "$ro"
  roster_row_fixture status=confirmed session="$AM_SID" name=w1 agent_id= \
    launched_at=2026-09-01T00:00:00Z subagent_type=bionic:implementor source=declared \
    deliverable="$r/never-yet.md" duration="2 hours" files=hooks/a.sh \
    suites_allowed=a.test.sh suites_source=declared re_executes="$AM_RE_A" \
    teammate_id=w1@session-8a41c2e0 tool_use_id=toolu_am_w1 >> "$ro"
  printf '%s' "$r"
}
# The verb. Sets AM_OUT and AM_RC in this shell (never inside `$( )`, which would take both).
am_amend() {  # <repo> <args…>
  local r="$1"; shift
  AM_OUT=$( cd "$r" && env CLAUDE_CODE_SESSION_ID="$AM_SID" CLAUDE_CONFIG_DIR="$r/no-such-config" \
              "${CGC_ENV[@]}" bash "$PARTY_PK_S" amend "$@" 2>&1 )
  AM_RC=$?
}
# THE BUDGET ARM: the PreToolUse Bash wall, payload carrying `agent_id`. Sets AM_ARM_ST and
# AM_ARM_OUT (the wall's whole channel).
am_arm() {  # <repo> <agent-id> <command>
  AM_ARM_OUT=$(mk_bash_payload "$AM_SID" "$1/am-transcript.jsonl" "$1" "$3" \
      | jq -c --arg a "$2" '. + {agent_id:$a, agent_type:"bionic:implementor"}' \
      | env -u CLAUDE_PROJECT_DIR HOME="$1" CLAUDE_CODE_SESSION_ID="$AM_SID" \
          bash "$PARTY_EG" 2>&1)
  AM_ARM_ST=$?
}
am_last() { grep -F "|name=w1|" "$1/.bionic/tmp/roster-$AM_SID.state" | tail -1; }
am_field() { printf '%s' "$1" | tr '|' '\n' | grep "^$2=" | head -1 | cut -d= -f2-; }

am_budget_line() { printf '%s\n' "$1" | grep '^On the budget:' | head -1; }
# The row a reader keyed on the id reads: the id's LAST row (the budget arm's pick, no status
# filter) and the id's last confirmed|identified row (stop-guard.sh's and stop-check.sh's by-id
# pick, :507-510 / :301-305 at 12574e2).
am_idpick()  { grep -F "|agent_id=$AM_ID|" "$1/.bionic/tmp/roster-$AM_SID.state" | tail -1; }
am_idpick_ci() { grep -F "|agent_id=$AM_ID|" "$1/.bionic/tmp/roster-$AM_SID.state" | grep -E '\|status=(confirmed|identified)\|' | tail -1; }

# ---- AM1: amend --reexec+ -> the budget arm admits the added run, and refused it before ----
AM_R1=$(am_world 1)
am_arm "$AM_R1" "$AM_ID" "$AM_RUN_B"
expect_eq "AM1 [poker amend -> bash-walls budget arm] BEFORE the amend the arm refuses the added run (the base pin, RED half)" "2" "$AM_ARM_ST"
expect_contains "AM1 …the refusal's budget names the original run" "$AM_RUN_A" "$(am_budget_line "$AM_ARM_OUT")"
expect_absent "AM1 …and ONLY the original: the added run is not on the budget it names" "widget" "$(am_budget_line "$AM_ARM_OUT")"
am_arm "$AM_R1" "$AM_ID" "$AM_RUN_A"
expect_eq "AM1 …while the original run is admitted (the arm reads the declaration, it is not refusing everything)" "0" "$AM_ARM_ST"
am_amend "$AM_R1" w1 --reexec+ "$AM_RUN_B" --reason x
expect_eq "AM1 the amend exits 0" "0" "$AM_RC"
expect_contains "AM1 …printing its success line" "poker: amended — w1:" "$AM_OUT"
am_arm "$AM_R1" "$AM_ID" "$AM_RUN_B"
expect_eq "AM1 AFTER the amend the arm ADMITS the added run (AC-1.1)" "0" "$AM_ARM_ST"
am_arm "$AM_R1" "$AM_ID" "$AM_RUN_A"
expect_eq "AM1 …and still admits the original run: an amend widens, it does not replace" "0" "$AM_ARM_ST"
am_arm "$AM_R1" "$AM_ID" "npx jest --testPathPatterns undeclared"
expect_eq "AM1 …and still refuses a run nobody declared: the arm was not switched off" "2" "$AM_ARM_ST"
expect_eq "AM1 the name's latest row carries the agent's id (the successor is not an empty-id copy)" "$AM_ID" "$(am_field "$(am_last "$AM_R1")" agent_id)"
expect_eq "AM1 …and the name's latest row IS the id's latest row: the verb and the wall read one row" \
  "$(am_last "$AM_R1")" "$(am_idpick "$AM_R1")"

# ---- AM2: amend --suites+ -> the budget arm admits the added suite (AC-1.2, suites half) ----
AM_R2=$(am_world 2)
am_arm "$AM_R2" "$AM_ID" "tests/run.sh --only s.test.sh"
expect_eq "AM2 [poker amend -> bash-walls budget arm] BEFORE the amend the arm refuses the added suite" "2" "$AM_ARM_ST"
expect_absent "AM2 …and the budget it names does not carry the added suite" "s.test.sh" "$(am_budget_line "$AM_ARM_OUT")"
am_amend "$AM_R2" w1 --suites+ tests/s.test.sh --reason x
expect_eq "AM2 the amend exits 0" "0" "$AM_RC"
am_arm "$AM_R2" "$AM_ID" "tests/run.sh --only s.test.sh"
expect_eq "AM2 AFTER the amend the arm ADMITS the added suite (AC-1.2)" "0" "$AM_ARM_ST"
am_arm "$AM_R2" "$AM_ID" "tests/run.sh --only a.test.sh"
expect_eq "AM2 …and still admits the suite the brief declared" "0" "$AM_ARM_ST"
am_arm "$AM_R2" "$AM_ID" "tests/run.sh --only z.test.sh"
expect_eq "AM2 …and still refuses a suite nobody declared" "2" "$AM_ARM_ST"
expect_eq "AM2 …and the name's latest row IS the id's latest row" "$(am_last "$AM_R2")" "$(am_idpick "$AM_R2")"

# ---- AM3: amend, then the recorder's SubagentStart for the same teammate -> the restart row
# carries the amended contract, and the arm still admits the added run (AC-1.4) ----
# `AM_R1` is AM1's world, amended with run B. The recorder takes its SubagentStart payload for
# the same teammate (name in `agent_type`, the transcript-form id in `agent_id`, capture probe
# §3-C) and, the id being identified already with an open contract, journals it a duplicate.
AM_TR1="$AM_R1/am-transcript.jsonl"
printf '{}\n' > "$AM_TR1"
AM_N3=$(grep -c '|name=w1|' "$AM_R1/.bionic/tmp/roster-$AM_SID.state")
mk_start_payload "$AM_SID" "$AM_TR1" "$AM_R1" w1 "$AM_ID" \
  | env CLAUDE_CODE_SESSION_ID="$AM_SID" bash "$PARTY_ER" >/dev/null 2>&1
expect_eq "AM3 [poker amend -> execution-recorder SubagentStart -> bash-walls budget arm] the restart wrote ONE row" \
  "$((AM_N3 + 1))" "$(grep -c '|name=w1|' "$AM_R1/.bionic/tmp/roster-$AM_SID.state")"
AM_L3=$(am_idpick "$AM_R1")
expect_eq "AM3 …the id's last row is the duplicate-start" "duplicate-start" "$(am_field "$AM_L3" status)"
expect_contains "AM3 …carrying the amended run, not only the original (AC-1.4)" "$AM_RUN_B" "$(am_field "$AM_L3" re_executes)"
expect_contains "AM3 …and the original beside it" "$AM_RUN_A" "$(am_field "$AM_L3" re_executes)"
expect_eq "AM3 …and it is the name's latest row too" "$(am_last "$AM_R1")" "$AM_L3"
am_arm "$AM_R1" "$AM_ID" "$AM_RUN_B"
expect_eq "AM3 the arm still ADMITS the added run after the restart" "0" "$AM_ARM_ST"
am_arm "$AM_R1" "$AM_ID" "npx jest --testPathPatterns undeclared"
expect_eq "AM3 …and still refuses an undeclared run" "2" "$AM_ARM_ST"

# ---- AM4: amend -> the stop wall and the observation typed by the id; the tick (AC-1.5) ----
#
# WHAT THEY PRINT. Neither hooks/stop-guard.sh nor hooks/stop-check.sh prints an agent's
# `re_executes=`: the contract they show is the deliverable, the progress artifact and the
# cadence, none of which an amend changes. So what can disagree on a teammate roster, and
# what this case pins, is WHICH AGENT and WHICH ROW each reader resolves when typed by the id
# (a non-empty id, found in the roster, the contract read from the roster) and that the row
# their by-id rule picks (the id's last confirmed|identified row) IS the amended one, which the
# first pair of assertions states directly. The tick's reading is the liveness read off the
# name's latest row: an empty id there reads no transcript at all and the row is never named
# quiet, a non-empty one finds the agent's log and names it.
AM_R4=$(am_world 4)
AM_BEFORE4=$(am_idpick_ci "$AM_R4")
am_amend "$AM_R4" w1 --reexec+ "$AM_RUN_B" --reason x
expect_eq "AM4 [poker amend -> stop-guard, stop-check, tick] the amend exits 0" "0" "$AM_RC"
expect_absent "AM4 the by-id pick BEFORE the amend carries only the original run" "widget" "$AM_BEFORE4"
expect_contains "AM4 …and AFTER it the by-id pick (confirmed|identified) carries the added run" "$AM_RUN_B" "$(am_idpick_ci "$AM_R4")"
expect_eq "AM4 …and that pick is the name's latest row" "$(am_last "$AM_R4")" "$(am_idpick_ci "$AM_R4")"
AM_SLUG=$(printf '%s' "$AM_R4" | sed 's/[^a-zA-Z0-9]/-/g')
AM_PROJ="$CLAUDE_CONFIG_DIR/projects/$AM_SLUG"
AM_SUB="$AM_PROJ/$AM_SID/subagents"
mkdir -p "$AM_SUB"
AM_TR4="$AM_PROJ/$AM_SID.jsonl"
printf '{"name":"w1","agentType":"implementor","description":"fixture","model":"opus"}' \
  > "$AM_SUB/agent-$AM_ID.meta.json"
printf '{"type":"assistant","message":{"content":[{"type":"text","text":"working"}]}}\n' \
  > "$AM_SUB/agent-$AM_ID.jsonl"
cg_live "$AM_TR4" w1
# The log is FRESH here: the stop wall's answer is then a refusal that names the agent and
# prints the contract it read, which is the channel this case reads.
AM_OBS=$( cd "$AM_R4" && env CLAUDE_CODE_SESSION_ID="$AM_SID" bash "$OBSERVE" "$AM_ID" 2>&1 )
expect_contains "AM4 the observation typed by the id resolves to that id" "Resolved:      $AM_ID" "$AM_OBS"
expect_contains "AM4 …reads the contract from the roster, by the id" "Contract (roster):  deliverables=$AM_R4/never-yet.md" "$AM_OBS"
expect_contains "AM4 …and publishes a non-empty target on its machine line" "|target=$AM_ID|" "$AM_OBS"
expect_contains "AM4 …sourcing the deliverable from the roster" "|deliverable_source=roster|" "$AM_OBS"
AM_SG=$(mk_stop_payload "$AM_SID" "$AM_TR4" "$AM_R4" "$AM_ID" | bash "$PARTY_SG" 2>&1); AM_SG_RC=$?
expect_eq "AM4 the stop wall typed by the id allows a stop of a working agent, its verdict recorded (wave-31 T32)" "0" "$AM_SG_RC"
expect_contains "AM4 …naming the agent by its non-empty id" "'$AM_ID' ($AM_ID) is ALIVE" "$AM_SG"
expect_contains "AM4 …and printing the roster's contract for it" "deliverable:  pending — $AM_R4/never-yet.md" "$AM_SG"
# THE TICK, over the same roster with the agent's log aged past its cadence. Its reading is
# `row_quiet` on the name's latest row; the assertion is on what it READ (the transcript of
# THAT id, named in the quiet line), not on the decision line.
# The recorded ListAgents answer is taken OFF the session transcript first: with a fresh live
# answer that does not list the agent as running, the tick files the row under GONE and never
# reads its liveness, which is a different arm from the one this case is about (and which of
# the two a run reaches depended on what earlier sections left in the environment).
printf '{}\n' > "$AM_TR4"
touch -t 202601010000 "$AM_SUB/agent-$AM_ID.jsonl"
AM_TICK=$( cd "$AM_R4" && env CLAUDE_CODE_SESSION_ID="$AM_SID" CLAUDE_CONFIG_DIR="$AM_R4/no-such-config" \
             CLAUDE_CONFIG_DIR="$CLAUDE_CONFIG_DIR" "${CGC_ENV[@]}" bash "$PARTY_PK_S" tick 2>&1 )
expect_contains "AM4 the tick read the agent's transcript off the name's latest row (a non-empty id)" \
  "w1: no line for " "$AM_TICK"
expect_contains "AM4 …naming the log of THAT id" "agent-$AM_ID.jsonl" "$AM_TICK"

# ---- AM5: amend, ACK, then the recorder's SubagentStart -> the RE-IDENTIFIED row carries the
# amended contract and the arm admits the added run (epic-23 wave-22 T9; spec D4 Δ2; critic
# C1; ADR-039 Δ2) ----
#
# THE CASE AM3 DOES NOT REACH. AM3's start lands while the name is OPEN, so the recorder
# journals a `duplicate-start` copied verbatim from the id's last row. Here the orchestrator
# acks the landing FIRST and then SendMessages the writer for a fix-up: the name reads CLOSED,
# the recorder takes the restart-after-ack path and re-identifies the id. Its two joins accept
# `intended|confirmed` only, and on a teammate roster neither of those rows is the amended one:
# the id join finds no row (a teammate's intended and confirmed rows carry no id) and the name
# join takes the recorder's ORIGINAL `confirmed` row. At b2f70c1 the re-identified row then
# carried run A only, became the id's last row, and the budget arm refused run B again. The
# restart now re-identifies from the id's latest STARTED row (`DUP_PRIOR_BEFORE`).
am_ack() {  # <repo> <at> — the sweeper ledger's ack line for w1, in its writer's shape
  local le="$1/.bionic/tmp/sweeper-$AM_SID.state"
  [ -f "$le" ] || printf '# bionic session sweeper ledger — schema sweeper-ledger/v1 — machine-local, safe to delete\n' > "$le"
  printf 'sweeper-ledger/v1|event=ack|at=%s|epoch=0|pid=1|session=%s|name=w1|by=patrol|reason=landed\n' \
    "$2" "$AM_SID" >> "$le"
}
am_start() {  # <repo> — the teammate's SubagentStart: the name in agent_type, the transcript id
  printf '{}\n' > "$1/am-transcript.jsonl"
  mk_start_payload "$AM_SID" "$1/am-transcript.jsonl" "$1" w1 "$AM_ID" \
    | env CLAUDE_CODE_SESSION_ID="$AM_SID" bash "$PARTY_ER" >/dev/null 2>&1
}
am_open() {  # <repo> -> roster_open_names for $AM_SID, sourced in a private subshell
  bash -c '. "$1"; shift; roster_open_names "$@"' _ "${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/roster.sh" \
    "$1/.bionic/tmp/roster-$AM_SID.state" "$1/.bionic/tmp/sweeper-$AM_SID.state" "$AM_SID" 2>/dev/null
}
AM_R5=$(am_world 5)
am_amend "$AM_R5" w1 --reexec+ "$AM_RUN_B" --reason x
expect_eq "AM5 [poker amend -> sweeper ack -> execution-recorder SubagentStart -> bash-walls budget arm] the amend exits 0" "0" "$AM_RC"
am_arm "$AM_R5" "$AM_ID" "$AM_RUN_B"
expect_eq "AM5 …the arm admits the added run before the ack (the amend reached it)" "0" "$AM_ARM_ST"
am_ack "$AM_R5" 2026-09-01T01:00:00Z
expect_absent "AM5 …the ack closes the name (the precondition of the restart path)" "w1" "$(am_open "$AM_R5")"
AM_N5=$(grep -c '|name=w1|' "$AM_R5/.bionic/tmp/roster-$AM_SID.state")
am_start "$AM_R5"
expect_eq "AM5 the restart after the ack wrote ONE row" \
  "$((AM_N5 + 1))" "$(grep -c '|name=w1|' "$AM_R5/.bionic/tmp/roster-$AM_SID.state")"
AM_L5=$(am_idpick "$AM_R5")
expect_eq "AM5 …the id's last row is a fresh identification, not a duplicate" "identified" "$(am_field "$AM_L5" status)"
expect_contains "AM5 …stamped as a restart (restarted_at), so the name reads open again" "restarted_at=" "$AM_L5"
expect_contains "AM5 …and open it reads" "w1" "$(am_open "$AM_R5")"
expect_contains "AM5 …the re-identified row carries the AMENDED run (critic C1: it carried run A only)" "$AM_RUN_B" "$(am_field "$AM_L5" re_executes)"
expect_contains "AM5 …and the original beside it" "$AM_RUN_A" "$(am_field "$AM_L5" re_executes)"
am_arm "$AM_R5" "$AM_ID" "$AM_RUN_B"
expect_eq "AM5 the arm ADMITS the added run after the ack and the restart" "0" "$AM_ARM_ST"
am_arm "$AM_R5" "$AM_ID" "npx jest --testPathPatterns undeclared"
expect_eq "AM5 …and still refuses an undeclared run" "2" "$AM_ARM_ST"

# ---- AM5b: the critic's c2.sh order — amend, a restart while OPEN (duplicate-start), THEN the
# ack, then a second restart. The id's latest started row is now the duplicate-start, and it is
# the one the re-identification copies (its status rewritten to identified). ----
AM_R5B=$(am_world 5b)
am_amend "$AM_R5B" w1 --reexec+ "$AM_RUN_B" --reason x
expect_eq "AM5b [poker amend -> recorder start (open) -> ack -> recorder start -> budget arm] the amend exits 0" "0" "$AM_RC"
am_start "$AM_R5B"
expect_eq "AM5b …the start while open is journalled a duplicate" "duplicate-start" "$(am_field "$(am_idpick "$AM_R5B")" status)"
am_arm "$AM_R5B" "$AM_ID" "$AM_RUN_B"
expect_eq "AM5b …and the arm admits the added run after it" "0" "$AM_ARM_ST"
am_ack "$AM_R5B" 2026-09-01T01:00:00Z
am_start "$AM_R5B"
AM_L5B=$(am_idpick "$AM_R5B")
expect_eq "AM5b the restart after the ack re-identifies the id" "identified" "$(am_field "$AM_L5B" status)"
expect_contains "AM5b …stamped as a restart" "restarted_at=" "$AM_L5B"
expect_contains "AM5b …carrying the AMENDED run" "$AM_RUN_B" "$(am_field "$AM_L5B" re_executes)"
am_arm "$AM_R5B" "$AM_ID" "$AM_RUN_B"
expect_eq "AM5b the arm ADMITS the added run after the second restart (critic c2.sh: refused at b2f70c1)" "0" "$AM_ARM_ST"

# ---- AM6: the ASYNC shape — intended (no id), then ARM 2's `confirmed` WITH the id, no
# identified row yet; amend --reexec+ -> the arm admits the added run (auditor C1, AC-1.3's
# async half chained into the budget arm). A REGRESSION PIN: the name's latest row is the
# id-bearing row, so the identity copy is that row itself, at 12574e2 as at b2f70c1. What it
# guards is an identity source narrowed to `identified` rows, which would leave the async
# successor without an id. ----
AM_R6=$(new_repo "am-6")
arm_patrol "$AM_R6" "$AM_SID"; engage_sids "$AM_R6" "$AM_SID"
AM_RO6="$AM_R6/.bionic/tmp/roster-$AM_SID.state"
roster_header > "$AM_RO6"
roster_row_fixture status=intended session="$AM_SID" name=w1 agent_id= \
  launched_at=2026-09-01T00:00:00Z subagent_type=bionic:implementor source=declared \
  deliverable="$AM_R6/never-yet.md" duration="2 hours" files=hooks/a.sh \
  suites_allowed=a.test.sh suites_source=declared re_executes="$AM_RE_A" \
  tool_use_id=toolu_am_w1 >> "$AM_RO6"
roster_row_fixture status=confirmed session="$AM_SID" name=w1 agent_id="$AM_ID" \
  launched_at=2026-09-01T00:00:00Z subagent_type=bionic:implementor source=declared \
  deliverable="$AM_R6/never-yet.md" duration="2 hours" files=hooks/a.sh \
  suites_allowed=a.test.sh suites_source=declared re_executes="$AM_RE_A" \
  tool_use_id=toolu_am_w1 >> "$AM_RO6"
am_arm "$AM_R6" "$AM_ID" "$AM_RUN_B"
expect_eq "AM6 [async: intended -> confirmed(id); poker amend -> bash-walls budget arm] BEFORE the amend the arm refuses the added run" "2" "$AM_ARM_ST"
am_amend "$AM_R6" w1 --reexec+ "$AM_RUN_B" --reason x
expect_eq "AM6 the amend exits 0" "0" "$AM_RC"
expect_eq "AM6 …the successor carries the agent's id" "$AM_ID" "$(am_field "$(am_last "$AM_R6")" agent_id)"
expect_eq "AM6 …and is the id's latest row" "$(am_last "$AM_R6")" "$(am_idpick "$AM_R6")"
am_arm "$AM_R6" "$AM_ID" "$AM_RUN_B"
expect_eq "AM6 AFTER the amend the arm ADMITS the added run (async shape)" "0" "$AM_ARM_ST"
am_arm "$AM_R6" "$AM_ID" "npx jest --testPathPatterns undeclared"
expect_eq "AM6 …and still refuses an undeclared run" "2" "$AM_ARM_ST"
# ============================================================
section "UB — UNBOUND MEANS NO RUN: every acting arm announces the fallback and acts as under none (wave-23-fixit-1810, REQ-1, AC-1.3; D1)"
# ============================================================
#
# THE CONTRACT (spec D1, Chris 2026-10-02). `session_run` still answers `fallback <plan>` for
# an unbound session in a root with an open run, so every consumer can say which plan the root
# would have handed it. The plan is announced and never acted on: each of the six acting arms
# below prints lib/run.sh's ONE advisory and then takes its `none` path. §S.4c pins that the
# seven announcers still SAY it; this section pins that the six that used to ACT on it no
# longer do, and that the six say one byte-identical thing.
#
# THE SEVENTH, THE COMMIT GATE (spec Δ1, A-orch-8): found by this row's own prototype run,
# it judged an unbound session's commit against the newest open run's step. It is driven
# here beside the six, under the same contract and the same advisory.
#
# EVERY ARM IS DRIVEN TWICE ON ONE WORLD, the binding the only difference: `fallback <p>` must
# not act, and `bound-open <p>` on the same tree MUST act — the anti-vacuity half, without
# which "no spend line, no hold, no refusal" would pass on an arm that had simply gone dead.
#
#   arm               fallback <p>                                  bound-open <p> (control)
#   context-spend     no spend state written                         state names <p>
#   landing guard     no row lookup: "session unbound", checkout     the row's declared base, silent
#   duties gate       a write naming <p> discharges nothing          that write discharges the refresh
#   fill gate         no refusal for <p>'s ready row                 refused: ready with room: T5
#   patrol-revive     a stale stamp revives nothing                  the stale stamp blocks
#   dispatch wall     judged with no plan: writer refused to bind    refused by <p>'s writers=1 budget
#   commit gate       the commit is not judged against <p>           refused: <p>'s step has no evidence

UB_RUN_LIB="$RUN_LIB"
UB_TEMPLATE="$(bash -c '. "$1" && run_unbound_advisory "<p>"' _ "$UB_RUN_LIB")"
UB_STOP_HOOK="$BIONIC_HOOKS_DIR/stop.sh"
UB_RING="$SANDBOX/ub-clear.ring"; printf '1700000000|80|0|1.0|8\n' > "$UB_RING"

ub_mode() {  # <repo> <sid> <plan> <fallback|bound>
  case "$4" in
    bound) bound_marker "$1" "$2" "$3" ;;
    *)     unbound_marker "$1" "$2" empty ;;
  esac
}
# ub_adv <output> <plan> -> the advisory LINES (a line that is the advisory, not a refusal's
# detail quoting it), the plan path folded to <p>
ub_adv() {
  printf '%s\n' "$1" | grep '^run resolved by newest-plan fallback' \
    | awk -v p="$2" '{ while ((i = index($0, p)) > 0) $0 = substr($0, 1, i-1) "<p>" substr($0, i+length(p)); print }'
}
# ub_stop <repo> <sid> <transcript> — the real Stop; sets UB_OUT (stdout) UB_ERR (stderr)
ub_stop() {
  local payload
  payload=$(jq -nc --arg c "$1" --arg s "$2" --arg t "$3" \
    '{session_id:$s, transcript_path:$t, cwd:$c, hook_event_name:"Stop", stop_hook_active:false, background_tasks:[]}')
  UB_OUT=$(env -u CLAUDE_PROJECT_DIR HOME="$1" CLAUDE_CODE_SESSION_ID="$2" \
    BIONIC_PRESSURE_RING="$UB_RING" BIONIC_NOW_EPOCH=1700000000 \
    BIONIC_PROBE_FREE_MB=8192 BIONIC_PROBE_LOAD_1M=1.0 BIONIC_PROBE_FREE_PCT=80 BIONIC_PROBE_SWAP_PCT=0 \
    GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
    bash "$UB_STOP_HOOK" <<< "$payload" 2>"$SANDBOX/ub.err")
  UB_ERR=$(cat "$SANDBOX/ub.err")
}
ub_decision() { printf '%s' "$UB_OUT" | jq -r '.decision // ""' 2>/dev/null; }
# ub_names_id <text> <id> -> the lines that name <id> as a word of its own: a row id a hook
# printed (`FILL T5`, `ready with room: T5`, `T4→T5`, `fill=T5`), or an agent's name that ends in it
# (`w-T5`, `(w26-T5)`), never the same letters inside a path or a longer name
# (`.worktrees/26-T5/`, `/tmp/T47-T5`, `T50`). A row id is judged by what the hook SAYS about the
# row; the paths it prints are wherever this suite and its sandbox happen to sit, and a tree or
# TMPDIR named for a task once turned these rows red (wave-26 T47).
# WHAT TELLS A NAME FROM A PATH (review 15 F6): a dash before the id is part of a name when the
# dash-joined word it ends starts after a character no path is made of; a path's last part
# (`26-T5`, `T47-T5`) is reached through a `/`, so it is never that word.
ub_names_id() {
  printf '%s\n' "$1" | /usr/bin/grep -E "(^|[^A-Za-z0-9_./-])([A-Za-z0-9_]+-)*$2([^A-Za-z0-9_/-]|\$)"
  return 0
}
ub_iso() { date -u -v-"$1"S +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "-$1 seconds" +%Y-%m-%dT%H:%M:%SZ; }
require_helpers ub_mode ub_adv ub_stop ub_decision ub_iso ub_names_id
# The extractor on a planted text: an id inside a path or a longer name is not a mention, an id
# the hook printed as a row is, on each line kind that names one.
expect_eq "UB ub_names_id keeps the lines that name T5 as a row or an agent, and only those" \
  "poker: FILL T5|poker-tick/v1|decision=FILL|fill=T5|poker: CHAIN T4→T5 (30 min)|ready with room: T5 (dispatch them or decline them)|poker: dispatch w-T5 now|poker: LAUNCHED (w26-T5)" \
  "$(ub_names_id "poker: note: run \`bash /x/.worktrees/26-T5/hooks/session-poker.sh arm\`
run resolved by newest-plan fallback (session unbound) — /tmp/T47-T5/w1r/run.md; bind
poker: FILL T5
poker-tick/v1|decision=FILL|fill=T5
poker: CHAIN T4→T5 (30 min)
poker: WAIT T50 — needs T4
ready with room: T5 (dispatch them or decline them)
poker: dispatch w-T5 now
poker: tree at /x/.worktrees/26-T5
poker: tmp /tmp/T47-T5
poker: LAUNCHED (w26-T5)" T5 | paste -sd'|' -)"

UB_ADVS=""   # one normalized advisory per fallback drive, newline-joined, in arm order
ub_collect() {  # <arm> <output> <plan>
  local a n
  a="$(ub_adv "$2" "$3")"
  n=$(printf '%s' "$a" | grep -c . || true)
  expect_eq "UB.$1 fallback: the advisory is printed exactly once" "1" "$n"
  UB_ADVS="${UB_ADVS}${UB_ADVS:+
}$1|$a"
}

# ---- UB.1 context-spend ------------------------------------------------------
UB1=$(new_repo "ub-spend"); UB1_P="$UB1/.bionic/docs/plans/epic-99/run.md"
s4_plan "$UB1_P" 4
jq -nc '{type:"assistant",message:{model:"claude-opus-5",usage:{input_tokens:1000,cache_creation_input_tokens:0,cache_read_input_tokens:2000}}}' > "$UB1/u.jsonl"
ub_mode "$UB1" "$SID_A" "$UB1_P" fallback
rm -f "$UB1/.bionic/tmp/context-spend.state"; ub_stop "$UB1" "$SID_A" "$UB1/u.jsonl"
expect_eq "UB.1 context-spend, fallback: no spend line — no state is written against <p>" "no" \
  "$([ -f "$UB1/.bionic/tmp/context-spend.state" ] && echo yes || echo no)"
ub_collect context-spend "$UB_ERR" "$UB1_P"
ub_mode "$UB1" "$SID_A" "$UB1_P" bound
rm -f "$UB1/.bionic/tmp/context-spend.state"; ub_stop "$UB1" "$SID_A" "$UB1/u.jsonl"
expect_eq "UB.1 context-spend, bound-open (control): the state names <p>" "$UB1_P" \
  "$(cut -f1 < "$UB1/.bionic/tmp/context-spend.state" 2>/dev/null)"

# ---- UB.2 landing guard ------------------------------------------------------
# tests/landing-gate.test.sh §18d's world: the tree is cut from wave/x at BASE, the main
# checkout sits on `develop`, and the plan's row declares BASE. Bound, the declared base is the
# diff base and the landing is silent; unbound, no row is looked up, so the guard takes the
# checkout's branch and says why — exactly what it does with no plan at all.
UB2="$SANDBOX/fx/ub-landing/repo"; mkdir -p "$UB2/.bionic/tmp"
ub_git() { env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git "$@"; }
ub_git -C "$UB2" init -q . && ub_git -C "$UB2" symbolic-ref HEAD refs/heads/main
ub_git -C "$UB2" config user.email t@example.invalid; ub_git -C "$UB2" config user.name T
printf '.bionic\n.bionic/\n.worktrees/\n' > "$UB2/.gitignore"; echo base > "$UB2/base.txt"
ub_git -C "$UB2" add .gitignore base.txt && ub_git -C "$UB2" commit -q -m base
ub_git -C "$UB2" checkout -q -b wave/x
echo w >> "$UB2/a.sh"; ub_git -C "$UB2" add a.sh; ub_git -C "$UB2" commit -q -m "wave a.sh"
UB2_BASE=$(ub_git -C "$UB2" rev-parse HEAD)
echo m >> "$UB2/mid.sh"; ub_git -C "$UB2" add mid.sh; ub_git -C "$UB2" commit -q -m "wave mid.sh"
ub_git -C "$UB2" worktree add -q "$UB2/.worktrees/ubtree" -b wt/ubtree "$UB2_BASE" >/dev/null 2>&1
ub_git -C "$UB2/.worktrees/ubtree" config user.email t@example.invalid
ub_git -C "$UB2/.worktrees/ubtree" config user.name T
ub_git -C "$UB2" checkout -q -b develop main
echo t >> "$UB2/.worktrees/ubtree/b.sh"; ub_git -C "$UB2/.worktrees/ubtree" add b.sh
ub_git -C "$UB2/.worktrees/ubtree" commit -q -m "the task's own edit"
UB2_P="$UB2/.bionic/docs/plans/epic-99/run.md"
mkdir -p "$(dirname "$UB2_P")"
{ printf -- '---\ngoverning-skill: canonical-sdlc\ncanonical_sdlc_version: 14\n---\n\n## SDLC State\n\ncurrent: 4\n\n'
  printf '## Tasks\n\n| id | step | kind | task | agent | deps | size | serves | Files | worktree | base | status |\n'
  printf '|---|---|---|---|---|---|---|---|---|---|---|---|\n'
  printf '| T1 | 4 | build | the task | implementor | — | 30m | REQ-2 | b.sh | ubtree | %s | active |\n' "$UB2_BASE"
} > "$UB2_P"
ub_landing_world() {  # a fresh roster and an undelivered-then-delivered landing, per drive
  roster_header > "$UB2/.bionic/tmp/roster-$SID_A.state"
  rm -f "$UB2/.bionic/tmp/roster-$SID_A.state.swept" 2>/dev/null
  roster_row_fixture status=confirmed session="$SID_A" name=ubtree agent_id=aubtree-1111111111111111 \
    launched_at="$(ub_iso 600)" subagent_type=implementor model=opus deliverable=.bionic/docs/record/ub.md \
    source=declared tool_use_id=toolu_ub files=b.sh >> "$UB2/.bionic/tmp/roster-$SID_A.state"
  mkdir -p "$UB2/.bionic/docs/record"; printf 'the report\n' > "$UB2/.bionic/docs/record/ub.md"
}
ub_landing_world; ub_mode "$UB2" "$SID_A" "$UB2_P" fallback
ub_stop "$UB2" "$SID_A" "$UB2/no-transcript.jsonl"
expect_contains "UB.2 landing guard, fallback: no row lookup — it diffs against the checkout, saying the session is unbound" \
  "landing gate: session unbound and no working-branch resolves; diffing against develop" "$UB_ERR"
expect_absent "UB.2 …and never names <p>'s row" "row T1" "$UB_ERR"
ub_collect landing-guard "$UB_ERR" "$UB2_P"
ub_landing_world; ub_mode "$UB2" "$SID_A" "$UB2_P" bound
ub_stop "$UB2" "$SID_A" "$UB2/no-transcript.jsonl"
expect_absent "UB.2 landing guard, bound-open (control): the row's declared base is used, silently" \
  "landing gate:" "$UB_ERR"
expect_absent "UB.2 …and a.sh, which only the checkout fallback charges, is not named" "a.sh" "$UB_ERR$UB_OUT"

# ---- UB.3 patrol-duties gate -------------------------------------------------
UB3=$(new_repo "ub-duties"); UB3_P="$UB3/.bionic/docs/plans/epic-99/run.md"
s4_plan "$UB3_P" 4
printf 'patrol-stamp/v1|at=%s|session=%s|verb=tick\n' "$(ub_iso 1)" "$SID_A" > "$UB3/.bionic/tmp/patrol-$SID_A.state"
{ jq -nc --arg t "bionic-patrol session=${SID_A:0:8} — Patrol tick. Run: bash /abs/hooks/session-poker.sh tick" \
    '{type:"user",isMeta:true,isSidechain:false,message:{role:"user",content:$t}}'
  jq -nc '{type:"assistant",isSidechain:false,message:{role:"assistant",content:[{type:"tool_use",id:"toolu_la",name:"ListAgents",input:{}}]}}'
  jq -nc --arg p "$UB3_P" '{type:"assistant",isSidechain:false,message:{role:"assistant",content:[{type:"tool_use",id:"toolu_ed",name:"Edit",input:{file_path:$p}}]}}'
} > "$UB3/tick.jsonl"
ub_mode "$UB3" "$SID_A" "$UB3_P" fallback
ub_stop "$UB3" "$SID_A" "$UB3/tick.jsonl"
# The tick turn owes no task-list refresh under any mode (wave-31 T32; D6, AC-6.5): fallback, the
# turn ends and the advisory is printed once (ub_collect); bound-open, it ends as well.
expect_eq "UB.3 duties gate, fallback: the tick turn is not refused, as under none" "" "$(ub_decision)"
ub_collect duties-gate "$UB_ERR" "$UB3_P"
ub_mode "$UB3" "$SID_A" "$UB3_P" bound
ub_stop "$UB3" "$SID_A" "$UB3/tick.jsonl"
expect_eq "UB.3 duties gate, bound-open (control): the same turn ends" "" "$(ub_decision)"

# ---- UB.4 fill gate ----------------------------------------------------------
UB4=$(new_repo "ub-fill"); UB4_P="$UB4/.bionic/docs/plans/epic-99/run.md"
mkdir -p "$(dirname "$UB4_P")"
{ printf -- '---\ngoverning-skill: superpowers:writing-plans\n'
  printf 'parallel-budget: writers=8 suites=2 worktrees=8 test_jobs=8 source=user\n'
  printf -- '---\n\n## SDLC State\n\ncurrent: 4\napproved-by: fixture 2026-10-04T00:00Z "approved"\n\n## Tasks\n\n'
  printf '| id | step | kind | task | agent | deps | size | serves | Files | status | worktree |\n'
  printf '|---|---|---|---|---|---|---|---|---|---|---|\n'
  printf '| T4 | 4 | build | landed | implementor | — | 15m | REQ-x | a.sh | landed | — |\n'
  printf '| T5 | 4 | build | ready | implementor | T4 | 15m | REQ-x | b.sh | pending | — |\n'
} > "$UB4_P"
rm -f "$UB4/.bionic/tmp/patrol-$SID_A.state"
roster_header > "$UB4/.bionic/tmp/roster-$SID_A.state"
jq -nc '{type:"user",uuid:"u-ub4",isSidechain:false,timestamp:"2026-10-02T19:40:00Z",message:{role:"user",content:"scope the next wave"}}' > "$UB4/turn.jsonl"
ub_mode "$UB4" "$SID_A" "$UB4_P" fallback
ub_stop "$UB4" "$SID_A" "$UB4/turn.jsonl"
expect_eq "UB.4 fill gate, fallback: no refusal for <p>'s ready row" "" "$(ub_decision)"
expect_eq "UB.4 …and T5 is named nowhere" "" "$(ub_names_id "$UB_OUT$UB_ERR" T5)"
ub_collect fill-gate "$UB_ERR" "$UB4_P"
ub_mode "$UB4" "$SID_A" "$UB4_P" bound
ub_stop "$UB4" "$SID_A" "$UB4/turn.jsonl"
expect_eq "UB.4 fill gate, bound-open (control): the same turn is refused" "block" "$(ub_decision)"
expect_contains "UB.4 …naming T5 as ready with room" "ready with room: T5" "$(ub_names_id "$UB_ERR" T5)"

# ---- UB.5 patrol-revive ------------------------------------------------------
UB5=$(new_repo "ub-revive"); UB5_P="$UB5/.bionic/docs/plans/epic-99/run.md"
s4_plan "$UB5_P" 4
printf 'poker-interval: 1s\n' > "$UB5/.bionic/config.yaml"
printf 'patrol-stamp/v1|at=2026-08-27T00:00:00Z|session=%s|verb=arm\n' "$SID_A" > "$UB5/.bionic/tmp/patrol-$SID_A.state"
touch -t "$(date -v-600S +%Y%m%d%H%M.%S 2>/dev/null || date -d '-600 seconds' +%Y%m%d%H%M.%S)" "$UB5/.bionic/tmp/patrol-$SID_A.state"
{ jq -nc --arg t "$(ub_iso 10000)" '{type:"assistant",timestamp:$t,message:{role:"assistant",content:[{type:"text",text:"working"}]}}'
  jq -nc --arg t "$(ub_iso 1)" '{type:"user",timestamp:$t,message:{role:"user",content:"carry on"}}'
} > "$UB5/idle.jsonl"
ub_mode "$UB5" "$SID_A" "$UB5_P" fallback
ub_stop "$UB5" "$SID_A" "$UB5/idle.jsonl"
expect_absent "UB.5 revive, fallback: a stale stamp revives nothing" "Patrol died" "$UB_OUT$UB_ERR"
expect_eq "UB.5 …no block at all" "" "$(ub_decision)"
ub_collect revive "$UB_ERR" "$UB5_P"
ub_mode "$UB5" "$SID_A" "$UB5_P" bound
ub_stop "$UB5" "$SID_A" "$UB5/idle.jsonl"
expect_contains "UB.5 revive, bound-open (control): the same stale stamp blocks" "Patrol died" "$UB_OUT"

# ---- UB.6 dispatch wall ------------------------------------------------------
UB6=$(new_repo "ub-dispatch"); UB6_P="$UB6/.bionic/docs/plans/epic-99/run.md"
s4_plan "$UB6_P" 4 1
s4_attest "$UB6" "$SID_A"
cg_live "$UB6/live.jsonl" "ub6a"
cg_roster_row "$UB6" "$SID_A" "ub6a" "aub6a-1111111111111111" "" "intended"
ub_dp() {  # <subagent_type> -> merged output
  mk_agent_payload "$SID_A" "$UB6" \
    | jq -c --arg t "$UB6/live.jsonl" --arg y "$1" '.transcript_path = $t | .tool_input.subagent_type = $y' \
    | env -u BIONIC_WALL_VERBOSE CLAUDE_CODE_SESSION_ID="$SID_A" bash "$PARTY_DP" 2>&1
  return 0
}
ub_mode "$UB6" "$SID_A" "$UB6_P" fallback
UB6_OUT=$(ub_dp implementor)
expect_contains "UB.6 dispatch wall, fallback: judged with no plan — the writer is refused with the bind instruction" \
  "dispatch refused — this session is bound to no run (bind it, or write its plan)" "$UB6_OUT"
expect_absent "UB.6 …and <p>'s budget is never read" "writers=1" "$UB6_OUT"
ub_collect dispatch-wall "$UB6_OUT" "$UB6_P"
expect_absent "UB.6 …while a read-only role is admitted, as before approval" "refused" "$(ub_dp bionic:researcher)"
ub_mode "$UB6" "$SID_A" "$UB6_P" bound
UB6_OUT=$(ub_dp implementor)
expect_contains "UB.6 dispatch wall, bound-open (control): refused by the run's writer budget" \
  "this passes the run's writer budget" "$UB6_OUT"
expect_absent "UB.6 …and never told to bind" "bound to no run" "$UB6_OUT"

# ---- UB.7 commit gate (Δ1) ---------------------------------------------------
UB7=$(new_repo "ub-commit"); UB7_P="$UB7/.bionic/docs/plans/epic-99/run.md"
write_plan "$UB7_P" "current: 5
Step 5: TODO"
ub_eg() {  # -> sets UB7_RC, UB7_OUT (merged)
  UB7_OUT=$(mk_bash_payload "$SID_A" "$SANDBOX/t.jsonl" "$UB7" 'git commit -m "x"' \
    | env -u CLAUDE_PROJECT_DIR -u BIONIC_WALL_VERBOSE HOME="$UB7" CLAUDE_CODE_SESSION_ID="$SID_A" \
        bash "$PARTY_EG" 2>&1); UB7_RC=$?
}
ub_mode "$UB7" "$SID_A" "$UB7_P" fallback
ub_eg
expect_eq "UB.7 commit gate, fallback: the commit is not judged against <p> — allowed" "0" "$UB7_RC"
expect_absent "UB.7 …and no refusal is rendered" "commit refused" "$UB7_OUT"
ub_collect commit-gate "$UB7_OUT" "$UB7_P"
ub_mode "$UB7" "$SID_A" "$UB7_P" bound
ub_eg
expect_eq "UB.7 commit gate, bound-open (control): refused, <p>'s step has no evidence" "2" "$UB7_RC"
expect_absent "UB.7 …and never told it is unbound" "session unbound" "$UB7_OUT"

# ---- UB.8 the Patrol tick (T11, review RC-1) ----------------------------------
# THE EIGHTH ARM, found by the Step-6 review: the poker's tick took `fallback <p>` as an open
# run and filled from <p>'s task table, naming another session's ready row for dispatch
# (`FILL T5`). AC-1.3 lists "prescribes a dispatch" as an acting arm. The tick under
# `fallback` decides as it does with no run: it prints the advisory once and fills nothing.
UB8=$(new_repo "ub-tick"); UB8_P="$UB8/.bionic/docs/plans/epic-99/run.md"
mkdir -p "$(dirname "$UB8_P")"
{ printf -- '---\ngoverning-skill: superpowers:writing-plans\n'
  printf 'parallel-budget: writers=8 suites=2 worktrees=8 test_jobs=8 source=user\n'
  printf -- '---\n\n## SDLC State\n\ncurrent: 4\napproved-by: fixture 2026-10-04T00:00Z "approved"\n\n## Tasks\n\n'
  printf '| id | step | kind | task | agent | deps | size | serves | Files | status | worktree |\n'
  printf '|---|---|---|---|---|---|---|---|---|---|---|\n'
  printf '| T4 | 4 | build | landed | implementor | — | 15m | REQ-x | a.sh | landed | — |\n'
  printf '| T5 | 4 | build | ready | implementor | T4 | 15m | REQ-x | b.sh | pending | — |\n'
} > "$UB8_P"
roster_header > "$UB8/.bionic/tmp/roster-$SID_A.state"
ub_tick() {  # <repo> <sid> -> merged output of the real tick
  ( cd "$1" && env -u CLAUDE_PROJECT_DIR HOME="$1" CLAUDE_CODE_SESSION_ID="$2" \
      BIONIC_PRESSURE_RING="$UB_RING" BIONIC_NOW_EPOCH=1700000000 \
      BIONIC_PROBE_FREE_MB=8192 BIONIC_PROBE_LOAD_1M=1.0 BIONIC_PROBE_FREE_PCT=80 BIONIC_PROBE_SWAP_PCT=0 \
      GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
      bash "$BIONIC_HOOKS_DIR/session-poker.sh" tick 2>&1 )
}
ub_mode "$UB8" "$SID_A" "$UB8_P" fallback
UB8_OUT=$(ub_tick "$UB8" "$SID_A")
# `no FILL — …` is the tick's own no-run sentence, so the absence is read on the two places a
# FILL is PRESCRIBED: the `poker: FILL <ids>` line and the decision line.
expect_absent "UB.8 tick, fallback: no FILL line is prescribed from <p>" "poker: FILL " "$UB8_OUT"
expect_absent "UB.8 …and the decision is not FILL" "decision=FILL" "$UB8_OUT"
expect_contains "UB.8 …it says it fills nothing, as a session with no run does" "no FILL — " "$UB8_OUT"
# THE ID IS READ AS A ROW, NOT AS LETTERS (wave-25 T15, then wave-26 T47). The tick prints paths:
# the plan's, under the sandbox, and its own in the re-arm note, under the tree this suite runs
# from. A tree at `.worktrees/25-T5` once turned this row red with no T5 printed as a task, and
# folding those two roots left every other path (a TMPDIR, a home) still able to; `ub_names_id`
# reads only an id the tick printed as a word of its own, on any line.
expect_eq "UB.8 …and <p>'s ready row T5 is named nowhere" "" "$(ub_names_id "$UB8_OUT" T5)"
UB8_ADV=$(printf '%s\n' "$UB8_OUT" | sed 's/^poker: //' | grep '^run resolved by newest-plan fallback' \
  | awk -v p="$UB8_P" '{ while ((i = index($0, p)) > 0) $0 = substr($0, 1, i-1) "<p>" substr($0, i+length(p)); print }')
expect_eq "UB.8 …and the advisory is printed exactly once" "1" "$(printf '%s' "$UB8_ADV" | grep -c . || true)"
expect_eq "UB.8 …and it is run_unbound_advisory's, byte for byte" "$UB_TEMPLATE" "$UB8_ADV"
ub_mode "$UB8" "$SID_A" "$UB8_P" bound
UB8_OUT=$(ub_tick "$UB8" "$SID_A")
expect_contains "UB.8 tick, bound-open (control): the same tick prescribes FILL" "FILL T5" "$(ub_names_id "$UB8_OUT" T5)"
expect_absent "UB.8 …and never says the session is unbound" "session unbound" "$UB8_OUT"

# ---- THE SEVEN SAY ONE THING -------------------------------------------------
# Byte-identical after the plan is folded to <p>, and equal to the template lib/run.sh builds
# — so an eighth hand-typed copy, or one arm's prefix, splits from the rest here.
expect_eq "UB.all seven arms announced (one advisory collected per arm)" "7" \
  "$(printf '%s\n' "$UB_ADVS" | grep -c '|')"
while IFS='|' read -r _ub_arm _ub_line; do
  [ -n "$_ub_arm" ] || continue
  expect_eq "UB.all $_ub_arm's advisory is run_unbound_advisory's, byte for byte" "$UB_TEMPLATE" "$_ub_line"
done <<UBEOF
$UB_ADVS
UBEOF
expect_eq "UB.all …so the seven are one string" "1" \
  "$(printf '%s\n' "$UB_ADVS" | cut -d'|' -f2- | sort -u | grep -c .)"


# ---- UB.9 the engagement door (wave-23 T13, critic C-3; D1 Δ4) -----------------
# The seed's own root shape, driven end to end: ONE open run, session A bound to it and LIVE
# (its pid file under the fixture claude home names A at this shell's pid, which `kill -0`
# answers for the whole run — `patrol_live_session_ids`, the sweeper's liveness). Session C
# invokes the skill through the real engage.sh and then stops through the real stop.sh.
# Before T13 the count rule bound C to A's run and C's Stop was refused `not launched: T5`
# at every turn end — the critic's reproduction, byte for byte. After it, C is written
# `plan=none`, told how to bind on the model's channel, and its Stop charges it nothing; A,
# on the same tree, is still refused (the control without which "no refusal" would pass on a
# fill gate that had simply gone dead).
SID_C="c3c3c3c3-0000-4000-8000-00000000000c"
UB9=$(new_repo "ub-engage"); UB9_P="$UB9/.bionic/docs/plans/epic-99/run.md"
mkdir -p "$(dirname "$UB9_P")"
{ printf -- '---\ngoverning-skill: superpowers:writing-plans\n'
  printf 'parallel-budget: writers=8 suites=2 worktrees=8 test_jobs=8 source=user\n'
  printf -- '---\n\n## SDLC State\n\ncurrent: 4\napproved-by: fixture 2026-10-04T00:00Z "approved"\n\n## Tasks\n\n'
  printf '| id | step | kind | task | agent | deps | size | serves | Files | status | worktree |\n'
  printf '|---|---|---|---|---|---|---|---|---|---|---|\n'
  printf '| T4 | 4 | build | landed | implementor | — | 15m | REQ-x | a.sh | landed | — |\n'
  printf '| T5 | 4 | build | ready | implementor | T4 | 15m | REQ-x | b.sh | pending | — |\n'
} > "$UB9_P"
bound_marker "$UB9" "$SID_A" "$UB9_P"
roster_header > "$UB9/.bionic/tmp/roster-$SID_A.state"
roster_header > "$UB9/.bionic/tmp/roster-$SID_C.state"
UB9_HOME="$SANDBOX/ub9-claude-home"; mkdir -p "$UB9_HOME/sessions"
printf '{"pid":%s,"sessionId":"%s","cwd":"%s"}\n' "$$" "$SID_A" "$UB9" > "$UB9_HOME/sessions/$$.json"
jq -nc '{type:"user",uuid:"u-ub9",isSidechain:false,timestamp:"2026-10-02T19:40:00Z",message:{role:"user",content:"scope the next wave"}}' > "$UB9/turn.jsonl"
UB9_ENG_OUT=$(jq -nc --arg s "$SID_C" --arg c "$UB9" \
    '{session_id:$s,transcript_path:"/dev/null",cwd:$c,hook_event_name:"PreToolUse",tool_name:"Skill",tool_input:{skill:"bionic:canonical-sdlc"},tool_use_id:"toolu_ub9"}' \
  | env -u CLAUDE_PROJECT_DIR HOME="$UB9" BIONIC_CLAUDE_HOME="$UB9_HOME" CLAUDE_CODE_SESSION_ID="$SID_C" \
      bash "$BIONIC_HOOKS_DIR/engage.sh" 2>/dev/null)
expect_eq "UB.9 engagement beside a LIVE session bound to the root's one run: C is written plan=none" \
  "plan=none" "$(grep -m1 '^plan=' "$UB9/.bionic/tmp/engaged-$SID_C.state" 2>/dev/null)"
expect_contains "UB.9 …and told on the model's channel, in run_unbound_advisory's words" \
  "$(printf '%s' "$UB_TEMPLATE" | sed "s|<p>|$UB9_P|g")" \
  "$(printf '%s' "$UB9_ENG_OUT" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)"
expect_eq "UB.9 …and A's binding is untouched" "plan=$UB9_P" \
  "$(grep -m1 '^plan=' "$UB9/.bionic/tmp/engaged-$SID_A.state" 2>/dev/null)"
ub_stop "$UB9" "$SID_C" "$UB9/turn.jsonl"
expect_eq "UB.9 C's turn end: no refusal" "" "$(ub_decision)"
expect_absent "UB.9 …and A's ready row is named nowhere" "ready with room: T5" "$UB_OUT$UB_ERR"
expect_eq "UB.9 …nor T5 at all" "" "$(ub_names_id "$UB_OUT$UB_ERR" T5)"
ub_stop "$UB9" "$SID_A" "$UB9/turn.jsonl"
expect_eq "UB.9 A's turn end on the same tree (control): refused" "block" "$(ub_decision)"
expect_contains "UB.9 …naming T5 as ready with room" "ready with room: T5" "$(ub_names_id "$UB_ERR$UB_OUT" T5)"

# ============================================================
section "SD — a standing fill decline: the tick's FILL and the stop wall's refusal name the same rows (wave-24 T27; REQ-4 AC-4.7; D2; Step-6 review C2/U1)"
# ============================================================
#
# The stop wall reads the session's latest declined fill-ledger line as the standing answer for
# the ready rows it saw, while `current:` is unchanged, and refuses a turn only for the rows it
# did not answer. The tick asks the same reader (`fill_standing_decline`) and leaves those rows
# out of its FILL. One fixture, both readers, the same question: which ready rows are owed? Two
# ready rows, R1 and R2, a ledger line answering R1. The tick must print `FILL R2`, and the wall
# must refuse a silent turn naming R2 alone. A second world whose line answers both: no FILL,
# and the turn ends. The mutation arm is a planted poker that never asks the reader.
sd_world() {  # <label> <ready ids the ledger line answered, comma-joined> -> repo
  local r
  r=$(new_repo "sd-$1")
  roster_header > "$r/.bionic/tmp/roster-$SID_A.state"
  cgc_plan "$r/.bionic/docs/plans/epic-99/sd.plan.md" \
    'parallel-budget: writers=8 suites=4 worktrees=32 test_jobs=8 source=user' 2
  s4_bind "$r" "$SID_A" "$r/.bionic/docs/plans/epic-99/sd.plan.md"
  s4_attest "$r" "$SID_A"
  mkdir -p "$r/.bionic/docs/record/sd"
  printf 'fill-ledger/v1|at=2026-10-03T09:00:00Z|session=%s|turn=u-sd-0|current=4|state=ok|ceiling=8|width=8|open=0|free=8|ready=%s|launched=|declined=R1 waits on the base merge|missed=2\n' \
    "$SID_A" "$2" > "$r/.bionic/docs/record/sd/fill-ledger.log"
  jq -nc '{type:"user",uuid:"u-sd-1",isSidechain:false,timestamp:"2026-10-03T09:05:00Z",message:{role:"user",content:"carry on"}}' \
    > "$r/sd-turn.jsonl"
  printf '%s' "$r"
}
# THE GATE'S ROOM IS THE FIXTURE'S (wave-37 T18; REQ-11 AC-11.4; D13). A decline stands only while the gate gives
# no room or no writer slot is free, so the worlds read the tick at room=no (SD_BUSY5=8.0: the five-minute busy
# cores over the share (the fixture shares 92%), session-poker.test.sh 11a) to see what a decline answers, and at room=yes to see it lapse.
# The wall passes the reader no room: it reads the lapse line the tick wrote, so after a tick the two agree.
sd_env() { env CLAUDE_CODE_SESSION_ID="$SID_A" CLAUDE_CONFIG_DIR="$SANDBOX/sd-no-config" BIONIC_PROBE_BUSY_CORES_5M="${SD_BUSY5:-1.0}" "${CGC_ENV[@]}" "$@"; }
sd_tick() {  # <repo> <poker> -> the ids the tick's FILL line names, sorted, space-joined
  cgc_ring
  ( cd "$1" && sd_env bash "$2" tick 2>&1 ) > "$1/sd-tick.out"
  sed -n 's/^poker: FILL \([A-Za-z0-9_. -]*\)$/\1/p' "$1/sd-tick.out" | head -1 | tr ' ' '\n' \
    | LC_ALL=C sort | tr '\n' ' '
}
sd_owed_noroom() {  # <repo> <poker> -> the ids the tick at room=no does NOT answer by the standing decline, sorted
  rm -f "$1/.bionic/tmp/tick-digest-$SID_A.state"   # a quiet tick prints only what changed since the last
  SD_BUSY5=8.0 sd_tick "$1" "$2" >/dev/null
  sed -n 's/^poker: WAIT \([A-Za-z0-9_.-]*\) — ready; no writer slot free.*$/\1/p' "$1/sd-tick.out" | LC_ALL=C sort | tr '\n' ' '
}
sd_wall() {  # <repo> -> the ids the stop wall refuses the turn for, sorted, space-joined
  cgc_ring
  s4_stop_payload "$1" "$SID_A" "$1/sd-turn.jsonl" | sd_env bash "$CGSD_STOP" 2>/dev/null \
    | jq -r '.reason // ""' 2>/dev/null \
    | /usr/bin/grep -o "session-poker\.sh'\{0,1\} decline [A-Za-z0-9_.,-]*" | head -1 \
    | sed 's/.* decline //' | tr ',' '\n' | LC_ALL=C sort | tr '\n' ' '
}
SD_R=$(sd_world some R1)
SD_OWED=$(sd_owed_noroom "$SD_R" "$CGSD_POKER")
expect_contains "SD precondition: the tick at room=no prints the standing decline" \
  "poker: fill-declined standing since 2026-10-03T09:00:00Z — R1 waits on the base merge" "$(cat "$SD_R/sd-tick.out")"
expect_eq "SD0 …and answers R1 by it, leaving R2, the row the decline did not see, to wait for a slot" "R2 " "$SD_OWED"
expect_eq "SD0b …and the stop wall refuses the silent turn for exactly that row" "$SD_OWED" "$(sd_wall "$SD_R")"
SD_TICK=$(sd_tick "$SD_R" "$CGSD_POKER")
expect_contains "SD1a AC-11.4 the tick at room=yes with a free slot records the lapse" \
  "poker: fill-declined lapsed — room=yes" "$(cat "$SD_R/sd-tick.out")"
expect_eq "SD1 …and fills both rows, the declined one asked again" "R1 R2 " "$SD_TICK"
expect_eq "SD2 …and the stop wall, reading the lapse the tick wrote, owes the same rows" "$SD_TICK" "$(sd_wall "$SD_R")"
SD_RA=$(sd_world all R1,R2)
expect_eq "SD3 a decline that answered both: the tick at room=no waits on neither for a slot" "" "$(sd_owed_noroom "$SD_RA" "$CGSD_POKER")"
expect_contains "SD3b …while it prints the decline as standing" "poker: fill-declined standing since " \
  "$(cat "$SD_RA/sd-tick.out")"
expect_eq "SD4 …and the stop wall owes nothing either" "" "$(sd_wall "$SD_RA")"
SD_TICK_A=$(sd_tick "$SD_RA" "$CGSD_POKER")
expect_eq "SD4b AC-11.4 …and at room=yes with a free slot the tick asks both again" "R1 R2 " "$SD_TICK_A"
expect_eq "SD4c …and the wall, reading the lapse, owes both" "$SD_TICK_A" "$(sd_wall "$SD_RA")"
# THE MUTATION ARM. A planted poker whose standing read and lapse are gone: it prints `FILL R1 R2` over the
# same fixture and records no lapse, so the wall still reads the decline standing and owes nothing, and the pin
# must go red.
SD_MUT="$SANDBOX/fx/sd-mut"
mkdir -p "$SD_MUT/hooks" "$SD_MUT/scripts"
ln -s "$CGC_LIBDIR" "$SD_MUT/scripts/lib"
for _sd_sib in "$BIONIC_HOOKS_DIR"/*; do
  [ "$(basename "$_sd_sib")" = session-poker.sh ] || ln -s "$_sd_sib" "$SD_MUT/hooks/$(basename "$_sd_sib")"
done
anchor file hooks/session-poker.sh 'SCHED_SD="$(fill_standing_decline '
anchor file hooks/session-poker.sh 'SCHED_LAPSE="$(fill_decline_lapsing '
sed -e 's/^\( *\)SCHED_SD="\$(fill_standing_decline .*$/\1SCHED_SD=""/' \
    -e 's/^\( *\)SCHED_LAPSE="\$(fill_decline_lapsing .*$/\1SCHED_LAPSE=""/' "$CGSD_POKER" > "$SD_MUT/hooks/session-poker.sh"
SD_RM=$(sd_world mut R1,R2)
SD_MUT_TICK=$(sd_tick "$SD_RM" "$SD_MUT/hooks/session-poker.sh")
expect_eq "SD5 mutation: the tick that never asks the reader fills both rows (it ran)" "R1 R2 " "$SD_MUT_TICK"
expect_ne "SD5b …and the agreement pin goes red on it" "$(sd_wall "$SD_RM")" "$SD_MUT_TICK"
# THE VERB'S TWIN ROWS (wave-27 T34; REQ-15 AC-15.1; D24). The same worlds with the decline recorded
# by `session-poker.sh decline` and no ledger line written by hand: the verb writes the line the
# reply form's turn leaves, so the tick and the wall read it by the one rule and owe the same rows.
sd_world_verb() {  # <label> <ids to decline, comma-joined> -> repo
  local r
  r=$(new_repo "sdv-$1")
  roster_header > "$r/.bionic/tmp/roster-$SID_A.state"
  cgc_plan "$r/.bionic/docs/plans/epic-99/sd.plan.md" \
    'parallel-budget: writers=8 suites=4 worktrees=32 test_jobs=8 source=user' 2
  s4_bind "$r" "$SID_A" "$r/.bionic/docs/plans/epic-99/sd.plan.md"
  s4_attest "$r" "$SID_A"
  ( cd "$r" && sd_env bash "$CGSD_POKER" decline "$2" 'R1 waits on the base merge' ) > "$r/sd-decline.out" 2>&1
  jq -nc '{type:"user",uuid:"u-sd-1",isSidechain:false,timestamp:"2026-10-03T09:05:00Z",message:{role:"user",content:"carry on"}}' \
    > "$r/sd-turn.jsonl"
  printf '%s' "$r"
}
SDV_R=$(sd_world_verb some R1)
expect_contains "SDV precondition: the verb recorded the decline" "decline — " "$(cat "$SDV_R/sd-decline.out")"
SDV_OWED=$(sd_owed_noroom "$SDV_R" "$CGSD_POKER")
expect_contains "SDV0 the tick at room=no prints the verb's decline as standing, in the reply form's words" \
  "— R1 waits on the base merge" "$(/usr/bin/grep '^poker: fill-declined standing since ' "$SDV_R/sd-tick.out")"
expect_eq "SDV1 …and leaves R2, the row the verb did not name, to wait for a slot" "R2 " "$SDV_OWED"
expect_eq "SDV2 …and the stop wall refuses the silent turn for exactly that row" "$SDV_OWED" "$(sd_wall "$SDV_R")"
SDV_RA=$(sd_world_verb all R1,R2)
expect_eq "SDV3 a verb decline naming both: the tick at room=no waits on neither for a slot" "" "$(sd_owed_noroom "$SDV_RA" "$CGSD_POKER")"
expect_eq "SDV4 …and the stop wall owes nothing either" "" "$(sd_wall "$SDV_RA")"
# THE LIFT (wave-35 T8; REQ-6 AC-6.2; D15). `decline lift [<ids>]` writes a ledger line of its own that ends
# the standing decline for the rows it names, every row it answered when it names none. The one reader stops
# at it, so the tick offers the rows the decline held and the wall owes the same rows. Read at room=no (a decline
# that finds room lapses by itself); the lift is the way a hold ends while the gate gives none.
( cd "$SDV_RA" && sd_env bash "$CGSD_POKER" decline lift R1 ) > "$SDV_RA/sd-lift.out" 2>&1
expect_contains "SDL precondition: the verb recorded the lift" "decline lift — R1" "$(cat "$SDV_RA/sd-lift.out")"
SDL_OWED=$(sd_owed_noroom "$SDV_RA" "$CGSD_POKER")
expect_eq "SDL1 after lifting R1 the tick no longer answers R1 by the decline, the row it held" "R1 " "$SDL_OWED"
expect_eq "SDL2 …and the stop wall refuses the silent turn for exactly that row" "$SDL_OWED" "$(sd_wall "$SDV_RA")"
( cd "$SDV_RA" && sd_env bash "$CGSD_POKER" decline lift ) > "$SDV_RA/sd-lift2.out" 2>&1
SDL_OWED2=$(sd_owed_noroom "$SDV_RA" "$CGSD_POKER")
expect_eq "SDL3 a lift naming no row ends the rest: the tick answers neither by it" "R1 R2 " "$SDL_OWED2"
expect_eq "SDL4 …and the stop wall owes both" "$SDL_OWED2" "$(sd_wall "$SDV_RA")"

# ============================================================
section "RPL — the hold's reply count and the sweeper's reply reader are one envelope grammar (wave-24 T27; Step-6 review U2; D3)"
# ============================================================
#
# Two hook processes read "the agent replied" off a transcript: `hold_reply_count` in
# session-poker.sh (the hold's fingerprint) and `transcript_events` in session-sweeper.sh (MET's
# completion signal). D3 says the first reuses the second's reply index; two processes share no
# memory, so each carries `def replies:` and this pins the two copies' grammar equal: the
# envelope scan and the idle-notice exclusion, the lines after `def replies:` up to the one that
# shapes each file's own output. The mutation arm doctors one copy and the pin must move.
rpl_grammar() {  # <file> -> the two grammar lines of its `def replies:`, trimmed
  awk '{ t = $0; sub(/^[ \t]+/, "", t) }
       t == "def replies:" { on = 1; n = 0; next }
       on && n < 3 { n++; if (t != "| .[]") print t }
       on && n == 3 { exit }' "$1"
}
RPL_PK="$(rpl_grammar "$CGSD_POKER")"
RPL_SW="$(rpl_grammar "$SWEEPER")"
expect_contains "RPL precondition: the poker's copy reads the envelope scan" "teammate-message teammate_id" "$RPL_PK"
expect_contains "RPL precondition: …and the idle-notice exclusion" "idle_notification" "$RPL_PK"
expect_eq "RPL the sweeper's reply grammar is the poker's, line for line" "$RPL_PK" "$RPL_SW"
RPL_MUT="$SANDBOX/fx/rpl-mut.sh"
anchor file hooks/session-poker.sh 'teammate-message teammate_id|agent-message from'
sed 's/teammate-message teammate_id|agent-message from/teammate-message teammate_id/' "$CGSD_POKER" > "$RPL_MUT"
RPL_MUT_G="$(rpl_grammar "$RPL_MUT")"
expect_contains "RPL2 mutation: the doctored copy still yields its grammar" "teammate-message teammate_id" "$RPL_MUT_G"
expect_ne "RPL2b …and the pin goes red on it" "$RPL_SW" "$RPL_MUT_G"

# ============================================================
section "MEMROOT — the two memory walls resolve one store root (wave-24 T27; Step-6 review U3; D16)"
# ============================================================
#
# The Bash half (bash-walls.sh, the collector for `wall_memory_store`) and the Write|Edit half
# (canonical-sdlc-governing-skill.sh) each resolve `${BIONIC_CLAUDE_HOME:-${CLAUDE_CONFIG_DIR:-
# $HOME/.claude}}` and expand `~`, `$HOME` and `${HOME}` spelled into the variable. Each hook's
# own §MEM drives it alone, so a change to one spelling in one hook went unseen. One engaged
# repo, one HOME, the same absolute path asked of both hooks under each root spelling: both
# refuse a store path, and both admit the default root's store while another root is named.
MR_R=$(new_repo memroot)
MR_H="$SANDBOX/memroot-home"; mkdir -p "$MR_H"
mr_bw() {  # <hook> <path> [env…] -> exit status
  local h="$1" p="$2"; shift 2
  mk_bash_payload "$SID_A" /dev/null "$MR_R" "touch $p" \
    | env -u CLAUDE_PROJECT_DIR HOME="$MR_H" CLAUDE_CODE_SESSION_ID="$SID_A" "$@" bash "$h" >/dev/null 2>&1
  printf '%s' "$?"
}
mr_gs() {  # <hook> <path> [env…] -> exit status
  local h="$1" p="$2"; shift 2
  jq -n --arg s "$SID_A" --arg c "$MR_R" --arg p "$p" \
    '{session_id:$s, cwd:$c, hook_event_name:"PreToolUse", tool_name:"Write", tool_input:{file_path:$p, content:"x"}}' \
    | env -u CLAUDE_PROJECT_DIR HOME="$MR_H" CLAUDE_CODE_SESSION_ID="$SID_A" "$@" bash "$h" >/dev/null 2>&1
  printf '%s' "$?"
}
# label | path asked | want (2 refused, 0 admitted) | BIONIC_CLAUDE_HOME | CLAUDE_CONFIG_DIR
MR_CASES="default|$MR_H/.claude/projects/-x/memory/a.md|2||
tilde|$MR_H/ccd/projects/-x/memory/a.md|2||~/ccd
dollar|$MR_H/ccd/projects/-x/memory/a.md|2||\$HOME/ccd
brace|$MR_H/ccd/projects/-x/memory/a.md|2||\${HOME}/ccd
slash|$MR_H/bch/projects/-x/memory/a.md|2|$MR_H/bch/|
precedence|$MR_H/bch/projects/-x/memory/a.md|2|$MR_H/bch|$MR_H/ccd
not-the-store|$MR_H/.claude/projects/-x/memory/a.md|0|$MR_H/bch|"
while IFS='|' read -r _mr_l _mr_p _mr_w _mr_b _mr_c; do
  [ -n "$_mr_l" ] || continue
  _mr_bw="$(mr_bw "$PARTY_EG" "$_mr_p" BIONIC_CLAUDE_HOME="$_mr_b" CLAUDE_CONFIG_DIR="$_mr_c")"
  _mr_gs="$(mr_gs "$PARTY_SG_W" "$_mr_p" BIONIC_CLAUDE_HOME="$_mr_b" CLAUDE_CONFIG_DIR="$_mr_c")"
  expect_eq "MEMROOT $_mr_l: bash-walls answers $_mr_w" "$_mr_w" "$_mr_bw"
  expect_eq "MEMROOT $_mr_l: …and governing-skill gives the same answer" "$_mr_bw" "$_mr_gs"
done <<MR_EOF
$MR_CASES
MR_EOF
# THE MUTATION ARM: a planted governing-skill whose `${HOME}` arm is gone. The two hooks must
# then disagree on the `brace` spelling, and agree again on `dollar`, which the arm does not touch.
MR_MUT_HOOKS="$(plant_hook_tree "$SANDBOX/fx/memroot-mut")"
anchor file hooks/canonical-sdlc-governing-skill.sh "'\${HOME}'|'\${HOME}/'*) GS_MEM_ROOT="
grep -vF "'\${HOME}'|'\${HOME}/'*) GS_MEM_ROOT=" "$PARTY_SG_W" > "$MR_MUT_HOOKS/canonical-sdlc-governing-skill.sh"
expect_eq "MEMROOT mutation: the doctored hook still refuses the dollar spelling (it runs)" "2" \
  "$(mr_gs "$MR_MUT_HOOKS/canonical-sdlc-governing-skill.sh" "$MR_H/ccd/projects/-x/memory/a.md" BIONIC_CLAUDE_HOME= 'CLAUDE_CONFIG_DIR=$HOME/ccd')"
expect_ne "MEMROOT mutation: …and on the brace spelling the agreement pin goes red" \
  "$(mr_bw "$PARTY_EG" "$MR_H/ccd/projects/-x/memory/a.md" BIONIC_CLAUDE_HOME= 'CLAUDE_CONFIG_DIR=${HOME}/ccd')" \
  "$(mr_gs "$MR_MUT_HOOKS/canonical-sdlc-governing-skill.sh" "$MR_H/ccd/projects/-x/memory/a.md" BIONIC_CLAUDE_HOME= 'CLAUDE_CONFIG_DIR=${HOME}/ccd')"

section "FACT — the proof line: one writer, every reader gives its kind, head and time back, and a reading its question (wave-26 T56 as §PRF; widened by wave-27 T2, REQ-2 AC-2.5)"
# THE ROW THE OWNERSHIP TABLE NAMED AND NOBODY WROTE. A proof line is written by one writer,
# proof.sh `proof_line` placed by `proof_add_line` (what `session-poker.sh proof-add` runs), and
# read by four readers: `proof_last` / `proof_last_line` (proof.sh), the readiness program's
# `proof_fields` (units.sh, seen here through `units_live_range`, which prints the last review
# proof's head), and two inline `at=` readers, the turn-end wall's (payload/scripts/lib/stop.sh)
# and the launch sync's (hooks/session-poker.sh). The last two are awk programs inside larger
# functions, so they are run here as the files carry them: each is cut out of its file by its
# own text (the needle below, anchored once in each), never by a line number.
#
# The fixture is written ONLY through the writer, then doctored around: three review proofs (a
# 1.11.0 line, then two readings, each carrying question, reader, result and scope), then a floor
# proof with the NEWEST time, so a reader blind to the kind answers the floor's time; a
# fenced proof line and one under another heading, each newer still, so a reader blind to the
# fence or the section answers theirs. Every reader must answer the last review line the writer
# wrote: kind review, its head, its time.
PRF_LIB="$BIONIC_HOOKS_DIR/../payload/scripts/lib"
PRF_STOP="$PRF_LIB/stop.sh"
PRF_POKER="$BIONIC_HOOKS_DIR/session-poker.sh"
PRF_NEEDLE='insdlc && /^proved:[ \t]/ && / kind=review( |$)/ && match($0, / at=[^ ]+/) {'
PRF_D="$SANDBOX/fx/prf"; mkdir -p "$PRF_D"
PRF_PLAN="$PRF_D/plan.md"
PRF_A=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
PRF_B=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
PRF_C=cccccccccccccccccccccccccccccccccccccccc
PRF_LIVE=dddddddddddddddddddddddddddddddddddddddd
PRF_E=eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
# prf_cut <file> — the single-quoted awk program whose text holds PRF_NEEDLE: from the `awk '`
# that opens it to the `' "$` that closes it. Nothing when either end is missing.
prf_cut() {
  PRF_N="$PRF_NEEDLE" awk -v q="'" '
    BEGIN { n = ENVIRON["PRF_N"] }
    { line[NR] = $0 }
    index($0, n) && !hit { hit = NR }
    END {
      if (!hit) exit 1
      for (s = hit; s > 0 && !index(line[s], "awk " q); s--) ;
      for (e = hit; e <= NR && !index(line[e], q " \"$"); e++) ;
      if (s < 1 || e > NR || s == e) exit 1
      t = line[s]; print substr(t, index(t, "awk " q) + 5)
      for (i = s + 1; i < e; i++) print line[i]
      t = line[e]; print substr(t, 1, index(t, q " \"$") - 1)
    }' "$1"
}
# prf_at <file> — that program run over the fixture; the first field of its first line is the
# time it answers (stop.sh prints the newest `at=`; the launch sync prints `at<TAB>evidence`,
# newest first, after its own `sort -r`).
prf_at() {
  local p; p="$(prf_cut "$1")" || return 0
  [ -n "$p" ] || return 0
  awk "$p" "$PRF_PLAN" 2>/dev/null | sort -r | head -n 1 | cut -f1
}
# THE WRITER, and nothing else, puts the proof lines in. The plan carries a units table so the
# readiness program has rows to run over (units_live_range prints nothing on an empty table).
{
  printf -- '---\nworking-branch: wave/prf\n---\n# prf fixture\n\n## SDLC State\n\ncurrent: 4\n'
  printf 'approved-by: fixture 2026-10-04T00:00Z "approved"\n\n## Tasks\n\n'
  printf '| id | step | kind | task | agent | deps | size | serves | Files | reads | status |\n'
  printf '|---|---|---|---|---|---|---|---|---|---|---|\n'
  printf '| T1 | 4 | build | landed work | implementor | — | 30 | REQ-x | lib/a.sh |  | landed |\n'
  printf '| T3 | 6 | review | follows the build | critic | — | 30 | REQ-x | .bionic/docs/record/w/review.md |  | pending |\n'
} > "$PRF_PLAN"
(
  # shellcheck source=/dev/null
  . "$PRF_LIB/proof.sh" || exit 1
  for _l in "$(proof_line review "$PRF_A" 2026-10-04T10:00:00Z record/w/r1.md)" \
            "$(proof_line review "$PRF_E" 2026-10-04T10:30:00Z record/w/adv.md adversarial w-crit flag whole)" \
            "$(proof_line review "$PRF_B" 2026-10-04T11:00:00Z record/w/r2.md evidence w-aud pass piece)" \
            "$(proof_line regression "$PRF_C" 2026-10-04T12:00:00Z record/w/floor.txt)"; do
    proof_add_line "$PRF_PLAN" "$_l" > "$PRF_PLAN.new" && mv "$PRF_PLAN.new" "$PRF_PLAN" || exit 1
  done
)
expect_eq "PRF fixture: the writer placed four proof lines inside ## SDLC State" "4" \
  "$(awk '/^## /{s=($0 ~ /SDLC State/)} s && /^proved: /' "$PRF_PLAN" | grep -c .)"
# The decoys, each newer than every real line: a fenced proof inside the section, and one under
# another heading. No reader may answer either.
awk '{ print } /^current: 4$/ { print "```"; print "proved: kind=review head=" h " at=2026-10-04T13:00:00Z evidence=record/w/fenced.md question=adversarial reader=w-crit result=pass scope=piece"; print "```" }' \
  h="$PRF_C" "$PRF_PLAN" > "$PRF_PLAN.new" && mv "$PRF_PLAN.new" "$PRF_PLAN"
printf '\n## Notes\n\nproved: kind=review head=%s at=2026-10-04T14:00:00Z evidence=record/w/elsewhere.md question=adversarial reader=w-crit result=pass scope=piece\n' "$PRF_C" >> "$PRF_PLAN"
expect_eq "PRF fixture: the two decoys are in (one fenced, one under ## Notes)" "2" \
  "$(grep -c 'evidence=record/w/\(fenced\|elsewhere\)\.md' "$PRF_PLAN")"
PRF_LINE="$(. "$PRF_LIB/proof.sh" && proof_last_line "$PRF_PLAN" review)"
expect_eq "PRF proof_last_line: the last review line, as the writer wrote it, its reading fields last" \
  "proved: kind=review head=$PRF_B at=2026-10-04T11:00:00Z evidence=record/w/r2.md question=evidence reader=w-aud result=pass scope=piece" "$PRF_LINE"
expect_eq "PRF proof_last (review): its head" "$PRF_B" \
  "$(. "$PRF_LIB/proof.sh" && proof_last "$PRF_PLAN" review)"
expect_eq "PRF proof_last (floor): the floor line is a different kind, with its own head" "$PRF_C" \
  "$(. "$PRF_LIB/proof.sh" && proof_last "$PRF_PLAN" floor)"
expect_eq "PRF units.sh (proof_fields, through units_live_range): the same review head" "${PRF_B}..${PRF_LIVE}" \
  "$(. "$PRF_LIB/units.sh" && UNITS_LIVE_HEAD="$PRF_LIVE" units_live_range "$PRF_PLAN")"
anchor file payload/scripts/lib/stop.sh 'insdlc && /^proved:[ \t]/ && / kind=review( |$)/ && match($0, / at=[^ ]+/) {'
anchor file hooks/session-poker.sh 'insdlc && /^proved:[ \t]/ && / kind=review( |$)/ && match($0, / at=[^ ]+/) {'
expect_nonempty "PRF the turn-end wall's at= reader is cut out of stop.sh by its text" "$(prf_cut "$PRF_STOP")"
expect_nonempty "PRF the launch sync's at= reader is cut out of session-poker.sh by its text" "$(prf_cut "$PRF_POKER")"
PRF_AT="${PRF_LINE##* at=}"; PRF_AT="${PRF_AT%% *}"
expect_eq "PRF stop.sh's at= reader: the time of the same review line" "$PRF_AT" "$(prf_at "$PRF_STOP")"
expect_eq "PRF session-poker.sh's at= reader: the time of the same review line" "$PRF_AT" "$(prf_at "$PRF_POKER")"
# THE DOCTORED SITE. A copy of stop.sh whose reader has lost its kind test (the drift a review
# reader most plausibly takes: "any proof's time") must answer the floor's time, and so turn the
# agreement above red. The copy still yields a program, so the difference is the reader's.
PRF_MUT="$PRF_D/stop.sh.mut"
PRF_MUT_TEXT='insdlc && /^proved:[ \t]/ && match($0, / at=[^ ]+/) {'
PRF_N="$PRF_NEEDLE" PRF_R="$PRF_MUT_TEXT" awk '
  BEGIN { n = ENVIRON["PRF_N"]; r = ENVIRON["PRF_R"] }
  { i = index($0, n); if (i) $0 = substr($0, 1, i - 1) r substr($0, i + length(n)); print }' "$PRF_STOP" > "$PRF_MUT"
expect_eq "PRF mutation: the doctored copy lost exactly the kind test" "0 1" \
  "$(grep -cF -- "$PRF_NEEDLE" "$PRF_MUT") $(grep -cF -- "$PRF_MUT_TEXT" "$PRF_MUT")"
PRF_NEEDLE_SAVED="$PRF_NEEDLE"; PRF_NEEDLE="$PRF_MUT_TEXT"
expect_nonempty "PRF mutation: …and still yields a reader that runs" "$(prf_at "$PRF_MUT")"
expect_ne "PRF mutation: …which answers another line's time, so the agreement row goes red" \
  "$PRF_AT" "$(prf_at "$PRF_MUT")"
PRF_NEEDLE="$PRF_NEEDLE_SAVED"

# §FACT (wave-27 T2; REQ-2 AC-2.5 verb half, D1). THE READING FIELDS RIDE THE SAME LINE. The
# writer above put an adversarial reading (head E) before the evidence reading (head B), so a
# reader keyed by kind alone answers B for every question. The one reading of a line,
# `proof_fields`, gives the four fields back as the writer wrote them; `proof_last` and
# `proof_last_line` keyed by a question answer that question's last line and nothing for a
# question never read; the decoys (fenced, under ## Notes, both adversarial and newer) stay unread.
expect_eq "FACT proof_fields: the evidence line's kind, head and four reading fields" \
  "review $PRF_B evidence w-aud pass piece" \
  "$(awk "$(. "$PRF_LIB/proof.sh" && proof_awk)"'
    proof_fields($0) && PROOF_HEAD == h { print PROOF_KIND, PROOF_HEAD, PROOF_QUESTION, PROOF_READER, PROOF_RESULT, PROOF_SCOPE }' \
    h="$PRF_B" "$PRF_PLAN")"
expect_eq "FACT proof_fields: …and a 1.11.0 line reads with its reading fields empty" "review|$PRF_A||||" \
  "$(awk "$(. "$PRF_LIB/proof.sh" && proof_awk)"'
    proof_fields($0) && PROOF_HEAD == h { print PROOF_KIND "|" PROOF_HEAD "|" PROOF_QUESTION "|" PROOF_READER "|" PROOF_RESULT "|" PROOF_SCOPE }' \
    h="$PRF_A" "$PRF_PLAN")"
expect_eq "FACT proof_last (review evidence): that question's head" "$PRF_B" \
  "$(. "$PRF_LIB/proof.sh" && proof_last "$PRF_PLAN" review evidence)"
expect_eq "FACT proof_last (review adversarial): its own head, not the newer evidence line's, nor a decoy's" "$PRF_E" \
  "$(. "$PRF_LIB/proof.sh" && proof_last "$PRF_PLAN" review adversarial)"
expect_eq "FACT proof_last_line (review adversarial): the line as the writer wrote it" \
  "proved: kind=review head=$PRF_E at=2026-10-04T10:30:00Z evidence=record/w/adv.md question=adversarial reader=w-crit result=flag scope=whole" \
  "$(. "$PRF_LIB/proof.sh" && proof_last_line "$PRF_PLAN" review adversarial)"
expect_eq "FACT proof_last (review structure): a question never read answers nothing" "" \
  "$(. "$PRF_LIB/proof.sh" && proof_last "$PRF_PLAN" review structure)"
# THE DOCTORED SITE. A copy of proof.sh whose last-proof reader has lost its question test (a
# reader keyed by kind alone, 1.11.0's) must answer the evidence head for the adversarial question.
FACT_NEEDLE='PROOF_KIND == k && (q == "" || PROOF_QUESTION == q)'
FACT_MUT_TEXT='PROOF_KIND == k'
FACT_MUT="$PRF_D/proof.sh.mut"
anchor file payload/scripts/lib/proof.sh 'PROOF_KIND == k && (q == "" || PROOF_QUESTION == q)'
FACT_N="$FACT_NEEDLE" FACT_R="$FACT_MUT_TEXT" awk '
  BEGIN { n = ENVIRON["FACT_N"]; r = ENVIRON["FACT_R"] }
  { i = index($0, n); if (i) $0 = substr($0, 1, i - 1) r substr($0, i + length(n)); print }' "$PRF_LIB/proof.sh" > "$FACT_MUT"
expect_eq "FACT mutation: the doctored copy lost exactly the question test" "0" \
  "$(grep -cF -- "$FACT_NEEDLE" "$FACT_MUT")"
expect_eq "FACT mutation: …and still reads the evidence question's head (it runs)" "$PRF_B" \
  "$(. "$FACT_MUT" && proof_last "$PRF_PLAN" review evidence)"
expect_ne "FACT mutation: …which answers the adversarial question with another line's head, so the agreement row goes red" \
  "$PRF_E" "$(. "$FACT_MUT" && proof_last "$PRF_PLAN" review adversarial)"

# §FACT-SEV (wave-28 T15; REQ-8 AC-8.3, D19, D20). THE PRIORITY TABLE HAS ONE DEFINITION, AND THE
# SCALE'S TEXT SAYS THE SAME. `PROOF_PRIORITY` in lib/proof.sh is the table every rating reads:
# `proof_priority` reads it cell by cell, and the findings parser (`proof_findings`) is handed it
# whole. Pinned here: the parser's priority column is `proof_priority`'s answer for each of the eight
# cells; the scale file the readers are pushed (`payload/context/severity.md`, row T16's) states the
# same eight cells in its table (a table row is a line opening with `|`: the scale's finding-line
# form also holds `|S2|`); and no other shipped file spells the table. A doctored copy of the
# scale with one cell flipped splits from the library.
FSEV_D="$PRF_D/sev"; mkdir -p "$FSEV_D"
FSEV_CELLS="S1:on S1:off S2:on S2:off S3:on S3:off S4:on S4:off"
fsev_lib() { . "$PRF_LIB/proof.sh" && proof_priority "$1" "$2"; }
fsev_parsed() {  # <S> <reach> -> the findings parser's priority column for a one-finding record
  printf 'reviewed: aaaaaaa..bbbbbbb\nfindings: 1\nfinding: 1 %s %s x.sh:1 a cell\nshown: 1 bash x.sh\n' "$1" "$2" > "$FSEV_D/rec.md"
  ( . "$PRF_LIB/proof.sh" && proof_findings "$FSEV_D/rec.md" ) | awk -F'\t' '{ print $5 }'
}
fsev_scale() {  # <scale file> <S> <reach> -> the cell the scale's table states, as fix, defer or note
  awk -v s="$2" -v r="$3" -F'|' '
    /^\|/ && $2 ~ /^[ \t]*S[1-4][ \t]*$/ { k = $2; gsub(/[ \t]/, "", k); if (k != s) next
      c = (r == "on" ? $3 : $4); gsub(/^[ \t]+|[ \t]+$/, "", c)
      if (c ~ /^fix/) print "fix"; else print c; exit }' "$1"
}
FSEV_SCALE="$BIONIC_HOOKS_DIR/../payload/context/severity.md"
expect_eq "FACT-SEV precondition: the scale file's table has a row for each of S1 to S4" "4" \
  "$(awk -F'|' '/^\|/ && $2 ~ /^[ \t]*S[1-4][ \t]*$/' "$FSEV_SCALE" 2>/dev/null | wc -l | tr -d ' ')"
for c in $FSEV_CELLS; do
  s="${c%%:*}"; r="${c#*:}"; want="$(fsev_lib "$s" "$r")"
  expect_regex "FACT-SEV $s $r: proof_priority answers one of fix, defer, note" '^(fix|defer|note)$' "$want"
  expect_eq "FACT-SEV $s $r: the findings parser rates it as proof_priority does" "$want" "$(fsev_parsed "$s" "$r")"
  expect_eq "FACT-SEV $s $r: the scale the readers are pushed states the same cell" "$want" "$(fsev_scale "$FSEV_SCALE" "$s" "$r")"
done
FSEV_TABLE='S1:on=fix S1:off=fix S2:on=fix'
expect_eq "FACT-SEV one definition: lib/proof.sh spells the table" "1" \
  "$(/usr/bin/grep -c "$FSEV_TABLE" "$PRF_LIB/proof.sh")"
expect_eq "FACT-SEV …and no other shipped hook or library does" "" \
  "$(/usr/bin/grep -rlF "S2:off=" "$BIONIC_HOOKS_DIR" "$PRF_LIB" 2>/dev/null | /usr/bin/grep -v '/proof\.sh$')"
# THE DOCTORED SCALE: S2 off flipped from defer to a fix splits from the library.
awk -F'|' 'BEGIN { OFS = "|" } $2 ~ /^[ \t]*S2[ \t]*$/ { $4 = " fix in the wave " } { print }' "$FSEV_SCALE" > "$FSEV_D/severity.mut.md" 2>/dev/null
expect_eq "FACT-SEV mutation: the doctored scale still reads (S1 on is fix)" "fix" "$(fsev_scale "$FSEV_D/severity.mut.md" S1 on)"
expect_ne "FACT-SEV mutation: …and its S2 off is no longer the library's, so the agreement row goes red" \
  "$(fsev_lib S2 off)" "$(fsev_scale "$FSEV_D/severity.mut.md" S2 off)"

# §FACT-FINAL (wave-31 T32; REQ-6 AC-6.3, D6; was §FACT-CHECK, wave-28 T41). A READER'S RATING IS
# FINAL, AND NO READER OF A STEP ASKS ABOUT A CHECK. Wave-28 T41 held the step on each open `check:`
# line through one reader, `proof_checks_open`, asked by the judge (`facts_state`) and by `current 8`.
# T32 deleted the reader and both of its callers. Pinned here: on a plan carrying open, settled, refuted
# and fenced `check:` lines, the judge answers each fact it owes and prints no `finding-check` line;
# the library defines no reader of checks; and `current 8`'s code names none.
FCHK_D="$PRF_D/fchk"; mkdir -p "$FCHK_D"
git -C "$FCHK_D" init -q 2>/dev/null; git -C "$FCHK_D" -c user.name=f -c user.email=f@x commit -q --allow-empty -m init 2>/dev/null
FCHK_H="$(git -C "$FCHK_D" rev-parse HEAD 2>/dev/null)"
{
  printf -- '---\nrigor: double\nscale: task\nbase-sha: %s\nworking-branch: main\n---\n# fact-check fixture\n\n## SDLC State\n\ncurrent: 7\n' "$FCHK_H"
  printf 'check: record/w/a.md#1 S3 off "open, no settlement"\n'
  printf 'check: record/w/a.md#2 S1 on "settled" settled=S2:off by=record/w/c.md\n'
  printf 'check: record/w/a.md#3 S2 on "refuted" refuted by=record/w/c.md\n'
  printf '\n```\ncheck: record/w/a.md#5 S1 on "fenced"\n```\n'
} > "$FCHK_D/plan.md"
FCHK_OUT="$(bash -c '. "$1" && facts_state "$2" "$3"' _ "$PRF_LIB/proof.sh" "$FCHK_D/plan.md" "$FCHK_H" 2>/dev/null)"
expect_regex "FACT-FINAL precondition: the fixture repository has a head" '^[0-9a-f]{40}$' "$FCHK_H"
expect_contains "FACT-FINAL the judge answers the facts the plan owes (the extractor reads real output: the floor line)" \
  "regression" "$FCHK_OUT"
expect_absent "FACT-FINAL …and holds no check, open or not: no finding-check line" "finding-check" "$FCHK_OUT"
expect_eq "FACT-FINAL the library defines the judge, and no reader of checks (proof_checks_open, _proof_check_state)" "1|0|0" \
  "$(bash -c '. "$1"; declare -F facts_state >/dev/null && printf 1 || printf 0; printf "|"; declare -F proof_checks_open >/dev/null && printf 1 || printf 0; printf "|"; declare -F _proof_check_state >/dev/null && printf 1 || printf 0' _ "$PRF_LIB/proof.sh" 2>/dev/null)"
expect_eq "FACT-FINAL current 7 and 8 ask the judge, cur7_judge, named for the first step it judges (the extractor reads the verb's file)…" "1" \
  "$(/usr/bin/grep -c '^cur7_judge() {' "$PRF_POKER")"
expect_eq "FACT-FINAL …and no reader of checks, by name" "0" \
  "$(/usr/bin/grep -c 'proof_checks_open\|cur8_checks' "$PRF_POKER")"

# ============================================================
section "DEAL — the dealing: at every rigor each reading question has exactly one role, and the roles are the reader roles (wave-27 T9; REQ-1 AC-1.2; D2, D6)"
# ============================================================
# ONE FUNCTION SAYS WHAT A RUN OWES. proof.sh `facts_owed <rigor> <scale>` prints the floor and one
# `review<TAB><question><TAB><role><TAB><scope>` line per owed reading; the judge (`facts_state`)
# and, from row T15, the dispatch wall both read it, so the dealing has one site. Pinned here: at
# each rigor and scale each question is dealt to exactly one role; the table is REQ-1's (wave-30
# T11, D1: `single` the critic holds all three; `double` the auditor evidence and the critic the
# other two), and no third level exists; every dealt role is one of PROOF_READER_ROLES, the set
# the fact verb admits a reader under, and every such role is
# dealt somewhere; at wave scale each code question owes a whole read by the same role. The six
# words before 1.14.0 deal nothing. A doctored copy whose `double` dealing hands evidence to the
# critic must split from the table.
DEAL_LIB="$BIONIC_HOOKS_DIR/../payload/scripts/lib/proof.sh"
deal() {  # <rigor> <scale> [<proof.sh>] -> facts_owed's lines
  bash -c '. "$1" && facts_owed "$2" "$3"' _ "${3:-$DEAL_LIB}" "$1" "$2" 2>/dev/null
}
deal_roles() {  # <rigor> <scale> [<proof.sh>] -> `<question>=<role>` per piece read, in table order
  deal "$@" | awk -F'\t' '$1 == "review" && $4 == "piece" { printf "%s%s=%s", (n++ ? " " : ""), $2, $3 }'
}
DEAL_QS="$(bash -c '. "$1" && printf "%s" "$PROOF_QUESTIONS"' _ "$DEAL_LIB")"
DEAL_ROLES="$(bash -c '. "$1" && printf "%s" "$PROOF_READER_ROLES"' _ "$DEAL_LIB")"
expect_eq "DEAL precondition: the questions are the Interfaces table's three" "evidence adversarial structure" "$DEAL_QS"
for deal_r in single double; do
  for deal_s in task wave; do
    for deal_q in $DEAL_QS; do
      expect_eq "DEAL $deal_r $deal_s: $deal_q is dealt to exactly one role" "1" \
        "$(deal "$deal_r" "$deal_s" | awk -F'\t' -v q="$deal_q" '$1 == "review" && $2 == q && $4 == "piece"' | awk 'END { print NR }')"
    done
    expect_eq "DEAL $deal_r $deal_s: the floor is owed, once" "1" "$(deal "$deal_r" "$deal_s" | /usr/bin/grep -cx regression)"
    expect_eq "DEAL $deal_r $deal_s: every dealt role is a reader role the fact verb admits" "" \
      "$(deal "$deal_r" "$deal_s" | ROLES="$DEAL_ROLES" awk -F'\t' '$1 == "review" && index(" " ENVIRON["ROLES"] " ", " " $3 " ") == 0 { print $3 }')"
  done
done
expect_eq "DEAL single: the critic holds all three" \
  "evidence=bionic:critic adversarial=bionic:critic structure=bionic:critic" "$(deal_roles single task)"
expect_eq "DEAL double: the auditor evidence, the critic adversarial and structure" \
  "evidence=bionic:auditor adversarial=bionic:critic structure=bionic:critic" "$(deal_roles double task)"
expect_eq "DEAL the two levels deal the auditor and the critic, and no third role" "bionic:auditor bionic:critic" \
  "$(for deal_r in single double; do deal "$deal_r" task; done | awk -F'\t' '$1 == "review" { print $3 }' | sort -u | tr '\n' ' ' | sed 's/ $//')"
# §RIGOR: THE SIX WORDS BEFORE 1.14.0 ARE NO LEVEL, so each deals nothing and says so by its exit.
for deal_old in low tested medium peer-reviewed high audited; do
  expect_eq "DEAL §RIGOR $deal_old (a word before 1.14.0) deals nothing" "" "$(deal "$deal_old" task)"
  expect_ne "DEAL §RIGOR …and says so by its exit" "0" \
    "$(bash -c '. "$1" && facts_owed "$2" task >/dev/null 2>&1; echo $?' _ "$DEAL_LIB" "$deal_old")"
done
for deal_r in single double; do
  expect_eq "DEAL $deal_r: the dealing does not change with scale" "$(deal_roles "$deal_r" task)" "$(deal_roles "$deal_r" wave)"
  expect_eq "DEAL $deal_r wave: each code question owes one whole read, by its piece reader; evidence none" \
    "$(deal_roles "$deal_r" wave | tr ' ' '\n' | /usr/bin/grep -v '^evidence=' | tr '\n' ' ' | sed 's/ $//')" \
    "$(deal "$deal_r" wave | awk -F'\t' '$1 == "review" && $4 == "whole" { printf "%s%s=%s", (n++ ? " " : ""), $2, $3 }')"
  expect_eq "DEAL $deal_r task: no whole read is owed" "0" "$(deal "$deal_r" task | /usr/bin/grep -c 'whole$')"
done
expect_eq "DEAL every reader role is dealt a question at some rigor (the reviewer is retired, wave-30 T20)" \
  "$(printf '%s\n' $DEAL_ROLES | sort | tr '\n' ' ' | sed 's/ $//')" \
  "$(for deal_r in single double; do deal "$deal_r" task; done | awk -F'\t' '$1 == "review" { print $3 }' | sort -u | tr '\n' ' ' | sed 's/ $//')"
# THE READER ROLES ARE READ-ONLY ROLES (wave-27 T45; review pass 13 F8). PROOF_READER_ROLES is the
# set the fact verb admits a reader under; roster.sh's ROLE_READONLY_SET is the set the walls run
# as readers. A reader role outside it would be dealt a question and walled as a writer, so every
# member of the first is a member of the second. A doctored roster.sh without bionic:critic splits.
DEAL_ROSTER="$BIONIC_HOOKS_DIR/../payload/scripts/lib/roster.sh"
deal_outside() {  # <roster.sh> -> each reader role its ROLE_READONLY_SET lacks, one per line
  RO="$(bash -c '. "$1" >/dev/null 2>&1; printf "%s" "$ROLE_READONLY_SET"' _ "$1")" ROLES="$DEAL_ROLES" awk 'BEGIN {
    n = split(ENVIRON["ROLES"], r, " "); for (i = 1; i <= n; i++) if (index(" " ENVIRON["RO"] " ", " " r[i] " ") == 0) print r[i] }'
}
expect_ne "DEAL roles precondition: roster.sh's read-only set is read" "" \
  "$(bash -c '. "$1" >/dev/null 2>&1; printf "%s" "$ROLE_READONLY_SET"' _ "$DEAL_ROSTER")"
expect_eq "DEAL every reader role (PROOF_READER_ROLES) is inside roster.sh's read-only set" "" "$(deal_outside "$DEAL_ROSTER")"
DEAL_RO_MUT="$SANDBOX/fx/deal-roster.sh.mut"; mkdir -p "$SANDBOX/fx"
anchor file payload/scripts/lib/roster.sh 'bionic:auditor bionic:critic Explore'
sed 's/bionic:auditor bionic:critic Explore/bionic:auditor Explore/' "$DEAL_ROSTER" > "$DEAL_RO_MUT"
expect_eq "DEAL roles mutation: a roster.sh whose read-only set lacks bionic:critic splits from the reader roles" \
  "bionic:critic" "$(deal_outside "$DEAL_RO_MUT")"
expect_eq "DEAL a rigor outside the two deals nothing" "" "$(deal standard task)"
expect_ne "DEAL …and says so by its exit" "0" "$(bash -c '. "$1" && facts_owed standard task >/dev/null 2>&1; echo $?' _ "$DEAL_LIB")"
# THE DOCTORED SITE: a copy whose double dealing gives evidence to the critic.
DEAL_NEEDLE='double=bionic:auditor,bionic:critic,bionic:critic'
DEAL_MUT="$SANDBOX/fx/deal-proof.sh.mut"; mkdir -p "$SANDBOX/fx"
anchor file payload/scripts/lib/proof.sh 'double=bionic:auditor,bionic:critic,bionic:critic'
DEAL_N="$DEAL_NEEDLE" awk '
  BEGIN { n = ENVIRON["DEAL_N"]; r = "double=bionic:critic,bionic:critic,bionic:critic" }
  { i = index($0, n); if (i) $0 = substr($0, 1, i - 1) r substr($0, i + length(n)); print }' "$DEAL_LIB" > "$DEAL_MUT"
expect_eq "DEAL mutation: the doctored copy still deals one role per question (it runs)" "3" \
  "$(deal double task "$DEAL_MUT" | awk -F'\t' '$1 == "review"' | awk 'END { print NR }')"
expect_ne "DEAL mutation: …and splits from the table, so the double row goes red" \
  "evidence=bionic:auditor adversarial=bionic:critic structure=bionic:critic" "$(deal_roles double task "$DEAL_MUT")"

# ============================================================
section "NM — the stamp names a suite FILE exactly when the budget counts it as this tree's (wave-26 T63; critic K4-N2)"
# ============================================================
#
# TWO READERS OF ONE CLAIM. The dispatch budget counts a suite file by `cmd_suite_claims` (its
# file half, `cmd_suite_targets`), scoped to a repository root: a claim counts only when its path
# is that root's own `tests/<basename>`. The Bash wall names the suites a run stamps
# (`_bsg_suites`, payload/scripts/lib/walls.sh) from the same reading. Before T63 the wall named
# every file claim by its basename, so `bash other/a.test.sh` stamped `a.test.sh` while the
# budget would not count it at all, and its green cleared tests/a.test.sh's red. Both readers
# now ask cmd_claim_scope. Pinned here, for each command: a claim's basename is among the
# stamp's names exactly when the budget, rooted where the stamp goes, counts that file; and a
# runner the budget keys by its run is stamped under that run's text, each character outside
# the name set turned into `_`. The stamp side is the real hook's wrap; the budget side is the
# library. A doctored copy of the wall that names every file by its basename again must split
# the two.
NM_D="$SANDBOX/fx/nm"; NM_R="$NM_D/repo"; NM_SID="nmsuite0-0000-0000-0000-000000000000"
mkdir -p "$NM_R/.bionic/tmp" "$NM_R/tests" "$NM_R/other" "$NM_D/home"
git -C "$NM_R" init -q 2>/dev/null
: > "$NM_R/.bionic/tmp/engaged-${NM_SID}.state"
NM_LIB="$BIONIC_HOOKS_DIR/../payload/scripts/lib"
[ -r "$NM_LIB/cmd-class.sh" ] || NM_LIB="$BIONIC_HOOKS_DIR/../scripts/lib"
nm_names() {  # <hook> <command> -> the --suites value the wall hands the shim, unquoted; "" when not wrapped
  local w
  w="$(jq -nc --arg s "$NM_SID" --arg c "$NM_R" --arg cmd "$2" \
    '{session_id:$s, transcript_path:"/irrelevant.jsonl", cwd:$c, permission_mode:"bypassPermissions",
      hook_event_name:"PreToolUse", tool_name:"Bash", tool_input:{command:$cmd, timeout:600000},
      tool_use_id:"toolu_nm", agent_id:"anmsuite-0123456789abcdef", agent_type:"test-runner"}' |
    env HOME="$NM_D/home" CLAUDE_CONFIG_DIR="$NM_D/home/.claude" CLAUDE_CODE_SESSION_ID="$NM_SID" \
      CLAUDE_PROJECT_DIR= BIONIC_PLUGINS_DIR="$NM_D/no-plugins" SHELL=/bin/bash CLAUDE_CODE_SHELL= \
      bash "$1" 2>/dev/null | jq -r '.hookSpecificOutput.updatedInput.command // ""' 2>/dev/null)"
  case "$w" in *' --suites '*) : ;; *) return 0 ;; esac
  w="${w#* --suites }"; w="${w%% -- *}"; w="${w#\'}"; w="${w%\'}"
  printf '%s' "$w"
}
nm_agree() {  # <hook> <command> -> `agree`, or `split <claim>` naming the first claim the two readers part on
  local n f k b r p
  n=",$(nm_names "$1" "$2"),"
  f="$(bash -c '. "$1" || exit 9; cmd_suite_targets "$2" "$3"' _ "$NM_LIB/cmd-class.sh" "$2" "$NM_R" 2>/dev/null)"
  while IFS=$'\t' read -r k b r; do
    [ -n "$k" ] || continue
    if [ "$k" = file ]; then
      case "$n" in *",$b,"*) p=1 ;; *) p=0 ;; esac
      if printf '%s\n' "$f" | grep -qxF -- "$b"; then
        [ "$p" = 1 ] || { printf 'split %s' "$b"; return 0; }
      else
        [ "$p" = 0 ] || { printf 'split %s' "$b"; return 0; }
      fi
    else
      case "$n" in *",${r//[!A-Za-z0-9._+-]/_},"*) : ;; *) printf 'split %s' "$r"; return 0 ;; esac
    fi
  done <<< "$(bash -c '. "$1" || exit 9; cmd_suite_claims "$2"' _ "$NM_LIB/cmd-class.sh" "$2" 2>/dev/null)"
  printf 'agree'
}
NM_HOOK="$BIONIC_HOOKS_DIR/bash-walls.sh"
NM_OTHER='bash other/a.test.sh'
expect_eq "NM fixture: the real wall wraps a suite and names it (the extractor reads a name)" \
  "a.test.sh" "$(nm_names "$NM_HOOK" 'bash tests/a.test.sh')"
expect_eq "NM fixture: the budget does not count other/a.test.sh as this tree's suite" "" \
  "$(bash -c '. "$1" || exit 9; cmd_suite_targets "$2" "$3"' _ "$NM_LIB/cmd-class.sh" "$NM_OTHER" "$NM_R" 2>&1)"
expect_eq "NM fixture: …while it counts tests/a.test.sh" "a.test.sh" \
  "$(bash -c '. "$1" || exit 9; cmd_suite_targets "$2" "$3"' _ "$NM_LIB/cmd-class.sh" 'bash tests/a.test.sh' "$NM_R" 2>&1)"
for _c in 'bash tests/a.test.sh' 'bash ./tests/a.test.sh' "bash $NM_R/tests/a.test.sh" \
          "$NM_OTHER" 'bash ../x/tests/a.test.sh' 'bash /elsewhere/tests/a.test.sh' \
          'bash tests/a.test.sh && bash other/b.test.sh' 'npm test && bash tests/a.test.sh' \
          'pytest -q' 'set -o pipefail; bash tests/a.test.sh 2>&1 | tee "$L"; rc=$?; exit $rc'; do
  expect_eq "NM [$_c] the stamp's names and the budget agree" "agree" "$(nm_agree "$NM_HOOK" "$_c")"
done
# THE DOCTORED SITE: a copy of the wall whose naming skips the scoping rule, naming every file
# claim by its basename (the projection before T63). It must still wrap, and it must part from
# the budget on the file the budget does not count.
NM_MUT="$NM_D/mut"
mkdir -p "$NM_MUT/hooks" "$NM_MUT/scripts/lib"
cp "$BIONIC_HOOKS_DIR"/*.sh "$NM_MUT/hooks/" 2>/dev/null
cp "$NM_LIB"/*.sh "$NM_MUT/scripts/lib/" 2>/dev/null
cp "$NM_LIB/../booked.sh" "$NM_MUT/scripts/booked.sh" 2>/dev/null
# The line as wave-28 T36 spells it (a door claim, kind `only`, is scoped like a file claim).
NM_NEEDLE='if { [ "$_k" != file ] && [ "$_k" != only ]; } || ! cmd_claim_scope "$_root" "$_b" "$_p"; then'
anchor file payload/scripts/lib/walls.sh 'if { [ "$_k" != file ] && [ "$_k" != only ]; } || ! cmd_claim_scope "$_root" "$_b" "$_p"; then'
NM_N="$NM_NEEDLE" awk '
  BEGIN { n = ENVIRON["NM_N"]; r = "if [ \"$_k\" != file ] && [ \"$_k\" != only ]; then" }
  { i = index($0, n); if (i) $0 = substr($0, 1, i - 1) r substr($0, i + length(n)); print }' \
  "$NM_LIB/walls.sh" > "$NM_MUT/scripts/lib/walls.sh"
expect_eq "NM mutation: the doctored copy lost exactly the scoping call" "0 1" \
  "$(grep -cF -- "$NM_NEEDLE" "$NM_MUT/scripts/lib/walls.sh") $(grep -cF -- 'if [ "$_k" != file ] && [ "$_k" != only ]; then' "$NM_MUT/scripts/lib/walls.sh")"
expect_eq "NM mutation: …and its wall still wraps and names a suite" "a.test.sh" \
  "$(nm_names "$NM_MUT/hooks/bash-walls.sh" 'bash tests/a.test.sh')"
expect_eq "NM mutation: …which names other/a.test.sh by its basename, so the agreement goes red" \
  "split a.test.sh" "$(nm_agree "$NM_MUT/hooks/bash-walls.sh" "$NM_OTHER")"


# ============================================================
section "RIGOR — two levels, single and double: the plan-write hook and every wall site give each its answer, and judge the six words before 1.14.0 as any other bad value (wave-28 T44; wave-30 T11: REQ-1 AC-1.4, D1)"
# ============================================================
# ONE FUNCTION SAYS WHAT A RIGOR WORD MEANS. lib/run.sh `rigor_level <word>` prints `single` or
# `double` for that word and returns 1 for any other. Every site that tests the word calls it: the
# plan-write hook's closed set and its floor rank (`rigor_rank`), and in lib/walls.sh the auditor
# relaxation (`matrix_auditor_required`) and each arm that asks for the double level
# (`validate_requirements_pointer`, `validate_dispatch_ledger`, `plan_bring_forward`). The task
# row's rigor cell check, the wall's floor rank and the ledger-shape router were sites too; they
# went with the retired task table (wave-31 T24; D2, A-T24-2). Pinned here: every site gives each
# level its answer; each of the six words before 1.14.0 (low/tested, medium/peer-reviewed,
# high/audited) gets exactly the answer a word that is no level gets — the closed sets refuse it,
# the auditor arm stays closed, and no double arm fires on it. A census holds the site count at zero (no line in hooks/ or payload/scripts/ tests
# an old word itself), and a doctored walls.sh whose auditor arm tests `low` directly reads an old
# word as a level, so the old-word rows go red on it.
RV_LIB="${BIONIC_SCRIPTS_DIR}/payload/scripts/lib"
RV_HOOK="$BIONIC_HOOKS_DIR/canonical-sdlc-governing-skill.sh"
RV_D="$SANDBOX/rigor"; mkdir -p "$RV_D"
RV_SID="7a6b5c4d-3e2f-4a1b-9c8d-7e6f5a4b3c2d"
rv_level() {  # <word> -> `<level> rc=<n>`, rigor_level's answer
  bash -c '. "$1/run.sh" >/dev/null 2>&1; out="$(rigor_level "$2")"; printf "%s rc=%s" "$out" "$?"' _ "$RV_LIB" "$1" 2>/dev/null
}
# A wave plan at the word, multi_agent, at current 4 with a pre-14 `## Tasks` table and none of the
# version-14 keys: `plan_bring_forward` fires on it at double and admits it otherwise. A plan with no `## Tasks` section: the
# dispatch ledger refuses it at double and passes it otherwise.
rv_bf_plan() {
  printf -- '---\nrigor: %s\nscale: wave\nmulti_agent: true\n---\n\n## SDLC State\ncurrent: 4\n\n## Tasks\n\n' "$1"
  printf -- '| id | task | status |\n|---|---|---|\n| T1 | a | pending |\n'
}
printf -- '---\nrigor: double\n---\n\n## SDLC State\ncurrent: 3\n' > "$RV_D/no-tasks.plan.md"
# THE GATE'S HELPERS ARE DEFINED INSIDE ITS BODY (`_eg_body`), so sourcing walls.sh defines none of
# them: each is lifted out by its own definition, flush-left from `name() {` to its `}`, and a row
# below holds every one of them defined, so no answer here is a missing function's silence.
RV_FNS="matrix_auditor_required validate_requirements_pointer step1_evidence_block evidence_line_field extract_continuation resolve_requirements_path validate_dispatch_ledger"
export RV_FNS
rv_site() {  # <walls.sh> <word> <site> -> that wall site's answer at the word
  rv_bf_plan "$2" > "$RV_D/bf-$2.plan.md"
  bash -c '
    . "$1/refuse.sh" >/dev/null 2>&1; . "$1/fold.sh" >/dev/null 2>&1
    . "$1/run.sh" >/dev/null 2>&1;    . "$1/units.sh" >/dev/null 2>&1
    . "$2" >/dev/null 2>&1
    for fn in $RV_FNS; do
      eval "$(awk -v n="$fn" '"'"'$0 ~ "^" n "\\(\\) *\\{" { f = 1 } f { print } f && /^}$/ { exit }'"'"' "$2")"
    done
    refuse() { echo refused; exit 2; }; log_finding() { echo logged; }
    RIGOR="$3"; SCALE=wave; MULTI_AGENT=true; CURRENT=3; SECTION=""; PLAN="$5"
    case "$4" in
      auditor)  if matrix_auditor_required; then echo owed; else echo relaxed; fi ;;
      pointer)  validate_requirements_pointer; echo passed ;;
      dispatch) validate_dispatch_ledger; echo passed ;;
      forward)  if plan_bring_forward "$6" >/dev/null 2>&1; then echo admitted; else echo fired; fi ;;
      defined)  for fn in $RV_FNS plan_bring_forward; do declare -F "$fn" >/dev/null || echo "missing $fn"; done; echo defined ;;
    esac' _ "$RV_LIB" "$1" "$2" "$3" "$RV_D/no-tasks.plan.md" "$RV_D/bf-$2.plan.md" 2>/dev/null
}
rv_rank() {  # <word> -> the plan-write hook's own `rigor_rank` of the word
  bash -c '. "$1/run.sh" >/dev/null 2>&1
    eval "$(awk '"'"'index($0, "rigor_rank() {") == 1 { f = 1 } f { print } f && /^}$/ { exit }'"'"' "$2")"
    rigor_rank "$3"' \
    _ "$RV_LIB" "$RV_HOOK" "$1" 2>/dev/null
}
# The hook's closed set, on the hook itself: a spec whose frontmatter carries the word is either
# refused on its rigor or carried past that check (to whatever the fixture lacks next).
RV_PROJ="$RV_D/proj"; mkdir -p "$RV_PROJ/.bionic/docs/specs/epic-01-demo" "$RV_PROJ/.bionic/tmp"
git -C "$RV_PROJ" init -q . 2>/dev/null
: > "$RV_PROJ/.bionic/tmp/engaged-$RV_SID.state"
rv_closed() {  # <word> -> `refused` when the hook refuses the word as a rigor, else `admitted`
  local c in err
  c="$(printf -- '---\ngoverning-skill: superpowers:brainstorming\nsdlc-step: 2\nepic: epic-01-demo\nwave: wave-01-x\ncanonical_sdlc_version: 14\nintent: build\nrigor: %s\nscale: wave\n---\n\n## Goal\n\nA spec.\n' "$1")"
  in="$(jq -n --arg p "$RV_PROJ/.bionic/docs/specs/epic-01-demo/x.spec.md" --arg c "$c" --arg s "$RV_SID" \
    '{session_id: $s, tool_name: "Write", tool_input: {file_path: $p, content: $c}}')"
  err="$(HOME="$RV_D" CLAUDE_CODE_SESSION_ID="$RV_SID" bash "$RV_HOOK" <<< "$in" 2>&1 >/dev/null)"
  case "$err" in *"that rigor is not single or double"*) echo refused ;; *) echo admitted ;; esac
}
RV_WALLS="$RV_LIB/walls.sh"
expect_eq "RIGOR precondition: every wall site this section asks is defined from walls.sh" "defined" \
  "$(rv_site "$RV_WALLS" double defined)"
# <word>:<rigor_level's answer>:<closed set>:<rank>:<auditor>:<arm>:<forward>
for rv_pair in "single:single rc=0:admitted:0:relaxed:passed:admitted" \
               "double:double rc=0:admitted:1:owed:refused:fired" \
               "low: rc=1:refused:-1:owed:passed:admitted" \
               "tested: rc=1:refused:-1:owed:passed:admitted" \
               "medium: rc=1:refused:-1:owed:passed:admitted" \
               "peer-reviewed: rc=1:refused:-1:owed:passed:admitted" \
               "high: rc=1:refused:-1:owed:passed:admitted" \
               "audited: rc=1:refused:-1:owed:passed:admitted"; do
  IFS=: read -r rv_w rv_lvl rv_cl rv_rk rv_aud rv_arm rv_bf <<< "$rv_pair"
  expect_eq "RIGOR $rv_w: rigor_level answers '$rv_lvl'" "$rv_lvl" "$(rv_level "$rv_w")"
  expect_eq "RIGOR $rv_w: the hook's closed set: $rv_cl" "$rv_cl" "$(rv_closed "$rv_w")"
  expect_eq "RIGOR $rv_w: the hook's floor rank is $rv_rk" "$rv_rk" "$(rv_rank "$rv_w")"
  expect_eq "RIGOR $rv_w: the matrix auditor is $rv_aud" "$rv_aud" "$(rv_site "$RV_WALLS" "$rv_w" auditor)"
  expect_eq "RIGOR $rv_w: the requirements-pointer arm $rv_arm" "$rv_arm" "$(rv_site "$RV_WALLS" "$rv_w" pointer)"
  expect_eq "RIGOR $rv_w: the dispatch-ledger arm $rv_arm" "$rv_arm" "$(rv_site "$RV_WALLS" "$rv_w" dispatch)"
  expect_eq "RIGOR $rv_w: the bring-forward arm $rv_bf" "$rv_bf" "$(rv_site "$RV_WALLS" "$rv_w" forward)"
done
for rv_w in standard High ""; do
  expect_eq "RIGOR seventh word '$rv_w': rigor_level refuses it" " rc=1" "$(rv_level "$rv_w")"
  expect_eq "RIGOR seventh word '$rv_w': the hook's floor rank has no place for it" "-1" "$(rv_rank "$rv_w")"
done
for rv_w in standard High; do
  expect_eq "RIGOR seventh word '$rv_w': the hook's closed set refuses it" "refused" "$(rv_closed "$rv_w")"
  expect_eq "RIGOR seventh word '$rv_w': the auditor arm stays closed on it" "owed" "$(rv_site "$RV_WALLS" "$rv_w" auditor)"
done
# THE CENSUS: no line in hooks/ or payload/scripts/ tests, ranks or lists a word before 1.14.0. A case
# arm (`low)`, `tested|…`) or an equality (`= high`, `= "audited"`) is a site that would read one as
# a level. Comments are not sites. The same reader, asked for the two words, finds rigor_level's and
# rigor_print's own arms in run.sh, so the reader reads real lines.
rv_census_re() {  # <alternation> -> the census pattern for those words
  printf '(^|[^a-z-])(%s)[[:space:]]*[|)]|[!=]=?[[:space:]]*"?(%s)("|[[:space:]]|\\]|$)' "$1" "$1"
}
RV_OLD='low|tested|medium|peer-reviewed|high|audited'
rv_census() {  # <alternation> <dir>… -> every non-comment line in the .sh files directly under them testing a word
  local d re; re="$(rv_census_re "$1")"; shift
  for d in "$@"; do /usr/bin/grep -nE "$re" "$d"/*.sh 2>/dev/null; done \
    | /usr/bin/grep -vE '^[^:]+:[0-9]+:[[:space:]]*#'
}
expect_eq "RIGOR census precondition: the census reads the two arms each of rigor_level, rigor_print and fix_cap_default (T21)" "6" \
  "$(rv_census 'single|double' "$RV_LIB" | /usr/bin/grep -c '/run\.sh:')"
expect_eq "RIGOR census: no site in hooks/ or payload/scripts/ tests a word before 1.14.0" "" \
  "$(rv_census "$RV_OLD" "$BIONIC_HOOKS_DIR" "$RV_LIB/.." "$RV_LIB")"
# THE DOCTORED SITE: a walls.sh whose auditor arm tests the old word `low` itself.
RV_MUT="$RV_D/mut/walls.sh"; mkdir -p "$RV_D/mut"
anchor file payload/scripts/lib/walls.sh 'matrix_auditor_required() {'
awk '/^matrix_auditor_required\(\) *\{/ { f = 1 }
     f && /case / { sub(/case .* in/, "case \"$RIGOR\" in") }
     f && /single\) return 1/ { sub(/single\)/, "low)") }
     f && /^}/ { f = 0 } { print }' "$RV_WALLS" > "$RV_MUT"
expect_eq "RIGOR mutation: the doctored copy tests 'low' in exactly one arm, and the census finds it" "1" \
  "$(rv_census "$RV_OLD" "$RV_D/mut" | /usr/bin/grep -c 'low) return 1')"
expect_eq "RIGOR mutation: …and still runs, relaxing the auditor at 'low'" "relaxed" "$(rv_site "$RV_MUT" low auditor)"
expect_ne "RIGOR mutation: …so it reads an old word as a level, and the low row goes red" \
  "$(rv_site "$RV_WALLS" low auditor)" "$(rv_site "$RV_MUT" low auditor)"

# ============================================================
section "§PLACE — one placement reader, four callers: a mutant cmd_place moves the stamp, the gate's tree, the commit's cwd and the jurisdiction arm at once (wave-36 T25; D11, AC-5.6)"
# ============================================================
#
# ONE SOURCE, FOUR READERS. Where a command runs is `cmd_place` (payload/scripts/lib/placement.sh)
# and nothing else: the shim's stamp (walls.sh `_bsg_cd_walk`, the wrap's --stamp-dir), the gate's
# tree (booked.sh `booked_cd_dir`, the request's tree=), the evidence gate's commit cwd (walls.sh
# `_eg_commit_cwd`, its boundary line) and the read-only role's jurisdiction arm (walls.sh ARM C,
# `_bsg_commit_outside`). Before wave-36 T25 the first three read the command text with grammars
# of their own. Pinned here: a doctored copy of the plugin whose `cmd_place` answers tree U for every
# question is driven through the real hook and the real shim, and every one of the four readers
# reads U, where the shipped reader gives each its own true place. A caller that kept a grammar of
# its own would not move with the mutant, and its row goes red.
#
# FIXTURE FIDELITY: an engaged git repository R with a suite, and U, a git repository outside it.
# Nothing in a command below names U, so U can reach a reader only through `cmd_place`.
PL_D="$SANDBOX/fx/place"; PL_R="$PL_D/repo"; PL_U="$PL_D/u"; PL_SID="plcplace-0000-0000-0000-000000000000"
mkdir -p "$PL_R/.bionic/tmp" "$PL_R/tests" "$PL_U" "$PL_D/home"
git -C "$PL_R" init -q 2>/dev/null; git -C "$PL_U" init -q 2>/dev/null
PL_R="$(cd "$PL_R" && pwd -P)"; PL_U="$(cd "$PL_U" && pwd -P)"
: > "$PL_R/.bionic/tmp/engaged-${PL_SID}.state"
printf '#!/bin/bash\necho "PASS: a"\necho; echo "a.test.sh: 1/1 passed, 0 failed  sections=1 setup=0"\n' > "$PL_R/tests/a.test.sh"
PL_LIB="$BIONIC_HOOKS_DIR/../payload/scripts/lib"
[ -r "$PL_LIB/placement.sh" ] || PL_LIB="$BIONIC_HOOKS_DIR/../scripts/lib"
# THE DOCTORED SITE: a copy of the plugin whose placement.sh ends by defining `cmd_place` again, to
# answer U, at rc 0, whatever it is asked.
PL_MUT="$PL_D/mut"
mkdir -p "$PL_MUT/hooks" "$PL_MUT/scripts/lib"
cp "$BIONIC_HOOKS_DIR"/*.sh "$PL_MUT/hooks/" 2>/dev/null
cp "$PL_LIB"/*.sh "$PL_MUT/scripts/lib/" 2>/dev/null
cp "$PL_LIB/../booked.sh" "$PL_MUT/scripts/booked.sh" 2>/dev/null
anchor file payload/scripts/lib/placement.sh 'cmd_place() {'
printf "\ncmd_place() { printf '%%s\\\\n' '%s'; return 0; }\n" "$PL_U" >> "$PL_MUT/scripts/lib/placement.sh"
expect_eq "§PLACE mutation: the doctored placement.sh parses, and its cmd_place answers U for any question" \
  "0 $PL_U" "$(bash -n "$PL_MUT/scripts/lib/placement.sh"; printf '%s ' "$?"; bash -c '. "$1" && cmd_place "bash tests/a.test.sh" /x suite' _ "$PL_MUT/scripts/lib/placement.sh" 2>/dev/null)"
expect_eq "§PLACE mutation: …while the shipped one answers the cwd for a command that moves nothing" \
  "$PL_R" "$(bash -c '. "$1" && cmd_place "bash tests/a.test.sh" "$2" suite' _ "$PL_LIB/placement.sh" "$PL_R" 2>/dev/null)"

pl_hook() {  # <hooks dir> <command> [agent_type] -> PL_ST, PL_ERR, PL_WRAP from the bash walls on that payload
  local p out
  if [ -n "${3:-}" ]; then
    p="$(jq -nc --arg s "$PL_SID" --arg c "$PL_R" --arg cmd "$2" --arg t "$3" \
      '{session_id:$s, transcript_path:"/irrelevant.jsonl", cwd:$c, permission_mode:"bypassPermissions",
        hook_event_name:"PreToolUse", tool_name:"Bash", tool_input:{command:$cmd, timeout:600000},
        tool_use_id:"toolu_pl", agent_id:"aplplace-0123456789abcdef", agent_type:$t}')"
  else
    p="$(jq -nc --arg s "$PL_SID" --arg c "$PL_R" --arg cmd "$2" \
      '{session_id:$s, transcript_path:"/irrelevant.jsonl", cwd:$c, permission_mode:"bypassPermissions",
        hook_event_name:"PreToolUse", tool_name:"Bash", tool_input:{command:$cmd, timeout:600000},
        tool_use_id:"toolu_pl"}')"
  fi
  PL_ERR="$(printf '%s' "$p" | env HOME="$PL_D/home" CLAUDE_CONFIG_DIR="$PL_D/home/.claude" CLAUDE_CODE_SESSION_ID="$PL_SID" \
      CLAUDE_PROJECT_DIR= BIONIC_PLUGINS_DIR="$PL_D/no-plugins" SHELL=/bin/bash CLAUDE_CODE_SHELL= \
      bash "$1/bash-walls.sh" 2>&1 >"$PL_D/hook.out")"; PL_ST=$?
  PL_WRAP="$(jq -r '.hookSpecificOutput.updatedInput.command // ""' "$PL_D/hook.out" 2>/dev/null)"
}
pl_stamp() {  # <hooks dir> -> the --stamp-dir the wall hands the shim for a suite that moves nothing; "none" when it hands none
  local w
  pl_hook "$1" 'bash tests/a.test.sh' test-runner
  case "$PL_WRAP" in *booked.sh*) : ;; *) printf 'unwrapped'; return 0 ;; esac
  case "$PL_WRAP" in *' --stamp-dir '*) w="${PL_WRAP#* --stamp-dir }"; printf '%s' "${w%% *}" ;; *) printf 'none' ;; esac
}
pl_tree() {  # <shim> -> the tree= the gate recorded for the shim's run of a suite that moves nothing, from R
  local before after f
  before="$(ls "$BIONIC_GATE_DIR/requests" 2>/dev/null)"
  ( cd "$PL_R" && env CLAUDE_CODE_SESSION_ID="$PL_SID" bash "$1" --suites a.test.sh -- 'bash tests/a.test.sh' >/dev/null 2>&1 )
  after="$(ls "$BIONIC_GATE_DIR/requests" 2>/dev/null)"
  f="$(comm -13 <(printf '%s\n' "$before" | sort) <(printf '%s\n' "$after" | sort) | grep . | head -n 1)"
  [ -n "$f" ] && sed -n 's/^tree=//p' "$BIONIC_GATE_DIR/requests/$f" | tail -n 1
}
pl_gate() {  # <hooks dir> -> the repository the evidence gate's boundary line names for `git commit` from R; "none" when it names none
  local l
  pl_hook "$1" 'git commit -q --allow-empty -m x'
  l="$(printf '%s\n' "$PL_ERR" | grep -F 'is outside the engaged repository' | head -n 1)"
  [ -n "$l" ] || { printf 'none'; return 0; }
  l="${l#evidence-gate: }"; printf '%s' "${l%% is outside the engaged repository*}"
}
pl_role() {  # <hooks dir> [command] -> `refused` when the read-only role arm refuses a test-runner's commit from R (default `git commit`), else `exempt`
  # The role arm is armed by the session's roster file; an empty one names no row, so the agent type
  # judges. It stands for this probe alone: a roster with no row would refuse the suite pl_stamp drives.
  : > "$PL_R/.bionic/tmp/roster-${PL_SID}.state"
  pl_hook "$1" "${2:-git commit -q --allow-empty -m x}" bionic:test-runner
  rm -f "$PL_R/.bionic/tmp/roster-${PL_SID}.state"
  case "$PL_ERR" in *'a read-only role never commits'*) printf 'refused' ;; *) printf 'exempt' ;; esac
}

# The shipped reader: each caller reads R, where the command runs.
expect_eq "§PLACE stamp [shipped] a suite that moves nothing is stamped where it stands: no --stamp-dir" "none" "$(pl_stamp "$BIONIC_HOOKS_DIR")"
expect_eq "§PLACE gate tree [shipped] …and the shim asks the gate from R" "$PL_R" "$(pl_tree "$PL_LIB/../booked.sh")"
expect_eq "§PLACE commit cwd [shipped] 'git commit' from R is inside: the gate names no outside repository" "none" "$(pl_gate "$BIONIC_HOOKS_DIR")"
pl_hook "$BIONIC_HOOKS_DIR" "cd $PL_U && git commit -q --allow-empty -m x"
expect_contains "§PLACE commit cwd [shipped, positive] …while 'cd U && git commit' is named outside, on the same extractor" \
  "$PL_U is outside the engaged repository" "$PL_ERR"
expect_eq "§PLACE jurisdiction [shipped] a read-only role's 'git commit' in R is refused by the role arm" "refused" "$(pl_role "$BIONIC_HOOKS_DIR")"
# The mutant: every caller reads U, from the one reader, with nothing in the command naming it.
expect_eq "§PLACE stamp [mutant] the wrap's --stamp-dir is U" "$PL_U" "$(pl_stamp "$PL_MUT/hooks")"
expect_eq "§PLACE gate tree [mutant] the shim asks the gate from U" "$PL_U" "$(pl_tree "$PL_MUT/scripts/booked.sh")"
expect_eq "§PLACE commit cwd [mutant] the evidence gate places 'git commit' in U and names it outside" "$PL_U" "$(pl_gate "$PL_MUT/hooks")"
expect_eq "§PLACE jurisdiction [mutant] the role arm places the commit in U, outside the project: exempt" "exempt" "$(pl_role "$PL_MUT/hooks")"

# TWO CALLERS, ONE CHAIN (wave-36 T43; D11, AC-5.6; walk.md shape six). The one-tree mutant above
# answers U whatever it is asked, so it cannot see a caller that asks a different question than its
# siblings: the auditor refuted AC-5.6 on `cd A && cd B && git commit`, which the evidence gate (it
# asks for the git) placed at B and the role arm (it asks for the git and for the end of the command,
# and needs the two equal) refused as moving-form `cd B`. Pinned twice. On the shipped reader, both
# commit callers place that chain at U, so a read-only role's commit there is exempt and the gate
# names U. And a second doctored copy whose `cmd_place` answers a DIFFERENT tree per target, Us for
# suite, U for git and Ue for the end of the command, reads every caller's question off its answer:
# the stamp and the gate's tree ask suite, the commit's cwd asks git, the role arm asks git and the
# end and so sees them differ. A caller that asks another target than these reads another tree, and
# its row goes red.
PL_CHAIN="cd $PL_D && cd $PL_U && git commit -q --allow-empty -m x"
expect_eq "§PLACE chain [shipped] a read-only role's 'cd A && cd U && git commit', both absolute, is exempt: the role arm places it at U" \
  "exempt" "$(pl_role "$BIONIC_HOOKS_DIR" "$PL_CHAIN")"
pl_hook "$BIONIC_HOOKS_DIR" "$PL_CHAIN"
expect_contains "§PLACE chain [shipped] …and the evidence gate names U outside, the same place" \
  "$PL_U is outside the engaged repository" "$PL_ERR"
PL_US="$PL_D/us"; PL_UE="$PL_D/ue"; mkdir -p "$PL_US" "$PL_UE"
PL_US="$(cd "$PL_US" && pwd -P)"; PL_UE="$(cd "$PL_UE" && pwd -P)"
PL_MUT3="$PL_D/mut3"
mkdir -p "$PL_MUT3/hooks" "$PL_MUT3/scripts/lib"
cp "$BIONIC_HOOKS_DIR"/*.sh "$PL_MUT3/hooks/" 2>/dev/null
cp "$PL_LIB"/*.sh "$PL_MUT3/scripts/lib/" 2>/dev/null
cp "$PL_LIB/../booked.sh" "$PL_MUT3/scripts/booked.sh" 2>/dev/null
printf "\ncmd_place() { case \"\${3-}\" in suite) printf '%%s\\\\n' '%s' ;; git) printf '%%s\\\\n' '%s' ;; *) printf '%%s\\\\n' '%s' ;; esac; return 0; }\n" \
  "$PL_US" "$PL_U" "$PL_UE" >> "$PL_MUT3/scripts/lib/placement.sh"
expect_eq "§PLACE per-target mutation: the doctored placement.sh parses, and answers Us, U and Ue for suite, git and the end" \
  "0 $PL_US $PL_U $PL_UE" "$(bash -n "$PL_MUT3/scripts/lib/placement.sh"; printf '%s ' "$?"
    bash -c '. "$1" && printf "%s " "$(cmd_place x /x suite)" "$(cmd_place x /x git)" && cmd_place x /x' _ "$PL_MUT3/scripts/lib/placement.sh" 2>/dev/null)"
expect_eq "§PLACE stamp [per-target] the stamp asks suite: --stamp-dir Us" "$PL_US" "$(pl_stamp "$PL_MUT3/hooks")"
expect_eq "§PLACE gate tree [per-target] the gate's tree asks suite: Us" "$PL_US" "$(pl_tree "$PL_MUT3/scripts/booked.sh")"
expect_eq "§PLACE commit cwd [per-target] the commit's cwd asks git: U" "$PL_U" "$(pl_gate "$PL_MUT3/hooks")"
pl_role "$PL_MUT3/hooks" > "$PL_D/role3.out"   # not in a substitution: the next row reads its PL_ERR
expect_eq "§PLACE jurisdiction [per-target] the role arm asks git and the end, sees U and Ue differ: refused" \
  "refused" "$(cat "$PL_D/role3.out")"
expect_contains "§PLACE jurisdiction [per-target] …naming the git's place and the end's, so it asked exactly those two" \
  "the first git runs in $PL_U but the shell ends in $PL_UE" "$PL_ERR"

# ============================================================
section "DEBT-LINE — one debt-line grammar, owned once in lib/debt.sh and sourced by its three consumers (wave-36 T13; D13; REQ-7 AC-7.8; ownership row 'the debt line')"
# ============================================================
#
# Three regexes read one carried debt before this row: card.sh's inherited reader, the debt verb's adopt
# arm, and close-out's co_debts, which wrote the line and checked nothing (A-orch-1: two hand-written
# lines whose `raised-by=` held a space reached a continuation and refused the next Step-1 card). Now
# `DEBT_LINE_ERE` is assigned once, in payload/scripts/lib/debt.sh, with `debt_line_ok` and
# `debt_carry_lines` beside it, and `debt add`, close-out and card.sh source it. fails-when: a consumer
# holds a debt-line regex of its own, or a mutant of the one regex leaves any consumer's verdict unchanged.
DL_LIB="$BIONIC_SCRIPTS_DIR/payload/scripts/lib/debt.sh"
DL_CONSUMERS="payload/scripts/card.sh payload/scripts/close-out.sh hooks/session-poker.sh"
dl_defs() {  # <pattern> -> path:line of each flush-left match in hooks/ and payload/scripts/
  ( cd "$BIONIC_SCRIPTS_DIR" && /usr/bin/grep -rnE "$1" hooks payload/scripts --include='*.sh' 2>/dev/null )
}
expect_eq "DEBT-LINE 1 the grammar is assigned once in the tree, in lib/debt.sh" "payload/scripts/lib/debt.sh" \
  "$(dl_defs '^DEBT_LINE_ERE=' | cut -d: -f1 | sort -u | paste -sd' ' -)"
expect_eq "DEBT-LINE 1b …assigned exactly once" "1" "$(dl_defs '^DEBT_LINE_ERE=' | wc -l | tr -d ' ')"
expect_eq "DEBT-LINE 1c debt_line_ok is defined once, in lib/debt.sh" "payload/scripts/lib/debt.sh" \
  "$(dl_defs '^debt_line_ok\(\)' | cut -d: -f1 | paste -sd' ' -)"
for dl_c in $DL_CONSUMERS; do
  expect_nonempty "DEBT-LINE 2 $dl_c sources lib/debt.sh" "$(/usr/bin/grep -nE '/debt\.sh"' "$BIONIC_SCRIPTS_DIR/$dl_c")"
  expect_eq "DEBT-LINE 2b $dl_c holds no debt-line regex of its own (no raised-by=[ or touches=[ pattern)" "0" \
    "$(/usr/bin/grep -cE 'raised-by=\[|touches=\[0-9\]' "$BIONIC_SCRIPTS_DIR/$dl_c")"
done
expect_nonempty "DEBT-LINE 2c precondition: the census pattern finds the one regex in lib/debt.sh" \
  "$(/usr/bin/grep -nE 'raised-by=\[' "$DL_LIB")"

# THE MUTANT: a copy of the payload and hooks whose one regex spells the field `raised_by=`. Each consumer
# is asked the same question against the real tree and the mutant: the card's inherited reader, `debt add`
# (the verb, run), and close-out's carry (`debt_carry_lines`, the reader co_debts calls).
DL_D="$SANDBOX/debt-line"; mkdir -p "$DL_D/real" "$DL_D/mut/payload"
cp -R "$BIONIC_SCRIPTS_DIR/hooks" "$DL_D/mut/hooks"; cp -R "$BIONIC_SCRIPTS_DIR/payload/scripts" "$DL_D/mut/payload/scripts"
sed '/^DEBT_LINE_ERE=/s/raised-by=/raised_by=/' "$DL_LIB" > "$DL_D/mut/payload/scripts/lib/debt.sh"
expect_eq "DEBT-LINE mut0 the mutant differs from lib/debt.sh in exactly one line" "1" \
  "$(diff "$DL_LIB" "$DL_D/mut/payload/scripts/lib/debt.sh" | /usr/bin/grep -c '^>')"
DL_P="$DL_D/proj"; mkdir -p "$DL_P/.bionic/docs/plans/epic-9" "$DL_P/.bionic/docs/record/wave-09-dl" "$DL_P/.bionic/docs/specs/epic-9" "$DL_P/.bionic/tmp"
( cd "$DL_P" && git init -q . ) >/dev/null 2>&1
printf '# plan\n\n## SDLC State\n\ncurrent: 4\n' > "$DL_P/.bionic/docs/plans/epic-9/wave-09-dl.plan.md"
DL_LINE='debt: tree_count duplicate "lib/a.sh:1, lib/b.sh:2" touches=4 raised-by=record/wave-08-x/critic-structure.md from=wave-08-x'
printf '%s\n' "# continuation — wave-09-dl" "" "## Deferrals" "" "$DL_LINE" > "$DL_P/.bionic/docs/record/wave-09-dl/continuation.md"
printf '# requirements\n' > "$DL_P/.bionic/docs/specs/epic-9/wave-10-next.requirements.md"
printf '%s\n' "# assumptions" "" 'debt: hole adopt-orphans hooks/a.sh:1' > "$DL_P/.bionic/docs/record/wave-09-dl/assumptions.md"
printf '%s\n' '# debt ledger: concept | kind | sites | raised-by <record> | touches N | burned <row> | —' \
  'tree_count | duplicate | lib/a.sh:1 | raised-by record/wave-08-x/critic-structure.md | touches 4 | —' > "$DL_D/ledger.md"
dl_card() {  # <payload scripts dir> -> card.sh inherited-debt over the fixture
  bash "$1/card.sh" inherited-debt "$DL_P/.bionic/docs/specs/epic-9/wave-10-next.requirements.md" 2>/dev/null 0<&-
}
dl_add() {  # <hooks dir> -> "<rc>|<output>" of debt add over the fixture's hole line, the plan named
  local o r
  rm -f "$DL_P/.bionic/docs/record/wave-09-dl/debt.md"
  o="$(cd "$DL_P" && CLAUDE_CODE_SESSION_ID=dl-sid bash "$1/session-poker.sh" debt add record/wave-09-dl/assumptions.md \
    .bionic/docs/plans/epic-9/wave-09-dl.plan.md 2>&1)"; r=$?
  printf '%s|%s' "$r" "$o"
}
dl_carry() {  # <debt.sh> -> debt_carry_lines over the fixture ledger
  bash -c '. "$1"; debt_carry_lines "$2" wave-09-dl' _ "$1" "$DL_D/ledger.md" 2>/dev/null
}
expect_eq "DEBT-LINE 3 card: the real reader lists the carried line" "$DL_LINE" "$(dl_card "$BIONIC_SCRIPTS_DIR/payload/scripts")"
expect_eq "DEBT-LINE 3b …and the mutant's lists nothing (the line reads as unknown)" "" "$(dl_card "$DL_D/mut/payload/scripts")"
DL_ADD_REAL="$(dl_add "$BIONIC_HOOKS_DIR")"
expect_eq "DEBT-LINE 4 debt add: the real verb adds the hole line (exit 0)" \
  "0|poker: debt add — adopt-orphans hole hooks/a.sh:1" "$(printf '%s\n' "$DL_ADD_REAL" | head -1)"
DL_ADD_MUT="$(dl_add "$DL_D/mut/hooks")"
expect_eq "DEBT-LINE 4b …and the mutant's refuses it (exit 1), the line not parsing" "1" "${DL_ADD_MUT%%|*}"
expect_contains "DEBT-LINE 4c …saying so" "does not parse as a debt line" "$DL_ADD_MUT"
expect_eq "DEBT-LINE 5 close-out's carry: the real reader carries the item" \
  "$(printf 'ok\tdebt: tree_count duplicate "lib/a.sh:1" touches=4 raised-by=record/wave-08-x/critic-structure.md from=wave-09-dl')" \
  "$(dl_carry "$DL_LIB")"
expect_eq "DEBT-LINE 5b …and the mutant's names the ledger line it cannot carry" \
  "$(printf 'bad\ttree_count | duplicate | lib/a.sh:1 | raised-by record/wave-08-x/critic-structure.md | touches 4 | —')" \
  "$(dl_carry "$DL_D/mut/payload/scripts/lib/debt.sh")"
expect_nonempty "DEBT-LINE 5c close-out's co_debts reads the carry through debt_carry_lines" \
  "$(awk '/^co_debts\(\) *\{/ { f = 1 } f && /debt_carry_lines/ { print; exit } f && /^}/ { f = 0 }' "$BIONIC_SCRIPTS_DIR/payload/scripts/close-out.sh")"
rm -rf "$DL_D"

# ============================================================
section "§SLUG — the project transcript directory name: one function, lib/detect.sh project_slug, three callers that move with it, and a name with a character more is another project (wave-37 T5; D9, ADR-058; ownership row 'the project transcript directory name')"
# ============================================================
#
# The CLI files a session's transcript under `<config>/projects/<name>/`, the name being the session's
# directory with every character outside [a-zA-Z0-9] turned to `-` (measured: /Users/admin/workspace/personal/bionic
# is `-Users-admin-workspace-personal-bionic`). Before wave-37 the rule was written twice (detect.sh's auto-memory
# reader and stop-orders.sh's own_transcript); D9 makes it a trust input, so it is one function now, over the
# PHYSICAL path, and its callers are detect.sh `detect_auto_memory`, hooks/stop-orders.sh `own_transcript` and
# lib/said.sh `_said_transcript`. Pinned here: the rule on known paths; the encoder spelled once across the three
# files; each caller names the function; a doctored library whose project_slug answers one fixed name moves the
# auto-memory reader and the words reader together (a caller that kept a copy would not move); and the name is
# matched by equality, so a transcript under `<name>2` (bionic beside bionic2) is not this project's, which a
# prefix-matching mutant of the words reader would accept.
#
# stop-orders' caller is pinned by its text only: own_transcript keeps a walk of every project directory behind
# the two names (it finds this session's ListAgents answers, it is no trust reader), so no fixture can tell from
# its output which name it asked first.
SG_D="$SANDBOX/fx/slug"; SG_SID="sgslug00-0000-4000-8000-00000000005a"
SG_LIB="$BIONIC_HOOKS_DIR/../payload/scripts/lib"
[ -r "$SG_LIB/said.sh" ] || SG_LIB="$BIONIC_HOOKS_DIR/../scripts/lib"
SG_SO="$BIONIC_HOOKS_DIR/stop-orders.sh"
mkdir -p "$SG_D/bionic/.bionic/tmp" "$SG_D/bionic2" "$SG_D/cfg/projects"
SG_R="$(cd "$SG_D/bionic" && pwd -P)"
ln -s "$SG_R" "$SG_D/link"
sg_slug() { bash -c '. "$1/detect.sh" >/dev/null 2>&1; project_slug "$2"' _ "${2:-$SG_LIB}" "$1" 2>/dev/null; }  # <path> [<lib>]
expect_eq "§SLUG 1 the measured name: /Users/admin/workspace/personal/bionic" "-Users-admin-workspace-personal-bionic" \
  "$(sg_slug /Users/admin/workspace/personal/bionic)"
expect_eq "§SLUG 1b …a worktree path: '/.' is '--'" "-x-repo--worktrees-37-T5" "$(sg_slug /x/repo/.worktrees/37-T5)"
expect_eq "§SLUG 1c …a symbolic link is named by the path it resolves to" "$(sg_slug "$SG_R")" "$(sg_slug "$SG_D/link")"
expect_eq "§SLUG 1d …which is the CLI's rule over the physical path" "$(printf '%s' "$SG_R" | sed 's/[^a-zA-Z0-9]/-/g')" "$(sg_slug "$SG_D/link")"

# ---------- one encoder, three callers (text) ----------
sg_body() { awk -v fn="$2" '$0 ~ "^[ \t]*" fn "\\(\\)[ \t]*\\{" { f = 1 } f { print } f && /^[ \t]*}[ \t]*$/ { exit }' "$1"; }  # <file> <function>
SG_ENC='s/[^a-zA-Z0-9]/-/g'
expect_eq "§SLUG 2 the encoder is spelled once across detect.sh, stop-orders.sh and said.sh" "1 0 0" \
  "$(/usr/bin/grep -cF "$SG_ENC" "$SG_LIB/detect.sh") $(/usr/bin/grep -cF "$SG_ENC" "$SG_SO") $(/usr/bin/grep -cF "$SG_ENC" "$SG_LIB/said.sh")"
expect_contains "§SLUG 2b …inside project_slug" "$SG_ENC" "$(sg_body "$SG_LIB/detect.sh" project_slug)"
expect_contains "§SLUG 3 detect_auto_memory names project_slug" "project_slug" "$(sg_body "$SG_LIB/detect.sh" detect_auto_memory)"
expect_contains "§SLUG 3b stop-orders.sh own_transcript names project_slug" "project_slug" "$(sg_body "$SG_SO" own_transcript)"
expect_contains "§SLUG 3c said.sh _said_transcript names project_slug" "project_slug" "$(sg_body "$SG_LIB/said.sh" _said_transcript)"

# ---------- one function: a doctored project_slug moves two callers at once (behaviour) ----------
SG_MUT="$SG_D/mut"; mkdir -p "$SG_MUT"; cp "$SG_LIB"/*.sh "$SG_MUT/" 2>/dev/null
anchor file payload/scripts/lib/detect.sh 'project_slug() {'
printf "\nproject_slug() { printf '%%s' '-mutant-name'; }\n" >> "$SG_MUT/detect.sh"
expect_eq "§SLUG mutation: the doctored detect.sh parses and its project_slug answers one name for any path" \
  "0 -mutant-name" "$(bash -n "$SG_MUT/detect.sh"; printf '%s ' "$?"; sg_slug "$SG_R" "$SG_MUT")"
sg_memory() {  # <lib> -> detect_auto_memory's dir= and files=, for the root
  ( cd "$SG_R" && env BIONIC_CLAUDE_HOME="$SG_D/cfg" BIONIC_ROOT="$SG_R" bash -c '. "$1/detect.sh" >/dev/null 2>&1; detect_auto_memory' _ "$1" 2>/dev/null ) \
    | sed -n 's/^env:auto-memory override=[^ ]* //p'
}
mkdir -p "$SG_D/cfg/projects/$(sg_slug "$SG_R")/memory" "$SG_D/cfg/projects/-mutant-name/memory"
: > "$SG_D/cfg/projects/$(sg_slug "$SG_R")/memory/a.md"
: > "$SG_D/cfg/projects/-mutant-name/memory/b.md"; : > "$SG_D/cfg/projects/-mutant-name/memory/c.md"
expect_eq "§SLUG 4 detect_auto_memory reads the root's own directory" "dir=$SG_D/cfg/projects/$(sg_slug "$SG_R")/memory files=1" "$(sg_memory "$SG_LIB")"
expect_eq "§SLUG 4b …and moves with the doctored project_slug" "dir=$SG_D/cfg/projects/-mutant-name/memory files=2" "$(sg_memory "$SG_MUT")"
sg_said() {  # <lib> <text> -> "<rc>|<SAID_SESSION>", user_said in the root, this session alone
  ( cd "$SG_R" && env CLAUDE_CONFIG_DIR="$SG_D/cfg" CLAUDE_CODE_SESSION_ID="$SG_SID" bash -c '. "$1/said.sh" 2>/dev/null; user_said "$2"; printf "%s|%s" "$?" "${SAID_SESSION:-}"' _ "$1" "$2" 2>/dev/null )
}
SG_W='keep the slug reader in one place please'
sg_tx() {  # <name> -> this session's transcript, holding the words, under that name alone
  rm -f "$SG_D/cfg/projects"/*/"$SG_SID.jsonl"; mkdir -p "$SG_D/cfg/projects/$1"
  jq -cn --arg c "$SG_W" --arg s "$SG_SID" '{type:"user",isSidechain:false,origin:{kind:"human"},promptSource:"typed",message:{role:"user",content:$c},sessionId:$s}' \
    > "$SG_D/cfg/projects/$1/$SG_SID.jsonl"
}
printf 'root=%s\nstarted=2026-10-14T00:00:00Z\ncwd=%s\n' "$SG_LIB" "$SG_R" > "$SG_R/.bionic/tmp/loaded-$SG_SID.state"
sg_tx "$(sg_slug "$SG_R")"
expect_eq "§SLUG 5 the words reader finds this session under the root's own name (rc 0)" "0|$SG_SID" "$(sg_said "$SG_LIB" "$SG_W")"
expect_eq "§SLUG 5b …and under the doctored project_slug it no longer does: the session is refused (rc 2)" "2|" "$(sg_said "$SG_MUT" "$SG_W")"
sg_tx -mutant-name
expect_eq "§SLUG 5c …while the doctored library reads the transcript under the name its project_slug gives (rc 0)" "0|$SG_SID" "$(sg_said "$SG_MUT" "$SG_W")"
expect_eq "§SLUG 5d …which the shipped library refuses (rc 2)" "2|" "$(sg_said "$SG_LIB" "$SG_W")"

# ---------- equality, never a prefix: bionic is not bionic2 ----------
expect_eq "§SLUG 6-pre precondition: bionic2's name is bionic's with a character more" "$(sg_slug "$SG_R")2" "$(sg_slug "$SG_D/bionic2")"
sg_tx "$(sg_slug "$SG_D/bionic2")"
expect_eq "§SLUG 6 a transcript under bionic2's directory is not bionic's session: refused (rc 2)" "2|" "$(sg_said "$SG_LIB" "$SG_W")"
SG_PFX="$SG_D/pfx"; mkdir -p "$SG_PFX"; cp "$SG_LIB"/*.sh "$SG_PFX/" 2>/dev/null
anchor file payload/scripts/lib/said.sh 'f="$dir/$s/$sid.jsonl"'
SG_N='f="$dir/$s/$sid.jsonl"' awk 'BEGIN { n = ENVIRON["SG_N"] } { i = index($0, n); if (i) $0 = substr($0, 1, i - 1) "f=\"$(ls -d \"$dir/$s\"*/\"$sid.jsonl\" 2>/dev/null | head -1)\"" substr($0, i + length(n)); print }' \
  "$SG_LIB/said.sh" > "$SG_PFX/said.sh"
expect_eq "§SLUG 6b the prefix mutant differs from the library in one line" "1" "$(diff "$SG_LIB/said.sh" "$SG_PFX/said.sh" | /usr/bin/grep -c '^>')"
expect_eq "§SLUG 6c …and accepts bionic2's transcript as bionic's (rc 0), so §SLUG 6 goes red under it" "0|$SG_SID" "$(sg_said "$SG_PFX" "$SG_W")"
rm -rf "$SG_D"

# ---------------------------------------------------------------------------
section "§WIDTH — the gate owns the width: the landing drain's J is the gate's answer, the runner's JOBS the floor's rule (wave-37 T1; wave-38 T6, D21, ADR-060; ownership row 'the width rule J')"
#
# wave-38 D21: the drain no longer sizes itself. Before each pass it asks the gate (lib/gate.sh
# `gate_width_ask <landing>`) through one door, lib/line.sh `_line_width_ask`, and starts exactly the
# answer; `_line_width` is retired. The floor (tests/run.sh `_runner_width`) still reads `pressure_level`
# over `gate_width`. So the agreement has two halves, neither a copy of the other's arithmetic: on each
# planted rung the drain's answer IS the gate's, and the runner's JOBS is still the floor's rule. The
# drain's rungs are T5's worked table (8 cores at share 92: load 2 answers 4, load 6 answers 1, from an
# empty store); the runner's are one sample in the ring, clear or critical, on the suite's 8 pinned cores
# at share 100.
WD_DIR="$SANDBOX/wd"; WD_HOME="$WD_DIR/cfg"; WD_RING="$WD_DIR/pressure.ring"; WD_NOW=1757030000
mkdir -p "$WD_HOME/bionic"; printf '100\n' > "$WD_HOME/bionic/share"
WD_GHOME="$WD_DIR/gcfg"; mkdir -p "$WD_GHOME/bionic"; printf '92\n' > "$WD_GHOME/bionic/share"
WD_LIB="$REPO_ROOT/payload/scripts/lib"
WD_CLEAR="BIONIC_PROBE_FREE_PCT=80 BIONIC_PROBE_SWAP_PCT=0 BIONIC_PROBE_LOAD_1M=0.1 BIONIC_PROBE_FREE_MB=8192"
WD_CRIT="BIONIC_PROBE_FREE_PCT=8 BIONIC_PROBE_SWAP_PCT=0 BIONIC_PROBE_LOAD_1M=0.1 BIONIC_PROBE_FREE_MB=8192"
wd_seed() {  # <probe env> — the ring, reset to one sample by pressure_sample
  rm -f "$WD_RING"
  ( eval "export $1"; export BIONIC_PRESSURE_RING="$WD_RING" BIONIC_NOW_EPOCH="$WD_NOW"
    . "$WD_LIB/resources.sh" >/dev/null 2>&1; pressure_sample 8 ) >/dev/null 2>&1
}
wd_runner() {  # <probe env> -> tests/run.sh's JOBS under --dry-run, no ceiling
  ( eval "export $1"; unset BIONIC_TEST_JOBS_CEILING
    export BIONIC_PRESSURE_RING="$WD_RING" BIONIC_NOW_EPOCH="$WD_NOW" CLAUDE_CONFIG_DIR="$WD_HOME"
    bash "$REPO_ROOT/tests/run.sh" --dry-run 2>/dev/null ) | sed -n 's/^JOBS=//p' | head -1
}
wd_rung() {  # <load> -> the probe env of the drain's planted machine: 8 cores, 30% of memory used, <load> busy
  printf 'BIONIC_PROBE_CORES=8 BIONIC_PROBE_TOTAL_MB=8192 BIONIC_PROBE_USED_PCT=30 BIONIC_PROBE_FREE_PCT=70 BIONIC_PROBE_FREE_MB=5734 BIONIC_PROBE_SWAP_PCT=0 BIONIC_PROBE_BUSY_CORES=%s BIONIC_PROBE_BUSY_CORES_5M=%s BIONIC_PROBE_LOAD_1M=%s' "$1" "$1" "$1"
}
wd_ask() {  # <probe env> <gate|drain> [<sed over _line_width_ask>] -> the answer for landing wd:T1, from an empty store of its own
  ( eval "export $1"; unset BIONIC_TEST_JOBS_CEILING
    export CLAUDE_CONFIG_DIR="$WD_GHOME" BIONIC_GATE_DIR="$WD_DIR/gate-$2" BIONIC_PRESSURE_RING="$WD_DIR/ask.ring" BIONIC_NOW_EPOCH="$WD_NOW"
    rm -rf "$BIONIC_GATE_DIR" "$BIONIC_PRESSURE_RING"
    bash -c '. "$1/line.sh" >/dev/null 2>&1 && . "$1/gate.sh" >/dev/null 2>&1 || exit 99
      [ -z "$3" ] || eval "$(declare -f _line_width_ask | sed "$3")"
      if [ "$2" = gate ]; then gate_width_ask wd:T1; else _line_width_ask wd:T1; fi' _ "$WD_LIB" "$2" "${3:-}" 2>/dev/null )
}
wd_seed "$WD_CLEAR"; WD_RUN_CLEAR="$(wd_runner "$WD_CLEAR")"
wd_seed "$WD_CRIT"; WD_RUN_CRIT="$(wd_runner "$WD_CRIT")"
expect_eq "WIDTH 1 the floor, a clear rung: the runner's JOBS is the whole width, pressure_level over gate_width (not vacuous)" "8" "$WD_RUN_CLEAR"
expect_eq "WIDTH 2 the floor, a critical rung: the runner's JOBS is a quarter" "2" "$WD_RUN_CRIT"
WD_GATE_2="$(wd_ask "$(wd_rung 2.0)" gate)"; WD_DRAIN_2="$(wd_ask "$(wd_rung 2.0)" drain)"
WD_GATE_6="$(wd_ask "$(wd_rung 6.0)" gate)"; WD_DRAIN_6="$(wd_ask "$(wd_rung 6.0)" drain)"
expect_eq "WIDTH 1b the drain, load 2 on 8 cores at share 92: the gate answers 4 (not vacuous)" "4" "$WD_GATE_2"
expect_eq "WIDTH 1c …and the drain's J is the gate's answer" "$WD_GATE_2" "$WD_DRAIN_2"
expect_eq "WIDTH 2b the drain, load 6: the gate answers 1 (0 by the rule, 1 by the floor)" "1" "$WD_GATE_6"
expect_eq "WIDTH 2c …and the drain's J is the gate's answer" "$WD_GATE_6" "$WD_DRAIN_6"
expect_true "WIDTH 3 line.sh asks the gate for the width (gate_width_ask)" test "$(/usr/bin/grep -c 'gate_width_ask' "$WD_LIB/line.sh")" -ge 1
expect_true "WIDTH 3b …and tests/run.sh still reads gate_width" test "$(/usr/bin/grep -c 'gate_width' "$REPO_ROOT/tests/run.sh")" -ge 1
expect_eq "WIDTH 3c the drain's door is defined and _line_width is retired" "yes no" \
  "$(bash -c '. "$1/line.sh" >/dev/null 2>&1; declare -F _line_width_ask >/dev/null && echo yes || echo no; declare -F _line_width >/dev/null && echo yes || echo no' _ "$WD_LIB" | tr '\n' ' ' | sed 's/ $//')"
# MUTANT: the drain sizes itself again by the floor's rule. It then parts from the gate's answer.
anchor fn payload/scripts/lib/line.sh 'gate_width_ask "$1"' _line_width_ask 'pressure_level "$(gate_width)"'
WD_MUT_2="$(wd_ask "$(wd_rung 2.0)" drain "$ANCHOR_SED")"
expect_true "WIDTH 4m-pre the mutant ran: its J is a whole number ($WD_MUT_2)" test -n "$WD_MUT_2" -a -z "${WD_MUT_2//[0-9]/}"
expect_true "WIDTH 4m MUTANT the drain sizes itself: its J parts from the gate's answer at load 2 (the rows can fail)" test "$WD_MUT_2" != "$WD_GATE_2"

finish
