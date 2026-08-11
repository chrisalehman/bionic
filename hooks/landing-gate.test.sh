#!/bin/bash
# Tests for hooks/landing-gate.sh — THE LANDING GATE (epic-16 wave-01, slice 5).
#
# SubagentStop. Serves AC-5 (a planted unmet contract blocks once, naming the items) and
# AC-6 (waived / non-wave / phantom / error all pass untouched, fail-open pinned).
#
# Governing design: .bionic/docs/specs/epic-16-landing-contract/wave-01-landing-contract.spec.md
# §Design; slice 5 of .bionic/docs/plans/epic-16-landing-contract/wave-01-landing-contract.plan.md.
#
# HERMETIC. Every payload is crafted and piped straight into the gate; nothing here stops a
# real subagent, touches the live installed hooks, or depends on a live wave. Repos are
# throwaway `git init`s under a mktemp'd sandbox, and the roster/plan fixtures are written
# as files.
#
# THE SWEEPER IS REAL IN EVERY CASE THAT HAS ONE. The gate consumes
# `session-sweeper.sh verdict <name>` and never re-implements its predicate, so a stubbed
# verdict would leave exactly the seam this slice exists to close (rule: seam-blindness —
# a seam substituting the value-under-test leaves the production path unverified). The gate
# resolves the sweeper as its own SIBLING, which is what bootstrap's `hooks/*.sh` install
# produces, so Sections 4a/4b get their absent/erroring sweeper by running a COPY of the
# gate out of a directory holding a different sibling — no env override, no PATH seam.
#
# Usage: bash hooks/landing-gate.test.sh

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")" && pwd)"
GATE="$HOOKS_DIR/landing-gate.sh"

SANDBOX="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/landing-gate-test.XXXXXX")" && pwd)"
BG_PIDS=""
cleanup() {
  local p
  for p in $BG_PIDS; do kill -9 "$p" 2>/dev/null; done
  chmod -R u+rwX "$SANDBOX" 2>/dev/null
  rm -rf "$SANDBOX"
}
trap cleanup EXIT

PASS=0
FAIL=0
TOTAL=0

ok() { TOTAL=$((TOTAL + 1)); PASS=$((PASS + 1)); echo "PASS: $1"; }
no() { TOTAL=$((TOTAL + 1)); FAIL=$((FAIL + 1)); echo "FAIL: $1"; [ -n "${2:-}" ] && echo "      $2"; return 0; }

expect_status()   { if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "expected exit $2, got $3"; fi; }
expect_contains() { if printf '%s' "$3" | grep -qF -- "$2"; then ok "$1"; else no "$1" "missing [$2] in: $(printf '%s' "$3" | head -3)"; fi; }
expect_absent()   { if printf '%s' "$3" | grep -qF -- "$2"; then no "$1" "unexpectedly present: $2"; else ok "$1"; fi; }
expect_empty()    { if [ -z "$2" ]; then ok "$1"; else no "$1" "expected no output, got: $2"; fi; }
expect_eq()       { if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "expected [$2] got [$3]"; fi; }
section()         { printf '\n=== %s ===\n' "$1"; }

# ---------- fixtures ----------
#
# FIXTURE FIDELITY (declared per rule fixtures-can-pin-away-the-test).
#
#   * SubagentStop payload ENVELOPE — VERBATIM from
#     .bionic/docs/record/landing-wave-capture-probe.md §3-D, a live teammate stop captured
#     2026-08-08 (CLI 2.1.226): field for field, including `background_tasks[]` with its
#     task-id key and `status: running`, `session_crons`, `effort`, `agent_transcript_path`.
#     Only session_id / cwd / agent_type / stop_hook_active are varied per case, and each is
#     a field the gate reads.
#   * PHANTOM payload — VERBATIM shape from §4 (run 6): `agent_type` empty, a transcript-form
#     `agent_id` matching no teammate, and a `last_assistant_message` that reads as a
#     predicted next user prompt. Three of four SubagentStop events in each captured run were
#     this shape; the probe's own conclusion is that any consumer must filter them.
#   * roster rows — the roster-state/v1 field set and ORDER written by
#     hooks/dispatch-preflight.sh (the `ROW=` assignment, absent-deliverable-wall era),
#     copied from hooks/session-sweeper.test.sh's `mkrow`. This suite's subject reads the
#     roster only through the sweeper, which is the real one here.
#   * SYNTHESIZED and declared: session ids, agent ids, plan text, deliverable paths, the
#     marker process a STILL-LIVE row claims. None is a platform surface.

SID="3b51bef0-d7bd-447a-bc65-8916c4b25353"
SID_B="7c2d1a04-55e8-4f31-9a70-1b8c3d0e6f22"

payload() {  # <cwd> <session_id> <agent_type> <stop_hook_active> [hook_event_name]
  local cwd="$1" sid="$2" atype="$3" active="$4" event="${5:-SubagentStop}"
  cat <<JSON
{
  "session_id": "$sid",
  "transcript_path": "/tmp/transcripts/$sid.jsonl",
  "cwd": "$cwd",
  "prompt_id": "95b0701b-7814-42ca-a26f-58123e667f9a",
  "permission_mode": "bypassPermissions",
  "agent_id": "aprobemate-4da9be517e8f90bd",
  "agent_type": "$atype",
  "effort": { "level": "high" },
  "hook_event_name": "$event",
  "stop_hook_active": $active,
  "agent_transcript_path": "/tmp/transcripts/$sid/subagents/agent-aprobemate-4da9be517e8f90bd.jsonl",
  "last_assistant_message": "DONE\n\nRan the slice; report written.",
  "background_tasks": [
    {
      "id": "tooha5cgi",
      "type": "teammate",
      "status": "running",
      "description": "run the slice and report"
    }
  ],
  "session_crons": []
}
JSON
}

# §4's non-teammate stop: empty agent_type, transcript-form id, next-prompt text.
phantom_payload() {  # <cwd> <session_id>
  local cwd="$1" sid="$2"
  cat <<JSON
{
  "session_id": "$sid",
  "transcript_path": "/tmp/transcripts/$sid.jsonl",
  "cwd": "$cwd",
  "prompt_id": "95b0701b-7814-42ca-a26f-58123e667f9a",
  "permission_mode": "bypassPermissions",
  "agent_id": "ab4c8f6f7f6f4e68d",
  "agent_type": "",
  "effort": { "level": "high" },
  "hook_event_name": "SubagentStop",
  "stop_hook_active": false,
  "last_assistant_message": "check on probemate6",
  "background_tasks": [],
  "session_crons": []
}
JSON
}

iso_ago() {  # <seconds ago> -> UTC ISO-8601, the launched_at shape
  date -u -v-"$1"S +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || date -u -d "-$1 seconds" +%Y-%m-%dT%H:%M:%SZ
}

# roster-state/v1, field set and order per hooks/dispatch-preflight.sh's writer.
mkrow() {  # <key=value>...
  local status=confirmed session="$SID" name=agent agent_id=a000 launched_at=""
  local subagent_type=implementor model=opus deliverable="" duration="" progress=""
  local claims="" cadence="" waiver="" tool_use_id=toolu_x source=declared kv
  for kv in "$@"; do
    case "$kv" in
      source=*)      source="${kv#*=}" ;;
      status=*)      status="${kv#*=}" ;;
      session=*)     session="${kv#*=}" ;;
      name=*)        name="${kv#*=}" ;;
      agent_id=*)    agent_id="${kv#*=}" ;;
      launched_at=*) launched_at="${kv#*=}" ;;
      deliverable=*) deliverable="${kv#*=}" ;;
      duration=*)    duration="${kv#*=}" ;;
      progress=*)    progress="${kv#*=}" ;;
      claims=*)      claims="${kv#*=}" ;;
      cadence=*)     cadence="${kv#*=}" ;;
      waiver=*)      waiver="${kv#*=}" ;;
      tool_use_id=*) tool_use_id="${kv#*=}" ;;
      *) printf 'mkrow: unknown key %s\n' "$kv" >&2; return 1 ;;
    esac
  done
  [ -n "$launched_at" ] || launched_at="$(iso_ago 60)"
  printf 'roster-state/v1|status=%s|session=%s|name=%s|agent_id=%s|launched_at=%s|subagent_type=%s|model=%s|deliverable=%s|source=%s|duration=%s|progress=%s|claims=%s|cadence=%s|absent=|waiver=%s|tool_use_id=%s\n' \
    "$status" "$session" "$name" "$agent_id" "$launched_at" "$subagent_type" "$model" \
    "$deliverable" "$source" "$duration" "$progress" "$claims" "$cadence" "$waiver" "$tool_use_id"
}

roster_of() { printf '%s/.bionic/tmp/roster-%s.state' "$1" "${2:-$SID}"; }

new_roster() {  # <repo> [sid]
  printf '# bionic session roster — schema roster-state/v1 — machine-local, safe to delete\n' \
    > "$(roster_of "$1" "${2:-$SID}")"
}

add_row() {  # <repo> <key=value>...
  local repo="$1"; shift
  mkrow "$@" >> "$(roster_of "$repo" "$SID")"
}

# An ACTIVE wave: the fence-aware `## SDLC State` / `current:` marker the evidence gate,
# stop-guard and dispatch-preflight all read.
plan_active() {  # <repo>
  local d="$1/.bionic/docs/plans/epic-16-landing-contract"
  mkdir -p "$d"
  cat > "$d/wave-01-landing-contract.plan.md" <<'PLAN'
---
governing-skill: superpowers:writing-plans
sdlc-step: 4
canonical_sdlc_version: 13
---

# Wave 01 — landing contract

## SDLC State

integration-branch: main
current: 4
PLAN
}

# A plan whose ONLY `## SDLC State` section is inside a fence: documentation, invisible to
# the parser, so no wave is active. The trap this shape encodes is on the record in
# .claude/rules/hook-authoring.md.
plan_fenced_only() {  # <repo>
  local d="$1/.bionic/docs/plans/epic-16-landing-contract"
  mkdir -p "$d"
  cat > "$d/wave-01-landing-contract.plan.md" <<'PLAN'
---
governing-skill: superpowers:writing-plans
---

# How a plan documents its own format

```
## SDLC State

current: 4
```
PLAN
}

make_repo() {  # <label> -> repo path
  local r="$SANDBOX/$1"
  mkdir -p "$r/.bionic/tmp"
  ( cd "$r" && git init -q . 2>/dev/null )
  printf '%s' "$r"
}

# The standard fixture: an active wave, a roster, and nothing delivered.
make_wave_repo() {  # <label> -> repo path
  local r
  r="$(make_repo "$1")"
  plan_active "$r"
  new_roster "$r"
  printf '%s' "$r"
}

deliver() {  # <repo> <relative path> — a real artifact, written now (after launched_at)
  local p="$1/$2"
  mkdir -p "$(dirname "$p")"
  printf 'the report\n' > "$p"
}

# ---------- running the gate ----------
#
# Sets OUT_STDOUT / OUT_STDERR / RC. Bounded: a gate that hangs inside a SubagentStop hook
# is a defect, and a suite that hangs on it would wedge `bash tests/run.sh`.
run_gate() {  # <gate path> <payload json>
  local gate="$1" json="$2"
  printf '%s' "$json" > "$SANDBOX/payload.json"
  ( exec bash "$gate" < "$SANDBOX/payload.json" ) \
    > "$SANDBOX/gate.out" 2> "$SANDBOX/gate.err" &
  local pid=$!
  BG_PIDS="$BG_PIDS $pid"
  local waited=0
  while kill -0 "$pid" 2>/dev/null && [ "$waited" -lt 200 ]; do
    sleep 0.1; waited=$((waited + 1))
  done
  if kill -0 "$pid" 2>/dev/null; then
    kill -9 "$pid" 2>/dev/null
    RC=124
  else
    wait "$pid"; RC=$?
  fi
  OUT_STDOUT="$(cat "$SANDBOX/gate.out")"
  OUT_STDERR="$(cat "$SANDBOX/gate.err")"
}

REFUSAL_TAIL="Land the contract (write the named artifacts), or stop again to pass — this gate blocks once."

# ================================================================= Section 1
section "Section 1: the block — an unmet contract stops a stopping agent once"

R1="$(make_wave_repo r1)"
add_row "$R1" name=w1-s5 deliverable=.bionic/docs/record/never.md launched_at="$(iso_ago 600)"

run_gate "$GATE" "$(payload "$R1" "$SID" w1-s5 false)"
expect_status "1a: UNMET contract blocks the stop (exit 2)" "2" "$RC"
expect_contains "1a: the refusal opens with the contract verdict" \
  "LANDING CONTRACT UNMET" "$OUT_STDERR"
expect_contains "1a: …names the artifact that is not on disk" \
  "missing=.bionic/docs/record/never.md" "$OUT_STDERR"
expect_contains "1a: …and tells the agent how to pass" "$REFUSAL_TAIL" "$OUT_STDERR"
expect_empty "1a: the refusal goes to stderr, never stdout" "$OUT_STDOUT"

# The stop is blocked ONCE. Claude Code re-enters with stop_hook_active true; a gate that
# re-blocked there would wedge the agent in a loop it cannot leave.
run_gate "$GATE" "$(payload "$R1" "$SID" w1-s5 true)"
expect_status "1b: stop_hook_active true passes the same unmet contract" "0" "$RC"
expect_empty "1b: …silently on stdout" "$OUT_STDOUT"
expect_empty "1b: …and on stderr" "$OUT_STDERR"

# Landing the contract is the other way through.
deliver "$R1" .bionic/docs/record/never.md
run_gate "$GATE" "$(payload "$R1" "$SID" w1-s5 false)"
expect_status "1c: once the artifact is written the stop passes" "0" "$RC"
expect_empty "1c: …silently" "$OUT_STDERR"

# ================================================================= Section 2
section "Section 2: the phantom filter and the payload relevance hoist"

R2="$(make_wave_repo r2)"
add_row "$R2" name=w1-s5 deliverable=.bionic/docs/record/never.md launched_at="$(iso_ago 600)"

run_gate "$GATE" "$(phantom_payload "$R2" "$SID")"
expect_status "2a: a phantom stop (empty agent_type) passes" "0" "$RC"
expect_empty "2a: …silently" "$OUT_STDERR"

run_gate "$GATE" "$(payload "$R2" "$SID" w1-s5 false Stop)"
expect_status "2b: a Stop payload is none of this gate's business" "0" "$RC"

run_gate "$GATE" "$(payload "" "$SID" w1-s5 false)"
expect_status "2c: no cwd — the repo is unresolvable, pass" "0" "$RC"

run_gate "$GATE" "$(payload "$SANDBOX/not-a-repo" "$SID" w1-s5 false)"
expect_status "2d: a cwd outside any repo passes" "0" "$RC"

run_gate "$GATE" "$(payload "$R2" "" w1-s5 false)"
expect_status "2e: no session key — no roster to scope to, pass" "0" "$RC"

run_gate "$GATE" "$(payload "$R2" "$SID_B" w1-s5 false)"
expect_status "2f: another session's stop reads that session's (absent) roster, pass" "0" "$RC"

run_gate "$GATE" "not json at all"
expect_status "2g: an unparseable payload passes" "0" "$RC"

# ================================================================= Section 3
section "Section 3: the states the gate must never block"

R3="$(make_wave_repo r3)"
# FIXTURE FIDELITY (Step-6 review S-1): a genuine waiver row names NO artifact — the wall's
# waiver label reads "why this dispatch produces nothing durable". A row carrying a declared
# artifact AND a waiver is contradictory and is answered for in Section 7.
add_row "$R3" name=waived-row waiver="exploratory probe" launched_at="$(iso_ago 600)"
add_row "$R3" name=met-row deliverable=.bionic/docs/record/landed.md launched_at="$(iso_ago 600)"
deliver "$R3" .bionic/docs/record/landed.md

run_gate "$GATE" "$(payload "$R3" "$SID" waived-row false)"
expect_status "3a: a waived row passes" "0" "$RC"
expect_empty "3a: …silently" "$OUT_STDERR"

run_gate "$GATE" "$(payload "$R3" "$SID" met-row false)"
expect_status "3b: a met row passes" "0" "$RC"

run_gate "$GATE" "$(payload "$R3" "$SID" never-dispatched false)"
expect_status "3c: a name on no roster row passes" "0" "$RC"

R3B="$(make_repo r3b)"
plan_active "$R3B"
run_gate "$GATE" "$(payload "$R3B" "$SID" w1-s5 false)"
expect_status "3d: no roster file at all passes" "0" "$RC"

# STILL-LIVE: an agent visibly still working has not failed to land. The verdict verb owns
# that judgment; the gate must honour it rather than reading "not delivered" as a failure.
R3C="$(make_wave_repo r3c)"
MARKER="$SANDBOX/bionic-landing-gate-marker-91744.sh"
printf '#!/bin/bash\nsleep 60\n' > "$MARKER"
chmod +x "$MARKER"
"$MARKER" & MARKER_PID=$!
BG_PIDS="$BG_PIDS $MARKER_PID"
add_row "$R3C" name=live-row deliverable=.bionic/docs/record/never.md \
  claims="$MARKER" launched_at="$(iso_ago 600)"
run_gate "$GATE" "$(payload "$R3C" "$SID" live-row false)"
expect_status "3e: a STILL-LIVE row passes" "0" "$RC"
expect_empty "3e: …silently" "$OUT_STDERR"
kill -9 "$MARKER_PID" 2>/dev/null

# ================================================================= Section 4
section "Section 4: no active wave — nothing to hold anyone to"

R4="$(make_repo r4)"
new_roster "$R4"
add_row "$R4" name=w1-s5 deliverable=.bionic/docs/record/never.md launched_at="$(iso_ago 600)"
run_gate "$GATE" "$(payload "$R4" "$SID" w1-s5 false)"
expect_status "4a: no plan at all — the same unmet roster passes" "0" "$RC"

R4B="$(make_repo r4b)"
plan_fenced_only "$R4B"
new_roster "$R4B"
add_row "$R4B" name=w1-s5 deliverable=.bionic/docs/record/never.md launched_at="$(iso_ago 600)"
run_gate "$GATE" "$(payload "$R4B" "$SID" w1-s5 false)"
expect_status "4b: a fenced-only SDLC State is documentation, not a live wave — pass" "0" "$RC"

# ================================================================= Section 5
section "Section 5: fail-open — every way the verdict can fail to answer"

# The gate resolves the sweeper as its own sibling. Both cases below run a COPY of the gate
# from a directory whose sibling differs, which is the production resolution path under a
# different filesystem, not a substituted seam.
R5="$(make_wave_repo r5)"
add_row "$R5" name=w1-s5 deliverable=.bionic/docs/record/never.md launched_at="$(iso_ago 600)"

NOSWEEP="$SANDBOX/hooks-nosweeper"
mkdir -p "$NOSWEEP"
cp "$GATE" "$NOSWEEP/landing-gate.sh" 2>/dev/null
run_gate "$NOSWEEP/landing-gate.sh" "$(payload "$R5" "$SID" w1-s5 false)"
expect_status "5a: the sweeper script is absent — pass, do not block on a verdict we cannot take" "0" "$RC"
expect_empty "5a: …silently" "$OUT_STDERR"

BADSWEEP="$SANDBOX/hooks-badsweeper"
mkdir -p "$BADSWEEP"
cp "$GATE" "$BADSWEEP/landing-gate.sh" 2>/dev/null
printf '#!/bin/bash\nexit 7\n' > "$BADSWEEP/session-sweeper.sh"
chmod +x "$BADSWEEP/session-sweeper.sh"
run_gate "$BADSWEEP/landing-gate.sh" "$(payload "$R5" "$SID" w1-s5 false)"
expect_status "5b: the sweeper errors — pass" "0" "$RC"

# A verdict that printed nothing this gate recognises is not an UNMET verdict.
QUIETSWEEP="$SANDBOX/hooks-quietsweeper"
mkdir -p "$QUIETSWEEP"
cp "$GATE" "$QUIETSWEEP/landing-gate.sh" 2>/dev/null
printf '#!/bin/bash\nexit 1\n' > "$QUIETSWEEP/session-sweeper.sh"
chmod +x "$QUIETSWEEP/session-sweeper.sh"
run_gate "$QUIETSWEEP/landing-gate.sh" "$(payload "$R5" "$SID" w1-s5 false)"
expect_status "5c: exit 1 with no verdict line for this name — pass" "0" "$RC"

# A symlinked roster makes the verdict verb REFUSE (exit 2, plan assumption 15). That is the
# gate's fail-open path, and it is the one direction a hostile repo could otherwise use to
# aim this gate: it must never turn a refusal into a block.
R5B="$(make_repo r5b)"
plan_active "$R5B"
REAL_ROSTER="$SANDBOX/elsewhere-roster.state"
printf '# bionic session roster — schema roster-state/v1 — machine-local, safe to delete\n' > "$REAL_ROSTER"
mkrow name=w1-s5 deliverable=.bionic/docs/record/never.md launched_at="$(iso_ago 600)" >> "$REAL_ROSTER"
ln -s "$REAL_ROSTER" "$(roster_of "$R5B")"
run_gate "$GATE" "$(payload "$R5B" "$SID" w1-s5 false)"
expect_status "5d: a symlinked roster refuses the verdict — the gate passes, never blocks" "0" "$RC"
expect_absent "5d: …and says nothing about a contract it never read" "LANDING CONTRACT" "$OUT_STDERR"

# ================================================================= Section 6
section "Section 6: the gate judges the row it was handed, and records nothing"

R6="$(make_wave_repo r6)"
add_row "$R6" name=mine deliverable=.bionic/docs/record/mine.md launched_at="$(iso_ago 600)"
add_row "$R6" name=sibling deliverable=.bionic/docs/record/sibling.md launched_at="$(iso_ago 600)"
deliver "$R6" .bionic/docs/record/mine.md

run_gate "$GATE" "$(payload "$R6" "$SID" mine false)"
expect_status "6a: a met row passes while a sibling row is UNMET" "0" "$RC"
expect_empty "6a: …and the sibling's failure is never reported to it" "$OUT_STDERR"

run_gate "$GATE" "$(payload "$R6" "$SID" sibling false)"
expect_status "6b: the unmet sibling blocks when it is the one stopping" "2" "$RC"
expect_contains "6b: …naming its own artifact" "missing=.bionic/docs/record/sibling.md" "$OUT_STDERR"
expect_absent "6b: …and not the other row's" "mine.md" "$OUT_STDERR"

# The verdict verb writes nothing (ADR-003 zero authority); a gate that journalled its own
# decisions would hand this SubagentStop path a write it has no permission to own.
BEFORE="$(ls -A "$R6/.bionic/tmp" | sort)"
run_gate "$GATE" "$(payload "$R6" "$SID" sibling false)"
AFTER="$(ls -A "$R6/.bionic/tmp" | sort)"
expect_eq "6c: blocking writes no state file of its own" "$BEFORE" "$AFTER"
expect_eq "6c: the roster keeps exactly the two rows it was given — no row appended" \
  "2" "$(grep -c '^roster-state/v1|' "$(roster_of "$R6")" | tr -d ' ')"

# ================================================================= Section 7
section "Section 7: the Step-6 review remediations (C-5, C-2, S-1, S-4)"

# --- C-5: two readers of one key, and only one of them normalizes ---
#
# The verb stores and prints `clean()`-normalized names; the gate grepped the RAW
# `agent_type` back out of the verb's output, so any name whose stored form differs from
# its payload form missed the line and the gate exited 0 — a silent disarm, which is the
# exact class of disagreement this wave exists to close. The gate now reads the single line
# the SCOPED verb returned, which removes the second reader rather than teaching it to
# normalize.
R7="$(make_wave_repo r7)"
add_row "$R7" name="a b" deliverable=.bionic/docs/record/never.md launched_at="$(iso_ago 600)"
run_gate "$GATE" "$(payload "$R7" "$SID" "a  b" false)"
expect_status "7a: a name needing normalization still reaches its own contract (exit 2)" "2" "$RC"
expect_contains "7a: …and the refusal names its artifact" \
  "missing=.bionic/docs/record/never.md" "$OUT_STDERR"
run_gate "$GATE" "$(payload "$R7" "$SID" "a b" false)"
expect_status "7b: control — the exact stored form blocks as it always did" "2" "$RC"

# --- C-2: a name carrying two contracts blocks nobody ---
#
# The gate joins by name, so a re-used agent name made agent #1 answerable for agent #2's
# artifact. The verb now reports AMBIGUOUS and the gate passes on it: letting a stop through
# is the recoverable error, blocking the wrong agent is not.
R7B="$(make_wave_repo r7b)"
deliver "$R7B" .bionic/docs/record/first.md
add_row "$R7B" name=dup deliverable=.bionic/docs/record/first.md  tool_use_id=toolu_01FIRST \
  launched_at="$(iso_ago 900)"
add_row "$R7B" name=dup deliverable=.bionic/docs/record/second.md tool_use_id=toolu_01SECOND \
  launched_at="$(iso_ago 600)"
run_gate "$GATE" "$(payload "$R7B" "$SID" dup false)"
expect_status "7c: an ambiguous name passes rather than blocking the wrong agent" "0" "$RC"
expect_empty "7c: …silently, naming no artifact that may not be its job" "$OUT_STDERR"

# --- S-1: a waiver does not silence a contract that also names an artifact ---
R7C="$(make_wave_repo r7c)"
add_row "$R7C" name=quoter deliverable=.bionic/docs/record/quoter-out.md source=declared \
  waiver="<why this dispatch produces nothing durable>" launched_at="$(iso_ago 600)"
run_gate "$GATE" "$(payload "$R7C" "$SID" quoter false)"
expect_status "7d: a quoted waiver beside a declared artifact still blocks (exit 2)" "2" "$RC"
expect_contains "7d: …naming the artifact the brief itself declared" \
  "missing=.bionic/docs/record/quoter-out.md" "$OUT_STDERR"

# --- S-4: the payload session key is shape-checked before it touches a path ---
#
# `roster-${SID}.state` interpolates the payload's session id straight into a path, and the
# symlink guards check the state directory and the exact filenames — so a key carrying path
# separators leaves the guarded directory entirely rather than tripping a guard. Session ids
# are harness-minted UUIDs today; this is the one payload value on this path that got no
# belt, and the repo is hostile by this machinery's own threat model.
R7D="$(make_wave_repo r7d)"
mkdir -p "$R7D/.bionic/tmp/roster-x" "$R7D/planted"
SID_TRAVERSAL='x/../../../planted/evil'
PLANTED="$R7D/planted/evil.state"
printf '# bionic session roster — schema roster-state/v1 — machine-local, safe to delete\n' > "$PLANTED"
mkrow name=w1-s5 session="$SID_TRAVERSAL" deliverable=.bionic/docs/record/never.md \
  launched_at="$(iso_ago 600)" >> "$PLANTED"
expect_eq "7e: the traversal fixture really does escape the state directory (not vacuous)" \
  "yes" "$([ -e "$R7D/.bionic/tmp/roster-${SID_TRAVERSAL}.state" ] && echo yes || echo no)"
run_gate "$GATE" "$(payload "$R7D" "$SID_TRAVERSAL" w1-s5 false)"
expect_status "7e: a session key carrying path separators is not a session key — pass" "0" "$RC"
expect_absent "7e: …and no verdict is taken over the roster it reached" \
  "LANDING CONTRACT" "$OUT_STDERR"

# --- F-1: a name that is non-empty but CLEANS to empty must not drive a block ---
#
# The sweeper's verdict scopes on clean("$agent_type"); a raw name made only of the
# characters clean() folds away (`|`, whitespace, controls) scopes to the empty predicate,
# which widens the verb to a BARE verdict — one line per name — and `head -1` would then
# read the FIRST roster row's foreign contract. The critic reproduced this as a fail-CLOSED
# regression: with the first row UNMET, agent_type="|" blocked the "|" agent citing that
# row's artifact. The gate now guards a clean-empty name the way S-4 guards the session key.
# The first row is UNMET so a widened bare verdict would have exit-1'd on it.
R7E="$(make_wave_repo r7e)"
add_row "$R7E" name=solo   deliverable=.bionic/docs/record/never.md launched_at="$(iso_ago 600)"
add_row "$R7E" name="twin" deliverable=.bionic/docs/record/other.md launched_at="$(iso_ago 600)"
run_gate "$GATE" "$(payload "$R7E" "$SID" "|" false)"
expect_status "7f: a pipe-only agent_type (clean-empty) passes, never blocks on a foreign row" "0" "$RC"
expect_absent "7f: …and names no contract it was never dispatched under" \
  "LANDING CONTRACT" "$OUT_STDERR"
run_gate "$GATE" "$(payload "$R7E" "$SID" "   " false)"
expect_status "7g: an all-whitespace agent_type (clean-empty) passes too" "0" "$RC"
expect_absent "7g: …silently, naming no foreign contract" "LANDING CONTRACT" "$OUT_STDERR"

# ================================================================= Section 8
section "Section 8: an ACKED row is closed for every reader (epic-16 w2 S3, R2)"
#
# The orchestrator verifies every agent's completion, and `ack` is that verification made
# durable so a row it closed stays closed across sessions. Blocking such an agent's stop
# over artifacts a human has already accounted for is precisely the false alarm this wave
# exists to end. The ack is invisible to `verdict` by design — a contract is met by
# artifacts or it is not, which is what lets an ack over an UNMET row WARN instead of
# quietly erasing the discrepancy — so the gate reads the ledger, and this suite makes the
# REAL ack verb write the ledger it reads.

SWEEPER_BIN="$(cd "$(dirname "$GATE")" && pwd)/session-sweeper.sh"
ack_row() {  # <repo> <name>
  ( cd "$1" && CLAUDE_CODE_SESSION_ID="$SID" bash "$SWEEPER_BIN" ack "$2" ) >/dev/null 2>&1
  return 0
}

R8="$(make_wave_repo r8)"
add_row "$R8" name=w2-s3 deliverable=.bionic/docs/record/never.md launched_at="$(iso_ago 600)"

# The precondition, and the paired positive for everything below: unacked, this blocks.
run_gate "$GATE" "$(payload "$R8" "$SID" w2-s3 false)"
expect_status "8a: precondition — an unacked UNMET contract still blocks" "2" "$RC"

ack_row "$R8" w2-s3
run_gate "$GATE" "$(payload "$R8" "$SID" w2-s3 false)"
expect_status "8b: once acked, the same stop passes" "0" "$RC"
expect_empty "8c: …silently — the orchestrator already accounted for it" "$OUT_STDERR"

# WHOLE-NAME MATCH, never a substring: an ack of a longer name must not close this row, or
# one ack of `w4-s10` would quietly close `w4-s1` too.
R8B="$(make_wave_repo r8b)"
add_row "$R8B" name=w4-s1  deliverable=.bionic/docs/record/never.md  launched_at="$(iso_ago 600)"
add_row "$R8B" name=w4-s10 deliverable=.bionic/docs/record/never2.md launched_at="$(iso_ago 600)"
ack_row "$R8B" w4-s10
run_gate "$GATE" "$(payload "$R8B" "$SID" w4-s1 false)"
expect_status "8d: an ack of w4-s10 does not close w4-s1" "2" "$RC"
run_gate "$GATE" "$(payload "$R8B" "$SID" w4-s10 false)"
expect_status "8e: …and does close w4-s10" "0" "$RC"

# A SYMLINKED LEDGER. Two guards fire, and the OUTER one decides: `session-sweeper.sh`
# refuses outright when its own ledger path is a link (nothing was written through it, and
# it will not answer over state it was redirected away from), so the verdict exits 2 and
# this gate takes its documented fail-open — an answer it did not get is not one it may
# refuse on. The gate's own `ledger_acked` declines the link too, so no ack out of a
# repo-controlled file ever closes a row here; it simply never gets that far.
# The CLOSED half of this pair is at the stop gate, where the same fixture refuses the
# stop (hooks/stop-guard.test.sh §11) — the two gates have opposite fail directions by
# design and this is the fixture that shows it.
R8C="$(make_wave_repo r8c)"
add_row "$R8C" name=w2-s3 deliverable=.bionic/docs/record/never.md launched_at="$(iso_ago 600)"
mkdir -p "$SANDBOX/elsewhere"
( cd "$SANDBOX/elsewhere" && git init -q . 2>/dev/null )
mkdir -p "$SANDBOX/elsewhere/.bionic/tmp"
printf '# bionic sweeper ledger — schema sweeper-ledger/v1\nsweeper-ledger/v1|event=ack|at=2026-08-11T00:00:00Z|epoch=1|pid=1|session=%s|name=w2-s3\n' \
  "$SID" > "$SANDBOX/elsewhere/ledger.state"
ln -s "$SANDBOX/elsewhere/ledger.state" "$R8C/.bionic/tmp/sweeper-$SID.state"
run_gate "$GATE" "$(payload "$R8C" "$SID" w2-s3 false)"
expect_status "8f: a symlinked ledger: the verb refuses, this gate fail-opens" "0" "$RC"
expect_empty "8g: …silently, claiming nothing about a contract it never read" "$OUT_STDERR"

# ---------- summary ----------
printf '\n---\n%d/%d passed, %d failed\n' "$PASS" "$TOTAL" "$FAIL"
[ "$FAIL" -eq 0 ]
