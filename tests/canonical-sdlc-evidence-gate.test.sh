#!/bin/bash
# Tests for canonical-sdlc-evidence-gate.sh — shard 1 of 2 (Sections 1-28, then the AC-E1 sweep and R2).
#
# The evidence-gate suite was sharded in two at wave-30 T3 (D8b) so a landing that touches the
# gate proves in minutes. The runners, helpers and shared plan fixtures live in
# tests/canonical-sdlc-evidence-gate.prelude.sh, sourced by both shards; the strategy note
# there applies to each. Usage: bash tests/canonical-sdlc-evidence-gate.test.sh
#
# THE PRELUDE IS SOURCED BEFORE THE FRAMEWORK, on purpose — see its header.

set -euo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/canonical-sdlc-evidence-gate.prelude.sh"
. "$(dirname "$0")/lib/assert.sh"
. "$(dirname "$0")/lib/bound-marker.sh"
. "$(dirname "$0")/lib/roster-row.sh"

# THE SEAM IS hooks/bash-walls.sh (epic-23 wave-11-lean-spine, T23). This wall is a
# FUNCTION now — `wall_evidence_gate` in payload/scripts/lib/walls.sh — registered through
# the one PreToolUse|Bash command object that carries all five. Every case below drives
# that process, which is what a Bash tool call actually starts; the wall's own verdict is
# unchanged and tests/bash-walls.test.sh owns the composition the process adds.
HOOK="${BIONIC_HOOKS_DIR}/bash-walls.sh"

# THE FLOOR A RUN PAST STEP 6 CARRIES (wave-35 T31; D20, A-orch-50). From `current: 7` the gate refuses a
# `regression: yes` plan whose section holds no `proved: kind=regression` line. A fixture at Step 7..9 that is
# about something else is written through eg_floor: the prelude's readings (eg_readings) and one floor
# line in proof-add regression's shape after `current:`. Rows about the floor arm itself write plans as given.
eg_floor() {  # <plan content> -> the content with the readings and one floor proof line
  eg_readings "$1" | EG_H="$EG_HEAD" awk '{ print }
    !done && /^[[:space:]]*current[[:space:]]*:[[:space:]]*[7-9][ab]?[[:space:]]*$/ {
      printf "proved: kind=regression head=%s at=2026-10-12T00:00:00Z evidence=record/floor.log\n", ENVIRON["EG_H"]; done = 1 }'
}

# ============================================================
# Section 1: non-commit commands always allowed
# ============================================================

section "Section 1: Non-commit commands pass through"

h1=$(make_home)
# Seed a plan that WOULD block if the command were a commit.
write_plan "$h1" "$FM
## SDLC State
current: 5
approved-by: fixture 2026-09-07T00:00Z "approved"
Step 5: TODO" > /dev/null

expect_allow "ls command — not a commit" "$h1" "ls /tmp"
expect_allow "git status — not a commit" "$h1" "git status"
# THE DESTINATION IS A FEATURE BRANCH, AND ONLY SINCE T23. This row is about "a push is
# not a commit", and the destination was incidental — but hooks/protect-main.sh is a
# function in the same process now, and it refuses a push to main in every project on the
# machine, which it did as a separate process before this suite ever saw the payload. A
# row that kept `origin main` would be asserting the GATE's silence through another wall's
# refusal, which is a green that proves a different line than the one it names.
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

# ============================================================
# Section 3: valid evidence allows commit
# ============================================================

section "Section 3: Valid evidence in ## SDLC State — allowed"

h3=$(make_home)
write_plan "$h3" "$FM
# plan

## SDLC State
current: 3
Step 1: /path/to/ideate.md
Step 2: /path/to/spec.md
Step 3: .bionic/docs/plans/this.md

## Other section" > /dev/null
expect_allow "valid pointer-step evidence — allow" "$h3" 'git commit -m "step 3 done"'

# A lettered step binds the arms of its number (T67, review pass 46 N10), so 8b past Verify
# owes the matrix Step 8 owes, and the walk arm reads its discharged row; the fixture carries a
# discharged matrix and the Step-0 `walk: exempt` (T80).
h3b=$(make_home)
write_plan "$h3b" "$(eg_floor "${FM%---}walk: exempt
---
## SDLC State
current: 8b
approved-by: fixture 2026-09-07T00:00Z "approved"
Step 8b: critic report attached in docs/review.md

## Verification Matrix

stack-health: n/a: no long-running serve

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1 | T1 | discharged | see AC-1 | CONFIRMED |

AC-1:
  fails-when: the planted defect this eval must go red on
  evidence: record/generic-evidence.md
  tier-run: bash test.sh — unit
  readback: 40/40 asserted")" > /dev/null
expect_allow "valid step 8b evidence — allow" "$h3b" 'git commit -m "critic done"'

h3c=$(make_home)
write_plan "$h3c" "$FM
## SDLC State
current: 10
approved-by: fixture 2026-09-07T00:00Z "approved"
- Step 10: commit SHA abc123 body written" > /dev/null
expect_allow "bulleted Step line — allow" "$h3c" 'git commit -m "x"'

# ============================================================
# Section 4: malformed / missing SDLC State pieces
# ============================================================

section "Section 4: Malformed SDLC State — blocked"

h4=$(make_home)
write_plan "$h4" "$FM
## SDLC State
# no current line, no phase lines

## Next section" > /dev/null
expect_block "missing 'current: N' line" "$h4" 'git commit -m "x"' "missing a valid 'current: N'"

h4b=$(make_home)
write_plan "$h4b" "$FM
## SDLC State
current: 5
approved-by: fixture 2026-09-07T00:00Z "approved"
Step 1: done
Step 2: done
# no Step 5 line" > /dev/null
expect_block "no matching Step N line" "$h4b" 'git commit -m "x"' "no 'Step 5:' line"

h4c=$(make_home)
write_plan "$h4c" "$FM
## SDLC State
current: five
Step 5: something" > /dev/null
expect_block "non-numeric current" "$h4c" 'git commit -m "x"' "missing a valid 'current: N'"

# ============================================================
# Section 5: empty / placeholder evidence — blocked
# ============================================================

section "Section 5: Placeholder evidence — blocked"

h5=$(make_home)
write_plan "$h5" "$FM
## SDLC State
current: 5
approved-by: fixture 2026-09-07T00:00Z "approved"
Step 5:   " > /dev/null
expect_block "empty evidence line" "$h5" 'git commit -m "x"' "is empty"

for token in TODO pending "in progress" XXX TBD placeholder; do
  h=$(make_home)
  write_plan "$h" "$FM
## SDLC State
current: 5
approved-by: fixture 2026-09-07T00:00Z "approved"
Step 5: $token" > /dev/null
  expect_block "placeholder '$token'" "$h" 'git commit -m "x"' "placeholder"
done

# Case-insensitive placeholder match. Under whole-value equality the ENTIRE
# trimmed value must equal a token, so the fixture is the bare token 'Todo'
# (was "Todo — still writing", which is prose that merely starts with the
# token — legal under the new contract; see 5e).
h5b=$(make_home)
write_plan "$h5b" "$FM
## SDLC State
current: 5
approved-by: fixture 2026-09-07T00:00Z "approved"
Step 5: Todo" > /dev/null
expect_block "placeholder 'Todo' (mixed case, bare token)" "$h5b" 'git commit -m "x"' "placeholder"

# --- whole-value equality: the placeholder ban matches only when the whole
# trimmed, lowercased value EQUALS a token (todo/pending/in progress/
# inprogress/xxx/tbd/placeholder). A token appearing as a substring of a
# longer value is legal evidence.

# 5c — whole-line 'Step 5: pending' (single-line value) → block.
h5c=$(make_home)
write_plan "$h5c" "$FM
## SDLC State
current: 5
approved-by: fixture 2026-09-07T00:00Z "approved"
Step 5: pending" > /dev/null
expect_block "whole-line 'Step 5: pending' → block" "$h5c" 'git commit -m "x"' "placeholder"

# 5d — trim + lowercase before comparison: '  Pending  ' (padded, mixed case)
# as a continuation value still equals the token → block.
h5d=$(make_home)
write_plan "$h5d" "$FM
## SDLC State
current: 5
approved-by: fixture 2026-09-07T00:00Z "approved"
Step 5:
  readback:   Pending  " > /dev/null
expect_block "padded mixed-case 'readback:   Pending  ' → block" "$h5d" 'git commit -m "x"' "placeholder"

# 5e — a value that merely CONTAINS a token as a substring is legal:
# 'resolved all TODOs from the last review' (contains 'todo') → allow. Under
# the OLD substring ban this was a false block.
h5e=$(make_home)
write_plan "$h5e" "$FM
## SDLC State
current: 3
Step 3: resolved all TODOs from the last review" > /dev/null
expect_allow "substring-only 'resolved all TODOs' → allow (whole-value equality)" \
  "$h5e" 'git commit -m "x"'

# 5f — a continuation key whose whole value equals a token still blocks:
# 'stack-health: pending' (value 'pending') → block.
h5f=$(make_home)
write_plan "$h5f" "$FM
## SDLC State
current: 5
approved-by: fixture 2026-09-07T00:00Z "approved"
Step 5:
  stack-health: pending" > /dev/null
expect_block "continuation 'stack-health: pending' (whole value) → block" \
  "$h5f" 'git commit -m "x"' "placeholder"

# ============================================================
# Section 6: compound commands + edge cases
# ============================================================

section "Section 6: Compound commands — commit detection"

h6=$(make_home)
write_plan "$h6" "$FM
## SDLC State
current: 5
approved-by: fixture 2026-09-07T00:00Z "approved"
Step 5: TODO" > /dev/null
expect_block "cd && git commit" "$h6" 'cd /tmp && git commit -m "x"' "placeholder"
expect_block "git add && git commit" "$h6" 'git add . && git commit -m "x"' "placeholder"

# False-positive check: quoted "git commit" as prose shouldn't trigger
# gate on its own, but a real `git commit` in the same command does.
h6b=$(make_home)
write_plan "$h6b" "$FM
## SDLC State
current: 5
approved-by: fixture 2026-09-07T00:00Z "approved"
Step 5: TODO" > /dev/null
expect_allow "echo only, no real commit" "$h6b" 'echo "we will git commit later"'

# ============================================================
# Section 7: newest-plan-wins
# ============================================================

section "Section 7: Newest plan file is the one enforced"
#
# THIS SECTION IS THE FALLBACK ARM, and since wave-session-bound-run that is a scope rather
# than a description of the whole rule. "Which plan answers for the run" is now a property of
# the SESSION: `session_run` reads the binding out of this session's engagement marker, and
# only a session with NO binding falls back to the newest plan — which is what every fixture
# below is, because `make_home` plants an empty marker (AC-3, and spec assumption A7: this
# pin remains true of the unbound arm and is re-scoped rather than deleted). Section 35 owns
# the bound arm, where the older of two open plans governs its own session and the newest
# governs nobody's.

h7=$(make_home)
# Older plan with valid state
write_plan "$h7" "$FM
## SDLC State
current: 5
approved-by: fixture 2026-09-07T00:00Z "approved"
Step 5: tests green" "old.md" > /dev/null
# Make old.md older than now.
touch -t 202001010000 "$h7/.bionic/docs/plans/old.md" 2>/dev/null || \
  touch -d "2020-01-01" "$h7/.bionic/docs/plans/old.md" 2>/dev/null || true
# Newer plan with bad state
write_plan "$h7" "$FM
## SDLC State
current: 5
approved-by: fixture 2026-09-07T00:00Z "approved"
Step 5: TODO" "new.md" > /dev/null
expect_block "newest plan rules — bad state blocks even with valid older plan" \
  "$h7" 'git commit -m "x"' "placeholder"

# A marker-less newer file is SKIPPED by plan selection (landing-supervision T8):
# it no longer shields an older plan from enforcement. The bad older plan governs.
h7b=$(make_home)
write_plan "$h7b" "$FM
## SDLC State
current: 5
approved-by: fixture 2026-09-07T00:00Z "approved"
Step 5: TODO" "old-bad.md" > /dev/null
touch -t 202001010000 "$h7b/.bionic/docs/plans/old-bad.md" 2>/dev/null || \
  touch -d "2020-01-01" "$h7b/.bionic/docs/plans/old-bad.md" 2>/dev/null || true
write_plan "$h7b" "# unrelated plan, no SDLC State" "new-neutral.md" > /dev/null
expect_block "marker-less newest is skipped — bad older plan still governs" \
  "$h7b" 'git commit -m "x"' "placeholder"

# Preserved ambiguity: when ONLY marker-less files exist, there is no plan to
# enforce and the commit passes silently (the ratified pass-on-ambiguity direction).
h7c=$(make_home)
write_plan "$h7c" "# unrelated plan, no SDLC State" "only-neutral.md" > /dev/null

# ============================================================
# Section 8: project-local plan directory (.bionic/docs/plans/)
# ============================================================

section "Section 8: Project-local plan dir (CLAUDE_PROJECT_DIR)"

# Helpers that exercise both plan-dir paths at once.
expect_allow_both() {
  local label="$1" home_dir="$2" project_dir="$3" command="$4"
  run_hook_with_project "$home_dir" "$project_dir" "$command"
  if [ "$HOOK_EXIT" -eq 0 ] && [ -z "$HOOK_STDERR" ]; then
    ok "$label"
  else
    no "$label" "expected allow; got exit=$HOOK_EXIT stderr='$HOOK_STDERR'"
  fi
}

expect_block_both() {
  local label="$1" home_dir="$2" project_dir="$3" command="$4" substr="${5:-BLOCKED}"
  run_hook_with_project "$home_dir" "$project_dir" "$command"
  if [ "$HOOK_EXIT" -eq 2 ] && grep -q "$substr" <<<"$HOOK_STDERR"; then
    ok "$label"
  else
    no "$label" "expected block with '$substr'; got exit=$HOOK_EXIT stderr='$HOOK_STDERR'"
  fi
}

# 8a — project-local plan alone, global empty: hook honors project plan.
h8a=$(make_home); p8a=$(make_project)
write_project_plan "$p8a" "$FM
## SDLC State
current: 5
approved-by: fixture 2026-09-07T00:00Z "approved"
Step 5: TODO" > /dev/null
expect_block_both "project-local plan (bad) blocks with no global plan" \
  "$h8a" "$p8a" 'git commit -m "x"' "placeholder"

# 8b — project-local plan alone, global empty: good evidence allows.
h8b=$(make_home); p8b=$(make_project)
write_project_plan "$p8b" "$FM
## SDLC State
current: 3
Step 3: commit abc123 tests green" > /dev/null
expect_allow_both "project-local plan (good) allows with no global plan" \
  "$h8b" "$p8b" 'git commit -m "x"'

# ---- 8c..8i: the directories this gate deliberately does NOT search ----
#
# BEHAVIOR CHANGE 2026-07-28 (user ruling): `~/.claude/plans/` and
# `<project>/docs/superpowers/plans/` are out of the search set entirely —
# bionic gates bionic's plans. 8c/8d/8e/8f/8h assert the NEW contract and each
# FAILS against the pre-change hook; that is what makes them worth having.
# [WALL: hooks/canonical-sdlc-evidence-gate.sh]

# 8c — a canonical plan in the global directory with no project plan anywhere:
# NOT gated. This blocked until 2026-07-28. The harness's own plan mode owns
# that directory; what it holds is not this project's run state.
h8c=$(make_home); p8c=$(make_project)
write_global_note "$h8c" "$FM
## SDLC State
current: 5
approved-by: fixture 2026-09-07T00:00Z "approved"
Step 5: TODO" "global-canonical.md" > /dev/null

# 8d — THE LIVE DEFECT. A project whose plan is correctly placed and whose
# current-step evidence is a placeholder, plus a NEWER non-canonical note in the
# global directory (plan mode drops these routinely). Selection took the newest
# .md across the whole set, so the note won, carried no `## SDLC State`, and the
# hook exited 0 — every commit in that project ran ungated. Two such files were
# sitting in the real ~/.claude/plans when this was found.
h8d=$(make_home); p8d=$(make_project)
write_project_plan "$p8d" "$FM
## SDLC State
current: 5
approved-by: fixture 2026-09-07T00:00Z "approved"
Step 5: TODO" > /dev/null
touch -t 202001010000 "$p8d/.bionic/docs/plans/active.md" 2>/dev/null || \
  touch -d "2020-01-01" "$p8d/.bionic/docs/plans/active.md" 2>/dev/null || true
write_global_note "$h8d" "# scratch note from plan mode

Not a canonical-sdlc plan — no SDLC State section." "newer-note.md" > /dev/null
expect_block_both "newer non-canonical global note cannot hijack plan selection" \
  "$h8d" "$p8d" 'git commit -m "x"' "placeholder"

# 8e — the same defect with a genuinely canonical, genuinely newer global plan
# whose own evidence is fine: the project's older, bad plan is still the one
# gated. Until 2026-07-28 the global plan won and the commit was allowed.
h8e=$(make_home); p8e=$(make_project)
write_project_plan "$p8e" "$FM
## SDLC State
current: 5
approved-by: fixture 2026-09-07T00:00Z "approved"
Step 5: TODO" "old-proj.md" > /dev/null
touch -t 202001010000 "$p8e/.bionic/docs/plans/old-proj.md" 2>/dev/null || \
  touch -d "2020-01-01" "$p8e/.bionic/docs/plans/old-proj.md" 2>/dev/null || true
write_global_note "$h8e" "$FM
## SDLC State
current: 3
Step 3: commit xyz green" "newer-global.md" > /dev/null
expect_block_both "newer canonical global plan cannot override the project's own" \
  "$h8e" "$p8e" 'git commit -m "x"' "placeholder"

# 8f — a project with no plan directory of its own, and a plan in the global
# directory: nothing to gate, silently. Until 2026-07-28 this "fell back" to the
# global plan and blocked.
h8f=$(make_home)
p8f=$(mktemp -d); cleanup_dirs+=("$p8f") # no .bionic/docs/plans/ inside
write_global_note "$h8f" "$FM
## SDLC State
current: 5
approved-by: fixture 2026-09-07T00:00Z "approved"
Step 5: TODO" > /dev/null
expect_allow_both "no project plan dir + global plan → no fallback, allow" \
  "$h8f" "$p8f" 'git commit -m "x"'

# 8g — CLAUDE_PROJECT_DIR unset: the project resolves from the hook input's cwd
# (the sandbox HOME here), and that project's OWN docs root is what is searched.
h8g=$(make_home)
write_plan "$h8g" "$FM
## SDLC State
current: 5
approved-by: fixture 2026-09-07T00:00Z "approved"
Step 5: TODO" > /dev/null
expect_block "CLAUDE_PROJECT_DIR unset: gates on the cwd project's own plan" \
  "$h8g" 'git commit -m "x"' "placeholder"

# 8h — docs/superpowers/plans/ is out too. Same vestige: the root docs/ tree was
# deleted 2026-07-16 and nothing writes canonical plans there. Until 2026-07-28
# a plan in it gated every commit in the project.
h8h=$(make_home); p8h=$(mktemp -d); cleanup_dirs+=("$p8h")
mkdir -p "$p8h/docs/superpowers/plans"
printf '%s\n## SDLC State\ncurrent: 5\napproved-by: fixture 2026-09-07T00:00Z approved\nStep 5: TODO\n' "$FM" > "$p8h/docs/superpowers/plans/active.md"
touch "$p8h/docs/superpowers/plans/active.md"
expect_allow_both "docs/superpowers/plans/ plan does NOT gate the commit" \
  "$h8h" "$p8h" 'git commit -m "x"'

# 8i — the complement of 8d, so "ignore the global directory" cannot be
# satisfied by a hook that blocks everything: a correctly-placed project plan
# with good evidence still allows, whatever the global directory holds.
h8i=$(make_home); p8i=$(make_project)
write_project_plan "$p8i" "$FM
## SDLC State
current: 3
Step 3: commit abc123 tests green" > /dev/null
write_global_note "$h8i" "$FM
## SDLC State
current: 5
approved-by: fixture 2026-09-07T00:00Z "approved"
Step 5: TODO" "newer-global.md" > /dev/null
expect_allow_both "good project plan allows regardless of the global directory" \
  "$h8i" "$p8i" 'git commit -m "x"'

# ============================================================
# Section 17: Verification Matrix gate
# ============================================================
#
# The Verify gate uses a pre-registered Verification Matrix
# stored in a top-level `## Verification Matrix` section of the plan. The
# Step-5 block keeps the tests floor (cmd/pass/total/output) and gains a
# required `auditor:` pointer; the matrix carries a per-session
# `stack-health:` line, a tier table (one row per AC), and one indented
# per-AC evidence block per non-waived row. Each row declares a tier
# (T0..T4); the hook demands that tier's evidence keys (keys_for_tier) —
# non-empty, placeholder-banned, and (on live tiers T3/T4) not self-written
# `n/a`. A `waiver:` entry exempts a row. At `current > 5` every non-waived
# row's auditor cell must read CONFIRMED. The matrix validates at current: 5
# (Step-5 validator) and as a prefix check for current: 6..9.

finish
