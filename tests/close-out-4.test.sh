#!/bin/bash
# tests/close-out-4.test.sh — payload/scripts/close-out.sh, part 4 of 6: sections §INHERITED-CONT through §ASKS-NOTHING.
#
# THE SUITE IS FOUR PARTS: one close-out.test.sh outran the suite bar, so it runs as
# four suites cut at section boundaries. Its design, sandbox, fixture builders and helpers are in tests/close-out.prelude.sh.
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
# `proof-add inherited <suite>` writes a `proof kind=inherited` event in the run's log: debt the run inherited, red at
# its base and at its floor. The reader renders each as `inherited: <suite> base=<sha> head=<sha> at=<ISO>
# evidence=<log>`, and close-out lists every such line under `## Inherited debt`, beside the hand-holds; a line a
# person typed inside a fence in the page is prose and is not carried.
# FIXTURE FIDELITY: mk_fixture at Step 8; each debt written by lib/proof.sh `proof_event`, the verb's own writer, with
# the fields and the instant the verb gives it.
# fails-when: an inherited debt is missing from the continuation, or a plan with none gets the heading.
inh_line() {  # <suite> <sha> -> the line the reader renders for the debt proof-add inherited writes
  printf 'inherited: %s base=%s head=%s at=2026-10-12T04:00:00Z evidence=record/wave-01-fixture/inherited-%s-%.12s.log' "$1" "$2" "$2" "$1" "$2"
}
inh_place() {  # <project> <line> -> the inherited: line's fact in the run, the proof event proof-add inherited writes
  case "$2" in inherited:\ *) ;; *) echo "inh_place: only an inherited: line is written here: '$2'" >&2; return 1 ;; esac
  local s b h a e
  read -r _ s b h a e <<< "$2"
  bash -c '. "$1/run.sh" && . "$1/proof.sh" || exit 1; LOG_AT="$3" proof_event "$2" kind=inherited "head=$4" "evidence=$5" "suite=$6" "base=$7"' \
    _ "$REPO_ROOT/payload/scripts/lib" "$1/$PLAN_REL" "${a#at=}" "${h#head=}" "${e#evidence=}" "$s" "${b#base=}"
}
inh_section() { awk '/^## / { s = ($0 == "## Inherited debt"); next } s && NF && !/^```/ { print }' "$1"; }
PINH="$(mk_fixture inherited-cont)"; advance_to "$PINH" 8
INH_H="$(fixture_git "$PINH" rev-parse --verify -q wave/01-fixture)"
inh_place "$PINH" "$(inh_line a.test.sh "$INH_H")"
inh_place "$PINH" "$(inh_line b.test.sh "$INH_H")"
awk '/^## Tasks/ { print "```"; print "inherited: fenced.test.sh base=0123456789ab head=0123456789ab at=x evidence=y"; print "```"; print "" } { print }' \
  "$PINH/$PLAN_REL" > "$PINH/$PLAN_REL.f" && mv "$PINH/$PLAN_REL.f" "$PINH/$PLAN_REL"
seal_fixture "$PINH/$PLAN_REL" "$PINH/$LOG_REL"
run_close "$PINH" run
expect_eq "INH-1 run closes the plan (rc 0)" "0" "$CO_RC"
expect_eq "INH-2b …the section is the run's two debts, in order, and not the fenced line" \
  "$(inh_line a.test.sh "$INH_H")|$(inh_line b.test.sh "$INH_H")" "$(inh_section "$PINH/$CONT_REL" | paste -sd'|' -)"
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
# reads the records of the sessions in the run's Step-4..9 window (the instant of the run's Step-4 event, else of its
# plan approval's, to now), BEFORE the tmp wipe takes them, and writes one `governed-by: <root> <commit> from
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
# gov_at <project> <event's head> <ISO|""> -> that event of the run's log stamped at <ISO>; empty, it keeps no instant,
# as the translation writes a step whose line had none
gov_at() {
  case "$1" in "$SANDBOX"/*) : ;; *) echo "gov_at: refusing outside the sandbox: '$1'" >&2; return 1 ;; esac
  awk -v h="run/v1|$2|" -v a="$3" 'index($0, h) == 1 { sub(/\|at=[^|]*/, "|at=" a) } { print }' "$1/$LOG_REL" > "$1/gov.log" \
    && mv "$1/gov.log" "$1/$LOG_REL"
  seal_fixture "$1/$PLAN_REL" "$1/$LOG_REL"
}
gov_section() { awk '/^## / { s = ($0 == "## Governed by"); next } s && NF && !/^```/ { print }' "$1"; }
gov_card() { printf '%s\n' "$CO_OUT" | /usr/bin/grep '^governed-by: '; }

PG="$(mk_fixture governed)"; advance_to "$PG" 8
gov_at "$PG" 'ev=step|n=4' 2026-10-13T20:39:00Z
GOV_CACHE="$SANDBOX/governed-cache/bionic/1.18.0"
mkdir -p "$GOV_CACHE/.claude-plugin"; printf '{\n  "name": "bionic",\n  "version": "1.18.0"\n}\n' > "$GOV_CACHE/.claude-plugin/plugin.json"
gov_record "$PG" s0 "/elsewhere/old/payload" 1111111111111111111111111111111111111111 2026-10-13T19:00:00Z   # before Step 4
gov_record "$PG" s1 "$GOV_ROOT" "$GOV_C1" 2026-10-13T23:55:11Z
gov_record "$PG" s2 "$GOV_ROOT" "$GOV_C1" 2026-10-14T01:00:00Z
gov_record "$PG" s3 "$GOV_ROOT" "$GOV_C2" 2026-10-14T03:00:00Z
gov_record "$PG" s4 "$GOV_CACHE" - 2026-10-13T21:00:00Z
ln -s "$PG/.bionic/tmp/loaded-s0.state" "$PG/.bionic/tmp/loaded-s5.state"   # a link is never a record
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
gov_at "$PGN" 'ev=step|n=4' 2026-10-13T20:39:00Z
gov_record "$PGN" s0 "/elsewhere/old/payload" 1111111111111111111111111111111111111111 2026-10-13T19:00:00Z
run_close "$PGN" run
expect_eq "GOV-4 AC-1.4 no record in the window: governed-by: installed <version>, on the card and in the continuation" \
  "0|governed-by: installed $GOV_VER|governed-by: installed $GOV_VER" "$CO_RC|$(gov_card)|$(gov_section "$PGN/$CONT_REL")"

# no instant on the Step-4 event: the window opens at the plan approval's
PGA="$(mk_fixture governed-approved)"; advance_to "$PGA" 8
gov_at "$PGA" 'ev=step|n=4' ""; gov_at "$PGA" 'ev=approval|key=step3' 2026-09-14T00:00:00Z
gov_record "$PGA" s0 "/elsewhere/old/payload" 1111111111111111111111111111111111111111 2026-09-13T23:00:00Z
gov_record "$PGA" s1 "$GOV_ROOT" "$GOV_C1" 2026-09-14T00:30:00Z
run_close "$PGA" check
expect_eq "GOV-5a the window opens at the plan approval: the later record governs, the earlier does not" \
  "governed-by: $GOV_ROOT $GOV_C1 from 2026-09-14T00:30:00Z" "$(gov_card)"

# an existing continuation: the section is merged in, the person's text kept, and a second close adds nothing
PGE="$(mk_fixture governed-existing)"; advance_to "$PGE" 8
gov_at "$PGE" 'ev=step|n=4' 2026-10-13T20:39:00Z
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
gov_at "$PGM" 'ev=step|n=4' 2026-10-13T20:39:00Z
gov_record "$PGM" s1 "$GOV_ROOT" "$GOV_C1" 2026-10-13T23:55:11Z
( cd "$PGM" && HOME="$SB_HOME" CLAUDE_PROJECT_DIR="" BIONIC_PLUGIN_ROOT="$REPO_ROOT/payload" BIONIC_CLAUDE_HOME="$SB_HOME/.claude" \
    bash "$GOV_MUT/scripts/close-out.sh" "$PGM/$PLAN_REL" run ) > "$SANDBOX/gov-mut.out" 2>&1
expect_eq "GOV-mut2 …and its continuation names the installed version while a record named the checkout" \
  "governed-by: installed $GOV_VER" "$(gov_section "$PGM/$CONT_REL")"
rm -rf "$GOV_MUT"

# ============================================================
section "§HAND-HOLDS-KINDS — wave-36 T14 (D13; REQ-7 AC-7.6): adopt's adoptions and the fixed disposals are folded under their own kinds, never as by-hand"
# ============================================================
# Every act a verb writes is folded under its own kind, and each kind of act by hand the hands question answers is one
# line of the continuation's ## Hand acts: its name, its count, each distinct reason once, in the order first given.
# fails-when: by-hand>0 for these acts, a kind omitted from either, a reason given twice, or a line for a kind with no act.
# FIXTURE FIDELITY: an amend, a hold, an extension and an adoption are the shipped verbs, driven as the session bound to the
# plan, each writing its own event; a by-hand landing (of a row no build row names, so no window opens) and two stops
# of a run with one reason are planted in their writers' shapes (driving them takes a landing tree and a live run:
# tests/reader.test.sh §HANDS drives both); the move is finding-move's event, written by its writer.
HK_P="$(mk_fixture handholds-kinds)"; advance_to "$HK_P" 8
HK_PLAN="$HK_P/$PLAN_REL"; HK_SID="closeout-hands-1"; HK_PRED="9f1e2d3c-4b5a-6978-8899-aabbccddeeff"; HK_RC=""
( in_fixture "$HK_P" || exit 1; . "$REPO_ROOT/tests/lib/bound-marker.sh"; bound_marker "$HK_P" "$HK_SID" "$HK_PLAN" )
for s in "$HK_SID" "$HK_PRED"; do bash -c '. "$1/roster.sh" && roster_header' _ "$REPO_ROOT/payload/scripts/lib" > "$HK_P/.bionic/tmp/roster-$s.state"; done
roster_row_fixture status=identified session="$HK_SID" name=w1 agent_id=aw1 plan="$HK_PLAN" files=hooks/a.sh suites_allowed=a.test.sh \
  suites_source=declared >> "$HK_P/.bionic/tmp/roster-$HK_SID.state"
roster_row_fixture status=identified session="$HK_PRED" name=w-ad agent_id=ad plan="$HK_PLAN" >> "$HK_P/.bionic/tmp/roster-$HK_PRED.state"
{ printf 'run/v1|ev=published|row=T9|commit=%s|kind=hand|by=Chris|why=no Lands-on could be read|at=2026-10-06T10:40:00Z\n' "$(printf 'd%.0s' $(seq 40))"
  for r in r1 r2; do printf 'run/v1|ev=hand|by=Chris|name=w-%s|run=%s|what=stop-run|why=hung on a closed pipe|at=2026-10-06T10:5%s:00Z\n' "$r" "$r" "${r#r}"; done
} >> "$HK_P/.bionic/docs/record/wave-01-fixture/run.log"
seal_fixture "$HK_PLAN" "$HK_P/$LOG_REL"
hk_poke() { ( in_fixture "$HK_P" || exit 9; HOME="$SB_HOME" CLAUDE_PROJECT_DIR="" BIONIC_CLAUDE_HOME="$SB_HOME/.claude" \
  CLAUDE_CODE_SESSION_ID="$HK_SID" bash "$BIONIC_HOOKS_DIR/session-poker.sh" "$@" ) >> "$SANDBOX/hk-poker" 2>&1; HK_RC="$HK_RC$?"; }
hk_poke amend w1 --files+ lib/z.sh --reason 'the brief missed lib/z.sh'; hk_poke hold w1 'kept for a second pass'
hk_poke extend w1 'more to read'; hk_poke adopt --why 'the session was cleared'
expect_regex "HK-0 precondition: amend, hold and extend exit 0, adopt 0 or 1 (open rows found)" '^000[01]$' "$HK_RC"
# a move to fixed is placed against its row's first landing that names its kind, as every landing the line writes does
awk -v c="$(printf 'e%.0s' $(seq 40))" 'index($0, "run/v1|ev=published|row=T1|at=") == 1 { sub(/\|at=/, "|commit=" c "|kind=queue|by=-|why=-|at=") } { print }' \
  "$HK_P/.bionic/docs/record/wave-01-fixture/run.log" > "$HK_P/hk.log" && mv "$HK_P/hk.log" "$HK_P/.bionic/docs/record/wave-01-fixture/run.log"
seal_fixture "$HK_PLAN" "$HK_P/$LOG_REL"
bash -c '. "$1/run.sh" && . "$1/proof.sh" || exit 1; LOG_AT=2026-10-06T14:00:00Z proof_finding_event "$2" ref=record/wave-01-fixture/rev.md#1 to=fixed row=T1 "by=Chris Lehman"' \
  _ "$REPO_ROOT/payload/scripts/lib" "$HK_PLAN"
# the run has landed build rows, so the count is over the window from the last of them, and says what it left out
HK_WANT="hand-holds: total=8 · by-hand=1 · stop-runs=2 · declines=0 · lifts=0 · amends=1 · holds=1 · extensions=1 · waivers=0 · second-regressions=0 · adoptions=1 · fixed=1 · needs-you=0 · unplaced=0"
expect_eq "HK-1 one act of each kind, and one to=fixed move, each read under its own kind, by-hand the landing alone, in the total" \
  "$HK_WANT" "$(hh_report "$HK_P" --hand-holds | grep '^hand-holds: ')"
run_close "$HK_P" check
expect_eq "HK-2 …and close-out's card prints the same line" "$HK_WANT" "$(printf '%s\n' "$CO_OUT" | grep '^hand-holds: ')"
run_close "$HK_P" run
expect_eq "HK-3 the continuation carries one line per kind with an act, its count and each reason once, and none for a kind with none" \
  "0|hand act: landing by hand · 1 · no Lands-on could be read
hand act: stop-run · 2 · hung on a closed pipe
hand act: amend · 1 · the brief missed lib/z.sh
hand act: hold · 1 · kept for a second pass
hand act: extend · 1 · more to read
hand act: adopt · 1 · the session was cleared" \
  "$CO_RC|$(awk '/^## / { s = ($0 == "## Hand acts"); next } s && /^hand act/' "$HK_P/$CONT_REL")"

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
section "§LANDS — wave-36 T14 (D13; REQ-7 AC-7.7; C70): close-out lands the rows its merge lands, keeps the session engaged until its last act, and a delivered plan binds bound-closed"
# ============================================================
# The rows close-out's merge lands are the plan's open (pending or active) rows of kind `integrate` (the merge
# itself) and `close` (the row the merge is read by, `merge` in units.sh's reads). Each is landed by one `published`
# event at the integration head, of the close kind and by close-out, after act 1 and before act 2, so the plan
# close-out delivers reads them landed through the units helper, with no cell or step line written.
# A run with such rows and no session bound to this plan is refused before the first act, nothing done. Act 3 keeps
# this session's engaged marker, which is also its binding; it is wiped as close-out's last act, so a close-out
# that refuses midway leaves the session engaged and its plan verbs working. A session that re-engages and binds the
# delivered plan reads it bound-closed; its cells are changed by an edit of the file, never by a verb.
# fails-when: a delivered plan reads a row its merge landed as pending; the bind of a delivered plan is refused; the
# marker is gone after a refusal midway.
lands_rows() {  # <project> -> the plan gains T3 (step 8, integrate) and T4 (step 9, close), pending: two nine-cell rows, nothing dispatching them,
  # and the release approval its integrate row is asked
  local plan="$1/$PLAN_REL"
  case "$1" in "$SANDBOX"/*) : ;; *) echo "lands_rows: refusing outside the sandbox: '$1'" >&2; return 1 ;; esac
  release_approved "$1"
  awk '{ print } /^\| T2 \|/ { print "| T3 | 8 | integrate | merge the wave into main | — | 10 | AC-1 | none | — |"
    print "| T4 | 9 | close | close-out, continuation.md | — | 10 | AC-1 | none | — |" }' "$plan" > "$plan.l" && mv "$plan.l" "$plan"
  seal_fixture "$plan" "$1/$LOG_REL"
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
lands_state() {  # <project> <id> -> the row's state as the units helper reads it, the run's log over its cells
  ( . "$REPO_ROOT/payload/scripts/lib/units.sh" >/dev/null 2>&1; units_rows "$1/$PLAN_REL" 2>/dev/null ) | awk -F'\t' -v id="$2" '$1 == id { print $10; exit }'
}
lands_pub() {  # <project> <id> -> the row's published events in its run's log, `<commit> <kind> <by>` each
  cat "$1"/.bionic/docs/record/*/run.log 2>/dev/null | awk -F'|' -v id="$2" '$2 == "ev=published" && $3 == "row=" id {
    c = k = b = ""; for (i = 4; i <= NF; i++) { if ($i ~ /^commit=/) c = substr($i, 8); if ($i ~ /^kind=/) k = substr($i, 6); if ($i ~ /^by=/) b = substr($i, 4) }
    print c, k, b }'
}
LA_SID="closeout-lands-sid"
PLA="$(mk_fixture lands)"; advance_to "$PLA" 8; lands_rows "$PLA"
awk '{ print } /^\| T4 \|/ { print "| T5 | 8 | integrate | a second merge | — | 10 | AC-1 | none | — |" }' "$PLA/$PLAN_REL" > "$PLA/t5" && mv "$PLA/t5" "$PLA/$PLAN_REL"
seal_fixture "$PLA/$PLAN_REL" "$PLA/$LOG_REL"
LA_MAIN="$(fixture_git "$PLA" rev-parse --verify -q main)"
lands_bind "$PLA" "$LA_SID"
expect_eq "LANDS-0 precondition: the session is bound (the verb said so), and T3 and T4 read pending" "0|pending|pending" \
  "$LP_RC|$(lands_state "$PLA" T3)|$(lands_state "$PLA" T4)"
LA_CK0="$(cksum < "$PLA/$PLAN_REL")"
lands_poker "$PLA" "$LA_SID" task-add T5 --drop 'no longer owed'
expect_eq "LANDS-0b the person drops T5 through its door, which writes no plan" "0|$LA_CK0" "$LP_RC|$(cksum < "$PLA/$PLAN_REL")"
run_close_as "$LA_SID" "$PLA" check
expect_eq "LANDS-1b …and writes nothing" "$LA_CK0" "$(cksum < "$PLA/$PLAN_REL")"
LA_ROWS0="$(cat "$PLA/$PLAN_REL")"; run_close_as "$LA_SID" "$PLA" run
expect_eq "LANDS-2 AC-7.7 run exits 0 and the delivered plan reads both rows landed (run_open says closed)" "0|landed|landed|1" \
  "$CO_RC|$(lands_state "$PLA" T3)|$(lands_state "$PLA" T4)|$(run_open_rc "$PLA/$PLAN_REL")"
expect_eq "LANDS-3 …each row by one published event at the integration head, of the close kind, by close-out" \
  "$LA_MAIN close close-out|$LA_MAIN close close-out" "$(lands_pub "$PLA" T3)|$(lands_pub "$PLA" T4)"
expect_eq "LANDS-3b …and neither row of the plan is written" "$(/usr/bin/grep -E '^\| T[345] \|' <<< "$LA_ROWS0")" \
  "$(/usr/bin/grep -E '^\| T[345] \|' "$PLA/$PLAN_REL")"
expect_contains "LANDS-4 …and the card says which rows it landed, the row the log drops not among them" "rows-landed: T3 T4 at main @ ${LA_MAIN:0:7}" "$CO_OUT"
expect_eq "LANDS-4b …which reads dropped, with no landing" "dropped|" "$(lands_state "$PLA" T5)|$(lands_pub "$PLA" T5)"
expect_eq "LANDS-5 the engaged marker is gone after run, and its removal is the card's last line" "no|yes" \
  "$(tmp_file_exists "$PLA" engaged "$LA_SID")|$(printf '%s\n' "$CO_OUT" | tail -1 | /usr/bin/grep -q '^disengaged: ' && echo yes || echo no)"
# the session re-engages and binds its delivered plan by the verb (ruling r1791955629-34788): bound-closed
lands_bind "$PLA" "$LA_SID"
expect_eq "LANDS-7a the bind verb binds the delivered plan (rc 0)" "0" "$LP_RC"
expect_contains "LANDS-7a2 precondition: the session reads its delivered plan as bound-closed (lib/run.sh session_run)" "bound-closed $PLA/$PLAN_REL" \
  "$(bash -c '. "$1/roots.sh" && . "$1/run.sh" || exit 9; session_run "$2" "$3"' _ "$REPO_ROOT/payload/scripts/lib" "$PLA" "$LA_SID")"
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
# The close typed by hand lands no row a writer holds: with a writer live on the close row it refuses, and lands
# nothing, because a row landed mid-work reads finished while its writer still writes it. The writer is a roster row of this session dispatched for T4 under this plan, launched a minute ago, as the dispatch wall writes it.
# fails-when: a landing is written for that row.
lands_writer() {  # <project> <sid> <row> -> a live writer for <row> on <sid>'s roster, under the project's plan
  roster_row_fixture session="$2" name="w-$3" row="$3" agent_id="a$3-live" plan="$1/$PLAN_REL" duration="4 hours" \
    launched_at="$(t=$(( $(date +%s) - 60 )); date -u -r "$t" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$t" +%Y-%m-%dT%H:%M:%SZ)" \
    >> "$1/.bionic/tmp/roster-$2.state"
}
PLO="$(mk_fixture lands-out)"; advance_to "$PLO" 8; lands_rows "$PLO"; lands_bind "$PLO" "$LA_SID"; lands_writer "$PLO" "$LA_SID" T4
LO_CK="$(cksum < "$PLO/$PLAN_REL")"
expect_eq "LANDS-11 precondition: the session is bound, and T4's writer reads open on its roster" "0|w-T4" \
  "$LP_RC|$(bash -c '. "$1/roster.sh" && roster_open_names "$2"' _ "$REPO_ROOT/payload/scripts/lib" "$PLO/.bionic/tmp/roster-$LA_SID.state")"
run_close_as "$LA_SID" "$PLO" run
expect_eq "LANDS-11a AC-8.3 a writer live on the close row: run refuses, the plan unchanged, and no landing is written for T3 or T4" \
  "2|$LO_CK||" "$CO_RC|$(cksum < "$PLO/$PLAN_REL")|$(lands_pub "$PLO" T3)|$(lands_pub "$PLO" T4)"
expect_contains "LANDS-11b …naming the row out and its writer, and that nothing was done" "rows out: T4 (w-T4" "$CO_OUT"
expect_contains "LANDS-11c …nothing was done" "nothing was done" "$CO_OUT"
: > "$PLO/.bionic/tmp/roster-$LA_SID.state"
run_close_as "$LA_SID" "$PLO" run
expect_eq "LANDS-11d …and with the writer gone, run lands both rows" "0|landed|landed" "$CO_RC|$(lands_state "$PLO" T3)|$(lands_state "$PLO" T4)"
# The continuation has one writer. A close row that was dispatched and whose Files name the continuation owns
# it, so the close writes none of it; the writer's file stands byte for byte.
# fails-when: the close appends to the continuation the close row's writer wrote.
PLW="$(mk_fixture lands-writes)"; advance_to "$PLW" 8; lands_rows "$PLW"
awk -v c="$CONT_REL" '/^\| T4 \|/ { print "| T4 | 9 | close | close-out, continuation.md | — | 10 | AC-1 | " c " | — |"; next } { print }' \
  "$PLW/$PLAN_REL" > "$PLW/t4" && mv "$PLW/t4" "$PLW/$PLAN_REL"
printf 'run/v1|ev=dispatch|row=T4|name=w-T4|at=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$PLW/$LOG_REL"
seal_fixture "$PLW/$PLAN_REL" "$PLW/$LOG_REL"; lands_bind "$PLW" "$LA_SID"
mkdir -p "$PLW/${CONT_REL%/*}"; printf '# continuation — written by the close row T4\n\nthe writer'"'"'s words\n' > "$PLW/$CONT_REL"
LW_CK="$(cksum < "$PLW/$CONT_REL")"
run_close_as "$LA_SID" "$PLW" run
expect_eq "LANDS-12 the close row dispatched owns the continuation: run exits 0, lands T4, and the writer's file is as written" \
  "0|landed|$LW_CK" "$CO_RC|$(lands_state "$PLW" T4)|$(cksum < "$PLW/$CONT_REL")"
[ "$CO_RC" = 0 ] || printf '%s\n' "$CO_OUT" | tail -8 | sed 's/^/    | /'
expect_contains "LANDS-12b …and the card says whose it is" "continuation: ${CONT_REL#.bionic/docs/} is the close row T4's" "$CO_OUT"
# A writer once dispatched began the continuation, and the stand-down took its launch back: no dispatch stands, but the
# file is still that writer's, so the close writes none of it.
# fails-when: the close appends to a continuation whose writer's dispatch was taken back.
PLK="$(mk_fixture lands-taken-back)"; advance_to "$PLK" 8; lands_rows "$PLK"
awk -v c="$CONT_REL" '/^\| T4 \|/ { print "| T4 | 9 | close | close-out, continuation.md | — | 10 | AC-1 | " c " | — |"; next } { print }' \
  "$PLK/$PLAN_REL" > "$PLK/t4" && mv "$PLK/t4" "$PLK/$PLAN_REL"
LK_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf 'run/v1|ev=dispatch|row=T4|name=w-T4|at=%s\nrun/v1|ev=cancel|of=dispatch|row=T4|name=w-T4|at=%s\n' "$LK_AT" "$LK_AT" >> "$PLK/$LOG_REL"
seal_fixture "$PLK/$PLAN_REL" "$PLK/$LOG_REL"; lands_bind "$PLK" "$LA_SID"
mkdir -p "$PLK/${CONT_REL%/*}"; printf '# continuation — begun by the close row T4\n\nthe writer'"'"'s words\n' > "$PLK/$CONT_REL"
LK_CK="$(cksum < "$PLK/$CONT_REL")"
expect_eq "LANDS-13 precondition: T4's launch was taken back, so no dispatch of it stands and it reads pending" "pending" "$(lands_state "$PLK" T4)"
run_close_as "$LA_SID" "$PLK" run
expect_eq "LANDS-13a a close row whose dispatch was taken back still owns the continuation: run exits 0 and the file is as its writer left it" \
  "0|$LK_CK" "$CO_RC|$(cksum < "$PLK/$CONT_REL")"
[ "$CO_RC" = 0 ] || printf '%s\n' "$CO_OUT" | tail -8 | sed 's/^/    | /'
expect_contains "LANDS-13b …and the card says whose it is" "continuation: ${CONT_REL#.bionic/docs/} is the close row T4's" "$CO_OUT"
# A close row whose record does not stand is not finished, so the merge does not land it: it stays open, named on the
# card, and the integrate row beside it lands as before.
# fails-when: the merge writes a landing for a close row whose record was never written.
PLR="$(mk_fixture lands-no-record)"; advance_to "$PLR" 8; lands_rows "$PLR"
LR_REC="record/wave-01-fixture/T4.md"
awk -v c="$LR_REC" '/^\| T4 \|/ { print "| T4 | 9 | close | close-out, the close record | — | 10 | AC-1 | " c " | — |"; next } { print }' \
  "$PLR/$PLAN_REL" > "$PLR/t4" && mv "$PLR/t4" "$PLR/$PLAN_REL"
seal_fixture "$PLR/$PLAN_REL" "$PLR/$LOG_REL"; lands_bind "$PLR" "$LA_SID"
LR_MAIN="$(fixture_git "$PLR" rev-parse --verify -q main)"
expect_eq "LANDS-14 precondition: T4's record is not on disk and T3 and T4 read pending" "no|pending|pending" \
  "$([ -e "$PLR/.bionic/docs/$LR_REC" ] && echo yes || echo no)|$(lands_state "$PLR" T3)|$(lands_state "$PLR" T4)"
run_close_as "$LA_SID" "$PLR" run
expect_eq "LANDS-14a a close row with no record reads open after the close, with no landing, and the integrate row lands" \
  "0|landed|$LR_MAIN close close-out|pending|" \
  "$CO_RC|$(lands_state "$PLR" T3)|$(lands_pub "$PLR" T3)|$(lands_state "$PLR" T4)|$(lands_pub "$PLR" T4)"
[ "$CO_RC" = 0 ] || printf '%s\n' "$CO_OUT" | tail -8 | sed 's/^/    | /'
expect_contains "LANDS-14b …and the card names it left open, beside the row it landed" \
  "rows-landed: T3 at main @ ${LR_MAIN:0:7}; T4 left open — no record it names stands" "$CO_OUT"

# ============================================================
section "§PARKED — wave-38 T15 (REQ-4 AC-4.3; D17): close-out closes a parked wave without the merge act"
# ============================================================
# A plan carrying a non-empty flush-left `## Wake Note` is parked
# (steps/8.md: "parking requires an explicit ## Wake Note"). `check` prints `merge: parked (<why>)` where it
# printed `merge: WOULD REFUSE`; `run` performs the tail without the merge act: the Step-9 line reads
# `delivered: parked on <working branch> @ <sha>`, the continuation's header says parked, where and why, the epic
# row is written `parked`, the patrol is disarmed, and the handoff's closed form says `resume point: PARKED on
# <branch> @ <sha> — <why>`. Nothing of the work is deleted: the trees and branches stay. A Wake Note whose body is
# empty or `(none)` (the old plans' template section) parks nothing.
# fails-when: `check` prints `merge: WOULD REFUSE` on a parked plan; a parked run deletes a branch.
PK_WHY="The release waits on a hand test on the user's machine."
# park_fixture <name> <wake|none|unparked> -> a fixture at Step 8 whose working branch carries one commit main
# never took (the facts re-planted at that head), with a ## Wake Note, an empty Wake Note, or neither
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
    none) printf '\n## Wake Note\n\n(none)\n' >> "$p/$PLAN_REL" ;;
    fenced) printf '\n```\n## Wake Note\n\nwaits\n```\n' >> "$p/$PLAN_REL" ;;
    title) printf '\n## Wake Note — %s\n' "$PK_WHY" >> "$p/$PLAN_REL" ;;
  esac
  seal_fixture "$p/$PLAN_REL" "$p/$LOG_REL"
  printf '%s\n' "$p"
}
# pk_handoff <project> -> the handoff document the run's log names
pk_handoff() { local r; r="$(co_handoff_rel "$1")"; [ -n "$r" ] && cat "$1/$r" 2>/dev/null; }

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
expect_contains "PK-3 …step 9 carries delivered: parked on <branch> @ <sha>" \
  "delivered=parked on wave/01-fixture @ $PK_WS" "$(co_step_answer "$PPK")"
expect_eq "PK-4 …the continuation is written and its header says parked, where and why" "1|yes|yes" \
  "$([ -f "$PPK/$CONT_REL" ] && echo 1 || echo 0)|$(contains "$(sed -n 3p "$PPK/$CONT_REL" 2>/dev/null)" "Parked ")|$(contains "$(sed -n 3,4p "$PPK/$CONT_REL" 2>/dev/null)" "\`wave/01-fixture\` @ $PK_WS")"
expect_absent "PK-4c …and never says the branch was merged" "merged into" "$(sed -n 1,6p "$PPK/$CONT_REL" 2>/dev/null)"
expect_contains "PK-5 …the epic row is printed parked" "parked" "$(printf '%s\n' "$CO_OUT" | /usr/bin/grep '^shipped-row: | 01 |')"
expect_contains "PK-7 …the handoff document's resume point is PARKED on <branch> @ <sha>" "resume point: PARKED on wave/01-fixture @ $PK_WS" "$(pk_handoff "$PPK")"
expect_eq "PK-8 the work is kept: wt/01-x and the working branch stand, main never moved" "yes|yes|$PK_MAIN0" \
  "$(branch_exists "$PPK" wt/01-x)|$(branch_exists "$PPK" wave/01-fixture)|$(fixture_git "$PPK" rev-parse main)"
expect_contains "PK-8b …and the card says nothing was removed" "worktree-removed: none — parked" "$CO_OUT"
run_close "$PPK" run
expect_eq "PK-9 a second run says already closed" "0|already closed" "$CO_RC|$CO_OUT"

# an unreached wt/* branch does not refuse a parked plan (nothing is deleted)
PPL="$(park_fixture parked2 wake)"
add_unreached_branch "$PPL"
run_close "$PPL" check
run_close "$PPL" run
expect_eq "PK-10b …run closes rc 0, keeping both wt/01-x and the unreached wt/01-y" "0|yes|yes" \
  "$CO_RC|$(branch_exists "$PPL" wt/01-x)|$(branch_exists "$PPL" wt/01-y)"

PPT="$(park_fixture parked-title title)"
run_close "$PPT" check
expect_contains "PK-10c a titled Wake Note with no body parks, the title its reason" "merge: parked ($PK_WHY)" "$CO_OUT"
# controls: the merge act's refusal stands on an unparked plan, an empty-template Wake Note, and one in a fence only
for _pk in unparked none fenced; do
  PPU="$(park_fixture "parked-$_pk" "$_pk")"
  PPU_CK="$(cksum < "$PPU/$PLAN_REL")"
  run_close "$PPU" check
  expect_contains "PK-11.$_pk control: an $_pk plan whose branch main never took still reads merge: WOULD REFUSE" \
    "merge: WOULD REFUSE — wave/01-fixture @ " "$CO_OUT"
  run_close "$PPU" run
  expect_eq "PK-11b.$_pk …and run refuses it, naming the merge, the plan unchanged" "2|yes|$PPU_CK" \
    "$CO_RC|$(contains "$CO_OUT" "is not reachable from main")|$(cksum < "$PPU/$PLAN_REL")"
done

# ============================================================
section "§ONE-WRITER — wave-38 T37 (critic-adversarial #2, critic-structure #1; D23): close-out and the handoff verb write one document on a parked or pull-request plan, with one pair of closed lines"
# ============================================================
# The closed document has one writer of its two state lines, `resume point:` and `working branch:`, and both doors
# write them into the one handoff document: close-out.sh's tail, and session-poker.sh `handoff` on the closed plan.
# close-out's document has the verb's sections in the verb's order and keeps what a session composed before the
# close. resume on close-out's parked document reads it parked. FIXTURE FIDELITY: §PARKED's closed parked plan
# (PPK), and §ANY-BRANCH's task-scale plan (mk_task_pr_fixture), its branch merged into main as the pull request's
# merge leaves it, since close-out closes only a run whose merge it reads; closed with
# `archive-on-close: false` so the plan stays where the verb can bind it (an archived plan leaves the project root);
# each as close-out left it, the session bound by the verb.
# fails-when: close-out writes another shape or drops a composed section; the two doors' closed lines differ.
. "$REPO_ROOT/payload/scripts/lib/handoff.sh"
ow_file() {  # <project> -> the absolute file the run's log names as its handoff
  local r
  r="$(co_handoff_rel "$1")"
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
  # The verb prints only the resume line, so the file it wrote is found where every reader finds it: the plan's pointer.
  OW_RC="$LP_RC"; OW_FILE="$(handoff_file_of "$2/$PLAN_REL" "$2")"
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
git -C "$OWR" merge -q --no-ff -m "the pull request's merge" fix/x >/dev/null 2>&1
printf 'archive-on-close: false\n' >> "$OWR/.bionic/config.yaml"
OW_FINDING="- the late fix waits — file.txt"
lands_bind "$OWR" "$OW_SID"
lands_poker "$OWR" "$OW_SID" handoff <<< "Findings
$OW_FINDING"
run_close "$OWR" run
expect_eq "OW-3 precondition: close-out closed the task-scale plan rc 0, merged and in place" "0|yes|yes" \
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
git -C "$OWO" merge -q --no-ff -m "the pull request's merge" fix/x >/dev/null 2>&1
printf 'archive-on-close: false\n' >> "$OWO/.bionic/config.yaml"
OWO_FILE="$(handoff_default_of "$OWO/$PLAN_REL" "$OWO")"
mkdir -p "${OWO_FILE%/*}"
printf '%s\n' "bionic-handoff/v1" "sitrep head: Bottom line" "- You owe nothing now." "written: 2026-01-01T00:00:00Z" \
  "step: 4" "open rows (1):" "  - T9 · w-T9 · .worktrees/T9 · active" \
  "mid-flight: zebra row is halfway" "order: quince goes first" "rulings: D99 mango stays" \
  "lessons: ferret waits for the gate" "risks: walnut will conflict" "/bionic:canonical-sdlc old/path.md" > "$OWO_FILE"
run_close "$OWO" run
expect_regex "OW-6 close-out writes the pair the handoff verb writes: written: on the local 12-hour clock…" '^written: [0-9]{1,2}:[0-9]{2} (AM|PM)$' "$(/usr/bin/grep -m1 '^written: ' "$OWO_FILE")"
expect_regex "OW-6b …and instant: the ISO instant, a line of its own (OW-6 read the same file)" '^instant: [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' "$(/usr/bin/grep -m1 '^instant: ' "$OWO_FILE")"
expect_eq "OW-5 close-out carries an old-shape handoff file: the human lines under their sections, the facts under State" \
  "0|Open|Next|Decisions|Findings|Open|State|State|State" \
  "$CO_RC|$(ow_sec_of "$OWO_FILE" zebra)|$(ow_sec_of "$OWO_FILE" quince)|$(ow_sec_of "$OWO_FILE" mango)|$(ow_sec_of "$OWO_FILE" ferret)|$(ow_sec_of "$OWO_FILE" walnut)|$(ow_sec_of "$OWO_FILE" 'step: 4')|$(ow_sec_of "$OWO_FILE" 'w-T9')|$(ow_sec_of "$OWO_FILE" 'Bottom line')"

# ============================================================
section "§SCORECARD — wave-38 T15 (D26): the continuation prints four lines, each against its target, and the sitrep sheet's pace, correctness and waste"
# ============================================================
# Under `## Scorecard`, fenced, exactly:
#   human stops (autonomous half): <n> · target 1           the register's rounds put after the plan's approved-by:
#   agent minutes after the final reply: <n> · target 0     roster launches of this plan after the merge approval
#   widest landing ready→landed: <row> <m> min · target < 15   landing-report --rows, the largest minutes=; 15 is LINE_LANDING_BAR (wave-39 T9)
#   human-wait minutes: <n> · no target (the user's)        those rounds, each opened= to its at=
#   asks put to you: <n> · <m> min                          the asks put after the approval, overlaps counted once
# then the sitrep sheet's pace, correctness and waste at close, `pace: …`, `correctness: …` and `waste: …`. A number the
# record cannot compute is `unverified`.
# `landing-report --scorecard <plan>` prints the same lines; close-out reads them before the tmp wipe (the roster).
# fails-when: a line is missing, carries a number the record does not hold, or prints a literal where it is unverified.
sc_section() { awk '/^## / { s = ($0 == "## Scorecard"); next } s && NF && !/^```/ { print }' "$1"; }
sc_plant() {  # <project> -> two queue landings (30 and 42 min), three approvals in two replies, two launches, one release card round
  local p="$1" plan="$1/$PLAN_REL" rec="$1/.bionic/docs/record/wave-01-fixture"
  case "$p" in "$SANDBOX"/*) : ;; *) echo "sc_plant: refusing outside the sandbox: '$p'" >&2; return 1 ;; esac
  mkdir -p "$rec"
  {
    printf 'run/v1|ev=ready|row=T1|name=w-T1|commit=%s|branch=wt/01-T1|tree=%s/.worktrees/01-T1|suites=a.test.sh|debt=-|carrier=1:x|at=2026-10-06T10:00:00Z\n' "$LAND_C" "$p"
    printf 'run/v1|ev=published|row=T1|commit=%s|kind=queue|by=-|why=-|at=2026-10-06T10:30:00Z\n' "$LAND_C"
    printf 'run/v1|ev=ready|row=T2|name=w-T2|commit=%s|branch=wt/01-T2|tree=%s/.worktrees/01-T2|suites=a.test.sh|debt=-|carrier=1:x|at=2026-10-06T11:00:00Z\n' "$LAND_C" "$p"
    printf 'run/v1|ev=published|row=T2|commit=%s|kind=queue|by=-|why=-|at=2026-10-06T11:42:00Z\n' "$LAND_C"
  } >> "$rec/run.log"
  bash -c '. "$1/run.sh" && . "$1/proof.sh" || exit 1; LOG_AT=2026-10-05T09:00:00Z proof_approval_event "$2" doc by=fixture "said=go ahead" \
    && LOG_AT=2026-10-06T12:00:00Z proof_approval_event "$2" release by=fixture said=1 && LOG_AT=2026-10-06T12:00:01Z proof_approval_event "$2" merge by=fixture said=1' \
    _ "$REPO_ROOT/payload/scripts/lib" "$plan"
  {
    roster_row_fixture status=intended name=w-early agent_id= launched_at=2026-10-06T09:00:00Z plan="$plan"
    roster_row_fixture status=intended name=w-late agent_id= launched_at=2026-10-06T12:05:01Z plan="$plan"
    roster_row_fixture status=intended name=w-other agent_id= launched_at=2026-10-06T13:00:00Z plan="/elsewhere/wave-99-other.plan.md"
  } >> "$p/.bionic/tmp/roster-fixture.state"
  # the release card's ask on the run's register, opened when the card rendered and closed by its reply, through
  # lib/owed.sh's own writers for the plan: the fixture binds no session for the verbs that open and close it
  local e
  for e in 1791287281 1791288001; do   # 2026-10-06T11:48:01Z, 2026-10-06T12:00:01Z
    BIONIC_NOW_EPOCH="$e" OWED_ROOT="$p" OWED_SID=score-sid OWED_PLAN="$plan" \
      bash -c '. "$1/run.sh" && . "$1/owed.sh" && if [ "$2" = 1791287281 ]; then owed_open approve:release "approval: release" "approve release"; else owed_close approve:release "release approval reply"; fi' \
      _ "$REPO_ROOT/payload/scripts/lib" "$e"
  done
  seal_fixture "$plan" "$rec/run.log"
}
SC_TAIL='human-wait minutes: 12 · no target (the user'"'"'s)'
PSC="$(mk_fixture scorecard1)"; advance_to "$PSC" 8
sc_plant "$PSC"
# The pace line is the time since the approval over the forecast: both reads take one now, so SC-2 compares two reads of
# one instant and a run slowed by load cannot tick the percentage between them.
SC_NOW=1791295200   # 2026-10-06T14:00:00Z, after every instant sc_plant writes
SC_VERB="$(BIONIC_NOW_EPOCH="$SC_NOW" BIONIC_GATE_DIR="$LAND_GATE" hh_report "$PSC" --scorecard)"
expect_eq "SC-0b …then the asks put to you, the sitrep sheet's pace, correctness and waste, and nothing more" "asks put to you|pace|correctness|waste|8" \
  "$(printf '%s\n' "$SC_VERB" | sed -n 5p | cut -d: -f1)|$(printf '%s\n' "$SC_VERB" | sed -n 6p | cut -d: -f1)|$(printf '%s\n' "$SC_VERB" | sed -n 7p | cut -d: -f1)|$(printf '%s\n' "$SC_VERB" | sed -n 8p | cut -d: -f1)|$(printf '%s\n' "$SC_VERB" | /usr/bin/grep -c . | tr -d ' ')"
BIONIC_NOW_EPOCH="$SC_NOW" BIONIC_GATE_DIR="$LAND_GATE" run_close "$PSC" run
expect_nonempty "SC-1b precondition: the extractor finds lines under the heading" "$(sc_section "$PSC/$CONT_REL")"
expect_eq "SC-2 D26 the section is the verb's eight lines, read before the wipe (the roster's launch counted)" \
  "$SC_VERB" "$(sc_section "$PSC/$CONT_REL")"
expect_eq "SC-4 …the heading sits before the Resume instruction" "yes" \
  "$(awk '/^## Scorecard$/ { a = NR } /^## Resume instruction/ { b = NR } END { print (a && b > a) ? "yes" : "no" }' "$PSC/$CONT_REL")"
# the wait is read off the register: the release card's one round, opened 11:48:01Z and closed 12:00:01Z
sc_wait() { printf '%s\n' "$1" | /usr/bin/grep '^human-wait minutes: '; }
expect_eq "SC-5 the release card's round on the register gives the 12-minute wait" "$SC_TAIL" "$(sc_wait "$SC_VERB")"
expect_eq "SC-5b …and the one stop, the round put after the plan's approval" "human stops (autonomous half): 1 · target 1" \
  "$(printf '%s\n' "$SC_VERB" | /usr/bin/grep '^human stops ')"
# a record that cannot compute a number prints unverified on that line, never a literal
PSU="$(mk_fixture scorecard2)"; advance_to "$PSU" 8
BIONIC_GATE_DIR="$LAND_GATE" run_close "$PSU" run
# an existing continuation gets the section added, once
PSE="$(mk_fixture scorecard3)"; advance_to "$PSE" 8
mkdir -p "$PSE/${CONT_REL%/*}"
printf '# continuation — hand written\n\n## Deferrals\n\n## Resume instruction\n\nedited by a person\n' > "$PSE/$CONT_REL"
BIONIC_GATE_DIR="$LAND_GATE" run_close "$PSE" run

# ============================================================
section "§APPROVED-HEAD — in the release order, close-out refuses a working head that is not the head the user approved"
# ============================================================
# FIXTURE FIDELITY: mk_fixture's run at 15 with a regression row and a release row, landed, its facts held at the working
# head B; each approval is the event the approve verb appends, the newest one read.
# fails-when: run closes the plan with the release approval at B's parent A and code between them.
PAH="$(mk_fixture approved-head)"; awk '{ print } /^\| T2 \|/ { print "| T3 | 5 | test | the whole regression | — | 10 | AC-1 | — | — |"; print "| T4 | 7 | doc | the release | — | 10 | AC-1 | CHANGELOG.md | — |" }' "$PAH/$PLAN_REL" > "$PAH/$PLAN_REL.r" && mv "$PAH/$PLAN_REL.r" "$PAH/$PLAN_REL"
printf 'run/v1|ev=published|row=%s|at=2026-10-04T12:30:00Z\n' T3 T4 >> "$PAH/$LOG_REL"; advance_to "$PAH" 8
AH_B="$(fixture_git "$PAH" rev-parse wave/01-fixture)"; AH_A="$(fixture_git "$PAH" rev-parse wave/01-fixture^)"
ah_appr() { printf 'run/v1|ev=approval|key=release|by=Dana Fixture|head=%s|said=Ship it.|at=2026-10-12T14:0%s:00Z\n' "$1" "$2" >> "$PAH/$LOG_REL"; seal_fixture "$PAH/$PLAN_REL" "$PAH/$LOG_REL"; }
ah_appr "$AH_A" 0; AH_CK0="$(cksum < "$PAH/$PLAN_REL")"; run_close "$PAH" run
expect_eq "AH-C1 approved at A, the working head B with code past A: run refuses (rc 2) naming both heads, the plan unchanged" \
  "2|yes|$AH_CK0" "$CO_RC|$(contains "$CO_OUT" "the working head ${AH_B:0:12} is not the head the user approved for release, ${AH_A:0:12}")|$(cksum < "$PAH/$PLAN_REL")"
ah_appr "$AH_B" 1; run_close "$PAH" run
expect_eq "AH-C0 control: the same run approved again at the working head B closes (rc 0)" "0" "$CO_RC"

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

# ============================================================
section "§NO-SCORECARD — close-out's stdout carries no scorecard line, and the Step-9 text shows none (REQ-14 AC-14.1)"
# ============================================================
# The scorecard belongs to the continuation (`## Scorecard`, §SCORECARD). The Step-9 report shows its ten parts and
# pastes no block, so close-out prints none of the verb's lines on its stdout, at `check` or at `run`.
# FIXTURE FIDELITY: §SCORECARD's planted record (sc_plant), so the verb has its seven lines to print; the step text is
# the shipped skills/canonical-sdlc/steps/9.md and its template.
# fails-when: a `scorecard: ` line prints on either verb's stdout, or the step text or its template names a scorecard.
ns_keys() { printf '%s\n' "$1" | sed -n 's/^\([a-z][a-z-]*\): .*/\1/p'; }  # <stdout> -> each line's key, in order
PNS="$(mk_fixture no-scorecard)"; advance_to "$PNS" 8
sc_plant "$PNS"
BIONIC_GATE_DIR="$LAND_GATE" run_close "$PNS" check
NS_CHECK="$(ns_keys "$CO_OUT")"
expect_contains "NS-0 precondition: the key extractor reads check's hand-holds line" "hand-holds" "$NS_CHECK"
expect_absent "NS-1 check prints no scorecard line" "scorecard" "$NS_CHECK"
BIONIC_GATE_DIR="$LAND_GATE" run_close "$PNS" run
NS_RUN="$(ns_keys "$CO_OUT")"
expect_eq "NS-2 run closes the plan (rc 0)" "0" "$CO_RC"
expect_contains "NS-3 precondition: the key extractor reads run's hand-holds line" "hand-holds" "$NS_RUN"
expect_absent "NS-4 run prints no scorecard line" "scorecard" "$NS_RUN"
expect_nonempty "NS-5 …and the continuation still holds the verb's lines under ## Scorecard" "$(sc_section "$PNS/$CONT_REL")"
NS_STEP9="$REPO_ROOT/skills/canonical-sdlc/steps/9.md"
NS_TMPL9="$REPO_ROOT/agents-src/templates/skills/canonical-sdlc/steps/9.md.tmpl"
expect_contains "NS-6 precondition: the Step-9 text names the report's ten parts" "covering ten parts" "$(cat "$NS_STEP9")"
expect_eq "NS-7 the Step-9 text names no scorecard (grep -c)" "0" "$(/usr/bin/grep -c scorecard "$NS_STEP9")"
expect_contains "NS-8 precondition: its template names the ten parts" "covering ten parts" "$(cat "$NS_TMPL9")"
expect_eq "NS-9 …nor does its template" "0" "$(/usr/bin/grep -c scorecard "$NS_TMPL9")"

# ============================================================
section "§REVIEWS-RENDERED — close-out renders the release entry's reviews from the plan and commits them on the working branch (REQ-14 AC-14.3)"
# ============================================================
# The entry's `### The reviews` part is the machine's: every review proof and every waiver of a question the run's log
# holds, in the order they were registered, one bullet each, under one fixed first line. `run` writes it into the
# working branch's CHANGELOG.md, replacing a hand-written part or adding one before `### Known limits`, commits it as
# close-out's own commit on that branch, and appends a `published` event of the part naming the commit to the run's
# log, so the branch holds no commit the log does not name. `check` says what `run` would do and writes
# nothing. A plan naming no `release:` gets no part and no commit. A part the integrate row rendered before the pull
# request is already listed, so close-out writes none (the rows after RV-16).
# FIXTURE FIDELITY: mk_fixture's plan and branches; the release entry is committed on the working branch and merged
# into main, as a release row's landing and the merge bring it; the failed review and the waiver are events written by
# the proof library's writers (`proof_event` and `proof_waiver_event`, which `proof-add` and `waive` call) with the
# fields and the instant those verbs give them, and the floor and the dealt reviews are planted again at the new head
# by plant_facts, as a run registers them after its release row.
# fails-when: the part differs from the log's reviews and waivers, the hand-written line survives, the rest of the file moves, the
# commit is not close-out's or touches another path, the checkout is left behind its branch, the record names no such
# commit, check writes, a plan with no release gets a commit, or a run with no pull request finds another writer.
rv_fixture() {  # <name> <yes|no: the entry carries a hand-written ### The reviews> -> the project at Step 8, echoed
  local p wt
  p="$(mk_fixture "$1")" && advance_to "$p" 8 || return 1
  wt="$p-wave"
  awk '{ print } /^adrs: none$/ && !d { print "release: 9.9.9"; d = 1 }' "$p/$PLAN_REL" > "$p/$PLAN_REL.r" \
    && mv "$p/$PLAN_REL.r" "$p/$PLAN_REL"
  seal_fixture "$p/$PLAN_REL" "$p/$LOG_REL"
  {
    printf '# Changelog\n\n## 9.9.9 — 2026-10-22\n\nThe prose a person wrote.\n\n'
    [ "$2" = no ] || printf '### The reviews\n\n- a hand-written line the render replaces\n\n'
    printf '### Known limits\n\n- one limit\n\n## 9.9.8 — 2026-10-01\n\n### The reviews\n\n- an older line, left as written\n'
  } > "$wt/CHANGELOG.md"
  fixture_git "$wt" add CHANGELOG.md && fixture_git "$wt" commit -q -m "the release entry" >/dev/null 2>&1 \
    && fixture_git "$p" merge -q --no-ff -m "merge the release" wave/01-fixture >/dev/null 2>&1 || return 1
  printf '%s\n' "$p"
}
rv_part() {  # <file> <version> -> the entry's ### The reviews part, its heading to the line before the next heading
  awk -v v="## $2 " '/^## / { inb = (index($0, v) == 1); inp = 0 }
    /^### / { inp = (inb && $0 == "### The reviews") }
    inp { print }' "$1"
}
rv_rest() {  # <file> <version> -> the file without that part
  awk -v v="## $2 " '/^## / { inb = (index($0, v) == 1); inp = 0 }
    /^### / { inp = (inb && $0 == "### The reviews") }
    !inp { print }' "$1"
}
rv_dealt() {  # <project> -> `<question> <scope>` per review the plan's rigor and scale deal, in the dealing's order
  bash -c '. "$1/run.sh" && . "$1/proof.sh" || exit 1
    facts_owed "$(plan_frontmatter_get "$2" rigor)" "$(plan_frontmatter_get "$2" scale)" \
      | awk -F"\t" "\$1 == \"review\" { print \$2, \$4 }"' _ "$REPO_ROOT/payload/scripts/lib" "$1/$PLAN_REL"
}
rv_bullet() {  # <question> <scope> <result> <head> <by> <at> <evidence> -> the bullet a proof line renders as
  printf -- '- %s review, %s: %s at %.8s by %s, %s (`%s`)\n' "$1" "$2" "$3" "$4" "$5" "$6" "${7##*/}"
}
rv_tip() { fixture_git "$1" rev-parse --verify -q "refs/heads/wave/01-fixture"; }
rv_event() {  # <project> <proof_event|proof_waiver_event> <at> <field>=<value>… -> one event in the run's log at <at>, by the proof library's writer
  local p="$1/$PLAN_REL" w="$2" at="$3"; shift 3
  bash -c '. "$1/run.sh" && . "$1/proof.sh" || exit 1; w="$2" p="$3" at="$4"; shift 4; LOG_AT="$at" "$w" "$p" "$@"' \
    _ "$REPO_ROOT/payload/scripts/lib" "$w" "$p" "$at" "$@"
}
rv_reviews() { /usr/bin/grep -c '^run/v1|ev=proof|kind=review|' "$1/$LOG_REL"; }   # <project> -> the review proofs its run's log holds
PRV="$(rv_fixture reviews-rendered yes)"
expect_nonempty "RV-0 precondition: the fixture is built" "$PRV"
RV_H1="$(fixture_git "$PRV" rev-parse --verify -q 'wave/01-fixture^')"
RV_H2="$(rv_tip "$PRV")"
RV_DEALT="$(rv_dealt "$PRV")"
RV_Q1="$(printf '%s\n' "$RV_DEALT" | awk 'NR == 1 { print $1 }')"; RV_S1="$(printf '%s\n' "$RV_DEALT" | awk 'NR == 1 { print $2 }')"
expect_nonempty "RV-0b precondition: the plan's rigor and scale deal a review" "$RV_Q1"
rv_event "$PRV" proof_event 2026-10-04T13:00:00Z kind=review "head=$RV_H1" evidence=record/wave-01-fixture/critic-fail.md \
  "question=$RV_Q1" reader=w-crit result=fail "scope=$RV_S1"
plant_facts "$PRV"
rv_event "$PRV" proof_waiver_event 2026-10-05T09:30:00Z "question=$RV_Q1" "head=$RV_H2" "by=Pat Doe" "said=waive — the fix landed at $RV_H2"
expect_contains "RV-1 precondition: the part extractor reads the hand-written line" "a hand-written line the render replaces" \
  "$(rv_part "$PRV-wave/CHANGELOG.md" 9.9.9)"
RV_REST0="$(rv_rest "$PRV-wave/CHANGELOG.md" 9.9.9)"
BIONIC_GATE_DIR="$LAND_GATE" run_close "$PRV" check
RV_CHECK="$(printf '%s\n' "$CO_OUT" | /usr/bin/grep '^reviews: ')"
expect_contains "RV-2 check says run would render the part on the working branch" "run would render" "$RV_CHECK"
expect_eq "RV-3 …and writes nothing: the branch is where it was" "$RV_H2" "$(rv_tip "$PRV")"
BIONIC_GATE_DIR="$LAND_GATE" run_close "$PRV" run
# The part is published before the merge readback, so the readback reads the branch the part is on. The fixture's release
# merge predates the part, so main does not hold the published tip and the run holds there (rc 2) until the person merges it.
expect_eq "RV-4 run publishes the part, then holds at the merge readback: the branch it moved to is not merged (rc 2)" "2|yes" \
  "$CO_RC|$(printf '%s\n' "$CO_OUT" | /usr/bin/grep -q 'is not reachable from' && echo yes)"
RV_TIP="$(rv_tip "$PRV")"
RV_WANT="$(
  printf '### The reviews\n\nRendered from the plan'"'"'s review and waiver lines, in the order they were registered.\n\n'
  while read -r q s; do rv_bullet "$q" "$s" pass "$RV_H1" w-read 2026-10-04T12:00:00Z "record/wave-01-fixture/$q-$s.md"; done <<RV
$RV_DEALT
RV
  rv_bullet "$RV_Q1" "$RV_S1" fail "$RV_H1" w-crit 2026-10-04T13:00:00Z record/wave-01-fixture/critic-fail.md
  while read -r q s; do rv_bullet "$q" "$s" pass "$RV_H2" w-read 2026-10-04T12:00:00Z "record/wave-01-fixture/$q-$s.md"; done <<RV
$RV_DEALT
RV
  printf -- '- %s review: waived at %.8s by Pat Doe, 2026-10-05T09:30:00Z: "waive — the fix landed at %s"\n\n' "$RV_Q1" "$RV_H2" "$RV_H2"
)"
RV_GOT="$(fixture_git "$PRV" show "$RV_TIP:CHANGELOG.md" 2>/dev/null)"
expect_eq "RV-5 the part published before the readback held is the log's reviews and waiver, byte for byte" "$RV_WANT" \
  "$(printf '%s\n' "$RV_GOT" | rv_part /dev/stdin 9.9.9)"
expect_absent "RV-6 …and the hand-written line is gone from it" "a hand-written line the render replaces" \
  "$(printf '%s\n' "$RV_GOT" | rv_part /dev/stdin 9.9.9)"
expect_eq "RV-7 the rest of the file is as it was: the prose, the limits, the older entry" "$RV_REST0" \
  "$(printf '%s\n' "$RV_GOT" | rv_rest /dev/stdin 9.9.9)"
expect_eq "RV-8 the commit is the checkout's own author's, on the release head" "fixture <fixture@example.invalid>|$RV_H2" \
  "$(fixture_git "$PRV" log -1 --format='%an <%ae>|%P' "$RV_TIP")"
expect_eq "RV-9 …and touches CHANGELOG.md alone" "CHANGELOG.md" "$(fixture_git "$PRV" diff --name-only "$RV_H2" "$RV_TIP")"
expect_eq "RV-10 the checkout holding the branch is at the commit, its file the committed one" "$RV_TIP|$RV_GOT" \
  "$(fixture_git "$PRV-wave" rev-parse HEAD)|$(cat "$PRV-wave/CHANGELOG.md")"
RV_EV="$(/usr/bin/grep '^run/v1|ev=published|part=reviews|' "$PRV/.bionic/docs/record/wave-01-fixture/run.log" 2>/dev/null)"
expect_contains "RV-11 the run's log names the commit as close-out's part, with no row" \
  "run/v1|ev=published|part=reviews|commit=$RV_TIP|branch=wave/01-fixture|by=close-out|at=" "$RV_EV"
expect_contains "RV-12 run's reviews line names the commit" "$(printf '%.12s' "$RV_TIP")" \
  "$(printf '%s\n' "$CO_OUT" | /usr/bin/grep '^reviews: ')"
expect_eq "RV-17 control: the plan has no integrate row, so no pull request came first and close-out is the part's one writer" \
  "0|1|by=close-out" \
  "$(/usr/bin/grep -c '^| T[0-9]* | [0-9]* | integrate |' "$PRV/$PLAN_REL")|$(/usr/bin/grep -c '|part=reviews|' "$PRV/.bionic/docs/record/wave-01-fixture/run.log" 2>/dev/null)|$(/usr/bin/grep '|part=reviews|' "$PRV/.bionic/docs/record/wave-01-fixture/run.log" 2>/dev/null | sed 's/.*|\(by=[^|]*\)|.*/\1/')"
# an entry with no part gets one, before ### Known limits
PRA="$(rv_fixture reviews-added no)"
plant_facts "$PRA"
BIONIC_GATE_DIR="$LAND_GATE" run_close "$PRA" run
RA_GOT="$(fixture_git "$PRA" show "$(rv_tip "$PRA"):CHANGELOG.md" 2>/dev/null)"
expect_eq "RV-13 an entry with no part gets one, its heading just before ### Known limits" "### The reviews|### Known limits" \
  "$(printf '%s\n' "$RA_GOT" | awk -v v='## 9.9.9 ' '/^## / { inb = (index($0, v) == 1) } inb && /^### / { printf "%s%s", s, $0; s = "|" } END { print "" }')"
expect_eq "RV-14 …one bullet per review proof of the run's log" \
  "$(rv_reviews "$PRA")" \
  "$(printf '%s\n' "$RA_GOT" | rv_part /dev/stdin 9.9.9 | /usr/bin/grep -c '^- ')"
# a plan naming no release: gets no part and no commit
PRN="$(mk_fixture reviews-norelease)"; advance_to "$PRN" 8
RN_H="$(rv_tip "$PRN")"
BIONIC_GATE_DIR="$LAND_GATE" run_close "$PRN" run
RN_LINE="$(printf '%s\n' "$CO_OUT" | /usr/bin/grep '^reviews: ')"
expect_contains "RV-15 a plan naming no release: says so" "names no release:" "$RN_LINE"
expect_eq "RV-16 …and its branch is where it was" "$RN_H" "$(rv_tip "$PRN")"
# THE PART RENDERED BEFORE THE PULL REQUEST. The integrate row runs `reviews-part <row>` before the push and
# `gh pr create`: the same render, committed on the working branch under the line's author and named by an
# `ev=integrate` line, so the person's merge carries the part to main and close-out finds it already listed. The judge
# holds that commit covered by the release check at its parent, and by an approval there, only while it is byte-equal to
# a fresh render of the plan: a part edited by hand is a release-set change past the approval like any other.
# FIXTURE FIDELITY: rv_fixture's entry; the plan gains the integrate and close rows (lands_rows) and the session is bound
# (lands_bind), as a run at Step 8 is; the project declares a release check and its check proof names the release head,
# as `release-check` writes it; the integrate row's record is a file under record/ its Files name; the person's merge is
# a plain merge into main. The hand-edited part is a commit on a side branch, made by git's plumbing.
# fails-when: the tick lands the integrate row while the part is missing, the verb's part differs from close-out's or
# touches another path, the record does not name the commit, main's entry lacks the part after the merge, close-out
# commits or records a second part, or the judge holds a hand-edited part covered.
bp_judge() {  # <project> <head> -> `<proof_prose_past rc from the release head>|<facts_state's check state at head>`
  bash -c '. "$1/roots.sh" 2>/dev/null; . "$1/run.sh" && . "$1/proof.sh" || exit 9
    proof_prose_past "$2" "$3" "$4"; p=$?
    s="$(facts_state "$2" "$4" 2>/dev/null | awk -F"\t" "\$1 == \"check\" { print \$2 }")"
    printf "%s|%s\n" "$p" "$s"' _ "$REPO_ROOT/payload/scripts/lib" "$1/$PLAN_REL" "$BP_H" "$2"
}
bp_side() {  # <project> <parent> <changelog file> -> a commit of that CHANGELOG.md on <parent>, named refs/heads/side
  local p="$1" b t c i="$SANDBOX/bp-side.index"
  b="$(fixture_git "$p" hash-object -w --path CHANGELOG.md "$3")" \
    && GIT_INDEX_FILE="$i" fixture_git "$p" read-tree "$2" \
    && GIT_INDEX_FILE="$i" fixture_git "$p" update-index --cacheinfo "100644,$b,CHANGELOG.md" \
    && t="$(GIT_INDEX_FILE="$i" fixture_git "$p" write-tree)" \
    && c="$(fixture_git "$p" commit-tree "$t" -p "$2" -m "a part edited by hand")" \
    && fixture_git "$p" update-ref refs/heads/side "$c" && rm -f "$i" && printf '%s\n' "$c"
}
BP_SID="closeout-reviews-pr-sid"
PBP="$(rv_fixture reviews-before-pr no)"
plant_facts "$PBP"; lands_rows "$PBP"
lands_bind "$PBP" "$BP_SID"
BP_H="$(rv_tip "$PBP")"
BP_REC="$PBP/.bionic/docs/record/wave-01-fixture"
printf 'release-check: bash tests/lib/release-check.sh\n' >> "$PBP/.bionic/config.yaml"
rv_event "$PBP" proof_event 2026-10-05T10:00:00Z kind=check "head=$BP_H" evidence=record/wave-01-fixture/release-check.log
printf '# T3: the pull request\n\n    gh pr create --base main --head wave/01-fixture --fill\n' > "$BP_REC/T3-pr.md"
sed -i '' -E '/^\| T3 \|/s#\| none \|#| .bionic/docs/record/wave-01-fixture/T3-pr.md |#' "$PBP/$PLAN_REL"
seal_fixture "$PBP/$PLAN_REL" "$PBP/$LOG_REL"
BP_ROW="$(/usr/bin/grep '^| T3 |' "$PBP/$PLAN_REL")"
expect_eq "BP-0 precondition: the session is bound, the integrate row names its record, and the judge reads the check at the release head" \
  "0|pending|0|covered" "$LP_RC|$(lands_state "$PBP" T3)|$(bp_judge "$PBP" "$BP_H")"
lands_poker "$PBP" "$BP_SID" tick
expect_eq "BP-1 the tick leaves the integrate row unlanded while the entry's reviews part is missing" "pending|0" \
  "$(lands_state "$PBP" T3)|$(lands_pub "$PBP" T3 | grep -c .)"
expect_contains "BP-1b …saying why once, naming the verb that renders it" "NOT-LANDED T3 — " "$LP_OUT"
expect_contains "BP-1c …the verb" "reviews-part T3" "$(printf '%s\n' "$LP_OUT" | /usr/bin/grep '^poker: NOT-LANDED T3')"
lands_poker "$PBP" "$BP_SID" reviews-part T3
BP_TIP="$(rv_tip "$PBP")"
expect_eq "BP-2 reviews-part renders the part: exit 0, a commit by the checkout's own author on the release head" "0|fixture <fixture@example.invalid>|$BP_H" \
  "$LP_RC|$(fixture_git "$PBP" log -1 --format='%an <%ae>|%P' "$BP_TIP")"
expect_eq "BP-3 …touching CHANGELOG.md alone" "CHANGELOG.md" "$(fixture_git "$PBP" diff --name-only "$BP_H" "$BP_TIP")"
BP_PART="$(fixture_git "$PBP" show "$BP_TIP:CHANGELOG.md" 2>/dev/null | rv_part /dev/stdin 9.9.9)"
expect_eq "BP-4 …one bullet per review proof of the run's log, under the part's heading" \
  "### The reviews|$(rv_reviews "$PBP")" \
  "$(printf '%s\n' "$BP_PART" | sed -n 1p)|$(printf '%s\n' "$BP_PART" | /usr/bin/grep -c '^- ')"
expect_contains "BP-5 the run's log names the commit as the integrate row's part, with no row" \
  "run/v1|ev=published|part=reviews|commit=$BP_TIP|branch=wave/01-fixture|tree=$(cd "$PBP-wave" && pwd -P)|by=T3|at=" \
  "$(/usr/bin/grep '^run/v1|ev=published|part=reviews|' "$BP_REC/run.log" 2>/dev/null)"
expect_eq "BP-6 the checkout holding the branch is at the commit" "$BP_TIP" "$(fixture_git "$PBP-wave" rev-parse HEAD)"
lands_poker "$PBP" "$BP_SID" reviews-part T3
expect_eq "BP-7 a second reviews-part finds the part listed: exit 0, no commit" "0|$BP_TIP" "$LP_RC|$(rv_tip "$PBP")"
expect_eq "BP-8 the judge holds the part commit covered: by an approval at the release head, and by the check there" \
  "0|covered" "$(bp_judge "$PBP" "$BP_TIP")"
fixture_git "$PBP" show "$BP_TIP:CHANGELOG.md" | awk '{ print } $0 == "### The reviews" { getline; print; print "- a bullet typed by hand" }' \
  > "$SANDBOX/bp-hand.md"
BP_SIDE="$(bp_side "$PBP" "$BP_H" "$SANDBOX/bp-hand.md")"
expect_eq "BP-9 a hand-edited part on the release head is no fresh render: the approval and the check do not reach it" \
  "1|uncovered" "$(bp_judge "$PBP" "$BP_SIDE" | sed 's/\(uncovered\).*/\1/')"
lands_poker "$PBP" "$BP_SID" tick
expect_eq "BP-10 with the part rendered, the next tick lands the integrate row: one published event of the record kind, its row unwritten" \
  "landed|1|$BP_ROW" "$(lands_state "$PBP" T3)|$(lands_pub "$PBP" T3 | grep -c ' record ')|$(/usr/bin/grep '^| T3 |' "$PBP/$PLAN_REL")"
fixture_git "$PBP" merge -q --no-ff -m "the pull request, merged" wave/01-fixture >/dev/null 2>&1
BP_MAIN="$(fixture_git "$PBP" show "main:CHANGELOG.md" 2>/dev/null | rv_part /dev/stdin 9.9.9)"
expect_eq "BP-11 after the person's merge, main's entry holds the part" "### The reviews" "$(printf '%s\n' "$BP_MAIN" | sed -n 1p)"
expect_eq "BP-11b …byte for byte the part the branch holds" "$BP_PART" "$BP_MAIN"
run_close_as "$BP_SID" "$PBP" run
expect_eq "BP-12 close-out closes the run (rc 0) and says the part is already listed" "0|yes" \
  "$CO_RC|$(printf '%s\n' "$CO_OUT" | /usr/bin/grep '^reviews: ' | /usr/bin/grep -q 'already lists' && echo yes)"
BP_PARTS="$(/usr/bin/grep '|part=reviews|' "$BP_REC/run.log" 2>/dev/null)"
expect_eq "BP-13 the log names one writer of the part, the integrate row (read beside close-out's absence)" "1|by=T3" \
  "$(printf '%s\n' "$BP_PARTS" | /usr/bin/grep -c .)|$(printf '%s\n' "$BP_PARTS" | sed 's/.*|\(by=[^|]*\)|.*/\1/')"
expect_eq "BP-14 …and close-out made no commit: the branch is at the integrate row's" "$BP_TIP" "$(rv_tip "$PBP")"

# ============================================================
section "§TWO-LINES — check gives one answer for the plan as it stands and the plan run would write"
# ============================================================
# On a plan whose flag review has a finding a landed row fixed, `check` prints two gate lines: the plan as it stands, and
# the plan with the close's facts pending. Both read the run's record, so both read ok.
# FIXTURE FIDELITY: the Step-8 fixture, its facts events in the run's log, each at its own instant: a structure review
# `result=flag` over a record holding two findings, one to fix and one a note; the first moved `to=fixed row=T1` (the
# event finding-move writes); T1's landing verdict green in the run's log; and step 8 carrying what the close
# cleans, so the plan as it stands and the plan close-out would write are judged on the same facts. Without the verdict
# the moved finding is still to fix, the flag derives fail, and both lines refuse.
# fails-when: payload/scripts/close-out.sh check prints the preflight's ok under another wording, so the second line is not
# the one the first is paired with (TL-2).
tl_world() {  # <name> -> the project built as above, echoed
  local p rec h
  p="$(mk_fixture "$1")"; advance_to "$p" 8
  rec="$p/.bionic/docs/record/wave-01-fixture"
  printf 'reviewed: aaaaaaa..bbbbbbb\nfindings: 2\nfinding: 1 S2 on file.txt:1 the fixture finding\nfinding: 2 S4 off - a note\nshown: 1 grep -n work file.txt\n' \
    > "$rec/structure-flag.md"
  h="$(fixture_git "$p" rev-parse wave/01-fixture)"
  bash -c '. "$1/proof.sh" || exit 1
    LOG_AT=2026-10-04T13:00:00Z proof_event "$2" kind=review "head=$3" evidence=record/wave-01-fixture/structure-flag.md \
      question=structure reader=w-read result=flag scope=piece || exit 1
    LOG_AT=2026-10-22T10:00:00Z proof_step_event "$2" 8 cleanup=done "tmp-wiped=0 entries" "tasks-completed=T1, T2"' \
    _ "$REPO_ROOT/payload/scripts/lib" "$p/$PLAN_REL" "$h"
  printf 'run/v1|ev=finding|ref=record/wave-01-fixture/structure-flag.md#1|to=fixed|row=T1|by=Fixture|at=2026-10-06T14:00:00Z\n' >> "$p/$LOG_REL"
  printf 'run/v1|ev=verdict|row=T1|commit=%s|suite=a.test.sh|result=green|log=a.log|admitted=-|width=1|at=2026-10-06T10:20:00Z\n' "$h" \
    >> "$p/$LOG_REL"
  seal_fixture "$p/$PLAN_REL" "$p/$LOG_REL"
  printf '%s\n' "$p"
}
run_close "$(tl_world two-lines)" check
expect_eq "TL-1 the plan as it stands: ok" "gate: ok against the plan as it stands" \
  "$(printf '%s\n' "$CO_OUT" | /usr/bin/grep -m1 '^gate: .*as it stands')"
expect_eq "TL-2 the plan run would write: ok, the same answer" "gate: ok against the plan run would write" \
  "$(printf '%s\n' "$CO_OUT" | /usr/bin/grep -m1 '^gate: .*run would write')"

# ============================================================
section "§READ-ORDER — close-out reads the hand-holds line last, over the window to its own delivered: time"
# ============================================================
# close-out writes `delivered:` and wipes its rosters before its last read of the hand-holds line, so what it does is
# inside the window and a release approval card ends nothing. The fixture: T1 landed (the start), a release approval
# page, then an amend and a decline in the run's log, both after the page. fails-when: the line is
# read before delivered: (the card ends it, and both acts are outside), or the wipe of the rosters loses the amend.
RO_P="$(mk_fixture read-order)"; advance_to "$RO_P" 8
RO_PLAN="$RO_P/$PLAN_REL"; RO_REC="$RO_P/.bionic/docs/record/wave-01-fixture"; mkdir -p "$RO_REC"
ro_ago() { date -u -v-"$1"M +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "-$1 minutes" +%Y-%m-%dT%H:%M:%SZ; }   # <minutes> -> that long ago
RO_C="$(printf 'e%.0s' $(seq 40))"
printf 'run/v1|ev=published|row=T1|commit=%s|kind=queue|by=-|why=-|at=%s\n' "$RO_C" "$(ro_ago 20)" >> "$RO_REC/run.log"
printf '# page\n\n## Replay\n\nrelease-approval/v1|plan=%s|head=%s|at=%s|decisions=1\n' "$RO_PLAN" "$RO_C" "$(ro_ago 10)" > "$RO_REC/release-approval-eeeeeeee.md"
printf 'run/v1|ev=stop|session=fixture|turn=|current=8|state=decline|ceiling=6|width=|open=|free=|ready=T3|launched=|declined=no room|missed=0|idle=|room=|at=%s\n' "$(ro_ago 5)" >> "$RO_REC/run.log"
printf 'run/v1|ev=hand|by=fixture|name=w-ro|what=amend|why=widen the files|at=%s\n' "$(ro_ago 5)" >> "$RO_REC/run.log"
seal_fixture "$RO_PLAN" "$RO_REC/run.log"
expect_contains "RO-0 precondition: before close-out a window opening before both acts reads them" \
  "declines=1 · lifts=0 · amends=1 " "$(hh_report "$RO_P" --hand-holds --since "$(ro_ago 15)" | grep '^hand-holds: ')"
run_close "$RO_P" run
RO_LINE="$(printf '%s\n' "$CO_OUT" | grep '^hand-holds: ')"
expect_eq "RO-1 run exits 0 and its wipe took the roster" "0/0" "$CO_RC/$(tmp_entries "$RO_P")"
[ "$CO_RC" = 0 ] || printf '%s\n' "$CO_OUT" | tail -15 | sed 's/^/    | /'
expect_contains "RO-2 the card's line counts the decline and the amend after the card: read last, after the wipe" \
  "hand-holds: total=2 · by-hand=0 · stop-runs=0 · declines=1 · lifts=0 · amends=1 " "$RO_LINE"
expect_eq "RO-3 …and the card prints it after its step8 line: it is read once Steps 8 and 9 are written" "yes" \
  "$(printf '%s\n' "$CO_OUT" | awk '/^step8: / { a = NR } /^hand-holds: / { b = NR } END { print (a && b > a) ? "yes" : "no" }')"
expect_eq "RO-4 …and the continuation carries that same final line" "$RO_LINE" \
  "$(awk '/^## / { s = ($0 == "## Hand-holds"); next } s && /^hand-holds: / { print; exit }' "$RO_P/$CONT_REL")"
# the plan where the close left it (the archive may have moved it)
RO_AFTER="$(find "$RO_P/.bionic/docs" -name "${PLAN_REL##*/}" -type f 2>/dev/null | head -1)"
RO_DEL="$(awk -F'|' '/\|ev=step\|n=9\|/ { for (i = 3; i <= NF; i++) if ($i ~ /^at=/) t = substr($i, 4) } END { print t }' "$RO_REC/run.log" 2>/dev/null)"
RO_ENDS="$( ( in_fixture "$RO_P" || exit 9
  HOME="$SB_HOME" CLAUDE_PROJECT_DIR="" BIONIC_PLUGIN_ROOT="$REPO_ROOT/payload" BIONIC_CLAUDE_HOME="$SB_HOME/.claude" \
    BIONIC_GATE_DIR="$HH_GATE" bash "$BIONIC_HOOKS_DIR/session-poker.sh" landing-report --hand-holds "$RO_AFTER" 2>/dev/null ) | grep '^hand-holds window: ')"
expect_regex "RO-5 the delivery's instant is its event's own second" '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' "$RO_DEL"
expect_contains "RO-5b …and the report read after the close names it as the window's end" "until ${RO_DEL/%:00Z/Z} (delivered:)" "$RO_ENDS"

# ============================================================
section "§MARKS — close-out fills every mark it can derive; the continuation keeps only the five a person owns (REQ-10 AC-10.2)"
# ============================================================
# The landings, the hand-holds line, the reviews and the governed-by lines are close-out's own readings, rendered in
# full; what is left marked is what only the next session decides: the first decision, what was ruled at the close,
# the version, the ideas path and the carry-overs. FIXTURE FIDELITY: a fresh continuation written by `run`.
# fails-when: a mark close-out could fill reads `<fill:` after it exits, or one of the five is filled for the person.
mk_marks() { /usr/bin/grep -o '<fill: [^>]*>' "$1" 2>/dev/null | awk '!s[$0]++'; }
MK_FIVE='<fill: the first decision, or "none">
<fill: what was ruled at this close, or "none">
<fill: version>
<fill: ideas path>
<fill: carry-overs from this wave>'
PMK="$(mk_fixture marks)"; advance_to "$PMK" 8
run_close "$PMK" run
MK_CONT="$PMK/$CONT_REL"
expect_eq "MK-1 run exits 0 and the continuation's marks are exactly the five person-owned ones" "0|$MK_FIVE" "$CO_RC|$(mk_marks "$MK_CONT")"
expect_contains "MK-2 …the card names the same five as owed" "continuation-owed: 5 marks only a person can fill" "$CO_OUT"
mk_sec() { awk -v h="$2" '/^## / { s = ($0 == h); next } s && NF && !/^```/ { print }' "$1"; }
expect_eq "MK-3 the four close-out fills are rendered: a landings line, a hand-holds line, the reviews sentence, a governed-by line" \
  "yes|yes|yes|yes" \
  "$(mk_sec "$MK_CONT" "## Landings" | /usr/bin/grep -q '^landings' && echo yes || echo no)|$(mk_sec "$MK_CONT" "## Hand-holds" | /usr/bin/grep -q '^hand-holds: ' && echo yes || echo no)|$(/usr/bin/grep -q '^Reviews: .*ADRs: ' "$MK_CONT" && echo yes || echo no)|$(mk_sec "$MK_CONT" "## Governed by" | /usr/bin/grep -q '^governed-by: ' && echo yes || echo no)"

# ============================================================
section "§OWED-AT-CLOSE — close-out settles the matrix row its own last reading proves, and the gate before the flip does not refuse on it"
# ============================================================
# A criterion owed at the close (its Task cell names the close row, step 9) whose eval names `landing-report --hand-holds`
# is proved by the line close-out reads last, after `delivered:`, so the pre-flight and the dry-run at step 8 owe it
# nothing; close-out proves it in the act that reads that line: at total=0 one proof event naming it, its evidence the
# continuation path, else nothing and the line quoted in the report. The plan is not written.
# FIXTURE FIDELITY: mk_fixture at Step 8; the close row T4 in its nine cells, pending, as a planner writes it, and the
# close's own session engaged and bound by the verb (lands_bind), so close-out lands T4 itself, as a run's close does;
# the two criteria are rows of `## Test design` naming their task in its Task column, one the close row's on the close's
# measure and one the close's step's on another eval. Where a criterion stands is the reader's answer (`reader cell`).
# fails-when: the run refuses on the pending row (OC-1; OC-1c shows the refusal live with the deferral off), or no proof names it at zero, one does above zero, a row on another eval is proved, or the plan is written.
OC_SID="closeout-owed-sid"
oc_rows() {  # <project> -> the page gains T4 (step 9, close) and two Test design rows with a Task column: one owed by T4 on the close's measure, one by step 9 on another eval
  local plan="$1/$PLAN_REL"
  case "$1" in "$SANDBOX"/*) : ;; *) echo "oc_rows: refusing outside the sandbox: '$1'" >&2; return 1 ;; esac
  awk '
    /^## / { sec = substr($0, 4) }
    sec == "Tasks" && /^\| T2 \|/ { print; print "| T4 | 9 | close | close-out, continuation.md | — | 10 | AC-2 | .bionic/docs/record/wave-01-fixture/continuation.md | — |"; next }
    sec == "Test design" && /^\| Requirement \|/ { print $0 " Task |"; next }
    sec == "Test design" && /^\|---/ { print $0 "---|"; next }
    sec == "Test design" && /^\| .* \| AC-1 \|/ { print $0 " — |"
      print "| — | fixture | AC-2 | T3 | `bash payload/hooks/session-poker.sh landing-report --hand-holds` at the close → `total=0` | the close reads above zero | T4 |"
      print "| — | fixture | AC-3 | T0 | the continuation names the release | the continuation is missing | 9 |"; next }
    { print }' "$plan" > "$plan.o" && mv "$plan.o" "$plan" && seal_fixture "$plan" "$1/$LOG_REL" && lands_bind "$1" "$OC_SID"
}
oc_after() { find "$1/.bionic/docs" -name "${PLAN_REL##*/}" -type f 2>/dev/null | head -1; }   # the plan where the close left it
oc_ask() { bash "$REPO_ROOT/payload/scripts/reader.sh" "$@" 2>/dev/null; }   # <plan> <question> [args] -> the reader's answer
oc_cell() { oc_ask "$1" cell "$2" | awk -F= '{ v[$1] = $2 } END { print v["state"] "|" v["by"] }'; }   # <plan> <AC> -> `<state>|<the event that discharged it>`
oc_eval() { awk '/^## / { s = ($0 == "## Test design"); next } s' "$1"; }   # <plan> -> its Test design section
oc_proofs() {  # <project> -> `<AC> <evidence>` of each proof naming a criterion in the run's log, space-joined
  awk -F'|' '$2 == "ev=proof" { a = ""; e = ""; for (i = 3; i <= NF; i++) { if ($i ~ /^ac=/) a = substr($i, 4); if ($i ~ /^evidence=/) e = substr($i, 10) }
    if (a != "") printf "%s%s %s", (n++ ? " " : ""), a, e }' "$1/.bionic/docs/record/wave-01-fixture/run.log" 2>/dev/null
}
OC_CONT="record/wave-01-fixture/continuation.md"
OC_AC1="AC-1 record/generic-evidence.md"
POC="$(mk_fixture owed-close)"; advance_to "$POC" 8; oc_rows "$POC"
expect_eq "OC-0 precondition: the session is bound, the close row is the page's at step 9, and both criteria pending, owed by the close row and the close's step" \
  "0|9|pending||task=T4|pending||task=9" \
  "$LP_RC|$(oc_ask "$POC/$PLAN_REL" row T4 | sed -n 's/^step=//p')|$(oc_cell "$POC/$PLAN_REL" AC-2)|$(oc_ask "$POC/$PLAN_REL" criterion AC-2 | /usr/bin/grep '^task=')|$(oc_cell "$POC/$PLAN_REL" AC-3)|$(oc_ask "$POC/$PLAN_REL" criterion AC-3 | /usr/bin/grep '^task=')"
OC_EV0="$(oc_eval "$POC/$PLAN_REL")"
# OC-1c: the deferral is what keeps OC-1 green. A copy of the plugin whose deferral never defers, run on the same page, must refuse on the live row.
OC_REV="$SANDBOX/oc-rev"; mkdir -p "$OC_REV" && cp -RL "$REPO_ROOT/payload" "$OC_REV/payload"; OC_W="$REPO_ROOT/payload/scripts/lib/walls.sh"
sed '/^matrix_row_deferred() {/,/^}/ s/^  local n="\${3%\[ab\]}"$/&; return 1/' "$OC_W" > "$OC_REV/payload/scripts/lib/walls.sh"
expect_eq "OC-1c0 the copy's deferral differs from the plugin's in one line" "1" "$(diff "$OC_W" "$OC_REV/payload/scripts/lib/walls.sh" | grep -c '^>')"
POR="$(mk_fixture owed-close-rev)"; advance_to "$POR" 8; oc_rows "$POR"
OC_R="$REPO_ROOT"; OC_S="$SCRIPT"; REPO_ROOT="$OC_REV"; SCRIPT="$OC_REV/payload/scripts/close-out.sh"; run_close_as "$OC_SID" "$POR" run; REPO_ROOT="$OC_R"; SCRIPT="$OC_S"
expect_ne "OC-1c the run on that copy refuses" "0" "$CO_RC"
expect_contains "OC-1d …on the live row, in the gate's words" "the row is live past the step that owes it" "$CO_OUT"
run_close_as "$OC_SID" "$POC" run
OC_LINE="$(printf '%s\n' "$CO_OUT" | grep '^hand-holds: ')"
expect_eq "OC-1 run exits 0: the pre-flight and the dry-run before the flip do not refuse on the row the close owes" "0" "$CO_RC"
[ "$CO_RC" = 0 ] || printf '%s\n' "$CO_OUT" | tail -15 | sed 's/^/    | /'
expect_contains "OC-1b …the dry-run said ok" "gate: ok" "$CO_OUT"
expect_contains "OC-2 precondition: the line read last reads zero" "hand-holds: total=0 " "$OC_LINE"
OC_P="$(oc_after "$POC")"
expect_eq "OC-3 the run's log holds one proof naming AC-2, its evidence the continuation path, beside the page's AC-1, and none naming AC-3, on another measure" \
  "$OC_AC1 AC-2 $OC_CONT" "$(oc_proofs "$POC")"
expect_eq "OC-3b …so the reader reads AC-2 discharged by that proof and AC-3 still pending, and the delivered page's Test design is as it was" \
  "discharged|proof|pending||$OC_EV0" "$(oc_cell "$OC_P" AC-2)|$(oc_cell "$OC_P" AC-3)|$(oc_eval "$OC_P")"
expect_contains "OC-3c …and the card names the row and the status it wrote" "matrix: AC-2 discharged" "$CO_OUT"
expect_eq "OC-3e …and a run with no act by hand has no ## Hand acts section beside its ## Hand-holds" "1|0" \
  "$(grep -c '^## Hand-holds$' "$POC/$CONT_REL")|$(grep -c '^## Hand acts$' "$POC/$CONT_REL")"
expect_eq "OC-3d …written in the act that reads the measure last, before the archive is asked: its line follows the hand-holds line and precedes archived:" "yes" \
  "$(printf '%s\n' "$CO_OUT" | awk '/^hand-holds: / { h = NR } /^matrix: AC-2 / { m = NR } /^archived: / { a = NR } END { print (h && m > h && a > m) ? "yes" : "no" }')"
# above zero: an amend after the last landing, as §READ-ORDER plants it
POB="$(mk_fixture owed-close-above)"; advance_to "$POB" 8; oc_rows "$POB"
OB_REC="$POB/.bionic/docs/record/wave-01-fixture"
printf 'run/v1|ev=published|row=T1|commit=%s|kind=queue|by=-|why=-|at=%s\n' "$(printf 'e%.0s' $(seq 40))" "$(ro_ago 20)" >> "$OB_REC/run.log"
printf 'run/v1|ev=hand|by=fixture|name=w-oc|what=amend|why=widen the files|at=%s\n' "$(ro_ago 5)" >> "$OB_REC/run.log"
seal_fixture "$POB/$PLAN_REL" "$OB_REC/run.log"
OB_EV0="$(oc_eval "$POB/$PLAN_REL")"
run_close_as "$OC_SID" "$POB" run
OB_LINE="$(printf '%s\n' "$CO_OUT" | grep '^hand-holds: ')"
expect_eq "OC-5 a measure above zero still delivers: run exits 0" "0" "$CO_RC"
[ "$CO_RC" = 0 ] || printf '%s\n' "$CO_OUT" | tail -15 | sed 's/^/    | /'
expect_contains "OC-5b precondition: the line read last counts the amend" "amends=1 " "$OB_LINE"
OB_P="$(oc_after "$POB")"
expect_eq "OC-6 above zero the log's one proof naming a criterion is the page's AC-1, the reader reads AC-2 pending, and the delivered page's Test design is as it was" \
  "$OC_AC1|pending||$OB_EV0" "$(oc_proofs "$POB")|$(oc_cell "$OB_P" AC-2)|$(oc_eval "$OB_P")"
expect_contains "OC-6c …and the card says it is blocked, naming the line" "matrix: AC-2 blocked — $OB_LINE" "$CO_OUT"

finish
