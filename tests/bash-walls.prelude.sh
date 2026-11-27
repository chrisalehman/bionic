# tests/bash-walls.prelude.sh — the shared half of the two bash-walls suites
# (wave-30 T9, D8). NOT A SUITE: the name does not end in `.test.sh`, so the roster glob
# never launches it.
#
# tests/bash-walls.test.sh (the composition and every wall's arms) and
# tests/bash-walls-egd.test.sh (the §EG-DERIVE sections, held out of the parallel batch
# because they carry wall-clock bounds) each source this file. It holds what both read: the
# jq and hook guards, the sandbox, the session constants, the fixture repository and payload
# builders, the hook runner and its readers, and §EG-6's plan writer and gate drive that
# §EG-DERIVE builds on (moved here, not copied).
#
# A SUITE SETS `HOOK=` BEFORE SOURCING THIS FILE, in its own text (so the impact map reaches
# the hook from each suite), and sources it BEFORE tests/lib/assert.sh: assert.sh derives, at
# its own load, every `expect_*` the suite calls and refuses one that is neither defined yet
# nor defined in that file. Nothing below calls `ok`/`no`/`section` at load time.

command -v jq >/dev/null 2>&1 || { echo "bash-walls: jq absent — suite cannot run"; exit 1; }

# NOT VACUOUS. Most assertions below read a refusal off a stream, but several read
# SILENCE — and a HOOK path that names nothing is silent too, at exit 127. A suite whose
# seam is wrong must stop rather than report the walls behaving.
[ -f "$HOOK" ] || { echo "bash-walls: no hook at $HOOK — suite refuses to run"; exit 1; }
bash -n "$HOOK" || { echo "bash-walls: $HOOK does not parse — suite refuses to run"; exit 1; }

# `cd ""` succeeds where it stands, so a mktemp that failed would name the suite's own directory as the sandbox, and
# the cleanup below would remove it: the sandbox is made, or the suite stops here.
SANDBOX="$(d="$(mktemp -d "${TMPDIR:-/tmp}/bash-walls-test.XXXXXX")" && cd "$d" && pwd -P)" \
  || { echo "bash-walls: no sandbox under ${TMPDIR:-/tmp}" >&2; exit 1; }
cleanup(){ rm -rf "$SANDBOX"; }
trap cleanup EXIT

SID="5f4e3d2c-1b0a-4998-8877-665544332211"
ACTOR="at23writer-9f8e7d6c5b4a3210"
FAKE_HOME="$SANDBOX/home"
mkdir -p "$FAKE_HOME"

# A helper is found beside this file, wherever the suite that sources it stands; one that does not load stops the suite.
BW_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
[ -r "$BW_HERE/lib/plan-fixture.sh" ] && . "$BW_HERE/lib/plan-fixture.sh" \
  || { echo "bash-walls.prelude.sh: cannot load $BW_HERE/lib/plan-fixture.sh" >&2; exit 1; }
[ -r "$BW_HERE/lib/maker-stop.sh" ] && . "$BW_HERE/lib/maker-stop.sh" \
  || { echo "bash-walls.prelude.sh: cannot load $BW_HERE/lib/maker-stop.sh" >&2; exit 1; }

# ---------- fixtures ----------

[ -r "$BW_HERE/lib/bash-walls-world.sh" ] && . "$BW_HERE/lib/bash-walls-world.sh" \
  || { echo "bash-walls.prelude.sh: cannot load $BW_HERE/lib/bash-walls-world.sh" >&2; exit 1; }

# bw_bind <repo> — an ENGAGED session in <repo> is bound to the plan the case just wrote at
# `active.md` (wave-23-fixit-1810, REQ-1, D1). An empty marker beside an open plan is the
# unbound state, whose newest-plan fallback is announced and never acted on: the evidence
# gate would judge no commit at all. An unengaged repo stays unengaged.
bw_bind() {
  [ -f "$1/.bionic/tmp/engaged-$SID.state" ] || return 0
  bound_marker "$1" "$SID" "$1/.bionic/docs/plans/active.md"
}

# block_plan <repo> — a run at Step 5 whose log holds no proof of the whole run, so the evidence gate
# refuses any `git commit` made under it; an engaged session is bound to it, as bw_bind binds.
block_plan() {
  local p; p="$(plan_fixture --current 5 "$1/.bionic/docs/plans/epic-x/wave-x.plan.md" wave)" || return 1
  [ ! -f "$1/.bionic/tmp/engaged-$SID.state" ] || bound_marker "$1" "$SID" "$p"
}

# arm_roster <repo> — the roster file the partition in `wall_background_suite_guard`
# (payload/scripts/lib/walls.sh) requires before that wall judges at all. Its PRESENCE is the whole predicate; no row is needed
# for the backgrounded-suite arm, which is the arm this suite drives.
arm_roster() { : > "$1/.bionic/tmp/roster-$SID.state"; }

# mk_payload <cwd> <command> [agent_id] [run_in_background] [tool_name] [agent_type] [timeout]
#
# `agent_type` IS A SEPARATE FIELD FROM `agent_id` and the two walls read different ones:
# hooks/farm-out-reminder.sh leaves on a non-empty `agent_type` (it moves work OFF the
# orchestrator thread, so the thread it moved work TO must not be nudged), while the
# agent-context predicate is `agent_id`. A row that wants ONE wall to answer sets both.
#
# `timeout` (T3, REQ-3, D4): omitted by default, matching the CLI's own shape — the Bash
# tool input schema declares it optional and the harness drops the key rather than send a
# null (record/wave-13-fixit-180/research-R2-walls.md §4). A row driving the repair arm
# passes a bare integer string; `tonumber` gives it the JSON number type a real payload
# carries, not a quoted string a real one never would.
mk_payload() {
  jq -n --arg s "$SID" --arg c "$1" --arg cmd "$2" --arg a "${3:-}" \
        --arg bg "${4:-omit}" --arg t "${5:-Bash}" --arg at "${6:-}" --arg to "${7:-omit}" \
    '{session_id:$s, cwd:$c, hook_event_name:"PreToolUse", tool_name:$t,
      tool_input:({command:$cmd}
                  + (if $bg == "omit" then {} else {run_in_background: ($bg == "true")} end)
                  + (if $to == "omit" then {} else {timeout: ($to | tonumber)} end)),
      tool_use_id:"toolu_01t23walls"}
     + (if $a == "" then {} else {agent_id:$a} end)
     + (if $at == "" then {} else {agent_type:$at} end)'
}

OUT=""; ERR=""; ST=0
run_hook() {  # <payload> [extra env assignments...]
  local payload="$1"; shift
  OUT=$(printf '%s' "$payload" | env HOME="$FAKE_HOME" \
          BIONIC_PLUGINS_DIR="$SANDBOX/no-plugins" CLAUDE_CODE_SESSION_ID="$SID" \
          CLAUDE_PROJECT_DIR= "$@" bash "$HOOK" 2>"$SANDBOX/.err")
  ST=$?
  ERR=$(cat "$SANDBOX/.err")
  return 0
}

# The three readers of the composed verdict. Each goes through jq or through an offset,
# never through a substring of the raw stream, so a test cannot pass on a malformed wire.
json_docs()   { printf '%s' "$OUT" | jq -s 'length' 2>/dev/null; }
deny_reason() { printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""' 2>/dev/null; }
context_of()  { printf '%s' "$OUT" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null; }
# updated_timeout_of / has_updated_input — T3 readers. `has_updated_input` distinguishes
# "no updatedInput key at all" from "updatedInput.timeout happens to be empty", which
# `updated_timeout_of` alone cannot: both read "" from jq's `// empty`.
updated_timeout_of()  { printf '%s' "$OUT" | jq -r '.hookSpecificOutput.updatedInput.timeout // empty' 2>/dev/null; }
has_updated_input()   { printf '%s' "$OUT" | jq -e '.hookSpecificOutput.updatedInput' >/dev/null 2>&1 && echo yes || echo no; }
# updated_command_of — the rewritten command (wave-26 T7): the booking wrap, when one rode.
updated_command_of()  { printf '%s' "$OUT" | jq -r '.hookSpecificOutput.updatedInput.command // empty' 2>/dev/null; }
# line_of <regex> — the 1-based line of the first stderr line matching, or empty.
line_of()     { printf '%s\n' "$ERR" | awk -v re="$1" '$0 ~ re {print NR; exit}'; }

# ---------- §EG-6's plan writer and gate drive (also the base of §EG-DERIVE) ----------
EG6_LIB="${BIONIC_HOOKS_DIR}/../payload/scripts/lib/proof.sh"
R_EG6="$(mk_repo eg6)" || { echo "bash-walls.prelude.sh: the eg6 fixture was not made" >&2; exit 1; }
H_EG6="$(git -C "$R_EG6" rev-parse HEAD)"
eg6_gate() {  # <plan text> -> ST, ERR of a main-checkout commit against the run at 15 the text stands for (eg6_world)
  eg6_world "$R_EG6" "$1"
  [ ! -f "$R_EG6/.bionic/tmp/engaged-$SID.state" ] || bound_marker "$R_EG6" "$SID" "$EG6_PAGE"
  run_hook "$(mk_payload "$R_EG6" 'git commit -m "x"')"
}
