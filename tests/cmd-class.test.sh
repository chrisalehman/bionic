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
  # registry and cache when the library is not beside the hook, and a fixture must never
  # load THIS machine's installed bionic.
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

# A suite run inside a construct, behind a prefix, or as a directly executed script: each
# is suite-class, so each is driven through the compound below like the plain form.
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

run_compound "$(mk_bash_payload "$GREPO" 'bash tests/run.sh' "$AGENT_ID" false)"
expect_eq "AC-24 run_in_background false is ALLOWED by the background arm" 0 "$ST"

run_compound "$(mk_bash_payload "$GREPO" 'bash tests/run.sh' "" true)"
expect_eq "AC-24 a MAIN-THREAD payload (no agent_id) leaves the arm silent" 0 "$ST"

# THE TWO THAT ARE SILENT ALL THE WAY DOWN: not suite-class, so neither wall speaks.
# NO REWRITE IN ANY MODE (wave-34 T2; D11, REQ-1 AC-1.3). These payloads are in bypass mode and GREPO's
# row states a budget; from wave-33 T36 the call came back as `export BIONIC_GATE_AGENT=guarded; <the
# command>`. That carry is retired: the gate names the agent by its tree (lib/gate.sh THE PLACE), so the
# call comes back as typed and "silently" means both streams empty, as it did before T36.
expect_silent_as_typed() {  # <label> <command> — both streams empty: no deny, no advisory, no updatedInput
  expect_empty "$1" "$ERR$OUT"
  expect_eq "$1 …no updatedInput, so the harness runs [$2] byte-identical (AC-16's refusals are the positive)" "" \
    "$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.updatedInput.command // empty' 2>/dev/null)"
}
run_compound "$(mk_bash_payload "$GREPO" 'git status --short' "$AGENT_ID" true)"
expect_eq "AC-24 a non-suite command backgrounded is ALLOWED" 0 "$ST"
expect_silent_as_typed "AC-24 …silently" 'git status --short'

run_compound "$(mk_bash_payload "$GREPO" 'git commit -m "make the row green"' "$AGENT_ID" true)"
expect_eq "AC-24 …and B-5's prose case is not a suite either" 0 "$ST"
expect_silent_as_typed "AC-24 …silently, on both streams" 'git commit -m "make the row green"'

# --- AC-16 (R-12/C-2): the B-9 wall refuses the same superset ---
for sc in "${SUPERSET_SUITES[@]}"; do
  run_compound "$(mk_bash_payload "$GREPO" "$sc" "$AGENT_ID" true)"
done
# NEGATIVE CONTROL on the same arm: prose that merely names a suite is not one.
run_compound "$(mk_bash_payload "$GREPO" 'echo "sudo bash tests/run.sh"' "$AGENT_ID" true)"
expect_eq "AC-16 …but prose naming a suite is still ALLOWED" 0 "$ST"
expect_silent_as_typed "AC-16 …in silence, from both walls" 'echo "sudo bash tests/run.sh"'

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
# POSITIVE CONTROL: the identical payload in an ARMED session must carry that reason, so
# the silence above is the partition deciding and not a dud fixture.
run_compound "$(mk_bash_payload "$GREPO" 'bash tests/run.sh' "$AGENT_ID" true)"

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


finish
