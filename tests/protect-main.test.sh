#!/bin/bash
# Tests for protect-main.sh Claude Code hook.
# Runs the hook against a matrix of push commands x branch states,
# verifying that pushes to main/master are always blocked and
# pushes to feature branches are allowed.
#
# Usage: bash tests/protect-main.test.sh

set -euo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"

# THE SEAM IS hooks/bash-walls.sh (epic-23 wave-11-lean-spine, T23). This wall is a
# FUNCTION now — `wall_protect_main` in payload/scripts/lib/walls.sh — registered through
# the one PreToolUse|Bash command object that carries all five. Every case below drives
# that process, which is what a Bash tool call actually starts; the wall's own verdict is
# unchanged and tests/bash-walls.test.sh owns the composition the process adds.
HOOK="${BIONIC_HOOKS_DIR}/bash-walls.sh"

# ---------- helpers ----------

run_hook() {
  # Feeds a simulated tool_input to the hook on stdin.
  #
  # The payload is built with `jq -n --arg`, not string interpolation: the
  # AC-9/AC-10 cases below carry double quotes and newlines (a heredoc), and
  # hand-built JSON mangles both. Same idiom as
  # tests/canonical-sdlc-evidence-gate.test.sh:run_hook.
  local cmd="$1"
  pm_payload "$ENGAGED_REPO" "$cmd" \
    | env CLAUDE_CODE_SESSION_ID="$SID" CLAUDE_PROJECT_DIR= bash "$HOOK" 2>/dev/null
}

# ---------- the engaged fixture (task-engaged-session, AC-20) ----------
#
# Since 2026-09-03 this wall only speaks in a session that invoked the canonical-sdlc
# skill (Chris: "Nothing should apply until bionic is triggered"). The marker recording
# the invocation is `.bionic/tmp/engaged-<sid>.state` under the payload's project root,
# so every arm below runs from a repo that has one — the world in which "does this wall
# still refuse a push to main" is the question anyone means. The unengaged world is the
# section at the bottom, driven on the same commands.
#
# THE ENVIRONMENT AGREES WITH THE PAYLOAD, because on the machine it does: lib/session.sh
# takes the env value as primary and the payload as a witness, so a driver that left the
# RUNNER's own session id in the environment would have the hook looking for a marker
# this fixture never wrote, and every row would pass for the wrong reason.
PM_SANDBOX="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/pmain.XXXXXX")" && pwd -P)"
SID="7a6b5c4d-3e2f-4109-8877-665544332211"
ENGAGED_REPO="$PM_SANDBOX/engaged"
PLAIN_REPO="$PM_SANDBOX/plain"
mkdir -p "$ENGAGED_REPO/.bionic/tmp" "$PLAIN_REPO/.bionic/tmp" "$PM_SANDBOX/home"
: > "$ENGAGED_REPO/.bionic/tmp/engaged-$SID.state"
export HOME="$PM_SANDBOX/home"

pm_payload() {  # <cwd> <command>
  jq -n --arg s "$SID" --arg c "$1" --arg cmd "$2" \
    '{session_id:$s, cwd:$c, hook_event_name:"PreToolUse", tool_name:"Bash",
      tool_input:{command:$cmd}}'
}

expect_block() {
  local label="$1"
  local cmd="$2"
  if run_hook "$cmd"; then
    no "$label" "expected BLOCK, got ALLOW"
  else
    ok "$label"
  fi
}

expect_allow() {
  local label="$1"
  local cmd="$2"
  if run_hook "$cmd"; then
    ok "$label"
  else
    no "$label" "expected ALLOW, got BLOCK"
  fi
}

# ---------- setup: fake git that reports a controllable branch ----------

FAKE_BIN=$(mktemp -d)
cat > "$FAKE_BIN/git" << 'FAKEGIT'
#!/bin/bash
# Intercept "git symbolic-ref --short HEAD" and return $FAKE_BRANCH.
# Also intercept the same call prefixed with "-C <dir>" (T5, D2: the wall now
# asks for the branch of the payload's resolved cwd via `git -C "$BIONIC_CWD"
# symbolic-ref --short HEAD`, not the hook process's own cwd) — strip a
# leading "-C <dir>" pair before matching. Pass everything else through to
# real git.
args=("$@")
if [[ "${args[0]:-}" == "-C" ]]; then
  args=("${args[@]:2}")
fi
if [[ "${args[*]}" == "symbolic-ref --short HEAD" ]]; then
  echo "${FAKE_BRANCH:-main}"
  exit 0
fi
# Fall through to real git for any other sub-command
REAL_GIT=$(which -a git | grep -v "$FAKE_BIN" | head -1)
exec "$REAL_GIT" "$@"
FAKEGIT
chmod +x "$FAKE_BIN/git"

export PATH="$FAKE_BIN:$PATH"

cleanup() { rm -rf "$FAKE_BIN"; }
trap cleanup EXIT

# ============================================================
# SECTION 1: On main branch — every push must be blocked
# ============================================================

section "Section 1: On 'main' branch (all pushes must be BLOCKED)"
export FAKE_BRANCH="main"

expect_block "explicit: push origin main"            "git push origin main"
expect_block "explicit: push upstream main"           "git push upstream main"
expect_block "explicit: push origin master"           "git push origin master"
expect_block "bare push"                              "git push"
expect_block "push origin (implicit branch)"          "git push origin"
expect_block "push origin HEAD"                       "git push origin HEAD"
expect_block "push -u origin main"                    "git push -u origin main"
expect_block "push --set-upstream origin main"        "git push --set-upstream origin main"
expect_block "push origin HEAD:main"                  "git push origin HEAD:main"
expect_block "push origin HEAD:refs/heads/main"       "git push origin HEAD:refs/heads/main"
expect_block "force push -f"                          "git push -f origin main"
expect_block "force push --force"                     "git push --force origin main"
expect_block "force push --force-with-lease"          "git push --force-with-lease origin main"
expect_block "push in compound command"               "cd /tmp && git push origin"
expect_block "push with env prefix"                   "GIT_SSH_COMMAND=ssh git push origin main"
expect_block "compound with ||"                       "false || git push origin main"
expect_block "force push flag at end"                 "git push origin main -f"
expect_block "force push --force at end"              "git push origin feat/x --force"
expect_block "refspec push HEAD:main"                 "git push origin HEAD:main"
# A case-blind filesystem runs `GIT` as git (wave-24 T31): the capitalised push is a push.
expect_block "capitalised: GIT push origin main"      "GIT push origin main"
expect_block "capitalised: Git push (bare, on main)"  "Git push"
# The words in front of git are names too (wave-25 T12): `SUDO` runs sudo and `BASH` runs bash
# on a case-blind filesystem, so each of these is the push its lower-case form is.
expect_block "capitalised prefix: SUDO git push origin main"   "SUDO git push origin main"
expect_block "capitalised runner: BASH -c '<push>'"           "BASH -c 'git push origin main'"
expect_block "capitalised prefix: Env X=1 git push"            "Env X=1 git push origin main"
expect_block "capitalised prefix: NOHUP git push (bare)"       "NOHUP git push"
# …and a commit is still a commit: this wall admits one on main, in either casing.
expect_allow "control: bash -c '<commit>' on main is admitted" "bash -c 'git commit -m x'"
expect_allow "capitalised runner: BASH -c '<commit>' is admitted exactly as bash -c is" "BASH -c 'git commit -m x'"

# ============================================================
# SECTION 2: On master branch — every push must be blocked
# ============================================================

section "Section 2: On 'master' branch (all pushes must be BLOCKED)"
export FAKE_BRANCH="master"

expect_block "master: bare push"                      "git push"
expect_block "master: push origin"                    "git push origin"
expect_block "master: push origin HEAD"               "git push origin HEAD"
expect_block "master: push origin master"             "git push origin master"

# ============================================================
# SECTION 3: On feature branch — non-main pushes must be allowed
# ============================================================

section "Section 3: On feature branch (safe pushes must be ALLOWED)"
export FAKE_BRANCH="feat/cool-thing"

expect_allow "feature: push origin feat/cool-thing"   "git push origin feat/cool-thing"
expect_allow "feature: push -u origin feat/cool-thing" "git push -u origin feat/cool-thing"
expect_allow "feature: bare push"                     "git push"
expect_allow "feature: push origin"                   "git push origin"
expect_allow "feature: push origin HEAD"              "git push origin HEAD"

# Even from a feature branch, explicit main/master must be blocked
expect_block "feature: push origin main (explicit)"   "git push origin main"
expect_block "feature: push origin master (explicit)"  "git push origin master"

# Force pushes always blocked regardless of branch
expect_block "feature: force push -f"                 "git push -f origin feat/cool-thing"
expect_block "feature: force push --force"            "git push --force origin feat/cool-thing"
expect_block "feature: force push --force-with-lease"  "git push --force-with-lease origin feat/cool-thing"

# Branch names containing "main" as substring should be allowed
expect_allow "feature: push branch with main substring" "git push origin feat/maintain-state"
expect_allow "feature: push domain-main branch"        "git push origin domain-main-fix"

# ============================================================
section "AC-E1.3/E1.5: every refusal is one line, in the criterion's shape"
# ============================================================
#
# fails-when: a refusal reaches the user as more than one VERDICT line, or in any shape but
# `bionic: <verb> refused — <fact> (<fix ≤ 40 cols>)`. Each of this wall's three
# refusal sites is TRIPPED for real here — the stderr asserted is the one a live
# session would paint (e1-measurement.md §D-2 F-D2-3) — and each is checked against
# the criterion's own regex, then against the exact line the ruled wording table
# gives it (s12-refusal-wording-draft.md §1 rows 2, 3 and 4).
#
# AC-E1.3 IS ABOUT THE VERDICT, AND ADR-030 MADE THAT DISTINCTION VISIBLE (epic-23
# wave-16 T4). Under ruling D-1 the `exit2` stream was the verdict and nothing else, so
# "the stream is one line" and "the verdict is one line" were the same measurement and this
# helper took the cheaper one. They are not the same any more: the wall's `detail` follows
# the verdict on that same wire now, bounded, with no knob set. What the criterion asks —
# a refusal the reader can read as one sentence, in the ruled wording, never wrapped — is
# the VERDICT, so that is what the rows below count and compare. The detail is asserted to
# be there as well, or narrowing the count would quietly weaken the section.

PM_LINE_RE='^bionic: [a-z-]+ refused — .+ \(.{1,40}\)$'
pm_stderr() {  # <branch> <command> -> the hook's stderr, verbatim
  FAKE_BRANCH="$1" pm_payload "$ENGAGED_REPO" "$2" \
    | env CLAUDE_CODE_SESSION_ID="$SID" CLAUDE_PROJECT_DIR= FAKE_BRANCH="$1" \
        bash "$HOOK" 2>"$PM_SANDBOX/.err" >/dev/null
  cat "$PM_SANDBOX/.err"
}

pm_one_line() {  # <label> <branch> <command> <expected line>
  local _lbl="$1" _br="$2" _cmd="$3" _want="$4" _got _n _line _rest
  _got="$(pm_stderr "$_br" "$_cmd")"
  _n="$(/usr/bin/grep -c '^bionic: ' "$PM_SANDBOX/.err" | tr -d ' ')"
  _line="$(/usr/bin/grep -m1 '^bionic: ' "$PM_SANDBOX/.err")"
  # WHAT FOLLOWS THE VERDICT, if anything: the stream minus its rendered line(s). Read
  # here rather than asserted per caller, because every site of this wall carries a
  # `detail` and a row that stopped carrying one is the regression worth seeing.
  _rest="$(/usr/bin/grep -v '^bionic: ' "$PM_SANDBOX/.err" | /usr/bin/grep -c . | tr -d ' ')"
  eq_or() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "want [$3] got [$2]"; fi; }
  eq_or "$_lbl: exactly one VERDICT line on the user stream" "$_n" "1"
  if printf '%s' "$_line" | /usr/bin/grep -qE "$PM_LINE_RE"; then
    ok "$_lbl: in AC-E1.3's shape"
  else
    no "$_lbl: in AC-E1.3's shape" "line=[$_line]"
  fi
  eq_or "$_lbl: and it is the table's own wording" "$_line" "$_want"
  # THE POSITIVE THAT KEEPS THE COUNT HONEST (ADR-030): the verdict is one line BECAUSE
  # the detail is a separate thing beneath it, not because the wall went quiet.
  if [ "$_rest" -ge 1 ]; then
    ok "$_lbl: with its detail beneath it, no knob set"
  else
    no "$_lbl: with its detail beneath it, no knob set" "nothing after the verdict"
  fi
}


# THE DETAIL IS ON THE WIRE, end to end through this real wall (AC-E1.5, re-authored by
# ADR-030). The branch name is the value the one line had no room for. It used to live
# behind the knob and nowhere else; `exit2` carries it to the reader now, so what this pair
# holds is the SPLIT rather than the absence: the verdict line is still the ruled sentence
# and carries no detail, and the detail sentence is on the stream beneath it with no knob
# set. Asserted on the line and on the stream separately, so neither half can pass over an
# empty capture.
PM_KNOB_OFF="$(pm_stderr "main" "git push origin feature/x")"
PM_KNOB_OFF_LINE="$(/usr/bin/grep -m1 '^bionic: ' "$PM_SANDBOX/.err")"
case "$PM_KNOB_OFF_LINE" in
  *"feature branch"*) ok "AC-E1.5 the verdict line is the ruled sentence, fix and all" ;;
  *) no "AC-E1.5 the verdict line is the ruled sentence, fix and all" "line=[$PM_KNOB_OFF_LINE]" ;;
esac
case "$PM_KNOB_OFF_LINE" in
  *'The current branch is'*) no "AC-E1.5 …and the detail sentence is NOT on that line" ;;
  *) ok "AC-E1.5 …and the detail sentence is NOT on that line" ;;
esac
case "$PM_KNOB_OFF" in
  *'The current branch is "main"'*) ok "AC-E1.5 …it is beneath it, with no knob set at all" ;;
  *) no "AC-E1.5 …it is beneath it, with no knob set at all" "got=[$PM_KNOB_OFF]" ;;
esac
pm_payload "$ENGAGED_REPO" "git push origin feature/x" \
  | env CLAUDE_CODE_SESSION_ID="$SID" CLAUDE_PROJECT_DIR= FAKE_BRANCH="main" \
      BIONIC_WALL_VERBOSE=1 bash "$HOOK" 2>"$PM_SANDBOX/.errv" >/dev/null || true
PM_KNOB_ON="$(cat "$PM_SANDBOX/.errv")"
case "$PM_KNOB_ON" in
  *'The current branch is "main"'*) ok "AC-E1.5 with BIONIC_WALL_VERBOSE=1 the detail names the branch" ;;
  *) no "AC-E1.5 with BIONIC_WALL_VERBOSE=1 the detail names the branch" "got=[$PM_KNOB_ON]" ;;
esac
if printf '%s' "$PM_KNOB_ON" | head -1 | /usr/bin/grep -qE "$PM_LINE_RE"; then
  ok "AC-E1.5 …and the one line is still the first of it"
else
  no "AC-E1.5 …and the one line is still the first of it"
fi

rm -rf "$PM_SANDBOX"

finish
