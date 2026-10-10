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
. "$(dirname "$0")/lib/roster-row.sh"   # the one roster-row builder (cross-gate S17; wave-30 T23)

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
# current: 9: frontmatter (walk exempt, single rigor, no named deploy target), a
# `## SDLC State` naming both branches, and a complete `## Verification Matrix` whose
# one T1 row owes evidence and has it.
#
# THE STATE A RUN IS IN BEFORE ITS TOOLS CLOSE IT, AND NOTHING THE TOOLS WRITE (wave-27 T4,
# D14, AC-7.3). No builder here plants `current: 8` or a Step 9 line: the first is the
# `current` verb's to write and the second is close-out's. A plan that carried either by
# hand would hide exactly the two refusals wave-26 met on its own close (research-riders-map
# B1, B2). §FIX-SHAPE reads these builders and fails if one comes back.
fixture_plan_text() {
  local aroot="$1" current="$2"
  cat <<PLAN_HEAD
---
governing-skill: canonical-sdlc
canonical_sdlc_version: 14
intent: bugfix
rigor: single
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
rigor: single
scale: wave
current: ${current}
approved-by: fixture 2026-09-14T00:00Z "approved"

- Step 7: CLOSED — n/a: no ADR owed by a fixture
- Step 8: (pending)

## Tasks

REQ-6/D5/ADR-032: close-out's census reads this table's \`worktree\` cells directly —
neither row's tree exists until a later helper creates the branch, and that is fine:
\`wt_branches()\` only lists a registered row whose branch this repository actually holds.

| id | step | kind | task | agent | deps | size | serves | Files | status | worktree |
|---|---|---|---|---|---|---|---|---|---|---|
| T1 | 4 | build | fixture writer one | implementor | — | 10 | AC-1 | file.txt | landed | 01-x |
| T2 | 4 | build | fixture writer two | implementor | — | 10 | AC-1 | file.txt | landed | 01-y |

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
# commit `main` has not taken, `.bionic/tmp/` with three files, the plan at Step 7 with no
# Step 9 line, an open epic plan with a shipped-wave table, and the matrix's evidence file.
# A row that closes the fixture moves it to Step 8 with `advance_to` first.
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
  fixture_plan_text "$aroot" 7 > "$p/.bionic/docs/plans/epic-fx/wave-01-fixture.plan.md"
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
  plant_facts "$p"
  printf '%s\n' "$p"
}

# plant_facts <project> -> what the run owes, held at the working branch's head, as a run that
# reached Step 7 has it (wave-27 T14; D3): the working branch checked out in a linked worktree
# beside the project (`<project>-wave`), and the floor and every reading lib/proof.sh `facts_owed`
# deals the plan's rigor and scale, each `result=pass`, at that head. The lines are the product's
# (`proof_line` placed by `proof_add_line`, the pair `proof-add` writes through); session-poker
# §56 holds the verb that writes them, and close-out and the gate read plan text whatever wrote
# it. `close-out.sh run` and `check`, and `current 8`, refuse unless `facts_state` holds these.
# A plan whose working branch is not a branch here gets nothing: there is no head to hold.
plant_facts() {
  local p="$1" plan="$1/$PLAN_REL" wb h
  case "$p" in "$SANDBOX"/*) : ;; *) echo "plant_facts: refusing outside the sandbox: '$p'" >&2; return 1 ;; esac
  wb="$(sed -n 's/^working-branch: //p' "$plan" | head -1)"
  h="$(fixture_git "$p" rev-parse --verify -q "refs/heads/${wb}^{commit}" 2>/dev/null)" || return 0
  # A REAL BASE (the T45 ruling): the judge deals no reading on a plan with no base-sha naming a
  # commit, so the run's base, the root commit the working branch grew from, is written first.
  /usr/bin/grep -q '^base-sha:' "$plan" || {
    sed "s/^working-branch: .*/&\\
base-sha: $(fixture_git "$p" rev-list --max-parents=0 "$wb" | head -1)/" "$plan" > "$plan.b" && mv "$plan.b" "$plan"; }
  fixture_git "$p" worktree list --porcelain 2>/dev/null | grep -qxF "branch refs/heads/$wb" \
    || fixture_git "$p" worktree add -q "$p-wave" "$wb" >/dev/null 2>&1
  bash -c '. "$1/run.sh" && . "$1/proof.sh" || exit 1
    facts_owed "$(plan_frontmatter_get "$2" rigor)" "$(plan_frontmatter_get "$2" scale)" \
      | while IFS="	" read -r k q role scope; do
          case "$k" in
            floor)  l="$(proof_line floor "$3" 2026-10-04T12:00:00Z record/wave-01-fixture/floor.log)" ;;
            review) l="$(proof_line review "$3" 2026-10-04T12:00:00Z "record/wave-01-fixture/$q-$scope.md" "$q" w-read pass "$scope")" ;;
            *) continue ;;
          esac
          proof_add_line "$2" "$l" > "$2.pf" && mv "$2.pf" "$2"
        done' _ "$REPO_ROOT/payload/scripts/lib" "$plan" "$h"
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

# mk_census_fixture <name> <working-branch> <tasks-rows> -> a minimal project good
# enough for close-out.sh's preflight and `check`'s census line only (D5, REQ-6,
# ADR-032): a real git repo (one commit, nothing to merge), a `.bionic/config.yaml`
# whose archive-root matches the plan's own so `archive_binding_check` stays silent,
# and a plan carrying the given `working-branch:` verbatim (any shape — the census no
# longer derives anything from it) plus the given `## Tasks` table rows. Section 0's
# register tests never call `run`, so this skips mk_fixture's merge/epic/tmp machinery
# entirely; it exists to prove the census is a pure function of the table, independent
# of everything mk_fixture also happens to set up.
mk_census_fixture() {
  local name="$1" working="$2" rows="$3"
  local p="$SANDBOX/$name"
  local aroot="$SANDBOX/$name-archive"
  mkdir -p "$p/.bionic/docs/plans/epic-fx" "$p/.bionic/docs/record" "$p/.bionic/tmp" "$aroot"
  printf 'archive-root: %s\n' "$aroot" > "$p/.bionic/config.yaml"
  # The dry-run now judges the OPEN plan (T16), so the matrix evidence file must exist.
  printf 'generic fixture proof — this suite tests the tail, not the artifact.\n' \
    > "$p/.bionic/docs/record/generic-evidence.md"
  cat > "$p/.bionic/docs/plans/epic-fx/wave-01-fixture.plan.md" <<PLAN_CENSUS
---
governing-skill: canonical-sdlc
canonical_sdlc_version: 14
intent: bugfix
rigor: single
scale: wave
deploy_target: n/a
use_worktree: false
has_ui: false
multi_agent: false
walk: exempt
archive-root: ${aroot}
---

# fixture register plan — census tests only

## SDLC State

integration-branch: main
working-branch: ${working}
base: main @ fixture
intent: bugfix
rigor: single
scale: wave
current: 7
approved-by: fixture 2026-09-14T00:00Z "approved"

- Step 7: CLOSED — n/a: no ADR owed by a fixture
- Step 8: (pending)

## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | status | worktree |
|---|---|---|---|---|---|---|---|---|---|---|
${rows}

## Handoff

- resume point: Step 8 open; the tail has not run.
- open blockers: none.
PLAN_CENSUS
  (
    in_fixture "$p" || exit 1
    git init -q . >/dev/null 2>&1
    git symbolic-ref HEAD refs/heads/main
    printf '.bionic/\n' > .gitignore
    printf 'seed\n' > file.txt
    git add -A >/dev/null 2>&1
    git commit -q -m "seed" >/dev/null 2>&1
  )
  printf '%s\n' "$p"
}

# mk_census_branch <project> <branch> -> a bare branch ref off HEAD — enough for
# `git show-ref` (wt_branches) and `git cherry` (wt_unreached) to answer about it.
mk_census_branch() {
  fixture_git "$1" branch "$2" >/dev/null 2>&1
}

# mk_census_fixture_nowt <name> <working-branch> <tasks-rows> -> like mk_census_fixture,
# but the `## Tasks` header carries NO `worktree` column at all (10 cells, not 11) — the
# shape research R1 reports as every plan this repository shipped through wave-16, and
# every consumer plan on 1.8.3 (critic C4). `units_has_column <plan> worktree` reads
# false against this table, which is the fork `wt_unreached`'s C4 fix reads.
mk_census_fixture_nowt() {
  local name="$1" working="$2" rows="$3"
  local p="$SANDBOX/$name"
  local aroot="$SANDBOX/$name-archive"
  mkdir -p "$p/.bionic/docs/plans/epic-fx" "$p/.bionic/docs/record" "$p/.bionic/tmp" "$aroot"
  printf 'archive-root: %s\n' "$aroot" > "$p/.bionic/config.yaml"
  # The dry-run now judges the OPEN plan (T16), so the matrix evidence file must exist.
  printf 'generic fixture proof — this suite tests the tail, not the artifact.\n' \
    > "$p/.bionic/docs/record/generic-evidence.md"
  cat > "$p/.bionic/docs/plans/epic-fx/wave-01-fixture.plan.md" <<PLAN_CENSUS
---
governing-skill: canonical-sdlc
canonical_sdlc_version: 14
intent: bugfix
rigor: single
scale: wave
deploy_target: n/a
use_worktree: false
has_ui: false
multi_agent: false
walk: exempt
archive-root: ${aroot}
---

# fixture register plan — no worktree column at all (C4)

## SDLC State

integration-branch: main
working-branch: ${working}
base: main @ fixture
intent: bugfix
rigor: single
scale: wave
current: 7
approved-by: fixture 2026-09-14T00:00Z "approved"

- Step 7: CLOSED — n/a: no ADR owed by a fixture
- Step 8: (pending)

## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | status |
|---|---|---|---|---|---|---|---|---|---|
${rows}

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
PLAN_CENSUS
  (
    in_fixture "$p" || exit 1
    git init -q . >/dev/null 2>&1
    git symbolic-ref HEAD refs/heads/main
    printf '.bionic/\n' > .gitignore
    printf 'seed\n' > file.txt
    git add -A >/dev/null 2>&1
    git commit -q -m "seed" >/dev/null 2>&1
  )
  printf '%s\n' "$p"
}

PLAN_REL=".bionic/docs/plans/epic-fx/wave-01-fixture.plan.md"
EPIC_REL=".bionic/docs/plans/epic-fx/epic.plan.md"
CONT_REL=".bionic/docs/record/wave-01-fixture/continuation.md"
UNITS_LIB="$REPO_ROOT/payload/scripts/lib/units.sh"

# advance_to <project> <N> -> the fixture plan's `current:` moved to N by `units_set_current`,
# the writer the `current` verb itself calls (hooks/session-poker.sh, the `current)` arm), so
# the plan holds the bytes the verb writes. The verb's own dry commit is NOT asked here: until
# wave-27 T14 it demands the Step-8 block close-out writes, and from T14 it demands the
# review facts; §E2E is the row that drives the whole verb.
advance_to() {
  local plan="$1/$PLAN_REL"
  case "$1" in "$SANDBOX"/*) : ;; *) echo "advance_to: refusing outside the sandbox: '$1'" >&2; return 1 ;; esac
  bash -c '. "$1" && units_set_current "$2" "$3"' _ "$UNITS_LIB" "$plan" "$2" > "$plan.adv" \
    && mv "$plan.adv" "$plan"
}

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
                run_open_rc tmp_entries sha_of branch_exists plant_tmp_session tmp_file_exists \
                mk_census_fixture mk_census_branch mk_census_fixture_nowt advance_to

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

P0="$(mk_fixture p0)"; advance_to "$P0" 8
run_close "$P0" "fly"
expect_eq "0c: an unknown verb exits 2" "2" "$CO_RC"
expect_eq "0d: …and says which verbs there are" "yes" "$(contains "$CO_OUT" "check")"

# 0h–0m — REQ-6 (D5, ADR-032): the census is the REGISTER, never a name.
# `working-branch:`'s shape decides nothing any more; a `## Tasks` row's `worktree`
# cell does. This retires the old `wave/<digits>-<slug>` shape refusal (R6 finding 1
# was the reason the shape existed, and the register has neither of its failure
# modes: no consumer shape is ever refused, and no foreign branch is ever swept in).
ROWS04="| T1 | 4 | build | fixture writer one | implementor | — | 10 | AC-1 | file.txt | active | 04-T1 |
| T2 | 4 | build | fixture writer two | implementor | — | 10 | AC-1 | file.txt | active | 04-T2 |"

P0H="$(mk_census_fixture p0h "w51/04-fixit" "$ROWS04")"; advance_to "$P0H" 8
mk_census_branch "$P0H" wt/04-T1
mk_census_branch "$P0H" wt/04-T2
mk_census_branch "$P0H" wt/99-x   # a foreign branch — no row of this plan names it
run_close "$P0H" check
expect_eq "0h: a w51-shaped working-branch is no longer refused in preflight" "0" "$CO_RC"
expect_eq "0i: …the census names exactly the registered trees, in table order" "yes" \
  "$(contains "$CO_OUT" "worktree-removed: wt/04-T1 wt/04-T2 (2 registered trees)")"
expect_eq "0j: …never the foreign, unregistered wt/99-x" "no" "$(contains "$CO_OUT" "wt/99-x")"

# working-branch: main is now an ordinary value — it decided nothing before this
# wave read it for anything but the merge act, and it decides nothing extra now.
P0K="$(mk_census_fixture p0k "main" "$ROWS04")"; advance_to "$P0K" 8
mk_census_branch "$P0K" wt/04-T1
mk_census_branch "$P0K" wt/04-T2
run_close "$P0K" check
expect_eq "0k: working-branch: main is accepted, not refused" "0" "$CO_RC"
expect_eq "0k2: …and still censuses its registered trees" "yes" \
  "$(contains "$CO_OUT" "worktree-removed: wt/04-T1 wt/04-T2 (2 registered trees)")"

# A plan whose `## Tasks` table names no tree: an EMPTY census is the conservative
# failure, and `check`/`run` both proceed rather than refusing.
ROWS_EMPTY="| T1 | 4 | build | fixture writer one | implementor | — | 10 | AC-1 | file.txt | active | — |"
P0L="$(mk_census_fixture p0l "wave/01-fixture" "$ROWS_EMPTY")"; advance_to "$P0L" 8
run_close "$P0L" check
expect_eq "0l: a plan with no filled worktree cell does not refuse" "0" "$CO_RC"
expect_eq "0m: …and says so by name, not silently" "yes" \
  "$(contains "$CO_OUT" "census: no registered trees")"

# ============================================================
section "0n — REQ-6 (AC-6.2): a wave control — the register meets today's shape-derived set"
# ============================================================
#
# A `wave/16-*`-shaped plan with every `wt/16-*` tree it spawned registered proves the
# migration is loss-free for the common case the old `wt/NN-*` glob was built for:
# the register's census is exactly the set the retired shape derivation would also
# have printed, and `wt_unreached` still refuses on a registered branch the working
# branch never took.

ROWS16="| T1 | 4 | build | fixture writer one | implementor | — | 10 | AC-1 | file.txt | landed | 16-a |
| T2 | 4 | build | fixture writer two | implementor | — | 10 | AC-1 | file.txt | active | 16-b |"
P0N="$(mk_census_fixture p0n "wave/16-fixit-183" "$ROWS16")"; advance_to "$P0N" 8
(
  in_fixture "$P0N" || exit 1
  git checkout -q -b wave/16-fixit-183
  printf 'work\n' >> file.txt
  git commit -q -am "wave work" >/dev/null 2>&1
  git branch wt/16-a
  git branch wt/16-orphan   # matches the OLD wt/16-* glob shape but no row of this
                            # plan names it — the register must never sweep it in
  git checkout -q main
  git merge -q --no-ff -m "merge wave 16" wave/16-fixit-183 >/dev/null 2>&1
  git checkout -q -b wt/16-b wave/16-fixit-183
  printf 'never landed\n' >> file.txt
  git commit -q -am "unreached" >/dev/null 2>&1
  git checkout -q main
)
run_close "$P0N" check
expect_eq "0n1: check does not refuse over the unreached wt/16-b" "0" "$CO_RC"
expect_eq "0n2: …the census matches exactly what the old wt/16-* glob would have found" "yes" \
  "$(contains "$CO_OUT" "worktree-removed: wt/16-a wt/16-b (2 registered trees)")"
expect_eq "0n2b: …never the unregistered wt/16-orphan, though its NAME fits the old glob" "no" \
  "$(contains "$CO_OUT" "wt/16-orphan")"

run_close "$P0N" run
expect_eq "0n3: run refuses — the registered wt/16-b carries unreached work" "2" "$CO_RC"
expect_eq "0n4: …naming it" "yes" "$(contains "$CO_OUT" "wt/16-b")"
expect_eq "0n5: …and the fully-reachable wt/16-a still survives the refusal" "yes" \
  "$(branch_exists "$P0N" "wt/16-a")"

# ============================================================
section "0o — C4: no worktree column at all falls back to the pre-wave glob census"
# ============================================================
#
# Critic C4's reproduction: a plan whose `## Tasks` table has NO `worktree` column at
# all (every plan this repository shipped through wave-16; every consumer plan on 1.8.3)
# yields an EMPTY register census, which silently turned `wt_unreached`'s refusal into a
# no-op — the arm's whole job is to refuse, and an empty census means it never can. The
# fix: when the table has no `worktree` column, `wt_unreached` falls back to the census
# every `wt/*` branch this repository holds, announced once on stderr so the fallback is
# never silent either way.

ROWS_NOWT="| T1 | 4 | build | fixture writer one | implementor | — | 10 | AC-1 | file.txt | active |"

# 0o1-0o5: an unmerged wt/01-T1 (git cherry shows a `+` line against the working
# branch) — today (unfixed) this passes silently; the fix must refuse and say so.
P0O="$(mk_census_fixture_nowt p0o "wave/01-x" "$ROWS_NOWT")"; advance_to "$P0O" 8
(
  in_fixture "$P0O" || exit 1
  git checkout -q -b wave/01-x
  printf 'work\n' >> file.txt
  git commit -q -am "wave work" >/dev/null 2>&1
  git checkout -q -b wt/01-T1 wave/01-x
  printf 'never landed\n' >> file.txt
  git commit -q -am "unreached" >/dev/null 2>&1
  git checkout -q main
  git merge -q --no-ff -m "merge wave" wave/01-x >/dev/null 2>&1
)
run_close "$P0O" check
expect_eq "0o1: check WOULD REFUSE naming wt/01-T1 though the register census is empty" "yes" \
  "$(contains "$CO_OUT" "WOULD REFUSE")"
expect_eq "0o2: …naming the branch" "yes" "$(contains "$CO_OUT" "wt/01-T1")"
expect_eq "0o3: …and announces the fallback on stderr, verbatim (scoped to this wave's wt/01-*, C7)" "yes" \
  "$(contains "$CO_OUT" "close-out: no worktree column in the ## Tasks table; unreached-work census falls back to wt/01-* (1.8.3 census)")"

run_close "$P0O" run
expect_eq "0o4: run refuses — the fallback census carries unreached work" "2" "$CO_RC"
expect_eq "0o5: …naming wt/01-T1" "yes" "$(contains "$CO_OUT" "wt/01-T1")"
expect_eq "0o5b: …the branch survives (nothing was deleted, nothing else was done)" "yes" \
  "$(branch_exists "$P0O" "wt/01-T1")"

# 0p: a columnless table whose only wt/* branch is fully merged — the fallback still
# fires (announced) but finds nothing to refuse, and the run proceeds.
P0P="$(mk_census_fixture_nowt p0p "wave/01-x" "$ROWS_NOWT")"; advance_to "$P0P" 8
(
  in_fixture "$P0P" || exit 1
  git checkout -q -b wave/01-x
  printf 'work\n' >> file.txt
  git commit -q -am "wave work" >/dev/null 2>&1
  git branch wt/01-T1 wave/01-x
  git checkout -q main
  git merge -q --no-ff -m "merge wave" wave/01-x >/dev/null 2>&1
)
plant_facts "$P0P"
run_close "$P0P" check
expect_eq "0p1: check does not WOULD-REFUSE — the only wt/* branch is fully merged" "no" \
  "$(contains "$CO_OUT" "WOULD REFUSE")"
expect_eq "0p2: …but still announces the fallback (a columnless table, either way), scoped to wt/01-*" "yes" \
  "$(contains "$CO_OUT" "unreached-work census falls back to wt/01-* (1.8.3 census)")"

run_close "$P0P" run
expect_eq "0p3: run proceeds — nothing in the fallback census carries unreached work" "0" "$CO_RC"

# ============================================================
section "0q — C7: the column-less fallback is scoped to wt/<NN>-*, exactly as 1.8.3 was"
# ============================================================
#
# Critic C7's reproduction: the fallback T24 shipped was `git for-each-ref 'refs/heads/wt/*'`
# — every `wt/*` branch this repository holds, unscoped by wave number. On a column-less
# plan (0o/0p's own shape) that means a DIFFERENT wave's leftover branch — one this task's
# wave never spawned and never merged — could trip act 2's refusal, or (on 1.8.3, the
# behaviour this restores) never could. Same fixture as 0p (own tree wt/01-T1 fully
# merged, so nothing of THIS wave's is unreached) plus a foreign wave's leftover
# (`wt/07-z`, cut from main, one unmerged commit — `add_foreign_unreached_branch`, whose
# own contract at :272-275 is that this branch "must never see it: not refused on, not
# deleted"). At 4e2ac66 (unfixed) this WOULD-REFUSEs and `run` refuses rc=2; at 72e07ec
# (1.8.3) and after this fix, `wt/07-z` falls outside `wt/01-*` and is invisible.

P0Q="$(mk_census_fixture_nowt p0q "wave/01-x" "$ROWS_NOWT")"; advance_to "$P0Q" 8
(
  in_fixture "$P0Q" || exit 1
  git checkout -q -b wave/01-x
  printf 'work\n' >> file.txt
  git commit -q -am "wave work" >/dev/null 2>&1
  git branch wt/01-T1 wave/01-x
  git checkout -q main
  git merge -q --no-ff -m "merge wave" wave/01-x >/dev/null 2>&1
)
add_foreign_unreached_branch "$P0Q"
plant_facts "$P0Q"
run_close "$P0Q" check
expect_eq "0q1: check does not WOULD-REFUSE over a foreign wt/07-z (out of wt/01-* scope)" "no" \
  "$(contains "$CO_OUT" "WOULD REFUSE")"
expect_eq "0q2: …never naming the foreign branch" "no" "$(contains "$CO_OUT" "wt/07-z")"
expect_eq "0q3: …still announces the fallback, scoped to this wave's wt/01-*" "yes" \
  "$(contains "$CO_OUT" "unreached-work census falls back to wt/01-* (1.8.3 census)")"

run_close "$P0Q" run
expect_eq "0q4: run does not refuse on the foreign branch" "0" "$CO_RC"
expect_eq "0q5: …wt/07-z survives — a foreign wave's tree is not this run's to judge" "yes" \
  "$(branch_exists "$P0Q" "wt/07-z")"

# ============================================================
section "0r — C7: a column-less WAVE-scale plan whose working-branch is not wave/<digits>-<slug> shaped refuses, as 1.8.3 did"
# ============================================================
#
# 1.8.3 derived its ENTIRE census (there was no register) from `working-branch:`'s shape
# and refused outright — before act 1, for both `check` and `run` — when no wave number
# could be read off it (`git show 72e07ec:payload/scripts/close-out.sh:242-245`). ADR-032
# retired that refusal for the register path (a `worktree` column names its own trees, no
# wave number needed), but a column-less plan has no register to fall back on — it is
# exactly 1.8.3's shape, and it must refuse exactly as 1.8.3 did rather than silently
# reach for an unscoped repo-wide census (C7's own finding). That refusal is kept for a
# `scale: wave` plan (this fixture's own scale — every fixture here is wave-scale); a
# task-scale plan has no wave number to want, and §ANY-BRANCH below pins it closing.

P0R="$(mk_census_fixture_nowt p0r "topic/not-a-wave-branch" "$ROWS_NOWT")"; advance_to "$P0R" 8
run_close "$P0R" check
expect_eq "0r1: check refuses (1.8.3 refused before act 1, for either verb)" "2" "$CO_RC"
expect_eq "0r2: …with 1.8.3's own wording" "yes" \
  "$(contains "$CO_OUT" "the plan's working-branch 'topic/not-a-wave-branch' is not wave/<digits>-<slug> shaped — the worktree census needs a wave number to scope wt/NN-* to")"

run_close "$P0R" run
expect_eq "0r3: run refuses identically" "2" "$CO_RC"
expect_eq "0r4: …with the same wording" "yes" \
  "$(contains "$CO_OUT" "the plan's working-branch 'topic/not-a-wave-branch' is not wave/<digits>-<slug> shaped — the worktree census needs a wave number to scope wt/NN-* to")"

# A table WITH the worktree column never derives a wave number at all — the register
# names its own trees — so the same non-wave-shaped working-branch is untouched there.
ROWS_WT_SHAPED="| T1 | 4 | build | fixture writer one | implementor | — | 10 | AC-1 | file.txt | active | 01-T1 |"
P0S="$(mk_census_fixture p0s "topic/not-a-wave-branch" "$ROWS_WT_SHAPED")"; advance_to "$P0S" 8
run_close "$P0S" check
expect_eq "0s1: a registered table with the same branch shape is never refused for it" "0" "$CO_RC"

# ============================================================
section "ANY-BRANCH — T11 (AC-9.2): a column-less TASK-scale plan closes on any working-branch"
# ============================================================
#
# A small late fix lives on a branch like `fixit/x`, never `wave/<digits>-<slug>`. A task-
# scale plan owns no wave, so there is no `wt/<NN>-*` to census and no wave number to
# refuse for lacking: the shape refusal is a wave-scale rule only. `wt_unreached` finds no
# branch to report and says nothing about a `wt/-*` glob.

mk_task_scale_fixture() {
  local name="$1" working="$2" p
  p="$(mk_census_fixture_nowt "$name" "$working" "$ROWS_NOWT")"; advance_to "$p" 8
  sed -i.bak 's/^scale: wave$/scale: task/' "$p/$PLAN_REL" && rm -f "$p/$PLAN_REL.bak"
  (
    in_fixture "$p" || exit 1
    git checkout -q -b "$working"
    printf 'late fix\n' >> file.txt
    git commit -q -am "late fix" >/dev/null 2>&1
    git checkout -q main
    git merge -q --no-ff -m "merge fix" "$working" >/dev/null 2>&1
  )
  plant_facts "$p"
  printf '%s\n' "$p"
}

PAB="$(mk_task_scale_fixture pab "fixit/x")"
expect_eq "AB0: the fixture really is task-scale (so a pass here is not the wave refusal's absence)" "yes" \
  "$(grep -q '^scale: task$' "$PAB/$PLAN_REL" && echo yes || echo no)"
run_close "$PAB" check
expect_eq "AB1: check on fixit/x is not refused" "0" "$CO_RC"
expect_eq "AB2: …prints no shape refusal" "no" "$(contains "$CO_OUT" "is not wave/<digits>-<slug> shaped")"
expect_eq "AB3: …and announces no wt/-* census fallback" "no" "$(contains "$CO_OUT" "wt/-*")"
run_close "$PAB" run
expect_eq "AB4: run on fixit/x closes with rc 0" "0" "$CO_RC"
expect_eq "AB5: …prints no shape refusal" "no" "$(contains "$CO_OUT" "is not wave/<digits>-<slug> shaped")"

# ============================================================
section "1 — AC-4.1: run performs the tail and the gate allows the commit"
# ============================================================

P1="$(mk_fixture p1)"; advance_to "$P1" 8
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

P2="$(mk_fixture p2)"; advance_to "$P2" 8
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

# 2j–2o — REQ-6 (D5, ADR-032): the census is MEMBERSHIP BY RECORD. A DIFFERENT
# wave's leftover branch (`wt/07-z`, carrying a commit `main` never took) is outside
# that record entirely — no row of this plan names it — so `run` must not refuse on
# it or delete it, and `check`'s report line must name only the registered tree this
# plan actually holds (`wt/01-x`; `wt/01-y`'s row is registered too, but that branch
# does not exist yet in this fixture).
P2F="$(mk_fixture p2f)"; advance_to "$P2F" 8
add_foreign_unreached_branch "$P2F"
run_close "$P2F" check
expect_eq "2j: check does not refuse over a foreign wt/07-z" "0" "$CO_RC"
expect_eq "2k: …and the census line names exactly the one registered tree in reach" "yes" \
  "$(contains "$CO_OUT" "worktree-removed: wt/01-x (1 registered tree)")"
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

P3="$(mk_fixture p3)"; advance_to "$P3" 8
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

P4="$(mk_fixture p4)"; advance_to "$P4" 8
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
section "4b — critic2 N-3 (T16): run's dry-run judges the plan while it is still OPEN"
# ============================================================
# The dry-run used to run AFTER current: 9 and delivered: were written, so the bound marker
# resolved bound-closed and the commit gate exited 0 before it read any step evidence. Here
# `run` is given a plan with NO Step-8 line. It must refuse (rc 2) and must not flip the
# plan to delivered; at d067c07d it flipped current to 9 and wrote delivered: first.
P16="$(mk_fixture p16)"; advance_to "$P16" 8
grep -v '^- Step 8:' "$P16/$PLAN_REL" > "$P16/plan.tmp" && mv "$P16/plan.tmp" "$P16/$PLAN_REL"
run_close "$P16" run
expect_eq "4k: run on a plan with no Step-8 line refuses rc 2" "2" "$CO_RC"
expect_eq "4l: …and the plan was not flipped to delivered" "no" \
  "$(grep -qE 'Step 9:.*delivered:' "$P16/$PLAN_REL" && echo yes || echo no)"
expect_eq "4m: …and current: is still 8" "yes" \
  "$(grep -qE '^current: 8$' "$P16/$PLAN_REL" && echo yes || echo no)"
expect_eq "4n: …and no gate: ok was reported" "no" "$(contains "$CO_OUT" "gate: ok")"

# A refusal that only the GATE can make (the matrix evidence file is gone): the gate judges
# the open plan at current 8 and refuses before the Step-9 flip. Since T17 that refusal comes
# from the pre-flight, before the Step-8 block is written into the plan at all (§4c).
P17="$(mk_fixture p17)"; advance_to "$P17" 8
rm -f "$P17/.bionic/docs/record/generic-evidence.md"
run_close "$P17" run
expect_eq "4o: run refuses when the gate refuses the open plan (rc 2)" "2" "$CO_RC"
expect_eq "4p: …and the plan is not flipped to delivered" "no" \
  "$(grep -qE 'Step 9:.*delivered:' "$P17/$PLAN_REL" && echo yes || echo no)"
expect_eq "4q: …current: is still 8" "yes" \
  "$(grep -qE '^current: 8$' "$P17/$PLAN_REL" && echo yes || echo no)"

# ============================================================
section "4c — critic3 P-1 (T17): run asks the gate first; check and run agree"
# ============================================================
# `run` used to perform acts 1–6 (branch sweep, tmp wipe, continuation, epic row) and only
# then ask the gate, so a refusal the Step-8 block cannot clear left a half-closed run: the
# branches and this session's tmp state gone, the continuation and epic row written. And
# `check` printed one sentence for every refusal ("the Step-8 block run writes is what
# clears it"), so it could not say which outcome `run` would reach. Now both verbs write
# phase 8's block into a scratch copy of the plan, bind a synthetic marker to the copy,
# and ask the real gate; `run` touches nothing until that pre-flight passes.
P18="$(mk_fixture p18)"; advance_to "$P18" 8
rm -f "$P18/.bionic/docs/record/generic-evidence.md"
PLAN18_SHA="$(sha_of "$P18/$PLAN_REL")"
EPIC18_SHA="$(sha_of "$P18/$EPIC_REL")"
run_close "$P18" check
expect_eq "4r: check on the evidence-missing plan exits 0" "0" "$CO_RC"
expect_eq "4s: …and prints the gate's own refusal for the plan run would write, naming the evidence" "yes" \
  "$(contains "$CO_OUT" "gate: WOULD REFUSE the plan run would write (rc=2): bionic: commit refused — AC-1's evidence names no real file")"
expect_eq "4t: …never the old sentence that promised the Step-8 block would clear it" "no" \
  "$(contains "$CO_OUT" "is what clears it")"
expect_eq "4u: …and leaves no scratch copy beside the plan" "0" \
  "$(find "$P18/.bionic/docs/plans" -name '*preflight*' | wc -l | tr -d ' ')"

run_close "$P18" run
expect_eq "4v: run on the same plan refuses rc 2" "2" "$CO_RC"
expect_eq "4w: …with the gate's own refusal line" "yes" \
  "$(contains "$CO_OUT" "bionic: commit refused — AC-1's evidence names no real file")"
expect_eq "4x: …before the first act: no merge: line was reported" "no" "$(contains "$CO_OUT" "merge: ")"
expect_eq "4y: …wt/01-x is still there" "yes" "$(branch_exists "$P18" "wt/01-x")"
expect_eq "4z: ….bionic/tmp/ still holds its three entries" "3" "$(tmp_entries "$P18")"
expect_eq "4aa: …no continuation was written" "no" \
  "$([ -f "$P18/$CONT_REL" ] && echo yes || echo no)"
expect_eq "4ab: …the epic plan is byte-for-byte what it was (no row for wave 01)" "$EPIC18_SHA" \
  "$(sha_of "$P18/$EPIC_REL")"
expect_eq "4ac: …the plan is byte-for-byte what it was (the block went into the copy only)" "$PLAN18_SHA" \
  "$(sha_of "$P18/$PLAN_REL")"
expect_eq "4ad: …and no scratch copy is left beside the plan" "0" \
  "$(find "$P18/.bionic/docs/plans" -name '*preflight*' | wc -l | tr -d ' ')"

# The control: the same fixture with its evidence. check says the gate allows the plan run
# would write, and run then performs the tail as §1 does.
P19="$(mk_fixture p19)"; advance_to "$P19" 8
run_close "$P19" check
expect_eq "4ae: check on the valid plan says the gate allows the plan run would write" "yes" \
  "$(contains "$CO_OUT" "gate: ok against the plan run would write")"
run_close "$P19" run
expect_eq "4af: …and run on it exits 0" "0" "$CO_RC"
expect_eq "4ag: …reporting the pre-flight before the first act" "yes" \
  "$(contains "$CO_OUT" "preflight: the commit gate allows the plan this run will write")"
expect_eq "4ah: …and the attestation after the Step-8 block, as before" "yes" "$(contains "$CO_OUT" "gate: ok")"

# ============================================================
section "4d — critic3 P-3 (T17): run refuses unless the plan reads current: 8"
# ============================================================
# Nothing read `current:` before phase 9 wrote `current: 9`, so the dry-run judged whatever
# step the plan named and the refusal blamed the blocks run wrote. A plan below Step 8 is
# refused by name, before anything is touched; check reports the same verdict.
for _co_cur in 7 4; do
  P20="$(mk_fixture "p20-$_co_cur")"
  advance_to "$P20" "$_co_cur"
  PLAN20_SHA="$(sha_of "$P20/$PLAN_REL")"
  EPIC20_SHA="$(sha_of "$P20/$EPIC_REL")"
  run_close "$P20" check
  expect_eq "4ai.$_co_cur: check at current $_co_cur names the step refusal run will make" "yes" \
    "$(contains "$CO_OUT" "advance the plan to Step 8 first")"
  run_close "$P20" run
  expect_eq "4aj.$_co_cur: run at current $_co_cur refuses rc 2" "2" "$CO_RC"
  expect_eq "4ak.$_co_cur: …with the line advance the plan to Step 8 first" "yes" \
    "$(contains "$CO_OUT" "advance the plan to Step 8 first")"
  expect_eq "4al.$_co_cur: …wt/01-x is still there" "yes" "$(branch_exists "$P20" "wt/01-x")"
  expect_eq "4am.$_co_cur: ….bionic/tmp/ still holds its three entries" "3" "$(tmp_entries "$P20")"
  expect_eq "4an.$_co_cur: …no continuation was written" "no" \
    "$([ -f "$P20/$CONT_REL" ] && echo yes || echo no)"
  expect_eq "4ao.$_co_cur: …the epic plan is unchanged" "$EPIC20_SHA" "$(sha_of "$P20/$EPIC_REL")"
  expect_eq "4ap.$_co_cur: …and the plan is unchanged (no Step-8 block written)" "$PLAN20_SHA" \
    "$(sha_of "$P20/$PLAN_REL")"
done

# ============================================================
section "4e — critic4 Q-1 (T19), wave-27 T4 (D14, B2): the Step 9 line is close-out's to write; the wave table is still a presence check"
# ============================================================
# `run` used to delete branches, wipe tmp and write the continuation and epic row, and only
# then refuse for a plan with no `- Step 9:` line or an epic plan with no `| wave |` table.
# T19 made both presence checks before the first act. Since wave-27 T4 the first one is
# gone: `step-line 9` is refused by the poker as close-out's to write, so a plan reaches
# close-out with no Step 9 line, and close-out writes it. It is written with phase 8's block
# and never earlier, so a refusal still leaves the plan byte-for-byte as it was.
presence_state() {
  printf 'br=%s tmp=%s cont=%s cur8=%s epicrow=%s' \
    "$(branch_exists "$1" "wt/01-x")" "$(tmp_entries "$1")" \
    "$([ -f "$1/$CONT_REL" ] && echo yes || echo no)" \
    "$(grep -qE '^current: 8$' "$1/$PLAN_REL" && echo yes || echo no)" \
    "$(grep -c '^| 01 ' "$1/$EPIC_REL")"
}
# step_lines <plan> <N> -> how many `Step N:` lines `## SDLC State` carries.
step_lines() {
  awk -v n="$2" '
    /^## / { insdlc = ($0 ~ /^## SDLC State/) }
    insdlc && $0 ~ "^[[:space:]]*-?[[:space:]]*Step[[:space:]]+" n "[[:space:]]*:" { c++ }
    END { print c + 0 }' "$1"
}
TA="$(mk_fixture t19a)"; advance_to "$TA" 8
expect_eq "q1.0: the fixture carries its Step-8 line (the counter reads this plan)" "1" "$(step_lines "$TA/$PLAN_REL" 8)"
expect_eq "q1.0b: …and no Step 9 line: nothing planted it" "0" "$(step_lines "$TA/$PLAN_REL" 9)"
run_close "$TA" check
expect_eq "q1.1: check does not refuse for the missing Step 9 line" "no" "$(contains "$CO_OUT" "no Step 9 line in ## SDLC State of")"
expect_eq "q1.1b: …it says run writes it" "yes" "$(contains "$CO_OUT" 'run writes `- Step 9: (pending)`')"
run_close "$TA" run
expect_eq "q1.2: run on a plan with no Step 9 line closes rc 0" "0" "$CO_RC"
expect_eq "q1.3: …and the plan carries exactly one Step 9 line" "1" "$(step_lines "$TA/$PLAN_REL" 9)"
expect_eq "q1.4: …which is the delivered line" "yes" \
  "$(grep -qE '^- Step 9: delivered: ' "$TA/$PLAN_REL" && echo yes || echo no)"
expect_eq "q1.5: …written after the Step-8 block" "yes" \
  "$(awk '/^- Step 8: CLOSED /{s8=NR} /^- Step 9: delivered: /{s9=NR} END{print (s8 && s9 > s8) ? "yes" : "no"}' "$TA/$PLAN_REL")"

# A refusal on a plan with no Step 9 line writes no Step 9 line: the evidence file is gone,
# so the pre-flight refuses, and the plan is byte-for-byte what it was.
TD="$(mk_fixture t19d)"; advance_to "$TD" 8
rm -f "$TD/.bionic/docs/record/generic-evidence.md"
PRE_D="$(presence_state "$TD")"; PLAN_D_SHA="$(sha_of "$TD/$PLAN_REL")"
run_close "$TD" run
expect_eq "q1.6: a refused run on a plan with no Step 9 line exits 2" "2" "$CO_RC"
expect_eq "q1.6b: …the plan is byte-identical (no Step 9 line was written early)" "$PLAN_D_SHA" "$(sha_of "$TD/$PLAN_REL")"
expect_eq "q1.6c: …branch, tmp, continuation, current: and epic row untouched" "$PRE_D" "$(presence_state "$TD")"

# A plan written before T4, carrying a `- Step 9: (pending)` line by hand, still closes with
# one Step 9 line: close-out replaces the line it finds and adds none.
TE="$(mk_fixture t19e)"; advance_to "$TE" 8
awk '{ print } /^- Step 8: \(pending\)$/ { print "- Step 9: (pending)" }' "$TE/$PLAN_REL" > "$TE/plan.tmp" \
  && mv "$TE/plan.tmp" "$TE/$PLAN_REL"
expect_eq "q1.6d: precondition: the older plan carries its hand-written Step 9 line" "1" "$(step_lines "$TE/$PLAN_REL" 9)"
run_close "$TE" run
expect_eq "q1.6e: …it closes rc 0" "0" "$CO_RC"
expect_eq "q1.6f: …with exactly one Step 9 line, the delivered one" "1/yes" \
  "$(step_lines "$TE/$PLAN_REL" 9)/$(grep -qE '^- Step 9: delivered: ' "$TE/$PLAN_REL" && echo yes || echo no)"

TB="$(mk_fixture t19b)"; advance_to "$TB" 8
printf -- '---\ncanonical_sdlc_version: 14\n---\n\n# epic-fx\n\n## SDLC State\n\ncurrent: 4\n\n## Notes\n\nNo waves table yet.\n' > "$TB/$EPIC_REL"
PRE_B="$(presence_state "$TB")"; PLAN_B_SHA="$(sha_of "$TB/$PLAN_REL")"; EPIC_B_SHA="$(sha_of "$TB/$EPIC_REL")"
run_close "$TB" check
expect_eq "q1.7: check names the missing wave table" "yes" "$(contains "$CO_OUT" "no | wave | table")"
run_close "$TB" run
expect_eq "q1.8: run on an epic plan with no wave table refuses rc 2" "2" "$CO_RC"
expect_eq "q1.9: …naming the missing table" "yes" "$(contains "$CO_OUT" "no | wave | table")"
expect_eq "q1.10: …before any act" "no" "$(contains "$CO_OUT" "worktree-removed:")"
expect_eq "q1.11: …branch, tmp, continuation, current: and epic row untouched" "$PRE_B" "$(presence_state "$TB")"
expect_eq "q1.12: …plan and epic plan byte-identical" "$PLAN_B_SHA/$EPIC_B_SHA" "$(sha_of "$TB/$PLAN_REL")/$(sha_of "$TB/$EPIC_REL")"

TC="$(mk_fixture t19c)"; advance_to "$TC" 8
run_close "$TC" check
expect_eq "q1.13: check on the valid fixture names no missing line" "no" "$(contains "$CO_OUT" "WOULD REFUSE — no ")"
run_close "$TC" run
expect_eq "q1.14: run on the valid fixture still succeeds" "0" "$CO_RC"

# ============================================================
section "VER — wave-27 T4 (AC-7.2, D14, B3): the released version is the run's, never the tool's"
# ============================================================
# `VERSION` is the INSTALLED bionic's (`plugin_root`'s plugin.json). It is what attests, and
# it used to be what the delivered line, the epic row and the continuation header called the
# release too — wave-26 corrected two of them by hand. The release is the plan's own
# `release:` field now, and with no field no version is written. The tool here is THIS
# checkout's payload (run_close pins BIONIC_PLUGIN_ROOT), read the way co_version reads it.
TOOLV="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$REPO_ROOT/payload/.claude-plugin/plugin.json" | head -1)"
RELV="7.7.7-fixture"
expect_nonempty "VER0: the tool's version reads from its manifest" "$TOOLV"
expect_ne "VER0b: …and differs from the release the fixture names" "$RELV" "$TOOLV"

# epic_version_cell <project> -> the version cell of the epic's wave-01 row, trimmed.
epic_version_cell() {
  grep '^| 01 |' "$1/$EPIC_REL" | head -1 | awk -F'|' '{ v = $3; gsub(/^[ \t]+|[ \t]+$/, "", v); print v }'
}
# delivered_line <project> -> the plan's Step 9 delivered line.
delivered_line() { grep -m1 '^- Step 9: delivered: ' "$1/$PLAN_REL"; }

PV1="$(mk_fixture ver1)"; advance_to "$PV1" 8
awk -v r="$RELV" '{ print } /^walk: exempt$/ { print "release: " r }' "$PV1/$PLAN_REL" > "$PV1/plan.tmp" \
  && mv "$PV1/plan.tmp" "$PV1/$PLAN_REL"
expect_eq "VER1: precondition: the plan's frontmatter names the release" "1" "$(grep -c "^release: $RELV\$" "$PV1/$PLAN_REL" | tr -d ' ')"
run_close "$PV1" run
expect_eq "VER2: run with release: closes rc 0" "0" "$CO_RC"
DL1="$(delivered_line "$PV1")"
expect_nonempty "VER3: the delivered line is there to read" "$DL1"
expect_eq "VER4: …it carries the plan's release after the slug" "yes" "$(contains "$DL1" "wave-01-fixture $RELV — ")"
expect_eq "VER5: …and not the tool's version" "no" "$(contains "$DL1" "$TOOLV")"
expect_eq "VER6: the epic row's version cell is the plan's release" "$RELV" "$(epic_version_cell "$PV1")"
expect_eq "VER7: the continuation header carries the release" "yes" "$(contains "$(head -1 "$PV1/$CONT_REL")" "$RELV")"
expect_eq "VER8: …and not the tool's version" "no" "$(contains "$(head -1 "$PV1/$CONT_REL")" "$TOOLV")"
expect_eq "VER9: attested-by: keeps the tool's own version, on both blocks" "2" \
  "$(grep -c "^  attested-by: close-out.sh $TOOLV\$" "$PV1/$PLAN_REL" | tr -d ' ')"

PV2="$(mk_fixture ver2)"; advance_to "$PV2" 8
expect_eq "VER10: precondition: this plan names no release" "0" "$(grep -c '^release:' "$PV2/$PLAN_REL" | tr -d ' ')"
run_close "$PV2" run
expect_eq "VER11: run with no release: closes rc 0" "0" "$CO_RC"
DL2="$(delivered_line "$PV2")"
expect_nonempty "VER12: the delivered line is there to read" "$DL2"
expect_eq "VER13: …it writes no version: the slug runs straight into the dash" "yes" "$(contains "$DL2" "wave-01-fixture — ")"
expect_eq "VER14: …and never the tool's" "no" "$(contains "$DL2" "$TOOLV")"
expect_eq "VER15: the epic row is there, with no version in its cell" "—" "$(epic_version_cell "$PV2")"
expect_eq "VER16: the continuation header names the wave" "yes" "$(contains "$(head -1 "$PV2/$CONT_REL")" "wave-01-fixture")"
expect_eq "VER17: …with no version in it" "no" "$(contains "$(head -1 "$PV2/$CONT_REL")" "$TOOLV")"
expect_eq "VER18: attested-by: still names the tool's version" "2" \
  "$(grep -c "^  attested-by: close-out.sh $TOOLV\$" "$PV2/$PLAN_REL" | tr -d ' ')"

# ============================================================
section "FIX-SHAPE — wave-27 T4 (AC-7.3, D14): the fixture builders plant nothing the tools write"
# ============================================================
# The builders are read out of this file. A planted `current: 8` or Step 9 line is what hid
# B1 and B2 from every run of this suite, so the read is the whole of each builder's body.
FS_BUILDERS="fixture_plan_text fixture_epic_text mk_fixture mk_census_fixture mk_census_fixture_nowt"
# builder_bodies <suite file> -> every line of those functions' bodies.
builder_bodies() {
  awk -v names=" $FS_BUILDERS " '
    match($0, /^[a-z_]+\(\) \{/) { n = substr($0, 1, RLENGTH - 4); inb = (index(names, " " n " ") > 0); next }
    inb && /^\}/ { inb = 0; next }
    inb { print }' "$1"
}
# builder_plants <suite file> -> the builder lines that plant what a tool writes.
builder_plants() {
  builder_bodies "$1" | grep -E 'current:[[:space:]]*8([^0-9]|$)|Step[[:space:]]+9|fixture_plan_text[^>]*[[:space:]]8([[:space:]]|$)'
}
FS_SUITE="$REPO_ROOT/tests/close-out.test.sh"
FS_BODIES="$(builder_bodies "$FS_SUITE")"
expect_eq "FS1: the extractor reads the plan builder's SDLC State" "yes" "$(contains "$FS_BODIES" "## SDLC State")"
expect_eq "FS2: …and a line of each builder (plan text, mk_fixture, the census heredocs, epic text)" "yes/yes/yes/yes" \
  "$(contains "$FS_BODIES" "current: \${current}")/$(contains "$FS_BODIES" "fixture_plan_text \"\$aroot\"")/$(contains "$FS_BODIES" "PLAN_CENSUS")/$(contains "$FS_BODIES" "# epic-fx")"
expect_empty "FS3: no builder plants current: 8 or a Step 9 line" "$(builder_plants "$FS_SUITE")"
# THE PAIRED POSITIVE: the same extractor on a copy with the old Step 9 line put back.
FS_MUT="$SANDBOX/fs-mut.test.sh"
awk '{ print } /^- Step 8: \(pending\)$/ && !d { print "- Step 9: (pending)"; d = 1 }' "$FS_SUITE" > "$FS_MUT"
expect_nonempty "FS4: …a copy with '- Step 9: (pending)' put back in a builder is caught" "$(builder_plants "$FS_MUT")"
sed 's/fixture_plan_text "\$aroot" 7/fixture_plan_text "$aroot" 8/' "$FS_SUITE" > "$FS_MUT"
expect_nonempty "FS5: …and so is a builder handing the plan current 8" "$(builder_plants "$FS_MUT")"

# ============================================================
section "E2E — wave-27 T4 (AC-7.1 close-out half, D14, B1): from Step 7 with no Step 9 line, the tools close the run"
# ============================================================
# The target, AC-7.1: no hand edit. The real `session-poker.sh current 8` moves the plan,
# then `close-out.sh run` delivers. The session is bound to the plan the way engagement binds
# it (tests/lib/bound-marker.sh, the one bound-marker builder).
#
# RE-AUTHORED BY wave-27 T14 from T4's pin of the refusal (A-T4.1). The verb no longer
# dry-commits the plan at Step 8, where the gate asked for the Step-8 block only close-out
# writes; it asks lib/proof.sh `facts_state` at the working head instead (D3). `mk_fixture`
# holds what a run at Step 7 owes there (`plant_facts`: at `rigor: single`, `scale: wave`, the
# floor and the critic's three questions at piece scope and two at whole scope), so `current 8`
# moves the plan and `close-out.sh run` then delivers, with no hand edit.
PE="$(mk_fixture e2e)"
E2E_SID="closeout-e2e-1"
expect_eq "E2E0: precondition: the fixture is at current: 7 with no Step 8 block written and no Step 9 line" "7/0" \
  "$(sed -n 's/^current: //p' "$PE/$PLAN_REL")/$(step_lines "$PE/$PLAN_REL" 9)"
expect_eq "E2E0b: precondition: it carries the six facts the single wave run owes" "6" \
  "$(/usr/bin/grep -c '^proved: ' "$PE/$PLAN_REL" | tr -d ' ')"
expect_eq "E2E0c: precondition: …and a base-sha naming a commit at or before the readings' head" "yes" \
  "$(b="$(sed -n 's/^base-sha: //p' "$PE/$PLAN_REL")"; [ -n "$b" ] && fixture_git "$PE" merge-base --is-ancestor "$b" wave/01-fixture && echo yes || echo no)"
( in_fixture "$PE" || exit 1; . "$REPO_ROOT/tests/lib/bound-marker.sh"; bound_marker "$PE" "$E2E_SID" "$PE/$PLAN_REL" )
( in_fixture "$PE" || exit 9
  HOME="$SB_HOME" CLAUDE_PROJECT_DIR="" BIONIC_CLAUDE_HOME="$SB_HOME/.claude" \
    CLAUDE_CODE_SESSION_ID="$E2E_SID" bash "$BIONIC_HOOKS_DIR/session-poker.sh" current 8 ) > "$SANDBOX/e2e-poker" 2>&1
E2E_POKER_RC=$?
E2E_POKER_OUT="$(cat "$SANDBOX/e2e-poker")"
expect_eq "E2E1: AC-7.1 the real current 8 is admitted on the facts (exit 0)" "0" "$E2E_POKER_RC"
expect_eq "E2E2: …saying the facts hold, not asking for the Step-8 block close-out writes" "yes/no" \
  "$(contains "$E2E_POKER_OUT" "every fact the run owes holds at")/$(contains "$E2E_POKER_OUT" "missing required field(s): merge worktree-removed")"
expect_eq "E2E3: …and the plan reads current: 8" "8" "$(sed -n 's/^current: //p' "$PE/$PLAN_REL")"
run_close "$PE" run
expect_eq "E2E4: AC-7.1 then close-out.sh run delivers (rc 0)" "0" "$CO_RC"
expect_eq "E2E5: …the plan carries the delivered line" "yes" "$( [ -n "$(delivered_line "$PE")" ] && echo yes || echo no)"
expect_eq "E2E6: …and reads closed" "1" "$(run_open_rc "$PE/$PLAN_REL")"

# THE SAME FUNCTION REFUSES IN CLOSE-OUT (D3). A fixture whose structure reading is the newest and
# fails: `check` says it would refuse, naming the failing line, and `run` refuses with nothing done.
PF="$(mk_fixture e2e-fail)"; advance_to "$PF" 8
bash -c '. "$1/proof.sh" && proof_add_line "$2" "$(proof_line review "$3" 2026-10-04T13:00:00Z record/wave-01-fixture/structure-fail.md structure w-read fail piece)"' \
  _ "$REPO_ROOT/payload/scripts/lib" "$PF/$PLAN_REL" "$(fixture_git "$PF" rev-parse wave/01-fixture)" > "$PF/$PLAN_REL.n" \
  && mv "$PF/$PLAN_REL.n" "$PF/$PLAN_REL"
run_close "$PF" check
expect_eq "E2E7: check WOULD REFUSE on the facts" "yes" "$(contains "$CO_OUT" "facts: WOULD REFUSE — the facts the run owes do not all hold at the working head")"
expect_eq "E2E8: …naming the failing reading and its evidence" "yes" \
  "$(contains "$CO_OUT" "$(printf 'review\tstructure\tbionic:critic\tpiece\tfailing\trecord/wave-01-fixture/structure-fail.md')")"
PF_SHA="$(sha_of "$PF/$PLAN_REL")"
run_close "$PF" run
expect_eq "E2E9: run refuses (rc 2)" "2" "$CO_RC"
expect_eq "E2E10: …in the same words" "yes" "$(contains "$CO_OUT" "bionic: close-out refused — the facts the run owes do not all hold at the working head")"
expect_eq "E2E11: …the plan untouched and wt/01-x still standing (nothing was done)" "$PF_SHA/yes" \
  "$(sha_of "$PF/$PLAN_REL")/$(branch_exists "$PF" wt/01-x)"
PG="$(mk_fixture e2e-holds)"; advance_to "$PG" 8
run_close "$PG" check
expect_eq "E2E12: …while on a fixture whose facts hold, check says so (the extractor read E2E7's line on a real plan)" "yes" \
  "$(contains "$CO_OUT" "facts: every fact the run owes holds at $(fixture_git "$PG" rev-parse wave/01-fixture)")"

# A RELEASE THAT WOULD SPLIT A CELL (A-orch-28): a `|` in `release:` is refused before any act.
PR="$(mk_fixture e2e-pipe)"; advance_to "$PR" 8
sed 's/^archive-root: /release: 1.2|3\narchive-root: /' "$PR/$PLAN_REL" > "$PR/$PLAN_REL.n" && mv "$PR/$PLAN_REL.n" "$PR/$PLAN_REL"
expect_eq "E2E13: precondition: the plan's frontmatter carries release: 1.2|3" "1" "$(/usr/bin/grep -c '^release: 1.2|3$' "$PR/$PLAN_REL" | tr -d ' ')"
PR_SHA="$(sha_of "$PR/$PLAN_REL")"
run_close "$PR" run
expect_eq "E2E14: A-orch-28 run refuses a release holding a | (rc 2)" "2" "$CO_RC"
expect_eq "E2E15: …saying why, before any act" "yes" "$(contains "$CO_OUT" "the release: field of the plan holds a | (1.2|3), which would split the version cell of the epic row")"
expect_eq "E2E16: …the plan untouched and wt/01-x still standing" "$PR_SHA/yes" "$(sha_of "$PR/$PLAN_REL")/$(branch_exists "$PR" wt/01-x)"

# ============================================================
section "4f — REQ-1 (AC-1.1–1.4): the shipped table is found once; the ADR cell is read, not marked"
# ============================================================
# D17 (wave-24 T1). `epic_has_row`, `act_epic` and `presence_missing` each used their own idea
# of "the wave table": a file-wide grep, the FIRST `| wave |` header, any `| wave |` header. A
# planned table (`| wave | … | status |`) above or beside the shipped one made all three disagree.
# One locator now picks the table whose header's first cell is `wave` AND which has a `shipped`
# cell. The helpers below read the fixture with their OWN awk, not the script's.

# table_rows <file> <kind> -> the data rows (not header, not rule) of the table whose header
# is `| wave |` AND carries (kind=shipped) or lacks (kind=planned) a `shipped` cell.
table_rows() {
  awk -v kind="$2" '
    function has_shipped(line,   n, i, c, a) {
      n = split(line, a, "|")
      for (i = 2; i < n; i++) { c = a[i]; gsub(/^[ \t]+|[ \t]+$/, "", c); if (c == "shipped") return 1 }
      return 0
    }
    /^\|[ \t]*wave[ \t]*\|/ && !intable {
      if ((kind == "shipped") == has_shipped($0)) { intable = 1; hdr = 1; next }
    }
    intable && !/^\|/ { intable = 0 }
    intable { if (hdr) { hdr = 0; next } print }
  ' "$1"
}
# rows_with_wave <file> <kind> <num> -> how many data rows of that table lead with <num>.
rows_with_wave() {
  table_rows "$1" "$2" | grep -cE "^\|[[:space:]]*$3[[:space:]]*\|" | tr -d ' '
}

# epic_planned_first -> an epic with a planned table ABOVE the shipped one. The planned table
# carries a `| 01 |` row (this fixture's own wave number), and a headerless `## Ladder`
# table carries another; neither is the shipped table.
epic_planned_first() {
  cat <<'EPIC78'
---
canonical_sdlc_version: 14
---

# epic-fx

## SDLC State

current: 4

## Waves — planned

| wave | version | slug | brief | status |
|---|---|---|---|---|
| 01 | 0.0.2 | fixture | a planned wave | planned |
| 09 | 0.0.9 | other | another | planned |

## Ladder

| 01 | step | one |
|---|---|---|
| 01 | step | two |

## Waves — shipped

| wave | version | plan | spec / requirements | ADRs | shipped |
|---|---|---|---|---|---|
| 00 | 0.0.1 | `wave-00-seed.plan.md` | — | — | 2026-01-01 |

## Notes

Nothing here.
EPIC78
}

# §78.1 — a `| 01 |` row that is not in the shipped table is not "already listed".
T78="$(mk_fixture t78a)"; advance_to "$T78" 8
epic_planned_first > "$T78/$EPIC_REL"
expect_eq "78.0: the extractor reads the shipped table (wave 00 is one row there)" "1" \
  "$(rows_with_wave "$T78/$EPIC_REL" shipped 00)"
expect_eq "78.0b: …and the planned table (wave 01 is one row there; wave 00 none)" "1/0" \
  "$(rows_with_wave "$T78/$EPIC_REL" planned 01)/$(rows_with_wave "$T78/$EPIC_REL" planned 00)"
expect_eq "78.0c: …and wave 01 is in the shipped table zero times before the run" "0" \
  "$(rows_with_wave "$T78/$EPIC_REL" shipped 01)"
run_close "$T78" check
expect_eq "78.1a: check names an epic-row line" "yes" "$(contains "$CO_OUT" "epic-row: ")"
expect_eq "78.1b: …and does not call wave 01 already listed" "no" "$(contains "$CO_OUT" "already listed")"
run_close "$T78" run
expect_eq "78.1c: run exits 0" "0" "$CO_RC"
expect_eq "78.1d: …the shipped table holds the wave-01 row" "1" "$(rows_with_wave "$T78/$EPIC_REL" shipped 01)"
expect_eq "78.1e: …the epic-row line says appended, not already listed" "yes" \
  "$(contains "$CO_OUT" "epic-row: wave 01 appended to epic.plan.md")"

# §78.2 — the planned table sits first; the row still lands in the shipped one.
T78B="$(mk_fixture t78b)"; advance_to "$T78B" 8
epic_planned_first > "$T78B/$EPIC_REL"
PLANNED_BEFORE="$(table_rows "$T78B/$EPIC_REL" planned)"
SHIPPED_BEFORE="$(table_rows "$T78B/$EPIC_REL" shipped | wc -l | tr -d ' ')"
expect_eq "78.2.0: the planned table has two rows and the shipped one (before) has one" "2/1" \
  "$(printf '%s\n' "$PLANNED_BEFORE" | wc -l | tr -d ' ')/$SHIPPED_BEFORE"
run_close "$T78B" run
expect_eq "78.2a: run exits 0" "0" "$CO_RC"
expect_eq "78.2b: the shipped table's row count rose by exactly one" "$((SHIPPED_BEFORE + 1))" \
  "$(table_rows "$T78B/$EPIC_REL" shipped | wc -l | tr -d ' ')"
expect_eq "78.2c: …the planned table is unchanged" "$PLANNED_BEFORE" "$(table_rows "$T78B/$EPIC_REL" planned)"
expect_eq "78.2d: …and the row sits after the existing shipped row (appended, not inserted above it)" "00 01" \
  "$(table_rows "$T78B/$EPIC_REL" shipped | sed -E 's/^\|[[:space:]]*([0-9]+)[[:space:]]*\|.*/\1/' | tr '\n' ' ' | sed 's/ $//')"
run_close "$T78B" run
expect_eq "78.2e: a second run adds no second row (reader and writer agree on the table)" "1" \
  "$(rows_with_wave "$T78B/$EPIC_REL" shipped 01)"

# §78.3 — an epic whose only `| wave |` table is the planned one has nowhere to put the row.
T78C="$(mk_fixture t78c)"; advance_to "$T78C" 8
epic_planned_first | awk '
  /^## Waves — shipped/ { skip = 1 }
  /^## Notes/ { skip = 0 }
  !skip { print }
' > "$T78C/epic.tmp" && mv "$T78C/epic.tmp" "$T78C/$EPIC_REL"
expect_eq "78.3.0: the fixture has a planned table and no shipped one" "1/0" \
  "$(rows_with_wave "$T78C/$EPIC_REL" planned 09)/$(table_rows "$T78C/$EPIC_REL" shipped | wc -l | tr -d ' ')"
PRE_C="$(presence_state "$T78C")"; PLAN_C_SHA="$(sha_of "$T78C/$PLAN_REL")"; EPIC_C_SHA="$(sha_of "$T78C/$EPIC_REL")"
run_close "$T78C" check
expect_eq "78.3a: check says it would refuse, naming the shipped table" "yes" \
  "$(contains "$CO_OUT" "presence: WOULD REFUSE — no | wave | table with a shipped column")"
run_close "$T78C" run
expect_eq "78.3b: run refuses rc 2" "2" "$CO_RC"
expect_eq "78.3c: …naming the missing shipped table" "yes" "$(contains "$CO_OUT" "table with a shipped column")"
expect_eq "78.3d: …before any act" "no" "$(contains "$CO_OUT" "worktree-removed:")"
expect_eq "78.3e: …branch, tmp, continuation and plans untouched" \
  "$PRE_C/$PLAN_C_SHA/$EPIC_C_SHA" \
  "$(presence_state "$T78C")/$(sha_of "$T78C/$PLAN_REL")/$(sha_of "$T78C/$EPIC_REL")"

# ---------- §86: the ADR cell reads the spec's `adrs:` line ----------

# adr_cell <project> -> the trimmed ADRs cell (column 5) of the wave-01 row in the shipped table.
adr_cell() {
  table_rows "$1/$EPIC_REL" shipped | grep -E '^\|[[:space:]]*01[[:space:]]*\|' | awk -F'|' '
    { c = $6; gsub(/^[ \t]+|[ \t]+$/, "", c); print c }'
}
# set_plan_keys <project> <spec-line|-> <adrs-line|-> -> inserts the given frontmatter lines
# after `walk:` ("-" inserts nothing).
set_plan_keys() {
  local p="$1/$PLAN_REL" extra=""
  [ "$2" = "-" ] || extra="${extra}$2"$'\n'
  [ "$3" = "-" ] || extra="${extra}$3"$'\n'
  EXTRA="$extra" awk '{ print } /^walk:/ { printf "%s", ENVIRON["EXTRA"] }' "$p" > "$p.tmp" && mv "$p.tmp" "$p"
}
# mk_spec <project> <adrs-line|-> -> writes the spec the plan names, with or without `adrs:`.
mk_spec() {
  mkdir -p "$1/.bionic/docs/specs/epic-fx"
  {
    printf -- '---\nsdlc-step: 2\n'
    [ "$2" = "-" ] || printf '%s\n' "$2"
    printf -- '---\n\n# fixture spec\n'
  } > "$1/.bionic/docs/specs/epic-fx/wave-01-fixture.spec.md"
}
SPEC_KEY="spec: specs/epic-fx/wave-01-fixture.spec.md"

T86="$(mk_fixture t86a)"; advance_to "$T86" 8
set_plan_keys "$T86" "$SPEC_KEY" "-"
mk_spec "$T86" "adrs: adrs/epic-fx/adr-040-first-thing.md · adrs/epic-fx/adr-041-second-thing.md"
run_close "$T86" run
expect_eq "86.0: run exits 0" "0" "$CO_RC"
expect_eq "86.1: the ADRs cell reads the spec's two ADRs, numbers joined by a comma" "040, 041" "$(adr_cell "$T86")"

T86B="$(mk_fixture t86b)"; advance_to "$T86B" 8
set_plan_keys "$T86B" "$SPEC_KEY" "-"
mk_spec "$T86B" "-"
run_close "$T86B" run
expect_eq "86.2a: a wave with no adrs: in spec or plan keeps the marker (run exits 0)" "0" "$CO_RC"
expect_eq "86.2b: …the cell is exactly the marker" "<fill: ADRs>" "$(adr_cell "$T86B")"

T86C="$(mk_fixture t86c)"; advance_to "$T86C" 8
set_plan_keys "$T86C" "$SPEC_KEY" "adrs: adrs/epic-fx/adr-039-from-the-plan.md"
mk_spec "$T86C" "-"
run_close "$T86C" run
expect_eq "86.3: a spec without adrs: falls back to the plan's adrs:" "039" "$(adr_cell "$T86C")"

T86D="$(mk_fixture t86d)"; advance_to "$T86D" 8
set_plan_keys "$T86D" "-" "adrs: adrs/epic-fx/adr-038-from-the-plan.md"
run_close "$T86D" run
expect_eq "86.4: a plan whose spec file is not on disk falls back to the plan's adrs:" "038" "$(adr_cell "$T86D")"

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

P5="$(mk_fixture p5)"; advance_to "$P5" 8
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
P6="$(mk_fixture p6)"; advance_to "$P6" 8
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

# ---------- wave-25 T15: the workspace record (`workspaces-<sid>.state`, written by
# ---------- spawn-worktree.sh create) and the gate file (`gate-<sid>.state`, written by
# ---------- hooks/permission-answer.sh) are session-keyed too. B (still live from above)
# ---------- keeps both through A's close-out; A's own and dead D's go.

P7="$(mk_fixture p7)"; advance_to "$P7" 8
for c in workspaces gate; do
  for s in "$TS_SID_A" "$TS_SID_B" "$TS_SID_D"; do
    printf '%s state for %s\n' "$c" "$s" > "$P7/.bionic/tmp/$c-$s.state"
  done
done
run_close_as "$TS_SID_A" "$P7" run
expect_eq "5.10: run (as A, with B live and D dead, workspaces and gate files only) exits 0" "0" "$CO_RC"
for c in workspaces gate; do
  expect_eq "5.11 ($c): live B's $c file survives A's close-out" "yes" \
    "$(tmp_file_exists "$P7" "$c" "$TS_SID_B")"
  expect_eq "5.12 ($c): A's own $c file is removed" "no" \
    "$(tmp_file_exists "$P7" "$c" "$TS_SID_A")"
  expect_eq "5.13 ($c): dead D's $c file is removed" "no" \
    "$(tmp_file_exists "$P7" "$c" "$TS_SID_D")"
done
expect_eq "5.14: only B's 2 spared files remain under .bionic/tmp/" "2" "$(tmp_entries "$P7")"

section "CARRY — wave-28 T17 (AC-8.7, D21): close-out writes every open deferral, with its sentence, under ## Deferrals of the continuation"
# ============================================================
# A deferral is held to its debts: the plan carries one `deferred:` line per finding the table
# defers (`session-poker.sh proof-add` writes it; `finding-stated` adds ` stated="<sentence>"`), and
# close-out carries each into the continuation, in the one form the next wave's Step 1 card reads:
#
#   deferred: <record>#<n> <S> <reach> "<title>" stated="<sentence|->" from=<wave name>
#
# in the plan's order, `-` for a deferral with no sentence, a `"` or a `\` in a sentence written
# `\"` and `\\` as the plan holds it. A `check:` line is a check owed, not a deferral, and is not
# carried. The heading is written whether or not there is anything under it, so a continuation
# that reports no deferral differs from one written before the heading existed.
CARRY_REC="record/wave-01-fixture/rev.md"
# carry_plant <project> <line>... -> each line inside the plan's ## SDLC State, after approved-by:
carry_plant() {
  local proj="$1" plan="$1/$PLAN_REL" l; shift
  case "$proj" in "$SANDBOX"/*) : ;; *) echo "carry_plant: refusing outside the sandbox: '$proj'" >&2; return 1 ;; esac
  local lines=""
  for l in "$@"; do lines="${lines}${l}
"; done
  CARRY_LINES="$lines" awk '{ print } /^approved-by: / && !d { printf "%s", ENVIRON["CARRY_LINES"]; d = 1 }' "$plan" > "$plan.carry" \
    && mv "$plan.carry" "$plan"
}
# carry_section <continuation> -> what stands under the heading `## Deferrals`, up to the next `## `,
# blank lines dropped; nothing when there is no such heading.
carry_section() {
  awk '/^## / { s = ($0 == "## Deferrals"); next } s && NF { print }' "$1"
}
CARRY_W="wave-01-fixture"
CARRY_Q1='Said \"go\" \\ now | here'   # the sentence: Said "go" \ now | here, as the plan holds it
PC="$(mk_fixture carry1)"; advance_to "$PC" 8
carry_plant "$PC" \
  "deferred: $CARRY_REC#2 S3 on \"second, written first\" stated=\"The second sentence.\"" \
  "deferred: $CARRY_REC#1 S2 off \"first, unstated\"" \
  "check: $CARRY_REC#4 S1 off \"a settled check, not a deferral\" settled=S2:off by=record/wave-01-fixture/chk.md" \
  "deferred: $CARRY_REC#3 S2 off \"third, quoted\" stated=\"$CARRY_Q1\""
# The check: line is SETTLED (wave-28 T14, ruling A-orch-165): since T41 an open check holds the step, so
# the fixture settles it, in the form the retired finding-check wrote (settled= and by=; wave-31 T32 removed
# the verb and the hold, and an old line binds nothing), at a rating the table defers (S2 off).
expect_eq "CARRY-0 precondition: the plan carries three deferred: lines and one check: line inside its SDLC State" "3 1" \
  "$(awk '/^## /{ s = ($0 ~ /^## SDLC State/) } s && /^deferred: /{ d++ } s && /^check: /{ c++ } END { print d + 0, c + 0 }' "$PC/$PLAN_REL")"
run_close "$PC" run
expect_eq "CARRY-1 run exits 0 over a plan carrying deferred: and check: lines (the gate and the parsers admit it)" "0" "$CO_RC"
expect_eq "CARRY-2 the continuation carries the heading ## Deferrals exactly once, flush left" "1" \
  "$(/usr/bin/grep -c '^## Deferrals$' "$PC/$CONT_REL" | tr -d ' ')"
expect_nonempty "CARRY-3 precondition: the extractor finds lines under the heading" "$(carry_section "$PC/$CONT_REL")"
expect_eq "CARRY-4 …one line per open deferral, in the plan's order, in the fixed form (a check: line is not carried)" \
"deferred: $CARRY_REC#2 S3 on \"second, written first\" stated=\"The second sentence.\" from=$CARRY_W
deferred: $CARRY_REC#1 S2 off \"first, unstated\" stated=\"-\" from=$CARRY_W
deferred: $CARRY_REC#3 S2 off \"third, quoted\" stated=\"$CARRY_Q1\" from=$CARRY_W" \
  "$(carry_section "$PC/$CONT_REL")"
expect_eq "CARRY-5 …and the heading comes after the template's Next wave section and before the Resume instruction" "yes" \
  "$(awk '/^## Next wave/ { a = NR } /^## Deferrals$/ { b = NR } /^## Resume instruction/ { c = NR } END { print (a && b > a && c > b) ? "yes" : "no" }' "$PC/$CONT_REL")"
expect_eq "CARRY-6 the plan close-out closed still reads closed (run_open says 1)" "1" "$(run_open_rc "$PC/$PLAN_REL")"

# none: the heading and nothing under it
PN="$(mk_fixture carry2)"; advance_to "$PN" 8
run_close "$PN" run
expect_eq "CARRY-7 a run with no deferral exits 0" "0" "$CO_RC"
expect_eq "CARRY-8 …and writes the heading ## Deferrals once, with nothing under it" "1|0" \
  "$(/usr/bin/grep -c '^## Deferrals$' "$PN/$CONT_REL" | tr -d ' ')|$(carry_section "$PN/$CONT_REL" | wc -l | tr -d ' ')"

# an existing continuation is never overwritten: a missing heading is appended, a present one is left
PE="$(mk_fixture carry3)"; advance_to "$PE" 8
carry_plant "$PE" "deferred: $CARRY_REC#1 S2 off \"kept\" stated=\"A kept sentence.\""
mkdir -p "$PE/${CONT_REL%/*}"
printf '# continuation — hand written\n\n## Resume instruction\n\nedited by a person\n' > "$PE/$CONT_REL"
run_close "$PE" run
expect_eq "CARRY-9 a continuation that exists without the heading: run exits 0" "0" "$CO_RC"
expect_eq "CARRY-10 …its own text is kept, byte for byte, at the top" "# continuation — hand written

## Resume instruction

edited by a person" "$(head -5 "$PE/$CONT_REL")"
expect_eq "CARRY-11 …and the deferral is appended under a ## Deferrals heading" \
  "deferred: $CARRY_REC#1 S2 off \"kept\" stated=\"A kept sentence.\" from=$CARRY_W" "$(carry_section "$PE/$CONT_REL")"
PH="$(mk_fixture carry4)"; advance_to "$PH" 8
carry_plant "$PH" "deferred: $CARRY_REC#1 S2 off \"not carried over a written heading\" stated=\"A sentence.\""
mkdir -p "$PH/${CONT_REL%/*}"
printf '# continuation — hand written\n\n## Deferrals\n\nnone, said the person\n' > "$PH/$CONT_REL"
run_close "$PH" run
expect_eq "CARRY-12 a continuation that already carries the heading: run exits 0" "0" "$CO_RC"
# wave-28 T50 (A-orch-74) supersedes A-T17.6's "with the heading, never touched": the merge adds the run's
# own line it lacks under the heading, after the line a person wrote there, which stays
expect_eq "CARRY-13 …the line a person wrote stays, and the run's own deferral it lacked is added under it" \
  "none, said the person
deferred: $CARRY_REC#1 S2 off \"not carried over a written heading\" stated=\"A sentence.\" from=$CARRY_W" \
  "$(carry_section "$PH/$CONT_REL")"

# check never writes it, and names what run would carry
PK="$(mk_fixture carry5)"; advance_to "$PK" 8
carry_plant "$PK" "deferred: $CARRY_REC#1 S2 off \"checked\""
run_close "$PK" check
expect_eq "CARRY-14 check exits 0 and writes no continuation" "0|no" \
  "$CO_RC|$([ -e "$PK/$CONT_REL" ] && echo yes || echo no)"

# the mutation arm: a doctored copy of close-out.sh with the heading dropped from the template
CARRY_MUT="$(mktemp -d "${TMPDIR:-/tmp}/close-out-carry-mut.XXXXXX")"
mkdir -p "$CARRY_MUT/scripts"; ln -s "$REPO_ROOT/payload/scripts/lib" "$CARRY_MUT/scripts/lib"
ln -s "$REPO_ROOT/payload/scripts/card.sh" "$CARRY_MUT/scripts/card.sh"   # close-out reads the inherited deferrals through it (T43)
sed "s/printf '## Deferrals/printf '## Carried over/" "$SCRIPT" > "$CARRY_MUT/scripts/close-out.sh"
expect_eq "CARRY-mut0 the doctored copy differs from the script in exactly one line (the doctor took)" "1" \
  "$(diff "$SCRIPT" "$CARRY_MUT/scripts/close-out.sh" | /usr/bin/grep -c '^>')"
PM="$(mk_fixture carry6)"; advance_to "$PM" 8
carry_plant "$PM" "deferred: $CARRY_REC#1 S2 off \"mutant\" stated=\"A sentence.\""
( cd "$PM" && HOME="$SB_HOME" CLAUDE_PROJECT_DIR="" BIONIC_PLUGIN_ROOT="$REPO_ROOT/payload" BIONIC_CLAUDE_HOME="$SB_HOME/.claude" \
    bash "$CARRY_MUT/scripts/close-out.sh" "$PM/$PLAN_REL" run ) > "$SANDBOX/carry-mut.out" 2>&1
CARRY_MRC=$?
expect_eq "CARRY-mut1 the doctored run still closes and writes its continuation (the mutant runs)" "0|yes" \
  "$CARRY_MRC|$([ -s "$PM/$CONT_REL" ] && echo yes || echo no)"
expect_eq "CARRY-mut2 …and the doctored continuation has no ## Deferrals heading, so CARRY-2 and CARRY-4 go red on it" "0|0" \
  "$(/usr/bin/grep -c '^## Deferrals$' "$PM/$CONT_REL" | tr -d ' ')|$(carry_section "$PM/$CONT_REL" | wc -l | tr -d ' ')"
rm -rf "$CARRY_MUT"


# ============================================================
# CARRY, continued — wave-28 T43 (AC-8.10, D21): what the run inherited and did not settle is carried
# ============================================================
# The run's requirements file disposes of the deferrals the newest continuation under the docs root
# carries (never the run's own; A-orch-64), under
# `## Inherited deferrals`: `adopted: <id> as REQ-<n>`, `again: <id>`, `closed: <id> <reason>`.
# Close-out writes, after this run's own lines, every inherited line deferred again and every one the
# requirements file did not dispose of, each as the old continuation wrote it, its `from=` kept. An
# adopted or a closed one is not carried. The reading is card.sh's (`card.sh inherited <plan>`), the
# one the Step 1 card listed them from.
CARRY_PREV="wave-00-prev"
CARRY_PR="record/$CARRY_PREV/read-adversarial-p2.md"
CARRY_P1="deferred: $CARRY_PR#1 S2 off \"deferred again\" stated=\"Kept \\\"as is\\\".\" from=$CARRY_PREV"
CARRY_P2="deferred: $CARRY_PR#2 S3 on \"left undisposed\" stated=\"-\" from=$CARRY_PREV"
CARRY_P3="deferred: $CARRY_PR#3 S3 on \"adopted\" stated=\"-\" from=$CARRY_PREV"
CARRY_P4="deferred: $CARRY_PR#4 S2 off \"closed\" stated=\"-\" from=$CARRY_PREV"
# carry_prev <project> -> the predecessor's continuation, carrying the four lines above under
# ## Deferrals: the only continuation under the docs root until close-out writes this run's own
carry_prev() {
  local proj="$1"
  case "$proj" in "$SANDBOX"/*) : ;; *) echo "carry_prev: refusing outside the sandbox: '$proj'" >&2; return 1 ;; esac
  mkdir -p "$proj/.bionic/docs/record/$CARRY_PREV"
  printf '%s\n' "# continuation — $CARRY_PREV" "" "## Deferrals" "" "$CARRY_P1" "$CARRY_P2" "$CARRY_P3" "$CARRY_P4" \
    "" "## Resume instruction" "" "nothing" > "$proj/.bionic/docs/record/$CARRY_PREV/continuation.md"
}
# carry_req <project> <line>... -> the plan names a requirements file whose ## Inherited deferrals holds the lines
carry_req() {
  local proj="$1" plan="$1/$PLAN_REL" rel="specs/epic-fx/wave-01-fixture.requirements.md"; shift
  case "$proj" in "$SANDBOX"/*) : ;; *) echo "carry_req: refusing outside the sandbox: '$proj'" >&2; return 1 ;; esac
  mkdir -p "$proj/.bionic/docs/specs/epic-fx"
  { printf '# fixture requirements\n\n## Goal\n\nThe fixture.\n\n## Inherited deferrals\n\n'; printf '%s\n' "$@"; } \
    > "$proj/.bionic/docs/$rel"
  sed "s#^walk: exempt\$#&\\
requirements: $rel#" "$plan" > "$plan.req" && mv "$plan.req" "$plan"
}
PI="$(mk_fixture carry7)"; advance_to "$PI" 8
carry_prev "$PI"
carry_req "$PI" "again: $CARRY_PR#1" "adopted: $CARRY_PR#3 as REQ-1" "closed: $CARRY_PR#4 fixed in passing"
carry_plant "$PI" "deferred: $CARRY_REC#1 S2 off \"this run's own\""
expect_eq "CARRY-15 precondition: the predecessor's continuation carries four lines, the plan names its requirements file, which holds three disposals" \
  "4|1|3" "$(carry_section "$PI/.bionic/docs/record/$CARRY_PREV/continuation.md" | wc -l | tr -d ' ')|$(/usr/bin/grep -c '^requirements: ' "$PI/$PLAN_REL" | tr -d ' ')|$(/usr/bin/grep -cE '^(again|adopted|closed): ' "$PI/.bionic/docs/specs/epic-fx/wave-01-fixture.requirements.md" | tr -d ' ')"
run_close "$PI" run
expect_eq "CARRY-16 run exits 0 over a run that inherited four deferrals" "0" "$CO_RC"
expect_nonempty "CARRY-17 precondition: the extractor finds lines under the heading" "$(carry_section "$PI/$CONT_REL")"
expect_eq "CARRY-18 this run's own line first, then the one deferred again and the undisposed one, as written, from= kept" \
"deferred: $CARRY_REC#1 S2 off \"this run's own\" stated=\"-\" from=$CARRY_W
$CARRY_P1
$CARRY_P2" "$(carry_section "$PI/$CONT_REL")"
expect_absent "CARRY-19 …the adopted one is not carried" "\"adopted\"" "$(carry_section "$PI/$CONT_REL")"
expect_absent "CARRY-19a …nor the closed one" "\"closed\"" "$(carry_section "$PI/$CONT_REL")"

# a run whose plan names no requirements file disposed of nothing: every inherited line is carried
PJ="$(mk_fixture carry8)"; advance_to "$PJ" 8
carry_prev "$PJ"
run_close "$PJ" run
expect_eq "CARRY-20 no requirements file: run exits 0 and carries all four inherited lines, in their order" \
  "0|$CARRY_P1
$CARRY_P2
$CARRY_P3
$CARRY_P4" "$CO_RC|$(carry_section "$PJ/$CONT_REL")"

# an existing continuation without the heading gets the carried lines in the appended section too; it
# is the newest continuation under the docs root, and it is this run's own, so it is not the predecessor
PL="$(mk_fixture carry9)"; advance_to "$PL" 8
carry_prev "$PL"
carry_req "$PL" "again: $CARRY_PR#1" "adopted: $CARRY_PR#2 as REQ-1" "closed: $CARRY_PR#3 done" "closed: $CARRY_PR#4 done"
mkdir -p "$PL/${CONT_REL%/*}"
printf '# continuation — hand written\n' > "$PL/$CONT_REL"
run_close "$PL" run
expect_eq "CARRY-21 an existing continuation without the heading: the again line is appended under it" \
  "0|$CARRY_P1" "$CO_RC|$(carry_section "$PL/$CONT_REL")"

# check says what run will do (read-structure-p15 #2): over an existing continuation with no heading,
# check names the append, and run then performs it; over one with the heading, both leave it
PV="$(mk_fixture carry11)"; advance_to "$PV" 8
carry_plant "$PV" "deferred: $CARRY_REC#1 S2 off \"appended\""
mkdir -p "$PV/${CONT_REL%/*}"
printf '# continuation — hand written\n' > "$PV/$CONT_REL"
run_close "$PV" check
expect_contains "CARRY-22 check over an existing continuation without the heading names the append run will make" \
  "continuation: ${CONT_REL#.bionic/docs/} already written — run appends the ## Deferrals section" "$CO_OUT"
expect_eq "CARRY-22a …and writes nothing" "0" "$(carry_section "$PV/$CONT_REL" | wc -l | tr -d ' ')"
run_close "$PV" run
expect_contains "CARRY-22b …then run appends it, as check said" \
  "continuation: ${CONT_REL#.bionic/docs/} already written — left as it stands, with the ## Deferrals section appended" "$CO_OUT"
PW="$(mk_fixture carry12)"; advance_to "$PW" 8
mkdir -p "$PW/${CONT_REL%/*}"
printf '# continuation — hand written\n\n## Deferrals\n' > "$PW/$CONT_REL"
run_close "$PW" check
expect_contains "CARRY-22c over a continuation that carries the heading, check says it is left as it stands" \
  "continuation: ${CONT_REL#.bionic/docs/} already written — left as it stands" "$CO_OUT"
expect_absent "CARRY-22d …and names no append" "appends the ## Deferrals" "$CO_OUT"

# a ## Deferrals inside a code fence of an existing continuation is an example, not the section: the
# section is still appended (read-adversarial-p15 #4)
PF="$(mk_fixture carry13)"; advance_to "$PF" 8
carry_plant "$PF" "deferred: $CARRY_REC#1 S2 off \"behind a fence\""
mkdir -p "$PF/${CONT_REL%/*}"
printf '# continuation — hand written\n\n```\n## Deferrals\n\ndeferred: an example of the form\n```\n' > "$PF/$CONT_REL"
run_close "$PF" run
carry_section_unfenced() { awk '/^```/ { f = !f; next } f { next } /^## / { s = ($0 == "## Deferrals"); next } s && NF { print }' "$1"; }
expect_eq "CARRY-23 an existing continuation whose only ## Deferrals is fenced: run appends the section, its deferral under it" \
  "0|deferred: $CARRY_REC#1 S2 off \"behind a fence\" stated=\"-\" from=$CARRY_W" "$CO_RC|$(carry_section_unfenced "$PF/$CONT_REL")"
expect_eq "CARRY-23a …and the fenced example is kept as it was" "1" \
  "$(/usr/bin/grep -c '^deferred: an example of the form$' "$PF/$CONT_REL" | tr -d ' ')"

# a continuation written by hand BEFORE Step 9 with the heading and this run's own line under it (the
# shape steps/9.md invites) still gets what the run inherited and did not settle (wave-28 T50, AC-8.10;
# read-adversarial-p16 #1): close-out merges, each line written once, the missing ones at the end of the
# section; check names what run will add, and says "left as it stands" only when nothing would be added
CARRY_OWN="deferred: $CARRY_REC#1 S2 off \"this run's own\" stated=\"-\" from=$CARRY_W"
PX="$(mk_fixture carry14)"; advance_to "$PX" 8
carry_prev "$PX"
carry_req "$PX" "adopted: $CARRY_PR#3 as REQ-1" "closed: $CARRY_PR#4 fixed in passing"
carry_plant "$PX" "deferred: $CARRY_REC#1 S2 off \"this run's own\""
mkdir -p "$PX/${CONT_REL%/*}"
printf '# continuation — hand written\n\n## Chris decides\n\n1. none\n\n## Deferrals\n\n%s\n\n## Resume instruction\n\nNothing to resume.\n' \
  "$CARRY_OWN" > "$PX/$CONT_REL"
expect_eq "CARRY-24 precondition: the hand-written continuation holds the heading and this run's own line, and nothing carried" \
  "$CARRY_OWN" "$(carry_section "$PX/$CONT_REL")"
CARRY_CK0="$(cksum < "$PX/$CONT_REL")"
run_close "$PX" check
expect_contains "CARRY-25 check over a continuation with the heading names the 2 lines run will add, by id" \
  "continuation: ${CONT_REL#.bionic/docs/} already written — run adds 2 deferred lines under ## Deferrals: $CARRY_PR#1 $CARRY_PR#2" "$CO_OUT"
expect_eq "CARRY-25a …and check writes nothing" "$CARRY_CK0" "$(cksum < "$PX/$CONT_REL")"
run_close "$PX" run
expect_eq "CARRY-26 run exits 0, and the section holds this run's own line first, then the two the run inherited and did not dispose of" \
  "0|$CARRY_OWN
$CARRY_P1
$CARRY_P2" "$CO_RC|$(carry_section "$PX/$CONT_REL")"
expect_contains "CARRY-26a …and run says it added them" \
  "continuation: ${CONT_REL#.bionic/docs/} already written — left as it stands, with 2 deferred lines added under ## Deferrals" "$CO_OUT"
expect_eq "CARRY-26b …the hand-written text around the section is kept, byte for byte" \
  "# continuation — hand written||## Chris decides||1. none||" "$(sed -n '1p;2p;3p;4p;5p;6p' "$PX/$CONT_REL" | tr '\n' '|')"
expect_eq "CARRY-26c …and the section is followed by a blank line and the next heading as it was" \
  "|## Resume instruction||Nothing to resume." "$(tail -4 "$PX/$CONT_REL" | tr '\n' '|' | sed 's/|$//')"
# a second close-out over what the first left adds nothing: the continuation the first run wrote is
# planted in a fresh fixture at the same step (a closed plan refuses a second run outright)
PX2="$(mk_fixture carry17)"; advance_to "$PX2" 8
carry_prev "$PX2"
carry_req "$PX2" "adopted: $CARRY_PR#3 as REQ-1" "closed: $CARRY_PR#4 fixed in passing"
carry_plant "$PX2" "deferred: $CARRY_REC#1 S2 off \"this run's own\""
mkdir -p "$PX2/${CONT_REL%/*}"; cp "$PX/$CONT_REL" "$PX2/$CONT_REL"
CARRY_CK1="$(cksum < "$PX2/$CONT_REL")"
expect_eq "CARRY-27 precondition: the planted continuation is the first run's, with its three lines under the heading" "3" \
  "$(carry_section "$PX2/$CONT_REL" | wc -l | tr -d ' ')"
run_close "$PX2" check
expect_contains "CARRY-27a check over it names none: left as it stands" \
  "continuation: ${CONT_REL#.bionic/docs/} already written — left as it stands" "$CO_OUT"
expect_absent "CARRY-27b …and names no add" "run adds" "$CO_OUT"
run_close "$PX2" run
expect_eq "CARRY-27c run exits 0 and the continuation is byte for byte what the first run left" "0|$CARRY_CK1" \
  "$CO_RC|$(cksum < "$PX2/$CONT_REL")"
expect_absent "CARRY-27d …with no line reported added" "deferred line" "$CO_OUT"

# a line already under the heading, byte for byte, is not written twice; the one missing is added alone
PY="$(mk_fixture carry15)"; advance_to "$PY" 8
carry_prev "$PY"
carry_req "$PY" "adopted: $CARRY_PR#3 as REQ-1" "closed: $CARRY_PR#4 fixed in passing"
mkdir -p "$PY/${CONT_REL%/*}"
printf '# continuation — hand written\n\n## Deferrals\n\n%s\n' "$CARRY_P2" > "$PY/$CONT_REL"
run_close "$PY" check
expect_contains "CARRY-28 check names only the one line that is not there" \
  "run adds 1 deferred line under ## Deferrals: $CARRY_PR#1" "$CO_OUT"
run_close "$PY" run
expect_eq "CARRY-28a run adds the missing one after the one that was there, and the one that was there once" \
  "0|$CARRY_P2
$CARRY_P1" "$CO_RC|$(carry_section "$PY/$CONT_REL")"

# a heading with nothing under it, then the next heading: the lines go under it, a blank line between
PZ="$(mk_fixture carry16)"; advance_to "$PZ" 8
carry_prev "$PZ"
carry_req "$PZ" "again: $CARRY_PR#1" "adopted: $CARRY_PR#2 as REQ-1" "closed: $CARRY_PR#3 done" "closed: $CARRY_PR#4 done"
mkdir -p "$PZ/${CONT_REL%/*}"
printf '# continuation — hand written\n\n## Deferrals\n\n## Resume instruction\n\nNothing.\n' > "$PZ/$CONT_REL"
run_close "$PZ" run
expect_eq "CARRY-29 an empty section followed by a heading: the carried line goes under it, the layout kept" \
  "0|# continuation — hand written||## Deferrals||$CARRY_P1||## Resume instruction||Nothing.|" \
  "$CO_RC|$(tr '\n' '|' < "$PZ/$CONT_REL")"

# the mutation arm: a doctored copy of close-out.sh that carries nothing it inherited
CARRY_MUT="$(mktemp -d "${TMPDIR:-/tmp}/close-out-inherit-mut.XXXXXX")"
mkdir -p "$CARRY_MUT/scripts"; ln -s "$REPO_ROOT/payload/scripts/lib" "$CARRY_MUT/scripts/lib"
ln -s "$REPO_ROOT/payload/scripts/card.sh" "$CARRY_MUT/scripts/card.sh"
sed 's/\$1 == "again" || \$1 == "open"/$1 == "none"/' "$SCRIPT" > "$CARRY_MUT/scripts/close-out.sh"
expect_eq "CARRY-mut3 the doctored copy differs from the script in exactly one line (the doctor took)" "1" \
  "$(diff "$SCRIPT" "$CARRY_MUT/scripts/close-out.sh" | /usr/bin/grep -c '^>')"
PQ="$(mk_fixture carry10)"; advance_to "$PQ" 8
carry_prev "$PQ"
carry_req "$PQ" "again: $CARRY_PR#1"
( cd "$PQ" && HOME="$SB_HOME" CLAUDE_PROJECT_DIR="" BIONIC_PLUGIN_ROOT="$REPO_ROOT/payload" BIONIC_CLAUDE_HOME="$SB_HOME/.claude" \
    bash "$CARRY_MUT/scripts/close-out.sh" "$PQ/$PLAN_REL" run ) > "$SANDBOX/carry-mut.out" 2>&1
CARRY_MRC=$?
expect_eq "CARRY-mut4 the doctored run still closes and writes its continuation's heading (the mutant runs)" "0|1" \
  "$CARRY_MRC|$(/usr/bin/grep -c '^## Deferrals$' "$PQ/$CONT_REL" | tr -d ' ')"
expect_eq "CARRY-mut5 …and carries neither the again line nor the undisposed ones, so CARRY-18 and CARRY-20 go red on it" "0" \
  "$(carry_section "$PQ/$CONT_REL" | wc -l | tr -d ' ')"
rm -rf "$CARRY_MUT"

# the merge's mutation arm (T50): a doctored copy of close-out.sh whose merge writes nothing
CARRY_MUT="$(mktemp -d "${TMPDIR:-/tmp}/close-out-merge-mut.XXXXXX")"
mkdir -p "$CARRY_MUT/scripts"; ln -s "$REPO_ROOT/payload/scripts/lib" "$CARRY_MUT/scripts/lib"
ln -s "$REPO_ROOT/payload/scripts/card.sh" "$CARRY_MUT/scripts/card.sh"
sed 's/^      co_cont_merge "\$missing"$/      :/' "$SCRIPT" > "$CARRY_MUT/scripts/close-out.sh"
expect_eq "CARRY-mut6 the doctored copy differs from the script in exactly one line (the doctor took)" "1" \
  "$(diff "$SCRIPT" "$CARRY_MUT/scripts/close-out.sh" | /usr/bin/grep -c '^>')"
PR="$(mk_fixture carry18)"; advance_to "$PR" 8
carry_prev "$PR"
carry_req "$PR" "adopted: $CARRY_PR#3 as REQ-1" "closed: $CARRY_PR#4 fixed in passing"
carry_plant "$PR" "deferred: $CARRY_REC#1 S2 off \"this run's own\""
mkdir -p "$PR/${CONT_REL%/*}"
printf '# continuation — hand written\n\n## Deferrals\n\n%s\n' "$CARRY_OWN" > "$PR/$CONT_REL"
( cd "$PR" && HOME="$SB_HOME" CLAUDE_PROJECT_DIR="" BIONIC_PLUGIN_ROOT="$REPO_ROOT/payload" BIONIC_CLAUDE_HOME="$SB_HOME/.claude" \
    bash "$CARRY_MUT/scripts/close-out.sh" "$PR/$PLAN_REL" run ) > "$SANDBOX/carry-mut.out" 2>&1
CARRY_MRC=$?
expect_eq "CARRY-mut7 the doctored run still closes, and the hand-written continuation keeps its own line (the mutant runs)" "0|$CARRY_OWN" \
  "$CARRY_MRC|$(carry_section "$PR/$CONT_REL")"
expect_eq "CARRY-mut8 …and adds nothing carried, so CARRY-26 and CARRY-28a go red on it" "1" \
  "$(carry_section "$PR/$CONT_REL" | wc -l | tr -d ' ')"
rm -rf "$CARRY_MUT"


# ============================================================
section "LANDINGS — wave-28 T14 (AC-4.5, D18): close-out's continuation prints the run's numbers with each landed row"
# ============================================================
# A continuation close-out writes from its template carries `## Landings`: the report's line and one
# line per landed row (`session-poker.sh landing-report --rows <plan>`), read from the run's landing
# record and the gate's requests and only printed. The plan is NAMED to the report, never resolved
# through the session: act 3 has wiped the session's binding before the continuation is written.
# FIXTURE FIDELITY: the events are PLANTED in the Interfaces table's `line/v1` shape, which
# lib/line.sh writes; the gate store is the sandbox's own, empty.
LAND_GATE="$SANDBOX/land-gate"; mkdir -p "$LAND_GATE/requests"
LAND_C="$(printf 'c%.0s' $(seq 40))"
# land_section <continuation> -> what stands under `## Landings`, up to the next `## `, fences and blank
# lines dropped; nothing when there is no such heading.
land_section() { awk '/^## / { s = ($0 == "## Landings"); next } s && NF && !/^```/ { print }' "$1"; }
land_plant() {  # <project> -> a ready and a queue landing for T1, a git landing for T2
  local rec="$1/.bionic/docs/record/wave-01-fixture/landing-proofs.log"
  case "$1" in "$SANDBOX"/*) : ;; *) echo "land_plant: refusing outside the sandbox: '$1'" >&2; return 1 ;; esac
  mkdir -p "${rec%/*}"
  printf 'line/v1|ev=ready|row=T1|name=w-T1|commit=%s|branch=wt/01-T1|tree=%s/.worktrees/01-T1|suites=a.test.sh|debt=-|carrier=1:x|at=2026-10-06T10:00:00Z\n' "$LAND_C" "$1" >> "$rec"
  printf 'line/v1|ev=verdict|row=T1|commit=%s|suite=a.test.sh|result=green|log=/rec/a.log|at=2026-10-06T10:20:00Z\n' "$LAND_C" >> "$rec"
  printf 'line/v1|ev=published|row=T1|commit=%s|kind=queue|by=-|why=-|at=2026-10-06T10:30:00Z\n' "$LAND_C" >> "$rec"
  printf 'line/v1|ev=published|row=T2|commit=%s|kind=git|by=-|why=-|at=2026-10-06T10:40:00Z\n' "$LAND_C" >> "$rec"
}
PLD="$(mk_fixture landings1)"; advance_to "$PLD" 8
land_plant "$PLD"
BIONIC_GATE_DIR="$LAND_GATE" run_close "$PLD" run
expect_eq "LAND-1 run exits 0 over a run whose landing record holds two landings" "0" "$CO_RC"
expect_eq "LAND-2 the continuation carries the heading ## Landings exactly once" "1" \
  "$(/usr/bin/grep -c '^## Landings$' "$PLD/$CONT_REL" | tr -d ' ')"
expect_nonempty "LAND-3 precondition: the extractor finds lines under the heading" "$(land_section "$PLD/$CONT_REL")"
expect_eq "LAND-4 …the report's line, then a line per landed row, as landing-report --rows prints them" \
"landings: queue=1 hand=0 git=1 · ready-to-landed median=30.0m p75=30.0m max=30.0m · runs: green=1 red=0 none=0 discarded=0 red-then-green=0 · waited median=0s · killed=0
T1 queue ready=2026-10-06T10:00:00Z landed=2026-10-06T10:30:00Z minutes=30.0 runs=1 waited=0s
T2 git ready=- landed=2026-10-06T10:40:00Z minutes=- runs=0 waited=0s" \
  "$(land_section "$PLD/$CONT_REL")"
expect_eq "LAND-5 …and the heading sits after ## Deferrals and before the Resume instruction" "yes" \
  "$(awk '/^## Deferrals$/ { a = NR } /^## Landings$/ { b = NR } /^## Resume instruction/ { c = NR } END { print (a && b > a && c > b) ? "yes" : "no" }' "$PLD/$CONT_REL")"
expect_eq "LAND-6 …and the Deferrals section above it still ends at its own heading (nothing of the report under it)" "0" \
  "$(awk '/^## / { s = ($0 == "## Deferrals"); next } s && /^landings: /' "$PLD/$CONT_REL" | wc -l | tr -d ' ')"
# no record: the line with zeros
PLZ="$(mk_fixture landings2)"; advance_to "$PLZ" 8
BIONIC_GATE_DIR="$LAND_GATE" run_close "$PLZ" run
expect_eq "LAND-7 a run with no landing record exits 0 and its continuation carries the line with zeros, and no row" \
  "0|landings: queue=0 hand=0 git=0 · ready-to-landed median=0.0m p75=0.0m max=0.0m · runs: green=0 red=0 none=0 discarded=0 red-then-green=0 · waited median=0s · killed=0" \
  "$CO_RC|$(land_section "$PLZ/$CONT_REL")"
# an existing continuation is never overwritten: no section is added to it
PLE="$(mk_fixture landings3)"; advance_to "$PLE" 8
land_plant "$PLE"
mkdir -p "$PLE/${CONT_REL%/*}"
printf '# continuation — hand written\n\n## Deferrals\n\n## Resume instruction\n\nedited by a person\n' > "$PLE/$CONT_REL"
BIONIC_GATE_DIR="$LAND_GATE" run_close "$PLE" run
expect_eq "LAND-8 a continuation written before close-out keeps its bytes: run exits 0 and adds no ## Landings" "0|0" \
  "$CO_RC|$(/usr/bin/grep -c '^## Landings$' "$PLE/$CONT_REL" | tr -d ' ')"
expect_eq "LAND-8b …control: the same continuation keeps its own line" "1" "$(/usr/bin/grep -c '^edited by a person$' "$PLE/$CONT_REL" | tr -d ' ')"
# the mutation arm: a doctored copy whose template drops the section
LAND_MUT="$(mktemp -d "${TMPDIR:-/tmp}/close-out-land-mut.XXXXXX")"
mkdir -p "$LAND_MUT/scripts"; ln -s "$REPO_ROOT/payload/scripts/lib" "$LAND_MUT/scripts/lib"
ln -s "$REPO_ROOT/payload/scripts/card.sh" "$LAND_MUT/scripts/card.sh"
sed 's/^\$(co_landings_section)$//' "$SCRIPT" > "$LAND_MUT/scripts/close-out.sh"
expect_eq "LAND-mut0 the doctored copy differs from the script in exactly one line (the doctor took)" "1" \
  "$(diff "$SCRIPT" "$LAND_MUT/scripts/close-out.sh" | /usr/bin/grep -c '^>')"
PLM="$(mk_fixture landings4)"; advance_to "$PLM" 8
land_plant "$PLM"
( cd "$PLM" && HOME="$SB_HOME" CLAUDE_PROJECT_DIR="" BIONIC_PLUGIN_ROOT="$REPO_ROOT/payload" BIONIC_CLAUDE_HOME="$SB_HOME/.claude" \
    BIONIC_GATE_DIR="$LAND_GATE" bash "$LAND_MUT/scripts/close-out.sh" "$PLM/$PLAN_REL" run ) > "$SANDBOX/land-mut.out" 2>&1
LAND_MRC=$?
expect_eq "LAND-mut1 the doctored run still closes and writes its continuation (the mutant runs)" "0|1" \
  "$LAND_MRC|$(/usr/bin/grep -c '^## Deferrals$' "$PLM/$CONT_REL" | tr -d ' ')"
expect_eq "LAND-mut2 …and carries no ## Landings, so LAND-2 and LAND-4 go red on it" "0" \
  "$(/usr/bin/grep -c '^## Landings$' "$PLM/$CONT_REL" | tr -d ' ')"
rm -rf "$LAND_MUT"

# ---- wave-28 T62 (AC-4.6, D18): a run open across the upgrade holds `landed:` lines and no line/v1 event ----
# The report says so (`landings: unmeasured`) where it once printed zeros; the continuation's section is
# that one line, with no fence and no row.
PLU="$(mk_fixture landings5)"; advance_to "$PLU" 8
LAND_UREC="$PLU/.bionic/docs/record/wave-01-fixture/landing-proofs.log"
mkdir -p "${LAND_UREC%/*}"
printf 'landed: row=T1 branch=wt/01-T1 head=%s merge=%s at=2026-10-06T10:10:00Z\nstamp/v1|head=%s|dirty=0|rc=0|at=2026-10-06T10:09:00Z|suites=a.test.sh\n' \
  "$LAND_C" "$LAND_C" "$LAND_C" > "$LAND_UREC"
BIONIC_GATE_DIR="$LAND_GATE" run_close "$PLU" run
expect_eq "LAND-9 a record of landed lines and no line/v1 event: run exits 0 and ## Landings is the one unmeasured line" \
  "0|landings: unmeasured — the landing record holds no line/v1 events" "$CO_RC|$(land_section "$PLU/$CONT_REL")"
expect_eq "LAND-9b …under no fence, and with no zeros anywhere in the continuation" "0|0" \
  "$(awk '/^## / { s = ($0 == "## Landings"); next } s && /^```/' "$PLU/$CONT_REL" | wc -l | tr -d ' ')|$(/usr/bin/grep -c '^landings: queue=0 ' "$PLU/$CONT_REL" | tr -d ' ')"
# the mutation arm: the unfenced branch never taken, so the section is fenced again
LAND_UMUT="$(mktemp -d "${TMPDIR:-/tmp}/close-out-unm-mut.XXXXXX")"
mkdir -p "$LAND_UMUT/scripts"; ln -s "$REPO_ROOT/payload/scripts/lib" "$LAND_UMUT/scripts/lib"
ln -s "$REPO_ROOT/payload/scripts/card.sh" "$LAND_UMUT/scripts/card.sh"
sed 's/^      "landings: unmeasured "\*)/      "landings: never "*)/' "$SCRIPT" > "$LAND_UMUT/scripts/close-out.sh"
expect_eq "LAND-mut3 the doctored copy differs from the script in exactly one line (the doctor took)" "1" \
  "$(diff "$SCRIPT" "$LAND_UMUT/scripts/close-out.sh" | /usr/bin/grep -c '^>')"
PLV="$(mk_fixture landings6)"; advance_to "$PLV" 8
mkdir -p "$PLV/.bionic/docs/record/wave-01-fixture"; cp "$LAND_UREC" "$PLV/.bionic/docs/record/wave-01-fixture/landing-proofs.log"
( cd "$PLV" && HOME="$SB_HOME" CLAUDE_PROJECT_DIR="" BIONIC_PLUGIN_ROOT="$REPO_ROOT/payload" BIONIC_CLAUDE_HOME="$SB_HOME/.claude" \
    BIONIC_GATE_DIR="$LAND_GATE" bash "$LAND_UMUT/scripts/close-out.sh" "$PLV/$PLAN_REL" run ) > "$SANDBOX/land-umut.out" 2>&1
LAND_UMRC=$?
expect_eq "LAND-mut4 the doctored run still closes and fences the line (two fence lines), which LAND-9b forbids" "0|2" \
  "$LAND_UMRC|$(awk '/^## / { s = ($0 == "## Landings"); next } s && /^```/' "$PLV/$CONT_REL" | wc -l | tr -d ' ')"
rm -rf "$LAND_UMUT"


# ============================================================
section "§FLOOR-DECLARED (wave-28 T75; REQ-17 AC-17.1, D36): close-out proceeds on a declared floor's log"
# ============================================================
# A project with no tests/*.test.sh roster declares its floor (`floor: true`, a command that passes). The
# floor fact plant_facts wrote is taken out, and the real verbs write it again from the declared floor's own
# run: `floor-run` logs it, `proof-add floor` cites the log, `current 8` moves the plan on the facts, and
# `close-out.sh run` delivers. The fixture's working head holds no tests/ directory (mk_fixture's shape).
PFL="$(mk_fixture floor-declared)"
FL_SID="closeout-floor-1"
sed '/^proved: kind=floor /d' "$PFL/$PLAN_REL" > "$PFL/$PLAN_REL.n" && mv "$PFL/$PLAN_REL.n" "$PFL/$PLAN_REL"
printf 'floor: true\n' >> "$PFL/.bionic/config.yaml"
( in_fixture "$PFL" || exit 1; . "$REPO_ROOT/tests/lib/bound-marker.sh"; bound_marker "$PFL" "$FL_SID" "$PFL/$PLAN_REL" )
fl_poke() {  # <verb> [<arg>...] -> FL_RC, FL_OUT: the real poker verb, in the fixture, as this session
  ( in_fixture "$PFL" || exit 9
    HOME="$SB_HOME" CLAUDE_PROJECT_DIR="" BIONIC_CLAUDE_HOME="$SB_HOME/.claude" \
      CLAUDE_CODE_SESSION_ID="$FL_SID" bash "$BIONIC_HOOKS_DIR/session-poker.sh" "$@" ) > "$SANDBOX/fl-poker" 2>&1
  FL_RC=$?; FL_OUT="$(cat "$SANDBOX/fl-poker")"
}
FL_H="$(fixture_git "$PFL" rev-parse wave/01-fixture)"
expect_eq "FL0 precondition: the plan carries no floor fact, and the working head no tests/ directory" "0|0" \
  "$(/usr/bin/grep -c '^proved: kind=floor ' "$PFL/$PLAN_REL" | tr -d ' ')|$(fixture_git "$PFL" ls-tree --name-only "$FL_H" tests/ | wc -l | tr -d ' ')"
fl_poke floor-run
expect_eq "FL1 floor-run runs the declared floor at the working head (exit 0), its log opening head= dirty=0 rc=0" \
  "0|head=$FL_H dirty=0 rc=0" "$FL_RC|$(head -n 1 "$PFL/.bionic/docs/record/wave-01-fixture/floor-run-$FL_H.log" 2>/dev/null)"
# THE FLOOR FACT FROM THAT LOG, BY THE PRODUCT'S JUDGE AND WRITER (as plant_facts writes its lines): the judge
# with the project root, as proof-add calls it, attests the declared log, and proof_add_line places the line.
# proof-add itself is not driven here: its dry commit runs the real gate at current: 4, which this fixture's
# Step-7 plan (no Step 0-6 lines) does not meet for any floor; session-poker §FLOOR-DECLARED drives the verb.
FL_AT="$(bash -c '. "$1/roots.sh" && . "$1/proof.sh" || exit 9
  h="$(proof_attested floor "$2/record/wave-01-fixture/floor-run-$3.log" "$4" "" "" "$5")" || { printf "%s" "$h"; exit 1; }
  proof_add_line "$6" "$(proof_line floor "$h" 2026-10-04T13:00:00Z "record/wave-01-fixture/floor-run-$3.log")" > "$6.pf" && mv "$6.pf" "$6" && printf "%s" "$h"' \
  _ "$REPO_ROOT/payload/scripts/lib" "$PFL/.bionic/docs" "$FL_H" "$PFL-wave" "$PFL" "$PFL/$PLAN_REL" 2>&1)"
expect_eq "FL2 the judge attests the declared floor's log at the working head, and the floor fact is written from it" "$FL_H|1" \
  "$FL_AT|$(/usr/bin/grep -c "^proved: kind=floor head=$FL_H " "$PFL/$PLAN_REL" | tr -d ' ')"
fl_poke current 8
expect_eq "FL3 current 8 is admitted on the facts (exit 0)" "0|8" "$FL_RC|$(sed -n 's/^current: //p' "$PFL/$PLAN_REL")"
run_close "$PFL" run
expect_eq "FL4 AC-17.1 close-out.sh run delivers on a declared floor's proof (rc 0), the plan closed" "0|1" \
  "$CO_RC|$(run_open_rc "$PFL/$PLAN_REL")"

section "DEBT-CARD — wave-30 T22 (AC-11.4, AC-11.2; D2, P2): the release card says the run's touches and burns; the continuation carries each unburned item"
# ============================================================
# The run's ledger is `record/<run>/debt.md` (lib/proof.sh `proof_debt_ledger_path`). close-out prints
# `debt: touched <N> · burned <M>`: N the touches summed over every item, M the items burned, never the
# ledger's length. The continuation's ## Deferrals carries one line per unburned item, after the
# deferred: lines, in the form
#
#   debt: <concept> <kind> "<sites>" touches=<N> raised-by=<record> from=<wave name>
#
# fails-when: the card omits the line or prints a count of items; the continuation omits an unburned item.
# FIXTURE FIDELITY: the ledger is planted in the line shape `session-poker.sh debt` writes (session-poker-4
# §DEBT-LEDGER pins the shape against the verb).
debt_plant() {  # <project> -> the ledger: three items, five touches, one burned
  local d="$1/.bionic/docs/record/wave-01-fixture"
  case "$1" in "$SANDBOX"/*) : ;; *) echo "debt_plant: refusing outside the sandbox: '$1'" >&2; return 1 ;; esac
  mkdir -p "$d"
  printf '%s\n' '# debt ledger: concept | kind | sites | raised-by <record> | touches N | burned <row> | —' \
    'tree_count | duplicate | lib/a.sh:1, lib/b.sh:2 | raised-by record/wave-01-fixture/critic-structure.md | touches 4 | —' \
    'log_shim | one-case-abstraction | lib/c.sh:3 | raised-by record/wave-01-fixture/critic-structure.md | touches 1 | burned T3' \
    'pair_x | unpinned-pair | lib/d.sh:9 | raised-by record/wave-01-fixture/critic-adversarial.md | touches 0 | —' > "$d/debt.md"
}
PDB="$(mk_fixture debtcard1)"; advance_to "$PDB" 8
debt_plant "$PDB"
run_close "$PDB" check
expect_eq "DEBT-CARD-1 check exits 0 over a run that keeps a debt ledger" "0" "$CO_RC"
expect_eq "DEBT-CARD-2 …and its card prints the run's touches and burns: 4+1+0 touched, one burned" \
  "debt: touched 5 · burned 1" "$(printf '%s\n' "$CO_OUT" | /usr/bin/grep '^debt: ')"
run_close "$PDB" run
expect_eq "DEBT-CARD-3 run exits 0" "0" "$CO_RC"
expect_eq "DEBT-CARD-4 …and prints the same line once (AC-11.4), not the ledger's three items" \
  "debt: touched 5 · burned 1" "$(printf '%s\n' "$CO_OUT" | /usr/bin/grep '^debt: ')"
expect_nonempty "DEBT-CARD-5 precondition: the extractor finds lines under ## Deferrals" "$(carry_section "$PDB/$CONT_REL")"
expect_eq "DEBT-CARD-6 the continuation carries each unburned item, in ledger order, and not the burned one (AC-11.2)" \
"debt: tree_count duplicate \"lib/a.sh:1, lib/b.sh:2\" touches=4 raised-by=record/wave-01-fixture/critic-structure.md from=$CARRY_W
debt: pair_x unpinned-pair \"lib/d.sh:9\" touches=0 raised-by=record/wave-01-fixture/critic-adversarial.md from=$CARRY_W" \
  "$(carry_section "$PDB/$CONT_REL" | /usr/bin/grep '^debt: ')"
expect_absent "DEBT-CARD-7 …the burned item is not carried" "log_shim" "$(carry_section "$PDB/$CONT_REL")"

# no ledger: the card still says it, at zero (the line is never omitted)
PDN="$(mk_fixture debtcard2)"; advance_to "$PDN" 8
run_close "$PDN" run
expect_eq "DEBT-CARD-8 a run with no ledger exits 0 and its card prints touched 0 · burned 0" \
  "0|debt: touched 0 · burned 0" "$CO_RC|$(printf '%s\n' "$CO_OUT" | /usr/bin/grep '^debt: ')"
expect_nonempty "DEBT-CARD-9 precondition: its continuation has a Deferrals heading to read" "$(/usr/bin/grep '^## Deferrals$' "$PDN/$CONT_REL")"
expect_absent "DEBT-CARD-9b …and carries no debt line" "debt: " "$(carry_section "$PDN/$CONT_REL")"

# an existing continuation with the heading: an unburned item not under it yet is merged in, each once
PDE="$(mk_fixture debtcard3)"; advance_to "$PDE" 8
debt_plant "$PDE"
mkdir -p "$PDE/${CONT_REL%/*}"
printf '# continuation — hand written\n\n## Deferrals\n\nnone, said the person\n' > "$PDE/$CONT_REL"
run_close "$PDE" run
expect_eq "DEBT-CARD-10 run over a written continuation exits 0" "0" "$CO_RC"
expect_eq "DEBT-CARD-11 …the person's line kept, both unburned items added under the heading" \
"none, said the person
debt: tree_count duplicate \"lib/a.sh:1, lib/b.sh:2\" touches=4 raised-by=record/wave-01-fixture/critic-structure.md from=$CARRY_W
debt: pair_x unpinned-pair \"lib/d.sh:9\" touches=0 raised-by=record/wave-01-fixture/critic-adversarial.md from=$CARRY_W" \
  "$(carry_section "$PDE/$CONT_REL")"

# ============================================================
section "DEBT-RECARRY — wave-30 T23 (A-orch-44; AC-11.2): an inherited debt line the run's ledger does not hold is carried again"
# ============================================================
# A continuation's `debt:` lines reach the next run's ledger only through `debt adopt` (wave-30 T32), and
# `card.sh inherited` withholds them so an adopted item is not written twice (A-T32.2). So an item nobody
# adopted was dropped at the next close-out. Now close-out carries each inherited debt line as written,
# its from= kept, unless the run's ledger holds its concept and kind: then the ledger's own line carries
# it (unburned) or nothing does (burned). fails-when: an unadopted item is dropped, or an adopted one is
# carried twice. FIXTURE FIDELITY: the predecessor's lines are in close-out's own carry shape (the printf
# docs-pins W30-L4b holds), and the ledger is debt_plant's, the shape `session-poker.sh debt` writes.
RC_FROM="from=$CARRY_PREV"
RC_HELD="debt: tree_count duplicate \"lib/a.sh:1, lib/b.sh:2\" touches=2 raised-by=record/$CARRY_PREV/critic-structure.md $RC_FROM"
RC_PAID="debt: log_shim one-case-abstraction \"lib/c.sh:3\" touches=1 raised-by=record/$CARRY_PREV/critic-structure.md $RC_FROM"
RC_LOOSE="debt: orphan_x duplicate \"lib/z.sh:7\" touches=3 raised-by=record/$CARRY_PREV/critic-structure.md $RC_FROM"
PRC="$(mk_fixture debtrecarry1)"; advance_to "$PRC" 8
debt_plant "$PRC"
mkdir -p "$PRC/.bionic/docs/record/$CARRY_PREV"
printf '%s\n' "# continuation — $CARRY_PREV" "" "## Deferrals" "" "$RC_HELD" "$RC_PAID" "$RC_LOOSE" \
  "" "## Resume instruction" "" "nothing" > "$PRC/.bionic/docs/record/$CARRY_PREV/continuation.md"
expect_eq "DEBT-RECARRY-0 precondition: card.sh inherited-debt reads the predecessor's three debt lines, as written" \
"$RC_HELD
$RC_PAID
$RC_LOOSE" "$(bash "$REPO_ROOT/payload/scripts/card.sh" inherited-debt "$PRC/.bionic/docs/plans/epic-fx/wave-01-fixture.requirements.md" 2>/dev/null)"
run_close "$PRC" run
expect_eq "DEBT-RECARRY-1 run exits 0 over a run that inherited three debt lines and keeps a ledger" "0" "$CO_RC"
expect_eq "DEBT-RECARRY-2 the ledger's unburned items, then the inherited line no ledger holds, as written with its from=" \
"debt: tree_count duplicate \"lib/a.sh:1, lib/b.sh:2\" touches=4 raised-by=record/wave-01-fixture/critic-structure.md from=$CARRY_W
debt: pair_x unpinned-pair \"lib/d.sh:9\" touches=0 raised-by=record/wave-01-fixture/critic-adversarial.md from=$CARRY_W
$RC_LOOSE" "$(carry_section "$PRC/$CONT_REL" | /usr/bin/grep '^debt: ')"
expect_absent "DEBT-RECARRY-3 …the inherited line whose concept and kind the ledger holds is not carried twice" \
  "touches=2 raised-by=record/$CARRY_PREV/critic-structure.md" "$(carry_section "$PRC/$CONT_REL")"
expect_absent "DEBT-RECARRY-4 …nor the one the ledger burned" "log_shim" "$(carry_section "$PRC/$CONT_REL")"
# THE RECORD TEMPLATE SAYS REGRESSION (wave-30 T23; AC-4.7, D10): the continuation close-out writes asks the
# orchestrator for the regression's result, in the word the doctrine uses.
expect_contains "REG-1 AC-4.7 the continuation's template asks for the regression result" "<fill: regression result>" "$(cat "$PRC/$CONT_REL" 2>/dev/null)"
expect_absent "REG-1b …and no longer for the floor's" "<fill: floor result>" "$(cat "$PRC/$CONT_REL" 2>/dev/null)"
# no ledger at all: every inherited debt line is carried, in its order
PRN="$(mk_fixture debtrecarry2)"; advance_to "$PRN" 8
mkdir -p "$PRN/.bionic/docs/record/$CARRY_PREV"
printf '%s\n' "# continuation — $CARRY_PREV" "" "## Deferrals" "" "$RC_HELD" "$RC_LOOSE" \
  "" "## Resume instruction" "" "nothing" > "$PRN/.bionic/docs/record/$CARRY_PREV/continuation.md"
run_close "$PRN" run
expect_eq "DEBT-RECARRY-5 a run with no ledger exits 0 and carries both inherited debt lines, as written" \
  "0|$RC_HELD
$RC_LOOSE" "$CO_RC|$(carry_section "$PRN/$CONT_REL" | /usr/bin/grep '^debt: ')"

# ============================================================
section "RUNS — wave-30 T12 (REQ-4 AC-4.6, D7d; D6): the card prints regression-runs, and the Step-8 sweep stops every orphan run"
# ============================================================
#
# THE COUNT IS READ BEFORE THE WIPE TAKES THE ROSTERS: `regression-runs: <n>` is session-poker's
# `regression-runs`, the full-runner runs the rosters record as ended. THE SWEEP: a detached run
# (booked.sh --detach) whose pid is alive and that wrote no end, left by a closing run, is an orphan;
# `run` stops it through `session-poker.sh stop-run` and names it with its last progress line, then
# the wipe takes its files; `check` names it and sends nothing. FIXTURE FIDELITY: the roster row is a
# run record in the shim's shape; the orphan is a stand-in shim (a loop that dies on TERM, under the
# real perl setsid, its pid file and progress line beside its log), because a closing run's orphan is
# a process nobody is waiting on and the sweep reads nothing else of it.
PR="$(mk_fixture pruns)"; advance_to "$PR" 8
PR_RUNS="$PR/.bionic/tmp/runs"; mkdir -p "$PR_RUNS" "$SANDBOX/fake-shim"
roster_row_fixture status=identified session=fixture name=w-reg agent_id=areg \
  "run_log=$PR_RUNS/w-reg-run.sh.log" run_cmd=tests/run.sh run_rc=0 >> "$PR/.bionic/tmp/roster-fixture.state"
printf '#!/bin/bash\nwhile :; do sleep 0.2; done\n' > "$SANDBOX/fake-shim/booked.sh"
PR_LOG="$PR_RUNS/w-orph-o.test.sh.log"; : > "$PR_LOG"
printf '2026-10-08T00:00:02Z\to.test.sh\t§sec-orph\n' > "$PR_LOG.progress.tsv"
perl -MPOSIX -e 'my $l = shift; my $p = fork; exit 0 if $p; POSIX::setsid(); open(my $f, ">", "$l.pid"); print $f "$$\n"; close $f; open(STDIN, "<", "/dev/null"); open(STDOUT, ">>", $l); open(STDERR, ">&", \*STDOUT); exec @ARGV' \
  "$PR_LOG" bash "$SANDBOX/fake-shim/booked.sh" --run-log "$PR_LOG"
i=0; while [ ! -s "$PR_LOG.pid" ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
PR_PID="$(cat "$PR_LOG.pid" 2>/dev/null)"
TS_LIVE_PIDS="$TS_LIVE_PIDS ${PR_PID:-}"
expect_true "RUNS.0 precondition: the orphan's shim is alive" kill -0 "${PR_PID:-0}"

run_close "$PR" check
expect_eq "RUNS.1 AC-4.6 check prints the release card's count of full runs, from the run records" "yes" \
  "$(contains "$CO_OUT" "regression-runs: 1")"
expect_eq "RUNS.2 check names the orphan, what stop-run would do, and its last progress line" "yes" \
  "$(contains "$CO_OUT" "orphan: w-orph-o.test.sh — RUNNING; would TERM its process group")"
expect_eq "RUNS.2b …ending in the run's last progress line" "yes" \
  "$(contains "$(printf '%s\n' "$CO_OUT" | grep '^orphan: ')" "; last progress: 2026-10-08T00:00:02Z o.test.sh §sec-orph")"
expect_true "RUNS.3 …and sends nothing: the orphan is still alive" kill -0 "${PR_PID:-0}"

run_close "$PR" run
expect_eq "RUNS.4 run exits 0" "0" "$CO_RC"
expect_eq "RUNS.5 AC-4.6 run prints the count on the card too" "yes" "$(contains "$CO_OUT" "regression-runs: 1")"
expect_eq "RUNS.6 run stops the orphan and says so, with its last progress line" "yes" \
  "$(contains "$CO_OUT" "orphan: w-orph-o.test.sh — stopped (TERM); it wrote no end, so rc=137 was recorded for it; last progress: 2026-10-08T00:00:02Z o.test.sh §sec-orph")"
expect_false "RUNS.7 …and the orphan's process is gone" kill -0 "${PR_PID:-0}"
expect_eq "RUNS.8 …and the wipe took its files with the rest of .bionic/tmp" "0" "$(tmp_entries "$PR")"
expect_eq "RUNS.9 one orphan, one line" "1" "$(printf '%s\n' "$CO_OUT" | grep -c '^orphan: ')"

finish
