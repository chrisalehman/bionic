#!/bin/bash
# payload/scripts/lib/context.sh — THE ONE CONTEXT PREAMBLE, for every hook that
# has one (epic-23 wave-11-lean-spine, REQ-1f (ii) and REQ-1h; spec Design §1
# "ContextPreamble", §2 D6).
#
# WHAT IT OWNS. Fifteen hooks opened the same way after the loader — read the
# payload, find the cwd, find the root, resolve the session id, ask whether this
# session engaged bionic, ask which run it is in — in 861 lines that said one
# thing. `bionic_context` says it once. Each hook then does its OWN work, and
# nothing here decides any of it.
#
# THE SEVEN VALUES. Every one is a VALUE the caller reads, never an action:
#
#   BIONIC_INPUT      the payload text, read from stdin at most once
#   BIONIC_CWD        the ONE ladder (below)
#   BIONIC_ROOT       project_root "$BIONIC_CWD"
#   BIONIC_SID        the session id, past the ONE shape guard
#   BIONIC_ENGAGED    0 or 1
#   BIONIC_RUN_WORD   bound-open | bound-closed | fallback | none
#   BIONIC_RUN_PLAN   the plan path the verdict names; empty for `none`
#
# THE RETURN CODE IS THE WHOLE CONTRACT. 1 when the session cannot be identified
# — no root, no session id, or a session id carrying a character outside
# [A-Za-z0-9_-] — and 0 otherwise. Every caller spells it `bionic_context || exit
# 0`, which is why a guard that returned 0 on a malformed id would arm fifteen
# walls on a key that addresses a file outside the state directory.
#
# ENGAGEMENT IS A VALUE, NOT AN EXIT, because session-start prints its bystander
# notice exactly where the other fourteen exit. Fourteen hooks spell the decision
# `[ "$BIONIC_ENGAGED" = 1 ] || exit 0` in their own bodies, one line each, and
# session-start reads the 0 and reports.
#
# THE RUN VERDICT IS A VALUE for a sharper reason (census §4.2, T10-pins §5.5).
# The four hooks carrying the 4-branch `case` do DIFFERENT things on
# `bound-closed`: two exit 0, two blank the plan and continue, the governing skill
# prints a line and falls through, and the evidence gate treats it as
# `bound-open`. A library that acted on the verdict would silently change four
# hooks; one that reports it changes none. So `bound-closed` returns 0 here like
# any other identified session, and the `case` stays in the caller.
#
# ONE LADDER (REQ-1h, AC-1h.1; user ruling 2026-09-12 "1, go with unify"). The
# census measured SEVEN cwd ladders across the fifteen. They are one now:
#
#   1. $CLAUDE_PROJECT_DIR, if set AND a directory
#   2. else the payload's `.cwd`, if a directory
#   3. else `pwd`
#
# EACH RUNG TESTS FOR A DIRECTORY AND NOT MERELY FOR A VALUE. A ladder that
# stopped at `-n` would answer with a path that does not exist and hand
# `project_root` a walk from nowhere — which is the fail-dangerous direction, since
# the walk would then answer about whatever directory the hook happened to be in.
#
# ONE GUARD (REQ-1h, AC-1h.2). The shape rule `[A-Za-z0-9_-]` lived in six of the
# fifteen; nine had no check at all, one blanked the variable instead of exiting,
# and two substituted the literal `unknown` and carried on. It lives here now, and
# an id that fails it leaves BIONIC_SID EMPTY as well as returning 1 — a caller
# that ignored the return code still cannot interpolate a traversal into a state
# path.
#
# READ ONCE, ADOPT IF ALREADY READ (R1). stdin is consumed exactly once in a
# process, so a second `cat` returns empty or blocks. Two hooks — protect-main and
# canonical-sdlc-evidence-gate — MUST read the payload before any library exists,
# because `loader_fail_closed` matches the repair allowlist on the command TEXT
# and the library that would have supplied it is precisely the one that failed to
# load. They assign BIONIC_INPUT from what they read, and this file adopts it. The
# test is `${BIONIC_INPUT+x}` and not `-n`: a hook whose payload really was empty
# has still consumed stdin.
#
# SOURCED, NEVER EXECUTED, AND SILENT AT SOURCE TIME. Callers read values out of
# variables and library verbs through `$( )`; anything printed on the way in would
# corrupt the first field of every one of those answers.
#
# IT BRINGS ITS OWN DEPENDENCIES through the self-dir idiom lib/roots.sh and
# lib/run.sh use, guarded on the function rather than the file so a caller that
# already sourced one pays nothing. `. lib/context.sh` is therefore a complete
# thing rather than a fragment — which is what lets a hook name `context.sh` in
# BIONIC_LIB_WANT and get a working `bionic_context`.
#
# BASH 3.2. No associative arrays, no `${var^^}`, no `mapfile`.
#
# NO `dirname`/`basename` IN THE SELF-LOCATOR, for lib/roots.sh's reason: a
# library that cannot be sourced without coreutils dies on the half-broken machine
# it is most needed on.
#
# [WALL: tests/context.test.sh]

_context_self_dir() {
  local self="${BASH_SOURCE[0]}"
  case "$self" in */*) echo "${self%/*}" ;; *) echo "." ;; esac
}

# RESOLVED AT SOURCE TIME, for the reason lib/roots.sh states at `_ROOTS_LIB_DIR`:
# `${BASH_SOURCE[0]%/*}` is RELATIVE when the file was sourced by a relative path,
# and a soft source that re-derived it later would read against whatever the
# caller's cwd had become.
_CONTEXT_LIB_DIR="$(cd "$(_context_self_dir)" && pwd -P)"

if ! declare -F project_root >/dev/null 2>&1; then
  # shellcheck source=/dev/null
  . "$_CONTEXT_LIB_DIR/root.sh"
fi
if ! declare -F session_id >/dev/null 2>&1; then
  # shellcheck source=/dev/null
  . "$_CONTEXT_LIB_DIR/session.sh"
fi
if ! declare -F session_run >/dev/null 2>&1; then
  # shellcheck source=/dev/null
  . "$_CONTEXT_LIB_DIR/run.sh"
fi

# ─── The one payload reader ──────────────────────────────────────────────────
#
# bionic_jq <path> -> that field of BIONIC_INPUT, or the empty string.
#
# BYTE-FOR-BYTE the `_jq()` the hooks carried fifteen private copies of:
# `printf '%s' … | jq -r "$1 // empty" 2>/dev/null`. The `// empty` is what turns
# an absent field into the empty string rather than the literal `null`, and the
# redirection is what keeps a hook from printing jq's parse error onto the user's
# stream for a payload it has nothing to say about.
#
# `${BIONIC_INPUT:-}` AND NOT `$BIONIC_INPUT`: every hook runs under `set -u`, so
# a bare expansion here would take the hook down at its first read rather than
# answering empty.
#
# TEN HOOKS KEEP A PRE-LOADER `_jq`, and that is not a second copy of this — it is
# the same concession R1 makes for `INPUT=$(cat)`. Those hooks read the payload to
# answer a cheap relevance question ABOVE the loader block, where `$BIONIC_LIB`
# does not yet have a value and no library function exists to call. Every read
# BELOW the loader goes through this one.
bionic_jq() {
  printf '%s' "${BIONIC_INPUT:-}" | jq -r "$1 // empty" 2>/dev/null
}

# ─── The one preamble ────────────────────────────────────────────────────────
#
# bionic_context -> sets the seven values; 0 when the session is identified, 1
# when it is not. Silent on both streams either way, because fourteen of the
# fifteen callers turn a 1 into `exit 0` and a bystander session must not learn
# that bionic is installed.
#
# THE ORDER IS CWD, ROOT, SID, ENGAGEMENT, RUN, and the two early returns are
# placed so that a caller reading a value after a failure reads an honest one:
# BIONIC_CWD is assigned before the root can fail, and BIONIC_SID is blanked
# before the guard returns.
bionic_context() {
  local _pcwd _sid _verdict

  # 1. THE PAYLOAD, ONCE.
  if [ -z "${BIONIC_INPUT+x}" ]; then
    if [ -t 0 ]; then
      # A HAND-RUN CALLER MUST NOT HANG. With stdin a terminal there is no payload
      # to read, and a `cat` would sit waiting for one that is never coming.
      BIONIC_INPUT=""
    else
      BIONIC_INPUT="$(cat)"
    fi
  fi

  # 2. THE ONE LADDER.
  if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -d "${CLAUDE_PROJECT_DIR:-}" ]; then
    BIONIC_CWD="$CLAUDE_PROJECT_DIR"
  else
    _pcwd="$(bionic_jq .cwd)"
    if [ -n "$_pcwd" ] && [ -d "$_pcwd" ]; then
      BIONIC_CWD="$_pcwd"
    else
      BIONIC_CWD="$(pwd)"
    fi
  fi

  # 3. THE ROOT. `project_root` prints nothing and still returns 0 when the walk
  # finds no project, so the emptiness is the test.
  BIONIC_ROOT="$(project_root "$BIONIC_CWD" 2>/dev/null)"
  [ -n "$BIONIC_ROOT" ] || return 1

  # 4. THE SESSION ID, PAST THE ONE GUARD. stderr is suppressed HERE rather than
  # at the call site for every caller but one: session-start wants lib/session.sh's
  # divergence line and spells its own call without the redirection (cross-gate
  # §P2), so the suppression that belongs to the other fourteen lives with them.
  _sid="$(session_id "$(bionic_jq .session_id)")" || _sid=""
  # ONE LINE, and the same spelling the six hooks that carried this rule used, so the
  # family pin that reads for it (tests/background-suite-guard.test.sh §B10) reads the
  # rule itself rather than a paraphrase of it.
  case "$_sid" in ''|*[!A-Za-z0-9_-]*) BIONIC_SID=""; return 1 ;; esac
  BIONIC_SID="$_sid"

  # 5. ENGAGEMENT, AS A VALUE.
  if engaged_session "$BIONIC_ROOT" "$BIONIC_SID"; then
    BIONIC_ENGAGED=1
  else
    BIONIC_ENGAGED=0
  fi

  # 6. THE RUN VERDICT, AS A VALUE. `session_run` returns 2 on `bound-closed` and
  # 1 on `none`; both are identified sessions, so neither may become this
  # function's return code.
  _verdict="$(session_run "$BIONIC_ROOT" "$BIONIC_SID" 2>/dev/null)" || :
  BIONIC_RUN_WORD="${_verdict%% *}"
  case "$_verdict" in
    *\ *) BIONIC_RUN_PLAN="${_verdict#* }" ;;
    *)    BIONIC_RUN_PLAN="" ;;
  esac

  return 0
}
