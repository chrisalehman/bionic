# payload/scripts/lib/observe.sh — THE OBSERVATION: one function of the roster row and
# the file system (epic-23 wave-15-fixit-182, REQ-2/D2; ADR-028).
#
#     BIONIC_LIB_WANT="… observe.sh"
#     . "$BIONIC_LIB/observe.sh"
#
# WHAT AN OBSERVATION IS. The facts about a dispatched agent that a stopper can read NOW:
# the working log's mtime and size, the contracted progress artifact's state, each
# contracted deliverable's presence, the row's declared cadence, and the `alive`/`idle`/
# `delivered` classification derived from them. It is produced at the moment of the act and
# never persisted for a later reader.
#
# WHY IT IS A LIBRARY. Until 1.8.1 the look lived in `hooks/stop-check.sh`, a verb the
# operator ran by hand; the stop gate could not take one, so it admitted a stop only against
# a RECORD of an earlier look — written by `hooks/execution-recorder.sh`, owned by an actor
# (D-3), staled by activity (D-1/D-6) and consumed once (D-2). On 2026-09-15 that gate
# refused a correct stop with "no observation exists in this repo" because nobody had run
# the verb: the wall asserted a condition it had not observed. ADR-028 rules that a wall
# asserts only what it can observe at the moment of the act, so the look became a function
# two callers share — `hooks/stop-check.sh` prints it, `hooks/stop-guard.sh` decides on it —
# and the record, its writer arm and the D-1/D-2/D-3/D-6 accounting over it left the tree.
#
# NOT A SUBPROCESS SEAM. The gate calls these functions IN PROCESS rather than running the
# verb and parsing its line. A text seam between these two parties broke once already
# (Step-6 review F-1, the command-line grammar divergence that recorded a look at an agent
# nobody had examined), and it sits on an irreversible path.
#
# CALLER CONTRACT. Set the five inputs, call `observe_agent <target> [deliverable …]`, then
# read the `OBS_*` answers. Nothing here writes a file, refuses anything, or exits.
#
#   OBSERVE_ROOT        the repository root the contract is written against (required)
#   OBSERVE_SESSION     this session's id (required — the roster is keyed by it)
#   OBSERVE_TRANSCRIPT  this session's transcript, `<projects>/<slug>/<sid>.jsonl`
#   OBSERVE_DOCS_ROOT   the docs root a `record/…` contract path resolves against
#   OBSERVE_ROSTER      the roster file (default `<root>/.bionic/tmp/roster-<sid>.state`)
#
# TWO OPTIONAL OVERRIDES, the verb's flags in variable form. Empty means "not named", which
# is a different fact from "named and absent" — the D-6 distinction a blank would erase.
#
#   OBSERVE_PROGRESS_ARG  an explicit progress path, overriding the roster's
#   OBSERVE_CLAIMS_ARG    an explicit subprocess claim pattern, overriding the roster's
#
# [WALL: tests/stop-check.test.sh, tests/stop-guard.test.sh]

# The roster schema this library reads. A row it cannot read is a row it does not guess at.
OBSERVE_ROSTER_VERSION="v1"

# The machine line's schema token, printed by `observe_machine_line`. Versioned so a reader
# can refuse a shape it does not read rather than guess at it.
OBSERVE_MACHINE_SCHEMA="stop-check-observation/v1"

# HOW QUIET IS TOO QUIET WHEN THE CONTRACT DID NOT SAY. The ratified liveness contract
# (2026-08-05) extends the ≥15m rule by one number — "too quiet" means quieter than the
# AUTHOR'S OWN declaration — so a row that declared a cadence is measured against it and a
# row that declared none falls back to the rule the contract widened. Fifteen minutes is the
# fail-CLOSED choice for the gate that consumes this: a generous window calls a dormant agent
# alive, which costs a refused stop and a retry, where a mean one calls a working agent idle
# and the stop destroys work nobody looked at.
OBSERVE_CADENCE_DEFAULT_S=900

# ---------- portable file facts ----------
#
# ONE DEFINITION NOW. `hooks/stop-check.sh` and `hooks/stop-guard.sh` each carried a copy of
# these two, byte for byte, held together by the resolver agreement battery in
# tests/cross-gate-agreement.test.sh §C. The copies were the price of the no-library rule
# (TDD §9: a sourced file the installer misses is a silently inert wall) and the loader's
# fail-closed qualification is what repealed it — a hook whose library is missing refuses or
# steps aside out loud, so there is no silent inertness left to buy.
file_mtime() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0; }
file_size()  { stat -f %z "$1" 2>/dev/null || stat -c %s "$1" 2>/dev/null || echo 0; }

# THE NEWEST COPY OF AN AGENT'S LOG, ANYWHERE UNDER ONE PROJECT DIRECTORY (D8; REQ-8;
# epic-23 wave-20 T5). The harness re-files a dispatched agent's transcript under whichever
# session is talking to it NOW, and `adopted_from=` only ever names the session that
# LAUNCHED it — a second `/clear`+resume leaves an INTERMEDIATE adopter's own copy named on
# no row at all, invisible to a reader that walks "this session, then the launcher" as a
# fixed chain (research D2 §REQ-8, triage-A). The newest copy of the id's log, by mtime,
# anywhere under the project directory, is the one to trust: the glob is scoped to the
# EXACT agent id, a 16-hex random suffix, so no other agent's log is ever a candidate.
#
# <project-dir> is the directory one level above every session directory —
# `<project-dir>/<session-id>/subagents/agent-<id>.jsonl` — which is what
# `${transcript%/*}` already is for a transcript path shaped `<project-dir>/<sid>.jsonl`.
agent_log_newest() {  # <agent-id> <project-dir> -> newest matching path on stdout, nonzero if none
  local id="$1" proj="$2" f newest="" newest_m=-1 m
  [ -n "$id" ] || return 1
  [ -n "$proj" ] && [ -d "$proj" ] || return 1
  for f in "$proj"/*/subagents/"agent-${id}.jsonl"; do
    [ -f "$f" ] || continue
    m="$(file_mtime "$f")"
    case "$m" in ''|*[!0-9]*) m=0 ;; esac
    if [ "$m" -gt "$newest_m" ]; then
      newest="$f"; newest_m="$m"
    fi
  done
  [ -n "$newest" ] || return 1
  printf '%s' "$newest"
  return 0
}

# One field out of a versioned pipe-delimited line, BY KEY, never by position (checklist
# A6): a fixed-field-order parser breaks undiagnosably the moment a field is added, so an
# unknown extra field must be inert here.
line_field() {  # <line> <key>
  printf '%s' "$1" | tr '|' '\n' | grep "^$2=" | head -1 | cut -d= -f2-
}

# Claude Code names a project directory by slugifying its path.
slugify() { printf '%s' "$1" | sed 's/[^a-zA-Z0-9]/-/g'; }

fmt_epoch() {
  date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || printf 'epoch:%s\n' "$1"
}

fmt_age() {  # <seconds> -> "3m 12s"
  local s="$1"
  [ "$s" -lt 0 ] 2>/dev/null && s=0
  if   [ "$s" -lt 60 ];    then printf '%ds\n' "$s"
  elif [ "$s" -lt 3600 ];  then printf '%dm %ds\n' $((s / 60)) $((s % 60))
  elif [ "$s" -lt 86400 ]; then printf '%dh %dm\n' $((s / 3600)) $(((s % 3600) / 60))
  else                          printf '%dd %dh\n' $((s / 86400)) $(((s % 86400) / 3600))
  fi
}

# Existence only, for P2 (Liveness contract, ratified 2026-08-05). `pgrep -f` matches the
# full command line; a `ps` fallback covers a machine without it.
observe_claims_live() {  # <pattern> -> 0 if a process matches, 1 otherwise
  local pat="$1"
  if command -v pgrep >/dev/null 2>&1; then
    pgrep -f -- "$pat" >/dev/null 2>&1
    return $?
  fi
  ps -eo command 2>/dev/null | grep -qF -- "$pat"
}

# A `|`, a newline or a control character inside a VALUE would forge a field. Every value on
# the machine line is operator-supplied — the typed target, the deliverable paths, the
# progress path — so they are normalized rather than refused: this library's job is to report
# evidence, and a target with an odd character in it is still a target somebody asked about.
observe_mline_value() {  # <value>
  printf '%s' "$1" | tr '\n\r\t|' '    ' | sed -e 's/[[:cntrl:]]/ /g' -e 's/  */ /g' \
    -e 's/^ *//' -e 's/ *$//' | cut -c 1-400
}

# PROSE TO SECONDS. A third reading of the grammar `hooks/session-sweeper.sh` owns and
# `hooks/session-poker.sh` copies (both at their own `parse_seconds`; §O of
# tests/cross-gate-agreement.test.sh holds all three CODE-identical). It is restated rather
# than shared for the reason run.sh's `live_runs` states: `parse_seconds` lives in two HOOKS
# and a library cannot source a hook. The cadence a dispatch declares is prose — "~6m",
# "5 min", "every 300 seconds" — and an unreadable one is the default rather than a guess.
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
  grep -qE '[0-9]+\.[0-9]+' <<< "$s" && return 1
  allnums="$(printf '%s' "$s" | grep -oE '[0-9]+')"
  [ "$(printf '%s\n' "$allnums" | grep -c '[0-9]')" -eq "$(printf '%s\n' "$nums" | grep -c '[0-9]')" ] \
    || return 1
  printf '%s' "$((hi * mult))"
}

# ---------- resolving a contracted path ----------
#
# The paths a contract names arrive as brief prose, and the spelling every task brief uses
# for an artifact under the docs root is `record/<wave>/x.md`. Resolving nothing at all
# stat'ed a relative path against whatever directory the observer happened to stand in, so a
# present progress file read `absent` and a landed deliverable read `ABSENT` — an observation
# that decides nothing, deciding wrongly (epic-17 W6 S15, A-6.6 (c)).
#
# RESOLUTION IS NOT A VERDICT. A path that climbs out with `..` resolves and is reported like
# any other; the landing gate is where a deliverable is judged.
observe_abs_path() {  # <path, as the contract spells it> -> absolute
  case "$1" in
    /*)       printf '%s\n' "$1" ;;
    record/*) printf '%s/%s\n' "${OBSERVE_DOCS_ROOT:-$OBSERVE_ROOT}" "$1" ;;
    *)        printf '%s/%s\n' "${OBSERVE_ROOT:-.}" "$1" ;;
  esac
}

# ---------- the roster walk ----------
#
# TWO ROWS CAN CARRY ONE AGENT — the dispatch writes the CONTRACT, the recorder writes the id
# one state later — so the id and the contract are collected separately rather than read off
# one chosen row. Preferring the row WITH the id loses a contract recorded after it;
# preferring the last row loses the id.
#
# `confirmed` or `identified`, never `intended`: the id on an unconfirmed row is a claim
# about a launch nothing has observed (Step-6 review C-2).
OBS_ROW_BY_ID=""; OBS_ROW_BY_NAME=""; OBS_ROW_WITH_ID=""
observe_roster_walk() {  # <key>
  local key="$1" rline rid rname f="$OBSERVE_ROSTER"
  OBS_ROW_BY_ID=""; OBS_ROW_BY_NAME=""; OBS_ROW_WITH_ID=""
  [ -n "$f" ] || return 0
  [ -f "$f" ] || return 0
  [ -L "$f" ] && return 0
  # Not read, rather than read and failing: an unopenable file would put the shell's own
  # "Permission denied" on a gate's stderr, where every byte is a refusal a reader parses.
  [ -r "$f" ] || return 0
  while IFS= read -r rline; do
    case "$rline" in '#'*|'') continue ;; esac
    case "$rline" in "roster-state/${OBSERVE_ROSTER_VERSION}|"*) : ;; *) continue ;; esac
    rid=$(line_field "$rline" agent_id)
    rname=$(line_field "$rline" name)
    case "$(line_field "$rline" status)" in
      confirmed|identified)
        [ -n "$rid" ] && [ "$rid" = "$key" ] && OBS_ROW_BY_ID="$rline"
        [ -n "$rid" ] && [ -n "$rname" ] && [ "$rname" = "$key" ] && OBS_ROW_WITH_ID="$rline"
        ;;
    esac
    [ -n "$rname" ] && [ "$rname" = "$key" ] && OBS_ROW_BY_NAME="$rline"
  done < "$f"
  return 0
}

# ---------- the observation ----------
#
# `observe_agent <typed-target> [contracted deliverable …]` — resolves the target against
# THIS SESSION'S ROSTER, stats what the contract names, and classifies. It answers in
# globals rather than on stdout because a stop gate needs eight facts out of one look and
# parsing them back out of a line would be the very seam D2 rejected.
#
#   OBS_OK              1 when the target resolved to an agent id, 0 otherwise
#   OBS_FAIL            `no-id` when the register carries no id for the name
#   OBS_NAME OBS_ID     the resolved name and transcript-form agent id
#   OBS_ADOPTED_FROM    the session that LAUNCHED it, when this one adopted it
#   OBS_SESSION         the session its working log is filed under
#   OBS_ROW             the roster row the contract was read off
#   OBS_LOG             the working log path, whether or not it exists
#   OBS_LOG_MTIME OBS_LOG_SIZE OBS_LOG_AGE
#   OBS_DELIVERABLES    `<state>:<path>` per contracted deliverable, comma-joined
#   OBS_DELIV_PATHS     the contracted paths as the contract spells them, comma-joined
#   OBS_DELIV_STATE     `delivered` (every one present and non-empty) / `pending` / `none`
#   OBS_DELIV_SOURCE    `args` | `roster` | `none`
#   OBS_DELIV_MISMATCH  what the roster recorded, when the caller named something else
#   OBS_PROGRESS OBS_PROGRESS_ABS OBS_PROGRESS_STATE OBS_PROGRESS_MTIME OBS_PROGRESS_AGE
#   OBS_PROGRESS_SOURCE OBS_PROGRESS_MISMATCH OBS_PROGRESS_NAMED
#   OBS_CLAIMS OBS_CLAIMS_SOURCE OBS_CLAIMS_NAMED
#   OBS_CADENCE         the declared cadence, as prose, or empty
#   OBS_CADENCE_S       that cadence in seconds, or the default
#   OBS_CADENCE_SOURCE  `roster` | `default`
#   OBS_CLASS           `delivered` | `alive` | `idle`
#   OBS_CLASSIFICATION  `ours`, and how — the display classification the verb prints
#   OBS_TYPE OBS_MODEL OBS_DESC   display metadata, `—` when unreadable
#   OBS_NOW             the epoch every age above was computed against
observe_agent() {  # <typed-target> [deliverable …]
  local target="$1"; shift
  local target_base typed_row aid dp d dsize dmtime pabs

  OBS_OK=0; OBS_FAIL=""; OBS_ROW=""; OBS_NAME=""; OBS_ID=""; OBS_ADOPTED_FROM=""
  OBS_SESSION=""; OBS_LOG=""; OBS_LOG_MTIME=0; OBS_LOG_SIZE=0; OBS_LOG_AGE=0
  OBS_DELIVERABLES=""; OBS_DELIV_PATHS=""; OBS_DELIV_STATE="none"; OBS_DELIV_SOURCE="none"
  OBS_DELIV_MISMATCH=""; OBS_PROGRESS=""; OBS_PROGRESS_ABS=""; OBS_PROGRESS_STATE="unnamed"
  OBS_PROGRESS_MTIME=0; OBS_PROGRESS_AGE=0; OBS_PROGRESS_SOURCE="none"
  OBS_PROGRESS_MISMATCH=""; OBS_PROGRESS_NAMED=0; OBS_CLAIMS=""; OBS_CLAIMS_SOURCE="none"
  OBS_CLAIMS_NAMED=0; OBS_CADENCE=""; OBS_CADENCE_S="$OBSERVE_CADENCE_DEFAULT_S"
  OBS_CADENCE_SOURCE="default"; OBS_CLASS="idle"; OBS_CLASSIFICATION="ours"
  OBS_OURS_BECAUSE=""; OBS_TYPE="—"; OBS_MODEL="—"; OBS_DESC="—"
  OBS_TYPED="$target"
  OBS_NOW=$(date -u +%s)

  [ -n "${OBSERVE_ROSTER:-}" ] || OBSERVE_ROSTER="$OBSERVE_ROOT/.bionic/tmp/roster-${OBSERVE_SESSION}.state"

  # A typed reference is a NAME, an agent id, or `name@team` — all three are legal TaskStop
  # inputs and none of them is resolved for us. Comparison is LITERAL: a target string is
  # never treated as a pattern.
  target_base="${target%@*}"
  [ -n "$target_base" ] || target_base="$target"

  observe_roster_walk "$target_base"
  # WHICH SPELLING THE CALLER TYPED IS A FACT THE RE-WALK DESTROYS (T32; A-T31.2). The walk
  # clears all three row variables on entry, so once an id has been translated into the name
  # it shares with the row a later re-walk finds, the row the caller actually named is gone —
  # and on an ambiguous roster the name alone cannot pick it back out. An agent id names ONE
  # row by construction and must resolve to that row, never to the last row of its name.
  typed_row=""
  if [ -n "$OBS_ROW_BY_ID" ]; then
    typed_row="$OBS_ROW_BY_ID"
    target_base=$(line_field "$OBS_ROW_BY_ID" name)
    observe_roster_walk "$target_base"
  fi
  OBS_NAME="$target_base"
  OBS_ROW="$OBS_ROW_BY_NAME"
  aid=$(line_field "$OBS_ROW_WITH_ID" agent_id)
  OBS_ADOPTED_FROM=$(line_field "$OBS_ROW" adopted_from)
  if [ -n "$typed_row" ]; then
    OBS_ROW="$typed_row"
    aid=$(line_field "$typed_row" agent_id)
    OBS_ADOPTED_FROM=$(line_field "$typed_row" adopted_from)
  fi
  case "$OBS_ADOPTED_FROM" in *[!A-Za-z0-9-]*) OBS_ADOPTED_FROM="" ;; esac
  OBS_ID="$aid"

  # A working log is filed under an agent's id, and a dispatch records that id on its roster
  # row when the agent starts. Without it there is no evidence tier to be had.
  if [ -z "$OBS_ID" ]; then
    OBS_FAIL="no-id"
    return 1
  fi

  # THE WORKING LOG, RESOLVED BY GLOB (D8; REQ-8), never by chasing `adopted_from` alone.
  # `adopted_from` names the session that LAUNCHED an agent this one took over after a
  # `/clear` — provenance, not a location — and the harness re-files the live copy under
  # whichever session is TALKING TO IT NOW, which after a SECOND `/clear` can be a session
  # this row names nowhere. `agent_log_newest` globs every session directory of this
  # project for the exact id and returns the newest, so the launcher, any intermediate
  # adopter and this session are all equally candidates.
  local proj_dir="${OBSERVE_TRANSCRIPT%/*}" found_log="" found_sid="" session_dir
  found_log="$(agent_log_newest "$OBS_ID" "$proj_dir")" || found_log=""
  if [ -n "$found_log" ]; then
    found_sid="$(basename "$(dirname "$(dirname "$found_log")")")"
    OBS_LOG="$found_log"
    OBS_META="${found_log%.jsonl}.meta.json"
    OBS_SESSION="$found_sid"
  else
    # NOTHING WRITTEN YET — name where the log WILL land rather than nothing: the
    # launcher's directory when adopted, this session's otherwise (the pre-glob default).
    session_dir="${OBSERVE_TRANSCRIPT%.jsonl}"
    [ -n "$OBS_ADOPTED_FROM" ] && session_dir="${proj_dir}/$OBS_ADOPTED_FROM"
    OBS_LOG="$session_dir/subagents/agent-${OBS_ID}.jsonl"
    OBS_META="$session_dir/subagents/agent-${OBS_ID}.meta.json"
    OBS_SESSION="${OBS_ADOPTED_FROM:-$OBSERVE_SESSION}"
  fi

  OBS_OURS_BECAUSE="the harness reports it as a teammate of this session (roster-${OBSERVE_SESSION}.state carries its row)"
  if [ -n "$OBS_ADOPTED_FROM" ]; then
    OBS_OURS_BECAUSE="this session ADOPTED it (adopted_from=${OBS_ADOPTED_FROM}); the harness reports it as a teammate, and its working log was found under session ${OBS_SESSION}"
  fi

  # THE TYPE IS DISPLAY ONLY, and it is read only where the live-set reader is loaded. The
  # stop gate deliberately does not source `agents.sh` — a library a file does not read is a
  # library it must not load — and the type appears in no decision here and on no machine
  # line, so its absence costs a display dash and nothing else.
  if type -t live_agents >/dev/null 2>&1 && [ -n "${OBSERVE_TRANSCRIPT:-}" ]; then
    OBS_TYPE=$(live_agents "$OBSERVE_TRANSCRIPT" 2>/dev/null \
      | awk -F'|' -v n="$OBS_NAME" '$1==n {print $2; exit}')
    [ -n "$OBS_TYPE" ] || OBS_TYPE="—"
  fi
  OBS_MODEL=$(jq -r '.model // "—"' "$OBS_META" 2>/dev/null)
  [ -n "$OBS_MODEL" ] || OBS_MODEL="—"
  OBS_DESC=$(jq -r '.description // "—"' "$OBS_META" 2>/dev/null)
  [ -n "$OBS_DESC" ] || OBS_DESC="—"

  # ---------- the contract: roster-sourced, an explicit argument always overriding ----------
  local r_deliv r_prog r_claims r_cad joined
  r_deliv=""; r_prog=""; r_claims=""; r_cad=""
  if [ -n "$OBS_ROW" ]; then
    r_deliv=$(line_field "$OBS_ROW" deliverable)
    r_prog=$(line_field "$OBS_ROW" progress)
    r_claims=$(line_field "$OBS_ROW" claims)
    r_cad=$(line_field "$OBS_ROW" cadence)
  fi

  if [ "$#" -gt 0 ]; then
    OBS_DELIV_SOURCE="args"
    joined=$(IFS=,; echo "$*")
    if [ -n "$r_deliv" ] && [ "$joined" != "$r_deliv" ]; then OBS_DELIV_MISMATCH="$r_deliv"; fi
  elif [ -n "$r_deliv" ]; then
    OBS_DELIV_SOURCE="roster"
    # PATHNAME EXPANSION OFF for exactly this split. Setting IFS suppresses word splitting
    # and says nothing about globbing, so a roster value of `docs/*.md` expanded against
    # whatever sat in the observer's cwd, and files nobody contracted for were reported
    # PRESENT (Step-6 review C-1/S-3).
    local oldifs="$IFS"; IFS=','; set -f; set -- $r_deliv; set +f; IFS="$oldifs"
  fi

  if [ -n "${OBSERVE_PROGRESS_ARG:-}" ]; then
    OBS_PROGRESS="$OBSERVE_PROGRESS_ARG"; OBS_PROGRESS_NAMED=1; OBS_PROGRESS_SOURCE="args"
    if [ -n "$r_prog" ] && [ "$OBS_PROGRESS" != "$r_prog" ]; then OBS_PROGRESS_MISMATCH="$r_prog"; fi
  elif [ -n "$r_prog" ]; then
    OBS_PROGRESS="$r_prog"; OBS_PROGRESS_NAMED=1; OBS_PROGRESS_SOURCE="roster"
  fi

  if [ -n "${OBSERVE_CLAIMS_ARG:-}" ]; then
    OBS_CLAIMS="$OBSERVE_CLAIMS_ARG"; OBS_CLAIMS_NAMED=1; OBS_CLAIMS_SOURCE="args"
  elif [ -n "$r_claims" ]; then
    OBS_CLAIMS="$r_claims"; OBS_CLAIMS_NAMED=1; OBS_CLAIMS_SOURCE="roster"
  fi

  # THE DECLARED CADENCE, the one number that makes an age readable. "Too quiet" means
  # quieter than the author's own declaration; an unreadable declaration falls back to the
  # default rather than being guessed at.
  if [ -n "$r_cad" ]; then
    OBS_CADENCE="$r_cad"
    local cad_s
    cad_s=$(parse_seconds "$r_cad") && [ -n "$cad_s" ] && {
      OBS_CADENCE_S="$cad_s"; OBS_CADENCE_SOURCE="roster"
    }
  fi

  # ---------- evidence 1: the working log (unfakeable — written by working) ----------
  if [ -f "$OBS_LOG" ]; then
    OBS_LOG_MTIME=$(file_mtime "$OBS_LOG")
    OBS_LOG_SIZE=$(file_size "$OBS_LOG")
    OBS_LOG_AGE=$((OBS_NOW - OBS_LOG_MTIME))
    [ "$OBS_LOG_AGE" -lt 0 ] && OBS_LOG_AGE=0
  fi

  # ---------- evidence 2: the contracted deliverables (meaning from the contract) ----------
  #
  # STAT THE RESOLVED PATH, REPORT THE CONTRACTED ONE, so the roster, the brief and every
  # rendering name the artifact the same way.
  #
  # AN EMPTY FILE IS NOT A DELIVERY. A zero-byte artifact is reported `empty` and leaves the
  # contract PENDING: the consumer of this classification refuses a stop of a live agent, and
  # an artifact opened but not written is exactly the state a stop would destroy.
  local pending=0 seen=0
  if [ "$#" -gt 0 ]; then
    for d in "$@"; do
      seen=$((seen + 1))
      dp="$(observe_abs_path "$d")"
      OBS_DELIV_PATHS="${OBS_DELIV_PATHS:+$OBS_DELIV_PATHS,}$d"
      if [ -f "$dp" ]; then
        dsize=$(file_size "$dp"); dmtime=$(file_mtime "$dp")
        if [ "$dsize" -eq 0 ]; then
          OBS_DELIVERABLES="${OBS_DELIVERABLES:+$OBS_DELIVERABLES,}empty:$(observe_mline_value "$d")"
          pending=$((pending + 1))
        else
          OBS_DELIVERABLES="${OBS_DELIVERABLES:+$OBS_DELIVERABLES,}present:$(observe_mline_value "$d")"
        fi
        OBS_DELIV_LAST_SIZE="$dsize"; OBS_DELIV_LAST_MTIME="$dmtime"
      elif [ -d "$dp" ]; then
        OBS_DELIVERABLES="${OBS_DELIVERABLES:+$OBS_DELIVERABLES,}dir:$(observe_mline_value "$d")"
      else
        OBS_DELIVERABLES="${OBS_DELIVERABLES:+$OBS_DELIVERABLES,}absent:$(observe_mline_value "$d")"
        pending=$((pending + 1))
      fi
    done
  fi
  if [ "$seen" -eq 0 ]; then
    OBS_DELIV_STATE="none"
  elif [ "$pending" -eq 0 ]; then
    OBS_DELIV_STATE="delivered"
  else
    OBS_DELIV_STATE="pending"
  fi

  # ---------- evidence 3: the progress artifact (the SECOND activity channel) ----------
  #
  # An hour-long command silences the working log for its whole hour: one tool call, one
  # result at the end. "No activity for 47 minutes" therefore describes a healthy suite and a
  # wedged one identically, and the separation lives one level down, in the work's own
  # byproducts. `unnamed` distinguishes "the contract named no artifact" from "it named one
  # and the artifact is missing" — the distinction a blank value would erase.
  if [ "$OBS_PROGRESS_NAMED" -eq 1 ]; then
    pabs="$(observe_abs_path "$OBS_PROGRESS")"
    OBS_PROGRESS_ABS="$pabs"
    if [ -e "$pabs" ]; then
      OBS_PROGRESS_STATE="present"
      OBS_PROGRESS_MTIME=$(file_mtime "$pabs")
      OBS_PROGRESS_AGE=$((OBS_NOW - OBS_PROGRESS_MTIME))
      [ "$OBS_PROGRESS_AGE" -lt 0 ] && OBS_PROGRESS_AGE=0
    else
      OBS_PROGRESS_STATE="absent"
    fi
  fi

  observe_class >/dev/null
  OBS_OK=1
  return 0
}

# ---------- the classification ----------
#
# THREE STATES, and the precedence between them is the whole of what a stop gate needs:
#
#   delivered  every contracted deliverable is on disk with something in it. Whatever the
#              agent is doing now, the artifact this dispatch exists for is there.
#   alive      the working log or the contracted progress artifact moved within the row's
#              declared cadence. Work is in flight.
#   idle       neither channel has moved inside the cadence and nothing was delivered.
#
# `delivered` OUTRANKS `alive` on purpose: the question a stop asks is "would this destroy
# work nobody has", and an artifact on disk answers it better than activity does — it cannot
# go stale and nobody has to remember to look. That is the same rule the landing contract
# already applies one screen earlier (epic-16 wave-02 R2); this is it applied to a contract
# the landing verdict has not called MET.
#
# CADENCE IS A WINDOW, NOT A TIMER ON EVIDENCE. D-1's refusal to put a clock on an
# observation stands: nothing here ages a LOOK. What is measured is the SUBJECT — how long
# ago it last wrote — against the number its own dispatch declared.
observe_class() {
  OBS_CLASS="idle"
  if [ "${OBS_DELIV_STATE:-none}" = "delivered" ]; then
    OBS_CLASS="delivered"
  elif [ "${OBS_LOG_MTIME:-0}" -gt 0 ] && [ "${OBS_LOG_AGE:-0}" -le "${OBS_CADENCE_S:-900}" ]; then
    OBS_CLASS="alive"
  elif [ "${OBS_PROGRESS_STATE:-unnamed}" = "present" ] \
    && [ "${OBS_PROGRESS_AGE:-0}" -le "${OBS_CADENCE_S:-900}" ]; then
    OBS_CLASS="alive"
  fi
  printf '%s\n' "$OBS_CLASS"
  return 0
}

# ---------- the machine line ----------
#
# The one line any machine reads, printed on the success path and nowhere else. It carries
# the RESOLVED identity and the file facts THIS look computed, so a reader never re-resolves
# anything — one resolver decides who was looked at, which is what makes the operator's view
# and any downstream reading the same fact rather than two computations that must be kept in
# agreement (the F-1 divergence class).
observe_machine_line() {
  printf '%s|target=%s|typed=%s|log=%s|mtime=%s|size=%s|deliverables=%s|progress=%s|progress_mtime=%s|progress_state=%s|classification=%s|deliverable_source=%s|progress_source=%s\n' \
    "$OBSERVE_MACHINE_SCHEMA" \
    "$(observe_mline_value "$OBS_ID")" \
    "$(observe_mline_value "$OBS_TYPED")" \
    "$(observe_mline_value "$OBS_LOG")" \
    "$OBS_LOG_MTIME" \
    "$OBS_LOG_SIZE" \
    "$OBS_DELIVERABLES" \
    "$(observe_mline_value "$OBS_PROGRESS")" \
    "$OBS_PROGRESS_MTIME" \
    "$OBS_PROGRESS_STATE" \
    "$(observe_mline_value "$OBS_CLASSIFICATION")" \
    "$(observe_mline_value "$OBS_DELIV_SOURCE")" \
    "$(observe_mline_value "$OBS_PROGRESS_SOURCE")"
}

# ---------- the look, in one line ----------
#
# WHAT A REFUSAL OWES ITS READER, and what a permitted stop gets too: the four facts the
# classification was made of. A wall that asserts only what it observes has to be able to say
# what it observed (ADR-028), and a reader who disagrees with the verdict needs the evidence
# rather than the conclusion.
observe_look_line() {
  local log_age="(no working log on disk yet)" prog deliv
  [ "${OBS_LOG_MTIME:-0}" -gt 0 ] && log_age="age $(fmt_age "${OBS_LOG_AGE:-0}")"
  prog="${OBS_PROGRESS_STATE:-unnamed}"
  [ "$prog" = "present" ] && prog="present, age $(fmt_age "${OBS_PROGRESS_AGE:-0}")"
  case "${OBS_DELIV_STATE:-none}" in
    none) deliv="deliverable: (none contracted)" ;;
    *)    deliv="deliverable ${OBS_DELIV_STATE}: ${OBS_DELIV_PATHS}" ;;
  esac
  printf 'log %s (%s) · progress %s%s · %s · cadence %ss (%s)\n' \
    "${OBS_LOG}" "$log_age" \
    "$prog" \
    "${OBS_PROGRESS:+ ${OBS_PROGRESS}}" \
    "$deliv" \
    "${OBS_CADENCE_S:-900}" "${OBS_CADENCE_SOURCE:-default}"
}
