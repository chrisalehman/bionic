#!/bin/bash
# tests/hook-timeout.test.sh — HOOKS NEVER TIME OUT (epic-23 wave-24-fixit-1811, T4; REQ-5,
# AC-5.1; spec D6, D7).
#
# WHAT IT OWNS. Wall-clock, and only wall-clock: each input below, driven through the real
# hook, finishes inside BUDGET seconds. This is the one suite in the tree that gates on time.
# tests/hook-latency.test.sh gates fork counts and says why timing is noisy; Chris ruled the
# exception (2026-10-03, design ledger Δ2) because a count cannot see the failure this suite
# exists for — a hook killed by its own `timeout: 10` in hooks.json, which fails open.
#
# WHY TIME CAN GATE HERE. The broken hooks took 5–120 s on these inputs and the fixed ones
# take a few hundredths, so a 2 s budget sits an order of magnitude from both, which holds
# under an 8-wide suite run (research-R2 §5). A row near 2 s on a fixed hook is a regression
# in its own right, not noise.
#
# THE COST WAS QUADRATIC, NOT LARGE (research-R2). bash 3.2's `${v//pat/}` and `${v/pat/r}`
# cost about matches × length, `${s:i:1}` walks from the start of a UTF-8 string every call,
# and an append loop copies the whole string each step. So the inputs are chosen for
# quote density, match offset and multibyte length, not just size:
#   a1  governing-skill  Edit of a 64 KB plan, old_string at ~8000
#   a2  governing-skill  the same plan, old_string at ~60000
#   b   bash-walls       a 64 KB python heredoc ending in a literal `git push`
#   b'  bash-walls       the same command ending in `git commit`, from a read-only agent
#   c   bash-walls       a 7.7 K quote-dense command ending in `g'i't commit`
#   d   bash-walls       a 3-segment `&&` chain whose first segment is ~8 K em dashes
#   e   bash-walls       a 52 KB single-quoted `python3 -c` body of 1 350 short lines (T22)
#   f   bash-walls       the same body double-quoted, then a newline and `make`
# Every row runs under `/bin/bash` (3.2 on macOS, the interpreter ADR-001 pins) AND under
# the newest bash on PATH: the 64 KB command also took 3.9 s under bash 5.3, so moving off
# 3.2 was never the fix.
#
# EACH ROW ALSO WITNESSES THE PATH IT TIMES. A fast hook that left early would pass a timing
# assertion for the wrong reason, so every row asserts the verdict that can only come from
# the far side of its hot path: the post-edit Tasks fault for a1/a2, protect-main's refusal
# for b, the read-only arm for b', the evidence gate for c (which the screen reaches only
# through its strip — `git` is not in c's text), and the chain deny for d2 and silence for d (the
# 8 K segment ends in a redirect).
#
# THE SELF-CHECK (§3) proves each input is heavy: the 7223b594 hot line, copied here verbatim
# and run on the same bytes under bash 3.2, must exceed the budget. An input that never
# reached the hot path could not make it do so. On a machine whose /bin/bash is not 3.x the
# 3.2-only lines cannot be slow, and the check is printed as an ADVISORY rather than gated.
#
# Timed by python3 (`time.monotonic`, process group killed at the cap). HT_CAP raises the cap
# to read a broken hook's real time for the record; it never changes the budget. The same
# clock also reads the child tree's CPU time (`RUSAGE_CHILDREN`, user+sys, before/after) into
# HT_CPU; only §VERB gates on it — the hook rows gate on wall-clock alone.
#
# FIXTURE FIDELITY (declared, per .claude/rules/test-harness.md, "Fixture fidelity"):
#   * the engaged project, the payload envelopes and the placeholder-evidence plan — the
#     shapes tests/hook-latency.test.sh and tests/bash-walls.test.sh pin.
#   * the input shapes — research-R2 §3–§4 measured each class on real commands: a plan Edit
#     near the end of a 64 KB file, a python heredoc rewriting a plan through `s.replace`, a
#     7,715-character command holding 1,618 single quotes, a ≥3-segment chain with one 8 K
#     segment in UTF-8. The bytes here are SYNTHESIZED to those measurements, not copied.
#   * what each row does NOT pin: machine load. The budget's margin carries that, not the
#     fixture.
#
# ANTI-VACUITY (per .claude/rules/test-harness.md, "Anti-vacuity"): the hooks must exist and
# parse or the suite refuses to run; every fixture's size, offset and quote count is asserted
# before any row reads a time; every row asserts its witness verdict beside its time; and §3
# is the mutation control — the removed line, put back, must blow the budget on these bytes.
#
# Usage: bash tests/hook-timeout.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"
. "$(dirname "$0")/lib/bound-marker.sh"

WALLS_HOOK="${BIONIC_HOOKS_DIR}/bash-walls.sh"
GS_HOOK="${BIONIC_HOOKS_DIR}/canonical-sdlc-governing-skill.sh"
BUDGET=2
CAP="${HT_CAP:-$BUDGET}"

command -v jq >/dev/null 2>&1      || { echo "hook-timeout: jq absent — suite cannot run"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "hook-timeout: python3 absent — suite cannot run"; exit 1; }
for _h in "$WALLS_HOOK" "$GS_HOOK"; do
  [ -f "$_h" ] || { echo "hook-timeout: no hook at $_h — suite refuses to run"; exit 1; }
  /bin/bash -n "$_h" || { echo "hook-timeout: $_h does not parse — suite refuses to run"; exit 1; }
done

SANDBOX="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/hook-timeout-test.XXXXXX")" && pwd -P)"
cleanup() { rm -rf "$SANDBOX"; }
trap cleanup EXIT

SID="7d1e2f3a-4b5c-4d6e-8f70-81a2b3c4d5e6"
ACTOR="aht4reader-0123456789abcdef"
FAKE_HOME="$SANDBOX/home"
mkdir -p "$FAKE_HOME" "$SANDBOX/in"

# ---------- the shells ----------

# ht_newest_bash — the highest-versioned bash among every `bash` on PATH.
ht_newest_bash() {
  local best="" bestv=-1 cand v
  while IFS= read -r cand; do
    [ -x "$cand" ] || continue
    v=$("$cand" -c 'printf "%d" $(( BASH_VERSINFO[0] * 10000 + BASH_VERSINFO[1] * 100 + BASH_VERSINFO[2] ))' 2>/dev/null) || continue
    case "$v" in ''|*[!0-9]*) continue ;; esac
    if [ "$v" -gt "$bestv" ]; then best="$cand"; bestv="$v"; fi
  done <<EOF
$(type -ap bash)
EOF
  printf '%s' "$best"
}
ht_version() { "$1" -c 'printf "%s" "$BASH_VERSION"' 2>/dev/null; }

NEWEST_BASH="$(ht_newest_bash)"
SHELLS="/bin/bash"
if [ -n "$NEWEST_BASH" ] && [ "$(ht_version "$NEWEST_BASH")" != "$(ht_version /bin/bash)" ]; then
  SHELLS="/bin/bash $NEWEST_BASH"
fi
OLD_IS_32=0
case "$(ht_version /bin/bash)" in 3.*) OLD_IS_32=1 ;; esac

# ---------- the clock ----------

# ht_time <shell> <script> <stdin-file> <cwd> <cap> -> "<seconds> <exit|timeout>"
# The environment is the caller's. A child that outlives the cap is killed with its whole
# process group, so a broken hook's forks do not keep burning the next row's budget.
cat > "$SANDBOX/clock.py" <<'PY'
import os, signal, subprocess, sys, time
import resource
shell, script, stdin_path, cwd, cap = sys.argv[1:6]
def cpu():
    r = resource.getrusage(resource.RUSAGE_CHILDREN)
    return r.ru_utime + r.ru_stime
def put_cpu(c):
    with open(os.environ["HT_CPU_FILE"], "w") as f:
        f.write("%.3f" % c)
out = open(sys.argv[6], "wb") if len(sys.argv) > 6 else subprocess.DEVNULL
err = open(sys.argv[7], "wb") if len(sys.argv) > 7 else subprocess.DEVNULL
with open(stdin_path, "rb") as fin:
    c0 = cpu()
    t = time.monotonic()
    p = subprocess.Popen([shell, script], stdin=fin, stdout=out, stderr=err, cwd=cwd,
                         start_new_session=True)
    try:
        rc = p.wait(timeout=float(cap))
        put_cpu(cpu() - c0)
        print("%.3f %d" % (time.monotonic() - t, rc))
    except subprocess.TimeoutExpired:
        os.killpg(p.pid, signal.SIGKILL)
        p.wait()
        put_cpu(cpu() - c0)
        print("%.3f timeout" % (time.monotonic() - t))
PY

HT_SECS=""; HT_RC=""; HT_OUT=""; HT_ERR=""; HT_CPU=""
ht_time() {  # <shell> <script> <stdin-file> <cwd> <cap>
  local r
  r=$(env HOME="$FAKE_HOME" CLAUDE_CODE_SESSION_ID="$SID" CLAUDE_PROJECT_DIR= \
        BIONIC_PLUGINS_DIR="$SANDBOX/no-plugins" HT_CPU_FILE="$SANDBOX/.cpu" LANG=en_US.UTF-8 LC_ALL= LC_CTYPE= \
        python3 "$SANDBOX/clock.py" "$1" "$2" "$3" "$4" "$5" "$SANDBOX/.out" "$SANDBOX/.err")
  HT_SECS="${r%% *}"; HT_RC="${r#* }"
  HT_CPU=$(cat "$SANDBOX/.cpu" 2>/dev/null)
  HT_OUT=$(cat "$SANDBOX/.out" 2>/dev/null); HT_ERR=$(cat "$SANDBOX/.err" 2>/dev/null)
}
under_budget() { awk -v s="$1" -v b="$BUDGET" 'BEGIN { exit !(s + 0 < b + 0) }'; }
over_budget()  { awk -v s="$1" -v b="$BUDGET" 'BEGIN { exit !(s + 0 > b + 0) }'; }

# ---------- the fixtures ----------

mk_repo() {  # <name> -> an engaged git repo on a feature branch
  local repo="$SANDBOX/$1"
  mkdir -p "$repo/.bionic/tmp" "$repo/.bionic/docs/plans/epic-01-demo" "$repo/.bionic/docs/record"
  git -C "$repo" init -q 2>/dev/null
  git -C "$repo" config user.email t@example.com
  git -C "$repo" config user.name "T"
  printf 'seed\n' > "$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit -qm seed 2>/dev/null
  git -C "$repo" checkout -q -b feature/t4 2>/dev/null
  : > "$repo/.bionic/tmp/engaged-$SID.state"
  printf '%s' "$repo"
}

setup_section "the repos and the inputs"

R_GS="$(mk_repo gs)"
R_PUSH="$(mk_repo push)"
R_AGENT="$(mk_repo agent)"; : > "$R_AGENT/.bionic/tmp/roster-$SID.state"
R_COMMIT="$(mk_repo commit)"
R_CHAIN="$(mk_repo chain)"

# The evidence gate refuses any commit under a bound plan whose step evidence is a
# placeholder — c's witness.
printf '%s\n' '---
governing-skill: canonical-sdlc
canonical_sdlc_version: 14
intent: build
rigor: tested
scale: wave
deploy_target: none
use_worktree: false
has_ui: false
---
# plan

## SDLC State
current: 5
approved-by: fixture 2026-09-07T00:00Z "approved"
Step 5: TODO' > "$R_COMMIT/.bionic/docs/plans/active.md"
bound_marker "$R_COMMIT" "$SID" "$R_COMMIT/.bionic/docs/plans/active.md"

GS_PLAN="$R_GS/.bionic/docs/plans/epic-01-demo/big.plan.md"

# Every input is generated here, byte for byte, so the sizes and offsets below are facts of
# this run rather than claims about a file somewhere else.
python3 - "$SANDBOX/in" "$GS_PLAN" "$SID" "$ACTOR" "$R_GS" "$R_PUSH" "$R_AGENT" "$R_COMMIT" "$R_CHAIN" <<'PY'
import json, sys
d, plan, sid, actor, r_gs, r_push, r_agent, r_commit, r_chain = sys.argv[1:10]

# -- a: a version-14 plan at step 3 whose Tasks table runs to 64 KB --
head = """---
governing-skill: superpowers:writing-plans
sdlc-step: 3
epic: epic-01-demo
wave: wave-01-x
canonical_sdlc_version: 14
intent: build
rigor: audited
scale: wave
cleanup_on_finish: true
use_worktree: false
surface_type: none
language: none
has_ui: false
multi_agent: false
deploy_target: none
model_plan: orchestrator=fable-5-high; exec-complex=opus-fresh; exec-standard=sonnet-fresh; explore=sonnet-fresh
parallel-budget: writers=8 suites=4 worktrees=32 test_jobs=8 source=probe
---

## Goal

A concise paragraph describing this fixture's goal.

## Verification Matrix

stack-health: n/a: no long-running serve observed

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1 | T1 | discharged | see AC-1 | CONFIRMED |

## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | status |
|---|---|---|---|---|---|---|---|---|---|
"""
def row(i):
    return "| T%d | 4 | build | rewrite the reader so it walks the table once — row %05d | implementor | — | 30m | REQ-x | a.sh | pending |\n" % (i, i)
body = head
i = 0
rows = {}
while len(body.encode()) < 65790:
    i += 1
    rows[i] = len(body.encode())
    body += row(i)
open(plan, "w").write(body)
def nearest(off):
    return min(rows, key=lambda k: abs(rows[k] - off))
meta = {}
for name, off in (("a1", 8000), ("a2", 60000)):
    k = nearest(off)
    old = row(k).rstrip("\n")
    new = old.replace("| pending |", "| doing |")
    payload = {"session_id": sid, "tool_name": "Edit",
               "tool_input": {"file_path": plan, "old_string": old, "new_string": new,
                              "replace_all": False}}
    json.dump(payload, open("%s/%s.json" % (d, name), "w"))
    meta[name] = rows[k]

def bash_payload(cwd, cmd, agent=False):
    p = {"session_id": sid, "cwd": cwd, "hook_event_name": "PreToolUse", "tool_name": "Bash",
         "tool_input": {"command": cmd}, "tool_use_id": "toolu_hook_timeout"}
    if agent:
        p["agent_id"] = actor
        p["agent_type"] = "bionic:test-runner"
    return p

# -- b: a python heredoc rewriting a plan through s.replace('''…''', '''…''') --
lines = ["python3 - <<'PY'", "p = '.bionic/docs/plans/active.md'", "s = open(p).read()"]
n = 0
while len("\n".join(lines)) < 65400:
    n += 1
    lines.append("s = s.replace('''| T%d | 4 | build | the \"old\" reader — pending |''', '''| T%d | 4 | build | the \"new\" reader — landed |''')" % (n, n))
lines += ["open(p, 'w').write(s)", "PY"]
heredoc = "\n".join(lines)
json.dump(bash_payload(r_push, heredoc + "\ngit push origin main"), open(d + "/b.json", "w"))
json.dump(bash_payload(r_agent, heredoc + "\ngit commit -m 'T4: rewrite'", agent=True),
          open(d + "/b2.json", "w"))
meta["b"] = len(heredoc + "\ngit push origin main")

# -- c: 7.7 K of single-quoted words, one obfuscated commit at the end --
toks = []
cmd = "printf '%s\\n'"
k = 0
while len(cmd) < 7680:
    k += 1
    cmd += " 'w%04d'" % k
cmd += " && g'i't commit -m x"
json.dump(bash_payload(r_commit, cmd), open(d + "/c.json", "w"))
meta["c"] = len(cmd)
meta["c_quotes"] = cmd.count("'")

# -- d: three && segments; the first is ~8 K characters of em dashes ending in a redirect --
seg = 'printf %s "' + ("—" * 8000) + '" > out.txt'
chain = seg + " && echo two && echo three"
json.dump(bash_payload(r_chain, chain), open(d + "/d.json", "w"))
meta["d_seg_chars"] = len(seg)
# -- d2: the same long segment, then a build segment — the witness that d's silence is the
#    hook finishing its walk rather than leaving early (see row d2 below) --
json.dump(bash_payload(r_chain, seg + " && make && echo three"), open(d + "/d2.json", "w"))

# -- e, f: a python3 -c body, never a heredoc, so nothing strips it before the classifier (T22) --
# Many short lines, not a few long ones: cmd_class's line loop cost lines × length under 3.2.
body = ["import re", "p = \".bionic/docs/plans/active.md\"", "s = open(p).read()"]
n = 0
while len("\n".join(body)) < 51700:
    n += 1
    body.append("s = s.replace(\"T%d — a\", \"T%d — b\")" % (n, n))
body.append("open(p, \"w\").write(s)")
body = "\n".join(body)
sq = "python3 -c '" + body + "'"
dq = "python3 -c \"" + body.replace("\"", "'") + "\""
json.dump(bash_payload(r_chain, sq), open(d + "/e.json", "w"))
# -- e2, f: the same bodies with `make` on the next line — the witness that the reading walked
#    past the body (a build deny can only come from the segment after it) --
json.dump(bash_payload(r_chain, sq + "\nmake"), open(d + "/e2.json", "w"))
json.dump(bash_payload(r_chain, dq + "\nmake"), open(d + "/f.json", "w"))
meta["e_bytes"] = len(sq.encode())
meta["e_lines"] = body.count("\n") + 1
meta["e_inner_quotes"] = body.count("'")

json.dump(meta, open(d + "/meta.json", "w"))
PY

meta() { jq -r ".$1" "$SANDBOX/in/meta.json"; }
expect_true "fixture: the plan is at least 64 KB" test "$(wc -c < "$GS_PLAN")" -ge 65536
expect_true "fixture: a1's old_string sits within 1 KB of offset 8000" \
  awk -v o="$(meta a1)" 'BEGIN { exit !(o > 7000 && o < 9000) }'
expect_true "fixture: a2's old_string sits within 1 KB of offset 60000" \
  awk -v o="$(meta a2)" 'BEGIN { exit !(o > 59000 && o < 61000) }'
expect_true "fixture: b's command is at least 64 000 characters" test "$(meta b)" -ge 64000
expect_true "fixture: c's command is ~7.7 K with over 1 500 single quotes" \
  awk -v n="$(meta c)" -v q="$(meta c_quotes)" 'BEGIN { exit !(n >= 7600 && n <= 7900 && q >= 1500) }'
expect_true "fixture: d's long segment is at least 8 000 characters" test "$(meta d_seg_chars)" -ge 8000
expect_true "fixture: e's command is at least 50 000 bytes" test "$(meta e_bytes)" -ge 50000
expect_true "fixture: e's body is at least 1 000 lines" test "$(meta e_lines)" -ge 1000
expect_eq "fixture: e's body holds no single quote, so it is one quoted word" "0" "$(meta e_inner_quotes)"

# ---------- the rows ----------

# row <id> <hook> <repo> <expected exit> <witness substring> <channel: out|err>
# A witness of SILENT asserts an empty stdout instead: the verdict is "nothing to say".
row() {
  local id="$1" hook="$2" repo="$3" want_rc="$4" witness="$5" chan="$6" sh got
  for sh in $SHELLS; do
    rm -f "$repo/.bionic/tmp/farm-out.state"
    ht_time "$sh" "$hook" "$SANDBOX/in/$id.json" "$repo" "$CAP"
    echo "hook-timeout: $id under $sh ($(ht_version "$sh")): ${HT_SECS}s rc=$HT_RC"
    expect_true "$id [$sh]: under ${BUDGET}s (took ${HT_SECS}s)" under_budget "$HT_SECS"
    expect_eq "$id [$sh]: exit $want_rc" "$want_rc" "$HT_RC"
    if [ "$chan" = out ]; then got="$HT_OUT"; else got="$HT_ERR"; fi
    if [ "$witness" = SILENT ]; then
      expect_eq "$id [$sh]: the hot path was reached and answered — silence, with d2 beside it" "" "$got"
    else
      expect_contains "$id [$sh]: the hot path was reached — $witness" "$witness" "$got"
    fi
  done
}

section "1 — governing-skill: a 64 KB plan Edit at ~8000 and ~60000"
echo "hook-timeout: shells = $SHELLS"
row a1 "$GS_HOOK" "$R_GS" 2 "status doing" err
row a2 "$GS_HOOK" "$R_GS" 2 "status doing" err

section "2 — bash-walls: the 64 KB heredoc, the quote-dense command, the 8 K chain segment"
row b  "$WALLS_HOOK" "$R_PUSH"   2 "main is a protected branch here" err
row b2 "$WALLS_HOOK" "$R_AGENT"  2 "a read-only role never commits" err
row c  "$WALLS_HOOK" "$R_COMMIT" 2 "evidence line is a placeholder" err
# d: the chain tier-2 nudge that used to witness this row is retired (wave-24 T11, AC-7.7), so a
# chain with no tier-1 segment answers with silence. Silence alone would read the same if the
# hook had left early, so d2 runs the same long first segment with a build segment behind it:
# its deny (class=chain) can only come from a walk that got past the 8 K segment and read the
# segments after it. d is the input being timed; d2 is the proof the timing covers the walk.
row d  "$WALLS_HOOK" "$R_CHAIN"  0 SILENT out
row d2 "$WALLS_HOOK" "$R_CHAIN"  0 "chain-class command" out

section "2b — bash-walls: a 52 KB quoted python3 -c body the classifier reads whole (T22)"
# e is the input being timed: class none, so silence. e2 and f put `make` on the line after
# the body, and their build deny can only come from a reading that walked past it.
row e  "$WALLS_HOOK" "$R_CHAIN"  0 SILENT out
row e2 "$WALLS_HOOK" "$R_CHAIN"  0 "farm-out [deny] class=build" err
row f  "$WALLS_HOOK" "$R_CHAIN"  0 "farm-out [deny] class=build" err

# ---------- the self-check ----------

section "3 — self-check: the 7223b594 hot line on the same input exceeds ${BUDGET}s"
#
# Each snippet is the hot line as it stood at 7223b594, copied verbatim, fed the same bytes
# the row above fed the hook. It is the line, not the hook: a hook-level rerun would need
# the old tree, and the line is what the fix removed.

# a: canonical-sdlc-governing-skill.sh:798-818 — the file read and the unique splice.
cat > "$SANDBOX/hot-a.sh" <<'SH'
BIONIC_INPUT=$(cat)
FILE_PATH=$(printf '%s' "$BIONIC_INPUT" | jq -r '.tool_input.file_path')
CONTENT=$(cat "$FILE_PATH")
_gs_old=$(printf '%s' "$BIONIC_INPUT" | jq -j '.tool_input.old_string // ""'; printf X)
_gs_old=${_gs_old%X}
_gs_new=$(printf '%s' "$BIONIC_INPUT" | jq -j '.tool_input.new_string // ""'; printf X)
_gs_new=${_gs_new%X}
CONTENT=${CONTENT/"$_gs_old"/"$_gs_new"}
SH

# b, c: walls.sh:218-223 — `_wall_mentions_git`'s four passes, once.
cat > "$SANDBOX/hot-b.sh" <<'SH'
COMMAND=$(jq -r '.tool_input.command')
_p="$COMMAND"
_p="${_p//\\$'\n'/}"
_p="${_p//\\/}"; _p="${_p//\'/}"; _p="${_p//\"/}"
SH

# d: walls.sh:4662-4710 — `_chain_seg_split`'s character walk over the first segment. (That
# function is deleted at T11; the line is what the self-check times, as it stood at 7223b594.)
cat > "$SANDBOX/hot-d.sh" <<'SH'
COMMAND=$(jq -r '.tool_input.command')
s="${COMMAND%% && *}"
n=${#s}; i=0; cur=""
while [ "$i" -lt "$n" ]; do
  c="${s:i:1}"
  cur="$cur$c"
  i=$((i + 1))
done
SH

# e: cmd-class.sh:833-844 at 7223b594 (1386-1395 at 19d708d1, unchanged) — cmd_class's walk over cmd_class_lines' output, which
# echoes each segment whole, so a quoted body's every line is one more pass over all of it.
cat > "$SANDBOX/hot-e.sh" <<'SH'
. "$HT_CMD_CLASS_LIB"
COMMAND=$(jq -r '.tool_input.command')
lines=$(cmd_class_lines "$COMMAND")
seen=$'\n'
rest="$lines"
while [ -n "$rest" ]; do
  line="${rest%%$'\n'*}"
  case "$rest" in
    *$'\n'*) rest="${rest#*$'\n'}" ;;
    *)        rest="" ;;
  esac
  cls="${line%%$'\t'*}"
  [ -n "$cls" ] || continue
  seen="$seen$cls"$'\n'
done
SH
HT_CMD_CLASS_LIB="$BIONIC_SCRIPTS_DIR/payload/scripts/lib/cmd-class.sh"
export HT_CMD_CLASS_LIB
expect_true "fixture: the cmd-class library the e self-check sources is on disk" test -f "$HT_CMD_CLASS_LIB"

selfcheck() {  # <id> <snippet>
  ht_time /bin/bash "$SANDBOX/$2" "$SANDBOX/in/$1.json" "$SANDBOX" "$CAP"
  echo "hook-timeout: self-check $1 (7223b594 hot line, /bin/bash): ${HT_SECS}s rc=$HT_RC"
  if [ "$OLD_IS_32" = 1 ]; then
    expect_true "$1: the 7223b594 hot line exceeds ${BUDGET}s on this input (took ${HT_SECS}s)" \
      over_budget "$HT_SECS"
  else
    advise "$1: the 7223b594 hot line on this input" \
      "/bin/bash is $(ht_version /bin/bash), not 3.2, so the 3.2-only cost cannot show" \
      over_budget "$HT_SECS"
  fi
}
selfcheck a1 hot-a.sh
selfcheck a2 hot-a.sh
selfcheck b  hot-b.sh
selfcheck c  hot-b.sh
selfcheck d  hot-d.sh
selfcheck e  hot-e.sh

# ---------- the plan-row verbs ----------

VERB_BUDGET=1
VERB_HANG=2
section "4 — §VERB: each plan-row verb under ${VERB_BUDGET}s CPU on a 66 KB plan (wave-24 T15; REQ-9 AC-9.7, D14)"
#
# The five verbs are typed by the orchestrator in its own turn, so their wall-clock is the
# turn's. AC-9.7's bound is the verb's own cost, so it is gated on CPU time (user+sys of the
# verb's whole child tree), which machine load does not move: at load ~8.6 on 8 cores the same
# verbs read 1.01–1.15 s of wall against 0.59–0.67 s unloaded. Wall is gated only at
# ${VERB_HANG}s, a hang ceiling matching the hook rows' budget. Both numbers print on every row.
# Each runs the whole task-add transaction — the projection through units.sh, a dry
# commit through the real bash-walls.sh, the checksum and the swap — on a plan the size of
# this wave's own (66 KB: 25 task rows, 40 matrix rows, a 30-row dispatch ledger, the rest task
# detail). The witness is the verb's own success line beside exit 0, which it prints only after
# the dry commit admitted the copy and the copy was swapped in. The plan is restored from its
# pristine copy before each shell's run, so `current 4` moves under both shells.
POKER_SH="${BIONIC_HOOKS_DIR}/session-poker.sh"
/bin/bash -n "$POKER_SH" || { echo "hook-timeout: $POKER_SH does not parse — suite refuses to run"; exit 1; }
R_VERB="$(mk_repo verb)"
VERB_PLAN="$R_VERB/.bionic/docs/plans/epic-01-demo/wave-01-verb.plan.md"
mkdir -p "$R_VERB/.bionic/docs/specs/epic-01-demo"
printf '# requirements\n' > "$R_VERB/.bionic/docs/specs/epic-01-demo/wave-01-verb.requirements.md"
printf '# spec\n' > "$R_VERB/.bionic/docs/specs/epic-01-demo/wave-01-verb.spec.md"
python3 - "$VERB_PLAN" <<'PY'
import sys
plan = sys.argv[1]
out = ["---", "governing-skill: canonical-sdlc", "canonical_sdlc_version: 14", "intent: bugfix",
       "rigor: audited", "scale: wave", "multi_agent: true", "use_worktree: true", "has_ui: false",
       "walk: exempt", "deploy_target: n/a",
       "parallel-budget: writers=8 suites=4 worktrees=32 test_jobs=8 source=probe", "---", "",
       "# fixture wave", "", "## SDLC State", "", "current: 3", "working-branch: feature/t4",
       'approved-by: fixture 2026-09-23T00:00Z "approved"', "",
       "- Step 1: requirements: specs/epic-01-demo/wave-01-verb.requirements.md",
       "- Step 2: spec: specs/epic-01-demo/wave-01-verb.spec.md",
       "- Step 3: plan: plans/epic-01-demo/wave-01-verb.plan.md",
       "- Step 4: opened", "  worktree: .worktrees/01-verb", "  base-sha: abc1234",
       "  branch: wave/01-verb"]
for i in range(1, 25):
    out.append("- T%d: landed — merge %07x into wave/01-verb; evidence record/T%d.md" % (i, i * 4099, i))
out.append("- T25: pending dispatch — the floor after every build row")
out += ["", "## Tasks", "", "| id | step | kind | task | agent | deps | size | serves | Files | worktree | base | status |",
        "|---|---|---|---|---|---|---|---|---|---|---|---|"]
for i in range(1, 25):
    out.append("| T%d | 4 | build | rewrite reader %d so it walks the table once | w-T%d | — | 30 | REQ-%d | lib/r%d.sh | — | — | landed |" % (i, i, i, i % 9 + 1, i))
out.append("| T25 | 5 | verify | the floor | test-runner | %s | 30 | REQ-1 | — | — | — | pending |"
           % ", ".join("T%d" % i for i in range(1, 25)))
out += ["", "## Verification Matrix", "", "| AC | tier | status | evidence | auditor |", "|---|---|---|---|---|"]
for i in range(1, 41):
    out.append("| AC-%d.1 | T2 | pending | — | — |" % i)
out.append("")
for i in range(1, 41):
    out += ["AC-%d.1:" % i, "  provenance: fixture row %d" % i, "  fails-when: reader %d walks twice" % i,
            "  eval: T2 — bash tests/reader-%d.test.sh" % i]
out += ["", "## Dispatch ledger", "", "| id | agent | dispatched | expected | artifact | landed | notes |",
        "|---|---|---|---|---|---|---|"]
for i in range(1, 31):
    out.append("| T%d | implementor (w-T%d) | 2026-10-03T%02d:00Z | 30 min | record/T%d.md | landed | batch %d |" % (i, i, i % 24, i, i % 4 + 1))
body = "\n".join(out) + "\n"
detail = ["", "## Task detail", ""]
k = 0
while len((body + "\n".join(detail)).encode()) < 66000:
    k += 1
    detail.append("### T%d — detail" % (k % 24 + 1))
    detail.append("The reader walks the table once and answers every question from that walk; "
                  "the walk is fence-aware and keyed on the header, so a renamed column is a fault "
                  "rather than a silent shift — paragraph %d." % k)
    detail.append("")
# The detail sits between the table and the matrix, as a real plan carries it.
cut = body.index("\n## Verification Matrix")
open(plan, "w").write(body[:cut] + "\n".join(detail) + body[cut:])
PY
cp "$VERB_PLAN" "$SANDBOX/verb-plan.pristine"
bound_marker "$R_VERB" "$SID" "$VERB_PLAN"
: > "$SANDBOX/in/empty"
expect_true "fixture: the verb plan is at least 66 000 bytes" test "$(wc -c < "$VERB_PLAN")" -ge 66000

verb_row() {  # <n> <verb> <args…> — times one verb under each shell already set in VERB_SH
  local n="$1" verb="$2"; shift 2
  { printf 'exec "$BASH" %q' "$POKER_SH"; printf ' %q' "$verb" "$@"; printf '\n'; } > "$SANDBOX/verb-$n.sh"
  ht_time "$VERB_SH" "$SANDBOX/verb-$n.sh" "$SANDBOX/in/empty" "$R_VERB" 30
  echo "hook-timeout: §VERB $verb under $VERB_SH ($(ht_version "$VERB_SH")): cpu=${HT_CPU}s wall=${HT_SECS}s rc=$HT_RC"
  expect_true "§VERB $verb [$VERB_SH]: CPU measured (got '${HT_CPU}')" \
    awk -v s="$HT_CPU" 'BEGIN { exit !(s ~ /^[0-9.]+$/ && s + 0 > 0) }'
  expect_true "§VERB $verb [$VERB_SH]: CPU under ${VERB_BUDGET}s (took ${HT_CPU}s cpu, ${HT_SECS}s wall)" \
    awk -v s="$HT_CPU" -v b="$VERB_BUDGET" 'BEGIN { exit !(s ~ /^[0-9.]+$/ && s + 0 < b + 0) }'
  expect_true "§VERB $verb [$VERB_SH]: wall under the ${VERB_HANG}s hang ceiling (took ${HT_SECS}s wall)" \
    awk -v s="$HT_SECS" -v b="$VERB_HANG" 'BEGIN { exit !(s ~ /^[0-9.]+$/ && s + 0 < b + 0) }'
  expect_eq "§VERB $verb [$VERB_SH]: exit 0" "0" "$HT_RC"
  expect_contains "§VERB $verb [$VERB_SH]: the transaction ran to its swap — its success line" \
    "poker: $verb — " "$HT_OUT"
}
for VERB_SH in $SHELLS; do
  cp "$SANDBOX/verb-plan.pristine" "$VERB_PLAN"
  verb_row 1 current 4
  verb_row 2 task-set T25 size=45
  verb_row 3 step-line T24 'merge checked' --append
  verb_row 4 ledger-add T31 'agent=implementor (w-T31)' dispatched=2026-10-03T12:00Z
  verb_row 5 ledger-set T1 'notes=batch 1, re-run'
  expect_contains "§VERB [$VERB_SH]: the plan carries task-set's cell" "| 45 | REQ-1 |" "$(grep -F '| T25 |' "$VERB_PLAN")"
  expect_contains "§VERB [$VERB_SH]: …and current's move" "current: 4" "$(grep -x 'current: 4' "$VERB_PLAN")"
done

finish
