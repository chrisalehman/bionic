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
#   §RESUME-KIND D8, AC-2.1 (wave-36 T11) a request is resumed only by its who, key and kind once
#                      its holder cleared it; a dead holder's is ended (rc=gone) and the ask takes a
#                      fresh number; gate_end on a never-admitted id is accepted only with --by
#   §WIDTH-ASK AC-6.1  (wave-38 T5; D21, D22) gate_width_ask <landing> on 8 cores at share 92:
#                      load 2.0, nothing admitted, 4; load 6.0, 1 (the oldest landing progresses);
#                      a younger landing 0 until the older finishes; a landing with its own run
#                      open is answered by the rule alone. The promise is resources.sh's suite
#                      cost, lifted. Mutation: resources.sh's cost set to 1.00 answers 7
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
#   §ROBUST    D21     (wave-38 T31; A-orch-43) a suite's promised seconds are robust to one
#                      contended run: with three kept durations the largest at or below twice
#                      their median (285, 300, 1775 promises 300, and `_line_time_for` fits it in
#                      1700); with fewer, the largest (1775 alone promises 1775)
#   §PROMISE   D11, AC-4.1 (wave-39 T8) the promise carries its load: three cost lines at load 1.5 asked at
#                      load 6 promise the median × 4 bounded by the largest kept; at 1.5 the median; the factor
#                      clamped to 0.5..4, a load below one counted as one; a line with no load, or a load now that
#                      cannot be read, is §ROBUST's promise; the admission's promise= and load=, the cost line it
#                      writes, `_line_time_for` and `_line_time_why` read the one figure. Mutation: every factor 1
#   §FINISHED  D22, AC-6.2 (wave-38 T31; A-orch-43) a landing's request records the row's window
#                      (its lease's span) and its landing record at ask, and when it was handed back;
#                      the scan ends a handed-back request whose row's record shows published,
#                      returned or stalled after its ask (why=row-finished), or whose holder has been
#                      gone longer than its window, 1800 s with none recorded (why=holder-gone), a
#                      landing request naming no landing by the window alone; a live waiter, one
#                      gone 10 s (AC-6.2's killed waiter), and a writer's work request are kept. Its
#                      landing record is written by line.sh's own `line_event` (wave-39 T17; AC-12.1)
#   §KEY       D18, AC-12.1 (wave-39 T17) one landing-key alphabet, line.sh `landing_key`: a multibyte row is
#                      written `_` a byte under every locale; the gate's row sanitiser and line.sh's key agree
#                      on it across locales; the gate's validator accepts exactly what landing_key leaves alone
#   §RECORD    D18, AC-12.1 (wave-39 T17) the gate reads the landing record through line.sh's reader, by
#                      name: published, returned and stalled finish a row, ready and verdict do not, each line
#                      written by `line_event`. Mutation: the writer moves ev= to the end of its fields, and the
#                      gate still reads the row finished
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
#                      <seconds>:<epoch>:<load> (wave-39 T8), three kept; the promise is the suite cost, no memory and the
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
#                      records its seconds unmarked; a never-seen key is promised the suite cost and
#                      an owed writer charged one, before and after a whole run; its next ask
#                      waits while another is held and is admitted once nothing is
#   §ONE-CORE  AC-8.1  (wave-33 T1) a command is promised the suite cost whatever is on record (the
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
#   §ROOM      AC-2.5  gate_room (T13, D14): a five-minute load over the share, promised work
#                      not yet showing and memory over the share each give no room; a waiting
#                      request alone gives room (wave-38 T5, D21); a quiet machine gives room;
#                      two asks on one reading give room once; gate_state prints the loads where
#                      clears= stood. Mutations: the waiting clause put back, the owed count, the
#                      five-minute reading
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

# ── §WIDTH-ASK ───────────────────────────────────────────────────────────────
# THE GATE ANSWERS A LANDING'S WIDTH (wave-38 T5; D21, D22; AC-6.1; ADR-060). `gate_width_ask
# <landing>` prints how many runners that landing may start now, one integer: the gate's own
# admission rule applied in sequence from the machine as it stands. b = max(load_1m, the promises
# of admitted runs and of waiting landing requests); a run counts while b + PROMISE ≤ share ×
# cores ÷ 100, each counted run adding PROMISE. PROMISE is resources.sh's measured suite cost,
# lifted at the top of this suite. D22: the oldest active landing (the earliest asked among its
# open requests, which carry `landing=<key>` from BIONIC_GATE_LANDING) is the one answered; any
# other is answered 0 until it finishes; the oldest is answered at least 1 while nothing of its
# own is open, so a landing always progresses. Planted: 8 cores at share 92, 7.36 cores of room.
section "§WIDTH-ASK — the gate answers how many runners a landing may start (D21, D22; AC-6.1)"
wask() { ( . "$GATE_LIB" 2>/dev/null; o="$(gate_width_ask "$@" 2>/dev/null)"; r=$?; printf '%s|%s' "$o" "$r" ); }
share92w() { printf '92\n' > "$CLAUDE_CONFIG_DIR/bionic/share"; }
# wa_seq <load> <n> — the sums b + PROMISE the rule tests for runs 1..n from an empty store
wa_seq() {
  awk -v p="${PROMISE:-0}" -v l="$1" -v n="$2" 'BEGIN {
    for (k = 1; k <= n; k++) { b = l; if (s > b) b = s; printf "%s%.2f", (k > 1 ? " " : ""), b + p; s += p } }'
}
fresh width-ask
share92w
world_machine 8 8192 30 2.0
expect_eq "WA.1 the gate promises a run resources.sh's suite cost: gate_promise's cores are the lifted PROMISE" \
  "$PROMISE" "$( . "$GATE_LIB" 2>/dev/null; gate_promise k 2>/dev/null | cut -d: -f2 )"
expect_eq "WA.2 load 2.0, nothing admitted ($(wa_seq 2.0 5) against 7.36): answered 4 (answer|rc)" \
  "4|0" "$(wask LA)"
world_machine 8 8192 30 6.0
expect_eq "WA.3 load 6.0, nothing admitted ($(wa_seq 6.0 1) > 7.36: 0 by the rule): the oldest landing is answered 1" \
  "1|0" "$(wask LA)"
fresh width-ask-two
share92w
world_machine 8 8192 30 2.0
BIONIC_GATE_LANDING=LA HOLD=1 ask_bg la1 landing a.test.sh 0; wait_for 20 has la1.rc
la1_id="$(id_of la1)"
expect_eq "WA.4 precondition: landing LA's run is admitted, tagged landing=LA, promised PROMISE (rc|landing|cores)" \
  "0|LA|$PROMISE" "$(rc_of la1)|$(field "$la1_id" landing)|$(field "$la1_id" promise | cut -d: -f2)"
expect_eq "WA.5 LA, the oldest active landing, one run admitted: answered 3 (its run counts in b)" "3|0" "$(wask LA)"
expect_eq "WA.6 LB, younger, is answered 0 while LA is active" "0|0" "$(wask LB)"
world_tick 5
BIONIC_GATE_LANDING=LB HOLD=1 ask_bg lb1 landing b.test.sh 0; wait_for 20 has lb1.rc
expect_eq "WA.7 precondition: a run of LB is admitted beside LA's, asked later (rc|asked LA|asked LB)" \
  "0|1000|1005" "$(rc_of lb1)|$(field "$la1_id" asked)|$(field "$(id_of lb1)" asked)"
expect_eq "WA.8 both active: LA, asked first, is answered by the rule over both runs (2)" "2|0" "$(wask LA)"
expect_eq "WA.9 …and LB, active but younger, is answered 0" "0|0" "$(wask LB)"
release la1
expect_eq "WA.10 once LA has finished, LB is the oldest active landing and is answered by the rule (3)" "3|0" "$(wask LB)"
expect_eq "WA.11 …and LA, now asking after LB, is answered 0" "0|0" "$(wask LA)"
world_machine 8 8192 30 6.0
expect_eq "WA.12 load 6.0 with LB's own run admitted: LB is answered 0 — it is progressing, so no runner joins the queue" \
  "0|0" "$(wask LB)"
release lb1
expect_eq "WA.13 …and with nothing of its own open, load 6.0, it is answered 1 again" "1|0" "$(wask LB)"
reap
fresh width-ask-usage
expect_eq "WA.14 no landing key is a usage error (rc 2)" "|2" "$(wask)"
expect_eq "WA.15 a key with a space in it is a usage error (rc 2)" "|2" "$(wask 'a b')"
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
expect_eq "WA.17 …and answers 7 at load 2.0, not 4: the answer reads resources.sh's cost" "7|0" "$(wask_fresh "$MWA")"
expect_eq "WA.17b the same fresh shell on the shipped gate answers 4 (the control)" "4|0" "$(wask_fresh "$GATE")"


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
# gate to itself is answered 4 (WA.2). The carrier is the suite's own shell, alive for every row.
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
expect_eq "LE.2 precondition: LA's run is admitted; LA is answered 3, LB 0 (T5's rule, LA's run open)" "0 3|0 0|0" \
  "$(rc_of le1) $(wask LA) $(wask LB)"
world_tick 5
release le1
expect_eq "LE.3 precondition: LA's run has ended, so no request is open (admitted+waiting)" "0+0" "$(lopenreq)"
expect_eq "LE.4 THE GAP: LA, between its runs with nothing of its own open, still holds the gate: LB is answered 0" \
  "0|0" "$(wask LB)"
expect_eq "LE.5 …and LA, the oldest, is answered by the count and the floor (4)" "4|0" "$(wask LA)"
world_tick 5
expect_eq "LE.6 LB's carrier opens a lease of its own, later (first 1010); LB is still answered 0" "0|1010|0|0" \
  "$(lopen LB "$LME" 600)|$(lfield LB first)|$(wask LB)"
expect_eq "LE.7 a close by a carrier that does not hold LA's lease changes nothing (rc 1, the lease kept)" "1|yes" \
  "$(lclose LA "$LGONE")|$(lhas LA)"
expect_eq "LE.8 LA's carrier closes its lease (published, returned or stalled): rc 0, the file gone" "0|no" \
  "$(lclose LA "$LME")|$(lhas LA)"
expect_eq "LE.9 …LB, now the oldest, is answered by the count" "4|0" "$(wask LB)"
expect_eq "LE.10 …and LA, asking with no lease and nothing open, is answered 0" "0|0" "$(wask LA)"
fresh lease-dead
share92w
world_machine 8 8192 30 2.0
lopen LA "$LGONE" 600 >/dev/null
expect_eq "LE.11 precondition: a lease is on file for LA whose carrier has exited" "yes|$LGONE" "$(lhas LA)|$(lfield LA carrier)"
expect_eq "LE.12 a dead carrier's lease holds nothing: LB is answered by the count" "4|0" "$(wask LB)"
expect_eq "LE.13 …and the scan that answered pruned it" "no" "$(lhas LA)"
fresh lease-wait
share92w
world_machine 8 8192 30 2.0
lopen LA "$LME" 600 >/dev/null
world_tick 10
expect_eq "LE.14 LA's carrier leaves its lease WAITING: rc 0; kept, nobody's, left at 1010, first still 1000" "0|-|1010|1000" \
  "$(lleave LA "$LME")|$(lfield LA carrier)|$(lfield LA left)|$(lfield LA first)"
expect_eq "LE.15 a lease nobody carries orders no one: LB is answered by the count while LA is away" "4|0" "$(wask LB)"
expect_eq "LE.16 …and the scan kept it, within its span" "yes" "$(lhas LA)"
world_tick 10
lopen LB "$LME" 600 >/dev/null
world_tick 10
expect_eq "LE.17 LA's next ready opens it again: rc 0, its carrier the new one, left cleared, first still 1000 (not 1030)" \
  "0|$LME||1000" "$(lopen LA "$LME" 600)|$(lfield LA carrier)|$(lfield LA left)|$(lfield LA first)"
expect_eq "LE.18 …so LA is the oldest again: LA 4, LB (first 1020) 0" "4|0 0|0" "$(wask LA) $(wask LB)"
lleave LA "$LME" >/dev/null
world_tick 601
expect_eq "LE.19 a lease left WAITING longer than its declared span (600 s) frees its place: LB 4, LA's lease pruned" \
  "4|0|no" "$(wask LB)|$(lhas LA)"
expect_eq "LE.20 …so LA's next open takes a fresh first-ask instant (1631), behind LB, and is answered 0" "1631|0|0" \
  "$(lopen LA "$LME" 600 >/dev/null; lfield LA first)|$(wask LA)"
fresh lease-tie
share92w
world_machine 8 8192 30 2.0
lopen LA "$LME" 600 >/dev/null; lopen LB "$LME" 600 >/dev/null
expect_eq "LE.21 two leases opened at one instant: the first opened is the older (order 1 then 2): LA 4, LB 0" \
  "1000 1000 1 2|4|0 0|0" "$(lfield LA first) $(lfield LB first) $(lfield LA seq) $(lfield LB seq)|$(wask LA) $(wask LB)"
fresh lease-mixed
share92w
world_machine 8 8192 30 2.0
BIONIC_GATE_LANDING=LC HOLD=1 ask_bg lc1 landing c.test.sh 0; wait_for 20 has lc1.rc
world_tick 5
lopen LA "$LME" 600 >/dev/null
expect_eq "LE.22 a landing with no lease is ordered by its open requests, as before: LC (asked 1000) answered 3, LA (lease 1005) 0" \
  "0 3|0 0|0" "$(rc_of lc1) $(wask LC) $(wask LA)"
release lc1
expect_eq "LE.23 …and once LC's request has ended, LC is not active: LA answered 4, LC 0" "4|0 0|0" "$(wask LA) $(wask LC)"
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
expect_eq "LE.25 the mutant read no lease line: its width ask feeds the awk no lease (positive: the shipped one does)" "0 1" \
  "$(grep -cF '"$_G_LEASE"; } | awk' "$MLE") $(grep -cF '"$_G_LEASE"; } | awk' "$GATE")"
expect_eq "LE.26 the mutant still runs and answers: LA, alone, 4" "4|0" "$(wask_m "$MLE" LA)"
expect_eq "LE.27 MUTANT the lease unread: LB is answered 4 in LA's gap, where the shipped gate answers 0 (the rows can fail)" \
  "4|0 0|0" "$(wask_m "$MLE" LB) $(wask_m "$GATE" LB)"

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
# processor: 6.0 busy cores, one run held, a second ask (6.0 + 1 > 6.4).
MG="$(mutant ceiling)"
anchor file payload/scripts/lib/gate.sh 'if (r >= 0 && !fits(u, share)) exit 1'
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
# promised the suite cost and no memory (wave-33 T1; Δ10), so the readings decide: w2 asks while the
# memory reads 85%, over the share of 80; w4 while the processor reads the share's whole room.
# Expected: 0 75 0 75 (the second over memory, the fourth over the processor while two are
# admitted) on any machine whose share holds two promises (share × cores ÷ 100 ≥ twice resources.sh's
# suite cost, wave-38 T5: 5 cores and up at 80); on a smaller one the third is refused too, the cost
# of a fixed promise a command.
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
admissions 6 6144; small="$ADM"
admissions 32 65536; large="$ADM"
hard_rows 4 4096; hsmall="$HRD"
hard_rows 32 65536; hlarge="$HRD"
expect_eq "C.1 a 6-core 6 GB machine decides 0 75 0 75 (4 cores at 80 hold one promise of the suite cost, wave-38 T5)" "0 75 0 75" "$small"
expect_eq "C.2 a 32-core 64 GB machine at the same percentages decides alike" "0 75 0 75" "$large"
expect_eq "C.3 the memory rule on the small machine: 75, then 0 on a busy processor" "75 0" "$hsmall"
expect_eq "C.4 and alike on the large one" "75 0" "$hlarge"

# ── §TWO ─────────────────────────────────────────────────────────────────────
section "§TWO — several commands never start on one reading (AC-2.4)"
fresh two
# THE ROOM FOR ONE (wave-33 T1; Δ10): every command is promised the suite cost and no memory, so the
# room is the live processor reading's: 6.0 busy cores of the 6.4 the share of 80 allows on 8.
# The first ask, nothing admitted, is admitted; a second (6.0 + the suite cost > 6.4) waits.
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
world_machine 8 8192 60 6.0
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
  world_machine 8 8192 60 6.0
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
  world_machine 8 8192 60 6.0
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

# ── §ROBUST ──────────────────────────────────────────────────────────────────
# THE PROMISE IS ROBUST TO ONE CONTENDED RUN (wave-38 T31; D21; A-orch-43). The gate promised a suite
# the LARGEST of its kept durations, so one run of close-out.test.sh under three-builder contention
# (1775 s, beside 760 and 669) set its promise past `ready --within 1700`, and no ready could ever
# start it. With three kept durations the promise is the largest at or below twice their median; with
# fewer, the largest. The durations are planted in the key's own cost file (`costf`, the project key
# the gate's own), newest last, as gate_end writes them.
finish
