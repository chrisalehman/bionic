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

# ---------- fixtures ----------

# mk_repo <name> [engaged: yes|no] — a git repo on a feature branch, engaged by default.
#
# A REAL GIT INIT, because hooks/protect-main.sh asks `git symbolic-ref --short HEAD` for
# the current branch and a directory that is not a repo answers nothing — which would make
# its third arm silent for a reason this suite never chose.
mk_repo() {
  local repo="$SANDBOX/$1"
  mkdir -p "$repo/.bionic/tmp" "$repo/.bionic/docs/plans" "$repo/.bionic/docs/record"
  git -C "$repo" init -q 2>/dev/null
  # Nothing is written until git agrees the repository is the one just made: a path that is empty, no directory, or
  # inside another repository would carry this identity and these commits to whatever repository answers for it.
  [ -n "$1" ] && [ -d "$repo" ] && [ "$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null)" = "$(cd "$repo" && pwd -P)" ] \
    || { echo "mk_repo: no repository of its own at '$repo'" >&2; return 1; }
  git -C "$repo" config user.email t@example.com
  git -C "$repo" config user.name "T"
  printf 'seed\n' > "$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit -qm seed 2>/dev/null
  git -C "$repo" checkout -q -b feature/t23 2>/dev/null
  printf 'generic fixture proof\n' > "$repo/.bionic/docs/record/generic-evidence.md"
  [ "${2:-yes}" = yes ] && : > "$repo/.bionic/tmp/engaged-$SID.state"
  bw_door "$repo" "${3:-with}"
  printf '%s' "$repo"
}

# bw_door <dir> [with|noonly|none] — what <dir>'s tests/run.sh is (wave-28 T54, D27). THE ONE DOOR
# fires only in a project whose runner takes `--only`, so a world is built WITH one by default (the
# project this suite's agent rows stand in is bionic's own shape); `noonly` is a runner of the
# project's own that takes no flag, and `none` is a project with suites and no runner at all.
bw_door() {
  mkdir -p "$1/tests"
  case "${2:-with}" in
    none)   rm -f "$1/tests/run.sh" ;;
    noonly) printf '#!/bin/bash\n# the project'"'"'s own runner: every suite, in order, no flags\nfor s in tests/*.test.sh; do bash "$s" || exit 1; done\n' > "$1/tests/run.sh" ;;
    *)      printf '#!/bin/bash\n# usage: tests/run.sh [--only <suite>.test.sh ...]\ncase "${1:-}" in --only) shift ;; esac\n' > "$1/tests/run.sh" ;;
  esac
}

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
eg6_reading() {  # <head> <question> <result> [<evidence>] -> one reading line
  bash -c '. "$1" && proof_line review "$2" 2026-10-04T12:00:00Z "$3" "$4" w-read "$5" piece' \
    _ "$EG6_LIB" "$1" "${4:-record/w27/$2-$3.md}" "$2" "$3"
}
eg6_plan() {  # <current> <scale> <lines> [<Step 6 line>] -> a double plan the gate admits at Step 6 bar the readings
  printf -- '---\ngoverning-skill: canonical-sdlc\ncanonical_sdlc_version: 14\nintent: build\nrigor: double\nscale: %s\n' "$2"
  printf 'deploy_target: none\nuse_worktree: false\nhas_ui: false\nwalk: exempt\n---\n# plan\n\n## SDLC State\n\n'
  printf 'current: %s\napproved-by: fixture 2026-09-22T00:00Z approved\n' "$1"
  printf -- '- Step 4: dispatched, record/w27/dispatch.md\n  worktree: .\n  base-sha: %s\n  branch: feature/t23\n' "$H_EG6"
  printf -- '- Step 5: floor green, record/w27/floor.log\n'
  [ -n "${4:-}" ] && printf -- '%s\n' "$4"
  [ -n "$3" ] && printf '%s\n' "$3"
  printf '\n## Verification Matrix\n\nstack-health: n/a: no long-running serve\n\n'
  printf '| AC | tier | status | evidence | auditor |\n|---|---|---|---|---|\n| AC-1 | T1 | discharged | see AC-1 | CONFIRMED |\n\n'
  printf 'AC-1:\n  fails-when: the planted defect this eval must go red on\n  evidence: record/generic-evidence.md\n'
  printf '  tier-run: bash tests/x.test.sh\n  readback: the line it wrote\n'
}
# eg6_world <repo> <plan text> [<eval type of its criterion>] [<log line>...] -> EG6_PAGE, the run at 15 the text's state section
#   stands for: plan_fixture's page at the text's current:, at double rigor, its log holding the fixture's events, a
#   regression proof, the text's review, moved: and waived: lines as the events a run at 15 writes for them, in the
#   order written (each caller writes them in the order of their instants), then the criterion's proof
#   (EG6_AC, the fixture's own unless named; its evidence EG6_EVIDENCE, the generic record unless named), then each line
#   given, so a person's word given after the proof stands after it, then the asks the run already held, which belong to the run and outlive a rebuild of its other facts; the working
#   branch and the base at the repository's head, so the evidence review there is the auditor's cell and the judge's
#   chains start there.
eg6_world() {
  local repo="$1" text="$2" type="${3:-hermetic}" ac="${EG6_AC:-AC-1.1}" cur head asks
  shift; shift; [ "$#" -eq 0 ] || shift
  head="$(git -C "$repo" rev-parse HEAD)"
  cur="$(printf '%s\n' "$text" | awk '$1 == "current:" { print $2; exit }')"
  asks="$(grep -h '|ev=ask|' "$repo/.bionic/docs/record/wave-01-fixture/run.log" 2>/dev/null)"
  rm -rf "$repo/.bionic/docs/plans/epic-99-fixture" "$repo/.bionic/docs/record/wave-01-fixture"
  EG6_PAGE="$(plan_fixture --current "${cur:-6}" "$repo/.bionic/docs/plans/epic-99-fixture/wave-01-fixture.plan.md" wave)"
  awk -v ty="$type" -v h="$head" -v ac="$ac" '/^rigor: /{ $0 = "rigor: double" } /^base-sha: /{ $0 = "base-sha: " h } { sub(/\| AC-1\.1 \| hermetic \|/, "| AC-1.1 | " ty " |"); gsub(/AC-1\.1/, ac); print }' "$EG6_PAGE" > "$EG6_PAGE.t" \
    && mv "$EG6_PAGE.t" "$EG6_PAGE"
  { printf 'run/v1|ev=proof|kind=regression|head=%s|evidence=record/floor.log|at=2026-10-04T01:00:00Z\n' "$head"
    printf '%s\n' "$text" | awk '
      function ev(t, s,   o, at, k, v) { o = "run/v1|ev=" t
        while (match(s, /[a-z][a-z0-9_-]*=("[^"]*"|[^ ]*)/)) { k = substr(s, RSTART, RLENGTH); s = substr(s, RSTART + RLENGTH)
          v = substr(k, index(k, "=") + 1); k = substr(k, 1, index(k, "=") - 1); gsub(/"/, "", v); if (k == "at") at = v; else o = o "|" k "=" v }
        print o "|at=" at }
      /^proved: kind=review / { ev("proof", substr($0, 8)) }
      /^moved: / { ev("finding", "ref=" substr($0, 8)) }
      /^waived: / { q = index($0, "\""); p = substr($0, 9, q - 10); b = index(p, " by "); n = split(substr(p, b + 4), w, " ")
        by = w[1]; for (i = 2; i < n; i++) by = by " " w[i]; ev("waiver", substr(p, 1, b - 1) " by=\"" by "\" said=" substr($0, q) " at=" w[n]) }'
    printf 'run/v1|ev=proof|ac=%s|evidence=%s|at=2026-10-04T01:00:01Z\n' "$ac" "${EG6_EVIDENCE:-record/generic-evidence.md}"
    [ "$#" -eq 0 ] || printf '%s\n' "$@"
    [ -z "$asks" ] || printf '%s\n' "$asks"; } >> "$(plan_fixture_log "$EG6_PAGE")"
  seal_fixture "$EG6_PAGE" "$(plan_fixture_log "$EG6_PAGE")"
  git -C "$repo" branch -f wave/01-fixture HEAD >/dev/null 2>&1
}
R_EG6="$(mk_repo eg6)" || { echo "bash-walls.prelude.sh: the eg6 fixture was not made" >&2; exit 1; }
H_EG6="$(git -C "$R_EG6" rev-parse HEAD)"
eg6_gate() {  # <plan text> -> ST, ERR of a main-checkout commit against the run at 15 the text stands for (eg6_world)
  eg6_world "$R_EG6" "$1"
  [ ! -f "$R_EG6/.bionic/tmp/engaged-$SID.state" ] || bound_marker "$R_EG6" "$SID" "$EG6_PAGE"
  run_hook "$(mk_payload "$R_EG6" 'git commit -m "x"')"
}
