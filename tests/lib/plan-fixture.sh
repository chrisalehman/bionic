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
