# tests/lib/plan-fixture.sh — THE ONE PLAN A FIXTURE WRITES, AT EITHER SCALE AND EITHER VERSION
#
#     . "$(dirname "$0")/lib/plan-fixture.sh"
#     P="$(plan_fixture "$R/.bionic/docs/plans/epic-99-fixture/wave-01-fixture.plan.md" task \
#            "| T1 | 4 | build | the first build | implementor | — | — | 30 | REQ-1 | a.sh | — | — | pending |")"
#
# ONE LEDGER SHAPE (D2). The scales differ in their ARTIFACTS and never in the ledger: a wave plan
# cites a requirements file and a spec, a task plan carries its design as a paragraph in the plan
# itself. So this helper takes the scale as a parameter and changes only those artifact lines with it.
#
# plan_fixture [--at 14] [--current <value>] <path> <task|wave> [<row>...] -> writes the plan at <path>
#   (directories made), prints <path>. Each <row> is one whole `## Tasks` data row in the header's
#   column order (`PLAN_FIXTURE_HEADER`). `--current` is the run's step (default 4); at 14 it is written into
#   `current:` verbatim — a test of a value the readers refuse (`T1`) passes it there, and gets the same plan
#   around it. At wave scale, when <path> sits under a `<docs root>/plans/` directory, the two
#   artifacts its Step-1 and Step-2 lines cite are written under `<docs root>/specs/` beside it.
#
# TWO VERSIONS. `--at 14` writes the plan at 14: `current:` in a `## SDLC State`, the thirteen-cell
# table, a `## Dispatch ledger` and a `## Verification Matrix`. Unasked, it writes the page a version-15
# run holds, the same words in their homes there: no state, ledger or matrix section, the header naming
# the working branch and base, each row in its nine authored cells, the criterion's fails-when in an
# `## Eval design`, and the run's log (`plan_fixture_log`) holding what the other cells and the state
# section said. Its step is a number and its plan sits under plans/, where the reader finds a log.
#
# HOOK-VALID. The frontmatter is the whole set hooks/canonical-sdlc-governing-skill.sh demands of a
# plan (the version, intent, rigor, scale, the opt-in and discriminator flags, model_plan), so a
# fixture that writes this through the Write hook is admitted, and a test may say so.
PLAN_FIXTURE_HEADER='| id | step | kind | task | agent | deps | reads | size | serves | Files | worktree | base | status |
|---|---|---|---|---|---|---|---|---|---|---|---|---|'

plan_fixture() {  # [--at 14] [--current <value>] <path> <task|wave> [<row>...]
  local cur=4 v=15 path scale docs rel stem epic row
  if [ "${1:-}" = "--at" ]; then v="${2:-}"; shift 2; fi
  if [ "${1:-}" = "--current" ]; then cur="${2:-}"; shift 2; fi
  path="${1:?plan_fixture: a path}"; scale="${2:?plan_fixture: a scale}"; shift 2
  case "$scale" in task|wave) : ;; *) echo "plan_fixture: scale '$scale' is not task or wave" >&2; return 2 ;; esac
  case "$v:$cur:$path" in 14:*) : ;; 15:[1-9]:*/plans/*) : ;;
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
    printf 'canonical_sdlc_version: %s\nintent: bugfix\nrigor: single\nscale: %s\n' "$v" "$scale"
    printf 'cleanup_on_finish: true\nuse_worktree: true\nsurface_type: none\nlanguage: none\n'
    printf 'has_ui: false\nmulti_agent: false\ndeploy_target: none\nmodel_plan: orchestrator=fable-5-high\n'
    [ "$v" = 14 ] || printf 'working-branch: wave/01-fixture\nbase-sha: abc1234\n'
    printf 'walk: exempt\nparallel-budget: writers=8 suites=4 worktrees=32 test_jobs=8 source=user\n---\n\n'
    printf '# fixture plan\n\n## Goal\n\nOne plan a fixture writes, at either scale, in the one ledger shape.\n\n'
    if [ "$v" = 14 ]; then
      printf '## SDLC State\n\ncurrent: %s\napproved-by: fixture 2026-10-04T00:00Z "approved"\n\n' "$cur"
      if [ "$scale" = wave ]; then
        printf -- '- Step 1: requirements: specs/%s/%s.requirements.md\n' "$epic" "$stem"
        printf -- '- Step 2: spec: specs/%s/%s.spec.md\n' "$epic" "$stem"
      else
        printf -- '- Step 1: requirements: this plan, ## Requirements\n- Step 2: design: this plan, ## Design\n'
      fi
      printf -- '- Step 3: plan: %s\n' "$rel"
      printf -- '- Step 4: opened\n  worktree: .worktrees/01-fixture\n  base-sha: abc1234\n  branch: wave/01-fixture\n\n'
    fi
    if [ "$scale" = task ]; then
      printf '## Requirements\n\n### REQ-1 — the fixture\n\n- AC-1.1 the fixture holds.\n\n'
      printf '## Design\n\nThe fixture design paragraph: a task-scale run writes its design here, not in a spec.\n\n'
    fi
    if [ "$v" = 15 ]; then
      printf '## Tasks\n\n| id | step | kind | task | deps | size | serves | Files | artifact |\n|---|---|---|---|---|---|---|---|---|\n'
      _plan_fixture_rows "$(plan_fixture_log "$path")" "$cur" "$@" || return 1
      printf '\n## Eval design\n\n| Requirement | Approach | Criterion | Eval type | Eval | Fails when |\n|---|---|---|---|---|---|\n'
      printf '| REQ-1 | fixture | AC-1.1 | hermetic | `tests/a.test.sh` | the fixture is wrong |\n'
    else
      printf '## Tasks\n\n%s\n' "$PLAN_FIXTURE_HEADER"
      for row in "$@"; do printf '%s\n' "$row"; done
      printf '\n## Dispatch ledger\n\n| id | agent | dispatched | expected | artifact | landed | notes |\n|---|---|---|---|---|---|---|\n'
      printf '\n## Verification Matrix\n\n| AC | tier | status | evidence | auditor |\n|---|---|---|---|---|\n'
      printf '| AC-1.1 | T2 | pending | — | — |\n\nAC-1.1:\n  provenance: fixture\n  fails-when: the fixture is wrong\n'
    fi
  } > "$path" || return 1
  printf '%s' "$path"
}

# plan_fixture_log <plan> -> the path of the run's log beside a plan under <docs>/plans/[<epic>/], as lib/reader.sh
#   `reader_record` joins them: <docs>/record/<the plan's name less .plan.md>/run.log.
plan_fixture_log() {
  local d="${1%/*}" n="${1##*/}"; case "${d%/*}" in */plans) d="${d%/*}" ;; esac
  printf '%s/record/%s/run.log' "${d%/plans}" "${n%.plan.md}"
}

# plan_fixture_state_add <plan> <line> -> <line> placed in the plan's unfenced `## SDLC State`, where a run at 14 held
#   its proofs: after the section's last proved, waived, deferred, moved or inherited line, else its last non-blank line,
#   so a line's place is its age. 1, the plan unchanged, when it has no such section. The line goes in through the
#   environment, not `-v`, which would read a backslash in a waiver's reply as an escape.
plan_fixture_state_add() {
  PF_LINE="$2" awk '{ row[NR] = $0 } /^[[:space:]]*```/ { f = !f; next } f { next }
    /^##[[:space:]]/ { s = ($0 ~ /^##[[:space:]]+SDLC State/); if (s) { seen = 1; n = NR }; next }
    s && /^(proved|waived|deferred|moved|inherited):[[:space:]]/ { p = NR }
    s && /[^[:space:]]/ { n = NR }
    END { if (!seen) exit 1; for (i = 1; i <= NR; i++) { print row[i]; if (i == (p ? p : n)) print ENVIRON["PF_LINE"] } }' "$1" > "$1.pf" \
    && mv "$1.pf" "$1" || { rm -f "$1.pf"; return 1; }
}

# _plan_fixture_rows <log> <step> [<row>...] -> each row, given in PLAN_FIXTURE_HEADER's thirteen cells, printed in the
#   nine a version-15 row holds; the log is written whole with what the other cells and the state section said: a step
#   event for each step to <step> (step 9 not delivered, as the state section's open 9 was), the plan's approval (the
#   one approval a verb writes), then
#   per row its dispatch under the agent cell's name (a row not
#   pending), its tree, and its landing. Each line has its own instant, so the fold reads them in the order written.
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
