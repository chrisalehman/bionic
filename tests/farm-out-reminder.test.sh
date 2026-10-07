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
# FIXTURE FIDELITY (declared, per .claude/rules/test-harness.md, "Fixture fidelity"):
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

# expect_wrap_only <label> <original command> — stdout is the booking wrap ALONE (wave-26 T7,
# D8). An allowed suite command now comes back rewritten into payload/scripts/booked.sh, so a
# row that read "silent" for this wall reads exactly this instead: no deny and no advisory on
# stdout (the object holds nothing but the event name and updatedInput), and the updated
# command is the shim around the ORIGINAL command, byte for byte.
expect_wrap_only() {  # <label> <command> [<options regex after --max-wait; default none>] [<suites; default run\.sh>]
  # Every wrap without a kill limit carries --max-wait (wave-27 T6, AC-8.3), after --quiet.
  local _cmd _s _r="'\\''" _o="${3-} --suites ${4-run\\.sh}"
  expect_eq "$1: …no deny and no advisory beside the booking wrap" '["hookEventName","updatedInput"]' \
    "$(printf '%s' "$OUT" | jq -c '.hookSpecificOutput | keys' 2>/dev/null)"
  _cmd=$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.updatedInput.command // empty' 2>/dev/null)
  expect_regex "$1: …the updated command runs the booking shim" \
    "^bash [^ ]+/scripts/booked\\.sh( --shell [^ ]+)?( --quiet)? --max-wait [0-9]+${_o} -- " "$_cmd"
  _s=${2//\'/$_r}
  expect_eq "$1: …around the original command, byte for byte" "'$_s'" "${_cmd#* -- }"
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
# THIS WALL STAYS SILENT; the only stdout is the booking wrap every allowed suite carries.
expect_wrap_only "1b" 'bash tests/run.sh'
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

run_hook "$(mk_payload "$PLAIN" 'docker run x')"
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
  "bionic: run refused — this command belongs in a subagent (timeout ≤120000 ms, or dispatch it)" \
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
#
# The CHAIN tier-2 arm is retired (wave-24 T11, D12, AC-7.7): a `&&` chain with no tier-1
# segment is never nudged, whatever its heads. Its once-per-class mechanics are pinned here on
# the two tier-2 singles that remain, `docker run` (docker-run) and `git clone`; section 4b pins the
# retirement itself.

ctx_of() { printf '%s' "$OUT" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null; }

run_hook "$(mk_payload "$ENGAGED" 'docker run x')"
expect_status "4a: a tier-2 single exits 0" 0 "$ST"
expect_eq "4b: …nudging on the additionalContext channel" "PreToolUse" \
  "$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.hookEventName // empty' 2>/dev/null)"
FO_CTX="$(ctx_of)"
expect_contains "4c: …the nudge names the class" "docker-run-class command on the main thread" "$FO_CTX"
expect_contains "4d: …and says it is advisory" "Advisory only." "$FO_CTX"
expect_empty "4e: …and it is NOT a deny" \
  "$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)"
expect_contains "4f: …with the instrument line on stderr" "farm-out [nudge] class=docker-run" "$ERR"

# THE SECOND ONE IS SILENT. Once per (session, class) — the state file is the memory.
run_hook "$(mk_payload "$ENGAGED" 'docker run x')"
expect_status "4g: the second docker-run command exits 0" 0 "$ST"
expect_empty "4h: …saying nothing on stdout" "$OUT"
expect_contains "4i: …and recording the suppression" "farm-out [suppressed] class=docker-run" "$ERR"

# A DIFFERENT CLASS STILL SPEAKS — the key is (session, class), not (session).
run_hook "$(mk_payload "$ENGAGED" 'git clone https://example.invalid/r.git')"
expect_contains "4j: a different tier-2 class still nudges" "clone-class command" "$(ctx_of)"
expect_contains "4k: …recorded under its own class" "farm-out [nudge] class=clone" "$ERR"

# A DIFFERENT SESSION STILL SPEAKS on a class this one has already spent.
: > "$ENGAGED/.bionic/tmp/engaged-$SID2.state"
run_hook "$(jq -n --arg s "$SID2" --arg c "$ENGAGED" \
  '{session_id:$s,cwd:$c,hook_event_name:"PreToolUse",tool_name:"Bash",
    tool_input:{command:"docker run x"}}')" "$SID2"
expect_contains "4l: a second session gets its own first nudge" "docker-run-class command" "$(ctx_of)"

expect_eq "4m: the state file carries one row per (session, class)" "3" \
  "$(grep -c . "$ENGAGED/.bionic/tmp/farm-out.state" 2>/dev/null)"

# ---------------------------------------------------------------------------
section "4b — the chain tier-2 arm is retired; tier 1 and the singles stay (wave-24 T11, AC-7.7)"
#
# WHAT WAS WRONG (research R4 §6). The arm nudged any chain of three or more `&&` segments
# with a non-observing head, and the count was a quote-blind split: the notification
# one-liner from the user's own CLAUDE.md plus `&& echo sent` was three segments, and
# `git commit -m "a && b && c"` was three, one of them `git commit -m "a`. Eight of eight
# recent firing transcripts were observation or notification one-liners.
#
# EVERY SILENCE BELOW SITS BESIDE A POSITIVE ON THE SAME EXTRACTOR AND THE SAME WALL, in this
# section: the docker-run single nudges through `ctx_of`, and a tier-1 chain denies through the
# same stdout. Each silent fixture runs on a FRESH farm-out.state, so a class spent earlier
# cannot be what kept it quiet.
FO_STATE="$ENGAGED/.bionic/tmp/farm-out.state"
cp "$FO_STATE" "$SANDBOX/.state.keep"
fresh_state() { rm -f "$FO_STATE"; }

decision_of() { printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null; }

fresh_state
run_hook "$(mk_payload "$ENGAGED" 'docker run x')"
expect_contains "4n: control — a tier-2 single still nudges on a fresh state" \
  "docker-run-class command on the main thread" "$(ctx_of)"

# THE NOTIFICATION ONE-LINER, as the user's CLAUDE.md spells it, and with `&& echo sent`.
NTFY='source ~/.claude/cron.env && curl -s -H "Title: x — y" -H "Priority: high" -d "one line" "https://ntfy.sh/$T"'
for c in "$NTFY" "$NTFY && echo sent" 'git commit -m "a && b"' 'git commit -m "a && b && c"' \
         'git add -A && git commit -m "a && b"' 'git add -A && git commit -m "a && b && c"' \
         "cd x && git commit -m 'a && b && c'" 'cd x && git fetch -q origin develop && git rev-parse HEAD && date'; do
  fresh_state
  run_hook "$(mk_payload "$ENGAGED" "$c")"
  expect_status "4o: a chain with no tier-1 segment exits 0 [$c]" 0 "$ST"
  expect_empty "4p: …and draws no context [$c]" "$(ctx_of)"
  expect_absent "4q: …and no [nudge] on stderr [$c]" "[nudge]" "$ERR"
done

# EVERY CHAIN THE ARM USED TO NUDGE FOR — a production head, a write behind an observer, a
# gh mutation, the lot — is silent now. These are the old 4q/4w/4y/4z2 fixtures, kept so the
# retirement is proved against the shapes the arm existed for.
for c in 'cd /tmp && ./build.sh && ./deploy.sh' 'cd x && git status && rm -rf build' \
         'cd x && gh api -X POST repos/o/r && git log -1' 'cd x && gh pr merge 5 && git log -1' \
         'cd x && mv a b && git log -1' 'cd x && mkdir d && git log -1' \
         'cd x && sort -o f f && git log -1' 'cd x && gh api -f k=v repos/x && git log -1' \
         'cd x && git status && jq . a.json > b.json' 'cd x && git status && date > stamp' \
         'cd x && git status && jq -n "{}" | tee out.json' 'cd x && git status; rm -rf build && date'; do
  fresh_state
  run_hook "$(mk_payload "$ENGAGED" "$c")"
  expect_empty "4r: a chain the retired arm nudged for is silent [$c]" "$(ctx_of)"
  expect_empty "4s: …and is no deny [$c]" "$(decision_of)"
done

# TIER 1 STAYS, in a chain of any length, quoted `&&` and all. The class is read off the
# decision and the instrument line, so a deny that arrived by the wrong route fails here.
for c in 'cd x && make && echo ok' 'cd x && git status && bash tests/a.test.sh' \
         'cd x && make' 'cd x && npm install && git status && date' \
         'cd x && make && echo "a && b && c"' 'echo "a && b" && cd x && bash tests/run.sh'; do
  fresh_state
  run_hook "$(mk_payload "$ENGAGED" "$c")"
  expect_eq "4t: a chain carrying a tier-1 segment denies [$c]" "deny" "$(decision_of)"
  expect_status "4u: …at exit 0, the way this wall denies [$c]" 0 "$ST"
done
fresh_state
run_hook "$(mk_payload "$ENGAGED" 'cd x && make && echo ok')"
expect_contains "4v: a 3-segment chain with a build segment is labelled class=chain" \
  "farm-out [deny] class=chain" "$ERR"
expect_contains "4w: …and redirects to the implementor (the build segment's role)" \
  "subagent_type: implementor" \
  "$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null)"
fresh_state
run_hook "$(mk_payload "$ENGAGED" 'cd x && git status && bash tests/a.test.sh')"
expect_contains "4x: …and one with a suite segment to the test-runner" "subagent_type: test-runner" \
  "$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null)"

# THE COUNT IS READ BY THE QUOTE-AWARE SEGMENTER. `make` behind two quoted `&&` is a
# 2-segment command, not a chain: whole-command tier 1 labels it by its class. Before the
# fix the quoted `&&`s made it a 4-segment chain and the label read class=chain.
fresh_state
run_hook "$(mk_payload "$ENGAGED" 'make "a && b && c"')"
expect_contains "4y: quoted && do not make a chain — the whole command keeps its class" \
  "farm-out [deny] class=build" "$ERR"

# wave-25 T12: A NAME IS READ THE WAY THE MACHINE RESOLVES IT. On a case-blind filesystem
# `GIT clone` runs git and `BASH tests/run.sh` runs the suite, so each capitalised form is
# the class its lower-case form is: the same nudge, the same deny, the same instrument line.
# Each pair runs on a fresh state, the lower-case control first.
for _fo12 in 'clone|git clone https://x/r.git|GIT clone https://x/r.git' \
             'docker-run|docker run x|DOCKER run x' 'docker-run|docker pull x|Docker pull x' \
             'docker-run|sudo docker run x|SUDO Docker run x' \
             'docker-run|docker run "a b"|DOCKER run "a b"'; do
  IFS='|' read -r _cls _lo _up <<< "$_fo12"
  fresh_state
  run_hook "$(mk_payload "$ENGAGED" "$_lo")"
  expect_contains "4z: control — [$_lo] nudges as $_cls" "farm-out [nudge] class=$_cls" "$ERR"
  fresh_state
  run_hook "$(mk_payload "$ENGAGED" "$_up")"
  expect_contains "4z: [$_up] nudges as $_cls, exactly as [$_lo]" "farm-out [nudge] class=$_cls" "$ERR"
  expect_contains "4z: …on the context channel" "$_cls-class command" "$(ctx_of)"
done
for _fo12 in 'suite|bash tests/run.sh|BASH tests/run.sh' 'build|sudo make|SUDO MAKE' \
             'install|npm install|NPM install' 'suite|env pytest|ENV Pytest'; do
  IFS='|' read -r _cls _lo _up <<< "$_fo12"
  fresh_state
  run_hook "$(mk_payload "$ENGAGED" "$_lo")"
  expect_contains "4z2: control — [$_lo] denies as $_cls" "farm-out [deny] class=$_cls" "$ERR"
  fresh_state
  run_hook "$(mk_payload "$ENGAGED" "$_up")"
  expect_eq "4z2: [$_up] denies, exactly as [$_lo]" "deny" "$(decision_of)"
  expect_contains "4z2: …as class=$_cls" "farm-out [deny] class=$_cls" "$ERR"
done
# ONLY THE WORD FOLDS, and a longer word is its own program: GITK is not git.
fresh_state
run_hook "$(mk_payload "$ENGAGED" 'GITK clone x')"
expect_empty "4z3: GITK clone draws no clone nudge (beside 4z's positive)" "$(ctx_of)"
cp "$SANDBOX/.state.keep" "$FO_STATE"

# ---------------------------------------------------------------------------
section "5 — the sanctioned override, and the config modes"

EXTRA_ENV=""
run_hook "$(mk_payload "$ENGAGED" 'FARM_OUT_ALLOW=1 bash tests/run.sh')"
expect_status "5a: the override exits 0" 0 "$ST"
# THE OVERRIDE LIFTS THIS WALL'S DENY, NOT THE BOOKING (wave-26 T7): it sanctions running a
# suite on the orchestrator thread, and that run still takes a place like any other.
expect_wrap_only "5a" 'FARM_OUT_ALLOW=1 bash tests/run.sh'
expect_contains "5b: …and is audited by name" "farm-out [override] class=user-sanctioned" "$ERR"

# CHAIN-AWARE (W4's false fire): the token is honoured after a separator too, not only
# in leading position.
run_hook "$(mk_payload "$ENGAGED" 'cd /x && FARM_OUT_ALLOW=1 bash tests/run.sh')"
# The leading literal `cd` is where the suite runs, so the shim stamps there (wave-26 T56).
expect_wrap_only "5c honoured mid-chain as well" 'cd /x && FARM_OUT_ALLOW=1 bash tests/run.sh' ' --stamp-dir /x'

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
# `off` silences THIS wall; the booking wrap is not farm-out's and rides the allowed call.
expect_wrap_only "5h saying nothing at all" 'bash tests/run.sh'
expect_empty "5h: …and nothing on stderr" "$ERR"

# ---------------------------------------------------------------------------
section "SHORT — a short command stays on the thread, known by the call's own timeout (wave-26 T9, D14, AC-4.1)"
#
# THE PASS READS THE TIMEOUT, NEVER THE NAME. A tier-1 command whose Bash call declares a
# `timeout` from 6000 ms to the short limit (`farm-out-short-ms:`, default 120000) passes. A
# command that holds a suite segment is wrapped as any suite is, plus `--kill-after <s>`, so the
# shim stops it before the harness's own timeout would move it to the background (s = the
# timeout in whole seconds less 5). A command with no suite segment runs exactly as typed, with
# no shim: the harness's own timeout bounds it (the lead's ruling at T44). The same command with
# no timeout is refused, and the refusal's first fix names the limit. Every row here pairs a
# pass with a refusal of the SAME command, so a pass keyed on the command's name cannot satisfy
# both.
#
# FIXTURE FIDELITY: `tool_input.timeout` is the Bash tool's own millisecond field, the one
# background-suite-guard's ARM R already reads (tests/background-suite-guard.test.sh builds it
# the same way); values are SYNTHESIZED.
SHORTR="$(mk_repo short yes)"
ONE='bash tests/one.test.sh'
# with_timeout <payload> <json value> — the payload with `tool_input.timeout` set to the value.
with_timeout() { printf '%s' "$1" | jq -c --argjson t "$2" '.tool_input.timeout = $t'; }
wrapped_cmd() { printf '%s' "$OUT" | jq -r '.hookSpecificOutput.updatedInput.command // empty' 2>/dev/null; }
reason_of() { printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null; }
# first_fix — the reason's text from its FIRST "Fix: " to the end of that sentence's clause.
first_fix() { local r; r="$(reason_of)"; case "$r" in *'Fix: '*) r="${r#*Fix: }"; printf '%s' "${r%% — *}" ;; esac; }
kill_re() {  # <seconds> <command regex> [<suites; default one\.test\.sh>] — the wrap, carrying --kill-after <seconds>
  printf '%s' "^bash [^ ]+/scripts/booked\\.sh( --shell [^ ]+)?( --quiet)? --kill-after $1 --suites ${3-one\\.test\\.sh} -- $2\$"
}

# S1 (the eval): a one-file suite command with timeout 60000 is allowed and wrapped with a kill limit.
run_hook "$(with_timeout "$(mk_payload "$SHORTR" "$ONE")" 60000)"
expect_status "S1a: a one-file suite call with timeout 60000 exits 0" 0 "$ST"
expect_empty "S1b: …and is not refused (beside S3's deny on the same extractor)" "$(decision_of)"
expect_regex "S1c: …it is wrapped with a kill limit of 55 s" "$(kill_re 55 "'bash tests/one\\.test\\.sh'")" "$(wrapped_cmd)"
expect_absent "S1d: …and no [deny] instrument line" "[deny]" "$ERR"

# S3 (the eval): the same command with no timeout is refused, the limit as its first fix.
run_hook "$(mk_payload "$SHORTR" "$ONE")"
expect_eq "S3a: the same command with no timeout is refused" "deny" "$(decision_of)"
expect_contains "S3b: …the user line's fix names the limit first" \
  "bionic: run refused — this command belongs in a subagent (timeout ≤120000 ms, or dispatch it)" "$ERR"
expect_nonempty "S3c: the reason carries a Fix" "$(first_fix)"
expect_contains "S3d: …and its FIRST fix is the limit" "timeout of at most 120000 ms" "$(first_fix)"
expect_contains "S3e: …dispatch is still offered after it" "Agent(subagent_type: test-runner" "$(reason_of)"
expect_empty "S3f: …and nothing is wrapped (beside S1's wrap on the same extractor)" "$(wrapped_cmd)"

# THE BOUNDARY AND THE MALFORMED. At the limit is short; one past it, zero, negative, a fraction,
# a word and null are not.
run_hook "$(with_timeout "$(mk_payload "$SHORTR" "$ONE")" 120000)"
expect_regex "S4a: timeout 120000 (at the limit) passes, killed at 115 s" "$(kill_re 115 "'bash tests/one\\.test\\.sh'")" "$(wrapped_cmd)"
# UNDER SIX SECONDS IS NOT SHORT (review 8 N1, A-T44.1): the kill would land at one second and
# its two-second grace would outlive the harness's own timeout, so the shim's line would be lost.
run_hook "$(with_timeout "$(mk_payload "$SHORTR" "$ONE")" 6000)"
expect_regex "S4b: timeout 6000 (the floor) passes, killed at 1 s" "$(kill_re 1 "'bash tests/one\\.test\\.sh'")" "$(wrapped_cmd)"
run_hook "$(with_timeout "$(mk_payload "$SHORTR" "$ONE")" 5999)"
expect_eq "S4e: timeout 5999 is not short — refused" "deny" "$(decision_of)"
expect_empty "S4f: …and not wrapped (beside S4b's wrap)" "$(wrapped_cmd)"
expect_contains "S4g: …the user line asks for at least the floor" \
  "bionic: run refused — this command belongs in a subagent (timeout ≥6000 ms, or dispatch it)" "$ERR"
expect_contains "S4h: …and the reason's first fix names the whole band" "timeout of 6000 to 120000 ms" "$(first_fix)"
# THE FLOOR IS ROOM FOR THE SHIM'S KILL, so it binds only a command the shim will wrap (review 12
# F5, A-T50.4). A build passes as typed whatever its timeout; a suite under the floor, alone or
# in a chain, is still refused with the floor as its fix.
for _t in 5999 1000; do
  run_hook "$(with_timeout "$(mk_payload "$SHORTR" 'make')" "$_t")"
  expect_status "S4i: a $_t ms build exits 0" 0 "$ST"
  expect_empty "S4j: …prints nothing on stdout: no wrap, no decision (beside S4e's deny) [$_t]" "$OUT"
  expect_empty "S4k: …and nothing on stderr (beside S4g's line) [$_t]" "$ERR"
done
run_hook "$(with_timeout "$(mk_payload "$SHORTR" "make && $ONE")" 5999)"
expect_eq "S4l: a 5999 ms chain that holds a suite is refused" "deny" "$(decision_of)"
expect_contains "S4m: …with the floor as its fix" "(timeout ≥6000 ms, or dispatch it)" "$ERR"
for _t in 120001 0 -5 60000.5 '"soon"' null 99999999999; do
  run_hook "$(with_timeout "$(mk_payload "$SHORTR" "$ONE")" "$_t")"
  expect_eq "S4c: timeout $_t is not short — refused" "deny" "$(decision_of)"
  expect_empty "S4d: …and not wrapped [$_t]" "$(wrapped_cmd)"
done

# EVERY CLASS THE WALL REFUSES IS SHORT BY THE SAME TEST, BUT ONLY A SUITE IS WRAPPED (the lead's
# ruling at T44, which removed `--unbooked`). A short command with no suite segment comes back
# with nothing at all: no updated input, no decision, no line. The wrap would run it in a child
# shell, where a `cd` does not carry to the next call, and the harness's timeout bounds it
# anyway. A short command with a suite segment is wrapped as any suite is, plus `--kill-after`.
for _c in 'make' 'npm install' 'cd x && make && echo ok' 'BIONIC_SLOT_HELD=1 make'; do
  run_hook "$(with_timeout "$(mk_payload "$SHORTR" "$_c")" 30000)"
  expect_status "S5a: a short [$_c] exits 0" 0 "$ST"
  expect_empty "S5b: …prints nothing on stdout: no wrap, no decision [$_c]" "$OUT"
  expect_empty "S5f: …and nothing on stderr [$_c]" "$ERR"
  run_hook "$(mk_payload "$SHORTR" "$_c")"
  expect_eq "S5c: …while [$_c] with no timeout is refused" "deny" "$(decision_of)"
  expect_contains "S5g: …with its user line on stderr [$_c]" "bionic: run refused" "$ERR"
done
run_hook "$(with_timeout "$(mk_payload "$SHORTR" "cd x && make && $ONE")" 30000)"
# The kill limit, then where the leading `cd` leads, resolved against the payload cwd (wave-26 T56).
S5E_DIR_RE="$(printf '%s' "$SHORTR/x" | sed 's/[][\.*^$+?(){}|]/\\&/g')"
expect_regex "S5e: a short chain that ends in a suite is wrapped with the kill limit and its stamp dir" \
  "$(kill_re "25 --stamp-dir $S5E_DIR_RE" "'cd x && make && bash tests/one\\.test\\.sh'")" "$(wrapped_cmd)"
run_hook "$(with_timeout "$(mk_payload "$SHORTR" "make && $ONE && echo done")" 30000)"
expect_regex "S5h: a short chain with a suite in the middle is wrapped too" \
  "$(kill_re 25 "'make && bash tests/one\\.test\\.sh && echo done'")" "$(wrapped_cmd)"
run_hook "$(with_timeout "$(mk_payload "$SHORTR" "BIONIC_QUIET=1 $ONE")" 60000)"
expect_regex "S5d: a short whole-machine suite carries --quiet and the kill limit" \
  "^bash [^ ]+/scripts/booked\\.sh( --shell [^ ]+)? --quiet --kill-after 55 --suites one\\.test\\.sh -- " "$(wrapped_cmd)"

# A SHORT CALL THAT IS NOT TIER-1 IS LEFT ALONE: nothing to pass, so nothing to wrap or kill.
run_hook "$(with_timeout "$(mk_payload "$SHORTR" 'ls -la')" 5000)"
expect_status "S6a: a short ls exits 0" 0 "$ST"
expect_empty "S6b: …and is neither wrapped nor answered (beside S1's wrap)" "$OUT"

# A SHORT TIMEOUT THE SHIM CANNOT ENFORCE IS NOT SHORT: a shell-backgrounded command detaches from
# the shim and cannot be stopped at the limit. `BIONIC_SLOT_HELD=1` in the prefix kept a suite out
# of the shim until wave-28 T12 (D13); it is no opt-out now, so such a call is wrapped with the
# kill limit and passes like any other short suite call.
run_hook "$(with_timeout "$(mk_payload "$SHORTR" "BIONIC_SLOT_HELD=1 $ONE")" 60000)"
expect_status "S7a: a short call carrying BIONIC_SLOT_HELD=1 passes" 0 "$ST"
expect_regex "S7b: …wrapped with the kill limit, like any short suite call" \
  "$(kill_re 55 "'BIONIC_SLOT_HELD=1 bash tests/one\\.test\\.sh'")" "$(wrapped_cmd)"
run_hook "$(with_timeout "$(mk_payload "$SHORTR" "$ONE &")" 60000)"
expect_eq "S7c: a short call the shell backgrounds is refused" "deny" "$(decision_of)"
expect_contains "S7d: …its first fix says to run it in the foreground" "foreground" "$(first_fix)"
# A backgrounded build escapes the harness's timeout as it would escape the shim (A-T44.4).
run_hook "$(with_timeout "$(mk_payload "$SHORTR" "make &")" 60000)"
expect_eq "S7e: a short build the shell backgrounds is refused" "deny" "$(decision_of)"
expect_contains "S7f: …its first fix says to run it in the foreground" "foreground" "$(first_fix)"

# THE LIMIT IS THE PROJECT'S: `farm-out-short-ms:` in .bionic/config.yaml. A malformed value is
# the default; 0 means no call is short, and the fix is dispatch alone.
SHORTC="$(mk_repo shortcfg yes)"
printf 'farm-out-short-ms: 30000\n' > "$SHORTC/.bionic/config.yaml"
run_hook "$(with_timeout "$(mk_payload "$SHORTC" "$ONE")" 60000)"
expect_eq "S8a: under farm-out-short-ms: 30000 a 60000 call is refused" "deny" "$(decision_of)"
expect_contains "S8b: …the fix names the project's limit" "(timeout ≤30000 ms, or dispatch it)" "$ERR"
run_hook "$(with_timeout "$(mk_payload "$SHORTC" "$ONE")" 30000)"
expect_regex "S8c: …and a 30000 call passes" "$(kill_re 25 "'bash tests/one\\.test\\.sh'")" "$(wrapped_cmd)"
printf 'farm-out-short-ms: 90000 \r\n' > "$SHORTC/.bionic/config.yaml"
run_hook "$(with_timeout "$(mk_payload "$SHORTC" "$ONE")" 90000)"
expect_regex "S8d: a CRLF line with trailing space still reads 90000" "$(kill_re 85 "'bash tests/one\\.test\\.sh'")" "$(wrapped_cmd)"
for _v in soon '' -1 '12 ms' 9999999999; do
  printf 'farm-out-short-ms: %s\n' "$_v" > "$SHORTC/.bionic/config.yaml"
  run_hook "$(with_timeout "$(mk_payload "$SHORTC" "$ONE")" 120000)"
  expect_regex "S8e: a malformed limit [$_v] is the default 120000" "$(kill_re 115 "'bash tests/one\\.test\\.sh'")" "$(wrapped_cmd)"
  run_hook "$(mk_payload "$SHORTC" "$ONE")"
  expect_contains "S8f: …and the refusal names it [$_v]" "(timeout ≤120000 ms, or dispatch it)" "$ERR"
done
printf 'farm-out-short-ms: 5999\n' > "$SHORTC/.bionic/config.yaml"
run_hook "$(with_timeout "$(mk_payload "$SHORTC" "$ONE")" 5999)"
expect_eq "S8i: a limit under the 6000 ms floor makes no call short" "deny" "$(decision_of)"
expect_contains "S8j: …and the fix is dispatch alone" "(dispatch it with the Agent tool)" "$ERR"
printf 'farm-out-short-ms: 0\n' > "$SHORTC/.bionic/config.yaml"
run_hook "$(with_timeout "$(mk_payload "$SHORTC" "$ONE")" 6000)"
expect_eq "S8g: under farm-out-short-ms: 0 no call is short" "deny" "$(decision_of)"
expect_contains "S8h: …and the fix is dispatch alone" "(dispatch it with the Agent tool)" "$ERR"

# THE PASS SITS AFTER THE MODE AND THE OVERRIDE. Advisory: short passes with its kill, no nudge.
# Off: farm-out says nothing, so the booking wrap carries no kill. The override: lifted and
# audited as before, no kill. A subagent: farm-out never speaks, so no kill.
run_hook "$(with_timeout "$(mk_payload "$ADV" "$ONE")" 60000)"
expect_regex "S9a: under advisory a short call passes with its kill limit" "$(kill_re 55 "'bash tests/one\\.test\\.sh'")" "$(wrapped_cmd)"
expect_empty "S9b: …and draws no nudge" "$(ctx_of)"
run_hook "$(with_timeout "$(mk_payload "$OFFREPO" "$ONE")" 60000)"
expect_wrap_only "S9c: under off the wrap carries no kill" "$ONE" "" "one\\.test\\.sh"
run_hook "$(with_timeout "$(mk_payload "$SHORTR" "FARM_OUT_ALLOW=1 $ONE")" 60000)"
expect_wrap_only "S9d: the override wins, no kill" "FARM_OUT_ALLOW=1 $ONE" "" "one\\.test\\.sh"
expect_contains "S9e: …and is audited" "farm-out [override] class=user-sanctioned" "$ERR"
run_hook "$(with_timeout "$(mk_payload "$SHORTR" "$ONE" Bash implementor)" 60000)"
expect_wrap_only "S9f: a subagent's short call carries no kill" "$ONE" "" "one\\.test\\.sh"
run_hook "$(with_timeout "$(mk_payload "$PLAIN" "$ONE")" 60000)"
expect_empty "S9g: an unengaged session's short call is untouched (beside S1)" "$OUT$ERR"

# THE PKG-EXEC ADVISORY IS RETIRED (D14). A control first: the surviving tier-2 nudge speaks
# on this extractor and this state.
FO_STATE_S="$SHORTR/.bionic/tmp/farm-out.state"
rm -f "$FO_STATE_S"
run_hook "$(mk_payload "$SHORTR" 'docker run x')"
expect_contains "S2.0: control — docker run still nudges here" "docker-run-class command" "$(ctx_of)"
for _c in 'npx tsc --noEmit' 'uvx ruff check .' 'NPX create-thing' 'sudo npx create-thing' 'npx create-thing "a b"'; do
  rm -f "$FO_STATE_S"
  run_hook "$(mk_payload "$SHORTR" "$_c")"
  expect_status "S2a: [$_c] exits 0" 0 "$ST"
  expect_empty "S2b: …prints nothing on stdout [$_c]" "$OUT"
  expect_empty "S2c: …and nothing on stderr [$_c]" "$ERR"
done

# ---------------------------------------------------------------------------
section "CHAIN-NL — a suite on its own line after a 3-segment chain is refused as on one line (review 8, T39 item 1)"
#
# THE CHAIN ARM READS THE FLATTENED TEXT, where a newline is a space, so a suite on the line
# after `a && b && c` became an argument of `c` and no segment classified: the call came back
# wrapped with no limit. When no segment classifies, the arm now reads the raw command whole.
# Each row pairs the two-line form with the one-line form on the same extractors.
NL_ONE='true && true && true && bash tests/t.test.sh'
NL_TWO="$(printf 'true && true && true\nbash tests/t.test.sh')"
run_hook "$(mk_payload "$SHORTR" "$NL_ONE")"
NL_ONE_ERR="$ERR"
expect_eq "NL1: the one-line form is refused" "deny" "$(decision_of)"
expect_contains "NL2: …as class=chain" "farm-out [deny] class=chain" "$NL_ONE_ERR"
run_hook "$(mk_payload "$SHORTR" "$NL_TWO")"
expect_eq "NL3: the two-line form is refused too" "deny" "$(decision_of)"
expect_eq "NL4: …with the same stderr, word for word" "$NL_ONE_ERR" "$ERR"
expect_contains "NL5: …naming the test-runner as the one-line form does" "Agent(subagent_type: test-runner" "$(reason_of)"
expect_empty "NL6: …and nothing is wrapped (beside NL7's wrap)" "$(wrapped_cmd)"
run_hook "$(with_timeout "$(mk_payload "$SHORTR" "$NL_TWO")" 60000)"
expect_regex "NL7: the two-line form with a short timeout is a short suite: wrapped with the kill limit" \
  "^bash [^ ]+/scripts/booked\\.sh( --shell [^ ]+)? --kill-after 55 --suites t\\.test\\.sh -- " "$(wrapped_cmd)"
NL_PLAIN="$(printf 'true && true && true\necho done')"
run_hook "$(mk_payload "$SHORTR" "$NL_PLAIN")"
expect_status "NL8: the same chain with no suite on its next line exits 0" 0 "$ST"
expect_empty "NL9: …and is not refused (beside NL3's deny)" "$(decision_of)"

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
