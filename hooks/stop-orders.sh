#!/bin/bash
# STOP ORDERS — the human's instruction, and the batch stand-down.
# Design: .bionic/docs/specs/epic-16-landing-contract/wave-02-fact-based-supervision.spec.md
#         §Design (R3, R8), slice S3.
# [WALL: hooks/stop-orders.test.sh]
#
# This is NOT a hook. Like hooks/session-sweeper.sh and hooks/stop-check.sh it lives in
# hooks/ for test-harness pairing and bootstrap installation only; it is never registered
# in MANAGED_HOOKS. Two questions, one invocation each:
#
#     bash ~/.claude/hooks/stop-orders.sh order <target> [--at <epoch>]
#     bash ~/.claude/hooks/stop-orders.sh standdown
#
# ORDER records that a human asked for an agent to be stopped, and prints what stopping it
# gives up. It is not evidence and it does not discharge the contract — it is an
# INSTRUCTION, and hooks/stop-guard.sh gets out of its way. Why a record at all: the gate
# runs inside a PreToolUse payload that carries nothing about who asked for the stop, so
# the order has to reach it the only way anything reaches a gate in this machine — as a
# fact on disk, written before the stop.
#
# AN ORDER IS BOUNDED IN TIME, and this is the one clock in the stop arc that belongs
# there. hooks/stop-guard.sh refuses to put a window on EVIDENCE (an observation is stale
# the moment its subject writes, however recent, and valid however old while its subject is
# dormant). An instruction is the other thing: it is current when it is given and it stops
# being current, and a standing order that outlived its conversation would open the wall
# for a name a later dispatch reuses. The window is generous — this is not a race — and an
# expired order simply leaves the ceremony where it was.
#
# STANDDOWN answers "which agents can I stop right now, and how do I address them?" in one
# read. Every row whose contract has LANDED — MET against a declared artifact, WAIVED, or
# acked — is listed with an address the platform's stop primitive accepts; every row that
# is still working, or has not landed, is listed as LEFT ALONE and never as a target. It
# stops nothing itself: stopping is the harness's primitive, not a shell script's. What it
# does is compute the batch, so the N stops that follow are N fact-discharged calls with no
# ceremony between them, instead of N observations.
#
# IT OWNS NO PREDICATE. "Did this contract land" is answered by
# `hooks/session-sweeper.sh verdict`, exactly as hooks/landing-gate.sh consumes it. This
# script parses that verb's machine lines and never stats a deliverable of its own.
#
# FILES (all under .bionic/tmp/, all machine-local, all safe to delete):
#   roster-<session>.state       read-only input, owned by hooks/dispatch-preflight.sh
#   sweeper-<session>.state      read-only input, owned by hooks/session-sweeper.sh
#   stop-orders-<session>.state  the orders this script owns (append-only)
#
# Exit codes:
#   0 — the order was recorded / the stand-down was computed
#   2 — usage error, or a refusal (a state path is a symbolic link, or is unwritable)
#   3 — no session key; nothing read, nothing written
#
# Session key: CLAUDE_CODE_SESSION_ID, exactly as hooks/session-sweeper.sh takes it.
#
# Installed globally by claude-bootstrap.sh to ~/.claude/hooks/

set -u

ORDER_SCHEMA="stop-order/v1"
LEDGER_SCHEMA="sweeper-ledger/v1"
ROSTER_VERSION="v1"

# HOW LONG AN ORDER IS CURRENT, in seconds. Duplicated as a literal in
# hooks/stop-guard.sh, which is the reader; the two are held together by
# tests/cross-gate-agreement.test.sh's stop-order case, which records an order at a
# boundary epoch and asks the gate about it.
ORDER_TTL_SECONDS=1800

say() { printf 'stop-orders: %s\n' "$1"; }
die() { printf 'stop-orders: %s\n' "$1" >&2; }

usage() {  # [message]
  [ $# -gt 0 ] && die "$1"
  die "Usage:"
  die "  bash ~/.claude/hooks/stop-orders.sh order <target> [--at <epoch>]"
  die "        record a human's stop order and print what stopping gives up"
  die "  bash ~/.claude/hooks/stop-orders.sh standdown"
  die "        list every landed row with an address you can stop it by"
  exit 2
}

[ $# -ge 1 ] || usage "no verb given."
VERB="$1"; shift

ORDER_TARGET=""
ORDER_AT=""
case "$VERB" in
  order)
    [ $# -ge 1 ] || usage "order needs a target."
    case "$1" in -*) usage "the target comes first: '$1' is an option, not a target." ;; esac
    ORDER_TARGET="$1"; shift
    while [ $# -gt 0 ]; do
      case "$1" in
        # `--at` exists for the suites, which have to place an order on either side of the
        # window boundary without sleeping through it (standing test discipline: accelerate
        # the clock, never wait on it). It is not a lie the gate can be told — an order is
        # a declaration either way, and backdating one only ever makes it expire sooner.
        --at)
          [ $# -ge 2 ] || usage "--at needs an epoch."
          case "$2" in ''|*[!0-9]*) usage "--at takes epoch seconds; got '$2'." ;; esac
          ORDER_AT="$2"; shift 2 ;;
        *) usage "unknown argument: $1" ;;
      esac
    done
    ;;
  standdown)
    [ $# -eq 0 ] || usage "standdown takes no arguments; got $#."
    ;;
  *) usage "unknown verb: $VERB" ;;
esac

# ---------------------------------------------------------------- session key

SESSION_ID="${CLAUDE_CODE_SESSION_ID:-}"
if [ -z "$SESSION_ID" ]; then
  die "REFUSED — no session key (CLAUDE_CODE_SESSION_ID is unset or empty)."
  die "Both verbs answer for ONE session's roster. Run this from inside a Claude Code"
  die "session; nothing was read and nothing was written."
  exit 3
fi

# ---------------------------------------------------------------- where state lives

REPO="$(git rev-parse --show-toplevel 2>/dev/null)"
[ -n "$REPO" ] || REPO="$PWD"
REPO_REAL="$(cd "$REPO" 2>/dev/null && pwd -P)"
if [ -z "$REPO_REAL" ]; then
  die "REFUSED — cannot resolve the working directory."
  exit 2
fi

BIONIC_DIR="$REPO_REAL/.bionic"
STATE_DIR="$BIONIC_DIR/tmp"
# Hostile-repo posture, byte for byte from hooks/session-sweeper.sh: a repo controls its
# own .bionic/ contents, so a symlink anywhere on the path this script writes through is
# refused rather than followed.
for _component in "$BIONIC_DIR" "$STATE_DIR"; do
  if [ -L "$_component" ]; then
    die "REFUSED — $_component is a symbolic link."
    die "The state directory must be a real directory inside the repo. Remove the link"
    die "and re-run; nothing was written."
    exit 2
  fi
done

ROSTER_FILE="$STATE_DIR/roster-${SESSION_ID}.state"
LEDGER_FILE="$STATE_DIR/sweeper-${SESSION_ID}.state"
ORDERS_FILE="$STATE_DIR/stop-orders-${SESSION_ID}.state"

if [ -L "$ORDERS_FILE" ]; then
  die "REFUSED — $ORDERS_FILE is a symbolic link; nothing was written through it."
  die "Remove it and re-run."
  exit 2
fi

SWEEPER="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/session-sweeper.sh"

# ---------------------------------------------------------------- shared readers

now_epoch() { date -u +%s; }
iso_now()   { date -u +%Y-%m-%dT%H:%M:%SZ; }

line_field() {  # <line> <key>
  printf '%s' "$1" | tr '|' '\n' | grep "^$2=" | head -1 | cut -d= -f2-
}

# Values reach this file from a brief and from the operator's keyboard, and every record
# here is pipe-delimited key=value. A `|`, a newline or a control character inside a value
# forges a field, so they are folded to spaces exactly as hooks/session-sweeper.sh's
# clean() folds them — the two must agree, because a name written by one is matched by the
# other.
clean() {  # <value>
  printf '%s' "$1" | tr '\n\r\t|' '    ' | sed -e 's/[[:cntrl:]]/ /g' -e 's/  */ /g' \
    -e 's/^ *//' -e 's/ *$//' | cut -c 1-400
}

# HAS THE ORCHESTRATOR CLOSED THIS ROW? DELIBERATELY DUPLICATED, byte for byte, into
# hooks/stop-guard.sh and hooks/landing-gate.sh — the TDD's §9 convention, for its reason:
# a sourced library the installer misses is a silently inert wall. The three copies are
# held together by tests/cross-gate-agreement.test.sh's stop-arc section, which drives all
# three over one ledger written by the real `session-sweeper.sh ack`.
#
# It reads the sweeper's ledger rather than its verdict because ack is invisible to
# `verdict` BY DESIGN (a contract is met by artifacts or it is not, which is what lets an
# ack over an UNMET row warn instead of quietly erasing the discrepancy). Whole-name match,
# never a substring: `w4-s1` must not be closed by an ack of `w4-s10`.
ledger_acked() {  # <ledger-file> <name> -> 0 when an ack closed that row
  local f="$1" want="$2" line n
  [ -n "$want" ] || return 1
  [ -L "$f" ] && return 1
  [ -f "$f" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in "sweeper-ledger/v1|"*) : ;; *) continue ;; esac
    case "$line" in *"|event=ack|"*) : ;; *) continue ;; esac
    n=$(printf '%s' "$line" | tr '|' '\n' | grep '^name=' | head -1 | cut -d= -f2-)
    [ -n "$n" ] && [ "$n" = "$want" ] && return 0
  done < "$f"
  return 1
}

# The LATEST roster row for a name. The roster is append-only and a contract advances along
# it (`intended` → `confirmed` → `identified`), every writer copying the contract fields
# forward, so the last row carrying a name is the authoritative one — the same fold
# hooks/session-sweeper.sh's latest_rows makes, and the same one hooks/session-poker.sh
# makes for its own lookup (plan assumption 13).
roster_row_for() {  # <name>
  local want="$1" line n out=""
  [ -L "$ROSTER_FILE" ] && return 0
  [ -f "$ROSTER_FILE" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in "roster-state/${ROSTER_VERSION}|"*) : ;; *) continue ;; esac
    n=$(line_field "$line" name)
    [ "$(clean "$n")" = "$want" ] && out="$line"
  done < "$ROSTER_FILE"
  printf '%s\n' "$out"
}

# HOW THE OPERATOR ADDRESSES THIS AGENT, in a form the stop primitive accepts. The launch
# response hands back `name@session-xxxxxxxx` and that is what TaskStop takes for a
# teammate; the transcript-form id (`aname-<hex>`) is a THIRD namespace that the roster's
# `identified` row carries and the platform will not resolve for the operator (capture
# probe §3-D/§5). Printing the id the reader cannot type is what cost four calls and an
# ambiguity round on 2026-08-11, so the recorded teammate address wins, the transcript id
# is the fallback, and the bare name is the floor.
stop_address() {  # <roster-row> <name>
  local row="$1" name="$2" tm aid
  tm=$(line_field "$row" teammate_id)
  [ -n "$tm" ] && { printf '%s\n' "$tm"; return 0; }
  aid=$(line_field "$row" agent_id)
  [ -n "$aid" ] && { printf '%s\n' "$aid"; return 0; }
  printf '%s\n' "$name"
}

# ---------------------------------------------------------------- verbs

case "$VERB" in

  order)
    _target="$(clean "$ORDER_TARGET")"
    [ -n "$_target" ] || usage "order needs a non-empty target."

    mkdir -p "$STATE_DIR" 2>/dev/null
    if [ ! -d "$STATE_DIR" ]; then
      die "REFUSED — the state directory could not be created ($STATE_DIR)."
      exit 2
    fi

    _at="${ORDER_AT:-$(now_epoch)}"
    [ -f "$ORDERS_FILE" ] || printf '# bionic stop orders — schema %s — machine-local, safe to delete\n' \
      "$ORDER_SCHEMA" >> "$ORDERS_FILE" 2>/dev/null
    if ! printf '%s|at=%s|epoch=%s|session=%s|target=%s\n' \
         "$ORDER_SCHEMA" "$(iso_now)" "$_at" "$SESSION_ID" "$_target" >> "$ORDERS_FILE" 2>/dev/null; then
      die "REFUSED — the order could not be written to $ORDERS_FILE."
      die "An unrecorded order is one the stop gate will never see, so the failure is"
      die "reported rather than assumed away."
      exit 2
    fi

    say "stop ordered: $_target — the gate will pass it for the next $((ORDER_TTL_SECONDS / 60)) minutes."
    # WHAT IS BEING GIVEN UP, from the verdict's own detail and never from a second
    # opinion about the disk. An order is not a claim that the work landed, and the
    # operator is owed the difference in one line.
    if [ -f "$SWEEPER" ]; then
      _v=$( cd "$REPO_REAL" 2>/dev/null || exit 9
            CLAUDE_CODE_SESSION_ID="$SESSION_ID" bash "$SWEEPER" verdict "$_target" 2>/dev/null )
      _line=$(printf '%s\n' "$_v" | grep -F 'landing-verdict/v1|' | head -1)
      if [ -n "$_line" ]; then
        _state=$(line_field "$_line" state)
        _detail=$(line_field "$_line" detail)
        case "$_state" in
          MET|WAIVED) say "its contract has landed ($_state) — nothing is given up." ;;
          *)          say "UNLANDED ($_state) — stopping gives up: $_detail" ;;
        esac
      else
        say "no contract row of that name on this session's roster — nothing is known to be given up."
      fi
    fi
    exit 0
    ;;

  standdown)
    if [ ! -f "$SWEEPER" ]; then
      die "REFUSED — the sweeper is not beside this script ($SWEEPER)."
      die "The landing question belongs to its verdict verb; this script owns no predicate"
      die "of its own and will not guess one."
      exit 2
    fi

    _v=$( cd "$REPO_REAL" 2>/dev/null || exit 9
          CLAUDE_CODE_SESSION_ID="$SESSION_ID" bash "$SWEEPER" verdict 2>/dev/null )
    _lines=$(printf '%s\n' "$_v" | grep -F 'landing-verdict/v1|')
    if [ -z "$_lines" ]; then
      say "no contract rows on this session's roster; nothing to stand down."
      exit 0
    fi

    _ready=""; _held=""; _nready=0; _nheld=0
    while IFS= read -r _l; do
      [ -n "$_l" ] || continue
      _name=$(line_field "$_l" name)
      _state=$(line_field "$_l" state)
      _detail=$(line_field "$_l" detail)
      [ -n "$_name" ] || continue
      _row=$(roster_row_for "$_name")
      _deliv=$(line_field "$_row" deliverable)
      _why=""
      # THE DISCHARGE SET, spelled the same way hooks/stop-guard.sh spells it: an ack, or a
      # WAIVED contract, or a MET one that had a declared artifact to meet. A row that
      # declared nothing stats MET for want of anything to hold it to, and standing one
      # down on that is standing it down on a fact nobody produced — an ack is what closes
      # those, which is the job ack exists for.
      if ledger_acked "$LEDGER_FILE" "$_name"; then
        _why="acked"
      elif [ "$_state" = "WAIVED" ]; then
        _why="waived"
      elif [ "$_state" = "MET" ] && [ -n "$_deliv" ]; then
        _why="met"
      fi
      if [ -n "$_why" ]; then
        _nready=$((_nready + 1))
        _ready="${_ready}  $(stop_address "$_row" "$_name")   ($_why — $_name)
"
      else
        _nheld=$((_nheld + 1))
        _held="${_held}  $_name   ($_state — $_detail)
"
      fi
    done <<EOF
$_lines
EOF

    if [ "$_nready" -gt 0 ]; then
      say "STAND DOWN — $_nready row(s) have landed; stop each by the address on its left:"
      printf '%s' "$_ready"
    else
      say "nothing has landed; there is nobody to stand down."
    fi
    if [ "$_nheld" -gt 0 ]; then
      # NAMED, NEVER TARGETED. A row still working or not yet landed is left alone by this
      # operation — printing it as a target is how a batch stand-down would end the very
      # work it was supposed to leave running.
      say "LEFT ALONE — $_nheld row(s) are not stood down by this operation:"
      printf '%s' "$_held"
    fi
    say "This script stopped nothing: stopping is the harness's, and each of these passes"
    say "the stop gate on its landed contract with no observation."
    exit 0
    ;;
esac
