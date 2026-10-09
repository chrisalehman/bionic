#!/bin/bash
# runner: solo
# TIMING-BOUND IN EVERY SECTION (T25, A-orch-37): each row below READS wall-clock seconds
# against a budget, and seconds are a property of the machine as much as of the code. Sharing
# the CPU with seven other suites in tests/run.sh's parallel batch inflated the §VERB verbs
# from 0.59-0.67 s to 1.01-1.15 s wall (and their CPU time to 0.89-1.05 s), so the marker above
# holds this suite out of that batch; tests/run.sh runs it alone afterwards.
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
#   g   bash-walls       a 200 KB single-quoted `python3 -c` body, engaged, `memory` in the cwd (T28)
#   b3  bash-walls       b's heredoc behind `cd sub && `, committing (T28)
#   b4  bash-walls       b's heredoc behind `cd <absolute repo> && `, committing (T28)
#   k   bash-walls       52 KB of short `"\""` runs, then make (wave-24 critic B1)
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
# HT_CPU, which §VERB prints beside its wall time as a diagnostic; nothing gates on it.
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
# g's repo: its path holds `memory`, which is what sends every command in it through
# cmd_write_targets (hooks/bash-walls.sh, the memory-store screen). The store is under the fake
# home, and BIONIC_CLAUDE_HOME names it for g's rows only, so the runner's own config dir
# cannot move the root.
R_MEM="$(mk_repo memory)"
mkdir -p "$FAKE_HOME/.claude/projects/-x/memory"

# The evidence gate refuses any commit under a bound plan whose step evidence is a
# placeholder — c's witness.
printf '%s\n' '---
governing-skill: canonical-sdlc
canonical_sdlc_version: 14
intent: build
rigor: single
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
python3 - "$SANDBOX/in" "$GS_PLAN" "$SID" "$ACTOR" "$R_GS" "$R_PUSH" "$R_AGENT" "$R_COMMIT" "$R_CHAIN" "$R_MEM" <<'PY'
import json, sys
d, plan, sid, actor, r_gs, r_push, r_agent, r_commit, r_chain, r_mem = sys.argv[1:11]

# -- a: a version-14 plan at step 3 whose Tasks table runs to 64 KB --
head = """---
governing-skill: superpowers:writing-plans
sdlc-step: 3
epic: epic-01-demo
wave: wave-01-x
canonical_sdlc_version: 14
intent: build
rigor: double
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
# -- k: many SHORT double-quoted runs, each holding a backslash, 52 KB in all, then `make`
#    (wave-24 critic Addendum 2 B1). The quote-end scan pays per run on this shape: 1.08 s
#    through the hook on the c0d6ab04 scan, 4.25 s on the T30 scan this row was added to
#    refuse. e/f are ONE long quoted run and cannot see it. --
kq = "echo " + " ".join(['"\\""'] * 10400)
json.dump(bash_payload(r_chain, kq + "\nmake"), open(d + "/k.json", "w"))
meta["k"] = len(kq)
meta["e_bytes"] = len(sq.encode())
meta["e_lines"] = body.count("\n") + 1
meta["e_inner_quotes"] = body.count("'")

# -- b3, b4: b's heredoc behind a leading cd, then a commit. b3's cd is relative, so only the
#    leading-cd read runs; b4's names an absolute directory, so the scan for later cds runs
#    too. The evidence gate's placeholder refusal can only come after both (T28) --
json.dump(bash_payload(r_commit, "cd sub && " + heredoc + "\ngit commit -m x"), open(d + "/b3.json", "w"))
json.dump(bash_payload(r_commit, "cd " + r_commit + " && " + heredoc + "\ngit commit -m x"),
          open(d + "/b4.json", "w"))
meta["b3"] = len("cd sub && " + heredoc + "\ngit commit -m x")

# -- g, g2: e's body grown to 200 KB, run where the cwd holds `memory` and the command does not.
#    g writes inside the repo, so silence; g2 writes the store after the body, and the memory
#    wall's refusal can only come from a tokenizer that walked past it (T28) --
gb = ["import re", "p = \".bionic/docs/plans/active.md\"", "s = open(p).read()"]
n = 0
while len("\n".join(gb).encode()) < 200000:
    n += 1
    gb.append("s = s.replace(\"T%d — a\", \"T%d — b\")" % (n, n))
gb.append("open(p, \"w\").write(s)")
gq = "python3 -c '" + "\n".join(gb) + "'"
json.dump(bash_payload(r_mem, gq + " > out.md"), open(d + "/g.json", "w"))
json.dump(bash_payload(r_mem, gq + " > ~/.claude/projects/-x/memory/n.md"), open(d + "/g2.json", "w"))
meta["g_bytes"] = len(gq.encode())
meta["g_memory"] = (gq + " > out.md").count("memory")
meta["g_inner_quotes"] = "\n".join(gb).count("'")

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
expect_true "fixture: b3's command is at least 64 000 characters" test "$(meta b3)" -ge 64000
expect_true "fixture: k's command is at least 52 000 characters" test "$(meta k)" -ge 52000
expect_true "fixture: g's command is at least 200 000 bytes" test "$(meta g_bytes)" -ge 200000
expect_eq "fixture: g's body holds no single quote, so it is one quoted word" "0" "$(meta g_inner_quotes)"
expect_eq "fixture: g's command never says memory — the cwd is what screens it in" "0" "$(meta g_memory)"
expect_contains "fixture: …and g's cwd does" "memory" "$(jq -r .cwd "$SANDBOX/in/g.json")"

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
row k  "$WALLS_HOOK" "$R_CHAIN"  0 "farm-out [deny] class=build" err

section "2c — bash-walls: a leading cd before the 64 KB heredoc, and 200 KB read for its writes (T28)"
# b3 and b4 are b behind a `cd`. Their placeholder refusal is the evidence gate judging the
# commit, which it does only after reading where the `cd` went. At 64 KB the leading-cd loops
# alone cost 1.3-1.9 s under 3.2, so b3 sits near the budget on the ac258929 lines rather than
# past it; b4 runs those lines and the later-cd scan, which took 19 s.
row b3 "$WALLS_HOOK" "$R_COMMIT" 2 "evidence line is a placeholder" err
row b4 "$WALLS_HOOK" "$R_COMMIT" 2 "evidence line is a placeholder" err
# g is the input being timed: it writes out.md in the repo, so silence. g2 writes the store
# after the same body, and its refusal is the proof that g's timing covers the whole read.
export BIONIC_CLAUDE_HOME="$FAKE_HOME/.claude"
row g  "$WALLS_HOOK" "$R_MEM"    0 SILENT out
row g2 "$WALLS_HOOK" "$R_MEM"    2 "this writes the memory store" err
unset BIONIC_CLAUDE_HOME

# ---------- the self-check ----------

section "3 — self-check: the base hot line on the same input exceeds ${BUDGET}s"
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

# b4: walls.sh:1259-1294 at ac258929 — `_eg_cd_targets`, which took the segments off the front
# of the remainder one at a time, each a pass over all of it. b3 has no line here: its loops
# cost under the budget on this input (see §2c).
cat > "$SANDBOX/hot-b4.sh" <<'SH'
COMMAND=$(jq -r '.tool_input.command')
_eg_cd_targets() {
  local _t="${1:-}" _rest _seg _p
  _EG_CDS=""
  case "$_t" in
    *[\;\&\|$'\n']*) _rest="${_t#*[;&|$'\n']}" ;;
    *) return 0 ;;
  esac
  case "$_rest" in *git*) _rest="${_rest%%git*}" ;; esac
  while [ -n "$_rest" ]; do
    case "$_rest" in
      *[\;\&\|$'\n']*) _seg="${_rest%%[;&|$'\n']*}"; _rest="${_rest#*[;&|$'\n']}" ;;
      *) _seg="$_rest"; _rest="" ;;
    esac
    while [ -n "$_seg" ]; do
      case "$_seg" in
        ' '*|'	'*|'('*|'{'*) _seg="${_seg#?}" ;;
        *) break ;;
      esac
    done
    case "$_seg" in
      'cd'|'cd '*|'cd	'*)
        _p="${_seg#cd}"
        while [ "${_p# }" != "$_p" ]; do _p="${_p# }"; done
        while [ "${_p#	}" != "$_p" ]; do _p="${_p#	}"; done
        while [ "${_p% }" != "$_p" ]; do _p="${_p% }"; done
        case "$_p" in
          '"'*'"') _p="${_p#\"}"; _p="${_p%\"}" ;;
          "'"*"'") _p="${_p#\'}"; _p="${_p%\'}" ;;
        esac
        [ -n "$_p" ] || _p='~'
        _EG_CDS="${_EG_CDS}${_p}"$'\n'
        ;;
    esac
  done
  return 0
}
_eg_cd_targets "$COMMAND"
SH

# g: cmd-class.sh:1134-1178 at ac258929 — `wt_tok`, which copied every character of a quoted
# run into its word one at a time, run once over the command as cmd_write_targets runs it twice.
cat > "$SANDBOX/hot-g.sh" <<'SH'
jq -r '.tool_input.command' | awk '
    function wt_tok(s, W, K,   L, i, c, q, cur, n, st, nx, j, w) {
      L = length(s); q = ""; cur = ""; n = 0; st = 0
      for (i = 1; i <= L; i++) {
        c = substr(s, i, 1)
        if (q != "") {
          if (c == q) q = ""
          else if (c == "\\" && q == "\"" && i < L) { i++; cur = cur substr(s, i, 1) }
          else cur = cur c
          continue
        }
        if (c == "\047" || c == "\"") { q = c; st = 1; continue }
        if (c == "\\") { i++; cur = cur substr(s, i, 1); continue }
        if (c == " " || c == "\t" || c == "\r" || c == "\n") {
          if (cur != "" || st) { W[++n] = cur; K[n] = "W" }
          cur = ""; st = 0; continue
        }
        if (c == ">" || (c == "&" && substr(s, i + 1, 1) == ">") || c == "<") {
          if (c != "&" && cur ~ /^[0-9]+$/ && !st) cur = ""
          if (cur != "" || st) { W[++n] = cur; K[n] = "W" }
          cur = ""; st = 0
          nx = substr(s, i + 1, 1)
          if (c == "<") {
            if (nx == ">") { W[++n] = "<>"; K[n] = "R"; i++; continue }
            if (nx == "&") { i++; while (substr(s, i + 1, 1) ~ /[0-9-]/) i++; W[++n] = "<&"; K[n] = "D"; continue }
            if (nx == "<") { i++; if (substr(s, i + 1, 1) == "<" || substr(s, i + 1, 1) == "-") i++ }
            W[++n] = "<"; K[n] = "I"; continue
          }
          if (c == "&") i++
          nx = substr(s, i + 1, 1)
          if (nx == ">" || nx == "|") { i++; nx = substr(s, i + 1, 1) }
          if (nx == "(") { W[++n] = ">("; K[n] = "I"; continue }
          if (nx == "&" && c != "&") {
            j = i + 2; w = ""
            while (j <= L && substr(s, j, 1) ~ /[0-9]/) { w = w substr(s, j, 1); j++ }
            if (w == "" && substr(s, j, 1) == "-") { w = "-"; j++ }
            if (w != "") { i = j - 1; W[++n] = ">&"; K[n] = "D"; continue }
            i++
          }
          W[++n] = ">"; K[n] = "R"; continue
        }
        cur = cur c
      }
      if (cur != "" || st) { W[++n] = cur; K[n] = "W" }
      return n
    }
    { a[++m] = $0 }
    END { s = a[1]; for (i = 2; i <= m; i++) s = s "\n" a[i]; wt_tok(s, W, K) }'
SH

selfcheck() {  # <id> <snippet> [base the hot line is copied from]
  local base="${3:-7223b594}"
  ht_time /bin/bash "$SANDBOX/$2" "$SANDBOX/in/$1.json" "$SANDBOX" "$CAP"
  echo "hook-timeout: self-check $1 ($base hot line, /bin/bash): ${HT_SECS}s rc=$HT_RC"
  if [ "$OLD_IS_32" = 1 ]; then
    expect_true "$1: the $base hot line exceeds ${BUDGET}s on this input (took ${HT_SECS}s)" \
      over_budget "$HT_SECS"
  else
    advise "$1: the $base hot line on this input" \
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
selfcheck b4 hot-b4.sh ac258929
selfcheck g  hot-g.sh  ac258929

section "3b — §FX: cmd_effects reads g's 200 KB command under ${BUDGET}s (wave-25 T2, D5)"
# The permission answer reads every command the CLI asks about through cmd_effects, so it carries
# the hook budget too. g is the largest input this suite builds: the effects walk tokenises it
# once more than the write-target walk does. The witness is the W line for the redirect AFTER
# the body, which only a walk that reached the end can print, beside the body's own unknown line.
cat > "$SANDBOX/fx-g.sh" <<'SH'
. "$HT_CMD_CLASS_LIB" || exit 1
cmd_effects "$(jq -r '.tool_input.command')" "$PWD"
SH
ht_time /bin/bash "$SANDBOX/fx-g.sh" "$SANDBOX/in/g.json" "$R_MEM" "$CAP"
echo "hook-timeout: §FX cmd_effects on g under /bin/bash ($(ht_version /bin/bash)): ${HT_SECS}s rc=$HT_RC"
expect_true "§FX g [/bin/bash]: under ${BUDGET}s (took ${HT_SECS}s)" under_budget "$HT_SECS"
expect_eq "§FX g [/bin/bash]: exit 0" "0" "$HT_RC"
expect_contains "§FX g: the walk reached the redirect after the body" "W	$R_MEM/out.md" "$HT_OUT"
expect_contains "§FX g: …and read the body itself as unknown" "?	" "$HT_OUT"

section "3c — permission-answer: a 52 KB question answered inside its 10 s registration (wave-25 T4, D1)"
# The carrier is registered on PermissionRequest at timeout 10, and the platform kills a hook at
# its registration: a carrier killed mid-read answers nothing and the dialog waits, the halt it
# exists to remove. So it is timed whole, under /bin/bash 3.2, on e's 52 KB python3 -c body with
# a push on the next line — the command reader walks the body and the reserved table reads
# every segment, the two costs T2 and T3 measured. The witness is the reserved denial, which
# only a reading that got past the body can give; a small question beside it is the baseline.
PA_HOOK="${BIONIC_HOOKS_DIR}/permission-answer.sh"
PA_REG=10
# The lead of a bypass session asks: the carrier answers only in bypass and auto mode (T20).
jq --arg cmd "$(jq -r '.tool_input.command' "$SANDBOX/in/e.json")" \
  '.hook_event_name = "PermissionRequest" | del(.tool_use_id) | .permission_mode = "bypassPermissions"
   | .tool_input.command = ($cmd + "\ngit push origin main") | .permission_suggestions = []' \
  "$SANDBOX/in/e.json" > "$SANDBOX/in/pa52.json"
jq '.tool_input.command = "touch out.txt"' "$SANDBOX/in/pa52.json" > "$SANDBOX/in/pa-small.json"
expect_true "fixture: the carrier's question is at least 52 000 bytes" \
  test "$(jq -r '.tool_input.command' "$SANDBOX/in/pa52.json" | wc -c)" -ge 52000
expect_eq "fixture: /bin/bash is 3.2, the shell the CLI runs the hook under" "1" "$OLD_IS_32"
ht_time /bin/bash "$PA_HOOK" "$SANDBOX/in/pa-small.json" "$R_CHAIN" "$PA_REG"
echo "hook-timeout: permission-answer small question under /bin/bash ($(ht_version /bin/bash)): ${HT_SECS}s rc=$HT_RC"
expect_eq "permission-answer small [/bin/bash]: answered (denied: this unbound session's payload names no scratch)" \
  "deny" "$(printf '%s' "$HT_OUT" | jq -r '.hookSpecificOutput.decision.behavior // "none"' 2>/dev/null)"
ht_time /bin/bash "$PA_HOOK" "$SANDBOX/in/pa52.json" "$R_CHAIN" "$PA_REG"
echo "hook-timeout: permission-answer 52 KB question under /bin/bash ($(ht_version /bin/bash)): ${HT_SECS}s rc=$HT_RC"
expect_true "permission-answer 52 KB [/bin/bash]: under its ${PA_REG}s registration (took ${HT_SECS}s)" \
  awk -v s="$HT_SECS" -v b="$PA_REG" 'BEGIN { exit !(s + 0 < b + 0) }'
expect_eq "permission-answer 52 KB [/bin/bash]: exit 0" "0" "$HT_RC"
expect_contains "permission-answer 52 KB: the reading got past the body to the push — a reserved denial" \
  "leaves the machine" "$(printf '%s' "$HT_OUT" | jq -r '.hookSpecificOutput.decision.message // ""' 2>/dev/null)"

# ---------- the plan-row verbs ----------

VERB_BUDGET=1
section "4 — §VERB: each plan-row verb under ${VERB_BUDGET}s on a 66 KB plan (wave-24 T15; REQ-9 AC-9.7, D14)"
#
# The five verbs are typed by the orchestrator in its own turn, so their wall-clock is the
# turn's. AC-9.7's bound is wall-clock, gated here as written. Load moves it: at load ~8.6 on
# 8 cores the same verbs read 1.01–1.15 s against 0.59–0.67 s unloaded, and CPU time moves with
# it (0.89–1.05 s), so this suite is marked `# runner: solo` rather than loosened. The verb's
# CPU time prints beside its wall time on every row, for the record; it is never asserted.
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
       "rigor: double", "scale: wave", "multi_agent: true", "use_worktree: true", "has_ui: false",
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
  expect_true "§VERB $verb [$VERB_SH]: under ${VERB_BUDGET}s (took ${HT_SECS}s wall, ${HT_CPU}s cpu)" \
    awk -v s="$HT_SECS" -v b="$VERB_BUDGET" 'BEGIN { exit !(s + 0 < b + 0) }'
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
