# tests/close-out.prelude.sh — THE HALF OF THE CLOSE-OUT SUITE EVERY PART SHARES (wave-39 T6; D1, D13,
# REQ-3 AC-3.1).
#
# Sourced by tests/close-out-1.test.sh through -4, after tests/lib/assert.sh, regression-fixture.sh and
# roster-row.sh. It is not a suite: the runner launches `*.test.sh` only. It sits beside the parts rather than
# under tests/lib/ so the reads index follows it from each part's `source` line, one hop (lib/anchors.sh, the
# prelude hop), and an edit to it is answered with these four suites, not the full run.
#
# WHY FOUR PARTS. One close-out.test.sh promised 1696 s on the gate, past the suite bar (lib/line.sh
# LINE_SUITE_BAR, ten minutes of promise; D1), so no writer's `ready --within` could hold it. It is cut at
# section boundaries into four suites of about equal cost, every section kept whole and in its order.
#
# WHAT IT HOLDS. The sandbox and the pins, the fixture builders and drivers every section uses, and each helper
# or constant a section defined that a section in a LATER part calls. A hoisted block is marked with the section
# it came from, and that section keeps a one-line pointer where it stood.
#
# WHAT IT NEVER HOLDS. A fixture: a repository one section builds and a later one reads is not a helper, so
# those sections share a part instead (§PARKED builds the repository §ONE-WRITER reads; both are part 4).
#
# THE SUITE: payload/scripts/close-out.sh: the Step 8/9 tail, performed
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
    echo "${0##*/}: refusing a fixture command with an EMPTY path" >&2
    return 1
  fi
  case "$d" in
    "$SANDBOX"/*) : ;;
    *) echo "${0##*/}: refusing a fixture command outside the sandbox: $d" >&2; return 1 ;;
  esac
  [ -d "$d" ] || { echo "${0##*/}: no fixture directory at $d" >&2; return 1; }
  cd "$d" || return 1
}

# fixture_git <dir> <git args...> — `git -C` with the same guard. `git -C ""` runs in the
# caller's directory exactly the way `cd ""` does.
fixture_git() {
  local d="${1:-}"
  shift
  case "$d" in
    "$SANDBOX"/*) : ;;
    *) echo "${0##*/}: refusing git outside the sandbox: '$d'" >&2; return 1 ;;
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
adrs: none
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
  tier-run: bash tests/close-out-1.test.sh
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
            regression)  l="$(proof_line regression "$3" 2026-10-04T12:00:00Z record/wave-01-fixture/floor.log)" ;;
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
  tier-run: bash tests/close-out-1.test.sh
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

# sc_strip <continuation> -> the file without its `## Scorecard` section (wave-38 T15): close-out adds that section to a
# continuation that exists, so a row about the rest of the file reads it with the section taken out, and the section is
# asserted on its own (§SCORECARD)
sc_strip() { awk '/^## / { s = ($0 == "## Scorecard") } !s' "$1"; }

# branch_exists <project> <branch> -> yes|no
branch_exists() {
  if fixture_git "$1" rev-parse --verify --quiet "refs/heads/$2" >/dev/null 2>&1; then
    printf 'yes'
  else
    printf 'no'
  fi
}

# hoisted from section 0o
ROWS_NOWT="| T1 | 4 | build | fixture writer one | implementor | — | 10 | AC-1 | file.txt | active |"

# hoisted from section ANY-BRANCH
mk_task_pr_fixture() {
  local name="$1" working="$2" p
  p="$(mk_census_fixture_nowt "$name" "$working" "$ROWS_NOWT")"; advance_to "$p" 8
  sed -i.bak 's/^scale: wave$/scale: task/' "$p/$PLAN_REL" && rm -f "$p/$PLAN_REL.bak"
  (
    in_fixture "$p" || exit 1
    git checkout -q -b "$working"
    printf 'late fix\n' >> file.txt
    git commit -q -am "late fix" >/dev/null 2>&1
    git checkout -q main
  )
  plant_facts "$p"
  printf '%s\n' "$p"
}

# hoisted from section 4e
presence_state() {
  printf 'br=%s tmp=%s cont=%s cur8=%s epicrow=%s' \
    "$(branch_exists "$1" "wt/01-x")" "$(tmp_entries "$1")" \
    "$([ -f "$1/$CONT_REL" ] && echo yes || echo no)" \
    "$(grep -qE '^current: 8$' "$1/$PLAN_REL" && echo yes || echo no)" \
    "$(grep -c '^| 01 ' "$1/$EPIC_REL")"
}

# hoisted from section 4e
# step_lines <plan> <N> -> how many `Step N:` lines `## SDLC State` carries.
step_lines() {
  awk -v n="$2" '
    /^## / { insdlc = ($0 ~ /^## SDLC State/) }
    insdlc && $0 ~ "^[[:space:]]*-?[[:space:]]*Step[[:space:]]+" n "[[:space:]]*:" { c++ }
    END { print c + 0 }' "$1"
}

# hoisted from section 4f
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

# hoisted from section 4f
# rows_with_wave <file> <kind> <num> -> how many data rows of that table lead with <num>.
rows_with_wave() {
  table_rows "$1" "$2" | grep -cE "^\|[[:space:]]*$3[[:space:]]*\|" | tr -d ' '
}

# hoisted from section 4f
# adr_cell <project> -> the trimmed ADRs cell (column 5) of the wave-01 row in the shipped table.
adr_cell() {
  table_rows "$1/$EPIC_REL" shipped | grep -E '^\|[[:space:]]*01[[:space:]]*\|' | awk -F'|' '
    { c = $6; gsub(/^[ \t]+|[ \t]+$/, "", c); print c }'
}

# hoisted from section 4f
# set_plan_keys <project> <spec-line|-> <adrs-line|-> -> inserts the given frontmatter lines
# after `walk:` ("-" inserts nothing).
set_plan_keys() {
  local p="$1/$PLAN_REL" extra="" drop=""
  # A KEY GIVEN REPLACES THE ONE THE FIXTURE CARRIES (wave-33 T8: the plan builder now says
  # `adrs: none`, because close-out refuses to write an epic row from a plan that says nothing).
  [ "$2" = "-" ] || { extra="${extra}$2"$'\n'; drop="${drop}spec "; }
  [ "$3" = "-" ] || { extra="${extra}$3"$'\n'; drop="${drop}adrs "; }
  EXTRA="$extra" DROP="$drop" awk '
    BEGIN { n = split(ENVIRON["DROP"], d, " ") }
    NR == 1 { fm = 1 }
    fm && NR > 1 && /^---$/ { fm = 0 }
    { for (i = 1; i <= n; i++) if (fm && index($0, d[i] ":") == 1) next }
    { print } /^walk:/ { printf "%s", ENVIRON["EXTRA"] }' "$p" > "$p.tmp" && mv "$p.tmp" "$p"
}

# hoisted from section CARRY
CARRY_REC="record/wave-01-fixture/rev.md"

# hoisted from section CARRY
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

# hoisted from section CARRY
# carry_section <continuation> -> what stands under the heading `## Deferrals`, up to the next `## `,
# blank lines dropped; nothing when there is no such heading.
carry_section() {
  awk '/^## / { s = ($0 == "## Deferrals"); next } s && NF { print }' "$1"
}

# hoisted from section CARRY
CARRY_W="wave-01-fixture"

# hoisted from section CARRY
CARRY_PREV="wave-00-prev"

# hoisted from section LANDINGS
LAND_GATE="$SANDBOX/land-gate"; mkdir -p "$LAND_GATE/requests"

# hoisted from section LANDINGS
LAND_C="$(printf 'c%.0s' $(seq 40))"

# hoisted from section §HAND-HOLDS
HH_GATE="$SANDBOX/hh-gate"; mkdir -p "$HH_GATE/requests"

# hoisted from section §HAND-HOLDS
# hh_report <project> [flags…] -> the poker's landing-report over that project's plan, stdout only
hh_report() {
  local proj="$1"; shift
  ( in_fixture "$proj" || exit 9
    HOME="$SB_HOME" CLAUDE_PROJECT_DIR="" BIONIC_PLUGIN_ROOT="$REPO_ROOT/payload" BIONIC_CLAUDE_HOME="$SB_HOME/.claude" \
      BIONIC_GATE_DIR="$HH_GATE" bash "$BIONIC_HOOKS_DIR/session-poker.sh" landing-report "$@" "$proj/$PLAN_REL" 2>/dev/null )
}

# hoisted from section DEBT-CARD
debt_plant() {  # <project> -> the ledger: three items, five touches, one burned
  local d="$1/.bionic/docs/record/wave-01-fixture"
  case "$1" in "$SANDBOX"/*) : ;; *) echo "debt_plant: refusing outside the sandbox: '$1'" >&2; return 1 ;; esac
  mkdir -p "$d"
  printf '%s\n' '# debt ledger: concept | kind | sites | raised-by <record> | touches N | burned <row> | —' \
    'tree_count | duplicate | lib/a.sh:1, lib/b.sh:2 | raised-by record/wave-01-fixture/critic-structure.md | touches 4 | —' \
    'log_shim | one-case-abstraction | lib/c.sh:3 | raised-by record/wave-01-fixture/critic-structure.md | touches 1 | burned T3' \
    'pair_x | unpinned-pair | lib/d.sh:9 | raised-by record/wave-01-fixture/critic-adversarial.md | touches 0 | —' > "$d/debt.md"
}

require_helpers in_fixture fixture_git contains fixture_plan_text fixture_epic_text mk_fixture \
                add_unreached_branch add_foreign_unreached_branch run_close run_close_as gate_rc \
                run_open_rc tmp_entries sha_of branch_exists plant_tmp_session tmp_file_exists \
                mk_census_fixture mk_census_branch mk_census_fixture_nowt advance_to \
                mk_task_pr_fixture presence_state step_lines table_rows rows_with_wave adr_cell set_plan_keys carry_plant carry_section hh_report debt_plant
