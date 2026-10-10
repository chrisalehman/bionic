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
. "$(dirname "$0")/lib/bound-marker.sh"
. "$(dirname "$0")/lib/roster-row.sh"

# THE SEAM IS hooks/bash-walls.sh (epic-23 wave-11-lean-spine, T23). This wall is a
# FUNCTION now — `wall_evidence_gate` in payload/scripts/lib/walls.sh — registered through
# the one PreToolUse|Bash command object that carries all five. Every case below drives
# that process, which is what a Bash tool call actually starts; the wall's own verdict is
# unchanged and tests/bash-walls.test.sh owns the composition the process adds.
HOOK="${BIONIC_HOOKS_DIR}/bash-walls.sh"

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
expect_block "29b Step 9 without delivered: → block naming the key" \
  "$h29b" 'git commit -m "x"' "delivered"

# 29c — a named live surface: delivered + the full trio → allow.
h29c=$(make_home)
write_plan "$h29c" "$(ship_plan local-harness "$ship_delivered
$ship_trio")" > /dev/null

# 29d — a named live surface with `delivered:` only → block, naming what the
# named target owes.
h29d=$(make_home)
write_plan "$h29d" "$(ship_plan local-harness "$ship_delivered")" > /dev/null
expect_block "29d Step 9, deploy_target named, trio missing → block" \
  "$h29d" 'git commit -m "x"' "deployed"

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
expect_block "29f Step 9 in the retired v13 shape → block on delivered" \
  "$h29f" 'git commit -m "x"' "delivered"

# 29g — `n/a:` was v13's escape at deploy_target: none. Under v14 there is
# nothing to escape: the run still has to name what it delivered.
h29g=$(make_home)
write_plan "$h29g" "$(ship_plan none "  n/a: nothing to deploy")" > /dev/null
expect_block "29g Step 9 with the retired 'n/a:' escape → block on delivered" \
  "$h29g" 'git commit -m "x"' "delivered"

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
write_plan "$h30a" "$(wave_plan 6 "$step6_body" "$(t4_matrix T4 "" "$GOOD_CONFIRM")")" > /dev/null

# 30b — an agent-shaped claim: no attributed human, no date. Still refused.
h30b=$(make_home)
write_plan "$h30b" "$(wave_plan 6 "$step6_body" \
  "$(t4_matrix T4 "" "confirmed by the implementor agent after the re-render")")" > /dev/null
expect_block "30b T4 + agent-shaped user-confirmed → block (no attributed user)" \
  "$h30b" 'git commit -m "x"' "CONFIRMED"

# 30c — a date with nobody attached is not an attribution either.
h30c=$(make_home)
write_plan "$h30c" "$(wave_plan 6 "$step6_body" \
  "$(t4_matrix T4 "" "2026-08-18 the wall renders as specified")")" > /dev/null
expect_block "30c T4 + dated but unattributed user-confirmed → block" \
  "$h30c" 'git commit -m "x"' "CONFIRMED"

# 30d — the exemption is T4-scoped. A T3 row cannot buy its way past the
# auditor by writing a user's name into its block: T3's evidence is a live
# reading an auditor CAN re-take independently, so the verdict still stands.
h30d=$(make_home)
write_plan "$h30d" "$(wave_plan 6 "$step6_body" "$(t4_matrix T3 "" "$GOOD_CONFIRM")")" > /dev/null
expect_block "30d T3 + well-formed user-confirmed → block (exemption is T4-only)" \
  "$h30d" 'git commit -m "x"' "CONFIRMED"

# 30e — no regression: a T4 row an auditor DID confirm still passes.
h30e=$(make_home)
write_plan "$h30e" "$(wave_plan 6 "$step6_body" "$(t4_matrix T4 CONFIRMED "$GOOD_CONFIRM")")" > /dev/null
expect_allow "30e T4 + CONFIRMED auditor cell → allow (unchanged)" \
  "$h30e" 'git commit -m "x"'

# 30f — pinned scope boundary: the form check lives in the post-Verify arm
# only. At current: 5 the row is still being discharged and the contract there
# is the one it always was — `user-confirmed` present, non-empty, not a
# placeholder. An impostor value passes the VERIFY gate and meets the form
# check on the 5->6 advance, which is where the authority claim is actually
# made. Widening the check to Step 5 would false-block mid-discharge commits
# on plans written before this contract existed.
h30f=$(make_home)
write_plan "$h30f" "$(wave_plan 5 "$step5_base" \
  "$(t4_matrix T4 CONFIRMED "confirmed by the implementor agent")")" > /dev/null
expect_allow "30f impostor at current: 5 → allow (form check is post-Verify only)" \
  "$h30f" 'git commit -m "x"'

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
write_plan "$h30h" "$(wave_plan 6 "$step6_body" "$(t4_matrix T4 REFUTED "$GOOD_CONFIRM")")" > /dev/null
expect_block "30h T4 + well-formed user-confirmed + auditor REFUTED → block" \
  "$h30h" 'git commit -m "x"' "REFUTED"

# 30i — UNVERIFIABLE is the auditor's other positive finding: it says the
# evidence could not be checked, which is not the same as nobody having looked.
# Same arm, same reason.
h30i=$(make_home)
write_plan "$h30i" "$(wave_plan 6 "$step6_body" "$(t4_matrix T4 UNVERIFIABLE "$GOOD_CONFIRM")")" > /dev/null
expect_block "30i T4 + well-formed user-confirmed + auditor UNVERIFIABLE → block" \
  "$h30i" 'git commit -m "x"' "UNVERIFIABLE"

# (30j — an arm asserting the refusal SENTENCE ("does not overturn") on the same
# fixture 30h already blocks on — deleted at epic-18 W1: its only failure mode
# was a reworded message.)

# 30k — and the positive twin, so the pair discriminates: the SAME row with the
# SAME confirmation and a CONFIRMED verdict passes. (30e proves the well-formed
# + CONFIRMED case at the top of this section; this arm is stated beside its
# refutation twin so a future edit that broke the agreement case would fail
# next to the one that proves the refusal.)
h30k=$(make_home)
write_plan "$h30k" "$(wave_plan 6 "$step6_body" "$(t4_matrix T4 CONFIRMED "$GOOD_CONFIRM")")" > /dev/null

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
sed 's#user_confirmed_form_ok "\$block_txt"#[ -n "$(user_confirmed_value "$block_txt")" ]#' \
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
expect_block "30g meta: the T3 row still blocks under the loosened form (tier scope is a separate arm)" \
  "$h30d" 'git commit -m "x"' "CONFIRMED"
HOOK="$_real_hook"

# Restore-proof: the real hook still refuses the impostor after the detour.
expect_block "30g meta: the real hook still refuses the impostor after the mutation proof" \
  "$h30b" 'git commit -m "x"' "CONFIRMED"

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
expect_block "31a refusal on a call that also writes the plan → names the split" \
  "$h31a" "$cmd31a" "this command also writes the plan"

# 31a — the same refusal still names the row it refused (the note is an extra
# line, not a replacement).
expect_block "31a the split line does not displace the original refusal" \
  "$h31a" "$cmd31a" "AC-2"

# 31b — the project-relative spelling of the same path (what an agent actually
# types) is matched too.
h31b=$(make_home)
write_plan "$h31b" "$(plan 6 "$step6_body" "$v101_matrix_pending")" > /dev/null
expect_block "31b relative plan path in the command → names the split" \
  "$h31b" 'python3 -c "open('"'"'.bionic/docs/plans/active.md'"'"',\"a\")" && git commit -m "x"' \
  "this command also writes the plan"

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
expect_allow "31d naming the plan in an otherwise-clean commit → allow, silent" \
  "$h31d" "python3 -c \"open('$p31d','a')\" && git commit -m \"x\""

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
expect_allow "32a rigor single, rows discharged, auditor cells empty, current 6 → allow" \
  "$h32a" 'git commit -m "x"'

h32b=$(make_home)
write_plan "$h32b" "$(plan_rigor single 7 "$v9_step7_body" "$m32_empty_aud")" > /dev/null
expect_allow "32b same at current 7 → allow" "$h32b" 'git commit -m "x"'

h32c=$(make_home)
write_plan "$h32c" "$(plan_rigor single 8 "$v9_step8_body" "$m32_empty_aud")" > /dev/null
expect_allow "32c same at current 8 → allow" "$h32c" 'git commit -m "x"'

h32d=$(make_home)
write_plan "$h32d" "$(plan_rigor single 9 "$v9_step9_body" "$m32_empty_aud")" > /dev/null
expect_allow "32d same at current 9 → allow (B-10's own repro step)" \
  "$h32d" 'git commit -m "x"'

# 32e — the Step-5 `auditor:` pointer is the same wall one step earlier: it is
# demanded once no row is pending. At single there is no auditor to point at.
h32e=$(make_home)
write_plan "$h32e" "$(plan_rigor single 5 "$step5_noaud" "$m32_empty_aud")" > /dev/null
expect_allow "32e rigor single, all rows discharged, no Step-5 auditor: pointer → allow" \
  "$h32e" 'git commit -m "x"'

# 32f — the task-ledger mirror (AC-26, second half) is gone with the task ledger (wave-31 T24;
# D2): its `done` row at single, and 32k's row raised to double by its own cell, were the
# retired table at `current: T2`. That plan meets the numeric refusal now.
h32f=$(make_home)
write_plan "$h32f" "$(eg_pf_plan T2 task single false "- T2: fixed enum check, bash suite 12/12" "$(eg_pf_row T1 — landed)" "$(eg_pf_row T2 — active)")" > /dev/null
expect_block "32f 32f's and 32k's task plan at current: T2 → refused as not numeric" \
  "$h32f" 'git commit -m "x"' "current: T2 is not numeric"

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
expect_block "32g the same fixture at rigor double, current 6 → block (CONFIRMED)" \
  "$h32g" 'git commit -m "x"' "auditor verdict is 'empty', not CONFIRMED"

h32h=$(make_home)
write_plan "$h32h" "$(plan_rigor double 6 "$step6_body" "$m32_empty_aud")" > /dev/null
expect_block "32h the same fixture at rigor double, current 6 → block (CONFIRMED)" \
  "$h32h" 'git commit -m "x"' "auditor verdict is 'empty', not CONFIRMED"

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
expect_block "32m off-enum rigor 'reviewed' at current 6 → block on its rigor (a typo is not a bypass)" \
  "$h32m" 'git commit -m "x"' "this plan's rigor is not single or double"

# 32m2 — and the Step-5 pointer half fails closed too.
h32m2=$(make_home)
write_plan "$h32m2" "$(plan_rigor "" 5 "$step5_noaud" "$m32_empty_aud")" > /dev/null
expect_block "32m2 no rigor key at current 5, no auditor: pointer → block (fail closed)" \
  "$h32m2" 'git commit -m "x"' "requires 'auditor:"

# ============================================================
# Section 33: a waiver outranks the `task: 9` tier refusal (review-a C-2)
# ============================================================
#
# The `task: 9` tag (Section 17r) is T0-only: on any other tier it is a
# mis-tag, and the refusal fires at every step. That check sat ABOVE the
# `waiver:` exemption in the row loop, so a row an author had WAIVED — the
# criterion let go, its evidence contract dissolved — still met the tier
# refusal, and the only way past it was to retier a row nobody intends to
# discharge. A waiver outranks every other per-row demand in this loop (the
# per-tier keys, the CONFIRMED wall); it outranks this one too.
#
# The waiver test is the loop's existing one — a `waiver:` token in the
# evidence cell or a `waiver:` line in the AC block — so "waived" means the
# same thing here as it does for the per-tier keys three lines below.

section "Section 33: a waiver outranks the task: 9 tier refusal"

# A T1 row (not T0, so the tag is a mis-tag) carrying `task: 9`, WAIVED via
# the evidence cell. AC-1 is an ordinary discharged row so the matrix is
# otherwise complete and each verdict below is the waived row's doing.
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

# The waiver in the AC BLOCK rather than the evidence cell — the loop's other
# spelling of the same fact.
m33_waived_block="${m33_waived/| AC-2 | T1 | waived | waiver: dana 2026-08-30 criterion dropped | waived |/| AC-2 | T1 | waived | dropped, see block | waived |}"
m33_waived_block="${m33_waived_block/  task: 9/  task: 9
  waiver: dana 2026-08-30 criterion dropped}"

# 33a — waived T1 row carrying task: 9 → commits.
h33a=$(make_home)
write_plan "$h33a" "$(plan 6 "$step6_body" "$m33_waived")" > /dev/null
expect_allow "33a waived T1 row carrying 'task: 9' at current 6 → allow (waiver outranks)" \
  "$h33a" 'git commit -m "x"'

# 33b — the same row UNWAIVED still blocks on the mis-tag, so 33a is the
# waiver's doing and not the tier refusal having been deleted.
h33b=$(make_home)
write_plan "$h33b" "$(plan 6 "$step6_body" "$m33_unwaived")" > /dev/null
expect_block "33b control: the same T1 row unwaived still blocks on the mis-tag" \
  "$h33b" 'git commit -m "x"' "only a T0 row defers its evidence to the close-out"

# 33c — the block-line spelling of the waiver reads the same way.
h33c=$(make_home)
write_plan "$h33c" "$(plan 6 "$step6_body" "$m33_waived_block")" > /dev/null
expect_allow "33c the waiver as an AC-block line (not the evidence cell) → allow too" \
  "$h33c" 'git commit -m "x"'

# 33d — scope control: the waiver exempts the row from the TIER refusal, not
# from the loop's unconditional arms. The same waived row with a circular
# `provenance: implementation` still blocks — the provenance arm sits above
# both, deliberately, and this fix did not move it.
# Anchored on 'task: 9' alone (never a path-bearing line): the pattern half
# of a bash ${var/pattern/replacement} substitution ends at its own FIRST '/',
# so a pattern spanning the 'evidence: record/generic-evidence.md' line above
# would truncate there and garble both halves — this fixture proved that the
# hard way and moved the anchor to a slash-free line instead.
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

section "Section 35: two sessions, two plans, one root"

S35_SID_A="a1111111-2222-3333-4444-555555555555"
S35_SID_B="b6666666-7777-8888-9999-000000000000"

# A root that doubles as the sandbox HOME, the same trick make_home plays: the runner
# posts cwd=<root>, so PROJECT_DIR resolves there and the docs root is <root>/.bionic/docs.
s35_root() {
  local dir
  dir=$(mktemp -d)
  cleanup_dirs+=("$dir")
  # CANONICALISED, for the reason audit_file_for records: the hook resolves its root
  # through lib/root.sh, which answers with `pwd -P`, while macOS hands `mktemp -d` back a
  # path under the /var -> /private/var symlink unresolved. Every assertion below matches
  # an announced path CHARACTER FOR CHARACTER, so a fixture holding the other spelling of
  # one directory would fail on the prefix and pass on any substring — which is exactly
  # what a `/var/...` needle does against a `/private/var/...` haystack.
  dir=$(cd "$dir" && pwd -P)
  mkdir -p "$dir/.claude/plans" "$dir/.bionic/docs/plans" "$dir/.bionic/tmp"
  write_generic_evidence "$dir"
  echo "$dir"
}

# THE MARKER'S EXACT TWO-LINE SHAPE, hooks/engage.sh:287 — `plan=<path>` then
# `engaged_at=<iso>`, mode 600, written by the real `bind_plan` (S11,
# tests/lib/bound-marker.sh; spec AC-24). A fixture that invented a one-line marker
# would be testing a file no writer in the fleet produces.
s35_bind() {  # <root> <sid> <plan path>
  bound_marker "$1" "$2" "$3"
}

# The three shapes that are NOT a binding, all of which the fleet really produces: an
# EMPTY marker (tests/session-poker.test.sh:82 plants one, and every `engage` in THIS
# suite writes one), the literal `plan=none` (what engagement writes when the root holds
# zero or several open runs), and a marker carrying no `plan=` line at all.
s35_unbind() {  # <root> <sid> [empty|none|nofield]
  unbound_marker "$1" "$2" "${3:-empty}"
}

# Two open plans, structurally identical except for WHICH ONE carries the current step's
# evidence — the one variable this section turns. Sets S35_A and S35_B.
s35_two_plans() {  # <root> <a|b: which plan carries the evidence>
  local root="$1" with="$2" a_body="" b_body=""
  # FROM wave-27 T14 (D3) A STEP-6 COMMIT IS ADMITTED ON READINGS, not on the Step 6 line, so the
  # plan that "carries its evidence" carries the readings the run owes as well (eg_readings'
  # shape), and the other plan carries neither: still one variable, the plan's evidence.
  case "$with" in
    a) a_body="$step6_body
$(eg_readings 'current: 6' | sed 1d)" ;;
    b) b_body="$step6_body
$(eg_readings 'current: 6' | sed 1d)" ;;
  esac
  S35_A="$root/.bionic/docs/plans/wave-a.plan.md"
  S35_B="$root/.bionic/docs/plans/wave-b.plan.md"
  printf '%s\n' "$(plan 6 "$a_body" "$matrix_complete")" > "$S35_A"
  printf '%s\n' "$(plan 6 "$b_body" "$matrix_complete")" > "$S35_B"
  # B IS THE NEWEST, by an hour rather than a filesystem tick: `active_plan` orders by
  # mtime, and two plans written in the same second make the OLD rule's answer a coin
  # toss — which would make every fallback assertion below flap instead of fail.
  touch -t 202609040000 "$S35_A"
  touch -t 202609040100 "$S35_B"
}

# Runs the hook AS a named session. Unlike run_hook this keeps stderr WHOLE: the
# resolution announcements are this section's subject, not noise to filter past.
s35_run() {  # <root> <sid> <command> -> S35_EXIT / S35_ERR
  local root="$1" sid="$2" command="$3" input tmp_err
  input=$(jq -n --arg c "$command" --arg cwd "$root" --arg s "$sid" \
            '{session_id: $s, tool_input: {command: $c}, cwd: $cwd}')
  tmp_err=$(mktemp)
  if HOME="$root" CLAUDE_PROJECT_DIR="" CLAUDE_CODE_SESSION_ID="$sid" \
       bash "$HOOK" <<< "$input" >/dev/null 2>"$tmp_err"; then
    S35_EXIT=0
  else
    S35_EXIT=$?
  fi
  S35_ERR=$(cat "$tmp_err")
  # THE DETAIL STREAM (task 13, ruling D-1): this section greps plan PATHS off the
  # refusal, and a path is `detail` now. Gated on the refusal so an allowed commit is
  # never driven twice.
  # An ALLOWED call has no refusal to expand, and its announcements are already on the
  # ordinary stream — so the fallback is that stream, not an empty string.
  S35_VERR="$S35_ERR"
  if [ "$S35_EXIT" != "0" ]; then
    S35_VERR=$(HOME="$root" CLAUDE_PROJECT_DIR="" CLAUDE_CODE_SESSION_ID="$sid" \
      BIONIC_WALL_VERBOSE=1 bash "$HOOK" <<< "$input" 2>&1 >/dev/null || true)
  fi
  rm -f "$tmp_err"
}

# <label> <expected exit> <substring stderr MUST carry, or -> <substring it must NOT, or ->
s35_assert() {
  local label="$1" want="$2" yes="$3" nope="$4" why=""
  [ "$S35_EXIT" = "$want" ] || why="exit=$S35_EXIT want=$want"
  if [ -z "$why" ] && [ "$yes" != "-" ] && ! grep -qF -- "$yes" <<< "$S35_VERR"; then
    why="stderr is missing '$yes'"
  fi
  if [ -z "$why" ] && [ "$nope" != "-" ] && grep -qF -- "$nope" <<< "$S35_VERR"; then
    why="stderr carries '$nope' and must not"
  fi
  if [ -z "$why" ]; then
    ok "$label"
  else
    no "$label" "$why stderr='$S35_ERR'"
  fi
}

# --- 35a AC-1: each session is gated on its OWN plan (the evidence is on A) ---
r35a=$(s35_root)
s35_two_plans "$r35a" a
s35_bind "$r35a" "$S35_SID_A" "$S35_A"
s35_bind "$r35a" "$S35_SID_B" "$S35_B"

s35_run "$r35a" "$S35_SID_A" 'git commit -m "x"'
s35_assert "35a session A, bound to the plan that carries its evidence → allow" 0 - "BLOCKED"

s35_run "$r35a" "$S35_SID_B" 'git commit -m "x"'
s35_assert "35a session B, same tree same commit, bound to the plan with none → BLOCKED on B" \
  2 "$S35_B" "$S35_A"

# --- 35b AC-1, THE INVERSE: swap which plan carries the evidence ---
# The old newest-plan rule allows session A's commit here (the newest plan is clean) and
# blocks session B's (its own plan is not the one read). Both rows below are its mirror.
r35b=$(s35_root)
s35_two_plans "$r35b" b
s35_bind "$r35b" "$S35_SID_A" "$S35_A"
s35_bind "$r35b" "$S35_SID_B" "$S35_B"

s35_run "$r35b" "$S35_SID_A" 'git commit -m "x"'
s35_assert "35b inverse: session A blocks on its OWN older plan while the newest is clean" \
  2 "$S35_A" "$S35_B"

s35_run "$r35b" "$S35_SID_B" 'git commit -m "x"'
s35_assert "35b inverse: session B, bound to the newest plan that carries its evidence → allow" \
  0 - "BLOCKED"

# --- 35c AC-3, as amended by wave-23-fixit-1810 (REQ-1, D1): no binding → the newest
# plan is announced and never acted on. The commit is NOT gated on B (which carries no
# evidence and used to refuse it), A is never read, and the hook says which plan it would
# have been, in lib/run.sh's one sentence. 35c3 below is the same tree bound to B: refused,
# so the allow here is the binding's doing and not a gate gone quiet.
for s35_shape in empty none nofield; do
  r35c=$(s35_root)
  s35_two_plans "$r35c" a          # the evidence is on A, so the NEWEST plan has none
  s35_unbind "$r35c" "$S35_SID_A" "$s35_shape"
  s35_run "$r35c" "$S35_SID_A" 'git commit -m "x"'
  s35_assert "35c unbound ($s35_shape) → the newest plan is announced and never acted on: allowed" \
    0 - "BLOCKED"
  s35_assert "35c unbound ($s35_shape) → and lib/run.sh's one advisory names B" \
    0 "run resolved by newest-plan fallback (session unbound) — $S35_B; bind with session-poker.sh bind $S35_B, or write this session's plan" "$S35_A"
done
r35c3=$(s35_root)
s35_two_plans "$r35c3" a
s35_bind "$r35c3" "$S35_SID_A" "$S35_B"
s35_run "$r35c3" "$S35_SID_A" 'git commit -m "x"'
s35_assert "35c3 control: the same tree BOUND to B is gated on B and refused" 2 "$S35_B" -

# THE NEGATIVE BESIDE THE POSITIVE: a BOUND session announces no fallback, because it
# did not use one. Without this row the announcement could be unconditional and every
# assertion above would still pass.
r35c2=$(s35_root)
s35_two_plans "$r35c2" a
s35_bind "$r35c2" "$S35_SID_A" "$S35_A"
s35_run "$r35c2" "$S35_SID_A" 'git commit -m "x"'
s35_assert "35c control: a BOUND session announces no fallback" 0 - "newest-plan fallback"

# --- 35d AC-6: a binding to a CLOSED plan is engaged-with-no-run, never a fall-through ---
r35d=$(s35_root)
s35_two_plans "$r35d" a            # B is newest, open, and carries no evidence
S35_D="$r35d/.bionic/docs/plans/wave-delivered.plan.md"
printf '%s\n## SDLC State\ncurrent: 9\napproved-by: fixture 2026-09-07T00:00Z approved\n- Step 9: delivered: .bionic/docs/record/x.md\n\n%s\n' \
  "$(matrix_frontmatter true)" "$matrix_complete" > "$S35_D"
touch -t 202609040030 "$S35_D"
s35_bind "$r35d" "$S35_SID_A" "$S35_D"
s35_run "$r35d" "$S35_SID_A" 'git commit -m "x"'
s35_assert "35d bound to a DELIVERED plan → this session has no open run: allow" 0 - "BLOCKED"
s35_assert "35d …and the reason is named, with the closed plan's own path" \
  0 "evidence-gate: bound plan closed — $S35_D; this session has no open run" -
s35_assert "35d …and the OPEN plan beside it is never read" 0 - "$S35_B"

# The control: the same tree and the same commit from a session BOUND to the open plan IS
# gated on it. Without it 35d's silence could be a gate that had simply stopped. (It was an
# UNBOUND session until wave-23-fixit-1810; an unbound session's fallback plan is announced
# and never acted on now, 35c.)
s35_bind "$r35d" "$S35_SID_B" "$S35_B"
s35_run "$r35d" "$S35_SID_B" 'git commit -m "x"'
s35_assert "35d control: the same tree, a session bound to the open plan, is gated on it" \
  2 "$S35_B" -

# --- 35f AC-1 at the OTHER site: the run predicate is the session's too ---
# 35a and 35b turn the site that picks the file to VALIDATE; both of their plans are open,
# so the site that decides whether a run is live agrees under either rule and is not under
# test there. Here the session's own plan is open and the root's NEWEST plan is delivered,
# which is the shape where the two sites disagree: the old root-keyed predicate reads the
# root as having no run at all and waves the commit through, while the session in fact has
# an open run with no evidence for its current step.
r35f=$(s35_root)
S35_FO="$r35f/.bionic/docs/plans/wave-open.plan.md"
S35_FD="$r35f/.bionic/docs/plans/wave-shipped.plan.md"
printf '%s\n' "$(plan 6 "" "$matrix_complete")" > "$S35_FO"
printf '%s\n## SDLC State\ncurrent: 9\napproved-by: fixture 2026-09-07T00:00Z approved\n- Step 9: delivered: .bionic/docs/record/x.md\n\n%s\n' \
  "$(matrix_frontmatter true)" "$matrix_complete" > "$S35_FD"
touch -t 202609040000 "$S35_FO"
touch -t 202609040100 "$S35_FD"
s35_bind "$r35f" "$S35_SID_A" "$S35_FO"
s35_run "$r35f" "$S35_SID_A" 'git commit -m "x"'
s35_assert "35f bound to an OPEN plan under a DELIVERED newest one → the session's run is live: BLOCKED" \
  2 "$S35_FO" "$S35_FD"

# The control, and it is the old rule stated as a fact: over the same tree a session with
# no binding sees a root whose newest plan is delivered, so there is no run to enforce.
s35_unbind "$r35f" "$S35_SID_B" empty
s35_run "$r35f" "$S35_SID_B" 'git commit -m "x"'
s35_assert "35f control: unbound over the same tree reads the root as closed and allows" \
  0 - "BLOCKED"

# --- 35e AC-6, the vanished plan: a binding outlives the file it names ---
r35e=$(s35_root)
s35_two_plans "$r35e" a
S35_GONE="$r35e/.bionic/docs/plans/wave-gone.plan.md"
s35_bind "$r35e" "$S35_SID_A" "$S35_GONE"
s35_run "$r35e" "$S35_SID_A" 'git commit -m "x"'
s35_assert "35e bound to a plan that no longer exists → closed, not a fall-through" \
  0 "evidence-gate: bound plan closed — $S35_GONE" -
s35_assert "35e …and the OPEN plan beside it is never read" 0 - "$S35_B"

# --- 35g the vanished plan meets the MISPLACEMENT SWEEP (S10a, critic C-1) ---
#
# 35e above proves a binding to a deleted plan reads as closed and allows. It passes on a
# root that happens to hold no stray `*.plan.md`, and that is the whole of the defect: the
# sweep's guard was `[ -z "$PLAN" ] || [ ! -f "$PLAN" ]`, so a bound-but-missing plan walked
# into the depth-5 project-wide sweep six hundred lines before the `bound-closed → exit 0`
# escape, and any unrelated stray plan in the project turned every commit from that session
# into a block naming a file that has nothing to do with it.
#
# PRE-WAVE THIS WAS UNREACHABLE. `PLAN` came from `active_plan`, which reports only files
# `find -type f` just produced, so `[ ! -f "$PLAN" ]` could not be true with `$PLAN` set. A
# bound path is the first `PLAN` in this hook's history that can name a file that is not
# there while the docs root holds a perfectly good plan.
#
# THREE SESSIONS, ONE TREE, and the tree is the point: the ONLY difference between them is
# the marker. A fix that simply disabled the sweep would fail 35g3.
#
# THE EVIDENCE SITS ON B, the newest, so both control arms resolve to a plan that is clean:
# `s35_two_plans "$r35g" a` would have the unbound fallback land on B and block for a reason
# that has nothing to do with this row (that is 35b's subject), and a control that blocks for
# the wrong reason proves nothing about the sweep.
r35g=$(s35_root)
s35_two_plans "$r35g" b
S35_GONE2="$r35g/.bionic/docs/plans/wave-gone.plan.md"
mkdir -p "$r35g/notes"
S35_STRAY="$r35g/notes/stray.plan.md"
printf -- '---\ncanonical_sdlc_version: 14\n---\n\n## SDLC State\n\ncurrent: 3\n' > "$S35_STRAY"

# NON-VACUITY: the stray really is a plan this sweep would name, proved by the state the
# sweep is FOR — a session with no plan at all in the root.
r35g0=$(s35_root)
mkdir -p "$r35g0/notes"
cp "$S35_STRAY" "$r35g0/notes/stray.plan.md"
s35_unbind "$r35g0" "$S35_SID_A" empty
s35_run "$r35g0" "$S35_SID_A" 'git commit -m "x"'
s35_assert "35g0 non-vacuity: with NO plan in the root the sweep still blocks on the stray" \
  2 "$r35g0/notes/stray.plan.md" -

# 35g1 THE DEFECT: bound to a plan that is gone, with a stray somewhere in the project.
s35_bind "$r35g" "$S35_SID_A" "$S35_GONE2"
s35_run "$r35g" "$S35_SID_A" 'git commit -m "x"'
s35_assert "35g1 bound to a DELETED plan beside a stray plan → allowed, not blocked" \
  0 "evidence-gate: bound plan closed — $S35_GONE2" "BLOCKED"
s35_assert "35g1 …and the stray is never named: it is not this session's business" \
  0 - "$S35_STRAY"
s35_assert "35g1 …and the operator is told the bound plan is not on disk" \
  0 "is not on disk" -
s35_assert "35g1 …and told how to get back to a live run" \
  0 "session-poker.sh bind" -

# 35g2 UNBOUND over the identical tree: the live plan is announced and never acted on
# (wave-23-fixit-1810, D1), and the gate stops there — the root has a live run, so nothing
# is misplaced and the sweep that named the stray never runs.
s35_unbind "$r35g" "$S35_SID_B" empty
s35_run "$r35g" "$S35_SID_B" 'git commit -m "x"'
s35_assert "35g2 unbound over the same tree resolves by fallback and is not blocked" \
  0 "newest-plan fallback" "BLOCKED"

# 35g3 BOUND TO A LIVE PLAN over the identical tree: the control that keeps 35g1 from
# passing on a hook that had stopped sweeping altogether.
s35_bind "$r35g" "$S35_SID_B" "$S35_B"
s35_run "$r35g" "$S35_SID_B" 'git commit -m "x"'
s35_assert "35g3 bound to a LIVE plan over the same tree is gated on it, not on the stray" \
  0 - "$S35_STRAY"

# --- 35h AC-2.1, the UNREADABLE plan: it exists, and nothing can be validated against it ---
#
# (wave-20 T1, REQ-2, D2.) 35e and 35g1 above allow a commit bound to a plan that is GONE:
# nothing is left to protect. A plan that is still there but cannot be read is the opposite
# case — the run may be mid-flight, and admitting the commit waves it past every step check
# the plan would have made. Two shapes, both driven by triage-D and research D3 N1 as
# admitted before this wave: the file at mode 000, and the file inside a folder that cannot
# be opened (which `-e` reports exactly as it reports a deleted file).
#
# THE TREE MAKES A FALL-THROUGH VISIBLE. B, the newest, carries the evidence, so a gate that
# resolved B in place of the unreadable plan would ADMIT this commit — the refusal can only
# come from the bound-unreadable arm itself.
r35h=$(s35_root)
s35_two_plans "$r35h" b
S35_LOCK="$r35h/.bionic/docs/plans/wave-locked.plan.md"
printf '%s\n' "$(plan 6 "" "$matrix_complete")" > "$S35_LOCK"
chmod 000 "$S35_LOCK"
if [ -e "$S35_LOCK" ] && [ ! -r "$S35_LOCK" ]; then
  ok "35h premise: the bound plan exists at mode 000 and this user cannot read it"
else
  no "35h premise: the bound plan exists at mode 000 and this user cannot read it" \
    "readable — the suite runs with a privilege that reads mode 000"
fi
s35_bind "$r35h" "$S35_SID_A" "$S35_LOCK"
s35_run "$r35h" "$S35_SID_A" 'git commit -m "x"'
s35_assert "35h1 bound to a mode-000 plan → the commit is refused" 2 "cannot be read" -
s35_assert "35h1 …and the refusal names the plan's path" 2 "$S35_LOCK" -
s35_assert "35h1 …and never calls it closed or says there is no open run" 2 - "no open run"
s35_assert "35h1 …and the open plan beside it is never read" 2 - "$S35_B"
chmod 644 "$S35_LOCK"
s35_run "$r35h" "$S35_SID_A" 'git commit -m "x"'
s35_assert "35h1 control: the same plan made readable is gated on its own evidence (BLOCKED for Step 6)" \
  2 "$S35_LOCK" "cannot be read"

r35i=$(s35_root)
s35_two_plans "$r35i" b
mkdir -p "$r35i/.bionic/docs/plans/vault"
S35_VAULTED="$r35i/.bionic/docs/plans/vault/wave-vaulted.plan.md"
printf '%s\n' "$(plan 6 "" "$matrix_complete")" > "$S35_VAULTED"
chmod 000 "$r35i/.bionic/docs/plans/vault"
if [ ! -e "$S35_VAULTED" ] && [ ! -x "$r35i/.bionic/docs/plans/vault" ]; then
  ok "35i premise: the plan's folder cannot be opened, so the plan reads as absent"
else
  no "35i premise: the plan's folder cannot be opened, so the plan reads as absent" \
    "the folder opens — the suite runs with a privilege that ignores mode 000"
fi
s35_bind "$r35i" "$S35_SID_A" "$S35_VAULTED"
s35_run "$r35i" "$S35_SID_A" 'git commit -m "x"'
s35_assert "35i bound to a plan inside an unopenable folder → the commit is refused" \
  2 "cannot be read" -
s35_assert "35i …and the refusal names the plan's path" 2 "$S35_VAULTED" -
s35_assert "35i …and does not say the plan is not on disk" 2 - "is not on disk"
s35_assert "35i …and the open plan beside it is never read" 2 - "$S35_B"
chmod 755 "$r35i/.bionic/docs/plans/vault"

# ============================================================
# Section 36: environments arm — declared, covered, fog (S3, AC-4, AC-23)
# ============================================================
#
# Frontmatter `environments:` is one line of entries joined by " · ", each
# `<name> (covered...)` or `<name> (fog — cure: <text>)`. The arm
# (validate_environments) fires at current: 5..9, the same durable-prefix
# span as the walk-artifact arm. Absent key: no-op — but the no-op still
# names itself on the log channel via a `[environments]` finding, never
# silent-silent. Declared: the Step-5 evidence must carry an
# `environments-covered:` line naming every non-fog environment; a fog entry
# with no cure blocks regardless of the covered line's content.

section "Section 36: environments arm"

# $1 = optional `environments:` frontmatter line (empty = key absent, the
# no-op case). walk: exempt keeps that unrelated arm out of the way so each
# fixture isolates the environments subject.
env_frontmatter() {
  local env_line="${1:-}"
  printf -- '---\n'
  printf -- 'governing-skill: canonical-sdlc\ncanonical_sdlc_version: 14\n'
  printf -- 'intent: build\nrigor: double\nscale: wave\n'
  printf -- 'deploy_target: none\nuse_worktree: false\nhas_ui: true\n'
  printf -- 'walk: exempt\n'
  if [ -n "$env_line" ]; then
    printf -- '%s\n' "$env_line"
  fi
  printf -- '---\n'
}

# $1 environments line · $2 Step-5 body (indented) · $3 matrix section.
env_plan5() {
  printf '%s\n## SDLC State\ncurrent: 5\napproved-by: fixture 2026-09-07T00:00Z approved\nStep 5:\n%s\n\n%s\n' \
    "$(env_frontmatter "$1")" "$2" "$3"
}

# Same, at current: 6 — the Step-5 block stays in the section so the durable
# prefix arm has something to read, mirroring walk_plan6.
env_plan6() {
  printf '%s\n## SDLC State\ncurrent: 6\napproved-by: fixture 2026-09-07T00:00Z approved\nStep 5:\n%s\nStep 6:\n%s\n\n%s\n' \
    "$(env_frontmatter "$1")" "$2" "$step6_body" "$3"
}

env_single_decl='environments: macos-system (covered by this wave)'
env_two_decl='environments: macos-system (covered by this wave) · linux-system (fog — cure: a Linux host runs tests/run.sh under the pin)'
env_fog_no_cure_decl='environments: macos-system (covered by this wave) · linux-system (fog)'
env_two_covered_decl='environments: macos-system (covered by this wave) · windows-system (covered by this wave)'

env_step5_covered="  cmd: bash test.sh
  pass: 332
  total: 332
  head: ${EG_HEAD}
  output: .bionic/docs/plans/wave-01.plan.md#step-5
  auditor: 3 rows CONFIRMED — report .bionic/docs/record/audit.md
  environments-covered: macos-system"

env_step5_no_covered_line="  cmd: bash test.sh
  pass: 332
  total: 332
  head: ${EG_HEAD}
  output: .bionic/docs/plans/wave-01.plan.md#step-5
  auditor: 3 rows CONFIRMED — report .bionic/docs/record/audit.md"

# 36a — declared covered set == the Step-5 environments-covered line → allow.
h36a=$(make_home)
write_plan "$h36a" "$(env_plan5 "$env_single_decl" "$env_step5_covered" "$matrix_complete")" > /dev/null
expect_allow "36a declared covered set matches environments-covered → allow" \
  "$h36a" 'git commit -m "x"'

# 36b — declared covered set present, Step-5 evidence has no
# 'environments-covered:' line at all → block.
h36b=$(make_home)
write_plan "$h36b" "$(env_plan5 "$env_single_decl" "$env_step5_no_covered_line" "$matrix_complete")" > /dev/null
expect_block "36b declared covered set, no 'environments-covered:' line → block" \
  "$h36b" 'git commit -m "x"' "no 'environments-covered:' line"

# 36c — a fog entry WITH a cure passes so long as the covered set is listed;
# the fog name itself must NOT be required in environments-covered.
h36c=$(make_home)
write_plan "$h36c" "$(env_plan5 "$env_two_decl" "$env_step5_covered" "$matrix_complete")" > /dev/null
expect_allow "36c fog entry with a cure + covered listed → allow (fog name not required)" \
  "$h36c" 'git commit -m "x"'

# 36d — a fog entry naming no cure blocks, even though the covered set is
# fully and correctly listed.
h36d=$(make_home)
write_plan "$h36d" "$(env_plan5 "$env_fog_no_cure_decl" "$env_step5_covered" "$matrix_complete")" > /dev/null
expect_block "36d fog entry with no cure named → block" \
  "$h36d" 'git commit -m "x"' "fog entry with no cure named"

# 36e — 'environments-covered:' omits a declared non-fog environment → block.
h36e=$(make_home)
write_plan "$h36e" "$(env_plan5 "$env_two_covered_decl" "$env_step5_covered" "$matrix_complete")" > /dev/null
expect_block "36e environments-covered omits a declared non-fog environment → block" \
  "$h36e" 'git commit -m "x"' "omits declared environment"

# 36f — the 'environments:' key is absent entirely → allow, SILENT on
# stderr (an ordinary commit in an ordinary repo never declares this key,
# so the no-op must not become noise the way an actionable finding is).
h36f=$(make_home)
write_plan "$h36f" "$(env_plan5 "" "$env_step5_no_covered_line" "$matrix_complete")" > /dev/null
expect_allow "36f absent 'environments:' → allow, silent on stderr" \
  "$h36f" 'git commit -m "x"'

# 36f2 — the SAME fixture, but the no-op is still recorded on the durable
# audit-file channel (log_finding_quiet) — "log-only" literally: logged,
# but never surfaced on stderr the way Section 20's refactor/tune findings
# are. Mirrors the 19e/19e2 stderr-vs-file split.
expect_audit_line "36f2 …and the no-op is recorded on the audit-file channel only" \
  "$h36f" 'git commit -m "x"' "evidence-gate environments:"

# 36g — durable prefix span (mirrors 26g/A5): at current: 6 the same
# fog-without-cure rule still blocks, so the claim cannot go stale once
# Verify is behind you.
h36g=$(make_home)
write_plan "$h36g" "$(env_plan6 "$env_fog_no_cure_decl" "$env_step5_covered" "$matrix_complete")" > /dev/null
expect_block "36g current: 6 still enforces the fog-cure rule (durable prefix)" \
  "$h36g" 'git commit -m "x"' "fog entry with no cure named"

# 36h — a plan whose frontmatter never mentions 'environments:' AND whose
# rows are all still pending: still a silent allow (no interaction with the
# matrix gate; the two arms are independent), and the no-op still lands on
# the audit file only.
h36h=$(make_home)
write_plan "$h36h" "$(env_plan5 "" "$env_step5_no_covered_line" "$walk_matrix_all_pending")" > /dev/null
expect_allow "36h absent 'environments:' + all rows pending → allow, silent on stderr" \
  "$h36h" 'git commit -m "x"'
expect_audit_line "36h2 …and the no-op is still recorded on the audit-file channel only" \
  "$h36h" 'git commit -m "x"' "evidence-gate environments:"

# 36i/36j — THE OVER-CLAIM DIRECTION (critic K-5). The arm walked the declared non-fog
# names and required each to be covered; nothing walked the covered names, so a plan could
# claim coverage it does not have and the gate was silent. THIS WAVE'S OWN FRONTMATTER is
# the live instance: `environments-covered: macos-system, linux-system` passed while
# linux-system was declared FOG, and a fog entry's entire meaning is "not covered".
env_step5_overclaim_fog="  cmd: bash test.sh
  pass: 332
  total: 332
  head: ${EG_HEAD}
  output: .bionic/docs/plans/wave-01.plan.md#step-5
  auditor: 3 rows CONFIRMED — report .bionic/docs/record/audit.md
  environments-covered: macos-system, linux-system"

h36i=$(make_home)
write_plan "$h36i" "$(env_plan5 "$env_two_decl" "$env_step5_overclaim_fog" "$matrix_complete")" > /dev/null
expect_block "36i environments-covered claims a FOG environment → block" \
  "$h36i" 'git commit -m "x"' "declares as FOG"

env_step5_overclaim_undeclared="  cmd: bash test.sh
  pass: 332
  total: 332
  head: ${EG_HEAD}
  output: .bionic/docs/plans/wave-01.plan.md#step-5
  auditor: 3 rows CONFIRMED — report .bionic/docs/record/audit.md
  environments-covered: macos-system, freebsd"

h36j=$(make_home)
write_plan "$h36j" "$(env_plan5 "$env_single_decl" "$env_step5_overclaim_undeclared" "$matrix_complete")" > /dev/null
expect_block "36j environments-covered names an UNDECLARED environment → block" \
  "$h36j" 'git commit -m "x"' "never declared"

# 36k — CONTROL, so 36i/36j are the over-claim rule and not a fixture that could never
# pass: the same declaration with the fog name dropped from the covered line allows. 36c
# above asserts the same thing from the other side; this one shares 36i's fixture.
h36k=$(make_home)
write_plan "$h36k" "$(env_plan5 "$env_two_decl" "$env_step5_covered" "$matrix_complete")" > /dev/null
expect_allow "36k control: the same declaration, covering only what it declares → allow" \
  "$h36k" 'git commit -m "x"'

# 36l — the durable prefix (mirrors 36g): at current: 6 the over-claim still blocks, so a
# coverage claim cannot go stale once Verify is behind you.
h36l=$(make_home)
write_plan "$h36l" "$(env_plan6 "$env_two_decl" "$env_step5_overclaim_fog" "$matrix_complete")" > /dev/null
expect_block "36l current: 6 still refuses the over-claim (durable prefix)" \
  "$h36l" 'git commit -m "x"' "declares as FOG"

# ============================================================
section "Section 37: K5/AC-K5.2 — Step-1 'requirements:' pointer"
# ============================================================
#
# K5 (design ledger K5; ADR-001): Step 1 authors wave-NN-<slug>.requirements.md; the
# Step-1 evidence line records its path once and this arm reads it back at every commit
# from current: 2 onward — durable, like the Step-5 walk artifact (A5). Scoped to
# rigor:double + multi_agent:true + scale wave|epic (mirrors D7's own guard, above) so
# the suite's FM (rigor: single) and frontmatter() (no multi_agent:) fixtures stay
# no-ops — proven directly in 37g below.

# $1 current  $2 raw Step-1 line content (no "Step 1: " prefix)  $3 the CURRENT step's
# own line content (only emitted when current != 1; a pointer step needs its OWN line
# non-empty and non-placeholder — "TODO"/"pending"/"in progress" etc. all block upstream
# of this arm, so every fixture below uses real-shaped prose instead).
k5_plan() {
  local current="$1" step1="$2" own="${3:-.bionic/docs/specs/epic-01-demo/wave-01-x.spec.md}"
  printf '%s\n' "$(d7_wave_frontmatter)"
  printf '## SDLC State\ncurrent: %s\n' "$current"
  printf 'Step 1: %s\n' "$step1"
  [ "$current" = "1" ] || printf 'Step %s: %s\n' "$current" "$own"
}

k5g_h=$(make_home)
k5g_p=$(make_project)
mkdir -p "$k5g_p/.bionic/docs/specs/epic-01-demo"
k5g_real="$k5g_p/.bionic/docs/specs/epic-01-demo/wave-01-x.requirements.md"
printf -- '---\ngoverning-skill: agent-skills:idea-refine\ncanonical_sdlc_version: 14\n---\n# reqs\n' \
  > "$k5g_real"

echo "-- 37a: current: 1 — the arm is inert (Step 1 is still being authored) --"
write_project_plan "$k5g_p" "$(k5_plan 1 "brief ideas/x.md rev 1; ratified in the terminal")" > /dev/null
expect_allow_p "37a current: 1, Step 1 has no requirements: field → allow (arm inert)" \
  "$k5g_h" "$k5g_p" 'git commit -m "x"'

echo "-- 37b: current: 2, Step 1 lacks 'requirements:' → block naming the field --"
write_project_plan "$k5g_p" "$(k5_plan 2 "in progress")" > /dev/null
expect_block_p "37b current: 2, no requirements: field → block" \
  "$k5g_h" "$k5g_p" 'git commit -m "x"' "no 'requirements:' field"

echo "-- 37c: current: 2, 'requirements:' names a file that does not exist → block naming the path --"
write_project_plan "$k5g_p" "$(k5_plan 2 "requirements: specs/epic-01-demo/nowhere.requirements.md")" > /dev/null
expect_block_p "37c current: 2, dangling requirements: path → block, names it" \
  "$k5g_h" "$k5g_p" 'git commit -m "x"' "does not resolve to a real file"

echo "-- 37d: current: 2, 'requirements:' resolves to a real file → allow --"
write_project_plan "$k5g_p" "$(k5_plan 2 "requirements: specs/epic-01-demo/wave-01-x.requirements.md")" > /dev/null
expect_allow_p "37d current: 2, requirements: resolves → allow" \
  "$k5g_h" "$k5g_p" 'git commit -m "x"'

echo "-- 37e: durable — current: 3 (a step past 2) still enforces the same pointer --"
write_project_plan "$k5g_p" "$(k5_plan 3 "in progress" ".bionic/docs/plans/active.md")" > /dev/null
expect_block_p "37e current: 3, no requirements: field → block (durable, not just at 2)" \
  "$k5g_h" "$k5g_p" 'git commit -m "x"' "no 'requirements:' field"

echo "-- 37f: a '..' component in the pointer refuses outright, never resolved --"
write_project_plan "$k5g_p" "$(k5_plan 2 "requirements: specs/../../../etc/passwd")" > /dev/null
expect_block_p "37f '..' component → block, never resolved" \
  "$k5g_h" "$k5g_p" 'git commit -m "x"' "climbs out with a '..' component"

echo "-- 37g: scope guard — rigor: single (this suite's FM/frontmatter() default) is a no-op --"
# Same current: 2, same missing field, same project — the only variable is rigor. If the
# guard were not real this would block exactly like 37b.
k5g_tested="$(d7_wave_frontmatter single true)
## SDLC State
current: 2
Step 1: in progress
Step 2: .bionic/docs/specs/epic-01-demo/wave-01-x.spec.md"
write_project_plan "$k5g_p" "$k5g_tested" > /dev/null
expect_allow_p "37g rigor: single → allow (scope guard makes the arm inert)" \
  "$k5g_h" "$k5g_p" 'git commit -m "x"'


# ============================================================
# Section 37: the approval arm and the fails-when arm (epic-22 K2)
# ============================================================
#
# TWO ARMS, ONE STEP BOUNDARY. Both fire from `current: 4` — the step where the plan
# stops being authored and starts being built — and both are silent below it.
#
#   approved-by:  AC-K2.4, design decision 2. Step 3 ends at one approval checkpoint,
#                 and until this arm existed the user's `approved` left no trace: a run
#                 could be at Step 4 with nobody able to say whether the plan had ever
#                 been ratified. The orchestrator now writes
#                 `approved-by: <user> <ISO-UTC> "<verbatim reply>"` into `## SDLC State`
#                 on the literal word, and this is what makes its absence cost something.
#   fails-when:   AC-K2.3. An eval with no nameable failure is not an eval — a row that
#                 cannot say what planted defect it must go red on is a row that will be
#                 green whatever the code does. The column is authored at Step 2 in the
#                 spec's `## Eval design` and rendered into the matrix at Step 3, so by
#                 Step 4 every AC block already has one or the plan skipped a step.
#
# WHY THE ARMS ARE NOT MUTUAL. 37f/37g drive each one with the OTHER condition satisfied,
# so neither refusal can be credited to the wrong wall.
#
# INERT CONDITIONS, pinned rather than assumed (37h..37k): below current 4 both are
# silent; a matrix with no AC block for a row leaves the fails-when arm with nothing to
# judge; and a plan with no `## Verification Matrix` at all is not a fails-when finding.
# The last two matter because the arms run at Step 4, where a plan is legitimately
# mid-authoring and half its matrix may not exist yet.

section "Section 37: the approval arm and the fails-when arm (epic-22 K2)"

# A Step-4 body the shape checks accept: Step 4 is a pointer step for this gate.
k2_step4="  plan-doc: .bionic/docs/plans/wave-01.plan.md#step-4"

# k2_plan <current> <approved-by line, or ""> <matrix section, or ""> -> a whole plan
k2_plan() {
  local approved_line=""
  [ -n "$2" ] && approved_line="$2
"
  printf '%s\n## SDLC State\ncurrent: %s\n%sStep %s:\n%s\n\n%s\n' \
    "$(matrix_frontmatter true)" "$1" "$approved_line" "$1" "$k2_step4" "${3:-}"
}

K2_APPROVED='approved-by: dana 2026-09-07T19:05Z "Ok, amazing! Approved."'

# k2_matrix <AC-2 fails-when line, or ""> -> a two-row matrix whose AC-1 block always
# names a fails-when and whose AC-2 block carries whatever the caller passes.
k2_matrix() {
  local ac2_fw=""
  [ -n "$1" ] && ac2_fw="
  $1"
  cat <<EOF
## Verification Matrix

stack-health: n/a: no long-running serve

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1 | T0 | pending | see AC-1 | |
| AC-2 | T0 | pending | see AC-2 | |

AC-1:
  criterion: the card carries every ratified row
  provenance: user 2026-09-07 "approved"
  fails-when: a card is missing
AC-2:
  criterion: the arm refuses a block that names no failure
  provenance: user 2026-09-07 "approved"${ac2_fw}
EOF
}

k2_matrix_full="$(k2_matrix 'fails-when: the gate passes it')"
k2_matrix_missing="$(k2_matrix '')"
k2_matrix_empty="$(k2_matrix 'fails-when:')"

# --- 37a/37b: the approval arm ---------------------------------------------

h37a=$(make_home)
write_plan "$h37a" "$(k2_plan 4 "" "$k2_matrix_full")" > /dev/null
expect_block "37a current: 4 with no approved-by: → block" \
  "$h37a" 'git commit -m "x"' "approved-by"

h37b=$(make_home)
write_plan "$h37b" "$(k2_plan 4 "$K2_APPROVED" "$k2_matrix_full")" > /dev/null
expect_allow "37b current: 4 with the approved-by line → allow" \
  "$h37b" 'git commit -m "x"'

# 37c — the line has to SAY something. An `approved-by:` with an empty value records no
# approval, and reading it as one would make the wall satisfiable by typing its key.
h37c=$(make_home)
write_plan "$h37c" "$(k2_plan 4 "approved-by:" "$k2_matrix_full")" > /dev/null
expect_block "37c an empty approved-by: value is not an approval → block" \
  "$h37c" 'git commit -m "x"' "approved-by"

# 37d — the durable prefix: the approval does not stop mattering once Step 4 is behind
# you. A plan that reaches Verify with the line deleted has lost the same fact.
h37d=$(make_home)
write_plan "$h37d" "$(k2_plan 6 "" "$k2_matrix_full")" > /dev/null
expect_block "37d current: 6 with no approved-by: → still blocked (durable prefix)" \
  "$h37d" 'git commit -m "x"' "approved-by"

# --- 37e/37f: the fails-when arm -------------------------------------------

h37e=$(make_home)
write_plan "$h37e" "$(k2_plan 4 "$K2_APPROVED" "$k2_matrix_missing")" > /dev/null
expect_block "37e an AC block with no fails-when: → block, naming the AC" \
  "$h37e" 'git commit -m "x"' "AC-2"

h37e2=$(make_home)
write_plan "$h37e2" "$(k2_plan 4 "$K2_APPROVED" "$k2_matrix_missing")" > /dev/null
expect_block "37e2 …and the refusal names the missing key" \
  "$h37e2" 'git commit -m "x"' "fails-when"

h37f=$(make_home)
write_plan "$h37f" "$(k2_plan 4 "$K2_APPROVED" "$k2_matrix_empty")" > /dev/null
expect_block "37f an empty fails-when: value → block" \
  "$h37f" 'git commit -m "x"' "fails-when"

# 37g — THE CONTROL 37e and 37f need. The same plan with both keys present allows, so
# the two refusals above are the missing key and not the fixture.
h37g=$(make_home)
write_plan "$h37g" "$(k2_plan 4 "$K2_APPROVED" "$k2_matrix_full")" > /dev/null
expect_allow "37g control: every AC block names a fails-when → allow" \
  "$h37g" 'git commit -m "x"'

# --- 37h..37k: the inert conditions ----------------------------------------

# 37h — below Step 4 the plan is still being authored: the approval has not been asked
# for and the matrix is still being written. Neither arm may fire.
h37h=$(make_home)
write_plan "$h37h" "$(k2_plan 3 "" "$k2_matrix_missing")" > /dev/null
expect_allow "37h current: 3 with neither approved-by nor fails-when → allow (both arms inert)" \
  "$h37h" 'git commit -m "x"'

# 37i — a row with no AC block at all is not a fails-when finding: there is no block to
# lack the key, and the per-tier evidence loop at Verify is what owns that gap.
k2_matrix_noblock="## Verification Matrix

stack-health: n/a: no long-running serve

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1 | T0 | pending | see AC-1 | |
| AC-9 | T0 | pending | see AC-9 | |

AC-1:
  criterion: the card carries every ratified row
  fails-when: a card is missing"
h37i=$(make_home)
write_plan "$h37i" "$(k2_plan 4 "$K2_APPROVED" "$k2_matrix_noblock")" > /dev/null
expect_allow "37i a matrix row with no AC block is not a fails-when finding → allow" \
  "$h37i" 'git commit -m "x"'

# 37j — no matrix section at all: a Step-4 plan may not have written one yet, and a wall
# that demanded one here would be the Verify gate's demand moved four steps early.
h37j=$(make_home)
write_plan "$h37j" "$(k2_plan 4 "$K2_APPROVED" "")" > /dev/null
expect_allow "37j a Step-4 plan with no '## Verification Matrix' → allow (fails-when arm inert)" \
  "$h37j" 'git commit -m "x"'

# 37l — A WAIVER DOES NOT EXCUSE THE COLUMN. Everywhere else in this loop a waiver
# dissolves a row's demands: the per-tier evidence keys, the CONFIRMED verdict, the
# `task: 9` tier refusal all yield to one. This arm does not, and the distinction is the
# reason: those are demands for EVIDENCE, and a waiver is precisely the decision not to
# gather it. `fails-when:` is not evidence — it is the design of the eval, authored at
# Step 2 before any waiver exists, and a row that never named a failure was never
# evaluable in the first place. Waiving it waives the question, not the answer.
h37l=$(make_home)
k2_matrix_waived="## Verification Matrix

stack-health: n/a: no long-running serve

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1 | T0 | waived | waiver: dana 2026-09-07 criterion dropped | waived |

AC-1:
  waiver: dana 2026-09-07 criterion dropped"
write_plan "$h37l" "$(k2_plan 4 "$K2_APPROVED" "$k2_matrix_waived")" > /dev/null
expect_block "37l a WAIVED row still has to name its fails-when → block" \
  "$h37l" 'git commit -m "x"' "fails-when"

# THE PLAN THAT SPECIFIED THESE WALLS is the first artifact they judge, and a wall its own
# specification cannot satisfy is a wall that gets turned off within the hour. That check is
# NOT a fixture here: `.bionic/` is machine-local by decision and absent from a fresh clone
# and from every worktree, so an arm reading it would degrade to a vacuous pass on exactly
# the machines the suite is meant to protect. It is a recorded drive instead —
# record/wave-01-plugin-only/s16-step-cards.log, "the real plan" — run against the live
# plan with the live hook, with its command and output.

# ============================================================
# Section 38: epic-22 K2.5 — the same two arms bind at task scale
# ============================================================
#
# D2/K2 (Section 37) built two arms for a NUMBERED-step plan: `approved-by:` absent from
# `## SDLC State` refuses a commit from `current: 4` onward, and a Verification Matrix AC block
# with no `fails-when:` refuses one from the same point. K2.5 made both bind on a task-scale plan
# at `current: T<n>`. ONE LEDGER SHAPE (wave-31 T24; REQ-1, D2): a task-scale plan's `current:`
# is a step number now, so the arms bind on it exactly as on a wave plan, from `current: 4`, and a
# `current: T<n>` is refused as not numeric (38e). The plan is tests/lib/plan-fixture.sh's.

section "Section 38: epic-22 K2.5 — approval/fails-when bind at task scale"

# k2t_plan <approved-by line, or ""> <matrix section> [<current>] -> a task-scale plan, one row,
# at current: 4 by default, its approved-by: line and its matrix the caller's.
k2t_plan() {
  eg_pf_plan "${3:-4}" task single false "" "$(eg_pf_row T1 — active)" \
    | awk -v A="$1" '/^approved-by: / { if (A != "") print A; next } /^## Verification Matrix$/ { exit } { print }'
  printf '%s\n' "$2"
}

# 38a — task scale, current: 4, a matrix present, NO approved-by → block naming approved-by.
h38a=$(make_home)
write_plan "$h38a" "$(k2t_plan "" "$k2_matrix_full")" > /dev/null
expect_block "38a task-scale current: 4 with no approved-by: → block" \
  "$h38a" 'git commit -m "x"' "approved-by"

# 38b — approved-by present; AC-2's block names no fails-when: → block naming AC-2.
h38b=$(make_home)
write_plan "$h38b" "$(k2t_plan "$K2_APPROVED" "$k2_matrix_missing")" > /dev/null
expect_block "38b task-scale current: 4, AC-2 names no fails-when: → block naming AC-2" \
  "$h38b" 'git commit -m "x"' "AC-2"

# 38c — an empty fails-when: value is the same defect as an absent one.
h38c=$(make_home)
write_plan "$h38c" "$(k2t_plan "$K2_APPROVED" "$k2_matrix_empty")" > /dev/null
expect_block "38c task-scale current: 4, AC-2 fails-when: is empty → block naming AC-2" \
  "$h38c" 'git commit -m "x"' "AC-2"

# 38d — both present, every AC block names a fails-when → allow.
h38d=$(make_home)
write_plan "$h38d" "$(k2t_plan "$K2_APPROVED" "$k2_matrix_full")" > /dev/null
expect_allow "38d task-scale current: 4, approved-by + every fails-when present → allow" \
  "$h38d" 'git commit -m "x"'

# 38e — the K2.5 pointer `current: T3` → refused as not numeric, before either arm.
h38e=$(make_home)
write_plan "$h38e" "$(k2t_plan "" "$k2_matrix_full" T3)" > /dev/null
expect_block "38e task-scale current: T3 → block, naming the value as not numeric" \
  "$h38e" 'git commit -m "x"' "current: T3 is not numeric"

# 38f — control: a numbered plan at current: 3 (wave, pre-approval) stays inert on both arms
# regardless of scale. Section 37h already proves this; reproven here beside the task-scale
# cases so the arms are visibly bounded to `current: 4` onward at either scale.
h38f=$(make_home)
write_plan "$h38f" "$(k2_plan 3 "" "$k2_matrix_missing")" > /dev/null
expect_allow "38f control: numbered current: 3 with neither approved-by nor fails-when → allow (K2.5 does not widen this)" \
  "$h38f" 'git commit -m "x"'

# 38g — control: current: 0 through 2 stay inert too, same reasoning as 38f.
for n in 0 1 2; do
  h38g=$(make_home)
  write_plan "$h38g" "$(k2_plan "$n" "" "$k2_matrix_missing")" > /dev/null
  expect_allow "38g control: numbered current: $n with neither approved-by nor fails-when → allow" \
    "$h38g" 'git commit -m "x"'
done

# ---- 38s: AC-12.1 (wave-19 REQ-12, D12) — the `- T<n>:` stub the Step-3 text prescribes ----
#
# A plan authored at Step 3 carries one `- T<n>:` line per `## Tasks` row BEFORE any writer
# runs. The arm that demanded the addressed row's line under `current: T<n>`, and its proof
# shape at double, went with that shape (wave-31 T24; D2); what reads the stub now is the
# dispatch-ledger arm, which judges a line that is there for a placeholder. The spelling is READ
# FROM THE RENDERED steps/3.md, not restated here: the rows below pin that what the text tells a
# planner to write is what the gate admits, on a task-scale plan's one table.
S38S_STEP3="${BIONIC_SKILLS_DIR}/canonical-sdlc/steps/3.md"
S38S_TPL="$( { /usr/bin/grep -m1 -E '^- T<n>: ' "$S38S_STEP3" 2>/dev/null || true; } | sed -E 's/^- T<n>: //')"
if [ -n "$S38S_TPL" ]; then
  ok "38s0 AC-12.1 — steps/3.md's SDLC State template carries a '- T<n>:' stub line"
else
  no "38s0 AC-12.1 — steps/3.md's SDLC State template carries a '- T<n>:' stub line" "file: $S38S_STEP3"
fi
s38s_stub() {  # <n> -> the text's stub for row T<n> of wave 19
  printf '%s' "$S38S_TPL" | sed -e "s/<n>/$1/g" -e 's/<wave>/19/g'
}

# s38s_plan <T1 evidence> <T1 status> -> a double multi_agent task-scale plan at current: 4,
# approved, two rows, the second still pending with the text's stub.
s38s_plan() {
  eg_pf_plan 4 task double true "- T1: $1
- T2: $(s38s_stub 2)" "$(eg_pf_row T1 — "$2" .worktrees/19-T1)" "$(eg_pf_row T2 — pending .worktrees/19-T2)"
}

# 38s1 — only the stubs, spelled as the text spells them → admitted.
h38s1=$(make_home)
write_plan "$h38s1" "$(s38s_plan "$(s38s_stub 1)" pending)" > /dev/null
expect_allow "38s1 AC-12.1 — double task plan at current: 4 carrying only the text's stubs → allow" \
  "$h38s1" 'git commit -m "x"'

# 38s2 — a row's stub is a bare `pending` → refused (the placeholder ban).
h38s2=$(make_home)
write_plan "$h38s2" "$(s38s_plan "pending" pending)" > /dev/null
expect_block "38s2 AC-12.1 — …and a bare 'pending' stub → block" \
  "$h38s2" 'git commit -m "x"' "dispatched task T1 evidence line is a placeholder"

# ============================================================
# Section 38: the prototype no-row arm (epic-22 K4, AC-K4.2)
# ============================================================
#
# A PROTOTYPE NEVER DISCHARGES A MATRIX ROW (design decision D7). Its output is a
# design ruling written back to the spec, not a shipped behavior — nothing about a
# throwaway is provable by an eval. The arm reads two Step-3 tables the plan already
# carries: `## Tasks` names which task ids are `kind: prototype`, and each
# Verification Matrix AC block's own `task:` field names which task discharges it.
# An AC block naming a prototype task is refused, at `current: 4` onward — the same
# step boundary as the approval and fails-when arms beside it (Section 37), and
# inert for the identical reason: both tables are Step-3 artifacts, not necessarily
# complete before Step 4.
#
# MIGRATED BY REQ-1e (T8). The section this arm read was `## Tasks`, four of whose
# columns it took by position; it is `## Tasks` now, read through lib/units.sh, and
# the matrix field it cross-references is `task:`. The fixtures below carry the
# widened ten-column schema for that reason.

section "Section 38: the prototype no-row arm (epic-22 K4)"

# k4_tasks <prototype-id> <other-id> -> a Tasks table with one prototype row and
# one build row, the shape the real plan's prototype task and the build task that
# cites its ruling already carry.
k4_tasks() {
  cat <<EOF
## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | status |
|---|---|---|---|---|---|---|---|---|---|
| $1 | 4 | prototype | E1: refusal wording (attended) | senior-implementor | — | 30m | E1 | record/x.md | pending |
| $2 | 4 | build | E1: hooks migrated | senior-implementor | $1 | 60m | E1 | hooks/*.sh | pending |
EOF
}

# k4_matrix <AC-1's task: value> -> a one-row matrix whose AC-1 block names the given
# task.
k4_matrix() {
  cat <<EOF
## Verification Matrix

stack-health: n/a: no long-running serve

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1 | T0 | pending | see AC-1 | |

AC-1:
  criterion: the refusal wording is proven
  provenance: user 2026-09-07 "approved"
  task: $1
  fails-when: the wording is untested
EOF
}

# k4_plan <current> <tasks section> <matrix section> -> a whole plan, same shape as
# k2_plan (Section 37) with a `## Tasks` table spliced in ahead of the matrix.
k4_plan() {
  printf '%s\n## SDLC State\ncurrent: %s\n%s\nStep %s:\n%s\n\n%s\n\n%s\n' \
    "$(matrix_frontmatter true)" "$1" "$K2_APPROVED" "$1" "$k2_step4" "$2" "$3"
}

# --- 38a/38b: the refusal, and its control -----------------------------------

# 38a — T12 is `kind: prototype` and AC-1 names `task: T12`: refused, naming
# both the AC and the task.
h38a=$(make_home)
write_plan "$h38a" "$(k4_plan 4 "$(k4_tasks T12 T13)" "$(k4_matrix T12)")" > /dev/null
expect_block "38a a kind: prototype task (T12) owning a matrix row (AC-1, task: T12) → block" \
  "$h38a" 'git commit -m "x"' "AC-1"
h38a2=$(make_home)
write_plan "$h38a2" "$(k4_plan 4 "$(k4_tasks T12 T13)" "$(k4_matrix T12)")" > /dev/null
expect_block "38a2 …and the refusal names the prototype task" \
  "$h38a2" 'git commit -m "x"' "task: T12"

# 38b — THE CONTROL 38a needs: the identical plan with AC-1 repointed at the BUILD
# task (T13) instead. Same Tasks table, same prototype row still present — only the
# matrix's own `task:` field changed — so an allow here proves the refusal above was
# earned by the AC pointing at a prototype, not by the fixture shape.
h38b=$(make_home)
write_plan "$h38b" "$(k4_plan 4 "$(k4_tasks T12 T13)" "$(k4_matrix T13)")" > /dev/null
expect_allow "38b control: the same AC repointed at the build task (T13) → allow" \
  "$h38b" 'git commit -m "x"'

# --- 38c: inert below Step 4 --------------------------------------------------
#
# `current: 3` is still plan authoring: the Tasks table and the matrix may both be
# incomplete, and this arm — like the approval and fails-when arms beside it — does
# not fire there even on a fixture that would refuse at Step 4.
h38c=$(make_home)
write_plan "$h38c" "$(k4_plan 3 "$(k4_tasks T12 T13)" "$(k4_matrix T12)")" > /dev/null
expect_allow "38c current: 3 with a prototype task owning a matrix row → allow (arm inert below Step 4)" \
  "$h38c" 'git commit -m "x"'

# --- 38d: no prototype row at all --------------------------------------------
#
# A Tasks table with no `kind: prototype` row leaves the arm with nothing to check —
# every AC's `task:` value is compared against an empty set, never against itself.
h38d=$(make_home)
k4_tasks_no_proto="## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | status |
|---|---|---|---|---|---|---|---|---|---|
| T12 | 4 | build | E1: refusal wording | senior-implementor | — | 30m | E1 | record/x.md | pending |
| T13 | 4 | build | E1: hooks migrated | senior-implementor | T12 | 60m | E1 | hooks/*.sh | pending |"
write_plan "$h38d" "$(k4_plan 4 "$k4_tasks_no_proto" "$(k4_matrix T12)")" > /dev/null
expect_allow "38d no kind: prototype row in '## Tasks' → allow (nothing to check against)" \
  "$h38d" 'git commit -m "x"'

# --- 38e: a prototype row, but no matrix AC names its task -------------------
#
# The prototype task exists in '## Tasks' but the matrix's own AC doesn't cite it
# (points at the build task) — this is 38b's shape again from the other direction,
# confirming the arm judges the AC block's `task:` field and not merely the presence
# of a prototype row anywhere in the plan.
h38e=$(make_home)
write_plan "$h38e" "$(k4_plan 4 "$(k4_tasks T12 T13)" "$(k4_matrix T13)")" > /dev/null
expect_allow "38e a prototype task present, but no AC block names it → allow" \
  "$h38e" 'git commit -m "x"'

# --- 38f: this plan's own task body — the wave's real Tasks/matrix shape ------
#
# Not a fixture: the arm's brief requires this exact plan pass as it stands (the
# prototype task owns no matrix row). That drive is recorded, with the real
# hook and the real plan, in record/wave-01-plugin-only/s18-prototype-unit.log rather
# than reproduced here — `.bionic/` is machine-local and absent from a fresh clone, so
# an in-suite fixture reading it would degrade to a vacuous pass on exactly the
# machines this arm is meant to protect.

# ============================================================
# Section 39: the matrix evidence-path arm (AC-1a.3, AC-1a.6)
# ============================================================
#
# wave-11-lean-spine row 1a: the plan holds claims, `record/` holds proof. From
# current: 5 onward, a `discharged` row's AC block must carry an `evidence:`
# key whose value resolves to a real file under <docs-root>/record/ — reusing
# resolve_walk_path()'s own template (record/<file> against the docs root, a
# bare path against the project root, absolute as written, a `..` component
# refused). Pending/blocked and waived rows are exempt, exactly as the
# existing per-tier key loop already is (validate_matrix's row-status
# branches, unchanged by this arm). The key sits last in keys_for_tier()'s
# per-tier list, so every fixture above that intentionally exercises a missing
# OTHER key still blocks on that key first — this arm only bites a block that
# was otherwise complete.

section "Section 39: the matrix evidence-path arm (AC-1a.3, AC-1a.6)"

# One discharged T1 row, complete per-tier keys (tier-run, readback), plus an
# `evidence:` value the caller supplies raw (after the colon) — the fixture
# varies only that one line.
evidence_matrix() {  # $1 = the evidence: value to write
  cat <<EOF
## Verification Matrix

stack-health: n/a: no long-running serve

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1 | T1 | discharged | see AC-1 | CONFIRMED |

AC-1:
  fails-when: the planted defect this eval must go red on
  tier-run: bash test.sh — unit suite
  readback: 332/332 asserted
  evidence: $1
EOF
}

# 39a — a path-cited evidence value naming a real file under record/ → allow.
# The whole plan is well under the 40 KB cap (AC-1a.1) — this fixture is a few
# hundred bytes, not the wave's own 40 KB-adjacent plan.
h39a=$(make_home)
mkdir -p "$h39a/.bionic/docs/record/wave-11-lean-spine/evidence"
printf 'AC-1: the unit suite went green — 332/332, output attached.\n' \
  > "$h39a/.bionic/docs/record/wave-11-lean-spine/evidence/AC-1.md"
write_plan "$h39a" "$(plan 5 "$step5_base" "$(evidence_matrix 'record/wave-11-lean-spine/evidence/AC-1.md')")" > /dev/null
expect_allow "39a discharged row, evidence: a real file under record/ → allow" \
  "$h39a" 'git commit -m "x"'

# 39b — an empty evidence value refuses, naming the row.
h39b=$(make_home)
write_plan "$h39b" "$(plan 5 "$step5_base" "$(evidence_matrix '')")" > /dev/null
expect_block "39b discharged row, evidence: empty → block, naming the row" \
  "$h39b" 'git commit -m "x"' "AC-1"

# 39c — a non-empty evidence value naming a path that does not resolve under
# record/ (a real file, just in the wrong place) refuses the same way the
# walk-artifact arm does for the identical shape (Section 26j).
h39c=$(make_home)
mkdir -p "$h39c/.bionic/docs/plans"
printf 'wrongly placed\n' > "$h39c/.bionic/docs/plans/AC-1.md"
write_plan "$h39c" "$(plan 5 "$step5_base" "$(evidence_matrix '.bionic/docs/plans/AC-1.md')")" > /dev/null
expect_block "39c discharged row, evidence: path outside record/ → block" \
  "$h39c" 'git commit -m "x"' "does not resolve under"

# 39d — the same climb-out shape the walk arm refuses (Section 26i): a `..`
# component is refused outright, before any file test.
h39d=$(make_home)
printf 'escaped\n' > "$h39d/.bionic/docs/escaped.md"
write_plan "$h39d" "$(plan 5 "$step5_base" "$(evidence_matrix 'record/../escaped.md')")" > /dev/null
expect_block "39d discharged row, evidence: path climbing out of record/ → block" \
  "$h39d" 'git commit -m "x"' "climbs out of"

# 39e — a pending row carries no evidence contract yet (the same exemption
# the per-tier key loop already gives it) — control for 39a-d.
h39e=$(make_home)
evidence_matrix_pending="## Verification Matrix

stack-health: n/a: no long-running serve

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1 | T1 | pending | see AC-1 |  |"
write_plan "$h39e" "$(plan 5 "$step5_base" "$evidence_matrix_pending")" > /dev/null
expect_allow "39e pending row, no evidence: key at all → allow (exempt, mid-discharge)" \
  "$h39e" 'git commit -m "x"'

# ============================================================
section "Section 40: the matrix survives a section larger than the pipe buffer (T37)"
# ============================================================
#
# THE DEFECT THIS SECTION EXISTS FOR. walls.sh tested for the `stack-health:` line with
# `echo "$MATRIX" | grep -qE …` under hooks/bash-walls.sh's `set -uo pipefail` (:86).
# `grep -q` exits at its FIRST match — the second line of the section — while `echo` is
# still writing the rest; past the 64 KB pipe buffer the producer has not drained, takes
# SIGPIPE, and exits 141, and `pipefail` promotes that 141 over grep's own 0. `if !` then
# reads a MATCH as a failure and the gate refuses. On 2026-09-15 this refused EVERY commit
# in this repo, on a plan carrying a valid stack-health line, once its matrix section
# reached 80,294 B (PIPESTATUS=141 0, record/wave-14-tune-181/T37-red.log).
#
# WHAT THE FIXTURE PADS, AND WHY IT IS NOT A DOCTORED LINE. The stack-health line itself is
# untouched — doctoring it would test a different thing. The padding is a long operator
# note appended to the last AC evidence block: indented prose, no `key:` at line start, no
# leading `|`, no fence, so every parser in the matrix validator sees exactly the fixture
# it saw before, only further away from the line under test. That is the whole variable:
# distance between the match and the end of the data.
t37_pad="$(LC_ALL=C awk 'BEGIN{for(i=1;i<=800;i++) printf "  the operator note for this row continues, line %d, padding this evidence block past the pipe buffer with prose that carries no key of its own\n", i}')"
matrix_t37_big="$matrix_complete
$t37_pad"

# ANTI-VACUITY: if the pad ever stopped clearing the buffer, every row below would pass for
# the wrong reason. 64 KB is the pipe buffer this defect turns on.
expect_eq "40a the padded matrix section really does exceed the 64 KB pipe buffer" "yes" \
  "$([ "${#matrix_t37_big}" -gt 65536 ] && echo yes || echo no)"
expect_contains "40a …and the stack-health line is present and valid, not doctored" \
  "stack-health: process restarts" "$matrix_t37_big"

# 40b — the whole point: an oversized matrix with a VALID stack-health line, at current: 7,
# commits. This is the row that was red before the fix, with the stack-health refusal.
h40b=$(make_home)
write_plan "$h40b" "$(plan 7 "$v9_step7_body" "$matrix_t37_big")" > /dev/null
expect_allow "40b oversized matrix, valid stack-health, current: 7 → allow" \
  "$h40b" 'git commit -m "x"'

# 40c — THE ARM KEEPS ITS POWER. The same oversized fixture with the stack-health line
# REMOVED must still refuse, and for the stack-health reason. Without this row the fix
# could have been "stop checking", which would pass 40b and protect nothing.
matrix_t37_big_nosh="$(printf '%s\n' "$matrix_t37_big" | sed '/^stack-health:/d')"
expect_eq "40c the mutant really did lose the stack-health line (not vacuous)" "1" \
  "$(( $(printf '%s\n' "$matrix_t37_big" | /usr/bin/grep -c '^stack-health:') \
     - $(printf '%s\n' "$matrix_t37_big_nosh" | /usr/bin/grep -c '^stack-health:') ))"
expect_eq "40c …and it is still oversized, so the refusal is not the buffer's doing" "yes" \
  "$([ "${#matrix_t37_big_nosh}" -gt 65536 ] && echo yes || echo no)"
h40c=$(make_home)
write_plan "$h40c" "$(plan 7 "$v9_step7_body" "$matrix_t37_big_nosh")" > /dev/null
expect_block "40c oversized matrix with NO stack-health line → still blocks" \
  "$h40c" 'git commit -m "x"' "stack-health"

# 40d — THE SAME FIXTURE UNPADDED still allows, so 40b's allow is not the padding's doing
# and the two differ in exactly one thing.
h40d=$(make_home)
write_plan "$h40d" "$(plan 7 "$v9_step7_body" "$matrix_complete")" > /dev/null
expect_allow "40d the same matrix UNPADDED, current: 7 → allow (the only variable is size)" \
  "$h40d" 'git commit -m "x"'

# width.sh was sourced by the AC-E1.3 section (now at the end of shard 1); Section 17t reads bionic_cols.
. "${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/width.sh"


# ============================================================
section "R3 — AC-3.1/AC-3.2: a pre-14 plan meets every version-14 fault at once"
# ============================================================
#
# WHAT THIS SECTION EXISTS FOR (seed A §8b–8c, research R2 §2d). A plan whose frontmatter
# says `canonical_sdlc_version: 14` and whose BODY is pre-14 met the gate one arm at a
# time: the `requirements:` arm, then `approved-by:`, then `fails-when:`, then the Tasks
# shape — and the reveal order was DATA-DEPENDENT on the previous repair, because widening
# the table is what makes the next arm reachable (R2 §2d). A round trip per fault, and no
# way to see the size of the job from the first refusal.
#
# AND THE LEAD-IN LIED ON THE WAY (§8b, R2 row 6a). `units_field <row> worktree` reads slot
# 11, which a header without the column leaves EMPTY for every row, so the register arm
# concluded "no ## Tasks row names worktree <tree>" about a table that never claimed to
# track trees. `units_has_column` is the discriminator (tests/units.test.sh §11).
#
# THE FIXTURE IS ONE PLAN CARRYING SIX FAULT CLASSES: a five-column task-scale `## Tasks`
# header (seven required columns absent), the task-scale status word `done`, no
# `requirements:` on the Step-1 line, no `approved-by:` line, a matrix AC block with no
# `fails-when:`, and no `## Goal` first section. It is driven FROM A REAL LINKED WORKTREE,
# because the lead-in this section also pins only speaks on a worktree commit.
#
# fails-when: the pre-14 fixture reveals its faults across two or more attempts at commit,
# or stderr carries "no ## Tasks row names worktree".
# [REQ-3 BRING-FORWARD SECTION: BEGIN]
R3_EXIT=0; R3_ERR=""
r3_commit_knob_unset() {  # <home> <project> <payload cwd> <command> -> R3_EXIT + R3_ERR
  local home_dir="$1" project_dir="$2" payload_cwd="$3" command="$4" input tmp_err
  input=$(jq -n --arg c "$command" --arg cwd "$payload_cwd" --arg s "$EG_SID" \
            '{session_id: $s, tool_input: {command: $c}, cwd: $cwd}')
  tmp_err=$(mktemp)
  eg_autobind "$project_dir"
  if env -u BIONIC_WALL_VERBOSE HOME="$home_dir" CLAUDE_PROJECT_DIR="$project_dir" \
       CLAUDE_CODE_SESSION_ID="$EG_SID" bash "$HOOK" <<< "$input" >/dev/null 2>"$tmp_err"; then
    R3_EXIT=0
  else
    R3_EXIT=$?
  fi
  R3_ERR=$(grep -v -E "$EG_RESOLUTION_RE" "$tmp_err" || true)
  rm -f "$tmp_err"
}
require_helpers r3_commit_knob_unset

# The pre-14 body. Note what it does NOT have: `## Goal`, the ten columns, `requirements:`,
# `approved-by:`, `fails-when:` — and note that `current: 5` and the Step-5 block ARE
# well-formed, so nothing upstream of the bring-forward arm can claim this refusal.
r3_pre14_tasks="## Tasks

| id | intent | rigor | description | status |
|---|---|---|---|---|
| T1 | build | double | the dispatched unit | done |"

r3_pre14_plan() {
  # d7_wave_frontmatter, not matrix_frontmatter: the requirements and fails-when arms are
  # guarded to `rigor: double` + `multi_agent: true` + wave|epic (walls.sh's D7 guard), and
  # matrix_frontmatter writes no `multi_agent:` line at all — a fixture built on it would
  # exercise only the two unguarded halves and call that the whole list.
  printf '%s\n' "$(d7_wave_frontmatter double true)"
  printf '## Overview\n\nA plan written to the pre-14 contract.\n\n'
  printf '## SDLC State\ncurrent: 5\nStep 1: opened 2026-09-19T22:00Z; research record/w16/r.md\nStep 5:\n%s\n- T1: bash suite 9/9 green\n\n' "$step5_base"
  printf '%s\n\n' "$r3_pre14_tasks"
  printf '## Verification Matrix\n\nstack-health: n/a: no long-running serve\n\n'
  printf '| AC | tier | status | evidence | auditor |\n|---|---|---|---|---|\n'
  printf '| AC-1 | T1 | discharged | see AC-1 | CONFIRMED |\n\n'
  printf 'AC-1:\n  evidence: record/w16/r.md\n'
}

r3_tmp=$(cd "$(mktemp -d)" && pwd -P); cleanup_dirs+=("$r3_tmp")
r3_main="$r3_tmp/main"
mkdir -p "$r3_main/.bionic/docs/plans" "$r3_main/.bionic/docs/record/w16"
printf 'evidence\n' > "$r3_main/.bionic/docs/record/w16/r.md"
git -C "$r3_main" init -q .
git -C "$r3_main" commit -q --allow-empty -m init
engage "$r3_main"
r3_pre14_plan > "$r3_main/.bionic/docs/plans/wave-16-pre14.plan.md"
git -C "$r3_main" worktree add -q "$r3_tmp/wt-T1" -b r3-t1

expect_eq "R3.0 the fixture's tree really is a LINKED worktree (its .git is a file)" "file" \
  "$(if [ -f "$r3_tmp/wt-T1/.git" ]; then echo file; else echo none; fi)"

r3_commit_knob_unset "$(make_home)" "$r3_main" "$r3_tmp/wt-T1" 'git commit -m "x"'

expect_status "R3a the pre-14 plan is refused, fail-closed" "2" "$R3_EXIT"
expect_eq "R3b …once: exactly one rendered refusal line" "1" \
  "$(printf '%s\n' "$R3_ERR" | /usr/bin/grep -c '^bionic: ')"
expect_eq "R3c …and the verdict names the contract version, not one arm" \
  "bionic: commit refused — this plan's body is not at contract version 14 (bring the plan forward)" \
  "$(printf '%s\n' "$R3_ERR" | /usr/bin/grep -m1 '^bionic: ')"
# THE SIX CLASSES, each read by the one string only its own check can produce. Six
# assertions rather than a count, so a list that names five and repeats one cannot pass.
expect_contains "R3d(1) …the Tasks table's absent columns, named together on one line" \
  "## Tasks: the table is missing columns: step task agent deps size serves Files" "$R3_ERR"
expect_contains "R3d(2) …the wave-scale status vocabulary" \
  "T1: status done is not one of pending active landed dropped" "$R3_ERR"
expect_contains "R3d(3) …the Step-1 requirements pointer" \
  "## SDLC State: the Step 1 evidence names no 'requirements:' pointer" "$R3_ERR"
expect_contains "R3d(4) …the approval line" \
  "## SDLC State: no 'approved-by:' line" "$R3_ERR"
expect_contains "R3d(5) …the matrix's fails-when" \
  "## Verification Matrix: no AC block names a 'fails-when:'" "$R3_ERR"
expect_contains "R3d(6) …and the missing Goal section" \
  "## Goal: the first section is not '## Goal'" "$R3_ERR"
# AC-3.2. The lead-in is a bare printf on stderr, not a refusal, so it is read off the
# whole stream and asserted ABSENT.
expect_absent "R3e AC-3.2 the worktree lead-in does not print when the table has no worktree column" \
  "no ## Tasks row names worktree" "$R3_ERR"
# NOT VACUOUS: the same commit from the same tree against a plan whose table DOES carry the
# column, and no row naming this tree, still prints the lead-in — so R3e read a suppression
# and not a hook that stopped printing lead-ins.
r3_wt_plan() {
  printf '%s\n' "$(d7_wave_frontmatter double true)"
  printf '## Goal\n\nThe control.\n\n'
  printf '## SDLC State\ncurrent: 5\napproved-by: fixture 2026-09-19T00:00Z "approved"\nStep 1: requirements: record/w16/r.md\nStep 5:\n%s\n- T1: bash suite 9/9 green\n\n' "$step5_base"
  printf '## Tasks\n\n| id | step | kind | task | agent | deps | size | serves | Files | worktree | status |\n'
  printf '|---|---|---|---|---|---|---|---|---|---|---|\n'
  printf '| T1 | 4 | build | the unit | implementor | — | 30m | REQ-x | a.sh | wt-elsewhere | active |\n\n'
  printf '%s\n' "$matrix_complete"
}
r3_main2="$r3_tmp/main2"
mkdir -p "$r3_main2/.bionic/docs/plans" "$r3_main2/.bionic/docs/record/w16"
printf 'evidence\n' > "$r3_main2/.bionic/docs/record/w16/r.md"
printf 'evidence\n' > "$r3_main2/.bionic/docs/record/generic-evidence.md"
git -C "$r3_main2" init -q .
git -C "$r3_main2" commit -q --allow-empty -m init
engage "$r3_main2"
r3_wt_plan > "$r3_main2/.bionic/docs/plans/wave-16-wt.plan.md"
git -C "$r3_main2" worktree add -q "$r3_tmp/wt-T2" -b r3-t2
r3_commit_knob_unset "$(make_home)" "$r3_main2" "$r3_tmp/wt-T2" 'git commit -m "x"'
expect_contains "R3f …while a table that DOES carry the column still gets the lead-in (the control)" \
  "no ## Tasks row names worktree" "$R3_ERR"

# THE OTHER CALLER, ON THE SAME BODY (wave-16 T25, Step-6 critic §C1). `plan_bring_forward`
# used to be HANDED the step, and this gate and the governing-skill hook handed it different
# facts: the gate the body's `current:`, the hook the frontmatter's `sdlc-step:`. The gate
# was never wrong — the hook was — but AC-3.1 is about the two lists being THE SAME, and a
# fixture carrying a misleading stamp is the only fixture that can say so. This one carries
# `sdlc-step: 3` in its frontmatter and `current: 5` in its body, and the gate must answer
# for the body: the stamp is not a fact about where the plan is.
#
# THE SAME FAULT CLASSES THE GOVERNING-SKILL SUITE DRIVES through its own caller (that
# suite's R3s0-R3s7): the same five-column `## Tasks` table byte for byte, the same Step-1
# `requirements:` pointer present, a `## Goal` present, and `approved-by:` and `fails-when:`
# absent. Each suite builds its frontmatter and its Step-5 block with its own helpers —
# neither is a class in the list — so what is shared is exactly what is under test.
# The five strings below are the five that suite asserts — a list that differed between the
# two callers would mean a writer repaired what one named and then met what the other kept
# to itself, which is the whole of AC-3.1.
#
# fails-when: the stamped fixture is admitted, the gate answers for `sdlc-step` rather than
# `current:`, or its list is not the governing-skill hook's list.
# The same table as the governing-skill suite drives, with a status word the wave-scale
# vocabulary accepts — so the only row faults in the list are the ones a five-column header
# forces, and the two `>= 4` classes are what the fixture is really about.
r3_pre14_tasks_pending="## Tasks

| id | intent | rigor | description | status |
|---|---|---|---|---|
| T1 | build | double | the dispatched unit | pending |"

r3s_frontmatter() {  # d7_wave_frontmatter + the misleading Step-0 stamp, inserted in place
  d7_wave_frontmatter double true | awk '/^---$/ && ++n == 2 { print "sdlc-step: 3" } { print }'
}
r3s_plan() {
  printf '%s\n' "$(r3s_frontmatter)"
  printf '## Goal\n\nThe stamp fixture.\n\n'
  # The Step-5 block is here because arms UPSTREAM of the bring-forward one refuse a plan
  # with no evidence line for its current step, and a fixture stopped there would say
  # nothing about the predicate. It is well-formed for the same reason `current: 5` is.
  printf '## SDLC State\ncurrent: 5\nStep 1: opened 2026-09-19T22:00Z; requirements: specs/epic-01-demo/w.requirements.md\nStep 5:\n%s\n- T1: bash suite 9/9 green\n\n' "$step5_base"
  printf '%s\n\n' "$r3_pre14_tasks_pending"
  printf '## Verification Matrix\n\nstack-health: n/a: no long-running serve\n\n'
  printf '| AC | tier | status | evidence | auditor |\n|---|---|---|---|---|\n'
  printf '| AC-1 | T1 | discharged | see AC-1 | CONFIRMED |\n'
}
r3s_main="$r3_tmp/main3"
mkdir -p "$r3s_main/.bionic/docs/plans" "$r3s_main/.bionic/docs/record/w16"
printf 'evidence\n' > "$r3s_main/.bionic/docs/record/w16/r.md"
git -C "$r3s_main" init -q .
git -C "$r3s_main" commit -q --allow-empty -m init
engage "$r3s_main"
r3s_plan > "$r3s_main/.bionic/docs/plans/wave-16-stamp.plan.md"

expect_eq "R3s0 meta: the fixture really does carry a stamp its body disagrees with" \
  "sdlc-step=3 current=5" \
  "sdlc-step=$(/usr/bin/grep -m1 '^sdlc-step:' "$r3s_main/.bionic/docs/plans/wave-16-stamp.plan.md" | tr -cd '0-9') current=$(/usr/bin/grep -m1 '^current:' "$r3s_main/.bionic/docs/plans/wave-16-stamp.plan.md" | tr -cd '0-9')"

r3_commit_knob_unset "$(make_home)" "$r3s_main" "$r3s_main" 'git commit -m "x"'

expect_status "R3s1 the stamped pre-14 plan is refused, fail-closed" "2" "$R3_EXIT"
expect_eq "R3s2 …with the contract-version verdict, not the table alone" \
  "bionic: commit refused — this plan's body is not at contract version 14 (bring the plan forward)" \
  "$(printf '%s\n' "$R3_ERR" | /usr/bin/grep -m1 '^bionic: ')"
expect_contains "R3s3(1) …the pre-14 table that arms the predicate" \
  "## Tasks: the table is missing columns: step task agent deps size serves Files" "$R3_ERR"
expect_contains "R3s3(2) …the first row fault a five-column header forces" \
  "T1: step (empty) is outside 3-9" "$R3_ERR"
expect_contains "R3s3(3) …the second" \
  "T1: kind double is not one of build test verify review doc integrate close prototype" "$R3_ERR"
expect_contains "R3s3(4) …the approval line, owed from current 4 and answered for current 5" \
  "## SDLC State: no 'approved-by:' line" "$R3_ERR"
expect_contains "R3s3(5) …and the matrix's fails-when, owed from the same step" \
  "## Verification Matrix: no AC block names a 'fails-when:'" "$R3_ERR"
# DERIVED, NOT BLANKET — the two classes this body satisfies are absent, exactly as they are
# from the governing-skill hook's list. Paired with R3s3(1)-(5) over the same refusal.
expect_absent "R3s4(1) …the requirements pointer this body carries is not named" \
  "the Step 1 evidence names no 'requirements:' pointer" "$R3_ERR"
expect_absent "R3s4(2) …nor the '## Goal' section this body carries" \
  "## Goal:" "$R3_ERR"

# THE CRLF TWIN (wave-16 T27, critic C7). Byte-for-byte the R3s fixture above — same
# frontmatter-stamp/body disagreement, same pre-14 table — translated to CRLF line endings
# with `perl -pe 's/\n/\r\n/'`, the critic's own repro technique. Before the fix,
# `_bf_section` and the `first_heading` awk inside `plan_bring_forward` read the plan RAW:
# a CRLF `## SDLC State` heading matched nothing, the derived step fell through to 0, and
# the predicate returned silently — the gate ADMITTED a pre-14 CRLF plan the SAME body's LF
# twin refuses six lines for (this is the RED; see T27-crlf-one-source.md). This is the
# governing-skill suite's R3t twin, driving the OTHER caller over the same body.
#
# fails-when: the CRLF commit is admitted, or its refusal names a different list than the
# LF twin's (R3s3(1)-(5) above).
r3t_lf="$(r3s_plan)"
r3t_crlf="$(printf '%s' "$r3t_lf" | perl -pe 's/\n/\r\n/')"

r3t_main="$r3_tmp/main-t27"
mkdir -p "$r3t_main/.bionic/docs/plans" "$r3t_main/.bionic/docs/record/w16" \
  "$r3t_main/.bionic/docs/specs/epic-01-demo"
printf 'evidence\n' > "$r3t_main/.bionic/docs/record/w16/r.md"
# `r3s_plan`'s Step 1 line names this file but never creates it (true of R3s above too) —
# harmless there because the bring-forward arm refuses first on the LF twin, but on the
# UNFIXED CRLF path bring-forward fails open and this arm is next, which would refuse for
# an unrelated reason and mask the defect this row exists to show. Created here so R3t
# isolates the one thing under test.
printf 'requirements\n' > "$r3t_main/.bionic/docs/specs/epic-01-demo/w.requirements.md"
git -C "$r3t_main" init -q .
git -C "$r3t_main" commit -q --allow-empty -m init
engage "$r3t_main"
printf '%s' "$r3t_crlf" > "$r3t_main/.bionic/docs/plans/wave-16-t27-crlf.plan.md"

# META FIRST, so no row below can pass over a fixture that lost its own CRLF-ness.
expect_contains "R3t0 meta: the twin fixture really is CRLF-terminated" \
  "CRLF" "$(file "$r3t_main/.bionic/docs/plans/wave-16-t27-crlf.plan.md")"

r3_commit_knob_unset "$(make_home)" "$r3t_main" "$r3t_main" 'git commit -m "x"'

expect_status "R3t1 the CRLF pre-14 plan is refused at commit, fail-closed — same as its LF twin" "2" "$R3_EXIT"
expect_eq "R3t2 …with the contract-version verdict, not admitted silently" \
  "bionic: commit refused — this plan's body is not at contract version 14 (bring the plan forward)" \
  "$(printf '%s\n' "$R3_ERR" | /usr/bin/grep -m1 '^bionic: ')"
expect_contains "R3t3(1) …the pre-14 table that arms the predicate" \
  "## Tasks: the table is missing columns: step task agent deps size serves Files" "$R3_ERR"
expect_contains "R3t3(2) …the first row fault a five-column header forces" \
  "T1: step (empty) is outside 3-9" "$R3_ERR"
expect_contains "R3t3(3) …the second" \
  "T1: kind double is not one of build test verify review doc integrate close prototype" "$R3_ERR"
expect_contains "R3t3(4) …the approval line, owed from current 4 and answered for current 5" \
  "## SDLC State: no 'approved-by:' line" "$R3_ERR"
expect_contains "R3t3(5) …and the matrix's fails-when, owed from the same step" \
  "## Verification Matrix: no AC block names a 'fails-when:'" "$R3_ERR"
expect_absent "R3t4(1) …the requirements pointer this body carries is not named" \
  "the Step 1 evidence names no 'requirements:' pointer" "$R3_ERR"
expect_absent "R3t4(2) …nor the '## Goal' section this body carries" \
  "## Goal:" "$R3_ERR"

# THE BOM TWIN (T8; REQ-11; wave-16 critic-b77d5aa C10; research R4 §D3). Byte-for-byte the
# r3t_lf plan above, prefixed with a UTF-8 byte-order mark on its very first byte.
# `plan_bring_forward`'s normalization awk compares the whole first record to "---" with
# `==`, which is BOM-insensitive, but every reader downstream (`_bf_fm_get`, `first_heading`)
# matches an ANCHORED regex, which the BOM defeats the same way a CRLF line ending defeated
# it above — so a BOM-prefixed pre-14 plan admitted silently before the fix (research R4
# D3.3-D3.4: octal and `\x` escapes in an awk REGEX do not strip a BOM on awk 20200816; only
# a STRING compare against "\357\273\277" does).
#
# fails-when: the BOM commit is admitted, or its refusal names a different list than the LF
# twin's (R3t3(1)-(5) above); or a direct call to `plan_bring_forward` on the BOM twin
# differs from a direct call on the LF twin.
r3u_bom="$(printf '\357\273\277%s' "$r3t_lf")"
r3u_bomcrlf="$(printf '\357\273\277%s' "$r3t_crlf")"

r3u_main="$r3_tmp/main-t8-bom"
mkdir -p "$r3u_main/.bionic/docs/plans" "$r3u_main/.bionic/docs/record/w16" \
  "$r3u_main/.bionic/docs/specs/epic-01-demo"
printf 'evidence\n' > "$r3u_main/.bionic/docs/record/w16/r.md"
printf 'requirements\n' > "$r3u_main/.bionic/docs/specs/epic-01-demo/w.requirements.md"
git -C "$r3u_main" init -q .
git -C "$r3u_main" commit -q --allow-empty -m init
engage "$r3u_main"
printf '%s' "$r3u_bom" > "$r3u_main/.bionic/docs/plans/wave-16-t8-bom.plan.md"

# META FIRST, so no row below can pass over a fixture that lost its own BOM.
expect_eq "R3u0 meta: the twin fixture really opens with a UTF-8 BOM" "efbbbf" \
  "$(head -c3 "$r3u_main/.bionic/docs/plans/wave-16-t8-bom.plan.md" | xxd -p)"

r3_commit_knob_unset "$(make_home)" "$r3u_main" "$r3u_main" 'git commit -m "x"'

expect_status "R3u1 the BOM pre-14 plan is refused at commit, fail-closed — same as its LF twin" "2" "$R3_EXIT"
expect_eq "R3u2 …with the contract-version verdict, not admitted silently" \
  "bionic: commit refused — this plan's body is not at contract version 14 (bring the plan forward)" \
  "$(printf '%s\n' "$R3_ERR" | /usr/bin/grep -m1 '^bionic: ')"
expect_contains "R3u3(1) …the pre-14 table that arms the predicate" \
  "## Tasks: the table is missing columns: step task agent deps size serves Files" "$R3_ERR"
expect_contains "R3u3(2) …the first row fault a five-column header forces" \
  "T1: step (empty) is outside 3-9" "$R3_ERR"
expect_contains "R3u3(3) …the second" \
  "T1: kind double is not one of build test verify review doc integrate close prototype" "$R3_ERR"
expect_contains "R3u3(4) …the approval line, owed from current 4 and answered for current 5" \
  "## SDLC State: no 'approved-by:' line" "$R3_ERR"
expect_contains "R3u3(5) …and the matrix's fails-when, owed from the same step" \
  "## Verification Matrix: no AC block names a 'fails-when:'" "$R3_ERR"
expect_absent "R3u4(1) …the requirements pointer this body carries is not named" \
  "the Step 1 evidence names no 'requirements:' pointer" "$R3_ERR"
expect_absent "R3u4(2) …nor the '## Goal' section this body carries" \
  "## Goal:" "$R3_ERR"

# THE BOM+CRLF TWIN — a Windows editor emits both at once (research R4 D3.6 row-27 note).
# Same six checks, same file, over the combined fixture.
r3v_main="$r3_tmp/main-t8-bomcrlf"
mkdir -p "$r3v_main/.bionic/docs/plans" "$r3v_main/.bionic/docs/record/w16" \
  "$r3v_main/.bionic/docs/specs/epic-01-demo"
printf 'evidence\n' > "$r3v_main/.bionic/docs/record/w16/r.md"
printf 'requirements\n' > "$r3v_main/.bionic/docs/specs/epic-01-demo/w.requirements.md"
git -C "$r3v_main" init -q .
git -C "$r3v_main" commit -q --allow-empty -m init
engage "$r3v_main"
printf '%s' "$r3u_bomcrlf" > "$r3v_main/.bionic/docs/plans/wave-16-t8-bomcrlf.plan.md"

expect_eq "R3v0 meta: the BOM+CRLF twin opens with the BOM and is CRLF-terminated" "efbbbf CRLF" \
  "$(head -c3 "$r3v_main/.bionic/docs/plans/wave-16-t8-bomcrlf.plan.md" | xxd -p) $(file "$r3v_main/.bionic/docs/plans/wave-16-t8-bomcrlf.plan.md" | /usr/bin/grep -o CRLF)"

r3_commit_knob_unset "$(make_home)" "$r3v_main" "$r3v_main" 'git commit -m "x"'

expect_status "R3v1 the BOM+CRLF pre-14 plan is refused at commit, fail-closed" "2" "$R3_EXIT"
expect_eq "R3v2 …with the contract-version verdict, not admitted silently" \
  "bionic: commit refused — this plan's body is not at contract version 14 (bring the plan forward)" \
  "$(printf '%s\n' "$R3_ERR" | /usr/bin/grep -m1 '^bionic: ')"
expect_contains "R3v3(1) …the pre-14 table that arms the predicate" \
  "## Tasks: the table is missing columns: step task agent deps size serves Files" "$R3_ERR"
expect_contains "R3v3(2) …the first row fault a five-column header forces" \
  "T1: step (empty) is outside 3-9" "$R3_ERR"
expect_contains "R3v3(3) …the second" \
  "T1: kind double is not one of build test verify review doc integrate close prototype" "$R3_ERR"
expect_contains "R3v3(4) …the approval line, owed from current 4 and answered for current 5" \
  "## SDLC State: no 'approved-by:' line" "$R3_ERR"
expect_contains "R3v3(5) …and the matrix's fails-when, owed from the same step" \
  "## Verification Matrix: no AC block names a 'fails-when:'" "$R3_ERR"
expect_absent "R3v4(1) …the requirements pointer this body carries is not named" \
  "the Step 1 evidence names no 'requirements:' pointer" "$R3_ERR"
expect_absent "R3v4(2) …nor the '## Goal' section this body carries" \
  "## Goal:" "$R3_ERR"

# THE FUNCTION-LEVEL ROW, no hook in the loop — AC-11.1's "same list at both callers" read
# directly: `plan_bring_forward` on the BOM twin, and on the BOM+CRLF twin, must return the
# SAME lines as `plan_bring_forward` on the LF twin — a diff of the outputs empty.
r3u_lf_file="$(mktemp "${TMPDIR:-/tmp}/r3u-lf.XXXXXX")"
printf '%s' "$r3t_lf" > "$r3u_lf_file"
r3u_lf_direct="$(bash -c '. "$1"; . "$2"; plan_bring_forward "$3"' _ \
  "${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/units.sh" \
  "${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/walls.sh" "$r3u_lf_file" 2>/dev/null || true)"
rm -f "$r3u_lf_file"

r3u_bom_direct="$(bash -c '. "$1"; . "$2"; plan_bring_forward "$3"' _ \
  "${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/units.sh" \
  "${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/walls.sh" \
  "$r3u_main/.bionic/docs/plans/wave-16-t8-bom.plan.md" 2>/dev/null || true)"
expect_eq "R3u5 …the predicate's own output on the BOM twin, diffed against the LF twin's — empty" \
  "" "$(diff <(printf '%s\n' "$r3u_lf_direct") <(printf '%s\n' "$r3u_bom_direct") 2>&1 || true)"

r3v_bomcrlf_direct="$(bash -c '. "$1"; . "$2"; plan_bring_forward "$3"' _ \
  "${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/units.sh" \
  "${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/walls.sh" \
  "$r3v_main/.bionic/docs/plans/wave-16-t8-bomcrlf.plan.md" 2>/dev/null || true)"
expect_eq "R3v5 …the predicate's own output on the BOM+CRLF twin, diffed against the LF twin's — empty" \
  "" "$(diff <(printf '%s\n' "$r3u_lf_direct") <(printf '%s\n' "$r3v_bomcrlf_direct") 2>&1 || true)"
# [REQ-3 BRING-FORWARD SECTION: END]

# ============================================================
section "R3 — AC-3.3: 'requirements:' is read anywhere on the Step-1 line (seed B B11)"
# ============================================================
#
# THE FIELD REPRO (seed B B11, measured 2026-09-19). `validate_requirements_pointer` greps
# `^[[:space:]]*requirements[[:space:]]*:` against the Step-1 evidence BLOCK, so a Step-1
# line that opens with anything else — `- Step 1: opened …; requirements: specs/…; card …`,
# the shape this wave's own plan very nearly took — carries a resolving pointer the arm
# cannot see, and the commit is refused "Step 1's evidence names no requirements file".
# The sibling pointer read on the Step-5 line (`walk-artifact:`) has the same anchor and
# gets the same tolerance; its control is R3j below.
#
# fails-when: the B11 line is refused, or a line with NO requirements pointer is admitted.
# [REQ-3 POINTER-TOLERANCE SECTION: BEGIN]
r3b11_plan() {  # $1 = the Step-1 line's text after "Step 1: "
  printf '%s\n' "$(d7_wave_frontmatter double true)"
  printf '## Goal\n\nThe B11 fixture.\n\n'
  printf '## SDLC State\ncurrent: 4\napproved-by: fixture 2026-09-19T00:00Z "approved"\n- Step 1: %s\nStep 4: opened; evidence record/generic-evidence.md\n\n' "$1"
  printf '%s\n\n' "$tasks_one_done"
  printf -- '- T1: bash suite 9/9 green\n\n'
  printf '%s\n' "$matrix_complete"
}

h_r3b11=$(make_home)
mkdir -p "$h_r3b11/.bionic/docs/specs/epic-01-demo"
printf 'requirements\n' > "$h_r3b11/.bionic/docs/specs/epic-01-demo/w16.requirements.md"
write_plan "$h_r3b11" "$(r3b11_plan 'opened 2026-09-19T22:00Z; requirements: specs/epic-01-demo/w16.requirements.md; card approved by chris')" > /dev/null
expect_allow "R3g AC-3.3 the B11 line — 'requirements:' mid-line — is admitted" \
  "$h_r3b11" 'git commit -m "x"'

# THE CONTROL, so R3g did not pass because the arm stopped asking: the same line with the
# pointer removed is still refused, and a pointer that resolves to nothing still is.
h_r3b11b=$(make_home)
write_plan "$h_r3b11b" "$(r3b11_plan 'opened 2026-09-19T22:00Z; card approved by chris')" > /dev/null
expect_block "R3h …a Step-1 line with no requirements pointer at all is still refused" \
  "$h_r3b11b" 'git commit -m "x"' "requirements"
h_r3b11c=$(make_home)
write_plan "$h_r3b11c" "$(r3b11_plan 'opened; requirements: specs/epic-01-demo/absent.requirements.md; card approved')" > /dev/null
expect_block "R3i …and a mid-line pointer naming no file is refused for THAT reason" \
  "$h_r3b11c" 'git commit -m "x"' "does not resolve"
# AND IT MUST NOT MATCH A LONGER KEY: `pre-requirements:` is a different field and naming
# one is not naming the artifact.
h_r3b11d=$(make_home)
write_plan "$h_r3b11d" "$(r3b11_plan 'opened; pre-requirements: specs/epic-01-demo/w16.requirements.md; card approved')" > /dev/null
expect_block "R3j …and 'pre-requirements:' is not 'requirements:'" \
  "$h_r3b11d" 'git commit -m "x"' "requirements"
# [REQ-3 POINTER-TOLERANCE SECTION: END]

# ============================================================
section "R12 — AC-12.2: a placeholder auditor cell parses empty (carry-over 20)"
# ============================================================
#
# CARRY-OVER 20. A matrix row's auditor cell is a free-text cell, and a table author who has
# no verdict to record writes the same em dash the `deps` and `worktree` cells use for
# "none". The T4 exemption asks for an auditor cell that is EMPTY or `CONFIRMED`
# (walls.sh:2953), so `—` — which means exactly "empty" to every human who reads the table
# and to every other cell in the ten-column contract — took the row to the refusal that
# exists for a STANDING FINDING, and told its author to settle a verdict nobody had given.
#
# THREE SPELLINGS, one rule: `—`, `-` and `n/a` fold to empty. A real verdict does not.
#
# fails-when: the `—` fixture refuses, or `REFUTED` stops refusing.
# [REQ-12 AUDITOR-CELL SECTION: BEGIN]
h_r12a=$(make_home)
write_plan "$h_r12a" "$(wave_plan 6 "$step6_body" "$(t4_matrix T4 "—" "$GOOD_CONFIRM")")" > /dev/null
expect_allow "R12a AC-12.2 a T4 row whose auditor cell is an em dash discharges on user-confirmed" \
  "$h_r12a" 'git commit -m "x"'
h_r12b=$(make_home)
write_plan "$h_r12b" "$(wave_plan 6 "$step6_body" "$(t4_matrix T4 "-" "$GOOD_CONFIRM")")" > /dev/null
expect_allow "R12b …and an ASCII hyphen" "$h_r12b" 'git commit -m "x"'
h_r12c=$(make_home)
write_plan "$h_r12c" "$(wave_plan 6 "$step6_body" "$(t4_matrix T4 "n/a" "$GOOD_CONFIRM")")" > /dev/null
expect_allow "R12c …and 'n/a'" "$h_r12c" 'git commit -m "x"'
# THE DISCRIMINATION. A cell carrying a real verdict is not a placeholder, and the arm that
# exists for a standing finding still fires on it.
h_r12d=$(make_home)
write_plan "$h_r12d" "$(wave_plan 6 "$step6_body" "$(t4_matrix T4 "REFUTED" "$GOOD_CONFIRM")")" > /dev/null
expect_block "R12d …while a standing REFUTED still refuses (the fold discriminates)" \
  "$h_r12d" 'git commit -m "x"' "REFUTED"
# AND THE NON-T4 DIRECTION IS UNTOUCHED: a T3 row's placeholder cell is not a confirmation.
h_r12e=$(make_home)
write_plan "$h_r12e" "$(wave_plan 6 "$step6_body" "$(t4_matrix T3 "—" "$GOOD_CONFIRM")")" > /dev/null
expect_block "R12e …and a T3 row with the same placeholder cell still needs its auditor" \
  "$h_r12e" 'git commit -m "x"' "auditor"
# [REQ-12 AUDITOR-CELL SECTION: END]

# ============================================================
section "Section 17t: §17's cells refuse by their SHAPE (wave-17 REQ-5, REQ-10; AC-5.1-5.4, AC-10.2)"
# ============================================================
#
# WHAT THIS SECTION IS ABOUT. Four arms that knew the whole fault and printed a fraction of
# it, and one key the Step-5 block may now carry. Each row here reads the VERDICT LINE — the
# one line a committer actually sees — not just the detail, because the wording IS the
# subject: the old verdicts were true sentences that sent the author to the wrong place.
#
# fails-when: any of the four prints its pre-wave verdict, or a control that must stay
# admitted is refused.

# ---- AC-5.1: both evidence-line arms count every row, and say the rule ----
#
# THE OLD BEHAVIOUR. Each arm named ONE id and asked for "a '- <id>:' evidence line", so an
# author owing eighteen of them learned of the second only after landing the first
# (wave-16 A-orch-10 is that specimen, eighteen lines deep). Neither said the obligation is
# one line PER ROW.
#
# ONE ARM, AT EITHER SCALE (wave-31 T24; REQ-1, D2). The task-scale arm that fired on the
# ADDRESSED unit's missing line went with `current: T<n>`; a task-scale plan's one table is read
# by the dispatch-ledger arm, as a wave plan's is. 17t1/17t2 are that arm at `scale: task`, and
# 17t3-17t5 below the same arm at wave scale, in the same words.
h17t1=$(make_home)
write_plan "$h17t1" "$(eg_pf_plan 4 task double true "" "$(eg_pf_row T1 — landed)" "$(eg_pf_row T2 — landed)" "$(eg_pf_row T3 — landed)")" > /dev/null
expect_block "17t1 task scale, three landed rows and no evidence lines at all → block" \
  "$h17t1" 'git commit -m "x"' "3 tasks have no evidence line"
expect_eq "17t1b …and the verdict line counts the rows and names the shape that is owed" \
  "bionic: commit refused — 3 tasks have no evidence line (add one '- T<id>:' per row)" \
  "$(printf '%s\n' "$HOOK_STDERR" | /usr/bin/grep '^bionic: ')"
expect_contains "17t1c …and the detail names the first id" "- T1:" "$HOOK_VSTDERR"
expect_contains "17t1d …the second" "- T2:" "$HOOK_VSTDERR"
expect_contains "17t1e …and the third, so one pass shows the whole debt" "- T3:" "$HOOK_VSTDERR"

# THE SINGULAR IS NOT "1 tasks". One row owing one line is the ordinary case, and the
# verdict is a sentence a person reads.
h17t2=$(make_home)
write_plan "$h17t2" "$(eg_pf_plan 4 task double true "- T1: bash suite 9/9 green" "$(eg_pf_row T1 — landed)" "$(eg_pf_row T2 — landed)")" > /dev/null
expect_block "17t2 task scale, one row short of its line → block" \
  "$h17t2" 'git commit -m "x"' "1 task has no evidence line"
expect_eq "17t2b …and the verdict agrees with itself in number" \
  "bionic: commit refused — 1 task has no evidence line (add one '- T<id>:' per row)" \
  "$(printf '%s\n' "$HOOK_STDERR" | /usr/bin/grep '^bionic: ')"

# THE SAME WORDING AT THE OTHER ARM. validate_dispatch_ledger walks every row of an double
# multi_agent wave's table; it used to refuse at the FIRST id it found short.
tasks_three_rows="## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | status |
|---|---|---|---|---|---|---|---|---|---|
| T1 | 4 | build | the first unit | implementor | — | 30m | REQ-x | a.sh | landed |
| T2 | 4 | build | the second unit | implementor | — | 30m | REQ-x | b.sh | landed |
| T3 | 4 | build | the third unit | implementor | — | 30m | REQ-x | c.sh | landed |"
h17t3=$(make_home)
write_plan "$h17t3" "$(d7_wave_plan "$tasks_three_rows" "")" > /dev/null
expect_block "17t3 wave scale, three dispatched rows and no evidence lines → block" \
  "$h17t3" 'git commit -m "x"' "3 tasks have no evidence line"
expect_eq "17t3b …in the same words the task-scale arm uses" \
  "bionic: commit refused — 3 tasks have no evidence line (add one '- T<id>:' per row)" \
  "$(printf '%s\n' "$HOOK_STDERR" | /usr/bin/grep '^bionic: ')"
expect_contains "17t3c …and the detail names every one of the three" "- T3:" "$HOOK_VSTDERR"

# THE MIDDLE ROW ALONE. The arm that stopped at the first id could not see T2 at all while
# T1 was short; this row proves the walk reaches past a row that IS satisfied.
h17t4=$(make_home)
write_plan "$h17t4" "$(d7_wave_plan "$tasks_three_rows" "- T1: bash suite 9/9 green
- T3: bash suite 9/9 green")" > /dev/null
expect_block "17t4 wave scale, only the middle row short → block, naming it" \
  "$h17t4" 'git commit -m "x"' "1 task has no evidence line"
expect_contains "17t4b …and the detail names T2, not T1 or T3" "- T2:" "$HOOK_VSTDERR"

# THE CONTROL. Three rows, three lines, nothing owed.
h17t5=$(make_home)
write_plan "$h17t5" "$(d7_wave_plan "$tasks_three_rows" "- T1: bash suite 9/9 green
- T2: bash suite 9/9 green
- T3: bash suite 9/9 green")" > /dev/null
expect_allow "17t5 wave scale, every row carries its line → allow" \
  "$h17t5" 'git commit -m "x"'

# ---- AC-5.3: `evidence:` takes one path, and a `;` is not a separator ----
#
# THE OLD BEHAVIOUR. `evidence: a.md; b.md` was handed whole to the path resolver, which
# prefixed a root and found no such file, so the refusal read "names no real file" and sent
# the author to write a file at a path no one had meant to name. The sibling reader of the
# walk artifact has truncated at the first `;` since epic-14; this cell is the outlier.
# The arm sits FIRST in the `evidence:` branch, ahead of the climb-out and file tests, so
# the shape fault is named before any question about where the value points.
h17t6=$(make_home)
write_plan "$h17t6" "$(plan 6 "$step6_body" \
  "$(evidence_matrix 'record/generic-evidence.md; record/second-file.md')")" > /dev/null
expect_block "17t6 an evidence: value carrying two paths → block on the shape" \
  "$h17t6" 'git commit -m "x"' "evidence: names more than one path"
expect_eq "17t6b …and the verdict names the cell and the rule, not the missing file" \
  "bionic: commit refused — evidence: names more than one path (one path under record/ per AC)" \
  "$(printf '%s\n' "$HOOK_STDERR" | /usr/bin/grep '^bionic: ')"
expect_contains "17t6c …while the detail names the AC and prints the value back" \
  "AC-1" "$HOOK_VSTDERR"
expect_contains "17t6d …the value included" "record/second-file.md" "$HOOK_VSTDERR"

# THE BARE CONTROL, same fixture, one path: still admitted.
h17t7=$(make_home)
write_plan "$h17t7" "$(plan 6 "$step6_body" "$(evidence_matrix 'record/generic-evidence.md')")" > /dev/null
expect_allow "17t7 …and one path under record/ is admitted exactly as before" \
  "$h17t7" 'git commit -m "x"'

# AND THE ARM DID NOT SWALLOW THE ONES BEHIND IT: a single path that names no file still
# refuses in its own words.
h17t8=$(make_home)
write_plan "$h17t8" "$(plan 6 "$step6_body" "$(evidence_matrix 'record/never-written.md')")" > /dev/null
expect_block "17t8 …and a single path naming no file keeps its own refusal" \
  "$h17t8" 'git commit -m "x"' "names no real file"

# ---- AC-9.1: the evidence: cell tolerates a trailing note (wave-18 REQ-9, D13) ----
#
# THE CELL MAY CARRY A NOTE. Split on the first ' — ' (space, em dash, space) before either
# test above: the path half is what the ';' check and the resolver ever see, so a note that
# itself carries a ';' never trips the "names more than one path" refusal, and the path half
# alone resolves under record/. The note half is discarded — never parsed, never required to
# resolve.
h17t8a=$(make_home)
write_plan "$h17t8a" "$(plan 6 "$step6_body" \
  "$(evidence_matrix 'record/generic-evidence.md — RED on a; GREEN on b')")" > /dev/null
expect_allow "17t8a an evidence: value with a trailing note (the note itself carrying a ';') → the path resolves, admitted" \
  "$h17t8a" 'git commit -m "x"'

# AND A BARE ';'-JOINED VALUE WITH NO NOTE (NO EM DASH) IS STILL REFUSED, TODAY'S WORDING.
h17t8b=$(make_home)
write_plan "$h17t8b" "$(plan 6 "$step6_body" "$(evidence_matrix 'a.md; b.md')")" > /dev/null
expect_block "17t8b …while a bare ';'-joined two-path value with no note is refused exactly as before" \
  "$h17t8b" 'git commit -m "x"' "evidence: names more than one path"

# ---- AC-5.4: the auditor cell is an equality, and the verdict says so ----
#
# THE OLD BEHAVIOUR. `CONFIRMED (audit-b3b87dc.md)` refused with "the auditor has not
# confirmed AC-1" — which reads as "no audit happened" to the one person who knows an audit
# did happen and annotated the cell with its path. The equality is right; the sentence was
# not. A cell that does NOT start with CONFIRMED is a different fact and keeps its verdict.
aud_matrix() {  # $1 = the auditor cell to write
  cat <<EOF
## Verification Matrix

stack-health: n/a: no long-running serve

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1 | T1 | discharged | see AC-1 | $1 |

AC-1:
  fails-when: the planted defect this eval must go red on
  tier-run: bash test.sh — unit suite
  readback: 332/332 asserted
  evidence: record/generic-evidence.md
EOF
}

h17t9=$(make_home)
write_plan "$h17t9" "$(plan 6 "$step6_body" "$(aud_matrix 'CONFIRMED (audit-x.md)')")" > /dev/null
expect_block "17t9 an auditor cell annotated past the token → block on the shape" \
  "$h17t9" 'git commit -m "x"' "the auditor cell is not the bare token"
expect_eq "17t9b …and the verdict no longer says the audit did not happen" \
  "bionic: commit refused — the auditor cell is not the bare token (write CONFIRMED; cite in evidence:)" \
  "$(printf '%s\n' "$HOOK_STDERR" | /usr/bin/grep '^bionic: ')"
expect_contains "17t9c …while the detail prints the cell back verbatim" \
  "CONFIRMED (audit-x.md)" "$HOOK_VSTDERR"
# THE WIDEST LINE THIS WAVE ADDS, PINNED AT ITS MEASURED WIDTH. Both halves are constants,
# so the number is deterministic — and it sits ON the ratified 100-column bound, which
# refuse.sh self-refuses past. Pinned here so a later edit to either half is caught in the
# section that owns the words, not as a refuse-call self-refusal in some unrelated suite.
expect_eq "17t9d …and the rendered line is exactly at the ratified column bound" "100" \
  "$(bionic_cols "$(printf '%s\n' "$HOOK_STDERR" | /usr/bin/grep '^bionic: ')")"

# THE BARE CONTROL: the token alone is admitted.
h17t10=$(make_home)
write_plan "$h17t10" "$(plan 6 "$step6_body" "$(aud_matrix 'CONFIRMED')")" > /dev/null
expect_allow "17t10 …and the bare token is admitted exactly as before" \
  "$h17t10" 'git commit -m "x"'

# THE DISCRIMINATOR: a cell that does not start with CONFIRMED is not a shape fault, and
# the arm that has always spoken for it still does.
h17t11=$(make_home)
write_plan "$h17t11" "$(plan 6 "$step6_body" "$(aud_matrix 'REFUTED')")" > /dev/null
expect_block "17t11 …while a REFUTED cell keeps the pre-wave verdict" \
  "$h17t11" 'git commit -m "x"' "the auditor has not confirmed"
h17t12=$(make_home)
write_plan "$h17t12" "$(plan 6 "$step6_body" "$(aud_matrix ' ')")" > /dev/null
expect_block "17t12 …and so does an empty one" \
  "$h17t12" 'git commit -m "x"' "the auditor has not confirmed"

# ---- AC-10.2: the Step-5 block's two refusals, pinned; then the new key ----
#
# THE TWO REFUSALS BELOW WERE UNPINNED until this wave (research R4 D2.6: no test file
# contained either string). A task that adds a key to this function has to leave them
# standing, and a pin written AFTER the change would prove only that the change kept what
# the change left.
step5_72="  cmd: bash tests/run.sh
  pass: 72
  total: 72
  head: ${EG_HEAD}
  output: .bionic/docs/plans/wave-01.plan.md#step-5
  auditor: 3 rows CONFIRMED — report .bionic/tmp/audit.md"
step5_71="  cmd: bash tests/run.sh
  pass: 71
  total: 72
  output: .bionic/docs/plans/wave-01.plan.md#step-5
  auditor: 3 rows CONFIRMED — report .bionic/tmp/audit.md"
step5_words="  cmd: bash tests/run.sh
  pass: most of them
  total: 72
  output: .bionic/docs/plans/wave-01.plan.md#step-5
  auditor: 3 rows CONFIRMED — report .bionic/tmp/audit.md"

h17t13=$(make_home)
write_plan "$h17t13" "$(plan 5 "$step5_words" "$matrix_complete")" > /dev/null
expect_block "17t13 a Step-5 block whose counters are not integers → block" \
  "$h17t13" 'git commit -m "x"' "'pass:' and 'total:' are not both integers"
expect_eq "17t13b …in those words" \
  "bionic: commit refused — 'pass:' and 'total:' are not both integers (write both as integers)" \
  "$(printf '%s\n' "$HOOK_STDERR" | /usr/bin/grep '^bionic: ')"

h17t14=$(make_home)
write_plan "$h17t14" "$(plan 5 "$step5_71" "$matrix_complete")" > /dev/null
expect_block "17t14 a Step-5 block one test short → block" \
  "$h17t14" 'git commit -m "x"' "the suite is not fully green"
expect_eq "17t14b …in those words" \
  "bionic: commit refused — the suite is not fully green (make pass equal total)" \
  "$(printf '%s\n' "$HOOK_STDERR" | /usr/bin/grep '^bionic: ')"

# THE NEW KEY. `pass:`/`total:` are the GATING counters; an advisory reading is a
# measurement the framework took and nobody gated on, so the gate RECORDS it and does not
# judge it. A block carrying three exceeded advisories on a fully green suite commits.
step5_advisory="  cmd: bash tests/run.sh
  pass: 72
  total: 72
  head: ${EG_HEAD}
  advisory-exceeded: 3
  output: .bionic/docs/plans/wave-01.plan.md#step-5
  auditor: 3 rows CONFIRMED — report .bionic/tmp/audit.md"
h17t15=$(make_home)
write_plan "$h17t15" "$(plan 5 "$step5_advisory" "$matrix_complete")" > /dev/null
expect_allow "17t15 a green Step-5 block carrying advisory-exceeded: 3 → allow (recorded, not judged)" \
  "$h17t15" 'git commit -m "x"'

# THE CONTROL IN THE OTHER DIRECTION: the key launders nothing. A red block carrying a
# zero advisory count is still red.
step5_71_advisory="  cmd: bash tests/run.sh
  pass: 71
  total: 72
  advisory-exceeded: 0
  output: .bionic/docs/plans/wave-01.plan.md#step-5
  auditor: 3 rows CONFIRMED — report .bionic/tmp/audit.md"
h17t16=$(make_home)
write_plan "$h17t16" "$(plan 5 "$step5_71_advisory" "$matrix_complete")" > /dev/null
expect_block "17t16 …and the key does not launder a red block" \
  "$h17t16" 'git commit -m "x"' "the suite is not fully green"

# AND THE KEY IS OPTIONAL: the same green block without it is the pre-wave fixture, byte
# for byte, and still commits.
h17t17=$(make_home)
write_plan "$h17t17" "$(plan 5 "$step5_72" "$matrix_complete")" > /dev/null
expect_allow "17t17 …and a green block that never mentions it is untouched" \
  "$h17t17" 'git commit -m "x"'


# ============================================================
section "REQ-9 — AC-9.1–9.3: jurisdiction ends at the engaged repository (wave-19 T6, D10, ADR-031)"
# ============================================================
#
# WHAT WENT WRONG (A-T11.1, wave-18; reproduced twice in wave-19 R3 Q3). A `git commit` into a
# repository that is not the engaged one — a scratch repo in a scratchpad, or a test bed
# `git init`-ed under the root's own record directory — was judged against THIS run's plan and
# refused for this run's evidence. The gate resolved the plan from the engaged root before it
# ever asked which repository the commit lands in, and the only repository test it had
# (`_eg_git_wt_name`) sees linked worktrees and nothing else.
#
# THE ROOT IS A REAL REPOSITORY with a bound-free engaged session and a `current: 5` plan whose
# Step-5 block is red (71/72), so every commit this gate still judges is REFUSED. That is what
# makes each allow below a verdict about the repository boundary and not about a lenient plan.
s9_tmp=$(cd "$(mktemp -d)" && pwd -P); cleanup_dirs+=("$s9_tmp")
s9_root="$s9_tmp/root"
mkdir -p "$s9_root/.bionic/docs/plans"
git -C "$s9_root" init -q .
git -C "$s9_root" -c user.email=t@example.com -c user.name=T commit -q --allow-empty -m init
write_generic_evidence "$s9_root"
engage "$s9_root"
s9_plan=$(write_project_plan "$s9_root" "$(plan 5 "$step5_71" "$matrix_complete")")
s9_home=$(make_home)

# The expected line is built from the FIXTURE's own paths, never from what the arm computes.
s9_line() {  # <the commit's repository toplevel> -> the one line the gate prints
  printf 'evidence-gate: %s is outside the engaged repository (%s); the evidence gate has no plan here' "$1" "$s9_root"
}
s9_expect_outside() {  # <label> <payload cwd> <command> <toplevel>
  run_hook_cwd "$s9_home" "$s9_root" "$2" "$3"
  if [ "$HOOK_EXIT" -eq 0 ] && [ "$HOOK_STDERR" = "$(s9_line "$4")" ] && [ -z "$HOOK_RESOLUTION" ]; then
    ok "$1"
  else
    no "$1" "expected exit 0 and exactly '$(s9_line "$4")'; exit=$HOOK_EXIT stderr='$HOOK_STDERR' resolution='$HOOK_RESOLUTION' detail='$HOOK_VSTDERR'"
  fi
}
s9_expect_judged() {  # <label> <payload cwd> <command> <substring of the refusal detail>
  run_hook_cwd "$s9_home" "$s9_root" "$2" "$3"
  if [ "$HOOK_EXIT" -eq 2 ] && eg_e1_check && grep -q "$4" <<<"$HOOK_VSTDERR"; then
    ok "$1"
  else
    no "$1" "expected refusal exit 2 naming '$4'; exit=$HOOK_EXIT line='$HOOK_STDERR' detail='$HOOK_VSTDERR'"
  fi
}

# --- 9c: THE CONTROL — inside the root, refused exactly as before ------------------------
s9_expect_judged "9c AC-9.1 a commit in the engaged root at current: 5 without green evidence is refused as before" \
  "$s9_root" 'git commit -m "x"' "the suite is not fully green"
s9_expect_judged "9c …and spelled 'git -C <root> commit', the same refusal" \
  "$s9_root" "git -C $s9_root commit -m x" "the suite is not fully green"
s9_expect_judged "9c …and from a subdirectory of the root, the same refusal (inside is the repository, not the path)" \
  "$s9_root" "git -C $s9_root/.bionic/docs commit -m x" "the suite is not fully green"

# --- 9a: a scratch repository outside the root --------------------------------------------
s9_scratch="$s9_tmp/scratchpad/q1"
mkdir -p "$s9_scratch"
git -C "$s9_scratch" init -q .
s9_expect_outside "9a AC-9.1 'git -C <scratch repo> commit' is admitted with one line naming both repositories" \
  "$s9_root" "git -C $s9_scratch commit -q --allow-empty -m x" "$s9_scratch"
s9_expect_outside "9a …and a leading 'cd <scratch repo> &&' is the same commit, admitted the same way" \
  "$s9_root" "cd $s9_scratch && git commit -m x" "$s9_scratch"
s9_expect_outside "9a …and a payload cwd inside the scratch repo is the same commit too" \
  "$s9_scratch" 'git commit -m "x"' "$s9_scratch"
# A SUBDIRECTORY of the scratch repo is named by its toplevel, which is the repository.
mkdir -p "$s9_scratch/sub/dir"
s9_expect_outside "9a …and '-C' at a subdirectory of the scratch repo names the repository's toplevel" \
  "$s9_root" "git -C $s9_scratch/sub/dir commit -m x" "$s9_scratch"

# THE TWO-DIRECTORY ARM STILL OWNS AN AMBIGUOUS COMMAND. The leading `cd` names the scratch
# repo but a second `cd` walks back into the root before the commit: the shell commits in the
# ROOT. Exempting on the leading directory would be the fail-open that arm exists to close.
s9_expect_judged "9a …but 'cd <scratch> && cd <root> && git commit' is not exempted — two directories, refused" \
  "$s9_root" "cd $s9_scratch && cd $s9_root && git commit -m x" "changes into"

# ONE COMMIT SEGMENT OR NONE EXEMPTED (review R1, wave-19). The arm places the FIRST commit it
# finds, so a command carrying two used to be exempted for the first one's repository while the
# second landed in the root unjudged. Only a positive answer exempts, and a positive answer is
# about ONE commit: any command text carrying two or more commit segments is judged as before.
s9_expect_judged "9a R1 'git -C <scratch> commit && git commit' is judged — the second commit lands in the root" \
  "$s9_root" "git -C $s9_scratch commit -m x && git commit -m y" "the suite is not fully green"
s9_expect_judged "9a R1 …and 'cd <scratch> && git commit && cd <root> && git commit' is judged too" \
  "$s9_root" "cd $s9_scratch && git commit -m x && cd $s9_root && git commit -m y" "the suite is not fully green"
s9_expect_judged "9a R1 …and a second commit inside an 'sh -c' string counts as a second commit" \
  "$s9_root" "git -C $s9_scratch commit -m x && bash -c 'git -C $s9_root commit -m y'" "the suite is not fully green"
s9_expect_judged "9a R1 …and 'cd <scratch> && git -C <root> commit' places the one commit in the root" \
  "$s9_root" "cd $s9_scratch && git -C $s9_root commit -m x" "the suite is not fully green"
# THE RULE'S STATED COST: two commits both into the scratch repo are judged too. The gate counts
# commit segments; it does not place each one, so it cannot tell this from the shapes above.
s9_expect_judged "9a R1 …and two commits both into the scratch repo are judged (the count, not a placement, decides)" \
  "$s9_root" "git -C $s9_scratch commit -m x && git -C $s9_scratch commit -m y" "the suite is not fully green"
# CONTROL: the count is of COMMIT segments. One commit beside other git calls is still exempted.
s9_expect_outside "9a R1 control: one outside commit beside a non-commit git call is still admitted with the line" \
  "$s9_root" "git -C $s9_scratch add -A && git -C $s9_scratch commit -m x && git -C $s9_scratch log -1" "$s9_scratch"

# ONE COMMIT, PLACED WRONG (critic C1, wave-19). Each command below carries ONE commit, and the
# arm used to place the directory the TEXT names first — the first absolute `-C`, the leading
# `cd`, the payload cwd — while git obeys the LAST `-C`, `--git-dir`/`--work-tree`/`GIT_DIR`
# name the repository outright, and a `pushd`, a nested `bash -c 'cd …'` or a piped `cd` moves
# (or fails to move) the shell where the reader never looks. Every one lands in the ROOT. Only a
# shape the arm can place exactly as git will is exempted; each of these is judged instead.
s9_expect_judged "9a C1 'git -C <scratch> -C <root> commit' is judged — git obeys the last -C" \
  "$s9_root" "git -C $s9_scratch -C $s9_root commit -m x" "the suite is not fully green"
s9_expect_judged "9a C1 …and a relative second -C ('-C <scratch> -C ../../root') is judged" \
  "$s9_root" "git -C $s9_scratch -C ../../root commit -m x" "the suite is not fully green"
s9_expect_judged "9a C1 …and '-C <scratch> --git-dir=<root>/.git --work-tree=<root>' is judged" \
  "$s9_root" "git -C $s9_scratch --git-dir=$s9_root/.git --work-tree=$s9_root commit -m x" "the suite is not fully green"
s9_expect_judged "9a C1 …and 'cd <scratch> && git --git-dir=<root>/.git --work-tree=<root> commit' is judged" \
  "$s9_root" "cd $s9_scratch && git --git-dir=$s9_root/.git --work-tree=$s9_root commit -m x" "the suite is not fully green"
s9_expect_judged "9a C1 …and 'cd <scratch> && GIT_DIR=… GIT_WORK_TREE=… git commit' is judged" \
  "$s9_root" "cd $s9_scratch && GIT_DIR=$s9_root/.git GIT_WORK_TREE=$s9_root git commit -m x" "the suite is not fully green"
s9_expect_judged "9a C1 …and 'cd <scratch> && pushd <root> && git commit' is judged" \
  "$s9_root" "cd $s9_scratch && pushd $s9_root && git commit -m x" "the suite is not fully green"
s9_expect_judged "9a C1 …and 'cd <scratch> && bash -c \"cd <root> && git commit\"' is judged" \
  "$s9_root" "cd $s9_scratch && bash -c 'cd $s9_root && git commit -m x'" "the suite is not fully green"
s9_expect_judged "9a C1 …and 'cd <scratch> && git -C ../../root commit' is judged (a relative -C after the cd)" \
  "$s9_root" "cd $s9_scratch && git -C ../../root commit -m x" "the suite is not fully green"
s9_expect_judged "9a C1 …and 'cd <scratch> | cat; git commit' is judged (a piped cd moves nothing)" \
  "$s9_root" "cd $s9_scratch | cat; git commit -m x" "the suite is not fully green"
s9_expect_judged "9a C1 …and a payload cwd in the scratch repo with 'pushd <root> && git commit' is judged" \
  "$s9_scratch" "pushd $s9_root && git commit -m x" "the suite is not fully green"
s9_expect_judged "9a C1 …and a payload cwd in the scratch repo with 'git -C ../../root commit' is judged" \
  "$s9_scratch" "git -C ../../root commit -m x" "the suite is not fully green"
# CONTROLS: the shapes the arm CAN place stay admitted — the writer brief's own `cd … || exit 1;`
# lead, and a `-C` AFTER the subcommand (commit's reuse-message flag), which is not git's cwd.
s9_expect_outside "9a C1 control: 'cd <scratch> || exit 1; git add -A && git commit' is still admitted" \
  "$s9_root" "cd $s9_scratch || exit 1; git add -A && git commit -m x" "$s9_scratch"
s9_expect_outside "9a C1 control: 'git -C <scratch> commit -C HEAD' is still admitted (the second -C is commit's)" \
  "$s9_root" "git -C $s9_scratch commit -C HEAD" "$s9_scratch"

# AN ALLOW-LIST, NOT A DENY-LIST (review R2-2, wave-19 T6e). The reader used to name the words
# that move the shell — `cd`, `pushd`, `eval`, a shell — and exempt everything else. A `cd` behind
# a reserved word (`if`, `while`, `until`, `!`, `time`) runs in the current shell all the same,
# and its first word was none of those, so each command below was exempted for the scratch repo
# while it committed in the ROOT. Three rounds (R1, C1, R2-2) each patched that list. Now every
# segment after the placing prefix must start with `git`, `true`, `:` or `exit`, and any `(`,
# `)`, `{`, `}` or backtick costs the exemption. Each of these is judged at the run's step.
s9_expect_judged "9a R2-2 payload cwd in the scratch repo with 'if cd <root>; then :; fi; git commit' is judged" \
  "$s9_scratch" "if cd $s9_root; then :; fi; git commit -m x" "the suite is not fully green"
s9_expect_judged "9a R2-2 …and 'time cd <root> && git commit' is judged" \
  "$s9_scratch" "time cd $s9_root && git commit -m x" "the suite is not fully green"
s9_expect_judged "9a R2-2 …and '! cd <root> || git commit' is judged" \
  "$s9_scratch" "! cd $s9_root || git commit -m x" "the suite is not fully green"
s9_expect_judged "9a R2-2 …and 'while ! cd <root>; do :; done; git commit' is judged" \
  "$s9_scratch" "while ! cd $s9_root; do :; done; git commit -m x" "the suite is not fully green"
s9_expect_judged "9a R2-2 …and 'cd <scratch> && if cd <root>; then git commit; fi' is judged" \
  "$s9_root" "cd $s9_scratch && if cd $s9_root; then git commit -m x; fi" "the suite is not fully green"
s9_expect_judged "9a R2-2 …and 'cd <scratch> && time cd <root> && git commit' is judged" \
  "$s9_root" "cd $s9_scratch && time cd $s9_root && git commit -m x" "the suite is not fully green"
# THE LIST IS OF WHAT IS ALLOWED, SO A WORD NOBODY NAMED IS JUDGED TOO. `until` is a reserved
# word the old reader never listed; a function named `git` shadows the binary, so the one
# `git -C <scratch> commit` in the text runs `git -C <root> commit` instead.
s9_expect_judged "9a R2-2 …and 'until cd <root>; do :; done; git commit' is judged (a word no list named)" \
  "$s9_scratch" "until cd $s9_root; do :; done; git commit -m x" "the suite is not fully green"
s9_expect_judged "9a R2-2 …and a function named git shadowing 'git -C <scratch> commit' is judged" \
  "$s9_root" "git() { command git -C $s9_root commit -m x; }; git -C $s9_scratch commit -m y" "the suite is not fully green"
# CONTROL: a redirection is not a segment. '2>&1' carries an '&' and still leaves the one commit
# placed where the payload cwd stands.
s9_expect_outside "9a R2-2 control: 'git add -A && git commit 2>&1' from the scratch repo is still admitted" \
  "$s9_scratch" "git add -A && git commit -m x 2>&1" "$s9_scratch"

# A QUOTE- OR BACKSLASH-SPLIT --git-dir/--work-tree/GIT_* SPELLING STILL NAMES THE REPOSITORY
# (audit V3-1, wave-19 T6f). `_eg_git_only`'s allow-list judges the first word of each segment,
# but the :1494 disqualifier that costs the exemption for `--git-dir`/`--work-tree`/`GIT_DIR`/
# `GIT_WORK_TREE`/`GIT_COMMON_DIR` is a raw substring test over $COMMAND. A quote or backslash
# dropped into the middle of the word defeats the substring match while git (after the shell
# removes the quote/backslash) still receives the flag whole, and the commit lands in the
# root. `--git-d""ir`, `--git-di\r` and `'--git-dir'` are three ways to split it; `GIT_D""IR` is
# ALREADY judged (its first word fails the allow-list outright) and stays as a control.
s9_expect_judged "9a V3-1 'git --git-d\"\"ir=<root>/.git commit' from the scratch repo is judged" \
  "$s9_scratch" "git --git-d\"\"ir=$s9_root/.git commit -m x" "the suite is not fully green"
s9_expect_judged "9a V3-1 'git --git-di\\r=<root>/.git commit' from the scratch repo is judged" \
  "$s9_scratch" "git --git-di\r=$s9_root/.git commit -m x" "the suite is not fully green"
s9_expect_judged "9a V3-1 \"git '--git-dir'=<root>/.git commit\" from the scratch repo is judged" \
  "$s9_scratch" "git '--git-dir'=$s9_root/.git commit -m x" "the suite is not fully green"
s9_expect_judged "9a V3-1 control: 'GIT_D\"\"IR=<root>/.git git commit' from the scratch repo is already judged (non-git first word)" \
  "$s9_scratch" "GIT_D\"\"IR=$s9_root/.git git commit -m x" "the suite is not fully green"
s9_expect_judged "9a V3-1 …and 'git -C <scratch> --git-d\"\"ir=<root>/.git commit' from the root is judged" \
  "$s9_root" "git -C $s9_scratch --git-d\"\"ir=$s9_root/.git commit -m x" "the suite is not fully green"
s9_expect_judged "9a V3-1 …and 'git -C <scratch> --git-di\\r=<root>/.git commit' from the root is judged" \
  "$s9_root" "git -C $s9_scratch --git-di\r=$s9_root/.git commit -m x" "the suite is not fully green"
s9_expect_judged "9a V3-1 …and \"git -C <scratch> '--git-dir'=<root>/.git commit\" from the root is judged" \
  "$s9_root" "git -C $s9_scratch '--git-dir'=$s9_root/.git commit -m x" "the suite is not fully green"
s9_expect_judged "9a V3-1 control: 'GIT_D\"\"IR=<root>/.git git -C <scratch> commit' from the root is already judged" \
  "$s9_root" "GIT_D\"\"IR=$s9_root/.git git -C $s9_scratch commit -m x" "the suite is not fully green"
# THE SAME CLASS, --work-tree (auditor V3-1's read, driven here): a quote-split spelling of
# --work-tree defeats the same raw substring test.
s9_expect_judged "9a V3-1 'git --work-t\"\"ree=<root> --git-dir=<root>/.git commit' from the scratch repo is judged" \
  "$s9_scratch" "git --work-t\"\"ree=$s9_root --git-dir=$s9_root/.git commit -m x" "the suite is not fully green"

# NOT A REPOSITORY AT ALL: git cannot name one, so the gate cannot say it is outside, and it
# keeps today's verdict (the commit would fail on its own; the wall does not guess).
s9_bare_dir="$s9_tmp/not-a-repo"; mkdir -p "$s9_bare_dir"
s9_expect_judged "9a …and a directory git places in no repository is judged as before, never exempted by a failed question" \
  "$s9_root" "git -C $s9_bare_dir commit -m x" "the suite is not fully green"

# --- 9b / AC-9.3: a repository NESTED under the root is outside it ------------------------
s9_nested="$s9_root/.bionic/docs/record/x/bed"
mkdir -p "$s9_nested"
git -C "$s9_nested" init -q .
expect_eq "9b the nested bed really is its own repository (its .git is a directory)" "dir" \
  "$(if [ -d "$s9_nested/.git" ]; then echo dir; else echo other; fi)"
s9_expect_outside "9b AC-9.3 'git -C <root>/.bionic/docs/record/x/bed commit' is admitted with the line" \
  "$s9_root" "git -C $s9_nested commit -q --allow-empty -m x" "$s9_nested"
s9_expect_outside "9b AC-9.3 …and a writer standing in the nested bed (payload cwd) is admitted the same way" \
  "$s9_nested" 'git commit -m "x"' "$s9_nested"

# --- 9d: a LINKED WORKTREE of the engaged repository is INSIDE ------------------------------
#
# It has a toplevel of its own, so a toplevel comparison would call it outside and exempt
# every writer's commit from the run. The comparison is the COMMON DIR, which a linked worktree
# shares with its main checkout — so it is judged, exactly as it was before this arm existed.
git -C "$s9_root" worktree add -q "$s9_root/.worktrees/19-T9" -b wt/19-T9 2>/dev/null
expect_ne "9d the linked worktree's toplevel differs from the root's (a toplevel test would get it wrong)" \
  "$s9_root" "$(git -C "$s9_root/.worktrees/19-T9" rev-parse --show-toplevel)"
s9_expect_judged "9d a commit from a linked worktree of the engaged repository is still judged (-C)" \
  "$s9_root" "git -C $s9_root/.worktrees/19-T9 commit -m x" "the suite is not fully green"
s9_expect_judged "9d …and from a leading cd into it" \
  "$s9_root" "cd $s9_root/.worktrees/19-T9 && git commit -m x" "the suite is not fully green"

# --- 9e: the comparison is PHYSICAL ------------------------------------------------------------
# A symlink to the root is the root: the same repository reached by another spelling.
ln -s "$s9_root" "$s9_tmp/root-link"
s9_expect_judged "9e '-C' through a symlink to the root is the root, and is judged" \
  "$s9_root" "git -C $s9_tmp/root-link commit -m x" "the suite is not fully green"

# --- 9g / AC-3.1: an env spelling of the commit gets the git spelling's verdict (wave-20 T3) --
#
# THE FAULT (triage-D row 3, Step-6 addition; research D3 REQ-3). The argv reader dropped a bare
# `env` only, so `env -C <root>`, `env -i` and `/usr/bin/env` left an option as argv[0] and no
# commit was read at all: `env -C <root> git commit` was ADMITTED in silence where `git -C <root>
# commit` is refused. The reader now skips env and its options and records its directory, and
# the gate places the commit there. Every row below is refused exactly as its 9c control is.
s9_expect_judged "9g AC-3.1 'env -C <root> git commit' is refused as 'git -C <root> commit' is" \
  "$s9_root" "env -C $s9_root git commit -m x" "the suite is not fully green"
s9_expect_judged "9g AC-3.1 …and 'env --chdir=<root> git commit'" \
  "$s9_root" "env --chdir=$s9_root git commit -m x" "the suite is not fully green"
s9_expect_judged "9g AC-3.1 …and 'env -i git commit' from the root" \
  "$s9_root" "env -i git commit -m x" "the suite is not fully green"
s9_expect_judged "9g …and 'env -u FOO git commit' from the root" \
  "$s9_root" "env -u FOO git commit -m x" "the suite is not fully green"
s9_expect_judged "9g …and '/usr/bin/env -C <root> git commit'" \
  "$s9_root" "/usr/bin/env -C $s9_root git commit -m x" "the suite is not fully green"
s9_expect_judged "9g …and 'env -C<root> git commit' (value inline)" \
  "$s9_root" "env -C$s9_root git commit -m x" "the suite is not fully green"
s9_expect_judged "9g …and \"env -S 'git commit -m x'\" (env's own split string)" \
  "$s9_root" "env -S 'git commit -m x'" "the suite is not fully green"
# THE SAME VERDICT, BYTE FOR BYTE. The judged rows above match a substring; this one holds the
# two spellings to one exit and one refusal line.
run_hook_cwd "$s9_home" "$s9_root" "$s9_root" "git -C $s9_root commit -m x"
s9g_git="$HOOK_EXIT|$HOOK_STDERR"
run_hook_cwd "$s9_home" "$s9_root" "$s9_root" "env -C $s9_root git commit -m x"
s9g_env="$HOOK_EXIT|$HOOK_STDERR"
expect_eq "9g AC-3.1 'env -C <root>' and 'git -C <root>' get one exit and one refusal line" "$s9g_git" "$s9g_env"
# THE ROW ATTRIBUTION FOLLOWS THE DIRECTORY: a linked worktree reached by env -C is judged, as
# 9d judges it reached by git -C.
s9_expect_judged "9g …and 'env -C <linked worktree> git commit' is judged as 9d's '-C' is" \
  "$s9_root" "env -C $s9_root/.worktrees/19-T9 git commit -m x" "the suite is not fully green"
# D3-3, FAIL-CLOSED: an env spelling is never exempted as outside the repository. `_eg_git_only`
# refuses a first word of `env`, so `env -C <scratch> git commit` is judged against this run's
# plan where `git -C <scratch> commit` (9a) is admitted. A writer who means the scratch repo
# spells `git -C`.
s9_expect_judged "9g D3-3 'env -C <scratch> git commit' is judged, never exempted (fail-closed)" \
  "$s9_root" "env -C $s9_scratch git commit -q --allow-empty -m x" "the suite is not fully green"
# CONTROLS: env in front of a non-commit is still no commit, and git's own absolute -C after an
# env -C places the commit where git will (the scratch repo is still judged: env is the first word).
run_hook_cwd "$s9_home" "$s9_root" "$s9_root" "env -C $s9_root git status"
expect_eq "9g control: 'env -C <root> git status' is no commit and is admitted" "0" "$HOOK_EXIT"
s9_expect_judged "9g control: 'env -C <scratch> git -C <root> commit' is judged in the root" \
  "$s9_root" "env -C $s9_scratch git -C $s9_root commit -m x" "the suite is not fully green"
# T6f's DE-QUOTE DISQUALIFIER STILL HOLDS behind env: a quote-split --git-dir naming the root.
s9_expect_judged "9g T6f 'env git --git-d\"\"ir=<root>/.git commit' from the scratch repo is judged" \
  "$s9_scratch" "env git --git-d\"\"ir=$s9_root/.git commit -m x" "the suite is not fully green"

# --- 9f / AC-9.2: the plan is never opened on an outside commit (trace) --------------------
#
# THE TRACE CHANNEL IS STDERR ITSELF, POINTED AT A FILE. A prelude (BASH_ENV, sourced before
# the hook's first line) runs `exec 2>&9` and `set -x`, so every command the process runs is
# recorded there. The plan's path appears in it the moment the gate resolves the plan
# (`PLAN=…`, `session_run`, `active_plan`); on an outside commit it must not appear at all.
# THE POSITIVE CONTROL runs first on the SAME root and the SAME trace channel: an inside commit's
# trace DOES carry the path, so a trace that recorded nothing cannot pass the negative.
#
# WHY NOT BASH_XTRACEFD (floor #1, wave-19; the class tests/hook-latency.test.sh already met in
# wave-14 T20). BASH_XTRACEFD arrived in bash 4.1. tests/run.sh pins `/bin/bash` — 3.2 on a Mac —
# first on PATH, so under the runner the `bash` below is 3.2, which accepts the assignment,
# ignores it and writes xtrace to stderr; stderr went to /dev/null and both controls read an
# EMPTY trace. By hand `bash` is Homebrew's 5.3 and the same rows passed. A DEBUG trap under
# `set -T` re-asserts fd 2 before every command, because a `2>/dev/null` inside the hook would
# otherwise hide that stretch of the trace. The hook's own stderr lands in the file too; the
# outside line names the root, never the plan's path, so it cannot satisfy or spoil a row here.
s9_prelude="$s9_tmp/xtrace-prelude.sh"
cat > "$s9_prelude" <<'PRELUDE'
exec 2>&9
set -T
trap 'exec 2>&9' DEBUG
set -x
PRELUDE
s9_trace() {  # <command> -> the trace file's path
  local _in _tr
  _tr=$(mktemp "$s9_tmp/trace.XXXXXX")
  _in=$(jq -n --arg c "$1" --arg cwd "$s9_root" --arg s "$EG_SID" \
          '{session_id: $s, tool_input: {command: $c}, cwd: $cwd}')
  HOME="$s9_home" CLAUDE_PROJECT_DIR="$s9_root" CLAUDE_CODE_SESSION_ID="$EG_SID" \
    BASH_ENV="$s9_prelude" bash "$HOOK" <<< "$_in" >/dev/null 2>/dev/null 9>"$_tr" || true
  printf '%s' "$_tr"
}
s9_tr_in=$(s9_trace 'git commit -m "x"')
expect_contains "9f control: an inside commit's trace records the plan path (the trace channel works)" \
  "$s9_plan" "$(cat "$s9_tr_in")"
s9_tr_out=$(s9_trace "git -C $s9_scratch commit -q --allow-empty -m x")
expect_contains "9f control: the outside commit's trace is not empty (the hook ran under xtrace)" \
  "git -C $s9_scratch commit" "$(cat "$s9_tr_out")"
expect_absent "9f AC-9.2 the outside commit's trace never names the plan path" \
  "$s9_plan" "$(cat "$s9_tr_out")"
expect_absent "9f AC-9.2 …and never enters the plan resolution" \
  "session_run " "$(cat "$s9_tr_out")"

# ============================================================
# Section 32: EVERY commit refusal carries the edit-then-commit note first (T12, AC-9.1/9.2)
# ============================================================
#
# Section 31 pinned the note on the matrix arm only, where it rode LAST in `detail`. The
# note is now computed once for the whole `commit` class and is detail line 1 on every
# arm, so the twelve-line fold cannot cut it. Two arms stand for the rest: the missing-
# fields arm (a plan at current: 9 with no Step 9 `delivered` field; Step 4 is a pointer step, A-T12.1) and the dispatch-ledger arm
# (an active|done row with no evidence line).

section "Section 32: the note is detail line 1 on every commit refusal"

T12_NOTE="Note: this command also writes the plan — run the edit first, then commit in a separate call."
t12_first_detail() {  # first non-empty line after the user line, from the verbose stream
  printf '%s\n' "$HOOK_VSTDERR" | awk '/^bionic: /{f=1; next} f && NF {print; exit}'
}
t12_expect_note_first() {  # <label> <home> <command>
  run_hook "$2" "$3"
  local got; got=$(t12_first_detail)
  if [ "$HOOK_EXIT" -eq 2 ] && [ "$got" = "$T12_NOTE" ]; then
    ok "$1"
  else
    no "$1" "expected exit 2 with detail line 1 == the note; exit=$HOOK_EXIT line1='$got'"
  fi
}
t12_expect_no_note() {  # <label> <home> <command>
  run_hook "$2" "$3"
  if [ "$HOOK_EXIT" -eq 2 ] && ! grep -q "also writes the plan" <<<"$HOOK_VSTDERR"; then
    ok "$1"
  else
    no "$1" "expected a refusal with NO note; exit=$HOOK_EXIT detail='$HOOK_VSTDERR'"
  fi
}

# 32a/32b — missing-fields arm.
h32a=$(make_home)
p32a=$(write_plan "$h32a" "$(plan 9 "  scratch: nothing here" "$matrix_complete")")
t12_expect_note_first "T12-a missing-fields arm, absolute plan path → note is detail line 1" \
  "$h32a" "sed -i 's/x/y/' $p32a && git commit -q -m m"
t12_expect_note_first "T12-b missing-fields arm, root-relative plan path → note is detail line 1" \
  "$h32a" "sed -i 's/x/y/' .bionic/docs/plans/active.md && git commit -q -m m"
t12_expect_no_note "T12-c missing-fields arm, plain commit → refused, no note" \
  "$h32a" "git commit -q -m m"

# 32d/32e — dispatch-ledger arm: a landed row with no `- T1:` line (wave-31 T24: the one arm; the
# task-ledger fixture these drove is the retired shape).
h32d=$(make_home)
p32d=$(write_plan "$h32d" "$(d7_wave_plan "$tasks_one_done" "")")
t12_expect_note_first "T12-d ledger arm, absolute plan path → note is detail line 1" \
  "$h32d" "sed -i 's/x/y/' $p32d && git commit -q -m m"
t12_expect_note_first "T12-e ledger arm, root-relative plan path → note is detail line 1" \
  "$h32d" "sed -i 's/x/y/' .bionic/docs/plans/active.md && git commit -q -m m"
t12_expect_no_note "T12-f ledger arm, plain commit → refused, no note" \
  "$h32d" "git commit -q -m m"
expect_contains "T12-f2 …and the refusal is the ledger arm's, not the numeric one" \
  "1 task has no evidence line" "$HOOK_STDERR"

# 32g — the matrix arm (section 31's case) keeps the note, now first rather than last.
t12_expect_note_first "T12-g matrix arm → the note is detail line 1, not the last line" \
  "$h31a" "$cmd31a"


# ============================================================
section "Section D4: launched is what the roster says — the gate reads the ledger through units_findings (wave-21 T5; REQ-4, AC-4.1, AC-4.3; D4, ADR-037 decision 3)"
# ============================================================
#
# THE DEFECT (report #2a, triage-A §2.2). The wave arm demanded a hand-written `- T<n>:` line
# for EVERY row, so an `active` row the dispatch hook had just put on the roster was refused
# at the writer's first commit for a copy of the launch record nobody had written. Now the
# gate asks `units_findings`: a `landed` row still owes its line, an `active` row whose agent
# cell names a roster row owes nothing, and an empty agent cell is self-owned. The roster is
# THIS session's, `.bionic/tmp/roster-<sid>.state` under the root; with no roster file the
# gate keeps today's line rule for agent-named `active` rows (spec assumption 1).
#
# fails-when: the launched active row is refused for a missing line, the landed row passes
# without one, or the self-owned row is refused for no roster row.
sD4_roster() {  # <home> <name>... — this session's roster, one launch row per name
  local h="$1" n; shift
  mkdir -p "$h/.bionic/tmp"
  roster_header > "$h/.bionic/tmp/roster-$EG_SID.state"
  for n in "$@"; do
    roster_row_fixture status=identified session="$EG_SID" name="$n" agent_id="a-$n" \
      >> "$h/.bionic/tmp/roster-$EG_SID.state"
  done
}
sD4_tasks() {  # <T2 agent cell> <T2 status> -> a ten-column table, T1 landed with its line below
  printf '## Tasks\n\n| id | step | kind | task | agent | deps | size | serves | Files | status |\n'
  printf '|---|---|---|---|---|---|---|---|---|---|\n'
  printf '| T1 | 4 | build | the first unit | w21-T1 | — | 30m | REQ-x | a.sh | landed |\n'
  printf '| T2 | 4 | build | the second unit | %s | — | 30m | REQ-x | b.sh | %s |\n' "$1" "$2"
}

# D4a — THE SPECIMEN: an active row whose agent cell names this session's roster row, and no
# `- T2:` line. The launch record IS the record; the commit goes through.
hD4a=$(make_home)
write_plan "$hD4a" "$(d7_wave_plan "$(sD4_tasks w21-T2 active)" "- T1: bash suite 9/9 green")" > /dev/null
sD4_roster "$hD4a" w21-T1 w21-T2
expect_allow "D4a AC-4.3 an active row its roster names commits with no '- T2:' line" \
  "$hD4a" 'git commit -m "x"'

# D4b — THE SAME ROW AT `landed` OWES ITS LINE, roster or not, in the words 17t pins.
hD4b=$(make_home)
write_plan "$hD4b" "$(d7_wave_plan "$(sD4_tasks w21-T2 landed)" "- T1: bash suite 9/9 green")" > /dev/null
sD4_roster "$hD4b" w21-T1 w21-T2
expect_block "D4b AC-4.3 a landed row with no line is still refused" \
  "$hD4b" 'git commit -m "x"' "1 task has no evidence line"
expect_contains "D4b2 …and the detail names T2" "- T2:" "$HOOK_VSTDERR"

# D4c — SELF-OWNED: an empty agent cell (em dash, then a blank cell) and NO roster file at all.
hD4c=$(make_home)
write_plan "$hD4c" "$(d7_wave_plan "$(sD4_tasks — active)" "- T1: bash suite 9/9 green")" > /dev/null
expect_allow "D4c AC-4.3 an active row with an em-dash agent cell and no roster commits with no line" \
  "$hD4c" 'git commit -m "x"'
hD4c2=$(make_home)
write_plan "$hD4c2" "$(d7_wave_plan "$(sD4_tasks '' active)" "- T1: bash suite 9/9 green")" > /dev/null
expect_allow "D4c2 …and so does a blank agent cell" "$hD4c2" 'git commit -m "x"'

# D4d — THE LAUNCH FINDING: a roster that names nobody in T2's agent cell. Refused, and the
# refusal says what is wrong — the agent is not on the roster — not that a line is missing.
hD4d=$(make_home)
write_plan "$hD4d" "$(d7_wave_plan "$(sD4_tasks bionic:implementor active)" "- T1: bash suite 9/9 green")" > /dev/null
sD4_roster "$hD4d" w21-T1 w21-T9
expect_block "D4d AC-4.1 an active row whose agent names no roster row is refused" \
  "$hD4d" 'git commit -m "x"' "names no row on this session's roster"
expect_eq "D4d2 …its verdict line names the launch, not a missing line" \
  "bionic: commit refused — 1 active task names no launched agent (write the roster name as agent)" \
  "$(printf '%s\n' "$HOOK_STDERR" | /usr/bin/grep '^bionic: ')"
expect_contains "D4d3 …and the detail names the row and the cell" "- T2: bionic:implementor" "$HOOK_VSTDERR"

# D4e — NO ROSTER FILE, AN AGENT-NAMED ACTIVE ROW: today's line rule, unchanged.
hD4e=$(make_home)
write_plan "$hD4e" "$(d7_wave_plan "$(sD4_tasks w21-T2 active)" "- T1: bash suite 9/9 green")" > /dev/null
expect_block "D4e assumption 1 with no roster file, an agent-named active row still owes its line" \
  "$hD4e" 'git commit -m "x"' "1 task has no evidence line"

# D4f — A PENDING ROW OWES NOTHING: no line until it lands (the one-edit trap, ADR-037).
hD4f=$(make_home)
write_plan "$hD4f" "$(d7_wave_plan "$(sD4_tasks w21-T2 pending)" "- T1: bash suite 9/9 green")" > /dev/null
expect_allow "D4f a pending row with no line commits" "$hD4f" 'git commit -m "x"'

# D4g — TASK SCALE, THE ONE TABLE (wave-31 T24; REQ-1, D2). The same ten-column table under
# `scale: task` is judged by the same arm in the same words: a self-owned `active` row with no
# line commits, and a `landed` one owes its line, refused byte for byte as D4b is at wave scale.
sD4_at_task() { printf '%s\n' "$1" | sed 's/^scale: wave$/scale: task/'; }
expect_eq "D4g0 the task-scale twin carries scale: task" "1" \
  "$(sD4_at_task "$(d7_wave_plan "$(sD4_tasks '' active)" "")" | /usr/bin/grep -c '^scale: task$')"
hD4g=$(make_home)
write_plan "$hD4g" "$(sD4_at_task "$(d7_wave_plan "$(sD4_tasks '' active)" "- T1: bash suite 9/9 green")")" > /dev/null
expect_allow "D4g AC-4.3 task scale, a self-owned active row with no line and no roster commits" \
  "$hD4g" 'git commit -m "x"'
hD4g2=$(make_home)
write_plan "$hD4g2" "$(sD4_at_task "$(d7_wave_plan "$(sD4_tasks w21-T2 landed)" "- T1: bash suite 9/9 green")")" > /dev/null
sD4_roster "$hD4g2" w21-T1 w21-T2
expect_block "D4g2 REQ-1 …and a landed row at task scale owes its line, refused as at wave scale" \
  "$hD4g2" 'git commit -m "x"' "1 task has no evidence line"
expect_eq "D4g3 …verdict line byte for byte the wave scale's (D4b)" \
  "bionic: commit refused — 1 task has no evidence line (add one '- T<id>:' per row)" \
  "$(printf '%s\n' "$HOOK_STDERR" | /usr/bin/grep '^bionic: ')"

# D4h — THE ONE ENUM AT TASK SCALE (19f, 22c1, 22c-t2 pinned the retired table's enum texts,
# which went with it): a status no enum defines is the reader's `units_validate` finding, in its
# words, at either scale.
hD4h=$(make_home)
write_plan "$hD4h" "$(sD4_at_task "$(d7_wave_plan "$(sD4_tasks w21-T2 wip)" "- T1: bash suite 9/9 green")")" > /dev/null
expect_block "D4h REQ-1 task scale, a 'wip' row is refused, naming the one enum" "$hD4h" 'git commit -m "x"' \
  "T2: status wip is not one of pending active landed dropped"
expect_eq "D4h2 …verdict line byte for byte" \
  "bionic: commit refused — that dispatched task's row is invalid (fix the row the detail names)" \
  "$(printf '%s\n' "$HOOK_STDERR" | /usr/bin/grep '^bionic: ')"
# D4h3 — the retired six-column table under a numeric `current:` is a broken table, refused
# naming the columns it lacks, never judged by a second enum.
hD4h3=$(make_home)
write_plan "$hD4h3" "$(sD4_at_task "$(d7_wave_plan "## Tasks

| id | intent | rigor | description | status | worktree |
|---|---|---|---|---|---|
| T1 | build | double | the finished work | done | — |" "- T1: bash suite 9/9 green")")" > /dev/null
expect_block "D4h3 REQ-1 the retired six-column table at task scale is refused, naming a missing column" \
  "$hD4h3" 'git commit -m "x"' "## Tasks: missing column step"

# ============================================================
section "§HEAD: Step-5 evidence names the head its run read (wave-26 T4; REQ-3 AC-3.2; D5)"
# ============================================================
#
# A PASS THAT DOES NOT SAY WHICH CODE IT READ CANNOT BE COMPARED WITH ANYTHING. Beside
# cmd/pass/total/output the block now carries `head:`, and the gate refuses it absent, when
# it is not a commit in the repository the commit is made in, and when the release head does
# not contain it (`git merge-base --is-ancestor`). The release head is the tip of the plan's
# `working-branch:` when the plan names one that resolves, and the HEAD of the directory the
# commit is made in otherwise. Every refusal is one line naming its fix. The positive control
# for each arm is the same fixture with the one fact corrected.
eg_commit() {  # <dir> <message> — one empty commit, fixed identity, no hooks
  git -C "$1" -c user.name=fixture -c user.email=fixture@example.invalid \
    -c commit.gpgsign=false -c core.hooksPath=/dev/null commit -q --allow-empty -m "$2" 2>/dev/null
}
step5_head() {  # <head line, or empty for none> [extra flush-left SDLC State line]
  printf '  cmd: bash tests/run.sh\n  pass: 72\n  total: 72\n'
  [ -n "$1" ] && printf '  head: %s\n' "$1"
  printf '  output: .bionic/docs/plans/wave-01.plan.md#step-5\n  auditor: 3 rows CONFIRMED — report .bionic/tmp/audit.md'
  [ -n "${2:-}" ] && printf '\n%s' "$2"
  return 0
}
expect_true "HEAD0 precondition: the fixture head is a 40-hex commit id" \
  /usr/bin/grep -qE '^[0-9a-f]{40}$' <<<"$EG_HEAD"

# --- absent ---
hHa=$(make_home); eg_head_repo "$hHa"
write_plan "$hHa" "$(plan 5 "$(step5_head '')" "$matrix_complete")" > /dev/null
expect_block "HEADa a green Step-5 block with no head: → block" \
  "$hHa" 'git commit -m "x"' "names no head"
expect_eq "HEADa2 …in one line that names the fix" \
  "bionic: commit refused — this step's evidence names no head (add head: <sha the run read>)" \
  "$(printf '%s\n' "$HOOK_STDERR" | /usr/bin/grep '^bionic: ')"
write_plan "$hHa" "$(plan 5 "$(step5_head "$EG_HEAD")" "$matrix_complete")" > /dev/null
expect_allow "HEADa3 …and the same block naming the repository's HEAD → allow" \
  "$hHa" 'git commit -m "x"'

# --- not a commit ---
hHb=$(make_home); eg_head_repo "$hHb"
write_plan "$hHb" "$(plan 5 "$(step5_head 0123456789abcdef0123456789abcdef01234567)" "$matrix_complete")" > /dev/null
expect_block "HEADb a head: that is no commit in the repository → block" \
  "$hHb" 'git commit -m "x"' "is not a commit"
expect_eq "HEADb2 …in one line that names the fix" \
  "bionic: commit refused — the Step-5 head: is not a commit here (record the sha the run read)" \
  "$(printf '%s\n' "$HOOK_STDERR" | /usr/bin/grep '^bionic: ')"
expect_contains "HEADb3 …and the detail names the value read" \
  "0123456789abcdef0123456789abcdef01234567" "$HOOK_VSTDERR"
write_plan "$hHb" "$(plan 5 "$(step5_head HEAD)" "$matrix_complete")" > /dev/null
expect_block "HEADb4 a symbolic head: (HEAD) is not a recorded head → block" \
  "$hHb" 'git commit -m "x"' "is not a commit"
write_plan "$hHb" "$(plan 5 "$(step5_head "${EG_HEAD:0:12}")" "$matrix_complete")" > /dev/null
expect_allow "HEADb5 …while an abbreviated sha of a real commit → allow" \
  "$hHb" 'git commit -m "x"'

# --- not contained: the commit being made does not hold it ---
hHc=$(make_home); eg_head_repo "$hHc"
git -C "$hHc" checkout -q -b side 2>/dev/null; eg_commit "$hHc" "side work"
HC_SIDE="$(git -C "$hHc" rev-parse HEAD)"
git -C "$hHc" checkout -q - 2>/dev/null
expect_eq "HEADc0 precondition: the side commit exists and HEAD is back on the fixture head" \
  "$EG_HEAD" "$(git -C "$hHc" rev-parse HEAD)"
write_plan "$hHc" "$(plan 5 "$(step5_head "$HC_SIDE")" "$matrix_complete")" > /dev/null
expect_block "HEADc a head: on another line of history than the commit → block" \
  "$hHc" 'git commit -m "x"' "does not contain head:"
expect_eq "HEADc2 …in one line that names the fix" \
  "bionic: commit refused — the release head does not contain head: (run the regression on that head)" \
  "$(printf '%s\n' "$HOOK_STDERR" | /usr/bin/grep '^bionic: ')"
# An older head the commit DOES contain is a contained head: staleness is proof_state's
# question (T5), not this one's.
eg_commit "$hHc" "ahead of the proof"
expect_true "HEADc3 precondition: HEAD moved past the fixture head" \
  test "$(git -C "$hHc" rev-parse HEAD)" != "$EG_HEAD"
write_plan "$hHc" "$(plan 5 "$(step5_head "$EG_HEAD")" "$matrix_complete")" > /dev/null
expect_allow "HEADc4 …while an ancestor of the commit's HEAD → allow" \
  "$hHc" 'git commit -m "x"'

# --- the plan's working-branch is the release head ---
# The commit is driven from the main checkout (on its own branch), and the run's floor ran
# on the wave branch: the head is the wave branch's, which HEAD does not contain. With the
# plan naming `working-branch:` the release head is that branch's tip, and it holds the head.
hHd=$(make_home); eg_head_repo "$hHd"
git -C "$hHd" branch wave/99-fx 2>/dev/null
git -C "$hHd" checkout -q wave/99-fx 2>/dev/null; eg_commit "$hHd" "wave work"
HD_WAVE="$(git -C "$hHd" rev-parse HEAD)"
git -C "$hHd" checkout -q - 2>/dev/null
write_plan "$hHd" "$(plan 5 "$(step5_head "$HD_WAVE" 'working-branch: wave/99-fx')" "$matrix_complete")" > /dev/null
expect_allow "HEADd the wave head, the plan naming working-branch: wave/99-fx → allow" \
  "$hHd" 'git commit -m "x"'
write_plan "$hHd" "$(plan 5 "$(step5_head "$HD_WAVE")" "$matrix_complete")" > /dev/null
expect_block "HEADd2 …and the same head with no working-branch: is judged against HEAD → block" \
  "$hHd" 'git commit -m "x"' "does not contain head:"
git -C "$hHd" checkout -q -b other 2>/dev/null; eg_commit "$hHd" "elsewhere"
HD_OTHER="$(git -C "$hHd" rev-parse HEAD)"
git -C "$hHd" checkout -q - 2>/dev/null
write_plan "$hHd" "$(plan 5 "$(step5_head "$HD_OTHER" 'working-branch: wave/99-fx')" "$matrix_complete")" > /dev/null
expect_block "HEADd3 …and a head the working branch does not hold → block" \
  "$hHd" 'git commit -m "x"' "does not contain head:"

# ============================================================
section "§RIGOR — the evidence gate judges single and double, and refuses a plan or a cell carrying any other word, naming the two (wave-28 T44; wave-30 T11: REQ-1 AC-1.4, D1)"
# ============================================================
# Each fixture below is one this suite already pins, written in the two levels. Its twin is the
# same plan with its frontmatter `rigor:` written in a word before 1.14.0 (single → low, double →
# high): the gate refuses the twin on its rigor, whatever the plan's own verdict, because a plan
# whose rigor names no level cannot run under a guessed one. The fixtures themselves are not
# changed; a twin is derived from them here.
eg_rv_twin() {  # <plan text> -> the same plan with its rigor written in a word before 1.14.0
  sed -E 's/^rigor: single$/rigor: low/; s/^rigor: double$/rigor: high/'
}
eg_rv_verdict() {  # <plan text> -> `exit=<n> <the user line>`, the home's path made neutral
  local h; h=$(make_home)
  write_plan "$h" "$1" > /dev/null
  run_hook "$h" 'git commit -m "x"'
  printf 'exit=%s %s' "$HOOK_EXIT" "$(printf '%s\n' "$HOOK_STDERR" | head -1 | sed "s#$h#HOME#g")"
}
EG_RV_REFUSED="exit=2 bionic: commit refused — this plan's rigor is not single or double (use single or double)"
eg_rv_pair() {  # <label> <want exit> <plan text>
  local tw old new
  tw="$(printf '%s\n' "$3" | eg_rv_twin)"
  expect_ne "§RIGOR $1: the twin carries a word before 1.14.0" "$3" "$tw"
  new="$(eg_rv_verdict "$3")"; old="$(eg_rv_verdict "$tw")"
  expect_eq "§RIGOR $1: the plan exits $2" "exit=$2" "${new%% *}"
  expect_eq "§RIGOR $1: the twin is refused on its rigor, naming the two" "$EG_RV_REFUSED" "$old"
}
# THE TASK-SCALE PAIRS ARE THE ONE TABLE (wave-31 T24; D2): the plans 22b/22c/22d pinned were the
# retired task table under `current: T<n>`; these are the same verdicts' fixtures in the one
# table at `current: 4`, so the twin is refused on its rigor ahead of a verdict the plan earns.
eg_rv_pair "task, single, one table" 0 "$(eg_pf_plan 4 task single false "" "$(eg_pf_row T1 — active)")"
eg_rv_pair "task, double multi_agent, a 'wip' row" 2 "$(eg_pf_plan 4 task double true "" "$(eg_pf_row T1 — wip)")"
eg_rv_pair "task, double multi_agent, a landed row with its line" 0 "$(eg_pf_plan 4 task double true "- T1: bash suite 12/12 green" "$(eg_pf_row T1 — landed)")"
eg_rv_pair "22c5 double multi_agent wave, no ## Tasks" 2 "$(d7_wave_plan "" "")"
eg_rv_pair "22c9 single multi_agent wave, no ## Tasks" 0 "$(d7_wave_plan "" "" single true)"
eg_rv_pair "32a single wave at 6, auditor cells empty" 0 "$(plan_rigor single 6 "$step6_body" "$m32_empty_aud")"
eg_rv_pair "32e single wave at 5, no auditor pointer" 0 "$(plan_rigor single 5 "$step5_noaud" "$m32_empty_aud")"
eg_rv_pair "32 double wave at 5, no auditor pointer" 2 "$(plan_rigor double 5 "$step5_noaud" "$m32_empty_aud")"

# THE ROW'S RIGOR CELL IS GONE (wave-31 T24; REQ-1, D2). The rows that stood here compared a
# frontmatter level with a task row's own `rigor` cell, and refused a cell in a word before
# 1.14.0; the cell was a column of the retired task table, and the one table carries `kind` in
# that slot. The frontmatter word is still judged by every pair above.

section "§READS-HEAD — the evidence gate refuses a commit while the regression row's reads drop head (wave-30 T13; REQ-4 AC-4.3; D7, Δ6a)"
# ============================================================
# The gate's ledger check is units_validate's (22e2, R2): a verify row whose reads cell drops head
# breaks a Task invariant, so every commit on that plan is refused naming the row and the token.
# The control is the same plan with the row reading its default written out.
eg_rh_tasks() {  # <T2's reads cell> -> a reads-column ## Tasks table: T1 landed build, T2 the regression row
  printf '%s\n' "## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | reads | status |
|---|---|---|---|---|---|---|---|---|---|---|
| T1 | 4 | build | the dispatched unit | implementor | — | 30m | REQ-x | a.sh |  | landed |
| T2 | 5 | verify | the one regression | test-runner | — | 30m | REQ-x | .bionic/docs/record/w/regression.md | $1 | pending |"
}
h_rh=$(make_home)
write_plan "$h_rh" "$(d7_wave_plan "$(eg_rh_tasks ".bionic/docs/record/w/build-log.md")" "- T1: bash suite 9/9 green")" > /dev/null
expect_block "§READS-HEAD rh1 a regression row reading a record path instead of head → block, naming the row and the token" \
  "$h_rh" 'git commit -m "x"' "T2: reads .bionic/docs/record/w/build-log.md drops head; a verify row must read head"
expect_contains "§READS-HEAD rh1b …under the ledger's verdict line" \
  "bionic: commit refused — that dispatched task's row is invalid" "$HOOK_STDERR"
h_rh2=$(make_home)
write_plan "$h_rh2" "$(d7_wave_plan "$(eg_rh_tasks "approval:plan, head")" "- T1: bash suite 9/9 green")" > /dev/null
expect_allow "§READS-HEAD rh2 the same plan with T2 reading approval:plan, head → allow" "$h_rh2" 'git commit -m "x"'

finish
