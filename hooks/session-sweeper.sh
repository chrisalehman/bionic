#!/bin/bash
# SESSION SWEEPER — epic-15 wave-04's ONE watcher for a whole session.
# Design: .bionic/docs/specs/epic-15-orchestrator-subagent-coordination/wave-04-watchers.spec.md
#         §Design ("the sweeper's own shape"), plus the ratified TDD it points at.
# [WALL: hooks/session-sweeper.test.sh]
#
# This is NOT a hook. Like hooks/preflight-probe.sh it lives in hooks/ for test-harness
# pairing and bootstrap installation only; it is never registered in MANAGED_HOOKS. It is
# armed once per session, by the orchestrator, as a harness-tracked background job:
#
#     bash ~/.claude/hooks/session-sweeper.sh arm [--tick <seconds>]
#     bash ~/.claude/hooks/session-sweeper.sh retire
#     bash ~/.claude/hooks/session-sweeper.sh status
#     bash ~/.claude/hooks/session-sweeper.sh ack <name> [<name> ...]
#
# WHAT IT IS. One long-lived process per session that reads the session roster and reports
# broken promises. It replaces the per-dispatch monitors that preceded it — bespoke
# predicates, untracked duplicates, four misfires in one day. Every threshold it applies
# is a field the brief itself declared and the dispatch gate journalled; it has no
# thresholds of its own and no opinion about any of them.
#
# WHAT IT NEVER DOES. It never stops, kills, or judges an agent. It reports state facts:
# an artifact's age, a process's absence, an elapsed interval against a declared one. The
# reading of those facts is the orchestrator's, always.
#
# THE LOOP. sleep tick → re-read the roster fresh → evaluate every non-satisfied row →
# sleep again. It lives until a finding, a retire, or the end of the session. The tick is
# an `arm` PARAMETER (default 120 s) and never an environment variable: an ambient value
# would be invisible in the ledger entry that records the arming.
#
# DELIVERY IS THE EXIT. When a tick produces findings they are batched — every broken row
# in one delivery — written to the findings file FIRST, and then the process exits 0. The
# exit is what wakes the orchestrator (a tracked background job's completion); the findings
# file is the hedge for a wake that gets lost, since a finding is a fact about current
# state and an unwatched interval delays detection without losing it.
#
# THE THREE CLASSES, and nothing else:
#   stale-progress — the declared progress artifact's mtime is older than the declared cadence
#   dead-claim     — the declared process pattern matches nothing AND the deliverables are absent
#   overdue        — now − launched_at exceeds the declared duration
# Plus done-detection, which is not a finding: a row whose declared deliverables are all
# present is SATISFIED, dropped from watching, and never woken on.
#
# ACK is the second way into that same exemption, and it exists because a roster row has no
# completion event of its own. An agent that finished but declared no machine-visible
# deliverable reads as overdue forever once its duration elapses, so the sweeper fires one
# tick after every re-arm until somebody hand-prunes the roster. The orchestrator verifies
# every agent's completion anyway; `ack` is that verification reaching the roster. An acked
# row takes the SATISFIED path — out of every class at once, not out of one of them, and
# never a fourth class or a second exemption mechanism.
#
# WHICH PREDICATES A ROW GETS is decided by field presence alone (spec AC-2):
#   claims=            → process liveness ONLY. While the claimed process is alive, all
#                        quiet is fine and no class fires for that row.
#   progress=+cadence= → stale-progress and overdue
#   neither            → overdue only ("turns-shaped" work)
# A row whose cadence cannot be parsed degrades to overdue-only, and the degradation is
# NAMED in the ledger — never guessed at, never silently dropped. The same holds for a
# duration that cannot be parsed (no overdue predicate survives) and for a row that
# declares no threshold at all (nothing to watch).
#
# FILES (all under .bionic/tmp/, all machine-local, all safe to delete):
#   roster-<session>.state           read-only input, schema roster-state/v1, owned by
#                                    hooks/dispatch-preflight.sh
#   sweeper-<session>.state          the ledger this script owns (append-only)
#   sweeper-<session>-findings.log   the findings mirror this script owns
#
# THE LEDGER is append-only and answers two questions: is a sweeper live for this session,
# and which rows has the orchestrator closed?
#   arm     — timestamp, pid, effective tick, row count, per-row degradations
#   degrade — a degradation first seen after arm time (a row added mid-session)
#   retire  — closes the open entry by pid
#   exit    — closes it from inside, naming the reason and the finding count
#   ack     — one row, closed by name. Append-only is what makes acks outlive the exit that
#             delivers a finding: every roster pass re-gathers them from this file, so an
#             ack taken before an exit is still in force after the re-arm.
# A second `arm` while the open entry's pid is LIVE is refused, naming that arming. This
# enforcement lives in the script because the doctrine it enforces is the one the wave
# exists to fix: monitors nobody could enumerate. A pid that is gone does not refuse — a
# killed or crashed sweeper must never wedge the session. An open entry whose pid cannot be
# READ refuses too, in the other direction: it may be a live sweeper this script cannot see,
# and the escape is the operator's (delete the ledger). Signalling stays fail-open over the
# same entry — see the asymmetry note at warn_bad_pid.
#
# Exit codes:
#   0 — arm delivered a finding, or was retired; retire completed; status found a live
#       sweeper; ack recorded (ALWAYS, including a name no roster row carries)
#   1 — arm refused because a live (or unreadable) arming already exists; status found no
#       live sweeper, or could not tell (live=unknown)
#   2 — usage error, or a refusal (a state path is a symbolic link, or is unwritable)
#   3 — no session key; nothing read, nothing written
#
# Session key: CLAUDE_CODE_SESSION_ID, exactly as hooks/preflight-probe.sh takes it. Every
# actor in a fleet shares one session key (design D-3), which is why the sweeper is
# per-session rather than per-agent — the whole point of the wave.
#
# Hostile-repo posture (design §8): a repo controls its own .bionic/ contents, so every
# path this script writes is checked for symlink redirection before anything is written.

set -u

LEDGER_SCHEMA="sweeper-ledger/v1"
FINDING_SCHEMA="sweeper-finding/v1"
STATUS_SCHEMA="sweeper-status/v1"
# Reader copy of hooks/dispatch-preflight.sh's roster constants (same precedent as
# hooks/preflight-probe.sh's copy: this script only ever READS roster files, so a prefix
# drift is a mislabeled scan, never a write hazard).
ROSTER_VERSION="v1"
ROSTER_PREFIX="roster-"
ROSTER_SUFFIX=".state"

# The tick default is OWNED here (spec ownership table): the ledger entry, the printed arm
# command in hooks/preflight-probe.sh, and the unarmed nag in hooks/dispatch-preflight.sh
# all render this one value.
DEFAULT_TICK=120
ARM_COMMAND="bash ~/.claude/hooks/session-sweeper.sh arm"
RETIRE_COMMAND="bash ~/.claude/hooks/session-sweeper.sh retire"
ACK_COMMAND="bash ~/.claude/hooks/session-sweeper.sh ack"

say()  { printf 'sweeper: %s\n' "$1"; }
die()  { printf 'sweeper: %s\n' "$1" >&2; }

usage() {  # [message]
  [ $# -gt 0 ] && die "$1"
  die "Usage:"
  die "  $ARM_COMMAND [--tick <seconds>]   watch this session's roster (default ${DEFAULT_TICK}s tick)"
  die "  $RETIRE_COMMAND                          close the live arming"
  die "  bash ~/.claude/hooks/session-sweeper.sh status   report whether one is live"
  die "  $ACK_COMMAND <name> [<name> ...]   close those rows: done, verified"
  exit 2
}

# ---------------------------------------------------------------- verb + flags

[ $# -ge 1 ] || usage "no verb given."
VERB="$1"; shift
TICK="$DEFAULT_TICK"

case "$VERB" in
  arm)
    while [ $# -gt 0 ]; do
      case "$1" in
        --tick)
          shift
          [ $# -ge 1 ] || usage "--tick needs a value in seconds."
          TICK="$1"; shift
          ;;
        --tick=*)
          TICK="${1#--tick=}"; shift
          ;;
        *) usage "unknown argument for arm: $1" ;;
      esac
    done
    case "$TICK" in
      ''|*[!0-9]*) usage "--tick takes whole seconds; got \"$TICK\"." ;;
    esac
    [ "$TICK" -ge 1 ] || usage "--tick must be at least 1 second; got \"$TICK\"."
    ;;
  retire|status)
    [ $# -eq 0 ] || usage "$VERB takes no arguments."
    ;;
  ack)
    # The names stay in "$@" for the verb block below; nothing is shifted here.
    [ $# -ge 1 ] || usage "ack needs at least one roster row name."
    ;;
  *) usage "unknown verb: $VERB" ;;
esac

# ---------------------------------------------------------------- session key

SESSION_ID="${CLAUDE_CODE_SESSION_ID:-}"
if [ -z "$SESSION_ID" ]; then
  die "REFUSED — no session key (CLAUDE_CODE_SESSION_ID is unset or empty)."
  die "A sweeper watches ONE session's roster, so without the key there is nothing to"
  die "watch and nothing to ledger. Run this from inside a Claude Code session."
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
FINDINGS_FILE="$STATE_DIR/sweeper-${SESSION_ID}-findings.log"

for _path in "$LEDGER_FILE" "$FINDINGS_FILE"; do
  if [ -L "$_path" ]; then
    die "REFUSED — $_path is a symbolic link; nothing was written through it."
    die "Remove it and re-run."
    exit 2
  fi
done

# ---------------------------------------------------------------- portable facts
#
# DELIBERATELY DUPLICATED from hooks/stop-check.sh, byte for byte, for the reason the TDD
# gives (§9): a sourced library the installer misses is a silently inert watcher. The
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
clean() {  # <value>
  printf '%s' "$1" | tr '\n\r\t|' '    ' | sed -e 's/[[:cntrl:]]/ /g' -e 's/  */ /g' \
    -e 's/^ *//' -e 's/ *$//' | cut -c 1-400
}

abs_path() {  # <path> — roster paths are usually absolute; a relative one is the repo's
  case "$1" in
    /*) printf '%s' "$1" ;;
    *)  printf '%s/%s' "$REPO_REAL" "$1" ;;
  esac
}

# ---------------------------------------------------------------- the prose parser
#
# `cadence=` and `duration=` are prose the dispatch gate lifted verbatim out of a brief:
# "every ~5 min", "20 minutes", "30–40 minutes". This reads the forms a brief actually
# uses and REFUSES everything else — a guessed threshold is a false alarm with a number
# in front of it, and the design's answer to an unreadable field is to name the
# degradation, never to invent a value.
#
# Deliberate limits, each one a refusal rather than a guess:
#   * exactly one number-unit pair. "1h30m" and "10 min, checkpoint at 5m" are refused.
#   * whole numbers only. "0.5h" is refused.
#   * a range ("30–40 minutes") is read at its GENEROUS end — the sweeper's job is to
#     notice a broken promise, and the promise is not broken until the longer bound passes.
#   * zero is refused: a zero threshold would make every tick a finding.
parse_seconds() {  # <prose> -> seconds on stdout; nonzero exit if it cannot be read
  local raw="$1" s pairs count nums hi unit mult n
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

# The one question the ledger answers, asked by three readers (arm's refusal, `status`,
# and the unarmed nag in hooks/dispatch-preflight.sh): is an arming still open, and is its
# process still there? Entries are replayed in order — an arm opens, a retire or an exit
# naming the same pid closes.
OPEN_PID=""; OPEN_TICK=""; OPEN_AT=""; OPEN_PID_BAD=""
read_open_arming() {
  OPEN_PID=""; OPEN_TICK=""; OPEN_AT=""; OPEN_PID_BAD=""
  [ -f "$LEDGER_FILE" ] || return 0
  local line ev p
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in "$LEDGER_SCHEMA|"*) : ;; *) continue ;; esac
    ev="$(line_field "$line" event)"
    case "$ev" in
      arm)
        # VALIDATE BEFORE BELIEVING, at the moment the value is read rather than after the
        # replay. This value came out of a file in the repo's own .bionic/tmp — the
        # directory the header's threat model names as repo-controlled — and it reaches
        # `kill -0` below and `kill -TERM` in `retire`. In POSIX kill a NEGATIVE pid is a
        # process GROUP and -1 is "every process the caller may signal", so an unvalidated
        # `pid=-1` makes one `retire` a session-wide SIGTERM; 0 is the caller's own group
        # and 1 is init. No adversary is required — any truncated or partial write that
        # leaves a `-` in the field lands in the same place.
        #
        # An unreadable entry is REMEMBERED SEPARATELY and never allowed to overwrite a
        # readable one. Validating after the replay instead let one corrupt line appended
        # after a healthy one erase a live sweeper from every reader at once — the Step-6
        # critic reproduced it: `status` denied a running sweeper, `arm` started a second
        # over it, `retire` closed only the second, and the first survived unenumerable.
        # Two open entries is not "the later one wins" when the later one cannot be read.
        p="$(line_field "$line" pid)"
        case "$p" in
          ''|*[!0-9]*|0|1)
            OPEN_PID_BAD="$p"
            ;;
          *)
            OPEN_PID="$p"
            OPEN_TICK="$(line_field "$line" tick)"
            OPEN_AT="$(line_field "$line" at)"
            ;;
        esac
        ;;
      retire|exit)
        p="$(line_field "$line" pid)"
        if [ -n "$OPEN_PID" ] && [ "$p" = "$OPEN_PID" ]; then
          OPEN_PID=""; OPEN_TICK=""; OPEN_AT=""
        fi
        ;;
    esac
  done < "$LEDGER_FILE"
  # Note what CANNOT be closed: a close line can only name a pid, so an entry whose pid is
  # unreadable is never matched by one. `OPEN_PID_BAD` therefore stands for the life of the
  # file, and the only way out is the operator's — delete the ledger. That is the price of
  # the asymmetry below, and it is charged in one direction only.
}

# WHAT A REJECTED ENTRY MEANS depends on which question is being asked, and getting that
# wrong in either direction is a live defect this script has already had once:
#
#   signalling (retire)  FAIL-OPEN. Never `kill` a value that could not be validated —
#                        `-1` alone is a session-wide SIGTERM. The bad value never reaches
#                        a signal or a close line, so `retire` simply has nothing to do.
#   arming (arm)         FAIL-CLOSED. Unreadable means "a sweeper MAY be live and this
#                        script cannot see it", so a second is refused rather than stacked
#                        over it. One sweeper per session is the invariant; an arm that
#                        guesses "probably nothing is there" is how the invariant dies.
#   answering (status)   NEITHER. It may not report not-live over an entry it cannot read;
#                        the honest third answer is live=unknown, and it exits non-zero so
#                        the dispatch nag WARNS (nothing is provably watching).
#
# Rejected, but never in silence — this script's doctrine is "named, never guessed", and a
# damaged ledger is exactly the state an operator needs told rather than smoothed over.
warn_bad_pid() {
  [ -n "$OPEN_PID_BAD" ] || return 0
  say "the ledger carries an open arming whose pid is unreadable (\"$OPEN_PID_BAD\"): it is"
  say "never believed and never signalled, so a sweeper may be live for this session that"
  say "this script cannot see. Arming is refused while it stands. Check for a stray sweeper"
  say "(pgrep -f session-sweeper.sh), then delete $LEDGER_FILE — it is machine-local and"
  say "safe to lose."
}

# A pid this shell can signal. Recycling is a theoretical false-positive and is accepted:
# the cost is one refused arm, and the fix is one `retire`.
pid_live() { [ -n "$1" ] && kill -0 "$1" 2>/dev/null; }

# The ledger's other answer: which rows the orchestrator has closed. Re-read on every roster
# pass rather than cached at arm time, so an ack taken while a sweeper is live lands on the
# next tick and an ack taken before a delivering exit is still in force after the re-arm.
ACKED_NAMES=""; ACKED_COUNT=0
read_acked() {
  ACKED_NAMES=""; ACKED_COUNT=0
  [ -f "$LEDGER_FILE" ] || return 0
  local line ev n
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in "$LEDGER_SCHEMA|"*) : ;; *) continue ;; esac
    ev="$(line_field "$line" event)"
    [ "$ev" = "ack" ] || continue
    n="$(line_field "$line" name)"
    # VALIDATE BEFORE BELIEVING, the same discipline the pid guard above applies to a value
    # out of this same repo-controlled file — with a different hazard, because a name reaches
    # a string comparison rather than `kill`. The shape that matters is the EMPTY one: every
    # row carries a name (`(unnamed)` when the roster declared none), and an empty entry
    # compared loosely would exempt the whole roster from watching in silence. Dropped, and
    # a truncated write is the likelier author of one than an adversary. Names are cleaned
    # at write time, so no entry here can carry a `|` or a newline to forge a field.
    [ -n "$n" ] || continue
    row_acked "$n" && continue
    ACKED_NAMES="${ACKED_NAMES}${n}
"
    ACKED_COUNT=$((ACKED_COUNT + 1))
  done < "$LEDGER_FILE"
}

# Whole-line match, never a substring: `w4-s1` must not be closed by an ack of `w4-s10`.
row_acked() {  # <row name>
  [ -n "$ACKED_NAMES" ] || return 1
  printf '%s' "$ACKED_NAMES" | grep -qxF -- "$1"
}

# ---------------------------------------------------------------- evaluation
#
# One pass over the roster. FINDINGS accumulates the batch; DEGRADED_NEW accumulates
# degradations not yet named in the ledger. Both are read by the caller — `arm` runs this
# once at arm time purely to survey (its findings are DISCARDED, because the design's loop
# sleeps before its first evaluation), and then once per tick for real.
FINDINGS=""; FINDING_COUNT=0; ROW_COUNT=0
DEGRADED_SEEN=""; DEGRADED_NEW=""

note_degradation() {  # <row name> <reason>
  case " $DEGRADED_SEEN " in *" $1 "*) return 0 ;; esac
  DEGRADED_SEEN="$DEGRADED_SEEN $1"
  DEGRADED_NEW="${DEGRADED_NEW}${DEGRADED_NEW:+,}${1}:${2}"
}

add_finding() {  # <class> <name> <agent_id> <detail>
  FINDING_COUNT=$((FINDING_COUNT + 1))
  FINDINGS="${FINDINGS}${FINDING_SCHEMA}|at=$(iso_now)|session=${SESSION_ID}|pid=$$|class=$1|name=$(clean "$2")|agent_id=$(clean "$3")|detail=$(clean "$4")
"
}

# Done-detection. ONE concept with TWO owners: hooks/stop-check.sh answers "is this
# deliverable delivered?" for the operator, this script answers it for the watcher, and
# they answered DIFFERENTLY until this branch set was mirrored onto stop-check.sh:526-541
# (Step-6 review D-2). A regular file is delivered only with bytes in it (an empty file is
# a path that got created, not a deliverable that got written); a DIRECTORY only with a
# file somewhere in it — `[ -s <dir> ]` is TRUE for an empty directory on both BSD and GNU,
# which used to mark a row SATISFIED, and satisfied means permanently exempt from watching;
# anything else is absent. The two implementations are held to one answer by
# tests/cross-gate-agreement.test.sh §I.2, which asks BOTH on shared fixtures and compares
# their answers to each other rather than to a restatement, so the next divergence goes red
# whichever side moves.
#
# The ONE deliberate divergence, pinned by that same section: a relative path resolves
# against the REPO ROOT here and against the operator's cwd there. This process is armed
# once as a background job and outlives the directory it was armed from, so a cwd-relative
# reading would make a single roster row mean different things on two arms of the same
# file; the operator's typed path, by contrast, is typed from somewhere on purpose.
deliverable_delivered() {  # <one path, as the roster spells it>
  local p; p="$(abs_path "$1")"
  if [ -f "$p" ]; then
    [ -s "$p" ]
  elif [ -d "$p" ]; then
    [ "$(find "$p" -type f 2>/dev/null | grep -c .)" -gt 0 ]
  else
    return 1
  fi
}

# Deliverables are comma-separated, as hooks/stop-check.sh reads them. Every one of them
# must be delivered; a row that declared none is never satisfied.
deliverables_all_present() {  # <comma-separated list>
  local list="$1" p n=0 old
  [ -n "$list" ] || return 1
  old="$IFS"; IFS=','; set -f
  # shellcheck disable=SC2086
  set -- $list
  set +f; IFS="$old"
  for p in "$@"; do
    p="$(printf '%s' "$p" | sed -e 's/^ *//' -e 's/ *$//')"
    [ -n "$p" ] || continue
    n=$((n + 1))
    deliverable_delivered "$p" || return 1
  done
  [ "$n" -gt 0 ]
}

evaluate_row() {  # <roster row>
  local row="$1" name aid launched deliv dur prog claims cadence rsession
  local now launched_e elapsed cad_s dur_s age mtime watched=0

  rsession="$(line_field "$row" session)"
  # The roster file is already per-session, so this only fires on a hand-edited or
  # copied file. It costs one comparison and keeps the sweeper honest about whose
  # promises it is holding.
  [ -n "$rsession" ] && [ "$rsession" != "$SESSION_ID" ] && return 0

  name="$(line_field "$row" name)"; [ -n "$name" ] || name="(unnamed)"
  aid="$(line_field "$row" agent_id)"
  launched="$(line_field "$row" launched_at)"
  deliv="$(line_field "$row" deliverable)"
  dur="$(line_field "$row" duration)"
  prog="$(line_field "$row" progress)"
  claims="$(line_field "$row" claims)"
  cadence="$(line_field "$row" cadence)"

  ROW_COUNT=$((ROW_COUNT + 1))

  # SATISFIED: the work landed. Nothing about a delivered row is worth waking anyone for,
  # whatever its clock says. An ACKED row is the same exemption reached by a different fact
  # — the orchestrator verified this agent's completion and said so — which is why it is a
  # second condition on this one branch rather than a check of its own further down. Both
  # answers exempt the row from every class below, and neither is a finding.
  if row_acked "$name" || deliverables_all_present "$deliv"; then
    return 0
  fi

  now="$(now_epoch)"

  # CLAIMS select process-liveness and nothing else (AC-2). A live claimed process means
  # all quiet is fine — a long compile writes no progress and delivers nothing until it
  # is done, and waking on that is the misfire this wave exists to end.
  if [ -n "$claims" ]; then
    if claims_live "$claims"; then
      return 0
    fi
    add_finding "dead-claim" "$name" "$aid" \
      "claimed process pattern \"$claims\" matches no live process and the declared deliverable(s) are absent: ${deliv:-(none declared)}"
    return 0
  fi

  # PROGRESS + CADENCE → staleness. An unreadable cadence degrades this row to
  # overdue-only and says so; it never becomes a guessed interval.
  if [ -n "$prog" ]; then
    if cad_s="$(parse_seconds "$cadence")"; then
      watched=1
      if [ -e "$(abs_path "$prog")" ]; then
        mtime="$(file_mtime "$(abs_path "$prog")")"
        age=$((now - mtime))
      else
        # Never written. The promise is dated from the launch, so the artifact that was
        # never created goes stale exactly as one that stopped being written would.
        launched_e="$(iso_epoch "$launched")"
        if [ -n "$launched_e" ]; then age=$((now - launched_e)); else age=0; fi
      fi
      if [ "$age" -gt "$cad_s" ]; then
        add_finding "stale-progress" "$name" "$aid" \
          "progress artifact $prog last changed ${age}s ago; the brief declared a cadence of \"$cadence\" (${cad_s}s)"
      fi
    else
      note_degradation "$name" "cadence-unreadable(\"${cadence:-none declared}\")-overdue-only"
    fi
  fi

  # OVERDUE — the one predicate every non-claims row can carry.
  if dur_s="$(parse_seconds "$dur")"; then
    launched_e="$(iso_epoch "$launched")"
    if [ -n "$launched_e" ]; then
      watched=1
      elapsed=$((now - launched_e))
      if [ "$elapsed" -gt "$dur_s" ]; then
        add_finding "overdue" "$name" "$aid" \
          "launched ${elapsed}s ago; the brief declared a duration of \"$dur\" (${dur_s}s)"
      fi
    else
      note_degradation "$name" "launched_at-unreadable-no-overdue"
    fi
  else
    note_degradation "$name" "duration-unreadable(\"${dur:-none declared}\")-no-overdue"
  fi

  # Nothing left to watch: the brief declared no threshold this sweeper can hold it to.
  # Recorded rather than assumed, so the gap is visible in the ledger instead of looking
  # like a clean bill of health.
  [ "$watched" -eq 0 ] && note_degradation "$name" "no-watchable-threshold"
  return 0
}

# Every name the roster declares, one per line. Read for the ack verb's "is this a row I
# know about?" warning only — never for evaluation, which reads whole rows. A symlinked
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

evaluate_roster() {
  FINDINGS=""; FINDING_COUNT=0; ROW_COUNT=0
  read_acked
  # A symlinked roster is not read at all (§8) — but this process stays ARMED over one, so
  # what it cannot watch is NAMED rather than returned on in silence. Every other
  # path-safety refusal in this script is loud and exits 2; this is the one branch that
  # keeps running, which is exactly why a silent return left the sweeper looking healthy
  # while watching nothing (Step-6 review C-2). Tested BEFORE `-f`, which is true THROUGH a
  # link to a file and false for a dangling one — both are the same unwatchable state.
  if [ -L "$ROSTER_FILE" ]; then
    note_degradation "(roster)" "symlinked-roster-unreadable"
    return 0
  fi
  # Absent is normal: `arm` runs before the session's first dispatch, and the roster
  # appears when that dispatch does.
  [ -f "$ROSTER_FILE" ] || return 0
  local line
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in "roster-state/${ROSTER_VERSION}|"*) : ;; *) continue ;; esac
    evaluate_row "$line"
  done < "$ROSTER_FILE"
}

flush_degradations() {
  [ -n "$DEGRADED_NEW" ] || return 0
  ledger_write "${LEDGER_SCHEMA}|event=degrade|at=$(iso_now)|epoch=$(now_epoch)|pid=$$|session=${SESSION_ID}|degraded=$(clean "$DEGRADED_NEW")"
  DEGRADED_NEW=""
}

# ---------------------------------------------------------------- delivery

deliver_findings() {
  # The findings file FIRST, then the ledger, then the exit. The order is the point: the
  # wake can be lost, so the durable record must already exist when the process is gone.
  if [ ! -e "$FINDINGS_FILE" ]; then
    printf '# bionic sweeper findings — schema %s — machine-local, safe to delete\n' \
      "$FINDING_SCHEMA" >> "$FINDINGS_FILE" 2>/dev/null && chmod 600 "$FINDINGS_FILE" 2>/dev/null
  fi
  {
    printf '# batch %s — %s finding(s) — sweeper pid %s, tick %ss\n' \
      "$(iso_now)" "$FINDING_COUNT" "$$" "$TICK"
    printf '%s' "$FINDINGS"
  } >> "$FINDINGS_FILE" 2>/dev/null

  ledger_write "${LEDGER_SCHEMA}|event=exit|at=$(iso_now)|epoch=$(now_epoch)|pid=$$|session=${SESSION_ID}|reason=finding|findings=${FINDING_COUNT}"

  # The wake itself. Facts only — what the roster promised, what the disk says now.
  local l
  printf '%s' "$FINDINGS" | while IFS= read -r l; do
    [ -n "$l" ] || continue
    printf 'sweeper: FINDING %s — %s: %s\n' \
      "$(line_field "$l" class)" "$(line_field "$l" name)" "$(line_field "$l" detail)"
  done
  say "$FINDING_COUNT finding(s) this tick; mirrored to $FINDINGS_FILE"
  say "exiting — the exit is the delivery. Re-arm first, then read the findings:"
  say "  $ARM_COMMAND"
  exit 0
}

# ---------------------------------------------------------------- verbs

case "$VERB" in

  status)
    read_open_arming
    warn_bad_pid
    read_acked
    [ "$ACKED_COUNT" -gt 0 ] && say "$ACKED_COUNT row(s) acked for this session (exempt from every class)"
    if pid_live "$OPEN_PID"; then
      say "a sweeper is live for this session (pid $OPEN_PID, armed $OPEN_AT, tick ${OPEN_TICK}s)"
      printf '%s|live=yes|pid=%s|tick=%s|armed_at=%s|session=%s|acked=%s|ledger=%s|findings=%s\n' \
        "$STATUS_SCHEMA" "$OPEN_PID" "$OPEN_TICK" "$OPEN_AT" "$SESSION_ID" "$ACKED_COUNT" "$LEDGER_FILE" "$FINDINGS_FILE"
      exit 0
    fi
    # The third answer. Nothing readable is live, but an unreadable open entry might be —
    # so this is not `live=no`, which is a claim about the world this script cannot support.
    # Exit 1 all the same: not-provably-live is what the dispatch nag acts on, and warning
    # over an unreadable ledger is the safe direction (silence would leave a session with
    # nothing provably watching and nothing said about it).
    if [ -z "$OPEN_PID" ] && [ -n "$OPEN_PID_BAD" ]; then
      say "cannot tell whether a sweeper is live for this session: the ledger's open arming"
      say "is unreadable. Resolve it before arming — see the note above."
      printf '%s|live=unknown|pid=|tick=|armed_at=|session=%s|acked=%s|ledger=%s|findings=%s\n' \
        "$STATUS_SCHEMA" "$SESSION_ID" "$ACKED_COUNT" "$LEDGER_FILE" "$FINDINGS_FILE"
      exit 1
    fi
    if [ -n "$OPEN_PID" ]; then
      say "the last arming (pid $OPEN_PID, armed $OPEN_AT) is no longer running; nothing is watching"
    else
      say "no sweeper is armed for this session"
    fi
    say "arm one with: $ARM_COMMAND"
    printf '%s|live=no|pid=%s|tick=%s|armed_at=%s|session=%s|acked=%s|ledger=%s|findings=%s\n' \
      "$STATUS_SCHEMA" "${OPEN_PID:-}" "${OPEN_TICK:-}" "${OPEN_AT:-}" "$SESSION_ID" "$ACKED_COUNT" "$LEDGER_FILE" "$FINDINGS_FILE"
    exit 1
    ;;

  retire)
    read_open_arming
    warn_bad_pid
    if [ -z "$OPEN_PID" ]; then
      say "no open arming for this session; nothing to retire"
      exit 0
    fi
    ledger_write "${LEDGER_SCHEMA}|event=retire|at=$(iso_now)|epoch=$(now_epoch)|pid=${OPEN_PID}|session=${SESSION_ID}|by=retire"
    if pid_live "$OPEN_PID"; then
      # The sweeper also reads the ledger every tick, so this signal only shortens the
      # wait; a machine where the signal does not land still retires within one tick.
      kill -TERM "$OPEN_PID" 2>/dev/null
      _waited=0
      while pid_live "$OPEN_PID" && [ "$_waited" -lt 50 ]; do
        sleep 0.1; _waited=$((_waited + 1))
      done
      if pid_live "$OPEN_PID"; then
        say "arming closed in the ledger; pid $OPEN_PID has not exited yet (it will within one tick)"
      else
        say "retired the sweeper armed at $OPEN_AT (pid $OPEN_PID)"
      fi
    else
      say "closed the ledger entry for pid $OPEN_PID, which was no longer running"
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
    _before="$(ledger_count '|event=ack|')"
    _recorded=""; _unknown=""
    for _name in "$@"; do
      _name="$(clean "$_name")"
      [ -n "$_name" ] || continue
      printf '%s\n' "$_known" | grep -qxF -- "$_name" \
        || _unknown="${_unknown}${_unknown:+, }${_name}"
      ledger_write "${LEDGER_SCHEMA}|event=ack|at=$(iso_now)|epoch=$(now_epoch)|pid=$$|session=${SESSION_ID}|name=${_name}"
      _recorded="${_recorded}${_recorded:+, }${_name}"
    done
    [ -n "$_recorded" ] || usage "ack needs at least one non-empty row name."

    _after="$(ledger_count '|event=ack|')"
    if [ "$_after" -le "$_before" ]; then
      die "REFUSED — the ack could not be journalled to $LEDGER_FILE."
      die "An unrecorded ack leaves the row watched and the sweeper firing on it, so the"
      die "failure is reported rather than assumed away."
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
      say "no roster row carries: $_unknown — recorded anyway; each is exempt the moment a"
      say "row of that name appears. Check the spelling against: $LEDGER_FILE"
    fi
    say "$ACKED_COUNT row(s) acked for this session; an acked row raises no finding of any class"
    exit 0
    ;;

  arm)
    read_open_arming
    warn_bad_pid
    if pid_live "$OPEN_PID"; then
      die "REFUSED — a sweeper is already live for this session: pid $OPEN_PID, armed at $OPEN_AT, tick ${OPEN_TICK}s."
      die "One sweeper per session is the invariant this wave exists to restore, so a second"
      die "arming is refused rather than stacked. Retire the live one first:"
      die "  $RETIRE_COMMAND"
      exit 1
    fi

    # FAIL-CLOSED over an entry this script cannot read. Nothing about the live case above
    # can be established here — that is the whole content of the state — so the choice is
    # between refusing an arm that may be unnecessary and starting a second sweeper over a
    # live one that nothing can enumerate. The second is the failure this wave exists to
    # end. No liveness test gates this: the script cannot distinguish a corrupt line with a
    # live sweeper behind it from one with nothing behind it, so it refuses in both.
    if [ -n "$OPEN_PID_BAD" ]; then
      die "REFUSED — the ledger carries an open arming whose pid is unreadable (\"$OPEN_PID_BAD\")."
      die "A sweeper may be live for this session and invisible to this script, so a second is"
      die "not started over it. Confirm none is running, then delete the ledger and arm again:"
      die "  pgrep -f session-sweeper.sh"
      die "  rm $LEDGER_FILE"
      die "  $ARM_COMMAND"
      exit 1
    fi

    mkdir -p "$STATE_DIR" 2>/dev/null
    if [ ! -d "$STATE_DIR" ]; then
      die "REFUSED — the state directory could not be created ($STATE_DIR)."
      exit 2
    fi

    # Survey before the first sleep: the arm entry has to name what this sweeper CANNOT
    # watch, and the only way to know that is to read the roster once. The findings this
    # pass produces are discarded — the loop below sleeps a full tick before the first
    # evaluation that can deliver, which is the grace an approximate promise needs.
    evaluate_roster
    FINDINGS=""; FINDING_COUNT=0
    _armed_degradations="$DEGRADED_NEW"; DEGRADED_NEW=""

    ledger_write "${LEDGER_SCHEMA}|event=arm|at=$(iso_now)|epoch=$(now_epoch)|pid=$$|tick=${TICK}|session=${SESSION_ID}|rows=${ROW_COUNT}|degraded=$(clean "$_armed_degradations")"
    if [ ! -s "$LEDGER_FILE" ]; then
      die "REFUSED — the arming could not be journalled to $LEDGER_FILE."
      die "An unledgered sweeper is invisible to the next arm and to the dispatch gate, so"
      die "it is not started at all."
      exit 2
    fi

    say "armed for session $SESSION_ID (pid $$, tick ${TICK}s, ${ROW_COUNT} row(s) on the roster)"
    [ -n "$_armed_degradations" ] && say "degraded rows (named, never guessed): $_armed_degradations"
    say "ledger:   $LEDGER_FILE"
    say "findings: $FINDINGS_FILE"

    # A `sleep` run in the foreground would hold a TERM until it finished — a 120 s tick
    # would make `retire` look wedged for two minutes. Backgrounding the sleep and
    # waiting on it lets the trap run the moment the signal lands.
    SLEEP_PID=""
    on_signal() {
      [ -n "$SLEEP_PID" ] && kill "$SLEEP_PID" 2>/dev/null
      exit 0
    }
    trap on_signal TERM INT

    retire_requested() {
      [ -f "$LEDGER_FILE" ] || return 1
      grep -qE "event=retire\|.*\|pid=$$\|" "$LEDGER_FILE" 2>/dev/null
    }

    while :; do
      sleep "$TICK" & SLEEP_PID=$!
      wait "$SLEEP_PID" 2>/dev/null
      SLEEP_PID=""

      if retire_requested; then
        say "retired; the ledger entry is closed. Nothing was stopped or judged."
        exit 0
      fi

      evaluate_roster
      flush_degradations
      [ "$FINDING_COUNT" -gt 0 ] && deliver_findings
    done
    ;;
esac
