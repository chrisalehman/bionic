#!/bin/bash
# Tests for hooks/stop-orders.sh — the human's stop order, and the batch stand-down
# (epic-16 wave-02 slice S3; R3, R8; AC-2's user-ordered half and AC-11).
#
# HERMETIC. Every run happens inside a mktemp'd repo with its own roster, its own sweeper
# ledger and its own session key; nothing here stops an agent, reads the live installed
# hooks, or writes outside the sandbox.
#
# FIXTURE FIDELITY (declared per checklist §A / spec §Design).
#   * roster rows — FAITHFUL to hooks/dispatch-preflight.sh's `ROW=` line, field for field,
#     including `teammate_id=` in the `name@session-xxxxxxxx` form the launch response
#     hands back (.bionic/docs/record/landing-wave-capture-probe.md §3-D).
#   * the ack ledger is never hand-written: this suite runs the real
#     hooks/session-sweeper.sh `ack` verb, so the reader under test reads a shape the
#     shipped writer actually produces.
#   * SYNTHESIZED and declared: session ids, agent ids, artifact contents.
#
# Usage: bash tests/stop-orders.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"

HERE="${BIONIC_HOOKS_DIR}"
ORDERS="$HERE/stop-orders.sh"
SWEEPER="$HERE/session-sweeper.sh"
PASS=0
FAIL=0
TOTAL=0

SANDBOX="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/stop-orders-test.XXXXXX")" && pwd)"
trap 'rm -rf "$SANDBOX"' EXIT

ok() { TOTAL=$((TOTAL + 1)); PASS=$((PASS + 1)); echo "PASS: $1"; }
no() { TOTAL=$((TOTAL + 1)); FAIL=$((FAIL + 1)); echo "FAIL: $1"; [ -n "${2:-}" ] && echo "      $2"; }

expect_status()   { if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "expected exit $2, got $3"; fi; }
expect_contains() { if grep -qF -- "$2" <<<"$3"; then ok "$1"; else no "$1" "missing: $2"; fi; }
expect_absent()   { if grep -qF -- "$2" <<<"$3"; then no "$1" "unexpectedly present: $2"; else ok "$1"; fi; }

SID="6c85684c-9588-45a0-bd26-e8c46956c94f"

make_repo() {  # <name> -> repo path
  local repo="$SANDBOX/$1"
  mkdir -p "$repo/.bionic/tmp" "$repo/.bionic/docs/record"
  git -C "$repo" init -q 2>/dev/null
  git -C "$repo" config user.email t@example.com
  git -C "$repo" config user.name "T"
  printf '%s\n' "$repo"
}

roster_row() {  # <repo> <name> <deliverable> [waiver] [teammate-id] [claims]
  local repo="$1" name="$2" deliv="$3" waiver="${4:-}" tmid="${5:-}" claims="${6:-}"
  local f="$repo/.bionic/tmp/roster-$SID.state"
  [ -f "$f" ] || printf '# bionic session roster — schema roster-state/v1 — machine-local, safe to delete\n' > "$f"
  printf 'roster-state/v1|status=confirmed|session=%s|name=%s|agent_id=|launched_at=2026-08-05T00:00:00Z|subagent_type=implementor|model=opus|deliverable=%s|duration=|progress=|claims=%s|absent=|waiver=%s|teammate_id=%s|tool_use_id=toolu_01FIXTURE\n' \
    "$SID" "$name" "$deliv" "$claims" "$waiver" "$tmid" >> "$f"
  return 0
}

OUT=""; ERR=""; ST=0
run_orders() {  # <repo> <args…>
  local repo="$1"; shift
  OUT=$( cd "$repo" && CLAUDE_CODE_SESSION_ID="$SID" bash "$ORDERS" "$@" 2>"$SANDBOX/.err" ); ST=$?
  ERR=$(cat "$SANDBOX/.err")
  return 0
}

# ============================================================
echo ""
echo "=== Section 1: usage, session key, hostile paths ==="
# ============================================================

R1="$(make_repo usage)"

run_orders "$R1"
expect_status "no verb: usage error" 2 "$ST"
run_orders "$R1" nonsense
expect_status "unknown verb: usage error" 2 "$ST"
run_orders "$R1" order
expect_status "order with no target: usage error" 2 "$ST"
run_orders "$R1" order --at 12345
expect_status "the target comes first" 2 "$ST"
run_orders "$R1" order agent --at notanumber
expect_status "--at takes epoch seconds" 2 "$ST"
run_orders "$R1" standdown extra
expect_status "standdown takes no arguments" 2 "$ST"

ST=0
OUT=$( cd "$R1" && env -u CLAUDE_CODE_SESSION_ID bash "$ORDERS" order someone 2>&1 ); ST=$?
expect_status "no session key: exit 3, nothing read or written" 3 "$ST"

# A repo controls its own .bionic/, so a symlink on the write path is refused rather
# than followed — the same posture hooks/session-sweeper.sh takes.
R2="$(make_repo hostile)"
ln -s /tmp/elsewhere.state "$R2/.bionic/tmp/stop-orders-$SID.state"
run_orders "$R2" order someone
expect_status "a symlinked orders file is REFUSED" 2 "$ST"

# ============================================================
echo ""
echo "=== Section 2: the order verb records, reports, and never refuses (R3) ==="
# ============================================================

R3="$(make_repo ordering)"
roster_row "$R3" "unlanded" ".bionic/docs/record/unlanded.md"

run_orders "$R3" order unlanded
expect_status "an order over an UNMET contract is recorded, not refused" 0 "$ST"

ORDERS_FILE="$R3/.bionic/tmp/stop-orders-$SID.state"
if grep -q "^stop-order/v1|.*|target=unlanded$" "$ORDERS_FILE"; then
  ok "the record is on disk, schema-versioned and key-addressed"
else
  no "the record is on disk, schema-versioned and key-addressed" "$(cat "$ORDERS_FILE" 2>&1)"
fi

# A landed contract gives nothing up, and the order says so rather than inventing a loss.
echo landed > "$R3/.bionic/docs/record/landed.md"
roster_row "$R3" "landed" ".bionic/docs/record/landed.md"
run_orders "$R3" order landed
expect_status "an order over a MET contract is recorded too" 0 "$ST"

# An order for a name no row carries is a typo or an agent from another session; either
# way it is recorded and reported, never refused — refusing would be the wall arguing
# with the person it works for.
run_orders "$R3" order ghost
expect_status "an order for an unknown name is still recorded" 0 "$ST"

# ============================================================
echo ""
echo "=== Section 3: standdown — the batch, and what it leaves alone (AC-11, R8) ==="
# ============================================================

R4="$(make_repo standdown)"

# Four landed rows, by three different routes, plus two that must be left running.
echo a > "$R4/.bionic/docs/record/a.md"
echo b > "$R4/.bionic/docs/record/b.md"
roster_row "$R4" "met-one" ".bionic/docs/record/a.md" "" "met-one@session-6c85684c"
roster_row "$R4" "met-two" ".bionic/docs/record/b.md" "" "met-two@session-6c85684c"
roster_row "$R4" "waived-one" "" "produces nothing durable" "waived-one@session-6c85684c"
roster_row "$R4" "acked-one" ".bionic/docs/record/never.md" "" "acked-one@session-6c85684c"
( cd "$R4" && CLAUDE_CODE_SESSION_ID="$SID" bash "$SWEEPER" ack acked-one ) >/dev/null 2>&1

# LEFT ALONE: one genuinely unmet, one still live. The live row's claimed process is this
# very suite — `claims=` is checked for EXISTENCE by pattern, so the honest way to fixture a
# live claim is to name a process that really is running rather than to stub the check.
roster_row "$R4" "unmet-one" ".bionic/docs/record/missing.md" "" "unmet-one@session-6c85684c"
roster_row "$R4" "live-one" ".bionic/docs/record/missing2.md" "" "live-one@session-6c85684c" \
  "stop-orders.test.sh"

run_orders "$R4" standdown
expect_status "standdown reports and exits clean" 0 "$ST"
# MEMBERSHIP IN THE BATCH BLOCK, never in the whole output: every row this suite plants is
# printed somewhere — the held ones by name in LEFT ALONE — so `expect_contains` over $OUT
# would pass for a row that was correctly excluded, which is the assertion inverted.
STANDDOWN_BLOCK=$(printf '%s\n' "$OUT" | sed -n '/STAND DOWN/,/LEFT ALONE/p')
expect_contains "the MET row is in the batch" "met-one" "$STANDDOWN_BLOCK"
expect_contains "…and so is the second" "met-two" "$STANDDOWN_BLOCK"
expect_contains "the WAIVED row is in the batch" "waived-one" "$STANDDOWN_BLOCK"
expect_contains "the ACKED row is in the batch though its artifact never landed" \
  "acked-one" "$STANDDOWN_BLOCK"
expect_contains "…each addressed the way the stop primitive takes it" \
  "met-one@session-6c85684c" "$STANDDOWN_BLOCK"

# THE POINT OF THE OPERATION: it touches no live-unmet row. Asserted as an ABSENCE from
# the stand-down block specifically, with the paired positive that the row is present in
# the LEFT ALONE block — an absence assertion over the whole output would pass just as
# well if standdown printed nothing at all.
expect_absent "the UNMET row is NOT in the stand-down batch" "unmet-one" "$STANDDOWN_BLOCK"
expect_absent "the STILL-LIVE row is NOT in the stand-down batch" "live-one" "$STANDDOWN_BLOCK"
LEFT_BLOCK=$(printf '%s\n' "$OUT" | sed -n '/LEFT ALONE/,$p')
expect_contains "…the UNMET row is named as left alone" "unmet-one" "$LEFT_BLOCK"
expect_contains "…the STILL-LIVE row is named as left alone" "live-one" "$LEFT_BLOCK"

# A row that declared NOTHING stats MET for want of anything to hold it to. Standing it
# down on that would be standing it down on a fact nobody produced; an ack is what closes
# those rows, and until one arrives it is left alone.
R5="$(make_repo vacuous)"
roster_row "$R5" "declares-nothing" ""
run_orders "$R5" standdown
expect_status "a contract-less roster still answers" 0 "$ST"
STANDDOWN_BLOCK=$(printf '%s\n' "$OUT" | sed -n '/STAND DOWN/,/LEFT ALONE/p')
expect_absent "a vacuous MET is not a landing: not in the batch" "declares-nothing" "$STANDDOWN_BLOCK"
( cd "$R5" && CLAUDE_CODE_SESSION_ID="$SID" bash "$SWEEPER" ack declares-nothing ) >/dev/null 2>&1
run_orders "$R5" standdown
expect_contains "…and the ack is what puts it in the batch" "1 row(s) have landed" "$OUT"

# THE APPEND-ONLY ADVANCE, pinned in this suite because standdown now reads the roster
# through ONE pre-loop fold instead of re-walking the file per verdict row (ap review P-1,
# epic-16 w2 Step-6 remediation R4). The behaviour is unchanged and that is the point of
# the pin: a contract advances along the roster and every writer copies the fields forward,
# so the LAST row carrying a name is the authoritative one, and a rewrite that starts
# taking the first row must not be able to stay green here. The cross-script half — the
# sweeper, the poker and this script agreeing on the same doubled roster — is
# tests/cross-gate-agreement.test.sh §P.
R5B="$(make_repo advanced)"
echo landed > "$R5B/.bionic/docs/record/advanced.md"
roster_row "$R5B" "advancing" "" "" "stale-address@session-6c85684c"
roster_row "$R5B" "advancing" ".bionic/docs/record/advanced.md" "" "live-address@session-6c85684c"
run_orders "$R5B" standdown
expect_status "a roster carrying two rows for one name still answers" 0 "$ST"
STANDDOWN_BLOCK=$(printf '%s\n' "$OUT" | sed -n '/STAND DOWN/,/LEFT ALONE/p')
expect_contains "the LATER row is the contract: the batch addresses it by that row" \
  "live-address@session-6c85684c" "$STANDDOWN_BLOCK"
expect_absent "…and never by the superseded row's address" "stale-address@session-6c85684c" "$OUT"
expect_contains "…counted once, not twice" "1 row(s) have landed" "$OUT"

# An empty roster is not an error and not a batch.
R6="$(make_repo emptyroster)"
run_orders "$R6" standdown
expect_status "an empty roster answers cleanly" 0 "$ST"

# ============================================================
echo ""
echo "=== Section 4: the pinned root — a worktree cwd answers for the MAIN repository (6-axis A-1) ==="
# ============================================================
#
# ap review A-1: from a worktree cwd, `git rev-parse --show-toplevel` answers the WORKTREE
# root, not the repository resolve_project_root maps onto (dispatch-preflight.sh's own
# convention, epic-16 w2 Step-6 remediation R3). A roster written at the main root then
# reads as having no contract rows at all from inside the worktree.

R7="$(make_repo worktree)"
echo seed > "$R7/README.md"
git -C "$R7" add README.md >/dev/null 2>&1
git -C "$R7" commit -qm seed >/dev/null 2>&1
roster_row "$R7" "live-worker" ".bionic/docs/record/never.md" "" "live-worker@session-6c85684c"

R7WT="$SANDBOX/worktree-wt"
# A REAL `git worktree add` (never a mocked path) — built from the repo root, since
# `git worktree add` resolves relative paths against pwd (.claude/rules/git-worktree-docs.md).
git -C "$R7" worktree add -q -b w-r3-wt "$R7WT" >/dev/null 2>&1
[ -e "$R7WT/.git" ] && ok "fixture: a real git worktree exists" \
  || no "fixture: a real git worktree exists"

run_orders "$R7" standdown
expect_status "from the main repo root, standdown sees the true roster" 0 "$ST"
expect_contains "…and leaves the open row alone (not a landing)" "live-worker" "$OUT"

run_orders "$R7WT" standdown
expect_status "from the WORKTREE cwd, the SAME session's standdown still reads the true roster" 0 "$ST"
expect_contains "…still names the open row through the worktree cwd" "live-worker" "$OUT"

git -C "$R7" worktree remove --force "$R7WT" >/dev/null 2>&1

# ============================================================
echo ""
echo "──────────────────────────────────────────────"
echo "stop-orders.sh: ${PASS}/${TOTAL} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ]
