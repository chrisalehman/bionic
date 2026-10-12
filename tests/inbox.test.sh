#!/bin/bash
# tests/inbox.test.sh — a ruling reaches the writer it is for (epic-23 wave-33 T10; REQ-1, AC-1.1 to
# AC-1.4; spec D1, the Eval design rows §PUSH, §STATE, §SCOPE, §GUARD).
#
# A ruling is the orchestrator's binding instruction to one live writer, recorded with
# `session-poker.sh rule <writer> '<text>'` as `ruling/v1` lines on the session's roster. It is
# PUSHED for speed: hooks/ruling-push.sh, a PostToolUse hook on every tool, maps the payload's
# `agent_id` to the roster name and hands an unpushed ruling of that name to the writer's model as
# `additionalContext` headed `bionic ruling`, once. It is GUARDED for truth: a push is visible but
# not necessarily obeyed (record/wave-33-workhorse/P1-additional-context.md), so the writer's commit
# (hooks/bash-walls.sh) and its `spawn-worktree.sh ready` (lib/line.sh) refuse while a ruling of that
# writer is unread, print it, and mark it shown, so the retry passes. `ruling-ack <id>` marks it
# shown from the writer's side; `rulings <writer>` is the orchestrator's read of the state.
#
# SECTIONS. §PUSH (AC-1.1): the push carries the ruling once, on one call, whichever of several
# concurrent calls completes first; the orchestrator's own calls carry nothing and consume nothing.
# §STATE (AC-1.2): `rulings` reads unread, pushed=, shown= off the roster. §SCOPE (AC-1.3): another
# writer's call carries nothing; a closed or unknown row is refused at once with the reason.
# §GUARD (AC-1.4): the commit and `ready`, refused with the ruling unread and passing once shown.
#
# HERMETIC. One model world (tests/lib/world.sh): a throwaway repository with a bound plan, a roster
# with rows wx-T1 and wx-T2, two row trees, a planted machine and clock, its own gate store. Every
# hook and verb is the tree's own file, run under the world's session id with an empty plugin
# registry, a config dir under the world, and no real ~/.claude read or written.
#
# FIXTURE FIDELITY. The hook payloads are the PostToolUse and PreToolUse|Bash shapes measured in
# record/wave-33-workhorse/P1-additional-context.md (a subagent call carries a top-level `agent_id`;
# the orchestrator's carries none). The roster rows come from the production writer (`roster_row`,
# through tests/lib/roster-row.sh); the closed row is closed the way the fleet closes one, an ack in
# the sweeper ledger after its launch. Nothing the criteria depend on is pinned away: the hook maps
# the id through the roster itself, and `ready` runs the real line on the world's planted machine.
#
# ANTI-VACUITY. Every empty readback sits beside a positive on the same extractor in the same world:
# (p2)/(p4) beside (p3), (c1)'s absences beside wx-T1's carry, (c2)'s absent line beside the live
# writer's, (g5) beside (g3). The commit control (g0) proves the world admits a commit at all, so
# (g3)'s refusal is the ruling's and (g5)'s pass is the shown mark's.
#
# Usage: bash tests/inbox.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"

command -v jq >/dev/null 2>&1 || { echo "inbox: jq absent — suite cannot run"; exit 1; }

POKER="$BIONIC_HOOKS_DIR/session-poker.sh"
PUSH="$BIONIC_HOOKS_DIR/ruling-push.sh"
WALLS="$BIONIC_HOOKS_DIR/bash-walls.sh"
HOOKS_JSON="$BIONIC_HOOKS_DIR/hooks.json"
SPAWN="$BIONIC_SCRIPTS_DIR/payload/scripts/spawn-worktree.sh"

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0

. "$(dirname "$0")/lib/world.sh"
. "${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/roster.sh"
. "$(dirname "$0")/lib/roster-row.sh"

export BIONIC_PLUGINS_DIR="$WORLD_ROOT/no-plugins"
mkdir -p "$BIONIC_PLUGINS_DIR"
export CLAUDE_CONFIG_DIR="$WORLD_ROOT/home"
mkdir -p "$CLAUDE_CONFIG_DIR/bionic"; printf '80\n' > "$CLAUDE_CONFIG_DIR/bionic/share"
export CLAUDE_CODE_SESSION_ID="$WORLD_SID" BIONIC_GATE_POLL=0.1 BIONIC_LINE_POLL=0.2
world_machine 8 8192 40 0.5
world_clock 1000
world_cost a.test.sh 5 0.5 5; world_cost b.test.sh 5 0.5 5

# ---------------------------------------------------------------------------- helpers
iso_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# A world whose plan the commit gate admits (the shape tests/landing-line.test.sh's `ll_world` plants),
# its two rows' launch lines on the roster with ids and the suite they land on, and a third writer,
# wx-T3, whose row is closed: acked in the sweeper ledger after its launch.
in_world() {  # -> the world root
  local r p
  r="$(world_repo)" || return 1
  [ -n "$r" ] && [ "$(git -C "$r" rev-parse --show-toplevel 2>/dev/null)" = "$r" ] || return 1
  p="$r/.bionic/docs/plans/epic-x/wave-x.plan.md"
  awk '{ print }
    /^working-branch: / { print "canonical_sdlc_version: 14" }
    /^current: 4$/ { print "approved-by: fixture 2026-10-04T00:00Z \"approved\""; print "- Step 4: started"; print "- T1: active"; print "- T2: active" }' \
    "$p" > "$p.n" && mv "$p.n" "$p"
  for t in T1 T2; do
    printf '%s|row=%s|lands_on=a.test.sh\n' \
      "$(roster_row_fixture status=intended session="$WORLD_SID" name="wx-$t" agent_id="b00$t" plan="$p")" "$t" \
      >> "$r/.bionic/tmp/roster-$WORLD_SID.state"
  done
  roster_row_fixture status=identified session="$WORLD_SID" name=wx-T3 agent_id=a00T3 plan="$p" \
    >> "$r/.bionic/tmp/roster-$WORLD_SID.state"
  printf 'sweeper-ledger/v1|event=ack|name=wx-T3|at=%s\n' "$(iso_now)" \
    >> "$r/.bionic/tmp/sweeper-$WORLD_SID.state"
  printf '%s' "$r"
}
in_roster() { printf '%s/.bionic/tmp/roster-%s.state' "$1" "$WORLD_SID"; }

# The orchestrator's verbs, from the world's root -> IN_OUT (both streams), IN_RC.
in_poker() {  # <root> <verb> [args...]
  local r="$1"; shift
  IN_OUT="$( cd "$r" && bash "$POKER" "$@" 2>&1 )"; IN_RC=$?
}
# The id a `rule` call printed (`poker: ruling <id> recorded for <writer> …`).
in_rid() { printf '%s\n' "$1" | sed -n 's/^poker: ruling \([^ ]*\) recorded for .*/\1/p' | head -1; }
# One line of `rulings <writer>` for <id>.
in_state() {  # <root> <writer> <id>
  ( cd "$1" && bash "$POKER" rulings "$2" 2>&1 ) | /usr/bin/grep -F "ruling $3 " | head -1
}

# The PostToolUse payload of one tool call -> its stdout. agent_id `-` is the orchestrator's own call.
in_payload() {  # <root> <agent_id|-> <tool_use_id>
  jq -nc --arg s "$WORLD_SID" --arg c "$1" --arg a "$2" --arg u "$3" \
    '{session_id:$s, cwd:$c, hook_event_name:"PostToolUse", tool_name:"Read",
      tool_input:{file_path:"/dev/null"}, tool_response:{}, tool_use_id:$u}
     + (if $a == "-" then {} else {agent_id:$a, agent_type:"bionic:implementor"} end)'
}
# IN_RC is the hook's own: the payload is a here-string, not a pipe, so a fast path that never reads
# its stdin cannot fail the writer of the payload with SIGPIPE under pipefail.
in_push() {  # <root> <agent_id|-> <tool_use_id> -> IN_OUT (stdout), IN_RC
  local p
  p="$(in_payload "$1" "$2" "$3")"
  IN_OUT="$( env CLAUDE_PROJECT_DIR="$1" bash "$PUSH" 2>/dev/null <<< "$p" )"; IN_RC=$?
}
in_ctx() { printf '%s' "$1" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null; }

# The PreToolUse|Bash walls on <command> from <agent_id> -> IN_OUT (both streams), IN_RC.
in_walls() {  # <root> <agent_id> <command>
  local p
  p="$(jq -nc --arg s "$WORLD_SID" --arg c "$1" --arg a "$2" --arg k "$3" \
    '{session_id:$s, cwd:$c, hook_event_name:"PreToolUse", tool_name:"Bash",
      tool_input:{command:$k}, tool_use_id:"toolu_inbox_walls", agent_id:$a, agent_type:"bionic:implementor"}')"
  IN_OUT="$( printf '%s' "$p" | env CLAUDE_PROJECT_DIR="" bash "$WALLS" 2>&1 )"; IN_RC=$?
}

# `ready` from a row's own tree -> IN_OUT (both streams), IN_RC.
in_ready() {  # <root> <row>
  IN_OUT="$( cd "$1/.worktrees/$2" && bash "$SPAWN" ready 2>&1 )"; IN_RC=$?
}

W="$(in_world)"
[ -n "$W" ] && [ -d "$W/.worktrees/T1" ] || { echo "inbox: the world could not be built — suite refuses to run"; exit 1; }
ROSTER="$(in_roster "$W")"

# ─────────────────────────────────────────────────────────────────────────────
section "§PUSH: a ruling rides the writer's next tool result, exactly once (AC-1.1)"

expect_contains "(p0) hooks.json registers ruling-push.sh on PostToolUse for every tool (matcher *)" \
  "ruling-push.sh" \
  "$(jq -r '.hooks.PostToolUse[]? | select(.matcher == "*") | .hooks[]?.command' "$HOOKS_JSON" 2>/dev/null)"

in_poker "$W" rule wx-T1 'use tabs, not commas, in the ledger'
expect_eq "(p1) rule records a ruling for a live writer (exit 0)" "0" "$IN_RC"
P_ID="$(in_rid "$IN_OUT")"
expect_nonempty "(p1) …and prints its id" "$P_ID"

in_push "$W" - toolu_main_1
expect_eq "(p2) the orchestrator's own call: the hook exits 0" "0" "$IN_RC"
P_MAIN="$(in_ctx "$IN_OUT")"
in_push "$W" b00T1 toolu_p_1
P_CTX1="$(in_ctx "$IN_OUT")"
expect_eq "(p3) the writer's call: the hook exits 0" "0" "$IN_RC"
expect_contains "(p3) …and its result carries the ruling, headed bionic ruling, binding" \
  "bionic ruling $P_ID from the orchestrator (binding): use tabs, not commas, in the ledger" "$P_CTX1"
expect_contains "(p3) …with the acknowledgement call" "hooks/session-poker.sh ruling-ack $P_ID" "$P_CTX1"
expect_eq "(p3) …on the PostToolUse channel" "PostToolUse" \
  "$(printf '%s' "$IN_OUT" | jq -r '.hookSpecificOutput.hookEventName // empty' 2>/dev/null)"
expect_eq "(p2) the orchestrator's call before it carried nothing and consumed nothing" "" "$P_MAIN"
in_push "$W" b00T1 toolu_p_2
P_CTX2="$(in_ctx "$IN_OUT")"
expect_eq "(p4) the writer's next call exits 0" "0" "$IN_RC"
expect_eq "(p4) …and carries none: the ruling was shown once" "" "$P_CTX2"
expect_eq "(p4) across both calls the ruling appears exactly once" "1" \
  "$(printf '%s\n%s\n' "$P_CTX1" "$P_CTX2" | /usr/bin/grep -c "bionic ruling $P_ID ")"

# Concurrent calls (a writer's parallel tool calls run their PostToolUse hooks at once): one carries it.
in_poker "$W" rule wx-T1 'stop after the parser lands'
P_ID2="$(in_rid "$IN_OUT")"
expect_nonempty "(p5) a second ruling is recorded" "$P_ID2"
for i in 1 2 3 4 5 6; do
  ( in_payload "$W" b00T1 "toolu_par_$i" | env CLAUDE_PROJECT_DIR="$W" bash "$PUSH" > "$WORLD_ROOT/par.$i" 2>/dev/null ) &
done
wait
P_PAR="$(cat "$WORLD_ROOT"/par.* 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)"
expect_contains "(p5) six concurrent calls: the ruling rides one of them" "bionic ruling $P_ID2 " "$P_PAR"
expect_eq "(p5) …and exactly one" "1" "$(printf '%s\n' "$P_PAR" | /usr/bin/grep -c "bionic ruling $P_ID2 ")"

# ─────────────────────────────────────────────────────────────────────────────
section "§STATE: the roster records delivery; the orchestrator reads it without asking (AC-1.2)"

in_poker "$W" rule wx-T2 'rebase onto the wave head first'
S_ID="$(in_rid "$IN_OUT")"
expect_nonempty "(s0) a ruling for wx-T2 is recorded" "$S_ID"
S_LINE0="$(in_state "$W" wx-T2 "$S_ID")"
expect_contains "(s1) before any push, rulings reads it unread" "unread" "$S_LINE0"
expect_absent "(s1) …and not shown" "shown=" "$S_LINE0"
expect_contains "(s1) …with its text" "rebase onto the wave head first" "$S_LINE0"
in_push "$W" b00T2 toolu_s_1
expect_contains "(s2) pushed: the push carried it" "bionic ruling $S_ID " "$(in_ctx "$IN_OUT")"
S_LINE1="$(in_state "$W" wx-T2 "$S_ID")"
expect_regex "(s2) …rulings reads pushed=<epoch>" "pushed=[0-9]+" "$S_LINE1"
expect_contains "(s2) …and still unread: a push is seen, not acknowledged" "unread" "$S_LINE1"
( cd "$W/.worktrees/T2" && bash "$POKER" ruling-ack "$S_ID" ) >/dev/null 2>&1
S_ACK_RC=$?
expect_eq "(s3) the writer acknowledges from its own tree (exit 0)" "0" "$S_ACK_RC"
S_LINE2="$(in_state "$W" wx-T2 "$S_ID")"
expect_regex "(s3) …rulings reads shown=<epoch>" "shown=[0-9]+" "$S_LINE2"
expect_absent "(s3) …and no longer unread" "unread" "$S_LINE2"
expect_true "(s4) the delivery is on the writer's roster, as ruling/v1 lines" \
  /usr/bin/grep -q "^ruling/v1|id=${S_ID}|" "$ROSTER"
in_poker "$W" ruling-ack r-no-such-ruling
expect_eq "(s5) ruling-ack of an id no ruling carries is refused (exit 2)" "2" "$IN_RC"

# ─────────────────────────────────────────────────────────────────────────────
section "§SCOPE: only the named writer sees it; a closed row is refused at once (AC-1.3)"

in_poker "$W" rule wx-T1 'only wx-T1 reads this'
C_ID="$(in_rid "$IN_OUT")"
expect_nonempty "(c0) a ruling for wx-T1 is recorded" "$C_ID"
in_push "$W" b00T2 toolu_c_b
C_B="$(in_ctx "$IN_OUT")"
in_push "$W" a-nested-delegate toolu_c_z
C_Z="$(in_ctx "$IN_OUT")"
in_push "$W" b00T1 toolu_c_a
C_A="$(in_ctx "$IN_OUT")"
expect_contains "(c1) wx-T1's call carries it" "bionic ruling $C_ID " "$C_A"
expect_absent "(c1) …the second live writer's call did not" "bionic ruling $C_ID " "$C_B"
expect_absent "(c1) …nor an unrostered agent's (a writer's own delegate)" "bionic ruling $C_ID " "$C_Z"

in_poker "$W" rule wx-T3 'too late for this one'
expect_eq "(c2) a ruling for a closed row is refused (exit 2)" "2" "$IN_RC"
expect_contains "(c2) …naming the row" "wx-T3" "$IN_OUT"
expect_contains "(c2) …and why" "closed" "$IN_OUT"
expect_true "(c2) the roster holds ruling lines for the live writer" /usr/bin/grep -q "|writer=wx-T1|" "$ROSTER"
expect_false "(c2) …and none for the closed row" /usr/bin/grep -q "|writer=wx-T3|" "$ROSTER"
in_poker "$W" rule wx-T9 'nobody'
expect_eq "(c3) a ruling for a name no row carries is refused (exit 2)" "2" "$IN_RC"
expect_contains "(c3) …naming it" "wx-T9" "$IN_OUT"
in_poker "$W" rule wx-T1 '   '
expect_eq "(c4) a ruling with no text is a usage error (exit 2)" "2" "$IN_RC"

# ─────────────────────────────────────────────────────────────────────────────
section "§ACK: a ruling acknowledged before its push is never pushed; the flag follows (T31)"

# The walk's sequence (record/wave-33-workhorse/walk.md §2, §8): record, ruling-ack, the writer's
# next call. Every ruling before this section is pushed, so the flag reads only these two. The flag
# is up while either is unacknowledged ((k1), (k2) up beside (k3) down, one extractor) and the push
# carries nothing for an acknowledged one ((k4) beside (k5), a fresh ruling the same call shape carries).
FLAG="$W/.bionic/tmp/ruling-pending-$WORLD_SID.state"
in_poker "$W" rule wx-T1 'acknowledged before any push'
K_ID1="$(in_rid "$IN_OUT")"
in_poker "$W" rule wx-T2 'acknowledged too'
K_ID2="$(in_rid "$IN_OUT")"
expect_nonempty "(k0) two rulings are recorded, one per writer" "$K_ID1$K_ID2"
expect_true "(k1) the pending flag is up once they are recorded" test -e "$FLAG"
( cd "$W/.worktrees/T1" && bash "$POKER" ruling-ack "$K_ID1" ) >/dev/null 2>&1
expect_true "(k2) wx-T1's acknowledged; wx-T2's is not: the flag stays up" test -e "$FLAG"
( cd "$W/.worktrees/T2" && bash "$POKER" ruling-ack "$K_ID2" ) >/dev/null 2>&1
expect_false "(k3) both acknowledged, none unread for any writer: the flag is down" test -e "$FLAG"
in_push "$W" b00T1 toolu_k_1
K_CTX="$(in_ctx "$IN_OUT")"
expect_eq "(k4) wx-T1's next call exits 0" "0" "$IN_RC"
expect_absent "(k4) …and carries no acknowledged ruling" "bionic ruling $K_ID1 " "$K_CTX"
expect_absent "(k4) …the push claimed nothing for it" "pushed=" "$(in_state "$W" wx-T1 "$K_ID1")"
expect_false "(k4) …and the flag is still down" test -e "$FLAG"
in_poker "$W" rule wx-T1 'a fresh one rides the next call'
K_ID3="$(in_rid "$IN_OUT")"
in_push "$W" b00T1 toolu_k_2
expect_contains "(k5) control: a fresh ruling, the same call shape, is carried" "bionic ruling $K_ID3 " "$(in_ctx "$IN_OUT")"
expect_false "(k5) …and once it is pushed the flag is down" test -e "$FLAG"
( cd "$W/.worktrees/T1" && bash "$POKER" ruling-ack "$K_ID3" ) >/dev/null 2>&1

# ─────────────────────────────────────────────────────────────────────────────
section "§GUARD: no commit and no ready against an unread ruling (AC-1.4)"

# The control: a writer with nothing unread commits in this world.
in_walls "$W" b00T2 'git commit -m "T2: work"'
expect_eq "(g0) control: wx-T2, nothing unread, commits (exit 0)" "0" "$IN_RC"

in_poker "$W" rule wx-T1 'rename the flag before you commit'
G_ID="$(in_rid "$IN_OUT")"
expect_nonempty "(g1) a ruling for wx-T1 is recorded" "$G_ID"
in_push "$W" b00T1 toolu_g_1
expect_contains "(g1) …and pushed (seen, not acknowledged)" "bionic ruling $G_ID " "$(in_ctx "$IN_OUT")"
in_walls "$W" b00T1 'ls -la'
expect_eq "(g2) a call that is no commit is not held (exit 0)" "0" "$IN_RC"
in_walls "$W" b00T1 'git add -A && git commit -m "T1: work"'
G_OUT1="$IN_OUT"
expect_eq "(g3) wx-T1's commit with the ruling unread is refused (exit 2)" "2" "$IN_RC"
expect_contains "(g3) …carrying the ruling" "rename the flag before you commit" "$G_OUT1"
expect_contains "(g3) …and the acknowledgement call" "ruling-ack $G_ID" "$G_OUT1"
expect_regex "(g4) the refusal marked it shown" "shown=[0-9]+" "$(in_state "$W" wx-T1 "$G_ID")"
in_walls "$W" b00T1 'git add -A && git commit -m "T1: work"'
expect_eq "(g5) the same commit once shown passes (exit 0)" "0" "$IN_RC"
expect_absent "(g5) …and says nothing of the ruling" "rename the flag before you commit" "$IN_OUT"

in_poker "$W" rule wx-T1 'land only after the rename'
R_ID="$(in_rid "$IN_OUT")"
expect_nonempty "(g6) a ruling for wx-T1 is recorded" "$R_ID"
REC="$W/.bionic/docs/record/wave-x/landing-proofs.log"
in_ready "$W" T1
expect_eq "(g6) wx-T1's ready with the ruling unread is refused (exit 2)" "2" "$IN_RC"
expect_contains "(g6) …saying why" "REFUSED reason=ruling-unread" "$IN_OUT"
expect_contains "(g6) …carrying the ruling" "land only after the rename" "$IN_OUT"
expect_false "(g6) …and nothing entered the line" test -e "$REC"
expect_regex "(g7) the refusal marked it shown" "shown=[0-9]+" "$(in_state "$W" wx-T1 "$R_ID")"
in_ready "$W" T1
expect_eq "(g8) the same ready once shown lands (exit 0)" "0" "$IN_RC"
expect_contains "(g8) …LANDED" "LANDED T1 " "$IN_OUT"

finish
