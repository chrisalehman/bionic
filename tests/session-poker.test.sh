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

# ---------- the default: the Patrol library's one constant ----------
#
# A caller whose `interval` call refuses or cannot be made (the arming wall, the stop library, session start, doctor)
# falls back to lib/patrol.sh's PATROL_INTERVAL_DEFAULT, so the poker reads its own default from that constant too, or
# the two would drift. Mutation-proof: the poker beside a library whose constant is moved answers the moved value. The
# copy lives in a tree shaped as the plugin ships, its library and parts linked, so it reads the shipped functions.
POKER_MUT_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/poker-default-mut.XXXXXX")"
mkdir -p "$POKER_MUT_ROOT/hooks" "$POKER_MUT_ROOT/scripts/lib"
PM_LIB="$(cd "$(dirname "$POKER")/../payload/scripts/lib" && pwd -P)"
for PM_F in "$PM_LIB"/*; do ln -s "$PM_F" "$POKER_MUT_ROOT/scripts/lib/"; done
rm "$POKER_MUT_ROOT/scripts/lib/patrol.sh"
sed 's/^PATROL_INTERVAL_DEFAULT=1200$/PATROL_INTERVAL_DEFAULT=420/' "$PM_LIB/patrol.sh" > "$POKER_MUT_ROOT/scripts/lib/patrol.sh"
ln -s "$(cd "$(dirname "$POKER")/poker" && pwd -P)" "$POKER_MUT_ROOT/hooks/poker"
cp "$POKER" "$POKER_MUT_ROOT/hooks/session-poker.sh"
rm -f "$R2/.bionic/config.yaml"
OUT="$( cd "$R2" && CLAUDE_CODE_SESSION_ID="$SID" bash "$POKER_MUT_ROOT/hooks/session-poker.sh" interval 2>&1 )"; RC=$?
expect_eq "the poker's default is the library's constant: moved to 420 there, interval with no config prints 420" "0|420" "$RC|$OUT"

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
# closed — `stop_landing_gate` and `stop_guard` in payload/scripts/lib/stop.sh, and hooks/stop-orders.sh.
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
bound_ago "$R3E"
delivered_plan "$R3E"
poke "$R3E" tick
expect_eq "an empty roster ticks quietly (exit 0)" "0" "$RC"
expect_contains "…and decides DISARM" "decision=DISARM" "$OUT"
expect_contains "…open=0" "open=0" "$OUT"
expect_absent   "…never QUIET on the same tick" "decision=QUIET" "$OUT"
# The pair: the same delivery, older than this session's binding, is the previous run's.
R3P="$(make_repo s3-prior)"; new_roster "$R3P"; delivered_plan "$R3P"
backdate "$(find "$R3P/.bionic/docs/plans" -name '*.plan.md' | head -1)" 3600
poke "$R3P" tick
expect_contains "a delivery older than the session's binding is the previous run's: QUIET, never DISARM" "decision=QUIET" "$OUT"

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
R3C="$(make_repo s3-closed)"; new_roster "$R3C"; bound_ago "$R3C"; delivered_plan "$R3C"
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
R3AK="$(make_repo s3-all-acked)"; new_roster "$R3AK"; bound_ago "$R3AK"; delivered_plan "$R3AK"
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
R3AN="$(make_repo s3-ack-past-due)"; new_roster "$R3AN"; bound_ago "$R3AN"; delivered_plan "$R3AN"
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
expect_eq "an ABSENT roster on an engaged session is QUIET, nothing dispatched yet (exit 0)" "0" "$RC"
expect_contains "…and never DISARMs over a roster it never found" "decision=QUIET" "$OUT"

# THE NESTED TOPOLOGY: a git repo inside a plain workspace that holds the `.bionic` tree. The walk
# passes the repo and chooses the workspace, where the session engaged, so the tick reads that root.
R5C="$TMPROOT/s5-candidates"
mkdir -p "$R5C/.bionic/tmp"
engage "$R5C"
R5CN="$R5C/nested-repo"
mkdir -p "$R5CN"
( cd "$R5CN" && git init -q . ) >/dev/null 2>&1
poke "$R5CN" tick
expect_eq "the nested-repo topology reads the workspace's root: QUIET on an absent roster (exit 0)" "0|1" \
  "$RC|$(printf '%s\n' "$OUT" | grep -c 'QUIET — engaged, nothing dispatched yet')"


# ============================================================
section "Section 6: a keyless tick refuses and writes nothing"
# ============================================================
mtime_of() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null; }
R6C="$(make_repo s6-nokey)"
OUT="$( cd "$R6C" && env -u CLAUDE_CODE_SESSION_ID bash "$POKER" tick 2>&1 )"; RC=$?
expect_eq "a keyless tick refuses (exit 3)" "3" "$RC"
# The state directory holds the engagement marker before the tick runs: no other file may appear.
R6C_WROTE="$(ls "$R6C/.bionic/tmp/" 2>/dev/null | /usr/bin/grep -v "^engaged-$SID.state$" || true)"
if [ -n "$R6C_WROTE" ]; then
  no "…and writes nothing: a session-keyed file needs a session key" \
      "wrote: $R6C_WROTE"
else
  ok "…and writes nothing: a session-keyed file needs a session key"
fi

# HOISTED to tests/session-poker.prelude.sh: fake_config_dir — Sections 41 and 43–45 build config dirs with it.

# ============================================================
section "Section 7: window — the roster's own birth, read by the Patrol library"
# ============================================================
#
# lib/patrol.sh `patrol_window <repo> <sid>` dates THIS roster's own record of the session for doctor's counters: the
# roster's creation instant, else nothing. BIRTH, NEVER MTIME: the
# roster is append-only, so an mtime a day ahead must not move the answer. The mtime is advanced, never backdated: on
# APFS `touch -t` to an instant before a file's birth lowers `st_birthtime` with it, so a backdating probe would move
# the very quantity it holds still. The expected instant is recomputed here, never read through the code under test.
s7_win() { bash -c '. "$1"; patrol_window "$2" "$3"' _ "$(dirname "$POKER")/../payload/scripts/lib/patrol.sh" "$@" 2>/dev/null; }
s7_birth_iso() {  # <path> -> UTC ISO-8601 of the filesystem's own creation instant
  local b
  b="$(stat -f %B "$1" 2>/dev/null || stat -c %W "$1" 2>/dev/null)"
  case "${b:-0}" in ''|*[!0-9]*|0) return 1 ;; esac
  date -u -r "$b" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$b" +%Y-%m-%dT%H:%M:%SZ
}
R7B="$(make_repo s7-roster)"; new_roster "$R7B"
S7B_EXPECT="$(s7_birth_iso "$(roster_of "$R7B")" || true)"
if [ -z "$S7B_EXPECT" ]; then
  no "this filesystem records no file birth time — Section 7 cannot run" "stat %B/%W gave nothing for $(roster_of "$R7B")"
else
  expect_eq "the window of a present roster is its own creation instant, as UTC ISO-8601" "$S7B_EXPECT" "$(s7_win "$R7B" "$SID")"
  touch -t "$(date -v+1d +%Y%m%d%H%M.%S 2>/dev/null || date -d '+1 day' +%Y%m%d%H%M.%S)" "$(roster_of "$R7B")"
  expect_ne "the mtime really did move a day off the birth instant" "$S7B_EXPECT" \
    "$(date -u -r "$(mtime_of "$(roster_of "$R7B")")" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$(mtime_of "$(roster_of "$R7B")")" +%Y-%m-%dT%H:%M:%SZ)"
  expect_eq "…and the window does not move with it: the roster is append-only" "$S7B_EXPECT" "$(s7_win "$R7B" "$SID")"
  R7F="$(make_repo s7-nothing)"
  expect_eq "no roster: no window, and nothing written beside the engagement" "|" \
    "$(s7_win "$R7F" "$SID")|$(ls "$R7F/.bionic/tmp" 2>/dev/null | /usr/bin/grep -v "^engaged-$SID.state$")"
fi

# ============================================================
finish
