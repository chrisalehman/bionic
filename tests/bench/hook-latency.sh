#!/bin/bash
# tests/bench/hook-latency.sh — THE INSTRUMENT (epic-23 wave-12-fixit-171, T10, REQ-10,
# spec D8 "measure first"). Runs hooks/bash-walls.sh and hooks/stop.sh, ten times each,
# against fixed payloads in an ENGAGED sandbox session, and prints one line per hook:
#
#     <hook> median=<ms> min=<ms> max=<ms>
#
# NOT PART OF THE GATE. This lives under tests/bench/, which tests/run.sh's
# `tests/*.test.sh` glob never reaches (bash globbing does not cross the `/`), so it
# never runs unattended and never blocks a commit. Timing is inherently noisy — that
# is the whole reason it is kept off the floor and run by hand, captured to
# record/<wave>/bench-*.txt instead of asserted on.
#
# WHY PYTHON3 FOR TIMING. macOS ships no `date +%s%N` (no nanosecond resolution), and
# `time` built into bash reports to a tty, not a variable. `time.time()` around
# `subprocess.run` is a wall-clock measurement of exactly what a hook invocation
# costs the harness — process spawn, `set -x`-free execution, everything.
#
# THE FIXTURE MIRRORS THE HOOKS' OWN SUITES, deliberately: a real git repo, a real
# `.bionic` tree with an open plan and the engagement marker
# (tests/bash-walls.test.sh `mk_repo`, tests/stop.test.sh `mkfix`) rather than a stub —
# because a hook that fails closed before doing any work would time its own early
# exit, not its ordinary cost. Neither fixture arms a roster row or a stale Patrol
# stamp, so both hooks run all of their verdict functions to completion without
# blocking (stop.test.sh §"four quiet verdicts", adapted to stay ENGAGED rather than
# bystander — a bystander session would time the engagement short-circuit instead of
# the real work).
#
# --hooks-dir DIR (or --hooks-dir=DIR): point the bench at a different hooks tree —
# for T11, its own worktree's `hooks/` — instead of this repo's. Its libraries are
# found the normal loader way, `<hooks-dir>/../payload/scripts/lib`, so the override
# only makes sense pointed at a full checkout, not a bare hooks/ directory.
#
# BENCH_EXTRA_CANDIDATES=<n> (env, default 0): after building the one-plan fixture,
# write <n> more plan-shaped files into the same sandbox plans/ directory — same
# shape as the shipped fixture (front matter + a flush-left `## SDLC State` heading),
# so `_run_candidates` (payload/scripts/lib/run.sh) walks and reads every one of
# them, not just the first. This is the repo-scale reading research R3 §7 and T4/T17
# each reproduced by hand with a scratchpad copy of this script; it is now first
# class. The bench always prints `hook-latency: candidates=<1+n>` before the timing
# lines, so a reader can see what was measured. At n=0 nothing else changes: no extra
# files are written and the timing output is byte-identical to the shipped default
# apart from that one new line.
#
#     BENCH_EXTRA_CANDIDATES=16 bash tests/bench/hook-latency.sh
#
# (17 = this repo's own plan-plus-incident count today, per T4/T17's repo-scale
# reading — see record/wave-14-tune-181/bench-T17-a0f043f.txt.)
#
# --candidates-only: build the fixture (extra candidates included), print the
# candidates line, the interpreter line (below), and `hook-latency: sandbox=<path>`,
# then exit WITHOUT running either hook and WITHOUT cleaning up the sandbox — the
# caller owns removing it. This is tests/hook-latency.test.sh §7's own minimal-run
# switch: that pin checks the FIXTURE the knob builds, not hook timing, and the two
# hook runs this script otherwise makes are ten invocations each it has no reason to
# pay for. §8 reuses the same switch to check the interpreter line without paying
# for those ten invocations either.
#
# THE INTERPRETER LINE, AND WHY THE FORK SITE CHANGED (epic-23 wave-14 T30, REQ-4;
# A-orch-47). This bench used to time `subprocess.run(["bash", hook], …)` — a
# PATH-resolved `bash`, Homebrew 5.3 on this machine — while the CLI invokes every
# hook BY PATH and lets the kernel read its own `#!/bin/bash` shebang (3.2.57, the
# floor's interpreter; hooks.json invokes each hook by path). That measured a
# production nobody runs, and 5.3's readings are the noisier of the two (A-orch-47:
# five medians spanning 6.6 ms under 5.3 vs 0.2 ms under 3.2). `run_n` below now
# execs the hook BY ITS OWN PATH — `subprocess.run([hook], …)` puts the hook path in
# argv[0], so the kernel takes the shebang exactly as the CLI does — and, once per
# capture, before any timing line, this script prints:
#
#     hook-latency: interpreter=<path> <version line>
#
# <path> is parsed from bash-walls.sh's own `#!` line, never PATH's `bash`; <version
# line> is that binary's own `--version | head -1`. Printed under --candidates-only
# too, so a reader — or a suite pin — can see what the bench is ABOUT to fork without
# paying for the runs that would prove it.
#
# Usage: bash tests/bench/hook-latency.sh [--hooks-dir DIR] [--candidates-only]

set -uo pipefail

HOOKS_DIR=""
CANDIDATES_ONLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --hooks-dir)
      HOOKS_DIR="${2:-}"
      [ $# -ge 2 ] || { echo "hook-latency: --hooks-dir needs a value" >&2; exit 1; }
      shift 2
      ;;
    --hooks-dir=*)
      HOOKS_DIR="${1#*=}"
      shift
      ;;
    --candidates-only)
      CANDIDATES_ONLY=1
      shift
      ;;
    -h|--help)
      sed -n '2,57p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "hook-latency: unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

BENCH_EXTRA_CANDIDATES="${BENCH_EXTRA_CANDIDATES:-0}"
case "$BENCH_EXTRA_CANDIDATES" in
  ''|*[!0-9]*)
    echo "hook-latency: BENCH_EXTRA_CANDIDATES must be a non-negative integer: $BENCH_EXTRA_CANDIDATES" >&2
    exit 1
    ;;
esac

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
HOOKS_DIR="${HOOKS_DIR:-$REPO_ROOT/hooks}"
_HOOKS_DIR_REQUESTED="$HOOKS_DIR"
HOOKS_DIR="$(cd "$HOOKS_DIR" 2>/dev/null && pwd -P)" || {
  echo "hook-latency: --hooks-dir does not exist: ${_HOOKS_DIR_REQUESTED}" >&2
  exit 1
}

command -v jq >/dev/null 2>&1 || { echo "hook-latency: jq absent — cannot build payloads" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "hook-latency: python3 absent — cannot time" >&2; exit 1; }

BASH_WALLS_HOOK="$HOOKS_DIR/bash-walls.sh"
STOP_HOOK="$HOOKS_DIR/stop.sh"
[ -f "$BASH_WALLS_HOOK" ] || { echo "hook-latency: no hook at $BASH_WALLS_HOOK" >&2; exit 1; }
[ -f "$STOP_HOOK" ] || { echo "hook-latency: no hook at $STOP_HOOK" >&2; exit 1; }

SANDBOX="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/hook-latency-bench.XXXXXX")" && pwd -P)"
# --candidates-only skips this cleanup deliberately (see the flag's own header doc
# above) so its caller can inspect the fixture files before removing them itself.
if [ "$CANDIDATES_ONLY" -eq 0 ]; then
  cleanup() { rm -rf "$SANDBOX"; }
  trap cleanup EXIT
fi

SID="be4c4570-1eb4-4c1a-9c1a-1a2b3c4d5e6f"

# ---------- the ENGAGED project fixture ----------
#
# One real git repo, one open plan, one engagement marker — nothing that would make
# any of the ten wall/verdict functions block or fail closed, so every one of them
# runs its ordinary quiet path.
PROJECT="$SANDBOX/proj"
mkdir -p "$PROJECT/.bionic/tmp" "$PROJECT/.bionic/docs/plans" "$PROJECT/.bionic/docs/record"
git -C "$PROJECT" init -q 2>/dev/null
git -C "$PROJECT" config user.email bench@example.com
git -C "$PROJECT" config user.name bench
printf 'seed\n' > "$PROJECT/README.md"
git -C "$PROJECT" add README.md
git -C "$PROJECT" commit -q -m seed 2>/dev/null
git -C "$PROJECT" checkout -q -b feature/bench 2>/dev/null
: > "$PROJECT/.bionic/tmp/engaged-$SID.state"
printf -- '---\ncanonical_sdlc_version: 14\n---\n\n## SDLC State\n\ncurrent: 4\n\n- Step 4\n' \
  > "$PROJECT/.bionic/docs/plans/wave-01.plan.md"

# BENCH_EXTRA_CANDIDATES extra plan-shaped files, same shape as the one above —
# front matter plus a flush-left `## SDLC State` heading, so `_run_candidates`
# (payload/scripts/lib/run.sh) walks and reads every one of them. Depth 1 under
# plans/, well inside the walk's own maxdepth 2 bound. At the default of 0 this
# loop never runs and the fixture is byte-identical to the shipped one.
_extra=1
while [ "$_extra" -le "$BENCH_EXTRA_CANDIDATES" ]; do
  printf -- '---\ncanonical_sdlc_version: 14\n---\n\n## SDLC State\n\ncurrent: 4\n\n- Step 4\n' \
    > "$PROJECT/.bionic/docs/plans/extra-$_extra.plan.md"
  _extra=$((_extra + 1))
done

echo "hook-latency: candidates=$((1 + BENCH_EXTRA_CANDIDATES))"

# ---------- the interpreter header (T30) ----------
#
# Parsed from bash-walls.sh's own shebang line, never from PATH's `bash` — that is
# the whole point of this line existing. `sed -n '1s/^#!//p'` strips the `#!`
# marker only on line 1 and prints nothing if line 1 isn't a shebang at all; `awk
# '{print $1}'` then drops any trailing interpreter args (e.g. a `-x` some other
# hook might carry) and leading/trailing whitespace along with it.
_interp_path=$(sed -n '1s/^#!//p' "$BASH_WALLS_HOOK" | awk '{print $1}')
if [ -n "$_interp_path" ] && [ -x "$_interp_path" ]; then
  _interp_version=$("$_interp_path" --version 2>&1 | head -1)
else
  _interp_version="(unknown — no executable found at parsed shebang path)"
fi
echo "hook-latency: interpreter=$_interp_path $_interp_version"

if [ "$CANDIDATES_ONLY" -eq 1 ]; then
  echo "hook-latency: sandbox=$SANDBOX"
  exit 0
fi

FAKE_HOME="$SANDBOX/home"
mkdir -p "$FAKE_HOME"
NO_PLUGINS="$SANDBOX/no-plugins"

# ---------- the fixed payloads ----------

BASH_WALLS_PAYLOAD=$(jq -nc --arg s "$SID" --arg c "$PROJECT" \
  '{session_id:$s, cwd:$c, hook_event_name:"PreToolUse", tool_name:"Bash",
    tool_input:{command:"ls -la"}, tool_use_id:"toolu_bench_walls"}')

TRANSCRIPT="$SANDBOX/transcript.jsonl"
jq -nc '{type:"assistant",message:{model:"claude-opus-5",
          usage:{input_tokens:1000,cache_creation_input_tokens:0,cache_read_input_tokens:0}}}' \
  > "$TRANSCRIPT"

STOP_PAYLOAD=$(jq -nc --arg s "$SID" --arg c "$PROJECT" --arg t "$TRANSCRIPT" \
  '{session_id:$s, transcript_path:$t, cwd:$c, hook_event_name:"Stop",
    stop_hook_active:false, background_tasks:[]}')

# ---------- driving + timing ----------
#
# One python3 process per hook, looping N times inside itself (spawn N bash
# subprocesses, wall-clock each with time.time()) rather than N python3 invocations,
# so the number reported is the hook's own cost, not python3's startup added ten times.
run_n() {  # <label> <hook> <payload> <n>
  BIONIC_BENCH_HOOK="$2" BIONIC_BENCH_PAYLOAD="$3" BIONIC_BENCH_N="$4" \
  BIONIC_BENCH_HOME="$FAKE_HOME" BIONIC_BENCH_SID="$SID" BIONIC_BENCH_NOPLUGINS="$NO_PLUGINS" \
  python3 - "$1" <<'PYEOF'
import os, subprocess, sys, time

label = sys.argv[1]
hook = os.environ["BIONIC_BENCH_HOOK"]
payload = os.environ["BIONIC_BENCH_PAYLOAD"].encode()
n = int(os.environ["BIONIC_BENCH_N"])

env = dict(os.environ)
env["HOME"] = os.environ["BIONIC_BENCH_HOME"]
env["CLAUDE_CODE_SESSION_ID"] = os.environ["BIONIC_BENCH_SID"]
env["CLAUDE_PROJECT_DIR"] = ""
env["BIONIC_PLUGINS_DIR"] = os.environ["BIONIC_BENCH_NOPLUGINS"]
for k in ("BIONIC_BENCH_HOOK", "BIONIC_BENCH_PAYLOAD", "BIONIC_BENCH_N",
          "BIONIC_BENCH_HOME", "BIONIC_BENCH_SID", "BIONIC_BENCH_NOPLUGINS"):
    env.pop(k, None)

times_ms = []
for _ in range(n):
    start = time.time()
    # Fork the hook BY ITS OWN PATH (argv[0] == hook), not "bash <hook>" — that puts
    # the hook's path in argv[0] so the kernel reads its own `#!/bin/bash` shebang,
    # exactly as the CLI does when it invokes a hook by path (T30, A-orch-47).
    # "bash <hook>" instead forks whatever `bash` PATH resolves first, bypassing the
    # shebang entirely and timing an interpreter production never runs.
    subprocess.run([hook], input=payload,
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, env=env)
    times_ms.append((time.time() - start) * 1000.0)

times_ms.sort()
mid = n // 2
median = times_ms[mid] if n % 2 == 1 else (times_ms[mid - 1] + times_ms[mid]) / 2.0
print(f"{label} median={median:.1f} min={min(times_ms):.1f} max={max(times_ms):.1f}")
PYEOF
}

run_n "bash-walls.sh" "$BASH_WALLS_HOOK" "$BASH_WALLS_PAYLOAD" 10
run_n "stop.sh" "$STOP_HOOK" "$STOP_PAYLOAD" 10
