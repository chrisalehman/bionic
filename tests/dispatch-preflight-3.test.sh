#!/bin/bash
# Tests for hooks/dispatch-preflight.sh — THE START GATE. One shard of four:
# §combined-deny … §T22-name-in-flight.
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
. "$(dirname "$0")/lib/bound-marker.sh"
. "$(dirname "$0")/lib/roster-row.sh"
. "$(dirname "$0")/lib/live-answer.sh"
. "$(dirname "$0")/lib/swept-marker.sh"
. "$(dirname "$0")/dispatch-preflight.prelude.sh"


section "§combined-deny — every fault one refusal on the deny wire, the first its line and the rest one line each"
# The pool refuses once for every fault its arms found, on `deny`: exit 0, one verdict on stdout, one line on the
# user stream. A lone fault keeps its arm's own detail; several put each fault after the first on a line of its
# own, `<fact> (<fix>)`, and a pointer. A state fault rides the same wire. FIXTURES: make_repo's approved, bound,
# armed session; s21_stamp_path's stamp removed for the unarmed Patrol. SYNTHESIZED.
# fails-when: a refusal exits non-zero, prints a second line or object, journals a row, drops a fault from the
# several-fault detail, or a lone fault loses its own Fix: block.
expect_empty "§combined-deny the verbose knob is UNSET for every arm here" "${BIONIC_WALL_VERBOSE:-}"
CD_TWO='Your task: review the wave.
Expected duration: 20 minutes'
REPO=$(make_repo rcombdeny yes); write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$CD_TWO" "denybot")"
expect_eq "§combined-deny a two-fault brief is denied, exit 0, one object on stdout" "deny|0|1" \
  "$GATE_VERDICT|$GATE_ST|$(printf '%s\n' "$GATE_OUT" | /usr/bin/grep -c . || true)"
expect_eq "§combined-deny …one refusal line on the user stream" "1" "$(printf '%s\n' "$GATE_ERR" | /usr/bin/grep -c '^bionic: ' || true)"
expect_contains "§combined-deny …the first fault is its line" "names no deliverable" "$GATE_ERR"
expect_contains "§combined-deny …the second rides the detail as one line" "declares no Files: and no Suites: (declare Suites:)" "$GATE_REASON"
expect_absent "§combined-deny …no lecture per fault (beside the second fault's line)" "Fix: " "$GATE_REASON"
expect_status "§combined-deny …and journals no roster row" "0" "$(roster_rows "$(roster_path "$REPO" "$SID_A")")"
REPO=$(make_repo rcombdeny2 yes); write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: build it.
Expected duration: ~15 minutes.
Suites: tests/widget.test.sh" "denybot2")"
expect_eq "§combined-deny a single-fault brief refuses on the same wire" "deny|0" "$GATE_VERDICT|$GATE_ST"
expect_contains "§combined-deny …carrying its arm's own Fix: block" "Fix: declare one durable artifact path" "$GATE_REASON"
REPO=$(make_repo rcombdeny3 yes); write_attestation "$REPO" "$SID_A"; rm -f "$(s21_stamp_path "$REPO" "$SID_A")"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "denybot3")"
expect_eq "§combined-deny a lone state fault (the unarmed Patrol) takes the deny wire too" "deny|1" \
  "$GATE_VERDICT|$(printf '%s\n' "$GATE_OUT" | /usr/bin/grep -c . || true)"
expect_contains "§combined-deny …refusing for the state, in the arming wall's own words" "Patrol" "$GATE_ERR$GATE_VERR"
REPO=$(make_repo rcombdeny3b yes); write_attestation "$REPO" "$SID_A"; rm -f "$(s21_stamp_path "$REPO" "$SID_A")"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$CD_TWO" "denybot3b")"
expect_eq "§combined-deny the state fault beside brief faults refuses once" "deny|1" \
  "$GATE_VERDICT|$(printf '%s\n' "$GATE_ERR" | /usr/bin/grep -c '^bionic: ' || true)"
expect_contains "§combined-deny …the brief's faults ride its detail" "names no deliverable" "$GATE_REASON"

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

# scaffold_block is defined in tests/dispatch-preflight.prelude.sh. Both it and scaffold_fill below read
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
