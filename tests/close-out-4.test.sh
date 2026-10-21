#!/bin/bash
# tests/close-out-4.test.sh — payload/scripts/close-out.sh, part 4 of 4: sections §INHERITED-CONT through §ASKS-NOTHING.
#
# THE SUITE IS FOUR PARTS (wave-39 T6; D1, D13, REQ-3 AC-3.1). One close-out.test.sh promised more than the
# suite bar, ten minutes of the gate's promise, so it runs as four suites cut at section boundaries. Its
# governing design, its sandbox, and the fixture builders and helpers every part shares are in
# tests/close-out.prelude.sh, sourced below after the framework.
#
# Usage: bash tests/close-out-4.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"
. "$(dirname "$0")/lib/regression-fixture.sh"
. "$(dirname "$0")/lib/roster-row.sh"   # the one roster-row builder (cross-gate S17; wave-30 T23)
. "$(dirname "$0")/close-out.prelude.sh"

# ============================================================
section "§INHERITED-CONT — wave-35 T10 (REQ-1 AC-1.6, A-orch-18): the continuation carries every inherited: line under its own heading; a plan with none prints none"
# ============================================================
# `proof-add inherited <suite>` writes `inherited: <suite> base=<sha> head=<sha> at=<ISO> evidence=<log>` under
# `## SDLC State` (T9): debt the run inherited, red at its base and at its floor. AC-1.6 says it is carried into the
# continuation, so close-out lists every such line under `## Inherited debt`, beside the hand-holds, as written. A
# line inside a fence is prose, not a line the verb wrote, and is not carried.
# FIXTURE FIDELITY: mk_fixture at Step 8; the lines are placed by lib/proof.sh `proof_add_line`, the placer the verb
# calls, in the verb's own shape.
# fails-when: an inherited: line is missing from the continuation, or a plan with none gets the heading.
inh_line() {  # <suite> <sha> -> the line proof-add inherited writes
  printf 'inherited: %s base=%s head=%s at=2026-10-12T04:00:00Z evidence=record/wave-01-fixture/inherited-%s-%.12s.log' "$1" "$2" "$2" "$1" "$2"
}
inh_place() {  # <project> <line> -> the line placed under ## SDLC State by the product's placer
  bash -c '. "$1/run.sh" && . "$1/proof.sh" || exit 1; proof_add_line "$2" "$3" > "$2.pf" && mv "$2.pf" "$2"' \
    _ "$REPO_ROOT/payload/scripts/lib" "$1/$PLAN_REL" "$2"
}
inh_section() { awk '/^## / { s = ($0 == "## Inherited debt"); next } s && NF && !/^```/ { print }' "$1"; }
PINH="$(mk_fixture inherited-cont)"; advance_to "$PINH" 8
INH_H="$(fixture_git "$PINH" rev-parse --verify -q wave/01-fixture)"
inh_place "$PINH" "$(inh_line a.test.sh "$INH_H")"
inh_place "$PINH" "$(inh_line b.test.sh "$INH_H")"
awk '/^## Tasks/ { print "```"; print "inherited: fenced.test.sh base=0123456789ab head=0123456789ab at=x evidence=y"; print "```"; print "" } { print }' \
  "$PINH/$PLAN_REL" > "$PINH/$PLAN_REL.f" && mv "$PINH/$PLAN_REL.f" "$PINH/$PLAN_REL"
run_close "$PINH" run
expect_eq "INH-1 run closes the plan (rc 0)" "0" "$CO_RC"
expect_absent "INH-2b …and not the fenced line" "fenced.test.sh" "$(inh_section "$PINH/$CONT_REL")"
expect_eq "INH-2c …beside the hand-holds: the section follows ## Hand-holds, before the Resume instruction" "yes" \
  "$(awk '/^## Hand-holds$/ { a = NR } /^## Inherited debt$/ { b = NR } /^## Resume instruction/ { c = NR } END { print (a && b > a && c > b) ? "yes" : "no" }' "$PINH/$CONT_REL")"
PINO="$(mk_fixture inherited-none)"; advance_to "$PINO" 8
run_close "$PINO" run

# T33 (D20, critic-adversarial #5; A-orch-32): an existing continuation.md gains the inherited lines under ## Inherited debt,
# each once, the person's own text untouched; the section follows ## Hand-holds, which the same merge writes.
inh_count() { /usr/bin/grep -c -F -x "$2" "$1" | tr -d ' '; }
PIE="$(mk_fixture inherited-existing)"; advance_to "$PIE" 8
INE_H="$(fixture_git "$PIE" rev-parse --verify -q wave/01-fixture)"
INE_A="$(inh_line a.test.sh "$INE_H")"; INE_B="$(inh_line b.test.sh "$INE_H")"
inh_place "$PIE" "$INE_A"; inh_place "$PIE" "$INE_B"
mkdir -p "$PIE/${CONT_REL%/*}"
printf '# continuation — hand written\n\nmy own note on the close\n\n## Deferrals\n\nnone, said the person\n\n## Resume instruction\n\nedited by a person\n' > "$PIE/$CONT_REL"
INE_CK0="$(cksum < "$PIE/$CONT_REL")"
run_close "$PIE" check
expect_eq "INH-4a …and writes nothing" "$INE_CK0" "$(cksum < "$PIE/$CONT_REL")"
run_close "$PIE" run
expect_eq "INH-5a …each line is in the file once" "1/1" "$(inh_count "$PIE/$CONT_REL" "$INE_A")/$(inh_count "$PIE/$CONT_REL" "$INE_B")"
expect_eq "INH-5c …the section follows ## Hand-holds and comes before the Resume instruction" "yes" \
  "$(awk '/^## Hand-holds$/ { a = NR } /^## Inherited debt$/ { b = NR } /^## Resume instruction/ { c = NR } END { print (a && b > a && c > b) ? "yes" : "no" }' "$PIE/$CONT_REL")"
PIE2="$(mk_fixture inherited-existing2)"; advance_to "$PIE2" 8
inh_place "$PIE2" "$INE_A"; inh_place "$PIE2" "$INE_B"
mkdir -p "$PIE2/${CONT_REL%/*}"; cp "$PIE/$CONT_REL" "$PIE2/$CONT_REL"
INE_CK1="$(cksum < "$PIE2/$CONT_REL")"
run_close "$PIE2" run
expect_eq "INH-6 run twice: exits 0, each line still once, the file byte for byte what the first run left" "0/1/1/$INE_CK1" \
  "$CO_RC/$(inh_count "$PIE2/$CONT_REL" "$INE_A")/$(inh_count "$PIE2/$CONT_REL" "$INE_B")/$(cksum < "$PIE2/$CONT_REL")"
# the heading holds one of the two lines (typed unfenced) and a note: the other is added under it, nothing twice
PIE3="$(mk_fixture inherited-existing3)"; advance_to "$PIE3" 8
inh_place "$PIE3" "$INE_A"; inh_place "$PIE3" "$INE_B"
mkdir -p "$PIE3/${CONT_REL%/*}"
printf '# continuation — hand written\n\n## Deferrals\n\n## Inherited debt\n\nthe person looked at a.test.sh\n%s\n\n## Resume instruction\n\nedited by a person\n' "$INE_A" > "$PIE3/$CONT_REL"
run_close "$PIE3" run
# a plan with no inherited: line gives an existing continuation no Inherited debt heading
PIE4="$(mk_fixture inherited-existing4)"; advance_to "$PIE4" 8
mkdir -p "$PIE4/${CONT_REL%/*}"
printf '# continuation — hand written\n\n## Deferrals\n\n## Resume instruction\n\nedited by a person\n' > "$PIE4/$CONT_REL"
run_close "$PIE4" run


# ============================================================
section "§GOVERNED — wave-36 T2 (REQ-1 AC-1.4, D7; ADR-055): the continuation names the root and commit that governed the run"
# ============================================================
# hooks/session-start.sh writes `.bionic/tmp/loaded-<sid>.state` at every session start (wave-36 T1): `root=`,
# `commit=` when the root is a checkout of the plugin, `started=`, then one `<sha256> <path>` per loaded file. close-out
# reads the records of the sessions in the run's Step-4..9 window (the Step-4 line's instant, else the plan's
# `approved-by:` instant, to now), BEFORE the tmp wipe takes them, and writes one `governed-by: <root> <commit> from
# <ISO>` per root and commit, in order of the first session that ran it, under `## Governed by` of the continuation
# and on the card. A record with no commit ran an installed copy: `governed-by: <root> installed <version> from <ISO>`.
# No record in the window: `governed-by: installed <version>`. The records below are in the writer's shape; the first is
# this run's own record (wave-36, session 1cee5232, at T1's land), copied, never read live.
GOV_ROOT="/Users/admin/workspace/personal/bionic/payload"
GOV_C1="7cb98434e04d97d1a32495806d1f14c54efb8171"
GOV_C2="1d7930259c3a5e0f2b4d6e8a0c1f3e5d7b9a2c4e"
GOV_VER="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$REPO_ROOT/payload/.claude-plugin/plugin.json" | head -1)"
expect_nonempty "GOV-00 precondition: the payload under test names its version (the none line's)" "$GOV_VER"
# gov_record <project> <sid> <root> <commit|-> <started> -> a load record in the writer's shape
gov_record() {
  case "$1" in "$SANDBOX"/*) : ;; *) echo "gov_record: refusing outside the sandbox: '$1'" >&2; return 1 ;; esac
  {
    printf 'root=%s\n' "$3"
    [ "$4" = - ] || printf 'commit=%s\n' "$4"
    printf 'started=%s\n' "$5"
    printf '612909030be5dc2a241a1afdb61732d28b567a830e7c905752826d69a5ba2acd agents/auditor.md\n'
    printf '44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a hooks/hooks.json\n'
  } > "$1/.bionic/tmp/loaded-$2.state"
}
# gov_step4 <project> <text> -> the plan's `- Step 4:` line, written in front of the Step-7 line
gov_step4() {
  local plan="$1/$PLAN_REL"
  case "$1" in "$SANDBOX"/*) : ;; *) echo "gov_step4: refusing outside the sandbox: '$1'" >&2; return 1 ;; esac
  GOV_TEXT="$2" awk '/^- Step 7:/ && !d { print "- Step 4: " ENVIRON["GOV_TEXT"]; print "  worktree: ."; d = 1 } { print }' \
    "$plan" > "$plan.g" && mv "$plan.g" "$plan"
}
gov_section() { awk '/^## / { s = ($0 == "## Governed by"); next } s && NF && !/^```/ { print }' "$1"; }
gov_card() { printf '%s\n' "$CO_OUT" | /usr/bin/grep '^governed-by: '; }

PG="$(mk_fixture governed)"; advance_to "$PG" 8
gov_step4 "$PG" "implement: opened 2026-10-13T20:39Z, writers in .worktrees/36-T<n>"
GOV_CACHE="$SANDBOX/governed-cache/bionic/1.18.0"
mkdir -p "$GOV_CACHE/.claude-plugin"; printf '{\n  "name": "bionic",\n  "version": "1.18.0"\n}\n' > "$GOV_CACHE/.claude-plugin/plugin.json"
gov_record "$PG" s0 "/elsewhere/old/payload" 1111111111111111111111111111111111111111 2026-10-13T19:00:00Z   # before Step 4
gov_record "$PG" s1 "$GOV_ROOT" "$GOV_C1" 2026-10-13T23:55:11Z
gov_record "$PG" s2 "$GOV_ROOT" "$GOV_C1" 2026-10-14T01:00:00Z
gov_record "$PG" s3 "$GOV_ROOT" "$GOV_C2" 2026-10-14T03:00:00Z
gov_record "$PG" s4 "$GOV_CACHE" - 2026-10-13T21:00:00Z
ln -s "$PG/.bionic/tmp/loaded-s0.state" "$PG/.bionic/tmp/loaded-s5.state"   # a link is never a record
GOV_WANT="governed-by: $GOV_CACHE installed 1.18.0 from 2026-10-13T21:00:00Z
governed-by: $GOV_ROOT $GOV_C1 from 2026-10-13T23:55:11Z
governed-by: $GOV_ROOT $GOV_C2 from 2026-10-14T03:00:00Z"
GOV_CK0="$(find "$PG/.bionic/tmp" -name 'loaded-*' | wc -l | tr -d ' ')"
run_close "$PG" check
expect_absent "GOV-1b …not the session that started before Step 4" "/elsewhere/old/payload" "$CO_OUT"
expect_eq "GOV-1c …and check removes no record" "$GOV_CK0" "$(find "$PG/.bionic/tmp" -name 'loaded-*' | wc -l | tr -d ' ')"
run_close "$PG" run
expect_eq "GOV-2b …the wipe took the records it read" "0" "$(find "$PG/.bionic/tmp" -name 'loaded-*' 2>/dev/null | wc -l | tr -d ' ')"
expect_eq "GOV-3b …after ## Hand-holds and before the Resume instruction" "yes" \
  "$(awk '/^## Hand-holds$/ { a = NR } /^## Governed by$/ { b = NR } /^## Resume instruction/ { c = NR } END { print (a && b > a && c > b) ? "yes" : "no" }' "$PG/$CONT_REL")"

# none in the window: the installed version, on the card and in the continuation
PGN="$(mk_fixture governed-none)"; advance_to "$PGN" 8
gov_step4 "$PGN" "implement: opened 2026-10-13T20:39Z"
gov_record "$PGN" s0 "/elsewhere/old/payload" 1111111111111111111111111111111111111111 2026-10-13T19:00:00Z
run_close "$PGN" run
expect_eq "GOV-4 AC-1.4 no record in the window: governed-by: installed <version>, on the card and in the continuation" \
  "0|governed-by: installed $GOV_VER|governed-by: installed $GOV_VER" "$CO_RC|$(gov_card)|$(gov_section "$PGN/$CONT_REL")"

# no instant on the Step-4 line (or no Step-4 line): the window opens at the plan's approved-by
PGA="$(mk_fixture governed-approved)"; advance_to "$PGA" 8
gov_record "$PGA" s0 "/elsewhere/old/payload" 1111111111111111111111111111111111111111 2026-09-13T23:00:00Z
gov_record "$PGA" s1 "$GOV_ROOT" "$GOV_C1" 2026-09-14T00:30:00Z
run_close "$PGA" check
expect_eq "GOV-5a the window opens at approved-by: the later record governs, the earlier does not" \
  "governed-by: $GOV_ROOT $GOV_C1 from 2026-09-14T00:30:00Z" "$(gov_card)"

# an existing continuation: the section is merged in, the person's text kept, and a second close adds nothing
PGE="$(mk_fixture governed-existing)"; advance_to "$PGE" 8
gov_step4 "$PGE" "implement: opened 2026-10-13T20:39Z"
gov_record "$PGE" s1 "$GOV_ROOT" "$GOV_C1" 2026-10-13T23:55:11Z
mkdir -p "$PGE/${CONT_REL%/*}"
printf '# continuation — hand written\n\nmy own note on the close\n\n## Deferrals\n\n## Resume instruction\n\nedited by a person\n' > "$PGE/$CONT_REL"
run_close "$PGE" check
expect_contains "GOV-6 check over an existing continuation without the section names the add run will make" \
  "the ## Governed by section" "$CO_OUT"
run_close "$PGE" run
PGE2="$(mk_fixture governed-existing2)"; advance_to "$PGE2" 8
mkdir -p "$PGE2/${CONT_REL%/*}"; cp "$PGE/$CONT_REL" "$PGE2/$CONT_REL"
GOV_CK1="$(cksum < "$PGE2/$CONT_REL")"
run_close "$PGE2" run
expect_eq "GOV-6c a second close over it (no record left, so its own reading is the installed line) adds nothing: byte for byte" \
  "0|$GOV_CK1|governed-by: installed $GOV_VER" "$CO_RC|$(cksum < "$PGE2/$CONT_REL")|$(gov_card)"

# the mutation arm: a doctored copy that finds no record — it still closes, and names the installed version while the
# records name the checkout, so GOV-3 goes red on it
GOV_MUT="$(mktemp -d "${TMPDIR:-/tmp}/close-out-gov-mut.XXXXXX")"
mkdir -p "$GOV_MUT/scripts"; ln -s "$REPO_ROOT/payload/scripts/lib" "$GOV_MUT/scripts/lib"
ln -s "$REPO_ROOT/payload/scripts/card.sh" "$GOV_MUT/scripts/card.sh"
sed 's#/loaded-\*\.state#/no-such-record-*.state#' "$SCRIPT" > "$GOV_MUT/scripts/close-out.sh"
expect_eq "GOV-mut0 the doctored copy differs from the script in exactly one line (the doctor took)" "1" \
  "$(diff "$SCRIPT" "$GOV_MUT/scripts/close-out.sh" | /usr/bin/grep -c '^>')"
PGM="$(mk_fixture governed-mut)"; advance_to "$PGM" 8
gov_step4 "$PGM" "implement: opened 2026-10-13T20:39Z"
gov_record "$PGM" s1 "$GOV_ROOT" "$GOV_C1" 2026-10-13T23:55:11Z
( cd "$PGM" && HOME="$SB_HOME" CLAUDE_PROJECT_DIR="" BIONIC_PLUGIN_ROOT="$REPO_ROOT/payload" BIONIC_CLAUDE_HOME="$SB_HOME/.claude" \
    bash "$GOV_MUT/scripts/close-out.sh" "$PGM/$PLAN_REL" run ) > "$SANDBOX/gov-mut.out" 2>&1
GOV_MRC=$?
expect_eq "GOV-mut2 …and its continuation names the installed version while a record named the checkout" \
  "governed-by: installed $GOV_VER" "$(gov_section "$PGM/$CONT_REL")"
rm -rf "$GOV_MUT"

# ============================================================
section "§HAND-HOLDS-KINDS — wave-36 T14 (D13; REQ-7 AC-7.6): adopt's adoptions and the fixed disposals are folded under their own kinds, never as by-hand"
# ============================================================
# AC-7.6: the fold counts every act a verb of this release writes. Two more kinds join `stop-runs` (T11):
#   adoptions   the roster row `adopt` files for each adopted agent (`source=adopted|…|adopted_from=<sid>`, written by
#               session-poker.sh adopt_write_row; its printed `poker-adopt/v1|…` report is stdout and kept nowhere), counted
#               DISTINCT (agent_id, adopted_from) over the rosters whose `plan=` is this run's, as amends are;
#   fixed       the plan's `moved: <record>#<n> to=fixed row=<T> …` line under ## SDLC State (`finding-move … fixed`),
#               one per line, fenced text skipped.
# by-hand stays the number of `--by-hand` landings. fails-when: by-hand>0 for these acts, or a kind omitted.
# FIXTURE FIDELITY: the roster rows through the one production row builder (roster_row_fixture), in adopt_write_row's
# field set; the moved line in finding-move's shape, placed under ## SDLC State.
HK_P="$(mk_fixture handholds-kinds)"; advance_to "$HK_P" 8
HK_PLAN="$HK_P/$PLAN_REL"
{
  roster_row_fixture status=identified name=w-ad agent_id=ad source=adopted adopted_from=old-sid-1 plan="$HK_PLAN"
  roster_row_fixture status=confirmed name=w-ad agent_id=ad source=adopted adopted_from=old-sid-1 plan="$HK_PLAN"
  roster_row_fixture status=identified name=w-oz agent_id=oz source=adopted adopted_from=old-sid-1 plan="/elsewhere/wave-99-other.plan.md"
  roster_row_fixture status=identified name=w-ln agent_id=ln source=launched plan="$HK_PLAN"
} >> "$HK_P/.bionic/tmp/roster-fixture.state"
HK_MOVED="moved: record/wave-01-fixture/rev.md#1 to=fixed row=T1 by=Chris Lehman at=2026-10-06T14:00:00Z"
awk -v m="$HK_MOVED" '
  /^approved-by: / { print; print m; next }
  /^## Tasks/ { print "```"; print "moved: record/wave-01-fixture/rev.md#2 to=fixed row=T2 by=Someone at=2026-10-06T14:10:00Z"; print "```"; print ""; print; next }
  /^- Step 8:/ { print "- T1: the reviewer said rev.md#3 was moved: to=fixed by hand, says this prose"; print; next }
  { print }' "$HK_PLAN" > "$HK_PLAN.k" && mv "$HK_PLAN.k" "$HK_PLAN"
HK_WANT="hand-holds: total=2 · by-hand=0 · stop-runs=0 · declines=0 · lifts=0 · amends=0 · holds=0 · extensions=0 · waivers=0 · second-regressions=0 · adoptions=1 · fixed=1"
expect_eq "HK-1 AC-7.6 one adoption (re-written once, another run's not counted) and one to=fixed move read adoptions=1 · fixed=1 · by-hand=0, in the total" \
  "$HK_WANT" "$(hh_report "$HK_P" --hand-holds | grep '^hand-holds: ')"
run_close "$HK_P" check
expect_eq "HK-2 …and close-out's card prints the same line" "$HK_WANT" "$(printf '%s\n' "$CO_OUT" | grep '^hand-holds: ')"

# ============================================================
section "§FENCE — wave-36 T14 (D13; C38): a line merged into a section that is one fenced list goes inside the fence"
# ============================================================
# `co_cont_merge` (co_cont_write's lines mode since wave-38 T15) added the owed lines after the section's last non-blank line, and a closing fence is such a line, so
# a line merged into close-out's own fenced sections (## Inherited debt, ## Governed by, ## Hand-holds) landed under
# the fence, outside the list it belongs to (research-plan-and-readings.md §C38, probe-c38-c21.log). The rule now:
# when the section is one fenced list (its first and last content lines are the fence of its one fenced block), the
# lines go before the closing fence; a section with anything else in it gets them after its last content, as before.
# ## Deferrals is read unfenced by every reader (card.sh's inherited reader, debt adopt), so its lines always go
# after: a carried line inside a fence there would be a line the next run never reads.
# fails-when: a merged line lands outside the one fenced list it was owed to, or inside a ## Deferrals fence.
fence_lines() {  # <continuation> <heading> <in|out> -> the section's lines inside (in) or outside (out) a fence, blanks dropped
  awk -v h="$2" -v w="$3" '
    /^## / && !f { s = ($0 == h); next }
    !s { next }
    /^```/ { f = !f; next }
    NF && ((w == "in") == (f == 1)) { print }' "$1"
}
PF1="$(mk_fixture fence-one)"; advance_to "$PF1" 8
PF_H="$(fixture_git "$PF1" rev-parse --verify -q wave/01-fixture)"
PF_A="$(inh_line a.test.sh "$PF_H")"; PF_B="$(inh_line b.test.sh "$PF_H")"
inh_place "$PF1" "$PF_A"; inh_place "$PF1" "$PF_B"
mkdir -p "$PF1/${CONT_REL%/*}"
printf '# continuation — hand written\n\n## Deferrals\n\n## Inherited debt\n\n```\n%s\n```\n\n## Resume instruction\n\nedited by a person\n' "$PF_A" > "$PF1/$CONT_REL"
expect_eq "FENCE-0 precondition: the section is one fenced list holding the first line (the extractor reads it)" "$PF_A|" \
  "$(fence_lines "$PF1/$CONT_REL" "## Inherited debt" in)|$(fence_lines "$PF1/$CONT_REL" "## Inherited debt" out)"
run_close "$PF1" run
expect_eq "FENCE-1 C38 run exits 0 and the owed line goes inside the fence, after the line there; nothing lands outside it" \
  "0|$PF_A $PF_B|" \
  "$CO_RC|$(fence_lines "$PF1/$CONT_REL" "## Inherited debt" in | paste -sd' ' -)|$(fence_lines "$PF1/$CONT_REL" "## Inherited debt" out)"
PF1B_CK="$(cksum < "$PF1/$CONT_REL")"
PF1B="$(mk_fixture fence-one-again)"; advance_to "$PF1B" 8
inh_place "$PF1B" "$PF_A"; inh_place "$PF1B" "$PF_B"
mkdir -p "$PF1B/${CONT_REL%/*}"; cp "$PF1/$CONT_REL" "$PF1B/$CONT_REL"
run_close "$PF1B" run
expect_eq "FENCE-2 a second close over it adds nothing: byte for byte" "0|$PF1B_CK" "$CO_RC|$(cksum < "$PF1B/$CONT_REL")"
# the otherwise arm: a section holding a note and then a fenced block keeps the old placement, after the block
PF3="$(mk_fixture fence-mixed)"; advance_to "$PF3" 8
inh_place "$PF3" "$PF_A"; inh_place "$PF3" "$PF_B"
mkdir -p "$PF3/${CONT_REL%/*}"
printf '# continuation — hand written\n\n## Deferrals\n\n## Inherited debt\n\nthe person looked at these\n\n```\n%s\n```\n\n## Resume instruction\n\nedited by a person\n' "$PF_A" > "$PF3/$CONT_REL"
run_close "$PF3" run
expect_eq "FENCE-3 a section that is a note and a fenced block: the owed line goes after the block, unfenced" \
  "0|$PF_A|the person looked at these $PF_B" \
  "$CO_RC|$(fence_lines "$PF3/$CONT_REL" "## Inherited debt" in | paste -sd' ' -)|$(fence_lines "$PF3/$CONT_REL" "## Inherited debt" out | paste -sd' ' -)"
# ## Deferrals: one fenced list there is an example a person pasted; the carried line goes after it, where it is read
PF4="$(mk_fixture fence-deferrals)"; advance_to "$PF4" 8
carry_plant "$PF4" "deferred: $CARRY_REC#1 S2 off \"carried past a fence\" stated=\"A sentence.\""
mkdir -p "$PF4/${CONT_REL%/*}"
printf '# continuation — hand written\n\n## Deferrals\n\n```\ndeferred: <record>#<n> <S> <reach> "<title>" — the form, pasted\n```\n\n## Resume instruction\n\nedited by a person\n' > "$PF4/$CONT_REL"
run_close "$PF4" run
expect_eq "FENCE-4 ## Deferrals that is one fenced list: the carried line goes after the fence, where card.sh reads it" \
  "0|deferred: $CARRY_REC#1 S2 off \"carried past a fence\" stated=\"A sentence.\" from=$CARRY_W" \
  "$CO_RC|$(fence_lines "$PF4/$CONT_REL" "## Deferrals" out)"

# ============================================================
section "§LANDS — wave-36 T14 (D13; REQ-7 AC-7.7; C70): close-out lands the rows its merge lands, keeps the session engaged until its last act, and task-set --reason amends a delivered plan"
# ============================================================
# The rows close-out's merge lands are the plan's open (pending or active) rows of kind `integrate` (the merge
# itself) and `close` (the row the merge is read by, `merge` in units.sh's reads). Each is landed through the one
# landing writer, `session-poker.sh row-landed <id> <integration head> <now>`, in this session (the plan verb needs
# its engagement and its binding), after act 1 and before act 2, so the plan close-out delivers reads them landed.
# A run with such rows and no session bound to this plan is refused before the first act, nothing done. Act 3 keeps
# this session's engaged marker, which is also its binding; it is wiped as close-out's last act, so a close-out
# that refuses midway leaves the session engaged and its plan verbs working. On the delivered plan, a session that
# re-engaged and bound it (bound-closed) may set cells with `task-set … --reason '<why>'`, which records the reason
# on the row's step line; without --reason the delivered refusal stands. A session not engaged is refused at the
# consent boundary (ruling r1791954201-85499).
# fails-when: a delivered plan reads a row its merge landed as pending; task-set --reason on it is refused; the
# marker is gone after a refusal midway.
lands_rows() {  # <project> -> the plan gains T3 (step 8, integrate) and T4 (step 9, close), pending, each with its step line,
  # and the `- Step 4:` line every plan past Step 4 carries (row-landed's dry commit judges a writer's copy at current: 4)
  local plan="$1/$PLAN_REL"
  case "$1" in "$SANDBOX"/*) : ;; *) echo "lands_rows: refusing outside the sandbox: '$1'" >&2; return 1 ;; esac
  awk '
    /^\| T2 \|/ { print
                  print "| T3 | 8 | integrate | merge the wave into main | — | — | 10 | AC-1 | none | pending | — |"
                  print "| T4 | 9 | close | close-out, continuation.md | — | — | 10 | AC-1 | none | pending | — |"; next }
    /^- Step 7:/ { print "- Step 4: implement: opened 2026-09-14T00:10Z"; print; next }
    /^- Step 8:/ { print "- T3: pending dispatch — —"; print "- T4: pending dispatch — —"; print; next }
    { print }' "$plan" > "$plan.l" && mv "$plan.l" "$plan"
}
LP_OUT=""; LP_RC=0
lands_poker() {  # <project> <sid> <verb> [<operand>…] -> LP_OUT (stdout and stderr), LP_RC
  local proj="$1" sid="$2"; shift 2
  LP_OUT="$( ( in_fixture "$proj" || exit 9
    HOME="$SB_HOME" CLAUDE_PROJECT_DIR="" BIONIC_PLUGIN_ROOT="$REPO_ROOT/payload" BIONIC_CLAUDE_HOME="$SB_HOME/.claude" \
      CLAUDE_CODE_SESSION_ID="$sid" bash "$BIONIC_HOOKS_DIR/session-poker.sh" "$@" ) 2>&1 )"
  LP_RC=$?
}
lands_bind() {  # <project> <sid> -> the session engaged (the marker engage.sh writes) and bound to the plan by the verb
  : > "$1/.bionic/tmp/engaged-$2.state"
  lands_poker "$1" "$2" bind "$1/$PLAN_REL"
}
lands_cell() {  # <project> <id> <field> -> the ## Tasks cell, trimmed (field 11 is status, 6 is agent)
  awk -F'|' -v id="$2" -v c="$3" '{ x = $2; gsub(/ /, "", x) } x == id { v = $c; gsub(/^ +| +$/, "", v); print v; exit }' "$1/$PLAN_REL"
}
lands_step() {  # <project> <id> -> the row's `- T<n>:` line under ## SDLC State
  /usr/bin/grep -m1 "^- $2: " "$1/$PLAN_REL"
}
LA_SID="closeout-lands-sid"
PLA="$(mk_fixture lands)"; advance_to "$PLA" 8; lands_rows "$PLA"
LA_MAIN="$(fixture_git "$PLA" rev-parse --verify -q main)"
lands_bind "$PLA" "$LA_SID"
expect_eq "LANDS-0 precondition: the session is bound (the verb said so), and T3 and T4 read pending, their step lines pending dispatch" \
  "0|pending|pending|- T3: pending dispatch — —" \
  "$LP_RC|$(lands_cell "$PLA" T3 11)|$(lands_cell "$PLA" T4 11)|$(lands_step "$PLA" T3)"
LA_CK0="$(cksum < "$PLA/$PLAN_REL")"
run_close_as "$LA_SID" "$PLA" check
expect_eq "LANDS-1b …and writes nothing" "$LA_CK0" "$(cksum < "$PLA/$PLAN_REL")"
run_close_as "$LA_SID" "$PLA" run
expect_eq "LANDS-2 AC-7.7 run exits 0 and the delivered plan reads both rows landed (run_open says closed)" "0|landed|landed|1" \
  "$CO_RC|$(lands_cell "$PLA" T3 11)|$(lands_cell "$PLA" T4 11)|$(run_open_rc "$PLA/$PLAN_REL")"
expect_contains "LANDS-3 …each row's step line reads landed at the integration head, by row-landed's write" \
  "- T3: landed $LA_MAIN " "$(lands_step "$PLA" T3)"
expect_contains "LANDS-3b …T4's too" "- T4: landed $LA_MAIN " "$(lands_step "$PLA" T4)"
expect_contains "LANDS-4 …and the card says which rows it landed" "rows-landed: T3 T4 at main @ ${LA_MAIN:0:7}" "$CO_OUT"
expect_eq "LANDS-5 the engaged marker is gone after run, and its removal is the card's last line" "no|yes" \
  "$(tmp_file_exists "$PLA" engaged "$LA_SID")|$(printf '%s\n' "$CO_OUT" | tail -1 | /usr/bin/grep -q '^disengaged: ' && echo yes || echo no)"
# task-set on the delivered plan: the session re-engages and binds it (bound-closed)
lands_poker "$PLA" "$LA_SID" task-set T3 agent=w-merge --reason 'named the agent after delivery'
expect_eq "LANDS-6 an unengaged session is refused at the consent boundary: rc 0, the plan unchanged" \
  "0|landed|—" "$LP_RC|$(lands_cell "$PLA" T3 11)|$(lands_cell "$PLA" T3 6)"
expect_contains "LANDS-6b …saying NOT-ENGAGED" "NOT-ENGAGED" "$LP_OUT"
# the session re-engages and binds its delivered plan by the verb (ruling r1791955629-34788): bound-closed
lands_bind "$PLA" "$LA_SID"
expect_eq "LANDS-7a the bind verb binds the delivered plan (rc 0)" "0" "$LP_RC"
expect_contains "LANDS-7a2 precondition: the session reads its delivered plan as bound-closed (lib/run.sh session_run)" "bound-closed $PLA/$PLAN_REL" \
  "$(bash -c '. "$1/roots.sh" && . "$1/run.sh" || exit 9; session_run "$2" "$3"' _ "$REPO_ROOT/payload/scripts/lib" "$PLA" "$LA_SID")"
LA_CK1="$(cksum < "$PLA/$PLAN_REL")"
lands_poker "$PLA" "$LA_SID" task-set T3 agent=w-merge
expect_eq "LANDS-7 bound to the delivered plan, task-set without --reason keeps the delivered refusal (rc 1), the plan unchanged" \
  "1|$LA_CK1" "$LP_RC|$(cksum < "$PLA/$PLAN_REL")"
expect_contains "LANDS-7b …the refusal naming the closed binding" "no bound open run (bound-closed" "$LP_OUT"
lands_poker "$PLA" "$LA_SID" task-set T3 agent=w-merge --reason 'named the agent after delivery'
expect_eq "LANDS-8 AC-7.7 with --reason it is accepted: rc 0, the cell set, never NOT-ENGAGED" "0|w-merge|no" \
  "$LP_RC|$(lands_cell "$PLA" T3 6)|$(contains "$LP_OUT" "NOT-ENGAGED")"
expect_contains "LANDS-8b …and the reason is recorded on the row's step line, after its landing" \
  "- T3: landed $LA_MAIN " "$(lands_step "$PLA" T3)"
expect_eq "LANDS-8c …ending ' reason: <why>'" "yes" \
  "$(lands_step "$PLA" T3 | /usr/bin/grep -q ' reason: named the agent after delivery$' && echo yes || echo no)"
# no session bound: the rows cannot be landed, so nothing is done
PLB="$(mk_fixture lands-unbound)"; advance_to "$PLB" 8; lands_rows "$PLB"
LB_CK="$(cksum < "$PLB/$PLAN_REL")"
run_close "$PLB" run
expect_eq "LANDS-9 open integrate and close rows with no session bound to the plan: run refuses before the first act, the plan unchanged" \
  "2|$LB_CK" "$CO_RC|$(cksum < "$PLB/$PLAN_REL")"
expect_contains "LANDS-9b …naming the rows and that nothing was done" "rows T3 T4 cannot be landed" "$CO_OUT"
expect_contains "LANDS-9c …nothing was done" "nothing was done" "$CO_OUT"
# a close-out that refuses midway (after act 3) leaves the session engaged: here the continuation cannot be appended to
PLC="$(mk_fixture lands-midway)"; advance_to "$PLC" 8
lands_bind "$PLC" "$LA_SID"
mkdir -p "$PLC/${CONT_REL%/*}"
printf '# continuation — hand written, read-only\n' > "$PLC/$CONT_REL"; chmod 444 "$PLC/$CONT_REL"
run_close_as "$LA_SID" "$PLC" run
expect_eq "LANDS-10 a close-out refused after act 3 (the continuation could not take its deferrals) leaves the session engaged" \
  "2|yes|yes" \
  "$CO_RC|$(contains "$CO_OUT" "could not append the deferrals")|$(tmp_file_exists "$PLC" engaged "$LA_SID")"
chmod 644 "$PLC/$CONT_REL"

# ============================================================
section "§PARKED — wave-38 T15 (REQ-4 AC-4.3; D17): close-out closes a parked wave without the merge act"
# ============================================================
# A plan carrying a non-empty flush-left `## Wake Note`, or a `parked:` line under `## SDLC State`, is parked
# (steps/8.md: "parking requires an explicit ## Wake Note"). `check` prints `merge: parked (<why>)` where it
# printed `merge: WOULD REFUSE`; `run` performs the tail without the merge act: the Step-9 line reads
# `delivered: parked on <working branch> @ <sha>`, the continuation's header says parked, where and why, the epic
# row is written `parked`, the patrol is disarmed, and the handoff's closed form says `resume point: PARKED on
# <branch> @ <sha> — <why>`. Nothing of the work is deleted: the trees and branches stay. `step-line 9` is accepted
# on such a plan. A Wake Note whose body is empty or `(none)` (the old plans' template section) parks nothing.
# fails-when: `check` prints `merge: WOULD REFUSE` on a parked plan; a parked run deletes a branch.
PK_WHY="The release waits on a hand test on the user's machine."
# park_fixture <name> <wake|line|none|unparked> -> a fixture at Step 8 whose working branch carries one commit main
# never took (the facts re-planted at that head), with a ## Wake Note, a parked: line, an empty Wake Note, or neither
park_fixture() {
  local p
  p="$(mk_fixture "$1")"
  advance_to "$p" 8
  ( in_fixture "$p-wave" || exit 1
    printf 'parked work\n' >> file.txt
    git commit -q -am "work main never took" >/dev/null 2>&1 ) || return 1
  plant_facts "$p"
  case "$2" in
    wake) printf '\n## Wake Note\n\n%s\n' "$PK_WHY" >> "$p/$PLAN_REL" ;;
    line) awk -v w="parked: $PK_WHY" '{ print } /^current: / && !d { print w; d = 1 }' "$p/$PLAN_REL" > "$p/pk.tmp" && mv "$p/pk.tmp" "$p/$PLAN_REL" ;;
    none) printf '\n## Wake Note\n\n(none)\n' >> "$p/$PLAN_REL" ;;
  esac
  printf '%s\n' "$p"
}
# pk_handoff <project> -> the handoff document the plan's ## Handoff pointer names
pk_handoff() { local r; r="$(sed -n 's/^handoff: \(.*\) written .*$/\1/p' "$1/$PLAN_REL" | head -1)"; [ -n "$r" ] && cat "$1/$r" 2>/dev/null; }

PPK="$(park_fixture parked1 wake)"
PK_WS="$(fixture_git "$PPK" rev-parse --short wave/01-fixture)"
PK_MAIN0="$(fixture_git "$PPK" rev-parse main)"
expect_nonempty "PK-0 precondition: the working branch names a commit" "$PK_WS"
expect_eq "PK-0b precondition: the working branch is NOT reachable from main (the merge act would refuse)" "1" \
  "$(fixture_git "$PPK" merge-base --is-ancestor wave/01-fixture main; echo $?)"
PK_CK0="$(cksum < "$PPK/$PLAN_REL")"
run_close "$PPK" check
expect_eq "PK-1b …and never merge: WOULD REFUSE" "no" "$(contains "$CO_OUT" "merge: WOULD REFUSE")"
expect_eq "PK-1c …and check writes nothing" "$PK_CK0" "$(cksum < "$PPK/$PLAN_REL")"
run_close "$PPK" run
expect_eq "PK-2 AC-4.3 run closes the parked plan rc 0, and the plan reads closed" "0|1" "$CO_RC|$(run_open_rc "$PPK/$PLAN_REL")"
expect_contains "PK-3 …the Step-9 line reads delivered: parked on <branch> @ <sha>" \
  "- Step 9: delivered: parked on wave/01-fixture @ $PK_WS" "$(/usr/bin/grep -m1 '^- Step 9: ' "$PPK/$PLAN_REL")"
expect_eq "PK-4 …the continuation is written and its header says parked, where and why" "1|yes|yes" \
  "$([ -f "$PPK/$CONT_REL" ] && echo 1 || echo 0)|$(contains "$(sed -n 3p "$PPK/$CONT_REL" 2>/dev/null)" "Parked ")|$(contains "$(sed -n 3,4p "$PPK/$CONT_REL" 2>/dev/null)" "\`wave/01-fixture\` @ $PK_WS")"
expect_absent "PK-4c …and never says the branch was merged" "merged into" "$(sed -n 1,6p "$PPK/$CONT_REL" 2>/dev/null)"
expect_contains "PK-5 …the epic row is written parked" "parked" "$(/usr/bin/grep '^| 01 |' "$PPK/$EPIC_REL")"
expect_contains "PK-7 …the handoff document's resume point is PARKED on <branch> @ <sha>" "resume point: PARKED on wave/01-fixture @ $PK_WS" "$(pk_handoff "$PPK")"
expect_eq "PK-8 the work is kept: wt/01-x and the working branch stand, main never moved" "yes|yes|$PK_MAIN0" \
  "$(branch_exists "$PPK" wt/01-x)|$(branch_exists "$PPK" wave/01-fixture)|$(fixture_git "$PPK" rev-parse main)"
expect_contains "PK-8b …and the card says nothing was removed" "worktree-removed: none — parked" "$CO_OUT"
run_close "$PPK" run
expect_eq "PK-9 a second run says already closed" "0|already closed" "$CO_RC|$CO_OUT"

# a parked: line under ## SDLC State parks too; an unreached wt/* branch does not refuse a parked plan (nothing is deleted)
PPL="$(park_fixture parked2 line)"
add_unreached_branch "$PPL"
run_close "$PPL" check
run_close "$PPL" run
expect_eq "PK-10b …run closes rc 0, keeping both wt/01-x and the unreached wt/01-y" "0|yes|yes" \
  "$CO_RC|$(branch_exists "$PPL" wt/01-x)|$(branch_exists "$PPL" wt/01-y)"

# controls: the merge act's refusal stands on an unparked plan, and on one whose Wake Note is the empty template
for _pk in unparked none; do
  PPU="$(park_fixture "parked-$_pk" "$_pk")"
  PPU_CK="$(cksum < "$PPU/$PLAN_REL")"
  run_close "$PPU" check
  expect_contains "PK-11.$_pk control: an $_pk plan whose branch main never took still reads merge: WOULD REFUSE" \
    "merge: WOULD REFUSE — wave/01-fixture @ " "$CO_OUT"
  run_close "$PPU" run
  expect_eq "PK-11b.$_pk …and run refuses it, naming the merge, the plan unchanged" "2|yes|$PPU_CK" \
    "$CO_RC|$(contains "$CO_OUT" "is not reachable from main")|$(cksum < "$PPU/$PLAN_REL")"
done

# step-line 9: accepted on a parked plan, refused as close-out's on an unparked one
PK_SID="closeout-park-sid"
PPS="$(park_fixture parked3 wake)"
# the `- Step 4:` line every plan past Step 4 carries: step-line's dry commit judges a writer's copy at current: 4 (§LANDS)
awk '/^- Step 7:/ { print "- Step 4: implement: opened 2026-09-14T00:10Z" } { print }' "$PPS/$PLAN_REL" > "$PPS/pk.tmp" && mv "$PPS/pk.tmp" "$PPS/$PLAN_REL"
lands_bind "$PPS" "$PK_SID"
expect_eq "PK-12 precondition: the session is bound to the parked plan" "0" "$LP_RC"
lands_poker "$PPS" "$PK_SID" step-line 9 "parked on wave/01-fixture — $PK_WHY"
PPN="$(park_fixture parked4 unparked)"
lands_bind "$PPN" "$PK_SID"
PPN_CK="$(cksum < "$PPN/$PLAN_REL")"
lands_poker "$PPN" "$PK_SID" step-line 9 "delivered by hand"

# ============================================================
section "§ONE-WRITER — wave-38 T37 (critic-adversarial #2, critic-structure #1; D23): close-out and the handoff verb write one document on a parked or pull-request plan, with one pair of closed lines"
# ============================================================
# The closed document has one writer of its two state lines, `resume point:` and `working branch:`, and both doors
# write them into the one handoff document: close-out.sh's tail, and session-poker.sh `handoff` on the closed plan.
# close-out's document has the verb's sections in the verb's order and keeps what a session composed before the
# close. resume on close-out's parked document reads it parked. FIXTURE FIDELITY: §PARKED's closed parked plan
# (PPK), and §ANY-BRANCH's task-scale plan whose pull request is owed (mk_task_pr_fixture), closed with
# `archive-on-close: false` so the plan stays where the verb can bind it (an archived plan leaves the project root);
# each as close-out left it, the session bound by the verb.
# fails-when: close-out writes another shape or drops a composed section; the two doors' closed lines differ.
. "$REPO_ROOT/payload/scripts/lib/handoff.sh"
ow_file() {  # <project> -> the absolute file the plan's ## Handoff pointer names
  local r
  r="$(sed -n 's/^handoff: \(.*\) written .*$/\1/p' "$1/$PLAN_REL" | head -1)"
  [ -n "$r" ] && printf '%s/%s\n' "$1" "$r"
}
ow_lines() { handoff_line "$1" "resume point"; handoff_line "$1" "working branch"; }  # <file> -> the two closed lines
ow_heads() {  # <file> -> the section headings, in order, each ending on |
  awk -v s="$HANDOFF_SECTIONS" 'BEGIN { n = split(s, h, "|"); for (i = 1; i <= n; i++) H[h[i]] = 1 } ($0 in H) { printf "%s|", $0 }' "$1" 2>/dev/null
}
ow_doors() {  # <label> <project> <sid> -> close-out's document kept at $SANDBOX/ow-copy-<label>, then the verb's; OW_RC, OW_FILE
  cp "$(ow_file "$2")" "$SANDBOX/ow-copy-$1" 2>/dev/null
  lands_bind "$2" "$3"
  lands_poker "$2" "$3" handoff < /dev/null
  OW_RC="$LP_RC"; OW_FILE="$(printf '%s\n' "$LP_OUT" | sed -n 's/^.*handoff — written to //p' | head -1)"
}
OW_SID="closeout-onewriter-sid"
OW_PK="$(ow_file "$PPK")"
: > "$PPK/.bionic/tmp/engaged-$OW_SID.state"
lands_poker "$PPK" "$OW_SID" resume "${OW_PK#"$PPK"/}"
expect_eq "OW-1 resume on close-out's parked document exits 0 and reads it parked; the document has the verb's sections, in order" \
  "0|yes|Summary|Goal|State|Findings|Decisions|Ruled out|Open|Suggested skills|Next|Resume|" \
  "$LP_RC|$(contains "$LP_OUT" "resume point: PARKED on ")|$(ow_heads "$OW_PK")"
ow_doors parked "$PPK" "$OW_SID"
expect_eq "OW-2 the handoff verb on the parked plan exits 0" "0" "$OW_RC"
expect_nonempty "OW-2c precondition: close-out's copy reads" "$(ow_lines "$SANDBOX/ow-copy-parked")"
expect_eq "OW-2d the verb's closed lines are close-out's" "$(ow_lines "$SANDBOX/ow-copy-parked")" "$(ow_lines "$OW_FILE")"

OWR="$(mk_task_pr_fixture ow-pr "fix/x")"
printf 'archive-on-close: false\n' >> "$OWR/.bionic/config.yaml"
OW_FINDING="- the late fix waits — file.txt"
lands_bind "$OWR" "$OW_SID"
lands_poker "$OWR" "$OW_SID" handoff <<< "Findings
$OW_FINDING"
run_close "$OWR" run
expect_eq "OW-3 precondition: close-out closed the task-scale plan rc 0, unmerged and in place" "0|no|yes" \
  "$CO_RC|$(git -C "$OWR" merge-base --is-ancestor fix/x main && echo yes || echo no)|$([ -f "$OWR/$PLAN_REL" ] && echo yes || echo no)"
expect_eq "OW-3b close-out keeps the Finding a session wrote before the close: yes" "yes" "$(grep -q -F -- "$OW_FINDING" "$(ow_file "$OWR")" 2>/dev/null && echo yes || echo no)"
ow_doors pr "$OWR" "$OW_SID"
expect_eq "OW-4 the handoff verb on the pull-request plan exits 0" "0" "$OW_RC"
expect_nonempty "OW-4c precondition: close-out's copy reads" "$(ow_lines "$SANDBOX/ow-copy-pr")"
expect_eq "OW-4d the verb's closed lines are close-out's" "$(ow_lines "$SANDBOX/ow-copy-pr")" "$(ow_lines "$OW_FILE")"

# OW-5: a handoff file of the old shape (the kind line, then lines of facts and five human lines) is carried into the
# closed document, not overwritten: each human line's words land under a section, the facts under State.
ow_sec_of() {  # <file> <words> -> the section heading that holds the first line carrying the words
  awk -v s="$HANDOFF_SECTIONS" -v w="$2" 'BEGIN { n = split(s, h, "|"); for (i = 1; i <= n; i++) H[h[i]] = 1 } ($0 in H) { cur = $0; next } index($0, w) { print cur; exit }' "$1"
}
OWO="$(mk_task_pr_fixture ow-old "fix/x")"
printf 'archive-on-close: false\n' >> "$OWO/.bionic/config.yaml"
OWO_FILE="$(handoff_default_of "$OWO/$PLAN_REL" "$OWO")"
mkdir -p "${OWO_FILE%/*}"
printf '%s\n' "bionic-handoff/v1" "sitrep head: Bottom line" "- You owe nothing now." "written: 2026-01-01T00:00:00Z" \
  "step: 4" "open rows (1):" "  - T9 · w-T9 · .worktrees/T9 · active" \
  "mid-flight: zebra row is halfway" "order: quince goes first" "rulings: D99 mango stays" \
  "lessons: ferret waits for the gate" "risks: walnut will conflict" "/bionic:canonical-sdlc old/path.md" > "$OWO_FILE"
run_close "$OWO" run
expect_eq "OW-5 close-out carries an old-shape handoff file: the human lines under their sections, the facts under State" \
  "0|Open|Next|Decisions|Findings|Open|State|State|State" \
  "$CO_RC|$(ow_sec_of "$OWO_FILE" zebra)|$(ow_sec_of "$OWO_FILE" quince)|$(ow_sec_of "$OWO_FILE" mango)|$(ow_sec_of "$OWO_FILE" ferret)|$(ow_sec_of "$OWO_FILE" walnut)|$(ow_sec_of "$OWO_FILE" 'step: 4')|$(ow_sec_of "$OWO_FILE" 'w-T9')|$(ow_sec_of "$OWO_FILE" 'Bottom line')"

# ============================================================
section "§TOLERANT — wave-38 T15 (REQ-4 AC-4.4): a prose line in the debt ledger is skipped with a note; a missing epic table is added"
# ============================================================
# A line of debt.md that is no table row at all (it carries no ` | ` cell separator: prose a person or an agent wrote)
# is skipped with one note line, `close-out: debt.md:<n> skipped — not a ledger row`, and never refuses; a table row
# that does not parse still refuses (DEBT-LINES, AC-7.8). An epic plan with no shipped table gets the table's header
# written before the row (4e q1.7–q1.12 and §78.3, restated).
# fails-when: either refusal fires.
TL_PROSE='The tree_count item above was raised in a review, and the record holds the reasoning.'
PTL="$(mk_fixture tolerant1)"; advance_to "$PTL" 8
debt_plant "$PTL"
printf '%s\n' "$TL_PROSE" >> "$PTL/.bionic/docs/record/wave-01-fixture/debt.md"
run_close "$PTL" check
expect_eq "TL-1 AC-4.4 check over a ledger with a prose line exits 0 and does not say it would refuse" "0|no" \
  "$CO_RC|$(contains "$CO_OUT" "debt-lines: WOULD REFUSE")"
run_close "$PTL" run
expect_eq "TL-2 AC-4.4 run completes (rc 0) and notes the skip once" "0|1" \
  "$CO_RC|$(printf '%s\n' "$CO_OUT" | /usr/bin/grep -c '^close-out: debt.md:5 skipped — not a ledger row$' | tr -d ' ')"
expect_nonempty "TL-3 precondition: the carry extractor reads the continuation's debt lines" "$(carry_section "$PTL/$CONT_REL" | /usr/bin/grep '^debt: ')"

# an epic plan with no shipped table, beside a prose debt line: both tolerated in one run
PTE="$(mk_fixture tolerant2)"; advance_to "$PTE" 8
printf -- '---\ncanonical_sdlc_version: 14\n---\n\n# epic-fx\n\n## SDLC State\n\ncurrent: 4\n\n## Notes\n\nNo waves table yet.\n' > "$PTE/$EPIC_REL"
debt_plant "$PTE"; printf '%s\n' "$TL_PROSE" >> "$PTE/.bionic/docs/record/wave-01-fixture/debt.md"
run_close "$PTE" run

# ============================================================
section "§SCORECARD — wave-38 T15 (D26): the continuation prints four lines, each against its target, and the sitrep's three indicators"
# ============================================================
# Under `## Scorecard`, fenced, exactly:
#   human stops (autonomous half): <n> · target 1           approved: lines after the plan's approved-by:, one per reply
#   agent minutes after the final reply: <n> · target 0     roster launches of this plan after the approved: merge line
#   widest landing ready→landed: <row> <m> min · target < 15   landing-report --rows, the largest minutes=; 15 is LINE_LANDING_BAR (wave-39 T9)
#   human-wait minutes: <n> · no target (the user's)        the final-card records, render to reply
# then the sitrep's schedule, correctness and waste lines at close. A number the record cannot compute is `unverified`.
# `landing-report --scorecard <plan>` prints the same lines; close-out reads them before the tmp wipe (the roster).
# fails-when: a line is missing, carries a number the record does not hold, or prints a literal where it is unverified.
sc_section() { awk '/^## / { s = ($0 == "## Scorecard"); next } s && NF && !/^```/ { print }' "$1"; }
sc_plant() {  # <project> -> two queue landings (30 and 42 min), three approvals in two replies, two launches, one final card
  local p="$1" plan="$1/$PLAN_REL" rec="$1/.bionic/docs/record/wave-01-fixture"
  case "$p" in "$SANDBOX"/*) : ;; *) echo "sc_plant: refusing outside the sandbox: '$p'" >&2; return 1 ;; esac
  mkdir -p "$rec"
  {
    printf 'line/v1|ev=ready|row=T1|name=w-T1|commit=%s|branch=wt/01-T1|tree=%s/.worktrees/01-T1|suites=a.test.sh|debt=-|carrier=1:x|at=2026-10-06T10:00:00Z\n' "$LAND_C" "$p"
    printf 'line/v1|ev=published|row=T1|commit=%s|kind=queue|by=-|why=-|at=2026-10-06T10:30:00Z\n' "$LAND_C"
    printf 'line/v1|ev=ready|row=T2|name=w-T2|commit=%s|branch=wt/01-T2|tree=%s/.worktrees/01-T2|suites=a.test.sh|debt=-|carrier=1:x|at=2026-10-06T11:00:00Z\n' "$LAND_C" "$p"
    printf 'line/v1|ev=published|row=T2|commit=%s|kind=queue|by=-|why=-|at=2026-10-06T11:42:00Z\n' "$LAND_C"
  } > "$rec/landing-proofs.log"
  awk '{ print } /^approved-by: / && !d {
         print "approved: doc by fixture 2026-10-05T09:00:00Z \"go ahead\""
         print "approved: release by fixture 2026-10-06T12:00:00Z \"1\""
         print "approved: merge by fixture 2026-10-06T12:00:01Z \"1\""; d = 1 }' "$plan" > "$plan.sc" && mv "$plan.sc" "$plan"
  {
    roster_row_fixture status=intended name=w-early agent_id= launched_at=2026-10-06T09:00:00Z plan="$plan"
    roster_row_fixture status=intended name=w-late agent_id= launched_at=2026-10-06T12:05:01Z plan="$plan"
    roster_row_fixture status=intended name=w-other agent_id= launched_at=2026-10-06T13:00:00Z plan="/elsewhere/wave-99-other.plan.md"
  } >> "$p/.bionic/tmp/roster-fixture.state"
  printf '%s\n' '**Final card · wave-01-fixture at abcdef12**' '' '## Replay' '' \
    "final-card/v1|plan=$plan|head=$LAND_C|at=2026-10-06T11:48:01Z|options=1" \
    'replied: at=2026-10-06T12:00:01Z option=1 words="1"' > "$rec/final-card-abcdef12.md"
}
SC_TAIL='human-wait minutes: 12 · no target (the user'"'"'s)'
PSC="$(mk_fixture scorecard1)"; advance_to "$PSC" 8
sc_plant "$PSC"
SC_VERB="$(BIONIC_GATE_DIR="$LAND_GATE" hh_report "$PSC" --scorecard)"
expect_eq "SC-0b …then the sitrep's three indicator lines, schedule, correctness and waste, and nothing more" "schedule|correctness|waste|7" \
  "$(printf '%s\n' "$SC_VERB" | sed -n 5p | cut -d' ' -f2)|$(printf '%s\n' "$SC_VERB" | sed -n 6p | cut -d' ' -f2)|$(printf '%s\n' "$SC_VERB" | sed -n 7p | cut -d' ' -f2)|$(printf '%s\n' "$SC_VERB" | /usr/bin/grep -c . | tr -d ' ')"
BIONIC_GATE_DIR="$LAND_GATE" run_close "$PSC" run
expect_nonempty "SC-1b precondition: the extractor finds lines under the heading" "$(sc_section "$PSC/$CONT_REL")"
expect_eq "SC-2 D26 the section is the verb's seven lines, read before the wipe (the roster's launch counted)" \
  "$SC_VERB" "$(sc_section "$PSC/$CONT_REL")"
expect_eq "SC-4 …the heading sits before the Resume instruction" "yes" \
  "$(awk '/^## Scorecard$/ { a = NR } /^## Resume instruction/ { b = NR } END { print (a && b > a) ? "yes" : "no" }' "$PSC/$CONT_REL")"
# the wait is read from the card's record under each name it has had: the release approval stem and tag, the old stem and
# tag a run wrote before the rename, and the final card's
sc_wait() { printf '%s\n' "$1" | /usr/bin/grep '^human-wait minutes: '; }
expect_eq "SC-5 precondition: the final-card record gives the 12-minute wait" "$SC_TAIL" "$(sc_wait "$SC_VERB")"
SC_OLDW="review"
for sc_stem in release-approval "${SC_OLDW}-results"; do
  PSW="$(mk_fixture "scorecard-$sc_stem")"; advance_to "$PSW" 8
  sc_plant "$PSW"
  SC_REC="$PSW/.bionic/docs/record/wave-01-fixture"
  sed -e "s#^final-card/v1|#${sc_stem}/v1|#" "$SC_REC/final-card-abcdef12.md" > "$SC_REC/${sc_stem}-abcdef12.md"
  rm -f "$SC_REC/final-card-abcdef12.md"
  expect_eq "SC-5b the record named $sc_stem-<head8>.md with the $sc_stem/v1 tag gives the same wait" "$SC_TAIL" \
    "$(sc_wait "$(BIONIC_GATE_DIR="$LAND_GATE" hh_report "$PSW" --scorecard)")"
done
# a record that cannot compute a number prints unverified on that line, never a literal
PSU="$(mk_fixture scorecard2)"; advance_to "$PSU" 8
BIONIC_GATE_DIR="$LAND_GATE" run_close "$PSU" run
# an existing continuation gets the section added, once
PSE="$(mk_fixture scorecard3)"; advance_to "$PSE" 8
mkdir -p "$PSE/${CONT_REL%/*}"
printf '# continuation — hand written\n\n## Deferrals\n\n## Resume instruction\n\nedited by a person\n' > "$PSE/$CONT_REL"
BIONIC_GATE_DIR="$LAND_GATE" run_close "$PSE" run

# ============================================================
section "§ASKS-NOTHING — wave-38 T15 (D17; AC-1.6, AC-1.7): close-out puts no question to the user"
# ============================================================
# Close-out asks nothing: no `read` in close-out.sh reaches a terminal (every one is a loop fed by a here-string, a
# pipe or a file), nothing prompts, and the Step-9 doctrine no longer asks the user's materiality ruling at close.
# fails-when: a prompt or a terminal read is added, or steps/9.md asks a ruling.
AN_READS="$(/usr/bin/grep -nE '(^|[^A-Za-z_])read[[:space:]]+-r' "$SCRIPT")"
expect_nonempty "AN-0 precondition: the extractor finds close-out.sh's read loops" "$AN_READS"
expect_empty "AN-1 every read in close-out.sh is a while-loop fed by a redirect or a pipe" \
  "$(printf '%s\n' "$AN_READS" | /usr/bin/grep -v 'while')"
expect_empty "AN-2 nothing reads the terminal or prompts (/dev/tty, read -p, select)" \
  "$(/usr/bin/grep -nE '/dev/tty|read[[:space:]]+-[a-z]*p|^[[:space:]]*select[[:space:]]' "$SCRIPT")"
AN_STEP9="$REPO_ROOT/skills/canonical-sdlc/steps/9.md"

finish
