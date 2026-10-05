#!/bin/bash
# Tests for hooks/session-poker.sh — the tick that decides whether a dispatched session
# needs a nudge.
#
# Governing design: .bionic/docs/specs/epic-16-landing-contract/
# wave-02-fact-based-supervision.spec.md §Design ("Poker"). Serves AC-7 (arm/tick/noop/
# disarm at an accelerated clock) and AC-6's arrival half (a dead agent is reported at the
# next wake with no watcher process ever having existed) — this suite proves the REPORTING
# side of AC-6; the "no watcher process at any point" process-table bracket is AC-6's own
# live T3 arc and is not hermetic.
#
# Hermetic, same posture as tests/session-sweeper.test.sh: every case runs inside a
# throwaway sandbox git repo. Nothing reads or writes the real .bionic/tmp, the real
# roster, or a live wave.
#
# CLOCK DISCIPLINE (house rule, carried from session-sweeper.test.sh): nothing here sleeps
# for a declared duration or interval. Launch times are roster fields (`iso_ago`), progress
# ages are mtimes (`backdate`), and the interval knob is driven small through a throwaway
# .bionic/config.yaml override — every threshold is fixture data, never a wait, and every
# override lives inside its own throwaway repo so nothing needs restoring at teardown.
#
# Usage: bash tests/session-poker.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"
. "$(dirname "$0")/lib/bound-marker.sh"
. "$(dirname "$0")/lib/roster-row.sh"
. "$(dirname "$0")/lib/swept-marker.sh"
. "$(dirname "$0")/lib/live-answer.sh"

# Overridable exactly as tests/session-sweeper.test.sh offers, for RED evidence against a
# mutated copy without ever touching the shipped file:
#   W2_POKER_UNDER_TEST=/tmp/mutant.sh bash tests/session-poker.test.sh
POKER="${W2_POKER_UNDER_TEST:-${BIONIC_HOOKS_DIR}/session-poker.sh}"
TMPROOT="$(mktemp -d)"

# THE LOADER'S REGISTRY LANE, POINTED AT NOTHING (bionic 1.4.0). The poker now finds its
# library through the shared loader idiom, whose candidates (2) and (3) read the CLI's
# plugin registry under `$BIONIC_PLUGINS_DIR` (default `$HOME/.claude/plugins`). Every
# invocation in this suite runs the shipped file, whose sibling `scripts/lib` answers at
# candidate (1) — so a run that ever reached the registry would be a run that failed to
# find the library beside the script, and pointing the knob at an empty directory turns
# that into a visible failure instead of a silent read of this machine's real install.
export BIONIC_PLUGINS_DIR="$TMPROOT/no-plugins"
mkdir -p "$BIONIC_PLUGINS_DIR"

# THE MACHINE IS FIXTURE DATA HERE, WITHOUT EXCEPTION (S8). The tick now samples the
# pressure ring and takes its fill width from `pressure_level`, so two readings that used
# to reach only the advisory HOLD line now decide how many tasks a FILL names. Left
# unpinned, this suite would read THIS machine — and a suite that happens to run while the
# fleet is busy would see a critical band, a quartered rung and a FILL of one where the case
# asked for two. Every one of these is a seam lib/resources.sh already owns
# (`BIONIC_PROBE_*`, resources.sh:154 and :242/:279) plus the ring path S7 added; pinning
# them here is the same discipline §11's preamble already declares for free_mb and load.
#
# THE RING GOES UNDER $TMPROOT, so nothing in this file can read or write the machine-scoped
# ring at ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/bionic/pressure.ring. Cases that need a
# particular BAND override the two percentages and take a ring of their own (`poke_rung`).
export BIONIC_PRESSURE_RING="$TMPROOT/pressure.ring"
export BIONIC_PROBE_FREE_MB=8192
export BIONIC_PROBE_LOAD_1M=1.0
export BIONIC_PROBE_FREE_PCT=60
export BIONIC_PROBE_SWAP_PCT=0

cleanup() { chmod -R u+rwX "$TMPROOT" 2>/dev/null; rm -rf "$TMPROOT"; }
trap cleanup EXIT

SID="8a41c2e0-9b71-4f3a-8d6e-2c19f7b0e5aa"

# ---------- sandbox + fixture builders (mirrors tests/session-sweeper.test.sh) ----------

make_repo() {  # <label> -> repo path, in a session that has ENGAGED bionic
  local r="$TMPROOT/$1"
  mkdir -p "$r/.bionic/tmp"
  ( cd "$r" && git init -q . 2>/dev/null )
  engage "$r"
  printf '%s' "$r"
}

# ---------- engagement (task-engaged-session, AC-10, AC-15) ----------
#
# Since 2026-09-03 `tick` and `adopt` decide nothing in a session that never invoked the
# canonical-sdlc skill (Chris: "Nothing should apply until bionic is triggered"). The
# record of the invocation is `.bionic/tmp/engaged-<sid>.state` under the repo root, and
# every fixture in this file carries one because every assertion in it is about what the
# Patrol does inside a run somebody started. Section 11 is the unengaged world.
#
# `arm` and `disarm` are deliberately NOT guarded: writing or removing a stamp for a
# session that asked for one is harmless, and disarm must leave this marker in place —
# a session that invoked the skill is bionic's for its whole life (AC-15).
engage()   { mkdir -p "$1/.bionic/tmp" && : > "$1/.bionic/tmp/engaged-$SID.state"; }
unengage() { rm -f "$1/.bionic/tmp/engaged-$SID.state"; }

roster_of() { printf '%s/.bionic/tmp/roster-%s.state' "$1" "${2:-$SID}"; }

iso_ago() {  # <seconds ago> -> UTC ISO-8601, the launched_at shape
  date -u -v-"$1"S +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || date -u -d "-$1 seconds" +%Y-%m-%dT%H:%M:%SZ
}

backdate() {  # <file> <seconds ago> — sets mtime, the progress-staleness input
  local ts
  ts="$(date -v-"$2"S +%Y%m%d%H%M.%S 2>/dev/null || date -d "-$2 seconds" +%Y%m%d%H%M.%S)"
  touch -t "$ts" "$1"
}

new_roster() {  # <repo>
  roster_header > "$(roster_of "$1")"
}

# Subset of tests/session-sweeper.test.sh's mkrow — the fields the poker actually reads
# (name, launched_at, deliverable, duration, progress, claims, cadence, waiver), same
# schema shape and field order as the roster writer in hooks/dispatch-preflight.sh.
mkrow() {  # <key=value>...
  local status=confirmed session="$SID" name=agent agent_id=a000 launched_at=""
  local deliverable="" duration="" progress="" claims="" cadence="" waiver=""
  local subagent_type=implementor
  local tool_use_id=toolu_x source=declared kv
  # THE ATTRIBUTION FIELD IS OPT-IN HERE, and that is the point (wave-session-bound-run,
  # A2). hooks/dispatch-preflight.sh appends `plan=` to every row it writes from this wave
  # on, but every roster written BEFORE it carries none — and `adopt`'s partition has to
  # answer for those too. A fixture that always emitted the field could not describe a
  # pre-wave roster, so `plan=` is written only when a case asks for it, and every existing
  # row in this file stays exactly the shape it was.
  local plan="" plan_set=no
  # THE THREE INSTRUMENT FIELDS ARE OPT-IN for the same reason `plan=` is (S13, spec
  # AC-20): every roster written before the suite-allowance wall carries none of them, and
  # `adopt` has to answer for those files too. A fixture that always emitted them could not
  # describe a pre-wall roster, and the third state — key absent, as opposed to key present
  # and empty — is the one the writer-side budget guard partitions on.
  local files="" sallow="" ssrc="" instrument_set=no
  local rexec="" rexec_set=no
  # THE DONE MARKER IS OPT-IN too (wave-24 T9, D3): a row that names none carries no key.
  local dmark="" dmark_set=no
  for kv in "$@"; do
    case "$kv" in
      re_executes=*) rexec="${kv#*=}"; rexec_set=yes ;;
      done=*)        dmark="${kv#*=}"; dmark_set=yes ;;
      plan=*)        plan="${kv#*=}"; plan_set=yes ;;
      status=*)      status="${kv#*=}" ;;
      session=*)     session="${kv#*=}" ;;
      agent_id=*)    agent_id="${kv#*=}" ;;
      subagent_type=*) subagent_type="${kv#*=}" ;;
      name=*)        name="${kv#*=}" ;;
      launched_at=*) launched_at="${kv#*=}" ;;
      deliverable=*) deliverable="${kv#*=}" ;;
      duration=*)    duration="${kv#*=}" ;;
      progress=*)    progress="${kv#*=}" ;;
      claims=*)      claims="${kv#*=}" ;;
      cadence=*)     cadence="${kv#*=}" ;;
      waiver=*)      waiver="${kv#*=}" ;;
      files=*)          files="${kv#*=}";  instrument_set=yes ;;
      suites_allowed=*) sallow="${kv#*=}"; instrument_set=yes ;;
      suites_source=*)  ssrc="${kv#*=}";   instrument_set=yes ;;
      *) printf 'mkrow: unknown key %s\n' "$kv" >&2; return 1 ;;
    esac
  done
  [ -n "$launched_at" ] || launched_at="$(iso_ago 60)"
  # THE ROW ITSELF COMES FROM `roster_row`, through tests/lib/roster-row.sh (S14, AC-25).
  # What stays here is this file's own house defaults — `model=opus`, `tool_use_id=toolu_x`,
  # a launch time sixty seconds ago — and the `plan=` opt-in above, which is the one thing
  # the production writer cannot express: no writer emits a row without that field any more,
  # and a pre-wave roster is exactly what these cases are about.
  local emit=roster_row_fixture
  [ "$plan_set" = yes ] || emit=roster_row_no_plan
  local -a instrument
  if [ "$instrument_set" = yes ]; then
    instrument=("files=$files" "suites_allowed=$sallow" "suites_source=$ssrc")
  fi
  [ "$rexec_set" = yes ] && instrument+=("re_executes=$rexec")
  [ "$dmark_set" = yes ] && instrument+=("done=$dmark")
  "$emit" \
    "status=$status" "session=$session" "name=$name" "agent_id=$agent_id" \
    "launched_at=$launched_at" "subagent_type=$subagent_type" model=opus \
    "deliverable=$deliverable" "source=$source" "duration=$duration" \
    "progress=$progress" "claims=$claims" "cadence=$cadence" absent= \
    "waiver=$waiver" ${instrument[@]+"${instrument[@]}"} \
    "tool_use_id=$tool_use_id" "plan=$plan"
}

add_row() {  # <repo> <key=value>...
  local repo="$1"; shift
  mkrow "$@" >> "$(roster_of "$repo")"
}

# THE AGENT SAID SO (wave-24 T9, REQ-4 AC-4.8; D3). MET is a landed deliverable AND a completion
# signal after the launch, and a fixture whose session transcript holds a panel but no report
# from the agent reads UNMET without one. A row meant to read MET gets its Done marker, written
# now, beside the deliverable: the row says nothing else, and nothing in the transcript moves.
said() {  # <dir> <name> -> the `done=<path>` argument, the marker written
  : > "$1/$2.done"
  printf 'done=%s/%s.done' "$1" "$2"
}

# The same, onto ANOTHER session's roster file in the same .bionic/tmp — the shape §8's
# `adopt` reads. `session=` is forced to match the filename, because that is the invariant
# the writer keeps and a fixture that broke it would be testing a state the fleet cannot
# produce.
add_row_to() {  # <repo> <session-id> <key=value>...
  local repo="$1" sid="$2"; shift 2
  local f; f="$(roster_of "$repo" "$sid")"
  [ -f "$f" ] || roster_header > "$f"
  mkrow session="$sid" "$@" >> "$f"
}

# THE ACK IS PLANTED THROUGH THE REAL VERB, never by hand-writing a ledger line. `acked=`
# reaches the poker on the verdict line (hooks/session-sweeper.sh:715), and the only writer
# of the ledger that line is computed from is `ack` itself — a fabricated ledger would pin
# this suite to a private idea of the ledger's shape rather than to the one the sweeper
# actually keeps. The sweeper is resolved exactly as the poker resolves it, as a sibling of
# the script under test, so a mutated poker copy still acks through the shipped sweeper.
SWEEPER_FOR_ACK="$(cd "$(dirname "$POKER")" && pwd)/session-sweeper.sh"
ack_rows() {  # <repo> <name>...
  local repo="$1"; shift
  ( cd "$repo" && env CLAUDE_CODE_SESSION_ID="$SID" bash "$SWEEPER_FOR_ACK" ack "$@" ) \
    >/dev/null 2>&1
}

# ---------- plan fixtures: the run-state read the tick takes (B-4, AC-13/AC-14) ----------
#
# WHY EVERY DISARM FIXTURE BELOW GREW A PLAN. `open == 0` used to be the whole DISARM
# predicate, and it is also what a live wave looks like between two batches — so the tick
# ended the Patrol of runs with days of work left (epic-20 W1 dogfood, idea §B-4). DISARM
# now needs the RUN to say it is delivered: `current: 9` with `delivered:` on the `Step 9:`
# line, read out of the newest plan carrying an unfenced `## SDLC State`. A fixture that
# writes no plan is therefore a fixture that cannot DISARM, which is AC-13's second half.
#
# CLOCK DISCIPLINE HOLDS: nothing here sleeps. `touch` after the write is what makes a
# fixture the newest candidate, exactly as `backdate` drives staleness above.
plan_body() {  # <current> [evidence text for the Step-<current> line] -> a whole plan file
  printf '# fixture plan\n\n## SDLC State\n\nintegration-branch: main\ncurrent: %s\n' "$1"
  # Past Step 3 the plan carries its approval, the fact the fill keys on (wave-26 T13; D3).
  case "${1%[ab]}" in [4-9]) printf '%s\n' 'approved-by: fixture 2026-10-04T00:00Z "approved"' ;; esac
  printf '\n- Step %s: %s\n' "$1" "${2:-evidence for this step}"
}

write_plan() {  # <repo> <body> [path relative to <docs-root>/plans]
  local repo="$1" body="$2" rel="${3:-epic-99-fixture/wave-01-fixture.plan.md}"
  local f="$repo/.bionic/docs/plans/$rel"
  mkdir -p "$(dirname "$f")"
  printf '%s' "$body" > "$f"
  touch "$f"
}

# The shorthand every DISARM fixture uses: a run that reached Step 9 and recorded a
# delivery. `delivered:` is the token the close-out step writes and the only one run_state
# accepts.
delivered_plan() {  # <repo>
  write_plan "$1" "$(plan_body 9 'delivered: bionic 9.9.9; report: record/fixture/close-out.md')"
}

# ---------- the session binding (wave-session-bound-run, AC-2/AC-3/AC-6/AC-8) ----------
#
# A plan the fixture can NAME. `write_plan` writes one and says nothing about where; the
# three sections below bind to a path, refuse a path, and assert a path appears nowhere, so
# each of them needs the path back. Same layout, one place, and the path is echoed rather
# than recomputed at every call site.
plan_at() {  # <repo> <relative path under <docs-root>/plans> <body> -> the absolute path
  write_plan "$1" "$3" "$2"
  printf '%s/.bionic/docs/plans/%s' "$1" "$2"
}

marker_of() { printf '%s/.bionic/tmp/engaged-%s.state' "$1" "${2:-$SID}"; }

# THE BOUND FIXTURE, in hooks/engage.sh's exact two-line shape — the same posture
# tests/canonical-sdlc-evidence-gate.test.sh §35 takes. Written directly rather than through
# `poker bind` so that §17 and §18 describe a session that arrived already bound (the
# ordinary case: engagement bound it, or the governing skill did) and do not depend on the
# verb §16 is testing.
bind_marker() {  # <repo> <plan path|none> [sid]
  bound_marker "$1" "${3:-$SID}" "$2"
}

# THE PHYSICAL SPELLING OF A PATH. `$TMPROOT` comes from `mktemp -d`, which on macOS hands
# back `/var/folders/...` — a symlink to `/private/var/folders/...`. A BOUND session reads its
# plan out of the marker and gets back whatever spelling was written there; an UNBOUND one
# gets the spelling the hook's own root walk produced, which is physical because every verb
# resolves its root with `pwd -P`. Both are the same file and the difference is real, so the
# fallback assertion below states which one it expects rather than papering over it.
real_path_of() {  # <path> -> the same file with its directory resolved
  printf '%s/%s' "$(cd "$(dirname "$1")" && pwd -P)" "$(basename "$1")"
}

file_mode() {  # <file> -> the three-digit mode, on either stat
  stat -f %Lp "$1" 2>/dev/null || stat -c %a "$1" 2>/dev/null
}

stamp_of() { printf '%s/.bionic/tmp/patrol-%s.state' "$1" "${2:-$SID}"; }

# THE TICK DIGEST (wave-24 T7, REQ-4; D4). A tick over the same facts as the last one prints one
# `unchanged` line, so a case that ticks the SAME world twice to read the second tick's full
# output — a doctored copy, a second cwd, a third reading of one pressure — forgets the digest
# first. Forgetting it is what an `arm` does to the next tick.
digest_of() { printf '%s/.bionic/tmp/tick-digest-%s.state' "$1" "${2:-$SID}"; }
forget_digest() { rm -f "$(digest_of "$1")"; }

# THE ARMING RECORD — the sibling of the stamp whose mtime `arm` sets and the tick compares a
# delivery against (R-13). Spelled out here the way stamp_of spells the stamp: one place in
# this suite knows the layout, and a rename on the writer's side shows up as a failure rather
# than as a fixture that quietly stops describing anything.
armed_of() { printf '%s%s' "$(stamp_of "$@")" ".armed"; }

# A DISARM FIXTURE DESCRIBES A PATROL THAT ARMED BEFORE THE RUN DELIVERED, and from 1.3.2
# that ordering is what the tick reads — so it is fixture DATA, set by arming through the
# real verb and dating the record back, exactly as `backdate` sets staleness and as
# tests/cross-gate-agreement.test.sh §S.3 sets "newest". Nothing here sleeps, and nothing is
# left to a same-second tie.
armed_ago() {  # <repo> [seconds ago, default 3600]
  poke "$1" arm
  backdate "$(armed_of "$1")" "${2:-3600}"
}

# ---------- running the poker (same watchdog shape as tests/session-sweeper.test.sh) ----------

POKE_BOUND=20
# A TICK RUNS ON A SESSION'S OWN RUN (wave-23-fixit-1810, REQ-1, D1; T11). An UNBOUND session
# gets the advisory and no run, so a fixture that engages with an empty marker and then asks
# the tick about the plan beside it would be asking an unbound session about someone else's
# run. `poke_bind` binds the empty marker to the library's open run for the drive, as
# cross-gate-agreement's `cg_eg_bind` does for the gate; a case that WANTS the unbound
# session sets POKE_UNBOUND=1 (§18c).
poke_bind() {  # <repo> -> binds an empty engaged marker to the root's open run, if there is one
  local m p; m="$(marker_of "$1")"
  [ -f "$m" ] && [ ! -L "$m" ] && [ ! -s "$m" ] || return 0
  p="$(bash -c '. "$1/run.sh" 2>/dev/null && active_run "$2"' _ "$BIONIC_SCRIPTS_DIR/payload/scripts/lib" "$1" 2>/dev/null)" || p=""
  [ -n "$p" ] && bound_marker "$1" "$SID" "$p"
  return 0
}
poke() {  # <repo> <args...> -> sets OUT, RC
  local repo="$1"; shift
  case "${1:-}" in tick|fill-report) [ "${POKE_UNBOUND:-0}" = 1 ] || poke_bind "$repo" ;; esac
  ( cd "$repo" && exec env CLAUDE_CODE_SESSION_ID="$SID" bash "$POKER" "$@" ) \
    > "$TMPROOT/poke.out" 2>&1 &
  local p=$! i=0
  while kill -0 "$p" 2>/dev/null && [ "$i" -lt $(( POKE_BOUND * 10 )) ]; do
    sleep 0.1; i=$((i+1))
  done
  if kill -0 "$p" 2>/dev/null; then
    kill -9 "$p" 2>/dev/null; wait "$p" 2>/dev/null
    RC=124
  else
    wait "$p" 2>/dev/null; RC=$?
  fi
  OUT="$(cat "$TMPROOT/poke.out")"
}

# ============================================================
section "Section 1: surface — usage, unknown verb, no session key"
# ============================================================

R1="$(make_repo s1)"; new_roster "$R1"

poke "$R1"
expect_eq "no verb is a usage error (exit 2)" "2" "$RC"

poke "$R1" tick extra-arg
expect_eq "more than one arg is a usage error (exit 2)" "2" "$RC"

poke "$R1" nonsense-verb
expect_eq "an unknown verb is a usage error (exit 2)" "2" "$RC"

OUT="$( cd "$R1" && CLAUDE_CODE_SESSION_ID="" bash "$POKER" tick 2>&1 )"; RC=$?
expect_eq "tick with no session key REFUSES with exit 3" "3" "$RC"

# ============================================================
section "Section 2: interval — the config knob"
# ============================================================

R2="$(make_repo s2)"

poke "$R2" interval
expect_eq "no config.yaml: the default (20m = 1200s) is used" "0" "$RC"
expect_eq "…printed as bare seconds" "1200" "$OUT"

mkdir -p "$R2/.bionic"
printf 'poker-interval: 5m\n' > "$R2/.bionic/config.yaml"
poke "$R2" interval
expect_eq "an override in .bionic/config.yaml is read (exit 0)" "0" "$RC"
expect_eq "…and resolves to its own seconds (5m = 300s)" "300" "$OUT"

# Accelerated-clock evidence for the knob itself: driven down to a couple of seconds,
# proving the read path carries a small value faithfully rather than only ever exercising
# the 30-minute default.
printf 'poker-interval: 2s\n' > "$R2/.bionic/config.yaml"
poke "$R2" interval
expect_eq "the interval reads a small override just as faithfully (2s)" "2" "$OUT"

printf 'poker-interval: not-a-duration\n' > "$R2/.bionic/config.yaml"
poke "$R2" interval
expect_eq "a malformed override REFUSES rather than silently defaulting (exit 2)" "2" "$RC"

# ---------- interval-default: the constant, with the config taken out of the question ----------
#
# ADDED FOR THE ARMING WALL (critic C-2, W5). `interval` above is right to refuse a
# malformed override — that is this repo's posture everywhere a prose value is read. But
# hooks/dispatch-preflight.sh has to measure staleness even then, because `.bionic/config.yaml`
# is machine-local and agent-writable and one bad line there must not be able to disarm a
# wall. Rather than retype 1200 in the gate — two copies of a constant that drift the first
# time either moves — the gate asks this verb.
#
# THE PROPERTY THAT MATTERS TO ITS CALLER is that the config cannot change the answer, so
# every arm below is driven ON TOP of a config the `interval` verb refuses or overrides.
poke "$R2" interval-default
expect_eq "interval-default answers 0 even though the live config is malformed" "0" "$RC"
expect_eq "…with this script's own default, in seconds (20m = 1200s)" "1200" "$OUT"

printf 'poker-interval: 5m\n' > "$R2/.bionic/config.yaml"
poke "$R2" interval-default
expect_eq "…and a perfectly VALID override does not move it either" "1200" "$OUT"
poke "$R2" interval
expect_eq "…while interval, on the same repo, still reads that override (5m = 300s)" "300" "$OUT"

# The gate's fallback is only worth having if it tracks the constant. Mutation-proof: move
# POKER_INTERVAL_DEFAULT on a copy and the verb has to move with it — a verb that printed a
# literal 1200 would answer 1200 here.
# THE DOCTORED COPY LIVES IN A TREE, not in a bare temp directory (bionic 1.4.0). The poker
# loads its library through the shared idiom, whose first candidate is `<dirname $0>/../
# scripts/lib` — the shape the installed plugin ships. A copy dropped anywhere else finds no
# library and fails open, which would make this mutation prove nothing. The library is
# LINKED, never duplicated: the copy under test must read the same functions the shipped
# script does.
POKER_MUT_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/poker-default-mut.XXXXXX")"
mkdir -p "$POKER_MUT_ROOT/hooks" "$POKER_MUT_ROOT/scripts"
ln -s "$(cd "$(dirname "$POKER")/../payload/scripts/lib" && pwd -P)" "$POKER_MUT_ROOT/scripts/lib"
POKER_MUT="$POKER_MUT_ROOT/hooks/session-poker.sh"
sed 's/^POKER_INTERVAL_DEFAULT="20m"$/POKER_INTERVAL_DEFAULT="7m"/' "$POKER" > "$POKER_MUT"
OUT="$( cd "$R2" && CLAUDE_CODE_SESSION_ID="$SID" bash "$POKER_MUT" interval-default 2>&1 )"; RC=$?
expect_eq "the verb answers from the CONSTANT, not from a literal (doctored 7m = 420s)" "420" "$OUT"

# ============================================================
section "Section 3: tick — the accelerated-clock decisions (AC-7, re-authored for the ack)"
# ============================================================
#
# AC-7's CONTRACT MOVED at epic-16 w2 Step-6 remediation R4 (cs review C-4), so this case
# list is re-authored rather than re-run: the ack is now an input to every decision below,
# and cases that used to read "an UNMET row past its duration NOTIFYs" now read "an UNACKED
# UNMET row past its duration NOTIFYs". Rerunning the old list green would have proven
# nothing about the property that changed.
#
# WHAT CHANGED. `acked=yes|no` rides beside the state on every verdict line
# (hooks/session-sweeper.sh:715), and three consumers already treated an acked row as
# closed — hooks/landing-gate.sh:214, hooks/stop-orders.sh:319, hooks/stop-guard.sh:491.
# The poker read the state alone, which made the sweeper's own closing sentence false:
#
#   hooks/session-sweeper.sh:817 — "an acked row is closed for every reader"
#
# It now is. An acked row is excluded from OPEN counting and from NOTIFY eligibility here
# exactly as it is there, which closes the two structural consequences C-4 named: DISARM
# was unreachable while any acked-UNMET row sat on the roster (the self-wake was immortal),
# and the NOTIFY set grew monotonically across a wave, re-alarming on work a human had
# already accounted for.
#
# The case list AC-7 is now driven by:
#   DISARM  — empty roster; every row MET; every row UNMET-but-ACKED (new).
#   NOTIFY  — an UNACKED UNMET row past its duration; a mixed roster naming only the
#             unacked overdue row (both paired positives for the exclusion above).
#   QUIET   — an UNMET row inside its duration; an unreadable duration; an ACKED overdue
#             row beside an unacked row that is not yet due (new).
#   REFUSE  — an absent roster (Section 5), unchanged by the ack.
#
# The ack reaches the poker on the verdict line it already parses, per row, and never from
# the ledger: the verb that owns the ledger is the verb that prints the answer (S9, and
# critic N-1's one-owner discipline).

# --- empty roster -> DISARM ---
R3E="$(make_repo s3-empty)"; new_roster "$R3E"
# The run says it is delivered, so the empty roster is a finish and not a lull (AC-14) — and
# the Patrol armed before that delivery was recorded, which is what makes the delivery THIS
# run's (R-13, AC-14's second half).
armed_ago "$R3E"
delivered_plan "$R3E"
poke "$R3E" tick
expect_eq "an empty roster ticks quietly (exit 0)" "0" "$RC"
expect_contains "…and decides DISARM" "decision=DISARM" "$OUT"
expect_contains "…open=0" "open=0" "$OUT"
expect_absent   "…never QUIET on the same tick" "decision=QUIET" "$OUT"

# --- arm-shape row (progress + cadence, inside cadence) -> tick reads verdict -> QUIET ---
R3A="$(make_repo s3-arm)"; new_roster "$R3A"
PROG_A="$R3A/prog-writer.md"
echo "working" > "$PROG_A"; backdate "$PROG_A" 30
add_row "$R3A" name=writer progress="$PROG_A" cadence="5 minutes" \
  deliverable="$R3A/absent-writer.md" duration="4 hours" launched_at="$(iso_ago 60)"
poke "$R3A" tick
expect_eq "an arm-shape row (fresh progress, inside cadence) ticks cleanly (exit 0)" "0" "$RC"
expect_contains "…tick read the row as STILL-LIVE through verdict, and QUIETs" "decision=QUIET" "$OUT"
expect_contains "…open=1" "open=1" "$OUT"
expect_absent   "…never DISARM with an open row present" "decision=DISARM" "$OUT"

# --- UNMET, but well inside its declared duration -> QUIET ---
R3Q="$(make_repo s3-quiet)"; new_roster "$R3Q"
add_row "$R3Q" name=fresh-unmet deliverable="$R3Q/absent-fresh.md" \
  duration="4 hours" launched_at="$(iso_ago 60)"
poke "$R3Q" tick
expect_eq "an UNMET row inside its duration ticks cleanly (exit 0)" "0" "$RC"
expect_contains "…decides QUIET" "decision=QUIET" "$OUT"
expect_contains "…open=1" "open=1" "$OUT"
expect_absent   "…never DISARM" "decision=DISARM" "$OUT"
expect_absent   "…never NOTIFY — not past duration yet" "decision=NOTIFY" "$OUT"

# --- UNACKED UNMET, past its declared duration -> exactly one NOTIFY, naming the row ---
# The paired positive for the acked cases below: the ack is what closes a row, and a row
# nobody acked is still surfaced however the state was reached.
R3N="$(make_repo s3-notify)"; new_roster "$R3N"
add_row "$R3N" name=overdue-agent deliverable="$R3N/absent-overdue.md" \
  duration="1 minute" launched_at="$(iso_ago 120)"
poke "$R3N" tick
expect_eq "an UNACKED UNMET row past its duration signals NOTIFY (exit 1)" "1" "$RC"
expect_contains "…decision=NOTIFY" "decision=NOTIFY" "$OUT"
expect_contains "…naming the row" "rows=overdue-agent" "$OUT"
expect_absent   "…never QUIET on the same tick" "decision=QUIET" "$OUT"
expect_absent   "…never DISARM on the same tick" "decision=DISARM" "$OUT"

# --- F-1 regression (t6-review.md §1): a landing-swept/v1 marker for this name, appended
# after the roster row, must not shadow it when NOTIFY reads duration=/launched_at= off the
# roster directly. The marker carries |name=<NAME>| but no duration=/launched_at=, so a
# by-name lookup that does not filter to the roster schema first takes the marker on
# `tail -1` and silently drops the row from NOTIFY eligibility (parse_seconds("") refuses).
R3SW="$(make_repo s3-swept-marker)"; new_roster "$R3SW"
add_row "$R3SW" name=overdue-swept deliverable="$R3SW/absent-overdue-swept.md" \
  duration="1 minute" launched_at="$(iso_ago 120)"
swept_marker_write "$(roster_of "$R3SW")" "$(iso_ago 1)" "$SID" overdue-swept a000 UNMET
poke "$R3SW" tick
expect_eq "a landing-swept marker after the row does not silence NOTIFY (exit 1)" "1" "$RC"
expect_contains "…decision=NOTIFY survives the marker" "decision=NOTIFY" "$OUT"
expect_contains "…naming the row" "rows=overdue-swept" "$OUT"

# --- all rows closed (MET), roster non-empty -> DISARM generalizes past "empty" ---
R3C="$(make_repo s3-closed)"; new_roster "$R3C"; armed_ago "$R3C"; delivered_plan "$R3C"
DEL_C="$R3C/delivered.md"; echo "done" > "$DEL_C"
add_row "$R3C" name=finished deliverable="$DEL_C" duration="1 minute" \
  launched_at="$(iso_ago 600)"
poke "$R3C" tick
expect_eq "a roster with every row MET ticks quietly (exit 0)" "0" "$RC"
expect_contains "…decides DISARM even though the roster is non-empty" "decision=DISARM" "$OUT"
expect_contains "…total=1" "total=1" "$OUT"
expect_contains "…open=0" "open=0" "$OUT"

# --- mixed roster: one MET + one NOTIFY-worthy UNMET -> NOTIFY names only the open one ---
R3M="$(make_repo s3-mixed)"; new_roster "$R3M"
DEL_M="$R3M/delivered.md"; echo "done" > "$DEL_M"
add_row "$R3M" name=already-landed deliverable="$DEL_M" duration="1 minute" \
  launched_at="$(iso_ago 600)"
add_row "$R3M" name=overdue-agent-2 deliverable="$R3M/absent-2.md" \
  duration="1 minute" launched_at="$(iso_ago 120)"
poke "$R3M" tick
expect_eq "a mixed roster still resolves to NOTIFY (exit 1)" "1" "$RC"
expect_contains "…names the overdue row" "rows=overdue-agent-2" "$OUT"
# NARROWED TO THE NOTIFY SET (T22). The claim was always about NOTIFY — a landed row is not
# overdue work — and it was written as a sweep of the whole tick output because nothing else
# named a MET row. Something does now: the TASKSTOP tell names exactly the MET lineages the
# sweep has not closed, which is this row. So the assertion reads the decision line it is
# about, and the tell gets its own cases in Section 12.
expect_absent   "…never names the already-landed row in the NOTIFY set" \
  "rows=already-landed" "$OUT"
expect_absent   "…nor in the NOTIFY detail" "already-landed:" "$OUT"
expect_contains "…open=1 (the landed row is not open)" "open=1" "$OUT"

# --- UNMET with an unreadable duration -> fail open, QUIET, never a guessed threshold ---
R3U="$(make_repo s3-unreadable)"; new_roster "$R3U"
add_row "$R3U" name=vague-duration deliverable="$R3U/absent-vague.md" \
  duration="whenever it feels right" launched_at="$(iso_ago 100000)"
poke "$R3U" tick
expect_eq "an unreadable duration never invents a threshold (exit 0)" "0" "$RC"
expect_contains "…QUIETs rather than guessing, however old the row is" "decision=QUIET" "$OUT"
expect_absent   "…never NOTIFY on a duration the parser refused" "decision=NOTIFY" "$OUT"

# ---------- the ack closes a row for the poker too (cs review C-4) ----------
#
# Three consequences, each pinned against the behaviour that shipped before R4: a roster of
# acked rows could never DISARM, an acked row was re-notified on every tick, and the OPEN
# count carried rows a human had already closed. Every fixture below acks through the real
# `ack` verb, so what is under test is the poker reading `acked=` off the verdict line — not
# this suite's idea of a ledger.

# --- every row UNMET-but-ACKED -> DISARM (the previously immortal self-wake) ---
# Before R4 this roster held OPEN at 3 forever: an acked row is never MET and never WAIVED,
# and its artifact — accounted for by a human rather than written to disk — will never
# appear. DISARM requires OPEN=0, so the self-wake could not be ended by the ordinary path
# an orchestrator uses to close a row that produced no artifact.
R3AK="$(make_repo s3-all-acked)"; new_roster "$R3AK"; armed_ago "$R3AK"; delivered_plan "$R3AK"
add_row "$R3AK" name=acked-1 deliverable="$R3AK/absent-1.md" duration="1 minute" \
  launched_at="$(iso_ago 600)"
add_row "$R3AK" name=acked-2 deliverable="$R3AK/absent-2.md" duration="1 minute" \
  launched_at="$(iso_ago 600)"
add_row "$R3AK" name=acked-3 deliverable="$R3AK/absent-3.md" duration="4 hours" \
  launched_at="$(iso_ago 60)"
ack_rows "$R3AK" acked-1 acked-2 acked-3
poke "$R3AK" tick
expect_eq "a roster of ACKED UNMET rows ticks quietly (exit 0)" "0" "$RC"
expect_contains "…and DISARMs — an acked row is closed for every reader, this one included" \
  "decision=DISARM" "$OUT"
expect_contains "…open=0 though every row is UNMET" "open=0" "$OUT"
expect_contains "…total still counts them (they are on the roster, they are just closed)" \
  "total=3" "$OUT"
expect_absent   "…never NOTIFY on rows a human already closed" "decision=NOTIFY" "$OUT"

# --- an ACKED row past its duration -> no notification (the wolf-cry) ---
# The take-2 capture (record/w2-t3-ac6-take2.txt:29) showed 10 of 11 open rows notified,
# nine of them acked ~15 minutes earlier — every tick re-alarming on closed work, which is
# the false-alarm class this wave exists to end.
# The sandbox label deliberately does NOT contain the row name: the DISARM line now names
# the plan path it decided from, and a repo dir called `s3-acked-overdue` would put the row
# name into the output by way of the fixture rather than by way of a notification.
R3AN="$(make_repo s3-ack-past-due)"; new_roster "$R3AN"; armed_ago "$R3AN"; delivered_plan "$R3AN"
add_row "$R3AN" name=acked-overdue deliverable="$R3AN/absent-acked-overdue.md" \
  duration="1 minute" launched_at="$(iso_ago 100000)"
ack_rows "$R3AN" acked-overdue
poke "$R3AN" tick
expect_eq "an ACKED row long past its duration raises no notification (exit 0)" "0" "$RC"
expect_absent "…never NOTIFY" "decision=NOTIFY" "$OUT"
expect_absent "…and never names the acked row" "acked-overdue" "$OUT"
expect_contains "…the roster having nothing else open, it DISARMs" "decision=DISARM" "$OUT"

# --- paired positive: the SAME row, unacked, still NOTIFYs ---
# The discriminator for the case above: identical fixture, no ack. Without this the acked
# case could pass because the fixture never notified in the first place.
R3AP="$(make_repo s3-acked-pair)"; new_roster "$R3AP"
add_row "$R3AP" name=acked-overdue deliverable="$R3AP/absent-acked-overdue.md" \
  duration="1 minute" launched_at="$(iso_ago 100000)"
poke "$R3AP" tick
expect_eq "the IDENTICAL row with no ack still signals NOTIFY (exit 1)" "1" "$RC"
expect_contains "…naming it" "rows=acked-overdue" "$OUT"

# --- mixed roster: only UNACKED rows are counted open, and only they can notify ---
R3AM="$(make_repo s3-acked-mixed)"; new_roster "$R3AM"
add_row "$R3AM" name=closed-by-ack deliverable="$R3AM/absent-closed.md" \
  duration="1 minute" launched_at="$(iso_ago 100000)"
add_row "$R3AM" name=still-open deliverable="$R3AM/absent-open.md" \
  duration="4 hours" launched_at="$(iso_ago 60)"
ack_rows "$R3AM" closed-by-ack
poke "$R3AM" tick
expect_eq "a mixed roster QUIETs when the only overdue row is acked (exit 0)" "0" "$RC"
expect_contains "…decides QUIET, not DISARM — one row is genuinely still open" \
  "decision=QUIET" "$OUT"
expect_contains "…open=1 counts only the unacked row" "open=1" "$OUT"
expect_contains "…total=2 still counts both" "total=2" "$OUT"
expect_absent   "…and the acked overdue row raises nothing" "decision=NOTIFY" "$OUT"

# ============================================================
section "Section 4: refusals propagate from the sweeper's one read"
# ============================================================

#
# THE CLAIM, ASSERTED (wave-01 S11, AC-16 / A-23). This section built its fixture,
# ran a tick and asserted nothing — the framework's section floor is what surfaced
# it. What it means to say is the exit table's line 2 at the top of
# hooks/session-poker.sh: a refusal PROPAGATED from the sweeper's one read is the
# tick's own refusal, exit 2, quoting the sweeper.
#
# THE FIXTURE REACHED NO SWEEPER READ (S11). `rm -rf .bionic/tmp` removes the
# engagement marker `make_repo` plants along with the roster, so the tick exited at
# the engagement switch with `NOT-ENGAGED … nothing decided` and rc 0: the section
# was driving a bystander session, not a refusal. The marker is re-planted AFTER
# the symlink goes in — through it, which is what a repo whose state directory is
# a link actually looks like — so the tick is engaged and reaches the read.
R4="$(make_repo s4)"; new_roster "$R4"
rm -rf "$R4/.bionic/tmp"
mkdir -p "$TMPROOT/elsewhere-s4"
ln -s "$TMPROOT/elsewhere-s4" "$R4/.bionic/tmp"
engage "$R4"
new_roster "$R4"
poke "$R4" tick
expect_status "a tick over an unreadable state directory REFUSES (exit 2), it does not decide" \
  "2" "$RC"
expect_contains "…and says the verdict read did not complete" \
  "REFUSED — the verdict read did not complete" "$OUT"
expect_contains "…quoting the SWEEPER's own refusal rather than inventing one" \
  "sweeper: REFUSED" "$OUT"
expect_contains "…naming the state directory as the symbolic link it is" \
  "is a symbolic link" "$OUT"
expect_absent "…and decides nothing: no DISARM, NOTIFY or QUIET verdict is printed" \
  "poker: QUIET" "$OUT"

# THE PAIRED POSITIVE, same builder and same drive with the link taken out: the
# tick decides. Every row above is about a refusal, and a refusal assertion over a
# drive that could never have decided anything is not a propagation test.
R4OK="$(make_repo s4ok)"; new_roster "$R4OK"
poke "$R4OK" tick
expect_status "the control: the same tick over a REAL state directory decides (exit 0)" \
  "0" "$RC"
expect_absent "…and refuses nothing" "REFUSED" "$OUT"
expect_regex "…printing a verdict of its own" 'poker: (DISARM|QUIET|NOTIFY)' "$OUT"

# ============================================================
section "Section 5: the pinned root — a worktree cwd answers for the MAIN repository (6-axis A-1)"
# ============================================================
#
# ap review A-1: from a worktree cwd, `git rev-parse --show-toplevel` answers the WORKTREE
# root, not the repository resolve_project_root maps onto (dispatch-preflight.sh's own
# convention, epic-16 w2 Step-6 remediation R3). A roster written at the main root then
# reads as an empty roster from inside the worktree, and DISARM is terminal by doctrine
# (skills/canonical-sdlc/SKILL.md §Dispatch: "DISARM also ends the heartbeat") — one tick
# taken from a worktree cwd would end supervision for the rest of the session while real
# work is still open.

R5="$(make_repo s5-worktree)"
( cd "$R5" && git config user.email t@example.com && git config user.name T \
  && echo seed > README.md && git add README.md && git commit -qm seed ) >/dev/null 2>&1
new_roster "$R5"
add_row "$R5" name=live-worker deliverable="$R5/absent-worker.md" \
  duration="1 minute" launched_at="$(iso_ago 120)"

R5WT="$TMPROOT/s5-worktree-wt"
# A REAL `git worktree add` (never a mocked path) — built from the repo root, since
# `git worktree add` resolves relative paths against pwd (.claude/rules/git-worktree-docs.md).
( cd "$R5" && git worktree add -q -b s5-r3-wt "$R5WT" ) >/dev/null 2>&1

poke "$R5" tick
expect_eq "from the main repo root, tick sees the open overdue row (NOTIFY, exit 1)" "1" "$RC"
expect_contains "…and names it" "rows=live-worker" "$OUT"

forget_digest "$R5"
poke "$R5WT" tick
expect_eq "from the WORKTREE cwd, the SAME session's tick still reads the true roster (NOTIFY, exit 1)" \
  "1" "$RC"
expect_contains "…still names the open row through the worktree cwd" "rows=live-worker" "$OUT"
expect_absent "…never quietly DISARMs because the worktree cwd resolved the wrong root" \
  "decision=DISARM" "$OUT"

( cd "$R5" && git worktree remove --force "$R5WT" ) >/dev/null 2>&1

# `interval` shares the same resolver (session-poker.sh:152) — a config override that lives
# at the main repo root must be honoured from the worktree cwd too.
mkdir -p "$R5/.bionic"
printf 'poker-interval: 7m\n' > "$R5/.bionic/config.yaml"
( cd "$R5" && git worktree add -q -b s5-r3-wt2 "$R5WT" ) >/dev/null 2>&1
poke "$R5WT" interval
expect_eq "…and the interval knob reads the main repo's override from the worktree too (7m = 420s)" \
  "420" "$OUT"
( cd "$R5" && git worktree remove --force "$R5WT" ) >/dev/null 2>&1

# ---------- the "no roster" vs "empty roster" distinction (ap review A-1, item 2) ----------
R5B="$(make_repo s5-no-roster)"
# No new_roster call: the state directory exists but the roster FILE itself does not — the
# absent-file case, deliberately distinct from the header-only roster Section 3's "empty
# roster" case plants.
poke "$R5B" tick
expect_eq "an ABSENT roster REFUSES rather than silently DISARMing (exit 2)" "2" "$RC"
expect_absent "…never prints a decision line for a roster it never found" "decision=" "$OUT"

# ---------- the refusal SHOWS ITS WALK (2.4, AC-13) ----------
#
# The refusal above has always said "an absent roster usually means the wrong project root
# was resolved" and then left the reader to re-derive the walk by hand — which is the one
# question they cannot answer from the message, because the answer is a property of the
# filesystem above their cwd. `project_root_candidates` is that walk, one line per ancestor
# with the reason it was passed over, and the chosen one marked.
#
# THE TOPOLOGY THAT MAKES IT MATTER is a git repo nested inside a plain workspace that holds
# the `.bionic` tree — the shape the eight old resolvers got wrong by asking git first and
# so answering the nested repo, which owns no roster and never will. Here the walk starts at
# the cwd, passes the repo as a candidate, and chooses the workspace above it: two lines,
# and the operator can see which one their roster should be under.
R5C="$TMPROOT/s5-candidates"
mkdir -p "$R5C/.bionic/tmp"
engage "$R5C"
R5CN="$R5C/nested-repo"
mkdir -p "$R5CN"
( cd "$R5CN" && git init -q . ) >/dev/null 2>&1
poke "$R5CN" tick
expect_eq "the nested-repo topology still REFUSES on an absent roster (exit 2)" "2" "$RC"
expect_contains "…and prints the walk it took" "$R5CN" "$OUT"
R5C_CHOSEN="$(printf '%s\n' "$OUT" | grep -F "chosen")"
expect_contains "…marking the workspace that holds the .bionic tree as the chosen root" \
  "$R5C	chosen" "$R5C_CHOSEN"
R5C_NESTED="$(printf '%s\n' "$OUT" | grep -F "$R5CN")"
expect_contains "…while the nested repo appears as an ancestor that was considered" \
  "candidate" "$R5C_NESTED"
expect_absent "…and the walk is not mistaken for a decision" "decision=" "$OUT"


# ============================================================
section "Section 6: the Patrol stamp — the arm verb, and stamp-before-decide on every tick"
# ============================================================
#
# epic-17 W5 task 4/4, spec AC-6; design ledger D-C mechanics (2) and (3).
#
# WHAT THE STAMP MEASURES, and the whole reason it is written where it is written.
# The stamp is the Patrol's liveness signal: a session-keyed file beside the roster whose
# AGE says how long ago the Patrol last fired. hooks/dispatch-preflight.sh refuses a
# dispatch when it is absent (never armed) or older than 2x the poker-interval
# (armed-but-dead). That makes WHEN the stamp is written a correctness property, not a
# detail: it is written the MOMENT the machinery runs, before the roster is read and
# before any decision is reached. A stamp written only on a successful decision would
# measure decisions-succeeding rather than firings-landing — and this wave's own
# orchestrator session produced 10+ healthy-but-REFUSED pre-roster ticks during one long
# interview, every one of which would have aged the stamp toward a false refusal of the
# next dispatch.
#
# `arm` exists for the other end of the same asymmetry: arming precedes dispatch by
# design (doctrine: arm at engagement, never on dispatch), so the first stamp cannot come
# from a tick that has a roster to read. Without the verb the wall is a chicken-and-egg.

# `stamp_of`, `armed_of` and `armed_ago` are defined with the other fixture builders above:
# Section 3's DISARM cases need them, and a definition here would be too late for those.
mtime_of() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null; }

# ---------- the arm verb ----------
R6="$(make_repo s6-arm)"
# Deliberately NO new_roster: arming happens at engagement, before anything is dispatched.
poke "$R6" arm
expect_eq "arm succeeds with no roster in existence at all (exit 0)" "0" "$RC"
if [ -f "$(stamp_of "$R6")" ]; then
  ok "arm writes the session-keyed stamp beside the roster"
else
  no "arm writes the session-keyed stamp beside the roster" "no file at $(stamp_of "$R6")"
fi
S6_BODY="$(cat "$(stamp_of "$R6")" 2>/dev/null)"
expect_contains "the stamp carries its own schema" "patrol-stamp/v1" "$S6_BODY"
expect_contains "…and names the session it answers for" "session=$SID" "$S6_BODY"
expect_contains "…and records which verb wrote it" "verb=arm" "$S6_BODY"

# The stamp is machine-local state under .bionic/tmp, exactly like the roster and the
# attestation, and gets the same mode.
expect_eq "the stamp is owner-only, like every other .bionic/tmp record" "600" \
  "$(stat -f '%OLp' "$(stamp_of "$R6")" 2>/dev/null || stat -c '%a' "$(stamp_of "$R6")" 2>/dev/null)"

OUT="$( cd "$R6" && env -u CLAUDE_CODE_SESSION_ID bash "$POKER" arm 2>&1 )"; RC=$?
expect_eq "arm without a session key refuses (exit 3) — a stamp answers for ONE session" "3" "$RC"

# ---------- stamp-before-decide: the REFUSED tick still stamps ----------
#
# The no-roster refusal (Section 5's ap review A-1 case) is the strongest available
# witness for ordering: the tick exits 2 having decided nothing, so a stamp on disk
# afterwards can only have been written before the roster was reached.
R6B="$(make_repo s6-refused-tick)"
poke "$R6B" tick
expect_eq "a pre-roster tick still REFUSES (exit 2)" "2" "$RC"
if [ -f "$(stamp_of "$R6B")" ]; then
  ok "…and it stamped anyway: liveness is firings landing, not decisions succeeding"
else
  no "…and it stamped anyway: liveness is firings landing, not decisions succeeding" \
      "no file at $(stamp_of "$R6B")"
fi
expect_contains "the refused tick's stamp records the verb that wrote it" "verb=tick" \
  "$(cat "$(stamp_of "$R6B")" 2>/dev/null)"

# A tick refused for a DIFFERENT reason stamps too — the no-session-key refusal is the one
# exception, and it is the right one: without the key there is no stamp path to write.
R6C="$(make_repo s6-nokey)"
OUT="$( cd "$R6C" && env -u CLAUDE_CODE_SESSION_ID bash "$POKER" tick 2>&1 )"; RC=$?
expect_eq "a keyless tick refuses (exit 3)" "3" "$RC"
# THE PROBE NAMES THE STAMP rather than counting files: `.bionic/tmp` is not empty before
# the tick runs any more, because the engagement marker lives there. What the assertion
# always meant — no session-keyed file was written by a run that had no session key — is
# what it now asks.
R6C_WROTE="$(ls "$R6C/.bionic/tmp/" 2>/dev/null | /usr/bin/grep -v "^engaged-$SID.state$" || true)"
if [ -n "$R6C_WROTE" ]; then
  no "…and writes no stamp: a session-keyed file needs a session key" \
      "wrote: $R6C_WROTE"
else
  ok "…and writes no stamp: a session-keyed file needs a session key"
fi

# ---------- a healthy tick REFRESHES a stale stamp ----------
R6D="$(make_repo s6-refresh)"; new_roster "$R6D"
add_row "$R6D" name=live-one deliverable=out.md duration="30 minutes" \
  launched_at="$(iso_ago 60)"
poke "$R6D" arm
backdate "$(stamp_of "$R6D")" 4000
poke "$R6D" tick
S6_AGE=$(( $(date +%s) - $(mtime_of "$(stamp_of "$R6D")") ))
if [ "$S6_AGE" -lt 120 ]; then
  ok "a tick refreshes the stamp it found stale"
else
  no "a tick refreshes the stamp it found stale" "age is still ${S6_AGE}s"
fi

# ---------- the stamp follows the PINNED root, exactly as the roster does ----------
# Same worktree hazard Section 5 drove for the roster: a stamp written under a worktree
# root while dispatch-preflight reads the main repository's would make the wall refuse a
# perfectly live Patrol, permanently and silently.
R6E="$(make_repo s6-worktree)"
( cd "$R6E" && git add -A 2>/dev/null; git -c user.email=t@e -c user.name=T commit -qm seed --allow-empty ) >/dev/null 2>&1
R6EWT="$TMPROOT/s6-worktree-wt"
( cd "$R6E" && git worktree add -q -b s6-wt "$R6EWT" ) >/dev/null 2>&1
if [ -d "$R6EWT" ]; then
  poke "$R6EWT" arm
  if [ -f "$(stamp_of "$R6E")" ]; then
    ok "arming from a worktree cwd stamps the MAIN repository's .bionic/tmp"
  else
    no "arming from a worktree cwd stamps the MAIN repository's .bionic/tmp" \
        "not at $(stamp_of "$R6E"); worktree has: $(ls "$R6EWT/.bionic/tmp" 2>/dev/null)"
  fi
  ( cd "$R6E" && git worktree remove --force "$R6EWT" ) >/dev/null 2>&1
else
  ok "arming from a worktree cwd stamps the MAIN repository's .bionic/tmp (skipped: no worktree)"
fi

# ============================================================
# THE BLIND-WALL DETECTOR, RETIRED (bionic 1.4.0, task ADOPT, spec AC-7)
# ============================================================
#
# It compared main-thread `Agent` tool_uses in the transcript against rows on the roster
# and raised a NOTIFY when dispatches outnumbered them. The condition it looked for was
# real: the dispatch wall lived in the governing skill's frontmatter, and a skill's
# registrations do not survive a session continue, a `/clear` + resume or a
# `/reload-plugins` — so the wall went silently absent and dispatches launched unrostered.
#
# Every wall is registered in hooks/hooks.json now and survives all three, so that
# condition cannot arise the way it did. What could still arise was the detector's own
# false positive: it had no "no active run" branch, so a session that had simply not
# engaged a run — no roster, because nothing was dispatched — read as a session whose wall
# had died. That fired for real on 2026-09-02 at 20:07Z, against this wave's own
# orchestrator, which is how it came to be in scope.
#
# The registration is pinned instead, in tests/hook-adoption.test.sh and
# tests/cross-gate-agreement.test.sh §L: every hook named once in hooks.json, none in the
# frontmatter. That is a claim about a file on disk rather than an inference from a
# transcript, and it goes red when the wiring changes rather than when a session is idle.
#
# ONE HELPER SURVIVES THE RETIREMENT: `fake_config_dir`. Section 8 builds a predecessor's
# subagent transcript under it, and `adopt` resolves the observe address through
# CLAUDE_CONFIG_DIR — so without it that section would read the real ~/.claude.
fake_config_dir() {  # <label> -> a CLAUDE_CONFIG_DIR with a projects/ tree
  local c="$TMPROOT/$1-config"
  mkdir -p "$c/projects/-fixture-project"
  printf '%s' "$c"
}

# ============================================================
section "Section 7: window — the roster's own birth, and nothing written"
# ============================================================
#
# WHAT THIS VERB IS FOR (S9, ledger H1/H2 + P4). Two readers ask "since when does THIS
# roster's own record of this session begin": this script's own counters, which take the
# instant as `<since>`, and payload/scripts/lib/patrol.sh, which reconstructs the same
# tally for doctor and cannot source a file under hooks/. Without the verb patrol.sh grows
# its own copy of `file_birth`/`epoch_iso`/`roster_window` and the two answers drift; with
# it, `patrol_window()` shells out here exactly as `patrol_interval()` already shells out
# for the interval.
#
# WHY IT IS TESTED HERE AT ALL. The agreement partner
# (tests/cross-gate-agreement.test.sh §Q.3) calls the two counting FUNCTIONS with a literal
# `since` and never shells to the verb — so §Q.3 stays green against a `window` that
# returns the wrong instant, refuses a valid session, or writes a stamp. This section is
# the only thing that looks at the verb.
#
# BIRTH, NEVER MTIME. The roster is append-only: its mtime is the LAST dispatch, so a
# window taken from mtime would hide every gap but the newest. 7c advances the mtime a day
# past the file's birth and asks again — an implementation reading mtime answers tomorrow,
# this one still answers with the creation instant.
#
# THE MTIME IS ADVANCED, NEVER BACKDATED, and that is a platform fact rather than a taste:
# on APFS `touch -t` to an instant EARLIER than the file's birth lowers `st_birthtime` to
# match (measured on this machine — a file born at 1788749678 backdated a day reported
# `stat %B` 1788663278), so a backdating probe would move the very quantity it is trying to
# hold still and could not discriminate at all. Forward is also the append-only direction
# the roster actually travels.

# The same two-step the production `file_birth`/`epoch_iso` pair takes, recomputed here
# rather than extracted from the script under test: a helper that called the code under
# test could only prove it agrees with itself.
s7_birth_iso() {  # <path> -> UTC ISO-8601 of the filesystem's own creation instant
  local b
  b="$(stat -f %B "$1" 2>/dev/null || stat -c %W "$1" 2>/dev/null)"
  case "${b:-0}" in ''|*[!0-9]*|0) return 1 ;; esac
  date -u -r "$b" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$b" +%Y-%m-%dT%H:%M:%SZ
}

# ---------- 7a: no session key ----------
R7A="$(make_repo s7-nokey)"; new_roster "$R7A"
OUT="$( cd "$R7A" && env -u CLAUDE_CODE_SESSION_ID bash "$POKER" window 2>&1 )"; RC=$?
expect_eq "window with no session key REFUSES with exit 3" "3" "$RC"
expect_contains "…and says why: a window answers for ONE session" \
  "A window answers for ONE session" "$OUT"

# ---------- 7b: a roster on disk — its own birth, as ISO ----------
R7B="$(make_repo s7-roster)"; new_roster "$R7B"
S7B_EXPECT="$(s7_birth_iso "$(roster_of "$R7B")" || true)"
if [ -z "$S7B_EXPECT" ]; then
  # A filesystem that keeps no creation time makes every arm below vacuous. Named out
  # loud rather than passed over: the fallback is correct and the test would be useless.
  no "this filesystem records no file birth time — Section 7 cannot run" \
     "stat %B/%W gave nothing for $(roster_of "$R7B")"
else
  poke "$R7B" window
  expect_eq "window over a present roster exits 0" "0" "$RC"
  expect_eq "…and prints that roster's own creation instant, as UTC ISO-8601" \
    "$S7B_EXPECT" "$OUT"

  # ---------- 7c: birth, not mtime ----------
  S7B_FWD="$(date -v+1d +%Y%m%d%H%M.%S 2>/dev/null || date -d '+1 day' +%Y%m%d%H%M.%S)"
  touch -t "$S7B_FWD" "$(roster_of "$R7B")"
  expect_ne "7c is not vacuous: the mtime really did move off the birth instant" \
    "$(s7_birth_iso "$(roster_of "$R7B")")" \
    "$(date -u -r "$(mtime_of "$(roster_of "$R7B")")" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
       || date -u -d "@$(mtime_of "$(roster_of "$R7B")")" +%Y-%m-%dT%H:%M:%SZ)"
  poke "$R7B" window
  expect_eq "…and an mtime a day ahead does not move it: the roster is append-only" \
    "$S7B_EXPECT" "$OUT"

  # ---------- 7d: it writes NO stamp — the property that separates it from tick/arm ----------
  if [ -f "$(stamp_of "$R7B")" ]; then
    no "window writes no Patrol stamp: asking what window to use is not a firing" \
       "a stamp appeared at $(stamp_of "$R7B")"
  else
    ok "window writes no Patrol stamp: asking what window to use is not a firing"
  fi
  S7B_WROTE="$(ls "$R7B/.bionic/tmp/" 2>/dev/null | /usr/bin/grep -v "^engaged-$SID.state$" \
               | /usr/bin/grep -v "^roster-$SID.state$" || true)"
  expect_eq "…and writes nothing else under .bionic/tmp either" "" "$S7B_WROTE"

  # ---------- 7e: no roster, a stamp — the stamp's birth ----------
  # ARMING PRECEDES DISPATCH by doctrine, so on a session whose roster was never written
  # the stamp still dates the stretch this session is answerable for. This is the arm that
  # keeps doctor's no-roster page (tests/doctor-patrol.test.sh Section 12c) honest.
  R7E="$(make_repo s7-stamp-only)"
  poke "$R7E" arm
  expect_eq "arm succeeded, so 7e has a stamp to date (not a vacuous fixture)" "0" "$RC"
  S7E_EXPECT="$(s7_birth_iso "$(stamp_of "$R7E")" || true)"
  poke "$R7E" window
  expect_eq "no roster, but a Patrol stamp: window falls back to the stamp exit 0" "0" "$RC"
  expect_eq "…and prints the STAMP's creation instant" "$S7E_EXPECT" "$OUT"
  expect_nonempty "…which is a real instant, not the empty fallback" "$OUT"
  if [ -f "$(roster_of "$R7E")" ]; then
    no "…and the read created no roster file" "a roster appeared at $(roster_of "$R7E")"
  else
    ok "…and the read created no roster file"
  fi

  # ---------- 7f: neither file — empty stdout, exit 0 ----------
  # NOT A REFUSAL. "No window" is a legitimate answer that every caller already handles:
  # patrol.sh passes the empty string down and both counters read the whole transcript,
  # which is what doctor printed before this verb existed.
  R7F="$(make_repo s7-nothing)"
  poke "$R7F" window
  expect_eq "neither roster nor stamp: window still exits 0" "0" "$RC"
  expect_eq "…and prints nothing at all" "" "$OUT"

  # ---------- 7g: OUTSIDE the engagement gate, exactly like `interval` ----------
  # `tick`, `adopt` and `sweep` decide things about a run and refuse in a session that
  # never invoked the skill. This one reports a file's creation instant, and a session
  # that never engaged bionic still has a doctor page — a read-only date must not be the
  # reason that page falls back to a whole-transcript count.
  R7G="$(make_repo s7-unengaged)"; new_roster "$R7G"
  S7G_EXPECT="$(s7_birth_iso "$(roster_of "$R7G")" || true)"
  unengage "$R7G"
  poke "$R7G" window
  expect_eq "an UNENGAGED session still gets a window (exit 0)" "0" "$RC"
  expect_eq "…and the same instant an engaged one would get" "$S7G_EXPECT" "$OUT"
fi

# ============================================================
section "Section 8: adopt — the agents a predecessor session left behind"
# ============================================================
#
# WHAT IS LOST ON `/clear`+resume and WHAT IS NOT. Lost: the completion message (delivered
# to a conversation that no longer exists) and the orchestrator's in-memory ledger. NOT
# lost: the agent itself (same process), its artifacts, its transcript under
# `<config>/projects/<slug>/<old-sid>/subagents/agent-<id>.jsonl`, and its roster row. The
# rolled-over session is missing exactly one thing it cannot re-derive — THE AGENT ID — and
# without it the successor can read an agent's files but cannot message or stop it.
#
# So these cases pin `adopt`: every OPEN row on every OTHER session's roster in this
# project, each with its id and the three addresses derived from it, and a verdict taken
# from disk. They also pin the two silences that matter: this session's own rows never
# appear (they are not adopted, they are held), and nothing on disk is written.

ADOPT_A="11111111-aaaa-4bbb-8ccc-000000000001"
ADOPT_B="22222222-aaaa-4bbb-8ccc-000000000002"
ID_LANDED="alanded-one-1111111111111111"
ID_RUNNING="arunning-one-222222222222222a"
ID_SILENT="asilent-one-3333333333333333"
ID_CLOSED="aclosed-one-4444444444444444"
ID_WAIVED="awaived-one-5555555555555556"
ID_RECHECK="arecheck-one-666666666666666"

R8="$(make_repo s8-adopt)"; new_roster "$R8"
mkdir -p "$R8/.bionic/docs/record"

# This session's own open row — the control. `adopt` is about OTHER sessions' work.
add_row "$R8" name=mine-current status=identified agent_id=amine-current-5555555555555555 \
  deliverable="$R8/.bionic/docs/record/mine.md" duration="30 minutes" cadence="10 minutes"

# ---- predecessor A: one landed, one running, one silent, one already swept MET ----
for _n in landed-one running-one silent-one closed-one; do
  add_row_to "$R8" "$ADOPT_A" name="$_n" status=intended agent_id="" \
    subagent_type=bionic:senior-implementor duration="45 minutes" cadence="10 minutes"
done
add_row_to "$R8" "$ADOPT_A" name=landed-one status=identified agent_id="$ID_LANDED" \
  subagent_type=bionic:senior-implementor duration="45 minutes" cadence="10 minutes" \
  deliverable="$R8/.bionic/docs/record/landed-one.md" \
  progress="$R8/.bionic/tmp/progress-landed.md"
# THE SUITE BUDGET THIS AGENT WAS DISPATCHED WITH (S13, spec AC-20). The writer-side guard
# in hooks/background-suite-guard.sh reads `suites_allowed=` off the row for the agent`s
# own id, so a resumed writer whose adopted row lost the field would come out of a /clear
# with no budget on it — and the wall that refuses an off-budget suite would go quiet for
# exactly the agents a clear leaves running longest. `running-one` carries one; the rows
# beside it deliberately do not, which is what makes §8g″ below able to tell a carried
# field from a manufactured one.
add_row_to "$R8" "$ADOPT_A" name=running-one status=identified agent_id="$ID_RUNNING" \
  subagent_type=bionic:implementor duration="45 minutes" cadence="10 minutes" \
  deliverable="$R8/.bionic/docs/record/running-one.md" \
  progress="$R8/.bionic/tmp/progress-running.md" \
  files="payload/scripts/lib/widget.sh,hooks/widget-guard.sh" \
  suites_allowed="alpha.test.sh beta.test.sh" suites_source=derived
add_row_to "$R8" "$ADOPT_A" name=silent-one status=identified agent_id="$ID_SILENT" \
  subagent_type=bionic:implementor duration="45 minutes" cadence="10 minutes" \
  deliverable="$R8/.bionic/docs/record/silent-one.md" \
  progress="$R8/.bionic/tmp/progress-silent.md"
add_row_to "$R8" "$ADOPT_A" name=closed-one status=identified agent_id="$ID_CLOSED" \
  subagent_type=bionic:implementor duration="45 minutes" cadence="10 minutes" \
  deliverable="$R8/.bionic/docs/record/closed-one.md"
# The terminal row. Until epic-23 wave-20 T2 the landing marker alone closed it here; since
# D10 the ONE close is an ack taken after the row's launch (`roster_open_names`,
# payload/scripts/lib/roster.sh; ADR-034 d1), so a MET-marked row nobody acked is ADOPTED —
# its agent may still be on the panel, and an unadopted live agent is one no stop can reach
# (the code in `roster_open_names` is the rule). The marker stays, to show it closes nothing on its own; the
# ack is written by the real verb, in the PREDECESSOR's own ledger, where adopt reads it.
swept_marker_write "$(roster_of "$R8" "$ADOPT_A")" "$(iso_ago 300)" "$ADOPT_A" closed-one "$ID_CLOSED" MET
( cd "$R8" && env CLAUDE_CODE_SESSION_ID="$ADOPT_A" bash "$SWEEPER_FOR_ACK" ack closed-one ) >/dev/null 2>&1

# ---- predecessor A: a Deliverable-waiver row (S17, AC-12 attempt 2) ----
#
# THE FIELD `adopt_write_row` USED TO DROP. This row declares no deliverable and carries a
# waiver instead — hooks/session-sweeper.sh's `verdict_row` reads `waiver=` straight off the
# row (no marker involved) and calls this WAIVED before it ever asks about a deliverable, so
# an adopted copy that lost the field verdicted as an unmet SILENT row for a contract that
# was never open (the live T4 walk this task repairs, ac12-t4-walk-2.md).
add_row_to "$R8" "$ADOPT_A" name=waived-one status=identified agent_id="$ID_WAIVED" \
  subagent_type=bionic:researcher duration="20 minutes" cadence="10 minutes" \
  waiver="probe only — a throwaway read-only agent, S17 fixture"

# ---- predecessor A: a row with a NON-MET landing-swept history (S17 marker carry) ----
#
# A prior stop attempt in the PREDECESSOR session left an UNMET marker on ITS roster before
# the `/clear` — hooks/landing-gate.sh's own recheck arm reads exactly this shape to decide
# "recheck" instead of "first verdict" the next time this name is swept. A MET marker can
# never coexist with an adopted row (a MET name is filtered out of the fold entirely, never
# offered — §8d's `closed-one`, which is also ACKED since epic-23 wave-20 T2 made the ack the
# one close), so the only history worth carrying forward here is a non-MET one.
add_row_to "$R8" "$ADOPT_A" name=recheck-one status=identified agent_id="$ID_RECHECK" \
  subagent_type=bionic:implementor duration="45 minutes" cadence="10 minutes" \
  deliverable="$R8/.bionic/docs/record/recheck-one.md"
swept_marker_write "$(roster_of "$R8" "$ADOPT_A")" "$(iso_ago 200)" "$ADOPT_A" recheck-one "$ID_RECHECK" UNMET

printf 'the report\n' > "$R8/.bionic/docs/record/landed-one.md"
printf 'progress\n'   > "$R8/.bionic/tmp/progress-landed.md"
printf 'progress\n'   > "$R8/.bionic/tmp/progress-running.md"
printf 'progress\n'   > "$R8/.bionic/tmp/progress-silent.md"
backdate "$R8/.bionic/tmp/progress-running.md" 60      # inside 2x a 10-minute cadence
backdate "$R8/.bionic/tmp/progress-silent.md" 5400     # far outside it

# ---- predecessor B: a row the recorder never identified ----
add_row_to "$R8" "$ADOPT_B" name=orphan-one status=intended agent_id="" \
  subagent_type=bionic:researcher duration="20 minutes" cadence="10 minutes" \
  deliverable="$R8/.bionic/docs/record/orphan-one.md"

# AN ID ON AN `intended` ROW IS NOT AN IDENTITY. hooks/dispatch-preflight.sh writes that
# field empty on its own append and the id arrives one state later, so a non-empty one here
# is a forgery or a bug — and hooks/stop-guard.sh already refuses to establish ownership
# from it for exactly that reason ("an intended row carrying an id walked a foreign agent
# past the ownership rule"). `adopt` reads the same accepted set, so this row is
# UNADDRESSABLE and the id it carries is never handed out as an address.
add_row_to "$R8" "$ADOPT_B" name=phantom-id status=intended \
  agent_id=aphantom-id-7777777777777777 \
  subagent_type=bionic:researcher duration="20 minutes" cadence="10 minutes" \
  deliverable="$R8/.bionic/docs/record/phantom-id.md"

# ---- the transcript of the landed agent, under the PREDECESSOR's session dir ----
C8="$(fake_config_dir s8)"
mkdir -p "$C8/projects/-fixture-project/$ADOPT_A/subagents"

long_text() {  # <marker> -> one line well past the "long enough to be a report" floor
  local i=0
  printf '%s ' "$1"
  while [ "$i" -lt 40 ]; do printf 'lorem ipsum dolor sit amet '; i=$((i+1)); done
}
tx_text() {  # <text> — one assistant entry carrying one text block
  printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"%s"}]}}\n' "$1"
}
{
  tx_text "$(long_text EARLIER-LONG-BLOCK)"
  printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_z","name":"Bash","input":{"command":"ls"}}]}}\n'
  tx_text "$(long_text ADOPT-FIXTURE-REPORT-TAIL)"
  tx_text "SHORT-SIGNOFF-MARKER"
} > "$C8/projects/-fixture-project/$ADOPT_A/subagents/agent-${ID_LANDED}.jsonl"

export CLAUDE_CONFIG_DIR="$C8"

# THE PREDECESSOR ROSTERS ARE THE READ-ONLY HALF, and they are what this cksum brackets.
# `adopt` writes exactly one file — the ADOPTING session's own roster (§8g) — so a bracket
# over every roster in the directory could no longer separate "wrote its own row" from
# "wrote into a predecessor's file", which is the thing that must never happen: those rows
# belong to a session that may still be appending to them, and a reader-modifies-writer
# would drop rows appended concurrently (hooks/execution-recorder.sh:399-419).
_before="$(cd "$R8/.bionic/tmp" && cksum "roster-$ADOPT_A.state" "roster-$ADOPT_B.state")"
_own_before="$(cksum < "$(roster_of "$R8")")"
poke "$R8" adopt
ADOPT_OUT="$OUT"   # kept for §8h's paired positive, which runs after later `poke`s
_after="$(cd "$R8/.bionic/tmp" && cksum "roster-$ADOPT_A.state" "roster-$ADOPT_B.state")"
_own_after="$(cksum < "$(roster_of "$R8")")"

# ---------- 8a: the id and the three addresses it buys ----------
expect_contains "the landed agent's id is printed" "$ID_LANDED" "$OUT"
expect_contains "the observe address is the predecessor's own subagent transcript" \
  "$C8/projects/-fixture-project/$ADOPT_A/subagents/agent-${ID_LANDED}.jsonl" "$OUT"
# THE MESSAGE ADDRESS IS THE NAME (T22, A-orch-33). It was the transcript-form id until
# 2026-09-14, when a SendMessage to an id that a `/clear` had re-keyed made the harness
# RESUME A COPY of the agent while the original was still running — two agents, one
# contract, one roster row. The agent table is lost across a `/clear`; the TEAMMATE table,
# which is keyed on the name, is not. So the id keeps the two lines it is actually the key
# for — the observe path and the stop — and the address a human or a model types is the
# bare name.
expect_contains "the message address is a SendMessage by NAME" "SendMessage to:landed-one" "$OUT"
expect_absent "…never by transcript id, which resumes a copy after a /clear" \
  "SendMessage to:$ID_LANDED" "$OUT"
# THE ADDRESS THE PLATFORM ACCEPTS, and not the one this verb happens to hold. The id
# `adopt` reads off the roster is the TRANSCRIPT form (`aname-<hex>`); the stop primitive
# takes `<name>@session-<id8>` for a teammate (capture
# record/session-20260814-wave-detector-terminal-state/min/logs/A-p3.jsonl:9), and printing
# the other one handed the operator a line they could not type.
#
# THE SESSION NAMED IS THE ONE THAT LAUNCHED THE AGENT (T3 FINDING 1, live 2026-09-03). The
# suffix used to be the ADOPTING session's, on the probe's reading that a `/clear` re-keys
# `CLAUDE_CODE_SESSION_ID` and therefore re-keys the address with it. The live harness says
# otherwise: driven through a real `/clear`, `TaskStop PROBE-AGENT@session-<adopting 8>`
# came back `No task found with ID: … Running teammates: PROBE-AGENT@session-<launching 8>`.
# The teammate table keys on the session that made the `Agent` call and the roll-over does
# not move it, so the address is built from the row's OWN `session=` field — the session it
# is filed under — and never from ours.
expect_contains "the stop address names the session that LAUNCHED the agent" \
  "TaskStop landed-one@session-${ADOPT_A:0:8}" "$OUT"
expect_absent "…never the transcript-form id, which the platform rejects for a teammate" \
  "TaskStop $ID_LANDED" "$OUT"
expect_absent "…and never the ADOPTING session's eight, which the harness answered nothing to" \
  "landed-one@session-${SID:0:8}" "$OUT"
# THE BARE NAME IS PRINTED BESIDE IT, because it is the one spelling that survived every
# step of the live drive: `TaskStop PROBE-AGENT` reached the stop wall before the `/clear`
# and after it, and it is what finally stopped the adopted agent. A suffixed address is a
# guess about which session the harness keys on; the bare name is not.
expect_contains "…with the bare name beside it, as the address that always survives" \
  "TaskStop landed-one — the bare name" "$OUT"
# THE MACHINE LINE CARRIES BOTH, so a reader that parses rather than greps gets the address
# without re-deriving it from two other fields.
expect_contains "the machine line carries the stop address" \
  "|address=landed-one@session-${ADOPT_A:0:8}|" "$OUT"
expect_contains "…beside the bare name it was built from" "|name=landed-one|" "$OUT"
expect_contains "the row names the predecessor session it came from" "from=$ADOPT_A" "$OUT"
expect_contains "the row carries its subagent_type" "bionic:senior-implementor" "$OUT"

# ---------- 8b: the four verdicts ----------
expect_contains "a deliverable on disk reads LANDED" "name=landed-one|verdict=LANDED" "$OUT"
expect_contains "a fresh progress file inside its cadence reads RUNNING" \
  "name=running-one|verdict=RUNNING" "$OUT"
expect_contains "a stale progress file reads SILENT" "name=silent-one|verdict=SILENT" "$OUT"
expect_contains "a row with no identified line reads UNADDRESSABLE" \
  "name=orphan-one|verdict=UNADDRESSABLE" "$OUT"
expect_contains "the second predecessor roster is scanned too" "from=$ADOPT_B" "$OUT"
expect_contains "an id on an intended row is no identity — that row is UNADDRESSABLE too" \
  "name=phantom-id|verdict=UNADDRESSABLE" "$OUT"
expect_absent "…and its id is never handed out as an address" \
  "TaskStop aphantom-id-7777777777777777" "$OUT"

# ---------- 8b′: the carried waiver, S17 (AC-12 attempt 2) ----------
#
# A row with no declared deliverable used to read SILENT — the same rendering as a row that
# never delivered anything and never will. The carried `waiver=` field is what tells the two
# apart, and it must outrank the deliverable/liveness checks: a waived contract is not "quiet
# for now", it was never open.
expect_contains "a carried waiver reads WAIVED, not SILENT" \
  "name=waived-one|verdict=WAIVED" "$OUT"
expect_absent "…never the misleading SILENT this row used to print" \
  "name=waived-one|verdict=SILENT" "$OUT"

# ---------- 8c: the report tail, extracted from the transcript ----------
expect_contains "the landed agent's report tail is printed" "ADOPT-FIXTURE-REPORT-TAIL" "$OUT"
expect_absent "…the LAST long block, not an earlier one" "EARLIER-LONG-BLOCK" "$OUT"
expect_absent "…and not a short sign-off that followed it" "SHORT-SIGNOFF-MARKER" "$OUT"
expect_contains "an agent with no transcript on disk says so" "transcript_present=no" "$OUT"

# ---------- 8d: what adopt must NOT do ----------
expect_absent "this session's own rows are never adopted" "mine-current" "$OUT"
expect_contains "8d meta: closed-one's ack is on the predecessor's own ledger" "|name=closed-one|" \
  "$(cat "$R8/.bionic/tmp/sweeper-$ADOPT_A.state" 2>/dev/null)"
expect_absent "a row acked after its launch is closed, not adopted" "closed-one" "$OUT"
expect_eq "no PREDECESSOR roster is modified — not one byte" "$_before" "$_after"
expect_eq "adopt writes no Patrol stamp — it is not a tick" "no" \
  "$([ -e "$R8/.bionic/tmp/patrol-${SID}.state" ] && echo yes || echo no)"
expect_eq "open predecessor rows exit in the NOTIFY band" 1 "$RC"

# ---------- 8e: an ack taken in the dead session still closes its row ----------
# "An ack taken in a session that has since died is still in force in its successor"
# (hooks/session-sweeper.sh's own ledger comment). The ack is planted through the real verb
# under the PREDECESSOR's session key, never by hand-writing a ledger line.
( cd "$R8" && env CLAUDE_CODE_SESSION_ID="$ADOPT_A" bash "$SWEEPER_FOR_ACK" ack silent-one ) \
  >/dev/null 2>&1
poke "$R8" adopt
expect_absent "an acked predecessor row is closed for adopt too" "name=silent-one" "$OUT"
expect_contains "…and its unacked siblings still adopt" "name=landed-one" "$OUT"

# ---------- 8g: the adopted row, written into THIS session's roster ----------
#
# WHAT THE ROW BUYS. Reading a predecessor's id back is not enough to ACT on the agent:
# hooks/stop-guard.sh reads ownership off THIS session's roster, and with no row carrying
# the id it classifies the target FOREIGN and refuses every stop of it. The row is the
# successor session saying, on disk, "this contract is mine now" — status `identified`
# because the id is known, `adopted_from=` because where it came from is a fact worth
# keeping, and `teammate_id=` because that is the only spelling the stop primitive takes.
#
# The predecessor's file is never touched (8d): a row is COPIED FORWARD, not moved.
OWN_ROSTER="$(roster_of "$R8")"
ADOPTED_ROW="$(grep -F "|name=landed-one|" "$OWN_ROSTER" | tail -1)"

expect_eq "the adopting session's own roster IS written" "no" \
  "$([ "$_own_before" = "$_own_after" ] && echo yes || echo no)"
expect_contains "the adopted row is status=identified — the id is known" \
  "|status=identified|" "$ADOPTED_ROW"
expect_contains "…filed under the ADOPTING session's key" "|session=$SID|" "$ADOPTED_ROW"
expect_contains "…carrying the transcript-form agent id the predecessor recorded" \
  "|agent_id=$ID_LANDED|" "$ADOPTED_ROW"
# THE ADDRESS FORM THE STOP PRIMITIVE TAKES, built from the session that LAUNCHED the
# agent (T3 FINDING 1). hooks/stop-guard.sh prefers this recorded address over the one it
# would construct, so a row carrying the adopting session's eight would put the address the
# live harness rejects into every refusal the gate prints.
expect_contains "…and the address form the stop primitive takes, built from the LAUNCHING session" \
  "|teammate_id=landed-one@session-${ADOPT_A:0:8}|" "$ADOPTED_ROW"
expect_absent "…never this session's eight, which the teammate table answers nothing to" \
  "|teammate_id=landed-one@session-${SID:0:8}|" "$ADOPTED_ROW"
expect_contains "…the contracted deliverable, copied forward" \
  "|deliverable=$R8/.bionic/docs/record/landed-one.md|" "$ADOPTED_ROW"
expect_contains "…its progress artifact" \
  "|progress=$R8/.bionic/tmp/progress-landed.md|" "$ADOPTED_ROW"
expect_contains "…its declared cadence" "|cadence=10 minutes|" "$ADOPTED_ROW"
expect_contains "…and the provenance of the adoption" "|adopted_from=$ADOPT_A|" "$ADOPTED_ROW"
expect_contains "the roster file carries its schema header" "roster-state/v1" \
  "$(head -1 "$OWN_ROSTER")"

# ---------- 8g″: the carried suite budget (S13, spec AC-20) ----------
#
# THREE FIELDS, CARRIED AS A GROUP. `files=` is what the brief declared it would touch,
# `suites_allowed=` the set derived or declared from it, `suites_source=` which of the two
# it was. hooks/background-suite-guard.sh reads the second off the row belonging to the
# calling agent`s id, and a /clear is exactly when it matters most: the agents that survive
# one are the long-running writers, and a budget that evaporates at the resume leaves the
# wall silent for them.
BUDGET_ROW="$(grep -F "|name=running-one|" "$OWN_ROSTER" | tail -1)"
expect_contains "the adopted row carries the derived suite budget forward" \
  "|suites_allowed=alpha.test.sh beta.test.sh|" "$BUDGET_ROW"
expect_contains "…the files the brief declared" \
  "|files=payload/scripts/lib/widget.sh,hooks/widget-guard.sh|" "$BUDGET_ROW"
expect_contains "…and where the set came from, so no reader mistakes derived for declared" \
  "|suites_source=derived|" "$BUDGET_ROW"

# A PRE-WALL ROW ADOPTS WITHOUT MANUFACTURING ONE. Absent is a third state, distinct from
# present-and-empty: the guard reads an empty `suites_allowed=` as "a budget was stated and
# came out empty" and an absent key as "this row predates the wall". An adopt that invented
# the first from the second would put a statement on the roster that nobody made.
NOBUDGET_ROW="$(grep -F "|name=waived-one|" "$OWN_ROSTER" | tail -1)"
expect_absent "a source row with no budget adopts with no budget field at all" \
  "suites_allowed=" "$NOBUDGET_ROW"
expect_absent "…nor a source for a set it does not carry" "suites_source=" "$NOBUDGET_ROW"
# NON-VACUITY: that row IS an adopted row, so the two absences above are the group being
# withheld and not a row that failed to be written.
expect_contains "…while still being a real adopted row" "|adopted_from=$ADOPT_A|" "$NOBUDGET_ROW"

# ---------- 8g′: the carried waiver and the copied marker (S17, AC-12 attempt 2) ----------
#
# THE WAIVER. `adopt_write_row` used to hard-code `waiver=` empty on every adopted row —
# the one contract field this fold read off the source and then threw away. Carried
# forward here exactly as the other contract fields are (deliverable/progress/cadence).
WAIVED_ROW="$(grep -F "|name=waived-one|" "$OWN_ROSTER" | tail -1)"
expect_contains "the adopted row carries the source's waiver, not an empty field" \
  "|waiver=probe only — a throwaway read-only agent, S17 fixture|" "$WAIVED_ROW"

# THE MARKER. `hooks/landing-gate.sh` is the schema's one writer today (its own comment,
# :561-563, calls a second writer "not a live path" — this makes it one, deliberately, by
# COPYING a line that writer already produced, never originating a new verdict). Copied so
# that `hooks/session-start.sh`'s `open_rows` and this file's own `youngest_suite_writer` —
# both of which read a `landing-swept/v1` line straight off the SAME roster file as ground
# truth, with no re-derivation — see the same history on the successor roster that stood on
# the predecessor's.
RECHECK_MARKERS="$(grep -F "${SWEPT_SCHEMA}|" "$OWN_ROSTER" | grep -F '|name=recheck-one|')"
expect_contains "the source's non-MET marker is copied onto the successor roster" \
  "state=UNMET" "$RECHECK_MARKERS"
expect_eq "…verbatim, exactly once" "1" "$(printf '%s\n' "$RECHECK_MARKERS" | grep -c .)"
# closed-one (§8d) is acked, so the fold excludes it from adoption entirely and there is no
# adopted row here for its MET marker to attach to.
expect_absent "a MET marker is never copied — there is no adopted row it could attach to" \
  "name=closed-one" "$(grep -F "${SWEPT_SCHEMA}|" "$OWN_ROSTER")"

# A ROW WITH NO ID BUYS NOTHING, so none is written. UNADDRESSABLE is the whole point of
# that verdict: there is no identity to file, and a row carrying an empty `agent_id=` would
# be inert at every by-id reader while looking like an adoption on disk.
expect_absent "an UNADDRESSABLE row is not adopted onto the roster" \
  "name=orphan-one" "$(cat "$OWN_ROSTER")"
expect_absent "…nor is the phantom id on an intended row" \
  "name=phantom-id" "$(cat "$OWN_ROSTER")"

# IDEMPOTENT. `adopt` is the FIRST thing a resumed session runs and it is run again on the
# next resume; an append per run would grow the roster without adding a fact, and every
# reader would re-read the same contract N times.
_dup_before="$(grep -c -F "|name=landed-one|" "$OWN_ROSTER")"
_marker_dup_before="$(grep -F "${SWEPT_SCHEMA}|" "$OWN_ROSTER" | grep -c -F '|name=recheck-one|')"
poke "$R8" adopt
_dup_after="$(grep -c -F "|name=landed-one|" "$OWN_ROSTER")"
_marker_dup_after="$(grep -F "${SWEPT_SCHEMA}|" "$OWN_ROSTER" | grep -c -F '|name=recheck-one|')"
expect_eq "a second adopt appends no second row for the same agent" "$_dup_before" "$_dup_after"
expect_eq "…nor a second copy of the carried marker" "$_marker_dup_before" "$_marker_dup_after"

# ---------- 8h: A NAME ALREADY LIVE HERE NEVER GETS A SECOND LIVE ROW (T6, AC-6.1) --------
#
# The idempotence check above is BY AGENT ID — a second agent, under a DIFFERENT id, adopted
# under the SAME name is not what it catches. Two live rows of one name is exactly the
# ambiguity `hooks/stop-guard.sh`'s own stop refusal exists to police (T29 §7); this proves
# the write side never manufactures it in the first place.
R8N="$(make_repo s8-live-name-collision)"; new_roster "$R8N"
ID_LIVE_OWN="alreadylive-88888888888888"
ID_PRED_DUP="predecessor-dup-8888888888"
PRED_8N="d8d8d8d8-1111-4bbb-8ccc-000000000088"
# THIS SESSION'S OWN roster already carries a LIVE row named dup-writer.
add_row "$R8N" name=dup-writer status=identified agent_id="$ID_LIVE_OWN" \
  deliverable="$R8N/own.md" duration="4 hours" launched_at="$(iso_ago 60)"
# A PREDECESSOR's roster carries a DIFFERENT agent under the identical name, still open.
add_row_to "$R8N" "$PRED_8N" name=dup-writer status=identified agent_id="$ID_PRED_DUP" \
  deliverable="$R8N/pred.md" duration="4 hours" launched_at="$(iso_ago 90)"
poke "$R8N" adopt
OWN_ROSTER_8N="$(cat "$(roster_of "$R8N")")"
expect_contains "a name already live here adopts under the next free -r<n>, not the name asked for" \
  "|name=dup-writer-r2|" "$OWN_ROSTER_8N"
expect_contains "…and the renamed row is the adopted one" \
  "adopted_from=$PRED_8N" "$(grep -F '|name=dup-writer-r2|' "$(roster_of "$R8N")")"
expect_eq "…exactly one live row still carries the bare name" "1" \
  "$(printf '%s\n' "$OWN_ROSTER_8N" | grep -cF '|name=dup-writer|')"
expect_contains "…and the tick says so once, on stderr" \
  "adopt: 'dup-writer' is already live on this session's roster — writing this row as 'dup-writer-r2'" \
  "$OUT"

# THE RENAME IS STILL IDEMPOTENT: a second `adopt` for the SAME predecessor id appends
# nothing new, by the SAME agent_id+adopted_from check every other adopt idempotence proves.
_dup8n_before="$(grep -cF '|name=dup-writer-r2|' "$(roster_of "$R8N")")"
poke "$R8N" adopt
_dup8n_after="$(grep -cF '|name=dup-writer-r2|' "$(roster_of "$R8N")")"
expect_eq "a second adopt of the same predecessor id renames nothing twice" \
  "$_dup8n_before" "$_dup8n_after"

# ---------- 8f: nothing to adopt, and no session key ----------
R8B="$(make_repo s8-alone)"; new_roster "$R8B"
add_row "$R8B" name=only-mine status=identified agent_id=aonly-mine-6666666666666666
poke "$R8B" adopt
expect_eq "a project with no predecessor roster exits 0" 0 "$RC"
expect_contains "…and says so rather than printing nothing" "nothing to adopt" "$OUT"

OUT="$( cd "$R8" && CLAUDE_CODE_SESSION_ID="" bash "$POKER" adopt 2>&1 )"; RC=$?
expect_eq "adopt with no session key REFUSES with exit 3" "3" "$RC"

# ---------- 8h: a row the roster REFUSED buys no stop address (review-a C-3) ----------
#
# `die()` prints and returns — it does not exit (hooks/session-poker.sh:156, and the tick
# depends on that). So a failed `adopt_write_row` used to warn and then print the address
# block anyway: `TaskStop <name>@session-<id8>` for a row that is not on this session's
# roster, which is exactly what both stop gates refuse as FOREIGN. The operator was handed
# a line that cannot work, at the one moment they are trying to reach an adopted agent.
#
# THE WRITE IS MADE TO FAIL THROUGH THE WRITER'S OWN REFUSAL — a symlink where the roster
# goes, which `adopt_write_row` declines like every other .bionic/tmp writer in the fleet.
# Never a chmod: a suite that runs as root would silently stop failing.
R8U="$(make_repo s8-roster-refused)"
mkdir -p "$R8U/.bionic/docs/record"
add_row_to "$R8U" "$ADOPT_A" name=landed-two status=identified \
  agent_id=alanded-two-7777777777777777 subagent_type=bionic:implementor \
  duration="45 minutes" cadence="10 minutes" \
  deliverable="$R8U/.bionic/docs/record/landed-two.md"
printf 'the report\n' > "$R8U/.bionic/docs/record/landed-two.md"
ln -s "$R8U/.bionic/tmp/not-a-roster.state" "$(roster_of "$R8U")"
poke "$R8U" adopt
expect_contains "the refused row is still REPORTED — the read half is unaffected" \
  "landed-two" "$OUT"
expect_contains "…with its id, which is a fact the roster write did not change" \
  "alanded-two-7777777777777777" "$OUT"
expect_absent "…but no stop address, because the row the gates read was never written" \
  "TaskStop" "$OUT"
expect_contains "…the stop line naming the write that failed instead" \
  "NOT journalled" "$OUT"
expect_contains "…and the cure, in terms of what the gates actually read" \
  "ownership from THIS session" "$OUT"
# Exit 1 is `adopt`'s "there are rows for you to ledger" signal, taken whenever it found
# any (`ADOPT_ROWS > 0`) — a warned write does not change it, and this pins that it does not.
expect_eq "…and the verb still exits 1: the found-rows signal, not a refusal" "1" "$RC"

# THE PAIRED POSITIVE is §8a on the same rendering: with the roster writable, the SAME
# block prints `TaskStop landed-one@session-…`. Without that pairing this case would pass
# against a verb that had simply stopped printing addresses at all.
expect_contains "the writable-roster fixture still offers the stop address (§8a's row)" \
  "TaskStop landed-one@session-" "$ADOPT_OUT"

# ---------- 8i: --report-only reads without writing (1.4, AC-4) ----------
#
# THE SessionStart BLOCK RUNS THIS ONE. `adopt` is the right verb for a model that has
# decided to take the predecessor's rows over; it is the wrong verb for a hook that fires
# on every resume, because a session that merely STARTED in this project would file rows
# for agents it may have no business holding. `--report-only` is the same read with the
# write removed, so the block can print the truth and leave the taking to the operator.
#
# The two halves are pinned separately, because either alone is passable by a verb that
# does the wrong thing: "writes nothing" is satisfied by a verb that prints nothing, and
# "prints the same rows" is satisfied by a verb that writes anyway.
R8R="$(make_repo s8-report-only)"; new_roster "$R8R"
mkdir -p "$R8R/.bionic/docs/record"
add_row_to "$R8R" "$ADOPT_A" name=landed-three status=identified \
  agent_id=alanded-three-88888888888888 subagent_type=bionic:implementor \
  duration="45 minutes" cadence="10 minutes" \
  deliverable="$R8R/.bionic/docs/record/landed-three.md"
printf 'the report\n' > "$R8R/.bionic/docs/record/landed-three.md"

_ro_pred_before="$(cd "$R8R/.bionic/tmp" && cksum "roster-$ADOPT_A.state")"
_ro_own_before="$(cksum < "$(roster_of "$R8R")")"
poke "$R8R" adopt --report-only
RO_OUT="$OUT"; RO_RC="$RC"
_ro_pred_after="$(cd "$R8R/.bionic/tmp" && cksum "roster-$ADOPT_A.state")"
_ro_own_after="$(cksum < "$(roster_of "$R8R")")"

expect_eq "--report-only leaves the predecessor roster byte-identical" \
  "$_ro_pred_before" "$_ro_pred_after"
expect_eq "--report-only leaves THIS session's roster byte-identical" \
  "$_ro_own_before" "$_ro_own_after"
expect_absent "…so the previewed row is NOT filed" "name=landed-three|" \
  "$(cat "$(roster_of "$R8R")")"
expect_contains "…and the verb says which mode it ran in" "report-only" "$RO_OUT"
expect_eq "…while the found-rows signal is unchanged (exit 1)" "1" "$RO_RC"

# THE ROWS ARE THE WRITING VERB'S ROWS. Compared with the wall-clock `at=` stamps
# normalised — the one field that legitimately differs between two runs a second apart —
# and with the mode line itself removed, since that line is the only thing that may differ.
# This is what makes the SessionStart block's output trustworthy: the operator reads the
# report, and `adopt` then files exactly what they were shown.
ro_rows() { printf '%s\n' "$1" | grep -v 'report-only' | sed -E 's/\|at=[^|]*\|/|at=X|/'; }
poke "$R8R" adopt
expect_eq "--report-only's rendering is the writing verb's, line for line" \
  "$(ro_rows "$RO_OUT")" "$(ro_rows "$OUT")"
expect_contains "…and the writing verb DID file the row that was previewed" \
  "|name=landed-three|" "$(cat "$(roster_of "$R8R")")"
expect_contains "…including the stop address the preview printed" \
  "TaskStop landed-three@session-" "$RO_OUT"

# Nothing to adopt, in report-only: the same silence and the same exit 0.
R8RB="$(make_repo s8-report-only-alone)"; new_roster "$R8RB"
poke "$R8RB" adopt --report-only
expect_eq "--report-only with no predecessor roster exits 0" "0" "$RC"
expect_contains "…and says so" "nothing to adopt" "$OUT"

# The flag is the ONLY second argument any verb takes; anything else is still a usage error.
poke "$R8R" adopt --bogus
expect_eq "an unknown flag after adopt is a usage error (exit 2)" "2" "$RC"
poke "$R8R" tick --report-only
expect_eq "…and --report-only is not a flag the tick takes" "2" "$RC"

# ---------- 8j: liveness reads the TRANSCRIPT too (1.6, AC-6) ----------
#
# THE DEFECT. A row was RUNNING only while its PROGRESS FILE was fresh, and a progress file
# is a promise the agent keeps by hand — the first thing a working agent drops when the work
# gets absorbing, and the one artifact a role without Write cannot produce at all. The agent
# is nevertheless observable: its transcript is appended to by the harness on every turn,
# under `<config>/projects/<slug>/<launching sid>/subagents/agent-<id>.jsonl`, which is the
# same file this verb already prints as the observe address. So liveness is now the OR of
# the two mtimes, and SILENT means both of them are stale — an agent that has neither
# written a line nor taken a turn inside the window its own row declared.
#
# THE WINDOW is ONE declared cadence, and the classification is `observe_class`'s
# (payload/scripts/lib/observe.sh; REQ-10 D9, which retired this verb's own doubled window —
# the fleet had two answers to one question). The mutation at the end of this block is what
# proves the verdict comes from that function rather than from arithmetic here.
R8L="$(make_repo s8-liveness)"; new_roster "$R8L"
mkdir -p "$R8L/.bionic/docs/record"
ID_TXFRESH="atxfresh-one-9999999999999999"
ID_TXSTALE="atxstale-one-aaaaaaaaaaaaaaaa"
SUB8="$C8/projects/-fixture-project/$ADOPT_A/subagents"

for _pair in "tx-fresh $ID_TXFRESH" "tx-stale $ID_TXSTALE"; do
  set -- $_pair
  add_row_to "$R8L" "$ADOPT_A" name="$1" status=identified agent_id="$2" \
    subagent_type=bionic:implementor duration="45 minutes" cadence="10 minutes" \
    deliverable="$R8L/.bionic/docs/record/$1.md" \
    progress="$R8L/.bionic/tmp/progress-$1.md"
  # The progress half is stale for BOTH rows: this block is about the other input, and a
  # fresh progress file would answer RUNNING without the transcript ever being stat'd.
  printf 'progress\n' > "$R8L/.bionic/tmp/progress-$1.md"
  backdate "$R8L/.bionic/tmp/progress-$1.md" 5400
  : > "$SUB8/agent-$2.jsonl"
done
# …and the transcripts differ: one written just now, one as old as the progress files.
backdate "$SUB8/agent-$ID_TXSTALE.jsonl" 5400

poke "$R8L" adopt --report-only
expect_contains "a stale progress file with a FRESH transcript still reads RUNNING" \
  "name=tx-fresh|verdict=RUNNING" "$OUT"
expect_contains "…and both mtimes stale reads SILENT" \
  "name=tx-stale|verdict=SILENT" "$OUT"
expect_contains "…the transcript's age is printed, so the verdict can be checked" \
  "transcript_age=" "$OUT"

# THE WINDOW IS ONE CADENCE, AND THE PREDICATE IS THE LIBRARY'S (re-authored at REQ-10 D9).
# This block used to prove the window was `PATROL_STALE_MULTIPLIER x cadence` by mutating the
# constant. The fleet carried four staleness arithmetics for three questions, two of them
# over a row and a cadence — `observe_class` at one cadence (payload/scripts/lib/observe.sh)
# and this verb at two — so a row read alive to one reader and silent to the other. D9 keeps
# the library's: one cadence, both readers, and the tick's own row loop asks the same
# function. A row 1.5 cadences quiet is SILENT now, where the doubled window called it
# RUNNING.
R8M="$(make_repo s8-window)"; new_roster "$R8M"
mkdir -p "$R8M/.bionic/docs/record"
add_row_to "$R8M" "$ADOPT_A" name=between status=identified \
  agent_id=abetween-one-bbbbbbbbbbbbbbbb subagent_type=bionic:implementor \
  duration="45 minutes" cadence="10 minutes" \
  deliverable="$R8M/.bionic/docs/record/between.md" \
  progress="$R8M/.bionic/tmp/progress-between.md"
printf 'progress\n' > "$R8M/.bionic/tmp/progress-between.md"
backdate "$R8M/.bionic/tmp/progress-between.md" 900   # 1.5x a 10-minute cadence

poke "$R8M" adopt --report-only
expect_contains "at 1.5x the declared cadence the row is SILENT — one cadence, not two" \
  "name=between|verdict=SILENT" "$OUT"

# THE BOUNDARY, FROM THE OTHER SIDE. Half a cadence is RUNNING, so the row above is not
# SILENT because this verb stopped reading mtimes.
R8N="$(make_repo s8-window-inside)"; new_roster "$R8N"
mkdir -p "$R8N/.bionic/docs/record"
add_row_to "$R8N" "$ADOPT_A" name=inside status=identified \
  agent_id=ainside-one-bbbbbbbbbbbbbbbc subagent_type=bionic:implementor \
  duration="45 minutes" cadence="10 minutes" \
  deliverable="$R8N/.bionic/docs/record/inside.md" \
  progress="$R8N/.bionic/tmp/progress-inside.md"
printf 'progress\n' > "$R8N/.bionic/tmp/progress-inside.md"
backdate "$R8N/.bionic/tmp/progress-inside.md" 300    # half a cadence
poke "$R8N" adopt --report-only
expect_contains "…and half a cadence still reads RUNNING" \
  "name=inside|verdict=RUNNING" "$OUT"

# THE VERDICT IS THE LIBRARY'S ANSWER, proven by mutation — the same shape the multiplier
# proof used, aimed at the function that owns the question now. A copy of the library whose
# `observe_class` always answers `alive` must turn the SILENT row above into a RUNNING one; a
# verb carrying its own arithmetic would answer SILENT against both trees. The doctored tree
# is the shape the plugin ships (hooks/ beside scripts/lib) and its library is a COPY,
# because this is the one fixture that must not read the shipped predicate.
OBS_MUT_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/poker-obs-mut.XXXXXX")"
mkdir -p "$OBS_MUT_ROOT/hooks" "$OBS_MUT_ROOT/scripts"
cp -R "$(cd "$(dirname "$POKER")/../payload/scripts/lib" && pwd -P)" "$OBS_MUT_ROOT/scripts/lib"
cat >> "$OBS_MUT_ROOT/scripts/lib/observe.sh" <<'OBS_MUT'

observe_class() { OBS_CLASS=alive; echo alive; return 0; }
OBS_MUT
cp "$POKER" "$OBS_MUT_ROOT/hooks/session-poker.sh"
if grep -qF 'OBS_CLASS=alive; echo alive' "$OBS_MUT_ROOT/scripts/lib/observe.sh"; then
  ok "8j meta: the doctored predicate landed (the pair below proves something)"
else
  no "8j meta: the doctored predicate did NOT land — the pair below proves nothing"
fi
OUT="$( cd "$R8M" && env CLAUDE_CODE_SESSION_ID="$SID" \
        bash "$OBS_MUT_ROOT/hooks/session-poker.sh" adopt --report-only 2>&1 )"
expect_contains "…and the SAME row reads RUNNING against a library whose predicate says alive" \
  "name=between|verdict=RUNNING" "$OUT"

# ---------- 8k: the ADOPT REPORT reads the ADOPTER's transcript too (T1d, walk W-3) ----------
#
# THE DEFECT THIS PINS. `row_quiet` (§8j's own comment, D4/REQ-2) already prefers THIS
# session's copy of an agent's transcript over the launching session's — the harness re-files
# a transcript under whichever session is talking to the agent NOW. But `adopt`'s own report
# (the `poker-adopt/v1|...` line and the human-readable `observe :` tail) used to build its
# `transcript=`/`transcript_age=` fields from the LAUNCHING session's copy only, unconditionally
# — so a re-run of `adopt --report-only` after this session had already exchanged a turn with
# the agent (the fresh copy now sitting under THIS session's subagents dir) still quoted the
# launcher's stale path and its large age, disagreeing with what the very next tick would say
# about the identical row. `agent_log_newest` is the fix (D8, superseding `transcript_dir_for`):
# one resolver, called by both.
R8K="$(make_repo s8-adopter-transcript)"; new_roster "$R8K"
mkdir -p "$R8K/.bionic/docs/record"
ID_ADOPTER_PREF="aadopterpref-onexxxxxxxxxxxxx"
add_row_to "$R8K" "$ADOPT_A" name=adopter-pref status=identified \
  agent_id="$ID_ADOPTER_PREF" subagent_type=bionic:implementor \
  duration="45 minutes" cadence="10 minutes" \
  deliverable="$R8K/.bionic/docs/record/adopter-pref.md" \
  progress="$R8K/.bionic/tmp/progress-adopter-pref.md"
# The progress channel is stale on BOTH candidate reads, so the transcript channel is the one
# this case is about.
printf 'progress\n' > "$R8K/.bionic/tmp/progress-adopter-pref.md"
backdate "$R8K/.bionic/tmp/progress-adopter-pref.md" 5400

# THE LAUNCHER'S COPY: old, the shape the pre-fix report always named.
mkdir -p "$C8/projects/-fixture-project/$ADOPT_A/subagents"
: > "$C8/projects/-fixture-project/$ADOPT_A/subagents/agent-${ID_ADOPTER_PREF}.jsonl"
backdate "$C8/projects/-fixture-project/$ADOPT_A/subagents/agent-${ID_ADOPTER_PREF}.jsonl" 1415

# THE ADOPTER'S OWN COPY (this session, $SID — what `poke` sets CLAUDE_CODE_SESSION_ID to):
# newer, because this is the session `adopt --report-only` is about to run as.
mkdir -p "$C8/projects/-fixture-project/$SID/subagents"
: > "$C8/projects/-fixture-project/$SID/subagents/agent-${ID_ADOPTER_PREF}.jsonl"
backdate "$C8/projects/-fixture-project/$SID/subagents/agent-${ID_ADOPTER_PREF}.jsonl" 60

poke "$R8K" adopt --report-only
expect_contains "the report names the ADOPTER's transcript path, not the launcher's" \
  "transcript=$C8/projects/-fixture-project/$SID/subagents/agent-${ID_ADOPTER_PREF}.jsonl|" \
  "$OUT"
expect_absent "…never the launcher's stale path" \
  "transcript=$C8/projects/-fixture-project/$ADOPT_A/subagents/agent-${ID_ADOPTER_PREF}.jsonl|" \
  "$OUT"
expect_regex "…and the small (adopter-side) age, not the launcher's large one" \
  'transcript_age=6[0-9][|]plan=' "$OUT"
expect_absent "…never the launcher's 1415s age" "transcript_age=1415|" "$OUT"
expect_contains "…the human-readable tail names the same adopter path" \
  "observe     : $C8/projects/-fixture-project/$SID/subagents/agent-${ID_ADOPTER_PREF}.jsonl" \
  "$OUT"

unset CLAUDE_CONFIG_DIR

# ============================================================
section "Section 9: disarm — the deliberate stop, made readable"
# ============================================================
#
# epic-19 wave-01 Step-6 repair, critic C-2.
#
# WHY THE VERB EXISTS. hooks/patrol-revive.sh blocks a turn whenever THIS session's stamp
# is older than 2x the interval, and it repeats that on every turn — `stop_hook_active`
# suppresses only the second stop inside one turn, and it resets at the next. Nothing in
# production ever REMOVED a stamp, so the two ordinary ways a run ends its own Patrol — the
# run-close `CronDelete` skills/canonical-sdlc/SKILL.md mandates, and this script's own
# DISARM decision, reached on every quiet stretch between dispatch batches — each left an
# aging stamp behind and turned a deliberate stop into an unbounded per-turn death notice
# demanding the re-arm the poker had just said was unnecessary.
#
# The stamp is the only record on disk that a Patrol runs here, so removing it is the
# readable fact "this one was ended on purpose", and the revive hook's ABSENT state is
# silent by design. Every case below drives the REAL verb: nothing here removes a stamp by
# hand, because what is being pinned is that the poker owns both ends of its own liveness
# record.

R9="$(make_repo s9-disarm)"
poke "$R9" arm
expect_eq "the fixture arms first (exit 0)" "0" "$RC"
expect_eq "…and the stamp is on disk before the disarm — the precondition, proven" "yes" \
  "$([ -f "$(stamp_of "$R9")" ] && echo yes || echo no)"

poke "$R9" disarm
expect_eq "disarm exits 0" "0" "$RC"
expect_eq "…and the stamp is gone" "no" \
  "$([ -e "$(stamp_of "$R9")" ] && echo yes || echo no)"
expect_contains "…and the message names the stamp it removed" "$(stamp_of "$R9")" "$OUT"

# IDEMPOTENT. A run-close ritual run twice, or a session that never armed at all, must not
# turn a no-op into a failure the operator has to interpret.
poke "$R9" disarm
expect_eq "a second disarm is a no-op success (exit 0)" "0" "$RC"
expect_contains "…and says the Patrol was already disarmed" "already disarmed" "$OUT"

OUT="$( cd "$R9" && env -u CLAUDE_CODE_SESSION_ID bash "$POKER" disarm 2>&1 )"; RC=$?
expect_eq "disarm without a session key refuses (exit 3) — a stamp answers for ONE session" \
  "3" "$RC"

# ONE SESSION'S STAMP, never the neighbour's: the same scoping `arm` and the revive hook
# both keep, and the reason a shared .bionic/tmp is safe for parallel sessions.
R9B="$(make_repo s9-neighbour)"
OTHER9="99999999-8888-7777-6666-555555555555"
poke "$R9B" arm
printf 'patrol-stamp/v1|at=%s|session=%s|verb=arm\n' "$(iso_ago 30)" "$OTHER9" \
  > "$(stamp_of "$R9B" "$OTHER9")"
poke "$R9B" disarm
expect_eq "disarm removes THIS session's stamp" "no" \
  "$([ -e "$(stamp_of "$R9B")" ] && echo yes || echo no)"
expect_eq "…and leaves another session's stamp exactly where it was" "yes" \
  "$([ -f "$(stamp_of "$R9B" "$OTHER9")" ] && echo yes || echo no)"

# A verb nobody can find is a verb nobody types, and the run-close ritual is a model
# reading this usage.
poke "$R9" nonsense-verb
expect_contains "the usage surface names the disarm verb" "session-poker.sh disarm" "$OUT"

# ---------- the DISARM decision removes the stamp as its LAST act ----------
#
# This is the producer the plan missed: DISARM is not a run-close ceremony, it is the
# decision every quiet stretch reaches. The decision line still prints — the removal is
# after it, so nothing above can be skipped by it.
R9C="$(make_repo s9-tick-disarm)"; new_roster "$R9C"; armed_ago "$R9C"; delivered_plan "$R9C"
poke "$R9C" tick
expect_contains "an empty roster still decides DISARM" "decision=DISARM" "$OUT"
expect_eq "…and that tick removed the stamp it wrote: the decision and the disk agree" "no" \
  "$([ -e "$(stamp_of "$R9C")" ] && echo yes || echo no)"

# THE PAIRED POSITIVE. The removal is bound to the DISARM decision, not to ticking at all:
# a tick that finds open work must leave the stamp exactly where a live Patrol needs it,
# or every tick would disarm the wall it exists to keep honest.
R9D="$(make_repo s9-tick-quiet)"; new_roster "$R9D"
add_row "$R9D" name=fresh-unmet deliverable="$R9D/absent-fresh.md" \
  duration="4 hours" launched_at="$(iso_ago 60)"
poke "$R9D" arm
poke "$R9D" tick
expect_contains "a roster with open work decides QUIET" "decision=QUIET" "$OUT"
expect_eq "…and that tick KEEPS the stamp" "yes" \
  "$([ -f "$(stamp_of "$R9D")" ] && echo yes || echo no)"

# ---------- the blind-wall precedence, retired with the detector ----------
#
# A `wall-blind` NOTIFY used to outrank the DISARM decision and keep the stamp: an empty
# roster was exactly what a session whose dispatch wall had died looked like, so stopping
# the clock on that tick would have taken the monitor down with the thing it monitors.
# The wall cannot die that way any more — every hook is registered in hooks/hooks.json and
# survives a continue, a `/clear` + resume and a `/reload-plugins` — so the detector, the
# precedence and this fixture go together. What replaces the guarantee is the registration
# pin itself (tests/hook-adoption.test.sh, cross-gate §L).

# ---------- disarm follows the PINNED root, exactly as arm does ----------
# The mirror of Section 6's worktree case: a disarm that removed a stamp under the worktree
# root would leave the main repository's stamp — the one every reader looks at — untouched,
# and the death notice would keep firing for the rest of the session.
R9F="$(make_repo s9-worktree)"
( cd "$R9F" && git add -A 2>/dev/null; git -c user.email=t@e -c user.name=T commit -qm seed --allow-empty ) >/dev/null 2>&1
R9FWT="$TMPROOT/s9-worktree-wt"
( cd "$R9F" && git worktree add -q -b s9-wt "$R9FWT" ) >/dev/null 2>&1
if [ -d "$R9FWT" ]; then
  poke "$R9F" arm
  poke "$R9FWT" disarm
  expect_eq "disarming from a worktree cwd removes the MAIN repository's stamp" "no" \
    "$([ -e "$(stamp_of "$R9F")" ] && echo yes || echo no)"
  ( cd "$R9F" && git worktree remove --force "$R9FWT" ) >/dev/null 2>&1
else
  ok "disarming from a worktree cwd removes the MAIN repository's stamp (skipped: no worktree)"
fi

# ============================================================
section "Section 10: the run-state read — DISARM belongs to a delivered run (B-4, AC-13/AC-14)"
# ============================================================
#
# THE DEFECT, from this repo's own dogfood (idea file §B-4). A wave landed every writer of
# one task, the roster went quiet for the minutes it took to brief the next, and the tick
# that fired in that gap DISARMed — terminally, by doctrine — leaving the rest of the wave
# unsupervised. `open == 0` answered "finished" for a state that was a lull.
#
# THE CURE: `open == 0` is necessary and no longer sufficient. The run itself has to say it
# is delivered, in the one place a canonical-sdlc run says so — `current: 9` plus
# `delivered:` on the `Step 9:` line of the newest plan carrying an unfenced `## SDLC
# State`. Everything else, INCLUDING the absence of any plan at all, is `open`, and `open`
# QUIETs with the stamp kept.
#
# The stamp is the discriminating half of every case here. QUIET vs DISARM is one word in a
# decision line; kept-vs-removed stamp is what the arming wall and hooks/patrol-revive.sh
# actually read, so a fix that printed QUIET and removed the stamp anyway would be no fix.

# --- AC-13a: empty roster, plan mid-run at current: 7 -> QUIET, stamp KEPT ---
R10A="$(make_repo s10-current-7)"; new_roster "$R10A"
write_plan "$R10A" "$(plan_body 7 'record/fixture/verify.md')"
poke "$R10A" arm
poke "$R10A" tick
expect_eq "AC-13: an empty roster mid-run ticks cleanly (exit 0)" "0" "$RC"
expect_contains "AC-13: …and decides QUIET, not DISARM — the run is at current: 7" \
  "decision=QUIET" "$OUT"
expect_absent "AC-13: …never DISARM on a roster that is merely between batches" \
  "decision=DISARM" "$OUT"
expect_eq "AC-13: …and the tick KEEPS its stamp, so the Patrol keeps firing" "yes" \
  "$([ -f "$(stamp_of "$R10A")" ] && echo yes || echo no)"
expect_contains "AC-13: …and the line says WHICH plan and WHERE the run is" "current: 7" "$OUT"

# --- AC-13b: empty roster, no readable plan at all -> QUIET, stamp KEPT ---
# The fail direction, stated as its own case: a run whose plan the tick cannot find is not
# a finished run. This is the one that governs an unfamiliar project, a docs-root override
# pointing somewhere else, and a plan that has not been written yet.
R10B="$(make_repo s10-no-plan)"; new_roster "$R10B"
poke "$R10B" arm
poke "$R10B" tick
expect_eq "AC-13: an empty roster with NO plan ticks cleanly (exit 0)" "0" "$RC"
expect_contains "AC-13: …and decides QUIET — no plan is not a delivered run" \
  "decision=QUIET" "$OUT"
expect_absent "AC-13: …never DISARM with nothing read to decide it from" "decision=DISARM" "$OUT"
expect_eq "AC-13: …and KEEPS the stamp" "yes" \
  "$([ -f "$(stamp_of "$R10B")" ] && echo yes || echo no)"

# --- AC-14: empty roster, plan at current: 9 with delivered: -> DISARM, stamp REMOVED ---
R10C="$(make_repo s10-delivered)"; new_roster "$R10C"
armed_ago "$R10C"
write_plan "$R10C" "$(plan_body 9 'delivered: bionic 9.9.9; report: record/fixture/close-out.md')"
poke "$R10C" tick
expect_eq "AC-14: a delivered run over an empty roster ticks cleanly (exit 0)" "0" "$RC"
expect_contains "AC-14: …and decides DISARM — the run said it is delivered" \
  "decision=DISARM" "$OUT"
expect_eq "AC-14: …and the DISARM removes the stamp, as it always did" "no" \
  "$([ -e "$(stamp_of "$R10C")" ] && echo yes || echo no)"

# --- THE DISCRIMINATOR for AC-14: current: 9, no `delivered:` -> QUIET, stamp KEPT ---
# AC-14 alone is satisfied by the OLD predicate too (an empty roster DISARMed whatever the
# plan said), so it proves nothing on its own. This case is the half that only the new
# predicate can pass: same roster, same `current: 9`, one token missing. Step 9 is reached
# well before the close-out is written, and a Patrol that dies at the top of Step 9 dies
# during the last stretch of work it exists to watch.
R10D="$(make_repo s10-step9-undelivered)"; new_roster "$R10D"
write_plan "$R10D" "$(plan_body 9 'close-out drafting, report not written yet')"
poke "$R10D" arm
poke "$R10D" tick
expect_contains "AC-14 discriminator: current: 9 with no delivered: decides QUIET" \
  "decision=QUIET" "$OUT"
expect_absent "AC-14 discriminator: …never DISARM before the delivery is recorded" \
  "decision=DISARM" "$OUT"
expect_eq "AC-14 discriminator: …and KEEPS the stamp" "yes" \
  "$([ -f "$(stamp_of "$R10D")" ] && echo yes || echo no)"

# --- an incident run answers too: <docs-root>/incidents/ is the second plan directory ---
R10E="$(make_repo s10-incident)"; new_roster "$R10E"
armed_ago "$R10E"
mkdir -p "$R10E/.bionic/docs/incidents"
printf '%s' "$(plan_body 9 'delivered: incident closed; report: record/fixture/x.md')" \
  > "$R10E/.bionic/docs/incidents/inc-01.md"
poke "$R10E" tick
expect_contains "a delivered INCIDENT plan DISARMs too — both plan directories are read" \
  "decision=DISARM" "$OUT"

# --- depth is bounded at 2, exactly as the gate bounds it ---
# A plan three levels down is not a candidate. The pairing matters: the SAME content at
# depth 2 DISARMs, so this case pins the bound rather than a broken fixture.
R10F="$(make_repo s10-too-deep)"; new_roster "$R10F"
write_plan "$R10F" "$(plan_body 9 'delivered: too deep to be seen')" \
  "epic-99/wave-01/nested/plan.md"
armed_ago "$R10F"
poke "$R10F" tick
expect_contains "a plan at depth 3 is not a candidate, so the tick QUIETs" "decision=QUIET" "$OUT"
write_plan "$R10F" "$(plan_body 9 'delivered: at depth two')" "epic-99/wave-01.plan.md"
poke "$R10F" tick
expect_contains "…and the SAME content at depth 2 DISARMs (the bound is pinned, not the fixture)" \
  "decision=DISARM" "$OUT"

# --- the newest-race filter: a newer marker-less .md never wins the selection ---
# The 2026-08-15 incident in one fixture. An unfiltered "newest *.md" read would take
# `scratch.md`, parse no `current:`, and answer `open` — which happens to be safe here — so
# the discriminating direction is the other one: the marker-less file is NEWER than a
# DELIVERED plan, and a filtered read still finds the plan and still DISARMs.
R10G="$(make_repo s10-newest-race)"; new_roster "$R10G"
write_plan "$R10G" "$(plan_body 9 'delivered: the real plan')"
printf 'a scratch note with no SDLC State heading at all\n' \
  > "$R10G/.bionic/docs/plans/epic-99-fixture/zz-scratch.md"
# The plan is backdated rather than the scrap re-touched: a same-second tie reads as "not
# newer" to `-nt`, which would pass this case without the filter ever being exercised.
backdate "$R10G/.bionic/docs/plans/epic-99-fixture/wave-01-fixture.plan.md" 3600
armed_ago "$R10G" 7200
poke "$R10G" tick
expect_contains "a NEWER marker-less .md does not shadow the delivered plan" \
  "decision=DISARM" "$OUT"

# --- a fenced `## SDLC State` is documentation, not a run ---
R10H="$(make_repo s10-fenced)"; new_roster "$R10H"
mkdir -p "$R10H/.bionic/docs/plans/epic-99-fixture"
{
  printf '# a document ABOUT plans\n\n'
  printf '```\n## SDLC State\ncurrent: 9\n- Step 9: delivered: not a real run\n```\n'
} > "$R10H/.bionic/docs/plans/epic-99-fixture/schema-notes.md"
poke "$R10H" arm
poke "$R10H" tick
expect_contains "a plan-shaped FENCED example is not a run, so the tick QUIETs" \
  "decision=QUIET" "$OUT"
expect_eq "…and KEEPS the stamp" "yes" \
  "$([ -f "$(stamp_of "$R10H")" ] && echo yes || echo no)"

# --- the predicate is a CONJUNCTION: a delivered plan never overrides an open row ---
# Without this, "run_state == delivered" could have been written as the whole predicate and
# every case above would still pass. A plan is a claim about the run; the roster is the fact
# about the work, and an open row outranks the claim.
R10I="$(make_repo s10-delivered-but-open)"; new_roster "$R10I"
delivered_plan "$R10I"
add_row "$R10I" name=still-running deliverable="$R10I/absent.md" \
  duration="4 hours" launched_at="$(iso_ago 60)"
armed_ago "$R10I"
poke "$R10I" tick
expect_contains "a DELIVERED plan with an open row still decides QUIET" "decision=QUIET" "$OUT"
expect_absent "…never DISARM while the roster carries open work" "decision=DISARM" "$OUT"
expect_eq "…and KEEPS the stamp" "yes" \
  "$([ -f "$(stamp_of "$R10I")" ] && echo yes || echo no)"

# --- the absent-roster REFUSAL is untouched by any of this ---
# The never-ran case keeps its own answer (Section 5): an absent roster is not an empty one,
# it is usually the wrong project root, and it refuses rather than deciding. Re-pinned here
# because the DISARM predicate moved past it and a future edit could route it into QUIET.
R10J="$(make_repo s10-no-roster)"
delivered_plan "$R10J"
poke "$R10J" tick
expect_eq "an absent roster still REFUSES (exit 2), delivered plan or not" "2" "$RC"
expect_absent "…and decides nothing" "decision=" "$OUT"

# --- AC-14 (R-13, critic C-4): a delivery that PREDATES this Patrol's arming is the
#     PREVIOUS run's, and never DISARMs the one that just armed ---
#
# THE WINDOW THIS CLOSES. A session finishes run W — its plan records `delivered:` — and
# then starts W+1. Arming happens at Step 0 (SKILL.md §Dispatch: "at engagement"), but
# W+1's plan, and its `## SDLC State`, does not exist until Step 1-3. In that gap the
# newest SDLC-State plan is still W's, its Step-9 line still says `delivered:`, and the
# roster is empty because nothing has been dispatched yet — so the tick took DISARM,
# removed the stamp, and hooks/dispatch-preflight.sh refused W+1's very first dispatch on
# the arming wall (critic C-4, wave-1.3.2 Step 6).
#
# The arming instant is FIXTURE DATA here, set by backdating the plan — never by sleeping,
# and never left to a same-second tie (tests/cross-gate-agreement.test.sh §S.3's rule).
R10K="$(make_repo s10-delivered-before-arm)"; new_roster "$R10K"
delivered_plan "$R10K"
backdate "$R10K/.bionic/docs/plans/epic-99-fixture/wave-01-fixture.plan.md" 3600
poke "$R10K" arm
poke "$R10K" tick
expect_eq "AC-14: a delivery older than the arming instant ticks quietly (exit 0)" "0" "$RC"
expect_contains "AC-14: …and decides QUIET — that delivery belongs to the previous run" \
  "decision=QUIET" "$OUT"
expect_absent "AC-14: …never DISARM at the START of the next run" "decision=DISARM" "$OUT"
expect_contains "AC-14: …and says so in words the reader can act on" \
  "before this Patrol armed" "$OUT"
expect_eq "AC-14: …and the stamp STAYS, so the first dispatch of the new run is not refused" "yes" \
  "$([ -f "$(stamp_of "$R10K")" ] && echo yes || echo no)"

# --- no arming record at all -> open, exactly as every other doubt does (ADR-002 §3) ---
# A tick in a session that never armed has nothing to date the delivery against. The fail
# direction is the ADR's, without exception: a wrong `open` costs a Patrol that keeps
# ticking over a finished run, which one `disarm` ends; a wrong `delivered` ends the
# supervision of a live run, terminally, and nothing recovers it.
R10L="$(make_repo s10-never-armed)"; new_roster "$R10L"
delivered_plan "$R10L"
poke "$R10L" tick
expect_eq "a tick with no arming record ticks quietly (exit 0)" "0" "$RC"
expect_contains "…and decides QUIET — there is nothing to date the delivery against" \
  "decision=QUIET" "$OUT"
expect_absent "…never DISARM off a delivery it cannot place in time" "decision=DISARM" "$OUT"
expect_contains "…naming the missing arming record as the reason" "arming record" "$OUT"

# ============================================================
section "Section 11: pressure — HOLD, EMERGENCY, and the RUNG (AC-17, AC-30, S8)"
# ============================================================
#
# WHAT THESE CASES OWN. The tick reads `resources_pressure` before it considers a single
# fill, because filling a machine that is already starving is the one scheduling mistake
# that costs WORK rather than time: the measured failure is a kernel SIGKILL, seven
# concurrent suites on an 8 GB machine driving free memory to ~188 MB and a suite dying
# mid-run (tests/run.sh:65-70).
#
# CLOCK AND MACHINE DISCIPLINE, the same house rule the rest of this suite keeps: nothing
# here waits for the machine to get into trouble, and nothing reads this machine at all.
# `resources_pressure` takes both of its readings through `BIONIC_PROBE_FREE_MB` /
# `BIONIC_PROBE_LOAD_1M` (lib/resources.sh's own seams, exercised the same way by
# tests/resources.test.sh), so every threshold below is fixture DATA.

# A plan carrying BOTH halves the scheduler reads: the frontmatter `parallel-budget:` line
# and the machine-readable task table. Written as one builder because a fixture that
# carried only one of them would be testing a plan shape the wave never produces.
#
# The budget line's shape is byte-identical to what Step 0 writes and to what
# hooks/dispatch-preflight.sh's budget arm reads (L-RESOURCES/2): one string, four fields.
wave_plan() {  # <repo> <budget line body, or "-" for none> <table row>...
  local repo="$1"; shift
  wave_plan_at "$repo" 'epic-99-fixture/wave-01-fixture.plan.md' "$@" >/dev/null
}

# THE SAME PLAN, AT A PATH THE CALLER NAMES, and echoing that path back. Section 18 needs
# TWO budgeted plans in one root — one bound, one not — which a fixed filename cannot
# describe. `wave_plan` is now a two-line delegate to this, so every Section 11/12 case
# still writes exactly the file it always wrote.
# THE ONE `## Tasks` HEADER EVERY FIXTURE PLAN IN THIS SUITE CARRIES (REQ-1e). The tick
# reads the table through payload/scripts/lib/units.sh now, which keys every column off
# this header row by NAME — so a fixture that named fewer columns would be testing a
# schema no plan ships. The `step` cell is the one that matters to FILL: `units_ready`
# answers for ONE step, and these fixtures sit at `current: 4`.
SP_TASKS_HEADER='| id | step | kind | task | agent | deps | size | serves | Files | status |
|---|---|---|---|---|---|---|---|---|---|
'
# THE APPROVAL A LIVE FIXTURE CARRIES (wave-26 T13; D3, AC-6.2). The ready set keys on the plan's
# `approved-by:` line, not on `current: >= 4`, so a fixture that means "past Step 3" writes it.
SP_APPROVED_LINE='approved-by: fixture 2026-10-04T00:00Z "approved"'

wave_plan_at() {  # <repo> <path under <docs-root>/plans> <budget or "-"> <table row>... -> the path
  local repo="$1" rel="$2" budget="$3"; shift 3
  local f="$repo/.bionic/docs/plans/$rel"
  mkdir -p "$(dirname "$f")"
  {
    printf -- '---\n'
    printf 'governing-skill: superpowers:writing-plans\n'
    [ "$budget" = "-" ] || printf 'parallel-budget: %s\n' "$budget"
    printf -- '---\n\n'
    printf '# fixture plan\n\n## SDLC State\n\ncurrent: 4\n%s\n\n- Step 4: in progress\n\n' "$SP_APPROVED_LINE"
    printf '## Tasks\n\n'
    printf '%s' "$SP_TASKS_HEADER"
    local row
    for row in "$@"; do printf '%s\n' "$row"; done
  } > "$f"
  touch "$f"
  printf '%s' "$f"
}

# The poker under an injected pressure reading. The two knobs are exported for exactly one
# invocation and unset afterwards, so no case can leak a reading into the next.
# ---------- the live answer, planted where `session_transcript` looks for it ----------
#
# Any project directory of CLAUDE_CONFIG_DIR, file `<session-id>.jsonl`. Section 19 owns the
# NARRATIVE (it is the section that made the tick read one) and used to own the code too;
# Section 12's stand-down cases need the same primitive, and a second copy of it there would
# be two ideas of what a ListAgents answer looks like. The BODY is always composed by
# tests/lib/live-answer.sh out of the committed corpus, never hand-typed, so separators and
# ref suffixes are the harness's rather than this suite's guess about them.
plant_answer() {  # <transcript file> <state: fresh|stale|none> <name[:status]>...
  local tr="$1" state="$2"; shift 2
  local body
  mkdir -p "$(dirname "$tr")"
  if [ "$state" = "none" ]; then
    printf '{"type":"user","timestamp":"2026-09-05T00:50:00.000Z","message":{"role":"user","content":"go"}}\n' \
      > "$tr"
    return 0
  fi
  body="$(live_answer_body "$@")"
  {
    jq -nc --arg ts "2026-09-05T00:50:00.000Z" \
      '{type:"user",timestamp:$ts,message:{role:"user",content:"go"}}'
    jq -nc --arg ts "2026-09-05T00:51:00.000Z" \
      '{type:"assistant",timestamp:$ts,message:{role:"assistant",content:[{type:"tool_use",id:"toolu_01S19LISTAGENTS",name:"ListAgents",input:{}}]}}'
    jq -nc --arg ts "2026-09-05T00:52:23.349Z" --arg b "$body" \
      '{type:"user",timestamp:$ts,message:{role:"user",content:[{type:"tool_result",tool_use_id:"toolu_01S19LISTAGENTS",content:$b}]}}'
    [ "$state" = "stale" ] && jq -nc --arg ts "2026-09-05T00:55:00.000Z" \
      '{type:"user",timestamp:$ts,message:{role:"user",content:"anything else?"}}'
  } > "$tr"
  return 0
}

poke_pressure() {  # <repo> <free_mb> <load_1m> <args...>
  local repo="$1" free="$2" load="$3"; shift 3
  BIONIC_PROBE_FREE_MB="$free" BIONIC_PROBE_LOAD_1M="$load" poke "$repo" "$@"
}

# THE SAME, FOR THE BAND THE RUNG IS COMPUTED FROM (S8). `free_mb`/`load_1m` decide the
# advisory `state=` arm (HOLD/EMERGENCY); the BAND behind `pressure_level` is decided by the
# free and swap PERCENTAGES, which are a different pair of readings on the same record
# (lib/resources.sh `pressure_band`). Both seams are pinned, so a case can put the machine in
# one state and the ring in another band — which is exactly the separation the design asks
# for: HOLD is advice to the model, the rung is regulation.
#
# A RING PER CASE, always empty at entry. `pressure_level` medians every sample inside the
# smoothing window, so a ring shared between cases would let an earlier case's band decide a
# later case's fill width. The tick takes its own sample, so an empty ring plus these two
# pins is a ring holding exactly one reading of the band the case named.
RUNG_N=0
poke_rung() {  # <repo> <free_pct> <swap_pct> <args...>
  local repo="$1" fp="$2" sp="$3"; shift 3
  RUNG_N=$((RUNG_N + 1))
  local ring="$TMPROOT/ring-$RUNG_N.ring"
  rm -f "$ring"
  BIONIC_PRESSURE_RING="$ring" BIONIC_PROBE_FREE_PCT="$fp" BIONIC_PROBE_SWAP_PCT="$sp" \
    poke "$repo" "$@"
}

# A READING ALREADY IN THE RING, taken through the REAL writer. `pressure_sample` is the one
# writer of that file (S7), so seeding by hand would pin this suite to a private idea of the
# ring's line shape rather than to the one the library actually keeps — and the case below
# turns on the SAMPLE COUNT, which is exactly what a hand-written line would fake.
RESOURCES_LIB="$(cd "${BIONIC_HOOKS_DIR}/../payload/scripts/lib" && pwd -P)/resources.sh"
seed_ring() {  # <ring> <free_pct> <swap_pct>
  BIONIC_PRESSURE_RING="$1" BIONIC_PROBE_FREE_PCT="$2" BIONIC_PROBE_SWAP_PCT="$3" \
  BIONIC_PROBE_LOAD_1M=1.0 \
    bash -c '. "$1"; pressure_sample 8' _ "$RESOURCES_LIB" >/dev/null 2>&1
}

# How many times a line appears in an output — "exactly one rung line per tick" is a claim
# about a COUNT, and `expect_contains` cannot make it.
count_lines_matching() {  # <needle> <output> -> integer
  local n
  n="$(printf '%s\n' "$2" | /usr/bin/grep -c -- "$1" 2>/dev/null)" || n=0
  case "${n:-}" in ''|*[!0-9]*) n=0 ;; esac
  printf '%s' "$n"
}

# ---------- 11a: a HOLD prints its measurement and fills nothing ----------
#
# The fixture has ready work AND a gap, so a tick that filled would fill. That is the whole
# discriminator: "no FILL under pressure" is only a claim if a FILL was available.
R11A="$(make_repo s11-hold)"; new_roster "$R11A"
wave_plan "$R11A" "writers=4 suites=2 worktrees=8 test_jobs=8 source=probe" \
  "| DONE | 4 | build | fixture task | implementor | — | 15m | REQ-x | a.sh | landed |" \
  "| NEXT | 4 | build | fixture task | implementor | DONE | 15m | REQ-x | a.sh | pending |"
poke_pressure "$R11A" 512 1.0 tick
expect_eq "a tick under memory pressure still exits 0 — HOLD is a decision, not a failure" \
  "0" "$RC"
expect_contains "…and prints HOLD with the free-memory reading" "poker: HOLD free_mb=512" "$OUT"
expect_contains "…and the load reading beside it" "load_1m=1.0" "$OUT"
expect_contains "…saying plainly that nothing is being filled" "no fills" "$OUT"
expect_absent "…and fills nothing, though a ready task and a gap both exist" "poker: FILL" "$OUT"
# THE WITHHELD LINE (wave-19 REQ-4 AC-4.1, D6). The stop wall exempts a tick turn from the
# fill invariant only on this line, so the HOLD path prints it beside its measurement.
expect_contains "11a2 …and prints the withheld line the stop wall reads, with the measurement" \
  "poker: fill withheld — HOLD free_mb=512 load_1m=1.0" "$OUT"

# The paired positive: the SAME repo, the SAME plan, with the machine reading healthy.
# Without it, 11a passes on a tick that can never fill anything.
poke_pressure "$R11A" 8192 1.0 tick
expect_contains "the same fixture with memory to spare DOES fill (11a discriminates)" \
  "poker: FILL NEXT" "$OUT"
expect_absent "…and prints no HOLD" "poker: HOLD" "$OUT"
expect_absent "11a3 …and withholds nothing" "fill withheld" "$OUT"

# ---------- 11b: ONE rung line per tick, on QUIET and on FILL alike (AC-17) ----------
#
# WHAT REPLACED NARROW. NARROW was advice computed from a COUNT the tick carried across
# firings in a sibling file — a stored fact about the machine, owned by a hook that only
# wakes every twenty minutes. The rung is the same judgment taken as a pure function of the
# ring at the moment of use, so it needs no counter, no sibling file and no second firing;
# what the tick owes the operator is therefore a REPORT, not a recommendation, and it owes
# it on every tick rather than on the second consecutive hold.
#
# THE LINE IS THE CONTRACT, and it is one line: `rung=<n>/<ceiling>` is the fill width and
# the ceiling it was taken against, `writers=` and `test_jobs=` are that same band applied to
# the two numbers the plan header carries (D3: "one fraction applied to both").
R11B="$(make_repo s11-rung-quiet)"; new_roster "$R11B"
wave_plan "$R11B" "writers=8 suites=2 worktrees=8 test_jobs=18 source=probe" \
  "| A | 4 | build | fixture task | implementor | — | 15m | REQ-x | a.sh | landed |"
# One open row, well inside its declared duration: the decision is QUIET and there is no
# pending task to fill, so this tick prints no FILL at all.
add_row "$R11B" name=live-writer deliverable=a.md duration="4 hours" launched_at="$(iso_ago 60)"
poke_rung "$R11B" 60 0 tick
expect_eq "a QUIET tick exits 0" "0" "$RC"
expect_contains "…decides QUIET" "decision=QUIET" "$OUT"
expect_absent   "…fills nothing" "poker: FILL" "$OUT"
expect_contains "…and STILL prints the rung, on a clear ring at the full ceiling" \
  "poker: rung=8/8 writers=8 test_jobs=18" "$OUT"
expect_eq       "…exactly once, not once per arm" "1" "$(count_lines_matching 'poker: rung=' "$OUT")"

# THE PAIRED POSITIVE: the same shape on a tick that FILLS. Without it, "on every tick" is a
# claim proven on one kind of tick.
R11B2="$(make_repo s11-rung-fill)"; new_roster "$R11B2"
wave_plan "$R11B2" "writers=8 suites=2 worktrees=8 test_jobs=18 source=probe" \
  "| A | 4 | build | fixture task | implementor | — | 15m | REQ-x | a.sh | landed |" \
  "| NEXT | 4 | build | fixture task | implementor | A | 15m | REQ-x | a.sh | pending |"
PLAN_R11B2="$R11B2/.bionic/docs/plans/epic-99-fixture/wave-01-fixture.plan.md"
poke_rung "$R11B2" 60 0 tick
expect_contains "a FILLING tick prints the rung too" \
  "poker: rung=8/8 writers=8 test_jobs=18" "$OUT"
expect_contains "…beside the fill it decided" "poker: FILL NEXT" "$OUT"
expect_eq       "…still exactly one rung line" "1" "$(count_lines_matching 'poker: rung=' "$OUT")"

# AND UNDER A HOLD, where no fill happens at all: the report is unconditional, so an operator
# reading a held tick still learns what width the machine would allow if it were not held.
BIONIC_PROBE_FREE_MB=512 poke_rung "$R11B2" 60 0 tick
expect_contains "a HELD tick prints the rung as well" "poker: rung=8/8" "$OUT"
expect_contains "…alongside the HOLD" "poker: HOLD" "$OUT"

# ---------- 11b2: the two exit paths ABOVE the report (Step-6 review C-5) ----------
#
# AC-17 reads "on every tick", and two arms exit before the scheduler block ever runs: the
# pre-dispatch QUIET of §13a — no roster file at all, which is the FIRST tick of every run
# by design, because arming precedes dispatch — and the terminal DISARM of §9c/§12j. The
# §11b fixture above calls `new_roster`, so it exercises the roster-present arm that already
# printed; these two are the ones that did not, and the first of them is the tick an
# operator sees most: the one taken right before the first dispatch, where "what width will
# this machine carry" is the whole question.
R11B4="$(make_repo s11-rung-no-roster)"
# Deliberately NO new_roster — §13a's pre-dispatch state — but WITH a budget to report.
poke "$R11B4" arm
wave_plan "$R11B4" "writers=8 suites=2 worktrees=8 test_jobs=18 source=probe" \
  "| A | 4 | build | fixture task | implementor | — | 15m | REQ-x | a.sh | landed |"
poke_rung "$R11B4" 60 0 tick
expect_eq "the pre-dispatch (no-roster) QUIET tick exits 0" "0" "$RC"
expect_contains "…decides QUIET" "decision=QUIET" "$OUT"
expect_contains "…and says the pre-dispatch line" "armed, nothing dispatched yet" "$OUT"
expect_contains "…and STILL prints the rung — this is the first tick of every run" \
  "poker: rung=8/8 writers=8 test_jobs=18" "$OUT"
expect_eq "…exactly once, not once per arm" "1" "$(count_lines_matching 'poker: rung=' "$OUT")"

# THE DISARM ARM. `delivered_plan` carries no `parallel-budget:` frontmatter, so this row
# also pins the missing-ceiling spelling the report's own comment promises: the line is
# PRINTED with `-` rather than withheld, because "the tick said nothing" and "the tick said
# there is no ceiling" are different facts and only the second one is true.
R11B5="$(make_repo s11-rung-disarm)"; new_roster "$R11B5"; armed_ago "$R11B5"
delivered_plan "$R11B5"
poke_rung "$R11B5" 60 0 tick
expect_eq "a DISARM tick exits 0" "0" "$RC"
expect_contains "…decides DISARM" "decision=DISARM" "$OUT"
expect_contains "…and STILL prints the rung, with the missing ceiling spelled out" \
  "poker: rung=-/- writers=- test_jobs=-" "$OUT"
expect_eq "…exactly once" "1" "$(count_lines_matching 'poker: rung=' "$OUT")"

# THE PAIRED POSITIVE FOR THAT ARM: the same terminal decision over a plan that DOES carry a
# budget, so the `-` above is proven to be the absent CEILING and not an absent report.
R11B6="$(make_repo s11-rung-disarm-budget)"; new_roster "$R11B6"; armed_ago "$R11B6"
write_plan "$R11B6" "$(printf -- '---\nparallel-budget: writers=8 suites=2 worktrees=8 test_jobs=18 source=probe\n---\n\n# fixture plan\n\n## SDLC State\n\nintegration-branch: main\ncurrent: 9\n\n- Step 9: delivered: bionic 9.9.9; report: record/fixture/close-out.md\n')"
poke_rung "$R11B6" 60 0 tick
expect_contains "a DISARM tick over a BUDGETED plan prints the real rung (11b5 discriminates)" \
  "poker: rung=8/8 writers=8 test_jobs=18" "$OUT"
expect_contains "…and still DISARMs" "decision=DISARM" "$OUT"

# ---------- 11b3: the tick never edits the plan (AC-17's third clause) ----------
#
# THE CLAUSE THE READBACK NAMED AS UNPINNED. The rung line and the FILL line are both console
# output; neither is a claim about the file on disk. A tick that decided to fill by rewriting
# the plan's own header — instead of only PRINTING what it decided — would still pass every
# case above. The plan is the one artifact every other reader (active_plan, open_runs, the
# bound marker) trusts to describe what a run intends, so a tick that edited it would be a
# second writer of state the rest of the wave assumes only Step 4 authorship touches.
#
# A REAL TICK THAT BOTH PRINTS THE RUNG AND FILLS — reusing R11B2's already-filling fixture —
# so the claim is proven on the same kind of tick that has something to write, not on an idle
# one that never reaches the fill path at all.
CKSUM_11B3_BEFORE="$(cksum < "$PLAN_R11B2")"
MTIME_11B3_BEFORE="$(stat -f %m "$PLAN_R11B2" 2>/dev/null || stat -c %Y "$PLAN_R11B2")"
poke_rung "$R11B2" 60 0 tick
expect_contains "the same FILLING tick, run again, still prints the rung" \
  "poker: rung=8/8 writers=8 test_jobs=18" "$OUT"
expect_eq "…and the plan's bytes are byte-identical after the tick" "$CKSUM_11B3_BEFORE" \
  "$(cksum < "$PLAN_R11B2")"
expect_eq "…and the plan's mtime is untouched by the tick" "$MTIME_11B3_BEFORE" \
  "$(stat -f %m "$PLAN_R11B2" 2>/dev/null || stat -c %Y "$PLAN_R11B2")"

# THE ANTI-VACUITY ARM. A doctored copy of the poker appends one byte to the plan right where
# the real tick only READS it (`SCHED_PLAN="$POKER_RUN_PLAN"`, now inside `sched_budget_read`
# and so indented two rather than four — the anchor follows the code, C-5), so the pin above
# is proven to discriminate a tick that DOES edit the plan from one that does not.
POKER_MUT_PLANEDIT_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/poker-planedit-mut.XXXXXX")"
mkdir -p "$POKER_MUT_PLANEDIT_ROOT/hooks" "$POKER_MUT_PLANEDIT_ROOT/scripts"
ln -s "$(cd "$(dirname "$POKER")/../payload/scripts/lib" && pwd -P)" \
  "$POKER_MUT_PLANEDIT_ROOT/scripts/lib"
# EVERY OTHER SIBLING HOOK, LINKED IN — `tick` refuses outright with no sibling
# hooks/session-sweeper.sh on disk, which a hooks/-plus-scripts/lib copy (the shape the
# 20m-default mutant above uses) does not provide because that mutant never runs `tick`.
for _sib in "$(dirname "$POKER")"/*; do
  _sibname="$(basename "$_sib")"
  [ "$_sibname" = "session-poker.sh" ] && continue
  ln -s "$_sib" "$POKER_MUT_PLANEDIT_ROOT/hooks/$_sibname"
done
POKER_MUT_PLANEDIT="$POKER_MUT_PLANEDIT_ROOT/hooks/session-poker.sh"
sed 's/^  SCHED_PLAN="\$POKER_RUN_PLAN"$/  SCHED_PLAN="$POKER_RUN_PLAN"; [ -n "$SCHED_PLAN" ] \&\& printf x >> "$SCHED_PLAN"/' \
  "$POKER" > "$POKER_MUT_PLANEDIT"
expect_eq "planedit meta: the sed anchor landed exactly once (the doctor took)" "1" \
  "$(diff "$POKER" "$POKER_MUT_PLANEDIT" | /usr/bin/grep -c '^>')"
CKSUM_11B3_MUT_BEFORE="$(cksum < "$PLAN_R11B2")"
POKER_REAL_11B3="$POKER"; POKER="$POKER_MUT_PLANEDIT"
forget_digest "$R11B2"
poke_rung "$R11B2" 60 0 tick
POKER="$POKER_REAL_11B3"
expect_contains "the doctored tick still fills (the mutation is only in the plan-touch path)" \
  "poker: FILL NEXT" "$OUT"
if [ "$CKSUM_11B3_MUT_BEFORE" = "$(cksum < "$PLAN_R11B2")" ]; then
  no "planedit: the doctored tick's plan edit did NOT change the plan's bytes (the arm proves nothing)"
else
  ok "planedit: the doctored tick DID change the plan's bytes — the byte-identity pin above discriminates"
fi
rm -rf "$POKER_MUT_PLANEDIT_ROOT"

# ---------- 11c: the rung IS the band, and the FILL is sized by it (AC-17, AC-14) ----------
#
# THE DISCRIMINATOR. Four ready tasks and a writers ceiling of eight means a clear machine
# fills all four; the same fixture on a critical ring must fill exactly the quarter-ceiling.
# A test that only ever ran clear would pass against a tick that ignored the ring entirely.
mk_rung_repo() {  # <label> -> a repo with writers=8 test_jobs=18 and four ready tasks
  local r; r="$(make_repo "$1")"; new_roster "$r"
  wave_plan "$r" "writers=8 suites=2 worktrees=8 test_jobs=18 source=probe" \
    "| BASE | 4 | build | fixture task | implementor | — | 15m | REQ-x | a.sh | landed |" \
    "| ONE | 4 | build | fixture task | implementor | BASE | 15m | REQ-x | a.sh | pending |" \
    "| TWO | 4 | build | fixture task | implementor | BASE | 15m | REQ-x | a.sh | pending |" \
    "| THREE | 4 | build | fixture task | implementor | BASE | 15m | REQ-x | a.sh | pending |" \
    "| FOUR | 4 | build | fixture task | implementor | BASE | 15m | REQ-x | a.sh | pending |"
  printf '%s' "$r"
}

R11C="$(mk_rung_repo s11-rung-clear)"
poke_rung "$R11C" 60 0 tick
expect_contains "a CLEAR ring reports the full ceiling" \
  "poker: rung=8/8 writers=8 test_jobs=18" "$OUT"
expect_contains "…and fills the whole gap" "poker: FILL ONE TWO THREE FOUR" "$OUT"

R11C2="$(mk_rung_repo s11-rung-warning)"
poke_rung "$R11C2" 20 0 tick
expect_contains "a WARNING ring halves both numbers" \
  "poker: rung=4/8 writers=4 test_jobs=9" "$OUT"
expect_contains "…and the fill is still under the halved rung" "poker: FILL ONE TWO THREE FOUR" "$OUT"

R11C3="$(mk_rung_repo s11-rung-critical)"
poke_rung "$R11C3" 8 0 tick
expect_contains "a CRITICAL ring quarters both numbers" \
  "poker: rung=2/8 writers=2 test_jobs=5" "$OUT"
expect_contains "…and the fill names ONLY the quarter-ceiling, in table order" \
  "poker: FILL ONE TWO" "$OUT"
expect_absent   "…never the third ready task" "THREE" "$(printf '%s\n' "$OUT" | /usr/bin/grep '^poker: FILL')"

# SWAP REACHES THE SAME BAND BY THE OTHER TERM, so the rung is not a free-percentage
# thermometer wearing a band's name.
R11C4="$(mk_rung_repo s11-rung-critical-swap)"
poke_rung "$R11C4" 60 95 tick
expect_contains "swap past the critical line quarters it too, on a healthy free percentage" \
  "poker: rung=2/8 writers=2 test_jobs=5" "$OUT"

# THE OPEN ROWS COME OFF THE RUNG, NOT OFF THE CEILING. This is the whole point of sizing
# the fill by the rung: two open rows against a quartered rung of 2 is a gap of ZERO, where
# against the ceiling of 8 it would still be a gap of six.
R11C5="$(mk_rung_repo s11-rung-critical-open)"
add_row "$R11C5" name=w1 deliverable=a.md duration="4 hours" launched_at="$(iso_ago 60)"
poke_rung "$R11C5" 8 0 tick
expect_contains "one open row against a rung of 2 leaves a gap of one" "poker: FILL ONE" "$OUT"
expect_absent   "…and the second ready task waits on the machine, not on the budget" "TWO" "$(printf '%s\n' "$OUT" | /usr/bin/grep '^poker: FILL')"
add_row "$R11C5" name=w2 deliverable=b.md duration="4 hours" launched_at="$(iso_ago 60)"
poke_rung "$R11C5" 8 0 tick
expect_absent   "two open rows against a rung of 2 fill nothing" "poker: FILL" "$OUT"
expect_contains "…and say which number closed the gap — the RUNG, named beside its ceiling" \
  "rung=2 of writers=8" "$OUT"

# ---------- 11c2: no plan budget, and the line still prints ----------
#
# The rung is a function of (ring, CEILING) and a plan that opts into no budget offers no
# ceiling. The honest report is the line with its fields empty rather than a number invented
# from somewhere else — and the line is still printed, because "the tick reported nothing"
# and "the tick reported no ceiling" are different facts.
R11C6="$(make_repo s11-rung-nobudget)"; new_roster "$R11C6"
wave_plan "$R11C6" "-" "| A | 4 | build | fixture task | implementor | — | 15m | REQ-x | a.sh | pending |"
poke_rung "$R11C6" 60 0 tick
expect_contains "a plan with no parallel-budget still prints the rung line" \
  "poker: rung=-/- writers=- test_jobs=-" "$OUT"
expect_contains "…and says why it is not filling, naming the key (wave-19 REQ-3 AC-3.2)" \
  "carries no parallel-budget: writers=" "$OUT"

# ---------- 11c3: NARROW and its counter file are GONE (AC-17) ----------
#
# TWO ASSERTIONS, BECAUSE THEY FAIL DIFFERENTLY. The first is about the script: a NARROW that
# survived anywhere in it — in a comment, in a dead branch — is a second answer to "how wide
# should this wave run" living beside the rung. The second is about the DISK: `.holds` was
# the only cross-tick state the scheduler kept, and a tick that still wrote it would be
# storing a liveness fact it no longer owns (D0). Three consecutive holds is what used to
# make the counter reach 2 and fire.
R11C7="$(mk_rung_repo s11-no-holds)"
BIONIC_PROBE_FREE_MB=512 poke_rung "$R11C7" 60 0 tick
forget_digest "$R11C7"
BIONIC_PROBE_FREE_MB=512 poke_rung "$R11C7" 60 0 tick
forget_digest "$R11C7"
BIONIC_PROBE_FREE_MB=512 poke_rung "$R11C7" 60 0 tick
expect_contains "the third consecutive hold is still just a HOLD" "poker: HOLD" "$OUT"
expect_absent   "…and never recommends a width" "NARROW" "$OUT"
expect_eq       "…and no .holds sibling of the stamp was ever written" "" \
  "$(ls "$R11C7/.bionic/tmp/" 2>/dev/null | /usr/bin/grep '\.holds$' || true)"
expect_eq       "the script carries no NARROW at all — not in code, not in a comment" "0" \
  "$(/usr/bin/grep -c 'NARROW' "$POKER" || true)"

# ---------- 11c4: the tick SAMPLES before it reads (AC-15, the Patrol's half) ----------
#
# WHY THIS CASE HAS TO SEED THE RING. `pressure_level` takes a single sample of its own when
# the ring is EMPTY — a first consumer on a cold machine must have something to answer from —
# so every case above would read the right band whether the tick sampled or not. The
# consumers-sample rule (D3 amendment: plugin hooks were not observed firing inside
# subagents, so nothing else fills the ring while writers run) is only observable against a
# ring that already holds a reading of ANOTHER band.
#
# THE ARITHMETIC THAT MAKES IT A DISCRIMINATOR. One CLEAR reading is already in the window.
# The machine now reads CRITICAL. A tick that samples leaves two readings, and an even split
# resolves to the worse band (S7) — critical, a rung of 2. A tick that only READ would see
# the clear reading alone and report the full ceiling of 8.
R11C8="$(mk_rung_repo s11-tick-samples)"
RING8="$TMPROOT/ring-tick-samples.ring"; rm -f "$RING8"
seed_ring "$RING8" 60 0
expect_eq "the seeded ring holds exactly one CLEAR reading" "1" \
  "$(wc -l < "$RING8" | tr -d ' ')"
BIONIC_PRESSURE_RING="$RING8" BIONIC_PROBE_FREE_PCT=8 BIONIC_PROBE_SWAP_PCT=0 poke "$R11C8" tick
expect_contains "the tick's OWN reading is in the median it answers from" "poker: rung=2/8" "$OUT"
expect_eq       "…because it appended one, leaving two readings in the ring" "2" \
  "$(wc -l < "$RING8" | tr -d ' ')"
# THE PAIRED NEGATIVE, same seeded ring shape, machine still CLEAR: sampling is not a way of
# always reading critical. Two clear readings stay clear and the ceiling is untouched.
R11C9="$(mk_rung_repo s11-tick-samples-clear)"
RING9="$TMPROOT/ring-tick-samples-clear.ring"; rm -f "$RING9"
seed_ring "$RING9" 60 0
BIONIC_PRESSURE_RING="$RING9" BIONIC_PROBE_FREE_PCT=60 BIONIC_PROBE_SWAP_PCT=0 poke "$R11C9" tick
expect_contains "a tick that samples a CLEAR machine onto a clear ring stays at the ceiling" \
  "poker: rung=8/8" "$OUT"

# ---------- 11d: EMERGENCY names the youngest suite-running writer ----------
#
# The kill floor. The tick NAMES a writer and stops nothing itself — stopping a writer
# destroys work, and an irreversible act taken by a hook off one reading is what this design
# refuses. The address it prints is the one both stop gates accept (POKER/8).
#
# "SUITE-RUNNING" IS READ OFF THE LEDGER (WALLS/3): an open row whose `claims=` is non-empty
# declared a subprocess claim and spends a suite. YOUNGEST, because the youngest writer has
# the least work to lose.
R11D="$(make_repo s11-emergency)"; new_roster "$R11D"
wave_plan "$R11D" "writers=8 suites=2 worktrees=8 test_jobs=8 source=probe" \
  "| A | 4 | build | fixture task | implementor | — | 15m | REQ-x | a.sh | landed |" \
  "| B | 4 | build | fixture task | implementor | — | 15m | REQ-x | a.sh | pending |"
# `status=intended` is the dispatch record — the row hooks/dispatch-preflight.sh appends
# when it admits a dispatch, carrying that brief's declared `claims=`. It is the predicate
# lib/patrol.sh's `patrol_roster_state` and the dispatch wall's own budget arm both count
# on (WALLS/2, WALLS/3), and the roster is append-only, so later `identified`/`confirmed`
# rows for the same name are transitions rather than second dispatches.
add_row "$R11D" status=intended name=old-suite-runner deliverable=a.md duration="4 hours" \
  claims="bash tests/run.sh" launched_at="$(iso_ago 3600)"
add_row "$R11D" status=intended name=young-suite-runner deliverable=b.md duration="4 hours" \
  claims="bash tests/run.sh" launched_at="$(iso_ago 60)"
add_row "$R11D" status=intended name=no-claim-writer deliverable=c.md duration="4 hours" \
  launched_at="$(iso_ago 10)"
poke_pressure "$R11D" 100 1.0 tick
expect_contains "at the kill floor the tick prints EMERGENCY with the reading" \
  "poker: EMERGENCY free_mb=100" "$OUT"
expect_contains "…naming the YOUNGEST suite-running writer, at the stop address" \
  "stop youngest suite-running writer young-suite-runner@session-$(printf '%s' "$SID" | cut -c1-8)" "$OUT"
expect_absent "…never the older one" "old-suite-runner@" "$OUT"
expect_absent "…and never a writer that claimed no suite" "no-claim-writer@" "$OUT"
expect_absent "…and fills nothing at the kill floor" "poker: FILL" "$OUT"
expect_contains "11d2 …and prints the withheld line the stop wall reads, with the measurement" \
  "poker: fill withheld — EMERGENCY free_mb=100" "$OUT"

# A roster with no suite-claiming row says so rather than naming a writer at random: the
# pressure is real and it is not this session's to relieve.
R11E="$(make_repo s11-emergency-noclaim)"; new_roster "$R11E"
wave_plan "$R11E" "writers=8 suites=2 worktrees=8 test_jobs=8 source=probe" \
  "| A | 4 | build | fixture task | implementor | — | 15m | REQ-x | a.sh | landed |"
add_row "$R11E" status=intended name=quiet-writer deliverable=a.md duration="4 hours" \
  launched_at="$(iso_ago 60)"
poke_pressure "$R11E" 100 1.0 tick
expect_contains "an EMERGENCY with no suite-running writer names no one" \
  "no suite-running writer on this roster to stop" "$OUT"
expect_contains "11e2 …and still withholds the fill, by its measurement" \
  "poker: fill withheld — EMERGENCY free_mb=100" "$OUT"

# ---------- 11f: an unreadable reading is ZERO FREE MEMORY, and that is the kill floor ----
#
# lib/resources.sh answers a SAFE fact rather than an empty field when it cannot read one
# ("A probe that cannot read a fact answers a SAFE fact, never an empty field"), so a
# garbage `free_mb` reads as 0 — below the emergency floor. This case pins the direction
# that fall takes rather than assuming it: a broken probe stops the wave from GROWING, it
# never silently widens it, and the tick still exits 0 because EMERGENCY is a decision.
R11F="$(make_repo s11-probe-junk)"; new_roster "$R11F"
wave_plan "$R11F" "writers=4 suites=2 worktrees=8 test_jobs=8 source=probe" \
  "| A | 4 | build | fixture task | implementor | — | 15m | REQ-x | a.sh | pending |"
poke_pressure "$R11F" "not-a-number" "not-a-load" tick
expect_eq "an unparseable pressure reading still exits 0" "0" "$RC"
expect_contains "…and reads as zero free memory: the safe fact, not an empty field" \
  "poker: EMERGENCY free_mb=0" "$OUT"
expect_absent "…so the wave is never widened off a reading nobody could take" "poker: FILL" "$OUT"

# ============================================================
section "Section 12: FILL — gap, readiness, and table order (AC-29, S7)"
# ============================================================
#
# gap = `writers` from the plan header's `parallel-budget:` MINUS the rows already open on
# this session's roster; ready = the task table's `pending` rows whose every dependency is
# `landed`. The tick prints min(gap, |ready|) ids in TABLE ORDER — the plan's own dependency
# ordering, maintained by the orchestrator, never an ordering this hook invents.

# ---------- 12a: three ready, gap two -> exactly two, in table order ----------
R12A="$(make_repo s12-fill-two)"; new_roster "$R12A"
wave_plan "$R12A" "writers=2 suites=2 worktrees=8 test_jobs=8 source=probe" \
  "| BASE | 4 | build | fixture task | implementor | — | 15m | REQ-x | a.sh | landed |" \
  "| ONE | 4 | build | fixture task | implementor | BASE | 15m | REQ-x | a.sh | pending |" \
  "| TWO | 4 | build | fixture task | implementor | BASE | 15m | REQ-x | a.sh | pending |" \
  "| THREE | 4 | build | fixture task | implementor | — | 15m | REQ-x | a.sh | pending |"
poke_pressure "$R12A" 8192 1.0 tick
expect_eq "a filling tick exits 0" "0" "$RC"
expect_contains "three ready and a gap of two fills exactly two, in table order" \
  "poker: FILL ONE TWO" "$OUT"
expect_absent "…and does not reach the third" "THREE" "$(printf '%s\n' "$OUT" | /usr/bin/grep '^poker: FILL')"

# ---------- 12a-T22: THE FILL LINE PRINTS THE NAME, NOT THE TASK ID ----------
#
# (T22, A-orch-33 — "names are derived, not invented".) The orchestrator copies the token
# the FILL line prints and uses it as the agent's name. For a task whose id has never been
# on this session's roster the two are the same string, which is why every fixture above
# still reads `FILL ONE TWO`. They diverge exactly when the id is already spent: a second
# run of `ONE` cannot be called `ONE`, because the stop gate, the message address and the
# dispatch wall all key on the name, and one name that means two agents is the ambiguity
# this whole task removes. So the tick derives `ONE-r2` and prints THAT.
#
# WHY THE ROSTER IS THE REGISTER and not the plan: the plan's `## Tasks` row keeps its id
# (`ONE` is still `ONE` to a human reading the ledger), and the roster is what actually
# records which names this session has handed out. A name is spent when a row carries it,
# whatever state that row is in — a closed row is the common case (a landed task being run
# again), and an open one cannot be reused either.

# 12a-T22-a: the id is free -> the name IS the id (this is the invariant every other
# fixture in this section rests on, asserted here rather than assumed).
R12AT="$(make_repo s12-fill-name-free)"; new_roster "$R12AT"
wave_plan "$R12AT" "writers=2 suites=2 worktrees=8 test_jobs=8 source=probe" \
  "| ONE | 4 | build | fixture task | implementor | — | 15m | REQ-x | a.sh | pending |"
poke_pressure "$R12AT" 8192 1.0 tick
expect_contains "12a-T22-a an unspent id is its own agent name" "poker: FILL ONE" "$OUT"

# 12a-T22-b: the id already has a CLOSED row -> the name is `ONE-r2`.
R12BT="$(make_repo s12-fill-name-r2)"; new_roster "$R12BT"
wave_plan "$R12BT" "writers=2 suites=2 worktrees=8 test_jobs=8 source=probe" \
  "| ONE | 4 | build | fixture task | implementor | — | 15m | REQ-x | a.sh | pending |"
add_row "$R12BT" name=ONE deliverable=a.md duration="15m" launched_at="$(iso_ago 600)"
swept_marker_write "$(roster_of "$R12BT")" "$(iso_ago 30)" "$SID" ONE a000 MET
poke_pressure "$R12BT" 8192 1.0 tick
expect_contains "12a-T22-b a spent id derives the next run's name" "poker: FILL ONE-r2" "$OUT"

# 12a-T22-c: `ONE` and `ONE-r2` both spent -> `ONE-r3`. The derivation counts, it does not
# guess: a rule that always appended `-r2` would pass (b) and hand out a name already taken.
R12CT="$(make_repo s12-fill-name-r3)"; new_roster "$R12CT"
# writers=4: the two spent rows below are still OPEN to the budget (their deliverable was
# never written), so a ceiling of 2 would close the gap and this case would prove nothing
# about naming.
wave_plan "$R12CT" "writers=4 suites=2 worktrees=8 test_jobs=8 source=probe" \
  "| ONE | 4 | build | fixture task | implementor | — | 15m | REQ-x | a.sh | pending |"
add_row "$R12CT" name=ONE deliverable=a.md duration="15m" launched_at="$(iso_ago 600)"
swept_marker_write "$(roster_of "$R12CT")" "$(iso_ago 30)" "$SID" ONE a000 MET
add_row "$R12CT" name=ONE-r2 deliverable=a.md duration="15m" launched_at="$(iso_ago 600)"
swept_marker_write "$(roster_of "$R12CT")" "$(iso_ago 30)" "$SID" ONE-r2 a000 MET
poke_pressure "$R12CT" 8192 1.0 tick
expect_contains "12a-T22-c a spent derived name derives the next one" "poker: FILL ONE-r3" "$OUT"
expect_absent "…and never re-offers the taken one" "poker: FILL ONE-r2" "$OUT"

# 12a-T22-d: ANOTHER SESSION'S ROSTER DOES NOT SPEND THIS SESSION'S NAMES — the same scope
# the dispatch wall's in-flight arm uses, so the two cannot disagree about which names are
# available.
R12DT="$(make_repo s12-fill-name-other)"; new_roster "$R12DT"
wave_plan "$R12DT" "writers=2 suites=2 worktrees=8 test_jobs=8 source=probe" \
  "| ONE | 4 | build | fixture task | implementor | — | 15m | REQ-x | a.sh | pending |"
add_row_to "$R12DT" "other-session-id" name=ONE deliverable=a.md duration="15m"
poke_pressure "$R12DT" 8192 1.0 tick
expect_contains "12a-T22-d a predecessor's roster does not spend a name here" "poker: FILL ONE" "$OUT"

# ---------- 12a-T22-e: THE PANEL REFRESH IS A ROSTER READING, NOT A TOOL CALL ----------
#
# (T22, A-orch-33.) `payload/scripts/lib/stop.sh` used to refuse the end of a Patrol turn
# until the transcript showed a ListAgents call — a chore demanded of the model before a
# gate would judge, which is exactly what ADR-024 rules out. The obligation behind it was
# real (eighteen finished agents once sat idle on one panel because nobody stopped them),
# and it is answered here instead: the tick already walks every row and every verdict, so
# it NAMES the lineages whose contract is MET and whose agent has not yet gone. Nothing is
# refused and nothing is stopped — the tick holds no authority (ADR-003).
#
# EVERY MET ROW IS A CANDIDATE (T10, A-orch-20 — corrects T1's own §12 fixture). A
# `landing-swept/v1` marker records that a landing was SEEN, not that the agent left: for a
# teammate it is written at its own SubagentStop, the moment it reports, while it is still on
# the panel. So "swept" and "still there" are not opposites, and the marker is read only
# inside the decision below, to close a row the panel already shows gone — never to exclude a
# candidate the panel still lists.
#
# THE PANEL IS THE WHOLE PREDICATE, AND THE TELL IS A DOER NOW (T1; D1, D2).
# `poker: TASKSTOP <name>` named a MET lineage and left the operator to go and find its
# address; from 1.8.0 the tick prints `poker: STANDDOWN <name>` for a MET row whose agent the
# harness STILL LISTS and writes the stop order for it in the same breath, so the TaskStop
# that answers it is never refused by the stop gate. The same row with its agent GONE is not
# a stand-down at all — nobody is there to stop — and is closed by an ack instead (§26).
#
# So every case below carries a ListAgents answer, planted where `session_transcript` looks
# for it. WITHOUT one the tick cannot tell "still there" from "gone" and does neither thing:
# that is the no-answer direction, pinned in §26 rather than here.
S12_CFG="$(fake_config_dir s12-standdown)"
export CLAUDE_CONFIG_DIR="$S12_CFG"
s12_answer() {  # <state> <name[:status]>...
  plant_answer "$S12_CFG/projects/-fixture-project/$SID.jsonl" "$@"
}

R12ET="$(make_repo s12-taskstop-met)"; new_roster "$R12ET"; armed_ago "$R12ET"; delivered_plan "$R12ET"
DEL_E="$R12ET/delivered.md"; echo "done" > "$DEL_E"
add_row "$R12ET" name=done-writer deliverable="$DEL_E" duration="1 minute" \
  launched_at="$(iso_ago 600)" "$(said "$R12ET" done-writer)"
s12_answer fresh "done-writer:running"
poke "$R12ET" tick
OUT_12E="$OUT"
expect_contains "12a-T22-e a MET row whose agent is still listed is stood down by name" \
  "poker: STANDDOWN done-writer" "$OUT"
expect_contains "12a-T22-e2 …and the tell says the order is already written" \
  "TaskStop it (the order is written)" "$OUT"
expect_contains "12a-T22-e3 …and the order is on disk, attributed to the Patrol" \
  "|by=patrol|target=done-writer" \
  "$(cat "$R12ET/.bionic/tmp/stop-orders-$SID.state" 2>/dev/null)"

# THE MARKER RECORDS THAT A LANDING WAS SEEN, NOT THAT THE AGENT LEFT (T10, A-orch-20). For a
# teammate `landing-swept/v1` is written at its own SubagentStop — the moment it reports —
# while it is still on the panel, so a swept row and a live row are not opposites. Presence is
# the panel's fact alone (spec §Assumptions): the marker never stands in for it, here or
# anywhere else in this arm.
R12FT="$(make_repo s12-taskstop-swept)"; new_roster "$R12FT"; armed_ago "$R12FT"; delivered_plan "$R12FT"
DEL_F="$R12FT/delivered.md"; echo "done" > "$DEL_F"
add_row "$R12FT" name=done-writer deliverable="$DEL_F" duration="1 minute" \
  launched_at="$(iso_ago 600)" "$(said "$R12FT" done-writer)"
swept_marker_write "$(roster_of "$R12FT")" "$(iso_ago 30)" "$SID" done-writer a000 MET
s12_answer fresh "done-writer:running"
poke "$R12FT" tick
expect_contains "12a-T22-f a swept row whose agent the panel still lists is stood down all the same" \
  "poker: STANDDOWN done-writer" "$OUT"
expect_contains "12a-T22-f2 …and the order is written, same as the unswept case" \
  "|by=patrol|target=done-writer" \
  "$(cat "$R12FT/.bionic/tmp/stop-orders-$SID.state" 2>/dev/null)"

# THE SAME SWEPT ROW, GONE FROM THE PANEL: no stand-down — there is nobody to stop — but the
# row IS closed, by the ack (RE-AUTHORED at wave-19 T1; ADR-034 d1). The marker records that a
# landing was seen, not that the name was closed; skipping the ack here left every writer that
# reported open for the life of the session (ideas row 16).
R12FG="$(make_repo s12-taskstop-swept-gone)"; new_roster "$R12FG"; armed_ago "$R12FG"; delivered_plan "$R12FG"
DEL_FG="$R12FG/delivered.md"; echo "done" > "$DEL_FG"
add_row "$R12FG" name=done-writer deliverable="$DEL_FG" duration="1 minute" \
  launched_at="$(iso_ago 600)" "$(said "$R12FG" done-writer)"
swept_marker_write "$(roster_of "$R12FG")" "$(iso_ago 30)" "$SID" done-writer a000 MET
s12_answer fresh "some-other-agent:running"
poke "$R12FG" tick
expect_absent "12a-T22-f3 a swept row whose agent the panel no longer lists draws no stand-down" \
  "poker: STANDDOWN" "$OUT"
expect_eq "12a-T22-f4 …and no order is written for it" "no" \
  "$([ -f "$R12FG/.bionic/tmp/stop-orders-$SID.state" ] && echo yes || echo no)"
expect_contains "12a-T22-f5 …and it is acked by the Patrol, reason landed — the ack is the close" \
  "|name=done-writer|by=patrol|reason=landed" \
  "$(cat "$R12FG/.bionic/tmp/sweeper-$SID.state" 2>/dev/null)"

# The second control: an OPEN row is not a MET lineage and is never named.
R12GT="$(make_repo s12-taskstop-open)"; new_roster "$R12GT"; armed_ago "$R12GT"; delivered_plan "$R12GT"
add_row "$R12GT" name=live-writer deliverable="$R12GT/never-written.md" duration="4 hours" \
  launched_at="$(iso_ago 60)"
s12_answer fresh "live-writer:running"
poke "$R12GT" tick
expect_absent "12a-T22-g an open row is never named for a stop" "poker: STANDDOWN" "$OUT"
expect_eq "12a-T22-g2 …and an open row draws no order either" "no" \
  "$([ -f "$R12GT/.bionic/tmp/stop-orders-$SID.state" ] && echo yes || echo no)"

# THE RETIRED TELL, asserted gone rather than assumed: `TASKSTOP` was the 1.7.x spelling, and
# a reader (or a gate) still keyed on it would go silently blind. Asserted against the tick
# that DID stand a row down — the one output where the old tell would have appeared.
expect_absent "12a-T22-h the retired TASKSTOP tell is not printed beside the new one" \
  "TASKSTOP" "$OUT_12E"

# ---------- 12a-T22-i: A STALE PANEL DEFERS RATHER THAN GUESSES (A-orch-31, T6) ----------
#
# Measured 20:55Z: a STALE reading (the panel's last-known answer, not a fresh one) still
# named a MET row for a stand-down and wrote a SECOND order for an agent a prior, human-
# issued stop order had already had stopped eighteen minutes earlier. A tell can afford to
# be a little old; an order and an ack cannot — the arm defers instead of guessing: no
# STANDDOWN, no order, no ack, and exactly one line saying the next tick decides.
R12ST="$(make_repo s12-taskstop-stale)"; new_roster "$R12ST"; armed_ago "$R12ST"; delivered_plan "$R12ST"
DEL_ST="$R12ST/delivered.md"; echo "done" > "$DEL_ST"
add_row "$R12ST" name=done-writer deliverable="$DEL_ST" duration="1 minute" \
  launched_at="$(iso_ago 600)"
s12_answer stale "done-writer:idle"
poke "$R12ST" tick
expect_absent "12a-T22-i a MET row under a STALE panel reading draws no stand-down" \
  "poker: STANDDOWN" "$OUT"
expect_eq "12a-T22-i2 …and no order is written for it" "no" \
  "$([ -f "$R12ST/.bionic/tmp/stop-orders-$SID.state" ] && echo yes || echo no)"
expect_eq "12a-T22-i3 …and it is not acked either — a stale reading is not evidence it is gone" "no" \
  "$([ -f "$R12ST/.bionic/tmp/sweeper-$SID.state" ] && echo yes || echo no)"
# RE-AUTHORED AT REQ-10 AC-10.4 (D5): the deferral is a FACT the reader cannot act on
# differently for knowing it, so it prints as `poker: note:` above the decision line.
# RE-AUTHORED AGAIN AT wave-20 T9 (REQ-4, AC-4.5; consumer report #11): the line NAMES the
# rows it held back — a deferral that names nothing leaves the operator to guess which agent
# is waiting on a ListAgents — and says `stale` only for a reading that is stale.
expect_contains "12a-T22-i4 …and the tick says exactly why, once, as a note naming the row" \
  "poker: note: stand-down deferred for done-writer — the panel reading is stale; ListAgents and the next tick decides" \
  "$OUT"
expect_eq "12a-T22-i5 …and only once" "1" \
  "$(printf '%s\n' "$OUT" | grep -c 'stand-down deferred' | tr -d ' ')"

# ---------- 12a-T22-i6: NO ANSWER AT ALL IS `absent`, NEVER `stale` (AC-4.5) ----------
#
# `live_agents` answers 4 (NONE) for a transcript with no ListAgents answer, and the tick
# finds no transcript at all for a session whose file does not exist. Both used to print
# "stale" — a word about a reading's AGE for a reading that was never taken. Both rows are
# named, the MET one and the duplicate-free open one alike.
R12SN="$(make_repo s12-taskstop-none)"; new_roster "$R12SN"; armed_ago "$R12SN"; delivered_plan "$R12SN"
DEL_SN="$R12SN/delivered.md"; echo "done" > "$DEL_SN"
add_row "$R12SN" name=met-a deliverable="$DEL_SN" duration="1 minute" launched_at="$(iso_ago 600)"
add_row "$R12SN" name=met-b deliverable="$DEL_SN" duration="1 minute" launched_at="$(iso_ago 600)"
s12_answer none
poke "$R12SN" tick
expect_contains "12a-T22-i6 a panel with no answer defers, naming both rows, and says absent" \
  "poker: note: stand-down deferred for met-a met-b — the panel reading is absent; ListAgents and the next tick decides" \
  "$OUT"
expect_absent "12a-T22-i7 …never stale" "the panel reading is stale" "$OUT"
rm -f "$S12_CFG/projects/-fixture-project/$SID.jsonl"
poke "$R12SN" tick
expect_contains "12a-T22-i8 no transcript at all is absent too, naming the rows" \
  "poker: note: stand-down deferred for met-a met-b — the panel reading is absent" "$OUT"

# THE CONFIG DIR IS HANDED BACK. Every case after this one is an ordinary fill case with no
# live answer of its own, and leaving the pointer here would let THIS section's transcript
# decide their `open=` — the trim would read every open row as gone and every gap as wide.
unset CLAUDE_CONFIG_DIR

# ---------- 12b: the gap closes as rows open ----------
#
# The same plan, one open row on the roster: writers=2 minus one open row is a gap of one.
R12B="$(make_repo s12-fill-gap-one)"; new_roster "$R12B"
wave_plan "$R12B" "writers=2 suites=2 worktrees=8 test_jobs=8 source=probe" \
  "| BASE | 4 | build | fixture task | implementor | — | 15m | REQ-x | a.sh | landed |" \
  "| ONE | 4 | build | fixture task | implementor | BASE | 15m | REQ-x | a.sh | pending |" \
  "| TWO | 4 | build | fixture task | implementor | BASE | 15m | REQ-x | a.sh | pending |"
add_row "$R12B" name=live-writer deliverable=a.md duration="4 hours" launched_at="$(iso_ago 60)"
poke_pressure "$R12B" 8192 1.0 tick
expect_contains "one open row against writers=2 leaves a gap of one" "poker: FILL ONE" "$OUT"
expect_absent "…and the second ready task waits" "TWO" "$(printf '%s\n' "$OUT" | /usr/bin/grep '^poker: FILL')"

# ---------- 12c: gap zero -> no FILL, and the reason is the budget ----------
R12C="$(make_repo s12-fill-full)"; new_roster "$R12C"
wave_plan "$R12C" "writers=1 suites=1 worktrees=8 test_jobs=8 source=probe" \
  "| ONE | 4 | build | fixture task | implementor | — | 15m | REQ-x | a.sh | pending |"
add_row "$R12C" name=live-writer deliverable=a.md duration="4 hours" launched_at="$(iso_ago 60)"
poke_pressure "$R12C" 8192 1.0 tick
expect_absent "a full budget fills nothing" "poker: FILL" "$OUT"
expect_contains "…and says which number closed the gap" "writers=1 and 1 unacked roster row(s): the budget is full" "$OUT"

# ---------- 12d: no parallel-budget line -> inert, and it says why ----------
#
# Every plan written before this wave, and every project that never ran Step 0's probe, has
# no such line. A budget is a ceiling a run OPTS INTO, so the absence is inert rather than
# an error — but a scheduler that went silent about it would be indistinguishable from one
# that was broken.
R12D="$(make_repo s12-no-budget)"; new_roster "$R12D"
wave_plan "$R12D" "-" \
  "| ONE | 4 | build | fixture task | implementor | — | 15m | REQ-x | a.sh | pending |"
poke_pressure "$R12D" 8192 1.0 tick
expect_eq "a plan with no parallel-budget line still ticks cleanly (exit 0)" "0" "$RC"
expect_absent "…and fills nothing" "poker: FILL" "$OUT"
expect_contains "…naming the missing key as the reason, as Step 0 writes it" \
  "carries no parallel-budget: writers=<n>" "$OUT"

# ---------- 12e: a pending task with an unlanded dependency is not ready ----------
R12E="$(make_repo s12-unlanded-dep)"; new_roster "$R12E"
wave_plan "$R12E" "writers=8 suites=2 worktrees=8 test_jobs=8 source=probe" \
  "| BASE | 4 | build | fixture task | implementor | — | 15m | REQ-x | a.sh | pending |" \
  "| DEPENDENT | 4 | build | fixture task | implementor | BASE | 15m | REQ-x | a.sh | pending |" \
  "| FREE | 4 | build | fixture task | implementor | — | 15m | REQ-x | a.sh | pending |"
poke_pressure "$R12E" 8192 1.0 tick
expect_contains "a pending task with an unlanded dep is held back" "poker: FILL BASE FREE" "$OUT"
expect_absent "…and DEPENDENT is not named" "DEPENDENT" "$(printf '%s\n' "$OUT" | /usr/bin/grep '^poker: FILL')"

# Several deps, one of them unlanded: ALL of them must be landed, not any.
R12F="$(make_repo s12-multi-dep)"; new_roster "$R12F"
wave_plan "$R12F" "writers=8 suites=2 worktrees=8 test_jobs=8 source=probe" \
  "| A | 4 | build | fixture task | implementor | — | 15m | REQ-x | a.sh | landed |" \
  "| B | 4 | build | fixture task | implementor | — | 15m | REQ-x | a.sh | pending |" \
  "| C | 4 | build | fixture task | implementor | A,B | 15m | REQ-x | a.sh | pending |"
poke_pressure "$R12F" 8192 1.0 tick
expect_contains "a task whose deps are landed AND pending is not ready" "poker: FILL B" "$OUT"
expect_absent "…so C waits for every one of them" " C" "$(printf '%s\n' "$OUT" | /usr/bin/grep '^poker: FILL')"

# A dependency the table does not carry at all is not confirmable, and an unconfirmable
# dependency holds its task back — a task held costs a batch, a task dispatched onto an
# unlanded dependency costs the writer's whole run.
R12G="$(make_repo s12-unknown-dep)"; new_roster "$R12G"
wave_plan "$R12G" "writers=8 suites=2 worktrees=8 test_jobs=8 source=probe" \
  "| ORPHAN | 4 | build | fixture task | implementor | NOT-IN-THIS-TABLE | 15m | REQ-x | a.sh | pending |" \
  "| FINE | 4 | build | fixture task | implementor | — | 15m | REQ-x | a.sh | pending |"
poke_pressure "$R12G" 8192 1.0 tick
expect_contains "an unknown dependency holds its task back" "poker: FILL FINE" "$OUT"
expect_absent "…and ORPHAN is not filled" "ORPHAN" "$(printf '%s\n' "$OUT" | /usr/bin/grep '^poker: FILL')"

# ---------- 12h: the table is read BY HEADER NAME, not by column position ----------
#
# The shipped table is four columns; the SCHED brief's own prose assumed three. A reader
# keyed on position would have been wrong about one of them and silently wrong about the
# next column anyone inserts.
R12H="$(make_repo s12-column-order)"; new_roster "$R12H"
f12h="$R12H/.bionic/docs/plans/epic-99-fixture/wave-01-fixture.plan.md"
mkdir -p "$(dirname "$f12h")"
{
  printf -- '---\ngoverning-skill: superpowers:writing-plans\n'
  printf 'parallel-budget: writers=8 suites=2 worktrees=8 test_jobs=8 source=probe\n'
  printf -- '---\n\n# fixture plan\n\n## SDLC State\n\ncurrent: 4\n%s\n\n- Step 4: in progress\n\n' "$SP_APPROVED_LINE"
  printf '## Tasks\n\n'
  printf '| status | owner | id | step | complexity | deps |\n|---|---|---|---|---|---|\n'
  printf '| landed | ada | BASE | 4 | complex | — |\n'
  printf '| pending | grace | LATER | 4 | standard | BASE |\n'
} > "$f12h"
touch "$f12h"
poke_pressure "$R12H" 8192 1.0 tick
expect_contains "a reordered, wider table is read by column NAME" "poker: FILL LATER" "$OUT"

# ---------- 12i: a FENCED table is documentation, not a schedule ----------
#
# The same rule the plan READ has taken since the 2026-08-15 newest-race incident: a
# schema example inside a ``` fence describes the table, it is not the table.
R12I="$(make_repo s12-fenced-table)"; new_roster "$R12I"
f12i="$R12I/.bionic/docs/plans/epic-99-fixture/wave-01-fixture.plan.md"
mkdir -p "$(dirname "$f12i")"
{
  printf -- '---\ngoverning-skill: superpowers:writing-plans\n'
  printf 'parallel-budget: writers=8 suites=2 worktrees=8 test_jobs=8 source=probe\n'
  printf -- '---\n\n# fixture plan\n\n## SDLC State\n\ncurrent: 4\n%s\n\n- Step 4: in progress\n\n' "$SP_APPROVED_LINE"
  printf 'The task table looks like this:\n\n'
  printf '```\n## Tasks\n\n'
  printf '%s' "$SP_TASKS_HEADER"
  printf '| EXAMPLE | 4 | build | a documented example | implementor | — | 15m | REQ-x | a.sh | pending |\n```\n'
} > "$f12i"
touch "$f12i"
poke_pressure "$R12I" 8192 1.0 tick
expect_absent "a fenced task table is documentation, and fills nothing" "poker: FILL" "$OUT"
expect_contains "…and the tick says the table gave it nothing ready" \
  "no pending task is ready" "$OUT"

# ---------- 12j: a DELIVERED run is never filled ----------
#
# DISARM is terminal and exits above the scheduler: there is nothing left to fill in a run
# that has closed, and a FILL line under a DISARM would be an instruction to dispatch into
# a finished wave.
R12J="$(make_repo s12-delivered)"; new_roster "$R12J"
f12j="$R12J/.bionic/docs/plans/epic-99-fixture/wave-01-fixture.plan.md"
mkdir -p "$(dirname "$f12j")"
{
  printf -- '---\ngoverning-skill: superpowers:writing-plans\n'
  printf 'parallel-budget: writers=8 suites=2 worktrees=8 test_jobs=8 source=probe\n'
  printf -- '---\n\n# fixture plan\n\n## SDLC State\n\ncurrent: 9\n\n'
  printf -- '- Step 9: delivered: bionic 9.9.9; report: record/fixture/close-out.md\n\n'
  printf '## Tasks\n\n'
  printf '%s' "$SP_TASKS_HEADER"
  printf '| LEFTOVER | 4 | build | a task nobody finished | implementor | — | 15m | REQ-x | a.sh | pending |\n'
} > "$f12j"
touch "$f12j"
armed_ago "$R12J" 7200
touch "$f12j"
poke_pressure "$R12J" 8192 1.0 tick
expect_contains "a delivered run DISARMs" "decision=DISARM" "$OUT"
expect_absent "…and is never filled" "poker: FILL" "$OUT"

# ---------- 12k: READINESS IS THE PREREQUISITE GRAPH (wave-20 REQ-5, Δ1, Δ6; ADR-036) ----------
#
# RE-AUTHORED. Through 1.8.6 ready was asked at the plan's own step (REQ-1e, AC-1e.4): a
# Step-6 review row whose deps had landed was "not this step's work" and sat unfilled while
# Verify ran. Δ1 made the prerequisite graph the whole schedule — a work row is ready when it
# is pending and every dependency has landed, whatever its step — and Δ6 kept the step for
# the two gate acts: an `integrate` or `close` row waits for `current:` to reach its step,
# because its real prerequisite is a gate passing, not a task landing.
sp_plan_at_step() {  # <repo> <current> <row>... -> the plan path
  local repo="$1" current="$2"; shift 2
  local f="$repo/.bionic/docs/plans/epic-99-fixture/wave-01-fixture.plan.md" row
  mkdir -p "$(dirname "$f")"
  {
    printf -- '---\ngoverning-skill: superpowers:writing-plans\n'
    printf 'parallel-budget: writers=8 suites=2 worktrees=8 test_jobs=8 source=probe\n'
    printf -- '---\n\n# fixture plan\n\n## SDLC State\n\ncurrent: %s\n%s\n\n' "$current" "$SP_APPROVED_LINE"
    printf -- '- Step %s: in progress\n\n' "$current"
    printf '## Tasks\n\n'
    printf '%s' "$SP_TASKS_HEADER"
    for row in "$@"; do printf '%s\n' "$row"; done
  } > "$f"
  touch "$f"
  printf '%s' "$f"
}

# 12k1 — AC-5.1 at current: 5: a ready Step-5 row, a ready Step-6 row and a Step-8
# integrate row, all three with every dependency landed. The two work rows are filled; the
# integrate row is not, because the run has not reached Step 8.
R12K1="$(make_repo s12-step-scoped)"; new_roster "$R12K1"
sp_plan_at_step "$R12K1" 5 \
  "| T1 | 4 | build | the build that landed | implementor | — | 15m | REQ-x | a.sh | landed |" \
  "| T2 | 5 | verify | this step's work | auditor | T1 | 15m | REQ-x | b.sh | pending |" \
  "| T3 | 6 | review | the next step's work, deps landed | critic | T1 | 15m | REQ-x | c.sh | pending |" \
  "| T4 | 8 | integrate | the merge, a gate act | implementor | T1 | 15m | REQ-x | — | pending |" > /dev/null
poke_pressure "$R12K1" 8192 1.0 tick
expect_contains "AC-5.1 at current: 5 the ready Step-5 AND Step-6 tasks are filled" "poker: FILL T2 T3" "$OUT"
expect_absent "…and the Step-8 integrate row is not (Δ6)" "T4" "$(printf '%s\n' "$OUT" | /usr/bin/grep '^poker: FILL')"

# 12k2 — at current: 4, two ready Step-4 rows and one held back by an unlanded dependency,
# named in TABLE order (the orchestrator's own dependency ordering, not an ordering the
# tick invents).
R12K2="$(make_repo s12-step-order)"; new_roster "$R12K2"
sp_plan_at_step "$R12K2" 4 \
  "| T1 | 4 | build | ready, first in the table | implementor | — | 15m | REQ-x | a.sh | pending |" \
  "| T2 | 4 | build | blocked on a pending row | implementor | T1 | 15m | REQ-x | b.sh | pending |" \
  "| T3 | 4 | build | ready, second in the table | implementor | — | 15m | REQ-x | c.sh | pending |" > /dev/null
poke_pressure "$R12K2" 8192 1.0 tick
expect_contains "two ready Step-4 tasks are filled in table order" "poker: FILL T1 T3" "$OUT"
# A bare task id is tested against the FILL line only: the tick's decision record carries an
# ISO timestamp (`at=2026-09-12T21:…`) whose `T2` made this case red for UTC hours 20–23 (A-86).
expect_absent "…and the one whose dependency has not landed is held back" "T2" "$(printf '%s\n' "$OUT" | /usr/bin/grep '^poker: FILL')"

# 12k3 — at current: 6 a table where nothing is ready: the review waits behind an ACTIVE
# floor, and the integrate row waits for Step 8. The tick says no task is ready, and no
# longer names a step — the step is no longer what it asked about.
R12K3="$(make_repo s12-step-none)"; new_roster "$R12K3"
sp_plan_at_step "$R12K3" 6 \
  "| T1 | 4 | build | landed long ago | implementor | — | 15m | REQ-x | a.sh | landed |" \
  "| T2 | 5 | verify | the floor, in flight | auditor | T1 | 15m | REQ-x | b.sh | active |" \
  "| T3 | 6 | review | behind the floor | critic | T2 | 15m | REQ-x | c.sh | pending |" \
  "| T4 | 8 | integrate | deps landed, step not reached | implementor | T1 | 15m | REQ-x | — | pending |" > /dev/null
poke_pressure "$R12K3" 8192 1.0 tick
expect_contains "a table with no ready row says so" "no pending task is ready" "$OUT"
# THE BULK SENTENCE IS GONE (wave-26 T13; D9, AC-6.6): each waiting row is on its own WAIT line
# with the read it lacks and the row that writes it, the step hold among them.
expect_absent "…and no longer as the bulk sentence that named no row" \
  "none has all its dependencies landed" "$OUT"
expect_contains "…the review names the floor it waits for" \
  "poker: WAIT T3 — waits for T2 (active)" "$OUT"
expect_contains "…and the integrate row its step (T10b)" \
  "poker: WAIT T4 — step 8 integrate row waits for current: 8" "$OUT"
expect_absent "…and names no step it filtered by" "pending step-" "$OUT"

# 12l — THE DIFFERENTIAL (wave-19 REQ-5 AC-5.2, D6; ADR-034 decision 2). The tick and the
# stop wall now count ONE occupancy — this session's roster rows that are not acked — so on
# the fixture where the roster and the plan disagree they must name the same rows. The
# mismatch: BASE is `landed` in the plan (no `active` row anywhere) while its roster row is
# still open (never acked; its deliverable is not on disk). writers=2, one open → gap one.
# The tick fills ONE. Pre-fix the wall read the plan's `active` column (zero) and named
# ONE and TWO; post-fix it reads the roster and names ONE. The row carries no `agent_id=`,
# so the landing gate in the same Stop hook cannot place it and stays out of the verdict.
STOP_HOOK_12L="${BIONIC_HOOKS_DIR}/stop.sh"
# HERMETIC PANEL (T2d, A-T2.13). §12a-T22 unsets CLAUDE_CONFIG_DIR on its way out, and a tick
# with none reads `$HOME/.claude` — the machine's REAL transcript for whatever session id this
# suite carries. 12l's own row wants "no answer" (the roster count stands), so it gets one,
# planted; 12l3–12l6 below plant the panel their shape needs. Unset again after 12l6.
export CLAUDE_CONFIG_DIR="$S12_CFG"
s12_answer none
R12L="$(make_repo s12-differential)"; new_roster "$R12L"
wave_plan "$R12L" "writers=2 suites=2 worktrees=8 test_jobs=8 source=probe" \
  "| BASE | 4 | build | landed, its row still open on the roster | implementor | — | 15m | REQ-x | a.sh | landed |" \
  "| ONE | 4 | build | fixture task | implementor | BASE | 15m | REQ-x | a.sh | pending |" \
  "| TWO | 4 | build | fixture task | implementor | BASE | 15m | REQ-x | a.sh | pending |"
add_row "$R12L" status=intended name=BASE agent_id= deliverable="$R12L/.bionic/docs/record/base.md" \
  duration="4 hours" launched_at="$(iso_ago 60)"
poke_pressure "$R12L" 8192 1.0 tick
OUT_12L="$OUT"          # kept for the R2-6 stale/none-panel control below (12l7e)
# The FILL line proper — `poker: FILL <ids>` — not the later `poker: FILL — … named for
# dispatch` echo beside the decision line (session-poker.sh, the decision block).
S12L_TICK="$(printf '%s\n' "$OUT" | /usr/bin/grep '^poker: FILL [A-Za-z0-9]' | head -1 | sed 's/^poker: FILL //' \
  | tr ' ' '\n' | /usr/bin/grep -v '^$' | sort | tr '\n' ' ')"
# The wall, on the same repo: an ordinary (non-tick) turn that dispatched nothing.
S12L_TR="$R12L/transcript-12l.jsonl"
jq -nc '{type:"user",isSidechain:false,userType:"external",message:{role:"user",content:"where are we?"}}' > "$S12L_TR"
# BOUND before the wall reads it — see s12l_wall_ids (wave-23-fixit-1810 T1).
bind_marker "$R12L" "$R12L/.bionic/docs/plans/epic-99-fixture/wave-01-fixture.plan.md"
S12L_OUT="$(cd "$R12L" && jq -nc --arg t "$S12L_TR" --arg c "$R12L" --arg s "$SID" \
  '{session_id:$s,transcript_path:$t,cwd:$c,hook_event_name:"Stop",stop_hook_active:false}' \
  | env CLAUDE_CODE_SESSION_ID="$SID" BIONIC_PRESSURE_RING="$TMPROOT/ring-12l" BIONIC_PROBE_FREE_PCT=80 \
      BIONIC_PROBE_SWAP_PCT=0 BIONIC_PROBE_LOAD_1M=1.0 bash "$STOP_HOOK_12L" 2>/dev/null)"
S12L_REASON="$(printf '%s' "$S12L_OUT" | jq -r '.reason // ""' 2>/dev/null)"
S12L_WALL=""
for _id in BASE ONE TWO; do
  case " $(printf '%s' "$S12L_REASON" | tr -c 'A-Za-z0-9_.-' ' ') " in *" $_id "*) S12L_WALL="${S12L_WALL}${_id} " ;; esac
done
expect_eq "12l the tick fills one row against one open roster row (the fixture discriminates)" \
  "ONE " "$S12L_TICK"
expect_eq "12l2 AC-5.2 the stop wall names exactly the ids the tick filled" "$S12L_TICK" "$S12L_WALL"

# 12l3–12l6 — THE END-OF-BATCH SHAPE (wave-19 audit V-2; T2d). 12l's BASE row is UNMET, and
# on an UNMET row the tick and the wall already agreed. They did not agree on a MET row the
# ack has not closed yet: every writer landed, and the agent is still idle on the panel, so
# the tick's STANDDOWN names it and does NOT ack it. The wall counts that row (it is not
# acked). The tick used to drop it (MET closes nothing for the fill any more), so its gap
# was one wider: writers=2, one MET-unacked row, two ready rows, and the tick filled ONE TWO
# where the wall allowed ONE. The occupancy the tick sizes its fill from is now the wall's
# predicate: this session's roster rows that are not acked, read AFTER the tick's own ack
# step. So the paired control, the same MET row with its agent GONE from a fresh panel, is
# acked by that step and frees its slot in the same tick.
s12l_wall_ids() {  # <repo> -> the ids among BASE ONE TWO that the stop wall names, sorted
  local repo="$1" tr="$1/transcript-wall.jsonl" out reason ids="" id
  # THE WALL CHARGES ONLY A BOUND SESSION'S OWN LEDGER (wave-23-fixit-1810, REQ-1, D1): the
  # session the tick filled for is bound to the plan it filled from before the wall reads it.
  bind_marker "$repo" "$repo/.bionic/docs/plans/epic-99-fixture/wave-01-fixture.plan.md"
  jq -nc '{type:"user",isSidechain:false,userType:"external",message:{role:"user",content:"where are we?"}}' > "$tr"
  out="$(cd "$repo" && jq -nc --arg t "$tr" --arg c "$repo" --arg s "$SID" \
    '{session_id:$s,transcript_path:$t,cwd:$c,hook_event_name:"Stop",stop_hook_active:false}' \
    | env CLAUDE_CODE_SESSION_ID="$SID" BIONIC_PRESSURE_RING="$TMPROOT/ring-$(basename "$repo")" \
        BIONIC_PROBE_FREE_PCT=80 BIONIC_PROBE_SWAP_PCT=0 BIONIC_PROBE_LOAD_1M=1.0 \
        bash "$STOP_HOOK_12L" 2>/dev/null)"
  reason="$(printf '%s' "$out" | jq -r '.reason // ""' 2>/dev/null)"
  for id in BASE ONE TWO; do
    case " $(printf '%s' "$reason" | tr -c 'A-Za-z0-9_.-' ' ') " in *" $id "*) ids="${ids}${id} " ;; esac
  done
  printf '%s' "$ids"
}
s12l_tick_ids() {  # <the tick's whole channel> -> the FILL ids, sorted, space-terminated
  printf '%s\n' "$1" | /usr/bin/grep '^poker: FILL [A-Za-z0-9]' | head -1 | sed 's/^poker: FILL //' \
    | tr ' ' '\n' | /usr/bin/grep -v '^$' | sort | tr '\n' ' '
}
s12l_met_repo() {  # <label> -> a repo: writers=2, BASE landed, ONE/TWO ready, one MET row
  local r; r="$(make_repo "$1")"; new_roster "$r"
  wave_plan "$r" "writers=2 suites=2 worktrees=8 test_jobs=8 source=probe" \
    "| BASE | 4 | build | landed | implementor | — | 15m | REQ-x | a.sh | landed |" \
    "| ONE | 4 | build | fixture task | implementor | BASE | 15m | REQ-x | a.sh | pending |" \
    "| TWO | 4 | build | fixture task | implementor | BASE | 15m | REQ-x | a.sh | pending |"
  echo "done" > "$r/landed-12l3.md"
  add_row "$r" name=done-writer agent_id= deliverable="$r/landed-12l3.md" duration="4 hours" \
    launched_at="$(iso_ago 600)" "$(said "$r" done-writer)"
  printf '%s' "$r"
}

R12L3="$(s12l_met_repo s12-differential-met-listed)"
s12_answer fresh "done-writer:idle"
poke_pressure "$R12L3" 8192 1.0 tick
expect_contains "12l3 precondition: the MET row's agent is still listed, so the tick stands it down (no ack)" \
  "poker: STANDDOWN done-writer" "$OUT"
S12L3_TICK="$(s12l_tick_ids "$OUT")"
expect_eq "12l3 a MET row the ack has not closed still occupies: writers=2 fills ONE" "ONE " "$S12L3_TICK"
expect_eq "12l4 AC-5.2 on the end-of-batch shape: the stop wall names exactly the ids the tick filled" \
  "$S12L3_TICK" "$(s12l_wall_ids "$R12L3")"

R12L5="$(s12l_met_repo s12-differential-met-gone)"
s12_answer fresh "somebody-else:running"
poke_pressure "$R12L5" 8192 1.0 tick
OUT_12L5="$OUT"         # kept for the R2-6 MET-gone control below (12l7d)
expect_contains "12l5 precondition: the MET row's agent is gone, so the tick's own step acks it" \
  "|name=done-writer|by=patrol|reason=landed" "$(cat "$R12L5/.bionic/tmp/sweeper-$SID.state" 2>/dev/null)"
S12L5_TICK="$(s12l_tick_ids "$OUT")"
expect_eq "12l5 …and the occupancy is read after that ack: the whole gap of two is filled" "ONE TWO " "$S12L5_TICK"
expect_eq "12l6 …and the stop wall, reading the same ledger, names the same two" \
  "$S12L5_TICK" "$(s12l_wall_ids "$R12L5")"

# 12l7 — R2-5/R2-6 (delta review at 1dd9133, C2-5). 12l/12l2 above pin the UNMET-open shape
# under a "no answer" panel, where the liveness trim never ran at all (A-T2.13's own
# reasoning, never driven by a differential). This pins the shape the trim's removal
# actually changes: the SAME UNMET row, under a FRESH panel that shows its agent gone. It is
# the 12l2/64a differential shape, on the UNMET row instead of the MET one — writers=2, BASE
# UNMET and unacked, ONE and TWO ready: expect the tick to fill exactly ONE, the row the wall
# names too.
s12l_unmet_repo() {  # <label> -> a repo: writers=2, BASE UNMET+open on the roster, ONE/TWO ready
  local r; r="$(make_repo "$1")"; new_roster "$r"
  wave_plan "$r" "writers=2 suites=2 worktrees=8 test_jobs=8 source=probe" \
    "| BASE | 4 | build | landed, its row still open on the roster | implementor | — | 15m | REQ-x | a.sh | landed |" \
    "| ONE | 4 | build | fixture task | implementor | BASE | 15m | REQ-x | a.sh | pending |" \
    "| TWO | 4 | build | fixture task | implementor | BASE | 15m | REQ-x | a.sh | pending |"
  add_row "$r" status=intended name=BASE agent_id= deliverable="$r/.bionic/docs/record/base-12l7.md" \
    duration="4 hours" launched_at="$(iso_ago 60)"
  printf '%s' "$r"
}
R12L7="$(s12l_unmet_repo s12-differential-unmet-gone)"
s12_answer fresh "somebody-else:idle"
poke_pressure "$R12L7" 8192 1.0 tick
S12L7_TICK="$(s12l_tick_ids "$OUT")"
expect_eq "12l7 R2-5: an UNMET row absent from a fresh panel still occupies: writers=2 fills ONE" \
  "ONE " "$S12L7_TICK"
expect_eq "12l7b …and the stop wall, reading the same predicate, names the same one" \
  "$S12L7_TICK" "$(s12l_wall_ids "$R12L7")"

# 12l7c — R2-6/C2-5: the tick now names the gone-UNMET row and the verb that closes it, so a
# crashed writer does not stall a fill slot silently until a human happens to run `stopped`.
expect_contains "12l7c R2-6: the tick names the gone-UNMET row and the closing verb" \
  "poker: GONE BASE — UNMET and absent from a fresh panel; close it with: bash ${BIONIC_HOOKS_DIR}/stop-orders.sh stopped BASE" \
  "$OUT"

# 12l7d — the control: a MET-gone row (12l5's own fixture/shape) is never reported as GONE.
# It is acked instead (D2, ADR-034 d1), and the two candidate sets never overlap.
expect_absent "12l7d …and a MET-gone row is never reported as GONE (it is acked instead)" \
  "poker: GONE" "$OUT_12L5"

# 12l7e — the control: a stale/unknown panel (12l/12l2's own fixture, whose UNMET row is
# read under a "no answer" panel) reports no GONE line either — the same silence the
# stand-down arm keeps for a STANDDOWN it cannot trust the panel enough to print (A-orch-31).
expect_absent "12l7e …and an unknown-panel tick reports no GONE line (nothing is fresh enough to trust)" \
  "poker: GONE" "$OUT_12L"

# 12l7f/12l7g — audit V3-2: `GONE_CANDIDATE_NAMES` covers STILL-LIVE too, and 12l7c's line
# hardcoded "UNMET" for every candidate. A STILL-LIVE row, progress-artifact shape, absent
# from a fresh panel is a row `stopped` DOES accept (T1g/A-T1.13's panel-gone override), so
# the report still recommends it — but has to name what it actually is.
s12l_stilllive_repo() {  # <label> -> a repo: writers=2, BASE STILL-LIVE (progress artifact), ONE/TWO ready
  local r; r="$(make_repo "$1")"; new_roster "$r"
  wave_plan "$r" "writers=2 suites=2 worktrees=8 test_jobs=8 source=probe" \
    "| BASE | 4 | build | still working, progress artifact fresh | implementor | — | 15m | REQ-x | a.sh | landed |" \
    "| ONE | 4 | build | fixture task | implementor | BASE | 15m | REQ-x | a.sh | pending |" \
    "| TWO | 4 | build | fixture task | implementor | BASE | 15m | REQ-x | a.sh | pending |"
  echo working > "$r/progress-12l7f.md"
  add_row "$r" status=intended name=BASE agent_id= deliverable="$r/.bionic/docs/record/base-12l7f.md" \
    duration="4 hours" launched_at="$(iso_ago 60)" progress="$r/progress-12l7f.md" cadence="10 minutes"
  printf '%s' "$r"
}
R12L7F="$(s12l_stilllive_repo s12-gone-still-live-no-claim)"
s12_answer fresh "somebody-else:idle"
poke_pressure "$R12L7F" 8192 1.0 tick
expect_contains "12l7f V3-2: a STILL-LIVE (progress-artifact) row absent from a fresh panel names STILL-LIVE, not UNMET" \
  "poker: GONE BASE — STILL-LIVE (progress" "$OUT"
expect_contains "12l7g …and still recommends the closing verb (T1g/A-T1.13 accepts this shape)" \
  "and absent from a fresh panel; close it with: bash ${BIONIC_HOOKS_DIR}/stop-orders.sh stopped BASE" "$OUT"

# 12l7h/12l7i/12l7j — the claimed-process STILL-LIVE shape: `stopped` refuses this one even
# panel-gone (T1g/A-T1.13 — a claimed process pattern is a fact about a real OS process, not
# this session's roster), so the report must not recommend a command that will be refused;
# it prints `GONE?` and names why. A claim is checked for EXISTENCE by pattern
# (`claims_live`, `pgrep -f`), so the honest fixture is a real background CHILD process,
# never this suite's own filename (macOS `pgrep` excludes its own ancestor chain — see
# tests/stop-orders.test.sh's Section 9 for the same note).
S12L7H_MARKER="bionic-t2f-claim-marker-$$"
( exec -a "$S12L7H_MARKER" sleep 30 ) &
S12L7H_PID=$!
s12l_stilllive_claim_repo() {  # <label> -> a repo: writers=2, BASE STILL-LIVE (claimed process), ONE/TWO ready
  local r; r="$(make_repo "$1")"; new_roster "$r"
  wave_plan "$r" "writers=2 suites=2 worktrees=8 test_jobs=8 source=probe" \
    "| BASE | 4 | build | still working, claimed process live | implementor | — | 15m | REQ-x | a.sh | landed |" \
    "| ONE | 4 | build | fixture task | implementor | BASE | 15m | REQ-x | a.sh | pending |" \
    "| TWO | 4 | build | fixture task | implementor | BASE | 15m | REQ-x | a.sh | pending |"
  add_row "$r" status=intended name=BASE agent_id= deliverable="$r/.bionic/docs/record/base-12l7h.md" \
    duration="4 hours" launched_at="$(iso_ago 60)" claims="$S12L7H_MARKER"
  printf '%s' "$r"
}
R12L7H="$(s12l_stilllive_claim_repo s12-gone-still-live-claim)"
s12_answer fresh "somebody-else:idle"
poke_pressure "$R12L7H" 8192 1.0 tick
expect_contains "12l7h V3-2: a claimed-process STILL-LIVE row absent from a fresh panel prints GONE?, never a bare GONE" \
  "poker: GONE? BASE — STILL-LIVE" "$OUT"
expect_contains "12l7i …naming the refusal stopped will give, not a command that will fail" \
  "stopped will refuse it: a claimed process pattern still matches a live process" "$OUT"
expect_absent "12l7j …and the bare GONE (without the ?) is never printed for this row" \
  "poker: GONE BASE" "$OUT"
kill "$S12L7H_PID" 2>/dev/null
wait "$S12L7H_PID" 2>/dev/null

# 12l7k/12l7l — AMBIGUOUS, absent from a fresh panel: `stopped` refuses AMBIGUOUS
# unconditionally, at its verdict-state `case`, before it ever reads a panel
# (hooks/stop-orders.sh:618-630) — so this shape must print `GONE?` too, never a `GONE`
# that recommends a doomed command (audit V3-2).
s12l_ambiguous_repo() {  # <label> -> a repo: writers=2, two contracts share BASE's name, ONE/TWO ready
  #
  # TWO DISTINCT `tool_use_id=` VALUES, NOT `add_row`/`mkrow`. AMBIGUOUS is counted in
  # hooks/session-sweeper.sh's `latest_rows` by DISTINCT (name, tool_use_id) pairs
  # (`contracts[name]++`, keyed on `seen[name SUBSEP tuid]`) — this file's own `mkrow`
  # hardcodes `tool_use_id=toolu_x` for every row and has no override key for it (its `case`
  # has no `tool_use_id=*` arm), so two `add_row` calls for the same name would write ONE
  # contract, never two. `roster_row_fixture` (the same production-shaped writer `mkrow`
  # itself calls into, tests/lib/roster-row.sh) takes the override directly, the same way
  # tests/session-sweeper.test.sh's own "one name, two contracts" fixture (`RA`/`dup`) does.
  local r; r="$(make_repo "$1")"; new_roster "$r"
  wave_plan "$r" "writers=2 suites=2 worktrees=8 test_jobs=8 source=probe" \
    "| BASE | 4 | build | two dispatches share this name | implementor | — | 15m | REQ-x | a.sh | landed |" \
    "| ONE | 4 | build | fixture task | implementor | BASE | 15m | REQ-x | a.sh | pending |" \
    "| TWO | 4 | build | fixture task | implementor | BASE | 15m | REQ-x | a.sh | pending |"
  roster_row_fixture status=intended session="$SID" name=BASE agent_id= \
    deliverable="$r/.bionic/docs/record/base-12l7k-first.md" duration="4 hours" \
    launched_at="$(iso_ago 900)" tool_use_id=toolu_0112L7KFIRST >> "$(roster_of "$r")"
  roster_row_fixture status=intended session="$SID" name=BASE agent_id= \
    deliverable="$r/.bionic/docs/record/base-12l7k-second.md" duration="4 hours" \
    launched_at="$(iso_ago 60)" tool_use_id=toolu_0112L7KSECOND >> "$(roster_of "$r")"
  printf '%s' "$r"
}
R12L7K="$(s12l_ambiguous_repo s12-gone-ambiguous)"
s12_answer fresh "somebody-else:idle"
poke_pressure "$R12L7K" 8192 1.0 tick
expect_contains "12l7k V3-2: an AMBIGUOUS row absent from a fresh panel prints GONE?, naming the refusal" \
  "poker: GONE? BASE — AMBIGUOUS and absent from a fresh panel; stopped will refuse it: two or more contracts share this name; stopped always refuses AMBIGUOUS" \
  "$OUT"
expect_absent "12l7l …and never the bare GONE" "poker: GONE BASE" "$OUT"
unset CLAUDE_CONFIG_DIR

# ============================================================
section "Section 13: the absent roster splits — QUIET before the first dispatch (AC-38)"
# ============================================================
#
# WHAT THIS FIXES, measured on this wave's own Patrol tick #1 (session b1a850c1,
# 2026-09-03). "No roster" was ONE refusal covering two states that deserve opposite
# answers. An orchestrator that had armed at engagement, was standing in the right project,
# and had simply not dispatched anything yet got REFUSED — with a wall of candidate paths
# describing a root that was perfectly correct. Arming precedes dispatch BY DESIGN
# (SKILL.md §Dispatch: "arm at engagement"), so the first tick of every run reaches that
# line, and answering it with a refusal is how a reader learns to ignore the one message
# that also reports a genuinely mis-resolved root.
#
# THE SPLIT: armed here AND the walk chose a real `.bionic` -> QUIET, exit 0, stamp kept,
# one line, no candidate walk. Anything else -> the refusal, unchanged.

# ---------- 13a: armed, real .bionic, nothing dispatched -> QUIET ----------
R13A="$(make_repo s13-armed-quiet)"
# Deliberately NO new_roster: this IS the pre-dispatch state, and it is the only state in
# which the roster file does not exist at all.
poke "$R13A" arm
poke "$R13A" tick
expect_eq "an armed session with nothing dispatched ticks quietly (exit 0)" "0" "$RC"
expect_contains "…and says so in one line the reader can act on" \
  "poker: QUIET — armed, nothing dispatched yet on this session" "$OUT"
expect_contains "…with a decision line a machine can read" "decision=QUIET" "$OUT"
expect_absent "…and never REFUSED" "REFUSED" "$OUT"
expect_absent "…and prints no candidate walk: the root is not in doubt" "chosen" "$OUT"
expect_eq "…and the stamp is kept, so the first dispatch of this run is not refused" "yes" \
  "$([ -f "$(stamp_of "$R13A")" ] && echo yes || echo no)"

# ---------- 13b: the SAME repo, never armed -> the refusal survives ----------
#
# The paired negative, and the one that keeps 13a from being "the tick stopped refusing".
# The arming record is written only by `arm`, and its path resolves against the same root
# the roster's does — so a tick that resolved the wrong root finds no record there either.
R13B="$(make_repo s13-unarmed)"
poke "$R13B" tick
expect_eq "an UNARMED session with no roster still REFUSES (exit 2)" "2" "$RC"
expect_contains "…naming the arming that never happened" "the Patrol never armed here" "$OUT"
expect_absent "…and takes no QUIET decision" "decision=QUIET" "$OUT"

# The discriminator on the other side: arm the same repo and the same tick goes QUIET.
poke "$R13B" arm
poke "$R13B" tick
expect_eq "…and arming that same repo flips it to QUIET (13b discriminates)" "0" "$RC"
expect_contains "…with the armed line" "armed, nothing dispatched yet" "$OUT"

# ---------- 13c: no real .bionic anywhere -> NOT-ENGAGED, one line, exit 0 ----------
#
# THIS ARM CHANGED ITS ANSWER AT task-engaged-session, and the change is the ruling rather
# than a regression. It used to REFUSE with the root walk printed, on the reading that a
# tick landing where no `.bionic` exists has resolved the wrong root. Engagement is read
# from that same resolved root, so a cwd with no `.bionic` above it is, necessarily, a
# session that never invoked the skill — and Chris's ruling is that bionic says nothing
# at all to those. One line, exit 0, no stamp.
#
# WHAT THE OLD ARM PROVED IS NOT LOST. The root walk is still printed on a refusal that
# CAN still happen — Section 5's nested-repo topology, where a real `.bionic` sits above
# the cwd, the session is engaged, and the roster is absent. That case asserts both the
# exit 2 and the walk.
R13C="$TMPROOT/s13-no-bionic"
mkdir -p "$R13C"
( cd "$R13C" && git init -q . ) >/dev/null 2>&1
poke "$R13C" tick
expect_eq "a cwd with no .bionic above it is NOT-ENGAGED, not refused (exit 0)" "0" "$RC"
expect_eq "…saying so in exactly one line" "poker: NOT-ENGAGED — this session has not invoked /bionic:canonical-sdlc; nothing decided" "$OUT"
expect_absent "…and no QUIET is taken on a session it decided nothing about" "decision=QUIET" "$OUT"
if [ -z "$(ls "$R13C/.bionic/tmp/" 2>/dev/null)" ]; then
  ok "…and no stamp, no .bionic/tmp manufactured under the wrong root"
else
  no "…and no stamp, no .bionic/tmp manufactured under the wrong root" \
      "found: $(ls "$R13C/.bionic/tmp/")"
fi

# ---------- 13d: a WORKTREE OF A BARE REPOSITORY reads chosen, not cwd-fallback (FIX-BARE) ----------
#
# critic-findings.md wave-1.4.0 issue 2 (MEDIUM). `_bionic_root_start` used to map every
# linked worktree to dirname(--git-common-dir); for a worktree of a BARE repo that is the
# directory HOLDING bare.git, not a working tree, so the checkout's own `.bionic` was never
# a candidate and the walk landed on cwd-fallback — tripping this file's own TICK_ROOT_TAG =
# "chosen"-only QUIET guard (session-poker.sh ~:1845) and reproducing the tick-#1 REFUSED
# wall AC-38 (Section 13 above) exists to prevent. Real `git init --bare` + a real
# `git worktree add`, never mocked.
R13D_DIR="$TMPROOT/s13d-bare"
mkdir -p "$R13D_DIR"
( cd "$R13D_DIR" && git init -q --bare bare.git ) >/dev/null 2>&1
R13DWT="$R13D_DIR/wt-of-bare"
( cd "$R13D_DIR/bare.git" && git worktree add -q -b s13d-wt "$R13DWT" ) >/dev/null 2>&1
mkdir -p "$R13DWT/.bionic/tmp"
engage "$R13DWT"

poke "$R13DWT" arm
poke "$R13DWT" tick
expect_eq "a bare-repo worktree with its own .bionic ticks quietly, not REFUSED (exit 0)" \
  "0" "$RC"
expect_contains "…the checkout's own .bionic is the chosen root, so the AC-38 guard fires QUIET" \
  "decision=QUIET" "$OUT"
expect_absent "…and never the candidate-wall refusal the bug used to reproduce" "REFUSED" "$OUT"
expect_eq "…and the stamp lands under the checkout, not under dirname(bare.git)" "yes" \
  "$([ -f "$(stamp_of "$R13DWT")" ] && echo yes || echo no)"

# ============================================================
section "Section 14: the LEASE OVERRUN — a worktree outliving its row (AC-28)"
# ============================================================
#
# A spawned worktree is a leased slot bound to the ledger row that dispatched its writer,
# and the lease ends when that row is fact-discharged. A tree still standing afterwards is
# a slot counted against the worktree budget that nobody holds — invisible, because nothing
# in the fleet walks `.worktrees` against the roster. AC-28 gave the walk to the Patrol
# tick; payload/scripts/lib/worktree.sh shipped `worktree_lease_overruns` and the tick never
# called it, so the acceptance criterion was discharged on the library suite alone
# (architecture finding, 05:50Z). This section is the call site.
#
# THE INPUT IS THE VERDICT READ THE TICK ALREADY TAKES — one `session-sweeper.sh verdict`
# over the whole roster — because that is where the discharge vocabulary lives: `state=MET`,
# `state=WAIVED`, and the `acked=` the sweeper folds in from its own ledger. The mapping to
# a tree is by convention (`.worktrees/<dir>` belongs to row `W-<DIR>`), the library's, not
# a second one here.
#
# THE TICK REMOVES NOTHING. It says the tree is standing; landing it is
# `spawn-worktree.sh land`, which the orchestrator runs.

# --- a discharged row whose tree still stands -> a NOTE and a field, never an alarm ---
#
# RE-AUTHORED AT REQ-10 AC-10.3 (D5). This case pinned `decision=NOTIFY` and the absence of
# `decision=QUIET`, which is the defect B4 reported: a standing tree is a FACT about disk,
# discovered fresh on every tick for the life of the tree, and it took the band the Patrol's
# prompt reads for something needing attention. It is a `poker: note:` line and a `trees=`
# field now, and the decision line says what the roster says.
#
# No delivered plan, so DISARM cannot fire and the tick reaches its decision the long way.
R14="$(make_repo s14-overrun)"; new_roster "$R14"
mkdir -p "$R14/.worktrees/foo" "$R14/.bionic/docs/record"
add_row "$R14" name=W-FOO deliverable="$R14/.bionic/docs/record/w-foo.md" duration="4 hours"
printf 'the report\n' > "$R14/.bionic/docs/record/w-foo.md"   # the fact that discharges it
poke "$R14" tick
# The PHYSICAL path, because the tick resolves its root with `pwd -P` and the temporary
# directory this suite builds in is reached through a symlink on macOS.
R14P="$(cd "$R14" && pwd -P)"
expect_contains "a discharged row whose tree still stands is one note naming the tree" \
  "poker: note: tree stands $R14P/.worktrees/foo — row discharged; land or remove" "$OUT"
expect_contains "…and the decision line carries the tree in its own field" \
  "|trees=$R14P/.worktrees/foo" "$OUT"
expect_contains "…while the decision itself is what the roster says: QUIET" \
  "decision=QUIET" "$OUT"
expect_eq "…and the tick does NOT take the NOTIFY band on a standing tree (exit 0)" "0" "$RC"
expect_absent "…nothing on this tick is a NOTIFY" "decision=NOTIFY" "$OUT"
expect_absent "…and the old alarm wording is gone" "NOTIFY lease-overrun" "$OUT"
expect_eq "…and the tree is not removed: the tick lands nothing" "1" \
  "$(ls "$R14/.worktrees" | grep -c .)"

# --- THE DISCRIMINATOR. A tree whose row is NOT discharged is a live lease, and silent.
# Without this the case above passes over a tick that reports every tree it can see.
R14B="$(make_repo s14-live-lease)"; new_roster "$R14B"
mkdir -p "$R14B/.worktrees/bar"
add_row "$R14B" name=W-BAR deliverable="$R14B/.bionic/docs/record/w-bar.md" duration="4 hours"
poke "$R14B" tick
expect_absent "an UNMET row's tree is a live lease, not an overrun" "tree stands" "$OUT"
expect_eq "…and the tick is QUIET (exit 0)" "0" "$RC"

# --- the other half of the discriminator: a discharged row whose tree is already gone.
# That lease ended correctly and has nothing to report.
R14C="$(make_repo s14-landed)"; new_roster "$R14C"
mkdir -p "$R14C/.worktrees" "$R14C/.bionic/docs/record"
add_row "$R14C" name=W-GONE deliverable="$R14C/.bionic/docs/record/w-gone.md" duration="4 hours"
printf 'the report\n' > "$R14C/.bionic/docs/record/w-gone.md"
poke "$R14C" tick
expect_absent "a discharged row whose tree is gone reports nothing" "tree stands" "$OUT"

# --- a project with no .worktrees at all is silent, and cheap ---
R14D="$(make_repo s14-no-trees)"; new_roster "$R14D"
mkdir -p "$R14D/.bionic/docs/record"
add_row "$R14D" name=W-NONE deliverable="$R14D/.bionic/docs/record/w-none.md" duration="4 hours"
printf 'the report\n' > "$R14D/.bionic/docs/record/w-none.md"
poke "$R14D" tick
expect_absent "no .worktrees directory, no walk and no line" "tree stands" "$OUT"

# --- THE LIBRARY IS THE ONE DEFINITION. The tick declares worktree.sh and sources it;
# a private copy of "discharged" or of the tree-to-row convention here would be the third.
expect_eq "the poker wants worktree.sh from the library" "1" \
  "$(grep -c '^BIONIC_LIB_WANT=".*worktree\.sh' "$POKER")"
expect_eq "…and sources it out of BIONIC_LIB" "1" \
  "$(grep -c '^\. "\$BIONIC_LIB/worktree\.sh"' "$POKER")"
expect_eq "…and calls the library's walk rather than restating it" "1" \
  "$(grep -c 'worktree_lease_overruns "' "$POKER")"

# ============================================================
section "Section 15: the unengaged session — tick and adopt decide nothing (AC-10, AC-15)"
# ============================================================
#
# Chris, 2026-09-03: "all guardrails imposed by bionic should only apply when exercising
# bionic. Nothing should apply until bionic is triggered." The Patrol prompt runs `tick`
# every interval, and a Patrol a predecessor left behind can fire in a session that never
# invoked the skill. It must then decide nothing about that session rather than deciding
# wrongly — one line, exit 0, and nothing written.
#
# `arm` and `disarm` are NOT guarded, for opposite reasons. `arm` writes a stamp for a
# session that explicitly asked for one, which is harmless. `disarm` removes that stamp
# and MUST leave the engagement marker exactly where it is: a session that invoked the
# skill is bionic's for its whole life, so every wall is still in force afterwards.

# ---------- tick ----------
R15T="$(make_repo s15-tick)"; new_roster "$R15T"
mkdir -p "$R15T/.bionic/docs/record"
add_row "$R15T" name=W-1 deliverable="$R15T/.bionic/docs/record/w1.md" duration="4 hours" cadence="10 minutes"
unengage "$R15T"
poke "$R15T" tick
expect_eq "AC-10 an unengaged tick exits 0" "0" "$RC"
expect_eq "AC-10 …printing exactly the one not-engaged line" \
  "poker: NOT-ENGAGED — this session has not invoked /bionic:canonical-sdlc; nothing decided" "$OUT"
expect_eq "AC-10 …and writing no Patrol stamp" "no" \
  "$([ -f "$(stamp_of "$R15T")" ] && echo yes || echo no)"
expect_absent "AC-10 …no verdict, no decision record" "decision=" "$OUT"

# CONTROL, on the same fixture: the marker back, and the tick decides again. Without this
# row every assertion above would also pass on a poker that had stopped working.
engage "$R15T"
poke "$R15T" tick
expect_contains "AC-10 control: with the marker back, the same tick decides" "decision=" "$OUT"
expect_eq "AC-10 …and stamps" "yes" "$([ -f "$(stamp_of "$R15T")" ] && echo yes || echo no)"

# ---------- adopt ----------
#
# The predecessor's roster is real and adoptable; only the marker is missing.
R15A="$(make_repo s15-adopt)"
R15A_OTHER="33333333-aaaa-4bbb-8ccc-000000000003"
mkdir -p "$R15A/.bionic/docs/record"
add_row_to "$R15A" "$R15A_OTHER" name=W-OLD status=identified agent_id=aold-one-6666666666666666 \
  subagent_type=bionic:implementor duration="45 minutes" cadence="10 minutes" \
  deliverable="$R15A/.bionic/docs/record/old.md"
unengage "$R15A"
poke "$R15A" adopt
expect_eq "AC-10 an unengaged adopt exits 0" "0" "$RC"
expect_eq "AC-10 …printing exactly the one not-engaged line" \
  "poker: NOT-ENGAGED — this session has not invoked /bionic:canonical-sdlc; nothing decided" "$OUT"
expect_eq "AC-10 …and adopting nothing: no roster for this session" "no" \
  "$([ -f "$(roster_of "$R15A")" ] && echo yes || echo no)"

engage "$R15A"
poke "$R15A" adopt
expect_contains "AC-10 control: with the marker back, adopt reads the predecessor's rows" \
  "W-OLD" "$OUT"

# ---------- AC-15: disarm removes the stamp and LEAVES the marker ----------
R15D="$(make_repo s15-disarm)"; new_roster "$R15D"
poke "$R15D" arm
expect_eq "AC-15 arm writes the stamp" "yes" "$([ -f "$(stamp_of "$R15D")" ] && echo yes || echo no)"
poke "$R15D" disarm
expect_eq "AC-15 disarm exits 0" "0" "$RC"
expect_eq "AC-15 …the Patrol stamp is gone" "no" \
  "$([ -f "$(stamp_of "$R15D")" ] && echo yes || echo no)"
expect_eq "AC-15 …and the engagement marker is STILL THERE" "yes" \
  "$([ -f "$R15D/.bionic/tmp/engaged-$SID.state" ] && echo yes || echo no)"

# ...AND A HOOK STILL BINDS AFTERWARDS, which is the half that matters: the claim is not
# about a file surviving, it is about the walls staying in force for the rest of the
# session. Driven through the hook Chris's own reproduction named — the wall that refuses
# a push to main — on this repo, after the disarm.
R15D_PUSH=$(jq -n --arg s "$SID" --arg c "$R15D" \
  '{session_id:$s, cwd:$c, hook_event_name:"PreToolUse", tool_name:"Bash",
    tool_input:{command:"git push --force origin main"}}' \
  | env CLAUDE_CODE_SESSION_ID="$SID" CLAUDE_PROJECT_DIR= \
      bash "$(dirname "$POKER")/bash-walls.sh" 2>&1 >/dev/null; echo "rc=$?")
expect_contains "AC-15 …so a wall still refuses after the disarm" "rc=2" "$R15D_PUSH"

# ...and the paired negative: remove the marker too and that same push passes.
unengage "$R15D"
R15D_PUSH2=$(jq -n --arg s "$SID" --arg c "$R15D" \
  '{session_id:$s, cwd:$c, hook_event_name:"PreToolUse", tool_name:"Bash",
    tool_input:{command:"git push --force origin main"}}' \
  | env CLAUDE_CODE_SESSION_ID="$SID" CLAUDE_PROJECT_DIR= \
      bash "$(dirname "$POKER")/bash-walls.sh" 2>&1 >/dev/null; echo "rc=$?")
expect_contains "AC-15 …and with the marker gone, it does not" "rc=0" "$R15D_PUSH2"


# ============================================================
section "Section 16: bind — the act that names this session's run (AC-8, D1)"
# ============================================================
#
# WHY A VERB AT ALL. Engagement binds the session when the root holds exactly one open run
# and writes `plan=none` when it holds several (AC-7) — so a resumed session in a root with
# two live runs is deliberately left unbound, and something has to let it say which run is
# its own. That something is this verb: the ONLY way a binding changes after engagement
# besides the governing skill's bind-on-first-write (design ledger D1, rejecting both an
# argument on the engage hook and a hand-edited marker).
#
# WHAT IT MUST REFUSE, and by name. The marker is what points every wall in the fleet at a
# particular plan, so a binding that names something which is not an open run of this root
# would aim the evidence gate at a file nobody is working on. `bind_plan`
# (payload/scripts/lib/binding.sh) holds that invariant and answers 0/1/2; this verb's job
# is to say WHICH refusal happened in words the operator can act on.

R16="$(make_repo s16-bind)"
P16A="$(plan_at "$R16" 'epic-16/wave-a.plan.md'    "$(plan_body 3)")"
P16A_REAL="$(real_path_of "$P16A")"   # canonical spelling — what bind_plan stores (defined here so §16's first rows can use it)
P16B="$(plan_at "$R16" 'epic-16/wave-b.plan.md'    "$(plan_body 4)")"
P16D="$(plan_at "$R16" 'epic-16/wave-done.plan.md' "$(plan_body 9 'delivered: bionic 9.9.9; report: record/fixture/close-out.md')")"
M16="$(marker_of "$R16")"

# ---------- 16a: an open plan binds, in the marker's own shape ----------
poke "$R16" bind "$P16A"
expect_eq       "bind to an open plan exits 0" "0" "$RC"
expect_contains "…and says what it bound" "poker: bound $P16A" "$OUT"
expect_eq       "…the marker is the two-line shape, and only two lines" "2" \
  "$(wc -l < "$M16" | tr -d ' ')"
# bind_plan stores the CANONICAL spelling (Step-6 SEC note, S10a): compare the resolved path.
expect_contains "…its plan= line names the plan that was bound" "plan=$P16A_REAL" "$(cat "$M16")"
expect_contains "…and engaged_at is carried, not dropped" "engaged_at=" "$(cat "$M16")"
expect_eq       "…written 600, as every marker in the fleet is" "600" "$(file_mode "$M16")"
# THE PAIRED NEGATIVE, on the same marker: binding A is also not binding B. Without this a
# writer that dumped every open run into the marker would pass the row above.
expect_absent   "…and the OTHER open run's path appears nowhere in the marker" \
  "$P16B" "$(cat "$M16")"

# ---------- 16b: a relative path resolves against the project root, and REBINDS ----------
# The second half is the contract's own sentence: after engagement, this verb is how a
# binding changes. A verb that refused to move an existing binding would leave a session
# that engaged into the wrong run with no way back.
# The path it resolves to is the PROJECT ROOT's own spelling — `project_root` resolves the
# root physically — so a relative operand is stored physically while an absolute one is
# stored as typed. Both name one file and every comparison in the fleet resolves directories
# before comparing (lib/binding.sh `_bind_resolve`, adopt's `adopt_plan_key`), so the
# difference is cosmetic; it is asserted rather than smoothed over so a future canonicaliser
# has a row that tells it what changed.
P16B_REAL="$(real_path_of "$P16B")"
poke "$R16" bind '.bionic/docs/plans/epic-16/wave-b.plan.md'
expect_eq       "a project-relative path binds (exit 0)" "0" "$RC"
expect_contains "…and is reported as the absolute path it resolved to" "poker: bound $P16B_REAL" "$OUT"
expect_contains "…the marker now names B" "plan=$P16B_REAL" "$(cat "$M16")"
expect_absent   "…and no longer names A: bind REBINDS" "plan=$P16A_REAL" "$(cat "$M16")"

# ---------- 16b2: a DOCS-ROOT-relative path binds too — the spelling session-start prints ----------
# THE PASTE-BACK GAP THIS CLOSES (S10b phase 2, from review P3's relative-path listing).
# session-start prints the open-run listing relative to the DOCS root (`plans/…`), because
# every absolute path there shares one long prefix. An operator who copies a listed line
# into `bind` hands over `plans/epic-16/wave-a.plan.md`, which resolved against the PROJECT
# root is `<repo>/plans/…` — a path that does not exist, and a refusal that reads as if the
# plan were wrong. Both spellings now bind. The project root is still tried FIRST, so every
# operand that worked before resolves to exactly what it resolved to before.
P16A_REAL="$(real_path_of "$P16A")"
poke "$R16" bind 'plans/epic-16/wave-a.plan.md'
expect_eq       "a docs-root-relative path binds (exit 0)" "0" "$RC"
expect_contains "…and is reported as the absolute path it resolved to" "poker: bound $P16A_REAL" "$OUT"
expect_contains "…the marker names A, reached by the listing's own spelling" "plan=$P16A_REAL" "$(cat "$M16")"
# THE PAIRED NEGATIVE: widening resolution must not invent a plan. An operand that is
# neither project-root-relative nor docs-root-relative is still refused, and the refusal
# names the PROJECT-root spelling — the one an operator typing a repo path would expect.
poke "$R16" bind 'plans/epic-16/no-such-plan.md'
expect_eq       "a relative operand matching neither root is still refused" "1" "$RC"
expect_contains "…and the refusal names the project-root spelling" \
  "$R16/plans/epic-16/no-such-plan.md" "$OUT"
# AND THE PRECEDENCE ROW: with a file at BOTH spellings, the project root wins, which is
# today's behaviour unchanged. Without this row the fallback could silently reorder the two.
mkdir -p "$R16/plans/epic-16"
printf '%s' "$(plan_body 3)" > "$R16/plans/epic-16/wave-a.plan.md"
poke "$R16" bind 'plans/epic-16/wave-a.plan.md'
expect_contains "with a file at both spellings the PROJECT root still wins" \
  "$R16/plans/epic-16/wave-a.plan.md" "$OUT"
rm -rf "$R16/plans"
# Restore the binding §16c-§16f expect to find: B, by its absolute path.
poke "$R16" bind "$P16B_REAL"
expect_eq       "…and the fixture is back on B for the refusal cases below" "0" "$RC"

# ---------- 16c: a delivered plan is refused — it is not an OPEN run ----------
_m16_before="$(cksum < "$M16")"
poke "$R16" bind "$P16D"
expect_eq       "bind to a delivered plan exits 1" "1" "$RC"
expect_contains "…and names the reason" "poker: REFUSED — not an open run" "$OUT"
expect_eq       "…leaving the marker byte-for-byte where it was" "$_m16_before" "$(cksum < "$M16")"
expect_contains "…so the session is still bound to what it was bound to" "plan=$P16B_REAL" "$(cat "$M16")"

# ---------- 16d: a path outside this root is not a plan of this root ----------
printf '%s' "$(plan_body 3)" > "$TMPROOT/outside-plan.md"
poke "$R16" bind "$TMPROOT/outside-plan.md"
expect_eq       "bind to a plan outside this root exits 1" "1" "$RC"
expect_contains "…and names the reason" "poker: REFUSED — not a plan under this root" "$OUT"
expect_eq       "…marker untouched" "$_m16_before" "$(cksum < "$M16")"

# ---------- 16e: a file inside the root that is not in a plan directory ----------
mkdir -p "$R16/.bionic/docs/record"
printf '%s' "$(plan_body 3)" > "$R16/.bionic/docs/record/notes.md"
poke "$R16" bind "$R16/.bionic/docs/record/notes.md"
expect_eq       "bind to a non-plan file inside the root exits 1" "1" "$RC"
expect_contains "…and names the reason" "poker: REFUSED — not a plan under this root" "$OUT"
expect_eq       "…marker untouched" "$_m16_before" "$(cksum < "$M16")"

# ---------- 16f: the discriminator between the two refusals is POSITIONAL ----------
# A file that lives under `plans/` but carries no `## SDLC State` is not a member of the
# open-run set either — and it is refused as "not an open run", because the reason is
# chosen by WHERE the path is, not by what is inside it. Stated as its own case so the rule
# is pinned rather than inferred from the two cases above.
printf 'just a note, no SDLC State here\n' > "$R16/.bionic/docs/plans/epic-16/notes.md"
poke "$R16" bind "$R16/.bionic/docs/plans/epic-16/notes.md"
expect_eq       "a non-plan file UNDER plans/ exits 1" "1" "$RC"
expect_contains "…refused as not an open run — the reason is positional" \
  "poker: REFUSED — not an open run" "$OUT"

# ---------- 16f2: a plan THREE levels under plans/ is outside the walk, and says so ----------
# The positional test has to use the SAME depth bound the open-run set is built with
# (review D8c, S10b). `open_runs` walks `find -maxdepth 2`, so `plans/<a>/<b>/x.md` is
# never a candidate — telling its author "not an open run" points them at the plan's
# CONTENT when the truth is that the walk never reached the file. Bounded here to the two
# depths the walk covers: `plans/x.md` and `plans/<dir>/x.md`.
mkdir -p "$R16/.bionic/docs/plans/epic-16/deeper"
printf '%s' "$(plan_body 3)" > "$R16/.bionic/docs/plans/epic-16/deeper/too-deep.plan.md"
poke "$R16" bind "$R16/.bionic/docs/plans/epic-16/deeper/too-deep.plan.md"
expect_eq       "a depth-3 plan under plans/ exits 1" "1" "$RC"
expect_contains "…refused as NOT A PLAN UNDER THIS ROOT — the walk never reached it" \
  "poker: REFUSED — not a plan under this root" "$OUT"
expect_absent   "…and not as an open-run failure, which would blame its content" \
  "poker: REFUSED — not an open run" "$OUT"
# THE PAIRED POSITIVE, same tree, one level up: depth 2 IS inside the walk, so an
# open-but-not-open-run file there still gets the content-shaped reason. Without this row
# the bound above could be a blanket "everything nested is outside the root".
poke "$R16" bind "$R16/.bionic/docs/plans/epic-16/notes.md"
expect_contains "…while its depth-2 sibling is still judged on content" \
  "poker: REFUSED — not an open run" "$OUT"

# ---------- 16g: a missing argument, and too many ----------
#
# EXIT 2, THIS FILE'S ONE CODE FOR AN ARGUMENT ERROR. S6 shipped a 3 here through a
# `USAGE_EXIT` variable only `bind` ever set, reasoning that a missing operand is the same
# class as the missing session key the verb refuses ten lines on. S8 reverted it: the session
# key is an ENVIRONMENT fact the caller cannot type — which is what 3 means everywhere else
# in this file — while an operand left off the command line is the usage error every other
# verb here already exits 2 for. The paired row below pins the OTHER code on the OTHER
# cause, so the two are told apart by this suite rather than merged by it.
poke "$R16" bind
expect_eq       "bind with no argument exits 2, this file's one argument-error code" "2" "$RC"
expect_contains "…and prints the usage" "Usage:" "$OUT"
expect_contains "…which lists bind among the verbs" "session-poker.sh bind" "$OUT"
expect_eq       "…and nothing was written" "$_m16_before" "$(cksum < "$M16")"

poke "$R16" bind "$P16A" "$P16B"
expect_eq       "bind with two arguments is the same usage error, same code" "2" "$RC"
expect_eq       "…and nothing was written" "$_m16_before" "$(cksum < "$M16")"

# THE PAIRED NEGATIVE — 2 is not what this verb says about everything. The missing SESSION
# KEY is an environment fault and still exits 3, so the revert above narrowed one code
# rather than collapsing two into one.
( cd "$R16" && env -u CLAUDE_CODE_SESSION_ID bash "$POKER" bind "$P16A" ) >/dev/null 2>&1
expect_eq       "…while a missing session key is still the environment fault, exit 3" "3" "$?"

# ---------- 16h: the engagement guard is above everything (AC-10) ----------
R16U="$(make_repo s16-unengaged)"
P16U="$(plan_at "$R16U" 'epic-16/wave-u.plan.md' "$(plan_body 3)")"
unengage "$R16U"
poke "$R16U" bind "$P16U"
expect_eq       "bind in a session that never invoked the skill exits 0" "0" "$RC"
expect_contains "…with the one NOT-ENGAGED line, and no refusal" "NOT-ENGAGED" "$OUT"
expect_absent   "…and no binding is claimed" "poker: bound" "$OUT"
expect_eq       "…and no marker is written" "no" \
  "$([ -e "$(marker_of "$R16U")" ] && echo yes || echo no)"

# ---------- 16i: a symlink where the marker goes ----------
# THE GUARD ANSWERS FIRST, and that is the finding this case pins. `engaged_session`
# (payload/scripts/lib/run.sh:351) refuses a symlink at the marker path BEFORE it is
# followed, so a planted link reads as "this session never engaged" rather than reaching
# `bind_plan`'s own symlink refusal. Either way the invariant that matters holds: the link's
# TARGET is not written through.
R16S="$(make_repo s16-symlink)"
P16S="$(plan_at "$R16S" 'epic-16/wave-s.plan.md' "$(plan_body 3)")"
printf 'PLANTED TARGET, MUST NOT BE WRITTEN\n' > "$TMPROOT/s16-link-target"
_s16_target_before="$(cksum < "$TMPROOT/s16-link-target")"
rm -f "$(marker_of "$R16S")"
ln -s "$TMPROOT/s16-link-target" "$(marker_of "$R16S")"
poke "$R16S" bind "$P16S"
expect_contains "a symlink at the marker path is never written through" "NOT-ENGAGED" "$OUT"
expect_eq       "…and the link's target is byte-for-byte untouched" \
  "$_s16_target_before" "$(cksum < "$TMPROOT/s16-link-target")"
expect_absent   "…and no binding is claimed" "poker: bound" "$OUT"

# ---------- 16j: the verb is on the surface ----------
poke "$R16" nosuchverb
expect_contains "the usage lists bind beside the other verbs" "session-poker.sh bind" "$OUT"

# ---------- 16k: a QUIET open run still binds (AC-4) ----------
#
# THE RULE THIS PINS, before the thing that could break it exists. This wave adds a LIVE
# subset of the open runs — open AND touched inside `live-window:` — and gives it to
# `engage` and to `session-start`'s listing. Every GATE, this verb included, keeps measuring
# against the strict OPEN set: a run somebody left alone for a week is still that session's
# run to name, and a bind that consulted liveness would refuse the one operand an operator
# reaches for precisely because the automatic binding did not happen.
P16Q="$(plan_at "$R16" 'epic-16/wave-quiet.plan.md' "$(plan_body 3)")"
P16Q_REAL="$(real_path_of "$P16Q")"
backdate "$P16Q" 691200   # eight days — well past any live window this wave will carry
poke "$R16" bind "$P16Q"
expect_eq       "a plan untouched for eight days, but still OPEN, binds (exit 0)" "0" "$RC"
expect_contains "…and the marker names it" "plan=$P16Q_REAL" "$(cat "$M16")"
# THE PAIRED NEGATIVE, on the same fixture: age is not what makes a run bindable. A plan
# equally old whose run is DELIVERED is still refused, so 16k proves "openness decides",
# not "everything binds".
P16QD="$(plan_at "$R16" 'epic-16/wave-quiet-done.plan.md' \
  "$(plan_body 9 'delivered: bionic 9.9.9; report: record/fixture/close-out.md')")"
backdate "$P16QD" 691200
poke "$R16" bind "$P16QD"
expect_eq       "…while an equally old DELIVERED run is still refused" "1" "$RC"
expect_contains "…as not an open run" "poker: REFUSED — not an open run" "$OUT"

# ---------- 16l: one canonicalizer — two spellings, one plan= (AC-23) ----------
#
# THREE SITES USED TO ANSWER "the comparable spelling of a plan path" and they disagreed at
# the edges: `_bind_resolve` (lib/binding.sh) refuses a relative path, `adopt_plan_key`
# degraded to the raw string, and bind's own inline `BIND_DIR_REAL` degraded to EMPTY. The
# divergence was latent only because `bind_plan` stores the canonical spelling; the first
# comparison to be added on either side would have been wrong. There is one site now, and
# these rows are what says so.
#
# THE TWO SPELLINGS ARE THE ONES AN OPERATOR ACTUALLY TYPES: a `./` prefix from tab
# completion, and a trailing slash from completing a directory-shaped path.
poke "$R16" bind './plans/epic-16/wave-a.plan.md'
expect_eq       "a ./-prefixed operand binds" "0" "$RC"
_m16l_dot="$(/usr/bin/grep '^plan=' "$M16")"
# REBOUND AWAY IN BETWEEN, so the equality below cannot be satisfied by a second bind that
# did nothing at all. Without this row the marker would still hold the `./` result and the
# two reads would match whether the trailing-slash operand bound or was refused.
poke "$R16" bind "$P16B_REAL"
expect_eq       "…the marker is moved off A before the second spelling is tried" "0" "$RC"
expect_contains "…and now names B" "plan=$P16B_REAL" "$(cat "$M16")"
poke "$R16" bind 'plans/epic-16/wave-a.plan.md/'
expect_eq       "…and so does the same path with a trailing slash" "0" "$RC"
_m16l_slash="$(/usr/bin/grep '^plan=' "$M16")"
expect_eq       "…both leave the IDENTICAL plan= spelling in the marker" \
  "$_m16l_dot" "$_m16l_slash"
expect_eq       "…and it is the spelling _bind_resolve produces" \
  "plan=$P16A_REAL" "$_m16l_slash"

# ---------- 16m: a directory that does not resolve is named, not swallowed ----------
#
# The inline canonicalizer left `BIND_REAL` EMPTY when its directory would not resolve, and
# the refusal then fell through the location `case` to "not a plan under this root" — a
# sentence about the WRONG thing: the path may well be under this root, it is the directory
# above it that is missing. The reason now says which of the two happened, and names the
# path either way.
poke "$R16" bind "$TMPROOT/no-such-dir-16m/wave.plan.md"
expect_eq       "a path whose directory does not exist is refused" "1" "$RC"
expect_contains "…naming what could not be resolved, and the path" \
  "poker: REFUSED — its directory does not resolve: $TMPROOT/no-such-dir-16m/wave.plan.md" "$OUT"

# ---------- 16n: adopt compares on the SAME spelling bind stores (AC-23) ----------
#
# THE OTHER HALF OF THE ONE-SITE CLAIM, asserted through behaviour rather than by reading the
# function: a row whose `plan=` is the bound plan with a trailing slash is THIS session's
# row. Under the old `adopt_plan_key` the trailing slash made `cd` fail on a regular file and
# the whole key degraded to the raw string, so the row read as another run's and was listed
# instead of adopted — the partition failing open in the one direction that loses an agent.
R16N="$(make_repo s16-adopt-canon)"; new_roster "$R16N"
P16N="$(plan_at "$R16N" 'epic-16/run-n.plan.md' "$(plan_body 3)")"
P16N_REAL="$(real_path_of "$P16N")"
PRED_16N="d6d6d6d6-4444-4bbb-8ccc-000000000044"
bind_marker "$R16N" "$P16N_REAL"
add_row_to "$R16N" "$PRED_16N" name=canon-writer status=identified agent_id=canonwriter1111111111 \
  subagent_type=bionic:implementor duration="45 minutes" cadence="10 minutes" plan="$P16N_REAL/"
poke "$R16N" adopt
expect_contains "a row naming the bound plan with a trailing slash is THIS session's row" \
  "partition=own" "$(printf '%s\n' "$OUT" | /usr/bin/grep 'name=canon-writer' | head -1)"
expect_contains "…so it lands on this session's roster" "name=canon-writer" \
  "$(cat "$(roster_of "$R16N")")"
# THE PAIRED NEGATIVE: canonicalising is not "call everything ours". A row naming a DIFFERENT
# plan in the same root, trailing slash and all, is still another run's.
P16N2="$(plan_at "$R16N" 'epic-16/run-n2.plan.md' "$(plan_body 4)")"
add_row_to "$R16N" "$PRED_16N" name=other-writer status=identified agent_id=otherwriter222222222 \
  subagent_type=bionic:implementor duration="45 minutes" cadence="10 minutes" \
  plan="$(real_path_of "$P16N2")/"
poke "$R16N" adopt
expect_contains "…while a different plan, equally slashed, is still another run's" \
  "partition=other" "$(printf '%s\n' "$OUT" | /usr/bin/grep 'name=other-writer' | head -1)"
expect_absent   "…and never reaches this session's roster" "name=other-writer" \
  "$(cat "$(roster_of "$R16N")")"

# ============================================================
section "Section 17: adopt partitions the fleet's rows on plan= (AC-2, T2)"
# ============================================================
#
# THE BUG, symptom 2 of the report. `adopt` walked every `roster-*.state` in the project's
# `.bionic/tmp` and offered every open row on every one of them — the only filter was the
# filename. Two runs sharing a root meant each session was handed the other's agents to
# ledger, message and stop.
#
# THE CURE IS ATTRIBUTION, NOT A SECOND SCAN. hooks/dispatch-preflight.sh now stamps the
# dispatching session's bound plan onto every row it writes (`plan=`, trailing), and a BOUND
# caller reads that field: rows naming its own plan are adoptable, rows naming another are
# LISTED under a heading and never written, rows with no field at all are pre-wave rosters
# (A2) and are listed too. An UNBOUND caller has no plan to compare against and gets exactly
# what it got before this wave — every row, adopted — which §8 above asserts in full and
# which nothing here may change.

PRED_A17="a7a7a7a7-1111-4bbb-8ccc-000000000011"
PRED_B17="b7b7b7b7-2222-4bbb-8ccc-000000000022"
PRED_N17="c7c7c7c7-3333-4bbb-8ccc-000000000033"
ID_A17="arun-a-writer-11111111111111"
ID_B17="brun-b-writer-22222222222222"
ID_N17="nrun-n-writer-33333333333333"

# One root, two open runs, three predecessor sessions: one dispatched under run A, one under
# run B, one before this wave existed. Built by a function because the same fixture is driven
# three times — bound to A, bound to B, and unbound — and a partition test whose three arms
# differed in the fixture would prove nothing about the partition.
mk_partition_repo() {  # <label> -> repo path
  local r pa pb
  r="$(make_repo "$1")"; new_roster "$r"
  pa="$(plan_at "$r" 'epic-17/run-a.plan.md' "$(plan_body 3)")"
  pb="$(plan_at "$r" 'epic-17/run-b.plan.md' "$(plan_body 4)")"
  add_row_to "$r" "$PRED_A17" name=a-writer status=identified agent_id="$ID_A17" \
    subagent_type=bionic:implementor duration="45 minutes" cadence="10 minutes" plan="$pa"
  add_row_to "$r" "$PRED_B17" name=b-writer status=identified agent_id="$ID_B17" \
    subagent_type=bionic:implementor duration="45 minutes" cadence="10 minutes" plan="$pb"
  # THE PRE-WAVE ROSTER: no `plan=` field at all, which is every roster written before this
  # wave landed (A2). It is not "another run" and it is not ours — it is unattributable.
  add_row_to "$r" "$PRED_N17" name=n-writer status=identified agent_id="$ID_N17" \
    subagent_type=bionic:implementor duration="45 minutes" cadence="10 minutes"
  printf '%s' "$r"
}

adopt_line() {  # <row name> <output> -> that row's poker-adopt/v1 line
  printf '%s\n' "$2" | grep "^poker-adopt/v1|.*|name=$1|" | head -1
}

OTHER_HEADING="poker: other runs in this root — listed, never adopted"
UNATTR_HEADING="poker: unattributed rows (pre-wave rosters) — listed, never adopted"

# ---------- 17a: bound to A — only A's rows land on this session's roster ----------
R17A="$(mk_partition_repo s17-bound-a)"
A17A="$R17A/.bionic/docs/plans/epic-17/run-a.plan.md"
B17A="$R17A/.bionic/docs/plans/epic-17/run-b.plan.md"
A17A_REAL="$(real_path_of "$A17A")"   # canonical spelling — what bind_marker's real writer stores (S11)
bind_marker "$R17A" "$A17A"
poke "$R17A" adopt
OUT17A="$OUT"
ROSTER17A="$(cat "$(roster_of "$R17A")")"

expect_contains "bound to A: its own run's row is partitioned own" \
  "partition=own" "$(adopt_line a-writer "$OUT17A")"
expect_contains "…and the machine line carries the plan it was attributed to" \
  "plan=$A17A" "$(adopt_line a-writer "$OUT17A")"
expect_contains "…the OTHER run's row is partitioned other" \
  "partition=other" "$(adopt_line b-writer "$OUT17A")"
expect_contains "…the pre-wave row is partitioned unattributed" \
  "partition=unattributed" "$(adopt_line n-writer "$OUT17A")"
expect_contains "…and its plan field says none, because the row carried no attribution" \
  "|plan=none|" "$(adopt_line n-writer "$OUT17A")"
expect_contains "…the other run's rows are printed under a heading that says they are not adopted" \
  "$OTHER_HEADING" "$OUT17A"
expect_contains "…and the unattributed rows under theirs" "$UNATTR_HEADING" "$OUT17A"
# THE ASSERTION THAT MATTERS — the file, not the report. Everything above is a rendering;
# this is what the stop gates will read tomorrow.
expect_contains "…this session's roster gains the A row" "name=a-writer" "$ROSTER17A"
expect_contains "…by id, which is what ownership is established from" "$ID_A17" "$ROSTER17A"
# ATTRIBUTED LIKE A DISPATCHED ROW, in the same trailing field hooks/dispatch-preflight.sh
# writes (S8; spec §Ownership table "roster attribution"). Before this the adopted row was
# the one row on any roster with no `plan=` at all, so a THIRD session bound to this same
# plan read this session's own adoption as `unattributed` and declined to re-adopt it. The
# value is the ADOPTER's binding: the launching session is recorded separately, in
# `adopted_from=`, and both are on the row.
expect_contains "…carrying THIS session's binding in the same trailing plan= field a dispatched row uses" \
  "|plan=$A17A_REAL" "$(printf '%s\n' "$ROSTER17A" | grep "name=a-writer")"
expect_contains "…beside the launching session it was adopted from" \
  "|adopted_from=$PRED_A17|" "$(printf '%s\n' "$ROSTER17A" | grep "name=a-writer")"
expect_absent   "…and NEVER the other run's row" "name=b-writer" "$ROSTER17A"
expect_absent   "…nor its id" "$ID_B17" "$ROSTER17A"
expect_absent   "…nor the unattributed row" "name=n-writer" "$ROSTER17A"
expect_absent   "…nor its id" "$ID_N17" "$ROSTER17A"
# Listed is not hidden: the operator still SEES the rows they may not take.
expect_contains "…the other run's row is still reported" "b-writer" "$OUT17A"
expect_contains "…and so is the unattributed one" "n-writer" "$OUT17A"

# ---------- 17b: bound to B — the inverse, on the same fixture ----------
R17B="$(mk_partition_repo s17-bound-b)"
A17B="$R17B/.bionic/docs/plans/epic-17/run-a.plan.md"
B17B="$R17B/.bionic/docs/plans/epic-17/run-b.plan.md"
B17B_REAL="$(real_path_of "$B17B")"   # canonical spelling — what bind_marker's real writer stores (S11)
bind_marker "$R17B" "$B17B"
poke "$R17B" adopt
OUT17B="$OUT"
ROSTER17B="$(cat "$(roster_of "$R17B")")"

expect_contains "bound to B: B's row is now the own one" \
  "partition=own" "$(adopt_line b-writer "$OUT17B")"
expect_contains "…and A's is the other one" \
  "partition=other" "$(adopt_line a-writer "$OUT17B")"
expect_contains "…this session's roster gains the B row" "name=b-writer" "$ROSTER17B"
expect_contains "…attributed to B, the plan THIS caller is bound to — the opposite answer on the same fixture" \
  "|plan=$B17B_REAL" "$(printf '%s\n' "$ROSTER17B" | grep "name=b-writer")"
expect_absent   "…and never the A row — the same fixture, the opposite answer" \
  "name=a-writer" "$ROSTER17B"
expect_absent   "…nor A's id" "$ID_A17" "$ROSTER17B"
expect_absent   "…nor the unattributed row" "name=n-writer" "$ROSTER17B"

# ---------- 17c: unbound — every row, exactly as before this wave ----------
# The control for both cases above and the guard on AC-3: a session with no binding has no
# plan to partition on, so it takes what `adopt` always gave it. The marker `make_repo`
# plants is EMPTY, which is the shape :82 has planted since this suite was written and which
# lib/run.sh reads as unbound (A1).
R17U="$(mk_partition_repo s17-unbound)"
poke "$R17U" adopt
OUT17U="$OUT"
ROSTER17U="$(cat "$(roster_of "$R17U")")"

expect_contains "unbound: the A row is adopted" "$ID_A17" "$ROSTER17U"
# AN UNBOUND ADOPTER WRITES `plan=none`, the same literal hooks/dispatch-preflight.sh writes
# for an unbound dispatcher — never the plan the row it took happened to name. Adoption does
# not create a binding; `bind` does.
expect_contains "…and the row it wrote says plan=none, because THIS session has no binding" \
  "|plan=none" "$(printf '%s\n' "$ROSTER17U" | grep "name=a-writer")"
expect_absent   "…never the plan the adopted row itself named" \
  "|plan=$R17U/.bionic/docs/plans/epic-17/run-a.plan.md" "$(printf '%s\n' "$ROSTER17U" | grep "name=a-writer")"
expect_contains "…the B row is adopted" "$ID_B17" "$ROSTER17U"
expect_contains "…and so is the unattributed one" "$ID_N17" "$ROSTER17U"
expect_contains "…every line says the partition it did NOT take" \
  "partition=all" "$(adopt_line a-writer "$OUT17U")"
expect_contains "…on the B row too" "partition=all" "$(adopt_line b-writer "$OUT17U")"
expect_contains "…and on the pre-wave row" "partition=all" "$(adopt_line n-writer "$OUT17U")"
expect_absent   "…no run is ever called another run's when there is nothing to compare to" \
  "$OTHER_HEADING" "$OUT17U"
expect_absent   "…and nothing is called unattributed either" "$UNATTR_HEADING" "$OUT17U"

# ---------- 17d: the summary counts separate what was taken from what was shown ----------
expect_contains "bound to A: the summary counts one adopted" "adopted=1" "$OUT17A"
expect_contains "…and two listed" "listed=2" "$OUT17A"
expect_contains "unbound: everything scanned is adopted" "adopted=3" "$OUT17U"
expect_contains "…and nothing is merely listed" "listed=0" "$OUT17U"

# ============================================================
section "Section 18: the tick reads THIS SESSION's run, not the root's newest (AC-3, AC-6)"
# ============================================================
#
# WHAT SECTION 10 PINNED AND WHAT IT COULD NOT. Section 10 proved the tick asks the RUN
# whether it is delivered before it DISARMs. It asked the root, though — `active_plan`, the
# newest plan carrying an unfenced `## SDLC State` — and a root with two runs in it has one
# newest plan and two sessions. So a session whose run was mid-flight DISARMed off the other
# run's close-out, and a session whose run had just closed kept ticking off the other run's
# open plan. Both are pinned below, and both are red under the root-keyed rule.
#
# THE FALLBACK IS ANNOUNCED, NEVER SILENT (AC-3). An unbound session still resolves by
# newest-plan and still behaves exactly as it did, and it now says which resolution it used —
# so a wrong answer in a two-run root is legible on the line that produced it rather than in
# a decision nobody can attribute.

# ---------- 18a: bound to the OPEN run, with a NEWER delivered plan beside it ----------
R18A="$(make_repo s18-bound-open)"; new_roster "$R18A"
armed_ago "$R18A"
P18A_OPEN="$(plan_at "$R18A" 'epic-18/run-open.plan.md' "$(plan_body 4)")"
P18A_DONE="$(plan_at "$R18A" 'epic-18/run-done.plan.md' \
  "$(plan_body 9 'delivered: bionic 9.9.9; report: record/fixture/close-out.md')")"
bind_marker "$R18A" "$P18A_OPEN"
poke "$R18A" tick
expect_eq       "a bound session over a delivered NEIGHBOUR ticks cleanly (exit 0)" "0" "$RC"
expect_contains "…and decides QUIET: this session's run is at current: 4" "decision=QUIET" "$OUT"
expect_absent   "…never DISARM off another run's close-out" "decision=DISARM" "$OUT"
expect_eq       "…and KEEPS the stamp, so the Patrol keeps firing" "yes" \
  "$([ -f "$(stamp_of "$R18A")" ] && echo yes || echo no)"
expect_contains "…the line names THIS session's plan" "$P18A_OPEN" "$OUT"
expect_absent   "…and the neighbour's plan appears nowhere" "$P18A_DONE" "$OUT"
expect_absent   "…a bound session never announces a fallback (AC-3's negative)" \
  "newest-plan fallback" "$OUT"

# ---------- 18b: bound to a run that has CLOSED, with a NEWER open plan beside it ----------
# AC-6: a binding is a commitment. The session says so and stands down; it never falls
# through to the plan the other run is working on.
R18B="$(make_repo s18-bound-closed)"; new_roster "$R18B"
armed_ago "$R18B"
P18B_DONE="$(plan_at "$R18B" 'epic-18/run-done.plan.md' \
  "$(plan_body 9 'delivered: bionic 9.9.9; report: record/fixture/close-out.md')")"
P18B_OPEN="$(plan_at "$R18B" 'epic-18/run-open.plan.md' "$(plan_body 4)")"
bind_marker "$R18B" "$P18B_DONE"
poke "$R18B" tick
expect_eq       "a session bound to a closed run ticks cleanly (exit 0)" "0" "$RC"
expect_contains "…and says so, naming the plan it is bound to" \
  "poker: bound plan closed — $P18B_DONE; this session has no open run" "$OUT"
expect_contains "…and DISARMs: this Patrol has nothing left to carry" "decision=DISARM" "$OUT"
expect_eq       "…the DISARM removes the stamp, as every DISARM does" "no" \
  "$([ -e "$(stamp_of "$R18B")" ] && echo yes || echo no)"
expect_absent   "…and the OTHER run's open plan appears nowhere in the tick" \
  "$P18B_OPEN" "$OUT"
expect_absent   "…a bound session never falls through to a fallback (AC-6)" \
  "newest-plan fallback" "$OUT"

# ---------- 18c: unbound — today's answer, said out loud ----------
R18C="$(make_repo s18-unbound)"; new_roster "$R18C"
armed_ago "$R18C"
P18C="$(plan_at "$R18C" 'epic-18/run-only.plan.md' "$(plan_body 4)")"
POKE_UNBOUND=1 poke "$R18C" tick
expect_contains "an unbound session says which resolution it used" \
  "poker: run resolved by newest-plan fallback (session unbound) — $(real_path_of "$P18C")" "$OUT"
expect_contains "…and says how to bind (wave-23 D1: announced, never acted on)" \
  "bind with session-poker.sh bind $(real_path_of "$P18C")" "$OUT"
expect_contains "…and decides QUIET: no run, so the Patrol keeps its stamp" "decision=QUIET" "$OUT"
expect_absent   "…never over <p>'s step: no run is read for it" "is at current:" "$OUT"
expect_absent   "…never DISARM on an open run" "decision=DISARM" "$OUT"
expect_absent   "…and it is not confused with a closed binding" "bound plan closed" "$OUT"

# ---------- 18d: unbound over a DELIVERED run still DISARMs ----------
# The equivalence guard. `session_run` answers `none` here — no binding, and no OPEN run to
# fall back to — and the tick must still read the newest plan and find the delivery, exactly
# as Section 10's AC-14 case does. A substitution that let `none` mean "no plan" would make
# DISARM unreachable for every unbound session in the fleet.
R18D="$(make_repo s18-unbound-delivered)"; new_roster "$R18D"
armed_ago "$R18D"
P18D="$(plan_at "$R18D" 'epic-18/run-done.plan.md' \
  "$(plan_body 9 'delivered: bionic 9.9.9; report: record/fixture/close-out.md')")"
poke "$R18D" tick
expect_contains "an unbound session over a delivered run still DISARMs" "decision=DISARM" "$OUT"
expect_eq       "…and still removes the stamp" "no" \
  "$([ -e "$(stamp_of "$R18D")" ] && echo yes || echo no)"
expect_absent   "…and announces no fallback: there was no open run to fall back to" \
  "newest-plan fallback" "$OUT"

# ---------- 18e: resolve_run under `fallback` resolves NO run (wave-23-fixit-1810, T11) ----------
# The unit read of what 18c reads through the tick. `fallback <p>` is announced and never
# acted on, so the two output variables are the ones a session with no run gets: no plan, not
# open. The function is extracted as text and driven with `session_run` stubbed, so the
# assertion is on the variables themselves rather than on a decision line downstream.
R18E_FN="$(sed -n '/^resolve_run() {/,/^}/p' "$POKER")"
r18e() {  # <session_run answer> -> "<plan>|<open>|<stderr>" after resolve_run
  bash -c '
    die() { printf "poker: %s\n" "$1" >&2; }
    run_unbound_advisory() { printf "ADVISORY %s" "$1"; }
    session_run() { printf "%s" "$SR_ANSWER"; }
    active_plan() { printf "/must/not/be/read"; }
    POKER_RUN_PLAN=""; POKER_RUN_OPEN=no; POKER_RUN_RESOLVED=no
    eval "$FN"
    resolve_run /r sid 2>"$ERRF"
    printf "%s|%s|%s" "$POKER_RUN_PLAN" "$POKER_RUN_OPEN" "$(cat "$ERRF")"
  ' _ 2>&1
}
export FN="$R18E_FN" ERRF="$TMPROOT/r18e.err"
R18E_OUT="$(SR_ANSWER='fallback /x/other.plan.md' r18e)"
expect_eq "resolve_run under fallback: no plan, not open, advisory on stderr" \
  "|no|poker: ADVISORY /x/other.plan.md" "$R18E_OUT"
R18E_OUT="$(SR_ANSWER='bound-open /x/mine.plan.md' r18e)"
expect_eq "resolve_run under bound-open (control): the plan, open, silent" \
  "/x/mine.plan.md|yes|" "$R18E_OUT"

# ---------- 18e: the scheduler reads the same run ----------
# The tick has two plan readers — the run-state read above and the FILL scheduler's budget
# and task table — and a Patrol that stood its ground correctly while filling another run's
# tasks would be worse than either failure alone. Two budgeted plans, one root: the bound
# one is filled from, and the newest one is not.
R18E="$(make_repo s18-scheduler)"; new_roster "$R18E"
poke "$R18E" arm
P18E_MINE="$(wave_plan_at "$R18E" 'epic-18/mine.plan.md' \
  "writers=4 suites=2 worktrees=8 test_jobs=8 source=probe" "| MINE-TASK | 4 | build | fixture task | implementor | — | 15m | REQ-x | a.sh | pending |")"
P18E_THEIRS="$(wave_plan_at "$R18E" 'epic-18/theirs.plan.md' \
  "writers=9 suites=2 worktrees=8 test_jobs=8 source=probe" "| THEIRS-TASK | 4 | build | fixture task | implementor | — | 15m | REQ-x | a.sh | pending |")"
bind_marker "$R18E" "$P18E_MINE"
# THE READING IS FIXTURE DATA, exactly as Section 11 makes it: a FILL assertion taken on
# whatever memory this machine happens to have free is an assertion that passes or fails on
# the weather. `poke_pressure` pins it healthy so the scheduler reaches the fill decision.
poke_pressure "$R18E" 8192 1.0 tick
expect_contains "the scheduler fills from the BOUND plan's task table" "poker: FILL MINE-TASK" "$OUT"
expect_absent   "…and never from the newest plan, which belongs to another run" \
  "THEIRS-TASK" "$OUT"

# ============================================================
section "Section 19: the tick sizes open= and FILL from the LIVE SET (S19; auditor F-14)"
# ============================================================
#
# THE DEFECT. The spec's ownership table names `session-poker.sh tick` as a rendering
# surface of the LIVE AGENT SET, and the shipped tick read no such thing: it counted roster
# rows by sweeper verdict alone. Since S16 the dispatch wall counts a row open only while
# the harness still calls its agent live, so the two could disagree about the same row — a
# finished-but-unstopped teammate is NOT open to the budget and WAS open to the tick. The
# Patrol would then print a fill the dispatch wall was about to refuse, or withhold one it
# would have allowed. Same question, two answers, which is the one thing this wave exists
# to remove.
#
# THE RULE. A row whose sweeper verdict is STILL-LIVE/UNMET/AMBIGUOUS is counted open only
# if `live_row_open` — the ONE predicate, payload/scripts/lib/agents.sh — says so on THIS
# session's own transcript. The tick DECIDES with it and never writes: no roster row, no
# marker and no verdict moves, which is why an idle row still appears on the roster and
# still notifies when it is overdue.
#
# THE FALLBACK IS THE ROSTER, and it is deliberate. The Patrol's prompt runs this tick
# BEFORE any ListAgents, so a tick that refused on a stale or missing answer would refuse
# every first tick of every session. The tick holds no authority (ADR-003): it prints a
# line. The wall at dispatch is the enforcement, and it is the one that refuses on a stale
# read — so here the roster count stands and the tick says, in one line, that it did.

# THE LIVE ANSWER, planted where `session_transcript` looks for it: any project directory
# of CLAUDE_CONFIG_DIR, file `<session-id>.jsonl`. Same body shape as
# tests/live-agents.test.sh's fixtures and tests/cross-gate-agreement.test.sh's `cg_live`.
S19_CFG="$TMPROOT/s19-config"
mkdir -p "$S19_CFG/projects/-fixture-project"

s19_answer() {  # <state: fresh|stale|none> <name[:status]>... -> plants this session's transcript
  plant_answer "$S19_CFG/projects/-fixture-project/$SID.jsonl" "$@"
}

# THE FILL IS COMPARED EXACTLY, never with a substring. `poker: FILL ONE` is a PREFIX of
# `poker: FILL ONE TWO`, so a contains-assertion on the smaller fill passes on the larger
# one and the arm that is supposed to detect over-filling detects nothing. Found by
# mutation (a) of this task's own battery, which moved the gap from one to two and left
# the row green.
s19_fill() {  # <the tick's whole channel> -> the ids it filled, or empty
  printf '%s\n' "$1" | sed -n 's/^poker: FILL //p' | head -1
}

s19_plan() {  # <repo> — writers=2, one landed base and two pending tasks
  wave_plan "$1" "writers=2 suites=2 worktrees=8 test_jobs=8 source=probe" \
    "| BASE | 4 | build | fixture task | implementor | — | 15m | REQ-x | a.sh | landed |" \
    "| ONE | 4 | build | fixture task | implementor | BASE | 15m | REQ-x | a.sh | pending |" \
    "| TWO | 4 | build | fixture task | implementor | BASE | 15m | REQ-x | a.sh | pending |"
}

export CLAUDE_CONFIG_DIR="$S19_CFG"

# ---------- 19a: the CONTROL — a running row is counted, exactly as before ----------
#
# This is the row that keeps every arm below from passing against a tick that had simply
# stopped counting. Same repo, same plan, same roster: only the STATUS WORD moves.
R19A="$(make_repo s19-running)"; new_roster "$R19A"
s19_plan "$R19A"
add_row "$R19A" name=live-writer deliverable=a.md duration="4 hours" launched_at="$(iso_ago 60)"
s19_answer fresh "live-writer:running"
poke_pressure "$R19A" 8192 1.0 tick
expect_eq "a RUNNING row is open: writers=2 minus one leaves a gap of one" \
  "ONE" "$(s19_fill "$OUT")"
expect_contains "…and the decision line counts it" "|open=1" "$OUT"

# ---------- 19b: an idle (finished, unstopped) agent leaves open=, and keeps its fill slot ----------
#
# Byte-for-byte 19a's fixture with `running` changed to `idle`. The roster row is untouched
# and still says `confirmed`; what changed is the harness's own answer about its agent.
#
# RE-AUTHORED AT T2d (wave-19 audit V-2; REQ-5, ADR-034 d2). `open=` still follows the live
# set, as S19 made it. The FILL does not any more: it is sized from every roster row that is
# not acked, which is the stop wall's predicate, and an unacked row whose agent is idle is
# still one the wall counts. Filling two here would print a FILL the wall's own arithmetic
# refuses to call owed. The slot comes back when the row is acked.
R19B="$(make_repo s19-idle)"; new_roster "$R19B"
s19_plan "$R19B"
add_row "$R19B" name=live-writer deliverable=a.md duration="4 hours" launched_at="$(iso_ago 60)"
s19_answer fresh "live-writer:idle"
poke_pressure "$R19B" 8192 1.0 tick
expect_eq "an IDLE row still occupies the fill until it is acked: writers=2 fills one (T2d)" \
  "ONE" "$(s19_fill "$OUT")"
expect_contains "…and the decision line agrees with the dispatch wall's count" "|open=0" "$OUT"
# THE ROW ITSELF IS UNTOUCHED. The tick decides; it never writes. A tick that had closed the
# roster row to make its own arithmetic true would break every other reader of that file.
expect_contains "…while the roster row it did not count is still on the roster, unchanged" \
  "name=live-writer" "$(cat "$(roster_of "$R19B")")"
expect_absent "…and no landing marker was written for it" \
  "landing-swept" "$(cat "$(roster_of "$R19B")")"

# ---------- 19c: FAIL-CLOSED — an unknown status word keeps the slot ----------
R19C="$(make_repo s19-third)"; new_roster "$R19C"
s19_plan "$R19C"
add_row "$R19C" name=live-writer deliverable=a.md duration="4 hours" launched_at="$(iso_ago 60)"
s19_answer fresh "live-writer:starting"
poke_pressure "$R19C" 8192 1.0 tick
expect_eq "an UNKNOWN status word keeps the row open — the gap stays one" \
  "ONE" "$(s19_fill "$OUT")"

# ---------- 19d: a row the answer does not carry at all is not open ----------
R19D="$(make_repo s19-absent)"; new_roster "$R19D"
s19_plan "$R19D"
add_row "$R19D" name=live-writer deliverable=a.md duration="4 hours" launched_at="$(iso_ago 60)"
s19_answer fresh "somebody-else:running"
poke_pressure "$R19D" 8192 1.0 tick
expect_eq "a row absent from the fresh answer still occupies the fill until acked: one (T2d)" \
  "ONE" "$(s19_fill "$OUT")"
expect_contains "…while open= follows the live set and drops it" "|open=0" "$OUT"

# ---------- 19e: STALE — the roster count stands, and the tick says so ----------
#
# The Patrol prompt runs the tick BEFORE ListAgents, so refusing here would refuse every
# tick. The line names the state and points at the gate that DOES refuse.
R19E="$(make_repo s19-stale)"; new_roster "$R19E"
s19_plan "$R19E"
add_row "$R19E" name=live-writer deliverable=a.md duration="4 hours" launched_at="$(iso_ago 60)"
s19_answer stale "live-writer:idle"
poke_pressure "$R19E" 8192 1.0 tick
expect_eq "a STALE answer falls back to the roster count" "ONE" "$(s19_fill "$OUT")"
expect_contains "…and names the state in one line" \
  "poker: live set stale — open= counted from the roster" "$OUT"
expect_absent "…and the retired ListAgents clause is gone (T6, AC-6.5)" \
  "ListAgents before any dispatch" "$OUT"
expect_eq "…and the tick still exits 0 rather than refusing" "0" "$RC"

# ---------- 19f: NONE — no usable answer in the transcript ----------
R19F="$(make_repo s19-none)"; new_roster "$R19F"
s19_plan "$R19F"
add_row "$R19F" name=live-writer deliverable=a.md duration="4 hours" launched_at="$(iso_ago 60)"
s19_answer none
poke_pressure "$R19F" 8192 1.0 tick
expect_eq "an unreadable live set falls back to the roster count too" "ONE" "$(s19_fill "$OUT")"
expect_contains "…naming that state instead" \
  "poker: live set none — open= counted from the roster" "$OUT"
expect_absent "…and the retired ListAgents clause is gone here too (T6, AC-6.5)" \
  "ListAgents before any dispatch" "$OUT"

# THE SAME, with no transcript for this session at all — the ordinary first tick of a
# session, and the case that must not become a refusal.
rm -f "$S19_CFG/projects/-fixture-project/$SID.jsonl"
R19F2="$(make_repo s19-no-transcript)"; new_roster "$R19F2"
s19_plan "$R19F2"
add_row "$R19F2" name=live-writer deliverable=a.md duration="4 hours" launched_at="$(iso_ago 60)"
poke_pressure "$R19F2" 8192 1.0 tick
expect_eq "no transcript at all: the roster count stands" "ONE" "$(s19_fill "$OUT")"
expect_contains "…with the same one line" "poker: live set none" "$OUT"
expect_eq "…and exit 0" "0" "$RC"

# ---------- 19g: a QUIET tick with nothing open says nothing about the live set ----------
#
# The reader is consulted only when the roster HAS a row whose openness could move. An empty
# roster has nothing for a live answer to narrow, and printing the fallback line on every
# quiet tick of every session would be noise the reader learns to skip.
R19G="$(make_repo s19-quiet)"; new_roster "$R19G"
s19_plan "$R19G"
poke_pressure "$R19G" 8192 1.0 tick
expect_absent "an empty roster consults no live set and says nothing about one" \
  "poker: live set" "$OUT"

# ---------- 19h: DISARM IS NEVER REACHED OFF A LIVENESS READING ----------
#
# DISARM is terminal — it removes the stamp and ends the Patrol for the rest of the session
# — and its precondition is "no open row". A row whose contract is UNMET and whose agent has
# finished without delivering is precisely the state that most needs a Patrol, so the
# terminal decision keeps the ROSTER's count and only the advisory arithmetic (open= and the
# fill) moves with the live set. Delivered run + an unmet roster row + an idle agent.
R19H="$(make_repo s19-disarm)"; new_roster "$R19H"; armed_ago "$R19H"; delivered_plan "$R19H"
R19H_DEL="$R19H/delivered.md"
add_row "$R19H" name=live-writer deliverable="$R19H_DEL" duration="4 hours" \
  launched_at="$(iso_ago 60)" "$(said "$R19H" live-writer)"
s19_answer fresh "live-writer:idle"
poke_pressure "$R19H" 8192 1.0 tick
expect_absent "an idle agent on an UNMET roster row does NOT unlock DISARM" "decision=DISARM" "$OUT"
expect_absent "…and the Patrol is not told it may stop" "the Patrol may stop" "$OUT"
expect_eq "…and the stamp is kept, which is what the arming wall actually reads" "yes" \
  "$([ -f "$(stamp_of "$R19H")" ] && echo yes || echo no)"
# The paired positive: the SAME repo, the SAME idle answer, with the contract genuinely MET
# — so the arm above is a statement about the liveness reading and not about a decision
# this fixture could never have reached.
echo "done" > "$R19H_DEL"
poke_pressure "$R19H" 8192 1.0 tick
expect_contains "…while a genuinely MET roster still DISARMs on the same idle answer" \
  "decision=DISARM" "$OUT"

# ---------- 19i: ONE transcript parse per tick, whatever the open-row count (P-4) ----------
#
# THE COST. `live_row_open` -> `live_agents_status` -> `live_agents` runs two whole-file `jq`
# passes. The loop above asks it once per open row INSIDE a command substitution, and a
# subshell inherits its parent's variables while its own writes die with it — so the
# library's per-process memo (payload/scripts/lib/agents.sh, S20's P-1) was being filled in a
# subshell and thrown away, and every row paid a full parse. Measured on this machine, one
# tick over twelve open rows and a 4.1 MB transcript ran jq 24 times and took 2.98 s; with
# the parse primed once in the tick's own shell, 2 times and 1.83 s. At 32 rows, 64 -> 2.
#
# COUNTED, NOT TIMED. A `jq` shim on PATH records one line per invocation whose argv names
# THIS transcript, then execs the real jq — the seam tests/live-agents.test.sh §T uses. A
# count is a pin and a duration is not: a future edit that reintroduces a per-row parse moves
# the count on any machine, and the count is 2 (one `_la_scan`, one `_la_body`) however many
# rows are open.
#
# THE DOCTORED COUNT MOVED FROM 12 TO 14 (wave-19 delta review R2-6, T2e). All six of this
# fixture's rows are UNMET and unacked, so each is a GONE-report candidate (R2-6): the
# stand-down arm now warms the panel for them too, not only for a MET or duplicate-start
# name. On the REAL tick that costs nothing — the priming call above already filled the
# memo before either reader runs, which is exactly what "the tick parsed the transcript
# exactly twice" just above still pins. The DOCTORED copy has that one priming call cut, so
# whichever reader is now first to ask pays the parse: the six per-row subshells (12, as
# before) AND the stand-down arm's own `live_agents` call, unprimed here for the first time
# in this process (2 more). The anti-vacuity arm's job — proving the priming call is load-
# bearing — is unweakened: it discriminates 14 from 2 exactly as it discriminated 12 from 2.
S19I_SHIM="$TMPROOT/s19i-shim"
mkdir -p "$S19I_SHIM"
S19I_REAL_JQ="$(command -v jq)"
S19I_COUNT="$TMPROOT/s19i-jq-calls"
cat > "$S19I_SHIM/jq" <<SHIMEOF
#!/bin/bash
for _a in "\$@"; do
  case "\$_a" in *"\$S19I_TRANSCRIPT") printf '%s\n' "\$_a" >> "\$S19I_COUNT_FILE" ;; esac
done
exec "$S19I_REAL_JQ" "\$@"
SHIMEOF
chmod +x "$S19I_SHIM/jq"

s19_open() {  # <the tick's whole channel> -> the open= field of its decision line
  printf '%s\n' "$1" | sed -n 's/.*|open=\([0-9][0-9]*\).*/\1/p' | head -1
}

# The tick under a pinned PATH. `poke` cannot carry one, and the shim has to be ahead of the
# real jq for the whole process tree the tick spawns.
poke_counted() {  # <repo> <args...> -> sets OUT, RC; appends to $S19I_COUNT
  local repo="$1"; shift
  OUT=$( cd "$repo" && env PATH="$S19I_SHIM:$PATH" \
           CLAUDE_CODE_SESSION_ID="$SID" \
           S19I_TRANSCRIPT="$S19I_TR" S19I_COUNT_FILE="$S19I_COUNT" \
           bash "$POKER" "$@" 2>&1 ); RC=$?
}

R19I="$(make_repo s19-one-parse)"; new_roster "$R19I"
wave_plan "$R19I" "writers=8 suites=2 worktrees=8 test_jobs=8 source=probe" \
  "| A | 4 | build | fixture task | implementor | — | 15m | REQ-x | a.sh | landed |"
S19I_NAMES=""
S19I_N=1
while [ "$S19I_N" -le 6 ]; do
  add_row "$R19I" name="parse-row-$S19I_N" deliverable="d$S19I_N.md" duration="4 hours" \
    launched_at="$(iso_ago 60)"
  S19I_NAMES="$S19I_NAMES parse-row-$S19I_N:running"
  S19I_N=$((S19I_N + 1))
done
# shellcheck disable=SC2086
s19_answer fresh $S19I_NAMES
S19I_TR="$S19_CFG/projects/-fixture-project/$SID.jsonl"

: > "$S19I_COUNT"
poke_counted "$R19I" tick
expect_eq "six open rows are all counted live (19i is not vacuous)" "6" "$(s19_open "$OUT")"
expect_eq "…and the tick parsed the transcript exactly twice, not twice per row" "2" \
  "$(/usr/bin/grep -c . "$S19I_COUNT" | tr -d ' ')"

# THE ANTI-VACUITY ARM. A doctored copy with the priming line removed — and nothing else
# changed — must pay a parse per row. Without it, "2" above is consistent with a tick that
# had stopped reading the transcript at all, which is exactly what 19f already forbids but
# not what this row is about.
S19I_MUT_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/poker-parse-mut.XXXXXX")"
mkdir -p "$S19I_MUT_ROOT/hooks" "$S19I_MUT_ROOT/scripts"
ln -s "$(cd "$(dirname "$POKER")/../payload/scripts/lib" && pwd -P)" "$S19I_MUT_ROOT/scripts/lib"
for _sib in "$(dirname "$POKER")"/*; do
  _sibname="$(basename "$_sib")"
  [ "$_sibname" = "session-poker.sh" ] && continue
  ln -s "$_sib" "$S19I_MUT_ROOT/hooks/$_sibname"
done
S19I_MUT="$S19I_MUT_ROOT/hooks/session-poker.sh"
sed 's@^        live_agents "\$TICK_TR" >/dev/null 2>&1 || :$@        : # priming removed@' \
  "$POKER" > "$S19I_MUT"
expect_eq "19i meta: the sed anchor landed exactly once (the doctor took)" "1" \
  "$(diff "$POKER" "$S19I_MUT" | /usr/bin/grep -c '^>')"
: > "$S19I_COUNT"
S19I_POKER_REAL="$POKER"; POKER="$S19I_MUT"
forget_digest "$R19I"
poke_counted "$R19I" tick
POKER="$S19I_POKER_REAL"
expect_eq "…the doctored tick still counts the same six rows" "6" "$(s19_open "$OUT")"
expect_eq "…and pays a full parse per row: fourteen, not two (19i discriminates)" "14" \
  "$(/usr/bin/grep -c . "$S19I_COUNT" | tr -d ' ')"
rm -rf "$S19I_MUT_ROOT"

# ============================================================
section "Section 20: the kill-floor target reads the ONE openness predicate, and only MET closes a row"
# ============================================================
#
# TWO DEFINITIONS OF "OPEN" LIVED IN THIS FILE after S19. The tick's `open=` moved onto
# `live_row_open` — the one predicate, payload/scripts/lib/agents.sh — while
# `youngest_suite_writer`, the arm that names an agent for the orchestrator to STOP at the
# kill floor, kept the pre-S19 roster spelling. The least consequential number the tick
# prints asked the live set; the most consequential NAME it prints did not, and so could
# name a writer the harness had already finished with (Step-6 correctness review, out-of-axis
# note on `youngest_suite_writer`).
#
# AND THE MARKER READ WAS STATE-BLIND. `hooks/session-start.sh`'s `open_rows` and the poker's
# own `adopt_fold` both require `state=MET` before a `landing-swept/v1` line closes a row;
# this arm and lib/patrol.sh's `patrol_roster_state` took ANY marker. S17's
# `adopt_copy_marker` is a second writer that puts non-MET markers on a successor's roster BY
# DESIGN, so the two readers that ignored `state=` are exactly the two that now meet them
# (Step-6 security review, out-of-axis note 2).
#
# THE FALLBACK IS THE TICK'S OWN, unchanged: STALE and NONE mean the roster spelling stands,
# because the Patrol's prompt runs before any ListAgents and a kill-floor arm that went silent
# on a first tick would be a wall firing on the healthy path.

swept_marker() {  # <repo> <name> <state>
  swept_marker_write "$(roster_of "$1")" "$(iso_ago 30)" "$SID" "$2" a000 "$3"
}

s20_repo() {  # <label> -> a repo with ONE intended, suite-claiming row named `suite-writer`
  local r; r="$(make_repo "$1")"; new_roster "$r"
  wave_plan "$r" "writers=8 suites=2 worktrees=8 test_jobs=8 source=probe" \
    "| A | 4 | build | fixture task | implementor | — | 15m | REQ-x | a.sh | landed |"
  add_row "$r" status=intended name=suite-writer deliverable=a.md duration="4 hours" \
    claims="bash tests/run.sh" launched_at="$(iso_ago 60)"
  printf '%s' "$r"
}
S20_TARGET="stop youngest suite-running writer suite-writer@session-$(printf '%s' "$SID" | cut -c1-8)"
S20_NONE="no suite-running writer on this roster to stop"

# ---------- 20a: an UNMET marker does NOT close the row ----------
#
# The state S17 made ordinary: a predecessor's verdict copied verbatim onto this roster,
# saying the contract was NOT met. The row is still open work, and a kill floor that read it
# as closed would report there is nobody to stop while the machine is dying.
R20A="$(s20_repo s20-unmet-marker)"
swept_marker "$R20A" suite-writer UNMET
s19_answer fresh "suite-writer:running"
poke_pressure "$R20A" 100 1.0 tick
expect_contains "an UNMET landing-swept marker leaves the row open, so the kill floor names it" \
  "$S20_TARGET" "$OUT"

# ---------- 20b: the paired positive — RE-AUTHORED (epic-23 wave-20 T20, REQ-10, D10) ----------
#
# It read "a MET marker DOES close it". `youngest_suite_writer` was one of the last two roster
# readers that closed a name on a `landing-swept/v1|state=MET` marker alone (found by T17,
# approved by Chris); it now asks the one close predicate, `roster_open_names`
# (payload/scripts/lib/roster.sh): a name is closed by an ack stamped after its latest launch,
# and by nothing else (ADR-034 d1). So the MET marker joins the UNMET one above — it leaves
# the row open, and a running writer behind it is still the one to stop — and the paired
# positive that keeps 20a honest is the ack. Both halves are pinned.
s20_ack() {  # <repo> <name> <at> — the sweeper ledger's ack line, in its writer's shape
  local le; le="$1/.bionic/tmp/sweeper-${SID}.state"
  [ -f "$le" ] || printf '# bionic session sweeper ledger — schema sweeper-ledger/v1 — machine-local, safe to delete\n' > "$le"
  printf 'sweeper-ledger/v1|event=ack|at=%s|epoch=0|pid=1|session=%s|name=%s|by=patrol|reason=landed\n' \
    "$3" "$SID" "$2" >> "$le"
}
R20B="$(s20_repo s20-met-marker)"
swept_marker "$R20B" suite-writer MET
s19_answer fresh "suite-writer:running"
poke_pressure "$R20B" 100 1.0 tick
expect_contains "20b T20: a MET marker with no ack leaves the row open, so the kill floor still names it" \
  "$S20_TARGET" "$OUT"

R20B2="$(s20_repo s20-acked)"
swept_marker "$R20B2" suite-writer MET
s20_ack "$R20B2" suite-writer "$(iso_ago 0)"
s19_answer fresh "suite-writer:running"
poke_pressure "$R20B2" 100 1.0 tick
expect_contains "…while an ack after its launch closes it, and the kill floor names no one (20a discriminates)" \
  "$S20_NONE" "$OUT"
expect_absent "…and never the acked writer's address" "suite-writer@" "$OUT"

# 20b3: AN ACK OLDER THAN THE LAUNCH CLOSES NOTHING. The predicate orders the two stamps; a
# name acked before this dispatch was launched is a relaunch, and it is open again.
R20B3="$(s20_repo s20-acked-before-launch)"
s20_ack "$R20B3" suite-writer "$(iso_ago 600)"
s19_answer fresh "suite-writer:running"
poke_pressure "$R20B3" 100 1.0 tick
expect_contains "…and an ack older than the launch closes nothing: the kill floor names the relaunched writer" \
  "$S20_TARGET" "$OUT"

# ---------- 20c: an IDLE agent is not a writer to stop ----------
#
# Finished and unstopped. The roster still carries the row — the tick writes nothing — but
# the harness has already let the agent go, so stopping it destroys nothing and the address
# is noise at the one moment the operator needs a real one.
R20C="$(s20_repo s20-live-idle)"
s19_answer fresh "suite-writer:idle"
poke_pressure "$R20C" 100 1.0 tick
expect_contains "an IDLE agent is not named at the kill floor" "$S20_NONE" "$OUT"
expect_absent "…so the orchestrator is never handed a stop address for an agent already gone" \
  "suite-writer@" "$OUT"

# ---------- 20d: the control — the same row, still running ----------
R20D="$(s20_repo s20-live-running)"
s19_answer fresh "suite-writer:running"
poke_pressure "$R20D" 100 1.0 tick
expect_contains "…while the same row with a RUNNING agent IS named (20c discriminates)" \
  "$S20_TARGET" "$OUT"

# ---------- 20e/20f: STALE and NONE fall back to the roster spelling ----------
#
# The same fallback `open=` takes twenty lines above, for the same reason: freshness is a
# property of the transcript, not of any one name, and the tick holds no authority. A
# fallback that went silent would make the kill floor useless on precisely the tick that runs
# before the session's first ListAgents.
R20E="$(s20_repo s20-live-stale)"
s19_answer stale "suite-writer:idle"
poke_pressure "$R20E" 100 1.0 tick
expect_contains "a STALE answer falls back to the roster and still names the writer" \
  "$S20_TARGET" "$OUT"

R20F="$(s20_repo s20-live-none)"
s19_answer none
poke_pressure "$R20F" 100 1.0 tick
expect_contains "…and so does an answer the transcript does not carry at all" \
  "$S20_TARGET" "$OUT"

# ============================================================
section "Section 21: hardening — the one unfiltered field, and the tail that reaches a terminal"
# ============================================================
#
# Both of these are LOW severity and neither is reachable through today's harness. They are
# fixed because the reasons they are unreachable are somebody else's guarantees: the CLI
# happens to mint UUID session ids, and `session_id` (payload/scripts/lib/session.sh) applies
# no charset check to either the env or the payload spelling, so the whole guarantee rests
# outside this repo.

# ---------- 21a: `session=` is the one field adopt_write_row did not filter (S-4) ----------
#
# Twelve of the thirteen interpolated fields go through `clean()`; `session=%s` took `$sid`
# raw. A value carrying a `|` forges a segment, and every by-key reader in the fleet takes
# the FIRST match — so a forged `name=` ahead of the real one wins. This is character for
# character the defect the wave fixed on the other writer one task earlier
# (hooks/dispatch-preflight.sh: "the asymmetry between the two writers was itself the defect").
#
# CALLED DIRECTLY, because the verb cannot be driven to it. `engaged_marker_path`
# (payload/scripts/lib/run.sh) charset-guards the session id to `[A-Za-z0-9_-]` before the
# engagement marker is even named, so a hostile id decides NOTHING — 21a2 below is that
# guard, asserted rather than assumed. The writer is still fixed: the guard belongs to a
# different file for a different reason, and a writer that is safe only because someone
# else's wall happens to stand in front of it is the asymmetry this repo already ruled on.
# The head of the script up to its verb dispatch is sourceable as a library, which is how
# the function is reached without running a verb.
# THE HEAD IS PLANTED IN A hooks/ OF ITS OWN, with the library linked in beside it — the
# same shape §11b3's doctored copy uses, and for the same reason: the script resolves
# `../scripts/lib` off its own directory and steps aside when it cannot find it.
S21A_DIR="$TMPROOT/s21-poker-head"
mkdir -p "$S21A_DIR/hooks" "$S21A_DIR/scripts"
ln -s "$(cd "$(dirname "$POKER")/../payload/scripts/lib" && pwd -P)" "$S21A_DIR/scripts/lib"
S21A_LIB="$S21A_DIR/hooks/session-poker-head.sh"
sed -n '1,/^# ---------------------------------------------------------------- verbs$/p' "$POKER" \
  | sed '$d' > "$S21A_LIB"
# `$0` CARRIES THE PATH, not `$1`: the script resolves its library off `dirname "$0"`, so a
# `bash -c … _ <lib>` invocation would look for it beside the caller's cwd and step aside.
expect_eq "21a meta: the sourceable head really does define adopt_write_row" "function" \
  "$(bash -c '. "$0" adopt >/dev/null 2>&1; type -t adopt_write_row' "$S21A_LIB" 2>/dev/null)"
S21A_ROOT="$TMPROOT/s21-forged-sid"
mkdir -p "$S21A_ROOT/.bionic/tmp"
bash -c '
  . "$0" adopt >/dev/null 2>&1
  adopt_write_row "$1/.bionic/tmp/roster-forged.state" \
    "forged|name=ghost|agent_id=deadbeefdeadbeefdeadbeef" \
    pred-writer apred-writer-2121212121212121 bionic:implementor \
    deliv.md prog.md "10 minutes" 2026-09-05T00:00:00Z osid addr none ""
' "$S21A_LIB" "$S21A_ROOT" >/dev/null 2>&1
S21A_ROW="$(grep "^${ROSTER_ROW_SCHEMA}|" "$S21A_ROOT/.bionic/tmp/roster-forged.state" 2>/dev/null | head -1)"
expect_contains "the row IS written (21a is not vacuous)" \
  "agent_id=apred-writer-2121212121212121" "$S21A_ROW"
expect_eq "…and the FIRST name= field a by-key reader sees is the real agent's" \
  "name=pred-writer" \
  "$(printf '%s' "$S21A_ROW" | tr '|' '\n' | grep '^name=' | head -1)"
# `clean()` FOLDS, it does not delete: the `|` becomes a space, so the forged text survives
# INSIDE the session field and is no longer a field of its own. That is the whole property —
# a segment is what a by-key reader sees, and the assertions below are about segments.
S21A_FIELDS="$(printf '%s' "$S21A_ROW" | tr '|' '\n')"
s21_fields_named() {  # <key> -> how many fields of the row carry exactly this key=value
  printf '%s\n' "$S21A_FIELDS" | grep -c "^$1\$" | tr -d ' '
}
expect_eq "…the forged name= is not a field of its own" "0" "$(s21_fields_named 'name=ghost')"
expect_eq "…the real one is, exactly once" "1" "$(s21_fields_named 'name=pred-writer')"
expect_eq "…the forged agent_id= is not a field either" "0" \
  "$(s21_fields_named 'agent_id=deadbeefdeadbeefdeadbeef')"
expect_eq "…and the whole forged value is ONE session= field, folded to spaces" "1" \
  "$(printf '%s\n' "$S21A_FIELDS" | grep -c '^session=' | tr -d ' ')"

# ---------- 21a2: and the verb cannot be driven there in the first place ----------
#
# The reachability half, asserted. `engaged_marker_path` refuses any session id outside
# `[A-Za-z0-9_-]`, so an id carrying a `|` reads as a session that never engaged and every
# verb says exactly that and decides nothing.
S21_SID_REAL="$SID"
SID='forged-sid|name=ghost|agent_id=deadbeefdeadbeefdeadbeef'
R21A2="$(make_repo s21-forged-sid-verb)"; new_roster "$R21A2"
S21_PRED="99999999-aaaa-4bbb-8ccc-000000000021"
add_row_to "$R21A2" "$S21_PRED" name=pred-writer status=identified \
  agent_id=apred-writer-2121212121212121 subagent_type=bionic:implementor \
  duration="45 minutes" cadence="10 minutes" \
  deliverable="$R21A2/.bionic/docs/record/pred.md"
poke "$R21A2" adopt
expect_contains "a session id outside [A-Za-z0-9_-] never reaches a verb at all" \
  "NOT-ENGAGED" "$OUT"
expect_absent "…and adopts nothing" "adopted_from=" "$(cat "$(roster_of "$R21A2")")"
SID="$S21_SID_REAL"

# ---------- 21b: C1 control characters do not survive the adopt report tail (S-6) ----------
#
# The strip was `tr -d '\000-\010\013-\037\177'`, which removes ESC and DEL but not the C1
# block as UTF-8 (`U+0080`–`U+009F`, i.e. `0xC2 0x80`–`0xC2 0x9F`). `U+009B` is CSI: on a
# terminal that honours C1 it opens a control sequence with no ESC in sight. What is quoted
# here is whatever an agent typed, printed into the operator's terminal by a verb they ran to
# find out what a predecessor left behind — the same reason the ESC strip is already there.
R21B="$(make_repo s21-c1-tail)"; new_roster "$R21B"
S21B_PRED="88888888-aaaa-4bbb-8ccc-000000000021"
S21B_ID="ac1tail-one-8888888888888888"
add_row_to "$R21B" "$S21B_PRED" name=c1-writer status=identified agent_id="$S21B_ID" \
  subagent_type=bionic:implementor duration="45 minutes" cadence="10 minutes" \
  deliverable="$R21B/.bionic/docs/record/c1.md"
C21="$(fake_config_dir s21)"
mkdir -p "$C21/projects/-fixture-project/$S21B_PRED/subagents"
S21B_CSI="$(printf '\302\233')"   # U+009B, CSI, as UTF-8
S21B_BODY="C1-TAIL-MARKER ${S21B_CSI}2J done. $(printf 'padding %.0s' 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20)"
printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":%s}]}}\n' \
  "$(printf '%s' "$S21B_BODY" | jq -Rs .)" \
  > "$C21/projects/-fixture-project/$S21B_PRED/subagents/agent-${S21B_ID}.jsonl"
S21_CFG_REAL="${CLAUDE_CONFIG_DIR:-}"
export CLAUDE_CONFIG_DIR="$C21"
poke "$R21B" adopt
if [ -n "$S21_CFG_REAL" ]; then export CLAUDE_CONFIG_DIR="$S21_CFG_REAL"; else unset CLAUDE_CONFIG_DIR; fi
expect_contains "the report tail IS quoted (21b is not vacuous)" "C1-TAIL-MARKER" "$OUT"
S21B_C1=$(printf '%s' "$OUT" | LC_ALL=C grep -c -- "$S21B_CSI") || S21B_C1=0
expect_eq "…and the CSI byte pair does not survive it" "0" "$S21B_C1"
expect_contains "…while the printable text beside the stripped byte survives" "2J done." "$OUT"

unset CLAUDE_CONFIG_DIR

# ============================================================
section "Section 22: FILL waits on Step-3 approval (epic-21 T4, AC-5)"
# ============================================================
#
# A printed FILL is a dispatch instruction (patrol-duties-gate.sh treats it as a duty), and
# dispatching a writer before Step 3's ratification review has ever run sends it against work
# nobody approved. `current:` below 4 means the plan is still inside Steps 0-3; observed
# 2026-09-05T17:54Z, the tick printed `FILL S1 S2 S3 S4 S12 S14 S15 S16` against the wave-01
# plan sitting at `current: 3` with eight ready tasks — this section reproduces that exact
# shape (writers=8, eight dependency-free pending tasks) as its RED fixture, and its GREEN
# twin (the identical plan at `current: 4`) proves the fix does not disturb the earlier,
# already-covered current:4 behavior Section 12 pins.

# ---------- fixture: the 17:54Z shape, at a caller-named `current:` ----------
s22_plan_at_current() {  # <repo> <current> -> the path, an eight-task writers=8 plan
  local repo="$1" cur="$2"
  local f="$repo/.bionic/docs/plans/epic-21-v1-ladder/wave-01-fixture.plan.md"
  mkdir -p "$(dirname "$f")"
  {
    printf -- '---\n'
    printf 'governing-skill: superpowers:writing-plans\n'
    printf 'parallel-budget: writers=8 suites=4 worktrees=32 test_jobs=8 source=probe\n'
    printf -- '---\n\n# fixture plan (mirrors the observed wave-01 shape)\n\n'
    printf '## SDLC State\n\ncurrent: %s\n' "$cur"
    # Approved exactly when the step says Step 3 has passed, so every row below still reads
    # as it did when `current:` was the gate; 22i and 22j pull the two facts apart.
    case "${cur%[ab]}" in [4-9]) printf '%s\n' "${S22_APPROVAL-$SP_APPROVED_LINE}" ;; *) [ -n "${S22_APPROVAL:-}" ] && printf '%s\n' "$S22_APPROVAL" ;; esac
    printf '\n- Step %s: in progress\n\n' "$cur"
    printf '## Tasks\n\n'
    printf '%s' "$SP_TASKS_HEADER"
    local id
    for id in S1 S2 S3 S4 S12 S14 S15 S16; do
      printf '| %s | 4 | build | generated | implementor | — | 15m | REQ-x | a.sh | pending |\n' "$id"
    done
  } > "$f"
  touch "$f"
  printf '%s' "$f"
}

# ---------- 22a: RED FIXTURE — current: 3, eight ready tasks -> no FILL line ----------
R22A="$(make_repo s22-current-3)"; new_roster "$R22A"
s22_plan_at_current "$R22A" 3 >/dev/null
poke_pressure "$R22A" 8192 1.0 tick
expect_eq "a plan awaiting approval still ticks cleanly (exit 0)" "0" "$RC"
expect_absent "the 17:54Z shape at current: 3 prints no FILL line at all" "poker: FILL" "$OUT"
expect_contains "…and names the pending approval instead" \
  "no FILL — plan at current: 3, Step-3 approval pending" "$OUT"
expect_absent "…so none of the eight tasks are named" "FILL S1" "$OUT"

# ---------- 22b: the same plan at current: 4 FILLs exactly as it always has ----------
R22B="$(make_repo s22-current-4)"; new_roster "$R22B"
s22_plan_at_current "$R22B" 4 >/dev/null
poke_pressure "$R22B" 8192 1.0 tick
expect_eq "an approved plan still ticks cleanly (exit 0)" "0" "$RC"
expect_contains "the identical shape at current: 4 fills all eight, in table order" \
  "poker: FILL S1 S2 S3 S4 S12 S14 S15 S16" "$OUT"
expect_absent "…and the approval-pending line is gone" "Step-3 approval pending" "$OUT"

# ---------- 22c: current: 0, 1, 2 all withhold the same way (not just 3) ----------
for S22_CUR in 0 1 2; do
  R22C="$(make_repo "s22-current-$S22_CUR")"; new_roster "$R22C"
  s22_plan_at_current "$R22C" "$S22_CUR" >/dev/null
  poke_pressure "$R22C" 8192 1.0 tick
  expect_absent "current: $S22_CUR also prints no FILL" "poker: FILL" "$OUT"
  expect_contains "…naming current: $S22_CUR by name" \
    "no FILL — plan at current: $S22_CUR, Step-3 approval pending" "$OUT"
done

# ---------- 22d: the approval gate does not mask an unrelated defect (a full budget) ----------
#
# An approved plan with no room on the roster still says the REAL reason (the budget is
# full), never the approval line — this section adds a gate ahead of the existing decisions,
# and a caller reading current: 4 must fall straight through to them, unchanged.
R22D="$(make_repo s22-current-4-full)"; new_roster "$R22D"
s22_plan_at_current "$R22D" 4 >/dev/null
add_row "$R22D" name=w1 deliverable=a.md duration="4 hours" launched_at="$(iso_ago 60)"
add_row "$R22D" name=w2 deliverable=b.md duration="4 hours" launched_at="$(iso_ago 60)"
add_row "$R22D" name=w3 deliverable=c.md duration="4 hours" launched_at="$(iso_ago 60)"
add_row "$R22D" name=w4 deliverable=d.md duration="4 hours" launched_at="$(iso_ago 60)"
add_row "$R22D" name=w5 deliverable=e.md duration="4 hours" launched_at="$(iso_ago 60)"
add_row "$R22D" name=w6 deliverable=f.md duration="4 hours" launched_at="$(iso_ago 60)"
add_row "$R22D" name=w7 deliverable=g.md duration="4 hours" launched_at="$(iso_ago 60)"
add_row "$R22D" name=w8 deliverable=h.md duration="4 hours" launched_at="$(iso_ago 60)"
poke_pressure "$R22D" 8192 1.0 tick
expect_absent "an approved-but-full budget still fills nothing" "poker: FILL" "$OUT"
expect_contains "…and still says the budget is full, not the approval line" \
  "the budget is full" "$OUT"
expect_absent "…never the approval-pending wording" "Step-3 approval pending" "$OUT"

# ---------- 22e/22f: the sub-step letter — the ONE grammar this repo already has ----------
#
# payload/scripts/lib/run.sh's run_open strips a trailing a/b sub-step letter before
# comparing the step number (`local step="${current%[ab]}"`) — `current: 3b` and `current:
# 4b` are recognized, in-repo forms, not malformed values. Before this fix,
# sched_plan_current rejected the letter outright (`*[!0-9]*` matched the trailing `b`),
# which made `3b` UNREADABLE rather than 3 — and an unreadable current: fell straight
# through to the readiness/budget checks below the gate, so a plan sitting at `current: 3b`
# with ready tasks and room on the roster FILLed exactly as `t144-review-b` finding (c)
# and review-a's C-5 describe. `4b` mirrors `4`.
R22E="$(make_repo s22-current-3b)"; new_roster "$R22E"
s22_plan_at_current "$R22E" 3b >/dev/null
poke_pressure "$R22E" 8192 1.0 tick
expect_eq "current: 3b still ticks cleanly (exit 0)" "0" "$RC"
expect_absent "current: 3b is current: 3 with a sub-step letter — no FILL" "poker: FILL" "$OUT"
expect_contains "…and the pending line names the STEP, letter stripped, mirroring run.sh's run_open" \
  "no FILL — plan at current: 3, Step-3 approval pending" "$OUT"

R22F="$(make_repo s22-current-4b)"; new_roster "$R22F"
s22_plan_at_current "$R22F" 4b >/dev/null
poke_pressure "$R22F" 8192 1.0 tick
expect_eq "current: 4b still ticks cleanly (exit 0)" "0" "$RC"
expect_contains "current: 4b is current: 4 with a sub-step letter — fills all eight" \
  "poker: FILL S1 S2 S3 S4 S12 S14 S15 S16" "$OUT"
expect_absent "…and the approval-pending line is gone" "Step-3 approval pending" "$OUT"

# ---------- 22g: current: T1 — task-scale, never a numbered step to gate on ----------
#
# `T<n>` is this repo's OTHER `current:` shape (run_state's task-scale arm: always an open
# run, no numbered close) — used by session/task plans, not wave plans with a Step-3 gate.
# It carries no numbered step to compare against 4, so the approval gate cannot read it as
# either "approved" or "pending" — it WITHHOLDS, unconditionally, rather than falling
# through to the readiness/budget checks and risking a FILL the gate exists to prevent
# (review-a C-5, review-b N-2: this exact shape used to fill).
R22G="$(make_repo s22-current-T1)"; new_roster "$R22G"
s22_plan_at_current "$R22G" T1 >/dev/null
poke_pressure "$R22G" 8192 1.0 tick
expect_eq "current: T1 still ticks cleanly (exit 0)" "0" "$RC"
expect_absent "current: T1 is task-scale, not a numbered step — no FILL" "poker: FILL" "$OUT"
expect_contains "…named as unreadable, not silently swallowed" \
  "no FILL — plan current: unreadable (T1)" "$OUT"
expect_absent "…never the numbered-step pending wording (there is no step number)" \
  "Step-3 approval pending" "$OUT"

# ---------- 22h: no `current:` line at all — unreadable, not DOUBT-then-FILL ----------
#
# A plan carrying an unfenced "## SDLC State" section but no `current:` line inside it —
# section extraction succeeds, the field itself does not exist. Same withholding as T1: the
# gate cannot tell whether Step 3 passed, so it never guesses FILL.
s22_plan_no_current() {  # <repo> -> the path, the 22-fixture shape with no current: line
  local repo="$1"
  local f="$repo/.bionic/docs/plans/epic-21-v1-ladder/wave-01-fixture.plan.md"
  mkdir -p "$(dirname "$f")"
  {
    printf -- '---\n'
    printf 'governing-skill: superpowers:writing-plans\n'
    printf 'parallel-budget: writers=8 suites=4 worktrees=32 test_jobs=8 source=probe\n'
    printf -- '---\n\n# fixture plan (mirrors the observed wave-01 shape, minus current:)\n\n'
    printf '## SDLC State\n\n- Step 3: in progress\n\n'
    printf '## Tasks\n\n'
    printf '%s' "$SP_TASKS_HEADER"
    local id
    for id in S1 S2 S3 S4 S12 S14 S15 S16; do
      printf '| %s | 4 | build | generated | implementor | — | 15m | REQ-x | a.sh | pending |\n' "$id"
    done
  } > "$f"
  touch "$f"
  printf '%s' "$f"
}
R22H="$(make_repo s22-current-missing)"; new_roster "$R22H"
s22_plan_no_current "$R22H" >/dev/null
poke_pressure "$R22H" 8192 1.0 tick
expect_eq "a plan with no current: line still ticks cleanly (exit 0)" "0" "$RC"
expect_absent "no current: line at all — no FILL" "poker: FILL" "$OUT"
expect_contains "…named as unreadable, with an empty value" \
  "no FILL — plan current: unreadable (none)" "$OUT"

# ---------- 22i/22j: THE GATE IS THE APPROVAL, NOT THE STEP (wave-26 T13; D3, AC-6.2) ----------
#
# `current:` is the orchestrator's own word; `approved-by:` is the user's act, and the one fact
# the dispatch wall already keys a writer on. The two are pulled apart here: a plan at
# `current: 4` with no approval line fills nothing, and a plan at `current: 3` that carries one
# fills — the differential that fails if the fill still keys on `current: >= 4`.
R22I="$(make_repo s22-current-4-unapproved)"; new_roster "$R22I"
S22_APPROVAL="" s22_plan_at_current "$R22I" 4 >/dev/null
poke_pressure "$R22I" 8192 1.0 tick
expect_absent "22i AC-6.2 current: 4 with no approved-by: prints no FILL" "poker: FILL" "$OUT"
expect_contains "22i2 …and names the pending approval" "Step-3 approval pending" "$OUT"
R22J="$(make_repo s22-current-3-approved)"; new_roster "$R22J"
S22_APPROVAL="$SP_APPROVED_LINE" s22_plan_at_current "$R22J" 3 >/dev/null
poke_pressure "$R22J" 8192 1.0 tick
expect_contains "22j AC-6.2 current: 3 with approved-by: present fills all eight" \
  "poker: FILL S1 S2 S3 S4 S12 S14 S15 S16" "$OUT"
expect_absent "22j2 …and names no pending approval" "Step-3 approval pending" "$OUT"

# ============================================================
section "Section 23: clean() — list fields survive the 400-char cut (REQ-9, D7)"
# ============================================================
#
# THE BUG (carry-over P2). `clean()`'s trailing `cut -c 1-400` applied to every field it
# rendered, `suites_allowed=` and `files=` included — the two LIST-valued fields (S13's
# suite-allowance wall), where a perfectly ordinary brief overflows 400 characters just by
# naming enough files or suites. The cut then silently dropped suites off the end: a budget
# the wall never agreed to and the operator never asked for. `clean()` now takes the field
# name and skips the cut for exactly these two; every other field, and every caller that
# passes none, keeps the same 400-character cap as before (§23c, below).

R23="$(make_repo s23-long-field)"; new_roster "$R23"
S23_PRED="55555555-aaaa-4bbb-8ccc-000000000023"
S23_LONG="$(printf '%*s' 600 '' | tr ' ' 'x')"
expect_eq "fixture meta: the long value really is 600 characters" "600" \
  "$(printf '%s' "$S23_LONG" | wc -c | tr -d ' ')"

# ---------- 23a: the round trip through `adopt` ----------
add_row_to "$R23" "$S23_PRED" name=long-budget status=identified \
  agent_id=along-budget-2323232323232323 subagent_type=bionic:implementor \
  duration="45 minutes" cadence="10 minutes" \
  deliverable="$R23/.bionic/docs/record/long-budget.md" \
  files="$S23_LONG" suites_allowed="$S23_LONG" suites_source=derived

poke "$R23" adopt
OWN_ROSTER_23="$(roster_of "$R23")"
LONG_ROW="$(grep -F "|name=long-budget|" "$OWN_ROSTER_23" | tail -1)"
expect_contains "23a meta: the row IS adopted (not vacuous)" "|adopted_from=$S23_PRED|" "$LONG_ROW"

# `awk length`, not `wc -c` — `wc -c` counts the trailing newline `grep`'s own output line
# carries, off by one on every call; `awk` strips it before measuring, same as every other
# fixture-length check in this file (`fixture meta` above uses `printf … | wc -c` on a value
# with NO trailing newline of its own, which is why that one call is safe as written).
field_len() {  # <row> <key> -> the character count of key= in a |-delimited row
  printf '%s' "$1" | tr '|' '\n' | grep "^$2=" | head -1 | cut -d= -f2- | awk '{ print length }'
}
expect_eq "a 600-char suites_allowed= reads back whole through adopt" "600" \
  "$(field_len "$LONG_ROW" suites_allowed)"
expect_eq "…and so does a 600-char files=" "600" \
  "$(field_len "$LONG_ROW" files)"

# ---------- 23b: and through the tick's rendering — a later tick does not re-cut it ----------
#
# `tick` never rewrites an adopted row's instrument fields, but this is the case that would
# have caught it if some future change routed them back through an un-fixed `clean()` a
# second time: the SAME roster file, read again after a real tick invocation, still carries
# the whole 600 characters, not a second, silent truncation.
poke "$R23" tick
expect_ne "a tick against this roster does not refuse outright" "2" "$RC"
LONG_ROW_AFTER_TICK="$(grep -F "|name=long-budget|" "$OWN_ROSTER_23" | tail -1)"
expect_eq "…the roster's own copy is still 600 characters after a tick" "600" \
  "$(field_len "$LONG_ROW_AFTER_TICK" suites_allowed)"

# ---------- 23c: existing clean() behaviour is unchanged for an ordinary field (AC-9.2) ----------
#
# The CUT half, specifically — Section 21 already pins the FOLD half (control characters
# and `|` still stripped everywhere, `session=` included). A field that is not one of the
# two list fields still stops at 400 characters, exactly as before this task.
S23_OVERLONG_NAME="$(printf '%*s' 500 '' | tr ' ' 'y')"
add_row_to "$R23" "$S23_PRED" name="$S23_OVERLONG_NAME" status=identified \
  agent_id=aoverlong-name-2323232323232323 subagent_type=bionic:implementor \
  duration="45 minutes" cadence="10 minutes" \
  deliverable="$R23/.bionic/docs/record/overlong-name.md"
poke "$R23" adopt
OVERLONG_ROW="$(grep -F "|deliverable=$R23/.bionic/docs/record/overlong-name.md|" "$OWN_ROSTER_23" | tail -1)"
expect_contains "23c meta: this row too is adopted (not vacuous)" \
  "|adopted_from=$S23_PRED|" "$OVERLONG_ROW"
expect_eq "an ordinary (non-list) field is still cut at 400 characters" "400" \
  "$(field_len "$OVERLONG_ROW" name)"

# ---------- 23d: adopt prints each adopted row's BUDGET beside `launched` (T6, REQ-5, AC-5.1) ----------
#
# THE REPORT (#1): a resumed orchestrator had to read the roster file to learn what a writer
# it just adopted was allowed to run, and the answer it needed to widen a refused suite was
# on the row all along. Both shapes are pinned, and a row carrying only a declared run is
# the AC-5.1 failure shape: its suites cell is empty, so a reader of `suites=` alone would
# call it a row with no budget.
R23D="$(make_repo s23d-budget-line)"; new_roster "$R23D"
S23D_PRED="55555555-aaaa-4bbb-8ccc-00000000023d"
add_row_to "$R23D" "$S23D_PRED" name=budget-both status=identified \
  agent_id=abudget-both-23232323232323d1 subagent_type=bionic:implementor \
  duration="45 minutes" cadence="10 minutes" \
  deliverable="$R23D/.bionic/docs/record/budget-both.md" \
  files=hooks/a.sh suites_allowed="alpha.test.sh beta.test.sh" suites_source=declared \
  re_executes="\`npx jest --testPathPatterns 'x'\`"
add_row_to "$R23D" "$S23D_PRED" name=budget-runs-only status=identified \
  agent_id=abudget-runs-23232323232323d2 subagent_type=bionic:implementor \
  duration="45 minutes" cadence="10 minutes" \
  deliverable="$R23D/.bionic/docs/record/budget-runs-only.md" \
  files=hooks/a.sh suites_allowed= suites_source=declared \
  re_executes="\`pytest tests/unit\`"
add_row_to "$R23D" "$S23D_PRED" name=budget-none status=identified \
  agent_id=abudget-none-23232323232323d3 subagent_type=bionic:implementor \
  duration="45 minutes" cadence="10 minutes" \
  deliverable="$R23D/.bionic/docs/record/budget-none.md" \
  files=hooks/a.sh suites_allowed= suites_source=declared
poke "$R23D" adopt
expect_contains "23d meta: the three rows ARE offered (not vacuous)" "budget-none" "$OUT"
expect_contains "23d a row with suites and a declared run prints both" \
  "  budget      : suites=alpha.test.sh beta.test.sh runs=\`npx jest --testPathPatterns 'x'\`" "$OUT"
expect_contains "23d2 a row with ONLY a declared run still prints a budget line (AC-5.1)" \
  "  budget      : suites=none runs=\`pytest tests/unit\`" "$OUT"
expect_contains "23d3 a row with neither prints the plain 'none'" "  budget      : none" "$OUT"
expect_eq "23d4 …one budget line per adopted row, three rows, three lines" "3" \
  "$(printf '%s\n' "$OUT" | grep -c '^  budget      : ')"

# ============================================================
section "Section 24: sweep — per-session pruning, not all-or-nothing (D5's prune half, T9)"
# ============================================================
#
# THE BUG. `sweep` judged every dead session identically (PID-liveness alone, no age at
# all); the age protection for a session that JUST died lived entirely in the CALLER
# (hooks/session-start.sh's own auto-sweep gate), which could only ask ONE question for the
# WHOLE directory — "is any file anywhere younger than the interval" — and skip calling this
# verb AT ALL when the answer was yes. One freshly-dead session therefore deferred every
# OTHER dead session's cleanup too. `sweep` now asks the age question itself, per session: a
# dead session's OWN newest file decides whether IT sweeps, and nothing about any other one.

R24="$(make_repo s24-sweep)"; new_roster "$R24"
C24="$(fake_config_dir s24)"
S24_REAL_CFG="${CLAUDE_CONFIG_DIR:-}"
export CLAUDE_CONFIG_DIR="$C24"
printf 'poker-interval: 2s\n' > "$R24/.bionic/config.yaml"

S24_AGED="44444444-aaaa-4bbb-8ccc-000000000024"
S24_FRESH="33333333-aaaa-4bbb-8ccc-000000000024"

add_row_to "$R24" "$S24_AGED" name=aged-one status=identified \
  agent_id=aaged-one-2424242424242424 subagent_type=bionic:implementor \
  duration="10 minutes" cadence="10 minutes"
backdate "$(roster_of "$R24" "$S24_AGED")" 10

add_row_to "$R24" "$S24_FRESH" name=fresh-one status=identified \
  agent_id=afresh-one-2424242424242424 subagent_type=bionic:implementor \
  duration="10 minutes" cadence="10 minutes"
# NOT backdated — its mtime is "now", inside the 2-second window. CLOCK DISCIPLINE: the
# window is fixture data (a throwaway .bionic/config.yaml override), never a real sleep.

expect_eq "24 meta: the aged predecessor's file exists before sweep" "yes" \
  "$([ -f "$(roster_of "$R24" "$S24_AGED")" ] && echo yes || echo no)"
expect_eq "24 meta: the fresh predecessor's file exists before sweep" "yes" \
  "$([ -f "$(roster_of "$R24" "$S24_FRESH")" ] && echo yes || echo no)"

poke "$R24" sweep --window
expect_eq "sweep exits 0 — something real was swept" "0" "$RC"

expect_eq "the AGED dead session's file is gone" "no" \
  "$([ -e "$(roster_of "$R24" "$S24_AGED")" ] && echo yes || echo no)"
expect_eq "the FRESH dead session's file is KEPT — deferred, not swept" "yes" \
  "$([ -f "$(roster_of "$R24" "$S24_FRESH")" ] && echo yes || echo no)"
expect_eq "the LIVE session's own roster is never touched" "yes" \
  "$([ -f "$(roster_of "$R24")" ] && echo yes || echo no)"

expect_contains "the aged session is reported swept" "$S24_AGED — dead, 1 file(s)" "$OUT"
expect_contains "the fresh session is named as deferred, individually" \
  "$S24_FRESH — dead, deferred (1 file(s) younger than the 2s window)" "$OUT"
expect_absent "…the fresh session is never reported as removed" \
  "$S24_FRESH — dead, 1 file(s)" "$OUT"
expect_contains "…and the live session is reported kept" "$SID — live, kept" "$OUT"

# `deferred=` is APPENDED after `refused=`, never inserted between the six fields a plain
# `sweep` call has always emitted (AC-9.2's spirit, extended to this line — see the schema
# print's own comment): it is the LAST field, no trailing `|` after it.
expect_contains "the schema line counts one deferred session" "|deferred=1" "$OUT"
expect_contains "…two dead sessions total (the aged one plus the deferred fresh one)" \
  "|dead=2|live=1|" "$OUT"
expect_contains "…exactly one file actually removed" "|removed=1|refused=0|deferred=1" "$OUT"

# The prose summary excludes the deferred session from its dead-session count — it reads
# "1 dead session" (the one actually swept), not "2", and calls the deferral out separately.
expect_contains "the prose summary names only the session actually swept" \
  "swept 1 file(s) across 1 dead session(s)" "$OUT"
expect_contains "…and separately calls out the deferral" \
  "1 dead session(s) deferred — their files are younger than the 2s window." "$OUT"

# ---------- 24b: the SAME session sweeps once it ages past the window ----------
#
# CLOCK DISCIPLINE HOLDS: backdating the file, not waiting out the interval, is what proves
# a session deferred a moment ago sweeps on its own once it qualifies.
backdate "$(roster_of "$R24" "$S24_FRESH")" 10
poke "$R24" sweep --window
expect_eq "the second sweep exits 0" "0" "$RC"
expect_eq "the now-aged FRESH session's file is gone too" "no" \
  "$([ -e "$(roster_of "$R24" "$S24_FRESH")" ] && echo yes || echo no)"
expect_contains "…and its removal is what the second sweep reports" \
  "$S24_FRESH — dead, 1 file(s)" "$OUT"

if [ -n "$S24_REAL_CFG" ]; then export CLAUDE_CONFIG_DIR="$S24_REAL_CFG"; else unset CLAUDE_CONFIG_DIR; fi

# ============================================================
section "Section 25: the duplicate-session tell — machinery, not prose (AC-4.3, T21)"
# ============================================================
#
# THE CLAIM WAS PROSE ONLY. skills/canonical-sdlc/dispatch.md promises: "A listed agent with
# NO ledger row is surfaced as a duplicate-session tell, never silently stopped" — and until
# this section, nothing computed it. Chris, 2026-09-14 (A-orch-29, "Add a test"): the tell
# becomes tick machinery with its own test.
#
# THE QUESTION: for every name THIS session's ListAgents answer calls live, does ANY roster
# under this project's `.bionic/tmp` — not only this session's own — carry a row for it, by
# `name=` or `agent_id=`? A live agent no roster remembers is either another session's
# dispatch (never rostered here) or a resumed copy of a finished one — either way, this is an
# OBSERVATION, never an act: no stop, no roster write, no effect on FILL/QUIET/NOTIFY.
#
# THE FIXTURE SHAPE FOLLOWS SECTION 19's: a transcript carrying a ListAgents answer, planted
# under $S19_CFG exactly as `s19_answer` plants it (CLAUDE_CONFIG_DIR is still pointed there —
# nothing in Section 20 through 24 tore it down permanently, and 24's own restore put it back).
export CLAUDE_CONFIG_DIR="$S19_CFG"

# ---------- 25a: an answer naming an agent absent from every roster -> the tell fires ----------
R25A="$(make_repo s25-orphan)"; new_roster "$R25A"
add_row "$R25A" name=live-writer deliverable=a.md duration="4 hours" launched_at="$(iso_ago 60)"
s19_answer fresh "live-writer:running" "stray-agent:running"
poke_pressure "$R25A" 8192 1.0 tick
expect_contains "a live name on no roster in this project is surfaced" \
  "poker: DUPLICATE-SESSION stray-agent — live here, on no roster of this project (another session's dispatch or a resumed copy); never stop it silently" \
  "$OUT"
expect_eq "…and the tick still exits 0 — an observation, not a refusal" "0" "$RC"

# ---------- 25b: the paired control — a live name WITH a row draws no tell ----------
R25B="$(make_repo s25-rostered)"; new_roster "$R25B"
add_row "$R25B" name=live-writer deliverable=a.md duration="4 hours" launched_at="$(iso_ago 60)"
s19_answer fresh "live-writer:running"
poke_pressure "$R25B" 8192 1.0 tick
expect_absent "a live name WITH a roster row draws no tell (25a discriminates)" \
  "DUPLICATE-SESSION" "$OUT"

# ---------- 25c: the row can be on ANOTHER session's roster, and by agent_id= too ----------
# Two more ways a name can be "ours": adopted onto a predecessor's file (never this session's
# own roster-$SID.state), and matched by the harness's own agent_id= rather than the label the
# dispatching session chose. Both clear the tell.
#
# THIS SESSION'S OWN ROSTER ALSO CARRIES AN OPEN ROW (audit-c19c16e-ac43.md item 4, T25). The
# predecessor's row alone left `roster-$SID.state` header-only, so `OPEN_ROSTER` read 0 and the
# whole tell block — cross-roster glob and `agent_id=` branch both — never ran; both assertions
# below passed for a reason that had nothing to do with either clearing path. `own-live-writer`
# is not named in the ListAgents answer below, so it neither draws a tell of its own nor changes
# which names the loop below considers — it exists only to make `OPEN_ROSTER > 0` true.
R25C="$(make_repo s25-other-roster)"; new_roster "$R25C"
add_row "$R25C" name=own-live-writer deliverable=a.md duration="4 hours" launched_at="$(iso_ago 60)"
S25C_PRED="55555555-aaaa-4bbb-8ccc-0000000025c1"
add_row_to "$R25C" "$S25C_PRED" name=predecessor-writer status=identified \
  agent_id=apredecessor-writer-25c111111111 duration="4 hours" launched_at="$(iso_ago 60)"
s19_answer fresh "predecessor-writer:running" "apredecessor-writer-25c111111111:running"
poke_pressure "$R25C" 8192 1.0 tick
expect_absent "a name on ANOTHER session's roster draws no tell" \
  "DUPLICATE-SESSION predecessor-writer" "$OUT"
expect_absent "…and a name matching agent_id= (not name=) draws no tell either" \
  "DUPLICATE-SESSION apredecessor-writer-25c111111111" "$OUT"

# ---------- 25d: no ListAgents answer at all -> no tell, no refusal, decision unchanged ----------
# AC-4.1: the tick never DEMANDS a ListAgents call. A session that has not made one yet — the
# ordinary first tick — gets exactly today's decision, silently, on this axis. The transcript
# EXISTS (a plain prompt entry) but carries no ListAgents tool_use at all — `s19_answer none`'s
# shape, which is what "no answer" means (distinct from Section 19f2's absent-file case, already
# proven elsewhere).
R25D="$(make_repo s25-no-answer)"; new_roster "$R25D"
add_row "$R25D" name=live-writer deliverable=a.md duration="4 hours" launched_at="$(iso_ago 60)"
s19_answer none
poke_pressure "$R25D" 8192 1.0 tick
expect_absent "no recorded answer at all -> no tell" "DUPLICATE-SESSION" "$OUT"
expect_eq "…and the tick still exits 0, not a refusal" "0" "$RC"
expect_contains "…and the ordinary decision is unchanged (open=1, no live set consulted)" \
  "|open=1" "$OUT"

# ---------- 25e: a STALE answer still names a live agent on no roster (review Q2) ----------
# hooks/session-poker.sh:3124 documents the asymmetry: "a STALE answer still names a real —
# if possibly outdated — live set worth surfacing." The trim above falls back to the roster
# count on stale (Section 19e), but the tell is a DIFFERENT read of the same cached set
# (`TICK_DUP_SET="$_LA_CACHE_OUT"`, populated whether `_la_ensure` returns fresh or stale) —
# so staleness silences the FILL arithmetic without silencing this observation. Before this
# case, Section 25 drove `s19_answer fresh` (25a-25c) and `s19_answer none` (25d) only; a
# change narrowing the tell to fresh-only left every existing assertion here green.
R25E="$(make_repo s25-stale)"; new_roster "$R25E"
add_row "$R25E" name=live-writer deliverable=a.md duration="4 hours" launched_at="$(iso_ago 60)"
s19_answer stale "stray-agent:running"
poke_pressure "$R25E" 8192 1.0 tick
expect_contains "a STALE answer's live name on no roster is still surfaced" \
  "poker: DUPLICATE-SESSION stray-agent — live here, on no roster of this project (another session's dispatch or a resumed copy); never stop it silently" \
  "$OUT"
expect_eq "…and the tick still exits 0 — an observation, not a refusal" "0" "$RC"

# ---------- 25f: a `duplicate-start` row is NAMED on the tick (T22 row (d), review C2) ----
# hooks/execution-recorder.sh journals `status=duplicate-start` when one agent id starts a
# second time — the fallback accepted BECAUSE a SubagentStart hook cannot block (A-T22.4),
# whose whole point is that somebody sees it. Until this case nothing read the field: the
# DUPLICATE-SESSION tell above asks a different question (a live name NO roster carries),
# and a duplicate start is carried by name AND by agent_id, so that tell is silent on it.
#
# ROSTER-ONLY, LIKE THE ROW ITSELF. No ListAgents answer is planted (`none`), because the
# fact is on disk and a tell that needed a live set would go quiet in exactly the degraded
# session — one that just lost its agent table across a `/clear` — that produces the row.
R25F="$(make_repo s25-dupstart)"; new_roster "$R25F"
add_row "$R25F" name=live-writer deliverable=a.md duration="4 hours" launched_at="$(iso_ago 60)"
add_row "$R25F" name=twinned status=identified agent_id=atwinned-2525252525252525 \
  deliverable=b.md duration="4 hours" launched_at="$(iso_ago 60)"
add_row "$R25F" name=twinned status=duplicate-start agent_id=atwinned-2525252525252525 \
  deliverable=b.md duration="4 hours" launched_at="$(iso_ago 60)"
s19_answer none
poke_pressure "$R25F" 8192 1.0 tick
expect_contains "a duplicate-start row is named on the tick" \
  "poker: DUPLICATE-START twinned — a second start under an id that already has a live row; the dispatch wall is the door that closes" \
  "$OUT"
expect_eq "…and the tick still exits 0 — an observation, not a refusal" "0" "$RC"

# ---------- 25g: the paired control — the same roster without the row draws no tell -------
# `twinned` keeps its `identified` row and loses only the `duplicate-start` one. A tell that
# fired on any second row of a name, or on the mere presence of a name twice, would pass 25f
# and fail here.
R25G="$(make_repo s25-no-dupstart)"; new_roster "$R25G"
add_row "$R25G" name=live-writer deliverable=a.md duration="4 hours" launched_at="$(iso_ago 60)"
add_row "$R25G" name=twinned status=identified agent_id=atwinned-2525252525252525 \
  deliverable=b.md duration="4 hours" launched_at="$(iso_ago 60)"
s19_answer none
poke_pressure "$R25G" 8192 1.0 tick
expect_absent "no duplicate-start row, no tell (25f discriminates)" "DUPLICATE-START" "$OUT"

# ============================================================
section "Section 26: the Patrol closes a moot row — the ack it writes itself (AC-1.3; T1, D2)"
# ============================================================
#
# THE DEFECT, from the 1.7.1 close-out. Two kinds of row survive every sweep and are named on
# every tick for the life of the session, forever, with nothing anybody can do about them
# except type an `ack` by hand:
#
#   AN ADOPTED MET ROW. `adopt_fold` excludes any name carrying a MET marker, so an adopted
#   row never arrives with one; the Stop-sweep skips every teammate row that is not already
#   UNMET; and the adopted agent's own SubagentStop belongs to the session that launched it,
#   not to this one. Nothing will ever write `landing-swept/v1` for it. Its contract reads MET
#   off the disk, it is unswept, and so it was named for a stop on every tick.
#
#   A `duplicate-start` ROW. hooks/execution-recorder.sh journals one when an id starts a
#   second time; the reader applied no ack filter, no swept filter and no liveness test, and
#   the roster is append-only — so the tell repeated for the life of the session too.
#
# THE RULE (D2). The Patrol may CLOSE a row when the world shows it moot: the contract is MET
# (or the row is a duplicate start) AND the panel no longer lists the agent. It closes it the
# way a human would — through the one ack verb — and the ledger line says who closed it and
# on what evidence: `by=patrol|reason=moot-and-gone`. There is nothing to stand down, so
# nothing is printed; the acted-on fact is the ledger, and the row is closed for every reader.
#
# WHAT IT MAY NOT DO is close a row on no evidence. With no answer at all the panel is
# UNKNOWN — not empty — and the tick neither stands the row down nor acks it (26e).

ack_ledger_of() { printf '%s/.bionic/tmp/sweeper-%s.state' "$1" "${2:-$SID}"; }

# ---------- 26a: an ADOPTED MET row whose agent the panel no longer lists ----------
#
# The row is adopted through the REAL verb off a predecessor's roster, because "adopted" is
# exactly the state no sweep will ever mark and a hand-written row carrying `adopted_from=`
# would be this suite's idea of the shape rather than the writer's.
PRED_26="d6d6d6d6-1111-4bbb-8ccc-000000000026"
ID_26="agone-writer-26262626262626"
R26A="$(make_repo s26-adopted-met)"; new_roster "$R26A"
DEL_26A="$R26A/delivered-26a.md"; echo "done" > "$DEL_26A"
add_row_to "$R26A" "$PRED_26" name=gone-writer status=identified agent_id="$ID_26" \
  subagent_type=bionic:implementor deliverable="$DEL_26A" duration="45 minutes" \
  cadence="10 minutes" "$(said "$R26A" gone-writer)"
poke "$R26A" adopt
expect_contains "26a meta: the fixture row really was adopted onto this session's roster" \
  "adopted_from=" "$(grep -F "|name=gone-writer|" "$(roster_of "$R26A")" | tail -1)"
expect_absent "26a meta: …and no sweep has ever marked it" "landing-swept/v1" \
  "$(cat "$(roster_of "$R26A")")"

s19_answer fresh "some-other-agent:running"
poke "$R26A" tick
expect_eq "26a the tick still exits 0 — closing a moot row is not a refusal" "0" "$RC"
# RE-AUTHORED at wave-19 T1 (D2): the row declared a deliverable and met it, so the close
# says `landed`; `moot-and-gone` is kept for a row that declared nothing (§33c) and for a
# duplicate start (26c).
expect_contains "26a an adopted MET row whose agent is gone is acked by the Patrol, reason landed" \
  "|name=gone-writer|by=patrol|reason=landed" \
  "$(cat "$(ack_ledger_of "$R26A")" 2>/dev/null)"
expect_contains "26a2 …through the real ack verb, on the schema its one reader reads" \
  "sweeper-ledger/v1|event=ack|" "$(cat "$(ack_ledger_of "$R26A")" 2>/dev/null)"
expect_absent "26a3 …and nothing is stood down: there is nobody left to stop" \
  "STANDDOWN" "$OUT"

# ---------- 26b: the second tick is SILENT, and acks nothing twice ----------
poke "$R26A" tick
expect_absent "26b the second tick names the closed row for no stop" "STANDDOWN gone-writer" "$OUT"
expect_absent "26b2 …nor under the retired tell" "TASKSTOP" "$OUT"
expect_eq "26b3 …and the row is acked exactly once, not once per tick" "1" \
  "$(grep -c '|event=ack|' "$(ack_ledger_of "$R26A")" 2>/dev/null | tr -d ' ')"

# ---------- 26c: a duplicate-start row whose agent the panel no longer lists ----------
#
# The tell still fires on the tick that finds it — the fact is new to this reader — and the
# SAME tick closes the row, so the session is told once instead of every ten minutes.
R26C="$(make_repo s26-dupstart-gone)"; new_roster "$R26C"
add_row "$R26C" name=twinned status=identified agent_id=atwinned-2626262626262626 \
  deliverable="$R26C/never-written.md" duration="4 hours" launched_at="$(iso_ago 60)"
add_row "$R26C" name=twinned status=duplicate-start agent_id=atwinned-2626262626262626 \
  deliverable="$R26C/never-written.md" duration="4 hours" launched_at="$(iso_ago 60)"
s19_answer fresh "some-other-agent:running"
poke "$R26C" tick
expect_contains "26c the duplicate-start tell still fires on the tick that finds it" \
  "poker: DUPLICATE-START twinned" "$OUT"
expect_contains "26c2 …and the same tick closes the row, on the evidence that it is moot" \
  "|name=twinned|by=patrol|reason=moot-and-gone" \
  "$(cat "$(ack_ledger_of "$R26C")" 2>/dev/null)"

poke "$R26C" tick
expect_absent "26c3 the second tick repeats neither the tell…" "DUPLICATE-START" "$OUT"
expect_eq "26c4 …nor the ack" "1" \
  "$(grep -c '|event=ack|' "$(ack_ledger_of "$R26C")" 2>/dev/null | tr -d ' ')"

# ---------- 26d: the panel STILL lists it — nothing is closed ----------
#
# The discriminator for both arms above. A row whose agent is still there is the stand-down
# case, never the ack case: closing it would throw away the contract while its author is
# still working, which is the one thing an ack can never be taken back from.
R26D="$(make_repo s26-dupstart-live)"; new_roster "$R26D"
add_row "$R26D" name=twinned status=identified agent_id=atwinned-2d2d2d2d2d2d2d2d \
  deliverable="$R26D/never-written.md" duration="4 hours" launched_at="$(iso_ago 60)"
add_row "$R26D" name=twinned status=duplicate-start agent_id=atwinned-2d2d2d2d2d2d2d2d \
  deliverable="$R26D/never-written.md" duration="4 hours" launched_at="$(iso_ago 60)"
s19_answer fresh "twinned:running"
poke "$R26D" tick
expect_contains "26d a live duplicate-start row is still told about" \
  "poker: DUPLICATE-START twinned" "$OUT"
expect_eq "26d2 …and nothing acks it while its agent is still on the panel" "no" \
  "$([ -f "$(ack_ledger_of "$R26D")" ] && echo yes || echo no)"

# ---------- 26e: NO answer is not an empty panel ----------
#
# `none` means the transcript carries no ListAgents answer at all — the state of every
# session before its first one, and of any session whose panel scrolled out of the window.
# An unknown panel is not evidence that anybody is gone, so the tick does neither thing.
R26E="$(make_repo s26-no-answer)"; new_roster "$R26E"; armed_ago "$R26E"; delivered_plan "$R26E"
DEL_26E="$R26E/delivered-26e.md"; echo "done" > "$DEL_26E"
add_row "$R26E" name=done-writer deliverable="$DEL_26E" duration="1 minute" \
  launched_at="$(iso_ago 600)" "$(said "$R26E" done-writer)"
s19_answer none
poke "$R26E" tick
expect_eq "26e a tick with no panel answer still exits 0" "0" "$RC"
expect_absent "26e2 …stands nothing down on an answer it does not have" "STANDDOWN" "$OUT"
expect_eq "26e3 …and closes nothing on it either" "no" \
  "$([ -f "$(ack_ledger_of "$R26E")" ] && echo yes || echo no)"


# ============================================================
section "Section 27: the tick's VERDICT — cadence liveness, the FILL band, notes, decision last (REQ-10; D5, D9)"
# ============================================================
#
# FOUR DEFECTS, ONE LINE. The tick decided from `duration=` alone while its own prompt
# promised a reading against the contracted `cadence=` (B5); `poker: FILL` printed as a side
# channel on a tick whose decision line said QUIET (B6); a standing worktree whose row was
# discharged — a FACT, not an alarm — took the NOTIFY band (B4); and two unactionable
# advisories printed BELOW the decision, so the last thing an operator read was not the
# answer (B7, seed A 8e). D5 makes `decision=` the ranked maximum DISARM > NOTIFY > FILL >
# QUIET with `fill=` and `trees=` beside it, D9 gives liveness to the library's one
# predicate — `observe_class`, payload/scripts/lib/observe.sh — and the decision line is the
# last line a tick prints.
#
# THE WINDOW IS ONE CADENCE, and it is the library's (D9). `adopt` used to multiply a
# cadence by PATROL_STALE_MULTIPLIER and the tick measured nothing at all; both ask
# `observe_class` now, so the fleet has two staleness arithmetics (stamp vs fire window, row
# vs cadence) where it had four.

# STDOUT ALONE, because "the decision line is the LAST line" is a claim about the machine
# channel. `poke` merges stderr into OUT, which is right for every other case in this file
# and cannot answer this one: a `die` WARN on stderr would read as the last line.
S27_OUT=""; S27_ERR=""
poke_split() {  # <repo> <args...> -> sets S27_OUT (stdout), S27_ERR (stderr), RC
  local repo="$1"; shift
  case "${1:-}" in tick|fill-report) [ "${POKE_UNBOUND:-0}" = 1 ] || poke_bind "$repo" ;; esac
  ( cd "$repo" && exec env CLAUDE_CODE_SESSION_ID="$SID" bash "$POKER" "$@" ) \
    > "$TMPROOT/s27.out" 2> "$TMPROOT/s27.err"
  RC=$?
  S27_OUT="$(cat "$TMPROOT/s27.out")"; S27_ERR="$(cat "$TMPROOT/s27.err")"
}

last_line() { printf '%s\n' "$1" | tail -1; }

# The mtime the tick is supposed to PRINT, read the way the hook reads it (epoch_iso over
# stat) — never a literal, so the assertion cannot drift from the file it describes.
iso_of_mtime() {  # <file> -> UTC ISO-8601 of its mtime
  local e
  e="$(stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null)"
  date -u -r "$e" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$e" +%Y-%m-%dT%H:%M:%SZ
}

require_helpers poke_split last_line iso_of_mtime

# ---------- 27a: a row quieter than ONE cadence NOTIFIES, and names the mtime it read ----
#
# THE SEED'S OWN SHAPE (B5, 20:40Z): `cadence=15 min`, a progress artifact 35 minutes old,
# and a duration nowhere near exceeded — the tick read QUIET and said "none past their
# declared duration", which was true about what it measured and silent about the agent that
# had stopped writing.
R27A="$(make_repo s27-cadence)"; new_roster "$R27A"
mkdir -p "$R27A/.bionic/docs/record"
P27A="$R27A/.bionic/tmp/progress-quiet.md"
printf 'progress\n' > "$P27A"
backdate "$P27A" 2100                                  # 35 minutes
add_row "$R27A" name=quiet-writer status=identified agent_id=aquiet-one-2700000000000001 \
  deliverable="$R27A/.bionic/docs/record/quiet.md" duration="4 hours" \
  launched_at="$(iso_ago 300)" cadence="15 minutes" progress="$P27A"
s19_answer none
poke "$R27A" tick
expect_contains "27a a row quieter than its declared cadence takes the NOTIFY band" \
  "decision=NOTIFY" "$OUT"
expect_eq "27a2 …and the tick exits 1, the band the Patrol's prompt reads" "1" "$RC"
expect_contains "27a3 …naming the row" "rows=quiet-writer" "$OUT"
expect_contains "27a4 …the cadence it was measured against" "cadence 900s" "$OUT"
expect_contains "27a5 …and the MTIME it read, not merely an age" \
  "$(iso_of_mtime "$P27A")" "$OUT"
expect_contains "27a6 …with the channel it read it from" "$P27A" "$OUT"
expect_absent "27a7 …and it is not the duration arm speaking: nothing is past its duration" \
  "past declared duration" "$OUT"

# ---------- 27b: THE CONTROL — the same row inside its cadence is QUIET ----------
#
# Byte for byte 27a's fixture with one number moved: the progress file is two minutes old
# instead of thirty-five. Without this, 27a passes against a tick that notifies every row.
R27B="$(make_repo s27-cadence-fresh)"; new_roster "$R27B"
mkdir -p "$R27B/.bionic/docs/record"
P27B="$R27B/.bionic/tmp/progress-live.md"
printf 'progress\n' > "$P27B"
backdate "$P27B" 120
add_row "$R27B" name=live-writer status=identified agent_id=alive-one-27000000000000002 \
  deliverable="$R27B/.bionic/docs/record/live.md" duration="4 hours" \
  launched_at="$(iso_ago 300)" cadence="15 minutes" progress="$P27B"
s19_answer none
poke "$R27B" tick
expect_contains "27b a row that wrote inside its cadence is QUIET" "decision=QUIET" "$OUT"
expect_eq "27b2 …exit 0" "0" "$RC"
expect_absent "27b3 …and is never named on a NOTIFY" "rows=live-writer" "$OUT"

# ---------- 27c: THE TRANSCRIPT IS THE SECOND CHANNEL, exactly as adopt reads it ----------
#
# A progress artifact is a promise an agent keeps by hand; the transcript is the harness's
# own record of a turn taken. `observe_class` reads either, so a row whose progress file
# went stale while its agent kept working is ALIVE — the asymmetry that keeps this arm from
# notifying the busiest writer on the roster.
R27C="$(make_repo s27-transcript)"; new_roster "$R27C"
mkdir -p "$R27C/.bionic/docs/record" "$S19_CFG/projects/-fixture-project/$SID/subagents"
P27C="$R27C/.bionic/tmp/progress-stale.md"
printf 'progress\n' > "$P27C"
backdate "$P27C" 3000
ID27C="atx-one-270000000000000000003"
TX27C="$S19_CFG/projects/-fixture-project/$SID/subagents/agent-$ID27C.jsonl"
: > "$TX27C"                                            # written just now
add_row "$R27C" name=tx-writer status=identified agent_id="$ID27C" \
  deliverable="$R27C/.bionic/docs/record/tx.md" duration="4 hours" \
  launched_at="$(iso_ago 300)" cadence="15 minutes" progress="$P27C"
s19_answer none
poke "$R27C" tick
expect_contains "27c a stale progress file with a FRESH transcript is still QUIET" \
  "decision=QUIET" "$OUT"
expect_absent "27c2 …and the row is not named" "rows=tx-writer" "$OUT"
# …and the same row with BOTH channels stale notifies, which is what makes the pair honest.
# The transcript is the NEWER of the two (2100s against the progress file's 3000s), because
# "last heard from" is the later channel and that is the one the line has to name: the row is
# quiet only when both are, so the newest is what the verdict rests on.
backdate "$TX27C" 2100
poke "$R27C" tick
expect_contains "27c3 …while both channels stale takes the NOTIFY band" "decision=NOTIFY" "$OUT"
expect_contains "27c4 …naming the transcript it read" "$TX27C" "$OUT"

# ---------- 27d: a row with NO readable channel is not notified for silence ----------
#
# There is no mtime to print, so there is nothing observed to report: the duration arm still
# answers for such a row and this one says nothing. A NOTIFY naming no evidence is the noise
# the cadence read exists to replace.
R27D="$(make_repo s27-no-channel)"; new_roster "$R27D"
mkdir -p "$R27D/.bionic/docs/record"
add_row "$R27D" name=mute-writer status=identified agent_id=amute-one-2700000000000004 \
  deliverable="$R27D/.bionic/docs/record/mute.md" duration="4 hours" \
  launched_at="$(iso_ago 300)" cadence="15 minutes"
s19_answer none
poke "$R27D" tick
expect_contains "27d a row that declared no progress artifact and has no transcript is QUIET" \
  "decision=QUIET" "$OUT"
expect_absent "27d2 …and is not named on a NOTIFY" "rows=mute-writer" "$OUT"

# ---------- 27e: FILL IS A DECISION, and it rides the decision line ----------
#
# B6, 19:00:46Z: `poker: FILL T13` printed and the line beneath it read `decision=QUIET`.
# The duty wall (payload/scripts/lib/stop.sh) reads the PRINTED line and is unchanged; what
# changes is that a tick that ordered work no longer reports nothing was wanted.
R27E="$(make_repo s27-fill)"; new_roster "$R27E"
wave_plan "$R27E" "writers=8 suites=4 worktrees=32 test_jobs=8 source=probe" \
  "| T13 | 4 | build | fixture task | implementor | — | 15m | REQ-x | a.sh | pending |"
s19_answer none
poke_pressure "$R27E" 8192 1.0 tick
expect_contains "27e the FILL line the duty wall reads is unchanged" "poker: FILL T13" "$OUT"
expect_contains "27e2 …and the decision line carries the band" "decision=FILL" "$OUT"
expect_contains "27e3 …with the ids in their own field" "|fill=T13" "$OUT"
expect_absent "27e4 …never QUIET on a tick that ordered work" "decision=QUIET" "$OUT"
expect_eq "27e5 …and FILL is not the exit-1 band: NOTIFY alone is" "0" "$RC"

# ---------- 27f: THE RANK — NOTIFY outranks FILL, and the fill is still reported ----------
#
# Both facts are true on one tick: a row is overdue AND the budget has room. The band is the
# higher of the two and nothing the tick learned is dropped, which is the whole content of
# "ranked maximum" as against "first arm wins".
R27F="$(make_repo s27-rank)"; new_roster "$R27F"
mkdir -p "$R27F/.bionic/docs/record"
wave_plan "$R27F" "writers=8 suites=4 worktrees=32 test_jobs=8 source=probe" \
  "| T13 | 4 | build | fixture task | implementor | — | 15m | REQ-x | a.sh | pending |"
add_row "$R27F" name=overdue-writer status=identified agent_id=aover-one-27000000000000005 \
  deliverable="$R27F/.bionic/docs/record/over.md" duration="1 minute" \
  launched_at="$(iso_ago 3600)"
s19_answer none
poke_pressure "$R27F" 8192 1.0 tick
expect_contains "27f an overdue row and a fillable gap on one tick: NOTIFY wins the band" \
  "decision=NOTIFY" "$OUT"
expect_contains "27f2 …and the fill it ordered is still on the line" "|fill=T13" "$OUT"
expect_contains "27f3 …with the FILL line itself still printed for the duty wall" \
  "poker: FILL T13" "$OUT"
expect_eq "27f4 …exit 1, the NOTIFY band" "1" "$RC"

# ---------- 27g: THE ADVISORIES ARE NOTES, AND THE DECISION IS LAST ----------
#
# The stale-panel deferral and the no-budget line are both true and unactionable, and both
# printed below the decision. A `poker: note:` above the decision line is what a fact gets;
# the decision line is the tick's last word.
R27G="$(make_repo s27-order)"; new_roster "$R27G"
mkdir -p "$R27G/.bionic/docs/record"
write_plan "$R27G" "$(plan_body 4 'in progress')"        # a plan with NO parallel-budget
DEL27G="$R27G/.bionic/docs/record/met.md"; printf 'done\n' > "$DEL27G"
add_row "$R27G" name=met-writer status=identified agent_id=amet-one-270000000000000006 \
  deliverable="$DEL27G" duration="4 hours" launched_at="$(iso_ago 600)"
add_row "$R27G" name=open-writer status=identified agent_id=aopen-one-27000000000000007 \
  deliverable="$R27G/.bionic/docs/record/open.md" duration="4 hours" launched_at="$(iso_ago 60)"
s19_answer stale "open-writer:running"
poke_split "$R27G" tick
expect_contains "27g the stale-panel deferral prints as a note" \
  "poker: note: stand-down deferred" "$S27_OUT"
expect_contains "27g2 …the missing budget prints as a note" \
  "poker: note: no FILL —" "$S27_OUT"
expect_contains "27g3 …and names the key it could not read, as Step 0 writes it" \
  "parallel-budget: writers=" "$S27_OUT"
expect_absent "27g3b …and no longer calls the budget an opt-in (wave-19 REQ-3, ADR-035)" \
  "opts into" "$S27_OUT"
expect_eq "27g4 the LAST stdout line is the decision line" "poker-tick/v1" \
  "$(printf '%s' "$(last_line "$S27_OUT")" | cut -d'|' -f1)"
expect_contains "27g5 …and that line is QUIET, the band the facts leave" "decision=QUIET" \
  "$(last_line "$S27_OUT")"

# ---------- 27h: every band's decision line is last, NOTIFY and DISARM included ----------
#
# One arm printing its sentence beneath the machine line is all it takes for a reader to
# have to know which arm answered, so the rule is asserted per band rather than once.
poke_split "$R27A" tick
expect_eq "27h a NOTIFY tick ends on its decision line" "poker-tick/v1" \
  "$(printf '%s' "$(last_line "$S27_OUT")" | cut -d'|' -f1)"
expect_contains "27h2 …and the sentence that explains it printed above" \
  "poker: NOTIFY" "$S27_OUT"

R27I="$(make_repo s27-disarm)"; new_roster "$R27I"; armed_ago "$R27I"; delivered_plan "$R27I"
s19_answer none
poke_split "$R27I" tick
expect_contains "27i a delivered run still DISARMs" "decision=DISARM" "$S27_OUT"
expect_eq "27i2 …and that line is its last" "poker-tick/v1" \
  "$(printf '%s' "$(last_line "$S27_OUT")" | cut -d'|' -f1)"

R27J="$(make_repo s27-armed-empty)"; armed_ago "$R27J"
s19_answer none
poke_split "$R27J" tick
expect_contains "27j an armed session with nothing dispatched is QUIET" "decision=QUIET" "$S27_OUT"
expect_eq "27j2 …and ends on the decision line too" "poker-tick/v1" \
  "$(printf '%s' "$(last_line "$S27_OUT")" | cut -d'|' -f1)"

# ---------- 27k: a live claimed process silences the cadence NOTIFY (T6, REQ-7, AC-7.3) ----------
#
# THE REPORT (#7): a writer waiting on a CI run (`gh run watch`) wrote nothing for 26 minutes
# and drew "quieter than the declared cadence". The machine already treats a live claimed
# process as work (triage-B §6.2) and the docs said otherwise; nothing pinned the composition.
# The driver is triage-B §6.2's: one UNMET row, deliverable absent, cadence 10 minutes, the
# transcript backdated 1563 s, a fresh ListAgents answer showing it running, and a stand-in
# watcher whose COMMAND LINE carries the claimed pattern (`pgrep -f` reads command lines).
# Beside it the SAME fixture with the claim DEAD must NOTIFY, so QUIET is the claim speaking.
S27K_PAT="gh-run-watch-27k-$$"
S27K_ID="apurge-27k-0000000000000006"
s27k_repo() {  # <label> <claim pattern> -> a repo carrying the 6.2 row
  local r; r="$(make_repo "$1")"; new_roster "$r"
  add_row "$r" name=s-purge-ledger status=identified agent_id="$S27K_ID" \
    deliverable="$r/.bionic/docs/record/s-purge-ledger.md" duration="4 hours" \
    launched_at="$(iso_ago 3000)" cadence="10 minutes" claims="$2"
  mkdir -p "$S19_CFG/projects/-fixture-project/$SID/subagents"
  printf '{"type":"user","message":{"role":"user","content":"go"}}\n' \
    > "$S19_CFG/projects/-fixture-project/$SID/subagents/agent-$S27K_ID.jsonl"
  backdate "$S19_CFG/projects/-fixture-project/$SID/subagents/agent-$S27K_ID.jsonl" 1563
  printf '%s' "$r"
}
( exec -a "$S27K_PAT" sleep 120 ) &
S27K_PID=$!
R27K="$(s27k_repo s27-live-claim "$S27K_PAT")"
s19_answer fresh "s-purge-ledger:running"
poke "$R27K" tick
expect_contains "27k an undelivered, quiet row whose claimed process is LIVE ticks QUIET" \
  "decision=QUIET" "$OUT"
expect_absent "27k2 …and never draws the cadence NOTIFY" "quieter than the declared cadence" "$OUT"
kill "$S27K_PID" 2>/dev/null; wait "$S27K_PID" 2>/dev/null
R27KD="$(s27k_repo s27-dead-claim "$S27K_PAT")"
s19_answer fresh "s-purge-ledger:running"
poke "$R27KD" tick
expect_contains "27k3 CONTROL: the same row with the claim DEAD takes the NOTIFY band" \
  "decision=NOTIFY" "$OUT"
expect_contains "27k4 …naming the quiet row, so 27k's QUIET was the claim and not a blind tick" \
  "s-purge-ledger" "$OUT"

# ============================================================
section "Section 28: adopt offers only OPEN runs' rows, once each (REQ-9; D10)"
# ============================================================
#
# THE DEFECT (B8, measured 2026-09-19). `adopt` walked every `roster-*.state` in the project
# and offered every row no marker and no ack had closed — with no reading of whether the run
# that dispatched it is still open, and none of whether the session that launched it is dead
# and its files already sweepable. A roster left behind by a released wave was therefore
# offered on every resume, forever, and an agent adopted N times appeared N times, once per
# roster that had adopted it.
#
# CLOSURE IS DERIVED, NEVER STORED (spec §1): a row's run is closed when `run_open` says so
# of its own `plan=`, and a session is dead when the dead-session walk names it AND its state
# files are older than the window the sweep defers inside. Both are questions this verb can
# ask cheaply; neither is a new field.
#
# THE PARTITION IS `closed`, and it is listed NOWHERE — not adopted, not shown, counted on
# the summary line so the drop is visible rather than silent.

# A predecessor session id per case: the walk is over filenames, so two cases sharing one id
# would share a roster.
S28_A="aaaa0000-28aa-4bbb-8ccc-000000000001"
S28_B="bbbb0000-28bb-4bbb-8ccc-000000000002"

# The `closed=` / `dupes=` counters off the summary line, by key.
s28_field() {  # <output> <key> -> the value on the poker-adopt summary line
  printf '%s\n' "$1" | /usr/bin/grep '^poker-adopt/v1|' | /usr/bin/grep '|scanned=' \
    | tail -1 | tr '|' '\n' | /usr/bin/grep "^$2=" | head -1 | cut -d= -f2-
}
require_helpers s28_field

# ---------- 28a: a row whose `plan=` run is CLOSED is offered nowhere ----------
#
# The in-house repro: the 1.8.2 session's roster folds to one open row whose plan is a
# delivered wave. `run_open` reads that plan and says closed; the row is residue, not work.
R28A="$(make_repo s28-closed-run)"; new_roster "$R28A"
mkdir -p "$R28A/.bionic/docs/record"
P28A_CLOSED="$(plan_at "$R28A" 'epic-28/wave-closed.plan.md' \
  "$(plan_body 9 'delivered: bionic 9.9.9; report: record/fixture/close-out.md')")"
add_row_to "$R28A" "$S28_A" name=closed-run-writer status=identified \
  agent_id=aclosed-run-2800000000000001 subagent_type=bionic:implementor \
  duration="45 minutes" cadence="10 minutes" plan="$P28A_CLOSED" \
  deliverable="$R28A/.bionic/docs/record/closed-run.md"
poke "$R28A" adopt
expect_absent "28a a row whose run is closed is not listed at all" "closed-run-writer" "$OUT"
expect_eq "28a2 …and the summary counts it closed" "1" "$(s28_field "$OUT" closed)"
expect_eq "28a3 …with nothing open to adopt" "0" "$(s28_field "$OUT" open)"
expect_contains "28a4 …so the verb says there is nothing to adopt" "nothing to adopt" "$OUT"
expect_eq "28a5 …and nothing was written to this session's roster" "0" \
  "$(/usr/bin/grep -c 'source=adopted' "$(roster_of "$R28A")" || true)"

# ---------- 28b: THE PAIRED POSITIVE — the same row under an OPEN run is adopted ----------
#
# One field moves: the plan the row names is at `current: 4` instead of delivered. Without
# this, 28a passes against a verb that offers nothing at all.
R28B="$(make_repo s28-open-run)"; new_roster "$R28B"
mkdir -p "$R28B/.bionic/docs/record"
P28B_OPEN="$(plan_at "$R28B" 'epic-28/wave-open.plan.md' "$(plan_body 4 'in progress')")"
add_row_to "$R28B" "$S28_A" name=open-run-writer status=identified \
  agent_id=aopen-run-28000000000000001 subagent_type=bionic:implementor \
  duration="45 minutes" cadence="10 minutes" plan="$P28B_OPEN" \
  deliverable="$R28B/.bionic/docs/record/open-run.md"
poke "$R28B" adopt
expect_contains "28b a row whose run is still open is offered" "open-run-writer" "$OUT"
expect_eq "28b2 …counted open" "1" "$(s28_field "$OUT" open)"
expect_eq "28b3 …and nothing is closed" "0" "$(s28_field "$OUT" closed)"
expect_eq "28b4 …and the row lands on this session's roster" "1" \
  "$(/usr/bin/grep -c '|name=open-run-writer|' "$(roster_of "$R28B")" || true)"

# ---------- 28c: a DEAD session whose files the sweep would take is offered nowhere ------
#
# The other half of closure, and the one that makes `adopt` agree with `sweep`: a session no
# process answers for, whose newest state file is older than the poker interval, is a session
# the next SessionStart deletes. Offering its rows hands the operator work that is about to
# vanish.
R28C="$(make_repo s28-dead-sweepable)"; new_roster "$R28C"
mkdir -p "$R28C/.bionic/docs/record"
add_row_to "$R28C" "$S28_B" name=dead-session-writer status=identified \
  agent_id=adead-one-280000000000000001 subagent_type=bionic:implementor \
  duration="45 minutes" cadence="10 minutes" \
  deliverable="$R28C/.bionic/docs/record/dead.md"
backdate "$(roster_of "$R28C" "$S28_B")" 4000            # past the 1200s default window
poke "$R28C" adopt
expect_absent "28c a dead session's sweepable row is not listed" "dead-session-writer" "$OUT"
expect_eq "28c2 …and the summary counts it closed" "1" "$(s28_field "$OUT" closed)"

# ---------- 28d: THE PAIRED POSITIVE — a dead session's YOUNG row is still adopted -------
#
# This is the case `adopt` exists for. A `/clear` leaves the predecessor id dead within
# seconds, and its roster is the freshest file in the directory; the sweep defers exactly
# that session, so the verb must too. The fixture is 28c with the mtime left alone.
R28D="$(make_repo s28-dead-young)"; new_roster "$R28D"
mkdir -p "$R28D/.bionic/docs/record"
add_row_to "$R28D" "$S28_B" name=fresh-corpse-writer status=identified \
  agent_id=afresh-one-28000000000000001 subagent_type=bionic:implementor \
  duration="45 minutes" cadence="10 minutes" \
  deliverable="$R28D/.bionic/docs/record/fresh.md"
poke "$R28D" adopt
expect_contains "28d a just-dead session's row is still offered" "fresh-corpse-writer" "$OUT"
expect_eq "28d2 …and nothing is counted closed" "0" "$(s28_field "$OUT" closed)"

# ---------- 28e: ONE AGENT ID APPEARS ONCE ----------
#
# Adoption files a copy of the row on the adopter's roster, so N resumes leave N rows for one
# agent across N rosters and this verb read all of them. Three rows, three names, one id.
R28E="$(make_repo s28-dupes)"; new_roster "$R28E"
mkdir -p "$R28E/.bionic/docs/record"
ID28E="adupe-one-2800000000000000005"
for _n in dupe-a dupe-b dupe-c; do
  add_row_to "$R28E" "$S28_A" name="$_n" status=identified agent_id="$ID28E" \
    subagent_type=bionic:implementor duration="45 minutes" cadence="10 minutes" \
    deliverable="$R28E/.bionic/docs/record/$_n.md"
done
poke "$R28E" adopt
expect_eq "28e three rows carrying one agent id are offered once" "1" \
  "$(printf '%s\n' "$OUT" | /usr/bin/grep -c "^poker-adopt/v1|.*|agent_id=$ID28E|" || true)"
expect_eq "28e2 …and the two it folded away are counted" "2" "$(s28_field "$OUT" dupes)"
expect_eq "28e3 …so exactly one row lands on this session's roster" "1" \
  "$(/usr/bin/grep -c "|agent_id=$ID28E|" "$(roster_of "$R28E")" || true)"

# ---------- 28f: THE REBUILT ROW CARRIES `re_executes=` (REQ-1 AC-1.1's adopt half) ------
#
# The field is a budget declaration — the commands a brief said it would re-run — and the
# writer-side guard reads it off the row for the agent's own id. A resumed writer whose
# adopted row lost it comes out of a `/clear` with no budget on it, which is the same failure
# the three instrument fields were carried forward to prevent. The fixture appends it as the
# TRAILING field a roster row carries it in.
R28F="$(make_repo s28-re-executes)"; new_roster "$R28F"
mkdir -p "$R28F/.bionic/docs/record"
S28F_ROSTER="$(roster_of "$R28F" "$S28_A")"
roster_header > "$S28F_ROSTER"
mkrow session="$S28_A" name=rerun-writer status=identified \
  agent_id=arerun-one-2800000000000006 subagent_type=bionic:implementor \
  duration="45 minutes" cadence="10 minutes" \
  deliverable="$R28F/.bionic/docs/record/rerun.md" \
  | sed 's/$/|re_executes=npx jest tests\/unit/' >> "$S28F_ROSTER"
poke "$R28F" adopt
expect_contains "28f the adopted row carries the declared runs forward" \
  "re_executes=npx jest tests/unit" "$(cat "$(roster_of "$R28F")")"
expect_eq "28f2 …on the row this adopt wrote, not on a second one" "1" \
  "$(/usr/bin/grep -c 'source=adopted' "$(roster_of "$R28F")" || true)"

# ---------- 28g: AND IT DOES NOT RE-ENCODE WHAT IT CARRIES (epic-23 wave-18, T4) ---------
#
# REQ-7 / D4. `re_executes=` is the one field whose value is a COMMAND compared back,
# character for character, against what a writer types — so the row percent-encodes the
# `|` it cannot hold literally, and every reader decodes it. `adopt` is the reader that is
# also a WRITER: it lifts the field off the source row and hands it to `roster_row` again.
# A reader that decoded without the writer re-encoding would put a raw pipe on the line and
# forge a segment; a writer that re-encoded an already-encoded value would turn `%7C` into
# `%257C` and hand a resumed agent a budget holding a command no shell could run. Both
# failures are invisible to 28f, whose run carries no pipe at all.
#
# fails-when: the adopted field differs by one byte from the source row's, or decoding it
# does not give back the command the brief declared.
R28G="$(make_repo s28-re-executes-pipe)"; new_roster "$R28G"
mkdir -p "$R28G/.bionic/docs/record"
S28G_ROSTER="$(roster_of "$R28G" "$S28_A")"
roster_header > "$S28G_ROSTER"
# THE STORED FORM IS THE WRITER'S OWN, taken from `roster_row` rather than typed here, so a
# fixture cannot disagree with the encoding production uses.
S28G_CMD="npx jest --testPathPattern='(a|b).spec.ts'"
S28G_ENC="$(roster_pipe_escape "$S28G_CMD")"
mkrow session="$S28_A" name=rerun-pipe status=identified \
  agent_id=arerun-two-2800000000000007 subagent_type=bionic:implementor \
  duration="45 minutes" cadence="10 minutes" \
  deliverable="$R28G/.bionic/docs/record/rerun-pipe.md" \
  | sed "s|\$|\|re_executes=$S28G_ENC|" >> "$S28G_ROSTER"
poke "$R28G" adopt
S28G_ROW="$(grep 'source=adopted' "$(roster_of "$R28G")" | tail -1)"
S28G_FIELD="$(printf '%s' "$S28G_ROW" | tr '|' '\n' | grep '^re_executes=' | head -1 | cut -d= -f2-)"
expect_eq "28g the adopted row carries the declared run byte for byte" \
  "$S28G_ENC" "$S28G_FIELD"
expect_eq "28g2 …so it still decodes to the command the brief declared" \
  "$S28G_CMD" "$(roster_pipe_unescape "$S28G_FIELD")"
expect_eq "28g3 …and the value is still ONE field of the row" "1" \
  "$(printf '%s' "$S28G_ROW" | tr '|' '\n' | grep -c '^re_executes=' | tr -d ' ')"

# ---------- 28h: a row whose plan is THERE and cannot be read is UNREADABLE, never closed ----
#
# (wave-20 T18, REQ-2, D2; T1's carry-over.) T1 made `session_run` answer `bound-unreadable`
# for a plan at mode 000, and every reader of the session's OWN binding names it. This verb
# reads a different plan — the one each foreign row names — and asked `[ -f p ] && ! run_open
# p`, so a mode-000 plan (`-f` true, `run_open` 3) read as CLOSED: its rows were counted
# `closed=` and printed nowhere, while the run they belong to may be mid-flight. A plan inside
# a folder that cannot be opened (`-f` false) fell the other way, through to the partition, so
# an unbound caller ADOPTED a row whose run it could not read. Both now print the row as
# UNREADABLE, naming the path; count it `unreadable=`, never `closed=`; and write nothing.
#
# THE CALLER IS UNBOUND, the partition that adopts every row (`all`): a verb that only LISTED
# the row would pass a bound caller's `other` arm for the wrong reason.
#
# PRIVILEGE, CHECKED FIRST (run-predicate R8h's reason): a suite running as root reads a
# mode-000 file, and every row below would pass on a readable plan.
S28_C="cccc0000-28cc-4bbb-8ccc-000000000003"
s28_tmp_sums() {  # <repo> -> one cksum line per file in .bionic/tmp, sorted: what adopt wrote
  ( cd "$1/.bionic/tmp" && for _f in *; do [ -f "$_f" ] && cksum "$_f"; done ) | sort
}
s28_line() {  # <row name> <output> -> that row's poker-adopt/v1 line
  printf '%s\n' "$2" | /usr/bin/grep "^poker-adopt/v1|.*|name=$1|" | head -1
}
R28H="$(make_repo s28-unreadable)"; new_roster "$R28H"
mkdir -p "$R28H/.bionic/docs/record"
P28H="$(plan_at "$R28H" 'epic-28/wave-locked.plan.md' "$(plan_body 4 'in progress')")"
add_row_to "$R28H" "$S28_C" name=locked-run-writer status=identified \
  agent_id=alocked-run-2800000000000008 subagent_type=bionic:implementor \
  duration="45 minutes" cadence="10 minutes" plan="$P28H" \
  deliverable="$R28H/.bionic/docs/record/locked-run.md"
chmod 000 "$P28H"
expect_eq "28h premise: the row's plan exists and this user cannot read it" "yes" \
  "$([ -e "$P28H" ] && [ ! -r "$P28H" ] && echo yes || echo no)"
S28H_BEFORE="$(s28_tmp_sums "$R28H")"
poke "$R28H" adopt
expect_contains "28h a row whose plan cannot be read is LISTED, never dropped as closed" \
  "partition=unreadable" "$(s28_line locked-run-writer "$OUT")"
expect_contains "28h2 …the report says UNREADABLE" "UNREADABLE" "$OUT"
expect_contains "28h3 …and names the plan it cannot read" "$P28H" "$OUT"
expect_eq "28h4 …it is never counted closed" "0" "$(s28_field "$OUT" closed)"
expect_eq "28h5 …it is counted unreadable, on the summary line" "1" "$(s28_field "$OUT" unreadable)"
expect_absent "28h6 …and the closed-run sentence is not said about it" "row(s) skipped" "$OUT"
expect_eq "28h7 …and nothing under .bionic/tmp changed: no row adopted, no marker copied, no ack" \
  "$S28H_BEFORE" "$(s28_tmp_sums "$R28H")"
# THE PAIRED POSITIVE, ON THE SAME FIXTURE: one fact moves — the plan's mode — and the same
# unbound caller adopts the same row. Without it, 28h passes against a verb that adopts nothing.
chmod 644 "$P28H"
poke "$R28H" adopt
expect_contains "28h8 …the same row, its plan readable again, is adopted" \
  "partition=all" "$(s28_line locked-run-writer "$OUT")"
expect_eq "28h9 …counted neither unreadable nor closed" "0|0" \
  "$(s28_field "$OUT" unreadable)|$(s28_field "$OUT" closed)"
expect_eq "28h10 …and it lands on this session's roster" "1" \
  "$(/usr/bin/grep -c '|name=locked-run-writer|' "$(roster_of "$R28H")" || true)"

# ---------- 28i: a BOUND caller whose own binding is that plan still never adopts it -----
#
# The row names the caller's own plan, so the partition alone would say `own` and write it.
# An unreadable plan outranks the partition: nothing can be read to take ownership against.
R28I="$(make_repo s28-unreadable-own)"; new_roster "$R28I"
mkdir -p "$R28I/.bionic/docs/record"
P28I="$(plan_at "$R28I" 'epic-28/wave-own.plan.md' "$(plan_body 4 'in progress')")"
add_row_to "$R28I" "$S28_C" name=own-locked-writer status=identified \
  agent_id=aown-locked-2800000000000009 subagent_type=bionic:implementor \
  duration="45 minutes" cadence="10 minutes" plan="$P28I" \
  deliverable="$R28I/.bionic/docs/record/own-locked.md"
bind_marker "$R28I" "$P28I"
chmod 000 "$P28I"
S28I_BEFORE="$(s28_tmp_sums "$R28I")"
poke "$R28I" adopt
expect_contains "28i bound to the unreadable plan: its own row is UNREADABLE, not own" \
  "partition=unreadable" "$(s28_line own-locked-writer "$OUT")"
expect_eq "28i2 …counted unreadable, never closed" "1|0" \
  "$(s28_field "$OUT" unreadable)|$(s28_field "$OUT" closed)"
expect_eq "28i3 …and nothing is written" "$S28I_BEFORE" "$(s28_tmp_sums "$R28I")"
chmod 644 "$P28I"
poke "$R28I" adopt
expect_contains "28i4 …the paired positive: readable again, the same row is its own" \
  "partition=own" "$(s28_line own-locked-writer "$OUT")"

# ---------- 28j: a plan inside a folder that cannot be opened is UNREADABLE too ---------
#
# research D3 N1's shape: `-e`, `-f` and `-r` are all false for the plan, exactly as for a
# deleted one, so only the nearest existing ancestor tells the two apart. This is the shape
# that was ADOPTED, not dropped: `[ -f p ]` failed, so the row fell through to `all`.
R28J="$(make_repo s28-unreadable-vault)"; new_roster "$R28J"
mkdir -p "$R28J/.bionic/docs/record"
P28J="$(plan_at "$R28J" 'epic-28/vault/wave-vaulted.plan.md' "$(plan_body 4 'in progress')")"
V28J="$R28J/.bionic/docs/plans/epic-28/vault"
add_row_to "$R28J" "$S28_C" name=vaulted-writer status=identified \
  agent_id=avaulted-run-280000000000010 subagent_type=bionic:implementor \
  duration="45 minutes" cadence="10 minutes" plan="$P28J" \
  deliverable="$R28J/.bionic/docs/record/vaulted.md"
chmod 000 "$V28J"
expect_eq "28j premise: the plan reads as absent and its folder cannot be opened" "no|no" \
  "$([ -e "$P28J" ] && echo yes || echo no)|$([ -x "$V28J" ] && echo yes || echo no)"
S28J_BEFORE="$(s28_tmp_sums "$R28J")"
poke "$R28J" adopt
expect_contains "28j a row whose plan sits in an unopenable folder is UNREADABLE, not adopted" \
  "partition=unreadable" "$(s28_line vaulted-writer "$OUT")"
expect_eq "28j2 …counted unreadable, never closed" "1|0" \
  "$(s28_field "$OUT" unreadable)|$(s28_field "$OUT" closed)"
expect_eq "28j3 …and nothing is written" "$S28J_BEFORE" "$(s28_tmp_sums "$R28J")"
chmod 755 "$V28J"

# ---------- 28k: THE CONTROL — a plan that is GONE is not unreadable ---------------------
#
# The row's plan was deleted under folders that open. That is today's behaviour, unchanged:
# `run_open` says nothing about a path that is not a file here, so the row keeps its
# partition (an unbound caller adopts it) and is neither unreadable nor closed.
R28K="$(make_repo s28-gone-plan)"; new_roster "$R28K"
mkdir -p "$R28K/.bionic/docs/record"
P28K="$R28K/.bionic/docs/plans/epic-28/wave-gone.plan.md"
add_row_to "$R28K" "$S28_C" name=gone-plan-writer status=identified \
  agent_id=agone-plan-2800000000000011 subagent_type=bionic:implementor \
  duration="45 minutes" cadence="10 minutes" plan="$P28K" \
  deliverable="$R28K/.bionic/docs/record/gone.md"
poke "$R28K" adopt
expect_contains "28k a row whose plan is gone keeps today's partition" \
  "partition=all" "$(s28_line gone-plan-writer "$OUT")"
expect_eq "28k2 …and is counted neither unreadable nor closed" "0|0" \
  "$(s28_field "$OUT" unreadable)|$(s28_field "$OUT" closed)"
expect_absent "28k3 …and the report never says UNREADABLE" "UNREADABLE" "$OUT"
# ============================================================
section "Section 29: extend — re-opening a MET row (REQ-10; D11, T-h)"
# ============================================================
#
# THE VERB. `verdict_row` (hooks/session-sweeper.sh) reads a name's LAST roster row alone —
# `standdown-declined:` answers one turn and writes nothing, and `ack` closes a row instead
# of opening one — so nothing existing re-opens a MET lineage. `extend <name> <reason>`
# appends a fresh row for the same name, launched NOW, with `<reason>` riding in `claims=`:
# the already-written deliverable then dates before the new launch instant, the verdict
# leaves MET, and the row counts OPEN again — the same append-only shape every other writer
# in this file keeps.

# ---------- 29a: a MET row is stood down; extend, and the next tick reads it live ----------
R29A="$(make_repo s29-extend-met)"; new_roster "$R29A"; armed_ago "$R29A"; delivered_plan "$R29A"
DEL_29A="$R29A/delivered.md"; echo "done" > "$DEL_29A"
add_row "$R29A" name=t1 deliverable="$DEL_29A" duration="1 minute" \
  launched_at="$(iso_ago 600)" "$(said "$R29A" t1)"
S29_CFG="$(fake_config_dir s29-extend)"
export CLAUDE_CONFIG_DIR="$S29_CFG"
plant_answer "$S29_CFG/projects/-fixture-project/$SID.jsonl" fresh "t1:running"

poke "$R29A" tick
expect_contains "29a baseline: the MET row is stood down before any extend" \
  "poker: STANDDOWN t1" "$OUT"

poke "$R29A" extend t1 "second commit"
expect_eq "29a2 extend exits 0" "0" "$RC"
expect_contains "29a3 …and says the row is open again" "extended" "$OUT"

poke "$R29A" tick
expect_absent "29a4 the same row, same tick, draws no STANDDOWN after extend" \
  "poker: STANDDOWN t1" "$OUT"
expect_contains "29a5 …and it counts open, not closed" "open=1" "$OUT"

unset CLAUDE_CONFIG_DIR

# ---------- 29b: extend on a name with no roster row REFUSES, naming it ----------
R29B="$(make_repo s29-extend-no-row)"; new_roster "$R29B"
poke "$R29B" extend nobody "a reason"
expect_eq "29b no such row REFUSES (exit 1)" "1" "$RC"
expect_contains "29b2 …and names the missing row" "nobody" "$OUT"

# ---------- 29c: an unengaged session decides nothing (AC-10, same guard as bind/adopt) --
R29C="$(make_repo s29-extend-unengaged)"; new_roster "$R29C"
add_row "$R29C" name=t1 deliverable="$R29C/never.md" duration="1 minute"
unengage "$R29C"
poke "$R29C" extend t1 "a reason"
expect_eq "29c an unengaged session's extend exits 0 (decides nothing)" "0" "$RC"
expect_contains "29c2 …and says so" "NOT-ENGAGED" "$OUT"
expect_eq "29c3 …and the roster is untouched" "1" \
  "$(/usr/bin/grep -c '|name=t1|' "$(roster_of "$R29C")" || true)"

# ---------- 29d: the arg shape — extend takes exactly two operands ----------
R29D="$(make_repo s29-extend-usage)"; new_roster "$R29D"
poke "$R29D" extend
expect_eq "29d extend with no operands is a usage error (exit 2)" "2" "$RC"
poke "$R29D" extend only-one
expect_eq "29d2 extend with one operand is a usage error (exit 2)" "2" "$RC"
poke "$R29D" extend a b c
expect_eq "29d3 extend with three operands is a usage error (exit 2)" "2" "$RC"

# ---------- 29e: THE EXTENSION SURVIVES adopt (AC-10.2; §28f pattern) ----------
#
# `adopt_fold` folds a roster to the LAST non-empty value per field per name — the same
# fold §28f pins for `re_executes=`. A predecessor session's row is extended (bumped
# `launched_at=`, unmoved `deliverable=`); a fresh session then adopts it, and the rebuilt
# row must carry the BUMP forward, or the adopted copy reads MET again the instant it
# lands (AC-10.2's fail-when).
S29_PRED="cccc0000-29cc-4bbb-8ccc-000000000003"
R29E="$(make_repo s29-extend-adopt)"; new_roster "$R29E"
mkdir -p "$R29E/.bionic/docs/record"
P29E_OPEN="$(plan_at "$R29E" 'epic-29/wave-open.plan.md' "$(plan_body 4 'in progress')")"
DEL_29E="$R29E/.bionic/docs/record/t1.md"; echo "done" > "$DEL_29E"
add_row_to "$R29E" "$S29_PRED" name=t1 status=identified \
  agent_id=aextend-2900000000000000001 subagent_type=bionic:implementor \
  duration="45 minutes" cadence="10 minutes" plan="$P29E_OPEN" \
  deliverable="$DEL_29E" launched_at="$(iso_ago 600)"

# `extend` runs AS the predecessor session, over ITS OWN roster (the shape the verb is
# for: a writer resuming its own MET row) — so the engagement guard needs the
# predecessor's own marker, not the adopter's. `engage()` always stamps the suite-global
# $SID; this is a second session id, stamped by hand the same way that helper does.
: > "$R29E/.bionic/tmp/engaged-$S29_PRED.state"

( cd "$R29E" && exec env CLAUDE_CODE_SESSION_ID="$S29_PRED" bash "$POKER" extend t1 "second commit" ) \
  >/dev/null 2>&1

poke "$R29E" adopt
expect_contains "29e the extended row is still offered for adopt" "t1" "$OUT"

S29E_CFG="$(fake_config_dir s29-extend-adopt)"
export CLAUDE_CONFIG_DIR="$S29E_CFG"
plant_answer "$S29E_CFG/projects/-fixture-project/$SID.jsonl" fresh "t1:running"
poke "$R29E" tick
expect_absent "29e2 …and the row adopt wrote does not read MET again" \
  "poker: STANDDOWN t1" "$OUT"
expect_contains "29e3 …and it counts open after adopt" "open=1" "$OUT"
unset CLAUDE_CONFIG_DIR

# ============================================================
# ---------- 29f: THE APPENDED ROW'S `re_executes=` IS BYTE-IDENTICAL TO THE ROW IT COPIED --
#
# REQ-7/D4 (T4) stores the declared runs percent-encoded; every writer takes the PLAIN
# value and encodes once. `extend` copies the field off the stored row, so it must decode
# before handing it back to `roster_row` — the symmetry `clean … re_executes` gives
# `adopt_write_row` (:517). Lifted raw, `%7C` is re-encoded to `%257C` and the extended
# row's declared run decodes to a command holding the literal text `%7C`, which no shell
# ever ran (wave-18 walk-bb711e1.md §14). Byte-identical stored fields is the whole pin.
R29F="$(make_repo s29-extend-rex)"; new_roster "$R29F"; armed_ago "$R29F"
DEL_29F="$R29F/delivered.md"; echo "done" > "$DEL_29F"
add_row "$R29F" name=t1 deliverable="$DEL_29F" duration="1 minute" \
  launched_at="$(iso_ago 600)"
S29F_ROSTER="$(roster_of "$R29F")"
S29F_ENC='npx jest --testPathPattern="(a%7Cb)"'
S29F_ROW1="$(grep '|name=t1|' "$S29F_ROSTER" | head -1)"
grep -v '|name=t1|' "$S29F_ROSTER" > "$S29F_ROSTER.tmp"
printf '%s|re_executes=%s\n' "$S29F_ROW1" "$S29F_ENC" >> "$S29F_ROSTER.tmp"
mv "$S29F_ROSTER.tmp" "$S29F_ROSTER"
poke "$R29F" extend t1 "second commit"
expect_eq "29f extend on a row carrying re_executes= exits 0" "0" "$RC"
S29F_FIRST="$(grep '|name=t1|' "$S29F_ROSTER" | head -1 | tr '|' '\n' | grep '^re_executes=' | head -1 | cut -d= -f2-)"
S29F_LAST="$(grep '|name=t1|' "$S29F_ROSTER" | tail -1 | tr '|' '\n' | grep '^re_executes=' | head -1 | cut -d= -f2-)"
expect_eq "29f2 the appended row stores the declared run exactly as the copied row does (no double encoding)" \
  "$S29F_ENC" "$S29F_LAST"
expect_eq "29f3 …so the two stored fields are byte-identical" "$S29F_FIRST" "$S29F_LAST"
expect_absent "29f4 …and %257C never appears on the roster" "%257C" "$(cat "$S29F_ROSTER")"


# ---------- 29g: THE REASON IS DATA, NEVER A PROCESS PATTERN (wave-20 T9, REQ-4, AC-4.4) ----------
#
# `extend` used to write its reason into `claims=` — the one field the sweeper hands to
# `pgrep -f` as a process pattern (`claims_live`). A reason is prose: `retry .* [a-z]+` in
# `claims=` is a regular expression that matches half the machine and reads the row
# STILL-LIVE for the life of the session. The reason now rides `extended=<iso> <reason>`,
# and `claims=` is copied from the row it extends, unchanged.
R29G="$(make_repo s29-extend-reason)"; new_roster "$R29G"
DEL_29G="$R29G/delivered.md"; echo "done" > "$DEL_29G"
add_row "$R29G" name=t1 deliverable="$DEL_29G" duration="1 minute" claims="build-worker-29g" \
  launched_at="$(iso_ago 600)"
S29G_ROSTER="$(roster_of "$R29G")"
poke "$R29G" extend t1 'retry .* [a-z]+ (x|y) $HOME'
expect_eq "29g extend with a metacharacter reason exits 0" "0" "$RC"
S29G_LAST="$(grep '|name=t1|' "$S29G_ROSTER" | tail -1)"
expect_eq "29g2 AC-4.4 claims= is the copied row's, not the reason" "build-worker-29g" \
  "$(printf '%s' "$S29G_LAST" | tr '|' '\n' | grep '^claims=' | cut -d= -f2-)"
expect_regex "29g3 …the reason rides extended=<iso> <reason>" \
  '^extended=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z retry \.\* \[a-z\]\+ \(x y\) \$HOME$' \
  "$(printf '%s' "$S29G_LAST" | tr '|' '\n' | grep '^extended=')"
expect_eq "29g4 …on the appended row only — the original carries no extended=" "0" \
  "$(grep '|name=t1|' "$S29G_ROSTER" | head -1 | grep -c '|extended=' || true)"

# ---------- 29h: THE TEAMMATE SHAPE — extend's successor is the row the wall reads for the id (wave-22 T1; REQ-1 AC-1.2, D1) ----------
#
# A teammate's roster can end `identified` (id) -> `confirmed` (agent_id= empty): the recorder
# keeps the transcript id off the confirmed row, and the two land in either order. `extend`
# copies the name's latest row, so at 12574e2 its successor had no id either and every by-id
# reader — the suite-budget wall first — kept reading the pre-extend row. The successor now
# takes `status=`, `agent_id=` and `teammate_id=` from the agent's latest identified row, so
# `roster_row_for_id` (payload/scripts/lib/roster.sh, the wall's own pick) returns it.
R29H="$(make_repo s29-extend-teammate)"; new_roster "$R29H"
S29H_LAUNCH="$(iso_ago 600)"
s29h_row() {  # <key=value>... — one row of the teammate fixture through the one writer
  roster_row_fixture status=identified "session=$SID" name=w1 agent_id=aw1-2900000000000008 \
    "launched_at=$S29H_LAUNCH" subagent_type=bionic:implementor source=declared \
    "deliverable=$R29H/delivered.md" duration="1 minute" files=hooks/a.sh \
    suites_allowed=a.test.sh suites_source=declared teammate_id=w1@session-8a41c2e0 \
    tool_use_id=toolu_w1 "$@" >> "$(roster_of "$R29H")"
}
s29h_row; s29h_row status=confirmed agent_id=
poke "$R29H" extend w1 "second commit"
expect_eq "29h extend on a teammate roster (latest row confirmed, no id) exits 0" "0" "$RC"
S29H_LAST="$(grep -F '|name=w1|' "$(roster_of "$R29H")" | tail -1)"
S29H_PICK="$(roster_row_for_id "$(roster_of "$R29H")" aw1-2900000000000008 2>/dev/null)"
expect_eq "29h2 AC-1.2 the wall's pick for the id is the extended row" "$S29H_LAST" "$S29H_PICK"
expect_ne "29h3 …which carries the new launched_at, not the dispatch's" "$S29H_LAUNCH" \
  "$(printf '%s' "$S29H_PICK" | tr '|' '\n' | grep '^launched_at=' | head -1 | cut -d= -f2-)"
expect_eq "29h4 …and the status the id was learned under" "identified" \
  "$(printf '%s' "$S29H_PICK" | tr '|' '\n' | grep '^status=' | head -1 | cut -d= -f2-)"

# ============================================================
section "Section 30: amend — a live contract changes through the shared grammar (wave-20 T9, REQ-4, AC-4.1/4.2; D4, Δ10)"
# ============================================================
#
# `amend <name> [--files+ p]… [--suites+ s]… [--reexec+ 'cmd']… --reason r` appends a
# successor row copied from the name's latest, with the added paths, suites and runs merged
# in (a union, never a narrowing), and `amended=<iso> <reason>`. The identity is copied
# verbatim: `status=`, `launched_at=`, `agent_id=`, `teammate_id=`, `tool_use_id=` — so the
# agent's verdict, its stop gate and its budget join see the same contract, wider. The stop
# wall and the budget wall already read the latest row, so a successor is read with no reader
# change. The merged fields are judged by `brief_validate_fields`, the dispatch wall's own
# grammar (payload/scripts/lib/brief.sh): whatever a dispatch carrying those lines would have
# been refused for, amend refuses.
#
# Refused: an unengaged session (decides nothing), an unknown name, a CLOSED row (the one
# close predicate, `roster_open_names`: an ack later than the latest launch), an empty change
# (no flag, or flags the row already carries), and anything the grammar refuses.
s30_row() {  # <repo> <key=value>... — one live row through the one writer
  local repo="$1"; shift
  roster_row_fixture status=identified "session=$SID" name=w1 agent_id=aw1-3000000000000001 \
    "launched_at=$(iso_ago 600)" subagent_type=bionic:implementor source=declared \
    "deliverable=$repo/never-yet.md" duration="2 hours" \
    files=hooks/a.sh suites_allowed=a.test.sh suites_source=declared \
    teammate_id=w1@session-8a41c2e0 tool_use_id=toolu_w1 "$@" >> "$(roster_of "$repo")"
}
s30_last() { grep -F "|name=${2:-w1}|" "$(roster_of "$1")" | tail -1; }
s30_field() { printf '%s' "$1" | tr '|' '\n' | grep "^$2=" | head -1 | cut -d= -f2-; }

R30="$(make_repo s30-amend)"; new_roster "$R30"; s30_row "$R30"
S30_BEFORE="$(s30_last "$R30")"
S30_N0="$(grep -c '|name=w1|' "$(roster_of "$R30")")"

# ---------- 30a: AC-4.1 — --files+ widens files=, and the row's identity is kept ----------
poke "$R30" amend w1 --files+ hooks/b.sh --reason 'the fix touches b'
expect_eq "30a amend --files+ exits 0" "0" "$RC"
expect_contains "30a2 …and says what it did" "amended" "$OUT"
S30_AFTER="$(s30_last "$R30")"
expect_eq "30a3 …one successor row appended" "$((S30_N0 + 1))" "$(grep -c '|name=w1|' "$(roster_of "$R30")")"
expect_eq "30a4 AC-4.1 files= is the union, old first" "hooks/a.sh,hooks/b.sh" "$(s30_field "$S30_AFTER" files)"
# The identity triple comes from the name's latest row that carries an id (wave-22 T1, D1) —
# on this one-row fixture that is the row itself, so the async shape is byte-for-byte 12574e2's;
# 30t1 below is the teammate shape, where the two rows differ.
S30_IDROW="$(grep -F '|name=w1|' "$(roster_of "$R30")" | grep -v '|agent_id=|' | head -1)"
for _k in status agent_id teammate_id; do
  expect_eq "30a5 AC-4.2 $_k= is the identified row's" "$(s30_field "$S30_IDROW" "$_k")" "$(s30_field "$S30_AFTER" "$_k")"
done
for _k in launched_at tool_use_id subagent_type deliverable suites_allowed suites_source; do
  expect_eq "30a5 AC-4.2 $_k= is copied verbatim" "$(s30_field "$S30_BEFORE" "$_k")" "$(s30_field "$S30_AFTER" "$_k")"
done
expect_regex "30a6 …and amended=<iso> <reason> records when and why" \
  '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z the fix touches b$' "$(s30_field "$S30_AFTER" amended)"
expect_eq "30a7 …the original row is untouched (append-only)" "$S30_BEFORE" \
  "$(grep -F '|name=w1|' "$(roster_of "$R30")" | sed -n "${S30_N0}p")"

# ---------- 30b: --suites+ and --reexec+, repeated, union into the row ----------
poke "$R30" amend w1 --suites+ tests/b.test.sh --suites+ tests/c.test.sh \
  --reexec+ 'npx jest --testPathPatterns widget' --reason 'b and c cover the fix'
expect_eq "30b amend --suites+ --reexec+ exits 0" "0" "$RC"
S30_B="$(s30_last "$R30")"
expect_eq "30b2 suites_allowed= is the old set plus both added, as basenames" \
  "a.test.sh b.test.sh c.test.sh" "$(s30_field "$S30_B" suites_allowed)"
expect_contains "30b3 re_executes= carries the added run, marked" \
  '`npx jest --testPathPatterns widget`' "$(s30_field "$S30_B" re_executes)"
expect_eq "30b4 files= keeps what the last amend added" "hooks/a.sh,hooks/b.sh" "$(s30_field "$S30_B" files)"
expect_eq "30b5 launched_at= still the dispatch's" "$(s30_field "$S30_BEFORE" launched_at)" "$(s30_field "$S30_B" launched_at)"

# ---------- 30c: an empty change is refused, and writes nothing ----------
S30_SUM="$(cksum < "$(roster_of "$R30")")"
poke "$R30" amend w1 --reason 'nothing'
expect_eq "30c amend with no change flag is a usage error (exit 2)" "2" "$RC"
poke "$R30" amend w1 --files+ hooks/a.sh --suites+ tests/a.test.sh --reason 'already there'
expect_eq "30c2 flags the row already carries are an empty change: REFUSED (exit 1)" "1" "$RC"
expect_contains "30c3 …saying so" "changes nothing" "$OUT"
poke "$R30" amend w1 --files+ hooks/z.sh
expect_eq "30c4 no --reason is a usage error (exit 2)" "2" "$RC"
expect_eq "30c5 …and none of the three wrote a row" "$S30_SUM" "$(cksum < "$(roster_of "$R30")")"

# ---------- 30d: AC-4.2 — an unknown name, and a closed row ----------
poke "$R30" amend nobody --files+ hooks/b.sh --reason r
expect_eq "30d an unknown name is REFUSED (exit 1)" "1" "$RC"
expect_contains "30d2 …naming it" "nobody" "$OUT"
R30C="$(make_repo s30-closed)"; new_roster "$R30C"; s30_row "$R30C"
ack_rows "$R30C" w1
S30C_SUM="$(cksum < "$(roster_of "$R30C")")"
poke "$R30C" amend w1 --files+ hooks/b.sh --reason 'too late'
expect_eq "30d3 AC-4.2 a closed (acked) row is REFUSED (exit 1)" "1" "$RC"
expect_contains "30d4 …saying it is closed" "closed" "$OUT"
expect_eq "30d5 …and the roster is unchanged" "$S30C_SUM" "$(cksum < "$(roster_of "$R30C")")"

# ---------- 30e: an unengaged session decides nothing ----------
R30E="$(make_repo s30-unengaged)"; new_roster "$R30E"; s30_row "$R30E"; unengage "$R30E"
S30E_SUM="$(cksum < "$(roster_of "$R30E")")"
poke "$R30E" amend w1 --files+ hooks/b.sh --reason r
expect_eq "30e an unengaged session's amend exits 0 (decides nothing)" "0" "$RC"
expect_contains "30e2 …and says so" "NOT-ENGAGED" "$OUT"
expect_eq "30e3 …and the roster is untouched" "$S30E_SUM" "$(cksum < "$(roster_of "$R30E")")"

# ---------- 30f: THE GRAMMAR — what a dispatch would refuse, amend refuses (Δ10) ----------
R30F="$(make_repo s30-grammar)"; new_roster "$R30F"; s30_row "$R30F"
S30F_SUM="$(cksum < "$(roster_of "$R30F")")"
poke "$R30F" amend w1 --suites+ '$SUITE.test.sh' --reason 'a variable'
expect_eq "30f a suite that is not a literal name is REFUSED (exit 1)" "1" "$RC"
expect_contains "30f2 …in the dispatch wall's own words" "a declared suite is not a literal name" "$OUT"
poke "$R30F" amend w1 --suites+ tests/widget.spec.js --reason 'a jest spec'
expect_eq "30f3 a suite the shell runner cannot run is REFUSED (exit 1)" "1" "$RC"
expect_contains "30f4 …naming the fix" "Re-executes:" "$OUT"
expect_eq "30f5 …and neither wrote a row" "$S30F_SUM" "$(cksum < "$(roster_of "$R30F")")"
# THE ROLE'S CAP: an auditor's Re-executes: holds three runs; a fourth is the dispatch wall's
# refusal, and so it is amend's (wave-20 T4, Δ3).
R30G="$(make_repo s30-auditor)"; new_roster "$R30G"
s30_row "$R30G" subagent_type=bionic:auditor suites_allowed=none \
  're_executes=`npm test` `pytest tests/unit` `go test ./...`'
S30G_SUM="$(cksum < "$(roster_of "$R30G")")"
poke "$R30G" amend w1 --reexec+ 'cargo test' --reason 'a fourth run'
expect_eq "30f6 an auditor's fourth run is REFUSED (exit 1)" "1" "$RC"
expect_contains "30f7 …by the three-run cap" "3-run cap" "$OUT"
expect_eq "30f8 …and the roster is unchanged" "$S30G_SUM" "$(cksum < "$(roster_of "$R30G")")"

# ---------- 30g: a waived budget takes the added set; suites_source is copied ----------
R30W="$(make_repo s30-waived)"; new_roster "$R30W"; s30_row "$R30W" suites_allowed=none
poke "$R30W" amend w1 --suites+ tests/d.test.sh --reason 'now it runs one'
expect_eq "30g amend onto a waived budget exits 0" "0" "$RC"
expect_eq "30g2 …none is replaced by the added set" "d.test.sh" "$(s30_field "$(s30_last "$R30W")" suites_allowed)"
poke "$R30W" amend w1 --files+ hooks/q.sh --reason 'files only'
expect_eq "30g3 a files-only amend of a declared budget needs no impact command (exit 0)" "0" "$RC"
expect_eq "30g4 …and keeps the declared set" "d.test.sh" "$(s30_field "$(s30_last "$R30W")" suites_allowed)"

# ---------- 30h: the arg shape ----------
poke "$R30" amend
expect_eq "30h amend with no name is a usage error (exit 2)" "2" "$RC"
poke "$R30" amend w1 --files+ --reason r
expect_eq "30h2 a flag with no value is a usage error (exit 2)" "2" "$RC"
poke "$R30" amend w1 --bogus x --reason r
expect_eq "30h3 an unknown flag is a usage error (exit 2)" "2" "$RC"

# ---------- 30t: THE TEAMMATE SHAPE, AND THE SUCCESS LINE CHECKS ITSELF (wave-22 T1; REQ-1 AC-1.3/AC-1.6, D1, D3) ----------
#
# THE DEFECT (wave-22 seed). A teammate's roster can end `identified` (id) -> `confirmed`
# (agent_id= empty). amend copied the name's latest row — empty id and all — so the
# suite-budget wall, which keys on the id, never saw the widened contract, and the agent was
# refused its added run right after `poker: amended` printed. The successor now takes
# `status=`, `agent_id=` and `teammate_id=` from the agent's latest identified row, and the
# verb asks `roster_row_for_id` — the wall's own pick — whether the row it wrote is the one
# the wall will read before it says so.
s30_teammate() {  # <repo> — s30_row, then the recorder's confirmed copy without the id
  s30_row "$1"; s30_row "$1" status=confirmed agent_id=
}
s30_pick() { roster_row_for_id "$(roster_of "$1")" "${2:-aw1-3000000000000001}" 2>/dev/null; }

R30T="$(make_repo s30-teammate)"; new_roster "$R30T"; s30_teammate "$R30T"
S30T_IDROW="$(grep -F '|name=w1|' "$(roster_of "$R30T")" | head -1)"
S30T_BEFORE="$(s30_last "$R30T")"
poke "$R30T" amend w1 --reexec+ 'npx jest --testPathPatterns widget' --reason 'run B'
expect_eq "30t1 amend on a teammate roster exits 0" "0" "$RC"
expect_contains "30t1b …with the success line" "poker: amended — w1:" "$OUT"
S30T_AFTER="$(s30_last "$R30T")"
expect_eq "30t1c AC-1.6 the wall's pick for the id IS the row amend wrote" "$S30T_AFTER" "$(s30_pick "$R30T")"
expect_eq "30t1d …carrying the status the id was learned under" "identified" "$(s30_field "$S30T_AFTER" status)"
expect_eq "30t1e …the identified row's id" "aw1-3000000000000001" "$(s30_field "$S30T_AFTER" agent_id)"
expect_eq "30t1f …and its teammate_id" "$(s30_field "$S30T_IDROW" teammate_id)" "$(s30_field "$S30T_AFTER" teammate_id)"
expect_contains "30t1g …and the added run" '`npx jest --testPathPatterns widget`' "$(s30_field "$S30T_AFTER" re_executes)"
for _k in launched_at tool_use_id subagent_type deliverable files suites_allowed suites_source; do
  expect_eq "30t1h $_k= is copied from the name's latest row" "$(s30_field "$S30T_BEFORE" "$_k")" "$(s30_field "$S30T_AFTER" "$_k")"
done

# 30t2: BEFORE IDENTIFICATION there is no id for any wall to key on; the recorder's
# `identified` row later inherits the successor whole (design probe §Q1). The verb writes the
# row and says when the walls will read it — never that they read it now.
R30T2="$(make_repo s30-intended)"; new_roster "$R30T2"; s30_row "$R30T2" status=intended agent_id=
S30T2_N0="$(grep -c '|name=w1|' "$(roster_of "$R30T2")")"
poke "$R30T2" amend w1 --files+ hooks/b.sh --reason 'before it starts'
expect_eq "30t2 AC-1.3 amend before identification exits 0" "0" "$RC"
expect_contains "30t2b …and says the walls read the row once the agent is identified" "once w1 is identified" "$OUT"
expect_absent "30t2c …never that they read it from now on" "read this row from now on" "$OUT"
expect_eq "30t2d …the successor is written" "$((S30T2_N0 + 1))" "$(grep -c '|name=w1|' "$(roster_of "$R30T2")")"
expect_eq "30t2e …unidentified, as the row it copied" "intended:" \
  "$(s30_field "$(s30_last "$R30T2")" status):$(s30_field "$(s30_last "$R30T2")" agent_id)"

# 30t3: THE SELF-CHECK CAN FAIL. A scratch copy of the verb with the identity appends
# (D1) deleted — `extend`'s, `amend`'s, and `hold`'s since wave-24 T7 — writes the 12574e2 successor — no id — and must name the row the wall reads
# instead of printing the success line.
S30T3_ROOT="$TMPROOT/poker-no-identity"
mkdir -p "$S30T3_ROOT/hooks" "$S30T3_ROOT/scripts"
ln -s "$(cd "$(dirname "$POKER")/../payload/scripts/lib" && pwd -P)" "$S30T3_ROOT/scripts/lib"
sed '/+=(${POKER_ID_ARGS\[@\]+/d' "$POKER" > "$S30T3_ROOT/hooks/session-poker.sh"
expect_eq "30t3 meta: the scratch copy lost exactly the three identity appends (extend, amend, hold)" "3" \
  "$(diff "$POKER" "$S30T3_ROOT/hooks/session-poker.sh" | /usr/bin/grep -c '^<')"
R30T3="$(make_repo s30-selfcheck)"; new_roster "$R30T3"; s30_teammate "$R30T3"
S30T3_POKER="$POKER"; POKER="$S30T3_ROOT/hooks/session-poker.sh"
poke "$R30T3" amend w1 --reexec+ 'npx jest --testPathPatterns widget' --reason 'run B'
POKER="$S30T3_POKER"
expect_eq "30t3b AC-1.6 a successor the wall does not read is exit 1" "1" "$RC"
expect_contains "30t3c …naming the row the budget wall reads instead" \
  "poker: amend written, but the budget wall reads identified row for aw1-3000000000000001 —" "$OUT"
expect_absent "30t3d …and never the success line" "poker: amended" "$OUT"

# 30t4: A NAME DISPATCHED AGAIN IS A NEW AGENT. The identity source is scoped to the latest
# row's dispatch cycle (its tool_use_id=): the earlier agent's id is not the new agent's, and
# stamping it would hand the old id the new contract while the new agent's identification,
# which joins intended|confirmed rows by name, skipped the successor (A-T1.2).
R30T4="$(make_repo s30-redispatch)"; new_roster "$R30T4"
s30_row "$R30T4"
s30_row "$R30T4" status=intended agent_id= teammate_id= tool_use_id=toolu_w1_again
poke "$R30T4" amend w1 --files+ hooks/b.sh --reason 'the new agent needs b'
expect_eq "30t4 amend on a re-dispatched name before its new agent is identified exits 0" "0" "$RC"
expect_contains "30t4b …and says the walls read the row once w1 is identified" "once w1 is identified" "$OUT"
expect_eq "30t4c …the successor keeps the new cycle's identity, not the earlier agent's id" \
  "intended::toolu_w1_again" \
  "$(s30_field "$(s30_last "$R30T4")" status):$(s30_field "$(s30_last "$R30T4")" agent_id):$(s30_field "$(s30_last "$R30T4")" tool_use_id)"
expect_ne "30t4d …so the earlier agent's id still picks its own row, not the new contract" \
  "$(s30_last "$R30T4")" "$(s30_pick "$R30T4")"

# 30t5: ONE ROSTER-STATE PREFIX (wave-22 T10; review 5). `identity_args` read `roster-state/v1|`
# while `roster_row_for_id` (the pick the self-check compares against) reads any `roster-state/`
# row, so under a schema bump the verb saw no id, printed "once identified" and never checked.
# The function is driven alone, extracted from the verb, on a v2 row.
S30T5_DIR="$TMPROOT/s30t5"; mkdir -p "$S30T5_DIR"
S30T5_ROW="$(roster_row_fixture status=identified "session=$SID" name=w1 agent_id=aw1-3000000000000001 \
  "launched_at=$(iso_ago 600)" subagent_type=bionic:implementor tool_use_id=toolu_w1 | sed "s#^${ROSTER_ROW_SCHEMA}|#roster-state/v2|#")"
printf '%s\n' "$S30T5_ROW" > "$S30T5_DIR/roster.state"
S30T5_OUT="$(bash -c '
  eval "$(awk "/^(line_field|row_has_key|identity_args)\\(\\) \\{/{p=1} p{print} p&&/^}/{p=0}" "$1")"
  POKER_ID_ARGS=(); POKER_ID=""
  identity_args "$2" w1 "$3"; printf "%s" "$POKER_ID"' _ "$POKER" "$S30T5_DIR/roster.state" "$S30T5_ROW" 2>&1)"
expect_eq "30t5 a roster-state/v2| row carrying the id is found by identity_args" "aw1-3000000000000001" "$S30T5_OUT"
expect_eq "30t5b …and by roster_row_for_id, the one pick (one prefix, two readers)" "$S30T5_ROW" \
  "$(roster_row_for_id "$S30T5_DIR/roster.state" aw1-3000000000000001 2>/dev/null)"

# 30t6: THE SUCCESS LINE NAMES ONLY THE WALLS THAT READ THE ROW (review 4). stop-guard and
# observe pick an id's row from `confirmed|identified` rows only, so a successor that copied a
# `duplicate-start` row is read by the budget wall alone; the teammate fixture (30t1) keeps both.
R30T6="$(make_repo s30-dupstart)"; new_roster "$R30T6"
s30_row "$R30T6"; s30_row "$R30T6" status=duplicate-start
poke "$R30T6" amend w1 --files+ hooks/b.sh --reason 'twinned agent'
expect_eq "30t6 amend whose latest id-bearing row is duplicate-start exits 0" "0" "$RC"
expect_contains "30t6b …the line says what was amended" "poker: amended — w1:" "$OUT"
expect_contains "30t6c …and names the budget wall" "the budget wall reads this row from now on" "$OUT"
expect_absent "30t6d …never the stop wall, which does not read a duplicate-start row" "stop and budget walls" "$OUT"
poke "$R30T" amend w1 --files+ hooks/c.sh --reason 'teammate again'
expect_contains "30t6e the teammate fixture's line keeps both walls" "the stop and budget walls read this row from now on" "$OUT"

# 30t7: THE COPY SOURCE AND THE ID STAMP ARE ONE ROW (wave-22 T13; critic-3598752 I4). `amend`'s
# and `extend`'s source rows were read on `roster-state/v1|` while `identity_args` reads any
# `roster-state/` row (30t5), so under a schema bump the copy came from the last v1 row and the
# identity from a later row. The roster here is one v1 row, then a later row on another schema
# version carrying the same id and cycle with its own files= and teammate_id=: both verbs copy
# AND stamp from that later row. The v1 row keeps the name open (`roster_open_names` reads v1).
s30t7_world() {  # <repo> — a v1 identified row, then a v2 copy of it with its own files/teammate_id
  local v2
  s30_row "$1"
  v2="$(roster_row_fixture status=identified "session=$SID" name=w1 agent_id=aw1-3000000000000001 \
    "launched_at=$(iso_ago 300)" subagent_type=bionic:implementor source=declared \
    "deliverable=$1/never-yet.md" duration="2 hours" files=hooks/v2.sh suites_allowed=a.test.sh \
    suites_source=declared teammate_id=w1@session-v2v2v2v2 tool_use_id=toolu_w1 \
    | sed "s#^${ROSTER_ROW_SCHEMA}|#roster-state/v2|#")"
  printf '%s\n' "$v2" >> "$(roster_of "$1")"
}
R30T7="$(make_repo s30-v2-amend)"; new_roster "$R30T7"; s30t7_world "$R30T7"
expect_contains "30t7 meta: the roster's last row is on another schema version" "roster-state/v2|" \
  "$(tail -1 "$(roster_of "$R30T7")")"
poke "$R30T7" amend w1 --reexec+ 'npx jest --testPathPatterns widget' --reason 'run B'
expect_eq "30t7b amend over a later non-v1 row exits 0" "0" "$RC"
expect_eq "30t7c …copying files= from that later row, not the last v1 row" "hooks/v2.sh" \
  "$(s30_field "$(s30_last "$R30T7")" files)"
expect_eq "30t7d …and stamping the same row's teammate_id (one source row)" "w1@session-v2v2v2v2" \
  "$(s30_field "$(s30_last "$R30T7")" teammate_id)"
R30T7E="$(make_repo s30-v2-extend)"; new_roster "$R30T7E"; s30t7_world "$R30T7E"
poke "$R30T7E" extend w1 "one more commit"
expect_eq "30t7e extend over a later non-v1 row exits 0" "0" "$RC"
expect_eq "30t7f …copying files= from that later row" "hooks/v2.sh" "$(s30_field "$(s30_last "$R30T7E")" files)"
expect_eq "30t7g …and stamping the same row's teammate_id" "w1@session-v2v2v2v2" \
  "$(s30_field "$(s30_last "$R30T7E")" teammate_id)"

# ============================================================
section "Section 30b: FOLLOW-UP — the tick holds a MET row whose agent has a message waiting (wave-20 T9, REQ-4, AC-4.3; Δ8)"
# ============================================================
#
# The orchestrator sent a MET agent a follow-up and the agent has not answered: the sweeper
# reads FOLLOW-UP, and the tick inherits it — counted open, never a STANDDOWN, no stop order.
# The transcript is the orchestrator's own, carrying the three shapes in the order the CLI
# writes them: the agent's report (a user record opening `<teammate-message`), the
# SendMessage tool_use, then a FRESH ListAgents answer — the agent `running`, as a message
# resumes it, and `idle` again once it has answered.
S30B_CFG="$(fake_config_dir s30b-followup)"
export CLAUDE_CONFIG_DIR="$S30B_CFG"
S30B_TR="$S30B_CFG/projects/-fixture-project/$SID.jsonl"
s30b_msg() {
  jq -nc --arg b "<teammate-message teammate_id=\"$1\" color=\"blue\" summary=\"r\">
report
</teammate-message>" '{type:"user",timestamp:"2026-09-05T00:50:10.000Z",message:{role:"user",content:$b}}'
}
s30b_send() {
  jq -nc --arg to "$1" '{type:"assistant",timestamp:"2026-09-05T00:50:20.000Z",message:{role:"assistant",content:[{type:"tool_use",id:"toolu_s30b",name:"SendMessage",input:{to:$to,message:"also x"}}]}}'
}
s30b_transcript() {  # <fw status> <record-producing commands…> — spliced between the prompt and the answer
  local tmp="$TMPROOT/s30b.panel" cmd st="$1"; shift
  plant_answer "$tmp" fresh "fw:$st"
  { head -1 "$tmp"; for cmd in "$@"; do eval "$cmd"; done; tail -n +2 "$tmp"; } > "$S30B_TR"
}
R30B="$(make_repo s30b-followup)"; new_roster "$R30B"; armed_ago "$R30B"; delivered_plan "$R30B"
DEL_30B="$R30B/delivered.md"; echo "done" > "$DEL_30B"
add_row "$R30B" name=fw deliverable="$DEL_30B" duration="1 minute" launched_at="$(iso_ago 600)" \
  "$(said "$R30B" fw)"

s30b_transcript running "s30b_msg fw" "s30b_send fw"
poke "$R30B" tick
expect_absent "30b-a AC-4.3 a MET row with a follow-up in flight draws no STANDDOWN" "poker: STANDDOWN fw" "$OUT"
expect_contains "30b-a2 …it counts open" "open=1" "$OUT"
expect_eq "30b-a3 …and no stop order is written for it" "no" \
  "$([ -f "$R30B/.bionic/tmp/stop-orders-$SID.state" ] && echo yes || echo no)"

s30b_transcript idle "s30b_msg fw" "s30b_send fw" "s30b_msg fw"
poke "$R30B" tick
expect_contains "30b-b the reply closes it: the same row is stood down" "poker: STANDDOWN fw" "$OUT"
unset CLAUDE_CONFIG_DIR

section "Section 31: the ledger is live at task scale — the tick fills, and the wall agrees (wave-18 REQ-3, AC-3.1/AC-3.3; ADR-033 d2)"
# ============================================================
#
# THE RUN SHAPE THAT REPORTED THE FRICTION. A task-scale plan carries six columns and a
# `current: T<n>`, and until this wave both readers of readiness were blind to it: the tick
# withheld on an unreadable `current:` (§22g) and `units_ready` refused a non-numeric step at
# the door. Filling was therefore possible only at wave scale, in the one run shape that
# never asked for it.
#
# WHAT §22g KEEPS, and why this section is not its inverse: §22g's plan is a WAVE table
# sitting at `current: T1`, a shape whose step cells contradict its `current:` — that stays
# unreadable and still fills nothing. What goes live here is the plan whose TABLE is
# task-scale too.
#
# AND THE AGREEMENT IS DRIVEN ON ONE FIXTURE, both sides. `payload/scripts/lib/fill.sh` is
# the single computation now; the tick prints its ids and the Stop hook's fill duty names the
# same ones back when the turn ends without dispatching them. A row that drove only the tick
# would leave the invariant's whole point — that the two cannot disagree — unpinned.

s31_task_plan() {  # <repo> <current> -> the path; six columns, T1 in flight, T2/T3 pending
  local repo="$1" cur="$2"
  local f="$repo/.bionic/docs/plans/epic-01-task-scale/task-01-fixture.plan.md"
  mkdir -p "$(dirname "$f")"
  {
    printf -- '---\n'
    printf 'governing-skill: superpowers:writing-plans\n'
    printf 'scale: task\n'
    printf 'parallel-budget: writers=8 suites=4 worktrees=32 test_jobs=8 source=probe\n'
    printf -- '---\n\n# fixture task-scale plan\n\n'
    printf '## SDLC State\n\ncurrent: %s\n%s\n\n- %s: in progress\n\n' "$cur" "$SP_APPROVED_LINE" "$cur"
    printf '## Tasks\n\n'
    printf '| id | intent | rigor | description | status | worktree |\n'
    printf '|---|---|---|---|---|---|\n'
    printf '| T1 | bugfix | standard | the unit in flight | active | 18-T1 |\n'
    printf '| T2 | bugfix | standard | the next unit | pending | — |\n'
    printf '| T3 | bugfix | audited | the unit after that | pending | — |\n'
  } > "$f"
  touch "$f"
  printf '%s' "$f"
}

# ---------- 31a: the tick fills a task-scale ledger, in table order ----------
R31A="$(make_repo s29-task-fill)"; new_roster "$R31A"
P31A="$(s31_task_plan "$R31A" T1)"
add_row "$R31A" name=T1 deliverable=t1.md duration="4 hours" launched_at="$(iso_ago 60)"
poke_pressure "$R31A" 8192 1.0 tick
expect_eq "31a a task-scale plan ticks cleanly (exit 0)" "0" "$RC"
expect_contains "31a2 …and fills the two pending rows, in table order" \
  "poker: FILL T2 T3" "$OUT"
expect_absent "31a3 …never the unreadable wording — T<n> is this repo's other current: shape" \
  "plan current: unreadable" "$OUT"
expect_absent "31a4 …and the row in flight is not offered again" "FILL T1" "$OUT"

# ---------- 31b: the wall names the same two rows when the turn dispatched neither ----------
#
# Driven through the SHIPPED Stop process (hooks/stop.sh), on the same fixture the tick just
# ran on: same plan, same roster, same session. The transcript holds an ordinary user turn —
# no Patrol tick in it at all, which is the whole point: before this wave the duty was
# derivative of a tick having printed a line, so a turn that simply ended with work ready and
# nobody dispatched ended in silence.
S31_STOP_HOOK="${BIONIC_HOOKS_DIR}/stop.sh"
s31_transcript() {  # <repo> <text>... -> the transcript path
  local repo="$1"; shift
  local tr="$repo/transcript.jsonl"
  : > "$tr"
  local t
  for t in "$@"; do
    jq -nc --arg x "$t" '{type:"user",isSidechain:false,userType:"external",
                          message:{role:"user",content:$x}}' >> "$tr"
  done
  printf '%s' "$tr"
}
s31_stop() {  # <repo> <transcript> -> sets S31_OUT, S31_RC
  S31_OUT="$(env CLAUDE_CODE_SESSION_ID="$SID" bash "$S31_STOP_HOOK" <<EOF 2>/dev/null
$(jq -nc --arg t "$2" --arg c "$1" --arg s "$SID" \
   '{session_id:$s,transcript_path:$t,cwd:$c,hook_event_name:"Stop",stop_hook_active:false}')
EOF
)"
  S31_RC=$?
}
s31_reason() { printf '%s' "$S31_OUT" | jq -r '.reason // ""' 2>/dev/null; }
s31_decision() { printf '%s' "$S31_OUT" | jq -r '.decision // ""' 2>/dev/null; }

S31_TR="$(s31_transcript "$R31A" "have a look at the next two units")"
# BOUND to the plan the tick filled from: the wall charges only a bound session's own ledger
# (wave-23-fixit-1810, REQ-1, D1).
bind_marker "$R31A" "$P31A"
s31_stop "$R31A" "$S31_TR"
expect_eq "31b the turn is refused — the ledger is live and two rows are ready" \
  "block" "$(s31_decision)"
expect_contains "31b2 …naming T2, the first ready row" "T2" "$(s31_reason)"
expect_contains "31b3 …and T3, the second — named, not counted" "T3" "$(s31_reason)"
expect_contains "31b4 …and saying what answers it" "fill-declined:" "$(s31_reason)"

# ---------- 31c: the same turn, with the rows dispatched, ends in silence ----------
#
# RE-AUTHORED FOR WAVE-20 (REQ-5, Δ7): the wall judges by count on the facts a dispatch leaves
# on disk — the roster row the dispatch wall writes at launch, and the plan row the orchestrator
# ledgers `active` — never by finding the id in an Agent call's words. So the dispatched turn
# carries both: T2 and T3 on the roster, and `active` in the table.
R31C="$(make_repo s29-task-dispatched)"; new_roster "$R31C"
P31C="$(s31_task_plan "$R31C" T1)"
sed -i.bak -e 's/^\(| T2 |.*\)| pending |/\1| active |/' -e 's/^\(| T3 |.*\)| pending |/\1| active |/' "$P31C"
add_row "$R31C" name=T1 deliverable=t1.md duration="4 hours" launched_at="$(iso_ago 60)"
add_row "$R31C" name=T2 deliverable=t2.md duration="4 hours" launched_at="$(iso_ago 30)"
add_row "$R31C" name=T3 deliverable=t3.md duration="4 hours" launched_at="$(iso_ago 30)"
expect_contains "31c0 precondition: both rows are ledgered active" "| active |" "$(grep '^| T3 |' "$P31C")"
S31C_TR="$(s31_transcript "$R31C" "dispatch the batch")"
jq -nc '{type:"assistant",isSidechain:false,
         message:{role:"assistant",content:[
           {type:"tool_use",id:"toolu_1",name:"Agent",input:{name:"T2",prompt:"row T2"}},
           {type:"tool_use",id:"toolu_2",name:"Agent",input:{name:"T3",prompt:"row T3"}}]}}' \
  >> "$S31C_TR"
s31_stop "$R31C" "$S31C_TR"
expect_eq "31c a turn that dispatched both ready rows is not refused" "" "$(s31_decision)"

# ============================================================
section "Section 32: one reader of the current: field, delegated to (wave-19 REQ-6, D7; AC-6.1)"
# ============================================================
#
# ONE PARSER, TWO NAMES. The stop library's fill duty has to know whether this run's ledger is
# live and has no poker to ask, so `payload/scripts/lib/fill.sh` owns the `current:` reader:
# the leading `## SDLC State` section, fence toggle first, CR translated rather than deleted,
# the first `current:` line, whitespace stripped. Until wave-19 this hook carried a second
# parser with the same grammar, because §CG of tests/cross-gate-agreement.test.sh extracted it
# as text; §CG now sources fill.sh beside the extraction, and this hook's
# `_sched_plan_current_field` is a one-line wrapper over the library's reader.
#
# THE WRAPPER STAYS, AND SO DOES THIS SECTION. Calling `_fill_current_field` straight from the
# poker would leave this section driving one function under two names — vacuous. Kept as a
# wrapper, the poker's body is extracted exactly as §CG extracts it and driven beside the
# library over one table of shapes, so a wrapper that drops or reorders its argument turns
# the table red (32m proves it on a mutant), and 32p pins that the body parses nothing itself.

S32_LIB_DIR="$(cd "${BIONIC_HOOKS_DIR}/../payload/scripts/lib" 2>/dev/null && pwd -P)" \
  || S32_LIB_DIR="$(cd "${BIONIC_HOOKS_DIR}/../scripts/lib" && pwd -P)"

s32_extract() {  # <poker file> -> the text of its _sched_plan_current_field, as §CG extracts it
  awk '$0 ~ "^_sched_plan_current_field\\(\\)" {f=1} f{print; if ($0=="}") exit}' "$1"
}
s32_poker_read() {  # <plan> [poker file] -> _sched_plan_current_field's answer, extracted and eval'd
  ( . "$S32_LIB_DIR/run.sh" >/dev/null 2>&1      # normalize_newlines is run.sh's
    . "$S32_LIB_DIR/fill.sh" >/dev/null 2>&1     # the reader the wrapper delegates to
    eval "$(s32_extract "${2:-$POKER}")"
    _sched_plan_current_field "$1" ) 2>/dev/null
}
s32_fill_read() {  # <plan> -> _fill_current_field's answer, from the library itself
  ( . "$S32_LIB_DIR/fill.sh" >/dev/null 2>&1; _fill_current_field "$1" ) 2>/dev/null
}

s32_plan() {  # <label> <body...> -> a plan path carrying exactly the bytes given
  local f="$TMPROOT/s30-$1.plan.md"; shift
  mkdir -p "$(dirname "$f")"
  printf '%s' "$1" > "$f"
  printf '%s' "$f"
}

# The shapes: an ordinary value, the sub-step letter, task scale, a fenced decoy ahead of the
# real section, a second `## ` heading closing the section, a `current:` that lives only
# inside the fence, no section at all, and a CR-only file (the line-ending case both readers
# translate rather than delete).
S32_LF='# p

## SDLC State

current: 4

- Step 4: in progress
'
S32_T='# p

## SDLC State

current: T7
'
S32_FENCED='# p

```
## SDLC State

current: 9
```

## SDLC State

current: 5
'
S32_ONLY_FENCED='# p

```
## SDLC State

current: 9
```

## Tasks

| id |
'
S32_CLOSED='# p

## SDLC State

- Step 4: in progress

## Tasks

current: 7
'
S32_NOSECTION='# p

current: 4
'
S32_SUBSTEP='# p

## SDLC State

current: 3b
'

s32_row() {  # <label> <body> <expected>
  local f; f="$(s32_plan "$1" "$2")"
  local a b
  a="$(s32_poker_read "$f")"
  b="$(s32_fill_read "$f")"
  expect_eq "32 the poker reads $1 as <$3>" "$3" "$a"
  expect_eq "32 …and fill.sh answers the same on $1" "$a" "$b"
}

s32_row "plain" "$S32_LF" "4"
s32_row "substep" "$S32_SUBSTEP" "3b"
s32_row "task-scale" "$S32_T" "T7"
s32_row "fenced-decoy" "$S32_FENCED" "5"
s32_row "only-fenced" "$S32_ONLY_FENCED" ""
s32_row "closed-section" "$S32_CLOSED" ""
s32_row "no-section" "$S32_NOSECTION" ""

# CR-only, the classic-Mac shape: a reader that DELETED the carriage returns would see one
# line and answer nothing, and both of these translate instead.
S32_CR="$(printf '# p\r\r## SDLC State\r\rcurrent: 6\r')"
s32_row "cr-only" "$S32_CR" "6"

# A path that is not a file at all — the silent, empty answer both give.
expect_eq "32 the poker answers nothing for a missing plan" "" "$(s32_poker_read "$TMPROOT/s30-absent.md")"
expect_eq "32 …and so does fill.sh" "" "$(s32_fill_read "$TMPROOT/s30-absent.md")"

# 32p: ONE PARSER. The poker's body delegates and parses nothing itself — a body that grew its
# own awk back would be the second reader AC-6.1 retires, agreeing today and drifting later.
S32_BODY="$(s32_extract "$POKER")"
expect_contains "32p the poker's reader delegates to fill.sh's" "_fill_current_field" "$S32_BODY"
expect_absent "32p …and runs no parse of its own (no awk)" "awk" "$S32_BODY"
expect_absent "32p …(no grep)" "grep" "$S32_BODY"

# 32m: THE TABLE CAN GO RED. A mutant poker whose wrapper drops its argument answers nothing
# for the plain shape, so the agreement rows above discriminate a broken delegation.
S32_MUT="$TMPROOT/s32-poker-dropped-arg.sh"
LC_ALL=C awk '{ if ($0 ~ /^  _fill_current_field "\$@"/) print "  _fill_current_field"; else print }' \
  "$POKER" > "$S32_MUT"
expect_eq "32m the mutant differs from the shipped poker by exactly the wrapper line" \
  "1" "$(diff "$POKER" "$S32_MUT" | grep -c '^< ')"
expect_eq "32m …and its reader answers nothing on the plain shape (the table would go red)" \
  "" "$(s32_poker_read "$(s32_plan plain "$S32_LF")" "$S32_MUT")"


# ============================================================
section "Section 33: the stop acks its row, and the quiet read follows the adopter (wave-19 T1; REQ-1 AC-1.1, REQ-2 AC-2.1/2.2; D2, D4; ADR-034)"
# ============================================================
#
# THE ACK IS THE CLOSE (ADR-034 d1). A `landing-swept/v1` marker records that a landing was
# SEEN; it is not a second terminal state. The STANDDOWN close used to skip every name that
# carried one — which is every writer that declared an artifact and reached SubagentStop — so
# exactly the rows that landed normally were never acked (ideas row 16; R1 F1, bed3/bed2). The
# close now skips only a name already acked, and writes `--reason landed` for a row that
# declared a deliverable; `moot-and-gone` stays for a row that declared nothing.
#
# THE QUIET READ FOLLOWS THE ADOPTER (D4). An adopted row's `adopted_from=` names the session
# that LAUNCHED it; the harness files the agent's transcript under whichever session is
# talking to it now. `row_quiet` reads this session's subagents dir first and falls back to the
# launcher's; `adopted_from=` itself is provenance and never rewritten (R1 Q4, bed3's false
# NOTIFY reproduced).
S33_CFG="$(fake_config_dir s33-ack-close)"
export CLAUDE_CONFIG_DIR="$S33_CFG"
s33_answer() {  # <state> <name[:status]>...
  plant_answer "$S33_CFG/projects/-fixture-project/$SID.jsonl" "$@"
}
s33_ledger() { cat "$(ack_ledger_of "$1")" 2>/dev/null; }

# ---------- 33a: the bed3/bed2 shape — two MET rows, one swept, a fresh panel naming neither ----------
R33A="$(make_repo s33-bed3)"; new_roster "$R33A"
mkdir -p "$R33A/.bionic/docs/record"
echo done > "$R33A/.bionic/docs/record/swept.md"
echo done > "$R33A/.bionic/docs/record/plain.md"
add_row "$R33A" name=swept-row status=identified agent_id=aswept00000000000000000 \
  deliverable="$R33A/.bionic/docs/record/swept.md" duration="1 hour" launched_at="$(iso_ago 600)" \
  "$(said "$R33A" swept-row)"
add_row "$R33A" name=plain-row status=identified agent_id=aplain00000000000000000 \
  deliverable="$R33A/.bionic/docs/record/plain.md" duration="1 hour" launched_at="$(iso_ago 600)" \
  "$(said "$R33A" plain-row)"
swept_marker_write "$(roster_of "$R33A")" "$(iso_ago 30)" "$SID" swept-row aswept00000000000000000 MET
s33_answer fresh "some-other-agent:running"
poke "$R33A" tick
expect_eq "33a the tick exits 0" "0" "$RC"
expect_contains "33a a SWEPT MET row gone from a fresh panel is acked, reason landed (AC-1.1)" \
  "|name=swept-row|by=patrol|reason=landed" "$(s33_ledger "$R33A")"
expect_contains "33a2 …and the unswept MET row beside it too, reason landed" \
  "|name=plain-row|by=patrol|reason=landed" "$(s33_ledger "$R33A")"
expect_contains "33a3 …which the one verdict line now reports closed" "|acked=yes|" \
  "$( cd "$R33A" && CLAUDE_CODE_SESSION_ID="$SID" bash "$SWEEPER_FOR_ACK" verdict swept-row 2>/dev/null )"
poke "$R33A" tick
expect_eq "33a4 the next tick acks neither a second time" "2" \
  "$(grep -c '|event=ack|' "$(ack_ledger_of "$R33A")" 2>/dev/null | tr -d ' ')"

# ---------- 33b: the same swept row STILL on the panel — stood down, never acked ----------
R33B="$(make_repo s33-swept-live)"; new_roster "$R33B"
mkdir -p "$R33B/.bionic/docs/record"
echo done > "$R33B/.bionic/docs/record/swept.md"
add_row "$R33B" name=swept-row status=identified agent_id=aswept00000000000000001 \
  deliverable="$R33B/.bionic/docs/record/swept.md" duration="1 hour" launched_at="$(iso_ago 600)" \
  "$(said "$R33B" swept-row)"
swept_marker_write "$(roster_of "$R33B")" "$(iso_ago 30)" "$SID" swept-row aswept00000000000000001 MET
s33_answer fresh "swept-row:idle"
poke "$R33B" tick
expect_contains "33b a swept row the panel still lists is stood down" "poker: STANDDOWN swept-row" "$OUT"
expect_contains "33b2 …with the order written" "|by=patrol|target=swept-row" \
  "$(cat "$R33B/.bionic/tmp/stop-orders-$SID.state" 2>/dev/null)"
expect_eq "33b3 …and it is NOT acked while its agent is on the panel" "no" \
  "$([ -f "$(ack_ledger_of "$R33B")" ] && echo yes || echo no)"

# ---------- 33c: a row that declared NOTHING keeps moot-and-gone ----------
R33C="$(make_repo s33-declared-nothing)"; new_roster "$R33C"
add_row "$R33C" name=bare-row status=identified agent_id=abare000000000000000000 \
  duration="1 hour" launched_at="$(iso_ago 600)" "$(said "$R33C" bare-row)"
s33_answer fresh "some-other-agent:running"
poke "$R33C" tick
expect_contains "33c a MET row that declared no deliverable is closed moot-and-gone" \
  "|name=bare-row|by=patrol|reason=moot-and-gone" "$(s33_ledger "$R33C")"
expect_absent "33c2 …never as landed: nothing was produced to land" \
  "reason=landed" "$(s33_ledger "$R33C")"

# ---------- 33d: the adopted row's quiet read — the bed3 false-NOTIFY shape (AC-2.1) ----------
#
# One OPEN row (deliverable absent, so UNMET and the cadence read runs) adopted from a
# predecessor. The predecessor's transcript is 5400 s old; the adopting session's is fresh.
S33_PRED="d6d6d6d6-1111-4bbb-8ccc-000000000033"
S33_ID="aadopt33000000000000000"
s33_adopted() {  # <label> -> repo with one adopted UNMET row
  local r; r="$(make_repo "s33-$1")"; new_roster "$r"
  mkdir -p "$r/.bionic/docs/record"
  add_row_to "$r" "$S33_PRED" name=w1 status=identified agent_id="$S33_ID" \
    subagent_type=bionic:senior-implementor deliverable="$r/.bionic/docs/record/never.md" \
    duration="4 hours" cadence="10 minutes" launched_at="$(iso_ago 6000)"
  printf '%s' "$r"
}
S33_PRED_TX="$S33_CFG/projects/-fixture-project/$S33_PRED/subagents/agent-${S33_ID}.jsonl"
S33_OWN_TX="$S33_CFG/projects/-fixture-project/$SID/subagents/agent-${S33_ID}.jsonl"
mkdir -p "$(dirname "$S33_PRED_TX")" "$(dirname "$S33_OWN_TX")"

R33D="$(s33_adopted adopt-live)"
: > "$S33_PRED_TX"; : > "$S33_OWN_TX"
poke "$R33D" adopt
S33_ROW_ADOPTED="$(grep "^${ROSTER_ROW_SCHEMA}|" "$(roster_of "$R33D")" | grep -F "|name=w1|")"
expect_contains "33d meta: the row really was adopted, provenance the predecessor" \
  "adopted_from=$S33_PRED" "$S33_ROW_ADOPTED"
backdate "$S33_PRED_TX" 5400
touch "$S33_OWN_TX"
s33_answer fresh "w1:running"
poke "$R33D" tick
expect_absent "33d an adopted row whose transcript under THIS session is fresh is not NOTIFYed (AC-2.1)" \
  "rows=w1" "$OUT"
expect_absent "33d2 …and the predecessor's stale path is not the one read" \
  "$S33_PRED_TX" "$OUT"

# ---------- 33e: the reverse — RE-AUTHORED under D8 (REQ-8; epic-23 wave-20 T5) ----------
#
# SUPERSEDES T1d's "this session's dir first" preference (walk W-3). Before D8, THIS
# session's own copy won regardless of age — a stale own copy alone forced NOTIFY even
# with a fresher copy sitting under the predecessor. `agent_log_newest` reads NEWEST,
# anywhere in the project: research D2 §REQ-8 named exactly this flip ("the flipped case,
# launcher newer than adopter, which this session's copy wins today and loses under
# newest-first — that case is the reason for 'newest'"). So the predecessor's FRESHER copy
# now keeps the row alive even though this session's own copy is 5400 s old.
R33E="$(s33_adopted adopt-reverse)"
: > "$S33_PRED_TX"; : > "$S33_OWN_TX"
poke "$R33E" adopt
touch "$S33_PRED_TX"
backdate "$S33_OWN_TX" 5400
s33_answer fresh "w1:running"
poke "$R33E" tick
expect_contains "33e under newest-first the PREDECESSOR's fresher copy keeps it alive (D8 supersedes T1d)" \
  "decision=QUIET" "$OUT"
expect_absent "33e2 …never NOTIFYed for this session's own stale copy alone" \
  "quieter than the declared cadence" "$OUT"

# ---------- 33f: nothing under this session — the launcher's dir is the fallback ----------
R33F="$(s33_adopted adopt-fallback)"
rm -f "$S33_OWN_TX"; : > "$S33_PRED_TX"
poke "$R33F" adopt
backdate "$S33_PRED_TX" 5400
s33_answer fresh "w1:running"
poke "$R33F" tick
expect_contains "33f with no file under this session the predecessor's path is still read" \
  "$S33_PRED_TX" "$OUT"
expect_contains "33f2 …and its staleness still notifies" "decision=NOTIFY" "$OUT"

# ---------- 33g: adopted_from= is provenance — byte-identical across a tick and a re-adopt ----------
S33_ROW_AFTER="$(grep "^${ROSTER_ROW_SCHEMA}|" "$(roster_of "$R33D")" | grep -F "|name=w1|")"
poke "$R33D" adopt
S33_ROW_READOPT="$(grep "^${ROSTER_ROW_SCHEMA}|" "$(roster_of "$R33D")" | grep -F "|name=w1|")"
expect_eq "33g the adopted row is byte-identical after a tick" "$S33_ROW_ADOPTED" "$S33_ROW_AFTER"
expect_eq "33g2 …and after a second adopt (idempotent, adopted_from= never rewritten)" \
  "$S33_ROW_ADOPTED" "$S33_ROW_READOPT"

# ---------- 33h: an INTERMEDIATE adopter's copy is found by the newest-id glob (D8, REQ-8, AC-8.2) ----------
#
# THE DEFECT (research D2 §REQ-8; triage-A). `row_quiet` used to check only THIS session's
# subagents directory, then the row's own `adopted_from=` — never a THIRD session that
# adopted the agent in between two `/clear`s. `adopted_from=` keeps naming the ORIGINAL
# launcher forever, so an intermediate adopter's own copy of the log is named on no row at
# all, and the Patrol reported a working agent quieter than its declared cadence against a
# path frozen since the launch.
#
# THE FIX. `agent_log_newest` globs every session directory of the project for the exact
# agent id and returns the newest by mtime, so the launcher, any intermediate adopter and
# this session are all equally candidates — no chain of `adopted_from=` to walk.
S33_INTER="e7e7e7e7-3333-4ddd-8eee-000000000034"
S33_INTER_TX="$S33_CFG/projects/-fixture-project/$S33_INTER/subagents/agent-${S33_ID}.jsonl"
mkdir -p "$(dirname "$S33_INTER_TX")"

R33H="$(s33_adopted adopt-intermediate)"
: > "$S33_PRED_TX"; rm -f "$S33_OWN_TX"
poke "$R33H" adopt
backdate "$S33_PRED_TX" 5400
# THE INTERMEDIATE ADOPTER's own copy — under a THIRD session this roster row names
# nowhere — FRESH.
: > "$S33_INTER_TX"
s33_answer fresh "w1:running"
poke "$R33H" tick
expect_absent "33h a row whose newest copy sits under an INTERMEDIATE adopter is not NOTIFYed" \
  "quieter than the declared cadence" "$OUT"
expect_absent "33h2 …the launcher's stale path never decided this tick's verdict" \
  "$S33_PRED_TX" "$OUT"
expect_absent "33h3 …and no NOTIFY names this row" "rows=w1" "$OUT"

unset CLAUDE_CONFIG_DIR

# ============================================================
section "Section 34: task-add — a schedule change is a transaction (wave-20 REQ-5, AC-5.3; Δ5)"
# ============================================================
#
# `task-add <id> <step> <kind> <task> <agent> <deps> <size> <serves> <Files>` — the table's
# own column order, the nine cells an author writes (status, worktree and base are the
# dispatcher's). It projects the row onto a COPY of the bound plan (`units_add_row`: the row,
# its `- <id>:` line, and no other row), runs
# `units_validate` on the copy and a dry commit through the REAL hooks/bash-walls.sh, and only
# then moves the copy over the plan. On any refusal the plan is byte-identical and the words
# that refused it print. AC-5.3 fails-when: "after task-add of a Step-4 row mid-run the next
# writer commit is refused for a dependency the verb should have written, or a refused add
# changes the plan".
#
# THE FIXTURE IS A PLAN THE REAL GATE ADMITS: audited, multi_agent, use_worktree, a Step-4
# block with its three fields, a `- T<n>:` line per row, and a matrix whose row carries its
# `fails-when:`. S34_GATE drives the same gate on a plan exactly as a session bound to it
# would, so the hand-edited control below is judged by the wall the verb dry-runs.
s34_plan() {  # <repo> <current> [step-4 block body] -> the plan path; the session is bound to it
  local repo="$1" cur="$2" block="${3:-}" f
  f="$repo/.bionic/docs/plans/epic-99-fixture/wave-01-fixture.plan.md"
  mkdir -p "$(dirname "$f")" "$repo/.bionic/docs/specs/epic-99-fixture"
  printf '# requirements\n' > "$repo/.bionic/docs/specs/epic-99-fixture/wave-01-fixture.requirements.md"
  printf '# spec\n' > "$repo/.bionic/docs/specs/epic-99-fixture/wave-01-fixture.spec.md"
  [ -n "$block" ] || block='  worktree: .worktrees/01-fixture
  base-sha: abc1234
  branch: wave/01-fixture'
  {
    printf -- '---\ngoverning-skill: canonical-sdlc\ncanonical_sdlc_version: 14\nintent: bugfix\n'
    printf 'rigor: audited\nscale: wave\nmulti_agent: true\nuse_worktree: true\nhas_ui: false\n'
    printf 'walk: exempt\ndeploy_target: n/a\n'
    printf 'parallel-budget: writers=8 suites=4 worktrees=32 test_jobs=8 source=probe\n---\n\n'
    printf '# fixture wave\n\n## SDLC State\n\ncurrent: %s\n' "$cur"
    printf 'approved-by: fixture 2026-09-23T00:00Z "approved"\n\n'
    printf -- '- Step 1: requirements: specs/epic-99-fixture/wave-01-fixture.requirements.md\n'
    printf -- '- Step 2: spec: specs/epic-99-fixture/wave-01-fixture.spec.md\n'
    printf -- '- Step 3: plan: plans/epic-99-fixture/wave-01-fixture.plan.md\n'
    printf -- '- Step 4: opened\n%s\n' "$block"
    [ "$cur" = 5 ] && printf -- '- Step 5: (pending)\n'
    printf -- '- T1: landed at record/T1.md\n- T2: dispatched to w-T2\n- T5: pending dispatch — .worktrees/01-T5\n\n'
    printf '## Tasks\n\n'
    printf '| id | step | kind | task | agent | deps | size | serves | Files | worktree | base | status |\n'
    printf '|---|---|---|---|---|---|---|---|---|---|---|---|\n'
    printf '| T1 | 4 | build | the first build | implementor | — | 30 | REQ-1 | a.sh | — | — | landed |\n'
    printf '| T2 | 4 | build | the second build | implementor | — | 30 | REQ-1 | b.sh | 01-T2 | abc1234 | active |\n'
    printf '| T5 | 5 | verify | the floor | test-runner | T1, T2 | 30 | REQ-1 | — | — | — | pending |\n\n'
    printf '## Verification Matrix\n\n| AC | tier | status | evidence | auditor |\n|---|---|---|---|---|\n'
    printf '| AC-1.1 | T2 | pending | — | — |\n\nAC-1.1:\n  provenance: fixture\n  fails-when: the fixture is wrong\n'
  } > "$f"
  bound_marker "$repo" "$SID" "$f" >/dev/null 2>&1
  printf '%s' "$f"
}

# S34_GATE <repo> -> rc of the REAL commit gate on a main-root `git commit` in this session.
s34_gate() {
  local repo="$1" input
  input="$(jq -n --arg s "$SID" --arg cwd "$repo" '{session_id: $s, cwd: $cwd,
    hook_event_name: "PreToolUse", tool_name: "Bash",
    tool_input: {command: "git commit -m x"}, tool_use_id: "toolu_s34"}')"
  GATE_ERR="$( cd "$repo" && CLAUDE_PROJECT_DIR="" CLAUDE_CODE_SESSION_ID="$SID" BIONIC_WALL_VERBOSE=1 \
    bash "${BIONIC_HOOKS_DIR}/bash-walls.sh" <<< "$input" 2>&1 >/dev/null )"
  GATE_RC=$?
}

# The verb runs the whole commit gate once per call; on a loaded machine that is longer than
# the bound the tick's rows are held to, so this section widens it and restores it after.
S34_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180

# ---------- 34a: the fixture is admitted as it stands (the control every row below leans on) ----------
R34A="$(make_repo s34-add)"; ( cd "$R34A" && git commit -q --allow-empty -m init )
P34A="$(s34_plan "$R34A" 4)"
s34_gate "$R34A"
expect_eq "34a the fixture plan is admitted by the real commit gate before any add" "0" "$GATE_RC"

# ---------- 34b: AC-5.3 — a Step-4 row added mid-run, and the next commit admitted ----------
poke "$R34A" task-add T6 4 build 'the fixup found mid-run' bionic:implementor '—' 30 REQ-5 'lib/c.sh'
expect_eq "34b task-add of a Step-4 row exits 0" "0" "$RC"
expect_contains "34b2 …and says what it did" "task-add — T6 added" "$OUT"
# THE GRAMMAR SPOKE AND ADMITTED (wave-20 T9, Δ10): the Files operand is a path the dispatch
# wall's lift reads. This fixture repo configures no impact command, which a dispatch carrying
# only this Files: line would be refused for — a fact about the repository, answered at
# dispatch by a Suites: line the plan row has no column for, so here it is a note.
expect_contains "34b2g …and the repository-level grammar fact is a note, not a refusal" \
  "poker: note: no impact command is configured here" "$OUT"
expect_contains "34b3 …the row is in the plan, pending" \
  "| T6 | 4 | build | the fixup found mid-run | bionic:implementor | — | 30 | REQ-5 | lib/c.sh | — | — | pending |" "$(cat "$P34A")"
expect_contains "34b4 …with its - T6: line" "- T6: pending dispatch — added by task-add" "$(cat "$P34A")"
# THREADED, AS IN 1.10, BECAUSE THIS TABLE HAS NO reads COLUMN (wave-26 T62; critic 2 K2-F1).
# The validator no longer demands the edge (D2), but with no head read for the floor the deps
# task-add writes are the one thing that holds it behind a late build.
expect_contains "34b5 …and threaded into the Step-5 row's deps (a table without reads)" \
  "| T5 | 5 | verify | the floor | test-runner | T1, T2, T6 |" "$(cat "$P34A")"
s34_gate "$R34A"
expect_eq "34b6 AC-5.3 the next commit is admitted: no dependency the verb should have written is missing" \
  "0" "$GATE_RC"

# ---------- 34c: the same row hand-added, with no threading, is ADMITTED (wave-26 T2, D2) ----------
# Through 1.10 this was the control that the verb's threading was needed: the hand edit was
# refused for the Step-4 prerequisite it did not write into T5. The rule is removed, so the
# same gate admits the same edit.
R34C="$(make_repo s34-hand)"; ( cd "$R34C" && git commit -q --allow-empty -m init )
P34C="$(s34_plan "$R34C" 4)"
awk '{ print }
     /^\| T5 \| 5 \|/ { print "| T6 | 4 | build | the fixup, hand-added | implementor | — | 30 | REQ-5 | lib/c.sh | — | — | pending |" }
     /^- T5: / { print "- T6: pending dispatch — by hand" }' "$P34C" > "$P34C.tmp" && mv "$P34C.tmp" "$P34C"
s34_gate "$R34C"
expect_eq "34c the hand-added row with no threading is admitted by the same gate" "0" "$GATE_RC"
expect_contains "34c2 …with T5's deps cell as its author wrote it" \
  "| T5 | 5 | verify | the floor | test-runner | T1, T2 |" "$(cat "$P34C")"

# ---------- 34d: a later-step row that names one build row is ADMITTED (wave-26 T2, D2) ----------
# It used to be refused for the Step-4 rows it did not reach. Admitted now, the plan changes only
# by that row and its line; the refusal rows below re-take the checksum after it.
poke "$R34A" task-add T7 5 verify 'a second floor, unthreaded' test-runner 'T1' 30 REQ-5 '—'
expect_eq "34d a Step-5 row naming one build row is admitted (exit 0)" "0" "$RC"
expect_contains "34d2 …the row is in the plan with the deps its author wrote" \
  "| T7 | 5 | verify | a second floor, unthreaded | test-runner | T1 |" "$(cat "$P34A")"
expect_contains "34d3 …and no other row's deps changed (a Step-5 add threads nothing)" \
  "| T5 | 5 | verify | the floor | test-runner | T1, T2, T6 |" "$(cat "$P34A")"
SUM34="$(cksum < "$P34A")"

poke "$R34A" task-add T6 4 build 'the same id again' implementor '—' 30 REQ-5 'lib/d.sh'
expect_eq "34d4 a duplicate id is refused" "1" "$RC"
expect_eq "34d5 …the plan is byte-identical" "$SUM34" "$(cksum < "$P34A")"
expect_contains "34d6 …naming the duplicate" "T6: duplicate id" "$OUT"

poke "$R34A" task-add T8 4 build 'a dep nobody defines' implementor 'T99' 30 REQ-5 'lib/e.sh'
expect_eq "34d7 a dep naming no row is refused, the plan unchanged" "1 $SUM34" "$RC $(cksum < "$P34A")"

# ---------- 34d8: THE FILES OPERAND IS JUDGED BY THE DISPATCH GRAMMAR (wave-20 T9; D4, Δ10) ----------
# task-add used to write its Files cell with no check at all (T6 carry-over). A cell the
# dispatch wall's lift reads as no path — a template slot, a bare word — is a row whose
# brief could never be admitted with that Files: line; the verb refuses it, in the grammar's
# own words, and the plan is byte-identical.
poke "$R34A" task-add T8 4 build 'a template for Files' implementor '—' 30 REQ-5 '<path>/x.sh'
expect_eq "34d8 a Files operand the grammar reads as no path is REFUSED (exit 1)" "1" "$RC"
expect_contains "34d9 …in the dispatch wall's words" "declares no Files:" "$OUT"
expect_eq "34d10 …and the plan is byte-identical" "$SUM34" "$(cksum < "$P34A")"
poke "$R34A" task-add T8 4 build 'a bare word for Files' implementor '—' 30 REQ-5 'CHANGELOG'
expect_eq "34d11 a bare word is REFUSED too, the plan unchanged" "1 $SUM34" "$RC $(cksum < "$P34A")"

# ---------- 34e: refused by the GATE, not the validator — the dry run is real ----------
# The row is valid, but the plan's Step-4 block has lost its base-sha: the validator is
# silent and the commit gate refuses. The verb must hear the gate, not only the validator.
R34E="$(make_repo s34-gate)"; ( cd "$R34E" && git commit -q --allow-empty -m init )
P34E="$(s34_plan "$R34E" 4 '  worktree: .worktrees/01-fixture
  branch: wave/01-fixture')"
SUM34E="$(cksum < "$P34E")"
poke "$R34E" task-add T6 4 build 'a valid row on a plan the gate refuses' implementor '—' 30 REQ-5 'lib/c.sh'
expect_eq "34e a valid row on a plan the commit gate refuses exits 1" "1" "$RC"
expect_eq "34e2 …the plan is byte-identical" "$SUM34E" "$(cksum < "$P34E")"
expect_contains "34e3 …and the gate's own words print" "bionic: commit refused" "$OUT"
expect_contains "34e4 …naming the field it wants" "base-sha" "$OUT"

# ---------- 34f: mid-Verify — the dry commit is a writer's, judged by the task arms ----------
# At current: 5 the Step-5 block is still pending, so a main-root commit would be refused for
# it. A writer's commit from a Step-4 row's tree is judged at Step 4, and that commit is the
# one AC-5.3 names — so the verb's dry run must be judged there too, or no row could ever be
# added during Verify, which is when fixups are found.
R34F="$(make_repo s34-verify)"; ( cd "$R34F" && git commit -q --allow-empty -m init )
P34F="$(s34_plan "$R34F" 5)"
poke "$R34F" task-add T6 4 build 'a fixup found during Verify' implementor '—' 30 REQ-5 'lib/c.sh'
expect_eq "34f a Step-4 row added at current: 5 is admitted" "0" "$RC"
expect_contains "34f2 …and written, current: untouched" "current: 5" "$(cat "$P34F")"
expect_contains "34f3 …with the row" "| T6 | 4 | build | a fixup found during Verify |" "$(cat "$P34F")"

# ---------- 34g: the refusals that precede any projection ----------
poke "$R34A" task-add T9 4 build
expect_eq "34g a short argument list is a usage error (exit 2)" "2" "$RC"

R34G="$(make_repo s34-unbound)"; ( cd "$R34G" && git commit -q --allow-empty -m init )
P34G="$(s34_plan "$R34G" 4)"; engage "$R34G"      # re-engaged EMPTY: the session is unbound
SUM34G="$(cksum < "$P34G")"
poke "$R34G" task-add T6 4 build 'onto no bound plan' implementor '—' 30 REQ-5 'lib/c.sh'
expect_eq "34g2 an unbound session is refused and the newest plan is not written" "1 $SUM34G" "$RC $(cksum < "$P34G")"
expect_contains "34g3 …saying why" "bound" "$OUT"

R34H="$(make_repo s34-step3)"; ( cd "$R34H" && git commit -q --allow-empty -m init )
P34H="$(s34_plan "$R34H" 3)"
SUM34H="$(cksum < "$P34H")"
poke "$R34H" task-add T6 4 build 'before approval' implementor '—' 30 REQ-5 'lib/c.sh'
expect_eq "34g4 a plan below current: 4 is refused, unchanged" "1 $SUM34H" "$RC $(cksum < "$P34H")"

unengage "$R34A"
poke "$R34A" task-add T9 4 build 'unengaged' implementor '—' 30 REQ-5 'lib/f.sh'
expect_contains "34g5 an unengaged session decides nothing" "NOT-ENGAGED" "$OUT"
engage "$R34A"

# ---------- 34h: nothing is left behind ----------
expect_eq "34h no projection copy is left beside any plan" "" \
  "$(find "$R34A" "$R34E" "$R34F" -name '*task-add*' 2>/dev/null)"
expect_eq "34h2 …and no dry-run engagement marker is left in .bionic/tmp" "" \
  "$(find "$R34A/.bionic/tmp" "$R34E/.bionic/tmp" "$R34F/.bionic/tmp" -name 'engaged-*' ! -name "engaged-$SID.state" 2>/dev/null)"
POKE_BOUND="$S34_BOUND_WAS"

# ============================================================
section "Section 35: fill-report — missed opportunity, HOLD and declines, from the fill ledger (wave-20 REQ-5, AC-5.6; Δ2)"
# ============================================================
#
# THE MEASURE (ADR-036 decision 4). Every Stop of an engaged run appends a `fill-ledger/v1`
# line; `fill-report` folds the lines by turn key (the last line of a turn wins — a refused
# Stop and its re-entry are one turn), orders them by `at`, and gives each line the interval
# up to the next. Missed minutes are the intervals whose line is `state=ok`, `missed>0` and
# undeclined; HOLD minutes are `state=hold|emergency` with a row ready; declined minutes are
# listed per reason. While the run is open the last line's interval runs to now; once it is
# closed, nothing after the last line is counted.
#
# THE FIXTURE: 10 minutes missed and 5 of HOLD, with a superseded line inside the missed turn
# (at 10:02, missed=1) that an unfolded sum would count as 3.5 more minutes.
s35_iso_epoch() {  # <ISO Z> -> epoch seconds, BSD or GNU date
  date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$1" +%s 2>/dev/null || date -u -d "$1" +%s
}
s35_line() {  # <at> <turn> <state> <ready> <launched> <declined> <missed>
  printf 'fill-ledger/v1|at=%s|session=%s|turn=%s|current=5|state=%s|ceiling=8|width=8|open=2|free=6|ready=%s|launched=%s|declined=%s|missed=%s\n' \
    "$1" "$SID" "$2" "$3" "$4" "$5" "$6" "$7"
}
s35_fixture() {  # <repo> <last line's missed> -> the plan path; writes plan + ledger
  local r="$1" plan led
  plan="$(plan_at "$r" epic-99-fixture/wave-35-fill.plan.md "$(plan_body 5)")"
  led="$r/.bionic/docs/record/wave-35-fill/fill-ledger.log"
  mkdir -p "${led%/*}"
  {
    s35_line 2026-09-23T10:00:00Z u-t1 ok ''    W-T1 ''          0
    s35_line 2026-09-23T10:02:00Z u-t2 ok T2    ''   ''          1
    s35_line 2026-09-23T10:05:30Z u-t2 ok T2    ''   ''          1
    s35_line 2026-09-23T10:15:30Z u-t3 hold T4  ''   ''          1
    s35_line 2026-09-23T10:20:30Z u-t4 ok ''    W-T4 ''          0
    s35_line 2026-09-23T10:25:30Z u-t5 ok T5    ''   'mid-merge' 1
    s35_line 2026-09-23T10:30:30Z u-t6 ok T6    ''   ''          "$2"
  } > "$led"
  printf '%s' "$plan"
}
S35_NOW="$(( $(s35_iso_epoch 2026-09-23T10:30:30Z) + 120 ))"

R35="$(make_repo s35)"
P35="$(s35_fixture "$R35" 0)"
OUT="$( cd "$R35" && BIONIC_NOW_EPOCH="$S35_NOW" CLAUDE_CODE_SESSION_ID="$SID" bash "$POKER" fill-report "$P35" 2>&1 )"; RC=$?
expect_eq "35a fill-report exits 0" "0" "$RC"
expect_contains "35b AC-5.6 the fixture's 10 missed minutes, exactly" "missed=10|" "$OUT"
expect_contains "35c …and its 5 HOLD minutes, separately" "hold=5|" "$OUT"
expect_contains "35d …and the declined minutes, with their reason" "declined=5|" "$OUT"
expect_contains "35e …the reason listed on its own line" "mid-merge" "$OUT"
expect_contains "35f …the superseded line folded away: six turns, not seven" "turns=6|" "$OUT"
expect_contains "35g …the line is the report's schema" "fill-report/v1|plan=wave-35-fill|" "$OUT"

# 35h: THE OPEN RUN'S LAST INTERVAL RUNS TO NOW. The last line misses one ready row, two minutes
# ago: open, those two minutes are missed; closed, nothing after the last line counts.
R35H="$(make_repo s35h)"
P35H="$(s35_fixture "$R35H" 1)"
OUT="$( cd "$R35H" && BIONIC_NOW_EPOCH="$S35_NOW" CLAUDE_CODE_SESSION_ID="$SID" bash "$POKER" fill-report "$P35H" 2>&1 )"
expect_contains "35h an open run's last interval runs to now: 10 + 2 missed" "missed=12|" "$OUT"
printf '%s' "$(plan_body 9 'delivered: bionic 9.9.9; report: record/x.md')" > "$P35H"
OUT="$( cd "$R35H" && BIONIC_NOW_EPOCH="$S35_NOW" CLAUDE_CODE_SESSION_ID="$SID" bash "$POKER" fill-report "$P35H" 2>&1 )"
expect_contains "35i …and a delivered run's does not: 10 missed" "missed=10|" "$OUT"
expect_contains "35j …and says the run is closed" "open=no" "$OUT"

# 35k: WITH NO OPERAND, the session's own run — the bound plan, as every verb resolves it.
R35K="$(make_repo s35k)"
P35K="$(s35_fixture "$R35K" 0)"
bind_marker "$R35K" "$P35K"
OUT="$( cd "$R35K" && BIONIC_NOW_EPOCH="$S35_NOW" CLAUDE_CODE_SESSION_ID="$SID" bash "$POKER" fill-report 2>&1 )"
expect_contains "35k with no operand the bound run's ledger is read" "plan=wave-35-fill|" "$OUT"
expect_contains "35l …with the same answer" "missed=10|" "$OUT"

# 35m: a plan with no ledger yet says so, and reports zeros rather than failing.
R35M="$(make_repo s35m)"
P35M="$(plan_at "$R35M" epic-99-fixture/wave-36-none.plan.md "$(plan_body 5)")"
poke "$R35M" fill-report "$P35M"
expect_eq "35m a run with no ledger exits 0" "0" "$RC"
expect_contains "35n …and names the file it looked for" "record/wave-36-none/fill-ledger.log" "$OUT"

# 35o: an operand that names no plan is a refusal, exit 2.
poke "$R35M" fill-report "$R35M/no-such.plan.md"
expect_eq "35o a plan that does not exist is refused (exit 2)" "2" "$RC"
poke "$R35M" fill-report a b
expect_eq "35p two operands is a usage error (exit 2)" "2" "$RC"

# 35q: A REFUSED TURN IS ONE TURN IN THE REPORT, END TO END (wave-20 T11b; review R3, critic C1).
# The ledger above is hand-written; this one is written by the REAL stop hook over a transcript
# in the CLI's own shape. One prompt, a launch, a refusal (T2 ready and left out), the Stop
# hook's feedback record — the synthetic user record the CLI writes after every Stop refusal —
# a second launch, and the re-entry Stop. Two ledger lines, one prompt: the report counts one.
S35Q_STOP="$(dirname "$POKER")/stop.sh"
R35Q="$(make_repo s35q)"
P35Q="$(plan_at "$R35Q" epic-99-fixture/wave-35q-refused.plan.md "$(
  printf -- '---\ngoverning-skill: canonical-sdlc\nparallel-budget: writers=8 suites=2 worktrees=8 test_jobs=8 source=probe\n---\n\n'
  plan_body 4
  printf '\n## Tasks\n\n| id | step | kind | task | agent | deps | size | serves | Files | status | worktree |\n'
  printf '|---|---|---|---|---|---|---|---|---|---|---|\n'
  printf '| T1 | 4 | build | first | implementor | — | 30m | REQ-x | a.sh | pending | — |\n'
  printf '| T2 | 4 | build | second | implementor | — | 30m | REQ-x | b.sh | pending | — |\n')")"
bind_marker "$R35Q" "$P35Q"
roster_header > "$R35Q/.bionic/tmp/roster-$SID.state"
S35Q_TR="$R35Q/s35q-transcript.jsonl"
S35Q_RING="$TMPROOT/s35q.ring"; printf '1700000000|80|0|1.0|8\n' > "$S35Q_RING"
s35q_agent() {  # <tool_use id> <name>
  jq -nc --arg i "$1" --arg n "$2" '{type:"assistant",isSidechain:false,message:{role:"assistant",content:[{type:"tool_use",id:$i,name:"Agent",input:{name:$n,description:"task",subagent_type:"bionic:implementor",prompt:"x"}}]}}' >> "$S35Q_TR"
  jq -nc --arg i "$1" '{type:"user",isSidechain:false,message:{role:"user",content:[{type:"tool_result",tool_use_id:$i,is_error:false,content:"Spawned"}]}}' >> "$S35Q_TR"
  roster_row_fixture status=intended session="$SID" name="$2" agent_id="a${2}000000000001" deliverable= \
    >> "$R35Q/.bionic/tmp/roster-$SID.state"
}
s35q_stop() {  # <stop_hook_active true|false> -> the hook's stdout
  jq -nc --arg c "$R35Q" --arg s "$SID" --arg t "$S35Q_TR" --argjson a "$1" \
    '{session_id:$s,transcript_path:$t,cwd:$c,hook_event_name:"Stop",stop_hook_active:$a}' \
    | ( cd "$R35Q" && env CLAUDE_CODE_SESSION_ID="$SID" BIONIC_PRESSURE_RING="$S35Q_RING" \
          BIONIC_NOW_EPOCH=1700000000 bash "$S35Q_STOP" 2>/dev/null )
}
jq -nc '{type:"user",uuid:"u-35q-1",timestamp:"2026-09-23T10:00:00.000Z",isSidechain:false,message:{role:"user",content:"dispatch the batch"}}' > "$S35Q_TR"
s35q_agent toolu_35Q1 W-T1
S35Q_OUT1="$(s35q_stop false)"
expect_contains "35q precondition: the first Stop is refused for the row left out" "Fillable gap" "$S35Q_OUT1"
jq -nc '{type:"user",isMeta:true,uuid:"u-35q-fb",timestamp:"2026-09-23T10:00:30.000Z",isSidechain:false,userType:"external",message:{role:"user",content:"Stop hook feedback:\nbionic: stop refused — rows are ready"}}' >> "$S35Q_TR"
s35q_agent toolu_35Q2 W-T2
s35q_stop true >/dev/null
S35Q_LED="$R35Q/.bionic/docs/record/wave-35q-refused/fill-ledger.log"
expect_eq "35q …the two Stops wrote two ledger lines" "2" "$(grep -c '^fill-ledger/v1|' "$S35Q_LED" 2>/dev/null)"
OUT="$( cd "$R35Q" && BIONIC_NOW_EPOCH="$S35_NOW" CLAUDE_CODE_SESSION_ID="$SID" bash "$POKER" fill-report "$P35Q" 2>&1 )"
expect_contains "35r T11b fill-report folds the refused turn's two lines into one turn" "turns=1|" "$OUT"
expect_contains "35s …and the turn's final line is the one that saw both launches: nothing missed" \
  "|launched=W-T1,W-T2|" "$(tail -n 1 "$S35Q_LED" 2>/dev/null)"

# ---------- §REPORT (wave-26 T16, D17; AC-6.8): idle minutes and peak width, from stamps the code wrote ----------
#
# The ledger line ends with `idle=` (the ready rows no launch and no decline covered while a slot was
# free) and `room=`; `fill-report` adds `idle minutes: <n>` (the interval from a line whose idle= is
# non-empty to the next line, once per interval) and `peak width: <n>` (the most roster rows open at
# one instant: `launched_at` to the sweeper ledger's ack stamp, the one close rule; no ack, open to now).
#
# THE FIXTURE: idle=T2 at 10:00, then a 12-minute interval to 10:12 (an 8-minute one after it has
# idle= empty and counts nothing). Four roster rows: A 10:00-10:10, B 10:05-10:15, C 10:08-open,
# D 10:20-open. Three are open at 10:08-10:10 and never more, so the peak is 3: four rows launched
# would read 4, and the two open now would read 2.
s35r_line() {  # <at> <turn> <idle> <room>
  printf 'fill-ledger/v1|at=%s|session=%s|turn=%s|current=5|state=ok|ceiling=8|width=8|open=2|free=%s|ready=T2|launched=|declined=|missed=1|idle=%s|room=%s\n' \
    "$1" "$SID" "$2" "$4" "$3" "$4"
}
R35R="$(make_repo s35r)"
P35R="$(plan_at "$R35R" epic-99-fixture/wave-35-rp.plan.md "$(plan_body 5)")"
L35R="$R35R/.bionic/docs/record/wave-35-rp/fill-ledger.log"
mkdir -p "${L35R%/*}"
{
  s35r_line 2026-09-23T10:00:00Z u-r1 T2 3
  s35r_line 2026-09-23T10:12:00Z u-r2 ''  2
  s35r_line 2026-09-23T10:20:00Z u-r3 ''  0
} > "$L35R"
new_roster "$R35R"
add_row_to "$R35R" "$SID" name=rp-a launched_at=2026-09-23T10:00:00Z
add_row_to "$R35R" "$SID" name=rp-b launched_at=2026-09-23T10:05:00Z
add_row_to "$R35R" "$SID" name=rp-c launched_at=2026-09-23T10:08:00Z
add_row_to "$R35R" "$SID" name=rp-d launched_at=2026-09-23T10:20:00Z
s20_ack "$R35R" rp-a 2026-09-23T10:10:00Z
s20_ack "$R35R" rp-b 2026-09-23T10:15:00Z
OUT="$( cd "$R35R" && BIONIC_NOW_EPOCH="$S35_NOW" CLAUDE_CODE_SESSION_ID="$SID" bash "$POKER" fill-report "$P35R" 2>&1 )"; RC=$?
expect_eq "35t fill-report exits 0 on the idle/width fixture" "0" "$RC"
expect_contains "35u AC-6.8 the planted 12-minute interval, exactly" "idle minutes: 12" "$OUT"
expect_contains "35v AC-6.8 the instant three rows overlap, exactly" "peak width: 3" "$OUT"
# A PLAN THAT SAYS OTHERWISE CHANGES NOTHING: the report reads the ledger and the roster, never prose.
OUT_R1="$OUT"
printf '\nThe run sat idle for 99 minutes at 2026-01-01T00:00:00Z and ran 9 wide at 2026-01-01T00:00:00Z.\n' >> "$P35R"
OUT="$( cd "$R35R" && BIONIC_NOW_EPOCH="$S35_NOW" CLAUDE_CODE_SESSION_ID="$SID" bash "$POKER" fill-report "$P35R" 2>&1 )"
expect_eq "35w a plan carrying a misleading time and width changes nothing in the report" "$OUT_R1" "$OUT"
# THE ZERO CASE, so 35u cannot pass on a constant: no line names an idle row, and an old-shape line
# (no idle= field at all) reads as none. The roster is the same, so the width still reads 3.
R35Z="$(make_repo s35z)"
P35Z="$(plan_at "$R35Z" epic-99-fixture/wave-35-rz.plan.md "$(plan_body 5)")"
L35Z="$R35Z/.bionic/docs/record/wave-35-rz/fill-ledger.log"
mkdir -p "${L35Z%/*}"
{
  s35r_line 2026-09-23T10:00:00Z u-z1 '' 3
  s35_line 2026-09-23T10:12:00Z u-z2 ok T2 '' '' 1
} > "$L35Z"
cp "$(roster_of "$R35R")" "$(roster_of "$R35Z")"
cp "$(ack_ledger_of "$R35R")" "$(ack_ledger_of "$R35Z")"
OUT="$( cd "$R35Z" && BIONIC_NOW_EPOCH="$S35_NOW" CLAUDE_CODE_SESSION_ID="$SID" bash "$POKER" fill-report "$P35Z" 2>&1 )"
expect_contains "35x no idle row names a zero, and an old-shape line is none" "idle minutes: 0" "$OUT"
expect_contains "35y …while the same roster still reads its peak" "peak width: 3" "$OUT"

# ============================================================
section "Section 36: prompt — the canonical Patrol prompt (wave-20 REQ-6, AC-6.1; D6)"
# ============================================================
#
# THE PROMPT IS PRINTED, NOT COMPOSED. Report #1: a Patrol job whose prompt was the bare tick
# command (or a marker with no tick) was never a tick turn, or ran no tick. `prompt` prints the
# one prompt a CronCreate should carry — the session's marker first, the tick command in it.
R36="$(make_repo s36)"
poke "$R36" prompt
expect_eq "36a prompt exits 0" "0" "$RC"
case "$OUT" in
  "bionic-patrol session=${SID:0:8} "*) ok "36b AC-6.1 the prompt starts with this session's marker" ;;
  *) no "36b AC-6.1 the prompt starts with this session's marker" "$OUT" ;;
esac
expect_contains "36c …and carries the tick command, by this poker's absolute path" "bash $POKER tick" "$OUT"
expect_eq "36d …on one line (a CronCreate prompt)" "1" "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')"
expect_contains "36e …and names the fill answer" "fill-declined:" "$OUT"
OUT="$( cd "$R36" && CLAUDE_CODE_SESSION_ID="" bash "$POKER" prompt 2>&1 )"; RC=$?
expect_eq "36f with no session key there is no marker to print (exit 3)" "3" "$RC"
poke "$R36" prompt extra
expect_eq "36g prompt takes no arguments (exit 2)" "2" "$RC"


# ============================================================
section "Section 37: T10b — the release waits for its step and the tick names the hold; task-add keeps author text byte for byte (critic C3, review R6)"
# ============================================================
#
# C3: at current: 5, with its Step-5 dependency landed, the Step-7 release row (kind `doc`) was
# ready, so the tick ordered `FILL` for a release before any auditor or critic verdict. Δ6's
# accepted reading holds a gate act until `current:` reaches its step; the release is the
# Document step's gate act. The tick's no-FILL line now NAMES each row held for its step, so a
# reader of the line can tell "nothing is ready" from "the release waits for Step 7".
R37A="$(make_repo s37-held)"; new_roster "$R37A"
sp_plan_at_step "$R37A" 5 \
  "| T1 | 4 | build | landed | implementor | — | 15m | REQ-x | a.sh | landed |" \
  "| T2 | 5 | verify | the live bed, landed | implementor | T1 | 15m | REQ-x | — | landed |" \
  "| T3 | 7 | doc | Release 1.8.7 | implementor | T2 | 15m | REQ-x | CHANGELOG.md | pending |" > /dev/null
poke_pressure "$R37A" 8192 1.0 tick
expect_absent "37a C3 at current: 5 the landed-dep Step-7 release row is not filled" \
  "poker: FILL" "$OUT"
# A TABLE WITHOUT `reads` KEEPS THE RELEASE'S STEP HOLD (wave-26 T13, A-T13.1): it has no
# `approval:release` to wait on, so its step is the one thing holding it. The hold is named on
# the row's own WAIT line now, not inside the no-FILL sentence.
expect_contains "37b …and the tick's WAIT line names the hold" \
  "T3 — step 7 doc row waits for current: 7" "$(printf '%s\n' "$OUT" | /usr/bin/grep '^poker: WAIT')"

# 37c — AT ITS STEP THE RELEASE FILLS. Same table at current: 7.
R37C="$(make_repo s37-at-step)"; new_roster "$R37C"
sp_plan_at_step "$R37C" 7 \
  "| T1 | 4 | build | landed | implementor | — | 15m | REQ-x | a.sh | landed |" \
  "| T2 | 5 | verify | the live bed, landed | implementor | T1 | 15m | REQ-x | — | landed |" \
  "| T3 | 7 | doc | Release 1.8.7 | implementor | T2 | 15m | REQ-x | CHANGELOG.md | pending |" > /dev/null
poke_pressure "$R37C" 8192 1.0 tick
expect_contains "37c at current: 7 the release row is filled" "poker: FILL T3" "$OUT"

# 37d–37f — TASK-ADD ACCEPTS A STEP-HELD ROW, AND KEEPS ITS TEXT (R6). The hold is a
# schedule fact, not a broken invariant, so the validator stays silent and the dry commit
# admits it. Author text reached awk through -v, which read `\n` and `\t` as escapes; now a
# backslash, an author-escaped `\|` and a `$` land in the row exactly as typed.
S37_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
R37D="$(make_repo s37-task-add)"; ( cd "$R37D" && git commit -q --allow-empty -m init )
P37D="$(s34_plan "$R37D" 5)"
poke "$R37D" task-add T7 7 doc 'Release: match C:\new\table and a\|b for $5' bionic:implementor 'T5' 30 REQ-5 '—'
expect_eq "37d task-add of a Step-7 doc row at current: 5 is accepted (exit 0)" "0" "$RC"
expect_contains "37e R6 …and the task text lands byte for byte: backslashes, \\| and \$ intact" \
  '| T7 | 7 | doc | Release: match C:\new\table and a\|b for $5 | bionic:implementor | T5 | 30 | REQ-5 | — | — | — | pending |' \
  "$(cat "$P37D")"
expect_contains "37f …with its - T7: line" "- T7: pending dispatch — added by task-add" "$(cat "$P37D")"
POKE_BOUND="$S37_BOUND_WAS"


# ============================================================
section "Section 38: the tick names an ext:-held row — poker: HELD <id> ext:<slug> (wave-21 T4; REQ-3, AC-3.3; D3, ADR-037 decision 2)"
# ============================================================
#
# A ROW WAITING ON THE WORLD IS DECLARED ONCE, IN ITS DEPS CELL, as `ext:<slug>`. The ready
# set already leaves it out (an ext: token never equals `landed`); what the tick adds is the
# report: one `poker: HELD <id> ext:<slug>` line per held row, every interval, AFTER the rung
# line and BEFORE the FILL line, so the hold is printed to the only actor who can lift it and
# nobody writes a decline for it turn after turn (triage-A §F.3).
# s38_line_no <pattern> — the first line of $OUT starting with <pattern>, by number; 0 if none.
s38_line_no() { printf '%s\n' "$OUT" | awk -v p="$1" 'index($0, p) == 1 { print NR; f = 1; exit } END { if (!f) print 0 }'; }

R38A="$(make_repo s38-held)"; new_roster "$R38A"
sp_plan_at_step "$R38A" 4 \
  "| T1 | 4 | build | landed | implementor | — | 15m | REQ-x | a.sh | landed |" \
  "| T2 | 4 | build | waits on CI | implementor | T1, ext:ci-ce9520e | 15m | REQ-x | b.sh | pending |" \
  "| T3 | 4 | build | ordinary, ready | implementor | T1 | 15m | REQ-x | c.sh | pending |" > /dev/null
poke_pressure "$R38A" 8192 1.0 tick
expect_contains "38a AC-3.3 the ext:-held row prints its HELD line" "poker: HELD T2 ext:ci-ce9520e" "$OUT"
expect_contains "38b …the ready row is filled" "poker: FILL T3" "$OUT"
expect_absent "38c …and the held row is not on the FILL line" "T2" "$(printf '%s\n' "$OUT" | /usr/bin/grep '^poker: FILL')"
S38_RUNG="$(s38_line_no 'poker: rung=')"; S38_HELD="$(s38_line_no 'poker: HELD ')"; S38_FILL="$(s38_line_no 'poker: FILL ')"
expect_true "38d …and the HELD line sits after the rung line and before the FILL line (rung=$S38_RUNG held=$S38_HELD fill=$S38_FILL)" \
  test "$S38_RUNG" -gt 0 -a "$S38_HELD" -gt "$S38_RUNG" -a "$S38_FILL" -gt "$S38_HELD"

# 38e — NOTHING ELSE READY: the HELD line still prints, and the no-FILL line's step sentence
# does not borrow it (the step hold and the ext hold are different facts).
R38E="$(make_repo s38-held-only)"; new_roster "$R38E"
sp_plan_at_step "$R38E" 4 \
  "| T1 | 4 | build | landed | implementor | — | 15m | REQ-x | a.sh | landed |" \
  "| T2 | 4 | build | waits on a rig and CI | implementor | ext:rig-2, T1, ext:ci-9 | 15m | REQ-x | b.sh | pending |" > /dev/null
poke_pressure "$R38E" 8192 1.0 tick
expect_contains "38e a row with two tokens prints one HELD line naming both, in cell order" "poker: HELD T2 ext:rig-2 ext:ci-9" "$OUT"
expect_absent "38f …no FILL line is printed" "poker: FILL" "$OUT"
expect_absent "38g …and the no-FILL line names no step hold for it" "Held for their step" "$(printf '%s\n' "$OUT" | /usr/bin/grep '^poker: no FILL')"

# 38h — THE TOKEN REMOVED, the row is ready again and no HELD line is printed (AC-3.4's tick side).
R38H="$(make_repo s38-cleared)"; new_roster "$R38H"
sp_plan_at_step "$R38H" 4 \
  "| T1 | 4 | build | landed | implementor | — | 15m | REQ-x | a.sh | landed |" \
  "| T2 | 4 | build | CI went green | implementor | T1 | 15m | REQ-x | b.sh | pending |" \
  "| T3 | 4 | build | ordinary, ready | implementor | T1 | 15m | REQ-x | c.sh | pending |" > /dev/null
poke_pressure "$R38H" 8192 1.0 tick
expect_contains "38h with the token removed the row is filled again" "poker: FILL T2 T3" "$OUT"
expect_absent "38i …and no HELD line is printed" "poker: HELD" "$OUT"

# ============================================================
section "Section 39: the tick lints the ledger — poker: LEDGER <id> <finding> (wave-21 T5; REQ-4, AC-4.2; D4, ADR-037 decision 3)"
# ============================================================
#
# THE SAME READER THE GATE ASKS. `units_findings` names every ledger defect — a status off
# the enum, a landed row with no `- T<n>:` line, an active row whose agent cell names no row
# on this session's roster — and the tick prints each one, every interval, as
# `poker: LEDGER <id> <kind> [<value>]`, after the HELD lines and before the FILL line. The
# finding reaches the orchestrator, who owns the ledger, before a writer's commit meets it.
R39A="$(make_repo s39-ledger)"; new_roster "$R39A"
mkrow name=w-T2 agent_id=a-w-T2 >> "$(roster_of "$R39A")"
P39A="$(sp_plan_at_step "$R39A" 4 \
  "| T1 | 4 | build | landed, no line | implementor | — | 15m | REQ-x | a.sh | landed |" \
  "| T2 | 4 | build | active, launched | w-T2 | — | 15m | REQ-x | b.sh | active |" \
  "| T3 | 4 | build | active, agent names no roster row | implementor | — | 15m | REQ-x | c.sh | active |" \
  "| T4 | 4 | build | status off the enum | implementor | — | 15m | REQ-x | d.sh | doing |" \
  "| T5 | 4 | build | active, self-owned | — | — | 15m | REQ-x | e.sh | active |" \
  "| T6 | 4 | build | waits on CI | implementor | T1, ext:ci-6 | 15m | REQ-x | f.sh | pending |" \
  "| T7 | 4 | build | ordinary, ready | implementor | T1 | 15m | REQ-x | g.sh | pending |")"
poke_pressure "$R39A" 8192 1.0 tick
expect_contains "39a AC-4.2 a landed row with no line ticks a LEDGER line" "poker: LEDGER T1 evidence" "$OUT"
expect_contains "39b …an active row whose agent is not on the roster ticks a launch line, naming the cell" \
  "poker: LEDGER T3 launch implementor" "$OUT"
expect_contains "39c …a status off the enum ticks a status line, naming the value" "poker: LEDGER T4 status doing" "$OUT"
expect_absent "39d …the launched active row is not a finding" "poker: LEDGER T2" "$OUT"
expect_absent "39e …nor is the self-owned one" "poker: LEDGER T5" "$OUT"
expect_eq "39f …exactly three LEDGER lines" "3" "$(printf '%s\n' "$OUT" | /usr/bin/grep -c '^poker: LEDGER ')"
S39_HELD="$(s38_line_no 'poker: HELD ')"; S39_LEDGER="$(s38_line_no 'poker: LEDGER ')"; S39_FILL="$(s38_line_no 'poker: FILL ')"
expect_true "39g …and the LEDGER lines sit after the HELD line and before the FILL line (held=$S39_HELD ledger=$S39_LEDGER fill=$S39_FILL)" \
  test "$S39_HELD" -gt 0 -a "$S39_LEDGER" -gt "$S39_HELD" -a "$S39_FILL" -gt "$S39_LEDGER"
expect_contains "39h …and the fill is unchanged by the lint" "poker: FILL T7" "$OUT"

# 39i — THE LEDGER REPAIRED: T1's line written, T3's cell naming its roster row, T4 back on
# the enum. No LEDGER line.
mkrow name=w-T3 agent_id=a-w-T3 >> "$(roster_of "$R39A")"
awk '{ print } $0 == "- Step 4: in progress" { print "- T1: bash suite 9/9 green" }' "$P39A" \
  | sed -e 's/| active, agent names no roster row | implementor |/| active, agent names no roster row | w-T3 |/' \
        -e 's/| d.sh | doing |/| d.sh | pending |/' > "$P39A.new" && mv "$P39A.new" "$P39A"
poke_pressure "$R39A" 8192 1.0 tick
expect_contains "39i precondition: T1's line is in the plan" "- T1: bash suite 9/9 green" "$(cat "$P39A")"
expect_absent "39j a repaired ledger ticks no LEDGER line" "poker: LEDGER" "$OUT"

# 39k — AN EMPTY ROSTER LAUNCHES NOBODY. The tick reaches its fill arm only with a roster file
# (no file is its own REFUSED/QUIET answer, §13), so the reader's no-roster rule is the gate's
# alone; what the tick can meet is a roster with no rows, and there an agent-named active row is
# a launch finding, not an evidence one.
R39K="$(make_repo s39-empty-roster)"; new_roster "$R39K"
sp_plan_at_step "$R39K" 4 \
  "| T1 | 4 | build | active, agent-named, nobody launched | w-T1 | — | 15m | REQ-x | a.sh | active |" \
  "| T2 | 4 | build | ordinary, ready | implementor | — | 15m | REQ-x | b.sh | pending |" > /dev/null
poke_pressure "$R39K" 8192 1.0 tick
expect_contains "39k an empty roster: the agent-named active row ticks a launch line" \
  "poker: LEDGER T1 launch w-T1" "$OUT"

# ============================================================
section "Section 40: HELD and LEDGER print in EVERY tick state — no roster, HOLD, EMERGENCY, no budget (wave-21 T13; REQ-3 AC-3.3, REQ-4 AC-4.1/AC-4.2)"
# ============================================================
#
# THE AUDIT'S REFUTATION, PINNED (record/wave-21-fixit-188/audit-3b45d05.md). Through T5 the
# HELD and LEDGER lines printed only inside the FILL branch, and three reachable states never
# reach it: the first tick of a run (no roster file yet: rung, QUIET, exit), HOLD or EMERGENCY
# under machine pressure, and a plan with no `parallel-budget`. The commit gate reads the
# ledger in every one of them, so a plan the gate refused ticked clean. Every case here holds
# an ext:-held row and a defective ledger row, and expects each line EXACTLY ONCE — printed
# before the state split, never a second time inside an arm. Sections 38/39 pin the probes to
# a healthy machine; these pin them to the states those sections never reach.
s40_count() { printf '%s\n' "$OUT" | /usr/bin/grep -c "^$1" 2>/dev/null; }

# 40a — THE FIRST TICK: armed, nothing dispatched, no roster file. With no roster the reader
# takes its no-roster rule, the gate's: an agent-named active row with no line is an
# `evidence` finding, not a `launch` one.
R40A="$(make_repo s40-no-roster)"
poke "$R40A" arm
sp_plan_at_step "$R40A" 4 \
  "| T1 | 4 | build | landed, no line | implementor | — | 15m | REQ-x | a.sh | landed |" \
  "| T2 | 4 | build | waits on CI | implementor | T1, ext:ci-40a | 15m | REQ-x | b.sh | pending |" \
  "| T3 | 4 | build | active, agent-named, no line | w-T3 | — | 15m | REQ-x | c.sh | active |" > /dev/null
poke_pressure "$R40A" 8192 1.0 tick
expect_contains "40a precondition: the no-roster first tick decides QUIET" "poker: QUIET — armed, nothing dispatched yet on this session" "$OUT"
expect_contains "40a AC-3.3 the first tick prints the ext:-held row's HELD line" "poker: HELD T2 ext:ci-40a" "$OUT"
expect_contains "40a2 AC-4.2 …and the landed row with no line ticks a LEDGER line" "poker: LEDGER T1 evidence" "$OUT"
expect_contains "40a3 AC-4.1 …and the agent-named active row owes its line, as the gate's no-roster rule says" \
  "poker: LEDGER T3 evidence" "$OUT"
expect_eq "40a4 …each HELD line once" "1" "$(s40_count 'poker: HELD ')"
expect_eq "40a5 …each LEDGER line once" "2" "$(s40_count 'poker: LEDGER ')"
S40_RUNG="$(s38_line_no 'poker: rung=')"; S40_HELD="$(s38_line_no 'poker: HELD ')"
S40_LEDGER="$(s38_line_no 'poker: LEDGER ')"; S40_QUIET="$(s38_line_no 'poker: QUIET')"
expect_true "40a6 …after the rung line and before the QUIET line (rung=$S40_RUNG held=$S40_HELD ledger=$S40_LEDGER quiet=$S40_QUIET)" \
  test "$S40_RUNG" -gt 0 -a "$S40_HELD" -gt "$S40_RUNG" -a "$S40_LEDGER" -gt "$S40_HELD" -a "$S40_QUIET" -gt "$S40_LEDGER"

# 40b — HOLD: a roster, a ready row and a gap, and the machine short on memory. No fill, and
# the lint still runs: a busy machine has nothing to do with the ledger.
R40B="$(make_repo s40-hold)"; new_roster "$R40B"
sp_plan_at_step "$R40B" 4 \
  "| T1 | 4 | build | landed, no line | implementor | — | 15m | REQ-x | a.sh | landed |" \
  "| T2 | 4 | build | waits on CI | implementor | T1, ext:ci-40b | 15m | REQ-x | b.sh | pending |" \
  "| T3 | 4 | build | ordinary, ready | implementor | T1 | 15m | REQ-x | c.sh | pending |" > /dev/null
poke_pressure "$R40B" 512 1.0 tick
expect_contains "40b precondition: the tick is under HOLD" "poker: HOLD free_mb=512" "$OUT"
expect_absent "40b precondition: …and fills nothing" "poker: FILL" "$OUT"
expect_contains "40b AC-3.3 under HOLD the ext:-held row prints its HELD line" "poker: HELD T2 ext:ci-40b" "$OUT"
expect_contains "40b2 AC-4.2 …and the landed row with no line ticks a LEDGER line" "poker: LEDGER T1 evidence" "$OUT"
expect_eq "40b3 …HELD once" "1" "$(s40_count 'poker: HELD ')"
expect_eq "40b4 …LEDGER once" "1" "$(s40_count 'poker: LEDGER ')"
S40_RUNG="$(s38_line_no 'poker: rung=')"; S40_HELD="$(s38_line_no 'poker: HELD ')"
S40_LEDGER="$(s38_line_no 'poker: LEDGER ')"; S40_HOLD="$(s38_line_no 'poker: HOLD ')"
expect_true "40b5 …after the rung line and before the HOLD line (rung=$S40_RUNG held=$S40_HELD ledger=$S40_LEDGER hold=$S40_HOLD)" \
  test "$S40_RUNG" -gt 0 -a "$S40_HELD" -gt "$S40_RUNG" -a "$S40_LEDGER" -gt "$S40_HELD" -a "$S40_HOLD" -gt "$S40_LEDGER"
# THE PAIRED POSITIVE: the same repo on a healthy machine fills T3 and prints each line once.
poke_pressure "$R40B" 8192 1.0 tick
expect_contains "40b6 …the same plan on a healthy machine fills the ready row" "poker: FILL T3" "$OUT"
expect_eq "40b7 …and still prints HELD once, not once per arm" "1" "$(s40_count 'poker: HELD ')"
expect_eq "40b8 …and LEDGER once" "1" "$(s40_count 'poker: LEDGER ')"

# 40c — EMERGENCY: the same pair under the kill floor.
R40C="$(make_repo s40-emergency)"; new_roster "$R40C"
sp_plan_at_step "$R40C" 4 \
  "| T1 | 4 | build | landed, no line | implementor | — | 15m | REQ-x | a.sh | landed |" \
  "| T2 | 4 | build | waits on CI | implementor | T1, ext:ci-40c | 15m | REQ-x | b.sh | pending |" > /dev/null
poke_pressure "$R40C" 100 1.0 tick
expect_contains "40c precondition: the tick is under EMERGENCY" "poker: fill withheld — EMERGENCY free_mb=100" "$OUT"
expect_contains "40c AC-3.3 under EMERGENCY the ext:-held row prints its HELD line" "poker: HELD T2 ext:ci-40c" "$OUT"
expect_contains "40c2 AC-4.2 …and the landed row with no line ticks a LEDGER line" "poker: LEDGER T1 evidence" "$OUT"
expect_eq "40c3 …HELD once" "1" "$(s40_count 'poker: HELD ')"
expect_eq "40c4 …LEDGER once" "1" "$(s40_count 'poker: LEDGER ')"

# 40d — NO BUDGET: the plan carries no `parallel-budget:` line, so the fill arm takes its
# no-budget note — and the lint does not wait on a budget it has no use for.
R40D="$(make_repo s40-no-budget)"; new_roster "$R40D"
P40D="$(sp_plan_at_step "$R40D" 4 \
  "| T1 | 4 | build | landed, no line | implementor | — | 15m | REQ-x | a.sh | landed |" \
  "| T2 | 4 | build | waits on CI | implementor | T1, ext:ci-40d | 15m | REQ-x | b.sh | pending |")"
/usr/bin/grep -v '^parallel-budget:' "$P40D" > "$P40D.new" && mv "$P40D.new" "$P40D"
poke_pressure "$R40D" 8192 1.0 tick
expect_contains "40d precondition: the tick takes the no-budget note" "carries no parallel-budget: writers=<n>" "$OUT"
expect_contains "40d AC-3.3 with no budget the ext:-held row prints its HELD line" "poker: HELD T2 ext:ci-40d" "$OUT"
expect_contains "40d2 AC-4.2 …and the landed row with no line ticks a LEDGER line" "poker: LEDGER T1 evidence" "$OUT"
expect_eq "40d3 …HELD once" "1" "$(s40_count 'poker: HELD ')"
expect_eq "40d4 …LEDGER once" "1" "$(s40_count 'poker: LEDGER ')"

# 40e — DISARM: the terminal tick (critic-4e6d4a9 I3). An empty roster on a run that says it is
# delivered — `current: 9`, `delivered:` on the Step-9 line, armed before that — decides DISARM,
# and a delivered run whose ledger still carries a finding is one the gate would refuse, so this
# last tick says so. No other case ticks DISARM over a plan with a hold and a finding, so the
# report's call on that arm was unpinned: deleting it left every suite green.
R40E="$(make_repo s40-disarm)"; new_roster "$R40E"
armed_ago "$R40E"
P40E="$(sp_plan_at_step "$R40E" 9 \
  "| T1 | 4 | build | landed, no line | implementor | — | 15m | REQ-x | a.sh | landed |" \
  "| T2 | 4 | build | waits on CI | implementor | T1, ext:ci-40e | 15m | REQ-x | b.sh | pending |")"
sed -e 's/^- Step 9: in progress$/- Step 9: delivered: bionic 9.9.9; report: record\/fixture\/close-out.md/' \
  "$P40E" > "$P40E.new" && mv "$P40E.new" "$P40E" && touch "$P40E"
poke_pressure "$R40E" 8192 1.0 tick
expect_contains "40e precondition: the plan's Step-9 line records the delivery" \
  "- Step 9: delivered: bionic 9.9.9" "$(cat "$P40E")"
expect_contains "40e precondition: …and the tick decides DISARM" "decision=DISARM" "$OUT"
expect_contains "40e AC-3.3 the DISARM tick prints the ext:-held row's HELD line" "poker: HELD T2 ext:ci-40e" "$OUT"
expect_contains "40e2 AC-4.2 …and the landed row with no line ticks a LEDGER line" "poker: LEDGER T1 evidence" "$OUT"
expect_eq "40e3 …HELD once" "1" "$(s40_count 'poker: HELD ')"
expect_eq "40e4 …LEDGER once" "1" "$(s40_count 'poker: LEDGER ')"
S40_RUNG="$(s38_line_no 'poker: rung=')"; S40_HELD="$(s38_line_no 'poker: HELD ')"
S40_LEDGER="$(s38_line_no 'poker: LEDGER ')"; S40_DISARM="$(s38_line_no 'poker: DISARM')"
expect_true "40e5 …after the rung line and before the DISARM line (rung=$S40_RUNG held=$S40_HELD ledger=$S40_LEDGER disarm=$S40_DISARM)" \
  test "$S40_RUNG" -gt 0 -a "$S40_HELD" -gt "$S40_RUNG" -a "$S40_LEDGER" -gt "$S40_HELD" -a "$S40_DISARM" -gt "$S40_LEDGER"
# ============================================================
section "Section 41: the quiet Patrol, tick side — prompt, band, hold, digest, version (wave-24 T7; REQ-4 AC-4.1–4.6, 4.9, 4.11; D1, D4, D5; ADR-041)"
# ============================================================
#
# THE DEFECT (research-R1). The prompt asked for a `fill-declined:` line on every tick, so all 29
# declines of the 1.8.10 run answered nothing the wall asked; the band ignored STANDDOWN, so
# `decision=QUIET` printed under a stand-down; and the tick wrote a fresh stop order for the
# same finished agent every tick, with no answer that lasted past one turn. The fix: a hold on
# the roster row that stands while its fingerprint does, a digest that makes an unchanged tick
# one line, and a prompt that asks only for what the tick printed.
#
# FIXTURE FIDELITY. Every fixture is SYNTHESIZED in this suite's own sandbox: the roster rows
# through `roster_row` (tests/lib/roster-row.sh), the panel through tests/lib/live-answer.sh's
# committed corpus, the completion message in the `<teammate-message>` envelope §30b plants (the
# shape the CLI writes, measured wave-20 T9b). The hold and the stand-down are written by the
# REAL verbs. §41c's Stop drive is the shipped hooks/stop.sh on a tick turn built the way
# tests/cross-gate-agreement.test.sh's CG-standdown builds one.
#
# ANTI-VACUITY. Every absence beside a positive on the same output: §41c's "no STANDDOWN" sits
# beside its `held w-1` count, and its Stop pass beside §41b's Stop refusal on the same drive.

S41_CFG="$(fake_config_dir s41-quiet)"
export CLAUDE_CONFIG_DIR="$S41_CFG"
S41_TR="$S41_CFG/projects/-fixture-project/$SID.jsonl"
orders_of() { printf '%s/.bionic/tmp/stop-orders-%s.state' "$1" "${2:-$SID}"; }
s41_msg() {  # <name> -> one completion message from <name>, in the envelope the CLI writes
  jq -nc --arg b "<teammate-message teammate_id=\"$1\" color=\"blue\" summary=\"r\">
report
</teammate-message>" '{type:"user",timestamp:"2026-09-05T00:50:10.000Z",message:{role:"user",content:$b}}'
}
s41_transcript() {  # <messages from w-1> <name:status>... -> this session's transcript, panel fresh
  local n="$1" i tmp="$TMPROOT/s41.panel"; shift
  plant_answer "$tmp" fresh "$@"
  { head -1 "$tmp"; i=0; while [ "$i" -lt "$n" ]; do s41_msg w-1; i=$((i + 1)); done; tail -n +2 "$tmp"; } > "$S41_TR"
}
# A LIVE LEDGER WITH NO GAP: writers=1, one ready row, and the MET row still unacked holds the
# slot — so the tick names no FILL and the stop wall's fill duty owes nothing.
s41_world() {  # <label> -> a repo: armed, bound, w-1 MET with a landed deliverable
  local r; r="$(make_repo "$1")"; new_roster "$r"; armed_ago "$r"
  local p; p="$(wave_plan_at "$r" "epic-99-fixture/wave-41.plan.md" \
    "writers=1 suites=2 worktrees=8 test_jobs=8 source=probe" \
    "| R1 | 4 | build | ready row | implementor | — | 15m | REQ-x | r1.sh | pending |")"
  bind_marker "$r" "$p"
  echo "done" > "$r/w1-report.md"; backdate "$r/w1-report.md" 300
  add_row "$r" name=w-1 agent_id=aw1-41414141414141 deliverable="$r/w1-report.md" \
    duration="4 hours" launched_at="$(iso_ago 600)" "$(said "$r" w-1)"
  printf '%s' "$r"
}
s41_count() {  # <text> <fixed string> -> lines carrying it
  printf '%s\n' "$1" | grep -cF -- "$2" | tr -d ' '
}

# ---------- §PROMPT (AC-4.1; D5): the prompt asks only for what the tick printed ----------
R41P="$(make_repo s41-prompt)"
poke "$R41P" prompt
S41_PROMPT="$OUT"
expect_nonempty "41a precondition: the prompt printed" "$S41_PROMPT"
expect_absent "41a AC-4.1 the unconditional fill-declined sentence is gone" \
  'or write a line "fill-declined: <reason>"; TaskStop' "$S41_PROMPT"
expect_contains "41a2 …the fill answer is asked only when a FILL line printed" \
  'only if a "poker: FILL" line printed' "$S41_PROMPT"
expect_contains "41a3 …the stand-down answer only when a STANDDOWN line printed" \
  'only if a "poker: STANDDOWN" line printed' "$S41_PROMPT"
expect_contains "41a4 …and the fill answer is still named" 'fill-declined: <reason>' "$S41_PROMPT"
expect_contains "41a5 AC-4.12 …the stand-down answer names hold, its reason a quoted placeholder" "session-poker.sh hold NAME 'why it stays up'" "$S41_PROMPT"
expect_contains "41a6 AC-4.13 …ListAgents only when the roster has an open row" \
  "ListAgents only when the roster has an open row" "$S41_PROMPT"
expect_regex "41a7 AC-4.11 …and it carries its version after the session token" \
  "^bionic-patrol session=${SID:0:8} v=[0-9]+ — " "$S41_PROMPT"

# ---------- §BAND (AC-4.2; D4): a stand-down raises the band ----------
R41B="$(s41_world s41-band)"
s41_transcript 1 "w-1:idle"
poke "$R41B" tick
S41B_OUT="$OUT"
expect_contains "41b precondition: the MET row on the panel is stood down" "poker: STANDDOWN w-1" "$S41B_OUT"
expect_contains "41b AC-4.2 …and the decision says so" "decision=STANDDOWN" "$S41B_OUT"
expect_absent "41b2 …never QUIET beside a STANDDOWN line" "decision=QUIET" "$S41B_OUT"
expect_contains "41b3 …and the order is written" "target=w-1" "$(cat "$(orders_of "$R41B")" 2>/dev/null)"
expect_contains "41b4 AC-4.12 …and the STANDDOWN line names the standing answer" "hold w-1" "$S41B_OUT"

# The tick turn the stop wall judges: the Patrol prompt, the tick's Bash call and its output,
# and the task-list refresh — no decline text anywhere.
S41_STOP="${BIONIC_HOOKS_DIR}/stop.sh"
s41_turn() {  # <repo> <tick output> -> the transcript path
  local tr="$1/s41-turn.jsonl"
  {
    jq -nc --arg t "$S41_PROMPT" '{type:"user",isMeta:true,isSidechain:false,userType:"external",message:{role:"user",content:$t}}'
    jq -nc --arg c "bash $POKER tick" '{type:"assistant",isSidechain:false,message:{role:"assistant",content:[{type:"tool_use",id:"toolu_01S41TICK",name:"Bash",input:{command:$c}}]}}'
    jq -nc --arg o "$2" '{type:"user",isSidechain:false,message:{role:"user",content:[{type:"tool_result",tool_use_id:"toolu_01S41TICK",content:$o}]}}'
    jq -nc '{type:"assistant",isSidechain:false,message:{role:"assistant",content:[{type:"tool_use",id:"toolu_01S41TL",name:"TaskList",input:{}}]}}'
    jq -nc '{type:"assistant",isSidechain:false,message:{role:"assistant",content:[{type:"text",text:"Continuing."}]}}'
  } > "$tr"
  printf '%s' "$tr"
}
s41_stop() {  # <repo> <transcript> -> sets S41_STOP_OUT
  S41_STOP_OUT="$(jq -nc --arg t "$2" --arg c "$1" --arg s "$SID" \
      '{session_id:$s,transcript_path:$t,cwd:$c,hook_event_name:"Stop",stop_hook_active:false}' \
    | env CLAUDE_CODE_SESSION_ID="$SID" bash "$S41_STOP" 2>/dev/null)"
}
s41_stop "$R41B" "$(s41_turn "$R41B" "$S41B_OUT")"
expect_contains "41b5 the CONTROL: the real stop wall refuses an unanswered stand-down on this drive" \
  "stand-down unanswered" "$(printf '%s' "$S41_STOP_OUT" | jq -r '.reason // ""' 2>/dev/null)"

# ---------- §HOLD-fix (wave-24 T27; critic I4): one pasteable hold line at all three sites ----------
# The tick's STANDDOWN line, the stop wall's stand-down refusal and the Patrol prompt each print
# the hold command. A bare `<reason>` pasted as printed is a redirect from a file named `reason`;
# each site now prints the reason as the one quoted placeholder. The tick's and the wall's lines
# carry the real name and parse, as a pasting shell parses them, into exactly five arguments.
s41_hold_argv() {  # <text> -> the first `bash …session-poker.sh hold …` command in it, as argc|name|reason
  local l
  l="$(printf '%s\n' "$1" | /usr/bin/grep -o "bash [^ ]*session-poker.sh hold [A-Za-z0-9_.-]* 'why it stays up'" | head -1)"
  [ -n "$l" ] || return 0
  eval "set -- $l"
  printf '%s|%s|%s' "$#" "$4" "$5"
}
S41B_WALL="$(printf '%s' "$S41_STOP_OUT" | jq -r '.reason // ""' 2>/dev/null)"
expect_eq "41b6 critic I4 the tick's STANDDOWN line pastes as one hold of w-1 with a quoted reason" \
  "5|w-1|why it stays up" "$(s41_hold_argv "$S41B_OUT")"
expect_eq "41b7 …and the stop wall's refusal prints the same command for the same row" \
  "5|w-1|why it stays up" "$(s41_hold_argv "$S41B_WALL")"
expect_contains "41b8 …and the Patrol prompt carries the same reason placeholder" \
  "hold NAME 'why it stays up'" "$S41_PROMPT"

# ---------- §HOLD (AC-4.3; D1): a hold stands, prints once, and the turn ends ----------
R41H="$(s41_world s41-hold)"
s41_transcript 1 "w-1:idle"
poke "$R41H" hold w-1 "addendum"
expect_eq "41c the hold verb exits 0" "0" "$RC"
S41H_ROW="$(grep -F '|name=w-1|' "$(roster_of "$R41H")" | tail -1)"
expect_regex "41c2 …and appends the row with held=<at> <reason> fp=<launch>:<mtime>:<count>" \
  '\|held=[0-9TZ:-]+ addendum fp=[0-9TZ:-]+:[0-9]+:1\|' "$S41H_ROW"
poke "$R41H" tick
S41H_T1="$OUT"
poke "$R41H" tick
S41H_T2="$OUT"
expect_eq "41c3 two ticks print exactly one held note" "1" \
  "$(s41_count "$S41H_T1
$S41H_T2" "poker: held w-1 since ")"
expect_contains "41c4 …which carries the reason" "— addendum" "$S41H_T1"
expect_absent "41c5 …and neither tick stands it down" "poker: STANDDOWN" "$S41H_T1$S41H_T2"
expect_absent "41c6 …nor writes it an order" "target=w-1" "$(cat "$(orders_of "$R41H")" 2>/dev/null)"
s41_stop "$R41H" "$(s41_turn "$R41H" "$S41H_T1")"
expect_eq "41c7 AC-4.3 the real stop wall ends the held tick's turn with no decline text" "" \
  "$(printf '%s' "$S41_STOP_OUT" | jq -r '.decision // ""' 2>/dev/null)"
# A successor row (a re-dispatch's, or `extend`'s) is a new contract and carries no hold (D1).
poke "$R41H" extend w-1 "more work"
expect_absent "41c8 the copy a successor row takes drops held=" "held=" \
  "$(grep -F '|name=w-1|' "$(roster_of "$R41H")" | tail -1)"
expect_contains "41c9 …while the row it copied from carried it" "held=" "$S41H_ROW"
poke "$R41H" hold w-nobody "x"
expect_eq "41c10 hold refuses a name with no row (exit 1)" "1" "$RC"
# A REASON THAT IS ONLY BLANKS IS NO REASON (wave-24 T27; Step-6 review C3): the tick would
# print a hold with nothing after its dash. The usage error, and no row is written.
S41H_ROWS="$(grep -c '|name=w-1|' "$(roster_of "$R41H")")"
poke "$R41H" hold w-1 "   "
expect_eq "41c11 C3 hold with a blank reason is the usage error (exit 2)" "2" "$RC"
poke "$R41H" hold w-1 "
"
expect_eq "41c12 C3 …and so is one of tabs and line breaks" "2" "$RC"
expect_eq "41c13 …and neither wrote a row" "$S41H_ROWS" "$(grep -c '|name=w-1|' "$(roster_of "$R41H")")"

# ---------- §HOLD-fp (AC-4.4; D1): each fingerprint component voids the hold ----------
s41_fp_case() {  # <label> <change command, eval'd with R set> 
  local R; R="$(s41_world "s41-fp-$1")"
  s41_transcript 1 "w-1:idle"
  poke "$R" hold w-1 "idle on purpose"
  poke "$R" tick
  expect_contains "41d-$1 precondition: held before the change" "poker: held w-1 since " "$OUT"
  eval "$2"
  poke "$R" tick
  expect_contains "41d-$1 AC-4.4 after the change the row is stood down again" "poker: STANDDOWN w-1" "$OUT"
  expect_contains "41d-$1 …and the order returns" "target=w-1" "$(cat "$(orders_of "$R")" 2>/dev/null)"
}
# The launch moves while the held= string is carried verbatim, so only the comparison can see it.
s41_fp_case launch 'grep -F "|name=w-1|" "$(roster_of "$R")" | tail -1 | sed "s/|launched_at=[^|]*|/|launched_at=$(iso_ago 500)|/" >> "$(roster_of "$R")"'
s41_fp_case mtime 'backdate "$R/w1-report.md" 200'
s41_fp_case message 's41_transcript 2 "w-1:idle"'

# ---------- §DECLINE-tick (wave-26 T15, AC-4.6; D16): a stand-down decline stands as a hold does ----------
# The decline used to answer its own turn only: the next tick ordered the same unchanged agent
# down again. The stop wall now writes the decline to the roster as `hold` writes it, so the real
# tick reads it through the hold's own fingerprint check. The second turn, with the agent
# unchanged, is not refused. A new message from the agent is a changed agent, and its turn is.
R41DC="$(s41_world s41-decline)"
s41_transcript 1 "w-1:idle"
poke "$R41DC" tick
expect_contains "41dc precondition: the tick stands w-1 down" "poker: STANDDOWN w-1" "$OUT"
S41DC_TR="$(s41_turn "$R41DC" "$OUT")"
jq -nc '{type:"assistant",isSidechain:false,message:{role:"assistant",content:[{type:"text",text:"standdown-declined: w-1 is kept for a second pass"}]}}' >> "$S41DC_TR"
s41_stop "$R41DC" "$S41DC_TR"
expect_eq "41dc2 the declining turn ends" "" "$(printf '%s' "$S41_STOP_OUT" | jq -r '.decision // ""' 2>/dev/null)"
# An unrelated row joins, so the next tick prints in full rather than `unchanged` (an unchanged
# tick writes no order whatever the answer was) and has to decide w-1 again.
add_row "$R41DC" name=busy2 deliverable="$R41DC/never-written-2.md" duration="4 hours" launched_at="$(iso_ago 60)"
s41_transcript 1 "w-1:idle" "busy2:running"
poke "$R41DC" tick
expect_absent "41dc3 precondition: the tick prints in full" "unchanged since" "$OUT"
expect_contains "41dc3 AC-4.6 the next tick reads the decline as a hold" "poker: held w-1 since " "$OUT"
expect_absent "41dc4 …and does not stand w-1 down again" "poker: STANDDOWN" "$OUT"
s41_stop "$R41DC" "$(s41_turn "$R41DC" "$OUT")"
expect_eq "41dc5 AC-4.6 the second turn, same agent and no decline text, is not refused" "" \
  "$(printf '%s' "$S41_STOP_OUT" | jq -r '.decision // ""' 2>/dev/null)"
s41_transcript 2 "w-1:idle" "busy2:running"
poke "$R41DC" tick
expect_contains "41dc6 a new message from w-1 voids the decline: the tick stands it down" "poker: STANDDOWN w-1" "$OUT"
s41_stop "$R41DC" "$(s41_turn "$R41DC" "$OUT")"
expect_contains "41dc7 …and that turn, with no answer, is refused" "stand-down unanswered" \
  "$(printf '%s' "$S41_STOP_OUT" | jq -r '.reason // ""' 2>/dev/null)"

# ---------- §HOLD-idle (AC-4.5; D1): a held idle row is not re-opened ----------
R41I="$(s41_world s41-hold-idle)"
s41_transcript 1 "w-1:idle"
poke "$R41I" hold w-1 "auditor kept for a second pass"
poke "$R41I" tick
S41I_T1="$OUT"
rm -f "$(digest_of "$R41I")"
poke "$R41I" tick
expect_contains "41e precondition: the held row prints its note" "poker: held w-1 since " "$S41I_T1$OUT"
expect_absent "41e AC-4.5 two ticks over a held idle row draw no NOTIFY" "NOTIFY" "$S41I_T1$OUT"

# ---------- §DIGEST (AC-4.9; D4): an unchanged tick is one line ----------
R41D="$(make_repo s41-digest)"; new_roster "$R41D"; armed_ago "$R41D"
add_row "$R41D" name=busy deliverable="$R41D/never-written.md" duration="4 hours" \
  launched_at="$(iso_ago 60)"
plant_answer "$S41_TR" fresh "busy:running"
expect_contains "41f precondition: arm recorded the prompt version" "prompt_version=" \
  "$(cat "$(digest_of "$R41D")" 2>/dev/null)"
poke "$R41D" tick
S41D_T1="$OUT"
expect_contains "41f2 the first tick prints its decision" "decision=QUIET" "$S41D_T1"
expect_contains "41f3 …and, QUIET with a row open, prints WAITING (wave-26 T15; D16)" "poker: WAITING" "$S41D_T1"
expect_contains "41f3b …and owes no task-list duty" "duty=none" "$(cat "$(digest_of "$R41D")" 2>/dev/null)"
poke "$R41D" tick
expect_eq "41f4 AC-4.9 the second tick's stdout is exactly one line" "1" \
  "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')"
expect_regex "41f5 …and that line is the unchanged line" \
  "^poker: unchanged since [0-9TZ:-]+ — decision=QUIET$" "$OUT"
expect_contains "41f6 …and the duty is none" "duty=none" "$(cat "$(digest_of "$R41D")" 2>/dev/null)"
add_row "$R41D" name=busy2 deliverable="$R41D/never-written-2.md" duration="4 hours" \
  launched_at="$(iso_ago 60)"
poke "$R41D" tick
expect_absent "41f7 a new row is a change: the full tick prints" "unchanged since" "$OUT"
expect_contains "41f8 …with its decision line" "decision=" "$OUT"

# ---------- §PVER (AC-4.11; D5): a stale or missing prompt version asks for a re-arm ----------
R41V="$(make_repo s41-pver)"; new_roster "$R41V"
add_row "$R41V" name=busy deliverable="$R41V/never-written.md" duration="4 hours" \
  launched_at="$(iso_ago 60)"
poke "$R41V" tick
expect_eq "41g AC-4.11 a tick with no recorded version prints one re-arm line" "1" \
  "$(s41_count "$OUT" "re-arm the Patrol")"
printf 'patrol-digest/v1\nprompt_version=1\n' > "$(digest_of "$R41V")"
poke "$R41V" tick
expect_eq "41g2 …and so does a tick under an older version" "1" "$(s41_count "$OUT" "re-arm the Patrol")"
poke "$R41V" arm
poke "$R41V" tick
expect_eq "41g3 …and an armed one prints none" "0" "$(s41_count "$OUT" "re-arm the Patrol")"
expect_contains "41g4 …while still printing its decision" "decision=" "$OUT"
# ---------- §DIGEST-emergency (D4): an EMERGENCY names a writer to stop on every tick ----------
R41X="$(make_repo s41-emergency)"; new_roster "$R41X"; armed_ago "$R41X"
add_row "$R41X" name=suite-writer deliverable="$R41X/never-written.md" duration="4 hours" \
  claims="bash tests/run.sh" launched_at="$(iso_ago 60)"
plant_answer "$S41_TR" fresh "suite-writer:running"
poke_pressure "$R41X" 100 1.0 tick
expect_contains "41h precondition: the first EMERGENCY tick names the writer" "poker: EMERGENCY" "$OUT"
poke_pressure "$R41X" 100 1.0 tick
expect_contains "41h2 the second EMERGENCY tick over the same facts still prints in full" "poker: EMERGENCY" "$OUT"
expect_absent "41h3 …never as unchanged" "unchanged since" "$OUT"
unset CLAUDE_CONFIG_DIR

# ---------- §SD-tick (AC-4.7; D2): the tick prints the standing fill decline ----------
#
# THE DEFECT (wave-24 Step-6 review C2). The stop wall read the session's latest declined fill-
# ledger line as the standing answer for the ready rows it saw, and the tick read nothing: it
# still printed `FILL ONE` and `decision=FILL` for a row the wall treated as answered, so the
# prompt asked for the answer again. The tick now asks the same reader the wall asks
# (`fill_standing_decline`, lib/fill.sh), prints `fill-declined standing since <at> — <reason>`,
# and names no standing row in its FILL. The ledger line is the recorder's shape
# (stop.sh `stop_fill_ledger`); the plan is mk_rung_repo's, at `current: 4` with four ready rows.
s41_sd_line() {  # <repo> <session> <current> <ready> <declined>
  local d="$1/.bionic/docs/record/wave-01-fixture"
  mkdir -p "$d"
  printf 'fill-ledger/v1|at=2026-10-03T09:00:00Z|session=%s|turn=u-1|current=%s|state=ok|ceiling=8|width=8|open=0|free=8|ready=%s|launched=|declined=%s|missed=4\n' \
    "$2" "$3" "$4" "$5" >> "$d/fill-ledger.log"
}
s41_fill_line() { printf '%s\n' "$1" | /usr/bin/grep '^poker: FILL ' | head -1; }
R41S="$(mk_rung_repo s41-sd-some)"
s41_sd_line "$R41S" "$SID" 4 ONE,TWO "ONE and TWO wait on the BASE merge"
poke_rung "$R41S" 60 0 tick
expect_contains "41i C2 AC-4.7 the tick prints the standing decline, its instant and its reason" \
  "poker: fill-declined standing since 2026-10-03T09:00:00Z — ONE and TWO wait on the BASE merge" "$OUT"
expect_eq "41i2 …and fills only the rows it did not answer" "poker: FILL THREE FOUR" "$(s41_fill_line "$OUT")"
R41A="$(mk_rung_repo s41-sd-all)"
s41_sd_line "$R41A" "$SID" 4 ONE,TWO,THREE,FOUR "the batch waits on the BASE merge"
poke_rung "$R41A" 60 0 tick
expect_contains "41i3 a decline that answered every ready row prints as standing" \
  "poker: fill-declined standing since 2026-10-03T09:00:00Z — the batch waits on the BASE merge" "$OUT"
expect_eq "41i4 …and the tick prints no FILL line" "" "$(s41_fill_line "$OUT")"
expect_absent "41i5 …nor decision=FILL" "decision=FILL" "$OUT"
# A moved current: is not one of the ways a line stands for nothing (wave-26 T15; D16).
R41M="$(mk_rung_repo s41-sd-moved)"
s41_sd_line "$R41M" "$SID" 3 ONE,TWO,THREE,FOUR "answered at an earlier step"
poke_rung "$R41M" 60 0 tick
expect_contains "41i6 wave-26 T15 (D16) a decline taken at another current: still stands over the same ready set" \
  "fill-declined standing since " "$OUT"
expect_eq "41i7 …and the tick prints no FILL line" "" "$(s41_fill_line "$OUT")"
R41O="$(mk_rung_repo s41-sd-other)"
s41_sd_line "$R41O" "ffffffff-0000-4000-8000-000000000000" 4 ONE,TWO,THREE,FOUR "another session's answer"
poke_rung "$R41O" 60 0 tick
expect_eq "41i8 another session's decline does not stand here" \
  "poker: FILL ONE TWO THREE FOUR" "$(s41_fill_line "$OUT")"
R41D2="$(mk_rung_repo s41-sd-dash)"
s41_sd_line "$R41D2" "$SID" 4 ONE,TWO,THREE,FOUR "—"
poke_rung "$R41D2" 60 0 tick
expect_eq "41i9 C4 a decline that is only a dash does not stand" \
  "poker: FILL ONE TWO THREE FOUR" "$(s41_fill_line "$OUT")"
expect_absent "41i10 …and no standing line" "fill-declined standing" "$OUT"

# ============================================================
section "Section 42: plan-row verbs — task-set, step-line, current, ledger-add, ledger-set (wave-24 T15; REQ-9 AC-9.1–9.3, 9.5, 9.6; D14)"
# ============================================================
#
# Five verbs replace the hand edits a run makes to its own plan: a `## Tasks` cell, a
# `- Step N:` or `- T<n>:` line, `current:`, and a `## Dispatch ledger` row. Each one is the
# task-add transaction (§34): projected onto a copy through units.sh, the copy judged by a dry
# commit through the REAL hooks/bash-walls.sh, the plan's checksum compared, and only then the
# swap. The fixture is §34's plan, which the real gate admits, plus a dispatch ledger, and it is
# committed so `git diff --numstat` can say exactly which lines a verb moved.
s42_plan() {  # <repo> <current> [step-4 block body] -> the plan path; bound, committed
  local p; p="$(s34_plan "$1" "$2" "${3:-}")"
  printf '\n## Dispatch ledger\n\n| id | agent | dispatched | expected | artifact | landed | notes |\n' >> "$p"
  printf '|---|---|---|---|---|---|---|\n| T1 | implementor (w-T1) | 2026-10-03T00:00Z | 30 min | record/T1.md | landed | batch 1 |\n' >> "$p"
  ( cd "$1" && git add -f "$p" && git commit -qm plan ) >/dev/null 2>&1
  printf '%s' "$p"
}
s42_numstat() { git -C "$1" diff --numstat | awk '{ printf "%s %s;", $1, $2 }'; }
s42_snap() {  # <repo> <plan> -> commit the plan and keep a byte copy for the cmp rows
  ( cd "$1" && git add -f "$2" && git commit -qm snap ) >/dev/null 2>&1
  cp "$2" "$TMPROOT/s42-before"
}
s42_unchanged() {  # <label> <want rc> <plan>
  expect_eq "$1 — refused (exit $2)" "$2" "$RC"
  expect_true "$1 — …and the plan is byte-identical (cmp)" cmp -s "$TMPROOT/s42-before" "$3"
}
S42_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180

R42="$(make_repo s42-verbs)"; ( cd "$R42" && git commit -q --allow-empty -m init )
P42="$(s42_plan "$R42" 4)"
s34_gate "$R42"
expect_eq "42a precondition: the fixture plan is admitted by the real commit gate" "0" "$GATE_RC"
expect_eq "42a2 precondition: the fixture is committed, so a diff starts empty" "" "$(s42_numstat "$R42")"

# ---------- §VERB (AC-9.1): exactly those cells change; Files names amend ----------
poke "$R42" task-set T2 status=landed worktree=— base=def5678
expect_eq "42b §VERB AC-9.1 task-set of three cells exits 0" "0" "$RC"
expect_contains "42b2 …and says what it did" "task-set — T2" "$OUT"
expect_eq "42b3 …git diff --numstat shows one line" "1 1;" "$(s42_numstat "$R42")"
expect_contains "42b4 …and that line is the row with exactly those cells" \
  "| T2 | 4 | build | the second build | implementor | — | 30 | REQ-1 | b.sh | — | def5678 | landed |" "$(cat "$P42")"
s34_gate "$R42"
expect_eq "42b5 …and the next commit is admitted" "0" "$GATE_RC"
s42_snap "$R42" "$P42"
poke "$R42" task-set T5 Files=c.sh
s42_unchanged "42c §VERB Files= is refused" 1 "$P42"
expect_contains "42c2 …naming amend" "task-set does not write Files — widen a dispatched contract with amend" "$OUT"
poke "$R42" task-set T5 files=c.sh
s42_unchanged "42c3 §VERB …and so is files=, in any case" 1 "$P42"

# ---------- §VERB-bad (AC-9.2): refused, byte-identical ----------
poke "$R42" task-set T5 colour=red
s42_unchanged "42d §VERB-bad a column the header does not carry" 1 "$P42"
expect_contains "42d2 …naming it" "colour" "$OUT"
poke "$R42" task-set T99 status=landed
s42_unchanged "42d3 §VERB-bad an id the table does not carry" 1 "$P42"
poke "$R42" task-set T5 'task=a|b'
s42_unchanged "42d4 §VERB-bad a pipe in a value" 1 "$P42"
poke "$R42" task-set T5 "task=a
b"
s42_unchanged "42d5 §VERB-bad a newline in a value" 1 "$P42"
poke "$R42" task-set T5 status
s42_unchanged "42d6 §VERB-bad an operand with no =" 2 "$P42"
poke "$R42" task-set T5 id=T9
s42_unchanged "42d7 §VERB-bad the id is the row's key, not a cell to set" 1 "$P42"
poke "$R42" task-set T5 status=bogus
s42_unchanged "42d8 §VERB-bad a status the Task invariants refuse" 1 "$P42"
expect_contains "42d9 …in the validator's own words" "T5: status bogus is not one of" "$OUT"
poke "$R42" step-line T5 "a
b"
s42_unchanged "42d10 §VERB-bad a newline in a step line" 1 "$P42"
poke "$R42" step-line Q5 text
s42_unchanged "42d11 §VERB-bad a key that is neither a step number nor T<n>" 2 "$P42"
poke "$R42" ledger-add T1 agent=x
s42_unchanged "42d12 §VERB-bad ledger-add of an id the ledger already carries" 1 "$P42"
poke "$R42" ledger-set T7 landed=yes
s42_unchanged "42d13 §VERB-bad ledger-set of an id the ledger does not carry" 1 "$P42"
poke "$R42" ledger-set T1 colour=red
s42_unchanged "42d14 §VERB-bad ledger-set of a column the ledger does not carry" 1 "$P42"
poke "$R42" ledger-set T1 'notes=a|b'
s42_unchanged "42d15 §VERB-bad a pipe in a ledger value" 1 "$P42"
# THE ID IS AN OPERAND TOO (wave-24 T27; Step-6 review C1). `ledger-add` wrote its id into the
# new row unchecked: a line break in it forged a plan line past the commit gate, and a pipe a
# cell. Every row verb now judges the id by one grammar before any projection.
poke "$R42" ledger-add "T8
- Step 9: forged" agent=y
s42_unchanged "42d15b §VERB-bad C1 ledger-add of an id carrying a line break" 1 "$P42"
expect_contains "42d15c …naming the id grammar" "is not one row id" "$OUT"
poke "$R42" ledger-add 'T9|x' agent=y
s42_unchanged "42d15d §VERB-bad C1 ledger-add of an id carrying a pipe" 1 "$P42"
poke "$R42" ledger-add 'T9 x' agent=y
s42_unchanged "42d15e §VERB-bad C1 ledger-add of an id of two words" 1 "$P42"
# THE GRAMMAR IS ASCII UNDER ANY LOCALE (wave-24 T29; critic addendum A3). `[A-Za-z]` is a
# collation range, and /bin/bash 3.2 under a UTF-8 locale let é, ö, ß and a fullwidth Ｔ
# through, so `Ｔ9` keyed a row that reads as T9. Driven by /bin/bash itself under UTF-8.
s42_u8() {  # <verb args...> -> sets OUT, RC; /bin/bash 3.2, a UTF-8 locale
  OUT="$( cd "$R42" && env LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 CLAUDE_CODE_SESSION_ID="$SID" /bin/bash "$POKER" "$@" 2>&1 )"; RC=$?
}
for _s42_id in 'é9' 'Tö' 'Ｔ9' 'T9ß'; do
  s42_u8 ledger-add "$_s42_id" agent=y
  s42_unchanged "42d15i §VERB-bad A3 ledger-add of the non-ASCII id $_s42_id under /bin/bash and UTF-8" 1 "$P42"
done
poke "$R42" ledger-set 'T1|x' notes=y
s42_unchanged "42d15f §VERB-bad C1 ledger-set of an id carrying a pipe" 1 "$P42"
poke "$R42" task-set "T5
x" size=45
s42_unchanged "42d15g §VERB-bad C1 task-set of an id carrying a line break" 1 "$P42"
poke "$R42" ledger-set T1 "notes
- Step 9: forged=y"
s42_unchanged "42d15h §VERB-bad C1 a column name carrying a line break" 1 "$P42"
expect_contains "42d15i …naming the column, not the value" "the column name" "$OUT"

# THE DRY COMMIT IS REAL: a valid cell on a plan the gate refuses — its Step-4 block has lost
# its base-sha, which no table check reads (§34e's fixture) — is refused in the gate's words.
R42E="$(make_repo s42-gate)"; ( cd "$R42E" && git commit -q --allow-empty -m init )
P42E="$(s42_plan "$R42E" 4 '  worktree: .worktrees/01-fixture
  branch: wave/01-fixture')"
s42_snap "$R42E" "$P42E"
poke "$R42E" task-set T5 size=45
s42_unchanged "42d16 §VERB-bad a valid cell on a plan the commit gate refuses" 1 "$P42E"
expect_contains "42d17 …in the gate's own words" "bionic: commit refused" "$OUT"
expect_contains "42d18 …naming the field it wants" "base-sha" "$OUT"
# …and the gate's placeholder arm, which the dry commit reaches only past the matrix: a row
# whose `- T<n>:` line is a placeholder refuses any write, naming the line.
R42P="$(make_repo s42-placeholder)"; ( cd "$R42P" && git commit -q --allow-empty -m init )
P42P="$(s42_plan "$R42P" 4)"
sed 's/^- T5: pending dispatch — .*$/- T5: TBD/' "$P42P" > "$P42P.tmp" && mv "$P42P.tmp" "$P42P"
s42_snap "$R42P" "$P42P"
expect_eq "42d19 precondition: the fixture's T5 line is a placeholder" "1" "$(grep -cx -- '- T5: TBD' "$P42P")"
poke "$R42P" task-set T5 size=45
s42_unchanged "42d20 §VERB-bad a write to a plan with a placeholder task line" 1 "$P42P"
expect_contains "42d21 …in the gate's own words" "dispatched task T5 evidence line is a placeholder ('TBD')" "$OUT"
s42_snap "$R42" "$P42"

# ---------- §VERB-race (AC-9.3): the plan touched between projection and swap ----------
# A `jq` on PATH that, the first time a process OTHER than this session's own poker calls it,
# appends a line to the plan before handing over to the real jq. The only such process is the
# dry commit's gate, which runs after the projection and before the swap — so the line lands
# in exactly the window the checksum guards.
mkdir -p "$TMPROOT/s42-shim"
cat > "$TMPROOT/s42-shim/jq" <<'SH'
#!/bin/bash
if [ "${CLAUDE_CODE_SESSION_ID:-}" != "$S42_SID" ] && [ ! -e "$S42_RACE_DONE" ]; then
  : > "$S42_RACE_DONE"
  printf '%s\n' '<!-- a concurrent edit -->' >> "$S42_RACE_PLAN"
fi
exec "$S42_REAL_JQ" "$@"
SH
chmod +x "$TMPROOT/s42-shim/jq"
export S42_SID="$SID" S42_REAL_JQ="$(command -v jq)" S42_RACE_DONE="$TMPROOT/s42-race-done" S42_RACE_PLAN="$P42"
S42_PATH_WAS="$PATH"; PATH="$TMPROOT/s42-shim:$PATH"
poke "$R42" task-set T5 size=45
PATH="$S42_PATH_WAS"
expect_eq "42e precondition: the concurrent edit landed during the dry commit" "yes" \
  "$([ -e "$S42_RACE_DONE" ] && echo yes)"
expect_eq "42e2 §VERB-race AC-9.3 the verb is refused (exit 1)" "1" "$RC"
expect_contains "42e3 …saying the plan changed" "changed while" "$OUT"
expect_contains "42e4 …the concurrent edit is intact" "<!-- a concurrent edit -->" "$(cat "$P42")"
expect_contains "42e5 …and the verb wrote nothing: T5 keeps its size" \
  "| T5 | 5 | verify | the floor | test-runner | T1, T2 | 30 |" "$(cat "$P42")"
poke "$R42" task-set T5 size=45
expect_eq "42e6 run again, it lands (exit 0)" "0" "$RC"
expect_contains "42e7 …the new cell is in" "| T5 | 5 | verify | the floor | test-runner | T1, T2 | 45 |" "$(cat "$P42")"
expect_contains "42e8 …beside the concurrent edit: nothing was lost" "<!-- a concurrent edit -->" "$(cat "$P42")"
s42_snap "$R42" "$P42"

# ---------- §VERB-cur (AC-9.5): current moves, 9 is close-out's ----------
poke "$R42" current 9
s42_unchanged "42f §VERB-cur AC-9.5 current 9 is refused" 1 "$P42"
expect_contains "42f2 …naming close-out" "close-out" "$OUT"
poke "$R42" current 5
s42_unchanged "42f3 §VERB-cur a move the gate refuses (no Step 5 block) is refused" 1 "$P42"
expect_contains "42f4 …in the gate's own words" "Step 5" "$OUT"
poke "$R42" current 4x
s42_unchanged "42f5 §VERB-cur a step that is neither N nor T<n>" 2 "$P42"

# The Step-4 block (A-orch-8): advancing to 4 writes the worktree/base-sha/branch fields the
# first writer's commit is refused without, from the run's own `working-branch:` — and only
# the fields the block lacks. The control is the same plan with no working-branch: line.
R42C="$(make_repo s42-cur)"
( cd "$R42C" && git commit -q --allow-empty -m init && git checkout -q -b wave/01-fixture )
P42C="$(s42_plan "$R42C" 3 '  note: the block owes its three fields')"
s42_snap "$R42C" "$P42C"
poke "$R42C" current 4
s42_unchanged "42f6 control: with no working-branch: line the block cannot be written, and current 4 is refused" 1 "$P42C"
expect_contains "42f7 …in the gate's own words, naming the missing fields" "base-sha" "$OUT"
awk '{ print } /^current: 3$/ { print "working-branch: wave/01-fixture" }' "$P42C" > "$P42C.tmp" && mv "$P42C.tmp" "$P42C"
s42_snap "$R42C" "$P42C"
poke "$R42C" current 4
expect_eq "42f8 §VERB-cur AC-9.5 current 4 from 3 exits 0" "0" "$RC"
expect_contains "42f9 …current: is 4" "current: 4" "$(cat "$P42C")"
expect_contains "42f10 …the Step-4 block carries its branch" "  branch: wave/01-fixture" "$(cat "$P42C")"
expect_contains "42f11 …its base-sha, the branch head at the advance" \
  "  base-sha: $(git -C "$R42C" rev-parse --short wave/01-fixture)" "$(cat "$P42C")"
expect_contains "42f12 …and its worktree, the checkout holding the branch" "  worktree: ." "$(cat "$P42C")"
expect_eq "42f13 …and nothing else moved: current: plus three added lines" "4 1;" "$(s42_numstat "$R42C")"
s34_gate "$R42C"
expect_eq "42f14 …and the first Step-4 commit is admitted" "0" "$GATE_RC"

# ---------- §VERB-line (AC-9.6): step-line and the ledger verbs write only their line or row ----------
poke "$R42" step-line T2 'landed — def5678 on wt/01-T2'
expect_eq "42g §VERB-line step-line T2 exits 0" "0" "$RC"
expect_eq "42g2 AC-9.6 …one line replaced" "1 1;" "$(s42_numstat "$R42")"
expect_eq "42g3 …and it reads as written" "1" "$(grep -cx -- '- T2: landed — def5678 on wt/01-T2' "$P42")"
s42_snap "$R42" "$P42"
poke "$R42" step-line T2 'merge abc1234' --append
expect_eq "42g4 §VERB-line --append exits 0" "0" "$RC"
expect_eq "42g5 AC-9.6 …one line replaced" "1 1;" "$(s42_numstat "$R42")"
expect_eq "42g6 …the text appended to the line" "1" \
  "$(grep -cx -- '- T2: landed — def5678 on wt/01-T2; merge abc1234' "$P42")"
s42_snap "$R42" "$P42"
poke "$R42" step-line 5 opened
expect_eq "42g7 §VERB-line step-line of a step with no line exits 0" "0" "$RC"
expect_eq "42g8 AC-9.6 …one line added" "1 0;" "$(s42_numstat "$R42")"
expect_eq "42g9 …after the Step-4 block, not inside it" "- Step 5: opened" \
  "$(awk 'prev ~ /^  branch: / { print; exit } { prev = $0 }' "$P42")"
s42_snap "$R42" "$P42"
poke "$R42" ledger-add T2 'agent=implementor (w-T2)' dispatched=2026-10-03T01:00Z 'expected=30 min'
expect_eq "42g10 §VERB-line ledger-add exits 0" "0" "$RC"
expect_eq "42g11 AC-9.6 …one row added" "1 0;" "$(s42_numstat "$R42")"
expect_eq "42g12 …after the last row, the cells it was not given spelled —" \
  "| T2 | implementor (w-T2) | 2026-10-03T01:00Z | 30 min | — | — | — |" \
  "$(awk 'prev ~ /^\| T1 \| implementor \(w-T1\)/ { print; exit } { prev = $0 }' "$P42")"
s42_snap "$R42" "$P42"
poke "$R42" ledger-set T2 'landed=landed 2026-10-03T02:00Z (merge abc1234)'
expect_eq "42g13 §VERB-line ledger-set exits 0" "0" "$RC"
expect_eq "42g14 AC-9.6 …one row replaced" "1 1;" "$(s42_numstat "$R42")"
expect_eq "42g15 …the one cell set" "1" \
  "$(grep -cxF -- '| T2 | implementor (w-T2) | 2026-10-03T01:00Z | 30 min | — | landed 2026-10-03T02:00Z (merge abc1234) | — |' "$P42")"
# THE ID GRAMMAR ADMITS THE LEDGER'S OWN SHAPES (T27, C1's positive): a suffixed id is one token.
s42_snap "$R42" "$P42"
poke "$R42" ledger-add T2-critic agent=critic
expect_eq "42g15b §VERB-line ledger-add of a suffixed id (T2-critic) exits 0" "0" "$RC"
expect_eq "42g15c …one row added" "1 0;" "$(s42_numstat "$R42")"
# A3's positive, same driver as 42d15i: an ASCII id under /bin/bash and UTF-8 is admitted.
s42_u8 ledger-add T2-u8 agent=critic
expect_eq "42g15d …and the same /bin/bash UTF-8 driver admits an ASCII id (T2-u8)" "0" "$RC"
s34_gate "$R42"
expect_eq "42g16 …and after all five verbs the next commit is admitted" "0" "$GATE_RC"

# ---------- the refusals that precede any projection, and nothing left behind ----------
R42G="$(make_repo s42-unbound)"; ( cd "$R42G" && git commit -q --allow-empty -m init )
P42G="$(s42_plan "$R42G" 4)"; engage "$R42G"
s42_snap "$R42G" "$P42G"
poke "$R42G" task-set T5 size=45
s42_unchanged "42h an unbound session is refused and the newest plan is not written" 1 "$P42G"
expect_contains "42h2 …saying why" "bound" "$OUT"
expect_eq "42h3 no projection copy is left beside any plan" "" \
  "$(find "$R42" "$R42C" "$R42E" "$R42P" -name '*.plan.md.*' 2>/dev/null)"
expect_eq "42h4 …and no dry-run engagement marker is left in .bionic/tmp" "" \
  "$(find "$R42/.bionic/tmp" "$R42C/.bionic/tmp" -name 'engaged-*' ! -name "engaged-$SID.state" 2>/dev/null)"
POKE_BOUND="$S42_BOUND_WAS"

# ============================================================
section "Section 43: the Done marker travels with the contract — hold and amend keep it, extend drops it, adopt carries it (wave-24 T9, REQ-4 AC-4.8; D3; A-orch-31)"
# ============================================================
#
# The verdict reads the LATEST row for a name, so a successor row that dropped `done=` would
# un-say an agent that had said it was done: a held row would leave MET and never print held.
# `hold` and `amend` continue the contract and keep the marker; `extend` re-opens it for new
# work, launched now, which is signalled afresh; `adopt` files the same contract under a new
# session and carries it.
# fails-when: a successor row of hold/amend/adopt lacks done=, or extend keeps it.
S43_CFG="$(fake_config_dir s43-done)"
export CLAUDE_CONFIG_DIR="$S43_CFG"
s43_last() { grep -F "|name=${2:-w-1}|" "$(roster_of "$1")" | tail -1; }
s43_done() { printf '%s' "$1" | tr '|' '\n' | grep '^done=' | head -1 | cut -d= -f2-; }
R43="$(s41_world s43-hold)"
S41_TR="$S43_CFG/projects/-fixture-project/$SID.jsonl"; s41_transcript 1 "w-1:idle"
S43_MARK="$R43/w-1.done"
expect_eq "43a precondition: the launch row names its Done marker" "$S43_MARK" "$(s43_done "$(s43_last "$R43")")"
poke "$R43" hold w-1 "second pass"
expect_eq "43a2 precondition: the hold took (exit 0)" "0" "$RC"
expect_contains "43a3 …its row is the hold's" "held=" "$(s43_last "$R43")"
expect_eq "43a4 hold keeps the Done marker on its successor row" "$S43_MARK" "$(s43_done "$(s43_last "$R43")")"
poke "$R43" tick
expect_contains "43a5 …so the held row still reads MET and prints held" "poker: held w-1 since " "$OUT"
poke "$R43" extend w-1 "more work"
expect_contains "43b precondition: the extend took — its row is the latest" "extended=" "$(s43_last "$R43")"
expect_eq "43b2 extend drops the Done marker: new work is signalled afresh" "" "$(s43_done "$(s43_last "$R43")")"

R43M="$(make_repo s43-amend)"; new_roster "$R43M"
s30_row "$R43M" "$(said "$R43M" w1)"
poke "$R43M" amend w1 --files+ hooks/b.sh --reason 'the fix touches b'
expect_eq "43c precondition: the amend took (exit 0)" "0" "$RC"
expect_contains "43c2 …its row is the amend's" "amended=" "$(s43_last "$R43M" w1)"
expect_eq "43c3 amend keeps the Done marker on its successor row" "$R43M/w1.done" "$(s43_done "$(s43_last "$R43M" w1)")"

PRED_43="d6d6d6d6-1111-4bbb-8ccc-000000000043"
R43A="$(make_repo s43-adopt)"; new_roster "$R43A"
echo done > "$R43A/adopted.md"
add_row_to "$R43A" "$PRED_43" name=adopted-writer status=identified agent_id=aadopted-434343434343434 \
  subagent_type=bionic:implementor deliverable="$R43A/adopted.md" duration="45 minutes" \
  cadence="10 minutes" "$(said "$R43A" adopted-writer)"
poke "$R43A" adopt
expect_contains "43d precondition: the row was adopted onto this session's roster" "adopted_from=$PRED_43" \
  "$(s43_last "$R43A" adopted-writer)"
expect_eq "43d2 adopt carries the Done marker onto the adopted row" "$R43A/adopted-writer.done" \
  "$(s43_done "$(s43_last "$R43A" adopted-writer)")"
unset CLAUDE_CONFIG_DIR

# ============================================================
section "Section 44: the lines a reader pastes keep a plugin root with a space as one word (wave-24 T29; critic I2, A-T27.8)"
# ============================================================
#
# The Patrol prompt, the tick's STANDDOWN line and its re-arm note print the poker's own path
# for a reader to paste. They printed `${HOOK_DIR}` bare, so a plugin root with a space (a
# `--plugin-dir` checkout under `~/My Projects/`) split in two at the paste. The poker here
# runs from a COPY of the payload under `<tmp>/my plugin/`, the layout an installed plugin has.
# Each printed command is parsed the way a pasting shell reads it (`eval set --`, nothing run)
# and the script path must come back as ONE argument naming the real file.
# fails-when: a printed poker path splits at the space.
s44_args() { eval "set -- $1"; printf '%s\n' "$@"; }  # <command text> -> its words, one per line
s44_word() { printf '%s\n' "$1" | sed -n "${2}p"; }    # <words> <n> -> the n-th
S44_ROOT="$TMPROOT/my plugin"
cp -RL "$(cd "$(dirname "$POKER")/../payload" && pwd -P)" "$S44_ROOT"
S44_POKER_SAVED="$POKER"; POKER="$S44_ROOT/hooks/session-poker.sh"
expect_true "44 precondition: the poker under test is the copy under a root with a space" test -f "$POKER"
S44_CFG="$(fake_config_dir s44-root)"
export CLAUDE_CONFIG_DIR="$S44_CFG"
S41_TR="$S44_CFG/projects/-fixture-project/$SID.jsonl"

R44P="$(make_repo s44-prompt)"
poke "$R44P" prompt
S44_TICK="$(printf '%s\n' "$OUT" | sed -n 's/.*then run: \(bash .*\) tick — the tick decides.*/\1 tick/p')"
expect_nonempty "44a the prompt names the tick command" "$S44_TICK"
S44_W="$(s44_args "$S44_TICK")"
expect_eq "44a2 …which parses as bash, the script and tick" "3" "$(printf '%s\n' "$S44_W" | grep -c '')"
expect_contains "44a3 …its script path one argument, space and all" "my plugin/hooks/session-poker.sh" "$(s44_word "$S44_W" 2)"
expect_true "44a4 …naming the real file" test -f "$(s44_word "$S44_W" 2)"
S44_HOLD="$(printf '%s\n' "$OUT" | sed -n "s/.*the hold line it prints: \(bash .* hold NAME 'why it stays up'\),.*/\1/p")"
expect_nonempty "44b the prompt names the hold command" "$S44_HOLD"
S44_W="$(s44_args "$S44_HOLD")"
expect_eq "44b2 …which parses as bash, the script, hold, NAME and the reason" "5" "$(printf '%s\n' "$S44_W" | grep -c '')"
expect_true "44b3 …its script path one argument naming the real file" test -f "$(s44_word "$S44_W" 2)"

R44S="$(s41_world s44-standdown)"
s41_transcript 1 "w-1:idle"
poke "$R44S" tick
S44_SD="$(printf '%s\n' "$OUT" | grep -F 'poker: STANDDOWN w-1' | sed -n 's/.*keep it up with: //p')"
expect_nonempty "44c the tick's STANDDOWN line prints its hold command" "$S44_SD"
S44_W="$(s44_args "$S44_SD")"
expect_eq "44c2 …which parses as bash, the script, hold, the name and the reason" "5" "$(printf '%s\n' "$S44_W" | grep -c '')"
expect_true "44c3 …its script path one argument naming the real file" test -f "$(s44_word "$S44_W" 2)"
expect_eq "44c4 …and the name is the row's" "w-1" "$(s44_word "$S44_W" 4)"

R44V="$(make_repo s44-pver)"; new_roster "$R44V"
add_row "$R44V" name=busy deliverable="$R44V/never-written.md" duration="4 hours" \
  launched_at="$(iso_ago 60)"
poke "$R44V" tick
S44_RA="$(printf '%s\n' "$OUT" | grep -F 're-arm the Patrol')"
expect_nonempty "44d the tick prints its re-arm note" "$S44_RA"
S44_ARM="$(printf '%s\n' "$S44_RA" | sed -n 's/.*then run `\(bash [^`]*\)`.*/\1/p')"
S44_W="$(s44_args "$S44_ARM")"
expect_eq "44d2 …whose arm command parses as bash, the script and arm" "3" "$(printf '%s\n' "$S44_W" | grep -c '')"
expect_true "44d3 …its script path one argument naming the real file" test -f "$(s44_word "$S44_W" 2)"
POKER="$S44_POKER_SAVED"
unset CLAUDE_CONFIG_DIR

# ============================================================
section "Section 45 §GATE: a reserved request reaches the lead through the Patrol tick, once (wave-25 T5; REQ-4 AC-4.3; D7)"
# ============================================================
#
# THE GAP. hooks/permission-answer.sh denies a reserved action (anything that leaves the
# machine, credentials, billing, production infrastructure) and appends one gate line per
# distinct request to `.bionic/tmp/gate-<lead sid>.state`. Nothing read that file, so a writer's
# denied push reached the lead only if the writer's report happened to say so. The tick reads it
# now: a request no tick has raised yet makes the band NOTIFY, prints one GATE line, and puts
# `gate=<count>:<categories>` last on the decision line. The digest records it as raised, so no
# later tick raises it again, whatever else moved; a new line raises again, and only itself.
#
# FIXTURE FIDELITY. The world is §41's DIGEST world (one open row inside its duration, a fresh
# panel), so the band without the gate is QUIET and every NOTIFY here is the gate's. Gate lines
# are written in the hook's own shape (the plan's Interfaces table: `gate/v1|at=|session=|asker=
# |category=|head=`); §GATE-dup writes them with the REAL hook instead, fed the platform's
# PermissionRequest payload twice (the shape tests/permission-answer.test.sh §A15 drives).
#
# ANTI-VACUITY. The decision-line extractor is proven on the control tick (45a reads QUIET
# through it) before any `gate=` absence is read through it, and every absence of `gate=` or of
# a GATE line sits beside a positive `decision=` read through the same extractor on the same
# output. The hook drive asserts the line exists and has the gate/v1 shape beside its count.
# fails-when: the tick ignores the gate file, or the hook appends a duplicate.

S45_CFG="$(fake_config_dir s45-gate)"
export CLAUDE_CONFIG_DIR="$S45_CFG"
S45_TR="$S45_CFG/projects/-fixture-project/$SID.jsonl"
gate_of() { printf '%s/.bionic/tmp/gate-%s.state' "$1" "${2:-$SID}"; }
gate_line() {  # <asker> <category> <head> -> one request in the hook's shape
  printf 'gate/v1|at=2026-10-03T23:00:00Z|session=%s|asker=%s|category=%s|head=%s\n' "$SID" "$1" "$2" "$3"
}
s45_world() {  # <label> -> a repo: armed, one open row inside its duration
  local r; r="$(make_repo "$1")"; new_roster "$r"; armed_ago "$r"
  add_row "$r" name=busy deliverable="$r/never-written.md" duration="4 hours" \
    launched_at="$(iso_ago 60)"
  printf '%s' "$r"
}
s45_line()  { printf '%s\n' "$1" | grep '^poker-tick/v1|' | tail -1; }  # <output> -> the decision line
s45_field() { s45_line "$1" | tr '|' '\n' | sed -n "s/^$2=//p" | head -1; }  # <output> <key>
s45_gates() { printf '%s\n' "$1" | grep -c '^poker: GATE ' | tr -d ' '; }  # <output> -> GATE lines
plant_answer "$S45_TR" fresh "busy:running"

# ---------- §GATE-a: no file and an empty file change nothing; one line raises NOTIFY ----------
R45="$(s45_world s45-gate)"
poke "$R45" tick
expect_eq "45a precondition: no gate file, the band read off the decision line is QUIET (exit 0)" \
  "QUIET|0" "$(s45_field "$OUT" decision)|$RC"
expect_eq "45a2 …and the line carries no gate= field" "" "$(s45_field "$OUT" gate)"
: > "$(gate_of "$R45")"
poke "$R45" tick
expect_regex "45a3 an empty gate file adds nothing to the digest: the next tick is the unchanged line" \
  "^poker: unchanged since [0-9TZ:-]+ — decision=QUIET$" "$OUT"
gate_line w99-T1 leaves-the-machine "git push origin wave/99-fx" >> "$(gate_of "$R45")"
poke "$R45" tick
expect_eq "45b AC-4.3 a gate line makes the tick decide NOTIFY (exit 1)" "NOTIFY|1" \
  "$(s45_field "$OUT" decision)|$RC"
expect_eq "45b2 …with a gate= field: the count and the category" "1:leaves-the-machine" \
  "$(s45_field "$OUT" gate)"
expect_regex "45b3 …last on the line, after the fields that were there" \
  '\|decision=NOTIFY\|total=[0-9]+\|open=[0-9]+(\|[a-z]+=[^|]*)*\|gate=1:leaves-the-machine$' "$(s45_line "$OUT")"
expect_eq "45b4 …so the open= reader cross-gate's la6_open_tick uses still reads it" "1" \
  "$(s45_line "$OUT" | sed -n 's/.*decision=[A-Z]*|total=[0-9]*|open=\([0-9]*\).*/\1/p')"
expect_eq "45b5 …and one GATE line" "1" "$(s45_gates "$OUT")"
expect_contains "45b6 …naming the asker, the category and the command head" \
  "poker: GATE w99-T1 — leaves-the-machine: git push origin wave/99-fx" "$OUT"
expect_contains "45b7 …under a sentence that says what to do with it" "put each GATE line below to the human once" "$OUT"

# ---------- §GATE-once: the next tick does not repeat it, whatever else moved ----------
poke "$R45" tick
expect_regex "45c AC-4.3 the next tick with no new line does not repeat it: it is the unchanged line" \
  "^poker: unchanged since [0-9TZ:-]+ — decision=QUIET$" "$OUT"
expect_eq "45c2 …exit 0, not NOTIFY's 1" "0" "$RC"
add_row "$R45" name=busy2 deliverable="$R45/never-written-2.md" duration="4 hours" \
  launched_at="$(iso_ago 60)"
plant_answer "$S45_TR" fresh "busy:running" "busy2:running"
poke "$R45" tick
expect_eq "45c3 another fact moved, so the tick prints in full and decides on the rows" "QUIET" \
  "$(s45_field "$OUT" decision)"
expect_eq "45c4 …the request already raised is not raised again: no gate= field" "" "$(s45_field "$OUT" gate)"
expect_eq "45c5 …and no GATE line" "0" "$(s45_gates "$OUT")"
armed_ago "$R45"
poke "$R45" tick
expect_eq "45c6 a re-arm drops the digest's hash, so the next tick prints in full" "QUIET" \
  "$(s45_field "$OUT" decision)"
expect_eq "45c7 …and keeps what was raised: no gate= field" "" "$(s45_field "$OUT" gate)"

# ---------- §GATE-new: a new request raises again, and only itself ----------
gate_line lead credentials "cat ~/.ssh/id_ed25519" >> "$(gate_of "$R45")"
poke "$R45" tick
expect_eq "45d a new line after a raised one raises again" "NOTIFY|1:credentials" \
  "$(s45_field "$OUT" decision)|$(s45_field "$OUT" gate)"
expect_eq "45d2 …with one GATE line" "1" "$(s45_gates "$OUT")"
expect_contains "45d3 …the new request's" "poker: GATE lead — credentials: cat ~/.ssh/id_ed25519" "$OUT"
expect_absent "45d4 …and not the one already raised" "git push origin wave/99-fx" "$OUT"

# ---------- §GATE-two: two requests at once are two lines and one NOTIFY ----------
R45T="$(s45_world s45-two)"
{ gate_line w99-T1 leaves-the-machine "gh pr create --fill"
  gate_line w99-T2 credentials "gh auth token"
} > "$(gate_of "$R45T")"
poke "$R45T" tick
expect_eq "45e two different requests: one decision line, NOTIFY" "1|NOTIFY" \
  "$(printf '%s\n' "$OUT" | grep -c '^poker-tick/v1|' | tr -d ' ')|$(s45_field "$OUT" decision)"
expect_eq "45e2 …carrying the count and both categories, sorted" "2:credentials,leaves-the-machine" \
  "$(s45_field "$OUT" gate)"
expect_eq "45e3 …and two GATE lines" "2" "$(s45_gates "$OUT")"
expect_contains "45e4 …one for each request" "poker: GATE w99-T2 — credentials: gh auth token" "$OUT"
expect_contains "45e5 …the other's too" "poker: GATE w99-T1 — leaves-the-machine: gh pr create --fill" "$OUT"

# ---------- §GATE-bad: a malformed line is ignored, and the tick still decides ----------
R45M="$(s45_world s45-malformed)"
{ printf 'not a gate line\n'
  printf 'gate/v1|at=2026-10-03T23:00:00Z|session=%s|asker=w99-T1|head=no category here\n' "$SID"
  printf 'gate/v1|at=2026-10-03T23:00:00Z|session=another-session|asker=w99-T1|category=billing|head=a neighbour request\n'
  printf 'gate/v9|at=2026-10-03T23:00:00Z|session=%s|asker=w99-T1|category=billing|head=a future schema\n' "$SID"
  printf 'gate/v1|at=2026-10-03T23:00:00Z|session=%s|asker=|category=billing|head=no asker\n' "$SID"
} > "$(gate_of "$R45M")"
poke "$R45M" tick
expect_eq "45f malformed lines only: the tick completes and decides on the rows (QUIET, exit 0)" \
  "QUIET|0" "$(s45_field "$OUT" decision)|$RC"
expect_eq "45f2 …raising none of them: no gate= field" "" "$(s45_field "$OUT" gate)"
gate_line w99-T1 billing "stripe charges create" >> "$(gate_of "$R45M")"
poke "$R45M" tick
expect_eq "45f3 …and a valid line among them is raised alone" "NOTIFY|1:billing|1" \
  "$(s45_field "$OUT" decision)|$(s45_field "$OUT" gate)|$(s45_gates "$OUT")"

# ---------- §GATE-link: a symlinked gate file is refused, not followed ----------
R45L="$(s45_world s45-link)"
gate_line w99-T1 leaves-the-machine "git push --force origin main" > "$TMPROOT/s45-elsewhere.state"
ln -s "$TMPROOT/s45-elsewhere.state" "$(gate_of "$R45L")"
poke "$R45L" tick
expect_eq "45g a symlinked gate file: the tick decides on the rows" "QUIET" "$(s45_field "$OUT" decision)"
expect_eq "45g2 …the link's target is not raised: no gate= field" "" "$(s45_field "$OUT" gate)"
expect_absent "45g3 …and its request is not printed" "git push --force origin main" "$OUT"
expect_contains "45g4 …the refusal is said, as a note" "is a symlink" "$OUT"

# ---------- §GATE-first: the armed tick before any dispatch raises it too ----------
R45F="$(make_repo s45-first)"; armed_ago "$R45F"
gate_line lead leaves-the-machine "git push origin wave/99-fx" > "$(gate_of "$R45F")"
poke "$R45F" tick
expect_eq "45h no roster yet (armed, nothing dispatched): NOTIFY, gate=, exit 1" \
  "NOTIFY|1:leaves-the-machine|1" "$(s45_field "$OUT" decision)|$(s45_field "$OUT" gate)|$RC"
expect_contains "45h2 …with its GATE line" "poker: GATE lead — leaves-the-machine: git push origin wave/99-fx" "$OUT"

# ---------- §GATE-disarm: DISARM outranks NOTIFY, and still carries the request ----------
R45X="$(make_repo s45-disarm)"; new_roster "$R45X"; armed_ago "$R45X"; delivered_plan "$R45X"
gate_line lead leaves-the-machine "git push origin main" > "$(gate_of "$R45X")"
poke "$R45X" tick
expect_eq "45i a delivered run with a request pending: the band stays DISARM (exit 0)" "DISARM|0" \
  "$(s45_field "$OUT" decision)|$RC"
expect_eq "45i2 …and the line still carries gate=" "1:leaves-the-machine" "$(s45_field "$OUT" gate)"
expect_contains "45i3 …under its GATE line" "poker: GATE lead — leaves-the-machine: git push origin main" "$OUT"

# ---------- §GATE-dup: the REAL hook, asked the same reserved question twice, leaves one line ----------
# Overridable for the planted defect, never by editing the hook in the tree:
#   W25_GATE_HOOK_UNDER_TEST=<copy>/hooks/permission-answer.sh bash tests/session-poker.test.sh
S45_HOOK="${W25_GATE_HOOK_UNDER_TEST:-${BIONIC_HOOKS_DIR}/permission-answer.sh}"
expect_true "45j precondition: the hook under test exists" test -f "$S45_HOOK"
gate_ask() {  # <repo> <command> -> sets GATE_ANSWER, the decision's behavior
  local pl
  pl="$(jq -n --arg s "$SID" --arg c "$1" --arg cmd "$2" \
    '{session_id:$s, transcript_path:"/dev/null", cwd:$c, permission_mode:"bypassPermissions",
      hook_event_name:"PermissionRequest", tool_name:"Bash",
      tool_input:{command:$cmd, description:"a fixture command"}, permission_suggestions:[]}')"
  GATE_ANSWER="$( cd "$1" && printf '%s' "$pl" \
    | env HOME="$TMPROOT/s45-home" CLAUDE_PROJECT_DIR="$1" CLAUDE_CODE_SESSION_ID="$SID" bash "$S45_HOOK" 2>/dev/null \
    | jq -r '.hookSpecificOutput.decision.behavior // "none"' 2>/dev/null )"
}
R45H="$(s45_world s45-hook)"
gate_ask "$R45H" "git push origin wave/99-fx"
expect_eq "45j2 the lead's git push: the hook denies it" "deny" "$GATE_ANSWER"
gate_ask "$R45H" "git push origin wave/99-fx"
expect_eq "45j3 …asked again, denied again" "deny" "$GATE_ANSWER"
expect_regex "45j4 …and the request is on file in the gate/v1 shape" \
  "^gate/v1\|at=[0-9TZ:-]+\|session=$SID\|asker=lead\|category=leaves-the-machine\|head=git push origin wave/99-fx$" \
  "$(head -1 "$(gate_of "$R45H")" 2>/dev/null)"
expect_eq "45j5 AC-4.3 the same request twice leaves one line" "1" \
  "$(grep -c '' "$(gate_of "$R45H")" 2>/dev/null | tr -d ' ')"
poke "$R45H" tick
expect_eq "45j6 …which the tick raises once: NOTIFY, one request, one GATE line" "NOTIFY|1:leaves-the-machine|1" \
  "$(s45_field "$OUT" decision)|$(s45_field "$OUT" gate)|$(s45_gates "$OUT")"

# ---------- §GATE-prompt: the Patrol prompt says what gate= means, and the version moved ----------
poke "$R45T" prompt
expect_contains "45k the Patrol prompt names the gate= field" "gate=" "$OUT"
expect_contains "45k2 …as a gate act for the human, through the human's own notify channel" \
  "through the human's own notify channel" "$OUT"
expect_contains "45k3 …and not to be performed" "do not perform it" "$OUT"
S45_V="$(printf '%s\n' "$OUT" | sed -n 's/^bionic-patrol session=[^ ]* v=\([0-9]*\) .*/\1/p')"
expect_regex "45k4 the prompt's version moved past 2, the version before the gate sentence" '^([3-9]|[1-9][0-9]+)$' "$S45_V"
printf 'patrol-digest/v1\nprompt_version=2\n' > "$(digest_of "$R45T")"
poke "$R45T" tick
expect_contains "45k5 …so a Patrol armed under v=2 is told to re-arm" \
  "its prompt is v=2 and this poker prints v=${S45_V}" "$OUT"
unset CLAUDE_CONFIG_DIR

# ============================================================
section "Section 47 §WAIT: the tick names every pending row — FILL or WAIT, with its unmet read and writer — and the longest chain (wave-26 T13; REQ-6 AC-6.6; D9)"
# ============================================================
#
# A TABLE WITH A `reads` COLUMN, so every row waits for what it reads and the kind defaults
# apply (D1). The fixture carries one row of each way to wait: a path an active row writes
# (T2), an external prerequisite (T3), an approval nobody has given (T4, the release), and the
# settled head every open code row writes (T6, the floor). T5 reads only the plan's approval
# and is the one ready writer. Sizes are minutes, so the longest chain is checkable by hand:
# T1 (30) → T2 (20) → T6 (60) = 110, against T5 (40) → T6 = 100 and T4 (15) → T6 = 75.
s47_plan() {  # <repo> <writers> <row>... -> the path; a reads table, approved, current: 4
  local repo="$1" writers="$2"; shift 2
  local f="$repo/.bionic/docs/plans/epic-99-fixture/wave-01-fixture.plan.md" row
  mkdir -p "$(dirname "$f")"
  {
    printf -- '---\ngoverning-skill: superpowers:writing-plans\n'
    printf 'parallel-budget: writers=%s suites=2 worktrees=8 test_jobs=8 source=probe\n' "$writers"
    printf -- '---\n\n# fixture plan\n\n## SDLC State\n\ncurrent: 4\n%s\n\n- Step 4: in progress\n\n' "$SP_APPROVED_LINE"
    printf '## Tasks\n\n'
    printf '| id | step | kind | task | agent | deps | size | serves | Files | status | reads |\n'
    printf '|---|---|---|---|---|---|---|---|---|---|---|\n'
    for row in "$@"; do printf '%s\n' "$row"; done
  } > "$f"
  touch "$f"
  printf '%s' "$f"
}
s47_lines() { printf '%s\n' "$OUT" | /usr/bin/grep "^poker: $1 " ; }  # <WAIT|FILL|CHAIN>

R47="$(make_repo s46-wait)"; new_roster "$R47"
s47_plan "$R47" 2 \
  "| T1 | 4 | build | in flight | implementor | — | 30 | REQ-x | payload/x.sh | active | |" \
  "| T2 | 4 | build | reads what T1 writes | implementor | — | 20 | REQ-x | payload/y.sh | pending | payload/x.sh |" \
  "| T3 | 4 | build | held by the world | implementor | ext:vendor-fix | 10 | REQ-x | payload/z.sh | pending | |" \
  "| T4 | 7 | doc | the release | implementor | — | 15 | REQ-x | CHANGELOG.md | pending | approval:release |" \
  "| T5 | 4 | build | ready | implementor | — | 40 | REQ-x | payload/w.sh | pending | |" \
  "| T6 | 5 | verify | the floor | auditor | — | 60 | REQ-x | .bionic/docs/record/floor.md | pending | |" >/dev/null
poke_pressure "$R47" 8192 1.0 tick
expect_eq "47a the tick over a reads table exits 0" "0" "$RC"
expect_nonempty "47a2 …and prints WAIT lines (the extractor reads real output)" "$(s47_lines WAIT)"
expect_contains "47b the one ready writer is filled" "poker: FILL T5" "$OUT"
expect_contains "47c a path read names the row that writes it and its status" \
  "poker: WAIT T2 — reads payload/x.sh, written by T1 (active)" "$OUT"
expect_contains "47d an external prerequisite is named as itself" "poker: WAIT T3 — ext:vendor-fix" "$OUT"
expect_eq "47e the release waits for its approval and nothing else — no step hold in a reads table" \
  "poker: WAIT T4 — approval:release" "$(s47_lines WAIT | /usr/bin/grep '^poker: WAIT T4 ')"
expect_contains "47f the floor names the head's writers, the active one first" \
  "poker: WAIT T6 — reads head, written by T1 (active), T2 (pending)" "$OUT"
# AC-6.6: EVERY PENDING ROW IS ON A FILL OR A WAIT LINE, the fixture's ids walked one by one.
S47_FILL="$(s47_lines FILL)"
for _s47 in T2 T3 T4 T5 T6; do
  _s47_on=no
  case " ${S47_FILL#poker: FILL } " in *" $_s47 "*) _s47_on=fill ;; esac
  [ -n "$(s47_lines WAIT | /usr/bin/grep "^poker: WAIT $_s47 — ")" ] && _s47_on="${_s47_on/no/wait}"
  expect_ne "47g AC-6.6 pending $_s47 is on a FILL or a WAIT line" "no" "$_s47_on"
done
expect_absent "47g2 …and the active row is on neither (it is not pending)" "WAIT T1 " "$(s47_lines WAIT)"
expect_absent "47h the bulk sentence is gone" "none has all its dependencies landed" "$OUT"
expect_eq "47i AC-6.6 the CHAIN line is the fixture's longest chain, by hand: 30 + 20 + 60" \
  "poker: CHAIN T1→T2→T6 (110 min)" "$(s47_lines CHAIN)"
# THE DIFFERENTIAL: land T1 and the chain moves to the next heaviest path, so 47i reads the
# graph and not a constant.
sed -i.bak 's/| payload\/x.sh | active |/| payload\/x.sh | landed |/' "$R47/.bionic/docs/plans/epic-99-fixture/wave-01-fixture.plan.md"
poke_pressure "$R47" 8192 1.0 tick
expect_eq "47j with T1 landed the chain is T5 → T6 (40 + 60)" "poker: CHAIN T5→T6 (100 min)" "$(s47_lines CHAIN)"
expect_contains "47j2 …and T2, its read now landed, is filled beside T5" "poker: FILL T2 T5" "$OUT"

# ============================================================
section "Section 47 §READY-EARLY (tick half): a doc row whose reads exist is offered before its step; a read-only row outside the writer gap (wave-26 T13; REQ-6 AC-6.1; D3, D9)"
# ============================================================
#
# current: 4 and one task landed. The Step-7 doc row reads the plan approval and the head, and
# nothing open writes the head, so it is ready now — it is not held until current: 7 (D3). The
# review row (kind review) takes no writer slot, so it is offered whatever the writer gap.
# A Step-7 doc row names the approval it waits for (wave-26 T62; K2-F3): this one is notes, not the
# release, so it reads approval:plan.
s47_early() {  # <repo> -> the plan; writers=1
  s47_plan "$1" 1 \
    "| T1 | 4 | build | landed | implementor | — | 30 | REQ-x | payload/x.sh | landed | |" \
    "| T2 | 7 | doc | the release notes draft | implementor | — | 20 | REQ-x | .bionic/docs/record/notes.md | pending | approval:plan, head |" \
    "| T3 | 6 | review | the review | critic | — | 30 | REQ-x | .bionic/docs/record/review.md | pending | |" >/dev/null
}
R47E="$(make_repo s46-early)"; new_roster "$R47E"; s47_early "$R47E"
poke_pressure "$R47E" 8192 1.0 tick
expect_contains "47k AC-6.1 at current: 4 the tick offers the doc row and the review row" "poker: FILL T2 T3" "$OUT"
# THE WRITER GAP CLOSED: one writer open, writers=1. The doc row is a writer and waits for a
# slot; the review is read-only and is still offered.
R47F="$(make_repo s46-early-full)"; new_roster "$R47F"; s47_early "$R47F"
add_row "$R47F" name=w1 deliverable=a.md duration="4 hours" launched_at="$(iso_ago 60)"
poke_pressure "$R47F" 8192 1.0 tick
expect_contains "47l D9 with no writer slot free the read-only review is still offered" "poker: FILL T3" "$OUT"
expect_absent "47l2 …and the doc row, a writer, is not on the FILL line" "T2" "$(s47_lines FILL)"
expect_contains "47l3 …it is on a WAIT line saying it is ready and waits for a writer slot" \
  "poker: WAIT T2 — ready; no writer slot free" "$OUT"
# REVIEW 10 ANSWER (b) (wave-26 T46): THE EXEMPTION IS THE RECORD, NOT THE KIND ALONE. A verify
# row whose Files name tracked code was offered with no slot free, then demanded by the wall and
# refused by the budget. It now takes a writer place like any writer; the same row writing only
# the record is still offered outside the gap.
s47_verify() {  # <repo> <T4 Files> -> the plan; writers=1, one writer open
  s47_plan "$1" 1 \
    "| T1 | 4 | build | landed | implementor | — | 30 | REQ-x | payload/x.sh | landed | |" \
    "| T4 | 5 | verify | the floor | test-runner | — | 30 | REQ-x | $2 | pending | |" >/dev/null
  add_row "$1" name=w1 deliverable=a.md duration="4 hours" launched_at="$(iso_ago 60)"
}
R47G="$(make_repo s47-verify-code)"; new_roster "$R47G"; s47_verify "$R47G" "payload/v.sh"
poke_pressure "$R47G" 8192 1.0 tick
expect_contains "47l4 b a verify row naming tracked code, no writer slot free: one WAIT line with the budget reason" \
  "poker: WAIT T4 — ready; no writer slot free" "$OUT"
expect_absent "47l5 …and it is not on a FILL line" "T4" "$(s47_lines FILL)"
R47H="$(make_repo s47-verify-record)"; new_roster "$R47H"; s47_verify "$R47H" ".bionic/docs/record/floor.md"
poke_pressure "$R47H" 8192 1.0 tick
expect_contains "47l6 b the same row writing only the record, no writer slot free: offered" "poker: FILL T4" "$OUT"

# ============================================================
section "Section 47 §APPROVE: approve <name> '<reply>' writes the approved: line through the verb transaction (wave-26 T13; REQ-6 AC-6.2; D3)"
# ============================================================
S47_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
R47A="$(make_repo s46-approve)"; ( cd "$R47A" && git commit -q --allow-empty -m init )
git -C "$R47A" config user.name "Dana Fixture"
P47A="$(s42_plan "$R47A" 4)"
# A READS TABLE (wave-26 T46; review 10 F6): approve records only a name some row reads, so the
# fixture's open rows read two — T5 `approval:release`, the active T2 `live:approval:ship`; the
# landed T1 reads `live:approval:landedonly`, which satisfies nothing (wave-26 T52; review 14 N4).
awk '
  /^\| id \| step \|/ { print $0 " reads |"; next }
  /^\|---\|/ { print $0 "---|"; next }
  /^\| T1 \|/ { print $0 " live:approval:landedonly |"; next }
  /^\| T2 \|/ { print $0 " live:approval:ship |"; next }
  /^\| T5 \|/ { sub(/\| T1, T2 \|/, "| — |"); print $0 " approval:release |"; next }
  /^\| T[0-9]+ \|/ { print $0 "  |"; next }
  { print }' "$P47A" > "$P47A.tmp" && mv "$P47A.tmp" "$P47A"
s42_snap "$R47A" "$P47A"
s34_gate "$R47A"
expect_eq "47m0 precondition: the reads-table fixture is admitted by the real commit gate" "0" "$GATE_RC"
poke "$R47A" approve release 'Ship it.'
expect_eq "47m approve release exits 0" "0" "$RC"
expect_contains "47m2 …and says what it wrote" "approve — release" "$OUT"
S47_LINE="$(/usr/bin/grep '^approved: release ' "$P47A")"
expect_regex "47n the line is approved: <name> by <git user> <ISO-UTC> \"<reply>\"" \
  '^approved: release by Dana Fixture [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z "Ship it\."$' "$S47_LINE"
expect_eq "47n2 …inside ## SDLC State, ahead of the next section" "SDLC" \
  "$(awk '/^## /{ s = $2 } /^approved: release /{ print s; exit }' "$P47A")"
expect_eq "47n3 …and git diff --numstat shows one line added, none removed" "1 0;" "$(s42_numstat "$R47A")"
s34_gate "$R47A"
expect_eq "47o the commit gate admits the approved plan" "0" "$GATE_RC"
s42_snap "$R47A" "$P47A"
poke "$R47A" approve release 'Again.'
s42_unchanged "47p a second approve of the same name" 1 "$P47A"
expect_contains "47p2 …naming the line already there" "approved: release" "$OUT"
poke "$R47A" approve plan 'approved'
s42_unchanged "47q approve plan" 1 "$P47A"
expect_contains "47q2 …saying the plan's approval is the approved-by: line written at Step 3" \
  "approved-by:" "$OUT"
expect_contains "47q3 …at Step 3" "Step 3" "$OUT"
poke "$R47A" approve 'rel|x' 'ok'
s42_unchanged "47r a name outside the approval:<name> grammar" 2 "$P47A"
poke "$R47A" approve integrate "a
b"
s42_unchanged "47s a reply carrying a line break" 1 "$P47A"
poke "$R47A" approve integrate
s42_unchanged "47t no reply at all" 2 "$P47A"
# REVIEW 10 F6: A NAME NO ROW READS IS REFUSED, and the refusal lists the names that are read,
# so a mistyped name is not recorded "once" while the row it was meant for waits in silence.
# The match is exact: a name in another case is another name.
poke "$R47A" approve relase 'Ship it.'
s42_unchanged "47t2 F6 a name no row reads (a typo of release)" 1 "$P47A"
expect_contains "47t3 …naming the names the rows read" "the rows read: release ship" "$OUT"
poke "$R47A" approve Release 'Ship it.'
s42_unchanged "47t4 F6 the read name in another case" 1 "$P47A"
# REVIEW 14 N4 (wave-26 T52): a name only the landed T1 reads satisfies nothing, so it is refused
# and is not among the names listed.
poke "$R47A" approve landedonly 'Go.'
s42_unchanged "47t4b N4 a name read only by a landed row" 1 "$P47A"
expect_contains "47t4c …listing only the names open rows read" "the rows read: release ship" "$OUT"
poke "$R47A" approve ship 'Go.'
expect_eq "47t5 F6 a name read as live:approval:<name> is recorded" "0" "$RC"
expect_contains "47t6 …the line written" "approved: ship by Dana Fixture" "$(cat "$P47A")"
POKE_BOUND="$S47_BOUND_WAS"

# ============================================================
section "Section 47 §WAITING-READY: WAITING says nothing is ready only when nothing is (wave-26 T13; review-6 F3; D9, D16)"
# ============================================================
#
# A QUIET tick with a row running printed `WAITING — <n> running, nothing ready` whatever the
# ready set held, so a full writer budget or a standing fill-declined read as "nothing ready"
# while a row was ready. Each such row now has its WAIT line saying why, and WAITING prints only
# when the untrimmed ready set is empty. Three worlds over one table shape, writers=1 and one
# writer running: a ready row the budget cannot take, a ready row the standing decline answered
# (writers=2, so a slot is free), and the control where the row waits on an unlanded read.
s47_quiet() {  # <repo> <writers> <T2 reads> -> the plan; T9 active, T2 pending, one writer open
  s47_plan "$1" "$2" \
    "| T9 | 4 | build | in flight | implementor | — | 30 | REQ-x | payload/q.sh | active | |" \
    "| T2 | 4 | build | the row | implementor | — | 20 | REQ-x | payload/r.sh | pending | $3 |" >/dev/null
  add_row "$1" name=w1 deliverable="$1/never-written.md" duration="4 hours" launched_at="$(iso_ago 60)"
}
R47Q="$(make_repo s47-waiting-full)"; new_roster "$R47Q"; s47_quiet "$R47Q" 1 ""
poke_pressure "$R47Q" 8192 1.0 tick
expect_contains "47u F3 a full writer budget names the ready row it cannot take, and why" \
  "poker: WAIT T2 — ready; no writer slot free" "$OUT"
expect_absent "47u2 …and does not say nothing is ready" "poker: WAITING" "$OUT"
R47R="$(make_repo s47-waiting-declined)"; new_roster "$R47R"; s47_quiet "$R47R" 2 ""
mkdir -p "$R47R/.bionic/docs/record/wave-01-fixture"
printf 'fill-ledger/v1|at=2026-10-04T00:00:00Z|session=%s|turn=u-47r|current=4|state=ok|ceiling=2|width=2|open=1|free=1|ready=T2|launched=|declined=T2 waits on the merge|missed=1\n' "$SID" \
  > "$R47R/.bionic/docs/record/wave-01-fixture/fill-ledger.log"
poke_pressure "$R47R" 8192 1.0 tick
expect_contains "47v precondition: the standing decline is read" "fill-declined standing since" "$OUT"
expect_contains "47v2 F3 a ready row the standing decline answered is named, and why" \
  "poker: WAIT T2 — ready; answered by the standing fill-declined" "$OUT"
expect_absent "47v3 …and the tick does not say nothing is ready" "poker: WAITING" "$OUT"
R47S="$(make_repo s47-waiting-none)"; new_roster "$R47S"; s47_quiet "$R47S" 1 "payload/q.sh"
poke_pressure "$R47S" 8192 1.0 tick
expect_contains "47w the control: the row waits on what T9 writes, on its WAIT line" \
  "poker: WAIT T2 — reads payload/q.sh, written by T9 (active)" "$OUT"
expect_contains "47w2 …and with nothing ready and a row running, WAITING prints" \
  "poker: WAITING — 1 running, nothing ready" "$OUT"

# ============================================================
section "Section 46 §PROOF-ADD: a proof names the head it read (wave-26 T4; REQ-3 AC-3.2; D5)"
# ============================================================
#
# `proof-add <floor|review|task> <evidence>` writes one line inside `## SDLC State`:
# `proved: kind=<kind> head=<40-hex> at=<ISO-UTC> evidence=<path under record/>`. The head
# is never an operand: it is the one the evidence names (a run log's `head=` header, a
# review's `reviewed: a..b` end; T14), held against the checkout holding the plan's
# `working-branch:`, which here is a linked worktree one commit ahead of the main checkout,
# so a head read from the cwd would be the wrong one. The write is §42's transaction: a
# copy, a dry commit through the real gate, a checksum, a swap; every refusal leaves the
# plan byte-identical. `proof_last <plan> <kind>` (payload/scripts/lib/proof.sh) reads the
# newest line of a kind back.
S46_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
S46_LIB="${BIONIC_HOOKS_DIR}/../payload/scripts/lib/proof.sh"
s46_last() {  # <plan> <kind> -> proof_last's answer, from the library itself
  bash -c '. "$1" && proof_last "$2" "$3"' _ "$S46_LIB" "$1" "$2" 2>/dev/null
}
s46_proved() { /usr/bin/grep -E '^proved: ' "$1"; }  # <plan> -> its proof lines

R46="$(make_repo s46-proof)"; ( cd "$R46" && git commit -q --allow-empty -m init )
P46="$(s42_plan "$R46" 4)"
awk '{ print } /^current: / && !d { print "working-branch: wave/01-fixture"; d = 1 }' "$P46" > "$P46.tmp" && mv "$P46.tmp" "$P46"
# THREE SUITES ARE THE ROSTER (wave-26 T52; review 14 N1): a floor log's `Gating:` tally must
# count every tests/*.test.sh at the head it read, so the fixture's logs say 3.
mkdir -p "$R46/tests"
for s46s in a b c; do printf '#!/bin/bash\n' > "$R46/tests/$s46s.test.sh"; done
( cd "$R46" && git add -f "$P46" tests && git commit -qm wb \
  && git worktree add -q -b wave/01-fixture "$R46/.worktrees/01-fixture" \
  && git -C "$R46/.worktrees/01-fixture" commit -q --allow-empty -m "wave work" ) >/dev/null 2>&1
W46_HEAD="$(git -C "$R46/.worktrees/01-fixture" rev-parse HEAD 2>/dev/null)"
mkdir -p "$R46/.bionic/docs/record/wave-01-fixture" "$R46/.bionic/docs/plans/elsewhere"
# THE EVIDENCE ATTESTS ITS HEAD (wave-26 T14; review 7 F1): a floor log carries the suite runner's
# header line `head=<sha> dirty=<n>`, a review its `reviewed: <a>..<b>` line.
printf 'floor log\nenv: os=fixture\nhead=%s dirty=0\nall suites passed\nGating: 3 passed, 0 failed\n' "$W46_HEAD" > "$R46/.bionic/docs/record/wave-01-fixture/floor.txt"
printf 'review notes\n' > "$R46/.bionic/docs/record/wave-01-fixture/review.md"
printf 'not a record\n' > "$R46/.bionic/docs/plans/elsewhere/notes.md"
expect_regex "46a0 precondition: the working branch's checkout has a 40-hex head" '^[0-9a-f]{40}$' "$W46_HEAD"
expect_true "46a0b precondition: …which is not the main checkout's head" \
  test "$W46_HEAD" != "$(git -C "$R46" rev-parse HEAD)"
s34_gate "$R46"
expect_eq "46a0c precondition: the fixture plan is admitted by the real commit gate" "0" "$GATE_RC"
expect_eq "46a0d precondition: the plan carries no proof line yet" "" "$(s46_proved "$P46")"
expect_true "46a0e precondition: proof.sh is in the tree under test" test -r "$S46_LIB"

# ---------- the write ----------
s42_snap "$R46" "$P46"
poke "$R46" proof-add floor record/wave-01-fixture/floor.txt
expect_eq "46a proof-add floor exits 0" "0" "$RC"
expect_contains "46a2 …and says what it wrote" "proof-add — kind=floor head=$W46_HEAD" "$OUT"
expect_eq "46a3 …git diff --numstat shows one line added" "1 0;" "$(s42_numstat "$R46")"
expect_regex "46a4 …in the proof line's shape, with the working branch's head" \
  "^proved: kind=floor head=${W46_HEAD} at=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z evidence=record/wave-01-fixture/floor.txt$" \
  "$(s46_proved "$P46")"
expect_eq "46a5 …inside ## SDLC State" "SDLC" \
  "$(awk '/^##[[:space:]]/ { s = $2 } /^proved: / { print s; exit }' "$P46")"
expect_eq "46a6 proof_last reads the floor head back" "$W46_HEAD" "$(s46_last "$P46" floor)"
expect_eq "46a7 …and a kind never proved reads nothing" "" "$(s46_last "$P46" review)"
s34_gate "$R46"
expect_eq "46a8 …and the next commit is admitted" "0" "$GATE_RC"

# A later proof of the same kind is the one proof_last reads; an absolute path under record/
# is written docs-root relative.
git -C "$R46/.worktrees/01-fixture" commit -q --allow-empty -m "more wave work" >/dev/null 2>&1
W46_HEAD2="$(git -C "$R46/.worktrees/01-fixture" rev-parse HEAD 2>/dev/null)"
# The review names what it read in abbreviated form; the proof names the commit it resolves to.
printf '# review\n\nreviewed: %s..%s (the fixture)\n\nnotes\n' "${W46_HEAD:0:8}" "${W46_HEAD2:0:10}" \
  > "$R46/.bionic/docs/record/wave-01-fixture/review.md"
s42_snap "$R46" "$P46"
poke "$R46" proof-add review "$R46/.bionic/docs/record/wave-01-fixture/review.md"
expect_eq "46b proof-add review by absolute path exits 0" "0" "$RC"
expect_eq "46b2 …one line added" "1 0;" "$(s42_numstat "$R46")"
expect_contains "46b3 …naming the evidence under record/" \
  "proved: kind=review head=${W46_HEAD2} " "$(s46_proved "$P46")"
expect_contains "46b4 …docs-root relative" "evidence=record/wave-01-fixture/review.md" "$(s46_proved "$P46" | tail -1)"
# REVIEW 7 F1: THE SAME FLOOR LOG AFTER A LANDING PROVES NOTHING NEW. The log read W46_HEAD; the
# branch has moved to W46_HEAD2 with no run, so re-citing it is refused and the floor proof
# stays at the head the run read. A log of a run at W46_HEAD2 proves W46_HEAD2.
s42_snap "$R46" "$P46"
poke "$R46" proof-add floor record/wave-01-fixture/floor.txt
s42_unchanged "46b5 F1 the floor log of the old head, after a landing" 1 "$P46"
expect_contains "46b5b …naming both heads and the fix" \
  "read head ${W46_HEAD:0:12}, but the working branch is at ${W46_HEAD2:0:12}; run it again on ${W46_HEAD2:0:12}" "$OUT"
expect_eq "46b6 F1 proof_last floor still reads the head the run read" "$W46_HEAD" "$(s46_last "$P46" floor)"
printf 'floor log\nhead=%s dirty=0\nGating: 3 passed, 0 failed\n' "$W46_HEAD2" > "$R46/.bionic/docs/record/wave-01-fixture/floor2.txt"
s42_snap "$R46" "$P46"
poke "$R46" proof-add floor record/wave-01-fixture/floor2.txt
expect_eq "46b6b …a log of a run at the new head exits 0" "0" "$RC"
expect_eq "46b6c …and proof_last floor reads the new head" "$W46_HEAD2" "$(s46_last "$P46" floor)"
expect_eq "46b7 …and the review head is its own, resolved from the review's reviewed: line" "$W46_HEAD2" "$(s46_last "$P46" review)"
expect_eq "46b8 …the proof lines sit together, newest last" "floor review floor" \
  "$(s46_proved "$P46" | sed -E 's/^proved: kind=([a-z]+) .*/\1/' | tr '\n' ' ' | sed 's/ $//')"

# ---------- F1: what the evidence must attest, each refusal naming its fix ----------
S46_REC="$R46/.bionic/docs/record/wave-01-fixture"
printf 'floor log\nhead=%s dirty=3\n' "$W46_HEAD2" > "$S46_REC/floor-dirty.txt"
printf 'floor log\nhead=none dirty=none\n' > "$S46_REC/floor-norepo.txt"
printf 'a log with no run header\n' > "$S46_REC/floor-bare.txt"
printf '# review\n\nno range here\n' > "$S46_REC/review-bare.md"
printf '# review\n\nreviewed: %s..0123456789abcdef0123456789abcdef01234567\n' "${W46_HEAD:0:8}" > "$S46_REC/review-gone.md"
S46_SIDE="$(git -C "$R46" commit-tree -p "$W46_HEAD" -m "a side commit" "$(git -C "$R46" rev-parse "$W46_HEAD^{tree}")" 2>/dev/null)"
printf '# review\n\nreviewed: %s..%s\n' "${W46_HEAD:0:8}" "$S46_SIDE" > "$S46_REC/review-side.md"
printf '# review\n\nreviewed: %s..%s\n' "${W46_HEAD:0:8}" "$W46_HEAD" > "$S46_REC/review-older.md"
expect_regex "46f0 precondition: the side commit exists" '^[0-9a-f]{40}$' "$S46_SIDE"
s42_snap "$R46" "$P46"
poke "$R46" proof-add floor record/wave-01-fixture/floor-dirty.txt
s42_unchanged "46f F1 a run at the head on a dirty tree" 1 "$P46"
expect_contains "46f2 …naming the dirt and the fix" "dirty tree (dirty=3); commit, run it again" "$OUT"
poke "$R46" proof-add floor record/wave-01-fixture/floor-norepo.txt
s42_unchanged "46f3 F1 a run that read no repository (head=none)" 1 "$P46"
poke "$R46" proof-add floor record/wave-01-fixture/floor-bare.txt
s42_unchanged "46f4 F1 a floor evidence with no run header" 1 "$P46"
expect_contains "46f5 …naming the line it needs" "carries no head=<sha> dirty=<n> line" "$OUT"
poke "$R46" proof-add review record/wave-01-fixture/review-bare.md
s42_unchanged "46f6 F1 a review with no reviewed: line" 1 "$P46"
expect_contains "46f7 …naming the line it needs" "carries no reviewed: <a>..<b> line" "$OUT"
poke "$R46" proof-add review record/wave-01-fixture/review-gone.md
s42_unchanged "46f8 F1 a review that read a commit this repository lacks" 1 "$P46"
poke "$R46" proof-add review record/wave-01-fixture/review-side.md
s42_unchanged "46f9 F1 a review of a commit off the working branch" 1 "$P46"
expect_contains "46f10 …naming it" "which is not on the working branch" "$OUT"
poke "$R46" proof-add floor record/wave-01-fixture/review-older.md
s42_unchanged "46f11 a floor proof never reads a review's range" 1 "$P46"
# REVIEW 10 F1 (wave-26 T5): A RUN AT THE HEAD MUST ALSO HAVE PASSED. The header says which head
# the run read, the runner's last `Gating:` line how it ended; a red run, a note quoting the
# header, a void suite, and a green inner verdict above a red outer one prove nothing. The green
# log at the same head (floor2.txt, 46b6b) is this block's positive control.
printf 'floor log\nhead=%s dirty=0\nGating: 40 passed, 3 failed\n' "$W46_HEAD2" > "$S46_REC/floor-red.txt"
printf '# review notes\nThe runner printed:\nhead=%s dirty=0\n(no run here)\n' "$W46_HEAD2" > "$S46_REC/floor-quote.txt"
printf 'floor log\nhead=%s dirty=0\nGating: 40 passed, 0 failed\nVoid: 1 — not timed\n' "$W46_HEAD2" > "$S46_REC/floor-void.txt"
printf 'floor log\nhead=%s dirty=0\n───── x: captured output ─────\nGating: 5 passed, 0 failed\n───── end x ─────\nGating: 40 passed, 2 failed\n' \
  "$W46_HEAD2" > "$S46_REC/floor-inner.txt"
s42_snap "$R46" "$P46"
poke "$R46" proof-add floor record/wave-01-fixture/floor-red.txt
s42_unchanged "46f12 F1 a red run at the head, on a clean tree" 1 "$P46"
expect_contains "46f12b …naming the verdict and the fix" "did not pass (Gating: 40 passed, 3 failed); fix it, run it again" "$OUT"
poke "$R46" proof-add floor record/wave-01-fixture/floor-quote.txt
s42_unchanged "46f13 F1 a note that quotes the run header" 1 "$P46"
expect_contains "46f13b …naming the verdict it lacks" "has no Gating: <n> passed, <m> failed verdict" "$OUT"
poke "$R46" proof-add floor record/wave-01-fixture/floor-void.txt
s42_unchanged "46f14 F1 a run whose tally does not reach the roster, with a Void: line" 1 "$P46"
expect_contains "46f14b …naming the tally against the roster" "40 passed and 1 void of 3 suites" "$OUT"
poke "$R46" proof-add floor record/wave-01-fixture/floor-inner.txt
s42_unchanged "46f15 F1 a green inner verdict above the runner's red one" 1 "$P46"
poke "$R46" proof-add task record/wave-01-fixture/floor-red.txt
s42_unchanged "46f16 F1 a task proof citing a red run" 1 "$P46"
# REVIEW 14 S3, N1, N2 (wave-26 T52). THE LAST RUN IN THE LOG IS JUDGED, and a verdict that sits
# inside a failing suite's captured output is not the runner's: a log cut off after a nested
# green verdict, or a red run for this head with another head's green run appended, proves
# nothing. A floor must be a WHOLE run: passed plus void reaches the suites at the head (three
# here). A void suite passed (T43), so a whole run with one is a floor.
printf 'floor log\nhead=%s dirty=0\n✗ FAIL\n───── x.test.sh: captured output ─────\nGating: 3 passed, 0 failed\n───── end x.test.sh ─────\n' \
  "$W46_HEAD2" > "$S46_REC/floor-cut.txt"
printf 'floor log\nhead=%s dirty=0\nGating: 2 passed, 1 failed\nFailed:\nhead=0123456789abcdef0123456789abcdef01234567 dirty=0\nGating: 3 passed, 0 failed\n' \
  "$W46_HEAD2" > "$S46_REC/floor-appended.txt"
printf 'floor log\nhead=%s dirty=0\nGating: 1 passed, 0 failed\n' "$W46_HEAD2" > "$S46_REC/floor-part.txt"
printf 'floor log\nhead=%s dirty=0\nGating: 2 passed, 0 failed\nVoid: 1 — not timed, each for the reason given; advisory, not a failure:\n    - c.test.sh (the machine was busy)\nNo gating suite failed; 1 void\n' \
  "$W46_HEAD2" > "$S46_REC/floor-whole-void.txt"
printf 'floor log\nhead=%s dirty=0\nGating: 2 passed, 1 failed\nhead=%s dirty=0\nGating: 3 passed, 0 failed\n' \
  "$W46_HEAD2" "$W46_HEAD2" > "$S46_REC/floor-rerun.txt"
s42_snap "$R46" "$P46"
poke "$R46" proof-add floor record/wave-01-fixture/floor-cut.txt
s42_unchanged "46f17 S3 a log cut off after a nested green verdict inside a capture" 1 "$P46"
expect_contains "46f17b …saying the verdict is inside a captured output" "inside a suite's captured output" "$OUT"
poke "$R46" proof-add floor record/wave-01-fixture/floor-appended.txt
s42_unchanged "46f18 S3 a red run for this head with another head's green run appended" 1 "$P46"
expect_contains "46f18b …judged by the last run, which read another head" "read head 0123456789ab" "$OUT"
poke "$R46" proof-add floor record/wave-01-fixture/floor-part.txt
s42_unchanged "46f19 N1 a green verdict over one suite of the three at the head" 1 "$P46"
expect_contains "46f19b …naming the tally against the roster" "1 passed and 0 void of 3 suites" "$OUT"
poke "$R46" proof-add floor record/wave-01-fixture/floor-whole-void.txt
expect_eq "46f20 N2 a whole run with one void suite that passed is a floor" "0" "$RC"
s42_snap "$R46" "$P46"
poke "$R46" proof-add floor record/wave-01-fixture/floor-rerun.txt
expect_eq "46f21 S3 a red run then a green rerun on the same head: the last run is judged, and it passed" "0" "$RC"
# A REVIEW OF AN OLDER HEAD IS A TRUE PROOF OF THAT HEAD: what landed since stays unread.
poke "$R46" proof-add review record/wave-01-fixture/review-older.md
expect_eq "46g a review of an ancestor of the branch head exits 0" "0" "$RC"
expect_eq "46g2 …and proves the head it read, not the branch head" "$W46_HEAD" "$(s46_last "$P46" review)"
# kind=task takes whichever the evidence carries, the run header first (A-T14.9).
s42_snap "$R46" "$P46"
poke "$R46" proof-add task record/wave-01-fixture/floor2.txt
expect_eq "46g3 a task proof citing a run log at the head exits 0" "0" "$RC"
poke "$R46" proof-add task record/wave-01-fixture/review-older.md
expect_eq "46g4 …and one citing a review of an older head exits 0" "0" "$RC"
expect_eq "46g5 …proving the head that review read" "$W46_HEAD" "$(s46_last "$P46" task)"
s42_snap "$R46" "$P46"
poke "$R46" proof-add task record/wave-01-fixture/floor-bare.txt
s42_unchanged "46g6 a task proof whose evidence attests no head" 1 "$P46"
expect_contains "46g7 …naming both forms" "neither a head=<sha> dirty=<n> run header nor a reviewed: <a>..<b> line" "$OUT"

# ---------- the refusals: byte-identical, naming the fix ----------
s42_snap "$R46" "$P46"
poke "$R46" proof-add bogus record/wave-01-fixture/floor.txt
s42_unchanged "46c a kind outside floor|review|task" 1 "$P46"
expect_contains "46c2 …naming the three kinds" "floor, review or task" "$OUT"
poke "$R46" proof-add floor plans/elsewhere/notes.md
s42_unchanged "46c3 an evidence path outside record/" 1 "$P46"
expect_contains "46c4 …naming record/" "under record/" "$OUT"
poke "$R46" proof-add floor record/../plans/elsewhere/notes.md
s42_unchanged "46c5 a path that climbs out of record/" 1 "$P46"
poke "$R46" proof-add floor record/wave-01-fixture/absent.txt
s42_unchanged "46c6 a missing evidence file" 1 "$P46"
expect_contains "46c7 …naming the file" "absent.txt" "$OUT"
# REVIEW 10 F7 (wave-26 T46): A SYMLINK UNDER record/ IS NOT A RECORD. The check resolved the
# directory, not the file, so a link to a log elsewhere was admitted and the evidence could
# change after the proof. The same bytes as a regular file under record/ are admitted.
printf 'floor log\nhead=%s dirty=0\nGating: 3 passed, 0 failed\n' "$W46_HEAD2" > "$R46/.bionic/docs/plans/elsewhere/run.log"
ln -s ../../plans/elsewhere/run.log "$S46_REC/floor-link.txt"
expect_true "46c7b precondition: the link is a symlink to a log outside record/" test -L "$S46_REC/floor-link.txt"
poke "$R46" proof-add floor record/wave-01-fixture/floor-link.txt
s42_unchanged "46c7c F7 evidence that is a symlink" 1 "$P46"
expect_contains "46c7d …naming the fix: copy the log into the record" "copy the log into the record" "$OUT"
cp "$R46/.bionic/docs/plans/elsewhere/run.log" "$S46_REC/floor-copy.txt"
poke "$R46" proof-add floor record/wave-01-fixture/floor-copy.txt
expect_eq "46c7e …and the same log copied into the record is admitted" "0" "$RC"
s42_snap "$R46" "$P46"
printf 'x\n' > "$R46/.bionic/docs/record/wave-01-fixture/two words.txt"
poke "$R46" proof-add floor "record/wave-01-fixture/two words.txt"
s42_unchanged "46c8 an evidence path with a space (the line is space-separated)" 1 "$P46"
poke "$R46" proof-add floor
s42_unchanged "46c9 one operand is the usage error" 2 "$P46"
poke "$R46" proof-add floor record/wave-01-fixture/floor.txt "$W46_HEAD"
s42_unchanged "46c10 …and so is a head given as an operand" 2 "$P46"

# The head is held against the working branch's checkout, so a plan whose branch no checkout
# holds, or that names none, is refused before any evidence head is read.
sed 's#^working-branch: wave/01-fixture$#working-branch: wave/99-gone#' "$P46" > "$P46.tmp" && mv "$P46.tmp" "$P46"
s42_snap "$R46" "$P46"
poke "$R46" proof-add floor record/wave-01-fixture/floor.txt
s42_unchanged "46d a working-branch: no checkout holds" 1 "$P46"
expect_contains "46d2 …naming the branch" "wave/99-gone" "$OUT"
sed '/^working-branch: /d' "$P46" > "$P46.tmp" && mv "$P46.tmp" "$P46"
s42_snap "$R46" "$P46"
poke "$R46" proof-add floor record/wave-01-fixture/floor.txt
s42_unchanged "46d3 a plan naming no working-branch:" 1 "$P46"
expect_contains "46d4 …naming the key to add" "working-branch:" "$OUT"
expect_eq "46e no projection copy is left beside the plan" "" \
  "$(find "$R46/.bionic/docs/plans" -name '*.plan.md.*' 2>/dev/null)"
POKE_BOUND="$S46_BOUND_WAS"

# ============================================================
section "Section 48 §READY-EARLY (review half): a review follows the build — offered once per landed difference, back to pending on its proof (wave-26 T14; REQ-6 AC-6.1, AC-6.5; D10)"
# ============================================================
#
# A reads table at current: 4 with one build landed and one still active. The review row (an
# empty reads cell, so `approval:plan, live:head`) is offered as soon as the first build lands,
# with no review proof yet (AC-6.1). Dispatched, it is active; `proof-add review` records the
# working branch's head A and returns the row to `pending` with its agent, worktree and base
# cells cleared — the next pass is its own launch and its own ledger line. The tick reads the
# head from the checkout holding `working-branch:` (a linked worktree one commit ahead of the
# main checkout, as §46), so at A the review waits, naming the proof's head; one more commit on
# the working branch — a landing — and the tick offers it again (AC-6.5). A tick that read the
# head from the main checkout would see a head other than A and offer it at 48e.
S48_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
s48_row() {  # <plan> <id> -> the row's cells, `|`-joined and trimmed: id|…|status|reads
  awk -F'|' -v id="$2" '{ c = $2; gsub(/^[ \t]+|[ \t]+$/, "", c) } c == id {
    o = ""; for (i = 2; i < NF; i++) { v = $i; gsub(/^[ \t]+|[ \t]+$/, "", v); o = o (i > 2 ? "|" : "") v }
    print o; exit }' "$1"
}
s48_fill_has() {  # <id> -> yes when the tick's FILL line names it
  case " $(s47_lines FILL | sed 's/^poker: FILL //') " in *" $1 "*) printf yes ;; *) printf no ;; esac
}

R48="$(make_repo s48-review)"; new_roster "$R48"; ( cd "$R48" && git commit -q --allow-empty -m init )
add_row "$R48" name=w-T2 deliverable=b.md duration="4 hours" launched_at="$(iso_ago 600)"
P48="$(s42_plan "$R48" 4)"
awk '
  /^current: / && !wb { print; print "working-branch: wave/01-fixture"; wb = 1; next }
  /^- T5: / { print "- T3: review passes, one per landed difference — record/wave-01-fixture/review.md" }
  /^\| id \| step \|/ { intab = 1
    print "| id | step | kind | task | agent | deps | size | serves | Files | worktree | base | status | reads |"
    print "|---|---|---|---|---|---|---|---|---|---|---|---|---|"
    print "| T1 | 4 | build | the first build | implementor | — | 30 | REQ-1 | a.sh | — | — | landed |  |"
    print "| T2 | 4 | build | the second build | w-T2 | — | 30 | REQ-1 | b.sh | 01-T2 | abc1234 | active |  |"
    print "| T3 | 6 | review | follows the build | critic | — | 30 | REQ-1 | .bionic/docs/record/wave-01-fixture/review.md | — | — | pending |  |"
    print "| T5 | 5 | verify | the floor | test-runner | — | 30 | REQ-1 | — | — | — | pending |  |"
    next }
  intab && /^\|/ { next }
  { intab = 0; print }' "$P48" > "$P48.tmp" && mv "$P48.tmp" "$P48"
( cd "$R48" && git add -f "$P48" && git commit -qm "reads table" \
  && git worktree add -q -b wave/01-fixture "$R48/.worktrees/01-fixture" \
  && git -C "$R48/.worktrees/01-fixture" commit -q --allow-empty -m "the first build lands" ) >/dev/null 2>&1
mkdir -p "$R48/.bionic/docs/record/wave-01-fixture"
W48_A="$(git -C "$R48/.worktrees/01-fixture" rev-parse HEAD 2>/dev/null)"
printf '# review\n\nreviewed: %s..%s (the first build)\n' "$(git -C "$R48" rev-parse HEAD)" "$W48_A" \
  > "$R48/.bionic/docs/record/wave-01-fixture/review.md"
expect_eq "48a0 precondition: the T3 row is a review with an empty reads cell, pending" \
  "T3|6|review|follows the build|critic|—|30|REQ-1|.bionic/docs/record/wave-01-fixture/review.md|—|—|pending|" \
  "$(s48_row "$P48" T3)"
expect_true "48a0b precondition: the working branch's head is not the main checkout's" \
  test "$W48_A" != "$(git -C "$R48" rev-parse HEAD)"
s34_gate "$R48"
expect_eq "48a0c precondition: the reads-table plan is admitted by the real commit gate" "0" "$GATE_RC"

# ---------- AC-6.1: no review proof yet, one build landed, one active — offered now ----------
poke_pressure "$R48" 8192 1.0 tick
expect_nonempty "48a the tick prints a FILL line (the extractor reads real output)" "$(s47_lines FILL)"
expect_eq "48a2 AC-6.1 with one build landed and one still active, the review is on the FILL line" "yes" "$(s48_fill_has T3)"

# ---------- dispatched, then its proof: the row goes back to pending ----------
add_row "$R48" name=w-T3 deliverable=review.md duration="1 hour" launched_at="$(iso_ago 60)"
poke "$R48" task-set T3 status=active agent=w-T3 worktree=01-T3 base=abc1234
expect_eq "48b0 precondition: task-set moves T3 active" "0" "$RC"
poke_pressure "$R48" 8192 1.0 tick
expect_eq "48b an active review is not offered again" "no" "$(s48_fill_has T3)"
expect_absent "48b2 …and it is on no WAIT line (it is not pending)" "WAIT T3 " "$(s47_lines WAIT)"
s42_snap "$R48" "$P48"
poke "$R48" proof-add review record/wave-01-fixture/review.md
expect_eq "48c proof-add review exits 0" "0" "$RC"
expect_contains "48c2 …writes the proof at the working branch's head" "proved: kind=review head=${W48_A} " \
  "$(/usr/bin/grep -E '^proved: ' "$P48")"
expect_eq "48c3 …and returns the review row to pending, its agent, worktree and base cleared" \
  "T3|6|review|follows the build|—|—|30|REQ-1|.bionic/docs/record/wave-01-fixture/review.md|—|—|pending|" \
  "$(s48_row "$P48" T3)"
expect_eq "48c4 …touching nothing else: the proof line added, the one row rewritten" "2 1;" "$(s42_numstat "$R48")"
expect_contains "48c5 …and it says which row it returned" "T3 back to pending" "$OUT"
s34_gate "$R48"
expect_eq "48c6 …and the next commit is admitted" "0" "$GATE_RC"

# ---------- AC-6.5: at head A it waits, naming A; one landing later it is offered ----------
poke_pressure "$R48" 8192 1.0 tick
expect_nonempty "48d the tick prints WAIT lines (the extractor reads real output)" "$(s47_lines WAIT)"
expect_eq "48d2 AC-6.5 at the proof's head the review is not offered" "no" "$(s48_fill_has T3)"
expect_eq "48d3 …its WAIT line names the proof head it has not moved past" \
  "poker: WAIT T3 — live:head: nothing landed past the review proof at ${W48_A:0:12}" \
  "$(s47_lines WAIT | /usr/bin/grep '^poker: WAIT T3 ')"
git -C "$R48/.worktrees/01-fixture" commit -q --allow-empty -m "the second build lands" >/dev/null 2>&1
W48_B="$(git -C "$R48/.worktrees/01-fixture" rev-parse HEAD 2>/dev/null)"
expect_true "48e0 precondition: the working branch moved past A" test "$W48_B" != "$W48_A"
poke_pressure "$R48" 8192 1.0 tick
expect_eq "48e AC-6.5 one landing past the proof and the review is offered again" "yes" "$(s48_fill_has T3)"
expect_absent "48e2 …and it is on no WAIT line" "WAIT T3 " "$(s47_lines WAIT)"

# REVIEW 10 F3 (wave-26 T46): ONLY THE ROW WHOSE RECORD IS THE EVIDENCE GOES BACK. A live review
# T3 is mid-pass while the settled final review T8 (reads head) is active beside it; the final
# review's proof returned T3 to pending too, and the next landing re-offered it under a reviewer
# still running. Now the final review's proof moves no row, and T3's own proof still returns it
# (a Files cell spelled record/… matches the same evidence: units LIVE.15e).
R48F="$(make_repo s48-final)"; new_roster "$R48F"; ( cd "$R48F" && git commit -q --allow-empty -m init )
add_row "$R48F" name=w-T3 deliverable=review.md duration="1 hour" launched_at="$(iso_ago 60)"
add_row "$R48F" name=w-T8 deliverable=final.md duration="1 hour" launched_at="$(iso_ago 60)"
P48F="$(s42_plan "$R48F" 4)"
awk '
  /^current: / && !wb { print; print "working-branch: wave/01-fixture"; wb = 1; next }
  /^- T5: / { print "- T3: review passes — record/wave-01-fixture/review.md"; print "- T8: the final review — record/wave-01-fixture/final.md" }
  /^\| id \| step \|/ { intab = 1
    print "| id | step | kind | task | agent | deps | size | serves | Files | worktree | base | status | reads |"
    print "|---|---|---|---|---|---|---|---|---|---|---|---|---|"
    print "| T1 | 4 | build | the first build | implementor | — | 30 | REQ-1 | a.sh | — | — | landed |  |"
    print "| T3 | 6 | review | follows the build | w-T3 | — | 30 | REQ-1 | .bionic/docs/record/wave-01-fixture/review.md | — | — | active |  |"
    print "| T8 | 6 | review | the final review | w-T8 | — | 30 | REQ-1 | .bionic/docs/record/wave-01-fixture/final.md | — | — | active | approval:plan, head |"
    print "| T5 | 5 | verify | the floor | test-runner | — | 30 | REQ-1 | — | — | — | pending |  |"
    next }
  intab && /^\|/ { next }
  { intab = 0; print }' "$P48F" > "$P48F.tmp" && mv "$P48F.tmp" "$P48F"
( cd "$R48F" && git add -f "$P48F" && git commit -qm "reads table" \
  && git worktree add -q -b wave/01-fixture "$R48F/.worktrees/01-fixture" \
  && git -C "$R48F/.worktrees/01-fixture" commit -q --allow-empty -m "the first build lands" ) >/dev/null 2>&1
mkdir -p "$R48F/.bionic/docs/record/wave-01-fixture"
W48F_A="$(git -C "$R48F/.worktrees/01-fixture" rev-parse HEAD 2>/dev/null)"
printf '# final review\n\nreviewed: %s..%s (the wave)\n' "$(git -C "$R48F" rev-parse HEAD)" "$W48F_A" \
  > "$R48F/.bionic/docs/record/wave-01-fixture/final.md"
printf '# review\n\nreviewed: %s..%s (the first build)\n' "$(git -C "$R48F" rev-parse HEAD)" "$W48F_A" \
  > "$R48F/.bionic/docs/record/wave-01-fixture/review.md"
s34_gate "$R48F"
expect_eq "48f0 precondition: the two-review plan is admitted by the real commit gate" "0" "$GATE_RC"
s42_snap "$R48F" "$P48F"
poke "$R48F" proof-add review record/wave-01-fixture/final.md
expect_eq "48f F3 the final review's proof exits 0" "0" "$RC"
expect_contains "48f2 …and writes its proof line" "proved: kind=review head=${W48F_A} " \
  "$(/usr/bin/grep -E '^proved: ' "$P48F")"
expect_eq "48f3 F3 …and leaves the live review mid-pass active, its agent kept" \
  "T3|6|review|follows the build|w-T3|—|30|REQ-1|.bionic/docs/record/wave-01-fixture/review.md|—|—|active|" \
  "$(s48_row "$P48F" T3)"
expect_eq "48f4 …touching nothing but the proof line" "1 0;" "$(s42_numstat "$R48F")"
expect_absent "48f5 …and it names no row returned" "back to pending" "$OUT"
s42_snap "$R48F" "$P48F"
poke "$R48F" proof-add review record/wave-01-fixture/review.md
expect_eq "48g F3 the live review's own proof exits 0" "0" "$RC"
expect_eq "48g2 …and returns T3 to pending, its agent cleared" \
  "T3|6|review|follows the build|—|—|30|REQ-1|.bionic/docs/record/wave-01-fixture/review.md|—|—|pending|" \
  "$(s48_row "$P48F" T3)"
expect_eq "48g3 …and only T3: the final review stays active" "active" \
  "$(s48_row "$P48F" T8 | awk -F'|' '{ print $12 }')"
# REVIEW 14 S4 (wave-26 T51): A REVIEW PROOF THAT RETURNS NO LIVE ROW SAYS SO. The live review's
# record was written under another name than its Files cell (`review-14.md`, Files `review.md`):
# the proof returns no row, rightly (T46), and through T46 the success line said nothing of it, so
# the active pass was never offered again and nobody saw why. The verb now names the active live
# review rows and their Files on such a proof, and still resets none of them. The control: once no
# live review is active, the final review's proof says nothing of the kind.
awk -F'|' 'BEGIN { OFS = "|" } $2 == " T3 " { $6 = " w-T3 "; $13 = " active " } { print }' "$P48F" > "$P48F.tmp" && mv "$P48F.tmp" "$P48F"
expect_eq "48h precondition: the live review T3 is active again, its agent named" \
  "T3|6|review|follows the build|w-T3|—|30|REQ-1|.bionic/docs/record/wave-01-fixture/review.md|—|—|active|" \
  "$(s48_row "$P48F" T3)"
cp "$R48F/.bionic/docs/record/wave-01-fixture/review.md" "$R48F/.bionic/docs/record/wave-01-fixture/review-14.md"
poke "$R48F" proof-add review record/wave-01-fixture/review-14.md
expect_eq "48h S4 a review proof no live row's Files hold exits 0" "0" "$RC"
expect_contains "48h2 S4 …and says it returned no live review row, naming the active one and its Files" \
  "no active live review row holds record/wave-01-fixture/review-14.md in its Files: T3 (.bionic/docs/record/wave-01-fixture/review.md)" "$OUT"
expect_eq "48h3 …and resets nothing: T3 stays active under its agent" \
  "T3|6|review|follows the build|w-T3|—|30|REQ-1|.bionic/docs/record/wave-01-fixture/review.md|—|—|active|" \
  "$(s48_row "$P48F" T3)"
poke "$R48F" proof-add review record/wave-01-fixture/review.md
expect_contains "48h4 control precondition: T3's own proof returns it" "T3 back to pending" "$OUT"
poke "$R48F" proof-add review record/wave-01-fixture/final.md
expect_eq "48h5 control: with no live review active, the final review's proof exits 0" "0" "$RC"
expect_absent "48h6 control …and says nothing of live rows" "no active live review row holds" "$OUT"
POKE_BOUND="$S48_BOUND_WAS"

# ============================================================
section "Section 49 §SYNC: the tick applies the launches the plan lacks, in one write (wave-26 T32, D4; review-3 F1, F2)"
# ============================================================
#
# The launch recorder starts `launch-sync` and does not wait for it. The tick runs the same
# transaction before it reads the plan, so a launch the detached call did not record (killed,
# refused, or never started) is recorded here and says so once, and one that cannot be recorded
# is printed on every tick until it is fixed. The fixture is §34's plan, which the real commit
# gate admits, with T2's agent cell naming a launch on the roster (the gate reads it there).
S49_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
R49="$(make_repo s49-sync)"; ( cd "$R49" && git commit -q --allow-empty -m init )
P49="$(s34_plan "$R49" 4)"
sed -e 's/^| T2 | 4 | build | the second build | implementor |/| T2 | 4 | build | the second build | w-T2 |/' \
    "$P49" > "$P49.tmp" && mv "$P49.tmp" "$P49"
awk '{ print } /^- T5: pending dispatch/ { print "- T6: pending dispatch"; print "- T7: pending dispatch" }
  /^\| T2 \| 4 \| build/ {
  print "| T6 | 4 | build | the sixth build | — | — | 30 | REQ-1 | f.sh | — | — | pending |"
  print "| T7 | 4 | build | the seventh build | — | — | 30 | REQ-1 | g.sh | — | — | pending |" }' "$P49" > "$P49.tmp" && mv "$P49.tmp" "$P49"
new_roster "$R49"
add_row "$R49" name=w-T2 agent_id=a-w-T2 launched_at="$(iso_ago 600)"
add_row "$R49" name=w-T6 agent_id=a-w-T6 launched_at="$(iso_ago 60)" deliverable=t6.md duration="45 minutes" \
  subagent_type=bionic:implementor
# A real linked worktree, its path as git lists it: the record counts nothing else (wave-26 T40).
T49_TREE="$(cd "$R49" && pwd -P)/.worktrees/01-T6"; git -C "$R49" worktree add -q -b wt/01-T6 "$T49_TREE" >/dev/null 2>&1
printf 'workspace/v1|session=%s|name=w-T6|path=%s|branch=wt/01-T6|base=0123456789abcdef0123456789abcdef01234567|plan=%s|at=2026-10-04T03:36:00Z\n' \
  "$SID" "$T49_TREE" "$P49" >> "$R49/.bionic/tmp/workspaces-$SID.state"
expect_contains "49 precondition: T6 is in the table, pending" "| f.sh | — | — | pending |" "$(grep '^| T6 |' "$P49")"
s34_gate "$R49"
expect_eq "49 precondition: the fixture is admitted by the real commit gate" "0" "$GATE_RC"

poke_pressure "$R49" 8192 1.0 tick
expect_contains "49a §SYNC the tick records the launch the plan lacked, and says so" "poker: LAUNCHED T6 w-T6" "$OUT"
expect_contains "49a2 …row T6 is active in its tree" "| w-T6 | — | 30 | REQ-1 | f.sh | .worktrees/01-T6 | 01234567 | active |" \
  "$(grep '^| T6 |' "$P49")"
expect_absent "49a3 …and the ready set it fills from no longer offers T6" "FILL T6" "$OUT"
poke_pressure "$R49" 8192 1.0 tick
expect_absent "49b …the next tick has nothing to record and says nothing of it" "poker: LAUNCHED" "$OUT"
expect_contains "49b2 …while it still decides" "decision=" "$OUT"

# 49c: a launch that cannot be recorded (a build row, no tree) is printed by the tick.
add_row "$R49" name=w-T7 agent_id=a-w-T7 launched_at="$(iso_ago 30)" deliverable=t7.md duration="45 minutes"
cp "$P49" "$TMPROOT/s49-before"
poke_pressure "$R49" 8192 1.0 tick
expect_contains "49c §SYNC the tick prints the launch it could not record" "poker: NOT-RECORDED T7 w-T7" "$OUT"
expect_contains "49c2 …with the command to run by hand" "task-set T7 status=active agent=w-T7" "$OUT"
expect_true "49c3 …and the plan is unchanged" cmp -s "$TMPROOT/s49-before" "$P49"
expect_eq "49d no projection copy is left beside the plan" "" \
  "$(find "$R49/.bionic/docs/plans" -name '*.plan.md.*' 2>/dev/null)"

# 49f (wave-26 T51; review 13 F1): the lock cannot be made — .bionic/tmp is not writable. The tick's
# call leaves a held lock to its holder and does not wait, yet through T32 its takeover arm looped
# without a bound and the tick never returned. Run in a process group of its own, bounded, and
# killed whole past the bound; what it left running is read by working directory.
s49_procs() {  # <dir> -> the pids of bash processes whose working directory is <dir> or below it
  local d
  d="$(cd "$1" 2>/dev/null && pwd -P)" || return 0
  lsof -a -c bash -d cwd -Fpn 2>/dev/null | awk -v d="$d" '
    /^p/ { p = substr($0, 2); next }
    /^n/ { n = substr($0, 2); if (n == d || index(n, d "/") == 1) print p }'
}
s49_tick_bounded() {  # <seconds> <repo> -> OUT, RC; 124, the tick's whole group killed, past the bound
  local i=0 n=$(( $1 * 10 )) p
  rm -f "$TMPROOT/s49f.rc"
  p="$( set -m
    ( cd "$2" && env CLAUDE_CODE_SESSION_ID="$SID" BIONIC_PROBE_FREE_MB=8192 BIONIC_PROBE_LOAD_1M=1.0 \
        bash "$POKER" tick > "$TMPROOT/s49f.out" 2>&1
      echo "$?" > "$TMPROOT/s49f.rc" ) </dev/null >/dev/null 2>&1 &
    echo "$!" )"
  while [ ! -s "$TMPROOT/s49f.rc" ] && [ "$i" -lt "$n" ]; do sleep 0.1; i=$((i + 1)); done
  if [ -s "$TMPROOT/s49f.rc" ]; then RC="$(cat "$TMPROOT/s49f.rc")"; else kill -9 -- "-$p" 2>/dev/null; RC=124; fi
  OUT="$(cat "$TMPROOT/s49f.out" 2>/dev/null)"
}
require_helpers s49_procs s49_tick_bounded
command -v lsof >/dev/null 2>&1 || { echo "session-poker: lsof absent — 49f cannot read what it left running"; exit 1; }
( cd "$R49" && while :; do sleep 1; done ) & S49_PLANT=$!
sleep 0.5
expect_contains "49f precondition: a process the row starts in the repo is found by its working directory" \
  " $S49_PLANT " " $(s49_procs "$R49" | tr '\n' ' ')"
kill "$S49_PLANT" 2>/dev/null; wait "$S49_PLANT" 2>/dev/null
poke_bind "$R49"
chmod a-w "$R49/.bionic/tmp"
s49_tick_bounded 20 "$R49"
chmod u+w "$R49/.bionic/tmp"
expect_ne "49f §F1 the tick returns when the launch lock cannot be made (rc $RC; 124 is the bound)" "124" "$RC"
expect_contains "49f2 …and prints that the lock cannot be made" "cannot be made" "$OUT"
expect_eq "49f3 …and leaves nothing running" "" "$(s49_procs "$R49")"

# 49e (wave-26 T32; T14, AC-6.5): the offered review names the range it reads. §48's world as it
# ends: a review proof at A, one landing to B, the review offered again. The digest is removed so
# the tick prints in full; the head is the one the tick reads for live:head, with no git of its own.
expect_nonempty "49e precondition: §48 left its world and both heads" "${R48:-}${W48_A:-}${W48_B:-}"
rm -f "$R48/.bionic/tmp/tick-digest-$SID.state"
poke_pressure "$R48" 8192 1.0 tick
expect_eq "49e precondition: the tick offers the review" "yes" "$(s48_fill_has T3)"
expect_contains "49e AC-6.5 …and names the range it reads, the proof's head to the head now" \
  "poker: RANGE T3 ${W48_A}..${W48_B}" "$OUT"
expect_absent "49e2 …and only for the review: the active build has no RANGE line" "poker: RANGE T2" "$OUT"
# 49e3 (wave-26 T62; critic 3 S3): THE DIGEST THIS REAL TICK WROTE CARRIES THAT HEAD. The turn-end
# wall reads `head=` from it and hands it to the same ready set (stop.sh); stop.test.sh §LH plants
# the field by hand, so this is the one row that reads what the tick itself wrote.
expect_eq "49e3 …and the digest the tick wrote carries the head it judged live:head against" "head=${W48_B}" \
  "$(/usr/bin/grep -E '^head=' "$(digest_of "$R48")" 2>/dev/null)"
POKE_BOUND="$S49_BOUND_WAS"


# ============================================================
section "Section 50 §FIRST-TICK: the armed first tick names the ready set — FILL, WAIT and CHAIN from the scheduler's one site (wave-26 T59; REQ-6 AC-6.6)"
# ============================================================
#
# THE FIRST TICK OF EVERY RUN FINDS NO ROSTER: arming precedes dispatch (§13a). Through T58 that
# arm printed the rung, the holds and the ledger, then `QUIET — armed, nothing dispatched yet`,
# and exited above the scheduler, so FILL, WAIT and CHAIN never printed on the one tick where
# every ready row is unstarted. Both arms now run the scheduler from one site, and the decision
# line agrees with what the tick printed: FILL with its `fill=` field when it names rows, QUIET
# (exit 0, stamp kept) when nothing is ready or approval is pending. The approval gate
# holds as everywhere: the gate is the plan's `approved-by:` line (wave-26 T13), so the plan at
# current: 3 below carries none, as a plan before Step-3 approval does.
s50_plan() {  # <repo> <current> <approved-by line, or empty> -> the plan path
  local f="$1/.bionic/docs/plans/epic-99-fixture/wave-01-fixture.plan.md"
  mkdir -p "$(dirname "$f")"
  {
    printf -- '---\ngoverning-skill: superpowers:writing-plans\n'
    printf 'parallel-budget: writers=8 suites=2 worktrees=8 test_jobs=8 source=probe\n'
    printf -- '---\n\n# fixture plan\n\n## SDLC State\n\ncurrent: %s\n%s\n\n- Step %s: in progress\n\n' "$2" "$3" "$2"
    printf '## Tasks\n\n%s' "$SP_TASKS_HEADER"
    printf '| T1 | 4 | build | ready, the long one | implementor | — | 20m | REQ-x | a.sh | pending |\n'
    printf '| T2 | 4 | build | ready | implementor | — | 10m | REQ-x | b.sh | pending |\n'
    printf '| T3 | 4 | build | ready | implementor | — | 5m | REQ-x | c.sh | pending |\n'
    printf '| T4 | 4 | build | waits on T1 | implementor | T1 | 15m | REQ-x | d.sh | pending |\n'
  } > "$f"
  printf '%s' "$f"
}
s50_last() { printf '%s\n' "$OUT" | tail -1; }

R50="$(make_repo s50-first-tick)"
poke "$R50" arm
s50_plan "$R50" 4 "$SP_APPROVED_LINE" >/dev/null
poke_pressure "$R50" 8192 1.0 tick
expect_eq "50a the armed first tick exits 0" "0" "$RC"
expect_eq "50a3 precondition: …with no roster file on disk, the no-roster arm" "no" "$([ -e "$(roster_of "$R50")" ] && echo yes || echo no)"
expect_contains "50b the first tick fills the three ready rows" "poker: FILL T1 T2 T3" "$OUT"
expect_contains "50c …names the waiting row with the read it lacks and its writer" \
  "poker: WAIT T4 — waits for T1 (pending)" "$OUT"
expect_contains "50d …and the longest chain, by hand: 20 + 15" "poker: CHAIN T1→T4 (35 min)" "$OUT"
expect_contains "50a2 …and its sentence is the FILL band's own" \
  "poker: FILL — T1 T2 T3 named for dispatch; the decision line carries them." "$OUT"
S50_FILL="$(s38_line_no 'poker: FILL T')"; S50_WAIT="$(s38_line_no 'poker: WAIT ')"
S50_CHAIN="$(s38_line_no 'poker: CHAIN ')"; S50_SAID="$(s38_line_no 'poker: FILL — ')"
expect_true "50e …each above the band's sentence (fill=$S50_FILL wait=$S50_WAIT chain=$S50_CHAIN said=$S50_SAID)" \
  test "$S50_FILL" -gt 0 -a "$S50_WAIT" -gt "$S50_FILL" -a "$S50_CHAIN" -gt "$S50_WAIT" -a "$S50_SAID" -gt "$S50_CHAIN"
expect_regex "50f the decision line agrees with what the tick printed: last, FILL, and the fill field" \
  '^poker-tick/v1\|at=[^|]+\|session=[^|]+\|decision=FILL\|total=0\|open=0\|fill=T1 T2 T3$' "$(s50_last)"
expect_absent "50f2 …and the QUIET sentence is not printed beside it" "poker: QUIET" "$OUT"
expect_eq "50g the rung prints once, from the one site" "1" "$(count_lines_matching 'poker: rung=' "$OUT")"
expect_eq "50h the stamp is kept" "yes" "$([ -f "$(stamp_of "$R50")" ] && echo yes || echo no)"
expect_eq "50i the tick digest the stop collector reads carries the FILL band, and the duty it owes" \
  "decision=FILL duty=owed" \
  "$(/usr/bin/grep -E '^(decision|duty)=' "$R50/.bionic/tmp/tick-digest-$SID.state" 2>/dev/null | tr '\n' ' ' | sed 's/ $//')"

# 50k — A FIRST TICK WITH NOTHING READY IS STILL QUIET: the one row waits on the world.
R50K="$(make_repo s50-first-tick-nothing-ready)"
poke "$R50K" arm
sp_plan_at_step "$R50K" 4 \
  "| T1 | 4 | build | waits on CI | implementor | ext:ci-50k | 15m | REQ-x | a.sh | pending |" >/dev/null
poke_pressure "$R50K" 8192 1.0 tick
expect_eq "50k the first tick with nothing ready exits 0" "0" "$RC"
expect_contains "50k2 precondition: …and read the plan: the held row is named" "poker: HELD T1 ext:ci-50k" "$OUT"
expect_absent "50k3 …names no row to fill" "poker: FILL" "$OUT"
expect_contains "50k4 …and decides QUIET in the no-roster arm" \
  "poker: QUIET — armed, nothing dispatched yet on this session" "$OUT"
expect_regex "50k5 …with the QUIET decision line, no fill field" \
  '^poker-tick/v1\|at=[^|]+\|session=[^|]+\|decision=QUIET\|total=0\|open=0$' "$(s50_last)"
expect_contains "50k6 …and a digest that says QUIET" "decision=QUIET" \
  "$(cat "$R50K/.bionic/tmp/tick-digest-$SID.state" 2>/dev/null)"

# 50j — THE SAME TABLE BEFORE STEP-3 APPROVAL: no FILL, no WAIT, no CHAIN, the approval line,
# and the same QUIET decision and exit code.
R50B="$(make_repo s50-first-tick-step3)"
poke "$R50B" arm
s50_plan "$R50B" 3 "" >/dev/null
poke_pressure "$R50B" 8192 1.0 tick
expect_eq "50j the first tick before approval exits 0" "0" "$RC"
expect_contains "50j2 …and prints the approval line" \
  "poker: no FILL — plan at current: 3, Step-3 approval pending" "$OUT"
expect_absent "50j3 …and names no row to fill" "poker: FILL" "$OUT"
expect_absent "50j4 …no WAIT line" "poker: WAIT" "$OUT"
expect_absent "50j5 …and no CHAIN line" "poker: CHAIN" "$OUT"
expect_contains "50j6 …deciding QUIET in the no-roster arm" \
  "poker: QUIET — armed, nothing dispatched yet on this session" "$OUT"
expect_regex "50j7 …with the decision line unchanged" \
  '^poker-tick/v1\|at=[^|]+\|session=[^|]+\|decision=QUIET\|total=0\|open=0$' "$(s50_last)"

# ============================================================
section "Section 51 §ADD-READS: a task added mid-run says what it reads, and the graph is the one a fresh derivation gives (wave-26 T59; REQ-5 AC-5.4)"
# ============================================================
#
# `task-add` takes an optional tenth operand, `<reads>`, passed to `units_add_row` as the row's
# reads cell (wave-26 T2, A-T2.14). In a table with a reads column a row waits for what it
# reads and its deps carry only `ext:<slug>`, so the add needs no hand-written dependency: its
# edges come from the table. A `—` reads is the cell `—`, which the readiness program reads as
# the kind's default. A reads operand on a table with no reads column has nowhere to go and is
# refused, unless it is `—`, which writes what the nine-operand form writes.
#
# THE FIXTURE IS §34's, WITH A reads COLUMN: s34_plan's admitted plan, its table widened by one
# column and T5's deps (task ids, which a reads table refuses) emptied.
S51_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
S51_UNITS="${BIONIC_HOOKS_DIR}/../payload/scripts/lib/units.sh"
s51_plan() {  # <repo> -> the plan path; s34_plan's, with a reads column
  local p; p="$(s34_plan "$1" 4)"
  awk '/^## Tasks/ { t = 1 } /^## Verification/ { t = 0 }
       t && /^\| id / { print $0 " reads |"; next }
       t && /^\|---/ { print $0 "---|"; next }
       t && /^\| T/ { sub(/\| T1, T2 \|/, "| — |"); print $0 " — |"; next }
       { print }' "$p" > "$p.tmp" && mv "$p.tmp" "$p"
  printf '%s' "$p"
}
s51_edges() { bash -c '. "$1" && units_edges "$2"' _ "$S51_UNITS" "$1" 2>/dev/null | LC_ALL=C sort; }  # <plan>
s51_rows() { /usr/bin/grep '^| T[0-9]' "$1"; }  # <plan> -> its task rows

R51="$(make_repo s51-add-reads)"; ( cd "$R51" && git commit -q --allow-empty -m init )
P51="$(s51_plan "$R51")"
s34_gate "$R51"
expect_eq "51a precondition: the reads-table fixture is admitted by the real commit gate" "0" "$GATE_RC"
S51_ROWS_BEFORE="$(s51_rows "$P51")"
poke "$R51" task-add T6 4 build 'reads what T2 writes' bionic:implementor '—' 30 REQ-5 'lib/c.sh' 'b.sh'
expect_eq "51b task-add with a reads operand and no deps exits 0" "0" "$RC"
expect_contains "51b2 …the reads operand is the row's reads cell" \
  "| T6 | 4 | build | reads what T2 writes | bionic:implementor | — | 30 | REQ-5 | lib/c.sh | — | — | pending | b.sh |" "$(cat "$P51")"
S51_EDGES="$(s51_edges "$P51")"
expect_contains "51c AC-5.4 the added row's edge comes from what it reads: T2 writes b.sh" \
  "$(printf 'T2\tT6\tb.sh')" "$S51_EDGES"
# THE FRESH DERIVATION: the same table written by hand in a second repo, its edges derived.
R51F="$(make_repo s51-add-reads-fresh)"; ( cd "$R51F" && git commit -q --allow-empty -m init )
P51F="$(s51_plan "$R51F")"
awk '{ print }
     /^\| T5 \| 5 \|/ { print "| T6 | 4 | build | reads what T2 writes | bionic:implementor | — | 30 | REQ-5 | lib/c.sh | — | — | pending | b.sh |" }
     /^- T5: / { print "- T6: pending dispatch — by hand" }' "$P51F" > "$P51F.tmp" && mv "$P51F.tmp" "$P51F"
expect_nonempty "51d precondition: the hand-written table derives edges" "$(s51_edges "$P51F")"
expect_eq "51d2 AC-5.4 the graph after the add equals a fresh derivation of the same table" \
  "$(s51_edges "$P51F")" "$S51_EDGES"
expect_eq "51e no other row is touched: T6 is appended to no later row's deps (every other row byte-identical)" \
  "$S51_ROWS_BEFORE" "$(s51_rows "$P51" | /usr/bin/grep -v '^| T6 ')"
s34_gate "$R51"
expect_eq "51f the next commit is admitted" "0" "$GATE_RC"

# 51g — REFUSALS LEAVE THE PLAN BYTE-IDENTICAL (cmp, §42's helpers).
s42_snap "$R51" "$P51"
poke "$R51" task-add T6 4 build 'the same id again' implementor '—' 30 REQ-5 'lib/d.sh' 'a.sh'
s42_unchanged "51g a duplicate id with a reads operand" 1 "$P51"
expect_contains "51g2 …naming the duplicate" "T6: duplicate id" "$OUT"
poke "$R51" task-add T7 4 build 'a read naming nothing' implementor '—' 30 REQ-5 'lib/d.sh' 'nonsense'
s42_unchanged "51g3 a reads token naming no artifact" 1 "$P51"
expect_contains "51g4 …in the validator's words" "read nonsense names no artifact" "$OUT"
poke "$R51" task-add T7 4 build 'a bare word for Files' implementor '—' 30 REQ-5 'CHANGELOG' 'a.sh'
s42_unchanged "51g5 a Files operand the dispatch grammar refuses" 1 "$P51"
poke "$R51" task-add T7 4 build 'eleven' implementor '—' 30 REQ-5 'lib/d.sh' 'a.sh' extra
s42_unchanged "51g6 eleven operands are the usage error" 2 "$P51"
expect_contains "51g7 …and the usage names the optional reads operand" "[<reads>]" "$OUT"

# 51h — TEN OPERANDS ON A TABLE WITHOUT THE COLUMN: a read has nowhere to go, so it is refused
# in one line, the plan byte-identical; `—` is the nine-operand form, byte for byte.
R51N="$(make_repo s51-no-reads)"; ( cd "$R51N" && git commit -q --allow-empty -m init )
P51N="$(s42_plan "$R51N" 4)"
s42_snap "$R51N" "$P51N"
poke "$R51N" task-add T6 4 build 'reads into no column' implementor '—' 30 REQ-5 'lib/c.sh' 'b.sh'
s42_unchanged "51h a reads operand on a table with no reads column" 1 "$P51N"
expect_contains "51h2 …saying why, in one line" "has no reads column" "$OUT"
poke "$R51N" task-add T6 4 build 'the dash reads' implementor '—' 30 REQ-5 'lib/c.sh' '—'
expect_eq "51h3 a — reads on that table is admitted" "0" "$RC"
R51M="$(make_repo s51-nine)"; ( cd "$R51M" && git commit -q --allow-empty -m init )
P51M="$(s42_plan "$R51M" 4)"
poke "$R51M" task-add T6 4 build 'the dash reads' implementor '—' 30 REQ-5 'lib/c.sh'
expect_eq "51h4 precondition: the nine-operand add of the same row exits 0" "0" "$RC"
expect_eq "51h5 …and the — reads wrote what the nine-operand form writes, byte for byte (the add's instant aside)" \
  "$(sed -E 's/ added by task-add at [0-9TZ:-]+$//' "$P51M")" "$(sed -E 's/ added by task-add at [0-9TZ:-]+$//' "$P51N")"
POKE_BOUND="$S51_BOUND_WAS"

# ============================================================
section "Section 52 §RUN-END: integrate waits for an open build, and the WAIT line names it (wave-26 T62; critic 2 K2-F5)"
# ============================================================
#
# A reads table at current: 8, the floor and the review both proved, the review row landed, and
# a late fix from the review still active. Integrate reads its default, now `proof:floor,
# proof:review, head`, so the open build holds the merge and the tick says so. Through T61 the
# tick offered the merge beside the build (FILL T3) and the turn-end wall demanded it.
# THE PROOFS NAME THE HEAD THE WORKING BRANCH IS AT (wave-26 T64): from T64 a floor proof stands
# only while proof_state answers covered or bounded, so the repository gets one commit, the plan
# names its branch as `working-branch:`, and both proofs name that commit, not a made-up hex.
s52_plan() {  # <repo> <T6 status> -> the plan path
  local f h b
  ( cd "$1" && git commit -q --allow-empty -m init ) >/dev/null 2>&1
  h="$(git -C "$1" rev-parse HEAD 2>/dev/null)"; b="$(git -C "$1" symbolic-ref --short HEAD 2>/dev/null)"
  f="$(s47_plan "$1" 2 \
    "| T1 | 4 | build | landed | implementor | — | 30 | REQ-x | payload/x.sh | landed | |" \
    "| T5 | 5 | verify | the floor | test-runner | — | 30 | REQ-x | .bionic/docs/record/floor.log | landed | |" \
    "| T2 | 6 | review | the final review | critic | — | 30 | REQ-x | .bionic/docs/record/review.md | landed | |" \
    "| T6 | 6 | build | late fix from the review | implementor | — | 20 | REQ-x | payload/x.sh | $2 | |" \
    "| T3 | 8 | integrate | merge to main | — | — | 10 | REQ-x | — | pending | |")"
  awk -v h="$h" -v b="$b" '
    /^current: / { print "current: 8"; print "working-branch: " b; next }
    { print }
    /^approved-by: / { print "proved: kind=floor head=" h " at=2026-10-04T11:00:00Z evidence=record/floor.log"
                       print "proved: kind=review head=" h " at=2026-10-04T11:05:00Z evidence=record/review.md" }' \
    "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  printf '%s' "$f"
}
R52="$(make_repo s52-open-build)"; new_roster "$R52"; s52_plan "$R52" active >/dev/null
add_row "$R52" name=w-T6 deliverable=T6.md duration="1 hour" launched_at="$(iso_ago 10)"
poke_pressure "$R52" 8192 1.0 tick
expect_nonempty "52a precondition: the tick prints WAIT lines (the extractor reads real output)" "$(s47_lines WAIT)"
expect_contains "52a2 K2-F5 integrate waits on head, and its WAIT line names the late build" \
  "poker: WAIT T3 — reads head, written by T6 (active)" "$OUT"
R52L="$(make_repo s52-landed)"; new_roster "$R52L"; s52_plan "$R52L" landed >/dev/null
poke_pressure "$R52L" 8192 1.0 tick
expect_contains "52b the build landed, both proofs in: the merge is offered" "poker: FILL T3" "$OUT"

# ============================================================
section "Section 53 §REVIEW-RANGE: a review proof starts where the last one ended (wave-26 T62; critic 2 K2-F2)"
# ============================================================
#
# `reviewed: <a>..<b>`: through T61 only <b> was attested, so `<head~1>..<head>` and
# `zzzz..<head>` were recorded as a review of everything up to the head. <a> must now be a
# commit on <b>'s history, at or before the last review proof's head, or, before the first
# review proof, at or before the plan's base: the Step-4 block's `base-sha:`, a real commit here.
# The working branch is cut from that base and carries four commits, C1 to C4.
S53_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
R53="$(make_repo s53-range)"; ( cd "$R53" && git commit -q --allow-empty -m init )
S53_B="$(git -C "$R53" rev-parse HEAD)"
P53="$(s42_plan "$R53" 4 "  worktree: .worktrees/01-fixture
  base-sha: ${S53_B:0:8}
  branch: wave/01-fixture")"
awk '{ print } /^current: / && !d { print "working-branch: wave/01-fixture"; d = 1 }' "$P53" > "$P53.tmp" && mv "$P53.tmp" "$P53"
( cd "$R53" && git add -f "$P53" && git commit -qm wb \
  && git worktree add -q -b wave/01-fixture "$R53/.worktrees/01-fixture" "$S53_B" ) >/dev/null 2>&1
for s53c in 1 2 3 4; do git -C "$R53/.worktrees/01-fixture" commit -q --allow-empty -m "C$s53c" >/dev/null 2>&1; done
S53_C1="$(git -C "$R53/.worktrees/01-fixture" rev-parse HEAD~3)"; S53_C2="$(git -C "$R53/.worktrees/01-fixture" rev-parse HEAD~2)"
S53_C3="$(git -C "$R53/.worktrees/01-fixture" rev-parse HEAD~1)"; S53_C4="$(git -C "$R53/.worktrees/01-fixture" rev-parse HEAD)"
S53_REC="$R53/.bionic/docs/record/wave-01-fixture"; mkdir -p "$S53_REC"
s53_review() { printf '# review\n\nreviewed: %s..%s\n' "$1" "$2" > "$S53_REC/$3"; }  # <a> <b> <file>
expect_regex "53a0 precondition: the working branch's head is C4, a 40-hex commit" '^[0-9a-f]{40}$' "$S53_C4"
expect_eq "53a0b precondition: the plan's base is the branch point" "$S53_B" \
  "$(git -C "$R53" merge-base "$S53_B" "$S53_C1")"
s53_review "$S53_C1" "$S53_C2" first-late.md
s53_review zzzz "$S53_C2" junk.md
s53_review "$S53_C3" "$S53_C2" backwards.md
s53_review "${S53_B:0:10}" "$S53_C2" first.md
s42_snap "$R53" "$P53"
poke "$R53" proof-add review record/wave-01-fixture/first-late.md
s42_unchanged "53a the first review starting past the plan's base" 1 "$P53"
expect_contains "53a2 …naming the base and the range to read" \
  "starts at ${S53_C1:0:12}, past the plan's base ${S53_B:0:12}, so what landed between them is unread; review ${S53_B:0:12}..${S53_C2:0:12}" "$OUT"
poke "$R53" proof-add review record/wave-01-fixture/junk.md
s42_unchanged "53b a range whose start is no commit (the critic's zzzz)" 1 "$P53"
expect_contains "53b2 …saying so" "starts at zzzz, which is no commit here" "$OUT"
poke "$R53" proof-add review record/wave-01-fixture/backwards.md
s42_unchanged "53c a range whose start is not on its end's history" 1 "$P53"
expect_contains "53c2 …saying so" "which is not on the history of its end ${S53_C2:0:12}" "$OUT"
poke "$R53" proof-add review record/wave-01-fixture/first.md
expect_eq "53d the first review from the base is recorded (exit 0)" "0" "$RC"
expect_eq "53d2 …at the end it read" "$S53_C2" "$(s46_last "$P53" review)"
# THE NEXT REVIEW STARTS AT OR BEFORE C2. One that read only the last commit, C3..C4, leaves C3
# unread and is refused; C2..C4 and an overlap from C1 are both recorded.
s53_review "$S53_C3" "$S53_C4" narrow.md
s53_review "$S53_C2" "$S53_C4" second.md
s42_snap "$R53" "$P53"
poke "$R53" proof-add review record/wave-01-fixture/narrow.md
s42_unchanged "53e K2-F2 a review of <head~1>..<head> past the last review proof" 1 "$P53"
expect_contains "53e2 …naming the proof and the range to read" \
  "starts at ${S53_C3:0:12}, past the last review proof ${S53_C2:0:12}, so what landed between them is unread; review ${S53_C2:0:12}..${S53_C4:0:12}" "$OUT"
poke "$R53" proof-add review record/wave-01-fixture/second.md
expect_eq "53f the review from the last proof is recorded (exit 0)" "0" "$RC"
expect_eq "53f2 …at its end" "$S53_C4" "$(s46_last "$P53" review)"
s53_review "$S53_C1" "$S53_C4" overlap.md
poke "$R53" proof-add review record/wave-01-fixture/overlap.md
expect_eq "53g a review that starts before the last proof (an overlap) is recorded" "0" "$RC"
POKE_BOUND="$S53_BOUND_WAS"

# ============================================================
section "Section 54 §FULL-RUN-REQUIRED: integrate waits for a full run when the change past the floor proof cannot be bounded (wave-26 T64; REQ-3 AC-3.3, AC-3.4)"
# ============================================================
#
# AC-3.4: "A second full run is required when the change cannot be bounded … Fails when a planted
# new file under a directory no suite names lands with no suite run at all." Through T63 the run
# only ADMITTED that full run: a task tree with no suite stamp lands (by design: a file no suite
# names has no affected suite), and integrate's `proof:floor` read took any floor proof line,
# whatever its head, so the tick offered the merge on a change no suite had read.
#
# EVERYTHING HERE IS THE PRODUCT'S OWN: the working branch `wave/01-fixture` in a linked checkout
# (as §46); its full runs are the shipped suite runner, copied byte for byte into the fixture with
# three green suites (runner-roster's recipe), so every log is a real runner's log; each proof
# line is written by `proof-add`; each task tree lands through the real `worktree_land`; the WAIT
# and FILL lines are the tick's. The map (`impact-command:`) answers lib/one.sh with two suites,
# lib/every.sh with all three, anything else with nothing. Integrate reads its kind default.
S54_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
R54="$(make_repo s54-full-run)"; new_roster "$R54"
S54_WT="$R54/.worktrees/01-fixture"
S54_REC="$R54/.bionic/docs/record/wave-01-fixture"
S54_MAP="$TMPROOT/s54-map.sh"
S54_COUNT="$TMPROOT/s54-map.count"
S54_WTLIB="${BIONIC_HOOKS_DIR}/../payload/scripts/lib/worktree.sh"
{
  printf '#!/bin/bash\n'
  printf 'printf "x\\n" >> "%s"\n' "$S54_COUNT"
  printf 'for f in "$@"; do\n'
  printf '  case "$f" in\n'
  printf '    lib/one.sh)   for s in a b; do printf "%%s.test.sh\\tdir-ref:%%s\\n" "$s" "$f"; done ;;\n'
  printf '    lib/every.sh) for s in a b c; do printf "%%s.test.sh\\tdir-ref:%%s\\n" "$s" "$f"; done ;;\n'
  printf '  esac\n'
  printf 'done\n'
} > "$S54_MAP"
mkdir -p "$R54/tests/lib" "$R54/payload/scripts/lib" "$R54/lib" "$S54_REC"
cp "$BIONIC_SCRIPTS_DIR/tests/run.sh" "$R54/tests/run.sh"
cp "$BIONIC_SCRIPTS_DIR/tests/lib/resolve-roots.sh" "$BIONIC_SCRIPTS_DIR/tests/lib/assert.sh" "$R54/tests/lib/"
cp "$BIONIC_SCRIPTS_DIR"/payload/scripts/lib/*.sh "$R54/payload/scripts/lib/"
for s54s in a b c; do
  printf '#!/bin/bash\nset -uo pipefail\n. "$(dirname "$0")/lib/assert.sh"\nsection "%s"\nexpect_eq "%s ran" x x\nfinish\n' \
    "$s54s" "$s54s" > "$R54/tests/$s54s.test.sh"
done
printf 'one\n' > "$R54/lib/one.sh"; printf 'every\n' > "$R54/lib/every.sh"
printf '.bionic/\n.worktrees/\n' > "$R54/.gitignore"
( cd "$R54" && git add .gitignore tests payload lib && git commit -qm base ) >/dev/null 2>&1
S54_BASE="$(git -C "$R54" rev-parse HEAD 2>/dev/null)"
P54="$(s42_plan "$R54" 4)"
awk '
  /^current: / && !wb { print; print "working-branch: wave/01-fixture"; wb = 1; next }
  /^- T5: / { print; print "- T3: integrate at Step 8"; next }
  /^\| id \| step \|/ { intab = 1
    print "| id | step | kind | task | agent | deps | size | serves | Files | worktree | base | status | reads |"
    print "|---|---|---|---|---|---|---|---|---|---|---|---|---|"
    print "| T1 | 4 | build | the build | implementor | — | 30 | REQ-1 | lib/one.sh | — | — | landed |  |"
    print "| T5 | 5 | verify | the floor | test-runner | — | 30 | REQ-1 | .bionic/docs/record/wave-01-fixture/floor.log | — | — | landed |  |"
    print "| T2 | 6 | review | the final review | critic | — | 30 | REQ-1 | .bionic/docs/record/wave-01-fixture/final-review.md | — | — | landed |  |"
    print "| T3 | 8 | integrate | merge to main | — | — | 10 | REQ-1 | — | — | — | pending |  |"
    next }
  intab && /^\|/ { next }
  { intab = 0; print }' "$P54" > "$P54.tmp" && mv "$P54.tmp" "$P54"
( cd "$R54" && git add -f "$P54" && git commit -qm "reads table" \
  && git worktree add -q -b wave/01-fixture "$S54_WT" ) >/dev/null 2>&1
printf 'impact-command: bash %s\n' "$S54_MAP" > "$R54/.bionic/config.yaml"
# s54_full <log> -> the copied runner, run whole in the working checkout, its log in the record
s54_full() {
  ( cd "$S54_WT" && env -u BIONIC_SLOT_HELD -u BIONIC_SLOT_PLACE -u BIONIC_SLOT_QUIET -u BIONIC_QUIET \
      -u BIONIC_LOAD_NOW_FILE BIONIC_SLOTS_DIR="$TMPROOT/s54-slots" BIONIC_SLOTS_N=2 BIONIC_SLOTS_POLL=0.1 \
      BIONIC_SLOTS_MAX_WAIT=20 BIONIC_SLOTS_NOTE_S=5 BIONIC_PRESSURE_RING="$TMPROOT/s54-ring" \
      BIONIC_TEST_JOBS_CEILING=2 BIONIC_PROBE_FREE_PCT=44 BIONIC_PROBE_SWAP_PCT=0 BIONIC_PROBE_LOAD_1M=0.1 \
      bash tests/run.sh ) > "$S54_REC/$1" 2>&1
}
# s54_land <id> <path> <content> -> a task tree on wt/01-<id> commits one file and NO suite runs
# in it (no stamp); the real land merges it. Leaves S54_LAND.
s54_land() {
  local t="$R54/.worktrees/01-$1"
  git -C "$S54_WT" worktree add -q -b "wt/01-$1" "$t" HEAD >/dev/null 2>&1
  mkdir -p "$(dirname "$t/$2")"; printf '%s\n' "$3" > "$t/$2"
  ( cd "$t" && git add "$2" && git commit -qm "$1: $2" ) >/dev/null 2>&1
  S54_LAND="$( . "$S54_WTLIB" >/dev/null 2>&1; worktree_land "$t" wave/01-fixture 2>&1 )"
}
# s54_floor <log> -> a full run on the working head, recorded by proof-add floor
s54_floor() { s54_full "$1"; poke "$R54" proof-add floor "record/wave-01-fixture/$1"; }
# s54_tick -> the tick at current: 8 (proof-add runs at current: 4, where the fixture plan's gate
# admits it; the tick reads current: 8, where integrate is no longer held for its step). The
# digest is cleared first, so each tick prints its whole reading rather than "unchanged" (as 48).
s54_tick() {
  rm -f "$(digest_of "$R54")"
  sed 's/^current: 4$/current: 8/' "$P54" > "$P54.tmp" && mv "$P54.tmp" "$P54"
  poke_pressure "$R54" 8192 1.0 tick
  sed 's/^current: 8$/current: 4/' "$P54" > "$P54.tmp" && mv "$P54.tmp" "$P54"
}
s54_wait() { s47_lines WAIT | /usr/bin/grep '^poker: WAIT T3 '; }

S54_W0="$(git -C "$S54_WT" rev-parse HEAD 2>/dev/null)"
s54_floor floor-1.log
expect_contains "54a0 precondition: the copied runner's log names the working head on a clean tree" \
  "head=${S54_W0} dirty=0" "$(cat "$S54_REC/floor-1.log")"
expect_contains "54a0b precondition: …and its verdict, every suite passed" "Gating: 3 passed, 0 failed" \
  "$(cat "$S54_REC/floor-1.log")"
expect_eq "54a0c precondition: proof-add floor recorded it (exit 0)" "0" "$RC"
printf '# final review\n\nreviewed: %s..%s\n' "$S54_BASE" "$S54_W0" > "$S54_REC/review.md"
poke "$R54" proof-add review record/wave-01-fixture/review.md
expect_eq "54a0d precondition: proof-add review recorded the review (exit 0)" "0" "$RC"
expect_eq "54a0e precondition: the plan's floor proof names the working head" "$S54_W0" "$(s46_last "$P54" floor)"
s54_tick
expect_contains "54a at the proved head integrate is offered" "poker: FILL T3" "$OUT"

# ---------- AC-3.4, the criterion's planted defect: a new file under a directory no suite names ----------
s54_land T7 newdir/x.sh 'new'
expect_contains "54b0 precondition: the task tree with no suite run LANDED through the real land" \
  "spawn-worktree: LANDED branch=wt/01-T7" "$S54_LAND"
expect_false "54b0b precondition: …and no suite ever stamped it" \
  test -e "$R54/.git/worktrees/01-T7/bionic-stamps"
S54_W1="$(git -C "$S54_WT" rev-parse HEAD 2>/dev/null)"
s54_tick
expect_nonempty "54b1 precondition: the tick prints a WAIT line for integrate (the extractor reads real output)" "$(s54_wait)"
expect_eq "54b AC-3.4 integrate WAITS: the head moved past the floor proof in a way the map cannot bound, and the line names the way out" \
  "poker: WAIT T3 — proof:floor: the head moved past the floor proof at ${S54_W0:0:12} in a way the map cannot bound (the map answers newdir/x.sh with no suite); take the full run on this head and record it with proof-add floor" \
  "$(s54_wait)"
expect_absent "54b2 …and the merge is not offered" "poker: FILL T3" "$OUT"
# THE COST: one tick runs proof_state once, though its schedule and its change fingerprint each
# ask the ready set. The map is the one process the state runs that this suite can count.
: > "$S54_COUNT"; s54_tick; S54_TICK_MAPS="$(awk 'END { print NR + 0 }' "$S54_COUNT")"
: > "$S54_COUNT"; ( . "$S46_LIB" >/dev/null 2>&1; proof_state "$P54" "$R54" ) >/dev/null 2>&1
S54_PS_MAPS="$(awk 'END { print NR + 0 }' "$S54_COUNT")"
expect_true "54b2c precondition: one proof_state over this change calls the map (the counter reads real calls)" \
  test "$S54_PS_MAPS" -gt 0
expect_eq "54b2d …and one tick calls it exactly as often: the floor state is computed once per tick" \
  "$S54_PS_MAPS" "$S54_TICK_MAPS"
s54_floor floor-2.log
expect_eq "54b3 the way out: a full run on the new head, recorded with proof-add floor (exit 0)" "0" "$RC"
expect_eq "54b4 …at that head" "$S54_W1" "$(s46_last "$P54" floor)"
s54_tick
expect_contains "54b5 …and the tick offers the merge" "poker: FILL T3" "$OUT"

# ---------- AC-3.3 still holds: a bounded change after a full pass is proved by its suites ----------
s54_land T8 lib/one.sh 'one, changed'
expect_contains "54c0 precondition: the bounded change LANDED" "spawn-worktree: LANDED branch=wt/01-T8" "$S54_LAND"
s54_tick
expect_contains "54c AC-3.3 a change the map bounds leaves the pass standing: the merge is offered" "poker: FILL T3" "$OUT"
expect_eq "54c2 …with no WAIT line for it" "" "$(s54_wait)"

# ---------- a change the map answers with every suite ----------
s54_land T9 lib/every.sh 'every, changed'
expect_contains "54d0 precondition: the every-suite change LANDED" "spawn-worktree: LANDED branch=wt/01-T9" "$S54_LAND"
s54_tick
expect_contains "54d a change the map answers with every suite: integrate WAITS, saying so" \
  "poker: WAIT T3 — proof:floor: the head moved past the floor proof at ${S54_W1:0:12} in a way the map cannot bound (the map answers the change with every suite (3 of 3))" \
  "$OUT"
expect_absent "54d2 …and the merge is not offered" "poker: FILL T3" "$OUT"
s54_floor floor-3.log
s54_tick
expect_contains "54d3 …until a full run on its head is recorded" "poker: FILL T3" "$OUT"

# ---------- a merge of work from outside the run (a file the map bounds, so only the outside rule holds it) ----------
S54_W3="$(git -C "$S54_WT" rev-parse HEAD 2>/dev/null)"
( cd "$S54_WT" && git checkout -q -b other-work && printf 'one, from outside\n' > lib/one.sh \
  && git commit -qam 'outside work' && git checkout -q wave/01-fixture \
  && git merge -q --no-ff -m 'merge other-work' other-work ) >/dev/null 2>&1
expect_true "54e0 precondition: the outside commit is on the working branch" \
  git -C "$S54_WT" merge-base --is-ancestor other-work wave/01-fixture
s54_tick
expect_contains "54e a merge from outside the run: integrate WAITS, saying another branch carries it" \
  "poker: WAIT T3 — proof:floor: the head moved past the floor proof at ${S54_W3:0:12} in a way the map cannot bound (1 of 2 commits since ${S54_W3:0:7} are on another branch than wave/01-fixture" \
  "$OUT"
expect_absent "54e2 …and the merge is not offered" "poker: FILL T3" "$OUT"
s54_floor floor-4.log
s54_tick
expect_contains "54e3 …until a full run on the merge is recorded" "poker: FILL T3" "$OUT"
POKE_BOUND="$S54_BOUND_WAS"


# ============================================================
section "AMEND-ROOT: amend reads a Files: entry with the dispatch wall's one reader (wave-27 T29; REQ-12 AC-12.3, D21)"
# ============================================================
#
# THE DEFECT, from a real run: the stop wall printed `amend <name> --files+ 'CONTEXT.md'` and
# amend REFUSED it as a change of nothing, because the grammar read a Files: entry as a path
# only when it carried a `/`. amend now reads each addition with the one reader in brief.sh,
# the dispatch wall's own: a path carries a `/`, or an extension, or names a file at the root.
RAR="$(make_repo amend-root)"; new_roster "$RAR"; s30_row "$RAR"
poke "$RAR" amend w1 --files+ 'CONTEXT.md' --reason 'the fix touches the root file'
expect_eq "AMEND-ROOT AC-12.3 amend --files+ 'CONTEXT.md' succeeds" "0" "$RC"
expect_eq "AMEND-ROOT …and files= holds the root file as written" "hooks/a.sh,CONTEXT.md" \
  "$(s30_field "$(s30_last "$RAR")" files)"
# A bare name with no extension is a path when the file exists at the root.
echo x > "$RAR/Widgetfile"
poke "$RAR" amend w1 --files+ Widgetfile --reason 'and the root build file'
expect_eq "AMEND-ROOT2 a bare name that exists at the root is accepted" "0" "$RC"
expect_eq "AMEND-ROOT2 …and stored as written" "hooks/a.sh,CONTEXT.md,Widgetfile" \
  "$(s30_field "$(s30_last "$RAR")" files)"
# Any other entry refuses, naming the spelling that is accepted, and writes nothing.
RAR_SUM="$(cksum < "$(roster_of "$RAR")")"
poke "$RAR" amend w1 --files+ Otherfile --reason 'a name with no file behind it'
expect_eq "AMEND-ROOT3 an entry that is not read as a path is REFUSED (exit 1)" "1" "$RC"
expect_contains "AMEND-ROOT3 …naming the entry and the accepted spelling" "./Otherfile" "$OUT"
expect_eq "AMEND-ROOT3 …and writes nothing" "$RAR_SUM" "$(cksum < "$(roster_of "$RAR")")"
poke "$RAR" amend w1 --files+ ./Otherfile --reason 'the spelling it named'
expect_eq "AMEND-ROOT4 the spelling the refusal names is accepted" "0" "$RC"
expect_eq "AMEND-ROOT4 …and recorded" "hooks/a.sh,CONTEXT.md,Widgetfile,./Otherfile" \
  "$(s30_field "$(s30_last "$RAR")" files)"

# ============================================================
section "Section 55 §RECON-PLAN: the tick asks for a task-list reconcile when current: moves 3 to 4 and when the table grows (wave-27 T13; REQ-11 AC-11.3; D20)"
# ============================================================
#
# The tick's digest records the plan's `current:` and its `## Tasks` row count. The tick prints
# the same `poker: RECONCILE` line it already prints for a status or ready-set change when
# `current:` was 3 at the last digest and is 4 now, or the row count has grown; and nothing
# extra when neither moved. Every row below waits on the world (an `ext:` read), so the ready
# set and the decision stay QUIET across the whole case: no status or ready-set move can print
# the line, and what prints it here is the new reading alone.
SRP_ROW1="| T1 | 4 | build | waits on CI | implementor | ext:ci-rp | 15m | REQ-x | a.sh | pending |"
SRP_ROW2="| T2 | 4 | build | waits on CI too | implementor | ext:ci-rp | 15m | REQ-x | b.sh | pending |"
sRP_plan() { sp_plan_at_step "$RRP" "$1" "$SRP_ROW1" "${@:2}" >/dev/null; }
RRP="$(make_repo s55-recon-plan)"
poke "$RRP" arm
sRP_plan 3
poke_pressure "$RRP" 8192 1.0 tick
expect_contains "RPa precondition: the first tick at current: 3 read the plan (the held row is named)" "poker: HELD T1 ext:ci-rp" "$OUT"
expect_absent "RPa2 …and asks no reconcile: nothing has moved yet" "poker: RECONCILE" "$OUT"
expect_contains "RPa3 precondition: the digest records the plan's current: and its row count" \
  "plan_current=3 plan_rows=1" \
  "$(/usr/bin/grep -E '^plan_(current|rows)=' "$(digest_of "$RRP")" 2>/dev/null | tr '\n' ' ' | sed 's/ $//')"
sRP_plan 4
poke_pressure "$RRP" 8192 1.0 tick
expect_contains "RPb AC-11.3 current: moves from 3 to 4: the tick prints the RECONCILE line" "poker: RECONCILE — " "$OUT"
expect_contains "RPb2 …in the wording the status-change path already prints" \
  "poker: RECONCILE — a ## Tasks status or the ready set changed since the last tick: TaskList, and bring the task list in line with the plan" "$OUT"
expect_eq "RPb3 …once" "1" "$(count_lines_matching 'poker: RECONCILE' "$OUT")"
expect_contains "RPb4 …and the digest owes the duty" "duty=owed" "$(cat "$(digest_of "$RRP")" 2>/dev/null)"
poke_pressure "$RRP" 8192 1.0 tick
expect_absent "RPc the next tick over the same plan prints no RECONCILE" "poker: RECONCILE" "$OUT"
expect_contains "RPc2 …and says so: unchanged" "unchanged since" "$OUT"
sRP_plan 4 "$SRP_ROW2"
poke_pressure "$RRP" 8192 1.0 tick
expect_contains "RPd a row added to the table: the tick prints the RECONCILE line" "poker: RECONCILE — " "$OUT"
poke_pressure "$RRP" 8192 1.0 tick
expect_absent "RPe …and the tick after it prints none" "poker: RECONCILE" "$OUT"
sRP_plan 5 "$SRP_ROW2"
poke_pressure "$RRP" 8192 1.0 tick
expect_absent "RPf current: moving 4 to 5 is not a reconcile" "poker: RECONCILE" "$OUT"
expect_eq "RPf2 …and the digest keeps what it read (current 5, two rows)" "plan_current=5 plan_rows=2" \
  "$(/usr/bin/grep -E '^plan_(current|rows)=' "$(digest_of "$RRP")" 2>/dev/null | tr '\n' ' ' | sed 's/ $//')"

# ============================================================
section "Section 56 §FACT: a reading is a review proof with a question, a reader, a result and a scope (wave-27 T2; REQ-2 AC-2.1, REQ-1 AC-1.4, REQ-4 AC-4.3; D1, D7)"
# ============================================================
#
# `proof-add review <record> --question <q> --reader <name>` writes the review proof line with
# four more fields, ` question=<q> reader=<name> result=<pass|flag|fail> scope=<piece|whole>`.
# The result and the scope are the record's own flush-left lines, its `question:` line must be the
# operand, and the reader must have a roster row on this machine (any session's roster of the
# project) whose role is a reader role dealt that question. A `structure` record answers every
# check id its checks file names. The head is still the record's `reviewed:` end, and the range
# starts at or before the last proof of THAT question. Every refusal leaves the plan byte-identical.
#
# FIXTURE FIDELITY. The roster rows are the production writer's (`roster_row_fixture`) with one
# key appended by hand, `questions=<q>[,<q>]`: SYNTHESIZED until row T15 teaches the dispatch wall
# to write it (the Interfaces table's roster key); the verb reads it by key, as every roster reader
# does. The checks file is planted in a copy of the hook tree, where the verb resolves it through
# its own lib root, so a case can remove it or empty it; 56g11 holds the shipped one (row T8's) to
# the same reading.
S56_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
s56_last() {  # <plan> <kind> [<question>] -> proof_last's answer, from the library itself
  bash -c '. "$1" && proof_last "$2" "$3" "$4"' _ "$S46_LIB" "$1" "$2" "${3:-}" 2>/dev/null
}
R56="$(make_repo s56-fact)"; ( cd "$R56" && git commit -q --allow-empty -m init )
S56_B="$(git -C "$R56" rev-parse HEAD)"
P56="$(s42_plan "$R56" 4 "  worktree: .worktrees/01-fixture
  base-sha: ${S56_B:0:8}
  branch: wave/01-fixture")"
awk '{ print } /^current: / && !d { print "working-branch: wave/01-fixture"; d = 1 }' "$P56" > "$P56.tmp" && mv "$P56.tmp" "$P56"
( cd "$R56" && git add -f "$P56" && git commit -qm wb \
  && git worktree add -q -b wave/01-fixture "$R56/.worktrees/01-fixture" "$S56_B" ) >/dev/null 2>&1
for s56c in 1 2 3 4; do git -C "$R56/.worktrees/01-fixture" commit -q --allow-empty -m "C$s56c" >/dev/null 2>&1; done
S56_C2="$(git -C "$R56/.worktrees/01-fixture" rev-parse HEAD~2)"
S56_C3="$(git -C "$R56/.worktrees/01-fixture" rev-parse HEAD~1)"; S56_C4="$(git -C "$R56/.worktrees/01-fixture" rev-parse HEAD)"
S56_REC="$R56/.bionic/docs/record/wave-01-fixture"; mkdir -p "$S56_REC"
# s56_rec <file> <a> <b> <question> <result> <scope> [<line>...] -> a reading record; a field given
# as - is left out, and each further argument is one more line.
s56_rec() {
  local f="$S56_REC/$1" a="$2" b="$3" q="$4" r="$5" s="$6" l; shift 6
  { printf '# reading\n\n'
    [ "$a" = - ] || printf 'reviewed: %s..%s\n' "$a" "$b"
    [ "$q" = - ] || printf 'question: %s\n' "$q"
    [ "$r" = - ] || printf 'result: %s\n' "$r"
    [ "$s" = - ] || printf 'scope: %s\n' "$s"
    for l in "$@"; do printf '%s\n' "$l"; done
    printf '\nwhat the reader found\n'; } > "$f"
}
# THE ROSTERS: this session's, and a predecessor's the verb must scan too.
S56_OSID="5f5f5f5f-0000-4000-8000-000000000055"
new_roster "$R56"; roster_header > "$(roster_of "$R56" "$S56_OSID")"
s56_row() {  # <roster> <name> <type> [<questions>] -> one row appended; no questions key when none
  local r; r="$(roster_row_fixture session="$SID" name="$2" agent_id="a-$2" subagent_type="$3")"
  if [ $# -ge 4 ]; then printf '%s|questions=%s\n' "$r" "$4"; else printf '%s\n' "$r"; fi >> "$1"
}
S56_RS="$(roster_of "$R56")"; S56_RO="$(roster_of "$R56" "$S56_OSID")"
# The plan's active T2 row names `implementor` as its agent, and with a roster present the commit
# gate asks this session's roster for that name, so it carries the row the dispatch would have.
s56_row "$S56_RS" implementor implementor
s56_row "$S56_RS" w-aud bionic:auditor evidence
s56_row "$S56_RS" w-crit bionic:critic adversarial,structure
s56_row "$S56_RS" w-rev bionic:reviewer structure
s56_row "$S56_RS" w-impl bionic:implementor evidence
s56_row "$S56_RS" w-noq bionic:auditor
s56_row "$S56_RO" w-old bionic:critic adversarial
s56_row "$S56_RS" w-two bionic:critic adversarial
s56_row "$S56_RO" w-two bionic:implementor adversarial
expect_regex "56a0 precondition: the working branch's head is C4, a 40-hex commit" '^[0-9a-f]{40}$' "$S56_C4"
expect_eq "56a0b precondition: a fixture row carries the appended questions key, read by key" "evidence" \
  "$(/usr/bin/grep -F '|name=w-aud|' "$S56_RS" | tr '|' '\n' | sed -n 's/^questions=//p')"
expect_eq "56a0c precondition: …and its role, as the production writer wrote it" "bionic:auditor" \
  "$(/usr/bin/grep -F '|name=w-aud|' "$S56_RS" | tr '|' '\n' | sed -n 's/^subagent_type=//p')"
s34_gate "$R56"
expect_eq "56a0d precondition: the fixture plan is admitted by the real commit gate" "0" "$GATE_RC"

# ---------- §FACT-shape (AC-2.1): question, reader, range and result, or refused ----------
s56_rec ev1.md "${S56_B:0:10}" "$S56_C2" evidence pass piece
s42_snap "$R56" "$P56"
poke "$R56" proof-add review record/wave-01-fixture/ev1.md --question evidence --reader w-aud
expect_eq "56a §FACT-shape a whole reading record registers (exit 0)" "0" "$RC"
expect_eq "56a2 …one line added" "1 0;" "$(s42_numstat "$R56")"
expect_regex "56a3 …the proof line with the four reading fields, in the table's order" \
  "^proved: kind=review head=${S56_C2} at=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z evidence=record/wave-01-fixture/ev1.md question=evidence reader=w-aud result=pass scope=piece$" \
  "$(s46_proved "$P56")"
expect_contains "56a4 …and the success line names them" "question=evidence reader=w-aud result=pass scope=piece" "$OUT"
expect_eq "56a5 proof_last review evidence reads that question's head" "$S56_C2" "$(s56_last "$P56" review evidence)"
expect_eq "56a6 …a question never read reads nothing" "" "$(s56_last "$P56" review adversarial)"
expect_eq "56a7 …and with no question, the last review proof of any question (1.11.0's reading)" "$S56_C2" "$(s56_last "$P56" review)"
s34_gate "$R56"
expect_eq "56a8 …and the next commit is admitted by the real gate" "0" "$GATE_RC"

s56_rec no-reviewed.md - - evidence pass piece
s56_rec no-question.md "$S56_C2" "$S56_C3" - pass piece
s56_rec no-result.md "$S56_C2" "$S56_C3" evidence - piece
s56_rec no-scope.md "$S56_C2" "$S56_C3" evidence pass -
s56_rec fine.md "$S56_C2" "$S56_C3" evidence fine piece
s56_rec partial.md "$S56_C2" "$S56_C3" evidence pass partial
s56_rec other-q.md "$S56_C2" "$S56_C3" adversarial pass piece
s42_snap "$R56" "$P56"
poke "$R56" proof-add review record/wave-01-fixture/no-reviewed.md --question evidence --reader w-aud
s42_unchanged "56b a record with no reviewed: line" 1 "$P56"
expect_contains "56b2 …naming the line" "reviewed:" "$OUT"
poke "$R56" proof-add review record/wave-01-fixture/no-question.md --question evidence --reader w-aud
s42_unchanged "56b3 a record with no question: line" 1 "$P56"
expect_contains "56b4 …naming the line" "question:" "$OUT"
poke "$R56" proof-add review record/wave-01-fixture/no-result.md --question evidence --reader w-aud
s42_unchanged "56b5 a record with no result: line" 1 "$P56"
expect_contains "56b6 …naming the line and the set" "no result: line; write result: pass, flag or fail" "$OUT"
poke "$R56" proof-add review record/wave-01-fixture/no-scope.md --question evidence --reader w-aud
s42_unchanged "56b7 a record with no scope: line" 1 "$P56"
expect_contains "56b8 …naming the line and the set" "no scope: line; write scope: piece or whole" "$OUT"
poke "$R56" proof-add review record/wave-01-fixture/fine.md --question evidence --reader w-aud
s42_unchanged "56b9 AC-2.1 result: fine, outside the set" 1 "$P56"
expect_contains "56b10 …naming the value and the set" "'fine'" "$OUT"
poke "$R56" proof-add review record/wave-01-fixture/partial.md --question evidence --reader w-aud
s42_unchanged "56b11 scope: partial, outside the set" 1 "$P56"
poke "$R56" proof-add review record/wave-01-fixture/other-q.md --question evidence --reader w-aud
s42_unchanged "56b12 a record whose question: is not the operand" 1 "$P56"
expect_contains "56b13 …naming both" "question: adversarial" "$OUT"
poke "$R56" proof-add review record/wave-01-fixture/ev1.md --question style --reader w-aud
s42_unchanged "56b14 a question outside evidence, adversarial, structure" 1 "$P56"
expect_contains "56b15 …naming the three" "evidence, adversarial or structure" "$OUT"
poke "$R56" proof-add review record/wave-01-fixture/ev1.md --question evidence
s42_unchanged "56b16 --question with no --reader is the usage error" 2 "$P56"
poke "$R56" proof-add review record/wave-01-fixture/ev1.md --reader w-aud
s42_unchanged "56b17 --reader with no --question is the usage error" 2 "$P56"
poke "$R56" proof-add floor record/wave-01-fixture/ev1.md --question evidence --reader w-aud
s42_unchanged "56b18 the reading flags on a floor proof are the usage error" 2 "$P56"
poke "$R56" proof-add review record/wave-01-fixture/ev1.md --question evidence --reader w-aud --scope whole
s42_unchanged "56b19 …and so is a flag the verb does not take" 2 "$P56"

# A FLAGGED OR FAILING READING IS A FACT TOO: the verb records what the reader found; whether it
# holds is the judge's question (row T9).
s56_rec ev-fail.md "$S56_C2" "$S56_C3" evidence fail whole
s42_snap "$R56" "$P56"
poke "$R56" proof-add review record/wave-01-fixture/ev-fail.md --question evidence --reader w-aud
expect_eq "56c a failing reading registers (exit 0)" "0" "$RC"
expect_contains "56c2 …carrying result=fail scope=whole" \
  "evidence=record/wave-01-fixture/ev-fail.md question=evidence reader=w-aud result=fail scope=whole" "$(s46_proved "$P56" | tail -1)"

# A PLAN BUILT UNDER 1.11.0 STILL WORKS: no --question, today's line and today's range start (the
# last review proof of any question, here the failing evidence reading at C3).
printf '# review\n\nreviewed: %s..%s\n' "$S56_C3" "$S56_C4" > "$S56_REC/legacy.md"
s42_snap "$R56" "$P56"
poke "$R56" proof-add review record/wave-01-fixture/legacy.md
expect_eq "56d a review proof with no --question registers as before (exit 0)" "0" "$RC"
expect_regex "56d2 …in 1.11.0's four-field shape" \
  "^proved: kind=review head=${S56_C4} at=[^ ]+ evidence=record/wave-01-fixture/legacy.md$" "$(s46_proved "$P56" | tail -1)"
expect_eq "56d3 …which no question reads as its own" "$S56_C3" "$(s56_last "$P56" review evidence)"

# THE RANGE STARTS AT THAT QUESTION'S LAST PROOF (D1; research §A.4). The adversarial question has
# no proof yet, so its first reading starts at the plan's base, though evidence was read to C3 and
# the legacy review to C4.
s56_rec adv-late.md "$S56_C2" "$S56_C4" adversarial pass piece
s56_rec adv1.md "${S56_B:0:10}" "$S56_C4" adversarial flag whole
s42_snap "$R56" "$P56"
poke "$R56" proof-add review record/wave-01-fixture/adv-late.md --question adversarial --reader w-crit
s42_unchanged "56e a first adversarial reading starting past the plan's base" 1 "$P56"
expect_contains "56e2 …naming the base" "past the plan's base ${S56_B:0:12}" "$OUT"
poke "$R56" proof-add review record/wave-01-fixture/adv1.md --question adversarial --reader w-crit
expect_eq "56e3 …and one from the base registers" "0" "$RC"
expect_eq "56e4 proof_last review adversarial reads its head" "$S56_C4" "$(s56_last "$P56" review adversarial)"
s56_rec ev-narrow.md "$S56_C4" "$S56_C4" evidence pass piece
s56_rec ev2.md "$S56_C3" "$S56_C4" evidence pass piece
s42_snap "$R56" "$P56"
poke "$R56" proof-add review record/wave-01-fixture/ev-narrow.md --question evidence --reader w-aud
s42_unchanged "56e5 an evidence reading past evidence's own last proof, though the last review of any question is at C4" 1 "$P56"
expect_contains "56e6 …naming that proof" "past the last evidence proof ${S56_C3:0:12}" "$OUT"
poke "$R56" proof-add review record/wave-01-fixture/ev2.md --question evidence --reader w-aud
expect_eq "56e7 …and one from it registers" "0" "$RC"

# ---------- §FACT-reader (AC-1.4): a reader never reads its own code ----------
s56_rec adv2.md "$S56_C2" "$S56_C4" adversarial pass piece
s42_snap "$R56" "$P56"
poke "$R56" proof-add review record/wave-01-fixture/adv2.md --question adversarial --reader ghost
s42_unchanged "56f AC-1.4 a reader with no roster row on this machine" 1 "$P56"
expect_contains "56f2 …naming the name" "ghost" "$OUT"
poke "$R56" proof-add review record/wave-01-fixture/ev2.md --question evidence --reader w-impl
s42_unchanged "56f3 AC-1.4 a reader whose row is a writer's, though it names the question" 1 "$P56"
expect_contains "56f4 …naming its role" "bionic:implementor" "$OUT"
poke "$R56" proof-add review record/wave-01-fixture/ev2.md --question evidence --reader w-noq
s42_unchanged "56f5 a reader role whose row names no questions" 1 "$P56"
expect_contains "56f6 …naming the question it was not dealt" "evidence" "$OUT"
poke "$R56" proof-add review record/wave-01-fixture/adv2.md --question adversarial --reader w-aud
s42_unchanged "56f7 a reader role dealt another question" 1 "$P56"
poke "$R56" proof-add review record/wave-01-fixture/adv2.md --question adversarial --reader w-two
s42_unchanged "56f8 a name a writer row carries in another session's roster" 1 "$P56"
expect_contains "56f9 …naming the writer role" "bionic:implementor" "$OUT"
poke "$R56" proof-add review record/wave-01-fixture/adv2.md --question adversarial --reader 'w old'
s42_unchanged "56f10 a reader name the space-separated line cannot hold" 1 "$P56"
poke "$R56" proof-add review record/wave-01-fixture/adv2.md --question adversarial --reader w-old
expect_eq "56f11 a reader row in a predecessor session's roster is found (exit 0)" "0" "$RC"
expect_contains "56f12 …and reader= is that row's name" "question=adversarial reader=w-old result=pass scope=piece" \
  "$(s46_proved "$P56" | tail -1)"

# ---------- §FACT-checks (AC-4.3): every structure check answered ----------
S56_IDS="reuse one-site single-job open-closed substitution narrow-interface dependency-direction"
s56_tree() {  # <root> [<checks file body>] -> a copy of the hook tree, the checks file planted when given
  mkdir -p "$1/hooks" "$1/scripts"
  cp "$BIONIC_HOOKS_DIR"/*.sh "$1/hooks/"
  cp -R "$(cd "$BIONIC_HOOKS_DIR/../payload/scripts/lib" && pwd -P)" "$1/scripts/lib"
  cp "$BIONIC_HOOKS_DIR"/../payload/scripts/*.sh "$1/scripts/"
  if [ $# -ge 2 ]; then mkdir -p "$1/context"; printf '%s' "$2" > "$1/context/checks-structure.md"; fi
}
S56_CHECKS="$(printf '# Structure checks\n\n'; for s56i in $S56_IDS; do printf -- '- **%s** — the check, and a failing case.\n' "$s56i"; done)"
s56_tree "$TMPROOT/s56-tree" "$S56_CHECKS"
s56_tree "$TMPROOT/s56-bare"
s56_tree "$TMPROOT/s56-noids" "$(printf '# Structure checks\n\nNo items here.\n')"
s56_checks() {  # <omit id> [<replace line>] -> one check: line per id but <omit id>, then <replace line>
  local i; for i in $S56_IDS; do [ "$i" = "$1" ] || printf 'check: %s PASS nothing to report\n' "$i"; done
  [ -z "${2:-}" ] || printf '%s\n' "$2"
}
S56_ALL="$(s56_checks none)"
expect_eq "56g0 precondition: the planted checks file names seven ids as - **<id>** items" "7" \
  "$(/usr/bin/grep -cE '^- \*\*[a-z-]+\*\*' "$TMPROOT/s56-tree/context/checks-structure.md")"
s56_rec st-all.md "${S56_B:0:10}" "$S56_C4" structure pass whole "$S56_ALL"
s56_rec st-no-single.md "${S56_B:0:10}" "$S56_C4" structure pass whole "$(s56_checks single-job)"
s56_rec st-maybe.md "${S56_B:0:10}" "$S56_C4" structure pass whole "$(s56_checks single-job 'check: single-job MAYBE unsure')"
s56_rec st-bare.md "${S56_B:0:10}" "$S56_C4" structure pass whole "$(s56_checks single-job 'check: single-job PASS')"
S56_POKER_REAL="$POKER"
s42_snap "$R56" "$P56"
POKER="$TMPROOT/s56-tree/hooks/session-poker.sh"
poke "$R56" proof-add review record/wave-01-fixture/st-no-single.md --question structure --reader w-rev
s42_unchanged "56g AC-4.3 a structure record that leaves single-job unanswered" 1 "$P56"
expect_contains "56g2 …naming the id" "single-job" "$OUT"
poke "$R56" proof-add review record/wave-01-fixture/st-maybe.md --question structure --reader w-rev
s42_unchanged "56g3 a check answered outside PASS, FLAG, FAIL, n/a" 1 "$P56"
poke "$R56" proof-add review record/wave-01-fixture/st-bare.md --question structure --reader w-rev
s42_unchanged "56g4 a check answered with no reason" 1 "$P56"
POKER="$TMPROOT/s56-bare/hooks/session-poker.sh"
poke "$R56" proof-add review record/wave-01-fixture/st-all.md --question structure --reader w-rev
s42_unchanged "56g5 a structure reading where the hook's lib root holds no checks file" 1 "$P56"
expect_contains "56g6 …naming the file it read for the ids" "checks-structure.md" "$OUT"
POKER="$TMPROOT/s56-noids/hooks/session-poker.sh"
poke "$R56" proof-add review record/wave-01-fixture/st-all.md --question structure --reader w-rev
s42_unchanged "56g7 a checks file that names no check id" 1 "$P56"
POKER="$TMPROOT/s56-tree/hooks/session-poker.sh"
poke "$R56" proof-add review record/wave-01-fixture/st-all.md --question structure --reader w-rev
expect_eq "56g8 a structure record answering all seven registers (exit 0)" "0" "$RC"
expect_contains "56g9 …as a structure reading by the reviewer" "question=structure reader=w-rev result=pass scope=whole" \
  "$(s46_proved "$P56" | tail -1)"
s56_rec st-crit.md "$S56_C4" "$S56_C4" structure flag piece "$S56_ALL"
poke "$R56" proof-add review record/wave-01-fixture/st-crit.md --question structure --reader w-crit
expect_eq "56g10 …and by a critic whose row lists it among two questions" "0" "$RC"
POKER="$S56_POKER_REAL"
# THE SHIPPED CHECKS FILE AND THE VERB AGREE: read through the same function the verb runs, the
# file the plugin ships accepts a record answering the Interfaces table's seven ids and refuses
# one that leaves single-job out.
S56_SHIPPED="${BIONIC_HOOKS_DIR}/../payload/context/checks-structure.md"
s56_read() { bash -c '. "$1" && proof_reading "$2" structure "$3"' _ "$S46_LIB" "$1" "$S56_SHIPPED" 2>/dev/null; }
expect_eq "56g11 the shipped checks file accepts a record answering the seven ids" "pass whole" "$(s56_read "$S56_REC/st-all.md")"
expect_contains "56g12 …and refuses one that leaves single-job unanswered" "leaves single-job unanswered" \
  "$(s56_read "$S56_REC/st-no-single.md")"
expect_eq "56h no projection copy is left beside the plan" "" \
  "$(find "$R56/.bionic/docs/plans" -name '*.plan.md.*' 2>/dev/null)"
POKE_BOUND="$S56_BOUND_WAS"

# ============================================================
section "Section 57 §JUDGE §WHOLE §WAIVE: facts_state says, per owed fact, whether it holds at a head; waive is the user's act (wave-27 T9; REQ-1 AC-1.2 AC-1.6, REQ-2 AC-2.3 AC-2.4, REQ-3 AC-3.1; D2, D10)"
# ============================================================
#
# `facts_owed <rigor> <scale>` (payload/scripts/lib/proof.sh) deals what a run owes: the floor, and
# one review fact per question for the role the rigor gives it, with a `scope=whole` fact more per
# code question at wave scale. `facts_state <plan> <head>` answers each owed line: covered,
# uncovered and the range nobody read, failing and the evidence that failed, or absent; rc 0 only
# when every line is covered. A question's facts and waivers are one chain in plan order: it holds
# at <head> when its newest link is not a failing fact and that link's head is <head>, or every
# commit past it touches only the docs root. `waive <question> '<reply>'` writes the user's waiver
# through the verb transaction, at the working head.
#
# FIXTURE FIDELITY. The fact lines are written by the production writer, proof.sh `proof_line`
# placed by `proof_add_line`, and waivers by `proof_waiver_line`, not by the verb: §56 holds the
# verb's admission of a reading, and the judge reads plan text whatever wrote it. 57t registers
# through the verb itself. The working branch's commits are real: two code commits, one commit
# under the docs root alone, one code commit. The 57t roster row carries `questions=` appended by
# hand (s56_row): SYNTHESIZED until row T15 teaches the dispatch wall to write it.
S57_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
S57_LIB="${BIONIC_HOOKS_DIR}/../payload/scripts/lib/proof.sh"
R57="$(make_repo s57-judge)"; ( cd "$R57" && git commit -q --allow-empty -m init )
git -C "$R57" config user.name "Dana Fixture"
S57_B="$(git -C "$R57" rev-parse HEAD)"
P57="$(s42_plan "$R57" 4 "  worktree: .worktrees/01-fixture
  base-sha: ${S57_B:0:8}
  branch: wave/01-fixture")"
awk '{ print } /^current: / && !d { print "working-branch: wave/01-fixture"; d = 1 }' "$P57" > "$P57.tmp" && mv "$P57.tmp" "$P57"
( cd "$R57" && git add -f "$P57" && git commit -qm wb \
  && git worktree add -q -b wave/01-fixture "$R57/.worktrees/01-fixture" "$S57_B" ) >/dev/null 2>&1
S57_WT="$R57/.worktrees/01-fixture"
s57_commit() {  # <checkout> <path> <message> -> the head after one commit touching <path>
  mkdir -p "$1/$(dirname "$2")"; printf '%s\n' "$3" >> "$1/$2"
  ( cd "$1" && git add -f "$2" && git commit -qm "$3" ) >/dev/null 2>&1
  git -C "$1" rev-parse HEAD
}
S57_C1="$(s57_commit "$S57_WT" lib/a.sh C1)"
S57_C2="$(s57_commit "$S57_WT" lib/a.sh C2)"
S57_C3="$(s57_commit "$S57_WT" .bionic/docs/record/wave-01-fixture/note.md C3)"
S57_C4="$(s57_commit "$S57_WT" lib/b.sh C4)"
cp "$P57" "$TMPROOT/s57-clean"
s57_reset() { cp "$TMPROOT/s57-clean" "$P57"; }
s57_add() {  # <plan> <line> -> the line placed by the production placer
  bash -c '. "$1" && proof_add_line "$2" "$3"' _ "$S57_LIB" "$1" "$2" > "$1.new" && mv "$1.new" "$1"
}
s57_fact() {  # <question> <head> <result> <scope> [<plan>] -> a reading line, its evidence named after it
  s57_add "${5:-$P57}" "$(bash -c '. "$1" && proof_line review "$2" 2026-10-04T12:00:00Z "$3" "$4" w-read "$5" "$6"' \
    _ "$S57_LIB" "$2" "record/wave-01-fixture/$1-$3-$4.md" "$1" "$3" "$4")"
}
s57_floor() {  # <head> [<plan>]
  s57_add "${2:-$P57}" "$(bash -c '. "$1" && proof_line floor "$2" 2026-10-04T12:00:00Z record/wave-01-fixture/floor.log' _ "$S57_LIB" "$1")"
}
s57_waiver() {  # <question> <head>
  s57_add "$P57" "$(bash -c '. "$1" && proof_waiver_line "$2" "$3" "Dana Fixture" 2026-10-04T12:00:00Z "ship it"' _ "$S57_LIB" "$1" "$2")"
}
s57_state() {  # <plan> <head> -> S57_OUT, S57_RC: what facts_state prints and its exit
  S57_OUT="$(bash -c '. "$1" && facts_state "$2" "$3"' _ "$S57_LIB" "$1" "$2" 2>/dev/null)"; S57_RC=$?
}
s57_of() {  # <owed line> -> the state facts_state gave that line (what follows it and a tab)
  printf '%s\n' "$S57_OUT" | F="$1" awk 'index($0, ENVIRON["F"] "\t") == 1 { print substr($0, length(ENVIRON["F"]) + 2); exit }'
}
S57_EV="$(printf 'review\tevidence\tbionic:auditor\tpiece')"
S57_AD="$(printf 'review\tadversarial\tbionic:critic\tpiece')"
S57_ST="$(printf 'review\tstructure\tbionic:reviewer\tpiece')"
S57_ADW="$(printf 'review\tadversarial\tbionic:critic\twhole')"
S57_STW="$(printf 'review\tstructure\tbionic:reviewer\twhole')"
s57_all() {  # <state>... -> the six owed lines of this plan, each with the next state
  printf 'floor\t%s\n%s\t%s\n%s\t%s\n%s\t%s\n%s\t%s\n%s\t%s' "$1" "$S57_EV" "$2" "$S57_AD" "$3" "$S57_ST" "$4" "$S57_ADW" "$5" "$S57_STW" "$6"
}
expect_regex "57a0 precondition: the working branch's head is C4, a 40-hex commit" '^[0-9a-f]{40}$' "$S57_C4"
expect_eq "57a0b precondition: C3 touches the docs root alone" ".bionic/docs/record/wave-01-fixture/note.md" \
  "$(git -C "$S57_WT" show --name-only --format= "$S57_C3")"
expect_eq "57a0c precondition: …and C4 a tracked path outside it" "lib/b.sh" "$(git -C "$S57_WT" show --name-only --format= "$S57_C4")"
expect_eq "57a0d precondition: the dealing for this plan (audited, wave): the floor, three piece reads, two whole reads" \
  "$(printf 'floor\n%s\n%s\n%s\n%s\n%s' "$S57_EV" "$S57_AD" "$S57_ST" "$S57_ADW" "$S57_STW")" \
  "$(bash -c '. "$1" && facts_owed audited wave' _ "$S57_LIB")"

# ---------- §JUDGE (AC-2.3): covered, uncovered naming its range, a docs-only tail ----------
s57_reset; s57_floor "$S57_C4"
for s57q in evidence adversarial structure; do s57_fact "$s57q" "$S57_C4" pass piece; done
s57_fact adversarial "$S57_C4" pass whole; s57_fact structure "$S57_C4" pass whole
s57_state "$P57" "$S57_C4"
expect_eq "57a §JUDGE every owed fact read at the head: each owed line, covered" \
  "$(s57_all covered covered covered covered covered covered)" "$S57_OUT"
expect_eq "57a2 …and rc 0" "0" "$S57_RC"
s57_reset; s57_floor "$S57_C4"
s57_fact evidence "$S57_C4" pass piece; s57_fact structure "$S57_C4" pass piece; s57_fact structure "$S57_C4" pass whole
s57_fact adversarial "$S57_C1" pass whole; s57_fact adversarial "$S57_C1" pass piece
s57_state "$P57" "$S57_C4"
expect_eq "57b §JUDGE AC-2.3 code landed past the last adversarial head: uncovered, naming the range nobody read" \
  "uncovered	${S57_C1}..${S57_C4}" "$(s57_of "$S57_AD")"
expect_eq "57b2 …the run does not hold (rc 1)" "1" "$S57_RC"
expect_eq "57b3 …while the questions read at the head stay covered" "covered" "$(s57_of "$S57_ST")"
expect_eq "57b4 …and the whole read, taken once, is not owed again for the later code" "covered" "$(s57_of "$S57_ADW")"
s57_reset; s57_floor "$S57_C4"
for s57q in evidence adversarial structure; do s57_fact "$s57q" "$S57_C2" pass piece; done
s57_fact adversarial "$S57_C2" pass whole; s57_fact structure "$S57_C2" pass whole
s57_state "$P57" "$S57_C3"
expect_eq "57c §JUDGE a docs-only tail: past the last head only the docs root changed, so every line is covered" \
  "$(s57_all covered covered covered covered covered covered)" "$S57_OUT"
expect_eq "57c2 …rc 0" "0" "$S57_RC"
s57_state "$P57" "$S57_C4"
expect_eq "57c3 …and one code commit more is uncovered from the same last head" "uncovered	${S57_C2}..${S57_C4}" "$(s57_of "$S57_EV")"
s57_reset; s57_floor "$S57_C4"
for s57q in evidence adversarial structure; do s57_fact "$s57q" "$S57_C1" pass piece; done
s57_state "$P57" "$S57_C3"
expect_eq "57c4 …a tail whose docs commit follows a code commit is not docs-only" "uncovered	${S57_C1}..${S57_C3}" "$(s57_of "$S57_ST")"

# ---------- §JUDGE (AC-2.4): failing, and what clears it ----------
s57_reset; s57_floor "$S57_C4"
s57_fact evidence "$S57_C2" pass piece; s57_fact evidence "$S57_C4" fail piece
s57_state "$P57" "$S57_C4"
expect_eq "57d §JUDGE AC-2.4 the question's newest fact is result=fail: failing, naming its evidence" \
  "failing	record/wave-01-fixture/evidence-fail-piece.md" "$(s57_of "$S57_EV")"
expect_eq "57d2 …rc 1" "1" "$S57_RC"
s57_fact evidence "$S57_C4" pass piece
s57_state "$P57" "$S57_C4"
expect_eq "57d3 …a later pass over the fix clears it" "covered" "$(s57_of "$S57_EV")"
s57_fact evidence "$S57_C4" flag piece
s57_state "$P57" "$S57_C4"
expect_eq "57d4 …and a flag is not a failure" "covered" "$(s57_of "$S57_EV")"

# ---------- §JUDGE: a waiver ----------
s57_reset; s57_fact evidence "$S57_C4" fail piece; s57_waiver evidence "$S57_C4"
s57_state "$P57" "$S57_C4"
expect_eq "57e §JUDGE a waiver newer than the failing fact covers the question" "covered" "$(s57_of "$S57_EV")"
s57_reset; s57_waiver evidence "$S57_C4"; s57_fact evidence "$S57_C4" fail piece
s57_state "$P57" "$S57_C4"
expect_eq "57e2 …a waiver older than it does not" "failing	record/wave-01-fixture/evidence-fail-piece.md" "$(s57_of "$S57_EV")"
s57_reset; s57_fact evidence "$S57_C2" fail piece; s57_waiver evidence "$S57_C2"
s57_state "$P57" "$S57_C4"
expect_eq "57e3 …a waiver covers its question up to its own head, and code past it is uncovered" \
  "uncovered	${S57_C2}..${S57_C4}" "$(s57_of "$S57_EV")"
s57_reset; s57_waiver structure "$S57_C4"
s57_state "$P57" "$S57_C4"
expect_eq "57e4 …a waiver alone covers its question at its head" "covered" "$(s57_of "$S57_ST")"
expect_eq "57e5 …and its whole read, which the user waived with the question" "covered" "$(s57_of "$S57_STW")"

# ---------- §JUDGE: absent ----------
s57_reset; s57_floor "$S57_C4"; s57_fact evidence "$S57_C4" pass piece
s57_add "$P57" "$(bash -c '. "$1" && proof_line review "$2" 2026-10-04T12:00:00Z record/wave-01-fixture/old.md' _ "$S57_LIB" "$S57_C4")"
s57_state "$P57" "$S57_C4"
expect_eq "57f §JUDGE a question with no fact and no waiver is absent" "absent" "$(s57_of "$S57_ST")"
expect_eq "57f2 …a review line carrying no question (1.11.0's) answers no question" "absent" "$(s57_of "$S57_AD")"
expect_eq "57f3 …while the question that has a fact is judged" "covered" "$(s57_of "$S57_EV")"
expect_eq "57f4 …and the floor is proof_state's answer: the floor proof names the working head, covered" "covered" "$(s57_of floor)"
s57_reset; s57_fact evidence "$S57_C4" pass piece
s57_state "$P57" "$S57_C4"
expect_eq "57f5 …with no floor proof the floor is absent" "absent" "$(s57_of floor)"
sed '/^rigor: /d' "$P57" > "$TMPROOT/s57-norigor.plan.md"
s57_state "$TMPROOT/s57-norigor.plan.md" "$S57_C4"
expect_eq "57f6 a plan whose rigor cannot be read is judged nothing: rc 2" "2" "$S57_RC"
expect_eq "57f7 …and no line is printed for it" "" "$S57_OUT"

# ---------- §WHOLE (AC-1.6): piece facts alone do not hold a wave ----------
# A proof line carries no range start, so the judge cannot see what a `scope=whole` reading read:
# it takes the line as the verb wrote it, and relies on the verb (row T41) refusing a whole read
# whose range starts after the plan's base-sha. 57w8 pins the answer on a planted whole line.
s57_reset; s57_floor "$S57_C4"
for s57q in evidence adversarial structure; do s57_fact "$s57q" "$S57_C4" pass piece; done
s57_state "$P57" "$S57_C4"
expect_eq "57w §WHOLE AC-1.6 a wave with piece facts and no scope=whole fact: every piece covered, each whole read absent" \
  "$(s57_all covered covered covered covered absent absent)" "$S57_OUT"
expect_eq "57w2 …so the run does not hold (rc 1)" "1" "$S57_RC"
s57_fact adversarial "$S57_C4" pass whole
s57_state "$P57" "$S57_C4"
expect_eq "57w3 …a whole read of one code question covers that line alone" "covered absent" \
  "$(s57_of "$S57_ADW") $(s57_of "$S57_STW")"
s57_fact structure "$S57_C4" fail whole
s57_state "$P57" "$S57_C4"
expect_eq "57w4 …a failing whole read is failing, on the whole line" "failing	record/wave-01-fixture/structure-fail-whole.md" "$(s57_of "$S57_STW")"
expect_eq "57w5 …and on the question's piece line, whose newest fact it is" "failing	record/wave-01-fixture/structure-fail-whole.md" "$(s57_of "$S57_ST")"
s57_reset; s57_floor "$S57_C4"
s57_fact adversarial "$S57_C2" pass whole; s57_fact adversarial "$S57_C4" pass piece
s57_state "$P57" "$S57_C4"
expect_eq "57w6 D10 a fix landed after the whole read is covered by a piece read" "covered covered" \
  "$(s57_of "$S57_AD") $(s57_of "$S57_ADW")"
s57_reset; s57_fact structure "$S57_C4" pass whole
s57_state "$P57" "$S57_C4"
expect_eq "57w8 a planted scope=whole line, whatever range its record read, is taken as written: the whole read and the piece chain both covered at its head" \
  "covered covered" "$(s57_of "$S57_STW") $(s57_of "$S57_ST")"
expect_eq "57w7 a task-scale dealing owes no whole read" "" \
  "$(bash -c '. "$1" && facts_owed audited task' _ "$S57_LIB" | /usr/bin/grep -F whole)"

# ---------- §WAIVE: the verb, through the plan transaction ----------
s57_reset; s42_snap "$R57" "$P57"
poke "$R57" waive adversarial 'Ship it, the fix is one line.'
expect_eq "57v §WAIVE waive writes the waiver (exit 0)" "0" "$RC"
expect_eq "57v2 …one line added" "1 0;" "$(s42_numstat "$R57")"
expect_regex "57v3 …the waiver line: the question, the working head, the git user, the instant and the reply" \
  "^waived: question=adversarial head=${S57_C4} by Dana Fixture [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z \"Ship it, the fix is one line\.\"$" \
  "$(/usr/bin/grep -E '^waived: ' "$P57")"
expect_contains "57v4 …and the success line names it" "question=adversarial head=${S57_C4}" "$OUT"
s57_state "$P57" "$S57_C4"
expect_eq "57v5 …which the judge reads: adversarial covered at the working head" "covered" "$(s57_of "$S57_AD")"
s57_fact adversarial "$S57_C4" fail piece
expect_eq "57v6 …a fact registered after it is placed after it" "waived: proved:" \
  "$(/usr/bin/grep -oE '^(waived|proved):' "$P57" | tr '\n' ' ' | sed 's/ $//')"
s57_state "$P57" "$S57_C4"
expect_eq "57v7 …so a later failing fact is newer than the waiver" "failing	record/wave-01-fixture/adversarial-fail-piece.md" "$(s57_of "$S57_AD")"
poke "$R57" waive structure 'keep C:\new\t as written'
expect_eq "57v7b a reply with backslashes is written (exit 0)" "0" "$RC"
expect_contains "57v7c …byte for byte" '"keep C:\new\t as written"' "$(/usr/bin/grep -F 'waived: question=structure' "$P57")"
s42_snap "$R57" "$P57"
poke "$R57" waive verdict 'Ship it.'
s42_unchanged "57v8 a question outside the set" 1 "$P57"
expect_contains "57v9 …naming the three questions" "evidence, adversarial or structure" "$OUT"
poke "$R57" waive adversarial $'two\nlines'
s42_unchanged "57v10 a reply with a line break" 1 "$P57"
poke "$R57" waive adversarial
s42_unchanged "57v11 no reply (the usage error)" 2 "$P57"
poke "$R57" waive adversarial '   '
s42_unchanged "57v12 a blank reply (the usage error)" 2 "$P57"
expect_eq "57v13 no projection copy is left beside the plan" "" \
  "$(find "$R57/.bionic/docs/plans" -name '*.plan.md.*' 2>/dev/null)"

# ---------- §TASK: a task-scale plan registers a reading and is judged (the Step-2 assumption) ----------
R57T="$(make_repo s57-task)"; ( cd "$R57T" && git commit -q --allow-empty -m init )
S57T_B="$(git -C "$R57T" rev-parse HEAD)"
P57T="$R57T/.bionic/docs/plans/epic-99-fixture/task-01-fixture.plan.md"
mkdir -p "$(dirname "$P57T")"
{
  printf -- '---\ngoverning-skill: canonical-sdlc\ncanonical_sdlc_version: 14\nintent: bugfix\n'
  printf 'rigor: tested\nscale: task\nmulti_agent: false\nuse_worktree: true\nhas_ui: false\n'
  printf 'walk: exempt\ndeploy_target: n/a\n'
  printf 'parallel-budget: writers=8 suites=4 worktrees=32 test_jobs=8 source=probe\n---\n\n'
  printf '# fixture task\n\n## SDLC State\n\ncurrent: T1\n%s\nworking-branch: task/01-fixture\n\n' "$SP_APPROVED_LINE"
  printf -- '- T1: the fix, in .worktrees/01-task\n\n'
  printf '## Tasks\n\n| id | intent | rigor | description | status |\n|---|---|---|---|---|\n'
  printf '| T1 | bugfix | tested | the fix | active |\n\n'
  printf '## Verification Matrix\n\n| AC | tier | status | evidence | auditor |\n|---|---|---|---|---|\n'
  printf '| AC-1.1 | T2 | pending | — | — |\n\nAC-1.1:\n  provenance: fixture\n  fails-when: the fixture is wrong\n'
} > "$P57T"
bound_marker "$R57T" "$SID" "$P57T" >/dev/null 2>&1
( cd "$R57T" && git add -f "$P57T" && git commit -qm plan \
  && git worktree add -q -b task/01-fixture "$R57T/.worktrees/01-task" "$S57T_B" ) >/dev/null 2>&1
S57T_C1="$(s57_commit "$R57T/.worktrees/01-task" lib/fix.sh C1)"
new_roster "$R57T"
s56_row "$(roster_of "$R57T")" w-tcrit bionic:critic evidence,adversarial,structure
S57T_REC="$R57T/.bionic/docs/record/task-01-fixture"; mkdir -p "$S57T_REC"
S57T_CHECKS="$(awk '/^- \*\*[a-z][a-z-]*\*\*/ { s = $0; sub(/^- \*\*/, "", s); sub(/\*\*.*$/, "", s); printf "check: %s PASS nothing to report\n", s }' \
  "${BIONIC_HOOKS_DIR}/../payload/context/checks-structure.md")"
for s57q in evidence adversarial structure; do
  { printf 'reviewed: %s..%s\nquestion: %s\nresult: pass\nscope: piece\n' "$S57T_B" "$S57T_C1" "$s57q"
    [ "$s57q" = structure ] && printf '%s\n' "$S57T_CHECKS"; printf '\nwhat the reader found\n'; } > "$S57T_REC/$s57q.md"
done
expect_regex "57t0 precondition: the shipped checks file names check ids the structure record answers" \
  '^check: [a-z-]+ PASS' "$(printf '%s\n' "$S57T_CHECKS" | head -1)"
s34_gate "$R57T"
expect_eq "57t0b precondition: the task-scale fixture plan is admitted by the real commit gate" "0" "$GATE_RC"
for s57q in evidence adversarial structure; do
  poke "$R57T" proof-add review "record/task-01-fixture/$s57q.md" --question "$s57q" --reader w-tcrit
  expect_eq "57t §TASK a task-scale plan registers a $s57q reading through the verb (exit 0)" "0" "$RC"
done
expect_eq "57t2 …three reading lines, at the task branch's head" "3" \
  "$(/usr/bin/grep -cE "^proved: kind=review head=${S57T_C1} .* reader=w-tcrit result=pass scope=piece$" "$P57T")"
s57_floor "$S57T_C1" "$P57T"
s57_state "$P57T" "$S57T_C1"
expect_eq "57t3 …and facts_state judges it by facts_owed tested task: the floor and one critic's three questions, covered" \
  "$(printf 'floor\tcovered\nreview\tevidence\tbionic:critic\tpiece\tcovered\nreview\tadversarial\tbionic:critic\tpiece\tcovered\nreview\tstructure\tbionic:critic\tpiece\tcovered')" \
  "$S57_OUT"
expect_eq "57t4 …rc 0" "0" "$S57_RC"
S57T_C2="$(s57_commit "$R57T/.worktrees/01-task" lib/fix.sh C2)"
s57_state "$P57T" "$S57T_C2"
expect_eq "57t5 …and a commit past the readings is uncovered there too" "uncovered	${S57T_C1}..${S57T_C2}" \
  "$(s57_of "$(printf 'review\tadversarial\tbionic:critic\tpiece')")"
POKE_BOUND="$S57_BOUND_WAS"

finish
