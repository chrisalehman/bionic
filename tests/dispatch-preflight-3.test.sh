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
#   dispatch-preflight-4.test.sh   §Q … §RECORDER, and S10h, which §RECORDER reads
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
# A12 outside the repo, A13 no deliverable, A14 no Files:/Suites:, A16 Files: with no
# impact command — no longer refuse where they stand. Each appends its finding (fact, fix
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
# is a SECOND arm keyed on `run.sh` in the derived suite set, so a brief that produces no
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
# never so much as mentions Files:/Suites:/impact-command — proving the pair was read as
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
  "no impact command" "$GATE_ERR$GATE_REASON"

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
      "Suites") [ "$mode" = "suites" ] || continue ;;
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

# ---- variant 2: the `Files:` form, where a derivation exists to consume it ----
REPO=$(make_repo rscaff2 yes)
write_attestation "$REPO" "$SID_A"
s27_impact "$REPO" widget.test.sh
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$SCAFFOLD_FILES" "scaffoldbot2")"
expect_status "§scaffold the Files: variant DISPATCHES where a derivation is configured" \
  "0" "$GATE_ST"
expect_status "§scaffold …and the budget is the derived one" "widget.test.sh" \
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

section "§T22-name-in-flight: a dispatch cannot reuse a name that is still open"

T22NF_NONE="$SANDBOX/.t22nf-none.jsonl"
mk_transcript "$T22NF_NONE" none

# (a) THE REFUSAL. One open `intended` row named `T5`; a dispatch that names `T5` again.
REPO=$(make_repo t22nfa yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=9 suites=9 worktrees=9 test_jobs=4 source=user"
s22_roster_row "$REPO" "$SID_A" "T5"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "T5" "claude-sonnet-5" "$T22NF_NONE")"
expect_eq "t22nfa a name with an open intended row is REFUSED" "deny" "$GATE_VERDICT"
expect_contains "…naming the fact" "that name is in flight" "$GATE_ERR"
expect_contains "…and the fix points at the FILL line" "use the FILL line's name" "$GATE_ERR"
expect_contains "…and the detail names the name and its status" "T5" "$GATE_VERR"

# (b) A CONFIRMED ROW IS OPEN TOO. The three live statuses are one class here.
REPO=$(make_repo t22nfb yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=9 suites=9 worktrees=9 test_jobs=4 source=user"
roster_row_no_plan status=confirmed "session=$SID_A" name=T6 agent_id=aT6-1111111111111111 \
  launched_at=2026-09-02T00:00:00Z subagent_type=implementor model= \
  deliverable=/tmp/d-T6 source=declared "duration=~10 minutes" progress= \
  claims= cadence= absent= waiver= tool_use_id=t-T6 >> "$(roster_path "$REPO" "$SID_A")"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "T6" "claude-sonnet-5" "$T22NF_NONE")"
expect_eq "t22nfb a name with an open confirmed row is REFUSED" "deny" "$GATE_VERDICT"
expect_contains "…naming the same fact" "that name is in flight" "$GATE_ERR"

# (c) AN IDENTIFIED ROW IS OPEN TOO.
REPO=$(make_repo t22nfc yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=9 suites=9 worktrees=9 test_jobs=4 source=user"
roster_row_no_plan status=identified "session=$SID_A" name=T7 agent_id=aT7-2222222222222222 \
  launched_at=2026-09-02T00:00:00Z subagent_type=implementor model= \
  deliverable=/tmp/d-T7 source=declared "duration=~10 minutes" progress= \
  claims= cadence= absent= waiver= tool_use_id=t-T7 >> "$(roster_path "$REPO" "$SID_A")"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "T7" "claude-sonnet-5" "$T22NF_NONE")"
expect_eq "t22nfc a name with an open identified row is REFUSED" "deny" "$GATE_VERDICT"

# (d) THE CONTROL THAT MAKES IT A RULE AND NOT A BAN. The SAME roster, the SAME transcript,
# a DIFFERENT name: allowed. A gate that refused every dispatch once a roster existed would
# pass (a)-(c) and fail here.
REPO=$(make_repo t22nfd yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=9 suites=9 worktrees=9 test_jobs=4 source=user"
s22_roster_row "$REPO" "$SID_A" "T5"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "T5-r2" "claude-sonnet-5" "$T22NF_NONE")"
expect_status "t22nfd the name the FILL line would derive instead is ALLOWED" "0" "$GATE_ST"
expect_absent "…and nothing is said about a name in flight" "in flight" "$GATE_ERR"

# (e) A MET MARKER DOES NOT FREE A NAME (epic-23 wave-20 T2, REQ-10 AC-10.1, D10). Until this
# wave the marker alone freed it here, while the sweeper and the stop wall still counted the
# row open — the MET-not-acked half of triage-C claim 4. The marker records that a landing was
# seen; the agent behind it may still be on the panel. REFUSED.
REPO=$(make_repo t22nfe yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=9 suites=9 worktrees=9 test_jobs=4 source=user"
s22_roster_row "$REPO" "$SID_A" "T8"
s22_sweep "$REPO" "$SID_A" "T8"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "T8" "claude-sonnet-5" "$T22NF_NONE")"
expect_eq "t22nfe a name with a MET marker and no ack is still in flight: REFUSED" "deny" "$GATE_VERDICT"
expect_contains "…naming the fact" "that name is in flight" "$GATE_ERR"
# (e2) …and the ack, once written, frees it: the same roster, one ack's difference.
s22_ack "$REPO" "$SID_A" "T8"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "T8" "claude-sonnet-5" "$T22NF_NONE")"
expect_status "t22nfe2 the same name, acked after its launch, is free to dispatch again" "0" "$GATE_ST"
expect_absent "…and no in-flight refusal" "in flight" "$GATE_ERR"

# (f) ANOTHER SESSION'S ROSTER IS NOT THIS ONE'S REGISTER. The row is planted under SID_B;
# SID_A dispatches the same name and is allowed. Names are unique per SESSION, which is the
# scope every other roster reader in the fleet already uses.
REPO=$(make_repo t22nff yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=9 suites=9 worktrees=9 test_jobs=4 source=user"
s22_roster_row "$REPO" "$SID_B" "T9"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "T9" "claude-sonnet-5" "$T22NF_NONE")"
expect_status "t22nff a predecessor session's row does not reserve the name here" "0" "$GATE_ST"

# (g) AN UNNAMED DISPATCH IS NOT JUDGED BY THIS ARM AT ALL — there is no name to be in
# flight, and an arm that refused one would break every unnamed async dispatch in the fleet.
REPO=$(make_repo t22nfg yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=9 suites=9 worktrees=9 test_jobs=4 source=user"
s22_roster_row "$REPO" "$SID_A" "T5"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "-" "claude-sonnet-5" "$T22NF_NONE")"
expect_absent "t22nfg an unnamed dispatch is never refused for a name in flight" \
  "in flight" "$GATE_ERR"

# (h) THE LANDED-THEN-RELAUNCHED NAME — the case the arm was built for and missed
# (delta review C1/S2). `T5` runs, lands, and its MET marker frees the name; the SAME name
# is then dispatched again (which (e) proves is allowed) and that second lineage reaches
# `identified`. A THIRD dispatch under `T5` while that lineage is live must be refused.
#
# WHY IT NEEDS ITS OWN CASE. `met` was a file-global flag set by ANY marker for the name,
# so one landing turned the arm off for that name for the rest of the session — and (e)'s
# fixture, which stops at the marker, cannot tell a position-blind reading from a
# position-aware one. The rule is that the LATEST contract decides: a marker older than the
# newest intended/confirmed/identified row of that name does not close it.
REPO=$(make_repo t22nfh yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=9 suites=9 worktrees=9 test_jobs=4 source=user"
s22_roster_row "$REPO" "$SID_A" "T5"
roster_row_no_plan status=identified "session=$SID_A" name=T5 agent_id=aT5-1111111111111111 \
  launched_at=2026-09-02T00:00:00Z subagent_type=implementor model= \
  deliverable=/tmp/d-T5 source=declared "duration=~10 minutes" progress= \
  claims= cadence= absent= waiver= tool_use_id=t-T5 >> "$(roster_path "$REPO" "$SID_A")"
s22_sweep "$REPO" "$SID_A" "T5"
# …the relaunch: a fresh contract for the same name, AFTER the marker.
s22_roster_row "$REPO" "$SID_A" "T5"
roster_row_no_plan status=identified "session=$SID_A" name=T5 agent_id=aT5-2222222222222222 \
  launched_at=2026-09-02T01:00:00Z subagent_type=implementor model= \
  deliverable=/tmp/d-T5 source=declared "duration=~10 minutes" progress= \
  claims= cadence= absent= waiver= tool_use_id=t-T5b >> "$(roster_path "$REPO" "$SID_A")"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "T5" "claude-sonnet-5" "$T22NF_NONE")"
expect_eq "t22nfh a name RELAUNCHED after its MET marker is in flight again: REFUSED" \
  "deny" "$GATE_VERDICT"
expect_contains "…naming the fact" "that name is in flight" "$GATE_ERR"
expect_contains "…and the status it names is the LATEST row's, not the first lineage's" \
  "identified" "$GATE_VERR"

# (i) THE PAIRED CONTROL — the same shape, with the relaunch closed by an ack taken AFTER
# it launched (2026-09-02T02:00Z). The latest contract is closed, so the name is free again.
# An arm that never freed a name once it had been open would pass (h) and fail here. (Until
# epic-23 wave-20 T2 the close here was the relaunch's own MET marker; a marker closes
# nothing now, D10, and the marker is kept to show it.)
REPO=$(make_repo t22nfi yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=9 suites=9 worktrees=9 test_jobs=4 source=user"
s22_roster_row "$REPO" "$SID_A" "T5"
s22_sweep "$REPO" "$SID_A" "T5"
s22_roster_row "$REPO" "$SID_A" "T5"
roster_row_no_plan status=identified "session=$SID_A" name=T5 agent_id=aT5-3333333333333333 \
  launched_at=2026-09-02T01:00:00Z subagent_type=implementor model= \
  deliverable=/tmp/d-T5 source=declared "duration=~10 minutes" progress= \
  claims= cadence= absent= waiver= tool_use_id=t-T5c >> "$(roster_path "$REPO" "$SID_A")"
s22_sweep "$REPO" "$SID_A" "T5"
s22_ack "$REPO" "$SID_A" "T5" 2026-09-02T02:00:00Z
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "T5" "claude-sonnet-5" "$T22NF_NONE")"
expect_status "t22nfi a relaunch closed by an ack after it launched frees the name again" "0" "$GATE_ST"
expect_absent "…and no in-flight refusal" "in flight" "$GATE_ERR"

# (j) ADOPTION RE-OPENS A NAME THIS SESSION HAD LANDED — deliberate, and nothing drove it
# (delta review S1; A-T26.2). `contract_note` retires a MET marker on ANY live row of the name
# that follows it, whatever `session=` that row carries — symmetrical with how the marker is
# set, and the reading (h) needs. Its consequence is the case below: `session-poker.sh`'s
# `adopt_write_row` journals a PREDECESSOR session's agent onto THIS session's roster as
# `status=identified` with `adopted_from=`, so a session that ran and landed a `T5` of its own
# and then adopts a predecessor's `T5` has a live `T5` row again, and the next dispatch under
# that name is refused. The refusal is true on its own terms — this register does carry an
# open row of the name — and (j2) is the way out.
REPO=$(make_repo t22nfj yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=9 suites=9 worktrees=9 test_jobs=4 source=user"
s22_roster_row "$REPO" "$SID_A" "T5"
s22_sweep "$REPO" "$SID_A" "T5"
# The ADOPT-SHAPED row, and the one field that separates it from (h)'s ordinary relaunch:
# `adopted_from=` naming the session that launched the agent this one took over.
roster_row_no_plan status=identified "session=$SID_A" name=T5 agent_id=aT5-4444444444444444 \
  launched_at=2026-09-02T01:00:00Z subagent_type=implementor model= \
  deliverable=/tmp/d-T5 source=declared "duration=~10 minutes" progress= \
  claims= cadence= absent= waiver= "adopted_from=$SID_B" tool_use_id=t-T5d \
  >> "$(roster_path "$REPO" "$SID_A")"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "T5" "claude-sonnet-5" "$T22NF_NONE")"
expect_eq "t22nfj an ADOPTED live row re-opens a name this session had landed: REFUSED" \
  "deny" "$GATE_VERDICT"
expect_contains "…naming the same fact" "that name is in flight" "$GATE_ERR"
expect_contains "…and the status it names is the adopted row's" "identified" "$GATE_VERR"

# (j2) THE PAIRED CONTROL, and the recovery — the ACK, the one close since epic-23 wave-20 T2
# (D10; it was the landing marker until then). Acking the adopted row after its launch frees
# the name, exactly as (e2) and (i) free an ordinary one — and without this row (j) is green
# on a wall that refuses the name forever.
s22_ack "$REPO" "$SID_A" "T5" 2026-09-02T02:00:00Z
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "T5" "claude-sonnet-5" "$T22NF_NONE")"
expect_status "t22nfj2 acking the adopted row frees the name again" "0" "$GATE_ST"
expect_absent "…and no in-flight refusal is left" "in flight" "$GATE_ERR"

# (k) A POST-LAUNCH ACK FREES THE NAME (wave-19 T4, REQ-1 AC-1.4, D1; ADR-034).
#
# CHANGED, WITH ATTRIBUTION. Wave-14 T16 drove the opposite here: this arm passed no ack
# ledger to `dp_roster_contracts`, on the premise that an ack was the orchestrator's
# judgement about a DELIVERABLE and could precede the agent leaving. ADR-034 retires that
# premise — the ack is the ONE terminal state of a name, the Patrol writes it only when a
# fresh panel confirms the agent gone, and `stop-orders.sh stopped` writes it beside the
# stop — so this arm now reads the same ledger the budget wall reads (r22mkd), and one
# question has one answer. `ack_closes`'s time test is kept: the ack must be LATER than the
# name's last launch.
#
# fails-when: a dispatch under a name acked after its last launch is refused, or one acked
# before its last launch is admitted (AC-1.4) — (k) is the first half, (l) the second.
REPO=$(make_repo t22nfk yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=9 suites=9 worktrees=9 test_jobs=4 source=user"
s22_roster_row "$REPO" "$SID_A" "T16-k"
s22_ack "$REPO" "$SID_A" "T16-k"
# META, and the anti-vacuity arm: the ack really is on the ledger, under the schema its WRITER
# declares (s22_ack reads `LEDGER_SCHEMA` out of hooks/session-sweeper.sh), and it postdates the
# launch stamp `s22_roster_row` wrote — so (k) below is green because the arm READ it, never
# because the fixture wrote a row no reader counts as open (the refusal (l) proves it is).
expect_contains "t22nfk meta: the ack is on the sweeper's ledger, for this name" \
  "name=T16-k" "$(cat "$REPO/.bionic/tmp/sweeper-$SID_A.state")"
expect_contains "t22nfk meta: …and it postdates the row's launched_at" \
  "at=2026-09-03T00:00:00Z" "$(cat "$REPO/.bionic/tmp/sweeper-$SID_A.state")"
expect_contains "t22nfk meta: …and that launch is 2026-09-02" \
  "launched_at=2026-09-02T00:00:00Z" "$(cat "$(roster_path "$REPO" "$SID_A")")"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "T16-k" "claude-sonnet-5" "$T22NF_NONE")"
expect_status "t22nfk a name acked AFTER its last launch is free: ADMITTED" "0" "$GATE_ST"
expect_eq "t22nfk …on no deny verdict either" "allow" "$GATE_VERDICT"
expect_absent "…and no in-flight refusal" "in flight" "$GATE_ERR$GATE_REASON"

# (l) THE PAIRED CONTROL — AN ACK OLDER THAN THE LAST LAUNCH FREES NOTHING. The same name
# was acked (2026-09-03), then RELAUNCHED (2026-09-04) and that lineage is live. The ack
# predates the live launch, so `ack_closes` declines it and the name is in flight — without
# this row, (k) is green on an arm that frees a name on ANY ack, including the stale one a
# relaunched agent sits behind.
REPO=$(make_repo t22nfl yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=9 suites=9 worktrees=9 test_jobs=4 source=user"
s22_roster_row "$REPO" "$SID_A" "T16-l"
s22_ack "$REPO" "$SID_A" "T16-l"
roster_row_no_plan status=identified "session=$SID_A" name=T16-l agent_id=aT16l-111111111111 \
  launched_at=2026-09-04T00:00:00Z subagent_type=implementor model= \
  deliverable=/tmp/d-T16-l source=declared "duration=~10 minutes" progress= \
  claims= cadence= absent= waiver= tool_use_id=t-T16-l2 >> "$(roster_path "$REPO" "$SID_A")"
expect_contains "t22nfl meta: the ack is on the ledger at 2026-09-03" \
  "at=2026-09-03T00:00:00Z" "$(cat "$REPO/.bionic/tmp/sweeper-$SID_A.state")"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "T16-l" "claude-sonnet-5" "$T22NF_NONE")"
expect_eq "t22nfl a name acked BEFORE its last launch is still REFUSED" "deny" "$GATE_VERDICT"
expect_contains "…naming the fact" "that name is in flight" "$GATE_ERR"
expect_contains "…and the status it names is the relaunch's" "identified" "$GATE_VERR"

section "§one-wire — one exit status for every brief/state refusal, whatever the fault count (wave-19 T4, REQ-7, D8)"
# ============================================================================
#
# THE DEFECT (ideas row 4; A-T4.8; research R3 Q1). `dp_refuse_findings` sent ONE finding out
# on `refuse exit2` (status 2) and SEVERAL on `refuse deny` (status 0 with a deny verdict), so
# a refusal's exit status depended on its fault count — and a fixture's fault count depends
# on its ENVIRONMENT as well as its brief: with no `impact-command:` in .bionic/config.yaml a
# `Files:` brief picks up a second fault silently (dispatch-preflight.sh, the no-impact arm).
# Both rows below therefore pin the config, so each carries exactly the faults it names.
#
# fails-when (AC-7.1): the two-fault brief exits 2 or names one fault, or its one-fault
# control leaves on a different wire. (AC-7.2): this two-fault row is absent.
#
# THE TWO-FAULT ROW: no deliverable, and no Files:/Suites: at all.
REPO=$(make_repo r1wire2 yes)
write_attestation "$REPO" "$SID_A"
s27_impact "$REPO" "tests/widget.test.sh"
expect_contains "1wire2 meta: the impact command is configured" "impact-command:" \
  "$(cat "$REPO/.bionic/config.yaml")"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: build it.
Expected duration: ~15 minutes." "w1wire2")"
expect_status "1wire2 a TWO-fault brief exits 0 — the verdict is the block" "0" "$GATE_ST"
expect_eq "1wire2 …with a deny verdict" "deny" "$GATE_VERDICT"
expect_contains "1wire2 …whose reason names the first fault" \
  "this brief names no deliverable" "$GATE_REASON"
expect_contains "1wire2 …and the second" \
  "this brief declares no Files: and no Suites:" "$GATE_REASON"
expect_status "1wire2 …and journals no roster row" "0" \
  "$(roster_rows "$(roster_path "$REPO" "$SID_A")")"

# THE ONE-FAULT CONTROL: the SAME brief plus a `Files:` line the configured impact command
# answers for, so the deliverable fault is the ONLY one. Same status, same verdict.
REPO=$(make_repo r1wire1 yes)
write_attestation "$REPO" "$SID_A"
s27_impact "$REPO" "tests/widget.test.sh"
expect_contains "1wire1 meta: the impact command is configured" "impact-command:" \
  "$(cat "$REPO/.bionic/config.yaml")"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: build it.
Expected duration: ~15 minutes.
Files: payload/scripts/lib/widget.sh" "w1wire1")"
expect_status "1wire1 a ONE-fault brief exits 0 too — the same wire" "0" "$GATE_ST"
expect_eq "1wire1 …with a deny verdict" "deny" "$GATE_VERDICT"
expect_contains "1wire1 …naming its one fault" "this brief names no deliverable" "$GATE_REASON"
expect_absent "1wire1 …and only that one: the Files: line satisfied the instrument arm" \
  "no Files: and no Suites:" "$GATE_REASON"
expect_absent "1wire1 …nor did a missing impact command add one" \
  "no impact command is configured" "$GATE_REASON"
expect_eq "1wire1 …the user stream is still ONE sentence" "1" \
  "$(printf '%s\n' "$GATE_ERR" | /usr/bin/grep -c '^bionic: ' || true)"
expect_status "1wire1 …and journals no roster row" "0" \
  "$(roster_rows "$(roster_path "$REPO" "$SID_A")")"

section "§three-arms — one refusal names every fault, across arms (wave-14 REQ-8, D3, AC-8.1/AC-8.3)"
# ============================================================================
#
# THE INCIDENT, ONE WAVE ON. Wave-12 T2 pooled the five BRIEF-SHAPE arms and left every
# STATE arm exiting where it stood, on the argument that a broken environment and a typo
# do not belong in one list. The 2026-09-13 loop is the measurement that overturned it:
# the six refusals Chris counted were the arming wall, then the budget, then the suite
# allowance — three DIFFERENT arms, one per attempt, each holding a fact the gate had
# already read. D3 keeps arm 6 (attestation) first and alone, because a repo that cannot
# be written makes every later disk read meaningless, and pools everything else.
#
# fails-when: the refusal names fewer than three faults, or fixing the first alone
# produces a refusal naming a fault the first refusal could have named.

# ONE SHAPE FAULT, not three: BRIEF_THREE_FAULTS would put five faults on the wire and the
# arm below could not tell "the pool works" from "the shape pool works". This is the
# §combined-deny single-fault brief — a declared Suites: and no artifact — so the only
# brief-shape arm that fires is A13.
BRIEF_ONE_SHAPE_FAULT='Your task: build it.
Expected duration: ~15 minutes.
Suites: tests/widget.test.sh'

REPO=$(make_repo r3arms yes)
write_attestation "$REPO" "$SID_A"
rm -f "$(s21_stamp_path "$REPO" "$SID_A")"                      # fault 1: arm 7a, the Patrol
s22_set_budget "$REPO" "writers=1 suites=9 worktrees=9 test_jobs=4 source=user"
s22_roster_row "$REPO" "$SID_A" "W-ONE"                          # fault 2: arm 10, the budget
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_ONE_SHAPE_FAULT" "w3arms")"

expect_eq "§three-arms a brief faulting in three arms is REFUSED" "deny" "$GATE_VERDICT"
expect_eq "§three-arms …exactly once: one refusal line reaches the user" "1" \
  "$(printf '%s\n' "$GATE_ERR" | /usr/bin/grep -c '^bionic: ' || true)"
# THE USER LINE IS THE FIRST ARM'S OWN, unchanged — the Patrol runs first in file order,
# and AC-E1.3 leaves no room on that line for a count or a second fault.
expect_eq "§three-arms …the user line stays the first arm's own sentence" \
  "bionic: dispatch refused — no Patrol stamp exists for this session (CronCreate the Patrol job)" \
  "$(printf '%s\n' "$GATE_ERR" | /usr/bin/grep '^bionic: ')"
# ALL THREE ON THE MODEL'S OWN WIRE. `$GATE_REASON` is parsed out of the deny verdict, so
# what is asserted here is what the model actually reads.
expect_contains "§three-arms …the model's wire names the Patrol fault" \
  "no Patrol stamp exists for this session" "$GATE_REASON"
expect_contains "§three-arms …and the budget fault" \
  "this passes the run's writer budget" "$GATE_REASON"
expect_contains "§three-arms …and the brief-shape fault" \
  "this brief names no deliverable" "$GATE_REASON"

# AC-8.3 — THE LINE BUDGET IS A FORMULA NOW, not a tolerance. Wave-13's cap was ten lines
# (one refusal line, a blank, the seven scaffold lines, a blank, the pointer) and it tracks
# the scaffold's own length by construction; epic-23 wave-16's `Re-executes:` line makes the
# scaffold eight lines and the fixed part eleven (REQ-1 AC-1.8, A-T2.7). REQ-8 adds ONE line
# per ADDITIONAL fault: the first fault is already the user line and costs nothing, faults
# 2..N cost a line each, and so does every `not checked:` line. Three faults, no not-checked
# line: eleven plus two.
# The fixed part is TWELVE since wave-20 T7 (AC-9.3): the prompt-only line sits beside the
# scaffold. Three faults, no not-checked line: twelve plus two.
# The fixed part is THIRTEEN since wave-21 T7 (AC-7.2): the scaffold's ninth line is the
# optional `Subprocess claim:` (§combined holds the nine). Three faults: thirteen plus two.
# The fixed part is FOURTEEN since wave-24 T9 (AC-4.8): the scaffold's tenth line is the
# optional `Done marker:` (§combined holds the ten). Three faults: fourteen plus two.
# The fixed part is NINETEEN since wave-28 T7/T22 (the scaffold's `Row:` and `Lands-on:`); the cap follows (wave-28 T58).
expect_status "§three-arms …and the wire is at most 21 lines (19 + one per additional fault)" "0" \
  "$([ "$(printf '%s' "$GATE_REASON" | wc -l | tr -d ' ')" -le 21 ] && echo 0 || echo 1)"
# NOT VACUOUS: a wire that named nothing extra would also be under the cap. It has to have
# GROWN by exactly the two lines the two extra faults bought.
# MOVED WITH THE FIXED PART (wave-21 T7; wave-24 T9; wave-28 T76): a wire that grew by nothing is the
# nineteen-line fixed part, 19 newlines, and the two extra faults bought two more: 21, measured. The floor that
# proves growth is that 21, which the cap above holds from the other side. It sat at fifteen, four under the
# fixed part, and passed a wire that had grown by nothing.
echo "      measured: the three-arm wire is $(printf '%s' "$GATE_REASON" | wc -l | tr -d ' ') newlines"
expect_status "§three-arms …and it really grew: the nineteen-line fixed part and the two lines the extra faults bought" "0" \
  "$([ "$(printf '%s' "$GATE_REASON" | wc -l | tr -d ' ')" -ge 21 ] && echo 0 || echo 1)"
# THE SHAPE BANS OF WAVE-13 STAND: no per-fault heading, no fault-count sentence, no
# stacked `Fix:` paragraphs. One line per fault is a LINE, not a section.
expect_absent "§three-arms …no fault-count header sentence" "SHAPE FAULTS" "$GATE_REASON"
expect_absent "§three-arms …no per-fault '── N.' heading" "── " "$GATE_REASON"
expect_absent "§three-arms …and no stacked Fix: blocks" "Fix: " "$GATE_REASON"
# THE FIXTURE'S OWN ROW STANDS AND NOTHING WAS ADDED TO IT. A refused dispatch is not a
# launch, however many arms it faulted in — and the budget fixture above wrote exactly one.
expect_status "§three-arms …and appends no row for the refused dispatch" "1" \
  "$(roster_rows "$(roster_path "$REPO" "$SID_A")")"

# ---- THE CLAIM: fixing the first fault surfaces NOTHING the first refusal withheld ----
#
# This is the arm that makes the section mean something. Arm the Patrol and dispatch the
# same brief into the same repo: the refusal must name the remaining two and must not
# name a THIRD that was readable all along.
write_attestation "$REPO" "$SID_A"
printf 'armed\n' > "$(s21_stamp_path "$REPO" "$SID_A")"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_ONE_SHAPE_FAULT" "w3arms2")"
expect_eq "§three-arms attempt 2, the Patrol armed, is still refused" "deny" "$GATE_VERDICT"
expect_absent "§three-arms …and the Patrol fault is gone" \
  "no Patrol stamp exists for this session" "$GATE_REASON"
expect_contains "§three-arms …naming the budget fault the first refusal already named" \
  "this passes the run's writer budget" "$GATE_REASON"
expect_contains "§three-arms …and the brief-shape fault it already named too" \
  "this brief names no deliverable" "$GATE_REASON"

# ---- AND ONE FAULT IS STILL ONE SENTENCE, on the one wire ----
#
# The discriminator wave-12 T17 installed kept a LONE state refusal off the JSON wire;
# wave-19 T4 (REQ-7, D8) retired that half, so every brief or state fault leaves as a deny
# verdict. What stays pinned is the sentence: a clean brief with nothing wrong but the
# Patrol refuses in the arming wall's own words, one verdict on stdout.
REPO=$(make_repo r3arms3 yes)
write_attestation "$REPO" "$SID_A"
rm -f "$(s21_stamp_path "$REPO" "$SID_A")"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w3arms3")"
expect_eq "§three-arms a LONE state fault refuses on the deny wire" "deny" "$GATE_VERDICT"
expect_eq "§three-arms …printing ONE verdict on stdout" "1" \
  "$(printf '%s\n' "$GATE_OUT" | /usr/bin/grep -c . || true)"
expect_eq "§three-arms …in the arming wall's own words, unchanged" \
  "bionic: dispatch refused — no Patrol stamp exists for this session (CronCreate the Patrol job)" \
  "$(printf '%s\n' "$GATE_ERR" | /usr/bin/grep '^bionic: ')"

section "§not-checked — a dependent arm says so, rather than going quiet (wave-14 REQ-8, AC-8.2)"
# ============================================================================
#
# SOME ARMS GENUINELY CANNOT ANSWER until an earlier one has produced something. The
# full-run wall reads `SUITES_ALLOWED` for `run.sh`; a brief that declares neither
# `Files:` nor `Suites:` produces no set at all, so the wall has nothing to read. Silence
# there is the thing AC-8.2 forbids: the author fixes the pooled faults, dispatches again,
# and meets a refusal the gate could have TOLD them was coming. The shape is the one the
# budget wall's per-field reading already uses — name the arm, name what it needs.
#
# fails-when: a dependent arm is silently skipped.

BRIEF_NO_SET='Your task: review the wave.
Expected duration: 20 minutes.'

REPO=$(make_repo rnotchk yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_NO_SET" "wnotchk")"
expect_eq "§not-checked a brief with no Files: and no Suites: is refused" "deny" "$GATE_VERDICT"
expect_contains "§not-checked …naming the suite-allowance fault" \
  "this brief declares no Files: and no Suites:" "$GATE_REASON"
expect_contains "§not-checked …and saying the full-run wall was not checked, and why" \
  "not checked: full-run, needs a suite set" "$GATE_REASON"
# THE CONTROL, and it is what stops this from pinning a constant string. It has to be a
# refusal on the SAME wire — two faults, so the several-fault wire is what is read — over a
# brief that DOES declare a suite set, which leaves the full-run wall checkable. An
# unarmed Patrol supplies the second fault without touching the brief.
REPO=$(make_repo rnotchk2 yes)
write_attestation "$REPO" "$SID_A"
rm -f "$(s21_stamp_path "$REPO" "$SID_A")"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_ONE_SHAPE_FAULT" "wnotchk2")"
expect_eq "§not-checked control: a two-fault brief that DECLARES Suites: is refused too" \
  "deny" "$GATE_VERDICT"
expect_absent "§not-checked …with no not-checked line for a wall that COULD be checked" \
  "not checked: full-run" "$GATE_REASON"

section "§slow-impact — a slow derivation is admitted, and derives the same set (wave-14 REQ-7, AC-7.1)"
# ============================================================================
#
# THE STANDING WORKAROUND THIS RETIRES. `IMPACT_BOUND_S` was six seconds and
# tests/lib/impact.sh cost 4.2 s at quiet load, so an ordinary dispatch under load 8-12
# took 5.6 s and was refused for the cost of asking its own question (A-orch-46). The
# operator's answer was to declare `Suites:` by hand on every dispatch during a floor.
# The bound is a HANG GUARD now (lib/bounds.sh), the cost is gone to T9's cache, and a
# derivation that merely takes 5.6 s is admitted.
#
# THE SLEEP IS THE LOAD. AC-7.1 states the cost in seconds; a load generator would prove
# the same thing with a fixture nobody can run twice the same way. What matters is that
# the gate waits for a derivation of that length and records its answer.
#
# fails-when: the loaded case is refused with the bound line, or the two derived sets differ.
REPO=$(make_repo rslowimp yes)
write_attestation "$REPO" "$SID_A"
s29_impact "$REPO" 5.6
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FILES" "w-slow-imp")"
expect_status "§slow-impact a 5.6s derivation is ADMITTED" "0" "$GATE_ST"
expect_absent "§slow-impact …with no bound line anywhere on the wire" "bound:" "$GATE_ERR"
SLOW_SET="$(roster_field "$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)" suites_allowed)"
expect_eq "§slow-impact …and the row carries the derivation's own answer" "alpha.test.sh" "$SLOW_SET"

# ---- THE PAIRED ARM (T29, AC-7.1 discrimination) ----
#
# WHY THE ARM ABOVE PROVES NOTHING ALONE. §slow-impact's claim is that the SHIPPED bound
# (10s since T35's D1 move, 20s as T9/D4 first set it) is what admits a 5.6s derivation —
# not that any bound would. At the
# superseded 6s bound the same 5.6s sleep cleared by only 0.4s, so this section passed
# there too (T6-one-refusal.md §3; auditor finding AC-7.1, UNVERIFIABLE at d3930dd): the
# observation is identical with the bound move absent. The missing control is the SAME
# 5.6s derivation, on the SAME fixture, forced under a bound BELOW the sleep — it must
# refuse, and its refusal must name the forced number, or the override never reached the
# arm and any refusal it produced would be refusing for some unrelated reason.
#
# HOW THE BOUND IS FORCED. dispatch-preflight.sh sources lib/bounds.sh only when
# IMPACT_BOUND_S is unset (`[ -z "${IMPACT_BOUND_S:-}" ]`, :2509) — an env value already
# set on entry wins and the library is never read. GATE_ENV is the driver's own channel
# for exactly this (see probe_env_on above, which does the same thing for
# ANTHROPIC_API_KEY and HOME); saved and restored around the one call so no later arm in
# this file inherits a forced bound.
#
# WHY 5 AGAINST 5.6 IS A REAL MARGIN NOW, AND WAS NOT (wave-14 T34). As written this arm
# was a coin flip, green at T29's head and red at 89f6944's on the same machine at lower
# load. Nothing about the override was at fault — instrumentation caught the arm reading
# `bound=5` exactly as intended — but the gate spent that bound as fifty `sleep 0.1` polls
# costing 115 ms each, so the "5 second" wait ran 5.77 s against a 5.6 s derivation and the
# fixture won about half the time. The wait is a wall-clock one now and ends in
# [4 s, 5 s], which is 0.6 s clear of the sleep and, being a clock, does not narrow under
# load. The 0.4 s the arm was written with was never the margin it looked like; measure
# before shortening it further.
#
# fails-when: the forced-5s call is ADMITTED, or its refusal does not name the forced
# number (`bound:   5s`, the arm's own wire spacing — a wire naming a different number
# would mean the override never reached the arm at all).
_S29_GATE_ENV_SAVE="$GATE_ENV"
GATE_ENV="$GATE_ENV IMPACT_BOUND_S=5"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FILES" "w-slow-imp-forced5")"
GATE_ENV="$_S29_GATE_ENV_SAVE"
expect_eq "§slow-impact …the SAME 5.6s derivation, forced to a 5s bound, is REFUSED" \
  "deny" "$GATE_VERDICT"
expect_contains "§slow-impact …naming the FORCED bound, proving the override reached the arm" \
  "bound:   5s" "$GATE_VERR"
# THE ROSTER IS THE CONTROL: still exactly the one row the ADMITTED call above wrote —
# not two, which would mean the forced-bound call was admitted after all and only the
# assertion above was wrong.
expect_status "§slow-impact …and journalled no row for the refused dispatch" \
  "1" "$(roster_rows "$(roster_path "$REPO" "$SID_A")")"

# THE SAME DISPATCH AT QUIET LOAD, same set. This is AC-7.1's second half: the derived set
# is a property of the tree and the brief, never of how long the machine took to say it.
REPO=$(make_repo rslowimp2 yes)
write_attestation "$REPO" "$SID_A"
s29_impact "$REPO" 0
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FILES" "w-quiet-imp")"
expect_status "§slow-impact control: the same brief with no sleep is admitted too" "0" "$GATE_ST"
expect_eq "§slow-impact …and derives the SAME set" "$SLOW_SET" \
  "$(roster_field "$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)" suites_allowed)"

section "§hanging-impact — a hang is still bounded, and the bound is named (wave-14 REQ-7, AC-7.2)"
# ============================================================================
#
# WHAT IS LEFT FOR A BOUND TO DO once the cost is cached: an impact command that never
# returns. A hook killed on the CLI's own timeout does NOT exit 2 — the dispatch proceeds
# with no roster row and therefore no budget at all — so the wait has to end on OUR terms,
# strictly inside the registration hooks/hooks.json gives this hook (§L.4c in
# cross-gate-agreement pins the pair; both numbers are read from their own files).
#
# NO SEAM. The bound is the shipped constant, read from lib/bounds.sh; the fixture simply
# outruns it. A test that shortened the bound would prove a value it had itself supplied.
#
# fails-when: the preflight waits past the stated bound, or the refusal does not name it.
BOUND_S="$(bash -c '. "$1" 2>/dev/null && printf "%s" "${IMPACT_BOUND_S:-}"' _ \
  "${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/bounds.sh" 2>/dev/null)"
expect_nonempty "§hanging-impact the shipped bound is readable from lib/bounds.sh" "$BOUND_S"

REPO=$(make_repo rhangimp yes)
write_attestation "$REPO" "$SID_A"
s29_impact "$REPO" 60
GATE_HIRES=1
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FILES" "w-hang-imp")"
GATE_HIRES=""
HANG_ELAPSED="$GATE_TIME_CS"
expect_eq "§hanging-impact a 60s derivation is REFUSED" "deny" "$GATE_VERDICT"
expect_contains "§hanging-impact …naming the bound it outran, as the library defines it" \
  "${BOUND_S}s" "$GATE_VERR"
# THE CLOCK IS THE CLAIM. `$GATE_TIME_CS` is the first drive alone (run_gate drives a
# second time under the verbose knob, which would double any number read across both).
# ONE SECOND OF SLACK, NOT EIGHT, AND READ IN HUNDREDTHS — the same re-pinning as 29a, for
# the same reason and against the same defect (wave-14 T34): the tick-counted wait ran
# 23.0-23.2s here too, and a whole-second clock with eight seconds of slack called it fine.
if [ "$HANG_ELAPSED" -le $(( (BOUND_S + 1) * 100 )) ]; then
  ok "§hanging-impact …and it stopped waiting at the bound, not at the sleep ($(( HANG_ELAPSED / 100 )).$(printf '%02d' $(( HANG_ELAPSED % 100 )))s)"
else
  no "§hanging-impact …and it stopped waiting at the bound, not at the sleep" \
    "took $(( HANG_ELAPSED / 100 )).$(printf '%02d' $(( HANG_ELAPSED % 100 )))s against a ${BOUND_S}s bound"
fi
expect_status "§hanging-impact …and journalled no row at all" \
  "0" "$(roster_rows "$(roster_path "$REPO" "$SID_A")")"

section "§bound-one-owner — the derivation bound is defined once, fleet-wide (wave-14 REQ-7, AC-7.4)"
# ============================================================================
#
# T9's own suite pins the LIBRARY's half (tests/stop.test.sh §6). This is the other half,
# and the one AC-7.4 names: the preflight carried its own `IMPACT_BOUND_S=6` under its own
# header, so the two legs of the fleet meant different things by "bounded" while each
# message quoted its own number.
#
# THE REAL PATHS, NOT `payload/`. `payload/hooks` is a symlink to `../hooks`, and grep -r
# does not descend through a symlinked directory met during recursion — AC-7.4's own
# spelling over `payload/` cannot see this file's definition at all and would report one
# while two existed (T9 report §6).
#
# A DEFINITION IS A LITERAL NUMBER. A line that READS the constant — the wait's own
# `[ "$SECONDS" -ge "$IMPACT_BOUND_S" ]` — is not counted; that distinction is the whole of
# what "defined in two places" means.
#
# TWO BOUNDS, ONE OWNER EACH (re-spelled by wave-14 T16 against T15). This arm counted every
# definition matching `[A-Z_]*IMPACT_BOUND_S=`, which was one until T15 landed
# `LG_IMPACT_BOUND_S=6` — the LANDING GATE's bound, a different number that moves for a
# different reason (lib/bounds.sh states both, and tests/stop.test.sh §6 owns that one). The
# loose prefix read T15's ratified second constant as a second definition of THIS one. So the
# count below is of the exact name, and the arm under it keeps the intent the prefix was there
# for: no hook re-spells a derivation bound under its own header, whatever it calls it — every
# `*IMPACT_BOUND_S=` definition in the fleet lives in lib/bounds.sh, and there are exactly two.
DP_BOUND_DEFS="$(/usr/bin/grep -rnE '^[[:space:]]*IMPACT_BOUND_S=[0-9]' \
  "${BIONIC_SCRIPTS_DIR}/hooks" "${BIONIC_SCRIPTS_DIR}/payload/scripts" 2>/dev/null)"
expect_eq "§bound-one-owner exactly one numeric definition across hooks/ and payload/scripts/" \
  "1" "$(printf '%s\n' "$DP_BOUND_DEFS" | /usr/bin/grep -c . )"
expect_contains "§bound-one-owner …and it is the one in lib/bounds.sh" "lib/bounds.sh" "$DP_BOUND_DEFS"
DP_BOUND_ANY="$(/usr/bin/grep -rnE '^[[:space:]]*[A-Z_]*IMPACT_BOUND_S=[0-9]' \
  "${BIONIC_SCRIPTS_DIR}/hooks" "${BIONIC_SCRIPTS_DIR}/payload/scripts" 2>/dev/null)"
expect_eq "§bound-one-owner …and NO other file defines a bound under any prefix" "0" \
  "$(printf '%s\n' "$DP_BOUND_ANY" | /usr/bin/grep -v '/lib/bounds\.sh:' | /usr/bin/grep -c . )"
expect_eq "§bound-one-owner …lib/bounds.sh owning exactly the two the fleet has (T15's is the second)" \
  "2" "$(printf '%s\n' "$DP_BOUND_ANY" | /usr/bin/grep -c '/lib/bounds\.sh:')"
# THE WAIT MOVED WITH THE DERIVATION (wave-20 T6; REQ-4, Δ10). The dispatch wall's derivation
# is `brief_validate_fields` in payload/scripts/lib/brief.sh now, the contract grammar `amend`
# and `task-add` call too, so the READ of the bound and the source of lib/bounds.sh are that
# file's. These rows follow them there; what they assert about the bound is unchanged.
DP_GRAMMAR="${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/brief.sh"
# NOT VACUOUS: the sweep reaches the grammar, whose READ it declines to count.
expect_nonempty "§bound-one-owner the sweep reaches lib/brief.sh, whose READ is uncounted" \
  "$(/usr/bin/grep -rn 'IMPACT_BOUND_S' "${BIONIC_SCRIPTS_DIR}/payload/scripts" 2>/dev/null \
     | /usr/bin/grep 'lib/brief.sh')"
DP_GATE_SRC="$(cat "$DP_GRAMMAR")"
expect_nonempty "§bound-one-owner the dispatch wall's grammar sources lib/bounds.sh" \
  "$(/usr/bin/grep -nE '^[[:space:]]*(\.|source)[[:space:]]+.*bounds\.sh' "$DP_GRAMMAR")"
# RE-SPELLED ONTO THE CLOCK (wave-14 T34). This pair used to read the hook's tick budget,
# `IMPACT_BOUND_TICKS=$(( IMPACT_BOUND_S * 10 ))`, and assert it was DERIVED from the
# constant rather than typed as a second literal. The budget is gone: a count of `sleep
# 0.1` polls cost 115 ms a poll, so spending it waited ~1.15x the bound the refusal quoted
# (T34 §2-3), and the wait now ends on `SECONDS` against the constant itself. The intent
# survives intact and gets stronger — the strongest form of "not a second number" is no
# second number at all — so the positive arm reads the stop condition and the negative one
# stands guard over the mechanism that was removed.
expect_regex "§bound-one-owner …and its wait ends on the constant itself, not on a derived second number" \
  '\[[[:space:]]*"\$SECONDS"[[:space:]]*-ge[[:space:]]*"\$IMPACT_BOUND_S"[[:space:]]*\]' "$DP_GATE_SRC"
expect_no_regex "§bound-one-owner …leaving no tick budget behind to drift against it" \
  '^[[:space:]]*IMPACT_BOUND_TICKS=' "$DP_GATE_SRC"

# ============================================================================

section "S32: the full-run wall is silent where it has nothing to judge (wave-26 D6)"
# ============================================================================
#
# THE FLOOR-ONCE ARM IS FOLDED INTO S28's WALL. Its question ("is the work being proved
# finished?") survives as the open-writer hold §PROOF-UNBOUNDED drives; its override, a
# `regression-cause:` line, does not. What stays here is the half S28 does not drive: the
# briefs and sessions the arm never speaks to, the not-checked line, and the one-parser pins.
#
# fails-when: a non-full-run brief or an unbound session is touched by this arm; a brief with
# no suite set leaves it silent; the hook grows a second Tasks parser.

S32_FLOOR_BRIEF='Your task: run the tests floor.
Expected artifact: .bionic/docs/record/w32-floor.log
Expected duration: ~40 minutes.
Suites: tests/run.sh'

S32_NARROW_BRIEF='Your task: fix the widget.
Expected artifact: .bionic/docs/record/w32-widget.md
Expected duration: ~15 minutes.
Suites: tests/widget.test.sh'

# THE CONTROL FIRST: on this very ledger the full-run brief is refused, so the silent rows
# below discriminate on the brief and the binding, not on a ledger that holds nothing.
REPO=$(pf_repo r32a)
write_attestation "$REPO" "$SID_A"
# (wave-26 T52, R1: a writer holds the floor only when the floor waits on it, so the ledger
# carries the verify row that depends on T3.)
pf_plan "$REPO" "" "$(pf_row T3 4 pending payload/scripts/lib/widget.sh)" \
  "$(pf_row T12 5 pending .bionic/docs/record/w32-floor.log verify T3)"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$S32_FLOOR_BRIEF" "w32-floor")"
expect_eq "32a control: a full-run brief over an open tracked-file writer is refused" "deny" "$GATE_VERDICT"
expect_contains "32a …naming the writer" "T3" "$(pf_line)"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$S32_NARROW_BRIEF" "w32-narrow")"
expect_eq "32f a brief that does not name tests/run.sh is untouched by this arm" "allow" "$GATE_VERDICT"
expect_absent "32f …silently" "write tracked files" "$GATE_ERR"

# NO BOUND PLAN AT ALL: no proof record to read and no ledger.
REPO=$(make_repo r32h yes)
write_attestation "$REPO" "$SID_A"
rm -rf "$REPO/.bionic/docs/plans"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$S32_FLOOR_BRIEF" "w32-unbound")"
expect_eq "32h an unbound session admits the full run" "allow" "$GATE_VERDICT"
expect_absent "32h …silently" "write tracked files" "$GATE_ERR"

# ---- and the arm says so when it cannot answer (wave-14 AC-8.2's shape) ----
REPO=$(make_repo r32i yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" 'Your task: review the wave.
Expected duration: 20 minutes.' "w32-no-set")"
expect_contains "32i a brief with no suite set leaves this arm unable to answer, and it says so" \
  "not checked: full-run, needs a suite set" "$GATE_REASON"
expect_absent "32i …once, under one name: the two retired arm names are gone" \
  "not checked: floor-once" "$GATE_REASON"

# ---- one Tasks parser, and it is the library's ----
S32_HOOK="$GATE"
expect_status "32j the hook reads the ledger through units_rows" "yes" \
  "$([ "$(/usr/bin/grep -c 'units_rows' "$S32_HOOK")" -ge 1 ] && echo yes || echo no)"
expect_status "32j …and declares units.sh in its own BIONIC_LIB_WANT" "yes" \
  "$(sed -n 's/^BIONIC_LIB_WANT="\(.*\)"$/\1/p' "$S32_HOOK" | head -1 \
     | tr ' ' '\n' | /usr/bin/grep -qx 'units.sh' && echo yes || echo no)"
# NO SECOND TABLE PARSER. The hook has carried exactly one split-on-pipe since epic-16: a
# roster-state LINE reader (since D10 the name-in-flight arm's status label), which is not a
# markdown table. The count stays at one, that one is the roster reader, and nothing in this
# hook scans for a `## Tasks` heading.
expect_eq "32j …and carries exactly one awk split on a pipe, the roster-line reader" \
  "1" "$(/usr/bin/grep -cE 'split\([^)]*\|' "$S32_HOOK")"
expect_contains "32j …which splits a roster LINE, not a markdown table" \
  "split(line, parts" "$(/usr/bin/grep -hE 'split\([^)]*\|' "$S32_HOOK")"
expect_eq "32j …and no arm of this hook scans for a ## Tasks heading of its own" \
  "0" "$(/usr/bin/grep -cE '/\^#+ *Tasks/' "$S32_HOOK")"

# ============================================================================

section "S33: an auditor brief may not waive Suites: (REQ-4 AC-4.3/AC-4.4, D6)"
# ============================================================================
#
# THE INCIDENT THIS ARM PREVENTS. `Suites: none` is a legitimate waiver for a role
# that never runs a suite at all — a researcher reads, a test-runner reports — and
# both pass through this wall unchanged. An auditor's Step-5 job is to FALSIFY the
# matrix's evidence, which for a hermetic-tier row means RE-RUNNING the suite the
# row names; an auditor brief that waives every suite has nothing to re-run.
#
# ROLE MATCHED WHOLE, ON subagent_type — never on the brief's prose (handoff rule).
# Both spellings this repo's briefs actually carry are covered: the fully-qualified
# `bionic:auditor` and the bare `auditor`.
#
# fails-when: an auditor brief with Suites: none is admitted; a researcher or
# test-runner brief with Suites: none is refused by THIS arm; an auditor brief that
# names real suites is refused by this arm.

S33_WAIVED_BRIEF='Your task: audit the wave-99 matrix.
Expected artifact: .bionic/docs/record/w33-audit.md
Expected duration: ~30 minutes.
Questions: evidence
Suites: none'

S33_DECLARED_BRIEF='Your task: audit the wave-99 matrix.
Expected artifact: .bionic/docs/record/w33-audit2.md
Expected duration: ~30 minutes.
Questions: evidence
Suites: tests/widget.test.sh, tests/gadget.test.sh'

# ---- AC-4.3: bionic:auditor + Suites: none is refused, fix names the suites ----
REPO=$(make_repo r33a yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$S33_WAIVED_BRIEF" "w33-auditor" \
                             "claude-sonnet-5" "$S5_LIVE_TRANSCRIPT" "bionic:auditor")"
expect_eq "33a a bionic:auditor brief with Suites: none is REFUSED" "deny" "$GATE_VERDICT"
expect_contains "33a …the one line names the fault" \
  "auditor" "$(printf '%s\n' "$GATE_ERR" | /usr/bin/grep '^bionic: ')"
expect_contains "33a …and the fix names what to declare" \
  "name one suite or run" "$(printf '%s\n' "$GATE_ERR" | /usr/bin/grep '^bionic: ')"
expect_status "33a …and no roster row was journalled for the refused dispatch" \
  "0" "$(roster_rows "$(roster_path "$REPO" "$SID_A")")"

# ---- AC-4.3: the bare role word ("auditor", no bionic: prefix) is caught too ----
REPO=$(make_repo r33b yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$S33_WAIVED_BRIEF" "w33-auditor-bare" \
                             "claude-sonnet-5" "$S5_LIVE_TRANSCRIPT" "auditor")"
expect_eq "33b a bare 'auditor' subagent_type with Suites: none is REFUSED too" \
  "deny" "$GATE_VERDICT"

# ---- AC-4.3: the CONTROL — an auditor brief that names real suites passes ----
REPO=$(make_repo r33c yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$S33_DECLARED_BRIEF" "w33-auditor-ok" \
                             "claude-sonnet-5" "$S5_LIVE_TRANSCRIPT" "bionic:auditor")"
expect_status "33c control: an auditor brief that DECLARES suites PASSES" "0" "$GATE_ST"
expect_absent "33c …with no refusal printed" "BLOCKED" "$GATE_ERR"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "33c …and the row carries the declared set" \
  "widget.test.sh gadget.test.sh" "$(roster_field "$ROW" suites_allowed)"

# ---- AC-4.4: the two other reading roles are UNCHANGED by this arm ----
for _role in bionic:researcher bionic:test-runner; do
  REPO=$(make_repo "r33d-${_role##*:}" yes)
  write_attestation "$REPO" "$SID_A"
  run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$S33_WAIVED_BRIEF" "w33-reader" \
                               "claude-sonnet-5" "$S5_LIVE_TRANSCRIPT" "$_role")"
  expect_status "33d a ${_role} brief with Suites: none is UNCHANGED — still admitted" \
    "0" "$GATE_ST"
done

# ---- AC-4.1 end-to-end (T4): a not-yet-existing tests/*.test.sh under Files: gets
# its self edge on the roster row, driven through the REAL tests/lib/impact.sh (the
# tool T4 changed) rather than the S27 stub — this row proves the two tasks meet.
# BIONIC_IMPACT_CACHE_DIR is forced empty so the real tree's own impact-cache under
# .bionic/tmp is never written to by this fixture run (impact.sh's own contract for
# turning the cache off).
s33_real_impact() {  # <repo> — point .bionic/config.yaml at the real impact.sh
  mkdir -p "$1/.bionic"
  printf 'impact-command: env BIONIC_IMPACT_CACHE_DIR= bash %s/tests/lib/impact.sh\n' \
    "${BIONIC_SCRIPTS_DIR}" > "$1/.bionic/config.yaml"
}

S33_NEWSUITE_BRIEF='Your task: add a brand-new suite.
Expected artifact: .bionic/docs/record/w33-newsuite.md
Expected duration: ~20 minutes.
Files: tests/brand-new.test.sh'

REPO=$(make_repo r33e yes)
write_attestation "$REPO" "$SID_A"
s33_real_impact "$REPO"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$S33_NEWSUITE_BRIEF" "w33-newsuite")"
expect_status "33e a Files: tests/brand-new.test.sh (absent) brief is ADMITTED" "0" "$GATE_ST"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_contains "33e …and the roster row's suites_allowed carries the new suite's self edge" \
  "brand-new.test.sh" "$(roster_field "$ROW" suites_allowed)"
# THE ANSWER IS ASKED, NOT WRITTEN DOWN (wave-27 T72; A-orch-146). A fixed list went red on every
# tree that gained a suite naming tests/: the real impact command is asked at run time, as the
# wall asks it (the same command and cache setting, in the fixture's root), and joined as the row
# joins it, so the row follows the tree and still goes red when the wall derives anything else.
S33E_WANT=$(cd "$REPO" && env BIONIC_IMPACT_CACHE_DIR= bash "${BIONIC_SCRIPTS_DIR}/tests/lib/impact.sh" \
  tests/brand-new.test.sh 2>/dev/null | awk -F'\t' '$1 != "" { print $1 }' | sort -u | tr '\n' ' ')
S33E_WANT="${S33E_WANT% }"
expect_contains "33e …the real impact command's answer holds the new suite's self edge" "brand-new.test.sh" "$S33E_WANT"
expect_eq "33e …and at least one other suite beside it" "ok" \
  "$([ "$(printf '%s\n' $S33E_WANT | /usr/bin/grep -vcx 'brand-new.test.sh')" -ge 1 ] && echo ok || echo "only: $S33E_WANT")"
expect_status "33e …the derived set is exactly the real tree's answer" \
  "$S33E_WANT" "$(roster_field "$ROW" suites_allowed)"
expect_status "33e …and the row says the set was DERIVED, not declared" \
  "derived" "$(roster_field "$ROW" suites_source)"

section "§runs-lift — a brief declares what it will RUN, in any runner (REQ-1, D1, D3, ADR-029)"
# ============================================================================
#
# WHAT THIS SECTION IS FOR. Until 1.8.3 "suite" meant "shell suite" at five independent
# sites (research R1 §9.1), so an agent working in a jest, pytest or go project could
# declare nothing true: the auditor arm refused it and the writer budget held nothing.
# `Re-executes:` is the one runner-agnostic label — lifted from the brief TEXT exactly as
# `Suites:` is, for every role, recorded on the roster row as its own field, and held by
# the writer-side budget arm (that half is T2's).
#
# THE GRAMMAR IS AUTHOR-MARKED (D3). A run is a backtick-delimited command on the span, in
# position order, at most three of them; text outside the marks is not a run; a run carrying
# an UNQUOTED pipe, a newline or an unexpanded shell variable is refused at the lift with the
# token named (a pipe inside quotes is an ordinary argument — 18T4a/18T4b below). The marks are KEPT on the roster field, which is what makes "the exact marked run"
# a thing the budget arm can compare against.
#
# fails-when: the field is absent from the row; an auditor brief declaring runs and waiving
# suites is refused; a brief carrying only this label is refused for declaring no
# instrument; an unexpanded name is admitted under either spelling; a fourth run reaches the
# row; unmarked text on the span is lifted as a run.

# [RL_BT, RL_JEST, RL_PYTEST, RL_GO, RL_NPM: defined in tests/dispatch-preflight.prelude.sh, hoisted from here for the shards — wave-30 T1]

# ---- AC-1.1: the field is lifted and lands on the roster row ----
REPO=$(make_repo r16la yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: audit the wave-99 matrix.
Expected artifact: .bionic/docs/record/w16-audit.md
Expected duration: ~30 minutes.
Questions: evidence
Suites: none
Re-executes: ${RL_JEST}" "w16-auditor" "claude-sonnet-5" "$S5_LIVE_TRANSCRIPT" "bionic:auditor")"
expect_status "16la an auditor brief declaring a marked run and waiving suites is ADMITTED" \
  "0" "$GATE_ST"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "16la …and the roster row carries the run, marks and all" \
  "$RL_JEST" "$(roster_field "$ROW" re_executes)"
expect_status "16la …with the waiver still recorded as the declared suite set" \
  "none" "$(roster_field "$ROW" suites_allowed)"

# ---- AC-8.1 (T5, REQ-8, D12): a span WITHIN the cap reads back every run it declared ----
# THE CONTROL FOR AC-8.2 BELOW. Two runs is under `RUNS_MAX` (3), so neither the cap-hit
# refusal nor its own drop field should ever fire here — the lift reads back exactly what
# was declared, space-joined, marks and all, and the dispatch is ADMITTED. Without this row
# a broken lift that dropped every second run, or one that refused ANY multi-run span, could
# pass 16le/16lf below green for the wrong reason.
REPO=$(make_repo r18t5a yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: re-run the evidence.
Expected artifact: .bionic/docs/record/w18-t5a.md
Expected duration: ~20 minutes.
Re-executes: ${RL_JEST} ${RL_PYTEST}" "w18-t5a")"
expect_status "18T5a a two-run span, under the cap, is ADMITTED" "0" "$GATE_ST"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "18T5a …and the lift reads BOTH runs back, in order" \
  "$RL_JEST $RL_PYTEST" "$(roster_field "$ROW" re_executes)"

# ---- AC-1.2: the auditor arm reads BOTH spellings, and its Fix text shows both ----
# Row 1 of the seed's §7 table: a named suite list is admitted (33c drives this too; it is
# repeated here as this section's own control, at the same fixture shape as rows 2 and 3).
REPO=$(make_repo r16lb1 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: audit the wave-99 matrix.
Expected artifact: .bionic/docs/record/w16-audit.md
Expected duration: ~30 minutes.
Questions: evidence
Suites: tests/widget.test.sh" "w16-aud-suites" "claude-sonnet-5" "$S5_LIVE_TRANSCRIPT" "bionic:auditor")"
expect_status "16lb1 an auditor naming a suite list is ADMITTED" "0" "$GATE_ST"

# Row 2: the waiver plus declared runs is admitted — the arm's predicate is "no suites AND
# no declared runs", not "no suites".
REPO=$(make_repo r16lb2 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: audit the wave-99 matrix.
Expected artifact: .bionic/docs/record/w16-audit.md
Expected duration: ~30 minutes.
Questions: evidence
Suites: none
Re-executes: ${RL_PYTEST}" "w16-aud-runs" "claude-sonnet-5" "$S5_LIVE_TRANSCRIPT" "bionic:auditor")"
expect_status "16lb2 an auditor waiving suites but declaring runs is ADMITTED" "0" "$GATE_ST"

# Row 3: the waiver alone is still refused, and the Fix text now names both spellings — an
# auditor in a jest repo must be able to read its way out of this refusal.
REPO=$(make_repo r16lb3 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$S33_WAIVED_BRIEF" "w16-aud-bare" \
                             "claude-sonnet-5" "$S5_LIVE_TRANSCRIPT" "bionic:auditor")"
expect_eq "16lb3 an auditor waiving suites with no declared runs is REFUSED" "deny" "$GATE_VERDICT"
expect_contains "16lb3 …and the Fix text shows the suite spelling" \
  "Suites: tests/one.test.sh" "$GATE_VERR"
expect_contains "16lb3 …and the runner spelling beside it" \
  "Re-executes:" "$GATE_VERR"

# ---- AC-1.3: the field is a budget declaration — it satisfies the Files-or-Suites arm ----
REPO=$(make_repo r16lc yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: re-run the unit tests and report.
Expected artifact: .bionic/docs/record/w16-runs.md
Expected duration: ~20 minutes.
Re-executes: ${RL_GO}" "w16-runsonly")"
expect_status "16lc a brief carrying only the runs label is ADMITTED" "0" "$GATE_ST"
expect_absent "16lc …the no-instrument arm did not fire" \
  "declares no Files: and no Suites:" "$GATE_ERR"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "16lc …and the declared run is the budget on the row" \
  "$RL_GO" "$(roster_field "$ROW" re_executes)"

# ---- AC-1.4: an unexpanded shell variable is refused at the lift, under BOTH spellings ----
# EACH FIXTURE CARRIES A VALID `Files:` LINE so the bad declaration is the brief's ONLY
# fault and the refusal is the single-fault shape, whose detail (and so the named token)
# is readable under the verbose knob (since wave-19 T4 one fault is a deny verdict too, its own detail on the reason).
REPO=$(make_repo r16ld1 yes)
write_attestation "$REPO" "$SID_A"
# THE STUB DERIVATION, not the real tool: the impact command is not under test in this
# section, and the real one over the real tree runs 11-17 s against a 10 s bound under
# wave-scale machine load (measured 2026-09-19), which would make these rows report the
# derivation bound instead of the fault they exist for.
s27_impact "$REPO" widget.test.sh
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: re-run the unit tests.
Expected artifact: .bionic/docs/record/w16-var.md
Expected duration: ~20 minutes.
Files: payload/scripts/lib/widget.sh
Re-executes: ${RL_BT}\$JEST x${RL_BT}" "w16-var-run")"
expect_eq "16ld1 a marked run holding an unexpanded name is REFUSED" "deny" "$GATE_VERDICT"
expect_contains "16ld1 …naming the token it saw" "\$JEST x" "$GATE_VERR"

REPO=$(make_repo r16ld2 yes)
write_attestation "$REPO" "$SID_A"
# THE STUB DERIVATION, not the real tool: the impact command is not under test in this
# section, and the real one over the real tree runs 11-17 s against a 10 s bound under
# wave-scale machine load (measured 2026-09-19), which would make these rows report the
# derivation bound instead of the fault they exist for.
s27_impact "$REPO" widget.test.sh
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: run the suite.
Expected artifact: .bionic/docs/record/w16-var2.md
Expected duration: ~20 minutes.
Files: payload/scripts/lib/widget.sh
Suites: \$SUITE" "w16-var-suite")"
expect_eq "16ld2 a Suites: token that is still a variable is REFUSED" "deny" "$GATE_VERDICT"
expect_contains "16ld2 …naming the token it saw" "\$SUITE" "$GATE_VERR"

# ---- AC-1.4 (cont.): a bracket that is not a WHOLE slot is a fault, named ----
#
# THE SILENT DROP THIS CLOSES (wave-16 T25, walk §W7). `istemplate()` carries two arms for
# trimtok RESIDUE — an opening bracket whose closer trimtok ate, and the mirror — and they
# are right where they were written, on `Files:` and `Suites:`, whose readers call trimtok
# first. `marked_runs()` never calls trimtok, so at THAT call site the same two arms fired
# on shell redirections: `> out`, `2>&1`, `<in`. The run was `continue`d with no
# `re_executes_bad` and no capwarn, the dispatch was ADMITTED with an empty or truncated
# `re_executes=` field, and the writer-side budget arm refused the agent's own command 40
# minutes later as undeclared. A pipe in the same position is refused loudly one line
# earlier and an unexpanded `$name` is refused with the token named (16ld1); this was the
# one shape that failed quietly.
#
# REFUSAL, NOT PASSTHROUGH (Chris, D14 option 3). An author who means a redirection is told
# which token and why, rather than having the wall silently agree to a budget entry nothing
# will ever equal.
#
# fails-when: a redirection run is admitted, its token is absent from the detail, or a
# roster row is written for the refused dispatch.
REPO=$(make_repo r16ld3 yes)
write_attestation "$REPO" "$SID_A"
# THE STUB DERIVATION, not the real tool — same reason as 16ld1 above.
s27_impact "$REPO" widget.test.sh
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: re-run the unit tests.
Expected artifact: .bionic/docs/record/w16-redir.md
Expected duration: ~20 minutes.
Files: payload/scripts/lib/widget.sh
Re-executes: ${RL_BT}bash tests/x.test.sh > out 2>&1${RL_BT}" "w16-redir-run")"
expect_eq "16ld3 a marked run carrying a shell redirection is REFUSED" "deny" "$GATE_VERDICT"
expect_contains "16ld3 …naming the whole token it saw, redirection and all" \
  "bash tests/x.test.sh > out 2>&1" "$GATE_VERR"
# THE PAIRED POSITIVE FOR 16ld5 (wave-21 T7, AC-6.1): a real redirection is still called one.
expect_contains "16ld3 …and the fault it names is still a redirection" \
  "a redirection: bash tests/x.test.sh > out 2>&1" "$GATE_VERR"
# AND NOTHING REACHED THE ROSTER. Under the old lift the row was written with the
# redirection tokens silently gone; this reads the absence of the row itself, and its
# failure message prints whatever row was written instead. Paired with the two positive
# rows above over the same fixture.
expect_empty "16ld3 …and no roster row was written for the refused dispatch" \
  "$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)"

# THE PAIRED POSITIVE, one fixture, both halves: a WHOLE `<...>` slot is still read as
# guidance — no fault, nothing lifted — and an ordinary run beside it still lifts with its
# marks intact. Without this row 16ld3 could pass on a lift that refused every run.
REPO=$(make_repo r16ld4 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: re-run the unit tests.
Expected artifact: .bionic/docs/record/w16-redir-ok.md
Expected duration: ~20 minutes.
Re-executes: ${RL_JEST} ${RL_BT}<cmd>${RL_BT}" "w16-redir-ok")"
expect_status "16ld4 a whole <cmd> slot beside an ordinary run is still ADMITTED" "0" "$GATE_ST"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "16ld4 …the slot lifted nothing and the ordinary run kept its marks" \
  "$RL_JEST" "$(roster_field "$ROW" re_executes)"

# ---- AC-6.1 (wave-21 T7; REQ-6, D6): a placeholder GLUED inside a run is a placeholder ----
#
# WHAT WAS WRONG (triage-B §3). `wholeslot()` admits a run that is NOTHING BUT `<...>`, and
# every other run holding a bracket was refused as "a redirection" — so
# `gh api repos/o/r/actions/jobs/<id>/logs`, a path with an unfilled `<id>` in it, sent its
# author to rewrite a correct command for a redirection it never had. Refusing it is right
# (a budget entry no typed command can equal is the `$name` rule); the WORD was wrong. A
# `<name>` with a non-space neighbour is an unfilled placeholder and is named as one; 16ld3
# above is the paired positive — `> out 2>&1` is still a redirection.
#
# fails-when: the glued run is admitted, called a redirection, or the detail does not say
# to fill it.
REPO=$(make_repo r16ld5 yes)
write_attestation "$REPO" "$SID_A"
# THE STUB DERIVATION, not the real tool — same reason as 16ld1 above.
s27_impact "$REPO" widget.test.sh
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: read the failed job's log.
Expected artifact: .bionic/docs/record/w21-placeholder.md
Expected duration: ~20 minutes.
Files: payload/scripts/lib/widget.sh
Re-executes: ${RL_BT}gh api repos/o/r/actions/jobs/<id>/logs${RL_BT}" "w21-ph-run")"
expect_eq "16ld5 a run with a placeholder glued inside a path is REFUSED" "deny" "$GATE_VERDICT"
expect_contains "16ld5 …named as an unfilled placeholder, with the run it sat in" \
  "an unfilled placeholder: gh api repos/o/r/actions/jobs/<id>/logs" "$GATE_VERR"
expect_absent "16ld5 …and never called a redirection" "a redirection: " "$GATE_VERR"
expect_contains "16ld5 …and the detail says a placeholder is filled with a real value" \
  "filled with a real value" "$GATE_VERR"
expect_empty "16ld5 …with no roster row written for the refused dispatch" \
  "$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)"

# ---- AC-6.2 (wave-21 T7; REQ-6, D6): a refused instrument is not a missing one ----
#
# WHAT WAS WRONG (triage-B §4.2, the cascade). 16ld1-16ld5 each carry a valid `Files:` line,
# so the refused run is their only fault. Take that line away and the run's own refusal
# came with a second, false one — "this brief declares no Files: and no Suites:" — because
# the no-instrument guard tested `suites_dropped` and none of its three siblings. A brief
# that declared its instrument and had it refused declared something; the fault it has is
# the one its own arm names. 27c is the control: a brief that declares nothing still draws
# the no-instrument refusal.
#
# fails-when: any of the four refusals below also carries the no-instrument sentence.
T7_NOFILES_HEAD="Your task: re-run the unit tests.
Expected artifact: .bionic/docs/record/w21-nofiles.md
Expected duration: ~20 minutes."

REPO=$(make_repo r16ld6a yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "${T7_NOFILES_HEAD}
Re-executes: ${RL_BT}\$JEST x${RL_BT}" "w21-nofiles-var")"
expect_eq "16ld6a the 16ld1 run with no Files: is REFUSED" "deny" "$GATE_VERDICT"
expect_contains "16ld6a …for its own fault, the token named" "\$JEST x" "$GATE_VERR"
expect_absent "16ld6a …and never for declaring nothing" \
  "declares no Files: and no Suites:" "$GATE_ERR$GATE_REASON"

REPO=$(make_repo r16ld6b yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "${T7_NOFILES_HEAD}
Re-executes: ${RL_BT}bash tests/x.test.sh > out 2>&1${RL_BT}" "w21-nofiles-redir")"
expect_eq "16ld6b the 16ld3 run with no Files: is REFUSED" "deny" "$GATE_VERDICT"
expect_contains "16ld6b …for its own fault, the token named" \
  "a redirection: bash tests/x.test.sh > out 2>&1" "$GATE_VERR"
expect_absent "16ld6b …and never for declaring nothing" \
  "declares no Files: and no Suites:" "$GATE_ERR$GATE_REASON"

REPO=$(make_repo r16ld6c yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "${T7_NOFILES_HEAD}
Re-executes: ${RL_BT}gh api repos/o/r/actions/jobs/<id>/logs${RL_BT}" "w21-nofiles-ph")"
expect_eq "16ld6c the 16ld5 run with no Files: is REFUSED" "deny" "$GATE_VERDICT"
expect_contains "16ld6c …for its own fault, the token named" \
  "an unfilled placeholder: gh api repos/o/r/actions/jobs/<id>/logs" "$GATE_VERR"
expect_absent "16ld6c …and never for declaring nothing" \
  "declares no Files: and no Suites:" "$GATE_ERR$GATE_REASON"

REPO=$(make_repo r16ld6d yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "${T7_NOFILES_HEAD}
Suites: \$SUITE" "w21-nofiles-suite")"
expect_eq "16ld6d the 16ld2 suite with no Files: is REFUSED" "deny" "$GATE_VERDICT"
expect_contains "16ld6d …for its own fault, the token named" "\$SUITE" "$GATE_VERR"
expect_absent "16ld6d …and never for declaring nothing" \
  "declares no Files: and no Suites:" "$GATE_ERR$GATE_REASON"

# ---- AC-7.1 / AC-7.2 (epic-23 wave-18, T4; REQ-7, D4): a QUOTED pipe is not a pipe ----
#
# WHAT WAS WRONG. The lift's pipe test was a whole-token scan — `index(tok, "|") > 0` — so
# a pipe inside single quotes, double quotes, a bracket expression or a regex alternation
# was refused identically to shell plumbing. A jest repository cannot declare its own runs
# without one: `--testPathPattern='(a|b)...'` is the ordinary spelling, and the refusal it
# drew told the author to "leave the shell plumbing off the span" about a character that
# was never plumbing. Research R2 §2 measured that the branch had NEVER been executed by a
# test in either direction, which is how the reading survived two waves.
#
# WHY BOTH HALVES ARE HERE. Making the scan quote-aware is necessary and not sufficient:
# the roster row is pipe-delimited, and the writer folded `|` to a space in every field —
# so an admitted run reached the row as a command no agent could ever type back, and the
# writer-side budget arm would refuse at run time the run this wall had just admitted (the
# wave-16 T25 failure through a different door). The row now percent-encodes the pipe in
# `re_executes=` and every reader decodes it, so the ADMIT row below asserts the encoded
# field, not just the exit status.
#
# fails-when: the quoted-pipe brief is refused; the unquoted one is admitted; the row
# carries a folded space where the pipe was; or the refusal still promises that any pipe
# is plumbing.
RL_QP_CMD="npx jest --testPathPattern='(a|b)\\.spec\\.ts'"
RL_QP_ENC="npx jest --testPathPattern='(a%7Cb)\\.spec\\.ts'"

# THE BRIEF CARRIES A VALID `Files:` LINE so the quoted pipe is its ONLY candidate fault.
# Without one the no-instrument arm fires beside it and the refusal leaves on the
# SEVERAL-fault wire, which is a `deny` verdict at exit 0 — a status this row would then
# read as admission, and the whole assertion would be green against the broken lift.
REPO=$(make_repo r18t4a yes)
write_attestation "$REPO" "$SID_A"
# THE STUB DERIVATION, not the real tool — same reason as 16ld1 above.
s27_impact "$REPO" widget.test.sh
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: re-run the unit tests.
Expected artifact: .bionic/docs/record/w18-qpipe.md
Expected duration: ~20 minutes.
Files: payload/scripts/lib/widget.sh
Re-executes: ${RL_BT}${RL_QP_CMD}${RL_BT}" "w18-qpipe")"
expect_status "18T4a a quoted pipe is not a pipe — the run is ADMITTED" "0" "$GATE_ST"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "18T4a2 …and the row carries the run with its pipe percent-encoded" \
  "${RL_BT}${RL_QP_ENC}${RL_BT}" "$(roster_field "$ROW" re_executes)"
# THE SEGMENT COUNT IS THE PROPERTY (S25d5's reasoning). A field that still held the raw
# pipe would read as one more segment to every by-key reader in the fleet.
expect_status "18T4a3 …and the run forged no segment of its own" "1" \
  "$(printf '%s' "$ROW" | tr '|' '\n' | grep -c '^re_executes=' | tr -d ' ')"

# THE OTHER DIRECTION, over the same shape. An UNQUOTED pipe is still shell plumbing and
# is still refused with the token named — the half that keeps 18T4a from being a hole.
REPO=$(make_repo r18t4b yes)
write_attestation "$REPO" "$SID_A"
# THE STUB DERIVATION, not the real tool — same reason as 16ld1 above.
s27_impact "$REPO" widget.test.sh
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: re-run the unit tests.
Expected artifact: .bionic/docs/record/w18-upipe.md
Expected duration: ~20 minutes.
Files: payload/scripts/lib/widget.sh
Re-executes: ${RL_BT}bash tests/x.test.sh | tee out${RL_BT}" "w18-upipe")"
expect_eq "18T4b an unquoted pipe IS a pipe — the run is REFUSED" "deny" "$GATE_VERDICT"
expect_contains "18T4b2 …naming the fault as a pipe" "a pipe" "$GATE_VERR"
expect_empty "18T4b3 …and no roster row was written for the refused dispatch" \
  "$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)"

# THE PROSE IS THE THIRD READER (AC-7.1). A wall whose sentence is false for the shape it
# now admits sends the author to fix a command that was never wrong; the detail must say
# UNQUOTED, and must no longer promise that any pipe at all is shell plumbing.
expect_contains "18T4c the detail names the unquoted pipe" "an unquoted pipe" "$GATE_VERR"
expect_absent "18T4c2 …and no longer calls every pipe plumbing" \
  "carrying a pipe" "$GATE_VERR"
# THE EVIDENCE MUST SHOW THE CHARACTER IT NAMES (T5, T4 carry-over). `C_RUNS_BAD` used to
# be sanitized with no field name, so `sanitize` folded this token's `|` to a space — the
# detail said "a pipe" beside a token that, as printed, no longer carried one. Passing the
# `re_executes` field name (the same case that keeps `re_executes=` itself pipe-intact)
# keeps the character in the evidence the classification names.
expect_contains "18T4c3 …and the shown token still carries the pipe it names" \
  "tests/x.test.sh | tee out" "$GATE_VERR"

# ---- AC-8.2 (T5, REQ-8, D12), supersedes AC-1.6: an over-cap span is REFUSED, naming the
# dropped run; unmarked text is not a run ----
# WHAT WAS WRONG. A four-run span used to be ADMITTED with three of the four on the row and
# a `warn()` line nobody in particular reads; the fourth run was left for the writer-side
# budget arm to refuse 40 minutes later, as undeclared, for a fact the author was never told
# at dispatch — the same shape T3 (REQ-8) closed for a dropped `Suites:` token. `RUNS_MAX`
# (3) is unchanged; only the fourth-and-up runs fate is.
REPO=$(make_repo r16le yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: re-run the evidence.
Expected artifact: .bionic/docs/record/w16-cap.md
Expected duration: ~20 minutes.
Re-executes: ${RL_JEST} ${RL_PYTEST} ${RL_GO} ${RL_NPM}" "w16-cap")"
# FLIPPED BY DESIGN (wave-20 T4; Δ3, Δ9). The cap of three is the AUDITOR's — its source is
# the auditor mandate's "<=3 re-executions" — and this brief is an implementor's (the
# driver's default role), so four runs is a declaration within SUITES_MAX and is admitted
# with every run on the row. The auditor twin that keeps the refusal is 16le-aud below.
expect_eq "16le a four-run span from an implementor is ADMITTED (the cap of three is the auditor's)" \
  "allow" "$GATE_VERDICT"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_contains "16le …and the row carries the fourth run" "npm test" "$(roster_field "$ROW" re_executes)"

# ---- AC-7.2 (wave-20 T4; REQ-7, Δ3, Δ9): three for auditors, SUITES_MAX for every other role ----
#
# fails-when: a test-runner brief with four runs is refused, an auditor brief with four is
# admitted, or a test-runner brief with 201 is admitted.
REPO=$(make_repo r16le-tr yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: re-run the evidence.
Expected artifact: .bionic/docs/record/w16-cap-tr.md
Expected duration: ~20 minutes.
Re-executes: ${RL_JEST} ${RL_PYTEST} ${RL_GO} ${RL_NPM}" "w16-cap-tr" claude-sonnet-5 "$S5_LIVE_TRANSCRIPT" bionic:test-runner)"
expect_eq "16le-tr a test-runner brief with four runs is ADMITTED" "allow" "$GATE_VERDICT"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_eq "16le-tr …and its row carries all four runs" \
  "${RL_JEST} ${RL_PYTEST} ${RL_GO} ${RL_NPM}" "$(roster_field "$ROW" re_executes)"

REPO=$(make_repo r16le-aud yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: re-run the evidence.
Expected artifact: .bionic/docs/record/w16-cap-aud.md
Expected duration: ~20 minutes.
Questions: evidence
Re-executes: ${RL_JEST} ${RL_PYTEST} ${RL_GO} ${RL_NPM}" "w16-cap-aud" claude-sonnet-5 "$S5_LIVE_TRANSCRIPT" bionic:auditor)"
expect_eq "16le-aud an auditor brief with four runs is REFUSED" "deny" "$GATE_VERDICT"
expect_contains "16le-aud …naming the fourth (dropped) run" "npm test" "$GATE_VERR"
expect_contains "16le-aud …and the fact names the auditor's 3-run cap" \
  "exceeds the 3-run cap" "$GATE_ERR"
expect_empty "16le-aud …with no roster row written for the refused dispatch" \
  "$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)"

# 201 RUNS, SUITES_MAX + 1: the count that bounds `Suites:` bounds every other role's runs.
T4_RUNS=""
for _i in $(seq 1 201); do T4_RUNS="$T4_RUNS ${RL_BT}pytest tests/unit/t${_i}.py${RL_BT}"; done
REPO=$(make_repo r16le-201 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: re-run the evidence.
Expected artifact: .bionic/docs/record/w16-cap-201.md
Expected duration: ~20 minutes.
Re-executes:${T4_RUNS}" "w16-cap-201" claude-sonnet-5 "$S5_LIVE_TRANSCRIPT" bionic:test-runner)"
expect_eq "16le-201 a test-runner brief with 201 runs is REFUSED" "deny" "$GATE_VERDICT"
expect_contains "16le-201 …naming the 201st run" "pytest tests/unit/t201.py" "$GATE_VERR"
expect_contains "16le-201 …against the 200-run cap" "exceeds the 200-run cap" "$GATE_ERR"
expect_empty "16le-201 …with no roster row written" \
  "$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)"

# THE TEXTS ARE ROLE-AWARE. A not-literal run is refused for every role; only the auditor's
# fix says "at most three". `Files:` and the stub derivation are there so this fault is the
# brief's ONLY one — with a second fault the refusal lists facts and no detail, and the
# absence row below would pass on a detail that was never printed. The positive row
# (`GATE_VERR` carries the not-literal token) proves the detail is on the wire.
REPO=$(make_repo r16le-txt-tr yes)
write_attestation "$REPO" "$SID_A"
s27_impact "$REPO" widget.test.sh
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: re-run the evidence.
Expected artifact: .bionic/docs/record/w16-txt-tr.md
Expected duration: ~20 minutes.
Files: payload/scripts/lib/widget.sh
Re-executes: ${RL_BT}pytest \$T${RL_BT}" "w16-txt-tr" claude-sonnet-5 "$S5_LIVE_TRANSCRIPT" bionic:test-runner)"
expect_eq "16le-txt a test-runner's variable run is refused" "deny" "$GATE_VERDICT"
expect_contains "16le-txt …and its detail is on the wire (non-vacuity)" "pytest \$T" "$GATE_VERR"
expect_absent "16le-txt …and its fix never tells a test-runner three" "at most three" "$GATE_VERR"
REPO=$(make_repo r16le-txt-aud yes)
write_attestation "$REPO" "$SID_A"
s27_impact "$REPO" widget.test.sh
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: re-run the evidence.
Expected artifact: .bionic/docs/record/w16-txt-aud.md
Expected duration: ~20 minutes.
Questions: evidence
Files: payload/scripts/lib/widget.sh
Re-executes: ${RL_BT}pytest \$T${RL_BT}" "w16-txt-aud" claude-sonnet-5 "$S5_LIVE_TRANSCRIPT" bionic:auditor)"
expect_eq "16le-txt an auditor's variable run is refused" "deny" "$GATE_VERDICT"
expect_contains "16le-txt …and its fix tells the auditor three" "at most three" "$GATE_VERR"

REPO=$(make_repo r16lf yes)
write_attestation "$REPO" "$SID_A"
# THE STUB DERIVATION, not the real tool: the impact command is not under test in this
# section, and the real one over the real tree runs 11-17 s against a 10 s bound under
# wave-scale machine load (measured 2026-09-19), which would make these rows report the
# derivation bound instead of the fault they exist for.
s27_impact "$REPO" widget.test.sh
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: re-run the evidence.
Expected artifact: .bionic/docs/record/w16-unmarked.md
Expected duration: ~20 minutes.
Files: payload/scripts/lib/widget.sh
Re-executes: npx jest --testPathPatterns 'x' and then pytest tests/unit" "w16-unmarked")"
expect_status "16lf a span with no marks at all is ADMITTED on its Files: line" "0" "$GATE_ST"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "16lf …and nothing unmarked was lifted as a run" \
  "" "$(roster_field "$ROW" re_executes)"

# ---- AC-1.7: the read-only roles are UNCHANGED — driven at :6531 (33d), unchanged here ----
# A researcher and a test-runner brief with `Suites: none` and no `Re-executes:` are still
# admitted; that is S33's own row 33d, and it is the pin this criterion is discharged by.

# ---- AC-1.8 — the scaffold's OWN placeholder lifts NOTHING (wave-16 T20; walk finding 1) ----
#
# `agents-src/blocks/brief-scaffold.md` carries `` Re-executes: `<cmd>` `` as guidance —
# rendered into dispatch.md verbatim. That is a TEMPLATE, exactly the shape `istemplate()`
# already rejects on the `Files:` and `Suites:` readers (`paths()`/`ispath()` and
# `suite_names()` both call it). `marked_runs()` did not, so a brief that pasted the scaffold
# without filling it in satisfied the suite-allowance wall on a budget entry
# (`` `<cmd>` ``) no real command could ever equal, and `dp_scaffold_marked` — which marks a
# label only when NONE of the three instrument fields is set — read the placeholder as a
# real declaration and left `Files:`/`Suites:`/`Re-executes:` all unmarked.
#
# THE LINE IS READ OUT OF THE SHIPPED FILE, never transcribed, exactly as the rest of this
# section's fixtures are.
RL_RE_EXECUTES_RAW_LINE="$(scaffold_raw_line "$DISPATCH_FILE" "Re-executes")"
expect_eq "16lg meta: the scaffold's own Re-executes line, unfilled, out of dispatch.md" \
  'Re-executes: `<cmd>`' "$RL_RE_EXECUTES_RAW_LINE"

# (a) the rendered scaffold placeholder, lifted as written, yields an EMPTY re_executes=
# field — `Suites: none` carries the instrument, so this brief still dispatches, and the
# placeholder must contribute nothing to the row.
REPO=$(make_repo r16lg1 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: build the widget.
Expected artifact: .bionic/docs/record/w16-scaffold-run.md
Expected duration: ~20 minutes.
Suites: none
${RL_RE_EXECUTES_RAW_LINE}" "w16-scaffold-run")"
expect_status "16lg1 a brief satisfying the instrument via Suites: none still dispatches" \
  "0" "$GATE_ST"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "16lg1 …and the scaffold's own placeholder lifts NOTHING onto the row" \
  "" "$(roster_field "$ROW" re_executes)"

# (b) with NO other instrument declared, an unfilled placeholder refuses exactly as an
# absent `Re-executes:` line would, and the several-fault scaffold marks ALL THREE
# instrument labels — reusing `$SM_FILES_LINE`/`$SM_SUITES_LINE` from §scaffold-marks
# above, plus the placeholder line itself as the (unsatisfied) `Re-executes:` line. The
# ambiguous-deliverable line is what keeps this on the several-fault deny wire (two
# faults: ambiguity + no instrument) rather than the single-fault shape, which never
# renders the scaffold at all (see §scaffold-marks (a)).
REPO=$(make_repo r16lg2 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: review the wave.
Expected artifact: compare .bionic/docs/record/a-notes.md against .bionic/docs/record/b-notes.md
Expected duration: 20 minutes.
${RL_RE_EXECUTES_RAW_LINE}" "w16-scaffold-only")"
expect_status "16lg2 an unfilled placeholder beside another fault reaches the deny wire" \
  "0" "$([ -n "$GATE_DENY" ] && echo 0 || echo 1)"
expect_contains "16lg2 …the Files: line IS marked (the placeholder satisfied nothing)" \
  "${SM_FILES_LINE} <ADD>" "$GATE_VERR"
expect_contains "16lg2 …the Suites: line IS marked" \
  "${SM_SUITES_LINE} <ADD>" "$GATE_VERR"
expect_contains "16lg2 …and the Re-executes: line ITSELF is marked, not read as satisfied" \
  "${RL_RE_EXECUTES_RAW_LINE} <ADD>" "$GATE_VERR"

# (c) a real marked run BESIDE the scaffold's placeholder lifts exactly the real run — the
# placeholder neither shadows it nor occupies one of the three cap slots.
RL_PLACEHOLDER="${RL_BT}<cmd>${RL_BT}"
REPO=$(make_repo r16lg3 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: re-run the unit tests.
Expected artifact: .bionic/docs/record/w16-scaffold-run3.md
Expected duration: ~20 minutes.
Re-executes: ${RL_PYTEST} ${RL_PLACEHOLDER}" "w16-mixed-run")"
expect_status "16lg3 a real run beside the scaffold's placeholder is ADMITTED" "0" "$GATE_ST"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "16lg3 …and only the real run reaches the row; the placeholder lifts nothing" \
  "$RL_PYTEST" "$(roster_field "$ROW" re_executes)"

# ============================================================================

section "§two-deliverables — two deliverable labels, two paths, one refusal (REQ-12 AC-12.1)"
# ============================================================================
#
# THE CARRY-OVER THIS CLOSES (row 14; research R3 row 35). `decl_deliverable` walked the
# deliverable-kind label hits in position order and returned the paths of the FIRST that
# yielded any — so a brief carrying `Expected artifact: a.md` and, lower down, a real
# `Deliverable: b.md` line was contracted to whichever came first, recorded `source=declared`
# as though a human had named one, with the other path silently discarded. The rule was
# POSITION, never label rank, and the ambiguity wall never saw two paths because each hit
# owned its own span.
#
# THE FIX IS THE WALL THIS FILE ALREADY HAS. The walk now unions the distinct paths of every
# deliverable-kind hit, so two labels naming two paths reach `deliverable_ambiguous=` exactly
# as one label naming two paths always has — one refusal, both candidates handed back, no
# guess. The same path under both labels is one path and is admitted: an author who repeated
# themselves has not created an ambiguity.
#
# fails-when: the two-path brief is admitted with one of the paths on the row, or the
# one-path brief is refused.

REPO=$(make_repo r16ma yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: write the report.
Expected artifact: .bionic/docs/record/w16-a.md
Deliverable: .bionic/docs/record/w16-b.md
Expected duration: ~20 minutes.
Suites: tests/widget.test.sh" "w16-two-deliv")"
expect_eq "16ma two deliverable labels naming two paths is REFUSED" "deny" "$GATE_VERDICT"
expect_contains "16ma …on the ambiguity arm, not on a guess" \
  "the deliverable label names several paths" "$GATE_ERR"
expect_contains "16ma …handing back the first candidate" \
  ".bionic/docs/record/w16-a.md" "$GATE_VERR"
expect_contains "16ma …and the second" \
  ".bionic/docs/record/w16-b.md" "$GATE_VERR"
expect_status "16ma …and no roster row was journalled" \
  "0" "$(roster_rows "$(roster_path "$REPO" "$SID_A")")"

REPO=$(make_repo r16mb yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: write the report.
Expected artifact: .bionic/docs/record/w16-a.md
Deliverable: .bionic/docs/record/w16-a.md
Expected duration: ~20 minutes.
Suites: tests/widget.test.sh" "w16-one-deliv")"
expect_status "16mb the same path under both labels is ADMITTED" "0" "$GATE_ST"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "16mb …and that one path is the contract on the row" \
  ".bionic/docs/record/w16-a.md" "$(roster_field "$ROW" deliverable)"

# ============================================================================


finish
