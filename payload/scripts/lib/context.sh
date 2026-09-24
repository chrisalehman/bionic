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
# THE EIGHT VALUES. Every one is a VALUE the caller reads, never an action:
#
#   BIONIC_INPUT      the payload text, read from stdin at most once
#   BIONIC_CWD        the ONE ladder (below)
#   BIONIC_ROOT       project_root "$BIONIC_CWD"
#   BIONIC_SID        the session id, past the ONE shape guard
#   BIONIC_ENGAGED    0 or 1
#   BIONIC_RUN_WORD   bound-open | bound-closed | bound-unreadable | fallback | none — or
#                     the sentinel `unset` when the caller did not ask for it (§6)
#   BIONIC_RUN_PLAN   the plan path the verdict names; empty for `none` and for
#                     the `unset` sentinel
#   BIONIC_WORKTREE   the linked worktree the root was mapped from, empty when
#                     the walk mapped none (epic-23 wave-14 REQ-2, spec D5)
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
# THE RUN VERDICT IS OPT-IN (epic-23 wave-14 REQ-4, spec D5): it is computed only
# when the caller set `BIONIC_CONTEXT_WANT_RUN=1` before the call, and otherwise
# BIONIC_RUN_WORD is the sentinel `unset` — a word outside the verdict vocabulary,
# so a reader that meets it cannot mistake it for `none`. §6 carries the reasoning
# and the list of callers that ask.
#
# THE RUN VERDICT IS A VALUE for a sharper reason (census §4.2, T10-pins §5.5).
# The four hooks carrying the 4-branch `case` do DIFFERENT things on
# `bound-closed`: two exit 0, two blank the plan and continue, the governing skill
# prints a line and falls through, and the evidence gate treats it as
# `bound-open`. A library that acted on the verdict would silently change four
# hooks; one that reports it changes none. So `bound-closed` returns 0 here like
# any other identified session, and the `case` stays in the caller.
#
# ONE LADDER (REQ-1h, AC-1h.1; user ruling 2026-09-12 "1, go with unify",
# corrected by critic Issue 2 / A-85). The census measured SEVEN cwd ladders across
# the fifteen. They are one now:
#
#   1. $CLAUDE_PROJECT_DIR, if set and it names a PROJECT
#   2. else the payload's `.cwd`, if a directory
#   3. else `pwd`
#
# EACH RUNG TESTS FOR A DIRECTORY AND NOT MERELY FOR A VALUE. A ladder that
# stopped at `-n` would answer with a path that does not exist and hand
# `project_root` a walk from nowhere — which is the fail-dangerous direction, since
# the walk would then answer about whatever directory the hook happened to be in.
#
# AND RUNG 1 TESTS FOR A PROJECT, NOT MERELY FOR A DIRECTORY, WHICH IS THE
# DIRECTION A WALL MUST FAIL IN (critic Issue 2, A-85). A session launched outside
# a bionic project and then worked inside one keeps CLAUDE_PROJECT_DIR at the
# LAUNCH directory while the payload's `.cwd` is the project — the ordinary
# two-repos day. A rung 1 that asked only `-d` took the launch directory;
# `project_root` never answers empty (root.sh falls back to the git toplevel, else
# the cwd), so the walk succeeded, found no engagement marker under that root, and
# BIONIC_ENGAGED came back 0 — which fourteen callers spell `|| exit 0`. One
# environment variable silenced all five Bash walls and all four turn-end verdicts
# at once: `push refused, rc 2` became silence and rc 0, measured. Nine of the
# fifteen pre-fold hooks recovered through `.cwd` and stayed armed, so this was a
# REGRESSION against the base, not merely a permissive reading.
#
# THE TEST IS root.sh's TERMINAL TAG, not `-d .bionic`: `project_root_candidates`
# ends in `chosen` exactly when a real `.bionic` was found, and in
# `git-toplevel-fallback` or `cwd-fallback` when none was. So a directory NESTED
# inside a project still wins rung 1 and still resolves to the root, and only a
# path with no project above it falls through. The walk is made ONCE — the chosen
# path is the root, so accepting the rung costs no second `project_root` call, and
# refusing it costs one walk on a path that was going to be refused anyway.
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
#
# ONE FORK FOR THE WHOLE ROSTER (REQ-10, T11). The line above is still the
# answer for any expression this file does not know; what changed is that the
# dozen expressions the hooks actually ask for are read by ONE `jq` and served
# from shell variables afterwards. T10 measured the cost being cut: library
# parsing is ~12–14% of a hook's runtime and external forks are the rest, at
# 5–8 ms each — `hooks/bash-walls.sh` asked `jq` seven times about one payload
# it had already read into memory, and `hooks/stop.sh` asked eight.
#
# THE FILL IS EAGER AND IT HAPPENS IN `bionic_context`, NEVER HERE. Almost every
# call site spells `X=$(bionic_jq .field)`, and a cache filled inside that
# command substitution dies with the subshell — the next field would refill it,
# and the hook would pay MORE forks than before, not fewer. `bionic_context`
# runs in the hook's own shell (`bionic_context 2>/dev/null || exit 0`), so the
# fill it performs is visible to every later subshell. A hook that never calls
# `bionic_context` never fills, and every read it makes forks exactly as it did
# before this change.
#
# THE FALLBACK IS THE WHOLE SAFETY ARGUMENT. `_bionic_jq_fill` writes one line
# per roster entry and then a sentinel; if the sentinel is not where it is
# expected — an embedded newline in a value, a payload jq cannot parse, an
# expression that errors on this shape of input — the cache is marked `bad` and
# every read falls through to the per-call fork above. The cache can therefore
# only ever be a speed-up: it is consulted when it is known-good and ignored
# otherwise, and no value is ever synthesised.
#
# THE ROSTER DELIBERATELY OMITS `.tool_input.command`. It is the one payload
# field that routinely carries newlines (a heredoc, a multi-line pipeline), and
# a line-oriented record cannot hold it without an escaping scheme this file
# would then have to reverse. The two hooks that need it read it once, above the
# loader, for `loader_fail_closed`'s allowlist (R1) — so it is already read
# exactly once without any help from here.
_BIONIC_JQ_STATE=""
_BIONIC_JQ_END="__bionic_jq_end__"

# Each entry below is a jq expression the roster serves, paired with the shell
# variable that holds it. The `s()` wrapper reproduces `<expr> // empty`
# exactly: null and false become the empty string, everything else is its own
# string. The three entries that do NOT go through `s()` are spelled out as
# their call sites spell them — `|tostring` renders an absent
# `run_in_background` as the literal `null`, which is what the uncached read
# has always returned, and the two `background_tasks` reads are the payload
# questions `payload/scripts/lib/stop.sh` used to ask with its own private `jq`.
_bionic_jq_fill() {
  local _out _rest _line
  _BIONIC_JQ_STATE=bad
  [ -n "${BIONIC_INPUT:-}" ] || return 1
  _out=$(printf '%s' "$BIONIC_INPUT" | jq -r '
    def s(f): (try f catch null) as $v
      | if ($v == null or $v == false) then "" else ($v | tostring) end;
    s(.cwd),
    s(.session_id),
    s(.hook_event_name),
    s(.tool_name),
    s(.agent_type),
    s(.agent_id),
    s(.transcript_path),
    s(.stop_hook_active),
    ((try (.tool_input.run_in_background) catch null) | tostring),
    (if (try (has("background_tasks")) catch false) then "yes" else "" end),
    ((try ([.background_tasks[]?.id // empty] | join("|")) catch "") | tostring),
    "'"$_BIONIC_JQ_END"'"
  ' 2>/dev/null) || return 1

  # SPLIT BY PARAMETER EXPANSION, not by `read`: a here-string opens a temp file
  # per read and a pipeline would put the assignments in a subshell. Twelve
  # builtin expansions cost nothing measurable and stay in this shell.
  _rest="$_out"
  _BIONIC_JQ_CWD="${_rest%%$'\n'*}"       ; _rest="${_rest#*$'\n'}"
  _BIONIC_JQ_SID="${_rest%%$'\n'*}"       ; _rest="${_rest#*$'\n'}"
  _BIONIC_JQ_EVENT="${_rest%%$'\n'*}"     ; _rest="${_rest#*$'\n'}"
  _BIONIC_JQ_TOOL="${_rest%%$'\n'*}"      ; _rest="${_rest#*$'\n'}"
  _BIONIC_JQ_AGENTTYPE="${_rest%%$'\n'*}" ; _rest="${_rest#*$'\n'}"
  _BIONIC_JQ_AGENTID="${_rest%%$'\n'*}"   ; _rest="${_rest#*$'\n'}"
  _BIONIC_JQ_TRANSCR="${_rest%%$'\n'*}"   ; _rest="${_rest#*$'\n'}"
  _BIONIC_JQ_STOPACT="${_rest%%$'\n'*}"   ; _rest="${_rest#*$'\n'}"
  _BIONIC_JQ_BG="${_rest%%$'\n'*}"        ; _rest="${_rest#*$'\n'}"
  _BIONIC_JQ_HASBT="${_rest%%$'\n'*}"     ; _rest="${_rest#*$'\n'}"
  _BIONIC_JQ_BTIDS="${_rest%%$'\n'*}"     ; _rest="${_rest#*$'\n'}"
  _line="${_rest%%$'\n'*}"

  # THE SENTINEL IS THE CHECK. Eleven values plus this line is the whole record;
  # anything else means a value carried a newline (or jq wrote nothing at all),
  # and a cache that cannot prove its own alignment must not be read.
  [ "$_line" = "$_BIONIC_JQ_END" ] || return 1
  _BIONIC_JQ_STATE=ok
}

bionic_jq() {
  if [ "${_BIONIC_JQ_STATE:-}" = ok ]; then
    case "$1" in
      .cwd)             printf '%s' "$_BIONIC_JQ_CWD" ; return 0 ;;
      .session_id)      printf '%s' "$_BIONIC_JQ_SID" ; return 0 ;;
      .hook_event_name) printf '%s' "$_BIONIC_JQ_EVENT" ; return 0 ;;
      .tool_name)       printf '%s' "$_BIONIC_JQ_TOOL" ; return 0 ;;
      .agent_type)      printf '%s' "$_BIONIC_JQ_AGENTTYPE" ; return 0 ;;
      .agent_id)        printf '%s' "$_BIONIC_JQ_AGENTID" ; return 0 ;;
      .transcript_path) printf '%s' "$_BIONIC_JQ_TRANSCR" ; return 0 ;;
      .stop_hook_active) printf '%s' "$_BIONIC_JQ_STOPACT" ; return 0 ;;
      '.tool_input.run_in_background|tostring')
                        printf '%s' "$_BIONIC_JQ_BG" ; return 0 ;;
      'if has("background_tasks") then "yes" else empty end')
                        printf '%s' "$_BIONIC_JQ_HASBT" ; return 0 ;;
      '[.background_tasks[]?.id // empty] | join("|")')
                        printf '%s' "$_BIONIC_JQ_BTIDS" ; return 0 ;;
    esac
  fi
  printf '%s' "${BIONIC_INPUT:-}" | jq -r "$1 // empty" 2>/dev/null
}

# ─── The one preamble ────────────────────────────────────────────────────────
#
# bionic_context -> sets the eight values; 0 when the session is identified, 1
# when it is not. Silent on both streams either way, because fourteen of the
# fifteen callers turn a 1 into `exit 0` and a bystander session must not learn
# that bionic is installed.
#
# THE ORDER IS CWD, ROOT, SID, ENGAGEMENT, RUN, and the two early returns are
# placed so that a caller reading a value after a failure reads an honest one:
# BIONIC_CWD is assigned before the root can fail, and BIONIC_SID is blanked
# before the guard returns.
bionic_context() {
  local _pcwd _sid _verdict _cands _last _root=""

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

  # 1b. THE PAYLOAD'S FIELDS, ONCE (REQ-10, T11). One `jq` for the whole roster,
  # here in the caller's own shell so every later `$(bionic_jq …)` reads a
  # variable instead of forking. A failure is not an error: `_bionic_jq_fill`
  # marks the cache unusable and `bionic_jq` forks per read exactly as it did
  # before, so nothing below this line depends on it succeeding.
  _bionic_jq_fill || :

  # 2. THE ONE LADDER. Rung 1 asks for a PROJECT (see the docblock); the walk it
  # makes is the same walk rung 3 would make, so it is kept rather than repeated.
  BIONIC_CWD=""
  if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -d "${CLAUDE_PROJECT_DIR:-}" ]; then
    # THE TERMINAL LINE, READ BY EXPANSION RATHER THAN BY `awk` (REQ-10, T11).
    # `project_root_candidates` emits exactly two tab-separated fields per line
    # (lib/root.sh's `_bionic_root_report`), and the rung takes the LAST line and
    # accepts it only when its tag is `chosen` — which is what the `awk -F'\t'
    # END` block said and what the three expansions below say. A line carrying no
    # tab is not a report line and is refused, as `$2 == "chosen"` refused it.
    # Rung 1 is the rung the CLI actually takes, so this fork was paid on every
    # hook event of every session.
    # NOT A COMMAND SUBSTITUTION (REQ-2). The walk also publishes BIONIC_WORKTREE
    # in the shell it runs in (lib/root.sh), and a `$(…)` is a subprocess: the
    # eighth value would be born and die inside it. The report is taken from the
    # return channel instead and the printed copy is discarded — `printf` to
    # /dev/null is a builtin, so this costs nothing the substitution did not.
    project_root_candidates "$CLAUDE_PROJECT_DIR" >/dev/null 2>&1
    _cands="${_BIONIC_ROOT_REPORT%$'\n'}"
    _last="${_cands##*$'\n'}"
    case "$_last" in
      *$'\t'*) [ "${_last#*$'\t'}" = "chosen" ] && _root="${_last%%$'\t'*}" ;;
    esac
    [ -n "$_root" ] && BIONIC_CWD="$CLAUDE_PROJECT_DIR"
  fi
  if [ -z "$BIONIC_CWD" ]; then
    _root=""
    _pcwd="$(bionic_jq .cwd)"
    if [ -n "$_pcwd" ] && [ -d "$_pcwd" ]; then
      BIONIC_CWD="$_pcwd"
    else
      BIONIC_CWD="$(pwd)"
    fi
  fi

  # 3. THE ROOT. On rungs 2 and 3 this is byte-for-byte the reading the library
  # shipped with — `project_root` returns 0 whatever it finds, so the emptiness is
  # the test and the walk's own fallbacks are honoured exactly as before. On rung 1
  # the root is the `chosen` path the rung already walked to.
  if [ -n "$_root" ]; then
    BIONIC_ROOT="$_root"
  else
    # Same shape, same reason as rung 1: in the caller's shell, so the walk's
    # BIONIC_WORKTREE survives it. `project_root` returns 0 whatever it finds, so
    # an empty answer is still the test, exactly as the substitution's was.
    project_root "$BIONIC_CWD" >/dev/null 2>&1
    BIONIC_ROOT="$_BIONIC_ROOT_ANSWER"
  fi
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

  # 6. THE RUN VERDICT, AS A VALUE — AND ONLY FOR A CALLER THAT ASKED FOR IT
  # (epic-23 wave-14 REQ-4, spec D5 "Hook context"). `session_run` returns 2 on
  # `bound-closed` and 1 on `none`; both are identified sessions, so neither may
  # become this function's return code.
  #
  # WHY IT IS OPT-IN. This is the most expensive value the preamble computes —
  # the scan walks every candidate under `plans/` and `incidents/` and reads each
  # one, measured at 28.0 ms on a one-plan fixture and growing ~2.8 ms per plan
  # the repo accumulates (research R3 §6-§7). `payload/scripts/lib/walls.sh`
  # holds ZERO references to either variable, so on the hottest path in the tree
  # — a PreToolUse Bash call, five walls — every millisecond of it was spent on
  # an answer nobody read.
  #
  # THE SENTINEL IS NOT THE EMPTY STRING, and that is the whole safety of this
  # cut. `none` is a real verdict ("this session is in no run"); an unasked
  # verdict is a different state, and a wall written later that read an empty
  # string where it expected a word would silently take the `none` branch — the
  # fail-dangerous direction, and one no test would catch because the value LOOKS
  # answered. `unset` is outside the closed verdict vocabulary
  # (bound-open | bound-closed | fallback | none), so a `case` over it falls to
  # its own `*)` arm and a comparison against any real verdict fails.
  #
  # A CALLER THAT WANTS THE VERDICT SETS `BIONIC_CONTEXT_WANT_RUN=1` BEFORE THE
  # CALL. Today that is the three hooks whose own bodies or libraries branch on
  # it: hooks/stop.sh (lib/stop.sh's spend, patrol-duties and patrol-revive),
  # hooks/dispatch-preflight.sh and hooks/session-start.sh. A hook that starts
  # reading the verdict sets the flag too — and reads `unset` as "I did not ask",
  # never as "no run".
  if [ "${BIONIC_CONTEXT_WANT_RUN:-0}" = 1 ]; then
    _verdict="$(session_run "$BIONIC_ROOT" "$BIONIC_SID" 2>/dev/null)" || :
    BIONIC_RUN_WORD="${_verdict%% *}"
    case "$_verdict" in
      *\ *) BIONIC_RUN_PLAN="${_verdict#* }" ;;
      *)    BIONIC_RUN_PLAN="" ;;
    esac
  else
    BIONIC_RUN_WORD="unset"
    BIONIC_RUN_PLAN=""
  fi

  return 0
}
