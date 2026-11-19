#!/bin/bash
# tests/run-seal.test.sh — the seal that vouches for a run's plan and log (payload/scripts/lib/seal.sh),
# and the one resolver of the repository's common git directory it lives in (lib/root.sh git_common_dir).
#
#   §HOME     git_common_dir answers the same directory from the main checkout, a linked worktree, a
#             subdirectory and a path not made yet, and nothing outside a repository; a seal written from
#             a worktree lands in the common directory, never in the tree's own git directory, and a plan
#             reached through a linked directory is the same seal.
#   §SEAL     verify, write and remove driven directly: no seal, clean, and each road of a change named by
#             what and how; a caught change stays caught through an honest write until the run is vouched
#             for; the command a write wraps runs between the check and the new seal; a seal that stands is
#             seen standing, and one out of shape is seen as none.
#   §LOCK     a held lock turns a call away in well under a hook's ten seconds with nothing run; a dead
#             holder's lock is taken over; honest appends racing each other leave the run clean.
#   §CLOSE    a plan moved off a standing seal reads gone; a seal removed before the move leaves none,
#             by the old path too; a removal under a held lock exits 75 and keeps the seal.
#   §PLAN     the write hook seals the plan in its after-arm: an admitted Write, then an admitted Edit,
#             each driven through the before and after arms, leave it clean, and the binding Write's own
#             bind event is sealed by the appender; an Edit seals and does not
#             bind; an Edit denied at the before-arm, or admitted there with its tool never run, leaves the
#             seal as it was; an after-arm whose seal cannot be had still exits 0 and says so. Then the
#             commit gate over a bound run: a plan changed by the shell is refused as changed, the
#             hook's own admitted Write and Edit and its denied Edit are not, and a seal held past
#             the wait refuses the commit to be run again.
#   §BOUND    the bound plan removed, renamed or moved: the commit is refused, the plan named gone.
#   §MARKER   the engaged file removed or made a link lifts no wall (a commit, a push to main), and
#             rewritten to no plan, no plan line or a decoy moves no judging off the bound run.
#   §LOG      the log removed, renamed, emptied, cut, or a close, step, cancel, proof, approval or
#             waiver appended by hand: refused, naming the log gone, shortened or added to.
#   §TOOLS    the same roads by Write and Edit through the write hook, then the commit.
#   §CHANGED  a caught change: the refusal names the log and both replies, the ask it opens is in the log
#             the seal names, and the sitrep lists it, the plan gone too; a plan put back still reads changed.
#   §ACCEPT   accept is taken only on words a session the log bound as sealed typed, then the run is clean
#             and one line names the word and the change. §ABANDON: abandon on typed words ends the run.
#
# FIXTURE FIDELITY. Every world is a real `git init` in a scratch directory, with a real linked worktree
# where one is named; plan and log are real files changed by the shell commands a person would type.
#
# ANTI-VACUITY. Each absence read sits beside a presence read of the same thing in the same world: no seal
# in the tree's git directory beside one in the common directory, nothing run under a held lock beside the
# same command run once the holder is dead, the lock gone beside the lock planted.

set -uo pipefail
. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"
. "${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/seal.sh"

SB="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$SB"' EXIT
export GIT_CEILING_DIRECTORIES="$SB"
M="$SB/main"
mkdir -p "$M/.bionic/docs/plans/e" "$M/.bionic/docs/record/w" "$SB/outside"
git -C "$M" init -q && git -C "$M" -c user.email=t@example.com -c user.name=T commit -q --allow-empty -m seed
git -C "$M" worktree add -q "$SB/tree" 2>/dev/null
P="$M/.bionic/docs/plans/e/w.plan.md"
L="$M/.bionic/docs/record/w/run.log"
HOME_DIR="$M/.git/bionic-seal"
base() {  # the run as it stood when sealed: no seal, a two-line plan, a three-line log
  seal_remove "$P"
  printf '# plan\n| T1 | row |\n' > "$P"
  printf 'run/v1|ev=step|n=1|at=a\nrun/v1|ev=step|n=2|at=b\nrun/v1|ev=step|n=3|at=c\n' > "$L"
  seal_write "$P" "$L"
}
road() {  # <label> <expected line> <shell change> — seal the base run, make the change, verify
  local out rc
  base; eval "$3"
  out="$(seal_verify "$P")"; rc=$?
  expect_eq "$1: verify names it" "$2" "$out"
  expect_status "$1: verify exits 1" 1 "$rc"
}

section "HOME"
expect_eq "the main checkout's common directory is its .git" "$M/.git" "$(git_common_dir "$M")"
expect_eq "a linked worktree answers the same directory" "$M/.git" "$(git_common_dir "$SB/tree")"
expect_eq "a subdirectory answers it" "$M/.git" "$(git_common_dir "$M/.bionic/docs/plans/e")"
expect_eq "a path not made yet answers its nearest directory's" "$M/.git" "$(git_common_dir "$M/no/such/dir")"
out="$(git_common_dir "$SB/outside")"; rc=$?
expect_status "outside any repository it exits 1" 1 "$rc"
expect_empty "and prints nothing" "$out"
TP="$SB/tree/w.plan.md"; printf 'p\n' > "$TP"
seal_write "$TP" "$SB/tree/run.log"; rc=$?
expect_status "a run whose plan sits in a worktree is sealed" 0 "$rc"
expect_eq "its seal is in the common directory" 1 "$(ls "$HOME_DIR"/*.seal 2>/dev/null | wc -l | tr -d ' ')"
expect_eq "and not in the tree's own git directory" "" "$(find "$M/.git/worktrees" -name '*.seal')"
expect_eq "the seal names the plan by its canonical path" "plan=$TP" "$(grep '^plan=' "$HOME_DIR"/*.seal)"
ln -s "$SB/tree" "$SB/link"
expect_eq "the plan reached through a linked directory is the same seal" clean "$(seal_verify "$SB/link/w.plan.md")"
seal_remove "$TP"

section "SEAL"
out="$(seal_verify "$P")"; rc=$?
expect_eq "a run never sealed reads none" none "$out"
expect_status "and exits 2" 2 "$rc"
printf '# plan\n' > "$P"; : > "$L"
seal_write "$P" "$L"; rc=$?
expect_status "the first seal of an open run is written clean" 0 "$rc"
expect_eq "and says no seal stood before it" none "$SEAL_WAS"
S="$(ls "$HOME_DIR"/*.seal)"
expect_eq "the seal is plain text: plan, digest, log, length, digest, state" \
  "seal/v1|plan=$P|plan_sum=$(cksum < "$P")|log=$L|log_len=0|log_sum=$(cksum < /dev/null | cut -d' ' -f1)|state=clean|what=|how=" \
  "$(paste -sd'|' - < "$S")"
base; expect_eq "a sealed run that is unchanged verifies clean" clean "$(seal_verify "$P")"
expect_status "and exits 0" 0 "$(seal_verify "$P" >/dev/null; echo $?)"
road "the plan removed" "changed what=plan how=gone" 'rm "$P"'
road "the plan renamed off its name" "changed what=plan how=gone" 'mv "$P" "${P%.plan.md}.md"'
road "the plan edited in place" "changed what=plan how=changed" 'sed -i.bak "s/row/ROW/" "$P"'
road "a line added to the plan" "changed what=plan how=changed" 'printf "| T9 | x |\n" >> "$P"'
road "the log removed" "changed what=log how=gone" 'rm "$L"'
road "the log emptied" "changed what=log how=shortened" ': > "$L"'
road "the log's last line cut" "changed what=log how=shortened" 'sed -i.bak "\$d" "$L"'
road "a line added to the log by hand" "changed what=log how=added" 'printf "run/v1|ev=abandon|at=d\n" >> "$L"'
road "a byte of the log changed at its length" "changed what=log how=changed" 'sed -i.bak "s/n=2/n=9/" "$L"'
road "the log rewritten longer" "changed what=log how=changed" 'sed -i.bak "s/n=2/n=29/" "$L"'
seal_remove "$P"; rm -f "$L"; seal_write "$P" "$L"
printf 'run/v1|ev=step|n=9|at=z\n' > "$L"
expect_eq "a log made by hand where the seal had none reads added" "changed what=log how=added" "$(seal_verify "$P")"
base; printf 'run/v1|ev=step|n=9|at=d\n' >> "$L"
seal_write "$P" "$L"; rc=$?
expect_status "an honest write over a caught change seals it changed" 1 "$rc"
expect_eq "and says what it caught" "changed what=log how=added" "$SEAL_WAS"
expect_eq "the change stays caught though the files now match the seal" "changed what=log how=added" "$(seal_verify "$P")"
seal_write "$P" "$L" sh -c 'printf "run/v1|ev=hand|at=e\n" >> "$1"' _ "$L"
expect_eq "a later honest append does not clear it" "changed what=log how=added" "$(seal_verify "$P")"
seal_write --vouch run "$P" "$L"; rc=$?
expect_status "the person's word seals the run as it stands" 0 "$rc"
expect_eq "and the run verifies clean" clean "$(seal_verify "$P")"
base; seal_write "$P" "$L" sh -c 'printf "run/v1|ev=hand|at=e\n" >> "$1"' _ "$L"; rc=$?
expect_status "an append wrapped by the write is sealed with it" 0 "$rc"
expect_eq "so the run verifies clean" clean "$(seal_verify "$P")"
expect_eq "and the append happened" 4 "$(wc -l < "$L" | tr -d ' ')"
seal_write "$P" "$L" false
expect_eq "the wrapped command's exit is handed back" 1 "$SEAL_RC"
base; printf '| T2 | new |\n' >> "$P"
seal_write --vouch plan "$P" "$L"; rc=$?
expect_status "a plan write the hook admitted is vouched for" 0 "$rc"
expect_eq "so the run verifies clean" clean "$(seal_verify "$P")"
printf 'run/v1|ev=hand|at=f\n' >> "$L"
seal_write --vouch plan "$P" "$L"
expect_eq "vouching for the plan never vouches for a hand change to the log" "changed what=log how=added" "$(seal_verify "$P")"
rm "$P"; seal_write --vouch run "$P" "$L"; rc=$?
expect_status "a run whose plan is gone cannot be vouched for" 1 "$rc"
expect_eq "it stays changed, plan gone" "changed what=plan how=gone" "$(seal_verify "$P")"
expect_status "a seal that stands is seen standing" 0 "$(seal_stands "$P"; echo $?)"
seal_remove "$P"; rc=$?
expect_status "remove exits 0" 0 "$rc"
expect_eq "and the run reads none" none "$(seal_verify "$P")"
expect_status "and no seal is seen standing" 1 "$(seal_stands "$P"; echo $?)"
base; printf 'not a seal\n' > "$(ls "$HOME_DIR"/w.plan.md.*.seal)"
expect_status "a seal out of shape is seen as none" 1 "$(seal_stands "$P"; echo $?)"
expect_eq "as verify reads it" none "$(seal_verify "$P")"
expect_status "outside any repository there is no home to stand in" 2 "$(seal_stands "$SB/outside/x.plan.md"; echo $?)"
seal_remove "$P"; rm -f "$P"
expect_status "remove of a seal not there exits 0" 0 "$(seal_remove "$P"; echo $?)"
seal_write "$P" "$L"; rc=$?
expect_status "with no seal and no plan nothing is sealed" 2 "$rc"
expect_eq "and no seal file is left" "" "$(ls "$HOME_DIR"/*.seal 2>/dev/null)"
OP="$SB/outside/w.plan.md"; printf 'p\n' > "$OP"
seal_write "$OP" "$SB/outside/run.log" sh -c ': > "$1"' _ "$SB/outside/ran"; rc=$?
expect_status "outside any repository nothing is sealed" 2 "$rc"
expect_true "but the wrapped command still ran" test -f "$SB/outside/ran"
expect_eq "and verify says there is no home" nohome "$(seal_verify "$OP")"

section "LOCK"
base
mkdir "$HOME_DIR/.reap"; printf '%s\n' "$$" > "$HOME_DIR/.reap/pid"
expect_true "a live holder's lock stands" test -d "$HOME_DIR/.reap"
t0=$SECONDS; seal_write "$P" "$L" sh -c ': > "$1"' _ "$SB/held"; rc=$?; waited=$((SECONDS - t0))
expect_status "a write meets a held lock and exits 75" 75 "$rc"
expect_true "it waited, then gave up well under ten seconds ($waited s)" test "$waited" -ge 1 -a "$waited" -le 4
expect_false "and ran nothing" test -f "$SB/held"
out="$(seal_verify "$P")"; rc=$?
expect_eq "verify meets it too and says busy" busy "$out"
expect_status "with exit 75" 75 "$rc"
sh -c 'exit 0' & dead=$!; wait "$dead"
printf '%s\n' "$dead" > "$HOME_DIR/.reap/pid"
seal_write "$P" "$L" sh -c ': > "$1"' _ "$SB/held"; rc=$?
expect_status "a dead holder's lock is taken over" 0 "$rc"
expect_true "and the command ran" test -f "$SB/held"
expect_false "and the lock is let go" test -d "$HOME_DIR/.reap"
base
for i in 1 2 3 4 5 6 7 8; do
  seal_write "$P" "$L" sh -c 'printf "run/v1|ev=hand|n=%s|at=g\n" "$2" >> "$1"' _ "$L" "$i" &
done
wait
expect_eq "eight appends racing each other all landed" 11 "$(wc -l < "$L" | tr -d ' ')"
expect_eq "and the run verifies clean" clean "$(seal_verify "$P")"

section "CLOSE"
# The archive moves a closed run's plan. A seal lifted BEFORE the move leaves nothing to read as a change; a seal left
# standing reads the move as a plan gone. The removal itself holds the lock, and a lock not had keeps the seal.
ARC="$M/.bionic/docs/plans/e/arch"; mkdir -p "$ARC"
base; mv "$P" "$ARC/w.plan.md"
expect_eq "a plan moved off a standing seal reads gone, the false alarm the removal comes before" "changed what=plan how=gone" "$(seal_verify "$P")"
mv "$ARC/w.plan.md" "$P"
base; seal_remove "$P"; rc=$?; mv "$P" "$ARC/w.plan.md"
expect_status "a seal removed, then the plan moved: the removal exits 0" 0 "$rc"
expect_eq "and the run reads none, not changed" none "$(seal_verify "$P")"
expect_eq "with no seal file left in the home" "" "$(ls "$HOME_DIR"/*.seal 2>/dev/null)"
mv "$ARC/w.plan.md" "$P"
base; mv "$P" "$ARC/w.plan.md"; seal_remove "$P"; rc=$?
expect_status "a seal whose plan is already moved is removed by its old path (its directory is there)" 0 "$rc"
expect_eq "and no seal file is left" "" "$(ls "$HOME_DIR"/*.seal 2>/dev/null)"
mv "$ARC/w.plan.md" "$P"
base
mkdir "$HOME_DIR/.reap"; printf '%s\n' "$$" > "$HOME_DIR/.reap/pid"
seal_remove "$P"; rc=$?
expect_status "a removal that meets a held lock exits 75" 75 "$rc"
expect_eq "and the seal is still there" 1 "$(ls "$HOME_DIR"/*.seal 2>/dev/null | wc -l | tr -d ' ')"
sh -c 'exit 0' & dead=$!; wait "$dead"
printf '%s\n' "$dead" > "$HOME_DIR/.reap/pid"
seal_remove "$P"; rc=$?
expect_status "the same removal once the holder is dead exits 0" 0 "$rc"
expect_eq "and the seal is gone" 0 "$(ls "$HOME_DIR"/*.seal 2>/dev/null | wc -l | tr -d ' ')"

section "PLAN"
# The write hook seals the plan in its after-arm, and only there. Each tool call is driven as Claude Code
# makes it: the before-arm's payload, then the tool's own effect on disk (done here by the shell, as the
# tool would), then the after-arm's payload. A call the before-arm denies, or whose tool never ran, has no
# after-arm, so it is driven with none.
. "$(dirname "$0")/lib/plan-fixture.sh"
GS_HOOK="$BIONIC_HOOKS_DIR/canonical-sdlc-governing-skill.sh"
R="$SB/proj"; mkdir -p "$R"; git -C "$R" init -q
SID=5e4d3c2b-1a09-4876-9b5c-4d3e2f1a0b9c
MK="$R/.bionic/tmp/engaged-$SID.state"
unbind() { mkdir -p "${MK%/*}"; printf 'plan=none\nengaged_at=2026-09-04T00:00:00Z\n' > "$MK"; }
unbind
RP="$R/.bionic/docs/plans/epic-99-fixture/wave-01-fixture.plan.md"
plan_fixture "$RP" task "| T1 | 4 | build | the first build | implementor | — | — | 30 | REQ-1 | a.sh | — | — | pending |" >/dev/null
RP="$(cd "${RP%/*}" && pwd -P)/${RP##*/}"
BODY="$(cat "$RP")
| a line the orchestrator wrote |"
NP="${RP%/*}/wave-02-fixture.plan.md"
plan_fixture "$NP" task "| T1 | 4 | build | another build | implementor | — | — | 30 | REQ-1 | b.sh | — | — | pending |" >/dev/null
NBODY="$(cat "$NP")"; rm "$NP"
drive() {  # <event> <tool> <tool_input json> [<tool_response json> [<agent id>]] -> HOOK_RC, HOOK_ERR
  local in
  in=$(jq -n --arg s "$SID" --arg c "$R" --arg e "$1" --arg t "$2" --argjson i "$3" \
         --argjson r "${4:-null}" --arg a "${5:-}" \
    '{session_id:$s, cwd:$c, hook_event_name:$e, tool_name:$t, tool_input:$i}
     + (if $r == null then {} else {tool_response:$r} end) + (if $a == "" then {} else {agent_id:$a} end)')
  HOOK_RC=0
  HOME="$SB/home" CLAUDE_CODE_SESSION_ID="$SID" bash "$GS_HOOK" <<< "$in" > /dev/null 2> "$SB/hook.err" || HOOK_RC=$?
  HOOK_ERR="$(cat "$SB/hook.err")"
}
edit_input() { jq -n --arg p "$RP" --arg o "$1" --arg n "$2" '{file_path:$p, old_string:$o, new_string:$n, replace_all:false}'; }
apply_edit() { local b; b="$(cat "$RP")"; printf '%s\n' "${b/"$1"/"$2"}" > "$RP"; }
seal_bytes() { cat "$R/.git/bionic-seal/"*.seal 2>/dev/null; }

after_arm_runs_for() {  # <tool> -> yes when hooks.json runs the write hook after that tool
  jq -r --arg t "$1" '[.hooks.PostToolUse[]? | select(any(.hooks[]?; .command | test("canonical-sdlc-governing-skill")))
    | .matcher | select(. as $m | $t | test("^(" + $m + ")$"))] | if length > 0 then "yes" else "no" end' \
    "$BIONIC_HOOKS_DIR/hooks.json"
}
expect_eq "hooks.json runs the write hook's after-arm for Write" yes "$(after_arm_runs_for Write)"
expect_eq "and for Edit" yes "$(after_arm_runs_for Edit)"
expect_eq "and not for Read" no "$(after_arm_runs_for Read)"

# The Write that creates a run's plan binds, and the bind appends its event to the log after the plan
# is sealed; that append is the appender's to seal, so here only the plan side is read.
WN=$(jq -n --arg p "$NP" --arg c "$NBODY" '{file_path:$p, content:$c}')
drive PreToolUse Write "$WN"
expect_status "the before-arm admits a new plan's first Write" 0 "$HOOK_RC"
printf '%s\n' "$NBODY" > "$NP"
drive PostToolUse Write "$WN" '{"type":"create"}'
expect_status "its after-arm exits 0" 0 "$HOOK_RC"
expect_eq "the Write that creates a plan binds the session" "plan=$NP" "$(head -1 "$MK")"
expect_eq "and seals the plan as written" "plan_sum=$(cksum < "$NP")" \
  "$(grep -h '^plan_sum=' "$R/.git/bionic-seal/${NP##*/}".*.seal 2>/dev/null)"
expect_regex "the bind's event is in the log" '^run/v1\|ev=bind\|' "$(/usr/bin/grep '^run/v1|ev=bind|' "$(plan_fixture_log "$NP")")"
expect_eq "and is sealed by the appender with the run, which verifies clean" clean "$(seal_verify "$NP")"
seal_remove "$NP"; unbind

# The fixture seals the run it plants; the seal is lifted so that the admit's own write, if any, is what reads.
seal_remove "$RP"
expect_eq "the planted run's seal is lifted" none "$(seal_verify "$RP")"
WI=$(jq -n --arg p "$RP" --arg c "$BODY" '{file_path:$p, content:$c}')
drive PreToolUse Write "$WI"
expect_status "the before-arm admits a Write over the plan" 0 "$HOOK_RC"
expect_eq "and seals nothing at its admit" none "$(seal_verify "$RP")"
printf '%s\n' "$BODY" > "$RP"
drive PostToolUse Write "$WI" '{"type":"update"}'
expect_status "the after-arm of the Write exits 0" 0 "$HOOK_RC"
expect_eq "an admitted Write leaves the plan sealed clean" clean "$(seal_verify "$RP")"

SUM0="$(cksum < "$RP")"
EI="$(edit_input "the first build" "the first build, edited")"
drive PreToolUse Edit "$EI"
expect_status "the before-arm admits an Edit of the plan" 0 "$HOOK_RC"
apply_edit "the first build" "the first build, edited"
expect_ne "the Edit changed the plan's bytes" "$SUM0" "$(cksum < "$RP")"
drive PostToolUse Edit "$EI" '{"filePath":"x"}'
expect_status "the after-arm of the Edit exits 0" 0 "$HOOK_RC"
expect_eq "an admitted Write then an admitted Edit leave the plan sealed clean" clean "$(seal_verify "$RP")"
expect_eq "an Edit seals and does not bind" "plan=none" "$(head -1 "$MK")"
expect_empty "and says nothing" "$HOOK_ERR"

S1="$(seal_bytes)"
DI="$(edit_input "governing-skill: canonical-sdlc" "")"
drive PreToolUse Edit "$DI"
expect_status "the before-arm denies an Edit that drops the governing skill" 2 "$HOOK_RC"
expect_nonempty "the seal stands before the denied Edit" "$S1"
expect_eq "a denied Edit with no after-arm leaves the seal as it was" "$S1" "$(seal_bytes)"
expect_eq "and the plan verifies clean" clean "$(seal_verify "$RP")"

EI2="$(edit_input "the first build, edited" "a build the tool never wrote")"
drive PreToolUse Edit "$EI2"
expect_status "the before-arm admits an Edit whose tool then never runs" 0 "$HOOK_RC"
expect_eq "an admitted Edit that never ran leaves the seal as it was" "$S1" "$(seal_bytes)"
expect_eq "and the plan verifies clean" clean "$(seal_verify "$RP")"

AI="$(edit_input "the first build, edited" "the first build, edited by an agent")"
drive PreToolUse Edit "$AI" "" a1b2c3
apply_edit "the first build, edited" "the first build, edited by an agent"
drive PostToolUse Edit "$AI" '{"filePath":"x"}' a1b2c3
expect_eq "a dispatched agent's admitted Edit is sealed too" clean "$(seal_verify "$RP")"
WU=$(jq -n --arg p "$RP" --arg c "$(cat "$RP")
| note |" '{file_path:$p, content:$c}')
drive PreToolUse Write "$WU" "" a1b2c3
printf '%s\n' "$(jq -r .content <<< "$WU")" > "$RP"
drive PostToolUse Write "$WU" '{"type":"update"}' a1b2c3
expect_eq "an agent's Write over the plan is sealed" clean "$(seal_verify "$RP")"
expect_eq "and moves no binding" "plan=none" "$(head -1 "$MK")"

mkdir -p "$R/.git/bionic-seal/.reap"; printf '%s\n' "$$" > "$R/.git/bionic-seal/.reap/pid"
S2="$(seal_bytes)"
LI="$(edit_input "| note |" "| note, under a held lock |")"
apply_edit "| note |" "| note, under a held lock |"
drive PostToolUse Edit "$LI" '{"filePath":"x"}'
expect_status "an after-arm whose seal meets a held lock still exits 0" 0 "$HOOK_RC"
expect_contains "and says the plan is not sealed" "not sealed" "$HOOK_ERR"
expect_eq "and the seal is as it was" "$S2" "$(seal_bytes)"
rm -rf "$R/.git/bionic-seal/.reap"
expect_eq "so the plan reads changed until it is sealed again" "changed what=plan how=changed" "$(seal_verify "$RP")"

# The commit gate (hooks/bash-walls.sh) over a fresh run at step 5 bound to SID, whose log owes a fact,
# so every commit of it is refused for that (OWED) until a change to the run is refused for the change.
. "$(dirname "$0")/lib/bound-marker.sh"
G="$SB/gate"
world() {
  rm -rf "$G"; mkdir -p "$G/.bionic/tmp"; git -C "$G" init -q
  git -C "$G" -c user.email=t@example.com -c user.name=T commit -q --allow-empty -m seed; git -C "$G" checkout -q -b feature/x
  GP="$(plan_fixture --current 5 "$G/.bionic/docs/plans/epic-x/wave-x.plan.md" wave)"; GL="$(plan_fixture_log "$GP")"
  : > "$G/.bionic/tmp/engaged-$SID.state"; bound_marker "$G" "$SID" "$GP"; GM="$G/.bionic/tmp/engaged-$SID.state"
}
gate() {  # <command> -> GRC, GLINE: the hook's exit and the first line it printed
  GRC=0; jq -n --arg s "$SID" --arg c "$G" --arg x "$1" '{session_id:$s, cwd:$c, hook_event_name:"PreToolUse",
    tool_name:"Bash", tool_input:{command:$x}}' | HOME="$SB/home" CLAUDE_CODE_SESSION_ID="$SID" CLAUDE_PROJECT_DIR= \
    BIONIC_PLUGINS_DIR="$SB/np" bash "$BIONIC_HOOKS_DIR/bash-walls.sh" > /dev/null 2> "$SB/gate.err" || GRC=$?
  GLINE="$(head -1 "$SB/gate.err")"
}
gated() {  # <label> <expected first line> <change> [<command>] -- a fresh world, the change, then the command
  world; eval "$3"; gate "${4:-git commit -m x}"
  expect_status "$1: refused" 2 "$GRC"
  expect_eq "$1: by that line" "$2" "$GLINE"
}
REF="bionic: commit refused —"
OWED="$REF a fact this step owes is missing (record each fact named)"
PUSH="bionic: push refused — main is a protected branch here (push from your own terminal)"
PG="$REF the run's plan is gone (only the person can rule)"
PC="$REF the run's plan was changed outside the tool (only the person can rule)"
LG="$REF the run's log is gone (only the person can rule)"
LS="$REF the run's log was shortened outside the tool (only the person can rule)"
LA="$REF the run's log was added to outside the tool (only the person can rule)"
LC="$REF the run's log was changed outside the tool (only the person can rule)"

# A file-writing tool's call in the gate world, driven through the write hook's before and after arms (drive,
# above), with the tool's own effect made by the shell between them; a call the before-arm denies goes no further.
tool() {  # <Write|Edit> <file> <content | old> [<new>] -> the tool call, admitted and made, in the gate world
  local in
  if [ "$1" = Write ]; then in="$(jq -n --arg p "$2" --arg c "$3" '{file_path:$p, content:$c}')"
  else in="$(jq -n --arg p "$2" --arg o "$3" --arg n "$4" '{file_path:$p, old_string:$o, new_string:$n, replace_all:false}')"; fi
  R="$G" drive PreToolUse "$1" "$in"; TOOL_PRE="$HOOK_RC"; [ "$HOOK_RC" = 0 ] || return 0
  # bash 3.2 keeps the quotes of a quoted replacement in the text, so the new string goes in unquoted.
  if [ "$1" = Write ]; then printf '%s\n' "$3" > "$2"; else local b n="$4"; b="$(cat "$2")"; printf '%s\n' "${b/"$3"/$n}" > "$2"; fi
  R="$G" drive PostToolUse "$1" "$in" '{"type":"update"}'
}
gated "the plan edited by sed -i" "$PC" 'sed -i.bak "s/fixture plan/a plan/" "$GP"'
gated "a line redirected onto the plan" "$PC" 'printf "| T9 | x |\n" >> "$GP"'
gated "an admitted Write, then an admitted Edit of the plan" "$OWED" \
  'tool Write "$GP" "$(cat "$GP")
"; tool Edit "$GP" "One plan a fixture writes" "One plan the tool wrote"'
expect_status "and the write hook admitted the Edit" 0 "$TOOL_PRE"
gated "an Edit of the plan denied at the before-arm" "$OWED" 'tool Edit "$GP" "governing-skill: canonical-sdlc" ""'
expect_status "and the write hook denied it" 2 "$TOOL_PRE"
world; mkdir -p "$G/.git/bionic-seal/.reap"; printf '%s\n' "$$" > "$G/.git/bionic-seal/.reap/pid"
t0=$SECONDS; gate "git commit -m x"
expect_eq "a seal held past the wait refuses the commit, to be run again (in $((SECONDS - t0)) s)" \
  "$REF the run's seal could not be read (run the commit again)" "$GLINE"

section "BOUND"
gated "the run as sealed" "$OWED" ':'
gated "the plan removed" "$PG" 'rm "$GP"'
gated "the plan renamed off .plan.md" "$PG" 'mv "$GP" "${GP%.plan.md}.md"'
gated "the plan moved to another folder" "$PG" 'mkdir -p "$G/.bionic/docs/plans/epic-y"; mv "$GP" "$G/.bionic/docs/plans/epic-y/"'

section "MARKER"
gated "the engaged file removed: a commit" "$OWED" 'rm "$GM"'
gated "and a push to main" "$PUSH" 'rm "$GM"' 'git push origin main'
gated "the engaged file replaced by a link: a commit" "$OWED" 'rm "$GM"; ln -s "$SB/outside" "$GM"'
gated "and a push to main" "$PUSH" 'rm "$GM"; ln -s "$SB/outside" "$GM"' 'git push origin main'
gated "the engaged file removed and a step added to the log" "$LA" 'rm "$GM"; printf "run/v1|ev=step|n=9|at=z\n" >> "$GL"'
gated "the engaged file rewritten to no plan" "$OWED" 'printf "plan=none\n" > "$GM"'
gated "to no plan line" "$OWED" 'printf "engaged_at=x\n" > "$GM"'
DECOY='DP="$(plan_fixture --current 4 "$G/.bionic/docs/plans/epic-y/wave-y.plan.md" wave)"'
world; eval "$DECOY"; bound_marker "$G" "$SID" "$DP"; gate "git commit -m x"
expect_status "control: a session bound to the decoy at step 4 has its commit admitted" 0 "$GRC"
gated "to a decoy plan at step 4" "$OWED" "$DECOY"'; printf "plan=%s\n" "$DP" > "$GM"'

section "LOG"
gated "the log removed" "$LG" 'rm "$GL"'
gated "the log renamed" "$LG" 'mv "$GL" "$GL.old"'
gated "the log emptied" "$LS" ': > "$GL"'
gated "its last line cut" "$LS" 'sed -i.bak "\$d" "$GL"'
gated "a line of it rewritten in place" "$LC" 'sed -i.bak "1s/n=1/n=7/" "$GL"'
for l in 'ev=abandon' 'ev=step|n=9|delivered=x' 'ev=step|n=10' 'ev=step|n=3' 'ev=cancel|of=step' \
         'ev=proof|kind=review|result=pass|head=x' 'ev=approval|key=step5|by=x|said=y' 'ev=waiver|key=x|by=y'; do
  gated "a hand-appended ${l%%|*} line (${l#ev=})" "$LA" "printf 'run/v1|$l|at=z\n' >> \"\$GL\""
done

section "TOOLS"
gated "a Write of the engaged file to no plan" "$OWED" 'tool Write "$GM" "plan=none"'
gated "an Edit of it to a decoy" "$OWED" "$DECOY"'; tool Edit "$GM" "$GP" "$DP"'
gated "a Write of the log cut short" "$LS" 'tool Write "$GL" "$(head -2 "$GL")"'
gated "an Edit adding a step to the log" "$LA" 'tool Edit "$GL" "$(tail -1 "$GL")" "$(tail -1 "$GL")
run/v1|ev=step|n=9|delivered=x|at=z"'
expect_status "and the write hook admitted that Edit" 0 "$TOOL_PRE"

section "CHANGED"
sitrep_asks() { (cd "$G" && HOME="$SB/home" CLAUDE_CODE_SESSION_ID="$SID" CLAUDE_PROJECT_DIR= \
  bash "$BIONIC_HOOKS_DIR/session-poker.sh" sitrep 2>/dev/null) | /usr/bin/grep '^ask: '; }
SA='^ask: key=seal:changed holds=every commit title=changed run: .* blocks=yes waits=user$'
while IFS="|" read -r label first change <&3; do
  gated "$label" "${!first}" "$change"
  E="$(cat "$SB/gate.err")"
  expect_contains "$label: the refusal names the log" "Log:   $GL" "$E"
  expect_contains "$label: and the reply that accepts" "session-poker.sh accept '<their words>'" "$E"
  expect_contains "$label: and the reply that abandons" "session-poker.sh abandon '<their words>'" "$E"
  expect_regex "$label: the ask is in the log the seal names" '^run/v1\|ev=ask\|key=seal:changed\|' "$(cat "$GL" 2>/dev/null)"
  expect_regex "$label: the sitrep lists it" "$SA" "$(sitrep_asks)"
done 3<<'ROWS'
the log removed|LG|rm "$GL"
the plan removed|PG|rm "$GP"
the plan edited|PC|printf "| T9 | x |\n" >> "$GP"
a line of the log rewritten|LC|sed -i.bak "1s/n=1/n=7/" "$GL"
ROWS
rm "$GP"
expect_regex "the ask of the changed log is listed still, with the plan then removed" "$SA" "$(sitrep_asks)"
gated "the plan removed, its commit refused, then put back" "$PC" 'cp "$GP" "$SB/keep"; rm "$GP"; gate "git commit -m x"; cp "$SB/keep" "$GP"'

section "ACCEPT"
. "${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/reader.sh"
CFG="$SB/cfg/projects/$(printf '%s' "$G" | sed 's/[^a-zA-Z0-9]/-/g')"; FX="$BIONIC_SCRIPTS_DIR/tests/fixtures/transcript-move"
typed() {  # <sid> <prompt>... -> the session witnessed in the gate world, each prompt typed in its transcript
  local s="$1" t; shift; mkdir -p "$CFG"; printf 'cwd=%s\n' "$G" > "$G/.bionic/tmp/loaded-$s.state"
  cat "$FX/frame.jsonl" > "$CFG/$s.jsonl"; for t in "$@"; do jq -c --arg t "$t" '.message.content = $t' "$FX/typed.jsonl" >> "$CFG/$s.jsonl"; done
}
poke() { PRC=0; (cd "$G" && HOME="$SB/home" CLAUDE_CONFIG_DIR="$SB/cfg" CLAUDE_CODE_SESSION_ID="$SID" CLAUDE_PROJECT_DIR= \
  bash "$BIONIC_HOOKS_DIR/session-poker.sh" "$@") > "$SB/poke.out" 2>&1 || PRC=$?; }
O=0a1b2c3d-4e5f-4061-8a7b-9c0d1e2f3a4b; W1="I accept the run as it stands"; ADD='printf "run/v1|ev=hand|what=note|why=by hand|at=z\n" >> "$GL"'
other() { git -C "$G" config user.name T; typed "$SID" "a prompt of another matter"; typed "$O" "$W1"; bound_marker "$G" "$O" "$GP"; }
gated "a bind line of another session added by hand" "$LA" 'other; printf "run/v1|ev=bind|by=engage|session=%s|at=z\n" "$O" >> "$GL"'
poke accept "$W1"
expect_status "accept on words only a session that line names typed: refused" 1 "$PRC"
expect_contains "for the words, that session not read: the sealed log binds it not" "refused: $O (not bound as the run was sealed)" "$(cat "$SB/poke.out")"
poke accept "a thing nobody typed at all"
expect_status "accept on words no session typed: refused" 1 "$PRC"
expect_eq "and the run stays changed" "changed what=log how=added" "$(seal_verify "$GP")"
gated "a line added by hand, the other session's bind sealed" "$LA" 'other; bind_record_session "$GP" "$O" engage; eval "$ADD"'
expect_regex "the ask stands before the word" "$SA" "$(sitrep_asks)"
poke accept "$W1"
expect_status "accept on words a session the sealed log binds typed: taken" 0 "$PRC"
expect_eq "the run verifies clean" clean "$(seal_verify "$GP")"
expect_eq "and its ask is closed" "" "$(sitrep_asks)"
gate "git commit -m x"; expect_eq "the commit meets the run's own refusal" "$OWED" "$GLINE"
expect_eq "the log holds one line, the word and what it accepted" 1 \
  "$(/usr/bin/grep -c "^run/v1|ev=approval|key=seal|by=T|said=$W1|session=$O|what=log|how=added|at=" "$GL")"

section "ABANDON"
W2="abandon the run here, it is done"
gated "a line added by hand" "$LA" "other; $ADD"
poke abandon "$W2"
expect_status "abandon on words no session typed: refused" 1 "$PRC"
expect_contains "for the words" "stand in no prompt the user typed" "$(cat "$SB/poke.out")"
expect_true "and the seal stands" seal_stands "$GP"
typed "$SID" "$W2"; poke abandon "$W2"
expect_status "abandon on words typed in this session: taken" 0 "$PRC"
expect_eq "the reader's step reads abandoned" state=abandoned "$(reader_main "$GP" step | tail -1)"
expect_status "the seal is gone" 1 "$(seal_stands "$GP"; echo $?)"
expect_eq "the log holds one abandon line, the word" 1 "$(/usr/bin/grep -c "^run/v1|ev=abandon|by=T|said=$W2|session=$SID|at=" "$GL")"
gate "git commit -m x"; expect_status "and a commit is admitted as a closed run's" 0 "$GRC"
gated "the plan removed" "$PG" "other; rm \"\$GP\"; typed \"\$SID\" \"\$W2\""
poke abandon "$W2"
expect_status "a run whose plan is gone is abandoned on the word" 0 "$PRC"
gate "git commit -m x"; expect_status "and its commit is admitted" 0 "$GRC"
wl() { bash -c '. "$1/git-argv.sh" && . "$1/walls.sh" && _wall_poker_contract_verb "$2"; printf "%s|%s " "$?" "$_WALL_POKER_VERB"' \
  _ "$BIONIC_SCRIPTS_DIR/payload/scripts/lib" "bash hooks/session-poker.sh $1 'w'"; }
expect_eq "the walls read both as verbs of the run's record, and not the sitrep" "0|accept 0|abandon 1| " "$(wl accept; wl abandon; wl sitrep)"

finish
