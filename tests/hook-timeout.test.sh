#!/bin/bash
# tests/hook-timeout.test.sh — HOOKS NEVER TIME OUT (epic-23 wave-24-fixit-1811, T4; REQ-5,
# AC-5.1; spec D6, D7), asserted as a COUNT THAT MUST NOT GROW WITH THE INPUT (wave-35 T11;
# REQ-2 AC-2.2, spec D11, design ledger Δ6).
#
# WHAT IT OWNS. A hook killed by its own `timeout: 10` in hooks.json fails open, and the hooks
# that were killed had a cost that grew faster than their input. This suite drives each input
# below through the real hook TWICE, at a small size and at a large one of the same shape, and
# counts the shell commands the hook executes on each (the hook-latency tracer, below). The two
# counts must be EQUAL. A hook that walks its input in shell steps — a loop over characters,
# lines or segments — executes more commands on the larger input and fails here on any machine,
# at any load. Nothing in this suite reads a clock: a row passes or fails by its count and its
# verdict, never by elapsed time (it used to gate 2 s of wall-clock per input, and was the one
# suite in the tree allowed to).
#
# THE BLIND SPOT, NAMED. One shell operation whose cost grows with its operand is ONE traced
# command at any size: bash 3.2's `${v//pat/}` and `${v/pat/r}` (about matches × length), a
# `${s:i:1}` that walks a UTF-8 string from its start, an append that copies the whole string,
# or one awk that is quadratic inside. A count cannot see any of them, and this suite does not
# claim to. That class is guarded where it lives: tests/hook-latency.test.sh §5 counts the
# classifier's readings by mode, so a command read whole more than once — the shape every
# operand-sized cost above took in these hooks — is a count that moves there.
#
# THE INPUTS ARE SHAPED, NOT JUST SIZED (research-R2): quote density, match offset and
# multibyte length are what made the old costs grow. Small / large:
#   a1  governing-skill  Edit of a 64 KB / 200 KB plan, old_string at 12% of it (~8000 small)
#   a2  governing-skill  the same plans, old_string at 91% (~60000 small)
#   b   bash-walls       a 64 KB / 200 KB python heredoc ending in a literal `git push`
#   b2  bash-walls       the same command ending in `git commit`, from a read-only agent
#   c   bash-walls       a 7.7 K / 200 KB quote-dense command ending in `g'i't commit`
#   d   bash-walls       a 3-segment `&&` chain whose first segment is 8 K / 66 K em dashes
#   e   bash-walls       a 52 KB / 200 KB single-quoted `python3 -c` body of short lines (T22)
#   f   bash-walls       the same body double-quoted, then a newline and `make`
#   g   bash-walls       a 64 KB / 200 KB single-quoted `python3 -c` body, `memory` in the cwd (T28)
#   b3  bash-walls       b's heredoc behind `cd sub && `, committing (T28)
#   b4  bash-walls       b's heredoc behind `cd <absolute repo> && `, committing (T28)
#   k   bash-walls       52 KB / 200 KB of short `"\""` runs, then make (wave-24 critic B1)
# Every row runs under `/bin/bash` (3.2 on macOS, the interpreter ADR-001 pins) AND under the
# newest bash on PATH.
#
# EACH ROW ALSO WITNESSES THE PATH IT COUNTS, at both sizes. A hook that left early would count
# the same at both sizes for the wrong reason, so every row asserts the verdict that can only
# come from the far side of its hot path: the post-edit Tasks fault for a1/a2, protect-main's
# refusal for b, the read-only arm for b2, the evidence gate for c (which the screen reaches
# only through its strip — `git` is not in c's text), the chain deny for d2 and silence for d
# (the long segment ends in a redirect).
#
# THE TRACER is tests/hook-latency.test.sh §4's: a BASH_ENV prelude, sourced by every bash the
# hook starts, that points xtrace at a private fd with a marker in PS4, so the count covers the
# whole process tree's shell commands, builtins included. Where it differs, it differs for a
# count that must come out the same twice. The fd is 87 (hooks use 9). A bash that knows
# BASH_XTRACEFD (4.1 on) traces to that fd and nothing else moves; 3.2 does not, so it keeps
# §4's DEBUG trap, which re-points fd 2 at the trace before each command so a hook's own
# `2>/dev/null` cannot hide what it runs. And the markers are counted as BYTES (`LC_ALL=C`):
# concurrent pipeline stages share the fd, a long line can land in pieces, and a UTF-8 grep
# skipped a marker that followed half an em dash (measured: 1191 or 1193 on one input, by run;
# 144 of 144 runs identical counted as bytes, six at a time).
#
# THE MUTATION CONTROL (§3) proves the equality can fail: a copy of bash-walls.sh and of the
# governing-skill hook, each with one loop over its input planted after the read, counts more
# on the large input of the same pair; and the base hot lines that walked in shell steps (d and
# e at 7223b594, b4 at ac258929), copied verbatim, count more on a larger input while the
# shipped hook counts the same on that pair.
#
# FIXTURE FIDELITY (declared, per .claude/rules/test-harness.md, "Fixture fidelity"):
#   * the engaged project, the payload envelopes and the placeholder-evidence plan — the
#     shapes tests/hook-latency.test.sh and tests/bash-walls.test.sh pin.
#   * the input shapes — research-R2 §3–§4 measured each class on real commands: a plan Edit
#     near the end of a 64 KB file, a python heredoc rewriting a plan through `s.replace`, a
#     7,715-character command holding 1,618 single quotes, a ≥3-segment chain with one 8 K
#     segment in UTF-8. The bytes here are SYNTHESIZED to those measurements, not copied, and
#     the large inputs are the same generators run further.
#   * what each row does NOT pin: the cost of one operation (THE BLIND SPOT above).
#
# ANTI-VACUITY (per .claude/rules/test-harness.md, "Anti-vacuity"): the hooks must exist and
# parse or the suite refuses to run; every fixture's size, offset and quote count is asserted
# before any row reads a count; every count is asserted non-zero beside the equality; every
# row asserts its witness verdict at both sizes; and §3 is the mutation control.
#
# Usage: bash tests/hook-timeout.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"
. "$(dirname "$0")/lib/bound-marker.sh"

WALLS_HOOK="${BIONIC_BASH_WALLS_UNDER_TEST:-${BIONIC_HOOKS_DIR}/bash-walls.sh}"
GS_HOOK="${BIONIC_GOVERNING_SKILL_UNDER_TEST:-${BIONIC_HOOKS_DIR}/canonical-sdlc-governing-skill.sh}"

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

# ---------- the runner and the counter ----------

# The prelude every traced bash sources before its first line (see THE TRACER above). A bash
# that knows BASH_XTRACEFD (4.1 on) traces to fd 87 whatever its fd 2 is; 3.2 does not, so it
# gets hook-latency §4's DEBUG trap, which re-points fd 2 at the trace before each command.
HT_PRELUDE="$SANDBOX/xtrace-prelude.sh"
cat > "$HT_PRELUDE" <<'PRELUDE'
exec 87>>"$HT_TRACE_OUT"
PS4='+|HTCOUNT|${BASH_SOURCE##*/}:${LINENO}| '
if [ "${BASH_VERSINFO[0]}" -ge 5 ] || { [ "${BASH_VERSINFO[0]}" -eq 4 ] && [ "${BASH_VERSINFO[1]}" -ge 1 ]; }; then
  BASH_XTRACEFD=87
else
  exec 2>&87
  set -T
  trap 'exec 2>&87' DEBUG
fi
set -x
PRELUDE
ht_has_xtracefd() {  # <shell> -> 0 when it traces to a named fd (bash 4.1 and later)
  "$1" -c '[ "${BASH_VERSINFO[0]}" -ge 5 ] || { [ "${BASH_VERSINFO[0]}" -eq 4 ] && [ "${BASH_VERSINFO[1]}" -ge 1 ]; }' 2>/dev/null
}

HT_RC=""; HT_OUT=""; HT_ERR=""; HT_N=""
# ht_run <shell> <script> <stdin-file> <cwd> — one untraced run: HT_RC, HT_OUT, HT_ERR.
ht_run() {
  ( cd "$4" && env HOME="$FAKE_HOME" CLAUDE_CODE_SESSION_ID="$SID" CLAUDE_PROJECT_DIR= \
      BIONIC_PLUGINS_DIR="$SANDBOX/no-plugins" LANG=en_US.UTF-8 LC_ALL= LC_CTYPE= \
      "$1" "$2" < "$3" > "$SANDBOX/.out" 2> "$SANDBOX/.err" )
  HT_RC=$?
  HT_OUT=$(cat "$SANDBOX/.out" 2>/dev/null); HT_ERR=$(cat "$SANDBOX/.err" 2>/dev/null)
}
# ht_count <shell> <script> <stdin-file> <cwd> — one traced run: HT_N (commands executed),
# HT_RC, HT_OUT (stdout; stderr goes to the trace with the xtrace).
ht_count() {
  local tr="$SANDBOX/.trace"
  : > "$tr"
  ( cd "$4" && env HOME="$FAKE_HOME" CLAUDE_CODE_SESSION_ID="$SID" CLAUDE_PROJECT_DIR= \
      BIONIC_PLUGINS_DIR="$SANDBOX/no-plugins" LANG=en_US.UTF-8 LC_ALL= LC_CTYPE= \
      HT_TRACE_OUT="$tr" BASH_ENV="$HT_PRELUDE" \
      "$1" "$2" < "$3" > "$SANDBOX/.out" 2>/dev/null )
  HT_RC=$?
  HT_OUT=$(cat "$SANDBOX/.out" 2>/dev/null)
  HT_N=$(LC_ALL=C grep -o '|HTCOUNT|' "$tr" 2>/dev/null | wc -l | tr -d ' ')
  rm -f "$tr"
}
ht_bytes() {  # <payload> -> the bytes of its command, or of the file an Edit names
  local c; c="$(jq -r '.tool_input.command // empty' "$1")"
  if [ -n "$c" ]; then printf '%s' "$c" | wc -c | tr -d ' '; else wc -c < "$(jq -r '.tool_input.file_path' "$1")" | tr -d ' '; fi
}

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
GS_PLAN_L="$R_GS/.bionic/docs/plans/epic-01-demo/bigger.plan.md"

# Every input is generated here, byte for byte, so the sizes and offsets below are facts of
# this run rather than claims about a file somewhere else. `<id>.json` is the small input,
# `<id>-l.json` the large one of the same shape, and §3's reduced pairs are `<id>-r…`.
python3 - "$SANDBOX/in" "$GS_PLAN" "$GS_PLAN_L" "$SID" "$ACTOR" "$R_GS" "$R_PUSH" "$R_AGENT" "$R_COMMIT" "$R_CHAIN" "$R_MEM" <<'PY'
import json, sys
d, plan_s, plan_l, sid, actor, r_gs, r_push, r_agent, r_commit, r_chain, r_mem = sys.argv[1:12]
LARGE = 200000
meta = {}
def put(name, payload):
    json.dump(payload, open("%s/%s.json" % (d, name), "w"))

# -- a: a version-14 plan at step 3 whose Tasks table runs to 64 KB / 200 KB --
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
def plan(path, size, suffix):
    body = head
    i = 0
    rows = {}
    while len(body.encode()) < size:
        i += 1
        rows[i] = len(body.encode())
        body += row(i)
    open(path, "w").write(body)
    total = len(body.encode())
    def nearest(off):
        return min(rows, key=lambda k: abs(rows[k] - off))
    for name, frac in (("a1", 0.122), ("a2", 0.912)):
        k = nearest(int(total * frac))
        old = row(k).rstrip("\n")
        new = old.replace("| pending |", "| doing |")
        put(name + suffix, {"session_id": sid, "tool_name": "Edit",
            "tool_input": {"file_path": path, "old_string": old, "new_string": new,
                           "replace_all": False}})
        meta[name + suffix] = rows[k]
    meta["plan" + suffix] = total
plan(plan_s, 65790, "")
plan(plan_l, LARGE, "-l")

def bash_payload(cwd, cmd, agent=False):
    p = {"session_id": sid, "cwd": cwd, "hook_event_name": "PreToolUse", "tool_name": "Bash",
         "tool_input": {"command": cmd}, "tool_use_id": "toolu_hook_timeout"}
    if agent:
        p["agent_id"] = actor
        p["agent_type"] = "bionic:test-runner"
    return p

# -- b: a python heredoc rewriting a plan through s.replace('''…''', '''…''') --
def heredoc(size):
    lines = ["python3 - <<'PY'", "p = '.bionic/docs/plans/active.md'", "s = open(p).read()"]
    n = 0
    while len("\n".join(lines)) < size:
        n += 1
        lines.append("s = s.replace('''| T%d | 4 | build | the \"old\" reader — pending |''', '''| T%d | 4 | build | the \"new\" reader — landed |''')" % (n, n))
    lines += ["open(p, 'w').write(s)", "PY"]
    return "\n".join(lines)

# -- c: single-quoted words, one obfuscated commit at the end --
def quoted(size):
    cmd = "printf '%s\\n'"
    k = 0
    while len(cmd) < size:
        k += 1
        cmd += " 'w%04d'" % k
    return cmd + " && g'i't commit -m x"

# -- d: three && segments; the first is em dashes ending in a redirect --
def dash_seg(n):
    return 'printf %s "' + ("—" * n) + '" > out.txt'

# -- e, f, g: a python3 -c body, never a heredoc, so nothing strips it before the classifier
#    (T22). Many short lines, not a few long ones: cmd_class's line loop cost lines × length.
def pybody(size, measure_bytes):
    b = ["import re", "p = \".bionic/docs/plans/active.md\"", "s = open(p).read()"]
    n = 0
    while (len("\n".join(b).encode()) if measure_bytes else len("\n".join(b))) < size:
        n += 1
        b.append("s = s.replace(\"T%d — a\", \"T%d — b\")" % (n, n))
    b.append("open(p, \"w\").write(s)")
    return "\n".join(b)

# -- k: many SHORT double-quoted runs, each holding a backslash, then `make` (wave-24 critic
#    Addendum 2 B1). The quote-end scan paid per run on this shape; e/f are ONE long run. --
def kq(runs):
    return "echo " + " ".join(['"\\""'] * runs)

for suffix, hd_size, c_size, d_n, e_size, k_runs, g_size in (
        ("",   65400,  7680,  8000,  51700, 10400, 64000),
        ("-l", LARGE,  LARGE, 66700, LARGE, 40000, LARGE)):
    h = heredoc(hd_size)
    put("b" + suffix, bash_payload(r_push, h + "\ngit push origin main"))
    put("b2" + suffix, bash_payload(r_agent, h + "\ngit commit -m 'T4: rewrite'", agent=True))
    meta["b" + suffix] = len(h + "\ngit push origin main")
    # b3, b4: b's heredoc behind a leading cd, then a commit. b3's cd is relative, so only the
    # leading-cd read runs; b4's names an absolute directory, so the scan for later cds runs
    # too. The evidence gate's placeholder refusal can only come after both (T28).
    put("b3" + suffix, bash_payload(r_commit, "cd sub && " + h + "\ngit commit -m x"))
    put("b4" + suffix, bash_payload(r_commit, "cd " + r_commit + " && " + h + "\ngit commit -m x"))
    meta["b3" + suffix] = len("cd sub && " + h + "\ngit commit -m x")
    c = quoted(c_size)
    put("c" + suffix, bash_payload(r_commit, c))
    meta["c" + suffix] = len(c)
    meta["c_quotes" + suffix] = c.count("'")
    seg = dash_seg(d_n)
    put("d" + suffix, bash_payload(r_chain, seg + " && echo two && echo three"))
    # d2: the same long segment, then a build segment — the witness that d's silence is the
    # hook finishing its walk rather than leaving early.
    put("d2" + suffix, bash_payload(r_chain, seg + " && make && echo three"))
    meta["d_seg_chars" + suffix] = len(seg)
    body = pybody(e_size, False)
    sq = "python3 -c '" + body + "'"
    dq = "python3 -c \"" + body.replace("\"", "'") + "\""
    put("e" + suffix, bash_payload(r_chain, sq))
    # e2, f: `make` on the next line — a build deny can only come from the segment after it.
    put("e2" + suffix, bash_payload(r_chain, sq + "\nmake"))
    put("f" + suffix, bash_payload(r_chain, dq + "\nmake"))
    meta["e_bytes" + suffix] = len(sq.encode())
    meta["e_lines" + suffix] = body.count("\n") + 1
    meta["e_inner_quotes" + suffix] = body.count("'")
    k = kq(k_runs)
    put("k" + suffix, bash_payload(r_chain, k + "\nmake"))
    meta["k" + suffix] = len(k)
    # g, g2: run where the cwd holds `memory` and the command does not. g writes inside the
    # repo, so silence; g2 writes the store after the same body, and the memory wall's refusal
    # can only come from a tokenizer that walked past it (T28).
    gbody = pybody(g_size, True)
    gq = "python3 -c '" + gbody + "'"
    put("g" + suffix, bash_payload(r_mem, gq + " > out.md"))
    put("g2" + suffix, bash_payload(r_mem, gq + " > ~/.claude/projects/-x/memory/n.md"))
    meta["g_bytes" + suffix] = len(gq.encode())
    meta["g_memory" + suffix] = (gq + " > out.md").count("memory")
    meta["g_inner_quotes" + suffix] = gbody.count("'")

# -- §3's reduced pairs: the shapes d, e and b4 at sizes whose traces stay small, because the
#    base hot lines print their whole remainder on every step of the walk they take --
for suffix, d_n, e_size, hd_size in (("-rs", 200, 2000, 2000), ("-rl", 800, 8000, 8000)):
    put("d" + suffix, bash_payload(r_chain, dash_seg(d_n) + " && echo two && echo three"))
    put("e" + suffix, bash_payload(r_chain, "python3 -c '" + pybody(e_size, False) + "'"))
    put("b4" + suffix, bash_payload(r_commit, "cd " + r_commit + " && " + heredoc(hd_size) + "\ngit commit -m x"))

# -- §3c's pair: the carrier reads a question of at most 65 536 bytes and refuses a larger one
#    unread ("command too large to read", hooks/permission-answer.sh), so its pair is 16 KB and
#    the largest question it reads, each a body with a push on the next line --
for name, size in (("pa", 16000), ("pa-l", 65400)):
    q = "python3 -c '" + pybody(size, True) + "'\ngit push origin main"
    put(name, {"session_id": sid, "cwd": r_chain, "hook_event_name": "PermissionRequest",
               "tool_name": "Bash", "tool_input": {"command": q},
               "permission_mode": "bypassPermissions", "permission_suggestions": []})
    meta[name] = len(q.encode())

json.dump(meta, open(d + "/meta.json", "w"))
PY

meta() { jq -r ".[\"$1\"]" "$SANDBOX/in/meta.json"; }
expect_true "fixture: the small plan is at least 64 KB" test "$(wc -c < "$GS_PLAN")" -ge 65536
expect_true "fixture: the large plan is at least 200 000 bytes" test "$(wc -c < "$GS_PLAN_L")" -ge 200000
expect_true "fixture: a1's old_string sits within 1 KB of offset 8000" \
  awk -v o="$(meta a1)" 'BEGIN { exit !(o > 7000 && o < 9000) }'
expect_true "fixture: a2's old_string sits within 1 KB of offset 60000" \
  awk -v o="$(meta a2)" 'BEGIN { exit !(o > 59000 && o < 61000) }'
expect_true "fixture: a1-l and a2-l sit at the same fractions of the large plan (12%, 91%)" \
  awk -v a="$(meta a1-l)" -v b="$(meta a2-l)" -v n="$(meta plan-l)" \
  'BEGIN { exit !(a > 0.11 * n && a < 0.13 * n && b > 0.90 * n && b < 0.92 * n) }'
expect_true "fixture: b's command is at least 64 000 characters" test "$(meta b)" -ge 64000
expect_true "fixture: c's command is ~7.7 K with over 1 500 single quotes" \
  awk -v n="$(meta c)" -v q="$(meta c_quotes)" 'BEGIN { exit !(n >= 7600 && n <= 7900 && q >= 1500) }'
expect_true "fixture: d's long segment is at least 8 000 characters" test "$(meta d_seg_chars)" -ge 8000
expect_true "fixture: e's command is at least 50 000 bytes" test "$(meta e_bytes)" -ge 50000
expect_true "fixture: e's body is at least 1 000 lines" test "$(meta e_lines)" -ge 1000
expect_eq "fixture: e's body holds no single quote, so it is one quoted word" "0" "$(meta e_inner_quotes)"
expect_true "fixture: b3's command is at least 64 000 characters" test "$(meta b3)" -ge 64000
expect_true "fixture: k's command is at least 52 000 characters" test "$(meta k)" -ge 52000
expect_true "fixture: g's small command is at least 64 000 bytes" test "$(meta g_bytes)" -ge 64000
for _m in b-l b3-l c-l k-l; do
  expect_true "fixture: $_m's command is at least 200 000 characters" test "$(meta "$_m")" -ge 200000
done
expect_true "fixture: d-l's long segment is at least 200 000 bytes" \
  test "$(jq -r '.tool_input.command' "$SANDBOX/in/d-l.json" | wc -c)" -ge 200000
expect_true "fixture: c-l keeps c's quote density (over one quote in six characters)" \
  awk -v n="$(meta c-l)" -v q="$(meta c_quotes-l)" 'BEGIN { exit !(q * 6 > n) }'
expect_true "fixture: e-l's command is at least 200 000 bytes, at least 3 000 lines" \
  awk -v n="$(meta e_bytes-l)" -v l="$(meta e_lines-l)" 'BEGIN { exit !(n >= 200000 && l >= 3000) }'
expect_true "fixture: g-l's command is at least 200 000 bytes" test "$(meta g_bytes-l)" -ge 200000
for _m in "" -l; do
  expect_eq "fixture: e$_m's body holds no single quote, so it is one quoted word" "0" "$(meta "e_inner_quotes$_m")"
  expect_eq "fixture: g$_m's body holds no single quote, so it is one quoted word" "0" "$(meta "g_inner_quotes$_m")"
  expect_eq "fixture: g$_m's command never says memory — the cwd is what screens it in" "0" "$(meta "g_memory$_m")"
done
expect_contains "fixture: …and g's cwd does" "memory" "$(jq -r .cwd "$SANDBOX/in/g.json")"

# ---------- the rows ----------

# pair <label> <shell> <script> <cwd> <small stdin> <large stdin> <want rc> <witness> <chan>
# Runs the script untraced at both sizes for its exit and its witness, then traced at both for
# the count, and asserts the two counts equal. A witness of SILENT asserts an empty stdout: the
# verdict is "nothing to say". PAIR_NS / PAIR_NL hold the two counts for §3's controls.
PAIR_NS=""; PAIR_NL=""
pair() {
  local label="$1" sh="$2" script="$3" cwd="$4" small="$5" large="$6" want_rc="$7" witness="$8" chan="$9"
  local size inp got n_s="" n_l=""
  for size in small large; do
    if [ "$size" = small ]; then inp="$small"; else inp="$large"; fi
    rm -f "$cwd/.bionic/tmp/farm-out.state"
    ht_run "$sh" "$script" "$inp" "$cwd"
    expect_eq "$label, $size: exit $want_rc" "$want_rc" "$HT_RC"
    if [ "$chan" = out ]; then got="$HT_OUT"; else got="$HT_ERR"; fi
    if [ "$witness" = SILENT ]; then
      expect_eq "$label, $size: the hot path was reached and answered — silence, with its pair beside it" "" "$got"
    else
      expect_contains "$label, $size: the hot path was reached — $witness" "$witness" "$got"
    fi
    rm -f "$cwd/.bionic/tmp/farm-out.state"
    ht_count "$sh" "$script" "$inp" "$cwd"
    expect_eq "$label, $size: the traced run took the same exit" "$want_rc" "$HT_RC"
    if [ "$size" = small ]; then n_s="$HT_N"; else n_l="$HT_N"; fi
  done
  PAIR_NS="$n_s"; PAIR_NL="$n_l"
  echo "hook-timeout: $label: $n_s commands at $(ht_bytes "$small") bytes, $n_l at $(ht_bytes "$large") bytes"
  expect_true "$label: the tracer counted the run (${n_s:-0} commands)" test "${n_s:-0}" -gt 0
}
# row <id> <hook> <repo> <expected exit> <witness substring> <channel: out|err>
row() {
  local id="$1" hook="$2" repo="$3" want_rc="$4" witness="$5" chan="$6" sh
  for sh in $SHELLS; do
    pair "$id [$sh]" "$sh" "$hook" "$repo" "$SANDBOX/in/$id.json" "$SANDBOX/in/$id-l.json" "$want_rc" "$witness" "$chan"
    expect_eq "$id [$sh]: the hook runs as many commands on the large input as on the small one" "$PAIR_NS" "$PAIR_NL"
  done
}

section "1 — governing-skill: a 64 KB / 200 KB plan Edit near its start and near its end"
echo "hook-timeout: shells = $SHELLS"
row a1 "$GS_HOOK" "$R_GS" 2 "status doing" err
row a2 "$GS_HOOK" "$R_GS" 2 "status doing" err

section "2 — bash-walls: the heredoc, the quote-dense command, the long chain segment"
row b  "$WALLS_HOOK" "$R_PUSH"   2 "main is a protected branch here" err
row b2 "$WALLS_HOOK" "$R_AGENT"  2 "a read-only role never commits" err
row c  "$WALLS_HOOK" "$R_COMMIT" 2 "evidence line is a placeholder" err
# d: the chain tier-2 nudge that used to witness this row is retired (wave-24 T11, AC-7.7), so a
# chain with no tier-1 segment answers with silence. Silence alone would read the same if the
# hook had left early, so d2 runs the same long first segment with a build segment behind it:
# its deny (class=chain) can only come from a walk that got past the long segment and read the
# segments after it. d is the input being counted; d2 is the proof the count covers the walk.
row d  "$WALLS_HOOK" "$R_CHAIN"  0 SILENT out
row d2 "$WALLS_HOOK" "$R_CHAIN"  0 "chain-class command" out

section "2b — bash-walls: a quoted python3 -c body the classifier reads whole (T22)"
# e is the input being counted: class none, so silence. e2 and f put `make` on the line after
# the body, and their build deny can only come from a reading that walked past it.
row e  "$WALLS_HOOK" "$R_CHAIN"  0 SILENT out
row e2 "$WALLS_HOOK" "$R_CHAIN"  0 "farm-out [deny] class=build" err
row f  "$WALLS_HOOK" "$R_CHAIN"  0 "farm-out [deny] class=build" err
row k  "$WALLS_HOOK" "$R_CHAIN"  0 "farm-out [deny] class=build" err

section "2c — bash-walls: a leading cd before the heredoc, and a body read for its writes (T28)"
# b3 and b4 are b behind a `cd`. Their placeholder refusal is the evidence gate judging the
# commit, which it does only after reading where the `cd` went.
row b3 "$WALLS_HOOK" "$R_COMMIT" 2 "evidence line is a placeholder" err
row b4 "$WALLS_HOOK" "$R_COMMIT" 2 "evidence line is a placeholder" err
# g is the input being counted: it writes out.md in the repo, so silence. g2 writes the store
# after the same body, and its refusal is the proof that g's count covers the whole read.
export BIONIC_CLAUDE_HOME="$FAKE_HOME/.claude"
row g  "$WALLS_HOOK" "$R_MEM"    0 SILENT out
row g2 "$WALLS_HOOK" "$R_MEM"    2 "this writes the memory store" err
unset BIONIC_CLAUDE_HOME

# ---------- the mutation control ----------

section "3 — self-check: a hook that walks its input counts more on the large input"
#
# (1) A PLANTED WALK, on the real row inputs. One loop over the input, 4 KB a step, inserted
# just after each hook reads it: on stdin for bash-walls, on the plan file's text for the
# governing-skill hook (a1's input is the plan, not the payload). The copy runs from a `hooks/`
# directory beside the real payload, so the loader resolves exactly as it does for the hook.
# Each mutant must still reach its far side (the witness, at both sizes) — and count more.
HT_MUT="$SANDBOX/mut"
mkdir -p "$HT_MUT/hooks"
_ht_root="$(cd "$(dirname "$WALLS_HOOK")/.." && pwd -P)"
[ -d "$_ht_root/payload" ] && ln -s "$_ht_root/payload" "$HT_MUT/payload"
[ -d "$_ht_root/scripts" ] && ln -s "$_ht_root/scripts" "$HT_MUT/scripts"
anchor insert hooks/bash-walls.sh '[ -n "$BIONIC_INPUT" ] || exit 0' \
  '_ht_w="$BIONIC_INPUT"; while [ "${#_ht_w}" -gt 4096 ]; do _ht_w="${_ht_w:4096}"; done' \
  "$HT_MUT/hooks/bash-walls.sh"
anchor insert hooks/canonical-sdlc-governing-skill.sh 'CONTENT=$(printf' \
  '_ht_w="$CONTENT"; while [ "${#_ht_w}" -gt 4096 ]; do _ht_w="${_ht_w:4096}"; done' \
  "$HT_MUT/hooks/canonical-sdlc-governing-skill.sh"
for _m in bash-walls canonical-sdlc-governing-skill; do
  expect_eq "self-check: the $_m copy parses and differs from the hook by the one planted line" "0 1" \
    "$(/bin/bash -n "$HT_MUT/hooks/$_m.sh" >/dev/null 2>&1; echo $?) $(diff "${BIONIC_HOOKS_DIR}/$_m.sh" "$HT_MUT/hooks/$_m.sh" | grep -c '^>')"
done
pair "self-check b, planted walk [/bin/bash]" /bin/bash "$HT_MUT/hooks/bash-walls.sh" "$R_PUSH" \
  "$SANDBOX/in/b.json" "$SANDBOX/in/b-l.json" 2 "main is a protected branch here" err
expect_true "self-check b: the planted walk counts more on the large input (${PAIR_NS} then ${PAIR_NL}): row b would go red" \
  test "${PAIR_NL:-0}" -gt "${PAIR_NS:-0}"
pair "self-check a2, planted walk [/bin/bash]" /bin/bash "$HT_MUT/hooks/canonical-sdlc-governing-skill.sh" "$R_GS" \
  "$SANDBOX/in/a2.json" "$SANDBOX/in/a2-l.json" 2 "status doing" err
expect_true "self-check a2: the planted walk counts more on the large input (${PAIR_NS} then ${PAIR_NL}): row a2 would go red" \
  test "${PAIR_NL:-0}" -gt "${PAIR_NS:-0}"

# (2) THE BASE HOT LINES THAT WALKED. Each snippet is the hot line as it stood at its base,
# copied verbatim, fed a reduced pair of its row's shape (the full inputs trace to hundreds of
# MB, because each step prints the remainder it walks). Its count must grow — and the shipped
# hook, fed the same pair, must count the same on both. The base lines of a1, a2, b, c and g
# were single operations whose cost grew with the operand (THE BLIND SPOT): a count cannot
# see them, so they are not here.

# d: walls.sh:4662-4710 — `_chain_seg_split`'s character walk over the first segment. (That
# function is deleted at T11; the line is what the self-check counts, as it stood at 7223b594.)
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
# of the remainder one at a time, each a pass over all of it.
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

hot_line() {  # <id> <snippet> <base> <repo> <want rc> <witness> <chan> — the base line grows, the hook does not
  local id="$1" snip="$2" base="$3" n_s n_l
  ht_count /bin/bash "$SANDBOX/$snip" "$SANDBOX/in/$id-rs.json" "$SANDBOX"; n_s="$HT_N"
  ht_count /bin/bash "$SANDBOX/$snip" "$SANDBOX/in/$id-rl.json" "$SANDBOX"; n_l="$HT_N"
  echo "hook-timeout: self-check $id ($base hot line, /bin/bash): $n_s commands at $(ht_bytes "$SANDBOX/in/$id-rs.json") bytes, $n_l at $(ht_bytes "$SANDBOX/in/$id-rl.json")"
  expect_true "self-check $id: the $base hot line counted its run (${n_s:-0} commands)" test "${n_s:-0}" -gt 0
  expect_true "self-check $id: …and counts more on the larger input (${n_s} then ${n_l}): it walks, and this count sees it" \
    test "${n_l:-0}" -gt "${n_s:-0}"
  pair "self-check $id, the shipped hook on the same pair [/bin/bash]" /bin/bash "$WALLS_HOOK" "$4" \
    "$SANDBOX/in/$id-rs.json" "$SANDBOX/in/$id-rl.json" "$5" "$6" "$7"
  expect_eq "self-check $id: …while the shipped hook counts the same on that pair" "$PAIR_NS" "$PAIR_NL"
}
hot_line d  hot-d.sh  7223b594 "$R_CHAIN"  0 SILENT out
hot_line e  hot-e.sh  7223b594 "$R_CHAIN"  0 SILENT out
hot_line b4 hot-b4.sh ac258929 "$R_COMMIT" 2 "evidence line is a placeholder" err

section "3b — §FX: cmd_effects reads g's command in as many commands at 200 KB as at 64 KB (wave-25 T2, D5)"
# The permission answer reads every command the CLI asks about through cmd_effects, so it carries
# the hook budget too. g is the largest input this suite builds: the effects walk tokenises it
# once more than the write-target walk does. The witness is the W line for the redirect AFTER
# the body, which only a walk that reached the end can print, beside the body's own unknown line.
cat > "$SANDBOX/fx-g.sh" <<'SH'
. "$HT_CMD_CLASS_LIB" || exit 1
cmd_effects "$(jq -r '.tool_input.command')" "$PWD"
SH
for _sz in "" -l; do
  ht_run /bin/bash "$SANDBOX/fx-g.sh" "$SANDBOX/in/g$_sz.json" "$R_MEM"
  expect_eq "§FX g$_sz [/bin/bash]: exit 0" "0" "$HT_RC"
  expect_contains "§FX g$_sz: the walk reached the redirect after the body" "W	$R_MEM/out.md" "$HT_OUT"
  expect_contains "§FX g$_sz: …and read the body itself as unknown" "?	" "$HT_OUT"
done
ht_count /bin/bash "$SANDBOX/fx-g.sh" "$SANDBOX/in/g.json" "$R_MEM";   FX_NS="$HT_N"
ht_count /bin/bash "$SANDBOX/fx-g.sh" "$SANDBOX/in/g-l.json" "$R_MEM"; FX_NL="$HT_N"
echo "hook-timeout: §FX cmd_effects on g under /bin/bash ($(ht_version /bin/bash)): $FX_NS commands at 64 KB, $FX_NL at 200 KB"
expect_true "§FX g [/bin/bash]: the tracer counted the walk (${FX_NS:-0} commands)" test "${FX_NS:-0}" -gt 0
expect_eq "§FX g [/bin/bash]: cmd_effects runs as many commands at 200 KB as at 64 KB" "$FX_NS" "$FX_NL"

section "3c — permission-answer: a 16 KB and a 64 KB question answered in as many commands (wave-25 T4, D1)"
# The carrier is registered on PermissionRequest at timeout 10, and the platform kills a hook at
# its registration: a carrier killed mid-read answers nothing and the dialog waits, the halt it
# exists to remove. So it is counted whole, under /bin/bash 3.2, on e's python3 -c body with a
# push on the next line — the command reader walks the body and the reserved table reads every
# segment, the two costs T2 and T3 measured. The large question is the largest the carrier
# reads at all: past 65 536 bytes it denies unread, a different path, so 200 KB cannot be its
# pair. The witness is the reserved denial, which only a reading that got past the body can
# give; a small question beside it is the baseline.
PA_HOOK="${BIONIC_HOOKS_DIR}/permission-answer.sh"
jq '.tool_input.command = "touch out.txt"' "$SANDBOX/in/pa.json" > "$SANDBOX/in/pa-small.json"
expect_true "fixture: the carrier's small question is at least 16 000 bytes" test "$(meta pa)" -ge 16000
expect_true "fixture: …and the large one between 64 000 and the 65 536 it reads" \
  awk -v n="$(meta pa-l)" 'BEGIN { exit !(n >= 64000 && n <= 65536) }'
expect_eq "fixture: /bin/bash is 3.2, the shell the CLI runs the hook under" "1" "$OLD_IS_32"
ht_run /bin/bash "$PA_HOOK" "$SANDBOX/in/pa-small.json" "$R_CHAIN"
expect_eq "permission-answer small [/bin/bash]: answered (denied: this unbound session's payload names no scratch)" \
  "deny" "$(printf '%s' "$HT_OUT" | jq -r '.hookSpecificOutput.decision.behavior // "none"' 2>/dev/null)"
PA_NS=""; PA_NL=""
for _sz in "" -l; do
  ht_run /bin/bash "$PA_HOOK" "$SANDBOX/in/pa$_sz.json" "$R_CHAIN"
  expect_eq "permission-answer pa$_sz [/bin/bash]: exit 0" "0" "$HT_RC"
  expect_contains "permission-answer pa$_sz: the reading got past the body to the push — a reserved denial" \
    "leaves the machine" "$(printf '%s' "$HT_OUT" | jq -r '.hookSpecificOutput.decision.message // ""' 2>/dev/null)"
  ht_count /bin/bash "$PA_HOOK" "$SANDBOX/in/pa$_sz.json" "$R_CHAIN"
  expect_eq "permission-answer pa$_sz [/bin/bash]: the traced run took the same exit" "0" "$HT_RC"
  if [ -z "$_sz" ]; then PA_NS="$HT_N"; else PA_NL="$HT_N"; fi
done
echo "hook-timeout: permission-answer under /bin/bash ($(ht_version /bin/bash)): $PA_NS commands at $(meta pa) bytes, $PA_NL at $(meta pa-l)"
expect_true "permission-answer [/bin/bash]: the tracer counted the carrier (${PA_NS:-0} commands)" test "${PA_NS:-0}" -gt 0
expect_eq "permission-answer [/bin/bash]: the carrier answers in as many commands at 64 KB as at 16 KB" "$PA_NS" "$PA_NL"

# ---------- the plan-row verbs ----------

section "4 — §VERB: each plan-row verb runs as many commands on a 200 KB plan as on a 66 KB one (wave-24 T15; REQ-9 AC-9.7, D14)"
#
# The five verbs are typed by the orchestrator in its own turn, so their cost is the turn's.
# Each runs the whole task-add transaction — the projection through units.sh, a dry commit
# through the real bash-walls.sh, the checksum and the swap — on a plan the size of this wave's
# own (66 KB: 25 task rows, 40 matrix rows, a 30-row dispatch ledger, the rest task detail),
# and again on the same plan with its task detail grown to 200 KB. The witness is the verb's own
# success line beside exit 0, which it prints only after the dry commit admitted the copy and
# the copy was swapped in, at both sizes. A verb changes the plan, so each runs once per size,
# traced, from that size's pristine copy, and is witnessed on its stdout.
POKER_SH="${BIONIC_HOOKS_DIR}/session-poker.sh"
/bin/bash -n "$POKER_SH" || { echo "hook-timeout: $POKER_SH does not parse — suite refuses to run"; exit 1; }
R_VERB="$(mk_repo verb)"
VERB_PLAN="$R_VERB/.bionic/docs/plans/epic-01-demo/wave-01-verb.plan.md"
mkdir -p "$R_VERB/.bionic/docs/specs/epic-01-demo"
printf '# requirements\n' > "$R_VERB/.bionic/docs/specs/epic-01-demo/wave-01-verb.requirements.md"
printf '# spec\n' > "$R_VERB/.bionic/docs/specs/epic-01-demo/wave-01-verb.spec.md"
python3 - "$SANDBOX/verb-plan" <<'PY'
import sys
dest = sys.argv[1]
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
for suffix, size in (("", 66000), ("-l", 200000)):
    detail = ["", "## Task detail", ""]
    k = 0
    while len((body + "\n".join(detail)).encode()) < size:
        k += 1
        detail.append("### T%d — detail" % (k % 24 + 1))
        detail.append("The reader walks the table once and answers every question from that walk; "
                      "the walk is fence-aware and keyed on the header, so a renamed column is a fault "
                      "rather than a silent shift — paragraph %d." % k)
        detail.append("")
    # The detail sits between the table and the matrix, as a real plan carries it.
    cut = body.index("\n## Verification Matrix")
    open(dest + suffix + ".pristine", "w").write(body[:cut] + "\n".join(detail) + body[cut:])
PY
cp "$SANDBOX/verb-plan.pristine" "$VERB_PLAN"
bound_marker "$R_VERB" "$SID" "$VERB_PLAN"
: > "$SANDBOX/in/empty"
expect_true "fixture: the small verb plan is at least 66 000 bytes" test "$(wc -c < "$SANDBOX/verb-plan.pristine")" -ge 66000
expect_true "fixture: the large verb plan is at least 200 000 bytes" test "$(wc -c < "$SANDBOX/verb-plan-l.pristine")" -ge 200000
expect_eq "fixture: the two verb plans carry the same rows above the detail" \
  "$(grep -c '^|' "$SANDBOX/verb-plan.pristine")" "$(grep -c '^|' "$SANDBOX/verb-plan-l.pristine")"

# THE VERBS ARE COUNTED UNDER A BASH THAT TRACES TO ITS OWN FD (4.1 on). bash 3.2 writes xtrace
# on fd 2, so a verb that reads a check's stderr through `$( … 2>&1)` reads the trace with it
# and refuses (measured: task-set under 3.2, traced, refused the copy it admits untraced). Under
# 3.2 each verb is run untraced and witnessed; the count is taken where the trace is invisible.
VERB_N=""; VERB_COUNTED=0
verb_row() {  # <n> <verb> <args…> — one verb under VERB_SH on the plan VERB_SZ names
  local n="$1" verb="$2"; shift 2
  { printf 'exec "$BASH" %q' "$POKER_SH"; printf ' %q' "$verb" "$@"; printf '\n'; } > "$SANDBOX/verb-$n.sh"
  if ht_has_xtracefd "$VERB_SH"; then
    ht_count "$VERB_SH" "$SANDBOX/verb-$n.sh" "$SANDBOX/in/empty" "$R_VERB"
    VERB_N="$VERB_N $verb=$HT_N"
  else
    ht_run "$VERB_SH" "$SANDBOX/verb-$n.sh" "$SANDBOX/in/empty" "$R_VERB"; HT_N="(untraced)"
  fi
  echo "hook-timeout: §VERB $verb under $VERB_SH ($(ht_version "$VERB_SH")), ${VERB_SZ:-small} plan: $HT_N commands rc=$HT_RC"
  expect_eq "§VERB $verb [$VERB_SH] ${VERB_SZ:-small}: exit 0" "0" "$HT_RC"
  expect_contains "§VERB $verb [$VERB_SH] ${VERB_SZ:-small}: the transaction ran to its swap — its success line" \
    "poker: $verb — " "$HT_OUT"
}
for VERB_SH in $SHELLS; do
  VERB_COUNTS=""
  for VERB_SZ in "" -l; do
    cp "$SANDBOX/verb-plan$VERB_SZ.pristine" "$VERB_PLAN"
    VERB_N=""
    verb_row 1 current 4
    verb_row 2 task-set T25 size=45
    verb_row 3 step-line T24 'merge checked' --append
    verb_row 4 ledger-add T31 'agent=implementor (w-T31)' dispatched=2026-10-03T12:00Z
    verb_row 5 ledger-set T1 'notes=batch 1, re-run'
    expect_contains "§VERB [$VERB_SH] ${VERB_SZ:-small}: the plan carries task-set's cell" "| 45 | REQ-1 |" "$(grep -F '| T25 |' "$VERB_PLAN")"
    expect_contains "§VERB [$VERB_SH] ${VERB_SZ:-small}: …and current's move" "current: 4" "$(grep -x 'current: 4' "$VERB_PLAN")"
    VERB_COUNTS="$VERB_COUNTS|$VERB_N"
  done
  ht_has_xtracefd "$VERB_SH" || continue
  VERB_COUNTED=$((VERB_COUNTED + 1))
  _vs="${VERB_COUNTS#|}"; _vs="${_vs%%|*}"; _vl="${VERB_COUNTS##*|}"
  expect_true "§VERB [$VERB_SH]: the tracer counted the verbs ($_vs)" test -n "$(printf '%s' "$_vs" | grep -E '=[1-9]')"
  expect_eq "§VERB [$VERB_SH]: each verb runs as many commands on the 200 KB plan as on the 66 KB one" "$_vs" "$_vl"
done
expect_true "§VERB: a bash that traces to its own fd was on PATH, so the verbs were counted (bash 4.1 or later; $SHELLS)" \
  test "$VERB_COUNTED" -gt 0

finish
