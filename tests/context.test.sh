#!/bin/bash
# tests/context.test.sh — payload/scripts/lib/context.sh: THE ONE CONTEXT PREAMBLE
# (epic-23 wave-11-lean-spine, REQ-1f (ii) and REQ-1h; AC-1f.2, AC-1h.1, AC-1h.2;
# spec Design §1 "ContextPreamble", §2 D6).
#
# WHAT IS UNDER TEST. Six lines that fifteen hooks used to carry a private copy of —
# read the payload, find the cwd, find the root, resolve the session id, ask whether
# this session engaged bionic, ask which run it is in — asked once here and answered
# the SAME way for every caller. The census T10 ran measured seven different cwd
# ladders, a session-id shape guard in six hooks of fifteen and three different
# actions on an empty id; REQ-1h says that residue goes to zero rather than being
# preserved per hook, so THIS suite is where the one reading is written down.
#
# THE EIGHT VALUES, and the fact that each is a VALUE and not an action:
#
#   BIONIC_INPUT      the payload text, read from stdin at most once
#   BIONIC_CWD        the one ladder: CLAUDE_PROJECT_DIR if it names a PROJECT,
#                     else the payload's `.cwd` if a directory, else `pwd`
#   BIONIC_ROOT       project_root "$BIONIC_CWD"
#   BIONIC_SID        session_id, past the one shape guard
#   BIONIC_ENGAGED    0 or 1 — a VALUE, because session-start prints a bystander
#                     line where the other fourteen exit
#   BIONIC_RUN_WORD   bound-open | bound-closed | fallback | none — or `unset`,
#                     the sentinel for a caller that did not set
#                     BIONIC_CONTEXT_WANT_RUN=1 (wave-14 REQ-4; section 4)
#   BIONIC_RUN_PLAN   the plan path the verdict names, empty for `none` and for
#                     the `unset` sentinel
#   BIONIC_WORKTREE   the linked worktree the root was mapped from, empty when
#                     the walk mapped none (epic-23 wave-14 REQ-2, spec D5)
#
# WHY THE VERDICT IS A VALUE AND NOT A DECISION (census §4.2, pins §5.5). The four
# hooks carrying the 4-branch `case` do DIFFERENT things on `bound-closed`: two exit
# 0, two blank the plan and continue, the governing skill prints a line and falls
# through, and the evidence gate treats it as `bound-open`. A library that acted on
# the verdict would silently change four hooks; one that returns it changes none.
#
# WHY THE RETURN CODE IS THE WHOLE CONTRACT. `bionic_context` returns 1 when it
# cannot identify the session — no root, an empty session id, a session id carrying
# a character outside [A-Za-z0-9_-] — and 0 otherwise. Every caller spells that
# `bionic_context || exit 0`, so a guard that returned 0 on a malformed id would arm
# fifteen walls on a key that addresses a file outside the state directory.
#
# HERMETIC. Every fixture is a directory under one mktemp sandbox; HOME is overridden
# into it so the ancestor walk cannot escape upward into the real checkout, and the
# library is sourced in a CHILD shell per probe so no row is answered by a variable an
# earlier row left set in this one.
#
# Usage: bash tests/context.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
LIB="$REPO_ROOT/payload/scripts/lib/context.sh"

SANDBOX="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/context-test.XXXXXX")" && pwd -P)"
cleanup() { rm -rf "$SANDBOX"; }
trap cleanup EXIT
mkdir -p "$SANDBOX/home"

SID="c0ntext1-2222-3333-4444-555555555555"

# ── the fixtures ─────────────────────────────────────────────────────────────

# mk_repo <name> <state> -> a project root. state = bare|engaged|open|closed
#   bare    : a directory with a .bionic, no engagement marker, no plan
#   engaged : the marker for $SID, no plan
#   open    : engaged, plus a plan at `current: 4`
#   closed  : engaged, plus a plan at `current: 9` carrying a delivered Step-9 line
mk_repo() {
  local name="$1" state="$2"
  local root="$SANDBOX/repos/$name"
  mkdir -p "$root/.bionic/tmp" "$root/.bionic/docs/plans/epic-99"
  case "$state" in
    engaged|open|closed) : > "$root/.bionic/tmp/engaged-$SID.state" ;;
  esac
  local cur="" step9=""
  case "$state" in
    open)   cur="4"; step9="- Step 9: (pending)" ;;
    closed) cur="9"; step9="- Step 9: delivered: record/x.md" ;;
  esac
  if [ -n "$cur" ]; then
    cat > "$root/.bionic/docs/plans/epic-99/wave-01.plan.md" <<PLAN
---
canonical_sdlc_version: 14
---

# fixture plan

## SDLC State

current: $cur

- Step 4: implementation
$step9
PLAN
  fi
  printf '%s' "$root"
}

# mk_wt_repo <name> -> "<main-root>TAB<worktree-dir>". The MAIN checkout carries the
# .bionic and the engagement marker; the linked worktree carries neither, so rule 1 of
# lib/root.sh has to map it before the walk can find anything at all. The worktree's
# directory name and its branch name differ on purpose — the eighth value is the
# worktree's, and a reading that parsed the branch would answer the other one.
mk_wt_repo() {
  # ONE `local` PER DERIVED VALUE. `local a="$1" b="$a"` expands every right-hand
  # side before the builtin assigns any of them, so `$a` there is the caller's `a`,
  # not this one — under `set -u` that is an unbound-variable abort, not a subtle
  # wrong answer, which is the only reason it did not ship silently.
  local name="$1"
  local root="$SANDBOX/repos/$name"
  local wt="$SANDBOX/repos/$name-tree"
  mkdir -p "$root/.bionic/tmp"
  git -c init.defaultBranch=main init -q "$root" >/dev/null 2>&1
  ( cd "$root" && : > .keep && git add .keep >/dev/null 2>&1 &&
    git -c user.name=t -c user.email=t@example.invalid commit -q -m init >/dev/null 2>&1 )
  git -C "$root" worktree add -q -b "$name-branch" "$wt" >/dev/null 2>&1
  : > "$root/.bionic/tmp/engaged-$SID.state"
  mkdir -p "$wt/sub"
  printf '%s\t%s' "$root" "$wt"
}

payload() {  # <cwd> [sid] -> the payload text
  local cwd="$1" sid="${2-$SID}"
  printf '{"session_id":"%s","cwd":"%s","hook_event_name":"PreToolUse"}' "$sid" "$cwd"
}

# ── the probe ────────────────────────────────────────────────────────────────
#
# ONE CHILD SHELL PER ROW, and the values come back as a labelled record rather than
# a positional list: a probe that printed seven bare fields would report the wrong
# one forever the first time a value was inserted in the middle.
#
# `<unset>` is distinguished from empty on purpose. "The lib never assigned this" and
# "the lib assigned it the empty string" are different contract claims, and the tty
# row below is exactly the pair that tells them apart.
#
# THE RECORD OPENS WITH A BARE NEWLINE, and that is for section 7 alone. BSD
# `script` puts a real terminal on descriptor 0, and a terminal ECHOES what is
# written to it: the forwarded payload comes back as `^D\b\b{"session_id":…}` with
# no trailing newline, so the first field printed would continue THAT line and
# `field`'s `^rc=` would never match. One leading newline puts every field at the
# start of a line on both paths; on the fourteen non-pty rows it costs one blank
# line that `sed` ignores. (Measured on darwin 25.6.0: without it the pty row's
# record reads `{"cwd":"x"}rc=1`.)
PROBE_BODY='
  printf "\n"
  cd "$1" || exit 99
  . "$2" >/dev/null 2>&1 || exit 98
  bionic_context 2>/dev/null
  _rc=$?
  printf "rc=%s\n"        "$_rc"
  printf "cwd=%s\n"       "${BIONIC_CWD-<unset>}"
  printf "root=%s\n"      "${BIONIC_ROOT-<unset>}"
  printf "sid=%s\n"       "${BIONIC_SID-<unset>}"
  printf "engaged=%s\n"   "${BIONIC_ENGAGED-<unset>}"
  printf "run_word=%s\n"  "${BIONIC_RUN_WORD-<unset>}"
  printf "run_plan=%s\n"  "${BIONIC_RUN_PLAN-<unset>}"
  printf "worktree=%s\n" "${BIONIC_WORKTREE-<unset>}"
  printf "input=%s\n"     "${BIONIC_INPUT-<unset>}"
'

# probe <run-from-dir> <payload> [VAR=VAL ...] -> the record on stdout
probe() {
  local from="$1" pay="$2"; shift 2
  printf '%s' "$pay" | env HOME="$SANDBOX/home" "$@" \
    /bin/bash -c "$PROBE_BODY" _ "$from" "$LIB" 2>/dev/null
}

# field <record> <key> -> that value
field() { printf '%s\n' "$1" | sed -n "s/^$2=//p"; }

require_helpers mk_repo mk_wt_repo payload probe field

# ============================================================
section "1 — the eight values, from one well-formed payload"
# ============================================================
#
# The anti-vacuity row of this whole suite: every other section varies ONE input and
# reads ONE value back, which proves nothing if the happy path never produced a value
# at all. This row is the happy path, read field by field.

R_OPEN=$(mk_repo one open)
# THE VERDICT IS ASKED FOR (epic-23 wave-14 REQ-4). `BIONIC_CONTEXT_WANT_RUN=1` is what
# hooks/stop.sh, hooks/dispatch-preflight.sh and hooks/session-start.sh set before their
# own call, and this row reads the eight values a caller that wants all eight gets. The
# row that reads them WITHOUT the flag is section 4's, below.
REC=$(probe "$SANDBOX" "$(payload "$R_OPEN")" CLAUDE_CODE_SESSION_ID="$SID" BIONIC_CONTEXT_WANT_RUN=1)

expect_eq "a well-formed payload identifies the session (return 0)" "0" "$(field "$REC" rc)"
expect_eq "BIONIC_CWD is the payload's cwd"      "$R_OPEN" "$(field "$REC" cwd)"
expect_eq "BIONIC_ROOT is that cwd's project root" "$R_OPEN" "$(field "$REC" root)"
expect_eq "BIONIC_SID is the resolved session id" "$SID"    "$(field "$REC" sid)"
expect_eq "BIONIC_ENGAGED is 1 for an engaged session" "1"  "$(field "$REC" engaged)"
expect_eq "BIONIC_RUN_WORD is the verdict word alone" "fallback" "$(field "$REC" run_word)"
expect_eq "BIONIC_RUN_PLAN is the plan the verdict names" \
  "$R_OPEN/.bionic/docs/plans/epic-99/wave-01.plan.md" "$(field "$REC" run_plan)"
expect_eq "BIONIC_INPUT holds the payload it read" "$(payload "$R_OPEN")" "$(field "$REC" input)"

# THE EIGHTH VALUE (epic-23 wave-14 REQ-2, spec D5 "Hook context"). `lib/root.sh`
# already knows whether the walk mapped a linked worktree onto its main repository;
# the preamble carries that name so the evidence gate can find the plan row that
# owns a worktree writer's commit without asking git a second time.
#
# EMPTY, NOT `<unset>`: fifteen hooks read these values under `set -u`, and an
# eighth value that only sometimes exists would abort the wall that read it.
expect_eq "BIONIC_WORKTREE is empty when the root is an ordinary directory" \
  "" "$(field "$REC" worktree)"

# The positive half, against a real linked worktree — without it the row above
# passes just as well against a library that never assigns the value anything.
WT_PAIR=$(mk_wt_repo eighth)
WT_MAIN="${WT_PAIR%%$'\t'*}"
WT_DIR="${WT_PAIR#*$'\t'}"
REC_WT=$(probe "$SANDBOX" "$(payload "$WT_DIR/sub")" CLAUDE_CODE_SESSION_ID="$SID")

expect_eq "a payload cwd inside a linked worktree still resolves to the MAIN root" \
  "$WT_MAIN" "$(field "$REC_WT" root)"
expect_eq "BIONIC_WORKTREE names the worktree the root was mapped from" \
  "eighth-tree" "$(field "$REC_WT" worktree)"
expect_ne "BIONIC_WORKTREE is not the branch name" \
  "eighth-branch" "$(field "$REC_WT" worktree)"
expect_eq "the session is still identified from inside the worktree (return 0)" \
  "0" "$(field "$REC_WT" rc)"

# ============================================================
section "2 — ONE cwd ladder (AC-1h.1): env, then the payload, then pwd"
# ============================================================
#
# THE LADDER IS DRIVEN AT EVERY RUNG, not asserted at its top. Three of the seven
# ladders the census found agree with this one on the first rung and disagree below
# it, so a suite that only drove "env wins" would have passed unchanged against four
# of the readings this requirement exists to delete.

R_ENV=$(mk_repo ladder-env engaged)
R_PAY=$(mk_repo ladder-payload engaged)
R_PWD=$(mk_repo ladder-pwd engaged)

# rung 1 — CLAUDE_PROJECT_DIR set, a directory AND naming a project: it wins over a
# perfectly good payload cwd. This is the rung session-start reverses today. The
# project half of the test is A-85's, driven in its own block below.
REC=$(probe "$R_PWD" "$(payload "$R_PAY")" CLAUDE_CODE_SESSION_ID="$SID" CLAUDE_PROJECT_DIR="$R_ENV")
expect_eq "CLAUDE_PROJECT_DIR, set and a directory, is the cwd" "$R_ENV" "$(field "$REC" cwd)"

# rung 1, refused — set but NOT a directory: the ladder falls THROUGH rather than
# taking it. A ladder that tested only `-n` would answer with a path that does not
# exist and hand project_root a walk from nowhere.
REC=$(probe "$R_PWD" "$(payload "$R_PAY")" CLAUDE_CODE_SESSION_ID="$SID" \
      CLAUDE_PROJECT_DIR="$SANDBOX/no-such-dir")
expect_eq "CLAUDE_PROJECT_DIR set to a non-directory falls through to the payload" \
  "$R_PAY" "$(field "$REC" cwd)"

# rung 1, empty — the same as unset, which is how every other env knob in this tree reads
REC=$(probe "$R_PWD" "$(payload "$R_PAY")" CLAUDE_CODE_SESSION_ID="$SID" CLAUDE_PROJECT_DIR="")
expect_eq "CLAUDE_PROJECT_DIR empty counts as unset" "$R_PAY" "$(field "$REC" cwd)"

# rung 2 — no env: the payload's .cwd
REC=$(probe "$R_PWD" "$(payload "$R_PAY")" CLAUDE_CODE_SESSION_ID="$SID")
expect_eq "with no CLAUDE_PROJECT_DIR the payload's .cwd is the cwd" "$R_PAY" "$(field "$REC" cwd)"

# rung 2, refused — a payload cwd that is not a directory falls through to pwd
REC=$(probe "$R_PWD" "$(payload "$SANDBOX/gone")" CLAUDE_CODE_SESSION_ID="$SID")
expect_eq "a payload .cwd that is not a directory falls through to pwd" "$R_PWD" "$(field "$REC" cwd)"

# rung 3 — no env, no payload cwd at all
REC=$(probe "$R_PWD" '{"session_id":"'"$SID"'"}' CLAUDE_CODE_SESSION_ID="$SID")
expect_eq "with neither, the cwd is pwd" "$R_PWD" "$(field "$REC" cwd)"

# rung 3 — no payload at all
REC=$(probe "$R_PWD" '' CLAUDE_CODE_SESSION_ID="$SID")
expect_eq "with an empty payload the cwd is still pwd" "$R_PWD" "$(field "$REC" cwd)"

# THE ROOT FOLLOWS THE LADDER, which is the point of the ladder. A hook that landed on
# the right cwd and the wrong root would answer "unarmed" from a worktree of an armed
# session — the failure AC-10 was written for.
REC=$(probe "$R_PWD" "$(payload "$R_PAY")" CLAUDE_CODE_SESSION_ID="$SID" CLAUDE_PROJECT_DIR="$R_ENV")
expect_eq "BIONIC_ROOT is resolved from whichever rung won" "$R_ENV" "$(field "$REC" root)"

# ── rung 1 IS FOR PROJECTS, NOT FOR DIRECTORIES (critic Issue 2, A-85) ───────
#
# THE DIRECTION A WALL MUST FAIL IN. A session launched outside a bionic project
# that then works inside one keeps CLAUDE_PROJECT_DIR at the LAUNCH directory, and
# the payload's `.cwd` is the project. A rung 1 that asked only `-d` took the launch
# directory, `project_root` answered with its git toplevel (root.sh's
# `git-toplevel-fallback` — it never answers empty), no engagement marker lived
# there, and every one of the five Bash walls and four turn-end verdicts went
# silent: `push refused, rc 2` became silence and rc 0, measured. Nine of the
# fifteen pre-fold hooks recovered through `.cwd` and would have stayed armed.
#
# So the rung tests for a PROJECT: `project_root_candidates` must terminate in
# `chosen`, which is the one tag that means a real `.bionic` was found. A
# `git-toplevel-fallback` or a `cwd-fallback` is not a project and does not win the
# ladder — it falls through to the same two rungs below it.

R_PLAIN_GIT="$SANDBOX/plain-git"; mkdir -p "$R_PLAIN_GIT"
( cd "$R_PLAIN_GIT" && git init -q . >/dev/null 2>&1 ) || :
R_PLAIN_BARE="$SANDBOX/plain-nogit"; mkdir -p "$R_PLAIN_BARE"

expect_eq "the fixture really is a git repository with no .bionic" "yes"   "$([ -d "$R_PLAIN_GIT/.git" ] && [ ! -e "$R_PLAIN_GIT/.bionic" ] && echo yes || echo no)"

# THE CRITIC'S TWO-REPOS DRIVE. CLAUDE_PROJECT_DIR at the git repo that is not a
# project, the payload `.cwd` at the engaged project.
REC=$(probe "$R_PWD" "$(payload "$R_PAY")" CLAUDE_CODE_SESSION_ID="$SID"       CLAUDE_PROJECT_DIR="$R_PLAIN_GIT")
expect_eq "a CLAUDE_PROJECT_DIR that is a git repo but NOT a project falls through to the payload"   "$R_PAY" "$(field "$REC" cwd)"
expect_eq "…and BIONIC_ROOT is the payload's project, not the git toplevel"   "$R_PAY" "$(field "$REC" root)"
expect_eq "…and the session is still identified (return 0)" "0" "$(field "$REC" rc)"
expect_eq "…and still reads as ENGAGED, which is what keeps the walls armed"   "1" "$(field "$REC" engaged)"

# The same with no repository at all, where root.sh's terminal tag is cwd-fallback
# rather than git-toplevel-fallback. Both are "no project"; neither may win.
REC=$(probe "$R_PWD" "$(payload "$R_PAY")" CLAUDE_CODE_SESSION_ID="$SID"       CLAUDE_PROJECT_DIR="$R_PLAIN_BARE")
expect_eq "a CLAUDE_PROJECT_DIR that is a plain directory falls through too"   "$R_PAY" "$(field "$REC" cwd)"
expect_eq "…and its root is the payload's project" "$R_PAY" "$(field "$REC" root)"

# RUNG 2 KEEPS ITS OWN TEST, and that is deliberate (A-85). The ruling scopes the
# project test to rung 1, where the failure was: an env var SHADOWING a project the
# payload names. Rung 2's only successor is `pwd` — the hook process's directory,
# which is a worse answer than the directory the tool actually ran in — so a payload
# `.cwd` that is a directory still wins on `-d`, exactly as before.
REC=$(probe "$R_PWD" "$(payload "$R_PLAIN_BARE")" CLAUDE_CODE_SESSION_ID="$SID" CLAUDE_PROJECT_DIR="$R_PLAIN_GIT")
expect_eq "rung 1 refused, the payload's .cwd still wins on -d even when it is no project" "$R_PLAIN_BARE" "$(field "$REC" cwd)"

# …and on to rung 3 when there is no payload cwd at all: the fall-through is the
# WHOLE ladder, not a one-step swap.
REC=$(probe "$R_PWD" '{"session_id":"'"$SID"'"}' CLAUDE_CODE_SESSION_ID="$SID" CLAUDE_PROJECT_DIR="$R_PLAIN_GIT")
expect_eq "rung 1 refused and no payload cwd: the cwd is pwd" "$R_PWD" "$(field "$REC" cwd)"

# THE POSITIVE CONTROL, so the row above cannot pass by disabling rung 1 outright:
# a CLAUDE_PROJECT_DIR that IS a project still beats a perfectly good payload cwd.
REC=$(probe "$R_PWD" "$(payload "$R_PAY")" CLAUDE_CODE_SESSION_ID="$SID" CLAUDE_PROJECT_DIR="$R_ENV")
expect_eq "a CLAUDE_PROJECT_DIR that IS a project still wins over the payload"   "$R_ENV" "$(field "$REC" cwd)"
expect_eq "…and its root is that project" "$R_ENV" "$(field "$REC" root)"

# A NESTED cwd inside the project is a project too — the rung asks project_root,
# not `-d .bionic`, so the env may name any directory under a root.
mkdir -p "$R_ENV/deep/deeper"
REC=$(probe "$R_PWD" "$(payload "$R_PAY")" CLAUDE_CODE_SESSION_ID="$SID"       CLAUDE_PROJECT_DIR="$R_ENV/deep/deeper")
expect_eq "a CLAUDE_PROJECT_DIR nested inside a project wins, and resolves to the root"   "$R_ENV" "$(field "$REC" root)"
expect_eq "…and the cwd is the directory the env named" "$R_ENV/deep/deeper" "$(field "$REC" cwd)"

# ============================================================
section "3 — ONE session-id guard (AC-1h.2): empty and malformed both return 1"
# ============================================================
#
# The guard is the reason the return code exists. Nine of the fifteen hooks had no
# shape check at all and two substituted the literal `unknown` and carried on; both
# readings end here.

R_G=$(mk_repo guard engaged)

REC=$(probe "$SANDBOX" "$(payload "$R_G")" CLAUDE_CODE_SESSION_ID="$SID")
expect_eq "a well-formed session id returns 0" "0" "$(field "$REC" rc)"

# empty: no env value and no payload value. session_id itself fails here; the lib
# must turn that into a return 1 rather than an empty key it goes on to interpolate.
REC=$(probe "$SANDBOX" "$(payload "$R_G" "")" CLAUDE_CODE_SESSION_ID="")
expect_eq "an empty session id returns 1" "1" "$(field "$REC" rc)"
expect_eq "…and BIONIC_SID is left empty, never the literal 'unknown'" "" "$(field "$REC" sid)"

# malformed: the shape AC-1h.2 names by value. `bad/../id` is a path traversal in a
# filename position — every state path in the tree is built by interpolating this key.
REC=$(probe "$SANDBOX" "$(payload "$R_G" 'bad/../id')" CLAUDE_CODE_SESSION_ID="bad/../id")
expect_eq "a session id carrying a path separator returns 1" "1" "$(field "$REC" rc)"
expect_eq "…and BIONIC_SID is blanked, so no caller can interpolate it" "" "$(field "$REC" sid)"

# the same shape from the ENV channel while the payload is clean: the guard is on the
# RESOLVED value, not on the payload read, because the env value is the primary one.
REC=$(probe "$SANDBOX" "$(payload "$R_G")" CLAUDE_CODE_SESSION_ID='bad;rm -rf /')
expect_eq "a malformed ENV session id returns 1 even with a clean payload id" "1" "$(field "$REC" rc)"

# every other character class the rule admits, so the guard is not simply refusing
# everything: letters, digits, underscore and hyphen all pass.
REC=$(probe "$SANDBOX" "$(payload "$R_G" 'A-z_0-9')" CLAUDE_CODE_SESSION_ID='A-z_0-9')
expect_eq "letters, digits, underscore and hyphen are admitted" "0" "$(field "$REC" rc)"

# A RETURN 1 SAYS NOTHING ON EITHER STREAM. Fifteen hooks turn it into `exit 0`, and a
# bystander session must not learn that bionic is installed.
BAD_OUT=$(printf '%s' "$(payload "$R_G" 'bad/../id')" | env HOME="$SANDBOX/home" \
  CLAUDE_CODE_SESSION_ID="bad/../id" /bin/bash -c \
  'cd "$1" || exit 99; . "$2" >/dev/null 2>&1 || { echo "no-library"; exit 98; }; bionic_context' _ "$SANDBOX" "$LIB" 2>&1)
expect_empty "a refusal is silent on both streams" "$BAD_OUT"

# ============================================================
section "4 — the run verdict is a VALUE, one word plus the path it names"
# ============================================================

R_CLOSED=$(mk_repo verdict-closed closed)
REC=$(probe "$SANDBOX" "$(payload "$R_CLOSED")" CLAUDE_CODE_SESSION_ID="$SID" BIONIC_CONTEXT_WANT_RUN=1)
expect_eq "a closed run still identifies the session (return 0)" "0" "$(field "$REC" rc)"
expect_eq "…and reports the verdict rather than acting on it" "none" "$(field "$REC" run_word)"
expect_eq "…with no plan path on the 'none' verdict" "" "$(field "$REC" run_plan)"

# a BOUND session: the marker names a plan, and the verdict is bound-open
R_BOUND=$(mk_repo verdict-bound open)
printf 'plan=%s\n' "$R_BOUND/.bionic/docs/plans/epic-99/wave-01.plan.md" \
  > "$R_BOUND/.bionic/tmp/engaged-$SID.state"
REC=$(probe "$SANDBOX" "$(payload "$R_BOUND")" CLAUDE_CODE_SESSION_ID="$SID" BIONIC_CONTEXT_WANT_RUN=1)
expect_eq "a bound session over an open plan reads bound-open" "bound-open" "$(field "$REC" run_word)"
expect_eq "…and names the bound plan" \
  "$R_BOUND/.bionic/docs/plans/epic-99/wave-01.plan.md" "$(field "$REC" run_plan)"

# THE VERDICT NEVER DECIDES. `bound-closed` is the verdict on which two hooks exit, two
# blank the plan and carry on, and the evidence gate treats the plan as usable; so the
# library must return 0 on it like any other identified session.
R_BC=$(mk_repo verdict-bound-closed closed)
printf 'plan=%s\n' "$R_BC/.bionic/docs/plans/epic-99/wave-01.plan.md" \
  > "$R_BC/.bionic/tmp/engaged-$SID.state"
REC=$(probe "$SANDBOX" "$(payload "$R_BC")" CLAUDE_CODE_SESSION_ID="$SID" BIONIC_CONTEXT_WANT_RUN=1)
expect_eq "bound-closed is reported, not acted on" "bound-closed" "$(field "$REC" run_word)"
expect_eq "…and the session is still identified (return 0)" "0" "$(field "$REC" rc)"

# ---- THE VERDICT IS OPT-IN (epic-23 wave-14 REQ-4, spec D5 "Hook context") ----
#
# The scan behind this one value walks every candidate under `plans/` and `incidents/`
# and reads each one — 28.0 ms on a one-plan fixture, about 2.8 ms more per plan a repo
# accumulates (research R3 §6-§7) — and `payload/scripts/lib/walls.sh` holds not one
# reference to either variable, so the five Bash walls paid all of it for an answer none
# of them read. A caller that wants the verdict now says so.
#
# THE SENTINEL IS THE WHOLE SAFETY OF THE CUT, and these rows exist to pin it rather than
# the saving. `none` is a REAL verdict — "this session is in no run" — and a caller that
# met the empty string where it expected a word would take the `none` branch and believe
# it had been told something. `unset` is outside the closed vocabulary, so a `case` over
# it falls to its own arm and a comparison with any real verdict fails: the reader finds
# out it did not ask, which is the fail-closed direction.
R_OPTIN=$(mk_repo verdict-optin open)
printf 'plan=%s\n' "$R_OPTIN/.bionic/docs/plans/epic-99/wave-01.plan.md" \
  > "$R_OPTIN/.bionic/tmp/engaged-$SID.state"

REC_OFF=$(probe "$SANDBOX" "$(payload "$R_OPTIN")" CLAUDE_CODE_SESSION_ID="$SID")
expect_eq "without the flag the verdict is the sentinel, NOT a verdict word" \
  "unset" "$(field "$REC_OFF" run_word)"
expect_true "…and it is a WORD, never the empty string a reader could mistake for none" \
  test -n "$(field "$REC_OFF" run_word)"
expect_eq "…with no plan path beside it" "" "$(field "$REC_OFF" run_plan)"
expect_eq "…and the session is identified exactly as before (return 0)" \
  "0" "$(field "$REC_OFF" rc)"
expect_eq "…and every other value is unaffected by not asking" \
  "$R_OPTIN 1" "$(field "$REC_OFF" root) $(field "$REC_OFF" engaged)"

# THE DIFFERENTIAL: same fixture, same payload, one variable. Without it these rows
# would pass against a library that had simply stopped computing the verdict at all.
REC_ON=$(probe "$SANDBOX" "$(payload "$R_OPTIN")" CLAUDE_CODE_SESSION_ID="$SID" BIONIC_CONTEXT_WANT_RUN=1)
expect_eq "with the flag the same session reads its real verdict" \
  "bound-open" "$(field "$REC_ON" run_word)"
expect_eq "…and names the plan the sentinel row withheld" \
  "$R_OPTIN/.bionic/docs/plans/epic-99/wave-01.plan.md" "$(field "$REC_ON" run_plan)"

# A FLAG THAT IS NOT `1` IS NOT AN ASK. The test is equality with `1`, not emptiness, so
# an inherited `BIONIC_CONTEXT_WANT_RUN=0` from an enclosing session cannot turn the scan
# back on by accident.
REC_ZERO=$(probe "$SANDBOX" "$(payload "$R_OPTIN")" CLAUDE_CODE_SESSION_ID="$SID" BIONIC_CONTEXT_WANT_RUN=0)
expect_eq "BIONIC_CONTEXT_WANT_RUN=0 is not an ask" "unset" "$(field "$REC_ZERO" run_word)"

# ============================================================
section "5 — engagement is a VALUE too, 0 or 1"
# ============================================================
#
# Fourteen hooks turn a 0 into `exit 0`; session-start prints a bystander line instead.
# A library that exited on it would delete that line and take session-start's whole
# unengaged report with it.

R_BARE=$(mk_repo engagement-bare bare)
REC=$(probe "$SANDBOX" "$(payload "$R_BARE")" CLAUDE_CODE_SESSION_ID="$SID")
expect_eq "an unengaged session is identified, not refused (return 0)" "0" "$(field "$REC" rc)"
expect_eq "…and reports BIONIC_ENGAGED=0" "0" "$(field "$REC" engaged)"

# a SYMLINK at the marker path reads as NOT engaged and is never followed — the one
# shape a repository controls that must not be able to OPEN a wall.
R_LNK=$(mk_repo engagement-symlink bare)
printf 'plan=none\n' > "$SANDBOX/eng-decoy"
ln -s "$SANDBOX/eng-decoy" "$R_LNK/.bionic/tmp/engaged-$SID.state"
REC=$(probe "$SANDBOX" "$(payload "$R_LNK")" CLAUDE_CODE_SESSION_ID="$SID")
expect_eq "a symlink at the marker path is not an engagement" "0" "$(field "$REC" engaged)"

# ============================================================
section "6 — the payload is read ONCE: adopted when already set, stdin otherwise"
# ============================================================
#
# THE TWO FAIL-CLOSED HOOKS ARE WHY (pins §2). protect-main and the evidence gate read
# stdin BEFORE any library exists, because `loader_fail_closed` matches the repair
# allowlist on the command TEXT and the library that would have supplied it is exactly
# what failed to load. They set BIONIC_INPUT from what they read; stdin is consumed once
# and a second `cat` would block or return empty.

R_A=$(mk_repo adopt engaged)
R_B=$(mk_repo adopt-other engaged)

ADOPT_REC=$(printf '%s' "$(payload "$R_B")" | env HOME="$SANDBOX/home" \
  CLAUDE_CODE_SESSION_ID="$SID" BIONIC_INPUT="$(payload "$R_A")" \
  /bin/bash -c "$PROBE_BODY" _ "$SANDBOX" "$LIB" 2>/dev/null)
expect_eq "a BIONIC_INPUT already set is ADOPTED, not overwritten from stdin" \
  "$(payload "$R_A")" "$(field "$ADOPT_REC" input)"
expect_eq "…so every value is read out of the adopted payload" "$R_A" "$(field "$ADOPT_REC" cwd)"

# AN EMPTY BIONIC_INPUT IS STILL SET. `${BIONIC_INPUT+x}` is the test, not `-n`: a hook
# whose payload really was empty has already consumed stdin, and a lib that re-read on
# emptiness would block behind a pipe with nothing left in it.
EMPTY_REC=$(printf '%s' "$(payload "$R_B")" | env HOME="$SANDBOX/home" \
  CLAUDE_CODE_SESSION_ID="$SID" BIONIC_INPUT="" \
  /bin/bash -c "$PROBE_BODY" _ "$R_A" "$LIB" 2>/dev/null)
expect_eq "BIONIC_INPUT set to the empty string is adopted as empty, never re-read" \
  "" "$(field "$EMPTY_REC" input)"
expect_eq "…and the cwd falls to pwd, since the adopted payload names none" \
  "$R_A" "$(field "$EMPTY_REC" cwd)"

# ============================================================
section "7 — stdin is read only when it is NOT a terminal"
# ============================================================
#
# THE RULE EXISTS SO A HAND-RUN CALLER CANNOT HANG. It is driven through a real pty,
# because `[ -t 0 ]` is the only thing that distinguishes the two cases and no
# redirection can fake it: `script` gives the child a terminal on descriptor 0 AND
# forwards this shell's pipe into it, so the payload IS available to a `cat` that is
# not guarded. A library that read anyway would find the payload and return 0; the
# guarded one finds no payload, no session id, and returns 1.
#
# WITHOUT THE FORWARDED PAYLOAD THIS ROW WOULD PROVE NOTHING — an unguarded `cat` on an
# empty terminal returns empty too, and both readings would look identical.
if command -v script >/dev/null 2>&1; then
  TTY_REC=$(printf '%s' "$(payload "$R_A")" | env HOME="$SANDBOX/home" \
    CLAUDE_CODE_SESSION_ID="" \
    script -q /dev/null /bin/bash -c "$PROBE_BODY" _ "$SANDBOX" "$LIB" 2>/dev/null \
    | tr -d '\r')
  expect_eq "with stdin a terminal the payload is NOT read, so the session is unidentified" \
    "1" "$(field "$TTY_REC" rc)"
  expect_eq "…and BIONIC_INPUT is left empty rather than filled from the terminal" \
    "" "$(field "$TTY_REC" input)"
else
  no "a pty is available to drive the terminal rule" "script(1) not found on this machine"
fi

# ============================================================
section "8 — bionic_jq: the one payload reader, replacing fifteen private _jq copies"
# ============================================================

JQ_BODY='
  . "$1" >/dev/null 2>&1 || exit 98
  BIONIC_INPUT="$2"
  printf "a=%s\n" "$(bionic_jq .session_id)"
  printf "b=%s\n" "$(bionic_jq .tool_input.command)"
  printf "c=%s\n" "$(bionic_jq .nope)"
  printf "d=%s\n" "$(bionic_jq .deep.nested.thing)"
'
JQ_REC=$(/bin/bash -c "$JQ_BODY" _ "$LIB" \
  '{"session_id":"s1","tool_input":{"command":"git push"},"deep":{"nested":{"thing":"yes"}}}' 2>/dev/null)
expect_eq "bionic_jq reads a top-level field out of BIONIC_INPUT" "s1" "$(field "$JQ_REC" a)"
expect_eq "bionic_jq reads a nested field" "git push" "$(field "$JQ_REC" b)"
expect_eq "an absent field is the empty string, never the literal null" "" "$(field "$JQ_REC" c)"
expect_eq "a deep path resolves" "yes" "$(field "$JQ_REC" d)"

# MALFORMED JSON IS EMPTY, NOT AN ERROR. Every one of the fifteen private `_jq` copies
# carried `2>/dev/null` for this reason: a hook that printed jq's parse error would put
# a line on the user's stream for a payload it has nothing to say about.
BAD_JQ=$(/bin/bash -c '. "$1" >/dev/null 2>&1 || exit 98; BIONIC_INPUT="not json at all"; printf "a=%s\n" "$(bionic_jq .session_id)"' \
  _ "$LIB" 2>&1)
expect_eq "a payload that is not JSON yields empty, on stdout and stderr alike" "a=" "$BAD_JQ"

# AND AN UNSET BIONIC_INPUT IS NOT AN UNBOUND-VARIABLE CRASH. Every hook runs under
# `set -u`, so a bare `$BIONIC_INPUT` here would take the hook down at its first read.
UNSET_JQ=$(/bin/bash -c 'set -u; . "$1" >/dev/null 2>&1 || exit 98; unset BIONIC_INPUT; printf "a=%s\n" "$(bionic_jq .session_id)"' \
  _ "$LIB" 2>&1)
expect_eq "bionic_jq with BIONIC_INPUT unset is empty, not an unbound-variable error" "a=" "$UNSET_JQ"

# ============================================================
section "9 — the library is sourced, never executed, and greets nobody"
# ============================================================
#
# Every caller reads its values out of variables the lib set, and several read library
# verbs through `$( )`. A library that printed at source time would corrupt the first
# field of every one of those answers.
SRC_OUT=$(/bin/bash -c '. "$1"' _ "$LIB" 2>&1)
expect_empty "sourcing context.sh prints nothing on either stream" "$SRC_OUT"

# IT BRINGS ITS OWN DEPENDENCIES, through the self-dir idiom lib/run.sh and lib/roots.sh
# use. A caller that sourced context.sh alone must still get a working bionic_context —
# that is what makes `. lib/context.sh` a complete thing rather than a fragment.
DEPS_OUT=$(/bin/bash -c '. "$1" >/dev/null 2>&1 || { echo "missing:the library itself"; exit 98; }
  for f in bionic_context bionic_jq project_root session_id engaged_session session_run; do
    declare -F "$f" >/dev/null 2>&1 || printf "missing:%s\n" "$f"
  done' _ "$LIB" 2>/dev/null)
expect_empty "sourcing context.sh alone defines every function bionic_context calls" "$DEPS_OUT"

finish
