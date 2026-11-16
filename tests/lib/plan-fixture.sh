# tests/lib/plan-fixture.sh — THE ONE PLAN A FIXTURE WRITES, AT EITHER SCALE, AT VERSION 15
#
#     . "$(dirname "$0")/lib/plan-fixture.sh"
#     P="$(plan_fixture "$R/.bionic/docs/plans/epic-99-fixture/wave-01-fixture.plan.md" task \
#            "| T1 | 4 | build | the first build | implementor | — | — | 30 | REQ-1 | a.sh | — | — | pending |")"
#
# ONE LEDGER SHAPE (D2). The scales differ in their ARTIFACTS and never in the ledger: a wave plan
# cites a requirements file and a spec, a task plan carries its design as a paragraph in the plan
# itself. So this helper takes the scale as a parameter and changes only those artifact lines with it.
#
# plan_fixture [--current <step>] <path> <task|wave> [<row>...] -> writes the plan at <path>
#   (directories made), prints <path>. Each <row> is one whole `## Tasks` data row in the header's
#   column order (id, step, kind, task, agent, deps, reads, size, serves, Files, worktree, base, status), its agent, worktree and status cells read as the events they stand for.
#   `--current` is the run's step, a number 1 to 9 (default 4). At wave scale, when <path> sits under a
#   `<docs root>/plans/` directory, the two artifacts its Step-1 and Step-2 lines cite are written under `<docs root>/specs/` beside it.
#
# THE PAGE. The page a version-15 run holds: no state, ledger or matrix section, the header naming
# the working branch and base, each row in its nine authored cells, the criterion's fails-when in an
# `## Eval design`, and the run's log (`plan_fixture_log`) holding what the agent, worktree and status
# cells say. Its step is a number and its plan sits under plans/, where the reader finds a log.
#
# HOOK-VALID. The frontmatter is the whole set hooks/canonical-sdlc-governing-skill.sh demands of a
# plan (the version, intent, rigor, scale, the opt-in and discriminator flags, model_plan), so a
# fixture that writes this through the Write hook is admitted, and a test may say so.
plan_fixture() {  # [--current <step>] <path> <task|wave> [<row>...]
  local cur=4 path scale docs rel stem epic
  if [ "${1:-}" = "--current" ]; then cur="${2:-}"; shift 2; fi
  path="${1:?plan_fixture: a path}"; scale="${2:?plan_fixture: a scale}"; shift 2
  case "$scale" in task|wave) : ;; *) echo "plan_fixture: scale '$scale' is not task or wave" >&2; return 2 ;; esac
  case "$cur:$path" in [1-9]:*/plans/*) : ;;
    *) echo "plan_fixture: a page at 15 takes a step number and a plan under plans/" >&2; return 2 ;; esac
  mkdir -p "$(dirname "$path")" || return 1
  stem="$(basename "$path" .plan.md)"
  epic="$(basename "$(dirname "$path")")"
  rel="plans/$epic/$stem.plan.md"
  if [ "$scale" = wave ]; then
    case "$path" in
      */plans/*/*)
        docs="${path%/plans/*}"
        mkdir -p "$docs/specs/$epic"
        printf '# requirements\n' > "$docs/specs/$epic/$stem.requirements.md"
        printf '# spec\n' > "$docs/specs/$epic/$stem.spec.md" ;;
    esac
  fi
  {
    printf -- '---\ngoverning-skill: canonical-sdlc\nsdlc-step: 3\nepic: %s\nwave: %s\n' "$epic" "$stem"
    printf 'canonical_sdlc_version: 15\nintent: bugfix\nrigor: single\nscale: %s\n' "$scale"
    printf 'cleanup_on_finish: true\nuse_worktree: true\nsurface_type: none\nlanguage: none\n'
    printf 'has_ui: false\nmulti_agent: false\ndeploy_target: none\nmodel_plan: orchestrator=fable-5-high\n'
    printf 'working-branch: wave/01-fixture\nbase-sha: abc1234\n'
    printf 'walk: exempt\nparallel-budget: writers=8 suites=4 worktrees=32 test_jobs=8 source=user\n---\n\n'
    printf '# fixture plan\n\n## Goal\n\nOne plan a fixture writes, at either scale, in the one ledger shape.\n\n'
    if [ "$scale" = task ]; then
      printf '## Requirements\n\n### REQ-1 — the fixture\n\n- AC-1.1 the fixture holds.\n\n'
      printf '## Design\n\nThe fixture design paragraph: a task-scale run writes its design here, not in a spec.\n\n'
    fi
    printf '## Tasks\n\n| id | step | kind | task | deps | size | serves | Files | artifact |\n|---|---|---|---|---|---|---|---|---|\n'
    _plan_fixture_rows "$(plan_fixture_log "$path")" "$cur" "$@" || return 1
    printf '\n## Eval design\n\n| Requirement | Approach | Criterion | Eval type | Eval | Fails when |\n|---|---|---|---|---|---|\n'
    printf '| REQ-1 | fixture | AC-1.1 | hermetic | `tests/a.test.sh` | the fixture is wrong |\n'
  } > "$path" || return 1
  printf '%s' "$path"
}

# plan_fixture_log <plan> -> the path of the run's log beside a plan under <docs>/plans/[<epic>/], as lib/reader.sh
#   `reader_record` joins them: <docs>/record/<the plan's name less .plan.md>/run.log.
plan_fixture_log() {
  local d="${1%/*}" n="${1##*/}"; case "${d%/*}" in */plans) d="${d%/*}" ;; esac
  printf '%s/record/%s/run.log' "${d%/plans}" "${n%.plan.md}"
}

# _plan_fixture_rows <log> <step> [<row>...] -> each row, given in the thirteen cells above, printed in the
#   nine a version-15 row holds; the log is written whole with what the other cells said: a step
#   event for each step to <step> (step 9 not delivered), the plan's approval (the one approval a verb writes), then
#   per row its dispatch under the agent cell's name (a row not pending), its tree, and its landing.
#   Each line has its own instant, so the fold reads them in the order written.
_plan_fixture_rows() {
  local log="$1" n="$2"; shift 2
  mkdir -p "${log%/*}" || return 1
  printf '%s\n' "$@" | awk -F'|' -v lf="$log" -v n="$n" '
    function none(s) { gsub(/—|-/, "", s); return s == "" }
    function ev(s) { printf "run/v1|ev=%s|at=2026-10-04T00:%02d:00Z\n", s, ++t > lf }
    BEGIN { for (i = 1; i <= n; i++) ev("step|n=" i (i == 9 ? "|delivered=no" : "")); ev("approval|key=step3|by=fixture|said=approved") }
    NF > 13 { for (i = 2; i < NF; i++) { c[i - 1] = $i; gsub(/^[ \t]+|[ \t]+$/, "", c[i - 1]) }
      printf "| %s | %s | %s | %s | %s | %s | %s | %s | — |\n", c[1], c[2], c[3], c[4], c[6], c[8], c[9], c[10]
      if (!none(c[5]) && c[13] != "pending") ev("dispatch|row=" c[1] "|name=" c[5])
      if (!none(c[11])) ev("tree|row=" c[1] "|path=" c[11])
      if (c[13] == "landed") ev("published|row=" c[1]) }'
}

# plan_fixture_themes <plan> [<status>...] -> the plan reads two themes from the sibling
#   `<docs root>/specs/<epic>/<slug>.requirements.md`, `## The card reads true` over the first requirement (two
#   criteria, AC-168 and AC-169) and `## The gate admits the work` over the second (one, AC-170); the plan's
#   `## Eval design` is replaced by one naming each criterion's requirement, and the run's log gains a passing proof
#   of each criterion whose next <status> is discharged and a waiver of each waived (else it stays pending).
plan_fixture_themes() {  # <plan> [<status>...]
  local plan="$1" d="${1%/*}" q a i=0 r1="AC-168 AC-169" r2=AC-170 log; shift
  q="${d%/*/*}/specs/${d##*/}/$(basename "$plan" .plan.md).requirements.md"; mkdir -p "${q%/*}" || return 1
  { printf -- '---\nscale: wave\n---\n# requirements\n\n## The card reads true\n\nThe card says what was authored.\n\n### REQ-1 — goals\n\n'
    printf -- '- %s read. Fails when: not.\n' $r1
    printf '\n## The gate admits the work\n\nThe gate honours the word.\n\n### REQ-2 — the word\n\n- %s honoured. Fails when: not.\n' "$r2"; } > "$q"
  { awk '/^## / { s = ($0 ~ /^## Eval design/) } !s' "$plan"
    printf '## Eval design\n\n| Requirement | Approach | Criterion | Eval type | Eval | Fails when |\n|---|---|---|---|---|---|\n'
    for a in $r1; do printf '| REQ-1 | x | %s | hermetic | `tests/a.test.sh` | %s is wrong |\n' "$a" "$a"; done
    printf '| REQ-2 | x | %s | hermetic | `tests/a.test.sh` | %s is wrong |\n' "$r2" "$r2"; } > "$plan.pft" && mv -f "$plan.pft" "$plan"
  log="$(plan_fixture_log "$plan")"; mkdir -p "${log%/*}"
  for a in $r1 $r2; do i=$((i + 1))
    case "${!i:-pending}" in
      discharged) printf 'run/v1|ev=proof|kind=eval|ac=%s|head=%040d|rc=0|at=2026-10-06T10:00:00Z\n' "$a" 1 >> "$log" ;;
      waived) printf 'run/v1|ev=waiver|ac=%s|head=%040d|by=fixture|said=waive it|at=2026-10-06T10:00:00Z\n' "$a" 1 >> "$log" ;;
    esac; done
}
