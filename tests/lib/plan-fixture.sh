# tests/lib/plan-fixture.sh — THE ONE PLAN A FIXTURE WRITES, AT EITHER SCALE
# (epic-23 wave-31 T5; REQ-1 AC-1.3, D2).
#
#     . "$(dirname "$0")/lib/plan-fixture.sh"
#     P="$(plan_fixture "$R/.bionic/docs/plans/epic-99-fixture/wave-01-fixture.plan.md" task \
#            "| T1 | 4 | build | the first build | implementor | — | — | 30 | REQ-1 | a.sh | — | — | pending |")"
#
# ONE LEDGER SHAPE (D2). The scales differ in their ARTIFACTS and never in the ledger: a wave plan
# cites a requirements file and a spec, a task plan carries its design as a paragraph in the plan
# itself; both carry numeric `current:`, the one `## Tasks` table below, a `## Dispatch ledger` and a
# `## Verification Matrix`. So this helper takes the scale as a parameter and changes only those
# artifact lines with it — every table it writes is the same bytes at both scales.
#
# plan_fixture [--current <value>] <path> <task|wave> [<row>...] -> writes the plan at <path>
#   (directories made), prints <path>. Each <row> is one whole `## Tasks` data row in the header's
#   column order (`PLAN_FIXTURE_HEADER`). `--current` writes that value into `current:` verbatim
#   (default 4) — a test of a value the readers refuse (`T1`) passes it here, and gets the same plan
#   around it. At wave scale, when <path> sits under a `<docs root>/plans/` directory, the two
#   artifacts its Step-1 and Step-2 lines cite are written under `<docs root>/specs/` beside it.
#
# HOOK-VALID. The frontmatter is the whole set hooks/canonical-sdlc-governing-skill.sh demands of a
# contract-14 plan (the version, intent, rigor, scale, the opt-in and discriminator flags,
# model_plan), so a fixture that writes this through the Write hook is admitted, and a test may say so.
PLAN_FIXTURE_HEADER='| id | step | kind | task | agent | deps | reads | size | serves | Files | worktree | base | status |
|---|---|---|---|---|---|---|---|---|---|---|---|---|'

plan_fixture() {  # [--current <value>] <path> <task|wave> [<row>...]
  local cur=4 path scale docs rel stem epic row
  if [ "${1:-}" = "--current" ]; then cur="${2:-}"; shift 2; fi
  path="${1:?plan_fixture: a path}"; scale="${2:?plan_fixture: a scale}"; shift 2
  case "$scale" in task|wave) : ;; *) echo "plan_fixture: scale '$scale' is not task or wave" >&2; return 2 ;; esac
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
    printf 'canonical_sdlc_version: 14\nintent: bugfix\nrigor: single\nscale: %s\n' "$scale"
    printf 'cleanup_on_finish: true\nuse_worktree: true\nsurface_type: none\nlanguage: none\n'
    printf 'has_ui: false\nmulti_agent: false\ndeploy_target: none\nmodel_plan: orchestrator=fable-5-high\n'
    printf 'walk: exempt\nparallel-budget: writers=8 suites=4 worktrees=32 test_jobs=8 source=user\n---\n\n'
    printf '# fixture plan\n\n## Goal\n\nOne plan a fixture writes, at either scale, in the one ledger shape.\n\n'
    printf '## SDLC State\n\ncurrent: %s\n' "$cur"
    printf 'approved-by: fixture 2026-10-04T00:00Z "approved"\n\n'
    if [ "$scale" = wave ]; then
      printf -- '- Step 1: requirements: specs/%s/%s.requirements.md\n' "$epic" "$stem"
      printf -- '- Step 2: spec: specs/%s/%s.spec.md\n' "$epic" "$stem"
    else
      printf -- '- Step 1: requirements: this plan, ## Requirements\n'
      printf -- '- Step 2: design: this plan, ## Design\n'
    fi
    printf -- '- Step 3: plan: %s\n' "$rel"
    printf -- '- Step 4: opened\n  worktree: .worktrees/01-fixture\n  base-sha: abc1234\n  branch: wave/01-fixture\n\n'
    if [ "$scale" = task ]; then
      printf '## Requirements\n\n### REQ-1 — the fixture\n\n- AC-1.1 the fixture holds.\n\n'
      printf '## Design\n\nThe fixture design paragraph: a task-scale run writes its design here, not in a spec.\n\n'
    fi
    printf '## Tasks\n\n%s\n' "$PLAN_FIXTURE_HEADER"
    for row in "$@"; do printf '%s\n' "$row"; done
    printf '\n## Dispatch ledger\n\n| id | agent | dispatched | expected | artifact | landed | notes |\n'
    printf '|---|---|---|---|---|---|---|\n'
    printf '\n## Verification Matrix\n\n| AC | tier | status | evidence | auditor |\n|---|---|---|---|---|\n'
    printf '| AC-1.1 | T2 | pending | — | — |\n\nAC-1.1:\n  provenance: fixture\n  fails-when: the fixture is wrong\n'
  } > "$path" || return 1
  printf '%s' "$path"
}

# plan_fixture_themes <plan> <dotted|flat|bare> [<status>...] -> the plan reads two themes from the sibling
#   `<docs root>/specs/<epic>/<slug>.requirements.md`, `## The card reads true` over the first requirement (two
#   criteria) and `## The gate admits the work` over the second (one); the plan gains an `## Eval design` naming each
#   criterion's requirement, and its matrix becomes one T2 row per criterion, status the next <status> (else pending),
#   each block `provenance:` and `fails-when:` with no `serves:`. dotted ids name their requirement; flat ids in the
#   hundreds name none; bare small ids number the first requirement's second criterion as the second requirement is.
plan_fixture_themes() {  # <plan> <dotted|flat|bare> [<status>...]
  local plan="$1" d="${1%/*}" q a i=0 r1 r2; shift
  case "$1" in dotted) r1="AC-1.1 AC-1.2" r2=AC-2.1 ;; flat) r1="AC-168 AC-169" r2=AC-170 ;; bare) r1="AC-1 AC-2" r2=AC-3 ;;
    *) echo "plan_fixture_themes: variant '$1' is not dotted, flat or bare" >&2; return 2 ;; esac; shift
  q="${d%/*/*}/specs/${d##*/}/$(basename "$plan" .plan.md).requirements.md"; mkdir -p "${q%/*}" || return 1
  { printf -- '---\nscale: wave\n---\n# requirements\n\n## The card reads true\n\nThe card says what was authored.\n\n### REQ-1 — goals\n\n'
    printf -- '- %s read. Fails when: not.\n' $r1
    printf '\n## The gate admits the work\n\nThe gate honours the word.\n\n### REQ-2 — the word\n\n- %s honoured. Fails when: not.\n' "$r2"; } > "$q"
  { awk '/^## / { s = ($0 ~ /^## Verification Matrix/) } !s' "$plan"
    printf '## Eval design\n\n| Requirement | Approach | Criterion | Eval type | Eval | Fails when |\n|---|---|---|---|---|---|\n'
    for a in $r1; do printf '| REQ-1 | x | %s | hermetic | `tests/a.test.sh` | %s is wrong |\n' "$a" "$a"; done
    printf '| REQ-2 | x | %s | hermetic | `tests/a.test.sh` | %s is wrong |\n\n## Verification Matrix\n\n| AC | tier | status | evidence | auditor |\n|---|---|---|---|---|\n' "$r2" "$r2"
    for a in $r1 $r2; do i=$((i + 1)); printf '| %s | T2 | %s | — | — |\n' "$a" "${!i:-pending}"; done
    for a in $r1 $r2; do printf '%s:\n  provenance: fixture\n  fails-when: %s is wrong\n' "$a" "$a"; done; } > "$plan.pft" && mv -f "$plan.pft" "$plan"
}
