#!/bin/bash
# Tests for the release approval card at the end of a run the verbs carried there: the door fixture (tests/lib/door.sh)
# is walked from its authored plan to the end state by the run's own verbs, and the card is rendered on what they left.
#
#   §CLOSE         the fixture's plan is put in the release order (the release row moved to step 7, a regression row at
#                  step 5, an integrate row reading the release and merge approvals), the build row lands by hand, the
#                  matrix is rendered and discharged, Steps 5, 6 and 7 are entered with the regression run and recorded,
#                  five readings registered by their readers and the declared check run, and the release row lands by
#                  hand with the release. At that head every fact holds and no `approved: release` line is written, so
#                  `current 6` and `current 7` would advance and `current 8` refuses on the release approval alone; the
#                  card exits 0, writes its page, and its replay table puts `approve:release` and `approve:merge`.
#   §CLOSE-MUTANT  the same end state under copies of the tree under test. Unchanged, the copy renders the card. With
#                  the card's `approve:release` settle deleted, the card is early. With the judge's refusal reworded in
#                  the one place it is spelled, the judge prints the new words and the card still renders. The refusal's
#                  text is spelled once, in hooks/poker/judge.sh, and read by payload/scripts/card.sh.
#   §GROW          criteria the matrix table lacks, their eval types in words, gain their rows at the mapped tier from
#                  matrix-render, before their blocks; an empty table renders whole; an unknown type is refused.
#
# FIXTURE FIDELITY: the repository is door_world's, a real `git init` with the check's closure, the real changelog and a
# plan whose Step-3 state the library authors. Every later change to the plan is a verb's: task-set, task-add,
# matrix-render, matrix-set, discharge, step-line, step-field, current, proof-add and the hand door's row line. This
# file never writes the plan, save §GROW's Eval design rows, which no verb writes. What it writes are the records the run's actors write: a one-row suite in the build
# row's commit, the matrix row's evidence, the walk and audit records, five reading records in the readers' grammar
# (the structure reading answering every id the shipped checks file names), and each reader's roster row through the
# production writer (`roster_row`), closed by the sweeper's own `ack`. SYNTHESIZED: the readers' names and the words
# of their records.
#
# ANTI-VACUITY: with no fixture built the suite stops before its first section, having asserted nothing, which finish
# fails. Every absence is read beside a presence through the same reader in the same fixture; every mutant first proves
# it changed the copy and that the copy ran, beside an unchanged copy that renders.
#
# Usage: bash tests/door-card.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0
DC_LOADED=0
# shellcheck source=/dev/null
. "$(dirname "$0")/lib/door.sh" && DC_LOADED=1
[ -n "${WORLD_ROOT:-}" ] || . "$(dirname "$0")/lib/world.sh"
# shellcheck source=/dev/null
. "$(dirname "$0")/lib/roster-row.sh"

setup_section "the door fixture, built once"

DC=""; DC_BASE=""
if [ "$DC_LOADED" = 1 ]; then read -r DC DC_BASE <<EOF
$(door_world "$WORLD_ROOT/door")
EOF
fi
echo "door_world: ${DC:-<nothing>} at ${DC_BASE:-<none>}"
if [ "$DC_LOADED" != 1 ] || [ -z "$DC" ] || [ ! -d "$DC/.git" ]; then
  finish
fi

DC_PLAN="$DC/$DOOR_PLAN_REL"
DC_REC="$DC/.bionic/docs/record/wave-x"
DC_LIB="$BIONIC_SCRIPTS_DIR/payload/scripts/lib"
dc_head() { git -C "$1" rev-parse --verify -q refs/heads/wave/x; }   # <root>
# dc_verb <label> <verb> [args] -> DOOR_OUT, DOOR_RC of the tree under test's poker run in the fixture as the bound
# session; the row holds its exit at 0, and the verb and its first line are printed, the walk's own log.
dc_verb() {
  local label="$1"
  shift
  door_run "$DC" bash "$DOOR_POKER" "$@"
  printf 'dc: %s -> rc %s: %s\n' "$1" "$DOOR_RC" "$(printf '%s\n' "$DOOR_OUT" | awk 'NF { print; exit }')"
  expect_eq "$label" "0" "$DOOR_RC"
  [ "$DOOR_RC" = 0 ] || printf '%s\n' "$DOOR_OUT" | sed 's/^/    | /' | head -20
}
dc_commit() { _door_inside "$1" && git -C "$1" add -A >/dev/null 2>&1 && git -C "$1" commit --quiet -m "$2"; }   # <tree> <message>
dc_current() { /usr/bin/grep -E '^current: ' "$1" | head -1; }   # <plan> -> its current: line
# dc_approved <plan> -> the `approved…` lines of the plan's ## SDLC State, the plan's own approval and any the user gave
dc_approved() { awk '/^## SDLC State/ { f = 1; next } f && /^## / { exit } f && /^approved/' "$1"; }
dc_keys() {   # <record dir> <h8> -> the keys of the card's replay table, in its order, space-joined
  /usr/bin/grep '^release-approval/v1|dec=' "$1/release-approval-$2.md" 2>/dev/null \
    | awk -F'|' '{ for (i = 2; i <= NF; i++) if (index($i, "key=") == 1) print substr($i, 5) }' | paste -sd' ' -
}
# dc_reading <name> <question> <scope> <a> <b> -> the reader's record and its roster row; its kind is the question's
# reader: the auditor reads evidence, the critic the other two.
dc_reading() {
  local nm="$1" q="$2" sc="$3" t=bionic:critic
  [ "$q" != evidence ] || t=bionic:auditor
  { printf 'reviewed: %s..%s\nquestion: %s\nresult: pass\nscope: %s\n' "$4" "$5" "$q" "$sc"
    [ "$q" != structure ] || awk '/^- \*\*[a-z][a-z-]*\*\*/ { s = $0; sub(/^- \*\*/, "", s); sub(/\*\*.*$/, "", s)
      print "check: " s " PASS the build row is one line of a library and a one-row suite" }' \
      "$BIONIC_SCRIPTS_DIR/payload/context/checks-structure.md"
    printf '\nfindings: 0\n\nThe reader read the build row and found nothing.\n'; } > "$DC_REC/$nm.md"
  printf '%s|questions=%s\n' "$(roster_row_fixture session="$WORLD_SID" name="$nm" agent_id="a-$nm" subagent_type="$t" \
    launched_at=2026-10-01T00:00:00Z deliverable="$DC_REC/$nm.md")" "$q" >> "$DC/.bionic/tmp/roster-$WORLD_SID.state"
}

# ============================================================
section "§CLOSE: the verbs carry the fixture to the end state, and the card renders on it"
# ============================================================
DC_T0="$SECONDS"
dc_verb "(c1) task-set moves the release row to step 7" task-set T2 step=7 --reason 'the release is the doc row at step 7'
dc_verb "(c2) task-add adds the regression row at step 5" task-add T3 5 test 'the regression. The whole suite runs once.' orchestrator — 10 REQ-1 —
dc_verb "(c3) task-add adds the integrate row that reads both approvals" \
  task-add T4 8 integrate 'merge into main. The run reaches main by its merge.' orchestrator — 10 REQ-1 — 'approval:release, approval:merge, head'
expect_eq "(c4) the plan is in the release order, its regression row T3" "T3" \
  "$(bash -c '. "$1/units.sh" && units_order "$2"' _ "$DC_LIB" "$DC_PLAN" 2>/dev/null)"

DC_P1="$(door_piece "$DC" T1)"
printf 'door_landed() { :; }\n' >> "$DC_P1/payload/scripts/lib/said.sh"
printf '#!/bin/bash\n. "$(dirname "$0")/lib/assert.sh"\nsection "the door holds"\nexpect_eq "one is one" 1 1\nfinish\n' \
  > "$DC_P1/tests/door.test.sh"
dc_commit "$DC_P1" "a library change and its suite" && door_land "$DC" "$DC_P1"
printf 'dc: land T1 -> rc %s\n' "$DOOR_RC"
expect_eq "(c5) the build row lands by hand" "0" "$DOOR_RC"

printf 'the library change holds\n' > "$DC_REC/ac-1.1.md"
dc_verb "(c6) matrix-render writes the criterion's block" matrix-render
dc_verb "(c7) matrix-set discharges the row with its evidence" matrix-set AC-1.1 status=discharged evidence=record/wave-x/ac-1.1.md task=T1
dc_verb "(c8) discharge writes the auditor cell" discharge AC-1.1
printf 'the walk the build row needed\n' > "$DC_REC/walk.md"
printf 'CONFIRMED: the one criterion is proved\n' > "$DC_REC/audit.md"
dc_verb "(c9) step-line writes Step 5" step-line 5 'regression at record/wave-x/regression-run.log'
dc_verb "(c10) step-field names the walk" step-field 5 walk-artifact=record/wave-x/walk.md
dc_verb "(c11) step-field records the auditor" step-field 5 'auditor=CONFIRMED, record/wave-x/audit.md'
dc_verb "(c12) current 5" current 5
DC_H1="$(dc_head "$DC")"
dc_verb "(c13) regression-run runs the whole run green" regression-run
dc_verb "(c14) proof-add records the regression" proof-add regression "record/wave-x/regression-run-$DC_H1.log"
for dc_qs in evidence:piece adversarial:piece structure:piece adversarial:whole structure:whole; do
  dc_reading "w-${dc_qs%%:*}-${dc_qs#*:}" "${dc_qs%%:*}" "${dc_qs#*:}" "$DC_BASE" "$DC_H1"
  dc_verb "(c15 ${dc_qs}) proof-add registers the reading" proof-add review "record/wave-x/w-${dc_qs%%:*}-${dc_qs#*:}.md" \
    --question "${dc_qs%%:*}" --reader "w-${dc_qs%%:*}-${dc_qs#*:}"
done
door_run "$DC" bash "$BIONIC_SCRIPTS_DIR/hooks/session-sweeper.sh" ack \
  w-evidence-piece w-adversarial-piece w-structure-piece w-adversarial-whole w-structure-whole
expect_eq "(c16) the sweeper acks the five readers" "0" "$DOOR_RC"
dc_verb "(c17) step-line writes Step 6" step-line 6 'review at record/wave-x/w-evidence-piece.md'
dc_verb "(c18) current 6" current 6
dc_verb "(c19) release-check at the build head" release-check
printf 'no decision this run\n' > "$DC_REC/adr.md"
dc_verb "(c20) step-line writes Step 7" step-line 7 'documented at record/wave-x/adr.md'
dc_verb "(c21) step-field names the document" step-field 7 adr=record/wave-x/adr.md
dc_verb "(c22) current 7" current 7

DC_P2="$(door_piece "$DC" T2)" && door_release "$DC" "$DC_P2" >/dev/null && door_land "$DC" "$DC_P2"
printf 'dc: land T2 -> rc %s\n' "$DOOR_RC"
expect_eq "(c23) the release row lands by hand with the release" "0" "$DOOR_RC"
dc_verb "(c24) release-check at the release head" release-check
DC_H="$(dc_head "$DC")"; DC_H8="${DC_H:0:8}"
echo "dc: the walk took $((SECONDS - DC_T0)) s and ended at $DC_H"

expect_eq "(c25) the end state is current: 7" "current: 7" "$(dc_current "$DC_PLAN")"
expect_contains "(c26) the plan carries its own approval line" "approved-by: " "$(dc_approved "$DC_PLAN")"
expect_absent "(c27) …and no approved: release line" "approved: release" "$(dc_approved "$DC_PLAN")"
dc_verb "(c28) current 6 --check would advance at the release head" current 6 --check
dc_verb "(c29) current 7 --check would advance: every fact the run owes holds at the release head" current 7 --check
door_run "$DC" bash "$DOOR_POKER" current 8 --check
DC_C8="$DOOR_OUT"
expect_eq "(c30) current 8 --check refuses" "1" "$DOOR_RC"
expect_contains "(c31) …on the release approval the plan does not carry" "carries no approved: release line" "$DC_C8"
expect_eq "(c32) …and on nothing else: one refusal line" "1" "$(printf '%s\n' "$DC_C8" | /usr/bin/grep -c '^poker: REFUSED')"

door_run "$DC" bash "$DOOR_POKER" release-approval "$DC_PLAN"
DC_CARD_RC="$DOOR_RC"; DC_CARD="$DOOR_OUT"
printf 'dc: release-approval -> rc %s: %s\n' "$DC_CARD_RC" "$(printf '%s\n' "$DC_CARD" | awk 'NF { print; exit }')"
expect_eq "(c33) the release approval card exits 0" "0" "$DC_CARD_RC"
expect_contains "(c34) …and renders the page" "Release approval · door $DOOR_VERSION" "$DC_CARD"
expect_eq "(c35) …written to the record at the head" "yes" "$([ -s "$DC_REC/release-approval-$DC_H8.md" ] && echo yes || echo no)"
expect_eq "(c36) the replay table puts approve:release and approve:merge" "approve:release approve:merge" "$(dc_keys "$DC_REC" "$DC_H8")"

# ============================================================
section "§CLOSE-MUTANT: the approve:release settle is load-bearing, and the refusal is spelled once"
# ============================================================
DCM_JUDGE="$BIONIC_SCRIPTS_DIR/hooks/poker/judge.sh"
DCM_CARD="$BIONIC_SCRIPTS_DIR/payload/scripts/card.sh"
DCM_TEXT="is admitted at the head the user approved for release, and"
expect_eq "(s1) the refusal's text is spelled once in the judge" "1" "$(/usr/bin/grep -c "$DCM_TEXT" "$DCM_JUDGE")"
expect_eq "(s2) …and never in the card" "0" "$(/usr/bin/grep -c "$DCM_TEXT" "$DCM_CARD")"
expect_eq "(s3) the card reads it from the judge, by the function the judge defines and calls" "yes yes" \
  "$([ "$(/usr/bin/grep -c 'cur8_unapproved_line' "$DCM_CARD")" -ge 1 ] && echo yes || echo no) $([ "$(/usr/bin/grep -c 'cur8_unapproved_line' "$DCM_JUDGE")" -ge 2 ] && echo yes || echo no)"

# dcm_tree <dir> -> a copy of the tree under test's hooks and payload under WORLD_ROOT, run as a plugin root
dcm_tree() {
  mkdir -p "$1/payload" && cp -R "$BIONIC_SCRIPTS_DIR/hooks" "$1/hooks" \
    && cp -R "$BIONIC_SCRIPTS_DIR/payload/scripts" "$BIONIC_SCRIPTS_DIR/payload/context" "$1/payload/" \
    && ln -s ../hooks "$1/payload/hooks"
}
# dcm_card <tree> <copy> -> DOOR_OUT, DOOR_RC of that tree's release-approval in a copy of the end state. The copy
# carries the page §CLOSE wrote, so it is removed first: a replay table read afterwards is this render's alone.
dcm_card() {
  rm -f "$2"/.bionic/docs/record/wave-x/release-approval-*.md
  door_run "$2" bash "$1/hooks/session-poker.sh" release-approval "$2/$DOOR_PLAN_REL"
}

DCM0="$WORLD_ROOT/tree-same"; dcm_tree "$DCM0"
read -r DCM0_R _ <<EOF
$(door_copy "$DC" "$WORLD_ROOT/door-same")
EOF
dcm_card "$DCM0" "$DCM0_R"
expect_eq "(m0) an unchanged copy of the tree renders the card on a copy of the end state" "0 approve:release approve:merge" \
  "$DOOR_RC $(dc_keys "$DCM0_R/.bionic/docs/record/wave-x" "$DC_H8")"

DCM1="$WORLD_ROOT/tree-unsettled"; dcm_tree "$DCM1"
# The cut replaces the settle statement with a no-op instead of deleting its line: the settle is the whole body of an
# if, and an emptied body leaves a card.sh that does not parse, so the mutant would fail on syntax, not on the
# missing settle.
sed -i.orig 's/^\( *\).*approve:release"\$.*$/\1:/' "$DCM1/payload/scripts/card.sh"
expect_eq "(m1a) the mutant deleted the approve:release settle from its card" "yes" \
  "$(cmp -s "$DCM1/payload/scripts/card.sh" "$DCM1/payload/scripts/card.sh.orig" && echo no || echo yes)"
read -r DCM1_R _ <<EOF
$(door_copy "$DC" "$WORLD_ROOT/door-unsettled")
EOF
dcm_card "$DCM1" "$DCM1_R"
expect_eq "(m1b) with the settle deleted the card does not render" "1" "$DOOR_RC"
expect_contains "(m1c) …it is early on the advance to 8" "CARD-EARLY — current 8 --check" "$DOOR_OUT"

DCM2="$WORLD_ROOT/tree-reworded"; dcm_tree "$DCM2"
sed -i.orig 's/current: 8 in the order (/current: 8 waits, in the order (/' "$DCM2/hooks/poker/judge.sh"
expect_eq "(m2a) the mutant rewords the judge's refusal in its judge" "yes" \
  "$(cmp -s "$DCM2/hooks/poker/judge.sh" "$DCM2/hooks/poker/judge.sh.orig" && echo no || echo yes)"
read -r DCM2_R _ <<EOF
$(door_copy "$DC" "$WORLD_ROOT/door-reworded")
EOF
door_run "$DCM2_R" bash "$DCM2/hooks/session-poker.sh" current 8 --check
expect_contains "(m2b) the reworded judge prints its new words" "poker: REFUSED — current: 8 waits, in the order (" "$DOOR_OUT"
dcm_card "$DCM2" "$DCM2_R"
expect_eq "(m2c) …and the card still renders, settling the release approval" "0 approve:release approve:merge" \
  "$DOOR_RC $(dc_keys "$DCM2_R/.bionic/docs/record/wave-x" "$DC_H8")"

# ============================================================
section "§GROW: a criterion the matrix table lacks gains its row at its tier, by matrix-render, before its block"
# ============================================================
# The Eval design names each criterion's eval type in words; lib/scale.sh `tier_of_eval_type` is the one map from a
# type to its tier (static, unit, hermetic, live, human to T0 to T4; a bare T<n> is itself). matrix-render adds a
# `| AC | tier | status | evidence | auditor |` row for every Eval design row the table lacks, in Eval design order,
# then writes the blocks at those tiers, so a criterion added after approval reaches the table and its block by the
# one verb, and an empty table renders whole. A type the map does not hold is refused, the plan unchanged.
# FIXTURE FIDELITY: a fresh door_world at its Step-3 state, then the Eval design rows a person adds after approval:
# no verb writes an Eval design row, so the plan's own table is extended in the plan's grammar.
# fails-when: a lacking row is left out, or lands at a tier the map does not give, or after the blocks; a type in
# words is refused; an empty table is refused; an unknown type is guessed at.
DCG_PLAN=""
# dcg_world <dir> <table rows: keep | empty> -> the fixture's root, its Eval design grown by four criteria in words
dcg_world() {
  local r
  read -r r _ <<EOF2
$(door_world "$1")
EOF2
  [ -n "$r" ] || return 1
  awk -v k="$2" '
    /^\| REQ-1 \| fixture run \| AC-1\.1 / { print
      print "| REQ-1 | a unit pin | AC-1.2 | unit | `tests/door.test.sh` | the pin is red |"
      print "| REQ-1 | the line read | AC-1.3 | Live | `tests/door.test.sh` | the line is missed |"
      print "| REQ-1 | a grep | AC-1.4 | static | `grep -c door payload/scripts/lib/said.sh` | the count is 0 |"
      print "| REQ-1 | a person reads it | AC-1.5 | T4 | the walk | the reader is lost |"
      next }
    k == "empty" && /^\| AC-1\.1 \| T1 \|/ { next }
    { print }' "$r/$DOOR_PLAN_REL" > "$r/$DOOR_PLAN_REL.n" && mv "$r/$DOOR_PLAN_REL.n" "$r/$DOOR_PLAN_REL"
  printf '%s' "$r"
}
dcg_rows() { awk '/^## Verification Matrix/ { m = 1; next } /^## / { m = 0 } m && /^\| AC-/ { split($0, c, /[ \t]*\|[ \t]*/); printf "%s%s %s %s", s, c[2], c[3], c[4]; s = "|" } END { print "" }' "$1"; }   # <plan> -> `<AC> <tier> <status>|…`
dcg_eval() { awk -v a="$2:" 'index($0, a) == 1 { b = 1; next } b && /^[^ \t]/ { b = 0 } b && /^[ \t]+eval:/ { sub(/^[ \t]+eval:[ \t]*/, ""); print; exit }' "$1"; }   # <plan> <AC> -> its block's eval: value
# dcg_order <plan> -> `rows-first` when the last table row comes before the first AC block line
dcg_order() { awk '/^\| AC-/ { lr = NR } /^AC-[^ \t:]+:/ && !fb { fb = NR } END { print ((lr && fb && lr < fb) ? "rows-first" : "blocks-first " lr " " fb) }' "$1"; }

DCG="$(dcg_world "$WORLD_ROOT/grow" keep)"; DCG_PLAN="$DCG/$DOOR_PLAN_REL"
expect_eq "(g0) precondition: the Eval design names five criteria, the table one" "AC-1.1 T1 pending" "$(dcg_rows "$DCG_PLAN")"
door_run "$DCG" bash "$DOOR_POKER" matrix-render
printf 'dc: matrix-render (grow) -> rc %s: %s\n' "$DOOR_RC" "$(printf '%s\n' "$DOOR_OUT" | awk 'NF { print; exit }')"
expect_eq "(g1) matrix-render renders the criteria the table lacked, their types in words: exit 0" "0" "$DOOR_RC"
expect_eq "(g2) the table carries a row for every Eval design row, in its order, at the tier the type maps to" \
  "AC-1.1 T1 pending|AC-1.2 T1 pending|AC-1.3 T3 pending|AC-1.4 T0 pending|AC-1.5 T4 pending" "$(dcg_rows "$DCG_PLAN")"
expect_eq "(g3) …the new rows' evidence and auditor cells are the dash the table's rows carry" "| AC-1.2 | T1 | pending | — | — |" \
  "$(awk '/^## Verification Matrix/ { m = 1; next } /^## / { m = 0 } m && index($0, "| AC-1.2 |") == 1' "$DCG_PLAN")"
expect_eq "(g4) the rows are written before the blocks" "rows-first" "$(dcg_order "$DCG_PLAN")"
expect_eq "(g5) each block reads its tier from its row" "T1 — \`tests/door.test.sh\`|T3 — \`tests/door.test.sh\`|T4 — the walk" \
  "$(dcg_eval "$DCG_PLAN" AC-1.2)|$(dcg_eval "$DCG_PLAN" AC-1.3)|$(dcg_eval "$DCG_PLAN" AC-1.5)"
expect_contains "(g5b) …and the T4 block owes the user's confirmation" "user-confirmed: pending" \
  "$(awk '/^AC-1\.5:/ { b = 1; next } b && /^[^ \t]/ { b = 0 } b' "$DCG_PLAN")"
door_run "$DCG" bash "$DOOR_POKER" matrix-render
expect_eq "(g6) a second render adds nothing: exit 0, the table unchanged" "0|AC-1.1 T1 pending|AC-1.2 T1 pending|AC-1.3 T3 pending|AC-1.4 T0 pending|AC-1.5 T4 pending" \
  "$DOOR_RC|$(dcg_rows "$DCG_PLAN")"

DCE="$(dcg_world "$WORLD_ROOT/grow-empty" empty)"; DCE_PLAN="$DCE/$DOOR_PLAN_REL"
expect_contains "(g7-pre) the empty world's table has its header and no row" "| AC | tier | status | evidence | auditor |" \
  "$(awk '/^## Verification Matrix/ { m = 1 } m' "$DCE_PLAN")"
expect_eq "(g7-pre2) …read by the same row reader (g2)" "" "$(dcg_rows "$DCE_PLAN")"
door_run "$DCE" bash "$DOOR_POKER" matrix-render
expect_eq "(g7) an empty tier table renders whole: exit 0, every row" \
  "0|AC-1.1 T2 pending|AC-1.2 T1 pending|AC-1.3 T3 pending|AC-1.4 T0 pending|AC-1.5 T4 pending" "$DOOR_RC|$(dcg_rows "$DCE_PLAN")"
expect_eq "(g7b) …the rows before the blocks" "rows-first" "$(dcg_order "$DCE_PLAN")"

DCU="$(dcg_world "$WORLD_ROOT/grow-unknown" keep)"; DCU_PLAN="$DCU/$DOOR_PLAN_REL"
sed -i.orig 's/| AC-1\.3 | Live |/| AC-1.3 | by eye |/' "$DCU_PLAN"
expect_eq "(g8-pre) the unknown world's AC-1.3 is typed in words no map holds" "1" "$(/usr/bin/grep -c '| AC-1.3 | by eye |' "$DCU_PLAN")"
cp "$DCU_PLAN" "$DCU_PLAN.before"
door_run "$DCU" bash "$DOOR_POKER" matrix-render
expect_eq "(g8) a type the map does not hold is refused, the plan unchanged" "1|same" \
  "$DOOR_RC|$(cmp -s "$DCU_PLAN" "$DCU_PLAN.before" && echo same || echo changed)"
expect_contains "(g8b) …naming the criterion and its type" "AC-1.3 (eval type: by eye)" "$DOOR_OUT"

finish
