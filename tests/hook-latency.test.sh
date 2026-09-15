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
# SECTION 4 IS A SECOND TRACER AND A DIFFERENT QUESTION (epic-23 wave-14, REQ-4,
# AC-4.3). `set -x` writes to stderr, and both hooks call `bionic_context 2>/dev/null`
# — so the tracer above is BLIND to everything the preamble does, and the counts in
# §1/§2 are counts of what remains visible. §4 traces to a PRIVATE FD instead — one the
# hooks' own stderr suppression cannot reach, on bash 3.2 as well as on 5.3 (T20) — which
# sees the whole invocation, and asserts two facts that are about
# SHAPE rather than volume: exactly one `git` fork per hook (the root walk's single
# `rev-parse`, REQ-2), and no plan-directory scan on the bash-walls path, where not one
# of the five walls reads the run verdict. It does not touch §1/§2's caps: those are
# spec D8's ratified numbers rated against the other tracer, and re-pointing them at
# this one would re-rate a cap rather than measure a regression.
#
# SECTIONS 5 AND 6 ARE SHAPE TOO, on the same trace-fd tracer (epic-23 wave-14 T17).
# §5 counts the CLASSIFIER readings by mode — `_cmd_class_awk` carries its mode in the
# awk command line — and drives both directions, because a screen that skipped the head
# reduction for every command would read as a clean pass while the tier-2 nudge went
# silent. §6 adds a THIRD hook to this suite, hooks/canonical-sdlc-governing-skill.sh,
# for one question only: how many times it walks the plans directory. It is a pin on a
# property that already holds, not a cut — see the section for what it refuses.
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

# ─────────────────────────────────────────────────────────────────────────────
section "4: the trace-fd trace — one git call, and no plan scan where nobody reads it"

# A SECOND TRACER, BESIDE THE ONE ABOVE, NOT IN PLACE OF IT (epic-23 wave-14 REQ-4,
# AC-4.3; research R3 §2).
#
# WHY THE `bash -x … 2>trace` TRACER CANNOT ANSWER THIS QUESTION. Both hooks call
# `bionic_context 2>/dev/null` (hooks/bash-walls.sh, hooks/stop.sh), and `set -x`
# writes to stderr — so the whole preamble's trace is discarded with its stderr and
# the ONE opaque line `bionic_context` stands in for every fork inside it. Measured
# on one identical invocation (R3 §2): the stderr trace showed 458 lines and ZERO
# `git` calls; the same run traced to a dedicated fd showed 722 lines and both of
# the `git rev-parse` calls that were really made. An AC-4.3 assertion written on
# the stderr trace would therefore read as PASSING against a hook that still made
# every call it was asked to stop making — the fail-dangerous direction.
#
# WHY SECTIONS 1–3 KEEP THE OLD TRACER ANYWAY. Their caps (12 and 6) are wave-12
# spec D8's ratified numbers, rated against what the stderr trace can see. Switching
# them to this tracer would not measure a regression — it would re-rate the caps,
# which is a decision for the spec and not a side effect of this row. So this
# section counts what it needs on its own trace and leaves those numbers alone. The
# honest trace-fd totals for both hooks are echoed below for the record.
#
# THE PRELUDE runs through BASH_ENV, which bash sources when it starts
# non-interactively to run a script — i.e. exactly once per hook invocation, before
# the hook's first line. The FUNCNAME field is what makes the no-scan assertion
# readable: a trace line raised inside `_run_candidates` carries its name, whatever
# file it was reached from.
#
# WHY NOT BASH_XTRACEFD (epic-23 wave-14 T20). `/bin/bash` on a Mac is 3.2.57 — the
# interpreter every hook's shebang names, and the one `tests/run.sh`'s interpreter pin
# (ADR-001) puts first on PATH for every `bash` a suite types, so it is what runs the
# hooks under the floor. BASH_XTRACEFD arrived in bash 4.1; 3.2 accepts the assignment,
# ignores it, and leaves xtrace on stderr — which `trace_fd_hook` sends to /dev/null. The
# trace therefore came back EMPTY and nine assertions failed honestly under the floor
# while this same suite passed by hand, where a bare `bash` is Homebrew's 5.3. The fd is
# claimed a different way now, one BOTH interpreters honour:
#
#   * `exec 2>&9` points stderr itself at the trace file, so plain `set -x` writes there;
#   * a DEBUG trap re-asserts it, because `bionic_context 2>/dev/null` points fd 2 back
#     at /dev/null for the length of the call. The trap fires before each command inside
#     that call and restores fd 2 to the trace file first, so the preamble traces in full
#     — which is the whole reason this section exists. `set -T` is what carries the trap
#     into functions and subshells; `exec` is a builtin, so the trap costs no fork.
#
# THE TRAP IS TRACED TOO, one `+… exec` line before each command it precedes, so a LINE
# TOTAL on this trace is roughly twice what the BASH_XTRACEFD tracer reported for the same
# invocation (bash-walls: 872 -> 2255) and the two are not comparable as totals. Nothing
# asserted here is a line total: every count in §4-§6 is anchored to a command word, or is
# a zero, or is a non-zero — and `exec` is not a word any of them match.
#
# WHAT THE FD CARRIES BESIDES THE TRACE. The hooks' own stderr, which used to be
# discarded, now lands in the same file. So every count below matches only lines this
# suite's PS4 raised (`$XT`, below) — a hook that printed the word `git` on stderr can
# neither inflate nor deflate a count.
TRACE_PRELUDE="$SANDBOX/xtrace-prelude.sh"
cat > "$TRACE_PRELUDE" <<'PRELUDE'
exec 9>>"$BIONIC_TRACE_OUT"
exec 2>&9
PS4='+|BIONIC|${BASH_SOURCE##*/}:${LINENO}|${FUNCNAME[0]:-MAIN}| '
set -T
trap 'exec 2>&9' DEBUG
set -x
PRELUDE

# trace_fd_hook <hook> <payload> <trace-file-out>
trace_fd_hook() {
  : > "$3"
  printf '%s' "$2" | env HOME="$FAKE_HOME" CLAUDE_CODE_SESSION_ID="$SID" CLAUDE_PROJECT_DIR="" \
    BIONIC_PLUGINS_DIR="$NO_PLUGINS" BIONIC_TRACE_OUT="$3" BASH_ENV="$TRACE_PRELUDE" \
    bash "$1" >/dev/null 2>/dev/null
  return 0
}

# count_lines <trace> <extended regex> -> how many trace lines match, on stdout
count_lines() {
  local c
  c=$(grep -cE "$2" "$1" 2>/dev/null || true)
  printf '%s' "${c:-0}"
}

# THE MARKER ANCHOR (T20). `$XT` opens a line this suite's own PS4 raised, at any nesting
# depth — `set -x` replicates PS4's FIRST character per level, so the `BIONIC` field lands
# after one or more `+`. `$XT_CMD` runs on through the `<file>:<line>` and `<function>`
# fields to the command word itself. Every count in §4-§6 is built from one of the two, so
# a line of hook stderr sharing the fd cannot be mistaken for a trace line.
XT='^\++\|BIONIC\|'
XT_CMD="$XT"'[^|]*\|[^|]*\| '

# NOT VACUOUS: a trace that came back empty (a prelude that failed to source, an fd the
# interpreter under test would not honour) would make every count below zero and certify
# both claims for the wrong reason. Each trace must carry the preamble itself — and
# `bionic_context` is the one place fd 2 is suppressed, so these two rows are also the
# proof that the DEBUG trap defeated the suppression on THIS interpreter.
FD_WALLS="$SANDBOX/tracefd-bash-walls.txt"
FD_STOP="$SANDBOX/tracefd-stop.txt"
trace_fd_hook "$BASH_WALLS_HOOK" "$BASH_WALLS_PAYLOAD" "$FD_WALLS"
trace_fd_hook "$STOP_HOOK" "$STOP_PAYLOAD" "$FD_STOP"

echo "hook-latency: hooks traced under bash $(bash -c 'echo "$BASH_VERSION"' 2>/dev/null) ($(command -v bash))"

expect_true "4-pre-a: the bash-walls trace-fd trace is non-empty" \
  test "$(count_lines "$FD_WALLS" "$XT"'[^|]*\|bionic_context\|')" -gt 0
expect_true "4-pre-b: the stop trace-fd trace is non-empty" \
  test "$(count_lines "$FD_STOP" "$XT"'[^|]*\|bionic_context\|')" -gt 0

# THE COMMAND WORD IS `git`, and `rev-parse` is an ARGUMENT — `git -C <dir> rev-parse`
# puts two words between them, so a `git rev-parse` string match would count zero and
# pass forever. The count is of every `git` fork in the whole invocation, which is
# strictly stronger than AC-4.3's "one `git rev-parse`": the one call that remains is
# the root walk's, and a second git call of any kind fails this row.
WALLS_GIT=$(count_lines "$FD_WALLS" "$XT_CMD"'git( |$)')
STOP_GIT=$(count_lines "$FD_STOP" "$XT_CMD"'git( |$)')
WALLS_REVPARSE=$(count_lines "$FD_WALLS" "$XT_CMD"'git .*rev-parse')
STOP_REVPARSE=$(count_lines "$FD_STOP" "$XT_CMD"'git .*rev-parse')

echo "hook-latency: trace-fd bash-walls.sh git=$WALLS_GIT (rev-parse=$WALLS_REVPARSE) lines=$(wc -l < "$FD_WALLS" | tr -d ' ')"
echo "hook-latency: trace-fd stop.sh       git=$STOP_GIT (rev-parse=$STOP_REVPARSE) lines=$(wc -l < "$FD_STOP" | tr -d ' ')"
# The §1/§2 histogram reads the OTHER tracer's PS4 (`+ cmd …`); this trace carries the
# fielded PS4 the prelude sets, so the counting pattern is its own.
histogram_fd() {  # <trace-file> — "<cmd>=<count>" per external that fired, for the record
  local trace="$1" cmd c
  for cmd in $EXTERNAL_CMDS; do
    c=$(grep -cE "${XT_CMD}${cmd}( |\$)" "$trace" 2>/dev/null || true)
    [ "${c:-0}" -gt 0 ] && printf '%s=%s ' "$cmd" "${c:-0}"
  done
  printf '\n'
}

echo "hook-latency: trace-fd external totals (record only, NOT the §1/§2 caps):"
echo "hook-latency:   bash-walls.sh $(histogram_fd "$FD_WALLS")"
echo "hook-latency:   stop.sh       $(histogram_fd "$FD_STOP")"

expect_eq "4a: bash-walls.sh forks git exactly once, and it is the root walk's rev-parse" \
  "1 1" "$WALLS_GIT $WALLS_REVPARSE"
expect_eq "4b: stop.sh forks git exactly once, and it is the root walk's rev-parse" \
  "1 1" "$STOP_GIT $STOP_REVPARSE"

# THE PLAN SCAN, WHERE NOBODY READS IT. `payload/scripts/lib/walls.sh` holds no
# reference to BIONIC_RUN_WORD or BIONIC_RUN_PLAN (R3 §6) — not one of bash-walls'
# five walls reads the run verdict, and the evidence gate fetches its own plan when
# it needs one. So every `_run_candidates` walk of the plans directory on this path
# is work whose answer is discarded, and its cost grows with every plan the repo
# accumulates. `stop.sh` is NOT asserted here: three of its four verdict functions
# genuinely branch on the verdict, so it opts in and scans on purpose.
WALLS_SCAN=$(count_lines "$FD_WALLS" "$XT"'[^|]*\|_run_candidates\|')
WALLS_SESSION_RUN=$(count_lines "$FD_WALLS" "$XT"'[^|]*\|session_run\|')
STOP_SCAN=$(count_lines "$FD_STOP" "$XT"'[^|]*\|_run_candidates\|')

echo "hook-latency: trace-fd _run_candidates lines — bash-walls=$WALLS_SCAN stop=$STOP_SCAN"

expect_eq "4c: no plan-directory scan in the bash-walls trace" "0" "$WALLS_SCAN"
expect_eq "4d: and no run-verdict computation to reach it" "0" "$WALLS_SESSION_RUN"

# THE DIFFERENTIAL: stop.sh opts in, so the same scan MUST still be there. Without
# this row, a cut that removed the scan from every hook — breaking three stop-side
# verdicts — would read as a clean pass on 4c.
expect_true "4e: stop.sh, which reads the verdict, still scans" \
  test "$STOP_SCAN" -gt 0

# ─────────────────────────────────────────────────────────────────────────────
section "5: the classifier is read once — no second awk for a head nobody can match"

# WHAT THIS SECTION OWNS (epic-23 wave-14 T17, REQ-4; T4 §5 / A-T4.2). The farm-out
# wall asks the classifier three questions — the whole command's class, each `&&`
# segment's class, and the reduced head tier 2 matches on — and each one used to
# arrive through its own command substitution. On the fixed `ls -la` payload that was
# TWO `awk` execs, of which exactly one, the class reading, could change the answer:
# `classify_tier2` matches only `^git`, `^docker` and `^(npx|uvx)`, and `ls -la`
# begins with none of them at any spelling.
#
# THE COUNT IS BY MODE, which is what makes it readable rather than arithmetic:
# `_cmd_class_awk` puts its mode in the awk command line (`awk -v mode=head`), so the
# trace says which reading forked, not merely how many did.
#
# AND IT IS ASSERTED IN BOTH DIRECTIONS. A screen that skipped the head reduction
# for every command would read as a clean pass here while the tier-2 nudge went
# silent — the fail-dangerous direction, and the one a fork count alone cannot see.
# So 5c drives a command that DOES reach tier 2 and asserts both that the reduction
# was computed and that the wall still spoke.

count_mode() {  # <trace> <mode> -> classifier awk forks in that mode
  count_lines "$1" "${XT_CMD}awk -v mode=$2( |\$)"
}

WALLS_HEAD_FORKS=$(count_mode "$FD_WALLS" head)
WALLS_LINES_FORKS=$(count_mode "$FD_WALLS" lines)
WALLS_CHAIN_AWK=$(count_lines "$FD_WALLS" "$XT"'.*gsub\(/&&/')

echo "hook-latency: classifier forks on 'ls -la' — mode=head=$WALLS_HEAD_FORKS mode=lines=$WALLS_LINES_FORKS chain-split-awk=$WALLS_CHAIN_AWK"

expect_eq "5a: no head reduction is computed for a command tier 2 cannot match" \
  "0" "$WALLS_HEAD_FORKS"
expect_eq "5b: the class reading is still made, exactly once" \
  "1" "$WALLS_LINES_FORKS"

# THE OTHER DIRECTION. `sudo git clone …` is class=none at tier 1 (git is in none of
# `cmd_class`'s arms), so it reaches tier 2 — and only reaches it through the head
# reduction, because `sudo ` sits in front of the word the matcher anchors on.
TIER2_PAYLOAD=$(jq -nc --arg s "$SID" --arg c "$PROJECT" \
  '{session_id:$s, cwd:$c, hook_event_name:"PreToolUse", tool_name:"Bash",
    tool_input:{command:"sudo git clone https://example.invalid/r.git"}, tool_use_id:"toolu_t17_tier2"}')
# THE UNTRACED RUN GOES FIRST, and the order is load-bearing: `nudge_once` speaks ONCE
# per (session, class) and suppresses every repeat, so a second invocation of the same
# payload under the same session id is silent by design. The trace that follows is
# suppressed instead — which costs it nothing, because every fork this section counts is
# made before the suppression check.
TIER2_OUT=$(printf '%s' "$TIER2_PAYLOAD" | env HOME="$FAKE_HOME" CLAUDE_CODE_SESSION_ID="$SID" \
  CLAUDE_PROJECT_DIR="" BIONIC_PLUGINS_DIR="$NO_PLUGINS" bash "$BASH_WALLS_HOOK" 2>/dev/null)
FD_TIER2="$SANDBOX/tracefd-tier2.txt"
trace_fd_hook "$BASH_WALLS_HOOK" "$TIER2_PAYLOAD" "$FD_TIER2"

expect_eq "5c: a command that CAN reach tier 2 still gets its head reduction" \
  "1" "$(count_mode "$FD_TIER2" head)"
expect_true "5c2: …and the wall still speaks for it — the screen is not a silence" \
  test -n "$TIER2_OUT"

# THE CHAIN SPLIT IS SHELL NOW, not an `awk` plus a `grep` plus a `sed` per segment.
# Driven, not merely counted: the same chain must still raise the chain nudge.
CHAIN_PAYLOAD=$(jq -nc --arg s "$SID" --arg c "$PROJECT" \
  '{session_id:$s, cwd:$c, hook_event_name:"PreToolUse", tool_name:"Bash",
    tool_input:{command:"cd a && ls -l && npx cowsay hi"}, tool_use_id:"toolu_t17_chain"}')
CHAIN_OUT=$(printf '%s' "$CHAIN_PAYLOAD" | env HOME="$FAKE_HOME" CLAUDE_CODE_SESSION_ID="$SID" \
  CLAUDE_PROJECT_DIR="" BIONIC_PLUGINS_DIR="$NO_PLUGINS" bash "$BASH_WALLS_HOOK" 2>/dev/null)
FD_CHAIN="$SANDBOX/tracefd-chain.txt"
trace_fd_hook "$BASH_WALLS_HOOK" "$CHAIN_PAYLOAD" "$FD_CHAIN"

echo "hook-latency: chain payload — chain-split-awk=$(count_lines "$FD_CHAIN" "$XT"'.*gsub\(/&&/') sed=$(count_lines "$FD_CHAIN" "$XT_CMD"'sed( |$)')"

expect_eq "5d: the && split forks no awk of its own" \
  "0" "$(count_lines "$FD_CHAIN" "$XT"'.*gsub\(/&&/')"
expect_true "5d2: …and the chain still raises its nudge" \
  test -n "$CHAIN_OUT"

# ─────────────────────────────────────────────────────────────────────────────
section "6: the governing-skill hook walks the plans directory exactly once"

# WHY THIS PIN EXISTS AND WHAT IT REFUSES (epic-23 wave-14 T17). T4 left
# hooks/canonical-sdlc-governing-skill.sh:431 computing its own `session_run`, and the
# obvious-looking follow-up is to set `BIONIC_CONTEXT_WANT_RUN=1` on this hook the way
# hooks/stop.sh, hooks/dispatch-preflight.sh and hooks/session-start.sh do, then read
# the preamble's verdict at :431. MEASURED, that is strictly worse in both halves:
#
#   * IT DOUBLES THE SCAN, it does not remove one. The hook makes ONE walk today. With
#     the flag set and :431 left alone it makes two — 15 `_run_candidates` trace lines
#     became 30, one `find` fork became two, on this fixture.
#   * AND THE TWO VERDICTS ARE NOT THE SAME VERDICT. `bionic_context` resolves against
#     `BIONIC_ROOT`, which is the SESSION's cwd; :431 resolves against
#     `PROJECT_ROOT_FROM_PATH`, which is the ARTIFACT's own root. The hook's header says
#     why in as many words: "a hook that scoped itself by the session's cwd and enforced
#     against the artifact's root would go quiet exactly where it was added to bind."
#     tests/canonical-sdlc-governing-skill.test.sh drives that difference; this row
#     catches the cheaper half, the second walk, wherever it comes from.
GOVERNING_SKILL_HOOK="${BIONIC_GOVERNING_SKILL_UNDER_TEST:-${BIONIC_HOOKS_DIR}/canonical-sdlc-governing-skill.sh}"
[ -f "$GOVERNING_SKILL_HOOK" ] || { echo "hook-latency: no hook at $GOVERNING_SKILL_HOOK — suite refuses to run"; exit 1; }

GS_PAYLOAD=$(jq -nc --arg s "$SID" --arg c "$PROJECT" \
  --arg f "$PROJECT/.bionic/docs/plans/wave-01.plan.md" \
  '{session_id:$s, cwd:$c, hook_event_name:"PreToolUse", tool_name:"Write",
    tool_input:{file_path:$f, content:"---\ngoverning-skill: superpowers:writing-plans\n---\n"},
    tool_use_id:"toolu_t17_gs"}')
FD_GS="$SANDBOX/tracefd-governing-skill.txt"
trace_fd_hook "$GOVERNING_SKILL_HOOK" "$GS_PAYLOAD" "$FD_GS"

GS_WALKS=$(count_lines "$FD_GS" "$XT"'[^|]*\|_run_candidates\| find')
echo "hook-latency: trace-fd governing-skill plan walks=$GS_WALKS lines=$(wc -l < "$FD_GS" | tr -d ' ')"

# NOT VACUOUS: a trace that never reached the verdict at all would report zero walks
# and certify the row for the wrong reason.
expect_true "6-pre: the governing-skill trace reached its run verdict" \
  test "$(count_lines "$FD_GS" "$XT"'[^|]*\|session_run\|')" -gt 0
expect_eq "6a: exactly one plan-directory walk on the governing-skill path" \
  "1" "$GS_WALKS"

# ─────────────────────────────────────────────────────────────────────────────
section "7: BENCH_EXTRA_CANDIDATES writes plan-shaped candidates into the sandbox fixture"

# THIS PIN OWNS THE BENCH'S OWN FIXTURE KNOB (epic-23 wave-14 T19, REQ-4). The
# repo-scale reading T4 and T17 each had to reproduce by hand with a scratchpad copy
# of tests/bench/hook-latency.sh is now first-class: the shipped script honours
# `BENCH_EXTRA_CANDIDATES=<n>` and writes n extra plan-shaped candidates into its own
# sandbox fixture alongside the one it always wrote. This pin drives the bench
# BINARY, not a hook — it is not part of the §1-6 hook-tracing suite above.
#
# WHY `--candidates-only`. The bench's job is ten-times-two hook invocations; this
# pin's job is the FIXTURE the bench builds before it ever calls a hook. Timing that
# to check a file count would make an O(1) question cost the suite real seconds for
# nothing it asserts on. `--candidates-only` builds the fixture, honours the env
# knob, prints "hook-latency: candidates=<n>" and "hook-latency: sandbox=<path>",
# and exits before running either hook — this pin's own minimal-run switch, added
# alongside the knob it exists to test. It also skips the sandbox's own cleanup trap
# so this section can inspect the files before deleting them itself.
BENCH_SCRIPT="$(dirname "$0")/bench/hook-latency.sh"
[ -f "$BENCH_SCRIPT" ] || { echo "hook-latency: no bench at $BENCH_SCRIPT — suite refuses to run"; exit 1; }

# n=2 -> candidates=3, and three plan-shaped files actually sitting in the sandbox's
# plans/ directory, each carrying the flush-left `## SDLC State` heading
# `_run_candidates` (payload/scripts/lib/run.sh) filters on — the same property that
# makes them real candidates on the hooks' own scan, not merely three more files.
BENCH_OUT_2=$(BENCH_EXTRA_CANDIDATES=2 bash "$BENCH_SCRIPT" --candidates-only)
BENCH_CANDIDATES_2=$(printf '%s\n' "$BENCH_OUT_2" | sed -n 's/^hook-latency: candidates=\([0-9]*\)$/\1/p')
BENCH_SANDBOX_2=$(printf '%s\n' "$BENCH_OUT_2" | sed -n 's/^hook-latency: sandbox=//p')

expect_eq "7a: BENCH_EXTRA_CANDIDATES=2 reports candidates=3" "3" "$BENCH_CANDIDATES_2"

BENCH_PLAN_FILES_2=$(find "$BENCH_SANDBOX_2/proj/.bionic/docs/plans" -maxdepth 2 -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
expect_eq "7b: the sandbox holds three plan-shaped files" "3" "$BENCH_PLAN_FILES_2"

BENCH_SDLC_FILES_2=$(grep -lE '^## SDLC State' "$BENCH_SANDBOX_2/proj/.bionic/docs/plans"/*.md 2>/dev/null | wc -l | tr -d ' ')
expect_eq "7c: all three carry a flush-left '## SDLC State' heading, the scan's own filter" \
  "3" "$BENCH_SDLC_FILES_2"

rm -rf "$BENCH_SANDBOX_2"

# unset -> candidates=1, the shipped default's shape, unchanged.
BENCH_OUT_0=$(bash "$BENCH_SCRIPT" --candidates-only)
BENCH_CANDIDATES_0=$(printf '%s\n' "$BENCH_OUT_0" | sed -n 's/^hook-latency: candidates=\([0-9]*\)$/\1/p')
BENCH_SANDBOX_0=$(printf '%s\n' "$BENCH_OUT_0" | sed -n 's/^hook-latency: sandbox=//p')

expect_eq "7d: BENCH_EXTRA_CANDIDATES unset reports candidates=1" "1" "$BENCH_CANDIDATES_0"

rm -rf "$BENCH_SANDBOX_0"

# ─────────────────────────────────────────────────────────────────────────────
section "8: the bench names the interpreter it forks the hooks with"

# THIS PIN OWNS THE FORK-SITE FIX (epic-23 wave-14 T30, REQ-4; A-orch-47). The bench
# used to time `subprocess.run(["bash", hook], …)` — a PATH-resolved `bash`, which on
# this machine is Homebrew 5.3 — while the CLI invokes every hook BY PATH and lets the
# kernel honour its own `#!/bin/bash` shebang (the floor's interpreter, 3.2.57). The
# bench was therefore timing a production nobody runs, and 5.3's readings are the
# noisier of the two (A-orch-47: five medians spanning 6.6 ms under 5.3 vs 0.2 ms
# under 3.2). §8 does not re-time anything — timing is `--candidates-only`'s job to
# stay cheap here too — it asserts the bench SAYS which interpreter it is about to
# fork, and that the name is the hook's own shebang binary, not whatever `bash` PATH
# would hand it.
EXPECTED_INTERP=$(sed -n '1s/^#!//p' "$BASH_WALLS_HOOK" | awk '{print $1}')
[ -n "$EXPECTED_INTERP" ] || { echo "hook-latency: could not parse a shebang from $BASH_WALLS_HOOK — suite refuses to run"; exit 1; }

BENCH_OUT_8=$(bash "$BENCH_SCRIPT" --candidates-only)
BENCH_SANDBOX_8=$(printf '%s\n' "$BENCH_OUT_8" | sed -n 's/^hook-latency: sandbox=//p')
INTERP_LINE=$(printf '%s\n' "$BENCH_OUT_8" | grep '^hook-latency: interpreter=')

echo "hook-latency: expected interpreter (bash-walls.sh shebang) = $EXPECTED_INTERP"
echo "hook-latency: bench interpreter line = $INTERP_LINE"

# NOT VACUOUS: an empty line would make 8b's grep -F vacuously fail rather than pass,
# but 8a pins the presence separately so a reader sees which half broke.
expect_true "8a: the bench prints an interpreter header line" \
  test -n "$INTERP_LINE"
expect_true "8b: the header names the hook's own shebang binary, not PATH's bash" \
  test -n "$(printf '%s' "$INTERP_LINE" | grep -F "interpreter=$EXPECTED_INTERP ")"

rm -rf "$BENCH_SANDBOX_8"

finish
