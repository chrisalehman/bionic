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
  for kv in "$@"; do
    case "$kv" in
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
  printf '# fixture plan\n\n## SDLC State\n\nintegration-branch: main\ncurrent: %s\n\n- Step %s: %s\n' \
    "$1" "$1" "${2:-evidence for this step}"
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
poke() {  # <repo> <args...> -> sets OUT, RC
  local repo="$1"; shift
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
# (memory adopt-skips-swept-rows). The marker stays, to show it closes nothing on its own; the
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
# about the identical row. `transcript_dir_for` is the fix: one resolver, called by both.
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

wave_plan_at() {  # <repo> <path under <docs-root>/plans> <budget or "-"> <table row>... -> the path
  local repo="$1" rel="$2" budget="$3"; shift 3
  local f="$repo/.bionic/docs/plans/$rel"
  mkdir -p "$(dirname "$f")"
  {
    printf -- '---\n'
    printf 'governing-skill: superpowers:writing-plans\n'
    [ "$budget" = "-" ] || printf 'parallel-budget: %s\n' "$budget"
    printf -- '---\n\n'
    printf '# fixture plan\n\n## SDLC State\n\ncurrent: 4\n\n- Step 4: in progress\n\n'
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
expect_absent   "…never the third ready task" "THREE" "$OUT"

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
expect_absent   "…and the second ready task waits on the machine, not on the budget" "TWO" "$OUT"
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
BIONIC_PROBE_FREE_MB=512 poke_rung "$R11C7" 60 0 tick
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
expect_absent "…and does not reach the third" "THREE" "$OUT"

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
  launched_at="$(iso_ago 600)"
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
  launched_at="$(iso_ago 600)"
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
  launched_at="$(iso_ago 600)"
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
# differently for knowing it, so it prints as `poker: note:` above the decision line. The
# sentence is unchanged; the channel marker in front of it is new.
expect_contains "12a-T22-i4 …and the tick says exactly why, once, as a note" \
  "poker: note: stand-down deferred — the panel reading is stale; ListAgents and the next tick decides" \
  "$OUT"
expect_eq "12a-T22-i5 …and only once" "1" \
  "$(printf '%s\n' "$OUT" | grep -c 'stand-down deferred' | tr -d ' ')"

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
expect_absent "…and the second ready task waits" "TWO" "$OUT"

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
expect_absent "…and DEPENDENT is not named" "DEPENDENT" "$OUT"

# Several deps, one of them unlanded: ALL of them must be landed, not any.
R12F="$(make_repo s12-multi-dep)"; new_roster "$R12F"
wave_plan "$R12F" "writers=8 suites=2 worktrees=8 test_jobs=8 source=probe" \
  "| A | 4 | build | fixture task | implementor | — | 15m | REQ-x | a.sh | landed |" \
  "| B | 4 | build | fixture task | implementor | — | 15m | REQ-x | a.sh | pending |" \
  "| C | 4 | build | fixture task | implementor | A,B | 15m | REQ-x | a.sh | pending |"
poke_pressure "$R12F" 8192 1.0 tick
expect_contains "a task whose deps are landed AND pending is not ready" "poker: FILL B" "$OUT"
expect_absent "…so C waits for every one of them" " C" "$OUT"

# A dependency the table does not carry at all is not confirmable, and an unconfirmable
# dependency holds its task back — a task held costs a batch, a task dispatched onto an
# unlanded dependency costs the writer's whole run.
R12G="$(make_repo s12-unknown-dep)"; new_roster "$R12G"
wave_plan "$R12G" "writers=8 suites=2 worktrees=8 test_jobs=8 source=probe" \
  "| ORPHAN | 4 | build | fixture task | implementor | NOT-IN-THIS-TABLE | 15m | REQ-x | a.sh | pending |" \
  "| FINE | 4 | build | fixture task | implementor | — | 15m | REQ-x | a.sh | pending |"
poke_pressure "$R12G" 8192 1.0 tick
expect_contains "an unknown dependency holds its task back" "poker: FILL FINE" "$OUT"
expect_absent "…and ORPHAN is not filled" "ORPHAN" "$OUT"

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
  printf -- '---\n\n# fixture plan\n\n## SDLC State\n\ncurrent: 4\n\n- Step 4: in progress\n\n'
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
  printf -- '---\n\n# fixture plan\n\n## SDLC State\n\ncurrent: 4\n\n- Step 4: in progress\n\n'
  printf 'The task table looks like this:\n\n'
  printf '```\n## Tasks\n\n'
  printf '%s' "$SP_TASKS_HEADER"
  printf '| EXAMPLE | 4 | build | a documented example | implementor | — | 15m | REQ-x | a.sh | pending |\n```\n'
} > "$f12i"
touch "$f12i"
poke_pressure "$R12I" 8192 1.0 tick
expect_absent "a fenced task table is documentation, and fills nothing" "poker: FILL" "$OUT"
expect_contains "…and the tick says the table gave it nothing ready" \
  "no pending step-4 task has all its dependencies landed" "$OUT"

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

# ---------- 12k: READY IS ASKED AT THE PLAN'S OWN STEP (REQ-1e, AC-1e.4) ----------
#
# The widened `## Tasks` table is ONE schedule covering Steps 3-9, so "pending with every
# dependency landed" stopped being the whole question the moment the step column arrived.
# A Step-6 review row whose dependencies happen to be landed is ready in the dependency
# sense and is still not this step's work; filling it would send a critic against code the
# Verify gate has not passed. `units_ready <plan> <step>` takes the step, and the step is
# the plan's own `current:`.
sp_plan_at_step() {  # <repo> <current> <row>... -> the plan path
  local repo="$1" current="$2"; shift 2
  local f="$repo/.bionic/docs/plans/epic-99-fixture/wave-01-fixture.plan.md" row
  mkdir -p "$(dirname "$f")"
  {
    printf -- '---\ngoverning-skill: superpowers:writing-plans\n'
    printf 'parallel-budget: writers=8 suites=2 worktrees=8 test_jobs=8 source=probe\n'
    printf -- '---\n\n# fixture plan\n\n## SDLC State\n\ncurrent: %s\n\n' "$current"
    printf -- '- Step %s: in progress\n\n' "$current"
    printf '## Tasks\n\n'
    printf '%s' "$SP_TASKS_HEADER"
    for row in "$@"; do printf '%s\n' "$row"; done
  } > "$f"
  touch "$f"
  printf '%s' "$f"
}

# 12k1 — at current: 5, a ready Step-5 row and a ready Step-6 row. Only the Step-5 id is
# named. Both rows are `pending` and both have every dependency `landed`, so the OLD
# reader — which had no step to ask about — would have named both.
R12K1="$(make_repo s12-step-scoped)"; new_roster "$R12K1"
sp_plan_at_step "$R12K1" 5 \
  "| T1 | 4 | build | the build that landed | implementor | — | 15m | REQ-x | a.sh | landed |" \
  "| T2 | 5 | verify | this step's work | auditor | T1 | 15m | REQ-x | b.sh | pending |" \
  "| T3 | 6 | review | the NEXT step's work | critic | T1 | 15m | REQ-x | c.sh | pending |" > /dev/null
poke_pressure "$R12K1" 8192 1.0 tick
expect_contains "at current: 5 the ready Step-5 task is filled" "poker: FILL T2" "$OUT"
expect_absent "…and the ready Step-6 task is not" "T3" "$(printf '%s\n' "$OUT" | /usr/bin/grep '^poker: FILL')"

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

# 12k3 — the same table at current: 6, where nothing is ready: the tick says so, naming
# the step it asked about rather than reporting an empty table.
R12K3="$(make_repo s12-step-none)"; new_roster "$R12K3"
sp_plan_at_step "$R12K3" 6 \
  "| T1 | 4 | build | landed long ago | implementor | — | 15m | REQ-x | a.sh | landed |" \
  "| T2 | 5 | verify | pending, but not at this step | auditor | T1 | 15m | REQ-x | b.sh | pending |" > /dev/null
poke_pressure "$R12K3" 8192 1.0 tick
expect_contains "a step with no ready row says which step it asked about" \
  "no pending step-6 task has all its dependencies landed" "$OUT"

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
    launched_at="$(iso_ago 600)"
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
poke "$R18C" tick
expect_contains "an unbound session says which resolution it used" \
  "poker: run resolved by newest-plan fallback (session unbound) — $(real_path_of "$P18C")" "$OUT"
expect_contains "…and decides exactly what it decided before this wave" "decision=QUIET" "$OUT"
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
  launched_at="$(iso_ago 60)"
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

# ---------- 20b: the paired positive — a MET marker DOES close it ----------
R20B="$(s20_repo s20-met-marker)"
swept_marker "$R20B" suite-writer MET
s19_answer fresh "suite-writer:running"
poke_pressure "$R20B" 100 1.0 tick
expect_contains "…while a MET marker closes it, and the kill floor names no one (20a discriminates)" \
  "$S20_NONE" "$OUT"
expect_absent "…and never the swept writer's address" "suite-writer@" "$OUT"

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
    printf '## SDLC State\n\ncurrent: %s\n\n- Step %s: in progress\n\n' "$cur" "$cur"
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
  cadence="10 minutes"
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
  launched_at="$(iso_ago 600)"
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
  launched_at="$(iso_ago 600)"
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
    printf '## SDLC State\n\ncurrent: %s\n\n- %s: in progress\n\n' "$cur" "$cur"
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
s31_task_plan "$R31A" T1 >/dev/null
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
s31_stop "$R31A" "$S31_TR"
expect_eq "31b the turn is refused — the ledger is live and two rows are ready" \
  "block" "$(s31_decision)"
expect_contains "31b2 …naming T2, the first ready row" "T2" "$(s31_reason)"
expect_contains "31b3 …and T3, the second — named, not counted" "T3" "$(s31_reason)"
expect_contains "31b4 …and saying what answers it" "fill-declined:" "$(s31_reason)"

# ---------- 31c: the same turn, with the rows dispatched, ends in silence ----------
#
# The discharge the tick-printed duty already had, on the ids this arm computed itself: an
# `Agent` tool_use naming each row answers for it.
R31C="$(make_repo s29-task-dispatched)"; new_roster "$R31C"
s31_task_plan "$R31C" T1 >/dev/null
add_row "$R31C" name=T1 deliverable=t1.md duration="4 hours" launched_at="$(iso_ago 60)"
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
  deliverable="$R33A/.bionic/docs/record/swept.md" duration="1 hour" launched_at="$(iso_ago 600)"
add_row "$R33A" name=plain-row status=identified agent_id=aplain00000000000000000 \
  deliverable="$R33A/.bionic/docs/record/plain.md" duration="1 hour" launched_at="$(iso_ago 600)"
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
  deliverable="$R33B/.bionic/docs/record/swept.md" duration="1 hour" launched_at="$(iso_ago 600)"
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
  duration="1 hour" launched_at="$(iso_ago 600)"
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

# ---------- 33e: the reverse — this session's file stale, so the row IS quiet ----------
R33E="$(s33_adopted adopt-reverse)"
: > "$S33_PRED_TX"; : > "$S33_OWN_TX"
poke "$R33E" adopt
touch "$S33_PRED_TX"
backdate "$S33_OWN_TX" 5400
s33_answer fresh "w1:running"
poke "$R33E" tick
expect_contains "33e the same row with THIS session's transcript 5400 s old takes NOTIFY" \
  "decision=NOTIFY" "$OUT"
expect_contains "33e2 …naming this session's transcript as the channel it read" \
  "$S33_OWN_TX" "$OUT"

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

unset CLAUDE_CONFIG_DIR

finish
