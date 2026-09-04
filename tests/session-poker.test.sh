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

# Overridable exactly as tests/session-sweeper.test.sh offers, for RED evidence against a
# mutated copy without ever touching the shipped file:
#   W2_POKER_UNDER_TEST=/tmp/mutant.sh bash tests/session-poker.test.sh
POKER="${W2_POKER_UNDER_TEST:-${BIONIC_HOOKS_DIR}/session-poker.sh}"
TMPROOT="$(mktemp -d)"
PASS=0; FAIL=0; TOTAL=0

# THE LOADER'S REGISTRY LANE, POINTED AT NOTHING (bionic 1.4.0). The poker now finds its
# library through the shared loader idiom, whose candidates (2) and (3) read the CLI's
# plugin registry under `$BIONIC_PLUGINS_DIR` (default `$HOME/.claude/plugins`). Every
# invocation in this suite runs the shipped file, whose sibling `scripts/lib` answers at
# candidate (1) — so a run that ever reached the registry would be a run that failed to
# find the library beside the script, and pointing the knob at an empty directory turns
# that into a visible failure instead of a silent read of this machine's real install.
export BIONIC_PLUGINS_DIR="$TMPROOT/no-plugins"
mkdir -p "$BIONIC_PLUGINS_DIR"

cleanup() { chmod -R u+rwX "$TMPROOT" 2>/dev/null; rm -rf "$TMPROOT"; }
trap cleanup EXIT

SID="8a41c2e0-9b71-4f3a-8d6e-2c19f7b0e5aa"

# ---------- assertion helpers ----------

ok()  { TOTAL=$((TOTAL+1)); PASS=$((PASS+1)); printf 'PASS: %s\n' "$1"; }
bad() { TOTAL=$((TOTAL+1)); FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1"
        [ $# -gt 1 ] && printf '      %s\n' "$2"; return 0; }

expect_eq()       { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected [$2] got [$3]"; fi; }
expect_contains() { case "$3" in *"$2"*) ok "$1" ;; *) bad "$1" "no [$2] in: $(printf '%s' "$3" | head -3)" ;; esac; }
expect_absent()   { case "$3" in *"$2"*) bad "$1" "unexpected [$2] in: $(printf '%s' "$3" | head -3)" ;; *) ok "$1" ;; esac; }
section()         { printf '\n=== %s ===\n' "$1"; }

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
  printf '# bionic session roster — schema roster-state/v1 — machine-local, safe to delete\n' \
    > "$(roster_of "$1")"
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
      *) printf 'mkrow: unknown key %s\n' "$kv" >&2; return 1 ;;
    esac
  done
  [ -n "$launched_at" ] || launched_at="$(iso_ago 60)"
  printf 'roster-state/v1|status=%s|session=%s|name=%s|agent_id=%s|launched_at=%s|subagent_type=%s|model=opus|deliverable=%s|source=%s|duration=%s|progress=%s|claims=%s|cadence=%s|absent=|waiver=%s|tool_use_id=%s' \
    "$status" "$session" "$name" "$agent_id" "$launched_at" "$subagent_type" "$deliverable" "$source" \
    "$duration" "$progress" "$claims" "$cadence" "$waiver" "$tool_use_id"
  [ "$plan_set" = yes ] && printf '|plan=%s' "$plan"
  printf '\n'
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
  [ -f "$f" ] || printf '# bionic session roster — schema roster-state/v1 — machine-local, safe to delete\n' > "$f"
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
  printf 'plan=%s\nengaged_at=%s\n' "$2" "$(iso_ago 600)" > "$(marker_of "$1" "${3:-$SID}")"
  chmod 600 "$(marker_of "$1" "${3:-$SID}")"
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
expect_eq "no config.yaml: the default (30m = 1800s) is used" "0" "$RC"
expect_eq "…printed as bare seconds" "1800" "$OUT"

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
# wall. Rather than retype 1800 in the gate — two copies of a constant that drift the first
# time either moves — the gate asks this verb.
#
# THE PROPERTY THAT MATTERS TO ITS CALLER is that the config cannot change the answer, so
# every arm below is driven ON TOP of a config the `interval` verb refuses or overrides.
poke "$R2" interval-default
expect_eq "interval-default answers 0 even though the live config is malformed" "0" "$RC"
expect_eq "…with this script's own default, in seconds (30m = 1800s)" "1800" "$OUT"

printf 'poker-interval: 5m\n' > "$R2/.bionic/config.yaml"
poke "$R2" interval-default
expect_eq "…and a perfectly VALID override does not move it either" "1800" "$OUT"
poke "$R2" interval
expect_eq "…while interval, on the same repo, still reads that override (5m = 300s)" "300" "$OUT"

# The gate's fallback is only worth having if it tracks the constant. Mutation-proof: move
# POKER_INTERVAL_DEFAULT on a copy and the verb has to move with it — a verb that printed a
# literal 1800 would answer 1800 here.
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
sed 's/^POKER_INTERVAL_DEFAULT="30m"$/POKER_INTERVAL_DEFAULT="7m"/' "$POKER" > "$POKER_MUT"
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
printf 'landing-swept/v1|at=%s|session=%s|name=overdue-swept|agent_id=a000|state=UNMET\n' \
  "$(iso_ago 1)" "$SID" >> "$(roster_of "$R3SW")"
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
expect_absent   "…never names the already-landed row" "already-landed" "$OUT"
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

R4="$(make_repo s4)"; new_roster "$R4"
rm -rf "$R4/.bionic/tmp"
mkdir -p "$TMPROOT/elsewhere-s4"
ln -s "$TMPROOT/elsewhere-s4" "$R4/.bionic/tmp"
poke "$R4" tick

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
# epic-17 W5 slice 4/4, spec AC-6; design ledger D-C mechanics (2) and (3).
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
  bad "arm writes the session-keyed stamp beside the roster" "no file at $(stamp_of "$R6")"
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
  bad "…and it stamped anyway: liveness is firings landing, not decisions succeeding" \
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
  bad "…and writes no stamp: a session-keyed file needs a session key" \
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
  bad "a tick refreshes the stamp it found stale" "age is still ${S6_AGE}s"
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
    bad "arming from a worktree cwd stamps the MAIN repository's .bionic/tmp" \
        "not at $(stamp_of "$R6E"); worktree has: $(ls "$R6EWT/.bionic/tmp" 2>/dev/null)"
  fi
  ( cd "$R6E" && git worktree remove --force "$R6EWT" ) >/dev/null 2>&1
else
  ok "arming from a worktree cwd stamps the MAIN repository's .bionic/tmp (skipped: no worktree)"
fi

# ============================================================
# Section 7 — THE BLIND-WALL DETECTOR, RETIRED (bionic 1.4.0, slice ADOPT, spec AC-7)
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
add_row_to "$R8" "$ADOPT_A" name=running-one status=identified agent_id="$ID_RUNNING" \
  subagent_type=bionic:implementor duration="45 minutes" cadence="10 minutes" \
  deliverable="$R8/.bionic/docs/record/running-one.md" \
  progress="$R8/.bionic/tmp/progress-running.md"
add_row_to "$R8" "$ADOPT_A" name=silent-one status=identified agent_id="$ID_SILENT" \
  subagent_type=bionic:implementor duration="45 minutes" cadence="10 minutes" \
  deliverable="$R8/.bionic/docs/record/silent-one.md" \
  progress="$R8/.bionic/tmp/progress-silent.md"
add_row_to "$R8" "$ADOPT_A" name=closed-one status=identified agent_id="$ID_CLOSED" \
  subagent_type=bionic:implementor duration="45 minutes" cadence="10 minutes" \
  deliverable="$R8/.bionic/docs/record/closed-one.md"
# The terminal row: hooks/landing-gate.sh's own marker, the only thing that closes a row
# without an ack. Written by hand here for the same reason the ack above is NOT — this
# marker's writer is a Stop hook with a whole payload contract, and the shape is one line.
printf 'landing-swept/v1|at=%s|session=%s|name=closed-one|agent_id=%s|state=MET\n' \
  "$(iso_ago 300)" "$ADOPT_A" "$ID_CLOSED" >> "$(roster_of "$R8" "$ADOPT_A")"

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
expect_contains "the message address is a SendMessage by id" "SendMessage to:$ID_LANDED" "$OUT"
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

# ---------- 8c: the report tail, extracted from the transcript ----------
expect_contains "the landed agent's report tail is printed" "ADOPT-FIXTURE-REPORT-TAIL" "$OUT"
expect_absent "…the LAST long block, not an earlier one" "EARLIER-LONG-BLOCK" "$OUT"
expect_absent "…and not a short sign-off that followed it" "SHORT-SIGNOFF-MARKER" "$OUT"
expect_contains "an agent with no transcript on disk says so" "transcript_present=no" "$OUT"

# ---------- 8d: what adopt must NOT do ----------
expect_absent "this session's own rows are never adopted" "mine-current" "$OUT"
expect_absent "a row already swept MET is closed, not adopted" "closed-one" "$OUT"
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
poke "$R8" adopt
_dup_after="$(grep -c -F "|name=landed-one|" "$OWN_ROSTER")"
expect_eq "a second adopt appends no second row for the same agent" "$_dup_before" "$_dup_after"

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
# THE WINDOW is `PATROL_STALE_MULTIPLIER × cadence`, read from payload/scripts/lib/patrol.sh
# rather than from an inline `* 2` (spec AC-22: one constant, three readers). The mutation
# at the end of this block is what proves the reader is the constant.
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

# THE THRESHOLD IS THE LIBRARY'S CONSTANT, NOT A LITERAL 2 — proven by mutation, the same
# way §2 proves the interval default is read from POKER_INTERVAL_DEFAULT. A row whose only
# fresh-ish input sits BETWEEN one cadence and two is RUNNING while the multiplier is 2 and
# SILENT the moment it is 1, so a poker carrying its own `* 2` answers RUNNING on both runs.
# The doctored tree is the shape the plugin ships (hooks/ beside scripts/lib) and its library
# is a COPY, because this is the one fixture that must not read the shipped constant.
MULT_MUT_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/poker-mult-mut.XXXXXX")"
mkdir -p "$MULT_MUT_ROOT/hooks" "$MULT_MUT_ROOT/scripts"
cp -R "$(cd "$(dirname "$POKER")/../payload/scripts/lib" && pwd -P)" "$MULT_MUT_ROOT/scripts/lib"
sed -i.bak 's/^export PATROL_STALE_MULTIPLIER=2$/export PATROL_STALE_MULTIPLIER=1/' \
  "$MULT_MUT_ROOT/scripts/lib/patrol.sh"
cp "$POKER" "$MULT_MUT_ROOT/hooks/session-poker.sh"
if grep -qF 'export PATROL_STALE_MULTIPLIER=1' "$MULT_MUT_ROOT/scripts/lib/patrol.sh"; then
  ok "8j meta: the doctored multiplier landed (the sed anchor still matches)"
else
  bad "8j meta: the doctored multiplier did NOT land — the pair below proves nothing"
fi

R8M="$(make_repo s8-multiplier)"; new_roster "$R8M"
mkdir -p "$R8M/.bionic/docs/record"
add_row_to "$R8M" "$ADOPT_A" name=between status=identified \
  agent_id=abetween-one-bbbbbbbbbbbbbbbb subagent_type=bionic:implementor \
  duration="45 minutes" cadence="10 minutes" \
  deliverable="$R8M/.bionic/docs/record/between.md" \
  progress="$R8M/.bionic/tmp/progress-between.md"
printf 'progress\n' > "$R8M/.bionic/tmp/progress-between.md"
backdate "$R8M/.bionic/tmp/progress-between.md" 900   # > one cadence, < two

poke "$R8M" adopt --report-only
expect_contains "at 1.5x the cadence the shipped multiplier (2) still reads RUNNING" \
  "name=between|verdict=RUNNING" "$OUT"
OUT="$( cd "$R8M" && env CLAUDE_CODE_SESSION_ID="$SID" \
        bash "$MULT_MUT_ROOT/hooks/session-poker.sh" adopt --report-only 2>&1 )"
expect_contains "…and the SAME row reads SILENT against a library whose multiplier is 1" \
  "name=between|verdict=SILENT" "$OUT"

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
# one slice, the roster went quiet for the minutes it took to brief the next, and the tick
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
section "Section 11: pressure — HOLD, NARROW, EMERGENCY (AC-30, S7)"
# ============================================================
#
# WHAT THESE CASES OWN. The tick reads `resources_pressure` before it considers a single
# fill, because filling a machine that is already starving is the one scheduling mistake
# that costs WORK rather than time: the measured failure is a kernel SIGKILL, seven
# concurrent suites on an 8 GB machine driving free memory to ~188 MB and a suite dying
# mid-run (tests/run.sh:63-68).
#
# CLOCK AND MACHINE DISCIPLINE, the same house rule the rest of this suite keeps: nothing
# here waits for the machine to get into trouble, and nothing reads this machine at all.
# `resources_pressure` takes both of its readings through `BIONIC_PROBE_FREE_MB` /
# `BIONIC_PROBE_LOAD_1M` (lib/resources.sh's own seams, exercised the same way by
# tests/resources.test.sh), so every threshold below is fixture DATA.

# A plan carrying BOTH halves the scheduler reads: the frontmatter `parallel-budget:` line
# and the machine-readable slice table. Written as one builder because a fixture that
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
    printf '## Slices (machine-readable)\n\n'
    printf '| id | deps | complexity | status |\n|---|---|---|---|\n'
    local row
    for row in "$@"; do printf '%s\n' "$row"; done
  } > "$f"
  touch "$f"
  printf '%s' "$f"
}

# The poker under an injected pressure reading. The two knobs are exported for exactly one
# invocation and unset afterwards, so no case can leak a reading into the next.
poke_pressure() {  # <repo> <free_mb> <load_1m> <args...>
  local repo="$1" free="$2" load="$3"; shift 3
  BIONIC_PROBE_FREE_MB="$free" BIONIC_PROBE_LOAD_1M="$load" poke "$repo" "$@"
}

# ---------- 11a: a HOLD prints its measurement and fills nothing ----------
#
# The fixture has ready work AND a gap, so a tick that filled would fill. That is the whole
# discriminator: "no FILL under pressure" is only a claim if a FILL was available.
R11A="$(make_repo s11-hold)"; new_roster "$R11A"
wave_plan "$R11A" "writers=4 suites=2 worktrees=8 test_jobs=8 source=probe" \
  "| DONE | — | standard | landed |" \
  "| NEXT | DONE | complex | pending |"
poke_pressure "$R11A" 512 1.0 tick
expect_eq "a tick under memory pressure still exits 0 — HOLD is a decision, not a failure" \
  "0" "$RC"
expect_contains "…and prints HOLD with the free-memory reading" "poker: HOLD free_mb=512" "$OUT"
expect_contains "…and the load reading beside it" "load_1m=1.0" "$OUT"
expect_contains "…saying plainly that nothing is being filled" "no fills" "$OUT"
expect_absent "…and fills nothing, though a ready slice and a gap both exist" "poker: FILL" "$OUT"

# The paired positive: the SAME repo, the SAME plan, with the machine reading healthy.
# Without it, 11a passes on a tick that can never fill anything.
poke_pressure "$R11A" 8192 1.0 tick
expect_contains "the same fixture with memory to spare DOES fill (11a discriminates)" \
  "poker: FILL NEXT" "$OUT"
expect_absent "…and prints no HOLD" "poker: HOLD" "$OUT"

# ---------- 11b: NARROW on the SECOND consecutive hold, not the first ----------
#
# One hold is a burst — a suite starting, a build finishing — and halving the fleet's width
# off a burst is a wave that runs at half speed for the rest of the day. The counter is a
# sibling of the Patrol stamp, session-scoped, and it is what makes "sustained" a fact about
# two firings rather than an adjective.
R11B="$(make_repo s11-narrow)"; new_roster "$R11B"
wave_plan "$R11B" "writers=4 suites=2 worktrees=8 test_jobs=18 source=probe" \
  "| A | — | standard | landed |"
poke_pressure "$R11B" 512 1.0 tick
expect_contains "the first hold prints HOLD" "poker: HOLD" "$OUT"
expect_absent "…and NOT NARROW: one hold is a burst" "poker: NARROW" "$OUT"
poke_pressure "$R11B" 512 1.0 tick
expect_contains "the second consecutive hold prints NARROW" "poker: NARROW test_jobs=9" "$OUT"
expect_contains "…alongside the HOLD it is narrowing from" "poker: HOLD" "$OUT"

# The counter CLEARS on a healthy tick, so "two consecutive" means consecutive. Without
# this, NARROW is inevitable on any wave long enough to see two holds an hour apart.
poke_pressure "$R11B" 8192 1.0 tick
expect_absent "a healthy tick prints no NARROW" "poker: NARROW" "$OUT"
poke_pressure "$R11B" 512 1.0 tick
expect_contains "…and the hold after it is a FIRST hold again" "poker: HOLD" "$OUT"
expect_absent "…so NARROW does not fire (the counter cleared)" "poker: NARROW" "$OUT"

# The halving reads the plan's own `test_jobs`, never a constant of its own.
R11C="$(make_repo s11-narrow-half)"; new_roster "$R11C"
wave_plan "$R11C" "writers=4 suites=2 worktrees=8 test_jobs=6 source=probe" \
  "| A | — | standard | landed |"
poke_pressure "$R11C" 512 1.0 tick
poke_pressure "$R11C" 512 1.0 tick
expect_contains "NARROW halves the plan's OWN test_jobs (6 -> 3), never a constant" \
  "poker: NARROW test_jobs=3" "$OUT"

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
  "| A | — | standard | landed |" \
  "| B | — | standard | pending |"
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

# A roster with no suite-claiming row says so rather than naming a writer at random: the
# pressure is real and it is not this session's to relieve.
R11E="$(make_repo s11-emergency-noclaim)"; new_roster "$R11E"
wave_plan "$R11E" "writers=8 suites=2 worktrees=8 test_jobs=8 source=probe" \
  "| A | — | standard | landed |"
add_row "$R11E" status=intended name=quiet-writer deliverable=a.md duration="4 hours" \
  launched_at="$(iso_ago 60)"
poke_pressure "$R11E" 100 1.0 tick
expect_contains "an EMERGENCY with no suite-running writer names no one" \
  "no suite-running writer on this roster to stop" "$OUT"

# ---------- 11f: an unreadable reading is ZERO FREE MEMORY, and that is the kill floor ----
#
# lib/resources.sh answers a SAFE fact rather than an empty field when it cannot read one
# ("A probe that cannot read a fact answers a SAFE fact, never an empty field"), so a
# garbage `free_mb` reads as 0 — below the emergency floor. This case pins the direction
# that fall takes rather than assuming it: a broken probe stops the wave from GROWING, it
# never silently widens it, and the tick still exits 0 because EMERGENCY is a decision.
R11F="$(make_repo s11-probe-junk)"; new_roster "$R11F"
wave_plan "$R11F" "writers=4 suites=2 worktrees=8 test_jobs=8 source=probe" \
  "| A | — | standard | pending |"
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
# this session's roster; ready = the slice table's `pending` rows whose every dependency is
# `landed`. The tick prints min(gap, |ready|) ids in TABLE ORDER — the plan's own dependency
# ordering, maintained by the orchestrator, never an ordering this hook invents.

# ---------- 12a: three ready, gap two -> exactly two, in table order ----------
R12A="$(make_repo s12-fill-two)"; new_roster "$R12A"
wave_plan "$R12A" "writers=2 suites=2 worktrees=8 test_jobs=8 source=probe" \
  "| BASE | — | complex | landed |" \
  "| ONE | BASE | complex | pending |" \
  "| TWO | BASE | standard | pending |" \
  "| THREE | — | standard | pending |"
poke_pressure "$R12A" 8192 1.0 tick
expect_eq "a filling tick exits 0" "0" "$RC"
expect_contains "three ready and a gap of two fills exactly two, in table order" \
  "poker: FILL ONE TWO" "$OUT"
expect_absent "…and does not reach the third" "THREE" "$OUT"

# ---------- 12b: the gap closes as rows open ----------
#
# The same plan, one open row on the roster: writers=2 minus one open row is a gap of one.
R12B="$(make_repo s12-fill-gap-one)"; new_roster "$R12B"
wave_plan "$R12B" "writers=2 suites=2 worktrees=8 test_jobs=8 source=probe" \
  "| BASE | — | complex | landed |" \
  "| ONE | BASE | complex | pending |" \
  "| TWO | BASE | standard | pending |"
add_row "$R12B" name=live-writer deliverable=a.md duration="4 hours" launched_at="$(iso_ago 60)"
poke_pressure "$R12B" 8192 1.0 tick
expect_contains "one open row against writers=2 leaves a gap of one" "poker: FILL ONE" "$OUT"
expect_absent "…and the second ready slice waits" "TWO" "$OUT"

# ---------- 12c: gap zero -> no FILL, and the reason is the budget ----------
R12C="$(make_repo s12-fill-full)"; new_roster "$R12C"
wave_plan "$R12C" "writers=1 suites=1 worktrees=8 test_jobs=8 source=probe" \
  "| ONE | — | complex | pending |"
add_row "$R12C" name=live-writer deliverable=a.md duration="4 hours" launched_at="$(iso_ago 60)"
poke_pressure "$R12C" 8192 1.0 tick
expect_absent "a full budget fills nothing" "poker: FILL" "$OUT"
expect_contains "…and says which number closed the gap" "writers=1 and 1 open row(s): the budget is full" "$OUT"

# ---------- 12d: no parallel-budget line -> inert, and it says why ----------
#
# Every plan written before this wave, and every project that never ran Step 0's probe, has
# no such line. A budget is a ceiling a run OPTS INTO, so the absence is inert rather than
# an error — but a scheduler that went silent about it would be indistinguishable from one
# that was broken.
R12D="$(make_repo s12-no-budget)"; new_roster "$R12D"
wave_plan "$R12D" "-" \
  "| ONE | — | complex | pending |"
poke_pressure "$R12D" 8192 1.0 tick
expect_eq "a plan with no parallel-budget line still ticks cleanly (exit 0)" "0" "$RC"
expect_absent "…and fills nothing" "poker: FILL" "$OUT"
expect_contains "…naming the missing field as the reason" "no readable parallel-budget: writers field" "$OUT"

# ---------- 12e: a pending slice with an unlanded dependency is not ready ----------
R12E="$(make_repo s12-unlanded-dep)"; new_roster "$R12E"
wave_plan "$R12E" "writers=8 suites=2 worktrees=8 test_jobs=8 source=probe" \
  "| BASE | — | complex | pending |" \
  "| DEPENDENT | BASE | complex | pending |" \
  "| FREE | — | standard | pending |"
poke_pressure "$R12E" 8192 1.0 tick
expect_contains "a pending slice with an unlanded dep is held back" "poker: FILL BASE FREE" "$OUT"
expect_absent "…and DEPENDENT is not named" "DEPENDENT" "$OUT"

# Several deps, one of them unlanded: ALL of them must be landed, not any.
R12F="$(make_repo s12-multi-dep)"; new_roster "$R12F"
wave_plan "$R12F" "writers=8 suites=2 worktrees=8 test_jobs=8 source=probe" \
  "| A | — | complex | landed |" \
  "| B | — | complex | pending |" \
  "| C | A,B | complex | pending |"
poke_pressure "$R12F" 8192 1.0 tick
expect_contains "a slice whose deps are landed AND pending is not ready" "poker: FILL B" "$OUT"
expect_absent "…so C waits for every one of them" " C" "$OUT"

# A dependency the table does not carry at all is not confirmable, and an unconfirmable
# dependency holds its slice back — a slice held costs a batch, a slice dispatched onto an
# unlanded dependency costs the writer's whole run.
R12G="$(make_repo s12-unknown-dep)"; new_roster "$R12G"
wave_plan "$R12G" "writers=8 suites=2 worktrees=8 test_jobs=8 source=probe" \
  "| ORPHAN | NOT-IN-THIS-TABLE | complex | pending |" \
  "| FINE | — | standard | pending |"
poke_pressure "$R12G" 8192 1.0 tick
expect_contains "an unknown dependency holds its slice back" "poker: FILL FINE" "$OUT"
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
  printf '## Slices\n\n'
  printf '| status | owner | id | complexity | deps |\n|---|---|---|---|---|\n'
  printf '| landed | ada | BASE | complex | — |\n'
  printf '| pending | grace | LATER | standard | BASE |\n'
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
  printf 'The slice table looks like this:\n\n'
  printf '```\n| id | deps | complexity | status |\n|---|---|---|---|\n'
  printf '| EXAMPLE | — | complex | pending |\n```\n'
} > "$f12i"
touch "$f12i"
poke_pressure "$R12I" 8192 1.0 tick
expect_absent "a fenced slice table is documentation, and fills nothing" "poker: FILL" "$OUT"
expect_contains "…and the tick says the table gave it nothing ready" \
  "no pending slice has all its dependencies landed" "$OUT"

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
  printf '## Slices\n\n| id | deps | complexity | status |\n|---|---|---|---|\n'
  printf '| LEFTOVER | — | complex | pending |\n'
} > "$f12j"
touch "$f12j"
armed_ago "$R12J" 7200
touch "$f12j"
poke_pressure "$R12J" 8192 1.0 tick
expect_contains "a delivered run DISARMs" "decision=DISARM" "$OUT"
expect_absent "…and is never filled" "poker: FILL" "$OUT"

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
  bad "…and no stamp, no .bionic/tmp manufactured under the wrong root" \
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
echo ""
echo "=== Section 14: the LEASE OVERRUN — a worktree outliving its row (AC-28) ==="
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

# --- a discharged row whose tree still stands -> one NOTIFY line naming both ---
# No delivered plan, so DISARM cannot fire and the tick reaches its decision the long way.
R14="$(make_repo s14-overrun)"; new_roster "$R14"
mkdir -p "$R14/.worktrees/foo" "$R14/.bionic/docs/record"
add_row "$R14" name=W-FOO deliverable="$R14/.bionic/docs/record/w-foo.md" duration="4 hours"
printf 'the report\n' > "$R14/.bionic/docs/record/w-foo.md"   # the fact that discharges it
poke "$R14" tick
# The PHYSICAL path, because the tick resolves its root with `pwd -P` and the temporary
# directory this suite builds in is reached through a symlink on macOS.
R14P="$(cd "$R14" && pwd -P)"
expect_contains "a discharged row whose tree still stands is one lease-overrun line" \
  "NOTIFY lease-overrun $R14P/.worktrees/foo row=W-FOO" "$OUT"
expect_eq "…and the tick takes the NOTIFY band (exit 1)" "1" "$RC"
expect_contains "…with a decision line a machine can read" "decision=NOTIFY" "$OUT"
expect_contains "…naming the row the lease was bound to" "W-FOO" "$OUT"
expect_absent "…never QUIET on the same tick" "decision=QUIET" "$OUT"
expect_eq "…and the tree is not removed: the tick lands nothing" "1" \
  "$(ls "$R14/.worktrees" | grep -c .)"

# --- THE DISCRIMINATOR. A tree whose row is NOT discharged is a live lease, and silent.
# Without this the case above passes over a tick that reports every tree it can see.
R14B="$(make_repo s14-live-lease)"; new_roster "$R14B"
mkdir -p "$R14B/.worktrees/bar"
add_row "$R14B" name=W-BAR deliverable="$R14B/.bionic/docs/record/w-bar.md" duration="4 hours"
poke "$R14B" tick
expect_absent "an UNMET row's tree is a live lease, not an overrun" "lease-overrun" "$OUT"
expect_eq "…and the tick is QUIET (exit 0)" "0" "$RC"

# --- the other half of the discriminator: a discharged row whose tree is already gone.
# That lease ended correctly and has nothing to report.
R14C="$(make_repo s14-landed)"; new_roster "$R14C"
mkdir -p "$R14C/.worktrees" "$R14C/.bionic/docs/record"
add_row "$R14C" name=W-GONE deliverable="$R14C/.bionic/docs/record/w-gone.md" duration="4 hours"
printf 'the report\n' > "$R14C/.bionic/docs/record/w-gone.md"
poke "$R14C" tick
expect_absent "a discharged row whose tree is gone reports nothing" "lease-overrun" "$OUT"

# --- a project with no .worktrees at all is silent, and cheap ---
R14D="$(make_repo s14-no-trees)"; new_roster "$R14D"
mkdir -p "$R14D/.bionic/docs/record"
add_row "$R14D" name=W-NONE deliverable="$R14D/.bionic/docs/record/w-none.md" duration="4 hours"
printf 'the report\n' > "$R14D/.bionic/docs/record/w-none.md"
poke "$R14D" tick
expect_absent "no .worktrees directory, no walk and no line" "lease-overrun" "$OUT"

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
      bash "$(dirname "$POKER")/protect-main.sh" 2>&1 >/dev/null; echo "rc=$?")
expect_contains "AC-15 …so a wall still refuses after the disarm" "rc=2" "$R15D_PUSH"

# ...and the paired negative: remove the marker too and that same push passes.
unengage "$R15D"
R15D_PUSH2=$(jq -n --arg s "$SID" --arg c "$R15D" \
  '{session_id:$s, cwd:$c, hook_event_name:"PreToolUse", tool_name:"Bash",
    tool_input:{command:"git push --force origin main"}}' \
  | env CLAUDE_CODE_SESSION_ID="$SID" CLAUDE_PROJECT_DIR= \
      bash "$(dirname "$POKER")/protect-main.sh" 2>&1 >/dev/null; echo "rc=$?")
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
  "|plan=$A17A" "$(printf '%s\n' "$ROSTER17A" | grep "name=a-writer")"
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
  "|plan=$B17B" "$(printf '%s\n' "$ROSTER17B" | grep "name=b-writer")"
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
# and slice table — and a Patrol that stood its ground correctly while filling another run's
# slices would be worse than either failure alone. Two budgeted plans, one root: the bound
# one is filled from, and the newest one is not.
R18E="$(make_repo s18-scheduler)"; new_roster "$R18E"
poke "$R18E" arm
P18E_MINE="$(wave_plan_at "$R18E" 'epic-18/mine.plan.md' \
  "writers=4 suites=2 worktrees=8 test_jobs=8 source=probe" "| MINE-SLICE | — | standard | pending |")"
P18E_THEIRS="$(wave_plan_at "$R18E" 'epic-18/theirs.plan.md' \
  "writers=9 suites=2 worktrees=8 test_jobs=8 source=probe" "| THEIRS-SLICE | — | standard | pending |")"
bind_marker "$R18E" "$P18E_MINE"
# THE READING IS FIXTURE DATA, exactly as Section 11 makes it: a FILL assertion taken on
# whatever memory this machine happens to have free is an assertion that passes or fails on
# the weather. `poke_pressure` pins it healthy so the scheduler reaches the fill decision.
poke_pressure "$R18E" 8192 1.0 tick
expect_contains "the scheduler fills from the BOUND plan's slice table" "poker: FILL MINE-SLICE" "$OUT"
expect_absent   "…and never from the newest plan, which belongs to another run" \
  "THEIRS-SLICE" "$OUT"

# ============================================================
printf '\n──────────────────────────────────────────────\n'
printf 'session-poker: %d passed, %d failed, %d total\n' "$PASS" "$FAIL" "$TOTAL"
[ "$FAIL" -eq 0 ]
