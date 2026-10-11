#!/bin/bash
# tests/notify.test.sh — THE PERSON'S LEDGER AND THE ONE SENDER (epic-23 wave-33-workhorse, T11;
# REQ-2 AC-2.2, AC-2.3 (the tick half), AC-2.4, AC-2.5; spec D2).
#
# WHAT THIS SUITE IS FOR. Nothing in a run called the person: the harness's push reaches a phone
# only while Remote Control is connected, and the tick's GATE line told the orchestrator to use
# "the human's own notify channel", which did not exist. D2 adds a store of what the person owes
# (payload/scripts/lib/owed.sh, `.bionic/tmp/owed-<session>.state`), written by the sources that
# leave the person a decision (the Step cards, the tick's GATE) and closed by the verbs that
# record the answer, and one sender (payload/scripts/lib/notify.sh) that the Stop and the tick
# call once per open item.
#
# THE SECTIONS ARE THE SPEC'S EVAL DESIGN ROWS, in order:
#   §ONCE     AC-2.2 one open key, a Stop sends 1; a second Stop 0; the answer verb closes; a new
#             key sends 1
#   §SOURCES  AC-2.3 (tick half) a tick deciding GATE sends 1, and the next tick 0
#   §QUIET    AC-2.4 a landing, a dispatch, a quiet tick send 0
#   §ABSENT   AC-2.5 with no channel file the Stop and tick fixtures print byte-identically to
#             the base; with the stub exiting 7, every exit code is unchanged
# T12 adds §SETUP and the close-out half of §SOURCES.
#
# HERMETIC. `curl` is a stub on PATH that counts its calls and records each one's title and body;
# HOME and CLAUDE_CONFIG_DIR are scratch, so neither the real channel file nor the real cron.env
# can be read, and the session id is the fixture's, so no store of a live session is touched.
#
# FIXTURE FIDELITY. Every fixture is built here from the shapes the shipped code writes: the
# Stop payload is the platform's (tests/stop.test.sh's `fire`), the gate lines are
# hooks/permission-answer.sh's `gate/v1` shape (tests/session-poker-2.test.sh §GATE), the tick
# world is §45's QUIET world, and the cards render artifacts whose stem matches the bound plan
# the way a run's requirements, spec and plan share one. The channel file and cron.env are
# SYNTHESIZED to the shape the brief names (`topic-from=cron.env:BIONIC_NTFY_TOPIC`,
# `title-prefix=`); T12's setup writes the real one.
#
# ANTI-VACUITY. The store reader (`nt_owed`) and the call counter (`nt_calls`) are each proven to
# return a positive reading on a fixture that must produce one (§ONCE 1 and 2) before any zero is
# read through them, and every "sends nothing" row sits beside the positive row of the same
# section on the same counter.
#
# Usage: bash tests/notify.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"
. "$(dirname "$0")/lib/bound-marker.sh"
. "$(dirname "$0")/lib/roster-row.sh"
. "$(dirname "$0")/lib/swept-marker.sh"
. "$(dirname "$0")/lib/live-answer.sh"
. "$(dirname "$0")/lib/plan-fixture.sh"

command -v jq >/dev/null 2>&1 || { echo "notify: jq absent — suite cannot run"; exit 1; }

POKER="${BIONIC_HOOKS_DIR}/session-poker.sh"
STOP_HOOK="${BIONIC_HOOKS_DIR}/stop.sh"
PREFLIGHT="${BIONIC_HOOKS_DIR}/dispatch-preflight.sh"
CARD_SH="${BIONIC_SCRIPTS_DIR}/payload/scripts/card.sh"
NT_LIB="${BIONIC_SCRIPTS_DIR}/payload/scripts/lib"
. "$(dirname "$0")/session-poker.prelude.sh"

# ---------- the stub, the scratch home, the channel ----------

NT_HOME="$TMPROOT/home"
mkdir -p "$NT_HOME"
export HOME="$NT_HOME"
NT_BIN="$TMPROOT/bin"
mkdir -p "$NT_BIN"
export NT_CALLS="$TMPROOT/curl.calls"
: > "$NT_CALLS"
# One line per call: `url=<url>|title=<Title header>|body=<-d value>`, then exit NT_CURL_RC.
cat > "$NT_BIN/curl" <<'STUB'
#!/bin/bash
url="" title="" body=""
while [ $# -gt 0 ]; do
  case "$1" in
    -d|--data|--data-raw|--data-binary) body="$2"; shift 2 ;;
    -H) case "$2" in Title:*) title="${2#Title: }" ;; esac; shift 2 ;;
    --max-time|-m|-o|--output) shift 2 ;;
    http*) url="$1"; shift ;;
    *) shift ;;
  esac
done
printf 'url=%s|title=%s|body=%s\n' "$url" "$title" "$(printf '%s' "$body" | tr '\n' ' ')" >> "$NT_CALLS"
exit "${NT_CURL_RC:-0}"
STUB
chmod +x "$NT_BIN/curl"
export PATH="$NT_BIN:$PATH"
export NT_CURL_RC=0

nt_calls() { /usr/bin/grep -c '^url=' "$NT_CALLS" 2>/dev/null | tr -d ' ' || true; }
nt_last()  { tail -1 "$NT_CALLS" 2>/dev/null; }

channel_on() {  # <config dir> — the declared channel: topic named in cron.env, a title prefix
  mkdir -p "$1/bionic"
  printf 'topic-from=cron.env:BIONIC_NTFY_TOPIC\ntitle-prefix=bionic-fixture\n' > "$1/bionic/notify"
  printf '# fixture cron env\nexport BIONIC_NTFY_TOPIC=fixture-topic-123\n' > "$1/cron.env"
}
channel_off() { rm -f "$1/bionic/notify"; }

# nt_owed <repo> <function> [args...] -> what owed.sh answers, in that repo, for the fixture
# session. Sourced from the shipped library, so the reader is the code under test.
nt_owed() {
  local repo="$1"; shift
  ( cd "$repo" && CLAUDE_CODE_SESSION_ID="$SID" bash -c '. "$1/owed.sh" && shift && "$@"' _ "$NT_LIB" "$@" ) 2>/dev/null
}

# nt_stop <repo> [event] [stop_hook_active] -> NT_OUT, NT_ERR, NT_RC: the real Stop hook, fed the
# platform's payload, in the scratch home. The transcript is one short user line.
NT_TX="$TMPROOT/stop-transcript.jsonl"
printf '{"type":"user","timestamp":"2026-10-11T00:00:00.000Z","message":{"role":"user","content":"go"}}\n' > "$NT_TX"
nt_stop() {
  local d="$1" ev="${2:-Stop}" sha="${3:-false}" payload
  payload=$(jq -nc --arg c "$d" --arg t "$NT_TX" --arg s "$SID" --arg e "$ev" --argjson a "$sha" \
    '{session_id:$s,transcript_path:$t,cwd:$c,hook_event_name:$e,stop_hook_active:$a,background_tasks:[]}')
  NT_OUT=$(cd "$d" && env CLAUDE_PROJECT_DIR="" CLAUDE_CODE_SESSION_ID="$SID" bash "$STOP_HOOK" \
    <<< "$payload" 2>"$TMPROOT/stop.err")
  NT_RC=$?
  NT_ERR=$(cat "$TMPROOT/stop.err" 2>/dev/null)
}

# nt_card <repo> <verb> <artifact...> -> NT_OUT, NT_RC: card.sh run from the repo, as the run does.
nt_card() {
  local repo="$1"; shift
  NT_OUT=$(cd "$repo" && CLAUDE_CODE_SESSION_ID="$SID" bash "$CARD_SH" "$@" 2>&1 0<&-)
  NT_RC=$?
}

# ---------- the run fixture: a bound plan below Step 3, its requirements and its spec ----------
#
# The three artifacts share the stem `wave-01-fixture`, the way a run's requirements, spec and
# plan do, so the Step cards render the session's own run. The plan carries no approved-by: line
# (a Step-1 card is shown before the plan is approved) and one pending row reading
# approval:release, the name the approve verb is asked to record.
nt_run() {  # <label> -> repo path; bound, committed, a git user
  local r p s q
  r="$(make_repo "$1")"
  git -C "$r" config user.name "Dana Fixture"
  git -C "$r" config user.email "dana@example.invalid"
  p="$r/.bionic/docs/plans/epic-99-fixture/wave-01-fixture.plan.md"
  q="$r/.bionic/docs/specs/epic-99-fixture/wave-01-fixture.requirements.md"
  s="$r/.bionic/docs/specs/epic-99-fixture/wave-01-fixture.spec.md"
  mkdir -p "${p%/*}" "${q%/*}"
  cat > "$p" <<'FIXEOF'
---
governing-skill: superpowers:writing-plans
canonical_sdlc_version: 14
sdlc-step: 3
walk: required
rigor: double
parallel-budget: writers=8 suites=4 worktrees=32 test_jobs=8 source=user
working-branch: wave/99-fixture
integration-branch: main
base-sha: abc1234
---

# fixture wave 99 · plan

## Goal

Land the fixture's two requirements under the fixture spec's design.

## SDLC State

integration-branch: main
current: 3

- Step 3: plan

## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | worktree | status | reads |
|---|---|---|---|---|---|---|---|---|---|---|---|
| T1 | 4 | build | REQ-1: the first task in one line. complexity: standard | implementor | — | 30 | REQ-1 | lib/first.sh | — | pending | approval:release |

## Verification Matrix

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1.1 | T0 | pending | — | — |
FIXEOF
  cat > "$q" <<'FIXEOF'
---
sdlc-step: 1
working-branch: wave/99-fixture
integration-branch: main
base-sha: abc1234
---

# fixture wave 99 · requirements

## Goal

Ship the fixture wave so the cards have an artifact to read.

## Not Doing

- The excluded item, and the one-line reason it is out.

## Requirements and acceptance criteria

### REQ-1 — the first requirement in one line

provenance: user 2026-10-11 "do the thing"
- AC-1.1 the first criterion. Fails when: it does not hold.
FIXEOF
  cat > "$s" <<'FIXEOF'
---
sdlc-step: 2
working-branch: wave/99-fixture
integration-branch: main
base-sha: abc1234
---

# fixture wave 99 · spec

## Goal

Answer the fixture's requirement with a design small enough to read whole.

## Design

### 1. Domain model

- **Fixture** — a file this suite writes and reads back.

### 3. Ownership table

| concept | owning module (SSoT) | rendering surfaces | agreement test |
|---|---|---|---|
| first thing | `lib/first.sh` | `card.sh` rows | `tests/first.test.sh` |

## Eval design

| Requirement | Approach | Criterion | Eval type | Eval | Fails when |
|---|---|---|---|---|---|
| REQ-1 | source pin | AC-1.1 the first criterion | static | `grep` | the pin is gone |
FIXEOF
  bound_marker "$r" "$SID" "$p"
  ( cd "$r" && git add -f .bionic/docs && git commit -qm fixture ) >/dev/null 2>&1
  printf '%s' "$r"
}
nt_plan() { printf '%s/.bionic/docs/plans/epic-99-fixture/wave-01-fixture.plan.md' "$1"; }
nt_req()  { printf '%s/.bionic/docs/specs/epic-99-fixture/wave-01-fixture.requirements.md' "$1"; }
nt_spec() { printf '%s/.bionic/docs/specs/epic-99-fixture/wave-01-fixture.spec.md' "$1"; }

# ============================================================
section "§ONCE: a turn that ends blocked sends one notification, and only one per block (AC-2.2)"
# ============================================================
export CLAUDE_CONFIG_DIR="$SP_CONFIG_DIR"
channel_on "$CLAUDE_CONFIG_DIR"
RO="$(nt_run nt-once)"
: > "$NT_CALLS"

nt_card "$RO" step1 "$(nt_req "$RO")"
expect_eq "N1 the Step-1 card renders (exit 0)" "0" "$NT_RC"
expect_contains "N1a …and prints its question" 'Do you approve these requirements? Reply "approved" to approve it.' "$NT_OUT"
N_LIST="$(nt_owed "$RO" owed_list)"
expect_nonempty "N1b the store reader answers: the card opened an item (the extractor works)" "$N_LIST"
expect_contains "N1c …keyed approve:step1" "approve:step1" "$(printf '%s\n' "$N_LIST" | cut -f1)"
expect_eq "N1d …and it is unsent" "approve:step1" "$(nt_owed "$RO" owed_unsent)"
expect_eq "N1e rendering a card sends nothing by itself" "0" "$(nt_calls)"

nt_stop "$RO"
expect_eq "N2 AC-2.2 the Stop that ends the blocked turn sends exactly one notification" "1" "$(nt_calls)"
expect_contains "N2a …carrying the one line the card printed for the block" \
  'body=Do you approve these requirements? Reply "approved" to approve it.' "$(nt_last)"
expect_contains "N2b …to the topic named in cron.env, never stored in the channel file" \
  "url=https://ntfy.sh/fixture-topic-123|" "$(nt_last)"
expect_contains "N2c …under the declared title prefix" "|title=bionic-fixture " "$(nt_last)"
expect_eq "N2d …and the item is marked sent: nothing is unsent" "" "$(nt_owed "$RO" owed_unsent)"
expect_contains "N2e …while it stays open (the block is unresolved)" "approve:step1" "$(nt_owed "$RO" owed_list | cut -f1)"

nt_stop "$RO"
expect_eq "N3 AC-2.2 a later turn on the same unresolved block sends nothing" "1" "$(nt_calls)"
nt_card "$RO" step1 "$(nt_req "$RO")"
nt_stop "$RO"
expect_eq "N3a …nor does the same card rendered again (the open is idempotent per key)" "1" "$(nt_calls)"
nt_stop "$RO" Stop true
expect_eq "N3b …nor a re-entry Stop" "1" "$(nt_calls)"

# A NAMED APPROVAL, answered by its verb. The item is opened through the library, as a source
# would; the approve verb records the user's reply and closes it.
nt_owed "$RO" owed_open approve:release "approval: release" 'Approve release? Reply "approved".' >/dev/null
expect_eq "N4 a second open key is unsent" "approve:release" "$(nt_owed "$RO" owed_unsent)"
nt_stop "$RO" SubagentStop
expect_eq "N4a a subagent's stop is not the person's turn end: it sends nothing" "1" "$(nt_calls)"
nt_stop "$RO"
expect_eq "N4b the next Stop sends it: one more, not two (the first key is already sent)" "2" "$(nt_calls)"
expect_contains "N4c …with its own line" "body=Approve release? Reply \"approved\"." "$(nt_last)"
POKE_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
poke "$RO" approve release 'Ship it.'
POKE_BOUND="$POKE_BOUND_WAS"
expect_eq "N5 the answer verb records the approval (exit 0)" "0" "$RC"
[ "$RC" = 0 ] || printf '      the verb said: %s\n' "$OUT"
N_KEYS="$(nt_owed "$RO" owed_list | cut -f1)"
expect_contains "N5a …the store still lists the card's open item (the reader works here)" "approve:step1" "$N_KEYS"
expect_absent "N5b …and the approval's item is closed by the verb that answered it" "approve:release" "$N_KEYS"

nt_card "$RO" step2 "$(nt_spec "$RO")"
expect_eq "N6 the Step-2 card renders (exit 0)" "0" "$NT_RC"
N_KEYS="$(nt_owed "$RO" owed_list | cut -f1)"
expect_contains "N6a …it opens approve:step2" "approve:step2" "$N_KEYS"
expect_absent "N6b …and closes approve:step1: a later card is shown only once the earlier one is answered" "approve:step1" "$N_KEYS"
nt_stop "$RO"
expect_eq "N7 AC-2.2 a new key sends one" "3" "$(nt_calls)"
expect_contains "N7a …the Step-2 card's question" 'body=Do you approve this design? Reply "approved" to approve it.' "$(nt_last)"
nt_stop "$RO"
expect_eq "N7b …and once" "3" "$(nt_calls)"

nt_card "$RO" step3 "$(nt_plan "$RO")"
expect_eq "N8 the Step-3 card renders (exit 0)" "0" "$NT_RC"
expect_eq "N8a …and its item is unsent" "approve:step3" "$(nt_owed "$RO" owed_unsent)"
awk '{ print } /^current: 3$/ { print "approved-by: Dana Fixture 2026-10-11T00:00:00Z \"approved\"" }' \
  "$(nt_plan "$RO")" > "$TMPROOT/plan.tmp" && mv "$TMPROOT/plan.tmp" "$(nt_plan "$RO")"
nt_stop "$RO"
expect_eq "N8b a plan approved before the turn ended owes nothing: the Stop closes the step items and sends none" \
  "3" "$(nt_calls)"
N_KEYS="$(nt_owed "$RO" owed_list | cut -f1)"
expect_absent "N8c …approve:step3 is closed" "approve:step3" "$N_KEYS"
expect_absent "N8d …and approve:step2 with it" "approve:step2" "$N_KEYS"

# A CARD THAT IS NOT THIS SESSION'S RUN OWES NOTHING. Another run's requirements, rendered in the
# same root (a suite rendering its fixtures, a reader comparing waves), open no item.
RO2="$(nt_run nt-other)"
mkdir -p "$RO2/.bionic/docs/specs/epic-98-other"
cp "$(nt_req "$RO2")" "$RO2/.bionic/docs/specs/epic-98-other/wave-02-other.requirements.md"
nt_card "$RO2" step1 "$RO2/.bionic/docs/specs/epic-98-other/wave-02-other.requirements.md"
expect_eq "N9 another run's card renders (exit 0)" "0" "$NT_RC"
nt_card "$RO2" step1 "$(nt_req "$RO2")"
expect_eq "N9a …and opens nothing: the only item is this run's own card's" "approve:step1" \
  "$(nt_owed "$RO2" owed_list | cut -f1 | tr '\n' ' ' | sed 's/ $//')"

# ============================================================
section "§SOURCES: a tick deciding GATE sends one notification per request (AC-2.3, the tick half)"
# ============================================================
NS_CFG="$(fake_config_dir nt-gate)"
export CLAUDE_CONFIG_DIR="$NS_CFG"
mkdir -p "$NS_CFG/bionic"; printf '80\n' > "$NS_CFG/bionic/share"
channel_on "$NS_CFG"
NS_TR="$NS_CFG/projects/-fixture-project/$SID.jsonl"
plant_answer "$NS_TR" fresh "busy:running"
gate_of() { printf '%s/.bionic/tmp/gate-%s.state' "$1" "$SID"; }
gate_line() {  # <asker> <category> <head>
  printf 'gate/v1|at=2026-10-11T00:00:00Z|session=%s|asker=%s|category=%s|head=%s\n' "$SID" "$1" "$2" "$3"
}
nt_world() {  # <label> -> a repo: armed, one open row inside its duration (the QUIET world)
  local r; r="$(make_repo "$1")"; new_roster "$r"; armed_ago "$r"
  add_row "$r" name=busy deliverable="$r/never-written.md" duration="4 hours" launched_at="$(iso_ago 60)"
  printf '%s' "$r"
}
RS="$(nt_world nt-gate)"
: > "$NT_CALLS"
gate_line w99-T1 leaves-the-machine "git push origin wave/99-fx" >> "$(gate_of "$RS")"
poke "$RS" tick
expect_eq "S1 precondition: the tick decides NOTIFY on the gate request (exit 1)" "1" "$RC"
expect_contains "S1a …and prints its GATE line" "poker: GATE w99-T1 — leaves-the-machine: git push origin wave/99-fx" "$OUT"
expect_eq "S2 AC-2.3 the tick that raises the GATE sends one notification" "1" "$(nt_calls)"
expect_contains "S2a …carrying the GATE line it printed" \
  "body=poker: GATE w99-T1 — leaves-the-machine: git push origin wave/99-fx" "$(nt_last)"
expect_contains "S2b …and the request is on the person's ledger" "gate:" "$(nt_owed "$RS" owed_list | cut -f1)"
poke "$RS" tick
expect_eq "S3 the next tick does not raise it again, and sends nothing" "1" "$(nt_calls)"
gate_line lead credentials "cat ~/.ssh/id_ed25519" >> "$(gate_of "$RS")"
poke "$RS" tick
expect_eq "S4 a new request raises again and sends one, only its own" "2" "$(nt_calls)"
expect_contains "S4a …the new request's line" "body=poker: GATE lead — credentials: cat ~/.ssh/id_ed25519" "$(nt_last)"

# ============================================================
section "§QUIET: progress never sends — a landing, a dispatch, a quiet tick (AC-2.4)"
# ============================================================
RQ="$(nt_world nt-quiet)"
# An unsent card item sits on the ledger: the tick is not a turn end, and must not send it.
nt_owed "$RQ" owed_open approve:step1 "approval: Step 1" 'Do you approve these requirements?' >/dev/null
expect_eq "Q0 precondition: the ledger holds one unsent item (the reader works on this fixture)" \
  "approve:step1" "$(nt_owed "$RQ" owed_unsent)"
: > "$NT_CALLS"
poke "$RQ" tick
expect_eq "Q1 precondition: the tick is quiet (QUIET, exit 0)" "0" "$RC"
expect_eq "Q1a AC-2.4 a quiet tick sends nothing, an unsent item on the ledger included" "0" "$(nt_calls)"
gate_line w99-T2 billing "stripe charges create" >> "$(gate_of "$RQ")"
poke "$RQ" tick
expect_eq "Q1b beside it: the same world's GATE tick sends exactly its one request (the counter works here)" \
  "1" "$(nt_calls)"
expect_contains "Q1c …the GATE line, not the card item" "body=poker: GATE w99-T2 — billing: stripe charges create" "$(nt_last)"

# THE RUN WORLD, ON ITS OWN COUNT: nothing owed, then a landing and a dispatch, then one item
# opened in the same world, which the next Stop sends (the positive on this counter, this fixture).
RL="$(nt_run nt-landing)"
: > "$NT_CALLS"
nt_stop "$RL"
expect_eq "Q2 a Stop with nothing owed sends nothing" "0" "$(nt_calls)"
poke "$RL" row-landed T1 --by-hand 'fixture landing'
expect_eq "Q3 AC-2.4 a landing sends nothing (whatever the verb answers: rc $RC)" "0" "$(nt_calls)"
NQ_PAYLOAD=$(jq -nc --arg c "$RL" --arg s "$SID" \
  '{session_id:$s,cwd:$c,hook_event_name:"PreToolUse",tool_name:"Agent",tool_input:{description:"T1",prompt:"do T1",subagent_type:"bionic:implementor",name:"w99-T1"}}')
( cd "$RL" && env CLAUDE_PROJECT_DIR="" CLAUDE_CODE_SESSION_ID="$SID" bash "$PREFLIGHT" <<< "$NQ_PAYLOAD" ) >/dev/null 2>&1
expect_eq "Q4 AC-2.4 a dispatch sends nothing" "0" "$(nt_calls)"
export CLAUDE_CONFIG_DIR="$SP_CONFIG_DIR"
nt_owed "$RL" owed_open approve:release "approval: release" 'Approve release?' >/dev/null
nt_stop "$RL"
expect_eq "Q5 beside them, in the same world, an item opened is sent by the next Stop (the counter works here)" \
  "1" "$(nt_calls)"
export CLAUDE_CONFIG_DIR="$NS_CFG"

# ============================================================
section "§ABSENT: no channel is 1.15.0, and a failed send changes no exit code (AC-2.5)"
# ============================================================
export CLAUDE_CONFIG_DIR="$SP_CONFIG_DIR"
channel_off "$SP_CONFIG_DIR"
: > "$NT_CALLS"
NA_OUT="$(cd "$TMPROOT" && bash -c '. "$1/notify.sh" && notify_send "a title" "a body"; echo "rc=$?"' _ "$NT_LIB" 2>&1)"
expect_eq "A1 AC-2.5 with no channel file, notify_send prints nothing and returns 0" "rc=0" "$NA_OUT"
expect_eq "A1a …and calls nothing" "0" "$(nt_calls)"
channel_on "$SP_CONFIG_DIR"
NA_OUT="$(cd "$TMPROOT" && bash -c '. "$1/notify.sh" && notify_send "a title" "a body"; echo "rc=$?"' _ "$NT_LIB" 2>&1)"
expect_eq "A1b beside it, with the channel declared it prints nothing either" "rc=0" "$NA_OUT"
expect_eq "A1c …and makes the one call (the counter works here)" "1" "$(nt_calls)"
channel_off "$SP_CONFIG_DIR"

# THE STOP, BYTE FOR BYTE. The base is the same fixture with no ledger at all (what 1.15.0 has);
# the case is the fixture with an open, unsent item and no channel.
RB="$(nt_run nt-base)"
RA="$(nt_run nt-absent)"
nt_owed "$RA" owed_open approve:release "approval: release" 'Approve release?' >/dev/null
: > "$NT_CALLS"
nt_stop "$RB"; NB_OUT="$NT_OUT"; NB_ERR="$NT_ERR"; NB_RC="$NT_RC"
nt_stop "$RA"
expect_eq "A2 AC-2.5 no channel: the Stop's stdout is byte-identical to the base" "$NB_OUT" "$NT_OUT"
expect_eq "A2a …its stderr is identical to the base's, the fixture's name aside" \
  "$(printf '%s' "$NB_ERR" | sed 's/nt-base/X/g')" "$(printf '%s' "$NT_ERR" | sed 's/nt-absent/X/g')"
expect_eq "A2b …and so is its exit code" "$NB_RC" "$NT_RC"
expect_eq "A2c …nothing was called" "0" "$(nt_calls)"
expect_eq "A2d …and the item is still owed, unsent, for a channel declared later" "approve:release" \
  "$(nt_owed "$RA" owed_unsent)"

# THE TICK, THREE WAYS: no channel, a channel whose send succeeds, a channel whose send fails.
# Each is a fresh world with the same request; the output is compared with its digits masked
# (the tick prints elapsed seconds and instants).
na_tick() {  # <label> -> NA_TOUT (digits masked), NA_TRC
  local r; r="$(nt_world "$1")"
  gate_line w99-T1 leaves-the-machine "git push origin wave/99-fx" >> "$(gate_of "$r")"
  poke "$r" tick
  NA_TOUT="$(printf '%s\n' "$OUT" | sed -e "s/$1/X/g" -e 's/[0-9]/N/g')"; NA_TRC="$RC"
}
export CLAUDE_CONFIG_DIR="$NS_CFG"
channel_off "$NS_CFG"
: > "$NT_CALLS"
na_tick nt-tick-off; NA_OFF="$NA_TOUT"; NA_OFF_RC="$NA_TRC"
expect_eq "A3 precondition: the GATE tick decides NOTIFY (exit 1)" "1" "$NA_OFF_RC"
expect_eq "A3a AC-2.5 no channel: the GATE tick calls nothing" "0" "$(nt_calls)"
channel_on "$NS_CFG"
na_tick nt-tick-on
expect_eq "A3b with a channel the same tick sends (the counter works here)" "1" "$(nt_calls)"
expect_eq "A3c …and prints exactly what the tick with no channel printed" "$NA_OFF" "$NA_TOUT"
expect_eq "A3d …with the same exit code" "$NA_OFF_RC" "$NA_TRC"
export NT_CURL_RC=7
na_tick nt-tick-fail
expect_eq "A4 a send that fails (curl exits 7) was attempted" "2" "$(nt_calls)"
expect_eq "A4a AC-2.5 …and the tick prints exactly what it printed with no channel" "$NA_OFF" "$NA_TOUT"
expect_eq "A4b …with the same exit code" "$NA_OFF_RC" "$NA_TRC"

export CLAUDE_CONFIG_DIR="$SP_CONFIG_DIR"
channel_on "$SP_CONFIG_DIR"
RF="$(nt_run nt-fail)"
nt_owed "$RF" owed_open approve:release "approval: release" 'Approve release?' >/dev/null
nt_stop "$RF"
expect_eq "A5 a failing send at the Stop was attempted" "3" "$(nt_calls)"
expect_eq "A5a AC-2.5 …and the Stop's exit code is the base's" "$NB_RC" "$NT_RC"
expect_eq "A5b …and its stdout is the base's" "$NB_OUT" "$NT_OUT"
NA_AUDIT="$(cat "$NT_HOME"/.claude/logs/*/sdlc-audit.md 2>/dev/null)"
expect_contains "A5c …and the failure is logged to the record, naming the key" "notify-failed" "$NA_AUDIT"
expect_contains "A5d …with the item's key" "approve:release" "$NA_AUDIT"
nt_stop "$RF"
expect_eq "A5e a failed send is not retried turn after turn" "3" "$(nt_calls)"
nt_card "$RF" step1 "$(nt_req "$RF")"
expect_eq "A6 AC-2.5 card.sh exits 0 with a failing channel" "0" "$NT_RC"
POKE_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
poke "$RF" approve release 'Ship it.'
POKE_BOUND="$POKE_BOUND_WAS"
expect_eq "A6a …and so does the answer verb" "0" "$RC"
export NT_CURL_RC=0

finish
