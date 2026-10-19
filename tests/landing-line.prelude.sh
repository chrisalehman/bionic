# tests/landing-line.prelude.sh — THE HALF OF THE LANDING-LINE SUITE EVERY PART SHARES (wave-39 T35; D1, D13, REQ-3 AC-3.3).
#
# Sourced by tests/landing-line-1.test.sh and tests/landing-line-2.test.sh, after resolve-roots.sh and assert.sh. It is
# not a suite: the runner launches `*.test.sh` only. It sits beside the parts rather than under tests/lib/ so the reads
# index follows it from each part's `source` line, one hop, and an edit to it is answered with both parts.
#
# WHY TWO PARTS. One landing-line.test.sh promised 650 to 823 s on the gate, past the suite bar (lib/line.sh
# LINE_SUITE_BAR, ten minutes of promise; D1), so no writer's `ready --within` could hold it. It is cut at a section
# boundary into two suites of equal cost, every section kept whole and in its order: part 1 runs §EVENTS through §OWED,
# part 2 §INPUTS through §LAND-RC-HAND. The cut is by the old suite's own section seconds (374 against 373).
# §OWED stays with part 1 because it reads what §ROW's ready run printed (LL_OUT_W1, KW, RW).
#
# WHAT IT HOLDS. The model world, the pins, the helpers every section uses, and each helper or constant a section of
# part 1 defined that a section of part 2 calls (marked below with the section it came from, and left behind as a
# one-line pointer there). `ll_carrier_env` is the one piece of state: the carrier's environment, set where the
# carrier section begins in part 1 and at the top of part 2, so each section sees the world it always saw.
#
# WHAT IT NEVER HOLDS. A fixture: a repository or a run output one section builds and a later one reads is not a
# helper, so those sections share a part instead.
#
# THE SUITE (the old file's own header, whole):
# The landing line (wave-28 T3, T4; REQ-1 AC-1.1 to AC-1.3, AC-1.5 to
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
# The proof fact (wave-39 T1; D5, ADR-061): a verdict carries reads=, its suite's read key at the commit, and
# the reuse test matches on it, never on the commit: §REUSE.
# SECTIONS: §EVENTS, §FOLD, §TREES (the pieces); §SAME, §PAIR, §BUSY, §MOVED, §GIT, §GUARD (the
# criteria). The carrier (wave-28 T4; AC-1.1, AC-1.2, AC-1.5 to AC-1.7, AC-3.1, AC-14.1 ready half):
# §READY, §PROOF, §RED, §AHEAD-RED, §SIDE, §ALONE, §WITHIN, §GUARD (ready half); the anchor check at every landing (wave-35 T3): §ANCHORS. The drain (wave-37 T1; D3): §DRAIN, §GRAMMAR; the drain asks the gate (wave-38 T6; D21, D22): §ADMITTED, §ASK, §STALL; the oldest landing keeps its place (wave-38 T30; D22): §GAP, §ORDER; every WAITING says why (wave-38 T31; D21, D22): §WHY; a suite the row removed is not owed (wave-39 T6): §ABSENT; a suite whose narrowed reads miss the diff is skipped on the head's green, and planted reds inside and outside a narrowed read land RED (wave-39 T4): §SKIP, §PLANT; a line re-ordered under an entry keeps its verdicts across both rebuilds (wave-39 T2): §REORDER; land --by-hand meets the declared release check in line_publish, pinned by a mutant (wave-39 T13): §LAND-RC-HAND. Mutants run in the publisher's own process (`LL_MUTANT`, a sed over `declare -f
# line_publish`), never on the tracked file, and stay as permanent guards that the rows can fail.

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
. "$(dirname "$0")/lib/wait.sh"

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

# ---------------------------------------------------------------------------- hoisted from part 1 (wave-39 T35)
# §BUSY: the stand-in runner
LL_RUNNER="$WORLD_ROOT/runner"; mkdir -p "$LL_RUNNER/tests"
printf '#!/bin/bash\nwhile :; do sleep 1; done\n' > "$LL_RUNNER/tests/run.sh"
ll_runner() {  # <cwd> -> a stand-in `tests/run.sh` process running there, until the suite ends
  ( cd "$1" && exec bash "$LL_RUNNER/tests/run.sh" ) >/dev/null 2>&1 &
  printf '%s\n' "$!" >> "$WORLD_ROOT/pids"; LL_RUNNER_PID=$!
  local i=0; while [ "$i" -lt 50 ]; do
    case "$(ps -o command= -p "$LL_RUNNER_PID" 2>/dev/null)" in *tests/run.sh*) return 0 ;; esac
    i=$((i + 1)); sleep 0.1; done; return 1
}

# §GUARD (the carrier, wave-28 T4): the carrier's own helpers and its ready driver
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
# sed over the function LL_MUTANT_FN. A function line.sh loads on first use (anchors.sh's reads_hashes) is loaded
# first, so the mutant replaces it and line.sh finds it declared.
. "$1/worktree.sh" && . "$1/session.sh" && . "$1/line.sh" || exit 99
if [ -n "${LL_MUTANT:-}" ]; then
  declare -F "$LL_MUTANT_FN" >/dev/null 2>&1 || . "$1/anchors.sh" || exit 99
  eval "$(declare -f "$LL_MUTANT_FN" | sed "$LL_MUTANT")"
fi
tree="$(git rev-parse --show-toplevel)"
line_ready "$tree" "$(worktree_root "$tree")" "$(session_id)" "${2:-}" "again"
RD
ll_drive() {  # <root> <row> <out file> [within] — the driver, in the background; rc in <out>.rc. LL_LIB names another library copy
  ( cd "$1/.worktrees/$2" && bash "$LL_RD" "${LL_LIB:-$REPO/payload/scripts/lib}" "${4:-}" > "$3" 2>&1; echo $? > "$3.rc" ) &
}
ll_lines() { if [ -f "$1" ]; then awk 'END { print NR }' "$1"; else echo 0; fi; }   # <file>
ll_wait_lines() {  # <file> <n> [tenths] -> 0 once the file has at least <n> lines
  local i=0
  while [ "$i" -lt "${3:-300}" ]; do [ "$(ll_lines "$1")" -ge "$2" ] && return 0; i=$((i + 1)); sleep 0.1; done
  return 1
}
ll_field() { printf '%s\n' "$1" | tr '|' '\n' | sed -n "s/^$2=//p" | head -1; }   # <event line> <key>

# §AHEAD-RED: the candidate, lease and landing readers
ll_nth_cand() { ll_field "$(ll_ev "$1" candidate | awk -F'|' -v r="row=$2" '$3 == r' | sed -n "${3:-1}p")" commit; }   # <root> <row> [n | $]
ll_has_cand() { [ "$(ll_ev "$1" candidate | awk -F'|' -v r="row=$2" '$3 == r { n++ } END { print n + 0 }')" -ge "${3:-1}" ]; }   # <root> <row> [n]
ll_wait_cand() { wait_ticks 300 0.1 ll_has_cand "$@"; }   # <root> <row> [n] -> 0 once <row> has at least <n> candidates (30 s at most)
ll_has_lines() { [ "$(ll_lines "$1")" -ge "$2" ]; }   # <file> <n>
ll_width_ask() { ( . "$REPO/payload/scripts/lib/gate.sh" 2>/dev/null && gate_width_ask "$1" 2>/dev/null ); }   # <landing key> -> the gate's answer
ll_lease() { printf '%s/leases/%s.lease' "$BIONIC_GATE_DIR" "$(printf '%s' "$1" | tr / %)"; }   # <landing key> -> its lease file (wave-38 T30)
ll_lease_field() { sed -n "s/^$2=//p" "$(ll_lease "$1")" 2>/dev/null | tail -n 1; }   # <landing key> <field>
ll_lease_carried() { local c; c="$(ll_lease_field "$1" carrier)"; [ -n "$c" ] && [ "$c" != - ]; }   # <landing key> -> 0 while a carrier holds it
ll_lease_has() { if [ -e "$(ll_lease "$1")" ]; then echo yes; else echo no; fi; }   # <landing key>
ll_lease_gate() { ( . "$REPO/payload/scripts/lib/gate.sh" 2>/dev/null && "$@" >/dev/null 2>&1; printf '%s' "$?" ); }   # <gate verb> <args> -> its rc
ll_open_landing() {  # -> the landing= key of the first open landing request, admitted and not ended
  local f
  for f in "$BIONIC_GATE_DIR"/requests/*; do
    grep -q '^admitted=' "$f" && ! grep -q '^ended=' "$f" && grep -q '^kind=landing$' "$f" && sed -n 's/^landing=//p' "$f"
  done | head -1
}

# §WITHIN: the gate's request reader
# THE VERDICT CARRIES ITS PROMISE AND ITS ACTUAL (wave-39 T8; D11, AC-4.2): promised= is the seconds the gate
# promised the run at its admission (its request's promise=), actual= the gate's own measure, ended less admitted.
ll_req_last() {  # <suite> <field> -> that field on the newest landing request for the suite, `ended-admitted` for `actual`
  local f="" i
  for i in $(ls "$BIONIC_GATE_DIR/requests" 2>/dev/null | grep -E '^[0-9]+$' | sort -n); do
    grep -q "^key=$1\$" "$BIONIC_GATE_DIR/requests/$i" && f="$BIONIC_GATE_DIR/requests/$i"
  done
  [ -n "$f" ] || return 0
  case "$2" in
    actual) awk -F= '$1 == "admitted" { a = $2 } $1 == "ended" { e = $2 } END { if (a != "" && e != "") print e - a }' "$f" ;;
    promise) sed -n 's/^promise=//p' "$f" | tail -n 1 | awk -F: '{ print $NF }' ;;
  esac
}

# §NOVERDICT/§STALLED (wave-28 T5): the verdict reader and the background killer
ll_results() {  # <root> <row> <commit> -> the results of the verdicts on <commit>, in record order
  ll_ev "$1" verdict | awk -F'|' -v r="row=$2" -v c="commit=$3" '$3 == r && $4 == c' \
    | sed 's/.*|result=\([^|]*\)|.*/\1/' | tr '\n' ' ' | sed 's/ $//'
}
ll_last_cand() { ll_field "$(ll_ev "$1" candidate | awk -F'|' -v r="row=$2" '$3 == r' | tail -1)" commit; }   # <root> <row>
ll_kill_bg() {  # <pid> — a background drive and every process under it
  _line_kill_tree "$1" 2>/dev/null; kill "$1" 2>/dev/null; wait "$1" 2>/dev/null
}

ll_carrier_env() {  # the carrier's environment, as the carrier section of part 1 sets it (wave-28 T4); the lines are that section's own
  . "${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/roster.sh"
  . "$(dirname "$0")/lib/roster-row.sh"
  export CLAUDE_CONFIG_DIR="$WORLD_ROOT/home"
  mkdir -p "$CLAUDE_CONFIG_DIR/bionic"; printf '80\n' > "$CLAUDE_CONFIG_DIR/bionic/share"
  export CLAUDE_CODE_SESSION_ID="$WORLD_SID" BIONIC_GATE_POLL=0.1 BIONIC_LINE_POLL=0.2
  world_machine 8 8192 40 0.5
  world_clock 1000
  export LL_SIG="$WORLD_ROOT/sig"; mkdir -p "$LL_SIG"
}
