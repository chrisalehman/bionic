#!/bin/bash
# tests/landing-line.test.sh — the landing line (wave-28 T3; REQ-1 AC-1.3, REQ-3 AC-3.6, AC-3.8,
# AC-3.9, REQ-5 AC-5.3, REQ-14 AC-14.1 publish half; spec D1, D2, D6, D9, D31).
#
# The line is the landing record's `line/v1` events and their fold (payload/scripts/lib/line.sh);
# a candidate is built in a landing tree the tool owns (lib/worktree.sh `landing_tree_take`,
# `landing_tree_point`), and `line_publish` fast-forwards the working branch to it under one lock.
# Every row runs in the model world (tests/lib/world.sh): a throwaway repository with the working
# branch `wave/x` checked out at its root, a bound plan and two row trees, T1 and T2. A carrier is
# a sleeping process whose `<pid>:<start>` the `ready` event names, so "present" is a live process.
# A publisher is its own process (`ll_pub`), so the lock's holder is never the suite's shell.
#
# SECTIONS: §EVENTS, §FOLD, §TREES (the pieces); §SAME, §PAIR, §BUSY, §MOVED, §GIT, §GUARD (the
# criteria). Mutants run in the publisher's own process (`LL_MUTANT`, a sed over `declare -f
# line_publish`), never on the tracked file, and stay as permanent guards that the rows can fail.
set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"

REPO="${BIONIC_SCRIPTS_DIR}"
LINE="${REPO}/payload/scripts/lib/line.sh"
SPAWN="${REPO}/payload/scripts/spawn-worktree.sh"

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0

ll_cleanup() {  # every carrier and stand-in runner the suite started
  local p
  [ -n "${WORLD_ROOT:-}" ] && [ -f "$WORLD_ROOT/pids" ] || return 0
  while IFS= read -r p; do kill "$p" 2>/dev/null; done < "$WORLD_ROOT/pids"
}
trap ll_cleanup EXIT
. "$(dirname "$0")/lib/world.sh"

LL_LOADED=0
if [ -r "$LINE" ] && . "$LINE" 2>/dev/null; then LL_LOADED=1; fi

# ---------------------------------------------------------------------------- helpers
ll_world() {  # -> a world root; its plan admitted by the real commit gate (the hand landing writes it)
  local r p
  r="$(world_repo)" || return 1
  [ -n "$r" ] && [ "$(git -C "$r" rev-parse --show-toplevel 2>/dev/null)" = "$r" ] || return 1
  p="$r/.bionic/docs/plans/epic-x/wave-x.plan.md"
  awk '{ print }
    /^working-branch: / { print "canonical_sdlc_version: 14" }
    /^current: 4$/ { print "approved-by: fixture 2026-10-04T00:00Z \"approved\""; print "- Step 4: started"; print "- T1: active"; print "- T2: active" }' \
    "$p" > "$p.n" && mv "$p.n" "$p"
  printf '%s' "$r"
}
ll_plan() { printf '%s/.bionic/docs/plans/epic-x/wave-x.plan.md' "$1"; }
ll_rec() { printf '%s/.bionic/docs/record/wave-x/landing-proofs.log' "$1"; }
ll_carrier() {  # -> `<pid>:<start>` of a new live process, kept until the suite exits
  local p
  sleep 900 >/dev/null 2>&1 &
  p=$!
  printf '%s\n' "$p" >> "$WORLD_ROOT/pids"
  printf '%s:%s' "$p" "$(_slots_since "$p")"
}
ll_dead() {  # -> `<pid>:<start>` of a process that has exited
  local p s
  sleep 30 >/dev/null 2>&1 &
  p=$!; s="$(_slots_since "$p")"
  kill "$p" 2>/dev/null; wait "$p" 2>/dev/null
  printf '%s:%s' "$p" "$s"
}
ll_ready() {  # <root> <row> <carrier> [suites] — the ready event a carrier appends
  local t="$1/.worktrees/$2"
  line_event "$(ll_plan "$1")" ready "row=$2" "name=wx-$2" "commit=$(git -C "$t" rev-parse HEAD)" \
    "branch=wt/$2" "tree=$t" "suites=${4:-a.test.sh}" "debt=-" "carrier=$3"
}
ll_cand() {  # <root> <row> <base> -> the candidate, built in a landing tree and recorded
  local t lt c
  t="$1/.worktrees/$2"
  lt="$(landing_tree_take "$1")" || return 1
  c="$(line_build "$lt" "$3" "$(git -C "$t" rev-parse HEAD)" "wt/$2")" || { landing_tree_free "$lt"; return 1; }
  landing_tree_free "$lt"
  line_event "$(ll_plan "$1")" candidate "row=$2" "base=$3" "commit=$c" "tree=$lt" >/dev/null || return 1
  printf '%s' "$c"
}
ll_green() {  # <root> <row> <candidate> [suite]
  line_event "$(ll_plan "$1")" verdict "row=$2" "commit=$3" "suite=${4:-a.test.sh}" result=green "log=-" >/dev/null
}
LL_PUB="$WORLD_ROOT/pub.sh"
cat > "$LL_PUB" <<'PUB'
#!/bin/bash
# <line.sh> <plan> <row>: one publisher, in a process of its own; LL_MUTANT is a sed over line_publish.
. "$1" || exit 99
if [ -n "${LL_MUTANT:-}" ]; then eval "$(declare -f line_publish | sed "$LL_MUTANT")"; fi
line_publish "$2" "$3"
PUB
ll_pub() {  # <root> <row> -> LL_OUT, LL_RC
  LL_OUT="$( cd "$1" && bash "$LL_PUB" "$LINE" "$(ll_plan "$1")" "$2" 2>&1 )"; LL_RC=$?
}
ll_pub_bg() {  # <root> <row> <out file> -> the publisher's pid; its rc lands in <out file>.rc
  ( cd "$1" && bash "$LL_PUB" "$LINE" "$(ll_plan "$1")" "$2" > "$3" 2>&1; echo $? > "$3.rc" ) &
  printf '%s' "$!"
}
ll_wait_file() {  # <file> [tenths] -> 0 once it exists
  local i=0 n="${2:-100}"
  while [ "$i" -lt "$n" ]; do [ -e "$1" ] && return 0; i=$((i + 1)); sleep 0.1; done
  return 1
}
ll_ev() {  # <root> <ev> -> the record's lines of that event
  grep "^line/v1|ev=$2|" "$(ll_rec "$1")" 2>/dev/null
}
ll_head() { git -C "$1" rev-parse --verify -q refs/heads/wave/x; }

if [ "$LL_LOADED" != 1 ]; then
  no "line.sh is present and sources ($LINE)" "it is missing or fails to source"
fi

# ---------------------------------------------------------------------------
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
printf '%s\n' "$(ll_dead)" > "$LT2.held"
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
expect_eq "(p5m) MUTANT lock skipped: both publishers exit 0 (the row can fail)" "0 0" \
  "$(cat "$WORLD_ROOT/p5-a.out.rc") $(cat "$WORLD_ROOT/p5-b.out.rc")"
expect_eq "(p5m) …and both append a published event" "2" "$(ll_ev "$RP5" published | grep -c 'row=T1|')"

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
LL_RUNNER="$WORLD_ROOT/runner"; mkdir -p "$LL_RUNNER/tests"
printf '#!/bin/bash\nwhile :; do sleep 1; done\n' > "$LL_RUNNER/tests/run.sh"
ll_runner() {  # <cwd> -> a stand-in `tests/run.sh` process running there, until the suite ends
  ( cd "$1" && exec bash "$LL_RUNNER/tests/run.sh" ) >/dev/null 2>&1 &
  printf '%s\n' "$!" >> "$WORLD_ROOT/pids"; LL_RUNNER_PID=$!
  local i=0; while [ "$i" -lt 50 ]; do
    case "$(ps -o command= -p "$LL_RUNNER_PID" 2>/dev/null)" in *tests/run.sh*) return 0 ;; esac
    i=$((i + 1)); sleep 0.1; done; return 1
}
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

finish
