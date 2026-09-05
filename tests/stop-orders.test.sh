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
  # The initial branch is NAMED here rather than inherited from the machine's
  # init.defaultBranch: `land` refuses to merge into a protected branch (F1), so
  # a fixture whose branch depends on the operator's git config would land on
  # one machine and refuse on the next.
  git -C "$repo" symbolic-ref HEAD refs/heads/wave/fixture 2>/dev/null
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
echo "=== Section 3b: standdown on an ADOPTED WAIVED row survives /clear (S17, AC-12) ==="
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
printf '# bionic session roster — schema roster-state/v1 — machine-local, safe to delete\n' \
  > "$ADOPT3B_ROSTER"
printf 'roster-state/v1|status=identified|session=%s|name=adopted-waived-row|agent_id=%s|launched_at=%s|subagent_type=implementor|model=opus|deliverable=|source=declared|duration=|progress=|claims=|cadence=10 minutes|absent=|waiver=%s|tool_use_id=toolu_01S17FIX\n' \
  "$ADOPT3B_PRED" "$ADOPT3B_ID" "2026-08-05T00:00:00Z" \
  "probe only — a throwaway read-only agent for the standdown/adopt walk" \
  >> "$ADOPT3B_ROSTER"

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
echo ""
echo "=== Section 6: standdown LANDS the trees it stands down (AC-28, C1) ==="
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
  roster_row "$R8" "$n" ".bionic/docs/record/$n.md" "" "$n@session-6c85684c"
done
roster_row "$R8" "still-working" ".bionic/docs/record/nothing.md" "" "still-working@session-6c85684c"

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
roster_row "$R9" "land-p" ".bionic/docs/record/land-p.md" "" "land-p@session-6c85684c"

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
echo ""
echo "=== Section 7: standdown reports LIVENESS beside a held row, and still writes nothing (S6) ==="
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

# The recorded ListAgents answer, in the harness's real shape (bodies byte-verbatim in
# tests/live-agents.test.sh; the separator is U+00B7 and `[8895ce]` is the ref suffix the
# reader strips). FRESH because the answer postdates the last user prompt.
plant_live() {  # <transcript> <fresh|stale> <name>...
  local tr="$1" freshness="$2"; shift 2
  local body n
  body=$(
    printf 'This session is bionic-fixture [fc3e2d] — the name other sessions use to message it (it is not listed below; a message to it would be a message to yourself).\n\nTeammates (%d):\n' "$#"
    for n in "$@"; do
      printf '  %s [8895ce]  ·  bionic:implementor  ·  running  ·  started 7m ago\n' "$n"
    done
  )
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
roster_row "$R8" "met-row"   ".bionic/docs/record/landed.md"  "" "met-row@session-6c85684c"
roster_row "$R8" "still-at-it" ".bionic/docs/record/nope.md"  "" "still-at-it@session-6c85684c"
roster_row "$R8" "walked-off"  ".bionic/docs/record/nope2.md" "" "walked-off@session-6c85684c"
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
roster_row "$R8" "s.ill-at-it" ".bionic/docs/record/nope3.md" "" "s.ill-at-it@session-6c85684c"
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
echo ""
echo "──────────────────────────────────────────────"
echo "stop-orders.sh: ${PASS}/${TOTAL} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ]
