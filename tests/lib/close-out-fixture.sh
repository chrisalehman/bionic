# tests/lib/close-out-fixture.sh — THE CLOSE-OUT FIXTURE: a git project the close-out tail runs on, and its guards
#
#     . "$(dirname "$0")/lib/close-out-fixture.sh"
#
# The close-out parts load it through tests/close-out.prelude.sh; a suite that draws its own surface over the same
# project (the release card, the notification at close) loads it itself, so the fixture has one home and a change to
# it reaches every suite that builds on it.
#
# THE CALLER SETS, before it calls a builder: SANDBOX (every fixture path is inside it, and the guards refuse any
# other), PLAN_REL and LOG_REL (the plan and its run's log under a project), REPO_ROOT (the checkout whose
# payload/scripts the builders run), and for run_close_as SCRIPT and SB_HOME. Each is read when a builder runs,
# never at load.

declare -F seal_fixture >/dev/null 2>&1 || { [ -r "${BASH_SOURCE[0]%/*}/seal-fixture.sh" ] && . "${BASH_SOURCE[0]%/*}/seal-fixture.sh"; } \
  || { echo "close-out-fixture.sh: cannot load ${BASH_SOURCE[0]%/*}/seal-fixture.sh" >&2; return 1; }
declare -F maker_stop >/dev/null 2>&1 || { [ -r "${BASH_SOURCE[0]%/*}/maker-stop.sh" ] && . "${BASH_SOURCE[0]%/*}/maker-stop.sh"; } \
  || { echo "close-out-fixture.sh: cannot load ${BASH_SOURCE[0]%/*}/maker-stop.sh" >&2; return 1; }

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

# fixture_own — 0 when the directory a subshell entered by in_fixture stands in is the top of a repository of its
# own. `git init` that failed leaves the directory inside whatever repository holds the sandbox, if one does, and
# every write after it would land there: a fixture writes nothing until git names this directory as its top, and
# the maker that called it stops the suite.
fixture_own() {
  [ "$(git rev-parse --show-toplevel 2>/dev/null)" = "$(pwd -P)" ] && return 0
  maker_stop "${FUNCNAME[1]:-fixture_own}" "no repository of its own at $(pwd -P)"
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

# fixture_epic_text -> an epic page at 15 that is itself OPEN (its run's log holds no step, so it stands at step 0),
# carrying a shipped wave table with one existing row. Open on purpose: an open sibling is what keeps
# `archive_run` from moving a wave out of a container epic, which is this repository's
# own shape and the one §1 asserts against.
fixture_epic_text() {
  cat <<'EPIC'
---
canonical_sdlc_version: 15
---

# epic-fx

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
    fixture_own || exit 1
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
  ) || maker_stop mk_fixture "the fixture at $p was not made"
  co_page15 "$p"
  seal_fixture "$p/$PLAN_REL" "$p/$LOG_REL"
  plant_facts "$p"
  seal_fixture "$p/$PLAN_REL" "$p/$LOG_REL"
  printf '%s\n' "$p"
}

# Every builder here writes the run a version-15 plan holds, its page made the version-15 one by co_page15 <project>: both branches in its header;
# no state, matrix or handoff section; each Tasks row in its nine authored cells; each criterion a row of `## Eval design`. The run's log beside it holds what those parts said, each in the
# shape its writer appends: a step per step to the plan's current one, the plan's approval, each row's dispatch, tree
# and landing, each discharged criterion's proof. A handoff written into the page is no fact the reader answers, so
# none is written. The instants are fixed and one apart; the reader folds the log in the order its lines stand.
co_page15() {
  local plan="$1/$PLAN_REL" log="$1/$LOG_REL"
  mkdir -p "${log%/*}" || return 1
  awk -v lf="$log" '
    function ev(s) { printf "run/v1|ev=%s|at=2026-10-04T00:%02d:00Z\n", s, ++t > lf }
    function cells(l, c,   n, i) { n = split(l, c, "|"); for (i = 2; i < n; i++) gsub(/^[ \t]+|[ \t]+$/, "", c[i]); return n }
    FNR == 1 { pass++; sec = "" }
    /^## / { sec = substr($0, 4) }
    pass == 1 && sec == "SDLC State" { if ($0 ~ /^(integration|working)-branch: /) hk = hk $0 "\n"; if ($1 == "current:") cur = $2
      if ($1 == "approved-by:") { by = $2; said = $0; sub(/^[^"]*"/, "", said); sub(/"$/, "", said) } }
    pass == 1 && sec == "Verification Matrix" { if (/^\| AC-/) { cells($0, c); ac[++na] = c[2]; tr[c[2]] = c[3]; st[c[2]] = c[4]; au[c[2]] = c[6] }
      else if (/^[A-Z]+-[0-9.]+:$/) b = substr($0, 1, length($0) - 1); else if (b != "" && match($0, /^  [a-z-]+: /)) k[b, $1] = substr($0, RLENGTH + 1) }
    pass == 1 { next }
    FNR == 1 { for (i = 1; i <= cur; i++) ev("step|n=" i); if (by != "") ev("approval|key=step3|by=" by "|said=" said) }
    FNR == 1 || hd { if ($0 == "---" && hd) printf "%s", hk; hd = ($0 != "---" || FNR == 1); sub(/^canonical_sdlc_version: 14$/, "canonical_sdlc_version: 15"); print; next }
    /^## / && sec == "Verification Matrix" { print "## Test design\n\n| Requirement | Approach | Criterion | Test type | Test | Fails when |\n|---|---|---|---|---|---|"
      for (i = 1; i <= na; i++) { a = ac[i]; e = k[a, "tier-run:"]; printf "| — | fixture | %s | %s | %s | %s |\n", a, tr[a], (e == "" ? "—" : "`" e "`"), k[a, "fails-when:"]
        if (st[a] == "discharged") ev("proof|ac=" a "|evidence=" k[a, "evidence:"] "|auditor=" au[a]) }
      print ""; next }
    sec == "SDLC State" || sec == "Verification Matrix" || sec == "Handoff" { next }
    sec == "Tasks" && /^\|/ { n = cells($0, c); if (!nh) { for (i = 2; i < n; i++) col[c[i]] = i; nh = 1; print "| id | step | kind | task | deps | size | serves | Files | artifact |"; next }
      if (c[2] ~ /^-+$/) { print "|---|---|---|---|---|---|---|---|---|"; next }
      printf "| %s | %s | %s | %s | %s | %s | %s | %s | — |\n", c[col["id"]], c[col["step"]], c[col["kind"]], c[col["task"]], c[col["deps"]], c[col["size"]], c[col["serves"]], c[col["Files"]]
      w = ("worktree" in col) ? c[col["worktree"]] : "—"; s = c[col["status"]]; if (s != "pending") ev("dispatch|row=" c[col["id"]] "|name=" c[col["agent"]])
      if (w != "—" && w != "") ev("tree|row=" c[col["id"]] "|path=" w); if (s == "landed") ev("published|row=" c[col["id"]]); next }
    { print }' "$plan" "$plan" > "$plan.15" && mv "$plan.15" "$plan"
}

# plant_facts <project> -> what the run owes, held at the working branch's head, as a run that
# reached Step 7 has it (wave-27 T14; D3): the working branch checked out in a linked worktree
# beside the project (`<project>-wave`), and the floor and every reading lib/proof.sh `facts_owed`
# deals the plan's rigor and scale, each `result=pass`, at that head. The lines are the product's
# (`proof_line`, each its proof event); session-poker
# §56 holds the verb that writes them, and close-out and the gate read plan text whatever wrote
# it. `close-out.sh run` and `check`, and `current 8`, refuse unless `facts_state` holds these.
# A plan whose working branch is not a branch here gets nothing: there is no head to hold.
plant_facts() {
  local p="$1" plan="$1/$PLAN_REL" wb h
  case "$p" in "$SANDBOX"/*) : ;; *) echo "plant_facts: refusing outside the sandbox: '$p'" >&2; return 1 ;; esac
  wb="$(sed -n 's/^working-branch: //p' "$plan" | head -1)"
  h="$(fixture_git "$p" rev-parse --verify -q "refs/heads/${wb}^{commit}" 2>/dev/null)" || return 0
  # A REAL BASE (the T45 ruling): the judge deals no reading on a plan with no base-sha naming a
  # commit, so the run's base, the root commit the working branch grew from, is written first, in the header, where
  # the judge reads it: after its working-branch:, or last in it on a page at 14, whose branch is in its state section.
  /usr/bin/grep -q '^base-sha:' "$plan" || {
    awk -v b="base-sha: $(fixture_git "$p" rev-list --max-parents=0 "$wb" | head -1)" 'NR == 1 && $0 == "---" { h = 1; print; next }
      h && $0 == "---" { if (!d) print b; d = 1; h = 0 } { print } h && !d && /^working-branch: / { print b; d = 1 }' \
      "$plan" > "$plan.b" && mv "$plan.b" "$plan" && seal_fixture "$plan" "$p/$LOG_REL"; }
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
          f="${l#proved: }"; LOG_AT=2026-10-04T12:00:00Z proof_event "$2" ${f/ at=2026-10-04T12:00:00Z/}
        done' _ "$REPO_ROOT/payload/scripts/lib" "$plan" "$h"
}

# advance_to <project> <N> -> the run stood at step N: one step event appended to its log, as the `current` verb
# appends it. §E2E drives the verb.
advance_to() {
  case "$1" in "$SANDBOX"/*) : ;; *) echo "advance_to: refusing outside the sandbox: '$1'" >&2; return 1 ;; esac
  printf 'run/v1|ev=step|n=%s|at=%s\n' "$2" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$1/$LOG_REL" || return
  seal_fixture "$1/$PLAN_REL" "$1/$LOG_REL"
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
