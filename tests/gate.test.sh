#!/bin/bash
# tests/gate.test.sh — payload/scripts/lib/gate.sh: one gate admits every heavy command on the
# machine's present reading plus its own record of what each command cost (epic-23
# wave-28-finished-work-lands, T2; REQ-2, REQ-4, REQ-7; spec D10, D11, D12; ADR-046).
#
# WHAT IS UNDER TEST. One section per eval the spec names:
#
#   §SHARE     AC-2.1  asks from two fixture projects read one share file; a project's own
#                      config or plan line changes neither; absent or unreadable is 80
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
#   §WAITED    AC-4.2  a request holds its asked and admitted times, and the wait is their gap
#   §KILLED    AC-4.3  a real child admitted and then killed with signal 9 is counted once;
#                      its peak is kept and it writes no cost
#   §COST      D12     gate_end's cost line, three kept, the per-field promise, the unknown
#                      command's promise, the memory rise from idle to the peak (a reading
#                      that rises mid-run and falls before gate_end), the overlap rule, an
#                      overestimate held until it ages out of the three lines, `times`, an
#                      unknown request line ignored. Mutations: no peak raised mid-run; four
#                      lines kept
#   §ROOM      AC-2.5  gate_room (T13, D14): a five-minute load over the share, a waiting
#                      request, promised work not yet showing and memory over the share each
#                      give no room; a quiet machine gives room; two asks on one reading give
#                      room once; gate_state prints the loads where clears= stood. Mutations:
#                      the waiting clause, the owed count, the five-minute reading
#   §REAPED    T47     a request killed earlier is written ended (rc 137) by the next locked act
#                      and overlaps nothing after: the next run learns its rise; one killed
#                      during another's run still overlaps it. Mutation: the killed-write removed
#   §ALONE     T47     an idle gate admits a promise over the room while the reading is at most
#                      the share; a reading over it still refuses. Mutation: the idle clause removed
#   §OWN       T47     a second ask by one who for one key, the first still polling, gets a
#                      number of its own. Mutation: the liveness test on reuse removed
#   §CLEARED   T47     a request returned 75 has its holder cleared, so a live caller that no
#                      longer polls keeps no head. Mutation: the clearing removed
#   §MACHINES  AC-7.3  the admission rows run under three planted machines and decide alike
#   §WRAP      AC-2.6, AC-2.13 (T12) the wrapper, booked.sh, asks the gate: the command's own code
#                      on a run; 75 and nothing run when the wait runs out, under --max-wait or
#                      --kill-after; its next call resumes the number and runs first; a nested
#                      shim is believed; a typed admission and BIONIC_SLOT_HELD=1 ask anyway; 2
#                      on usage; a stamp on every end but usage; the runner takes no number; a
#                      run is sampled while it runs. Mutations: the wrapper believing a typed
#                      admission without asking; the wrapper exiting 0 on a timeout
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
# to run (its own positive row) before its claim is read; §COST adds two more, and §REAPED,
# §ALONE, §OWN and §CLEARED one each (T47).
#
# FIXTURE FIDELITY (declared, per .claude/rules/test-harness.md, "Fixture fidelity"):
#   * The machine, the clock and the cost records are SYNTHESIZED by design (the world's
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
#   WORK=<sh>  once admitted, run <sh> as a child before holding (processor time for `times`)
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
if [ -n "${CHILD:-}" ]; then
  ( kid="$CHILD"; unset CHILD HOLD WORK; BIONIC_GATE_ADMIT="$id" bash "$0" "$d" "$kid" "$kind" "$key" 0 )
fi
[ -z "${WORK:-}" ] || bash -c "$WORK"
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
wait_for() {  # <seconds> <cmd>... — rc 0 once the command succeeds, 1 at the ceiling
  local i=0 lim=$(( $1 * 20 ))
  shift
  until "$@"; do
    i=$((i + 1)); [ "$i" -lt "$lim" ] || return 1
    sleep 0.05
  done
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
expect_eq "S.1 no share file: gate_share prints 80" "80" "$( . "$GATE_LIB" 2>/dev/null; gate_share )"
for bad in abc 0 101 "" 1234; do
  printf '%s\n' "$bad" > "$CLAUDE_CONFIG_DIR/bionic/share"
  expect_eq "S.2 an unreadable share '$bad' is 80" "80" "$( . "$GATE_LIB" 2>/dev/null; gate_share )"
done
printf '50\n' > "$CLAUDE_CONFIG_DIR/bionic/share"
for p in A B; do
  mkdir -p "$D/proj$p/.bionic/docs/plans"
  printf 'share: 90\ngate-share: 90\n' > "$D/proj$p/.bionic/config.yaml"
  printf -- '---\nshare: 90\n---\nshare=90\n' > "$D/proj$p/.bionic/docs/plans/p.plan.md"
done
world_cost k 10 0.5 30
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
world_cost k 10 0.5 30
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

# ── §HARD ────────────────────────────────────────────────────────────────────
section "§HARD — memory is the hard limit, the processor the soft one (AC-2.2)"
fresh hard
world_machine 8 8192 85 1.0
world_cost k 5 0.5 30
expect_eq "H.1 used 85 under a share of 80, nothing admitted: not admitted (rc 75)" "75" "$(ask_fg h1 work k 0)"
expect_eq "H.2 its request was taken (asked=1000)" "1000" "$(field "$(req_of h1)" asked)"
expect_eq "H.3 and holds no admitted line (asked|admitted)" "1000|" "$(field "$(req_of h1)" asked)|$(field "$(req_of h1)" admitted)"
fresh hard2
world_machine 8 8192 30 16
world_cost k 5 2 30
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
expect_eq "H.7 another unknown command while that one runs: rc 75" "75" "$(ask_fg u2 work never-seen-2 0)"
release u1
fresh hard4
world_machine 8 8192 30 1.0
world_cost k 5 0.5 30
export BIONIC_PROBE_USED_PCT=-1
HOLD=1 ask_bg m1 work k 0
wait_for 20 has m1.rc
expect_eq "H.8 memory unreadable (-1), nothing admitted: admitted" "0" "$(rc_of m1)"
expect_eq "H.9 memory unreadable while one is admitted: rc 75" "75" "$(ask_fg m2 work k 0)"
release m1
export BIONIC_PROBE_USED_PCT=30
# Mutation arm: the share's ceiling lifted to 100. The same H.1 ask must then be admitted.
MG="$(mutant ceiling)"
anchor "$MG" 'if (u + n[1] > share) exit 1' 1
sed -i.bak 's/if (u + n\[1\] > share) exit 1/if (u + n[1] > 100) exit 1/' "$MG"
fresh hard-mut
world_machine 8 8192 85 1.0
world_cost k 5 0.5 30
expect_eq "H.10 the mutant still decides: used 85 + 20 > 100 is refused (rc 75)" "75" \
  "$(world_cost big 20 0.5 30; GATE_LIB="$MG" ask_fg hm0 work big 0)"
expect_eq "H.11 the mutant admits at 85% used under a share of 80 — the ceiling is the rule" "0" \
  "$(GATE_LIB="$MG" ask_fg hm1 work k 0)"

# ── the admission rows, parameterised by machine (§NOCONST, §MACHINES) ───────
# admissions <cores> <total_mb> — four asks on one machine, every processor figure a share of
# its cores; sets ADM to the four rcs. (Rows that start background askers never run inside
# `$( )`: a poller started in a subshell would outlive the row unreaped.) Expected on any machine: 0 75 0 75 (the second over memory,
# the fourth over the processor while two are admitted).
admissions() {
  local c="$1" q h
  q="$(awk -v c="$c" 'BEGIN { printf "%g", c * 0.25 }')"
  h="$(awk -v c="$c" 'BEGIN { printf "%g", c * 0.5 }')"
  fresh "adm-$1-$2"
  world_machine "$c" "$2" 50 "$q"
  world_cost k1 20 "$q" 60
  world_cost k2 5 "$q" 60
  world_cost k3 1 "$h" 60
  HOLD=1 ask_bg w1 work k1 0; wait_for 20 has w1.rc
  ask_fg w2 work k1 0 >/dev/null
  HOLD=1 ask_bg w3 work k2 0; wait_for 20 has w3.rc
  ask_fg w4 work k3 0 >/dev/null
  ADM="$(rc_of w1) $(rc_of w2) $(rc_of w3) $(rc_of w4)"
  touch "$D/w1.go" "$D/w3.go"
}
# hard_rows <cores> <total_mb> — §HARD's two rules on one machine; sets HRD to two rcs (75 0)
hard_rows() {
  fresh "hardm-$1-$2"
  world_machine "$1" "$2" 85 1
  world_cost k 5 0.1 30
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
world_machine 8 8192 60 1.0
world_cost k 15 0.5 30
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
world_cost k 5 0.5 30
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
world_machine 8 8192 60 1.0
world_cost h 15 0.5 30
world_cost k 15 0.5 30
HOLD=1 ask_bg nh work h 0; wait_for 20 has nh.rc
expect_eq "N.1 the holder is admitted (60 + 15)" "0" "$(rc_of nh)"
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
  world_machine 8 8192 60 1.0
  world_cost h 15 0.5 30
  world_cost k 15 0.5 30
  world_cost l 15 0.5 30
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
  world_machine 8 8192 50 1.0
  world_cost k 25 0.5 30
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

# ── §WAITED ──────────────────────────────────────────────────────────────────
section "§WAITED — a request holds its asked and admitted times (AC-4.2)"
fresh waited
world_machine 8 8192 60 1.0
world_cost h 15 0.5 30
world_cost k 15 0.5 30
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
world_machine 8 8192 50 1.0
world_cost k 25 0.5 30
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
expect_eq "K.10 the killed run kept the peak a reading raised mid-run (70)" "70" "$(field "${kk_id:-none}" peak)"
expect_eq "K.11 and it wrote no cost: cost/k holds the one planted line" "1 25:0.5:30:1000" \
  "$(wc -l < "$BIONIC_GATE_DIR/cost/k" | tr -d ' ') $(head -n 1 "$BIONIC_GATE_DIR/cost/k")"

# ── §COST ────────────────────────────────────────────────────────────────────
section "§COST — a command's cost is learned from the machine (D12)"
# peak_run <gate lib> <name> — idle 40; a run admitted at 40, a reading of 55 mid-run (the one
# call that samples, gate_state), back to 40 at gate_end 30 s later. Sets PK_STATE (the mid-run
# gate_state line), PK_ID and PK_LINE (cost/k's newest line).
peak_run() {
  fresh "$2"
  world_machine 8 8192 40 1.0
  world_cost k 10 0.5 20
  world_cost k 4 1.5 50
  world_cost k 7 0.25 90
  world_cost other 30 3 10
  GATE_LIB="$1" HOLD=1 ask_bg c1 work k 0; wait_for 20 has c1.rc
  PK_ID="$(id_of c1)"
  PK_STATE="$(GATE_LIB="$1" BIONIC_PROBE_USED_PCT=55 state)"
  printf 'later-field=a line this gate does not know\n' >> "$BIONIC_GATE_DIR/requests/${PK_ID:-none}"
  world_tick 30
  release c1
  PK_LINE="$(tail -n 1 "$BIONIC_GATE_DIR/cost/k" 2>/dev/null)"
}
peak_run "$GATE" cost
c1_id="$PK_ID"
expect_eq "D.1 the promise is the per-field maximum of the key's lines" "10:1.5:90" "$(field "$c1_id" promise)"
expect_contains "D.2 a reading taken during the run (gate_state at 55) sees it admitted" "admitted=1 " "$PK_STATE"
expect_eq "D.3 the peak is kept on the request" "55" "$(field "$c1_id" peak)"
expect_eq "D.16 a request line the gate does not know is ignored: the run ended all the same" \
  "1030 a line this gate does not know" "$(field "$c1_id" ended) $(field "$c1_id" later-field)"
expect_eq "D.4 gate_end exits 0" "0" "$(cat "$D/c1.endrc")"
expect_eq "D.5 it writes ended at 1030" "1030" "$(field "$c1_id" ended)"
expect_eq "D.6 and the rc" "0" "$(field "$c1_id" rc)"
expect_eq "D.7 cost/k keeps three lines: the oldest planted is now the second" "3 4:1.5:50:1000" \
  "$(wc -l < "$BIONIC_GATE_DIR/cost/k" | tr -d ' ') $(head -n 1 "$BIONIC_GATE_DIR/cost/k")"
expect_regex "D.8 the newest is this run: rise to the peak 55-40=15 (the end read 40), 30 s, at 1030" \
  '^15:[0-9.]+:30:1030$' "$PK_LINE"
expect_eq "D.9 the oldest planted line is gone" "0" "$(grep -c '^10:0.5:20:' "$BIONIC_GATE_DIR/cost/k")"
world_machine 8 8192 40 1.0
HOLD=1 ask_bg c2 work never-seen 0; wait_for 20 has c2.rc
expect_eq "D.10 a command never seen is promised the maximum over every cost file" "30:3:90" \
  "$(field "$(id_of c2)" promise)"
release c2
fresh cost-over
world_machine 8 8192 40 1.0
world_cost k 9 0.5 20
world_cost j 5 0.5 20
HOLD=1 ask_bg o1 work k 0; wait_for 20 has o1.rc
HOLD=1 ask_bg o2 work j 0; wait_for 20 has o2.rc
expect_eq "D.11 two runs are admitted side by side" "0 0" "$(rc_of o1) $(rc_of o2)"
BIONIC_PROBE_USED_PCT=70 state >/dev/null
world_tick 10
release o1; release o2
expect_regex "D.12 an overlapped run carries the previous memory value (9), not the rise" \
  '^9:[0-9.]+:10:1010$' "$(tail -n 1 "$BIONIC_GATE_DIR/cost/k")"
fresh cost-cpu
world_machine 8 8192 40 1.0
world_cost k 1 0.5 20
WORK="awk 'BEGIN { for (i = 0; i < 3000000; i++) s += i }'" HOLD=1 ask_bg u1 work k 0
wait_for 20 has u1.rc
world_tick 1
release u1
expect_regex "D.13 the processor field is the children's time from \`times\`, over 0" \
  '^[0-9]*\.[0-9]*[1-9][0-9]*:1:' "$(tail -n 1 "$BIONIC_GATE_DIR/cost/k" | cut -d: -f2-)"
MP="$(mutant peak)"
anchor "$MP" 'if [ "$reading" -ge 0 ] && [ "$reading" -gt "${_R_peak:--1}" ]; then' 1
sed -i.bak 's/if \[ "\$reading" -ge 0 \] && \[ "\$reading" -gt "\${_R_peak:--1}" \]; then/if false; then/' "$MP"
peak_run "$MP" cost-mut
expect_regex "D.17 the mutant (no peak raised mid-run) still ends the run and writes its line" \
  ':30:1030$' "$PK_LINE"
expect_regex "D.18 the mutant records 0, not the peak's 15 — the mid-run sample is the rule" '^0:' "$PK_LINE"
# age_runs <gate lib> <name> — cost/k holds one overestimate (30, an overlapped run's measured
# rise); four undisturbed runs follow, each rising 5. Sets AGE to the four admissions' memory
# promises.
age_runs() {
  local i p
  fresh "$2"
  world_machine 8 8192 40 1.0
  world_cost k 30 0.5 20
  AGE=""
  for i in 1 2 3 4; do
    GATE_LIB="$1" HOLD=1 ask_bg "a$i" work k 0; wait_for 20 has "a$i.rc"
    p="$(field "$(id_of "a$i")" promise)"; AGE="$AGE ${p%%:*}"
    GATE_LIB="$1" BIONIC_PROBE_USED_PCT=45 state >/dev/null
    world_tick 10
    release "a$i"
  done
  AGE="${AGE# }"
}
age_runs "$GATE" cost-age
expect_eq "D.19 three lower undisturbed runs do not lower the promise until the overestimate ages out" \
  "30 30 30 5" "$AGE"
MK="$(mutant keep4)"
anchor "$MK" '} | tail -n 3 > "$_GD/cost/.new.$id"' 1
sed -i.bak 's/} | tail -n 3 > "\$_GD\/cost\/.new.\$id"/} | tail -n 4 > "$_GD\/cost\/.new.$id"/' "$MK"
age_runs "$MK" cost-age-mut
expect_eq "D.20 the mutant keeping four lines still runs all four and holds 30 one run longer" \
  "30 30 30 30" "$AGE"
expect_eq "D.14 gate_end of a request that does not exist exits 2" "2" \
  "$( . "$GATE_LIB" 2>/dev/null; gate_end 999 0 2>/dev/null; echo $? )"
expect_eq "D.15 gate_ask with an unknown kind exits 2" "2" \
  "$( . "$GATE_LIB" 2>/dev/null; gate_ask fast k 2>/dev/null; echo $? )"
# THE PUBLIC READER (T13; pass 12): `gate_promise <key>` prints what `_gate_promise` prints,
# loading the store itself, so a caller outside the lock can ask what a key is promised.
fresh promise-public
world_cost k 10 0.5 30
world_cost k 5 2 30
expect_eq "D.21 gate_promise prints the per-field maximum for a key, loading the store itself" \
  "10:2:30" "$( . "$GATE_LIB" 2>/dev/null; gate_promise k 2>/dev/null )"
expect_eq "D.22 a key never seen is promised the maximum over every cost file" \
  "10:2:30" "$( . "$GATE_LIB" 2>/dev/null; gate_promise never 2>/dev/null )"
expect_eq "D.23 no key is a usage error (rc 2)" "2" \
  "$( . "$GATE_LIB" 2>/dev/null; gate_promise 2>/dev/null; echo $? )"

# ── §ROOM ────────────────────────────────────────────────────────────────────
# gate_room [--owed <n>] (wave-28 T13; D14): may another writer start? Every row plants an
# 8-core machine under a share of 80, so the processor limit is 6.4 cores. `room` runs the
# verb in a child and appends its rc to the one line it prints.
section "§ROOM — width follows the machine's load (AC-2.5)"
room() { ( . "$GATE_LIB" 2>/dev/null; o="$(gate_room "$@" 2>&1)"; r=$?; printf '%s rc=%s' "$o" "$r" ); }
fresh room-quiet
world_machine 8 8192 30 1.0
world_cost k 5 1.5 30
expect_eq "RM.1 a quiet machine gives room" \
  "room=yes load=1.0/1.0 cores=8 promised=0 waiting=0 rc=0" "$(room)"
fresh room-5m
world_machine 8 8192 30 1.0 7.0
world_cost k 5 1.5 30
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
world_cost k 5 0.5 30
HOLD=1 ask_bg rw1 work k 0; wait_for 20 has rw1.rc
ask_bg rw2 whole k 600; wait_for 20 asked_by rw2
expect_eq "RM.5 one is admitted and a whole request waits behind it (rc|asked|admitted)" "0|1000|" \
  "$(rc_of rw1)|$(field "$(req_of rw2)" asked)|$(field "$(req_of rw2)" admitted)"
expect_eq "RM.6 a waiting request gives no room, though the load and the promises fit" \
  "room=no load=1.0/1.0 cores=8 promised=0.5 waiting=1 rc=1" "$(room)"
MW="$(mutant room-wait)"
anchor "$MW" 'if (wait > 0) room = 0' 1
sed -i.bak 's/if (wait > 0) room = 0/if (0) room = 0/' "$MW"
expect_eq "RM.7 the mutant without the waiting clause runs and gives room — the clause is the rule" \
  "room=yes load=1.0/1.0 cores=8 promised=0.5 waiting=1 rc=0" "$(GATE_LIB="$MW" room)"
release rw1
fresh room-prom
world_machine 8 8192 30 1.0
world_cost k 5 6 30
HOLD=1 ask_bg rp1 work k 0; wait_for 20 has rp1.rc
expect_eq "RM.8 a run is admitted promising 6 cores (rc|promise)" "0|5:6:30" \
  "$(rc_of rp1)|$(field "$(req_of rp1)" promise)"
expect_eq "RM.9 a load of 1.0 plus the 6 promised and not yet showing is over 6.4: no room" \
  "room=no load=1.0/1.0 cores=8 promised=6 waiting=0 rc=1" "$(room)"
release rp1
expect_eq "RM.10 once it has ended its promise no longer counts" \
  "room=yes load=1.0/1.0 cores=8 promised=0 waiting=0 rc=0" "$(room)"
fresh room-owed
world_machine 8 8192 30 1.0
world_cost k 5 3 30
expect_eq "RM.11 one writer owed at the largest promise on record, 3 cores: 1.0 + 3 fits" \
  "room=yes load=1.0/1.0 cores=8 promised=3 waiting=0 rc=0" "$(room --owed 1)"
expect_eq "RM.12 two writers owed: 1.0 + 6 is over 6.4, no room" \
  "room=no load=1.0/1.0 cores=8 promised=6 waiting=0 rc=1" "$(room --owed 2)"
MO="$(mutant room-owed)"
anchor "$MO" 'prom = pc + owed * most' 1
sed -i.bak 's/prom = pc + owed \* most/prom = pc + 0 * most/' "$MO"
expect_eq "RM.13 the mutant that drops the owed count runs and gives room — the count is the rule" \
  "room=yes load=1.0/1.0 cores=8 promised=0 waiting=0 rc=0" "$(GATE_LIB="$MO" room --owed 2)"
fresh room-two
world_machine 8 8192 30 4.0
world_cost k 5 3 30
expect_eq "RM.14 the first ask on one reading, nothing offered yet: room" \
  "room=yes load=4.0/4.0 cores=8 promised=0 waiting=0 rc=0" "$(room --owed 0)"
expect_eq "RM.15 the second ask on the same reading counts the first: 4.0 + 3 is over 6.4" \
  "room=no load=4.0/4.0 cores=8 promised=3 waiting=0 rc=1" "$(room --owed 1)"
fresh room-nocost
world_machine 8 8192 30 1.0
expect_eq "RM.16 no cost on record and nothing owed: room" \
  "room=yes load=1.0/1.0 cores=8 promised=0 waiting=0 rc=0" "$(room)"
expect_eq "RM.17 no cost on record: one writer not yet showing takes all the room" \
  "room=no load=1.0/1.0 cores=8 promised=8 waiting=0 rc=1" "$(room --owed 1)"
fresh room-mem
world_machine 8 8192 85 1.0
world_cost k 5 1 30
expect_eq "RM.18 memory used 85 under a share of 80 gives no room" \
  "room=no load=1.0/1.0 cores=8 promised=0 waiting=0 rc=1" "$(room)"
expect_eq "RM.19 …and 80 used gives room (at most the share)" \
  "room=yes load=1.0/1.0 cores=8 promised=0 waiting=0 rc=0" "$(BIONIC_PROBE_USED_PCT=80 room)"
fresh room-blind
world_machine 8 8192 30 1.0
world_cost k 5 1 30
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
world_cost k 5 0.5 30
HOLD=1 ask_bg rs1 work k 0; wait_for 20 has rs1.rc
expect_eq "RM.24 gate_state prints the loads and the promised cores where clears= stood" \
  "share=80 used=35 admitted=1 waiting=0 landing-waiting=0 load=1.0/2.5 promised=0.5" "$(state)"
expect_absent "RM.25 …and no clears= field" "clears=" "$(state)"
release rs1
# ── §REAPED ──────────────────────────────────────────────────────────────────
section "§REAPED — a killed request overlaps nothing once it is seen dead (T47; cost row)"
# learn_run <gate lib> <name> <kill 0|1> — idle 30. With kill=1 a run of key x is admitted and
# killed with signal 9, and the clock moves a minute. Then a run of key L is admitted at 30, a
# reading of 70 is taken mid-run (gate_state), and it ends 30 s later. Sets LR_LINE (cost/L's
# newest line), LR_KID (the killed request's id) and LR_LIST (gate_list after the run).
learn_run() {
  local kp
  fresh "$2"
  world_machine 8 8192 30 1.0
  world_cost L 10 0.5 30
  world_cost x 5 0.5 30
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
  LR_LINE="$(tail -n 1 "$BIONIC_GATE_DIR/cost/L" 2>/dev/null)"
  LR_LIST="$(GATE_LIB="$1" glist)"
}
learn_run "$GATE" reaped-control 0
expect_regex "R.1 control, nothing killed: the run learns its rise, 70-30=40" '^40:[0-9.]+:30:1030$' "$LR_LINE"
learn_run "$GATE" reaped 1
expect_eq "R.2 the killed run was admitted, and gate_list lists it killed" "0 1" \
  "$(rc_of rx) $(printf '%s\n' "$LR_LIST" | grep -c "^${LR_KID:-none} killed ")"
expect_regex "R.3 a run after it learns the same 40, not the carried 10" '^40:[0-9.]+:30:1090$' "$LR_LINE"
expect_eq "R.4 the next locked act (that run's admission at 1060) wrote it ended, rc 137" "1060|137" \
  "$(field "$LR_KID" ended)|$(field "$LR_KID" rc)"
expect_eq "R.5 and it wrote no cost: cost/x holds its one planted line" "1" \
  "$(wc -l < "$BIONIC_GATE_DIR/cost/x" | tr -d ' ')"
fresh reaped-during
world_machine 8 8192 30 1.0
world_cost L 10 0.5 30
world_cost x 5 0.5 30
HOLD=1 ask_bg r1 work L 0; wait_for 20 has r1.rc
world_tick 5
HOLD=1 ask_bg rx work x 0; wait_for 20 has rx.rc
rx_id="$(id_of rx)"; rx_pid="$(cat "$D/rx.pid")"
BIONIC_PROBE_USED_PCT=70 state >/dev/null
kill -KILL "$rx_pid"; wait_for 20 dead "$rx_pid"
world_tick 25
release r1
expect_eq "R.6 two runs admitted, the second five seconds into the first" "0 0" "$(rc_of r1) $(rc_of rx)"
expect_regex "R.7 one killed while the other ran overlapped it: the survivor carries 10" \
  '^10:[0-9.]+:30:1030$' "$(tail -n 1 "$BIONIC_GATE_DIR/cost/L")"
expect_eq "R.8 the survivor's gate_end wrote the killed one ended at 1030, rc 137" "1030|137" \
  "$(field "$rx_id" ended)|$(field "$rx_id" rc)"
expect_eq "R.9 gate_list still counts it killed, once" "1" "$(glist | grep -c "^${rx_id:-none} killed ")"
MR="$(mutant reap)"
anchor "$MR" "rc=137\\n'" 1
sed -i.bak "/rc=137\\\\n'/d" "$MR"
learn_run "$MR" reaped-mut 1
expect_regex "R.10 the mutant (no killed-write) still admits both runs and ends the second" \
  '^0 [0-9.]+:30:1090$' "$(rc_of rx) ${LR_LINE#*:}"
expect_regex "R.11 the mutant carries 10 after a kill: the written end is the rule" '^10:' "$LR_LINE"

# ── §ALONE ───────────────────────────────────────────────────────────────────
section "§ALONE — a promise alone never refuses an idle gate; the reading stays the limit (T47; usage row)"
# alone_rows <gate lib> <name> — reading 40, share 80, big promised 45 (so 40 + 45 > 80), small
# promised 3. A big landing asks, then a small work ask behind it. Sets AL_BIG (big's rc),
# AL_WAIT (the small ask while big runs: waiting or served) and AL_SMALL (its rc at the end).
alone_rows() {
  fresh "$2"
  world_machine 8 8192 40 1.0
  world_cost big 45 1.0 60
  world_cost small 3 0.5 20
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
expect_eq "I.1 big alone on an idle gate (reading 40 + promise 45 > share 80): admitted" "0" "$AL_BIG"
expect_eq "I.2 the 3% ask behind it took a number at 1000" "1000" "$(field "$(req_of is)" asked)"
expect_eq "I.3 and waits while big runs (40 + 45 + 3 > 80)" "waiting" "$AL_WAIT"
expect_eq "I.4 once big ends, the 3% ask is admitted" "0" "$AL_SMALL"
fresh alone-new
world_machine 8 8192 40 1.0
world_cost big 45 1.0 60
expect_eq "I.5 a never-seen key on an idle gate, promised the maximum (45): admitted" "0" \
  "$(ask_fg in1 work never-seen 0)"
expect_eq "I.6 its promise is that maximum" "45:1:60" "$(field "$(req_of in1)" promise)"
for rd in 80:0 81:75 85:75; do
  fresh "alone-${rd%%:*}"
  world_machine 8 8192 "${rd%%:*}" 1.0
  world_cost big 45 1.0 60
  expect_eq "I.7 an idle gate reading ${rd%%:*} under share 80: big gets rc ${rd#*:}" "${rd#*:}" \
    "$(ask_fg ir work big 0)"
done
MI="$(mutant alone)"
anchor "$MI" 'if (r >= 0 && !(unf == 0 && fits(r, share))) {' 1
sed -i.bak 's/if (r >= 0 \&\& !(unf == 0 \&\& fits(r, share))) {/if (r >= 0) {/' "$MI"
alone_rows "$MI" alone-mut
expect_eq "I.8 the mutant (no idle clause) still admits the 3% ask" "0" "$AL_SMALL"
expect_eq "I.9 the mutant refuses big alone on an idle gate — the idle clause is the rule" "75" "$AL_BIG"

# ── §OWN ─────────────────────────────────────────────────────────────────────
section "§OWN — a live waiter's number is never taken over (T47; request row)"
# own_rows <gate lib> <name> — reading 30; a holder admitted at 40 (another who); two asks by
# one who (agent twin) for key k (25) while the first still polls. Sets OW_N (requests then),
# OW_FIRST (the first ask's id), OW_STATE (gate_state with both waiting).
own_rows() {
  fresh "$2"
  world_machine 8 8192 30 1.0
  world_cost h 40 0.5 20
  world_cost k 25 0.5 20
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
release oh
wait_for 20 has o1.rc; wait_for 20 has o2.rc
expect_eq "O.5 once the holder ends both are served (30 + 25 + 25 ≤ 80)" "0 0" "$(rc_of o1) $(rc_of o2)"
expect_eq "O.6 each under its own number" "2 3" "$(id_of o1) $(id_of o2)"
expect_contains "O.7 gate_state then counts both admitted, none waiting" "admitted=2 waiting=0 " "$(state)"
touch "$D/o1.go" "$D/o2.go"
fresh own-gave-up
world_machine 8 8192 30 1.0
world_cost h 40 0.5 20
world_cost k 25 0.5 20
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
# cleared_rows <gate lib> <name> — reading 30; a holder admitted at 40; a landing promised 20
# finds no room, returns 75, and its process lives on, polling nothing. Then the holder ends
# and a 5% work ask comes. Sets CL_P (the landing's rc and liveness), CL_ID, CL_STATE (gate_state
# with the holder ended) and CL_Q (the 5% ask's rc).
cleared_rows() {
  local p
  fresh "$2"
  world_machine 8 8192 30 1.0
  world_cost h 40 0.5 20
  world_cost a 20 0.5 20
  world_cost b 5 0.5 20
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
expect_eq "E.4 a later 5% ask is served" "0" "$CL_Q"
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
for m in "2 2048" "8 16384" "64 262144"; do
  set -- $m
  admissions "$1" "$2"
  expect_eq "M.1 the admission rows on a $1-core $2 MB machine: 0 75 0 75" "0 75 0 75" "$ADM"
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
world_cost k.test.sh 10 0.5 30
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
fresh wrap-number
world_machine 8 8192 60 1.0
world_cost h 15 0.5 30
world_cost k.test.sh 15 0.5 30
HOLD=1 ask_bg nh work h 0; wait_for 20 has nh.rc
expect_eq "B.7 the holder is admitted (60 + 15)" "0" "$(rc_of nh)"
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
world_cost k.test.sh 10 0.5 30
expect_eq "B.24 a shim nested in an admitted command runs (both exit 0)" "0" \
  "$(book_fg np --agent np --max-wait 30 --suites k.test.sh -- \
      "bash '$BOOKED' --agent kid --max-wait 30 --suites j.test.sh -- 'touch $D/kid.ran'")"
expect_true "B.25 …its command ran" has kid.ran
expect_eq "B.26 …and it took no number of its own" "1" "$(nreq)"
expect_eq "B.27 the parent's request was ended once, by the parent" "0" "$(field "$(req_of np)" rc)"

# A typed admission from no ancestor, and BIONIC_SLOT_HELD=1, ask anyway.
stranger_rows() {  # <booked> <prefix> — sets ST_RC and ST_RAN for an unbooked caller with no room
  fresh "wrap-stranger-$2"
  world_machine 8 8192 60 1.0
  world_cost h 15 0.5 30
  world_cost k.test.sh 15 0.5 30
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
world_machine 8 8192 60 1.0
world_cost h 15 0.5 30
world_cost k.test.sh 15 0.5 30
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
world_machine 8 8192 60 1.0
world_cost h 15 0.5 30
world_cost k.test.sh 15 0.5 30
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
world_cost k.test.sh 10 0.5 30
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
touch "$D/pk.go"; wait_for 20 has pk.brc
expect_eq "B.43 the run ended 0" "0" "$(brc pk)"
expect_eq "B.44 a reading of 70 taken mid-run by the wrapper is the request's peak" "70" "$(field "$pk_id" peak)"
expect_regex "B.45 …so its cost is the rise 70-40=30, though the end read 40" '^30:' \
  "$(tail -n 1 "$BIONIC_GATE_DIR/cost/k.test.sh" 2>/dev/null)"

finish
