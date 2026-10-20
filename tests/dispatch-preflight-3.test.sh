#!/bin/bash
# Tests for hooks/dispatch-preflight.sh — THE START GATE. One shard of four:
# §combined … §two-deliverables.
#
# The suite's header (what it governs, how it stays hermetic) is in
# tests/dispatch-preflight.test.sh; the fixtures and their fidelity notes are in
# tests/dispatch-preflight.prelude.sh.
#
# FOUR SHARDS, ONE SUITE (wave-30 T1; design ledger Δ7, D8; AC-5.1). This suite ran for
# 1,462 s at width 4, the longest in the roster, so it is split by section into four files
# that the runner schedules side by side. Each is a gating suite by location, and each passes
# alone:
#
#   dispatch-preflight.test.sh     §CAP … §role-class, then §no-listagents
#   dispatch-preflight-2.test.sh   S1 … S22
#   dispatch-preflight-3.test.sh   §combined … §two-deliverables
#   dispatch-preflight-4a.test.sh  S10h … §LR       (two parts since wave-39 T37; the helpers they share
#   dispatch-preflight-4b.test.sh  §T72 … §FILES     are in tests/dispatch-preflight-4.prelude.sh)
#
# What every shard needs and no section owns is in tests/dispatch-preflight.prelude.sh: the
# fixtures, the sandbox and its traps, run_gate and the payload builders, and the helpers and
# constant strings that a section defined and a section in another shard reads. Each shard
# sources the framework and the shared libraries itself, then the prelude. The one fixture
# that crosses sections, the decoy roster file S10h plants and §RECORDER reads, is kept in
# one shard by moving S10h beside §RECORDER. §no-listagents reads a sweep that run_gate keeps
# over every payload driven before it, so it closes the shard that drives the most; it sweeps
# that shard's traffic, not the whole suite's. The sum of the four shards' checks is the
# unsplit suite's count.
#
# Usage: bash tests/run.sh --only dispatch-preflight-3.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"
# THE NARROWING (wave-39 T44; D6, AC-2.4, A-orch-22). The verbs of hooks/session-poker.sh this suite reaches,
# directly or through the hooks and scripts it runs: arm, debt, interval, interval-default, window. Each line
# below is that closure: the library (every run executes it), the arm of each verb, the sections defining the
# globals they read, and each helper outside those.
reads hooks/session-poker.sh section "the library"
reads hooks/session-poker.sh section "whose run is this?"
reads hooks/session-poker.sh fn clean
reads hooks/session-poker.sh fn epoch_iso
reads hooks/session-poker.sh fn file_birth
reads hooks/session-poker.sh fn file_mtime
reads hooks/session-poker.sh fn iso_now
reads hooks/session-poker.sh fn line_field
reads hooks/session-poker.sh fn note
reads hooks/session-poker.sh fn now_epoch
reads hooks/session-poker.sh fn parse_seconds
reads hooks/session-poker.sh fn patrol_stamp_file
reads hooks/session-poker.sh fn poker_interval_seconds
reads hooks/session-poker.sh fn roster_window
reads hooks/session-poker.sh fn row_has_key
reads hooks/session-poker.sh fn sched_facts_state
reads hooks/session-poker.sh fn tmp_dir_ok
. "$(dirname "$0")/lib/bound-marker.sh"
. "$(dirname "$0")/lib/roster-row.sh"
. "$(dirname "$0")/lib/live-answer.sh"
. "$(dirname "$0")/lib/swept-marker.sh"
. "$(dirname "$0")/dispatch-preflight.prelude.sh"

section "§combined — one refusal, every brief-shape fault (wave-12 T2, D3, AC-1.1/AC-1.2)"
# ============================================================================
#
# THE INCIDENT THIS SECTION IS BUILT FROM. On 2026-09-13 six dispatch attempts were spent
# spawning one researcher: the gate exited at the FIRST failing brief-shape arm, so each
# attempt taught the author exactly one fault and the next attempt found the next one. The
# faults were all in the brief — the one artifact the author was holding — and all readable
# in a single pass.
#
# WHAT CHANGED (spec D3, principle P-A). The five BRIEF-SHAPE arms — A11 several paths,
# A12 outside the repo, A13 no deliverable, A14 no Files:/Suites:, A16 Files: naming
# no suite — no longer refuse where they stand. Each appends its finding (fact, fix
# and its own verbatim `Fix:` block) to a list, and ONE `refuse exit2` after the last of
# them emits the list in file order and exits 2 once. The STATE arms are untouched: a
# missing attestation, an unarmed Patrol, an unapproved plan, a worktree cwd, a full
# budget and a second full-tree dispatch each still exit where they stand, because none of
# them is a defect in the brief and none is fixed by reading the next one.
#
# fails-when: a three-fault brief is refused for fewer than three faults, or refused more
# than once, or the second attempt — written from the first refusal's own `Fix:` examples —
# is refused for a fault the first refusal never named.

REPO=$(make_repo rcomb yes)
# A BUDGETED PLAN (ADR-035). Since epic-23 wave-20 T2 a keyless live plan adds its own
# `not checked: budget` line to the wire, and this arm's line cap counts the scaffold's walls,
# not the budget's; a real plan carries the key, so the fixture does too.
s22_set_budget "$REPO" "writers=99 suites=99 worktrees=99 test_jobs=4 source=user"
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_THREE_FAULTS" "combobot")"

# THE CHANNEL IS THE VERDICT, NOT THE STATUS (wave-12 T17). A combined refusal exits 0 and
# blocks with a PreToolUse deny verdict, so this arm reads `$GATE_VERDICT` — the driver's
# reading of both wires — where it used to read exit 2. §combined-deny below is where that
# channel is pinned in full; here it only has to be a REFUSAL for the counts to mean anything.
expect_eq "§combined a brief with three shape faults is REFUSED" "deny" "$GATE_VERDICT"

# ONE REFUSAL, NOT THREE. `refuse` exits, so a second refusal object cannot be emitted by
# the same process — but a wall that printed its findings as it went would show three
# `bionic: ` lines, and a wall that kept exiting at the first arm would show one line and
# one finding. The count of refusal lines and the count of findings are therefore both
# read, and they are different numbers on purpose.
expect_eq "§combined …exactly once: one refusal line reaches the user" "1" \
  "$(printf '%s\n' "$GATE_ERR" | /usr/bin/grep -c '^bionic: ' || true)"
expect_eq "§combined …and the detail carries one refusal, not three stacked" "1" \
  "$(printf '%s\n' "$GATE_VERR" | /usr/bin/grep -c '^bionic: dispatch refused' || true)"

# THE USER LINE IS THE FIRST ARM'S OWN, and the detail says how many there are. AC-E1.3
# gives the line one fact and one six-word fix, and the widest arm here already spends 99
# of its 100 columns — so a line that also carried a count would be refused by the
# renderer as malformed. The count lives one line into the detail instead, where there is
# room for it and for every fault behind it.
expect_eq "§combined …the user line stays the first arm's own sentence" \
  "bionic: dispatch refused — the deliverable label names several paths (name exactly one deliverable)" \
  "$(printf '%s\n' "$GATE_ERR" | /usr/bin/grep '^bionic: ')"
# THE MARKED SCAFFOLD REPLACES THE OLD RATIONALE (T2, D3/D11). No fault-count header
# sentence, no per-fault `── N.` heading, no `Fix:` block — the several-fault wire is the
# scaffold read live out of the shipped dispatch.md, each label the brief left empty
# suffixed ` <ADD>`, closed by one pointer line. Every string compared against below is
# read out of $DISPATCH_FILE at run time, never transcribed, so this stays true when the
# scaffold's own wording next changes.
expect_absent "§combined …no fault-count header sentence" "SHAPE FAULTS" "$GATE_VERR"
expect_absent "§combined …no per-fault '── N.' heading" "── " "$GATE_VERR"
expect_absent "§combined …no Fix: block" "Fix: " "$GATE_VERR"
# RAISED 8 -> 10 (T17, R6 finding 3): the scaffold gained two lines (`Progress artifact:`,
# `Cadence:`), and dp_scaffold_marked reproduces every scaffold line verbatim — marked or
# not — so the wire grows by exactly as many lines as the scaffold does. Not a widened
# tolerance; the cap tracks the scaffold's own line count by construction.
#
# RAISED 10 -> 13 (wave-14 T6, REQ-8/AC-8.3, A-T6.2), and by a formula rather than a
# feeling. Ten is still the fixed part — one refusal line, a blank, seven scaffold lines, a
# blank, the pointer. On top of it this brief buys three lines and no more, though WHICH
# three moved at T26 (critic Issue 3): the ambiguity fault IS the refusal line and costs
# nothing; "this brief declares no Files: and no Suites:" is the second fault and costs one
# line; and two `not checked:` lines now ride the wire instead of one — `deliverable, needs
# one path` (the absent-deliverable arm recognising the ambiguity arm's own candidates,
# rather than repeating the fault) and `one-regression, needs a suite set` (unchanged). The
# general form is still 10 + (faults - 1) + not-checked lines, and the total is unchanged
# at 13 because a line only moved from the fault column to the not-checked column.
# §three-arms holds the criterion's own case — three faults, nothing unchecked, twelve —
# where this arm holds the canonical brief. Widening either without moving a fault count is
# the mistake to catch.
#
# RAISED 13 -> 14 (wave-15 T5, REQ-5, A-T5.2), and by the same formula. The floor-once wall
# is a SECOND arm keyed on `run.sh` in the suite set, so a brief that produces no
# set leaves two walls unable to answer rather than one, and AC-8.2's rule is that each of
# them says so. The fault count did not move — the third `not checked:` line is a new wall
# declaring itself, which is the growth this cap is meant to permit.
#
# RAISED 14 -> 15 (epic-23 wave-16, REQ-1 AC-1.8, A-T2.7), by the cap's oldest clause: it
# "tracks the scaffold's own line count by construction", and the scaffold gained the
# `Re-executes:` line. The FIXED part is now eleven — one refusal line, a blank, EIGHT
# scaffold lines, a blank, the pointer — and the variable part is unmoved at one extra
# fault plus three not-checked lines. No fault and no wall was added by that change.
#
# RAISED 15 -> 16 (wave-20 T7, REQ-9 AC-9.3), in the FIXED part: the wire now carries one
# line saying the wall reads the prompt text only, beside the scaffold it tells the author to
# copy. The fixed part is twelve; the variable part is unmoved.
#
# RAISED 16 -> 17 (wave-21 T7, REQ-7 AC-7.2), by the oldest clause again: the scaffold gained
# the optional `Subprocess claim:` line, which `dp_scaffold_marked` reproduces like every
# other. The FIXED part is thirteen — one refusal line, a blank, NINE scaffold lines, the
# prompt-only line, a blank, the pointer — and the variable part is unmoved. The meta row
# below holds the scaffold at nine lines, so the next line added to it moves this cap on
# purpose rather than by surprise.
#
# RAISED 17 -> 18 (wave-24 T9, REQ-4 AC-4.8, A-T9.12), by that clause: the scaffold gained the
# optional `Done marker:` line. The FIXED part is fourteen — one refusal line, a blank, TEN
# scaffold lines, the prompt-only line, a blank, the pointer — and the variable part is unmoved.
#
# LOWERED 18 -> 17 (wave-26 T5, REQ-3 D6): the one-regression and floor-once arms became ONE
# full-run arm, so a brief with no suite set leaves one wall unable to answer, not two. The
# variable part is one extra fault plus two not-checked lines; the fixed part is unmoved.
# RAISED 17 -> 18 (wave-27 T17, D5): the scaffold gained the readers' `Questions:` line; the FIXED part is fifteen, ELEVEN scaffold lines.
# RAISED 18 -> 20 (wave-27 T31, D23): the scaffold gained `Lands-red:` and `Red-evidence:`; the FIXED part is seventeen, THIRTEEN scaffold lines.
# RAISED 20 -> 22 (wave-28 T58, repairing the pin after T7/T22): the scaffold gained `Row:` and `Lands-on:`; the FIXED part is nineteen, FIFTEEN scaffold lines.
expect_eq "§combined meta: the shipped scaffold is fifteen lines, the count both caps are built on" \
  "15" "$(scaffold_block "$DISPATCH_FILE" | wc -l | tr -d ' ')"
expect_status "§combined …the wire is at most 22 lines (19 + 1 extra fault + 2 not-checked)" "0" \
  "$([ "$(printf '%s' "$GATE_REASON" | wc -l | tr -d ' ')" -le 22 ] && echo 0 || echo 1)"
expect_contains "§combined …and the fixed line that grew it is the prompt-only sentence" \
  "The wall reads the prompt text only." "$GATE_REASON"
# AND THE FULL-RUN WALL'S LINE IS NAMED — a cap without saying which line fills it is a
# widened tolerance, which is the mistake the comment above warns about.
expect_contains "§combined …and one not-checked line is the full-run wall's" \
  "not checked: full-run, needs a suite set" "$GATE_REASON"

# EACH LABEL, MARKED BY WHETHER THIS BRIEF CARRIES IT — not by which wall fired. The
# absent Files: and the absent Deliverable-waiver: lines earn ` <ADD>`; the present
# Expected duration: line is left exactly as shipped. The ambiguous Expected artifact:
# line does NOT earn one (T26, critic Issue 3) — the label was read and rejected as
# ambiguous, which is not the same fault as an empty label, and the wire's own
# `not checked: deliverable, needs one path` line (below) says so instead.
COMB_ART_LINE="$(scaffold_raw_line "$DISPATCH_FILE" "Expected artifact")"
COMB_FILES_LINE="$(scaffold_raw_line "$DISPATCH_FILE" "Files")"
COMB_DURATION_LINE="$(scaffold_raw_line "$DISPATCH_FILE" "Expected duration")"
COMB_WAIVER_LINE="$(scaffold_raw_line "$DISPATCH_FILE" "Deliverable-waiver")"
expect_absent "§combined …the still-ambiguous Expected artifact: line is NOT marked <ADD>" \
  "${COMB_ART_LINE} <ADD>" "$GATE_VERR"
expect_contains "§combined …and its not-checked line names the deliverable arm instead" \
  "not checked: deliverable, needs one path" "$GATE_VERR"
expect_contains "§combined …the absent Files: line is marked <ADD>" \
  "${COMB_FILES_LINE} <ADD>" "$GATE_VERR"
expect_contains "§combined …the absent Deliverable-waiver: line is marked <ADD>" \
  "${COMB_WAIVER_LINE} <ADD>" "$GATE_VERR"
expect_contains "§combined …the present Expected duration: line is left exactly as shipped" \
  "$COMB_DURATION_LINE" "$GATE_VERR"
expect_absent "§combined …and carries no <ADD> of its own" \
  "${COMB_DURATION_LINE} <ADD>" "$GATE_VERR"
expect_contains "§combined …and closes with the pointer line" \
  "See skills/canonical-sdlc/dispatch.md §Dispatch for why each line is required." "$GATE_VERR"

# AND NOTHING WAS LAUNCHED. A refused dispatch is not a launch, however many faults it had.
expect_status "§combined …and journals no roster row" "0" \
  "$(roster_rows "$(roster_path "$REPO" "$SID_A")")"

# ---- the second attempt, written from the first refusal's own examples ----
#
# THE WHOLE POINT, AND THE ONLY ARM THAT CAN CARRY IT. Three facts in one message are worth
# nothing if acting on all three still leaves a fault the message never mentioned. The
# examples are read back OUT of the stderr rather than typed here, so this stays true when
# the wording is next edited.
COMB_ART=$(fix_example "$GATE_VERR")
COMB_SUITES=$(printf '%s\n' "$GATE_VERR" | /usr/bin/grep -m1 -E '^Suites:' \
  | sed -e 's/[[:space:]]*#.*$//' -e 's/[[:space:]]*<ADD>[[:space:]]*$//' -e 's/[[:space:]]*$//')
expect_status "§combined the refusal really recommended an artifact path" "0" \
  "$([ -n "$COMB_ART" ] && echo 0 || echo 1)"
expect_status "§combined …and a Suites: line" "0" \
  "$([ -n "$COMB_SUITES" ] && echo 0 || echo 1)"
expect_absent "§combined …neither carrying a slot the walls themselves refuse" "<" "$COMB_ART"

REPO=$(make_repo rcomb2 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: review the wave.
Expected artifact: $COMB_ART
Expected duration: 20 minutes
$COMB_SUITES" "combobot2")"
expect_status "§combined attempt 2, following every scaffold-line example, PASSES" "0" "$GATE_ST"
expect_status "§combined …with the recommended path as the contract" \
  "$COMB_ART" "$(roster_field "$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)" deliverable)"

# ---- the discriminator: declaring one field discharges that field's PAIR, and nothing else ----
#
# Without this arm a wall that printed the scaffold with every line marked unconditionally
# would pass every assertion above.
#
# RENARROWED BY WAVE-14 T26 (critic Issue 3). This arm used to declare `Suites:` against
# $BRIEF_THREE_FAULTS and check that the Files:/Suites: pair lost its <ADD> while the
# Expected artifact:/Deliverable-waiver: pair — still unresolved by an AMBIGUOUS label —
# kept theirs, on a deny wire the ambiguity finding and a separately-firing "this brief
# names no deliverable" finding kept alive together. That second finding is exactly critic
# Issue 3's contradiction (fixed above: an ambiguous label is one fault, not two), so
# $BRIEF_THREE_FAULTS with `Suites:` added now carries the ambiguity fault ALONE — the
# single-fault shape, with no scaffold on it at all (§combined a two-fault
# brief... below reads that exact fixture). What this arm can still discriminate is
# narrower and cleaner: a GENUINELY absent (non-ambiguous) deliverable is a real,
# independent fault from "no Files: and no Suites:" — declaring `Suites:` discharges only
# the second and leaves the first exactly where it was.
REPO=$(make_repo rcomb3 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: review the wave.
Expected duration: 20 minutes
Suites: tests/widget.test.sh" "combobot3")"
expect_eq "§combined declaring Suites: discharges the Files:/Suites: fault, leaving the other" \
  "deny" "$GATE_VERDICT"
expect_contains "§combined …the surviving fault is the genuinely absent deliverable" \
  "this brief names no deliverable" "$GATE_ERR"
expect_absent "§combined …and the Files:/Suites: fault is really gone, not merely unmarked" \
  "Files:" "$GATE_ERR$GATE_REASON"

# ---- and a ONE-fault brief is refused in its arm's own words, as it always was ----
#
# AC-1.3 from the other side: collecting must not re-word the single-fault refusal every
# other section in this file reads. One finding renders as one finding — the arm's own fact,
# its own fix, its own detail — and the user line is the one the E1.3 table pins.
REPO=$(make_repo rcomb4 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: build it.
Expected duration: ~15 minutes.
Suites: tests/widget.test.sh" "combobot4")"
expect_eq "§combined a single-fault brief keeps the arm's own line, unchanged" \
  "bionic: dispatch refused — this brief names no deliverable (add an Expected artifact: line)" \
  "$(printf '%s\n' "$GATE_ERR" | /usr/bin/grep '^bionic: ')"
expect_eq "§combined …and renders exactly one Fix: block" "1" \
  "$(printf '%s\n' "$GATE_VERR" | /usr/bin/grep -c '^Fix: ' || true)"

# ============================================================================

section "§scaffold-marks — the scaffold marks what the brief LACKS, not what it omits (wave-14 REQ-6, D8)"
# ============================================================================
#
# WHAT A MARK MEANS. `dp_scaffold_marked` reproduces the shipped scaffold and suffixes
# ` <ADD>` to the lines this brief still needs. Until wave-14 it asked only "did this brief
# spell this label", which is A-T2.1's literal-presence rule — and three of the scaffold's
# labels are not standalone requirements at all. The scaffold says so itself: `Files:` is
# "writers; a read-only brief omits this and keeps Suites: none" (wave-21 T7's wording),
# `Deliverable-waiver:` is "only for a report returned by message". So a read-only brief that had correctly declared `Suites:` was told to add
# files it will not touch, and a brief that had declared its artifact was told to waive it —
# an instruction that, followed, would make the dispatch worse. Two of the three items on
# wave-13's walk.
#
# THE RULE (D8). `Files:` is marked only when `C_FILES` and `C_SUITES` are BOTH empty — the
# suite-allowance wall's own condition, so the mark appears exactly when that wall fires.
# `Expected artifact:` and `Deliverable-waiver:` are each marked only when `C_DELIVERABLE`
# and `C_WAIVER` are both empty — the absent-deliverable wall's own condition, and the pair
# is symmetric because either one satisfies the contract.
#
# KEYED ON THE LIFTED FIELDS, NEVER ON LITERAL LINE PRESENCE (R2 Q7). `BRIEF_THREE_FAULTS`
# below carries an `Expected artifact:` line whose span names two paths: the extractor emits
# candidates and leaves `C_DELIVERABLE` empty, so the brief HAS the label and still needs it.
# A rule keyed on the label's presence would unmark it and take (c) — and §combined's own
# pin — red.
#
# EVERY EXPECTED STRING IS READ OUT OF THE SHIPPED dispatch.md at run time, never
# transcribed, exactly as §combined does it.

SM_ART_LINE="$(scaffold_raw_line "$DISPATCH_FILE" "Expected artifact")"
SM_FILES_LINE="$(scaffold_raw_line "$DISPATCH_FILE" "Files")"
SM_SUITES_LINE="$(scaffold_raw_line "$DISPATCH_FILE" "Suites")"
SM_WAIVER_LINE="$(scaffold_raw_line "$DISPATCH_FILE" "Deliverable-waiver")"
expect_nonempty "§scaffold-marks meta: the four scaffold lines were read out of dispatch.md" \
  "${SM_ART_LINE}${SM_FILES_LINE}${SM_SUITES_LINE}${SM_WAIVER_LINE}"

# (a) AC-6.1 — A READ-ONLY BRIEF DECLARES ITS INSTRUMENT THE OTHER WAY. `Suites: none` is
# the read-only waiver, so `Files:`/`Suites:` are satisfied and must not be marked.
#
# RENARROWED BY WAVE-14 T26 (critic Issue 3). This fixture used to pair an ambiguous
# deliverable label with an empty one for a two-fault deny — the exact duplicate-counting
# bug Issue 3 names (see the §combined rewrite above for the full reasoning). With that
# collapsed to one fault, and `Suites: none` discharging the OTHER pooled arm this file has
# (no independent third arm can fire alongside a satisfied Files:/Suites: pair and a
# deliverable-field fault — every other brief-shape arm reads the same field), this brief
# is down to its single-fault shape, where `dp_scaffold_marked` never renders
# at all. What still discriminates: the refusal names ONLY the deliverable fault, and
# never so much as mentions Files:/Suites: — proving the pair was read as
# satisfied rather than merely unmarked on a wire this fixture can no longer reach.
REPO=$(make_repo rsm-readonly yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: review the wave.
Expected duration: 20 minutes
Suites: none" "smbot1")"
expect_eq "§scaffold-marks (a) the read-only brief refuses on its own single-arm wire" \
  "deny" "$GATE_VERDICT"
expect_contains "§scaffold-marks (a) …naming the absent deliverable" \
  "this brief names no deliverable" "$GATE_ERR"
expect_absent "§scaffold-marks (a) …and never mentioning Files: — Suites: none satisfied it" \
  "Files:" "$GATE_ERR$GATE_REASON"
expect_absent "§scaffold-marks (a) …nor Suites: — it was declared, not missing" \
  "names no suite" "$GATE_ERR$GATE_REASON"

# (b) AC-6.2 — A DECLARED ARTIFACT SATISFIES THE WAIVER'S HALF OF THE PAIR. The deliverable
# resolves outside the repo and the brief declares no instrument: two faults, and a
# `C_DELIVERABLE` that is non-empty. Nothing here needs a waiver.
REPO=$(make_repo rsm-artifact yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: build it.
Expected artifact: ../../../../../../etc/hosts
Expected duration: ~15 minutes." "smbot2")"
expect_status "§scaffold-marks (b) the artifact-bearing brief refuses on the several-fault wire" "0" \
  "$([ -n "$GATE_DENY" ] && echo 0 || echo 1)"
expect_absent "§scaffold-marks (b) …and the Deliverable-waiver: line is NOT marked beside a declared artifact" \
  "${SM_WAIVER_LINE} <ADD>" "$GATE_VERR"
expect_contains "§scaffold-marks (b) …the Deliverable-waiver: line is still rendered, as shipped" \
  "$SM_WAIVER_LINE" "$GATE_VERR"
expect_absent "§scaffold-marks (b) …nor is the declared Expected artifact: line marked" \
  "${SM_ART_LINE} <ADD>" "$GATE_VERR"
expect_contains "§scaffold-marks (b) …while the absent Files: line IS marked (no instrument either way)" \
  "${SM_FILES_LINE} <ADD>" "$GATE_VERR"

# (c) AC-6.2, THE OTHER DIRECTION. A declared waiver satisfies the artifact's half of the
# same pair: the brief reports by message, so `Expected artifact:` is not something it
# lacks. Its two faults are the ambiguous label and the missing instrument — the
# absent-deliverable wall is waived, which is what the waiver is for.
REPO=$(make_repo rsm-waiver yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: review the wave.
Expected artifact: compare .bionic/docs/record/a-notes.md against .bionic/docs/record/b-notes.md
Deliverable-waiver: nothing durable — this dispatch reports by message
Expected duration: 20 minutes" "smbot3")"
expect_status "§scaffold-marks (c) the waived brief refuses on the several-fault wire" "0" \
  "$([ -n "$GATE_DENY" ] && echo 0 || echo 1)"
expect_absent "§scaffold-marks (c) …and the Expected artifact: line is NOT marked beside a declared waiver" \
  "${SM_ART_LINE} <ADD>" "$GATE_VERR"
expect_absent "§scaffold-marks (c) …nor is the declared Deliverable-waiver: line marked" \
  "${SM_WAIVER_LINE} <ADD>" "$GATE_VERR"
expect_contains "§scaffold-marks (c) …while the absent Files: line IS marked" \
  "${SM_FILES_LINE} <ADD>" "$GATE_VERR"

# (d) AC-6.3 — NEITHER INSTRUMENT DECLARED, BOTH THOSE LINES MARKED. `BRIEF_THREE_FAULTS`
# is §combined's own fixture: `Files:`/`Suites:` are both absent (marked), and
# `Deliverable-waiver:` is absent too (marked). `Expected artifact:` is NOT marked (T26,
# critic Issue 3) — the label was read and rejected as ambiguous, which `dp_scaffold_marked`
# now treats as a populated-but-unresolved label rather than an empty one; the wire's
# `not checked: deliverable, needs one path` line (§combined above) is where that reads.
REPO=$(make_repo rsm-both yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_THREE_FAULTS" "smbot4")"
expect_status "§scaffold-marks (d) the three-fault brief refuses on the several-fault wire" "0" \
  "$([ -n "$GATE_DENY" ] && echo 0 || echo 1)"
expect_absent "§scaffold-marks (d) the still-ambiguous Expected artifact: line is NOT marked" \
  "${SM_ART_LINE} <ADD>" "$GATE_VERR"
expect_contains "§scaffold-marks (d) both absent -> the Deliverable-waiver: line is marked" \
  "${SM_WAIVER_LINE} <ADD>" "$GATE_VERR"
expect_contains "§scaffold-marks (d) neither instrument -> the Files: line is marked" \
  "${SM_FILES_LINE} <ADD>" "$GATE_VERR"
expect_contains "§scaffold-marks (d) neither instrument -> the Suites: line is marked" \
  "${SM_SUITES_LINE} <ADD>" "$GATE_VERR"

# (e)/(f) AC-7.2 (wave-21 T7; REQ-7, D7) — THE OPTIONAL LINE IS NEVER MARKED. The scaffold
# carries `Subprocess claim:` for a task that backgrounds a watcher (a CI wait, `gh run
# watch`); a task that backgrounds nothing omits it, and that is the ordinary case, so its
# absence is never a fault and never an `<ADD>`. (f) reads (d)'s several-fault wire above —
# the brief carries no claim, and every instrument line on that wire IS marked, so an
# unmarked claim line there is the rule, not an accident of a wire that marks nothing. (e)
# is the admit direction: the canonical brief, which carries no claim, passes.
#
# fails-when: the claim line is marked `<ADD>`, missing from the wire, or a brief without
# it is refused.
SM_CLAIM_LINE="$(scaffold_raw_line "$DISPATCH_FILE" "Subprocess claim")"
expect_nonempty "§scaffold-marks meta: the optional Subprocess claim: line was read out of dispatch.md" \
  "$SM_CLAIM_LINE"
expect_contains "§scaffold-marks (f) the several-fault wire renders the optional claim line, as shipped" \
  "${SM_CLAIM_LINE:-<no Subprocess claim: line in the scaffold>}" "$GATE_VERR"
expect_absent "§scaffold-marks (f) …and never marks it, though the brief carries no claim" \
  "${SM_CLAIM_LINE:-<no Subprocess claim: line in the scaffold>} <ADD>" "$GATE_VERR"

REPO=$(make_repo rsm-noclaim yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "smbot5")"
expect_eq "§scaffold-marks (e) a brief with no Subprocess claim: line is ADMITTED" \
  "allow" "$GATE_VERDICT"
expect_absent "§scaffold-marks (e) …and its absence is not an absence finding" \
  "claims" "$(roster_field "$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)" absent)"
# ============================================================================

section "§combined-deny — the combined refusal reaches the MODEL (wave-12 T17, AC-1.1)"
# ============================================================================
#
# WHAT T2 LEFT OPEN (its finding A-T2.2; ruling A-orch-10, 2026-09-13). The five brief-shape
# arms already collect into ONE refusal — and it went out on `exit2`, where refuse.sh's
# channel table ships `detail_to_user=no` under ruling D-1 AND there is only one wire: what
# the user stream carries is what the model's synthetic tool_result carries. So the author
# read one sentence and THE MODEL READ THE SAME ONE SENTENCE. The findings list existed and
# no dispatching model ever saw it, which is the six-attempt loop of 2026-09-13 still
# running behind a better-built wall.
#
# WHAT THIS PINS. The combined refusal goes out on `deny`: a PreToolUse verdict on STDOUT
# whose `permissionDecisionReason` the same measurement proved reaches the model verbatim
# (`model_only=yes`), with exit 0 because the JSON is the block rather than the status. D-1
# is NOT reversed — the human still gets exactly one line on stderr — and the knob is not
# involved anywhere below: these arms run with BIONIC_WALL_VERBOSE unset, which is the state
# a real dispatch runs in.
#
# THE ARM THAT CARRIES THE CLAIM is the last one: attempt two is written from the examples
# read back out of the MODEL'S OWN WIRE, `permissionDecisionReason`, and must dispatch. Three
# facts on a channel the model reads are worth nothing if acting on all three still leaves a
# fault the message never named.
#
# fails-when: the three-fault brief exits 2; or its stdout is not one parseable deny verdict;
# or the reason names fewer than three facts or carries fewer than three `Fix:` blocks; or
# the human's one line grows a detail behind it; or the single-fault brief leaves on a
# different wire (wave-19 T4, REQ-7, D8 — until then this clause read the other way).

expect_empty "§combined-deny the verbose knob is UNSET for every arm here" "${BIONIC_WALL_VERBOSE:-}"

REPO=$(make_repo rcombdeny yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_THREE_FAULTS" "denybot")"

expect_status "§combined-deny a three-fault brief exits 0 — the verdict is the block" \
  "0" "$GATE_ST"
expect_eq "§combined-deny …and the verdict is a deny, not an allow" "deny" "$GATE_VERDICT"
expect_eq "§combined-deny …stdout is ONE object and nothing else" "1" \
  "$(printf '%s\n' "$GATE_OUT" | /usr/bin/grep -c . || true)"
expect_eq "§combined-deny …naming the PreToolUse event it answers" "PreToolUse" \
  "$(printf '%s' "$GATE_OUT" | jq -r '.hookSpecificOutput.hookEventName' 2>/dev/null || echo PARSE-FAILED)"
expect_eq "§combined-deny …with permissionDecision=deny" "deny" \
  "$(printf '%s' "$GATE_OUT" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null || echo PARSE-FAILED)"

# THE REASON IS THE MODEL'S WIRE. Every assertion below reads `$GATE_REASON`, which the
# driver parsed out of the JSON with `jq` — so an escaper that broke on the findings list's
# newlines reads EMPTY here rather than passing on a grep of the raw bytes.
expect_eq "§combined-deny the reason opens with the refusal's one line" \
  "bionic: dispatch refused — the deliverable label names several paths (name exactly one deliverable)" \
  "$(printf '%s\n' "$GATE_REASON" | sed -n '1p')"
# NO RATIONALE ON THE MODEL'S WIRE EITHER (T2, D3/D11) — the marked scaffold replaces it,
# read live out of $DISPATCH_FILE, the same way §combined checks GATE_VERR.
expect_absent "§combined-deny …no fault-count header sentence" "SHAPE FAULTS" "$GATE_REASON"
expect_absent "§combined-deny …no per-fault '── N.' heading" "── " "$GATE_REASON"
expect_absent "§combined-deny …no Fix: block" "Fix: " "$GATE_REASON"
expect_absent "§combined-deny …the still-ambiguous Expected artifact: line is NOT marked <ADD>" \
  "${COMB_ART_LINE} <ADD>" "$GATE_REASON"
expect_contains "§combined-deny …and its not-checked line names the deliverable arm instead" \
  "not checked: deliverable, needs one path" "$GATE_REASON"
expect_contains "§combined-deny …the absent Files: line is marked <ADD>" \
  "${COMB_FILES_LINE} <ADD>" "$GATE_REASON"
expect_contains "§combined-deny …the present Expected duration: line is left exactly as shipped" \
  "$COMB_DURATION_LINE" "$GATE_REASON"
expect_contains "§combined-deny …and closes with the pointer line" \
  "See skills/canonical-sdlc/dispatch.md §Dispatch for why each line is required." "$GATE_REASON"

# AND THE HUMAN IS STILL INTERRUPTED BY ONE SENTENCE (ruling D-1). The split is the whole
# reason this channel was chosen over flipping `detail_to_user`: the model reads everything,
# the reader reads one line, and neither is a setting.
expect_eq "§combined-deny the user stream carries exactly one refusal line" "1" \
  "$(printf '%s\n' "$GATE_ERR" | /usr/bin/grep -c '^bionic: ' || true)"
expect_eq "§combined-deny …the first arm's own sentence, unchanged" \
  "bionic: dispatch refused — the deliverable label names several paths (name exactly one deliverable)" \
  "$(printf '%s\n' "$GATE_ERR" | /usr/bin/grep '^bionic: ')"
expect_absent "§combined-deny …with no findings list behind it" "Fix: " "$GATE_ERR"
expect_absent "§combined-deny …and no count header either" "SHAPE FAULTS" "$GATE_ERR"

# NOTHING WAS LAUNCHED. A deny exits 0, which is the one status a wall must never let mean
# "allowed" by accident: the roster is where that would show.
expect_status "§combined-deny …and journals no roster row" "0" \
  "$(roster_rows "$(roster_path "$REPO" "$SID_A")")"

# ---- the discriminator, INVERTED: a ONE-fault brief takes the same deny wire ----
#
# CHANGED, WITH ATTRIBUTION (wave-19 T4, REQ-7, D8). This arm used to pin the opposite: that
# a single fault stayed on exit2 with an empty stdout, so a change moving every refusal to
# `deny` would red here. Two statuses for one kind of refusal was the defect REQ-7 names —
# a fixture's status depended on how many faults its ENVIRONMENT added (A-T4.8). What the
# arm still protects is the single fault's own SHAPE: its arm's line, unchanged, on the
# user stream, and its arm's own detail — not the pooled list — on the model's wire.
REPO=$(make_repo rcombdeny2 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: build it.
Expected duration: ~15 minutes.
Suites: tests/widget.test.sh" "denybot2")"
expect_eq "§combined-deny a single-fault brief refuses on the same deny wire" "deny" "$GATE_VERDICT"
expect_status "§combined-deny …exiting 0, the verdict being the block" "0" "$GATE_ST"
expect_eq "§combined-deny …stdout is ONE verdict and nothing else" "1" \
  "$(printf '%s\n' "$GATE_OUT" | /usr/bin/grep -c . || true)"
expect_absent "§combined-deny …carrying its arm's own detail, not the pooled scaffold" \
  "See skills/canonical-sdlc/dispatch.md §Dispatch" "$GATE_REASON"
expect_eq "§combined-deny …with its arm's own line, unchanged" \
  "bionic: dispatch refused — this brief names no deliverable (add an Expected artifact: line)" \
  "$(printf '%s\n' "$GATE_ERR" | /usr/bin/grep '^bionic: ')"

# ---- and a LONE refusal is not on the JSON channel either, whatever arm it came from ----
#
# CHANGED, WITH ATTRIBUTION (wave-14 T6, REQ-8/D3, A-T6.4). This arm used to drive
# `BRIEF_THREE_FAULTS` with the Patrol unarmed and assert exit2, on wave-12's reading that
# the channel tracks "a list of BRIEF faults" and a state fault is a different kind of
# thing. REQ-8 overturns that reading: the arming wall now pools with the rest, so that
# fixture carries FOUR faults and the several-fault wire is where all four belong — the
# whole point being that the model reads them in one pass. What the arm was really
# protecting is that a LONE fault keeps its arm's own sentence, its own `exit2` and an empty
# stdout, and that claim is stronger when the lone fault is a STATE one, so that is what it
# drives now: a clean brief whose only defect is the unarmed Patrol. Since wave-19 T4
# (REQ-7, D8) that lone fault's WIRE is the deny verdict too; its sentence is still its own.
REPO=$(make_repo rcombdeny3 yes)
write_attestation "$REPO" "$SID_A"
rm -f "$(s21_stamp_path "$REPO" "$SID_A")"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "denybot3")"
expect_eq "§combined-deny a LONE state fault (the unarmed Patrol) takes the deny wire too" \
  "deny" "$GATE_VERDICT"
expect_eq "§combined-deny …and prints ONE verdict on stdout" "1" \
  "$(printf '%s\n' "$GATE_OUT" | /usr/bin/grep -c . || true)"
expect_contains "§combined-deny …refusing for the state, in the arming wall's own words" \
  "Patrol" "$GATE_ERR$GATE_VERR"

# THE PAIRED CONTROL, and it is the half REQ-8 added: the SAME unarmed Patrol beside brief
# faults is one refusal on the model's wire, naming both kinds. Without this row the arm
# above reads as "state refusals never reach the deny channel", which is what stopped being
# true.
REPO=$(make_repo rcombdeny3b yes)
write_attestation "$REPO" "$SID_A"
rm -f "$(s21_stamp_path "$REPO" "$SID_A")"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_THREE_FAULTS" "denybot3b")"
expect_eq "§combined-deny the same state fault BESIDE brief faults refuses once, on deny" \
  "deny" "$GATE_VERDICT"
expect_eq "§combined-deny …with exactly one refusal line on the user stream" "1" \
  "$(printf '%s\n' "$GATE_ERR" | /usr/bin/grep -c '^bionic: ' || true)"
expect_contains "§combined-deny …the model's wire naming the state fault" \
  "no Patrol stamp exists for this session" "$GATE_REASON"
expect_contains "§combined-deny …and a brief fault beside it" \
  "this brief declares no Files: and no Suites:" "$GATE_REASON"

# ---- the claim: attempt two, written from the MODEL'S wire, dispatches ----
REPO=$(make_repo rcombdeny4 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_THREE_FAULTS" "denybot4")"
DENY_ART=$(fix_example "$GATE_REASON")
DENY_SUITES=$(printf '%s\n' "$GATE_REASON" | /usr/bin/grep -m1 -E '^Suites:' \
  | sed -e 's/[[:space:]]*#.*$//' -e 's/[[:space:]]*<ADD>[[:space:]]*$//' -e 's/[[:space:]]*$//')
expect_status "§combined-deny the reason really recommended an artifact path" "0" \
  "$([ -n "$DENY_ART" ] && echo 0 || echo 1)"
expect_status "§combined-deny …and a Suites: line" "0" \
  "$([ -n "$DENY_SUITES" ] && echo 0 || echo 1)"
expect_absent "§combined-deny …neither carrying a slot the walls themselves refuse" "<" "$DENY_ART"

REPO=$(make_repo rcombdeny5 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: review the wave.
Expected artifact: $DENY_ART
Expected duration: 20 minutes
$DENY_SUITES" "denybot5")"
expect_eq "§combined-deny attempt 2, from the reason alone, is ALLOWED" "allow" "$GATE_VERDICT"
expect_status "§combined-deny …and the recommended path is the contract on the row" \
  "$DENY_ART" "$(roster_field "$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)" deliverable)"


# ============================================================================

section "§scaffold-verbatim — the shipped brief scaffold dispatches as written (AC-2.2)"
# ============================================================================
#
# WHAT THIS PINS. `agents-src/blocks/brief-scaffold.md` renders into seven surfaces, one of
# which is skills/canonical-sdlc/dispatch.md; an orchestrator writes its brief by filling
# that block in. A scaffold whose filled form the gate refuses teaches the wrong grammar to
# every dispatch in the tree, and nothing but a drive can tell you which it is.
#
# THE BLOCK IS READ OUT OF THE SHIPPED FILE, never transcribed here: a copy in this suite
# would go on passing after the source drifted, which is the exact failure this pins against.
# Only two things are done to it — the trailing `  # …` annotations are stripped (they are
# guidance to the author, not brief text) and each `<placeholder>` span is replaced with a
# real value, keeping the label spelling and the surrounding text the file wrote.
#
# fails-when: the rendered scaffold, filled in, is refused by the gate it is written for.

SCAFFOLD_FILE="$DISPATCH_FILE"

# scaffold_block is defined earlier in this file (beside fix_example, ~line 2440), shared
# with §combined/§combined-deny — not redefined here. Both it and scaffold_fill below read
# the file named by $SCAFFOLD_FILE, reassigned for the SKILL.md second pass further down.

scaffold_fill() {  # <suites|files> -> the scaffold as a brief, placeholders filled
  local mode="$1" line label value
  printf 'Your task: build the widget.\n'
  while IFS= read -r line; do
    line="${line%%  #*}"
    line="$(printf '%s' "$line" | sed 's/[[:space:]]*$//')"
    [ -n "$line" ] || continue
    label="${line%%:*}"
    case "$label" in
      "Deliverable-waiver") continue ;;
      "Files")  [ "$mode" = "files" ]  || continue ;;
    esac
    case "$label" in
      "Expected duration") value="20" ;;
      "Expected artifact") value=".bionic/docs/record/w99-scaffold.md" ;;
      "Progress artifact") value=".bionic/docs/record/w99-scaffold.progress" ;;
      "Cadence")           value="15" ;;
      "Files")             value="payload/scripts/lib/widget.sh" ;;
      "Suites")            value="none" ;;
      *)                   value="" ;;
    esac
    case "$line" in
      *"<"*">"*) line="${line%%<*}${value}${line##*>}" ;;
    esac
    printf '%s\n' "$line"
  done < <(scaffold_block "$SCAFFOLD_FILE")
}

# ANTI-VACUITY FIRST: a block that could not be found would make every drive below a drive
# of the two lines this helper prepends, and they would pass.
SCAFFOLD_RAW="$(scaffold_block "$SCAFFOLD_FILE")"
expect_status "§scaffold the shipped dispatch.md really carries a fenced scaffold" "0" \
  "$([ "$(printf '%s\n' "$SCAFFOLD_RAW" | /usr/bin/grep -c .)" -ge 3 ] && echo 0 || echo 1)"
expect_contains "§scaffold …carrying the deliverable label the gate reads" \
  "Expected artifact:" "$SCAFFOLD_RAW"

SCAFFOLD_SUITES="$(scaffold_fill suites)"
SCAFFOLD_FILES="$(scaffold_fill files)"
expect_absent "§scaffold the filled brief leaves no placeholder behind" "<" "$SCAFFOLD_SUITES"
expect_absent "§scaffold …in either variant" "<" "$SCAFFOLD_FILES"
expect_contains "§scaffold …and still spells the labels the way the file does" \
  "Expected artifact: .bionic/docs/record/" "$SCAFFOLD_SUITES"

# ---- variant 1: the waiver form of the instrument line ----
REPO=$(make_repo rscaff1 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$SCAFFOLD_SUITES" "scaffoldbot1")"
expect_status "§scaffold the rendered scaffold, filled in, DISPATCHES" "0" "$GATE_ST"
expect_status "§scaffold …with the named artifact as the contract" \
  ".bionic/docs/record/w99-scaffold.md" \
  "$(roster_field "$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)" deliverable)"

# T17 (R6 finding 3, A-orch-36 walk item 2): a brief built strictly from the scaffold used to
# warn "absent brief field(s): … progress" by construction, because the shipped block had no
# `Progress artifact:`/`Cadence:` line to fill in. The scaffold now carries both, so the
# filled brief leaves nothing absent and the roster row records both fields.
expect_absent "§scaffold …and prints no absent-field warning naming progress (T17)" \
  "absent brief field(s)" "$GATE_ERR"
expect_status "§scaffold …the roster row's progress artifact is filled (T17)" \
  ".bionic/docs/record/w99-scaffold.progress" \
  "$(roster_field "$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)" progress)"
expect_status "§scaffold …and its cadence is filled alongside it (T17)" \
  "15 min" \
  "$(roster_field "$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)" cadence)"

# ---- variant 2: the `Files:` form, its Suites: line beside it (Files: is scope, not a budget) ----
REPO=$(make_repo rscaff2 yes)
write_attestation "$REPO" "$SID_A"
expect_contains "§scaffold the Files: variant carries the scaffold's Suites: line too" \
  "Suites: none" "$SCAFFOLD_FILES"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$SCAFFOLD_FILES" "scaffoldbot2")"
expect_status "§scaffold the Files: variant DISPATCHES" \
  "0" "$GATE_ST"
expect_status "§scaffold …and the budget is the brief's own Suites: line" "none" \
  "$(roster_field "$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)" suites_allowed)"

# ---- the discriminator: the scaffold UNFILLED is refused ----
#
# So "it dispatches" is a fact about the filling, not about a gate that waves anything
# carrying the right labels through.
REPO=$(make_repo rscaff3 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: build the widget.
$SCAFFOLD_RAW" "scaffoldbot3")"
# T23 (review R1): the scaffold's own `Suites: none   # read-only brief; …` comment is no
# longer read as a span of dropped suites, so the unfilled scaffold is once again refused
# for its REAL fault — its deliverable is an unfilled `<…>` slot, which is one fault, which
# is the exit-2 channel (task 12/T17's rule: one fault exits 2, several deny). T6 had
# weakened this to `expect_ne allow` when the comment added a second fault; the channel is
# pinned again, because a channel nobody pins is a channel that drifts.
expect_eq "§scaffold the scaffold with its placeholders still in it is REFUSED" \
  "deny" "$GATE_VERDICT"

# ---- the SECOND home: SKILL.md carries the same scaffold, injected (T2, AC-2.2/AC-2.3) ----
#
# `SKILL.md.tmpl` gained its own `<!-- INJECT: brief-scaffold -->` beside the
# dispatch-pointer sentence, so an orchestrator who never opens dispatch.md still meets a
# fillable scaffold on the page it reads every Step-4 dispatch from. Same drives, same
# extractor, a different file — proof the second copy is byte-identical in shape, not just
# present (docs-pins.test.sh's 131/131b pin presence; this pins that it DISPATCHES).
SCAFFOLD_FILE="${BIONIC_SKILLS_DIR}/canonical-sdlc/SKILL.md"

SCAFFOLD_RAW="$(scaffold_block "$SCAFFOLD_FILE")"
expect_status "§scaffold …and SKILL.md's own copy really carries a fenced scaffold" "0" \
  "$([ "$(printf '%s\n' "$SCAFFOLD_RAW" | /usr/bin/grep -c .)" -ge 3 ] && echo 0 || echo 1)"

SCAFFOLD_SUITES="$(scaffold_fill suites)"

REPO=$(make_repo rscaff4 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$SCAFFOLD_SUITES" "scaffoldbot4")"
expect_status "§scaffold …SKILL.md's rendered scaffold, filled in, DISPATCHES" "0" "$GATE_ST"
expect_status "§scaffold …with the named artifact as the contract" \
  ".bionic/docs/record/w99-scaffold.md" \
  "$(roster_field "$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)" deliverable)"

REPO=$(make_repo rscaff5 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: build the widget.
$SCAFFOLD_RAW" "scaffoldbot5")"
# T23 (review R1): as the dispatch.md variant above — the comment is no longer a drop, the
# one remaining fault is the unfilled deliverable slot, and the exit-2 channel is pinned.
expect_eq "§scaffold …SKILL.md's scaffold, unfilled, is REFUSED the same way" \
  "deny" "$GATE_VERDICT"

# ============================================================================

section "§a3-text — the Patrol stamp is armed at engagement, not by hand (D4, REQ-3)"
# ============================================================================
#
# WHY THE TEXT MOVED. Until this wave the A3 refusal handed the model a two-step re-arm and
# step 2 was `session-poker.sh arm` — a command the operator was expected to type after
# engaging. hooks/engage.sh now runs it itself, with the session id and the project root it
# already holds, right after writing the engagement marker (T4, spec D4). A refusal that
# still ordered the hand step would be instructing the model to do the machine's work, which
# is principle P-A read at its own wall.
#
# THE ARM ITSELF IS UNCHANGED — an absent stamp still refuses, in the same words, and still
# names the CronCreate half, which IS the model's step: engagement writes the stamp, nothing
# but the model can create the recurring job that keeps writing it.
#
# fails-when: the never-armed refusal still names `session-poker.sh arm` as a step to run,
# or stops naming engagement as what writes the stamp.

REPO=$(make_repo ra3 yes)
write_attestation "$REPO" "$SID_A"
rm -f "$(s21_stamp_path "$REPO" "$SID_A")"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_eq "§a3 an absent stamp still refuses the dispatch" "deny" "$GATE_VERDICT"
expect_contains "§a3 …in the same words as before" \
  "bionic: dispatch refused — no Patrol stamp exists for this session" "$GATE_ERR"
expect_contains "§a3 …and the fix names engagement as what writes the stamp" \
  "engage" "$GATE_VERR"
expect_absent "§a3 …and no longer orders the hand-run arm" \
  "session-poker.sh arm" "$GATE_VERR"
expect_contains "§a3 …while still naming the one half the model owns" "CronCreate" "$GATE_VERR"
# LOOK FIRST (wave-21 T7; REQ-1 AC-1.4, the preflight half). A `/clear` or a resume leaves a
# predecessor's job running, and the stop gate's ritual fold refuses a CronCreate that no
# CronList preceded — so a fix that names CronCreate alone walks the model into the next
# refusal. The fix text names CronList, and names it FIRST.
#
# fails-when: the never-armed fix names CronCreate with no CronList before it.
T7_FIX_TEXT="$(printf '%s\n' "$GATE_VERR" | /usr/bin/grep -m1 '^Fix: ' || true)"
expect_contains "§a3 …and the fix line looks before it creates" "Fix: CronList, then CronCreate" \
  "$T7_FIX_TEXT"

# THE PAIRED ARM, and the anti-vacuity one. A4 (armed, then stopped firing) is a different
# finding with a different remedy — the clock died, the stamp did not — and it keeps both
# halves. It also proves the absence above is a fact about A3's text rather than about a
# string this suite can no longer produce at all.
REPO=$(make_repo ra3b yes)
write_attestation "$REPO" "$SID_A"
s21_backdate "$(s21_stamp_path "$REPO" "$SID_A")" 4000
run_gate "$(s21_stale_payload "$SID_A" "$REPO")"
expect_eq "§a3 the STALE arm is untouched by the A3 rewording" "deny" "$GATE_VERDICT"
expect_contains "§a3 …still naming the armed-but-dead state" "stopped firing" "$GATE_ERR"
expect_contains "§a3 …and still offering the hand re-arm, which is A4's remedy" \
  "session-poker.sh arm" "$GATE_VERR"

# ======================== §T22-name-in-flight: A NAME IN FLIGHT IS REFUSED AT DISPATCH
# (T22, A-orch-33; AC-4.4's prevention half.)
#
# THE ROSTER IS THE IDENTITY REGISTER. Two agents of one name in one session is the
# condition every downstream ambiguity was built to survive: the stop gate carried a whole
# arm for it ("several live agents answer to that name"), and a message addressed to a name
# that resolves to two agents reaches the wrong one. The cure is at the door — a name with
# an OPEN row on THIS session's roster is not available, and the FILL line already names a
# free one.
#
# OPEN IS A ROSTER-AND-LEDGER READING (P-A; wave-19 T4, D1, ADR-034; epic-23 wave-20 T2,
# D10). `intended`, `confirmed` and `identified` are open; a name is free again only when a
# sweeper-ledger ack LATER than its last launch closes it — `roster_open_names`, the one
# close predicate every reader calls. A `landing-swept/v1|…|state=MET` marker closes nothing
# (it did here until wave-20, and nowhere else agreed). No transcript, no live set, no tool call: every fixture below leaves the transcript
# in the `none` state deliberately, so a gate that reached for an answer would refuse the
# control rows too.

finish
