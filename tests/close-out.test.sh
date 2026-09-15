#!/bin/bash
# tests/close-out.test.sh — payload/scripts/close-out.sh: the Step 8/9 tail, performed
# by one script that attests its own acts (epic-23 wave-13-fixit-180, REQ-4; AC-4.1,
# AC-4.3, AC-4.4; design ledger D5, D6).
#
# WHAT IT OWNS. Four sections, each hermetic against a fixture project under a mktemp
# sandbox with HOME redirected into it — never this repository, never the real plan,
# never the real archive:
#
#   §1  AC-4.1  `run` performs every act on a fixture at Step 8: the merge readback,
#               the worktree sweep, the tmp wipe, the TaskUpdate instruction, the
#               continuation, the epic row, the patrol instruction, the handoff
#               rewrite, the two lifecycle blocks with `attested-by:`, the gate
#               dry-run, and the archive. Then the REAL hooks/bash-walls.sh, on a
#               `git commit` payload, allows the commit the script's blocks describe.
#   §2  AC-4.3  a `wt/*` branch carrying a commit the working branch never took
#               refuses BY NAME and performs nothing; a fully reachable one is deleted.
#   §3  AC-4.4  a second `run` prints `already closed` and touches nothing — the plan,
#               the epic plan and the continuation keep their checksums.
#   §4          `check` is a diagnosis: it reports and changes not one byte.
#
# WHY A GIT FIXTURE AND NOT A STUB. Two of the acts are git verdicts — `merge-base
# --is-ancestor` and `git cherry` — and both are exactly the kind of answer a stub
# would get subtly wrong in the safe direction (a stub that always says "reachable"
# turns AC-4.3 into a test of the stub). Every fixture below is a real repository with
# a real merge and real branches, built by `git init` under the sandbox.
#
# THE ENGAGEMENT MARKER IS WIPED BY THE SCRIPT ITSELF (act 3 takes the whole of
# `.bionic/tmp/`, Chris 2026-09-14), so every hook drive below arms its own marker for
# its own session id first. That is the same thing close-out.sh does around its own
# dry-run, and it is why the dry-run is not silently inert.
#
# Usage: bash tests/close-out.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
SCRIPT="$REPO_ROOT/payload/scripts/close-out.sh"
RUN_LIB="$REPO_ROOT/payload/scripts/lib/run.sh"
HOOK="${BIONIC_HOOKS_DIR}/bash-walls.sh"

SANDBOX="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/close-out-test.XXXXXX")" && pwd -P)"
# TS_LIVE_PIDS -> processes §tmp-spares spawns to stand in for a live neighbour session
# (session-sweep.test.sh:79's trick: a real `kill -0`-able pid, never this shell's own).
# The EXIT trap kills every one; nothing here waits on them.
TS_LIVE_PIDS=""
cleanup() {
  local p
  for p in $TS_LIVE_PIDS; do kill -9 "$p" 2>/dev/null; done
  rm -rf "$SANDBOX"
}
trap cleanup EXIT

SB_HOME="$SANDBOX/home"
mkdir -p "$SB_HOME/.claude"

# Every fixture commit is made by this identity, so a redirected HOME with no
# ~/.gitconfig cannot make `git commit` fail for a reason this suite is not about.
export GIT_AUTHOR_NAME=fixture GIT_AUTHOR_EMAIL=fixture@example.invalid
export GIT_COMMITTER_NAME=fixture GIT_COMMITTER_EMAIL=fixture@example.invalid

# contains <haystack> <needle> -> yes|no. A function, not a `case` inside a command
# substitution — bash 3.2 mis-parses that shape and truncates at the first `)`
# (tests/archive.test.sh carries the same note).
contains() {
  case "$1" in
    *"$2"*) printf 'yes' ;;
    *)      printf 'no'  ;;
  esac
}

# ---------- the sandbox guard ----------

# in_fixture <dir> — the ONLY way a subshell below enters a fixture. `cd ""` is a NO-OP in
# bash, not an error, so a fixture path that came out empty does not stop the subshell: it
# leaves it in whatever directory the SUITE is running from, which is this repository's own
# checkout, and every `git init` / `git commit` / `git checkout` after it lands there.
#
# MEASURED, 2026-09-14, on the first run of this file. `local name="$1" p="$SANDBOX/$name"`
# expands every word BEFORE the builtin assigns any of them, so `$p` was empty; the fixture
# builder then committed the suite's own uncommitted work onto the branch under test and
# moved HEAD onto `main`. Nothing was lost, and nothing about that was visible from the
# test output. The guard is three conditions — non-empty, a real directory, and INSIDE the
# sandbox — and no fixture command runs outside it.
in_fixture() {
  local d="${1:-}"
  if [ -z "$d" ]; then
    echo "close-out.test.sh: refusing a fixture command with an EMPTY path" >&2
    return 1
  fi
  case "$d" in
    "$SANDBOX"/*) : ;;
    *) echo "close-out.test.sh: refusing a fixture command outside the sandbox: $d" >&2; return 1 ;;
  esac
  [ -d "$d" ] || { echo "close-out.test.sh: no fixture directory at $d" >&2; return 1; }
  cd "$d" || return 1
}

# fixture_git <dir> <git args...> — `git -C` with the same guard. `git -C ""` runs in the
# caller's directory exactly the way `cd ""` does.
fixture_git() {
  local d="${1:-}"
  shift
  case "$d" in
    "$SANDBOX"/*) : ;;
    *) echo "close-out.test.sh: refusing git outside the sandbox: '$d'" >&2; return 1 ;;
  esac
  git -C "$d" "$@"
}

# ---------- the fixture ----------

# fixture_plan_text <archive-root> <current> -> a plan the evidence gate reads clean at
# current: 9: frontmatter (walk exempt, tested rigor, no named deploy target), a
# `## SDLC State` naming both branches, and a complete `## Verification Matrix` whose
# one T1 row owes tier-run/readback/evidence and has them.
fixture_plan_text() {
  local aroot="$1" current="$2"
  cat <<PLAN_HEAD
---
governing-skill: canonical-sdlc
canonical_sdlc_version: 14
intent: bugfix
rigor: tested
scale: wave
deploy_target: n/a
use_worktree: false
has_ui: false
multi_agent: false
walk: exempt
archive-root: ${aroot}
---

# fixture wave · close-out suite

## SDLC State

integration-branch: main
working-branch: wave/01-fixture
base: main @ fixture
intent: bugfix
rigor: tested
scale: wave
current: ${current}
approved-by: fixture 2026-09-14T00:00Z "approved"

- Step 7: CLOSED — n/a: no ADR owed by a fixture
- Step 8: (pending)
- Step 9: (pending)

## Verification Matrix

stack-health: n/a: no long-running serve

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1 | T1 | discharged | see AC-1 | CONFIRMED |

AC-1:
  fails-when: the planted defect this eval must go red on
  evidence: record/generic-evidence.md
  tier-run: bash tests/close-out.test.sh
  readback: the two lifecycle blocks the script wrote

## Handoff

- resume point: Step 8 open; the tail has not run.
- open blockers: none.
PLAN_HEAD
}

# fixture_epic_text -> an epic plan that is itself OPEN (current: 4), carrying a shipped
# wave table with one existing row. Open on purpose: an open sibling is what keeps
# `archive_run` from moving a wave out of a container epic, which is this repository's
# own shape and the one §1 asserts against.
fixture_epic_text() {
  cat <<'EPIC'
---
canonical_sdlc_version: 14
---

# epic-fx

## SDLC State

current: 4

## Waves — shipped

| wave | version | plan | spec / requirements | ADRs | shipped |
|---|---|---|---|---|---|
| 00 | 0.0.1 | `wave-00-seed.plan.md` | — | — | 2026-01-01 |

## Notes

Nothing here.
EPIC
}

# mk_fixture <name> -> an initialised project at $SANDBOX/<name>, echoed. Contains:
# a git repo whose `wave/01-fixture` is merged into `main`, a `wt/01-x` branch holding no
# commit `main` has not taken, `.bionic/tmp/` with three files, the plan at Step 8, an
# open epic plan with a shipped-wave table, and the matrix's evidence file.
mk_fixture() {
  # ONE ASSIGNMENT PER `local`. Every word on a `local` line is expanded BEFORE the
  # builtin assigns any of them, so `local name="$1" p="$SANDBOX/$name"` reads `$name`
  # while it is still unset — silently empty without `set -u`, and a hard exit with it.
  local name="$1"
  local p="$SANDBOX/$name"
  local aroot="$SANDBOX/$name-archive"
  mkdir -p "$p/.bionic/docs/plans/epic-fx" \
           "$p/.bionic/docs/record/wave-01-fixture" \
           "$p/.bionic/tmp" \
           "$aroot"
  printf 'poker-interval: 20\narchive-root: %s\n' "$aroot" > "$p/.bionic/config.yaml"
  printf 'generic fixture proof — this suite tests the tail, not the artifact.\n' \
    > "$p/.bionic/docs/record/generic-evidence.md"
  : > "$p/.bionic/tmp/engaged-fixture.state"
  : > "$p/.bionic/tmp/roster-fixture.state"
  : > "$p/.bionic/tmp/scratch.txt"

  # The epic plan FIRST, the wave plan second: `active_plan`'s newest-mtime walk is how
  # the gate picks which plan to read, and the wave plan is the one under test.
  fixture_epic_text > "$p/.bionic/docs/plans/epic-fx/epic.plan.md"
  fixture_plan_text "$aroot" 8 > "$p/.bionic/docs/plans/epic-fx/wave-01-fixture.plan.md"
  touch "$p/.bionic/docs/plans/epic-fx/wave-01-fixture.plan.md"

  (
    in_fixture "$p" || exit 1
    git init -q . >/dev/null 2>&1
    git symbolic-ref HEAD refs/heads/main
    printf '.bionic/\n' > .gitignore
    printf 'seed\n' > file.txt
    git add -A >/dev/null 2>&1
    git commit -q -m "seed" >/dev/null 2>&1
    git checkout -q -b wave/01-fixture
    printf 'work\n' >> file.txt
    git commit -q -am "wave work" >/dev/null 2>&1
    git branch wt/01-x
    git checkout -q main
    git merge -q --no-ff -m "merge wave" wave/01-fixture >/dev/null 2>&1
  )
  printf '%s\n' "$p"
}

# add_unreached_branch <project> -> plants `wt/01-y` carrying one commit the working branch
# never took: `git cherry wave/01-fixture wt/01-y` answers with a `+` line.
add_unreached_branch() {
  (
    in_fixture "$1" || exit 1
    git checkout -q -b wt/01-y wave/01-fixture
    printf 'never landed\n' >> file.txt
    git commit -q -am "unreached" >/dev/null 2>&1
    git checkout -q main
  )
}

# add_foreign_unreached_branch <project> -> plants `wt/07-z`, a DIFFERENT wave's writer,
# carrying one commit `main` never took. The census this task scopes to `wt/01-*` (this
# fixture's own wave number) must never see it: not refused on, not deleted. Built off
# `main` rather than `wave/01-fixture` so it exists independent of that branch entirely —
# the shape of a foreign wave's leftover worktree, not a sibling of this wave's own.
add_foreign_unreached_branch() {
  (
    in_fixture "$1" || exit 1
    git checkout -q -b wt/07-z main
    printf 'foreign wave work\n' >> file.txt
    git commit -q -am "foreign unreached" >/dev/null 2>&1
    git checkout -q main
  )
}

PLAN_REL=".bionic/docs/plans/epic-fx/wave-01-fixture.plan.md"
EPIC_REL=".bionic/docs/plans/epic-fx/epic.plan.md"
CONT_REL=".bionic/docs/record/wave-01-fixture/continuation.md"

# ---------- drivers ----------

CO_OUT=""
CO_RC=0
# run_close <project> <verb> -> sets CO_OUT (stdout+stderr merged) and CO_RC. The status
# is taken from a file-redirected call rather than a command substitution, because a
# substitution's subshell cannot hand a variable back.
run_close() {
  local proj="$1" verb="$2" f="$SANDBOX/co-out"
  # BIONIC_PLUGIN_ROOT is pinned to THIS checkout's payload, so the script's own
  # `plugin_root` (and therefore the hook it dry-runs and the version it attests) is the
  # copy under test rather than whatever the CLI happens to have installed on the machine
  # running the suite. BIONIC_CLAUDE_HOME (REQ-1: close-out.sh now sources lib/patrol.sh,
  # whose liveness reads land under claude_home()) is pinned the same way and for the
  # same reason `tests/session-sweep.test.sh`'s `poke()` pins it rather than trusting
  # HOME alone — claude_home()'s own override chain reads CLAUDE_CONFIG_DIR BEFORE HOME,
  # and this suite's own session (this very shell) has that set, so HOME redirection on
  # its own is not hermetic against the real machine's live sessions.
  ( in_fixture "$proj" || exit 9
    HOME="$SB_HOME" CLAUDE_PROJECT_DIR="" BIONIC_PLUGIN_ROOT="$REPO_ROOT/payload" \
      BIONIC_CLAUDE_HOME="$SB_HOME/.claude" \
      bash "$SCRIPT" "$proj/$PLAN_REL" "$verb" ) > "$f" 2>&1
  CO_RC=$?
  CO_OUT="$(cat "$f")"
  rm -f "$f"
}

# run_close_as <sid> <project> <verb> -> like run_close, but pins CLAUDE_CODE_SESSION_ID
# to <sid> for the call — this is the script's own identity (`CO_SID`), the input REQ-1's
# tmp-spare rule reads to tell "this session's own state" from "a live neighbour's".
run_close_as() {
  local sid="$1" proj="$2" verb="$3" f="$SANDBOX/co-out"
  ( in_fixture "$proj" || exit 9
    HOME="$SB_HOME" CLAUDE_PROJECT_DIR="" BIONIC_PLUGIN_ROOT="$REPO_ROOT/payload" \
      BIONIC_CLAUDE_HOME="$SB_HOME/.claude" \
      CLAUDE_CODE_SESSION_ID="$sid" \
      bash "$SCRIPT" "$proj/$PLAN_REL" "$verb" ) > "$f" 2>&1
  CO_RC=$?
  CO_OUT="$(cat "$f")"
  rm -f "$f"
}

# plant_tmp_session <project> <sid> -> the five session-keyed classes AC-1.1 names
# (`engaged-`, `roster-`, `patrol-`, `preflight-`, `sweeper-`), one file per class,
# under <project>/.bionic/tmp — the shape tests/session-sweep.test.sh's plant_session
# builder plants for the same classes, minus that suite's `stop-orders` and the
# `patrol-*.state.armed` sibling (neither is load-bearing for what this section proves).
plant_tmp_session() {
  local p="$1" sid="$2" c
  for c in engaged roster patrol preflight sweeper; do
    printf '%s state for %s\n' "$c" "$sid" > "$p/.bionic/tmp/$c-$sid.state"
  done
}

# tmp_file_exists <project> <class> <sid> -> yes|no, whether one planted file survived.
tmp_file_exists() {
  if [ -f "$1/.bionic/tmp/$2-$3.state" ]; then printf 'yes'; else printf 'no'; fi
}

# gate_rc <project> -> the real hooks/bash-walls.sh verdict on a `git commit` payload,
# driven exactly the way tests/canonical-sdlc-evidence-gate.test.sh drives it: env
# session id agreeing with the payload's, an engagement marker armed for that id,
# CLAUDE_PROJECT_DIR empty, cwd pinned to the project.
gate_rc() {
  local proj="$1"
  local sid="closeout-suite-1"
  local input
  case "$proj" in "$SANDBOX"/*) : ;; *) echo "gate_rc: refusing outside the sandbox: '$proj'" >&2; echo 9; return 0 ;; esac
  mkdir -p "$proj/.bionic/tmp"
  : > "$proj/.bionic/tmp/engaged-${sid}.state"
  input=$(jq -n --arg c "git commit -m x" --arg cwd "$proj" --arg s "$sid" \
            '{session_id: $s, cwd: $cwd, hook_event_name: "PreToolUse", tool_name: "Bash",
              tool_input: {command: $c}, tool_use_id: "toolu_suite"}')
  HOME="$SB_HOME" CLAUDE_PROJECT_DIR="" CLAUDE_CODE_SESSION_ID="$sid" \
    bash "$HOOK" <<< "$input" >/dev/null 2>&1
  echo $?
}

# run_open_rc <plan> -> lib/run.sh's own verdict: 0 open, 1 closed.
run_open_rc() {
  ( /bin/bash -c '. "$1" || exit 9; run_open "$2"' _ "$RUN_LIB" "$1" >/dev/null 2>&1 )
  echo $?
}

# tmp_entries <project> -> how many entries are left directly under .bionic/tmp/.
tmp_entries() {
  find "$1/.bionic/tmp" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | tr -d ' '
}

# sha_of <file> -> a checksum, or `absent`. cksum, not sha1sum: this tree runs on macOS
# where sha1sum is not installed, and any stable digest answers "did this change".
sha_of() {
  if [ -f "$1" ]; then cksum < "$1" | tr -d ' '; else printf 'absent'; fi
}

# branch_exists <project> <branch> -> yes|no
branch_exists() {
  if fixture_git "$1" rev-parse --verify --quiet "refs/heads/$2" >/dev/null 2>&1; then
    printf 'yes'
  else
    printf 'no'
  fi
}

require_helpers in_fixture fixture_git contains fixture_plan_text fixture_epic_text mk_fixture \
                add_unreached_branch add_foreign_unreached_branch run_close run_close_as gate_rc \
                run_open_rc tmp_entries sha_of branch_exists plant_tmp_session tmp_file_exists

# ============================================================
section "0 — the script exists, parses, and refuses an unusable call"
# ============================================================

expect_eq "0a: close-out.sh is on disk" "yes" "$([ -r "$SCRIPT" ] && echo yes || echo no)"
expect_eq "0b: close-out.sh parses" "yes" \
  "$(bash -n "$SCRIPT" 2>/dev/null && echo yes || echo no)"

# The guard that keeps this suite's own git commands inside the sandbox, asserted rather
# than assumed — it is the one helper here whose failure is invisible in the results.
expect_eq "0e: the sandbox guard refuses an EMPTY fixture path" "1" \
  "$( ( in_fixture "" ) >/dev/null 2>&1; echo $? )"
expect_eq "0f: …and one outside the sandbox (this repository)" "1" \
  "$( ( in_fixture "$REPO_ROOT" ) >/dev/null 2>&1; echo $? )"
expect_eq "0g: …while a real fixture path is entered" "0" \
  "$( ( in_fixture "$SB_HOME" ) >/dev/null 2>&1; echo $? )"

P0="$(mk_fixture p0)"
run_close "$P0" "fly"
expect_eq "0c: an unknown verb exits 2" "2" "$CO_RC"
expect_eq "0d: …and says which verbs there are" "yes" "$(contains "$CO_OUT" "check")"

# 0h/0i/0j — R6 finding 1 (architecture FAIL, T16): the worktree census must be scoped to
# THIS wave's `wt/NN-*` branches, derived from the plan's own working-branch. A working
# branch that is not `wave/<digits>-<slug>` shaped has no wave number to scope to, and the
# preflight refuses rather than falling back to a repo-wide census.
P0H="$(mk_fixture p0h)"
sed -i.bak 's#^working-branch: wave/01-fixture$#working-branch: main#' "$P0H/$PLAN_REL"
rm -f "$P0H/$PLAN_REL.bak"
run_close "$P0H" check
expect_eq "0h: a non-wave-shaped working-branch refuses in preflight" "2" "$CO_RC"
expect_eq "0i: …naming the branch" "yes" "$(contains "$CO_OUT" "working-branch 'main'")"
expect_eq "0j: …and the expected shape" "yes" \
  "$(contains "$CO_OUT" "wave/<digits>-<slug>")"

# ============================================================
section "1 — AC-4.1: run performs the tail and the gate allows the commit"
# ============================================================

P1="$(mk_fixture p1)"
expect_eq "1.0: the fixture starts with three entries under .bionic/tmp/" "3" "$(tmp_entries "$P1")"
run_close "$P1" run

expect_eq "1a: run exits 0" "0" "$CO_RC"
expect_eq "1b: act 1 — merge: reports the ancestry readback" "yes" \
  "$(contains "$CO_OUT" "merge: wave/01-fixture @ ")"
expect_eq "1c: …naming the integration branch it is reachable from" "yes" \
  "$(contains "$CO_OUT" "reachable from main @ ")"
expect_eq "1d: act 2 — worktree-removed: names the branch it deleted" "yes" \
  "$(contains "$CO_OUT" "worktree-removed: wt/01-x")"
expect_eq "1e: …and wt/01-x is actually gone" "no" "$(branch_exists "$P1" "wt/01-x")"
expect_eq "1f: act 3 — tmp-wiped: counts what it removed" "yes" \
  "$(contains "$CO_OUT" "tmp-wiped: 3 entries")"
expect_eq "1g: …and .bionic/tmp/ is empty afterwards (REQ-1: this fixture's ids read as dead, so nothing is spared — §tmp-spares below covers a live one)" "0" "$(tmp_entries "$P1")"
expect_eq "1h: act 4 — tasks-completed: is the TaskUpdate instruction" "yes" \
  "$(contains "$CO_OUT" "tasks-completed: mark every 4/*, 5–9 entry completed (TaskUpdate)")"
expect_eq "1i: act 5 — continuation: names the file it wrote" "yes" \
  "$(contains "$CO_OUT" "continuation: ")"
expect_eq "1j: …and the file is there, non-empty" "yes" \
  "$([ -s "$P1/$CONT_REL" ] && echo yes || echo no)"
expect_eq "1k: …in the 1.7.1 shape — the five headings" "yes" \
  "$(contains "$(cat "$P1/$CONT_REL")" "## Resume instruction")"
expect_eq "1l: …and it leaves the orchestrator's unknowns marked" "yes" \
  "$(contains "$(cat "$P1/$CONT_REL")" "<fill")"
expect_eq "1m: act 6 — epic-row: reports the row" "yes" "$(contains "$CO_OUT" "epic-row: ")"
expect_eq "1n: …and the epic table carries exactly one row for wave 01" "1" \
  "$(grep -c '^|[[:space:]]*01[[:space:]]*|' "$P1/$EPIC_REL" | tr -d ' ')"
expect_eq "1o: …without disturbing the row that was already there" "1" \
  "$(grep -c '^|[[:space:]]*00[[:space:]]*|' "$P1/$EPIC_REL" | tr -d ' ')"
expect_eq "1p: act 8 — patrol: names CronDelete and the disarm verb" "yes" \
  "$(contains "$CO_OUT" "patrol: CronDelete")"
expect_eq "1q: …and the disarm command" "yes" \
  "$(contains "$CO_OUT" "session-poker.sh disarm")"
expect_eq "1r: act 9 — the handoff is rewritten to the closed form" "yes" \
  "$(contains "$(cat "$P1/$PLAN_REL")" "resume point: NONE — DELIVERED at ")"
expect_eq "1s: …and the open-run resume point is gone" "no" \
  "$(contains "$(cat "$P1/$PLAN_REL")" "the tail has not run")"

PLAN1="$(cat "$P1/$PLAN_REL")"
expect_eq "1t: the Step-8 line is CLOSED with a timestamp" "yes" \
  "$(grep -qE '^- Step 8: CLOSED [0-9]{4}-[0-9]{2}-[0-9]{2}T' <<< "$PLAN1" && echo yes || echo no)"
expect_eq "1u: …merge: on its own continuation line, never semicolon-joined" "yes" \
  "$(grep -qE '^  merge: ' <<< "$PLAN1" && echo yes || echo no)"
expect_eq "1v: …worktree-removed: on its own line" "yes" \
  "$(grep -qE '^  worktree-removed: ' <<< "$PLAN1" && echo yes || echo no)"
expect_eq "1w: …cleanup: done" "yes" \
  "$(grep -qE '^  cleanup: done' <<< "$PLAN1" && echo yes || echo no)"
expect_eq "1x: …tmp-wiped: on its own line" "yes" \
  "$(grep -qE '^  tmp-wiped: ' <<< "$PLAN1" && echo yes || echo no)"
expect_eq "1y: …tasks-completed: on its own line" "yes" \
  "$(grep -qE '^  tasks-completed: ' <<< "$PLAN1" && echo yes || echo no)"
expect_eq "1z: …and Step 8 is attested by the script that wrote it" "2" \
  "$(grep -c '^  attested-by: close-out.sh ' <<< "$PLAN1" | tr -d ' ')"
expect_eq "1aa: the Step-9 line carries delivered: INLINE, the shape run.sh greps for" "yes" \
  "$(grep -qE '^[[:space:]]*-?[[:space:]]*Step 9:.*delivered:' <<< "$PLAN1" && echo yes || echo no)"
expect_eq "1ab: …with archived: on its own continuation line" "yes" \
  "$(grep -qE '^  archived: ' <<< "$PLAN1" && echo yes || echo no)"
expect_eq "1ac: …and current: advanced to 9" "yes" \
  "$(grep -qE '^current: 9$' <<< "$PLAN1" && echo yes || echo no)"
expect_eq "1ad: the (pending) placeholders are gone" "no" "$(contains "$PLAN1" "Step 8: (pending)")"

expect_eq "1ae: run_open now reads the plan as CLOSED" "1" "$(run_open_rc "$P1/$PLAN_REL")"
expect_eq "1af: the script's own gate dry-run reported ok" "yes" "$(contains "$CO_OUT" "gate: ok")"
expect_eq "1ag: AC-4.1 — the real bash-walls.sh allows the close-out commit" "0" "$(gate_rc "$P1")"
expect_eq "1ah: act 7 — archived: passes archive_run's line through" "yes" \
  "$(contains "$CO_OUT" "archived: bionic: archive")"
expect_eq "1ai: …and the run directory stayed, the epic being open" "yes" \
  "$([ -f "$P1/$PLAN_REL" ] && echo yes || echo no)"

# ============================================================
section "2 — AC-4.3: an unreached wt/* branch refuses by name and nothing else happens"
# ============================================================

P2="$(mk_fixture p2)"
add_unreached_branch "$P2"
PLAN_BEFORE="$(sha_of "$P2/$PLAN_REL")"
run_close "$P2" run

expect_eq "2a: the run exits 2" "2" "$CO_RC"
expect_eq "2b: …and the refusal names the branch that is not reachable" "yes" \
  "$(contains "$CO_OUT" "wt/01-y")"
expect_eq "2c: …wt/01-y survives" "yes" "$(branch_exists "$P2" "wt/01-y")"
expect_eq "2d: …and so does wt/01-x — a refusal deletes nothing at all" "yes" \
  "$(branch_exists "$P2" "wt/01-x")"
expect_eq "2e: …the tmp wipe never ran" "3" "$(tmp_entries "$P2")"
expect_eq "2f: …no continuation was written" "no" \
  "$([ -f "$P2/$CONT_REL" ] && echo yes || echo no)"
expect_eq "2g: …and the plan is byte-for-byte what it was" "$PLAN_BEFORE" \
  "$(sha_of "$P2/$PLAN_REL")"

# The same fixture with the offending branch gone: the reachable one is deleted.
fixture_git "$P2" branch -D wt/01-y >/dev/null 2>&1
run_close "$P2" run
expect_eq "2h: with wt/01-y gone the run exits 0" "0" "$CO_RC"
expect_eq "2i: …and the fully reachable wt/01-x is deleted" "no" "$(branch_exists "$P2" "wt/01-x")"

# 2j–2o — R6 finding 1 (architecture FAIL, T16): the census is scoped to THIS wave's
# `wt/01-*`. A DIFFERENT wave's leftover branch (`wt/07-z`, carrying a commit `main`
# never took) is outside that scope entirely — `run` must not refuse on it or delete it,
# and `check`'s report line must name the scoped prefix rather than a repo-wide one.
P2F="$(mk_fixture p2f)"
add_foreign_unreached_branch "$P2F"
run_close "$P2F" check
expect_eq "2j: check does not refuse over a foreign wt/07-z" "0" "$CO_RC"
expect_eq "2k: …and the census line names this wave's scoped prefix" "yes" \
  "$(contains "$CO_OUT" "worktree-removed: wt/01-*")"
expect_eq "2l: …never naming the foreign branch" "no" "$(contains "$CO_OUT" "wt/07-z")"

run_close "$P2F" run
expect_eq "2m: run does not refuse on the foreign branch either" "0" "$CO_RC"
expect_eq "2n: …wt/07-z survives — a foreign wave's tree is not this run's to judge" "yes" \
  "$(branch_exists "$P2F" "wt/07-z")"
expect_eq "2o: …while this wave's own wt/01-x is still deleted as before" "no" \
  "$(branch_exists "$P2F" "wt/01-x")"

# ============================================================
section "3 — AC-4.4: a second run is a no-op"
# ============================================================

P3="$(mk_fixture p3)"
run_close "$P3" run
expect_eq "3a: the first run exits 0" "0" "$CO_RC"
PLAN_SHA="$(sha_of "$P3/$PLAN_REL")"
EPIC_SHA="$(sha_of "$P3/$EPIC_REL")"
CONT_SHA="$(sha_of "$P3/$CONT_REL")"

run_close "$P3" run
expect_eq "3b: the second run exits 0" "0" "$CO_RC"
expect_eq "3c: …and says the run is already closed" "yes" "$(contains "$CO_OUT" "already closed")"
expect_eq "3d: …the plan is unchanged" "$PLAN_SHA" "$(sha_of "$P3/$PLAN_REL")"
expect_eq "3e: …the epic plan is unchanged (no second row)" "$EPIC_SHA" "$(sha_of "$P3/$EPIC_REL")"
expect_eq "3f: …the continuation is unchanged" "$CONT_SHA" "$(sha_of "$P3/$CONT_REL")"
expect_eq "3g: …and still exactly one row for wave 01" "1" \
  "$(grep -c '^|[[:space:]]*01[[:space:]]*|' "$P3/$EPIC_REL" | tr -d ' ')"

# ============================================================
section "4 — check is a diagnosis: it reports and changes nothing"
# ============================================================

P4="$(mk_fixture p4)"
PLAN4_SHA="$(sha_of "$P4/$PLAN_REL")"
EPIC4_SHA="$(sha_of "$P4/$EPIC_REL")"
run_close "$P4" check

expect_eq "4a: check exits 0" "0" "$CO_RC"
expect_eq "4b: …reports the merge it would attest" "yes" "$(contains "$CO_OUT" "merge:")"
expect_eq "4c: …reports the branches it would delete" "yes" \
  "$(contains "$CO_OUT" "worktree-removed:")"
expect_eq "4d: …reports what the tmp wipe would take" "yes" \
  "$(contains "$CO_OUT" "tmp-wiped: 3 entries")"
# THE PAIR THAT MAKES 1af/1ag NON-VACUOUS. A gate that allowed everything would report
# `gate: ok` after `run` for no reason at all. Here the SAME gate, on the SAME fixture,
# with only the Step-8 block missing, says it would refuse — so the two readings together
# say the gate is reading this plan and discriminating on what the script wrote into it.
expect_eq "4e: …and dry-runs the gate, which refuses the plan as it stands" "yes" \
  "$(contains "$CO_OUT" "gate: would refuse the plan as it stands")"
expect_eq "4f: the plan is untouched" "$PLAN4_SHA" "$(sha_of "$P4/$PLAN_REL")"
expect_eq "4g: the epic plan is untouched" "$EPIC4_SHA" "$(sha_of "$P4/$EPIC_REL")"
expect_eq "4h: no continuation was written" "no" \
  "$([ -f "$P4/$CONT_REL" ] && echo yes || echo no)"
expect_eq "4i: .bionic/tmp/ still holds its three entries" "3" "$(tmp_entries "$P4")"
expect_eq "4j: wt/01-x still exists" "yes" "$(branch_exists "$P4" "wt/01-x")"

# ============================================================
section "5 — REQ-1 (AC-1.1–1.3): a close-out spares a live neighbour's session state"
# ============================================================
#
# TWO SESSIONS SHARE ONE ROOT. A closes over its own run (session A, identified to
# close-out.sh by CLAUDE_CODE_SESSION_ID, the way the real CLI always sets it); B is a
# DIFFERENT, still-running session with its own five session-keyed files here — the shape
# AC-1.1's provenance names verbatim (`engaged-`, `roster-`, `patrol-`, `preflight-` and
# `sweeper-`). "Live" is proven the same way tests/session-sweep.test.sh:79 proves it: a
# real process (`sleep`, backgrounded) this machine's own `kill -0` will find, named in a
# session file under the sandboxed claude-home `HOME` (`$SB_HOME`) already resolves to.

TS_SID_A="closeout-suite-session-a1a1a1a1"
TS_SID_B="closeout-suite-session-b2b2b2b2"

# ---------- AC-1.1 / AC-1.2: B is live, and is spared; A and the unkeyed/dead entries
# ---------- are removed, with the tmp-wiped: line naming both counts.

P5="$(mk_fixture p5)"
plant_tmp_session "$P5" "$TS_SID_A"
plant_tmp_session "$P5" "$TS_SID_B"

sleep 3600 &
TS_B_PID=$!
TS_LIVE_PIDS="${TS_LIVE_PIDS} ${TS_B_PID}"
mkdir -p "$SB_HOME/.claude/sessions"
jq -nc --arg sid "$TS_SID_B" --argjson pid "$TS_B_PID" --arg cwd "$P5" \
  '{sessionId:$sid,pid:$pid,cwd:$cwd}' > "$SB_HOME/.claude/sessions/${TS_SID_B}.json"

# baseline 3 (mk_fixture) + A's 5 + B's 5.
expect_eq "5.0: the fixture starts with 13 entries under .bionic/tmp/ (3 baseline + 5 A + 5 B)" \
  "13" "$(tmp_entries "$P5")"

run_close_as "$TS_SID_A" "$P5" run
expect_eq "5.1: run (as A, with B live) exits 0" "0" "$CO_RC"

for c in engaged roster patrol preflight sweeper; do
  expect_eq "5.2 ($c): B's $c-keyed file survives A's close-out" "yes" \
    "$(tmp_file_exists "$P5" "$c" "$TS_SID_B")"
done
for c in engaged roster patrol preflight sweeper; do
  expect_eq "5.3 ($c): A's own $c-keyed file is removed" "no" \
    "$(tmp_file_exists "$P5" "$c" "$TS_SID_A")"
done
# the baseline's unkeyed scratch.txt and its "fixture"-sid files (dead — no live session
# named "fixture" was ever registered) go with A's own state.
expect_eq "5.4: only B's 5 spared files remain under .bionic/tmp/" "5" "$(tmp_entries "$P5")"
expect_eq "5.5: tmp-wiped: names the total scanned" "yes" \
  "$(contains "$CO_OUT" "tmp-wiped: 13 entries under")"
expect_eq "5.6: …and the removed/spared counts (8 removed: A's 5 + the 3 baseline; 5 spared: B's)" \
  "yes" "$(contains "$CO_OUT" "8 removed, 5 spared")"

# ---------- AC-1.3: a same-shaped neighbour whose session is DEAD is not spared — the
# ---------- sweeper's verdict (patrol_dead_sessions), not mere sparing-by-default, decides.

TS_SID_D="closeout-suite-session-d4d4d4d4"
P6="$(mk_fixture p6)"
plant_tmp_session "$P6" "$TS_SID_A"
plant_tmp_session "$P6" "$TS_SID_D"
# TS_SID_D is never registered in $SB_HOME/.claude/sessions/ — it reads dead by
# construction, the same as the baseline fixture's "fixture" sid above.

run_close_as "$TS_SID_A" "$P6" run
expect_eq "5.7: run (as A, with D dead) exits 0" "0" "$CO_RC"
for c in engaged roster patrol preflight sweeper; do
  expect_eq "5.8 ($c): D's dead $c-keyed file is removed, not spared" "no" \
    "$(tmp_file_exists "$P6" "$c" "$TS_SID_D")"
done
expect_eq "5.9: .bionic/tmp/ is empty afterwards — nothing here is live" "0" "$(tmp_entries "$P6")"

finish
