#!/bin/bash
# Tests for hooks/patrol-revive.sh — THE PATROL SELF-HEAL (epic-19 wave-01, AC-F6,
# design ledger D4).
#
# THE CONTRACT UNDER TEST. The CLI holds its cron table in process memory with no
# file behind it, so a `claude plugin update`, a `/reload-plugins` or a
# `/clear`+resume can delete the Patrol job and NOTHING says so: the stamp keeps
# reading fresh for one stale window, then goes stale where only a dispatch
# attempt or a hand-run doctor would ever look. This Stop hook is the thing that
# looks. On every orchestrator turn end, if a Patrol stamp exists for THIS session
# and is older than one fire window (the poker-interval plus the scheduler's jitter)
# with an idle stretch that long and no tick in it, it refuses the turn in ONE line that
# names the three acts in order: look at the cron table, create the job if it is absent,
# arm. The explanation behind the line is not in the line; `session-poker.sh patrol
# --explain` prints it.
#
# THE THREE STAMP STATES, and why only one of them speaks here:
#   absent  — never armed. Nothing engaged a run on this session, or nothing armed
#             one yet; that is hooks/dispatch-preflight.sh's refusal to make when a
#             dispatch is actually attempted, not a monitor's to raise every turn.
#   fresh   — firings are landing. Silent.
#   stale   — armed, then died. THE refusal.
#
# THE HOOK MUST NOT STAMP. `session-poker.sh arm` would freshen the stamp and
# satisfy the arming wall over a cron table that still holds nothing — a Patrol
# that reads alive and never fires again, which is worse than the state it
# replaced. Group 5 asserts the stamp's mtime is untouched; Group 4 demands the line
# name CronCreate before arm, and the explanation rows demand the rule that a refused
# CronCreate is never followed by arm, for the same reason
# tests/dispatch-preflight.test.sh S21 demands it.
#
# ACCELERATED CLOCK, NEVER A WAIT. The interval is pinned tiny through the
# project's own knob (`poker-interval:` in .bionic/config.yaml) and staleness is
# manufactured by backdating the stamp's mtime — the `s21_backdate` idiom of
# tests/dispatch-preflight.test.sh, borrowed whole. Nothing in this suite sleeps,
# and every fixture lives in its own mktemp project, so there is no clock to
# restore.
#
# Usage: bash tests/patrol-revive.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"
# The one bound-marker builder (wave-23-fixit-1810 T1), for engage_marker below.
. "$(dirname "$0")/lib/bound-marker.sh"

# THE MERGED ENTRY POINT (epic-23 wave-11, T12). This monitor is a FUNCTION now —
# `stop_patrol_revive` in payload/scripts/lib/stop.sh — and the process that runs it is
# hooks/stop.sh. Every fixture below drives that process.
HOOK="${BIONIC_PATROL_REVIVE_UNDER_TEST:-${BIONIC_HOOKS_DIR}/stop.sh}"

# THE SOURCE THE THREE FILE-READING ARMS BELOW ASK (epic-23 wave-11, T12). This
# gate's body lives in payload/scripts/lib/stop.sh now; $HOOK is the process that
# runs it. An arm that reads TEXT reads the library, an arm that DRIVES drives the
# hook, and the two are named separately so neither can silently read the other.
HOOK_SRC="${BIONIC_PATROL_REVIVE_SRC_UNDER_TEST:-${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/stop.sh}"

# pass/fail were pure-rename shadows of the framework's ok/no; the suite's own
# explicit TOTAL=$((TOTAL + 1)) lines (including the ones inside
# expect_quiet/expect_block/expect_reason_names below) are dropped too since
# ok/no already increment it (S7, AC-12). expect_quiet/expect_block/
# expect_reason_names are suite-specific helpers (not owned names) rebuilt on
# the framework's ok/no.

command -v jq >/dev/null 2>&1 || { echo "patrol-revive: jq absent — suite cannot run"; exit 1; }

# THE SUITE IS NOT ALLOWED TO BE VACUOUS. Every silent-pass assertion below reads
# "rc 0 and no stdout", which is exactly what a MISSING hook produces once the
# shell's own 127 is discarded — so an absent or unparsable hook would turn most
# of this file green over nothing. Prove the subject exists and parses before any
# of it runs (.claude/rules/test-harness.md, "Anti-vacuity").
[ -f "$HOOK" ] || { echo "patrol-revive: no hook at $HOOK — suite refuses to run"; exit 1; }
bash -n "$HOOK" || { echo "patrol-revive: $HOOK does not parse — suite refuses to run"; exit 1; }

SID="11111111-2222-3333-4444-555555555555"
OTHER_SID="99999999-8888-7777-6666-555555555555"

# ---------- fixture builders ----------

# A scratch project carrying a .bionic/tmp and a TINY poker-interval, so 2x the
# interval is two seconds and a backdated stamp is decisively stale without any
# wait. No git repository is created: `project_root` answers at the nearest ancestor
# carrying `.bionic/`, which is this directory itself.
#
# AND AN OPEN RUN (bionic 1.4.0, spec AC-7). The hook is registered always-on now, so it
# is delivered on every Stop in every project on the machine, and its first scope
# condition is `active_run` — there is no Patrol to be dead where there is no run. Every
# fixture that expects this monitor to SPEAK therefore needs a plan; §11 below drives the
# paired negative, where the plan is the only thing missing.
# engage_marker <project> <session> — the engagement marker, BOUND to the fixture's own plan
# when it has one (wave-23-fixit-1810, REQ-1, D1). An empty marker beside an open plan is the
# unbound state, whose newest-plan fallback is announced and never acted on: this monitor
# returns there without reading the stamp, so every fixture that means "this session is
# running this wave" binds. A project with no wave-01 plan gets the empty (unbound) marker,
# and Group 9 binds or leaves it unbound on purpose.
engage_marker() {
  local plan="$1/.bionic/docs/plans/wave-01.plan.md"
  if [ -f "$plan" ]; then
    bound_marker "$1" "$2" "$plan"
  else
    : > "$1/.bionic/tmp/engaged-$2.state"
  fi
}

make_env() {  # [interval] -> project dir on stdout
  local dir; dir=$(mktemp -d)
  mkdir -p "$dir/.bionic/tmp" "$dir/.bionic/docs/plans"
  # ENGAGED (task-engaged-session). This monitor asks `engaged_session` before it asks
  # anything else, so a fixture without the marker is silent for a reason that has nothing
  # to do with the stamp under test. An armed Patrol implies an engaged session anyway —
  # SKILL.md arms the Patrol AT engagement — so the marker travels with the stamp in
  # write_stamp below as well. §12 drives the unengaged direction deliberately.
  printf 'poker-interval: %s\n' "${1:-1s}" > "$dir/.bionic/config.yaml"
  cat > "$dir/.bionic/docs/plans/wave-01.plan.md" <<'PRPLAN'
---
canonical_sdlc_version: 14
---

## SDLC State

current: 4

- Step 4: tasks in flight
PRPLAN
  engage_marker "$dir" "$SID"
  printf '%s' "$dir"
}

stamp_path() { printf '%s/.bionic/tmp/patrol-%s.state' "$1" "$2"; }

# The arming record `session-poker.sh arm` writes beside the stamp (bionic 1.3.2, R-13). This
# hook never reads it — it reads the stamp's mtime and nothing else — but Group 7 drives a
# real DISARM tick, and from 1.3.2 a tick DISARMs only on a delivery that POSTDATES this
# session's arming, so the fixture there has to carry one.
armed_path() { printf '%s.armed' "$(stamp_path "$1" "$2")"; }

write_stamp() {  # <project> <session>
  printf 'patrol-stamp/v1|at=2026-08-27T00:00:00Z|session=%s|verb=arm\n' "$2" \
    > "$(stamp_path "$1" "$2")"
  # The engagement marker for the SAME session: a Patrol is armed at engagement, so a
  # stamp without a marker is a state the machine does not produce (task-engaged-session).
  engage_marker "$1" "$2"
}

# THE STAMP A TICK WRITES (wave-20 REQ-6, D6): `verb=tick`, dated when it ran, and its mtime
# set to the same instant. The stop wall now refuses a marker turn unless such a stamp sits at
# or after the marker row, so the rows that describe a Patrol that fired AND ticked plant this
# rather than `write_stamp`'s arm stamp.
write_tick_stamp() {  # <project> <session> <seconds ago>
  printf 'patrol-stamp/v1|at=%s|session=%s|verb=tick\n' "$(pr_iso "$3")" "$2" > "$(stamp_path "$1" "$2")"
  engage_marker "$1" "$2"
  backdate "$(stamp_path "$1" "$2")" "$3"
}

# The `s21_backdate` idiom of tests/dispatch-preflight.test.sh, verbatim in
# behaviour: age is a MTIME, never a sleep.
backdate() {  # <file> <seconds ago>
  local ts
  ts="$(date -v-"$2"S +%Y%m%d%H%M.%S 2>/dev/null || date -d "-$2 seconds" +%Y%m%d%H%M.%S)"
  touch -t "$ts" "$1"
}

mtime_of() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null; }

# ---------- driving the hook ----------

# ---------- the transcript the verdict reads (REQ-1, AC-1.1/1.2/1.3) ----------
#
# THE VERDICT IS AN IDLE-TIME PREDICATE NOW, not a wall-clock threshold: a session cron
# fires only while the session is idle, so a stamp older than one fire window proves
# nothing on its own and the hook goes on to read the transcript for an idle gap. Every
# fixture that expects a NOTICE therefore has to carry a transcript with a real gap in it,
# and the four other shapes below are the fixtures for the busy, tick and unreadable
# verdicts. `transcript_path` used to be the literal /dev/null, which is now the
# `unreadable` case and would have made every blocking assertion in this file advisory.
#
# RELATIVE TO NOW, REBUILT PER DRIVE, for the reason `backdate` exists: the gap has to fall
# AFTER the reference instant, and the reference instant is a stamp this suite backdates by
# between 50 and 4000 seconds. A file written once at suite start would drift out from
# under the later groups. Nothing here sleeps.
# THE LIBRARY DIRECTORY, for the rows that call `patrol_verdict` directly (AC-6.3). Resolved
# the way Group 13's own structural rows resolve it, below.
PR_LIB_DIR_EARLY="${BIONIC_SCRIPTS_DIR}/payload/scripts/lib"
[ -d "$PR_LIB_DIR_EARLY" ] || PR_LIB_DIR_EARLY="${BIONIC_SCRIPTS_DIR}/scripts/lib"
PR_TRANSCRIPT="$(mktemp)"
PR_TRANSCRIPT_MODE=idle

pr_iso() {  # <seconds ago> -> ISO-8601 Z
  date -u -v-"$1"S +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || date -u -d "-$1 seconds" +%Y-%m-%dT%H:%M:%SZ
}

pr_assistant() {  # <seconds ago>
  printf '{"type":"assistant","timestamp":"%s","message":{"role":"assistant","content":[{"type":"text","text":"working"}]}}\n' \
    "$(pr_iso "$1")"
}

pr_user() {  # <seconds ago> <text>
  printf '{"type":"user","timestamp":"%s","message":{"role":"user","content":"%s"}}\n' \
    "$(pr_iso "$1")" "$2"
}

pr_build_transcript() {
  case "$PR_TRANSCRIPT_MODE" in
    # ONE IDLE GAP, OPEN AT THE FAR END. The assistant record is older than any stamp this
    # suite backdates and the user record is a second ago, so the gap the predicate measures
    # is (stamp age - 1s) whatever the fixture chose — decisively past every fire window
    # driven here, and past none that is not.
    idle)   { pr_assistant 10000; pr_user 1 "carry on"; } > "$PR_TRANSCRIPT" ;;
    # ONE CONTINUOUS 2500s TURN: a prompt, then assistant records all the way to now. There
    # is no user record after the prompt, so no idle gap exists to measure and the session
    # was demonstrably working the whole time.
    busy)   { pr_user 2500 "a long piece of work"
              for _pr_s in 2400 2100 1800 1500 1200 900 600 300 120 30 5; do
                pr_assistant "$_pr_s"
              done ; } > "$PR_TRANSCRIPT" ;;
    # A MARKER TURN WHOSE TICK RAN (re-authored, wave-20 REQ-6, D6). The tick stamps before it
    # decides, so a ticked marker row always sits BEFORE the stamp: here the marker fires at
    # -1600s, its tick stamps (the fixture's own stamp, backdated to -1500s by the row that
    # drives this mode), and the session then works without an idle gap to now. The marker is
    # no proof of life on its own any more — the stamp is — and this one is followed by it.
    # The TaskList after the marker keeps `stop_patrol_duties`'s refresh duty discharged, so
    # this verdict's silence stays observable.
    tick)   { pr_assistant 10000
              pr_user 1600 "bionic-patrol session=11111111 — patrol tick"
              printf '{"type":"assistant","timestamp":"%s","message":{"role":"assistant","content":[{"type":"tool_use","name":"TaskList","input":{}}]}}\n' \
                "$(pr_iso 1590)"
              for _pr_s in 1400 1100 800 500 200 5; do pr_assistant "$_pr_s"; done
            } > "$PR_TRANSCRIPT" ;;
    # MARKER TURNS AFTER THE STAMP, AND NO TICK IN THEM (wave-20 REQ-6, AC-6.3). The clock
    # fires — two marker rows, each followed by work — but neither turn ran the tick, so the
    # stamp never moved. A clock that fires without ticking is a dead Patrol; the marker rows
    # used to move the reference instant and read it healthy.
    markers) { pr_assistant 10000
               pr_user 1500 "bionic-patrol session=11111111 — patrol tick"
               pr_assistant 1490
               pr_user 300 "bionic-patrol session=11111111 — patrol tick"
               pr_assistant 290
             } > "$PR_TRANSCRIPT" ;;
    # THE CONTROL FOR `markers`: the same two marker rows, both BEFORE the stamp (each ticked,
    # the stamp written after the second), and unbroken work since.
    ticked) { pr_assistant 10000
              pr_user 2800 "bionic-patrol session=11111111 — patrol tick"
              pr_assistant 2790
              pr_user 2000 "bionic-patrol session=11111111 — patrol tick"
              printf '{"type":"assistant","timestamp":"%s","message":{"role":"assistant","content":[{"type":"tool_use","name":"TaskList","input":{}}]}}\n' \
                "$(pr_iso 1990)"
              for _pr_s in 1600 1200 800 400 5; do pr_assistant "$_pr_s"; done
            } > "$PR_TRANSCRIPT" ;;
    # NO USER RECORD IN THE WINDOW — the first of AC-1.3's three unreadable shapes.
    nouser) { pr_assistant 900; pr_assistant 60; } > "$PR_TRANSCRIPT" ;;
    # A RECORD THAT CANNOT BE DATED — the third.
    notime) printf '{"type":"user","message":{"role":"user","content":"when was this"}}\n' \
              > "$PR_TRANSCRIPT" ;;
    # NO TRANSCRIPT AT ALL — the second.
    none)   rm -f "$PR_TRANSCRIPT" ;;
  esac
}

stdin_for() {  # <cwd> [session] [event] [stop_hook_active]
  pr_build_transcript
  jq -nc --arg c "$1" --arg s "${2:-$SID}" --arg e "${3:-Stop}" --argjson a "${4:-false}" \
    --arg t "$PR_TRANSCRIPT" \
    '{session_id:$s,transcript_path:$t,cwd:$c,
      hook_event_name:$e,stop_hook_active:$a}'
}

# THE ENVIRONMENT AGREES WITH THE PAYLOAD, because on the machine it does (A-probe-2).
# The hook takes its session key from lib/session.sh, env first, and the stamp filename
# is built from it — so a driver that left the runner's own id in the environment would
# have this monitor watching a file the fixture never wrote.
PR_ERRFILE="$(mktemp)"
HOOK_ERR_USER=""
fire() {  # <cwd> [session] [event] [stop_hook_active]
  HOOK_OUT=$(env CLAUDE_CODE_SESSION_ID="${2:-$SID}" bash "$HOOK" \
    <<< "$(stdin_for "$1" "${2:-$SID}" "${3:-Stop}" "${4:-false}")" 2>"$PR_ERRFILE")
  HOOK_RC=$?
  # THE USER STREAM (task 13). The JSON reason on stdout is what every arm below reads;
  # this is the one line a reader is shown, and the AC-E1.3 section at the end asserts it.
  HOOK_ERR_USER=$(cat "$PR_ERRFILE" 2>/dev/null)
}

fire_raw() {  # <stdin-json>
  local _sid; _sid=$(printf '%s' "$1" | jq -r '.session_id // ""' 2>/dev/null) || _sid=""
  HOOK_OUT=$(env CLAUDE_CODE_SESSION_ID="$_sid" bash "$HOOK" <<< "$1" 2>/dev/null); HOOK_RC=$?
}

reason_of()   { printf '%s' "$HOOK_OUT" | jq -r '.reason // ""' 2>/dev/null; }
decision_of() { printf '%s' "$HOOK_OUT" | jq -r '.decision // ""' 2>/dev/null; }

expect_quiet() {  # <label>
  if [ "$HOOK_RC" -eq 0 ] && [ -z "$HOOK_OUT" ]; then
    ok "$1"
  else
    no "$1" "rc=$HOOK_RC stdout=<$HOOK_OUT>"
  fi
}

# A block is the JSON decision payload on stdout with rc 0 — the channel
# hooks/patrol-duties-gate.sh uses, and the one whose `reason` the CLI renders
# into the operator's terminal. That rendering IS the notice AC-F6 asks for:
# there is no second output surface here.
expect_block() {  # <label>
  local d; d=$(decision_of)
  if [ "$HOOK_RC" -ne 0 ]; then
    no "$1" "rc=$HOOK_RC (a JSON block exits 0); stdout=<$HOOK_OUT>"; return
  fi
  if [ "$d" != "block" ]; then
    no "$1" "decision=<$d> expected block; stdout=<$HOOK_OUT>"; return
  fi
  ok "$1"
}

expect_reason_names() {  # <label> <substring>
  local r; r=$(reason_of)
  case "$r" in
    *"$2"*) ok "$1" ;;
    *)      no "$1" "reason does not name <$2>: $r" ;;
  esac
}

section "Group 2: the false-positive guards"

# A stamp belonging to ANOTHER session is not this session's Patrol. Without this
# the hook would raise a dead Patrol on a session that never had one.
D=$(make_env); write_stamp "$D" "$OTHER_SID"; backdate "$(stamp_path "$D" "$OTHER_SID")" 600
fire "$D"; expect_quiet "6: a stale stamp keyed to ANOTHER session is silent"

# SubagentStop is a WORKER's turn ending. A subagent arms no Patrol (SKILL.md
# §Dispatch: "subagents stay timerless"), and blocking its stop would hold a
# worker hostage to its orchestrator's clock — the exact exclusion
# hooks/patrol-duties-gate.sh makes.
D=$(make_env); write_stamp "$D" "$SID"; backdate "$(stamp_path "$D" "$SID")" 600
fire "$D" "$SID" SubagentStop; expect_quiet "7: SubagentStop is silent"

D=$(make_env); write_stamp "$D" "$SID"; backdate "$(stamp_path "$D" "$SID")" 600
fire "$D" "$SID" PreToolUse; expect_quiet "8: a non-Stop payload is silent"

# BLOCKS ONCE. The CLI re-enters the stop with stop_hook_active true after a hook
# blocked it; refusing again wedges a turn with no way out.
D=$(make_env); write_stamp "$D" "$SID"; backdate "$(stamp_path "$D" "$SID")" 600
fire "$D" "$SID" Stop true; expect_quiet "9: stop_hook_active true passes — it blocks once"

# A symlink is not a stamp: the same posture every other .bionic/tmp reader takes.
# It reads as ABSENT, so a hostile repo can close this wall and never open one.
#
# THE LINK ITSELF IS BACKDATED, not only its target, and that is what makes this
# assertion discriminate. `[ -f ]` follows a link to a real file and both `stat -f`
# and `stat -c` read the LINK's own timestamp — so with a fresh link over a stale
# target the hook is silent whether or not the `-L` guard is there, and the test
# would pin nothing. Aged with `touch -h`, dropping the guard blocks.
D=$(make_env); OTHER=$(make_env); write_stamp "$OTHER" "$SID"
backdate "$(stamp_path "$OTHER" "$SID")" 600
ln -s "$(stamp_path "$OTHER" "$SID")" "$(stamp_path "$D" "$SID")"
_lts="$(date -v-600S +%Y%m%d%H%M.%S 2>/dev/null || date -d "-600 seconds" +%Y%m%d%H%M.%S)"
touch -h -t "$_lts" "$(stamp_path "$D" "$SID")"
fire "$D"; expect_quiet "10: a symlinked stamp is silent, never followed"

# No session key, and a key that is not shaped like one: every path this hook
# reads interpolates it, so an unreadable key is an ambiguity, and an ambiguity
# passes.
D=$(make_env); write_stamp "$D" "$SID"; backdate "$(stamp_path "$D" "$SID")" 600
fire_raw "$(jq -nc --arg c "$D" '{session_id:"",cwd:$c,hook_event_name:"Stop",stop_hook_active:false}')"
expect_quiet "11: no session key is silent"

fire_raw "$(jq -nc --arg c "$D" '{session_id:"../../etc",cwd:$c,hook_event_name:"Stop",stop_hook_active:false}')"
expect_quiet "12: a session key carrying path separators is silent"

# No cwd at all: nothing to root the stamp under.
fire_raw "$(jq -nc '{session_id:"11111111-2222-3333-4444-555555555555",cwd:"",hook_event_name:"Stop",stop_hook_active:false}')"
expect_quiet "13: an empty cwd is silent"

# jq itself absent: the hook cannot read its own payload, so it cannot decide.
#
# THE PAYLOAD IS BUILT BEFORE THE RESTRICTED PATH APPLIES (wave-01 S4, AC-11).
# `PATH="$NOJQ" bash "$HOOK" <<< "$(stdin_for "$D")"` is a temporary assignment
# on a simple command, and bash 3.2 has that assignment IN EFFECT while the
# here-string's command substitution is expanded, where bash 5.3 does not.
# `stdin_for` is itself a `jq` call and `jq` is the one program this directory
# deliberately omits — so, measured on this machine, the same line handed the
# hook `{"session_id":…}` under 5.3 and a bare newline under 3.2. Under the
# interpreter ADR-001 pins the fleet to, this assertion was passing on an EMPTY
# payload: a hook that cannot read a payload it was never given, which is a
# different fact from the one the label names.
D=$(make_env); write_stamp "$D" "$SID"; backdate "$(stamp_path "$D" "$SID")" 600
# EVERYTHING BUT jq. The list this started as — nine programs — was short of
# what the hook actually runs (`INPUT=$(cat)` on its first working line), so
# the jq-present control below could not have spoken whatever the hook did.
# A directory that is missing eleven things does not test the absence of one.
NOJQ=$(mktemp -d)
for _b in bash sh cat date stat touch git grep sed awk dirname basename mktemp \
          tr head tail cut find rm ls printf realpath readlink id sort uniq wc env; do
  _p=$(command -v "$_b" 2>/dev/null) && ln -sf "$_p" "$NOJQ/$_b"
done
_PAYLOAD14=$(stdin_for "$D")
# AND THE SESSION KEY IS SET, THE WAY `fire` SETS IT. Without
# CLAUDE_CODE_SESSION_ID the hook resolves no session, matches no stamp and is
# silent on ANY input — measured here — so the call below was silent for that
# reason as much as for the missing jq. Two wrong reasons for one right answer.
if [ -n "$_PAYLOAD14" ]; then
  ok "14a: the jq-absent fixture built a real payload to hand the hook"
else
  no "14a: the jq-absent fixture handed the hook nothing" \
       "14 below would then pass for the wrong reason"
fi
_OUT=$(env CLAUDE_CODE_SESSION_ID="$SID" PATH="$NOJQ" bash "$HOOK" <<< "$_PAYLOAD14" 2>/dev/null); _RC=$?
if [ "$_RC" -eq 0 ] && [ -z "$_OUT" ]; then
  ok "14: jq absent — passes, silent"
else
  no "14: jq absent did not pass silently" "rc=$_RC stdout=<$_OUT>"
fi
# THE PAIRED POSITIVE, on the same payload and the same directory with jq put
# back. Silence is the easiest verdict in the world to get by accident, and
# every other reason this hook could be silent — a stamp the fixture failed to
# plant, a payload the hook rejects for some other reason, a hook that says
# nothing on any input — survives assertion 14 untouched. This is the arm that
# rules them out: change one program on the PATH and the same call speaks.
_jq_real=$(command -v jq 2>/dev/null) && ln -sf "$_jq_real" "$NOJQ/jq"
_OUT14B=$(env CLAUDE_CODE_SESSION_ID="$SID" PATH="$NOJQ" bash "$HOOK" <<< "$_PAYLOAD14" 2>/dev/null); _RC14B=$?
if [ "$_RC14B" -eq 0 ] && [ -n "$_OUT14B" ]; then
  ok "14b: …and with jq put back, that same payload DOES produce a finding"
else
  no "14b: the jq-present control said nothing either — 14 proves nothing" \
       "rc=$_RC14B stdout=<$_OUT14B>"
fi
rm -rf "$NOJQ"

# The poker unreachable on both lanes: no interval, therefore no threshold. A
# monitor that cannot measure has nothing to report — the same direction
# hooks/dispatch-preflight.sh takes for its own staleness half.
D=$(make_env); write_stamp "$D" "$SID"; backdate "$(stamp_path "$D" "$SID")" 600

# THE COPY GOES IN A SHIPPED-SHAPE TREE (duplication F-5, A-52's class). A bare copy of
# hooks/stop.sh in a mktemp'd directory has no scripts/lib beside it, so the loader finds
# no library and the hook steps aside — at rc 0 with an empty stdout, which is letter for
# letter what this assertion reads as "no threshold, no finding". It passed for the wrong
# reason, and it would get worse after the merge rather than better: one of the loader's
# healing candidates is the main checkout's payload/scripts/lib, so once this wave lands
# the bare copy would start loading MAIN's libraries and exercising a different tree than
# the one under test. hooks/ beside scripts/lib/, holding THIS checkout's library, is the
# shape that makes the copy run its own code.
PR_LIB_SRC="${BIONIC_SCRIPTS_DIR}/payload/scripts/lib"
[ -d "$PR_LIB_SRC" ] || PR_LIB_SRC="${BIONIC_SCRIPTS_DIR}/scripts/lib"
PRTREE=$(mktemp -d)
mkdir -p "$PRTREE/hooks" "$PRTREE/scripts/lib" "$PRTREE/cfg"
cp "$PR_LIB_SRC"/*.sh "$PRTREE/scripts/lib/" 2>/dev/null || true
cp "$HOOK" "$PRTREE/hooks/stop.sh"
# AND NO session-poker.sh IN EITHER PLACE THE GATE LOOKS — its own directory first, then
# $CLAUDE_CONFIG_DIR/hooks. That absence is the whole condition under test, so both
# lookups are pointed at directories this fixture built and left pokerless.
# AND THE SESSION KEY IS SET, THE WAY `fire` SETS IT — assertion 14's rule, and the other
# reason this fixture used to be silent. Without CLAUDE_CODE_SESSION_ID the hook resolves no
# session, matches no stamp and says nothing on ANY input, so the absent poker would have
# been the second wrong reason for one right answer.
_OUT=$(env CLAUDE_CODE_SESSION_ID="$SID" CLAUDE_CONFIG_DIR="$PRTREE/cfg" \
         bash "$PRTREE/hooks/stop.sh" <<< "$(stdin_for "$D")" 2>"$PRTREE/.err"); _RC=$?
_ERR=$(cat "$PRTREE/.err" 2>/dev/null)
if [ "$_RC" -eq 0 ] && [ -z "$_OUT" ]; then
  ok "15: no sibling poker — passes, silent (no threshold, no finding)"
else
  no "15: a hook with no poker beside it did not pass silently" "rc=$_RC stdout=<$_OUT>"
fi

# THE LOUD ANCHOR, first half: the copy RAN. A hook that stepped aside at the loader is
# silent too, and the sentence that tells the two apart is the loader's own — it names the
# library it could not read and says the hook is standing down. Emptiness is NOT the test:
# this gate narrates its plan resolution on stderr when it resolves one, which is the copy
# working rather than the copy failing.
case "$_ERR" in
  *"stepping aside"*|*"library "*" not found"*)
    no "15a: the copied hook stepped aside at the loader instead of running" "stderr=<$_ERR>" ;;
  *)
    ok "15a: …with the copy running its own logic, not stepping aside at the loader" ;;
esac

# THE LOUD ANCHOR, second half — the paired positive, on the same tree and the same
# payload with a poker put beside it. Silence is the easiest verdict in the world to get by
# accident; change one file in the directory and the same call must speak.
cp "${BIONIC_HOOKS_DIR}/session-poker.sh" "$PRTREE/hooks/session-poker.sh"
_OUT15B=$(env CLAUDE_CODE_SESSION_ID="$SID" CLAUDE_CONFIG_DIR="$PRTREE/cfg" \
            bash "$PRTREE/hooks/stop.sh" <<< "$(stdin_for "$D")" 2>/dev/null); _RC15B=$?
if [ "$_RC15B" -eq 0 ] && [ -n "$_OUT15B" ]; then
  ok "15b: …and with a poker beside it that same payload DOES produce a finding"
else
  no "15b: the poker-present control said nothing either — 15 proves nothing" \
       "rc=$_RC15B stdout=<$_OUT15B>"
fi
rm -rf "$PRTREE"

section "Group 3: worktree resolution"

# THE STAMP LIVES AT THE MAIN REPOSITORY'S ROOT, always — hooks/session-poker.sh
# writes it there through the same `--git-common-dir` mapping, and a reader that
# rooted a worktree at its own tree would read an absent stamp and go silent for
# every turn a run spends in one. Both directions are driven: the main
# repository's stale stamp IS seen from a worktree cwd, and a stamp planted under
# the worktree's own tree is NOT what gets read.
WTBASE=$(mktemp -d)
WTREPO="$WTBASE/repo"; mkdir -p "$WTREPO"
git -C "$WTREPO" init -q 2>/dev/null
git -C "$WTREPO" config user.email t@example.com
git -C "$WTREPO" config user.name "T"
echo seed > "$WTREPO/README.md"
git -C "$WTREPO" add README.md >/dev/null 2>&1
git -C "$WTREPO" commit -qm seed >/dev/null 2>&1
mkdir -p "$WTREPO/.bionic/tmp" "$WTREPO/.bionic/docs/plans"
# A 300s interval, not the 1s the other groups use. Group 3 has a FRESH stamp on one side
# of every pair, and "fresh" against a 2s limit is a race with the machine: under a
# parallel suite run the stamp this fixture writes can be three seconds old before the
# hook reads it, and assertion 17 then blocks for a reason that is not the one under test.
# Staleness here is an mtime backdated by ten minutes against a two-minute limit, so both
# sides clear the boundary by an order of magnitude rather than by a second.
printf 'poker-interval: 60s\n' > "$WTREPO/.bionic/config.yaml"
# The open run this monitor is scoped by lives at the MAIN repository too — same
# mapping, same reason: a reader rooted at the worktree would find neither.
cat > "$WTREPO/.bionic/docs/plans/wave-01.plan.md" <<'PRWTPLAN'
---
canonical_sdlc_version: 14
---

## SDLC State

current: 4

- Step 4: tasks in flight
PRWTPLAN
WT="$WTBASE/wt"
git -C "$WTREPO" worktree add -q -b pr-wt "$WT" >/dev/null 2>&1

write_stamp "$WTREPO" "$SID"; backdate "$(stamp_path "$WTREPO" "$SID")" 600
fire "$WT"; expect_block "16: a worktree cwd reads the MAIN repository's stale stamp"

# The mirror image: the main stamp is fresh, and a stale one is planted under the
# worktree's own tree. A reader rooted at the worktree would block on a Patrol
# that is firing perfectly.
write_stamp "$WTREPO" "$SID"
mkdir -p "$WT/.bionic/tmp"
write_stamp "$WT" "$SID"; backdate "$(stamp_path "$WT" "$SID")" 600
fire "$WT"; expect_quiet "17: a stale stamp under the WORKTREE's own tree is not read"
rm -rf "$WTBASE"

section "Group 4: what the refusal says, and what decides it"

# THE REFUSAL IS ONE LINE, and the line names no age, no limit and no path: a repeat over the same
# stale stamp has to be the same line, so everything that varies with the stamp lives behind the
# explanation (read below, once), never in the reason. What the hook DECIDES on is the stamp's state
# and the project's own knob, so those are driven by behaviour: a refreshed stamp ends the refusal,
# and the window the age is judged against follows `poker-interval:`.
D=$(make_env 1m); write_stamp "$D" "$SID"; backdate "$(stamp_path "$D" "$SID")" 600
fire "$D"
G4_FIRST="$(reason_of)"

# THE STAMP BY ITS STATE. Refused while it is stale; the very same file touched fresh is silent. A
# silence read after a refusal on the same fixture is the only silence that proves the hook looked
# at the stamp rather than at nothing.
expect_block "18: a stale stamp is refused, with the refusal headline" 
expect_reason_names "18a: …under the refusal's headline" "bionic: stop refused"
touch "$(stamp_path "$D" "$SID")"
fire "$D"; expect_quiet "18b: …and the same stamp refreshed is silent — the state decides, not the file"
backdate "$(stamp_path "$D" "$SID")" 600

# THE THREE ACTS, in the order that is a safety property: `arm` alone freshens the stamp over an
# empty cron table and buys a Patrol that reads alive and never fires, so the line must look
# (CronList) and create (CronCreate) before it stamps (arm), and the creating is conditional on the
# looking. One line, because the CLI prints a reason as its own error line.
fire "$D"
G4_REASON="$(reason_of)"
G4_LINES="$(printf '%s\n' "$G4_REASON" | awk 'END{print NR}')"
G4_PRE="${G4_REASON%%CronList*}"; G4_MID="${G4_REASON%%CronCreate*}"; G4_ARM="${G4_REASON%%; arm*}"
expect_reason_names "19: …it names the CronCreate half, conditional on the looking" "CronCreate if absent"
if [ "$G4_LINES" = 1 ] && [ "${#G4_PRE}" -lt "${#G4_MID}" ] && [ "${#G4_MID}" -lt "${#G4_ARM}" ] \
   && [ "$G4_REASON" != "$G4_ARM" ]; then
  ok "20: …in one line, the acts in order: CronList, CronCreate, then arm"
else
  no "20: the reason is not one line naming CronList, CronCreate, arm in order" "lines=$G4_LINES reason=<$G4_REASON>"
fi

# A REPEAT IS THE SAME LINE. The same stamp, older: an age in the line would make the second refusal
# longer than the first, and the CLI shows the user every one.
backdate "$(stamp_path "$D" "$SID")" 1100
fire "$D"
expect_block "22 meta: the older stamp is refused again"
if [ -n "$G4_FIRST" ] && [ "$(reason_of)" = "$G4_FIRST" ]; then
  ok "22: …and a repeat over the same stale stamp is the identical line"
else
  no "22: a repeat over the same stale stamp differs from the first" "first=<$G4_FIRST> repeat=<$(reason_of)>"
fi

# THE WINDOW IS THE FIRE WINDOW OF THE PROJECT'S OWN KNOB, driven rather than quoted. The knob is 1m,
# so the window is 66s (the interval plus a tenth for the scheduler's jitter). A stamp 40s old is inside
# it and silent; one 90s old is past it and inside twice the interval, which the hook used to judge by,
# so it is refused only by a hook that measures the window. The ages clear both edges by over twenty
# seconds, and no row sleeps.
D=$(make_env 1m); write_stamp "$D" "$SID"; backdate "$(stamp_path "$D" "$SID")" 40
fire "$D"; expect_quiet "22b: a stamp inside the project's fire window (40s of a 1m knob) is silent"
backdate "$(stamp_path "$D" "$SID")" 90
fire "$D"; expect_block "22c: …and one past it (90s), still inside twice the interval, is refused"

# THE EXPLANATION is what the line leaves out, asked for through the poker beside the hook under test.
# It is static text over that poker's own path, so it is read once. Its words are a document's, not a
# computed fact's: the rows below pin the facts a reader acts on, and each needs the verb to have
# printed before an absence or a phrase means anything.
G4_EXPLAIN="$(cd "$(mktemp -d)" && env CLAUDE_CODE_SESSION_ID="$SID" bash "${BIONIC_HOOKS_DIR}/session-poker.sh" patrol --explain 2>&1)"
G4_EXPLAIN_RC=$?
if [ "$G4_EXPLAIN_RC" -eq 0 ] && [ -n "$G4_EXPLAIN" ]; then
  ok "21a meta: patrol --explain prints, rc 0"
else
  no "21a meta: patrol --explain printed nothing or failed" "rc=$G4_EXPLAIN_RC out=<$G4_EXPLAIN>"
fi
explain_names() {  # <label> <substring>
  case "$G4_EXPLAIN" in
    *"$2"*) ok "$1" ;;
    *)      no "$1" "the explanation does not name <$2>" ;;
  esac
}

# The poker it names is the sibling this hook measured against, never a placeholder a model would paste
# into a `command not found` (the resolved-root rule).
explain_names "21: the explanation names the arm act with the poker as an absolute path" "${BIONIC_HOOKS_DIR}/session-poker.sh arm"

# Why the operator is seeing a refusal at all: the cron table is in process memory and a plugin
# update takes it with no file left behind.
explain_names "23: …and the cause the operator can act on" "plugin update"

# 24 retired: that a refusal comes once per turn is row 9's fact (a re-entered stop passes), and the
# line never said it.

section "Group 6: registration"

# A hook with a suite, a run line and no registration is installed, green in its
# own suite, and never fired.
#
# THE CHANNEL MOVED (bionic 1.4.0, task ADOPT, spec AC-7). It was registered in the
# governing skill's frontmatter, which is what made this monitor share the failure mode
# it monitors: three of the four events that kill a Patrol also deregistered the hook,
# silently and at the same moment. It is in hooks/hooks.json now and survives all four —
# so BOTH halves are asserted, because either alone is a wall in the wrong place: a
# lingering frontmatter entry would fire it twice per turn (the CLI does not deduplicate
# across the two manifests), and a missing manifest entry would not fire it at all.
if grep -q '\${CLAUDE_PLUGIN_ROOT}/hooks/stop.sh' \
     "${BIONIC_HOOKS_DIR}/hooks.json"; then
  ok "28: hooks/hooks.json registers the hook, always on"
else
  no "28: the hook is not registered in hooks/hooks.json — it would never fire"
fi
# The REGISTRATION spelling, not any mention: the Patrol section names this hook in prose
# (it is what reports a Patrol death, and the disarm ritual exists because of it), and a
# grep for the bare filename would forbid the documentation along with the duplicate.

# 29: THE ASSERTION THAT WOULD HAVE CAUGHT THIS. The manifest registers
# this hook as a BARE PATH — `command: ${CLAUDE_PLUGIN_ROOT}/hooks/patrol-revive.sh`,
# no interpreter — and that is exactly how the CLI's own hook runner invokes it: a
# shell handed the literal path as the command, which requires the tracked file
# itself to carry the execute bit. Every other assertion in this suite drives the
# hook through `bash "$HOOK"`, which reads the file regardless of its mode bits and
# would stay green even if the tracked file were not executable — the walk that
# found this bug caught it by reproducing the registration exactly, and that is
# what this assertion now does: a bare path handed to `sh -c`, matching
# `sh -c ".../patrol-revive.sh"` verbatim.
sh -c "$HOOK" <<< '{"hook_event_name":"Stop"}' >/dev/null 2>&1
REGISTERED_RC=$?
if [ "$REGISTERED_RC" -ne 126 ]; then
  ok "29: the hook runs when invoked exactly as registered (bare path via sh -c, rc=$REGISTERED_RC)"
else
  no "29: rc=126 (Permission denied) invoking the hook as the manifest registers it — the tracked file lost its execute bit"
fi

section "Group 7: the deliberate stop — a removed stamp is what ends the notice"

# THE NOTICE IS PER-TURN, NOT ONCE PER SESSION, and that is the whole reason
# `session-poker.sh disarm` exists (critic C-2, epic-19 w1 Step 6). `stop_hook_active`
# suppresses the SECOND stop inside ONE turn; it resets at the next turn, so a stamp left
# stale blocks turn after turn with no operator action that stops it — and there is no CLI
# backstop above this hook, because blocks that are one-per-turn are never CONSECUTIVE.
#
# Nothing in production removed a stamp before the disarm verb, so both routine ways a run
# ends its own Patrol — the run-close `CronDelete` and the poker's own DISARM decision —
# produced exactly that unbounded loop. These cases drive it: five turns, five blocks, and
# then the two things that stop it.
POKER_FOR_DISARM="${BIONIC_HOOKS_DIR}/session-poker.sh"

D=$(make_env 1m); write_stamp "$D" "$SID"; backdate "$(stamp_path "$D" "$SID")" 600
G7_BLOCKS=0
for _t in 1 2 3 4 5; do
  fire "$D"
  [ "$(decision_of)" = "block" ] && G7_BLOCKS=$((G7_BLOCKS + 1))
done
if [ "$G7_BLOCKS" -eq 5 ]; then
  ok "30: a stale stamp blocks EVERY turn — five turns, five blocks (the notice is per-turn)"
else
  no "30: the per-turn block is not what this hook does" "blocked $G7_BLOCKS of 5 turns"
fi

# THE CURE, THROUGH THE REAL VERB — never an `rm` in the test, which would pin this suite to
# its own idea of where the stamp lives instead of to the poker that owns it.
( cd "$D" && env CLAUDE_CODE_SESSION_ID="$SID" bash "$POKER_FOR_DISARM" disarm ) >/dev/null 2>&1
G7_RC=$?
if [ "$G7_RC" -eq 0 ] && [ ! -e "$(stamp_path "$D" "$SID")" ]; then
  ok "31: session-poker.sh disarm removes this session's stamp (rc=0)"
else
  no "31: disarm did not remove the stamp" \
       "rc=$G7_RC; still at $(stamp_path "$D" "$SID")"
fi

fire "$D"; expect_quiet "32: …and the very next turn is silent — the forever-block is over"

# THE OTHER PRODUCER, end to end. The poker's own DISARM decision — "the Patrol may stop" —
# is reached on every quiet stretch between dispatch batches, not only at run close. Its
# tick removes the stamp as its last act, so the turn that follows it is silent rather than
# a death notice demanding the re-arm the tick just said was unnecessary.
D=$(make_env 1m)
printf '# bionic session roster — schema roster-state/v1 — machine-local, safe to delete\n' \
  > "$D/.bionic/tmp/roster-$SID.state"
# THE ROSTER IS NO LONGER THE WHOLE PREDICATE (bionic 1.3.2, wave-1.3.2 task 4/4). An empty
# roster on a run that has not delivered is a lull, not a finish, and the tick QUIETs and
# keeps its stamp — so this fixture has to say the run IS delivered to reach the DISARM this
# case is about. `current: 9` with `delivered:` on the Step-9 line is the only spelling
# hooks/session-poker.sh's run_state() accepts.
mkdir -p "$D/.bionic/docs/plans/epic-99"
{
  printf '# fixture plan\n\n## SDLC State\n\nintegration-branch: main\ncurrent: 9\n\n'
  printf -- '- Step 9: delivered: fixture run closed; report: record/fixture/close-out.md\n'
} > "$D/.bionic/docs/plans/epic-99/wave-01.plan.md"
# AND THE ORDERING IS STATED, NOT LEFT TO THE CLOCK. `make_env` plants a second plan at
# `plans/wave-01.plan.md` reading `current: 4`, and which of the two the tick resolves is
# `active_plan`'s newest-by-mtime pick. Both files are written inside the same second, so
# the pick comes down to how `[ "$f" -nt "$plan" ]` breaks a tie — and that is an
# INTERPRETER-DEPENDENT answer: bash 5 compares st_mtimespec to the nanosecond and calls the
# epic-99 plan newer, while bash 3.2 — the /bin/bash macOS ships — compares whole seconds,
# finds neither newer, and keeps the first candidate the walk produced. Measured, two files
# 61µs apart: 3.2.57 says `b -nt a` is FALSE, 5.3.15 says TRUE. Under the system interpreter
# this case therefore resolved the `current: 4` plan, the tick QUIETed on an undelivered run,
# and cases 33 and 34 failed for a reason that has nothing to do with DISARM. Backdating the
# other plan puts five whole seconds between them, which every interpreter agrees about.
backdate "$D/.bionic/docs/plans/wave-01.plan.md" 5
# ARMED THROUGH THE REAL VERB, and dated back, so the plan written a moment ago is a
# delivery that POSTDATES the arming — which is what the tick now requires before it will
# DISARM (R-13, critic C-4). A hand-written stamp alone leaves the session with no arming
# record at all, and the tick QUIETs rather than reaching the decision this case is about.
# ENGAGED (task-engaged-session, 2026-09-03): the poker's `tick` decides nothing in a
# session that never invoked the canonical-sdlc skill, so the one case in this file that
# drives a real tick has to say the session did. `arm`, on the line below, is deliberately
# not guarded and needs no marker.
: > "$D/.bionic/tmp/engaged-$SID.state"
( cd "$D" && env CLAUDE_CODE_SESSION_ID="$SID" bash "$POKER_FOR_DISARM" arm ) >/dev/null 2>&1
backdate "$(armed_path "$D" "$SID")" 600
backdate "$(stamp_path "$D" "$SID")" 600
G7_TICK=$( cd "$D" && env CLAUDE_CODE_SESSION_ID="$SID" CLAUDE_CONFIG_DIR="$D/no-config" \
             bash "$POKER_FOR_DISARM" tick 2>&1 )
case "$G7_TICK" in
  *decision=DISARM*)
    if [ ! -e "$(stamp_path "$D" "$SID")" ]; then
      ok "33: a DISARM tick removes the stamp it wrote — the decision and the disk agree"
    else
      no "33: a DISARM tick left its stamp behind — the death notice fires on the next turn"
    fi
    ;;
  *) no "33: the fixture roster did not reach a DISARM decision" "$G7_TICK" ;;
esac

# THE DEATH NOTICE AFTER A DISARM IS LATE, NEVER ABSENT, and that is what this case has to
# reach. The tick stamps BEFORE it decides (liveness is firings landing), so a DISARM tick
# that left its stamp behind leaves a FRESH one: the session is quiet for one whole stale
# window and only then starts blocking on every turn, forever. A fire taken immediately
# after the tick is therefore silent whether or not the stamp was removed, and would pin
# nothing. Aging whatever survived the tick is what puts the two outcomes apart — with the
# stamp gone there is nothing to age and the hook is silent for good.
if [ -e "$(stamp_path "$D" "$SID")" ]; then
  backdate "$(stamp_path "$D" "$SID")" 600
fi
fire "$D"; expect_quiet "34: …and one stale window later there is still no notice to fire"

# ---------- what the explanation says about the footgun in its own third act ----------
#
# CREATING IS THE REFUSABLE HALF. `CronCreate` is measured non-deterministically refusable by the
# auto-mode classifier, and a model that stamps without it freshens the stamp over an EMPTY cron
# table: a Patrol that reads alive to this hook, to the arming wall and to /bionic:doctor, and never
# fires again. The header argues that this is strictly worse than the death it heals. The line is too
# short to carry the argument (it says "if absent"), so the explanation carries it, and these rows
# hold it there for the reader who acts on it.
D=$(make_env 1m); write_stamp "$D" "$SID"; backdate "$(stamp_path "$D" "$SID")" 600
fire "$D"
expect_block "35: the stale fixture is refused, so there is a refusal to explain"
explain_names "36: the arm act is conditional on the create act in the text itself" \
  "Only once step 2 returned a job"
explain_names "37: …and a refused CronCreate is told to stop, not to arm" \
  "do NOT run step 3"
explain_names "38: …and the deliberate-stop path is named, not left to be guessed" \
  "session-poker.sh disarm"

# ---------- the header's own honesty about its backstop ----------
#
# The retired sentence claimed the CLI overrides this hook "after 8 consecutive blocks".
# It cannot: `stop_hook_active` guarantees exactly one block per turn and the re-entry
# always passes, so the blocks are never consecutive and that override can never engage
# here. A limit accepted against a safety net that does not exist is the thing this pin
# exists to keep out — asserted as a PAIR, so the absence rests on an extractor proven to
# find text in this file.
if grep -q 'never consecutive' "$HOOK_SRC"; then
  ok "39: the header states why the CLI's consecutive-block override cannot engage here"
else
  no "39: the header does not say why the consecutive-block override cannot engage"
fi
if grep -q 'backstop above ours is the CLI' "$HOOK"; then
  no "39b: the header still claims a backstop that cannot fire for this hook"
else
  ok "39b: …and no longer claims that backstop as its own"
fi

finish
