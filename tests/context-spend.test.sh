#!/bin/bash
# Tests for the CONTEXT-SPEND instrument — epic-23 wave-11-lean-spine, task T12,
# ruling R1 ("the suite that does not exist is written FIRST").
#
# WHY THIS FILE EXISTS AT ALL. Census §6.3 measured it: of the four hooks that fire
# on Stop, this was the ONE with no dedicated suite. It was covered only sideways —
# doctor-patrol, cross-gate-agreement, engage, hook-adoption, patrol-duties-gate and
# session-sweep each reach it while asking about something else — so a merge that
# changed its behaviour had thin cover. This suite is the BASELINE the fold is
# proven against: it is committed GREEN against the unmerged `hooks/context-spend.sh`
# and then re-pointed, unchanged in count, at `hooks/stop.sh`.
#
# WHAT THE INSTRUMENT PROMISES (hooks/context-spend.sh header). One line per SDLC
# step boundary, appended to `$HOME/.claude/logs/<slug>/sdlc-audit.md` — outside
# every consuming project tree, incident 0001 — and otherwise SILENCE. It never
# refuses and it never writes stdout, because a Stop hook's stdout can carry a block
# payload.
#
# ── TWO ASSERTIONS HERE RECORD A GAP, NOT A PROMISE ──────────────────────────
#
# §1b and §2b are marked [BASELINE GAP] and they assert what this hook DOES today,
# which is not what the other three Stop hooks do. Measured at this file's authoring
# commit:
#
#     grep -n 'hook_event_name\|stop_hook_active' hooks/context-spend.sh   -> (no output)
#
# The other three open with `[ "$(_jq '.hook_event_name')" = "Stop" ] || exit 0` and
# `[ "$(_jq '.stop_hook_active')" = "true" ] && exit 0`. This one has NEITHER. In
# production that has cost nothing, because `hooks.json` registers it on Stop alone
# and a re-entry Stop finds the state file already carrying the new step — so the
# same-step arm at :267 makes it idempotent by a different route. Both facts are
# asserted below rather than assumed: §5 drives the re-entry idempotence directly.
#
# The gap becomes load-bearing the moment the four fold into one process registered
# on Stop AND SubagentStop (REQ-1f (iv), ADR-004), which is why it is pinned here in
# the baseline instead of being discovered by the merge.
#
# ACCELERATED, NEVER SLEPT. A step boundary is manufactured by seeding the state file
# through the hook itself and then editing the plan's `current:` — the boundary
# detector is a file diff, so nothing here waits on a clock.
#
# FAKE $HOME, ALWAYS. `audit_path` is `$HOME`-rooted by incident 0001, so every
# fixture carries its own HOME and the runner's real `~/.claude/logs` is never
# touched. §4 asserts the write landed inside the fixture HOME and nowhere else.
#
# Usage: bash tests/context-spend.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"

# THE SEAM (S18 precedent, tests/patrol-revive.test.sh:42). Named so that T12's merge
# re-points this whole suite at hooks/stop.sh by setting one variable, and so that the
# differential can drive the ORIGINAL out of a scratch directory.
HOOK="${BIONIC_CONTEXT_SPEND_UNDER_TEST:-${BIONIC_HOOKS_DIR}/context-spend.sh}"

command -v jq >/dev/null 2>&1 || { echo "context-spend: jq absent — suite cannot run"; exit 1; }

# THE SUITE IS NOT ALLOWED TO BE VACUOUS. Nine of the assertions below read "rc 0 and
# nothing appended", which is exactly what a MISSING hook produces. Prove the subject
# exists and parses before any of it runs (memory/no-vacuous-tests-at-authoring).
[ -f "$HOOK" ] || { echo "context-spend: no hook at $HOOK — suite refuses to run"; exit 1; }
bash -n "$HOOK" || { echo "context-spend: $HOOK does not parse — suite refuses to run"; exit 1; }

SID="aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
OTHER_SID="11111111-2222-3333-4444-555555555555"

# ---------- fixture builders ----------

# slug_for — `audit_path`'s own spelling, reproduced here for the one reason
# tests/canonical-sdlc-evidence-gate.test.sh:54 reproduces it: the fixture has to
# name the file it expects BEFORE the hook writes it. Byte-identical to
# hooks/context-spend.sh's `audit_path` body (basename sanitised, cksum of the
# absolute path).
slug_for() {  # <project root> -> <basename>-<cksum>
  local base sum
  base=$(basename "$1" | sed 's/[^A-Za-z0-9._-]/-/g')
  sum=$(printf '%s' "$1" | cksum | cut -d' ' -f1)
  printf '%s-%s' "$base" "$sum"
}

audit_file_for() {  # <fake home> <project root> -> the path the hook will append to
  printf '%s/.claude/logs/%s/sdlc-audit.md' "$1" "$(slug_for "$2")"
}

# A scratch project: an ENGAGED session, one OPEN run, and a plan whose `## SDLC
# State` names a step. No git repository — `project_root` answers at the nearest
# ancestor carrying `.bionic/`, which is this directory itself.
#
# The engagement marker is EMPTY, which is the unbound shape: `session_run` then
# falls back to the newest plan and the hook says so once on stderr. §6 reads that
# line, so the fixture's binding state is deliberate and not incidental.
make_env() {  # [step] -> project dir on stdout
  local dir step
  # RESOLVED (`pwd -P`), because `mktemp -d` hands back a path under /var, which is a
  # symlink to /private/var on this platform, and `project_root` answers with the
  # PHYSICAL path. The audit file's slug is a cksum OF THAT PATH, so a fixture holding
  # the /var spelling would compute a different slug than the hook writes and every
  # append assertion below would read an empty file and call it silence.
  dir=$(cd "$(mktemp -d)" && pwd -P)
  step="${1:-4}"
  mkdir -p "$dir/.bionic/tmp" "$dir/.bionic/docs/plans"
  : > "$dir/.bionic/tmp/engaged-$SID.state"
  cat > "$dir/.bionic/docs/plans/wave-01.plan.md" <<CSPLAN
---
canonical_sdlc_version: 14
---

## SDLC State

current: $step

- Step $step: tasks in flight
CSPLAN
  printf '%s' "$dir"
}

# THE PLAN'S STEP, rewritten in place. This is the whole boundary mechanism: the
# state file holds the step the last Stop saw, the plan holds the step this Stop
# sees, and a difference between them is the boundary.
set_step() {  # <project> <step>
  local p="$1/.bionic/docs/plans/wave-01.plan.md"
  sed -e "s/^current:.*/current: $2/" "$p" > "$p.new" && mv "$p.new" "$p"
}

make_home() { ( cd "$(mktemp -d)" && pwd -P ); }

# A transcript whose LAST assistant entry carries `.message.usage`. Occupancy is
# input + cache_creation + cache_read (the hook's own sum), so the three fields are
# written separately and the expected total is the caller's to compute.
write_transcript() {  # <file> <input> <cache_creation> <cache_read> [model]
  jq -nc --arg m "${5:-claude-opus-5}" \
     --argjson i "$2" --argjson cc "$3" --argjson cr "$4" \
     '{type:"assistant",message:{model:$m,usage:{input_tokens:$i,cache_creation_input_tokens:$cc,cache_read_input_tokens:$cr}}}' \
     > "$1"
}

# ---------- driving the hook ----------

stdin_for() {  # <cwd> <transcript> [session] [event] [stop_hook_active]
  jq -nc --arg c "$1" --arg t "$2" --arg s "${3:-$SID}" \
         --arg e "${4:-Stop}" --argjson a "${5:-false}" \
    '{session_id:$s,transcript_path:$t,cwd:$c,hook_event_name:$e,stop_hook_active:$a}'
}

CS_ERRFILE="$(mktemp)"
HOOK_OUT=""
HOOK_RC=0
HOOK_ERR=""

# THE ENVIRONMENT AGREES WITH THE PAYLOAD (tests/patrol-revive.test.sh:134, A-probe-2).
# The session key comes from lib/session.sh, environment first, and both the engagement
# marker and the state file are keyed by it — so a driver that left the runner's own id
# in the environment would have this instrument measuring a session the fixture never
# created. CLAUDE_PROJECT_DIR is blanked for the matching reason: it is rung 1 of the one
# cwd ladder, and the runner's own value would outrank the fixture's `.cwd`.
fire() {  # <project> <fake home> <transcript> [session] [event] [stop_hook_active]
  HOOK_OUT=$(env HOME="$2" CLAUDE_PROJECT_DIR="" CLAUDE_CODE_SESSION_ID="${4:-$SID}" \
    bash "$HOOK" <<< "$(stdin_for "$1" "$3" "${4:-$SID}" "${5:-Stop}" "${6:-false}")" \
    2>"$CS_ERRFILE")
  HOOK_RC=$?
  HOOK_ERR=$(cat "$CS_ERRFILE" 2>/dev/null)
}

# fire_raw — an arbitrary payload, for the malformed cases. The session key is read
# back out of the payload where there is one, so a payload carrying no session id
# drives the hook with no key in the environment either.
fire_raw() {  # <fake home> <stdin json>
  local _sid
  _sid=$(printf '%s' "$2" | jq -r '.session_id // ""' 2>/dev/null) || _sid=""
  HOOK_OUT=$(env HOME="$1" CLAUDE_PROJECT_DIR="" CLAUDE_CODE_SESSION_ID="$_sid" \
    bash "$HOOK" <<< "$2" 2>"$CS_ERRFILE")
  HOOK_RC=$?
  HOOK_ERR=$(cat "$CS_ERRFILE" 2>/dev/null)
}

audit_lines() {  # <fake home> <project> -> the number of audit lines on disk
  local f
  f=$(audit_file_for "$1" "$2")
  [ -f "$f" ] || { printf '0'; return 0; }
  /usr/bin/grep -c 'context-spend' "$f" 2>/dev/null || printf '0'
}

audit_last() {  # <fake home> <project> -> the last audit line, or the empty string
  local f
  f=$(audit_file_for "$1" "$2")
  [ -f "$f" ] || return 0
  tail -n 1 "$f" 2>/dev/null
}

# expect_silent — the instrument's whole failure mode, asserted as one thing: rc 0,
# nothing on stdout (the header's hard rule — stdout can carry a block payload), and
# not one byte appended to the audit file.
expect_silent() {  # <label> <fake home> <project>
  local n
  n=$(audit_lines "$2" "$3")
  if [ "$HOOK_RC" -eq 0 ] && [ -z "$HOOK_OUT" ] && [ "$n" = "0" ]; then
    ok "$1"
  else
    no "$1" "rc=$HOOK_RC stdout=<$HOOK_OUT> audit-lines=$n"
  fi
}

require_helpers slug_for audit_file_for make_env set_step make_home write_transcript \
                stdin_for fire fire_raw audit_lines audit_last expect_silent

# ─────────────────────────────────────────────────────────────────────────────
section "Group 1: the event — what this hook reads, and what it does not"

# 1a: a Stop at NO boundary is silent. The first Stop a session ever takes seeds the
# state file and says nothing: there is no earlier occupancy to take a delta against,
# so an instrument that spoke here would be inventing its first measurement.
CS_D=$(make_env 4); CS_H=$(make_home); CS_T=$(mktemp)
write_transcript "$CS_T" 1000 200 300
fire "$CS_D" "$CS_H" "$CS_T"
expect_silent "1a: the first Stop of a session seeds the state and is silent" "$CS_H" "$CS_D"

expect_true "1a: …and the seed really was written" \
  test -f "$CS_D/.bionic/tmp/context-spend.state"

# 1b: [BASELINE GAP] A NON-Stop payload is treated exactly like a Stop, because this
# hook reads no `hook_event_name` at all:
#
#     grep -n 'hook_event_name' hooks/context-spend.sh   -> (no output)
#
# The other three Stop hooks exit at their first lines on a foreign event. In
# production this costs nothing — hooks.json registers this one on Stop alone — and it
# is pinned here because the merge of the four into one process registered on Stop AND
# SubagentStop is exactly what makes the missing guard reachable (ADR-004).
CS_D=$(make_env 4); CS_H=$(make_home); CS_T=$(mktemp)
write_transcript "$CS_T" 1000 200 300
fire "$CS_D" "$CS_H" "$CS_T"                       # seed at step 4
set_step "$CS_D" 5
write_transcript "$CS_T" 4000 200 300
fire "$CS_D" "$CS_H" "$CS_T" "$SID" SubagentStop   # boundary, on a foreign event
expect_eq "1b: [BASELINE GAP] a SubagentStop payload at a boundary still appends — no event guard" \
  "1" "$(audit_lines "$CS_H" "$CS_D")"

# ─────────────────────────────────────────────────────────────────────────────
section "Group 2: re-entrancy"

# 2a: a bystander session — engaged marker absent — is silent, whatever the payload
# says. This is the consent boundary: a session that never invoked canonical-sdlc must
# not see a refusal, an advisory, or a STATE WRITE from this hook.
CS_D=$(make_env 4); CS_H=$(make_home); CS_T=$(mktemp)
rm -f "$CS_D/.bionic/tmp/engaged-$SID.state"
write_transcript "$CS_T" 1000 200 300
fire "$CS_D" "$CS_H" "$CS_T"
expect_silent "2a: a bystander session is silent" "$CS_H" "$CS_D"
expect_false "2a: …and no state file was written for it either" \
  test -f "$CS_D/.bionic/tmp/context-spend.state"

# 2b: [BASELINE GAP] `stop_hook_active: true` is not read either:
#
#     grep -n 'stop_hook_active' hooks/context-spend.sh   -> (no output)
#
# A re-entry Stop at a boundary therefore appends, exactly as a first Stop would.
# §5 shows why this has been harmless: the FIRST Stop of the pair already moved the
# state on, so a real re-entry finds the same step and the same-step arm (:267) stops
# it. The gap is only reachable with a payload that re-enters WITHOUT a preceding
# verdict, which is what this fixture builds.
CS_D=$(make_env 4); CS_H=$(make_home); CS_T=$(mktemp)
write_transcript "$CS_T" 1000 200 300
fire "$CS_D" "$CS_H" "$CS_T"                          # seed at step 4
set_step "$CS_D" 5
write_transcript "$CS_T" 4000 200 300
fire "$CS_D" "$CS_H" "$CS_T" "$SID" Stop true         # boundary, re-entry flag set
expect_eq "2b: [BASELINE GAP] stop_hook_active true at a boundary still appends — no re-entrancy guard" \
  "1" "$(audit_lines "$CS_H" "$CS_D")"

# ─────────────────────────────────────────────────────────────────────────────
section "Group 3: an engaged session at a step boundary — the one thing it says"

# 3: THE LINE. Seed at step 4 with 1500 occupied, move the plan to step 5, stop again
# with 4500 occupied: one line, attributed to the step that ENDED, carrying the delta
# across it.
CS_D=$(make_env 4); CS_H=$(make_home); CS_T=$(mktemp)
write_transcript "$CS_T" 1000 200 300                 # 1500 occupied
fire "$CS_D" "$CS_H" "$CS_T"
set_step "$CS_D" 5
write_transcript "$CS_T" 4000 200 300                 # 4500 occupied
fire "$CS_D" "$CS_H" "$CS_T"

expect_status "3: the boundary Stop still exits 0 — this hook never refuses" "0" "$HOOK_RC"
expect_empty "3: …and never writes stdout" "$HOOK_OUT"
expect_eq "3: exactly one line is appended" "1" "$(audit_lines "$CS_H" "$CS_D")"

CS_LINE=$(audit_last "$CS_H" "$CS_D")
expect_contains "3: the line is attributed to the step that ENDED, not the one entered" \
  "context-spend step-4:" "$CS_LINE"
expect_contains "3: …and carries the occupancy the transcript's last usage names" \
  "occupied=4500" "$CS_LINE"
expect_contains "3: …and the delta across the step" "delta=+3000" "$CS_LINE"
expect_contains "3: …and the model" "model=claude-opus-5" "$CS_LINE"
expect_contains "3: …and the plan it measured against" \
  "$CS_D/.bionic/docs/plans/wave-01.plan.md" "$CS_LINE"
expect_regex "3: …in log_v11_finding's line format, timestamped UTC" \
  '^- [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z context-spend step-' \
  "$CS_LINE"

# THE QUOTED LINE (R1). Written to the run's evidence stream so the report can quote a
# real one rather than a paraphrase of the format.
printf 'context-spend baseline line: %s\n' "$CS_LINE" >&2

# 4: THE AUDIT STREAM LIVES OUTSIDE THE PROJECT (incident 0001). $HOME-rooted, so a
# consuming project cannot commit it whatever its .gitignore says.
expect_true "4: the line landed under the fixture HOME" \
  test -f "$(audit_file_for "$CS_H" "$CS_D")"
expect_empty "4: …and nothing named sdlc-audit.md was written inside the project" \
  "$(find "$CS_D" -name 'sdlc-audit.md' 2>/dev/null)"

# ─────────────────────────────────────────────────────────────────────────────
section "Group 4: idempotence — the same boundary twice"

# 5: THE SAME BOUNDARY, TWICE. The second Stop reads the state the first one wrote,
# finds the same step, and says nothing. This is what has made the missing
# `stop_hook_active` guard harmless in production, and it is asserted directly rather
# than argued: one line, not two.
CS_D=$(make_env 4); CS_H=$(make_home); CS_T=$(mktemp)
write_transcript "$CS_T" 1000 200 300
fire "$CS_D" "$CS_H" "$CS_T"
set_step "$CS_D" 5
write_transcript "$CS_T" 4000 200 300
fire "$CS_D" "$CS_H" "$CS_T"
expect_eq "5: the boundary appended one line" "1" "$(audit_lines "$CS_H" "$CS_D")"

write_transcript "$CS_T" 9000 200 300
fire "$CS_D" "$CS_H" "$CS_T"
expect_eq "5: the SAME boundary a second time appends nothing — still one line" \
  "1" "$(audit_lines "$CS_H" "$CS_D")"
expect_status "5: …and the repeat Stop exits 0" "0" "$HOOK_RC"

# 6: A SESSION SWITCH RE-SEEDS rather than diffing against another session's
# occupancy. Two concurrent sessions on one plan must never take a delta against each
# other; the state is keyed by (plan, session) and a foreign key re-seeds in silence.
: > "$CS_D/.bionic/tmp/engaged-$OTHER_SID.state"
write_transcript "$CS_T" 20000 200 300
set_step "$CS_D" 6
fire "$CS_D" "$CS_H" "$CS_T" "$OTHER_SID"
expect_eq "6: a second session at a boundary re-seeds instead of appending" \
  "1" "$(audit_lines "$CS_H" "$CS_D")"

# ─────────────────────────────────────────────────────────────────────────────
section "Group 5: malformed and missing input — silence, exit 0, every time"

# 7: NOT JSON AT ALL.
CS_D=$(make_env 4); CS_H=$(make_home)
fire_raw "$CS_H" 'this is not json {{{'
expect_silent "7: a payload that is not JSON is silent, exit 0" "$CS_H" "$CS_D"

# 8: JSON, BUT EMPTY. No transcript path, so the hook stops at its second line.
CS_D=$(make_env 4); CS_H=$(make_home)
fire_raw "$CS_H" '{}'
expect_silent "8: an empty JSON object is silent, exit 0" "$CS_H" "$CS_D"

# 9: A TRANSCRIPT PATH THAT IS NOT A FILE.
CS_D=$(make_env 4); CS_H=$(make_home)
fire "$CS_D" "$CS_H" "/nonexistent/transcript.jsonl"
expect_silent "9: an absent transcript is silent, exit 0" "$CS_H" "$CS_D"

# 10: A TRANSCRIPT WITH NO USAGE. `fromjson?` swallows the unparsable lines and the
# qualifying-entry filter finds nothing, so there is no occupancy to measure.
CS_D=$(make_env 4); CS_H=$(make_home); CS_T=$(mktemp)
printf 'not json\n{"type":"user","message":{"content":"hi"}}\n' > "$CS_T"
fire "$CS_D" "$CS_H" "$CS_T"
expect_silent "10: a transcript with no assistant usage is silent, exit 0" "$CS_H" "$CS_D"

# 11: A MALFORMED SESSION ID. `bionic_context` blanks the id and returns 1 rather than
# substituting a literal, so nothing interpolates a traversal into the state path
# (REQ-1h, lib/context.sh "ONE GUARD").
CS_D=$(make_env 4); CS_H=$(make_home); CS_T=$(mktemp)
write_transcript "$CS_T" 1000 200 300
fire "$CS_D" "$CS_H" "$CS_T" '../../etc/passwd'
expect_silent "11: a session id outside [A-Za-z0-9_-] is silent, exit 0" "$CS_H" "$CS_D"
expect_empty "11: …and wrote no state file anywhere under the project" \
  "$(find "$CS_D/.bionic/tmp" -name 'context-spend.state' 2>/dev/null)"

# 12: NO PLAN. An engaged session with nothing open has no step boundary to record.
CS_D=$(make_env 4); CS_H=$(make_home); CS_T=$(mktemp)
rm -f "$CS_D/.bionic/docs/plans/wave-01.plan.md"
write_transcript "$CS_T" 1000 200 300
fire "$CS_D" "$CS_H" "$CS_T"
expect_silent "12: an engaged session with no open run is silent, exit 0" "$CS_H" "$CS_D"

# ─────────────────────────────────────────────────────────────────────────────
section "Group 6: the advisory channel"

# 13: THE FALLBACK LINE. An engaged-but-UNBOUND session resolves its run by the
# newest-plan fallback, and this hook says so ONCE — on stderr, never on stdout, for
# the header's reason. This is the hook's only non-audit output, and it is the arm the
# fold reads as an advisory.
CS_D=$(make_env 4); CS_H=$(make_home); CS_T=$(mktemp)
write_transcript "$CS_T" 1000 200 300
fire "$CS_D" "$CS_H" "$CS_T"
expect_contains "13: an unbound session gets the newest-plan fallback advisory on stderr" \
  "context-spend: run resolved by newest-plan fallback" "$HOOK_ERR"
expect_empty "13: …and nothing at all on stdout" "$HOOK_OUT"

finish
