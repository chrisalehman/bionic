#!/bin/bash
# tests/hook-latency.test.sh — THE SUBPROCESS CAP (epic-23 wave-12-fixit-171, T10,
# REQ-10, spec D8 "measure first"; T11 turns this green).
#
# WHAT IT OWNS. Not timing — timing is `tests/bench/hook-latency.sh`'s, and it is
# noisy by nature, which is exactly why it is not gated on. This suite gates on
# something stable instead: how many EXTERNAL commands `hooks/bash-walls.sh` and
# `hooks/stop.sh` fork per invocation, traced with `bash -x` over the same fixed
# payloads the bench uses (an engaged sandbox project, `ls -la` for bash-walls, a
# quiet Stop for stop.sh). A subprocess fork is the dominant, portable, and
# machine-independent cost a shell hook can carry — jq, grep, awk, one more `git`
# call — and unlike wall-clock ms it does not move between runs or machines.
#
# THE COUNT, NOT THE NAME. `^\++ (cmd)( |$)` over the trace, summed across a fixed
# roster of externals (jq grep awk sed cut tr git date stat find sort uniq head
# tail wc python3 basename dirname readlink realpath) — one or more leading `+`
# because `set -x` nests a `+` per function/subshell depth, and every level's own
# fork is real cost.
#
# CAPS: bash-walls.sh <= 12, stop.sh <= 6 (spec D8's post-cut target; T11 lands the
# cut that gets both hooks under these). RED TODAY BY DESIGN — the spike measured
# ~35 for bash-walls and ~10 for stop, both already over cap, so this suite fails
# at the parent commit and until T11 lands. That is the correct RED for a task-kind
# row: it proves the counting mechanism finds the real problem before anyone tries
# to fix it.
#
# THE SELF-CHECK (§3) is not about the cap value at all — it proves the COUNTER
# itself is sensitive to a single added subprocess, independent of whether today's
# baseline is above or below either cap. It copies bash-walls.sh to a scratch file,
# inserts exactly one extra `jq -n 1 >/dev/null` after the shebang (so it always
# executes, on every code path, before any early exit), traces the copy the same
# way, and asserts the mutant's count is the baseline's plus exactly one. A counter
# that could not detect that would pass this suite for the wrong reason forever.
#
# HERMETIC. Same fixture shape as tests/bash-walls.test.sh's `mk_repo` and
# tests/stop.test.sh's `mkfix`: a real git init and a real `.bionic` tree under a
# mktemp sandbox, engaged for this suite's own synthetic session id — no real
# ~/.claude, no real plan, no shared state with any other suite.
#
# Usage: bash tests/hook-latency.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"

BASH_WALLS_HOOK="${BIONIC_BASH_WALLS_UNDER_TEST:-${BIONIC_HOOKS_DIR}/bash-walls.sh}"
STOP_HOOK="${BIONIC_STOP_UNDER_TEST:-${BIONIC_HOOKS_DIR}/stop.sh}"

command -v jq >/dev/null 2>&1 || { echo "hook-latency: jq absent — suite cannot run"; exit 1; }

# NOT VACUOUS: a missing or unparsing hook must stop the suite, not report a
# suspiciously low subprocess count for a hook that never ran at all.
for _h in "$BASH_WALLS_HOOK" "$STOP_HOOK"; do
  [ -f "$_h" ] || { echo "hook-latency: no hook at $_h — suite refuses to run"; exit 1; }
  bash -n "$_h" || { echo "hook-latency: $_h does not parse — suite refuses to run"; exit 1; }
done

SANDBOX="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/hook-latency-test.XXXXXX")" && pwd -P)"
cleanup() { rm -rf "$SANDBOX"; }
trap cleanup EXIT

SID="c0110c7c-a1b2-4c3d-8e9f-0011223344ff"

# ---------- the ENGAGED project fixture (same shape as the bench's) ----------

PROJECT="$SANDBOX/proj"
mkdir -p "$PROJECT/.bionic/tmp" "$PROJECT/.bionic/docs/plans" "$PROJECT/.bionic/docs/record"
git -C "$PROJECT" init -q 2>/dev/null
git -C "$PROJECT" config user.email t@example.com
git -C "$PROJECT" config user.name "T"
printf 'seed\n' > "$PROJECT/README.md"
git -C "$PROJECT" add README.md
git -C "$PROJECT" commit -q -m seed 2>/dev/null
git -C "$PROJECT" checkout -q -b feature/hook-latency 2>/dev/null
: > "$PROJECT/.bionic/tmp/engaged-$SID.state"
printf -- '---\ncanonical_sdlc_version: 14\n---\n\n## SDLC State\n\ncurrent: 4\n\n- Step 4\n' \
  > "$PROJECT/.bionic/docs/plans/wave-01.plan.md"

FAKE_HOME="$SANDBOX/home"
mkdir -p "$FAKE_HOME"
NO_PLUGINS="$SANDBOX/no-plugins"

# ---------- the fixed payloads (same shape as the bench's) ----------

BASH_WALLS_PAYLOAD=$(jq -nc --arg s "$SID" --arg c "$PROJECT" \
  '{session_id:$s, cwd:$c, hook_event_name:"PreToolUse", tool_name:"Bash",
    tool_input:{command:"ls -la"}, tool_use_id:"toolu_hook_latency"}')

TRANSCRIPT="$SANDBOX/transcript.jsonl"
jq -nc '{type:"assistant",message:{model:"claude-opus-5",
          usage:{input_tokens:1000,cache_creation_input_tokens:0,cache_read_input_tokens:0}}}' \
  > "$TRANSCRIPT"

STOP_PAYLOAD=$(jq -nc --arg s "$SID" --arg c "$PROJECT" --arg t "$TRANSCRIPT" \
  '{session_id:$s, transcript_path:$t, cwd:$c, hook_event_name:"Stop",
    stop_hook_active:false, background_tasks:[]}')

# ---------- tracing + counting ----------

EXTERNAL_CMDS="jq grep awk sed cut tr git date stat find sort uniq head tail wc python3 basename dirname readlink realpath"

# trace_hook <hook> <payload> <trace-file-out>
trace_hook() {
  printf '%s' "$2" | env HOME="$FAKE_HOME" CLAUDE_CODE_SESSION_ID="$SID" CLAUDE_PROJECT_DIR="" \
    BIONIC_PLUGINS_DIR="$NO_PLUGINS" bash -x "$1" >/dev/null 2>"$3"
  return 0
}

# count_external <trace-file> — total external-command forks in the trace, summed
# over EXTERNAL_CMDS, on stdout.
count_external() {
  local trace="$1" total=0 cmd c
  for cmd in $EXTERNAL_CMDS; do
    c=$(grep -cE "^\++ ${cmd}( |\$)" "$trace" 2>/dev/null || true)
    total=$((total + ${c:-0}))
  done
  printf '%s' "$total"
}

# histogram <trace-file> — "<cmd>=<count>" per external command that fired at
# least once, one per line, for the record.
histogram() {
  local trace="$1" cmd c
  for cmd in $EXTERNAL_CMDS; do
    c=$(grep -cE "^\++ ${cmd}( |\$)" "$trace" 2>/dev/null || true)
    [ "${c:-0}" -gt 0 ] && printf '%s=%s\n' "$cmd" "${c:-0}"
  done
}

# trace_best <hook> <payload> <out-trace-file> [<n>=5] — writes the HIGHEST-count of
# <n> bash -x traces to <out-trace-file>.
#
# NOT A SINGLE SAMPLE, ON PURPOSE. `bash -x` traces a pipeline's stages from separate
# concurrently-forked subshells, all writing xtrace lines to the SAME stderr fd; measured
# directly (four consecutive traces of the unmodified bash-walls.sh, identical fixture and
# payload): 31, 31, 31, 30 — one run in four silently DROPPED one trace line (a subshell's
# last xtrace write racing its own exit, confirmed by diffing two 31-count traces: same
# lines, different order, nothing missing between two full-count runs; the 30-count run was
# genuinely one line short). The race can only LOSE a line, never invent one, so the maximum
# across a few retraces is the honest count — a single sample can UNDERCOUNT and falsely
# certify a hook UNDER its cap, which is the wrong direction to be wrong in a suite whose
# whole job is catching a hook that forks too much.
trace_best() {
  local hook="$1" payload="$2" out="$3" n="${4:-5}" i best=-1 t c
  for i in $(seq 1 "$n"); do
    t="$SANDBOX/_trace_try_$i.txt"
    trace_hook "$hook" "$payload" "$t"
    c=$(count_external "$t")
    if [ "$c" -gt "$best" ]; then best="$c"; cp "$t" "$out"; fi
  done
  rm -f "$SANDBOX"/_trace_try_*.txt
}

TRACE_WALLS="$SANDBOX/trace-bash-walls.txt"
TRACE_STOP="$SANDBOX/trace-stop.txt"
trace_best "$BASH_WALLS_HOOK" "$BASH_WALLS_PAYLOAD" "$TRACE_WALLS"
trace_best "$STOP_HOOK" "$STOP_PAYLOAD" "$TRACE_STOP"

WALLS_COUNT=$(count_external "$TRACE_WALLS")
STOP_COUNT=$(count_external "$TRACE_STOP")

# ─────────────────────────────────────────────────────────────────────────────
section "1: bash-walls.sh forks at most 12 external commands per Bash call"

echo "hook-latency: bash-walls.sh external-command count = $WALLS_COUNT (cap 12)"
echo "hook-latency: bash-walls.sh histogram:"
histogram "$TRACE_WALLS" | sed 's/^/hook-latency:   /'

expect_true "1a: bash-walls.sh count <= 12" test "$WALLS_COUNT" -le 12

# ─────────────────────────────────────────────────────────────────────────────
section "2: stop.sh forks at most 6 external commands per Stop"

echo "hook-latency: stop.sh external-command count = $STOP_COUNT (cap 6)"
echo "hook-latency: stop.sh histogram:"
histogram "$TRACE_STOP" | sed 's/^/hook-latency:   /'

expect_true "2a: stop.sh count <= 6" test "$STOP_COUNT" -le 6

# ─────────────────────────────────────────────────────────────────────────────
section "3: self-check — the counter is sensitive to one added subprocess"

# A MUTANT COPY, not the real hook: one `jq -n 1 >/dev/null` spliced in right
# after the shebang line, so it runs on EVERY code path (no early exit skips
# line 2) regardless of which fixture is fed to it. This proves the mechanism
# itself would catch a regression that added one call — independent of where
# today's baseline sits relative to either cap.
#
# THE MUTANT NEEDS ITS OWN hooks/../payload SIBLING, not a bare file in $SANDBOX.
# The loader pasted into every hook resolves the library relative to `dirname
# "$0"` (`../payload/scripts/lib`); a mutant copied to a lone file with no
# `payload/` beside it fails that lookup and takes the fail-closed early exit
# instead of running the real verdict functions — measured directly: a bare
# copy traced at 4 external commands against a baseline of 31, not baseline+1.
# A `hooks/` directory next to a symlinked `payload/` (or `scripts/`, the
# installed-plugin layout's sibling name) — real target, not copied — reproduces
# the loader's own resolution exactly, whichever candidate this tree uses.
HOOK_TREE_ROOT="$(cd "$(dirname "$BASH_WALLS_HOOK")/.." && pwd -P)"
mkdir -p "$SANDBOX/hookscopy/hooks"
[ -d "$HOOK_TREE_ROOT/scripts" ] && ln -s "$HOOK_TREE_ROOT/scripts" "$SANDBOX/hookscopy/scripts"
[ -d "$HOOK_TREE_ROOT/payload" ] && ln -s "$HOOK_TREE_ROOT/payload" "$SANDBOX/hookscopy/payload"
MUTANT="$SANDBOX/hookscopy/hooks/bash-walls-mutant.sh"
awk 'NR==1{print; print "jq -n 1 >/dev/null"; next} {print}' "$BASH_WALLS_HOOK" > "$MUTANT"
chmod +x "$MUTANT"
bash -n "$MUTANT" || echo "hook-latency: mutant does not parse — see $MUTANT"

TRACE_MUTANT="$SANDBOX/trace-mutant.txt"
trace_best "$MUTANT" "$BASH_WALLS_PAYLOAD" "$TRACE_MUTANT"
MUTANT_COUNT=$(count_external "$TRACE_MUTANT")

echo "hook-latency: mutant (bash-walls.sh + 1 jq) count = $MUTANT_COUNT; baseline = $WALLS_COUNT"

EXPECT_MUTANT=$((WALLS_COUNT + 1))
expect_eq "3a: one planted jq call raises the count by exactly one" \
  "$EXPECT_MUTANT" "$MUTANT_COUNT"

finish
