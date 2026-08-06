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
# THE LEDGER is append-only and answers one question: is a sweeper live for this session?
#   arm     — timestamp, pid, effective tick, row count, per-row degradations
#   degrade — a degradation first seen after arm time (a row added mid-session)
#   retire  — closes the open entry by pid
#   exit    — closes it from inside, naming the reason and the finding count
# A second `arm` while the open entry's pid is LIVE is refused, naming that arming. This
# enforcement lives in the script because the doctrine it enforces is the one the wave
# exists to fix: monitors nobody could enumerate. A pid that is gone does not refuse — a
# killed or crashed sweeper must never wedge the session.
#
# Exit codes:
#   0 — arm delivered a finding, or was retired; retire completed; status found a live sweeper
#   1 — arm refused because a live arming already exists; status found no live sweeper
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

say()  { printf 'sweeper: %s\n' "$1"; }
die()  { printf 'sweeper: %s\n' "$1" >&2; }

usage() {  # [message]
  [ $# -gt 0 ] && die "$1"
  die "Usage:"
  die "  $ARM_COMMAND [--tick <seconds>]   watch this session's roster (default ${DEFAULT_TICK}s tick)"
  die "  $RETIRE_COMMAND                          close the live arming"
  die "  bash ~/.claude/hooks/session-sweeper.sh status   report whether one is live"
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
# copies are held together by the cross-gate agreement suite.

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

# The one question the ledger answers, asked by three readers (arm's refusal, `status`,
# and the unarmed nag in hooks/dispatch-preflight.sh): is an arming still open, and is its
# process still there? Entries are replayed in order — an arm opens, a retire or an exit
# naming the same pid closes.
OPEN_PID=""; OPEN_TICK=""; OPEN_AT=""
read_open_arming() {
  OPEN_PID=""; OPEN_TICK=""; OPEN_AT=""
  [ -f "$LEDGER_FILE" ] || return 0
  local line ev p
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in "$LEDGER_SCHEMA|"*) : ;; *) continue ;; esac
    ev="$(line_field "$line" event)"
    case "$ev" in
      arm)
        OPEN_PID="$(line_field "$line" pid)"
        OPEN_TICK="$(line_field "$line" tick)"
        OPEN_AT="$(line_field "$line" at)"
        ;;
      retire|exit)
        p="$(line_field "$line" pid)"
        if [ -n "$OPEN_PID" ] && [ "$p" = "$OPEN_PID" ]; then
          OPEN_PID=""; OPEN_TICK=""; OPEN_AT=""
        fi
        ;;
    esac
  done < "$LEDGER_FILE"
}

# A pid this shell can signal. Recycling is a theoretical false-positive and is accepted:
# the cost is one refused arm, and the fix is one `retire`.
pid_live() { [ -n "$1" ] && kill -0 "$1" 2>/dev/null; }

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

# Done-detection. Every declared deliverable must be present AND non-empty: an empty file
# is a path that got created, not a deliverable that got written (the same substance test
# hooks/stop-check.sh applies). Deliverables are comma-separated, as hooks/stop-check.sh
# reads them.
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
    [ -s "$(abs_path "$p")" ] || return 1
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
  # whatever its clock says.
  if deliverables_all_present "$deliv"; then
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

evaluate_roster() {
  FINDINGS=""; FINDING_COUNT=0; ROW_COUNT=0
  # Absent is normal: `arm` runs before the session's first dispatch, and the roster
  # appears when that dispatch does. A symlinked roster is not read at all (§8).
  [ -f "$ROSTER_FILE" ] || return 0
  [ -L "$ROSTER_FILE" ] && return 0
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
    if pid_live "$OPEN_PID"; then
      say "a sweeper is live for this session (pid $OPEN_PID, armed $OPEN_AT, tick ${OPEN_TICK}s)"
      printf '%s|live=yes|pid=%s|tick=%s|armed_at=%s|session=%s|ledger=%s|findings=%s\n' \
        "$STATUS_SCHEMA" "$OPEN_PID" "$OPEN_TICK" "$OPEN_AT" "$SESSION_ID" "$LEDGER_FILE" "$FINDINGS_FILE"
      exit 0
    fi
    if [ -n "$OPEN_PID" ]; then
      say "the last arming (pid $OPEN_PID, armed $OPEN_AT) is no longer running; nothing is watching"
    else
      say "no sweeper is armed for this session"
    fi
    say "arm one with: $ARM_COMMAND"
    printf '%s|live=no|pid=%s|tick=%s|armed_at=%s|session=%s|ledger=%s|findings=%s\n' \
      "$STATUS_SCHEMA" "${OPEN_PID:-}" "${OPEN_TICK:-}" "${OPEN_AT:-}" "$SESSION_ID" "$LEDGER_FILE" "$FINDINGS_FILE"
    exit 1
    ;;

  retire)
    read_open_arming
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

  arm)
    read_open_arming
    if pid_live "$OPEN_PID"; then
      die "REFUSED — a sweeper is already live for this session: pid $OPEN_PID, armed at $OPEN_AT, tick ${OPEN_TICK}s."
      die "One sweeper per session is the invariant this wave exists to restore, so a second"
      die "arming is refused rather than stacked. Retire the live one first:"
      die "  $RETIRE_COMMAND"
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
