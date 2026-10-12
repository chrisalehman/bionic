#!/bin/bash
# tests/gate.test.sh — payload/scripts/lib/gate.sh: one gate admits every heavy command on the
# machine's present reading, one core a command, keeping only durations (wave-33 T1; Δ10) (epic-23
# wave-28-finished-work-lands, T2; REQ-2, REQ-4, REQ-7; spec D10, D11, D12; ADR-046).
#
# WHAT IS UNDER TEST. One section per eval the spec names:
#
#   §SHARE     AC-2.1  asks from two fixture projects read one share file; a project's own
#                      config or plan line changes neither; absent or unreadable is 92
#   §HARD      AC-2.2  memory planted over the share is not admitted; a busy processor with
#                      nothing admitted is; an unknown command or an unknown reading waits for
#                      an idle gate. Mutation: the share's ceiling lifted admits at 85%
#   §NOCONST   AC-2.3  the same asks on a 4-core 4 GB and a 32-core 64 GB machine at equal
#                      used percentages decide alike
#   §TWO       AC-2.4  two asks at one instant with room for one: one admitted, one waits on an
#                      unmoved reading; a dead holder's lock is taken over
#   §NUMBER    AC-2.6  an ask whose time runs out exits 75 before --within, having run nothing;
#                      its next ask resumes its number and is served before a later one
#   §FIRST     AC-2.7  a writer's number waits, a landing's arrives, and the landing is admitted
#                      first. Mutation: landing-before-work removed admits the writer
#   §ANCESTOR  AC-2.13 an admission passed down is believed only from an ancestor holder; a
#                      typed one asks anyway; BIONIC_SLOT_HELD=1 is ignored. Mutation: the
#                      ancestor test removed believes the stranger
#   §ANCESTRY  AC-1.4  (wave-32 T1; D5) a child of an admitted holder, BIONIC_GATE_ADMIT unset
#                      or naming an id the store cannot believe, is admitted as the holder's and
#                      files nothing; a process that is not a descendant files its own; an
#                      ended admission is believed by nobody
#   §WAITED    AC-4.2  a request holds its asked and admitted times, and the wait is their gap
#   §KILLED    AC-4.3  a real child admitted and then killed with signal 9 is counted once;
#                      it holds no peak and writes no duration
#   §COST      D12     (wave-33 T1; Δ10: durations only) gate_end's duration line,
#                      <seconds>:<epoch>, three kept; the promise is one core, no memory and the
#                      key's longest kept duration; an unknown command's is one core and no
#                      seconds; an overlapped run records its own seconds; a run's processor
#                      work and memory are not recorded; an overlong run held until it ages out
#                      of the three lines; an unknown request line ignored. Mutation: four
#                      lines kept
#   §ZERO-SECONDS D5   (wave-32 T1) a run admitted and ended in one second writes its end and
#                      rc and no duration line; one ended 2 s later writes its line
#   §CORES-OVER Δ10    (wave-33 T1, retiring wave-32 T19's core-count test) a run whose
#                      children's processor time is impossible writes its seconds all the same,
#                      and no cores
#   §WHOLE-COST D1, D5, Δ10 a whole request is promised its width, gate_width; its gate_end
#                      records its seconds unmarked; a never-seen key is promised one core and
#                      an owed writer charged one, before and after a whole run; its next ask
#                      waits while another is held and is admitted once nothing is
#   §ONE-CORE  AC-8.1  (wave-33 T1) a command is promised one core whatever is on record (the
#                      research store's 4.4- and 3.94-core lines); two writers admitted on it;
#                      an empty store promises one core; a whole run its width
#   §SIDE-BY-SIDE AC-8.2 two writers' single suites on an idle 8-core probe at share 92 are
#                      admitted side by side, on a fresh store and on the probe's stray line
#   §DURATIONS AC-8.6  durations keyed by project and command: a run in project A writes A's
#                      file only, B's time limit (line.sh `_line_time_for`) is unchanged; a
#                      worktree is its repository's project; an unkeyed 1.15.0 file is read for
#                      its seconds only and never changed
#   §SHARE-ROOM AC-9.1 share × cores ÷ 100 at one site and the one core at one site: a mutant
#                      at each moves every reader. Mutations: the room doubled; the core set to 3
#   §ROOM      AC-2.5  gate_room (T13, D14): a five-minute load over the share, a waiting
#                      request, promised work not yet showing and memory over the share each
#                      give no room; a quiet machine gives room; two asks on one reading give
#                      room once; gate_state prints the loads where clears= stood. Mutations:
#                      the waiting clause, the owed count, the five-minute reading
#   §OPEN      T71     one rule says which requests are open (no ended= line, holder alive): the
#                      scan, gate_list, gate_asked and the prune read it; a holder-gone request is
#                      not showing and is pruned after BIONIC_GATE_KEEP; gate_asked answers over
#                      20,000 request files, takes no lock and survives a file removed mid-read;
#                      2,000 expired requests are pruned by a batch, under a second; ended=008 and
#                      BIONIC_GATE_KEEP=abc abort nothing. Mutations: the rule split back, the exec
#                      list back, an rm per file back, the decimal read removed
#   §REAPED    T47     a request killed earlier is written ended (rc 137) by the next locked act;
#                      runs after it and beside it record their own seconds. Mutation: the
#                      killed-write removed leaves the killed request never ended
#   §ALONE     T47, Δ10 a request promises no memory: a small ask is admitted beside a big run
#                      while the reading is at most the share; a reading over it still refuses
#   §OWN       T47     a second ask by one who for one key, the first still polling, gets a
#                      number of its own. Mutation: the liveness test on reuse removed
#   §CLEARED   T47     a request returned 75 has its holder cleared, so a live caller that no
#                      longer polls keeps no head. Mutation: the clearing removed
#   §MACHINES  AC-7.3  the admission rows run under three planted machines and decide alike, but
#                      for a 2-core machine whose share holds one command of one core (Δ10)
#   §WRAP      AC-2.6, AC-2.13 (T12) the wrapper, booked.sh, asks the gate: the command's own code
#                      on a run; 75 and nothing run when the wait runs out, under --max-wait or
#                      --kill-after; its next call resumes the number and runs first; a nested
#                      shim is believed; a typed admission and BIONIC_SLOT_HELD=1 ask anyway; 2
#                      on usage; a stamp on every end but usage; the runner takes no number; a
#                      run is sampled while it runs. Mutations: the wrapper believing a typed
#                      admission without asking; the wrapper exiting 0 on a timeout
#   §BUDGET-AT-ASK AC-6.2 (wave-33 T3; D7) an agent budgeted for a.test.sh, in a real checkout of
#                      the runner: a whole run through a symlinked script, a variable and a symlink
#                      at argv[0], and b.test.sh through a script's door, are refused at the ask,
#                      75, the budget's own line, nothing run; a.test.sh through a script runs; the
#                      main thread, a row with no budget, a believed admission and a landing are
#                      not judged; a declared Re-executes run admits the suite it names. Mutation:
#                      the ask's budget call removed admits the off-budget ask
#   §CASE      AC-6.3  (wave-33 T3) on a case-blind filesystem (planted both ways) A.TEST.SH is
#                      a.test.sh and TESTS/RUN.SH the whole run; case-exact, A.TEST.SH is another
#                      file; `bash TESTS/RUN.SH` from a script, where this filesystem folds, is
#                      refused at the ask
#
# HERMETIC. Everything runs in the model world (tests/lib/world.sh): a planted machine, a
# planted clock moved by world_tick, a gate store and a CLAUDE_CONFIG_DIR under the world's
# directory, which is removed on exit. Askers are real processes (bash children), because a
# holder's liveness is the gate's own rule: a background asker holds its admission until the
# row touches its `.go` file. No sleep is longer than a poll (0.05 s) except the bounded waits
# for a file a child writes.
#
# ANTI-VACUITY. A missing or unparseable gate.sh fails every row by name (an asker that
# cannot source it exits 127), not one row. Every "waits" row stands beside a positive on the
# same request (its file exists, its asked line is read). Three mutation arms run on a copy
# of payload/scripts/lib under the world's directory, each anchored first and each proved
# to run (its own positive row) before its claim is read; §COST adds one more, and §REAPED,
# §OWN and §CLEARED one each (T47). §OPEN adds four (T71); §SHARE-ROOM two (wave-33 T1);
# §BUDGET-AT-ASK one (wave-33 T3).
#
# FIXTURE FIDELITY (declared, per .claude/rules/test-harness.md, "Fixture fidelity"):
#   * The machine, the clock and the duration records are SYNTHESIZED by design (the world's
#     pins): the claims are about what the gate decides on a reading, and a real reading would
#     make them depend on what this machine is doing. The readers themselves are
#     tests/resources.test.sh's to assert.
#   * Holders are REAL processes: liveness is the pid-and-start rule run on them, and the
#     killed row kills one with signal 9. Nothing fakes a holder's life or death.
#   * The share file and the store are real files under a planted CLAUDE_CONFIG_DIR.
#
# Usage: bash tests/gate.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"
. "$(dirname "$0")/lib/roster-row.sh"
. "$(dirname "$0")/lib/wait.sh"   # wait_for <seconds> <cmd>…, the bounded poll

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
GATE="$REPO_ROOT/payload/scripts/lib/gate.sh"

# This suite may itself run inside a booked or admitted command; the rows measure a caller
# that holds nothing.
unset BIONIC_SLOT_HELD BIONIC_SLOT_PLACE BIONIC_GATE_ADMIT BIONIC_GATE_AGENT BIONIC_NOW_EPOCH \
  BIONIC_GATE_POLL BIONIC_PROBE_PROC GIT_DIR GIT_WORK_TREE

BG=""
kill_tree() {  # <pid> — the pid and every descendant, children first
  local c
  for c in $(pgrep -P "$1" 2>/dev/null); do kill_tree "$c"; done
  kill -KILL "$1" 2>/dev/null
}
cleanup() {
  local p
  for p in $BG; do kill_tree "$p"; done
}
trap cleanup EXIT
. "$(dirname "$0")/lib/world.sh"

export CLAUDE_CONFIG_DIR="$WORLD_ROOT/home"
export CLAUDE_CODE_SESSION_ID="$WORLD_SID"
export BIONIC_GATE_POLL=0.05
export GATE_LIB="$GATE"
mkdir -p "$CLAUDE_CONFIG_DIR/bionic"

if [ -r "$GATE" ] && bash -n "$GATE" 2>/dev/null; then
  ok "subject present and parses: payload/scripts/lib/gate.sh"
else
  no "subject present and parses: payload/scripts/lib/gate.sh" "missing or unparseable"
fi

# ── fixture helpers ──────────────────────────────────────────────────────────

# asker.sh <dir> <name> <kind> <key> <within> — one asking process. Its id and rc land in
# <dir>/<name>.id and <name>.rc (rc last, so a reader that sees rc sees the id). Env:
#   HOLD=1     once admitted, hold until <dir>/<name>.go, then gate_end <id> 0 (<name>.endrc)
#   CHILD=<n>  once admitted, run asker <n> for the same kind and key as a CHILD of this
#              process, with BIONIC_GATE_ADMIT=<id>, before holding
#   CHILD_ADMIT=<v>  the child's BIONIC_GATE_ADMIT is <v> instead of <id>; `-` leaves it unset
#   ENDFIRST=1 once admitted, gate_end <id> 0 before running CHILD (the admission is over)
#   WORK=<sh>  once admitted, run <sh> as a child before holding (processor time for `times`)
#   PLANT_CPU=<s>  the children's processor time `times` reports at gate_end is <s> seconds
#   AGENT=<a>  ask as agent <a> (the who's second half) instead of <name>, so two askers share a who
#   LIVE=1     after a 75, stay alive, polling nothing, until <dir>/<name>.go
# Its own pid is written first, to <name>.pid.
cat > "$WORLD_ROOT/asker.sh" <<'ASKER'
d="$1"; n="$2"; kind="$3"; key="$4"; within="$5"
printf '%s\n' "$$" > "$d/$n.pid"
export BIONIC_GATE_AGENT="${AGENT:-$n}"
. "$GATE_LIB" 2>/dev/null
id="$(gate_ask "$kind" "$key" --within "$within" 2>"$d/$n.err")"; rc=$?
printf '%s\n' "$id" > "$d/$n.id"
printf '%s\n' "$rc" > "$d/$n.rc.tmp" && mv "$d/$n.rc.tmp" "$d/$n.rc"
if [ "$rc" != 0 ]; then
  [ "${LIVE:-0}" = 1 ] || exit 0
  i=0
  while [ ! -f "$d/$n.go" ] && [ "$i" -lt 1200 ]; do i=$((i + 1)); sleep 0.05; done
  exit 0
fi
[ "${ENDFIRST:-0}" != 1 ] || gate_end "$id" 0
if [ -n "${CHILD:-}" ]; then
  ( kid="$CHILD"; adm="${CHILD_ADMIT-$id}"; unset CHILD CHILD_ADMIT ENDFIRST HOLD WORK
    if [ "$adm" = - ]; then unset BIONIC_GATE_ADMIT; else export BIONIC_GATE_ADMIT="$adm"; fi
    bash "$0" "$d" "$kid" "$kind" "$key" 0 )
fi
[ -z "${WORK:-}" ] || bash -c "$WORK"
[ -z "${PLANT_CPU:-}" ] || times() { printf '0m0.00s 0m0.00s\n0m%ss 0m0.00s\n' "$PLANT_CPU"; }
[ "${HOLD:-0}" = 1 ] || exit 0
i=0
while [ ! -f "$d/$n.go" ] && [ "$i" -lt 1200 ]; do i=$((i + 1)); sleep 0.05; done
gate_end "$id" 0; printf '%s\n' "$?" > "$d/$n.endrc"
ASKER

fresh() {  # <name> — a row of its own: asker directory, gate store, share 80, clock 1000
  reap
  D="$WORLD_ROOT/rows/$1"
  mkdir -p "$D"
  export BIONIC_GATE_DIR="$D/gate"
  printf '80\n' > "$CLAUDE_CONFIG_DIR/bionic/share"
  world_clock 1000
}
ask_bg() {  # <name> <kind> <key> <within> — an asker in the background (HOLD/CHILD/WORK pass)
  bash "$WORLD_ROOT/asker.sh" "$D" "$@" >/dev/null 2>&1 &
  BG="$BG $!"
}
reap() {  # the last row's askers that still poll or hold: killed, so no row feeds the next
  local p
  for p in $BG; do kill_tree "$p"; wait "$p" 2>/dev/null; done
  BG=""
}
ask_fg() {  # <name> <kind> <key> <within> — an asker in the foreground; prints its rc
  bash "$WORLD_ROOT/asker.sh" "$D" "$@"
  cat "$D/$1.rc" 2>/dev/null || echo none
}
has() { [ -e "$D/$1" ]; }
rc_of() { cat "$D/$1.rc" 2>/dev/null || echo none; }
id_of() { cat "$D/$1.id" 2>/dev/null; }
nreq() {  # how many request files the store holds
  ls "$BIONIC_GATE_DIR/requests" 2>/dev/null | grep -c '^[0-9][0-9]*$'
}
nreq_is() { [ "$(nreq)" = "$1" ]; }
field() {  # <id> <field> — the request's last <field>= line's value
  [ -n "${1:-}" ] || return 0
  sed -n "s/^$2=//p" "$BIONIC_GATE_DIR/requests/$1" 2>/dev/null | tail -n 1
}
req_of() {  # <agent name> — the id of the request that agent asked (by its who line)
  grep -l "^who=$WORLD_SID:$1\$" "$BIONIC_GATE_DIR"/requests/[0-9]* 2>/dev/null | head -n 1 | sed 's#.*/##'
}
asked_by() { [ -n "$(req_of "$1")" ]; }
release() {  # <name> — let a holding asker end, and wait until it has
  touch "$D/$1.go"
  wait_for 20 has "$1.endrc"
}
dead() { ! kill -0 "$1" 2>/dev/null; }
resumed() {  # <id> <name> — the request's holder is now that asker's process
  case "$(field "$1" holder)" in "$(cat "$D/$2.pid" 2>/dev/null):"*) return 0 ;; esac
  return 1
}
state() {  # gate_state in a child, so the suite's shell holds nothing
  ( . "$GATE_LIB" 2>/dev/null; gate_state 2>&1 )
}
glist() { ( . "$GATE_LIB" 2>/dev/null; gate_list 2>&1 ); }
# The cost file a run asked from <dir> (default: here) writes for <key> (wave-33 T1; D4, AC-8.6):
# cost/<project key>%<key>, the project key the gate's own (`_gate_project`), a `/` written `%`.
pk_here() {  # [<dir>] — the gate's project key for <dir> (default: here)
  ( . "$GATE_LIB" 2>/dev/null; _gate_project "${1:-$(pwd -P)}" 2>/dev/null )
}
costf() {  # <key> [<dir>] — the path of that cost file
  printf '%s/cost/%s%%%s\n' "$BIONIC_GATE_DIR" "$(pk_here "${2:-}")" "$(printf '%s' "$1" | tr / %)"
}

# The mutation copies: payload/scripts/lib whole, under the world (outside every checkout).
MUT="$WORLD_ROOT/mutants"
mutant() {  # <name> — a fresh copy of the libraries; prints the copy's gate.sh
  mkdir -p "$MUT/$1"
  cp -R "$REPO_ROOT/payload/scripts/lib" "$MUT/$1/lib"
  printf '%s\n' "$MUT/$1/lib/gate.sh"
}

# ── §SHARE ───────────────────────────────────────────────────────────────────
section "§SHARE — one share per machine (AC-2.1)"
fresh share
world_machine 8 8192 55 1.0
rm -f "$CLAUDE_CONFIG_DIR/bionic/share"
expect_eq "S.1 no share file: gate_share prints 92, the default" "92" "$( . "$GATE_LIB" 2>/dev/null; gate_share )"
for bad in abc 0 101 "" 1234; do
  printf '%s\n' "$bad" > "$CLAUDE_CONFIG_DIR/bionic/share"
  expect_eq "S.2 an unreadable share '$bad' is 92, the default" "92" "$( . "$GATE_LIB" 2>/dev/null; gate_share )"
done
# A share file the user (or `session-poker.sh share <n>`) wrote wins over the default.
printf '70\n' > "$CLAUDE_CONFIG_DIR/bionic/share"
expect_eq "S.2b a share file holding 70 is 70, not the default" "70" "$( . "$GATE_LIB" 2>/dev/null; gate_share )"
printf '50\n' > "$CLAUDE_CONFIG_DIR/bionic/share"
for p in A B; do
  mkdir -p "$D/proj$p/.bionic/docs/plans"
  printf 'share: 90\ngate-share: 90\n' > "$D/proj$p/.bionic/config.yaml"
  printf -- '---\nshare: 90\n---\nshare=90\n' > "$D/proj$p/.bionic/docs/plans/p.plan.md"
done
world_cost k 30
shA="$(cd "$D/projA" && . "$GATE_LIB" 2>/dev/null; gate_share)"
shB="$(cd "$D/projB" && . "$GATE_LIB" 2>/dev/null; gate_share)"
expect_eq "S.3 project A, its config and plan saying 90, reads the machine's share 50" "50" "$shA"
expect_eq "S.4 project B reads the same share" "50" "$shB"
rA="$(cd "$D/projA" && ask_fg a work k 0)"
rB="$(cd "$D/projB" && ask_fg b work k 0)"
expect_eq "S.5 at share 50, a reading of 55 is refused in project A (rc 75)" "75" "$rA"
expect_eq "S.6 and in project B (rc 75)" "75" "$rB"
expect_eq "S.7 project A's request names its tree" "$(cd "$D/projA" && pwd -P)" "$(field "$(req_of a)" tree)"
expect_eq "S.8 project B's request names its own" "$(cd "$D/projB" && pwd -P)" "$(field "$(req_of b)" tree)"
printf '80\n' > "$CLAUDE_CONFIG_DIR/bionic/share"
expect_eq "S.9 the same ask at share 80 is admitted (55 + 10 ≤ 80)" "0" "$(cd "$D/projA" && ask_fg a2 work k 0)"
expect_eq "S.10 the store defaults to \$CLAUDE_CONFIG_DIR/bionic/gate" "$CLAUDE_CONFIG_DIR/bionic/gate" \
  "$( unset BIONIC_GATE_DIR; . "$GATE_LIB" 2>/dev/null; gate_dir )"

# The verb (T10, D16): `session-poker.sh share <n>` writes the file the gate reads. The verb runs under
# the world's own CLAUDE_CONFIG_DIR and a HOME that holds nothing; the gate's asks follow what it wrote.
share_verb() {  # <args...> -> the verb's output; BIONIC_CLAUDE_HOME stays as the caller set it
  ( cd "$D" && env HOME="$WORLD_ROOT/nohome" BIONIC_PLUGINS_DIR="$WORLD_ROOT/no-plugins" \
      bash "$REPO_ROOT/hooks/session-poker.sh" share "$@" 2>&1 )
}
fresh sharev
world_machine 8 8192 55 1.0
world_cost k 30
expect_eq "S.11 the verb prints the share the gate reads (80 from fresh)" "80" "$(share_verb)"
expect_eq "S.12 share 50 exits 0 and the gate's share is 50" "0|50" \
  "$(share_verb 50 >/dev/null; echo "$?")|$( . "$GATE_LIB" 2>/dev/null; gate_share )"
expect_eq "S.13 at the set share 50, a reading of 55 is refused (rc 75)" "75" "$(ask_fg v1 work k 0)"
share_verb 80 >/dev/null
expect_eq "S.14 the verb sets it back to 80 and the same ask is admitted (rc 0)" "0" "$(ask_fg v2 work k 0)"
share_verb 101 >/dev/null; S15_RC=$?
expect_eq "S.15 a refused value exits 1 and leaves the file as it was (80)" "1|80" "$S15_RC|$(sed -n 1p "$CLAUDE_CONFIG_DIR/bionic/share")"
expect_eq "S.16 and the verb's print is the gate's (80)" "$( . "$GATE_LIB" 2>/dev/null; gate_share )" "$(share_verb)"
# BIONIC_CLAUDE_HOME moves claude_home() for other readers, not the share file (T2's choice); the verb writes where
# gate_share reads under it (read-structure-p6 #3)
BCH="$D/bch"; mkdir -p "$BCH/bionic"; printf '33\n' > "$BCH/bionic/share"
BIONIC_CLAUDE_HOME="$BCH" share_verb 45 >/dev/null
expect_eq "S.17 with BIONIC_CLAUDE_HOME set the verb's write and gate_share's read meet (45)" "45" \
  "$(env BIONIC_CLAUDE_HOME="$BCH" bash -c '. "$1" 2>/dev/null; gate_share' _ "$GATE_LIB")"
expect_eq "S.18 …and the other home's own share file was not written (33)" "33" "$(sed -n 1p "$BCH/bionic/share")"

# ── §WIDTH ───────────────────────────────────────────────────────────────────
# THE WIDTH THE SHARE ALLOWS (wave-32 T2; D1, AC-1.1). gate_width is the share's room as a
# whole number of workers: floor(share × cores ÷ 100), at least 1. It is the one formula the
# runner sizes a whole run's JOBS from, so the gate owns it beside gate_share. Driven over
# planted share files on a planted 8-core probe (BIONIC_PROBE_CORES, the knob world_machine
# sets), each read in a fresh child so nothing this shell holds feeds it.
section "§WIDTH — the width a whole run takes is the share's room, floored (wave-32 T2; D1)"
gw_of() {  # <share> <cores> — gate_width over a planted share file and core count
  printf '%s\n' "$1" > "$CLAUDE_CONFIG_DIR/bionic/share"
  env BIONIC_PROBE_CORES="$2" bash -c '. "$1" 2>/dev/null; gate_width' _ "$GATE_LIB"
}
expect_eq "WD.1 share 92 on 8 cores: 7 workers (7.36, floored)" "7" "$(gw_of 92 8)"
expect_eq "WD.2 share 100 on 8 cores: 8 workers" "8" "$(gw_of 100 8)"
expect_eq "WD.3 share 50 on 8 cores: 4 workers" "4" "$(gw_of 50 8)"
expect_eq "WD.4 share 1 on 8 cores: floored at 1, never 0" "1" "$(gw_of 1 8)"
expect_eq "WD.5 the cores are read, not assumed: share 92 on 64 cores is 58" "58" "$(gw_of 92 64)"
expect_eq "WD.6 an unreadable share is the default's room: 92 on 8 cores, 7" "7" "$(gw_of bogus 8)"

# ── §HARD ────────────────────────────────────────────────────────────────────
section "§HARD — memory is the hard limit, the processor the soft one (AC-2.2)"
fresh hard
world_machine 8 8192 85 1.0
world_cost k 30
expect_eq "H.1 used 85 under a share of 80, nothing admitted: not admitted (rc 75)" "75" "$(ask_fg h1 work k 0)"
expect_eq "H.2 its request was taken (asked=1000)" "1000" "$(field "$(req_of h1)" asked)"
expect_eq "H.3 and holds no admitted line (asked|admitted)" "1000|" "$(field "$(req_of h1)" asked)|$(field "$(req_of h1)" admitted)"
fresh hard2
world_machine 8 8192 30 16
world_cost k 30
HOLD=1 ask_bg p1 work k 0
wait_for 20 has p1.rc
expect_eq "H.4 16 busy cores of 8, nothing admitted: admitted (rc 0)" "0" "$(rc_of p1)"
expect_eq "H.5 a second ask while one is admitted and the processor is over: rc 75" "75" "$(ask_fg p2 work k 0)"
release p1
fresh hard3
world_machine 8 8192 30 1.0
HOLD=1 ask_bg u1 work never-seen 0
wait_for 20 has u1.rc
expect_eq "H.6 a command with no cost file anywhere, nothing admitted: admitted" "0" "$(rc_of u1)"
expect_eq "H.7 another unknown command while that one runs is promised one core (wave-33 T1, AC-8.1) and admitted beside it: rc 0" "0" "$(ask_fg u2 work never-seen-2 0)"
release u1
fresh hard4
world_machine 8 8192 30 1.0
world_cost k 30
export BIONIC_PROBE_USED_PCT=-1
HOLD=1 ask_bg m1 work k 0
wait_for 20 has m1.rc
expect_eq "H.8 memory unreadable (-1), nothing admitted: admitted" "0" "$(rc_of m1)"
expect_eq "H.9 memory unreadable while one is admitted: rc 75" "75" "$(ask_fg m2 work k 0)"
release m1
export BIONIC_PROBE_USED_PCT=30
# Mutation arm: the share's ceiling lifted to 100. The same H.1 ask must then be admitted. The
# gate promises no memory (wave-33 T1; Δ10), so the mutant's own refusal is shown on the
# processor: 6.0 busy cores, one run held, a second ask (6.0 + 1 > 6.4).
MG="$(mutant ceiling)"
anchor "$MG" 'if (r >= 0 && !fits(u, share)) exit 1' 1
sed -i.bak 's/if (r >= 0 \&\& !fits(u, share)) exit 1/if (r >= 0 \&\& !fits(u, 100)) exit 1/' "$MG"
fresh hard-mut
world_machine 8 8192 85 6.0
world_cost k 30
GATE_LIB="$MG" HOLD=1 ask_bg hm1 work k 0; wait_for 20 has hm1.rc
expect_eq "H.10 the mutant still decides: with one held, a second ask over the processor is refused (rc 75)" "75" \
  "$(GATE_LIB="$MG" ask_fg hm0 work k 0)"
expect_eq "H.11 the mutant admits at 85% used under a share of 80 — the ceiling is the rule" "0" \
  "$(rc_of hm1)"
reap

# ── the admission rows, parameterised by machine (§NOCONST, §MACHINES) ───────
# admissions <cores> <total_mb> — four asks on one machine, every reading a share of the
# machine; sets ADM to the four rcs. (Rows that start background askers never run inside
# `$( )`: a poller started in a subshell would outlive the row unreaped.) Each command is
# promised one core and no memory (wave-33 T1; Δ10), so the readings decide: w2 asks while the
# memory reads 85%, over the share of 80; w4 while the processor reads the share's whole room.
# Expected: 0 75 0 75 (the second over memory, the fourth over the processor while two are
# admitted) on any machine whose share holds two commands (share × cores ÷ 100 ≥ 2: 3 cores
# and up at 80); on a smaller one the third is refused too, the cost of a fixed core a command.
admissions() {
  local c="$1" q f
  q="$(awk -v c="$c" 'BEGIN { printf "%g", c * 0.25 }')"
  f="$(awk -v c="$c" 'BEGIN { printf "%g", c * 0.8 }')"
  fresh "adm-$1-$2"
  world_machine "$c" "$2" 50 "$q"
  world_cost k1 60
  world_cost k2 60
  world_cost k3 60
  HOLD=1 ask_bg w1 work k1 0; wait_for 20 has w1.rc
  BIONIC_PROBE_USED_PCT=85 ask_fg w2 work k1 0 >/dev/null
  HOLD=1 ask_bg w3 work k2 0; wait_for 20 has w3.rc
  BIONIC_PROBE_BUSY_CORES="$f" ask_fg w4 work k3 0 >/dev/null
  ADM="$(rc_of w1) $(rc_of w2) $(rc_of w3) $(rc_of w4)"
  touch "$D/w1.go" "$D/w3.go"
}
# hard_rows <cores> <total_mb> — §HARD's two rules on one machine; sets HRD to two rcs (75 0)
hard_rows() {
  fresh "hardm-$1-$2"
  world_machine "$1" "$2" 85 1
  world_cost k 30
  ask_fg x1 work k 0 >/dev/null
  world_machine "$1" "$2" 30 "$(( $1 * 2 ))"
  ask_fg x2 work k 0 >/dev/null
  HRD="$(rc_of x1) $(rc_of x2)"
}

# ── §NOCONST ─────────────────────────────────────────────────────────────────
section "§NOCONST — no machine constant decides (AC-2.3)"
admissions 4 4096; small="$ADM"
admissions 32 65536; large="$ADM"
hard_rows 4 4096; hsmall="$HRD"
hard_rows 32 65536; hlarge="$HRD"
expect_eq "C.1 a 4-core 4 GB machine decides 0 75 0 75" "0 75 0 75" "$small"
expect_eq "C.2 a 32-core 64 GB machine at the same percentages decides alike" "0 75 0 75" "$large"
expect_eq "C.3 the memory rule on the small machine: 75, then 0 on a busy processor" "75 0" "$hsmall"
expect_eq "C.4 and alike on the large one" "75 0" "$hlarge"

# ── §TWO ─────────────────────────────────────────────────────────────────────
section "§TWO — several commands never start on one reading (AC-2.4)"
fresh two
# THE ROOM FOR ONE (wave-33 T1; Δ10): every command is promised one core and no memory, so the
# room is the live processor reading's: 6.0 busy cores of the 6.4 the share of 80 allows on 8.
# The first ask, nothing admitted, is admitted; a second (6.0 + 1 > 6.4) waits.
world_machine 8 8192 60 6.0
world_cost k 30
HOLD=1 ask_bg t1 work k 0
HOLD=1 ask_bg t2 work k 0
wait_for 20 has t1.rc; wait_for 20 has t2.rc
expect_eq "T.1 both asks were taken" "2" "$(nreq)"
expect_eq "T.2 exactly one of two asks at one instant is admitted" "0 75" \
  "$(printf '%s\n%s\n' "$(rc_of t1)" "$(rc_of t2)" | sort -n | tr '\n' ' ' | sed 's/ $//')"
touch "$D/t1.go" "$D/t2.go"
wait_for 20 has t1.endrc || wait_for 20 has t2.endrc
fresh two-lock
world_machine 8 8192 30 1.0
world_cost k 30
mkdir -p "$BIONIC_GATE_DIR/lock"
sh -c 'exit 0' & deadpid=$!; wait "$deadpid"
printf 'Thu Jan 1 00:00:00 1970\n' > "$BIONIC_GATE_DIR/lock/since"
printf '%s\n' "$deadpid" > "$BIONIC_GATE_DIR/lock/pid"
dead "$deadpid" || no "T.4 the planted lock's holder is dead" "pid $deadpid lives"
expect_eq "T.5 a lock left by a dead holder is taken over: the ask is decided (rc 0)" "0" "$(ask_fg l1 work k 0)"
expect_false "T.6 and the lock is given back" test -d "$BIONIC_GATE_DIR/lock"

# ── §NUMBER ──────────────────────────────────────────────────────────────────
section "§NUMBER — a wait never ends in a kill, and the number holds its turn (AC-2.6)"
fresh number
world_machine 8 8192 60 6.0
world_cost h 30
world_cost k 30
HOLD=1 ask_bg nh work h 0; wait_for 20 has nh.rc
expect_eq "N.1 the holder is admitted (nothing else admitted)" "0" "$(rc_of nh)"
HOLD=1 ask_bg na work k 3
wait_for 20 asked_by na
na_id="$(req_of na)"
expect_eq "N.2 the timed ask took a number at 1000" "1000" "$(field "$na_id" asked)"
sleep 0.3
expect_false "N.3 at 1000 of a 3-second wait it is still waiting" has na.rc
world_tick 2; sleep 0.3
expect_false "N.4 at 1002 it is still waiting" has na.rc
world_tick 1
wait_for 20 has na.rc
expect_eq "N.5 at 1003 it exits 75, not 124" "75" "$(rc_of na)"
expect_eq "N.6 nothing ran: its request holds no admitted line (asked|admitted)" "1000|" "$(field "$na_id" asked)|$(field "$na_id" admitted)"
expect_eq "N.7 its request is kept" "1000" "$(field "$na_id" asked)"
world_tick 5
HOLD=1 ask_bg nb work k 600
wait_for 20 nreq_is 3
expect_eq "N.8 a later number is taken at 1008" "1008" "$(field "$(req_of nb)" asked)"
rm -f "$D/na.rc" "$D/na.id" "$D/na.pid"
HOLD=1 ask_bg na work k 600
wait_for 20 has na.pid
wait_for 20 resumed "$na_id" na
expect_eq "N.9 the next ask by the same who for the same key resumes the same number" "3" "$(nreq)"
release nh
wait_for 20 has na.rc
expect_eq "N.10 when room appears the resumed number is admitted" "0" "$(rc_of na)"
expect_eq "N.11 it is the number first taken" "${na_id:-none}" "$(id_of na)"
expect_false "N.12 the later number is still waiting" has nb.rc
expect_eq "N.13 and holds no admitted line (asked|admitted)" "1008|" "$(field "$(req_of nb)" asked)|$(field "$(req_of nb)" admitted)"

# ── §FIRST ───────────────────────────────────────────────────────────────────
# first_rows <gate lib> <prefix> — a writer waits, a landing arrives, room appears; sets FIRST
# to the agent admitted first (w or l), or none.
first_rows() {
  fresh "first-$2"
  world_machine 8 8192 60 6.0
  world_cost h 30
  world_cost k 30
  world_cost l 30
  GATE_LIB="$1" HOLD=1 ask_bg fh work h 0; wait_for 20 has fh.rc
  GATE_LIB="$1" HOLD=1 ask_bg fw work k 600; wait_for 20 asked_by fw
  world_tick 10
  GATE_LIB="$1" HOLD=1 ask_bg fl landing l 600; wait_for 20 asked_by fl
  FIRST_STATE="$(GATE_LIB="$1" state)"
  touch "$D/fh.go"
  wait_for 20 has fw.rc || wait_for 20 has fl.rc
  sleep 0.3
  if has fl.rc && ! has fw.rc; then FIRST=l
  elif has fw.rc && ! has fl.rc; then FIRST=w
  else FIRST="none: w=$(rc_of fw) l=$(rc_of fl)"
  fi
}
section "§FIRST — a landing's run goes first (AC-2.7)"
first_rows "$GATE" real
expect_eq "F.1 the writer asked first, the landing later; the landing is admitted first" "l" "$FIRST"
expect_contains "F.2 gate_state counted both waiting, one a landing" "waiting=2 landing-waiting=1" "$FIRST_STATE"
expect_contains "F.3 gate_state counted the one admitted" "admitted=1" "$FIRST_STATE"
expect_regex "F.4 gate_state prints its one line" \
  '^share=80 used=[0-9-]+ admitted=1 waiting=2 landing-waiting=1 load=[0-9.-]+/[0-9.-]+ promised=[0-9.]+$' "$FIRST_STATE"
MF="$(mutant first)"
anchor "$MF" 'else r = ($1 == "landing" ? 1 : 2)' 1
sed -i.bak 's/else r = (\$1 == "landing" ? 1 : 2)/else r = 2/' "$MF"
first_rows "$MF" mut
expect_eq "F.5 the mutant (landing ranked as work) still admits one of them: the writer" "w" "$FIRST"

# ── §ANCESTOR ────────────────────────────────────────────────────────────────
# ancestor_rows <gate lib> <prefix> — a holder passes its admission to a child; a stranger
# types it. Sets AN_CHILD (child's rc and id), AN_STRANGER (rc) and AN_HOLDER (id).
ancestor_rows() {
  fresh "anc-$2"
  world_machine 8 8192 50 6.0
  world_cost k 30
  GATE_LIB="$1" HOLD=1 CHILD=kid ask_bg par work k 0
  wait_for 20 has par.rc; wait_for 20 has kid.rc
  AN_HOLDER="$(id_of par)"
  AN_CHILD="$(rc_of kid) $(id_of kid)"
  AN_NREQ="$(nreq)"
  AN_STRANGER="$(GATE_LIB="$1" BIONIC_GATE_ADMIT="$AN_HOLDER" ask_fg str work k 0)"
  AN_HELD="$(GATE_LIB="$1" BIONIC_SLOT_HELD=1 ask_fg held work k 0)"
  AN_NREQ2="$(nreq)"
  touch "$D/par.go"
}
section "§ANCESTOR — an admission is believed only from its holder (AC-2.13)"
ancestor_rows "$GATE" real
expect_eq "A.1 the holder is admitted" "0" "$(rc_of par)"
expect_eq "A.2 its child, given BIONIC_GATE_ADMIT, is believed: rc 0 and the holder's id" \
  "0 $AN_HOLDER" "$AN_CHILD"
expect_eq "A.3 the child took no number of its own" "1" "$AN_NREQ"
expect_eq "A.4 a stranger typing the same admission asks anyway, and there is no room (rc 75)" \
  "75" "$AN_STRANGER"
expect_eq "A.5 BIONIC_SLOT_HELD=1 is ignored: it asks, and waits (rc 75)" "75" "$AN_HELD"
expect_eq "A.6 the stranger and the held ask each took a number" "3" "$AN_NREQ2"
MA="$(mutant ancestor)"
anchor "$MA" '_gate_ancestor "$hp" || return 1' 1
sed -i.bak '/_gate_ancestor "\$hp" || return 1/d' "$MA"
ancestor_rows "$MA" mut
expect_eq "A.7 the mutant still believes the child" "0 $AN_HOLDER" "$AN_CHILD"
expect_eq "A.8 the mutant (no ancestor test) believes the stranger — the test is the rule" "0" "$AN_STRANGER"

# ── §ANCESTRY ────────────────────────────────────────────────────────────────
# THE GATE BELIEVES BY ANCESTRY (wave-32 T1; D5, design ledger Δ9; AC-1.4). A process that
# descends from the live holder of an admitted, unfinished request already runs under that
# admission, whether or not it carries the id: a nested runner handed a scratch store's id,
# or none, asks the real store and is given the ancestor's admission instead of filing a
# request that store could never admit while the ancestor's lives. The room is one run's (the
# second ask of k finds none), so a child that filed its own request would read 75.
# ancestry_row <name> <child admit, - for unset> — a holder admitted, its child asking with
# that BIONIC_GATE_ADMIT. Sets AY (the child's rc and id), AY_HOLDER and AY_NREQ. ENDFIRST
# passes through.
ancestry_row() {
  fresh "ancestry-$1"
  world_machine 8 8192 50 6.0
  world_cost k 30
  HOLD=1 CHILD=kid CHILD_ADMIT="$2" ask_bg par work k 0
  wait_for 20 has par.rc; wait_for 20 has kid.rc
  AY_HOLDER="$(id_of par)"
  AY="$(rc_of kid) $(id_of kid)"
  AY_NREQ="$(nreq)"
}
section "§ANCESTRY — a descendant of an admission's live holder runs under it, id or no id (D5; AC-1.4)"
ancestry_row unset -
expect_eq "AY.1 the holder is admitted (request 1)" "0 1" "$(rc_of par) $AY_HOLDER"
expect_eq "AY.2 its child with no BIONIC_GATE_ADMIT is admitted as the holder's: rc 0 and its id" \
  "0 $AY_HOLDER" "$AY"
expect_eq "AY.3 …and filed no request of its own: the store holds one" "1" "$AY_NREQ"
ancestry_row bogus 999
expect_eq "AY.4 its child naming an id this store cannot believe (999) is admitted as the holder's" \
  "0 $AY_HOLDER" "$AY"
expect_eq "AY.5 …and filed no request of its own: the store holds one" "1" "$AY_NREQ"
AY_STRANGER="$(ask_fg str work k 0)"
expect_eq "AY.6 a process that is not a descendant still files its own, and finds no room (rc 75)" \
  "75" "$AY_STRANGER"
expect_eq "AY.7 …its request is the store's second" "2 2" "$(nreq) $(req_of str)"
touch "$D/par.go"
ENDFIRST=1 ancestry_row ended -
expect_eq "AY.8 an ended admission is believed by nobody: the child of a holder that ended it files its own (rc 0, request 2)" \
  "0 2" "$AY"
expect_eq "AY.9 …so the store holds two" "2" "$AY_NREQ"
touch "$D/par.go"

# ── §WAITED ──────────────────────────────────────────────────────────────────
section "§WAITED — a request holds its asked and admitted times (AC-4.2)"
fresh waited
world_machine 8 8192 60 6.0
world_cost h 30
world_cost k 30
HOLD=1 ask_bg wh work h 0; wait_for 20 has wh.rc
HOLD=1 ask_bg ww work k 600; wait_for 20 asked_by ww
ww_id="$(req_of ww)"
expect_contains "W.1 while it waits, gate_state counts it" "waiting=1" "$(state)"
world_tick 60
release wh
wait_for 20 has ww.rc
expect_eq "W.2 it is admitted once room appears" "0" "$(rc_of ww)"
expect_eq "W.3 its asked time is 1000" "1000" "$(field "$ww_id" asked)"
expect_eq "W.4 its admitted time is 1060" "1060" "$(field "$ww_id" admitted)"
expect_contains "W.5 gate_list shows both times, a wait of 60 s" \
  "${ww_id:-none} admitted kind=work asked=1000 admitted=1060" "$(glist)"
release ww

# ── §KILLED ──────────────────────────────────────────────────────────────────
section "§KILLED — a run killed with signal 9 is counted once (AC-4.3)"
fresh killed
world_machine 8 8192 50 6.0
world_cost k 30
HOLD=1 ask_bg kk work k 0; wait_for 20 has kk.rc
kk_id="$(id_of kk)"; kk_pid="$(cat "$D/kk.pid")"
expect_eq "K.1 the child is admitted" "0" "$(rc_of kk)"
expect_eq "K.2 while it runs, a second ask finds no room (rc 75)" "75" "$(ask_fg k2 work k 0)"
BIONIC_PROBE_USED_PCT=70 state >/dev/null
kill -KILL "$kk_pid"
wait_for 20 dead "$kk_pid"
dead "$kk_pid" || no "K.3 the killed child is dead" "pid $kk_pid lives"
L1="$(glist)"; L2="$(glist)"
expect_eq "K.4 gate_list counts one killed request" "1" "$(printf '%s\n' "$L1" | grep -c ' killed ')"
expect_contains "K.5 it is the child's" "${kk_id:-none} killed kind=work" "$L1"
expect_eq "K.6 a second reading counts it once again, not twice" "1" "$(printf '%s\n' "$L2" | grep -c ' killed ')"
expect_eq "K.7 it was admitted and never ended (admitted|ended)" "1000|" "$(field "$kk_id" admitted)|$(field "$kk_id" ended)"
expect_contains "K.8 gate_state no longer counts it admitted" "admitted=0 " "$(state)"
expect_eq "K.9 its promise is released: the same ask is now admitted" "0" "$(ask_fg k3 work k 0)"
expect_eq "K.10 the killed run was admitted and holds no peak= line: the gate records no memory (Δ10)" "1000|" \
  "$(field "${kk_id:-none}" admitted)|$(field "${kk_id:-none}" peak)"
expect_eq "K.11 and it wrote no duration: cost/k holds the one planted line" "1 30:1000" \
  "$(wc -l < "$(costf k)" | tr -d ' ') $(head -n 1 "$(costf k)")"

# ── §COST ────────────────────────────────────────────────────────────────────
# WHAT A RUN TEACHES IS ITS DURATION (D12; wave-33 T1, D4 as amended, Δ10; AC-8.6). gate_end
# writes the run's seconds, `<seconds>:<epoch>`, three kept, newest last; the promise reads one
# core, no memory, and the key's longest kept duration (the landing's time limit reads it).
# Nothing about the run's processor time or memory is measured or kept.
section "§COST — a command's duration is learned; nothing else is (D12; Δ10)"
# dur_run <gate lib> <name> — cost/k holds 20, 50 and 90 s; a run admitted at 1000, a gate_state
# mid-run, ended 30 s later. Sets PK_STATE (the mid-run gate_state line), PK_ID and PK_LINE
# (cost/k's newest line).
dur_run() {
  fresh "$2"
  world_machine 8 8192 40 1.0
  world_cost k 20
  world_cost k 50
  world_cost k 90
  world_cost other 10
  GATE_LIB="$1" HOLD=1 ask_bg c1 work k 0; wait_for 20 has c1.rc
  PK_ID="$(id_of c1)"
  PK_STATE="$(GATE_LIB="$1" BIONIC_PROBE_USED_PCT=55 state)"
  printf 'later-field=a line this gate does not know\n' >> "$BIONIC_GATE_DIR/requests/${PK_ID:-none}"
  world_tick 30
  release c1
  PK_LINE="$(tail -n 1 "$(costf k)" 2>/dev/null)"
}
dur_run "$GATE" cost
c1_id="$PK_ID"
expect_eq "D.1 the promise is one core, no memory, and the key's longest kept duration" "0:1:90" "$(field "$c1_id" promise)"
expect_contains "D.2 a reading taken during the run (gate_state at 55) sees it admitted" "admitted=1 " "$PK_STATE"
expect_eq "D.3 the request was admitted and holds no peak= line: no memory is sampled for it" "1000|" \
  "$(field "$c1_id" admitted)|$(field "$c1_id" peak)"
expect_eq "D.16 a request line the gate does not know is ignored: the run ended all the same" \
  "1030 a line this gate does not know" "$(field "$c1_id" ended) $(field "$c1_id" later-field)"
expect_eq "D.4 gate_end exits 0" "0" "$(cat "$D/c1.endrc")"
expect_eq "D.5 it writes ended at 1030" "1030" "$(field "$c1_id" ended)"
expect_eq "D.6 and the rc" "0" "$(field "$c1_id" rc)"
expect_eq "D.7 cost/k keeps three lines: the oldest planted is now the second" "3 50:1000" \
  "$(wc -l < "$(costf k)" | tr -d ' ') $(head -n 1 "$(costf k)")"
expect_eq "D.8 the newest is this run: 30 s, at 1030" "30:1030" "$PK_LINE"
expect_eq "D.9 the oldest planted line is gone" "0" "$(grep -c '^20:' "$(costf k)")"
world_machine 8 8192 40 1.0
HOLD=1 ask_bg c2 work never-seen 0; wait_for 20 has c2.rc
expect_eq "D.10 a command never seen is promised one core and no seconds" "0:1:0" \
  "$(field "$(id_of c2)" promise)"
release c2
fresh cost-over
world_machine 8 8192 40 1.0
world_cost k 20
world_cost j 20
HOLD=1 ask_bg o1 work k 0; wait_for 20 has o1.rc
HOLD=1 ask_bg o2 work j 0; wait_for 20 has o2.rc
expect_eq "D.11 two runs are admitted side by side" "0 0" "$(rc_of o1) $(rc_of o2)"
BIONIC_PROBE_USED_PCT=70 state >/dev/null
world_tick 10
release o1; release o2
expect_eq "D.12 an overlapped run records its own seconds, as any run does" "10:1010" "$(tail -n 1 "$(costf k)")"
fresh cost-cpu
world_machine 8 8192 40 1.0
world_cost k 20
WORK="awk 'BEGIN { for (i = 0; i < 3000000; i++) s += i }'" HOLD=1 ask_bg u1 work k 0
wait_for 20 has u1.rc
world_tick 1
release u1
expect_eq "D.13 a run that did processor work records its seconds and epoch only: no cores, no memory" \
  "20:1000 1:1001" "$(tr '\n' ' ' < "$(costf k)" | sed 's/ $//')"
# age_runs <gate lib> <name> — cost/k holds one overlong run (300 s); four 10 s runs follow. Sets
# AGE to the four admissions' promised seconds.
age_runs() {
  local i p
  fresh "$2"
  world_machine 8 8192 40 1.0
  world_cost k 300
  AGE=""
  for i in 1 2 3 4; do
    GATE_LIB="$1" HOLD=1 ask_bg "a$i" work k 0; wait_for 20 has "a$i.rc"
    p="$(field "$(id_of "a$i")" promise)"; AGE="$AGE ${p##*:}"
    world_tick 10
    release "a$i"
  done
  AGE="${AGE# }"
}
age_runs "$GATE" cost-age
expect_eq "D.19 three shorter runs do not shorten the promise until the overlong one ages out" \
  "300 300 300 10" "$AGE"
MK="$(mutant keep4)"
anchor "$MK" '} | tail -n 3 > "$_GD/cost/.new.$id"' 1
sed -i.bak 's/} | tail -n 3 > "\$_GD\/cost\/.new.\$id"/} | tail -n 4 > "$_GD\/cost\/.new.$id"/' "$MK"
age_runs "$MK" cost-age-mut
expect_eq "D.20 the mutant keeping four lines still runs all four and holds 300 one run longer" \
  "300 300 300 300" "$AGE"
expect_eq "D.14 gate_end of a request that does not exist exits 2" "2" \
  "$( . "$GATE_LIB" 2>/dev/null; gate_end 999 0 2>/dev/null; echo $? )"
expect_eq "D.15 gate_ask with an unknown kind exits 2" "2" \
  "$( . "$GATE_LIB" 2>/dev/null; gate_ask fast k 2>/dev/null; echo $? )"
# THE PUBLIC READER (T13; pass 12): `gate_promise <key>` prints what `_gate_promise` prints,
# loading the store itself, so a caller outside the lock can ask what a key is promised.
fresh promise-public
world_cost k 30
world_cost k 45
expect_eq "D.21 gate_promise prints one core and the key's longest duration, loading the store itself" \
  "0:1:45" "$( . "$GATE_LIB" 2>/dev/null; gate_promise k 2>/dev/null )"
expect_eq "D.22 a key never seen is promised one core and no seconds" \
  "0:1:0" "$( . "$GATE_LIB" 2>/dev/null; gate_promise never 2>/dev/null )"
expect_eq "D.23 no key is a usage error (rc 2)" "2" \
  "$( . "$GATE_LIB" 2>/dev/null; gate_promise 2>/dev/null; echo $? )"

# ── §ZERO-SECONDS ────────────────────────────────────────────────────────────
# A RUN OF ZERO SECONDS TEACHES NOTHING (wave-32 T1; D5). A run admitted and ended in the same
# second has no measured time: gate_end writes its end and rc, and no duration line. One ended
# 2 s later still writes.
section "§ZERO-SECONDS — a run admitted and ended in one second writes no duration line (D5)"
fresh zero-seconds
world_machine 8 8192 40 1.0
world_cost k 20
ZS_BEFORE="$(cat "$(costf k)")"
HOLD=1 ask_bg z0 work k 0; wait_for 20 has z0.rc
z0_id="$(id_of z0)"
release z0
expect_eq "Z.1 the run is admitted and ended at the same second (admitted|ended|rc)" "1000|1000|0" \
  "$(field "$z0_id" admitted)|$(field "$z0_id" ended)|$(field "$z0_id" rc)"
expect_eq "Z.2 gate_end exits 0" "0" "$(cat "$D/z0.endrc" 2>/dev/null)"
expect_eq "Z.3 …and the duration file is unchanged: the one planted line" "$ZS_BEFORE" \
  "$(cat "$(costf k)")"
HOLD=1 ask_bg z2 work k 0; wait_for 20 has z2.rc
z2_id="$(id_of z2)"
world_tick 2
release z2
expect_eq "Z.4 a run ended 2 s after its admission writes its end" "1000|1002" \
  "$(field "$z2_id" admitted)|$(field "$z2_id" ended)"
expect_eq "Z.5 …and a duration line: 2 s, at 1002, after the planted one" \
  "20:1000 2:1002" "$(tr '\n' ' ' < "$(costf k)" | sed 's/ $//')"

# ── §CORES-OVER ──────────────────────────────────────────────────────────────
# A RUN'S PROCESSOR TIME IS NOT MEASURED (wave-33 T1; Δ10, which retires wave-32 T19's core-count
# test with the measurement it guarded). The children's time is planted (PLANT_CPU) at 40 s over
# a 2 s run on an 8-core machine, 20 cores, a number no run can reach: the line written is the
# run's seconds all the same, and carries no cores.
section "§CORES-OVER — a run's processor time is neither measured nor recorded (Δ10)"
cores_run() {  # <name> <planted cpu seconds> [gate lib] — a 2 s run on the planted clock, ended
  GATE_LIB="${3:-$GATE_LIB}" PLANT_CPU="$2" HOLD=1 ask_bg "$1" work k 0; wait_for 20 has "$1.rc"
  world_tick 2
  release "$1"
}
fresh cores-over
world_machine 8 8192 40 1.0
world_cost k 20
cores_run co1 40
co1_id="$(id_of co1)"
expect_eq "CO.1 a run whose children took 40 s over 2 s writes its end and rc" "1002|0" \
  "$(field "$co1_id" ended)|$(field "$co1_id" rc)"
expect_eq "CO.2 gate_end exits 0" "0" "$(cat "$D/co1.endrc" 2>/dev/null)"
expect_eq "CO.3 …and its duration, 2 s at 1002, after the planted line: no cores field" \
  "20:1000 2:1002" "$(tr '\n' ' ' < "$(costf k)" | sed 's/ $//')"

# ── §WHOLE-COST ──────────────────────────────────────────────────────────────
# A WHOLE RUN IS PROMISED ITS WIDTH, AND NOTHING IT RECORDS MOVES ANOTHER'S PROMISE (wave-32 T26;
# D1, D5; wave-33 T1, Δ10). A whole admission holds the machine alone and takes gate_width
# workers, so it is promised gate_width cores (6 at share 80 on 8). Its gate_end records its
# seconds like any run's, unmarked: a never-seen key is promised one core before and after it,
# and gate_room charges an owed writer one core. The arms are the wave-32 critic's probe: a work
# request for a.test.sh held, then a never-seen key asks, without and with a whole run on record.
# The whole run's own next ask is pinned both ways: it waits while a.test.sh is held and is
# admitted once nothing is.
section "§WHOLE-COST — a whole run is promised its width; its record moves no other promise (D1, D5; Δ10)"
wc_room() { ( . "$GATE_LIB" 2>/dev/null; o="$(gate_room --owed 1 2>&1)"; r=$?; printf '%s rc=%s' "$o" "$r" ); }
wc_promise() { ( . "$GATE_LIB" 2>/dev/null; gate_promise "$1" 2>&1 ); }
fresh whole-cost-without
world_machine 8 8192 40 1.0
world_cost a.test.sh 120
HOLD=1 ask_bg wa work a.test.sh 0; wait_for 20 has wa.rc
expect_eq "WC.1 without a whole run: the work request for a.test.sh is admitted and held (rc)" "0" "$(rc_of wa)"
expect_eq "WC.2 …a never-seen key is promised one core" "0:1:0" "$(wc_promise new.test.sh)"
expect_eq "WC.3 …gate_room --owed 1 charges one core for the owed writer beside the held one and gives room" \
  "room=yes load=1.0/1.0 cores=8 promised=2 waiting=0 rc=0" "$(wc_room)"
expect_eq "WC.4 …and the never-seen key is admitted beside the held one (rc 0)" "0" \
  "$(ask_fg wn work new.test.sh 0)"
fresh whole-cost-with
world_machine 8 8192 40 1.0
world_cost a.test.sh 120
PLANT_CPU=14.10 HOLD=1 ask_bg wr whole tests/run.sh 0; wait_for 20 has wr.rc
world_tick 2
release wr
wr_id="$(id_of wr)"
expect_eq "WC.5 the whole request was admitted at 1000 and ended at 1002 with rc 0" "1000|1002|0" \
  "$(field "$wr_id" admitted)|$(field "$wr_id" ended)|$(field "$wr_id" rc)"
expect_eq "WC.6 …promised its width, gate_width (6 at share 80 on 8), no memory, no seconds yet" "0:6:0" \
  "$(field "$wr_id" promise)"
expect_eq "WC.7 its gate_end wrote one line, 2 s at 1002, unmarked" "2:1002" \
  "$(cat "$(costf tests/run.sh)" 2>/dev/null)"
HOLD=1 ask_bg wa work a.test.sh 0; wait_for 20 has wa.rc
expect_eq "WC.8 with the whole run on record, the work request for a.test.sh is admitted and held (rc)" "0" \
  "$(rc_of wa)"
expect_eq "WC.9 …a never-seen key is still promised one core" "0:1:0" "$(wc_promise new.test.sh)"
expect_eq "WC.10 …gate_room --owed 1 still charges one core, and gives room" \
  "room=yes load=1.0/1.0 cores=8 promised=2 waiting=0 rc=0" "$(wc_room)"
expect_eq "WC.11 …and the never-seen key is admitted beside the held one (rc 0)" "0" \
  "$(ask_fg wn work new.test.sh 0)"
expect_eq "WC.12 the whole run's next ask, a.test.sh still held, waits (rc 75)" "75" \
  "$(ask_fg wr2 whole tests/run.sh 0)"
release wa
expect_eq "WC.13 …and with nothing held it is admitted (rc 0), promised its width and its 2 s" "0|0:6:2" \
  "$(ask_fg wr3 whole tests/run.sh 0)|$(field "$(id_of wr3)" promise)"

# ── §ONE-CORE ────────────────────────────────────────────────────────────────
# THE GATE DOES NOT FORECAST FROM HISTORY (wave-33 T1; D4 as amended, Δ10; AC-8.1). A command
# that declares no width is promised one core and no memory; a whole run, the width it takes
# (gate_width); no cores or memory are read from recorded runs, and live load is the backstop.
# The store planted here is the research's (research-wall-landing-gate.md §4): a 4.4-core line
# from a 1-second run and a 3.94-core line from a 2,923-second one, in the 1.15.0 unkeyed shape.
# Planted 8 cores, share 92 (7.36), 1.2 cores busy, 30% memory used.
section "§ONE-CORE — a command is promised one core, whatever is on record (AC-8.1)"
legacy_cost() {  # <file name> <line>... — an unkeyed cost file, as 1.15.0 and before wrote them
  local f="$BIONIC_GATE_DIR/cost/$1"; shift
  mkdir -p "$BIONIC_GATE_DIR/cost"; printf '%s\n' "$@" >> "$f"
}
promise_in() { ( cd "$1" && . "$GATE_LIB" 2>/dev/null && gate_promise "$2" 2>&1 ); }  # <dir> <key>
share92() { printf '92\n' > "$CLAUDE_CONFIG_DIR/bionic/share"; }
oc_room() { ( . "$GATE_LIB" 2>/dev/null; o="$(gate_room "$@" 2>&1)"; r=$?; printf '%s rc=%s' "$o" "$r" ); }
fresh one-core-empty
share92
world_machine 8 8192 30 1.2
expect_eq "OC.1 an empty store promises a command one core, no memory, no seconds" "0:1:0" \
  "$(promise_in "$REPO_ROOT" never.test.sh)"
fresh one-core
share92
world_machine 8 8192 30 1.2
legacy_cost version-compare.test.sh "33:4.4:1:900"
legacy_cost seen.test.sh "33:3.94:2923:900"
expect_eq "OC.2 with a 4.4-core line on record, an unseen command is promised one core" "0:1:0" \
  "$(promise_in "$REPO_ROOT" never.test.sh)"
expect_eq "OC.3 …and the seen one, 3.94 cores on record, one core too: only its seconds are read" "0:1:2923" \
  "$(promise_in "$REPO_ROOT" seen.test.sh)"
HOLD=1 ask_bg oa work seen.test.sh 0; wait_for 20 has oa.rc
HOLD=1 ask_bg ob work never.test.sh 0; wait_for 20 has ob.rc
expect_eq "OC.4 two writers on that store are admitted side by side (A held, B beside it)" "0 0 ended=" \
  "$(rc_of oa) $(rc_of ob) ended=$(field "$(id_of oa)" ended)"
expect_eq "OC.5 …each promised one core: A's seconds its own, B's none" "0:1:2923 0:1:0" \
  "$(field "$(id_of oa)" promise) $(field "$(id_of ob)" promise)"
expect_eq "OC.6 gate_room charges two owed writers one core each beside the two admitted (1.2 + 4 ≤ 7.36)" \
  "room=yes load=1.2/1.2 cores=8 promised=4 waiting=0 rc=0" "$(oc_room --owed 2)"
reap
fresh one-core-whole
share92
world_machine 8 8192 30 1.2
legacy_cost "tests%run.sh" "2:5.11:1932:900:whole"
HOLD=1 ask_bg ow whole tests/run.sh 0; wait_for 20 has ow.rc
expect_eq "OC.7 a whole run is promised the width it takes, gate_width (7 at 92 on 8), and its seconds" "0|0:7:1932" \
  "$(rc_of ow)|$(field "$(id_of ow)" promise)"
reap

# ── §SIDE-BY-SIDE ────────────────────────────────────────────────────────────
# TWO WRITERS ON AN IDLE MACHINE (wave-33 T1; D4, AC-8.2). The probe's shape
# (record/wave-33-workhorse/probes/probe-gate.sh): writer A's single suite is admitted and
# held; writer B's, a key with no record of its own, asks with no time to wait. Planted 8 cores,
# share 92. B is admitted while A still holds, or the row is red.
section "§SIDE-BY-SIDE — two writers' single suites are admitted side by side (AC-8.2)"
side_by_side() {  # <name> <busy cores> <file=line>... — SB: A's rc, B's rc, A's ended (empty: still held)
  local kv
  fresh "$1"; share92
  world_machine 8 8192 30 "$2"; shift 2
  for kv in "$@"; do legacy_cost "${kv%%=*}" "${kv#*=}"; done
  HOLD=1 ask_bg sa work a.test.sh 0; wait_for 20 has sa.rc
  HOLD=1 ask_bg sb work b.test.sh 0; wait_for 20 has sb.rc
  SB="$(rc_of sa) $(rc_of sb) ended=$(field "$(id_of sa)" ended)"
}
side_by_side side-fresh 0
expect_eq "SB.1 a fresh store, an idle machine: A is admitted, then B beside it while A holds" "0 0 ended=" "$SB"
expect_eq "SB.2 …B was promised one core" "0:1:0" "$(field "$(id_of sb)" promise)"
side_by_side side-stray 3.5 "a.test.sh=0:1.1:30:1" "x.test.sh=0:4.4:1:1"
expect_eq "SB.3 the probe's row: a stray 4.4-core 1-second line, 3.5 cores busy: B is admitted beside A" "0 0 ended=" "$SB"
expect_eq "SB.4 …promised one core, not the stray 4.4" "0:1:0" "$(field "$(id_of sb)" promise)"
reap

# ── §DURATIONS ───────────────────────────────────────────────────────────────
# THE ONLY HISTORY IS EACH SUITE'S DURATION, KEYED BY PROJECT AND COMMAND (wave-33 T1; D4 as
# amended, Δ10; AC-8.6). gate_end writes `<seconds>:<epoch>` to `cost/<project key>%<command>`;
# the project key is the asking checkout's repository (its common git directory, so every
# worktree of one repository is one project; a directory that is no repository is itself). The
# landing's time limit (line.sh `_line_time_for`) reads the seconds. Two fixture projects run
# the same command, `tests/run.sh`, on the planted clock: B for 2 s, then A for 5 s. An unkeyed
# file a 1.15.0 gate wrote is read for its seconds only, for a key with no keyed file, and is
# never moved or changed.
section "§DURATIONS — two projects' same-named suites keep separate durations (AC-8.6)"
run_in() {  # <dir> <name> <seconds> — a work run of tests/run.sh in <dir>, ended <seconds> later
  pushd "$1" >/dev/null || return 1
  HOLD=1 ask_bg "$2" work tests/run.sh 0
  popd >/dev/null || return 1
  wait_for 20 has "$2.rc"; world_tick "$3"; release "$2"
}
limit_in() {  # <dir> — the landing's time limit for tests/run.sh asked from <dir>, deadline now+100
  ( cd "$1" && . "$GATE_LIB" 2>/dev/null && . "$REPO_ROOT/payload/scripts/lib/line.sh" 2>/dev/null \
      && _line_time_for tests/run.sh "$(( $(_res_now) + 100 ))" 2>&1 )
}
fresh durations
share92
world_machine 8 8192 30 0
PA="$D/projA"; PB="$D/projB"
for p in "$PA" "$PB"; do mkdir -p "$p"; git init -q "$p"; done
PKA_FILE="$(costf tests/run.sh "$PA")"
PKB_FILE="$(costf tests/run.sh "$PB")"
expect_regex "DU.1 each project has a key of its own: 8 hex digits, A's not B's" '^[0-9a-f]{8} [0-9a-f]{8} differ$' \
  "$(pk_here "$PA") $(pk_here "$PB") $([ "$(pk_here "$PA")" != "$(pk_here "$PB")" ] && echo differ)"
run_in "$PB" pb 2
DU_B0="$(limit_in "$PB")"
expect_eq "DU.2 project B's 2 s run of tests/run.sh wrote B's own file, seconds and epoch only" "2:1002" \
  "$(cat "$PKB_FILE" 2>/dev/null)"
expect_eq "DU.3 …and B's time limit for tests/run.sh is 100 s less its 2 recorded" "98" "$DU_B0"
run_in "$PA" pa 5
expect_eq "DU.4 project A's 5 s run of tests/run.sh wrote A's own file" "5:1007" "$(cat "$PKA_FILE" 2>/dev/null)"
expect_eq "DU.5 …B's file still holds B's one line" "2:1002" "$(cat "$PKB_FILE" 2>/dev/null)"
expect_eq "DU.6 …and B's time limit is unchanged by A's run" "$DU_B0" "$(limit_in "$PB")"
expect_eq "DU.7 A's time limit reads A's 5 s" "95" "$(limit_in "$PA")"
expect_eq "DU.8 no unkeyed tests%run.sh was written" "absent" \
  "$([ -e "$BIONIC_GATE_DIR/cost/tests%run.sh" ] && echo present || echo absent)"
pushd "$PB" >/dev/null || exit 1; HOLD=1 ask_bg pb3 work tests/run.sh 0; popd >/dev/null || exit 1
wait_for 20 has pb3.rc
expect_eq "DU.9 an admission asked from B is promised one core and B's seconds" "0|0:1:2" \
  "$(rc_of pb3)|$(field "$(id_of pb3)" promise)"
reap
git -C "$PA" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init 2>/dev/null
git -C "$PA" worktree add -q "$D/projA-wt" 2>/dev/null
expect_nonempty "DU.10 a worktree of A is a checkout of its own (positive)" \
  "$(git -C "$D/projA-wt" rev-parse --show-toplevel 2>/dev/null)"
expect_eq "DU.11 …and is project A: its time limit reads A's 5 s" "95" "$(limit_in "$D/projA-wt")"
fresh durations-legacy
share92
world_machine 8 8192 30 0
PC="$D/projC"; mkdir -p "$PC"; git init -q "$PC"
legacy_cost "tests%run.sh" "5:7:30:900"
DUL_BEFORE="$(cat "$BIONIC_GATE_DIR/cost/tests%run.sh")"
expect_eq "DU.12 an unkeyed tests%run.sh is read for its seconds only: one core, 30 s" "0:1:30" \
  "$(promise_in "$PC" tests/run.sh)"
run_in "$PC" pc 2
expect_eq "DU.13 C's run writes C's own file" "2:1002" "$(cat "$(costf tests/run.sh "$PC")" 2>/dev/null)"
expect_eq "DU.14 …which C's promise now reads, not the unkeyed 30 s" "0:1:2" "$(promise_in "$PC" tests/run.sh)"
expect_eq "DU.15 …and the unkeyed file is neither moved nor changed" "$DUL_BEFORE" \
  "$(cat "$BIONIC_GATE_DIR/cost/tests%run.sh" 2>/dev/null)"

# ── §SHARE-ROOM ──────────────────────────────────────────────────────────────
# ONE SITE FOR THE SHARE'S ROOM, ONE FOR THE CORE (wave-33 T1; debt share-room, AC-9.1; Δ10).
# share × cores ÷ 100 is the processor room the share allows: gate_width floors it, the
# admission test and gate_room compare against it unfloored, and it used to be computed at each
# of the three. Now `_gate_share_cores` computes it and all three read it: a mutant that doubles
# the room there moves the width, the admission and the room together. Likewise the one core a
# command is promised and the room charges an owed writer comes from `_gate_cores_for`: a
# mutant there moves both. Planted 8 cores, share 92 (7.36), 6.5 cores busy: a held run, a
# second ask, and one owed writer.
section "§SHARE-ROOM — the share's room and the one core are each computed at one site (AC-9.1)"
share_room_rows() {  # <gate lib> <name> — SR: width, held rc, second rc, room line with rc
  fresh "$2"; share92
  world_machine 8 8192 30 6.5
  SR_W="$(GATE_LIB="$1" bash -c '. "$GATE_LIB" 2>/dev/null; gate_width')"
  GATE_LIB="$1" HOLD=1 ask_bg s1 work a.test.sh 0; wait_for 20 has s1.rc
  GATE_LIB="$1" HOLD=1 ask_bg s2 work b.test.sh 0; wait_for 20 has s2.rc
  SR="$SR_W $(rc_of s1) $(rc_of s2) $(GATE_LIB="$1" oc_room --owed 1)"
}
share_room_rows "$GATE" share-room
expect_eq "SR.1 shipped: width 7; the held run admitted; the second (6.5 + 1 > 7.36) waits; an owed writer finds no room" \
  "7 0 75 room=no load=6.5/6.5 cores=8 promised=2 waiting=0 rc=1" "$SR"
MSR="$(mutant share-room)"
anchor "$MSR" 'printf "%.10g", s * c / 100' 1
sed -i.bak 's#printf "%.10g", s \* c / 100#printf "%.10g", s * c / 50#' "$MSR"
share_room_rows "$MSR" share-room-mut
expect_eq "SR.2 the room's one site doubled (14.72): width 14, the second ask admitted, room for the owed writer" \
  "14 0 0 room=yes load=6.5/6.5 cores=8 promised=3 waiting=0 rc=0" "$SR"
MCO="$(mutant one-core)"
anchor "$MCO" '    *)     echo 1 ;;' 1
sed -i.bak 's#^    \*)     echo 1 ;;#    *)     echo 3 ;;#' "$MCO"
fresh one-core-mut
share92
world_machine 8 8192 30 1.2
expect_eq "SR.3 the core's one site set to 3: the stranger's promise reads 3" "0:3:0" \
  "$( . "$MCO" 2>/dev/null; gate_promise never.test.sh 2>&1 )"
expect_eq "SR.4 …and the room charges the owed writer 3 too: the two cannot disagree" \
  "room=yes load=1.2/1.2 cores=8 promised=3 waiting=0 rc=0" "$(GATE_LIB="$MCO" oc_room --owed 1)"
reap

# ── §ROOM ────────────────────────────────────────────────────────────────────
# gate_room [--owed <n>] (wave-28 T13; D14): may another writer start? Every row plants an
# 8-core machine under a share of 80, so the processor limit is 6.4 cores. `room` runs the
# verb in a child and appends its rc to the one line it prints.
section "§ROOM — width follows the machine's load (AC-2.5)"
room() { ( . "$GATE_LIB" 2>/dev/null; o="$(gate_room "$@" 2>&1)"; r=$?; printf '%s rc=%s' "$o" "$r" ); }
fresh room-quiet
world_machine 8 8192 30 1.0
world_cost k 30
expect_eq "RM.1 a quiet machine gives room" \
  "room=yes load=1.0/1.0 cores=8 promised=0 waiting=0 rc=0" "$(room)"
fresh room-5m
world_machine 8 8192 30 1.0 7.0
world_cost k 30
expect_eq "RM.2 a five-minute load of 7.0, over 6.4 cores, gives no room though the last minute is quiet" \
  "room=no load=1.0/7.0 cores=8 promised=0 waiting=0 rc=1" "$(room)"
expect_eq "RM.3 …and the same machine with its five-minute load at 1.0 gives room" \
  "room=yes load=1.0/1.0 cores=8 promised=0 waiting=0 rc=0" "$(BIONIC_PROBE_BUSY_CORES_5M=1.0 room)"
expect_eq "RM.4 a one-minute load over the share gives no room either" \
  "room=no load=7.0/1.0 cores=8 promised=0 waiting=0 rc=1" \
  "$(BIONIC_PROBE_BUSY_CORES=7.0 BIONIC_PROBE_BUSY_CORES_5M=1.0 room)"
M5="$(mutant room-5m)"
anchor "$M5" 'if (known(b5)) { if (b5 + prom > lim) room = 0 }' 1
sed -i.bak 's/if (known(b5)) { if (b5 + prom > lim) room = 0 }/if (0) room = 0/' "$M5"
expect_eq "RM.4a the mutant that ignores the five-minute load runs and gives room — the reading is the rule" \
  "room=yes load=1.0/7.0 cores=8 promised=0 waiting=0 rc=0" "$(GATE_LIB="$M5" room)"
fresh room-wait
world_machine 8 8192 30 1.0
world_cost k 30
HOLD=1 ask_bg rw1 work k 0; wait_for 20 has rw1.rc
ask_bg rw2 whole k 600; wait_for 20 asked_by rw2
expect_eq "RM.5 one is admitted and a whole request waits behind it (rc|asked|admitted)" "0|1000|" \
  "$(rc_of rw1)|$(field "$(req_of rw2)" asked)|$(field "$(req_of rw2)" admitted)"
expect_eq "RM.6 a waiting request gives no room, though the load and the promises fit" \
  "room=no load=1.0/1.0 cores=8 promised=1 waiting=1 rc=1" "$(room)"
MW="$(mutant room-wait)"
anchor "$MW" 'if (wait > 0) room = 0' 1
sed -i.bak 's/if (wait > 0) room = 0/if (0) room = 0/' "$MW"
expect_eq "RM.7 the mutant without the waiting clause runs and gives room — the clause is the rule" \
  "room=yes load=1.0/1.0 cores=8 promised=1 waiting=1 rc=0" "$(GATE_LIB="$MW" room)"
release rw1
# Every command is promised one core and every owed writer charged one (wave-33 T1; Δ10), so
# these rows set the room with the live load: 5.5, 4.5 and 5.5 busy cores of the 6.4 allowed.
fresh room-prom
world_machine 8 8192 30 5.5
world_cost k 30
HOLD=1 ask_bg rp1 work k 0; wait_for 20 has rp1.rc
expect_eq "RM.8 a run is admitted promising one core (rc|promise)" "0|0:1:30" \
  "$(rc_of rp1)|$(field "$(req_of rp1)" promise)"
expect_eq "RM.9 a load of 5.5 plus the one core promised and not yet showing is over 6.4: no room" \
  "room=no load=5.5/5.5 cores=8 promised=1 waiting=0 rc=1" "$(room)"
release rp1
expect_eq "RM.10 once it has ended its promise no longer counts" \
  "room=yes load=5.5/5.5 cores=8 promised=0 waiting=0 rc=0" "$(room)"
fresh room-owed
world_machine 8 8192 30 4.5
world_cost k 30
expect_eq "RM.11 one writer owed at one core: 4.5 + 1 fits" \
  "room=yes load=4.5/4.5 cores=8 promised=1 waiting=0 rc=0" "$(room --owed 1)"
expect_eq "RM.12 two writers owed: 4.5 + 2 is over 6.4, no room" \
  "room=no load=4.5/4.5 cores=8 promised=2 waiting=0 rc=1" "$(room --owed 2)"
MO="$(mutant room-owed)"
anchor "$MO" 'prom = pc + owed * most' 1
sed -i.bak 's/prom = pc + owed \* most/prom = pc + 0 * most/' "$MO"
expect_eq "RM.13 the mutant that drops the owed count runs and gives room — the count is the rule" \
  "room=yes load=4.5/4.5 cores=8 promised=0 waiting=0 rc=0" "$(GATE_LIB="$MO" room --owed 2)"
fresh room-two
world_machine 8 8192 30 5.5
world_cost k 30
expect_eq "RM.14 the first ask on one reading, nothing offered yet: room" \
  "room=yes load=5.5/5.5 cores=8 promised=0 waiting=0 rc=0" "$(room --owed 0)"
expect_eq "RM.15 the second ask on the same reading counts the first: 5.5 + 1 is over 6.4" \
  "room=no load=5.5/5.5 cores=8 promised=1 waiting=0 rc=1" "$(room --owed 1)"
fresh room-nocost
world_machine 8 8192 30 1.0
expect_eq "RM.16 no cost on record and nothing owed: room" \
  "room=yes load=1.0/1.0 cores=8 promised=0 waiting=0 rc=0" "$(room)"
expect_eq "RM.17 no cost on record: one writer not yet showing is charged one core (wave-33 T1, AC-8.1): room" \
  "room=yes load=1.0/1.0 cores=8 promised=1 waiting=0 rc=0" "$(room --owed 1)"
fresh room-mem
world_machine 8 8192 85 1.0
world_cost k 30
expect_eq "RM.18 memory used 85 under a share of 80 gives no room" \
  "room=no load=1.0/1.0 cores=8 promised=0 waiting=0 rc=1" "$(room)"
expect_eq "RM.19 …and 80 used gives room (at most the share)" \
  "room=yes load=1.0/1.0 cores=8 promised=0 waiting=0 rc=0" "$(BIONIC_PROBE_USED_PCT=80 room)"
fresh room-blind
world_machine 8 8192 30 1.0
world_cost k 30
expect_eq "RM.20 an unreadable five-minute load with nothing admitted, waiting or owed: room" \
  "room=yes load=1.0/-1 cores=8 promised=0 waiting=0 rc=0" "$(BIONIC_PROBE_BUSY_CORES_5M=-1 room)"
expect_eq "RM.21 …and with one writer owed: no room" \
  "room=no load=1.0/-1 cores=8 promised=1 waiting=0 rc=1" "$(BIONIC_PROBE_BUSY_CORES_5M=-1 room --owed 1)"
expect_eq "RM.22 an unreadable memory reading with one writer owed: no room" \
  "room=no load=1.0/1.0 cores=8 promised=1 waiting=0 rc=1" "$(BIONIC_PROBE_USED_PCT=-1 room --owed 1)"
expect_eq "RM.23 an owed count that is not a whole number is a usage error (rc 2)" "2" \
  "$( . "$GATE_LIB" 2>/dev/null; gate_room --owed x >/dev/null 2>&1; echo $? )"
fresh room-state
world_machine 8 8192 30 1.0 2.5
world_cost k 30
HOLD=1 ask_bg rs1 work k 0; wait_for 20 has rs1.rc
expect_eq "RM.24 gate_state prints the loads and the promised cores where clears= stood" \
  "share=80 used=30 admitted=1 waiting=0 landing-waiting=0 load=1.0/2.5 promised=1" "$(state)"
expect_absent "RM.25 …and no clears= field" "clears=" "$(state)"
release rs1
# ── §OWED ────────────────────────────────────────────────────────────────────
# (wave-28 T52, a fixit on T13; AC-2.5, AC-2.8.) The stop wall's owed count asks the gate who is
# showing on every Stop, under a 10 s hook timeout. It used to fork one grep per request file per
# open writer, over a store that was never pruned. Now one awk reads every request once and counts
# the unended ones, and the scan removes ended requests older than BIONIC_GATE_KEEP. The budget is
# read two ways: the grep forks a stub on PATH sees (none are allowed) and the wall time in whole
# seconds from `date +%s` around the call (at most 1, which a call under a second meets even across
# a tick; the per-file walk over 2,000 files is tens of seconds).
section "§OWED — the owed count reads the store once and the store is pruned (T52)"
plant_ended() {  # <id> <who> <ended epoch> — one ended request
  mkdir -p "$BIONIC_GATE_DIR/requests"
  printf 'key=k\nkind=work\nwho=%s\ntree=/t\nasked=%s\nholder=-\nadmitted=%s\npromise=5:1:30\nended=%s\nrc=0\n' \
    "$2" "$(( $3 - 20 ))" "$(( $3 - 10 ))" "$3" > "$BIONIC_GATE_DIR/requests/$1"
}
plant_ended_many() {  # <n> <who prefix> <ended epoch> — n ended requests, ids 100001 up, in one awk
  mkdir -p "$BIONIC_GATE_DIR/requests"
  awk -v n="$1" -v p="$2" -v e="$3" -v d="$BIONIC_GATE_DIR/requests" 'BEGIN {
    for (i = 1; i <= n; i++) {
      f = d "/" (100000 + i)
      printf "key=k\nkind=work\nwho=%s%d\ntree=/t\nasked=%d\nholder=-\nadmitted=%d\npromise=5:1:30\nended=%d\nrc=0\n",
        p, i, e - 20, e - 10, e > f
      close(f)
    }
  }'
}
plant_open() {  # <id> <who> — one request nothing has ended: waiting, held by this shell, which lives (T71)
  printf 'key=k\nkind=work\nwho=%s\ntree=/t\nasked=900\nholder=%s:\n' "$2" "$$" > "$BIONIC_GATE_DIR/requests/$1"
}
gone_or_kept() { [ -e "$BIONIC_GATE_DIR/requests/$1" ] && echo kept || echo gone; }
mkdir -p "$WORLD_ROOT/owed-stub"
printf '#!/bin/sh\necho x >> "%s"\nexec /usr/bin/grep "$@"\n' "$WORLD_ROOT/owed-greps" > "$WORLD_ROOT/owed-stub/grep"
chmod +x "$WORLD_ROOT/owed-stub/grep"
owed_names() {  # the writers asked about: w1..w6 open, wEnded ended, wNever never asked
  local i
  for i in 1 2 3 4 5 6; do printf '%s:w%s\n' "$WORLD_SID" "$i"; done
  printf '%s:wEnded\n%s:wNever\n' "$WORLD_SID" "$WORLD_SID"
}
owed_count() {  # <gate lib> — fill_gate_owed over owed_names' names, a stub counting grep forks
  : > "$WORLD_ROOT/owed-greps"
  ( . "$1" 2>/dev/null; . "$REPO_ROOT/payload/scripts/lib/fill.sh" 2>/dev/null
    owed_names | sed "s/^$WORLD_SID://" \
      | PATH="$WORLD_ROOT/owed-stub:$PATH" fill_gate_owed /nonexistent "$WORLD_SID" )
}
fresh owed-budget
world_machine 8 8192 30 1.0
plant_ended_many 2000 "$WORLD_SID:e" 900
plant_ended 99999 "$WORLD_SID:wEnded" 900
for i in 1 2 3 4 5 6; do plant_open "$i" "$WORLD_SID:w$i"; done
expect_eq "OW.1 the planted store reads: six requests without an ended line (positive)" "6" \
  "$(/usr/bin/grep -L '^ended=' "$BIONIC_GATE_DIR"/requests/[0-9]* | wc -l | tr -d ' ')"
expect_eq "OW.2 …among 2,007 request files" "2007" "$(nreq)"
OW_T0="$(date +%s)"
OW_N="$(owed_count "$GATE_LIB")"
OW_T1="$(date +%s)"
OW_GREPS="$(wc -l < "$WORLD_ROOT/owed-greps" | tr -d ' ')"
expect_eq "OW.3 the owed count is the names with no unended request: the one that ended and the one never asked" \
  "2" "$OW_N"
expect_eq "OW.4 the count over a 2,000-request store forks no grep (the budget, by fork count)" "0" "$OW_GREPS"
expect_true "OW.5 …and takes at most one wall second (the budget, by time)" test "$((OW_T1 - OW_T0))" -le 1
OW_ASKED="$( . "$GATE_LIB" 2>/dev/null; owed_names | gate_asked | tr '\n' ' ' )"
expect_eq "OW.6 gate_asked on stdin prints exactly the names with an unended request, in the order given" \
  "$(for i in 1 2 3 4 5 6; do printf '%s:w%s ' "$WORLD_SID" "$i"; done)" "$OW_ASKED"
expect_eq "OW.7 …rc 0 when any is showing" "0" \
  "$( . "$GATE_LIB" 2>/dev/null; printf '%s\n' "$WORLD_SID:w1" | gate_asked >/dev/null; echo $? )"
expect_eq "OW.8 …and rc 1, nothing printed, when none is" "|1" \
  "$( . "$GATE_LIB" 2>/dev/null; o="$(printf '%s\n' "$WORLD_SID:wNever" | gate_asked)"; echo "$o|$?" )"
fresh owed-empty
mkdir -p "$BIONIC_GATE_DIR/requests"
expect_eq "OW.9 an empty store prints nothing and answers rc 1" "|1" \
  "$( . "$GATE_LIB" 2>/dev/null; o="$(printf '%s\n' "$WORLD_SID:w1" | gate_asked)"; echo "$o|$?" )"
# The mutant: the per-file grep walk, one fork per request file per name, put back over the same
# verb. A smaller store keeps its run short; the fork count is what the budget row reads.
fresh owed-mutant
world_machine 8 8192 30 1.0
plant_ended_many 150 "$WORLD_SID:e" 900
plant_ended 99999 "$WORLD_SID:wEnded" 900
for i in 1 2 3 4 5 6; do plant_open "$i" "$WORLD_SID:w$i"; done
OM="$(mutant owed)"
anchor "$OM" 'gate_asked() {' 1
cat >> "$OM" <<'MUTANT'
gate_asked() {  # the old walk: one grep per request file per name
  local nm f hit=1
  _GD="$(gate_dir)"
  while IFS= read -r nm; do
    for f in "$_GD"/requests/[0-9]*; do
      grep -qxF "who=$nm" "$f" 2>/dev/null && { printf '%s\n' "$nm"; hit=0; break; }
    done
  done
  return $hit
}
MUTANT
OWM_N="$(owed_count "$OM")"
OWM_GREPS="$(wc -l < "$WORLD_ROOT/owed-greps" | tr -d ' ')"
expect_eq "OW.10 the mutant runs, and still counts the ended request as asked: the old walk's answer" "1" "$OWM_N"
expect_true "OW.11 …and it forks a grep per file per name, which OW.4's fork count reads red" \
  test "$OWM_GREPS" -ge 300

# The prune: an ended request older than BIONIC_GATE_KEEP goes at the next scan; a younger one,
# every unended one and the cost records stay.
fresh owed-prune
world_machine 8 8192 30 1.0
world_clock 100000
world_cost k 30
plant_ended 7 "$WORLD_SID:old" 13000
plant_ended 9 "$WORLD_SID:young" 14000
plant_open 8 "$WORLD_SID:waiting"
expect_eq "OW.12 the planted store reads: two ended requests and an unended one (positive)" \
  "$WORLD_SID:old $WORLD_SID:waiting $WORLD_SID:young" "$(field 7 who) $(field 8 who) $(field 9 who)"
state >/dev/null
expect_eq "OW.13 the default bound is a day: an ended request 87000 s old is gone" "gone" "$(gone_or_kept 7)"
expect_eq "OW.14 …one 86000 s old stays (positive: it is read)" "$WORLD_SID:young" "$(field 9 who)"
expect_eq "OW.15 …an unended request stays, however old" "$WORLD_SID:waiting" "$(field 8 who)"
expect_eq "OW.16 …and the duration record stays" "$(basename "$(costf k)")" "$(ls "$BIONIC_GATE_DIR/cost")"
BIONIC_GATE_KEEP=500 state >/dev/null
expect_eq "OW.17 BIONIC_GATE_KEEP=500 removes the one 86000 s old as well" "gone" "$(gone_or_kept 9)"
expect_eq "OW.18 …and still the unended one and the duration record stay" "$WORLD_SID:waiting $(basename "$(costf k)")" \
  "$(field 8 who) $(ls "$BIONIC_GATE_DIR/cost")"
fresh owed-keep-young
world_machine 8 8192 30 1.0
world_clock 100000
plant_ended 9 "$WORLD_SID:y" 99900
BIONIC_GATE_KEEP=500 state >/dev/null
expect_eq "OW.19 an ended request younger than the bound stays" "$WORLD_SID:y" "$(field 9 who)"

# gate_room reads the figure the admission test reads: gate_usage, not the raw reading.
fresh owed-usage
world_machine 8 8192 50 1.0
world_cost k 30
HOLD=1 ask_bg ou1 work k 0; wait_for 20 has ou1.rc
# The gate promises no memory (wave-33 T1; Δ10), so the figure above the raw reading is the idle
# floor: idle planted at 90 while one run is admitted and the reading is 50.
printf '90\n' > "$BIONIC_GATE_DIR/idle"
expect_eq "OW.20 the run is admitted (positive), idle 90 over the reading 50: used=90" \
  "0|share=80 used=90" "$(rc_of ou1)|$(state | cut -d' ' -f1,2)"
expect_eq "OW.21 used=90 over a share of 80, the raw reading 50: no room" \
  "room=no load=1.0/1.0 cores=8 promised=1 waiting=0 rc=1" "$(room)"
release ou1

# ── §OPEN ────────────────────────────────────────────────────────────────────
# (wave-28 T71, a fixit on T52; REQ-2, D10–D12.) "Which requests are open" is ONE rule, the
# live-holder rule `_gate_open` carries, and the scan, gate_list, gate_asked and the prune all
# read it. gate_asked reads the store with no exec-argument list and tolerates a request pruned
# mid-read; the prune removes in one batch and reads every number as decimal.
section "§OPEN — one rule says which requests are open; gate_asked and the prune survive growth (T71)"
plant_live() {  # <id> <who> [asked] — a request nothing has ended whose holder lives (this shell)
  mkdir -p "$BIONIC_GATE_DIR/requests"
  printf 'key=k\nkind=work\nwho=%s\ntree=/t\nasked=%s\nholder=%s:\n' "$2" "${3:-900}" "$$" \
    > "$BIONIC_GATE_DIR/requests/$1"
}
plant_gone() {  # <id> <who> <asked> — never admitted, nobody holds it (a 75's, or its holder died)
  mkdir -p "$BIONIC_GATE_DIR/requests"
  printf 'key=k\nkind=work\nwho=%s\ntree=/t\nasked=%s\nholder=-\n' "$2" "$3" > "$BIONIC_GATE_DIR/requests/$1"
}
plant_dying() {  # <id> <who> <asked> <dead pid> — admitted, never ended, its holder dead
  mkdir -p "$BIONIC_GATE_DIR/requests"
  printf 'key=k\nkind=work\nwho=%s\ntree=/t\nasked=%s\nholder=%s:\nadmitted=%s\npromise=5:1:30\n' \
    "$2" "$3" "$4" "$(( $3 + 10 ))" > "$BIONIC_GATE_DIR/requests/$1"
}
plant_raw() {  # <id> <who> <ended text, as written> — an ended request whose number is typed as given
  mkdir -p "$BIONIC_GATE_DIR/requests"
  printf 'key=k\nkind=work\nwho=%s\ntree=/t\nasked=1\nholder=-\nadmitted=2\npromise=5:1:30\nended=%s\nrc=0\n' \
    "$2" "$3" > "$BIONIC_GATE_DIR/requests/$1"
}
dead_pid() { local p; sleep 0 & p=$!; wait "$p" 2>/dev/null; printf '%s' "$p"; }
cpu_ms() {  # <cmd…> — the user and system CPU of the command and every child it waited for, in ms
  local t
  t="$( { TIMEFORMAT='%U %S'; time "$@" >/dev/null 2>&1; } 2>&1 )"
  awk -v t="$t" 'BEGIN { split(t, a, " "); printf "%d", (a[1] + a[2]) * 1000 }'
}
yn() { case "$1" in *"$2"*) echo yes ;; *) echo no ;; esac; }  # <haystack> <needle>
ga() {  # <names…> — gate_asked over the names in the order given: "<printed, space-joined>|<rc>"
  ( . "${GA_LIB:-$GATE_LIB}" 2>/dev/null
    o="$(printf '%s\n' "$@" | gate_asked 2>/dev/null)"; r=$?
    [ -z "$o" ] || o="${o//$'\n'/ } "
    printf '%s|%s' "$o" "$r" )
}
op_stub="$WORLD_ROOT/op-stub"
mkdir -p "$op_stub/awk-dir" "$op_stub/rm-dir"
# an awk that first removes the file $VANISH (the request pruned between the list and the read)
printf '#!/bin/sh\n[ -z "$VANISH" ] || /bin/rm -f "$VANISH"\nexec "%s" "$@"\n' "$(command -v awk)" > "$op_stub/awk-dir/awk"
# an rm that counts its own execs
printf '#!/bin/sh\necho x >> "%s"\nexec /bin/rm "$@"\n' "$WORLD_ROOT/op-rms" > "$op_stub/rm-dir/rm"
chmod +x "$op_stub/awk-dir/awk" "$op_stub/rm-dir/rm"

# One rule, six states. 1 waiting and 2 admitted (holders live), 3 ended, 4 ended by a kill,
# 5 never admitted with nobody holding it, 6 admitted and its holder dead, never ended.
fresh open-agree
world_machine 8 8192 30 1.0
world_clock 100000
OP_DEAD="$(dead_pid)"
plant_live 1 "op:w1" 99000
printf 'key=k\nkind=work\nwho=op:w2\ntree=/t\nasked=99000\nholder=%s:\nadmitted=99010\npromise=5:1:30\n' "$$" \
  > "$BIONIC_GATE_DIR/requests/2"
plant_ended 3 "op:w3" 99500
plant_ended 4 "op:w4" 99500; printf 'rc=137\n' >> "$BIONIC_GATE_DIR/requests/4"
plant_gone 5 "op:w5" 99000
plant_dying 6 "op:w6" 99000 "$OP_DEAD"
expect_eq "OP.1 the six planted states read as the list names them (positive: the readings below are not empty)" \
  "1 waiting|2 admitted|3 ended|4 killed|5 gone|6 killed" \
  "$(glist | awk '{ printf "%s%s %s", (n++ ? "|" : ""), $1, $2 }')"
expect_eq "OP.2 gate_asked names the two whose request is open, and no other" "op:w1 op:w2 |0" \
  "$(ga op:w1 op:w2 op:w3 op:w4 op:w5 op:w6)"
state > "$D/op-state"
expect_contains "OP.3 the scan tallies the same two: one admitted, one waiting" "admitted=1 waiting=1 " "$(cat "$D/op-state")"
expect_eq "OP.4 …and wrote the sixth's end (rc 137) while it was at it" "137" "$(field 6 rc)"

# The pre-filter in gate_asked reads the LAST ended= line, as _gate_read does: a later empty
# ended= takes the end back, so a request the rule calls open is named, not skipped.
fresh open-reread
world_machine 8 8192 30 1.0
world_clock 100000
plant_live 1 "op:w1" 99000
printf 'ended=5\nended=\n' >> "$BIONIC_GATE_DIR/requests/1"
expect_eq "OP.4b a later empty ended= line leaves the request open: the list calls it waiting (positive)" "1 waiting" \
  "$(glist | awk '{ printf "%s %s", $1, $2 }')"
expect_eq "OP.4c …and gate_asked, reading the last ended= as the rule does, names it" "op:w1 |0" "$(ga op:w1)"

# A run is killed when it ended with an exit over 128 (D18): a signal's 128+n, 143 from the rollover kills
# and 137 from signal 9 alike. 128 itself and 0 are exits, not kills.
fresh open-killed-rc
world_machine 8 8192 30 1.0
world_clock 100000
plant_ended 1 "op:r143" 99500; printf 'rc=143\n' >> "$BIONIC_GATE_DIR/requests/1"
plant_ended 2 "op:r128" 99500; printf 'rc=128\n' >> "$BIONIC_GATE_DIR/requests/2"
plant_ended 3 "op:r0" 99500
plant_ended 4 "op:r137" 99500; printf 'rc=137\n' >> "$BIONIC_GATE_DIR/requests/4"
OP_KRC='1 killed|2 ended|3 ended|4 killed'
expect_eq "OP.4d gate_list names an ended request with rc 143 killed, as it does one with rc 137; 128 and 0 stay ended" \
  "$OP_KRC" "$(glist | awk '{ printf "%s%s %s", (n++ ? "|" : ""), $1, $2 }')"

# A request nobody holds is not showing, and goes after BIONIC_GATE_KEEP like an ended one.
fresh open-gone
world_machine 8 8192 30 1.0
world_clock 100000
OP_DEAD="$(dead_pid)"
plant_gone 11 "op:g11" 13000
plant_gone 12 "op:g12" 14000
plant_live 13 "op:g13" 10
plant_dying 14 "op:g14" 50 "$OP_DEAD"
expect_eq "OP.5 holder-gone requests are not showing; the live one is (positive in the same call)" "op:g13 |0" \
  "$(ga op:g11 op:g12 op:g13 op:g14)"
state >/dev/null
expect_eq "OP.6 a never-admitted request 87000 s past its asked is pruned" "gone" "$(gone_or_kept 11)"
expect_eq "OP.7 …one 86000 s past stays (it is read), and so does the live waiter however old" \
  "op:g12 op:g13" "$(field 12 who) $(field 13 who)"
expect_eq "OP.8 a request killed unseen is written ended now and kept by the same rule" "100000|137" \
  "$(field 14 ended)|$(field 14 rc)"
world_clock 186500
state >/dev/null
expect_eq "OP.9 86500 s on, that one goes too (its age counts from the end written)" "gone" "$(gone_or_kept 14)"
expect_eq "OP.10 …and the live waiter stays, a day and more old" "op:g13" "$(field 13 who)"
fresh open-readonly
world_machine 8 8192 30 1.0
world_clock 100000
plant_ended 5 "op:old" 13000
plant_gone 6 "op:gone" 13000
glist >/dev/null; ga op:old op:gone >/dev/null
expect_eq "OP.11 gate_list and gate_asked only read: an expired ended and an expired gone request stay" "kept kept" \
  "$(gone_or_kept 5) $(gone_or_kept 6)"
state >/dev/null
expect_eq "OP.12 …and the next scan, which prunes, takes both" "gone gone" "$(gone_or_kept 5) $(gone_or_kept 6)"
fresh open-number
world_machine 8 8192 30 1.0
world_clock 100000
plant_ended 9 "op:old" 13000
state >/dev/null
expect_eq "OP.13 the pruned store is empty (positive for the row below)" "0" "$(nreq)"
expect_eq "OP.14 a request number is the highest present plus one: after a prune the next ask holds 1, not 10" "0 1" \
  "$(ask_fg n1 work k 0) $(id_of n1)"

# ARG_MAX: 20,000 request files, empty (planted by one awk), and one open request among them.
fresh open-20k
world_machine 8 8192 30 1.0
mkdir -p "$BIONIC_GATE_DIR/requests"
awk -v d="$BIONIC_GATE_DIR/requests" 'BEGIN { for (i = 1; i <= 20000; i++) { f = d "/" (100000 + i); printf "" > f; close(f) } }'
plant_live 1 "op:w1"
expect_eq "OP.15 the store holds 20,001 request files (positive)" "20001" "$(nreq)"
expect_eq "OP.16 gate_asked over 20,001 files names the one open writer and answers rc 0" "op:w1 |0" \
  "$(ga op:w1 op:wNever)"
OP_CPU="$(cpu_ms ga op:w1 op:wNever)"
echo "      measured: gate_asked over 20,001 files, $OP_CPU ms of CPU"
expect_true "OP.17 …on under 5 s of CPU, half the Stop wall's 10" test "$OP_CPU" -lt 5000
mkdir "$BIONIC_GATE_DIR/lock"; printf '%s\n' "$$" > "$BIONIC_GATE_DIR/lock/pid"
expect_eq "OP.18 …and with the lock held by another it takes no lock: the same answer" "op:w1 |0" "$(ga op:w1 op:wNever)"
rm -rf "$BIONIC_GATE_DIR/lock"
find "$BIONIC_GATE_DIR/requests" -name '1[0-9][0-9][0-9][0-9][0-9]' -delete

# A request pruned between the list and the read: the other names are still answered.
fresh open-vanish
world_machine 8 8192 30 1.0
plant_live 1 "op:w1"; plant_live 2 "op:w2"; plant_live 3 "op:w3"
expect_eq "OP.19 with all three requests present, all three names are answered (positive)" \
  "op:w1 op:w2 op:w3 |0" "$(ga op:w1 op:w2 op:w3)"
OP_V="$( VANISH="$BIONIC_GATE_DIR/requests/3" PATH="$op_stub/awk-dir:$PATH" ga op:w1 op:w2 op:w3 )"
expect_eq "OP.20 request 3 removed after the list, before the read: the other two are still named, rc 0" \
  "op:w1 op:w2 |0" "$OP_V"
expect_eq "OP.21 …and the stub did remove it (the row is not vacuous)" "gone" "$(gone_or_kept 3)"

# The prune is one batch: 2,000 expired requests removed inside gate_room fork no rm per file.
fresh open-prune2k
world_machine 8 8192 30 1.0
world_clock 100000
plant_ended_many 2000 "op:e" 900
expect_eq "OP.22 2,000 expired requests are planted (positive)" "2000" "$(nreq)"
op_room() { ( . "${1:-$GATE_LIB}" 2>/dev/null; gate_room ); }
OP_CPU="$(cpu_ms op_room)"
expect_eq "OP.22b gate_room, timed, pruned them all (positive for the timing row)" "0" "$(nreq)"
plant_ended_many 2000 "op:e" 900
: > "$WORLD_ROOT/op-rms"
OP_R="$( . "$GATE_LIB" 2>/dev/null; PATH="$op_stub/rm-dir:$PATH" gate_room 2>&1 )"
expect_contains "OP.23 gate_room answers (positive)" "room=yes" "$OP_R"
expect_eq "OP.24 …every expired request is gone" "0" "$(nreq)"
expect_true "OP.25 …removed by at most 5 rm execs, never one per file" \
  test "$(wc -l < "$WORLD_ROOT/op-rms" | tr -d ' ')" -le 5
echo "      measured: gate_room pruning 2,000 expired requests, $OP_CPU ms of CPU"
expect_true "OP.26 …and the run before it took under 2 s of CPU (about 0.8 s; an rm per file is over 4 s)" \
  test "$OP_CPU" -lt 2000

# Every number read as decimal; a non-number refused to the default with one stderr line; the lock freed.
fresh open-decimal
world_machine 8 8192 30 1.0
world_clock 1000
plant_raw 1 "op:d" "008"
plant_raw 2 "op:d" "010"
op_run() {  # <knob value or -> — gate_state, then gate_room, in one child: "rc=<n> lock=<held|free>"; stderr to op-err
  ( . "$GATE_LIB" 2>/dev/null
    if [ "$1" != - ]; then export BIONIC_GATE_KEEP="$1"; fi
    gate_state >/dev/null 2>"$D/op-err"; r1=$?
    gate_room >/dev/null 2>>"$D/op-err"
    printf 'rc=%s' "$r1" )
  [ -d "$BIONIC_GATE_DIR/lock" ] && echo ' lock=held' || echo ' lock=free'
}
expect_eq "OP.27 ended=008 and ended=010 (not octal) in the store: the scan finishes, rc 0, the lock is freed" \
  "rc=0 lock=free" "$(op_run - | tr '\n' ' ' | sed 's/ $//')"
expect_eq "OP.28 …they read as 8 and 10 — 992 s old, kept — and nothing was said" "2 0" \
  "$(nreq) $(wc -l < "$D/op-err" | tr -d ' ')"
rm -rf "$BIONIC_GATE_DIR/lock"
fresh open-keep
world_machine 8 8192 30 1.0
world_clock 100000
plant_ended 1 "op:k1" 50000
plant_ended 2 "op:k2" 13000
expect_eq "OP.29 BIONIC_GATE_KEEP=abc: the scan finishes, rc 0, the lock is freed" "rc=0 lock=free" \
  "$(op_run abc | tr '\n' ' ' | sed 's/ $//')"
expect_eq "OP.30 …the default day applies: the 50,000 s request stays, the 87,000 s one goes" "kept gone" \
  "$(gone_or_kept 1) $(gone_or_kept 2)"
expect_eq "OP.31 …and the refusal is one stderr line (two scans ran in the process), naming the knob" \
  "1 gate: BIONIC_GATE_KEEP='abc'" "$(wc -l < "$D/op-err" | tr -d ' ') $(head -c 28 "$D/op-err")"
expect_true "OP.32 …of at most 100 columns" test "$(awk '{ if (length($0) > m) m = length($0) } END { print m + 0 }' "$D/op-err")" -le 100
plant_ended 2 "op:k2" 13000
rm -rf "$BIONIC_GATE_DIR/lock"
expect_eq "OP.33 a 20-digit BIONIC_GATE_KEEP is no number either: default used, 50,000 s old stays, the 87,000 s one goes" \
  "rc=0 lock=free kept gone" "$(op_run 99999999999999999999 | tr '\n' ' ' | sed 's/ $//') $(gone_or_kept 1) $(gone_or_kept 2)"
expect_eq "OP.34 …and says so on one stderr line" "1" "$(wc -l < "$D/op-err" | tr -d ' ')"
rm -rf "$BIONIC_GATE_DIR/lock"
plant_ended 2 "op:k2" 13000
expect_eq "OP.35 BIONIC_GATE_KEEP=0500 reads as 500: both go, nothing said" "rc=0 lock=free gone gone 0" \
  "$(op_run 0500 | tr '\n' ' ' | sed 's/ $//') $(gone_or_kept 1) $(gone_or_kept 2) $(wc -l < "$D/op-err" | tr -d ' ')"
rm -rf "$BIONIC_GATE_DIR/lock"

# The mutants: each rule put back by itself on a copy of the library, proved to run, and read red.
# (1) the rule split again — open means "no ended= line" and nothing more, as gate_asked's awk once
# spelled it.
fresh open-mut-split
world_machine 8 8192 30 1.0
world_clock 100000
plant_gone 11 "op:g11" 13000
plant_live 13 "op:g13" 10
MS="$(mutant open-split)"
anchor "$MS" 'elif _gate_alive; then' 1
sed -i.bak 's/elif _gate_alive; then/elif true; then/' "$MS"
expect_eq "OP.M1 the mutant (open = no ended= line) still names the live waiter (it runs)" "yes" \
  "$(yn "$(GA_LIB="$MS" ga op:g11 op:g13)" op:g13)"
expect_eq "OP.M2 …and names the holder-gone writer too, which OP.5 reads red: the live-holder rule is the row" \
  "op:g11 op:g13 |0" "$(GA_LIB="$MS" ga op:g11 op:g13)"
# (2) the exec-argument list put back: every request path to one awk, as T52 shipped it.
fresh open-mut-exec
world_machine 8 8192 30 1.0
plant_live 1 "op:w1"; plant_live 2 "op:w2"
ME="$(mutant open-exec)"
anchor "$ME" 'gate_asked() {' 1
cat >> "$ME" <<'MUTANT'
gate_asked() {  # T52's: every request path in one awk's argument list
  _GD="$(gate_dir)"
  set -- "$_GD"/requests/[0-9]*
  [ -e "$1" ] || { cat >/dev/null; return 1; }
  awk '
    FILENAME == "-" { if ($0 != "") { n++; name[n] = $0 }; next }
    FNR == 1 { flush() }
    /^who=/ { w = substr($0, 5); next }
    /^ended=/ { ended = 1 }
    function flush() { if (w != "" && !ended) open[w] = 1; w = ""; ended = 0 }
    END {
      flush()
      for (i = 1; i <= n; i++) if (name[i] in open) { print name[i]; hit = 1 }
      exit !hit
    }' - "$@" 2>/dev/null
}
MUTANT
expect_eq "OP.M3 the mutant (exec list) answers a small store: it runs" "op:w1 op:w2 |0" "$(GA_LIB="$ME" ga op:w1 op:w2)"
mkdir -p "$BIONIC_GATE_DIR/requests"
awk -v d="$BIONIC_GATE_DIR/requests" 'BEGIN { for (i = 1; i <= 20000; i++) { f = d "/" (100000 + i); printf "" > f; close(f) } }'
expect_eq "OP.M4 …and over 20,002 files it answers nothing — OP.16 reads red" "|126" "$(GA_LIB="$ME" ga op:w1 op:w2)"
expect_eq "OP.M5 …where the shipped rule answers (OP.16's positive on the same store)" "op:w1 op:w2 |0" "$(ga op:w1 op:w2)"
find "$BIONIC_GATE_DIR/requests" -name '1[0-9][0-9][0-9][0-9][0-9]' -delete
# (3) one rm per file put back.
fresh open-mut-rm
world_machine 8 8192 30 1.0
world_clock 100000
plant_ended_many 2000 "op:e" 900
MR2="$(mutant open-rm)"
anchor "$MR2" '|| old[${#old[@]}]="$f"' 1
sed -i.bak '/|| old\[\${#old\[@\]}\]="\$f"/c\
      [ "$((now - born))" -le "$keep" ] || rm -f "$f"' "$MR2"
: > "$WORLD_ROOT/op-rms"
OP_CPU="$(PATH="$op_stub/rm-dir:$PATH" cpu_ms op_room "$MR2")"
echo "      measured: the mutant pruning 2,000 expired requests, $OP_CPU ms of CPU"
expect_eq "OP.M6 the mutant (rm per file) still prunes all 2,000 (it runs)" "0" "$(nreq)"
expect_true "OP.M7 …forking an rm each, which OP.25's bound reads red" \
  test "$(wc -l < "$WORLD_ROOT/op-rms" | tr -d ' ')" -ge 2000
expect_true "OP.M7b …and costing over 2 s of CPU, which OP.26's bound reads red" test "$OP_CPU" -ge 2000
# (4) the decimal read taken out.
fresh open-mut-dec
world_machine 8 8192 30 1.0
world_clock 100000
plant_raw 1 "op:d" "99000"
MD="$(mutant open-dec)"
anchor "$MD" '_G_NUM=$((10#$1))' 1
sed -i.bak 's/10#\$1/$1/' "$MD"
expect_eq "OP.M8 the mutant (no 10#) reads an ordinary ended= and finishes (it runs)" "rc=0 lock=free" \
  "$(GATE_LIB="$MD" op_run - | tr '\n' ' ' | sed 's/ $//')"
plant_raw 2 "op:d" "008"
expect_eq "OP.M9 …and with ended=008 it aborts under the lock, which OP.27 reads red" " lock=held" \
  "$(GATE_LIB="$MD" op_run - | tr '\n' ' ' | sed 's/ $//')"
rm -rf "$BIONIC_GATE_DIR/lock"
# (5) the killed rule back to 137 only, as _gate_open once spelled it.
fresh open-mut-137
world_machine 8 8192 30 1.0
world_clock 100000
plant_ended 1 "op:r143" 99500; printf 'rc=143\n' >> "$BIONIC_GATE_DIR/requests/1"
plant_ended 4 "op:r137" 99500; printf 'rc=137\n' >> "$BIONIC_GATE_DIR/requests/4"
M137="$(mutant open-137)"
anchor "$M137" '[ "$_G_NUM" -gt 128 ]' 1
sed -i.bak 's/\[ "\$_G_NUM" -gt 128 \]/[ "$_G_NUM" -eq 137 ]/' "$M137"
expect_eq "OP.M10 the mutant (killed is rc 137 only) still names the rc 137 request killed (it runs)" "4 killed" \
  "$(GATE_LIB="$M137" glist | awk '$2 == "killed" { print $1 " " $2 }')"
expect_eq "OP.M11 …and reads the rc 143 request ended, which OP.4d reads red: the over-128 rule is the row" "1 ended" \
  "$(GATE_LIB="$M137" glist | awk '$1 == 1 { print $1 " " $2 }')"

# ── §REAPED ──────────────────────────────────────────────────────────────────
section "§REAPED — a killed request is written ended once it is seen dead (T47)"
# learn_run <gate lib> <name> <kill 0|1> — with kill=1 a run of key x is admitted and killed with
# signal 9, and the clock moves a minute. Then a run of key L is admitted, a gate_state is taken
# mid-run, and it ends 30 s later. Sets LR_LINE (cost/L's newest line), LR_KID (the killed
# request's id) and LR_LIST (gate_list after the run). The gate learns only durations (wave-33
# T1; Δ10), so what the killed-write is seen by is the killed request's own end.
learn_run() {
  local kp
  fresh "$2"
  world_machine 8 8192 30 1.0
  world_cost L 30
  world_cost x 30
  LR_KID=''
  if [ "$3" = 1 ]; then
    GATE_LIB="$1" HOLD=1 ask_bg rx work x 0; wait_for 20 has rx.rc
    LR_KID="$(id_of rx)"; kp="$(cat "$D/rx.pid")"
    kill -KILL "$kp"; wait_for 20 dead "$kp"
    world_tick 60
  fi
  GATE_LIB="$1" HOLD=1 ask_bg r1 work L 0; wait_for 20 has r1.rc
  GATE_LIB="$1" BIONIC_PROBE_USED_PCT=70 state >/dev/null
  world_tick 30
  release r1
  LR_LINE="$(tail -n 1 "$(costf L)" 2>/dev/null)"
  LR_LIST="$(GATE_LIB="$1" glist)"
}
learn_run "$GATE" reaped-control 0
expect_eq "R.1 control, nothing killed: the run learns its 30 s" "30:1030" "$LR_LINE"
learn_run "$GATE" reaped 1
expect_eq "R.2 the killed run was admitted, and gate_list lists it killed" "0 1" \
  "$(rc_of rx) $(printf '%s\n' "$LR_LIST" | grep -c "^${LR_KID:-none} killed ")"
expect_eq "R.3 a run after it learns its own 30 s" "30:1090" "$LR_LINE"
expect_eq "R.4 the next locked act (that run's admission at 1060) wrote it ended, rc 137" "1060|137" \
  "$(field "$LR_KID" ended)|$(field "$LR_KID" rc)"
expect_eq "R.5 and it wrote no duration: cost/x holds its one planted line" "1" \
  "$(wc -l < "$(costf x)" | tr -d ' ')"
fresh reaped-during
world_machine 8 8192 30 1.0
world_cost L 30
world_cost x 30
HOLD=1 ask_bg r1 work L 0; wait_for 20 has r1.rc
world_tick 5
HOLD=1 ask_bg rx work x 0; wait_for 20 has rx.rc
rx_id="$(id_of rx)"; rx_pid="$(cat "$D/rx.pid")"
BIONIC_PROBE_USED_PCT=70 state >/dev/null
kill -KILL "$rx_pid"; wait_for 20 dead "$rx_pid"
world_tick 25
release r1
expect_eq "R.6 two runs admitted, the second five seconds into the first" "0 0" "$(rc_of r1) $(rc_of rx)"
expect_eq "R.7 one killed while the other ran: the survivor records its own 30 s" \
  "30:1030" "$(tail -n 1 "$(costf L)")"
expect_eq "R.8 the survivor's gate_end wrote the killed one ended at 1030, rc 137" "1030|137" \
  "$(field "$rx_id" ended)|$(field "$rx_id" rc)"
expect_eq "R.9 gate_list still counts it killed, once" "1" "$(glist | grep -c "^${rx_id:-none} killed ")"
MR="$(mutant reap)"
anchor "$MR" "rc=137\\n'" 1
sed -i.bak "/rc=137\\\\n'/d" "$MR"
learn_run "$MR" reaped-mut 1
expect_eq "R.10 the mutant (no killed-write) still admits both runs and ends the second" \
  "0 30:1090" "$(rc_of rx) $LR_LINE"
expect_eq "R.11 the mutant leaves the killed request admitted and never ended (admitted|ended|rc): the written end is the rule" \
  "1000||" "$(field "$LR_KID" admitted)|$(field "$LR_KID" ended)|$(field "$LR_KID" rc)"

# ── §ALONE ───────────────────────────────────────────────────────────────────
# THE READING IS THE MEMORY LIMIT (T47; usage row; wave-33 T1, Δ10). A request promises no
# memory, so nothing it promises refuses it: an idle gate admits a big run while the reading is
# at most the share, and a small ask behind it is admitted beside it. A reading over the share
# still refuses. (T47's idle clause, which spared an idle gate a memory promise over the room,
# guarded a promise the gate no longer makes; it is gone with its mutant arm.)
section "§ALONE — the live reading is the memory limit; a promise holds no memory (T47; Δ10)"
# alone_rows <gate lib> <name> — reading 40, share 80. A big landing asks, then a small work ask
# behind it. Sets AL_BIG (big's rc), AL_WAIT (the small ask while big runs: waiting or served)
# and AL_SMALL (its rc at the end).
alone_rows() {
  fresh "$2"
  world_machine 8 8192 40 1.0
  world_cost big 60
  world_cost small 20
  GATE_LIB="$1" HOLD=1 ask_bg ib landing big 0; wait_for 20 has ib.rc
  AL_BIG="$(rc_of ib)"
  GATE_LIB="$1" HOLD=1 ask_bg is work small 600; wait_for 20 asked_by is
  sleep 0.3
  if has is.rc; then AL_WAIT=served; else AL_WAIT=waiting; fi
  [ "$AL_BIG" != 0 ] || release ib
  wait_for 20 has is.rc
  AL_SMALL="$(rc_of is)"
  touch "$D/is.go"
}
alone_rows "$GATE" alone
expect_eq "I.1 big alone on an idle gate (reading 40 under share 80): admitted" "0" "$AL_BIG"
expect_eq "I.2 the small ask behind it took a number at 1000" "1000" "$(field "$(req_of is)" asked)"
expect_eq "I.3 and is admitted while big runs: neither promises memory (40 ≤ 80)" "served" "$AL_WAIT"
expect_eq "I.4 the small ask's rc is 0" "0" "$AL_SMALL"
fresh alone-new
world_machine 8 8192 40 1.0
world_cost big 60
expect_eq "I.5 a never-seen key on an idle gate: admitted" "0" \
  "$(ask_fg in1 work never-seen 0)"
expect_eq "I.6 its promise is one core, no memory, no seconds" "0:1:0" "$(field "$(req_of in1)" promise)"
for rd in 80:0 81:75 85:75; do
  fresh "alone-${rd%%:*}"
  world_machine 8 8192 "${rd%%:*}" 1.0
  world_cost big 60
  expect_eq "I.7 an idle gate reading ${rd%%:*} under share 80: big gets rc ${rd#*:}" "${rd#*:}" \
    "$(ask_fg ir work big 0)"
done

# ── §OWN ─────────────────────────────────────────────────────────────────────
section "§OWN — a live waiter's number is never taken over (T47; request row)"
# own_rows <gate lib> <name> — share 15 on 8 cores, 1.2 cores, room for one command of one
# core (wave-33 T1; Δ10); reading 10, idle processor; a holder admitted (another who); two asks
# by one who (agent twin) for key k while the first still polls. Sets OW_N (requests then),
# OW_FIRST (the first ask's id), OW_STATE (gate_state with both waiting). The share is raised to
# 80 when the holder ends, so both waiters fit.
own_rows() {
  fresh "$2"
  printf '15\n' > "$CLAUDE_CONFIG_DIR/bionic/share"
  world_machine 8 8192 10 0
  world_cost h 20
  world_cost k 20
  GATE_LIB="$1" HOLD=1 ask_bg oh work h 0; wait_for 20 has oh.rc
  GATE_LIB="$1" AGENT=twin HOLD=1 ask_bg o1 work k 600; wait_for 20 asked_by twin
  OW_FIRST="$(req_of twin)"
  GATE_LIB="$1" AGENT=twin HOLD=1 ask_bg o2 work k 600; wait_for 20 has o2.pid
  wait_for 5 nreq_is 3 || wait_for 5 resumed "$OW_FIRST" o2
  OW_N="$(nreq)"
  OW_STATE="$(GATE_LIB="$1" state)"
}
own_rows "$GATE" own
expect_eq "O.1 the first ask by twin took number 2 at 1000" "2 1000" "$OW_FIRST $(field "$OW_FIRST" asked)"
expect_eq "O.2 a second ask by the same who for the same key, the first still polling, took a number of its own" \
  "3" "$OW_N"
expect_true "O.3 the first's request still names the first asker as its holder" resumed "$OW_FIRST" o1
expect_contains "O.4 gate_state counts both waiting" "admitted=1 waiting=2 " "$OW_STATE"
printf '80\n' > "$CLAUDE_CONFIG_DIR/bionic/share"
release oh
wait_for 20 has o1.rc; wait_for 20 has o2.rc
expect_eq "O.5 once the holder ends and the share is 80, both are served (1 + 1 ≤ 6.4)" "0 0" "$(rc_of o1) $(rc_of o2)"
expect_eq "O.6 each under its own number" "2 3" "$(id_of o1) $(id_of o2)"
expect_contains "O.7 gate_state then counts both admitted, none waiting" "admitted=2 waiting=0 " "$(state)"
touch "$D/o1.go" "$D/o2.go"
fresh own-gave-up
printf '15\n' > "$CLAUDE_CONFIG_DIR/bionic/share"
world_machine 8 8192 10 0
world_cost h 20
world_cost k 20
HOLD=1 ask_bg sh work h 0; wait_for 20 has sh.rc
AGENT=twin HOLD=1 ask_bg s1 work k 600; wait_for 20 asked_by twin
s1_id="$(req_of twin)"
expect_eq "O.8 a second ask by twin that gives up returns 75" "75" "$(AGENT=twin ask_fg s2 work k 0)"
expect_true "O.9 the first's request still names the first asker" resumed "$s1_id" s1
release sh
wait_for 20 has s1.rc
expect_eq "O.10 the machine empty, the first waiter is served under its number" "0 ${s1_id:-none}" \
  "$(rc_of s1) $(id_of s1)"
touch "$D/s1.go"
MO="$(mutant own)"
anchor "$MO" '&& [ "$_R_key" = "$2" ] && ! _gate_alive; then' 1
sed -i.bak 's/ \&\& ! _gate_alive; then$/; then/' "$MO"
own_rows "$MO" own-mut
expect_eq "O.11 the mutant (no liveness test on reuse) still takes the first ask's number" "2" "$OW_FIRST"
expect_eq "O.12 the mutant hands the second ask the live waiter's number — the test is the rule" "2" "$OW_N"

# ── §CLEARED ─────────────────────────────────────────────────────────────────
section "§CLEARED — a request returned 75 is nobody's until its who asks again (T47; request row)"
# cleared_rows <gate lib> <name> — share 15 on 8 cores, room for one command (wave-33 T1; Δ10),
# reading 10; a holder admitted; a landing finds no room, returns 75, and its process lives on,
# polling nothing. Then the holder ends and a work ask comes. Sets CL_P (the landing's rc and
# liveness), CL_ID, CL_STATE (gate_state with the holder ended) and CL_Q (the work ask's rc).
cleared_rows() {
  local p
  fresh "$2"
  printf '15\n' > "$CLAUDE_CONFIG_DIR/bionic/share"
  world_machine 8 8192 10 0
  world_cost h 20
  world_cost a 20
  world_cost b 20
  GATE_LIB="$1" HOLD=1 ask_bg eh work h 0; wait_for 20 has eh.rc
  GATE_LIB="$1" LIVE=1 ask_bg ep landing a 0; wait_for 20 has ep.rc
  p="$(cat "$D/ep.pid")"
  CL_P="$(rc_of ep) $(if dead "$p"; then echo dead; else echo alive; fi)"
  CL_ID="$(req_of ep)"
  release eh
  CL_STATE="$(GATE_LIB="$1" state)"
  CL_Q="$(GATE_LIB="$1" ask_fg eq work b 0)"
}
cleared_rows "$GATE" cleared
expect_eq "E.1 the landing finds no room, returns 75, and its process lives on" "75 alive" "$CL_P"
expect_eq "E.2 its request is kept (asked 1000) and its holder cleared" "1000|-" \
  "$(field "$CL_ID" asked)|$(field "$CL_ID" holder)"
expect_contains "E.3 with the holder ended, gate_state counts nobody waiting" "admitted=0 waiting=0 " "$CL_STATE"
expect_eq "E.4 a later work ask is served" "0" "$CL_Q"
expect_eq "E.5 the same who asking again resumes the cleared number and is admitted" "0 ${CL_ID:-none} 3" \
  "$(AGENT=ep ask_fg ep2 landing a 0) $(id_of ep2) $(nreq)"
touch "$D/ep.go"
MC="$(mutant cleared)"
anchor "$MC" '_gate_holder "$id" -' 1
sed -i.bak '/_gate_holder "\$id" -/d' "$MC"
cleared_rows "$MC" cleared-mut
expect_eq "E.6 the mutant (no holder cleared) still returns 75 and the process lives on" "75 alive" "$CL_P"
expect_eq "E.7 the mutant lets the live non-polling landing keep the head — the clearing is the rule" \
  "75" "$CL_Q"
touch "$D/ep.go"

# ── §MACHINES ────────────────────────────────────────────────────────────────
section "§MACHINES — the gate is proved on other machines (AC-7.3)"
# The 2-core machine's share of 80 is 1.6 cores, less than two commands of one core each
# (wave-33 T1; Δ10): its third ask is refused too, so its row reads 0 75 75 75.
for m in "2 2048 0_75_75_75" "8 16384 0_75_0_75" "64 262144 0_75_0_75"; do
  set -- $m
  admissions "$1" "$2"
  expect_eq "M.1 the admission rows on a $1-core $2 MB machine: ${3//_/ }" "${3//_/ }" "$ADM"
  hard_rows "$1" "$2"
  expect_eq "M.2 the hard rows on a $1-core $2 MB machine: 75 0" "75 0" "$HRD"
done


# ── §WRAP ────────────────────────────────────────────────────────────────────
# THE WRAPPER ASKS THE GATE (T12; AC-2.6, AC-2.13, D10). payload/scripts/booked.sh, the shim
# the Bash wall wraps every suite in, asks `gate_ask work <key> --within <the call's limit>`,
# runs the command with BIONIC_GATE_ADMIT exported, ends the request with the command's code,
# and exits 75 with a line naming the command to run again when the gate did not admit it in
# time. Every end stamps. Each booked call here runs in a world repository (its stamp lands in
# that repository's git dir) through booker.sh, a real child that records the shim's rc.
BOOKED="$REPO_ROOT/payload/scripts/booked.sh"
export BOOKED_SH="$BOOKED"
cat > "$WORLD_ROOT/booker.sh" <<'BOOKER'
d="$1"; n="$2"; shift 2
cd "${WR:?}" || exit 1
bash "${BOOKED_SH:?}" "$@" >"$d/$n.out" 2>"$d/$n.err"; rc=$?
printf '%s\n' "$rc" > "$d/$n.brc.tmp" && mv "$d/$n.brc.tmp" "$d/$n.brc"
BOOKER
book_fg() {  # <name> <booked args...> — the shim in the foreground; prints its rc
  bash "$WORLD_ROOT/booker.sh" "$D" "$@"
  cat "$D/$1.brc" 2>/dev/null || echo none
}
book_bg() {  # <name> <booked args...> — the shim in the background
  bash "$WORLD_ROOT/booker.sh" "$D" "$@" >/dev/null 2>&1 &
  BG="$BG $!"
}
brc() { cat "$D/$1.brc" 2>/dev/null || echo none; }
stamp_last() { tail -n 1 "$(git -C "$WR" rev-parse --absolute-git-dir)/bionic-stamps" 2>/dev/null; }
hold_cmd() {  # <name> — a command that marks itself started and holds until <name>.go
  printf 'touch %q; i=0; while [ ! -f %q ] && [ $i -lt 600 ]; do i=$((i+1)); sleep 0.05; done' \
    "$D/$1.ran" "$D/$1.go"
}
WR="$(world_repo)"; export WR
section "§WRAP — the wrapper asks the gate; a wait ends 75 and keeps its number (T12; AC-2.6, AC-2.13)"
expect_true "B.0 the world repository the shim stamps exists" test -d "$WR/.git"

# A run: the command's own code, the request ended with it, the admission handed down, a stamp.
fresh wrap-run
world_machine 8 8192 40 1.0
world_cost k.test.sh 30
expect_eq "B.1 an admitted command runs, and the shim exits with the command's own code" "3" \
  "$(book_fg w1 --agent w1 --max-wait 30 --suites k.test.sh -- "printf '%s' \"\$BIONIC_GATE_ADMIT\" > '$D/w1.admit'; exit 3")"
w1_id="$(req_of w1)"
expect_eq "B.2 it asked as work, keyed by its suite's file name, and ended with rc 3" \
  "work k.test.sh 3" "$(field "$w1_id" kind) $(field "$w1_id" key) $(field "$w1_id" rc)"
expect_eq "B.3 who carries the agent name the wall passed (--agent)" \
  "$WORLD_SID:w1" "$(field "$w1_id" who)"
expect_eq "B.4 the command saw BIONIC_GATE_ADMIT naming its own request" "${w1_id:-none}" \
  "$(cat "$D/w1.admit" 2>/dev/null)"
expect_match "B.5 the stamp records rc 3 and the suite" "stamp/v1|head=*|rc=3|*|suites=k.test.sh|*" \
  "$(stamp_last)"
expect_eq "B.6 a command with no single suite is keyed by its first 60 characters" \
  "0 echo one two" "$(book_fg w2 --agent w2 --max-wait 30 -- 'echo one two') $(field "$(req_of w2)" key)"

# A wait that runs out: 75, nothing ran, the number kept, the line naming the command, a stamp.
# The room is the live processor's (wave-33 T1; Δ10): 6.0 busy cores of the 6.4 the share of 80
# allows, room for the holder alone.
fresh wrap-number
world_machine 8 8192 60 6.0
world_cost h 30
world_cost k.test.sh 30
HOLD=1 ask_bg nh work h 0; wait_for 20 has nh.rc
expect_eq "B.7 the holder is admitted (nothing else admitted)" "0" "$(rc_of nh)"
book_bg na --agent na --max-wait 3 --suites k.test.sh -- "$(hold_cmd na)"
wait_for 20 asked_by na
na_id="$(req_of na)"
na_h1="$(field "$na_id" holder)"
# Resumed: the request names a new, live holder (a 75 clears the holder since T47, so a cleared
# holder is not yet the second shim).
resumed_by_shim() {
  local h; h="$(field "$1" holder)"
  case "$h" in [0-9]*:*) [ "$h" != "$na_h1" ] && kill -0 "${h%%:*}" 2>/dev/null ;; *) return 1 ;; esac
}
sleep 0.3
expect_false "B.8 at 1000 of a 3-second wait the shim is still waiting" has na.brc
world_tick 3
wait_for 20 has na.brc
expect_eq "B.9 at 1003 the shim exits 75, not 124 or 69" "75" "$(brc na)"
expect_eq "B.10 nothing ran: the request was taken at 1000 and holds no admitted line" "1000|" \
  "$(field "$na_id" asked)|$(field "$na_id" admitted)"
expect_false "B.11 …and the command never started" has na.ran
expect_contains "B.12 its line says to run the command again" "run again" "$(cat "$D/na.err" 2>/dev/null)"
expect_contains "B.13 …naming the command" "$D/na.go" "$(cat "$D/na.err" 2>/dev/null)"
expect_match "B.14 the shim stamped the 75 with its suite" "stamp/v1|head=*|rc=75|*|suites=k.test.sh|*" \
  "$(stamp_last)"
book_bg nk --agent nk --kill-after 2 --suites k.test.sh -- "$(hold_cmd nk)"
wait_for 20 asked_by nk
world_tick 2
wait_for 20 has nk.brc
expect_eq "B.15 under --kill-after the wait ends 75 too, never 124" "75" "$(brc nk)"
expect_false "B.16 …and its command never started" has nk.ran
world_tick 5
book_bg nb --agent nb --max-wait 600 --suites k.test.sh -- "$(hold_cmd nb)"
wait_for 20 asked_by nb
expect_eq "B.17 a later number is taken at 1010" "1010" "$(field "$(req_of nb)" asked)"
rm -f "$D/na.brc"
book_bg na --agent na --max-wait 600 --suites k.test.sh -- "$(hold_cmd na)"
wait_for 20 resumed_by_shim "$na_id"
expect_eq "B.18 the shim's next call resumes the same number: no new request" "4" "$(nreq)"
release nh
wait_for 20 has na.ran
expect_true "B.19 when room appears the resumed number's command runs" has na.ran
sleep 0.3
expect_false "B.20 …before the later number's" has nb.ran
expect_eq "B.21 …admitted under the number first taken" "1000" "$(field "$na_id" asked)"
touch "$D/na.go"; wait_for 20 has na.brc
wait_for 20 has nb.ran
expect_true "B.22 once it ends, the later number runs" has nb.ran
touch "$D/nb.go"; wait_for 20 has nb.brc
expect_eq "B.23 both ended 0" "0 0" "$(brc na) $(brc nb)"

# Nesting: a shim inside an admitted command is believed, takes no number, and runs.
fresh wrap-nest
world_machine 8 8192 40 1.0
world_cost k.test.sh 30
expect_eq "B.24 a shim nested in an admitted command runs (both exit 0)" "0" \
  "$(book_fg np --agent np --max-wait 30 --suites k.test.sh -- \
      "bash '$BOOKED' --agent kid --max-wait 30 --suites j.test.sh -- 'touch $D/kid.ran'")"
expect_true "B.25 …its command ran" has kid.ran
expect_eq "B.26 …and it took no number of its own" "1" "$(nreq)"
expect_eq "B.27 the parent's request was ended once, by the parent" "0" "$(field "$(req_of np)" rc)"

# A typed admission from no ancestor, and BIONIC_SLOT_HELD=1, ask anyway.
stranger_rows() {  # <booked> <prefix> — sets ST_RC and ST_RAN for an unbooked caller with no room
  fresh "wrap-stranger-$2"
  world_machine 8 8192 60 6.0
  world_cost h 30
  world_cost k.test.sh 30
  HOLD=1 ask_bg sh work h 0; wait_for 20 has sh.rc
  BIONIC_GATE_ADMIT="$(id_of sh)" BOOKED_SH="$1" \
    book_bg st --agent st --max-wait 1 --suites k.test.sh -- "touch '$D/st.ran'"
  wait_for 20 asked_by st || wait_for 5 has st.brc
  world_tick 1
  wait_for 20 has st.brc
  ST_RC="$(brc st)"; ST_RAN=no; has st.ran && ST_RAN=yes
}
stranger_rows "$BOOKED" real
expect_eq "B.28 a stranger typing the holder's admission asks anyway, and with no room ends 75" "75" "$ST_RC"
expect_eq "B.29 …its command never ran" "no" "$ST_RAN"
fresh wrap-held
world_machine 8 8192 60 6.0
world_cost h 30
world_cost k.test.sh 30
HOLD=1 ask_bg hh work h 0; wait_for 20 has hh.rc
BIONIC_SLOT_HELD=1 book_bg sl --agent sl --max-wait 1 --suites k.test.sh -- "touch '$D/sl.ran'"
wait_for 20 asked_by sl
world_tick 1
wait_for 20 has sl.brc
expect_eq "B.30 BIONIC_SLOT_HELD=1 skips nothing: the shim asked, and with no room ends 75" "75" "$(brc sl)"
expect_false "B.31 …its command never ran" has sl.ran
MW_DIR="$MUT/wrap-believe"; mkdir -p "$MW_DIR"; cp -R "$REPO_ROOT/payload/scripts" "$MW_DIR/scripts"
anchor "$MW_DIR/scripts/booked.sh" '    booked_ask work' 1
sed -i.bak 's/^    booked_ask work$/    [ -n "${BIONIC_GATE_ADMIT:-}" ] || booked_ask work/' "$MW_DIR/scripts/booked.sh"
stranger_rows "$MW_DIR/scripts/booked.sh" mut
expect_eq "B.32 the mutant (believes a typed admission without asking) still ends: rc 0" "0" "$ST_RC"
expect_eq "B.33 …and runs the stranger's command: asking is the rule" "yes" "$ST_RAN"

# The wrapper exiting 0 on a gate timeout would read as a green run: the mutation arm.
MZ_DIR="$MUT/wrap-zero"; mkdir -p "$MZ_DIR"; cp -R "$REPO_ROOT/payload/scripts" "$MZ_DIR/scripts"
anchor "$MZ_DIR/scripts/booked.sh" 'exit "$BOOKED_WAITED_RC"' 1
sed -i.bak 's/exit "\$BOOKED_WAITED_RC"/exit 0/' "$MZ_DIR/scripts/booked.sh"
fresh wrap-zero
world_machine 8 8192 60 6.0
world_cost h 30
world_cost k.test.sh 30
HOLD=1 ask_bg zh work h 0; wait_for 20 has zh.rc
BOOKED_SH="$MZ_DIR/scripts/booked.sh" book_bg zz --agent zz --max-wait 1 --suites k.test.sh -- "touch '$D/zz.ran'"
wait_for 20 asked_by zz
world_tick 1
wait_for 20 has zz.brc
expect_false "B.34 the mutant (exits 0 on a timeout) still ran nothing" has zz.ran
expect_eq "B.35 …and exits 0, a wait read as a pass — B.9's 75 is the rule" "0" "$(brc zz)"

# Usage ends 2, asks nothing, stamps nothing.
fresh wrap-usage
world_machine 8 8192 40 1.0
WU_BEFORE="$(stamp_last)"
expect_eq "B.36 no -- is usage: rc 2" "2" "$(book_fg wu --agent wu --max-wait 30)"
expect_eq "B.37 …no request was taken" "0" "$(nreq)"
expect_eq "B.38 …and no stamp was written" "$WU_BEFORE" "$(stamp_last)"
expect_eq "B.39 an empty --agent is usage too" "2" "$(book_fg wv --agent '' --max-wait 30 -- 'true')"

# The runner holds nothing: its suites ask for themselves (tests/runner-roster.test.sh §ASK).
fresh wrap-runner
world_machine 8 8192 40 1.0
expect_eq "B.40 the runner (--suites run.sh) is run, not admitted" "0" \
  "$(book_fg rn --agent rn --max-wait 30 --suites run.sh -- 'exit 0')"
expect_eq "B.41 …it took no number: the runner holds nothing" "0" "$(nreq)"
expect_match "B.42 …and it still stamped" "stamp/v1|head=*|rc=0|*|suites=run.sh|*" "$(stamp_last)"

# A run nothing else polls is sampled by the wrapper while it runs (T2's sampling note). The
# memory reading is read live here, not from a pin: a stub `memory_pressure` (darwin) and a
# planted meminfo (linux) the row rewrites mid-run.
fresh wrap-sample
world_machine 8 8192 40 1.0
world_cost k.test.sh 30
mkdir -p "$D/stub" "$D/proc"
printf '#!/bin/sh\nu=$(cat "%s")\necho "System-wide memory free percentage: $((100 - u))%%"\n' "$D/used" \
  > "$D/stub/memory_pressure"
chmod +x "$D/stub/memory_pressure"
live_used() {  # <pct> — the live reading the stub and the planted meminfo give
  printf '%s\n' "$1" > "$D/used"
  printf 'MemTotal: 1000000 kB\nMemAvailable: %s kB\n' "$(( (100 - $1) * 10000 ))" > "$D/proc/meminfo"
}
live_used 40
( unset BIONIC_PROBE_USED_PCT BIONIC_PROBE_FREE_PCT
  PATH="$D/stub:$PATH" BIONIC_PROBE_PROC="$D/proc" \
    book_bg pk --agent pk --max-wait 30 --suites k.test.sh -- "$(hold_cmd pk)"
  wait ) &
BG="$BG $!"
wait_for 20 has pk.ran
pk_id="$(req_of pk)"
live_used 70; sleep 1
live_used 40
# The run lasts 2 s on the planted clock (wave-32 T1): a run of zero seconds writes no cost line
# (§ZERO-SECONDS), and this row reads the cost line a real run of some seconds writes.
world_tick 2
touch "$D/pk.go"; wait_for 20 has pk.brc
expect_eq "B.43 the run ended 0" "0" "$(brc pk)"
expect_eq "B.44 the wrapper's mid-run reading of 70 leaves no peak= on the admitted request: the gate records no memory (Δ10)" \
  "1000|" "$(field "$pk_id" admitted)|$(field "$pk_id" peak)"
expect_eq "B.45 …and the run's duration line, in the fixture repository's project where the shim ran, is its 2 s" "2:1002" \
  "$(tail -n 1 "$(costf k.test.sh "$WR")" 2>/dev/null)"

# §NUMBER, THE TREE A REQUEST NAMES (wave-28 T36; ruling A-orch-55/56). These rows belong to
# §NUMBER and sit here because they drive the real shim, whose harness (book_fg) §WRAP defines.
# The doctrine runs a row's suite as `cd <row tree> || exit 1; bash tests/x.test.sh`, often from
# the main checkout, and the wall passes `--stamp-dir <row tree>`. The shim used to ask the gate
# from its own cwd, so the request read `tree=<main checkout>` while the stamp went to the row
# tree, and the landing's busy check took every writer's suite for a run in the main checkout.
# The request now names the tree the stamp goes to: --stamp-dir's checkout, else the `cd <tree>`
# opening the command, else the shim's cwd.
fresh number-tree
world_machine 8 8192 40 1.0
world_cost t.test.sh 30
NT_ROW="$WR/.worktrees/T1"
NT_ROW_P="$(cd "$NT_ROW" 2>/dev/null && pwd -P)"
NT_WR_P="$(cd "$WR" && pwd -P)"
expect_nonempty "N.14 the row tree the doctrine call names is a checkout of its own" \
  "$(git -C "$NT_ROW" rev-parse --show-toplevel 2>/dev/null)"
expect_eq "N.15 a wrapped \`cd <tree>; bash tests/x\` from the main checkout runs (rc 0)" "0" \
  "$(book_fg nt1 --agent nt1 --max-wait 30 --stamp-dir "$NT_ROW" --suites t.test.sh -- "cd '$NT_ROW' || exit 1; true")"
expect_eq "N.16 …and its request records tree=<the row tree>, the stamp's tree" "$NT_ROW_P" \
  "$(field "$(req_of nt1)" tree)"
expect_match "N.16b …while the stamp went to the row tree's git dir" "stamp/v1|*|suites=t.test.sh|*" \
  "$(tail -n 1 "$(git -C "$NT_ROW" rev-parse --absolute-git-dir)/bionic-stamps" 2>/dev/null)"
expect_eq "N.17 with no --stamp-dir, the \`cd <tree>\` opening the command names the tree" "0 $NT_ROW_P" \
  "$(book_fg nt2 --agent nt2 --max-wait 30 --suites t.test.sh -- "cd $NT_ROW || exit 1; true") $(field "$(req_of nt2)" tree)"
expect_eq "N.18 a command that opens with no cd names the shim's own checkout (the positive for the cwd)" \
  "0 $NT_WR_P" "$(book_fg nt3 --agent nt3 --max-wait 30 --suites t.test.sh -- 'true') $(field "$(req_of nt3)" tree)"
expect_eq "N.19 …and the shim's command still runs where the shim stands (its own cd moves it)" "$NT_WR_P" \
  "$(book_fg nt4 --agent nt4 --max-wait 30 --stamp-dir "$NT_ROW" --suites t.test.sh -- "pwd -P > '$D/nt4.pwd'" >/dev/null; cat "$D/nt4.pwd" 2>/dev/null)"

# THE DOOR'S RUNNER HOLDS NOTHING EITHER (wave-28 T36; D27, AC-10.2). `tests/run.sh --only a b`
# names its suites, so the stamp can say which suites the run proved, and the wall passes
# `--runner`: the shim takes no number, and each suite the runner starts asks for itself.
fresh wrap-door
world_machine 8 8192 40 1.0
expect_eq "B.46 the door's runner (--runner, its suites named) is run, not admitted" "0" \
  "$(book_fg dr --agent dr --max-wait 30 --runner --suites a.test.sh,b.test.sh -- 'exit 0')"
expect_eq "B.47 …it took no number" "0" "$(nreq)"
expect_match "B.48 …and its stamp names the suites it ran" "stamp/v1|head=*|rc=0|*|suites=a.test.sh,b.test.sh|*" \
  "$(stamp_last)"
expect_eq "B.49 the same call without --runner asks the gate (B.47 is not vacuous)" "0 1" \
  "$(book_fg dq --agent dq --max-wait 30 --suites a.test.sh,b.test.sh -- 'exit 0') $(nreq)"


# ── §BUDGET-AT-ASK ───────────────────────────────────────────────────────────
section "§BUDGET-AT-ASK — a budgeted agent's suite or whole run is refused where it asks the gate (wave-33 T3; D7, AC-6.2)"
# The wall reads a command's text; a script runs what its text cannot be made to say (a symlink, a
# variable, a capitalised spelling). So the budget is held where a suite actually starts: the gate's
# ask. An agent whose roster row states `Suites:`/`Re-executes:` asking for a suite key or a whole
# run outside them is refused there, exit 75, the budget's own line, nothing filed and nothing run.
# The main thread, an agent with no budget, an admission believed from an ancestor and a landing's
# ask are not judged. FIXTURE FIDELITY: a real git checkout of the shipped runner and this tree's
# libraries (runner-roster.test.sh's rr_tree shape); the roster row is the recorder's own shape
# (`roster-state/v1|…|name=|agent_id=|suites_allowed=|re_executes=`) under <project>/.bionic/tmp,
# keyed by the session; the agent rides in BIONIC_GATE_AGENT, as booked.sh and the wall export it.
# fails-when: an off-budget run started through a script is admitted.
fresh budget
world_machine 8 8192 20 0.5
BA="$D/proj"; BA_MARKS="$D/marks"
mkdir -p "$BA/tests/lib" "$BA/payload/scripts/lib" "$BA/tools" "$BA/.bionic/tmp" "$BA_MARKS"
git -C "$BA" init -q
cp "$REPO_ROOT/tests/run.sh" "$BA/tests/run.sh"
cp "$REPO_ROOT/tests/lib/resolve-roots.sh" "$REPO_ROOT/tests/lib/assert.sh" "$BA/tests/lib/"
cp "$REPO_ROOT"/payload/scripts/lib/*.sh "$BA/payload/scripts/lib/"
for s in a b; do
  printf '#!/bin/bash\nset -uo pipefail\n. "$(dirname "$0")/lib/assert.sh"\n: > "$BA_MARKS/%s.ran"\nsection "%s"\nexpect_eq "%s ran" x x\nfinish\n' \
    "$s" "$s" "$s" > "$BA/tests/$s.test.sh"
done
ln -s ../tests/run.sh "$BA/tools/run.sh"
ln -s tests "$BA/t2"
printf '#!/bin/bash\nR=tests/run.sh\nbash "$R"\n' > "$BA/tools/var.sh"
printf '#!/bin/bash\nbash TESTS/run.sh\n' > "$BA/tools/caps.sh"
printf '#!/bin/bash\nbash TESTS/RUN.SH\n' > "$BA/tools/caps2.sh"
printf '#!/bin/bash\nX="$(cd "$(dirname "$0")" && pwd -P)"\nbash tests/run.sh --only a.test.sh\n' > "$BA/tools/door-a.sh"
printf '#!/bin/bash\nbash tests/run.sh --only b.test.sh\n' > "$BA/tools/door-b.sh"
BA_ROSTER="$BA/.bionic/tmp/roster-$WORLD_SID.state"
ba_row() {  # <name> <id> [<key>=<value>...] — appends a roster row of the recorder's shape
  local n="$1" i="$2"
  shift 2
  roster_row_fixture status=identified session="$WORLD_SID" name="$n" agent_id="$i" \
    launched_at=2026-10-11T00:00:00Z subagent_type=bionic:implementor "$@" >> "$BA_ROSTER"
}
printf '# bionic session roster — schema roster-state/v1 — machine-local, safe to delete\n' > "$BA_ROSTER"
ba_row fx afx-1 'suites_allowed=a.test.sh' 're_executes='
ba_row fwide afwide-1 'suites_allowed=a.test.sh b.test.sh run.sh' 're_executes='
ba_row fopen afopen-1 'files=x'
ba_row frex afrex-1 'suites_allowed=' 're_executes=`tests/run.sh --only b.test.sh`'
# ba_drive <agent|-> <command> — the command run in the checkout (BA_AT, default BA) as the agent's Bash call runs it
# (`-` is the main thread: no BIONIC_GATE_AGENT); leaves BA_OUT and BA_RC; marks cleared first.
BA_OUT=""; BA_RC=0
ba_drive() {
  local who=()
  [ "$1" = - ] || who=("BIONIC_GATE_AGENT=$1")
  rm -f "$BA_MARKS"/*.ran
  BA_OUT="$( cd "${BA_AT:-$BA}" && env -u BIONIC_GATE_ADMIT -u BIONIC_GATE_AGENT ${who[@]+"${who[@]}"} \
    BA_MARKS="$BA_MARKS" BIONIC_PRESSURE_RING="$D/ring" BIONIC_TEST_JOBS_CEILING=2 \
    bash -c "$2" 2>&1 )"
  BA_RC=$?
}
ran() { ls "$BA_MARKS" 2>/dev/null | sed 's/\.ran$//' | sort | paste -sd, -; }
BA_LINE="refused at the gate"

ba_drive - 'bash tools/run.sh'
expect_eq "BA.1 control: the main thread's whole run through a symlink to the runner runs both suites" "0 a,b" "$BA_RC $(ran)"
ba_drive fx 'bash tools/run.sh'
expect_eq "BA.2 AC-6.2 fx (a.test.sh only): the whole run through a symlink is refused at the ask, 75, nothing run" "75 " \
  "$BA_RC $(ran)"
expect_contains "BA.2b …with the budget's own line" "$BA_LINE" "$BA_OUT"
expect_contains "BA.2c …naming the whole run and the budget" "allowed: a.test.sh" "$BA_OUT"
ba_drive fx 'bash tools/var.sh'
expect_eq "BA.3 AC-6.2 the whole run through a variable is refused at the ask, nothing run" "75 " "$BA_RC $(ran)"
expect_contains "BA.3b …with the budget's own line" "$BA_LINE" "$BA_OUT"
ba_drive fx './tools/run.sh'
expect_eq "BA.4 the symlink run at argv[0] is refused alike" "75 " "$BA_RC $(ran)"
ba_drive fx 'bash t2/run.sh'
expect_eq "BA.4b …and through a linked directory" "75 " "$BA_RC $(ran)"
ba_drive fx 'bash tools/door-b.sh'
expect_eq "BA.5 AC-6.2 an off-budget suite through a script's door is refused; b never ran" "75 " "$BA_RC $(ran)"
expect_contains "BA.5b …the line names the suite" "b.test.sh" "$BA_OUT"
expect_contains "BA.5c …and the run's report says it was refused at the ask, never run" "REFUSED (the budget, at the gate's ask; never run)" "$BA_OUT"
ba_drive fx 'bash tools/door-a.sh'
expect_eq "BA.6 AC-6.2 the on-budget a.test.sh through a script (with X=\"\$(cmd \"\$a\")\" in it) is admitted and runs" "0 a" \
  "$BA_RC $(ran)"
ba_drive fx 'bash tests/run.sh --only a.test.sh b.test.sh'
expect_eq "BA.7 one call naming both: a runs, b is refused, and the run exits 75 (no suite failed)" "75 a" "$BA_RC $(ran)"
expect_contains "BA.7b …b's refusal is in the report" "b.test.sh" "$BA_OUT"
ba_drive fwide 'bash tools/run.sh'
expect_eq "BA.8 control: an agent whose budget carries run.sh runs the whole run" "0 a,b" "$BA_RC $(ran)"
ba_drive fopen 'bash tools/run.sh'
expect_eq "BA.9 an agent whose row states no budget is unaffected" "0 a,b" "$BA_RC $(ran)"
ba_drive fnobody 'bash tools/run.sh'
expect_eq "BA.10 an agent no row names is unaffected (the wall speaks for unplaced agents)" "0 a,b" "$BA_RC $(ran)"
ba_drive frex 'bash tools/door-b.sh'
expect_eq "BA.11 a suite a declared Re-executes run names is admitted" "0 b" "$BA_RC $(ran)"
ba_drive frex 'bash tests/run.sh --only a.test.sh'
expect_eq "BA.12 …and one it does not name is refused" "75 " "$BA_RC $(ran)"

# The ask itself, one asker at a time: refused asks file nothing; believed and landing asks are not judged.
fresh budget-ask
world_machine 8 8192 20 0.5
expect_eq "BA.13 gate_ask work b.test.sh by fx: 75" "75" "$(cd "$BA" && AGENT=fx ask_fg q1 work b.test.sh 2)"
expect_contains "BA.13b …its line on stderr" "$BA_LINE" "$(cat "$D/q1.err" 2>/dev/null)"
expect_eq "BA.13c …and no request was filed" "0" "$(nreq)"
expect_eq "BA.14 gate_ask work a.test.sh by fx: admitted" "0" "$(cd "$BA" && AGENT=fx ask_fg q2 work a.test.sh 2)"
expect_eq "BA.15 gate_ask whole tests/run.sh by fx: 75" "75" "$(cd "$BA" && AGENT=fx ask_fg q3 whole tests/run.sh 2)"
expect_eq "BA.16 a key that is no suite and no whole run (booked.sh's command key) is not the budget's" "0" \
  "$(cd "$BA" && AGENT=fx ask_fg q4 work 'echo one two' 2)"
expect_eq "BA.17 a landing's ask is the landing's, not the writer's spend" "0" "$(cd "$BA" && AGENT=fx ask_fg q5 landing b.test.sh 2)"
expect_eq "BA.18 the main thread's ask is not judged" "0" "$(cd "$BA" && AGENT=main ask_fg q6 work b.test.sh 2)"
# WORK runs as the holder's child, so the admission it names is believed (the ancestor rule).
(cd "$BA" && AGENT=fx WORK="cd '$BA' && BIONIC_GATE_ADMIT=\$(cat '$D/q7.id') BIONIC_GATE_AGENT=fx bash -c '. \"\$GATE_LIB\"; gate_ask work b.test.sh --within 2 >/dev/null 2>&1; echo \$? > \"$D/q7w.rc\"'" \
  ask_fg q7 work a.test.sh 2 >/dev/null)
expect_eq "BA.19 under fx's admitted a.test.sh, a child asking b.test.sh is believed, not judged" "0" "$(cat "$D/q7w.rc" 2>/dev/null)"
# MUTATION: the ask's budget call removed admits the off-budget ask.
BA_MUT="$(mutant budget-off)"
expect_true "BA.20 anchor: gate_ask calls the budget at the ask" grep -q '^  _gate_budget "\$kind" "\$key" || return 75$' "$BA_MUT"
sed -i.bak '/^  _gate_budget "\$kind" "\$key" || return 75$/d' "$BA_MUT"
expect_eq "BA.21 mutant: without it, fx's off-budget ask is admitted (the rows above are not vacuous)" "0" \
  "$(cd "$BA" && AGENT=fx GATE_LIB="$BA_MUT" ask_fg q8 work b.test.sh 2)"

# ── §BUDGET-AT-ASK, P rows: a suite run by a path outside tests/ (wave-34 T7; D23, AC-14.5) ──
# The wall names a suite file that is not this tree's own tests/<basename> by its RUN, each character
# outside the name set turned into `_` (walls.sh _bsg_suites: `bash scripts/deploy/__tests__/x.test.sh`
# is `bash_scripts_deploy___tests___x.test.sh`), and the shim asks the gate under that key. The budget
# records a suite by its file name, so the key must meet the entry it is: the same suite, run by a path.
# fails-when: a budgeted suite run by a path outside tests/ is refused against its own budget entry.
fresh budget-path
world_machine 8 8192 20 0.5
mkdir -p "$BA/scripts/deploy/__tests__"
for s in a b; do
  printf '#!/bin/bash\n: > "$BA_MARKS/%s.ran"\nexit 0\n' "$s" > "$BA/scripts/deploy/__tests__/$s.test.sh"
done
PK_DEPLOY=bash_scripts_deploy___tests___
pk_ask() {  # <name> <agent> <key> -> the ask's rc
  (cd "$BA" && AGENT="$2" ask_fg "$1" work "$3" 2)
}
expect_eq "P.1 AC-14.5 fx (a.test.sh only): a.test.sh run by scripts/deploy/__tests__/ is admitted" "0" \
  "$(pk_ask p1 fx "${PK_DEPLOY}a.test.sh")"
expect_eq "P.2 …and b.test.sh by that path is held to the budget, refused 75" "75" "$(pk_ask p2 fx "${PK_DEPLOY}b.test.sh")"
expect_contains "P.2b …the line names the key and the entry" "allowed: a.test.sh" "$(cat "$D/p2.err" 2>/dev/null)"
expect_eq "P.3 a.test.sh run from its own directory (cd tests && bash a.test.sh, key bash_a.test.sh) is admitted" "0" \
  "$(pk_ask p3 fx bash_a.test.sh)"
expect_eq "P.4 a bare key that merely ends in the entry (user_a.test.sh) is another suite, refused" "75" \
  "$(pk_ask p4 fx user_a.test.sh)"
expect_eq "P.4b …as is an interpreter word glued to another name (bash_ba.test.sh)" "75" "$(pk_ask p4b fx bash_ba.test.sh)"
expect_eq "P.5 the path key meets a wide budget's entry (fwide: a b run.sh)" "0" "$(pk_ask p5 fwide "${PK_DEPLOY}b.test.sh")"
expect_eq "P.6 a suite a declared Re-executes run names is admitted by a path too (frex names b.test.sh)" "0" \
  "$(pk_ask p6 frex "${PK_DEPLOY}b.test.sh")"
expect_eq "P.6b …and one it does not name is refused (a.test.sh)" "75" "$(pk_ask p6b frex "${PK_DEPLOY}a.test.sh")"
expect_eq "P.7 sh, zsh, dash and ksh runs meet the entry as bash does" "0 0 0 0" \
  "$(pk_ask p7a fx sh_scripts_a.test.sh) $(pk_ask p7b fx zsh_scripts_a.test.sh) $(pk_ask p7c fx dash_scripts_a.test.sh) $(pk_ask p7d fx ksh_scripts_a.test.sh)"
expect_eq "P.8 case-blind: the capitalised entry is the same suite by a path; case-exact it is another" "0 75" \
  "$(cd "$BA" && BIONIC_PROBE_CASE_BLIND=1 AGENT=fx ask_fg p8a work "${PK_DEPLOY}A.TEST.SH" 2) $(cd "$BA" && BIONIC_PROBE_CASE_BLIND=0 AGENT=fx ask_fg p8b work "${PK_DEPLOY}A.TEST.SH" 2)"
# The real shim, as the wall calls it: the suite is typed by its path, the wall names it by its run.
pk_shim() {  # <agent> <suite file name> -> the shim's rc; leaves PK_OUT; marks cleared first
  rm -f "$BA_MARKS"/*.ran
  PK_OUT="$( cd "$BA" && env -u BIONIC_GATE_ADMIT BA_MARKS="$BA_MARKS" CLAUDE_CODE_SESSION_ID="$WORLD_SID" \
    BIONIC_PRESSURE_RING="$D/ring" BIONIC_TEST_JOBS_CEILING=2 \
    bash "$BOOKED_SH_BA" --agent "$1" --max-wait 30 --suites "${PK_DEPLOY}$2" -- "bash scripts/deploy/__tests__/$2" 2>&1 )"
  return $?
}
BOOKED_SH_BA="$REPO_ROOT/payload/scripts/booked.sh"
pk_shim fx a.test.sh; PK_RC=$?
expect_eq "P.9 AC-14.5 the shim, fx running scripts/deploy/__tests__/a.test.sh: admitted, the suite ran, rc 0" "0 a" "$PK_RC $(ran)"
pk_shim fx b.test.sh; PK_RC=$?
expect_eq "P.10 …and b.test.sh by its path is refused at the ask, 75, never run" "75 " "$PK_RC $(ran)"
expect_contains "P.10b …with the budget's own line" "$BA_LINE" "$PK_OUT"
# THE PLACE NAMES THE ASKER (wave-34 T2; D11, REQ-1 AC-1.2, AC-1.4). No command carries the agent's
# name any more: a writer works in its own linked tree, whose git directory holds `bionic-agent`
# (spawn-worktree.sh create --for; tests/spawn-worktree.test.sh §MARKER), and an ask that carries no
# BIONIC_GATE_AGENT is that writer's. So a suite started inside the tree through python, awk,
# `source` or a script outside the tree meets the writer's budget in every permission mode, and its
# request is filed under the writer's name. The main checkout's git directory is the common one: it
# asks as main, and a marker planted there is never read. FIXTURE FIDELITY: a real linked tree of
# the BA checkout holding the same runner and libraries, its marker planted as create writes it.
# fails-when: the marker fallback is deleted (admitted as main), or who reads `:main`.
fresh budget-mark
world_machine 8 8192 20 0.5
git -C "$BA" -c user.name=t -c user.email=t@t -c core.hooksPath=/dev/null commit -q --allow-empty -m place
BM="$D/tree"
git -C "$BA" worktree add -q --detach "$BM" 2>/dev/null
cp -R "$BA/tests" "$BA/payload" "$BA/tools" "$BM/"
ln -s tests "$BM/t2"
BM_GD="$(git -C "$BM" rev-parse --absolute-git-dir)"
printf 'fx\n' > "$BM_GD/bionic-agent"
printf '#!/bin/bash\nbash tests/run.sh --only "$1"\n' > "$D/outside.sh"
BM_PY='import subprocess, sys; sys.exit(subprocess.run(["bash", "tests/run.sh", "--only", sys.argv[1]]).returncode)'
BM_P="$(cd "$BM" && pwd -P)"; BA_P="$(cd "$BA" && pwd -P)"
expect_eq "M.0 control: the tree is linked, its git directory its own (not the common one), the marker fx" "fx|yes" \
  "$(cat "$BM_GD/bionic-agent")|$([ "$BM_GD" != "$(git -C "$BM" rev-parse --path-format=absolute --git-common-dir)" ] && echo yes)"
if command -v python3 >/dev/null 2>&1 && python3 -c '' >/dev/null 2>&1; then
  BA_AT="$BM" ba_drive - "python3 -c '$BM_PY' b.test.sh"
  expect_eq "M.1 AC-1.2 no name carried, inside fx's tree: an off-budget suite through python is refused at the ask, 75, nothing run" \
    "75 " "$BA_RC $(ran)"
  expect_contains "M.1b …with the budget's own line, naming fx" "b.test.sh is not on fx's budget" "$BA_OUT"
  BA_AT="$BM" ba_drive - "python3 -c '$BM_PY' a.test.sh"
  expect_eq "M.1c …and the on-budget a.test.sh through python is admitted and runs" "0 a" "$BA_RC $(ran)"
  BA_AT="$BA" ba_drive - "python3 -c '$BM_PY' b.test.sh"
  expect_eq "M.1d AC-1.4 the same python launcher in the main checkout asks as main and runs" "0 b" "$BA_RC $(ran)"
else
  ok "M.1 python3 cannot run on this machine: M.2 to M.4 carry the launcher claim (awk, source, a script outside the tree)"
fi
BA_AT="$BM" ba_drive - "awk 'BEGIN { exit system(\"bash tests/run.sh --only b.test.sh\") }'"
expect_eq "M.2 AC-1.2 …through awk" "75 " "$BA_RC $(ran)"
expect_contains "M.2b …naming fx" "b.test.sh is not on fx's budget" "$BA_OUT"
BA_AT="$BM" ba_drive - 'source tools/door-b.sh'
expect_eq "M.3 AC-1.2 …through source" "75 " "$BA_RC $(ran)"
BA_AT="$BM" ba_drive - "bash '$D/outside.sh' b.test.sh"
expect_eq "M.4 AC-1.2 …through a script outside the tree, started from inside it" "75 " "$BA_RC $(ran)"
BA_AT="$BM" ba_drive - "bash '$D/outside.sh' a.test.sh"
expect_eq "M.4b …which runs the on-budget a.test.sh" "0 a" "$BA_RC $(ran)"
BA_AT="$BM" ba_drive fwide "bash '$D/outside.sh' b.test.sh"
expect_eq "M.5 a name carried wins over the place: fwide in fx's tree runs b" "0 b" "$BA_RC $(ran)"
BA_AT="$BA" ba_drive - "bash '$D/outside.sh' b.test.sh"
expect_eq "M.6 AC-1.4 the main checkout has no marker: the same script there asks as main and runs b" "0 b" "$BA_RC $(ran)"
printf 'fx\n' > "$BA/.git/bionic-agent"
BA_AT="$BA" ba_drive - "bash '$D/outside.sh' b.test.sh"
expect_eq "M.6b AC-1.4 …and a marker planted in the main checkout's git directory is never read" "0 b" "$BA_RC $(ran)"
rm -f "$BA/.git/bionic-agent"

# THE REQUEST'S WHO, one asker at a time, so the fill sees the writer as showing.
fresh budget-mark-who
world_machine 8 8192 20 0.5
bm_ask() {  # <gate lib> <dir> <key> — gate_ask work <key> from <dir>, no name carried; prints its rc
  ( cd "$2" && env -u BIONIC_GATE_AGENT -u BIONIC_GATE_ADMIT bash -c \
      '. "$1" 2>/dev/null; gate_ask work "$2" --within 2 >/dev/null 2>&1; echo $?' _ "$1" "$3" )
}
expect_eq "M.7 AC-1.2 gate_ask work a.test.sh from fx's tree, no name carried: admitted" "0" "$(bm_ask "$GATE_LIB" "$BM" a.test.sh)"
expect_eq "M.7b …and its request is filed under fx, so the fill sees fx showing" "a.test.sh|$BM_P" \
  "$(field "$(req_of fx)" key)|$(field "$(req_of fx)" tree)"
expect_eq "M.8 AC-1.4 gate_ask work b.test.sh from the main checkout: admitted" "0" "$(bm_ask "$GATE_LIB" "$BA" b.test.sh)"
expect_eq "M.8b …filed under main (M.7b is the positive, same reader)" "b.test.sh|$BA_P" \
  "$(field "$(req_of main)" key)|$(field "$(req_of main)" tree)"
expect_eq "M.9 gate_ask work b.test.sh from fx's tree: 75, nothing filed" "75 2" \
  "$(bm_ask "$GATE_LIB" "$BM" b.test.sh) $(nreq)"
# MUTATION: the fallback deleted asks as main; the common dir read in place of the tree's own finds no marker.
fresh budget-mark-mut1
world_machine 8 8192 20 0.5
BM_MUT1="$(mutant mark-off)"
expect_true "M.10 anchor: the ask falls back to the place's marker" grep -q '^  \[ -n "\$_GATE_AGENT" \] || _gate_marker$' "$BM_MUT1"
sed -i.bak '/^  \[ -n "\$_GATE_AGENT" \] || _gate_marker$/d' "$BM_MUT1"
expect_eq "M.10b mutant: without it, fx's off-budget ask from its tree is admitted (M.1–M.9 are not vacuous)" "0" \
  "$(bm_ask "$BM_MUT1" "$BM" b.test.sh)"
fresh budget-mark-mut2
world_machine 8 8192 20 0.5
BM_MUT2="$(mutant mark-common)"
expect_true "M.11 anchor: the marker is read from the tree's own git directory" grep -q '"\$_GATE_GITDIR/bionic-agent"' "$BM_MUT2"
sed -i.bak 's#\$_GATE_GITDIR/bionic-agent#$_GATE_COMMON/bionic-agent#g' "$BM_MUT2"
expect_eq "M.11b mutant: reading the common directory instead, fx's off-budget ask is admitted" "0" \
  "$(bm_ask "$BM_MUT2" "$BM" b.test.sh)"
# THE MARKER COSTS NO FORK (AC-1.4): the one `git rev-parse` that names the request's tree names who
# asks and finds the roster too, so an ask from a marked tree makes the git calls one from the main
# checkout makes, and a carried name makes no more. Counted by a `git` on PATH that logs each call.
fresh budget-mark-fork
world_machine 8 8192 20 0.5
mkdir -p "$D/shim"
printf '#!/bin/bash\necho "$*" >> "%s/git.calls"\nexec %q "$@"\n' "$D" "$(command -v git)" > "$D/shim/git"
chmod +x "$D/shim/git"
bm_gits() {  # <dir> <key> [agent] — how many git calls one gate_ask work <key> from <dir> makes
  rm -f "$D/git.calls"
  ( cd "$1" && env -u BIONIC_GATE_AGENT -u BIONIC_GATE_ADMIT ${3:+BIONIC_GATE_AGENT=$3} PATH="$D/shim:$PATH" \
      bash -c '. "$1" 2>/dev/null; gate_ask work "$2" --within 2 >/dev/null 2>&1' _ "$GATE_LIB" "$2" )
  if [ -f "$D/git.calls" ]; then grep -c '' "$D/git.calls"; else echo 0; fi
}
BM_G_MAIN="$(bm_gits "$BA" a.test.sh)"
expect_true "M.12 control: the shim sees the main checkout's ask call git ($BM_G_MAIN)" test "$BM_G_MAIN" -ge 1
expect_eq "M.12b AC-1.4 an ask from fx's tree with no name carried makes the same git calls" "$BM_G_MAIN" \
  "$(bm_gits "$BM" a.test.sh)"
expect_eq "M.12c …and so does one carrying fx's name" "$BM_G_MAIN" "$(bm_gits "$BM" a.test.sh fx)"

# ── §CASE ────────────────────────────────────────────────────────────────────
section "§CASE — a capitalised spelling meets the budget its lowercase one meets (wave-33 T3; D7, AC-6.3)"
# On a case-blind filesystem `TESTS/RUN.SH` is the runner and `GAMMA.TEST.SH` is gamma.test.sh, so
# the ask compares keys folded there and exactly elsewhere. BIONIC_PROBE_CASE_BLIND plants the
# filesystem's answer so both directions run on any machine; the drive of `bash TESTS/RUN.SH` needs
# the real filesystem to find the file, so it runs where the real one folds and says so otherwise.
fresh case
world_machine 8 8192 20 0.5
ca_ask() {  # <planted 0|1> <name> <kind> <key>
  (cd "$BA" && BIONIC_PROBE_CASE_BLIND="$1" AGENT=fx ask_fg "$2" "$3" "$4" 2)
}
expect_eq "CA.1 control: a.test.sh is admitted" "0" "$(ca_ask 1 c1 work a.test.sh)"
expect_eq "CA.2 case-blind: A.TEST.SH is a.test.sh, admitted" "0" "$(ca_ask 1 c2 work A.TEST.SH)"
expect_eq "CA.3 case-blind: GAMMA.TEST.SH is refused as gamma.test.sh is" "75 75" \
  "$(ca_ask 1 c3 work GAMMA.TEST.SH) $(ca_ask 1 c3l work gamma.test.sh)"
expect_eq "CA.4 case-blind: TESTS/RUN.SH is the whole run, refused" "75" "$(ca_ask 1 c4 whole TESTS/RUN.SH)"
expect_eq "CA.5 case-exact: A.TEST.SH is another file, not on the budget" "75" "$(ca_ask 0 c5 work A.TEST.SH)"
BA_REAL_BLIND=no; [ "$BA/tests" -ef "$BA/TESTS" ] && BA_REAL_BLIND=yes
if [ "$BA_REAL_BLIND" = yes ]; then
  ba_drive fx 'bash tools/caps.sh'
  expect_eq "CA.6 AC-6.3 bash TESTS/run.sh from a script, on this case-blind filesystem: refused at the ask, nothing run" \
    "75 " "$BA_RC $(ran)"
  expect_contains "CA.6b …with the budget's own line" "$BA_LINE" "$BA_OUT"
  ba_drive - 'bash tools/caps.sh'
  expect_eq "CA.7 control: the main thread's same script runs the whole run" "0 a,b" "$BA_RC $(ran)"
  # The capitalised NAME is refused by the runner itself before anything asks: its interpreter seam
  # re-runs any script not named run.sh (tests/lib/resolve-roots.sh), and the runner refuses the
  # suite paths it is handed. Nothing runs, on the budget or off it.
  ba_drive - 'bash tools/caps2.sh'
  expect_eq "CA.8 bash TESTS/RUN.SH: the runner refuses its own capitalised name, for anyone; nothing runs" "2 " "$BA_RC $(ran)"
else
  echo "  (CA.6–CA.8 not run: this filesystem is case-exact, so TESTS/RUN.SH names no file here)"
fi

finish
