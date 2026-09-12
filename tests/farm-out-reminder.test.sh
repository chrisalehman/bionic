#!/bin/bash
# tests/farm-out-reminder.test.sh — the wall's own suite, written at last
# (epic-23 wave-11-lean-spine, T23/R1).
#
# WHY IT EXISTS, AND WHY IT EXISTS *FIRST*. hooks/farm-out-reminder.sh is the only one
# of the five PreToolUse|Bash walls that answers on STDOUT as JSON rather than by exit 2
# plus stderr, and T23 folds all five into one process. A merge whose baseline is
# "whatever the hook did" cannot tell a repair from a regression, and this wall had no
# suite of its own: its behaviour was covered incidentally by tests/cmd-class.test.sh,
# which owns the CLASSIFIER, not the wire. So the wire is pinned here, against the hook
# as it stands BEFORE the fold, and the fold is then held to it.
#
# WHAT IT COVERS — the wall's two tiers and the four ways it stays silent.
#
#   tier 1  a suite/build/install-class command on the main thread DENIES:
#           hookSpecificOutput.permissionDecision = "deny" on stdout, the one ruled
#           user line on stderr, exit 0. Never exit 2 (ADR-002).
#   tier 2  a production-shaped command NUDGES with hookSpecificOutput.additionalContext,
#           ONCE per (session, class); the second is suppressed.
#   silence a non-Bash payload, a subagent (`agent_type` non-empty), a session that never
#           invoked canonical-sdlc, and a payload that is not JSON at all.
#
# HERMETIC. Every payload is crafted and piped in; the repo is a throwaway directory under
# a mktemp'd sandbox; HOME and BIONIC_PLUGINS_DIR point inside it so the loader cannot
# reach this machine's installed plugin and the audit stream cannot reach this machine's
# real one.
#
# FIXTURE FIDELITY (declared, per .claude memory fixtures-can-pin-away-the-test):
#   * PreToolUse|Bash payload envelope — the shape tests/cmd-class.test.sh pins.
#   * `agent_type` — the field hooks/farm-out-reminder.sh:34 reads to discriminate a
#     subagent from the main thread (epic-08 Q1 spike).
#   * the engagement marker `.bionic/tmp/engaged-<sid>.state` — written by the
#     canonical-sdlc skill, read by every wall in this class.
#   * session ids and commands — SYNTHESIZED.
#
# Usage: bash tests/farm-out-reminder.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"

# THE SEAM IS A VARIABLE, NOT A LITERAL AT EVERY CALL SITE. T23 re-points this one line
# at hooks/bash-walls.sh and the whole suite drives the folded process instead.
HOOK="${BIONIC_HOOKS_DIR}/bash-walls.sh"

SANDBOX="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/farm-out-test.XXXXXX")" && pwd -P)"
cleanup() { rm -rf "$SANDBOX"; }
trap cleanup EXIT

SID="9c8b7a65-4321-4abc-8def-0123456789ab"
SID2="1a2b3c4d-5e6f-4071-8213-445566778899"
FAKE_HOME="$SANDBOX/home"
mkdir -p "$FAKE_HOME"

# ---------- fixtures ----------

# mk_repo <name> <engaged: yes|no> — a project root, armed or not.
mk_repo() {
  local repo="$SANDBOX/$1"
  mkdir -p "$repo/.bionic/tmp"
  [ "$2" = yes ] && : > "$repo/.bionic/tmp/engaged-$SID.state"
  printf '%s' "$repo"
}

# mk_payload <cwd> <command> [tool_name] [agent_type]
mk_payload() {
  jq -n --arg s "$SID" --arg c "$1" --arg cmd "$2" \
        --arg t "${3:-Bash}" --arg a "${4:-}" \
    '{session_id:$s, cwd:$c, hook_event_name:"PreToolUse", tool_name:$t,
      tool_input:{command:$cmd}, tool_use_id:"toolu_01farmout"}
     + (if $a == "" then {} else {agent_type:$a} end)'
}

OUT=""; ERR=""; ST=0
EXTRA_ENV=""
# run_hook <payload> [session id] — drive the wall, capturing all three streams.
#
# THE ENVIRONMENT AGREES WITH THE PAYLOAD. lib/session.sh takes the environment value as
# primary and the payload as a witness, so a driver that left the RUNNER's own session id
# in the environment would have the wall looking for a marker this fixture never wrote,
# and every silence below would be silence for the wrong reason.
run_hook() {
  local payload="$1" sid="${2:-$SID}"
  # shellcheck disable=SC2086  # EXTRA_ENV is this file's own space-free assignments
  OUT=$(printf '%s' "$payload" | env HOME="$FAKE_HOME" \
          BIONIC_PLUGINS_DIR="$SANDBOX/no-plugins" CLAUDE_CODE_SESSION_ID="$sid" \
          CLAUDE_PROJECT_DIR= $EXTRA_ENV bash "$HOOK" 2>"$SANDBOX/.err")
  ST=$?
  ERR=$(cat "$SANDBOX/.err")
  return 0
}

# audit_file <project root> — the $HOME-rooted audit path the wall computes (incident
# 0001: the stream must live where a consuming project cannot commit it). Derived by the
# hook's own rule rather than hard-coded, so a change to the slug fails loudly here.
audit_file() {
  local base sum
  base=$(basename "$1" | sed 's/[^A-Za-z0-9._-]/-/g')
  sum=$(printf '%s' "$1" | cksum | cut -d' ' -f1)
  printf '%s/.claude/logs/%s-%s/sdlc-audit.md' "$FAKE_HOME" "$base" "$sum"
}

setup_section "the engaged and bystander repos"
ENGAGED="$(mk_repo engaged yes)"
PLAIN="$(mk_repo plain no)"
ok "fixtures built: $ENGAGED and $PLAIN"

# ---------------------------------------------------------------------------
section "0 — the anchor: this suite is driving something (A-52)"
#
# HALF THIS FILE ASSERTS SILENCE, and a HOOK path that names nothing is silent too:
# `bash /nonexistent` writes one line to stderr and exits 127, which every "expect_empty"
# below would read as the wall behaving. T10's four vacuous fixtures were exactly this
# shape. So the seam is asserted before it is used, and the wall is shown SPEAKING once
# before it is asked to stay quiet.
expect_true "0a: the hook under test exists at the resolved seam [$HOOK]" test -f "$HOOK"
run_hook "$(mk_payload "$ENGAGED" 'bash tests/run.sh')"
expect_nonempty "0b: …and it answers a tier-1 command, so silence below means silence" "$OUT"

# ---------------------------------------------------------------------------
section "1 — the four silences: this wall has nothing to say"

# A NON-Bash PAYLOAD. The wall reads `.tool_name` and leaves on anything else; the
# matcher makes this unreachable in production, and the arm is what keeps it that way.
run_hook "$(mk_payload "$ENGAGED" 'bash tests/run.sh' Read)"
expect_status "1a: a non-Bash payload exits 0" 0 "$ST"
expect_empty "1a: …writing nothing to stdout" "$OUT"
expect_empty "1a: …and nothing to stderr" "$ERR"

# A SUBAGENT. `agent_type` non-empty is the measured discriminator (epic-08 Q1 spike):
# the whole point of the wall is to move work OFF the orchestrator thread, so the thread
# it moved the work to must not be nudged to move it again.
run_hook "$(mk_payload "$ENGAGED" 'bash tests/run.sh' Bash implementor)"
expect_status "1b: a subagent payload exits 0" 0 "$ST"
expect_empty "1b: …writing nothing to stdout" "$OUT"
expect_empty "1b: …and nothing to stderr" "$ERR"

# AN EMPTY COMMAND.
run_hook "$(mk_payload "$ENGAGED" '')"
expect_status "1c: an empty command exits 0" 0 "$ST"
expect_empty "1c: …silently" "$OUT$ERR"

# A MALFORMED PAYLOAD — not JSON at all. `_jq` answers empty for every field, so the
# `.tool_name` arm above carries it out. Fail-open, and silent about it.
run_hook 'this is not json at all {'
expect_status "1d: a malformed payload exits 0" 0 "$ST"
expect_empty "1d: …writing nothing to stdout" "$OUT"
expect_empty "1d: …and nothing to stderr" "$ERR"

# NOTHING ON STDIN AT ALL.
run_hook ''
expect_status "1e: an empty payload exits 0" 0 "$ST"
expect_empty "1e: …silently" "$OUT$ERR"

# ---------------------------------------------------------------------------
section "2 — the bystander session: nothing applies until bionic is triggered"
#
# Chris, 2026-09-03: "all guardrails imposed by bionic should only apply when exercising
# bionic." The trigger is the engagement marker, and this repo has none. Both tiers are
# driven, because a wall that went quiet on one tier only would look armed from the other.

run_hook "$(mk_payload "$PLAIN" 'bash tests/run.sh')"
expect_status "2a: an unengaged session's tier-1 command exits 0" 0 "$ST"
expect_empty "2a: …with no deny on stdout" "$OUT"
expect_empty "2a: …and no audit line on stderr" "$ERR"

run_hook "$(mk_payload "$PLAIN" 'npx create-thing')"
expect_status "2b: an unengaged session's tier-2 command exits 0" 0 "$ST"
expect_empty "2b: …with no nudge on stdout" "$OUT"
expect_empty "2b: …and nothing on stderr" "$ERR"

expect_false "2c: …and no audit file was written for the bystander project" \
  test -e "$(audit_file "$PLAIN")"

# ---------------------------------------------------------------------------
section "3 — tier 1: the deny, on stdout, at exit 0"
#
# ADR-002 (epic-08 wave-04, ratified 2026-07-20): enforcement lives in stdout JSON only.
# Never exit 2 — the status is what separates this wall from the four beside it, and the
# fold has to keep the distinction rather than average it away.

run_hook "$(mk_payload "$ENGAGED" 'bash tests/run.sh')"
expect_status "3a: a suite-class command on the main thread exits 0" 0 "$ST"
expect_ne "3b: …and NEVER by exit 2 — the status is this wall's whole distinction" "2" "$ST"
expect_eq "3c: …the decision read back off the wire" "deny" \
  "$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)"
expect_eq "3d: …on the PreToolUse event" "PreToolUse" \
  "$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.hookEventName // empty' 2>/dev/null)"

FO_REASON="$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null)"
expect_contains "3e: …the reason opens with the one ruled user line" \
  "bionic: run refused — this command belongs in a subagent (dispatch it with the Agent tool)" \
  "$FO_REASON"
expect_contains "3f: …names the role a suite redirects to" "subagent_type: test-runner" "$FO_REASON"
expect_contains "3g: …and names the sanctioned override" "FARM_OUT_ALLOW=1" "$FO_REASON"
expect_contains "3h: …the user stream carries that same one line" \
  "bionic: run refused — this command belongs in a subagent" "$ERR"
expect_contains "3i: …and the instrument line naming the class" "farm-out [deny] class=suite" "$ERR"

# THE ROLE IS CLASS-KEYED. A build-class command redirects to the implementor, not the
# test-runner — one assertion that the role is read rather than pasted.
run_hook "$(mk_payload "$ENGAGED" 'npm install')"
expect_eq "3j: an install-class command also denies" "deny" \
  "$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)"
expect_contains "3k: …and redirects to the implementor" "subagent_type: implementor" \
  "$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null)"

# ---------------------------------------------------------------------------
section "4 — tier 2: one additionalContext nudge per class per session"

run_hook "$(mk_payload "$ENGAGED" 'cd /tmp && ./build.sh && ./deploy.sh')"
expect_status "4a: a chain-class command exits 0" 0 "$ST"
expect_eq "4b: …nudging on the additionalContext channel" "PreToolUse" \
  "$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.hookEventName // empty' 2>/dev/null)"
FO_CTX="$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)"
expect_contains "4c: …the nudge names the class" "chain-class command on the main thread" "$FO_CTX"
expect_contains "4d: …and says it is advisory" "Advisory only." "$FO_CTX"
expect_empty "4e: …and it is NOT a deny" \
  "$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)"
expect_contains "4f: …with the instrument line on stderr" "farm-out [nudge] class=chain" "$ERR"

# THE SECOND ONE IS SILENT. Once per (session, class) — the state file is the memory.
run_hook "$(mk_payload "$ENGAGED" 'cd /tmp && ./build.sh && ./deploy.sh')"
expect_status "4g: the second chain-class command exits 0" 0 "$ST"
expect_empty "4h: …saying nothing on stdout" "$OUT"
expect_contains "4i: …and recording the suppression" "farm-out [suppressed] class=chain" "$ERR"

# A DIFFERENT CLASS STILL SPEAKS — the key is (session, class), not (session).
run_hook "$(mk_payload "$ENGAGED" 'npx create-thing')"
expect_contains "4j: a different tier-2 class still nudges" "pkg-exec-class command" \
  "$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)"
expect_contains "4k: …recorded under its own class" "farm-out [nudge] class=pkg-exec" "$ERR"

# A DIFFERENT SESSION STILL SPEAKS on a class this one has already spent.
: > "$ENGAGED/.bionic/tmp/engaged-$SID2.state"
run_hook "$(jq -n --arg s "$SID2" --arg c "$ENGAGED" \
  '{session_id:$s,cwd:$c,hook_event_name:"PreToolUse",tool_name:"Bash",
    tool_input:{command:"cd /tmp && ./build.sh && ./deploy.sh"}}')" "$SID2"
expect_contains "4l: a second session gets its own first nudge" "chain-class command" \
  "$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)"

expect_eq "4m: the state file carries one row per (session, class)" "3" \
  "$(grep -c . "$ENGAGED/.bionic/tmp/farm-out.state" 2>/dev/null)"

# ---------------------------------------------------------------------------
section "5 — the sanctioned override, and the config modes"

EXTRA_ENV=""
run_hook "$(mk_payload "$ENGAGED" 'FARM_OUT_ALLOW=1 bash tests/run.sh')"
expect_status "5a: the override exits 0" 0 "$ST"
expect_empty "5a: …with no deny on stdout" "$OUT"
expect_contains "5b: …and is audited by name" "farm-out [override] class=user-sanctioned" "$ERR"

# CHAIN-AWARE (W4's false fire): the token is honoured after a separator too, not only
# in leading position.
run_hook "$(mk_payload "$ENGAGED" 'cd /x && FARM_OUT_ALLOW=1 bash tests/run.sh')"
expect_empty "5c: …honoured mid-chain as well" "$OUT"

# `farm-out-mode: advisory` DOWNGRADES a deny to a nudge.
ADV="$(mk_repo advisory yes)"
printf 'farm-out-mode: advisory\n' > "$ADV/.bionic/config.yaml"
run_hook "$(mk_payload "$ADV" 'bash tests/run.sh')"
expect_empty "5d: under advisory mode a tier-1 command does NOT deny" \
  "$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)"
expect_contains "5e: …it nudges instead" "suite-class command on the main thread" \
  "$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)"
expect_contains "5f: …and the downgrade is audited" "farm-out [deny-downgraded] class=suite" "$ERR"

# `farm-out-mode: off` SILENCES the wall entirely.
OFFREPO="$(mk_repo off yes)"
printf 'farm-out-mode: off\n' > "$OFFREPO/.bionic/config.yaml"
run_hook "$(mk_payload "$OFFREPO" 'bash tests/run.sh')"
expect_status "5g: under off mode the wall exits 0" 0 "$ST"
expect_empty "5h: …saying nothing at all" "$OUT$ERR"

# ---------------------------------------------------------------------------
section "6 — the audit stream: outside the project, and carrying no command text"
#
# Incident 0001: an excerpt of the raw command leaked a live credential into the audit
# file. The payload is `class=<c> mode=<m>` and nothing else — a length bound is not a
# sanitizer, so the assertion is that the command text is ABSENT, not that it is short.

AUD="$(audit_file "$ENGAGED")"
expect_true "6a: the audit file lands under \$HOME, outside the project" test -f "$AUD"
expect_no_match "6b: …never inside the project tree" "$ENGAGED*" "$AUD"
expect_contains "6c: …recording the deny by class and mode" "farm-out deny: class=suite mode=block" \
  "$(cat "$AUD" 2>/dev/null)"
expect_absent "6d: …and carrying no word of the command itself" "tests/run.sh" \
  "$(cat "$AUD" 2>/dev/null)"

SECRETCMD='npm install --token=AAAABBBBCCCCDDDDEEEEFFFF00001111'
run_hook "$(mk_payload "$ENGAGED" "$SECRETCMD")"
expect_absent "6e: a secret in the command never reaches the audit file" "AAAABBBBCCCCDDDD" \
  "$(cat "$AUD" 2>/dev/null)"
expect_contains "6f: …and the deny reason redacts it on the wire" "[REDACTED]" \
  "$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null)"

finish
