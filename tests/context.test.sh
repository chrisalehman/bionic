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
# THE SEVEN VALUES, and the fact that each is a VALUE and not an action:
#
#   BIONIC_INPUT      the payload text, read from stdin at most once
#   BIONIC_CWD        the one ladder: CLAUDE_PROJECT_DIR if set and a directory,
#                     else the payload's `.cwd` if a directory, else `pwd`
#   BIONIC_ROOT       project_root "$BIONIC_CWD"
#   BIONIC_SID        session_id, past the one shape guard
#   BIONIC_ENGAGED    0 or 1 — a VALUE, because session-start prints a bystander
#                     line where the other fourteen exit
#   BIONIC_RUN_WORD   bound-open | bound-closed | fallback | none
#   BIONIC_RUN_PLAN   the plan path the verdict names, empty for `none`
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
PROBE_BODY='
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

require_helpers mk_repo payload probe field

# ============================================================
section "1 — the seven values, from one well-formed payload"
# ============================================================
#
# The anti-vacuity row of this whole suite: every other section varies ONE input and
# reads ONE value back, which proves nothing if the happy path never produced a value
# at all. This row is the happy path, read field by field.

R_OPEN=$(mk_repo one open)
REC=$(probe "$SANDBOX" "$(payload "$R_OPEN")" CLAUDE_CODE_SESSION_ID="$SID")

expect_eq "a well-formed payload identifies the session (return 0)" "0" "$(field "$REC" rc)"
expect_eq "BIONIC_CWD is the payload's cwd"      "$R_OPEN" "$(field "$REC" cwd)"
expect_eq "BIONIC_ROOT is that cwd's project root" "$R_OPEN" "$(field "$REC" root)"
expect_eq "BIONIC_SID is the resolved session id" "$SID"    "$(field "$REC" sid)"
expect_eq "BIONIC_ENGAGED is 1 for an engaged session" "1"  "$(field "$REC" engaged)"
expect_eq "BIONIC_RUN_WORD is the verdict word alone" "fallback" "$(field "$REC" run_word)"
expect_eq "BIONIC_RUN_PLAN is the plan the verdict names" \
  "$R_OPEN/.bionic/docs/plans/epic-99/wave-01.plan.md" "$(field "$REC" run_plan)"
expect_eq "BIONIC_INPUT holds the payload it read" "$(payload "$R_OPEN")" "$(field "$REC" input)"

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

# rung 1 — CLAUDE_PROJECT_DIR set AND a directory: it wins over a perfectly good
# payload cwd. This is the rung session-start reverses today.
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
REC=$(probe "$SANDBOX" "$(payload "$R_CLOSED")" CLAUDE_CODE_SESSION_ID="$SID")
expect_eq "a closed run still identifies the session (return 0)" "0" "$(field "$REC" rc)"
expect_eq "…and reports the verdict rather than acting on it" "none" "$(field "$REC" run_word)"
expect_eq "…with no plan path on the 'none' verdict" "" "$(field "$REC" run_plan)"

# a BOUND session: the marker names a plan, and the verdict is bound-open
R_BOUND=$(mk_repo verdict-bound open)
printf 'plan=%s\n' "$R_BOUND/.bionic/docs/plans/epic-99/wave-01.plan.md" \
  > "$R_BOUND/.bionic/tmp/engaged-$SID.state"
REC=$(probe "$SANDBOX" "$(payload "$R_BOUND")" CLAUDE_CODE_SESSION_ID="$SID")
expect_eq "a bound session over an open plan reads bound-open" "bound-open" "$(field "$REC" run_word)"
expect_eq "…and names the bound plan" \
  "$R_BOUND/.bionic/docs/plans/epic-99/wave-01.plan.md" "$(field "$REC" run_plan)"

# THE VERDICT NEVER DECIDES. `bound-closed` is the verdict on which two hooks exit, two
# blank the plan and carry on, and the evidence gate treats the plan as usable; so the
# library must return 0 on it like any other identified session.
R_BC=$(mk_repo verdict-bound-closed closed)
printf 'plan=%s\n' "$R_BC/.bionic/docs/plans/epic-99/wave-01.plan.md" \
  > "$R_BC/.bionic/tmp/engaged-$SID.state"
REC=$(probe "$SANDBOX" "$(payload "$R_BC")" CLAUDE_CODE_SESSION_ID="$SID")
expect_eq "bound-closed is reported, not acted on" "bound-closed" "$(field "$REC" run_word)"
expect_eq "…and the session is still identified (return 0)" "0" "$(field "$REC" rc)"

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
