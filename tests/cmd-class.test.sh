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
# FIXTURE FIDELITY (declared, per .claude memory fixtures-can-pin-away-the-test):
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

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
# THE TWO SPELLINGS OF ONE DIRECTORY. payload/hooks is a symlink to <repo>/hooks, so a hook
# is reached BOTH as <repo>/payload/hooks/x.sh (what ${CLAUDE_PLUGIN_ROOT} renders) and as
# <repo>/hooks/x.sh (what tests/lib/resolve-roots.sh renders). `$0` is textual, so
# "$(dirname "$0")/../scripts/lib" resolves only under the first. Both are driven below.
PAYLOAD_HOOKS="$REPO_ROOT/payload/hooks"
PLAIN_HOOKS="${BIONIC_HOOKS_DIR}"
LIB="$REPO_ROOT/payload/scripts/lib/cmd-class.sh"
FARM_OUT="$PAYLOAD_HOOKS/farm-out-reminder.sh"
BG_GUARD="$PAYLOAD_HOOKS/background-suite-guard.sh"
CTX_GUARD="$PAYLOAD_HOOKS/agent-context-guard.sh"

SANDBOX="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/cmd-class-test.XXXXXX")" && pwd -P)"
cleanup() { rm -rf "$SANDBOX"; }
trap cleanup EXIT

PASS=0
FAIL=0
TOTAL=0
ok() { TOTAL=$((TOTAL + 1)); PASS=$((PASS + 1)); echo "PASS: $1"; }
no() { TOTAL=$((TOTAL + 1)); FAIL=$((FAIL + 1)); echo "FAIL: $1"; [ -n "${2:-}" ] && echo "      $2"; }
expect_eq()       { if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "expected [$2], got [$3]"; fi; }
expect_contains() { case "$3" in *"$2"*) ok "$1" ;; *) no "$1" "expected to contain [$2], got: $3" ;; esac; }
expect_empty()    { if [ -z "$2" ]; then ok "$1"; else no "$1" "expected no output, got: $2"; fi; }

SID="7b2ae913-0c4f-4d21-9a55-13e0c7ab4d10"
AGENT_ID="as5class-91ab3cd7e5f20114"

FAKE_HOME="$SANDBOX/home"
mkdir -p "$FAKE_HOME/.claude/projects/-sandbox"
: > "$FAKE_HOME/.claude/projects/-sandbox/$SID.jsonl"

# ============================================================
echo "=== C0 — the library and both hooks exist and parse ==="
# ============================================================
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

# ============================================================
echo "=== C1 — the library reads argv positions, never prose ==="
# ============================================================
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

# ============================================================
echo "=== C2/C3 — farm-out-reminder through the library (AC-15, AC-16) ==="
# ============================================================
FARM_REPO="$SANDBOX/farm/repo"
mkdir -p "$FARM_REPO/.bionic/tmp"

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
  OUT=$(printf '%s' "$payload" | env HOME="$FAKE_HOME" CLAUDE_CONFIG_DIR="$FAKE_HOME/.claude" \
          CLAUDE_PROJECT_DIR= bash "$@" 2>"$SANDBOX/.err")
  ST=$?
  ERR=$(cat "$SANDBOX/.err")
  return 0
}

farm_decision() {  # <command> -> "" when silent, else the deny/nudge class
  run_hook "$(mk_bash_payload "$FARM_REPO" "$1")" "$FARM_OUT"
  printf '%s' "$OUT"
}

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
expect_empty "AC-15 …silent on unquoted prose carrying `make <word>`" \
  "$(farm_decision 'echo make sure the row is green')"
expect_empty "AC-15 …silent on unquoted prose carrying `npm install`" \
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

# --- behaviour the library must not have changed ---
expect_empty "the sanctioned override still silences the wall" \
  "$(farm_decision 'FARM_OUT_ALLOW=1 bash tests/run.sh')"
expect_empty "…including as an env prefix mid-chain" \
  "$(farm_decision 'cd x && FARM_OUT_ALLOW=1 bash tests/run.sh')"
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

# --- advisory mode still downgrades a deny to a nudge ---
printf 'farm-out-mode: advisory\n' > "$FARM_REPO/.bionic/config.yaml"
D=$(farm_decision 'bash tests/run.sh')
expect_contains "advisory mode downgrades the suite deny to a nudge" 'additionalContext' "$D"
rm -f "$FARM_REPO/.bionic/config.yaml"

# ============================================================
echo "=== C4 — background-suite-guard behind agent-context-guard (AC-23, AC-24) ==="
# ============================================================
make_repo() {  # <name> -> an armed repo
  local repo="$SANDBOX/$1/repo"
  mkdir -p "$repo/.bionic/tmp"
  git -C "$repo" init -q 2>/dev/null
  git -C "$repo" config user.email t@example.com
  git -C "$repo" config user.name "T"
  echo seed > "$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit -qm seed 2>/dev/null
  printf '# bionic session roster — schema roster-state/v1 — machine-local, safe to delete\n' \
    > "$repo/.bionic/tmp/roster-$SID.state"
  chmod 600 "$repo/.bionic/tmp/roster-$SID.state"
  printf '%s' "$repo"
}
GREPO=$(make_repo guarded)

run_guarded() {  # <payload> — through agent-context-guard, as hooks.json registers it
  run_hook "$1" "$CTX_GUARD" "$BG_GUARD"
}

# --- AC-23: agent context + armed + run_in_background true + suite-class -> REFUSED
run_guarded "$(mk_bash_payload "$GREPO" 'bash tests/run.sh' "$AGENT_ID" true)"
expect_eq "AC-23 a backgrounded suite in an agent context of an armed session is REFUSED" 2 "$ST"
expect_contains "AC-23 …and the refusal names the foreground tee form" "2>&1 | tee" "$ERR"
expect_contains "AC-23 …quoting the command it refused" "bash tests/run.sh" "$ERR"

# --- AC-24: the three cells that must stay silent ---
run_guarded "$(mk_bash_payload "$GREPO" 'bash tests/run.sh' "$AGENT_ID" omit)"
expect_eq "AC-24 the same command with no run_in_background is ALLOWED" 0 "$ST"
expect_empty "AC-24 …silently" "$ERR$OUT"

run_guarded "$(mk_bash_payload "$GREPO" 'bash tests/run.sh' "$AGENT_ID" false)"
expect_eq "AC-24 run_in_background false is ALLOWED" 0 "$ST"
expect_empty "AC-24 …silently" "$ERR$OUT"

run_guarded "$(mk_bash_payload "$GREPO" 'bash tests/run.sh' "" true)"
expect_eq "AC-24 a MAIN-THREAD payload (no agent_id) leaves the arm silent" 0 "$ST"
expect_empty "AC-24 …silently" "$ERR$OUT"

run_guarded "$(mk_bash_payload "$GREPO" 'git status --short' "$AGENT_ID" true)"
expect_eq "AC-24 a non-suite command backgrounded is ALLOWED" 0 "$ST"
expect_empty "AC-24 …silently" "$ERR$OUT"

run_guarded "$(mk_bash_payload "$GREPO" 'git commit -m "make the row green"' "$AGENT_ID" true)"
expect_eq "AC-24 …and B-5's prose case is not a suite either" 0 "$ST"

# --- the guard's own partition still holds: an UNARMED session is silent ---
UREPO=$(make_repo unarmed)
rm -f "$UREPO/.bionic/tmp/roster-$SID.state"
run_guarded "$(mk_bash_payload "$UREPO" 'bash tests/run.sh' "$AGENT_ID" true)"
expect_eq "an unarmed session leaves the arm silent even for a backgrounded suite" 0 "$ST"
# POSITIVE CONTROL: the same payload straight into the wall must refuse, so the silence
# above is the guard's decision and not a dud fixture.
run_hook "$(mk_bash_payload "$UREPO" 'bash tests/run.sh' "$AGENT_ID" true)" "$BG_GUARD"
expect_eq "…positive control: that same payload refuses when driven straight into the wall" 2 "$ST"

# ============================================================
echo "=== C5 — FAIL-CLOSED sourcing: no library, no pass (AC-12 shape, D1) ==="
# ============================================================
# The library is moved aside for the length of this section and restored by the trap on
# any exit path. Both hooks must REFUSE the suite-class case rather than allow it.
LIB_HIDDEN="$SANDBOX/cmd-class.sh.hidden"
restore_lib() { [ -f "$LIB_HIDDEN" ] && mv "$LIB_HIDDEN" "$LIB"; rm -rf "$SANDBOX"; }
trap restore_lib EXIT
mv "$LIB" "$LIB_HIDDEN"

D=$(farm_decision 'bash tests/run.sh')
expect_contains "C5 farm-out DENIES when its classifier cannot load" '"deny"' "$D"
expect_contains "C5 …naming the path it could not load" "cmd-class.sh" "$D"

run_guarded "$(mk_bash_payload "$GREPO" 'bash tests/run.sh' "$AGENT_ID" true)"
expect_eq "C5 background-suite-guard REFUSES when its classifier cannot load" 2 "$ST"
expect_contains "C5 …naming the path it could not load" "cmd-class.sh" "$ERR"

mv "$LIB_HIDDEN" "$LIB"
trap cleanup EXIT
# The restore is the precondition of everything after this line, so prove it.
expect_eq "C5 the library is back on disk" "suite" "$(class_of 'bash tests/run.sh')"

# ============================================================
echo "=== C6 — every source in payload/hooks/*.sh resolves inside payload/ ==="
# ============================================================
# A sourced library the installer misses is a silently inert wall (agent-context-guard.sh
# :106-108). The hooks are reachable under two spellings of one directory (see the header),
# so each literal is expanded under BOTH and the pin is: at least one expansion exists, and
# every expansion that exists lies under <repo>/payload/.
# Two literal shapes reach a sibling file from a hook: "$(dirname "$0")/<rel>.sh" (the
# library source) and "$(cd "$(dirname "$0")" … && pwd)/<name>.sh" (the sweeper handoff
# every stop hook uses). Both are collected.
SRC_LITERALS=$( { /usr/bin/grep -hoE '\$\(dirname "\$0"\)/[^"]*\.sh' "$PAYLOAD_HOOKS"/*.sh \
                    | sed 's|^\$(dirname "\$0")||'
                  /usr/bin/grep -hoE '&& pwd\)/[^"]*\.sh' "$PAYLOAD_HOOKS"/*.sh \
                    | sed 's|^&& pwd)||'
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
# ANTI-VACUITY: the extractor must actually see both shapes it claims to cover.
expect_contains "…and the extractor sees the cmd-class library (shape A)" "cmd-class.sh" "$SRC_LITERALS"
expect_contains "…and the sweeper handoff (shape B)" "session-sweeper.sh" "$SRC_LITERALS"

# ============================================================
echo
echo "=== cmd-class: $PASS/$TOTAL passed ==="
[ "$FAIL" -eq 0 ] || echo "FAILURES: $FAIL"
[ "$FAIL" -eq 0 ]
