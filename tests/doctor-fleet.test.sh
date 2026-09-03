#!/bin/bash
# tests/doctor-fleet.test.sh — doctor's RESOURCES section and the three run-scoped
# rows (bionic 1.4.0, wave-bionic-1.4.0-update slice DOCTOR handoff 5.3 and 1.4;
# spec AC-27, AC-4's doctor line, AC-8, AC-11).
#
# WHAT IS UNDER TEST, and why these four facts belong on one page.
#
#   RESOURCES (AC-27). The live probe — what this machine is right now — and,
#   per live session holding a preflight attestation in this project, the budget
#   that session is dispatching under. A version-1 attestation is the honest
#   record of a machine nobody measured (preflight-probe loads its resources
#   library fail-open, L-RESOURCES/3) and prints as "no budget recorded", never
#   as a budget of zeroes.
#
#   THE ACTIVE RUN (AC-8). `active_run` is the predicate every always-on hook
#   gates its own work behind. Doctor prints what that predicate sees — the plan,
#   its step, and how long since it was touched — so a person can tell a machine
#   whose walls are armed from one whose walls are inert.
#
#   PREDECESSOR ROSTERS (AC-4's doctor line). A `/clear` re-keys the session and
#   leaves the previous session's roster on disk with rows nobody will ever close.
#   Doctor lists them; the counting is doctor's own, through lib/patrol.sh's
#   `patrol_roster_state`, and never through the tick's adopt verb.
#
#   LEGACY .bionic SYMLINKS (AC-11). spawn-worktree.sh used to plant
#   `<wt>/.bionic -> <main>/.bionic`; lib/root.sh now steps over such a link and
#   never roots on it, so one left on disk is a silent second path to the same
#   state. Doctor lists them.
#
# HERMETIC, AND THE FIXTURE IS A WHOLE PROJECT. Doctor is run with its cwd inside
# a fixture project holding its own `.bionic/`, so `project_root` answers the
# fixture and nothing reads this checkout's real state. The "live" sessions are
# session files naming THIS test's own pid, which is alive by construction.
#
# Usage: bash tests/doctor-fleet.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"

REPO="${BIONIC_SCRIPTS_DIR}"
PAYLOAD="${REPO}/payload"
DOCTOR_SH="${PAYLOAD}/scripts/doctor.sh"

command -v jq >/dev/null 2>&1 || { echo "doctor-fleet.test.sh: jq is required"; exit 1; }

PASS=0; FAIL=0; TOTAL=0
ok() { TOTAL=$((TOTAL + 1)); PASS=$((PASS + 1)); echo "PASS: $1"; }
no() { TOTAL=$((TOTAL + 1)); FAIL=$((FAIL + 1)); echo "FAIL: $1"; [ -n "${2:-}" ] && echo "      $2"; return 0; }
expect_true()  { local label="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$label"; else no "$label"; fi; }
expect_match() {
  local label="$1" pattern="$2" actual="$3"
  # shellcheck disable=SC2053  # RHS is a glob on purpose
  if [[ "$actual" == $pattern ]]; then ok "$label"; else no "$label" "no match for '$pattern' in: $(printf '%.900s' "$actual")"; fi
}
expect_no_match() {
  local label="$1" pattern="$2" actual="$3"
  # shellcheck disable=SC2053  # RHS is a glob on purpose
  if [[ "$actual" == $pattern ]]; then no "$label" "unexpected match for '$pattern'"; else ok "$label"; fi
}

TMP="$(mktemp -d /tmp/bionic-doctor-fleet.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

CHOME="${TMP}/claude-home"
mkdir -p "${CHOME}/plugins" "${CHOME}/sessions"
PROJ="${TMP}/proj"
mkdir -p "${PROJ}/.bionic/tmp" "${PROJ}/.bionic/docs/plans/w"
FIXTURE_RC="${TMP}/dot.zshrc"
: > "$FIXTURE_RC"

# THE SESSIONS ARE LIVE BECAUSE THEIR PID IS THIS PROCESS. `patrol_live_sessions`
# drops any session file whose pid does not answer `kill -0`, so a fabricated pid
# would make every case below vacuous.
LIVE_PID=$$
SID_V2="aaaaaaaa-1111-2222-3333-444444444444"
SID_V1="bbbbbbbb-5555-6666-7777-888888888888"
GONE_SID="cccccccc-9999-0000-1111-222222222222"

write_session() {  # <file-stem> <session-id> <pid>
  jq -nc --arg sid "$2" --arg cwd "$PROJ" --argjson pid "$3" \
    '{pid:$pid, sessionId:$sid, cwd:$cwd, startedAt:1788000000000, status:"busy"}' \
    > "${CHOME}/sessions/$1.json"
}

BUDGET="writers=22 suites=18 worktrees=32 test_jobs=18 source=probe"
write_attestation_v2() {  # <session-id>
  {
    printf '# bionic environment attestation — machine-local, safe to delete\n'
    printf 'version=2\nkind=preflight-attestation\n'
    printf 'session_id=%s\n' "$1"
    printf 'written_at=1788000000\nrepo=%s\n' "$PROJ"
    printf 'cores=18\nmem_gb=128\ndisk_free_gb=1663\nload_1m=2.28\nos=darwin\n'
    printf 'budget=%s\n' "$BUDGET"
  } > "${PROJ}/.bionic/tmp/preflight-$1.state"
}
write_attestation_v1() {  # <session-id>
  {
    printf '# bionic environment attestation — machine-local, safe to delete\n'
    printf 'version=1\nkind=preflight-attestation\n'
    printf 'session_id=%s\n' "$1"
    printf 'written_at=1788000000\nrepo=%s\n' "$PROJ"
  } > "${PROJ}/.bionic/tmp/preflight-$1.state"
}

# ─── The bin dir: real tools doctor legitimately needs, and nothing else ─────
#
# WHY PATH IS REPLACED, AND WHY THIS SUITE IS THE ONE THAT NEEDS IT. Doctor's
# THIRD PARTY table asks the machine's package managers what is installed —
# `brew`, `npm ls -g`, `npx`, `pnpm store path`, `uv tool list` — and those
# shell-outs are NOT under `BIONIC_DOCTOR_PROBE_SECONDS`, which bounds the
# plugin-registry probe and patrol, not the dependency roster. Measured on this
# machine with the full PATH: 32 seconds per run, 28 of them inside those five
# probes, times the SEVEN runs below. That is where "doctor-fleet hangs past
# five minutes" came from — not a blocked read but a real-machine roster walk
# that grows with whatever the machine happens to have installed, and grows
# again under load. Nothing in this file asserts a dependency row.
#
# So the fixture describes a machine carrying only base tools. Every package
# manager is off PATH, every dependency probe answers "not on PATH" immediately,
# and the run time stops being a function of this machine's software. The
# pattern and its reasoning are tests/fresh-home.test.sh's, which replaces PATH
# with a shim dir for the same reason.
#
# THE LIST IS THE COMPLETE SET OF PROGRAMS DOCTOR CAN REACH. `sleep` earns its
# place because `detect_bounded` degrades to an unbounded wait without it;
# `sysctl`, `vm_stat`, `df` and `id` because `resources_probe` is what Section 1
# asserts; `ps` because `patrol_live_sessions` asks whether a pid answers; `git`
# because the version row resolves a feed with it.
#
# `claude` IS ON THE LIST, and it is the one entry that is not free — the CLI's
# plugin listing leaves the process. It stays because dropping it changes the
# machine under test rather than the machine's speed: with the CLI absent, four
# rows turn into "the claude CLI is not on PATH", and one of the FIX lines that
# renders from that cause measures 105 columns, breaking case 20. That is a real
# width defect in `FIX_LINES_OTHER` — the one printer on the page with no column
# bound, already surfaced as DOCTOR/13 — and it belongs to whoever closes
# DOCTOR/13, not to this fixture. A bionic machine has the CLI by construction;
# manufacturing one that does not, in a suite about resources and rosters, would
# be testing somebody else's row. The listing is bounded by
# `BIONIC_DOCTOR_PROBE_SECONDS`, which is why it costs a second and not a hang.
BIN="$TMP/bin"
mkdir -p "$BIN"
for _real in bash sh env cat grep sed awk mkdir rm cp mv chmod stat readlink ls tr head tail \
             sort uniq wc cut jq mktemp find xargs shasum uname date touch diff cmp printf \
             true false sleep dirname basename realpath id ps df sysctl vm_stat nproc git \
             claude; do
  _p="$(command -v "$_real" 2>/dev/null)" && ln -sf "$_p" "${BIN}/${_real}" 2>/dev/null
done

run_doctor() {
  ( cd "$PROJ" && HOME="$TMP" PATH="$BIN" BIONIC_SHELL_RC="$FIXTURE_RC" \
      BIONIC_CLAUDE_HOME="$CHOME" BIONIC_PLUGIN_ROOT="$PAYLOAD" \
      BIONIC_DOCTOR_PROBE_SECONDS=3 \
      bash "$DOCTOR_SH" < /dev/null 2>&1 )
}

section() {  # <output> <SECTION NAME> -> the lines under that heading
  printf '%s\n' "$1" | awk -v h="$2" '
    $0 == h { on = 1; next }
    on && /^[A-Z][A-Z ]*$/ { on = 0 }
    on { print }'
}

echo "=== Section 1: the live probe ==="

OUT1="$(run_doctor)"
RES1="$(section "$OUT1" "RESOURCES")"

expect_match "1: the section exists" "*machine*" "$RES1"
expect_match "2: it names cores, memory, free disk, load and os" \
  "*core*GB*free*load*" "$RES1"

echo ""
echo "=== Section 2: a version-2 attestation prints its recorded budget and source ==="

write_session "1001" "$SID_V2" "$LIVE_PID"
write_attestation_v2 "$SID_V2"

OUT2="$(run_doctor)"
RES2="$(section "$OUT2" "RESOURCES")"

expect_match "3: the session is named by its short id" "*${SID_V2%%-*}*" "$RES2"
expect_match "4: the budget is the recorded string, not a re-derivation" \
  "*writers=22 suites=18 worktrees=32 test_jobs=18*" "$RES2"
expect_match "5: and the source it was recorded with" "*source=probe*" "$RES2"

echo ""
echo "=== Section 3: a version-1 attestation records no budget, and says so ==="

write_session "1002" "$SID_V1" "$LIVE_PID"
write_attestation_v1 "$SID_V1"

OUT3="$(run_doctor)"
RES3="$(section "$OUT3" "RESOURCES")"

expect_match "6: the v1 session is named" "*${SID_V1%%-*}*" "$RES3"
expect_match "7: with the honest line, never a budget of zeroes" \
  "*${SID_V1%%-*}*no budget recorded*" "$RES3"
expect_no_match "8: and no fabricated writers count rides it" \
  "*${SID_V1%%-*}*writers=*" "$RES3"

echo ""
echo "=== Section 4: the active-run row ==="

# A plan the `active_run` predicate calls OPEN: a `## SDLC State` heading and a
# flush-left `current:` below 9.
cat > "${PROJ}/.bionic/docs/plans/w/wave.plan.md" <<'PLAN'
# a fixture plan

## SDLC State

integration-branch: main
current: 4
PLAN

OUT4="$(run_doctor)"

expect_match "9: the row names the plan the predicate resolved" "*active run*wave.plan.md*" "$OUT4"
expect_match "10: and the step it is on" "*active run*current: 4*" "$OUT4"

# Closed: step 9 with a delivered line. `active_run` refuses, and the row has to
# follow it rather than keep reporting a run nobody is in.
cat > "${PROJ}/.bionic/docs/plans/w/wave.plan.md" <<'PLAN'
# a fixture plan

## SDLC State

current: 9

- Step 9: delivered: 2026-09-02
PLAN

OUT5="$(run_doctor)"
expect_match "11: a closed run reads as no active run" "*active run*none*" "$OUT5"
expect_no_match "12: and does not quote a step" "*active run*current: 9*" "$OUT5"

echo ""
echo "=== Section 5: predecessor rosters with open rows ==="

# A roster belonging to a session that is NOT live: two dispatches intended, one
# swept closed by the landing gate, one still open.
{
  printf '# bionic session roster — schema roster-state/v1\n'
  printf 'roster-state/v1|status=intended|session=%s|name=W-ALPHA|agent_id=|launched_at=x\n' "$GONE_SID"
  printf 'roster-state/v1|status=intended|session=%s|name=W-BETA|agent_id=|launched_at=x\n' "$GONE_SID"
  printf 'landing-swept/v1|session=%s|name=W-ALPHA|\n' "$GONE_SID"
} > "${PROJ}/.bionic/tmp/roster-${GONE_SID}.state"

OUT6="$(run_doctor)"

expect_match "13: the predecessor roster is listed by its short id" \
  "*predecessor*${GONE_SID%%-*}*" "$OUT6"
expect_match "14: with the count of rows nobody closed" "*predecessor*1 open*" "$OUT6"
# MATCHED PER LINE. A whole-output glob would happily span from the predecessor
# row down to the RESOURCES section, where a live session's short id legitimately
# appears — and pass or fail for the wrong reason.
PRED_LINES="$(printf '%s\n' "$OUT6" | awk '/predecessor/')"
expect_no_match "15: a LIVE session's roster is not called a predecessor" \
  "*${SID_V2%%-*}*" "$PRED_LINES"

echo ""
echo "=== Section 6: legacy .bionic symlinks under .worktrees/ ==="

mkdir -p "${PROJ}/.worktrees/alpha" "${PROJ}/.worktrees/beta"
ln -s "${PROJ}/.bionic" "${PROJ}/.worktrees/alpha/.bionic"
mkdir -p "${PROJ}/.worktrees/beta/.bionic"   # a real directory is not a legacy link

OUT7="$(run_doctor)"

expect_match "16: the symlinked worktree is listed" "*legacy .bionic symlink*alpha*" "$OUT7"
expect_no_match "17: a real .bionic directory is not" "*legacy .bionic symlink*beta*" "$OUT7"
expect_match "18: and the row carries a repair" "*legacy .bionic symlink*1*" "$OUT7"

echo ""
echo "=== Section 7: registration, and the column budget ==="

expect_true "19: tests/run.sh names doctor-fleet.test.sh" \
  grep -q 'run "doctor-fleet.test.sh" bash tests/doctor-fleet.test.sh' "${REPO}/tests/run.sh"

too_wide() {
  printf '%s\n' "$1" | awk '
    { s = $0
      gsub(/✓|✗|–|—|≥|…|·|→|•/, ".", s)
      if (length(s) > 100) print length(s) ": " $0 }'
}
_over="$(too_wide "$OUT7")"
if [ -z "$_over" ]; then ok "20: every line of the fullest run fits 100 columns"
else no "20: a line exceeds 100 columns" "$_over"; fi

echo ""
echo "========================================"
echo "doctor-fleet: $PASS/$TOTAL passed"
echo "========================================"

[ "$FAIL" -eq 0 ] || exit 1
