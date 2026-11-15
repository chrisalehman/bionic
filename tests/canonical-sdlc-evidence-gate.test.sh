#!/bin/bash
# Tests for canonical-sdlc-evidence-gate.sh — shard 1 of 2 (Sections 1-28, then the AC-E1 sweep and R2).
#
# Sharded in two so a landing that touches the gate proves in minutes. Runners, helpers and
# shared fixtures live in tests/canonical-sdlc-evidence-gate.prelude.sh, sourced by both shards, whose strategy
# note applies to each. Usage: bash tests/canonical-sdlc-evidence-gate.test.sh
#
# THE PRELUDE IS SOURCED BEFORE THE FRAMEWORK, on purpose — see its header.

set -euo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/canonical-sdlc-evidence-gate.prelude.sh"
. "$(dirname "$0")/lib/assert.sh"
. "$(dirname "$0")/lib/bound-marker.sh"
. "$(dirname "$0")/lib/roster-row.sh"

# THE SEAM IS hooks/bash-walls.sh: every case drives the process a Bash tool
# call starts, where `wall_evidence_gate` (payload/scripts/lib/walls.sh) runs; tests/bash-walls.test.sh owns the composition.
HOOK="${BIONIC_HOOKS_DIR}/bash-walls.sh"

# ============================================================
# Section 1: non-commit commands always allowed
# ============================================================

section "Section 1: Non-commit commands pass through"

h1=$(make_home)
# Seed a plan that WOULD block if the command were a commit: a run at Step 5 with no regression proof.
eg_page "$h1" 5 > /dev/null

expect_allow "ls command — not a commit" "$h1" "ls /tmp"
expect_allow "git status — not a commit" "$h1" "git status"
# THE DESTINATION IS A FEATURE BRANCH: protect-main.sh runs in the same process and refuses a push to main,
# so `origin main` would assert the gate's silence through another wall's refusal.
expect_allow "git push — not a commit" "$h1" "git push origin feature/x"

# ============================================================
# Section 2: commit with no plans directory / no plans
# ============================================================

section "Section 2: Commit with no canonical-sdlc state — allowed"

h2=$(make_home)
# plans dir exists but empty

h2b=$(mktemp -d); cleanup_dirs+=("$h2b")
# A bare temp dir: no plan directory of any kind.
expect_allow "no plans dir at all — allow commit" "$h2b" 'git commit -m "x"'

h2c=$(make_home)
write_plan "$h2c" "# regular plan
Some content.
No SDLC State section here." > /dev/null

section "Section 2b: a plan declares 15; one at 14 on disk is a document; the two gates agree"

h2v=$(make_home)
write_plan "$h2v" "${FM/version: 14/version: 13}
## SDLC State
current: 4" v.plan.md > /dev/null
expect_block "a plan at 13 is refused, the fix naming the version a plan is written at" "$h2v" 'git commit -m "x"' "set 'canonical_sdlc_version: 15'"
# Bound, since the walk admits no page at 13 that holds no state section: the session's binding is how one reaches here.
h2s=$(make_home)
bound_marker "$h2s" "$EG_SID" "$(write_plan "$h2s" "${FM/version: 14/version: 13}
# a plan" s.plan.md)"
expect_block "a bound plan at 13 with no state section is refused at the commit too, on its version alone" "$h2s" 'git commit -m "x"' "canonical_sdlc_version: '13'"
for v in 13 14 15; do
  h=$(make_home); git -C "$h" init -q; p=$(write_plan "$h" "${FM/version: 14/version: $v}
## SDLC State
current: 4" "v$v.plan.md"); run_hook "$h" 'git commit -m "x"'
  w=$(jq -n --arg p "$p" --arg c "$(cat "$p")" --arg s "$EG_SID" '{session_id: $s, hook_event_name: "PreToolUse", tool_name: "Write", tool_input: {file_path: $p, content: $c}}' \
    | HOME="$h" CLAUDE_CODE_SESSION_ID="$EG_SID" bash "${BIONIC_HOOKS_DIR}/canonical-sdlc-governing-skill.sh" 2>&1 >/dev/null | grep -c 'unsupported version' || true)
  case "$v" in 13) expect_eq "the write hook refuses 13 for its version" 1 "$w" ;; 14) expect_eq "the write hook says nothing of a plan at 14 on disk" 0 "$w" ;; esac
  expect_eq "the write hook and the commit gate agree on version $v" "$w" "$(grep -c 'unsupported sdlc version' <<< "$HOOK_STDERR" || true)"
done
# The plan builder writes either page: asked for 15, the version 15, no state section, and the log the reader reads.
for v in 14 15; do p=$(plan_fixture --at $v --current 5 "$EG_PF_DIR/plans/epic-99-fixture/wave-0$v.plan.md" wave "$(eg_pf_row T1 dw active)")
  PF_GOT[$v]="$(grep -c -e "^canonical_sdlc_version: $v\$" -e '^## SDLC State' "$p")|$(bash "$BIONIC_SCRIPTS_DIR/payload/scripts/reader.sh" "$p" status T1 | head -1)"; done
expect_eq "plan_fixture at 14 holds the version and its state section; at 15 the version alone, and the row's dispatch in its log" \
  "2|state=dispatched 1|state=dispatched" "${PF_GOT[14]} ${PF_GOT[15]}"

# ============================================================
# Section 9: a criterion is owed at the step whose task proves it
# ============================================================
#
# A criterion is owed at the step of the task that proves it: before it, a pending or blocked criterion owes neither
# its per-tier keys nor an auditor's verdict. The literal 9 is the close's step; a criterion owed at 9 is the close's
# to settle, never demanded of an open plan. The criteria table's Task column names the task.
# FIXTURE FIDELITY: the page at 15 is SYNTHESIZED in the nine cells and the Eval design, its one landing an event of
# its run's log; the Step-9 runs are eg_page's.
# fails-when: a criterion is owed at a step other than its task's (9o), a dash or a missing column names a step
# (9o, 9q), the close settles one it does not measure (9p), or the deferral outlives its owing step (9k, 9l).

section "Section 9: a criterion is owed at the step whose task proves it"

# The two file-scope readers the judge and the card share with the gate, asked as hooks/poker/judge.sh asks them.
ow_ask() {  # <plan> <function> [args…] -> what the function prints, then `rc=<n>`
  bash -c 'L="$1"; shift; . "$L/root.sh" && . "$L/run.sh" && . "$L/units.sh" && . "$L/walls.sh" >/dev/null 2>&1 || exit 9
    PLAN="$1"; RIGOR="$(plan_frontmatter_get "$1" rigor)"; shift; "$@"; echo "rc=$?"' _ "$BIONIC_SCRIPTS_DIR/payload/scripts/lib" "$@"
}
# At 15 a criterion has no block: the criteria table's Task column names the task that proves it.
ow_h15="$(make_home)"; ow_15="$ow_h15/.bionic/docs/plans/epic-01-x/wave-01-x.plan.md"; mkdir -p "${ow_15%/*}" "$ow_h15/.bionic/docs/record/wave-01-x"
ow_page15() {  # <Task column: yes|no> -> the page at 15, T1 landed in its log
  local h=' Task |' s='---|' x c
  [ "$1" = yes ] || { h=''; s=''; }
  printf -- '---\ncanonical_sdlc_version: 15\nrigor: double\nscale: wave\n---\n## Tasks\n\n| id | step | kind | task | deps | size | serves | Files | artifact |\n|---|---|---|---|---|---|---|---|---|\n'
  printf '| T1 | 4 | build | the build | — | 30 | REQ-1 | a.sh | — |\n| T7 | 7 | doc | the release | — | 10 | REQ-1 | CHANGELOG.md | — |\n| T9 | 9 | close | the close | — | 10 | REQ-1 | — | — |\n'
  printf '\n## Eval design\n\n| Requirement | Approach | Criterion | Eval type | Eval | Fails when |%s\n|---|---|---|---|---|---|%s\n' "$h" "$s"
  for x in "AC-2|T9" "AC-3|T1" "AC-4|T7" "AC-5|9" "AC-6|T1, T9" "AC-7|—"; do c=" ${x#*|} |"; [ "$1" = yes ] || c=''
    printf '| REQ-1 | a suite | %s | live | `bash payload/hooks/session-poker.sh landing-report --hand-holds` at the close | above zero |%s\n' "${x%%|*}" "$c"; done
}
printf 'run/v1|ev=published|row=T1|commit=%s|kind=queue|by=-|why=-|at=2026-11-01T00:00:01Z\n' "$EG_HEAD" > "$ow_h15/.bionic/docs/record/wave-01-x/run.log"
ow_owe15() { local a; for a in AC-2 AC-3 AC-4 AC-5 AC-6 AC-7; do printf '%s:%s:%s ' "$a" "$(ow_ask "$ow_15" matrix_owing_step "$ow_15" "$a" | head -1 | sed 's/^rc=.*//')" "$(ow_ask "$ow_15" matrix_owing_open "$ow_15" "$a" | head -1 | sed 's/^rc=.*//')"; done; }
ow_page15 yes > "$ow_15"
expect_eq "9o at 15 each criterion is owed at the step of the task its Task cell names, open while that task is not landed; a dash names none" \
  "AC-2:9:yes AC-3:4: AC-4:7:yes AC-5:9: AC-6:9:yes AC-7:: " "$(ow_owe15)"
expect_eq "9p …so the close settles the criteria owed at 9 whose eval is its measure, and the advance to 8 owes those owed before it and none of these" \
  "AC-2 AC-5 AC-6|AC-3 AC-4 AC-7" "$(ow_ask "$ow_15" matrix_close_rows "$ow_15" | /usr/bin/grep -v '^rc=' | paste -sd' ' -)|$(ow_ask "$ow_15" matrix_unruled "$ow_15" 8 | /usr/bin/grep -v '^rc=' | paste -sd' ' -)"
ow_page15 no > "$ow_15"
expect_eq "9q a page at 15 with no Task column owes every criterion at no particular step, as before the column" \
  "AC-2:: AC-3:: AC-4:: AC-5:: AC-6:: AC-7:: " "$(ow_owe15)"
ow_p9="$(eg_page "$(make_home)" 9)"
ow_p9d="$(eg_page "$(make_home)" 9 'run/v1|ev=step|n=9|delivered=2026-10-24T00:00Z wave-01|at=2026-10-24T00:00:00Z')"
expect_eq "9k a row owed at 9 is deferred while the run is open, and owed once its step 9 carries delivered:" \
  "rc=0|rc=1" "$(ow_ask "$ow_p9" matrix_row_deferred "$ow_p9" 9 9 pending | tail -1)|$(ow_ask "$ow_p9d" matrix_row_deferred "$ow_p9d" 9 9 pending | tail -1)"
expect_eq "9l a discharged row is never deferred, and a pending one is before its step" "rc=1|rc=0" \
  "$(ow_ask "$ow_p9" matrix_row_deferred "$ow_p9" 9 6 discharged | tail -1)|$(ow_ask "$ow_p9" matrix_row_deferred "$ow_p9" 9 6 pending | tail -1)"

# ============================================================
# Section 26: the walk gate reads the walk
# ============================================================
# The walk the gate reads is the run's newest walk proof, which proof-add walk registers only once it parsed the
# record's verdict table, so the AC identifiers in that record are its verdicts.
# fails-when: a discharged criterion admitted with no walk proof (26a), a walk proof naming an absent record admitted
# (26c), or a walk proof the run's log holds not read as the walk (26d).

section "Section 26: the walk gate reads the walk"

wg_home() {  # [<record the walk proof names>] -> a sandbox at 15, current 5, the walk owed and its criterion discharged
  local h p; h=$(make_home); eg_head_repo "$h"; mkdir -p "$h/.bionic/docs/record/w"
  printf 'verdict: confirmed\n\n| AC | verdict | why |\n|---|---|---|\n| AC-1.1 | CONFIRMED | drove it |\n' > "$h/.bionic/docs/record/w/walk.md"
  p=$(eg_page "$h" 5 "run/v1|ev=proof|kind=regression|head=$EG_HEAD|evidence=record/floor.log|at=2026-10-24T00:00:00Z" \
    "run/v1|ev=proof|ac=AC-1.1|evidence=record/generic-evidence.md|at=2026-10-24T00:00:01Z" \
    ${1:+"run/v1|ev=proof|kind=walk|head=$EG_HEAD|evidence=record/w/$1|at=2026-10-24T00:00:02Z"})
  awk '!/^walk: exempt$/' "$p" > "$p.t" && mv "$p.t" "$p"; printf '%s' "$h"
}
expect_block "26a a discharged criterion with no walk proof is refused for the walk" "$(wg_home)" 'git commit -m "x"' "no walk recorded"
expect_block "26c a walk proof naming an absent record is refused for it" "$(wg_home other.md)" 'git commit -m "x"' "record/w/other.md"
expect_allow "26d a walk proof the run's log holds is the walk, its record's AC identifiers its verdicts" "$(wg_home walk.md)" 'git commit -m "x"'

# ============================================================
# Section 27: an epic's plan at 15 owes its own spec, never a wave's requirements
# ============================================================
# An epic has no wave and no requirements file: its Step 1 and 2 write specs/<epic>/epic.spec.md. fails-when: a run
# bound to an epic at 15 is refused for the header's wave when its spec stands (27a), is admitted with no spec (27b),
# or a wave's plan, asked beside it, stops owing the requirements file it names (27c, 27d).

section "Section 27: a bound epic at 15 owes its spec"

ep_home() {  # [spec: yes|no] -> a sandbox whose one plan is an epic at 15, current 3, Step 2's approval in its log
  local h p d; h=$(make_home); eg_head_repo "$h"
  p=$(eg_page "$h" 3 'run/v1|ev=approval|key=step2|by=fixture|said=approved|at=2026-10-04T00:30:00Z'); d="${p%/plans/*}"
  mkdir -p "$d/record/epic-99-fixture" "$d/specs/epic-99-fixture"; mv "$d/record/wave-01-fixture/run.log" "$d/record/epic-99-fixture/run.log"
  rm -f "$d/specs/epic-99-fixture/wave-01-fixture".*
  awk '/^wave: / { next } /^rigor: / { $0 = "rigor: double" } /^scale: / { $0 = "scale: epic" } /^multi_agent: / { $0 = "multi_agent: true" } { print }' "$p" > "${p%/*}/epic.plan.md" && rm "$p"
  [ "${1:-yes}" = no ] || printf '# epic spec\n' > "$d/specs/epic-99-fixture/epic.spec.md"
  printf '%s' "$h"
}
expect_allow "27a an epic at 15, current 3, its spec standing and Step 2 approved, commits" "$(ep_home yes)" 'git commit -m "x"'
expect_block "27b …and with its spec gone is refused for that file, named" "$(ep_home no)" 'git commit -m "x"' "owed at 15: Step 1's requirements: specs/epic-99-fixture/epic.spec.md"
wv_home() {  # [requirements: yes|no] -> a wave at 15, current 3, rigor double, multi_agent true, Step 2 approved
  local h p; h=$(make_home); eg_head_repo "$h"
  p=$(eg_page "$h" 3 'run/v1|ev=approval|key=step2|by=fixture|said=approved|at=2026-10-04T00:30:00Z')
  sed -i '' -e 's/^rigor: .*/rigor: double/' -e 's/^multi_agent: .*/multi_agent: true/' "$p"
  [ "${1:-yes}" = yes ] || rm -f "${p%/plans/*}/specs/epic-99-fixture/wave-01-fixture.requirements.md"
  printf '%s' "$h"
}
expect_allow "27c a wave at 15, rigor double, its requirements file standing, commits" "$(wv_home yes)" 'git commit -m "x"'
expect_block "27d …and with that file gone is refused for it, named as before" "$(wv_home no)" 'git commit -m "x"' "owed at 15: Step 1's requirements: specs/epic-99-fixture/wave-01-fixture.requirements.md"

finish
