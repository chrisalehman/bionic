#!/bin/bash
# Tests for canonical-sdlc-evidence-gate.sh — shard 2 of 2 (Section 29 onward).
#
# The evidence-gate suite was sharded in two at wave-30 T3 (D8b) so a landing that touches the
# gate proves in minutes. The runners, helpers and shared plan fixtures live in
# tests/canonical-sdlc-evidence-gate.prelude.sh, sourced by both shards; the strategy note
# there applies to each. Usage: bash tests/canonical-sdlc-evidence-gate-2.test.sh
#
# THE PRELUDE IS SOURCED BEFORE THE FRAMEWORK, on purpose — see its header.

set -euo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/canonical-sdlc-evidence-gate.prelude.sh"
. "$(dirname "$0")/lib/assert.sh"
. "$(dirname "$0")/lib/regression-fixture.sh"
. "$(dirname "$0")/lib/bound-marker.sh"
. "$(dirname "$0")/lib/roster-row.sh"

# THE SEAM IS hooks/bash-walls.sh (epic-23 wave-11-lean-spine, T23). This wall is a
# FUNCTION now — `wall_evidence_gate` in payload/scripts/lib/walls.sh — registered through
# the one PreToolUse|Bash command object that carries all five. Every case below drives
# that process, which is what a Bash tool call actually starts; the wall's own verdict is
# unchanged and tests/bash-walls.test.sh owns the composition the process adds.
HOOK="${BIONIC_HOOKS_DIR}/bash-walls.sh"

# THE FLOOR A RUN PAST STEP 6 CARRIES (wave-35 T31; D20, A-orch-50): shard 1's eg_floor, the same helper,
# since the prelude both shards source is outside the row that added the arm.
eg_floor() {  # <plan content> -> the content with the readings and one floor proof line
  eg_readings "$1" | EG_H="$EG_HEAD" awk '{ print }
    !done && /^[[:space:]]*current[[:space:]]*:[[:space:]]*[7-9][ab]?[[:space:]]*$/ {
      printf "proved: kind=regression head=%s at=2026-10-12T00:00:00Z evidence=record/floor.log\n", ENVIRON["EG_H"]; done = 1 }'
}

# ============================================================
# Section 29: Step 9 close-out contract (v14)
# ============================================================
#
# The v14 contract, ratified 2026-08-19 (epic-17 W5, design ledger D-A):
#
#   delivered:  ALWAYS. Every run has a terminal state — a PR open and ready
#               for a human to review, or commits landed locally ready to
#               push. Nothing past that boundary is the run's to claim.
#   deployed: / verified: / monitored:
#               owed EXACTLY when frontmatter names a live deploy_target.
#
# What died with v13: the trio was owed whenever a target existed, and `n/a:`
# discharged the step only at `deploy_target: none`. That rule encoded
# wave==release — the exception, not the rule — and it let a run with no live
# surface close by writing `n/a` instead of naming what it delivered.
#
# `deploy_target` itself is n/a by default and is never inferred (AC-3), so
# the trio is strictly opt-in: 29a/29e/29e2 are the ordinary run, 29c is the
# dogfood run that operates its own surface.
section "Section 29: Step 9 close-out contract (v14)"

# A plan at current: 9. $1 = deploy_target value, $2 = the Step-9 block body.
# Reuses Section 17's matrix_complete, since current: 9 revalidates the matrix
# as a prefix check before the step shape is ever reached.
ship_plan() {
  printf '%s\n## SDLC State\ncurrent: 9\napproved-by: fixture 2026-09-07T00:00Z approved\nStep 9:\n%s\n\n%s\n' \
    "$(frontmatter wave "$1")" "$2" "$matrix_complete"
}

ship_delivered="  delivered: PR #412 open and review-ready — 6 commits on wave/17-05"
ship_trio="  deployed: ./claude-bootstrap.sh rc=0 to this machine
  verified: installed hook spot-check reads SUPPORTED_SDLC_VERSION=14
  monitored: one Patrol cycle clean, no wall misfires"

# 29a — no live surface, `delivered:` present → allow. The default run's whole
# close-out obligation is this one line.
h29a=$(make_home)
write_plan "$h29a" "$(ship_plan none "$ship_delivered")" > /dev/null

# 29b — `delivered:` missing → block. The terminal state is not optional.
h29b=$(make_home)
write_plan "$h29b" "$(ship_plan none "  note: wrapped it up")" > /dev/null
expect_block "29b Step 9 without delivered: → block naming the key" "$h29b" 'git commit -m "x"' "delivered"

# 29c — a named live surface: delivered + the full trio → allow.
h29c=$(make_home)
write_plan "$h29c" "$(ship_plan local-harness "$ship_delivered
$ship_trio")" > /dev/null

# 29d — a named live surface with `delivered:` only → block, naming what the
# named target owes.
h29d=$(make_home)
write_plan "$h29d" "$(ship_plan local-harness "$ship_delivered")" > /dev/null
expect_block "29d Step 9, deploy_target named, trio missing → block" "$h29d" 'git commit -m "x"' "deployed"

# 29e — `deploy_target: n/a` is not a named surface (AC-3's default value), so
# the trio is not owed.
h29e=$(make_home)
write_plan "$h29e" "$(ship_plan n/a "$ship_delivered")" > /dev/null

# 29e2 — no `deploy_target` line at all reads the same way. An omission is
# never a named surface, so it can never conjure the trio into existence.
h29e2=$(make_home)
write_plan "$h29e2" "---
governing-skill: canonical-sdlc
canonical_sdlc_version: 14
intent: build
rigor: double
scale: wave
use_worktree: false
has_ui: false
walk: exempt
---

## SDLC State
current: 9
approved-by: fixture 2026-09-07T00:00Z "approved"
Step 9:
$ship_delivered

$matrix_complete" > /dev/null

# 29f — the v13 shape (deploy:/verified-at:/monitor:) no longer discharges the
# step: it names a release and never names the delivery.
h29f=$(make_home)
write_plan "$h29f" "$(ship_plan none "  deploy: shipped to prod at 14:02
  verified-at: https://app.example/health
  monitor: one cycle clean")" > /dev/null
expect_block "29f Step 9 in the retired v13 shape → block on delivered" "$h29f" 'git commit -m "x"' "delivered"

# 29g — `n/a:` was v13's escape at deploy_target: none. Under v14 there is
# nothing to escape: the run still has to name what it delivered.
h29g=$(make_home)
write_plan "$h29g" "$(ship_plan none "  n/a: nothing to deploy")" > /dev/null
expect_block "29g Step 9 with the retired 'n/a:' escape → block on delivered" "$h29g" 'git commit -m "x"' "delivered"

# 29h — a run with no named target that deployed something anyway and said so
# is recording MORE than it owes, which is never a reason to refuse a commit.
# The trio is unowed here, not forbidden.
h29h=$(make_home)
write_plan "$h29h" "$(ship_plan none "$ship_delivered
$ship_trio")" > /dev/null

# ============================================================
# Section 30: T4 rows discharge on the user's own confirmation
# ============================================================
#
# THE BLIND SPOT THIS CLOSES. Past the Verify gate, every non-waived row must
# carry an auditor verdict of CONFIRMED. T4 is the tier whose evidence IS the
# user's confirmation — an independent agent auditing it can only re-read what
# the user said, which is not independence, it is transcription. So a
# legitimately user-confirmed T4 row had exactly one way past this arm: the
# Waiver Protocol. That recorded a waiver where nothing was waived. Epic-17 W4
# paid it in that form for its AC-7 and the row reads, permanently, as if the
# criterion had been let go.
#
# THE FIX. A T4 row whose AC block carries a well-formed
# `user-confirmed: <user> <date> <what>` discharges without a waiver. Nothing
# else moves: the tier's evidence key was always `user-confirmed` (keys_for_tier),
# and this arm now reads that same value as the discharge it already was.
#
# THE IMPOSTOR, AND THE HONEST LIMIT. The form check is an ATTRIBUTION check —
# a leading user token, an ISO date, and something said. An agent-shaped claim
# ("confirmed after re-render", "2026-08-18 the wall renders") carries no
# attributed human and is refused. What no hook can see is whether the named
# human actually said it; a fabricated `chris 2026-08-19 ...` passes the form.
# The form buys a record that names who and when — it does not buy honesty, and
# it is not sold as if it did.
# WHERE IT BITES. The ruling is demanded from step 8, the merge advance, where the release approval card
# settles it; from step 6 the arm asks only for a verdict, and a T4 row's `user-confirmed:` line is one. So
# every arm below is written at current: 8, and 30m pins the step-6 half beside them.
section "Section 30: T4 rows discharge on user-confirmed, impostors do not"

# $1 = tier, $2 = auditor cell, $3 = the block's user-confirmed value.
t4_matrix() {
  printf '## Verification Matrix

stack-health: n/a: no long-running serve

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1 | %s | discharged | see AC-1 | %s |

AC-1:
  fails-when: the planted defect this eval must go red on
  evidence: record/generic-evidence.md
  user-confirmed: %s
  tier-run: rendered the wall in the live client
  fresh: rebuilt from the deployed payload
  cold-client: fresh session, no snapshot carryover
  contact: user opened it and read the text back
  readback: quoted the rendered literal verbatim\n' "$1" "$2" "$3"
}

GOOD_CONFIRM='chris 2026-08-18 read the rendered wall in his own client and confirmed the wording'

# 30a — the case the blind spot refused: a real user confirmation, no auditor
# verdict, no waiver → allow.
h30a=$(make_home)
write_plan "$h30a" "$(eg_floor "$(wave_plan 8 "$v9_step8_body" "$(t4_matrix T4 "" "$GOOD_CONFIRM")")")" > /dev/null
expect_allow "30a T4 + attributed user-confirmed + empty auditor cell at current 8 → allow (ruled by the user)" "$h30a" 'git commit -m "x"'

# 30b — an agent-shaped claim: no attributed human, no date. Still refused.
h30b=$(make_home)
write_plan "$h30b" "$(eg_floor "$(wave_plan 8 "$v9_step8_body" \
  "$(t4_matrix T4 "" "confirmed by the implementor agent after the re-render")")")" > /dev/null
expect_block "30b T4 + agent-shaped user-confirmed → block (no attributed user)" "$h30b" 'git commit -m "x"' "CONFIRMED"

# 30c — a date with nobody attached is not an attribution either.
h30c=$(make_home)
write_plan "$h30c" "$(eg_floor "$(wave_plan 8 "$v9_step8_body" \
  "$(t4_matrix T4 "" "2026-08-18 the wall renders as specified")")")" > /dev/null
expect_block "30c T4 + dated but unattributed user-confirmed → block" "$h30c" 'git commit -m "x"' "CONFIRMED"

# 30d — the exemption is T4-scoped. A T3 row cannot buy its way past the
# auditor by writing a user's name into its block: T3's evidence is a live
# reading an auditor CAN re-take independently, so the verdict still stands.
h30d=$(make_home)
write_plan "$h30d" "$(eg_floor "$(wave_plan 8 "$v9_step8_body" "$(t4_matrix T3 "" "$GOOD_CONFIRM")")")" > /dev/null
expect_block "30d T3 + well-formed user-confirmed → block (exemption is T4-only)" "$h30d" 'git commit -m "x"' "CONFIRMED"

# 30e — no regression: a T4 row an auditor DID confirm still passes.
h30e=$(make_home)
write_plan "$h30e" "$(eg_floor "$(wave_plan 8 "$v9_step8_body" "$(t4_matrix T4 CONFIRMED "$GOOD_CONFIRM")")")" > /dev/null
expect_allow "30e T4 + CONFIRMED auditor cell → allow (unchanged)" "$h30e" 'git commit -m "x"'

# 30f — pinned scope boundary: the form check lives in the post-Verify arm
# only. At current: 5 the row is still being discharged and the contract there
# is the one it always was — `user-confirmed` present, non-empty, not a
# placeholder. An impostor value passes the VERIFY gate and meets the form
# check on the advance to 8, which is where the ruling is demanded. Widening the check to Step 5 would false-block mid-discharge commits
# on plans written before this contract existed.
h30f=$(make_home)
write_plan "$h30f" "$(wave_plan 5 "$step5_base" \
  "$(t4_matrix T4 CONFIRMED "confirmed by the implementor agent")")" > /dev/null
expect_allow "30f impostor at current: 5 → allow (form check is post-Verify only)" "$h30f" 'git commit -m "x"'

# 30h — THE REFUTATION ARM (critic C-1, W5). The exemption above replaces the
# WAIVER FORM a user-confirmed row used to be paid in; it does not replace the
# AUDITOR. Those are different authorities and the design ratified only the
# first substitution. Written as a plain `elif` ahead of the verdict test, the
# arm let a T4 row carrying a well-formed `user-confirmed:` walk past an
# auditor's STANDING REFUTED — the one verdict in the vocabulary that is a
# positive finding rather than an absence, and the one this very wave produced
# three of on its first audit pass. So the exemption is scoped to an auditor
# cell that is EMPTY (nobody has ruled) or CONFIRMED (agreement): a refutation
# on the record meets the wall, and the refusal names the refutation rather
# than the attribution, because the attribution is fine and re-writing it is
# not the fix.
h30h=$(make_home)
write_plan "$h30h" "$(eg_floor "$(wave_plan 8 "$v9_step8_body" "$(t4_matrix T4 REFUTED "$GOOD_CONFIRM")")")" > /dev/null
expect_block "30h T4 + well-formed user-confirmed + auditor REFUTED → block" "$h30h" 'git commit -m "x"' "REFUTED"

# 30i — UNVERIFIABLE is the auditor's other positive finding: it says the
# evidence could not be checked, which is not the same as nobody having looked.
# Same arm, same reason.
h30i=$(make_home)
write_plan "$h30i" "$(eg_floor "$(wave_plan 8 "$v9_step8_body" "$(t4_matrix T4 UNVERIFIABLE "$GOOD_CONFIRM")")")" > /dev/null
expect_block "30i T4 + well-formed user-confirmed + auditor UNVERIFIABLE → block" "$h30i" 'git commit -m "x"' "UNVERIFIABLE"

# 30m — the step-6 half of the move. At current: 6 the arm asks for a verdict, not a ruling: the impostor of
# 30b and the standing finding of 30h each carry a `user-confirmed:` line, which is a T4 row's verdict, so the
# gate admits both there; 30b and 30h refuse the same rows at current: 8.
h30m=$(make_home)
write_plan "$h30m" "$(wave_plan 6 "$step6_body" \
  "$(t4_matrix T4 "" "confirmed by the implementor agent after the re-render")")" > /dev/null
expect_allow "30m T4 + agent-shaped user-confirmed at current 6 → allow (a verdict; the ruling is step 8's)" "$h30m" 'git commit -m "x"'
h30m2=$(make_home)
write_plan "$h30m2" "$(wave_plan 6 "$step6_body" "$(t4_matrix T4 REFUTED "$GOOD_CONFIRM")")" > /dev/null
expect_allow "30m2 T4 + well-formed user-confirmed + auditor REFUTED at current 6 → allow" "$h30m2" 'git commit -m "x"'

# (30j — an arm asserting the refusal SENTENCE ("does not overturn") on the same
# fixture 30h already blocks on — deleted at epic-18 W1: its only failure mode
# was a reworded message.)

# 30k — and the positive twin, so the pair discriminates: the SAME row with the
# SAME confirmation and a CONFIRMED verdict passes. (30e proves the well-formed
# + CONFIRMED case at the top of this section; this arm is stated beside its
# refutation twin so a future edit that broke the agreement case would fail
# next to the one that proves the refusal.)
h30k=$(make_home)
write_plan "$h30k" "$(eg_floor "$(wave_plan 8 "$v9_step8_body" "$(t4_matrix T4 CONFIRMED "$GOOD_CONFIRM")")")" > /dev/null

# 30g — META-EVIDENCE, and the durable half of this section.
#
# 30b/30c/30d block against the PRE-fix hook too, for the old reason (no
# CONFIRMED verdict at all). A test that reads green on both sides of a change
# proves nothing about the change, so the impostor arms are re-run here against
# a DOCTORED hook whose attribution form check has been loosened to accept any
# non-empty value. If the form check is what refuses the impostor, 30b's
# fixture must ALLOW there. If it does not, the impostor arms above are
# passing on the missing-verdict rule and this section is decorative.
#
# The doctored copy lives in a temp dir and the real hook is never touched.
h30g_dir=$(mktemp -d); cleanup_dirs+=("$h30g_dir")
# Since 1.3.2 the gate reads commands through scripts/lib/git-argv.sh and
# REFUSES when it cannot load it (spec AC-12, Chris D1). A doctored copy alone
# in a bare temp dir therefore refuses everything for the wrong reason, so the
# copy gets the shipped layout around it: hooks/ beside scripts/lib/.
mkdir -p "$h30g_dir/hooks" "$h30g_dir/scripts/lib"
# Since bionic 1.4.0 the gate wants several libraries and the loader qualifies a directory
# only when it holds ALL of them (BIONIC_LIB_WANT). A fixture that plants a subset is a
# fixture that refuses everything for the wrong reason.
#
# THE WHOLE DIRECTORY, NOT A HAND-LIST (epic-22 wave-01, N1). This loop named four
# libraries by hand. That list went stale the moment lib/run.sh grew a soft source of
# lib/roots.sh — `docs_root` came back `command not found`, the gate fell through, and this
# section's mutation arm went GREEN against a hook that had allowed for the wrong reason.
# A hand-list of a shipped directory's contents is a second copy of that directory, kept by
# hand; the glob cannot drift.
for _h30g_cand in "${BIONIC_HOOKS_DIR}/../scripts/lib" \
                  "${BIONIC_HOOKS_DIR}/../payload/scripts/lib"; do
  if [ -d "$_h30g_cand" ]; then
    cp "$_h30g_cand"/*.sh "$h30g_dir/scripts/lib/" 2>/dev/null
    break
  fi
done
# THE MUTATION LANDS ON THE LIBRARY NOW, NOT ON THE HOOK (T23). The predicate this
# section loosens lives in `wall_evidence_gate`'s body in payload/scripts/lib/walls.sh;
# the hook beside it is 200 lines of preamble and a fold. So the doctored tree gets a
# doctored COPY OF THE LIBRARY and an untouched copy of the hook, and the loader finds
# it because `$h30g_dir/scripts/lib` is candidate class (1).
DOCTORED_HOOK="$h30g_dir/hooks/loose-gate.sh"
cp "$HOOK" "$DOCTORED_HOOK"
H30G_LIB="$h30g_dir/scripts/lib/walls.sh"
H30G_LIB_REAL="$(dirname "$H30G_LIB")/.walls-real.sh"
cp "$H30G_LIB" "$H30G_LIB_REAL"
sed 's#^user_confirmed_attributed() {#user_confirmed_attributed() { [ -n "$1" ]; return; #' \
  "$H30G_LIB_REAL" > "$H30G_LIB"

if ! diff -q "$H30G_LIB_REAL" "$H30G_LIB" > /dev/null 2>&1; then
  ok "30g meta: the doctored copy differs from the real hook (mutation landed)"
else
  no "30g meta: the doctored copy differs from the real hook (mutation landed)" "the form-check mutation did not apply — the sed anchor moved, so the arms below prove nothing"
fi
rm -f "$H30G_LIB_REAL"

_real_hook="$HOOK"
HOOK="$DOCTORED_HOOK"
# T4-scoping is a separate predicate from the form, so the T3 row must STILL
# block against the doctored hook — the tier arm is not what was loosened.
expect_block "30g meta: the T3 row still blocks under the loosened form (tier scope is a separate arm)" "$h30d" 'git commit -m "x"' "CONFIRMED"
HOOK="$_real_hook"

# Restore-proof: the real hook still refuses the impostor after the detour.
expect_block "30g meta: the real hook still refuses the impostor after the mutation proof" "$h30b" 'git commit -m "x"' "CONFIRMED"

# ============================================================
# Section 31: a refusal on a call that also writes the plan (B-6)
# ============================================================
#
# The gate reads the plan off disk when the CALL starts. So a single Bash call
# that edits the plan and then commits is judged against the PRE-EDIT plan: the
# fix the agent just wrote is invisible, and the refusal reads as though it had
# never been made. The observed reflex is to re-run the same combined call. When
# the refused command's text names the plan, the refusal now says so.

section "Section 31: refusal names the edit-then-commit split"

# 31a — a python3 heredoc writing the plan's absolute path, then a commit,
# refused by the matrix arm → the refusal carries the split line.
h31a=$(make_home)
p31a=$(write_plan "$h31a" "$(plan 6 "$step6_body" "$v101_matrix_pending")")
cmd31a=$(printf 'python3 - <<%s\nopen("%s","a").write("\\nAC-2:\\n  tier-run: x\\n")\nEOF\ngit commit -m "discharge AC-2"' "'EOF'" "$p31a")

# 31a — the same refusal still names the row it refused (the note is an extra
# line, not a replacement).
expect_block "31a the split line does not displace the original refusal" "$h31a" "$cmd31a" "AC-2"

# 31b — the project-relative spelling of the same path (what an agent actually
# types) is matched too.
h31b=$(make_home)
write_plan "$h31b" "$(plan 6 "$step6_body" "$v101_matrix_pending")" > /dev/null

# 31c — a refused commit that does NOT name the plan gets the ordinary 3-line
# refusal and no split line. Same fixture and same extractor as 31a, so this
# pins the note's scope rather than asserting an empty world.
run_hook "$h31a" 'git commit -m "x"'
if [ "$HOOK_EXIT" -eq 2 ] \
   && grep -q "AC-2" <<<"$HOOK_VSTDERR" \
   && ! grep -q "also writes the plan" <<<"$HOOK_STDERR"; then
  ok "31c plain commit refusal carries no split line"
else
  no "31c plain commit refusal carries no split line" "expected a block naming AC-2 with NO split line; exit=$HOOK_EXIT stderr='$HOOK_STDERR'"
fi

# 31d — the note rides on a refusal, never on its own: a command that names the
# plan but has nothing to refuse is still allowed silently.
h31d=$(make_home)
p31d=$(write_plan "$h31d" "$(plan 6 "$step6_body" "$matrix_complete")")
expect_allow "31d naming the plan in an otherwise-clean commit → allow, silent" "$h31d" "python3 -c \"open('$p31d','a')\" && git commit -m \"x\""

# ============================================================
# Section 32: the auditor wall is rigor-keyed (B-10 / R-11)
# ============================================================
#
# SKILL.md's rigor table says `single` skips BOTH independent assurance roles
# — "Self-review only." The gate read the matrix's auditor column
# unconditionally, so a `single` run met a CONFIRMED wall for a verdict its own
# rigor says nobody was ever sent to write. B-10's repro: a bugfix · single ·
# task run refused at `current: 9` on "matrix row 'AC-1' auditor verdict is
# 'empty', not CONFIRMED".
#
# The rule: at `single` the matrix's auditor column is not read (any value —
# empty included — passes the post-Verify CONFIRMED arm at every step 6..9) and
# the Step-5 `auditor:` pointer is not demanded once the rows are discharged.
# At `double` and `double` both walls are exactly as they were. An
# unknown or missing frontmatter `rigor:` takes the STRICT reading — fail
# closed, since a plan that does not say what rigor it runs at has not bought
# the relaxation.
#
# The task-ledger side (apply_rigor_lanes) went with the retired task table (wave-31 T24;
# D2); 32f pins what its fixture meets now.

section "Section 32: the auditor wall is rigor-keyed"

# A wave plan at a caller-chosen frontmatter rigor. Same shape as
# matrix_frontmatter (walk: exempt, deploy_target: none, no multi_agent — so the
# walk arm and the dispatch ledger stay out of the way), with `rigor` as the one
# variable. Pass an empty string for $1 to omit the key entirely.
plan_rigor() {  # $1 rigor (empty = key absent)  $2 current  $3 step body  $4 matrix
  printf -- '---\n'
  printf -- 'governing-skill: canonical-sdlc\n'
  printf -- 'canonical_sdlc_version: 14\n'
  printf -- 'intent: build\n'
  [ -n "$1" ] && printf -- 'rigor: %s\n' "$1"
  printf -- 'scale: wave\n'
  printf -- 'deploy_target: none\n'
  printf -- 'use_worktree: false\n'
  printf -- 'has_ui: true\n'
  printf -- 'walk: exempt\n'
  printf -- '---\n'
  printf -- '## SDLC State\ncurrent: %s\napproved-by: fixture 2026-09-07T00:00Z approved\nStep %s:\n%s\n\n%s\n' "$2" "$2" "$3" "$4"
}

# Every row discharged, every per-tier key present, EVERY AUDITOR CELL EMPTY.
# The only thing standing between this matrix and a clean commit is the
# CONFIRMED arm, so each verdict below is that arm's doing.
m32_empty_aud="## Verification Matrix

stack-health: process restarts 0 → 0 across walk; no crash/OOM state change

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1 | T1 | discharged | see AC-1 |  |
| AC-2 | T1 | discharged | see AC-2 |  |

AC-1:
  fails-when: the planted defect this eval must go red on
  evidence: record/generic-evidence.md
  tier-run: bash tests/canonical-sdlc-evidence-gate.test.sh
  readback: 120/120 asserted
AC-2:
  fails-when: the planted defect this eval must go red on
  evidence: record/generic-evidence.md
  tier-run: bash test.sh — unit suite
  readback: 332/332 asserted"

# The same matrix carrying a STANDING REFUTED verdict. At single the column is
# not read at all, so this passes too — the relaxation is "the column is not a
# gate", not "an empty cell is tolerated".
m32_refuted="${m32_empty_aud/| AC-1 | T1 | discharged | see AC-1 |  |/| AC-1 | T1 | discharged | see AC-1 | REFUTED |}"

# The same matrix with AC-2's `evidence:` key removed (wave-31 T6: the pointer is the one key every tier owes; this
# control named `readback:` while the gate demanded it). The rest of the matrix
# contract is untouched by B-10, so this must still block at single — the
# discrimination control for every 32a..32d allow.
m32_nl=$'\n'
m32_missing_key="${m32_empty_aud/  evidence: record\/generic-evidence.md${m32_nl}  tier-run: bash test.sh — unit suite/  tier-run: bash test.sh — unit suite}"

# Step-5 tests floor with NO `auditor:` pointer.
step5_noaud="  cmd: bash test.sh
  pass: 332
  total: 332
  head: ${EG_HEAD}
  output: .bionic/docs/plans/wave-01.plan.md#step-5"

# ---- AC-26: at `single` the wall is not there ------------------------------

# 32a..32d — the post-Verify CONFIRMED arm is a prefix contract at 6, 7, 8 and
# 9 (dispatch()); B-10's own repro was at 9, so all four steps are pinned. The
# 7/8/9 step bodies are Section 17r's, which their own validators pin already.
h32a=$(make_home)
write_plan "$h32a" "$(plan_rigor single 6 "$step6_body" "$m32_empty_aud")" > /dev/null
expect_allow "32a rigor single, rows discharged, auditor cells empty, current 6 → allow" "$h32a" 'git commit -m "x"'

h32b=$(make_home)
write_plan "$h32b" "$(eg_floor "$(plan_rigor single 7 "$v9_step7_body" "$m32_empty_aud")")" > /dev/null
expect_allow "32b same at current 7 → allow" "$h32b" 'git commit -m "x"'

h32c=$(make_home)
write_plan "$h32c" "$(eg_floor "$(plan_rigor single 8 "$v9_step8_body" "$m32_empty_aud")")" > /dev/null
expect_allow "32c same at current 8 → allow" "$h32c" 'git commit -m "x"'

h32d=$(make_home)
write_plan "$h32d" "$(eg_floor "$(plan_rigor single 9 "$v9_step9_body" "$m32_empty_aud")")" > /dev/null
expect_allow "32d same at current 9 → allow (B-10's own repro step)" "$h32d" 'git commit -m "x"'

# 32e — the Step-5 `auditor:` pointer is the same wall one step earlier: it is
# demanded once no row is pending. At single there is no auditor to point at.
h32e=$(make_home)
write_plan "$h32e" "$(plan_rigor single 5 "$step5_noaud" "$m32_empty_aud")" > /dev/null
expect_allow "32e rigor single, all rows discharged, no Step-5 auditor: pointer → allow" "$h32e" 'git commit -m "x"'

# 32f — the task-ledger mirror (AC-26, second half) is gone with the task ledger (wave-31 T24;
# D2): its `done` row at single, and 32k's row raised to double by its own cell, were the
# retired table at `current: T2`. That plan meets the numeric refusal now.
h32f=$(make_home)
write_plan "$h32f" "$(eg_pf_plan T2 task single false "- T2: fixed enum check, bash suite 12/12" "$(eg_pf_row T1 — landed)" "$(eg_pf_row T2 — active)")" > /dev/null
expect_block "32f 32f's and 32k's task plan at current: T2 → refused as not numeric" "$h32f" 'git commit -m "x"' "current: T2 is not numeric"

# 32n — the column is not READ at single, not merely tolerated when empty: a
# standing REFUTED verdict passes too. Pinned deliberately (it is the sharpest
# statement of the rule, and the case a narrower fix would get wrong).
h32n=$(make_home)
write_plan "$h32n" "$(plan_rigor single 6 "$step6_body" "$m32_refuted")" > /dev/null
expect_allow "32n rigor single, a REFUTED auditor cell at current 6 → allow (column unread)" \
  "$h32n" 'git commit -m "x"'

# 32o — discrimination control: everything ELSE the matrix demands still bites
# at single. AC-2 (T1) is missing its `evidence:` key on the same fixture family
# and at the same step, so 32a..32d are the auditor arm standing down and not
# the matrix going quiet.
h32o=$(make_home)
write_plan "$h32o" "$(plan_rigor single 6 "$step6_body" "$m32_missing_key")" > /dev/null
expect_block "32o control: single plan missing the evidence key still blocks at current 6" \
  "$h32o" 'git commit -m "x"' "missing evidence key 'evidence'"

# ---- AC-27: at double and double the wall is unchanged -------------

h32g=$(make_home)
write_plan "$h32g" "$(plan_rigor double 6 "$step6_body" "$m32_empty_aud")" > /dev/null

h32h=$(make_home)
write_plan "$h32h" "$(plan_rigor double 6 "$step6_body" "$m32_empty_aud")" > /dev/null

# 32i/32j — the Step-5 pointer half of AC-27.
h32i=$(make_home)
write_plan "$h32i" "$(plan_rigor double 5 "$step5_noaud" "$m32_empty_aud")" > /dev/null
expect_block "32i rigor double, discharged rows, no Step-5 auditor: pointer → block" \
  "$h32i" 'git commit -m "x"' "requires 'auditor:"

h32j=$(make_home)
write_plan "$h32j" "$(plan_rigor double 5 "$step5_noaud" "$m32_empty_aud")" > /dev/null
expect_block "32j rigor double, discharged rows, no Step-5 auditor: pointer → block" \
  "$h32j" 'git commit -m "x"' "requires 'auditor:"

# ---- fail-closed on an unknown or missing rigor ----------------------------

# 32l — no `rigor:` key at all. A plan that never says what rigor it runs at
# has not bought the relaxation, so the strict reading holds.
h32l=$(make_home)
write_plan "$h32l" "$(plan_rigor "" 6 "$step6_body" "$m32_empty_aud")" > /dev/null
expect_block "32l frontmatter with NO rigor key at current 6 → block (fail closed)" \
  "$h32l" 'git commit -m "x"' "not CONFIRMED"

# 32m — an off-enum value is no bypass: since wave-30 T11 the gate refuses a rigor that names no
# level before any arm reads it, so a typo is refused on its rigor, ahead of the matrix.
h32m=$(make_home)
write_plan "$h32m" "$(plan_rigor reviewed 6 "$step6_body" "$m32_empty_aud")" > /dev/null

# 32m2 — and the Step-5 pointer half fails closed too.
h32m2=$(make_home)
write_plan "$h32m2" "$(plan_rigor "" 5 "$step5_noaud" "$m32_empty_aud")" > /dev/null
expect_block "32m2 no rigor key at current 5, no auditor: pointer → block (fail closed)" \
  "$h32m2" 'git commit -m "x"' "requires 'auditor:"

# ============================================================
# Section 33: a row owed at the close owes nothing before it
# ============================================================
#
# A criterion is owed at the step whose task proves it, and `task: 9` names the close. An
# unwaived pending row carrying it owes neither its per-tier keys nor a verdict at an earlier
# step, so the commit is allowed (33b). Delete the owing-step comparison from the deferral
# predicate and the same row is live: it meets the per-tier key refusals (33b-rev). A waiver
# still outranks the per-tier keys, in either spelling (33a, 33c), and sits below the
# provenance arm (33d).

section "Section 33: a row owed at the close owes nothing before it"

# The first row is an ordinary discharged row, so each verdict below is the second row's doing.
m33_waived="## Verification Matrix

stack-health: n/a: no long-running serve

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1 | T1 | discharged | see AC-1 | CONFIRMED |
| AC-2 | T1 | waived | waiver: dana 2026-08-30 criterion dropped | waived |

AC-1:
  fails-when: the planted defect this eval must go red on
  evidence: record/generic-evidence.md
  tier-run: bash test.sh — unit suite
  readback: 332/332 asserted
AC-2:
  fails-when: the planted defect this eval must go red on
  evidence: record/generic-evidence.md
  task: 9"

# The same row with the waiver taken away: pending, no token anywhere.
m33_unwaived="${m33_waived/| AC-2 | T1 | waived | waiver: dana 2026-08-30 criterion dropped | waived |/| AC-2 | T1 | pending | see AC-2 |  |}"

# The waiver in the AC BLOCK rather than the evidence cell.
m33_waived_block="${m33_waived/| AC-2 | T1 | waived | waiver: dana 2026-08-30 criterion dropped | waived |/| AC-2 | T1 | waived | dropped, see block | waived |}"
m33_waived_block="${m33_waived_block/  task: 9/  task: 9
  waiver: dana 2026-08-30 criterion dropped}"

h33a=$(make_home)
write_plan "$h33a" "$(plan 6 "$step6_body" "$m33_waived")" > /dev/null
expect_allow "33a waived T1 row carrying 'task: 9' at current 6 → allow" \
  "$h33a" 'git commit -m "x"'

h33b=$(make_home)
write_plan "$h33b" "$(plan 6 "$step6_body" "$m33_unwaived")" > /dev/null
expect_allow "33b unwaived pending T1 row carrying 'task: 9' at current 6 → allow (owed at the close, deferred)" \
  "$h33b" 'git commit -m "x"'
# The reverted rule: a copy of the shipped layout whose deferral predicate never defers.
h33r_dir=$(mktemp -d); cleanup_dirs+=("$h33r_dir")
cp -R "$h30g_dir/hooks" "$h30g_dir/scripts" "$h33r_dir/"
cp "$_h30g_cand/walls.sh" "$h33r_dir/scripts/lib/walls.sh.real"
sed 's#^matrix_row_deferred() {#matrix_row_deferred() { return 1;#' "$h33r_dir/scripts/lib/walls.sh.real" > "$h33r_dir/scripts/lib/walls.sh"
expect_true "33b-rev meta: the reverted copy differs from the real library (mutation landed)" \
  test -n "$(diff "$h33r_dir/scripts/lib/walls.sh.real" "$h33r_dir/scripts/lib/walls.sh")"
rm -f "$h33r_dir/scripts/lib/walls.sh.real"
_real_hook="$HOOK"; HOOK="$h33r_dir/hooks/loose-gate.sh"
expect_block "33b-rev the same home against a gate whose deferral never defers → block, on the verdict it owes" \
  "$h33b" 'git commit -m "x"' "the auditor has not confirmed AC-2"
HOOK="$_real_hook"

h33c=$(make_home)
write_plan "$h33c" "$(plan 6 "$step6_body" "$m33_waived_block")" > /dev/null
expect_allow "33c the waiver as an AC-block line (not the evidence cell) → allow too" \
  "$h33c" 'git commit -m "x"'

# Anchored on 'task: 9' alone: the pattern half of a ${var/pattern/replacement} ends at its
# own first '/', so an anchor spanning a path-bearing line would truncate and garble both halves.
m33_waived_prov="${m33_waived/  task: 9/  task: 9
  provenance: implementation}"
h33d=$(make_home)
write_plan "$h33d" "$(plan 6 "$step6_body" "$m33_waived_prov")" > /dev/null
expect_block "33d control: a waived row still meets the provenance arm above it" \
  "$h33d" 'git commit -m "x"' "provenance: implementation"

# ============================================================
# Section 34: the session never invoked the skill (AC-6)
# ============================================================
#
# THE PAIRED WORLD for every section above. Chris, 2026-09-03: "all guardrails imposed
# by bionic should only apply when exercising bionic. Nothing should apply until bionic
# is triggered." The trigger is the canonical-sdlc skill and the record of it is
# `.bionic/tmp/engaged-<sid>.state` under the project root; every fixture above carries
# one because every fixture above describes a run somebody started. Take it away and this
# gate is not quieter, it is absent: exit 0, nothing on stdout, nothing on stderr.
#
# EACH ARM IS A COMMIT THIS GATE REFUSES TWO LINES LATER, on the identical fixture with
# the marker restored — the control is what stops the whole section passing on a gate
# that had simply stopped working.
#
# THE ORDERING CONTRACT IS UNCHANGED BY THIS. Plan hygiene still sits above the run
# predicate, so an ENGAGED session committing against a malformed plan is still refused
# whether or not a run is open (34b's control). What the guard adds is prior to both
# questions, not a fourth clause inside either.

section "Section 34: no engagement marker — the gate is not there at all"

# Captures stdout as well as stderr and the exit code: "silent" here means all three.
run_hook_full() {  # <home> <command> -> S34_EXIT / S34_OUT / S34_ERR
  local home_dir="$1" command="$2" input tmp_err tmp_out
  input=$(jq -n --arg c "$command" --arg cwd "$home_dir" --arg s "$EG_SID" \
            '{session_id: $s, tool_input: {command: $c}, cwd: $cwd}')
  tmp_err=$(mktemp); tmp_out=$(mktemp)
  eg_autobind "$home_dir"
  if HOME="$home_dir" CLAUDE_PROJECT_DIR="" CLAUDE_CODE_SESSION_ID="$EG_SID" \
       bash "$HOOK" <<< "$input" >"$tmp_out" 2>"$tmp_err"; then
    S34_EXIT=0
  else
    S34_EXIT=$?
  fi
  S34_OUT=$(cat "$tmp_out"); S34_ERR=$(cat "$tmp_err")
  rm -f "$tmp_err" "$tmp_out"
}

expect_silent() {  # <label> — asserts on the last run_hook_full
  if [ "$S34_EXIT" -eq 0 ] && [ -z "$S34_OUT" ] && [ -z "$S34_ERR" ]; then
    ok "$1"
  else
    no "$1" "expected exit 0 and total silence; got exit=$S34_EXIT stdout='$S34_OUT' stderr='$S34_ERR'"
  fi
}

expect_refused() {  # <label> — the control: the SAME fixture, marker restored
  expect_eq "$1" 2 "$S34_EXIT"
}

# --- 34a: an open run whose current step has no evidence — the gate's core refusal ---
h34a=$(make_home)
write_plan "$h34a" "$(plan 5 "" "$matrix_complete")" > /dev/null
unengage "$h34a"
run_hook_full "$h34a" 'git commit -m "x"'
expect_silent "34a an empty Step 5 line passes an unengaged session"
engage "$h34a"
run_hook_full "$h34a" 'git commit -m "x"'
expect_refused "34a control: the same commit, marker restored, is REFUSED"

# --- 34b: PLAN HYGIENE, the half that sits ABOVE the run predicate ---
# A plan with no readable `current:` is refused whether or not a run is open, because a
# plan that lies is a defect in every state. That refusal is owed to an ENGAGED session
# and to nobody else.
h34b=$(make_home)
printf -- '---\ngoverning-skill: canonical-sdlc\ncanonical_sdlc_version: 14\nintent: build\nrigor: single\nscale: wave\n---\n\n## SDLC State\ncurrent: banana\n' \
  > "$h34b/.bionic/docs/plans/active.md"
touch "$h34b/.bionic/docs/plans/active.md"
unengage "$h34b"
run_hook_full "$h34b" 'git commit -m "x"'
expect_silent "34b a malformed 'current:' passes an unengaged session"
engage "$h34b"
run_hook_full "$h34b" 'git commit -m "x"'
expect_refused "34b control: plan hygiene still refuses the ENGAGED session"

# --- 34c: the misplacement sweep, which needs no open run either ---
h34c=$(make_home)
p34c=$(mktemp -d); cleanup_dirs+=("$p34c")
mkdir -p "$p34c/docs/bionic/plans/epic-01-demo"
s24_marked_plan > "$p34c/docs/bionic/plans/epic-01-demo/wave-01-x.plan.md"
run_hook_with_project "$h34c" "$p34c" 'git commit -m "x"'
if [ "$HOOK_EXIT" -eq 0 ] && [ -z "$HOOK_STDERR" ]; then
  ok "34c the misplacement sweep does not fire in an unengaged session"
else
  no "34c the misplacement sweep does not fire in an unengaged session" "expected allow; exit=$HOOK_EXIT stderr='$HOOK_STDERR'"
fi
engage "$p34c"
run_hook_with_project "$h34c" "$p34c" 'git commit -m "x"'
if [ "$HOOK_EXIT" -eq 2 ] && grep -q "misplaced" <<<"$HOOK_VSTDERR"; then
  ok "34c control: the same tree, marker planted, is REFUSED as misplaced"
else
  no "34c control: the same tree, marker planted, is REFUSED as misplaced" "expected block; exit=$HOOK_EXIT stderr='$HOOK_STDERR'"
fi

# --- 34d: the shapes that are NOT engagement, on a fixture that otherwise refuses ---
h34d=$(make_home)
write_plan "$h34d" "$(plan 5 "" "$matrix_complete")" > /dev/null

# A SYMLINK at the marker path is refused before it is followed (lib/run.sh), so a link
# into an engaged tree cannot open this gate from outside it.
unengage "$h34d"
ln -s "$h34a/.bionic/tmp/engaged-$EG_SID.state" "$h34d/.bionic/tmp/engaged-$EG_SID.state"
run_hook_full "$h34d" 'git commit -m "x"'
expect_silent "34d a SYMLINK at the marker path is not engagement"
rm -f "$h34d/.bionic/tmp/engaged-$EG_SID.state"

# ANOTHER SESSION'S marker is not this session's: the path interpolates the key.
: > "$h34d/.bionic/tmp/engaged-99999999-8888-7777-6666-555555555555.state"
run_hook_full "$h34d" 'git commit -m "x"'
expect_silent "34d another session's marker is not engagement"

# A DIRECTORY at the marker path is not a regular file.
mkdir -p "$h34d/.bionic/tmp/engaged-$EG_SID.state"
run_hook_full "$h34d" 'git commit -m "x"'
expect_silent "34d a DIRECTORY at the marker path is not engagement"
rmdir "$h34d/.bionic/tmp/engaged-$EG_SID.state"

# ============================================================
# Section 35: THE SESSION'S OWN RUN (wave-session-bound-run, AC-1/AC-3/AC-6)
# ============================================================
#
# Until 2026-09-04 this gate answered "which run am I in" by scanning the project root
# for the newest plan carrying `## SDLC State`. Two engaged sessions in one repository
# therefore shared one run identity: a commit from EITHER was measured against whichever
# plan was newest, so the second session's own evidence was never the evidence checked.
# The resolution is session-keyed now — lib/run.sh's `session_run` reads the `plan=`
# field hooks/engage.sh has written into `engaged-<sid>.state` since 1.4.1 and nothing
# read — and both of this hook's resolution sites take its verdict.
#
# EVERY FIXTURE HERE IS ONE ROOT WITH TWO OPEN PLANS, and that is the point: it is the
# only shape in which the old rule and the new one disagree. A one-plan root cannot tell
# them apart, so a section built on one would pass under either and prove nothing.
#
# THE TWO DIRECTIONS ARE BOTH DRIVEN (35a and 35b). "The bound session is gated on its
# own plan" is only half an assertion if the bound plan is also the newest one — the old
# rule agrees there. 35b swaps which plan carries the evidence, so the bound session
# blocks on the OLDER plan while the newest one is clean, which the old rule cannot do.

# ============================================================
section "§ORDER-VERB, §WHOLE-RUN, §FIX-ROW, §APPROVED-HEAD — build, regression, review, release, approval, merge, through the verbs"
# ============================================================
# FIXTURE FIDELITY: one real repository; tests/run.sh is a fixture runner printing the real runner's verdict lines (a suite
# is green unless tests/red names it); the plan is bound to this session and hooks/session-poker.sh runs as it. The proofs
# and landing lines are written in their writers' shapes; the judge reads text whatever wrote it. fails-when: a regression
# runs beside an open build row or twice at one head, a fixed red asks a second whole run, or current 8 passes at a head the user did not approve.
OD_SID="6e7f8091-2a3b-4c4d-9e0f-1a2b3c4d5e6f"; OD_LIB="${BIONIC_HOOKS_DIR}/../payload/scripts/lib"
OD_ROOT="$(mktemp -d)"; cleanup_dirs+=("$OD_ROOT"); OD="$(cd "$OD_ROOT" && pwd -P)/repo"
OD_RL="record/wave-01-fixture"; OD_REC="$OD/.bionic/docs/$OD_RL"; OD_PLAN="$OD/.bionic/docs/plans/epic-99-fixture/wave-01-fixture.plan.md"
mkdir -p "$OD/.bionic/tmp" "$OD_REC" "${OD_PLAN%/*}" "$OD/.bionic/docs/specs/epic-99-fixture" "$OD/tests" "$OD/lib"
od_git() { git -C "$OD" -c user.email=dana@fixture.test "$@"; }
od_git init -q; od_git config user.name "Dana Fixture"; od_git checkout -q -b wave/01-fixture
printf '.bionic/\n' > "$OD/.gitignore"; printf 'one\n' > "$OD/lib/b.sh"; : > "$OD/tests/red"
printf 'true\n' > "$OD/tests/a.test.sh"; printf 'true\n' > "$OD/tests/b.test.sh"
cat > "$OD/tests/run.sh" <<'OD_RUN'
#!/bin/bash
cd "$(dirname "$0")" || exit 1
p=0; f=0; bad=""; printf 'Gating suites: a.test.sh b.test.sh\n'
for s in a.test.sh b.test.sh; do
  if grep -qx "$s" red; then printf '  %s  ✗ FAIL\n' "$s"; f=$((f + 1)); bad="$bad    - $s"$'\n'; else printf '  %s  ✓ PASS\n' "$s"; p=$((p + 1)); fi
done
printf 'Gating: %s passed, %s failed\n' "$p" "$f"; [ "$f" -eq 0 ] && exit 0; printf 'Failed:\n%s' "$bad"; exit 1
OD_RUN
od_git add -A; od_git commit -qm base; OD_B="$(od_git rev-parse HEAD)"
: > "$OD/.bionic/tmp/engaged-$OD_SID.state"
printf '# r\n' > "$OD/.bionic/docs/specs/epic-99-fixture/wave-01-fixture.requirements.md"
printf '# s\n' > "$OD/.bionic/docs/specs/epic-99-fixture/wave-01-fixture.spec.md"
for od_f in dispatch audit review docs generic-evidence; do printf 'fixture evidence\n' > "$OD_REC/$od_f.md"; done
od_row() { printf '| %s | %s | %s | %s | %s | — | 30 | REQ-1 | %s | — | — | %s | %s |\n' "$@"; }  # id step kind task agent Files status reads
od_plan() {  # <current> <SDLC lines> <row>... -> OD_PLAN, bound to this session
  local cur="$1" sd="$2"; shift 2
  { printf -- '---\ngoverning-skill: canonical-sdlc\ncanonical_sdlc_version: 14\nintent: build\nrigor: double\nscale: wave\n'
    printf 'deploy_target: none\nuse_worktree: false\nhas_ui: false\nwalk: exempt\n---\n# plan\n\n## SDLC State\n\n'
    printf 'current: %s\nworking-branch: wave/01-fixture\nintegration-branch: main\napproved-by: fixture 2026-09-22T00:00Z approved\n' "$cur"
    printf -- '- Step 1: requirements: specs/epic-99-fixture/wave-01-fixture.requirements.md\n- Step 2: spec: specs/epic-99-fixture/wave-01-fixture.spec.md\n'
    printf -- '- Step 3: plan: plans/epic-99-fixture/wave-01-fixture.plan.md\n'
    printf -- '- Step 4: dispatched, %s/dispatch.md\n  worktree: .\n  base-sha: %s\n  branch: wave/01-fixture\n- T1: landed at %s/dispatch.md\n' "$OD_RL" "$OD_B" "$OD_RL"
    [ -z "$sd" ] || printf '%s\n' "$sd"
    printf '\n## Tasks\n\n| id | step | kind | task | agent | deps | size | serves | Files | worktree | base | status | reads |\n'
    printf '|---|---|---|---|---|---|---|---|---|---|---|---|---|\n'; printf '%s\n' "$@"
    printf '\n## Verification Matrix\n\nstack-health: n/a: no long-running serve\n\n| AC | tier | status | evidence | auditor |\n|---|---|---|---|---|\n'
    printf '| AC-1.1 | T1 | discharged | see AC-1.1 | CONFIRMED |\n\nAC-1.1:\n  fails-when: the planted defect this eval must go red on\n'
    printf '  evidence: %s/generic-evidence.md\n  tier-run: bash tests/a.test.sh\n  readback: the line it wrote\n' "$OD_RL"
  } > "$OD_PLAN"
  bound_marker "$OD" "$OD_SID" "$OD_PLAN" >/dev/null 2>&1 || :
}
od_rows() {  # <T1 status> <T2 status> <T3 and T4 status> -> the order's rows: build, regression, review, release, integrate
  od_row T1 4 build 'the lib writer' implementor lib/b.sh "$1" 'approval:plan'
  od_row T2 5 test 'the whole regression' test-runner — "$2" 'approval:plan, head'
  od_row T3 6 review 'the critic' critic .bionic/docs/record/w/T3.md "$3" 'approval:plan, head'
  od_row T4 7 doc 'the release' implementor README.md "$3" 'approval:plan, head'
  od_row T5 8 integrate 'merge into main' orchestrator — pending 'approval:release, approval:merge, head'
}
od_poke() {  # <args...> -> OD_OUT, OD_RC: session-poker.sh as this session, in the repository
  OD_RC=0
  OD_OUT="$(cd "$OD" && env CLAUDE_CODE_SESSION_ID="$OD_SID" HOME="$OD_ROOT/home" CLAUDE_CONFIG_DIR="$OD_ROOT/config" \
    BIONIC_GATE_DIR="$OD_ROOT/gate" bash "${BIONIC_HOOKS_DIR}/session-poker.sh" "$@" 2>&1)" || OD_RC=$?
}
od_logs() { find "$OD_REC" -name 'regression-run-*.log' | wc -l | tr -d ' '; }
od_lrec() { bash -c '. "$1/line.sh" >/dev/null 2>&1 && line_record "$2"' _ "$OD_LIB" "$OD_PLAN" || printf '%s/none' "$OD_ROOT"; }
od_state() { bash -c '. "$1/roots.sh" 2>/dev/null; . "$1/proof.sh" && proof_state "$2" "$3"' _ "$OD_LIB" "$OD_PLAN" "$OD" 2>/dev/null | cut -f1; }

od_plan 4 '' "$(od_rows pending pending pending)"
cp "$OD_PLAN" "$OD_ROOT/before"
od_poke task-add T9 7 test 'a second regression. The suite runs again after the release.' test-runner — 90 REQ-1 .bionic/docs/record/w/T9.md 'approval:plan, head'
expect_eq "OV-1 AC-7.1 task-add of a regression row after the review and the release is refused (exit 1)" "1" "$OD_RC"
expect_eq "OV-1b …and the refusal is the validator's one line for T9, naming T3, the review row it follows" \
  'T9: the regression row comes after the review row T3; the order is build, regression, review, release: put T9 at step 5, ahead of T3' \
  "$(printf '%s\n' "$OD_OUT" | grep '^T9:' || :)"
expect_true "OV-1c …and the plan is byte-identical" cmp -s "$OD_ROOT/before" "$OD_PLAN"

od_plan 5 '' "$(od_rows pending pending pending)"
od_poke regression-run
expect_eq "WR-1 AC-6.1 a build row open: regression-run refuses (exit 1), and nothing ran" "1|0" "$OD_RC|$(od_logs)"
expect_contains "WR-1b …naming the open row" "T1 (step 4, pending)" "$OD_OUT"
od_plan 5 '' "$(od_rows landed pending pending)"
od_poke regression-run
expect_eq "WR-2 AC-6.1 every build row landed: one whole run at the head (exit 0, one log)" "0|1" "$OD_RC|$(od_logs)"
expect_eq "WR-2b …recording one verdict per suite at that commit" "2" "$(/usr/bin/grep -c "^line/v1|ev=verdict|row=regression|commit=$OD_B|" "$(od_lrec)" 2>/dev/null || :)"
od_poke regression-run
expect_eq "WR-3 AC-6.1 a second whole run at the same green head: refused (exit 1), no second log" "1|1" "$OD_RC|$(od_logs)"
expect_contains "WR-3b …saying the head has its whole run" "runs once at a head" "$OD_OUT"
od_poke proof-add regression "$OD_RL/regression-run-$OD_B.log"; printf 'notes\n' > "$OD/README.md"; od_git add README.md; od_git commit -qm 'docs only'
od_poke regression-run
expect_eq "WR-3c AC-1.4 one docs commit past the green whole run: refused (exit 1), no log written for the head" "1|1" "$OD_RC|$(od_logs)"
expect_contains "WR-3d …naming the pass at B, its log, and that nothing since moved code" "green at ${OD_B:0:8}, 1 landing since moved no code" "$OD_OUT"
expect_contains "WR-3e …and the full pass's log" "$OD_RL/regression-run-$OD_B.log" "$OD_OUT"
expect_contains "WR-3f …and the exit that lands code" "spawn-worktree.sh ready" "$OD_OUT"

printf 'b.test.sh\n' > "$OD/tests/red"; od_git commit -qam 'b breaks'; OD_H="$(od_git rev-parse HEAD)"
# A head past a whole run is run again: the verb is stopped only by the dirty tree planted here, the last refusal before the runner.
printf 'dirt\n' >> "$OD/lib/b.sh"
od_poke regression-run
od_git checkout -q -- lib/b.sh
expect_eq "FX-1 a new head H past the one whole run: regression-run is not refused as a second whole run; it reaches the dirty-tree check before the runner (exit 1, no log)" "1|1" "$OD_RC|$(od_logs)"
expect_contains "FX-1b …the refusal is the dirty tree's, the last one before the runner" "is dirty (dirty=1)" "$OD_OUT"
expect_absent "FX-1d …and no refusal names the whole run's head as having the run" "${OD_B:0:12} has it" "$OD_OUT"
expect_absent "FX-1e …nor the green pass: the code commit past B put the head out of its reach (the mutant of WR-3c)" "moved no code" "$OD_OUT"
# THE RED RUN THE PLAN'S WHOLE RUN WAS, left at H as the verb leaves one: the runner's report as the log's body, the run line and the per-suite facts through the product's writers.
OD_PLANT=0
(cd "$OD" && { bash tests/run.sh 2>&1 || :; }) | regression_fixture "$OD_PLAN" "$OD_REC/regression-run-$OD_H.log" "$OD_H" 0 1 || OD_PLANT=$?
bash -c '. "$1/proof.sh" && proof_regression_fold "$2" "$3" "$4" "$5" "$6"' _ "$OD_LIB" "$OD_PLAN" "$OD" "$OD_H" \
  "$OD_REC/regression-run-$OD_H.log" "$OD_RL/regression-run-$OD_H.log" || OD_PLANT=$((OD_PLANT + 10))
expect_eq "FX-1c precondition: the red run is left at H (both writers exit 0), its run line and its one red verdict in the record" "0|1|1" \
  "$OD_PLANT|$(/usr/bin/grep -c "^line/v1|ev=run|log=$OD_RL/regression-run-$OD_H.log|head=$OD_H|" "$(od_lrec)" || :)|$(/usr/bin/grep -c "^line/v1|ev=verdict|row=regression|commit=$OD_H|suite=b.test.sh|result=red|" "$(od_lrec)" || :)"
OD_FL="$(bash -c '. "$1/proof.sh" && proof_floor_line "$2" 2026-10-12T11:00:00Z "$3" b.test.sh' _ "$OD_LIB" "$OD_H" "$OD_RL/regression-run-$OD_H.log")"
od_plan 5 "$OD_FL" "$(od_rows landed landed pending)"
expect_eq "FX-1b precondition: the regression at H owes the red suite" "owed" "$(od_state)"
: > "$OD/tests/red"; printf 'two\n' > "$OD/lib/b.sh"; od_git commit -qam 'T6: the fix'; OD_C="$(od_git rev-parse HEAD)"
OD_S2="$(od_state)"
expect_true "FX-2 the fix commit C with no run of its own is not covered (FX-1b and FX-3 read the same extractor)" test -n "$OD_S2" -a "$OD_S2" != covered
{ printf 'line/v1|ev=ready|row=T6|suites=tests/a.test.sh,tests/b.test.sh|at=2026-10-12T12:00:00Z\n'
  printf 'line/v1|ev=published|row=T6|commit=%s|at=2026-10-12T12:10:00Z\n' "$OD_C"
  for od_s in a.test.sh b.test.sh; do
    printf 'line/v1|ev=verdict|row=T6|commit=%s|suite=%s|result=green|log=/fixture/T6.log|at=2026-10-12T12:05:00Z\n' "$OD_C" "$od_s"
  done; } >> "$(od_lrec)"
expect_eq "FX-3 AC-6.2 the fix row green on its own suite and the red one: the head is accepted" "covered" "$(od_state)"
printf 'dirt\n' >> "$OD/lib/b.sh"
od_poke regression-run
od_git checkout -q -- lib/b.sh
expect_eq "FX-4 …and a covered head C is run again: regression-run at C is not refused as proved; it reaches the dirty-tree check before the runner (exit 1, no log)" \
  "1|2" "$OD_RC|$(od_logs)"
expect_contains "FX-4b …the refusal is the dirty tree's, the last one before the runner" "is dirty (dirty=1)" "$OD_OUT"
expect_absent "FX-4c …and no refusal says the head is already proved" "is already proved" "$OD_OUT"
od_git checkout -q -b row/T7; printf 'three\n' > "$OD/lib/b.sh"; od_git commit -qam 'T7: a second fix'; OD_R="$(od_git rev-parse HEAD)"
od_git checkout -q wave/01-fixture; od_git merge -q --no-ff -m 'land T7 by hand' row/T7; OD_M="$(od_git rev-parse HEAD)"
OD_S3="$(od_state)"
expect_true "HL-1 a hand landing M with no verdict recorded is not covered (HL-2 reads the same extractor)" test -n "$OD_S3" -a "$OD_S3" != covered
printf 'line/v1|ev=verdict|row=T7|commit=%s|suite=b.test.sh|result=green|log=/fixture/T7.log|at=2026-10-12T12:20:00Z\n' "$OD_R" >> "$(od_lrec)"
expect_eq "HL-2 AC-6.2 …and covered by the row's green verdict keyed by the row head M brought in" "covered" "$(od_state)"
od_git checkout -q -b row/T8; printf 'eight\n' > "$OD/lib/b.sh"; od_git commit -qam 'T8: a third fix'; OD_R2="$(od_git rev-parse HEAD)"
od_git checkout -q wave/01-fixture; od_git merge -q --no-ff -m 'land T8 by hand' row/T8; OD_M2="$(od_git rev-parse HEAD)"
{ printf 'line/v1|ev=ready|row=T8|commit=%s|suites=none|at=2026-10-12T12:30:00Z\n' "$OD_R2"
  printf 'line/v1|ev=published|row=T8|commit=%s|kind=hand|by=Fixture|at=2026-10-12T12:31:00Z\n' "$OD_M2"; } >> "$(od_lrec)"
OD_S4="$(od_state)"
expect_true "HL-3 a hand landing whose ready says none, with no verdict recorded, is not covered (HL-4 reads the same extractor)" test -n "$OD_S4" -a "$OD_S4" != covered
printf 'line/v1|ev=verdict|row=T8|commit=%s|suite=b.test.sh|result=green|log=/fixture/T8.log|at=2026-10-12T12:32:00Z\n' "$OD_R2" >> "$(od_lrec)"
expect_eq "HL-4 …and covered once the verdicts the row recorded name a green suite at the row head" "covered" "$(od_state)"

printf '# fixture\n' > "$OD/README.md"; od_git add README.md; od_git commit -qm 'T4: the release'; OD_A="$(od_git rev-parse HEAD)"
od_reads() {  # the five readings a double wave plan is dealt, at A
  local q
  for q in evidence adversarial structure; do
    printf 'question: %s\nresult: pass\nscope: piece\nreviewed: %s..%s\nfindings: 0\n' "$q" "${OD_B:0:10}" "${OD_A:0:10}" > "$OD_REC/$q.md"
    bash -c '. "$1/proof.sh" && proof_line review "$2" 2026-10-12T13:00:00Z "$3" "$4" w-read pass piece' _ "$OD_LIB" "$OD_A" "$OD_RL/$q.md" "$q"
  done
  for q in adversarial structure; do
    printf 'question: %s\nresult: pass\nscope: whole\nreviewed: %s..%s\nfindings: 0\n' "$q" "${OD_B:0:10}" "${OD_A:0:10}" > "$OD_REC/$q-whole.md"
    bash -c '. "$1/proof.sh" && proof_line review "$2" 2026-10-12T13:00:00Z "$3" "$4" w-read pass whole' _ "$OD_LIB" "$OD_A" "$OD_RL/$q-whole.md" "$q"
  done
}
od_appr() { printf 'approved: release by Dana Fixture 2026-10-12T14:00:00Z head=%s "Ship it."' "$1"; }
od_s8() {  # <approval line> -> the plan at current: ${OD_S:-8}, every row but integrate landed
  local st
  st="$(printf -- '- Step 5: verified, %s/audit.md\n  auditor: CONFIRMED, %s/audit.md\n- Step 6: review at %s/review.md\n' "$OD_RL" "$OD_RL" "$OD_RL")"
  st="$st"$'\n'"$(printf -- '- Step 7: documented at %s/docs.md\n  n/a: no decision this run' "$OD_RL")"$'\n'"$OD_FL"$'\n'"$(od_reads)"
  od_plan "${OD_S:-8}" "${1:+$1$'\n'}$st" "$(od_rows landed landed landed)"$'\n'"$(od_row T6 5 build 'the fix' implementor lib/b.sh landed 'approval:plan')"$'\n'
}
od_s8 "$(od_appr "$OD_A")"
expect_eq "AH-0 precondition: the plan is in the order, the regression row named" "T2" \
  "$(bash -c '. "$1/units.sh" && units_order "$2"' _ "$OD_LIB" "$OD_PLAN" 2>/dev/null || :)"
od_poke current 8 --check
expect_eq "AH-1 approved head A, the working head A, the whole run at H with C fixed on its suites: refused as regression unproved, naming both exits" "1|yes" \
  "$OD_RC|$(printf '%s\n' "$OD_OUT" | /usr/bin/grep -q 'regression.*unproved' && printf '%s\n' "$OD_OUT" | /usr/bin/grep -q 'reply .* on the release card' && echo yes || echo no)"
od_mu() { printf 'approved: merge-unproved by chris 2026-10-26T00:00:00Z head=%s "merge"' "$1"; }  # the merge approval, at the head it names
od_s8 "$(od_appr "$OD_A")"$'\n'"$(od_mu "$OD_A")"; od_poke current 8 --check
expect_eq "AH-1b …and with the person's merge-unproved word at head A beside it: passes" "0" "$OD_RC"
od_s8 "$(od_appr "$OD_A")"$'\n'"$(od_mu "$OD_C")"; od_poke current 8 --check
expect_eq "AH-1c …the same word naming a head that is not A leaves it refused" "1" "$OD_RC"
# §EXIT7: the unproved exit is the step's. At 7 no release card can exist yet, so the exit is the pass; at 8 it is the card's reply, and a
# docs head past the whole run is admitted at 7. fails-when: current 7 over an unproved head names a reply or a release card, current 8
# stops naming the reply, or a docs commit past the run draws a refusal at 7.
OD_N7='needs: the pass — wait for it (the tick starts it once no row is ready), or start it: session-poker.sh regression-run'
od_x7() { OD_FL="$2" OD_S=$(($1 - 1)) od_s8 "$(od_appr "$OD_A")"; od_poke current "$1" --check; }  # <step> <floor line> -> the plan one step before it, asked for <step>
od_rg() { printf '%s\n' "$OD_OUT" | /usr/bin/grep 'regression.*unproved' | awk -F'\t' '{ print $NF }'; }
od_x7 7 "$OD_FL"
expect_eq "X7-1 AC-2.1 current 7 over the unproved head A: refused, the exit is the pass and names no reply and no release card" "1|$OD_N7|0" \
  "$OD_RC|$(od_rg)|$(od_rg | /usr/bin/grep -ciE 'reply|release card' || :)"
od_x7 8 "$OD_FL"
expect_eq "X7-2 AC-2.2 current 8 at the same head: refused, the exit is the card's reply, as before" \
  "1|needs: the user — reply <n> on the release card (merge without a whole run at this head), or wait for the pass" "$OD_RC|$(od_rg)"
printf 'notes\n' >> "$OD/README.md"; od_git commit -qam 'a docs commit past the pass'
od_x7 7 "$(bash -c '. "$1/proof.sh" && proof_floor_line "$2" 2026-10-12T11:30:00Z "$3"' _ "$OD_LIB" "$OD_A" "$OD_RL/regression-run-$OD_H.log")"
expect_eq "X7-3 AC-2.3 the pass at A and one docs commit past it: current 7 admitted (exit 0), no regression unproved" "0|" "$OD_RC|$(od_rg)"
od_git reset -q --hard "$OD_A"

od_s8 "$(od_appr "$OD_C")"
od_poke current 8 --check
expect_eq "AH-2 AC-7.2 approved head C, the working head A: current 8 --check refuses (exit 1)" "1" "$OD_RC"
od_s8 'approved: release by Dana Fixture 2026-10-12T14:00:00Z "Ship it."'
od_poke current 8 --check
expect_eq "AH-3 an approval line that names no head: refused (exit 1), saying so" "1|yes" \
  "$OD_RC|$(printf '%s\n' "$OD_OUT" | /usr/bin/grep -q "names no head" && echo yes || echo no)"
od_s8 ''
od_poke current 8 --check
expect_eq "AH-4 no approved: release line: refused (exit 1), naming the verb that writes it" "1|yes" \
  "$OD_RC|$(printf '%s\n' "$OD_OUT" | /usr/bin/grep -q "approve release" && echo yes || echo no)"

# A WHOLE RUN AT AN ANCESTOR IS CITED THROUGH proof-add AS THE JUDGE JUDGES IT: the verb accepts the log at the head A
# where the judge says covered, and a later commit no run proves is refused by that commit, not by "a whole run".
od_plan 5 '' "$(od_rows landed landed pending)"
od_poke proof-add regression "$OD_RL/regression-run-$OD_H.log"
expect_eq "PA-1 a whole run at ancestor H, every commit since proved or excused: proof-add accepts it (exit 0), and the head is covered" \
  "0|covered" "$OD_RC|$(od_state)"
printf 'four\n' > "$OD/lib/b.sh"; od_git commit -qam 'a change no run proves'; OD_D="$(od_git rev-parse HEAD)"
od_plan 5 '' "$(od_rows landed landed pending)"
od_poke proof-add regression "$OD_RL/regression-run-$OD_H.log"
expect_eq "PA-2 …and one commit later that no landing proves: refused (exit 1), naming that commit and that it is not proved" "1|yes" \
  "$OD_RC|$(printf '%s\n' "$OD_OUT" | /usr/bin/grep -q "commit ${OD_D:0:12} .*is not proved" && echo yes || echo no)"
expect_absent "PA-2b …and the same refusal offers no second whole run (the positive above reads this output)" "run the whole" "$OD_OUT"

section "§DRY-ORIGIN — a plan verb's dry commit of a copy judges the reader rule on the origin's landing record, as a commit of the plan does"
# ============================================================
# FIXTURE FIDELITY: the order fixture's repository and plan builder above; the copy is named the way a plan verb names
# it, `<plan>.task-add-dry.<pid>`, bound under `planverb-<pid>` by a marker carrying `plan=<copy>` and, when the verb
# wrote it, `dry_of=<plan>`; the commit goes through bash-walls.sh as the verb sends it. The plan holds a landed release
# row, a fix row born at step 4 and published after it, and a review row at step 7 that reads the fix row's record: the
# reader rule admits it by the landing record's publish order and refuses it by the plan's order.
# fails-when: a dry commit of such a copy is refused by plan order although the origin's record published the fix row
# after the release, or the copy with no `dry_of=` is admitted.
OD_DPID=4343
OD_DCOPY="$OD_PLAN.task-add-dry.$OD_DPID"; OD_DMARK="$OD/.bionic/tmp/engaged-planverb-$OD_DPID.state"
od_dry() {  # <dry_of plan, or empty for a marker with none> -> OD_OUT, OD_RC: the copy's dry commit through the gate
  local sid="planverb-$OD_DPID"
  # the ledger arm judges only a plan that declares multi_agent, and a step-4 plan reaches it only when it declares a
  # worktree: the order fixture's frontmatter declares neither
  sed -e 's/^scale: wave$/scale: wave\nmulti_agent: true/' -e 's/^use_worktree: false$/use_worktree: true/' "$OD_PLAN" > "$OD_DCOPY"
  { printf 'plan=%s\n' "$OD_DCOPY"; [ -z "$1" ] || printf 'dry_of=%s\n' "$1"; printf 'engaged_at=2026-10-12T00:00:00Z\n'; } > "$OD_DMARK"
  OD_RC=0
  OD_OUT="$(cd "$OD" && env CLAUDE_PROJECT_DIR="" CLAUDE_CODE_SESSION_ID="$sid" HOME="$OD_ROOT/home" CLAUDE_CONFIG_DIR="$OD_ROOT/config" \
    BIONIC_GATE_DIR="$OD_ROOT/gate" BIONIC_WALL_VERBOSE=1 bash "$HOOK" 2>&1 >/dev/null <<< "$(jq -n --arg s "$sid" --arg cwd "$OD" \
      '{session_id: $s, cwd: $cwd, hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: "git commit -m task-add"}, tool_use_id: "toolu_dry"}')")" || OD_RC=$?
  rm -f "$OD_DCOPY" "$OD_DMARK"
}
od_dplan() {  # the order's rows with a fix row T6 born at step 4 and a review row T9 at step 7 reading its record
  od_plan 4 "$(printf -- '- T2: landed at %s/dispatch.md\n- T3: landed at %s/dispatch.md\n- T4: landed at %s/dispatch.md\n- T6: landed at %s/dispatch.md' "$OD_RL" "$OD_RL" "$OD_RL" "$OD_RL")" \
    "$(od_rows landed landed landed)" \
    "$(od_row T6 4 build 'the fix born at step 4' implementor 'lib/b.sh, .bionic/docs/record/w/T6.md' landed 'approval:plan')" \
    "$(od_row T9 7 review 'the critic reads the fix as a piece' critic .bionic/docs/record/w/T9.md pending 'approval:plan, head, .bionic/docs/record/w/T6.md')"
}
od_dpub() {  # <row>... -> the landing record: a published event for each row, in the order given
  : > "$(od_lrec)"
  local r
  for r in "$@"; do printf 'line/v1|ev=published|row=%s|commit=%s|kind=queue|by=-|why=-|at=2026-10-12T00:00:00Z\n' "$r" "$OD_B" >> "$(od_lrec)"; done
}
DO_ORD='T4: the release row comes ahead of the review row T9'
od_dplan; od_dpub T1 T2 T3 T4 T6
od_dry "$OD_PLAN"
expect_eq "DO-1 AC-15.1 the dry commit of the copy, dry_of= naming the plan whose record published the fix row T6 after the release T4: the reader rule admits T9 (exit 0)" "0" "$OD_RC"
expect_absent "DO-1b …and the order refusal is not printed (the refusal below reads the same output)" "$DO_ORD" "$OD_OUT"
od_dry ""
expect_eq "DO-2 the same copy under a marker with no dry_of=: refused (exit 2) by plan order, the copy naming no record" "2" "$OD_RC"
expect_contains "DO-2b …and the refusal is the reader rule's order text for T9 the plan-order judgment prints" "$DO_ORD" "$OD_OUT"
od_dpub T1 T2 T3 T6 T4
od_dry "$OD_PLAN"
expect_eq "DO-3 dry_of= naming a plan whose record published the fix row BEFORE the release: refused (exit 2), as a commit of the plan is" "2" "$OD_RC"
expect_contains "DO-3b …with the order text" "$DO_ORD" "$OD_OUT"

finish
