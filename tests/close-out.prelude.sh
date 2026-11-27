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
# WHAT IT HOLDS. The sandbox and the pins, the drivers every section uses, and each helper or constant a section
# defined that a section in a LATER part calls. The fixture builders are tests/lib/close-out-fixture.sh, loaded here. A hoisted block is marked with the section
# it came from, and that section keeps a one-line pointer where it stood.
#
# WHAT IT NEVER HOLDS. A fixture: a repository one section builds and a later one reads is not a helper, so
# those sections share a part instead (§PARKED builds the repository §ONE-WRITER reads; both are part 4).
#
# THE SUITE: payload/scripts/close-out.sh, the Step 8/9 tail performed by one script that attests its own acts. Every
# section is hermetic against a fixture project under a mktemp sandbox with HOME redirected into it: never this
# repository, never the real plan, never the real archive.
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
# A helper is found beside this file, wherever the suite that sources it stands; one that does not load stops the suite.
CO_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=/dev/null
declare -F seal_fixture >/dev/null 2>&1 || { [ -r "$CO_HERE/lib/seal-fixture.sh" ] && . "$CO_HERE/lib/seal-fixture.sh"; } \
  || { echo "close-out.prelude.sh: cannot load $CO_HERE/lib/seal-fixture.sh" >&2; exit 1; }
[ -r "$CO_HERE/lib/maker-stop.sh" ] && . "$CO_HERE/lib/maker-stop.sh" \
  || { echo "close-out.prelude.sh: cannot load $CO_HERE/lib/maker-stop.sh" >&2; exit 1; }
SCRIPT="$REPO_ROOT/payload/scripts/close-out.sh"
RUN_LIB="$REPO_ROOT/payload/scripts/lib/run.sh"
HOOK="${BIONIC_HOOKS_DIR}/bash-walls.sh"

# `cd ""` succeeds where it stands, so a mktemp that failed would name the suite's own directory as the sandbox, and
# the cleanup below would remove it: the sandbox is made, or the suite stops here.
SANDBOX="$(d="$(mktemp -d "${TMPDIR:-/tmp}/close-out-test.XXXXXX")" && cd "$d" && pwd -P)" \
  || { echo "close-out.prelude.sh: no sandbox under ${TMPDIR:-/tmp}" >&2; exit 1; }
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

# The sandbox guard and the fixture builders are tests/lib/close-out-fixture.sh, which a suite outside these parts
# loads as well.
[ -r "$CO_HERE/lib/close-out-fixture.sh" ] && . "$CO_HERE/lib/close-out-fixture.sh" \
  || { echo "close-out.prelude.sh: cannot load $CO_HERE/lib/close-out-fixture.sh" >&2; exit 1; }

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
  local title="census tests only" cols="| id | step | kind | task | agent | deps | size | serves | Files | status | worktree |"
  local sep="|---|---|---|---|---|---|---|---|---|---|---|" matrix=""
  if [ -n "${CO_NOWT:-}" ]; then
    title="no worktree column at all (C4)"; cols="${cols% worktree |}"; sep="${sep%---|}"
    matrix="## Verification Matrix

stack-health: n/a: no long-running serve

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1 | T1 | discharged | see AC-1 | CONFIRMED |

AC-1:
  fails-when: the planted defect this eval must go red on
  evidence: record/generic-evidence.md
  tier-run: bash tests/close-out-1.test.sh
  readback: the two lifecycle blocks the script wrote

"
  fi
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

# fixture register plan — ${title}

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

${cols}
${sep}
${rows}

${matrix}## Handoff

- resume point: Step 8 open; the tail has not run.
- open blockers: none.
PLAN_CENSUS
  (
    in_fixture "$p" || exit 1
    git init -q . >/dev/null 2>&1
    fixture_own || exit 1
    git symbolic-ref HEAD refs/heads/main
    printf '.bionic/\n' > .gitignore
    printf 'seed\n' > file.txt
    git add -A >/dev/null 2>&1
    git commit -q -m "seed" >/dev/null 2>&1
  ) || maker_stop mk_census_fixture "the fixture at $p was not made"
  co_page15 "$p"
  seal_fixture "$p/$PLAN_REL" "$p/$LOG_REL"
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
mk_census_fixture_nowt() { CO_NOWT=1 mk_census_fixture "$@"; }

PLAN_REL=".bionic/docs/plans/epic-fx/wave-01-fixture.plan.md"
EPIC_REL=".bionic/docs/plans/epic-fx/epic.plan.md"
CONT_REL=".bionic/docs/record/wave-01-fixture/continuation.md"
LOG_REL=".bionic/docs/record/wave-01-fixture/run.log"
TASKS_WORDS="mark every 4/"

# co_handoff_rel <project> -> where the run's handoff was written, from the project's root, as the reader answers it
co_handoff_rel() { bash "$REPO_ROOT/payload/scripts/reader.sh" "$1/$PLAN_REL" handoff 2>/dev/null | sed -n 's/^path=//p'; }

# co_step_answer <project> [<n>] -> the reader's step answer for the fixture's run; with <n>, the answer the reader gives
# over the run's log as it stood at its last step-<n> event, the log cut there and nothing else of the run read.
co_step_answer() {
  if [ -z "${2:-}" ]; then bash "$REPO_ROOT/payload/scripts/reader.sh" "$1/$PLAN_REL" step 2>/dev/null; return; fi
  bash -c '. "$1/lib/reader.sh" || exit 9
    f="$(awk -v n="|ev=step|n=$3|" "{ l[NR] = \$0; if (index(\$0, n)) c = NR } END { for (i = 1; i <= c; i++) print l[i] }" "$2")"
    [ -n "$f" ] || exit 1
    reader_facts() { printf "%s\n" "$f"; }; reader_q_step -' _ "$REPO_ROOT/payload/scripts" "$1/$LOG_REL" "$2" 2>/dev/null
}

# release_approved <project> -> the person's release approval at the working branch's head, the event the approve verb
# appends: a run with a row that integrates is asked it at the close.
release_approved() {
  local wb; wb="$(sed -n 's/^working-branch: //p' "$1/$PLAN_REL" | head -1)"
  printf 'run/v1|ev=approval|key=release|by=Dana Fixture|head=%s|said=Ship it.|at=2026-10-04T12:30:00Z\n' \
    "$(fixture_git "$1" rev-parse --verify -q "refs/heads/$wb")" >> "$1/$LOG_REL" || return
  seal_fixture "$1/$PLAN_REL" "$1/$LOG_REL"
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

# tmp_file_exists <project> <class> <sid> -> yes|no, whether one planted file survived.
tmp_file_exists() {
  if [ -f "$1/.bionic/tmp/$2-$3.state" ]; then printf 'yes'; else printf 'no'; fi
}

# gate_rc <project> -> the real hooks/bash-walls.sh verdict on a `git commit` payload,
# driven exactly the way tests/canonical-sdlc-evidence-gate.test.sh drives it: env
# session id agreeing with the payload's, an engagement marker bound to the project's plan
# for that id through tests/lib/bound-marker.sh (an empty marker is no binding, and the wall
# then resolves the newest plan and judges nothing against this one), CLAUDE_PROJECT_DIR
# empty, cwd pinned to the project.
gate_rc() {
  local proj="$1"
  local sid="closeout-suite-1"
  local input
  case "$proj" in "$SANDBOX"/*) : ;; *) echo "gate_rc: refusing outside the sandbox: '$proj'" >&2; echo 9; return 0 ;; esac
  mkdir -p "$proj/.bionic/tmp"
  ( in_fixture "$proj" || exit 1; . "$CO_HERE/lib/bound-marker.sh" || exit 1; bound_marker "$proj" "$sid" "$proj/$PLAN_REL" ) \
    || { echo "gate_rc: could not bind the marker in '$proj'" >&2; echo 9; return 0; }
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

ROWS_NOWT="| T1 | 4 | build | fixture writer one | implementor | — | 10 | AC-1 | file.txt | active |"

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
  seal_fixture "$p/$PLAN_REL" "$p/$LOG_REL"
  printf '%s\n' "$p"
}

presence_state() {
  printf 'br=%s tmp=%s cont=%s cur8=%s epicrow=%s' \
    "$(branch_exists "$1" "wt/01-x")" "$(tmp_entries "$1")" \
    "$([ -f "$1/$CONT_REL" ] && echo yes || echo no)" \
    "$(co_step_answer "$1" | grep -qx 'n=8' && echo yes || echo no)" \
    "$(grep -c '^| 01 ' "$1/$EPIC_REL")"
}

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

# adr_cell <project> -> the trimmed ADRs cell (column 5) of the wave-01 row in the shipped table.
adr_cell() {
  table_rows "$1/$EPIC_REL" shipped | grep -E '^\|[[:space:]]*01[[:space:]]*\|' | awk -F'|' '
    { c = $6; gsub(/^[ \t]+|[ \t]+$/, "", c); print c }'
}

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
    { print } /^walk:/ { printf "%s", ENVIRON["EXTRA"] }' "$p" > "$p.tmp" && mv "$p.tmp" "$p" || return
  seal_fixture "$p" "$1/$LOG_REL"
}

CARRY_REC="record/wave-01-fixture/rev.md"

# carry_plant <project> <line>... -> each `deferred:` line its run's deferral event: a `stated=` holding a `|` cannot be
# a field, and a `check:` line is a retired verb's, so neither is written
carry_plant() {
  local proj="$1"; shift
  case "$proj" in "$SANDBOX"/*) : ;; *) echo "carry_plant: refusing outside the sandbox: '$proj'" >&2; return 1 ;; esac
  printf '%s\n' "$@" | awk '/^deferred: / { s = substr($0, 11); split(s, w, " "); t = substr(s, index(s, "\"") + 1)
    r = substr(t, index(t, "\"") + 1); t = substr(t, 1, index(t, "\"") - 1); o = "|ref=" w[1] "|severity=" w[2] "|reach=" w[3] "|to=deferred|title=" t
    if (match(r, /stated="[^"]*"/) && !index(r, "|")) o = o "|stated=" substr(r, RSTART + 8, RLENGTH - 9)
    print "run/v1|ev=finding" o "|at=2026-10-04T12:00:00Z" }' >> "$proj/$LOG_REL" || return
  seal_fixture "$proj/$PLAN_REL" "$proj/$LOG_REL"
}

# carry_section <continuation> -> what stands under the heading `## Deferrals`, up to the next `## `,
# blank lines dropped; nothing when there is no such heading.
carry_section() {
  awk '/^## / { s = ($0 == "## Deferrals"); next } s && NF { print }' "$1"
}

CARRY_W="wave-01-fixture"

CARRY_PREV="wave-00-prev"

LAND_GATE="$SANDBOX/land-gate"; mkdir -p "$LAND_GATE/requests"

LAND_C="$(printf 'c%.0s' $(seq 40))"

HH_GATE="$SANDBOX/hh-gate"; mkdir -p "$HH_GATE/requests"

# hh_report <project> [flags…] -> the poker's landing-report over that project's plan, stdout only
hh_report() {
  local proj="$1"; shift
  ( in_fixture "$proj" || exit 9
    HOME="$SB_HOME" CLAUDE_PROJECT_DIR="" BIONIC_PLUGIN_ROOT="$REPO_ROOT/payload" BIONIC_CLAUDE_HOME="$SB_HOME/.claude" \
      BIONIC_GATE_DIR="$HH_GATE" bash "$BIONIC_HOOKS_DIR/session-poker.sh" landing-report "$@" "$proj/$PLAN_REL" 2>/dev/null )
}

debt_plant() {  # <project> -> the run's debts, as the debt verb's events: three items, five touches, one burned
  local d="$1/.bionic/docs/record/wave-01-fixture"
  case "$1" in "$SANDBOX"/*) : ;; *) echo "debt_plant: refusing outside the sandbox: '$1'" >&2; return 1 ;; esac
  mkdir -p "$d"
  printf 'run/v1|ev=debt|%s|at=2026-10-04T12:00:00Z\n' \
    'concept=tree_count|kind=duplicate|sites=lib/a.sh:1, lib/b.sh:2|raised-by=record/wave-01-fixture/critic-structure.md|touches=4' \
    'concept=log_shim|kind=one-case-abstraction|sites=lib/c.sh:3|raised-by=record/wave-01-fixture/critic-structure.md|touches=1|burned=T3' \
    'concept=pair_x|kind=unpinned-pair|sites=lib/d.sh:9|raised-by=record/wave-01-fixture/critic-adversarial.md|touches=0' >> "$d/run.log" || return
  seal_fixture "$1/$PLAN_REL" "$d/run.log"
}

require_helpers in_fixture fixture_git contains fixture_plan_text fixture_epic_text mk_fixture \
                add_unreached_branch add_foreign_unreached_branch run_close run_close_as gate_rc \
                run_open_rc tmp_entries sha_of branch_exists plant_tmp_session tmp_file_exists \
                mk_census_fixture mk_census_branch mk_census_fixture_nowt advance_to \
                mk_task_pr_fixture presence_state table_rows rows_with_wave adr_cell set_plan_keys carry_plant carry_section hh_report debt_plant
