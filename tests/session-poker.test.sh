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
# THE SUITE IS FOUR SHARDS (wave-30 T2; design-ledger Δ7, D8). It ran 968 s at width 4 as one
# file, so its sections are split by number across four suites the runner schedules apart:
# Sections 1–34 here, 35–55 in tests/session-poker-2.test.sh, 56–70 in -3 and §SEV to the end
# in -4, each in its original order. A section that builds a repository a later section reads
# travels with it. The sandbox, the pins, the fixture builders and every helper a later shard
# calls live in tests/session-poker.prelude.sh, which each shard sources after the framework
# and the POKER seam. This header is the whole suite's: the other three shards point here.
#
# Usage: bash tests/session-poker.test.sh   (and -2, -3, -4)

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/plan-fixture.sh"
. "$(dirname "$0")/lib/assert.sh"
. "$(dirname "$0")/lib/bound-marker.sh"
. "$(dirname "$0")/lib/roster-row.sh"
. "$(dirname "$0")/lib/swept-marker.sh"
. "$(dirname "$0")/lib/live-answer.sh"

# Overridable exactly as tests/session-sweeper.test.sh offers, for RED evidence against a
# mutated copy without ever touching the shipped file:
#   W2_POKER_UNDER_TEST=/tmp/mutant.sh bash tests/session-poker.test.sh
POKER="${W2_POKER_UNDER_TEST:-${BIONIC_HOOKS_DIR}/session-poker.sh}"
# The dispatcher loads its seven parts from poker/ beside it; a doctored copy carries that directory too.
POKER_PARTS="$(dirname "$POKER")/poker"
# Everything else every shard shares: tests/session-poker.prelude.sh.
. "$(dirname "$0")/session-poker.prelude.sh"

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

# HOISTED to tests/session-poker.prelude.sh: fake_config_dir — Sections 41 and 43–45 build config dirs with it.

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
finish
