#!/bin/bash
# tests/permission-effects.test.sh — the effects reader judged THROUGH THE HOOK (epic-23
# wave-25-never-paused T16; Step-6 review B1, B2).
#
# WHAT IT OWNS. The places where payload/scripts/lib/cmd-class.sh `cmd_effects` used to be
# confident and wrong, driven end to end: a real PermissionRequest payload into
# hooks/permission-answer.sh, on a fixture with a real symlink, asking for the decision. Every
# row here is a command whose write or delete lands outside the asker's grant at run time while
# a reader that decided the place itself said it was inside.
#
# WHY A SUITE OF ITS OWN. grant.test.sh §G5 proves `grant_resolve` follows a link before it
# folds `..`, by calling it directly; it never went through the reader, which folded `..` as
# text before the hook ever saw the path (B1), and resolved a link the same command makes
# before it existed (B2). Only a row that goes payload -> reader -> resolver -> grant catches
# either, so these rows drive the hook and nothing else.
#
# HERMETIC. One mktemp sandbox holds the project (a git repository on the run's working branch
# with a bound plan, a roster and a workspace record), the asker's tree inside it, and a
# directory OUTSIDE every root the grant composes. HOME is a scratch directory in the sandbox.
# No command under test is ever run: the hook only reads it.
#
# FIXTURE FIDELITY (per .claude/rules/test-harness.md). The payload is the shape
# tests/permission-answer.test.sh drives (record/wave-25-never-paused/verify-first-permission-hook.md
# E2, E3, E7), with the asker a writer teammate whose tree is recorded. The symlink is real
# (`ln -s`), so the hook's resolver walks the filesystem as it does live; the fixture pins
# nothing the rows depend on except the link itself and where it points.
#
# ANTI-VACUITY (per .claude/rules/test-harness.md). Every deny sits beside an allow on the same
# fixture, by the same asker, through the same reader feature: a `..` under a real directory, a
# cd and a relative `..`, and `mkdir -p d && echo x > d/f`, which must stay readable.
#
# Usage: bash tests/permission-effects.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"
. "$(dirname "$0")/lib/roster-row.sh"

HOOK="${PA_TEST_HOOK:-$BIONIC_HOOKS_DIR/permission-answer.sh}"

SANDBOX="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/permission-effects-test.XXXXXX")" && pwd -P)"
cleanup() { chmod -R u+rwX "$SANDBOX" 2>/dev/null; rm -rf "$SANDBOX"; }
trap cleanup EXIT

HOME_FX="$SANDBOX/home"
mkdir -p "$HOME_FX" "$SANDBOX/plugins"
SID="pe0ffect-2222-3333-4444-555555555555"
BRANCH="wave/99-fx"
PLAN_BASE="wave-99-fx"

# ---------- fixture ----------

P="$SANDBOX/proj"
TREE="$P/.worktrees/25-T1"
OUT="$SANDBOX/outside"
mkdir -p "$P/hooks" "$P/.bionic/tmp" "$P/.bionic/docs/plans/epic-99" "$P/.bionic/docs/specs/epic-99" \
         "$P/.bionic/docs/record/$PLAN_BASE" "$TREE/a/sub" "$TREE/sub" "$OUT/sub" "$SANDBOX/proj-scratch"
git -C "$P" init -q 2>/dev/null
git -C "$P" checkout -q -b "$BRANCH" 2>/dev/null
git -C "$P" -c user.email=fx@example.invalid -c user.name=fx commit -q --allow-empty -m init 2>/dev/null
PLAN="$P/.bionic/docs/plans/epic-99/$PLAN_BASE.plan.md"
cat > "$PLAN" <<PEPLAN
---
canonical_sdlc_version: 14
intent: build
rigor: audited
scale: wave
working-branch: $BRANCH
spec: specs/epic-99/$PLAN_BASE.spec.md
requirements: specs/epic-99/$PLAN_BASE.requirements.md
---

# fixture plan

## SDLC State

integration-branch: main
intent: build
rigor: audited
scale: wave
current: 4

- Step 4: tasks in flight
PEPLAN
: > "$P/.bionic/docs/specs/epic-99/$PLAN_BASE.spec.md"
: > "$P/.bionic/docs/specs/epic-99/$PLAN_BASE.requirements.md"
printf 'plan=%s\n' "$PLAN" > "$P/.bionic/tmp/engaged-$SID.state"
: > "$P/hooks/x.sh"
: > "$TREE/a/f"

# The asker: a writer teammate whose tree is recorded (the T1 interface line, verbatim).
AID="aw99-T1-0974313b7a6b74f2"
roster_header > "$P/.bionic/tmp/roster-$SID.state"
roster_row_fixture status=confirmed session="$SID" name=w99-T1 agent_id="$AID" \
  subagent_type=bionic:senior-implementor deliverable="$P/.bionic/docs/record/$PLAN_BASE/T1.md" \
  >> "$P/.bionic/tmp/roster-$SID.state"
printf 'workspace/v1|session=%s|name=%s|path=%s|branch=wt/%s|base=abc1234|plan=none|at=2026-10-03T23:00:00Z\n' \
  "$SID" w99-T1 "$TREE" w99-T1 >> "$P/.bionic/tmp/workspaces-$SID.state"

# THE LINK: inside the tree, pointing OUTSIDE every root. tree/link/.. is $OUT to the kernel.
ln -s "$OUT/sub" "$TREE/link"

# payload <command> -> the PermissionRequest payload for the teammate, cwd = its tree.
payload() {
  local ti
  ti="$(jq -n --arg c "$1" '{command:$c, description:"a fixture command"}')"
  jq -n --arg s "$SID" --arg c "$TREE" --arg sc "$SANDBOX/proj-scratch" --argjson ti "$ti" \
        --arg aid "$AID" --arg tp "$HOME_FX/.claude/projects/fx/$SID.jsonl" '
    {session_id:$s, transcript_path:$tp, cwd:$c, scratchpad_dir:$sc,
     permission_mode:"bypassPermissions", hook_event_name:"PermissionRequest",
     tool_name:"Bash", tool_input:$ti, permission_suggestions:[],
     agent_id:$aid, agent_type:"bionic:senior-implementor"}'
}

# drive <command> -> OUT_JSON; the hook runs as the platform runs it, from the project.
OUT_JSON=""
drive() {
  OUT_JSON="$(cd "$P" && payload "$1" | env HOME="$HOME_FX" CLAUDE_PROJECT_DIR="$P" \
      BIONIC_PLUGINS_DIR="$SANDBOX/plugins" CLAUDE_CODE_SESSION_ID="$SID" \
      bash "$HOOK" 2>/dev/null)"
}
behavior() { printf '%s' "$OUT_JSON" | jq -r '.hookSpecificOutput.decision.behavior // "none"' 2>/dev/null || printf 'bad'; }
message() { printf '%s' "$OUT_JSON" | jq -r '.hookSpecificOutput.decision.message // ""' 2>/dev/null; }

# answer_is <allow|deny> <label> <command>
answer_is() {
  drive "$3"
  expect_eq "$2 [${3//$SANDBOX/<sb>}]" "$1" "$(behavior)"
}

# ══════════════════════════════════════════════════════════════════════════════════════
section "§E0 the fixture: the link is real and the kernel puts link/.. outside the tree"

expect_true "E0.1 tree/link is a symlink" test -L "$TREE/link"
expect_eq "E0.2 the kernel resolves tree/link/.. to the outside directory" "$OUT" "$(cd -P "$TREE/link/.." && pwd -P)"
answer_is allow "E0.3 control: the teammate writing inside its tree is allowed" "touch $TREE/ok.txt"
answer_is deny "E0.4 control: the teammate writing outside is denied" "touch $OUT/x.txt"

# ══════════════════════════════════════════════════════════════════════════════════════
section "§E1 B1: a \`..\` after a link is decided by the resolver, not folded by the reader"

answer_is deny "E1.1 a write to tree/link/../escape lands outside: deny" "echo x > $TREE/link/../escape"
answer_is deny "E1.2 a cd into the link, then ../victim: deny" "cd $TREE/link && rm -rf ../victim"
answer_is deny "E1.3 a relative link/../victim from the tree: deny" "rm -rf link/../victim"
# The paired allows: the same `..` under a real directory stays inside.
answer_is allow "E1.4 a write to tree/sub/../ok stays inside: allow" "echo x > $TREE/sub/../ok.txt"
answer_is allow "E1.5 a cd into a real directory, then ../a/f: allow" "cd $TREE/sub && rm -f ../a/f"
answer_is allow "E1.6 a relative sub/../ok from the tree: allow" "touch sub/../ok2.txt"

# ══════════════════════════════════════════════════════════════════════════════════════
section "§E2 B2: a link the command makes, or a cp or mv that may carry one, is not resolved early"

answer_is deny "E2.1 ln -s outside, then rm beneath the new link: deny" "ln -s $OUT $TREE/nl1 && rm -rf $TREE/nl1/victim"
answer_is deny "E2.2 ln -s outside as a relative link, then write through it: deny" "ln -s $OUT nl2 && echo x > nl2/f"
answer_is deny "E2.3 ln -s outside, cd into it, then rm: deny" "ln -s $OUT $TREE/nl3 && cd $TREE/nl3 && rm -rf victim"
answer_is deny "E2.4 a hard link to main's hook, then a write to it: deny" "ln $P/hooks/x.sh $TREE/h && echo y > $TREE/h"
drive "ln -s $OUT $TREE/nl4"
expect_contains "E2.5 the denial says why" "a link redirects every later path" "$(message)"
answer_is deny "E2.6 cp -R, then rm beneath the copy: deny" "cp -R $TREE/a $TREE/b && rm -rf $TREE/b/sub"
answer_is deny "E2.7 mv, then rm beneath the destination: deny" "mv $TREE/a $TREE/b && rm -rf $TREE/b/sub"
answer_is deny "E2.8 mv, then a write AT the destination: deny" "mv $TREE/a $TREE/b && echo x > $TREE/b"
# The paired allows: a directory mkdir made holds no link, and a copy with nothing after it.
answer_is allow "E2.9 mkdir -p d && echo x > d/f stays allowed" "mkdir -p $TREE/d && echo x > $TREE/d/f"
answer_is allow "E2.10 a relative mkdir -p d && echo x > d/f stays allowed" "mkdir -p d2 && echo x > d2/f"
answer_is allow "E2.11 a cp with no later path beneath it is allowed" "cp $TREE/a/f $TREE/c.txt"

finish
