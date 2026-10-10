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
write_plan "$h3b" "${FM%---}walk: exempt
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
  readback: 40/40 asserted" > /dev/null
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

section "Section 17: Verification Matrix gate"





# --- matrix fixtures -------------------------------------------------------


# discharged T3 row with NO matching AC evidence block (AC-1 block absent).
matrix_no_block="## Verification Matrix

stack-health: n/a: no long-running serve

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1 | T3 | discharged | see AC-1 | CONFIRMED |
| AC-2 | T1 | discharged | see AC-2 | CONFIRMED |

AC-2:
  fails-when: the planted defect this eval must go red on
  evidence: record/generic-evidence.md
  tier-run: bash test.sh
  readback: 332/332 asserted"

# AC-1 evidence is a placeholder token.
matrix_placeholder="## Verification Matrix

stack-health: n/a: no long-running serve

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1 | T3 | discharged | see AC-1 | CONFIRMED |

AC-1:
  fails-when: the planted defect this eval must go red on
  evidence: TBD"

# AC-1 (T3) evidence is a self-written n/a with no waiver.
matrix_live_na="## Verification Matrix

stack-health: n/a: no long-running serve

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1 | T3 | discharged | see AC-1 | CONFIRMED |

AC-1:
  fails-when: the planted defect this eval must go red on
  evidence: n/a: not reachable quickly"

# Complete matrix but AC-1 auditor verdict is REFUTED.
matrix_refuted="## Verification Matrix

stack-health: process restarts 0 → 0 across walk; no crash/OOM state change

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1 | T3 | discharged | see AC-1 | REFUTED |
| AC-2 | T1 | discharged | see AC-2 | CONFIRMED |
| AC-3 | T3 | waived | waiver: dana 2026-07-16 env stale | waived |

AC-1:
  fails-when: the planted defect this eval must go red on
  evidence: record/generic-evidence.md
  tier-run: https://app.example/panel — opened the panel
  fresh: origin A rebuilt token-9f3a; origin B cdn purged
  cold-client: fresh incognito profile, no SW cache
  contact: clicked open — panel closed → open
  readback: panel.visible === true via page eval
AC-2:
  fails-when: the planted defect this eval must go red on
  evidence: record/generic-evidence.md
  tier-run: bash test.sh — unit suite
  readback: 332/332 asserted"

# Complete matrix; the waived row's auditor cell is empty (legal).
matrix_waived_empty="## Verification Matrix

stack-health: process restarts 0 → 0 across walk; no crash/OOM state change

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1 | T3 | discharged | see AC-1 | CONFIRMED |
| AC-2 | T1 | discharged | see AC-2 | CONFIRMED |
| AC-3 | T3 | waived | waiver: dana 2026-07-16 env stale |  |

AC-1:
  fails-when: the planted defect this eval must go red on
  evidence: record/generic-evidence.md
  tier-run: https://app.example/panel — opened the panel
  fresh: origin A rebuilt token-9f3a; origin B cdn purged
  cold-client: fresh incognito profile, no SW cache
  contact: clicked open — panel closed → open
  readback: panel.visible === true via page eval
AC-2:
  fails-when: the planted defect this eval must go red on
  evidence: record/generic-evidence.md
  tier-run: bash test.sh — unit suite
  readback: 332/332 asserted"

# stack-health line absent.
matrix_no_stackhealth="## Verification Matrix

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1 | T1 | discharged | see AC-1 | CONFIRMED |

AC-1:
  fails-when: the planted defect this eval must go red on
  evidence: record/generic-evidence.md
  tier-run: bash test.sh
  readback: 40/40 asserted"

# stack-health via the n/a escape.
matrix_stackhealth_na="## Verification Matrix

stack-health: n/a: no long-running serve

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1 | T1 | discharged | see AC-1 | CONFIRMED |

AC-1:
  fails-when: the planted defect this eval must go red on
  evidence: record/generic-evidence.md
  tier-run: bash test.sh
  readback: 40/40 asserted"

# T0/T1/T2-only matrix — no T3 fields, no browser artifacts anywhere.
matrix_lower_tiers="## Verification Matrix

stack-health: n/a: no long-running serve

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1 | T1 | discharged | see AC-1 | CONFIRMED |
| AC-2 | T2 | discharged | see AC-2 | CONFIRMED |
| AC-3 | T0 | discharged | see AC-3 | CONFIRMED |

AC-1:
  fails-when: the planted defect this eval must go red on
  evidence: record/generic-evidence.md
  tier-run: bash test.sh — unit
  readback: 40/40 asserted
AC-2:
  fails-when: the planted defect this eval must go red on
  evidence: record/generic-evidence.md
  tier-run: playwright hermetic run
  readback: rendered rows === 5
  fixture-fidelity: derived from captured prod payload 2026-07-10
AC-3:
  fails-when: the planted defect this eval must go red on
  evidence: record/generic-evidence.md
  tier-run: pnpm build && tsc
  readback: 0 type errors"

# false-green entry with no paired rewritten entry.
matrix_false_green_unpaired="## Verification Matrix

stack-health: n/a: no long-running serve

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1 | T1 | discharged | see AC-1 | CONFIRMED |

AC-1:
  fails-when: the planted defect this eval must go red on
  evidence: record/generic-evidence.md
  tier-run: bash test.sh
  readback: 40/40 asserted

false-green: hermetic-x — green over broken branch"

# false-green entry WITH a paired rewritten entry.
matrix_false_green_paired="## Verification Matrix

stack-health: n/a: no long-running serve

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1 | T1 | discharged | see AC-1 | CONFIRMED |

AC-1:
  fails-when: the planted defect this eval must go red on
  evidence: record/generic-evidence.md
  tier-run: bash test.sh
  readback: 40/40 asserted

false-green: hermetic-x — green over broken branch
rewritten: fixed in commit abc123, test now RED-first"

# A malformed row: a stray literal | shears an extra cell.
matrix_malformed="## Verification Matrix

stack-health: n/a: no long-running serve

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1 | T3 | discharged | see | AC-1 | CONFIRMED |

AC-1:
  fails-when: the planted defect this eval must go red on
  evidence: record/generic-evidence.md
  tier-run: x
  fresh: x
  cold-client: x
  contact: x
  readback: x"

# --- cases -----------------------------------------------------------------

# 17a — complete matrix at current: 5 → allow.
h17a=$(make_home)
write_plan "$h17a" "$(plan 5 "$step5_base" "$matrix_complete")" > /dev/null
expect_allow "17a complete matrix (T3 + T1 + waived T3) at current 5 → allow" \
  "$h17a" 'git commit -m "x"'

# 17b — discharged row with NO AC evidence block → block, names the AC.
h17b=$(make_home)
write_plan "$h17b" "$(plan 5 "$step5_base" "$matrix_no_block")" > /dev/null
expect_block "17b discharged T3 row with no AC block → block (names AC-1)" \
  "$h17b" 'git commit -m "x"' "AC-1"

# 17c — placeholder token in an AC evidence field → block.
h17c=$(make_home)
write_plan "$h17c" "$(plan 5 "$step5_base" "$matrix_placeholder")" > /dev/null
expect_block "17c evidence: TBD in AC block → block (placeholder ban)" \
  "$h17c" 'git commit -m "x"' "placeholder"

# 17c-substr — a matrix AC field VALUE that merely CONTAINS a placeholder
# token as a substring is legal; only a whole-value match blocks. evidence:
# 'record/... — status pending → done ...' (the note contains 'pending') → allow.
matrix_substr_ok="## Verification Matrix

stack-health: n/a: no long-running serve

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1 | T1 | discharged | see AC-1 | CONFIRMED |

AC-1:
  fails-when: the planted defect this eval must go red on
  evidence: record/generic-evidence.md — status pending → done, 40/40 asserted"
h17c2=$(make_home)
write_plan "$h17c2" "$(plan 5 "$step5_base" "$matrix_substr_ok")" > /dev/null
expect_allow "17c matrix evidence note containing 'pending' substring → allow (whole-value equality)" \
  "$h17c2" 'git commit -m "x"'

# 17d — T3 row with self-written n/a on a field, no waiver → block, points
# at the Waiver Protocol.
h17d=$(make_home)
write_plan "$h17d" "$(plan 5 "$step5_base" "$matrix_live_na")" > /dev/null
expect_block "17d T3 evidence: n/a, no waiver → block (Waiver Protocol)" \
  "$h17d" 'git commit -m "x"' "Waiver Protocol"

# 17d-case — the live-tier n/a ban must be case-insensitive: 'N/A' and
# 'N/a: <reason>' are the same self-written downgrade as lowercase 'n/a'
# (review-gate finding: a single capital letter must not defeat the ban).
# The variants are written as full literal matrices rather than derived from
# matrix_live_na via ${var/pat/rep}: a slash in the evidence value forces
# an escaped slash in the pattern, and bash 3.2 leaves that backslash in the
# replacement (producing 'evidence: N\/A'), so the variant is never built.
matrix_live_na_upper="## Verification Matrix

stack-health: n/a: no long-running serve

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1 | T3 | discharged | see AC-1 | CONFIRMED |

AC-1:
  fails-when: the planted defect this eval must go red on
  evidence: N/A"
h17d2=$(make_home)
write_plan "$h17d2" "$(plan 5 "$step5_base" "$matrix_live_na_upper")" > /dev/null
expect_block "17d T3 evidence: N/A (uppercase), no waiver → block" \
  "$h17d2" 'git commit -m "x"' "Waiver Protocol"

matrix_live_na_mixed="## Verification Matrix

stack-health: n/a: no long-running serve

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1 | T3 | discharged | see AC-1 | CONFIRMED |

AC-1:
  fails-when: the planted defect this eval must go red on
  evidence: N/a: not reachable quickly"
h17d3=$(make_home)
write_plan "$h17d3" "$(plan 5 "$step5_base" "$matrix_live_na_mixed")" > /dev/null
expect_block "17d T3 evidence: N/a: <reason> (mixed case), no waiver → block" \
  "$h17d3" 'git commit -m "x"' "Waiver Protocol"

# 17e (a T3 row carrying only the suite-credit shape is blocked for the missing fresh/cold-client/contact
# keys) is gone with those keys (wave-31 T6; REQ-5): a T3 row owes the one pointer, and §KEYS KX-1 pins the
# block that carries it alone. Tier-Discharge Rule's suite-credit ban is doctrine for the auditor, not a key.

# 17f — current: 6, one row auditor REFUTED → block.
h17f1=$(make_home)
write_plan "$h17f1" "$(plan 6 "$step6_body" "$matrix_refuted")" > /dev/null
expect_block "17f current 6 with a REFUTED row → block (CONFIRMED required)" \
  "$h17f1" 'git commit -m "x"' "CONFIRMED"

# 17f — current: 6, all non-waived rows CONFIRMED → allow.
h17f2=$(make_home)
write_plan "$h17f2" "$(plan 6 "$step6_body" "$matrix_complete")" > /dev/null
expect_allow "17f current 6 all CONFIRMED (waived row exempt) → allow" \
  "$h17f2" 'git commit -m "x"'

# 17f — current: 6, waived row with an empty auditor cell → allow.
h17f3=$(make_home)
write_plan "$h17f3" "$(plan 6 "$step6_body" "$matrix_waived_empty")" > /dev/null
expect_allow "17f current 6 waived row with empty auditor cell → allow" \
  "$h17f3" 'git commit -m "x"'

# 17g — current: 5 with NO ## Verification Matrix section → block.
h17g=$(make_home)
write_plan "$h17g" "$(matrix_frontmatter true)
## SDLC State
current: 5
approved-by: fixture 2026-09-07T00:00Z "approved"
Step 5:
$step5_base" > /dev/null
expect_block "17g current 5 with no Verification Matrix section → block" \
  "$h17g" 'git commit -m "x"' "Verification Matrix"

# 17h — matrix missing the stack-health line → block.
h17h1=$(make_home)
write_plan "$h17h1" "$(plan 5 "$step5_base" "$matrix_no_stackhealth")" > /dev/null
expect_block "17h matrix missing stack-health → block" \
  "$h17h1" 'git commit -m "x"' "stack-health"

# 17h — stack-health via the n/a escape → allow.
h17h2=$(make_home)
write_plan "$h17h2" "$(plan 5 "$step5_base" "$matrix_stackhealth_na")" > /dev/null
expect_allow "17h stack-health: n/a with reason → allow" \
  "$h17h2" 'git commit -m "x"'

# 17i — T0/T1/T2-only matrix, no T3 fields, no browser artifacts → allow.
h17i=$(make_home)
write_plan "$h17i" "$(plan 5 "$step5_base" "$matrix_lower_tiers")" > /dev/null
expect_allow "17i lower-tier-only matrix (T0/T1/T2) → allow" \
  "$h17i" 'git commit -m "x"'

# 17j — Step-5 block missing the auditor pointer → block.
h17j1=$(make_home)
write_plan "$h17j1" "$(plan 5 "  cmd: bash test.sh
  pass: 332
  total: 332
  head: ${EG_HEAD}
  output: .bionic/docs/plans/wave-01.plan.md#step-5" "$matrix_complete")" > /dev/null
expect_block "17j Step-5 missing auditor → block" \
  "$h17j1" 'git commit -m "x"' "auditor"

# 17j — Step-5 block missing the tests floor (cmd) → block (validator reuse).
h17j2=$(make_home)
write_plan "$h17j2" "$(plan 5 "  pass: 332
  total: 332
  output: .bionic/docs/plans/wave-01.plan.md#step-5
  auditor: 3 rows CONFIRMED — report .bionic/tmp/audit.md" "$matrix_complete")" > /dev/null
expect_block "17j Step-5 missing tests floor cmd → block" \
  "$h17j2" 'git commit -m "x"' "cmd"

# 17l — false-green entry with NO paired rewritten entry → block.
h17l1=$(make_home)
write_plan "$h17l1" "$(plan 5 "$step5_base" "$matrix_false_green_unpaired")" > /dev/null
expect_block "17l false-green without rewritten → block" \
  "$h17l1" 'git commit -m "x"' "rewritten"

# 17l — false-green entry WITH a paired rewritten entry → allow.
h17l2=$(make_home)
write_plan "$h17l2" "$(plan 5 "$step5_base" "$matrix_false_green_paired")" > /dev/null
expect_allow "17l false-green with paired rewritten → allow" \
  "$h17l2" 'git commit -m "x"'

# 17l — no false-green entry at all (key is optional) → allow.
h17l3=$(make_home)
write_plan "$h17l3" "$(plan 5 "$step5_base" "$matrix_lower_tiers")" > /dev/null
expect_allow "17l no false-green entry (optional key) → allow" \
  "$h17l3" 'git commit -m "x"'

# 17m — a malformed table row (stray literal | shears a cell) → block.
h17m=$(make_home)
write_plan "$h17m" "$(plan 5 "$step5_base" "$matrix_malformed")" > /dev/null
expect_block "17m malformed row (extra literal |) → block" \
  "$h17m" 'git commit -m "x"' "malformed"

# --- mid-discharge commits at the Verify gate ------------------------
#
# At current: 5 a row still being discharged (status pending/blocked) is
# exempt from its per-tier evidence keys, and the Step-5 `auditor:` pointer
# is required only once every row is discharged or waived — the full
# contract bites on the 5→6 advance (the 6..9 prefix check), mirroring the
# CONFIRMED rule. The status cell becomes load-bearing, so it gains an enum
# check (pending|blocked|discharged|waived). Rationale: without this, a
# corrective commit made mid-walk has no honest home — the observed
# workaround was editing `current:` back to 4, which silently disables the
# tests floor and misstates the step.

# Step-5 block with the tests floor but NO auditor pointer — the shape of a
# mid-walk corrective commit.
v101_step5_noauditor="  cmd: bash test.sh
  pass: 332
  total: 332
  head: ${EG_HEAD}
  output: .bionic/docs/plans/wave-01.plan.md#step-5"


# Same shape with a blocked row (undrivable interaction, loud).
v101_matrix_blocked="${v101_matrix_pending/| AC-2 | T3 | pending | see AC-2 |  |/| AC-2 | T3 | blocked | montage panel undrivable — see AC-2 |  |}"

# Invalid status token in the status cell.
v101_matrix_bad_status="${v101_matrix_pending/| AC-2 | T3 | pending | see AC-2 |  |/| AC-2 | T3 | done | see AC-2 |  |}"

# Pending row that DOES carry a partial AC block with a live-tier n/a —
# exempt at current: 5 (the whole per-tier check is deferred, caught when
# the row flips to discharged or at the 6..9 prefix check).
v101_matrix_pending_partial="$v101_matrix_pending
AC-2:
  fails-when: the planted defect this eval must go red on
  evidence: record/generic-evidence.md
  contact: n/a: staging origin down"

# 17n — pending row, no AC block, current: 5 → allow (mid-walk commit home).
h17n1=$(make_home)
write_plan "$h17n1" "$(plan 5 "$step5_base" "$v101_matrix_pending")" > /dev/null
expect_allow "17n pending row without AC block at current 5 → allow" \
  "$h17n1" 'git commit -m "x"'

# 17n — pending row AND no auditor pointer → allow (the auditor is the
# Step-5 exit gate; it cannot have run while rows are pending).
h17n2=$(make_home)
write_plan "$h17n2" "$(plan 5 "$v101_step5_noauditor" "$v101_matrix_pending")" > /dev/null
expect_allow "17n pending row + no auditor pointer at current 5 → allow" \
  "$h17n2" 'git commit -m "x"'

# 17n — blocked row, no auditor pointer → allow (same relaxation).
h17n3=$(make_home)
write_plan "$h17n3" "$(plan 5 "$v101_step5_noauditor" "$v101_matrix_blocked")" > /dev/null
expect_allow "17n blocked row + no auditor pointer at current 5 → allow" \
  "$h17n3" 'git commit -m "x"'

# 17n — pending row with a partial block carrying a live-tier n/a → allow
# at current 5 (deferred, not licensed: it blocks at discharge/advance).
h17n4=$(make_home)
write_plan "$h17n4" "$(plan 5 "$step5_base" "$v101_matrix_pending_partial")" > /dev/null
expect_allow "17n pending row with partial block (contact: n/a) at current 5 → allow" \
  "$h17n4" 'git commit -m "x"'

# 17o — fully discharged matrix + missing auditor pointer → still block
# (17j1 pins the same shape; this pins it against the mid-discharge relaxation).
h17o1=$(make_home)
write_plan "$h17o1" "$(plan 5 "$v101_step5_noauditor" "$matrix_complete")" > /dev/null
expect_block "17o fully discharged matrix + no auditor pointer → block" \
  "$h17o1" 'git commit -m "x"' "auditor"

# 17p — invalid status token → block, names the row and the enum.
h17p1=$(make_home)
write_plan "$h17p1" "$(plan 5 "$step5_base" "$v101_matrix_bad_status")" > /dev/null
expect_block "17p invalid status 'done' at current 5 → block (enum)" \
  "$h17p1" 'git commit -m "x"' "invalid status"

h17p2=$(make_home)
write_plan "$h17p2" "$(plan 6 "$step6_body" "$v101_matrix_bad_status")" > /dev/null
expect_block "17p invalid status 'done' at current 6 → block (enum)" \
  "$h17p2" 'git commit -m "x"' "invalid status"

# 17q — the relaxation is 5-only: a pending row at current: 6 blocks (its
# per-tier keys are demanded by the prefix check).
h17q=$(make_home)
write_plan "$h17q" "$(plan 6 "$step6_body" "$v101_matrix_pending")" > /dev/null
expect_block "17q pending row at current 6 → block (relaxation is 5-only)" \
  "$h17q" 'git commit -m "x"' "AC-2"

# --- 17r: `task: 9` rows — evidence only Step 9 can produce --------------
#
# A criterion whose only evidence is a Step-9 lifecycle artifact (the close-out
# report, continuation.md, the ADR the close-out writes) cannot be discharged
# while the plan sits at Steps 5..8: the artifact it would cite does not exist
# yet. Such a row declares `task: 9` in its AC block — parsed like
# `provenance:`, never a sixth table cell (the 7-field row pin would refuse
# every row) — and is then exempt from TWO separate arms while current < 9:
# the per-tier evidence keys, and the CONFIRMED/auditor wall that bites at
# current > 5. At current: 9 the artifact exists and the row is ordinary.
# The tag is T0-only: every other tier names evidence that exists before Step
# 9, so `task: 9` there is a mis-tag and blocks, naming the tier.

# T0 pending row whose AC block is the tag, beside a fully discharged T3 row
# so the rest of the matrix is valid (matrix_complete's shape, which 17f2
# pins as an allow at current: 6).
v9_matrix="## Verification Matrix

stack-health: process restarts 0 → 0 across walk; no crash/OOM state change

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1 | T3 | discharged | see AC-1 | CONFIRMED |
| AC-2 | T0 | pending | see AC-2 |  |

AC-1:
  fails-when: the planted defect this eval must go red on
  evidence: record/generic-evidence.md
  tier-run: https://app.example/panel — opened the panel
  fresh: origin A rebuilt token-9f3a; origin B cdn purged
  cold-client: fresh incognito profile, no SW cache
  contact: clicked open — panel closed → open
  readback: panel.visible === true via page eval
AC-2:
  fails-when: the planted defect this eval must go red on
  evidence: record/generic-evidence.md
  provenance: spec §Close-out obligations
  task: 9"

# The same matrix with the tag replaced by an ordinary line — the control that
# keeps every allow below non-vacuous: untagged, this row blocks at current 6.
v9_matrix_untagged="${v9_matrix/  task: 9/  note: written at close-out}"

# The tag on a tier that has evidence before Step 9 — a mis-tag.
v9_matrix_t1="${v9_matrix/| AC-2 | T0 | pending | see AC-2 |  |/| AC-2 | T1 | pending | see AC-2 |  |}"
v9_matrix_t4="${v9_matrix/| AC-2 | T0 | pending | see AC-2 |  |/| AC-2 | T4 | pending | see AC-2 |  |}"

# The tagged row once Step 9 has run: discharged, T0 keys present, CONFIRMED.
v9_matrix_discharged="${v9_matrix/| AC-2 | T0 | pending | see AC-2 |  |/| AC-2 | T0 | discharged | see AC-2 | CONFIRMED |}"
v9_matrix_discharged="${v9_matrix_discharged/  task: 9/  task: 9
  tier-run: read .bionic/docs/record/wave-01/close-out.md
  readback: close-out names all 9 steps and the continuation}"


# 17r — the exemption holds at every post-Verify step before 9 (AC-6).
h17r6=$(make_home)
write_plan "$h17r6" "$(plan 6 "$step6_body" "$v9_matrix")" > /dev/null
expect_allow "17r T0 pending row with task: 9 at current 6 → allow" \
  "$h17r6" 'git commit -m "x"'

h17r7=$(make_home)
write_plan "$h17r7" "$(plan 7 "$v9_step7_body" "$v9_matrix")" > /dev/null
expect_allow "17r T0 pending row with task: 9 at current 7 → allow" \
  "$h17r7" 'git commit -m "x"'

h17r8=$(make_home)
write_plan "$h17r8" "$(plan 8 "$v9_step8_body" "$v9_matrix")" > /dev/null
expect_allow "17r T0 pending row with task: 9 at current 8 → allow" \
  "$h17r8" 'git commit -m "x"'

# 17r — control: the SAME row without the tag blocks at current 6, so the
# three allows above are the tag's doing and not the fixture's.
h17r_ctl=$(make_home)
write_plan "$h17r_ctl" "$(plan 6 "$step6_body" "$v9_matrix_untagged")" > /dev/null
expect_block "17r untagged T0 pending row at current 6 → block (control)" \
  "$h17r_ctl" 'git commit -m "x"' "AC-2"

# 17r — at current: 9 the artifact exists, so the row is ordinary and its
# pending state blocks (AC-7).
h17r9=$(make_home)
write_plan "$h17r9" "$(plan 9 "$v9_step9_body" "$v9_matrix")" > /dev/null
expect_block "17r task: 9 row still pending at current 9 → block" \
  "$h17r9" 'git commit -m "x"' "AC-2"

# 17r — and discharging it the ordinary way at current: 9 passes, so the block
# above is the row's state and not the tag becoming poison.
h17r9d=$(make_home)
write_plan "$h17r9d" "$(plan 9 "$v9_step9_body" "$v9_matrix_discharged")" > /dev/null
expect_allow "17r task: 9 row discharged + CONFIRMED at current 9 → allow" \
  "$h17r9d" 'git commit -m "x"'

# 17r — the tag on T1..T4 is a mis-tag: block, naming the tier (AC-8).
h17rt1=$(make_home)
write_plan "$h17rt1" "$(plan 6 "$step6_body" "$v9_matrix_t1")" > /dev/null
# Substring is the tag, not the tier: today's missing-key refusal for this row
# ALSO contains "T1", so a tier-only assertion would pass for the wrong reason.
# The current-5 case below is where "names the tier" discriminates.
expect_block "17r task: 9 on a T1 row at current 6 → block naming the tier" \
  "$h17rt1" 'git commit -m "x"' "task: 9"

h17rt4=$(make_home)
write_plan "$h17rt4" "$(plan 6 "$step6_body" "$v9_matrix_t4")" > /dev/null
expect_block "17r task: 9 on a T4 row at current 6 → block naming the tier" \
  "$h17rt4" 'git commit -m "x"' "task: 9"

# 17r — the mis-tag is a shape error, so it fires at the Verify gate too,
# where a pending row is otherwise exempt from everything.
h17rt5=$(make_home)
write_plan "$h17rt5" "$(plan 5 "$step5_base" "$v9_matrix_t1")" > /dev/null
expect_block "17r task: 9 on a T1 row at current 5 → block naming the tier" \
  "$h17rt5" 'git commit -m "x"' "T1"
# ============================================================
# Section 18: matrix parser — section scoping + fenced-code skip
# ============================================================
#
# The matrix validator reads every parse (stack-health, false-green,
# tier-table rows, per-AC blocks) from matrix_section() — the body of the
# top-level `## Verification Matrix` section. Two properties this section
# pins:
#   (1) Row grammar applies ONLY inside that section — a leading-pipe line
#       in another section is never read as a table row.
#   (2) Inside that section, lines within ``` fenced code blocks are
#       skipped — so a jq/shell pipeline written in leading-pipe
#       continuation style does not masquerade as a malformed table row.
# Regression origin: epic-06's matrix section embeds fenced bash/jq blocks;
# a leading-pipe jq continuation line ('| select(.name == "chromium")') was
# parsed as a matrix row and blocked the commit with a bogus malformed-row
# error.

section "Section 18: matrix section scoping + fenced-code skip"

# A fenced bash block whose jq pipeline uses leading-pipe continuation lines
# — the exact shape that tripped the validator live. Single-quoted so the
# triple backticks and inner quotes stay literal (no command substitution).
v10_fence_block='```bash
playwright projects --json | jq -r '"'"'.browsers[]
       | select(.name == "chromium")
       | "\(.name)"'"'"'
```'

# (a) Valid, fully discharged matrix with a fenced pipeline appended inside
# the section (matrix is the last section, so the fence sits at EOF within
# it). RED before the fix: the '| select(...)' lines parse as malformed rows.
matrix_fence_after="$matrix_complete

$v10_fence_block"

h18a=$(make_home)
write_plan "$h18a" "$(plan 5 "$step5_base" "$matrix_fence_after")" > /dev/null
expect_allow "18a fenced jq (leading-pipe) inside matrix section at current 5 → allow" \
  "$h18a" 'git commit -m "x"'

# (b) A leading-pipe line OUTSIDE the matrix section (a later ## section),
# not fenced → allow. Pins that row grammar is scoped to the matrix section.
h18b=$(make_home)
write_plan "$h18b" "$(matrix_frontmatter true)
## SDLC State
current: 5
approved-by: fixture 2026-09-07T00:00Z "approved"
Step 5:
$step5_base

$matrix_complete

## Notes
| this stray pipe line lives outside the matrix section
| and must never be read as a table row" > /dev/null
expect_allow "18b leading-pipe line outside the matrix section → allow" \
  "$h18b" 'git commit -m "x"'

# (c) A fenced pipeline (skipped) AND a genuinely malformed table row (a
# stray literal | shears a cell) → still block. Pins that fence-skip does
# not suppress real malformed rows.
matrix_fence_and_malformed="## Verification Matrix

stack-health: n/a: no long-running serve

$v10_fence_block

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1 | T3 | discharged | see | AC-1 | CONFIRMED |

AC-1:
  fails-when: the planted defect this eval must go red on
  evidence: record/generic-evidence.md
  tier-run: x
  fresh: x
  cold-client: x
  contact: x
  readback: x"

h18c=$(make_home)
write_plan "$h18c" "$(plan 5 "$step5_base" "$matrix_fence_and_malformed")" > /dev/null
expect_block "18c fenced pipeline + genuinely malformed row → block (malformed)" \
  "$h18c" 'git commit -m "x"' "malformed"

# (d) A fenced pipeline placed between stack-health and the table (mid-
# section), containing leading-pipe lines → allow. Pins that fence-skip works
# anywhere in the section, not just at the tail.
matrix_fence_before_table="## Verification Matrix

stack-health: n/a: no long-running serve

$v10_fence_block

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1 | T1 | discharged | see AC-1 | CONFIRMED |

AC-1:
  fails-when: the planted defect this eval must go red on
  evidence: record/generic-evidence.md
  tier-run: bash test.sh
  readback: 40/40 asserted"

h18d=$(make_home)
write_plan "$h18d" "$(plan 5 "$step5_base" "$matrix_fence_before_table")" > /dev/null
expect_allow "18d fenced pipeline before the table (mid-section) → allow" \
  "$h18d" 'git commit -m "x"'

# ============================================================
# Section 15: CRLF and CR-only line endings
# ============================================================
#
# CRLF (\r\n) previously defeated the hook's exact-match awk frontmatter
# parser (`$0=="---"` never matches "---\r"), so the version marker and every
# frontmatter-keyed check were lost. The earlier fix `tr -d '\r'` then broke
# CR-only (classic-Mac) plans by deleting every line break, collapsing the file
# to ONE line so `/^## SDLC State/` never matched and the hook exited 0 as "not
# a canonical-sdlc plan" — every commit passed ungated. The parser now
# TRANSLATES \r to real newlines, so all three line-ending styles parse alike.
#
# Each style is proved BOTH ways: a valid plan must be allowed (no false block
# from a mangled parse) and a plan with a broken matrix row must be blocked on
# THAT row (proving the frontmatter and body actually parsed, rather than the
# file being waved through or rejected wholesale).

section "Section 15: CRLF and CR-only line endings"

# Inserts a literal CR before each newline. Bash-3.2-safe ANSI-C quoting embeds
# a real CR byte in the sed script itself (BSD sed's replacement text does not
# interpret the two-character "\r" as an escape).
to_crlf() {
  printf '%s' "$1" | sed $'s/$/\r/'
}

# Replaces every newline with a carriage return, so the content carries NO \n
# at all. (write_plan then appends one trailing \n; the internal line breaks
# stay pure \r — the faithful CR-only shape.)
to_cr() {
  printf '%s' "$1" | tr '\n' '\r'
}

# 15a — CRLF plan, complete Step 5 + complete matrix → allow.
h15a=$(make_home)
write_plan "$h15a" "$(to_crlf "$(plan 5 "$step5_base" "$matrix_complete")")" > /dev/null
expect_allow "CRLF plan, complete Step 5 + matrix → allow" \
  "$h15a" 'git commit -m "x"'

# 15b — CRLF plan whose matrix has a discharged row with no AC block → block on
# that row. A mangled parse would either allow, or block on the version.
h15b=$(make_home)
write_plan "$h15b" "$(to_crlf "$(plan 5 "$step5_base" "$matrix_no_block")")" > /dev/null
expect_block "CRLF plan, broken matrix row → block on AC-1 (frontmatter parsed)" \
  "$h15b" 'git commit -m "x"' "AC-1"

# 15c — CR-only plan, complete Step 5 + complete matrix → allow.
h15c=$(make_home)
write_plan "$h15c" "$(to_cr "$(plan 5 "$step5_base" "$matrix_complete")")" > /dev/null
expect_allow "CR-only plan, complete Step 5 + matrix → allow" \
  "$h15c" 'git commit -m "x"'

# 15d — CR-only plan with a broken matrix row → block on that row. Before the
# fix the whole file collapsed to one line and the commit passed ungated.
h15d=$(make_home)
write_plan "$h15d" "$(to_cr "$(plan 5 "$step5_base" "$matrix_no_block")")" > /dev/null
expect_block "CR-only plan, broken matrix row → block on AC-1 (body parsed)" \
  "$h15d" 'git commit -m "x"' "AC-1"

# ============================================================
# Section 19: triple, task ledger, merge-target
# ============================================================
#
# Governance keys off the intent × rigor × scale triple. Two shapes follow
# from `scale:`:
#   (1) Wave/epic-scale plans carry the numbered-step shape — pointer steps
#       1/2/3/4, the Verify gate at 5, document at 7, integrate=8, ship=9.
#   (2) Task-scale plans (scale: task) address a ledger TASK, not a numbered
#       step: `current: T<n>` with evidence on `- T<n>:` lines.
#
# A wave plan naming an `epic:` also gets a LOG-ONLY merge-target check at the
# integrate step. `current: T<n>` on a non-task plan still blocks — the
# T-format is scale: task only.

section "Section 19: triple, task ledger, merge-target"

# Log-only assertion helpers: exit 0 with a finding on stderr (the standard
# expect_allow requires EMPTY stderr, which a finding violates).
expect_finding() {
  local label="$1" home_dir="$2" command="$3" substr="$4"
  run_hook "$home_dir" "$command"
  if [ "$HOOK_EXIT" -eq 0 ] && grep -q "$substr" <<<"$HOOK_STDERR"; then
    ok "$label"
  else
    no "$label" "expected allow exit 0 + stderr '$substr'; got exit=$HOOK_EXIT stderr='$HOOK_STDERR'"
  fi
}

expect_finding_both() {
  local label="$1" home_dir="$2" project_dir="$3" command="$4" substr="$5"
  run_hook_with_project "$home_dir" "$project_dir" "$command"
  if [ "$HOOK_EXIT" -eq 0 ] && grep -q "$substr" <<<"$HOOK_STDERR"; then
    ok "$label"
  else
    no "$label" "expected allow exit 0 + stderr '$substr'; got exit=$HOOK_EXIT stderr='$HOOK_STDERR'"
  fi
}




# A wave plan naming an epic and carrying an integration-branch line, for
# the merge-target check. $1 current, $2 step body, $3 matrix, $4 epic,
# $5 integration-branch.
wave_epic_plan() {
  printf '%s\n## SDLC State\nintegration-branch: %s\ncurrent: %s\napproved-by: fixture 2026-09-07T00:00Z "approved"\nStep %s:\n%s\n\n%s\n' \
    "$(frontmatter wave none false "$4")" "$5" "$1" "$1" "$2" "$3"
}



# A complete integrate (Step 8) block that passes the shape check, so the
# merge-target log-only check can be exercised in isolation.
integrate_body="  merge: merged wave into epic/07-x
  worktree-removed: n/a
  cleanup: n/a"

# --- (2) wave/epic-scale plans: the numbered-step shape ------------------

# 19a — wave plan at Step 5 with an incomplete matrix (discharged T3 row
# with no AC block) → block.
h19a=$(make_home)
write_plan "$h19a" "$(wave_plan 5 "$step5_base" "$matrix_no_block")" > /dev/null
expect_block "19a wave plan Step 5 incomplete matrix → block" \
  "$h19a" 'git commit -m "x"' "AC-1"

# 19b — wave plan at Step 5 with a complete matrix + auditor pointer →
# allow (pointer/matrix evidence in place).
h19b=$(make_home)
write_plan "$h19b" "$(wave_plan 5 "$step5_base" "$matrix_complete")" > /dev/null
expect_allow "19b wave plan Step 5 complete matrix → allow" \
  "$h19b" 'git commit -m "x"'

# 19c — integrate is Step 8. A plan at current: 8 with a
# complete matrix but an integrate block missing merge/worktree-removed →
# block on the shape check (integrate fires at 8).
h19c=$(make_home)
write_plan "$h19c" "$(wave_plan 8 "  note: integrating now" "$matrix_complete")" > /dev/null
expect_block "19c integrate Step 8 missing merge fields → block" \
  "$h19c" 'git commit -m "x"' "merge"

# 19c2 — Step 4 is a pointer step: a pointer body allows.
h19c2=$(make_home)
write_plan "$h19c2" "$(frontmatter wave)
## SDLC State
current: 4
approved-by: fixture 2026-09-07T00:00Z "approved"
Step 4: .bionic/docs/plans/wave.plan.md#step-4" > /dev/null
expect_allow "19c2 wave plan Step 4 pointer → allow" \
  "$h19c2" 'git commit -m "x"'

# --- (2) the retired task-scale ledger is refused, not judged (wave-31 T24; REQ-1, D2) ----
#
# 19d-19j pinned the task-scale ledger the gate judged under `current: T<n>`: a valid ledger
# allowed; a missing table, a bad status or a done row short of its line logged; the addressed
# row's missing or placeholder line refused; the same under CRLF and CR-only line endings. That
# shape is deleted: `current:` is a step number at every scale. 19d is what the shape meets now
# and 19d2 its control, the same one-table plan at a numeric `current:`, admitted. 19j and
# 19j-cr keep the line-ending half: the value is named with its `\r` stripped.
h19d=$(make_home)
write_plan "$h19d" "$(eg_pf_plan T2 task single false "- T2: bash extract-helper.sh 4 cases green" "$(eg_pf_row T1 — landed)" "$(eg_pf_row T2 — active)")" > /dev/null
expect_block "19d task plan at current: T2 → block, naming the value as not numeric" \
  "$h19d" 'git commit -m "x"' "current: T2 is not numeric"
h19d2=$(make_home)
write_plan "$h19d2" "$(eg_pf_plan 4 task single false "- T2: bash extract-helper.sh 4 cases green" "$(eg_pf_row T1 — landed)" "$(eg_pf_row T2 — active)")" > /dev/null
expect_allow "19d2 control: the same one-table plan at current: 4 → allow" \
  "$h19d2" 'git commit -m "x"'
h19j=$(make_home)
write_plan "$h19j" "$(to_crlf "$(eg_pf_plan T2 task single false "" "$(eg_pf_row T2 — active)")")" > /dev/null
expect_block "19j CRLF task plan at current: T2 → the same refusal, the value read without its CR" \
  "$h19j" 'git commit -m "x"' "current: T2 is not numeric"
h19jcr=$(make_home)
write_plan "$h19jcr" "$(to_cr "$(eg_pf_plan T2 task single false "" "$(eg_pf_row T2 — active)")")" > /dev/null
expect_block "19j-cr CR-only task plan at current: T2 → the same refusal" \
  "$h19jcr" 'git commit -m "x"' "current: T2 is not numeric"

# --- (4) epic merge-target consistency (log-only) ------------------------

# Build a project with an epic plan declaring integration-branch: epic/07-x.
make_epic_project() {
  local branch="$1"
  local proj
  proj=$(make_project)
  mkdir -p "$proj/.bionic/docs/plans/epic-fix"
  printf -- '---\ncanonical_sdlc_version: 14\nintent: build\nrigor: double\nscale: epic\n---\n## SDLC State\nintegration-branch: %s\ncurrent: 1\n' \
    "$branch" > "$proj/.bionic/docs/plans/epic-fix/epic.plan.md"
  touch -t 202001010000 "$proj/.bionic/docs/plans/epic-fix/epic.plan.md" 2>/dev/null || \
    touch -d "2020-01-01" "$proj/.bionic/docs/plans/epic-fix/epic.plan.md" 2>/dev/null || true
  echo "$proj"
}

# 19k — plan integration-branch (main) mismatches the epic's (epic/07-x) at
# the integrate step → exit 0 + merge-target finding.
h19k=$(make_home); p19k=$(make_epic_project "epic/07-x")
write_project_plan "$p19k" \
  "$(wave_epic_plan 8 "$integrate_body" "$matrix_complete" epic-fix main)" \
  "wave-newest.plan.md" > /dev/null
expect_finding_both "19k merge-target mismatch → exit 0 + merge-target finding" \
  "$h19k" "$p19k" 'git commit -m "x"' "merge-target"

# 19l — matching integration-branch → no finding (silent allow).
h19l=$(make_home); p19l=$(make_epic_project "epic/07-x")
write_project_plan "$p19l" \
  "$(wave_epic_plan 8 "$integrate_body" "$matrix_complete" epic-fix "epic/07-x")" \
  "wave-newest.plan.md" > /dev/null
expect_allow_both "19l merge-target match → allow, no finding" \
  "$h19l" "$p19l" 'git commit -m "x"'

# --- (5) current: is a step number at every scale --------------------------

# `current: T2` on a WAVE-scale plan is not a valid step pointer, and since wave-31 T24 (D2) it is
# none on a task-scale plan either (19d): the numeric check refuses it, naming the value.
h19m=$(make_home)
write_plan "$h19m" "$(frontmatter wave)
## SDLC State
current: T2
Step 5: whatever" > /dev/null
expect_block "19m wave-scale plan with current: T2 → block (not numeric)" \
  "$h19m" 'git commit -m "x"' "current: T2 is not numeric"

# --- fence-aware SDLC-State extraction (blocking-grade correctness) -------

# A fenced ``` example containing a `## SDLC State` heading + `current: T2`
# line — the D12 task-scale schema as it appears in a plan's PROSE. Single-
# quoted so the triple backticks stay literal (no command substitution).
v11_fenced_sdlcstate_shadow='```
## SDLC State
current: T2

- T1: <evidence>
- T2: <evidence>
```'

# 19o — the SDLC-State extraction must be fence-aware, like matrix_section.
# A plan whose body documents the task-scale schema in a fenced block
# BEFORE the real section must validate against the REAL `## SDLC State`
# (current: 5 + complete matrix), not the shadowed `current: T2`. Before the
# fix the fence-blind awk captured the fenced `current: T2` first →
# CURRENT=T2 → non-numeric → false block. Same defect class the matrix parser
# fixed (fence-blind row parsing). This fix removes false blocks, adds none.
h19o=$(make_home)
write_plan "$h19o" "$(matrix_frontmatter true)

Doc note — the task-scale ledger schema (D12) looks like:

$v11_fenced_sdlcstate_shadow

## SDLC State
current: 5
approved-by: fixture 2026-09-07T00:00Z "approved"
Step 5:
$step5_base

$matrix_complete" > /dev/null
expect_allow "19o fenced ## SDLC State shadow before real section → validates real section (allow)" \
  "$h19o" 'git commit -m "x"'

# 19p — the `## Tasks` extraction is fence-aware: a fenced ``` example carrying a bogus-status
# row before the REAL `## Tasks` table is not read. Moved to the one table (wave-31 T24; D2): the
# reader that judges a row's status is the dispatch-ledger arm, so the fixture is a double
# multi_agent wave plan. 19p2 is its control: the same row in the real table is refused.
v19p_bad='| T9 | 4 | build | example row | implementor | — | 30m | REQ-x | x.sh | doing |'
v19p_fence='```
## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | status |
|---|---|---|---|---|---|---|---|---|---|
'"$v19p_bad"'
```'
h19p=$(make_home)
write_plan "$h19p" "$(d7_wave_plan "Example ledger:

$v19p_fence

$tasks_one_done" "- T1: bash tests/run.sh 12/12 green")" > /dev/null
expect_allow "19p fenced ## Tasks example before the real table → not read (fence-aware)" \
  "$h19p" 'git commit -m "x"'
h19p2=$(make_home)
write_plan "$h19p2" "$(d7_wave_plan "$tasks_one_done
$v19p_bad" "- T1: bash tests/run.sh 12/12 green")" > /dev/null
expect_block "19p2 control: the same 'doing' row in the real table → block, naming it" \
  "$h19p2" 'git commit -m "x"' "T9: status doing is not one of"

# 19q — a doc file whose ONLY `## SDLC State` occurrence is inside a fenced
# ``` example (no real section) must pass through as NON-CANONICAL (exit 0),
# not be parsed and false-blocked on the now-empty extraction. The presence
# check must be fence-aware too, matching the extraction: a fenced heading is
# documentation, not state. Decision recorded in the plan's ## Assumptions.
v11_fenced_only_sdlcstate="# Some skill doc

Here is how a canonical-sdlc plan records its state:

$v11_fenced_sdlcstate_shadow

That is the schema — this file itself is not a plan and carries no real
SDLC-State section of its own."
h19q=$(make_home)
write_plan "$h19q" "$v11_fenced_only_sdlcstate" > /dev/null

# --- fence-aware epic-plan read in merge-target (review fix) --------------

# An epic project whose epic.plan.md documents a `## SDLC State` example in a
# fenced ``` block (bogus integration-branch: fenced-decoy) BEFORE its real
# section (integration-branch: $1). Fence-blind, the cross-file read picks the
# decoy (head -1) and mis-reports the merge target.
make_epic_project_fenced() {
  local branch="$1" proj
  proj=$(make_project)
  mkdir -p "$proj/.bionic/docs/plans/epic-fix"
  cat > "$proj/.bionic/docs/plans/epic-fix/epic.plan.md" <<EOF
---
canonical_sdlc_version: 14
intent: build
rigor: double
scale: epic
---
# Epic plan

The epic's state block looks like this:

\`\`\`
## SDLC State
integration-branch: fenced-decoy
current: 1
\`\`\`

## SDLC State
integration-branch: ${branch}
current: 1
EOF
  touch -t 202001010000 "$proj/.bionic/docs/plans/epic-fix/epic.plan.md" 2>/dev/null || \
    touch -d "2020-01-01" "$proj/.bionic/docs/plans/epic-fix/epic.plan.md" 2>/dev/null || true
  echo "$proj"
}

# 19r — the merge-target epic-plan read must be fence-aware, like every other
# SDLC-State extraction this wave. The wave plan's integration-branch matches
# the epic's REAL value (epic/07-x); the fenced decoy (fenced-decoy) must be
# ignored → silent (no finding). Before the fix the fence-blind awk read the
# decoy first (head -1) → mismatch → spurious merge-target finding. Log-only
# blast radius, but the exact defect class this wave eliminated everywhere else.
h19r=$(make_home); p19r=$(make_epic_project_fenced "epic/07-x")
write_project_plan "$p19r" \
  "$(wave_epic_plan 8 "$integrate_body" "$matrix_complete" epic-fix "epic/07-x")" \
  "wave-newest.plan.md" > /dev/null
expect_allow_both "19r fenced ## SDLC State in epic plan → merge-target reads real section (silent)" \
  "$h19r" "$p19r" 'git commit -m "x"'

# ============================================================
# Section 20: intent-scoped Step-5 evidence keys (R7, log-only)
# ============================================================
#
# Plans declare an `intent:` in frontmatter. Two intents carry a
# conditional Step-5 evidence key set, checked LOG-ONLY (D14) at the Verify
# gate — never blocks:
#   - refactor: requires `behavior-preservation:` (non-empty); `compat-matrix:`
#     and `revert-plan:` are optional but must not be present-and-empty.
#   - tune: requires `baseline:`, `target:`, `re-measure:` (all non-empty).
# Any other intent (e.g. build) gets no check at all — this is intent-scoped,
# not a universal Step-5 key like bundle-fresh/drive-check/stack-health. A
# — no audit write, no finding.

section "Section 20: intent-scoped Step-5 evidence keys (R7, log-only)"

# Counts occurrences of $substr in stderr — for asserting an exact finding
# count (e.g. the tune intent's three missing keys).
expect_finding_count() {
  local label="$1" home_dir="$2" command="$3" substr="$4" expected="$5"
  run_hook "$home_dir" "$command"
  local count
  count=$(grep -c "$substr" <<<"$HOOK_STDERR") || count=0
  if [ "$HOOK_EXIT" -eq 0 ] && [ "$count" -eq "$expected" ]; then
    ok "$label"
  else
    no "$label" "expected allow exit 0 + ${expected}x '$substr'; got exit=$HOOK_EXIT count=$count stderr='$HOOK_STDERR'"
  fi
}


# Frontmatter with a caller-chosen intent (Section 19's frontmatter
# hardcodes intent: build). $1 intent, $2 scale (default wave).
r7_frontmatter() {
  local intent="$1" scale="${2:-wave}"
  printf -- '---\n'
  printf -- 'governing-skill: canonical-sdlc\n'
  printf -- 'canonical_sdlc_version: 14\n'
  printf -- 'intent: %s\n' "$intent"
  printf -- 'rigor: double\n'
  printf -- 'scale: %s\n' "$scale"
  printf -- 'deploy_target: none\n'
  printf -- 'use_worktree: false\n'
  printf -- 'has_ui: false\n'
  printf -- 'walk: exempt\n'  # see matrix_frontmatter — the walk arm is fail-closed
  printf -- '---\n'
}

# A wave plan with the given intent, at the given current/Step-5 body/
# matrix. $1 intent, $2 current, $3 Step-block body, $4 matrix.
r7_wave_plan() {
  printf '%s\n## SDLC State\ncurrent: %s\napproved-by: fixture 2026-09-07T00:00Z "approved"\nStep %s:\n%s\n\n%s\n' \
    "$(r7_frontmatter "$1")" "$2" "$2" "$3" "$4"
}

# Refactor Step-5 body with behavior-preservation already satisfied — the
# base for the compat-matrix/revert-plan sub-cases (20c), which isolate
# that one axis by keeping behavior-preservation clean.
r7_refactor_body_ok="$step5_base
  behavior-preservation: suites 211/211 pre @abc, 211/211 post @def"

# --- 20a/20b: refactor — behavior-preservation required ------------------

# 20a — refactor plan, valid tests floor + matrix, NO behavior-preservation
# key → exit 0 + refactor-evidence finding on stderr AND in the audit file.
h20a=$(make_home)
write_plan "$h20a" "$(r7_wave_plan refactor 5 "$step5_base" "$matrix_complete")" > /dev/null
expect_finding "20a refactor plan missing behavior-preservation → finding" \
  "$h20a" 'git commit -m "x"' "canonical-sdlc \[refactor-evidence\]"
h20a2=$(make_home)
write_plan "$h20a2" "$(r7_wave_plan refactor 5 "$step5_base" "$matrix_complete")" > /dev/null
expect_audit_line "20a2 refactor plan missing behavior-preservation → audit file line" \
  "$h20a2" 'git commit -m "x"' "evidence-gate refactor-evidence:"

# 20b — same plan + behavior-preservation present → exit 0, NO finding.
h20b=$(make_home)
write_plan "$h20b" "$(r7_wave_plan refactor 5 "$r7_refactor_body_ok" "$matrix_complete")" > /dev/null
expect_allow "20b refactor plan with behavior-preservation → allow, no finding" \
  "$h20b" 'git commit -m "x"'

# --- 20c: refactor — compat-matrix/revert-plan optional-but-not-empty ----

# 20c1 — compat-matrix present but empty → refactor-evidence finding.
h20c1=$(make_home)
write_plan "$h20c1" "$(r7_wave_plan refactor 5 "$r7_refactor_body_ok
  compat-matrix:" "$matrix_complete")" > /dev/null
expect_finding "20c1 refactor compat-matrix present but empty → finding" \
  "$h20c1" 'git commit -m "x"' "compat-matrix"

# 20c2 — compat-matrix: n/a: not a migration (non-empty) → clean.
h20c2=$(make_home)
write_plan "$h20c2" "$(r7_wave_plan refactor 5 "$r7_refactor_body_ok
  compat-matrix: n/a: not a migration" "$matrix_complete")" > /dev/null
expect_allow "20c2 refactor compat-matrix non-empty n/a → allow, no finding" \
  "$h20c2" 'git commit -m "x"'

# 20c3 — compat-matrix/revert-plan entirely absent → clean (they are
# optional; only presence-and-empty is a finding).
h20c3=$(make_home)
write_plan "$h20c3" "$(r7_wave_plan refactor 5 "$r7_refactor_body_ok" "$matrix_complete")" > /dev/null
expect_allow "20c3 refactor compat-matrix/revert-plan absent → allow, no finding" \
  "$h20c3" 'git commit -m "x"'

# --- 20d: tune — baseline/target/re-measure all required ------------------

# 20d1 — tune plan missing all three keys → exactly THREE tune-evidence
# findings (assert count, not just "at least one").
h20d1=$(make_home)
write_plan "$h20d1" "$(r7_wave_plan tune 5 "$step5_base" "$matrix_complete")" > /dev/null
expect_finding_count "20d1 tune plan missing baseline/target/re-measure → 3 findings" \
  "$h20d1" 'git commit -m "x"' "tune-evidence" 3

# 20d2 — tune plan with all three non-empty → clean.
r7_tune_body_ok="$step5_base
  baseline: p95 340ms @abc
  target: p95 <= 200ms
  re-measure: p95 190ms @def"
h20d2=$(make_home)
write_plan "$h20d2" "$(r7_wave_plan tune 5 "$r7_tune_body_ok" "$matrix_complete")" > /dev/null
expect_allow "20d2 tune plan with baseline/target/re-measure → allow, no finding" \
  "$h20d2" 'git commit -m "x"'

# --- 20e: build — intent-scoped, not universal ----------------------------

# 20e — build intent with none of the refactor/tune keys → NO finding (these
# checks are intent-scoped; build never triggers them).
h20e=$(make_home)
write_plan "$h20e" "$(r7_wave_plan build 5 "$step5_base" "$matrix_complete")" > /dev/null
expect_allow "20e build plan with no intent-scoped keys → allow, no finding" \
  "$h20e" 'git commit -m "x"'

# --- 20g/20h: R7 keys are truly log-only (critic Issue 1) ------------------
#
# The universal placeholder ban (the whole-Step-block scan a few hundred
# lines up) used to scan these six intent-scoped keys too, so a
# placeholder R7 value BLOCKED the commit — contradicting the ratified
# log-only contract. R7 keys are exempted from that ban
# (version-gated: v≤10 plans still block on a stray placeholder R7-named
# line — see 20i); validate_intent_evidence itself now treats a placeholder
# value the same as missing/empty, so the finding still fires.

# 20g — refactor plan, behavior-preservation: TODO (placeholder value, not
# missing) → exit 0 + refactor-evidence finding + audit line (was BLOCKED).
h20g=$(make_home)
write_plan "$h20g" "$(r7_wave_plan refactor 5 "$step5_base
  behavior-preservation: TODO" "$matrix_complete")" > /dev/null
expect_finding "20g refactor behavior-preservation: TODO → allow + refactor-evidence finding" \
  "$h20g" 'git commit -m "x"' "canonical-sdlc \[refactor-evidence\]"
h20g2=$(make_home)
write_plan "$h20g2" "$(r7_wave_plan refactor 5 "$step5_base
  behavior-preservation: TODO" "$matrix_complete")" > /dev/null
expect_audit_line "20g2 refactor behavior-preservation: TODO → audit file line" \
  "$h20g2" 'git commit -m "x"' "evidence-gate refactor-evidence:"

# 20h — tune plan, baseline: tbd (placeholder), target/re-measure valid →
# exit 0 + exactly ONE tune-evidence finding (not three — the other two
# keys are present and non-placeholder).
h20h=$(make_home)
write_plan "$h20h" "$(r7_wave_plan tune 5 "$step5_base
  baseline: tbd
  target: p95 <= 200ms
  re-measure: p95 190ms @def" "$matrix_complete")" > /dev/null
expect_finding_count "20h tune baseline: tbd (rest valid) → exactly 1 tune-evidence finding" \
  "$h20h" 'git commit -m "x"' "tune-evidence" 1

# ============================================================
# Section 21: audit dir follows the plan's project (strategy alignment)
# ============================================================
#
# log_finding's audit_dir now walks up from $PLAN's own directory to the
# nearest ancestor containing .bionic/, matching the governing-skill hook's
# find_project_root_from_path strategy — findings live with the project that
# owns the artifact. PROJECT_DIR is the fallback only.
#
# NOTE (pinning, not RED — see plan ## Assumptions): plan discovery is
# rooted at PROJECT_DIR (PLAN_DIRS is built from $PROJECT_DIR's docs root
# alone), so in every case constructible through the hook's real
# discovery paths, walk-up resolves to the SAME directory PROJECT_DIR already
# names. Both cases below pass identically before and after the refactor;
# they pin the new code path (and its fallback) rather than catch a bug.

section "Section 21: audit dir follows the plan's project (strategy alignment)"

# Like run_hook_with_project, but pins CLAUDE_PROJECT_DIR to $2 (the fixture
# project that owns the plan) while the JSON cwd field AND the actual
# invoking shell's cwd are $3 (an unrelated sibling dir) — proving
# log_finding follows the plan's own project via walk-up, never whatever
# directory happened to invoke the hook.
run_hook_project_elsewhere_cwd() {
  local home_dir="$1" project_dir="$2" elsewhere_dir="$3" command="$4"
  local input
  input=$(jq -n --arg c "$command" --arg cwd "$elsewhere_dir" --arg s "$EG_SID" \
            '{session_id: $s, tool_input: {command: $c}, cwd: $cwd}')
  local tmp_err
  tmp_err=$(mktemp)
  eg_autobind "$project_dir"
  if (cd "$elsewhere_dir" && HOME="$home_dir" CLAUDE_PROJECT_DIR="$project_dir" CLAUDE_CODE_SESSION_ID="$EG_SID" bash "$HOOK" <<< "$input" >/dev/null 2>"$tmp_err"); then
    HOOK_EXIT=0
  else
    HOOK_EXIT=$?
  fi
  split_stderr "$tmp_err"
  HOOK_VSTDERR=""
  if [ "$HOOK_EXIT" -ne 0 ]; then
    eg_knob "$( (cd "$elsewhere_dir" && HOME="$home_dir" CLAUDE_PROJECT_DIR="$project_dir" \
      CLAUDE_CODE_SESSION_ID="$EG_SID" BIONIC_WALL_VERBOSE=1 bash "$HOOK" <<< "$input") 2>&1 >/dev/null || true)"
  fi
  rm -f "$tmp_err"
}

# 21a — fixture project owns the plan; the JSON cwd field and the actual
# process cwd both point at an unrelated sibling temp dir. Asserts the audit
# line lands in the audit file KEYED ON the fixture project (incident 0001:
# under the sandbox HOME, slugged by the fixture root — never inside the
# project tree), and that NO .bionic/ gets created under the sibling (no cwd
# leak). The "nothing under the fixture tree" arm is paired with the presence
# arm on purpose: alone it would pass if the hook wrote nothing at all.
h21a=$(make_home)
fixture21a=$(make_project)
elsewhere21a=$(mktemp -d); cleanup_dirs+=("$elsewhere21a")
write_project_plan "$fixture21a" "$(r7_wave_plan tune 5 "$step5_base" "$matrix_complete")" > /dev/null
run_hook_project_elsewhere_cwd "$h21a" "$fixture21a" "$elsewhere21a" 'git commit -m "x"'
fixture_audit=$(audit_file_for "$h21a" "$fixture21a")
in_tree21a=$(find "$fixture21a" "$elsewhere21a" -name 'sdlc-audit.md' 2>/dev/null)
if [ "$HOOK_EXIT" -eq 0 ] && [ -f "$fixture_audit" ] && grep -q "tune-evidence" "$fixture_audit" \
  && [ ! -d "$elsewhere21a/.bionic" ] && [ -z "$in_tree21a" ]; then
  ok "21a audit line follows the plan's fixture project, not the invoking cwd"
else
  no "21a" "expected fixture-keyed audit line under HOME + no audit file in any project tree; exit=$HOOK_EXIT fixture_audit_exists=$([ -f "$fixture_audit" ] && echo yes || echo no) elsewhere_bionic=$([ -d "$elsewhere21a/.bionic" ] && echo yes || echo no) in_tree='$in_tree21a'"
fi

# 21b — fail-open fallback: the sandbox-HOME fixture (Section 19/20's usual
# one) is not a git repository, so resolve_project_root cannot compute a root
# from the plan and falls back to $PROJECT_DIR (== $h21b here, via the cwd
# field) — hook still exits 0 and still writes the audit line, unblocked.
h21b=$(make_home)
write_plan "$h21b" "$(r7_wave_plan tune 5 "$step5_base" "$matrix_complete")" > /dev/null
expect_audit_line "21b fail-open: no .bionic ancestor above the plan → PROJECT_DIR fallback used" \
  "$h21b" 'git commit -m "x"' "tune-evidence"

# ============================================================
# Section 21c: AC-10 — the audit root is COMPUTED, never discovered
# ============================================================
#
# audit_root now delegates to resolve_project_root, which computes the root
# from `git rev-parse --path-format=absolute --git-common-dir` instead of
# walking the plan's ancestors for an existing `.bionic/`. Consequences:
# a project whose `.bionic/` has never existed still resolves, and every
# linked worktree of one repo answers with the parent repo — one repo, one
# audit file, instead of one per worktree.
#
# Fixture fidelity: real `git init` repos and a real `git worktree add` on
# disk. The behaviour under test is git's own path-format handling, which a
# stubbed `git` cannot reproduce.

echo ""
# 21c-e2e — the CALL SITE, driven through the hook's real stdin contract, from
# INSIDE a linked worktree. The plan lives where the governing-skill hook
# demands it live — the MAIN repo's docs root — and the worktree carries a
# newer decoy plan in its own .bionic/docs/plans/. Three arms, asserted
# together:
#   - the decoy is NOT selected (it would block on a placeholder), so
#     PROJECT_DIR/DOCS_ROOT resolved to the main repo, not the worktree;
#   - the finding lands in the audit file keyed on the main repo;
#   - no audit file keyed on the worktree exists.
# The absence arm alone would pass if the hook had written nothing at all.
#
# Step-6 finding C2/S1 rewrote this case's fixture. It used to put the real
# plan INSIDE the worktree's own .bionic/ — a placement the governing-skill
# hook blocks, so the two hooks disagreed about the same repo and no artifact
# location satisfied both. This shape is the reachable one.
ac10_tmp=$(cd "$(mktemp -d)" && pwd -P); cleanup_dirs+=("$ac10_tmp")
ac10_main="$ac10_tmp/main"
mkdir -p "$ac10_main/.bionic/docs/plans" "$ac10_main/deep/sub/dir"
write_generic_evidence "$ac10_main"
git -C "$ac10_main" init -q .
git -C "$ac10_main" commit -q --allow-empty -m init
git -C "$ac10_main" worktree add -q "$ac10_tmp/wt" -b ac10-wt
ac10_wt="$ac10_tmp/wt"
# ENGAGED, on the MAIN repo: every linked worktree of one repo resolves to one root, so
# that is the one root the engagement marker can live under and the one this gate reads.
engage "$ac10_main"
mkdir -p "$ac10_wt/.bionic/docs/plans"
h21c=$(make_home)
# This repository has a head of its own, so the Step-5 block names it (wave-26 T4, D5).
printf '%s\n' "$(r7_wave_plan tune 5 "${step5_base/$EG_HEAD/$(git -C "$ac10_main" rev-parse HEAD)}" "$matrix_complete")" \
  > "$ac10_main/.bionic/docs/plans/active.md"
touch "$ac10_main/.bionic/docs/plans/active.md"
printf -- '---\ngoverning-skill: canonical-sdlc\ncanonical_sdlc_version: 14\nintent: build\nrigor: single\nscale: wave\n---\n## SDLC State\ncurrent: 5\napproved-by: fixture 2026-09-07T00:00Z approved\nStep 5: TODO\n' \
  > "$ac10_wt/.bionic/docs/plans/decoy.md"
touch "$ac10_wt/.bionic/docs/plans/decoy.md"
run_hook_with_project "$h21c" "$ac10_wt" 'git commit -m "x"'
ac10_main_audit=$(audit_file_for "$h21c" "$ac10_main")
ac10_wt_audit=$(audit_file_for "$h21c" "$ac10_wt")
if [ "$HOOK_EXIT" -eq 0 ] && [ -f "$ac10_main_audit" ] && grep -q "tune-evidence" "$ac10_main_audit" \
   && [ ! -f "$ac10_wt_audit" ]; then
  ok "21c-e2e commit from a worktree → main repo's plan, one audit file keyed on the main repo"
else
  no "21c-e2e commit from a worktree → main repo's plan and audit file" \
    "exit=$HOOK_EXIT main_audit=$([ -f "$ac10_main_audit" ] && echo yes || echo no) wt_audit=$([ -f "$ac10_wt_audit" ] && echo yes || echo no) stderr='$HOOK_STDERR'"
fi

# ============================================================
# Section 22: the rigor-keyed ledger lanes are gone with the task-scale shape (wave-31 T24; D2)
# ============================================================
#
# Sections 22, 22c Part A, 22d and 22f pinned the evidence gate's task-scale ledger lanes, run
# under the `current: T<n>` arm: the addressed unit's floor (its row, its `- T<n>:` line, no
# placeholder), the proof-shape lane at double, the per-row rigor cell and its floor, and the
# double plan's promotion of the other rows' findings. One ledger shape (REQ-1, D2) deleted that
# arm and `validate_task_ledger` with it: `current:` is a step number at every scale, and the one
# `## Tasks` table carries no rigor cell. Each deleted section leaves one row: its own fixture,
# written in the one table at `current: T<n>`, meets the gate's refusal naming the value.

section "Section 22: the rigor-keyed ledger lanes are gone — current: T<n> is refused as not numeric"

h22T=$(make_home)
write_plan "$h22T" "$(eg_pf_plan T2 task double false "- T2: implemented and verified manually" "$(eg_pf_row T1 — landed)" "$(eg_pf_row T2 — active)")" > /dev/null
expect_block "22-T 22b1's plan (double, prose evidence on the addressed row) at current: T2 is refused as not numeric" \
  "$h22T" 'git commit -m "x"' "current: T2 is not numeric"

# --- 22c: the D7 dispatched-task ledger (task 4/3) ------------------------
#
# validate_dispatch_ledger demands a `## Tasks` dispatched-task ledger section on rigor:double +
# multi_agent:true plans at scale wave or task (absent → block; empty/none-dispatched → allow;
# rows validate at SINGLE-FLOOR shape only — enum + evidence-line presence, NO per-row
# auditor/critic, plan Assumption A2). Every other plan is a guard no-op. Part A pinned the
# retired task table's double plan-level strictness (the other rows' ledger-shape findings
# promoted to blocks); that arm went with the table (wave-31 T24; REQ-1, D2). 22c-T is what its
# fixture meets now, and 22c-T2/T3 show the one table at task scale judged by Part B's arm.

section "Section 22c: double strictness + D7 dispatch-ledger presence"

# ---- Part A: the retired task table's strictness is gone ---------------------

# 22c-T — 22c1's plan: double, task scale, a second row in a status no enum defines, at
# current: T1 → refused as not numeric, before any row is read.
h22cT=$(make_home)
write_plan "$h22cT" "$(eg_pf_plan T1 task double false "- T1: bash suite 12/12 green" "$(eg_pf_row T1 — active)" "$(eg_pf_row T2 — wip)")" > /dev/null
expect_block "22c-T 22c1's plan at current: T1 is refused as not numeric" \
  "$h22cT" 'git commit -m "x"' "current: T1 is not numeric"

# 22c-T2 — the same rows at a numeric current, double multi_agent, task scale: the `wip` row is
# refused by the dispatch-ledger arm in the one enum's words, as at wave scale (A-T24-6).
h22cT2=$(make_home)
write_plan "$h22cT2" "$(eg_pf_plan 4 task double true "- T1: bash suite 12/12 green" "$(eg_pf_row T1 — landed)" "$(eg_pf_row T2 — wip)")" > /dev/null
expect_block "22c-T2 REQ-1 at scale: task, double multi_agent, a 'wip' row is refused by the dispatch-ledger arm, naming the one enum" \
  "$h22cT2" 'git commit -m "x"' "T2: status wip is not one of pending active landed dropped"

# 22c-T3 — control: the same plan with T2 pending is admitted.
h22cT3=$(make_home)
write_plan "$h22cT3" "$(eg_pf_plan 4 task double true "- T1: bash suite 12/12 green" "$(eg_pf_row T1 — landed)" "$(eg_pf_row T2 — pending)")" > /dev/null
expect_allow "22c-T3 control: the same task-scale plan with T2 pending → allow" \
  "$h22cT3" 'git commit -m "x"'

# ---- Part B: wave-scale D7 dispatched-task ledger presence ---------------



# 22c5 — double multi_agent wave with NO ## Tasks section → block (D7 presence).
h22c5=$(make_home)
write_plan "$h22c5" "$(d7_wave_plan "" "")" > /dev/null
expect_block "22c5 double multi_agent wave with no ## Tasks → block (D7 presence)" \
  "$h22c5" 'git commit -m "x"' "dispatched-task ledger"

# 22c6 — WITH a ## Tasks section, header-only + a `none dispatched` line, zero
# T-rows → allow (section present suffices; the parser needs no row). The header
# is the widened ten-column schema REQ-1e made the one Tasks shape; a header short
# of it is a `missing column` violation now, pinned by 22e2 below.
tasks_none="## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | status |
|---|---|---|---|---|---|---|---|---|---|

none dispatched — the orchestrator appends one row per dispatched task-shaped unit."
h22c6=$(make_home)
write_plan "$h22c6" "$(d7_wave_plan "$tasks_none" "")" > /dev/null
expect_allow "22c6 double multi_agent wave with none-dispatched ## Tasks → allow" \
  "$h22c6" 'git commit -m "x"'

# 22c7 — ## Tasks with one dispatched row (done) AND a matching `- T1:` evidence
# line in ## SDLC State → allow. NOTE: the line carries NO auditor/critic token
# yet it passes — single-floor shape only at wave scale (pins Assumption A2).
h22c7=$(make_home)
write_plan "$h22c7" "$(d7_wave_plan "$tasks_one_done" "- T1: bash suite 9/9 green")" > /dev/null
expect_allow "22c7 double multi_agent wave dispatched T1 + evidence line → allow (single-floor shape, no auditor/critic)" \
  "$h22c7" 'git commit -m "x"'

# 22c8 — ## Tasks with a dispatched row (done) but NO `- T1:` evidence line
# anywhere in ## SDLC State → block.
h22c8=$(make_home)
write_plan "$h22c8" "$(d7_wave_plan "$tasks_one_done" "")" > /dev/null
expect_block "22c8 double multi_agent wave dispatched T1 with no evidence line → block" \
  "$h22c8" 'git commit -m "x"' "evidence line"

# 22c9 — single wave with NO ## Tasks → allow (the
# guard excludes single plans).
h22c9=$(make_home)
write_plan "$h22c9" "$(d7_wave_plan "" "" single true)" > /dev/null
expect_allow "22c9 single wave with no ## Tasks → allow (guard excludes)" \
  "$h22c9" 'git commit -m "x"'

# 22c10 — double wave with multi_agent: false and NO ## Tasks → allow (the guard
# excludes single-agent plans).
h22c10=$(make_home)
write_plan "$h22c10" "$(d7_wave_plan "" "" double false)" > /dev/null
expect_allow "22c10 double wave with multi_agent:false, no ## Tasks → allow (guard excludes)" \
  "$h22c10" 'git commit -m "x"'

# 22c11 (self-reference pin) — reproduce THIS wave-05 plan's exact ## Tasks shape
# (header + `|---|` separator + blank + a `none dispatched — ...` prose line,
# zero T-rows) on an double multi_agent wave fixture → allow. This is the shape
# the deployed NEW hook must accept when wave-05 itself advances past the pointer
# steps into the dispatcher.
tasks_selfref="## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | status |
|---|---|---|---|---|---|---|---|---|---|

none dispatched — D7 ledger opens empty; the orchestrator appends one row
per dispatched task-shaped unit (work ledgered under Step-4 evidence, not
here, unless dispatched as discrete task-shaped work)."
h22c11=$(make_home)
write_plan "$h22c11" "$(d7_wave_plan "$tasks_selfref" "")" > /dev/null
expect_allow "22c11 self-reference pin — THIS plan's exact ## Tasks shape (zero T-rows) → allow" \
  "$h22c11" 'git commit -m "x"'

# 22c12 (base-faithful presence, correctness F-1) — a `## Tasks` section carrying
# PROSE and NO header row at all → allow. D7's presence rule is a question about the
# SECTION, not about the table: rule 2 of this function's own docblock, and the shape
# its own Fix text advertises ("a header plus a 'none dispatched' line is fine").
# 22c6 and 22c11 both carry a ten-column header AND a `|---|` separator, so neither
# can tell a section-basis presence test from a table-basis one; this fixture can.
tasks_prose_only="## Tasks

none dispatched — no task-shaped unit has been dispatched on this wave yet."
h22c12=$(make_home)
write_plan "$h22c12" "$(d7_wave_plan "$tasks_prose_only" "")" > /dev/null
expect_allow "22c12 double multi_agent wave, ## Tasks prose with NO header row → allow (presence is the section, not the table)" \
  "$h22c12" 'git commit -m "x"'

# 22c13 — a `## Tasks` heading with an EMPTY section (nothing between it and the
# next `##`) → block. The other half of the base rule: empty is not fine, only a
# section with content is. 22c5 pins the ABSENT half.
h22c13=$(make_home)
write_plan "$h22c13" "$(d7_wave_plan "## Tasks" "")" > /dev/null
expect_block "22c13 double multi_agent wave, ## Tasks heading with an empty section → block (D7 presence)" \
  "$h22c13" 'git commit -m "x"' "dispatched-task ledger"

# ---- 22e: the wave's TEN-column ## Tasks table (REQ-1e, AC-1e.3) ----------
#
# THE SELF-REFERENCE PIN THIS WAVE NEEDS. 22c11 pinned the five-column shape
# `| id | intent | rigor | description | status |` the D7 ledger shipped with;
# REQ-1e widens it to `| id | step | kind | task | agent | deps | size | serves
# | Files | status |`, which puts `agent` where the old positional read took
# `status` ($6) and `kind` where it took `rigor` ($4). Measured before the fix
# (record/wave-11-lean-spine/step1-measure-1a-1e.md §4.3): every row of this
# table fails the status enum, on this wave's own plan, at its own next commit.
#
# The table below is wave-11-lean-spine's OWN `## Tasks` section, copied
# verbatim, on an double multi_agent wave fixture at current: 5 — the exact
# triple that arms validate_dispatch_ledger. It carries `landed`, the status the
# widened schema uses and the old enum (pending|active|done|dropped) does not.
IFS= read -r -d '' tasks_ten_column <<'TEN_COLUMN_EOF' || true
## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | status |
|---|---|---|---|---|---|---|---|---|---|
| T1 | 3 | doc | Plan, Tasks and matrix written; Step-3 card approved | orchestrator | — | 30m | all | plan | landed |
| T2 | 4 | build | 1d: `disable-model-invocation: true` on the five command templates; re-render; frontmatter pin | orchestrator | T1 | 15m | REQ-1d | agents-src/templates/commands/*.tmpl, payload/commands/*.md, payload/integrity/rendered.sha256, tests/docs-pins.test.sh | landed |
| T3 | 4 | build | 1c-a: survival renders once to payload/context/survival.md; auditor mandate moved the same way; role templates ≤5 KB with a one-line pointer; §5 writer rules as defaults; PIPESTATUS fixed; six pins re-pointed | senior-implementor | T1 | 60m | REQ-1c | agents-src/blocks/survival.md, agents-src/templates/*.md.tmpl, agents-src/render.sh, agents/*.md, payload/context/survival.md, tests/docs-pins.test.sh, tests/render.test.sh, payload/integrity/rendered.sha256 | landed |
| T4 | 4 | build | 1c-b: SubagentStart hook injects survival for bionic:* agents, self-attributed first line; stdout-equals-file pin | implementor | T3 | 45m | REQ-1c | hooks/execution-recorder.sh, tests/execution-recorder.test.sh | landed |
| T5 | 4 | build | 1b: core + steps/0–9 + dispatch.md from the template; render.sh unit rows; 168 pins re-pointed, 4 structural ones rewritten; prune to caps; session-start pointer line | senior-implementor | T1 | 120m | REQ-1b | agents-src/templates/skills/canonical-sdlc/, agents-src/render.sh, skills/canonical-sdlc/, tests/docs-pins.test.sh, tests/render.test.sh, payload/integrity/rendered.sha256, hooks/session-start.sh | landed |
| T6 | 4 | build | 1a: three prose surfaces re-pointed to record/ paths; evidence-gate fixtures (path-cited ≤40 KB passes; empty evidence value fails) | implementor | T3, T5 | 45m | REQ-1a | agents-src/blocks/critic-template.md, agents-src/templates/senior-implementor.md.tmpl, agents-src/templates/skills/canonical-sdlc/steps/, tests/canonical-sdlc-evidence-gate.test.sh | landed |
| T7 | 4 | build | 1e-a: lib/units.sh (units_rows, units_ready, units_validate) TDD from tests/units.test.sh; domain dictionary entry | senior-implementor | T1 | 60m | REQ-1e | payload/scripts/lib/units.sh, tests/units.test.sh, design/domain-dictionary.md | landed |
| T8 | 4 | build | 1e-b: callers onto units.sh (gate ledger checks + prototype check, tick FILL, governing-skill Step-3 wall); the retired word becomes task everywhere; fixtures migrated; differential vs old parsers on the specimen plan | senior-implementor | T6, T7 | 120m | REQ-1e | hooks/canonical-sdlc-evidence-gate.sh, hooks/session-poker.sh, hooks/canonical-sdlc-governing-skill.sh, hooks/dispatch-preflight.sh, tests/canonical-sdlc-evidence-gate.test.sh, tests/session-poker.test.sh, tests/canonical-sdlc-governing-skill.test.sh, tests/docs-pins.test.sh, agents-src/ | active |
| T9 | 4 | build | 1f-a: remove the seven dead functions; stop-check.sh retained as the observation producer (census DELETE reversed) | implementor | T1 | 30m | REQ-1f | hooks/stop-check.sh, hooks/stop-guard.sh, payload/scripts/lib/, tests/ | landed |
| T10 | 4 | build | 1f-b: lib/context.sh with bionic_context; fifteen hooks call it; no-inline-sequence pin | senior-implementor | T8, T9, T11 | 90m | REQ-1f | payload/scripts/lib/context.sh, hooks/*.sh, tests/cross-gate-agreement.test.sh | pending |
| T11 | 4 | build | 1f-c: loader block ≤95 lines in loader.sh's heredoc and all 21 hooks; §N.1 pin and mutation arm green | senior-implementor | T1 | 60m | REQ-1f | payload/scripts/lib/loader.sh, hooks/*.sh, tests/cross-gate-agreement.test.sh | landed |
| T12 | 4 | build | 1f-d: context-spend suite first (RED); lib/stop.sh four functions; hooks/stop.sh on Stop + SubagentStop with fold; differential vs the four originals; hooks.json ≤12 command objects | senior-implementor | T10 | 150m | REQ-1f | payload/scripts/lib/stop.sh, hooks/stop.sh, hooks/hooks.json, hooks/context-spend.sh, hooks/landing-gate.sh, hooks/patrol-duties-gate.sh, hooks/patrol-revive.sh, tests/stop.test.sh, tests/context-spend.test.sh, tests/ | pending |
| T13 | 5 | verify | Walk: an agent that has not read the ACs drives the candidate by plugin-dir in a throwaway project and narrates; record/wave-11-lean-spine/walk.md | researcher | T2, T4, T5, T6, T8, T12, T22 | 30m | all | record/wave-11-lean-spine/walk.md | pending |
| T14 | 5 | test | Tests floor: bash tests/run.sh in the wave worktree; census commands re-run; evidence/floor.md | test-runner | T2, T4, T5, T6, T8, T12, T22 | 40m | all | record/wave-11-lean-spine/evidence/floor.md | pending |
| T15 | 5 | verify | Discharge the matrix: 22 static pins, 12 hermetic rows, 6 live drives; one evidence file per AC | orchestrator | T13, T14 | 90m | all | record/wave-11-lean-spine/evidence/ | pending |
| T16 | 5 | verify | Auditor on the REQ-1e and REQ-1f rows (double) and the wave verdict | auditor | T15 | 45m | REQ-1e, REQ-1f | record/wave-11-lean-spine/auditor.md | pending |
| T17 | 6 | review | Six-axis self-review, one reviewer per axis in parallel at exec-complex | orchestrator | T16 | 45m | all | record/wave-11-lean-spine/review/ | pending |
| T18 | 6 | review | Critic on T7–T12 (double rows) | critic | T17 | 45m | REQ-1e, REQ-1f | record/wave-11-lean-spine/critic.md | pending |
| T19 | 7 | doc | ADRs 001–004; spec adrs: pointer | orchestrator | T18 | 30m | D1, D3, D4, D5 | adrs/epic-23-bionic-tech-debt/ | pending |
| T20 | 8 | integrate | Wake Note, then attended no-ff merge to main; writer worktrees and the wave worktree removed; tmp ephemera wiped | orchestrator | T19 | 20m | all | none | pending |
| T22 | 4 | build | 1g: fix the doctor/setup agreement on the `motion` row so DS.2a/2c/9/11 pass on this machine; honour the 2026-08-22 ruling | senior-implementor | T1 | 60m | REQ-1g | payload/scripts/lib/deps.sh, payload/scripts/doctor.sh, payload/scripts/setup.sh, tests/cross-gate-agreement.test.sh | landed |
| T21 | 9 | close | Close-out report with dispositions; continuation.md; archive_run; Patrol CronDelete + disarm | orchestrator | T20 | 30m | all | record/wave-11-lean-spine/closeout-report.md | pending |
TEN_COLUMN_EOF
IFS= read -r -d '' ten_column_evidence <<'TEN_COLUMN_EV_EOF' || true
- T1: record/wave-11-lean-spine/briefs/T1-report.md, suites green
- T2: record/wave-11-lean-spine/briefs/T2-report.md, suites green
- T3: record/wave-11-lean-spine/briefs/T3-report.md, suites green
- T4: record/wave-11-lean-spine/briefs/T4-report.md, suites green
- T5: record/wave-11-lean-spine/briefs/T5-report.md, suites green
- T6: record/wave-11-lean-spine/briefs/T6-report.md, suites green
- T7: record/wave-11-lean-spine/briefs/T7-report.md, suites green
- T8: record/wave-11-lean-spine/briefs/T8-report.md, suites green
- T9: record/wave-11-lean-spine/briefs/T9-report.md, suites green
- T10: record/wave-11-lean-spine/briefs/T10-report.md, suites green
- T11: record/wave-11-lean-spine/briefs/T11-report.md, suites green
- T12: record/wave-11-lean-spine/briefs/T12-report.md, suites green
- T13: record/wave-11-lean-spine/briefs/T13-report.md, suites green
- T14: record/wave-11-lean-spine/briefs/T14-report.md, suites green
- T15: record/wave-11-lean-spine/briefs/T15-report.md, suites green
- T16: record/wave-11-lean-spine/briefs/T16-report.md, suites green
- T17: record/wave-11-lean-spine/briefs/T17-report.md, suites green
- T18: record/wave-11-lean-spine/briefs/T18-report.md, suites green
- T19: record/wave-11-lean-spine/briefs/T19-report.md, suites green
- T20: record/wave-11-lean-spine/briefs/T20-report.md, suites green
- T22: record/wave-11-lean-spine/briefs/T22-report.md, suites green
- T21: record/wave-11-lean-spine/briefs/T21-report.md, suites green
TEN_COLUMN_EV_EOF
h22e1=$(make_home)
write_plan "$h22e1" "$(d7_wave_plan "$tasks_ten_column" "$ten_column_evidence")" > /dev/null
expect_allow "22e1 AC-1e.3 — the ten-column ## Tasks table on an double multi_agent wave → allow" \
  "$h22e1" 'git commit -m "x"'

# 22e2 — THE DELEGATION IS LIVE, not decorative: the invariants this check used to
# restate by hand are `units_validate`'s now, and a violation it alone knows about —
# a dep naming no row — refuses, naming the id and the rule.
tasks_dangling_dep="## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | status |
|---|---|---|---|---|---|---|---|---|---|
| T1 | 4 | build | the dispatched unit | implementor | T99 | 30m | REQ-x | a.sh | landed |"
h22e2=$(make_home)
write_plan "$h22e2" "$(d7_wave_plan "$tasks_dangling_dep" "- T1: bash suite 9/9 green")" > /dev/null
expect_block "22e2 a dep naming no row in the ten-column ledger → block (delegated to units_validate)" \
  "$h22e2" 'git commit -m "x"' "T99"

# 22e3 — a header short of the ten columns is a `missing column` violation, which is
# the AC-1e.5 wall's third case reaching the gate from the other side.
tasks_missing_column="## Tasks

| id | kind | task | agent | deps | size | serves | Files | status |
|---|---|---|---|---|---|---|---|---|
| T1 | build | the dispatched unit | implementor | — | 30m | REQ-x | a.sh | landed |"
h22e3=$(make_home)
write_plan "$h22e3" "$(d7_wave_plan "$tasks_missing_column" "- T1: bash suite 9/9 green")" > /dev/null
expect_block "22e3 a ledger header missing the step column → block naming the column" \
  "$h22e3" 'git commit -m "x"' "missing column step"

# 22e4 — the control 22e1 needs on the OTHER variable: the same ten-column table with
# one status nobody defines. An allow above must be earned by the table being valid,
# not by the check having gone inert on a shape it no longer understands.
tasks_bad_status="## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | status |
|---|---|---|---|---|---|---|---|---|---|
| T1 | 4 | build | the dispatched unit | implementor | — | 30m | REQ-x | a.sh | done |"
h22e4=$(make_home)
write_plan "$h22e4" "$(d7_wave_plan "$tasks_bad_status" "- T1: bash suite 9/9 green")" > /dev/null
expect_block "22e4 status 'done' in the widened schema → block (the four are pending active landed dropped)" \
  "$h22e4" 'git commit -m "x"' "status done is not one of"

# 22e5 — A RAW `|` IN A CELL (REQ-8, AC-8.3). The gate and the Step-3 write-time wall
# read the SAME library, so a table whose only fault is an unescaped pipe must be refused
# here with the SAME line the hook prints — one that names the pipe and the repair instead
# of the three violations the shift used to raise against cells that were correct. The row
# below is tests/units.test.sh §9b's own row and the counts are pinned identically: if the
# two ever drift, a writer repairing a plan against the gate's advice would be told
# something the hook does not say.
tasks_raw_pipe="## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | status |
|---|---|---|---|---|---|---|---|---|---|
| T1 | 4 | build | the dispatched unit | implementor | — | 30m | REQ-x | a.sh | landed |
| T2 | 4 | build | do b | a raw | pipe | T1 | S | REQ-x | b.sh | landed |"
h22e5=$(make_home)
write_plan "$h22e5" "$(d7_wave_plan "$tasks_raw_pipe" "- T1: bash suite 9/9 green
- T2: bash suite 9/9 green")" > /dev/null
expect_block "22e5 AC-8.3 a raw pipe in a Tasks cell → block, naming the pipe not the shift" \
  "$h22e5" 'git commit -m "x"' "T2: 12 cells for 11 columns"
expect_block "22e5b …and the same line carries the repair" \
  "$h22e5" 'git commit -m "x"' "escape it as"

# ============================================================
# Sections 22d and 22f: the rigor cell is gone with the task-scale table (wave-31 T24; D2)
# ============================================================
#
# 22d pinned the per-row `rigor` cell's resolution (the cell first, the frontmatter as fallback,
# an off-enum cell INVALID) and 22f its floor (a cell lowering a row below the frontmatter refused
# unless the row's line carried a waiver). The cell was a column of the retired task table; the
# one table carries `kind` in that slot and no rigor column, so there is no cell to resolve or to
# floor. What each section's fixture meets now is the numeric refusal of its `current: T1`.

section "Section 22d: per-row rigor resolution is gone with the rigor cell"

expect_eq "22d-T0 the one table's header carries kind in slot 3" "1" \
  "$(eg_pf_plan 4 task double false "" | /usr/bin/grep -cF '| id | step | kind | task |')"
expect_eq "22d-T0b …and carries no rigor column" "0" \
  "$(eg_pf_plan 4 task double false "" | /usr/bin/grep -cF '| rigor |')"
h22dT=$(make_home)
write_plan "$h22dT" "$(eg_pf_plan T1 task single false "- T1: fixed it manually" "$(eg_pf_row T1 — active)")" > /dev/null
expect_block "22d-T 22d1's plan (single, the addressed row's prose line) at current: T1 is refused as not numeric" \
  "$h22dT" 'git commit -m "x"' "current: T1 is not numeric"

section "Section 22f: the row-rigor floor is gone with the rigor cell"

h22fT=$(make_home)
write_plan "$h22fT" "$(eg_pf_plan T1 task double false "- T1: reproduced and fixed the boundary case, waiver: dana 2026-07-19 genuine bugfix" "$(eg_pf_row T1 — active)")" > /dev/null
expect_block "22f-T 22d2b's plan (double, a waiver on the row's line) at current: T1 is refused as not numeric" \
  "$h22fT" 'git commit -m "x"' "current: T1 is not numeric"

# ============================================================
# Section 23: canonical_sdlc_version — exactly one supported value
# ============================================================
#
# The hook supports canonical_sdlc_version: 14 and nothing else. Every other
# value blocks with exit 2 and a message naming the value found. One
# table-driven case over representative bad values — an older number, a much
# older number, a legacy single digit, a far-future number, an empty value, and
# non-numeric garbage — because there is one behavior here, not one per value.
#
# The version check sits ahead of every shape check, so these fixtures carry a
# valid ## SDLC State: what is under test is the version, not the evidence.

section "Section 23: canonical_sdlc_version — exactly one supported value"

versioned_plan() {  # $1 = the canonical_sdlc_version value to declare
  printf -- '---\n'
  printf -- 'governing-skill: canonical-sdlc\n'
  printf -- 'canonical_sdlc_version: %s\n' "$1"
  printf -- 'intent: build\nrigor: single\nscale: wave\n'
  printf -- '---\n'
  printf -- '## SDLC State\ncurrent: 3\nStep 3: .bionic/docs/plans/wave-01.plan.md\n'
}

for bad_version in 13 12 11 9 2 99 "" banana 12.0 v12; do
  h=$(make_home)
  write_plan "$h" "$(versioned_plan "$bad_version")" > /dev/null
  expect_block "unsupported canonical_sdlc_version '${bad_version:-<empty>}' → block, naming the value found" \
    "$h" 'git commit -m "x"' "canonical_sdlc_version: '${bad_version}'"
done

# A plan with NO canonical_sdlc_version line at all is not a special case: it
# reads as the empty value and blocks the same way.
h23none=$(make_home)
write_plan "$h23none" "---
governing-skill: canonical-sdlc
intent: build
rigor: single
scale: wave
---
## SDLC State
current: 3
Step 3: .bionic/docs/plans/wave-01.plan.md" > /dev/null
expect_block "absent canonical_sdlc_version → block" \
  "$h23none" 'git commit -m "x"' "the only supported version"

# The supported value passes the version gate (proved by reaching — and
# satisfying — the evidence checks beyond it).
h23ok=$(make_home)
write_plan "$h23ok" "$(versioned_plan 14)" > /dev/null
expect_allow "canonical_sdlc_version: 14 → allow" "$h23ok" 'git commit -m "x"'

# ============================================================
# Section 24: AC-13 — the plan-search fail-open
# ============================================================
#
# This hook fails open DIFFERENTLY from the governing-skill hook. It never
# tests `.bionic/` at all: every candidate plan directory is skipped by
# `[ -d "$d" ] || continue`, PLAN comes back empty, and the commit passes
# ungated. Closing the governing-skill hook's fail-open does nothing for this
# one, which is why the two are driven independently here.
#
# The distinction the AC draws, applied to a commit gate:
#   ABSENT     — no plan anywhere. Not a canonical-sdlc run. Never blocks;
#                this is every commit in every project that does not use the
#                lifecycle, and a wall there would be intolerable.
#   MISPLACED  — a plan carrying the run marker exists in the project, but
#                outside every directory the gate searches. The gate is
#                silently disabled and the commit would sail through. Blocks,
#                naming where the plan belongs.
section "Section 24: AC-13 — misplaced plan blocks, absent plan never does"


echo "-- c1: ABSENCE never blocks --"
# A project with no .bionic/ at all and no plan file anywhere. The single most
# common commit in the world; it must pass, silently.
s24_h1=$(make_home)
s24_p1=$(mktemp -d); cleanup_dirs+=("$s24_p1")
mkdir -p "$s24_p1/src"
printf 'echo hi\n' > "$s24_p1/src/main.sh"
run_hook_with_project "$s24_h1" "$s24_p1" 'git commit -m "x"'
if [ "$HOOK_EXIT" -eq 0 ] && [ -z "$HOOK_STDERR" ]; then
  ok "no .bionic/, no plan anywhere → allow, silently"
else
  no "no .bionic/, no plan anywhere → allow, silently" "expected allow; exit=$HOOK_EXIT stderr='$HOOK_STDERR'"
fi

# .bionic/docs/plans/ exists but is empty — a project that has run Step 0 and
# not yet written a plan. Still absence, still no block.
s24_h1b=$(make_home)
s24_p1b=$(make_project)
run_hook_with_project "$s24_h1b" "$s24_p1b" 'git commit -m "x"'
if [ "$HOOK_EXIT" -eq 0 ] && [ -z "$HOOK_STDERR" ]; then
  ok "empty .bionic/docs/plans/ → allow, silently"
else
  no "empty .bionic/docs/plans/ → allow, silently" "expected allow; exit=$HOOK_EXIT stderr='$HOOK_STDERR'"
fi

echo "-- c2: MISPLACEMENT blocks, naming the correct path --"
# The legacy layout, and the shape a moved-or-renamed tree leaves behind: a
# real canonical-sdlc plan the gate cannot see.
s24_h2=$(make_home)
s24_p2=$(mktemp -d); cleanup_dirs+=("$s24_p2")
mkdir -p "$s24_p2/docs/bionic/plans/epic-01-demo"
# ENGAGED, and the misplacement is untouched by it: the marker lives in `.bionic/tmp`,
# the docs root this gate names is `.bionic/docs`, and creating one does not create the
# other. hooks/engage.sh makes the tmp directory in exactly this shape of project.
engage "$s24_p2"
s24_marked_plan > "$s24_p2/docs/bionic/plans/epic-01-demo/wave-01-x.plan.md"
run_hook_with_project "$s24_h2" "$s24_p2" 'git commit -m "x"'
if [ "$HOOK_EXIT" -eq 2 ] \
   && grep -q "misplaced" <<<"$HOOK_VSTDERR" \
   && grep -qF "$s24_p2/.bionic/docs/plans/" <<<"$HOOK_VSTDERR"; then
  ok "misplaced plan → block, naming the correct path"
else
  no "misplaced plan → block, naming the correct path" "expected block naming $s24_p2/.bionic/docs/plans/; exit=$HOOK_EXIT stderr='$HOOK_STDERR'"
fi

# The identical plan in the right place is found and gated normally — proof the
# block above is about WHERE the file is, not about the file.
s24_h3=$(make_home)
s24_p3=$(make_project)
s24_marked_plan > "$s24_p3/.bionic/docs/plans/wave-01-x.plan.md"

echo "-- c3: unmarked files are unaffected --"
# A *.plan.md with no canonical_sdlc_version is not a canonical-sdlc run
# artifact. Plenty of projects have plan-shaped markdown; none of it is this
# hook's business.
s24_h4=$(make_home)
s24_p4=$(mktemp -d); cleanup_dirs+=("$s24_p4")
mkdir -p "$s24_p4/notes"
printf '# Some plan\n\nnot a canonical-sdlc artifact\n' > "$s24_p4/notes/roadmap.plan.md"
run_hook_with_project "$s24_h4" "$s24_p4" 'git commit -m "x"'
if [ "$HOOK_EXIT" -eq 0 ] && [ -z "$HOOK_STDERR" ]; then
  ok "unmarked *.plan.md → allow, silently"
else
  no "unmarked *.plan.md → allow, silently" "expected allow; exit=$HOOK_EXIT stderr='$HOOK_STDERR'"
fi

# A FENCED example of the frontmatter is documentation. Only the leading block
# counts — the recurring trap in this repo is a parser that reads fenced
# examples as real declarations.
s24_h5=$(make_home)
s24_p5=$(mktemp -d); cleanup_dirs+=("$s24_p5")
mkdir -p "$s24_p5/docs"
{ printf '# How to write a plan\n\n```\n---\ncanonical_sdlc_version: 14\n---\n```\n'; } \
  > "$s24_p5/docs/example.plan.md"
run_hook_with_project "$s24_h5" "$s24_p5" 'git commit -m "x"'
if [ "$HOOK_EXIT" -eq 0 ] && [ -z "$HOOK_STDERR" ]; then
  ok "fenced frontmatter example → allow, silently"
else
  no "fenced frontmatter example → allow, silently" "expected allow; exit=$HOOK_EXIT stderr='$HOOK_STDERR'"
fi

echo "-- c4: elsewhere under the docs root is PLACED, not misplaced --"
# <docs-root>/spikes/ and <docs-root>/record/ hold real artifacts carrying this
# frontmatter. The governing-skill hook treats the whole docs root as placed;
# this hook must agree, or the two would disagree about the same file.
s24_h6=$(make_home)
s24_p6=$(make_project)
mkdir -p "$s24_p6/.bionic/docs/spikes"
s24_marked_plan > "$s24_p6/.bionic/docs/spikes/spike-x.plan.md"
run_hook_with_project "$s24_h6" "$s24_p6" 'git commit -m "x"'
if [ "$HOOK_EXIT" -eq 0 ] && [ -z "$HOOK_STDERR" ]; then
  ok "marked plan under <docs-root>/spikes/ → placed, allow"
else
  no "marked plan under <docs-root>/spikes/ → placed, allow" "expected allow; exit=$HOOK_EXIT stderr='$HOOK_STDERR'"
fi

echo "-- c5: the named path follows docs-root: in config.yaml --"
s24_h7=$(make_home)
s24_p7=$(mktemp -d); cleanup_dirs+=("$s24_p7")
mkdir -p "$s24_p7/.bionic" "$s24_p7/.bionic/docs/plans/epic-01-demo"
printf 'docs-root: custom/docs\n' > "$s24_p7/.bionic/config.yaml"
engage "$s24_p7"
s24_marked_plan > "$s24_p7/.bionic/docs/plans/epic-01-demo/wave-01-x.plan.md"
run_hook_with_project "$s24_h7" "$s24_p7" 'git commit -m "x"'
if [ "$HOOK_EXIT" -eq 2 ] && grep -qF "$s24_p7/custom/docs/plans/" <<<"$HOOK_VSTDERR"; then
  ok "block names the CONFIGURED docs root, not a hardcoded .bionic/"
else
  no "block names the CONFIGURED docs root, not a hardcoded .bionic/" "expected block naming $s24_p7/custom/docs/plans/; exit=$HOOK_EXIT stderr='$HOOK_STDERR'"
fi

echo "-- c6: a non-commit command is never touched by any of this --"
s24_h8=$(make_home)

echo "-- c7: a NON-EMPTY ~/.claude/plans must not make the sweep unreachable --"
# Step-6 finding C1/S2, still pinned after its root cause was removed. The guard
# on this whole block used to be "no plan was found in ANY searched directory",
# and the FIRST directory searched was the global, project-agnostic
# ~/.claude/plans/. One unrelated .md there — the harness's own plan mode writes
# into exactly that directory — made $PLAN non-empty and the block dead. Two
# such files were sitting on the developing machine, so the branch AC-13 added
# had never executed in production.
#
# C1/S2 fixed that by scoping the guard to a project-only selection. The
# 2026-07-28 ruling fixed it at the root instead: the global directory is no
# longer searched at all, so nothing in it can make $PLAN non-empty and the
# project-only selection collapsed back into $PLAN. These three cases now pin
# that the whole class is structurally gone — a file in ~/.claude/plans/ changes
# none of the three verdicts below. They also stop make_home()'s EMPTY
# ~/.claude/plans/ from substituting away the precondition, which is the
# recorded seam-blindness class and the reason they are written this way.
# [WALL: hooks/canonical-sdlc-evidence-gate.sh]
s24_h9=$(make_home)
printf '# just a note\n' > "$s24_h9/.claude/plans/stray.md"
s24_p9=$(mktemp -d); cleanup_dirs+=("$s24_p9")
mkdir -p "$s24_p9/docs/bionic/plans/epic-01-demo"
engage "$s24_p9"
s24_marked_plan > "$s24_p9/docs/bionic/plans/epic-01-demo/wave-01-x.plan.md"
run_hook_with_project "$s24_h9" "$s24_p9" 'git commit -m "x"'
if [ "$HOOK_EXIT" -eq 2 ] \
   && grep -q "misplaced" <<<"$HOOK_VSTDERR" \
   && grep -qF "$s24_p9/.bionic/docs/plans/" <<<"$HOOK_VSTDERR"; then
  ok "misplaced plan blocks even with a non-empty ~/.claude/plans"
else
  no "misplaced plan blocks even with a non-empty ~/.claude/plans" "expected block; exit=$HOOK_EXIT stderr='$HOOK_STDERR'"
fi

# The guard must not widen the BLOCK. A project whose plan is correctly placed
# has a plan, so the sweep never runs — regardless of what the global directory
# holds.
s24_h10=$(make_home)
printf '# just a note\n' > "$s24_h10/.claude/plans/stray.md"
s24_p10=$(make_project)
s24_marked_plan > "$s24_p10/.bionic/docs/plans/wave-01-x.plan.md"
touch "$s24_p10/.bionic/docs/plans/wave-01-x.plan.md"
run_hook_with_project "$s24_h10" "$s24_p10" 'git commit -m "x"'
if [ "$HOOK_EXIT" -eq 0 ] && [ -z "$HOOK_STDERR" ]; then
  ok "correctly-placed project plan + non-empty ~/.claude/plans → no false block"
else
  no "correctly-placed project plan + non-empty ~/.claude/plans → no false block" "expected allow; exit=$HOOK_EXIT stderr='$HOOK_STDERR'"
fi

# ABSENCE still never blocks, even though the sweep now runs in this state.
s24_h11=$(make_home)
printf '# just a note\n' > "$s24_h11/.claude/plans/stray.md"
s24_p11=$(mktemp -d); cleanup_dirs+=("$s24_p11")
mkdir -p "$s24_p11/src"
printf 'echo hi\n' > "$s24_p11/src/main.sh"
run_hook_with_project "$s24_h11" "$s24_p11" 'git commit -m "x"'
if [ "$HOOK_EXIT" -eq 0 ] && [ -z "$HOOK_STDERR" ]; then
  ok "no project plan, nothing misplaced, non-empty ~/.claude/plans → allow"
else
  no "no project plan, nothing misplaced, non-empty ~/.claude/plans → allow" "expected allow; exit=$HOOK_EXIT stderr='$HOOK_STDERR'"
fi

# ============================================================
# Section 25: C2/S1 — the two hooks name ONE root per repo
# ============================================================
#
# The governing-skill hook resolves the project root with resolve_project_root
# (`--git-common-dir`, i.e. the MAIN repo even from inside a linked worktree).
# This gate derived PROJECT_DIR — and therefore DOCS_ROOT, PLAN_DIRS and the
# AC-13 misplacement sweep's root — from CLAUDE_PROJECT_DIR/.cwd/pwd, i.e. the
# WORKTREE. Task 1 migrated only audit_root().
#
# The consequence was that in a linked worktree NO artifact placement satisfied
# both hooks: put the plan where the governing hook demands (the main repo) and
# every commit from the worktree ran ungated; put it in the worktree so the gate
# finds it and every artifact write was blocked. canonical-sdlc ships a
# `use_worktree` flag, so this is the lifecycle's own normal mode.
#
# Fixture fidelity: a real `git init` + `git worktree add`, like Section 21c —
# the behaviour under test is git's own --git-common-dir handling.
# [WALL: hooks/canonical-sdlc-evidence-gate.sh]

section "Section 25: one root per repo across both hooks (worktrees)"

s25_plan() {  # a canonical plan whose current step evidence is a placeholder
  printf -- '---\ngoverning-skill: canonical-sdlc\ncanonical_sdlc_version: 14\n'
  printf -- 'intent: build\nrigor: single\nscale: wave\n'
  printf -- 'deploy_target: none\nuse_worktree: true\nhas_ui: false\n---\n'
  printf -- '## SDLC State\ncurrent: 5\napproved-by: fixture 2026-09-07T00:00Z approved\nStep 5: TODO\n'
}

s25_tmp=$(cd "$(mktemp -d)" && pwd -P); cleanup_dirs+=("$s25_tmp")
s25_main="$s25_tmp/main"
mkdir -p "$s25_main/.bionic/docs/plans"
git -C "$s25_main" init -q .
git -C "$s25_main" commit -q --allow-empty -m init
git -C "$s25_main" worktree add -q "$s25_tmp/wt" -b s25-wt
s25_wt="$s25_tmp/wt"
engage "$s25_main"
s25_plan > "$s25_main/.bionic/docs/plans/wave-01-x.plan.md"

echo "-- 25a: a commit FROM the worktree is gated against the main repo's plan --"
s25_h1=$(make_home)
run_hook_with_project "$s25_h1" "$s25_wt" 'git commit -m "x"'
if [ "$HOOK_EXIT" -eq 2 ] \
   && grep -q "placeholder" <<<"$HOOK_VSTDERR" \
   && grep -qF "$s25_main/.bionic/docs/plans/wave-01-x.plan.md" <<<"$HOOK_VSTDERR"; then
  ok "25a commit from a linked worktree is gated by the main repo's plan"
else
  no "25a commit from a linked worktree is gated by the main repo's plan" "expected block naming the main repo's plan; exit=$HOOK_EXIT stderr='$HOOK_STDERR'"
fi

echo "-- 25b: control — the identical commit from the MAIN repo --"
s25_h2=$(make_home)
run_hook_with_project "$s25_h2" "$s25_main" 'git commit -m "x"'
if [ "$HOOK_EXIT" -eq 2 ] && grep -q "placeholder" <<<"$HOOK_STDERR"; then
  ok "25b commit from the main repo blocks identically"
else
  no "25b commit from the main repo blocks identically" "expected block; exit=$HOOK_EXIT stderr='$HOOK_STDERR'"
fi

echo "-- 25c: the misplacement sweep also walks the MAIN repo, not the worktree --"
# Same shape, no plan anywhere the gate searches, and a marked plan sitting
# outside the docs root in the MAIN repo. Both the sweep's root and the docs
# root it names must be the main repo's.
s25_tmp2=$(cd "$(mktemp -d)" && pwd -P); cleanup_dirs+=("$s25_tmp2")
s25_main2="$s25_tmp2/main"
mkdir -p "$s25_main2/notes"
git -C "$s25_main2" init -q .
git -C "$s25_main2" commit -q --allow-empty -m init
git -C "$s25_main2" worktree add -q "$s25_tmp2/wt" -b s25-wt2
s25_wt2="$s25_tmp2/wt"
engage "$s25_main2"
s25_marked_plan_body() {
  printf -- '---\ngoverning-skill: superpowers:writing-plans\n'
  printf -- 'canonical_sdlc_version: 14\nintent: build\nrigor: single\nscale: wave\n---\n'
  printf -- '## SDLC State\ncurrent: 3\nStep 3: .bionic/docs/plans/wave-01.plan.md\n'
}
s25_marked_plan_body > "$s25_main2/notes/rogue.plan.md"
s25_h3=$(make_home)
run_hook_with_project "$s25_h3" "$s25_wt2" 'git commit -m "x"'
if [ "$HOOK_EXIT" -eq 2 ] \
   && grep -q "misplaced" <<<"$HOOK_VSTDERR" \
   && grep -qF "$s25_main2/notes/rogue.plan.md" <<<"$HOOK_VSTDERR" \
   && grep -qF "$s25_main2/.bionic/docs/plans/" <<<"$HOOK_VSTDERR"; then
  ok "25c sweep from a worktree finds the main repo's misplaced plan"
else
  no "25c sweep from a worktree finds the main repo's misplaced plan" "expected block naming the main repo's paths; exit=$HOOK_EXIT stderr='$HOOK_STDERR'"
fi

echo "-- 25e: ONE file, BOTH hooks, one worktree — the two must agree --"
# A19: every worktree fixture in this tree had asked ONE hook about the
# placement convenient to that hook, and the two suites' answers contradicted
# each other while both stayed green. This case puts a single artifact path in
# front of both binaries in the order the lifecycle actually uses them:
#   1. the governing-skill hook REFUSES the worktree-local placement and names
#      the main repo's docs root;
#   2. it ACCEPTS the placement it named;
#   3. this gate, invoked from the worktree, gates the commit against that same
#      file.
# Before the C2/S1 repair, (3) was exit 0 — obey (1) and every commit from a
# worktree ran ungated.
s25_gov_hook="$(dirname "$HOOK")/canonical-sdlc-governing-skill.sh"
s25_gov_home=$(make_home)   # keeps the governing hook's audit writes off the real ~/.claude
s25_run_write() {  # $1=file path, $2=content → S25_GOV_EXIT / S25_GOV_STDERR
  local input tmp_err
  # The governing hook is engagement-scoped too, and it looks for the marker under the
  # ARTIFACT's root — which for both arms of 25e is the main repo (engaged above).
  input=$(jq -n --arg p "$1" --arg c "$2" --arg s "$EG_SID" \
    '{session_id: $s, tool_name: "Write", tool_input: {file_path: $p, content: $c}}')
  tmp_err=$(mktemp)
  if HOME="$s25_gov_home" CLAUDE_CODE_SESSION_ID="$EG_SID" bash "$s25_gov_hook" <<< "$input" >/dev/null 2>"$tmp_err"; then
    S25_GOV_EXIT=0
  else
    S25_GOV_EXIT=$?
  fi
  S25_GOV_STDERR=$(cat "$tmp_err")
  rm -f "$tmp_err"
}
s25_artifact='---
governing-skill: superpowers:writing-plans
sdlc-step: 3
epic: epic-01-demo
wave: wave-01-x
canonical_sdlc_version: 14
intent: build
rigor: single
scale: wave
cleanup_on_finish: true
use_worktree: true
surface_type: none
language: none
has_ui: false
multi_agent: false
deploy_target: none
model_plan: orchestrator=fable-5-high
parallel-budget: writers=8 suites=4 worktrees=32 test_jobs=8 source=user
---

## Goal

One artifact path put in front of both hooks, so their answers about placement must agree.

## Verification Matrix

stack-health: n/a: no long-running serve observed

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1 | T1 | discharged | see AC-1 | CONFIRMED |

## SDLC State
current: 5
approved-by: fixture 2026-09-07T00:00Z "approved"
Step 5: TODO
'
s25_run_write "$s25_wt/.bionic/docs/plans/epic-01-demo/both.plan.md" "$s25_artifact"
if [ "$S25_GOV_EXIT" -eq 2 ] && grep -qF "$s25_main/.bionic/docs" <<<"$S25_GOV_STDERR"; then
  ok "25e1 governing hook refuses the worktree-local placement, names the main repo"
else
  no "25e1 governing hook refuses the worktree-local placement, names the main repo" "exit=$S25_GOV_EXIT stderr='$S25_GOV_STDERR'"
fi

mkdir -p "$s25_main/.bionic/docs/plans/epic-01-demo"
s25_run_write "$s25_main/.bionic/docs/plans/epic-01-demo/both.plan.md" "$s25_artifact"
if [ "$S25_GOV_EXIT" -eq 0 ]; then
  ok "25e2 governing hook accepts the placement it named"
else
  no "25e2 governing hook accepts the placement it named" "exit=$S25_GOV_EXIT stderr='$S25_GOV_STDERR'"
fi

printf '%s' "$s25_artifact" > "$s25_main/.bionic/docs/plans/epic-01-demo/both.plan.md"
touch "$s25_main/.bionic/docs/plans/epic-01-demo/both.plan.md"
s25_h5=$(make_home)
run_hook_with_project "$s25_h5" "$s25_wt" 'git commit -m "x"'
if [ "$HOOK_EXIT" -eq 2 ] \
   && grep -q "placeholder" <<<"$HOOK_VSTDERR" \
   && grep -qF "$s25_main/.bionic/docs/plans/epic-01-demo/both.plan.md" <<<"$HOOK_VSTDERR"; then
  ok "25e3 the gate, from the worktree, gates the SAME file the governing hook accepted"
else
  no "25e3 the gate, from the worktree, gates the SAME file the governing hook accepted" "exit=$HOOK_EXIT stderr='$HOOK_STDERR'"
fi

ac10_oldgit=$(mktemp -d); cleanup_dirs+=("$ac10_oldgit")
ac10_real_git=$(command -v git)
{
  printf '#!/bin/bash\n'
  printf 'for a in "$@"; do\n'
  printf '  [ "$a" = "--path-format=absolute" ] && exit 129\n'
  printf 'done\n'
  printf 'exec %s "$@"\n' "$ac10_real_git"
} > "$ac10_oldgit/git"
chmod +x "$ac10_oldgit/git"
echo "-- 25f: git < 2.31 — the two hooks still agree on one root --"
# FIX 1 and FIX 5 meet here. Under old git the resolver's primary branch fails,
# so if the fallback did not exist the gate would keep PROJECT_DIR at the
# worktree and C2/S1 would be reopened on every pre-2.31 machine — a green
# 25a would be proving nothing about them. Same fixture, same assertion, one
# variable changed.
# [WALL: hooks/canonical-sdlc-evidence-gate.sh]
s25_h6=$(make_home)
s25_saved_path="$PATH"
PATH="$ac10_oldgit:$PATH"
run_hook_with_project "$s25_h6" "$s25_wt" 'git commit -m "x"'
PATH="$s25_saved_path"
if [ "$HOOK_EXIT" -eq 2 ] \
   && grep -q "placeholder" <<<"$HOOK_VSTDERR" \
   && grep -qF "$s25_main/.bionic/docs/plans/" <<<"$HOOK_VSTDERR"; then
  ok "25f old git — worktree commit still gated by the main repo's plan"
else
  no "25f old git — worktree commit still gated by the main repo's plan" "expected block naming the main repo; exit=$HOOK_EXIT stderr='$HOOK_STDERR'"
fi

echo "-- 25d: a non-repo project dir still resolves to itself (fallback intact) --"
# resolve_project_root falls back to the supplied value when git cannot answer,
# so every non-repo fixture in this suite keeps its previous meaning.
s25_h4=$(make_home)
s25_p4=$(make_project)
s24_marked_plan > "$s25_p4/.bionic/docs/plans/wave-01-x.plan.md"
run_hook_with_project "$s25_h4" "$s25_p4" 'git commit -m "x"'
if [ "$HOOK_EXIT" -eq 0 ] && [ -z "$HOOK_STDERR" ]; then
  ok "25d non-repo project dir resolves to itself, plan still found"
else
  no "25d non-repo project dir resolves to itself, plan still found" "expected allow; exit=$HOOK_EXIT stderr='$HOOK_STDERR'"
fi

echo "-- 25g: THE WORKTREE ALIAS (D7, wave-13-fixit-180, AC-7.2). An 'evidence:' file written
# RELATIVE from inside a spawned worktree, with a plain shell redirect — no hook in the
# loop, exactly how a dispatched writer makes it. project_root already folds the gate's OWN
# resolution onto the main checkout (25a proves that), but that does not help a file that
# was never physically written there: without the alias the write lands INSIDE the
# worktree, invisible to the gate. With the alias — spawn-worktree.sh create's own act,
# planted before any writer touches the tree — the SAME relative write lands, physically,
# in the main checkout, and the gate allows the commit. --"

matrix_w25g="## Verification Matrix

stack-health: process restarts 0 → 0 across walk; no crash/OOM state change

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1 | T1 | discharged | see AC-1 | CONFIRMED |

AC-1:
  fails-when: the planted defect this eval must go red on
  evidence: record/w25g/x.md
  tier-run: bash test.sh — unit suite
  readback: 1/1 asserted"

s25g_tmp=$(cd "$(mktemp -d)" && pwd -P); cleanup_dirs+=("$s25g_tmp")
s25g_main="$s25g_tmp/main"
mkdir -p "$s25g_main/.bionic/docs/plans"
git -C "$s25g_main" init -q .
git -C "$s25g_main" commit -q --allow-empty -m init
engage "$s25g_main"
# The Step-5 block names this repository's own head (wave-26 T4, D5): every tree below is cut from it.
plan 5 "${step5_base/$EG_HEAD/$(git -C "$s25g_main" rev-parse HEAD)}" "$matrix_w25g" > "$s25g_main/.bionic/docs/plans/wave-01-x.plan.md"

# (a) NO alias: a PLAIN `git worktree add` — this world exists whether or not `create` plants
# an alias, and is the honest control — the record written relative from inside it lands
# inside the worktree, orphaned from the main tree the gate resolves against.
git -C "$s25g_main" worktree add -q "$s25g_tmp/wt-noalias" -b s25g-noalias
s25g_wt_a="$s25g_tmp/wt-noalias"
( cd "$s25g_wt_a" && mkdir -p .bionic/docs/record/w25g && printf 'evidence\n' > .bionic/docs/record/w25g/x.md )
expect_false "25g(a) without the alias, the relative write never reaches the main tree" \
  test -f "${s25g_main}/.bionic/docs/record/w25g/x.md"
run_hook_with_project "$(make_home)" "$s25g_wt_a" 'git commit -m "x"'
if [ "$HOOK_EXIT" -eq 2 ]; then
  ok "25g(a) …so the evidence-gate block names the missing file"
else
  no "25g(a) …so the evidence-gate block names the missing file" \
    "expected block; exit=$HOOK_EXIT stderr='$HOOK_STDERR'"
fi

# (b) THE REAL `spawn-worktree.sh create` (not a hand-planted symlink — the thing under test
# is whether CREATE itself plants the alias) on a second, otherwise identical worktree — the
# same relative write now lands in the main checkout.
s25g_sha="$(git -C "$s25g_main" rev-parse HEAD)"
( cd "$s25g_main" && bash "${BIONIC_SCRIPTS_DIR}/payload/scripts/spawn-worktree.sh" create "$s25g_sha" s25g-alias >/dev/null 2>&1 )
s25g_wt_b="${s25g_main}/.worktrees/s25g-alias"
( cd "$s25g_wt_b" && mkdir -p .bionic/docs/record/w25g && printf 'evidence\n' > .bionic/docs/record/w25g/x.md )
expect_true "25g(b) with the alias, the SAME relative write lands in the main tree" \
  test -f "${s25g_main}/.bionic/docs/record/w25g/x.md"
run_hook_with_project "$(make_home)" "$s25g_wt_b" 'git commit -m "x"'
if [ "$HOOK_EXIT" -eq 0 ] && [ -z "$HOOK_STDERR" ]; then
  ok "25g(b) …so the evidence-gate allows the commit"
else
  no "25g(b) …so the evidence-gate allows the commit" "expected allow; exit=$HOOK_EXIT stderr='$HOOK_STDERR'"
fi

echo "-- 25g(c)-(f): THE ROW'S STEP IS THE JUDGMENT (wave-14 REQ-2, ADR-027, AC-2.1-2.4).
# Parallel writers broke the gate's one assumption: several tasks are in flight at once, each
# at its own step, each in its own tree, and every one of them was judged against the run's
# single \`current:\`. A Step-4 writer committing while the run sits at Step 5 was refused for
# evidence that cannot exist yet, and in wave-13 the orchestrator regressed \`current:\` by hand
# to land it. ADR-027 makes the \`## Tasks\` table the register: the row names the tree, the
# gate reads the row, and the commit is judged at THAT row's step.
#
# THE FIXTURE IS ONE PLAN, DRIVEN FROM THREE PLACES — that is the whole discrimination. The
# same \`current: 5\` plan carries a Step-5 block that is NOT green (pass 331 of 332), so a
# main-root commit must still be refused for it; a commit from the tree row T3 owns must be
# judged at Step 4 and allowed; and a commit from the tree row T9 owns, whose step is AHEAD
# of the run, must be refused naming the row and both steps. One plan, three verdicts. --"

s25r_step4="  worktree: .worktrees/wt-T3
  base-sha: 0fe69ed
  branch: wt/14-T3"

# NOT GREEN, deliberately: this is the byte that makes 25g(d) a real control rather than a
# second copy of 25g(c).
s25r_step5_red="  cmd: bash test.sh
  pass: 331
  total: 332
  output: .bionic/docs/plans/wave-01.plan.md#step-5
  auditor: 3 rows CONFIRMED — report .bionic/tmp/audit.md"

# The register. The `worktree` cell sits between `Files` and `status`, where this wave's own
# plan carries it.
s25r_tasks="## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | worktree | status |
|---|---|---|---|---|---|---|---|---|---|---|
| T3 | 4 | build | the build in its own tree | senior-implementor | — | 60m | REQ-2 | a.sh | wt-T3 | active |
| T9 | 6 | review | the review the run has not reached | critic | T3 | 30m | REQ-2 | b.sh | wt-T9 | pending |
| T5 | 5 | build | the row standing exactly where the run stands | implementor | — | 20m | REQ-2 | c.sh | wt-T5 | active |
| T6 | 6 | review | a review filled ahead of the run, its writer at work | critic | T3 | 30m | REQ-5 | d.sh | wt-T6 | active |
| T8 | 8 | integrate | the merge, a gate act, ahead of the run | implementor | T3 | 30m | REQ-5 | — | wt-T8 | active |"

s25r_plan() {
  printf '%s\n## SDLC State\ncurrent: 5\napproved-by: fixture 2026-09-14T00:00Z "approved"\nStep 4:\n%s\nStep 5:\n%s\n\n%s\n\n%s\n' \
    "$(matrix_frontmatter true none true)" "$s25r_step4" "$s25r_step5_red" "$s25r_tasks" "$matrix_w25g"
}

s25r_tmp=$(cd "$(mktemp -d)" && pwd -P); cleanup_dirs+=("$s25r_tmp")
s25r_main="$s25r_tmp/main"
mkdir -p "$s25r_main/.bionic/docs/plans" "$s25r_main/.bionic/docs/record/w25g"
printf 'evidence\n' > "$s25r_main/.bionic/docs/record/w25g/x.md"
git -C "$s25r_main" init -q .
git -C "$s25r_main" commit -q --allow-empty -m init
engage "$s25r_main"
s25r_plan > "$s25r_main/.bionic/docs/plans/wave-01-x.plan.md"

# REAL LINKED WORKTREES, never a hand-planted `.git` file: the name the arm reads is the one
# git itself chose for the tree, out of `<main>/.git/worktrees/<name>`.
git -C "$s25r_main" worktree add -q "$s25r_tmp/wt-T3" -b s25r-t3
git -C "$s25r_main" worktree add -q "$s25r_tmp/wt-T9" -b s25r-t9
git -C "$s25r_main" worktree add -q "$s25r_tmp/wt-stray" -b s25r-stray
git -C "$s25r_main" worktree add -q "$s25r_tmp/wt-T5" -b s25r-t5
git -C "$s25r_main" worktree add -q "$s25r_tmp/wt-T6" -b s25r-t6
git -C "$s25r_main" worktree add -q "$s25r_tmp/wt-T8" -b s25r-t8

# THE ALLOW-PATH NOTE, SPELLED ONCE (T24 item (c), architecture review \u00a74.1). Before this
# wave the gate spoke when it DECLINED to use the register (25g(f)) and stayed silent when it
# used it \u2014 so the one case where a wall substitutes a different value for the run's declared
# `current:` was the one case with no record of having done it. Every allow below that is
# judged behind `current:` now carries this exact line. (25g(k) was the silence control for
# it until wave-17; a row standing where the run stands is now read for its `status` and gets
# a note of its own — ADR-031, and the re-authored 25g(k) below.)
s25r_note_T3="evidence-gate: judged at row T3's step 4 (run at current: 5)"

expect_eq "25g(c) the fixture's tree really is a LINKED worktree (its .git is a file)" "file" \
  "$(if [ -f "$s25r_tmp/wt-T3/.git" ]; then echo file; elif [ -d "$s25r_tmp/wt-T3/.git" ]; then echo dir; else echo none; fi)"
expect_contains "25g(c) …whose gitdir names the tree the plan row names" "/worktrees/wt-T3" \
  "$(cat "$s25r_tmp/wt-T3/.git")"

# --- 25g(c) / AC-2.1: the worktree commit is judged at its row's step ---------------------
#
# CLAUDE_PROJECT_DIR is the MAIN checkout and the payload's `.cwd` is the worktree — the
# arrangement A-T2.5 names, and the one that makes BIONIC_WORKTREE read EMPTY. An arm that
# leaned on that variable alone would pass this case only when the fixture lied about the
# environment.
run_hook_cwd "$(make_home)" "$s25r_main" "$s25r_tmp/wt-T3" 'git commit -m "x"'
if [ "$HOOK_EXIT" -eq 0 ] && [ "$HOOK_STDERR" = "$s25r_note_T3" ]; then
  ok "25g(c) AC-2.1 a commit from row T3's tree is judged at the row's step 4, allowed, and the note says so"
else
  no "25g(c) AC-2.1 a commit from row T3's tree is judged at the row's step 4, allowed, and the note says so" \
    "expected allow + the note; exit=$HOOK_EXIT stderr='$HOOK_STDERR' detail='$HOOK_VSTDERR'"
fi

# --- 25g(d) / AC-2.2: the main root is untouched ------------------------------------------
run_hook_with_project "$(make_home)" "$s25r_main" 'git commit -m "x"'
if [ "$HOOK_EXIT" -eq 2 ] && grep -q "pass=331" <<<"$HOOK_VSTDERR"; then
  ok "25g(d) AC-2.2 the SAME plan still refuses a main-root commit at current: 5 for pass != total"
else
  no "25g(d) AC-2.2 the SAME plan still refuses a main-root commit at current: 5 for pass != total" \
    "expected block naming pass=331; exit=$HOOK_EXIT stderr='$HOOK_STDERR' detail='$HOOK_VSTDERR'"
fi

# --- 25g(e) / AC-2.3, RE-AUTHORED BY wave-20 REQ-5 (Δ6, AC-5.1): a row AHEAD of the run ----
#
# Through 1.8.6 every row ahead of `current:` was refused: the step filter meant nothing ahead
# could be dispatched, so a tree whose row sat past the run was one nobody should be
# committing from. Readiness is now the prerequisite graph (Δ1), so a Step-6 row whose deps
# have landed IS dispatched during Step 5, and a writer that cannot commit would be the fill's
# own dead end. Δ6 draws the line: an ACTIVE work row ahead of the run is a writer at work and
# is judged by the task arms, exactly as an in-step active row is; a row that is NOT active,
# and any integrate/close row (a gate act, whose real prerequisite is a gate passing), keeps
# the refusal — and the refusal still names the row and both steps.
#
# 25g(e): T9 is PENDING — no writer was dispatched into its tree — so it keeps the refusal.
run_hook_cwd "$(make_home)" "$s25r_main" "$s25r_tmp/wt-T9" 'git commit -m "x"'
if [ "$HOOK_EXIT" -eq 2 ] && eg_e1_check \
   && grep -q "T9" <<<"$HOOK_VSTDERR" \
   && grep -qE "(^|[^0-9])6([^0-9]|$)" <<<"$HOOK_VSTDERR" \
   && grep -qE "(^|[^0-9])5([^0-9]|$)" <<<"$HOOK_VSTDERR"; then
  ok "25g(e) AC-2.3 a commit from a tree whose PENDING row is ahead of current: is refused, naming T9, 6 and 5"
else
  no "25g(e) AC-2.3 a commit from a tree whose PENDING row is ahead of current: is refused, naming T9, 6 and 5" \
    "expected block naming T9/6/5; exit=$HOOK_EXIT stderr='$HOOK_STDERR' detail='$HOOK_VSTDERR'"
fi

# 25g(e2) / AC-5.1: T6 is an ACTIVE Step-6 review row, filled at Step 5 because its deps
# landed. Its commit is judged by the task arms — allowed on the same plan whose Step-5 block
# refuses a main-root commit (25g(d)) — and the note names the row, as the in-step arm's does.
run_hook_cwd "$(make_home)" "$s25r_main" "$s25r_tmp/wt-T6" 'git commit -m "x"'
if [ "$HOOK_EXIT" -eq 0 ] \
   && [ "$HOOK_STDERR" = "evidence-gate: judged by row T6's task arms (run at current: 5)" ]; then
  ok "25g(e2) AC-5.1 an ACTIVE row ahead of current: commits, judged by its task arms, and the note says so"
else
  no "25g(e2) AC-5.1 an ACTIVE row ahead of current: commits, judged by its task arms, and the note says so" \
    "expected allow + the task-arms note; exit=$HOOK_EXIT stderr='$HOOK_STDERR' detail='$HOOK_VSTDERR'"
fi

# 25g(e3) / Δ6: T8 is an ACTIVE Step-8 integrate row. A gate act ahead of the run keeps the
# refusal whatever its status: the merge must not commit before Verify has passed.
run_hook_cwd "$(make_home)" "$s25r_main" "$s25r_tmp/wt-T8" 'git commit -m "x"'
if [ "$HOOK_EXIT" -eq 2 ] && eg_e1_check \
   && grep -q "T8" <<<"$HOOK_VSTDERR" \
   && grep -qE "(^|[^0-9])8([^0-9]|$)" <<<"$HOOK_VSTDERR"; then
  ok "25g(e3) Δ6 an ACTIVE integrate row ahead of current: is still refused, naming T8 and 8"
else
  no "25g(e3) Δ6 an ACTIVE integrate row ahead of current: is still refused, naming T8 and 8" \
    "expected block naming T8/8; exit=$HOOK_EXIT stderr='$HOOK_STDERR' detail='$HOOK_VSTDERR'"
fi

# --- 25g(f): a tree no row owns keeps today's behaviour, and says so ----------------------
#
# FAIL-SAFE, NOT FAIL-OPEN: the commit is judged at `current:` exactly as it is today — so it
# is refused for the same not-green Step-5 block 25g(d) is refused for — and one line on
# stderr names the tree, so a writer whose row was never ledgered finds out from the wall
# rather than from the verdict.
run_hook_cwd "$(make_home)" "$s25r_main" "$s25r_tmp/wt-stray" 'git commit -m "x"'
if [ "$HOOK_EXIT" -eq 2 ] && grep -q "pass=331" <<<"$HOOK_VSTDERR" \
   && grep -q "wt-stray" <<<"$HOOK_STDERR"; then
  ok "25g(f) a tree no ## Tasks row names is judged at current: and the note names the tree"
else
  no "25g(f) a tree no ## Tasks row names is judged at current: and the note names the tree" \
    "expected block at current: 5 plus a note naming wt-stray; exit=$HOOK_EXIT stderr='$HOOK_STDERR' detail='$HOOK_VSTDERR'"
fi

# --- 25g(g): `git -C <worktree>` from the main root is the worktree's commit --------------
#
# The payload's cwd is the MAIN checkout and the tree is named by the command instead. The
# commit still happens in row T3's tree, so it is still row T3's commit.
run_hook_cwd "$(make_home)" "$s25r_main" "$s25r_main" "git -C $s25r_tmp/wt-T3 commit -m \"x\""
if [ "$HOOK_EXIT" -eq 0 ] && [ "$HOOK_STDERR" = "$s25r_note_T3" ]; then
  ok "25g(g) a 'git -C <worktree> commit' from the main root is judged at row T3's step too"
else
  no "25g(g) a 'git -C <worktree> commit' from the main root is judged at row T3's step too" \
    "expected allow + the note; exit=$HOOK_EXIT stderr='$HOOK_STDERR' detail='$HOOK_VSTDERR'"
fi

# --- 25g(h): the shape every bionic brief mandates — `cd <tree> || exit 1; git commit` -----
#
# A writer's Bash call carries the tree in the COMMAND, not in the payload: the harness posts
# the session's cwd, and the `cd` runs afterwards. Without this arm the dominant real shape
# would take the main-root path and AC-2.1 would hold only for fixtures.
run_hook_cwd "$(make_home)" "$s25r_main" "$s25r_main" "cd $s25r_tmp/wt-T3 || exit 1; git commit -m \"x\""
if [ "$HOOK_EXIT" -eq 0 ] && [ "$HOOK_STDERR" = "$s25r_note_T3" ]; then
  ok "25g(h) a leading 'cd <worktree> || exit 1' before the commit is judged at row T3's step"
else
  no "25g(h) a leading 'cd <worktree> || exit 1' before the commit is judged at row T3's step" \
    "expected allow + the note; exit=$HOOK_EXIT stderr='$HOOK_STDERR' detail='$HOOK_VSTDERR'"
fi

# --- 25g(i)-(n): THE ARM RECONCILES ITS SUBJECT WITH GIT (wave-14 T24, REQ-2) -------------
#
# WHAT WENT WRONG, IN ONE SENTENCE. The arm named the tree it judged from the command TEXT
# and from a `.git` FILE, and never reconciled either with the tree the commit lands in — so
# the OBJECT of the judgement (the commit) and the SUBJECT of it (a directory named in a
# string) were two different things, and a main-checkout commit could be judged at a Step-4
# row's step and skip the whole Step-5 verify shape, leaving no artifact behind: the plan
# still reads `current: 5`, the commit still lands in main, and the only record is a
# transcript line.
#
# THE FOUR CASES BELOW ARE THE FOUR WAYS IT COULD BE WRONG, and each is driven against the
# SAME `current: 5` fixture 25g(c)-(h) drive, so the discrimination is the input and nothing
# else:
#   (i) the tree is not git's       — a hand-written `.git` file naming any row's cell;
#   (j) the text names two trees    — `cd <tree> && cd <main> && git commit`;
#   (k) the row stands where the run stands — its `status` decides (k2 is the control);
#   (l) two rows name one tree      — the register is ambiguous, not resolvable by order;
#   (m) `git -C <relative>`         — a real worktree commit that used to lose its row;
#   (n) `g\<newline>it commit`      — a real commit the cheap screen called "provably not".

# --- 25g(i): a directory git never made is not a worktree, whatever its `.git` file says --
#
# The security review's own repro, verbatim in shape: the file names row T3's tree, the
# gitdir target does not exist and belongs to no repository, and the directory need not even
# be inside this repo. The FILE READ IS A PRE-FILTER and nothing more from here on — git is
# asked, git says no, the arm declines, and the commit is judged at `current: 5` exactly as
# a main-root commit is. 25g(c) is the control: the SAME derived name, from a tree git made,
# still resolves to row T3.
s25r_forged="$s25r_tmp/forged"
mkdir -p "$s25r_forged"
printf 'gitdir: /nowhere/at/all/.git/worktrees/wt-T3\n' > "$s25r_forged/.git"
expect_eq "25g(i) the forged tree really does answer row T3's name to a file read" "wt-T3" \
  "$(_g=$(head -1 "$s25r_forged/.git"); _g="${_g#gitdir: }"; printf '%s' "${_g##*/}")"
run_hook_cwd "$(make_home)" "$s25r_main" "$s25r_main" "cd $s25r_forged || exit 1; git commit -m \"x\""
if [ "$HOOK_EXIT" -eq 2 ] && grep -q "pass=331" <<<"$HOOK_VSTDERR" \
   && ! grep -q "judged at row" <<<"$HOOK_STDERR"; then
  ok "25g(i) a forged .git naming row T3's tree is declined and the commit is judged at current: 5"
else
  no "25g(i) a forged .git naming row T3's tree is declined and the commit is judged at current: 5" \
    "expected the Step-5 refusal and no row note; exit=$HOOK_EXIT stderr='$HOOK_STDERR' detail='$HOOK_VSTDERR'"
fi

# --- 25g(j): two directories named before the commit is an ambiguity, not a first one -----
#
# The critic's issue 1, and the one the reconcile alone does NOT close: wt-T3 is a REAL
# linked worktree of this repo, so git confirms it — and the commit still lands in main.
# The text names two trees and the arm cannot know which one obeys, so it refuses and names
# both rather than trusting the one that happens to come first.
run_hook_cwd "$(make_home)" "$s25r_main" "$s25r_main" "cd $s25r_tmp/wt-T3 && cd $s25r_main && git commit -m \"x\""
if [ "$HOOK_EXIT" -eq 2 ] && eg_e1_check \
   && grep -qF "$s25r_tmp/wt-T3" <<<"$HOOK_VSTDERR" \
   && grep -qF "$s25r_main" <<<"$HOOK_VSTDERR"; then
  ok "25g(j) 'cd <tree> && cd <main> && git commit' is refused as ambiguous, naming both directories"
else
  no "25g(j) 'cd <tree> && cd <main> && git commit' is refused as ambiguous, naming both directories" \
    "expected exit 2 naming both dirs; exit=$HOOK_EXIT stderr='$HOOK_STDERR' detail='$HOOK_VSTDERR'"
fi

# --- 25g(j2) / AC-3.1: the ambiguity is the COMMAND's, not the first directory's ----------
#
# THE FAIL-OPEN HALF OF 25g(j) (wave-17 REQ-3, D4; bug 6). The arm above lived inside the
# `_EG_WT` guard, so it only ever saw a command whose FIRST directory git had confirmed as a
# linked worktree of this repository. Every other first directory — the main checkout, a
# records directory under it, `/tmp` — left `_EG_WT` empty, skipped the whole block, and the
# commit was judged at the run's `current:` with no word said about the second `cd`. That is
# the shape a consumer actually wrote (`cd <records-dir>; …; cd <tree> && git commit`) and
# the shape that produced an unrelated wave-level refusal instead of an answer.
#
# NOTHING IN THE TEXT SAYS WHICH DIRECTORY OBEYS, and that is true whatever the first one is:
# a `;` runs the rest wherever the shell is standing, a failed `cd` leaves it in the old
# place, and a `&&` only looks decisive. So the refusal is a property of the COMMAND and the
# arm is asked before any directory is resolved. Driven from the same `current: 5` fixture,
# with an ordinary directory (the main checkout's own record/ tree) in first position — the
# one position that used to buy silence.
s25r_amb="cd $s25r_main/.bionic/docs/record/w25g; printf 'x\\n' > y.md; cd $s25r_tmp/wt-T3 && git commit -m \"x\""
run_hook_cwd "$(make_home)" "$s25r_main" "$s25r_main" "$s25r_amb"
if [ "$HOOK_EXIT" -eq 2 ] && eg_e1_check \
   && grep -qF "two directories are named before the commit" <<<"$HOOK_STDERR" \
   && grep -qF "$s25r_main/.bionic/docs/record/w25g" <<<"$HOOK_VSTDERR" \
   && grep -qF "$s25r_tmp/wt-T3" <<<"$HOOK_VSTDERR" \
   && grep -qF "git -C <dir> commit" <<<"$HOOK_VSTDERR"; then
  ok "25g(j2) AC-3.1 two directories before the commit are refused when the FIRST is an ordinary directory too"
else
  no "25g(j2) AC-3.1 two directories before the commit are refused when the FIRST is an ordinary directory too" \
    "expected exit 2 'two directories are named before the commit' naming both dirs and git -C; exit=$HOOK_EXIT stderr='$HOOK_STDERR' detail='$HOOK_VSTDERR'"
fi

# …and the control that keeps it from becoming "any cd is a refusal": the SAME first
# directory, one `cd`, is judged at `current:` exactly as 25g(i) and 25g(d) are.
run_hook_cwd "$(make_home)" "$s25r_main" "$s25r_main" \
  "cd $s25r_main/.bionic/docs/record/w25g || exit 1; git commit -m \"x\""
if [ "$HOOK_EXIT" -eq 2 ] && grep -q "pass=331" <<<"$HOOK_VSTDERR" \
   && ! grep -qF "two directories" <<<"$HOOK_STDERR"; then
  ok "25g(j2) …and ONE cd into that same directory is still judged at current: 5, not refused as ambiguous"
else
  no "25g(j2) …and ONE cd into that same directory is still judged at current: 5, not refused as ambiguous" \
    "expected the Step-5 refusal and no ambiguity line; exit=$HOOK_EXIT stderr='$HOOK_STDERR' detail='$HOOK_VSTDERR'"
fi

# --- 25g(s) / C3: two `cd`s that name ONE directory are one directory ---------------------
#
# The arm fired on the PRESENCE of a second `cd` token and never on whether the two
# directories differ, so `cd X && cd X` was refused with a sentence that answers its own
# complaint — "the command changes into 'X' and then into 'X'" — and `cd X && cd .` with it.
# Nothing is ambiguous about a command that names one directory twice: the shell is standing
# in the same place whichever `cd` obeyed, and the gate holds both values before it speaks.
# So the arm compares the two RESOLVED targets and refuses only when they DIFFER. 25g(j) and
# 25g(j2) above are the controls that keep this from becoming "any second cd is fine".
#
# RESOLVED, NOT INTERPRETED (D4). The second target is read exactly as the first one is, and
# a relative target is joined to the first — which is where the shell stands when the second
# `cd` runs. A `.` segment and a trailing slash fold away lexically; nothing is stat-ed,
# nothing is expanded, and `..`, `~` and an unexpanded variable stay ambiguous and stay
# refused (A-T22.2).
run_hook_cwd "$(make_home)" "$s25r_main" "$s25r_main" \
  "cd $s25r_tmp/wt-T3 && cd $s25r_tmp/wt-T3 && git commit -m \"x\""
if [ "$HOOK_EXIT" -eq 0 ] && [ "$HOOK_STDERR" = "$s25r_note_T3" ]; then
  ok "25g(s) C3 'cd X && cd X && git commit' names ONE directory and is judged at row T3's step 4"
else
  no "25g(s) C3 'cd X && cd X && git commit' names ONE directory and is judged at row T3's step 4" \
    "expected allow + '$s25r_note_T3'; exit=$HOOK_EXIT stderr='$HOOK_STDERR' detail='$HOOK_VSTDERR'"
fi

# …and the same directory spelled `.`, which is the form a writer actually types. It is one
# directory by the same resolution, not by a special case for the string.
run_hook_cwd "$(make_home)" "$s25r_main" "$s25r_main" \
  "cd $s25r_tmp/wt-T3 && cd . && git commit -m \"x\""
if [ "$HOOK_EXIT" -eq 0 ] && [ "$HOOK_STDERR" = "$s25r_note_T3" ]; then
  ok "25g(s) …and 'cd X && cd . && git commit' resolves to that same one directory too"
else
  no "25g(s) …and 'cd X && cd . && git commit' resolves to that same one directory too" \
    "expected allow + '$s25r_note_T3'; exit=$HOOK_EXIT stderr='$HOOK_STDERR' detail='$HOOK_VSTDERR'"
fi

# …and the one-cell-away control, in the SAME fixture: two tree paths that really are two
# directories are still the refusal REQ-3 exists for, with its text unchanged.
run_hook_cwd "$(make_home)" "$s25r_main" "$s25r_main" \
  "cd $s25r_tmp/wt-T3 && cd $s25r_tmp/wt-T5 && git commit -m \"x\""
if [ "$HOOK_EXIT" -eq 2 ] && eg_e1_check \
   && grep -qF "two directories are named before the commit" <<<"$HOOK_STDERR" \
   && grep -qF "$s25r_tmp/wt-T3" <<<"$HOOK_VSTDERR" \
   && grep -qF "$s25r_tmp/wt-T5" <<<"$HOOK_VSTDERR"; then
  ok "25g(s) …while two DISTINCT resolved directories are still refused, naming both"
else
  no "25g(s) …while two DISTINCT resolved directories are still refused, naming both" \
    "expected exit 2 naming both dirs; exit=$HOOK_EXIT stderr='$HOOK_STDERR' detail='$HOOK_VSTDERR'"
fi

# --- 25g(t) / W6: EVERY `cd` before the commit is a directory the arm has to fold ---------
#
# THE HOLE C3's FIX OPENED (re-walk at 4e2ac66, W6). The reader took the FIRST `cd` after the
# first separator and returned; every later one was invisible to it. While the PRESENCE of a
# second `cd` refused, that cost nothing — the command was refused before the third target
# could matter. Once two matching targets became an allow, `cd X && cd X && cd Y` walked
# through the arm and was judged at X's row, while the shell commits in Y, which another row
# owns at another step. Fail-open, and one `&&` away from the shape 25g(j) refuses.
#
# SO THE ARM FOLDS THE WHOLE LIST, not its first two entries. Every `cd` target before the
# commit is resolved in order — each relative to the directory the previous one left the shell
# standing in — and the command names ONE directory only when they all fold alike. The first
# target that does not is the one the refusal names, so the detail always reads as a real
# disagreement and never as a sentence answering its own complaint (C3).
run_hook_cwd "$(make_home)" "$s25r_main" "$s25r_main" \
  "cd $s25r_tmp/wt-T3 && cd $s25r_tmp/wt-T3 && cd $s25r_tmp/wt-T5 && git commit -m \"x\""
if [ "$HOOK_EXIT" -eq 2 ] && eg_e1_check \
   && grep -qF "two directories are named before the commit" <<<"$HOOK_STDERR" \
   && grep -qF "changes into '$s25r_tmp/wt-T3' and then into '$s25r_tmp/wt-T5'" <<<"$HOOK_VSTDERR"; then
  ok "25g(t) W6 a THIRD cd into another directory is refused, and the detail names the pair that differs"
else
  no "25g(t) W6 a THIRD cd into another directory is refused, and the detail names the pair that differs" \
    "expected exit 2 naming wt-T3 then wt-T5; exit=$HOOK_EXIT stderr='$HOOK_STDERR' detail='$HOOK_VSTDERR'"
fi

# …and the difference is caught wherever it sits in the list: here the SECOND target is the
# odd one and the third returns to the first. A commit is still not placed by this text.
run_hook_cwd "$(make_home)" "$s25r_main" "$s25r_main" \
  "cd $s25r_tmp/wt-T3 && cd $s25r_tmp/wt-T5 && cd $s25r_tmp/wt-T3 && git commit -m \"x\""
if [ "$HOOK_EXIT" -eq 2 ] && eg_e1_check \
   && grep -qF "two directories are named before the commit" <<<"$HOOK_STDERR" \
   && grep -qF "changes into '$s25r_tmp/wt-T3' and then into '$s25r_tmp/wt-T5'" <<<"$HOOK_VSTDERR"; then
  ok "25g(t) …and a cd AWAY and BACK is refused too, naming the target that differs"
else
  no "25g(t) …and a cd AWAY and BACK is refused too, naming the target that differs" \
    "expected exit 2 naming wt-T3 then wt-T5; exit=$HOOK_EXIT stderr='$HOOK_STDERR' detail='$HOOK_VSTDERR'"
fi

# …the control that keeps this from becoming "three cds are a refusal": three spellings of the
# ONE directory are one directory, by the same fold that answers for two.
run_hook_cwd "$(make_home)" "$s25r_main" "$s25r_main" \
  "cd $s25r_tmp/wt-T3 && cd $s25r_tmp/wt-T3 && cd $s25r_tmp/wt-T3 && git commit -m \"x\""
if [ "$HOOK_EXIT" -eq 0 ] && [ "$HOOK_STDERR" = "$s25r_note_T3" ]; then
  ok "25g(t) …while THREE cds into the same directory stay one directory, judged at row T3's step 4"
else
  no "25g(t) …while THREE cds into the same directory stay one directory, judged at row T3's step 4" \
    "expected allow + '$s25r_note_T3'; exit=$HOOK_EXIT stderr='$HOOK_STDERR' detail='$HOOK_VSTDERR'"
fi

# …and the same three directories spelled the three ways a writer actually types them: the
# relative `./` is joined to where the shell is standing, and the trailing slash folds away.
run_hook_cwd "$(make_home)" "$s25r_main" "$s25r_main" \
  "cd $s25r_tmp/wt-T3 && cd ./ && cd $s25r_tmp/wt-T3/ && git commit -m \"x\""
if [ "$HOOK_EXIT" -eq 0 ] && [ "$HOOK_STDERR" = "$s25r_note_T3" ]; then
  ok "25g(t) …and 'cd X && cd ./ && cd X/' folds to that one directory as well"
else
  no "25g(t) …and 'cd X && cd ./ && cd X/' folds to that one directory as well" \
    "expected allow + '$s25r_note_T3'; exit=$HOOK_EXIT stderr='$HOOK_STDERR' detail='$HOOK_VSTDERR'"
fi

# …and what a `git -C` does to the whole question, pinned as it stands (A-T31.3). `-C` is
# branch (1) of `_eg_commit_cwd` and it answers first, because git's own cwd override is what
# the commit obeys whatever the shell did: the `cd` list is never read, the arm never fires,
# and the commit is judged at the tree `-C` names — here row T3's, though the text last
# changed into row T5's tree. This is the escape the refusal's own Fix line offers, so it has
# to keep working; the row exists so that a later widening of the arm cannot take it away
# silently.
run_hook_cwd "$(make_home)" "$s25r_main" "$s25r_main" \
  "cd $s25r_tmp/wt-T5 && git -C $s25r_tmp/wt-T3 commit -m \"x\""
if [ "$HOOK_EXIT" -eq 0 ] && [ "$HOOK_STDERR" = "$s25r_note_T3" ]; then
  ok "25g(t) …and a 'git -C <dir>' still overrides the cds the text names, judged at row T3's step 4"
else
  no "25g(t) …and a 'git -C <dir>' still overrides the cds the text names, judged at row T3's step 4" \
    "expected allow + '$s25r_note_T3'; exit=$HOOK_EXIT stderr='$HOOK_STDERR' detail='$HOOK_VSTDERR'"
fi

# --- 25g(k) / AC-1.1: the row stands where the run stands, and it is ACTIVE ---------------
#
# THE SUBJECT IS RESOLVED BEFORE ANY ARM JUDGES (wave-17 REQ-1, D1, ADR-031). Row T5 sits at
# step 5, the run is at `current: 5`, and the Step-5 block is red — the exact shape that
# refused a writer for the floor that writer's own task exists to produce (bug 2; carry-over
# 1; three D10 `current:` regressions in wave-16). What decides is the row's `status` cell,
# validated since wave-11 and read by nobody until now: `active` means this commit discharges
# T5's obligations and not the run's, so the TASK arms judge it — the Step-4 block shape and
# the matrix `fails-when:` presence — and the run's Verify arm never sees it.
#
# THE NOTE IS NOT OPTIONAL, for the reason the step substitution's note one case up is not:
# this is the second place in the fleet where a wall judges a commit by something other than
# the run's declared `current:`, and an operator who cannot explain why a commit passed must
# not have to read the source. It names the ROW, because the row is the subject.
#
# WHAT THIS ROW USED TO PIN, and why the pin moved (AC-1.4, ADR-031). Until wave-17 this was
# the silence control: step == current substituted nothing, so nothing printed. That silence
# WAS the catch-22 — it is how the run's red floor reached a task tree. 25g(k2) below is the
# control that replaces it: the SAME tree, the SAME red floor, the row `landed` instead of
# `active`.
s25r_note_T5="evidence-gate: judged by row T5's task arms (run at current: 5)"
run_hook_cwd "$(make_home)" "$s25r_main" "$s25r_tmp/wt-T5" 'git commit -m "x"'
if [ "$HOOK_EXIT" -eq 0 ] && [ "$HOOK_STDERR" = "$s25r_note_T5" ]; then
  ok "25g(k) AC-1.1 a commit from an ACTIVE row's tree meets the task arms, not the run's red floor, and the note names the row"
else
  no "25g(k) AC-1.1 a commit from an ACTIVE row's tree meets the task arms, not the run's red floor, and the note names the row" \
    "expected allow + '$s25r_note_T5'; exit=$HOOK_EXIT stderr='$HOOK_STDERR' detail='$HOOK_VSTDERR'"
fi

# --- 25g(k2) / AC-1.3: `landed` is not `active`, and status is the whole discrimination ----
#
# THE EXEMPTION IS THE ACTIVE ROW'S ALONE. A tree whose task has already landed is not a
# writer at work: nothing is in flight there, and a commit out of it is the run's like any
# other — so the red floor still refuses it, at `current:`, and the refusal names the step it
# judged at so the reader can tell WHICH arm spoke. `pending` and `dropped` are the same
# case; `landed` is the one a real run actually produces, because every row of a wave ends
# there and the tree survives until Step 8 tears it down.
#
# ONE FIXTURE AWAY FROM 25g(k): same plan, same red Step-5 block, same tree name, same
# commit. The status cell is the input and nothing else is, which is what makes the pair a
# discrimination rather than two assertions.
#
# (THE LABEL. The spec's Eval design calls this row "25g(n) new"; 25g(n) has named the
# `g\<newline>it commit` row since wave-14 and is pinned green by AC-1.4, so the new row is
# (k2), beside the row it controls. See A-T1.3.)
s25n_tasks="${s25r_tasks/| c.sh | wt-T5 | active |/| c.sh | wt-T5 | landed |}"
s25n_plan() {
  printf '%s\n## SDLC State\ncurrent: 5\napproved-by: fixture 2026-09-14T00:00Z "approved"\nStep 4:\n%s\nStep 5:\n%s\n\n%s\n\n%s\n' \
    "$(matrix_frontmatter true none true)" "$s25r_step4" "$s25r_step5_red" "$s25n_tasks" "$matrix_w25g"
}
expect_eq "25g(k2) the fixture carries T5's row as landed" "1" \
  "$(s25n_plan | grep -c 'wt-T5 | landed' | tr -d ' ')"
expect_eq "25g(k2) …and 25g(k)'s own fixture still carries it as active" "1" \
  "$(s25r_plan | grep -c 'wt-T5 | active' | tr -d ' ')"

s25n_tmp=$(cd "$(mktemp -d)" && pwd -P); cleanup_dirs+=("$s25n_tmp")
s25n_main="$s25n_tmp/main"
mkdir -p "$s25n_main/.bionic/docs/plans" "$s25n_main/.bionic/docs/record/w25g"
printf 'evidence\n' > "$s25n_main/.bionic/docs/record/w25g/x.md"
git -C "$s25n_main" init -q .
git -C "$s25n_main" commit -q --allow-empty -m init
engage "$s25n_main"
s25n_plan > "$s25n_main/.bionic/docs/plans/wave-01-x.plan.md"
git -C "$s25n_main" worktree add -q "$s25n_tmp/wt-T5" -b s25n-t5

run_hook_cwd "$(make_home)" "$s25n_main" "$s25n_tmp/wt-T5" 'git commit -m "x"'
if [ "$HOOK_EXIT" -eq 2 ] && grep -q "pass=331" <<<"$HOOK_VSTDERR" \
   && grep -q "canonical-sdlc step 5" <<<"$HOOK_VSTDERR" \
   && ! grep -q "task arms" <<<"$HOOK_STDERR"; then
  ok "25g(k2) AC-1.3 a commit from a LANDED row's tree is still judged at current:, and the refusal names step 5"
else
  no "25g(k2) AC-1.3 a commit from a LANDED row's tree is still judged at current:, and the refusal names step 5" \
    "expected the Step-5 refusal naming the step, and no task-arms note; exit=$HOOK_EXIT stderr='$HOOK_STDERR' detail='$HOOK_VSTDERR'"
fi

# --- 25g(r) / C1: the task-arms fork belongs to rows at step 4 and above ------------------
#
# THE FORK NAMES STEP 4, SO IT CAN ONLY BE ASKED OF A ROW THAT HAS REACHED IT. `CURRENT=4`
# was written whenever an `active` row stood where the run stands, and `units_validate`
# admits a step cell of 3 — so a run at `current: 3` with an `active` step-3 row committing
# out of its tree was judged at step 4, a step the run has not started, and refused for a
# `Step 4:` evidence line its author could only produce by writing a Step-4 claim into a
# Step-3 plan. That is the requirement inverted: REQ-1 exists so a task commit is not held
# to the arms of a LATER step, and this held it to the arms of a step the run had not
# reached. The guard is the row's own step (`>= 4`), and below it the row keeps today's path
# — judged at `current:`, no note, nothing substituted — which is the pending/landed/dropped
# behaviour the design already blesses.
#
# THE DISCRIMINATION IS ONE CELL, AND BOTH HALVES MUST AGREE. `active` and `landed` are
# driven against the same plan, the same tree and the same commit, and the fix is what makes
# their verdicts identical — so this pair goes red on any change that lets the fork reach a
# step-3 row, whatever refusal it produces. 25g(k) is the other side of the same guard: an
# `active` row AT step 5 still takes the fork, and it stays green unedited.
s25p_tmp=$(cd "$(mktemp -d)" && pwd -P); cleanup_dirs+=("$s25p_tmp")
s25p_main="$s25p_tmp/main"
mkdir -p "$s25p_main/.bionic/docs/plans" "$s25p_main/.bionic/docs/record/w25g"
printf 'evidence\n' > "$s25p_main/.bionic/docs/record/w25g/x.md"
git -C "$s25p_main" init -q .
git -C "$s25p_main" commit -q --allow-empty -m init
engage "$s25p_main"

s25p_plan() {  # $1 = the step-3 row's status cell — the only variable in the pair
  printf '%s\n## SDLC State\ncurrent: 3\nStep 1: requirements: .bionic/docs/plans/wave-01-x.plan.md\napproved-by: fixture 2026-09-20T00:00Z "approved"\nStep 3: .bionic/docs/record/w25g/x.md\n- T3: .bionic/docs/record/w25g/x.md\n\n## Tasks\n\n| id | step | kind | task | agent | deps | size | serves | Files | worktree | status |\n|---|---|---|---|---|---|---|---|---|---|---|\n| T3 | 3 | doc | the row standing exactly where a run at Step 3 stands | implementor | — | 20m | REQ-2 | a.sh | wt-T3r | %s |\n\n%s\n' \
    "$(matrix_frontmatter true none true)" "$1" "$matrix_w25g"
}
s25p_plan active > "$s25p_main/.bionic/docs/plans/wave-01-x.plan.md"
git -C "$s25p_main" worktree add -q "$s25p_tmp/wt-T3r" -b s25p-t3r
expect_eq "25g(r) the fixture's step-3 row really is active" "1" \
  "$(s25p_plan active | grep -c 'wt-T3r | active' | tr -d ' ')"
expect_eq "25g(r) …and the run really is at current: 3" "1" \
  "$(s25p_plan active | grep -c '^current: 3$' | tr -d ' ')"

run_hook_cwd "$(make_home)" "$s25p_main" "$s25p_tmp/wt-T3r" 'git commit -m "x"'
s25p_active_exit="$HOOK_EXIT"; s25p_active_err="$HOOK_STDERR"; s25p_active_detail="$HOOK_VSTDERR"

s25p_plan landed > "$s25p_main/.bionic/docs/plans/wave-01-x.plan.md"
run_hook_cwd "$(make_home)" "$s25p_main" "$s25p_tmp/wt-T3r" 'git commit -m "x"'
s25p_landed_exit="$HOOK_EXIT"; s25p_landed_err="$HOOK_STDERR"

if [ "$s25p_active_exit" = "$s25p_landed_exit" ] && [ "$s25p_active_err" = "$s25p_landed_err" ]; then
  ok "25g(r) C1 an ACTIVE step-3 row is judged exactly as the LANDED one is — the fork does not reach below step 4"
else
  no "25g(r) C1 an ACTIVE step-3 row is judged exactly as the LANDED one is — the fork does not reach below step 4" \
    "active exit=$s25p_active_exit stderr='$s25p_active_err' vs landed exit=$s25p_landed_exit stderr='$s25p_landed_err'"
fi

if ! grep -qF "task arms" <<<"$s25p_active_err"; then
  ok "25g(r) …so no task-arms note is printed for a row below step 4"
else
  no "25g(r) …so no task-arms note is printed for a row below step 4" \
    "expected no task-arms note; stderr='$s25p_active_err'"
fi

if ! grep -qF "'Step 4:'" <<<"$s25p_active_detail"; then
  ok "25g(r) …and the run at current: 3 is never refused for a 'Step 4:' line it cannot honestly carry"
else
  no "25g(r) …and the run at current: 3 is never refused for a 'Step 4:' line it cannot honestly carry" \
    "expected no Step 4 demand; exit=$s25p_active_exit detail='$s25p_active_detail'"
fi

# --- 25g(m): `git -C .` inside a worktree keeps its row -----------------------------------
#
# The critic's issue 2, the fail-SAFE half of the same defect: branch (1) returned the
# relative path verbatim, `_eg_wt_name` rejected it for not starting with `/`, and the row
# was lost — a Step-4 writer refused for Step-5 evidence that cannot exist yet, which is the
# exact failure REQ-2 exists to remove. A relative `-C` resolves against the shell's cwd,
# which is what branches (2) and (3) already answer, so it falls through to them.
run_hook_cwd "$(make_home)" "$s25r_main" "$s25r_tmp/wt-T3" 'git -C . commit -m "x"'
if [ "$HOOK_EXIT" -eq 0 ] && [ "$HOOK_STDERR" = "$s25r_note_T3" ]; then
  ok "25g(m) a 'git -C . commit' from inside row T3's tree is still judged at the row's step 4"
else
  no "25g(m) a 'git -C . commit' from inside row T3's tree is still judged at the row's step 4" \
    "expected allow + the note; exit=$HOOK_EXIT stderr='$HOOK_STDERR' detail='$HOOK_VSTDERR'"
fi

# --- 25g(n): a line continuation inside the word `git` is still a commit ------------------
#
# `_wall_mentions_git` (walls.sh) strips backslashes and quotes and looks for the substring
# `git`. A backslash-NEWLINE is a line continuation: the backslash goes and a newline is left
# standing between `g` and `it`, so the screen answered "provably not a git command" while
# `git_argv_has_sub` answered `commit` for the same string — and the whole evidence gate was
# skipped for a real commit. Driven from the MAIN root, where the verdict is unambiguous.
s25r_cont="g\\
it commit -m \"x\""
run_hook_cwd "$(make_home)" "$s25r_main" "$s25r_main" "$s25r_cont"
if [ "$HOOK_EXIT" -eq 2 ] && grep -q "pass=331" <<<"$HOOK_VSTDERR"; then
  ok "25g(n) a 'g\\<newline>it commit' reaches the gate and is refused like any other commit"
else
  no "25g(n) a 'g\\<newline>it commit' reaches the gate and is refused like any other commit" \
    "expected the Step-5 refusal; exit=$HOOK_EXIT stderr='$HOOK_STDERR' detail='$HOOK_VSTDERR'"
fi

# --- 25g(l): two rows naming one tree is an ambiguous register, not a race to be first ----
#
# Correctness F4. The cell is compared by BASENAME, so `wt/14-TC` and `.worktrees/14-TC`
# collide, and the arm used to take the first row in table order and say nothing — if the
# SECOND row were the real owner, and it is the one at step 6, the ahead-of-run refusal
# 25g(e) exists for would never fire. Nothing forbids the collision at write time
# (`units_validate` declines to, deliberately), so the gate declines to resolve it: judged
# at `current:`, with a note naming both rows so the register can be repaired.
s25c_tasks="## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | worktree | status |
|---|---|---|---|---|---|---|---|---|---|---|
| TA | 4 | build | the row that happens to be written first | implementor | — | 20m | REQ-2 | a.sh | wt/14-TC | active |
| TB | 6 | review | the row that may be the real owner | critic | TA | 20m | REQ-2 | b.sh | .worktrees/14-TC | pending |"

s25c_tmp=$(cd "$(mktemp -d)" && pwd -P); cleanup_dirs+=("$s25c_tmp")
s25c_main="$s25c_tmp/main"
mkdir -p "$s25c_main/.bionic/docs/plans" "$s25c_main/.bionic/docs/record/w25g"
printf 'evidence\n' > "$s25c_main/.bionic/docs/record/w25g/x.md"
git -C "$s25c_main" init -q .
git -C "$s25c_main" commit -q --allow-empty -m init
engage "$s25c_main"
printf '%s\n## SDLC State\ncurrent: 5\napproved-by: fixture 2026-09-14T00:00Z "approved"\nStep 4:\n%s\nStep 5:\n%s\n\n%s\n\n%s\n' \
  "$(matrix_frontmatter true none true)" "$s25r_step4" "$s25r_step5_red" "$s25c_tasks" "$matrix_w25g" \
  > "$s25c_main/.bionic/docs/plans/wave-01-x.plan.md"
git -C "$s25c_main" worktree add -q "$s25c_main/.worktrees/14-TC" -b s25c-tc

run_hook_cwd "$(make_home)" "$s25c_main" "$s25c_main/.worktrees/14-TC" 'git commit -m "x"'
if [ "$HOOK_EXIT" -eq 2 ] && grep -q "pass=331" <<<"$HOOK_VSTDERR" \
   && grep -q "TA" <<<"$HOOK_STDERR" && grep -q "TB" <<<"$HOOK_STDERR"; then
  ok "25g(l) two ## Tasks rows naming one tree decline to resolve, and the note names both"
else
  no "25g(l) two ## Tasks rows naming one tree decline to resolve, and the note names both" \
    "expected the Step-5 refusal plus a note naming TA and TB; exit=$HOOK_EXIT stderr='$HOOK_STDERR' detail='$HOOK_VSTDERR'"
fi

# --- 25g(o): THE WORKTREE-DERIVATION AGREEMENT (Step-6 duplication review F2, epic-23
# wave-14-tune-181 T27). lib/root.sh's project_root publishes BIONIC_WORKTREE for the cwd the
# LADDER took; lib/walls.sh's _eg_wt_name (A-T2.5's fast-path partner, walls.sh:1805-1838)
# answers the same question for the PAYLOAD's cwd, reading the tree's `.git` file directly
# rather than asking git. walls.sh's own fast path (walls.sh:2123) takes BIONIC_WORKTREE
# UNCHECKED whenever the ladder's cwd and the payload's cwd are the SAME directory — so
# nothing has ever compared the two derivations' answers on a directory where both can
# answer; every fixture in this suite stays green whichever one is wrong.
#
# OWNER: THIS SUITE, not tests/root.test.sh. root.test.sh's own header names it "the ONE
# reader for 'which project root is this cwd in'" (tests/root.test.sh:2-3) — a single-library
# charter §10 already holds to, sourcing nothing but root.sh — and pulling walls.sh's
# _eg_wt_name into it would break that charter for one arm. This suite already imports a copy
# of walls.sh for a doctored-file mutation (Section 30's H30G_LIB) and already builds the REAL
# linked worktrees (wt-T3, wt-T9, wt-stray) this arm reads, rather than fixturing a fourth
# `git worktree add` purely for this comparison.
EGWT_ROOT_LIB="${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/root.sh"
EGWT_WALLS="${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/walls.sh"

# eg_wt_root_at <cwd> -> BIONIC_WORKTREE after one project_root call from inside <cwd> —
# tests/root.test.sh's own `wt_at` idiom (§10), subshelled so no variable it sets leaks here.
eg_wt_root_at() {
  ( cd "$1" 2>/dev/null || exit 1
    HOME="$(make_home)"; export HOME
    . "$EGWT_ROOT_LIB" || exit 1
    project_root >/dev/null
    printf '%s' "${BIONIC_WORKTREE-}" )
}

# eg_wt_extract <file> -> _eg_wt_name's body, eval'd into the CURRENT shell. The extraction
# idiom tests/cross-gate-agreement.test.sh's fn_body and tests/lib/swept-marker.sh both use:
# `awk` at column zero, eval'd — never sourced whole, because walls.sh runs MODULE-LEVEL code
# at its own bottom (`_EG_WT=…`, walls.sh:2121) that wants $COMMAND/$PLAN/$BIONIC_CWD already
# set, none of which this arm has any business setting up just to reach one function.
eg_wt_extract() {
  eval "$(awk '/^_eg_wt_name\(\)/,/^\}/' "$1")"
}
eg_wt_extract "$EGWT_WALLS"
expect_true "25g(o) _eg_wt_name extracts from walls.sh (not vacuous)" \
  type -t _eg_wt_name

# THE ARM. Read from the SAME real linked worktree 25g(c) already built and already proved is
# a linked worktree (its `.git` is a file naming `/worktrees/wt-T3`) — the arrangement where
# the ladder's cwd and the payload's cwd are identical, because both derivations are asked
# about the exact same directory.
expect_eq "25g(o) root.sh's BIONIC_WORKTREE and walls.sh's _eg_wt_name name the SAME linked worktree" \
  "$(eg_wt_root_at "$s25r_tmp/wt-T3")" "$(_eg_wt_name "$s25r_tmp/wt-T3")"
expect_eq "25g(o) …and both really answer 'wt-T3' — not two empties agreeing vacuously" \
  "wt-T3" "$(eg_wt_root_at "$s25r_tmp/wt-T3")"
# THE FALSE CASE, so the pin above cannot be two derivations that always agree by returning a
# constant: for the ORDINARY main checkout both derivations answer EMPTY, not a second name.
expect_eq "25g(o) …and for the ordinary main checkout both derivations agree on EMPTY" \
  "$(eg_wt_root_at "$s25r_main")" "$(_eg_wt_name "$s25r_main")"
expect_eq "25g(o) …empty, specifically — not two non-empty values that happen to match" \
  "" "$(eg_wt_root_at "$s25r_main")"

# THE MUTATION ARM (F2's own suggested shape: "a doctored copy of one derivation"). A DOCTORED
# COPY of walls.sh — never the shipped file, the same H30G_LIB pattern Section 30 already uses
# — with _eg_wt_name's one basename expansion changed to a DIRNAME expansion: a real drift
# shape (a maintainer re-deriving "the tail of the gitdir path" reaches for the wrong
# parameter expansion) that still recognises a worktree gitdir — the `*/worktrees/*` guard is
# untouched — but names the wrong thing. `anchor` first: the needle must occur exactly once in
# walls.sh, or the `sed` below is a no-op and the mutant is a silent copy of the real file.
egwt_sed_escape() {  # <text> -> the same text, safe as either half of a sed s@..@..@ over BRE
  printf '%s' "$1" | sed -e 's/[][\/.*^$]/\\&/g'
}
EGWT_NEEDLE="printf '%s' \"\${_g##*/}\""
EGWT_MUT_NEEDLE="printf '%s' \"\${_g%/*}\""
anchor "$EGWT_WALLS" "$EGWT_NEEDLE" 1
EGWT_MUT="$s25r_tmp/25g-o-mutant-walls.sh"
sed "s@$(egwt_sed_escape "$EGWT_NEEDLE")@$(egwt_sed_escape "$EGWT_MUT_NEEDLE")@" \
  "$EGWT_WALLS" > "$EGWT_MUT"
if ! diff -q "$EGWT_WALLS" "$EGWT_MUT" > /dev/null 2>&1; then
  ok "25g(o) meta: the doctored copy differs from the real walls.sh (mutation landed)"
else
  no "25g(o) meta: the doctored copy differs from the real walls.sh (mutation landed)" \
    "the basename->dirname mutation did not apply — the sed anchor moved, so the arm below proves nothing"
fi

unset -f _eg_wt_name
eg_wt_extract "$EGWT_MUT"
expect_ne "25g(o) …and the SAME comparison calls the doctored copy a drift (basename -> dirname)" \
  "$(eg_wt_root_at "$s25r_tmp/wt-T3")" "$(_eg_wt_name "$s25r_tmp/wt-T3")"

# Restore-proof: the real extraction still agrees after the mutation proof.
unset -f _eg_wt_name
eg_wt_extract "$EGWT_WALLS"
expect_eq "25g(o) …and the real copy still agrees, restored after the mutation proof" \
  "$(eg_wt_root_at "$s25r_tmp/wt-T3")" "$(_eg_wt_name "$s25r_tmp/wt-T3")"

# --- 25g(p)-(q): ANOTHER REPOSITORY'S TREE IS OUTSIDE THIS RUN (wave-17 REQ-4, T1) --------
#
# WHAT WENT WRONG (bug 7). A commit made in a linked worktree of a DIFFERENT repository
# reaches this gate whenever the session's project is this one: `_eg_wt_name` reads the
# tree's `.git` file and answers a name, `_eg_git_wt_name` asks git and finds the common dir
# is not this repository's, and the arm declines — correctly, because this plan's register
# has nothing to say about that tree. But the decline fell THROUGH to the run's own
# `current:`, so the other repository's commit was judged by this run's Verify arm and
# refused for a floor it has no part in producing. The gate had already said out loud that it
# could not place the commit; it then judged it anyway.
#
# THE EXEMPTION IS NOT THE DECLINE. `_eg_git_wt_name` used to `return 0` with `_EG_GITWT`
# empty for every failure alike — no git, an old git, a deleted directory, a bare repository,
# a forged `.git` file, another repository's tree. Only the last of those is a tree git
# positively placed somewhere else, and only it is exempt; everything else is still a decline
# judged at `current:`. 25g(i) above is the discrimination: a forged `.git` naming row T3's
# tree gets no exemption, because git never answered for it at all.
#
# A SECOND REAL REPOSITORY, never a hand-planted file: `git worktree add` in a scratch repo
# of its own, so the common dir the arm compares is one git itself wrote.
s25x_tmp=$(cd "$(mktemp -d)" && pwd -P); cleanup_dirs+=("$s25x_tmp")
s25x_other="$s25x_tmp/other"
mkdir -p "$s25x_other"
git -C "$s25x_other" init -q .
git -C "$s25x_other" commit -q --allow-empty -m init
git -C "$s25x_other" worktree add -q "$s25x_tmp/other-wt" -b s25x-wt
s25x_wt="$s25x_tmp/other-wt"
# The expected common dir is derived from the FIXTURE's own layout — `<other repo>/.git` —
# and never from the `git rev-parse` the arm itself runs, or the pin would be the code
# agreeing with itself.
s25x_common="$s25x_other/.git"

expect_eq "25g(p) the foreign tree really is a LINKED worktree (its .git is a file)" "file" \
  "$(if [ -f "$s25x_wt/.git" ]; then echo file; elif [ -d "$s25x_wt/.git" ]; then echo dir; else echo none; fi)"
expect_contains "25g(p) …whose gitdir points into the OTHER repository, not this fixture's" \
  "$s25x_common/worktrees/other-wt" "$(cat "$s25x_wt/.git")"
expect_ne "25g(p) …and that common dir is not the bound plan's repository" \
  "$s25r_main/.git" "$s25x_common"

# --- 25g(p) / AC-4.1: the foreign tree is exempt, and the line names the boundary ---------
#
# The bound plan is the SAME `current: 5` fixture with the red Step-5 block that refuses
# 25g(d), 25g(f), 25g(i) and 25g(k2). If the exemption were not there this commit would be
# refused for `pass=331` like all of them, which is what makes the allow below a verdict
# about the repository boundary and not about a lenient fixture.
# RE-AUTHORED BY wave-19 T6 (REQ-9, D10). The jurisdiction arm now asks every commit which
# repository it lands in, before the plan is read, and a linked worktree of ANOTHER repository
# has another common dir — so it leaves there, with the one boundary line every outside
# repository gets, and never reaches the rc-4 arm whose line this pin used to carry. The
# verdict is unchanged: admitted, one line, this run's arms silent.
s25x_note="evidence-gate: $s25x_wt is outside the engaged repository ($s25r_main); the evidence gate has no plan here"
run_hook_cwd "$(make_home)" "$s25r_main" "$s25x_wt" 'git commit -m "x"'
if [ "$HOOK_EXIT" -eq 0 ] && [ "$HOOK_STDERR" = "$s25x_note" ]; then
  ok "25g(p) AC-4.1 a commit from another repository's linked worktree is exempt, and one line names the tree and the repository"
else
  no "25g(p) AC-4.1 a commit from another repository's linked worktree is exempt, and one line names the tree and the repository" \
    "expected exit 0 and exactly '$s25x_note'; exit=$HOOK_EXIT stderr='$HOOK_STDERR' detail='$HOOK_VSTDERR'"
fi

# --- 25g(q) / AC-4.3: the always-on guards are not exempt with it -------------------------
#
# THE EXEMPTION IS THE EVIDENCE GATE'S ALONE. It says this RUN's step arms do not reach that
# tree; it does not say bionic is off there. The walls that never read a plan — farm-out here,
# and the background-suite guard beside it — are folded into the SAME process as the gate, so
# an exemption spelled as an early `exit 0` out of the gate's own subshell must leave them
# standing. A foreign tree is not a corner of the machine where a suite runs on the
# orchestrator thread.
#
# ITS OWN RUNNER, AND THE REASON (fixture fidelity, per .claude/rules/test-harness.md,
# "Fixture fidelity"). Every runner above posts `{session_id, tool_input, cwd}`,
# because the evidence gate reads no more than that — but `wall_farm_out_reminder` screens on
# `.tool_name` (walls.sh) and a payload without it returns before classifying anything. The
# real PreToolUse envelope always carries it, so the omission is the fixtures' and not the
# platform's; this arm posts the field rather than widening 460 other payloads to reach one
# wall. The deny channel exits 0 and renders JSON on stdout beside its line on stderr, so both
# streams are captured here.
s25x_run_bash() {  # <project_dir> <payload cwd> <command> -> S25X_OUT, S25X_ERR, S25X_RC
  local home_dir project_dir payload_cwd command input tmp_err
  home_dir="$(make_home)"; project_dir="$1"; payload_cwd="$2"; command="$3"
  input=$(jq -n --arg c "$command" --arg cwd "$payload_cwd" --arg s "$EG_SID" \
            '{session_id: $s, hook_event_name: "PreToolUse", tool_name: "Bash",
              tool_input: {command: $c}, cwd: $cwd}')
  tmp_err=$(mktemp)
  eg_autobind "$project_dir"
  S25X_OUT=$(HOME="$home_dir" CLAUDE_PROJECT_DIR="$project_dir" CLAUDE_CODE_SESSION_ID="$EG_SID" \
    bash "$HOOK" <<< "$input" 2>"$tmp_err") && S25X_RC=0 || S25X_RC=$?
  S25X_ERR=$(cat "$tmp_err"); rm -f "$tmp_err"
}

# The control first: the SAME runner, the same tree, an ordinary command no wall classifies —
# so the two arms below cannot both be "this runner always refuses".
s25x_run_bash "$s25r_main" "$s25x_wt" 'echo hello'
if [ "$S25X_RC" -eq 0 ] && ! grep -qF "belongs in a subagent" <<<"$S25X_ERR"; then
  ok "25g(q) an ordinary command from the foreign tree is not refused by any wall"
else
  no "25g(q) an ordinary command from the foreign tree is not refused by any wall" \
    "expected silence; rc=$S25X_RC stderr='$S25X_ERR'"
fi

s25x_run_bash "$s25r_main" "$s25x_wt" 'bash tests/run.sh'
if grep -qF "belongs in a subagent" <<<"$S25X_ERR" \
   && grep -qF '"permissionDecision":"deny"' <<<"$S25X_OUT"; then
  ok "25g(q) AC-4.3 a suite command from the exempt foreign tree still meets the farm-out wall"
else
  no "25g(q) AC-4.3 a suite command from the exempt foreign tree still meets the farm-out wall" \
    "expected the farm-out deny on both streams; rc=$S25X_RC stdout='$S25X_OUT' stderr='$S25X_ERR'"
fi

# …and the override still works from there, so the arm above is the wall's verdict and not a
# property of the tree.
s25x_run_bash "$s25r_main" "$s25x_wt" 'FARM_OUT_ALLOW=1 bash tests/run.sh'
if ! grep -qF "belongs in a subagent" <<<"$S25X_ERR"; then
  ok "25g(q) …and FARM_OUT_ALLOW=1 from the same tree is sanctioned as anywhere else"
else
  no "25g(q) …and FARM_OUT_ALLOW=1 from the same tree is sanctioned as anywhere else" \
    "expected no farm-out refusal under the override; rc=$S25X_RC stderr='$S25X_ERR'"
fi


# --- 25gT: A ROW'S TREE IS JUDGED BY ITS ROW AT EITHER SCALE (wave-18 REQ-11, D3; wave-31 T24: REQ-1, D2)
#
# 25g(c)-(f) above prove the rule on a wave table. A task-scale plan carries the SAME `## Tasks`
# table now, step cell included (one ledger shape), so the fork reads the row's step at either
# scale: the second set of task arms it once ran for a table with no step column is gone, and so
# is the `current: T<n>` early exit beside it. These rows build one plan with
# tests/lib/plan-fixture.sh at `scale: task` and again at `scale: wave` and drive the same commit
# from the row's own tree: the verdict and the note are identical. A `current: T<n>` is refused
# from the tree as anywhere, as not numeric. The rows that drove the task arm's readings lane at
# `current: 6` (the old (e)-(l)) went with that arm; the readings a run owes from Step 6 are the
# numbered path's, pinned by tests/bash-walls.test.sh §EG-6.
#
# REAL LINKED WORKTREES, spelled `18-T<n>` — the shape `git worktree add` produces for a
# dispatched row (research R1 Q5).

s25t_tmp=$(cd "$(mktemp -d)" && pwd -P); cleanup_dirs+=("$s25t_tmp")
s25t_main="$s25t_tmp/main"
mkdir -p "$s25t_main/.bionic/docs/plans"
git -C "$s25t_main" init -q .
git -C "$s25t_main" commit -q --allow-empty -m init
engage "$s25t_main"
git -C "$s25t_main" worktree add -q "$s25t_main/.worktrees/18-T1" -b s25t-t1 2>/dev/null
s25t_wt="$s25t_main/.worktrees/18-T1"

# s25t_plan <current> <task|wave> -> the one plan, row T1 at step 4 owning tree 18-T1. The Step-5
# block is deliberately NOT green (331 of 332), so a main-root commit at `current: 5` is still
# refused by the run's own Verify arm — 25gT(c) is that control, and it is what makes 25gT(b) a
# discrimination rather than a fixture that admits everything.
s25t_plan() {
  local p="$s25t_tmp/gen/$2/plans/epic-99-fixture/task-01-x.plan.md"
  plan_fixture --current "$1" "$p" "$2" "$(eg_pf_row T1 implementor active 18-T1)" \
    "$(eg_pf_row T2 implementor pending)" > /dev/null || return 1
  awk '{ print } /^  branch: wave\/01-fixture$/ {
    print "- Step 5:\n  cmd: bash tests/run.sh\n  pass: 331\n  total: 332\n  output: .bionic/docs/plans/task-01-x.plan.md#step-5" }' "$p"
}
s25t_write() { s25t_plan "$@" > "$s25t_main/.bionic/docs/plans/task-01-x.plan.md"; }

expect_eq "25gT(a) the fixture's tree really is a LINKED worktree, named 18-T1 by git" \
  "18-T1" "$(basename "$(git -C "$s25t_wt" rev-parse --git-dir)")"
expect_eq "25gT(a2) …and the plan carries the row's tree and the not-green Step-5 block" "2" \
  "$(s25t_plan 5 task | /usr/bin/grep -cE '^\| T1 \| 4 \| .*\| 18-T1 \||^  pass: 331$')"

# --- 25gT(b) / AC-11.2: the tree's commit is judged at its row's step, at scale: task -------
S25T_NOTE="evidence-gate: judged at row T1's step 4 (run at current: 5)"
s25t_write 5 task
run_hook_cwd "$(make_home)" "$s25t_main" "$s25t_wt" 'git commit -m "x"'
if [ "$HOOK_EXIT" -eq 0 ] && [ "$HOOK_STDERR" = "$S25T_NOTE" ]; then
  ok "25gT(b) AC-11.2 at scale: task a commit from row T1's tree at current: 5 is judged at the row's step 4, allowed, and the note says so"
else
  no "25gT(b) AC-11.2 at scale: task a commit from row T1's tree at current: 5 is judged at the row's step 4, allowed, and the note says so" \
    "expected allow + the note; exit=$HOOK_EXIT stderr='$HOOK_STDERR' detail='$HOOK_VSTDERR'"
fi

# --- 25gT(c) / AC-11.2: the main root still meets the run's numbered-step block ------------
run_hook_with_project "$(make_home)" "$s25t_main" 'git commit -m "x"'
if [ "$HOOK_EXIT" -eq 2 ] && grep -q "pass=331" <<<"$HOOK_VSTDERR"; then
  ok "25gT(c) AC-11.2 the SAME plan still refuses a main-root commit at current: 5 for pass != total"
else
  no "25gT(c) AC-11.2 the SAME plan still refuses a main-root commit at current: 5 for pass != total" \
    "expected the Step-5 block; exit=$HOOK_EXIT stderr='$HOOK_STDERR' detail='$HOOK_VSTDERR'"
fi

# --- 25gT(b2) / REQ-1: the same table under scale: wave, the same verdict and note ---------
s25t_write 5 wave
run_hook_cwd "$(make_home)" "$s25t_main" "$s25t_wt" 'git commit -m "x"'
expect_eq "25gT(b2) REQ-1 the same commit at scale: wave gets the same exit and the same note" \
  "0 $S25T_NOTE" "$HOOK_EXIT $HOOK_STDERR"

# --- 25gT(d) / REQ-1: current: T1 from the row's tree is refused as not numeric -------------
s25t_write T1 task
run_hook_cwd "$(make_home)" "$s25t_main" "$s25t_wt" 'git commit -m "x"'
if [ "$HOOK_EXIT" -eq 2 ] && grep -qF "current: T1 is not numeric" <<<"$HOOK_VSTDERR"; then
  ok "25gT(d) REQ-1 at current: T1 a commit from the row's tree is refused, the value named as not numeric"
else
  no "25gT(d) REQ-1 at current: T1 a commit from the row's tree is refused, the value named as not numeric" \
    "expected the numeric refusal; exit=$HOOK_EXIT stderr='$HOOK_STDERR' detail='$HOOK_VSTDERR'"
fi

# ============================================================
# Section 26: the walk-artifact arm (AC-1, AC-2)
# ============================================================
#
# Walk-first verification: before any matrix row discharges, an agent must have
# narrated the real running surface into <docs-root>/record/. The arm reads
# plan frontmatter `walk:` — `exempt` makes it inert, `required` OR AN ABSENT
# KEY arms it (fail-closed, plan assumption A1: an exemption is ratified at
# Step 0, never inferred from an omission). Armed, at current: 5..9 with any
# matrix row `discharged`, three conditions must all hold:
#   (a) the Step-5 evidence carries a `walk-artifact: <path>` line;
#   (b) that path resolves to a real file under <docs-root>/record/;
#   (c) `grep -E 'AC-[0-9]'` over that file finds nothing — the walk narrates,
#       it never checklists (the artifact is written without having read the
#       acceptance criteria, and an AC identifier is the tell that it was).
# It is a durable PREFIX condition (A5): the 6..9 arm re-checks it, so the
# artifact cannot be deleted once the Verify gate is behind you.
#
# The Step-5 block is read by its own extractor at every step, not from the
# current step's BLOCK — at current: 6 the BLOCK holds Step-6 evidence.

section "Section 26: walk-artifact arm"

# $1 = a full `walk:` frontmatter line, or empty for THE KEY IS ABSENT (the
# fail-closed case). Otherwise the Section-17 shape: double wave, no
# multi_agent key, so the dispatch-ledger machinery stays out of the way.
walk_frontmatter() {
  local walk_line="${1:-}"
  printf -- '---\n'
  printf -- 'governing-skill: canonical-sdlc\ncanonical_sdlc_version: 14\n'
  printf -- 'intent: build\nrigor: double\nscale: wave\n'
  printf -- 'deploy_target: none\nuse_worktree: false\nhas_ui: true\n'
  if [ -n "$walk_line" ]; then
    printf -- '%s\n' "$walk_line"
  fi
  printf -- '---\n'
}

# $1 walk line · $2 Step-5 body (indented) · $3 matrix section.
walk_plan5() {
  printf '%s\n## SDLC State\ncurrent: 5\napproved-by: fixture 2026-09-07T00:00Z approved\nStep 5:\n%s\n\n%s\n' \
    "$(walk_frontmatter "$1")" "$2" "$3"
}

# Same, at current: 6 — the Step-5 block stays in the section so the durable
# prefix arm has something to read.
walk_plan6() {
  printf '%s\n## SDLC State\ncurrent: 6\napproved-by: fixture 2026-09-07T00:00Z approved\nStep 5:\n%s\nStep 6:\n%s\n\n%s\n' \
    "$(walk_frontmatter "$1")" "$2" "$step6_body" "$3"
}

# Writes a walk narration into the sandbox's <docs-root>/record/.
# $1 home · $2 content · $3 filename (default walk-20260801.md).
write_walk_artifact() {
  local dir="$1/.bionic/docs/record" name="${3:-walk-20260801.md}"
  mkdir -p "$dir"
  printf '%s\n' "$2" > "$dir/$name"
  echo "$dir/$name"
}

# A real walk narration: what was driven, what came back. No AC identifiers.
walk_clean_text="Started a scratch repo with the hook wired and tried an ordinary commit.
It refused, naming a missing narration file. Wrote one under record/, ran the
same commit again, and it went through. Nothing else in the tree changed."

# The same narration with a criterion identifier in it — a checklist leaking
# into the walk.
walk_dirty_text="Started a scratch repo and tried an ordinary commit.
It refused as AC-3 predicted, then passed once the file existed."

walk_step5_with_artifact="  cmd: bash test.sh
  pass: 332
  total: 332
  head: ${EG_HEAD}
  output: .bionic/docs/plans/wave-01.plan.md#step-5
  auditor: 3 rows CONFIRMED — report .bionic/docs/record/audit.md
  walk-artifact: record/walk-20260801.md"

walk_step5_no_artifact="  cmd: bash test.sh
  pass: 332
  total: 332
  head: ${EG_HEAD}
  output: .bionic/docs/plans/wave-01.plan.md#step-5
  auditor: 3 rows CONFIRMED — report .bionic/docs/record/audit.md"


walk_step5_pending="  cmd: bash test.sh
  pass: 332
  total: 332
  head: ${EG_HEAD}
  output: .bionic/docs/plans/wave-01.plan.md#step-5"

# 26a — walk: required, rows discharged, no walk-artifact line → block.
h26a=$(make_home)
write_plan "$h26a" "$(walk_plan5 'walk: required' "$walk_step5_no_artifact" "$matrix_complete")" > /dev/null
expect_block "26a walk: required + discharged rows + no walk-artifact line → block" \
  "$h26a" 'git commit -m "x"' "no 'walk-artifact:' line"

# 26b — the line, a real file under record/, no AC identifiers → allow.
h26b=$(make_home)
write_walk_artifact "$h26b" "$walk_clean_text" > /dev/null
write_plan "$h26b" "$(walk_plan5 'walk: required' "$walk_step5_with_artifact" "$matrix_complete")" > /dev/null
expect_allow "26b walk: required + clean artifact under record/ → allow" \
  "$h26b" 'git commit -m "x"'

# 26c — the artifact names an acceptance criterion → block.
h26c=$(make_home)
write_walk_artifact "$h26c" "$walk_dirty_text" > /dev/null
write_plan "$h26c" "$(walk_plan5 'walk: required' "$walk_step5_with_artifact" "$matrix_complete")" > /dev/null
expect_block "26c walk artifact containing 'AC-3' → block" \
  "$h26c" 'git commit -m "x"' "names acceptance criteria"

# 26d — walk: exempt, discharged rows, no artifact anywhere → allow (inert).
h26d=$(make_home)
write_plan "$h26d" "$(walk_plan5 'walk: exempt' "$walk_step5_no_artifact" "$matrix_complete")" > /dev/null
expect_allow "26d walk: exempt + discharged rows + no artifact → allow" \
  "$h26d" 'git commit -m "x"'

# 26e — the key is ABSENT: fail-closed, so it behaves exactly like required.
h26e=$(make_home)
write_plan "$h26e" "$(walk_plan5 '' "$walk_step5_no_artifact" "$matrix_complete")" > /dev/null
expect_block "26e walk key absent + discharged rows + no artifact → block (fail-closed)" \
  "$h26e" 'git commit -m "x"' "no 'walk-artifact:' line"

# 26f — nothing discharged yet: the arm does not fire even fail-closed.
h26f=$(make_home)
write_plan "$h26f" "$(walk_plan5 '' "$walk_step5_pending" "$walk_matrix_all_pending")" > /dev/null
expect_allow "26f current 5, all rows pending, no artifact → allow (arm does not fire)" \
  "$h26f" 'git commit -m "x"'

# 26g — durable prefix condition (A5): at current: 6 the named artifact is
# gone, so the commit blocks even though Step 5 is behind us.
h26g=$(make_home)
h26g_art=$(write_walk_artifact "$h26g" "$walk_clean_text")
write_plan "$h26g" "$(walk_plan6 'walk: required' "$walk_step5_with_artifact" "$matrix_complete")" > /dev/null
rm -f "$h26g_art"
expect_block "26g current 6 with the walk artifact deleted → block (durable prefix)" \
  "$h26g" 'git commit -m "x"' "no file exists at"

# 26g-ok — the same plan with the artifact still in place → allow, so the
# block above is the deletion and not the step.
h26g2=$(make_home)
write_walk_artifact "$h26g2" "$walk_clean_text" > /dev/null
write_plan "$h26g2" "$(walk_plan6 'walk: required' "$walk_step5_with_artifact" "$matrix_complete")" > /dev/null

# 26h — a project-relative spelling of the same file resolves too.
h26h=$(make_home)
write_walk_artifact "$h26h" "$walk_clean_text" > /dev/null
write_plan "$h26h" "$(walk_plan5 'walk: required' "  cmd: bash test.sh
  pass: 332
  total: 332
  head: ${EG_HEAD}
  output: .bionic/docs/plans/wave-01.plan.md#step-5
  auditor: 3 rows CONFIRMED — report .bionic/docs/record/audit.md
  walk-artifact: .bionic/docs/record/walk-20260801.md" "$matrix_complete")" > /dev/null
expect_allow "26h project-relative walk-artifact path under record/ → allow" \
  "$h26h" 'git commit -m "x"'

# 26i — a path that climbs out of record/ is refused before any file test.
h26i=$(make_home)
printf 'walk narration living outside the record\n' > "$h26i/.bionic/docs/escaped.md"
write_plan "$h26i" "$(walk_plan5 'walk: required' "  cmd: bash test.sh
  pass: 332
  total: 332
  head: ${EG_HEAD}
  output: .bionic/docs/plans/wave-01.plan.md#step-5
  auditor: 3 rows CONFIRMED — report .bionic/docs/record/audit.md
  walk-artifact: record/../escaped.md" "$matrix_complete")" > /dev/null
expect_block "26i walk-artifact climbing out of record/ → block" \
  "$h26i" 'git commit -m "x"' "does not resolve under"

# 26j — a real file that simply lives somewhere else is refused the same way.
h26j=$(make_home)
printf 'walk narration in the wrong place\n' > "$h26j/.bionic/docs/plans/walk.md"
write_plan "$h26j" "$(walk_plan5 'walk: required' "  cmd: bash test.sh
  pass: 332
  total: 332
  head: ${EG_HEAD}
  output: .bionic/docs/plans/wave-01.plan.md#step-5
  auditor: 3 rows CONFIRMED — report .bionic/docs/record/audit.md
  walk-artifact: .bionic/docs/plans/walk.md" "$matrix_complete")" > /dev/null
expect_block "26j walk-artifact outside record/ → block" \
  "$h26j" 'git commit -m "x"' "does not resolve under"

# 26k — a zero-byte file at the named path is not a walk: existence alone is
# not enough, the artifact must carry content. The message must distinguish
# this case ("file is empty at") from the missing-file case above ("no file
# exists at").
h26k=$(make_home)
mkdir -p "$h26k/.bionic/docs/record"
touch "$h26k/.bionic/docs/record/walk-20260801.md"
write_plan "$h26k" "$(walk_plan5 'walk: required' "$walk_step5_with_artifact" "$matrix_complete")" > /dev/null
expect_block "26k zero-byte walk artifact → block (existence alone is not enough)" \
  "$h26k" 'git commit -m "x"' "file is empty at"

# 26l — an OFF-ENUM walk value arms the arm exactly like `required`. walk_mode()
# treats everything that is not the literal `exempt` as armed (A1/A7: a typo
# must never buy a bypass), and the enum itself is the governing-skill hook's
# job at write time. That split is only sound if the gate really does arm here,
# which is what this pins — independently of the other hook's coverage.
h26l=$(make_home)
write_plan "$h26l" "$(walk_plan5 'walk: bogus' "$walk_step5_no_artifact" "$matrix_complete")" > /dev/null
expect_block "26l off-enum 'walk: bogus' + discharged rows + no artifact → block (arms like required)" \
  "$h26l" 'git commit -m "x"' "no 'walk-artifact:' line"

# 26m/26n/26o — packed-line extraction (bugfix A17). Sibling extractors
# elsewhere in this hook already truncate at ';' to tolerate a Step-5 line
# with more fields packed after the value; the raw walk-artifact extraction
# was the outlier, greedy to end-of-line. A Step-5 line of the shape
# `walk-artifact: record/x.md; cmd: ...` swallowed the semicolon-joined
# remainder as part of the "path", which never resolved even though the real
# file exists.

walk_step5_packed_ok="  cmd: bash test.sh
  pass: 332
  total: 332
  head: ${EG_HEAD}
  output: .bionic/docs/plans/wave-01.plan.md#step-5
  auditor: 3 rows CONFIRMED — report .bionic/docs/record/audit.md
  walk-artifact: record/walk-20260801.md; cmd: bash test.sh; pass: 332; total: 332"

walk_step5_packed_bad="  cmd: bash test.sh
  pass: 332
  total: 332
  head: ${EG_HEAD}
  output: .bionic/docs/plans/wave-01.plan.md#step-5
  auditor: 3 rows CONFIRMED — report .bionic/docs/record/audit.md
  walk-artifact: record/../escaped.md; cmd: bash test.sh; pass: 332; total: 332"

# 26m — a packed Step-5 line (fields after the path, semicolon-joined) naming
# a real, clean file under record/ → allow.
h26m=$(make_home)
write_walk_artifact "$h26m" "$walk_clean_text" > /dev/null
write_plan "$h26m" "$(walk_plan5 'walk: required' "$walk_step5_packed_ok" "$matrix_complete")" > /dev/null
expect_allow "26m packed walk-artifact line (fields after the path) → allow" \
  "$h26m" 'git commit -m "x"'

# 26n — regression pin: the dedicated continuation-line shape (no packed
# fields) still passes after the truncate-at-';' fix.
h26n=$(make_home)
write_walk_artifact "$h26n" "$walk_clean_text" > /dev/null
write_plan "$h26n" "$(walk_plan5 'walk: required' "$walk_step5_with_artifact" "$matrix_complete")" > /dev/null
expect_allow "26n dedicated continuation-line walk-artifact (unpacked) → allow" \
  "$h26n" 'git commit -m "x"'

# 26o — a packed line whose truncated value is STILL a bad path (climbs out
# of record/ via '..') must still block. The ';' cut must not accidentally
# salvage a genuinely bad path.
h26o=$(make_home)
printf 'walk narration living outside the record\n' > "$h26o/.bionic/docs/escaped.md"
write_plan "$h26o" "$(walk_plan5 'walk: required' "$walk_step5_packed_bad" "$matrix_complete")" > /dev/null
expect_block "26o packed walk-artifact line with a bad truncated path → block" \
  "$h26o" 'git commit -m "x"' "does not resolve under"

# ============================================================
# Section 27: the provenance arm (AC-5)
# ============================================================
#
# A citation of the literal form `provenance: implementation` is circular —
# it names the change itself as the source of its own requirement. The arm
# blocks on that exact value (whitespace-trimmed) inside any AC block, at
# whatever tier/status the row carries. A missing `provenance:` line does NOT
# block (plan assumption A4 — presence is a W+1 candidate, not this wave's).
# A value that merely CONTAINS the word ("implementation-first rewrite of
# spec §3") is a real citation and must not trip the whole-value test.
# validate_matrix() is the single call site for both the current: 5 Verify
# gate and the current: 6..9 prefix re-validation (dispatch() line ~1506), so
# one case at current: 6 confirms the arm fires there without a duplicate
# implementation.

section "Section 27: provenance arm"

# Builds a one-row T1 matrix (discharged, auditor CONFIRMED) whose AC-1 block
# carries tier-run + readback (satisfying T1's own evidence requirement) plus
# an optional `provenance:` line. $1 = the provenance value to write after
# the colon, or empty/omitted for no `provenance:` line at all.
prov_matrix() {
  local prov_line=""
  if [ -n "${1:-}" ]; then
    prov_line="
  provenance: $1"
  fi
  printf '## Verification Matrix\n\nstack-health: n/a: no long-running serve\n\n| AC | tier | status | evidence | auditor |\n|---|---|---|---|---|\n| AC-1 | T1 | discharged | see AC-1 | CONFIRMED |\n\nAC-1:\n  tier-run: bash test.sh — unit suite\n  fails-when: the planted defect this eval must go red on
  evidence: record/generic-evidence.md\n  readback: 332/332 asserted%s\n' "$prov_line"
}

# 27a — the literal value blocks.
h27a=$(make_home)
write_plan "$h27a" "$(plan 5 "$step5_base" "$(prov_matrix "implementation")")" > /dev/null
expect_block "27a provenance: implementation → block" \
  "$h27a" 'git commit -m "x"' "provenance: implementation"

# 27b — a real citation allows.
h27b=$(make_home)
write_plan "$h27b" "$(plan 5 "$step5_base" "$(prov_matrix "spec §3")")" > /dev/null
expect_allow "27b provenance: spec §3 → allow" \
  "$h27b" 'git commit -m "x"'

# 27c — no provenance line at all does not block (A4: presence isn't required).
h27c=$(make_home)
write_plan "$h27c" "$(plan 5 "$step5_base" "$(prov_matrix "")")" > /dev/null
expect_allow "27c no provenance line at all → allow" \
  "$h27c" 'git commit -m "x"'

# 27d — a value containing the word, not equal to it, must not trip the
# whole-value test.
h27d=$(make_home)
write_plan "$h27d" "$(plan 5 "$step5_base" "$(prov_matrix "implementation-first rewrite of spec §3")")" > /dev/null
expect_allow "27d provenance substring 'implementation-first ...' → allow (no false trigger)" \
  "$h27d" 'git commit -m "x"'

# 27e — surrounding whitespace around the value is trimmed before the
# equality test, so it still blocks.
h27e=$(make_home)
write_plan "$h27e" "$(plan 5 "$step5_base" "$(prov_matrix "  implementation  ")")" > /dev/null
expect_block "27e provenance:   implementation   (padded) → block" \
  "$h27e" 'git commit -m "x"' "provenance: implementation"

# 27f — the same arm fires at current: 6, the dispatch() prefix
# re-validation, confirming validate_matrix()'s single call site covers both
# without a second implementation.
h27f=$(make_home)
write_plan "$h27f" "$(plan 6 "$step6_body" "$(prov_matrix "implementation")")" > /dev/null
expect_block "27f provenance: implementation at current: 6 (prefix re-validation) → block" \
  "$h27f" 'git commit -m "x"' "provenance: implementation"

# 27g — the compare is case-insensitive, matching the placeholder and
# live-tier convention in the same loop (trim already applies): a capitalized
# value is the same circular citation as the lowercase one.
h27g=$(make_home)
write_plan "$h27g" "$(plan 5 "$step5_base" "$(prov_matrix "Implementation")")" > /dev/null
expect_block "27g provenance: Implementation (capitalized) → block (case-insensitive)" \
  "$h27g" 'git commit -m "x"' "provenance: implementation"

# 27h — pinned control: the case-fold must not widen the match past the
# whole-value test — a real citation prefixed by "the" still allows.
h27h=$(make_home)
write_plan "$h27h" "$(plan 5 "$step5_base" "$(prov_matrix "the implementation")")" > /dev/null
expect_allow "27h provenance: the implementation → allow (pinned control)" \
  "$h27h" 'git commit -m "x"'

# 27i — pinned control: a substring citation still allows after the
# case-fold.
h27i=$(make_home)
write_plan "$h27i" "$(plan 5 "$step5_base" "$(prov_matrix "implementation-first rewrite of spec section 3")")" > /dev/null
expect_allow "27i provenance: implementation-first rewrite of spec section 3 → allow (pinned control)" \
  "$h27i" 'git commit -m "x"'

# --- step scope of the arm (PINNED, not merely observed) -------------------
#
# validate_matrix() runs at the Verify gate (current: 5) and as the prefix
# re-check for current: 6..9, and nowhere else — so the provenance arm is
# SILENT at the authoring steps 2/3/4, where the citation is written and the
# matrix is locked. 27j/27k pin that as the INTENDED shipped scope: the
# provenance rule is a commit-gate property from Verify onward, and a plan
# carrying the barred literal commits freely while it is still being authored.
# This is deliberate rather than accidental — enforcing it at authoring time
# means the governing-skill hook's Write gate, which is a deferred candidate
# and not this wave's. If that ever lands, these two cases are the ones that
# must be rewritten first, and the rewrite is the signal that the scope moved.
# Pointer body: steps 1-4 exit before any matrix validation, so the block only
# has to be non-empty and non-placeholder.
prov_pointer_body="  plan-doc: .bionic/docs/plans/wave-01.plan.md"

# 27j — the barred literal at current: 3 commits clean.
h27j=$(make_home)
write_plan "$h27j" "$(plan 3 "$prov_pointer_body" "$(prov_matrix "implementation")")" > /dev/null

# 27k — and at current: 4, the last step before the gate.
h27k=$(make_home)
write_plan "$h27k" "$(plan 4 "$prov_pointer_body" "$(prov_matrix "implementation")")" > /dev/null

# ============================================================
# Section 28: matrix_block tolerates a markdown list leader
# ============================================================
#
# matrix_block() anchors each AC evidence block with index($0, "AC-n:")==1, so a
# header written as a markdown list item (`- AC-1:`) yielded an EMPTY block, and
# every behavior that reads that block went silent at once: the provenance arm
# saw no citation, the per-tier key loop saw no keys (blocking an otherwise
# conformant plan), the `waiver:` exemption never found its token, and the
# post-Verify CONFIRMED check lost that same exemption. Four behaviors, one
# extractor — so the list leader was a whole-contract bypass, not one arm's bug.
#
# The leader is stripped from a COPY of the line before the index test, which
# leaves two invariants intact: the block TERMINATOR (`/^[^[:space:]]/`) still
# reads the raw line, so a following list item still ends the previous block;
# and AC-1 still does not match the AC-11 block (28f). The strip accepts the
# three CommonMark bullet markers (`-`, `*`, `+`) plus at least one space, flush
# left — 28g/28h pin the two boundaries that stay invisible.

section "Section 28: matrix_block list-leader tolerance"

# T1's own evidence keys, satisfying the per-tier requirement.
leader_t1_keys="  tier-run: bash test.sh — unit suite
  fails-when: the planted defect this eval must go red on
  evidence: record/generic-evidence.md
  readback: 332/332 asserted"

# $1 = block-header leader ("" flush-left, "- ", "* ", …)
# $2 = the AC-1 block body (indented lines)
# $3 = the auditor cell value (default CONFIRMED; empty exercises the
#      post-Verify CONFIRMED check).
leader_matrix() {
  local leader="${1:-}" body="$2" aud="${3-CONFIRMED}"
  printf '## Verification Matrix\n\nstack-health: n/a: no long-running serve\n\n| AC | tier | status | evidence | auditor |\n|---|---|---|---|---|\n| AC-1 | T1 | discharged | see AC-1 | %s |\n\n%sAC-1:\n%s\n' \
    "$aud" "$leader" "$body"
}

# 28a — provenance arm: a list-leader block carrying the barred literal blocks
# exactly as a flush-left one does (27a is the flush-left twin).
h28a=$(make_home)
write_plan "$h28a" "$(plan 5 "$step5_base" "$(leader_matrix '- ' "$leader_t1_keys
  provenance: implementation")")" > /dev/null
expect_block "28a '- AC-1:' block with provenance: implementation → block" \
  "$h28a" 'git commit -m "x"' "provenance: implementation"

# 28b — per-tier keys: a list-leader block whose T1 evidence is complete must
# PASS. Before the strip this blocked on a missing key that was sitting in the
# plan the whole time — the shape that made every per-tier check vacuous.
h28b=$(make_home)
write_plan "$h28b" "$(plan 6 "$step6_body" "$(leader_matrix '- ' "$leader_t1_keys")")" > /dev/null

# 28c — waiver-token exemption: the `waiver:` entry lives in the AC block (not
# the evidence cell), so reading the block is the only way to find it. With the
# block visible the row is exempt from the per-tier keys and commits clean.
h28c=$(make_home)
write_plan "$h28c" "$(plan 5 "$step5_base" "$(leader_matrix '- ' "  waiver: dana 2026-08-01 env stale
  fails-when: the planted defect this eval must go red on
  evidence: record/generic-evidence.md")")" > /dev/null
# The `fails-when:` line is not part of 28c's subject — the block-side waiver is. It is here
# because that key is unconditional from `current: 4` (epic-22 K2): a waiver dissolves the
# obligation to RUN an eval, never the obligation to have designed one, so a waived row still
# names its failure. 37l pins that reading directly.
expect_allow "28c '- AC-1:' block whose only evidence entry is 'waiver:' → allow (block-side exemption found)" \
  "$h28c" 'git commit -m "x"'

# 28d — post-Verify CONFIRMED check: complete keys, NO waiver anywhere, auditor
# cell empty, at current: 6. The block must be visible for the gate to reach
# this check at all; the expected message is what discriminates, since the same
# plan blocked before the strip for the wrong reason (a missing evidence key).
h28d=$(make_home)
write_plan "$h28d" "$(plan 6 "$step6_body" "$(leader_matrix '- ' "$leader_t1_keys" '')")" > /dev/null
expect_block "28d '- AC-1:' block, keys complete, auditor cell empty at current: 6 → block on the verdict" \
  "$h28d" 'git commit -m "x"' "auditor verdict is 'empty'"

# 28e — the other bullet markers are the same list. An author reaching for `*`
# must not get a silently different parse from one reaching for `-`.
h28e=$(make_home)
write_plan "$h28e" "$(plan 5 "$step5_base" "$(leader_matrix '* ' "$leader_t1_keys
  provenance: implementation")")" > /dev/null
expect_block "28e '* AC-1:' block with provenance: implementation → block" \
  "$h28e" 'git commit -m "x"' "provenance: implementation"

# 28f — the AC-1/AC-11 disambiguation index() bought must survive the strip.
# AC-11's block comes FIRST and is the only one carrying the barred literal; if
# stripping had let AC-1 match the `- AC-11:` header, AC-1 would inherit that
# citation and the block would name row 'AC-1' instead.
h28f=$(make_home)
write_plan "$h28f" "$(plan 5 "$step5_base" "## Verification Matrix

stack-health: n/a: no long-running serve

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1 | T1 | discharged | see AC-1 | CONFIRMED |
| AC-11 | T1 | discharged | see AC-11 | CONFIRMED |

- AC-11:
  fails-when: the planted defect this eval must go red on
  evidence: record/generic-evidence.md
$leader_t1_keys
  provenance: implementation
- AC-1:
  fails-when: the planted defect this eval must go red on
  evidence: record/generic-evidence.md
$leader_t1_keys
  provenance: spec §3")" > /dev/null
expect_block "28f '- AC-11:' before '- AC-1:' → AC-1 keeps its own block (AC-11 is the row that blocks)" \
  "$h28f" 'git commit -m "x"' "row 'AC-11' cites"

# 28g — pinned boundary: `-AC-1:` with no space after the dash is not a list
# item and stays invisible, so its keys are not found. The strip requires a
# separator; it is not a general "ignore leading punctuation".
h28g=$(make_home)
write_plan "$h28g" "$(plan 5 "$step5_base" "$(leader_matrix '-' "$leader_t1_keys")")" > /dev/null
expect_block "28g '-AC-1:' (no space) → block (pinned boundary: not a list item)" \
  "$h28g" 'git commit -m "x"' "missing evidence key"

# 28h — pinned boundary: an INDENTED list header stays invisible too. The block
# terminator is `/^[^[:space:]]/`, so an indented header would never end the
# preceding block; keeping the strip flush-left preserves that invariant.
h28h=$(make_home)
write_plan "$h28h" "$(plan 5 "$step5_base" "$(leader_matrix '  - ' "$leader_t1_keys")")" > /dev/null
expect_block "28h '  - AC-1:' (indented) → block (pinned boundary: strip is flush-left only)" \
  "$h28h" 'git commit -m "x"' "missing evidence key"


section "§UNFILLED: the stubs Step 3 renders carry 'pending', which the gate accepts before the Verify gate and refuses at it — stack-health: and walk-artifact: included (wave-30 T14; REQ-6 AC-6.1; D9, Δ12a)"

# fails-when: a plan rendered at Step 3 is refused at current: 3 or 4 on its 'pending' stubs, or a
# 'pending' stub (a tier key, stack-health:, walk-artifact:) passes the Verify gate once no row is
# still pending, or at current: 6.
#
# THE TOKEN IS 'pending' (Δ12a): already in is_placeholder_value's set, so a tier key reading
# 'pending' was refused wherever the key loop judges it; what T14 adds is the two matrix-level
# lines, which the key loop never reads. stack-health: lost its exemption (any non-empty value but
# a bare n/a used to pass), and a walk-artifact: line in the matrix — the stub the render verb
# writes beside it — is held to the same rule. Both bite exactly where a tier key does: at
# current: 5 once no row is pending or blocked (the mid-walk relaxation the key loop has), and at
# every step after. FIXTURE FIDELITY: the matrix below is the shape `session-poker.sh
# matrix-render` writes (session-poker-4 §MATRIX-RENDER pins the writer); the gate is the real one.

# $1 stack-health value · $2 walk-artifact value ("" = no line) · $3 row status · $4 auditor
# cell · $5 keys: pending | filled
unf_matrix() {
  local sh="$1" wa="$2" st="$3" aud="$4" keys="$5" ev
  if [ "$keys" = pending ]; then ev=pending; else ev=record/generic-evidence.md; fi
  printf '## Verification Matrix\n\nstack-health: %s\n' "$sh"
  [ -z "$wa" ] || printf 'walk-artifact: %s\n' "$wa"
  printf '\n| AC | tier | status | evidence | auditor |\n|---|---|---|---|---|\n'
  printf '| AC-1 | T2 | %s | see AC-1 | %s |\n| AC-2 | T1 | %s | see AC-2 | %s |\n\n' "$st" "$aud" "$st" "$aud"
  printf 'AC-1:\n  provenance: spec section 1\n  fails-when: the planted defect this eval must go red on\n'
  printf '  eval: T2 — bash test.sh\n  task: T1\n  evidence: %s\n' "$ev"
  printf 'AC-2:\n  provenance: spec section 2\n  fails-when: the second planted defect\n'
  printf '  eval: T1 — bash test.sh\n  task: pending\n  evidence: %s\n' "$ev"
}
unf_body="  plan-doc: .bionic/docs/plans/wave-01.plan.md"

# --- before the Verify gate: the rendered stubs commit ---------------------------------------
hUF1=$(make_home)
write_plan "$hUF1" "$(plan 3 "$unf_body" "$(unf_matrix pending pending pending '' pending)")" > /dev/null
expect_allow "UF-1 the rendered stubs (every key, stack-health: and walk-artifact: 'pending') at current: 3 → allow" \
  "$hUF1" 'git commit -m "x"'
hUF2=$(make_home)
write_plan "$hUF2" "$(plan 4 "$unf_body" "$(unf_matrix pending pending pending '' pending)")" > /dev/null
expect_allow "UF-2 …and at current: 4 → allow" "$hUF2" 'git commit -m "x"'
hUF3=$(make_home)
write_plan "$hUF3" "$(plan 5 "$step5_base" "$(unf_matrix pending pending pending '' pending)")" > /dev/null
expect_allow "UF-3 …and at current: 5 while every row is still pending (the mid-walk relaxation) → allow" \
  "$hUF3" 'git commit -m "x"'

# --- at the Verify gate: each stub is refused, by name, beside its filled twin -------------------
hUF4=$(make_home)
write_plan "$hUF4" "$(plan 5 "$step5_base" "$(unf_matrix 'restarts 0 → 0' '' discharged CONFIRMED pending)")" > /dev/null
expect_block "UF-4 a discharged row whose evidence: reads 'pending' at current: 5 → block, naming the key" \
  "$hUF4" 'git commit -m "x"' "evidence key 'evidence' is a placeholder"
hUF4b=$(make_home)
write_plan "$hUF4b" "$(plan 5 "$step5_base" "$(unf_matrix 'restarts 0 → 0' '' discharged CONFIRMED filled)")" > /dev/null
expect_allow "UF-4b …the same matrix with the keys filled → allow (the control)" "$hUF4b" 'git commit -m "x"'
hUF5=$(make_home)
write_plan "$hUF5" "$(plan 5 "$step5_base" "$(unf_matrix pending '' discharged CONFIRMED filled)")" > /dev/null
expect_block "UF-5 stack-health: pending at current: 5, no row pending → block (the exemption is gone)" \
  "$hUF5" 'git commit -m "x"' "'stack-health:' is still a placeholder"
hUF5b=$(make_home)
write_plan "$hUF5b" "$(plan 5 "$step5_base" "$(unf_matrix TBD '' discharged CONFIRMED filled)")" > /dev/null
expect_block "UF-5b …any placeholder token, 'TBD' as well → block" \
  "$hUF5b" 'git commit -m "x"' "'stack-health:' is still a placeholder"
hUF6=$(make_home)
write_plan "$hUF6" "$(plan 5 "$step5_base" "$(unf_matrix 'restarts 0 → 0' pending discharged CONFIRMED filled)")" > /dev/null
expect_block "UF-6 walk-artifact: pending in the matrix at current: 5, no row pending → block" \
  "$hUF6" 'git commit -m "x"' "'walk-artifact:' is still a placeholder"
hUF6b=$(make_home)
write_plan "$hUF6b" "$(plan 5 "$step5_base" "$(unf_matrix 'restarts 0 → 0' record/walk.md discharged CONFIRMED filled)")" > /dev/null
expect_allow "UF-6b …the same line naming the walk record → allow (the control)" "$hUF6b" 'git commit -m "x"'

# --- after the Verify gate: no relaxation ------------------------------------------------------
hUF7=$(make_home)
write_plan "$hUF7" "$(plan 6 "$step6_body" "$(unf_matrix pending '' discharged CONFIRMED filled)")" > /dev/null
expect_block "UF-7 stack-health: pending at current: 6 → block" \
  "$hUF7" 'git commit -m "x"' "'stack-health:' is still a placeholder"
hUF7b=$(make_home)
write_plan "$hUF7b" "$(plan 6 "$step6_body" "$(unf_matrix 'restarts 0 → 0' '' discharged CONFIRMED filled)")" > /dev/null
expect_allow "UF-7b …the same plan with stack-health filled → allow (the control)" "$hUF7b" 'git commit -m "x"'

# ============================================================
# §KEYS: the matrix owes one pointer per row (wave-31 T6; REQ-5 AC-5.1, AC-5.2, D5)
# ============================================================
section "§KEYS: every tier owes 'evidence:' and a T4 row 'user-confirmed:' too; a pointer that names no real file still blocks (wave-31 T6; REQ-5)"

# fails-when: a T3 block carrying only 'evidence:' is refused at the Verify gate, or a block with no
# real 'evidence:' pointer passes it, or keys_for_tier still names a key beyond the two it owes.
#
# $1 tier · $2 the block's key lines after fails-when (each already indented, newline-joined)
kx_matrix() {
  printf '## Verification Matrix\n\nstack-health: n/a: no long-running serve\n\n'
  printf '| AC | tier | status | evidence | auditor |\n|---|---|---|---|---|\n'
  printf '| AC-1 | %s | discharged | see AC-1 | CONFIRMED |\n\n' "$1"
  printf 'AC-1:\n  fails-when: the planted defect this eval must go red on\n%s\n' "$2"
}
KX_EV="  evidence: record/generic-evidence.md"

# (i) the case the old list refused: a T3 block carrying 'evidence:' and nothing else.
hKX1=$(make_home)
write_plan "$hKX1" "$(plan 5 "$step5_base" "$(kx_matrix T3 "$KX_EV")")" > /dev/null
expect_allow "KX-1 a T3 block carrying only 'evidence:' (a real record file) at current: 5 → allow" \
  "$hKX1" 'git commit -m "x"'
for kx_t in T0 T1 T2; do
  hKXt=$(make_home)
  write_plan "$hKXt" "$(plan 5 "$step5_base" "$(kx_matrix "$kx_t" "$KX_EV")")" > /dev/null
  expect_allow "KX-1$kx_t …and a $kx_t block carrying only 'evidence:' → allow" "$hKXt" 'git commit -m "x"'
done
# A block written to the old list keeps working: a key the gate no longer names is not refused.
hKX1b=$(make_home)
write_plan "$hKX1b" "$(plan 5 "$step5_base" "$(kx_matrix T3 "$KX_EV
  tier-run: bash test.sh — unit
  fresh: origin A rebuilt token-9f3a
  cold-client: fresh incognito profile
  contact: clicked open — panel closed → open
  readback: panel.visible === true")")" > /dev/null
expect_allow "KX-1b a T3 block that still carries the five retired keys beside 'evidence:' → allow (an extra key is not refused)" \
  "$hKX1b" 'git commit -m "x"'

# (ii) the pointer is the one thing the row owes.
hKX2=$(make_home)
write_plan "$hKX2" "$(plan 5 "$step5_base" "$(kx_matrix T2 "  tier-run: bash test.sh — unit
  readback: 40/40 asserted
  fixture-fidelity: the fixture plants the defect")")" > /dev/null
expect_block "KX-2 a T2 block with no 'evidence:' (every retired key present) → block, naming the key" \
  "$hKX2" 'git commit -m "x"' "missing evidence key 'evidence'"
hKX2b=$(make_home)
write_plan "$hKX2b" "$(plan 5 "$step5_base" "$(kx_matrix T3 "  evidence: record/does-not-exist.md")")" > /dev/null
expect_block "KX-2b a T3 block whose pointer names no real file → block" \
  "$hKX2b" 'git commit -m "x"' "names no real file"
hKX2c=$(make_home)
write_plan "$hKX2c" "$(plan 5 "$step5_base" "$(kx_matrix T1 "  evidence: pending")")" > /dev/null
expect_block "KX-2c a T1 block whose pointer is still the 'pending' stub → block" \
  "$hKX2c" 'git commit -m "x"' "placeholder"

# T4 owes the user's own confirmation as well as the pointer.
hKX3=$(make_home)
write_plan "$hKX3" "$(plan 5 "$step5_base" "$(kx_matrix T4 "$KX_EV
  user-confirmed: chris 2026-10-09 opened it and read the wall")")" > /dev/null
expect_allow "KX-3 a T4 block with 'evidence:' and 'user-confirmed:' → allow" "$hKX3" 'git commit -m "x"'
hKX3b=$(make_home)
write_plan "$hKX3b" "$(plan 5 "$step5_base" "$(kx_matrix T4 "$KX_EV")")" > /dev/null
expect_block "KX-3b …a T4 block with 'evidence:' alone → block, naming 'user-confirmed'" \
  "$hKX3b" 'git commit -m "x"' "missing evidence key 'user-confirmed'"

# (iii) the list matrix-render writes from: the same function, read the way the verb reads it.
# session-poker-4 §MATRIX-RENDER drives the verb itself and pins the rendered blocks.
kx_keys() { ( . "${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/walls.sh" >/dev/null 2>&1; keys_for_tier "$1" ); }
expect_eq "KX-4 keys_for_tier reads 'evidence' for T0 to T3 (positive, before the absence row)" \
  "evidence|evidence|evidence|evidence" "$(printf '%s|%s|%s|%s' "$(kx_keys T0)" "$(kx_keys T1)" "$(kx_keys T2)" "$(kx_keys T3)")"
expect_eq "KX-4b …and 'user-confirmed evidence' for T4" "user-confirmed evidence" "$(kx_keys T4)"
expect_eq "KX-4c …so no tier names a retired key (0 matches over all five)" "0" \
  "$(for kx_t in T0 T1 T2 T3 T4; do kx_keys "$kx_t"; done | /usr/bin/grep -c 'tier-run\|readback\|fixture-fidelity\|fresh\|cold-client\|contact' || true)"

# ============================================================
# §REGRESSION-NO: the regression is a Step-0 setting, and the Step-5 arm reads it (wave-31 T27; REQ-12 AC-12.2; D4)
# ============================================================
section "§REGRESSION-NO: at 'regression: no' the Step-5 block carries 'regression: no (Step 0, <user>) — <where it runs>' in place of cmd/pass/total/output/head; at yes, or with the key absent, the floor is owed (wave-31 T27; REQ-12 AC-12.2; D4)"

# fails-when: a `no` plan is blocked at Step 5 for a missing floor, or a `yes` plan passes without one.
#
# THE KEY IS THE PLAN'S FRONTMATTER `regression: yes|no`, written at Step 0 by `session-poker.sh
# regression` (session-poker-4 §REGRESSION-SET). AN ABSENT KEY READS `yes`, fail-closed as an absent
# `walk:` reads `required` (Section 26e): every plan written before the key keeps being asked for
# `pass == total`. Only the exact value `no` relaxes the arm. `regression-override:` is the record of
# who chose against the scale default; its presence changes nothing here and it is never parsed.
#
# The fixture is Section 26's: double wave, a complete matrix, `walk: exempt` so the walk arm stays
# out of the way, and the auditor pointer the finished matrix owes at double.
# $1 the frontmatter lines after `walk: exempt` (newline-joined; empty for none) · $2 the Step-5 body.
rn_plan() { walk_plan5 "walk: exempt${1:+
$1}" "$2" "$matrix_complete"; }
RN_AUD="  auditor: 3 rows CONFIRMED — report .bionic/docs/record/audit.md"
RN_LINE="  regression: no (Step 0, Chris) — CI on main runs the whole suite on merge"
RN_FLOOR="  cmd: bash test.sh
  pass: 332
  total: 332
  head: ${EG_HEAD}
  output: .bionic/docs/plans/wave-01.plan.md#step-5"
RN_RED="  cmd: bash test.sh
  pass: 331
  total: 332
  head: ${EG_HEAD}
  output: .bionic/docs/plans/wave-01.plan.md#step-5"

# (i) AC-12.2's three cases.
hRN1=$(make_home)
write_plan "$hRN1" "$(rn_plan 'regression: no' "$RN_LINE
$RN_AUD")" > /dev/null
expect_allow "RN-1 AC-12.2 regression: no + the Step-0 line, no cmd/pass/total/output/head → admitted at current: 5 with no floor" \
  "$hRN1" 'git commit -m "x"'
hRN2=$(make_home)
write_plan "$hRN2" "$(rn_plan 'regression: no' "$RN_AUD")" > /dev/null
expect_block "RN-2 AC-12.2 regression: no, the same block without the line → blocked, naming the line to add" \
  "$hRN2" 'git commit -m "x"' "regression: no (Step 0, <user>) — <where it runs>"
hRN3=$(make_home)
write_plan "$hRN3" "$(rn_plan 'regression: yes' "$RN_LINE
$RN_AUD")" > /dev/null
expect_block "RN-3 AC-12.2 regression: yes without a floor (the line instead of cmd/pass/total) → blocked for the fields" \
  "$hRN3" 'git commit -m "x"' "missing required field(s): cmd pass total output"
hRN3b=$(make_home)
write_plan "$hRN3b" "$(rn_plan 'regression: yes' "$RN_RED
$RN_LINE
$RN_AUD")" > /dev/null
expect_block "RN-3b regression: yes with pass != total → blocked: the line does not stand in for a green run" \
  "$hRN3b" 'git commit -m "x"' "the suite is not fully green"
hRN3c=$(make_home)
write_plan "$hRN3c" "$(rn_plan 'regression: yes' "$RN_FLOOR
$RN_AUD")" > /dev/null
expect_allow "RN-3c regression: yes with a green floor → admitted (the arm at yes is the arm it was)" \
  "$hRN3c" 'git commit -m "x"'

# (ii) an absent key is yes.
hRN4=$(make_home)
write_plan "$hRN4" "$(rn_plan '' "$RN_LINE
$RN_AUD")" > /dev/null
expect_block "RN-4 no regression: key, the line and no floor → blocked: an absent key reads yes (fail-closed)" \
  "$hRN4" 'git commit -m "x"' "missing required field(s): cmd pass total output"
hRN4b=$(make_home)
write_plan "$hRN4b" "$(rn_plan '' "$RN_FLOOR
$RN_AUD")" > /dev/null
expect_allow "RN-4b …and the same plan with a green floor is admitted" "$hRN4b" 'git commit -m "x"'
hRN4c=$(make_home)
write_plan "$hRN4c" "$(rn_plan 'regression: off' "$RN_LINE
$RN_AUD")" > /dev/null
expect_block "RN-4c regression: off (a value that is not no) reads yes → blocked for the fields" \
  "$hRN4c" 'git commit -m "x"' "missing required field(s): cmd pass total output"

# (iii) the override line is presence-only, never parsed.
hRN5=$(make_home)
write_plan "$hRN5" "$(rn_plan 'regression: no
regression-override: ??? not a record at all' "$RN_LINE
$RN_AUD")" > /dev/null
expect_allow "RN-5 regression: no beside a regression-override: line that parses as nothing → admitted (the line is not read)" \
  "$hRN5" 'git commit -m "x"'
hRN5b=$(make_home)
write_plan "$hRN5b" "$(rn_plan 'regression: yes
regression-override: Dana Fixture 2026-10-09 derived=no chosen=no' "$RN_LINE
$RN_AUD")" > /dev/null
expect_block "RN-5b regression: yes beside an override saying chosen=no → blocked: the key decides, the override is not parsed" \
  "$hRN5b" 'git commit -m "x"' "missing required field(s): cmd pass total output"

# (iv) the line's grammar: `no (Step 0, <user>) — <where it runs>`, each part non-empty.
rn_bad() {  # <label> <line>
  local h; h=$(make_home)
  write_plan "$h" "$(rn_plan 'regression: no' "$2
$RN_AUD")" > /dev/null
  expect_block "$1" "$h" 'git commit -m "x"' "regression: no (Step 0, <user>) — <where it runs>"
}
rn_bad "RN-6 a line with no user → blocked" "  regression: no (Step 0, ) — CI on main"
rn_bad "RN-6b a line with no em dash and no place → blocked" "  regression: no (Step 0, Chris)"
rn_bad "RN-6c a line naming no place after the em dash → blocked" "  regression: no (Step 0, Chris) —   "
rn_bad "RN-6d a line saying yes on a no plan → blocked" "  regression: yes (Step 0, Chris) — CI on main"
rn_bad "RN-6e a line that is not Step 0's → blocked" "  regression: no (Step 3, Chris) — CI on main"
hRN6f=$(make_home)
write_plan "$hRN6f" "$(rn_plan 'regression: no' "  regression: no (Step 0, Dana Fixture) — the release pipeline, job full-suite
$RN_AUD")" > /dev/null
expect_allow "RN-6f …and a well-formed line with a two-word user and a long place → admitted" "$hRN6f" 'git commit -m "x"'

# (v) THE FLOOR AT `no`, BEYOND STEP 5 (research-T4-T26-sites §3): `current 8` asks lib/proof.sh
# `facts_state`, which asks `facts_owed`; and the integrate row's kind default reads `proof:floor`
# (lib/units.sh `kdef`). At `no` neither deals the floor, or the plan clears Step 5 and is refused
# at Step 8. Read through the libraries themselves, as KX-4 reads keys_for_tier.
RN_DIR="$(mktemp -d)"; cleanup_dirs+=("$RN_DIR")
rn_units_plan() {  # <frontmatter line or empty> <file>
  printf -- '---\nscale: wave\nrigor: single\n%s---\n## SDLC State\n\ncurrent: 8\napproved-by: fixture 2026-10-04T10:00:00Z "approved"\n\n## Tasks\n\n| id | step | kind | task | agent | deps | size | serves | Files | worktree | base | status | reads |\n|---|---|---|---|---|---|---|---|---|---|---|---|---|\n| T1 | 4 | build | a | w-T1 | — | 10 | REQ-1 | lib/a.sh | — | — | landed | — |\n| T3 | 8 | integrate | merge to main | — | — | 10 | REQ-1 | — | — | — | pending | — |\n' \
    "${1:+$1
}" > "$2"
}
rn_units_plan 'regression: no' "$RN_DIR/no.md"
rn_units_plan 'regression: yes' "$RN_DIR/yes.md"
rn_units_plan '' "$RN_DIR/absent.md"
rn_lib() { ( . "${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/units.sh" >/dev/null 2>&1; "$@" ) 2>/dev/null; }
rn_owed() { rn_lib facts_owed single wave "" "$1" | cut -f1 | sort -u | tr '\n' ' ' | sed 's/ $//'; }
expect_eq "RN-7 facts_owed deals the floor at regression: yes (positive, before the absence row)" "floor review" "$(rn_owed "$RN_DIR/yes.md")"
expect_eq "RN-7b …and with the key absent" "floor review" "$(rn_owed "$RN_DIR/absent.md")"
expect_eq "RN-7c …and not at regression: no: the readings are still owed, the floor is not" "review" "$(rn_owed "$RN_DIR/no.md")"
rn_waits() { rn_lib units_waiting "$1" 8 | awk -F'\t' '$1 == "T3" { sub(/: .*/, "", $2); print $2 }' | sort -u | tr '\n' ' ' | sed 's/ $//'; }
expect_eq "RN-8 the integrate row's default reads wait on proof:floor at regression: yes (positive)" "proof:floor proof:review" "$(rn_waits "$RN_DIR/yes.md")"
expect_eq "RN-8b …and with the key absent" "proof:floor proof:review" "$(rn_waits "$RN_DIR/absent.md")"
expect_eq "RN-8c …and at regression: no the default drops proof:floor, still waiting on proof:review" "proof:review" "$(rn_waits "$RN_DIR/no.md")"
expect_eq "RN-8d the decline line's read-back of the default drops it too at no" "reads='proof:review, head, lib/a.sh'" \
  "$(rn_lib units_hold_read "$RN_DIR/no.md" T3 T1)"
expect_eq "RN-8e …and keeps it at yes" "reads='proof:floor, proof:review, head, lib/a.sh'" \
  "$(rn_lib units_hold_read "$RN_DIR/yes.md" T3 T1)"

# ============================================================
# Two sections moved here from after Section 40 when the suite was sharded (wave-30 T3).
# AC-E1.3/E1.5: its first row counts the refusals the run saw (eg_e1_check, called by every
# expect_block and expect_block_p). The sweep is this shard's; the second shard's refusals are
# each held to the same shape by their own expect_block, which fails on a line out of shape.
# R2 (AC-2.1): tests/cross-gate-agreement.test.sh (R2, the KNOB-UNSET span) reads THIS file by
# name and wants exactly one marked span in it, so the span stays in the file that keeps the name.
# ============================================================

section "AC-E1.3/E1.5: every refusal is one line, in the criterion's shape"

# fails-when: a refusal reaches the user as more than one line, or in any shape but
# `bionic: <verb> refused — <fact> (<fix ≤ 40 cols>)`.
#
# The counters below were filled by `eg_e1_check`, which every `expect_block` and
# `expect_block_p` call above runs — so the coverage is every refusal this suite
# produces, across all thirty-one direct sites and both parametric frames, rather than
# an arm per site. The count proves the sweep saw real refusals.
expect_eq "E1.3 the gate refused many times in this run (not counting over air)" "yes" \
  "$([ "$EG_E1_SEEN" -ge 100 ] && echo yes || echo no)"
expect_eq "E1.3 every refusal matched the criterion's shape" "" "$EG_E1_BAD_SHAPE"
expect_eq "E1.3 every refusal put exactly one rendered line on the user stream" "" "$EG_E1_BAD_LINES"

# THE PARAMETRIC TABLE'S EXACT WORDING at one block_matrix site and one
# ledger_shape_fail site, and the column budget on the widest of them.
. "${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/width.sh"
eg_e1_h=$(make_home)
write_plan "$eg_e1_h" "$(matrix_frontmatter true)
## SDLC State
current: 5
approved-by: fixture 2026-09-07T00:00Z \"approved\"
Step 5:
$step5_base" > /dev/null
run_hook "$eg_e1_h" 'git commit -m "x"'
expect_status "E1.3 the no-matrix fixture refuses" "2" "$HOOK_EXIT"
expect_eq "E1.3 …with the parametric table's line for :1798" \
  "bionic: commit refused — this plan has no verification matrix yet (add one row per criterion)" \
  "$(printf '%s\n' "$HOOK_STDERR" | /usr/bin/grep '^bionic: ')"
expect_eq "E1.3 …inside the 100-column budget" "yes" \
  "$([ "$(bionic_cols "$(printf '%s\n' "$HOOK_STDERR" | /usr/bin/grep '^bionic: ')")" -le 100 ] && echo yes || echo no)"
# THE HEADLINE IS WHAT THIS ARM IS ABOUT, AND ADR-030 MOVED THE STREAM UNDER IT. The old
# headline named the section; the migration put that name in `detail`, and under ruling D-1
# `detail` was on no stream a reader saw, so "not on the user stream" and "not on the
# verdict line" were the same assertion. They are not the same any more: the detail now
# rides the same wire (refuse.sh field 9, ADR-030). So the row reads the VERDICT LINE,
# which is the sentence it was always about, and its twin asserts the name is still
# somewhere a reader can reach.
expect_absent "E1.5 the section name the old headline carried is NOT on the verdict line" \
  "## Verification Matrix" "$(printf '%s\n' "$HOOK_STDERR" | /usr/bin/grep -m1 '^bionic: ')"
expect_contains "E1.5 …and it rides the detail beneath it, with no knob set at all" \
  "## Verification Matrix" "$HOOK_STDERR"
expect_contains "E1.5 …and BIONIC_WALL_VERBOSE=1 carries it, with the step number" \
  "canonical-sdlc step" "$HOOK_VSTDERR"
expect_contains "E1.5 …and the caller's repair prose" \
  "Verification Matrix" "$HOOK_VSTDERR"

# ============================================================
section "R2 — AC-2.1: the invalid-row refusal carries its violation list, knob UNSET (ADR-030)"
# ============================================================
#
# WHAT THIS SECTION EXISTS FOR (seed A §8a, carry-over 8, research R2 row 15). Section 22e2
# above already drives this exact fixture and reads `T99` — out of `$HOOK_VSTDERR`, the
# SECOND drive, taken with `BIONIC_WALL_VERBOSE=1`. Under ruling D-1 the first drive printed
# one sentence and the violation list reached no reader at all, and because every detail
# assertion in this suite reads the verbose stream, the suite was green for three releases
# while a consumer's orchestrator sourced `units_validate` by hand to learn which row was
# broken. ADR-030 flips the `exit2` channel's field 9; this section reads the stream a real
# commit actually gets.
#
# ITS OWN RUNNER, ON PURPOSE. `expect_block` calls `eg_e1_check` and then greps
# `$HOOK_VSTDERR`; using it here would re-introduce the very seam the section is about. The
# runner below drives the hook ONCE, with the knob explicitly removed from the environment
# rather than merely unset in it, and keeps the whole stream minus the run-resolution
# announcements (`split_stderr`'s rule, spelled once more so the assertions below are about
# the refusal and not about a diagnostic).
#
# fails-when: the refusal prints one line with the knob unset; or the violation list names
# no row; or the verdict is no longer the first line.
# [REQ-2 AC-2.3 KNOB-UNSET SECTION: BEGIN]
EG_R2_EXIT=0; EG_R2_ERR=""
r2_commit_knob_unset() {  # <home> <command> -> EG_R2_EXIT + EG_R2_ERR (announcements split off)
  local home_dir="$1" command="$2" input tmp_err
  input=$(jq -n --arg c "$command" --arg cwd "$home_dir" --arg s "$EG_SID" \
            '{session_id: $s, tool_input: {command: $c}, cwd: $cwd}')
  tmp_err=$(mktemp)
  eg_autobind "$home_dir"
  if env -u BIONIC_WALL_VERBOSE HOME="$home_dir" CLAUDE_PROJECT_DIR="" \
       CLAUDE_CODE_SESSION_ID="$EG_SID" bash "$HOOK" <<< "$input" >/dev/null 2>"$tmp_err"; then
    EG_R2_EXIT=0
  else
    EG_R2_EXIT=$?
  fi
  EG_R2_ERR=$(grep -v -E "$EG_RESOLUTION_RE" "$tmp_err" || true)
  rm -f "$tmp_err"
}
require_helpers r2_commit_knob_unset

# THE FIXTURE IS ITS OWN, not 22e2's variable reached across three thousand lines: a dep
# naming no row is the violation `units_validate` alone knows about, and two rows make the
# list name WHICH row rather than being the only row there is.
r2_tasks_bad="## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | status |
|---|---|---|---|---|---|---|---|---|---|
| T1 | 4 | build | the dispatched unit | implementor | — | 30m | REQ-x | a.sh | landed |
| T2 | 5 | verify | the other unit | auditor | T99 | 30m | REQ-x | b.sh | pending |"
h_r2=$(make_home)
write_plan "$h_r2" "$(d7_wave_plan "$r2_tasks_bad" "- T1: bash suite 9/9 green
- T2: bash suite 9/9 green")" > /dev/null
r2_commit_knob_unset "$h_r2" 'git commit -m "x"'

expect_status "R2a an invalid-row commit is still refused, fail-closed" "2" "$EG_R2_EXIT"
expect_eq "R2b …and the verdict is the first line, unchanged" \
  "bionic: commit refused — that dispatched task's row is invalid (fix the row the detail names)" \
  "$(printf '%s\n' "$EG_R2_ERR" | /usr/bin/grep -m1 '^bionic: ')"
expect_contains "R2c …with units_validate's violation line behind it (AC-2.1)" \
  "T2: dep T99 names no row in the table" "$EG_R2_ERR"
expect_contains "R2d …and the Fix prose that names all TWELVE columns (R7/W3c)" \
  "the columns are id | step | kind | task | agent | deps | size | serves | Files | worktree | base | status" \
  "$EG_R2_ERR"
expect_eq "R2e …so the stream is no longer the one line the defect shipped" "no" \
  "$([ "$(printf '%s\n' "$EG_R2_ERR" | /usr/bin/grep -c .)" = "1" ] && echo yes || echo no)"
expect_eq "R2f …and still exactly one rendered refusal line, not two" "1" \
  "$(printf '%s\n' "$EG_R2_ERR" | /usr/bin/grep -c '^bionic: ')"

# THE OTHER DIRECTION, so R2c is not passing on a stream that carries everything: an
# ALLOWED commit on the repaired table says nothing at all, knob unset or not.
r2_tasks_good="${r2_tasks_bad/| auditor | T99 |/| auditor | T1 |}"
h_r2b=$(make_home)
write_plan "$h_r2b" "$(d7_wave_plan "$r2_tasks_good" "- T1: bash suite 9/9 green
- T2: bash suite 9/9 green")" > /dev/null
r2_commit_knob_unset "$h_r2b" 'git commit -m "x"'
expect_status "R2g the repaired table commits" "0" "$EG_R2_EXIT"
expect_empty "R2h …and prints nothing, so R2c read a refusal and not a chatty hook" "$EG_R2_ERR"
# [REQ-2 AC-2.3 KNOB-UNSET SECTION: END]

finish
