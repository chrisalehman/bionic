#!/bin/bash
# Tests for hooks/stop-orders.sh — the human's stop order, and the batch stand-down
# (epic-16 wave-02 task S3; R3, R8; AC-2's user-ordered half and AC-11).
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
. "$(dirname "$0")/lib/assert.sh"
. "$(dirname "$0")/lib/live-answer.sh"
. "$(dirname "$0")/lib/roster-row.sh"

HERE="${BIONIC_HOOKS_DIR}"
ORDERS="$HERE/stop-orders.sh"
SWEEPER="$HERE/session-sweeper.sh"

SANDBOX="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/stop-orders-test.XXXXXX")" && pwd)"
trap 'rm -rf "$SANDBOX"' EXIT

# expect_status, expect_contains, expect_absent are the framework's
# (tests/lib/assert.sh) — S9b removed the private shadows here (AC-12); same
# semantics (contains/absent are literal substring, argument order unchanged).

SID="6c85684c-9588-45a0-bd26-e8c46956c94f"

make_repo() {  # <name> -> repo path
  local repo="$SANDBOX/$1"
  mkdir -p "$repo/.bionic/tmp" "$repo/.bionic/docs/record"
  git -C "$repo" init -q 2>/dev/null
  # The initial branch is NAMED here rather than inherited from the machine's
  # init.defaultBranch: `land` refuses to merge into a protected branch (F1), so
  # a fixture whose branch depends on the operator's git config would land on
  # one machine and refuse on the next.
  git -C "$repo" symbolic-ref HEAD refs/heads/wave/fixture 2>/dev/null
  git -C "$repo" config user.email t@example.com
  git -C "$repo" config user.name "T"
  printf '%s\n' "$repo"
}

# RENAMED OFF THE WRITER'S NAME (S17): `roster_row` is the production writer
# (payload/scripts/lib/roster.sh), and a private definition of that name would shadow the
# one writer with a fixture.
so_roster_row() {  # <repo> <name> <deliverable> [waiver] [teammate-id] [claims] [progress] [cadence]
  local repo="$1" name="$2" deliv="$3" waiver="${4:-}" tmid="${5:-}" claims="${6:-}"
  local progress="${7:-}" cadence="${8:-}"
  local f="$repo/.bionic/tmp/roster-$SID.state"
  [ -f "$f" ] || roster_header > "$f"
  roster_row_fixture status=confirmed session="$SID" name="$name" agent_id= \
    launched_at=2026-08-05T00:00:00Z deliverable="$deliv" claims="$claims" \
    waiver="$waiver" teammate_id="$tmid" progress="$progress" cadence="$cadence" >> "$f"
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
section "Section 1: usage, session key, hostile paths"
# ============================================================

R1="$(make_repo usage)"

run_orders "$R1"
expect_status "no verb: usage error" 2 "$ST"
run_orders "$R1" nonsense
expect_status "unknown verb: usage error" 2 "$ST"
run_orders "$R1" order
expect_status "order with no target: usage error" 2 "$ST"
run_orders "$R1" order --at 12345
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
section "Section 2: the order verb records, reports, and never refuses (R3)"
# ============================================================

R3="$(make_repo ordering)"
so_roster_row "$R3" "unlanded" ".bionic/docs/record/unlanded.md"

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
so_roster_row "$R3" "landed" ".bionic/docs/record/landed.md"
run_orders "$R3" order landed
expect_status "an order over a MET contract is recorded too" 0 "$ST"

# An order for a name no row carries is a typo or an agent from another session; either
# way it is recorded and reported, never refused — refusing would be the wall arguing
# with the person it works for.
run_orders "$R3" order ghost
expect_status "an order for an unknown name is still recorded" 0 "$ST"

# ---------- the order's ATTRIBUTION: who said stop (AC-1.1; T1, D1) ----------
#
# An order used to mean one thing: a human said stop. From 1.8.0 it means one of two things —
# a human said stop, or a VERIFIED LANDING did (the Patrol writes one for every row whose
# contract is MET while its agent is still on the panel, so the TaskStop it asks for is not
# refused by the stop gate a moment later). The two are not the same fact and the line says
# which: `by=human` or `by=patrol`. The default is `human`, because a caller that names no
# author is a person at a terminal.

R3B="$(make_repo order-by)"
so_roster_row "$R3B" "attributed" ".bionic/docs/record/attributed.md"
ORDERS_FILE_B="$R3B/.bionic/tmp/stop-orders-$SID.state"

run_orders "$R3B" order attributed
expect_status "an order with no --by is recorded" 0 "$ST"
expect_contains "…and is attributed to a human, which is what an unattributed order is" \
  "|by=human|target=attributed" "$(cat "$ORDERS_FILE_B" 2>/dev/null)"

run_orders "$R3B" order patrolled --by patrol
expect_status "an order the Patrol places is recorded" 0 "$ST"
expect_contains "…and says so on the line the stop gate reads" \
  "|by=patrol|target=patrolled" "$(cat "$ORDERS_FILE_B" 2>/dev/null)"

run_orders "$R3B" order explicit --by human
expect_status "an explicitly human order is recorded" 0 "$ST"
expect_contains "…and reads exactly as the default does" \
  "|by=human|target=explicit" "$(cat "$ORDERS_FILE_B" 2>/dev/null)"

# THE VALUE IS A CLOSED SET. `by=` is an attribution the stop gate will print back to a
# reader; a free-text value would let a caller write whatever it liked into that sentence.
run_orders "$R3B" order someone --by nobody
expect_status "--by takes human or patrol, and refuses anything else" 2 "$ST"
run_orders "$R3B" order someone --by
expect_status "--by with no value is a usage error" 2 "$ST"
expect_absent "…and a refused order writes nothing" "target=someone" \
  "$(cat "$ORDERS_FILE_B" 2>/dev/null)"

# THE TARGET STILL COMES FIRST, and an option in its place is still refused: the flag added
# here must not turn the target into something optional.
run_orders "$R3B" order --by patrol
expect_status "the target still comes first, before any option" 2 "$ST"

# --at and --by compose, in either order.
run_orders "$R3B" order both --at 1788000000 --by patrol
expect_status "--at and --by compose" 0 "$ST"
expect_contains "…and both land on the one line" "|epoch=1788000000|" \
  "$(grep -F "|target=both" "$ORDERS_FILE_B" 2>/dev/null)"
expect_contains "…in the order the reader parses" "|by=patrol|target=both" \
  "$(cat "$ORDERS_FILE_B" 2>/dev/null)"

# ============================================================
section "Section 3: standdown — the batch, and what it leaves alone (AC-11, R8)"
# ============================================================

R4="$(make_repo standdown)"

# Four landed rows, by three different routes, plus two that must be left running.
echo a > "$R4/.bionic/docs/record/a.md"
echo b > "$R4/.bionic/docs/record/b.md"
so_roster_row "$R4" "met-one" ".bionic/docs/record/a.md" "" "met-one@session-6c85684c"
so_roster_row "$R4" "met-two" ".bionic/docs/record/b.md" "" "met-two@session-6c85684c"
so_roster_row "$R4" "waived-one" "" "produces nothing durable" "waived-one@session-6c85684c"
so_roster_row "$R4" "acked-one" ".bionic/docs/record/never.md" "" "acked-one@session-6c85684c"
( cd "$R4" && CLAUDE_CODE_SESSION_ID="$SID" bash "$SWEEPER" ack acked-one ) >/dev/null 2>&1

# LEFT ALONE: one genuinely unmet, one still live. The live row's claimed process is this
# very suite — `claims=` is checked for EXISTENCE by pattern, so the honest way to fixture a
# live claim is to name a process that really is running rather than to stub the check.
so_roster_row "$R4" "unmet-one" ".bionic/docs/record/missing.md" "" "unmet-one@session-6c85684c"
so_roster_row "$R4" "live-one" ".bionic/docs/record/missing2.md" "" "live-one@session-6c85684c" \
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
so_roster_row "$R5" "declares-nothing" ""
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
so_roster_row "$R5B" "advancing" "" "" "stale-address@session-6c85684c"
so_roster_row "$R5B" "advancing" ".bionic/docs/record/advanced.md" "" "live-address@session-6c85684c"
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
section "Section 3b: standdown on an ADOPTED WAIVED row survives /clear (S17, AC-12)"
# ============================================================
#
# THE CROSS-SCRIPT PROOF. §3 above plants a waived row by hand with `roster_row`; this plants
# it on a PREDECESSOR's roster and runs the real hooks/session-poker.sh `adopt` verb to carry
# it onto THIS session's own roster, exactly the shape a user-run `/clear` leaves behind
# (ac12-t4-walk-2.md). `standdown` never reads the marker or re-derives anything of its own —
# it asks `session-sweeper.sh verdict`, which reads `waiver=` straight off the row — so this
# is a pin on the CARRY, not on standdown's own logic.
R3B="$(make_repo adopted-waived)"
mkdir -p "$R3B/.bionic/docs/record"
ADOPT3B_PRED="9f1e2d3c-4b5a-6978-8899-aabbccddeeff"
ADOPT3B_ID="aadoptedwaived00000000000000000"
ADOPT3B_ROSTER="$R3B/.bionic/tmp/roster-$ADOPT3B_PRED.state"
roster_header > "$ADOPT3B_ROSTER"
roster_row_fixture status=identified session="$ADOPT3B_PRED" name=adopted-waived-row \
  agent_id="$ADOPT3B_ID" launched_at=2026-08-05T00:00:00Z cadence='10 minutes' \
  waiver='probe only — a throwaway read-only agent for the standdown/adopt walk' \
  tool_use_id=toolu_01S17FIX >> "$ADOPT3B_ROSTER"

# `adopt` decides nothing in a session that never engaged bionic (AC-10) — the same guard
# session-poker.test.sh's fixtures carry, planted by hand here since this suite has no
# engagement helper of its own.
: > "$R3B/.bionic/tmp/engaged-$SID.state"
( cd "$R3B" && CLAUDE_CODE_SESSION_ID="$SID" bash "$HERE/session-poker.sh" adopt ) >/dev/null 2>&1

run_orders "$R3B" standdown
expect_status "standdown over a freshly-adopted roster reports and exits clean" 0 "$ST"
SD3B_BLOCK=$(printf '%s\n' "$OUT" | sed -n '/STAND DOWN/,/LEFT ALONE/p')
expect_contains "the adopted row is in the stand-down batch" \
  "adopted-waived-row" "$SD3B_BLOCK"
expect_contains "…because its CARRIED waiver, not an ack or a fresh MET" \
  "waived — adopted-waived-row" "$SD3B_BLOCK"

# ============================================================
section "Section 4: the pinned root — a worktree cwd answers for the MAIN repository (6-axis A-1)"
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
so_roster_row "$R7" "live-worker" ".bionic/docs/record/never.md" "" "live-worker@session-6c85684c"

R7WT="$SANDBOX/worktree-wt"
# A REAL `git worktree add` (never a mocked path) — built from the repo root, since
# `git worktree add` resolves relative paths against pwd (.claude/rules/git-worktree-docs.md).
git -C "$R7" worktree add -q -b w-r3-wt "$R7WT" >/dev/null 2>&1
# (fixture sanity check removed epic-18 W3 4/6: not a subject-under-test assertion --
#  it verified git worktree add itself, not hooks/stop-orders.sh; see ledger-stop-orders.md)

run_orders "$R7" standdown
expect_status "from the main repo root, standdown sees the true roster" 0 "$ST"
expect_contains "…and leaves the open row alone (not a landing)" "live-worker" "$OUT"

run_orders "$R7WT" standdown
expect_status "from the WORKTREE cwd, the SAME session's standdown still reads the true roster" 0 "$ST"
expect_contains "…still names the open row through the worktree cwd" "live-worker" "$OUT"

git -C "$R7" worktree remove --force "$R7WT" >/dev/null 2>&1

# ============================================================
section "Section 6: standdown LANDS the trees it stands down (AC-28, C1)"
# ============================================================
#
# C1: a worktree is a leased slot bound to its ledger row, and standing an agent
# down is where the lease ends. standdown does not stop anybody — stopping is
# the harness's — but the tree is disk, and giving it back is this script's to
# do. The act itself is payload/scripts/lib/worktree.sh's `worktree_land`; what
# is asserted here is that standdown calls it once per DISCHARGED row and
# reports every answer, refusals included.
#
# A row is matched to its tree by the convention the whole repo uses: a row
# named `<x>` (or `W-<X>`) holds `.worktrees/<x>`.

R8="$(make_repo standdown-lands)"
echo seed > "$R8/README.md"
git -C "$R8" add README.md >/dev/null 2>&1
git -C "$R8" commit -qm seed >/dev/null 2>&1

# Three trees, each a branch with a commit of its own so there is something to
# land; the third is left dirty so its landing must refuse.
for t in land-a land-b land-c; do
  git -C "$R8" worktree add -q -b "$t" "$R8/.worktrees/$t" >/dev/null 2>&1
  echo "$t" > "$R8/.worktrees/$t/$t.txt"
  git -C "$R8/.worktrees/$t" add -A >/dev/null 2>&1
  git -C "$R8/.worktrees/$t" commit -qm "$t work" >/dev/null 2>&1
done
echo "unsaved" >> "$R8/.worktrees/land-c/land-c.txt"

# A fourth row that is NOT discharged, holding a tree that must survive: the
# point of the operation is that it touches only what has landed.
# It carries a commit of its own on purpose: a branch with nothing beyond the
# main checkout is "merged" trivially, and the not-merged assertion below would
# pass without proving anything.
git -C "$R8" worktree add -q -b still-working "$R8/.worktrees/still-working" >/dev/null 2>&1
echo working > "$R8/.worktrees/still-working/wip.txt"
git -C "$R8/.worktrees/still-working" add -A >/dev/null 2>&1
git -C "$R8/.worktrees/still-working" commit -qm "wip" >/dev/null 2>&1

for n in land-a land-b land-c; do
  echo "$n" > "$R8/.bionic/docs/record/$n.md"
  so_roster_row "$R8" "$n" ".bionic/docs/record/$n.md" "" "$n@session-6c85684c"
done
so_roster_row "$R8" "still-working" ".bionic/docs/record/nothing.md" "" "still-working@session-6c85684c"

run_orders "$R8" standdown
expect_status "standdown with trees exits clean" 0 "$ST"

expect_contains "the first discharged row's tree is reported LANDED" \
  "LANDED branch=land-a" "$OUT"
expect_contains "…and so is the second" "LANDED branch=land-b" "$OUT"
expect_contains "the dirty tree is reported REFUSED, naming why" \
  "REFUSED reason=dirty-tree" "$OUT"
expect_contains "…and the refusal is attributable to its row" "land-c" "$OUT"

# READ BACK FROM DISK, not from the report: a line claiming a landing is not a
# landing.
if [ ! -d "$R8/.worktrees/land-a" ]; then ok "the landed tree is gone"; else no "the landed tree is gone"; fi
if [ ! -d "$R8/.worktrees/land-b" ]; then ok "…and so is the second"; else no "…and so is the second"; fi
if [ -d "$R8/.worktrees/land-c" ]; then ok "the refused tree is still there"; else no "the refused tree is still there"; fi
if [ -d "$R8/.worktrees/still-working" ]; then
  ok "the tree of a row that has NOT landed is untouched"
else
  no "the tree of a row that has NOT landed is untouched"
fi
if git -C "$R8" rev-list --count "HEAD..land-a" 2>/dev/null | grep -qx 0; then
  ok "land-a's work is merged into the main checkout"
else
  no "land-a's work is merged into the main checkout"
fi
if git -C "$R8" show-ref --verify --quiet refs/heads/land-a; then
  ok "and its BRANCH survives the landing"
else
  no "and its BRANCH survives the landing"
fi
if git -C "$R8" rev-list --count "HEAD..still-working" 2>/dev/null | grep -qx 0; then
  no "the unlanded row's branch was merged" "standdown merged a row it should have left alone"
else
  ok "the unlanded row's branch was NOT merged"
fi

# A REFUSAL THE OPERATOR MUST SEE. `land` refuses to merge into a protected
# branch (security F1), and standdown reports that refusal the way it reports a
# dirty tree — it is not a special case here, and the tree stays standing.
R9="$(make_repo standdown-protected)"
echo seed > "$R9/README.md"
git -C "$R9" add README.md >/dev/null 2>&1
git -C "$R9" commit -qm seed >/dev/null 2>&1
git -C "$R9" worktree add -q -b land-p "$R9/.worktrees/land-p" >/dev/null 2>&1
echo p > "$R9/.worktrees/land-p/land-p.txt"
git -C "$R9/.worktrees/land-p" add -A >/dev/null 2>&1
git -C "$R9/.worktrees/land-p" commit -qm "land-p work" >/dev/null 2>&1
git -C "$R9" checkout -q -b main
echo land-p > "$R9/.bionic/docs/record/land-p.md"
so_roster_row "$R9" "land-p" ".bionic/docs/record/land-p.md" "" "land-p@session-6c85684c"

run_orders "$R9" standdown
expect_status "standdown on a protected checkout still exits clean" 0 "$ST"
expect_contains "the land onto main is reported REFUSED, naming the branch" \
  "REFUSED reason=protected-branch branch=main" "$OUT"
if [ -d "$R9/.worktrees/land-p" ]; then ok "the tree of the refused land is still there"; else no "the tree of the refused land is still there"; fi
if git -C "$R9" rev-list --count "HEAD..land-p" 2>/dev/null | grep -qx 0; then
  no "main was merged into" "standdown merged unreviewed work into main"
else
  ok "main was NOT merged into"
fi

# A roster with no trees at all must behave exactly as it did before this
# feature: the landing report is additive, never a precondition.
run_orders "$R4" standdown
expect_status "a session with no trees stands down unchanged" 0 "$ST"
expect_absent "…and reports no landings" "LANDED branch=" "$OUT"

# ============================================================
section "Section 7: standdown reports LIVENESS beside a held row, and still writes nothing (S6)"
# ============================================================
#
# WHAT THE ROSTER CANNOT SAY. A row whose contract has not landed is held either way, and
# `UNMET` reads the same whether the agent is still working on it or finished without
# delivering — the second is the reported defect (B-2), and it is the state an operator most
# needs to see. Since S6 the harness's own answer can say which, so the LEFT ALONE block says
# it. Nothing else about this verb moves: it reports, it decides nothing, and it writes
# nothing to the roster.

R8="$(make_repo liveness)"
R8CFG="$SANDBOX/liveness-cfg"
R8SLUG=$(printf '%s' "$R8" | sed 's/[^a-zA-Z0-9]/-/g')
mkdir -p "$R8CFG/projects/$R8SLUG"
R8TR="$R8CFG/projects/$R8SLUG/$SID.jsonl"

# THE ANSWER BODY IS BUILT BY tests/lib/live-answer.sh (S17, spec AC-27/AC-28): the self
# line, the `Teammates (N):` header and every teammate row come out of the committed corpus
# at tests/fixtures/claude/listagents-answers.jsonl with only this suite's names and
# statuses substituted in place. The private builder that used to sit here re-typed the
# harness's separator, its ref suffix and its recognition anchor — three spellings of that
# anchor across the tree, and the one thing standing between "empty answer" and
# "unrecognised body".
# FRESH because the answer postdates the last user prompt.
LIVE_ANSWER_TYPE="bionic:implementor"
plant_live() {  # <transcript> <fresh|stale> <name>...
  local tr="$1" freshness="$2"; shift 2
  local body
  body="$(live_answer_body "$@")"
  {
    jq -nc --arg ts "2026-09-05T00:50:00.000Z" \
      '{type:"user",timestamp:$ts,message:{role:"user",content:"go"}}'
    jq -nc --arg ts "2026-09-05T00:51:00.000Z" \
      '{type:"assistant",timestamp:$ts,message:{role:"assistant",content:[{type:"tool_use",id:"toolu_01FIXTURELISTAGENTS",name:"ListAgents",input:{}}]}}'
    jq -nc --arg ts "2026-09-05T00:52:23.349Z" --arg b "$body" \
      '{type:"user",timestamp:$ts,message:{role:"user",content:[{type:"tool_result",tool_use_id:"toolu_01FIXTURELISTAGENTS",content:$b}]}}'
    if [ "$freshness" = "stale" ]; then
      jq -nc --arg ts "2026-09-05T00:53:00.000Z" \
        '{type:"user",timestamp:$ts,message:{role:"user",content:"a later turn"}}'
    fi
  } > "$tr"
  return 0
}

run_orders_cfg() {  # <repo> <args…> — like run_orders, with the metadata root pinned
  local repo="$1"; shift
  OUT=$( cd "$repo" && CLAUDE_CODE_SESSION_ID="$SID" CLAUDE_CONFIG_DIR="$R8CFG" \
         bash "$ORDERS" "$@" 2>"$SANDBOX/.err" ); ST=$?
  ERR=$(cat "$SANDBOX/.err")
  return 0
}

echo landed > "$R8/.bionic/docs/record/landed.md"
so_roster_row "$R8" "met-row"   ".bionic/docs/record/landed.md"  "" "met-row@session-6c85684c"
so_roster_row "$R8" "still-at-it" ".bionic/docs/record/nope.md"  "" "still-at-it@session-6c85684c"
so_roster_row "$R8" "walked-off"  ".bionic/docs/record/nope2.md" "" "walked-off@session-6c85684c"
plant_live "$R8TR" fresh "still-at-it"

R8_BEFORE=$(cat "$R8/.bionic/tmp/roster-$SID.state")
run_orders_cfg "$R8" standdown
expect_status "standdown reports and exits clean" 0 "$ST"

R8_SD=$(printf '%s\n' "$OUT" | sed -n '/STAND DOWN/,/LEFT ALONE/p')
R8_LA=$(printf '%s\n' "$OUT" | sed -n '/LEFT ALONE/,$p')
expect_contains "the MET row is stood down, unchanged by any of this" "met-row" "$R8_SD"
expect_contains "…and named as met" "met" "$R8_SD"
expect_contains "the row whose agent the harness still names is marked live" \
  "still-at-it   (UNMET" "$R8_LA"
expect_contains "…with the liveness the roster alone cannot express" "[live]" "$R8_LA"
expect_contains "the row whose agent the harness does NOT name is marked not live" \
  "walked-off" "$R8_LA"
expect_contains "…which is the finished-but-unstopped state (B-2)" "[not live]" "$R8_LA"

# AND IT WROTE NOTHING. The roster is byte-identical after the report, which is the whole
# contract of this verb — reading the live set added a sentence, not a side effect.
if [ "$R8_BEFORE" = "$(cat "$R8/.bionic/tmp/roster-$SID.state")" ]; then
  ok "standdown wrote nothing to the roster"
else
  no "standdown wrote nothing to the roster" "the roster changed"
fi

# A STALE ANSWER EARNS NO ANNOTATION. The reader still prints a stale set — only its exit
# status says "do not act" — so a caller that branched on the set rather than the status
# would label a departed agent live. The report says nothing rather than something wrong.
plant_live "$R8TR" stale "still-at-it"
run_orders_cfg "$R8" standdown
R8_LA2=$(printf '%s\n' "$OUT" | sed -n '/LEFT ALONE/,$p')
expect_contains "a stale answer still leaves the held rows reported" "still-at-it" "$R8_LA2"
expect_absent "…but with no liveness claim on them" "[live]" "$R8_LA2"
expect_absent "…and none the other way either" "[not live]" "$R8_LA2"

# …and with no answer at all, the same silence. The paired positive is the fresh run above.
: > "$R8TR"
run_orders_cfg "$R8" standdown
R8_LA3=$(printf '%s\n' "$OUT" | sed -n '/LEFT ALONE/,$p')
expect_contains "with no answer at all the held rows are still reported" "walked-off" "$R8_LA3"
expect_absent "…and still carry no liveness claim" "[not live]" "$R8_LA3"


# A NAME IS NOT A PATTERN (S-5). `_is_live` dropped the roster's name straight into a basic
# regular expression, so a `.`, `*` or `[` in it over-matched — and the name is the operator's
# typed target or a value lifted off a row, neither of which the fleet charset-guards. The row
# below answers to nothing in the live set and would be annotated `[live]` off its neighbour's
# name alone. Diagnostic-only, and the annotation is the entire point of this block.
so_roster_row "$R8" "s.ill-at-it" ".bionic/docs/record/nope3.md" "" "s.ill-at-it@session-6c85684c"
plant_live "$R8TR" fresh "still-at-it"
run_orders_cfg "$R8" standdown
R8_LA4=$(printf '%s\n' "$OUT" | sed -n '/LEFT ALONE/,$p')
R8_META=$(printf '%s\n' "$R8_LA4" | grep -F 's.ill-at-it')
expect_contains "the metacharacter row is still reported (the arm is not vacuous)" \
  "s.ill-at-it" "$R8_META"
expect_contains "…and a name carrying a regex metacharacter is matched LITERALLY: not live" \
  "[not live]" "$R8_META"
expect_absent "…never annotated live off the neighbour its pattern would have matched" \
  "  [live]" "$R8_META"
# The paired positive on the same run: the neighbour it would have matched IS live, so the
# row above is a statement about the match and not about a live set that had gone empty.
expect_contains "…while the real still-at-it beside it is still live" "[live]" \
  "$(printf '%s\n' "$R8_LA4" | grep -F 'still-at-it   (UNMET')"


# ============================================================
section "Section 8: stopped <name> acks the row it stops; standdown drops a row only when acked AND gone (wave-19 T1; REQ-1 AC-1.2/1.3; D3; ADR-034)"
# ============================================================
#
# THE ACK IS THE CLOSE (ADR-034 d1). A TaskStop ends a process; nothing in it closes the
# name. `stopped <name>` is the verb that does, beside the stop: one verdict read decides
# whether there is a row to close, and the close goes through the sweeper's own `ack` verb —
# the same call shape the tick's STANDDOWN close makes — never a private ledger write.
# An unknown or already-acked name is a refusal, exit 2: the sweeper would record an unknown
# name and warn, and a second ack says nothing new.
#
# STOPPED NOW CHECKS WHAT STANDDOWN ALREADY CHECKS (wave-19 T1 follow-up, critic C4). Before
# this fix `stopped` acked ANY open row on the strength of the name alone — still-live or
# UNMET — and since T4 that ack frees the name for a fresh dispatch while the agent it named
# is still running (dispatch-preflight.sh:2272 treats any ack newer than the launch as the
# name closing). So a FRESH panel reading must confirm the name is gone: present on the
# panel -> refused, naming it live; a stale or absent panel -> refused, because a verb that
# cannot see does not ack. The verdict picks the reason (T1e, audit V-1): MET or WAIVED
# closes `landed`, UNMET closes `abandoned`, any other state is refused, naming it. The ack it writes is `--by human`, never `--by patrol`: this is a
# deliberate model-callable verb, not the tick's own automated sweep.
R9="$(make_repo stopped)"
R9SLUG=$(printf '%s' "$R9" | sed 's/[^a-zA-Z0-9]/-/g')
mkdir -p "$R8CFG/projects/$R9SLUG"
R9TR="$R8CFG/projects/$R9SLUG/$SID.jsonl"
so_roster_row "$R9" "open-one" ".bionic/docs/record/never.md" "" "open-one@session-6c85684c"
s9_ledger() { cat "$R9/.bionic/tmp/sweeper-$SID.state" 2>/dev/null; }

# UNMET AND STILL ON A FRESH PANEL: refused, naming the verdict (C4, unchanged by T1e). An
# agent that is visibly working has not been stopped, whatever its contract says.
plant_live "$R9TR" fresh "open-one"
run_orders_cfg "$R9" stopped open-one
expect_status "stopped on an UNMET row the fresh panel still lists is refused, exit 2 (C4)" 2 "$ST"
expect_contains "…naming the verdict" "UNMET" "$OUT$ERR"
expect_contains "…and naming it live" "still on the panel" "$OUT$ERR"
expect_absent "…and acks nothing" "|name=open-one|" "$(s9_ledger)"

# UNMET UNDER A STALE PANEL: refused, naming the verdict (C4). A verb that cannot see does
# not ack, and "the panel is old" is not evidence that the agent left.
plant_live "$R9TR" stale
run_orders_cfg "$R9" stopped open-one
expect_status "stopped on an UNMET row under a stale panel is refused, exit 2 (C4)" 2 "$ST"
expect_contains "…naming the verdict" "UNMET" "$OUT$ERR"
expect_absent "…and acks nothing" "|name=open-one|" "$(s9_ledger)"

# UNMET AND GONE FROM A FRESH PANEL: closed, reason abandoned (wave-19 T1e, audit V-1; REQ-1
# AC-1.2). This is T1's own original fixture — `open-one`'s deliverable never exists — and
# the agent it named was stopped before it landed (w19-T6 this wave). Refusing it left the
# name blocked and counted against the budget with no close but a hand `sweeper ack`. The
# ack is attributed honestly: `reason=abandoned`, never `landed` — nothing landed — and never
# the tick's `moot-and-gone`, which names a row that had nothing to produce.
plant_live "$R9TR" fresh
run_orders_cfg "$R9" stopped open-one
expect_status "stopped on an UNMET row the fresh panel shows gone acks it, exit 0 (V-1)" 0 "$ST"
expect_contains "…through the sweeper, by a human verb, reason abandoned" \
  "|name=open-one|by=human|reason=abandoned" "$(s9_ledger)"
expect_absent "…and never as landed" "|name=open-one|by=human|reason=landed" "$(s9_ledger)"
expect_contains "…saying so to the operator" "reason abandoned" "$OUT"
expect_contains "…so the one verdict line reports it closed" "|acked=yes|" \
  "$( cd "$R9" && CLAUDE_CODE_SESSION_ID="$SID" bash "$SWEEPER" verdict open-one 2>/dev/null )"
run_orders_cfg "$R9" standdown
expect_status "standdown after an abandoned close exits clean" 0 "$ST"
expect_absent "…and lists the abandoned row nowhere: closed, and nobody left to stop (AC-1.3)" \
  "open-one" "$OUT"

# MET, but the fresh panel still lists the agent: refused, naming it live (C4) — the
# defect's sharper edge, a landed contract whose agent is still working.
echo landed > "$R9/.bionic/docs/record/met-live.md"
so_roster_row "$R9" "met-live" ".bionic/docs/record/met-live.md" "" "met-live@session-6c85684c"
plant_live "$R9TR" fresh "met-live"
run_orders_cfg "$R9" stopped met-live
expect_status "stopped on a row the fresh panel still lists is refused, exit 2 (C4)" 2 "$ST"
expect_contains "…naming it as live" "met-live" "$OUT$ERR"
expect_absent "…and acks nothing" "|name=met-live|" "$(s9_ledger)"

# A STALE panel: refused too — a verb that cannot see does not ack (C4). Still MET, still
# actually gone; only the panel reading is untrustworthy.
plant_live "$R9TR" stale
run_orders_cfg "$R9" stopped met-live
expect_status "stopped under a stale panel is refused, exit 2 (C4)" 2 "$ST"
expect_absent "…and acks nothing" "|name=met-live|" "$(s9_ledger)"

# MET, and the fresh panel shows the agent gone: acked, by a human verb, reason landed (C4).
# This is the one case `stopped` still closes — the verb runs beside TaskStop, after the
# agent is gone.
plant_live "$R9TR" fresh
run_orders_cfg "$R9" stopped met-live
expect_status "stopped on a MET row the fresh panel shows gone acks it, exit 0" 0 "$ST"
expect_contains "…acked through the sweeper, by a human verb, reason landed" \
  "|name=met-live|by=human|reason=landed" "$(s9_ledger)"
expect_contains "…on the sweeper's own ledger schema" "sweeper-ledger/v1|event=ack|" "$(s9_ledger)"
expect_contains "…so the one verdict line now reports it closed" "|acked=yes|" \
  "$( cd "$R9" && CLAUDE_CODE_SESSION_ID="$SID" bash "$SWEEPER" verdict met-live 2>/dev/null )"

run_orders_cfg "$R9" stopped met-live
expect_status "stopped on an ALREADY-ACKED name is refused, exit 2" 2 "$ST"
expect_contains "…saying why in one line" "met-live" "$OUT$ERR"
expect_eq "…and writes no second ack" "1" \
  "$(s9_ledger | grep -c '|event=ack|.*|name=met-live|' | tr -d ' ')"

run_orders "$R9" stopped nobody-here
expect_status "stopped on an UNKNOWN name is refused, exit 2" 2 "$ST"
expect_eq "…in exactly one line" "1" \
  "$(printf '%s\n' "$OUT$ERR" | grep -c . | tr -d ' ')"
expect_absent "…and nothing is recorded for it" "|name=nobody-here|" "$(s9_ledger)"

run_orders "$R9" stopped
expect_status "stopped with no target is a usage refusal" 2 "$ST"
run_orders "$R9" stopped --by human
expect_status "stopped takes the target first, as order does" 2 "$ST"
expect_contains "…and says so" "the target comes first" "$ERR"

# ---------- standdown: an acked row keeps its address until a FRESH panel shows it gone ----------
R10="$(make_repo standdown-acked)"
R10SLUG=$(printf '%s' "$R10" | sed 's/[^a-zA-Z0-9]/-/g')
mkdir -p "$R8CFG/projects/$R10SLUG"
R10TR="$R8CFG/projects/$R10SLUG/$SID.jsonl"
so_roster_row "$R10" "acked-live" ".bionic/docs/record/n1.md" "" "acked-live@session-6c85684c"
so_roster_row "$R10" "acked-gone" ".bionic/docs/record/n2.md" "" "acked-gone@session-6c85684c"
( cd "$R10" && CLAUDE_CODE_SESSION_ID="$SID" bash "$SWEEPER" ack acked-live acked-gone ) >/dev/null 2>&1
plant_live "$R10TR" fresh "acked-live"
run_orders_cfg "$R10" standdown
expect_status "standdown with acked rows exits clean" 0 "$ST"
R10_SD=$(printf '%s\n' "$OUT" | sed -n '/STAND DOWN/,/LEFT ALONE/p')
expect_contains "an acked row the fresh panel still lists keeps its stop address (AC-1.3)" \
  "acked-live@session-6c85684c   (acked — acked-live)" "$R10_SD"
expect_absent "an acked row a fresh panel shows GONE is not listed at all (AC-1.3)" \
  "acked-gone" "$OUT"

# A STALE panel is not evidence the agent left: the acked row keeps its address.
plant_live "$R10TR" stale "acked-live"
run_orders_cfg "$R10" standdown
expect_contains "under a stale panel the acked-gone row keeps its address" \
  "acked-gone@session-6c85684c   (acked — acked-gone)" "$OUT"

# ---------- standdown ENDS THE LEASE of an acked-and-gone row too (wave-19 T1b, R2) ----------
#
# `continue`-ing out of the acked-and-gone branch before the LANDED/REFUSED block runs
# means the common path — land, stop, tick ack — never reaches worktree_land for that row:
# the tree stands until someone runs `spawn-worktree.sh land` by hand, which undoes spec
# AC-28 (1.4.0, "standing an agent down is where the lease ends"). The row stays out of
# READY — an ack already closed it and there is nobody left to stop — but its lease still
# has to end here, because standdown is the only pass that will ever look at this row again.
R11="$(make_repo standdown-acked-gone-lease)"
echo seed > "$R11/README.md"
git -C "$R11" add README.md >/dev/null 2>&1
git -C "$R11" commit -qm seed >/dev/null 2>&1
git -C "$R11" worktree add -q -b acked-gone-lease "$R11/.worktrees/acked-gone-lease" >/dev/null 2>&1
echo work > "$R11/.worktrees/acked-gone-lease/work.txt"
git -C "$R11/.worktrees/acked-gone-lease" add -A >/dev/null 2>&1
git -C "$R11/.worktrees/acked-gone-lease" commit -qm "acked-gone-lease work" >/dev/null 2>&1

R11SLUG=$(printf '%s' "$R11" | sed 's/[^a-zA-Z0-9]/-/g')
mkdir -p "$R8CFG/projects/$R11SLUG"
R11TR="$R8CFG/projects/$R11SLUG/$SID.jsonl"
# THE DELIVERABLE IS WRITTEN (wave-19 T1f, review R2-1). Before T1f this row's n3.md was never
# written, so the row was UNMET and this block pinned a merge of work nobody landed. A lease
# ends in a merge only for a landed row (MET or WAIVED); the UNMET shape is R12 below.
echo landed > "$R11/.bionic/docs/record/n3.md"
so_roster_row "$R11" "acked-gone-lease" ".bionic/docs/record/n3.md" "" "acked-gone-lease@session-6c85684c"
( cd "$R11" && CLAUDE_CODE_SESSION_ID="$SID" bash "$SWEEPER" ack acked-gone-lease ) >/dev/null 2>&1
# A fresh panel that lists nobody: the row's agent is gone, not merely stale.
plant_live "$R11TR" fresh
run_orders_cfg "$R11" standdown
expect_status "standdown over an acked-and-gone row with a tree exits clean" 0 "$ST"

R11_SD=$(printf '%s\n' "$OUT" | sed -n '/STAND DOWN/,/LEFT ALONE/p')
expect_absent "the acked-and-gone row is kept out of READY (AC-1.3 unchanged by R2)" \
  "acked-gone-lease" "$R11_SD"
expect_contains "…but its lease still ends, reported under LEASES" \
  "LANDED branch=acked-gone-lease" "$OUT"
expect_contains "…attributable to its row by name" \
  "(acked-gone-lease)" "$OUT"
if [ ! -d "$R11/.worktrees/acked-gone-lease" ]; then
  ok "the acked-and-gone row's tree is actually landed, not just reported"
else
  no "the acked-and-gone row's tree is actually landed, not just reported"
fi
if git -C "$R11" rev-list --count "HEAD..acked-gone-lease" 2>/dev/null | grep -qx 0; then
  ok "…its work is merged into the main checkout"
else
  no "…its work is merged into the main checkout"
fi

# ============================================================
# AN ABANDONED ROW'S TREE STANDS (wave-19 T1f, review R2-1). T1b made standdown land the tree
# of every acked-and-gone row; T1e made `stopped` ack an UNMET-and-gone row as `abandoned`.
# Together, `stopped` then `standdown` merged an abandoned agent's partial work into whatever
# branch the main checkout sat on — hidden on main/master by the protected-branch refusal,
# live everywhere else. So this fixture puts the main checkout on a NON-protected branch
# (`integration`), the one shape where the refusal cannot mask the merge. The verdict, not
# the ack's reason, decides: UNMET leaves tree and branch in place for a human to salvage.
# ============================================================
R12="$(make_repo standdown-abandoned-stands)"
echo seed > "$R12/README.md"
git -C "$R12" add README.md >/dev/null 2>&1
git -C "$R12" commit -qm seed >/dev/null 2>&1
git -C "$R12" checkout -qb integration
git -C "$R12" worktree add -q -b half-done "$R12/.worktrees/half-done" >/dev/null 2>&1
echo partial > "$R12/.worktrees/half-done/partial.txt"
git -C "$R12/.worktrees/half-done" add -A >/dev/null 2>&1
git -C "$R12/.worktrees/half-done" commit -qm "half-done WIP" >/dev/null 2>&1

R12SLUG=$(printf '%s' "$R12" | sed 's/[^a-zA-Z0-9]/-/g')
mkdir -p "$R8CFG/projects/$R12SLUG"
R12TR="$R8CFG/projects/$R12SLUG/$SID.jsonl"
# The deliverable is never written: the row is UNMET when its agent goes.
so_roster_row "$R12" "half-done" ".bionic/docs/record/never.md" "" "half-done@session-6c85684c"
plant_live "$R12TR" fresh

run_orders_cfg "$R12" stopped half-done
expect_status "stopped closes the UNMET-and-gone row (the T1e precondition)" 0 "$ST"
expect_contains "…as abandoned" "reason abandoned" "$OUT"

run_orders_cfg "$R12" standdown
expect_status "standdown over an abandoned row with a tree exits clean" 0 "$ST"
if [ "$(git -C "$R12" rev-parse --abbrev-ref HEAD 2>/dev/null)" = "integration" ]; then
  ok "the main checkout is on a non-protected branch (the refusal cannot mask a merge)"
else
  no "the main checkout is on a non-protected branch (the refusal cannot mask a merge)"
fi
if [ "$(git -C "$R12" rev-list --count "HEAD..half-done" 2>/dev/null)" = "1" ]; then
  ok "the abandoned branch is NOT merged: it is still ahead of the main checkout"
else
  no "the abandoned branch is NOT merged: it is still ahead of the main checkout" \
    "HEAD..half-done = $(git -C "$R12" rev-list --count "HEAD..half-done" 2>&1)"
fi
expect_absent "…and no LANDED line claims it" "LANDED branch=half-done" "$OUT"
if [ -d "$R12/.worktrees/half-done" ] && [ -f "$R12/.worktrees/half-done/partial.txt" ]; then
  ok "…its tree stands, the partial work still in it"
else
  no "…its tree stands, the partial work still in it"
fi
R12_LE=$(printf '%s\n' "$OUT" | sed -n '/LEASES/,$p')
R12_REAL=$(cd "$R12" && pwd -P)   # the verb names trees under the physical repo path
expect_contains "the LEASES report names the tree as abandoned and standing" \
  "abandoned — tree stands: $R12_REAL/.worktrees/half-done (branch half-done); remove or salvage by hand   (half-done)" \
  "$R12_LE"
expect_absent "…and the header no longer reads as if nothing touched a tree" \
  "nothing has landed; there is nobody to stand down." "$OUT"

# ============================================================
section "Section 9: stopped — STILL-LIVE is not a close on its own; a fresh, absent panel overrides the progress-artifact shape (wave-19 T1g, audit V2-1, critic C2-2)"
# ============================================================
#
# STILL-LIVE used to refuse `stopped` unconditionally, whatever the panel showed: a writer
# TaskStopped mid-work has, by construction, a progress artifact inside its cadence, so the
# refusal held for up to the whole cadence and the slot stayed occupied the entire time —
# the exact w19-T6 shape `stopped` exists to close (A-orch-4). The panel is the stronger
# fact once it is fresh: absent from it closes the row `abandoned`, exactly like
# UNMET-and-gone (T1e). A claimed-process pattern that still matches a live process is a
# fact the panel cannot speak to either way (it lists this session's roster of agents, not
# the processes one may have started), so that shape stays refused even panel-gone.
R13="$(make_repo stopped-still-live)"
R13SLUG=$(printf '%s' "$R13" | sed 's/[^a-zA-Z0-9]/-/g')
mkdir -p "$R8CFG/projects/$R13SLUG"
R13TR="$R8CFG/projects/$R13SLUG/$SID.jsonl"
s13_ledger() { cat "$R13/.bionic/tmp/sweeper-$SID.state" 2>/dev/null; }

R13PROG="$R13/.bionic/docs/record/progress13.md"
mkdir -p "$(dirname "$R13PROG")"
echo working > "$R13PROG"   # written just now — inside any cadence
so_roster_row "$R13" "still-live-gone" ".bionic/docs/record/never-slg.md" "" \
  "still-live-gone@session-6c85684c" "" "$R13PROG" "10 minutes"

# STILL-LIVE, and still on a fresh panel: refused, naming the wait rather than a bare "not
# landed" — there is something to do, and the line now says what.
plant_live "$R13TR" fresh "still-live-gone"
run_orders_cfg "$R13" stopped still-live-gone
expect_status "STILL-LIVE and still on a fresh panel is refused, exit 2" 2 "$ST"
expect_contains "…naming the wait" \
  "retry after the cadence elapses, or when a fresh panel no longer lists it" "$OUT$ERR"
expect_absent "…and acks nothing" "|name=still-live-gone|" "$(s13_ledger)"

# STILL-LIVE under a stale panel: refused too, same wait — a verb that cannot see does not
# ack, and staleness is not evidence the agent left.
plant_live "$R13TR" stale
run_orders_cfg "$R13" stopped still-live-gone
expect_status "STILL-LIVE under a stale panel is refused, exit 2" 2 "$ST"
expect_contains "…naming the same wait" \
  "retry after the cadence elapses, or when a fresh panel no longer lists it" "$OUT$ERR"
expect_absent "…and acks nothing" "|name=still-live-gone|" "$(s13_ledger)"

# STILL-LIVE, and the fresh panel shows the agent GONE: the panel overrides the progress
# artifact — closed `abandoned`, same as UNMET-and-gone, and the operator is told why.
plant_live "$R13TR" fresh
run_orders_cfg "$R13" stopped still-live-gone
expect_status "STILL-LIVE the fresh panel shows gone is acked, exit 0 (V2-1)" 0 "$ST"
expect_contains "…through the sweeper, by a human verb, reason abandoned" \
  "|name=still-live-gone|by=human|reason=abandoned" "$(s13_ledger)"
expect_contains "…and the operator is told the panel is what decided it" \
  "panel-gone overrides STILL-LIVE" "$OUT"
expect_contains "…naming the progress artifact's age and the cadence" "s old, cadence" "$OUT"
expect_contains "…so the one verdict line reports it closed" "|acked=yes|" \
  "$( cd "$R13" && CLAUDE_CODE_SESSION_ID="$SID" bash "$SWEEPER" verdict still-live-gone 2>/dev/null )"

# THE CLAIMED-PROCESS SHAPE IS NOT OVERRIDDEN. `claims=` is checked for EXISTENCE by
# pattern (session-sweeper.sh's `claims_live`, which shells out to `pgrep -f`), so the
# honest way to fixture a live claim is a process that really is running — a background
# CHILD of this suite, never the suite's own process. macOS `pgrep` excludes its own
# ancestor chain by default (`man pgrep`: "the current pgrep or pkill process and all of
# its ancestors are excluded"), and `claims_live`'s `pgrep -f` runs several processes below
# this suite (stop-orders.sh -> session-sweeper.sh -> pgrep), so a claim naming the SUITE's
# own filename is never actually found by it — the standdown LEFT ALONE fixture earlier in
# this file (`live-one`, claims="stop-orders.test.sh") happens to pass regardless because
# LEFT ALONE does not distinguish STILL-LIVE from UNMET; it is not proof `claims_live` saw a
# live process. A background child is not an ancestor and IS matched.
CLAIMS_MARKER="bionic-t1g-claim-marker-$$"
( exec -a "$CLAIMS_MARKER" sleep 30 ) &
CLAIMS_MARKER_PID=$!
so_roster_row "$R13" "claims-live-gone" ".bionic/docs/record/never-clg.md" "" \
  "claims-live-gone@session-6c85684c" "$CLAIMS_MARKER"
plant_live "$R13TR" fresh
run_orders_cfg "$R13" stopped claims-live-gone
expect_status "a claimed-process STILL-LIVE row stays refused even panel-gone, exit 2" 2 "$ST"
expect_contains "…naming the claim, not the panel" "claimed process pattern" "$OUT$ERR"
expect_absent "…and acks nothing" "|name=claims-live-gone|" "$(s13_ledger)"
kill "$CLAIMS_MARKER_PID" 2>/dev/null
wait "$CLAIMS_MARKER_PID" 2>/dev/null

# ---------- standdown never merges the tree a panel-gone override closed (T1f unchanged) ----------
#
# T1f's rule stands: `_land_row_tree` merges only MET/WAIVED. An acked STILL-LIVE-and-gone
# row's tree stands, reported the same way an abandoned UNMET tree does — no new lease path
# was added by this fix, only a new way to reach the same ack.
R14="$(make_repo standdown-stilllive-stands)"
echo seed > "$R14/README.md"
git -C "$R14" add README.md >/dev/null 2>&1
git -C "$R14" commit -qm seed >/dev/null 2>&1
git -C "$R14" checkout -qb integration
git -C "$R14" worktree add -q -b still-working "$R14/.worktrees/still-working" >/dev/null 2>&1
echo partial > "$R14/.worktrees/still-working/partial14.txt"
git -C "$R14/.worktrees/still-working" add -A >/dev/null 2>&1
git -C "$R14/.worktrees/still-working" commit -qm "still-working WIP" >/dev/null 2>&1

R14SLUG=$(printf '%s' "$R14" | sed 's/[^a-zA-Z0-9]/-/g')
mkdir -p "$R8CFG/projects/$R14SLUG"
R14TR="$R8CFG/projects/$R14SLUG/$SID.jsonl"
R14PROG="$R14/.bionic/docs/record/progress14.md"
echo working > "$R14PROG"
so_roster_row "$R14" "still-working" ".bionic/docs/record/never-sw.md" "" \
  "still-working@session-6c85684c" "" "$R14PROG" "10 minutes"
plant_live "$R14TR" fresh

run_orders_cfg "$R14" stopped still-working
expect_status "stopped closes the STILL-LIVE-and-gone row (V2-1 precondition)" 0 "$ST"
expect_contains "…as abandoned" "reason abandoned" "$OUT"

run_orders_cfg "$R14" standdown
expect_status "standdown over the closed row with a tree exits clean" 0 "$ST"
if [ "$(git -C "$R14" rev-list --count "HEAD..still-working" 2>/dev/null)" = "1" ]; then
  ok "the closed branch is NOT merged: it is still ahead of the main checkout"
else
  no "the closed branch is NOT merged: it is still ahead of the main checkout" \
    "HEAD..still-working = $(git -C "$R14" rev-list --count "HEAD..still-working" 2>&1)"
fi
expect_absent "…and no LANDED line claims it" "LANDED branch=still-working" "$OUT"
if [ -d "$R14/.worktrees/still-working" ] && [ -f "$R14/.worktrees/still-working/partial14.txt" ]; then
  ok "…its tree stands, the partial work still in it"
else
  no "…its tree stands, the partial work still in it"
fi

finish
