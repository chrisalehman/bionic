#!/bin/bash
# tests/cmd-class.test.sh — payload/scripts/lib/cmd-class.sh and the two hooks that read it.
#
# THE DEFECT THIS SUITE EXISTS FOR (B-5, wave-bionic-1.3.2). farm-out-reminder.sh used to
# grep one flattened string for tier-1 tokens with mid-string anchors, so `make( +[^ ]+)?`
# after any space denied `git commit -m "make the row green"` as class=build, and a heredoc
# body carrying `bash tests/run.sh` denied as class=suite. Research measured both
# (record/wave-bionic-1.3.2-dogfood-fixes/research-b3-b5-b9-cmd-parsing.md §2). The cure is
# to read argv POSITIONS instead of substrings: prose, quoted strings and heredoc bodies
# are never argv[0] of anything, so they never classify.
#
# AND THE ARM B-9 ADDS. hooks/background-suite-guard.sh refuses a subagent's
# `run_in_background: true` Bash call when the same reader says the command is suite-class,
# so a suite's evidence cannot be produced where no one is reading the output.
#
# HERMETIC. Every payload is crafted and piped into a hook; nothing dispatches a real tool
# call, reads the operator's ~/.claude, or depends on a live wave. Repos are throwaway git
# inits under a mktemp'd sandbox, HOME is redirected.
#
# FIXTURE FIDELITY (declared, per .claude/rules/test-harness.md, "Fixture fidelity"):
#   * PreToolUse|Bash payload envelope — the shape tests/protect-main.test.sh already pipes
#     into a live Bash hook, plus the two fields these arms turn on: a top-level `agent_id`
#     (measured present in an agent context / absent on the main thread,
#     record/w3-slice1-posttooluse-probe.md §3) and `tool_input.run_in_background`.
#   * `run_in_background` — declared OPTIONAL on the Bash tool input by the shipped CLI
#     schema (@anthropic-ai/claude-code 2.1.251, sdk-tools.d.ts:722). ABSENT, never
#     `false`, when the caller did not set it — which is why the arm tests `== true`.
#     NOT YET OBSERVED in a captured PreToolUse|Bash hook payload (A-3, s5-report.md):
#     these cases prove the hook's logic against the documented shape, not the transport.
#   * roster stamp, attestation, session ids — SYNTHESIZED, the same schema
#     tests/agent-context-guard.test.sh writes.
#
# Usage: bash tests/cmd-class.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/roster-row.sh"
. "$(dirname "$0")/lib/assert.sh"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
# THE TWO SPELLINGS OF ONE DIRECTORY. payload/hooks is a symlink to <repo>/hooks, so a hook
# is reached BOTH as <repo>/payload/hooks/x.sh (what ${CLAUDE_PLUGIN_ROOT} renders) and as
# <repo>/hooks/x.sh (what tests/lib/resolve-roots.sh renders). `$0` is textual, so
# "$(dirname "$0")/../scripts/lib" resolves only under the first. Both are driven below.
PAYLOAD_HOOKS="$REPO_ROOT/payload/hooks"
PLAIN_HOOKS="${BIONIC_HOOKS_DIR}"
LIB="$REPO_ROOT/payload/scripts/lib/cmd-class.sh"
# BOTH WALLS ARE ONE PROCESS (T23). `wall_farm_out_reminder` and
# `wall_background_suite_guard` are functions of payload/scripts/lib/walls.sh behind
# hooks/bash-walls.sh, so the two names below name the same hook; the classifier each of
# them consumes is unchanged, which is what this suite is about.
FARM_OUT="$PAYLOAD_HOOKS/bash-walls.sh"
BG_GUARD="$PAYLOAD_HOOKS/bash-walls.sh"
# hooks/agent-context-guard.sh IS NO LONGER IN FRONT OF THIS WALL (T23/R2): the manifest
# registers hooks/bash-walls.sh alone on PreToolUse|Bash and the guard's predicate is a
# function-level gate inside `wall_background_suite_guard`. The file itself stays, still
# registered on SubagentStop, and tests/agent-context-guard.test.sh is its suite.

SANDBOX="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/cmd-class-test.XXXXXX")" && pwd -P)"
cleanup() { rm -rf "$SANDBOX"; }
trap cleanup EXIT

SID="7b2ae913-0c4f-4d21-9a55-13e0c7ab4d10"
AGENT_ID="as5class-91ab3cd7e5f20114"

FAKE_HOME="$SANDBOX/home"
mkdir -p "$FAKE_HOME/.claude/projects/-sandbox"
: > "$FAKE_HOME/.claude/projects/-sandbox/$SID.jsonl"

section "C0 — the library and both hooks exist and parse"
if [ -f "$LIB" ]; then ok "payload/scripts/lib/cmd-class.sh is on disk"; else
  no "payload/scripts/lib/cmd-class.sh is on disk" "$LIB"
fi
if bash -n "$LIB" 2>"$SANDBOX/.syn"; then ok "the library parses (bash -n)"; else
  no "the library parses (bash -n)" "$(cat "$SANDBOX/.syn")"
fi
if bash -n "$BG_GUARD" 2>"$SANDBOX/.syn"; then ok "background-suite-guard.sh parses (bash -n)"; else
  no "background-suite-guard.sh parses (bash -n)" "$(cat "$SANDBOX/.syn")"
fi
if bash -n "$FARM_OUT" 2>"$SANDBOX/.syn"; then ok "farm-out-reminder.sh parses (bash -n)"; else
  no "farm-out-reminder.sh parses (bash -n)" "$(cat "$SANDBOX/.syn")"
fi

section "C1 — the library reads argv positions, never prose"
# Driven through a child bash that sources the library, so a `set -e`/`set -u` collision or
# a stray write to the caller's shell shows up here rather than corrupting the suite.
class_of() {  # <command> -> the library's verdict
  printf '%s' "$1" | bash -c '
    set -uo pipefail
    . "$1" || { echo "SOURCE-FAILED"; exit 1; }
    cmd_class "$(cat)"
  ' _ "$LIB" 2>&1
}

case_is() {  # <expected class> <command> [label]
  local want="$1" cmd="$2" got
  got=$(class_of "$cmd")
  expect_eq "${3:-$want: $cmd}" "$want" "$got"
}

# --- the classes that must still be caught (AC-16 at the library level) ---
case_is suite 'bash tests/run.sh'
case_is suite 'bash tests/run.sh --serial'
case_is suite 'bash tests/cmd-class.test.sh'
case_is suite 'bash test.sh'
case_is suite 'pytest'
case_is suite 'pytest tests/'
case_is suite 'npm test'
case_is suite 'pnpm test'
case_is suite 'yarn test'
case_is suite 'go test ./...'
case_is suite 'cargo test'
case_is suite 'make test'
case_is suite 'make check'
case_is suite 'cd /tmp/x && bash tests/run.sh'
case_is suite 'FOO=1 bash tests/run.sh'
case_is suite 'cd x && FARM_OUT_ALLOW= bash tests/run.sh'
case_is suite 'bash tests/run.sh 2>&1 | tee /tmp/evidence.log'
case_is suite 'env nohup timeout 30 bash tests/run.sh'
case_is suite "bash -c 'bash tests/run.sh'"
case_is suite '/usr/local/bin/pytest tests/'

# --- D8/REQ-6: setsid joins the suite wrappers (research row 6: was `none`) ---
case_is suite 'setsid bash tests/run.sh'

case_is build 'make'
case_is build 'make widget'
case_is build 'npm run build'
case_is build 'cargo build'
case_is build 'go build ./...'
case_is build 'docker build .'

case_is install 'npm install'
case_is install 'pnpm add left-pad'
case_is install 'pip3 install requests'
case_is install 'uv sync'
case_is install 'brew install jq'

case_is bootstrap 'bash claude-bootstrap.sh'
case_is bootstrap './claude-bootstrap.sh'

# --- R-12: the reading is a SUPERSET of the 1.3.1 string match (critic C-1) ---
# A suite reached through a shell construct or a command-taking prefix lands at
# argv[1..n], where the 1.3.2 reader did not look, so `sudo bash tests/run.sh`
# and `( bash tests/run.sh )` walked past both the farm-out wall and the new
# B-9 background wall that 1.3.1's `(^|[;&| ])bash +tests/run\.sh` refused.
case_is suite 'sudo bash tests/run.sh'
case_is suite 'sudo -u ci bash tests/run.sh'
case_is suite '( bash tests/run.sh )'
case_is suite '(bash tests/run.sh)'
case_is suite '{ bash tests/run.sh; }'
case_is suite 'if true; then bash tests/run.sh; fi'
case_is suite 'for i in 1; do bash tests/run.sh; done'
case_is suite '! bash tests/run.sh'
case_is suite 'xargs bash tests/run.sh'
case_is suite 'xargs -I{} bash tests/run.sh'
case_is suite 'nice -n 10 bash tests/run.sh'
case_is suite 'exec bash tests/run.sh'
case_is suite 'ssh box bash tests/run.sh'
case_is suite 'find . -exec bash tests/run.sh \;'
case_is suite 'true & bash tests/run.sh'
case_is suite 'eval "bash tests/run.sh"'
case_is suite "sh -c 'sudo bash tests/run.sh'"

# --- C-2: a DIRECTLY EXECUTED suite is a suite ---
# tests/run.sh is -rwxr-xr-x with a bash shebang, so `./tests/run.sh` is an
# ordinary invocation; classify_argv only reached the suite arm when argv[0]
# was bash/sh/zsh, so a script at argv[0] fell through every arm to `none`.
# And the `bash run.sh` arm required a `/` in the name, which is exactly the
# shape `cd <worktree>/tests && bash run.sh` does not have.
case_is suite './tests/run.sh'
case_is suite 'tests/run.sh'
case_is suite './tests/run.sh --serial'
case_is suite './tests/cmd-class.test.sh'
case_is suite 'tests/cmd-class.test.sh'
case_is suite './test.sh'
case_is suite 'cd tests && bash run.sh'
case_is suite '(cd tests; bash run.sh)'
case_is suite 'cd tests && bash run.sh 2>&1 | tee /tmp/e.log'
case_is suite 'bash -c "./tests/run.sh"'
case_is suite 'sudo ./tests/run.sh'

# --- and the negatives the superset must NOT swallow ---
case_is none 'ls tests/run.sh'
case_is none 'cat ./tests/run.sh'
case_is none 'echo "sudo bash tests/run.sh"'
case_is none "echo '( bash tests/run.sh )'"
case_is none 'vim tests/run.sh'
case_is none 'git add tests/run.sh'
case_is none 'find . -name run.sh'
case_is none 'bash run.sh'
case_is none 'run.sh'
case_is none 'sudo git status'

# --- T24: only the PROJECT'S runner is the full-suite runner ---
# The arms read the basename `run.sh` alone, so any script of that name — a scratch replay
# harness, `scripts/run.sh` — was classed `suite` and refused as the full tree. The runner
# is `tests/run.sh`, `./tests/run.sh`, or a path ending `/tests/run.sh`.
case_is none '/bin/bash /private/tmp/x/run.sh'
case_is none 'bash scripts/run.sh'
case_is none './run.sh'
case_is none 'sh run.sh'
case_is none 'scripts/run.sh'
case_is none './scripts/run.sh --serial'
case_is none 'sudo bash /tmp/scratch/replay/run.sh'
# CONTROLS — the project's runner, in every spelling, stays the suite.
case_is suite 'bash tests/run.sh'
case_is suite './tests/run.sh'
case_is suite 'bash /abs/repo/tests/run.sh'
case_is suite 'tests/run.sh --serial'
case_is suite '/abs/repo/tests/run.sh'
case_is suite '/bin/bash /abs/repo/tests/run.sh --serial'
case_is none 'bash tests/run.sh --dry-run'
case_is none '/abs/repo/tests/run.sh --help'

# --- cmd_unwrap_head: the reduction farm-out's tier-2 matcher reads (B-4a) ---
# It replaced two sed twins in farm-out-reminder.sh whose rule set was smaller
# than the library's, so `sudo npx x` and `FOO=1 npx x` never reached tier-2.
head_of() { bash -c '. "$1" || exit 1; cmd_unwrap_head "$2"' _ "$LIB" "$2" 2>&1; }
expect_eq "head: a bare command is unchanged"      'npx create-thing' "$(head_of _ 'npx create-thing')"
expect_eq "head: env prefix comes off"             'npx create-thing' "$(head_of _ 'env npx create-thing')"
expect_eq "head: an ordinary assignment comes off" 'npx create-thing' "$(head_of _ 'FOO=1 npx create-thing')"
expect_eq "head: sudo comes off"                   'npx create-thing' "$(head_of _ 'sudo npx create-thing')"
expect_eq "head: timeout <n> comes off"            'npx create-thing' "$(head_of _ 'timeout 60 npx create-thing')"
expect_eq "head: nohup comes off"                  'npx create-thing' "$(head_of _ 'nohup npx create-thing')"
expect_eq "head: one sh -c wrapper comes off"      'npx create-thing' "$(head_of _ "sh -c 'npx create-thing'")"
expect_eq "head: eval comes off"                   'npx create-thing' "$(head_of _ 'eval "npx create-thing"')"
expect_eq "head: bash <(cat F) collapses to the script" 'bash tests/run.sh' "$(head_of _ 'bash <(cat tests/run.sh)')"
expect_eq "head: prose is left alone"              'echo make sure the row is green' \
  "$(head_of _ 'echo make sure the row is green')"

# --- prose, quoted strings and heredoc bodies NEVER classify (AC-15, B-5) ---
case_is none 'git commit -m "make the row green"'
case_is none 'echo "npm install done"'
case_is none "echo 'make sure the row is green'"
case_is none 'git commit -m "run npm install first"'
case_is none 'ls claude-bootstrap.sh'
case_is none 'make clean'
case_is none 'echo remake'
case_is none 'echo make sure the row is green'   # the UNQUOTED prose the old `make( +[^ ]+)?` denied
case_is none 'cat notes.md | grep make'
case_is none 'grep -n "bash tests/run.sh" notes.md'

HEREDOC_CMD="python3 - <<'EOF'
pytest tests/policies
152 passed
bash tests/run.sh
make sure the row is green
npm install first
EOF"
case_is none "$HEREDOC_CMD" "none: a heredoc body carrying suite/build/install words"

HEREDOC_DASH="cat <<-END > /tmp/notes.txt
	make the row green
	END"
case_is none "$HEREDOC_DASH" "none: a <<- heredoc body with a tab-indented terminator"

# A heredoc that OPENS a real suite command after the terminator still classifies.
HEREDOC_THEN_SUITE="cat <<'EOF' > /tmp/n.txt
make the row green
EOF
bash tests/run.sh"
case_is suite "$HEREDOC_THEN_SUITE" "suite: a real command AFTER a heredoc still classifies"

section "C2/C3 — farm-out-reminder through the library (AC-15, AC-16)"
# ---------- engagement (task-engaged-session, AC-6 / AC-20) ----------
#
# Since 2026-09-03 both hooks this section drives ask one question before any other: did
# this session invoke the canonical-sdlc skill? (Chris: "all guardrails imposed by bionic
# should only apply when exercising bionic. Nothing should apply until bionic is
# triggered.") hooks/engage.sh answers it by writing `.bionic/tmp/engaged-<sid>.state`
# under the project root, creating the directory where there is none.
#
# EVERY FIXTURE BELOW IS ENGAGED, including the negative controls — otherwise the run
# predicate and the classifier, which are what those controls are about, would never be
# reached and each would pass for the wrong reason. §C6 at the bottom is the unengaged
# world, and it is the only place the marker is absent.
engage()   { mkdir -p "$1/.bionic/tmp" && : > "$1/.bionic/tmp/engaged-$SID.state"; }
unengage() { rm -f "$1/.bionic/tmp/engaged-$SID.state"; }

FARM_REPO="$SANDBOX/farm/repo"
mkdir -p "$FARM_REPO/.bionic/tmp" "$FARM_REPO/.bionic/docs/plans"
engage "$FARM_REPO"
# THE WALL IS RUN-SCOPED SINCE bionic 1.4.0 (task ADOPT, spec AC-7). The hook is
# registered always-on now, so what scopes it is an on-disk fact rather than an armed
# skill: `active_run` under the payload's project root. Every AC-16 arm below asks
# whether the wall still refuses the real thing, and none of them would be asking
# anything without an OPEN run here. The negative control is FARM_NORUN, further down.
cat > "$FARM_REPO/.bionic/docs/plans/wave-01.plan.md" <<'FARMPLAN'
---
canonical_sdlc_version: 14
---

## SDLC State

current: 4

- Step 4: implementation
FARMPLAN

mk_bash_payload() {  # <cwd> <command> [agent_id] [run_in_background:true|false|omit]
  local bg="${4:-omit}"
  jq -n --arg s "$SID" --arg c "$1" --arg cmd "$2" --arg a "${3:-}" \
        --arg bg "$bg" \
    '{session_id:$s, transcript_path:"/irrelevant.jsonl", cwd:$c,
      permission_mode:"bypassPermissions",
      hook_event_name:"PreToolUse", tool_name:"Bash",
      tool_input:({command:$cmd}
                  + (if $bg == "omit" then {} else {run_in_background: ($bg == "true")} end)),
      tool_use_id:"toolu_01cmdclass"}
     + (if $a == "" then {} else {agent_id:$a} end)'
}

OUT=""; ERR=""; ST=0
run_hook() {  # <payload> <hook> [args...]
  local payload="$1"; shift
  # BIONIC_PLUGINS_DIR is pointed at an empty sandbox for the same reason HOME is:
  # since bionic 1.4.0 the loader HEALS before it fails, consulting the CLI's plugin
  # registry and cache when the library is not beside the hook. Without this door
  # closed, §C5's "library moved aside" fixture would quietly load THIS machine's
  # installed bionic and prove nothing.
  # THE ENVIRONMENT AGREES WITH THE PAYLOAD, because on the machine it does (A-probe-2).
  # hooks/agent-context-guard.sh builds the roster filename from lib/session.sh's answer,
  # where the ENV value is primary — so a driver that left the runner's own session id in
  # the environment would have the guard looking for a roster this fixture never wrote,
  # and every wall behind it would read "unarmed".
  local _sid; _sid=$(printf '%s' "$payload" | jq -r '.session_id // ""' 2>/dev/null) || _sid=""
  OUT=$(printf '%s' "$payload" | env HOME="$FAKE_HOME" CLAUDE_CONFIG_DIR="$FAKE_HOME/.claude" \
          BIONIC_PLUGINS_DIR="$SANDBOX/no-plugins" CLAUDE_CODE_SESSION_ID="$_sid" \
          CLAUDE_PROJECT_DIR= bash "$@" 2>"$SANDBOX/.err")
  ST=$?
  ERR=$(cat "$SANDBOX/.err")
  return 0
}

farm_decision() {  # <command> -> "" when silent, else the deny/nudge class
  run_hook "$(mk_bash_payload "$FARM_REPO" "$1")" "$FARM_OUT"
  printf '%s' "$OUT"
}

# --- AC-6/R-1: the nudge is PLAN-FREE — engagement alone scopes it ---
#
# THE DEFECT (step-6 review R-1). Until this fix the hook carried
# `active_run "$ROOT" >/dev/null || exit 0` below its engagement guard, so an engaged
# session that had not yet written a plan — the whole of Step 0 through Step 3 — ran its
# suites with no nudge at all. The ratified design says otherwise: engagement decides
# WHETHER a bionic wall speaks, and the farm-out nudge needs no plan to know that a suite
# command belongs in a subagent. The run predicate stayed behind after the 1.4.0 guard
# landed above it; it is gone now.
#
# THE PAIR. Two fixtures with NO plan on disk, differing only in the engagement marker.
# Engaged → the same suite command that denies above denies here. Unengaged → silence on
# both channels. Neither row can pass on a hook that had simply stopped working, because
# the other row proves it still fires.
FARM_NORUN="$SANDBOX/farm/norun"
mkdir -p "$FARM_NORUN"
engage "$FARM_NORUN"
run_hook "$(mk_bash_payload "$FARM_NORUN" 'bash tests/run.sh')" "$FARM_OUT"
expect_contains "R-1 farm-out DENIES a suite command with NO plan on disk (nudge is plan-free)" \
  '"deny"' "$OUT"
expect_eq "R-1 …exiting 0" "0" "$ST"

# The tier-2 nudge, same world: no plan, engaged, still spoken.
run_hook "$(mk_bash_payload "$FARM_NORUN" 'docker run x')" "$FARM_OUT"
expect_contains "R-1 …the tier-2 nudge also fires with no plan on disk" \
  'additionalContext' "$OUT"

# THE PAIRED SILENCE: same tree, same commands, marker removed.
unengage "$FARM_NORUN"
run_hook "$(mk_bash_payload "$FARM_NORUN" 'bash tests/run.sh')" "$FARM_OUT"
expect_empty "R-1 …and with no marker and no plan it is SILENT on stdout" "$OUT"
expect_empty "R-1 …and silent on stderr" "$ERR"
expect_eq "R-1 …exiting 0" "0" "$ST"
engage "$FARM_NORUN"

FARM_CLOSED="$SANDBOX/farm/closed"
mkdir -p "$FARM_CLOSED/.bionic/docs/plans"
engage "$FARM_CLOSED"
cat > "$FARM_CLOSED/.bionic/docs/plans/wave-01.plan.md" <<'CLOSEDPLAN'
---
canonical_sdlc_version: 14
---

## SDLC State

current: 9

- Step 9: delivered: record/x.md
CLOSEDPLAN
run_hook "$(mk_bash_payload "$FARM_CLOSED" 'bash tests/run.sh')" "$FARM_OUT"
expect_contains "R-1 …a CLOSED run does not silence it either (current: 9)" '"deny"' "$OUT"
expect_eq "R-1 …exiting 0" "0" "$ST"

# --- AC-15: silent on prose, quoted strings and heredoc bodies ---
expect_empty "AC-15 farm-out is SILENT on git commit -m \"make the row green\"" \
  "$(farm_decision 'git commit -m "make the row green"')"
expect_empty "AC-15 …silent on a heredoc body carrying pytest/bash tests/run.sh" \
  "$(farm_decision "$HEREDOC_CMD")"
expect_empty "AC-15 …silent on echo \"npm install done\"" \
  "$(farm_decision 'echo "npm install done"')"
# THE UNQUOTED SHAPE, which is the one that was measurably RED (research-b3 §2: the quote
# in `echo 'make sure…'` blocked the space anchor by luck, so only the unquoted spelling and
# the heredoc body reproduced the field DENY).
# SINGLE-quoted labels, deliberately. These two carried backticks inside DOUBLE
# quotes until 2026-08-30, so the suite ran `make` and `npm install` for real on
# every invocation — writing a package-lock.json into the repo root and a log
# into ~/.npm/_logs (auditor-step5.md F-3). A test suite must not execute the
# commands it is describing.
expect_empty 'AC-15 …silent on unquoted prose carrying `make <word>`' \
  "$(farm_decision 'echo make sure the row is green')"
expect_empty 'AC-15 …silent on unquoted prose carrying `npm install`' \
  "$(farm_decision 'echo run npm install first')"

# --- AC-16: still a wall on the real thing ---
D=$(farm_decision 'bash tests/run.sh --serial')
expect_contains "AC-16 farm-out still DENIES bash tests/run.sh --serial" '"deny"' "$D"
expect_contains "AC-16 …as class suite, redirected to test-runner" 'test-runner' "$D"
D=$(farm_decision 'cd x && FARM_OUT_ALLOW= bash tests/run.sh')
expect_contains "AC-16 …DENIES cd x && FARM_OUT_ALLOW= bash tests/run.sh (empty is not the override)" \
  '"deny"' "$D"
expect_contains "AC-16 …DENIES pytest tests/" '"deny"' "$(farm_decision 'pytest tests/')"
expect_contains "AC-16 …DENIES npm test" '"deny"' "$(farm_decision 'npm test')"
expect_contains "AC-16 …DENIES make test" '"deny"' "$(farm_decision 'make test')"

# --- AC-16 (R-12/C-2): the same wall through a construct, a prefix, or a
#     directly executed script. One list, driven through BOTH walls below. ---
SUPERSET_SUITES=(
  'sudo bash tests/run.sh'
  '( bash tests/run.sh )'
  'if true; then bash tests/run.sh; fi'
  'xargs bash tests/run.sh'
  './tests/run.sh'
  'tests/run.sh'
  'cd tests && bash run.sh'
  '(cd tests; bash run.sh)'
)
for sc in "${SUPERSET_SUITES[@]}"; do
  expect_contains "AC-16 farm-out DENIES [$sc]" '"deny"' "$(farm_decision "$sc")"
done

# --- behaviour the library must not have changed ---
# THE OVERRIDE SILENCES FARM-OUT'S DENY, NOT THE BOOKING (wave-26 T7, D8): the allowed call
# comes back as the booking wrap alone — no deny, no advisory — around the original command.
expect_wrap_only() {  # <label> <original command> — reads $OUT
  local _cmd _s _r="'\\''"
  expect_eq "$1 (no deny and no advisory beside the booking wrap)" '["hookEventName","updatedInput"]' \
    "$(printf '%s' "$OUT" | jq -c '.hookSpecificOutput | keys' 2>/dev/null)"
  _cmd=$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.updatedInput.command // empty' 2>/dev/null)
  expect_regex "$1 (the updated command runs the booking shim)" \
    "^bash [^ ]+/scripts/booked\\.sh( --shell [^ ]+)?( --quiet)? -- " "$_cmd"
  _s=${2//\'/$_r}
  expect_eq "$1 (around the original command, byte for byte)" "'$_s'" "${_cmd#* -- }"
}
run_hook "$(mk_bash_payload "$FARM_REPO" 'FARM_OUT_ALLOW=1 bash tests/run.sh')" "$FARM_OUT"
expect_wrap_only "the sanctioned override still silences the wall" 'FARM_OUT_ALLOW=1 bash tests/run.sh'
run_hook "$(mk_bash_payload "$FARM_REPO" 'cd x && FARM_OUT_ALLOW=1 bash tests/run.sh')" "$FARM_OUT"
expect_wrap_only "…including as an env prefix mid-chain" 'cd x && FARM_OUT_ALLOW=1 bash tests/run.sh'
expect_empty "a subagent payload leaves farm-out silent (agent_type non-empty)" \
  "$(printf '%s' "$(mk_bash_payload "$FARM_REPO" 'bash tests/run.sh')" \
     | jq '. + {agent_type:"general-purpose"}' \
     | env HOME="$FAKE_HOME" bash "$FARM_OUT" 2>/dev/null)"
D=$(farm_decision 'npm install')
expect_contains "an install-class command still denies" '"deny"' "$D"
D=$(farm_decision 'make widget')
expect_contains "a build-class command still denies" '"deny"' "$D"
expect_empty "make clean stays silent" "$(farm_decision 'make clean')"
expect_empty "ls claude-bootstrap.sh stays silent (reading a script is not running it)" \
  "$(farm_decision 'ls claude-bootstrap.sh')"
D=$(farm_decision 'bash claude-bootstrap.sh')
expect_contains "a bootstrap-class command still denies" '"deny"' "$D"

# --- B-4a: tier-2 reads the library, so its wrappers come off too ---
# `git clone`/`docker run` are the NUDGE tier (the npx/uvx nudge retired at wave-26 T9). Before the sed twins
# were deleted, only env/nohup/timeout/FARM_OUT_*= came off, so a sudo- or
# assignment-wrapped tier-2 command reached the matcher with the wrapper still
# at argv[0] and nudged nobody.
expect_contains "B-4a tier-2 still nudges a bare docker run" 'additionalContext' \
  "$(farm_decision 'docker run x')"
# A DIFFERENT class, because nudge_once suppresses a repeat of the same one.
expect_contains "B-4a …and now through sudo" 'additionalContext' \
  "$(farm_decision 'sudo git clone https://example.invalid/r.git')"
expect_empty "B-4a …but prose naming docker run still says nothing" \
  "$(farm_decision 'echo run docker run x first')"

# --- advisory mode still downgrades a deny to a nudge ---
printf 'farm-out-mode: advisory\n' > "$FARM_REPO/.bionic/config.yaml"
D=$(farm_decision 'bash tests/run.sh')
expect_contains "advisory mode downgrades the suite deny to a nudge" 'additionalContext' "$D"
rm -f "$FARM_REPO/.bionic/config.yaml"

section "C4 — background-suite-guard inside the compound (AC-23, AC-24)"
#
# THE GUARD IS NOT IN FRONT ANY MORE, AND THE MANIFEST IS WHY (T23 ruling R2, A-54).
# hooks/agent-context-guard.sh used to wrap this wall's registration; the fold could not
# keep that wrapper, because a wrapper around the COMPOUND would silence protect-main,
# protect-database, the evidence gate and farm-out-reminder on every main-thread call.
# The guard's predicate is a FUNCTION-level gate inside `wall_background_suite_guard`
# now, and hooks.json registers hooks/bash-walls.sh alone — so a fixture that still drove
# the guard in front would be driving a registration that does not exist.
#
# AND THE VERDICT IS COMPOSED (A-53, A-56.3). Every payload below is suite-class, so
# farm-out-reminder answers it too, and it always did: on this thread its tier-1 deny has
# fired on `bash tests/run.sh` since 1.3.2. What the old fixture measured was the guard
# keeping the OTHER wall off the call. With one process the two answers meet, and the
# fold composes them into ONE `permissionDecision: deny` carrying BOTH reasons — the deny
# wire's exit status is 0, with the decision in the JSON. So each row below asserts the
# arm it is about BY ITS OWN SENTENCE, present or absent, rather than by an exit code
# that now belongs to the compound.
make_repo() {  # <name> -> an armed repo of an ENGAGED session
  local repo="$SANDBOX/$1/repo"
  mkdir -p "$repo/.bionic/tmp"
  # ENGAGED: hooks/agent-context-guard.sh in front, and the wall behind it, both step
  # aside for a session that never invoked the skill. The arming roster below is a
  # different fact and the cells here are about that one.
  : > "$repo/.bionic/tmp/engaged-$SID.state"
  git -C "$repo" init -q 2>/dev/null
  git -C "$repo" config user.email t@example.com
  git -C "$repo" config user.name "T"
  echo seed > "$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit -qm seed 2>/dev/null
  {
    roster_header
    # THE ROW CARRIES THE FULL-TREE BUDGET, and it has to (S13, spec AC-21). Every cell in
    # C4 drives `bash tests/run.sh` from an agent context, and since the budget arm shipped
    # a full-tree run is refused unless this agent`s own row allows it — so a header-only
    # roster would put the BUDGET arm under test in the cells that exist to test the
    # BACKGROUND one, and the three "must stay silent" cells would have gone red for a
    # wall they never meant to reach. The unbudgeted world is
    # tests/background-suite-guard.test.sh`s.
    roster_row_fixture "session=$SID" name=guarded "agent_id=$AGENT_ID" \
      suites_allowed=run.sh suites_source=declared files=
  } > "$repo/.bionic/tmp/roster-$SID.state"
  chmod 600 "$repo/.bionic/tmp/roster-$SID.state"
  printf '%s' "$repo"
}
GREPO=$(make_repo guarded)

run_compound() {  # <payload> — straight into hooks/bash-walls.sh, as hooks.json registers it
  run_hook "$1" "$BG_GUARD"
}

# THE BACKGROUND ARM'S OWN SENTENCE, which is what every row in this section is really
# asking about. It is `wall_background_suite_guard`'s fact and no other wall's, so its
# presence in the composed verdict is the arm firing and its absence is the arm silent —
# a reading that survives farm-out-reminder answering the same payload.
BSG_REASON='suite-run refused — a backgrounded suite'"'"'s result is never read'
FARM_REASON="run refused — this command belongs in a subagent"

# THE DETAIL KNOB IS NOT THIS SECTION'S ANY MORE. `BIONIC_WALL_VERBOSE=1` is the `exit2`
# channel's rule — one line on the user stream, everything else behind the knob — and the
# composed verdict here renders on the `deny` channel, whose reason field carries the
# detail to the model by design (that is what farm-out-reminder's own deny has always
# done). The knob's behaviour on a wall that blocks ALONE is still driven, in
# tests/background-suite-guard.test.sh; here the detail is asserted where it actually
# lands, in $OUT.

# --- AC-23: agent context + armed + run_in_background true + suite-class -> REFUSED
run_compound "$(mk_bash_payload "$GREPO" 'bash tests/run.sh' "$AGENT_ID" true)"
expect_contains "AC-23 a backgrounded suite in an agent context of an armed session is REFUSED" \
  '"permissionDecision":"deny"' "$OUT"
expect_contains "AC-23 …and the refusal is the BACKGROUND arm's" "$BSG_REASON" "$OUT"
expect_contains "AC-23 …composed WITH farm-out's own reason, not instead of it" "$FARM_REASON" "$OUT"
expect_eq "AC-23 …on the deny wire, whose status is 0 with the decision in the JSON" 0 "$ST"
expect_contains "AC-23 …and the refusal names the foreground tee form" "2>&1 | tee" "$OUT"
expect_contains "AC-23 …quoting the command it refused" "bash tests/run.sh" "$OUT"

# --- AC-24: the three cells that must stay silent ---
# THE THREE CELLS THE BACKGROUND ARM MUST STAY OUT OF. Each is suite-class, so
# farm-out-reminder answers it — and that is the tier-1 deny it has always given on this
# thread, not the arm under test. The row is the ABSENCE of the background arm's own
# sentence, which is the same claim the old `expect_empty` made when the guard kept the
# other wall off the call.
run_compound "$(mk_bash_payload "$GREPO" 'bash tests/run.sh' "$AGENT_ID" omit)"
expect_eq "AC-24 the same command with no run_in_background is ALLOWED by the background arm" 0 "$ST"
expect_absent "AC-24 …silently — its reason is nowhere in the verdict" "$BSG_REASON" "$ERR$OUT"
expect_contains "AC-24 …while farm-out's own deny stands, as it does on this thread" \
  "$FARM_REASON" "$OUT"

run_compound "$(mk_bash_payload "$GREPO" 'bash tests/run.sh' "$AGENT_ID" false)"
expect_eq "AC-24 run_in_background false is ALLOWED by the background arm" 0 "$ST"
expect_absent "AC-24 …silently" "$BSG_REASON" "$ERR$OUT"

run_compound "$(mk_bash_payload "$GREPO" 'bash tests/run.sh' "" true)"
expect_eq "AC-24 a MAIN-THREAD payload (no agent_id) leaves the arm silent" 0 "$ST"
expect_absent "AC-24 …silently" "$BSG_REASON" "$ERR$OUT"
expect_contains "AC-24 …and the main thread is exactly where farm-out's deny belongs" \
  "$FARM_REASON" "$OUT"

# THE TWO THAT ARE SILENT ALL THE WAY DOWN: not suite-class, so neither wall speaks.
run_compound "$(mk_bash_payload "$GREPO" 'git status --short' "$AGENT_ID" true)"
expect_eq "AC-24 a non-suite command backgrounded is ALLOWED" 0 "$ST"
expect_empty "AC-24 …silently" "$ERR$OUT"

run_compound "$(mk_bash_payload "$GREPO" 'git commit -m "make the row green"' "$AGENT_ID" true)"
expect_eq "AC-24 …and B-5's prose case is not a suite either" 0 "$ST"
expect_empty "AC-24 …silently, on both streams" "$ERR$OUT"

# --- AC-16 (R-12/C-2): the B-9 wall refuses the same superset ---
for sc in "${SUPERSET_SUITES[@]}"; do
  run_compound "$(mk_bash_payload "$GREPO" "$sc" "$AGENT_ID" true)"
  expect_contains "AC-16 background-suite-guard REFUSES backgrounded [$sc]" "$BSG_REASON" "$OUT"
done
# NEGATIVE CONTROL on the same arm: prose that merely names a suite is not one.
run_compound "$(mk_bash_payload "$GREPO" 'echo "sudo bash tests/run.sh"' "$AGENT_ID" true)"
expect_eq "AC-16 …but prose naming a suite is still ALLOWED" 0 "$ST"
expect_empty "AC-16 …in silence, from both walls" "$ERR$OUT"

# --- the partition still holds, one level in: an UNARMED session is silent ---
#
# THE PARTITION MOVED, THE EXPERIMENT DID NOT. It used to be hooks/agent-context-guard.sh
# in front; it is the first thing `wall_background_suite_guard` asks now (T23/R2). So the
# pair below is the same difference measured at the same fixture — unarmed, and armed —
# with the verdict read by the arm's own sentence rather than by an exit code the
# compound now shares with farm-out-reminder.
UREPO=$(make_repo unarmed)
rm -f "$UREPO/.bionic/tmp/roster-$SID.state"
run_compound "$(mk_bash_payload "$UREPO" 'bash tests/run.sh' "$AGENT_ID" true)"
expect_eq "an unarmed session leaves the arm silent even for a backgrounded suite" 0 "$ST"
expect_absent "…its reason nowhere in the verdict" "$BSG_REASON" "$ERR$OUT"
# POSITIVE CONTROL: the identical payload in an ARMED session must carry that reason, so
# the silence above is the partition deciding and not a dud fixture.
run_compound "$(mk_bash_payload "$GREPO" 'bash tests/run.sh' "$AGENT_ID" true)"
expect_contains "…positive control: the same payload in an ARMED session does refuse" \
  "$BSG_REASON" "$OUT"

section "C5 — FAIL-CLOSED sourcing: no library, no pass (AC-12 shape, D1)"
# HERMETIC, AND THAT IS A CORRECTION. This section used to `mv` the SHIPPED library aside
# for its own length and restore it from a trap — a write outside its own mktemp root, and
# the one thing tests/run.sh's parallel mode assumes no suite does. Every sibling suite
# that reads payload/scripts/lib/cmd-class.sh (and since bionic 1.4.0 that is every suite
# driving farm-out-reminder or the background-suite guard) saw the library vanish for a
# few hundred milliseconds and went red for a reason that had nothing to do with it.
# Measured: `BIONIC_TEST_JOBS=18 bash tests/run.sh` with hook-adoption.test.sh on the
# roster, 13 failures here, zero when run alone.
#
# The copies live in a throwaway tree shaped like the shipped plugin — hooks/ beside
# scripts/lib/, with the classifier simply absent — so what is under test is the same
# resolution the shipped hooks perform, and nothing outside $SANDBOX is touched.
C5_TREE="$SANDBOX/no-classifier"
mkdir -p "$C5_TREE/hooks" "$C5_TREE/scripts/lib"
for _c5_lib in "$(dirname "$LIB")"/*.sh; do
  case "$(basename "$_c5_lib")" in cmd-class.sh) continue ;; esac
  cp "$_c5_lib" "$C5_TREE/scripts/lib/"
done
cp "$FARM_OUT" "$C5_TREE/hooks/bash-walls.sh"
C5_SAVED_FARM="$FARM_OUT"; C5_SAVED_BG="$BG_GUARD"
FARM_OUT="$C5_TREE/hooks/bash-walls.sh"
BG_GUARD="$C5_TREE/hooks/bash-walls.sh"

# BOTH OF THESE STEP ASIDE NOW (bionic 1.4.0, design ledger S4). They refused until
# 1.4.0, on the reasoning the two irreversible-action walls still use — and that
# reasoning does not reach here. farm-out guards where a command RUNS; this guard
# prevents a suite whose output nobody reads. Both mistakes are reversible and cost a
# re-run; refusing every Bash call in every session on the machine because one file is
# missing is not. The direction is chosen by the cost of the mistake, per hook.
# Driven through run_hook rather than farm_decision: the latter runs the hook inside a
# command substitution, so $ST and $ERR would still describe whatever ran before it.
run_hook "$(mk_bash_payload "$FARM_REPO" 'bash tests/run.sh')" "$FARM_OUT"
expect_empty "C5 farm-out STEPS ASIDE when its classifier cannot load (fail open)" "$OUT"
expect_eq "C5 …exiting 0" "0" "$ST"
expect_contains "C5 …naming the file it could not load, once, on stderr" "cmd-class.sh" "$ERR"
expect_eq "C5 …in exactly one line" "1" "$(printf '%s\n' "$ERR" | /usr/bin/grep -c .)"
expect_contains "C5 …and pointing at the diagnosis" "/bionic:doctor" "$ERR"

# BOTH ADVISORY WALLS WANT THE CLASSIFIER, and in one process both reach for it on this
# payload — so both step aside and both say so, one line each, each naming itself. Two
# walls stood down; a reader told once could not tell which.
run_compound "$(mk_bash_payload "$GREPO" 'bash tests/run.sh' "$AGENT_ID" true)"
expect_eq "C5 background-suite-guard STEPS ASIDE when its classifier cannot load" 0 "$ST"
expect_contains "C5 …naming the file it could not load" "cmd-class.sh" "$ERR"
expect_contains "C5 …and naming itself, not the compound" "background-suite-guard:" "$ERR"
expect_contains "C5 …beside farm-out-reminder, which wanted the same file" "farm-out-reminder:" "$ERR"
expect_eq "C5 …in exactly one line per wall" "2" "$(printf '%s\n' "$ERR" | /usr/bin/grep -c .)"

# THE COMPOUND STILL FAILS CLOSED ON WHAT THE CLOSED WALLS NEED (A-56.1). The classifier
# is absent on this very tree and a push is refused all the same — which is the whole
# point of a WANT that names only the two closed walls' libraries. Without it the fold
# made the WANT the union of five, and one advisory wall's missing file refused every
# Bash command in every project on the machine.
run_hook "$(mk_bash_payload "$FARM_REPO" 'git push origin main')" "$FARM_OUT"
expect_eq "C5 …while a push on the same tree is still REFUSED" "2" "$ST"
expect_contains "C5 …by protect-main, which never wanted the classifier" "push refused" "$ERR"
run_hook "$(mk_bash_payload "$FARM_REPO" 'ls')" "$FARM_OUT"
expect_eq "C5 …and an ordinary command still passes" "0" "$ST"

FARM_OUT="$C5_SAVED_FARM"; BG_GUARD="$C5_SAVED_BG"
# The shipped library was never touched, and everything after this line depends on that,
# so prove it rather than assume it.
expect_eq "C5 the library is back on disk" "suite" "$(class_of 'bash tests/run.sh')"

section "C6 — every source in payload/hooks/*.sh resolves inside payload/"
# A sourced library the installer misses is a silently inert wall (agent-context-guard.sh
# :106-108). The hooks are reachable under two spellings of one directory (see the header),
# so each literal is expanded under BOTH and the pin is: at least one expansion exists, and
# every expansion that exists lies under <repo>/payload/.
# Two literal shapes reach a sibling file from a hook: "$(dirname "$0")/<rel>.sh" (the
# handoff to a sibling SCRIPT) and "$(cd "$(dirname "$0")" … && pwd)/<name>.sh" (the
# sweeper handoff every stop hook uses).
#
# THE LIBRARY IS NO LONGER ONE OF THEM, and that is the bionic 1.4.0 change (task
# ADOPT, spec AC-16): the two class-(1) candidate spellings live inside the shared
# loader block, computed from a variable, so no `$(dirname "$0")/...` literal names a
# library any more. They are collected here explicitly, from the block itself, so this
# section still covers the reference that matters most — and covers BOTH spellings,
# which the old extractor never did (it only ever saw whichever one a hook wrote first).
#
# AND A HOOK'S `BIONIC_LIB_WANT` IS NO LONGER THE WHOLE SET (T23, A-56.1/A-57). The five
# PreToolUse|Bash walls share one process, and hooks/bash-walls.sh asks the loader only
# for what the two FAIL-CLOSED walls need — otherwise a file that merely makes an
# advisory wall step aside would refuse every Bash command on the machine. A library only
# an advisory wall reads is declared per wall in payload/scripts/lib/walls.sh's table and
# sourced there, by `wall_libs`, out of the same `$BIONIC_LIB` the loader resolved. So
# that table is the second place a class-(1) reference is declared, and this extractor
# reads it for the same reason it reads the WANT lines: the reference is real, it has to
# resolve inside the checkout, and nothing here may name a basename by hand.
#
# Both sweeps are DERIVED. Empty either declaration and the anti-vacuity rows at the end
# of this section go red rather than the sweep quietly covering less.
WALLS_LIB="$(dirname "$LIB")/walls.sh"
SRC_LITERALS=$( { /usr/bin/grep -hoE '\$\(dirname "\$0"\)/[^"]*\.sh' "$PAYLOAD_HOOKS"/*.sh \
                    | sed 's|^\$(dirname "\$0")||'
                  /usr/bin/grep -hoE '&& pwd\)/[^"]*\.sh' "$PAYLOAD_HOOKS"/*.sh \
                    | sed 's|^&& pwd)||'
                  # the loader's own class-(1) directories, one per wanted basename —
                  # from the hooks' WANT lines and from the per-wall table together,
                  # because both declare files sourced out of $BIONIC_LIB.
                  for _c6_want in $( { /usr/bin/grep -hoE '^BIONIC_LIB_WANT="[^"]*"' "$PAYLOAD_HOOKS"/*.sh \
                                         | sed -E 's/^BIONIC_LIB_WANT="//; s/"$//'
                                       /usr/bin/grep -hoE '^BIONIC_WALL_LIBS_[A-Za-z0-9_]*="[^"]*"' "$WALLS_LIB" \
                                         | sed -E 's/^BIONIC_WALL_LIBS_[A-Za-z0-9_]*="//; s/"$//'
                                     } 2>/dev/null | tr ' ' '\n' | sort -u); do
                    printf '/../scripts/lib/%s\n/../payload/scripts/lib/%s\n' "$_c6_want" "$_c6_want"
                  done
                } 2>/dev/null | sort -u)
if [ -n "$SRC_LITERALS" ]; then ok "payload/hooks reaches sibling files by relative path"; else
  no "payload/hooks reaches sibling files by relative path" "found none to check"
fi

# THREE READINGS OF ONE LITERAL, because the same file is reached three ways:
#   1. INSTALLED PLUGIN — payload/hooks is a real directory, `..` is lexical: the reading
#      that decides whether the shipped plugin can load the file at all.
#   2. ${CLAUDE_PLUGIN_ROOT} over this checkout — payload/hooks is a symlink, so the
#      kernel resolves `..` to <repo>, not to <repo>/payload.
#   3. tests/lib/resolve-roots.sh — <repo>/hooks directly.
# The pin: at least one reading finds the file (a reference nothing can resolve is the
# silently-inert-wall class, agent-context-guard.sh:106-108), and no reading escapes the
# checkout onto a path the plugin does not ship.
lexnorm() {  # lexical a/b/../c, no filesystem, no symlink following
  awk -v p="$1" 'BEGIN {
    n = split(p, a, "/"); k = 0
    for (i = 1; i <= n; i++) {
      if (a[i] == "" || a[i] == ".") continue
      if (a[i] == "..") { if (k > 0) k--; continue }
      st[++k] = a[i]
    }
    s = ""; for (i = 1; i <= k; i++) s = s "/" st[i]
    print (s == "" ? "/" : s)
  }'
}
SRC_BAD=""
while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  found=0
  # `../payload/scripts/lib/...` is the REPO spelling of the same directory: it resolves
  # only when payload/hooks is a symlink to <repo>/hooks, so under the installed-plugin
  # reading it is expected to find nothing. Its twin covers that reading, and the pin
  # below is per-basename, not per-spelling.
  case "$rel" in /../payload/scripts/lib/*) continue ;; esac
  for cand in "$(lexnorm "$PAYLOAD_HOOKS$rel")" "$PAYLOAD_HOOKS$rel" "$PLAIN_HOOKS$rel"; do
    [ -f "$cand" ] || continue
    found=1
    phys="$(cd "$(dirname "$cand")" && pwd -P)/$(basename "$cand")"
    case "$phys" in
      "$REPO_ROOT"/*) : ;;
      *) SRC_BAD="$SRC_BAD escapes-checkout:$rel($phys)" ;;
    esac
  done
  [ "$found" = 1 ] || SRC_BAD="$SRC_BAD unresolvable:$rel"
done <<EOF
$SRC_LITERALS
EOF
expect_eq "every relative sibling reference resolves, and never outside the checkout" "" "$SRC_BAD"
# The one that matters most, stated on its own: the shipped plugin — where payload/hooks is
# a real directory — can load the classifier from the primary spelling both hooks use.
expect_eq "the installed-plugin reading of the cmd-class source lands on the shipped library" \
  "$REPO_ROOT/payload/scripts/lib/cmd-class.sh" \
  "$(lexnorm "$PAYLOAD_HOOKS/../scripts/lib/cmd-class.sh")"
# ANTI-VACUITY: the extractor must actually see every shape it claims to cover.
expect_contains "…and the extractor sees the cmd-class library (shape A)" "cmd-class.sh" "$SRC_LITERALS"
expect_contains "…and the sweeper handoff (shape B)" "session-sweeper.sh" "$SRC_LITERALS"
# WHERE SHAPE A FINDS THE CLASSIFIER NOW, stated so the row above cannot pass on the
# wrong declaration: the Bash walls' process does not name cmd-class.sh on its WANT line,
# and the per-wall table does — the two walls that read it source it there, below the
# partition. If the sweep of that table were dropped, the Bash process's declaration would
# be missing from the sweep, which is what happened when the fold moved the source site.
#
# SCOPED TO hooks/bash-walls.sh SINCE wave-20 T4 (REQ-7, D7). hooks/dispatch-preflight.sh
# now declares cmd-class.sh on its own WANT line — its lift pastes the library's one run
# normaliser into `collapse()` — so "no hook's WANT line names it" stopped being true by
# design. What this row guards is the Bash process's declaration, and that is unchanged.
expect_absent "…and the Bash walls' own WANT line does not name it, which is why the table is swept" \
  "cmd-class.sh" "$(/usr/bin/grep -hoE '^BIONIC_LIB_WANT="[^"]*"' "$PAYLOAD_HOOKS"/bash-walls.sh)"
expect_nonempty "…(non-vacuity: the Bash walls do declare a WANT line to read)" \
  "$(/usr/bin/grep -hoE '^BIONIC_LIB_WANT="[^"]*"' "$PAYLOAD_HOOKS"/bash-walls.sh)"
expect_contains "…while the per-wall table declares it, for the two walls that read it" \
  "cmd-class.sh" "$(/usr/bin/grep -hoE '^BIONIC_WALL_LIBS_[A-Za-z0-9_]*="[^"]*"' "$WALLS_LIB")"

section "C6 — the session never invoked the skill: neither hook is there (AC-6, AC-20)"
#
# THE PAIRED WORLD for C2/C3 and C4. Chris, 2026-09-03: "all guardrails imposed by bionic
# should only apply when exercising bionic. Nothing should apply until bionic is
# triggered." Both hooks read `.bionic/tmp/engaged-<sid>.state` before anything else, so
# with the marker removed the suite commands every arm above denies pass in silence: exit
# 0, nothing on stdout, nothing on stderr.
#
# Each fixture here is one an arm above REFUSES, unengaged and then re-engaged, so no row
# can pass on a hook that had simply stopped working.

# --- farm-out-reminder: the deny and the nudge both go quiet (AC-6) ---
unengage "$FARM_REPO"
run_hook "$(mk_bash_payload "$FARM_REPO" 'bash tests/run.sh')" "$FARM_OUT"
expect_empty "AC-6 farm-out is SILENT on a suite command in an unengaged session" "$OUT"
expect_empty "AC-6 …and says nothing on stderr either" "$ERR"
expect_eq "AC-6 …exiting 0" "0" "$ST"

run_hook "$(mk_bash_payload "$FARM_REPO" 'docker run x')" "$FARM_OUT"
expect_empty "AC-6 …the tier-2 nudge is silent too" "$OUT$ERR"

# THE OVERRIDE IS NOT CONSULTED, because there is nothing to override: an audit line
# recording a bypass of a wall that was never going to fire is noise in the one stream
# that has to stay readable.
run_hook "$(mk_bash_payload "$FARM_REPO" 'FARM_OUT_ALLOW=1 bash tests/run.sh')" "$FARM_OUT"
expect_empty "AC-6 …and an explicit override is silent rather than audited" "$OUT$ERR"

# A SYMLINK at the marker path is not a marker (lib/run.sh refuses `-L` before following
# it), and neither is another session's.
ln -s "$FARM_CLOSED/.bionic/tmp" "$FARM_REPO/.bionic/tmp/engaged-$SID.state" 2>/dev/null
run_hook "$(mk_bash_payload "$FARM_REPO" 'bash tests/run.sh')" "$FARM_OUT"
expect_empty "AC-6 …a SYMLINK at the marker path is not engagement" "$OUT$ERR"
rm -f "$FARM_REPO/.bionic/tmp/engaged-$SID.state"
: > "$FARM_REPO/.bionic/tmp/engaged-00000000-1111-2222-3333-444444444444.state"
run_hook "$(mk_bash_payload "$FARM_REPO" 'bash tests/run.sh')" "$FARM_OUT"
expect_empty "AC-6 …another session's marker is not engagement" "$OUT$ERR"

# CONTROL: restore the marker and the identical command denies again.
engage "$FARM_REPO"
expect_contains "AC-6 control: with the marker back, the same suite command DENIES" \
  '"deny"' "$(farm_decision 'bash tests/run.sh')"

# --- background-suite-guard: the same, inside the compound (AC-20) ---
#
# THE ENGAGEMENT GUARD IS AHEAD OF ALL FIVE NOW, in hooks/bash-walls.sh, which is why the
# unengaged rows below are silent on BOTH streams rather than only on the background arm's:
# no wall runs at all. That is the same answer the five hooks gave one by one, asked once.
unengage "$GREPO"
run_compound "$(mk_bash_payload "$GREPO" 'bash tests/run.sh' "$AGENT_ID" true)"
expect_eq "AC-20 a backgrounded suite passes an unengaged session" "0" "$ST"
expect_empty "AC-20 …silently" "$OUT$ERR"

# A SECOND UNENGAGED PAYLOAD, so the silence is the marker's doing and not this one
# command's: a push is the loudest thing in the tree and it too says nothing here.
run_compound "$(mk_bash_payload "$GREPO" 'git push origin main' "$AGENT_ID" true)"
expect_eq "AC-20 …and so does a push, which no wall is armed to see" "0" "$ST"
expect_empty "AC-20 …still silently" "$OUT$ERR"

# CONTROL: the marker back, the same payload refuses again.
engage "$GREPO"
run_compound "$(mk_bash_payload "$GREPO" 'bash tests/run.sh' "$AGENT_ID" true)"
expect_contains "AC-20 control: with the marker back, the wall REFUSES again" "$BSG_REASON" "$OUT"

section "C7 — cmd_suite_targets: WHICH suite a command runs (S13, AC-21)"
# The budget arm cannot compare a command to a set of suite basenames without knowing which
# basenames the command names. That reading is here, beside the class, because it is the
# same reading: `cmd_class` and `cmd_suite_targets` answer off the same argv positions, and
# a second matcher outside this library would have to re-implement strip_leading,
# unwrap_runner and the quote-aware tokeniser to see them.
#
# MEASURED IN BOTH DIRECTIONS, per the library`s own superset note (:47-51: "Any new arm
# here is a wall — measure both directions"). Every spelling the class arm recognises must
# also NAME its suite, or the budget arm silently allows what the class arm caught; and no
# spelling the class arm rejects may name one, or the budget arm refuses prose.

targets_of() {  # <command> -> the library's targets, newline-joined
  printf '%s' "$1" | bash -c '
    set -uo pipefail
    . "$1" || { echo "SOURCE-FAILED"; exit 1; }
    cmd_suite_targets "$(cat)"
  ' _ "$LIB" 2>&1
}

targets_are() {  # <expected, newline-joined> <command>
  expect_eq "targets [$2]" "$1" "$(targets_of "$2")"
}

# --- direction 1: every suite-class spelling names the file it runs ---
targets_are 'run.sh'       'bash tests/run.sh'
targets_are 'run.sh'       'bash tests/run.sh --serial'
targets_are 'run.sh'       'bash -x tests/run.sh'
targets_are 'cmd-class.test.sh' 'bash tests/cmd-class.test.sh'
targets_are 'test.sh'      'bash test.sh'
targets_are 'run.sh'       './tests/run.sh'
targets_are 'run.sh'       'tests/run.sh'
targets_are 'run.sh'       'cd tests && bash run.sh'
targets_are 'run.sh'       '(cd tests; bash run.sh)'
targets_are 'run.sh'       'sudo bash tests/run.sh'
targets_are 'run.sh'       '( bash tests/run.sh )'
targets_are 'run.sh'       'if true; then bash tests/run.sh; fi'
targets_are 'run.sh'       'FARM_OUT_ALLOW=1 bash tests/run.sh'
targets_are 'run.sh'       'PIN=/tmp/p PATH=$PIN:$PATH bash tests/run.sh'
targets_are 'loader.test.sh' 'bash "$REPO/tests/loader.test.sh"'
targets_are 'width.test.sh' 'bash tests/width.test.sh 2>&1 | tee /tmp/w.log'

# THE WHOLE POINT OF THE SET: a chain names every suite in it, in position order.
targets_are 'a.test.sh
b.test.sh' 'bash tests/a.test.sh && bash tests/b.test.sh'
targets_are 'a.test.sh
run.sh' 'bash tests/a.test.sh; ./tests/run.sh'
# …and a suite named twice is one claim, not two.
targets_are 'a.test.sh' 'bash tests/a.test.sh && bash tests/a.test.sh'

# THE SUPERSET ARRAY ITSELF, so a spelling added to the class arm cannot be added without
# an answer here. Both halves asserted per spelling: it classifies AND it names a target.
for sc in "${SUPERSET_SUITES[@]}"; do
  expect_eq "C7 [$sc] is suite-class" "suite" "$(class_of "$sc")"
  expect_eq "C7 …and names its suite" "run.sh" "$(targets_of "$sc")"
done

# --- direction 2: nothing else names one ---
targets_are '' 'git status --short'
targets_are '' 'echo "bash tests/run.sh"'
targets_are '' 'echo run bash tests/run.sh first'
targets_are '' 'git commit -m "make the row green"'
targets_are '' 'ls tests/run.sh'
targets_are '' 'bash run.sh'
targets_are '' 'cat <<EOF
bash tests/run.sh
EOF'
# SUITE-CLASS BUT FILELESS. These run a suite and name no file this repo budgets by, so the
# budget arm has nothing to compare and stands aside — asserted rather than assumed,
# because a target invented for them would refuse a project bionic has no row about.
for fileless in 'pytest' 'npm test' 'go test ./...' 'make test' 'make check' 'cargo test'; do
  expect_eq "C7 [$fileless] is suite-class" "suite" "$(class_of "$fileless")"
  expect_eq "C7 …and names no suite FILE" "" "$(targets_of "$fileless")"
done


section "C8 — the SCOPED reading: which repo's suite, and a mode that runs nothing (K-2, A-7, A-36a)"
# THE DEFECT. `cmd_suite_targets` answered with a BASENAME and nothing else, so the budget
# arm judged any file on the machine named `*.test.sh` against THIS repository's roster.
# Three false refusals were hit without trying (critic K-2): a scratch probe at
# /tmp/critic-probe/probe2.test.sh, an unexpanded `$t.test.sh`, and `bash tests/run.sh
# --dry-run`, a mode whose whole documented behaviour is to run nothing (the walk, A-36a).
#
# THE CURE, in two halves. (a) An optional SECOND argument names the repository the answer
# is about; with it, a segment names a target only when the path it runs resolves to that
# repo's `tests/<basename>`. (b) A suite-class segment carrying `--dry-run` names no target
# at all — the runner's own "run nothing" mode is not an instrument spend.
#
# WHY SHAPE AND NOT EXISTENCE. The resolved path is compared to `<root>/tests/<basename>`;
# it is NOT stat'd. A hook that refused only files it could see would allow a suite the
# writer is about to create, and would make the wall's answer depend on the filesystem at
# hook time rather than on the command. The class this closes is "a path somewhere else",
# and the path says that on its own.

targets_of_in() {  # <repo root> <command> -> the library's targets, scoped to that root
  printf '%s' "$2" | bash -c '
    set -uo pipefail
    . "$1" || { echo "SOURCE-FAILED"; exit 1; }
    cmd_suite_targets "$(cat)" "$2"
  ' _ "$LIB" "$1" 2>&1
}

C8_ROOT="$SANDBOX/c8repo"
mkdir -p "$C8_ROOT/tests"

targets_in_are() {  # <expected> <command>
  expect_eq "C8 targets [$2] under the repo root" "$1" "$(targets_of_in "$C8_ROOT" "$2")"
}

# --- (a) this repo's tests/, and nothing else ---
targets_in_are 'run.sh'          'bash tests/run.sh'
targets_in_are 'run.sh'          './tests/run.sh'
targets_in_are 'alpha.test.sh'   'bash tests/alpha.test.sh'
targets_in_are 'alpha.test.sh'   "bash $C8_ROOT/tests/alpha.test.sh"
# …and the same basename anywhere else on the machine is NOT this row's business.
targets_in_are ''                'bash /tmp/critic-probe/probe2.test.sh'
targets_in_are ''                'bash /some/other/tree/tests/run.sh'
targets_in_are ''                'bash ../sibling/tests/alpha.test.sh'
targets_in_are ''                'bash scratch/alpha.test.sh'

# THE cd-LICENSED BASENAME FORM STAYS NAMED. `cd tests && bash run.sh` records no
# directory to resolve against, so the reading cannot say which tree it is in — and the
# full tree is the one act this arm fails CLOSED on. Named, therefore refusable.
targets_in_are 'run.sh'          'cd tests && bash run.sh'

# AN UNEXPANDED VARIABLE STAYS NAMED TOO, deliberately: the guard has a refusal written
# for exactly this state (C-5), and it can only give it if the reading hands the token up.
targets_in_are '$s.test.sh'      'bash "tests/$s.test.sh"'

# --- (b) --dry-run runs nothing, so it spends nothing ---
targets_in_are ''                'bash tests/run.sh --dry-run'
targets_in_are ''                'bash tests/run.sh --dry-run 2>&1 | tee /tmp/d.log'
# THE CLASS FOLLOWS NOW (wave-24 T5, AC-7.5). This row used to pin `--dry-run` as still
# suite-CLASS, and on the main thread that class drew the farm-out deny for a command that
# runs nothing (research R4 §4). §CASE below owns the whole flag set.
expect_eq "C8 …and --dry-run is not suite-class either" \
  "none" "$(class_of 'bash tests/run.sh --dry-run')"
# The exemption is the flag, not the runner: a real run beside it is still named.
targets_in_are 'run.sh'          'bash tests/run.sh --serial'

# --- the unscoped call is unchanged: no root, the legacy basename answer ---
expect_eq "C8 with no root the answer is the bare basename, as before" \
  "probe2.test.sh" "$(targets_of 'bash /tmp/critic-probe/probe2.test.sh')"

section "C9 — cmd_backgrounded: a shell-backgrounded suite is caught like a tool-backgrounded one (D8, REQ-6)"
# research row 6: cmd_class already reads every one of these as suite-class; the gap is
# that nothing asked whether the TEXT itself backgrounds it. cmd_backgrounded is the new,
# single answer to that question — 0 (true) when the command backgrounds, 1 otherwise —
# read positionally (a bare `&` control operator, never one folded into `&&` or a `2>&1`
# redirect; or a `nohup`/`setsid` wrapper), the same discipline as every other reading in
# this file.
bg_of() {  # <command> -> "yes"/"no" per cmd_backgrounded's exit status
  printf '%s' "$1" | bash -c '
    set -uo pipefail
    . "$1" || { echo "SOURCE-FAILED"; exit 1; }
    if cmd_backgrounded "$(cat)"; then echo yes; else echo no; fi
  ' _ "$LIB" 2>&1
}
bg_is() {  # <expected: yes|no> <command> [label]
  local want="$1" cmd="$2" got
  got=$(bg_of "$cmd")
  expect_eq "${3:-$want: $cmd}" "$want" "$got"
}

# --- the six shell-backgrounded forms (AC-6.1) ---
bg_is yes 'bash tests/run.sh &'
bg_is yes 'nohup bash tests/run.sh &'
bg_is yes 'while :; do bash tests/run.sh; done &'
bg_is yes '( bash tests/run.sh ) &'
bg_is yes 'bash tests/run.sh > /tmp/x.log 2>&1 &'
bg_is yes 'bash tests/run.sh & disown'

# --- the wrapper form (AC-6.2): setsid alone, no trailing & at all ---
bg_is yes 'setsid bash tests/run.sh'

# --- foreground forms untouched (AC-6.3) ---
bg_is no 'bash tests/run.sh'
bg_is no 'bash tests/x.test.sh > /tmp/log 2>&1; echo rc=$?'
bg_is no 'bash tests/run.sh && echo done'
# a `&` INSIDE QUOTES is not a separator — it is an argument, or prose, never backgrounding
bg_is no 'bash tests/run.sh --note "a & b"'
bg_is no 'echo "sudo bash tests/run.sh &"'
# `2>&1` alone, with no trailing bare `&`, backgrounds nothing
bg_is no 'bash tests/run.sh 2>&1 | tee /tmp/evidence.log'

section "C10 — REQ-1 AC-1.5 / REQ-5 AC-5.1-5.2: a runner names its RUN, a flag that runs nothing is not a run"
# TWO HALVES OF ONE READING, both measured here because both are the same question asked
# of argv: does this command RUN a suite, and — when it does — WHICH run is it.
#
# (a) REQ-1 AC-1.5. `pytest`, `npm test`, `go test`, `jest` and `npx jest` have been
#     suite-CLASS since wave-01 and named nothing at all, because the only target this
#     library knew how to name was a shell suite FILE. A target-less suite-class command
#     cannot be compared to anything, so `payload/scripts/lib/walls.sh`'s budget arm had
#     nothing to hold a writer in a jest repo to (research R1 Q2: "it is not that the arm
#     rejects jest, it is that the arm cannot see it"). A runner form now names its RUN —
#     the argv text the classifier read, whitespace-collapsed — which is exactly the shape
#     `hooks/dispatch-preflight.sh` writes onto the roster row under `re_executes=`
#     (A-T1.4: the author's marked run, collapsed), so the two ends compare.
#
# (b) REQ-5 AC-5.1/5.2. `bash -n <suite>` READS a suite and runs none of it; the flag skip
#     at the bash arm treated `-n` as an ordinary option and classified the same words as a
#     run. The table below is the discriminator: a non-executing flag makes the command
#     `none`, and `-x`/`-v`, which do execute, stay `suite`.
#
# THE SUPERSET RULE CUTS BOTH WAYS HERE (:47-51). Widening the class is a wall that can
# now refuse what it used to allow, so every row below is stated in both directions: the
# runner forms name a run AND still name no suite FILE (C7's answer is unchanged), and the
# reading forms are `none` AND silent at the farm-out wall.

claims_of() {  # <command> -> "<kind>\t<target>\t<run>" per suite-class segment
  printf '%s' "$1" | bash -c '
    set -uo pipefail
    . "$1" || { echo "SOURCE-FAILED"; exit 1; }
    cmd_suite_claims "$(cat)"
  ' _ "$LIB" 2>&1
}
claim_kinds_of() { claims_of "$1" | awk -F'\t' '{ print $1 }'; }
claim_run_of()   { claims_of "$1" | awk -F'\t' 'NR == 1 { print $3 }'; }

# --- (a) AC-1.5: every runner form names the run it will make ---
runner_row() {  # <command>
  expect_eq "C10 [$1] is suite-class" "suite" "$(class_of "$1")"
  expect_eq "C10 …and names the RUN it will make, not nothing" "$1" "$(claim_run_of "$1")"
  expect_eq "C10 …as a run, not as a suite file" "run" "$(claim_kinds_of "$1")"
  expect_eq "C10 …and C7's answer is unchanged: it names no suite FILE" "" "$(targets_of "$1")"
}
runner_row "npx jest --testPathPatterns 'x'"
runner_row "jest --testPathPatterns 'x'"
runner_row 'npx jest'
runner_row 'pytest tests/x.py'
runner_row 'go test ./...'
runner_row 'npm test'

# The run is the text the CLASSIFIER read, so the prefixes this library already strips do
# not change which run a command is — `timeout 600 npx jest …` is the same spend as
# `npx jest …`, and a writer who declared one has declared the other.
expect_eq "C10 a stripped prefix leaves the same run" \
  "npx jest --testPathPatterns 'x'" "$(claim_run_of "timeout 600 npx jest --testPathPatterns 'x'")"
expect_eq "C10 …and so does wider spacing (collapsed, as the lift collapses it)" \
  "npx jest --testPathPatterns 'x'" "$(claim_run_of "npx    jest   --testPathPatterns 'x'")"

# A SHELL SUITE STILL ANSWERS AS A FILE, with its run beside it — the budget arm needs both
# (the basename to compare against `suites_allowed=`, the run to compare against
# `re_executes=`), and a file that answered only as a run would silently retire AC-21.
expect_eq "C10 a shell suite is still a FILE claim" "file" "$(claim_kinds_of 'bash tests/alpha.test.sh')"
expect_eq "C10 …carrying its run beside the basename" \
  "bash tests/alpha.test.sh" "$(claim_run_of 'bash tests/alpha.test.sh')"

# NEGATIVE CONTROL: `npx` is not a suite verb. Stripping it must not make every npx call a
# suite — the tier-2 nudge (B-4a) is the wall that speaks for those.
expect_eq "C10 npx create-react-app is NOT suite-class" "none" "$(class_of 'npx create-react-app x')"
expect_eq "C10 …and names no run" "" "$(claims_of 'npx create-react-app x')"

# --- (b) AC-5.1: a flag that runs nothing is not a run ---
reads_only() {  # <command>
  expect_eq "C10 [$1] runs nothing, so it is not suite-class" "none" "$(class_of "$1")"
  expect_eq "C10 …and names nothing for a budget to hold" "" "$(claims_of "$1")"
}
reads_only 'bash -n tests/x.test.sh'
reads_only 'bash --noexec tests/x.test.sh'
reads_only 'bash -nx tests/x.test.sh'
reads_only 'bash -xn tests/x.test.sh'
reads_only 'bash -o noexec tests/x.test.sh'
reads_only 'chmod +x tests/x.test.sh'
reads_only 'cat tests/x.test.sh'
reads_only 'ls tests/*.test.sh'

# AT THE WALL, not just in the library: AC-5.1's words are "pass the farm-out wall".
expect_empty "AC-5.1 farm-out is SILENT on bash -n tests/x.test.sh" \
  "$(farm_decision 'bash -n tests/x.test.sh')"
expect_empty "AC-5.1 …on chmod +x tests/x.test.sh" \
  "$(farm_decision 'chmod +x tests/x.test.sh')"
expect_empty "AC-5.1 …on cat tests/x.test.sh" \
  "$(farm_decision 'cat tests/x.test.sh')"
expect_empty "AC-5.1 …on ls tests/*.test.sh" \
  "$(farm_decision 'ls tests/*.test.sh')"

# --- (b) AC-5.2: the flags that DO execute are untouched ---
still_runs() {  # <command> <expected target>
  expect_eq "C10 [$1] still executes, so it stays suite-class" "suite" "$(class_of "$1")"
  expect_eq "C10 …and still names its suite" "$2" "$(targets_of "$1")"
}
still_runs 'bash tests/x.test.sh' 'x.test.sh'
still_runs 'bash -x tests/x.test.sh' 'x.test.sh'
still_runs 'bash -v tests/x.test.sh' 'x.test.sh'
still_runs 'bash -o errexit tests/x.test.sh' 'x.test.sh'
# The ANTI-VACUITY arm for the table: the letter that disqualifies is read on its own, not
# as a substring of every flag that happens to contain it.
still_runs 'bash --verbose tests/x.test.sh' 'x.test.sh'



section "C11 — REQ-7 AC-7.1 (wave-20 T4, D7): a redirected run is the same run"
# THE SPELLING TABLE. A run claim used to carry its segment's redirections, so
# `npx jest x 2>&1` claimed the run `npx jest x 2>&1` and the budget arm compared that,
# exactly, to the author's declared `npx jest x` — and refused the spelling every role
# file prescribes for saving evidence (triage-B B1). Redirections, a trailing `| tee`,
# and `|| true` change where the output goes and whether a failure stops the shell; none
# of them changes what runs. ONE HELPER, `cmd_run_norm`, strips them; it is what builds
# LAST_RUN here, what walls.sh applies to the declared side, and what the dispatch lift's
# `collapse()` calls. This section owns the table; the walls' rows are in
# tests/bash-walls.test.sh section 19.
#
# fails-when: any of the eight spellings normalises to anything but the bare command, a
# quoted `>` or `|` is stripped, or two runs differing only inside quotes normalise equal.

norm_of() {  # <command> -> cmd_run_norm's answer
  bash -c '. "$1" || { echo "SOURCE-FAILED"; exit 1; }; cmd_run_norm "$2"' _ "$LIB" "$1" 2>&1
}
runs_norm_of() {  # <marked field> -> cmd_runs_norm's answer
  bash -c '. "$1" || { echo "SOURCE-FAILED"; exit 1; }; cmd_runs_norm "$2"' _ "$LIB" "$1" 2>&1
}
T4_P='/tmp/t4-ev.log'
t4_spellings() {  # <bare run> — the eight spellings AC-7.1 names, each against the bare run
  local j="$1"
  expect_eq "C11 [$j] > p normalises to the bare run"          "$j" "$(norm_of "$j > $T4_P")"
  expect_eq "C11 [$j] >> p normalises to the bare run"         "$j" "$(norm_of "$j >> $T4_P")"
  expect_eq "C11 [$j] 2>&1 normalises to the bare run"         "$j" "$(norm_of "$j 2>&1")"
  expect_eq "C11 [$j] &> p normalises to the bare run"         "$j" "$(norm_of "$j &> $T4_P")"
  expect_eq "C11 [$j] | tee p normalises to the bare run"      "$j" "$(norm_of "$j | tee $T4_P")"
  expect_eq "C11 [$j] 2>&1 | tee p normalises to the bare run" "$j" "$(norm_of "$j 2>&1 | tee $T4_P")"
  expect_eq "C11 [$j] |& tee p normalises to the bare run"     "$j" "$(norm_of "$j |& tee $T4_P")"
  expect_eq "C11 [$j] || true normalises to the bare run"      "$j" "$(norm_of "$j || true")"
  # THE CLAIM SIDE, through the same reading the budget arm uses. The splitter already cut
  # `|`, `|&` and `||`; what reaches LAST_RUN for the other spellings is the redirect.
  expect_eq "C11 [$j] > p 2>&1 CLAIMS the bare run"           "$j" "$(claim_run_of "$j > $T4_P 2>&1")"
  expect_eq "C11 [$j] 2>&1 CLAIMS the bare run"               "$j" "$(claim_run_of "$j 2>&1")"
  expect_eq "C11 [$j] &> p CLAIMS the bare run"               "$j" "$(claim_run_of "$j &> $T4_P")"
  expect_eq "C11 [$j] 2>&1 | tee p CLAIMS the bare run"       "$j" "$(claim_run_of "$j 2>&1 | tee $T4_P")"
}
t4_spellings "npx jest --testPathPatterns 'x'"
t4_spellings 'bash tests/gamma.test.sh'
t4_spellings 'pytest tests/unit'

# THE OTHER SHAPES A REDIRECTION TAKES, each one a trailing redirection too.
J4="npx jest --testPathPatterns 'x'"
expect_eq "C11 a target glued to its operator (>p) is one redirection" "$J4" "$(norm_of "$J4 >$T4_P")"
expect_eq "C11 a numbered stream to a file (2>/dev/null)" "$J4" "$(norm_of "$J4 2>/dev/null")"
expect_eq "C11 both orders of the pair (2>&1 > p)" "$J4" "$(norm_of "$J4 2>&1 > $T4_P")"
expect_eq "C11 tee with its append flag (| tee -a p)" "$J4" "$(norm_of "$J4 2>&1 | tee -a $T4_P")"
expect_eq "C11 a quoted target with a space in it is one word" "$J4" "$(norm_of "$J4 > \"a b.log\" 2>&1")"
expect_eq "C11 wider spacing collapses as it always did" "$J4" "$(norm_of "npx   jest  --testPathPatterns 'x'   2>&1")"

# QUOTED TEXT IS AN ARGUMENT, NOT PLUMBING — kept whole, character for character.
expect_eq "C11 a quoted > is kept" "jest -t 'a > b'" "$(norm_of "jest -t 'a > b'")"
expect_eq "C11 a quoted | tee is kept" 'jest -t "x | tee y"' "$(norm_of 'jest -t "x | tee y"')"
expect_eq "C11 a quoted run with a redirect after it keeps the quotes" \
  "jest -t 'a b'" "$(norm_of "jest -t 'a b' > $T4_P")"
expect_ne "C11 two runs differing only inside quotes stay different" \
  "$(norm_of "jest -t 'a b' 2>&1")" "$(norm_of "jest -t 'c d' 2>&1")"

# WHAT IS NOT A TRAILING REDIRECTION STAYS. Anti-vacuity for the table above: a helper that
# cut at the first operator, or kept only argv[0..1], would pass every row before this.
expect_eq "C11 a pipe into something that is not tee is kept" \
  'pytest tests/unit | grep -v skip' "$(norm_of 'pytest tests/unit | grep -v skip')"
expect_eq "C11 a chain is kept" 'pytest tests/unit && echo done' "$(norm_of 'pytest tests/unit && echo done')"
expect_eq "C11 || with something other than true is kept" \
  'pytest tests/unit || echo failed' "$(norm_of 'pytest tests/unit || echo failed')"
expect_eq "C11 an input redirection is not stripped (it changes what runs)" \
  'pytest tests/unit < in.txt' "$(norm_of 'pytest tests/unit < in.txt')"
expect_eq "C11 a bare run is itself" "$J4" "$(norm_of "$J4")"

# THE DECLARED SIDE: a marked field, each run normalised inside its own marks.
T4_BT='`'
expect_eq "C11 cmd_runs_norm normalises each marked run and keeps the marks" \
  "${T4_BT}npx jest x${T4_BT} ${T4_BT}pytest tests/unit${T4_BT}" \
  "$(runs_norm_of "${T4_BT}npx jest x 2>&1${T4_BT} ${T4_BT}pytest tests/unit > $T4_P${T4_BT}")"
expect_eq "C11 …and leaves a field with nothing to strip byte-identical" \
  "${T4_BT}npx jest --testPathPatterns 'x|y'${T4_BT}" \
  "$(runs_norm_of "${T4_BT}npx jest --testPathPatterns 'x|y'${T4_BT}")"
expect_eq "C11 …and an empty field is empty" "" "$(runs_norm_of '')"


section "§WAIT — REQ-7 AC-7.3 (D12): a fan-out that waits is not backgrounded"
# THE FALSE REFUSAL (research R4 §2). `cmd_backgrounded` answered yes for any bare `&`, so
# `a & b & wait` — two suites in parallel, the shell held until both finish — was refused as
# if its result could never be read. The rule now: a `&` job is PENDING in its subshell
# group until an unconditional bare `wait` in that same group, outside any branch the job
# was not also in, and not a pipeline stage. A job still pending at the end backgrounds.
# Driven through C9's `bg_of`, whose positive rows (C9) sit beside these.
bg_is no  'bash tests/a.test.sh & bash tests/b.test.sh & wait'
bg_is no  '(bash tests/a.test.sh & bash tests/b.test.sh & wait)'
bg_is no  '( bash tests/a.test.sh & bash tests/b.test.sh & wait ) 2>&1 | tee /tmp/w.log'
bg_is no  'bash tests/a.test.sh & bash tests/b.test.sh &
wait'
bg_is no  'for s in a b; do bash tests/$s.test.sh & done; wait'
bg_is no  'for s in a b; do bash tests/$s.test.sh & wait; done'
bg_is no  'bash tests/a.test.sh & bash tests/b.test.sh & wait; echo rc=$?'
# STILL REFUSED — every shape the requirement names, and the branch shapes beside them.
bg_is yes 'bash tests/a.test.sh &'
bg_is yes 'bash tests/a.test.sh & bash tests/b.test.sh'
bg_is yes '(bash tests/a.test.sh &); wait'
bg_is yes 'bash tests/a.test.sh & false && wait'
bg_is yes 'bash tests/a.test.sh & wait | cat'
bg_is yes 'bash tests/a.test.sh & p=$!; wait $p'
bg_is yes 'nohup bash tests/a.test.sh'
bg_is yes 'setsid bash tests/a.test.sh'
bg_is yes 'bash tests/a.test.sh & (wait)'
bg_is yes 'bash tests/a.test.sh & wait %1; bash tests/b.test.sh &'
bg_is yes 'bash tests/a.test.sh & wait &'
bg_is yes 'bash tests/a.test.sh & if true; then wait; fi'
bg_is yes 'bash tests/a.test.sh & if true; then
wait
fi'
bg_is yes 'case $x in a) bash tests/a.test.sh & ;; b) wait;; esac'
bg_is yes 'if c; then bash tests/a.test.sh & else wait; fi'
bg_is yes 'nohup bash tests/a.test.sh & wait'
# `wait $p` must be pinned against a positive on the same shape, or a wait-parser that
# admitted nothing would pass it: `wait` with no operand is the admit, one word apart.
bg_is no  'bash tests/a.test.sh & wait'


section "§CASE — REQ-7 AC-7.5 (D12): a flag that runs nothing, and the words of a case"
# TWO FALSE REFUSALS AND ONE BYPASS (research R4 §4). `tests/run.sh --dry-run`, `-h`,
# `--help` and `--list` read as suite-class, so the main-thread farm-out wall denied a
# command that runs nothing; a suite named only in a `case` PATTERN landed at argv[0] and
# read as a run; and a suite run inside a case ARM read as `case` at argv[0], class none.
for ro in 'bash tests/run.sh --dry-run' './tests/run.sh --list' 'bash tests/run.sh --help' \
          'tests/run.sh -h' 'bash tests/run.sh --serial --dry-run'; do
  expect_eq "§CASE [$ro] is not a suite run" "none" "$(class_of "$ro")"
  expect_eq "§CASE …and claims nothing" "" "$(claims_of "$ro")"
done
expect_empty "§CASE farm-out is SILENT on bash tests/run.sh --dry-run" \
  "$(farm_decision 'bash tests/run.sh --dry-run')"
# POSITIVE, SAME EXTRACTORS: --serial alone is the full tree, and a suite file is not
# exempted by a flag it does not take.
expect_eq "§CASE --serial alone is still a full-tree run" "suite" "$(class_of 'bash tests/run.sh --serial')"
expect_eq "§CASE …naming run.sh" "run.sh" "$(targets_of 'bash tests/run.sh --serial')"
expect_eq "§CASE ./tests/run.sh is still a run" "run.sh" "$(targets_of './tests/run.sh')"
expect_eq "§CASE a suite file given --help is still that suite's run" \
  "a.test.sh" "$(targets_of 'bash tests/a.test.sh --help')"

# THE PATTERN LIST IS NOT A COMMAND.
expect_eq "§CASE a suite named only in a (pattern) is not a run" \
  "none" "$(class_of 'case $x in (tests/b.test.sh) echo b;; esac')"
expect_eq "§CASE …nor in an alternation" \
  "none" "$(class_of 'case $f in a) :;; tests/run.sh|tests/b.test.sh) echo hit;; esac')"
expect_eq "§CASE …and names nothing" "" \
  "$(targets_of 'case $f in a) :;; tests/run.sh|tests/b.test.sh) echo hit;; esac')"
# THE ARM BODY IS. Same extractor, same shape, the suite moved from pattern to body.
expect_eq "§CASE a suite run inside a case arm is a run" \
  "suite" "$(class_of 'case $x in a) bash tests/a.test.sh;; esac')"
targets_are 'a.test.sh' 'case $x in a) bash tests/a.test.sh;; esac'
targets_are 'b.test.sh' 'case $x in a) echo;; b) bash tests/b.test.sh;; esac'
targets_are 'a.test.sh' 'case $x in a) bash tests/a.test.sh; esac'
targets_are 'a.test.sh' 'case "$x" in
  a|b) bash tests/a.test.sh ;;
  *) echo no ;;
esac'
targets_are 'c.test.sh' 'case $x in a) :;; esac; bash tests/c.test.sh'
targets_are 'a.test.sh
b.test.sh' 'case $x in a) case $y in q) bash tests/a.test.sh;; esac;; b) bash tests/b.test.sh;; esac'
targets_are 'a.test.sh' 'for x in 1; do case $x in 1) bash tests/a.test.sh;; esac; done'


section "§REDIR — REQ-7 AC-7.6 (D12): a leading redirection is plumbing, never argv[0]"
# THE FALSE REFUSAL AND THE BYPASS (research R4 §5). `strip_leading` had no rule for a
# redirection, so a GLUED input redirect (`<tests/a.test.sh wc -l`) put the suite path at
# argv[0] and read as a run of it, while a redirect IN FRONT of a real run
# (`2>/dev/null bash tests/a.test.sh`) left `2>/dev/null` at argv[0] and read as none.
for rd in '<tests/a.test.sh wc -l' '<$R/tests/a.test.sh wc -l' \
          'while read l; do :; done <$R/tests/a.test.sh' '< tests/a.test.sh wc -l' \
          '<"tests/a.test.sh" wc -l'; do
  expect_eq "§REDIR [$rd] reads a suite file, it does not run it" "none" "$(class_of "$rd")"
  expect_eq "§REDIR …and claims nothing" "" "$(claims_of "$rd")"
done
expect_empty "§REDIR farm-out is SILENT on <tests/a.test.sh wc -l" \
  "$(farm_decision '<tests/a.test.sh wc -l')"
for rr in '2>/dev/null bash tests/a.test.sh' '>log bash tests/a.test.sh' \
          '< /dev/null bash tests/a.test.sh' '2> "a b.log" bash tests/a.test.sh' \
          '>>log 2>&1 bash tests/a.test.sh' 'FOO=1 2>/dev/null bash tests/a.test.sh'; do
  expect_eq "§REDIR [$rr] runs the suite behind the redirect" "suite" "$(class_of "$rr")"
  expect_eq "§REDIR …and names it" "a.test.sh" "$(targets_of "$rr")"
done
expect_eq "§REDIR …and its run is the command, not the plumbing in front of it" \
  "bash tests/a.test.sh" "$(claim_run_of '2>/dev/null bash tests/a.test.sh')"


section "§LOOP — REQ-6 AC-6.3 (D9): a literal loop or assignment resolves before it refuses"
# THE REFUSAL THAT CHECKED NOTHING (research R3 Q1). The budget arm reads the command text
# before the shell expands it, so `for s in a b; do bash tests/$s.test.sh; done` reached it
# as the one claim `$s.test.sh`, refused as unexpanded — about 100 refusals all-time, 57 of
# them loops over a fully literal word list. A literal word list, or one literal assignment
# separated by `;`, `&&` or a newline, is resolved here into the suites it names. A body
# that reassigns the variable keeps the `$` claim, so the refusal still fires there.
targets_are 'a.test.sh
b.test.sh' 'for s in a b; do bash tests/$s.test.sh; done'
targets_are 'a.test.sh
b.test.sh' 'for s in a b; do bash "tests/$s.test.sh"; done'
targets_are 'a.test.sh
b.test.sh' 'for s in a b; do bash tests/${s}.test.sh; done'
targets_are 'a.test.sh
b.test.sh' 'for s in "a" '"'b'"'; do bash tests/$s.test.sh; done'
targets_are 'a.test.sh
b.test.sh' 'for s in a b
do
  bash tests/$s.test.sh 2>&1 | tee /tmp/$s.log
done'
targets_are 'x-p.test.sh
y-p.test.sh' 'for a in x y; do for b in p; do bash tests/$a-$b.test.sh; done; done'
targets_are 'a.test.sh' 's=a; bash tests/$s.test.sh'
targets_are 'a.test.sh' 's=a && bash tests/$s.test.sh'
targets_are 'a.test.sh' 's=a
bash tests/$s.test.sh'
expect_eq "§LOOP …the resolved claim carries the resolved run" \
  "bash tests/a.test.sh" "$(claim_run_of 's=a; bash tests/$s.test.sh')"
# SCOPED, as the budget arm calls it: each resolved path is this repo's tests/<basename>.
expect_eq "§LOOP scoped to a repo root, each resolved suite is that repo's" "a.test.sh
b.test.sh" "$(targets_of_in "$C8_ROOT" 'for s in a b; do bash tests/$s.test.sh; done')"

# KEPT UNRESOLVED — the same extractor answering `$` beside the resolved rows above.
targets_are '$s.test.sh' 'for s in a b; do s=run; bash tests/$s.test.sh; done'
targets_are '$s.test.sh' 'for s in a b; do read s; bash tests/$s.test.sh; done'
targets_are '$s.test.sh' 'for s in a b; do printf -v s x; bash tests/$s.test.sh; done'
targets_are '$s.test.sh' 'for s in a b; do export s=c; bash tests/$s.test.sh; done'
targets_are '$s.test.sh' 'for s in $(seq 3); do bash tests/$s.test.sh; done'
targets_are '$s.test.sh' 'for s in $set; do bash tests/$s.test.sh; done'
targets_are '$s.test.sh' 'for s in a*; do bash tests/$s.test.sh; done'
targets_are '$s.test.sh' 's=a bash tests/$s.test.sh'
targets_are '$s.test.sh' 's=a; s=b; bash tests/$s.test.sh'
targets_are '$s.test.sh' 's=a | bash tests/$s.test.sh'
targets_are '$s.test.sh' 's=a & bash tests/$s.test.sh'
targets_are '$s.test.sh' 'false || s=a; bash tests/$s.test.sh'
targets_are '$s.test.sh' '(s=a); bash tests/$s.test.sh'
targets_are '$s.test.sh' 'if c; then s=a; fi; bash tests/$s.test.sh'
targets_are '$s.test.sh' 'bash tests/$s.test.sh; s=a'
targets_are '$s.test.sh' 's=$(pick); bash tests/$s.test.sh'
targets_are '$s.test.sh' 'eval x; s=a; bash tests/$s.test.sh'
targets_are '$s.test.sh' 'for s in a; do bash '"'"'tests/$s.test.sh'"'"'; done'
targets_are 'a.test.sh
b.test.sh
$s.test.sh' 'for s in a b; do bash tests/$s.test.sh; done; bash tests/$s.test.sh'
# THE SAME SHAPE WITH THE VARIABLE INSIDE ITS OWN GROUP resolves, beside `(s=a); …` above.
targets_are 'a.test.sh' '(s=a; bash tests/$s.test.sh)'

section "§LOOPLINES — wave-24 T13 (D10, AC-6.3): the loop's own words, as the lines to run"
# THE REFUSAL THAT HAD NOTHING TO PRINT. A `$` claim the classifier will not resolve used to
# be answered with a canned `alpha`/`beta` example. `cmd_suite_loop_lines` is the one reading
# of the loop header that refusal prints: each literal word of the `for` list put into the
# suite path the body runs, one `bash <path>` line each, read by the same awk as the claims —
# never a second parse in the wall.
loop_lines_of() {  # <command> -> cmd_suite_loop_lines' answer
  bash -c '. "$1" || { echo "SOURCE-FAILED"; exit 1; }; cmd_suite_loop_lines "$2"' _ "$LIB" "$1" 2>&1
}
loop_lines_are() {  # <expected, newline-joined> <command>
  expect_eq "loop lines [$2]" "$1" "$(loop_lines_of "$2")"
}
loop_lines_are 'bash tests/a.test.sh
bash tests/b.test.sh' 'for s in a b; do bash "tests/$s.test.sh"; done'
# A command the claims will not expand at all (an `eval`) still has a body that leaves V alone,
# so its header words are what the loop runs.
loop_lines_are 'bash tests/a.test.sh
bash tests/b.test.sh' 'for s in a b; do bash "tests/$s.test.sh"; done; eval :'
# The path is the one the body names, so a `./` spelling and a trailing tee stay the body's own.
loop_lines_are 'bash ./tests/a.test.sh
bash ./tests/b.test.sh' 'for s in a b; do bash ./tests/$s.test.sh 2>&1 | tee log; done'
# Nested literal loops: every pair, in header order.
loop_lines_are 'bash tests/x-p.test.sh
bash tests/y-p.test.sh' 'for a in x y; do for b in p; do bash tests/$a-$b.test.sh; done; done'
# A word repeated in the header is one line.
loop_lines_are 'bash tests/a.test.sh' 'for s in a a; do bash tests/$s.test.sh; done'
# A BODY THAT REASSIGNS THE VARIABLE runs something other than the header's words (wave-24
# T26, walk-head-b surprise 3): `s=c` runs c twice, so printing a and b would hand the reader
# a false fix. Nothing is derived, by any of the forms that assign — beside the rows above on
# the same extractor, and for the nested frame whose OUTER variable is the one reassigned.
# fails-when: a reassigning body still prints the header words.
loop_lines_are '' 'for s in a b; do s=c; bash "tests/$s.test.sh"; done'
loop_lines_are '' 'for s in a b; do read s; bash tests/${s}.test.sh; done'
loop_lines_are '' 'for s in a b; do s=run; bash ./tests/$s.test.sh 2>&1 | tee log; done'
loop_lines_are '' 'for a in x y; do for b in p; do a=z; bash tests/$a-$b.test.sh; done; done'
loop_lines_are '' 'for s in a a; do s=c; bash tests/$s.test.sh; done'
# NOTHING TO PRINT — the same extractor, beside the rows above: a header that is not all literal,
# a `$` with no loop around it, and a suite segment outside the loop.
loop_lines_are '' 'for s in $(seq 3); do bash tests/$s.test.sh; done'
loop_lines_are '' 'for s in a*; do bash tests/$s.test.sh; done'
loop_lines_are '' 's=a bash tests/$s.test.sh'
loop_lines_are '' 'for s in a b; do echo $s; done; bash tests/$s.test.sh'
loop_lines_are '' 'for s in a b; do s=c; echo "tests/$s.test.sh"; done'


section "§VAR — REQ-6 AC-6.4 (D9): a variable holding a whole suite name is a suite run"
# THE BYPASS (research R3 Q1, "guarantee gap"). `X=a.test.sh; bash tests/$X` and
# `for f in tests/a.test.sh; do bash $f; done` read class NONE: the `.test.sh` the classifier
# keys on was inside the variable, so neither the budget nor the farm-out wall saw a suite.
expect_eq "§VAR X=a.test.sh; bash tests/\$X is a suite run" "suite" "$(class_of 'X=a.test.sh; bash tests/$X')"
targets_are 'a.test.sh' 'X=a.test.sh; bash tests/$X'
expect_eq "§VAR …as a FILE claim" "file" "$(claim_kinds_of 'X=a.test.sh; bash tests/$X')"
expect_eq "§VAR a loop over whole suite paths is a suite run" "suite" \
  "$(class_of 'for f in tests/a.test.sh tests/b.test.sh; do bash $f; done')"
targets_are 'a.test.sh
b.test.sh' 'for f in tests/a.test.sh tests/b.test.sh; do bash $f; done'
expect_eq "§VAR …scoped to a repo root, as the budget arm asks" "a.test.sh" \
  "$(targets_of_in "$C8_ROOT" 'X=a.test.sh; bash tests/$X')"
# NEGATIVE CONTROLS on the same extractors: a variable holding something that is not a
# suite stays what it was.
expect_eq "§VAR X=notes.txt; cat \$X is not a suite run" "none" "$(class_of 'X=notes.txt; cat $X')"
expect_eq "§VAR a loop over scripts that are not suites is not a suite run" "none" \
  "$(class_of 'for f in a.sh b.sh; do bash $f; done')"
targets_are '' 'for f in a.sh b.sh; do bash $f; done'


section "§WT — REQ-3 (D16): cmd_write_targets names the paths a command writes"
# THE MEMORY WALL READS THIS (walls.sh `wall_memory_store`, hooks/bash-walls.sh collects). The
# store has to be told apart from its READERS: a wave's own readback names the store and
# redirects (`{ find <store> -newer m; } > record/x.txt`), so "the text mentions the store"
# refuses the audit. What a command WRITES is a property of argv positions and redirect
# targets, read with the same segmentation this file uses for everything else.
#
# HOME IS PINNED to /h for every row, so `~` and `$HOME` expand to a known prefix. The
# optional second argument is the payload cwd that a relative target with no `cd` before it
# resolves against.
wt_of() {  # <command> [<cwd>] [env assignments…] -> the library's write targets, one per line
  local _c="$1" _d="${2-}"; shift; [ $# -gt 0 ] && shift
  printf '%s' "$_c" | env HOME=/h BIONIC_CLAUDE_HOME= CLAUDE_CONFIG_DIR= "$@" bash -c '
    set -uo pipefail
    . "$1" || { echo "SOURCE-FAILED"; exit 1; }
    cmd_write_targets "$(cat)" "$2"' _ "$LIB" "$_d"
}
wt_are() {  # <expected, newline-joined> <command> [<cwd>] [env…]
  expect_eq "write targets [$(printf '%q' "$2")]" "$1" "$(wt_of "$2" "${3-}" "${@:4}")"
}

# --- redirects: every operator that opens a file for writing ---
wt_are '/a/b.md' 'echo hi > /a/b.md'
wt_are '/a/b.md' 'echo hi >> /a/b.md'
wt_are '/a/c' 'echo hi >| /a/c'
wt_are '/a/d' 'cmd &> /a/d'
wt_are '/a/e' 'cmd 2>/a/e'
wt_are '/a/f' '2>/a/f cmd'
wt_are '/a/g' 'echo hi >/a/g'
wt_are '/a/h b' 'echo hi > "/a/h b"'
# A DUPLICATION IS NOT A FILE, and neither is an input redirect or a here-string.
wt_are '/a/i' 'cmd > /a/i 2>&1'
wt_are '' 'cmd 2>&1 >&2 <in.txt'
wt_are '' 'grep x <<< "$v"'
# A HEREDOC BODY IS TEXT, NEVER A COMMAND: its `>` writes nothing. The command that opened it
# still writes its own redirect target.
wt_are '/a/c.md' "$(printf 'cat > /a/c.md <<%sEOF%s\nbody > /x/y\ntouch /x/z\nEOF' "'" "'")"
# QUOTED TEXT IS AN ARGUMENT, so a `>` inside quotes is prose.
wt_are '' "echo '> /a/no'"
wt_are '' 'git commit -m "x > /a/no"'

# --- argv writers ---
wt_are '/a/t1
/a/t2' 'printf x | tee -a /a/t1 /a/t2'
wt_are '/a/f.md' "sed -i '' 's/a/b/' /a/f.md"
wt_are '/a/f.md' "sed -i 's/a/b/' /a/f.md"
wt_are '/a/f.md
/a/g.md' "sed -i.bak -e 's/a/b/' /a/f.md /a/g.md"
wt_are '/a/f.md' "sed --in-place -E 's/a/b/' /a/f.md"
# NEGATIVE beside the positives above on the same extractor: sed without -i writes stdout.
wt_are '' "sed 's/a/b/' /a/f.md"
wt_are '/b/dest' 'cp /a/src /b/dest'
wt_are '/d' 'mv x y z /d/'
wt_are '/d' 'cp -t /d a b'
wt_are '/d' 'mv --target-directory=/d a'
wt_are '/a/x
/a/y' 'touch /a/x /a/y'
wt_are '/a/x' 'touch -r /a/ref /a/x'
wt_are '/a/m' 'mkdir -p /a/m'
wt_are '/a/n' 'mkdir -m 700 /a/n'
wt_are '/a/link' 'ln -s /src /a/link'
# READERS WRITE NOTHING — the AC-3.3 set, each beside the writers above.
wt_are '' 'cat /a/b'
wt_are '' 'ls -la /a'
wt_are '' 'find /s -newer m -type f'
wt_are '' 'rm -f /s/f'
wt_are '' 'tar -cf - /s'
wt_are '/r/x.txt' '{ find /s -newer m; } > /r/x.txt'

# --- one level of `sh -c` / `eval`, and command-taking prefixes ---
wt_are '/a/q' "bash -c 'echo hi > /a/q'"
wt_are '/a/s' 'sudo tee /a/s'
wt_are '/a/v' 'X=1 env Y=2 touch /a/v'

# --- `~`, `$HOME`, `${HOME}` and the store-root variables expand ---
wt_are '/h/.claude/projects/p/memory/a' 'touch ~/.claude/projects/p/memory/a'
wt_are '/h/x' 'echo > "$HOME/x"'
wt_are '/h/y' 'echo > ${HOME}/y'
wt_are '/h' 'mkdir ~'
wt_are '/c/projects/p/memory/f' 'echo > $CLAUDE_CONFIG_DIR/projects/p/memory/f' '' CLAUDE_CONFIG_DIR=/c
wt_are '/b/projects/p/memory/f' 'echo > "${BIONIC_CLAUDE_HOME}/projects/p/memory/f"' '' BIONIC_CLAUDE_HOME=/b
# An unset store variable stays a literal: nothing here invents a value.
wt_are '$CLAUDE_CONFIG_DIR/f' 'echo > $CLAUDE_CONFIG_DIR/f'

# --- relative targets resolve against a preceding cd, then against the payload cwd ---
# THE WAVE-23 SHAPE (A-orch-30): the store's path appears only in the `cd`, the heredoc body
# is prose, and the writes that follow name bare basenames.
wt_are '/s/x.md
/s/MEMORY.md' "$(printf 'cd /s && cat >> x.md <<%sEOF%s\n- line > not a target\nEOF\nsed -i %s%s %ss|a|b|%s MEMORY.md' "'" "'" "'" "'" "'" "'")"
wt_are '/h/.claude/projects/p/memory/a.md' 'cd ~/.claude/projects/p/memory && touch a.md'
wt_are '/s/sub/f' 'cd /s; cd sub && echo > f'
wt_are '/t/f' 'cd /s && echo > ../t/f'
wt_are '/w/out.txt' 'echo > out.txt' /w
wt_are 'out.txt' 'echo > out.txt'
wt_are '/w/x' 'echo > ./x' /w
# A cd INSIDE A SUBSHELL ends with it.
wt_are '/w/out.txt' '(cd /s && ls) && echo > out.txt' /w
wt_are '/s/in.txt' '(cd /s && echo > in.txt)' /w
# `cd` alone is home; `cd -` is a directory the text cannot name, so the payload cwd stands.
wt_are '/h/f' 'cd && touch f' /w
wt_are '/w/f' 'cd /s && cd - && touch f' /w

# --- a double-quoted target is read whole and unescaped in one split (T28) ---
# wt_tok copies a quoted run in one piece and drops its escapes with one split on the
# backslash. Each row answers the same as the character walk it replaced. The last two rows
# hold a newline inside the quote (the unclosed one reaches the reader with its line end), and
# they are the ones a split on the one-character string "\\" got wrong: macOS awk also splits
# such a string on newline. (A newline inside a target reads as `/`, because the path fold
# splits the same way.)
wt_are '/a/b\c' 'echo x > "/a/b\\c"'
wt_are '/a/b"c' 'echo x > "/a/b\"c"'
wt_are '/a/\\' 'echo x > "/a/\\\\"'
wt_are '/a/l1/l2\x' "$(printf 'echo x > "/a/l1\nl2\\\\x"')"
wt_are '/a/x' 'tee "/a/x\'

section "§QRUN — wave-24 T22: a quoted run is found whole, never walked"
# `cmdnorm_qend` finds where a quote closes and the three readers copy the run in one piece
# (segments, argv_tok, cmdnorm_run). Each pair below differs only in whether the quote closes
# before the `;`, so a reader that closes it early or late turns one answer into the other.
case_is none  'echo "a\" ; make ; b"' 'a \" inside double quotes does not close them'
case_is build 'echo "a\\"; make'     'a \\ inside double quotes is one backslash, and the quote closes'
case_is build "echo 'a\\'; make"     'a backslash inside single quotes hides nothing'
case_is none  'echo "a; make'        'a quote that never closes runs to the end'
case_is none  'echo "a\'             'a backslash at the very end of an unclosed quote'
# An unclosed quote in argv[0] or argv[1] is no word at all, to its last character.
case_is none  '"make'                'argv[0] in a quote that never closes is not make'
case_is none  'npm "install'         'argv[1] in a quote that never closes is not install'
case_is build 'echo "\é"; make'      'a backslash before a multibyte character'
case_is build "'make' -j4"           'argv[0] spelled inside quotes is still argv[0]'
case_is install '"npm" install'      'a quoted word joins its unquoted neighbour'
case_is none  '"npm install"'        'a quoted run holding a space is prose'
expect_eq "§QRUN a quoted redirect is an argument, the trailing one comes off" \
  "bash tests/x.test.sh \"a > b\"" "$(norm_of 'bash tests/x.test.sh "a > b" > log')"
expect_eq "§QRUN an escaped quote does not end the run before the redirect" \
  "pytest \"a\\\" > b\"" "$(norm_of 'pytest "a\" > b" 2>&1')"

section "§FX — wave-25 T2 (D5, AC-2.8): cmd_effects says what a command writes and deletes, or that it cannot tell"
# A PERMISSION ANSWER READS THIS (lib/grant.sh, T3), and it may allow only what was read in
# full: any `?` line puts the command outside every root. So the defect this section exists for
# is the one §WT above pins as correct for ITS caller — an unread target OMITTED, the same
# output a pure reader gives. A missed write or delete is a hole; a false unknown is a denial.
#
# THE SHAPE each row asserts: the W and D lines in order, then one `?` when any unknown line
# was printed. The reasons are prose for a person and are not pinned, except that an unknown
# line carries its segment (the decision names it). HOME is pinned to /h, as in §WT.
fx_of() {  # <command> [<cwd>] -> cmd_effects' lines, from $FX_LIB (the shipped library by default)
  local _c="$1" _d="${2-}"
  printf '%s' "$_c" | env HOME=/h BIONIC_CLAUDE_HOME= CLAUDE_CONFIG_DIR= bash -c '
    set -uo pipefail
    . "$1" || { echo "SOURCE-FAILED"; exit 1; }
    cmd_effects "$(cat)" "$2"' _ "${FX_LIB:-$LIB}" "$_d"
}
fx_shape() {  # <command> [<cwd>] -> the W/D lines, then `?` once if anything was unknown
  fx_of "$@" | awk -F'\t' '$1 == "?" { u = 1; next } { print } END { if (u) print "?" }'
}
fx_are() {  # <expected, newline-joined> <command> [<cwd>]
  expect_eq "effects [$(printf '%q' "$2")${3:+ in $3}]" "$1" "$(fx_shape "$2" "${3-}")"
}
T=$'\t'

# --- the matrix row: each of these is unknown, and `rm -f /a/b` is a delete ---
fx_are "D${T}/a/b" 'rm -f /a/b'
fx_are '?' 'rm -f $X'
fx_are '?' 'rm -f /a/*.tmp'
fx_are '?' "python3 -c 'import os; os.remove(\"/a/b\")'"
fx_are '?' "bash -c \"bash -c 'bash -c \\\"rm -f /a/b\\\"'\""
fx_are '?' 'cd /s && cd - && rm -f f' /w
fx_are '?' 'shred /a/b'

# --- deletes ---
fx_are "D${T}/a/b
D${T}/a/c" 'rm -rf -- /a/b /a/c'
fx_are "D${T}/a/d" 'rmdir /a/d'
fx_are "D${T}/a/b/c
D${T}/a/b
D${T}/a" 'rmdir -p /a/b/c'
fx_are "D${T}/a/u" 'unlink /a/u'
fx_are "D${T}/a/x
W${T}/b/y" 'mv /a/x /b/y'
fx_are "D${T}/w/a
D${T}/w/b
W${T}/d" 'mv -t /d a b' /w
# The glob in `-name` is a test find applies, not a target: the root is what -delete reaches.
fx_are "D${T}/s" "find /s -name '*.tmp' -delete"
fx_are "D${T}/w" 'find -delete' /w
fx_are '?' 'find /s -exec rm {} \;'

# --- writes: everything the write-target mode finds ---
fx_are "W${T}/a/out" 'cat x > /a/out' /w
fx_are "W${T}/a/t" 'echo hi | tee /a/t'
fx_are "W${T}/a/f" "sed -i 's/a/b/' /a/f"
fx_are "W${T}/a/x" 'touch /a/x'
fx_are "W${T}/a/m" 'mkdir -p /a/m'
fx_are "W${T}/a/l" 'ln -s /src /a/l'
fx_are "W${T}/b/d" 'cp /a/s /b/d'
fx_are "W${T}/a/o" 'printf x >> /a/o 2>&1'
# A sed script that writes a file of its own (`w`) is a write nobody listed.
fx_are '?' "sed 's/a/b/w /a/o' /a/f"

# --- pure readers print nothing, beside a delete read off the same command ---
fx_are "D${T}/a/c" 'cat /a/b; rm /a/c'
for _r in 'cat /a/b' 'ls -la /a' 'head -5 /a/f' 'tail -n 2 /a/f' 'grep -rn x /a' 'wc -l /a/f' \
          'echo hi' 'printf x' 'test -f /a/f' '[ -f /a/f ]' 'true' 'pwd' 'date' \
          'find /s -type f' 'git status' 'git log --oneline -3' 'git diff HEAD' \
          'git show HEAD:x' 'git -C /r rev-parse HEAD'; do
  fx_are '' "$_r" /w
done

# --- every unknown form the reader names ---
fx_are '?' 'rm -f /a/$X' /w
fx_are '?' 'rm -f `cat /a/list`' /w
fx_are '?' 'rm -f $(cat /a/list)' /w
fx_are '?' 'echo $(rm -f /a/b)' /w
fx_are '?' 'rm /a/x?' /w
fx_are '?' 'rm /a/[ab]' /w
fx_are '?' 'rm /a/{x,y}' /w
fx_are '?' "perl -e 'unlink \"/a/b\"'"
fx_are '?' "node -e 'require(\"fs\").rmSync(\"/a/b\")'"
fx_are '?' "$(printf "python3 - <<'PY'\nimport os\nos.remove('/a/b')\nPY")"
fx_are '?' "$(printf "bash <<'EOF'\nrm -f /a/b\nEOF")"
fx_are '?' 'bash /a/x.sh'
fx_are '?' './x.sh' /w
# An unquoted heredoc tag lets the body run a command substitution; a quoted one does not.
fx_are "W${T}/a/f
?" "$(printf 'cat > /a/f <<EOF\n$(rm -rf /a)\nEOF')"
fx_are "W${T}/a/f" "$(printf "cat > /a/f <<'EOF'\n\$(rm -rf /a) \`x\`\nEOF")"
fx_are '?' 'popd && rm f' /w
fx_are '?' 'cd $X && rm f' /w
fx_are '?' 'cd "$D" && touch f' /w
fx_are "D${T}/s/f" 'cd /s && rm f' /w
fx_are '?' 'find /s | xargs rm' /w
fx_are '?' "eval 'rm -f /a/b'"
fx_are '?' 'source /a/x.sh'
fx_are '?' '. /a/x.sh'
fx_are '?' 'dd if=/a/x of=/a/y'
fx_are '?' 'install -m 644 a /a/b' /w
fx_are '?' "perl -i -pe 's/a/b/' /a/f"
fx_are '?' 'truncate -s 0 /a/f'
fx_are '?' 'tar -xf /a/t.tar' /w
fx_are '?' 'rsync -a /a/ /b/'
fx_are '?' 'curl -o /a/f https://example.invalid/x'
fx_are '?' 'git commit -m x' /w
fx_are '?' 'git clean -fd' /w
fx_are '?' 'git rm x' /w
fx_are '?' 'git checkout -- .' /w
fx_are '?' 'git -c core.pager=x log' /w
fx_are '?' 'git diff --output=/a/p' /w
fx_are '?' 'sudo rm /a/b'
fx_are '?' 'ssh host rm /a/b'
fx_are '?' "$(printf 'echo x > "/a/l1\nl2"')"

# --- one level of `sh -c` is read; wrappers read through ---
fx_are "D${T}/a/b" "bash -c 'rm -f /a/b'"
fx_are "D${T}/a/b" "bash -c \"bash -c 'rm -f /a/b'\""
fx_are "W${T}/a/q" "sh -lc 'touch /a/q'"
fx_are "D${T}/a/v" 'X=1 env Y=2 rm /a/v'
fx_are "D${T}/a/t" 'timeout 5 rm /a/t'
fx_are "D${T}/a/n" 'nohup rm /a/n'

# --- relative targets resolve against a cd, then the cwd; with neither they are unknown ---
fx_are "D${T}/w/out.txt" 'rm -f out.txt' /w
fx_are '?' 'rm -f out.txt'
fx_are '?' 'echo > ./x'
fx_are "D${T}/s/f" 'cd /s && rm f'
fx_are "D${T}/w/x" 'rm ../x' /w/s
fx_are "D${T}/h/x" 'rm ~/x'

# --- a cd counts only where the text proves it ran: a failed cd leaves the shell where it was ---
fx_are '?' 'cd /s; rm f' /w
fx_are "D${T}/s/f
?" 'cd /s && rm f; rm g' /w
fx_are "D${T}/s/f" 'cd /s || exit 1; rm f' /w
fx_are '?' 'cd /s || true; rm f' /w
fx_are "D${T}/w/f" 'cd /s | rm f' /w
fx_are "D${T}/s/f
D${T}/w/g" '(cd /s && rm f); rm g' /w
fx_are "D${T}/s/f
D${T}/w/g" 'cd /s && rm f & rm g' /w
fx_are '?' '! cd /s && rm f' /w
# A loop runs its body again from wherever the cd left it.
fx_are "D${T}/w/f
?" 'for i in 1 2; do rm f && cd sub; done' /w
fx_are '?' 'for d in a b; do cd $d && rm f; done' /w
# A variable the text assigns only after another command succeeded may hold what it held before.
fx_are '?' 'false && X=/a/q; rm $X' /w
fx_are "D${T}/a/q" 'X=/a/q; rm $X' /w
# An assignment to a variable the reader expands moves every path read through it.
fx_are '?' 'HOME=/x; rm ~/f' /w
fx_are '?' "HOME=/x bash -c 'rm ~/f'" /w

# --- text the segmenter cannot place is unknown, never stripped or split silently ---
fx_are '?' "$(printf "cat <<'E F'\nx\nE F\nrm -rf /a\nE")"
fx_are '?' "$(printf 'echo hi # <<X\nrm -rf /a\nX')"
fx_are '?' "$(printf 'echo "a\n<<X"\nrm -rf /a\nX')"
fx_are '?' "$(printf 'echo "a\n<<X b"\nrm -rf /a\nX')"
fx_are '?' "echo \$'it\\'s'; rm /a/b"
# A comment line runs nothing; one holding a quote may hide the line after it.
fx_are "D${T}/a/b" "$(printf '# note\nrm /a/b')"
fx_are '?' "$(printf "# don't\nrm /a/b")"
fx_are '?' "$(printf "echo hi # it's\nrm -rf /a")"
fx_are '?' "echo \"\${x#\"'\"}\"; rm -rf /a"
fx_are '?' "$(printf "bash -c 'cat <<EOF\necho it\"s\nEOF\nrm -rf /a'")"
fx_are '?' "$(printf 'rm /a/b\r')"
# What a listed command runs can be moved by the text: a PATH, a startup file, a library, git's
# environment, or a function of the same name.
fx_are '?' 'PATH=/tmp/x:$PATH; cat /a/b'
fx_are '?' "BASH_ENV=/tmp/e.sh bash -c 'true'"
fx_are '?' 'LD_PRELOAD=/tmp/l.so cat /a/b'
fx_are '?' 'GIT_EXTERNAL_DIFF=/tmp/d git diff' /w
fx_are '?' 'git --exec-path=/tmp/x status' /w
fx_are '?' 'cd() { true; }; cd /a && rm f' /w
fx_are '?' 'cd /s || return; rm f' /w
fx_are '?' 'date 0101000020'
fx_are "D${T}/a/b" 'date -u +%FT%TZ; rm /a/b'

# --- a read prints no line, so a read whose file the text does not name is unknown ---
# (orchestrator addition 2026-10-03.) The reserved table matches literal paths only, so
# `cat ~/.ss?/id_ed25519` would otherwise read as "no effects" and be allowed.
fx_are '?' 'cat ~/.ss?/id_ed25519'
fx_are '?' 'd=.ssh; cat ~/$d/id'
fx_are '' 'cat /a/b'
fx_are "D${T}/a/c" 'cat /a/b; rm /a/c'
fx_are '?' 'ls *.md' /w
fx_are '?' 'cat ~/.ssh/{id_rsa,id_ed25519}'
fx_are '?' 'wc -l < ~/.ss?/id'
fx_are '?' 'git diff --no-index ~/.ss?/a /a/b' /w
fx_are '?' 'grep -rn x /a/*.md' /w
# A grep pattern and an option are not files: they stay unread text.
fx_are '' "grep -rn 'a*b' /a" /w
fx_are '' "grep -e 'x?' --include='*.md' -r /a" /w
fx_are '' 'head -n 5 /a/f' /w

# --- find that follows symlinks reaches past the root it names (orchestrator addition) ---
# Every worktree holds a `.bionic` link into shared state: `find -L <tree> -delete` deletes
# through it while its D line names only the tree.
fx_are '?' 'find -L /a -delete'
fx_are '?' 'find -H /a -name x'
fx_are '?' 'find /a -follow -type f'
fx_are "D${T}/a" 'find /a -delete'
fx_are '?' "find /a* -name x"

# --- the wave's incident: the variable is set inside the inner shell, so its target is unread ---
FX_INC='echo TR; bash -c '"'"'TR=./x.jsonl; touch $TR; rm -f $TR'"'"
fx_are '?' "$FX_INC" /w
expect_contains "§FX the incident's unknown line names the unread rm segment" \
  "${T}rm -f \$TR" "$(fx_of "$FX_INC" /w | grep -F "?${T}")"

# --- the line protocol: rc 0, and one line per effect even when a segment spans lines ---
FX_ML="$(printf "python3 -c 'a = 1\nW\t/x/forged\nb = 2' > /a/o; rm /a/r")"
FX_OUT="$(fx_of "$FX_ML" /w; echo "rc=$?")"
expect_contains "§FX cmd_effects exits 0 with an unknown line" "rc=0" "$FX_OUT"
expect_nonempty "§FX the multi-line command printed lines" "$(printf '%s\n' "$FX_OUT" | grep -v '^rc=')"
expect_eq "§FX every line is W, D or a three-field ?" "" \
  "$(printf '%s\n' "$FX_OUT" | grep -v '^rc=' | awk -F'\t' '!(($1 == "W" || $1 == "D") && NF == 2 && $2 ~ /^\// || $1 == "?" && NF == 3)')"
expect_eq "§FX a body line shaped like an effect never becomes one" "" \
  "$(printf '%s\n' "$FX_OUT" | grep -F '/x/forged' | grep -v '^?')"
expect_eq "§FX …while the write and the delete after the body are read" "W${T}/a/o
D${T}/a/r" "$(printf '%s\n' "$FX_OUT" | grep -E '^(W|D)')"

# --- mutation control: the unknown line taken out is the write-target mode's omission ---
FX_MUT="$SANDBOX/cmd-class.fx-mutant.sh"
anchor "$LIB" 'print "?\t" r "\t" s' 1
grep -vF 'print "?\t" r "\t" s' "$LIB" > "$FX_MUT"
expect_true "§FX mutant: the library without its unknown line still parses" bash -n "$FX_MUT"
expect_eq "§FX mutant: a delete is still read (the mutant runs)" "D${T}/a/b" "$(FX_LIB="$FX_MUT" fx_shape 'rm -f /a/b')"
expect_eq "§FX mutant: the variable target is omitted — the defect" "" "$(FX_LIB="$FX_MUT" fx_shape 'rm -f $X')"
expect_eq "§FX mutant: the incident reads as harmless — the defect" "" "$(FX_LIB="$FX_MUT" fx_shape "$FX_INC" /w)"
expect_eq "§FX shipped: the same incident is unknown" "?" "$(fx_shape "$FX_INC" /w)"

# --- mutation controls for the two orchestrator additions: the check taken out is the defect ---
FX_MUT2="$SANDBOX/cmd-class.fx-mutant-rop.sh"
anchor "$LIB" 'fx_unk("unresolved read operand", t)' 1
grep -vF 'fx_unk("unresolved read operand", t)' "$LIB" > "$FX_MUT2"
expect_true "§FX read-operand mutant parses" bash -n "$FX_MUT2"
expect_eq "§FX read-operand mutant: a delete is still read (the mutant runs)" "D${T}/a/b" "$(FX_LIB="$FX_MUT2" fx_shape 'rm -f /a/b')"
expect_eq "§FX read-operand mutant: the globbed key read is no effect — the defect" "" "$(FX_LIB="$FX_MUT2" fx_shape 'cat ~/.ss?/id_ed25519')"
FX_MUT3="$SANDBOX/cmd-class.fx-mutant-follow.sh"
anchor "$LIB" 'fx_unk("find follows symlinks", t)' 1
grep -vF 'fx_unk("find follows symlinks", t)' "$LIB" > "$FX_MUT3"
expect_true "§FX find-follow mutant parses" bash -n "$FX_MUT3"
expect_eq "§FX find-follow mutant: plain -delete is still a D (the mutant runs)" "D${T}/a" "$(FX_LIB="$FX_MUT3" fx_shape 'find /a -delete')"
expect_eq "§FX find-follow mutant: -L -delete names only the root — the defect" "D${T}/a" "$(FX_LIB="$FX_MUT3" fx_shape 'find -L /a -delete')"

section "§FOLD — wave-25 T12: a command NAME is read the way the machine resolves it"
# On a case-blind filesystem `BASH` runs bash, `TEE` runs tee and `RM` runs rm (`command -v
# TEE` finds /usr/bin/TEE), so a reader that matched the literal name read each of them as an
# unknown word: a suite the farm-out wall never saw, a memory-store write the memory wall never
# saw, a delete the effects reader called unknown. The fold is ONE awk function
# (`cmd_word_fold`, CMD_WORD_FOLD_AWK) applied to the command word and the wrapper words, in
# every mode. Operands, paths, flags and subcommands never fold. Six builtins never fold either:
# `cd`, `pushd`, `popd`, `wait`, `exit`, `return`, whose capitalised spelling is a different
# program (/usr/bin/CD is `builtin cd` in a child shell and moves nothing) or no program. A
# reader that folded them would believe in a directory change or an exit that never happened.

# --- class: each name class, in its capitalised form, beside its lower-case control ---
for _p in 'suite|bash tests/run.sh|BASH tests/run.sh' 'suite|bash tests/cmd-class.test.sh|Bash tests/cmd-class.test.sh' \
          'suite|sudo bash tests/run.sh|SUDO bash tests/run.sh' 'suite|env bash tests/run.sh|ENV bash tests/run.sh' \
          'suite|time bash tests/run.sh|TIME bash tests/run.sh' 'suite|nohup bash tests/run.sh|NOHUP bash tests/run.sh' \
          'suite|timeout 60 bash tests/run.sh|TIMEOUT 60 bash tests/run.sh' 'suite|nice -n 5 bash tests/run.sh|Nice -n 5 bash tests/run.sh' \
          'suite|xargs bash tests/run.sh|XARGS bash tests/run.sh' 'suite|ssh box bash tests/run.sh|SSH box bash tests/run.sh' \
          'suite|command bash tests/run.sh|COMMAND bash tests/run.sh' 'suite|bash -c "bash tests/run.sh"|BASH -c "bash tests/run.sh"' \
          'suite|sh -c "sh tests/a.test.sh"|SH -c "SH tests/a.test.sh"' \
          'suite|pytest|PYTEST' 'suite|jest|Jest' 'suite|npm test|NPM test' 'suite|npx jest|NPX jest' \
          'suite|go test ./...|GO test ./...' 'suite|make test|Make test' 'build|make|MAKE' 'build|cargo build|CARGO build' \
          'install|npm install|NPM install' 'install|pip install x|PIP install x' 'install|uv sync|UV sync' \
          'install|brew install x|BREW install x' 'build|docker build .|DOCKER build .'; do
  IFS='|' read -r _cls _lo _up <<< "$_p"
  case_is "$_cls" "$_lo" "§FOLD control: $_lo is $_cls"
  case_is "$_cls" "$_up" "§FOLD $_up is $_cls, exactly as $_lo"
done
# --- only the WORD folds: an operand, a path, a flag or a subcommand keeps its case ---
case_is suite 'bash tests/run.sh'          '§FOLD control: the runner path in lower case is the suite'
case_is none  'bash TESTS/RUN.SH'          '§FOLD an operand path never folds: TESTS/RUN.SH is not the runner'
case_is none  './tests/X.TEST.SH'          '§FOLD a script path at argv[0] never folds either'
case_is none  'npm TEST'                   '§FOLD a subcommand never folds: npm TEST is not npm test'
case_is none  'bash -n tests/x.test.sh'    '§FOLD control: -n reads the suite and runs nothing'
case_is suite 'bash -N tests/x.test.sh'    '§FOLD a flag never folds: -N is not -n'
# --- a builtin-only word never folds: EVAL, EXEC and SOURCE resolve to nothing ---
case_is suite 'eval "bash tests/run.sh"'   '§FOLD control: eval runs its string'
case_is none  'EVAL "bash tests/run.sh"'   '§FOLD EVAL is not eval: it runs nothing'
case_is suite 'exec bash tests/run.sh'     '§FOLD control: exec runs its command'
case_is none  'EXEC bash tests/run.sh'     '§FOLD EXEC is not exec: it runs nothing'
# --- cd is not folded: /usr/bin/CD moves nothing, so it licenses no bare run.sh ---
case_is suite 'cd tests && bash run.sh'    '§FOLD control: a cd licenses the bare run.sh'
case_is none  'CD tests && bash run.sh'    '§FOLD CD moves nothing, so it licenses nothing'

# --- head: the tier-2 matcher reads the folded word ---
expect_eq "§FOLD head: SUDO NPX comes off and the word folds" 'npx create-thing' "$(head_of _ 'SUDO NPX create-thing')"
expect_eq "§FOLD head: GIT clone reads as git clone"            'git clone https://x/r.git' "$(head_of _ 'GIT clone https://x/r.git')"
expect_eq "§FOLD head: a runner string's word folds too"         'docker run x' "$(head_of _ "BASH -c 'DOCKER run x'")"
expect_eq "§FOLD head: bash <(CAT F) collapses as bash <(cat F)" 'bash tests/run.sh' "$(head_of _ 'bash <(CAT tests/run.sh)')"
expect_eq "§FOLD head: only the word folds, never its operands"  'npx Create-Thing' "$(head_of _ 'NPX Create-Thing')"

# --- targets and claims ---
targets_are 'x.test.sh' 'bash tests/x.test.sh'
targets_are 'x.test.sh' 'BASH tests/x.test.sh'
targets_are 'run.sh'    'SUDO Bash tests/run.sh'
targets_are ''          'bash tests/X.TEST.SH'

# --- backgrounded: NOHUP is a wrapper; WAIT is /usr/bin/WAIT and collects no job ---
bg_is yes 'NOHUP bash tests/run.sh'        '§FOLD NOHUP backgrounds as nohup does'
bg_is no  'bash tests/run.sh & wait'       '§FOLD control: wait collects the job'
bg_is yes 'bash tests/run.sh & WAIT'       '§FOLD WAIT is not wait: the job is still pending'

# --- writes: every writer, and the wrappers in front of one ---
wt_are '/a/f' 'echo x | TEE /a/f'
wt_are '/a/f' 'Tee -a /a/f'
wt_are '/a/y' 'CP /x /a/y'
wt_are '/a/y' 'MV /x /a/y'
wt_are '/a/t' 'TOUCH /a/t'
wt_are '/a/d' 'MKDIR -p /a/d'
wt_are '/a/l' 'LN -s /x /a/l'
wt_are '/a/f' "SED -i '' s/a/b/ /a/f"
wt_are '/a/f' 'SUDO tee /a/f'
wt_are '/a/f' "BASH -c 'TEE /a/f'"
wt_are '/a/f' 'cd /a && TEE f'
wt_are '/A/F' 'TEE /A/F'
wt_are ''     "SED -I '' s/a/b/ /a/f"
wt_are '/x/f' 'cd /x && tee f' /w
wt_are '/w/f' 'CD /x && tee f' /w

# --- effects: deletes, writes and readers; the transparent prefixes fold ---
fx_are "D${T}/a/b" 'RM -rf /a/b'
fx_are "D${T}/a/b" 'Rm /a/b'
fx_are "D${T}/a/d" 'RMDIR /a/d'
fx_are "D${T}/a/u" 'UNLINK /a/u'
fx_are "D${T}/a/b
W${T}/c" 'MV /a/b /c'
fx_are "W${T}/a/f" 'TOUCH /a/f'
fx_are "D${T}/a/b" 'ENV rm /a/b'
fx_are "D${T}/a/b" 'COMMAND rm /a/b'
fx_are "D${T}/a/b" 'NOHUP rm /a/b'
fx_are "D${T}/a/b" 'TIME rm /a/b'
fx_are "D${T}/a/b" 'NICE -n 5 rm /a/b'
fx_are "D${T}/a/b" 'TIMEOUT 5 rm /a/b'
fx_are "D${T}/a/b" "BASH -c 'RM /a/b'"
fx_are "D${T}/a/b" '/bin/RM /a/b'
fx_are '' 'CAT /a/b'
fx_are '' 'GIT status'
fx_are '' 'Ls /a'
fx_are "D${T}/A/B" 'rm -rf /A/B'
fx_are "D${T}/x/f" 'cd /x && rm f' /w
fx_are "D${T}/w/f
?" 'CD /x && rm f' /w
fx_are "D${T}/x/f" 'cd /x || exit; rm f' /w
fx_are '?' 'cd /x || EXIT; rm f' /w

# --- THE PLANTED DEFECT, as a mutant: the one awk fold made the identity ---
FOLD_MUT="$SANDBOX/cmd-class.fold-mutant.sh"
sed 's|^      if (w !~ /\[ABCDEFGHIJKLMNOPQRSTUVWXYZ\]/) return w$|      return w|' "$LIB" > "$FOLD_MUT"
expect_eq "§FOLD mutant: one line changed" "1" "$(diff "$LIB" "$FOLD_MUT" | grep -c '^>')"
expect_true "§FOLD mutant parses" bash -n "$FOLD_MUT"
expect_eq "§FOLD mutant still reads rm -rf /a/b (the mutant runs)" "D${T}/a/b" "$(FX_LIB="$FOLD_MUT" fx_shape 'rm -rf /a/b')"
expect_eq "§FOLD mutant reads RM -rf /a/b as unknown — the defect" '?' "$(FX_LIB="$FOLD_MUT" fx_shape 'RM -rf /a/b')"

finish
