#!/bin/bash
# SESSION POKER — the tick that decides whether a dispatched session needs a nudge.
# Design: .bionic/docs/specs/epic-16-landing-contract/wave-02-fact-based-supervision.spec.md
#         §Design ("Poker"), succeeding epic-09/epic-10's resident cron poker — deliberately
#         NOT resurrected (spec §Rejected alternatives: "OS cron / launchd for the tick" is
#         residency in configuration form, ratified against).
# [WALL: hooks/session-poker.test.sh]
#
# This is NOT a hook, exactly like hooks/session-sweeper.sh: it lives in hooks/ for
# test-harness pairing and bootstrap installation only (claude-bootstrap.sh installs every
# hooks/*.sh into ~/.claude/hooks/) and is never registered in MANAGED_HOOKS. It is invoked
# ON DEMAND, one question per invocation, and holds no process open:
#
#     bash ~/.claude/hooks/session-poker.sh tick       one decision over this roster (read-only)
#     bash ~/.claude/hooks/session-poker.sh interval    the configured self-wake interval, seconds
#
# WHAT IT IS. The poker is a session-scoped self-wake, not a resident process (spec R1). The
# doctrine that ARMS it lives in skills/canonical-sdlc/SKILL.md §Dispatch: the orchestrator's
# own harness self-wake primitive sleeps `interval` seconds and calls `tick`; THIS SCRIPT
# DECIDES, the harness schedules. `tick` is exactly ONE `verdict` read over the whole roster,
# plus — for any UNMET row only — a direct roster lookup of that one row's own
# `duration=`/`launched_at=` fields (verdict's own output carries neither). Never a per-row
# verdict call, never a second judgment of MET/UNMET/STILL-LIVE: that judgment belongs to
# `verdict` alone (ownership table, spec §Design) and this script only consumes it.
#
# WHAT IT NEVER DOES. It never stops, kills, arms, or notifies on its own authority. The
# decision is printed on stdout as ONE machine-readable line, and the caller (the doctrine's
# self-wake loop) is what turns a NOTIFY line into an actual push. Zero authority, exactly
# like `verdict` (ADR-003) — this verb cannot even record that it ran.
#
# AN ACKED ROW IS CLOSED HERE, exactly as it is for the other three consumers of the
# verdict line (hooks/landing-gate.sh, hooks/stop-orders.sh, hooks/stop-guard.sh): it is
# neither open nor notifiable. `acked=` is read PER ROW off the verdict line below, never
# from the ledger — the verb that owns the ledger is the verb that prints the answer.
#
# DECISIONS, in precedence order:
#   DISARM   the roster carries no OPEN row — an empty roster (spec's "disarmed on empty
#            roster" invariant, literally) generalizes here to the roster having nothing
#            open at all: every row MET, WAIVED or ACKED is the same "nothing left to wait
#            for" as no rows existing, so all read DISARM (S2 design decision plus epic-16
#            w2 Step-6 remediation R4, both logged to the plan).
#   NOTIFY   at least one UNACKED UNMET row's elapsed time (now − launched_at) exceeds its own
#            declared `duration=`, read by the same parser `verdict` uses for `cadence=`
#            (hooks/session-sweeper.sh's parse_seconds, duplicated below — see that file's
#            fix, same commit lineage, epic-16 w2 S2). A row whose duration is unreadable or
#            whose launch time is unreadable is skipped, never guessed at — the same
#            "refuse rather than invent" rule verdict itself follows.
#   QUIET    open rows exist (UNMET-not-past-duration, STILL-LIVE, or AMBIGUOUS) but none
#            qualify for NOTIFY — the tick ran, found nothing to say, and that is reported.
#
# Exit codes mirror hooks/session-sweeper.sh's verdict verb, because a caller already knows
# how to branch on this shape:
#   0 — DISARM or QUIET
#   1 — NOTIFY (something needs surfacing)
#   2 — usage error, or a refusal (propagated from the sweeper read, or raised here)
#   3 — no session key
#
# Session key: CLAUDE_CODE_SESSION_ID, exactly as hooks/session-sweeper.sh takes it.
#
# THE SWEEPER IS THIS SCRIPT'S SIBLING, resolved exactly as hooks/landing-gate.sh resolves
# it: no PATH lookup (a hook's PATH is not ours to trust), no environment override (a seam on
# the path under test would leave the production path unverified) — so the same resolution
# holds in the repo and in ~/.claude/hooks/ once claude-bootstrap.sh installs both.

set -u

POKER_DECISION_SCHEMA="poker-tick/v1"
POKER_INTERVAL_DEFAULT="30m"

say()  { printf 'poker: %s\n' "$1"; }
die()  { printf 'poker: %s\n' "$1" >&2; }

usage() {  # [message]
  [ $# -gt 0 ] && die "$1"
  die "Usage:"
  die "  bash ~/.claude/hooks/session-poker.sh tick       one decision over this session's roster (read-only)"
  die "  bash ~/.claude/hooks/session-poker.sh interval    the configured self-wake interval, in seconds"
  exit 2
}

[ $# -eq 1 ] || usage "exactly one verb required."
VERB="$1"
case "$VERB" in
  tick|interval) : ;;
  *) usage "unknown verb: $VERB" ;;
esac

# ---------------------------------------------------------------- portable facts
#
# DELIBERATELY DUPLICATED from hooks/session-sweeper.sh, CODE-identical (not byte-identical —
# each file's comments explain its own copy in its own terms, exactly as
# tests/cross-gate-agreement.test.sh's §I.1 already treats signature comments for its own
# duplicated family), for the reason that file's own header gives (§9 there): a sourced
# library the installer misses is a silently inert consumer, and every duplicate here answers
# the SAME question its sibling answers so the two cannot quietly drift into different
# readings of one fact. `parse_seconds` is duplicated post-fix (epic-16 w2 S2, same commit
# that fixed the original). The five are held together by tests/cross-gate-agreement.test.sh
# §O, which compares executable text with every pure-comment line stripped from both sides —
# epic-16 w2 Step-6 remediation R3, closing rd review D-1 (this claim used to name no test,
# and was already false for parse_seconds before that fix).

now_epoch() { date -u +%s; }
iso_now()   { date -u +%Y-%m-%dT%H:%M:%SZ; }

iso_epoch() {  # <ISO-8601 Z> -> epoch seconds, empty if unreadable
  date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$1" +%s 2>/dev/null \
    || date -u -d "$1" +%s 2>/dev/null
}

# One field out of a versioned pipe-delimited line, BY KEY, never by position — same
# rationale as hooks/session-sweeper.sh's copy: field order is not a contract.
line_field() {  # <line> <key>
  printf '%s' "$1" | tr '|' '\n' | grep "^$2=" | head -1 | cut -d= -f2-
}

clean() {  # <value>
  printf '%s' "$1" | tr '\n\r\t|' '    ' | sed -e 's/[[:cntrl:]]/ /g' -e 's/  */ /g' \
    -e 's/^ *//' -e 's/ *$//' | cut -c 1-400
}

# The prose duration/cadence parser. Deliberate limits, each a refusal rather than a guess —
# see hooks/session-sweeper.sh's copy for the full rationale (its own comments there are
# specific to ITS callers, e.g. `cadence=`, which this script never reads — that is why this
# copy's comments are shorter, not why the code differs). This is that function's POST-FIX
# body, CODE-identical (§O compares it with comments on both sides stripped).
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
  printf '%s' "$s" | grep -qE '[0-9]+\.[0-9]+' && return 1
  allnums="$(printf '%s' "$s" | grep -oE '[0-9]+')"
  [ "$(printf '%s\n' "$allnums" | grep -c '[0-9]')" -eq "$(printf '%s\n' "$nums" | grep -c '[0-9]')" ] \
    || return 1
  printf '%s' "$((hi * mult))"
}

# ---------------------------------------------------------------- the pinned root
#
# DELIBERATELY DUPLICATED, byte for byte, from hooks/dispatch-preflight.sh's copy
# (the origin is hooks/canonical-sdlc-governing-skill.sh; tests/cross-gate-agreement.test.sh
# §N.1/§N.2 compare six copies now, this one included). epic-16 w2 Step-6 remediation R3,
# closing ap review A-1: this script used to answer `git rev-parse --show-toplevel`, which
# names the WORKTREE root. A worktree cwd would then poll a roster file that only ever
# existed under the MAIN repository, read it as empty, and DISARM — silently and
# permanently, since DISARM ends the self-wake for the rest of the session (doctrine,
# skills/canonical-sdlc/SKILL.md §Dispatch). `--git-common-dir` maps a worktree back onto its
# main repository, so both this script and the roster's writer land on one address space.
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

# ---------------------------------------------------------------- the interval knob
#
# `poker-interval:` in <project>/.bionic/config.yaml — the exact convention
# hooks/context-spend.sh (`docs-root:`) and hooks/canonical-sdlc-governing-skill.sh
# (`docs-root:`, `rigor-floor:`) already use: a project-scoped key, grep'd and sed-stripped,
# never a YAML parser. ASSUMPTION (logged to the plan, S2): this is the first CONSUMER of
# that convention outside canonical-sdlc's own hooks; no config.yaml ships by default, so an
# absent file or an absent key both read as the documented default, 30m — a knob nobody has
# touched behaves as if it were never added. A malformed override REFUSES rather than
# silently falling back to the default, matching this repo's "refuse, never guess" posture
# everywhere else a prose value is read (parse_seconds itself, the two hooks above).
poker_interval_seconds() {
  local repo cfg raw ov
  repo="$(resolve_project_root "$PWD/." "$PWD")"
  cfg="$repo/.bionic/config.yaml"
  raw="$POKER_INTERVAL_DEFAULT"
  if [ -f "$cfg" ] && [ ! -L "$cfg" ]; then
    ov="$(grep -E '^[[:space:]]*poker-interval[[:space:]]*:' "$cfg" 2>/dev/null | head -1 \
      | sed -E 's/^[[:space:]]*poker-interval[[:space:]]*:[[:space:]]*//' \
      | tr -d '\r' | sed -e 's/[[:space:]]*$//')"
    [ -n "$ov" ] && raw="$ov"
  fi
  parse_seconds "$raw"
}

# ---------------------------------------------------------------- verbs

case "$VERB" in

  interval)
    SECS="$(poker_interval_seconds)" || {
      die "REFUSED — the configured poker-interval could not be read as a duration."
      die "Fix or remove the 'poker-interval:' line in .bionic/config.yaml; the default is $POKER_INTERVAL_DEFAULT."
      exit 2
    }
    printf '%s\n' "$SECS"
    exit 0
    ;;

  tick)
    SESSION_ID="${CLAUDE_CODE_SESSION_ID:-}"
    if [ -z "$SESSION_ID" ]; then
      die "REFUSED — no session key (CLAUDE_CODE_SESSION_ID is unset or empty)."
      die "A tick answers for ONE session's roster, so without the key there is nothing to read."
      exit 3
    fi

    # The sweeper is this script's sibling — same resolution as hooks/landing-gate.sh's.
    SWEEPER="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/session-sweeper.sh"
    if [ ! -f "$SWEEPER" ]; then
      die "REFUSED — sibling hooks/session-sweeper.sh not found; nothing was read."
      exit 2
    fi

    REPO="$(resolve_project_root "$PWD/." "$PWD")"
    REPO_REAL="$(cd "$REPO" 2>/dev/null && pwd -P)"
    if [ -z "$REPO_REAL" ]; then
      die "REFUSED — cannot resolve the working directory."
      exit 2
    fi
    ROSTER_FILE="$REPO_REAL/.bionic/tmp/roster-${SESSION_ID}.state"

    # EXACTLY ONE verdict read over the whole roster (no name argument), run from the repo
    # root exactly as landing-gate.sh runs it. `|| exit 9` keeps a failed `cd` out of the
    # exit-1 band, which is NOTIFY's alone.
    VERDICT_OUT=$( cd "$REPO_REAL" 2>/dev/null || exit 9
                   CLAUDE_CODE_SESSION_ID="$SESSION_ID" bash "$SWEEPER" verdict 2>&1 )
    VERDICT_RC=$?
    if [ "$VERDICT_RC" -eq 9 ]; then
      die "REFUSED — could not enter $REPO_REAL to read the roster."
      exit 2
    fi
    # 2 (a refusal the sweeper itself raised — a symlinked roster or ledger) and 3 (no
    # session key, unreachable here since SESSION_ID was already checked) propagate
    # verbatim: a tick that cannot trust its one read has nothing to decide from.
    if [ "$VERDICT_RC" -eq 2 ] || [ "$VERDICT_RC" -eq 3 ]; then
      die "REFUSED — the verdict read did not complete: $VERDICT_OUT"
      exit "$VERDICT_RC"
    fi

    TOTAL=0; OPEN=0; NOTIFY_ROWS=""; NOTIFY_DETAIL=""
    while IFS= read -r LINE; do
      case "$LINE" in "landing-verdict/v1|"*) : ;; *) continue ;; esac
      TOTAL=$((TOTAL + 1))
      RNAME="$(line_field "$LINE" name)"
      RSTATE="$(line_field "$LINE" state)"

      # THE ACK CLOSES THE ROW HERE TOO, before the state is looked at at all: excluded from
      # OPEN and therefore from DISARM's precondition, and excluded from NOTIFY eligibility.
      # Read per row off the verdict line this loop is already walking — never from the
      # ledger, whose one owner is the verb that prints this line (hooks/session-sweeper.sh,
      # S9) — and spelled exactly as the three consumers that already read it:
      # hooks/landing-gate.sh:214, hooks/stop-orders.sh:319, hooks/stop-guard.sh:491.
      # This is what makes the ack verb's own closing sentence true —
      #   hooks/session-sweeper.sh:817 "an acked row is closed for every reader"
      # — which it was not while this script was the fourth reader that ignored the field
      # (cs review C-4, epic-16 w2 Step-6 remediation R4). Two structural consequences were
      # riding on the omission, both worse than the noise: an acked-UNMET row is never MET
      # and never WAIVED, and its artifact was accounted for by a human rather than written
      # to disk, so it held OPEN above zero PERMANENTLY and DISARM — the end of the
      # self-wake — was unreachable by the ordinary path that closes an artifact-less row;
      # and every tick re-notified the same closed work, growing the NOTIFY set
      # monotonically across a wave. AC-7's contract moves with this (assumption 41), which
      # is why hooks/session-poker.test.sh §3 re-authors the accelerated-clock cases rather
      # than re-running them.
      #
      # TOTAL still counts an acked row: it is on the roster, and "how many contracts does
      # this session carry" is not the question the ack answers. Only `open=` moves.
      [ "$(line_field "$LINE" acked)" = "yes" ] && continue

      case "$RSTATE" in
        MET|WAIVED) : ;;                      # closed — not open
        *)          OPEN=$((OPEN + 1)) ;;      # STILL-LIVE, UNMET, AMBIGUOUS — open
      esac
      [ "$RSTATE" = "UNMET" ] || continue

      # Duration is a SECOND, ADVISORY-ONLY read of this one row — never a re-judgment of
      # MET/UNMET, which stays verdict's alone. The roster is append-only; the last line
      # carrying this name is its latest contract, the same row verdict itself just folded.
      # Filtered to the roster-state/v1 schema FIRST (t6-review.md F-1): a landing-swept/v1
      # marker for this same name also carries `|name=<name>|` and is appended AFTER the
      # roster rows, so an unfiltered `tail -1` takes the marker instead — it has no
      # duration=/launched_at=, and the row's overdue NOTIFY goes silent for the rest of the
      # session. Same schema-prefix discipline as every other roster reader in the fleet
      # (e.g. hooks/execution-recorder.sh's `roster-state/${ROSTER_VERSION}|` filters).
      ROW_LINE="$(grep -F "roster-state/v1|" "$ROSTER_FILE" 2>/dev/null \
        | grep -F "|name=${RNAME}|" | tail -1)"
      [ -n "$ROW_LINE" ] || continue
      DUR_RAW="$(line_field "$ROW_LINE" duration)"
      LAUNCHED_RAW="$(line_field "$ROW_LINE" launched_at)"
      DUR_S="$(parse_seconds "$DUR_RAW")" || continue
      LE="$(iso_epoch "$LAUNCHED_RAW")"
      [ -n "$LE" ] || continue
      AGE=$(( $(now_epoch) - LE ))
      [ "$AGE" -gt "$DUR_S" ] || continue
      NOTIFY_ROWS="${NOTIFY_ROWS}${NOTIFY_ROWS:+,}$(clean "$RNAME")"
      NOTIFY_DETAIL="${NOTIFY_DETAIL}${NOTIFY_DETAIL:+; }$(clean "$RNAME"): $(line_field "$LINE" detail) (elapsed ${AGE}s past declared duration \"$DUR_RAW\" (${DUR_S}s))"
    done <<EOF
$VERDICT_OUT
EOF

    # "No roster" and "empty roster" are different facts, and only the latter may DISARM
    # (ap review A-1, item 2). A roster with zero verdict lines because the file plain does
    # not exist is indistinguishable, from the arithmetic alone, from a roster that exists
    # and legitimately has nothing open yet — but the first case is usually the wrong project
    # root having been resolved, and DISARM is silent and terminal for the rest of the
    # session (doctrine, skills/canonical-sdlc/SKILL.md §Dispatch: "DISARM also ends the
    # self-wake"). Checked only on the TOTAL=0 path: any row at all on the roster proves the
    # file exists, so OPEN=0-with-TOTAL>0 can never be the absent-file case.
    if [ "$TOTAL" -eq 0 ] && [ ! -e "$ROSTER_FILE" ]; then
      die "REFUSED — no roster at $ROSTER_FILE; this is not the same as an empty one."
      die "An absent roster usually means the wrong project root was resolved, or nothing has"
      die "been dispatched yet on this session — either way, nothing was read to decide DISARM"
      die "from, and DISARM ends the self-wake for the rest of this session."
      exit 2
    fi

    # DISARM — no open row, whether because the roster is empty or because every row on it
    # is already MET/WAIVED (S2 design decision: "no open rows" generalizes the spec's
    # literal "disarmed on empty roster", logged to the plan).
    if [ "$TOTAL" -eq 0 ] || [ "$OPEN" -eq 0 ]; then
      printf '%s|at=%s|session=%s|decision=DISARM|total=%s|open=%s\n' \
        "$POKER_DECISION_SCHEMA" "$(iso_now)" "$SESSION_ID" "$TOTAL" "$OPEN"
      say "DISARM — no open row on this roster; the self-wake may stop."
      exit 0
    fi

    if [ -n "$NOTIFY_ROWS" ]; then
      printf '%s|at=%s|session=%s|decision=NOTIFY|total=%s|open=%s|rows=%s|detail=%s\n' \
        "$POKER_DECISION_SCHEMA" "$(iso_now)" "$SESSION_ID" "$TOTAL" "$OPEN" \
        "$NOTIFY_ROWS" "$(clean "$NOTIFY_DETAIL")"
      say "NOTIFY — past declared duration: $NOTIFY_DETAIL"
      exit 1
    fi

    printf '%s|at=%s|session=%s|decision=QUIET|total=%s|open=%s\n' \
      "$POKER_DECISION_SCHEMA" "$(iso_now)" "$SESSION_ID" "$TOTAL" "$OPEN"
    say "QUIET — $OPEN open row(s) on this roster, none past their declared duration."
    exit 0
    ;;
esac
