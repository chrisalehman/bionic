#!/bin/bash
# SESSION SWEEPER — the landing verdict, and the ack that closes a row.
# Design: .bionic/docs/specs/epic-16-landing-contract/wave-02-fact-based-supervision.spec.md
#         §Design ("Deletion inventory"), succeeding epic-15 wave-04's watcher design.
# [WALL: tests/session-sweeper.test.sh]
#
# This is NOT a hook. Like hooks/preflight-probe.sh it lives in hooks/ for test-harness
# pairing and to ride the payload's hooks/ directory into the mounted plugin; it is
# registered on NO channel. It is
# invoked on demand, one question per invocation, and it holds no process open:
#
#     bash ~/.claude/hooks/session-sweeper.sh verdict [<name>]
#     bash ~/.claude/hooks/session-sweeper.sh ack <name> [<name> ...]
#
# WHAT IT IS, since epic-16 wave-02: A READ OF DISK STATE, taken at the moment a decision
# needs one. It used to be a resident watcher as well — one long-lived process per session,
# sleeping on a tick, reporting by exiting. That half is deleted, and residency rather than
# its implementation is why: a resident process can be disowned, killed, or left dormant,
# every one of those failures is silent, and supervision that depends on staying alive
# reports nothing exactly when it matters most. A fact on disk cannot die that way. Nothing
# here has to stay running, stay armed, or stay configured for its answers to be correct.
#
# WHAT IT NEVER DOES. It never stops, kills, or judges an agent. It reports state facts: an
# artifact's presence, its substance, its date against a launch. The reading of those facts
# is the caller's, always.
#
# VERDICT asks whether a row's contract LANDED. Its states, in precedence order:
#
#     WAIVED      the brief waived this contract, and declared no artifact beside it
#     AMBIGUOUS   two or more contracts share this name; none of them is judged
#     MET         every declared artifact is on disk, non-empty, written after the launch
#     FOLLOW-UP   MET, but the orchestrator has sent the agent a message it has not answered
#                 (never a row the ack has already closed: a send after the close is ignored)
#     STILL-LIVE  not landed, but the row's own claimed process or progress says it is working
#     UNMET       declared, not delivered, nothing running
#
# AMBIGUOUS joined the set in wave-01's Step-6 review remediation (C-2).
#
# ACK is the orchestrator's completion event reaching the roster, and it exists because a
# roster row has no completion event of its own. An agent that finished but declared no
# machine-visible deliverable leaves nothing on disk to read; the orchestrator verifies
# every agent's completion anyway, and `ack` is that verification made durable, so a row it
# closed stays closed across sessions. It does NOT reach the verdict's STATE: a contract is
# met by artifacts or it is not, which is what lets an ack over an UNMET row WARN instead of
# quietly erasing the discrepancy. It DOES ride out beside that state, as `acked=` on the
# verdict machine line (epic-16 wave-02 S9) — a report of a second fact, never an input to
# the first. Before S9 the three stop-side scripts each opened this ledger through their own
# byte-identical copy of a reader; the ledger has ONE reader now, here, and everything
# downstream consumes a field on a line it was already asking for.
#
# FILES (all under .bionic/tmp/, all machine-local, all safe to delete):
#   roster-<session>.state   read-only input, schema roster-state/v1, owned by
#                            hooks/dispatch-preflight.sh
#   sweeper-<session>.state  the ledger this script owns (append-only)
#
# THE LEDGER is append-only and answers one question — which rows the orchestrator has
# closed — through one event:
#   ack — one row, closed by name.
#
# Exit codes:
#   0 — verdict found no UNMET row (including: no rows at all, or no row of that name);
#       ack recorded (ALWAYS, including a name no roster row carries)
#   1 — verdict found at least one UNMET row
#   2 — usage error, or a refusal (a state path is a symbolic link, or is unwritable)
#   3 — no session key; nothing read, nothing written
#
# Session key: CLAUDE_CODE_SESSION_ID, exactly as hooks/preflight-probe.sh takes it. Every
# actor in a fleet shares one session key (design D-3), which is why the roster this script
# reads and the ledger it writes are per-session rather than per-agent.
#
# Hostile-repo posture (design §8): a repo controls its own .bionic/ contents, so every
# path this script writes is checked for symlink redirection before anything is written.
# Registered on no channel — invoked on demand from the mounted plugin payload.

set -u

LEDGER_SCHEMA="sweeper-ledger/v1"
VERDICT_SCHEMA="landing-verdict/v1"
# Reader copy of hooks/dispatch-preflight.sh's roster constants (same precedent as
# hooks/preflight-probe.sh's copy: this script only ever READS roster files, so a prefix
# drift is a mislabeled scan, never a write hazard).
ROSTER_VERSION="v1"
ROSTER_PREFIX="roster-"
ROSTER_SUFFIX=".state"

# THIS SCRIPT'S OWN PATH, so the usage it prints names the copy the operator actually
# invoked — identical in a repo checkout, in a bootstrap-installed ~/.claude/hooks/, and in
# an installed plugin payload. Deliberately NOT ${CLAUDE_PLUGIN_ROOT}: this script is run by
# hand and by the harness outside any plugin context, where that variable does not exist.
HOOK_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
[ -n "$HOOK_DIR" ] || HOOK_DIR="$(dirname "$0")"
ACK_COMMAND="bash ${HOOK_DIR}/session-sweeper.sh ack"
VERDICT_COMMAND="bash ${HOOK_DIR}/session-sweeper.sh verdict"

say()  { printf 'sweeper: %s\n' "$1"; }
die()  { printf 'sweeper: %s\n' "$1" >&2; }

usage() {  # [message]
  [ $# -gt 0 ] && die "$1"
  die "Usage:"
  die "  $VERDICT_COMMAND [<name>]         did the contract land? (read-only)"
  die "  $ACK_COMMAND <name> [<name> ...] [--by human|patrol] [--reason <word>]"
  die "        close those rows: done, verified"
  exit 2
}

# ---------------------------------------------------------------- verb + flags

[ $# -ge 1 ] || usage "no verb given."
VERB="$1"; shift
VERDICT_NAME=""

# WHO CLOSED THE ROW, AND ON WHAT EVIDENCE (bionic 1.8.0, REQ-1 D2). An ack used to mean
# exactly one thing — the orchestrator verified this agent's completion by hand — and that is
# still the default, because a caller that names no author is a person at a terminal. What
# widened is the set of things that may close a row: the Patrol closes one whose contract is
# MET (or whose status is `duplicate-start`) once the panel no longer lists its agent, and
# `reason=moot-and-gone` is the evidence it read. Both ride the ledger line, because the
# ledger is the durable record of every row a session closed and "who closed this, and why"
# is the first question a reader asks of a row closed without its contract landing.
#
# NEITHER IS A SECOND CLASS OF ACK. The row is closed for every reader either way; the
# attribution is a fact about the ACT, never a qualifier on its effect.
ACK_BY="human"
ACK_REASON=""
ACK_NAMES=()
case "$VERB" in
  ack)
    [ $# -ge 1 ] || usage "ack needs at least one roster row name."
    # THE FLAGS ARE PARSED OFF, NOT LEFT IN "$@": the verb block walks the names, and a
    # caller that mistyped a flag must not quietly close a row called `--bye`.
    while [ $# -gt 0 ]; do
      case "$1" in
        --by)
          [ $# -ge 2 ] || usage "--by needs a value."
          case "$2" in
            human|patrol) ACK_BY="$2" ;;
            *) usage "--by takes human or patrol; got '$2'." ;;
          esac
          shift 2 ;;
        --reason)
          [ $# -ge 2 ] || usage "--reason needs a value."
          # ONE WORD, because it is read back by machine as often as by eye — the field is
          # a key on a `|`-delimited line, and a value carrying a space or a separator is a
          # value some later reader will split in the wrong place.
          case "$2" in
            ''|*[[:space:]]*|*"|"*) usage "--reason takes one word; got '$2'." ;;
            *) ACK_REASON="$2" ;;
          esac
          shift 2 ;;
        -*) usage "unknown argument: $1" ;;
        *) ACK_NAMES+=("$1"); shift ;;
      esac
    done
    [ "${#ACK_NAMES[@]}" -ge 1 ] || usage "ack needs at least one roster row name."
    ;;
  verdict)
    # ONE name at most, on purpose. `verdict a b` is far likelier to be a caller that meant
    # `ack a b` than a caller that wants two rows, and a verb whose exit code is a single
    # yes/no about the whole run has no honest answer to spell for an arbitrary subset. The
    # two shapes that exist are the whole session and one row.
    [ $# -le 1 ] || usage "verdict takes at most one roster row name; got $#."
    VERDICT_NAME="${1:-}"
    ;;
  *) usage "unknown verb: $VERB" ;;
esac

# ---------------------------------------------------------------- session key

# ---------- the library ----------
#
# One loader idiom, byte-identical in every hook (spec AC-16); its source of truth is
# payload/scripts/lib/loader.sh. FAIL OPEN: nothing this script does is irreversible,
# and a reporting verb that refused because a file was missing would take the
# diagnosis down with the thing being diagnosed.
BIONIC_LIB_WANT="roots.sh root.sh roster.sh session.sh"
# --- bionic-loader/v2 BEGIN
# Find the bionic library — pasted BYTE-IDENTICALLY into all 15 carriers, because a library
# cannot load itself. payload/scripts/lib/loader.sh owns this text and its header holds the
# long form; §N.1 of tests/cross-gate-agreement.test.sh pins and caps every copy, and
# tests/loader.test.sh drives the behaviour. BIONIC_LIB_WANT, set on the line above, names
# the basenames this hook sources; afterwards exactly one of BIONIC_LIB (a directory holding
# all of them) and BIONIC_LIB_MISSING is non-empty. CANDIDATES, each class reached only when
# the earlier one fails: (1) beside the hook in BOTH spellings, since `..` resolves after the
# payload/hooks symlink; (2) the marketplace source tree, read from the registry and never
# assumed; (3) the newest version in that marketplace's cache, by THREE-INTEGER compare —
# 1.10.0 beats 1.3.2, which a lexical sort gets backwards. (2) and (3) heal a partly damaged
# install, so one broken location cannot lock the user out of the repair (R-1 §(5)).
BIONIC_LIB=""; BIONIC_LIB_MISSING=""; BIONIC_LIB_CANDS=""
_bl_dir="$(dirname "$0")"; _bl_want="${BIONIC_LIB_WANT:-}"
_bl_try() {
  [ -n "${1:-}" ] || return 1
  if [ -z "$BIONIC_LIB_CANDS" ]; then BIONIC_LIB_CANDS="$1"; else BIONIC_LIB_CANDS="$BIONIC_LIB_CANDS, $1"; fi
  [ -d "$1" ] || return 1
  for _bl_f in $_bl_want; do [ -r "$1/$_bl_f" ] || return 1; done
  BIONIC_LIB="$1"
}
if ! _bl_try "$_bl_dir/../scripts/lib" && ! _bl_try "$_bl_dir/../payload/scripts/lib"; then
  _bl_pd="${BIONIC_PLUGINS_DIR:-${HOME:-/nonexistent}/.claude/plugins}"; _bl_mk=""
  if [ -r "$_bl_pd/installed_plugins.json" ]; then
    _bl_keys="$(jq -r '(.plugins // {}) | keys[] | select(startswith("bionic@"))' "$_bl_pd/installed_plugins.json" 2>/dev/null)"
    _bl_mk="${_bl_keys%%
*}"
    _bl_mk="${_bl_mk#bionic@}"
  fi
  if [ -n "$_bl_mk" ]; then
    _bl_src=""
    if [ -r "$_bl_pd/known_marketplaces.json" ]; then
      _bl_src="$(jq -r --arg mk "$_bl_mk" '.[$mk].source.path // empty' "$_bl_pd/known_marketplaces.json" 2>/dev/null)"
    fi
    if [ -n "$_bl_src" ]; then _bl_try "$_bl_src/payload/scripts/lib" || :; fi
    if [ -z "$BIONIC_LIB" ]; then
      _bl_best=""; _bl_bestk=""
      for _bl_v in "$_bl_pd/cache/$_bl_mk/bionic"/*; do
        [ -d "$_bl_v" ] || continue
        _bl_n="${_bl_v##*/}"
        case "$_bl_n" in ''|*[!0-9.]*) continue ;; esac
        _bl_x1=""; _bl_x2=""; _bl_x3=""
        IFS=. read -r _bl_x1 _bl_x2 _bl_x3 _bl_rest <<BIONIC_LOADER_VER
$_bl_n
BIONIC_LOADER_VER
        _bl_k="$(printf '%05d%05d%05d' "$((10#${_bl_x1:-0}))" "$((10#${_bl_x2:-0}))" "$((10#${_bl_x3:-0}))" 2>/dev/null)" || continue
        if [ -z "$_bl_bestk" ] || [ "$_bl_k" \> "$_bl_bestk" ]; then _bl_bestk="$_bl_k"; _bl_best="$_bl_n"; fi
      done
      if [ -n "$_bl_best" ]; then _bl_try "$_bl_pd/cache/$_bl_mk/bionic/$_bl_best/scripts/lib" || :; fi
    fi
  fi
fi
if [ -z "$BIONIC_LIB" ]; then
  BIONIC_LIB_MISSING="${_bl_want%% *}"
  [ -n "$BIONIC_LIB_MISSING" ] || BIONIC_LIB_MISSING="scripts/lib"
fi
loader_fail_open() {
  echo "$1: library ${BIONIC_LIB_MISSING:-the bionic library} not found at ${BIONIC_LIB_CANDS:-(no candidate)} — hook stepping aside; run /bionic:doctor" >&2
  exit 0
}
loader_fail_closed() {
  _bl_root="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd -P)" || _bl_root=""
  [ -n "$_bl_root" ] || _bl_root="$(dirname "$0")/.."
  case "${2:-}" in
    "claude plugin update bionic@bionic"|\
    "claude plugin install bionic@bionic"|\
    "bash $_bl_root/scripts/doctor.sh"|\
    "bash $_bl_root/scripts/setup.sh") exit 0 ;;
  esac
  _bl_who="${1:-a bionic hook}"
  if [ "${#_bl_who}" -gt 25 ]; then _bl_who="${_bl_who:0:24}…"; fi
  printf 'bionic: load refused — %s cannot load the bionic library (run /bionic:doctor)\n' "$_bl_who" >&2
  if [ "${BIONIC_WALL_VERBOSE:-}" = "1" ]; then
    cat >&2 <<BIONIC_LOADER_REFUSE
A wall that cannot read a command refuses it rather than waving it through.

Wanted: ${BIONIC_LIB_MISSING:-the bionic library}
Looked in: ${BIONIC_LIB_CANDS:-(no candidate)}

Until the plugin is whole again this wall permits exactly four commands, each matched
as a whole string:

    claude plugin update bionic@bionic
    claude plugin install bionic@bionic
    bash $_bl_root/scripts/doctor.sh
    bash $_bl_root/scripts/setup.sh

Anything else is refused, including one of those four with another command chained
after it. Run one of them, or act from your own terminal.
BIONIC_LOADER_REFUSE
  fi
  exit 2
}
# --- bionic-loader/v2 END
if [ -n "$BIONIC_LIB_MISSING" ]; then loader_fail_open "session-sweeper"; fi
# shellcheck source=/dev/null
. "$BIONIC_LIB/roots.sh"
. "$BIONIC_LIB/root.sh"
# THE ONE CLOSE PREDICATE (epic-23 wave-20 T2, D10): `roster_open_names`, which the `acked=`
# column asks so it answers what dispatch preflight, the stop wall and the tick's adopt answer.
# shellcheck source=/dev/null
. "$BIONIC_LIB/roster.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/session.sh"

# THE SESSION KEY, from the library (design §1): the environment value is primary. This
# script is invoked from a shell rather than by a hook payload, so there is no witness
# to disagree with — but the key it lands on has to be the same one the hooks that write
# the roster land on, and that is what asking the one reader buys.
SESSION_ID=$(session_id "" 2>/dev/null) || SESSION_ID=""
if [ -z "$SESSION_ID" ]; then
  die "REFUSED — no session key (CLAUDE_CODE_SESSION_ID is unset or empty)."
  die "Both verbs answer for ONE session's roster, so without the key there is nothing to"
  die "read and nothing to ledger. Run this from inside a Claude Code session."
  exit 3
fi

# ---------------------------------------------------------------- where state lives

# THE ROOT (spec AC-10, lib/root.sh). `rev-parse --show-toplevel` answers with whatever
# tree the SHELL stands in; inside a linked worktree that is not where the state lives,
# and the reader and the writer then disagree about which `.bionic` is real. This was a
# byte-identical private copy — one of eight — held together by an agreement suite;
# there is one answer now, and it maps a worktree onto its main repository before it
# walks for the nearest real `.bionic`.
REPO="$(project_root "$PWD")"
[ -n "$REPO" ] || REPO="$PWD"
REPO_REAL="$(cd "$REPO" 2>/dev/null && pwd -P)"
if [ -z "$REPO_REAL" ]; then
  die "REFUSED — cannot resolve the working directory."
  exit 2
fi

# ---------------------------------------------------------------- where artifacts live
#
# THE DOCS ROOT, AND WHY THIS HOOK SUDDENLY NEEDS ONE (epic-17 W6 S15, A-6.6 (c)).
# A roster deliverable is brief prose: `Expected artifact: record/epic-17-w6/x.md` is what
# every task brief in this epic actually writes, because that is the spelling the Step-5
# contract and `canonical-sdlc-evidence-gate.sh` established for an artifact under the docs
# root. This gate resolved it against the REPO root, looked at `<repo>/record/…`, found
# nothing, and reported the row missing while the file sat where the brief meant. One wave
# already answered that by writing a duplicate copy at the repo root to appease the gate,
# which is the failure mode of a gate that is wrong: it teaches the work to be wrong too.
#
# THE RULE COMES FROM lib/roots.sh's `docs_root` — one definition for the whole tree, held
# by tests/cross-gate-agreement.test.sh §Roots. This hook used to carry a copy of the
# evidence gate's `resolve_docs_root()`, one of four, agreeing by body comparison rather
# than by being one function (epic-22 wave-01, N1).

# THE PROJECT ROOT, UNDER THE EVIDENCE GATE'S NAME FOR IT — the names are kept because the
# two hooks answer the same question about the same shape of path.
# The VALUE is this hook's own and stays so: the gate folds a linked worktree back to the
# main repo (its artifacts are written there), while this hook answers for the roster in
# the tree it was run from. Same rule about which root a path is relative to; different
# root, deliberately.
PROJECT_DIR="$REPO_REAL"
DOCS_ROOT="$(docs_root "$PROJECT_DIR")"

BIONIC_DIR="$REPO_REAL/.bionic"
STATE_DIR="$BIONIC_DIR/tmp"
for _component in "$BIONIC_DIR" "$STATE_DIR"; do
  if [ -L "$_component" ]; then
    die "REFUSED — $_component is a symbolic link."
    die "The state directory must be a real directory inside the repo. Remove the link"
    die "and re-run; nothing was written."
    exit 2
  fi
done

ROSTER_FILE="$STATE_DIR/${ROSTER_PREFIX}${SESSION_ID}${ROSTER_SUFFIX}"
LEDGER_FILE="$STATE_DIR/sweeper-${SESSION_ID}.state"

if [ -L "$LEDGER_FILE" ]; then
  die "REFUSED — $LEDGER_FILE is a symbolic link; nothing was written through it."
  die "Remove it and re-run."
  exit 2
fi

# ---------------------------------------------------------------- portable facts
#
# DELIBERATELY DUPLICATED from hooks/stop-check.sh, byte for byte, for the reason the TDD
# gives (§9): a sourced library the installer misses is a silently inert gate. The
# copies are held together by tests/cross-gate-agreement.test.sh §I.1, which extracts
# file_mtime, line_field, claims_live and clean (stop-check.sh's mline_value) out of BOTH
# files and compares the bodies — a one-side edit goes red there.

file_mtime() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0; }

# One field out of a versioned pipe-delimited line, BY KEY, never by position. The roster
# writer's field ORDER has already differed between shipped rows (a `cadence=` was added
# mid-epic), so position would read the wrong value on a row this script did not author.
line_field() {  # <line> <key>
  printf '%s' "$1" | tr '|' '\n' | grep "^$2=" | head -1 | cut -d= -f2-
}

# Existence only. `pgrep -f` matches the full command line; a `ps` fallback covers a
# machine without it. Same function as hooks/stop-check.sh's, same reason for the copy.
claims_live() {  # <pattern>
  local pat="$1"
  if command -v pgrep >/dev/null 2>&1; then
    pgrep -f -- "$pat" >/dev/null 2>&1
    return $?
  fi
  ps -eo command 2>/dev/null | grep -qF -- "$pat"
}

now_epoch() { date -u +%s; }
iso_now()   { date -u +%Y-%m-%dT%H:%M:%SZ; }

iso_epoch() {  # <ISO-8601 Z> -> epoch seconds, empty if unreadable
  date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$1" +%s 2>/dev/null \
    || date -u -d "$1" +%s 2>/dev/null
}

# Values reaching a pipe-delimited record are roster-sourced prose and operator-supplied
# paths; a `|`, newline or control character inside one would forge a field. Normalized
# rather than refused, exactly as hooks/stop-check.sh normalizes its machine line.
#
# THE SECOND ARGUMENT IS THE POKER'S OWN ADDITION (T9, REQ-9), carried here so the two
# copies stay code-identical (tests/cross-gate-agreement.test.sh §O) — this file never
# calls clean() with one, since none of its own values are the list-valued fields
# (`suites_allowed=`, `files=`) the poker's `adopt_write_row` exempts from the cut. Every
# call in THIS file stays on the `*)` branch below, cut at 400 exactly as before.
#
# THE `re_executes` ARM IS CARRIED THE SAME WAY (T4, REQ-7/D4). The roster stores the
# declared runs percent-encoded — `payload/scripts/lib/roster.sh` owns that encoding and
# carries the reasoning — and the poker's `adopt_write_row` decodes them so its writer can
# encode them again. This file reads no such field, so the arm is inert here; it is present
# because the two copies are held identical as CODE, and a twin that drifted by one arm is
# the drift §O exists to catch.
clean() {  # <value>
  local out
  out="$(printf '%s' "$1" | tr '\n\r\t|' '    ' | sed -e 's/[[:cntrl:]]/ /g' -e 's/  */ /g' \
    -e 's/^ *//' -e 's/ *$//')"
  case "${2:-}" in
    suites_allowed|files) printf '%s' "$out" ;;
    re_executes)
      out="${out//\%7C/|}"
      printf '%s' "${out//\%25/%}" ;;
    *) printf '%s' "$out" | cut -c 1-400 ;;
  esac
}

# THE ONE RESOLUTION RULE, and it is not this file's (epic-17 W6 S15, A-6.S15.4). Body for
# body it is `resolve_walk_path()` in canonical-sdlc-evidence-gate.sh, which is the copy
# that documents the rule at its definition site and the copy every brief was written
# against: absolute stands; a value led by `record/` is docs-root-relative, because that is
# the spelling the Step-5 contract publishes; anything else is project-relative, so a
# fully-spelled `.bionic/docs/record/<file>.md` lands in the same place. Containment — a
# `..` that climbs out — is the CALLER's question, exactly as it is in the gate; this only
# resolves. tests/cross-gate-agreement.test.sh holds the three copies to one body.
abs_path() {  # <path, as the roster spells it> -> absolute
  case "$1" in
    /*)       printf '%s\n' "$1" ;;
    record/*) printf '%s/%s\n' "$DOCS_ROOT" "$1" ;;
    *)        printf '%s/%s\n' "$PROJECT_DIR" "$1" ;;
  esac
}

# ---------------------------------------------------------------- the prose parser
#
# `cadence=` and `duration=` are prose the dispatch gate lifted verbatim out of a brief:
# "every ~5 min", "20 minutes", "30–40 minutes". This reads the forms a brief actually
# uses and REFUSES everything else — a guessed threshold is a false alarm with a number
# in front of it, and the design's answer to an unreadable field is to drop the conjunct
# that needed it, never to invent a value.
#
# `cadence=` is the one field still read here, by row_still_live: fresh progress inside the
# declared cadence is what spares a mid-flight agent a false UNMET. `duration=` reaches this
# parser from nowhere in this script any more — it belonged to the deleted overdue
# predicate — and the form is kept parseable because the same prose still rides the roster.
#
# Deliberate limits, each one a refusal rather than a guess:
#   * exactly one number-unit pair. "1h30m" and "10 min, checkpoint at 5m" are refused.
#   * whole numbers only. "0.5h" is refused.
#   * a range ("30–40 minutes") is read at its GENEROUS end — the question is whether a
#     promise is broken, and it is not broken until the longer bound passes.
#   * zero is refused: a zero threshold would call every row late the instant it launched.
parse_seconds() {  # <prose> -> seconds on stdout; nonzero exit if it cannot be read
  local raw="$1" s pairs count nums hi unit mult n allnums
  [ -n "$raw" ] || return 1
  s="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')"
  s="${s//\~/ }"; s="${s//–/-}"; s="${s//—/-}"; s="${s//,/ }"
  pairs="$(printf '%s' "$s" \
    | grep -oE '[0-9]+([[:space:]]*-[[:space:]]*[0-9]+)?[[:space:]]*(hours?|hrs?|minutes?|mins?|seconds?|secs?|h|m|s)([^a-z0-9]|$)')"
  count="$(printf '%s\n' "$pairs" | grep -c '[0-9]')"
  [ "$count" -eq 1 ] || return 1
  nums="$(printf '%s' "$pairs" | grep -oE '[0-9]+')"
  hi=0
  for n in $nums; do [ "$n" -gt "$hi" ] && hi="$n"; done
  [ "$hi" -gt 0 ] || return 1
  unit="$(printf '%s' "$pairs" | grep -oE '[a-z]+' | tail -1)"
  case "$unit" in
    h|hr|hrs|hour|hours)         mult=3600 ;;
    m|min|mins|minute|minutes)   mult=60 ;;
    s|sec|secs|second|seconds)   mult=1 ;;
    *) return 1 ;;
  esac
  # REFUSE what `grep -oE` silently dropped rather than matched. It reports only what it
  # matched, so two failure shapes above look identical to a single clean pair:
  #   * a decimal point anywhere near a digit ("0.5h" matches the trailing "5h" and never
  #     sees the "0."; the header's "whole numbers only" is a refusal, not a truncation).
  #   * two pairs glued with no separator ("1h30m" — "1h" fails its own trailing-boundary
  #     check and is silently skipped, leaving only "30m" for `pairs` to find).
  # A decimal anywhere in the cleaned string fails outright; a mismatch between every digit
  # run in the string and the digit run(s) actually captured inside the matched pair catches
  # the glued case, because nothing legitimate is a digit run OUTSIDE the one pair.
  grep -qE '[0-9]+\.[0-9]+' <<< "$s" && return 1
  allnums="$(printf '%s' "$s" | grep -oE '[0-9]+')"
  [ "$(printf '%s\n' "$allnums" | grep -c '[0-9]')" -eq "$(printf '%s\n' "$nums" | grep -c '[0-9]')" ] \
    || return 1
  printf '%s' "$((hi * mult))"
}

# ---------------------------------------------------------------- the ledger

ledger_write() {  # <line> — append-only; the header is written once
  if [ ! -e "$LEDGER_FILE" ]; then
    printf '# bionic session sweeper ledger — schema %s — machine-local, safe to delete\n' \
      "$LEDGER_SCHEMA" >> "$LEDGER_FILE" 2>/dev/null && chmod 600 "$LEDGER_FILE" 2>/dev/null
  fi
  printf '%s\n' "$1" >> "$LEDGER_FILE" 2>/dev/null
}

# How many ledger lines carry a pattern. Every count goes through here so the answer is ONE
# LINE BY CONSTRUCTION, because `grep -c` is a trap for the obvious idiom: it prints its
# count on stdout AND exits 1 when that count is zero, so a `|| printf 0` fallback appends a
# second line to an answer grep already gave. The resulting two-line "0" reaches an integer
# test, which rejects it on stderr while the surrounding `if` reads false and the verb
# carries on — a live ack succeeded and complained at the same time (2026-08-07). Here
# grep's exit status is discarded and only an all-digits answer is believed; an unreadable
# file prints nothing, which is zero of them.
ledger_count() {  # <pattern> -> a single integer, on stdout
  local n
  n="$(grep -c -- "$1" "$LEDGER_FILE" 2>/dev/null)"
  case "$n" in
    ''|*[!0-9]*) n=0 ;;
  esac
  printf '%s' "$n"
}

# The ledger's answer: which names the orchestrator has acked, and — through the one close
# predicate — which roster rows those acks actually close. Re-read on every invocation rather
# than cached anywhere, because the file is the only durable copy — an ack taken in a session
# that has since died is still in force in its successor.
#
# AN ACK CLOSES THE ROW IT POSTDATES, NOT THE NAME FOREVER (epic-23 wave-20 T2, D10).
# `ACKED_NAMES` is the ledger's fact — every name an ack was ever journalled for, which is
# what the ack verb counts and reports. `ACKED_OPEN` is `roster_open_names`
# (payload/scripts/lib/roster.sh) over this session's roster and this ledger: the names
# still under contract, because no ack was taken after their latest live launch. A row is
# acked when its name was acked AND it is not still open — so a name acked and then
# dispatched again reads `acked=no` here, as it reads open to dispatch preflight, the stop
# wall's occupancy and the tick's `adopt_fold`, which all ask the same predicate.
ACKED_NAMES=""; ACKED_COUNT=0; ACKED_OPEN=""; ACKED_READ=0
read_acked() {
  ACKED_NAMES=""; ACKED_COUNT=0; ACKED_OPEN=""; ACKED_READ=1
  [ -f "$LEDGER_FILE" ] || return 0
  [ -L "$ROSTER_FILE" ] || ACKED_OPEN="$(roster_open_names "$ROSTER_FILE" "$LEDGER_FILE" "$SESSION_ID")"
  local line ev n
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in "$LEDGER_SCHEMA|"*) : ;; *) continue ;; esac
    ev="$(line_field "$line" event)"
    [ "$ev" = "ack" ] || continue
    n="$(line_field "$line" name)"
    # VALIDATE BEFORE BELIEVING a value out of this repo-controlled file. The shape that
    # matters is the EMPTY one: every row carries a name (`(unnamed)` when the roster
    # declared none), and an empty entry compared loosely would read as closing the whole
    # roster at once, in silence. Dropped, and a truncated write is the likelier author of
    # one than an adversary. Names are cleaned at write time, so no entry here can carry a
    # `|` or a newline to forge a field.
    [ -n "$n" ] || continue
    [ -n "$ACKED_NAMES" ] && grep -qxF -- "$n" <<< "$ACKED_NAMES" && continue
    ACKED_NAMES="${ACKED_NAMES}${n}
"
    ACKED_COUNT=$((ACKED_COUNT + 1))
  done < "$LEDGER_FILE"
}

# THE LATEST ACK OF ONE NAME, for a sentence and never for a decision (wave-20 T9b). Whether
# the name is closed is `row_acked`'s answer, which is `roster_open_names`'; this only says
# when and by whom, so a detail can name the close a follow-up was ignored against. One awk
# pass, run only on that rare path: `at by reason`, space-separated, empty when none reads.
# The name reaches awk through ENVIRON, never `-v`, which reads backslashes as escapes, and the
# ledger on stdin, never as an operand, which awk reads as an assignment when it holds a `=`.
ack_stamp_of() {  # <name> -> "<at> <by> <reason>" of its latest well-formed ack
  [ -f "$LEDGER_FILE" ] && [ ! -L "$LEDGER_FILE" ] || return 0
  SWEEP_ACK_NAME="$1" awk -F'|' '
    index($0, "sweeper-ledger/v1|") == 1 {
      ev = ""; nm = ""; at = ""; by = ""; rs = ""
      for (i = 2; i <= NF; i++) {
        k = substr($i, 1, index($i, "=") - 1); v = substr($i, index($i, "=") + 1)
        if (k == "event") ev = v; else if (k == "name") nm = v; else if (k == "at") at = v
        else if (k == "by") by = v; else if (k == "reason") rs = v
      }
      if (ev == "ack" && nm == ENVIRON["SWEEP_ACK_NAME"] && at != "" && at "" >= best "") {
        best = at; line = at " " by " " rs
      }
    }
    END { if (line != "") print line }' < "$LEDGER_FILE" 2>/dev/null
}

# Whole-line match, never a substring: `w4-s1` must not be closed by an ack of `w4-s10`.
# Acked AND not still open (read_acked's header): an ack older than the row's latest launch
# closes nothing.
row_acked() {  # <row name>
  # BOTH operands are guarded, and the second guard is the here-string's (T37). `<<<`
  # appends a newline to its word, so a ledger ending in one presents a trailing EMPTY
  # line that `grep -qxF -- ""` matches — where the `printf '%s' | grep` this replaced
  # emitted no such line and answered 1. An empty row name is not an acked row.
  [ -n "$ACKED_NAMES" ] || return 1
  [ -n "$1" ] || return 1
  grep -qxF -- "$1" <<< "$ACKED_NAMES" || return 1
  [ -n "$ACKED_OPEN" ] || return 0
  ! grep -qxF -- "$1" <<< "$ACKED_OPEN"
}

# Every name the roster declares, one per line. Read for the ack verb's "is this a row I
# know about?" warning only — never for judging, which reads whole rows. A symlinked
# roster is not read here either (§8), so an ack against one warns and records rather than
# claiming the name is unknown on evidence it never had.
roster_names() {
  [ -L "$ROSTER_FILE" ] && return 0
  [ -f "$ROSTER_FILE" ] || return 0
  local line
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in "roster-state/${ROSTER_VERSION}|"*) : ;; *) continue ;; esac
    line_field "$line" name
  done < "$ROSTER_FILE"
}

# ---------------------------------------------------------------- the landing verdict
#
# THE LANDING QUESTION. `verdict` asks whether a row's contract LANDED, and it is now the
# ONLY delivered-predicate this script owns. Until epic-16 wave-02 there was a second, looser
# one beside it — the deleted watch loop's exists-and-non-empty satisfied-check, which
# answered a different question (is this row worth waking someone for?) and was carried at a
# weaker reading on purpose while the strict one earned field proof. It has that proof now,
# and the loose reading died with the loop rather than being promoted into it.
#
# THE DIVERGENCES ARE NAMED, all of them — a comment that under-reports one is worse than
# no comment, because the next reader trusts it (wave-01 Step-6 architecture review A-1).
# hooks/stop-check.sh renders a SECOND reading of the same fact (`[ -f ]` ∧ size > 0) in its
# operator-facing evidence, and the two disagree on exactly these, and nowhere else:
#   staleness   landing requires mtime AFTER the row's own launched_at; the evidence line
#               does not date the artifact at all.
#   symlinks    landing refuses a symlinked deliverable on BOTH its branches (a contract
#               satisfied by `ln -s` is satisfied with zero bytes written, review S-3); the
#               evidence line follows the link.
#   waiver      landing reads `waiver=`; the evidence line does not.
#   no declared deliverable
#               landing calls such a row MET vacuously (assumption 9).
# stop-check.sh blocks nothing on its reading; this one is what the landing gate consumes.
# tests/cross-gate-agreement.test.sh §I.2 asks BOTH on one set of fixtures and compares
# their answers to each other, so the next divergence goes red whichever side moves.
#
# IT WRITES NOTHING. No ledger entry, no roster row — a verdict is a read of the disk, and
# the caller (hooks/landing-gate.sh, or an orchestrator answering an idle ping) owns every
# consequence of it. ADR-003's zero-authority rule reaches its end here: this verb cannot
# even record that it ran, which is what makes it safe to call from a hook on every
# subagent stop.
#
# THE ACK DOES NOT REACH THE STATE. An ack is the orchestrator saying "I verified this agent
# finished" — a fact about the verification, not about the disk. A contract is met by
# artifacts or it is not, so `verdict` re-reads the disk for an acked row exactly as for any
# other. That separation is what lets `ack` warn on an UNMET row instead of quietly erasing
# the discrepancy.
#
# IT DOES REACH THE LINE, as `acked=yes|no` beside the state (epic-16 wave-02 S9). Two facts,
# spelled separately, computed independently, carried together — because every consumer of
# this line needs both and none of them should have to open the ledger to get the second.
# The exit code is the state's alone: an acked UNMET row still exits 1, exactly as it did
# when the callers read the ledger themselves, and what to do about the pair stays theirs.

epoch_iso() {  # <epoch seconds> -> ISO-8601 Z; empty when it cannot be rendered
  [ -n "$1" ] || return 0
  date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null
}

# The delivered predicate, ONE declared path at a time (AC-4). Every outcome names its
# conjunct in the caller's readback — `delivered=`, `missing=`, `empty=`, `stale=` — because
# a bare "not delivered" tells a stopping agent nothing it can act on, and this string IS
# the refusal text the landing gate prints back to it.
# THE DIRECTORY BRANCH IS BOUNDED, in both directions, and the bound is not a tuning knob.
# A deliverable path comes off a roster row, which comes off brief prose: `Expected
# artifact: /usr/share` is one ordinary line away from any brief, and this predicate runs
# from the Stop-sweep (`hooks/landing-gate.sh`, invoked on the harness's Stop event — a
# SubagentStop-registered wall never runs at all, t4b-probe-report.md §3) on every sweep.
# Unbounded, that row cost 86 s of filesystem walk per stop (Step-6 review C-3). The cap on how many files are stat'd also caps the walk
# itself — `head` closes the pipe and `find` stops — so a huge or non-repo directory cannot
# stall the gate whatever path a row names.
LANDING_DIR_MAXDEPTH=8
LANDING_DIR_SCAN_CAP=200

CONJUNCT=""
landing_conjunct() {  # <path, as the roster spells it> <launched epoch|""> <launched ISO>
  local raw="$1" le="$2" liso="$3" p mtime newest f count=0 capped=0
  CONJUNCT=""
  # A `..` COMPONENT IS REFUSED, not normalized — the same call the evidence gate makes
  # about a walk artifact, taken at the same place: in the caller, over the raw value.
  # A relative deliverable that climbs out of the root it is relative to is a placement
  # error whatever it happens to land on, and normalizing it would hide which root the
  # brief meant.
  if grep -qE '(^|/)\.\.(/|$)' <<< "$raw"; then
    CONJUNCT="refused=$raw (a deliverable path may not climb out of the project with '..' — name it as record/<file>, a project-relative path, or an absolute one)"
    return 1
  fi
  p="$(abs_path "$raw")"
  # A SYMBOLIC LINK IS NOT A DELIVERED ARTIFACT — asked FIRST, so both branches below are
  # held to one answer. The file branch used to follow the link ([ -e ], [ -s ] and stat all
  # resolve) while the directory branch did not (`find -type f` skips links), so `ln -s`
  # satisfied a file contract with zero bytes written and satisfied nothing inside a
  # directory one (Step-6 review S-3). Refusing is the direction that agrees with what a
  # landed artifact means: bytes this agent wrote, at a path the brief named.
  if [ -L "$p" ]; then
    CONJUNCT="symlink=$raw (a symbolic link is not a delivered artifact — write a real file)"
    return 1
  fi
  if [ -d "$p" ]; then
    # A directory deliverable is delivered when a FILE lives in it, and its clock is the
    # newest file it holds. The count is not decoration: `[ -s <dir> ]` is true for an empty
    # directory on both BSD and GNU, so a size test alone would read a freshly-created
    # directory as landed work. ONE traversal answers both halves — the count and the clock
    # — where two used to.
    newest=0
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      count=$((count + 1))
      mtime="$(file_mtime "$f")"
      case "$mtime" in ''|*[!0-9]*) mtime=0 ;; esac
      [ "$mtime" -gt "$newest" ] && newest="$mtime"
    done < <(find "$p" -maxdepth "$LANDING_DIR_MAXDEPTH" -type f 2>/dev/null \
             | head -n "$LANDING_DIR_SCAN_CAP")
    if [ "$count" -eq 0 ]; then
      CONJUNCT="empty=$raw"; return 1
    fi
    [ "$count" -ge "$LANDING_DIR_SCAN_CAP" ] && capped=1
    mtime="$newest"
  elif [ -e "$p" ]; then
    if [ ! -s "$p" ]; then
      CONJUNCT="empty=$raw"; return 1
    fi
    mtime="$(file_mtime "$p")"
  else
    CONJUNCT="missing=$raw"; return 1
  fi
  # A TRUNCATED WALK CANNOT DATE THE DELIVERY, so it does not try: the newest file it saw is
  # not the newest file there is, and judging staleness from it would refuse a stop on a
  # partial answer. The conjunct is DROPPED and the detail says so — assumption 13's rule
  # for an unreadable launched_at, reached from the other side.
  if [ "$capped" -eq 1 ]; then
    CONJUNCT="delivered=$raw (directory scan capped at $LANDING_DIR_SCAN_CAP files: not judged for staleness)"
    return 0
  fi
  # STALENESS is judged only against a launch time this script could read. An unreadable
  # `launched_at` DROPS the conjunct rather than dating the promise from a guess — this
  # script's "named, never guessed" rule — and the caller says so in the detail instead of
  # silently applying a two-conjunct predicate.
  if [ -n "$le" ] && [ "$mtime" -le "$le" ]; then
    CONJUNCT="stale=$raw (mtime $(epoch_iso "$mtime") < launched_at $liso)"
    return 1
  fi
  CONJUNCT="delivered=$raw"
  return 0
}

# STILL-LIVE adds NO liveness judgment of its own: a claimed process that exists, or a
# progress artifact written inside its declared cadence. Both are fields the brief itself
# declared. The state exists so a verdict taken mid-flight does not read as a broken
# contract — an agent that is visibly still working has not failed to land. A dead claim
# falls THROUGH to progress/cadence here rather than ending the question, which is what
# spares a still-writing agent a false UNMET.
LIVE_REASON=""
row_still_live() {  # <claims> <progress> <cadence> <launched_at>
  local claims="$1" prog="$2" cadence="$3" launched="$4" cad_s age mtime le p
  LIVE_REASON=""
  if [ -n "$claims" ] && claims_live "$claims"; then
    LIVE_REASON="claimed process pattern \"$claims\" matches a live process"
    return 0
  fi
  [ -n "$prog" ] || return 1
  cad_s="$(parse_seconds "$cadence")" || return 1
  p="$(abs_path "$prog")"
  if [ -e "$p" ]; then
    mtime="$(file_mtime "$p")"
    age=$(( $(now_epoch) - mtime ))
  else
    # Never written: the promise is dated from the launch, so an artifact that was never
    # created goes stale exactly as one that stopped being written would.
    le="$(iso_epoch "$launched")"
    [ -n "$le" ] || return 1
    age=$(( $(now_epoch) - le ))
  fi
  [ "$age" -le "$cad_s" ] || return 1
  LIVE_REASON="progress artifact $prog last changed ${age}s ago, inside the declared cadence \"$cadence\" (${cad_s}s)"
  return 0
}

# ---------------------------------------------------------------- the follow-up in flight
#
# FOLLOW-UP (wave-20 T9; REQ-4, AC-4.3; spec D4, ledger Δ8). The orchestrator sends a MET
# agent a follow-up and the agent sets to work on it — and until this state existed every
# reader saw MET: the tick printed STANDDOWN, and `stop-orders.sh standdown` merged and
# removed the tree of an agent still writing its reply. No hook fires on SendMessage, but the
# orchestrator's own transcript records both halves of the exchange:
#
#   the send   an assistant record whose content holds a `tool_use` named `SendMessage`;
#              `input.to` is the name it was addressed to (a trailing ` [ref]` is dropped)
#   a reply    an envelope carrying the agent's own words, in either shape the CLI writes
#              (wave-20 T9b, review R1, measured in this wave's orchestrator transcript):
#                `<teammate-message teammate_id="<name>" …>` — a teammate's message
#                `<agent-message from="<name>">` — a background agent's hand-back, in an
#                  `isMeta` user record (`Another Claude session sent a message:` …)
#              and in either carrier: a user record's text, or — when it lands mid-turn —
#              an `attachment` record of type `queued_command`, whose `prompt` holds it
#
# AN IDLE NOTICE IS NO REPLY (wave-20 T9b, critic C5). An envelope whose body is the JSON
# `{"type":"idle_notification",…}` says the agent's turn ended, not that it answered; the one
# from the report turn can be delivered after the send, and counting it put a row the agent
# was still working on back to MET, so standdown could land the tree under it. A record that
# carries a report beside an idle notice still answers, by the report.
#
# A NAME HAS A FOLLOW-UP IN FLIGHT when its latest send comes after its latest reply, in the
# transcript's own record order (the order the CLI appended them, which no clock skew can
# reorder). The agent's next reply closes it. ONE OWNER: the state is decided
# here, in `verdict_row`, and the tick, standdown, the lease walk and the stop guard inherit
# it unchanged — no consumer reads the transcript for this itself (Δ8's rejected
# alternative). A declaring verb beside each message was rejected too: forgetting it fails
# silently, and destructively.
#
# WHAT IS NOT A REPLY. A `tool_result` that merely QUOTES a teammate message (a grep of a
# record file) is not the harness delivering one, so only a user record's string content and
# its text blocks are read. A sidechain SendMessage is not the orchestrator's.
#
# FAIL DIRECTION: no transcript, no jq, or nothing parseable is "no follow-up" — the state
# every reader had before this existed, so a missing input can never hold a row it did not
# hold yesterday. The accepted cost is the other way round: a message that was not a
# follow-up holds the row until the agent answers it (Δ8, "conservative cost accepted").
#
# READ ONCE PER PROCESS, and only when a row reads MET — a verdict over rows none of which
# landed never opens the transcript. `grep -F` on the two literals first: a session's
# transcript is tens of megabytes and the records this asks about are a handful of lines.
FOLLOWUP_READ=0; FOLLOWUP_OPEN=""; FOLLOWUP_AT=""
read_followups() {
  local d tr=""
  FOLLOWUP_READ=1; FOLLOWUP_OPEN=""
  command -v jq >/dev/null 2>&1 || return 0
  for d in "$(transcripts_dir)"/*/; do
    if [ -f "${d}${SESSION_ID}.jsonl" ] && [ ! -L "${d}${SESSION_ID}.jsonl" ]; then
      tr="${d}${SESSION_ID}.jsonl"; break
    fi
  done
  [ -n "$tr" ] || return 0
  FOLLOWUP_OPEN="$(grep -F -e '"name":"SendMessage"' -e '<teammate-message' -e '<agent-message' "$tr" 2>/dev/null \
    | jq -R -r '
        # Every envelope in a text, as [name, body]; the body runs to its closing tag, or to
        # the end of the text when a truncated record has none.
        def replies:
          [scan("<(?:teammate-message teammate_id|agent-message from)=\"([^\"]+)\"[^>]*>((?:(?!</(?:teammate-message|agent-message)>)[\\s\\S])*)")]
          | .[]
          | select((.[1] | (fromjson? // null) | type == "object" and .type == "idle_notification") | not)
          | .[0];
        (fromjson? // empty)
        | select(type == "object" and .isSidechain != true)
        | (.timestamp // "") as $ts
        | if .type == "assistant" then
            (.message.content // [] | if type == "array" then .[] else empty end
             | select(type == "object" and .type == "tool_use" and .name == "SendMessage")
             | "S\t\(.input.to // "" | tostring)\t\($ts)")
          elif .type == "user" then
            (.message.content
             | if type == "string" then .
               elif type == "array" then ([.[] | select(type == "object" and .type == "text") | .text] | join("\n"))
               else "" end
             | replies | "R\t\(.)\t\($ts)")
          elif .type == "attachment" then
            (.attachment
             | select(type == "object" and .type == "queued_command")
             | .prompt | select(type == "string")
             | replies | "R\t\(.)\t\($ts)")
          else empty end' 2>/dev/null \
    | awk -F'\t' '
        { n = $2; sub(/ \[[^]]*\]$/, "", n); sub(/@.*$/, "", n); if (n == "") next
          if ($1 == "S") { sent[n] = NR; at[n] = $3 } else if ($1 == "R") { rep[n] = NR } }
        END { for (n in sent) if (!(n in rep) || sent[n] > rep[n]) printf "%s\t%s\n", n, at[n] }')"
  return 0
}

# A MET row whose agent has a follow-up in flight becomes FOLLOW-UP. The row is matched by
# its name, and by its teammate address with the `@session-…` suffix off — the orchestrator
# sends to the bare name, and the teammate-message names the bare name too.
#
# A CLOSED ROW STAYS CLOSED (wave-20 T9b, review R2, walk §8c). A send to a row the ack has
# already closed — the tick's stand-down close, or `stop-orders.sh stopped` beside a stop —
# reopens nothing: the close is the name's one terminal state (ADR-034), and reading FOLLOW-UP
# there held the row LEFT ALONE in standdown for a reply that could not come, while the tick
# counted it closed. "Closed" is `row_acked`'s answer, which is `roster_open_names`' (read_acked
# above); nothing here re-derives it. The row keeps its MET and the detail says the send was
# ignored, naming the close. A name dispatched again after its ack is open, and a follow-up to
# it counts as it always did.
verdict_followup() {  # <roster row> — rewrites VERDICT_STATE/VERDICT_DETAIL when it applies
  local name tid n at stamp s_at s_by s_why
  [ "$FOLLOWUP_READ" = 1 ] || read_followups
  [ -n "$FOLLOWUP_OPEN" ] || return 0
  name="$(line_field "$1" name)"
  tid="$(line_field "$1" teammate_id)"; tid="${tid%%@*}"
  while IFS=$'\t' read -r n at; do
    [ -n "$n" ] || continue
    if [ "$n" = "$name" ] || { [ -n "$tid" ] && [ "$n" = "$tid" ]; }; then
      [ "$ACKED_READ" = 1 ] || read_acked
      if row_acked "$(clean "$name")"; then
        stamp="$(ack_stamp_of "$(clean "$name")")"
        read -r s_at s_by s_why <<< "$stamp"
        VERDICT_DETAIL="follow-up ignored: row acked at ${s_at:-an unreadable time}${s_by:+ (by $s_by${s_why:+, reason $s_why})} — the close stands, and a send after it reopens nothing${at:+ (sent $at)}. The contract itself is met: $VERDICT_DETAIL"
        return 0
      fi
      VERDICT_STATE="FOLLOW-UP"
      VERDICT_DETAIL="follow-up in flight — a message was sent to this agent${at:+ at $at} and it has not answered since; nothing lands or stands down until it does. The contract itself is met: $VERDICT_DETAIL"
      return 0
    fi
  done <<EOF
$FOLLOWUP_OPEN
EOF
  return 0
}

# One row in, one state out. PRECEDENCE, and each step is a decision:
#   WAIVED      first — but NOT unconditionally, and that is the Step-6 review's S-1. A
#               waiver is an explicit designation that this row's contract is not held, and
#               the label reads "why this dispatch produces nothing durable": it is for a
#               dispatch that names no artifact. A row carrying BOTH a DECLARED deliverable
#               and a waiver is contradictory, and the contradiction is surfaced — the
#               deliverable is judged and the detail says the waiver was disregarded —
#               rather than resolved in the direction that checks nothing. One line of
#               quoted documentation in a brief used to silence the whole contract, and the
#               briefs in this repo quote the wall's own help text constantly. A waiver over
#               an INFERRED path still wins: there only the waiver was declared.
#   MET         a landed contract is MET whatever else is true of the row, including a
#               still-running process: the artifacts are on disk and that is the question.
#   FOLLOW-UP   a MET row the orchestrator has since messaged, until the agent answers
#               (`verdict_followup`, above): the only state MET yields to.
#   STILL-LIVE  only for a row that has NOT landed. Visible work in flight is not a failure.
#   UNMET       what is left: declared, not delivered, nothing running.
# AMBIGUOUS is decided one level up, in the verdict loop, because it is a fact about the
# NAME across rows rather than about any one row.
# A row that declares NO deliverable is MET, vacuously and by design. The wall that refuses
# an undeclared contract is hooks/dispatch-preflight.sh's, at dispatch, where it can still be
# fixed; making this verb UNMET such a row would block a stopping agent with a refusal that
# names nothing to write, which is the fail-CLOSED direction on a judgment this machinery
# does not own (R7).
VERDICT_STATE=""; VERDICT_DETAIL=""
verdict_row() {  # <roster row>
  local row="$1" launched deliv waiver source claims prog cadence le p n=0 fails="" oks="" old
  local note="" restarted rnote=""
  waiver="$(line_field "$row" waiver)"
  source="$(line_field "$row" source)"
  launched="$(line_field "$row" launched_at)"
  deliv="$(line_field "$row" deliverable)"
  claims="$(line_field "$row" claims)"
  prog="$(line_field "$row" progress)"
  cadence="$(line_field "$row" cadence)"
  VERDICT_STATE=""; VERDICT_DETAIL=""

  if [ -n "$waiver" ]; then
    # `source=` is the writer's own word for where the path came from, so this asks no
    # question of the prose. Anything but `inferred` reads as declared, which keeps rows
    # written before the field existed on the safe side of the contradiction.
    if [ -n "$deliv" ] && [ "$source" != "inferred" ]; then
      note="waiver disregarded — the brief declared an artifact AND waived it, which cannot both hold: $waiver"
    else
      VERDICT_STATE="WAIVED"
      VERDICT_DETAIL="the brief waived this contract: $waiver"
      return 0
    fi
  fi

  # A RESTART AFTER AN ACK IS NAMED, NEVER JUDGED AGAINST (wave-20 T20c, critic C2-2).
  # hooks/execution-recorder.sh stamps `restarted_at=` on the row that re-identifies an id
  # whose lineage an ack closed, and leaves `launched_at` as the contract's launch. The
  # restart is occupancy — the name holds a slot again, which `roster_open_names` reads and
  # `acked=` reports — and it moves no clock this verdict dates a deliverable against: the
  # artifact written before the ack still meets the contract. The detail says so, so a
  # reader seeing `acked=no` on a MET row knows why the name is open.
  restarted="$(line_field "$row" restarted_at)"
  [ -z "$restarted" ] || rnote="restarted at $restarted after the ack of this name — it holds a slot again, and the contract is judged against its launch at ${launched:-an unreadable time}"
  le="$(iso_epoch "$launched")"
  # Deliverables are comma-separated, as hooks/stop-check.sh reads them. Every declared path
  # is stat'd, not just up to the first failure: the readback
  # has to name EVERY failing conjunct or an agent fixes one item per stop.
  old="$IFS"; IFS=','; set -f
  # shellcheck disable=SC2086
  set -- $deliv
  set +f; IFS="$old"
  for p in "$@"; do
    p="$(printf '%s' "$p" | sed -e 's/^ *//' -e 's/ *$//')"
    [ -n "$p" ] || continue
    n=$((n + 1))
    if landing_conjunct "$p" "$le" "$launched"; then
      oks="${oks}${oks:+; }${CONJUNCT}"
    else
      fails="${fails}${fails:+; }${CONJUNCT}"
    fi
  done

  if [ "$n" -eq 0 ]; then
    VERDICT_STATE="MET"
    VERDICT_DETAIL="${note:+$note; }no deliverable declared — this row names nothing to hold it to${rnote:+; $rnote}"
    verdict_followup "$row"
    return 0
  fi
  if [ -z "$fails" ]; then
    VERDICT_STATE="MET"; VERDICT_DETAIL="${note:+$note; }$oks"
    [ -n "$le" ] || VERDICT_DETAIL="${note:+$note; }$oks (launched_at \"$launched\" unreadable: not judged for staleness)"
    VERDICT_DETAIL="$VERDICT_DETAIL${rnote:+; $rnote}"
    verdict_followup "$row"
    return 0
  fi
  if row_still_live "$claims" "$prog" "$cadence" "$launched"; then
    VERDICT_STATE="STILL-LIVE"
    VERDICT_DETAIL="${note:+$note; }$LIVE_REASON; outstanding: $fails${rnote:+; $rnote}"
    return 0
  fi
  VERDICT_STATE="UNMET"; VERDICT_DETAIL="${note:+$note; }$fails"
  [ -n "$le" ] || VERDICT_DETAIL="${note:+$note; }$fails (launched_at \"$launched\" unreadable: not judged for staleness)"
  VERDICT_DETAIL="$VERDICT_DETAIL${rnote:+; $rnote}"
  return 0
}

# The roster is APPEND-ONLY and a contract ADVANCES along it — `intended` at the dispatch
# wall, `confirmed` when the spawn returns, `identified` when the subagent starts. The
# latest row for a name is the authoritative one (spec §1 domain model) and it is
# self-sufficient, because every writer that appends copies the contract fields forward. So a
# verdict is one line PER NAME rather than per row: a three-state chain is ONE contract, and
# a gate handed three lines for one stopping agent would have to guess which to believe.
#
# One awk pass rather than a shell loop over `line_field`, which is four processes per field
# per row: this verb runs from the Stop-sweep (`hooks/landing-gate.sh`, invoked on the
# harness's Stop event, not SubagentStop — see that file's header) under the 10 s timeout
# the registration declares, against a roster that is deliberately uncapped (the
# recorder's F-1 note says why). The fold is the reader-side twin of the recorder's
# "take the LAST row for a tool_use_id".
#
# IT EMITS THE NAME IT ALREADY PARSED, and the count of contracts under it, TAB-delimited
# ahead of the row. Both callers used to throw the parsed name away and recover it with
# `line_field` per folded row — five processes each, 9.665 s at 1000 rows against a 0.029 s
# fold, on the path the landing gate runs at every subagent stop (Step-6 review, measured;
# the same change measured 6.36 s → 0.125 s end to end). A tab cannot appear inside a field:
# every writer on this roster runs its values through a sanitizer that turns one into a
# space, and this fold does the same to the name it emits.
#
# THE CONTRACT COUNT is the C-2 answer. The roster is keyed by NAME and nothing else, so two
# dispatches sharing a name are indistinguishable to every reader downstream — the fold used
# to hand the later contract's deliverable to whichever agent stopped first. `tool_use_id` is
# the one field that separates DISPATCHES from the state chain of a single dispatch
# (intended → confirmed → identified all copy it forward), so counting its distinct non-empty
# values per name counts contracts. Rows carrying none fold into one bucket: unknowable is
# not the same as several.
latest_rows() {
  [ -f "$ROSTER_FILE" ] || return 0
  awk -v pfx="roster-state/${ROSTER_VERSION}|" -v sid="$SESSION_ID" '
    index($0, pfx) != 1 { next }
    {
      name = ""; rsession = ""; tuid = ""
      nf = split($0, f, "|")
      for (i = 1; i <= nf; i++) {
        # FIRST field of a key wins, exactly as line_field takes `head -1`; a forged
        # second `name=` further along the row must not overrule the writer.
        if (name == "" && substr(f[i], 1, 5) == "name=") name = substr(f[i], 6)
        if (rsession == "" && substr(f[i], 1, 8) == "session=") rsession = substr(f[i], 9)
        if (tuid == "" && substr(f[i], 1, 12) == "tool_use_id=") tuid = substr(f[i], 13)
      }
      # The roster file is already per-session; this only fires on a hand-edited or copied
      # file, and it costs one comparison to keep the verdict honest about whose promises
      # it is answering for.
      if (rsession != "" && rsession != sid) next
      if (name == "") name = "(unnamed)"
      gsub(/\t/, " ", name)
      if (tuid != "" && !((name SUBSEP tuid) in seen)) {
        seen[name SUBSEP tuid] = 1
        contracts[name]++
      }
      if (!(name in row)) { order[++n] = name }
      row[name] = $0
    }
    END {
      for (i = 1; i <= n; i++)
        printf "%s\t%d\t%s\n", order[i], contracts[order[i]] + 0, row[order[i]]
    }
  ' "$ROSTER_FILE" 2>/dev/null
}

# The latest row for ONE name, or empty when none carries it. `ack`'s UNMET-warning check
# needs exactly this — a single row for a single name — while `verdict`'s own loop needs
# every row it can see; this is the minimal shared plumbing between the two callers, not a
# second copy of the predicate (verdict_row stays the only place that computes MET/UNMET/
# WAIVED/STILL-LIVE).
row_for_name() {  # <name>
  local _want="$1" _row _rname _nc
  # `$'\t'` and not `"$(printf '\t')"`: an IFS prefix on a `while` condition is re-evaluated
  # on EVERY iteration, so the command substitution would spend a subshell per row — the
  # exact per-row process cost this fold exists to remove.
  while IFS=$'\t' read -r _rname _nc _row; do
    [ -n "$_row" ] || continue
    [ "$_rname" = "$_want" ] && { printf '%s\n' "$_row"; return 0; }
  done <<EOF
$(latest_rows)
EOF
}

# ---------------------------------------------------------------- verbs

case "$VERB" in

  verdict)
    # A symlinked roster is REFUSED here, where `ack` only warns over one (see roster_names).
    # The difference is what the two produce: an ack records a name and a warning either way,
    # while this verb produces a VERDICT, and a clean one computed over a roster the script
    # was redirected away from is a false statement about contracts it never read. Exit 2 is
    # the caller's fail-open path.
    if [ -L "$ROSTER_FILE" ]; then
      die "REFUSED — $ROSTER_FILE is a symbolic link; the roster was not read."
      die "A verdict over a roster this script cannot trust would be a claim about contracts"
      die "it never saw. Remove the link and re-run; nothing was written."
      exit 2
    fi

    _want="$(clean "$VERDICT_NAME")"
    # ONCE, ahead of the loop: the ledger is one file and every row asks it the same
    # question, so a per-row read would be a file open per row on the path the Stop-sweep
    # runs (`hooks/landing-gate.sh`, the harness's Stop event — not SubagentStop). Read here
    # rather than cached anywhere across invocations — an ack taken by
    # a process that has since exited is still in force, which is the whole durability
    # claim the stop-side consumers rest on.
    read_acked
    _rows="$(latest_rows)"
    _n=0; _met=0; _unmet=0; _waived=0; _live=0; _ambig=0; _follow=0; _unmet_lines=""
    # The fold hands over the name and the contract count it already parsed; re-deriving
    # them here with `line_field` is what made this loop 9.665 s at 1000 rows (see
    # latest_rows). IFS is scoped to the read, and spelled `$'\t'` rather than as a command
    # substitution, which an IFS prefix would re-run once per row.
    while IFS=$'\t' read -r _rname _ncontracts _row; do
      [ -n "$_row" ] || continue
      [ -z "$_want" ] || [ "$_rname" = "$_want" ] || continue
      verdict_row "$_row"
      # ONE NAME, TWO CONTRACTS: the fold picked one of them and no reader can tell which
      # this stopping agent holds — the earlier agent would be judged against the later
      # one's artifact, and refused for not writing something that was never its job
      # (Step-6 review C-2). Say so and hold nobody to it. A waiver is still answered
      # first: it is an explicit designation, and it makes the ambiguity moot.
      if [ "$VERDICT_STATE" != "WAIVED" ] && [ "${_ncontracts:-0}" -gt 1 ]; then
        VERDICT_STATE="AMBIGUOUS"
        VERDICT_DETAIL="$_ncontracts contracts share the name \"$_rname\" on this roster; no reader can tell which one is stopping, so none of them is judged. Re-dispatch under distinct names, or read the rows by tool_use_id."
      fi
      _n=$((_n + 1))
      # THE ACK, REPORTED BESIDE THE STATE and never folded into it (S9). Asked with the
      # CLEANED name — the form the ack verb stores and this line prints — so the one
      # reader of the ledger and the one printer of the answer normalize the key identically;
      # a second normalization is the C-5 divergence class, and this is the site that used to
      # have three of them downstream. `no` is printed rather than left empty on purpose: a
      # consumer must be able to tell "not acked" from "this verb does not carry the field".
      _pname="$(clean "$_rname")"
      _acked=no; row_acked "$_pname" && _acked=yes
      printf '%s|at=%s|session=%s|name=%s|state=%s|acked=%s|detail=%s\n' \
        "$VERDICT_SCHEMA" "$(iso_now)" "$SESSION_ID" "$_pname" \
        "$VERDICT_STATE" "$_acked" "$(clean "$VERDICT_DETAIL")"
      case "$VERDICT_STATE" in
        MET)        _met=$((_met + 1)) ;;
        WAIVED)     _waived=$((_waived + 1)) ;;
        STILL-LIVE) _live=$((_live + 1)) ;;
        AMBIGUOUS)  _ambig=$((_ambig + 1)) ;;
        FOLLOW-UP)  _follow=$((_follow + 1)) ;;
        UNMET)
          _unmet=$((_unmet + 1))
          _unmet_lines="${_unmet_lines}UNMET — ${_rname}: $(clean "$VERDICT_DETAIL")
"
          ;;
      esac
    done <<EOF
$_rows
EOF

    # NOTHING TO ANSWER FOR IS NOT A FAILURE. A name on no roster row is the phantom class
    # the landing gate filters on (AC-6), and a session with no roster is one that has not
    # dispatched yet. Both exit 0 — this verb reports contracts it can see, and inventing an
    # UNMET for a row that does not exist is exactly the false alarm the wave exists to end.
    if [ "$_n" -eq 0 ]; then
      if [ -n "$_want" ]; then
        say "no row named \"$_want\" on this session's roster; there is no contract to hold"
      else
        say "no contract rows on this session's roster"
      fi
      exit 0
    fi

    say "$_n row(s): $_met MET, $_unmet UNMET, $_waived WAIVED, $_live STILL-LIVE, $_ambig AMBIGUOUS, $_follow FOLLOW-UP"
    if [ "$_unmet" -gt 0 ]; then
      printf '%s' "$_unmet_lines" | while IFS= read -r _l; do
        [ -n "$_l" ] && say "$_l"
      done
      say "the named artifacts are not on disk as the brief declared them."
      say "Nothing was stopped, judged, or recorded — this verb only reads."
      exit 1
    fi
    exit 0
    ;;

  ack)
    mkdir -p "$STATE_DIR" 2>/dev/null
    if [ ! -d "$STATE_DIR" ]; then
      die "REFUSED — the state directory could not be created ($STATE_DIR)."
      exit 2
    fi

    _known="$(roster_names)"
    # SCOPED TO THIS PROCESS'S OWN LINES. A bare `|event=ack|` count answers "did some ack
    # line appear", which a CONCURRENT caller's append satisfies just as well as ours — so a
    # write that failed could be journalled as a success on somebody else's evidence
    # (Step-6 review C-6). The trailing `|` is load-bearing: without it pid 123 matches
    # pid 1234.
    _before="$(ledger_count "|event=ack|.*|pid=$$|")"
    _recorded=""; _unknown=""
    _ack_attr="|by=${ACK_BY}"
    [ -n "$ACK_REASON" ] && _ack_attr="${_ack_attr}|reason=${ACK_REASON}"
    for _name in "${ACK_NAMES[@]}"; do
      _name="$(clean "$_name")"
      [ -n "$_name" ] || continue
      grep -qxF -- "$_name" <<< "$_known" \
        || _unknown="${_unknown}${_unknown:+, }${_name}"

      # A row's verdict is a fact about the disk; ack is a fact about the ORCHESTRATOR'S
      # VERIFICATION — an ack over an UNMET row does not close the contract, it warns that a
      # row is being closed which has not landed. verdict_row is the one place that computes
      # MET/UNMET/WAIVED/STILL-LIVE; this reuses it rather than re-deriving it.
      _ack_suffix=""
      _ack_row="$(row_for_name "$_name")"
      if [ -n "$_ack_row" ]; then
        verdict_row "$_ack_row"
        if [ "$VERDICT_STATE" = "UNMET" ]; then
          say "WARNING: acking UNMET contract — $(clean "$VERDICT_DETAIL")"
          _ack_suffix="|verdict=UNMET|detail=$(clean "$VERDICT_DETAIL")"
        fi
      fi
      # THE ATTRIBUTION SITS BETWEEN THE NAME AND THE UNMET SUFFIX. `name=` stays where every
      # existing reader finds it (the field read is by key, not by position), and `detail=` —
      # the one field that can carry a sentence — stays last.
      ledger_write "${LEDGER_SCHEMA}|event=ack|at=$(iso_now)|epoch=$(now_epoch)|pid=$$|session=${SESSION_ID}|name=${_name}${_ack_attr}${_ack_suffix}"
      _recorded="${_recorded}${_recorded:+, }${_name}"
    done
    [ -n "$_recorded" ] || usage "ack needs at least one non-empty row name."

    _after="$(ledger_count "|event=ack|.*|pid=$$|")"
    if [ "$_after" -le "$_before" ]; then
      die "REFUSED — the ack could not be journalled to $LEDGER_FILE."
      die "An unrecorded ack leaves the row open to every later reader, so the failure is"
      die "reported rather than assumed away."
      exit 2
    fi

    read_acked
    say "acked: $_recorded"
    # A name no roster row carries is RECORDED, warned about, and never refused. Two reasons,
    # both about what a refusal would cost: an ack can legitimately precede the row (the
    # roster is written by the dispatch gate, and a re-dispatch under the same name is
    # ordinary), and a roster this script cannot read — symlinked, or not yet written —
    # would turn every ack into a refusal precisely when the operator most needs the row
    # quieted. A typo's whole blast radius is one inert ledger line and this warning.
    if [ -n "$_unknown" ]; then
      say "no roster row carries: $_unknown — recorded anyway; each closes a row of that name"
      say "launched before this ack, never one launched after it. Check the spelling against: $LEDGER_FILE"
    fi
    say "$ACKED_COUNT row(s) acked for this session; an acked row is closed for every reader"
    exit 0
    ;;
esac
