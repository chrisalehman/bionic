# tests/lib/bash-walls-world.sh — THE BASH-WALLS WORLD: the fixture repository, its door, and the run at 15 the
# evidence gate judges
#
#     . "$(dirname "$0")/lib/bash-walls-world.sh"
#
# The two bash-walls suites load it through tests/bash-walls.prelude.sh; a suite that drives the same gate from
# another side loads it itself, so the world has one home.
#
# THE CALLER SETS SANDBOX (every repository is made inside it), SID (the session an engaged repository is marked
# for), EG6_LIB (the proof library eg6_reading prints through) and H_EG6 (the base eg6_plan names); each is read when
# a builder runs.

declare -F maker_stop >/dev/null 2>&1 || { [ -r "${BASH_SOURCE[0]%/*}/maker-stop.sh" ] && . "${BASH_SOURCE[0]%/*}/maker-stop.sh"; } \
  || { echo "bash-walls-world.sh: cannot load ${BASH_SOURCE[0]%/*}/maker-stop.sh" >&2; return 1; }
declare -F plan_fixture >/dev/null 2>&1 || { [ -r "${BASH_SOURCE[0]%/*}/plan-fixture.sh" ] && . "${BASH_SOURCE[0]%/*}/plan-fixture.sh"; } \
  || { echo "bash-walls-world.sh: cannot load ${BASH_SOURCE[0]%/*}/plan-fixture.sh" >&2; return 1; }

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
    || maker_stop mk_repo "no repository of its own at '$repo'"
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
