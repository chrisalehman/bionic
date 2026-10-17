#!/bin/bash
# THE REGRESSION'S MACHINE TOKENS, RENAMED AND ALIASED ONCE (epic-23 wave-38 T8; REQ-9 AC-9.1, AC-9.2 key half,
# AC-9.4; D6).
#
# WHAT THIS SUITE OWNS. payload/scripts/lib/alias.sh, the one map from each old spelling of the full regression's
# machine tokens to its new one, and the seam each token is read at:
#
#     floor-run                 -> regression-run             the verb, read at `VERB="$1"` in hooks/session-poker.sh
#     proof-add floor           -> proof-add regression       the proof kind, read at `PF_KIND="$1"`
#     floor: (config.yaml)      -> regression-command:        the regression's command, read by `regression-run`
#     kind=floor                -> kind=regression            a proof line's kind, read by lib/proof.sh `proof_fields`
#     proof:floor               -> proof:regression           a reads token, read by lib/units.sh's tokenizer
#     born: floor               -> born: regression           a born marker, read by lib/units.sh `units_born_marks`
#     --born floor:             -> --born regression:         task-add's operand
#     of=floor                  -> of=regression              the marker's backing
#     floor-run-<sha>.log       -> regression-run-<sha>.log   the log name; the second-run glob matches both
#     rigor-floor:              -> rigor-minimum:             the rigor minimum, read by hooks/canonical-sdlc-governing-skill.sh
#
# Everything written from now on carries the new spelling. A spelling a person types or a config file carries is
# read through `alias_read`, which prints `deprecated: <old> is <new>; the old spelling works until 1.22.0` to stderr
# once per process for that spelling. A token a 1.20.0 tool wrote into a plan (a proof line, a reads cell, a born
# marker) is read silently: the plan still judges, and nobody is told to edit a record (A-T8-1).
#
# §ALIAS: each pair through the library, and each typed token end to end through the real verb: the new spelling
#   works and says nothing; the old spelling works and says exactly one deprecated: line; a 1.20.0 plan judges as
#   its renamed twin does.
# §AGREE: for each token the alias and the new name reach one implementation: the seam calls the map, the readers
#   answer the old and the new spelling with one answer, and no production line outside alias.sh spells an old token
#   (a planted second copy goes red).
#
# FIXTURE FIDELITY (the rule of that name). The verb fixtures are session-poker-4 §FLOOR-DECLARED's and session-poker-3
# §BORN-FLOOR's shapes, built with the shards' own prelude; the 1.20.0 plan is SYNTHESIZED, its proof line, reads cells
# and born marker in the shapes 1.20.0's writers wrote (proof_floor_line, kdef, units_add_row's born operand).
# ANTI-VACUITY (the rule of that name). Every empty readback sits beside a positive on the same reader: each pair's
# silent new spelling beside its old spelling's line, each AP equality beside a non-empty answer, the scan beside a
# proof it read files and two planted copies it finds, each plant after a parse check of the mutant.
#
# HERMETIC: every repository is a scratch git repository under the prelude's TMPROOT; the hook and libraries are this
# tree's. Usage: bash tests/run.sh --only regression-rename.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"
. "$(dirname "$0")/lib/bound-marker.sh"
. "$(dirname "$0")/lib/roster-row.sh"
. "$(dirname "$0")/lib/swept-marker.sh"
. "$(dirname "$0")/lib/live-answer.sh"

POKER="${BIONIC_HOOKS_DIR}/session-poker.sh"
LIB="${BIONIC_SCRIPTS_DIR}/payload/scripts/lib"
ALIAS_SH="$LIB/alias.sh"
S46_LIB="$LIB/proof.sh"
GOV_HOOK="${BIONIC_HOOKS_DIR}/canonical-sdlc-governing-skill.sh"
. "$(dirname "$0")/session-poker.prelude.sh"

DEP_TAIL='; the old spelling works until 1.22.0'

# al <function> <args...> -> stdout of one alias.sh function in a clean shell; stderr to $TMPROOT/al.err
al() {
  bash -c '. "$1" || exit 9; shift; "$@"' _ "$ALIAS_SH" "$@" 2> "$TMPROOT/al.err"
}
al_err() { cat "$TMPROOT/al.err" 2>/dev/null; }
deps_in() { printf '%s\n' "$1" | /usr/bin/grep -c '^deprecated: ' | tr -d ' '; }   # <text> -> its deprecated: lines

# ============================================================
section "§ALIAS-MAP: alias_token answers every pair, the new spelling silently, the old with one deprecated: line"
# ============================================================
expect_true "AM-0 lib/alias.sh exists and passes bash -n" bash -n "$ALIAS_SH"
for am_pair in \
  "verb|floor-run|regression-run|floor-run|regression-run" \
  "proof-kind|floor|regression|proof-add floor|proof-add regression" \
  "config|floor|regression-command|floor:|regression-command:" \
  "kind|floor|regression|kind=floor|kind=regression" \
  "reads|proof:floor|proof:regression|proof:floor|proof:regression" \
  "born|floor|regression|born: floor|born: regression" \
  "born-operand|floor:|regression:|--born floor:|--born regression:" \
  "born-of|floor|regression|of=floor|of=regression" \
  "log|floor-run-|regression-run-|floor-run-<sha>.log|regression-run-<sha>.log" \
  "rigor-key|rigor-floor|rigor-minimum|rigor-floor:|rigor-minimum:"; do
  IFS='|' read -r am_k am_old am_new am_os am_ns <<< "$am_pair"
  expect_eq "AM-$am_k-1 alias_token $am_k $am_new is $am_new" "$am_new" "$(al alias_token "$am_k" "$am_new")"
  expect_eq "AM-$am_k-1b …and says nothing on stderr" "" "$(al_err)"
  expect_eq "AM-$am_k-2 alias_token $am_k $am_old is $am_new" "$am_new" "$(al alias_token "$am_k" "$am_old")"
  expect_eq "AM-$am_k-2b …and prints exactly the one deprecated: line" "deprecated: $am_os is $am_ns$DEP_TAIL" "$(al_err)"
done
expect_eq "AM-3 a word the map does not carry is answered as itself" "review" "$(al alias_token proof-kind review)"
expect_eq "AM-3b …silently" "" "$(al_err)"
expect_eq "AM-4 the same old spelling read twice in one process prints its line once" \
  "regression-run regression-run|1" \
  "$(bash -c '. "$1"; alias_read verb floor-run; a="$ALIAS_TOKEN"; alias_read verb floor-run; printf "%s %s" "$a" "$ALIAS_TOKEN"' _ "$ALIAS_SH" 2> "$TMPROOT/al.err")|$(deps_in "$(al_err)")"
expect_eq "AM-4b two old spellings in one process print one line each" "2" \
  "$(bash -c '. "$1"; alias_read verb floor-run; alias_read config floor; alias_read verb floor-run' _ "$ALIAS_SH" 2>&1 | /usr/bin/grep -c '^deprecated: ' | tr -d ' ')"
expect_eq "AM-5 alias_spellings log names the new prefix first, then the old" "regression-run- floor-run-" \
  "$(al alias_spellings log | paste -sd' ' -)"
expect_eq "AM-6 alias_cell reads normalises each token of a cell, live: kept, others untouched" \
  "proof:regression, live:proof:regression, proof:review, head" \
  "$(bash -c '. "$1"; alias_cell reads "proof:floor, live:proof:floor, proof:review, head"; printf "%s" "$ALIAS_TOKEN"' _ "$ALIAS_SH" 2>/dev/null)"
expect_eq "AM-6b …and a cell carrying no old token comes back byte for byte" "proof:review,head" \
  "$(bash -c '. "$1"; alias_cell reads "proof:review,head"; printf "%s" "$ALIAS_TOKEN"' _ "$ALIAS_SH" 2>/dev/null)"
AM_CFG="$TMPROOT/am-cfg"; mkdir -p "$AM_CFG/.bionic"
printf 'floor: bash old.sh\n' > "$AM_CFG/.bionic/config.yaml"
expect_eq "AM-7 alias_config reads the old key's value when only the old key is written" "bash old.sh|1" \
  "$(bash -c '. "$1/roots.sh"; . "$1/alias.sh"; alias_config "$2" config ""; printf "%s" "$ALIAS_VALUE"' _ "$LIB" "$AM_CFG" 2> "$TMPROOT/al.err")|$(deps_in "$(al_err)")"
printf 'floor: bash old.sh\nregression-command: bash new.sh\n' > "$AM_CFG/.bionic/config.yaml"
expect_eq "AM-7b …and the new key's value, silently, when both are written" "bash new.sh|0" \
  "$(bash -c '. "$1/roots.sh"; . "$1/alias.sh"; alias_config "$2" config ""; printf "%s" "$ALIAS_VALUE"' _ "$LIB" "$AM_CFG" 2> "$TMPROOT/al.err")|$(deps_in "$(al_err)")"
expect_eq "AM-8 alias_keyed reads a key: value text, the old key with its line" "double|1" \
  "$(bash -c '. "$1"; alias_keyed rigor-key "$(printf "x: 1\nrigor-floor: double \r\n")"; printf "%s" "$ALIAS_VALUE"' _ "$ALIAS_SH" 2> "$TMPROOT/al.err")|$(deps_in "$(al_err)")"

# ============================================================
section "§ALIAS-VERB: regression-run, regression-command: and proof-add regression work silently; floor-run, floor: and proof-add floor work with one deprecated: line each"
# ============================================================
# FIXTURE FIDELITY: session-poker-4 §FLOOR-DECLARED's shape. A plan bound to this session, its working branch checked
# out in a linked worktree one commit ahead, no tests/ directory at the head, and a declared command that is a stub
# script printing a runner's verdict. Each run is the real verb, each proof the real proof-add.
AV_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
RAV="$(make_repo rename-verbs)"; ( cd "$RAV" && git commit -q --allow-empty -m init )
PAV="$(s42_plan "$RAV" 4)"
awk '{ print } /^current: / && !d { print "working-branch: wave/01-fixture"; d = 1 }' "$PAV" > "$PAV.tmp" && mv "$PAV.tmp" "$PAV"
( cd "$RAV" && git add -f "$PAV" && git commit -qm wb \
  && git worktree add -q -b wave/01-fixture "$RAV/.worktrees/01-fixture" \
  && git -C "$RAV/.worktrees/01-fixture" commit -q --allow-empty -m "wave work" ) >/dev/null 2>&1
AV_W="$(git -C "$RAV/.worktrees/01-fixture" rev-parse HEAD 2>/dev/null)"
AV_REC="$RAV/.bionic/docs/record/wave-01-fixture"; mkdir -p "$AV_REC"
AV_STUB="$TMPROOT/av-regression.sh"
printf '#!/bin/bash\necho "Gating: 4 passed, 0 failed"\nexit 0\n' > "$AV_STUB"
expect_regex "AV-0 precondition: the working head is a 40-hex commit" '^[0-9a-f]{40}$' "$AV_W"

printf 'regression-command: bash %s\n' "$AV_STUB" > "$RAV/.bionic/config.yaml"
poke "$RAV" regression-run
expect_eq "AV-1 regression-run runs the declared regression-command: (exit 0)" "0" "$RC"
expect_true "AV-1b …and writes its log as regression-run-<head>.log" test -f "$AV_REC/regression-run-$AV_W.log"
expect_contains "AV-1c …which the verb names on its proof-add regression line" \
  "proof-add regression record/wave-01-fixture/regression-run-$AV_W.log" "$OUT"
expect_eq "AV-1d …and no deprecated: line is printed" "0" "$(deps_in "$OUT")"
poke "$RAV" proof-add regression "record/wave-01-fixture/regression-run-$AV_W.log"
expect_eq "AV-2 proof-add regression accepts that log (exit 0)" "0" "$RC"
expect_regex "AV-2b …and writes a kind=regression line at the working head" \
  "^proved: kind=regression head=${AV_W} .*evidence=record/wave-01-fixture/regression-run-${AV_W}\.log " \
  "$(/usr/bin/grep '^proved: ' "$PAV" | tail -n 1)"
expect_eq "AV-2c …and no deprecated: line is printed" "0" "$(deps_in "$OUT")"

printf 'floor: bash %s\n' "$AV_STUB" > "$RAV/.bionic/config.yaml"
poke "$RAV" floor-run
expect_eq "AV-3 floor-run, with the old floor: key, runs the declared command all the same (exit 0)" "0" "$RC"
expect_true "AV-3b …and writes the NEW name, regression-run-<head>-2.log" test -f "$AV_REC/regression-run-$AV_W-2.log"
expect_false "AV-3c …never the old one" test -e "$AV_REC/floor-run-$AV_W.log"
expect_eq "AV-3d …printing exactly two deprecated: lines, one for the verb and one for the key" "2" "$(deps_in "$OUT")"
expect_contains "AV-3e …the verb's" "deprecated: floor-run is regression-run$DEP_TAIL" "$OUT"
expect_contains "AV-3f …and the key's" "deprecated: floor: is regression-command:$DEP_TAIL" "$OUT"
poke "$RAV" proof-add floor "record/wave-01-fixture/regression-run-$AV_W-2.log"
expect_eq "AV-4 proof-add floor works (exit 0)" "0" "$RC"
expect_regex "AV-4b …and writes kind=regression, the new spelling" \
  "^proved: kind=regression head=${AV_W} .*evidence=record/wave-01-fixture/regression-run-${AV_W}-2\.log " \
  "$(/usr/bin/grep '^proved: ' "$PAV" | tail -n 1)"
expect_eq "AV-4c …printing the one deprecated: line, proof-add floor is proof-add regression" \
  "1|deprecated: proof-add floor is proof-add regression$DEP_TAIL" \
  "$(deps_in "$OUT")|$(printf '%s\n' "$OUT" | /usr/bin/grep '^deprecated: ')"
expect_eq "AV-4d no proof line spells kind=floor after either verb" "0" "$(/usr/bin/grep -c 'kind=floor' "$PAV" | tr -d ' ')"
expect_eq "AV-4e …beside the two kind=regression lines the verbs wrote" "2" "$(/usr/bin/grep -c '^proved: kind=regression ' "$PAV" | tr -d ' ')"
POKE_BOUND="$AV_BOUND_WAS"

# ============================================================
section "§ALIAS-BORN: --born regression:<suite> works silently; --born floor:<suite> works with one deprecated: line; both write born: regression … of=regression"
# ============================================================
# FIXTURE FIDELITY: session-poker-3 §BORN-FLOOR's shape. The plan carries a 1.20.0 proof line, kind=floor with
# owed=a.test.sh,b.test.sh, written by the library's own proof_add_line: the on-disk old spelling backs both markers.
AB_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
RAB="$(make_repo rename-born)"; ( cd "$RAB" && git commit -q --allow-empty -m init )
AB_C1="$(git -C "$RAB" rev-parse HEAD)"
git -C "$RAB" branch wave/01-fixture
PAB="$(s42_plan "$RAB" 4 "  worktree: .worktrees/01-fixture
  base-sha: abc1234
  branch: wave/01-fixture
  working-branch: wave/01-fixture")"
bash -c '. "$1" && proof_add_line "$2" "$3"' _ "$S46_LIB" "$PAB" \
  "proved: kind=floor head=${AB_C1} at=2026-10-14T00:00:00Z evidence=record/wave-01-fixture/floor.txt owed=a.test.sh,b.test.sh" > "$PAB.new" && mv "$PAB.new" "$PAB"
( cd "$RAB" && git add -f "$PAB" && git commit -qm floor ) >/dev/null 2>&1
poke "$RAB" task-add T6 4 build 'fix the red' bionic:implementor '—' 30 REQ-5 'lib/c.sh' --born regression:a.test.sh
expect_eq "AB-1 task-add --born regression:a.test.sh, which the 1.20.0 proof line owes, exits 0" "0" "$RC"
expect_regex "AB-1b …the row's line ends born: regression a.test.sh of=regression" \
  '^- T6: pending dispatch — added by task-add at [0-9T:Z-]+ born: regression a\.test\.sh of=regression$' "$(/usr/bin/grep '^- T6:' "$PAB")"
expect_contains "AB-1c …the task cell says born: regression" "| T6 | 4 | build | fix the red · born: regression |" "$(cat "$PAB")"
expect_eq "AB-1d …and no deprecated: line is printed" "0" "$(deps_in "$OUT")"
poke "$RAB" task-add T7 4 build 'fix the other red' bionic:implementor '—' 30 REQ-5 'lib/d.sh' --born floor:b.test.sh
expect_eq "AB-2 task-add --born floor:b.test.sh works (exit 0)" "0" "$RC"
expect_regex "AB-2b …and writes the new marker, born: regression b.test.sh of=regression" \
  '^- T7: pending dispatch — added by task-add at [0-9T:Z-]+ born: regression b\.test\.sh of=regression$' "$(/usr/bin/grep '^- T7:' "$PAB")"
expect_eq "AB-2c …printing the one deprecated: line" "1|deprecated: --born floor: is --born regression:$DEP_TAIL" \
  "$(deps_in "$OUT")|$(printf '%s\n' "$OUT" | /usr/bin/grep '^deprecated: ')"
POKE_BOUND="$AB_BOUND_WAS"

# ============================================================
section "§ALIAS-PLAN: a plan 1.20.0 wrote (kind=floor, proof:floor, born: floor … of=floor) judges as its renamed twin does, silently"
# ============================================================
# The two plans differ only by the old and new spellings of the on-disk tokens. Every reader is the library's own,
# sourced as a hook sources it: proof_last and the owed field, the absent judge, the born-marker reader, the units
# validator and the readiness program (units_ready, units_waiting, units_edges).
AP_DIR="$TMPROOT/ap"; mkdir -p "$AP_DIR"
AP_H="0123456789abcdef0123456789abcdef01234567"
ap_plan() {  # <proof kind> <reads token> <born word> <of word> -> a plan on stdout
  printf -- '---\ngoverning-skill: superpowers:writing-plans\nparallel-budget: writers=8 suites=2 worktrees=8 test_jobs=8 source=user\n---\n\n'
  printf '# fixture plan\n\n## SDLC State\n\ncurrent: 7\n%s\n\n- Step 4: in progress\n' "$SP_APPROVED_LINE"
  printf -- '- T3: landed at record/T3.md born: %s a.test.sh of=%s\n' "$3" "$4"
  printf 'proved: kind=%s head=%s at=2026-10-14T00:00:00Z evidence=record/w/r.log owed=a.test.sh\n\n' "$1" "$AP_H"
  printf '## Tasks\n\n| id | step | kind | task | agent | deps | size | serves | Files | status | reads |\n'
  printf '|---|---|---|---|---|---|---|---|---|---|---|\n'
  printf '| T3 | 6 | build | the fix | implementor | — | 30 | REQ-1 | a.sh | landed | — |\n'
  printf '| T4 | 7 | doc | the release | implementor | — | 30 | REQ-1 | b.md | pending | %s, approval:release |\n' "$2"
  printf '| T5 | 7 | review | the live read | critic | — | 30 | REQ-1 | .bionic/docs/record/w/r2.md | pending | live:%s |\n' "$2"
  printf '| T6 | 8 | integrate | the merge | implementor | — | 30 | REQ-1 | — | pending | — |\n'
}
ap_plan floor proof:floor floor floor > "$AP_DIR/old.plan.md"
ap_plan regression proof:regression regression regression > "$AP_DIR/new.plan.md"
ap() {  # <plan> <function> [args] -> the library's answer, roots, run, units (and through it proof, alias) sourced
  bash -c '. "$1/roots.sh"; . "$1/run.sh"; . "$1/units.sh"; p="$2"; fn="$3"; shift 3; "$fn" "$p" "$@"' _ "$LIB" "$1" "${@:2}" 2>> "$TMPROOT/ap.err"
}
ap_both() {  # <label> <function...> -> the old plan's answer equals the new plan's, and both are non-empty
  local o n; o="$(ap "$AP_DIR/old.plan.md" "${@:2}")"; n="$(ap "$AP_DIR/new.plan.md" "${@:2}")"
  expect_nonempty "$1 — the renamed plan answers" "$n"
  expect_eq "$1 — the 1.20.0 plan answers as its renamed twin" "$n" "$o"
}
: > "$TMPROOT/ap.err"
expect_eq "AP-0 the new plan's last regression proof is its head (the reader's positive)" "$AP_H" \
  "$(bash -c '. "$1/proof.sh"; proof_last "$2" regression' _ "$LIB" "$AP_DIR/new.plan.md" 2>/dev/null)"
expect_eq "AP-1 the 1.20.0 plan's kind=floor line is the last regression proof too" "$AP_H" \
  "$(bash -c '. "$1/proof.sh"; proof_last "$2" regression' _ "$LIB" "$AP_DIR/old.plan.md" 2>/dev/null)"
expect_eq "AP-2 …and its owed= field reads a.test.sh" "a.test.sh" \
  "$(bash -c '. "$1/proof.sh"; _proof_last_read "$2" regression owed' _ "$LIB" "$AP_DIR/old.plan.md" 2>/dev/null)"
expect_eq "AP-3 …and the absent judge finds a regression line (exit 1, nothing printed)" "1|" \
  "$(o="$(bash -c '. "$1/proof.sh"; proof_floor_absent "$2"' _ "$LIB" "$AP_DIR/old.plan.md" 2>/dev/null)"; printf '%s|%s' "$?" "$o")"
expect_eq "AP-4 the born-marker reader reads the 1.20.0 marker as a regression-born row" "$(printf 'T3\tregression\ta.test.sh')" \
  "$(ap "$AP_DIR/old.plan.md" units_born_marks)"
ap_both "AP-5 units_born_marks" units_born_marks
expect_eq "AP-6 the units validator passes the renamed plan (no violation)" "" "$(ap "$AP_DIR/new.plan.md" units_validate)"
expect_eq "AP-6b …and passes the 1.20.0 plan, proof:floor in its reads, the same" "" "$(ap "$AP_DIR/old.plan.md" units_validate)"
expect_eq "AP-6c a reads token the validator does not know is still refused (the validator's positive)" "1" \
  "$(sed 's/live:proof:floor/live:proof:flour/' "$AP_DIR/old.plan.md" > "$AP_DIR/bad.plan.md"; ap "$AP_DIR/bad.plan.md" units_validate | /usr/bin/grep -c 'T5: read' | tr -d ' ')"
ap_both "AP-7 units_waiting at step 7" units_waiting 7
expect_contains "AP-7b …and the 1.20.0 plan's T4 waits on approval:release, its regression read met" \
  "$(printf 'T4\tapproval:release')" "$(ap "$AP_DIR/old.plan.md" units_waiting 7)"
ap_both "AP-8 units_edges" units_edges
expect_eq "AP-9 none of these readers printed a deprecated: line for the on-disk tokens" "0" "$(deps_in "$(cat "$TMPROOT/ap.err")")"

# ============================================================
section "§AGREE-SEAM: each typed token is read at its one seam, through the map"
# ============================================================
SP_SH="$POKER"; PROOF_SH="$LIB/proof.sh"; UNITS_SH="$LIB/units.sh"
code_lines() { /usr/bin/grep -v -E '^[[:space:]]*#' "$1"; }   # <file> -> its lines that are not comments
expect_eq "AG-1 the verb is normalised once, on the line after VERB is read, before both case blocks" "1|1" \
  "$(code_lines "$SP_SH" | /usr/bin/grep -c 'alias_read verb "\$VERB"' | tr -d ' ')|$(awk '/^VERB="\$1"; shift$/ { getline; print ($0 ~ /alias_read verb "\$VERB"/) ? 1 : 0; exit }' "$SP_SH")"
expect_eq "AG-2 each case block holds one regression-run) arm, and no block a floor-run) arm" "2|0" \
  "$(code_lines "$SP_SH" | /usr/bin/grep -c -E '^[[:space:]]+regression-run\)' | tr -d ' ')|$(code_lines "$SP_SH" | /usr/bin/grep -c -E '^[[:space:]]+floor-run\)' | tr -d ' ')"
expect_eq "AG-3 the proof kind is normalised once, where PF_KIND is read" "1" \
  "$(code_lines "$SP_SH" | /usr/bin/grep -c 'alias_read proof-kind "\$PF_KIND"' | tr -d ' ')"
expect_eq "AG-4 the born operand is normalised once, in task-add's --born parse" "1" \
  "$(code_lines "$SP_SH" | /usr/bin/grep -c 'alias_read born-operand' | tr -d ' ')"
expect_eq "AG-5 the regression's command is read once, through alias_config" "1" \
  "$(code_lines "$SP_SH" | /usr/bin/grep -c 'alias_config "\$FR_ROOT" config' | tr -d ' ')"
expect_eq "AG-6 the second-run glob walks every spelling of the log name" "1" \
  "$(code_lines "$SP_SH" | /usr/bin/grep -c 'alias_spellings log' | tr -d ' ')"
expect_eq "AG-7 proof_fields normalises the kind through the map, written once at load and pasted once" "1|1" \
  "$(code_lines "$PROOF_SH" | /usr/bin/grep -c '_PROOF_KIND_NORM="$(_proof_alias_norm kind PROOF_KIND)"' | tr -d ' ')|$(code_lines "$PROOF_SH" | /usr/bin/grep -c -F '"$_PROOF_KIND_NORM"' | tr -d ' ')"
expect_eq "AG-8 the reads token is normalised through the map at the tokenizer and at the validator" "2" \
  "$(code_lines "$UNITS_SH" | /usr/bin/grep -c -F '"$_UNITS_READS_NORM"' | tr -d ' ')"
expect_eq "AG-9 both born-marker readers take their spellings from the map" "1|1" \
  "$(code_lines "$UNITS_SH" | /usr/bin/grep -c -F '$(_proof_alias_born)' | tr -d ' ')|$(code_lines "$PROOF_SH" | /usr/bin/grep -c -F '$(_proof_alias_born)' | tr -d ' ')"
expect_eq "AG-10 the governing-skill hook reads the rigor minimum through the map, at its two readers" "2" \
  "$(code_lines "$GOV_HOOK" | /usr/bin/grep -c 'alias_keyed rigor-key' | tr -d ' ')"

# ============================================================
section "§AGREE-ONE: the alias and the new name reach one implementation"
# ============================================================
# THE VERB AND THE KIND: the same refusal, word for word, from the old and the new spelling; the old adds one line.
RAG="$(make_repo rename-agree)"
ag_same() {  # <label> <new args> -- <old args>
  local label="$1" n o; shift
  local -a na=() oa=()
  while [ "$1" != -- ]; do na+=("$1"); shift; done; shift; oa=("$@")
  poke "$RAG" "${na[@]}"; n="$RC|$OUT"
  poke "$RAG" "${oa[@]}"; o="$RC|$(printf '%s\n' "$OUT" | /usr/bin/grep -v '^deprecated: ')"
  expect_nonempty "$label — the new spelling answers" "${n#*|}"
  expect_eq "$label — the old spelling answers the same, less its deprecated: line" "$n" "$o"
  expect_eq "$label — …which it printed once" "1" "$(deps_in "$OUT")"
}
ag_same "AO-1 regression-run x / floor-run x (the usage error)" regression-run x -- floor-run x
ag_same "AO-2 proof-add regression / proof-add floor with a flag that takes no value (the usage error)" proof-add regression record/x.log --reader -- proof-add floor record/x.log --reader
# THE PROOF LINE: proof_fields, lifted from proof_awk, reads the old and new line as one kind.
ag_kind() { printf '%s\n' "$1" | awk "$(bash -c '. "$1"; proof_awk' _ "$PROOF_SH")"'{ if (proof_fields($0)) print PROOF_KIND }'; }
expect_eq "AO-3 proof_fields reads kind=regression as regression" "regression" "$(ag_kind "proved: kind=regression head=$AP_H at=x evidence=e")"
expect_eq "AO-3b …and kind=floor as regression" "regression" "$(ag_kind "proved: kind=floor head=$AP_H at=x evidence=e")"
expect_eq "AO-3c …and every other kind as itself" "review" "$(ag_kind "proved: kind=review head=$AP_H at=x evidence=e")"
# THE CONFIG KEY: one reader, alias_config, answers both keys with one value.
printf 'floor: bash x.sh\n' > "$AM_CFG/.bionic/config.yaml"
AO_OLD="$(bash -c '. "$1/roots.sh"; . "$1/alias.sh"; alias_config "$2" config ""; printf "%s" "$ALIAS_VALUE"' _ "$LIB" "$AM_CFG" 2>/dev/null)"
printf 'regression-command: bash x.sh\n' > "$AM_CFG/.bionic/config.yaml"
AO_NEW="$(bash -c '. "$1/roots.sh"; . "$1/alias.sh"; alias_config "$2" config ""; printf "%s" "$ALIAS_VALUE"' _ "$LIB" "$AM_CFG" 2>/dev/null)"
expect_eq "AO-4 alias_config answers floor: and regression-command: with one value" "bash x.sh|bash x.sh" "$AO_OLD|$AO_NEW"
# THE AWK NORMALISATION: alias_awk_norm emits the statements every awk reader runs, from the one map.
ag_norm() { awk "BEGIN { t = \"$2\"; $(bash -c '. "$1"; alias_awk_norm "$2" t' _ "$ALIAS_SH" "$1") print t }"; }
expect_eq "AO-5 alias_awk_norm reads turns proof:floor and live:proof:floor into the new token" \
  "proof:regression|live:proof:regression|proof:review" \
  "$(ag_norm reads proof:floor)|$(ag_norm reads live:proof:floor)|$(ag_norm reads proof:review)"
expect_eq "AO-6 alias_awk_norm kind and born answer as alias_token does" "regression|regression|$(al alias_token kind floor)|$(al alias_token born floor)" \
  "$(ag_norm kind floor)|$(ag_norm born floor)|regression|regression"

# ============================================================
section "§AGREE-SCAN: no production line outside alias.sh spells an old token; a planted second copy goes red"
# ============================================================
# The patterns name the old spellings as a reader or writer would carry them: the verb, the typed kind, the config
# key read by name, a proof line's field, a reads token, the born marker and its operand and backing, the log
# prefix, the rigor key and the governing hook's finding ids, a comparison against the bare word or a case arm on
# it. Comments are not read. tests/fixtures and doctrine are not production code.
SCAN_ERE='floor-run|proof-add floor|kind=floor|proof:floor|born: floor|born floor:|of=floor|rigor-floor|(intent|project|epic)-floor|born-floor|second-floors|"floor"|= floor( |\]|;|$)|^[[:space:]]*floor\)|\|floor\)|config_value [^)]* floor '
scan() {  # <file>... -> the lines spelling an old token, `<file>:<line>`
  local f
  for f in "$@"; do
    awk -v f="${f##*/}" '/^[[:space:]]*#/ { next } { print f ":" FNR ":" $0 }' "$f"
  done | /usr/bin/grep -E "$SCAN_ERE" | /usr/bin/grep -v -E '^alias\.sh:'
}
SCAN_FILES=()
for f in "${BIONIC_HOOKS_DIR}"/*.sh "${BIONIC_SCRIPTS_DIR}"/payload/scripts/*.sh "$LIB"/*.sh; do [ -f "$f" ] && SCAN_FILES+=("$f"); done
expect_nonempty "AS-0 the scan has files to read (the scanner's positive)" "${SCAN_FILES[*]}"
AS_HITS="$(scan "${SCAN_FILES[@]}")"
expect_eq "AS-1 no production code line spells an old token (hits: $(printf '%s' "$AS_HITS" | head -c 400))" "0" \
  "$(printf '%s' "$AS_HITS" | /usr/bin/grep -c . | tr -d ' ')"
AS_MUT="$TMPROOT/as-mut"; mkdir -p "$AS_MUT"
cp "$SP_SH" "$AS_MUT/session-poker.sh"; cp "$PROOF_SH" "$AS_MUT/proof.sh"
anchor -E "$AS_MUT/session-poker.sh" '^  regression-run\)$' 2
awk '/^  regression-run\)$/ && !d { print "  floor-run) : ;;"; d = 1 } { print }' "$AS_MUT/session-poker.sh" > "$AS_MUT/sp.tmp" && mv "$AS_MUT/sp.tmp" "$AS_MUT/session-poker.sh"
expect_true "AS-2 precondition: the planted poker still parses" bash -n "$AS_MUT/session-poker.sh"
expect_eq "AS-2b a planted floor-run) arm, a second copy of the verb, is found" "1" "$(scan "$AS_MUT/session-poker.sh" | /usr/bin/grep -c . | tr -d ' ')"
anchor "$AS_MUT/proof.sh" 'PROOF_KIND == "regression" || PROOF_KIND == "task"' 1
sed 's/PROOF_KIND == "regression" || PROOF_KIND == "task"/PROOF_KIND == "floor" || PROOF_KIND == "regression" || PROOF_KIND == "task"/' "$AS_MUT/proof.sh" > "$AS_MUT/p.tmp" && mv "$AS_MUT/p.tmp" "$AS_MUT/proof.sh"
expect_true "AS-3 precondition: the planted proof library still parses" bash -n "$AS_MUT/proof.sh"
expect_eq "AS-3b a planted PROOF_KIND == \"floor\", a second reading of the kind, is found" "1" "$(scan "$AS_MUT/proof.sh" | /usr/bin/grep -c . | tr -d ' ')"


# ============================================================
section "§ALLOWLIST: the AC-9.3 grep over the tree under test prints nothing; a planted prose floor line is printed"
# ============================================================
# wave-38 T9 (REQ-9 AC-9.3, D6; spec §Eval design row 223). The grep runs EXACTLY as the eval row spells it, from the
# root of the tree under test. tests/fixtures/floor-allowlist.txt holds grep -v -f patterns only, of two shapes: a
# pattern anchored with ^ admits a whole class of line (lib/alias.sh's ALIAS_MAP arms; a shell comment, code-internal
# under D6), and every other pattern names one code-internal identifier. An empty line there would admit every
# line, so the file is checked first; each pattern must admit a line the raw grep prints, so none is dead.
# The eval's grep admits a whole line for one identifier on it, so a prose "floor" beside an identifier would pass it.
# AL-2c closes that: outside the class lines it deletes each identifier and finds no "floor" left.
AL_ROOT="$BIONIC_SCRIPTS_DIR"
AL_FILE="$AL_ROOT/tests/fixtures/floor-allowlist.txt"
al_grep() {  # <root> -> the AC-9.3 grep's output at that root, verbatim; rc is the pipeline's (1: no line printed)
  ( cd "$1" || exit 9; /usr/bin/grep -rni floor hooks/ payload/scripts payload/commands skills/ agents/ agents-src/ | grep -v -f tests/fixtures/floor-allowlist.txt )
}
al_raw() { ( cd "$1" || exit 9; /usr/bin/grep -rni floor hooks/ payload/scripts payload/commands skills/ agents/ agents-src/ ); }
al_left() {  # <root> -> each raw line outside the class patterns that still spells floor once every identifier is deleted
  /usr/bin/grep '^\^' "$AL_FILE" > "$TMPROOT/al-class"
  /usr/bin/grep -v '^\^' "$AL_FILE" | awk '{ print "s/" $0 "//g" }' > "$TMPROOT/al-strip.sed"
  al_raw "$1" | /usr/bin/grep -v -f "$TMPROOT/al-class" | sed -f "$TMPROOT/al-strip.sed" \
    | awk '{ c = $0; sub(/^[^:]*:[0-9]*:/, "", c); if (tolower(c) ~ /floor/) print }'
}
expect_true "AL-0 the allowlist exists and is not empty" test -s "$AL_FILE"
expect_eq "AL-0b …and holds patterns only: no empty line, no comment line" "0" \
  "$(/usr/bin/grep -c -E '^[[:space:]]*$|^#' "$AL_FILE" 2>/dev/null | tr -d ' ')"
expect_eq "AL-0c …and no identifier pattern carries a / (the strip's delimiter)" "0" \
  "$(/usr/bin/grep -v '^\^' "$AL_FILE" | /usr/bin/grep -c / | tr -d ' ')"
AL_RAW="$(al_raw "$AL_ROOT")"
expect_nonempty "AL-1 the raw grep reads lines at this tree (the grep's positive)" "$AL_RAW"
AL_DEAD=""
while IFS= read -r al_pat; do
  [ -n "$al_pat" ] || continue
  [ "$(printf '%s\n' "$AL_RAW" | grep -c -e "$al_pat")" -gt 0 ] || AL_DEAD="$AL_DEAD [$al_pat]"
done < "$AL_FILE"
expect_eq "AL-1b every pattern admits a line the raw grep prints (dead:$AL_DEAD)" "" "$AL_DEAD"
AL_OUT="$(al_grep "$AL_ROOT")"; AL_RC=$?
expect_eq "AL-2 the AC-9.3 grep prints nothing at this tree (printed: $(printf '%s' "$AL_OUT" | head -c 600))" "0" \
  "$(printf '%s' "$AL_OUT" | /usr/bin/grep -c . | tr -d ' ')"
expect_eq "AL-2b …and grep -v read the allowlist (rc 1, no line selected; 2 is an unread file)" "1" "$AL_RC"
AL_LEFT="$(al_left "$AL_ROOT")"
expect_eq "AL-2c no prose floor sits beside an identifier (left: $(printf '%s' "$AL_LEFT" | head -c 600))" "0" \
  "$(printf '%s' "$AL_LEFT" | /usr/bin/grep -c . | tr -d ' ')"
# The power: a scratch copy of the six trees and the allowlist with four prose lines planted. The eval's grep prints
# the three that carry no identifier; AL-2c's reading prints all four.
AL_MUT="$TMPROOT/al-tree"; mkdir -p "$AL_MUT/payload" "$AL_MUT/tests/fixtures"
cp -R "$AL_ROOT/hooks" "$AL_ROOT/skills" "$AL_ROOT/agents" "$AL_ROOT/agents-src" "$AL_MUT/"
cp -R "$AL_ROOT/payload/scripts" "$AL_ROOT/payload/commands" "$AL_MUT/payload/"
cp "$AL_FILE" "$AL_MUT/tests/fixtures/"
expect_eq "AL-3 precondition: the copy prints what the tree prints" "$AL_OUT" "$(al_grep "$AL_MUT")"
printf '\nThe floor is one whole run plus the greens after it.\n' >> "$AL_MUT/skills/canonical-sdlc/SKILL.md"
printf '%s\n' '  die "REFUSED — the floor is owed at the head"' '  say "the floor holds"  # planted beside a comment' \
  '  log_floor_finding project-minimum "project floor single"' '  echo "the floor is printed by echo"' \
  '# a planted comment: the floor stays code-internal' >> "$AL_MUT/hooks/session-poker.sh"
expect_true "AL-3b precondition: the planted poker still parses" bash -n "$AL_MUT/hooks/session-poker.sh"
AL_MOUT="$(al_grep "$AL_MUT")"
AL_MLEFT="$(al_left "$AL_MUT")"
expect_eq "AL-4 the grep prints the four planted prose lines with no identifier beyond what the tree prints" "4" \
  "$(( $(printf '%s' "$AL_MOUT" | /usr/bin/grep -c . | tr -d ' ') - $(printf '%s' "$AL_OUT" | /usr/bin/grep -c . | tr -d ' ') ))"
expect_contains "AL-4b …the doctrine sentence" "SKILL.md:$(( $(wc -l < "$AL_ROOT/skills/canonical-sdlc/SKILL.md") + 2 )):The floor is one whole run" "$AL_MOUT"
expect_contains "AL-4c …the refusal" 'die "REFUSED — the floor is owed at the head"' "$AL_MOUT"
expect_contains "AL-4d …and the printed line a trailing comment does not admit" 'say "the floor holds"' "$AL_MOUT"
expect_contains "AL-4e …the echo" 'echo "the floor is printed by echo"' "$AL_MOUT"
expect_contains "AL-4f the planted comment is read by the raw grep (the positive)" 'a planted comment: the floor' "$(al_raw "$AL_MUT")"
expect_absent "AL-4g …and the comment class admits it: the grep does not print it" 'a planted comment: the floor' "$AL_MOUT"
expect_eq "AL-5 AL-2c's reading prints all five planted prose lines beyond what the tree leaves" "5" \
  "$(( $(printf '%s' "$AL_MLEFT" | /usr/bin/grep -c . | tr -d ' ') - $(printf '%s' "$AL_LEFT" | /usr/bin/grep -c . | tr -d ' ') ))"
expect_contains "AL-5b …the prose beside log_floor_finding, which the eval's grep admits" 'project floor single' "$AL_MLEFT"
# THE COMMENT CLASS'S GUARD (A-orch-24, A-T9-4). The class admits a line by its shape, so a line that LOOKS like a
# comment but is printed would pass: one inside a heredoc body, or inside a double-quoted string an earlier line left
# open (the shape every die/say message here takes). al_guard walks each file holding an admitted comment line with
# a small quote and heredoc state machine and prints each admitted line that sits in either place. A single-quoted
# string left open is not reported: in this tree those are awk programs (lib/units.sh's scheduler, printed by
# printf '%s' and run by awk), whose comments are code.
AL_GUARD_AWK=''
read -r -d '' AL_GUARD_AWK <<'AWK' || true
FNR == NR { if ($1 == f) W[$2] = 1; next }
term != "" {
  t = $0; if (strip) sub(/^\t+/, "", t)
  if (t == term) { term = ""; next }
  if (FNR in W) print f ":" FNR ": in a heredoc body (" term ")"
  next
}
{
  if (q == "\"" && (FNR in W)) print f ":" FNR ": in an open double-quoted string"
  line = $0; n = length(line); opener = ""
  for (i = 1; i <= n; i++) {
    c = substr(line, i, 1)
    if (q == "\047") { if (c == "\047") q = ""; continue }
    if (q == "\"") { if (c == "\\") { i++; continue } if (c == "\"") q = ""; continue }
    if (c == "\\") { i++; continue }
    if (c == "#" && (i == 1 || substr(line, i - 1, 1) ~ /[ \t;(|&]/)) break
    if (c == "\047" || c == "\"") { q = c; continue }
    if (substr(line, i, 2) == "<<" && substr(line, i, 3) != "<<<") {
      h = substr(line, i + 2); st = (h ~ /^-/); sub(/^-/, "", h); sub(/^[ ]*/, "", h); gsub(/["\047\\]/, "", h)
      if (match(h, /^[A-Za-z_][A-Za-z_0-9]*/)) { opener = substr(h, 1, RLENGTH); ostrip = st }
      i++
    }
  }
  if (opener != "") { term = opener; strip = ostrip }
}
AWK
al_guard() {  # <root> -> each admitted comment line inside a heredoc body or an open double-quoted string
  /usr/bin/grep '^\^' "$AL_FILE" | /usr/bin/grep -v 'alias' > "$TMPROOT/al-cmt"
  ( cd "$1" || exit 9
    al_raw . | /usr/bin/grep -f "$TMPROOT/al-cmt" | awk -F: '{ print $1 "\t" $2 }' > "$TMPROOT/al-adm.tsv"
    cut -f1 "$TMPROOT/al-adm.tsv" | sort -u | while IFS= read -r al_f; do
      awk -F'\t' -v f="$al_f" "$AL_GUARD_AWK" "$TMPROOT/al-adm.tsv" "$al_f"
    done )
}
AL_GUARD="$(al_guard "$AL_ROOT")"
expect_nonempty "AL-6 the guard walks the comment lines the class admits (the reader's positive)" "$(cat "$TMPROOT/al-adm.tsv" 2>/dev/null)"
expect_eq "AL-6b no admitted comment line sits in a heredoc body or an open double-quoted string (found: $(printf '%s' "$AL_GUARD" | head -c 400))" \
  "0" "$(printf '%s' "$AL_GUARD" | /usr/bin/grep -c . | tr -d ' ')"
printf '%s\n' 'cat <<EOF' '# the floor, printed by a heredoc' 'EOF' '  say "a printed message' '# the floor, inside the printed string"' \
  >> "$AL_MUT/hooks/session-poker.sh"
expect_true "AL-6c precondition: the guard's plants still parse" bash -n "$AL_MUT/hooks/session-poker.sh"
AL_MGUARD="$(al_guard "$AL_MUT")"
expect_eq "AL-6d the guard finds both planted lines in the copy" "2" "$(printf '%s' "$AL_MGUARD" | /usr/bin/grep -c . | tr -d ' ')"
expect_contains "AL-6e …the heredoc's" "in a heredoc body (EOF)" "$AL_MGUARD"
expect_contains "AL-6f …and the open string's" "in an open double-quoted string" "$AL_MGUARD"

finish
