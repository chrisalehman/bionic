#!/bin/bash
# THE SETTINGS-CHANNEL PARTITION GUARD — session-20260815-landing-supervision, T6.
#
# Registered in settings.json in front of a wall that is ALREADY registered on the
# skill channel, and its whole job is to make sure exactly one of those two
# registrations is ever live for a given event:
#
#     settings.json  ->  this guard  ->  exec the real wall   (agent contexts only)
#     SKILL.md hooks ->  the real wall                        (main thread, unchanged)
#
# WHY A SECOND CHANNEL AT ALL. The skill-frontmatter channel is looked up by SESSION
# key, and a tool-class event raised inside a teammate or subagent context is
# dispatched under the AGENT key — so `PreToolUse|Write`, `PreToolUse|Agent` and
# their PostToolUse twins never reach a skill-registered hook from inside an agent.
# Measured, both directions, with a same-session main-thread positive control:
# .bionic/docs/record/session-20260815-landing-supervision/t1-probe-report.md §3
# (CLI 2.1.233). Every wall this repo has ever installed therefore stopped at depth
# one, and delegating was enough to escape it. The settings channel IS alive in
# those contexts, which is what this file makes usable.
#
# WHY THE GUARD CANNOT LIVE INSIDE THE WALL. The settings channel is alive on the
# main thread too, and in every session on this machine including the ones that
# never invoked the governing skill. A wall invoked through it cannot tell which
# channel called it — same script, same payload — so a guard written into the wall
# would answer the same way on both, and the only predicate that silences the
# settings channel on a main-thread event (no top-level `agent_id`) would silence
# the skill channel there too, disarming main-thread coverage outright. The guard
# has to be the thing the channel points AT, and nothing else can be.
#
# THE PARTITION (design D1, ratified 2026-08-15; plan AC-8). Run the wall iff:
#
#   1. the payload carries a top-level `agent_id`      — this is an agent context.
#      Main-thread payloads have no such field (t1 §3, `ctx = .agent_id // "MAIN"`).
#   2. `.bionic/tmp/roster-<session_id>.state` exists   — this session is armed.
#      The roster is written by the dispatch wall on the SKILL channel, so it
#      provably precedes any agent context: a teammate exists only after a
#      main-thread dispatch, and that dispatch is what writes the file. An
#      unarmed session therefore fails this check on one stat and pays nothing
#      else, which is what keeps a machine-wide settings registration from
#      re-globalising walls that were deliberately made skill-scoped.
#
# Anything else — ambiguity included — exits 0 in silence. This guard never
# refuses on its own account and never prints: a refusal here would be a wall
# nobody wrote, and a message here would be attributed to the wall behind it.
#
# THE WALL BEHIND IT IS NAMED BY ARGUMENT, one guard for every wall, because the
# partition is a single fact about a channel rather than a property of any one
# wall. A second copy of this predicate — one per wall, or one per script — is the
# twin the design rejected by name.
#
# THE LEDGER DOES NOT TRAVEL WITH THE WALL. Walls are read-and-refuse predicates
# and cost nothing at depth; writers stay at depth one (the governing principle,
# "distribute the reads, centralize the writes"). hooks/dispatch-preflight.sh is
# both, so this guard hands it BIONIC_HOOK_CHANNEL=agent-context and that script
# skips its roster append alone — a nested dispatch is refused or passed by the
# wall, and never rostered.
#
# Exit code 2 (from the wall behind it) = block the tool call entirely.
# [WALL: hooks/agent-context-guard.test.sh]
#
# Installed globally by claude-bootstrap.sh to ~/.claude/hooks/

set -uo pipefail

# ---------- the wall this invocation guards ----------
#
# `~` is expanded by the shell that runs the settings.json command string, so the
# argument normally arrives absolute; the expansion below only covers a literal
# tilde surviving an exotic invocation. A target that is missing or unnamed is a
# misconfiguration, and a misconfigured guard passes the tool call through rather
# than blocking work on its own confusion.
TARGET="${1:-}"
[ -n "$TARGET" ] || exit 0
case "$TARGET" in '~/'*) TARGET="$HOME/${TARGET#\~/}" ;; esac
[ -f "$TARGET" ] || exit 0

INPUT=$(cat)
_jq() { printf '%s' "$INPUT" | jq -r "$1 // empty" 2>/dev/null; }

# ---------- 1. is this an agent context? ----------
# The cheapest question, asked first and with no filesystem behind it: every
# main-thread tool call on this machine — armed or not — leaves here.
[ -n "$(_jq '.agent_id')" ] || exit 0

# ---------- 2. is this session armed? ----------
PAYLOAD_SID=$(_jq '.session_id')
[ -n "$PAYLOAD_SID" ] || exit 0
# The same belt hooks/dispatch-preflight.sh wears on the same value, in the same
# direction: the roster path is built by interpolating this key, so a key carrying
# a path separator addresses a file outside the state directory entirely. Session
# ids are harness-minted UUIDs, so this silences nothing real.
case "$PAYLOAD_SID" in *[!A-Za-z0-9_-]*) exit 0 ;; esac

CWD=$(_jq '.cwd')
[ -n "$CWD" ] || exit 0

# DELIBERATELY DUPLICATED, byte for byte, from hooks/canonical-sdlc-governing-skill.sh
# — the origin of a family the evidence gate, the dispatch wall, the probe, the poker
# and stop-orders all carry, held together by tests/cross-gate-agreement.test.sh §N.1.
# A sourced library the installer misses is a silently inert wall (TDD §9), and this
# guard must land on the same `.bionic` the dispatch wall wrote the roster into or it
# answers "unarmed" from a worktree of an armed session.
resolve_project_root() {  # $1=a path whose repo we want; $2=fallback (default pwd)
  local d common root
  d=$(dirname "$1")
  while [ ! -d "$d" ] && [ "$d" != "/" ] && [ "$d" != "." ] && [ -n "$d" ]; do
    d=$(dirname "$d")
  done
  if common=$(git -C "$d" rev-parse --path-format=absolute --git-common-dir 2>/dev/null); then
    dirname "$common"
    return
  fi
  if common=$(git -C "$d" rev-parse --git-common-dir 2>/dev/null); then
    case "$common" in
      /*) root=$(dirname "$common") ;;
      *)  root=$(cd "$d" 2>/dev/null && cd "$(dirname "$common")" 2>/dev/null && pwd -P) ;;
    esac
    if [ -n "$root" ]; then
      printf '%s\n' "$root"
      return
    fi
  fi
  # NO-GIT FALLBACK: the pin follows the TARGET, never the shell. Outside any
  # repository, walk up from the nearest existing ancestor of the target for
  # the nearest directory already carrying a `.bionic/` tree and answer there;
  # only when none exists does the supplied fallback (default pwd) win — which
  # preserves the first-write-into-a-fresh-project path and changes nothing
  # inside a git repository, where the arms above always answer first.
  root="$d"
  while [ -n "$root" ] && [ "$root" != "/" ] && [ "$root" != "." ]; do
    if [ -d "$root/.bionic" ]; then
      printf '%s\n' "$root"
      return
    fi
    root=$(dirname "$root")
  done
  printf '%s\n' "${2:-$(pwd)}"
}

REPO=$(resolve_project_root "$CWD/." "$CWD")
[ -n "$REPO" ] && [ -d "$REPO" ] || exit 0

# A symlink anywhere on the arming path is not followed, the same three levels the
# attestation gets in hooks/dispatch-preflight.sh. The stakes are lower here — the
# only thing a planted roster can do is make a wall RUN — but a repo pointing this
# guard at another tree's arming fact is still a repo deciding which session it
# belongs to, and the answer is cheap.
[ ! -L "$REPO/.bionic" ] && [ ! -L "$REPO/.bionic/tmp" ] || exit 0
ROSTER_FILE="$REPO/.bionic/tmp/roster-${PAYLOAD_SID}.state"
[ ! -L "$ROSTER_FILE" ] && [ -f "$ROSTER_FILE" ] || exit 0

# ---------- both true: hand the payload to the wall ----------
#
# The payload goes back in on stdin exactly as it arrived, and the wall's exit
# status is this guard's — a refusal must reach the harness as the wall's own 2,
# with the wall's own words already on stderr.
printf '%s' "$INPUT" | BIONIC_HOOK_CHANNEL=agent-context bash "$TARGET"
exit $?
