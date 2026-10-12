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
# T12 adds §SETUP (AC-2.1: setup's notify item and doctor's read-only report), the close-out half
# of §SOURCES (D: a delivered run sends one notification), the gate item's closer (C) and the
# wipe's sparing of a live neighbour's ledger (W).
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
# NT_CURL_KILL=1: the caller is killed mid-send, after this call is recorded (the Stop's ten seconds).
[ -z "${NT_CURL_KILL:-}" ] || kill -9 "$PPID"
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
expect_regex "N2c2 …with ONE space between the prefix and the title, not two" '[|]title=bionic-fixture [^ ]' "$(nt_last)"
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

# ---- T12: THE GATE ITEM'S CLOSER. A gate item is closed when the gate is no longer raised: its key
# is gone from `gate_raised=` (the request left the gate file). Two requests are raised, one is
# cleared, then the other. The positive (two items open, two sent) is read through the same
# `nt_owed` reader before any item is read as closed.
RG="$(nt_world nt-gate-close)"
: > "$NT_CALLS"
gate_line w99-T1 leaves-the-machine "git push origin wave/99-fx" >> "$(gate_of "$RG")"
gate_line lead credentials "cat ~/.ssh/id_ed25519" >> "$(gate_of "$RG")"
poke "$RG" tick
expect_eq "C1 two requests raised: the tick sent two" "2" "$(nt_calls)"
NG_OPEN="$(nt_owed "$RG" owed_list | cut -f1 | /usr/bin/grep '^gate:')"
expect_eq "C1a …and both are open on the person's ledger (the reader sees them)" "2" "$(printf '%s\n' "$NG_OPEN" | /usr/bin/grep -c .)"
NG_FIRST="$(printf '%s\n' "$NG_OPEN" | sed -n 1p)"; NG_SECOND="$(printf '%s\n' "$NG_OPEN" | sed -n 2p)"
gate_line lead credentials "cat ~/.ssh/id_ed25519" > "$(gate_of "$RG")"
poke "$RG" tick
expect_eq "C2 AC-2.3 the request that left the gate file is closed, and only it" "$NG_SECOND" \
  "$(nt_owed "$RG" owed_list | cut -f1 | /usr/bin/grep '^gate:')"
expect_ne "C2a …(the closed one was the first)" "$NG_FIRST" "$NG_SECOND"
expect_eq "C2b closing sends nothing" "2" "$(nt_calls)"
rm -f "$(gate_of "$RG")"
poke "$RG" tick
expect_eq "C3 the gate file gone: the last gate item closes" "0" \
  "$(nt_owed "$RG" owed_list | cut -f1 | /usr/bin/grep -c '^gate:')"
expect_eq "C3a …and nothing was sent for it" "2" "$(nt_calls)"
gate_line lead credentials "cat ~/.ssh/id_ed25519" >> "$(gate_of "$RG")"
poke "$RG" tick
expect_eq "C4 the same request raised again after it cleared is a new need, and sends once more" "3" "$(nt_calls)"
expect_eq "C4a …on the ledger again" "1" "$(nt_owed "$RG" owed_list | cut -f1 | /usr/bin/grep -c '^gate:')"

# ---- T12: CLOSE-OUT'S DELIVERY (AC-2.3, the close half). A run delivered at close sends one
# notification, once. The fixture is close-out.test.sh's own (a git project at Step 8 that `run`
# takes to delivered): its builders are read out of that file by name, so this suite holds no
# second copy of the fixture and a builder that changes there changes here.
CO_TESTS="$(dirname "$0")/close-out.test.sh"
nt_import_fn() {  # <name> [<file>] -> the function, defined here, read out of <file> (close-out.test.sh)
  local body from="${2:-$CO_TESTS}"
  body="$(awk -v n="$1" 'index($0, n "() {") == 1 { p = 1 } p { print } p && /^}/ { exit }' "$from")"
  if [ -z "$body" ]; then echo "nt_import_fn: no $1 in $from" >&2; return 1; fi
  eval "$body"
}
REPO_ROOT="$BIONIC_SCRIPTS_DIR"
SCRIPT="$REPO_ROOT/payload/scripts/close-out.sh"
PLAN_REL=".bionic/docs/plans/epic-fx/wave-01-fixture.plan.md"
UNITS_LIB="$REPO_ROOT/payload/scripts/lib/units.sh"
SANDBOX="$(cd "$(mktemp -d "$TMPROOT/co.XXXXXX")" && pwd -P)"
SB_HOME="$SANDBOX/home"; mkdir -p "$SB_HOME/.claude"
export GIT_AUTHOR_NAME=fixture GIT_AUTHOR_EMAIL=fixture@example.invalid
export GIT_COMMITTER_NAME=fixture GIT_COMMITTER_EMAIL=fixture@example.invalid
NT_IMPORT_MISSING=""
for _f in in_fixture fixture_git fixture_plan_text fixture_epic_text plant_facts mk_fixture advance_to run_close_as plant_tmp_session; do
  nt_import_fn "$_f" || NT_IMPORT_MISSING="$NT_IMPORT_MISSING $_f"
done
expect_eq "D0 close-out.test.sh's fixture builders were all read out of it" "" "$NT_IMPORT_MISSING"
CO_SIDA="nt-closeout-session-a1a1a1a1"
NT_PLUGIN_ROOT_SAVED="${BIONIC_PLUGIN_ROOT:-}"
channel_on "$SB_HOME/.claude"

PD="$(mk_fixture nt-deliver)"; advance_to "$PD" 8
: > "$NT_CALLS"
run_close_as "$CO_SIDA" "$PD" check
expect_eq "D1 precondition: check reaches the end (exit 0) and sends nothing" "0:0" "$CO_RC:$(nt_calls)"
run_close_as "$CO_SIDA" "$PD" run
expect_eq "D2 the close runs to delivered (exit 0)" "0" "$CO_RC"
expect_contains "D2a …and prints the delivered line" "step9: delivered:" "$CO_OUT"
expect_eq "D3 AC-2.3 the delivered run sent one notification" "1" "$(nt_calls)"
expect_contains "D3a …naming the delivery in its title" "delivered: wave-01-fixture|body=" "$(nt_last)"
expect_contains "D3d …under the channel's title prefix" "title=bionic-fixture" "$(nt_last)"
expect_contains "D3b …and carrying the run's name in the body" "wave-01-fixture" "$(nt_last)"
expect_contains "D3c …to the topic cron.env names, read at send time" "https://ntfy.sh/fixture-topic-123" "$(nt_last)"
run_close_as "$CO_SIDA" "$PD" run
expect_contains "D4 a second run says the run is already closed" "already closed" "$CO_OUT"
expect_eq "D4a …and sends nothing more" "1" "$(nt_calls)"

: > "$NT_CALLS"
channel_off "$SB_HOME/.claude"
PN="$(mk_fixture nt-nochannel)"; advance_to "$PN" 8
run_close_as "$CO_SIDA" "$PN" run
expect_eq "D5 AC-2.5 with no channel the close still delivers (exit 0)" "0" "$CO_RC"
expect_contains "D5a …to the same delivered line" "step9: delivered:" "$CO_OUT"
expect_eq "D5b …and sends nothing" "0" "$(nt_calls)"
expect_eq "D5c …and leaves nothing under .bionic/tmp (no ledger written for a channel nobody declared)" "0" \
  "$(find "$PN/.bionic/tmp" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')"

channel_on "$SB_HOME/.claude"
export NT_CURL_RC=7
PF="$(mk_fixture nt-failing)"; advance_to "$PF" 8
run_close_as "$CO_SIDA" "$PF" run
expect_eq "D6 AC-2.5 a delivery send that fails does not fail the close (exit 0)" "0" "$CO_RC"
expect_contains "D6a …and the delivered line is printed" "step9: delivered:" "$CO_OUT"
expect_eq "D6b …the send was attempted (the failing stub was reached)" "1" "$(nt_calls)"
export NT_CURL_RC=0

# ---- T12: THE WIPE SPARES A LIVE NEIGHBOUR'S LEDGER. `owed` is a session-state class, so
# close-out's tmp wipe keeps a still-running neighbour's open items and removes a dead one's.
channel_off "$SB_HOME/.claude"
CO_SIDB="nt-closeout-session-b2b2b2b2"; CO_SIDD="nt-closeout-session-d4d4d4d4"
PW="$(mk_fixture nt-wipe)"; advance_to "$PW" 8
plant_tmp_session "$PW" "$CO_SIDA"
for _s in "$CO_SIDA" "$CO_SIDB" "$CO_SIDD"; do
  OWED_ROOT="$PW" OWED_SID="$_s" bash -c '. "$1/owed.sh" && owed_open approve:release "approval: release" "Approve release?"' _ "$NT_LIB"
done
sleep 300 &
NT_LIVE_PID=$!
mkdir -p "$SB_HOME/.claude/sessions"
jq -nc --arg sid "$CO_SIDB" --argjson pid "$NT_LIVE_PID" --arg cwd "$PW" '{sessionId:$sid,pid:$pid,cwd:$cwd}' \
  > "$SB_HOME/.claude/sessions/${CO_SIDB}.json"
expect_eq "W0 precondition: all three sessions' stores are planted" "yes yes yes" \
  "$(for _s in $CO_SIDA $CO_SIDB $CO_SIDD; do [ -f "$PW/.bionic/tmp/owed-$_s.state" ] && printf 'yes ' ; done | sed 's/ $//')"
run_close_as "$CO_SIDA" "$PW" run
expect_eq "W1 the close runs (exit 0)" "0" "$CO_RC"
expect_eq "W2 AC-2.3 the live neighbour's owed store survives the wipe" "yes" \
  "$([ -f "$PW/.bionic/tmp/owed-$CO_SIDB.state" ] && echo yes || echo no)"
expect_eq "W2a …with its open item" "approve:release" "$(OWED_ROOT="$PW" OWED_SID="$CO_SIDB" bash -c '. "$1/owed.sh" && owed_list' _ "$NT_LIB" | cut -f1)"
expect_eq "W3 this session's own store is removed, like the rest of its state" "no" \
  "$([ -f "$PW/.bionic/tmp/owed-$CO_SIDA.state" ] && echo yes || echo no)"
expect_eq "W3a …and a dead session's store is removed" "no" \
  "$([ -f "$PW/.bionic/tmp/owed-$CO_SIDD.state" ] && echo yes || echo no)"
kill -9 "$NT_LIVE_PID" 2>/dev/null

# ============================================================
section "§ASKS: a named approval a row waits on opens one item, at the tick and at the dispatch wall (T35; AC-2.2)"
# ============================================================
#
# The tick prints `WAIT <id> — approval:<name>` for a row whose only unmet read is an approval the
# user gives, and the dispatch wall refuses a dispatch of that row naming the approve verb. Both
# open `approve:<name>`, the key the approve verb closes, with the line they printed. A row that
# waits on an approval AND on other work is not yet blocked on the person: it opens nothing.
export CLAUDE_CONFIG_DIR="$NS_CFG"
channel_on "$NS_CFG"
nk_world() {  # <label> -> a repo: armed, bound to a reads table at Step 4, committed, a git user
  local r p; r="$(make_repo "$1")"; new_roster "$r"
  git -C "$r" config user.name "Dana Fixture"
  s47_plan "$r" 2 \
    "| T1 | 4 | build | in flight | implementor | — | 30 | REQ-x | payload/x.sh | active | |" \
    "| T4 | 7 | doc | the release | implementor | — | 15 | REQ-x | CHANGELOG.md | pending | approval:release |" \
    "| T5 | 4 | build | waits on two | implementor | — | 20 | REQ-x | payload/y.sh | pending | approval:doctrine-growth, payload/x.sh |" >/dev/null
  # The commit gate the approve verb's dry commit asks reads the plan's sdlc version and step line.
  p="$r/.bionic/docs/plans/epic-99-fixture/wave-01-fixture.plan.md"
  awk 'NR == 1 { print; print "canonical_sdlc_version: 14"; next }
       $0 == "- Step 4: in progress" { print "- Step 4: T1 dispatched; T4 and T5 wait"; next } { print }' "$p" > "$p.tmp" && mv "$p.tmp" "$p"
  ( cd "$r" && git add -f .bionic/docs && git commit -qm fixture ) >/dev/null 2>&1
  printf '%s' "$r"
}
nk_reply() { nt_owed "$1" owed_list | awk -F'\t' -v k="$2" '$1 == k { print $4 }'; }  # <repo> <key>
RK="$(nk_world nt-ask-approval)"
: > "$NT_CALLS"
poke_pressure "$RK" 8192 1.0 tick
expect_eq "AK1 precondition: the tick prints the release's WAIT, the approval its only unmet read" \
  "poker: WAIT T4 — approval:release" "$(s47_lines WAIT | /usr/bin/grep '^poker: WAIT T4 ')"
expect_contains "AK1a precondition: …and T5's WAIT names its approval beside a row's write" \
  "approval:doctrine-growth" "$(s47_lines WAIT | /usr/bin/grep '^poker: WAIT T5 ')"
NK_KEYS="$(nt_owed "$RK" owed_list | cut -f1)"
expect_contains "AK2 AC-2.2 the WAIT on an approval opens an item keyed approve:<name>, the approve verb's key" \
  "approve:release" "$NK_KEYS"
expect_absent "AK2a …and the row that also waits on other work opens none (same reader)" "approve:doctrine-growth" "$NK_KEYS"
expect_eq "AK2b …carrying the line the tick printed" "poker: WAIT T4 — approval:release" "$(nk_reply "$RK" approve:release)"
expect_eq "AK2c the tick sends nothing for it by itself" "0" "$(nt_calls)"
nt_stop "$RK"
expect_eq "AK3 the Stop that ends the blocked turn sends one notification" "1" "$(nt_calls)"
expect_contains "AK3a …carrying the WAIT line" "body=poker: WAIT T4 — approval:release" "$(nt_last)"
poke_pressure "$RK" 8192 1.0 tick
nt_stop "$RK"
expect_eq "AK4 a later turn on the same unresolved approval sends nothing" "1" "$(nt_calls)"
expect_eq "AK4a …and the store holds one open item for it, not two" "1" \
  "$(nt_owed "$RK" owed_list | cut -f1 | /usr/bin/grep -c '^approve:release$')"
POKE_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
poke "$RK" approve release 'Ship it.'
POKE_BOUND="$POKE_BOUND_WAS"
expect_eq "AK5 the approve verb records the user's reply (exit 0)" "0" "$RC"
[ "$RC" = 0 ] || printf '      the verb said: %s\n' "$OUT"
expect_contains "AK5a …and closes the item it answers" "|key=approve:release|state=closed|by=approve|" \
  "$(cat "$RK/.bionic/tmp/owed-$SID.state" 2>/dev/null)"
poke_pressure "$RK" 8192 1.0 tick
nt_stop "$RK"
expect_eq "AK5b …so the next tick reopens nothing and the next Stop sends nothing" "1" "$(nt_calls)"

# THE DISPATCH WALL. A dispatch of the release row, refused because the approval is not recorded,
# opens the same key with the refusal's own line; a fresh world, so the tick has opened nothing.
RKP="$(nk_world nt-ask-preflight)"
poke_bind "$RKP"
expect_eq "AK6 precondition: the store is empty before the dispatch" "" "$(nt_owed "$RKP" owed_list)"
NK_PAYLOAD=$(jq -nc --arg c "$RKP" --arg s "$SID" \
  '{session_id:$s,cwd:$c,hook_event_name:"PreToolUse",tool_name:"Agent",tool_input:{description:"T4",prompt:"do T4\nRow: T4",subagent_type:"bionic:implementor",name:"w99-T4"}}')
NK_OUT="$( cd "$RKP" && env CLAUDE_PROJECT_DIR="" CLAUDE_CODE_SESSION_ID="$SID" ANTHROPIC_API_KEY=sk-fixture-marker bash "$PREFLIGHT" <<< "$NK_PAYLOAD" 2>&1 )"
expect_contains "AK6a precondition: the wall refuses the dispatch for the approval" "row T4 waits for approval:release" "$NK_OUT"
expect_contains "AK6b AC-2.2 the refusal opens approve:release" "approve:release" "$(nt_owed "$RKP" owed_list | cut -f1)"
expect_contains "AK6c …carrying the refusal's line" "row T4 waits for approval:release" "$(nk_reply "$RKP" approve:release)"
( cd "$RKP" && env CLAUDE_PROJECT_DIR="" CLAUDE_CODE_SESSION_ID="$SID" ANTHROPIC_API_KEY=sk-fixture-marker bash "$PREFLIGHT" <<< "$NK_PAYLOAD" ) >/dev/null 2>&1
expect_eq "AK6d a second refused dispatch on the same approval opens nothing new" "1" \
  "$(/usr/bin/grep -c '|key=approve:release|' "$RKP/.bionic/tmp/owed-$SID.state" 2>/dev/null | tr -d ' ')"

# THE COMMIT WALL'S ASKS (wave-34 T5; REQ-4 AC-4.1, AC-4.2; D14). From Step 6 the evidence gate refuses a commit for
# a question whose newest reading failed, and the matrix arm refuses for a row only the person can let go: a live-tier
# field written n/a, or an auditor's finding a T4 confirmation does not overturn. Each asks the person for a waiver.
# The gate is a pure predicate (the freeze, .claude/rules/hook-authoring.md), so it hands each ask back beside its
# refusal and hooks/bash-walls.sh, the hook that calls it, opens the item, keyed as the answer verb closes it:
# `waive:<question>` (`waive`), `waive-row:<AC>` (`waive-row`). A question with no reading at all asks the run for a
# reading first, not the person, and opens nothing (the tick's own rule, T35's A-T35-4).
# FIXTURE FIDELITY: bash-walls.test.sh's §EG-6 world, its prelude's builders read out of that file by name (a plan the
# real gate admits at current: 6 bar the readings; the reading lines in lib/proof.sh's writer's shape); the real hook.
NT_BW_PRELUDE="$(dirname "$0")/bash-walls.prelude.sh"
NT_IMPORT_MISSING=""
for _f in mk_repo bw_door eg6_plan eg6_reading; do
  nt_import_fn "$_f" "$NT_BW_PRELUDE" || NT_IMPORT_MISSING="$NT_IMPORT_MISSING $_f"
done
expect_eq "AK-6 precondition: the §EG-6 builders were all read out of bash-walls.prelude.sh" "" "$NT_IMPORT_MISSING"
EG6_LIB="$NT_LIB/proof.sh"
CW_HOOK="${BIONIC_HOOKS_DIR}/bash-walls.sh"
RCW="$(mk_repo nt-ask-gate)"
H_EG6="$(git -C "$RCW" rev-parse HEAD)"
cw_commit() {  # <repo> <plan text> -> CW_ERR, CW_RC: a main-checkout `git commit` through the hook, the session bound to the plan
  printf '%s\n' "$2" > "$1/.bionic/docs/plans/active.md"
  bound_marker "$1" "$SID" "$1/.bionic/docs/plans/active.md" >/dev/null 2>&1
  CW_ERR="$(jq -nc --arg s "$SID" --arg c "$1" \
      '{session_id:$s,cwd:$c,hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:"git commit -m x"},tool_use_id:"toolu_nt_ask"}' \
    | ( cd "$1" && env CLAUDE_PROJECT_DIR="" CLAUDE_CODE_SESSION_ID="$SID" bash "$CW_HOOK" 2>&1 >/dev/null ))"
  CW_RC=$?
}
cw_open() { nt_owed "$1" owed_list | cut -f1 | sort | paste -sd, -; }  # <repo> -> the open keys, sorted, comma-joined
CW_READ="$(eg6_reading "$H_EG6" evidence pass)
$(eg6_reading "$H_EG6" adversarial pass)
$(eg6_reading "$H_EG6" structure pass)"
cw_commit "$RCW" "$(eg6_plan 6 wave "$CW_READ")"
expect_eq "AK-6 precondition: the plan with a passing reading of each question is admitted (exit 0)" "0" "$CW_RC"
expect_eq "AK-6p …and opens nothing" "" "$(cw_open "$RCW")"
CW_FAIL="$(eg6_reading "$H_EG6" evidence pass)
$(eg6_reading "$H_EG6" structure fail record/w27/structure-new.md)"
cw_commit "$RCW" "$(eg6_plan 6 wave "$CW_FAIL")"
expect_eq "AK-6a precondition: no adversarial reading and a failing structure one: refused (exit 2)" "2" "$CW_RC"
expect_contains "AK-6b …naming the failing question" "- structure: the newest reading is result=fail" "$CW_ERR"
expect_contains "AK-6c …and the absent one" "- adversarial: no reading, and no waiver" "$CW_ERR"
expect_eq "AK-6 AC-4.1 the question refusal opens waive:structure, the waive verb's key, and nothing for the absent question" \
  "waive:structure" "$(cw_open "$RCW")"
expect_contains "AK-6d …carrying the refusal's line for it" "structure: the newest reading is result=fail (evidence=record/w27/structure-new.md)" \
  "$(nk_reply "$RCW" waive:structure)"
cw_commit "$RCW" "$(eg6_plan 6 wave "$CW_FAIL")"
expect_eq "AK-6e a second refused commit on the same question opens nothing new" "1" \
  "$(/usr/bin/grep -c '|key=waive:structure|' "$RCW/.bionic/tmp/owed-$SID.state" 2>/dev/null | tr -d ' ')"

# THE MATRIX ROW'S ASKS. Every reading passes, so only the matrix speaks. A T3 row whose evidence is n/a is a downgrade
# only the person makes; a T4 row the user confirmed, under a REFUTED auditor cell, needs the finding settled or the row
# waived. Each opens `waive-row:<AC>`.
CW_NA="$(eg6_plan 6 wave "$CW_READ" | sed -e 's/^| AC-1 | T1 | discharged | see AC-1 | CONFIRMED |$/| AC-1 | T3 | discharged | see AC-1 | CONFIRMED |/' \
  -e 's|^  evidence: record/generic-evidence.md$|  evidence: n/a|')"
cw_commit "$RCW" "$CW_NA"
expect_eq "AK-7 precondition: a T3 row whose evidence is n/a is refused (exit 2)" "2" "$CW_RC"
expect_contains "AK-7a …in the matrix arm's words" "AC-1 calls its evidence evidence n/a" "$CW_ERR"
expect_eq "AK-7 AC-4.1 the matrix-row ask opens waive-row:AC-1, the waive-row verb's key" \
  "waive-row:AC-1,waive:structure" "$(cw_open "$RCW")"
expect_contains "AK-7b …carrying the refusal's line" "AC-1 calls its evidence evidence n/a" "$(nk_reply "$RCW" waive-row:AC-1)"
CW_T4="$(eg6_plan 6 wave "$CW_READ" | sed -e 's/AC-1/AC-2/g' \
  -e 's/^| AC-2 | T1 | discharged | see AC-2 | CONFIRMED |$/| AC-2 | T4 | discharged | see AC-2 | REFUTED |/' \
  | awk '{ print } $0 == "  evidence: record/generic-evidence.md" { print "  user-confirmed: Dana 2026-10-01 the fixture works" }')"
cw_commit "$RCW" "$CW_T4"
expect_eq "AK-7c precondition: a user-confirmed T4 row under a REFUTED auditor cell is refused (exit 2)" "2" "$CW_RC"
expect_contains "AK-7d …naming the auditor's finding" "the auditor's finding on AC-2 stands" "$CW_ERR"
expect_eq "AK-7e AC-4.1 that ask opens waive-row:AC-2" "waive-row:AC-1,waive-row:AC-2,waive:structure" "$(cw_open "$RCW")"

# THE ANSWER CLOSES IT. `waive-row` writes the row's waiver on the person's words and closes `waive-row:<AC>`; the
# transcript is the CLI's typed-prompt shape (tests/fixtures/transcript-move), under a config dir of the verb's own, so
# the section's transcript (its planted ListAgents answer) is not the one said.sh reads.
CW_CFG="$(fake_config_dir nt-asks)"
jq -cn --arg c "I waive row AC-1, the live check moved to the next wave" --arg s "$SID" \
  '{type:"user",isSidechain:false,origin:{kind:"human"},promptSource:"typed",message:{role:"user",content:$c},sessionId:$s}' \
  >> "$CW_CFG/projects/-fixture-project/$SID.jsonl"
cw_waive_row() {  # <repo> -> RC, OUT: `waive-row AC-1` on the person's words, under the verb's config dir
  local keep="$CLAUDE_CONFIG_DIR" bound="$POKE_BOUND"
  export CLAUDE_CONFIG_DIR="$CW_CFG"; POKE_BOUND=180
  poke "$1" waive-row AC-1 'I waive row AC-1' 'the live check moved to the next wave'
  export CLAUDE_CONFIG_DIR="$keep"; POKE_BOUND="$bound"
}
printf '%s\n' "$CW_NA" > "$RCW/.bionic/docs/plans/active.md"
cw_waive_row "$RCW"
expect_eq "AK-8 precondition: waive-row records the person's waiver (exit 0)" "0" "$RC"
[ "$RC" = 0 ] || printf '      the verb said: %s\n' "$OUT"
expect_contains "AK-8 AC-4.1 …and closes the item the matrix ask opened" "|key=waive-row:AC-1|state=closed|by=waive-row|" \
  "$(cat "$RCW/.bionic/tmp/owed-$SID.state" 2>/dev/null)"
expect_eq "AK-8a …and no other: the question's and the other row's stay open" "waive-row:AC-2,waive:structure" "$(cw_open "$RCW")"

# WAIVING A QUESTION SETTLES ITS FINDINGS (AC-4.2). `disposition` opens `finding:<record>#<n>` for each finding that
# needs the person ("fix it, defer it, or waive <question>"); `waive <question>` is that answer for every finding of
# the question's readings, so it closes them with `waive:<question>`. A finding of another question stays open.
# FIXTURE FIDELITY: canonical-sdlc-evidence-gate-2.test.sh's §DISPOSITION builders, read out of that file by name
# (a repository on its working branch, reading records in the reader's shape, their proof lines in lib/proof.sh's).
NT_EG2="$(dirname "$0")/canonical-sdlc-evidence-gate-2.test.sh"
NT_IMPORT_MISSING=""
for _f in fp_repo fp_commit fp_plan_path fp_plan fp_record fp_proved fp_landing; do
  nt_import_fn "$_f" "$NT_EG2" || NT_IMPORT_MISSING="$NT_IMPORT_MISSING $_f"
done
expect_eq "AK-9 precondition: the §DISPOSITION builders were all read out of canonical-sdlc-evidence-gate-2.test.sh" "" "$NT_IMPORT_MISSING"
FP_SID="$SID"; FP_LIB="$NT_LIB"; FP_REC="record/wave-01-fixture"
FP_ROOT="$TMPROOT/nt-findings"; mkdir -p "$FP_ROOT"
RFW="$(fp_repo findings)"
FW_B="$(git -C "$RFW" rev-parse HEAD)"
FW_C1="$(fp_commit "$RFW" a.sh one)"
fp_record "$RFW" adv.md adversarial fail "${FW_B:0:10}..${FW_C1:0:10}" 'findings: 1' \
  'finding: 1 S2 on a.sh:1 data lost on a second run' 'shown: 1 bash a.sh; bash a.sh'
fp_record "$RFW" st.md structure fail "${FW_B:0:10}..${FW_C1:0:10}" 'findings: 2' \
  'finding: 1 S2 on b.sh:2 a side path loses data' 'shown: 1 bash b.sh --side' \
  'finding: 2 S1 on b.sh:3 the parser crashes on an empty file' 'shown: 2 bash b.sh < /dev/null'
fp_plan "$RFW" "${FW_B:0:10}" "$(fp_proved "$FW_C1" adv.md adversarial fail)
$(fp_proved "$FW_C1" st.md structure fail)" ""
fp_landing "$RFW" ""
( cd "$RFW" && git add -f .bionic/docs && git commit -qm "the plan and its records" ) >/dev/null 2>&1
bound_marker "$RFW" "$SID" "$(fp_plan_path "$RFW")" >/dev/null 2>&1
FW_KA="finding:record:wave-01-fixture:adv.md:1"
FW_K1="finding:record:wave-01-fixture:st.md:1"
FW_K2="finding:record:wave-01-fixture:st.md:2"
POKE_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
poke "$RFW" disposition
expect_eq "AK-9 precondition: disposition exits 0" "0" "$RC"
[ "$RC" = 0 ] || printf '      the verb said: %s\n' "$OUT"
expect_eq "AK-9a precondition: it opens one item per finding needing the person: two of structure, one of adversarial" \
  "$FW_KA,$FW_K1,$FW_K2" "$(cw_open "$RFW")"
poke "$RFW" waive structure 'ship it as it stands'
POKE_BOUND="$POKE_BOUND_WAS"
expect_eq "AK-9b precondition: waive records the waiver (exit 0)" "0" "$RC"
[ "$RC" = 0 ] || printf '      the verb said: %s\n' "$OUT"
expect_eq "AK-9 AC-4.2 waiving structure closes both of its finding items; adversarial's stays open" "$FW_KA" "$(cw_open "$RFW")"
expect_contains "AK-9c …each closed by the waiver" "|key=$FW_K2|state=closed|by=waive|" "$(cat "$RFW/.bionic/tmp/owed-$SID.state" 2>/dev/null)"

# ============================================================
section "§ASKS mutants: every opener, doctored to open nothing, turns its row red (wave-34 T5; REQ-4 AC-4.5)"
# ============================================================
# One copy of the plugin, hooks/ beside scripts/, so a hook's loader and a script's own lib/ find the copy's library
# first. For each opener, the one call that opens its item is made a no-op (`:` in its place); the copy is shown to
# parse and to differ from the tree under test, the row's own fixture runs against it, and the reading its row asserts
# comes back without the item; then the file is restored from the tree. Each mutant row also reads the act that carries
# the opener (the card's exit, the refusal, the tick's line, the verb's exit), so a copy that died early is not a red.
NM="$TMPROOT/nt-mutant"; mkdir -p "$NM/hooks"
cp -R "$BIONIC_HOOKS_DIR/." "$NM/hooks/"
cp -R "$BIONIC_SCRIPTS_DIR/payload/scripts" "$NM/scripts"
nt_src() { case "$1" in hooks/*) printf '%s/%s' "$BIONIC_HOOKS_DIR" "${1#hooks/}" ;; *) printf '%s/payload/%s' "$BIONIC_SCRIPTS_DIR" "$1" ;; esac; }
nt_doctor() {  # <label> <file under the copy> <call word> <anchor> -> the one line carrying both made a no-op, proved
  local f="$NM/$2" n
  cp "$(nt_src "$2")" "$f"
  n="$(awk -v w="$3" -v a="$4" 'index($0, a) && index($0, w) { n++ } END { print n + 0 }' "$f")"
  W="$3" A="$4" awk 'index($0, ENVIRON["A"]) && (i = index($0, ENVIRON["W"] " ")) { $0 = substr($0, 1, i - 1) ": " substr($0, i + length(ENVIRON["W"]) + 1) } { print }' \
    "$f" > "$f.mut" && cat "$f.mut" > "$f" && rm -f "$f.mut"
  expect_eq "$1 the doctored opener is one line" "1" "$n"
  expect_eq "$1 …the copy parses and differs from the tree's" "0 differs" \
    "$(bash -n "$f" >/dev/null 2>&1; echo "$?") $(cmp -s "$f" "$(nt_src "$2")" && echo same || echo differs)"
}
nt_undo() { cp "$(nt_src "$1")" "$NM/$1"; }  # <file under the copy>

# The commit wall: the hook's one opener, then each ask the gate hands it.
CW_KEEP="$CW_HOOK"; CW_HOOK="$NM/hooks/bash-walls.sh"
nt_doctor "MA-1 [bash-walls.sh opener]" hooks/bash-walls.sh owed_open '"$_bw_key"'
RMA="$(mk_repo nt-mut-hook)"; H_EG6="$(git -C "$RMA" rev-parse HEAD)"
cw_commit "$RMA" "$(eg6_plan 6 wave "$(eg6_reading "$H_EG6" evidence pass)
$(eg6_reading "$H_EG6" adversarial pass)
$(eg6_reading "$H_EG6" structure fail)")"
expect_contains "MA-1a the mutant still refuses the failing question" "- structure: the newest reading is result=fail" "$CW_ERR"
expect_eq "MA-1b AC-4.5 …and AK-6 goes red: no waive:structure item" "" "$(cw_open "$RMA")"
nt_undo hooks/bash-walls.sh
nt_doctor "MA-2 [the question's ask]" scripts/lib/walls.sh _eg_owe '"waive:'
cw_commit "$RMA" "$(eg6_plan 6 wave "$(eg6_reading "$H_EG6" evidence pass)
$(eg6_reading "$H_EG6" adversarial pass)
$(eg6_reading "$H_EG6" structure fail)")"
expect_contains "MA-2a the mutant still refuses the failing question" "- structure: the newest reading is result=fail" "$CW_ERR"
expect_eq "MA-2b AC-4.5 …and AK-6 goes red: no waive:structure item" "" "$(cw_open "$RMA")"
nt_undo scripts/lib/walls.sh
H_EG6="$(git -C "$RCW" rev-parse HEAD)"
nt_doctor "MA-3 [the n/a row's ask]" scripts/lib/walls.sh _eg_owe 'calls its ${key} evidence n/a'
cw_commit "$RMA" "$(printf '%s\n' "$CW_NA" | sed "s/$(git -C "$RCW" rev-parse HEAD)/$(git -C "$RMA" rev-parse HEAD)/g")"
expect_contains "MA-3a the mutant still refuses the n/a row" "AC-1 calls its evidence evidence n/a" "$CW_ERR"
expect_eq "MA-3b AC-4.5 …and AK-7 goes red: no waive-row:AC-1 item" "" "$(cw_open "$RMA")"
nt_undo scripts/lib/walls.sh
nt_doctor "MA-4 [the auditor finding's ask]" scripts/lib/walls.sh _eg_owe 'finding on ${ac} stands'
cw_commit "$RMA" "$(printf '%s\n' "$CW_T4" | sed "s/$(git -C "$RCW" rev-parse HEAD)/$(git -C "$RMA" rev-parse HEAD)/g")"
expect_contains "MA-4a the mutant still refuses the T4 row" "the auditor's finding on AC-2 stands" "$CW_ERR"
expect_eq "MA-4b AC-4.5 …and AK-7e goes red: no waive-row:AC-2 item" "" "$(cw_open "$RMA")"
nt_undo scripts/lib/walls.sh
CW_HOOK="$CW_KEEP"

# The person's other asks: the Step card, the tick's approval WAIT and GATE, the dispatch wall, the disposition, the
# close's delivery. The poker copy finds the copy's library beside it, as the tree's does.
POKER_KEEP="$POKER"; POKER="$NM/hooks/session-poker.sh"
nt_doctor "MA-5 [the tick's approval]" hooks/session-poker.sh owed_open '"approve:$c"'
RMK="$(nk_world nt-mut-approval)"
poke_pressure "$RMK" 8192 1.0 tick
expect_eq "MA-5a the mutant tick still prints the release's WAIT" "poker: WAIT T4 — approval:release" "$(s47_lines WAIT | /usr/bin/grep '^poker: WAIT T4 ')"
expect_absent "MA-5b AC-4.5 …and AK2 goes red: no approve:release item" "approve:release" "$(nt_owed "$RMK" owed_list | cut -f1)"
nt_undo hooks/session-poker.sh
nt_doctor "MA-6 [the tick's GATE]" hooks/session-poker.sh owed_open '"gate:$k"'
RMS="$(nt_world nt-mut-gate)"
gate_line w99-T1 leaves-the-machine "git push origin wave/99-fx" >> "$(gate_of "$RMS")"
poke "$RMS" tick
expect_contains "MA-6a the mutant tick still prints the GATE line" "poker: GATE w99-T1 — leaves-the-machine: git push origin wave/99-fx" "$OUT"
expect_absent "MA-6b AC-4.5 …and S2b goes red: no gate: item" "gate:" "$(nt_owed "$RMS" owed_list | cut -f1)"
nt_undo hooks/session-poker.sh
nt_doctor "MA-7 [the disposition's finding]" hooks/session-poker.sh owed_open '"$(finding_owed_key "$DSP_FID")"'
FP_ROOT="$TMPROOT/nt-mut-findings"; mkdir -p "$FP_ROOT"
RMF="$(fp_repo findings)"
cp -R "$RFW/.bionic/docs/." "$RMF/.bionic/docs/"
( cd "$RMF" && git add -f .bionic/docs && git commit -qm "the plan and its records" ) >/dev/null 2>&1
bound_marker "$RMF" "$SID" "$(fp_plan_path "$RMF")" >/dev/null 2>&1
POKE_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
poke "$RMF" disposition
expect_contains "MA-7a the mutant disposition still renders the open finding" "poker: finding $FP_REC/st.md#2 S1" "$OUT"
expect_eq "MA-7b AC-4.5 …and AK-9a goes red: no finding: item" "" "$(cw_open "$RMF")"
nt_undo hooks/session-poker.sh

# The closers: a waive-row that closes nothing, a waive that closes only waive:<q>.
nt_doctor "MA-8 [waive-row's close]" hooks/session-poker.sh poker_owed_close '"waive-row:'
RMW="$(mk_repo nt-mut-row)"; H_EG6="$(git -C "$RMW" rev-parse HEAD)"
cw_commit "$RMW" "$(printf '%s\n' "$CW_NA" | sed "s/$(git -C "$RCW" rev-parse HEAD)/$H_EG6/g")"
expect_eq "MA-8a precondition: the n/a row's ask is open in the mutant's world" "waive-row:AC-1" "$(cw_open "$RMW")"
cw_waive_row "$RMW"
expect_eq "MA-8b the mutant waive-row still records the waiver (exit 0)" "0" "$RC"
expect_eq "MA-8c AC-4.5 …and AK-8 goes red: the item stays open" "waive-row:AC-1" "$(cw_open "$RMW")"
nt_undo hooks/session-poker.sh
nt_doctor "MA-9 [waive's finding close]" hooks/session-poker.sh poker_owed_close '"$2" "$key" "waive"'
FP_ROOT="$TMPROOT/nt-mut-waive"; mkdir -p "$FP_ROOT"
RMV="$(fp_repo findings)"
cp -R "$RFW/.bionic/docs/." "$RMV/.bionic/docs/"
( cd "$RMV" && git add -f .bionic/docs && git commit -qm "the plan and its records" ) >/dev/null 2>&1
bound_marker "$RMV" "$SID" "$(fp_plan_path "$RMV")" >/dev/null 2>&1
poke "$RMV" disposition
expect_eq "MA-9a precondition: the findings are open in the mutant's world" "$FW_KA,$FW_K1,$FW_K2" "$(cw_open "$RMV")"
poke "$RMV" waive structure 'ship it as it stands'
expect_eq "MA-9b the mutant waive still records the waiver (exit 0)" "0" "$RC"
expect_eq "MA-9c AC-4.5 …and AK-9 goes red: structure's findings stay open" "$FW_KA,$FW_K1,$FW_K2" "$(cw_open "$RMV")"
nt_undo hooks/session-poker.sh
POKE_BOUND="$POKE_BOUND_WAS"
POKER="$POKER_KEEP"

PREFLIGHT_KEEP="$PREFLIGHT"; PREFLIGHT="$NM/hooks/dispatch-preflight.sh"
nt_doctor "MA-10 [the dispatch wall's approval]" hooks/dispatch-preflight.sh owed_open '"approve:${DP_AW_NAME}"'
RMP="$(nk_world nt-mut-preflight)"
poke_bind "$RMP"
NK_OUT="$( cd "$RMP" && env CLAUDE_PROJECT_DIR="" CLAUDE_CODE_SESSION_ID="$SID" ANTHROPIC_API_KEY=sk-fixture-marker bash "$PREFLIGHT" <<< "$(printf '%s' "$NK_PAYLOAD" | jq -c --arg c "$RMP" '.cwd = $c')" 2>&1 )"
expect_contains "MA-10a the mutant wall still refuses the dispatch" "row T4 waits for approval:release" "$NK_OUT"
expect_eq "MA-10b AC-4.5 …and AK6b goes red: no approve:release item" "" "$(nt_owed "$RMP" owed_list | cut -f1)"
nt_undo hooks/dispatch-preflight.sh
PREFLIGHT="$PREFLIGHT_KEEP"

CARD_KEEP="$CARD_SH"; CARD_SH="$NM/scripts/card.sh"
nt_doctor "MA-11 [the Step card]" scripts/card.sh owed_open '"approve:step$n"'
RMC="$(nt_run nt-mut-card)"
nt_card "$RMC" step1 "$(nt_req "$RMC")"
expect_contains "MA-11a the mutant card still prints its question" 'Do you approve these requirements?' "$NT_OUT"
expect_eq "MA-11b AC-4.5 …and N1c goes red: no approve:step1 item" "" "$(nt_owed "$RMC" owed_list | cut -f1)"
nt_undo scripts/card.sh
CARD_SH="$CARD_KEEP"

SCRIPT_KEEP="$SCRIPT"; SCRIPT="$NM/scripts/close-out.sh"
nt_doctor "MA-12 [the close's delivery]" scripts/close-out.sh owed_open '"delivered: $WAVE_SLUG"'
channel_on "$SB_HOME/.claude"
: > "$NT_CALLS"
PMD="$(mk_fixture nt-mut-deliver)"; advance_to "$PMD" 8
run_close_as "$CO_SIDA" "$PMD" run
expect_contains "MA-12a the mutant close still delivers" "step9: delivered:" "$CO_OUT"
expect_eq "MA-12b AC-4.5 …and D3 goes red: no delivery item, so nothing sent" "0" "$(nt_calls)"
nt_undo scripts/close-out.sh
channel_off "$SB_HOME/.claude"
SCRIPT="$SCRIPT_KEEP"

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
# A FAILED SEND IS RETRIED (wave-33 T34; critic finding 3, which reverses A-T11-3). The item is
# marked before its send, and a send that fails takes the mark back, so the next caller sends it:
# one attempt per turn while the channel fails, then exactly one call once it works.
nt_stop "$RF"
expect_eq "A5e a failed send is retried by the next Stop, one attempt per turn" "4" "$(nt_calls)"
expect_eq "A5f …and the item is still owed, unsent, while the channel fails" "approve:release" "$(nt_owed "$RF" owed_unsent)"
export NT_CURL_RC=0
nt_stop "$RF"
expect_eq "A5g with the channel working, the next Stop sends it" "5" "$(nt_calls)"
expect_contains "A5h …that call is the item the failed sends owed" "title=bionic-fixture approval: release|" "$(nt_last)"
expect_eq "A5i …and the item is no longer unsent" "" "$(nt_owed "$RF" owed_unsent)"
nt_stop "$RF"
expect_eq "A5j …and the Stop after it calls nothing: sent once" "5" "$(nt_calls)"
# A caller killed mid-send (the call made, the caller gone before it learns the result) leaves the
# mark, so the item is never sent twice.
nt_owed "$RF" owed_open approve:killed "approval: killed" 'Killed?' >/dev/null
expect_eq "K1 precondition: a second item is owed, unsent" "approve:killed" "$(nt_owed "$RF" owed_unsent)"
NT_CURL_KILL=1 nt_owed "$RF" owed_send
expect_eq "K2 the killed caller made its one call" "6" "$(nt_calls)"
expect_contains "K2a …for that item" "title=bionic-fixture approval: killed|" "$(nt_last)"
expect_eq "K2b …and the item stays marked sent" "" "$(nt_owed "$RF" owed_unsent)"
nt_owed "$RF" owed_send
nt_stop "$RF"
expect_eq "K3 the next caller and the next Stop send it no second time" "6" "$(nt_calls)"
# A LATE TIMEOUT IS A FAILED SEND (wave-34 T5; REQ-4 AC-4.4, D10 "1"). curl's --max-time can expire after ntfy has
# accepted the message (exit 28): the call reached the service and the sender cannot tell whether it landed. It is
# retried like any failure, so the person is told at least once, and may be told twice; never zero times.
nt_owed "$RF" owed_open approve:late "approval: late" 'Late?' >/dev/null
expect_eq "A5k precondition: a third item is owed, unsent" "approve:late" "$(nt_owed "$RF" owed_unsent)"
export NT_CURL_RC=28
nt_stop "$RF"
expect_eq "A5k AC-4.4 the Stop made the call, which the stub accepted and then timed out on (exit 28)" "7" "$(nt_calls)"
expect_contains "A5k1 …for that item" "title=bionic-fixture approval: late|" "$(nt_last)"
expect_eq "A5k2 …and the item is unsent again: a timeout after acceptance proves no delivery" "approve:late" \
  "$(nt_owed "$RF" owed_unsent)"
export NT_CURL_RC=0
nt_stop "$RF"
expect_eq "A5k3 AC-4.4 the next Stop sends it again: at least once" "8" "$(nt_calls)"
expect_contains "A5k4 …the same item" "title=bionic-fixture approval: late|" "$(nt_last)"
expect_eq "A5k5 …and only then is it marked sent" "" "$(nt_owed "$RF" owed_unsent)"
# THE MUTANT: the retry removed (the unmark after a failed send made a no-op, in the §ASKS mutants' copy). The same
# late timeout then leaves the item marked sent, and nothing sends it again: A5k2 and A5k3 go red.
nt_doctor "MA-13 [the retry]" scripts/lib/owed.sh owed_unmark_sent '"$key"'
nt_owed "$RF" owed_open approve:late2 "approval: late2" 'Late again?' >/dev/null
NT_LIB_KEEP="$NT_LIB"; NT_LIB="$NM/scripts/lib"
export NT_CURL_RC=28
nt_owed "$RF" owed_send
export NT_CURL_RC=0
expect_eq "MA-13a the mutant made the late call" "9" "$(nt_calls)"
expect_eq "MA-13b AC-4.4 …and A5k2 goes red: the item stays marked sent" "" "$(nt_owed "$RF" owed_unsent)"
nt_owed "$RF" owed_send
expect_eq "MA-13c …so A5k3 goes red: nothing sends it again" "9" "$(nt_calls)"
NT_LIB="$NT_LIB_KEEP"
nt_undo scripts/lib/owed.sh
nt_owed "$RF" owed_close approve:late2 fixture >/dev/null
# THE TEXTS SAY IT (AC-4.4, a criterion about the wording itself): the ledger and the sender promise at least once,
# and no sentence of either promises a single send. The reader finds the promise sentences (the positive), then the filter.
NT_ONCE_RE='(sends?|sent|send each)[^.;]* once'
nt_sentences() { sed -e 's/^[[:space:]]*#[[:space:]]\{0,1\}//' "$1" | tr '\n' ' ' | tr '.' '\n'; }  # <file> -> one sentence a line
NT_ONCE="$( { nt_sentences "$NT_LIB/owed.sh"; nt_sentences "$NT_LIB/notify.sh"; } | /usr/bin/grep -E -i "$NT_ONCE_RE")"
expect_contains "A5l AC-4.4 owed.sh and notify.sh say a notice is sent at least once (the reader finds the lines)" "at least once" "$NT_ONCE"
expect_eq "A5m …and no sentence of either promises one send" "" "$(printf '%s\n' "$NT_ONCE" | /usr/bin/grep -v 'at least once')"
expect_contains "A5n …each file in its own words: notify.sh" "at least once" "$(/usr/bin/grep -i 'at least once' "$NT_LIB/notify.sh")"
export NT_CURL_RC=7
nt_card "$RF" step1 "$(nt_req "$RF")"
expect_eq "A6 AC-2.5 card.sh exits 0 with a failing channel" "0" "$NT_RC"
POKE_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
poke "$RF" approve release 'Ship it.'
POKE_BOUND="$POKE_BOUND_WAS"
expect_eq "A6a …and so does the answer verb" "0" "$RC"
export NT_CURL_RC=0

# ============================================================
section "§SETUP: setup declares the channel, with consent, and doctor reports it without sending (AC-2.1)"
# ============================================================
# A scratch HOME and a PATH of its own: the real tools doctor and setup run, inert stubs for the ones
# they only ask about, no `claude`, and the counting `curl` of this suite. Nothing ambient is reachable.
NSU_HOME="$TMPROOT/setup-home"; NSU_BIN="$TMPROOT/setup-bin"
mkdir -p "$NSU_HOME" "$NSU_BIN"
for _t in bash sh env cat grep sed awk mkdir rm cp mv chmod stat readlink ls tr head tail sort uniq wc cut jq mktemp find xargs \
          shasum uname date touch diff cmp printf true false sleep dirname basename realpath id ps df sysctl vm_stat git strings; do
  _p="$(command -v "$_t" 2>/dev/null)" && ln -sf "$_p" "$NSU_BIN/$_t"
done
for _t in node pnpm gh rg uv docker aws perl; do
  printf '#!/bin/sh\ncase "$1" in --version) echo 1.0.0 ;; esac\nexit 0\n' > "$NSU_BIN/$_t"; chmod +x "$NSU_BIN/$_t"
done
cp "$NT_BIN/curl" "$NSU_BIN/curl"
NSU_CH="$NSU_HOME/.claude"
nsu() {  # <answers, printf %b> <script> [args...] -> NSU_OUT, NSU_RC
  local answers="$1" script="$2"; shift 2
  NSU_OUT=$(printf '%b' "$answers" | env -i HOME="$NSU_HOME" PATH="$NSU_BIN" SHELL=/bin/zsh TMPDIR="$TMPROOT" \
    BIONIC_SHELL_RC="$NSU_HOME/.zshrc" BIONIC_PLUGIN_ROOT="$BIONIC_SCRIPTS_DIR/payload" \
    CLAUDE_PLUGIN_ROOT="$BIONIC_SCRIPTS_DIR/payload" BIONIC_DOCTOR_PROBE_SECONDS=15 \
    NT_CALLS="$NT_CALLS" NT_CURL_RC="${NT_CURL_RC:-0}" bash "$script" "$@" 2>&1)
  NSU_RC=$?
}
NSU_SETUP="$BIONIC_SCRIPTS_DIR/payload/scripts/setup.sh"
NSU_DOCTOR="$BIONIC_SCRIPTS_DIR/payload/scripts/doctor.sh"
cron_env_only() { mkdir -p "$1"; printf '# fixture cron env\nexport BIONIC_NTFY_TOPIC=fixture-topic-123\n' > "$1/cron.env"; }

nsu "" "$NSU_SETUP" --list
expect_contains "SU0 setup lists the notify item (and the roster read is not empty)" "notify" "$NSU_OUT"
expect_contains "SU0a …beside the items it always listed" "working-principles" "$NSU_OUT"

cron_env_only "$NSU_CH"
: > "$NT_CALLS"
nsu "n\n" "$NSU_SETUP" --only notify
expect_eq "SU1 a no declares nothing" "absent" "$([ -e "$NSU_CH/bionic/notify" ] && echo present || echo absent)"
expect_eq "SU1a …and sends nothing" "0" "$(nt_calls)"
expect_contains "SU1b …and the question was put (a no is an answer to it; an item setup does not know would print no question)" "[y/N]" "$NSU_OUT"
nsu "" "$NSU_SETUP" --only notify
expect_eq "SU1c nobody there to answer (closed input) declares nothing" "absent" "$([ -e "$NSU_CH/bionic/notify" ] && echo present || echo absent)"
expect_eq "SU1d …and sends nothing" "0" "$(nt_calls)"

nsu "y\n" "$NSU_SETUP" --only notify
expect_eq "SU2 AC-2.1 a yes writes the channel file" "present" "$([ -f "$NSU_CH/bionic/notify" ] && echo present || echo absent)"
expect_eq "SU2a …naming where the topic is read from" "topic-from=cron.env:BIONIC_NTFY_TOPIC" \
  "$(/usr/bin/grep '^topic-from=' "$NSU_CH/bionic/notify" 2>/dev/null)"
expect_nonempty "SU2b …and a title prefix" "$(sed -n 's/^title-prefix=//p' "$NSU_CH/bionic/notify" 2>/dev/null)"
expect_eq "SU2c …without the topic itself (it stays where the user keeps it)" "0" \
  "$(/usr/bin/grep -c 'fixture-topic-123' "$NSU_CH/bionic/notify" 2>/dev/null)"
expect_eq "SU2d …and sent exactly one test notification" "1" "$(nt_calls)"
expect_contains "SU2e …to the topic cron.env names" "https://ntfy.sh/fixture-topic-123" "$(nt_last)"
expect_contains "SU2f …a test, saying so" "setup" "$(nt_last)"
expect_eq "SU2g setup exits 0" "0" "$NSU_RC"
NSU_BYTES="$(cksum < "$NSU_CH/bionic/notify")"
nsu "y\n" "$NSU_SETUP" --only notify
expect_eq "SU3 a second run asks nothing and sends nothing" "1" "$(nt_calls)"
expect_eq "SU3a …and leaves the file byte for byte" "$NSU_BYTES" "$(cksum < "$NSU_CH/bionic/notify")"
expect_contains "SU3b …saying it is already declared" "already declared" "$NSU_OUT"
expect_contains "SU3c …and that nothing is left for this item" "nothing left to do for notify" "$NSU_OUT"

rm -rf "$NSU_CH/bionic" "$NSU_CH/cron.env"; : > "$NT_CALLS"
nsu "y\n" "$NSU_SETUP" --only notify
expect_eq "SU4 with no topic in cron.env nothing is declared" "absent" "$([ -e "$NSU_CH/bionic/notify" ] && echo present || echo absent)"
expect_eq "SU4a …nothing is sent" "0" "$(nt_calls)"
expect_contains "SU4b …and the user is told which variable to set" "BIONIC_NTFY_TOPIC" "$NSU_OUT"
expect_eq "SU4c …without failing setup" "0" "$NSU_RC"

cron_env_only "$NSU_CH"; : > "$NT_CALLS"
NT_CURL_RC=7
nsu "y\n" "$NSU_SETUP" --only notify
NT_CURL_RC=0
expect_eq "SU5 a test send that fails still leaves the channel declared" "present" "$([ -f "$NSU_CH/bionic/notify" ] && echo present || echo absent)"
expect_eq "SU5a …the send was attempted once" "1" "$(nt_calls)"
expect_eq "SU5b …setup exits 0" "0" "$NSU_RC"
expect_contains "SU5c …and says the test notification did not go" "did not" "$NSU_OUT"
rm -rf "$NSU_CH/bionic"; : > "$NT_CALLS"

nsu "n\n" "$NSU_SETUP" --all
expect_contains "SU6 the whole-run plan offers the item in its own words (the page a user consents from)" "notification" "$NSU_OUT"

# DOCTOR READS, NEVER SENDS. The stub is proven live above (SU2d counted 1 through this very PATH).
: > "$NT_CALLS"
channel_on "$NSU_CH"
nsu "" "$NSU_DOCTOR"
NSU_DOC_ON="$(printf '%s\n' "$NSU_OUT" | /usr/bin/grep 'notify channel')"
expect_nonempty "SD1 doctor prints a notify channel row (the extractor reads one)" "$NSU_DOC_ON"
expect_contains "SD1a …declared, naming the variable it reads" "BIONIC_NTFY_TOPIC" "$NSU_DOC_ON"
expect_absent "SD1b …and not as unset" "not set" "$NSU_DOC_ON"
expect_eq "SD1c doctor sent nothing" "0" "$(nt_calls)"
channel_off "$NSU_CH"
nsu "" "$NSU_DOCTOR"
NSU_DOC_OFF="$(printf '%s\n' "$NSU_OUT" | /usr/bin/grep 'notify channel')"
expect_nonempty "SD2 with no channel the row is still there" "$NSU_DOC_OFF"
expect_contains "SD2a …saying it is not set, and where it is offered" "not set" "$NSU_DOC_OFF"
expect_contains "SD2b …through setup" "/bionic:setup" "$NSU_DOC_OFF"
expect_eq "SD2c doctor sent nothing" "0" "$(nt_calls)"

# ============================================================
section "§DOCTOR: a topic in cron.env with no channel file is named, with the setup item that writes it (wave-34 T5; REQ-4 AC-4.6)"
# ============================================================
# The walk's machine had BIONIC_NTFY_TOPIC in cron.env and no channel file, so every send was a no-op while the run
# believed it could reach the person. Doctor says so, and names the setup item that writes the channel file.
rm -rf "$NSU_CH/bionic"; cron_env_only "$NSU_CH"
expect_eq "DC0 precondition: notify_declared returns 1 on this machine (no channel file)" "1" \
  "$(env -i HOME="$NSU_HOME" PATH="$NSU_BIN" bash -c '. "$1/notify.sh"; notify_declared; echo "$?"' _ "$NT_LIB")"
: > "$NT_CALLS"
nsu "" "$NSU_DOCTOR"
DC_ROW="$(printf '%s\n' "$NSU_OUT" | /usr/bin/grep -A1 'notify channel')"  # the row and the line under it
expect_eq "DC1 doctor prints the notify channel row and the line under it (the extractor reads two)" "2" "$(printf '%s\n' "$DC_ROW" | /usr/bin/grep -c .)"
expect_contains "DC1a AC-4.6 …saying cron.env carries the topic" "BIONIC_NTFY_TOPIC is in cron.env" "$DC_ROW"
expect_contains "DC1b …that no channel file exists, so nothing is sent" "no channel file exists, so nothing is sent" "$DC_ROW"
expect_contains "DC1c …naming the setup item that writes it" "/bionic:setup's notify item" "$(printf '%s\n' "$DC_ROW" | /usr/bin/grep 'notify channel')"
expect_absent "DC1d …and never as declared (DC1a reads the same row)" "reads BIONIC_NTFY_TOPIC from" "$DC_ROW"
expect_eq "DC1e doctor sent nothing" "0" "$(nt_calls)"

finish
