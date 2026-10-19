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
expect_eq "(e3) …and only one line" "1" "$(ll_ev "$RE" ready | awk 'END { print NR }')"
line_event "$PE" verdict row=T1 "commit=$(ll_head "$RE")" "suite=a|b" result=green log=- >/dev/null 2>&1; RCB=$?
expect_ne "(e4) a value holding | is refused" "0" "$RCB"
expect_eq "(e4) …and nothing is written" "1" "$(awk 'END { print NR }' "$(ll_rec "$RE")")"
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
expect_eq "(s2) …and no published event for T2" "" "$(ll_ev "$RS" published | grep 'row=T2')"

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
expect_eq "(p1) the checkout is clean and at the branch" "$KP2:" "$(git -C "$RP" rev-parse HEAD):$(git -C "$RP" status --porcelain)"
unset BIONIC_LINE_PAUSE_BEFORE_PUBLISH

RP2="$(ll_pair_world)"; HP2="$(ll_head "$RP2")"
ll_pub "$RP2" T2
expect_eq "(p2) T2 asking first is told to rebuild (rc 3)" "3" "$LL_RC"
expect_eq "(p2) …and nothing is published" "$HP2" "$(ll_head "$RP2")"
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
expect_eq "(p4) …one published event" "1" "$(ll_ev "$RP4" published | grep -c 'row=T1|')"
RP5="$(ll_pair_world)"; mkdir -p "$WORLD_ROOT/pause-p5"
export LL_MUTANT='/_line_lock_take /d'
ll_p4 "$RP5" "$WORLD_ROOT/pause-p5" "$WORLD_ROOT/p5"
unset LL_MUTANT
# Both mutant publishers are released by the one `T1.go` at the same instant, so their fast-forwards
# race on the checkout's index lock and either may be refused (wave-28 T4 met `2 0` under load). What
# the lock decides is whether the second is told to rebuild; that is what the mutant row reads.
expect_ne "(p5m) MUTANT lock skipped: the second publisher of the row is not told to rebuild (the row can fail)" "3" \
  "$(cat "$WORLD_ROOT/p5-b.out.rc" 2>/dev/null)"
expect_eq "(p5m) …both mutant publishers ran to their end, at least one publishing" "yes yes yes" \
  "$([ -s "$WORLD_ROOT/p5-a.out.rc" ] && echo yes) $([ -s "$WORLD_ROOT/p5-b.out.rc" ] && echo yes) $([ "$(ll_ev "$RP5" published | grep -c 'row=T1|')" -ge 1 ] && echo yes)"

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
expect_eq "(h1) the checkout is clean and at the branch" "$(ll_head "$RH"):" "$(git -C "$RH" rev-parse HEAD):$(git -C "$RH" status --porcelain)"

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
expect_eq "(g3) …once" "2" "$(ll_ev "$RG" published | awk 'END { print NR }')"
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
expect_match "(d1) …printing the guard's line, the writer's tree in its fix, ending say ready again" \
  "spawn-worktree: REFUSED reason=bionic-committed path=.bionic commit=${TDC:0:12} branch=wt/T1 onto=wave/x fix='git -C ${RD}/.worktrees/T1 rm -r --cached .bionic, commit, say ready again' — *" \
  "$(printf '%s\n' "$LL_OUT" | grep 'reason=bionic-committed')"
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
expect_eq "(r1) …printing LANDED and the owed line, exactly" \
  "$(printf 'LANDED T1 %s\nlanded T1 %s — owed: complete task T1, then stop wx-T1' "$KR" "$KR")" "$LL_OUT"
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
expect_contains "(r6d2) …and the hand landing" "--by-hand --reason '<why>'" "$LL_OUT"
expect_false "(r6d2) …and nothing is appended" test -e "$(ll_rec "$RR6b")"
ll_launch "$RR6b" T1 'none docs only'
ll_verb "$RR6b" T1
expect_eq "(r6d3) …while the same tree, lands_on=none <why> (a declared waiver) publishes with no run (the one parser, the key's meaning)" "0 none 0" \
  "$LL_RC $(ll_field "$(ll_ev "$RR6b" ready)" suites) $(ll_ev "$RR6b" verdict | awk 'END { print NR }')"
ll_launch "$RR3" T1 none
ll_verb "$RR3" T1
expect_eq "(r7) lands_on=none: the candidate publishes with no run" "0 none 0" \
  "$LL_RC $(ll_field "$(ll_ev "$RR3" ready)" suites) $(ll_ev "$RR3" verdict | awk 'END { print NR }')"

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

# THE PASS IS GONE (wave-35 T1; D12, REQ-3 AC-3.1; ADR-054, which supersedes ADR-053): a landing starts
# no background run, whatever .bionic/config.yaml says. The project declares a regression (`floor:`, a
# stub that writes where it ran and waits for its go file) and the old switch, `background-pass: on`.
# fails-when: ready starts a detached run, prints a pass line, or the record gains an ev=pass.
R7_STUB="$WORLD_ROOT/r7-floor-stub.sh"
printf '#!/bin/bash\nd=%s/r7-$1\nprintf "%%s\\n" "$(pwd -P)" >> "$d.started"\ni=0; while [ ! -e "$d.go" ] && [ "$i" -lt 300 ]; do sleep 0.1; i=$((i + 1)); done\necho "stub regression: 4 passed"\n' "$WORLD_ROOT" > "$R7_STUB"
r7_started() { awk 'END { print NR + 0 }' "$WORLD_ROOT/r7-$1.started" 2>/dev/null || echo 0; }   # <tag> -> runs of the stub
r7_ps() { ps -axo command= 2>/dev/null | R7N="$R7_STUB $1" awk 'index($0, ENVIRON["R7N"]) { c++ } END { print c + 0 }'; }   # <tag> -> live stubs (the needle in the environment, so awk never counts itself)
RR7="$(ll_rworld)"
printf 'floor: bash %s r7\nbackground-pass: on\n' "$R7_STUB" > "$RR7/.bionic/config.yaml"
ll_verb "$RR7" T1
K7="$(ll_field "$(ll_ev "$RR7" candidate | tail -1)" commit)"
expect_nonempty "(r7-pre) a candidate was built" "$K7"
expect_eq "(r7) AC-3.1 background-pass: on and a declared floor: ready lands and prints LANDED and the owed line, exactly" \
  "0|$(printf 'LANDED T1 %s\nlanded T1 %s — owed: complete task T1, then stop wx-T1' "$K7" "$K7")" "$LL_RC|$LL_OUT"
sleep 2
expect_eq "(r7b) …the record holds the landing's published event (the reader reads this record)" "1" \
  "$(ll_ev "$RR7" published | awk 'END { print NR + 0 }')"
expect_eq "(r7c) …the declared regression never ran, and no process runs it" "0 0" "$(r7_started r7) $(r7_ps r7)"
( bash "$R7_STUB" r7 >/dev/null 2>&1 & )
ll_wait_lines "$WORLD_ROOT/r7-r7.started" 1 100
expect_eq "(r7d) control: the same stub started by hand is counted by both readers" "1 1" "$(r7_started r7) $(r7_ps r7)"
: > "$WORLD_ROOT/r7-r7.go"
r7_gone() { [ "$(r7_ps r7)" = 0 ]; }
r7_i=0; while ! r7_gone && [ "$r7_i" -lt 100 ]; do sleep 0.1; r7_i=$((r7_i + 1)); done
sleep 1
expect_eq "(r7e) …and once every stub is released and gone, the record still holds no ev=pass" "0 0" \
  "$(r7_ps r7) $(ll_ev "$RR7" pass | awk 'END { print NR + 0 }')"

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
expect_true "(q2) …the branch holds the row" git -C "$RQ2" merge-base --is-ancestor wt/T1 wave/x

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
expect_eq "(x2) …nothing published" "" "$(ll_ev "$RX" published)"
expect_eq "(x3) T1 leaves the line" "" "$(line_state "$(ll_plan "$RX")")"
RC1="$(ll_rworld)"; HC1="$(ll_head "$RC1")"
printf 'one\n' > "$RC1/T1.txt"; git -C "$RC1" add T1.txt; git -C "$RC1" commit -qm "the branch writes T1.txt too"
HC1="$(ll_head "$RC1")"
ll_verb "$RC1" T1
expect_eq "(x4) a conflict with the accepted head returns the row (exit 1)" "1" "$LL_RC"
expect_eq "(x4) …printing CONFLICT and the files" "CONFLICT T1 T1.txt" "$LL_OUT"
expect_regex "(x4) …returned why=conflict" "^line/v1\\|ev=returned\\|row=T1\\|why=conflict\\|detail=T1.txt\\|" "$(ll_ev "$RC1" returned)"
expect_eq "(x4) …nothing published" "$HC1" "$(ll_head "$RC1")"

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
expect_false "(a3) …which does not contain T1's commit" git -C "$RA" merge-base --is-ancestor "$T1A" wave/x
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
expect_eq "(w1) …so T2's run has not started" "0" "$(ll_lines "$LL_SIG/s-T2.runs")"
expect_eq "(w1) …and T2's candidate is built on T1's" "$(ll_nth_cand "$RW" T1)" "$(git -C "$RW" rev-parse "$(ll_nth_cand "$RW" T2)^1")"
touch "$LL_SIG/s-T1.go"
expect_true "(w2-pre) T2's run starts once T1's has ended" ll_wait_lines "$LL_SIG/s-T2.runs" 1
touch "$LL_SIG/s-T2.go"
ll_wait_file "$WORLD_ROOT/s-T1.out.rc" 300; ll_wait_file "$WORLD_ROOT/s-T2.out.rc" 300
expect_eq "(w2) both publish" "0 0" "$(cat "$WORLD_ROOT/s-T1.out.rc" 2>/dev/null) $(cat "$WORLD_ROOT/s-T2.out.rc" 2>/dev/null)"
expect_eq "(w2) …in order, T2's run on the candidate built on T1's: one run each" "T1 T2 1 1 $(ll_nth_cand "$RW" T2)" \
  "$(ll_ev "$RW" published | sed 's/.*|row=\([^|]*\)|.*/\1/' | tr '\n' ' ')$(ll_lines "$LL_SIG/s-T1.runs") $(ll_lines "$LL_SIG/s-T2.runs") $(head -1 "$LL_SIG/s-T2.runs" 2>/dev/null)"

# ---------------------------------------------------------------------------
section "§ALONE: no orchestrator act between ready and published (AC-3.1)"
RL="$(ll_rworld)"
: > "$(world_verbs)"
ll_verb_bg "$RL" T1 "$WORLD_ROOT/l-T1.out"; ll_verb_bg "$RL" T2 "$WORLD_ROOT/l-T2.out"
ll_wait_file "$WORLD_ROOT/l-T1.out.rc" 300; ll_wait_file "$WORLD_ROOT/l-T2.out.rc" 300
expect_eq "(l1) both rows published" "0 0 2" \
  "$(cat "$WORLD_ROOT/l-T1.out.rc" 2>/dev/null) $(cat "$WORLD_ROOT/l-T2.out.rc" 2>/dev/null) $(ll_ev "$RL" published | awk 'END { print NR }')"
expect_eq "(l1) …and from ready to published the verb log holds only ready" "ready ready" \
  "$(tr '\n' ' ' < "$(world_verbs)" | sed 's/ $//')"
expect_true "(l1) …the branch holds both rows" git -C "$RL" merge-base --is-ancestor wt/T2 wave/x

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
# THE PROMISE, PRINTED (wave-39 T8; D11, AC-4.3): ready says once, at its start, the seconds its suites promise
# against the --within it was given; it is the first line, ahead of everything the carrier prints.
expect_eq "(n1p) AC-4.3 ready's first line is the promised total against --within: promised 600s of 60s" "promised 600s of 60s" \
  "$(printf '%s\n' "$LL_OUT" | head -n 1)"
expect_eq "(n1) …nothing run: no verdict, no log, no gate request" "0 0 $REQN" \
  "$(ll_ev "$RN" verdict | awk 'END { print NR }') $(ls "$RN/.bionic/docs/record/wave-x/line" 2>/dev/null | wc -l | tr -d ' ') $(ls "$BIONIC_GATE_DIR/requests" | wc -l | tr -d ' ')"
expect_eq "(n1) …the entry kept, its carrier gone" "T1 no" "$(line_state "$(ll_plan "$RN")" | cut -f1,4 | tr '\t' ' ')"
ll_verb "$RN" T1 --within 900
expect_eq "(n2) with the time, the same command lands it" "0" "$LL_RC"
expect_eq "(n2p) …its first line the same promise against the new bound: promised 600s of 900s" "promised 600s of 900s" \
  "$(printf '%s\n' "$LL_OUT" | head -n 1)"
# ll_req_last: hoisted to tests/landing-line.prelude.sh (part 2 calls it)
N2V="$(ll_ev "$RN" verdict)"
expect_regex "(n2f-pre) the gate's request for the run holds its promise and its admission and end" '^600 [0-9]+$' \
  "$(ll_req_last c.test.sh promise) $(ll_req_last c.test.sh actual)"
expect_eq "(n2f) AC-4.2 the verdict carries promised=600 and actual= the gate's ended less admitted, after reads=" \
  "600 $(ll_req_last c.test.sh actual) yes" \
  "$(ll_field "$N2V" promised) $(ll_field "$N2V" actual) $(printf '%s\n' "$N2V" | grep -qE '\|reads=[^|]+\|promised=600\|actual=[0-9]+\|at=' && echo yes)"
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

# ---------------------------------------------------------------------------
section "§GUARD (ready half): a row that commits .bionic is refused before any landing tree (AC-14.1)"
RU="$(ll_rworld)"; HU="$(ll_head "$RU")"
git -C "$RU/.worktrees/T1" add -f .bionic && git -C "$RU/.worktrees/T1" commit -qm "T1: the link, committed"
TU="$(git -C "$RU/.worktrees/T1" rev-parse HEAD)"
ll_verb "$RU" T1
expect_eq "(u1) ready exits 1" "1" "$LL_RC"
expect_eq "(u1) …printing GUARD, the path and the commit first" "GUARD T1 .bionic $TU" "$(printf '%s\n' "$LL_OUT" | head -1)"
expect_match "(u1) …then the guard's own line, the writer's tree in its fix, ending say ready again" \
  "spawn-worktree: REFUSED reason=bionic-committed path=.bionic commit=${TU:0:12} branch=wt/T1 onto=wave/x fix='git -C ${RU}/.worktrees/T1 rm -r --cached .bionic, commit, say ready again' — *" \
  "$(printf '%s\n' "$LL_OUT" | sed -n 2p)"
expect_false "(u1) …before any landing tree exists" test -e "$RU/.bionic/tmp/landing"
expect_eq "(u1) …nothing appended, nothing published" "0 $HU" "$(ll_lines "$(ll_rec "$RU")") $(ll_head "$RU")"
RU2="$(ll_rworld)"; HU2="$(ll_head "$RU2")"
git -C "$RU2/.worktrees/T1" add -f .bionic && git -C "$RU2/.worktrees/T1" commit -qm "T1: the link, committed"
TU2="$(git -C "$RU2/.worktrees/T1" rev-parse HEAD)"
LL_MUTANT='s/_wt_bionic_committed "\$root" "\$acc" "\$head"/false/' LL_MUTANT_FN=line_ready ll_drive "$RU2" T1 "$WORLD_ROOT/u-T1.out"
ll_wait_file "$WORLD_ROOT/u-T1.out.rc" 300
expect_eq "(u2m-pre) the mutant ran: the row entered the line" "1" "$(ll_ev "$RU2" ready | awk 'END { print NR }')"
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
expect_absent "(v1) …and no RED" "RED " "$LL_OUT"
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
expect_eq "(t6m-pre) the mutant ran: the row entered the line" "1" "$(ll_ev "$RT6" ready | awk 'END { print NR }')"
expect_true "(t6m) MUTANT second-none branch removed: a third run starts (the rows can fail)" \
  test "$(ll_ev "$RT6" verdict | grep -c 'result=none')" -ge 3
expect_eq "(t6m) …and no stalled event" "" "$(ll_ev "$RT6" stalled)"

# ---------------------------------------------------------------------------
section "§STANDING: a red that fails at the accepted head too is the branch's, not the row's (AC-9.3)"
#
# The working branch carries its own red: `a` fails `FAIL: a planted red` at the accepted head, and
# fails one line more when a file `extra-fail` is present. T1 commits that file (a red it adds); T2
# adds nothing to `a`.
ll_standing_world() {  # [T1's file] [its text] [dup: the head fails the planted label twice] -> root
  local r f="${1:-extra-fail}" t="${2:-T1 adds this}"
  r="$(ll_world)" || return 1
  ll_launch "$r" T1 a; ll_launch "$r" T2 a
  printf '#!/bin/bash\necho "PASS: a ran"\necho "FAIL: a planted red"\n[ ! -f dup-at-head ] || [ -f fix ] || echo "FAIL: a planted red"\n[ ! -f extra-fail ] || echo "FAIL: $(cat extra-fail)"\necho; echo "a.test.sh: 1/2 passed, 1 failed  sections=1 setup=0"; exit 1\n' \
    > "$r/tests/a.test.sh"
  if [ -n "${3:-}" ]; then : > "$r/dup-at-head"; git -C "$r" add dup-at-head || return 1; fi
  git -C "$r" commit -qam "the branch's own red" || return 1
  printf '%s\n' "$t" > "$r/.worktrees/T1/$f"
  git -C "$r/.worktrees/T1" add "$f" && git -C "$r/.worktrees/T1" commit -qm "T1: one failing line more" || return 1
  printf '%s' "$r"
}
RS="$(ll_standing_world)"; HS="$(ll_head "$RS")"
ll_verb "$RS" T1
KS1="$(ll_last_cand "$RS" T1)"
LS1="$RS/.bionic/docs/record/wave-x/line/T1-a-${KS1:0:12}.log"; LSH="$RS/.bionic/docs/record/wave-x/line/T1-a-${HS:0:12}.log"
expect_eq "(s1) a red that adds a failing line is the row's: exit 1, RED and the candidate's log" "1|RED T1 a.test.sh $LS1" "$LL_RC|$LL_OUT"
expect_regex "(s1) …after the suite ran once at the accepted head, in the landing tree, red there too" \
  "^line/v1\\|ev=verdict\\|row=T1\\|commit=${HS}\\|suite=a.test.sh\\|result=red\\|log=${LSH}\\|" "$(ll_ev "$RS" verdict)"
expect_contains "(s1) …its log is the head's own run" "FAIL: a planted red" "$(cat "$LSH" 2>/dev/null)"
expect_eq "(s1) …no standing event, the row returned" "|T1" \
  "$(ll_ev "$RS" standing)|$(ll_ev "$RS" returned | sed 's/.*|row=\([^|]*\)|.*/\1/')"
ll_verb "$RS" T2
KS2="$(ll_last_cand "$RS" T2)"
expect_eq "(s2) a red whose failing lines all fail at the head: T2 is published (exit 0)" "0 $KS2" "$LL_RC $(ll_head "$RS")"
expect_eq "(s2) …its own verdict red on its candidate" "red" "$(ll_results "$RS" T2 "$KS2")"
expect_eq "(s2) …the head's run remembered for that head: one run there, not two" "1" \
  "$(ll_ev "$RS" verdict | grep -c "|commit=${HS}|")"
expect_regex "(s2) …one standing event for that head, its failing lines, the head's log, and its cause: code, no run disagreeing (AC-7.2)" \
  "^line/v1\\|ev=standing\\|head=${HS}\\|suite=a.test.sh\\|lines=1\\|log=${LSH}\\|cause=code\\|against=-\\|at=[0-9T:-]+Z$" "$(ll_ev "$RS" standing)"
git -C "$RS/.worktrees/T1" rm -q extra-fail && git -C "$RS/.worktrees/T1" commit -qm "T1: the added line taken out"
# A plain commit on the branch makes a head no run has read (T2's published candidate was itself run,
# so as the head it is already remembered).
printf 'note\n' > "$RS/NOTE.txt"; git -C "$RS" add NOTE.txt; git -C "$RS" commit -qm "a plain commit on the branch"
HS3="$(ll_head "$RS")"
ll_verb "$RS" T1
expect_eq "(s3) the same row without its line, on a new head: published (exit 0)" "0" "$LL_RC"
expect_eq "(s3) …the new head runs the suite once more: one run at it, a second standing event naming it" "1 2 1" \
  "$(ll_ev "$RS" verdict | grep -c "|commit=${HS3}|") $(ll_ev "$RS" standing | awk 'END { print NR }') $(ll_ev "$RS" standing | grep -c "|head=${HS3}|")"
# MUTANT: the comparison inverted. T1's added line is taken for the branch's, and T1 publishes.
RSM="$(ll_standing_world)"
LL_MUTANT='s/-eq 0 \]/-ne 0 ]/' LL_MUTANT_FN=_line_red_owner ll_drive "$RSM" T1 "$WORLD_ROOT/sm.out"
ll_wait_file "$WORLD_ROOT/sm.out.rc" 300
expect_eq "(s4m-pre) the mutant ran: T1 was proved on a candidate" "red" "$(ll_results "$RSM" T1 "$(ll_last_cand "$RSM" T1)")"
expect_eq "(s4m) MUTANT comparison inverted: a red the row adds is published (the rows can fail)" "0 T1" \
  "$(cat "$WORLD_ROOT/sm.out.rc" 2>/dev/null) $(ll_ev "$RSM" published | sed 's/.*|row=\([^|]*\)|.*/\1/')"
# THE FAILING LINES ARE COUNTED, line for line (fixit T51): the head fails `FAIL: a planted red` once; a
# candidate that fails the SAME label a second time has added a line, though no new text.
RS5="$(ll_standing_world extra-fail 'a planted red')"; HS5="$(ll_head "$RS5")"
ll_verb "$RS5" T1
KS5="$(ll_last_cand "$RS5" T1)"
LS5="$RS5/.bionic/docs/record/wave-x/line/T1-a-${KS5:0:12}.log"
expect_eq "(s5) a second failing line under a label the head fails once is the row's: exit 1, RED and the candidate's log" \
  "1|RED T1 a.test.sh $LS5" "$LL_RC|$LL_OUT"
expect_eq "(s5) …that log holds the label twice, the added line among them; the head's run holds it once" "2 1" \
  "$(grep -c '^FAIL: a planted red$' "$LS5" 2>/dev/null) $(grep -c '^FAIL: a planted red$' "$RS5/.bionic/docs/record/wave-x/line/T1-a-${HS5:0:12}.log" 2>/dev/null)"
expect_eq "(s5) …no standing event, the row returned" "|T1" \
  "$(ll_ev "$RS5" standing)|$(ll_ev "$RS5" returned | sed 's/.*|row=\([^|]*\)|.*/\1/')"
# The head fails the label twice (`dup-at-head`); a row that adds nothing fails it twice too.
RS6="$(ll_standing_world extra-fail 'T1 adds this' dup)"; HS6="$(ll_head "$RS6")"
ll_verb "$RS6" T2
KS6="$(ll_last_cand "$RS6" T2)"
expect_eq "(s6) equal counts under one label: T2 is published (exit 0), its own verdict red" "0 $KS6 red" \
  "$LL_RC $(ll_head "$RS6") $(ll_results "$RS6" T2 "$KS6")"
expect_regex "(s6) …one standing event for that head naming both of its failing lines" \
  "^line/v1\\|ev=standing\\|head=${HS6}\\|suite=a.test.sh\\|lines=2\\|" "$(ll_ev "$RS6" standing)"
# T1 adds `fix`, which takes one of the head's two lines away: fewer lines than the head's is standing.
RS7="$(ll_standing_world fix 'T1 fixes one' dup)"; HS7="$(ll_head "$RS7")"
ll_verb "$RS7" T1
KS7="$(ll_last_cand "$RS7" T1)"
LS7="$RS7/.bionic/docs/record/wave-x/line/T1-a-${KS7:0:12}.log"
expect_eq "(s7) one line fewer than the head's under the label: published (exit 0)" "0 $KS7" "$LL_RC $(ll_head "$RS7")"
expect_eq "(s7) …the candidate's own run held the label once, the head's twice (the rows can fail)" "1 2" \
  "$(grep -c '^FAIL: a planted red$' "$LS7" 2>/dev/null) $(grep -c '^FAIL: a planted red$' "$RS7/.bionic/docs/record/wave-x/line/T1-a-${HS7:0:12}.log" 2>/dev/null)"
# MUTANT: the set difference restored (a line counts as new only when its text is absent at the head).
RS8="$(ll_standing_world extra-fail 'a planted red')"
LL_MUTANT='s/c\[k\] > h\[k\]/!(k in h)/' LL_MUTANT_FN=_line_new_fails ll_drive "$RS8" T1 "$WORLD_ROOT/s8m.out"
ll_wait_file "$WORLD_ROOT/s8m.out.rc" 300
expect_eq "(s8m-pre) the mutant ran: T1 was proved on a candidate" "red" "$(ll_results "$RS8" T1 "$(ll_last_cand "$RS8" T1)")"
expect_eq "(s8m) MUTANT set difference restored: the second line under the label lands (the rows can fail)" "0 T1" \
  "$(cat "$WORLD_ROOT/s8m.out.rc" 2>/dev/null) $(ll_ev "$RS8" published | sed 's/.*|row=\([^|]*\)|.*/\1/')"

# ---------------------------------------------------------------------------
section "§AHEAD-CONFLICT: a wait on a conflicting candidate ahead ends when that entry resolves (ruling A-orch-51)"
#
# T1 is ahead, proving on a suite that waits for its go; T2 adds the same new file with other text, so
# it conflicts with T1's candidate (not with the accepted head) and waits for T1. Once T1 publishes,
# the accepted head is T1's candidate: T2 rebuilds on it, conflicts with the accepted head, and is
# returned with CONFLICT — it never sleeps on for ever (read-adversarial-p12, the reader's probe3).
ll_conflict_world() {  # <tag> -> root
  local r
  r="$(ll_rworld)" || return 1
  ll_commit_suite "$r" T1 a "$(ll_block_body "$1-T1" a green)"
  printf 'one\n' > "$r/.worktrees/T1/shared.txt"; git -C "$r/.worktrees/T1" add shared.txt && git -C "$r/.worktrees/T1" commit -qm "T1: shared one"
  printf 'two\n' > "$r/.worktrees/T2/shared.txt"; git -C "$r/.worktrees/T2" add shared.txt && git -C "$r/.worktrees/T2" commit -qm "T2: shared two"
  printf '%s' "$r"
}
RK="$(ll_conflict_world k)"
ll_verb_bg "$RK" T1 "$WORLD_ROOT/k-T1.out"
ll_wait_lines "$LL_SIG/k-T1.runs" 1
ll_verb_bg "$RK" T2 "$WORLD_ROOT/k-T2.out"; K2_BG=$!
sleep 2
expect_false "(k0-pre) T2 waits on T1's candidate while T1 proves" test -e "$WORLD_ROOT/k-T2.out.rc"
touch "$LL_SIG/k-T1.go"
ll_wait_file "$WORLD_ROOT/k-T1.out.rc" 300
ll_wait_file "$WORLD_ROOT/k-T2.out.rc" 150 || ll_kill_bg "$K2_BG"
expect_eq "(k1) T1 publishes; T2's wait then ends: CONFLICT with the accepted head, exit 1" "0|1|CONFLICT T2 shared.txt" \
  "$(cat "$WORLD_ROOT/k-T1.out.rc" 2>/dev/null)|$(cat "$WORLD_ROOT/k-T2.out.rc" 2>/dev/null)|$(cat "$WORLD_ROOT/k-T2.out" 2>/dev/null)"
expect_regex "(k1) …T2 returned why=conflict" "^line/v1\\|ev=returned\\|row=T2\\|why=conflict\\|detail=shared.txt\\|" "$(ll_ev "$RK" returned)"
# MUTANT: the wait's end removed. T2 sleeps on after T1 publishes.
RKM="$(ll_conflict_world km)"
ll_verb_bg "$RKM" T1 "$WORLD_ROOT/km-T1.out"
ll_wait_lines "$LL_SIG/km-T1.runs" 1
LL_MUTANT='s/! _line_ahead_open /false \&\& _line_ahead_open /' LL_MUTANT_FN=_line_carry \
  ll_drive "$RKM" T2 "$WORLD_ROOT/km-T2.out"; KM2_BG=$!
sleep 2; touch "$LL_SIG/km-T1.go"
ll_wait_file "$WORLD_ROOT/km-T1.out.rc" 300
ll_wait_file "$WORLD_ROOT/km-T2.out.rc" 80
expect_eq "(k2m-pre) the mutant ran: T1 published and T2 entered the line" "0 1" \
  "$(cat "$WORLD_ROOT/km-T1.out.rc" 2>/dev/null) $(ll_ev "$RKM" ready | grep -c '|row=T2|')"
expect_false "(k2m) MUTANT the wait's end removed: T2 still waits 8 s after T1 published (the row can fail)" \
  test -e "$WORLD_ROOT/km-T2.out.rc"
ll_kill_bg "$KM2_BG"

# ---------------------------------------------------------------------------
section "§ROW: the publish writes the row — status, step line, ledger line — in one transaction, and marks the roster (AC-3.2)"
#
# Inside the lock, after the `published` event: `session-poker.sh row-landed <id> <commit> <at>`, run as a
# command on the BOUND plan (one copy, one dry commit as a writer, one swap: all three lines or none),
# then the roster mark `landed=<40-hex> landed_at=<ISO-UTC>` on the row's roster line. The writer's tree
# stands: it goes at `stopped <name>` (tests/stop-orders.test.sh Section 10). Mutants are seds over the
# functions in the driver's own process (LL_MUTANT_FN), never the tracked file.
ll_lworld() {  # -> ll_rworld with a `## Dispatch ledger` table holding a row for T1 (none for T2)
  local r p
  r="$(ll_rworld)" || return 1
  p="$(ll_plan "$r")"
  printf '\n## Dispatch ledger\n\n| id | agent | dispatched | expected | artifact | landed | notes |\n|---|---|---|---|---|---|---|\n| T1 | wx-T1 | 2026-10-07T00:00Z | 10 min | T1.md | — | tree T1 |\n' >> "$p"
  printf '%s' "$r"
}
ll_cell() {  # <plan> <table: tasks|ledger> <id> <column> -> the cell, trimmed
  awk -F'|' -v sect="$2" -v id="$3" -v col="$4" '
    /^## / { on = (sect == "tasks" ? ($0 ~ /^## Tasks/) : ($0 ~ /^## Dispatch ledger/)); hdr = 0; next }
    on && /^\|/ { for (i = 2; i < NF; i++) { c = $i; gsub(/^ +| +$/, "", c); v[i] = c }
      if (!hdr) { for (i = 2; i < NF; i++) if (v[i] == col) k = i; hdr = 1; next }
      if (v[2] == id && k) { print v[k]; exit } }' "$1"
}
ll_stepline() { grep -E "^- $2:" "$1" | head -1; }   # <plan> <id> -> the row's `- T<n>:` line
ll_mark() { grep "|name=$2|" "$1/.bionic/tmp/roster-$WORLD_SID.state" | tail -1; }   # <root> <name> -> its latest roster line

RW="$(ll_lworld)"; PW="$(ll_plan "$RW")"
: > "$(world_verbs)"
ll_verb "$RW" T1
LL_OUT_W1="$LL_OUT"
KW="$(ll_field "$(ll_ev "$RW" published | grep '|row=T1|' | tail -1)" commit)"
AW="$(ll_field "$(ll_ev "$RW" published | grep '|row=T1|' | tail -1)" at)"
expect_eq "(w0) precondition: ready exits 0 and the published event names a 40-hex candidate" "0 1" \
  "$LL_RC $(printf '%s\n' "$KW" | grep -cE '^[0-9a-f]{40}$')"
expect_eq "(w1) the row's status is landed" "landed" "$(ll_cell "$PW" tasks T1 status)"
expect_eq "(w1b) …the other row's status is as it was (the positive on that extractor)" "active" "$(ll_cell "$PW" tasks T2 status)"
expect_eq "(w2) the row's - T1: line gains the landed commit and the publish's instant" "- T1: active landed ${KW} ${AW}" "$(ll_stepline "$PW" T1)"
expect_eq "(w3) the ledger row's landed cell reads landed <at> <commit>" "landed ${AW} ${KW}" "$(ll_cell "$PW" ledger T1 landed)"
expect_contains "(w4) the row's roster line gains landed= and landed_at=, the same commit and instant" \
  "|landed=${KW}|landed_at=${AW}" "$(ll_mark "$RW" wx-T1)"
if [ -d "$RW/.worktrees/T1" ]; then ok "(w5) the writer's tree stands after its landing: it goes at the stop"; else no "(w5) the writer's tree stands after its landing: it goes at the stop"; fi
ll_verb "$RW" T2
KW2="$(ll_field "$(ll_ev "$RW" published | grep '|row=T2|' | tail -1)" commit)"
expect_eq "(w6) a second row lands with no verb between: ready twice in the verb log" "$(printf 'ready\nready')" "$(cat "$(world_verbs)")"
expect_eq "(w6b) …its status is landed" "landed" "$(ll_cell "$PW" tasks T2 status)"
expect_eq "(w6c) …and the ledger, which had no row T2, gains one with its landed cell" \
  "landed $(ll_field "$(ll_ev "$RW" published | grep '|row=T2|' | tail -1)" at) ${KW2}" "$(ll_cell "$PW" ledger T2 landed)"
expect_eq "(w6d) …and T1's row still reads as its landing wrote it" "landed ${AW} ${KW}" "$(ll_cell "$PW" ledger T1 landed)"

# ONE TRANSACTION: a ledger the verb cannot write (two rows T1) refuses the whole write after the publish;
# the status and the step line are not written either, and the refusal is printed, never swallowed.
RX="$(ll_lworld)"; PX="$(ll_plan "$RX")"
printf '| T1 | wx-T1 | 2026-10-07T00:00Z | 10 min | T1.md | — | a second row T1 |\n' >> "$PX"
PX0="$(cat "$PX")"
ll_verb "$RX" T1
expect_eq "(w7) a refused plan write after the publish: ready still exits 0 (the row is published)" "0" "$LL_RC"
expect_eq "(w7b) …and the plan is byte-identical: no status, no step line, no ledger line" "$PX0" "$(cat "$PX")"
expect_contains "(w7c) …the verb's refusal is printed" "carries more than one row T1" "$LL_OUT"
expect_contains "(w7d) …with the row and what is owed by hand" "PLAN-UNWRITTEN T1" "$LL_OUT"
expect_contains "(w7e) …while the roster mark is still written" "|landed=" "$(ll_mark "$RX" wx-T1)"

# THE DEBT T5 WROTE IS WHAT THE GATE READS AFTER THE WRITE (wave-27 passes 60, 63): a declared red
# publishes with its debt; the writer-mode write is admitted on the REAL plan, and the gate's own reader
# of the bound plan's record (lib/proof.sh `proof_debts`) still deals the debt.
RD="$(ll_world)"; PD="$(ll_plan "$RD")"
ll_launch "$RD" T1 'a, b.test.sh' lands_red='b.test.sh until T9'
ll_redsuite "$RD" T1 b
ll_verb "$RD" T1
expect_eq "(w8) precondition: the declared red publishes (exit 0, DEBT said)" "0 1" \
  "$LL_RC $(printf '%s\n' "$LL_OUT" | grep -c '^DEBT T1 b.test.sh ')"
expect_eq "(w8b) the plan write is admitted on the real plan over the debt: status landed" "landed" "$(ll_cell "$PD" tasks T1 status)"
expect_eq "(w8c) …and the gate's reader of the bound plan deals the debt T5 wrote" "debt	b.test.sh	T9" \
  "$(bash -c '. "$1/proof.sh" && proof_debts "$2"' _ "$REPO/payload/scripts/lib" "$PD" | cut -f1-3)"

# MUTANTS, each run as the driver runs ready; the rows above fail on each.
RM1="$(ll_lworld)"
LL_MUTANT_FN=_line_plan_write LL_MUTANT='s|bash "$poker" row-landed|cp "$1" "$1.copy" \&\& : |' ll_drive "$RM1" T1 "$WORLD_ROOT/m1.out"
ll_wait_file "$WORLD_ROOT/m1.out.rc" 600
expect_eq "(w1m) mutant: the write goes to a copy — the mutant ran and published (rc 0)" "0" "$(cat "$WORLD_ROOT/m1.out.rc" 2>/dev/null)"
expect_eq "(w1m2) …and the bound plan's status is NOT landed: (w1) is the row that fails" "active" "$(ll_cell "$(ll_plan "$RM1")" tasks T1 status)"
RM2="$(ll_lworld)"
LL_MUTANT_FN=_line_roster_mark LL_MUTANT='s|roster_mark_landed |: |' ll_drive "$RM2" T1 "$WORLD_ROOT/m2.out"
ll_wait_file "$WORLD_ROOT/m2.out.rc" 600
expect_eq "(w4m) mutant: the mark skipped — the mutant ran and published (rc 0)" "0" "$(cat "$WORLD_ROOT/m2.out.rc" 2>/dev/null)"
expect_absent "(w4m2) …and the roster line carries no mark: (w4) is the row that fails" "|landed=" "$(ll_mark "$RM2" wx-T1)"
expect_contains "(w4m3) …the roster line read is the row's (the positive on that extractor)" "|name=wx-T1|" "$(ll_mark "$RM2" wx-T1)"
RM3="$(ll_lworld)"
LL_MUTANT_FN=_line_carry LL_MUTANT='s|_line_owed "$row" "$cand" "$name";|_line_owed "$row" "$cand" "$name"; git -C "$root" worktree remove --force "$wt";|' \
  ll_drive "$RM3" T1 "$WORLD_ROOT/m3.out"
ll_wait_file "$WORLD_ROOT/m3.out.rc" 600
expect_eq "(w5m) mutant: the removal moved back to the landing — the mutant ran and published (rc 0)" "0" "$(cat "$WORLD_ROOT/m3.out.rc" 2>/dev/null)"
if [ ! -d "$RM3/.worktrees/T1" ]; then ok "(w5m2) …and the tree is gone: (w5) is the row that fails"; else no "(w5m2) …and the tree is gone: (w5) is the row that fails"; fi

# ---------------------------------------------------------------------------
section "§SERVED-EVIDENCE: a landing writes its criteria's evidence — the log of the suite each criterion's eval names (wave-31 T22; REQ-15 AC-15.1, AC-15.2; D15, A-orch-51)"
#
# `ready` publishes, then `row-landed` writes the row. After the status, the step line and the ledger
# line it writes `evidence: <the row's green log for the suite the criterion's eval: names>` into every
# criterion the row SERVES (its `serves` cell naming the AC id or its REQ, the relation matrix-render's
# task: cell reads), when the cell is `pending` or already a landing's path; any other value is a hand
# fill and stays. A criterion whose eval names a suite the landing did not run, a T0 criterion, and a
# criterion no landing row serves are left as they were. The path is docs-root-relative.
se_world() {  # -> a world whose rows T1, T2 both land on a.test.sh and serve criteria of the plan below
  local r p
  r="$(ll_world)" || return 1
  p="$(ll_plan "$r")"
  ll_launch "$r" T1 a.test.sh; ll_launch "$r" T2 a.test.sh
  awk '/^\| T1 \|/ { sub(/\| REQ-1 \|/, "| AC-8.1 AC-7.1 AC-5.1 |") }
       /^\| T2 \|/ { sub(/\| REQ-1 \|/, "| REQ-8 |") }
       { print }' "$p" > "$p.n" && mv "$p.n" "$p"
  cat >> "$p" <<'PLAN'

## Dispatch ledger

| id | agent | dispatched | expected | artifact | landed | notes |
|---|---|---|---|---|---|---|
| T1 | wx-T1 | 2026-10-07T00:00Z | 10 min | T1.md | — | tree T1 |
| T2 | wx-T2 | 2026-10-07T00:00Z | 10 min | T2.md | — | tree T2 |

## Eval design

| Requirement | Approach | Criterion | Eval type | Eval | Fails when |
|---|---|---|---|---|---|
| REQ-8 | the suite | AC-8.1 | T2 | `a.test.sh` §SECTION-A: the first | wrong |
| REQ-8 | the suite | AC-8.2 | T2 | `b.test.sh` §SECTION-B: the second | wrong |
| REQ-7 | a grep | AC-7.1 | T0 | grep -c foo file | wrong |
| REQ-6 | the suite | AC-6.1 | T2 | `a.test.sh` §SECTION-A: the unserved | wrong |
| REQ-5 | the suite | AC-5.1 | T2 | `a.test.sh` §SECTION-A: the hand fill | wrong |

## Verification Matrix

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-8.1 | T2 | pending | — | — |
| AC-8.2 | T2 | pending | — | — |
| AC-7.1 | T0 | pending | — | — |
| AC-6.1 | T2 | pending | — | — |
| AC-5.1 | T2 | pending | — | — |

AC-8.1:
  provenance: p
  fails-when: f
  eval: T2 — `a.test.sh` §SECTION-A: the first
  task: T1
  evidence: pending
AC-8.2:
  provenance: p
  fails-when: f
  eval: T2 — `b.test.sh` §SECTION-B: the second
  task: T2
  evidence: pending
AC-7.1:
  provenance: p
  fails-when: f
  eval: T0 — grep -c foo file
  task: T1
  evidence: pending
AC-6.1:
  provenance: p
  fails-when: f
  eval: T2 — `a.test.sh` §SECTION-A: the unserved
  task: pending
  evidence: pending
AC-5.1:
  provenance: p
  fails-when: f
  eval: T2 — `a.test.sh` §SECTION-A: the hand fill
  task: T1
  evidence: record/hand/filled-by-the-orchestrator.log
PLAN
  printf '%s' "$r"
}
se_ev() {  # <plan> <AC id> -> the evidence: cell of that criterion's block
  awk -v ac="$2:" '{ h = $0; sub(/^[-*+][ \t]+/, "", h) }
    index(h, ac) == 1 { f = 1; next }
    /^[^ \t]/ { f = 0 }
    f && /^[ \t]+evidence:/ { v = $0; sub(/^[ \t]+evidence:[ \t]*/, "", v); print v; exit }' "$1"
}
se_log() {  # <root> <row> -> the docs-root-relative path of the row's green a.test.sh verdict log
  local l; l="$(ll_field "$(ll_ev "$1" verdict | grep "|row=$2|" | grep '|suite=a.test.sh|' | grep '|result=green|' | tail -1)" log)"
  printf '%s' "${l#"$1/.bionic/docs/"}"
}
RS="$(se_world)"; PS="$(ll_plan "$RS")"
expect_eq "(se0) precondition: the criteria read pending before any landing, hand fill in place (positive on se_ev)" \
  "pending pending pending pending record/hand/filled-by-the-orchestrator.log" \
  "$(se_ev "$PS" AC-8.1) $(se_ev "$PS" AC-8.2) $(se_ev "$PS" AC-7.1) $(se_ev "$PS" AC-6.1) $(se_ev "$PS" AC-5.1)"
ll_verb "$RS" T1
SE_LOG1="$(se_log "$RS" T1)"
expect_eq "(se1) precondition: ready exits 0, the row is landed, and its green a.test.sh verdict names a log under record/wave-x/line/" \
  "0 landed 1" "$LL_RC $(ll_cell "$PS" tasks T1 status) $(printf '%s\n' "$SE_LOG1" | grep -cE '^record/wave-x/line/T1-.*\.log$')"
expect_eq "(se2) AC-15.1 the criterion the row serves by its id, whose eval names a.test.sh, reads the row's log (docs-root-relative)" \
  "$SE_LOG1" "$(se_ev "$PS" AC-8.1)"
if [ -f "$RS/.bionic/docs/$SE_LOG1" ]; then ok "(se2b) …and that path is a file under the docs root"; else no "(se2b) …and that path is a file under the docs root" "no $RS/.bionic/docs/$SE_LOG1"; fi
expect_eq "(se3) a criterion whose eval names a suite the landing did not run (b.test.sh) is untouched" "pending" "$(se_ev "$PS" AC-8.2)"
expect_eq "(se4) a T0 criterion the row serves (a grep, no suite) is untouched" "pending" "$(se_ev "$PS" AC-7.1)"
expect_eq "(se5) a criterion no row serves is untouched" "pending" "$(se_ev "$PS" AC-6.1)"
expect_eq "(se6) a hand-filled value is untouched, though the row serves it and its eval names a.test.sh" \
  "record/hand/filled-by-the-orchestrator.log" "$(se_ev "$PS" AC-5.1)"
# T2 changes a.test.sh, so its landing runs the suite again rather than reusing T1's verdict (wave-39 T1; D5):
# a candidate whose suite read the same blobs would reuse it and write no log of its own (§REUSE).
ll_commit_suite "$RS" T2 a "$(printf 'echo "PASS: a, as T2 changed it"\necho\necho "a.test.sh: 1/1 passed, 0 failed  sections=1 setup=0"\nexit 0')"
ll_verb "$RS" T2
SE_LOG2="$(se_log "$RS" T2)"
expect_eq "(se7) precondition: the second row lands, and its log is another path than the first's" \
  "0 landed 1" "$LL_RC $(ll_cell "$PS" tasks T2 status) $([ -n "$SE_LOG2" ] && [ "$SE_LOG2" != "$SE_LOG1" ] && echo 1)"
expect_eq "(se8) AC-15.2 two rows serving AC-8.1 (T1 by its id, T2 by its REQ) landed in turn: one path, the newer" \
  "$SE_LOG2" "$(se_ev "$PS" AC-8.1)"
expect_eq "(se8b) …one evidence line in the block, not two" "1" "$(awk '{ h = $0; sub(/^[-*+][ \t]+/, "", h) } index(h, "AC-8.1:") == 1 { f = 1; next } /^[^ \t]/ { f = 0 } f && /^[ \t]+evidence:/ { n++ } END { print n + 0 }' "$PS")"
expect_eq "(se9) T2 serves AC-8.2 by REQ-8, but its eval names b.test.sh, which T2 did not run: untouched" "pending" "$(se_ev "$PS" AC-8.2)"
expect_eq "(se10) the hand fill is untouched by the second landing too" "record/hand/filled-by-the-orchestrator.log" "$(se_ev "$PS" AC-5.1)"
# A REUSED SUITE IS THE ROW'S GREEN FOR ITS CRITERIA (wave-39 T2; D5, A-orch-11): a row whose candidate reads what a
# proved one read runs nothing and writes no verdict of its own (§REUSE), so its criteria read the log of the verdict
# its reuse line names. Here T1 no longer serves AC-8.1, which T2 serves by REQ-8 alone; T2 leaves a.test.sh as T1
# landed it, so its landing skips a on the head's green, and AC-8.1 reads T1's log.
RS2="$(se_world)"; PS2="$(ll_plan "$RS2")"
awk '/^\| T1 \|/ { sub(/\| AC-8\.1 AC-7\.1 AC-5\.1 \|/, "| AC-7.1 AC-5.1 |") } { print }' "$PS2" > "$PS2.n" && mv "$PS2.n" "$PS2"
ll_verb "$RS2" T1
SE2_LOG1="$(se_log "$RS2" T1)"
expect_eq "(se11-pre) T1 lands its own run of a.test.sh, and AC-8.1, which it no longer serves, still reads pending" \
  "0 1 pending" "$LL_RC $(printf '%s\n' "$SE2_LOG1" | grep -cE '^record/wave-x/line/T1-.*\.log$') $(se_ev "$PS2" AC-8.1)"
ll_verb "$RS2" T2
SE2_K1="$(ll_field "$(ll_ev "$RS2" published | grep '|row=T1|' | tail -1)" commit)"
expect_eq "(se11-pre) T2 lands with no run of its own: its landing skipped a.test.sh, whose reuse line names T1's candidate" \
  "0 1 0 1" "$LL_RC $(printf '%s\n' "$LL_OUT" | grep -c '^skip a\.test\.sh reads=') $(ll_ev "$RS2" verdict | grep -c '|row=T2|') $(ll_ev "$RS2" reused | grep '|row=T2|' | grep -c "|from=${SE2_K1}|")"
expect_eq "(se11) A-orch-11: the criterion only T2 serves reads the log of the verdict T2's reuse line names" \
  "$SE2_LOG1" "$(se_ev "$PS2" AC-8.1)"
expect_eq "(se12) …and the criterion whose suite T2 neither ran nor reused (b.test.sh) is untouched" "pending" "$(se_ev "$PS2" AC-8.2)"

# ---------------------------------------------------------------------------
section "§OWED: what is still owed prints as one line, after the write and the mark, naming no verb (AC-3.3)"
expect_eq "(o1) the owed line is printed once, last, byte for byte, the name off the roster row" \
  "landed T1 ${KW} — owed: complete task T1, then stop wx-T1" "$(printf '%s\n' "$LL_OUT_W1" | grep '^landed T1 ')"
expect_eq "(o1b) …exactly one such line, and it is the last line of ready's output" "1 yes" \
  "$(printf '%s\n' "$LL_OUT_W1" | grep -c '^landed T1 ') $([ "$(printf '%s\n' "$LL_OUT_W1" | tail -1)" = "landed T1 ${KW} — owed: complete task T1, then stop wx-T1" ] && echo yes || echo no)"
expect_absent "(o2) …it names no plan or roster verb" "row-landed" "$LL_OUT_W1"
expect_absent "(o2b) …nor the poker script" "session-poker" "$LL_OUT_W1"
expect_contains "(o3) by the time it prints, the mark and the plan row are written (read back from the mutant-free run)" \
  "landed=${KW}" "$(ll_mark "$RW" wx-T1)"


# ---------------------------------------------------------------------------
section "§TOO-LONG: ready refuses a Lands-on suite whose gate promise is over the suite bar; nothing runs (wave-39 T39; D1, AC-3.2)"
#
# THE SUITE BAR (line.sh LINE_SUITE_BAR, 600): ten minutes of the gate's promise. A Lands-on suite promising more is
# refused before the row enters the line, one `too-long <suite> <s>s — split it` line each, exit 1: no ready event,
# no lease, no runner, no gate request. A suite at or under the bar runs. A suite the row removed is not judged
# (the carrier records it absent, §ABSENT), or a split row naming its old whole could never land.
# fails-when: a suite over the bar is run, or one under it is refused.
RT="$(ll_world)"; ll_launch "$RT" T1 a,c
( cd "$RT" && world_cost c.test.sh 700 )
( cd "$RT" && world_suite c green >/dev/null ) && git -C "$RT" add tests/c.test.sh && git -C "$RT" commit -qm "suite c"
REQT="$(ls "$BIONIC_GATE_DIR/requests" 2>/dev/null | wc -l | tr -d ' ')"
ll_verb "$RT" T1 --within 900
expect_eq "(tl1) AC-3.2 a Lands-on suite promising 700 s: exit 1, the first line too-long c.test.sh 700s — split it" \
  "1|too-long c.test.sh 700s — split it" "$LL_RC|$(printf '%s\n' "$LL_OUT" | head -n 1)"
expect_eq "(tl1b) …one too-long line, for c alone (a promises nothing recorded)" "1" \
  "$(printf '%s\n' "$LL_OUT" | grep -c '^too-long ')"
expect_eq "(tl2) …nothing run: no ready event, no verdict, no log, no gate request, no lease" "0 0 0 $REQT no" \
  "$(ll_ev "$RT" ready | awk 'END { print NR }') $(ll_ev "$RT" verdict | awk 'END { print NR }') $(ls "$RT/.bionic/docs/record/wave-x/line" 2>/dev/null | wc -l | tr -d ' ') $(ls "$BIONIC_GATE_DIR/requests" 2>/dev/null | wc -l | tr -d ' ') $(ll_lease_has "$(_line_landing_key "$RT" "$(ll_plan "$RT")" T1)")"
( cd "$RT" && world_cost c.test.sh 599 && world_cost c.test.sh 599 && world_cost c.test.sh 599 )
ll_verb "$RT" T1 --within 900
expect_eq "(tl3) AC-3.2 the same suite promising 599 s runs: exit 0, LANDED, c green" "0|LANDED T1|green" \
  "$LL_RC|$(printf '%s\n' "$LL_OUT" | grep '^LANDED ' | head -n 1 | cut -d' ' -f1-2)|$(ll_ev "$RT" verdict | while IFS= read -r v; do [ "$(ll_field "$v" suite)" = c.test.sh ] && ll_field "$v" result; done | tail -n 1)"
expect_eq "(tl3b) …and prints no too-long line" "0" "$(printf '%s\n' "$LL_OUT" | grep -c '^too-long ')"
# A row that removes a suite over the bar (the split itself) still names it on its Lands-on: not refused, it lands.
RT2="$(ll_world)"; ll_launch "$RT2" T1 "a.test.sh b.test.sh"
( cd "$RT2" && world_cost b.test.sh 700 )
git -C "$RT2/.worktrees/T1" rm -q tests/b.test.sh && git -C "$RT2/.worktrees/T1" commit -qm "T1: b split away"
ll_verb "$RT2" T1 --within 900
expect_eq "(tl4) a row that removed b (700 s) lands on what it holds: exit 0, LANDED, b absent, no too-long" "0|LANDED T1|absent|0" \
  "$LL_RC|$(printf '%s\n' "$LL_OUT" | grep '^LANDED ' | head -n 1 | cut -d' ' -f1-2)|$(ll_ev "$RT2" verdict | while IFS= read -r v; do [ "$(ll_field "$v" suite)" = b.test.sh ] && ll_field "$v" result; done | tail -n 1)|$(printf '%s\n' "$LL_OUT" | grep -c '^too-long ')"
# MUTANT: the bar check removed, the 700 s suite runs to a green verdict (the rows above can fail).
RT3="$(ll_world)"; ll_launch "$RT3" T1 c
( cd "$RT3" && world_cost c.test.sh 700 )
( cd "$RT3" && world_suite c green >/dev/null ) && git -C "$RT3" add tests/c.test.sh && git -C "$RT3" commit -qm "suite c"
LL_MUTANT='s/-gt "\$LINE_SUITE_BAR"/-gt 99999/' LL_MUTANT_FN=_line_too_long ll_drive "$RT3" T1 "$WORLD_ROOT/tl-T1.out" 900
ll_wait_file "$WORLD_ROOT/tl-T1.out.rc" 1200
expect_eq "(tl5m) MUTANT the bar check removed: the 700 s suite runs and is green (the rows can fail)" "0 green 0" \
  "$(cat "$WORLD_ROOT/tl-T1.out.rc" 2>/dev/null) $(ll_field "$(ll_ev "$RT3" verdict | tail -n 1)" result) $(grep -c '^too-long ' "$WORLD_ROOT/tl-T1.out" 2>/dev/null)"

finish
