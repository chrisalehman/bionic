#!/bin/bash
# tests/plan-page.test.sh — the plan is the person's: what a version-15 plan may hold, judged where it is
# written and read through the one parser of its authored parts (payload/scripts/lib/plan-read.sh).
#
#   §SECTIONS  a version-15 plan holding a verification matrix, a state or a handoff section is refused at
#              the write with the heading's line named; a version-14 plan holding all three is admitted, and
#              so is a version-15 plan whose only copy of one is inside a fence.
#   §ROW       a version-15 Tasks table with a status or an agent cell is refused, naming the cell; its nine
#              authored cells alone are admitted.
#   §KEYS      each header key the version-15 header has no place for is refused on a version-15 plan, the
#              refusal naming it; the same key on a version-14 plan is admitted.
#
# A later section of this suite is the commit gate's: it judges the same plans at the commit, so it reuses
# `page` and `write_plan` below and appends its own section after §KEYS.
#
# FIXTURE FIDELITY. Each plan is a real file in a scratch git repository with an engaged session, written
# through hooks/canonical-sdlc-governing-skill.sh as the Write tool would post it. Every plan carries the
# whole header the hook demands, so a refusal is the shape's and never a missing flag's: each refused plan
# has an admitted twin that differs only in the part under test (SYNTHESIZED from that header list).
#
# ANTI-VACUITY. Every refusal row stands beside its admitted twin on the same driver, and the line a
# refusal names is computed from the fixture with `grep -n`, never typed.

set -uo pipefail
. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"
HOOK="${BIONIC_HOOKS_DIR}/canonical-sdlc-governing-skill.sh"
PLAN_READ="${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/plan-read.sh"
[ -r "$HOOK" ] && bash -n "$HOOK" || { echo "plan-page: the write hook is missing or does not parse: $HOOK"; exit 1; }

SID="7c1e5b2a-9d40-4f6e-8a31-2b0c9e4d7f15"
R="$(cd "$(mktemp -d)" && pwd -P)"; HOME_DIR="$(mktemp -d)"
trap 'rm -rf "$R" "$HOME_DIR"' EXIT
git -C "$R" init -q .
mkdir -p "$R/.bionic/docs/plans/epic-01-demo" "$R/.bionic/tmp"
: > "$R/.bionic/tmp/engaged-$SID.state"

# page <version> [extra header line]... -> a plan's text: the whole header, a Goal, and the body on stdin.
page() {
  local v="$1" l; shift
  printf -- '---\ngoverning-skill: canonical-sdlc\nsdlc-step: 4\nepic: epic-01-demo\nwave: wave-01-x\n'
  printf 'canonical_sdlc_version: %s\nintent: build\nrigor: double\nscale: wave\n' "$v"
  printf 'cleanup_on_finish: true\nuse_worktree: false\nsurface_type: cli-plugin\nlanguage: bash\n'
  printf 'has_ui: false\nmulti_agent: true\ndeploy_target: n/a\nmodel_plan: orchestrator=a; implementor=b\n'
  for l in "$@"; do printf '%s\n' "$l"; done
  printf -- '---\n\n## Goal\n\nA plan written by a person.\n\n'
  cat
}

# write_plan <text> -> HOOK_EXIT, and HOOK_SAID: the refusal with its detail (BIONIC_WALL_VERBOSE=1).
write_plan() {
  local in
  in="$(jq -n --arg p "$R/.bionic/docs/plans/epic-01-demo/wave-01-x.plan.md" --arg c "$1" --arg s "$SID" \
    '{session_id: $s, hook_event_name: "PreToolUse", tool_name: "Write", tool_input: {file_path: $p, content: $c}}')"
  HOOK_SAID="$(HOME="$HOME_DIR" CLAUDE_CODE_SESSION_ID="$SID" BIONIC_WALL_VERBOSE=1 bash "$HOOK" <<< "$in" 2>&1 >/dev/null)"
  HOOK_EXIT=$?
}

NINE='| id | step | kind | task | deps | size | serves | Files | artifact |
|---|---|---|---|---|---|---|---|---|
| T1 | 4 | build | the first | — | 30 | REQ-1 | a.sh | record/T1.md |'
MACHINE='## Verification Matrix

| AC | tier | status |
|---|---|---|
| AC-1 | T1 | pending |

## SDLC State

current: 4

## Handoff

The next session reads this.'

section "SECTIONS"
write_plan "$(printf '## Tasks\n\n%s\n' "$NINE" | page 15)"
expect_status "a version-15 plan of the person's parts alone is admitted" 0 "$HOOK_EXIT"
for h in "Verification Matrix" "SDLC State" "Handoff"; do
  body="$(printf '## Tasks\n\n%s\n\n%s\n' "$NINE" "$MACHINE")"
  text="$(printf '%s\n' "$body" | page 15)"
  n="$(printf '%s\n' "$text" | grep -n "^## $h\$" | cut -d: -f1)"
  expect_nonempty "the fixture holds ## $h" "$n"
  write_plan "$text"
  expect_status "a version-15 plan holding ## $h is refused" 2 "$HOOK_EXIT"
  expect_contains "the refusal names ## $h at its line" "line $n: ## $h" "$HOOK_SAID"
done
write_plan "$(printf '%s\n' "$MACHINE" | page 14)"
expect_status "a version-14 plan holding all three is admitted" 0 "$HOOK_EXIT"
write_plan "$(printf '## Tasks\n\n%s\n\nAn example:\n\n```\n## Handoff\n```\n' "$NINE" | page 15)"
expect_status "a fenced ## Handoff is prose, and admitted" 0 "$HOOK_EXIT"

section "ROW"
for c in status agent; do
  table="$(printf '%s\n' "$NINE" | awk -v c="$c" 'NR == 1 { sub(/ artifact \|$/, " artifact | " c " |") } NR == 2 { $0 = $0 "---|" } NR == 3 { $0 = $0 " x |" } { print }')"
  text="$(printf '## Tasks\n\n%s\n' "$table" | page 15)"
  n="$(printf '%s\n' "$text" | grep -n '^| id |' | cut -d: -f1)"
  expect_contains "the fixture's header names the cell $c" "| $c |" "$table"
  write_plan "$text"
  expect_status "a version-15 row with the cell $c is refused" 2 "$HOOK_EXIT"
  expect_contains "the refusal names the $c cell at the header's line" "line $n: the Tasks table holds the cell $c" "$HOOK_SAID"
done

section "KEYS"
gone="$(bash -c '. "$1" && printf "%s" "$PLAN_READ_GONE_KEYS"' _ "$PLAN_READ")"
expect_nonempty "the parser lists the keys a version-15 header has no place for" "$gone"
for k in $gone; do
  write_plan "$(printf '## Tasks\n\n%s\n' "$NINE" | page 15 "$k: 2026-11-10")"
  expect_status "a version-15 header with $k: is refused" 2 "$HOOK_EXIT"
  expect_contains "the refusal names $k" "header key $k:" "$HOOK_SAID"
  write_plan "$(printf '%s\n' "$MACHINE" | page 14 "$k: 2026-11-10")"
  expect_status "a version-14 header with $k: is admitted" 0 "$HOOK_EXIT"
done

finish
