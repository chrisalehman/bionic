#!/bin/bash
# tests/landing-line.test.sh — the landing line (wave-28 T3, T4; REQ-1 AC-1.1 to AC-1.3, AC-1.5 to
# AC-1.7, REQ-3 AC-3.1, AC-3.6, AC-3.8, AC-3.9, REQ-5 AC-5.3, REQ-14 AC-14.1; spec D1 to D6, D9, D31).
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
# criteria). The carrier (wave-28 T4; AC-1.1, AC-1.2, AC-1.5 to AC-1.7, AC-3.1, AC-14.1 ready half):
# §READY, §PROOF, §RED, §AHEAD-RED, §SIDE, §ALONE, §WITHIN, §GUARD (ready half). Mutants run in the publisher's own process (`LL_MUTANT`, a sed over `declare -f
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
. "${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/roster.sh"
. "$(dirname "$0")/lib/roster-row.sh"
export CLAUDE_CONFIG_DIR="$WORLD_ROOT/home"
mkdir -p "$CLAUDE_CONFIG_DIR/bionic"; printf '80\n' > "$CLAUDE_CONFIG_DIR/bionic/share"
export CLAUDE_CODE_SESSION_ID="$WORLD_SID" BIONIC_GATE_POLL=0.1 BIONIC_LINE_POLL=0.2
world_machine 8 8192 40 0.5
world_clock 1000
export LL_SIG="$WORLD_ROOT/sig"; mkdir -p "$LL_SIG"

ll_launch() {  # <root> <row> <lands_on> [key=value...] — the row's launch line on the session's roster
  local r="$1" t="$2" l="$3"
  shift 3
  printf '%s|row=%s|lands_on=%s\n' \
    "$(roster_row_fixture status=intended session="$WORLD_SID" name="wx-$t" agent_id="b00$t" plan="$(ll_plan "$r")" "$@")" \
    "$t" "$l" >> "$r/.bionic/tmp/roster-$WORLD_SID.state"
}
ll_rworld() {  # -> a world whose rows T1 and T2 land on a.test.sh and b.test.sh
  local r
  r="$(ll_world)" || return 1
  ll_launch "$r" T1 a.test.sh; ll_launch "$r" T2 b.test.sh
  printf '%s' "$r"
}
ll_commit_suite() {  # <root> <row> <suite name> <body> — the row commits tests/<suite>.test.sh with <body>
  local t="$1/.worktrees/$2"
  printf '#!/bin/bash\n%s\n' "$4" > "$t/tests/$3.test.sh"
  git -C "$t" add "tests/$3.test.sh" && git -C "$t" commit -qm "$2: $3 as planted"
}
ll_redsuite() {  # <root> <row> <suite> — the row's commit turns <suite> red (world_suite, from inside the tree)
  ( cd "$1/.worktrees/$2" && world_suite "$3" red >/dev/null ) \
    && git -C "$1/.worktrees/$2" commit -qam "$2: $3 red"
}
# A suite that writes its start, waits for <go> (30 s at most), then ends <green|red>.
ll_block_body() {  # <tag> <name> <green|red>
  local end
  if [ "$3" = red ]; then end="echo 'FAIL: $1 red'; echo; echo '$2.test.sh: 0/1 passed, 1 failed  sections=1 setup=0'; exit 1"
  else end="echo 'PASS: $1'; echo; echo '$2.test.sh: 1/1 passed, 0 failed  sections=1 setup=0'; exit 0"; fi
  printf 'git rev-parse HEAD >> "$LL_SIG/%s.runs"\ni=0; while [ ! -e "$LL_SIG/%s.go" ] && [ "$i" -lt 300 ]; do sleep 0.1; i=$((i + 1)); done\n%s' \
    "$1" "$1" "$end"
}
ll_verb() {  # <root> <row> [args] — the writer's one verb, logged, from its tree -> LL_OUT, LL_RC
  local r="$1" t="$2"
  shift 2
  printf 'ready\n' >> "$(world_verbs)"
  LL_OUT="$( cd "$r/.worktrees/$t" && bash "$SPAWN" ready "$@" 2>&1 )"; LL_RC=$?
}
ll_verb_bg() {  # <root> <row> <out file> [args] — the same, in the background; rc in <out>.rc
  local r="$1" t="$2" o="$3"
  shift 3
  printf 'ready\n' >> "$(world_verbs)"
  ( cd "$r/.worktrees/$t" && bash "$SPAWN" ready "$@" > "$o" 2>&1; echo $? > "$o.rc" ) &
}
LL_RD="$WORLD_ROOT/ready-driver.sh"
cat > "$LL_RD" <<'RD'
#!/bin/bash
# <lib dir> [within]: `ready` as spawn-worktree.sh calls it, in a process of its own; LL_MUTANT is a
# sed over the function LL_MUTANT_FN.
. "$1/worktree.sh" && . "$1/session.sh" && . "$1/line.sh" || exit 99
if [ -n "${LL_MUTANT:-}" ]; then eval "$(declare -f "$LL_MUTANT_FN" | sed "$LL_MUTANT")"; fi
tree="$(git rev-parse --show-toplevel)"
line_ready "$tree" "$(worktree_root "$tree")" "$(session_id)" "${2:-}" "again"
RD
ll_drive() {  # <root> <row> <out file> [within] — the driver, in the background; rc in <out>.rc
  ( cd "$1/.worktrees/$2" && bash "$LL_RD" "$REPO/payload/scripts/lib" "${4:-}" > "$3" 2>&1; echo $? > "$3.rc" ) &
}
ll_lines() { if [ -f "$1" ]; then awk 'END { print NR }' "$1"; else echo 0; fi; }   # <file>
ll_wait_lines() {  # <file> <n> [tenths] -> 0 once the file has at least <n> lines
  local i=0
  while [ "$i" -lt "${3:-300}" ]; do [ "$(ll_lines "$1")" -ge "$2" ] && return 0; i=$((i + 1)); sleep 0.1; done
  return 1
}
ll_field() { printf '%s\n' "$1" | tr '|' '\n' | sed -n "s/^$2=//p" | head -1; }   # <event line> <key>

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
expect_regex "(r2) the entry: the ready event, with the row, the roster name, the suites, the debt, the carrier and its time" \
  "^line/v1\\|ev=ready\\|row=T1\\|name=wx-T1\\|commit=${T1R}\\|branch=wt/T1\\|tree=${RR}/.worktrees/T1\\|suites=a.test.sh\\|debt=-\\|carrier=[0-9]+:[^|]+\\|at=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$" \
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
ll_launch "$RR3" T1 none
ll_verb "$RR3" T1
expect_eq "(r7) lands_on=none: the candidate publishes with no run" "0 none 0" \
  "$LL_RC $(ll_field "$(ll_ev "$RR3" ready)" suites) $(ll_ev "$RR3" verdict | awk 'END { print NR }')"

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
# records each run's head and waits. T2 is proved ahead, on T1's candidate; T1 turns red; T2's run is
# stopped (discarded), rebuilt on the accepted head, proved again and published without T1.
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
expect_true "(a0-pre) T2's first run started" ll_wait_lines "$LL_SIG/a-T2.runs" 1
KA1="$(ll_ev "$RA" candidate | awk -F'|' '$3 == "row=T1"' | head -1)"; KA1="$(ll_field "$KA1" commit)"
expect_eq "(a0) T2's first run is on a candidate built on T1's" "$KA1" "$(git -C "$RA" rev-parse "$(head -1 "$LL_SIG/a-T2.runs")^1")"
touch "$LL_SIG/a-T1.go"
ll_wait_file "$WORLD_ROOT/a-T1.out.rc" 300
expect_eq "(a1) T1 is red: exit 1" "1" "$(cat "$WORLD_ROOT/a-T1.out.rc" 2>/dev/null)"
expect_true "(a2) T2 is rebuilt and proved again while its first run never ended" ll_wait_lines "$LL_SIG/a-T2.runs" 2 300
expect_regex "(a2) …its first run discarded" \
  "\\|row=T2\\|commit=$(head -1 "$LL_SIG/a-T2.runs")\\|suite=b.test.sh\\|result=discarded\\|" "$(ll_ev "$RA" verdict)"
expect_eq "(a2) …the second candidate built on the accepted head" "$HA" "$(git -C "$RA" rev-parse "$(sed -n 2p "$LL_SIG/a-T2.runs")^1")"
touch "$LL_SIG/a-T2.go"
ll_wait_file "$WORLD_ROOT/a-T2.out.rc" 300
expect_eq "(a3) T2 publishes: exit 0" "0" "$(cat "$WORLD_ROOT/a-T2.out.rc" 2>/dev/null)"
expect_eq "(a3) …the branch is T2's second candidate" "$(sed -n 2p "$LL_SIG/a-T2.runs")" "$(ll_head "$RA")"
expect_false "(a3) …which does not contain T1's commit" git -C "$RA" merge-base --is-ancestor "$T1A" wave/x
expect_regex "(a3) T1 stays returned, red" "^line/v1\\|ev=returned\\|row=T1\\|why=red\\|" "$(ll_ev "$RA" returned)"
expect_eq "(a3) …and only T2 is published" "T2" "$(ll_ev "$RA" published | sed 's/.*|row=\([^|]*\)|.*/\1/' | tr '\n' ' ' | sed 's/ $//')"
# MUTANT: the discard removed. T2's first run is never stopped when its base is replaced: no second
# run starts while the first waits, and no `discarded` verdict is appended.
RA2="$(ll_ahead_world m)"
ll_verb_bg "$RA2" T1 "$WORLD_ROOT/m-T1.out"
ll_wait_lines "$LL_SIG/m-T1.runs" 1
LL_MUTANT='s/_line_replaced "\$2" "\$1" "\$3" "\$5"/false/' LL_MUTANT_FN=_line_prove ll_drive "$RA2" T2 "$WORLD_ROOT/m-T2.out"
expect_true "(a4m-pre) the mutant ran: T2's first run started" ll_wait_lines "$LL_SIG/m-T2.runs" 1
touch "$LL_SIG/m-T1.go"; ll_wait_file "$WORLD_ROOT/m-T1.out.rc" 300
sleep 3
expect_eq "(a4m) MUTANT discard removed: no second run while the first waits (the rows can fail)" "1" "$(ll_lines "$LL_SIG/m-T2.runs")"
expect_eq "(a4m) …and no discarded verdict" "" "$(ll_ev "$RA2" verdict | grep 'result=discarded')"
touch "$LL_SIG/m-T2.go"; ll_wait_file "$WORLD_ROOT/m-T2.out.rc" 300

# ---------------------------------------------------------------------------
section "§SIDE: independent proofs run side by side (AC-1.7)"
#
# Room planted for both (share 80, 40% used, each promising 5% and half a core): T1's and T2's runs
# are both admitted, and both start, before either ends.
RW="$(ll_rworld)"
ll_commit_suite "$RW" T1 a "$(ll_block_body s-T1 a green)"
ll_commit_suite "$RW" T2 b "$(ll_block_body s-T2 b green)"
ll_verb_bg "$RW" T1 "$WORLD_ROOT/s-T1.out"
ll_wait_lines "$LL_SIG/s-T1.runs" 1
ll_verb_bg "$RW" T2 "$WORLD_ROOT/s-T2.out"
expect_true "(w1) T2's run starts while T1's has not ended" ll_wait_lines "$LL_SIG/s-T2.runs" 1
expect_eq "(w1) …both admitted by the gate as landings, neither ended" "a.test.sh b.test.sh" \
  "$(for f in "$BIONIC_GATE_DIR"/requests/*; do
       grep -q '^admitted=' "$f" && ! grep -q '^ended=' "$f" && grep -q '^kind=landing$' "$f" && sed -n 's/^key=//p' "$f"
     done | sort | tr '\n' ' ' | sed 's/ $//')"
expect_eq "(w1) …T2's on T1's candidate" "$(ll_field "$(ll_ev "$RW" candidate | head -1)" commit)" \
  "$(git -C "$RW" rev-parse "$(head -1 "$LL_SIG/s-T2.runs")^1")"
touch "$LL_SIG/s-T1.go" "$LL_SIG/s-T2.go"
ll_wait_file "$WORLD_ROOT/s-T1.out.rc" 300; ll_wait_file "$WORLD_ROOT/s-T2.out.rc" 300
expect_eq "(w2) both publish" "0 0" "$(cat "$WORLD_ROOT/s-T1.out.rc" 2>/dev/null) $(cat "$WORLD_ROOT/s-T2.out.rc" 2>/dev/null)"
expect_eq "(w2) …in order, T2's proof kept: one run each" "T1 T2 1 1" \
  "$(ll_ev "$RW" published | sed 's/.*|row=\([^|]*\)|.*/\1/' | tr '\n' ' ')$(ll_lines "$LL_SIG/s-T1.runs") $(ll_lines "$LL_SIG/s-T2.runs")"

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
world_cost c.test.sh 5 0.5 600
RN="$(ll_world)"; ll_launch "$RN" T1 c
( cd "$RN" && world_suite c green >/dev/null ) && git -C "$RN" add tests/c.test.sh && git -C "$RN" commit -qm "suite c"
REQN="$(ls "$BIONIC_GATE_DIR/requests" 2>/dev/null | wc -l | tr -d ' ')"
ll_verb "$RN" T1 --within 60
expect_eq "(n1) a suite promising 600 s with 60 s left: exit 75" "75" "$LL_RC"
expect_eq "(n1) …printing WAITING and the same command" "WAITING T1 — run again: bash ${SPAWN} ready --within 60" "$LL_OUT"
expect_eq "(n1) …nothing run: no verdict, no log, no gate request" "0 0 $REQN" \
  "$(ll_ev "$RN" verdict | awk 'END { print NR }') $(ls "$RN/.bionic/docs/record/wave-x/line" 2>/dev/null | wc -l | tr -d ' ') $(ls "$BIONIC_GATE_DIR/requests" | wc -l | tr -d ' ')"
expect_eq "(n1) …the entry kept, its carrier gone" "T1 no" "$(line_state "$(ll_plan "$RN")" | cut -f1,4 | tr '\t' ' ')"
ll_verb "$RN" T1 --within 900
expect_eq "(n2) with the time, the same command lands it" "0" "$LL_RC"
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
ll_results() {  # <root> <row> <commit> -> the results of the verdicts on <commit>, in record order
  ll_ev "$1" verdict | awk -F'|' -v r="row=$2" -v c="commit=$3" '$3 == r && $4 == c' \
    | sed 's/.*|result=\([^|]*\)|.*/\1/' | tr '\n' ' ' | sed 's/ $//'
}
ll_last_cand() { ll_field "$(ll_ev "$1" candidate | awk -F'|' -v r="row=$2" '$3 == r' | tail -1)" commit; }   # <root> <row>
ll_kill_bg() {  # <pid> — a background drive and every process under it
  _line_kill_tree "$1" 2>/dev/null; kill "$1" 2>/dev/null; wait "$1" 2>/dev/null
}

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
expect_regex "(s2) …one standing event for that head, its failing lines and the head's log" \
  "^line/v1\\|ev=standing\\|head=${HS}\\|suite=a.test.sh\\|lines=1\\|log=${LSH}\\|at=[0-9T:-]+Z$" "$(ll_ev "$RS" standing)"
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
section "§INPUTS: the poll and --within read as numbers (read-structure-p12 #7, read-adversarial-p12 #4)"
expect_eq "(i1) BIONIC_LINE_POLL that is no number falls back to 1 s; a decimal one is kept" "1 0.2" \
  "$(BIONIC_LINE_POLL=abc bash -c '. "$1" && printf %s "$LINE_POLL"' _ "$LINE") $(BIONIC_LINE_POLL=0.2 bash -c '. "$1" && printf %s "$LINE_POLL"' _ "$LINE")"
RI="$(ll_rworld)"
ll_verb "$RI" T1 --within 08
expect_eq "(i2) --within 08 is eight seconds, not an octal error: the 5 s suite runs and lands" "0" "$LL_RC"

finish
