#!/bin/bash
# tests/gate.test.sh — payload/scripts/lib/gate.sh: one gate admits every heavy command on the
# machine's present reading, one core a command, keeping only durations (wave-33 T1; Δ10) (epic-23
# wave-28-finished-work-lands, T2; REQ-2, REQ-4, REQ-7; spec D10, D11, D12; ADR-046).
#
# WHAT IS UNDER TEST. One section per eval the spec names:
#
#   §SHARE     AC-2.1  asks from two fixture projects read one share file; a project's own
#                      config or plan line changes neither; absent or unreadable is 92
#   §WIDTH     D1      the width a whole run takes is the share's room, floored
#   §HARD      AC-2.2  memory planted over the share is not admitted; a busy processor with
#                      nothing admitted is not either; an unknown command or an unknown reading waits for
#                      an idle gate. Mutation: the share's ceiling lifted admits at 85%
#   §ROOM              a promise fades into the load over a minute; the room and an ask agree
#   §LONE              the load falls under waiters with nothing admitted: the order goes first
#   §NOCONST   AC-2.3  the same asks on a 4-core 4 GB and a 32-core 64 GB machine at equal
#                      used percentages decide alike
#   §TWO       AC-2.4  two asks at one instant with room for one: one admitted, one waits on an
#                      unmoved reading; a dead holder's lock is taken over
#   §NUMBER    AC-2.6  an ask whose time runs out exits 75 before --within, having run nothing;
#                      its next ask resumes its number and is served before a later one
#   §RESUME-KIND D8, AC-2.1 (wave-36 T11) a request is resumed only by its who, key and kind once
#                      its holder cleared it; a dead holder's is ended (rc=gone) and the ask takes a
#                      fresh number; gate_end on a never-admitted id is accepted only with --by
#   §WIDTH-ASK AC-6.1  (wave-38 T5; D21, D22) gate_width_ask <landing> on 8 cores at share 92:
#                      load 2.0, nothing admitted, 3; load 6.0, 0 (the limit holds for it too);
#                      a younger landing 0 until the older finishes. The promise is resources.sh's
#                      suite cost, lifted. Mutation: resources.sh's cost set to 1.00 answers 5
#   §LEASE     D22     (wave-38 T30; A-T6-10) a landing whose carrier holds a lease stays the oldest
#                      across its run gaps: a younger landing is answered 0 while the older has
#                      nothing open; closed, the younger is answered by the count; a dead carrier's
#                      lease is pruned; one left WAITING orders no one, keeps its age for the next
#                      open, and is pruned after its span; ties by opening order; a landing with no
#                      lease is ordered as before. open prints the age it gave; `new` takes a
#                      fresh one, an age given is set exactly, seq never repeats (A-orch-49).
#                      Mutation: the lease unread answers 4 in the gap
#   §TERM      AC-6.2  (wave-38 T5) a waiter killed with TERM hands its request back; the row's
#                      next ask resumes its number and asked=. Mutation: the trap removed ends it
#                      rc=gone and files a fresh number (N.12, SIGKILL, unchanged)
#   §WHOLE-HOLDER the tick's whole run (regression@<h8>, budget run.sh) is admitted alone, and waits while a landing runs
#   §COST              a booked run's cores ride its cost line's fourth field, capped at the machine and floored
#                      at 0.1; kept cores promise the key's next ask by the rule its seconds use, three fields the prior
#   §CLASS             a browser or whole ask on a fresh key is promised the room free; a work ask waits beside it
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
# §BUDGET-AT-ASK one (wave-33 T3); §RESUME-KIND one (wave-36 T11), and §OWN's arm reads its
# mutant's new harm: blind to liveness, it ends the live waiter's request (rc=gone).
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

# THE PROMISE, LIFTED (wave-38 T5; D21, AC-6.1; ADR-060). The cores the gate promises one work or
# landing run is resources.sh's measured suite cost, read through its reader here and never
# written as a literal in this suite: a remeasured cost moves every row below with it. `pr <n>`
# prints n promises as the gate prints a sum of them (awk %g).
PROMISE="$( . "$REPO_ROOT/payload/scripts/lib/resources.sh" 2>/dev/null; _res_suite_cores 2>/dev/null )"
pr() { awk -v p="${PROMISE:-0}" -v n="$1" 'BEGIN { printf "%g", p * n }'; }
mkdir -p "$CLAUDE_CONFIG_DIR/bionic"
# Rows that read the share's room whole run with no reserve; the rows that read the reserve set their own.
printf '0\n' > "$CLAUDE_CONFIG_DIR/bionic/reserve"

if [ -r "$GATE" ] && bash -n "$GATE" 2>/dev/null; then
  ok "subject present and parses: payload/scripts/lib/gate.sh"
else
  no "subject present and parses: payload/scripts/lib/gate.sh" "missing or unparseable"
fi
# The lift is proved before any row reads through it: an empty PROMISE would make every promise
# row below compare against nothing.
expect_regex "PR.0 resources.sh's reader names one suite's cost in cores, a positive decimal" \
  '^[0-9]+(\.[0-9]+)?$' "$PROMISE"

# ── fixture helpers ──────────────────────────────────────────────────────────

# asker.sh <dir> <name> <kind> <key> <within> — one asking process. Its id and rc land in
# <dir>/<name>.id and <name>.rc (rc last, so a reader that sees rc sees the id). Env:
#   HOLD=1     once admitted, hold until <dir>/<name>.go, then gate_end <id> 0 (<name>.endrc)
#   CHILD=<n>  once admitted, run asker <n> for the same kind and key as a CHILD of this
#              process, with BIONIC_GATE_ADMIT=<id>, before holding
#   CHILD_ADMIT=<v>  the child's BIONIC_GATE_ADMIT is <v> instead of <id>; `-` leaves it unset
#   ENDFIRST=1 once admitted, gate_end <id> 0 before running CHILD (the admission is over)
#   WORK=<sh>  once admitted, run <sh> as a child before holding (processor time for `times`)
#   PLANT_CPU=[<a>:]<s>  the children's processor time `times` reports at gate_end is <s> seconds (<a> at the ask)
#   CLASS=<c>  ask with --class <c>
#   AGENT=<a>  ask as agent <a> (the who's second half) instead of <name>, so two askers share a who
#   LIVE=1     after a 75, stay alive, polling nothing, until <dir>/<name>.go
# Its own pid is written first, to <name>.pid.
cat > "$WORLD_ROOT/asker.sh" <<'ASKER'
d="$1"; n="$2"; kind="$3"; key="$4"; within="$5"
printf '%s\n' "$$" > "$d/$n.pid"
export BIONIC_GATE_AGENT="${AGENT:-$n}"
. "$GATE_LIB" 2>/dev/null
[ -z "${BUSY_FILE:-}" ] || _res_busy_cores() { cat "$BUSY_FILE"; }   # BUSY_FILE=<f>: a load that can fall under a waiter
case "${PLANT_CPU:-}" in *:*) times() { printf '0m0.00s 0m0.00s\n0m%ss 0m0.00s\n' "${PLANT_CPU%%:*}"; } ;; esac
id="$(gate_ask "$kind" "$key" --within "$within" ${CLASS:+--class "$CLASS"} 2>"$d/$n.err")"; rc=$?
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
[ -z "${PLANT_CPU:-}" ] || times() { printf '0m0.00s 0m0.00s\n0m%ss 0m0.00s\n' "${PLANT_CPU#*:}"; }
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

# The reserve: one core is the person's. The room is share × cores ÷ 100 less it (absent: 1), never under 1.
shr() {  # <share> <reserve|-> — the room over planted files; - leaves no reserve file
  printf '%s\n' "$1" > "$CLAUDE_CONFIG_DIR/bionic/share"; rm -f "$CLAUDE_CONFIG_DIR/bionic/reserve"
  [ "$2" = - ] || printf '%s\n' "$2" > "$CLAUDE_CONFIG_DIR/bionic/reserve"
  ( . "$GATE_LIB" 2>/dev/null; _gate_share_cores )
}
expect_eq "S.19 share 92, reserve 1, 8 cores: 6.36 (7.36 less the person's core)" "6.36" "$(shr 92 1)"
expect_eq "S.20 no reserve file reads the same: the default is 1" "6.36" "$(shr 92 -)"
expect_regex "S.21 gate_state carries reserve=1 after share=" '^share=92 reserve=1 ' "$(shr 92 1 >/dev/null; . "$GATE_LIB" 2>/dev/null; gate_state)"
expect_eq "S.22 reserve 0 leaves the whole share: 7.36" "7.36" "$(shr 92 0)"

# The verb (T10, D16): `session-poker.sh share <n>` writes the file the gate reads. The verb runs under
# the world's own CLAUDE_CONFIG_DIR and a HOME that holds nothing; the gate's asks follow what it wrote.
share_verb() {  # <args...> -> the verb's output; BIONIC_CLAUDE_HOME stays as the caller set it
  ( cd "$D" && env HOME="$WORLD_ROOT/nohome" BIONIC_PLUGINS_DIR="$WORLD_ROOT/no-plugins" \
      bash "$REPO_ROOT/hooks/session-poker.sh" share "$@" 2>&1 )
}
fresh sharev
world_machine 8 8192 55 1.0
world_cost k 30
expect_eq "S.11 the verb prints the share the gate reads (80 from fresh), with the reserve, cores and room" "share=80 reserve=0 cores=8 room=6.4" "$(share_verb)"
expect_eq "S.12 share 50 exits 0 and the gate's share is 50" "0|50" \
  "$(share_verb 50 >/dev/null; echo "$?")|$( . "$GATE_LIB" 2>/dev/null; gate_share )"
expect_eq "S.13 at the set share 50, a reading of 55 is refused (rc 75)" "75" "$(ask_fg v1 work k 0)"
share_verb 80 >/dev/null
expect_eq "S.14 the verb sets it back to 80 and the same ask is admitted (rc 0)" "0" "$(ask_fg v2 work k 0)"
share_verb 101 >/dev/null; S15_RC=$?
expect_eq "S.15 a refused value exits 1 and leaves the file as it was (80)" "1|80" "$S15_RC|$(sed -n 1p "$CLAUDE_CONFIG_DIR/bionic/share")"
expect_eq "S.16 and the verb's print is the gate's (share=80)" "share=$( . "$GATE_LIB" 2>/dev/null; gate_share )" "$(share_verb | cut -d' ' -f1)"
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
expect_eq "WD.7 share 92, reserve 1, 8 cores: 6 workers (6.36, floored)" "6" \
  "$(printf '1\n' > "$CLAUDE_CONFIG_DIR/bionic/reserve"; gw_of 92 8; printf '0\n' > "$CLAUDE_CONFIG_DIR/bionic/reserve")"

# ── §WIDTH-ASK ───────────────────────────────────────────────────────────────
# THE GATE ANSWERS A LANDING'S WIDTH (wave-38 T5; D21, D22; AC-6.1; ADR-060). `gate_width_ask
# <landing>` prints how many runners that landing may start now, one integer: the gate's own
# admission rule applied in sequence from the machine as it stands. b = load_1m plus the fading
# promises of admitted runs and those of waiting landing requests; a run counts while b + PROMISE ≤
# share × cores ÷ 100, each counted run adding PROMISE. PROMISE is resources.sh's measured suite cost,
# lifted at the top of this suite. D22: the oldest active landing (the earliest asked among its
# open requests, which carry `landing=<key>` from BIONIC_GATE_LANDING) is the one answered; any
# other is answered 0 until it finishes; the oldest too is answered 0 while the load leaves no
# room. Planted: 8 cores at share 92, 7.36 cores of room.
section "§WIDTH-ASK — the gate answers how many runners a landing may start (D21, D22; AC-6.1)"
wask() { ( . "$GATE_LIB" 2>/dev/null; o="$(gate_width_ask "$@" 2>/dev/null)"; r=$?; printf '%s|%s' "$o" "$r" ); }
share92w() { printf '92\n' > "$CLAUDE_CONFIG_DIR/bionic/share"; }
# wa_seq <load> <n> — the sums b + PROMISE the rule tests for runs 1..n from an empty store
wa_seq() {
  awk -v p="${PROMISE:-0}" -v l="$1" -v n="$2" 'BEGIN {
    for (k = 1; k <= n; k++) { printf "%s%.2f", (k > 1 ? " " : ""), l + s + p; s += p } }'
}
fresh width-ask
share92w
world_machine 8 8192 30 2.0
expect_eq "WA.1 the gate promises a run resources.sh's suite cost: gate_promise's cores are the lifted PROMISE" \
  "$PROMISE" "$( . "$GATE_LIB" 2>/dev/null; gate_promise k 2>/dev/null | cut -d: -f2 )"
expect_eq "WA.2 load 2.0, nothing admitted ($(wa_seq 2.0 4) against 7.36): answered 3 (answer|rc)" \
  "3|0" "$(wask LA)"
world_machine 8 8192 30 6.0
expect_eq "WA.3 load 6.0, nothing admitted ($(wa_seq 6.0 1) > 7.36): the oldest landing is answered 0, as the rule says" \
  "0|0" "$(wask LA)"
fresh width-ask-two
share92w
world_machine 8 8192 30 2.0
BIONIC_GATE_LANDING=LA HOLD=1 ask_bg la1 landing a.test.sh 0; wait_for 20 has la1.rc
la1_id="$(id_of la1)"
expect_eq "WA.4 precondition: landing LA's run is admitted, tagged landing=LA, promised PROMISE (rc|landing|cores)" \
  "0|LA|$PROMISE" "$(rc_of la1)|$(field "$la1_id" landing)|$(field "$la1_id" promise | cut -d: -f2)"
expect_eq "WA.5 LA, the oldest active landing, one run admitted: answered 2 (its run counts in b, beside the load)" "2|0" "$(wask LA)"
expect_eq "WA.6 LB, younger, is answered 0 while LA is active" "0|0" "$(wask LB)"
world_tick 5
BIONIC_GATE_LANDING=LB HOLD=1 ask_bg lb1 landing b.test.sh 0; wait_for 20 has lb1.rc
expect_eq "WA.7 precondition: a run of LB is admitted beside LA's, asked later (rc|asked LA|asked LB)" \
  "0|1000|1005" "$(rc_of lb1)|$(field "$la1_id" asked)|$(field "$(id_of lb1)" asked)"
expect_eq "WA.8 both active: LA, asked first, is answered by the rule over both runs (1)" "1|0" "$(wask LA)"
expect_eq "WA.9 …and LB, active but younger, is answered 0" "0|0" "$(wask LB)"
release la1
expect_eq "WA.10 once LA has finished, LB is the oldest active landing and is answered by the rule (2)" "2|0" "$(wask LB)"
reap
fresh width-ask-usage
expect_eq "WA.14 no landing key, or a key with a space in it, is a usage error (rc 2 each)" "|2 |2" "$(wask) $(wask 'a b')"
MWA="$(mutant width-ask)"
anchor file payload/scripts/lib/resources.sh 'CORES_PER_SUITE='
sed -i.bak 's/^CORES_PER_SUITE=[0-9.]*/CORES_PER_SUITE=1.00/' "${MWA%/gate.sh}/resources.sh"
fresh width-ask-mut
share92w
world_machine 8 8192 30 2.0
# A fresh bash, so the mutant gate.sh sources the mutant resources.sh beside it: this suite's own
# shell already holds the shipped readers (world.sh), which gate.sh would otherwise keep.
wask_fresh() { bash -c '. "$1" 2>/dev/null; o="$(gate_width_ask LA 2>/dev/null)"; printf "%s|%s" "$o" "$?"' _ "$1"; }
expect_eq "WA.16 the mutant whose resources.sh says one core a suite runs and promises 1.00, as planted (positive)" "1.00" \
  "$(bash -c '. "$1" 2>/dev/null; gate_promise k 2>/dev/null | cut -d: -f2' _ "$MWA")"
expect_eq "WA.17 …and answers 5 at load 2.0, not 3: the answer reads resources.sh's cost" "5|0" "$(wask_fresh "$MWA")"
expect_eq "WA.17b the same fresh shell on the shipped gate answers 3 (the control)" "3|0" "$(wask_fresh "$GATE")"
# NO NUMBER CAPS THE ANSWER: on a machine with room for thousands of runs it is that room, the share's cores over the
# suite cost, whatever that comes to.
fresh width-ask-room
printf '100\n' > "$CLAUDE_CONFIG_DIR/bionic/share"
world_machine 8192 65536 30 0.0
expect_eq "WA.18 share 100 on 8192 cores at load 0: answered the room, 8192 cores over the suite cost" \
  "$(awk -v p="$PROMISE" 'BEGIN { print int(8192 / p) }')|0" "$(wask LA)"


# ── §LEASE ───────────────────────────────────────────────────────────────────
# THE OLDEST LANDING KEEPS ITS PLACE ACROSS ITS RUN GAPS (wave-38 T30; D22; A-T6-10, A-orch-29).
# A landing whose carrier opened a lease (`gate_landing_open <landing> <carrier> [<span>]`) is active
# from that open until its carrier closes it (`gate_landing_close`), whether or not a request of its
# own is open: between its runs, at a pass restart, while its red judge waits, a younger landing is
# answered 0. Leases are ordered by their first-ask instant, ties by the order they were opened. A
# lease whose carrier has died is pruned by the next scan. One its carrier left WAITING
# (`gate_landing_leave`) is nobody's: it orders no one, keeps its first-ask instant for the next open
# of its key, and is pruned once its declared span has passed. A landing with no lease is ordered by
# its open requests, as T5 left it. Planted: 8 cores at share 92 and load 2.0, so a landing with the
# gate to itself is answered 3 (WA.2). The carrier is the suite's own shell, alive for every row.
section "§LEASE — the oldest landing keeps its place across its run gaps (D22; A-T6-10)"
lopen() { ( . "$GATE_LIB" 2>/dev/null; gate_landing_open "$@" >/dev/null 2>&1; printf '%s' "$?" ); }
lleave() { ( . "$GATE_LIB" 2>/dev/null; gate_landing_leave "$@" >/dev/null 2>&1; printf '%s' "$?" ); }
lclose() { ( . "$GATE_LIB" 2>/dev/null; gate_landing_close "$@" >/dev/null 2>&1; printf '%s' "$?" ); }
leasef() { printf '%s/leases/%s.lease\n' "$BIONIC_GATE_DIR" "$(printf '%s' "$1" | tr / %)"; }   # <landing> -> its lease file
lfield() { sed -n "s/^$2=//p" "$(leasef "$1")" 2>/dev/null | tail -n 1; }   # <landing> <field>
lhas() { if [ -e "$(leasef "$1")" ]; then echo yes; else echo no; fi; }   # <landing>
lopenreq() { state | sed -n 's/.* admitted=\([0-9]*\) waiting=\([0-9]*\) .*/\1+\2/p'; }   # open requests, admitted+waiting
LME="$$:$( . "$GATE_LIB" 2>/dev/null; _slots_since "$$" )"
( exit 0 ) & LGONE="$!"; wait "$LGONE" 2>/dev/null
expect_true "LE.0 precondition: the suite's shell is a live carrier with a start time" test -n "${LME#*:}"
expect_true "LE.0b …and the other carrier has exited" dead "$LGONE"
LGONE="$LGONE:0"
fresh lease
share92w
world_machine 8 8192 30 2.0
expect_eq "LE.1 LA's carrier opens its lease: rc 0; the lease names LA, its carrier and its first-ask instant (1000)" \
  "0|LA|$LME|1000" "$(lopen LA "$LME" 600)|$(lfield LA landing)|$(lfield LA carrier)|$(lfield LA first)"
BIONIC_GATE_LANDING=LA HOLD=1 ask_bg le1 landing a.test.sh 0; wait_for 20 has le1.rc
expect_eq "LE.2 precondition: LA's run is admitted; LA is answered 2, LB 0 (T5's rule, LA's run open)" "0 2|0 0|0" \
  "$(rc_of le1) $(wask LA) $(wask LB)"
world_tick 5
release le1
expect_eq "LE.3 precondition: LA's run has ended, so no request is open (admitted+waiting)" "0+0" "$(lopenreq)"
expect_eq "LE.4 THE GAP: LA, between its runs with nothing of its own open, still holds the gate: LB is answered 0" \
  "0|0" "$(wask LB)"
expect_eq "LE.5 …and LA, the oldest, is answered by the count (3)" "3|0" "$(wask LA)"
world_tick 5
expect_eq "LE.6 LB's carrier opens a lease of its own, later (first 1010); LB is still answered 0" "0|1010|0|0" \
  "$(lopen LB "$LME" 600)|$(lfield LB first)|$(wask LB)"
expect_eq "LE.7 a close by a carrier that does not hold LA's lease changes nothing (rc 1, the lease kept)" "1|yes" \
  "$(lclose LA "$LGONE")|$(lhas LA)"
expect_eq "LE.8 LA's carrier closes its lease (published, returned or stalled): rc 0, the file gone" "0|no" \
  "$(lclose LA "$LME")|$(lhas LA)"
expect_eq "LE.9 …LB, now the oldest, is answered by the count" "3|0" "$(wask LB)"
expect_eq "LE.10 …and LA, asking with no lease and nothing open, is answered 0" "0|0" "$(wask LA)"
fresh lease-dead
share92w
world_machine 8 8192 30 2.0
lopen LA "$LGONE" 600 >/dev/null
expect_eq "LE.11 precondition: a lease is on file for LA whose carrier has exited" "yes|$LGONE" "$(lhas LA)|$(lfield LA carrier)"
expect_eq "LE.12 a dead carrier's lease holds nothing: LB is answered by the count" "3|0" "$(wask LB)"
expect_eq "LE.13 …and the scan that answered pruned it" "no" "$(lhas LA)"
fresh lease-wait
share92w
world_machine 8 8192 30 2.0
lopen LA "$LME" 600 >/dev/null
world_tick 10
expect_eq "LE.14 LA's carrier leaves its lease WAITING: rc 0; kept, nobody's, left at 1010, first still 1000" "0|-|1010|1000" \
  "$(lleave LA "$LME")|$(lfield LA carrier)|$(lfield LA left)|$(lfield LA first)"
expect_eq "LE.15 a lease nobody carries orders no one: LB is answered by the count while LA is away" "3|0" "$(wask LB)"
expect_eq "LE.16 …and the scan kept it, within its span" "yes" "$(lhas LA)"
world_tick 10
lopen LB "$LME" 600 >/dev/null
world_tick 10
expect_eq "LE.17 LA's next ready opens it again: rc 0, its carrier the new one, left cleared, first still 1000 (not 1030)" \
  "0|$LME||1000" "$(lopen LA "$LME" 600)|$(lfield LA carrier)|$(lfield LA left)|$(lfield LA first)"
expect_eq "LE.18 …so LA is the oldest again: LA 3, LB (first 1020) 0" "3|0 0|0" "$(wask LA) $(wask LB)"
lleave LA "$LME" >/dev/null
world_tick 601
expect_eq "LE.19 a lease left WAITING longer than its declared span (600 s) frees its place: LB 3, LA's lease pruned" \
  "3|0|no" "$(wask LB)|$(lhas LA)"
expect_eq "LE.20 …so LA's next open takes a fresh first-ask instant (1631), behind LB, and is answered 0" "1631|0|0" \
  "$(lopen LA "$LME" 600 >/dev/null; lfield LA first)|$(wask LA)"
fresh lease-tie
share92w
world_machine 8 8192 30 2.0
lopen LA "$LME" 600 >/dev/null; lopen LB "$LME" 600 >/dev/null
expect_eq "LE.21 two leases opened at one instant: the first opened is the older (order 1 then 2): LA 3, LB 0" \
  "1000 1000 1 2|3|0 0|0" "$(lfield LA first) $(lfield LB first) $(lfield LA seq) $(lfield LB seq)|$(wask LA) $(wask LB)"
fresh lease-mixed
share92w
world_machine 8 8192 30 2.0
BIONIC_GATE_LANDING=LC HOLD=1 ask_bg lc1 landing c.test.sh 0; wait_for 20 has lc1.rc
world_tick 5
lopen LA "$LME" 600 >/dev/null
expect_eq "LE.22 a landing with no lease is ordered by its open requests, as before: LC (asked 1000) answered 2, LA (lease 1005) 0" \
  "0 2|0 0|0" "$(rc_of lc1) $(wask LC) $(wask LA)"
release lc1
expect_eq "LE.23 …and once LC's request has ended, LC is not active: LA answered 3, LC 0" "3|0 0|0" "$(wask LA) $(wask LC)"
reap
fresh lease-usage
expect_eq "LE.24 open with no carrier, open of a key that is not a landing key, close with no key: rc 2 each" "2 2 2" \
  "$(lopen LA) $(lopen 'a b' "$LME") $(lclose)"
# THE AGE (wave-38 T30, A-orch-49): the line hands the gate the age of its entry, so the gate's order
# is the line's. `gate_landing_open` prints the age it gave, `<first>:<seq>`; `new` takes a fresh one
# however a lease of the landing is kept; an age given is set exactly; seq comes from a counter that
# never gives a number twice.
lopen_out() { ( . "$GATE_LIB" 2>/dev/null; gate_landing_open "$@" 2>/dev/null ); }   # <args> -> the age printed
fresh lease-age
share92w
world_machine 8 8192 30 2.0
expect_eq "LE.28 open prints the lease's age, <first>:<seq>" "1000:1" "$(lopen_out LA "$LME" 600)"
world_tick 10
lleave LA "$LME" >/dev/null
world_tick 10
expect_eq "LE.29 open with 'new' takes a fresh age though LA's lease is kept, nobody's: 1020:2, not 1000:1; carried, left cleared" \
  "1020:2|$LME|" "$(lopen_out LA "$LME" 600 new)|$(lfield LA carrier)|$(lfield LA left)"
expect_eq "LE.30 open with an age given sets exactly that age (a line entry's re-entry)" "1000:1|1000|1" \
  "$(lopen_out LA "$LME" 600 1000:1)|$(lfield LA first)|$(lfield LA seq)"
lclose LA "$LME" >/dev/null
expect_eq "LE.31 with every lease closed, a fresh open takes the next seq (3), never one given before" "1020:3" \
  "$(lopen_out LB "$LME" 600)"
expect_eq "LE.32 an age that is not <first>:<seq> or 'new' is a usage error (rc 2), and an empty span is the default" "2 0" \
  "$(lopen LA "$LME" 600 1000) $(lopen LC "$LME" '' new)"

# MUTANT: the width ask reads no lease. The gap is open again: LB is answered by the count while LA is
# between its runs, the harm A-T6-10 found.
MLE="$(mutant lease)"
anchor file payload/scripts/lib/gate.sh '"$_G_LEASE"; } | awk'
sed -i.bak 's/printf .%s. "\$_G_LEASE"; }/}/' "$MLE"
fresh lease-mut
share92w
world_machine 8 8192 30 2.0
wask_m() { bash -c '. "$1" 2>/dev/null; o="$(gate_width_ask "$2" 2>/dev/null)"; printf "%s|%s" "$o" "$?"' _ "$1" "$2"; }   # <gate.sh> <landing>
lopen LA "$LME" 600 >/dev/null
expect_eq "LE.26 the mutant still runs and answers: LA, alone, 3" "3|0" "$(wask_m "$MLE" LA)"
expect_eq "LE.27 MUTANT the lease unread: LB is answered 3 in LA's gap, where the shipped gate answers 0 (the rows can fail)" \
  "3|0 0|0" "$(wask_m "$MLE" LB) $(wask_m "$GATE" LB)"

# ── §HARD ────────────────────────────────────────────────────────────────────
section "§HARD — memory is the hard limit, the processor the soft one (AC-2.2)"
fresh hard
world_machine 8 8192 85 1.0
world_cost k 30
expect_eq "H.1 used 85 under a share of 80, nothing admitted: not admitted (rc 75)" "75" "$(ask_fg h1 work k 0)"
expect_eq "H.3 and holds no admitted line (asked|admitted)" "1000|" "$(field "$(req_of h1)" asked)|$(field "$(req_of h1)" admitted)"
fresh hard2
world_machine 8 8192 30 16
world_cost k 30
ask_bg p1 work k 1; wait_for 20 asked_by p1; world_tick 1
wait_for 20 has p1.rc
expect_eq "H.4 16 busy cores of 8, nothing admitted: the limit holds, it waits out --within 1 (rc 75)" "75" "$(rc_of p1)"
expect_eq "H.5 …its request was taken and holds no admitted line (asked|admitted)" "1000|" "$(field "$(req_of p1)" asked)|$(field "$(req_of p1)" admitted)"
reap
fresh hard3
world_machine 8 8192 30 1.0
HOLD=1 ask_bg u1 work never-seen 0
wait_for 20 has u1.rc
expect_eq "H.6 a command with no cost file anywhere, nothing admitted: admitted" "0" "$(rc_of u1)"
expect_eq "H.7 another unknown command while that one runs is promised the suite cost (wave-33 T1, AC-8.1) and admitted beside it: rc 0" "0" "$(ask_fg u2 work never-seen-2 0)"
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
# processor: 4.0 busy cores, one run held, a second ask (4.0 and two promises > 6.4).
MG="$(mutant ceiling)"
anchor file payload/scripts/lib/gate.sh 'if (r >= 0 && !fits(u, share)) exit 1'
sed -i.bak 's/if (r >= 0 \&\& !fits(u, share)) exit 1/if (r >= 0 \&\& !fits(u, 100)) exit 1/' "$MG"
fresh hard-mut
world_machine 8 8192 85 4.0
world_cost k 30
GATE_LIB="$MG" HOLD=1 ask_bg hm1 work k 0; wait_for 20 has hm1.rc
expect_eq "H.10 the mutant still decides: with one held, a second ask over the processor is refused (rc 75)" "75" \
  "$(GATE_LIB="$MG" ask_fg hm0 work k 0)"
expect_eq "H.11 the mutant admits at 85% used under a share of 80 — the ceiling is the rule" "0" \
  "$(rc_of hm1)"
reap

# A PROMISE FADES INTO THE LOAD: runs admitted at load 0 count whole, five sixths 10 s on, nothing a minute on.
section "§ROOM — a promise fades into the load, read alike by the room and an ask (AC-4.1 to AC-4.3)"
fresh room; world_machine 8 8192 30 0; for n in r1 r2 r3; do HOLD=1 ask_bg "$n" work k 0; wait_for 20 has "$n.rc"; done
room() { ( . "$GATE_LIB" 2>/dev/null; [ -z "${BUSY_FILE:-}" ] || _res_busy_cores() { cat "$BUSY_FILE"; }; gate_room "$@" 2>&1 ) | sed -n 's/^room=\([a-z]*\) .* promised=\([^ ]*\) .*/promised=\2 room=\1/p'; }
world_machine 8 8192 30 2.95; world_clock 1120
expect_eq "RM.1 three admitted ($(rc_of r1)$(rc_of r2)$(rc_of r3)) 120 s ago at $PROMISE, busy 2.95 of 6.4: the load carries them" "promised=0 room=yes" "$(room)"
world_clock 1010; expect_true "RM.2 …admitted 10 s ago, five sixths of $(pr 3), about 4.0, which closes the room ($(room))" awk -v l="$(room)" 'BEGIN { split(l, a, /[= ]/); exit !(a[2] >= 3.9 && a[2] <= 4.1 && a[4] == "no") }'
rm_margin() { world_machine 8 8192 30 "$1"; printf '%s|%s' "$(room --owed 1 | sed 's/.*room=//')" "$(ask_fg "$2" work k 0)"; }   # <busy> <asker> -> room|rc
expect_eq "RM.3 a newcomer at the margin: gate_room --owed 1 and the ask agree, busy 0.8 no and waits, 0.7 yes and admitted" "no|75 yes|0" "$(rm_margin 0.8 r4) $(rm_margin 0.7 r5)"
fresh roomu; world_machine 8 8192 30 0; for n in u1 u2 u3; do HOLD=1 ask_bg "$n" work k 0; wait_for 20 has "$n.rc"; done; world_clock 1030
printf '1.0\n' > "$D/ub"; expect_true "RM.4 control: three admitted 30 s ago at $PROMISE, busy 1.0: half faded, about 2.4 of $(pr 3) ($(BUSY_FILE="$D/ub" room))" \
  awk -v l="$(BUSY_FILE="$D/ub" room)" 'BEGIN { split(l, a, /[= ]/); exit !(a[2] >= 2.3 && a[2] <= 2.5) }'
printf -- '-\n' > "$D/ub"; expect_eq "RM.5 the same three, the busy reading unreadable: every promise counts whole, $(pr 3)" "promised=$(pr 3) room=no" "$(BUSY_FILE="$D/ub" room)"

# NOTHING ADMITTED IS NO EXCEPTION: three asks wait at load 16 on 4 cores at share 80 (3.2); it falls to 1.0, room for one.
section "§LONE — the limit holds with nothing admitted, and the order goes first when the load falls (AC-5.2, AC-5.4)"
fresh lone; world_machine 4 4096 30 16; printf '16\n' > "$D/busy"
for a in w1:work w2:work l1:landing; do BUSY_FILE="$D/busy" BIONIC_GATE_LANDING=LL HOLD=1 ask_bg "${a%:*}" "${a#*:}" "${a%:*}.test.sh" 600; wait_for 20 asked_by "${a%:*}"; world_tick 5; done; sleep 0.3
expect_eq "LO.1 three asks at load 16, nothing admitted: all wait (rc rc rc|asked asked asked)" "none none none|1000 1005 1010" "$(rc_of w1) $(rc_of w2) $(rc_of l1)|$(field "$(req_of w1)" asked) $(field "$(req_of w2)" asked) $(field "$(req_of l1)" asked)"
printf '1.0\n' > "$D/busy.tmp" && mv "$D/busy.tmp" "$D/busy"; wait_for 20 has l1.rc; sleep 0.3
expect_eq "LO.2 the load falls to 1.0: the landing is admitted before the older work asks (l1|w1|w2)" "0|none|none" "$(rc_of l1)|$(rc_of w1)|$(rc_of w2)"
release l1; wait_for 20 has w1.rc; sleep 0.3
expect_eq "LO.3 the landing ended: the lower asked= is admitted and the newer waits (w1|w2)" "0|none" "$(rc_of w1)|$(rc_of w2)"
reap

# ── the admission rows, parameterised by machine (§NOCONST, §MACHINES) ───────
# admissions <cores> <total_mb> — four asks on one machine, every reading a share of the
# machine; sets ADM to the four rcs. (Rows that start background askers never run inside
# `$( )`: a poller started in a subshell would outlive the row unreaped.) Each command is
# promised the suite cost and no memory (wave-33 T1; Δ10), so the readings decide: w2 asks while the
# memory reads 85%, over the share of 80; w4 while the processor reads the share's whole room.
# Expected: 0 75 0 75 (the second over memory, the fourth over the processor while two are
# admitted) on any machine whose share holds a quarter of its cores busy and two promises (6 cores
# and up at 80); on a smaller one the third is refused too, the cost of a fixed promise a command.
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
# hard_rows <cores> <total_mb> — §HARD's two rules on one machine; sets HRD to two rcs (75 75)
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
admissions 6 6144; small="$ADM"
admissions 32 65536; large="$ADM"
hard_rows 4 4096; hsmall="$HRD"
hard_rows 32 65536; hlarge="$HRD"
expect_eq "C.1 a 6-core 6 GB machine decides 0 75 0 75 (4 cores at 80 hold one promise of the suite cost, wave-38 T5)" "0 75 0 75" "$small"
expect_eq "C.2 a 32-core 64 GB machine at the same percentages decides alike" "0 75 0 75" "$large"
expect_eq "C.3 the memory rule on the small machine: 75, then 75 on a processor busy twice over, nothing admitted" "75 75" "$hsmall"
expect_eq "C.4 and alike on the large one" "75 75" "$hlarge"

# ── §TWO ─────────────────────────────────────────────────────────────────────
section "§TWO — several commands never start on one reading (AC-2.4)"
fresh two
# THE ROOM FOR ONE (wave-33 T1; Δ10): every command is promised the suite cost and no memory, so the
# room is the live processor reading's: 4.0 busy cores of the 6.4 the share of 80 allows on 8.
# The first ask (4.0 and one suite cost) is admitted; a second (4.0 and two > 6.4) waits.
world_machine 8 8192 60 4.0
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
# wave-36 T34 (D8, AC-2.1): a lock with no pid is a claim in progress, stale past a few seconds. One
# left by a claimer killed between its mkdir and its pid write (dated 2020 here) was never taken at
# all at 67325f32: _gate_steal made its token INSIDE the lock, which set the lock's age to now, so
# its own recheck read `taking` and the ask failed at the ten-second ceiling.
fresh two-lock-taking
world_machine 8 8192 30 1.0
world_cost k 30
mkdir -p "$BIONIC_GATE_DIR/lock"
touch -t 202001010000 "$BIONIC_GATE_DIR/lock"
expect_false "T.7 the planted lock has no pid (the fixture is the killed claimer's)" test -e "$BIONIC_GATE_DIR/lock/pid"
expect_eq "T.8 a lock left with no pid, long past the bound, is taken over: the ask is decided (rc 0)" "0" "$(ask_fg l1 work k 0)"
expect_false "T.9 and the lock is given back, with no steal token left beside it" \
  bash -c 'test -d "$1/lock" || ls -d "$1"/lock.steal* 2>/dev/null | grep -q .' _ "$BIONIC_GATE_DIR"

# ── §NUMBER ──────────────────────────────────────────────────────────────────
section "§NUMBER — a wait never ends in a kill, and the number holds its turn (AC-2.6)"
fresh number
world_machine 8 8192 60 4.0
world_cost h 30
world_cost k 30
HOLD=1 ask_bg nh work h 0; wait_for 20 has nh.rc
expect_eq "N.1 the holder is admitted (nothing else admitted)" "0" "$(rc_of nh)"
HOLD=1 ask_bg na work k 3
wait_for 20 asked_by na
na_id="$(req_of na)"
expect_eq "N.2 the timed ask took a number at 1000" "1000" "$(field "$na_id" asked)"
world_tick 2; sleep 0.3
expect_false "N.4 at 1002 it is still waiting" has na.rc
world_tick 1
wait_for 20 has na.rc
expect_eq "N.5 at 1003 it exits 75, not 124" "75" "$(rc_of na)"
expect_eq "N.6 nothing ran: its request holds no admitted line (asked|admitted)" "1000|" "$(field "$na_id" asked)|$(field "$na_id" admitted)"
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

# ── §RESUME-KIND ─────────────────────────────────────────────────────────────
section "§RESUME-KIND — the gate ends what it cannot resume (wave-36 T11; D8, AC-2.1; C2, C3)"
# A request is resumed only by the same who, key AND kind, and only one whose holder handed it
# back (holder=-, a 75). A never-admitted request whose holder died (a shim killed in its wait) is
# ended at that who's next ask for the key, `ended=<now> rc=gone`, and the ask gets a fresh
# number: wave-35 saw request 2156 read kind=whole after a work ask resumed it. gate_end on a
# never-admitted id is refused unless the end names who stopped it (`--by`, stop-run's call).
newest_req() { ls "$BIONIC_GATE_DIR/requests" 2>/dev/null | grep '^[0-9][0-9]*$' | sort -n | tail -n 1; }
holder_was() {  # <id> <pid> — the request still names that (dead) pid as its holder
  case "$(field "$1" holder)" in "$2:"*) return 0 ;; esac
  return 1
}
# An asker is killed only once it is PARKED: it said it waits, which gate_ask prints after it unlocks,
# and its poll is 30 s, so the kill lands in its sleep. A SIGKILL inside the lock's claim (mkdir done,
# pid not yet written) leaves a lock no one may steal for a while, and the next ask's --within 0 then
# files nothing: a row about resume must not hang on the lock's own window.
parked() { grep -q 'waits for its turn' "$D/$1.err" 2>/dev/null; }
fresh resume-kind
world_machine 8 8192 60 4.0
world_cost h 30
world_cost k 30
HOLD=1 ask_bg rh work h 0; wait_for 20 has rh.rc
expect_eq "N.12a precondition: a holder is admitted, so a whole ask waits" "0" "$(rc_of rh)"
BIONIC_GATE_POLL=30 AGENT=rk HOLD=1 ask_bg rw whole k 600
wait_for 20 asked_by rk; wait_for 20 parked rw
rw_id="$(req_of rk)"; rw_pid="$(cat "$D/rw.pid" 2>/dev/null)"
expect_eq "N.12b precondition: the whole ask filed a request that waits (kind|admitted)" "whole|" \
  "$(field "$rw_id" kind)|$(field "$rw_id" admitted)"
kill_tree "$rw_pid"; wait "$rw_pid" 2>/dev/null; wait_for 20 dead "$rw_pid"
expect_true "N.12c precondition: its asker is killed and the request still names it as holder" holder_was "$rw_id" "$rw_pid"
AGENT=rk ask_fg rn work k 0 >/dev/null
rn_id="$(newest_req)"
expect_eq "N.12 AC-2.1 a work ask by the same who for the same key, the whole request's holder dead, takes a fresh number" \
  "3 yes" "$(nreq) $([ -n "$rn_id" ] && [ "$rn_id" != "$rw_id" ] && echo yes || echo no)"
expect_eq "N.12d …which reads kind=work, never the dead request's kind" "work" "$(field "$rn_id" kind)"
expect_eq "N.12e the dead holder's request is ended at that ask: ended=<now> rc=gone (ended|rc)" "1000|gone" \
  "$(field "$rw_id" ended)|$(field "$rw_id" rc)"
expect_match "N.12f gate_list reads it ended" "$rw_id ended kind=whole *rc=gone key=k" \
  "$(glist | grep "^$rw_id ")"
# the same kind: a dead holder's request is ended whatever the kind of the next ask
BIONIC_GATE_POLL=30 AGENT=rs HOLD=1 ask_bg rs1 whole k 600
wait_for 20 asked_by rs; wait_for 20 parked rs1
rs_id="$(req_of rs)"; rs_pid="$(cat "$D/rs1.pid" 2>/dev/null)"
kill_tree "$rs_pid"; wait "$rs_pid" 2>/dev/null; wait_for 20 dead "$rs_pid"
expect_true "N.12g precondition: a second whole ask's asker is killed, its request names it" holder_was "$rs_id" "$rs_pid"
AGENT=rs ask_fg rs2 whole k 0 >/dev/null
expect_eq "N.12h the same whole ask by that who takes a fresh number too, and the dead one reads rc=gone (requests|rc|new kind)" \
  "5|gone|whole" "$(nreq)|$(field "$rs_id" rc)|$(field "$(newest_req)" kind)"
# cleared_kind_rows <gate lib> <name> — a whole ask returned 75 (holder cleared), then a work
# ask, then a whole ask, all by one who for one key, a holder admitted throughout. Sets CK_ID (the
# cleared request), CK_N1 (requests after the work ask), CK_W (the work ask's request), CK_N2
# (requests after the second whole ask).
cleared_kind_rows() {
  fresh "$2"
  world_machine 8 8192 60 4.0
  world_cost h 30
  world_cost k 30
  GATE_LIB="$1" HOLD=1 ask_bg ch work h 0; wait_for 20 has ch.rc
  GATE_LIB="$1" AGENT=rc ask_fg rc1 whole k 0 >/dev/null
  CK_ID="$(req_of rc)"
  GATE_LIB="$1" AGENT=rc ask_fg rc2 work k 0 >/dev/null
  CK_N1="$(nreq)"; CK_W="$(newest_req)"
  GATE_LIB="$1" AGENT=rc ask_fg rc3 whole k 0 >/dev/null
  CK_N2="$(nreq)"
}
cleared_kind_rows "$GATE" resume-cleared
expect_eq "N.12i precondition: the whole ask returned 75 and its request is nobody's (rc|kind|holder)" "75|whole|-" \
  "$(rc_of rc1)|$(field "$CK_ID" kind)|$(field "$CK_ID" holder)"
expect_eq "N.12j a work ask by the same who for the same key does not resume the cleared whole request: a fresh number, kind=work" \
  "3 work" "$CK_N1 $(field "$CK_W" kind)"
expect_eq "N.12k …and the cleared request is left as it was: kind=whole, holder -, no ended line (kind|holder|ended)" "whole|-|" \
  "$(field "$CK_ID" kind)|$(field "$CK_ID" holder)|$(field "$CK_ID" ended)"
expect_eq "N.12l the who's next whole ask resumes the cleared number: no new request" "3" "$CK_N2"
# gate_end on a never-admitted id: refused from a caller that never asked, accepted from stop-run's call
GE_OUT="$( . "$GATE" 2>/dev/null; gate_end "$CK_W" 143 2>&1; echo "rc=$?")"
expect_eq "N.12m gate_end on a never-admitted id with no --by is refused (rc 2), as before" "rc=2" "${GE_OUT##*$'\n'}"
expect_contains "N.12n …saying it was never admitted, and writes no end" "was never admitted" "$GE_OUT"
expect_eq "N.12o …the request holds no ended line" "" "$(field "$CK_W" ended)"
GE_OUT="$( . "$GATE" 2>/dev/null; gate_end "$CK_W" 143 --by "$WORLD_SID" --why 'parked by a test' 2>&1; echo "rc=$?")"
expect_eq "N.12p gate_end <id> 143 --by <sid> --why <reason> on a never-admitted id is accepted (rc 0)" "rc=0" "${GE_OUT##*$'\n'}"
expect_eq "N.12q …and writes the end with who stopped it and why (ended|rc|by|why)" "1000|143|$WORLD_SID|parked by a test" \
  "$(field "$CK_W" ended)|$(field "$CK_W" rc)|$(field "$CK_W" by)|$(field "$CK_W" why)"
MK="$(mutant resume-kind)"
anchor file payload/scripts/lib/gate.sh 'elif [ -z "$_GATE_ID" ] && [ "$_R_kind" = "$1" ]; then'
sed -i.bak 's/ \&\& \[ "\$_R_kind" = "\$1" \]; then$/; then/' "$MK"
cleared_kind_rows "$MK" resume-cleared-mut
expect_eq "N.12r the mutant (no kind test on resume) still files the whole ask's request" "whole" "$(field "$CK_ID" kind)"
expect_eq "N.12s the mutant hands the work ask the cleared whole request — the kind test is the rule" "2" "$CK_N1"

# ── §TERM ────────────────────────────────────────────────────────────────────
# A WAITER KILLED WITH TERM KEEPS ITS NUMBER (wave-38 T5; AC-6.2; ADR-060). The drain stops a
# runner with TERM to it and to every descendant, the tree read first (line.sh `_line_kill_tree`).
# A runner still in gate_ask's wait used to die with its holder line naming its dead pid, so its
# who's next ask ended it rc=gone and took a fresh number, the youngest. gate_ask now traps TERM
# while it waits: it hands the request back (holder=-, as a 75 does) and then dies of the TERM as
# before, so the row's next ask under the same key and kind resumes the number and its asked=.
# SIGKILL runs no trap: §RESUME-KIND's N.12 rows pin, unchanged, that such a request is ended
# rc=gone. The mutant with the trap's line removed shows the old harm on the same fixture.
section "§TERM — a waiter killed with TERM keeps its number for the row's next ask (AC-6.2)"
term_tree() {  # <pid> — TERM to the pid, then to every descendant, the tree read before the first kill
  local all="$1" front="$1" next p
  while [ -n "$front" ]; do
    next=""
    for p in $front; do next="$next $(pgrep -P "$p" 2>/dev/null | tr '\n' ' ')"; done
    front="$(echo $next)"; all="$all $front"
  done
  for p in $all; do kill -TERM "$p" 2>/dev/null; done
}
handed_back() { [ "$(field "$1" holder)" = - ]; }
holder_as() {  # <id> <pid> — `asker` when the request's holder is that pid, else its holder as written
  case "$(field "$1" holder)" in "$2:"*) echo asker ;; *) field "$1" holder ;; esac
}
# term_rows <gate lib> <name> — a holder admitted; landing ask tl1 (who tl, key k) parked; its tree
# TERMed; five seconds on, the same who asks again (tl2). Sets TR_ID, TR_PRE (holder rc|kind|admitted|
# whose holder), TR_BACK (holder|ended|admitted after the TERM), TR_NEXT (requests|asked|rc of TR_ID
# after the next ask) and TR_ADM (tl2's rc|id once the holder ends).
term_rows() {
  local pid
  fresh "$2"
  world_machine 8 8192 60 4.0
  world_cost h 30
  world_cost k 30
  GATE_LIB="$1" HOLD=1 ask_bg th work h 0; wait_for 20 has th.rc
  GATE_LIB="$1" AGENT=tl HOLD=1 ask_bg tl1 landing k 600
  wait_for 20 asked_by tl; wait_for 20 parked tl1
  TR_ID="$(req_of tl)"; pid="$(cat "$D/tl1.pid" 2>/dev/null)"
  TR_PRE="$(rc_of th)|$(field "$TR_ID" kind)|$(field "$TR_ID" admitted)|$(holder_as "$TR_ID" "$pid")"
  term_tree "$pid"; wait "$pid" 2>/dev/null; wait_for 20 dead "$pid"
  wait_for 5 handed_back "$TR_ID"
  TR_BACK="$(holder_as "$TR_ID" "$pid")|$(field "$TR_ID" ended)|$(field "$TR_ID" admitted)"
  world_tick 5
  GATE_LIB="$1" AGENT=tl HOLD=1 ask_bg tl2 landing k 600
  wait_for 20 has tl2.pid
  wait_for 20 tl2_placed
  TR_NEXT="$(nreq)|$(field "$TR_ID" asked)|$(field "$TR_ID" rc)"
  release th
  wait_for 20 has tl2.rc
  TR_ADM="$(rc_of tl2)|$(id_of tl2)"
  touch "$D/tl2.go"; wait_for 20 has tl2.endrc
}
tl2_placed() { resumed "$TR_ID" tl2 || nreq_is 3; }
term_rows "$GATE" term
expect_eq "TM.1 precondition: a holder is admitted and the landing's run waits, held by its asker (rc|kind|admitted|holder)" \
  "0|landing||asker" "$TR_PRE"
expect_eq "TM.2 killed with TERM, the waiter hands its request back cleanly: holder -, no ended line, nothing admitted" \
  "-||" "$TR_BACK"
expect_eq "TM.3 the row's next ask under the same key and kind resumes it: no new request, asked kept (requests|asked|rc)" \
  "2|1000|" "$TR_NEXT"
expect_eq "TM.4 when room appears it is admitted under its first number" "0|${TR_ID:-none}" "$TR_ADM"
MTM="$(mutant term)"
anchor file payload/scripts/lib/gate.sh "trap '_GATE_TERMED=1' TERM"
sed -i.bak "/trap '_GATE_TERMED=1' TERM/d" "$MTM"
term_rows "$MTM" term-mut
expect_eq "TM.5 the mutant without the trap runs: its holder is admitted and its landing waits (positive)" \
  "0|landing||asker" "$TR_PRE"
expect_eq "TM.6 …killed with TERM its request still names the dead asker" "asker||" "$TR_BACK"
expect_eq "TM.7 …so the next ask ends it rc=gone and takes a fresh number — the trap is the rule" \
  "3|1000|gone" "$TR_NEXT"
reap

section "§WHOLE-HOLDER — the tick's whole run, held by regression@<h8> with budget run.sh, is admitted alone when nothing is unfinished and waits while a landing runs"
# The tick starts the regression as the roster object `regression@<h8>`, a row whose one suite is
# run.sh, and the runner it starts asks the gate kind whole, as booked.sh spells the name
# (`regression_<h8>`). FIXTURE FIDELITY: a real repository holding this session's roster, the rows
# from the production writer (roster_row_fixture); the askers are real processes asking from inside
# it, so the budget is read where the gate reads it. fails-when: the budget does not read the row by
# the name booked.sh spells, a whole run is admitted beside another run, or a whole run passes a
# landing that is still running.
fresh whole-holder
world_machine 8 8192 30 0.3
world_cost h 30
world_cost k 30
WH_P="$D/proj"; mkdir -p "$WH_P/.bionic/tmp"; git -C "$WH_P" init -q
{ roster_header
  roster_row_fixture session="$WORLD_SID" status=run name=regression@0123abcd agent_id= subagent_type=bionic:test-runner \
    suites_allowed=run.sh suites_source=DECLARED waiver="a whole run the tick started"
  roster_row_fixture session="$WORLD_SID" status=run name=regression@89abcdef agent_id= subagent_type=bionic:test-runner \
    suites_allowed=a.test.sh suites_source=DECLARED waiver="a whole run the tick started"
} > "$WH_P/.bionic/tmp/roster-$WORLD_SID.state"
WH_HERE="$(pwd -P)"; cd "$WH_P" || exit 1
AGENT=regression_0123abcd HOLD=1 ask_bg wh1 whole tests/run.sh 0; wait_for 20 has wh1.rc
expect_eq "WH.1 nothing unfinished: regression@<h8>'s whole ask under budget run.sh is admitted (rc|kind)" \
  "0|whole" "$(rc_of wh1)|$(field "$(id_of wh1)" kind)"
expect_eq "WH.2 …alone: a work ask beside it waits, and its request is filed (rc|filed)" "75|yes" \
  "$(ask_fg wx work h 0 | tail -n 1)|$(asked_by wx && echo yes || echo no)"
release wh1
HOLD=1 ask_bg wl landing k 0; wait_for 20 has wl.rc
expect_eq "WH.3-pre a landing is admitted and still running" "0" "$(rc_of wl)"
AGENT=regression_0123abcd ask_fg wh2 whole tests/run.sh 0 >/dev/null
expect_eq "WH.3 while the landing runs the whole ask is not admitted: it waits its turn, its request filed kind whole (rc|kind)" \
  "75|whole" "$(rc_of wh2)|$(field "$(newest_req)" kind)"
expect_absent "WH.3b …a wait for room, not the budget's refusal" "not on regression_0123abcd's budget" "$(cat "$D/wh2.err" 2>/dev/null)"
release wl
AGENT=regression_0123abcd ask_fg wh3 whole tests/run.sh 0 >/dev/null
expect_eq "WH.4 the landing ended: the same whole ask is admitted" "0" "$(rc_of wh3)"
( . "$GATE_LIB" 2>/dev/null; gate_end "$(id_of wh3)" 0 ) >/dev/null 2>&1
AGENT=regression_89abcdef ask_fg wb whole tests/run.sh 0 >/dev/null
expect_eq "WH.5 control: an object whose budget does not name run.sh is refused its whole run (75)" "75" "$(rc_of wb)"
expect_contains "WH.5b …by the budget, naming the object as booked.sh spells it" \
  "a whole run is not on regression_89abcdef's budget" "$(cat "$D/wb.err" 2>/dev/null)"
cd "$WH_HERE" || exit 1
reap

# ── §COST ───────────────────────────────────────────────────────────────────
# A RUN'S CORES RIDE ITS COST LINE. gate_end reads `times` in the holder's own shell and writes
# <seconds>:<epoch>:<load>:<cores>, the children's processor seconds over the wall seconds, capped at the
# machine and floored at 0.1; the next ask for the key is promised the kept cores by the rule its seconds
# use, and a key whose lines carry none its prior. The booked run moves the planted clock one second
# itself, so its wall seconds are exact and its processor time is the loop's.
section "§COST — a run's cores ride its cost line, and the next ask is promised them (AC-3.1 to AC-3.5)"
fresh cost; world_machine 8 8192 30 0; CO_D="$D/proj"; mkdir -p "$CO_D"
CO_CMD='i=0; while [ $i -lt 400000 ]; do i=$((i+1)); done; printf "1001\n" > "$BIONIC_NOW_FILE.t" && mv "$BIONIC_NOW_FILE.t" "$BIONIC_NOW_FILE"'
( cd "$CO_D" && bash "$REPO_ROOT/payload/scripts/booked.sh" --suites cpu.test.sh -- "$CO_CMD" ) >/dev/null 2>&1
expect_true "CO.1 booked.sh over a loop of about a processor-second, one second long, writes a fourth field of at least 0.5 ($(cat "$(costf cpu.test.sh "$CO_D")" 2>/dev/null))" \
  awk -F: 'END { exit !(NR == 1 && NF == 4 && $1 == 1 && $4 + 0 >= 0.5) }' "$(costf cpu.test.sh "$CO_D")"
world_cost_cores k 30 5.8 6.0 13.0
printf '30:1000:1\n30:1001:1\n30:1002:1\n' > "$(costf old)"
expect_eq "CO.2 kept cores 5.8, 6.0 and 13.0 promise 6.0, the largest at or under twice their median; three-field lines promise the prior, their seconds read" \
  "0:6.0:30 0:$PROMISE:30" "$( . "$GATE_LIB" 2>/dev/null; echo "$(gate_promise k) $(gate_promise old)" )"
world_clock 1000; for co in 400:p1 0.01:p2; do PLANT_CPU="${co%:*}" HOLD=1 ask_bg "${co#*:}" work "${co#*:}" 0; wait_for 20 has "${co#*:}.rc"; world_tick 10; release "${co#*:}"; done
expect_eq "CO.3 a planted 400 s of processor over 10 s on 8 cores writes 8, the machine; 0.01 s writes 0.1, the floor" \
  "10:1010:0:8 10:1020:0:0.1" "$(cat "$(costf p1)") $(cat "$(costf p2)")"
PLANT_CPU=30:40 HOLD=1 ask_bg p3 work p3 0; wait_for 20 has p3.rc; world_tick 10; release p3
expect_eq "CO.4 30 s at the ask and 40 s at the end over 10 s writes 1: the polls before admission are not the run's" "10:1030:0:1" "$(cat "$(costf p3)")"
printf '92\n' > "$CLAUDE_CONFIG_DIR/bionic/share"; printf '1\n' > "$CLAUDE_CONFIG_DIR/bionic/reserve"; world_cost_cores hv 30 7.5 7.5 7.5; world_cost_cores m3 30 3.0 3.0 3.0
ask_fg c5a work hv 0 >/dev/null; ask_fg c5b work m3 0 >/dev/null; world_machine 8 8192 30 2.0; ask_fg c5c work hv 0 >/dev/null
expect_eq "CO.5 kept 7.5 past share 92 reserve 1 (6.36) is admitted on the room free, 6 at busy 0 and 4 at busy 2.0; kept 3.0 promises 3.0 (rc|promise)" \
  "0|0:6:30 0|0:4:30 0|0:3.0:30" "$(for a in c5a c5c c5b; do printf '%s|%s ' "$(rc_of $a)" "$(field "$(id_of $a)" promise)"; done | sed 's/ $//')"
world_machine 8 8192 30 0; sv() { ( set -u; . "$GATE_LIB" 2>/dev/null; gate_promise hv; [ -z "${1:-}" ] || echo "$1" >&2 ) 2>"$D/pr.err"; }   # a caller that never scanned
expect_eq "CO.5b gate_promise under set -u on kept 7.5 prints the bounded promise and nothing on stderr (promise|stderr)" "0:6:30|" "$(sv)|$(cat "$D/pr.err")"
expect_eq "CO.5c …and the stderr read is not vacuous: a planted line reads back (promise|stderr)" "0:6:30|planted" "$(sv planted)|$(cat "$D/pr.err")"
world_machine 8 8192 30 0.5; HOLD=1 ask_bg c6h work hv 99999; wait_for 5 has c6h.rc; world_tick 120
expect_eq "CO.6 a light key asked behind it while it holds, its promise a minute old, is admitted (heavy|light rc)" "0|0" "$(rc_of c6h)|$(ask_fg c6l work lt 0 | tail -n 1)"
reap

# ── §CLASS ───────────────────────────────────────────────────────────────────
# A BROWSER OR COMPILE RUN, OR A WHOLE ONE, IS PROMISED THE ROOM FREE AT ADMISSION until its key has a
# measurement: max(1, floor(share cores - busy - faded)), 6.36 at share 92 and reserve 1 on 8 cores.
section "§CLASS — a browser run is promised the free room, and a work ask waits beside it (AC-2.1, AC-2.2, AC-3.3)"
fresh class; printf '92\n' > "$CLAUDE_CONFIG_DIR/bionic/share"; printf '1\n' > "$CLAUDE_CONFIG_DIR/bionic/reserve"
world_machine 8 8192 30 2.0
CLASS=browser ask_fg cb1 work pw 0 >/dev/null; ask_fg cw1 whole tests/run.sh 0 >/dev/null
expect_eq "CL.1 at busy 2.0, nothing admitted, a browser ask on a fresh key and a whole ask are promised the free room, 4 (rc|class|promise ×2)" \
  "0|browser|0:4:0 0|0:4:0" "$(rc_of cb1)|$(field "$(id_of cb1)" class)|$(field "$(id_of cb1)" promise) $(rc_of cw1)|$(field "$(id_of cw1)" promise)"
world_machine 8 8192 30 0; world_tick 120
CLASS=browser HOLD=1 ask_bg cb2 work pw 0; wait_for 20 has cb2.rc
expect_eq "CL.2 at busy 0 the browser ask is promised the width, 6, and a work ask beside it waits (rc|promise|work rc)" \
  "0|0:6:0|75" "$(rc_of cb2)|$(field "$(id_of cb2)" promise)|$(ask_fg cw2 work k 0 | tail -n 1)"
printf '0\n' > "$CLAUDE_CONFIG_DIR/bionic/reserve"
reap

finish
