#!/bin/bash
# THE REGRESSION'S OLD SPELLINGS: THE PLAN-READ ROWS STAY, THE TYPED AND CONFIG ROWS ARE GONE (epic-23 wave-38 T8,
# REQ-9; wave-39 T18, REQ-13 AC-13.1, D2).
#
# WHAT THIS SUITE OWNS. payload/scripts/lib/alias.sh and the seam each old spelling is met at. Until 1.21.0 the full
# regression's verbs, keys and record tokens spelled "floor"; wave-38 renamed them and kept each old spelling for one
# release. 1.22.0 removes the half a person types or a config carries (D2: writers drop the old word, readers keep it,
# and what is no longer read is REFUSED naming the new spelling, never accepted silently):
#
#     floor-run                 -> regression-run             the verb, read at `VERB="$1"` in hooks/session-poker.sh
#     proof-add floor           -> proof-add regression       the proof kind, read at `PF_KIND="$1"`
#     --born floor:<suite>      -> --born regression:<suite>  task-add's operand
#     proof:floor (typed)       -> proof:regression           a reads cell given to task-add or task-set reads=
#     floor: (config.yaml)      -> regression-command:        the regression's command, read by `regression-run`
#     floor-run-<sha>.log       -> regression-run-<sha>.log   the whole-run log's name: the old one is not read, not refused
#     rigor-floor:              -> rigor-minimum:             the rigor minimum, read by hooks/canonical-sdlc-governing-skill.sh
#
# What a 1.20.0 TOOL wrote into a plan is read as it always was, silently (D-w39-2; A-T8-1): a proof line's kind=floor,
# a reads cell's proof:floor, a born marker's `born: floor … of=floor`. A plan is a record, and a rename never
# invalidates a record already written.
#
# §ALIAS-MAP: the map's four plan-read rows answer the old and the new spelling with one answer, silently.
# §GONE: each typed or config spelling is refused with a line naming the new one, through the library and through the
#   real verb, and the new spelling beside each still works. (The rigor-floor: key is also pinned end to end in
#   tests/canonical-sdlc-governing-skill.test.sh §MINIMUM.)
# §ALIAS-PLAN: a 1.20.0 plan (kind=floor, proof:floor, born: floor … of=floor) judges as its renamed twin does.
# §AGREE: the old and the new spelling of a plan token reach one implementation, each refusal is made at its one seam
#   through the map, and no production line outside alias.sh spells an old token (a planted second copy goes red).
#
# FIXTURE FIDELITY (the rule of that name). The verb fixtures are session-poker-4 §FLOOR-DECLARED's and §FLOOR-RUN's and
# session-poker-3 §BORN-FLOOR's shapes, built with the shards' own prelude; the 1.20.0 plan is SYNTHESIZED, its proof
# line, reads cells and born marker in the shapes 1.20.0's writers wrote (proof_floor_line, kdef, units_add_row's born
# operand).
# ANTI-VACUITY (the rule of that name). Every refusal sits beside the new spelling's success on the same fixture and
# the same reader: each log, proof line and row a refusal must not write is counted beside the one its new spelling
# wrote; each empty readback sits beside a positive; the scan sits beside a proof it read files and two planted copies
# it finds, each plant after a parse check of the mutant.
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


# al <function> <args...> -> stdout of one alias.sh function in a clean shell; stderr to $TMPROOT/al.err
al() {
  bash -c '. "$1" || exit 9; shift; "$@"' _ "$ALIAS_SH" "$@" 2> "$TMPROOT/al.err"
}
al_err() { cat "$TMPROOT/al.err" 2>/dev/null; }
# gone <function> <args...> -> `gone|<the refusal's sentence>` when the library refuses the spelling, `kept|` when it does not
gone() {
  bash -c '. "$1" || exit 9; fn="$2"; shift 2; if "$fn" "$@"; then printf "gone|%s" "$ALIAS_GONE_SAID"; else printf "kept|"; fi' _ "$ALIAS_SH" "$@" 2> "$TMPROOT/al.err"
}

# ============================================================
section "§ALIAS-MAP: alias_token answers the four plan-read rows, the new spelling and the old one alike, both silently"
# ============================================================
expect_true "AM-0 lib/alias.sh exists and passes bash -n" bash -n "$ALIAS_SH"
for am_pair in \
  "kind|floor|regression" \
  "reads|proof:floor|proof:regression" \
  "born|floor|regression" \
  "born-of|floor|regression"; do
  IFS='|' read -r am_k am_old am_new <<< "$am_pair"
  expect_eq "AM-$am_k-1 alias_token $am_k $am_new is $am_new" "$am_new" "$(al alias_token "$am_k" "$am_new")"
  expect_eq "AM-$am_k-1b …and says nothing on stderr" "" "$(al_err)"
  expect_eq "AM-$am_k-2 alias_token $am_k $am_old is $am_new" "$am_new" "$(al alias_token "$am_k" "$am_old")"
  expect_eq "AM-$am_k-2b …and says nothing on stderr either: a plan's old token is read silently, nobody is told to edit a record" "" "$(al_err)"
done
expect_eq "AM-3 a word the map does not carry is answered as itself" "review" "$(al alias_token kind review)"
expect_eq "AM-3b …a typed spelling is not in the map any more: the verb floor-run is answered as itself" "floor-run" "$(al alias_token verb floor-run)"
expect_eq "AM-3c …silently" "" "$(al_err)"
expect_eq "AM-5 alias_spellings born names the new spelling first, then the old (the born reader's alternation)" "regression floor" \
  "$(al alias_spellings born | paste -sd' ' -)"
expect_eq "AM-5b …and nothing for the verb, whose old spelling is gone" "" "$(al alias_spellings verb)"
expect_eq "AM-6 the removed readers are not defined: alias_cell, alias_config, alias_keyed, alias_spellings log" "0|0|0" \
  "$(bash -c '. "$1"; for f in alias_cell alias_config alias_keyed; do declare -F "$f" >/dev/null && c=$((c + 1)); done; printf "%s" "${c:-0}"' _ "$ALIAS_SH")|$(bash -c '. "$1"; alias_spellings log | grep -c .' _ "$ALIAS_SH" | tr -d ' ')|$(bash -c '. "$1"; declare -F alias_gone >/dev/null && echo 0' _ "$ALIAS_SH")"

# ============================================================
section "§GONE: the library refuses each typed and config spelling and names the new one; the new spelling is kept"
# ============================================================
# One row per typed spelling. The library answers `gone|<old as written> is gone; write <new as written>` for the old
# spelling and `kept|` for the new one beside it, so a refusal is never the answer to every word.
for go_row in \
  "alias_gone|verb|floor-run|regression-run|floor-run is gone; write regression-run" \
  "alias_gone|proof-kind|floor|regression|proof-add floor is gone; write proof-add regression" \
  "alias_gone|born-operand|floor:|regression:|--born floor: is gone; write --born regression:"; do
  IFS='|' read -r go_fn go_k go_old go_new go_say <<< "$go_row"
  expect_eq "GO-$go_k-1 $go_fn $go_k $go_old is refused, naming the new spelling" "gone|$go_say" "$(gone "$go_fn" "$go_k" "$go_old")"
  expect_eq "GO-$go_k-1b …$go_new beside it is kept" "kept|" "$(gone "$go_fn" "$go_k" "$go_new")"
  expect_eq "GO-$go_k-1c …a word of no row is kept" "kept|" "$(gone "$go_fn" "$go_k" review)"
done
expect_eq "GO-reads-1 a typed reads cell carrying proof:floor is refused, naming proof:regression" "gone|proof:floor is gone; write proof:regression" \
  "$(gone alias_gone_cell reads 'approval:plan, proof:floor, head')"
expect_eq "GO-reads-1b …the live: form too" "gone|proof:floor is gone; write proof:regression" "$(gone alias_gone_cell reads 'head, live:proof:floor')"
expect_eq "GO-reads-1c …and the cell of the new spelling is kept" "kept|" "$(gone alias_gone_cell reads 'approval:plan, proof:regression, live:proof:review, head')"
expect_eq "GO-reads-1d …and so is a cell with no tokens at all" "kept|" "$(gone alias_gone_cell reads '—')"
expect_eq "GO-config-1 a config text carrying the floor: key is refused, naming regression-command:" "gone|floor: is gone; write regression-command:" \
  "$(gone alias_gone_text config "$(printf 'poker-interval: 20m\nfloor: bash old.sh\n')")"
expect_eq "GO-config-1b …with the new key beside it too: the old key is still refused, never read past" "gone|floor: is gone; write regression-command:" \
  "$(gone alias_gone_text config "$(printf 'floor: bash old.sh\nregression-command: bash new.sh\n')")"
expect_eq "GO-config-1c …the new key alone is kept" "kept|" "$(gone alias_gone_text config 'regression-command: bash new.sh')"
expect_eq "GO-config-1d …and floor-attestation:, another key that begins with the word, is not this one" "kept|" "$(gone alias_gone_text config 'floor-attestation: yes')"
expect_eq "GO-rigor-1 a text carrying rigor-floor: is refused, naming rigor-minimum:" "gone|rigor-floor: is gone; write rigor-minimum:" \
  "$(gone alias_gone_text rigor-key "$(printf 'x: 1\nrigor-floor: double \r\n')")"
expect_eq "GO-rigor-1b …rigor-minimum: beside it is kept" "kept|" "$(gone alias_gone_text rigor-key "$(printf 'x: 1\nrigor-minimum: double\n')")"
expect_eq "GO-log-1 the log's old prefix is floor-run-, one name" "floor-run-" "$(al alias_gone_names log)"
expect_eq "GO-log-1b …and its refusal names the new log: floor-run-<sha>.log is gone; write regression-run-<sha>.log" \
  "gone|floor-run-<sha>.log is gone; write regression-run-<sha>.log" \
  "$(bash -c '. "$1"; alias_gone_say log && printf "gone|%s" "$ALIAS_GONE_SAID"' _ "$ALIAS_SH")"
expect_eq "GO-silent-1 the refusals say it once, in their sentence: nothing reaches stderr" "" "$(al_err)"

# ============================================================
section "§GONE-VERB: floor-run, floor: and proof-add floor are refused by the real verb, naming the new spelling; regression-run, regression-command: and proof-add regression beside each work"
# ============================================================
# FIXTURE FIDELITY: session-poker-4 §FLOOR-DECLARED's shape. A plan bound to this session, its working branch checked
# out in a linked worktree one commit ahead, no tests/ directory at the head, and a declared command that is a stub
# script printing a runner's verdict. Each run is the real verb, each proof the real proof-add.
AV_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
RAV="$(make_repo gone-verbs)"; ( cd "$RAV" && git commit -q --allow-empty -m init )
PAV="$(s42_plan "$RAV" 4)"
awk '{ print } /^current: / && !d { print "working-branch: wave/01-fixture"; d = 1 }' "$PAV" > "$PAV.tmp" && mv "$PAV.tmp" "$PAV"
( cd "$RAV" && git add -f "$PAV" && git commit -qm wb \
  && git worktree add -q -b wave/01-fixture "$RAV/.worktrees/01-fixture" \
  && git -C "$RAV/.worktrees/01-fixture" commit -q --allow-empty -m "wave work" ) >/dev/null 2>&1
AV_W="$(git -C "$RAV/.worktrees/01-fixture" rev-parse HEAD 2>/dev/null)"
AV_REC="$RAV/.bionic/docs/record/wave-01-fixture"; mkdir -p "$AV_REC"
AV_STUB="$TMPROOT/av-regression.sh"
printf '#!/bin/bash\necho "Gating: 4 passed, 0 failed"\nexit 0\n' > "$AV_STUB"
av_logs() { ls "$AV_REC"/regression-run-*.log "$AV_REC"/floor-run-*.log 2>/dev/null | awk 'END { print NR + 0 }'; }   # -> the run logs the record holds, by either name
av_proofs() { /usr/bin/grep -c '^proved: ' "$PAV" | tr -d ' '; }              # -> the proof lines the plan holds
expect_regex "GV-0 precondition: the working head is a 40-hex commit" '^[0-9a-f]{40}$' "$AV_W"

printf 'regression-command: bash %s\n' "$AV_STUB" > "$RAV/.bionic/config.yaml"
poke "$RAV" regression-run
expect_eq "GV-1 regression-run runs the declared regression-command: (exit 0)" "0" "$RC"
expect_true "GV-1b …and writes its log as regression-run-<head>.log" test -f "$AV_REC/regression-run-$AV_W.log"
expect_eq "GV-1c …and prints no word about a spelling" "0" "$(printf '%s\n' "$OUT" | /usr/bin/grep -c -e 'deprecated' -e ' is gone' | tr -d ' ')"
poke "$RAV" floor-run
expect_eq "GV-2 floor-run, on the same config, is refused (exit 1)" "1" "$RC"
expect_contains "GV-2b …the refusal names the new verb" "floor-run is gone; write regression-run" "$OUT"
expect_eq "GV-2c …and nothing ran: the one log of GV-1 is all the record holds" "1" "$(av_logs)"
poke "$RAV" proof-add floor "record/wave-01-fixture/regression-run-$AV_W.log"
expect_eq "GV-3 proof-add floor, citing the log GV-1 wrote, is refused (exit 1)" "1" "$RC"
poke "$RAV" proof-add regression "record/wave-01-fixture/regression-run-$AV_W.log"
expect_eq "GV-3d proof-add regression citing the same log works (exit 0)" "0" "$RC"

printf 'floor: bash %s\n' "$AV_STUB" > "$RAV/.bionic/config.yaml"
poke "$RAV" regression-run
expect_eq "GV-4 regression-run with only the old floor: key is refused (exit 1)" "1" "$RC"
expect_contains "GV-4b …the refusal names the new key" "floor: is gone; write regression-command:" "$OUT"
expect_eq "GV-4c …and nothing ran: still the one log" "1" "$(av_logs)"
printf 'floor: bash %s\nregression-command: bash %s\n' "$AV_STUB" "$AV_STUB" > "$RAV/.bionic/config.yaml"
poke "$RAV" regression-run
expect_eq "GV-4d …and with both keys written the old one is refused all the same (exit 1)" "1|1" "$RC|$(av_logs)"
expect_contains "GV-4e …naming the new key" "floor: is gone; write regression-command:" "$OUT"
printf 'regression-command: bash %s\n' "$AV_STUB" > "$RAV/.bionic/config.yaml"
poke "$RAV" regression-run
expect_eq "GV-4f the new key alone runs again (the refusals above were the old key's, not the verb's): second log, exit 0" "0|2" "$RC|$(av_logs)"
POKE_BOUND="$AV_BOUND_WAS"

# ============================================================
section "§GONE-BORN: --born floor:<suite> and a typed proof:floor are refused naming the new spelling; --born regression:<suite> and proof:regression write their rows"
# ============================================================
# FIXTURE FIDELITY: session-poker-3 §BORN-FLOOR's shape. The plan carries a 1.20.0 proof line, kind=floor with
# owed=a.test.sh,b.test.sh, written by the library's own proof_add_line: the on-disk old spelling backs the marker, and
# is read silently (§ALIAS-PLAN) while a person's typing of it is not.
AB_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
RAB="$(make_repo gone-born)"; ( cd "$RAB" && git commit -q --allow-empty -m init )
AB_C1="$(git -C "$RAB" rev-parse HEAD)"
git -C "$RAB" branch wave/01-fixture
PAB="$(s42_plan "$RAB" 4 "  worktree: .worktrees/01-fixture
  base-sha: abc1234
  branch: wave/01-fixture
  working-branch: wave/01-fixture")"
bash -c '. "$1" && proof_add_line "$2" "$3"' _ "$S46_LIB" "$PAB" \
  "proved: kind=floor head=${AB_C1} at=2026-10-14T00:00:00Z evidence=record/wave-01-fixture/floor.txt owed=a.test.sh,b.test.sh" > "$PAB.new" && mv "$PAB.new" "$PAB"
# …and a reads column, s51_plan's awk (session-poker-2 §51): the typed reads cells below need somewhere to go.
awk '/^## Tasks/ { t = 1 } /^## Verification/ { t = 0 }
     t && /^\| id / { print $0 " reads |"; next }
     t && /^\|---/ { print $0 "---|"; next }
     t && /^\| T/ { sub(/\| T1, T2 \|/, "| — |"); print $0 " — |"; next }
     { print }' "$PAB" > "$PAB.tmp" && mv "$PAB.tmp" "$PAB"
( cd "$RAB" && git add -f "$PAB" && git commit -qm floor ) >/dev/null 2>&1
ab_row() { /usr/bin/grep -c "^- $1:" "$PAB" | tr -d ' '; }   # <id> -> the lines the plan's state block holds for that row
poke "$RAB" task-add T6 4 build 'fix the red' bionic:implementor '—' 30 REQ-5 'lib/c.sh' --born regression:a.test.sh
expect_eq "GB-1 task-add --born regression:a.test.sh, which the 1.20.0 proof line owes, exits 0" "0" "$RC"
poke "$RAB" task-add T7 4 build 'fix the other red' bionic:implementor '—' 30 REQ-5 'lib/d.sh' --born floor:b.test.sh
expect_eq "GB-2 task-add --born floor:b.test.sh is refused (exit 1)" "1" "$RC"
expect_contains "GB-2b …the refusal names the new operand" "--born floor: is gone; write --born regression:" "$OUT"
poke "$RAB" task-add T8 4 test 'reads the regression' bionic:implementor '—' 30 REQ-5 '—' 'proof:regression, head'
expect_eq "GB-3 task-add with the reads cell 'proof:regression, head' exits 0" "0" "$RC"
expect_contains "GB-3b …and the row's cell carries it as typed" "| proof:regression, head |" "$(/usr/bin/grep '^| T8 |' "$PAB")"
poke "$RAB" task-add T9 4 test 'reads the old word' bionic:implementor '—' 30 REQ-5 '—' 'proof:floor, head'
expect_eq "GB-4 task-add with the reads cell 'proof:floor, head' is refused (exit 1)" "1" "$RC"
expect_contains "GB-4b …naming the new token" "proof:floor is gone; write proof:regression" "$OUT"
poke "$RAB" task-add T9 4 test 'reads the old word live' bionic:implementor '—' 30 REQ-5 '—' 'live:proof:floor'
expect_eq "GB-4c …the live: form too (exit 1), naming the new token" "1|1" \
  "$RC|$(printf '%s\n' "$OUT" | /usr/bin/grep -c 'proof:floor is gone; write proof:regression' | tr -d ' ')"
poke "$RAB" task-set T8 reads=proof:floor
expect_eq "GB-5 task-set T8 reads=proof:floor is refused (exit 1), naming the new token" "1|1" \
  "$RC|$(printf '%s\n' "$OUT" | /usr/bin/grep -c 'proof:floor is gone; write proof:regression' | tr -d ' ')"
expect_contains "GB-5b …and T8's cell is as it was" "| proof:regression, head |" "$(/usr/bin/grep '^| T8 |' "$PAB")"
poke "$RAB" task-set T8 'reads=approval:plan, proof:regression, head'
expect_eq "GB-5c task-set T8 reads='approval:plan, proof:regression, head' works (exit 0)" "0" "$RC"
expect_contains "GB-5d …and writes the cell" "| approval:plan, proof:regression, head |" "$(/usr/bin/grep '^| T8 |' "$PAB")"
POKE_BOUND="$AB_BOUND_WAS"

# ============================================================
section "§GONE-LOG: the one-run glob reads regression-run-<sha>.log; a floor-run-<sha>.log is not the head's whole run"
# ============================================================
# FIXTURE FIDELITY: session-poker-4 §FLOOR-RUN's shape: a stub tests/run.sh at the head, the plan's build rows landed, no
# config key, no regression proof. The record holds a log opening as the verb's whole-run logs do, `head=` on line one
# and `command: tests/run.sh` on line two. Under the new name it is the head's one whole run and refuses another; under
# the 1.20.0 name it is not read, so the run goes; the log that run writes refuses the next. The name alone moves the
# answer, on one fixture.
GL_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
RGL="$(make_repo gone-log)"; ( cd "$RGL" && git commit -q --allow-empty -m init )
GL_SEEN="$TMPROOT/gl-seen"
mkdir -p "$RGL/tests"
printf '#!/bin/bash\nprintf "ran\\n" >> "%s"\nprintf "head=x dirty=0\\nGating: 1 passed, 0 failed\\n"\n' "$GL_SEEN" > "$RGL/tests/run.sh"
printf '#!/bin/bash\nexit 0\n' > "$RGL/tests/a.test.sh"
( cd "$RGL" && git add tests && git commit -qm suites ) >/dev/null 2>&1
PGL="$(s42_plan "$RGL" 4)"; s42_builds_landed "$PGL"
awk '{ print } /^current: / && !d { print "working-branch: wave/01-fixture"; d = 1 }' "$PGL" > "$PGL.tmp" && mv "$PGL.tmp" "$PGL"
( cd "$RGL" && git add -f "$PGL" && git commit -qm wb \
  && git worktree add -q -b wave/01-fixture "$RGL/.worktrees/01-fixture" \
  && git -C "$RGL/.worktrees/01-fixture" commit -q --allow-empty -m "wave work" ) >/dev/null 2>&1
GL_W="$(git -C "$RGL/.worktrees/01-fixture" rev-parse HEAD 2>/dev/null)"
GL_REC="$RGL/.bionic/docs/record/wave-01-fixture"; mkdir -p "$GL_REC"
gl_ran() { [ -f "$GL_SEEN" ] && awk 'END { print NR + 0 }' "$GL_SEEN" || echo 0; }
expect_regex "GL-0 precondition: the working head is a 40-hex commit" '^[0-9a-f]{40}$' "$GL_W"
printf 'head=%s dirty=0\ncommand: tests/run.sh\nGating: 1 passed, 0 failed\nrc=0\n' "$GL_W" > "$GL_REC/regression-run-$GL_W.log"
poke "$RGL" regression-run
expect_eq "GL-1 a whole-run log under the new name at the head refuses another run: exit 1, and the stub never ran" "1|0" "$RC|$(gl_ran)"
rm -f "$GL_REC/regression-run-$GL_W.log"
printf 'head=%s dirty=0\ncommand: tests/run.sh\nGating: 1 passed, 0 failed\nrc=0\n' "$GL_W" > "$GL_REC/floor-run-$GL_W.log"
poke "$RGL" regression-run
expect_eq "GL-2 the same log under the 1.20.0 name is not read: the whole run goes (exit 0), the stub ran once" "0|1" "$RC|$(gl_ran)"
expect_true "GL-2b …and wrote its log under the new name" test -f "$GL_REC/regression-run-$GL_W.log"
rm -f "$GL_REC/floor-run-$GL_W.log"
poke "$RGL" regression-run
expect_eq "GL-3 the verb's own log refuses the next run at that head: exit 1, the stub still ran once" "1|1" "$RC|$(gl_ran)"
POKE_BOUND="$GL_BOUND_WAS"


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
  printf '| T5 | 7 | review | the live read | critic | — | 30 | REQ-1 | .bionic/docs/record/w/r2.md | pending | live:%s |\n' "$2"
  printf '| T4 | 7 | doc | the release | implementor | — | 30 | REQ-1 | b.md | pending | %s, approval:release |\n' "$2"
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
ap_both "AP-7 units_waiting at step 7" units_waiting 7
expect_contains "AP-7b …and the 1.20.0 plan's T4 waits on approval:release, its regression read met" \
  "$(printf 'T4\tapproval:release')" "$(ap "$AP_DIR/old.plan.md" units_waiting 7)"
ap_both "AP-8 units_edges" units_edges
expect_eq "AP-9 none of these readers printed a word on stderr for the on-disk tokens (the readers' positives are the answers above)" "0" "$(wc -c < "$TMPROOT/ap.err" | tr -d ' ')"


# ============================================================
# ============================================================
SP_SH="$POKER"; PROOF_SH="$LIB/proof.sh"; UNITS_SH="$LIB/units.sh"
# The regression-run verb's body is in the proof record's part beside the dispatcher; its parse arm stays in the dispatcher.
SP_PROOF="$(dirname "$POKER")/poker/proof.sh"
code_lines() { /usr/bin/grep -v -E '^[[:space:]]*#' "$1"; }   # <file> -> its lines that are not comments



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
for f in "${BIONIC_HOOKS_DIR}"/*.sh "${BIONIC_HOOKS_DIR}"/poker/*.sh "${BIONIC_SCRIPTS_DIR}"/payload/scripts/*.sh "$LIB"/*.sh; do [ -f "$f" ] && SCAN_FILES+=("$f"); done
expect_eq "AS-0b the scan reads the core script's seven parts beside the dispatcher" "7" \
  "$(printf '%s\n' "${SCAN_FILES[@]}" | /usr/bin/grep -c '/hooks/poker/[a-z]*\.sh$' | tr -d ' ')"
expect_nonempty "AS-0 the scan has files to read (the scanner's positive)" "${SCAN_FILES[*]}"
AS_HITS="$(scan "${SCAN_FILES[@]}")"
expect_eq "AS-1 no production code line spells an old token (hits: $(printf '%s' "$AS_HITS" | head -c 400))" "0" \
  "$(printf '%s' "$AS_HITS" | /usr/bin/grep -c . | tr -d ' ')"
AS_MUT="$TMPROOT/as-mut"; mkdir -p "$AS_MUT"
cp "$SP_SH" "$AS_MUT/session-poker.sh"; cp "$PROOF_SH" "$AS_MUT/proof.sh"
# One `  regression-run)` arm: the parse case's. The exec arm is a one-line call into the proof record's part.
anchor -E "$AS_MUT/session-poker.sh" '^  regression-run\)$' 1
awk '/^  regression-run\)$/ && !d { print "  floor-run) : ;;"; d = 1 } { print }' "$AS_MUT/session-poker.sh" > "$AS_MUT/sp.tmp" && mv "$AS_MUT/sp.tmp" "$AS_MUT/session-poker.sh"
expect_true "AS-2 precondition: the planted poker still parses" bash -n "$AS_MUT/session-poker.sh"
anchor "$AS_MUT/proof.sh" 'PROOF_KIND == "regression" || PROOF_KIND == "task"' 1
sed 's/PROOF_KIND == "regression" || PROOF_KIND == "task"/PROOF_KIND == "floor" || PROOF_KIND == "regression" || PROOF_KIND == "task"/' "$AS_MUT/proof.sh" > "$AS_MUT/p.tmp" && mv "$AS_MUT/p.tmp" "$AS_MUT/proof.sh"
expect_true "AS-3 precondition: the planted proof library still parses" bash -n "$AS_MUT/proof.sh"


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
expect_contains "AL-4d …and the printed line a trailing comment does not admit" 'say "the floor holds"' "$AL_MOUT"
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
# THE STATE IS A STACK (wave-38 T33, A-T33-2): s single-quoted, d double-quoted, c a $( … ) body, p a ( … ) inside
# one. A $( inside a double-quoted string opens code again, so its quotes nest and do not close the outer string:
# `v="$(K="$key" \` leaves one string open, not two closed and one open. Read flat, lib/gate.sh's budget verdict
# (`verdict="$(GATE_BUDGET_KEY="$key" … awk '…')"`) turned the walk inside out from there on, and the comment
# block above gate_width_ask read as a printed string. A case arm's `x)` inside a $( … ) closes it early.
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
  if (substr(S, length(S)) == "d" && (FNR in W)) print f ":" FNR ": in an open double-quoted string"
  line = $0; n = length(line); opener = ""
  for (i = 1; i <= n; i++) {
    c = substr(line, i, 1); q = substr(S, length(S))
    if (q == "s") { if (c == "\047") S = substr(S, 1, length(S) - 1); continue }
    if (q == "d") {
      if (c == "\\") { i++; continue }
      if (c == "\"") { S = substr(S, 1, length(S) - 1); continue }
      if (substr(line, i, 2) == "$(") { S = S "c"; i++ }
      continue
    }
    if (c == "\\") { i++; continue }
    if (c == "#" && (i == 1 || substr(line, i - 1, 1) ~ /[ \t;(|&]/)) break
    if (c == "\047") { S = S "s"; continue }
    if (c == "\"") { S = S "d"; continue }
    if (substr(line, i, 2) == "$(") { S = S "c"; i++; continue }
    if (q == "c" || q == "p") {
      if (c == "(") { S = S "p"; continue }
      if (c == ")") { S = substr(S, 1, length(S) - 1); continue }
    }
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
# The third plant is gate.sh's shape, quotes nested in a $( … ) in a string, and a comment after it: a flat walk
# reads that comment as inside a printed string, the stack does not (AL-6g beside the two it does find).
printf '%s\n' '  v="$(K="$k" \' "    awk 'BEGIN { gsub(/[\`\"]/, \"\", s) }')\"" "  msg=\"the \${who}'s line\"" \
  '# the floor, after quotes nested in a substitution' \
  'cat <<EOF' '# the floor, printed by a heredoc' 'EOF' '  say "a printed message' '# the floor, inside the printed string"' \
  >> "$AL_MUT/hooks/session-poker.sh"
expect_true "AL-6c precondition: the guard's plants still parse" bash -n "$AL_MUT/hooks/session-poker.sh"
AL_MGUARD="$(al_guard "$AL_MUT")"
expect_eq "AL-6d the guard finds both planted lines in the copy" "2" "$(printf '%s' "$AL_MGUARD" | /usr/bin/grep -c . | tr -d ' ')"
expect_contains "AL-6e …the heredoc's" "in a heredoc body (EOF)" "$AL_MGUARD"
expect_contains "AL-6f …and the open string's" "in an open double-quoted string" "$AL_MGUARD"
AL_NESTED_LN="$(/usr/bin/grep -n '^# the floor, after quotes nested' "$AL_MUT/hooks/session-poker.sh" | cut -d: -f1)"
expect_nonempty "AL-6g precondition: the nested plant's line is found" "$AL_NESTED_LN"
expect_contains "AL-6g …and the class admits it: the guard walks it" "$(printf 'hooks/session-poker.sh\t%s' "$AL_NESTED_LN")" \
  "$(cat "$TMPROOT/al-adm.tsv" 2>/dev/null)"
expect_absent "AL-6g …and the comment after quotes nested in a substitution is not reported" \
  "hooks/session-poker.sh:$AL_NESTED_LN:" "$AL_MGUARD"

finish
