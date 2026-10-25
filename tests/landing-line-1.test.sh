#!/bin/bash
# tests/landing-line-1.test.sh — the landing line, part 1 of 2: §EVENTS through §OWED.
#
# THE SUITE IS TWO PARTS (wave-39 T35; D1, D13, REQ-3 AC-3.3). One landing-line.test.sh promised more than the suite
# bar, ten minutes of the gate's promise, so it runs as two suites cut at a section boundary. Its governing header, its
# model world and the helpers both parts share are in tests/landing-line.prelude.sh, sourced below after the framework.
#
# Usage: bash tests/landing-line-1.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"
. "$(dirname "$0")/landing-line.prelude.sh"

section "§EVENTS: each event is one line, appended by one write, to the landing record"
#
# The record is wave-27's `landing-proofs.log` under the bound plan's record directory; a `line/v1`
# line separates its fields with `|`, so a value holding `|` or a line break is refused unwritten.
RE="$(ll_world)"
expect_nonempty "(fixture) the world repository was made" "$RE"
PE="$(ll_plan "$RE")"
expect_eq "(e1) line_record names the bound plan's landing record" "$(ll_rec "$RE")" "$(line_record "$PE")"
CE="$(ll_carrier)"
ll_ready "$RE" T1 "$CE" >/dev/null; RCE=$?
expect_eq "(e2) a ready event is appended (rc 0)" "0" "$RCE"
LE1="$(ll_ev "$RE" ready)"
expect_regex "(e2) …as one line in the interface's shape, at= ISO-UTC last" \
  "^line/v1\\|ev=ready\\|row=T1\\|name=wx-T1\\|commit=[0-9a-f]{40}\\|branch=wt/T1\\|tree=${RE}/.worktrees/T1\\|suites=a.test.sh\\|debt=-\\|carrier=${CE}\\|at=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$" "$LE1"
line_event "$PE" verdict row=T1 "commit=$(ll_head "$RE")" "suite=a|b" result=green log=- >/dev/null 2>&1; RCB=$?
expect_ne "(e4) a value holding | is refused" "0" "$RCB"
expect_eq "(e5) line_head prints the working branch's head" "$(ll_head "$RE")" "$(line_head "$PE")"

# ---------------------------------------------------------------------------
section "§FOLD: line_state prints each open entry in record order, and the base rule"
#
# `<row> <name> <commit> <present> <base> <candidate> <outcome> <suites>`, tab-separated; an entry's
# base is the candidate of the nearest earlier entry that is present and not returned or stalled,
# else the accepted head; an absent entry is skipped and holds nothing.
RF="$(ll_world)"; PF="$(ll_plan "$RF")"; HF="$(ll_head "$RF")"
CF1="$(ll_carrier)"; CF2="$(ll_carrier)"
ll_ready "$RF" T1 "$CF1" >/dev/null; ll_ready "$RF" T2 "$CF2" >/dev/null
T1C="$(git -C "$RF/.worktrees/T1" rev-parse HEAD)"; T2C="$(git -C "$RF/.worktrees/T2" rev-parse HEAD)"
expect_eq "(f1) two entries waiting; T2's base is unknown while T1 has no candidate" \
  "$(printf 'T1\twx-T1\t%s\tyes\t%s\t-\twaiting\ta.test.sh\nT2\twx-T2\t%s\tyes\t-\t-\twaiting\ta.test.sh' "$T1C" "$HF" "$T2C")" \
  "$(line_state "$PF")"
KF1="$(ll_cand "$RF" T1 "$HF")"
expect_nonempty "(f2-pre) T1's candidate was built" "$KF1"
expect_eq "(f2) T1 is proving on its candidate, and T2's base is that candidate" \
  "$(printf 'T1\twx-T1\t%s\tyes\t%s\t%s\tproving\ta.test.sh\nT2\twx-T2\t%s\tyes\t%s\t-\twaiting\ta.test.sh' "$T1C" "$HF" "$KF1" "$T2C" "$KF1")" \
  "$(line_state "$PF")"
ll_green "$RF" T1 "$KF1"
expect_eq "(f3) a green verdict on every suite makes T1 green" "green" "$(line_state "$PF" | awk -F'\t' '$1 == "T1" { print $7 }')"
line_event "$PF" verdict row=T1 "commit=$HF" suite=a.test.sh result=red log=- >/dev/null
expect_eq "(f3b) a verdict on another commit is not this candidate's" "green" "$(line_state "$PF" | awk -F'\t' '$1 == "T1" { print $7 }')"
RF2="$(ll_world)"; PF2="$(ll_plan "$RF2")"; HF2="$(ll_head "$RF2")"
ll_ready "$RF2" T1 "$(ll_dead)" >/dev/null; ll_ready "$RF2" T2 "$(ll_carrier)" >/dev/null
ll_cand "$RF2" T1 "$HF2" >/dev/null
expect_eq "(f4) an entry whose carrier is gone is printed absent" "no" "$(line_state "$PF2" | awk -F'\t' '$1 == "T1" { print $4 }')"
expect_eq "(f4) …and holds nothing: the next entry's base is the accepted head" "$HF2" \
  "$(line_state "$PF2" | awk -F'\t' '$1 == "T2" { print $5 }')"
line_event "$PF2" returned row=T1 why=red detail=- >/dev/null
expect_eq "(f5) a returned entry leaves the fold" "T2" "$(line_state "$PF2" | cut -f1 | tr '\n' ' ' | sed 's/ $//')"

# ---------------------------------------------------------------------------
section "§ONE-READER: every reader reads a landing line's fields by name, through lib/line.sh line_kv"
# Every line here carries a field ahead of its own, as a writer that adds one writes it. fails-when: a reader reads a
# field by its place, or a grep of hooks/ and payload/scripts/ finds a second parser beside the planted one.
OD="$WORLD_ROOT/one-reader"; ORC="$OD/landing-proofs.log"; OC=0123456789abcdef0123456789abcdef01234567; mkdir -p "$OD/t/payload"
printf 'line/v1|ev=%s|x=-|row=T1|commit=%s|%s|at=2026-10-20T00:00:00Z\n' ready "$OC" debt=a.test.sh verdict "$OC" 'suite=a.test.sh|result=red|log=/r.log' \
  verdict "$OC" 'suite=b.test.sh|result=none|log=/n.log' verdict "$OC" 'suite=c.test.sh|result=green|log=/g.log' > "$ORC"
cp -R "$BIONIC_HOOKS_DIR" "$OD/t/hooks"; cp -R "$REPO/payload/scripts" "$OD/t/payload/scripts"
printf '%s\n' '  function fv(k,   i) { return "" }' '  $2 == "ev=verdict" { print fv("row") }' > "$OD/t/hooks/planted.sh"
expect_eq "(o2) the grep finds the planted parser and the one reader's two lines, and nothing else" "hooks/planted.sh:2 payload/scripts/lib/line.sh:2" \
  "$( (cd "$OD/t" && /usr/bin/grep -rnE 'function [a-z_]+\(k, *i\)|"ev=|-v [a-z]+="(row|commit|suite|head|log|cause)=|\$[0-9]+ *[!=]= *"line/v1"|substr\(\$2, *4\)|\|ev=\(|index\(\$0, *"line/v1\|"\)|substr\(\$0, *1, *8\) *== *"line/v1\|"' hooks payload) \
     | /usr/bin/grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' | cut -d: -f1 | uniq -c | awk '{ print $2 ":" $1 }' | LC_ALL=C sort | paste -sd' ' -)"

# ---------------------------------------------------------------------------
section "§TREES: landing trees are the tool's, detached, held by a live process, reused"
RT="$(ll_world)"
LT1="$(landing_tree_take "$RT")"
expect_eq "(t1) the first tree is <root>/.bionic/tmp/landing/1" "$RT/.bionic/tmp/landing/1" "$LT1"
expect_regex "(t1) …held by <pid>:<start>" "^[0-9]+:.+" "$(cat "$LT1.held" 2>/dev/null)"
expect_contains "(t1) …a detached checkout git lists" "detached" \
  "$(git -C "$RT" worktree list --porcelain | awk -v p="$LT1" '$0 == "worktree " p { f = 1; next } f && /^$/ { exit } f')"
LT2="$( cd "$RT" && bash -c '. "$1"; landing_tree_take "$2"' _ "$LINE" "$RT" )"
expect_eq "(t2) a second taker, while the first holds, gets the next tree" "$RT/.bionic/tmp/landing/2" "$LT2"
landing_tree_point "$LT1" "$(git -C "$RT" rev-parse main)"
expect_eq "(t3) landing_tree_point re-points it, detached" "$(git -C "$RT" rev-parse main) HEAD" \
  "$(git -C "$LT1" rev-parse HEAD) $(git -C "$LT1" rev-parse --abbrev-ref HEAD)"
landing_tree_free "$LT1"
expect_false "(t4) freed by removing the hold" test -e "$LT1.held"
expect_eq "(t4) …and taken again" "$LT1" "$(landing_tree_take "$RT")"
landing_tree_free "$LT1"
# Never a bare `.held`: with no tree 2 (the library absent) nothing is planted, in the cwd or anywhere.
[ -z "$LT2" ] || printf '%s\n' "$(ll_dead)" > "$LT2.held"
LT3="$(landing_tree_take "$RT")"; LT4="$(landing_tree_take "$RT")"
expect_eq "(t5) a hold whose holder is not alive is free (tree 2 taken after tree 1)" "$LT2" "$LT4"
landing_tree_free "$LT3"; landing_tree_free "$LT4"

# ---------------------------------------------------------------------------
section "§SAME: what is published is what was proved (AC-1.3)"
RS="$(ll_world)"; PS="$(ll_plan "$RS")"; HS="$(ll_head "$RS")"
ll_ready "$RS" T1 "$(ll_carrier)" >/dev/null
KS1="$(ll_cand "$RS" T1 "$HS")"; ll_green "$RS" T1 "$KS1"
ll_pub "$RS" T1
expect_eq "(s1) the publish exits 0" "0" "$LL_RC"
expect_eq "(s1) the working branch is the proved candidate, exactly" "$KS1" "$(ll_head "$RS")"
expect_eq "(s1) …and the checkout that holds it is there, clean" "$KS1:" \
  "$(git -C "$RS" rev-parse HEAD):$(git -C "$RS" status --porcelain)"
expect_regex "(s1) the published event names that candidate" \
  "^line/v1\\|ev=published\\|row=T1\\|commit=${KS1}\\|kind=queue\\|by=-\\|why=-\\|at=" "$(ll_ev "$RS" published)"
expect_eq "(s1) …and T1 leaves the fold" "" "$(line_state "$PS")"
ll_ready "$RS" T2 "$(ll_carrier)" >/dev/null
KS2="$(ll_cand "$RS" T2 "$KS1")"; ll_green "$RS" T2 "$KS2"
echo "# a hand edit" >> "$RS/tests/a.test.sh"
git -C "$RS" commit -qam "a hand commit to a mapped file, after the verdict"
HS2="$(ll_head "$RS")"
ll_pub "$RS" T2
expect_eq "(s2) a commit to the branch between verdict and publish: rc 3, rebuild" "3" "$LL_RC"
expect_contains "(s2) …saying so" "REBUILD T2" "$LL_OUT"
expect_eq "(s2) …nothing is published" "$HS2" "$(ll_head "$RS")"

# ---------------------------------------------------------------------------
section "§PAIR: two publishes never interleave (AC-3.8)"
#
# The pause seam holds a publisher just before its fast-forward, inside the lock. Order one: T1
# (first in line) reaches the seam; T2 starts and cannot reach it while T1 holds the lock; both
# are released and both land, in order. Order two: T2 asks first and is told to rebuild; T1
# publishes; T2 then publishes. Then the hand landing as the second.
ll_pair_world() {  # -> root; T1 and T2 green, T2's candidate built on T1's
  local r h k1 k2
  r="$(ll_world)" || return 1; h="$(ll_head "$r")"
  ll_ready "$r" T1 "$(ll_carrier)" >/dev/null; ll_ready "$r" T2 "$(ll_carrier)" >/dev/null
  k1="$(ll_cand "$r" T1 "$h")"; ll_green "$r" T1 "$k1"
  k2="$(ll_cand "$r" T2 "$k1")"; ll_green "$r" T2 "$k2"
  printf '%s' "$r"
}
RP="$(ll_pair_world)"; KP2="$(line_state "$(ll_plan "$RP")" | awk -F'\t' '$1 == "T2" { print $6 }')"
PAUSE="$WORLD_ROOT/pause-p1"; mkdir -p "$PAUSE"
export BIONIC_LINE_PAUSE_BEFORE_PUBLISH="$PAUSE"
ll_pub_bg "$RP" T1 "$WORLD_ROOT/p1-T1.out" >/dev/null
expect_true "(p1) T1 reaches the seam" ll_wait_file "$PAUSE/T1.at-publish"
ll_pub_bg "$RP" T2 "$WORLD_ROOT/p1-T2.out" >/dev/null
sleep 1
expect_false "(p1) T2 does not reach the seam while T1 holds the lock" test -e "$PAUSE/T2.at-publish"
touch "$PAUSE/T1.go" "$PAUSE/T2.go"
ll_wait_file "$WORLD_ROOT/p1-T1.out.rc" 300; ll_wait_file "$WORLD_ROOT/p1-T2.out.rc" 300
expect_eq "(p1) both exit 0" "0 0" "$(cat "$WORLD_ROOT/p1-T1.out.rc") $(cat "$WORLD_ROOT/p1-T2.out.rc")"
expect_eq "(p1) the branch is T2's candidate, which holds T1's" "$KP2" "$(ll_head "$RP")"
expect_eq "(p1) published in order: T1, then T2" "T1 T2" \
  "$(ll_ev "$RP" published | sed 's/.*|row=\([^|]*\)|.*/\1/' | tr '\n' ' ' | sed 's/ $//')"
unset BIONIC_LINE_PAUSE_BEFORE_PUBLISH

RP2="$(ll_pair_world)"; HP2="$(ll_head "$RP2")"
ll_pub "$RP2" T2
expect_eq "(p2) T2 asking first is told to rebuild (rc 3)" "3" "$LL_RC"
ll_pub "$RP2" T1; RCP21=$LL_RC
ll_pub "$RP2" T2
expect_eq "(p2) then T1 publishes, then T2" "0 0" "$RCP21 $LL_RC"
expect_eq "(p2) published in order: T1, then T2" "T1 T2" \
  "$(ll_ev "$RP2" published | sed 's/.*|row=\([^|]*\)|.*/\1/' | tr '\n' ' ' | sed 's/ $//')"

# THE FIRST-IN-LINE CHECK, ALONE: T1 present and waiting, T2's candidate built on the accepted head.
RP3="$(ll_world)"; HP3="$(ll_head "$RP3")"
ll_ready "$RP3" T1 "$(ll_carrier)" >/dev/null; ll_ready "$RP3" T2 "$(ll_carrier)" >/dev/null
KP3="$(ll_cand "$RP3" T2 "$HP3")"; ll_green "$RP3" T2 "$KP3"
ll_pub "$RP3" T2
expect_eq "(p3) an entry behind a present one does not publish, even on the accepted head (rc 3)" "3" "$LL_RC"
expect_eq "(p3) …and nothing is published" "$HP3" "$(ll_head "$RP3")"
LL_MUTANT='/_line_first_in_line/d'
export LL_MUTANT
ll_pub "$RP3" T2
expect_eq "(p3m) MUTANT first-in-line skipped: T2 publishes ahead of T1 (the row can fail)" "0:$KP3" "$LL_RC:$(ll_head "$RP3")"
unset LL_MUTANT

# THE LOCK: two publishers of one row. The second waits on the lock, and once the first has
# published the row is no longer in line, so it is told to rebuild. Mutated (the lock skipped),
# the second passes every check while the first is paused at the seam, and both publish.
ll_p4() {  # <out prefix> -> two publishers of T1, the second started while the first is paused
  local r="$1" pause="$2"
  export BIONIC_LINE_PAUSE_BEFORE_PUBLISH="$pause"
  ll_pub_bg "$r" T1 "$3-a.out" >/dev/null
  ll_wait_file "$pause/T1.at-publish"
  ll_pub_bg "$r" T1 "$3-b.out" >/dev/null
  sleep 1
  touch "$pause/T1.go"; ll_wait_file "$3-a.out.rc" 300; ll_wait_file "$3-b.out.rc" 300
  unset BIONIC_LINE_PAUSE_BEFORE_PUBLISH
}
RP4="$(ll_pair_world)"; mkdir -p "$WORLD_ROOT/pause-p4"
ll_p4 "$RP4" "$WORLD_ROOT/pause-p4" "$WORLD_ROOT/p4"
expect_eq "(p4) the second publisher of a row already published is told to rebuild" "0 3" \
  "$(cat "$WORLD_ROOT/p4-a.out.rc") $(cat "$WORLD_ROOT/p4-b.out.rc")"
RP5="$(ll_pair_world)"; mkdir -p "$WORLD_ROOT/pause-p5"
export LL_MUTANT='/_line_lock_take /d'
ll_p4 "$RP5" "$WORLD_ROOT/pause-p5" "$WORLD_ROOT/p5"
unset LL_MUTANT
# Both mutant publishers are released by the one `T1.go` at the same instant, so their fast-forwards
# race on the checkout's index lock and either may be refused (wave-28 T4 met `2 0` under load). What
# the lock decides is whether the second is told to rebuild; that is what the mutant row reads.
expect_ne "(p5m) MUTANT lock skipped: the second publisher of the row is not told to rebuild (the row can fail)" "3" \
  "$(cat "$WORLD_ROOT/p5-b.out.rc" 2>/dev/null)"

# THE HAND LANDING AS THE SECOND: it enters the line behind T1, builds on T1's candidate, waits
# for the lock, and publishes after it under the same lock.
RH="$(ll_world)"; HH="$(ll_head "$RH")"
ll_ready "$RH" T1 "$(ll_carrier)" >/dev/null
KH1="$(ll_cand "$RH" T1 "$HH")"; ll_green "$RH" T1 "$KH1"
PAUSEH="$WORLD_ROOT/pause-h"; mkdir -p "$PAUSEH"
export BIONIC_LINE_PAUSE_BEFORE_PUBLISH="$PAUSEH"
ll_pub_bg "$RH" T1 "$WORLD_ROOT/h-T1.out" >/dev/null
ll_wait_file "$PAUSEH/T1.at-publish"
( cd "$RH" && CLAUDE_CODE_SESSION_ID="$WORLD_SID" bash "$SPAWN" land "$RH/.worktrees/T2" --by-hand --reason 'pair' \
    > "$WORLD_ROOT/h-T2.out" 2>&1; echo $? > "$WORLD_ROOT/h-T2.out.rc" ) &
sleep 2
expect_false "(h1) the hand landing does not reach the seam while T1 holds the lock" test -e "$PAUSEH/T2.at-publish"
touch "$PAUSEH/T1.go" "$PAUSEH/T2.go"
ll_wait_file "$WORLD_ROOT/h-T1.out.rc" 300; ll_wait_file "$WORLD_ROOT/h-T2.out.rc" 600
unset BIONIC_LINE_PAUSE_BEFORE_PUBLISH
expect_eq "(h1) both exit 0" "0 0" "$(cat "$WORLD_ROOT/h-T1.out.rc" 2>/dev/null) $(cat "$WORLD_ROOT/h-T2.out.rc" 2>/dev/null)"
expect_eq "(h1) published in order: T1 by the queue, then T2 by hand" "T1:queue T2:hand" \
  "$(ll_ev "$RH" published | sed 's/.*|row=\([^|]*\)|commit=[^|]*|kind=\([^|]*\)|.*/\1:\2/' | tr '\n' ' ' | sed 's/ $//')"
expect_true "(h1) the branch holds both rows' commits" git -C "$RH" merge-base --is-ancestor wt/T2 wave/x
expect_true "(h1) …T1's too" git -C "$RH" merge-base --is-ancestor "$KH1" wave/x

# ---------------------------------------------------------------------------
section "§BUSY: never a publish under a live run in the checkout that holds the branch (AC-3.6)"
RB="$(ll_world)"; HB="$(ll_head "$RB")"
ll_ready "$RB" T1 "$(ll_carrier)" >/dev/null
KB="$(ll_cand "$RB" T1 "$HB")"; ll_green "$RB" T1 "$KB"
mkdir -p "$BIONIC_GATE_DIR/requests"
printf 'key=a.test.sh\nkind=work\nwho=%s:main\ntree=%s\nasked=1\nholder=%s\nadmitted=2\npromise=1:1:1\n' \
  "$WORLD_SID" "$RB" "$(ll_carrier)" > "$BIONIC_GATE_DIR/requests/41"
ll_pub "$RB" T1
expect_eq "(b1) an admitted, unended request in that checkout holds the publish (rc 4)" "4" "$LL_RC"
expect_match "(b1) …printing HELD and naming the run" "HELD T1 — *41*a.test.sh*" "$LL_OUT"
expect_eq "(b1) …and the branch did not move" "$HB" "$(ll_head "$RB")"
printf 'key=a.test.sh\nkind=work\nwho=%s:main\ntree=%s\nasked=1\nholder=%s\nadmitted=2\npromise=1:1:1\n' \
  "$WORLD_SID" "$RB/.worktrees/T2" "$(ll_carrier)" > "$BIONIC_GATE_DIR/requests/41"
# LL_RUNNER and ll_runner: hoisted to tests/landing-line.prelude.sh (§REORDER and §ABSENT in part 2 call it)
expect_true "(b2-pre) a stand-in runner started in the checkout that holds the branch" ll_runner "$RB"
ll_pub "$RB" T1
expect_eq "(b2) an unadmitted suite process there holds the publish too (rc 4)" "4" "$LL_RC"
expect_match "(b2) …naming it" "HELD T1 — *pid=${LL_RUNNER_PID} cwd=${RB}*" "$LL_OUT"
expect_eq "(b2) …and the branch did not move" "$HB" "$(ll_head "$RB")"
kill "$LL_RUNNER_PID" 2>/dev/null; wait "$LL_RUNNER_PID" 2>/dev/null
expect_true "(b3-pre) a stand-in runner started in a row tree under the root" ll_runner "$RB/.worktrees/T2"
ll_pub "$RB" T1
expect_eq "(b3) a run in a row tree, and a request for a row tree, hold nothing: it publishes" "0:$KB" "$LL_RC:$(ll_head "$RB")"
kill "$LL_RUNNER_PID" 2>/dev/null; wait "$LL_RUNNER_PID" 2>/dev/null
rm -f "$BIONIC_GATE_DIR/requests/41"

# ---------------------------------------------------------------------------
section "§MOVED: no publish after a run that moved a real checkout (AC-3.9)"
RM="$(ll_world)"; HM="$(ll_head "$RM")"
ll_ready "$RM" T1 "$(ll_carrier)" >/dev/null
KM="$(ll_cand "$RM" T1 "$HM")"
sleep 1
# The run: a suite in the landing tree that reaches out and moves the main checkout's branch.
LTM="$(landing_tree_take "$RM")"; landing_tree_point "$LTM" "$KM"
printf '#!/bin/bash\ngit -C %s checkout -q -b moved-by-a-suite\n' "$RM" > "$WORLD_ROOT/mover.sh"
( cd "$LTM" && bash "$WORLD_ROOT/mover.sh" )
landing_tree_free "$LTM"
ll_green "$RM" T1 "$KM"
ll_pub "$RM" T1
expect_eq "(m1) the publish stops (rc 5)" "5" "$LL_RC"
expect_eq "(m1) …and the report names the checkout" "MOVED $RM" "$(printf '%s\n' "$LL_OUT" | grep '^MOVED')"
expect_eq "(m1) …and the branch did not move" "$HM" "$(ll_head "$RM")"

# ---------------------------------------------------------------------------
section "§GIT: a plain git merge is counted, not refused (AC-5.3)"
RG="$(ll_world)"; PG="$(ll_plan "$RG")"
ll_ready "$RG" T1 "$(ll_carrier)" >/dev/null
expect_eq "(g0) T1 is open before the merge" "T1" "$(line_state "$PG" | cut -f1)"
git -C "$RG" merge -q --no-ff -m "a person merges T1 by hand" wt/T1
HG="$(ll_head "$RG")"
expect_eq "(g1) after a plain merge of its branch, the next read closes T1" "" "$(line_state "$PG")"
expect_regex "(g1) …marked landed by git, naming the accepted head" \
  "^line/v1\\|ev=published\\|row=T1\\|commit=${HG}\\|kind=git\\|by=-\\|why=-\\|at=" "$(ll_ev "$RG" published)"
line_state "$PG" >/dev/null
expect_eq "(g2) a second read adds nothing" "1" "$(ll_ev "$RG" published | awk 'END { print NR }')"
git -C "$RG" merge -q --no-ff -m "and T2, never on the line" wt/T2
line_state "$PG" >/dev/null
expect_regex "(g3) a plan row never on the line is marked landed by git too" \
  "^line/v1\\|ev=published\\|row=T2\\|commit=$(ll_head "$RG")\\|kind=git\\|" "$(ll_ev "$RG" published | sed -n 2p)"
# A TREE CUT AT THE HEAD WITH NO COMMIT YET (ruling A-orch-39, read-adversarial-p8 #1): it has landed
# nothing, so the first read does not count it, and its real plain merge later is counted. The world
# gives every row tree a commit, so this tree is cut by hand.
ll_t3_world() {  # -> a world whose plan has a row T3, its tree cut at wave/x with no commit
  local r
  r="$(ll_world)" || return 1
  git -C "$r" worktree add -q -b wt/T3 "$r/.worktrees/T3" wave/x >/dev/null 2>&1 || return 1
  printf '| T3 | 4 | build | row three | wx-T3 | — | | 10 | REQ-1 | T3.txt | .worktrees/T3 | | active |\n' >> "$(ll_plan "$r")"
  printf '%s' "$r"
}
RG4="$(ll_t3_world)"; PG4="$(ll_plan "$RG4")"
ll_ready "$RG4" T1 "$(ll_carrier)" >/dev/null   # a record to read: the count reads none without one
expect_eq "(g4-pre) T3's tree is at the accepted head" "$(ll_head "$RG4")" "$(git -C "$RG4/.worktrees/T3" rev-parse HEAD)"
line_state "$PG4" >/dev/null
expect_eq "(g4) a row tree with no commit of its own is not counted landed by git" "" "$(ll_ev "$RG4" published)"
printf 't3\n' > "$RG4/.worktrees/T3/T3.txt"; git -C "$RG4/.worktrees/T3" add T3.txt; git -C "$RG4/.worktrees/T3" commit -qm "T3 work"
git -C "$RG4" merge -q --no-ff -m "a person merges T3" wt/T3
line_state "$PG4" >/dev/null
expect_regex "(g4) …and its real plain merge is, once it has one" \
  "^line/v1\\|ev=published\\|row=T3\\|commit=$(ll_head "$RG4")\\|kind=git\\|" "$(ll_ev "$RG4" published)"
RG5="$(ll_t3_world)"; ll_ready "$RG5" T1 "$(ll_carrier)" >/dev/null
( eval "$(declare -f _line_count_git | sed '/_line_cut_at/d')"; line_state "$(ll_plan "$RG5")" >/dev/null )
expect_contains "(g5m) MUTANT the cut check removed: the tree with no commit is counted landed (the row can fail)" \
  "|row=T3|" "$(ll_ev "$RG5" published)"

# ---------------------------------------------------------------------------
section "§GUARD: a candidate that commits .bionic is returned before anything is published (AC-14.1, publish half)"
RD="$(ll_world)"; HD="$(ll_head "$RD")"
git -C "$RD/.worktrees/T1" add -f .bionic && git -C "$RD/.worktrees/T1" commit -qm "T1: the link, committed"
TDC="$(git -C "$RD/.worktrees/T1" rev-parse HEAD)"
ll_ready "$RD" T1 "$(ll_carrier)" >/dev/null
KD="$(ll_cand "$RD" T1 "$HD")"; ll_green "$RD" T1 "$KD"
LTD="$(line_state "$(ll_plan "$RD")" | cut -f6)"
expect_nonempty "(d0) the candidate was built" "$LTD"
ll_pub "$RD" T1
expect_eq "(d1) the publish is refused by the guard (rc 6)" "6" "$LL_RC"
expect_absent "(d1) …never the landing tree" ".bionic/tmp/landing" "$LL_OUT"
expect_absent "(d1) …and nothing of stamps" "stamps" "$LL_OUT"
expect_eq "(d1) nothing is published" "$HD" "$(ll_head "$RD")"
expect_regex "(d1) the row is returned with why=guard" "^line/v1\\|ev=returned\\|row=T1\\|why=guard\\|detail=.bionic\\|at=" "$(ll_ev "$RD" returned)"
expect_true "(d1) the project's .bionic is still a directory" test -d "$RD/.bionic" -a ! -L "$RD/.bionic"
RD2="$(ll_world)"; HD2="$(ll_head "$RD2")"
git -C "$RD2/.worktrees/T1" add -f .bionic && git -C "$RD2/.worktrees/T1" commit -qm "T1: the link, committed"
ll_ready "$RD2" T1 "$(ll_carrier)" >/dev/null
KD2="$(ll_cand "$RD2" T1 "$HD2")"; ll_green "$RD2" T1 "$KD2"
export LL_MUTANT='/_line_guard /d'
ll_pub "$RD2" T1
unset LL_MUTANT
expect_eq "(d2m) MUTANT guard call removed: the link is published (the row can fail)" "0:$KD2" "$LL_RC:$(ll_head "$RD2")"

# ============================================================================ the carrier (wave-28 T4)
#
# `spawn-worktree.sh ready` from a row's own tree. Each row below builds its own world, plants the
# row's launch line on the roster (`lands_on=`, the suites it lands on; T7 lifts it from the brief),
# and drives the verb or, for a mutant, `line_ready` in a driver process of its own (`LL_RD`, the
# verb's own call, with LL_MUTANT a sed over the function LL_MUTANT_FN). Suites run through the real
# gate on the world's planted machine: room for two runs at once, a clock that moves only when told.
ll_carrier_env   # the carrier's environment: roster, config dir, machine, clock, signal dir (tests/landing-line.prelude.sh; part 2 calls it as well)

# ll_launch to ll_field (the carrier driver and its verbs): hoisted to tests/landing-line.prelude.sh (part 2 calls them)

# ---------------------------------------------------------------------------
section "§READY: ready is one verb and the writer's last act (AC-1.1)"
#
# From the row's tree, `ready` appends the entry (with its time), proves the candidate, publishes,
# and prints LANDED and the acts still owed; the fixture's verb log holds no other verb.
world_cost a.test.sh 5 0.5 5; world_cost b.test.sh 5 0.5 5
RR="$(ll_rworld)"; HR="$(ll_head "$RR")"; T1R="$(git -C "$RR/.worktrees/T1" rev-parse HEAD)"
: > "$(world_verbs)"
ll_verb "$RR" T1
KR="$(ll_ev "$RR" candidate | head -1)"; KR="$(ll_field "$KR" commit)"
expect_eq "(r1) ready exits 0" "0" "$LL_RC"
expect_nonempty "(r1-pre) a candidate was built" "$KR"
expect_regex "(r2) the entry: the ready event, with the row, the roster name, the suites, the debt, the carrier, its lease's age and its time" \
  "^line/v1\\|ev=ready\\|row=T1\\|name=wx-T1\\|commit=${T1R}\\|branch=wt/T1\\|tree=${RR}/.worktrees/T1\\|suites=a.test.sh\\|debt=-\\|carrier=[0-9]+:[^|]+\\|age=[0-9]+:[0-9]+\\|at=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$" \
  "$(ll_ev "$RR" ready)"
expect_eq "(r2) …and it is the record's first line" "ready" "$(head -1 "$(ll_rec "$RR")" | cut -d'|' -f2 | sed 's/^ev=//')"
expect_eq "(r3) the verb log holds the one verb, ready" "ready" "$(cat "$(world_verbs)")"
expect_eq "(r4) the branch is the candidate: the row merged onto the accepted head" "$KR $HR $T1R" \
  "$(ll_head "$RR") $(git -C "$RR" rev-parse "$KR^1") $(git -C "$RR" rev-parse "$KR^2")"
expect_regex "(r4) …proved by a green verdict on that candidate, its log under the record directory" \
  "^line/v1\\|ev=verdict\\|row=T1\\|commit=${KR}\\|suite=a.test.sh\\|result=green\\|log=${RR}/.bionic/docs/record/wave-x/line/T1-a-${KR:0:12}.log\\|" \
  "$(ll_ev "$RR" verdict)"
expect_contains "(r4) …the log holds the suite's own end line" "a.test.sh: 1/1 passed" \
  "$(cat "$RR/.bionic/docs/record/wave-x/line/T1-a-${KR:0:12}.log" 2>/dev/null)"
expect_false "(r4) …and the landing tree's hold is freed" test -e "$RR/.bionic/tmp/landing/1.held"
RR2="$(ll_world)"
ll_launch "$RR2" T1 'a, b.test.sh' lands_red='b.test.sh until T9'
ll_verb "$RR2" T1
expect_eq "(r5) suites and the debt are read off the launch line" "a.test.sh,b.test.sh b.test.sh" \
  "$(E="$(ll_ev "$RR2" ready)"; printf '%s %s' "$(ll_field "$E" suites)" "$(ll_field "$E" debt)")"
expect_eq "(r5) …and each suite is run on the candidate" "a.test.sh:green b.test.sh:green" \
  "$(ll_ev "$RR2" verdict | sed 's/.*|suite=\([^|]*\)|result=\([^|]*\)|.*/\1:\2/' | tr '\n' ' ' | sed 's/ $//')"
RR3="$(ll_world)"
printf '%s|row=T1\n' "$(roster_row_fixture status=intended session="$WORLD_SID" name=wx-T1 agent_id=b00T1 plan="$(ll_plan "$RR3")")" \
  >> "$RR3/.bionic/tmp/roster-$WORLD_SID.state"
ll_verb "$RR3" T1
expect_eq "(r6) a launch line naming no lands_on is refused (exit 2)" "2" "$LL_RC"
expect_contains "(r6) …saying so" "REFUSED reason=no-lands-on row=T1 name=wx-T1" "$LL_OUT"
expect_false "(r6) …and nothing is appended" test -e "$(ll_rec "$RR3")"
# A RUN OPEN AT UPGRADE (wave-28 T21; D26, AC-7.2): a launch row 1.12.0 wrote carries `suites_allowed=` and no
# `row=` or `lands_on=`; ready reads its suites from there. A row naming none is refused, with the hand landing.
RR4="$(ll_world)"
printf '%s\n' "$(roster_row_fixture status=intended session="$WORLD_SID" name=wx-T1 agent_id=b00T1 plan="$(ll_plan "$RR4")" \
  suites_allowed=a.test.sh suites_source=declared)" >> "$RR4/.bionic/tmp/roster-$WORLD_SID.state"
ll_verb "$RR4" T1
expect_eq "(r6b) a 1.12.0 launch row (suites_allowed=, no row=, no lands_on=) lands by ready (exit 0)" "0" "$LL_RC"
expect_eq "(r6b) …on the suites it allowed" "a.test.sh" "$(ll_field "$(ll_ev "$RR4" ready)" suites)"
RR5="$(ll_world)"
printf '%s|row=T1|lands_on=a.test.sh\n' "$(roster_row_fixture status=intended session="$WORLD_SID" name=wx-T1 agent_id=b00T1 plan="$(ll_plan "$RR5")" \
  suites_allowed=b.test.sh suites_source=declared)" >> "$RR5/.bionic/tmp/roster-$WORLD_SID.state"
ll_verb "$RR5" T1
expect_eq "(r6c) a row naming both reads lands_on=, not suites_allowed=" "0 a.test.sh" "$LL_RC $(ll_field "$(ll_ev "$RR5" ready)" suites)"
RR6="$(ll_world)"
printf '%s\n' "$(roster_row_fixture status=intended session="$WORLD_SID" name=wx-T1 agent_id=b00T1 plan="$(ll_plan "$RR6")" \
  suites_allowed= suites_source=declared)" >> "$RR6/.bionic/tmp/roster-$WORLD_SID.state"
ll_verb "$RR6" T1
expect_eq "(r6d) a 1.12.0 row that names no suite (suites_allowed= empty) is refused (exit 2)" "2" "$LL_RC"
expect_contains "(r6d) …naming the row" "REFUSED reason=no-lands-on row=T1 name=wx-T1" "$LL_OUT"
expect_contains "(r6d) …and the hand landing" "--by-hand --reason '<why>'" "$LL_OUT"
expect_false "(r6d) …and nothing is appended" test -e "$(ll_rec "$RR6")"
ll_launch "$RR6" T1 none
ll_verb "$RR6" T1
expect_true "(r6d-control) …while the same tree, its launch row naming lands_on=none, lands and the record exists" test -e "$(ll_rec "$RR6")"
RR6b="$(ll_world)"
printf '%s\n' "$(roster_row_fixture status=intended session="$WORLD_SID" name=wx-T1 agent_id=b00T1 plan="$(ll_plan "$RR6b")" \
  suites_allowed='none docs only' suites_source=declared)" >> "$RR6b/.bionic/tmp/roster-$WORLD_SID.state"
ll_verb "$RR6b" T1
expect_eq "(r6d2) suites_allowed=none on a 1.12.0 row is an absence, not a waiver: refused (exit 2), naming its key" "2 yes" \
  "$LL_RC $(printf '%s' "$LL_OUT" | grep -qF "REFUSED reason=no-lands-on row=T1 name=wx-T1 suites_allowed=none docs only — " && echo yes || echo no)"
ll_launch "$RR6b" T1 'none docs only'
ll_verb "$RR6b" T1
expect_eq "(r6d3) …while the same tree, lands_on=none <why> (a declared waiver) publishes with no run (the one parser, the key's meaning)" "0 none 0" \
  "$LL_RC $(ll_field "$(ll_ev "$RR6b" ready)" suites) $(ll_ev "$RR6b" verdict | awk 'END { print NR }')"

# THE ROW THE WALL READS (wave-28 T64; D26, REQ-7 AC-7.2, REQ-2 AC-2.11). `ready` takes a row's suites from the
# roster row the walls read for its agent (`roster_row_for_id`: the latest row carrying the agent's id, the
# successors `amend`, `hold`, `extend`, the landed mark and `adopt` write included), never from the launch row alone.
# Rows are the 1.12.0 shape (no `row=`, no `lands_on=`): the plan row's agent cell, `wx-T1`, finds them.
ll_roster() { printf '%s/.bionic/tmp/roster-%s.state' "$1" "$WORLD_SID"; }
ll_wrow() {  # <root> <key=value>... — one row of wx-T1 on the roster, through the production writer
  local r="$1"
  shift
  printf '%s\n' "$(roster_row_fixture session="$WORLD_SID" name=wx-T1 agent_id=b00T1 plan="$(ll_plan "$r")" \
    suites_source=declared "$@")" >> "$(ll_roster "$r")"
}
ll_wide() {  # <root> <suites> [more] — the launch, its identification, then an amend widening to <suites>
  ll_wrow "$1" status=intended suites_allowed=a.test.sh
  ll_wrow "$1" status=identified suites_allowed=a.test.sh
  [ -z "${3:-}" ] || ll_wrow "$1" status=identified suites_allowed=a.test.sh "$3"
  ll_wrow "$1" status=identified suites_allowed="$2" amended='2026-10-07T00:00:00Z widened'
}
ll_verdicts() {  # <root> -> `suite:result` of each verdict on the row's candidate (a red is asked once more at the head)
  local k
  k="$(ll_field "$(ll_ev "$1" candidate | head -1)" commit)"
  ll_ev "$1" verdict | grep -F "|commit=${k}|" | sed 's/.*|suite=\([^|]*\)|result=\([^|]*\)|.*/\1:\2/' | tr '\n' ' ' | sed 's/ $//'
}
RM1="$(ll_world)"; HM1="$(ll_head "$RM1")"
ll_wide "$RM1" 'a.test.sh b.test.sh'
ll_redsuite "$RM1" T1 b
ll_verb "$RM1" T1
KM1="$(ll_field "$(ll_ev "$RM1" candidate)" commit)"
expect_eq "(r6e) a row amended to a b, b red on the candidate: ready exits 1, RED naming b" \
  "1 RED T1 b.test.sh $RM1/.bionic/docs/record/wave-x/line/T1-b-${KM1:0:12}.log" "$LL_RC $LL_OUT"
expect_eq "(r6e) …proved on the amended set, both suites run" "a.test.sh,b.test.sh a.test.sh:green b.test.sh:red" \
  "$(ll_field "$(ll_ev "$RM1" ready)" suites) $(ll_verdicts "$RM1")"
expect_eq "(r6e) …and nothing is published" "$HM1" "$(ll_head "$RM1")"
RM2="$(ll_world)"
ll_wide "$RM2" 'a.test.sh b.test.sh'
ll_verb "$RM2" T1
expect_eq "(r6f) the same row, every suite green: LANDED (exit 0)" "0 LANDED" "$LL_RC $(printf '%s\n' "$LL_OUT" | head -1 | cut -d' ' -f1)"
expect_eq "(r6f) …on both suites of the amended set, the stamp read for neither" "a.test.sh,b.test.sh a.test.sh:green b.test.sh:green" \
  "$(ll_field "$(ll_ev "$RM2" ready)" suites) $(ll_verdicts "$RM2")"
RM3="$(ll_world)"
ll_wrow "$RM3" status=identified suites_allowed='a.test.sh b.test.sh' adopted_from=99999999-0000-4000-8000-000000000000
ll_redsuite "$RM3" T1 b
ll_verb "$RM3" T1
expect_eq "(r6g) an adopted row (adopted_from=, no launch row) stands as the launch row: proved on its suites, b red" \
  "1 a.test.sh,b.test.sh a.test.sh:green b.test.sh:red" "$LL_RC $(ll_field "$(ll_ev "$RM3" ready)" suites) $(ll_verdicts "$RM3")"
RM3b="$(ll_world)"
grep -v '|name=wx-T1|' "$(ll_roster "$RM3b")" > "$(ll_roster "$RM3b").n" && mv "$(ll_roster "$RM3b").n" "$(ll_roster "$RM3b")"
ll_verb "$RM3b" T1
expect_eq "(r6g) …while a roster with no row of the agent is refused no-launch-row (exit 2)" "2" "$LL_RC"
expect_contains "(r6g) …naming the row" "REFUSED reason=no-launch-row row=T1 roster=" "$LL_OUT"
ll_wrow "$RM3b" status=identified suites_allowed=a.test.sh adopted_from=99999999-0000-4000-8000-000000000000
ll_verb "$RM3b" T1
expect_eq "(r6g) …and the same tree with an adopted row of the agent lands (exit 0)" "0 a.test.sh" "$LL_RC $(ll_field "$(ll_ev "$RM3b" ready)" suites)"
K3B="$(ll_field "$(ll_ev "$RM3b" published)" commit)"
expect_nonempty "(r6g2-pre) the adopted row's landing was published" "$K3B"
expect_contains "(r6g2) the adopted-only row's landing is marked on its roster row (the mark reads the row the wall reads)" "|landed=${K3B}|" \
  "$(grep '|name=wx-T1|' "$(ll_roster "$RM3b")" | tail -1)"
expect_contains "(r6g2) …and the owed line is printed, naming the agent" "owed: complete task T1, then stop wx-T1" "$LL_OUT"
# THE MARK GOES TO THE WRITER `ready` HELD THE LANDING TO (wave-35 T7; burns debt row-writer-lookup). The
# launch line is wx-T1; the agent's latest row carries the same id under another name, wx-T1b, so
# `line_row_writer` answers wx-T1b. `_line_roster_mark` asks it too, and marks wx-T1b's row, never the
# launch line's name.
# fails-when: the landing is marked on wx-T1 while wx-T1b, the writer the landing was held to, carries none.
RM3c="$(ll_world)"
grep -v '|name=wx-T1|' "$(ll_roster "$RM3c")" > "$(ll_roster "$RM3c").n" && mv "$(ll_roster "$RM3c").n" "$(ll_roster "$RM3c")"
ll_wrow "$RM3c" status=intended suites_allowed=a.test.sh
printf '%s\n' "$(roster_row_fixture session="$WORLD_SID" name=wx-T1b agent_id=b00T1 plan="$(ll_plan "$RM3c")" \
  suites_source=declared status=identified suites_allowed=a.test.sh adopted_from=99999999-0000-4000-8000-000000000000)" \
  >> "$(ll_roster "$RM3c")"
ll_verb "$RM3c" T1
K3C="$(ll_field "$(ll_ev "$RM3c" published)" commit)"
expect_eq "(r6g3-pre) the row whose id moved to wx-T1b lands (exit 0)" "0" "$LL_RC"
expect_nonempty "(r6g3-pre) …and its landing was published" "$K3C"
expect_contains "(r6g3) the landing is marked on wx-T1b, the writer the landing was held to" "|landed=${K3C}|" \
  "$(grep '|name=wx-T1b|' "$(ll_roster "$RM3c")" | tail -1)"
expect_eq "(r6g3) …and the launch line's name carries no mark (r6g3 is the positive, same roster)" "" \
  "$(grep '|name=wx-T1|' "$(ll_roster "$RM3c")" | grep -F "|landed=${K3C}|")"
RM4="$(ll_world)"
ll_wide "$RM4" 'a.test.sh b.test.sh' held='2026-10-07T00:10:00Z waiting on T2'
ll_wrow "$RM4" status=identified suites_allowed='a.test.sh b.test.sh' extended='2026-10-07T00:20:00Z more time'
ll_redsuite "$RM4" T1 b
ll_verb "$RM4" T1
expect_eq "(r6h) a hold and an extend after the amend: still the amended set, b red (exit 1)" \
  "1 a.test.sh,b.test.sh a.test.sh:green b.test.sh:red" "$LL_RC $(ll_field "$(ll_ev "$RM4" ready)" suites) $(ll_verdicts "$RM4")"
RM4b="$(ll_world)"
ll_wrow "$RM4b" status=intended suites_allowed=a.test.sh
ll_wrow "$RM4b" status=identified suites_allowed=a.test.sh held='2026-10-07T00:10:00Z waiting on T2'
ll_wrow "$RM4b" status=identified suites_allowed=a.test.sh extended='2026-10-07T00:20:00Z more time'
ll_wrow "$RM4b" status=identified suites_allowed='a.test.sh b.test.sh' amended='2026-10-07T00:30:00Z widened'
ll_redsuite "$RM4b" T1 b
ll_verb "$RM4b" T1
expect_eq "(r6h) a hold and an extend BETWEEN the launch and the amend: the same" \
  "1 a.test.sh,b.test.sh a.test.sh:green b.test.sh:red" "$LL_RC $(ll_field "$(ll_ev "$RM4b" ready)" suites) $(ll_verdicts "$RM4b")"
RM4c="$(ll_world)"
ll_wide "$RM4c" 'a.test.sh b.test.sh'
ll_wrow "$RM4c" status=identified suites_allowed='a.test.sh b.test.sh' amended='2026-10-07T00:30:00Z widened' \
  landed=0123456789abcdef0123456789abcdef01234567 landed_at=2026-10-07T00:40:00Z
ll_verb "$RM4c" T1
expect_eq "(r6h) …and a landed mark after the amend: the same (exit 0)" "0 a.test.sh,b.test.sh" \
  "$LL_RC $(ll_field "$(ll_ev "$RM4c" ready)" suites)"
# One suite-name parser, the label's (brief.sh, `Lands-on:`): a bare name with or without `.test.sh`, a path by its
# basename; `run.sh` (the budget's full-runner token) is no suite. The refusal names the key the value came from.
RM5="$(ll_world)"
ll_wrow "$RM5" status=intended suites_allowed='a.test.sh run.sh'
ll_verb "$RM5" T1
expect_eq "(r6i) suites_allowed= naming run.sh is refused, naming that key (exit 2)" "2" "$LL_RC"
expect_contains "(r6i) …lands-on-unreadable, the row and suites_allowed=, not lands_on=" \
  "REFUSED reason=lands-on-unreadable row=T1 suites_allowed=a.test.sh run.sh" "$LL_OUT"
expect_contains "(r6i) …with the hand landing" "--by-hand --reason '<why>'" "$LL_OUT"
expect_false "(r6i) …and nothing is appended" test -e "$(ll_rec "$RM5")"
ll_wrow "$RM5" status=identified suites_allowed=a.test.sh amended='2026-10-07T00:30:00Z narrowed'
ll_verb "$RM5" T1
expect_eq "(r6i) …while the same tree, its current row naming a.test.sh, lands (exit 0)" "0 a.test.sh" \
  "$LL_RC $(ll_field "$(ll_ev "$RM5" ready)" suites)"
RM6="$(ll_world)"
ll_launch "$RM6" T1 'tests/a.test.sh run.sh'
ll_verb "$RM6" T1
expect_eq "(r6j) lands_on= naming run.sh is refused naming lands_on= (exit 2)" "2 REFUSED reason=lands-on-unreadable row=T1 lands_on=tests/a.test.sh run.sh" \
  "$LL_RC $(printf '%s' "$LL_OUT" | sed 's/^spawn-worktree: //; s/ — .*//')"
expect_false "(r6j) …and nothing is appended" test -e "$(ll_rec "$RM6")"
ll_launch "$RM6" T1 'tests/a.test.sh a'
ll_verb "$RM6" T1
expect_eq "(r6j) …while the same tree, its row naming a path and a bare name, lands on each as named, the path kept (exit 0)" "0 tests/a.test.sh,a.test.sh" \
  "$LL_RC $(ll_field "$(ll_ev "$RM6" ready)" suites)"
# THE MUTANTS: the launch-row read restored (the amend row lands with b unrun), and the fallback winning over lands_on=.
RM7="$(ll_world)"; HM7="$(ll_head "$RM7")"
ll_wide "$RM7" 'a.test.sh b.test.sh'
ll_redsuite "$RM7" T1 b
# The anchor (wave-35 T3, D16) is the mutant's precondition and its sed: `anchors check` names this line
# at any landing that moves the call out of line_row_writer (b86a4b6d did, and nothing said so).
anchor fn payload/scripts/lib/line.sh '_line_current_row ' line_row_writer 'false '
LL_MUTANT="$ANCHOR_SED" LL_MUTANT_FN=line_row_writer ll_drive "$RM7" T1 "$WORLD_ROOT/m7-T1.out"
ll_wait_file "$WORLD_ROOT/m7-T1.out.rc" 300
expect_eq "(r6em-pre) the mutant ran: the row entered the line, proved on a.test.sh alone" "a.test.sh a.test.sh:green" \
  "$(ll_field "$(ll_ev "$RM7" ready)" suites) $(ll_verdicts "$RM7")"
expect_eq "(r6em) MUTANT the launch-row read restored: the amended row lands with b unrun, red on the branch (the row can fail)" \
  "0 yes" "$(cat "$WORLD_ROOT/m7-T1.out.rc" 2>/dev/null) $([ "$(ll_head "$RM7")" != "$HM7" ] && echo yes || echo no)"
RM8="$(ll_world)"
printf '%s|row=T1|lands_on=a.test.sh\n' "$(roster_row_fixture status=intended session="$WORLD_SID" name=wx-T1 agent_id=b00T1 plan="$(ll_plan "$RM8")" \
  suites_allowed=b.test.sh suites_source=declared)" >> "$(ll_roster "$RM8")"
LL_MUTANT='s/\[ -n "\$v" \] || {/false || {/' LL_MUTANT_FN=_line_lands ll_drive "$RM8" T1 "$WORLD_ROOT/m8-T1.out"
ll_wait_file "$WORLD_ROOT/m8-T1.out.rc" 300
expect_eq "(r6cm) MUTANT suites_allowed= wins over lands_on=: the row is proved on b.test.sh (the row can fail)" "b.test.sh" \
  "$(ll_field "$(ll_ev "$RM8" ready)" suites)"
RM9="$(ll_world)"
printf '%s\n' "$(roster_row_fixture status=intended session="$WORLD_SID" name=wx-T1 agent_id=b00T1 plan="$(ll_plan "$RM9")" \
  suites_allowed=none suites_source=declared)" >> "$(ll_roster "$RM9")"
LL_MUTANT='s/\[ "\$key" = lands_on \] || return 3/:/' LL_MUTANT_FN=_line_lands ll_drive "$RM9" T1 "$WORLD_ROOT/m9-T1.out"
ll_wait_file "$WORLD_ROOT/m9-T1.out.rc" 300
expect_eq "(r6dm) MUTANT the absence arm removed: suites_allowed=none lands with no run (the row can fail)" "0 none" \
  "$(cat "$WORLD_ROOT/m9-T1.out.rc" 2>/dev/null) $(ll_field "$(ll_ev "$RM9" ready)" suites)"
# The parser, asked directly: the label's grammar.
expect_eq "(r6k) the suite-name parser: names, paths, run.sh, none" \
  "a.test.sh|a.test.sh,b.test.sh|tests/a.test.sh|none|FAIL|FAIL|FAIL" \
  "$(_line_suites a)|$(_line_suites 'a.test.sh, b')|$(_line_suites tests/a.test.sh)|$(_line_suites 'none docs')|$(_line_suites run.sh || echo FAIL)|$(_line_suites 'a.b' || echo FAIL)|$(_line_suites -x || echo FAIL)"
expect_eq "(r6k2) …a path keeps its directories, one spelling per file; no .., no absolute path, no empty or . directory" \
  "tests/a.test.sh|./a.test.sh|d/x.test.sh,x.test.sh|FAIL|FAIL|FAIL|FAIL|FAIL" \
  "$(_line_suites './tests/a, tests/a.test.sh')|$(_line_suites ./a)|$(_line_suites 'd/x x')|$(_line_suites ../a.test.sh || echo FAIL)|$(_line_suites /d/a.test.sh || echo FAIL)|$(_line_suites d//a.test.sh || echo FAIL)|$(_line_suites d/./a.test.sh || echo FAIL)|$(_line_suites d/run.sh || echo FAIL)"

# ---------------------------------------------------------------------------
section "§GATE: the line runs the suites the brief names, asks the gate before each start, and holds no width of its own"
#
# A fixture gate answers 2, then 5; seven named suites log their start and wait for a go file. x, named by no brief, is
# the project's declared floor, the old background switch on. A width of the line's own would start more or fewer.
GT_FIX='s|gate_width_ask "\$1"|bash "$LL_SIG/gate-fix.sh"|'
printf '#!/bin/bash\na=5; [ -e "$LL_SIG/g.asked" ] || { a=2; : > "$LL_SIG/g.asked"; }\necho "ask $a" >> "$LL_SIG/g.log"; echo "$a"\n' > "$LL_SIG/gate-fix.sh"
expect_contains "(g0-pre) the fixture gate is in _line_width_ask" 'bash "$LL_SIG/gate-fix.sh"' "$(declare -f _line_width_ask | sed "$GT_FIX")"
RG="$(ll_world)"; ll_launch "$RG" T1 'n1 n2 n3 n4 n5 n6 n7'
for s in n1 n2 n3 n4 n5 n6 n7 x; do
  printf '#!/bin/bash\necho "start %s" >> "$LL_SIG/g.log"\ni=0; while [ %s = 1 ] && [ ! -e "$LL_SIG/g-%s.go" ] && [ "$i" -lt 300 ]; do sleep 0.1; i=$((i + 1)); done\necho "PASS: %s"; echo; echo "%s.test.sh: 1/1 passed, 0 failed  sections=1 setup=0"\n' \
    "$s" "$([ "$s" = x ] && echo 0 || echo 1)" "$s" "$s" "$s" > "$RG/tests/$s.test.sh"
done
git -C "$RG" add tests && git -C "$RG" commit -qm "eight suites"
printf 'floor: bash tests/x.test.sh\nbackground-pass: on\n' > "$RG/.bionic/config.yaml"; world_machine 64 65536 40 0.5
LL_MUTANT="$GT_FIX" LL_MUTANT_FN=_line_width_ask ll_drive "$RG" T1 "$WORLD_ROOT/g.out"; G_BG=$!
ll_wait_lines "$LL_SIG/g.log" 3 300 && touch "$LL_SIG/g-n1.go"
ll_wait_lines "$LL_SIG/g.log" 9 300
expect_eq "(g1) asked before the first start and again as n1 ended, it starts exactly each answer: 2, then 5 beside n2" \
  "ask 2|start|start|ask 5|start|start|start|start|start" "$(sed 's/^start n[1-7]$/start/' "$LL_SIG/g.log" | paste -sd'|' -)"
touch "$LL_SIG"/g-n[1-7].go
ll_wait_file "$WORLD_ROOT/g.out.rc" 600 || ll_kill_bg "$G_BG"; KG="$(ll_last_cand "$RG" T1)"
expect_eq "(g2) the row lands on its seven suites: exit 0, the branch at its candidate" "0 $KG" "$(cat "$WORLD_ROOT/g.out.rc" 2>/dev/null) $(ll_head "$RG")"
expect_false "(g3) x, which no brief names, never ran, though the project declares it its floor" wait_for 2 grep -q '^start x$' "$LL_SIG/g.log"
( cd "$RG" && bash tests/x.test.sh >/dev/null )
expect_true "(g3) …while x run by hand logs its start (the control)" grep -q '^start x$' "$LL_SIG/g.log"
( unset LINE_WIDTH; _line_verdict_put "$(ll_plan "$RG")" T9 "$KG" z.test.sh absent - >/dev/null )
expect_eq "(g4) n1's verdict carries the gate's first answer as its width; one written with no answer asked carries -" "2 -" \
  "$(ll_field "$(ll_ev "$RG" verdict | grep -F '|suite=n1.test.sh|')" width) $(ll_field "$(ll_ev "$RG" verdict | grep -F '|suite=z.test.sh|')" width)"
world_machine 8 8192 40 0.5

# ---------------------------------------------------------------------------
section "§PROOF: the tool makes the proof; no stamp is read (AC-1.2)"
#
# A stamp is what 1.12.0's land judged: a line in the tree's `bionic-stamps`. Each world plants one
# that contradicts the candidate's own run; the run decides.
ll_stamp() {  # <root> <row> <rc> — a clean stamp at the row's head naming a.test.sh
  local t="$1/.worktrees/$2"
  printf 'stamp/v1|head=%s|dirty=0|rc=%s|at=2026-10-06T00:00:00Z|suites=a.test.sh|cmd=bash tests/a.test.sh\n' \
    "$(git -C "$t" rev-parse HEAD)" "$3" >> "$(git -C "$t" rev-parse --absolute-git-dir)/bionic-stamps"
}
RQ="$(ll_rworld)"; HQ="$(ll_head "$RQ")"
ll_redsuite "$RQ" T1 a; ll_stamp "$RQ" T1 0
expect_false "(q1-pre) the planted stamp is green proof to 1.12.0's reader" \
  _wt_stale_proof "$RQ/.worktrees/T1" "$(git -C "$RQ/.worktrees/T1" rev-parse HEAD)"
ll_verb "$RQ" T1
expect_eq "(q1) a green stamp beside a red candidate: red (exit 1)" "1" "$LL_RC"
expect_match "(q1) …printing RED" "RED T1 a.test.sh *" "$LL_OUT"
expect_eq "(q1) …and nothing is published" "$HQ" "$(ll_head "$RQ")"
RQ2="$(ll_rworld)"; ll_stamp "$RQ2" T1 1
expect_true "(q2-pre) the planted stamp is red to 1.12.0's reader" \
  _wt_stale_proof "$RQ2/.worktrees/T1" "$(git -C "$RQ2/.worktrees/T1" rev-parse HEAD)"
ll_verb "$RQ2" T1
expect_eq "(q2) a red stamp beside a green candidate: published (exit 0)" "0" "$LL_RC"

# ---------------------------------------------------------------------------
section "§RED: green publishes, the row's red publishes nothing (AC-1.5)"
RX="$(ll_rworld)"; HX="$(ll_head "$RX")"
ll_redsuite "$RX" T1 a
ll_verb "$RX" T1
KX="$(ll_field "$(ll_ev "$RX" candidate)" commit)"
LX="$RX/.bionic/docs/record/wave-x/line/T1-a-${KX:0:12}.log"
expect_eq "(x1) a red candidate: ready exits 1" "1" "$LL_RC"
expect_eq "(x1) …printing RED, the suite and the log's path" "RED T1 a.test.sh $LX" "$LL_OUT"
expect_contains "(x1) …a log that holds the failing line" "FAIL: a planted red" "$(cat "$LX" 2>/dev/null)"
expect_eq "(x1) the branch's head is unchanged" "$HX" "$(ll_head "$RX")"
expect_regex "(x2) the verdict is red on the candidate" "\\|commit=${KX}\\|suite=a.test.sh\\|result=red\\|log=${LX}\\|" "$(ll_ev "$RX" verdict)"
expect_regex "(x2) …and the row is returned, naming the log" "^line/v1\\|ev=returned\\|row=T1\\|why=red\\|detail=${LX}\\|at=" "$(ll_ev "$RX" returned)"
expect_eq "(x3) T1 leaves the line" "" "$(line_state "$(ll_plan "$RX")")"
RC1="$(ll_rworld)"; HC1="$(ll_head "$RC1")"
printf 'one\n' > "$RC1/T1.txt"; git -C "$RC1" add T1.txt; git -C "$RC1" commit -qm "the branch writes T1.txt too"
HC1="$(ll_head "$RC1")"
ll_verb "$RC1" T1
expect_eq "(x4) a conflict with the accepted head returns the row (exit 1)" "1" "$LL_RC"
expect_eq "(x4) …printing CONFLICT and the files" "CONFLICT T1 T1.txt" "$LL_OUT"
expect_regex "(x4) …returned why=conflict" "^line/v1\\|ev=returned\\|row=T1\\|why=conflict\\|detail=T1.txt\\|" "$(ll_ev "$RC1" returned)"
expect_eq "(x4) …nothing published" "$HC1" "$(ll_head "$RC1")"
# THE USER'S ORDER: while one stands the line starts no suite and returns the entry with the user's words; lifted, the same ready runs it.
RO="$(ll_rworld)"; HO="$(ll_head "$RO")"; ll_order() { awk -v l="$2" '/^## Tasks/ { print l } { print }' "$(ll_plan "$1")" > "$(ll_plan "$1").n" && mv "$(ll_plan "$1").n" "$(ll_plan "$1")"; }
ll_order "$RO" 'order: given 2026-10-20T00:00:00Z "no suites, I said"'; ll_verb "$RO" T1
expect_eq "(x5) an order standing: ready exits 1" "1" "$LL_RC"
expect_contains "(x5) …printing the user's words" 'the user'"'"'s order stands: "no suites, I said"' "$LL_OUT"
expect_eq "(x5) …no suite started and the row is returned for the order" "0 $HO order" "$(ll_ev "$RO" verdict | wc -l | tr -d ' ') $(ll_head "$RO") $(ll_field "$(ll_ev "$RO" returned)" why)"
ll_order "$RO" 'order: lifted 2026-10-20T00:01:00Z "go on"'; ll_verb "$RO" T1
expect_eq "(x6) once lifted, the same ready runs the suite and lands (exit 0, a green verdict)" "0 green" "$LL_RC $(ll_field "$(ll_ev "$RO" verdict)" result)"

# ---------------------------------------------------------------------------
section "§AHEAD-RED: a refused row holds nothing behind it (AC-1.6)"
#
# T1 lands on a.test.sh, which its commit makes red once released; T2 lands on b.test.sh, which
# records each run's head and waits. T2's candidate is built ahead, on T1's; under D22 the gate holds
# T2's run (answer 0) while T1's run is open. T1 turns red and is returned; T2 is rebuilt on the
# accepted head, proved and published without T1. T2's go file is planted before T1's, so the outcome
# never depends on which landing runs first. Since wave-38 T30 each ready holds its landing's lease, so
# T1 stays the older landing in the gap between its run and its red judge's (A-T6-10, now closed; §GAP
# pins the gap), and each lease is closed when its landing is returned or published.
# ll_nth_cand to ll_open_landing: hoisted to tests/landing-line.prelude.sh (part 2 calls them)
ll_ahead_world() {  # <tag> -> root
  local r
  r="$(ll_rworld)" || return 1
  ll_commit_suite "$r" T1 a "$(ll_block_body "$1-T1" a red)"
  ll_commit_suite "$r" T2 b "$(ll_block_body "$1-T2" b green)"
  printf '%s' "$r"
}
RA="$(ll_ahead_world a)"; HA="$(ll_head "$RA")"; T1A="$(git -C "$RA/.worktrees/T1" rev-parse HEAD)"
ll_verb_bg "$RA" T1 "$WORLD_ROOT/a-T1.out"
expect_true "(a0-pre) T1's run started" ll_wait_lines "$LL_SIG/a-T1.runs" 1
ll_verb_bg "$RA" T2 "$WORLD_ROOT/a-T2.out"
expect_true "(a0-pre) T2's first candidate is built" ll_wait_cand "$RA" T2
expect_false "(a0) no run of T2 starts in the 2 s while T1's run is open" wait_for 2 ll_has_lines "$LL_SIG/a-T2.runs" 1
KA1="$(ll_nth_cand "$RA" T1)"
expect_eq "(a0) T2's first candidate is built on T1's" "$KA1" "$(git -C "$RA" rev-parse "$(ll_nth_cand "$RA" T2)^1")"
expect_eq "(a0) …T1's run the open landing run, and none of T2's on it" "T1 0" "$(ll_open_landing | sed 's/.*://') $(ll_lines "$LL_SIG/a-T2.runs")"
RA_K1="$(_line_landing_key "$RA" "$(ll_plan "$RA")" T1)"; RA_K2="$(_line_landing_key "$RA" "$(ll_plan "$RA")" T2)"
expect_eq "(a0) …each ready holds its landing's lease, carried (wave-38 T30)" "yes yes" \
  "$(ll_lease_carried "$RA_K1" && echo yes) $(ll_lease_carried "$RA_K2" && echo yes)"
expect_true "(a0) …T1's opened first: T1 is the older landing" test "$(ll_lease_field "$RA_K1" seq)" -lt "$(ll_lease_field "$RA_K2" seq)"
touch "$LL_SIG/a-T2.go" "$LL_SIG/a-T1.go"
ll_wait_file "$WORLD_ROOT/a-T1.out.rc" 300
expect_eq "(a1) T1 is red: exit 1" "1" "$(cat "$WORLD_ROOT/a-T1.out.rc" 2>/dev/null)"
ll_wait_file "$WORLD_ROOT/a-T2.out.rc" 300
KA2="$(ll_nth_cand "$RA" T2 '$')"
expect_nonempty "(a2-pre) T2 was rebuilt" "$KA2"
expect_eq "(a2) T2 publishes: exit 0, the branch at its latest candidate, which is built on the accepted head" "0 $KA2 $HA" \
  "$(cat "$WORLD_ROOT/a-T2.out.rc" 2>/dev/null) $(ll_head "$RA") $(git -C "$RA" rev-parse "${KA2}^1" 2>/dev/null)"
[ "$(cat "$WORLD_ROOT/a-T2.out.rc" 2>/dev/null)" = 0 ] || printf 'DIAG (a2) T2 said: %s | its events: %s\n' \
  "$(tr '\n' ' ' < "$WORLD_ROOT/a-T2.out" 2>/dev/null)" "$(grep '|row=T2|' "$(ll_rec "$RA")" 2>/dev/null | cut -d'|' -f2,4- | tr '\n' ' ')"
expect_eq "(a3) …proved by its last run, on that candidate" "$KA2" "$(tail -1 "$LL_SIG/a-T2.runs" 2>/dev/null)"
expect_regex "(a3) T1 stays returned, red" "^line/v1\\|ev=returned\\|row=T1\\|why=red\\|" "$(ll_ev "$RA" returned)"
expect_eq "(a3) …and only T2 is published" "T2" "$(ll_ev "$RA" published | sed 's/.*|row=\([^|]*\)|.*/\1/' | tr '\n' ' ' | sed 's/ $//')"
expect_eq "(a5) both leases are closed: T1's at its return, T2's at its publish (wave-38 T30)" "no no" \
  "$(ll_lease_has "$RA_K1") $(ll_lease_has "$RA_K2")"
# THE DISCARD (D5): a run whose base is replaced while it runs is stopped, written `discarded`, and the
# candidate rebuilt. Under D22 a row behind never runs while the row ahead runs, so the base is moved here
# by a plain commit on the working branch under one landing's live run.
ll_move_head() {  # <root> <tag> — a plain commit on the working branch, at its root
  printf '%s\n' "$2" > "$1/moved-$2.txt" && git -C "$1" add "moved-$2.txt" && git -C "$1" commit -qm "a plain commit on the working branch ($2)"
}
RA3="$(ll_rworld)"; ll_commit_suite "$RA3" T1 a "$(ll_block_body d-T1 a green)"
ll_verb_bg "$RA3" T1 "$WORLD_ROOT/d-T1.out"
expect_true "(a4-pre) T1's first run started" ll_wait_lines "$LL_SIG/d-T1.runs" 1
ll_move_head "$RA3" d; HA3="$(ll_head "$RA3")"
expect_true "(a4) the head moved under the live run: T1 is rebuilt and proved again while its first run never ended" ll_wait_lines "$LL_SIG/d-T1.runs" 2 300
expect_regex "(a4) …its first run discarded" \
  "\\|row=T1\\|commit=$(head -1 "$LL_SIG/d-T1.runs")\\|suite=a.test.sh\\|result=discarded\\|" "$(ll_ev "$RA3" verdict)"
expect_eq "(a4) …the second candidate built on the moved head" "$HA3" "$(git -C "$RA3" rev-parse "$(sed -n 2p "$LL_SIG/d-T1.runs")^1")"
touch "$LL_SIG/d-T1.go"; ll_wait_file "$WORLD_ROOT/d-T1.out.rc" 300
expect_eq "(a4) T1 publishes its second candidate: exit 0" "0 $(sed -n 2p "$LL_SIG/d-T1.runs")" "$(cat "$WORLD_ROOT/d-T1.out.rc" 2>/dev/null) $(ll_head "$RA3")"
# MUTANT: the discard removed. T1's first run is never stopped when its base is replaced: no second
# run starts while the first waits, and no `discarded` verdict is appended.
RA2="$(ll_rworld)"; ll_commit_suite "$RA2" T1 a "$(ll_block_body m-T1 a green)"
# The watch over every live runner is the drain's (wave-37 T1; D3): `_line_drain_next` starts and watches them.
LL_MUTANT='s/_line_replaced "\$2" "\$1" "\$3" "\$5"/false/' LL_MUTANT_FN=_line_drain_next ll_drive "$RA2" T1 "$WORLD_ROOT/m-T1.out"
expect_true "(a4m-pre) the mutant ran: T1's first run started" ll_wait_lines "$LL_SIG/m-T1.runs" 1
ll_move_head "$RA2" m
sleep 3
expect_eq "(a4m) MUTANT discard removed: no second run while the first waits (the rows can fail)" "1" "$(ll_lines "$LL_SIG/m-T1.runs")"
expect_eq "(a4m) …and no discarded verdict" "" "$(ll_ev "$RA2" verdict | grep 'result=discarded')"
touch "$LL_SIG/m-T1.go"; ll_wait_file "$WORLD_ROOT/m-T1.out.rc" 300

# ---------------------------------------------------------------------------
section "§SIDE: two landings take the gate's width one at a time; the younger's candidate is still built ahead (AC-1.7 as wave-38 D22 orders it)"
#
# D22 (design-ledger Δ16): the gate answers width to the oldest active landing and 0 to a younger one
# until the older's lease closes (wave-38 T30), and the drain starts exactly the answer (D21). So T2's candidate
# is built on T1's while T1's run holds, but T2's run starts only once T1's has ended. Both publish, in
# order. The answer is read from the gate itself, not inferred from a run that has not started.
RW="$(ll_rworld)"
ll_commit_suite "$RW" T1 a "$(ll_block_body s-T1 a green)"
ll_commit_suite "$RW" T2 b "$(ll_block_body s-T2 b green)"
ll_verb_bg "$RW" T1 "$WORLD_ROOT/s-T1.out"
ll_wait_lines "$LL_SIG/s-T1.runs" 1
ll_verb_bg "$RW" T2 "$WORLD_ROOT/s-T2.out"
expect_true "(w1-pre) T2's candidate is built while T1's run holds" ll_wait_cand "$RW" T2
expect_false "(w1) no run of T2 starts in the 2 s while T1's run is open" wait_for 2 ll_has_lines "$LL_SIG/s-T2.runs" 1
SW_KEY="$(ll_open_landing)"
expect_eq "(w1) T1's run is the one open landing run, tagged with T1's landing key" "a.test.sh|T1" \
  "$(for f in "$BIONIC_GATE_DIR"/requests/*; do
       grep -q '^admitted=' "$f" && ! grep -q '^ended=' "$f" && grep -q '^kind=landing$' "$f" && sed -n 's/^key=//p' "$f"
     done | sort | tr '\n' ' ' | sed 's/ $//')|${SW_KEY##*:}"
expect_eq "(w1) …the gate answers T2's landing 0 while it is open" "0" "$(ll_width_ask "${SW_KEY%:*}:T2")"
expect_eq "(w1) …and T2's candidate is built on T1's" "$(ll_nth_cand "$RW" T1)" "$(git -C "$RW" rev-parse "$(ll_nth_cand "$RW" T2)^1")"
touch "$LL_SIG/s-T1.go"
expect_true "(w2-pre) T2's run starts once T1's has ended" ll_wait_lines "$LL_SIG/s-T2.runs" 1
touch "$LL_SIG/s-T2.go"
ll_wait_file "$WORLD_ROOT/s-T1.out.rc" 300; ll_wait_file "$WORLD_ROOT/s-T2.out.rc" 300
expect_eq "(w2) both publish" "0 0" "$(cat "$WORLD_ROOT/s-T1.out.rc" 2>/dev/null) $(cat "$WORLD_ROOT/s-T2.out.rc" 2>/dev/null)"
expect_eq "(w2) …in order, T2's run on the candidate built on T1's: one run each" "T1 T2 1 1 $(ll_nth_cand "$RW" T2)" \
  "$(ll_ev "$RW" published | sed 's/.*|row=\([^|]*\)|.*/\1/' | tr '\n' ' ')$(ll_lines "$LL_SIG/s-T1.runs") $(ll_lines "$LL_SIG/s-T2.runs") $(head -1 "$LL_SIG/s-T2.runs" 2>/dev/null)"

# ---------------------------------------------------------------------------
section "§WITHIN: no suite starts whose promised seconds exceed the time left (D3)"
# The gate keeps each suite's duration under its project (wave-33 T1; Δ10): the 600 s is planted
# in the fixture repository the landing runs in.
RN="$(ll_world)"; ll_launch "$RN" T1 c
( cd "$RN" && world_cost c.test.sh 600 )
( cd "$RN" && world_suite c green >/dev/null ) && git -C "$RN" add tests/c.test.sh && git -C "$RN" commit -qm "suite c"
REQN="$(ls "$BIONIC_GATE_DIR/requests" 2>/dev/null | wc -l | tr -d ' ')"
ll_verb "$RN" T1 --within 60
expect_eq "(n1) a suite promising 600 s with 60 s left: exit 75" "75" "$LL_RC"
expect_eq "(n1) …printing WAITING and the same command (§WHY reads the reason after it)" "WAITING T1 — run again: bash ${SPAWN} ready --within 60" "$(printf '%s\n' "$LL_OUT" | grep '^WAITING ' | head -n 1)"
expect_eq "(n1) …nothing run: no verdict, no log, no gate request" "0 0 $REQN" \
  "$(ll_ev "$RN" verdict | awk 'END { print NR }') $(ls "$RN/.bionic/docs/record/wave-x/line" 2>/dev/null | wc -l | tr -d ' ') $(ls "$BIONIC_GATE_DIR/requests" | wc -l | tr -d ' ')"
expect_eq "(n1) …the entry kept, its carrier gone" "T1 no" "$(line_state "$(ll_plan "$RN")" | cut -f1,4 | tr '\t' ' ')"
ll_verb "$RN" T1 --within 900
expect_eq "(n2) with the time, the same command lands it" "0" "$LL_RC"
# ll_req_last: hoisted to tests/landing-line.prelude.sh (part 2 calls it)
N2V="$(ll_ev "$RN" verdict)"
expect_regex "(n2f-pre) the gate's request for the run holds its promise and its admission and end" '^600 [0-9]+$' \
  "$(ll_req_last c.test.sh promise) $(ll_req_last c.test.sh actual)"
expect_eq "(n2f) AC-4.2 the verdict carries promised=600 and actual= the gate's ended less admitted, after width=" \
  "600 $(ll_req_last c.test.sh actual) yes" \
  "$(ll_field "$N2V" promised) $(ll_field "$N2V" actual) $(printf '%s\n' "$N2V" | grep -qE '\|width=[^|]+\|promised=600\|actual=[0-9]+\|at=' && echo yes)"
# AC-4.3 WITH TWO SUITES: a (5 s) fits in 60 s, c (600 s) does not. ready prints the total, runs a, and waits c:
# WAITING exit 75, a's verdict written, nothing started for c.
RN5="$(ll_world)"; ll_launch "$RN5" T1 a,c
( cd "$RN5" && world_cost a.test.sh 5 && world_cost c.test.sh 600 )
( cd "$RN5" && world_suite a green >/dev/null && world_suite c green >/dev/null ) && git -C "$RN5" add tests/a.test.sh tests/c.test.sh \
  && git -C "$RN5" commit -qm "suites a and c"
N5_C="$(grep -l '^key=c.test.sh$' "$BIONIC_GATE_DIR"/requests/[0-9]* 2>/dev/null | awk 'END { print NR }')"
ll_verb "$RN5" T1 --within 60
expect_eq "(n5) AC-4.3 a,c with 60 s: promised 605s of 60s first, then WAITING, exit 75" "75|promised 605s of 60s|WAITING T1 — run again: bash ${SPAWN} ready --within 60" \
  "$LL_RC|$(printf '%s\n' "$LL_OUT" | head -n 1)|$(printf '%s\n' "$LL_OUT" | grep '^WAITING ' | head -n 1)"
expect_eq "(n5) …waiting on c, whose promise the time left cannot hold" "waiting: suite c.test.sh promises 600s and" \
  "$(printf '%s\n' "$LL_OUT" | grep '^waiting: ' | head -n 1 | cut -d' ' -f1-6)"
expect_eq "(n5) …a ran and is green; c has no verdict and no gate request: it was waited, not started short" "a.test.sh:green $N5_C" \
  "$(ll_ev "$RN5" verdict | while IFS= read -r v; do printf '%s:%s ' "$(ll_field "$v" suite)" "$(ll_field "$v" result)"; done | sed 's/ $//') $(grep -l '^key=c.test.sh$' "$BIONIC_GATE_DIR"/requests/[0-9]* 2>/dev/null | awk 'END { print NR }')"
RN6="$(ll_world)"; ll_launch "$RN6" T1 a,c; ( cd "$RN6" && world_cost a.test.sh 5 && world_cost c.test.sh 600 && world_suite c green >/dev/null )
git -C "$RN6" add tests/c.test.sh && git -C "$RN6" commit -qm "suite c" && git -C "$RN6/.worktrees/T1" merge -q --no-edit wave/x
git -C "$RN6/.worktrees/T1" rm -q tests/c.test.sh && git -C "$RN6/.worktrees/T1" commit -qm "T1: c removed"; ll_verb "$RN6" T1 --within 60
expect_eq "(n6) AC-10.3 a,c, c on the accepted head and removed by the row: the promised total leaves c out, 5s of 60s" "promised 5s of 60s" "$(printf '%s\n' "$LL_OUT" | head -n 1)"
# THE LOOKUP NAMES THE LANDING TREE (wave-33 T1; Δ10). Durations are keyed by project, so
# `_line_time_for` reads the landing tree's, wherever the carrier stands: asked from outside every
# repository (the world's root), it still finds the fixture repository's 600 s.
ll_time_from_outside() {  # <deadline offset> -> "<printed> rc=<n>"
  ( cd "$WORLD_ROOT" && . "$REPO/payload/scripts/lib/gate.sh" 2>/dev/null \
      && . "$REPO/payload/scripts/lib/line.sh" 2>/dev/null \
      && o="$(_line_time_for c.test.sh "$(( $(_res_now) + $1 ))" "$RN")"; echo "$o rc=$?" )
}
expect_eq "(n4) asked from outside the repository with 900 s left, the gate may take 300 (900 less the 600 recorded)" \
  "300 rc=0" "$(ll_time_from_outside 900)"
expect_eq "(n4) …and with 60 s left the landing tree's 600 s refuses it (rc 1)" " rc=1" "$(ll_time_from_outside 60)"
RN2="$(ll_world)"; ll_launch "$RN2" T1 c
( cd "$RN2" && world_suite c green >/dev/null ) && git -C "$RN2" add tests/c.test.sh && git -C "$RN2" commit -qm "suite c"
LL_MUTANT='s/exit 1/exit 0/' LL_MUTANT_FN=_line_time_for ll_drive "$RN2" T1 "$WORLD_ROOT/n-T1.out" 60
ll_wait_file "$WORLD_ROOT/n-T1.out.rc" 300
expect_eq "(n3m) MUTANT the time check removed: the suite starts past its time (the rows can fail)" "0 green" \
  "$(cat "$WORLD_ROOT/n-T1.out.rc" 2>/dev/null) $(ll_field "$(ll_ev "$RN2" verdict)" result)"

section "§TOO-LONG: a Lands-on command is held to the suite bar as a suite is"
RL="$(ll_world)"; ll_launch "$RL" T1 '`bash%20c.test.sh`'; ( cd "$RL" && world_cost "bash c.test.sh" 700 ); ll_verb "$RL" T1
expect_eq "(tl1) a command promising 700 s: refused, exit 1, nothing entered the line" "1 too-long 0" "$LL_RC $(printf '%s\n' "$LL_OUT" | awk '/^too-long /{ print $1 }') $(ll_ev "$RL" ready | awk 'END { print NR }')"

# ---------------------------------------------------------------------------
section "§GUARD (ready half): a row that commits .bionic is refused before any landing tree (AC-14.1)"
RU="$(ll_rworld)"; HU="$(ll_head "$RU")"
git -C "$RU/.worktrees/T1" add -f .bionic && git -C "$RU/.worktrees/T1" commit -qm "T1: the link, committed"
TU="$(git -C "$RU/.worktrees/T1" rev-parse HEAD)"
ll_verb "$RU" T1
expect_eq "(u1) ready exits 1" "1" "$LL_RC"
expect_eq "(u1) …printing GUARD, the path and the commit first" "GUARD T1 .bionic $TU" "$(printf '%s\n' "$LL_OUT" | head -1)"
expect_false "(u1) …before any landing tree exists" test -e "$RU/.bionic/tmp/landing"
RU2="$(ll_rworld)"; HU2="$(ll_head "$RU2")"
git -C "$RU2/.worktrees/T1" add -f .bionic && git -C "$RU2/.worktrees/T1" commit -qm "T1: the link, committed"
TU2="$(git -C "$RU2/.worktrees/T1" rev-parse HEAD)"
LL_MUTANT='s/_wt_bionic_committed "\$root" "\$acc" "\$head"/false/' LL_MUTANT_FN=line_ready ll_drive "$RU2" T1 "$WORLD_ROOT/u-T1.out"
ll_wait_file "$WORLD_ROOT/u-T1.out.rc" 300
expect_true "(u2m) MUTANT the ready guard removed: a landing tree is built first (the row can fail)" test -d "$RU2/.bionic/tmp/landing/1"
expect_eq "(u2m) …and the publish's own guard still refuses it, GUARD first, nothing published" "1 GUARD T1 .bionic $TU2 $HU2" \
  "$(cat "$WORLD_ROOT/u-T1.out.rc" 2>/dev/null) $(head -1 "$WORLD_ROOT/u-T1.out") $(ll_head "$RU2")"

# ---------------------------------------------------------------------------
section "§ANCHORS: ready checks every anchor on the candidate and refuses a moved one (wave-35 T3; D16, AC-7.2)"
#
# The accepted head carries lib/line.sh and tests/c.test.sh, whose anchor inserts before a comment in it.
# T1 takes the head, then rewords (or leaves) that comment, and lands on a.test.sh alone: c.test.sh is
# never run, so only the check over every suite in the tree can see the anchor it moved.
ll_anchor_world() {  # <comment T1 commits> -> root; the head anchored, T1's row on a.test.sh
  local r t
  r="$(ll_rworld)" || return 1
  t="$r/.worktrees/T1"
  mkdir -p "$r/lib"
  printf '%s\n' '#!/bin/bash' '  # THE ANCHORED COMMENT' 'echo shipped' > "$r/lib/line.sh"
  printf '%s\n' '#!/bin/bash' '. "$(dirname "$0")/lib/assert.sh"' \
    "anchor insert lib/line.sh '  # THE ANCHORED COMMENT' 'echo mutant' \"\$TMPDIR/m\"" > "$r/tests/c.test.sh"
  git -C "$r" add lib/line.sh tests/c.test.sh && git -C "$r" commit -qm "head: an anchored comment"
  git -C "$t" merge -q --no-edit wave/x
  printf '%s\n' '#!/bin/bash' "$1" 'echo shipped, edited' > "$t/lib/line.sh"
  git -C "$t" commit -qam "T1: line.sh edited"
  printf '%s' "$r"
}
RAN="$(ll_anchor_world '  # THE ANCHORED COMMENT')"; HAN="$(ll_head "$RAN")"
ll_verb "$RAN" T1
expect_eq "(an1-pre) a row that keeps the anchored comment lands (exit 0), the check run over the candidate" "0" "$LL_RC"
expect_contains "(an1-pre) …printing LANDED" "LANDED T1 " "$LL_OUT"
RAM="$(ll_anchor_world '  # THE COMMENT, REWORDED')"; HAM="$(ll_head "$RAM")"
ll_verb "$RAM" T1
expect_eq "(an1) the row that rewords it, landing on a.test.sh, is refused (exit 2)" "2" "$LL_RC"
expect_contains "(an1) …saying the anchor moved, for this row" "REFUSED reason=anchor-moved row=T1" "$LL_OUT"
expect_contains "(an1) …naming the suite and line whose anchor it moved" \
  "MOVED tests/c.test.sh:3 insert lib/line.sh found=0" "$LL_OUT"
expect_eq "(an1) …and nothing is published" "$HAM" "$(ll_head "$RAM")"
expect_eq "(an1) …the entry is returned, why=anchor-moved" "anchor-moved" \
  "$(ll_field "$(ll_ev "$RAM" returned)" why)"
expect_eq "(an1) …before any suite ran on the candidate" "" "$(ll_ev "$RAM" verdict)"
expect_nonempty "(an1) …over a candidate that was built" "$(ll_ev "$RAM" candidate)"
AN_CHECK="$(bash "$REPO/hooks/session-poker.sh" anchors check "$REPO" 2>&1)"; AN_RC=$?
expect_eq "(an2) session-poker.sh anchors check on the shipped tree exits 0" "0" "$AN_RC"
expect_empty "(an2) …and names no moved anchor" "$AN_CHECK"
expect_contains "(an2) …over an index that holds this suite's own anchor" "tests/landing-line-1.test.sh" \
  "$(bash "$REPO/hooks/session-poker.sh" anchors index "$REPO" 2>&1)"

# ============================================================================ what a red means (wave-28 T5)
#
# REQ-9, D8: a run with no verdict (a signal, a failed start, no end line) keeps the entry's place
# and the suite is asked again; a second sets the entry `stalled` (exit 70). A red is the row's only
# when it is new: the suite is run once at the accepted head in the landing tree, remembered per head,
# and a candidate whose failing lines all fail there too is `standing`, not the row's. The declared
# debt is §LAND-DEBT's (tests/worktree.test.sh). Each suite below ends as the harness ends one: `PASS:`
# and `FAIL:` lines, then the verdict line `<file>: <p>/<t> passed, <f> failed …`.
ll_flaky_body() {  # <tag> <name> <runs with no verdict> <kill|none> — later runs are green
  local cut="kill -9 \$\$"
  [ "$4" = none ] && cut="exit 0"
  printf 'n=$(cat "$LL_SIG/%s.n" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" > "$LL_SIG/%s.n"\necho "PASS: run $n"\nif [ "$n" -le %s ]; then %s; fi\necho; echo "%s.test.sh: 1/1 passed, 0 failed  sections=1 setup=0"; exit 0\n' \
    "$1" "$1" "$3" "$cut" "$2"
}
# ll_results, ll_last_cand and ll_kill_bg: hoisted to tests/landing-line.prelude.sh (part 2 calls them)

# ---------------------------------------------------------------------------
section "§NOVERDICT: a run with no verdict sends nothing back; the suite is asked again (AC-9.1)"
RV="$(ll_rworld)"
ll_commit_suite "$RV" T1 a "$(ll_flaky_body v1 a 1 kill)"
ll_verb "$RV" T1
KV="$(ll_last_cand "$RV" T1)"
expect_nonempty "(v1-pre) a candidate was built" "$KV"
expect_eq "(v1) a run killed by a signal, then a green one: ready exits 0" "0" "$LL_RC"
expect_match "(v1) …printing LANDED" "LANDED T1 ${KV}*" "$LL_OUT"
expect_eq "(v1) the suite was asked again on the one candidate: none, then green" "none green" "$(ll_results "$RV" T1 "$KV")"
expect_regex "(v1) …the none verdict names its own log" \
  "\\|commit=${KV}\\|suite=a.test.sh\\|result=none\\|log=${RV}/.bionic/docs/record/wave-x/line/T1-a-${KV:0:12}.log\\|" "$(ll_ev "$RV" verdict)"
expect_eq "(v1) the row is published, never returned" "T1|" \
  "$(ll_ev "$RV" published | sed 's/.*|row=\([^|]*\)|.*/\1/')|$(ll_ev "$RV" returned)"
RV2="$(ll_rworld)"
ll_commit_suite "$RV2" T1 a "$(ll_flaky_body v2 a 1 none)"
ll_verb "$RV2" T1
KV2="$(ll_last_cand "$RV2" T1)"
expect_eq "(v2) a run that exits 0 with no end line is no verdict, not green: none, then green, published" "0 none green" \
  "$LL_RC $(ll_results "$RV2" T1 "$KV2")"

# ---------------------------------------------------------------------------
section "§STALLED: a second run with no verdict stalls the entry; no third run starts; the line passes over it (AC-9.2)"
RT="$(ll_rworld)"; HT="$(ll_head "$RT")"
( cd "$RT/.worktrees/T1" && world_suite a none >/dev/null ) && git -C "$RT/.worktrees/T1" commit -qam "T1: a ends early"
ll_verb "$RT" T1
KT="$(ll_last_cand "$RT" T1)"
LT1="$RT/.bionic/docs/record/wave-x/line/T1-a-${KT:0:12}.log"; LT2="$RT/.bionic/docs/record/wave-x/line/T1-a-${KT:0:12}-2.log"
expect_eq "(t1) two runs with no end line: ready exits 70" "70" "$LL_RC"
expect_eq "(t1) …printing STALLED and both logs" "STALLED T1 ${LT1},${LT2}" "$LL_OUT"
expect_regex "(t1) …one stalled event naming both logs" "^line/v1\\|ev=stalled\\|row=T1\\|logs=${LT1},${LT2}\\|at=[0-9T:-]+Z$" "$(ll_ev "$RT" stalled)"
expect_eq "(t1) …two runs, no third" "none none" "$(ll_results "$RT" T1 "$KT")"
expect_eq "(t1) …the entry kept on the line, stalled, nothing returned or published" "T1 stalled||$HT" \
  "$(line_state "$(ll_plan "$RT")" | cut -f1,7 | tr '\t' ' ')|$(ll_ev "$RT" returned)|$(ll_head "$RT")"
RT2="$(ll_rworld)"
( cd "$RT2/.worktrees/T1" && world_suite a kill >/dev/null ) && git -C "$RT2/.worktrees/T1" commit -qam "T1: a is killed"
ll_verb "$RT2" T1
expect_eq "(t2) two runs killed by a signal: exit 70, two none verdicts" "70 none none" "$LL_RC $(ll_results "$RT2" T1 "$(ll_last_cand "$RT2" T1)")"
RT3="$(ll_world)"; ll_launch "$RT3" T1 z
ll_verb "$RT3" T1
expect_eq "(t3) a suite that cannot start (the candidate has no tests/z.test.sh): exit 70, two none verdicts" "70 none none" \
  "$LL_RC $(ll_results "$RT3" T1 "$(ll_last_cand "$RT3" T1)")"
# (t4) the publish passes over a stalled entry ahead, as the base rule does (read-adversarial-p8 #3).
RT4="$(ll_world)"; HT4="$(ll_head "$RT4")"
ll_ready "$RT4" T1 "$(ll_carrier)" >/dev/null; ll_cand "$RT4" T1 "$HT4" >/dev/null
line_event "$(ll_plan "$RT4")" stalled row=T1 logs=x.log,y.log >/dev/null
ll_ready "$RT4" T2 "$(ll_carrier)" >/dev/null; KT4="$(ll_cand "$RT4" T2 "$HT4")"; ll_green "$RT4" T2 "$KT4"
expect_eq "(t4-pre) T1 is present and stalled ahead of T2, whose base the base rule makes the accepted head" \
  "T1 yes stalled|T2 yes $HT4" \
  "$(line_state "$(ll_plan "$RT4")" | awk -F'\t' '$1 == "T1" { a = $1 " " $4 " " $7 } $1 == "T2" { b = $1 " " $4 " " $5 } END { print a "|" b }')"
ll_pub "$RT4" T2
expect_eq "(t4) the publish passes over the stalled entry: T2 is published (rc 0)" "0 $KT4" "$LL_RC $(ll_head "$RT4")"
# (t5) the writer says ready again after STALLED: the entry is carried again, and lands.
RT5="$(ll_rworld)"
ll_commit_suite "$RT5" T1 a "$(ll_flaky_body t5 a 2 kill)"
ll_verb "$RT5" T1
expect_eq "(t5-pre) the first ready stalls" "70" "$LL_RC"
ll_verb_bg "$RT5" T1 "$WORLD_ROOT/t5.out"; T5_BG=$!
ll_wait_file "$WORLD_ROOT/t5.out.rc" 300 || ll_kill_bg "$T5_BG"
expect_eq "(t5) ready again after STALLED carries the entry and lands it (a third run, asked for)" "0 none none green" \
  "$(cat "$WORLD_ROOT/t5.out.rc" 2>/dev/null) $(ll_results "$RT5" T1 "$(ll_last_cand "$RT5" T1)")"
# MUTANT: the second-none branch removed. The suite is asked a third time.
RT6="$(ll_rworld)"
( cd "$RT6/.worktrees/T1" && world_suite a none >/dev/null ) && git -C "$RT6/.worktrees/T1" commit -qam "T1: a ends early"
LL_MUTANT='s/-ge 2 \]/-ge 99 ]/' LL_MUTANT_FN=_line_carry ll_drive "$RT6" T1 "$WORLD_ROOT/t6.out"; T6_BG=$!
i=0; while [ "$i" -lt 300 ] && [ "$(ll_ev "$RT6" verdict | grep -c 'result=none')" -lt 3 ]; do sleep 0.1; i=$((i + 1)); done
ll_kill_bg "$T6_BG"
expect_eq "(t6m) …and no stalled event" "" "$(ll_ev "$RT6" stalled)"

# ---------------------------------------------------------------------------
section "§WINDOW: the hand-holds count is read over a window, every source by its own time"
#
# `landing-report --hand-holds [--since <ISO>] [--until <ISO>]` counts a hand-hold only when its line's own time falls
# after the window's start and at or before its end. A line with no time of its own cannot be placed inside a window
# with an end: it is not counted, and the line's last count, `unplaced=`, says how many there were. With no flags the
# two ends are read from records: the start is the newest published landing of a row of kind build, the end the
# plan's `delivered:` time; before the run is delivered the window runs to now and the report says so. Every source
# is planted in its writer's shape: the landing record's line/v1 lines, the fill ledger's fill-ledger/v1 lines, the
# roster through the one production row writer, the plan's proof lines through lib/proof.sh, the AC blocks through
# matrix-render.
ww_report() {  # <root> [flags…] -> landing-report --hand-holds over the root's plan, stdout only
  local root="$1"; shift
  ( cd "$root" && CLAUDE_PROJECT_DIR="" BIONIC_PLUGIN_ROOT="$REPO/payload" \
      bash "$BIONIC_HOOKS_DIR/session-poker.sh" landing-report --hand-holds "$@" "$(ll_plan "$root")" 2>/dev/null )
}
ww_hh() { ww_report "$@" | grep '^hand-holds: '; }   # <root> [flags…] -> the counts line
ww_ends() { ww_report "$@" | grep '^hand-holds window: '; }   # <root> [flags…] -> the ends line
ww_proof() { bash -c '. "$1/run.sh" && . "$1/proof.sh" || exit 1; shift; proof_line "$@"' _ "$REPO/payload/scripts/lib" "$@"; }
ww_sdlc() {  # <root> <line>… -> each line under ## SDLC State, after the rows' step lines
  local p; p="$(ll_plan "$1")"; shift
  # through the environment: macOS awk refuses a -v value holding a line break
  WW_ADD="$(printf '%s\n' "$@")" awk '{ print } /^- T2: / && !d { print ENVIRON["WW_ADD"]; d = 1 }' "$p" > "$p.w" && mv "$p.w" "$p"
}
ww_poke() {  # <root> <verb> [args…] -> the poker run as the world's session, from the root; stdout and stderr
  local root="$1"; shift
  ( cd "$root" && CLAUDE_CODE_SESSION_ID="$WORLD_SID" CLAUDE_PROJECT_DIR="" BIONIC_PLUGIN_ROOT="$REPO/payload" \
      bash "$BIONIC_HOOKS_DIR/session-poker.sh" "$@" 2>&1 )
}
# A matrix whose n-th row carries the n-th waiver line in its block. The blocks are matrix-render's, written from the
# plan's own `### REQ-1` criteria, so each header is the `AC-1.<n>: <the criterion's text>` shape a real run carries;
# the waiver line is waive-row's `  waiver: <who> <time> "<words>" — <why>`, added at the end of its block as
# waive-row adds a key, at a time the fixture names (the verb stamps its own instant, which no window could place).
ww_matrix() {  # <root> <waiver value>… -> WW_MR, matrix-render's exit
  local root="$1" p n=0 v; p="$(ll_plan "$1")"; shift
  { printf '\n## Requirements\n\n### REQ-1 — the window fixture\n\n'
    for v in "$@"; do n=$((n + 1)); printf -- '- AC-1.%d the row %d holds its waiver. Fails when: it is not read.\n' "$n" "$n"; done
    printf '\n## Eval design\n\n| Requirement | Approach | Criterion | Eval type | Eval | Fails when |\n|---|---|---|---|---|---|\n'
    n=0; for v in "$@"; do n=$((n + 1)); printf '| REQ-1 | fixture | AC-1.%d | hermetic | `tests/a.test.sh` | a planted defect |\n' "$n"; done
    printf '\n## Verification Matrix\n\n| AC | tier | status | evidence | auditor |\n|---|---|---|---|---|\n'
    n=0; for v in "$@"; do n=$((n + 1)); printf '| AC-1.%d | T1 | waived | — | — |\n' "$n"; done
  } >> "$p"
  ww_poke "$root" matrix-render >/dev/null; WW_MR=$?
  # through the environment: macOS awk refuses a -v value holding a line break
  WW_WV="$(printf '%s\n' "$@")" awk '
    BEGIN { n = split(ENVIRON["WW_WV"], w, "\n") }
    function flush() { if (cur != "" && (cur in w)) print "  waiver: " w[cur]; cur = "" }
    /^AC-1\.[0-9]+:/ { flush(); print; cur = substr($0, 6, index($0, ":") - 6) + 0; next }
    cur != "" && /^[ \t]+[^ \t]/ { print; next }
    { flush(); print }
    END { flush() }' "$p" > "$p.w" && mv "$p.w" "$p"
}
WW_C="$(printf 'c%.0s' $(seq 40))"
WW_D="$(printf 'd%.0s' $(seq 40))"
ww_pub() { printf 'line/v1|ev=published|row=%s|commit=%s|kind=%s|by=-|why=-|at=%s\n' "$1" "$WW_C" "$2" "$3"; }   # <row> <kind> <at>
ww_dec() { printf 'fill-ledger/v1|at=%s|session=fixture|turn=|current=4|state=%s|ceiling=6|width=|open=|free=|ready=T1|launched=|declined=no room|missed=0|idle=|room=|named=T1\n' "$1" "$2"; }   # <at> <state>

# (w1) one hand landing before the window, one decline inside it.
RW1="$(ll_world)"; mkdir -p "$(dirname "$(ll_rec "$RW1")")"
ww_pub T1 hand 2026-10-20T10:00:00Z > "$(ll_rec "$RW1")"
ww_dec 2026-10-20T12:00:00Z decline > "$(dirname "$(ll_rec "$RW1")")/fill-ledger.log"
expect_eq "WINDOW-1 a hand landing before the window and a decline inside it read declines=1 by-hand=0" \
  "hand-holds: total=1 · by-hand=0 · stop-runs=0 · declines=1 · lifts=0 · amends=0 · holds=0 · extensions=0 · waivers=0 · second-regressions=0 · adoptions=0 · fixed=0 · unplaced=0" \
  "$(ww_hh "$RW1" --since 2026-10-20T11:00:00Z --until 2026-10-20T13:00:00Z)"
expect_contains "WINDOW-1a …and a window that opens before the landing counts it: the record is read, the window moved it" \
  "hand-holds: total=2 · by-hand=1 · stop-runs=0 · declines=1 " "$(ww_hh "$RW1" --since 2026-10-20T09:00:00Z --until 2026-10-20T13:00:00Z)"
expect_contains "WINDOW-1b …and one that closes before the decline drops it" \
  "hand-holds: total=1 · by-hand=1 · stop-runs=0 · declines=0 " "$(ww_hh "$RW1" --since 2026-10-20T09:00:00Z --until 2026-10-20T11:00:00Z)"

# (w1c) every source by its own time: each planted before, inside and after the window 11:00 to 13:00.
RW2="$(ll_world)"; WW_RD="$(dirname "$(ll_rec "$RW2")")"; mkdir -p "$WW_RD"
WW_PL="$(ll_plan "$RW2")"; WW_RO="$RW2/.bionic/tmp/roster-$WORLD_SID.state"
for t in 10:30 12:30 14:30; do
  ww_pub T9 hand "2026-10-20T$t:00Z"
  printf 'line/v1|ev=stop-run|request=21|who=fixture:w-T3|kind=whole|key=tests/run.sh|by=fixture|why=parked|at=2026-10-20T%s:00Z\n' "$t"
done > "$(ll_rec "$RW2")"
ww_pub T1 queue 2026-10-20T10:00:00Z >> "$(ll_rec "$RW2")"   # the landing the moves name, before each of them
for t in 10:30 12:30 14:30; do ww_dec "2026-10-20T$t:00Z" decline; ww_dec "2026-10-20T$t:05Z" lift; done > "$WW_RD/fill-ledger.log"
for t in 10:30 12:30 14:30; do
  roster_row_fixture status=identified name=w-a agent_id=aa plan="$WW_PL" amended="2026-10-20T$t:00Z widen the files"
  roster_row_fixture status=confirmed name=w-a agent_id=aa plan="$WW_PL" amended="2026-10-20T$t:00Z widen the files"
  roster_row_fixture status=identified name=w-b agent_id=ab plan="$WW_PL" held="2026-10-20T$t:00Z waiting on the reader"
  roster_row_fixture status=identified name=w-c agent_id=ac plan="$WW_PL" extended="2026-10-20T$t:00Z more work"
done >> "$WW_RO"
roster_row_fixture status=identified name=w-ad agent_id=ad source=adopted adopted_from=old-sid plan="$WW_PL" >> "$WW_RO"
ww_sdlc "$RW2" "$(ww_proof regression "$WW_D" 2026-10-20T09:00:00Z record/wave-x/floor.log)" \
  "$(ww_proof regression "$WW_D" 2026-10-20T10:30:00Z record/wave-x/floor-2.log)" \
  "$(ww_proof regression "$WW_D" 2026-10-20T12:30:00Z record/wave-x/floor-3.log)" \
  "$(ww_proof regression "$WW_D" 2026-10-20T14:30:00Z record/wave-x/floor-4.log)" \
  "waived: question=adversarial head=$WW_D by Dana 2026-10-20T10:30:00Z \"waive it\"" \
  "waived: question=structure head=$WW_D by Dana 2026-10-20T12:30:00Z \"waive it\"" \
  "waived: question=evidence head=$WW_D by Dana 2026-10-20T14:30:00Z \"waive it\"" \
  "moved: record/wave-x/rev.md#1 to=fixed row=T1 by=Dana at=2026-10-20T10:30:00Z" \
  "moved: record/wave-x/rev.md#2 to=fixed row=T1 by=Dana at=2026-10-20T12:30:00Z" \
  "moved: record/wave-x/rev.md#3 to=fixed row=T1 by=Dana at=2026-10-20T14:30:00Z"
ww_matrix "$RW2" 'Dana Fixture 2026-10-20T10:30:00Z "waive the row" — fixture' \
  'Dana Fixture 2026-10-20T12:30:00Z "waive the row" — fixture' 'Dana Fixture 2026-10-20T14:30:00Z "waive the row" — fixture'
expect_eq "WINDOW-1c-1 precondition: matrix-render wrote the three blocks, every header carrying its criterion's text, each block one waiver" "0|3|0|3" \
  "$WW_MR|$(grep -cE '^AC-1\.[0-9]+: .' "$WW_PL")|$(grep -cE '^AC-1\.[0-9]+:[[:space:]]*$' "$WW_PL")|$(grep -c '^  waiver: ' "$WW_PL")"
expect_eq "WINDOW-1c-0 precondition: the plan holds the four regression proofs, three waived: and three moved: lines" "4/3/3" \
  "$(grep -c '^proved: kind=regression ' "$WW_PL")/$(grep -c '^waived: question=' "$WW_PL")/$(grep -c '^moved: ' "$WW_PL")"
expect_eq "WINDOW-1c a wide window reads three of every kind, the regressions past the first, and the adoption it cannot place" \
  "hand-holds: total=33 · by-hand=3 · stop-runs=3 · declines=3 · lifts=3 · amends=3 · holds=3 · extensions=3 · waivers=6 · second-regressions=3 · adoptions=0 · fixed=3 · unplaced=1" \
  "$(ww_hh "$RW2" --since 2026-10-20T08:00:00Z --until 2026-10-20T16:00:00Z)"
expect_eq "WINDOW-1d …and the window 11:00 to 13:00 reads one of each, every source filtered by its own time" \
  "hand-holds: total=11 · by-hand=1 · stop-runs=1 · declines=1 · lifts=1 · amends=1 · holds=1 · extensions=1 · waivers=2 · second-regressions=1 · adoptions=0 · fixed=1 · unplaced=1" \
  "$(ww_hh "$RW2" --since 2026-10-20T11:00:00Z --until 2026-10-20T13:00:00Z)"

# (w2) the matrix waiver's two forms. The ISO form is placed by its time; the date form counts with no end, and
# a day the window's start falls inside cannot be placed. That waive-row writes the ISO form is read where the card's
# reply writes it, tests/release-approval.test.sh §HANDHOLDS (WINDOW-2a).
RW3="$(ll_world)"; mkdir -p "$(dirname "$(ll_rec "$RW3")")"
ww_matrix "$RW3" 'Dana Fixture 2026-10-20T12:30:00Z "waive the row" — inside' 'Dana Fixture 2026-10-20T14:30:00Z "waive the row" — after' \
  'Dana Fixture 2026-10-19 "waive the row" — a whole day before' 'Dana Fixture 2026-10-20 "waive the row" — the start falls inside this day'
expect_eq "WINDOW-2-0 precondition: matrix-render wrote the four blocks with their criterion's text, each block one waiver" "0|4|4" \
  "$WW_MR|$(grep -cE '^AC-1\.[0-9]+: .' "$(ll_plan "$RW3")")|$(grep -c '^  waiver: ' "$(ll_plan "$RW3")")"
expect_contains "WINDOW-2 a waiver at a time inside the window counts, the one after it does not, the day before is placed outside, the day the start falls in is unplaced" \
  "waivers=1 · second-regressions=0 · adoptions=0 · fixed=0 · unplaced=1" "$(ww_hh "$RW3" --since 2026-10-20T11:00:00Z --until 2026-10-20T13:00:00Z)"
expect_contains "WINDOW-2b …and with no end, every form counts, the date-only ones too" \
  "waivers=4 · second-regressions=0 · adoptions=0 · fixed=0 · unplaced=0" "$(ww_hh "$RW3" --since 2026-01-01T00:00:00Z)"
expect_eq "WINDOW-2c …and with no window at all (no build landing, no page), both forms count and nothing is unplaced" \
  "hand-holds: total=4 · by-hand=0 · stop-runs=0 · declines=0 · lifts=0 · amends=0 · holds=0 · extensions=0 · waivers=4 · second-regressions=0 · adoptions=0 · fixed=0" \
  "$(ww_hh "$RW3")"

# (w3) the ends from records. The start is the last build row's landing; the end is the plan's `delivered:` time, and
# before the run is delivered the window runs to now. A release approval page ends nothing: what is done after the
# card, close-out's own acts among them, is inside the window.
RW4="$(ll_world)"; WW_RD4="$(dirname "$(ll_rec "$RW4")")"; mkdir -p "$WW_RD4"
{ ww_pub T1 queue 2026-10-20T11:00:00Z; ww_pub T9 hand 2026-10-20T11:30:00Z; } > "$(ll_rec "$RW4")"
ww_dec 2026-10-20T10:00:00Z decline > "$WW_RD4/fill-ledger.log"
ww_times() { printf '%s\n' "$1" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{5,8}Z' | paste -sd' ' -; }   # <ends line> -> its times
WW_E4="$(ww_ends "$RW4")"
expect_contains "WINDOW-3 with no delivered: time the ends line runs the window to now" "until now: the plan names no delivered: time" "$WW_E4"
expect_eq "WINDOW-3a …and prints one time, the start: the last build row's landing, never an end" \
  "2026-10-20T11:00:00Z" "$(ww_times "$WW_E4")"
expect_contains "WINDOW-3b …and the counts read from that landing to now: the later hand landing of a row that is no build row counts, the earlier decline does not" \
  "hand-holds: total=1 · by-hand=1 · stop-runs=0 · declines=0 " "$(ww_hh "$RW4")"
printf '# page\n\n## Replay\n\nrelease-approval/v1|plan=%s|head=%s|at=2026-10-20T11:20:00Z|decisions=1\n' "$(ll_plan "$RW4")" "$WW_C" > "$WW_RD4/release-approval-cccccccc.md"
WW_E4="$(ww_ends "$RW4")"
expect_eq "WINDOW-3c a release approval page is no end: the ends line still prints the start alone and runs to now" \
  "2026-10-20T11:00:00Z|1" "$(ww_times "$WW_E4")|$(printf '%s\n' "$WW_E4" | grep -c 'until now')"
expect_contains "WINDOW-3d …and the hand landing after the page is counted: the card does not stop the count" \
  "hand-holds: total=1 · by-hand=1 · " "$(ww_hh "$RW4")"
# delivered: as close-out writes it, a minute; the run reads closed once current is 9 and the Step 9 line says so
awk '/^current: 4$/ { print "current: 9"; next } /^- T2: / { print; print "- Step 9: delivered: 2026-10-20T11:40Z wave-x — fixture"; next } { print }' \
  "$(ll_plan "$RW4")" > "$(ll_plan "$RW4").d" && mv "$(ll_plan "$RW4").d" "$(ll_plan "$RW4")"
ww_pub T9 hand 2026-10-20T11:40:30Z >> "$(ll_rec "$RW4")"
ww_pub T9 hand 2026-10-20T11:41:00Z >> "$(ll_rec "$RW4")"
WW_E4="$(ww_ends "$RW4")"
expect_eq "WINDOW-3e with a delivered: time the ends line prints both ends, the start and the plan's delivered: time, named as such" \
  "2026-10-20T11:00:00Z 2026-10-20T11:40Z|1" "$(ww_times "$WW_E4")|$(printf '%s\n' "$WW_E4" | grep -c 'until 2026-10-20T11:40Z (delivered:)')"
expect_contains "WINDOW-3f …and the count reaches through the delivered minute: the act at 11:40:30 counts, the one at 11:41 does not" \
  "hand-holds: total=2 · by-hand=2 · " "$(ww_hh "$RW4")"
# ---------------------------------------------------------------------------
section "§WAIVERS: a waiver in a block matrix-render wrote is counted"
# matrix-render heads each block `AC-<id>: <the criterion's text>`, and waive-row adds its `waiver:` line to that block.
# The count reads that header as it reads a bare `AC-<id>:` one, through the one matcher of a block's heading.
# fails-when: the header match is bare-only, and the four rendered waivers read waivers=0.
RW5="$(ll_world)"; mkdir -p "$(dirname "$(ll_rec "$RW5")")"
ww_matrix "$RW5" 'Dana Fixture 2026-10-20T12:00:00Z "waive the row" — one' 'Dana Fixture 2026-10-20T12:10:00Z "waive the row" — two' \
  'Dana Fixture 2026-10-20T12:20:00Z "waive the row" — three' 'Dana Fixture 2026-10-20T12:30:00Z "waive the row" — four'
expect_eq "WAIVERS-0 precondition: matrix-render exited 0 and wrote four texted headers, no bare one, and four waivers" "0|4|0|4" \
  "$WW_MR|$(grep -cE '^AC-1\.[0-9]+: .' "$(ll_plan "$RW5")")|$(grep -cE '^AC-1\.[0-9]+:[[:space:]]*$' "$(ll_plan "$RW5")")|$(grep -c '^  waiver: ' "$(ll_plan "$RW5")")"
expect_eq "WAIVERS-1 the four waivers under rendered headers read waivers=4 over a window that holds them" \
  "hand-holds: total=4 · by-hand=0 · stop-runs=0 · declines=0 · lifts=0 · amends=0 · holds=0 · extensions=0 · waivers=4 · second-regressions=0 · adoptions=0 · fixed=0 · unplaced=0" \
  "$(ww_hh "$RW5" --since 2026-10-20T11:00:00Z --until 2026-10-20T13:00:00Z)"

# ---------------------------------------------------------------------------
section "§MOVED: a finding moved to fixed is placed by its time against the landing it names"
# A `moved: … to=fixed row=<T>` line typed before <T> lands is the landing's own business, outside the count; one typed
# after <T> landed is a hand marking a fix, inside it. A move naming a row that has not landed cannot be placed, and
# says so in `unplaced=`. The lines stand after-first in the plan, so a placement by line order reads them wrong.
# fails-when: a move a minute before its landing counts, or one a minute after does not.
RW6="$(ll_world)"; mkdir -p "$(dirname "$(ll_rec "$RW6")")"
ww_pub T2 queue 2026-10-20T12:00:00Z > "$(ll_rec "$RW6")"
ww_sdlc "$RW6" "moved: record/wave-x/rev.md#2 to=fixed row=T2 by=Dana at=2026-10-20T12:01:00Z" \
  "moved: record/wave-x/rev.md#1 to=fixed row=T2 by=Dana at=2026-10-20T11:59:00Z" \
  "moved: record/wave-x/rev.md#3 to=fixed row=T9 by=Dana at=2026-10-20T12:30:00Z"
expect_eq "MOVED-0 precondition: the plan holds the three moves and the record T2's one landing" "3|1" \
  "$(grep -c '^moved: ' "$(ll_plan "$RW6")")|$(grep -c '|ev=published|row=T2|' "$(ll_rec "$RW6")")"
expect_eq "MOVED-1 the move a minute after T2 landed counts, the one a minute before does not, the one naming a row never landed is unplaced" \
  "hand-holds: total=1 · by-hand=0 · stop-runs=0 · declines=0 · lifts=0 · amends=0 · holds=0 · extensions=0 · waivers=0 · second-regressions=0 · adoptions=0 · fixed=1 · unplaced=1" \
  "$(ww_hh "$RW6" --since 2026-10-20T09:00:00Z --until 2026-10-20T14:00:00Z)"
RW7="$(ll_world)"; mkdir -p "$(dirname "$(ll_rec "$RW7")")"
ww_pub T2 queue 2026-10-20T12:00:00Z > "$(ll_rec "$RW7")"
ww_sdlc "$RW7" "moved: record/wave-x/rev.md#1 to=fixed row=T2 by=Dana at=2026-10-20T11:59:00Z"
expect_contains "MOVED-2 …and the move before the landing alone, inside the same window, reads fixed=0 and nothing unplaced" \
  "fixed=0 · unplaced=0" "$(ww_hh "$RW7" --since 2026-10-20T09:00:00Z --until 2026-10-20T14:00:00Z)"

RW9="$(ll_world)"; mkdir -p "$(dirname "$(ll_rec "$RW9")")"
ww_pub T2 queue 2026-10-20T12:00:00Z > "$(ll_rec "$RW9")"
ww_sdlc "$RW9" "moved: record/wave-x/rev.md#2 to=fixed row=T2 by=Dana at=2026-10-20T12:01:00Z" \
  "moved: record/wave-x/rev.md#4 to=fixed row=T2 by=landing at=2026-10-20T12:02:00Z landing=$WW_C"
expect_contains "MOVED-3 a move the landing wrote (by=landing) is its settlement: beside a hand move after the landing, fixed=1" \
  "fixed=1 · unplaced=0" "$(ww_hh "$RW9" --since 2026-10-20T09:00:00Z --until 2026-10-20T14:00:00Z)"

# ---------------------------------------------------------------------------
section "§ORDER: the reader rule and the numbers re-renderer read one publish order"
# Whether a row was written after the release is publish order: lib/units.sh `_units_publish_order` places each landed
# row at its last landing line, and lib/line.sh `_line_release_landed` names the release row the numbers re-renderer
# reads as landed. Both read the record through one parser, a `published` event and an older `landed:` header alike.
# The record here lands the release row D7 by a header alone and T2 by an event. fails-when: one reader is changed and
# the other is not: the two disagree on the release row, or on which line came first.
RW8="$(ll_world)"; WW_P8="$(ll_plan "$RW8")"; mkdir -p "$(dirname "$(ll_rec "$RW8")")"
awk '{ print } /^\| T2 \| 4 \| build / { print "| D7 | 7 | doc | the release | wx-D7 | — | | 10 | REQ-1 | CHANGELOG.md | — | | landed |" }' \
  "$WW_P8" > "$WW_P8.o" && mv "$WW_P8.o" "$WW_P8"
ww_order() {  # <root> -> `<units' order, sorted>|<line's landed release row>`
  ( _wt_units_load || exit 9
    printf '%s|%s' "$(_units_publish_order "$(ll_plan "$1")" "$(units_rows "$(ll_plan "$1")")" | tr ' ' '\n' | LC_ALL=C sort | paste -sd' ' -)" \
      "$(_line_release_landed "$(ll_plan "$1")" "$(ll_rec "$1")" 2>/dev/null)" )
}
{ printf 'landed: row=D7 merge=%s at=2026-10-20T10:00:00Z\n' "$WW_D"; ww_pub T2 queue 2026-10-20T11:00:00Z; } > "$(ll_rec "$RW8")"
expect_eq "ORDER-0 precondition: the plan holds the release row D7, a doc row at step 7, landed" "D7	7	doc" \
  "$( ( _wt_units_load && units_rows "$WW_P8" ) | awk -F'\t' '$1 == "D7" { print $1 "\t" $2 "\t" $3 }')"
expect_eq "ORDER-1 both readers read the release row's header as its landing, and units places it before T2's event" \
  "D7=1 T2=2|D7" "$(ww_order "$RW8")"
{ ww_pub T2 queue 2026-10-20T09:00:00Z; printf 'landed: row=D7 merge=%s at=2026-10-20T10:00:00Z\n' "$WW_D"; } > "$(ll_rec "$RW8")"
expect_eq "ORDER-2 …and with the two lines swapped, T2 first, both still name D7 and units places T2 first" \
  "D7=2 T2=1|D7" "$(ww_order "$RW8")"
# ---------------------------------------------------------------------------
section "§NUMBERS-JUDGE: the release numbers a landing past the release writes are the judge copy's release-note"
# The judge is the commit the plan's release range starts from (here its `base-sha:`, the world having no tag). It
# holds a release-note that prints the block one way; the accepted head's own copy prints one field more. A row landing
# past the published release row has its numbers rendered by the judge's copy, the copy its release check compares
# with, so the entry's block is the judge's output and never carries the head's field. fails-when: the renderer is
# the plugin root's or the head's, so the landing is refused in the renderer's words or the block carries extra=1.
nj_stub() {  # <extra field> -> a release-note stand-in: the heading, the head and instant line, one fenced line
  printf '%s\n' '#!/bin/bash' '[ "$1" = release-note ] || exit 2' \
    "printf '### The landing numbers\\n\\n\`landing-report --rows\` at %s on %s:\\n\\n\`\`\`\\nlandings: judge=1$1\\n\`\`\`\\n' \"\$3\" \"\$5\""
}
RJ="$(ll_world)"; PJ="$(ll_plan "$RJ")"
mkdir -p "$RJ/hooks"; nj_stub "" > "$RJ/hooks/session-poker.sh"
printf '# Changelog\n\n## 9.9.9 — 2026-10-20\n\n### The landing numbers\n\n`landing-report --rows` at 0 on 2026-10-20T00:00:00Z:\n\n```\nlandings: as released\n```\n\n## 9.9.8 — 2026-10-01\n\n- before\n' \
  > "$RJ/CHANGELOG.md"
git -C "$RJ" add hooks/session-poker.sh CHANGELOG.md && git -C "$RJ" commit -qm "the release and its renderer"
NJ_JUDGE="$(ll_head "$RJ")"
nj_stub " extra=1" > "$RJ/hooks/session-poker.sh" && git -C "$RJ" commit -qam "the renderer prints a field more"
NJ_HEAD="$(ll_head "$RJ")"
awk -v j="$NJ_JUDGE" '{ print } /^working-branch: / { print "release: 9.9.9"; print "base-sha: " j }
  /^\| T2 \| 4 \| build \|/ { print "| T9 | 7 | doc | the release 9.9.9 | wx-T9 | — | | 10 | REQ-1 | CHANGELOG.md | .worktrees/T9 | | active |" }' \
  "$PJ" > "$PJ.n" && mv "$PJ.n" "$PJ"
mkdir -p "$(dirname "$(ll_rec "$RJ")")"
printf 'line/v1|ev=published|row=T9|commit=%s|kind=hand|by=t|why=w|at=2026-10-20T00:00:00Z\n' "$NJ_JUDGE" >> "$(ll_rec "$RJ")"
expect_eq "(nj0) precondition: the judge's copy and the head's differ by the one field, and the plan names the judge as its base" \
  "1 0 1 base-sha: $NJ_JUDGE" \
  "$(git -C "$RJ" show "$NJ_HEAD:hooks/session-poker.sh" | grep -c 'judge=1 extra=1') $(git -C "$RJ" show "$NJ_JUDGE:hooks/session-poker.sh" | grep -c 'extra=1') $(grep -c '^| T9 | 7 | doc |' "$PJ") $(grep '^base-sha: ' "$PJ")"
ll_ready "$RJ" T1 "$(ll_carrier)" >/dev/null
KJ="$(ll_cand "$RJ" T1 "$NJ_HEAD")"; ll_green "$RJ" T1 "$KJ"
ll_pub "$RJ" T1
NJ_TIP="$(ll_head "$RJ")"
expect_eq "(nj1) the row past the release lands (exit 0)" "0" "$LL_RC"
expect_contains "(nj1b) …its publish names the numbers commit on the candidate" "|row=T1|commit=$KJ|kind=queue|by=-|why=-|numbers=$NJ_TIP|" \
  "$(ll_ev "$RJ" published)"
NJ_BLOCK="$(git -C "$RJ" show "$NJ_TIP:CHANGELOG.md" 2>/dev/null | awk '/^## 9\.9\.9 / { f = 1; next } /^## / { f = 0 } f && NF')"
NJ_ON="$(printf '%s\n' "$NJ_BLOCK" | sed -n 's/^`landing-report --rows` at [0-9a-f]* on \([0-9TZ:-]*\):$/\1/p')"
expect_regex "(nj2-0) the entry's block names the candidate and an instant" '^[0-9]{4}-[0-9]{2}-[0-9]{2}T' "$NJ_ON"
expect_eq "(nj2) …and equals, line for line, what the judge's copy prints for that head and instant" \
  "$(git -C "$RJ" show "$NJ_JUDGE:hooks/session-poker.sh" | bash -s release-note --at "$KJ" --on "$NJ_ON" "$PJ" | awk NF)" "$NJ_BLOCK"
expect_absent "(nj2b) …never the head's field" "extra=1" "$NJ_BLOCK"

section "§BORN-AT-8: past judgment only a fix born of a failing review lands; any other row is refused past-judgment"
#
# A plan at `current: 8` that the judge can answer (rigor, scale, base-sha) carries a registered structure reading whose
# newest result is fail, its record holding one finding to fix. T1's `- T1:` line carries the born marker task-add
# writes for that finding; T2 is unborn, then regression-born, then born of the same finding once T1 has answered it.
# FIXTURE FIDELITY: the reading and the markers are planted in the shapes `proof-add review` and `task-add --born` write
# them (the replay drives the verbs themselves: tests/close-replay.test.sh §CLOSE); the landing is the writer's `ready`.
# fails-when: lib/worktree.sh `_wt_land_checks` keeps the past-judgment refusal for the born row (ba3), or admits a row
# the born rule does not name: unborn (ba1), regression-born (ba2), born of a review no longer failing (ba4).
ba_world() {  # -> a world at current 8: T1 born of rev.md#1, a failing structure reading of it newest
  local r p h b
  r="$(ll_rworld)" || return 1
  p="$(ll_plan "$r")"; h="$(ll_head "$r")"; b="$(git -C "$r" rev-parse main)"
  mkdir -p "$r/.bionic/docs/record/wave-x"
  printf 'reviewed: %s..%s\nquestion: structure\nresult: fail\nscope: piece\n\nfindings: 1\nfinding: 1 S1 off T1.txt:1 the row is wrong\nshown: 1 cat T1.txt\n' \
    "$b" "$h" > "$r/.bionic/docs/record/wave-x/rev.md"
  BA_H="$h" BA_B="$b" awk '
    { print }
    /^working-branch: / && !fm { fm = 1; print "rigor: single"; print "scale: task"; print "base-sha: " ENVIRON["BA_B"] }
    ' "$p" | BA_H="$h" awk '
    /^current: 4$/ { print "current: 8"; print "proved: kind=review head=" ENVIRON["BA_H"] " at=2026-10-20T00:00:00Z evidence=record/wave-x/rev.md question=structure reader=w-rev result=fail scope=piece"; next }
    /^- T1: active$/ { print "- T1: active — added by task-add at 2026-10-20T00:00:00Z born: review S1 off of=record/wave-x/rev.md#1"; next }
    { print }' > "$p.n" && mv "$p.n" "$p"
  printf '%s' "$r"
}
ba_mark_t2() {  # <root> <born marker | empty> — T2's `- T2:` line as task-add writes it, with that marker
  local p
  p="$(ll_plan "$1")"
  BA_M="$2" awk '/^- T2: / { print "- T2: active — added by task-add at 2026-10-20T00:00:00Z" (ENVIRON["BA_M"] != "" ? " born: " ENVIRON["BA_M"] : ""); next } { print }' \
    "$p" > "$p.n" && mv "$p.n" "$p"
}
ba_ready_rows() { ll_ev "$1" ready | sed -n 's/^line\/v1|ev=ready|row=\([^|]*\)|.*/\1/p' | tr '\n' ' ' | sed 's/ $//'; }   # <root>
RB="$(ba_world)"; PB="$(ll_plan "$RB")"
expect_eq "(ba0) precondition: the plan reads current 8 and the judge reads structure failing on rev.md" "8|failing	record/wave-x/rev.md" \
  "$(sed -n 's/^current: //p' "$PB")|$(bash -c '. "$1/proof.sh" && facts_state "$2" "$3"' _ "$REPO/payload/scripts/lib" "$PB" "$(ll_head "$RB")" 2>/dev/null \
     | awk -F'\t' '$1 == "review" && $2 == "structure" { print $5 "\t" $6 }')"
ll_verb "$RB" T2
expect_eq "(ba1) an unborn row is refused (exit 2)" "2" "$LL_RC"
expect_contains "(ba1) …past-judgment, as before" "REFUSED reason=past-judgment why=current-8" "$LL_OUT"
ba_mark_t2 "$RB" 'regression a.test.sh of=floor'
expect_contains "(ba2-pre) T2 carries the regression-born marker" "born: regression a.test.sh of=floor" "$(/usr/bin/grep '^- T2: ' "$PB")"
ll_verb "$RB" T2
expect_eq "(ba2) a row born of a regression's red is refused past-judgment too (exit 2)" "2 yes" \
  "$LL_RC $(printf '%s' "$LL_OUT" | grep -qF 'REFUSED reason=past-judgment why=current-8' && echo yes || echo no)"
ll_verb "$RB" T1
expect_eq "(ba3) the row born of the failing review's finding lands by ready at current 8 (exit 0)" "0" "$LL_RC"
expect_contains "(ba3) …printing LANDED" "LANDED T1 " "$LL_OUT"
expect_contains "(ba3) …published by the queue" "|row=T1|commit=$(ll_head "$RB")|kind=queue|" "$(ll_ev "$RB" published)"
expect_eq "(ba3) …the step never moved back" "8" "$(sed -n 's/^current: //p' "$PB")"
expect_eq "(ba1-ba2) the refused rows entered nothing: the record's ready events are T1's alone (ba3 read the same extractor)" "T1" \
  "$(ba_ready_rows "$RB")"
ba_mark_t2 "$RB" 'review S1 off of=record/wave-x/rev.md#1'
ll_verb "$RB" T2
expect_eq "(ba4) once T1 answered the review, a row born of the same finding is refused past-judgment (exit 2)" "2 yes" \
  "$LL_RC $(printf '%s' "$LL_OUT" | grep -qF 'REFUSED reason=past-judgment why=current-8' && echo yes || echo no)"


# ---------------------------------------------------------------------------
finish
