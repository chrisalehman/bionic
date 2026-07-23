#!/bin/bash
# sdlc-poker — the dead-man relay driver (slice 4/1: core).
#
# An out-of-band, deliberately-dumb script run by a marker-tagged crontab entry
# every 3 minutes under a standing service identity (~/.claude/cron.env). It
# reads explicitly-registered armed goals (consent registry), classifies each
# from plan state + the live session registry + transcript quiet, writes a
# derived status file, and logs every observable event. Its verbs are classify,
# poke, notify, record — never kill, never approve, never enumerate.
#
# This slice implements C1 (registration), C2 (P3 registry-primary
# classification incl. the degrade path and quiet-never-dead), and C8 (run
# discipline: mkdir lock with stale reclaim, audit log, derived status files,
# per-goal state cache). The poke and notify ACTIONS are no-op stubs here
# (do_poke / do_notify) — slice 4/2 wires them.
#
# All state lives under $HOME/.claude (the fixture suite re-points $HOME):
#   sdlc-goals/<goal-id>            consent-registry records (C1)
#   sdlc-status/<goal-id>.md        derived, always-rebuildable status (C8)
#   sdlc-status/.state/<goal-id>    per-goal classification cache (dedupe, 4/2)
#   sdlc-poker-audit.log            one line per observable event (C8)
#   sdlc-poker.lock/                mkdir single-instance lock + pid file (C8)
#
# Discipline (hooks-rules.md, spec C8): set -u with unconditionally-bound vars;
# CR normalization by TRANSLATION (awk sub+gsub), never `tr -d '\r'`; BSD-awk
# portable (no newlines in -v); `$?`-capture, never ${PIPESTATUS[0]}. NO
# kill/pkill/killall anywhere — liveness is read with `ps -p`. Every
# non-catastrophic path exits 0; diagnostics go to stderr; no color.

set -u

# Sourced env / thresholds (spec C2/C4). Overridable so the fixture suite and
# future tuning can rebind them without editing the script.
QUIET_THRESHOLD="${QUIET_THRESHOLD:-180}"   # idle quiet → IDLE_STALLED (seconds)
WEDGE_QUIET="${WEDGE_QUIET:-540}"           # busy quiet → WEDGED (3× threshold)
POKE_CAP="${POKE_CAP:-3}"                    # max pokes per stall episode (4/2)
POKE_TIMEOUT="${POKE_TIMEOUT:-900}"          # per-poke wall-clock cap, seconds (C4 amendment B)

# Absolute claude binary for the POKE (C4: alias not inherited). The registry
# READ uses PATH-resolved bare `claude` (AS-7a); only the poke is pinned. Kept
# overridable exactly as the thresholds are, so the fixture suite points it at a
# stub — the default literal is the fixture-asserted contract value.
POKE_CLAUDE_BIN="${POKE_CLAUDE_BIN:-/opt/homebrew/bin/claude}"

# Fixed poke prompt (C4, fixture-asserted): resume-and-continue with the gate
# escape hatch, carrying NO approval vocabulary (banned-token list, C4). Single-
# quoted so the backticked markers stay literal (no command substitution).
POKE_PROMPT='continue per the plan'"'"'s `## SDLC State`; if blocked on a decision, write a `## Wake Note` and stop'

# Fixed re-prompt preamble (D-C3, 4/4): the ladder's rung-2 resume carries an
# EXPLICIT directive = this project-silent preamble + the baton's `next-action`
# value verbatim (appended by the dispatcher). Same transport/timeout as the
# generic poke; carries NO approval vocabulary (banned-token list, C4). Single-
# quoted so the backticked markers stay literal.
REPROMPT_PREAMBLE='resume per the plan'"'"'s `## SDLC State` and carry out the recorded next action; if blocked on a decision, write a `## Wake Note` and stop. Next action:'

# Registration globals — bound unconditionally so set -u never trips on a path
# that reads them before load_registration runs (hooks-rules.md).
REG_PLAN=""; REG_CWD=""; REG_SESSION_ID=""; REG_PID=""; REG_ARMED_AT=""

# Transcript memo (D-C8 e09 fold): resolve_transcript's glob scan is resolved
# ONCE per goal per poll and reused by every consumer (transcript_quiet,
# transcript_grammar, write_status, transcript_mtime_key). Keyed on
# REG_SESSION_ID — load_registration always sets it non-empty before any
# consumer runs, so a differing (or still-empty) key is always a genuine
# cache miss; a goal-to-goal transition inside process_goals's loop changes
# REG_SESSION_ID and so naturally invalidates the prior goal's entry.
# _XSCRIPT_SCANS counts actual (non-memoized) scans — test-observable only,
# read nowhere in production logic.
_XSCRIPT_SID=""; _XSCRIPT_PATH=""; _XSCRIPT_SCANS=0

# ---------- first poker↔lib integration (D-C9, slice 4/4) ----------
# The poker sources sdlc-state-lib.sh — the durable-state substrate the revival
# ladder derives from (baton_parse, sdlc_ladder_next, sdlc_effect_run, the rung
# key grammar). Path resolved relative to THIS file (${BASH_SOURCE[0]}), so it
# works whether the poker is run as a child or sourced by the fixture suite; the
# override seam SDLC_STATE_LIB lets a suite point it elsewhere (or at a bad path,
# to prove the degrade). The poker keeps `set -u`; the lib is written WITHOUT it
# and its `${x:-}` guards are the net (D-C9). A sourcing failure is fail-closed:
# SDLC_LIB_OK stays 0, every goal takes the baton-less legacy path, the poll
# never dies (main audits the degrade once).
SDLC_STATE_LIB="${SDLC_STATE_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/sdlc-state-lib.sh}"
SDLC_LIB_OK=0
if [ -f "$SDLC_STATE_LIB" ] && . "$SDLC_STATE_LIB" 2>/dev/null; then
  SDLC_LIB_OK=1
fi

# ---------- path helpers (read $HOME at call time) ----------
goals_dir()   { printf '%s/.claude/sdlc-goals' "$HOME"; }
status_dir()  { printf '%s/.claude/sdlc-status' "$HOME"; }
state_dir()   { printf '%s/.claude/sdlc-status/.state' "$HOME"; }
audit_log()   { printf '%s/.claude/sdlc-poker-audit.log' "$HOME"; }
lock_dir()    { printf '%s/.claude/sdlc-poker.lock' "$HOME"; }

# Portable mtime (epoch seconds): BSD stat first, GNU stat fallback.
file_mtime() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null; }
iso_now()    { date -u +%Y-%m-%dT%H:%M:%SZ; }
iso_of_mtime() {
  local m; m=$(file_mtime "$1" 2>/dev/null) || m=""
  [ -n "$m" ] || { echo "unknown"; return; }
  date -u -r "$m" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || date -u -d "@$m" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || echo "unknown"
}

# ---------- C1: consent-registry reading ----------
# Value of KEY=VALUE from a registration file (CR-tolerant).
reg_val() {  # $1=file $2=key
  grep -E "^$2=" "$1" 2>/dev/null | head -1 | sed -E "s/^$2=//" \
    | awk '{ sub(/\r$/, ""); print }'
}

# Load a goal's registration into REG_* globals. Returns 1 if the record is
# missing or lacks any required key (the caller treats that as MALFORMED-RECORD).
load_registration() {  # $1=goal-id
  local f; f="$(goals_dir)/$1"
  REG_PLAN=""; REG_CWD=""; REG_SESSION_ID=""; REG_PID=""; REG_ARMED_AT=""
  [ -f "$f" ] || return 1
  REG_PLAN=$(reg_val "$f" PLAN)
  REG_CWD=$(reg_val "$f" CWD)
  REG_SESSION_ID=$(reg_val "$f" SESSION_ID)
  REG_PID=$(reg_val "$f" PID)
  REG_ARMED_AT=$(reg_val "$f" ARMED_AT)
  [ -n "$REG_PLAN" ] && [ -n "$REG_CWD" ] && [ -n "$REG_SESSION_ID" ] \
    && [ -n "$REG_PID" ] && [ -n "$REG_ARMED_AT" ]
}

# CR-normalized frontmatter value (translate \r, never delete — hooks-rules.md).
normalize_nl() { awk '{ sub(/\r$/, ""); gsub(/\r/, "\n"); print }' "$1"; }

plan_frontmatter() {  # $1=plan $2=key
  normalize_nl "$1" | awk 'NR==1 && $0=="---"{f=1; next} f && $0=="---"{exit} f' \
    | grep -E "^[[:space:]]*$2[[:space:]]*:" | head -1 \
    | sed -E "s/^[[:space:]]*$2[[:space:]]*:[[:space:]]*//" \
    | sed -E 's/[[:space:]]+$//' | sed -E "s/^['\"]//;s/['\"]\$//"
}

# `current:` from the plan's ## SDLC State (fence-aware: a fenced example must
# not shadow the real section — same idiom as the evidence-gate hook).
plan_current() {  # $1=plan
  normalize_nl "$1" | awk '
    /^[[:space:]]*```/ { fence = !fence; next }
    fence { next }
    /^## SDLC State/ { s=1; next }
    /^## / { s=0 }
    s && /^[[:space:]]*current[[:space:]]*:/ {
      sub(/^[[:space:]]*current[[:space:]]*:[[:space:]]*/, ""); gsub(/[[:space:]]/, ""); print; exit
    }'
}

# ## Wake Note section present? (fence-aware; returns 0 if present)
plan_has_wake_note() {  # $1=plan
  normalize_nl "$1" | awk '
    /^[[:space:]]*```/ { fence = !fence; next }
    fence { next }
    /^## Wake Note/ { found=1 }
    END { exit(found ? 0 : 1) }'
}

# Armed = registration well-formed (checked by the caller before this call —
# unreadable plan is MALFORMED, not merely unarmed) AND
# sdlc_keepalive_effective(REG_PLAN) = true. keepalive:false / fallback-false
# (Global Constraints fallback table: explicit flag wins; absent-flag
# continuous → true; absent-flag task/wave/epic → false) is an AUDITED skip
# (SKIP-UNARMED), replacing the old silent `continue`. The resolver's rc 1
# (unreadable plan — should not occur post-caller-check, but fail-loud rather
# than assume) and rc 2 (off-enum keepalive value) both land on the existing
# MALFORMED-RECORD audit path — never guess past a malformed flag.
is_armed() {  # $1=gid; uses REG_PLAN
  local gid="$1" ka karc
  if [ "$SDLC_LIB_OK" != "1" ]; then
    # Lib unavailable (already audited once via LADDER-DEGRADE, gid "-") —
    # sdlc_keepalive_effective is undefined in this branch, so fall back to
    # the pre-S2 scale-only check, byte-identical to the old is_armed_scale.
    [ "$(plan_frontmatter "$REG_PLAN" scale)" = "continuous" ]
    return $?
  fi
  ka="$(sdlc_keepalive_effective "$REG_PLAN")"; karc=$?
  if [ "$karc" -ne 0 ]; then
    audit_line "$gid" MALFORMED-RECORD "keepalive resolution failed (rc=$karc) for $REG_PLAN"
    return 1
  fi
  [ "$ka" = "true" ] && return 0
  audit_line "$gid" SKIP-UNARMED "keepalive effective=false"
  return 1
}

# ---------- transcript signals ----------
# Newest transcript for the registered session, located by SESSION-ID GLOB across
# every Claude Code project dir — $HOME/.claude/projects/*/<sid>.jsonl (C2
# amendment, Step-6 critic). Session ids are unique, so by-id glob is the A11
# principle applied to the filesystem and is immune to project-dir sanitizer
# drift: the shipped cwd→dir transform replicated only [/.] while Claude Code
# sanitizes [^a-zA-Z0-9] plus a length-cap/hash, so ANY underscore-bearing cwd
# silently broke resolution → stall/wedge detection defeated. Nullglob-safe via
# the -f guard (an unmatched glob word is skipped); >1 match is impossible for a
# uuid but the newest is taken defensively. Echoes a path or nothing.
# Populates the _XSCRIPT_PATH memo (global) for the current REG_SESSION_ID.
# Called DIRECTLY (never via `$(...)`) by every internal consumer below — a
# command-substitution call forks a subshell, and a subshell's variable writes
# never reach the parent, so the memo would silently never stick. Callers read
# $_XSCRIPT_PATH themselves right after calling this.
_resolve_transcript_memo() {
  if [ "$_XSCRIPT_SID" = "$REG_SESSION_ID" ]; then return; fi
  local t best="" bestm="" m
  for t in "$HOME"/.claude/projects/*/"$REG_SESSION_ID".jsonl; do
    [ -f "$t" ] || continue
    m=$(file_mtime "$t" 2>/dev/null) || m=0
    [ -n "$m" ] || m=0
    if [ -z "$best" ] || [ "$m" -gt "$bestm" ]; then best="$t"; bestm="$m"; fi
  done
  _XSCRIPT_SID="$REG_SESSION_ID"; _XSCRIPT_PATH="$best"
  _XSCRIPT_SCANS=$((_XSCRIPT_SCANS + 1))
}

# Public wrapper — unchanged external contract (echoes a path or nothing).
# Safe to call via `$(resolve_transcript)`; internal consumers call
# _resolve_transcript_memo directly instead, so the memo survives across sites.
resolve_transcript() {  # uses REG_SESSION_ID; memoized (D-C8 e09 fold)
  _resolve_transcript_memo
  [ -n "$_XSCRIPT_PATH" ] && printf '%s' "$_XSCRIPT_PATH"
}

# Transcript quiet in seconds (now - mtime). No transcript → 0 (recently-active
# assumption: mtime is a suspect flag only and must never manufacture a stall).
transcript_quiet() {
  local mt now
  _resolve_transcript_memo
  [ -n "$_XSCRIPT_PATH" ] || { echo 0; return; }
  mt=$(file_mtime "$_XSCRIPT_PATH" 2>/dev/null) || mt=""
  [ -n "$mt" ] || { echo 0; return; }
  now=$(date +%s)
  echo $(( now - mt ))
}

# Last-event grammar (degrade fallback): dangling tool_use → busy;
# last-prompt (user) marker → idle; otherwise unknown.
transcript_grammar() {
  local last
  _resolve_transcript_memo
  [ -n "$_XSCRIPT_PATH" ] || { echo unknown; return; }
  last=$(tail -n 1 "$_XSCRIPT_PATH" 2>/dev/null)
  if printf '%s' "$last" | grep -q '"tool_use"' \
     && ! printf '%s' "$last" | grep -q '"tool_result"'; then
    echo busy
  elif printf '%s' "$last" | grep -qE '"type"[[:space:]]*:[[:space:]]*"user"'; then
    echo idle
  else
    echo unknown
  fi
}

# ---------- C2: classification (P3 verbatim, registry-primary) ----------
# Given a live BUSY/IDLE/NOSTATUS reading, fold in transcript quiet.
busy_or_wedged() { [ "$(transcript_quiet)" -gt "$WEDGE_QUIET" ] && echo WEDGED || echo BUSY; }
idle_or_stalled() { [ "$(transcript_quiet)" -gt "$QUIET_THRESHOLD" ] && echo IDLE_STALLED || echo IDLE; }

# Degrade path (registry unavailable/unparseable): ps -p $PID (alive/dead only)
# → transcript last-event grammar → mtime as suspect flag. Total signal loss
# echoes "" (caller audits + silently skips; the poker itself never wedges).
degrade_classify() {  # $1=goal-id (for future audit context)
  if ! ps -p "$REG_PID" >/dev/null 2>&1; then echo DEAD; return; fi
  case "$(transcript_grammar)" in
    busy) busy_or_wedged ;;
    idle) idle_or_stalled ;;
    *)    echo "" ;;
  esac
}

# classify_goal <goal-id> [registry-json registry-rc] → one of
# COMPLETE|GATED|DEAD|IDLE_STALLED|IDLE|BUSY|WEDGED (or "" on total-signal-loss
# degrade). Loads the registration itself so it is callable directly on a
# planted goal. Plan state first, session liveness second.
#
# registry-json/registry-rc (D-C8 e09 fold, SDLC_REGISTRY_CMD seam): when the
# caller passes both (process_goals's once-per-poll fetch), classify_goal uses
# them as-is and never shells out itself. Called with just the goal-id (the
# direct-call convention every existing fixture case uses), it self-fetches via
# `${SDLC_REGISTRY_CMD:-claude agents --json}` exactly as before — no observable
# behavior change on that path, just the same seam process_goals now uses.
classify_goal() {  # $1=goal-id $2=registry-json (optional) $3=registry-rc (optional, paired with $2)
  local gid="$1"
  load_registration "$gid" || { echo ""; return; }

  # 1. PLAN state (charter close / gate take precedence over liveness).
  [ "$(plan_current "$REG_PLAN")" = "10" ] && { echo COMPLETE; return; }
  plan_has_wake_note "$REG_PLAN" && { echo GATED; return; }

  # 2. SESSION liveness — registry JSON by SESSION_ID only (never enumeration).
  # Registry unavailable/unparseable → degrade.
  local json rc present status
  if [ "$#" -ge 3 ]; then
    json="$2"; rc="$3"
  else
    json=$(${SDLC_REGISTRY_CMD:-claude agents --json} 2>/dev/null); rc=$?
  fi
  if [ "$rc" -ne 0 ] || ! command -v jq >/dev/null 2>&1; then
    audit_line "$gid" DEGRADE "registry unavailable (rc=$rc); ps/grammar fallback"
    degrade_classify "$gid"; return
  fi
  present=$(printf '%s' "$json" | jq -r --arg sid "$REG_SESSION_ID" 'any(.[]; .sessionId==$sid)' 2>/dev/null)
  case "$present" in
    true)  : ;;
    false) echo DEAD; return ;;   # absent from registry → DEAD (P3)
    *)     audit_line "$gid" DEGRADE "registry parse failed; ps/grammar fallback"
           degrade_classify "$gid"; return ;;
  esac
  status=$(printf '%s' "$json" | jq -r --arg sid "$REG_SESSION_ID" \
    '[.[] | select(.sessionId==$sid)][0] | .status // "NOSTATUS"' 2>/dev/null)
  case "$status" in
    busy) busy_or_wedged ;;                       # 3. BUSY + quiet>WEDGE → WEDGED
    idle) idle_or_stalled ;;                      # IDLE vs IDLE_STALLED
    *)    busy_or_wedged ;;                       # NOSTATUS print-child → alive-working (treat as BUSY)
  esac
}

# ---------- C8: run discipline ----------
audit_line() {  # $1=goal-id $2=event $3=detail
  local log; log="$(audit_log)"
  mkdir -p "$(dirname "$log")" 2>/dev/null
  printf '%s %s %s %s\n' "$(iso_now)" "$1" "$2" "${3:-}" >> "$log" 2>/dev/null
}

# Derived-status word per the C3 action table (the status file is always
# rebuildable, so this is a pure mapping from the classification).
state_word() {  # $1=classification
  case "$1" in
    COMPLETE)                 echo complete ;;
    GATED)                    echo gated ;;
    DEAD|IDLE_STALLED)        echo poked ;;
    IDLE)                     echo idle ;;
    BUSY)                     echo driving ;;
    WEDGED)                   echo wedged ;;
    *)                        echo unknown ;;
  esac
}

# Human recovery command (C3): the ONLY place a signal verb appears as a string
# in this script — never executed, only surfaced in the WEDGE status/notification
# so force stays human. Consolidated to one template so the no-signal-invocation
# fixture can whitelist exactly this line.
recovery_cmd() {  # uses REG_PID, REG_CWD, REG_SESSION_ID
  printf 'kill %s && cd %s && claude --resume %s' "$REG_PID" "$REG_CWD" "$REG_SESSION_ID"
}

# write_status <goal-id> <classification> — derived status file (C8): state,
# plan current, last transcript activity, attach handle, + recovery command on
# WEDGE. No occupancy field (wave-04).
write_status() {  # $1=goal-id $2=classification
  local gid="$1" state="$2" dir iso cur
  dir="$(status_dir)"; mkdir -p "$dir" 2>/dev/null
  cur=$(plan_current "$REG_PLAN"); [ -n "$cur" ] || cur="unknown"
  _resolve_transcript_memo
  if [ -n "$_XSCRIPT_PATH" ]; then iso=$(iso_of_mtime "$_XSCRIPT_PATH"); else iso="unknown"; fi
  {
    echo "# sdlc-poker status: $gid"
    echo "state: $(state_word "$state")"
    echo "plan-current: $cur"
    echo "last-activity: $iso"
    echo "attach: cd $REG_CWD && claude --resume $REG_SESSION_ID"
    if [ "$state" = "WEDGED" ]; then
      echo "recovery: $(recovery_cmd)"
    fi
  } > "$dir/$gid.md" 2>/dev/null
}

# Per-goal classification cache — the transition-dedupe substrate slice 4/2's
# notify path reads.
cache_state() {  # $1=goal-id $2=classification
  local d; d="$(state_dir)"; mkdir -p "$d" 2>/dev/null
  printf '%s\n' "$2" > "$d/$1" 2>/dev/null
}

# Single-instance mkdir lock with a pid file. Held → we own it (return 0);
# a live holder → silent overlap (return 1); a stale holder (pid dead, read
# with ps -p — never `kill`) → reclaim. Cron overlap is normal, not an error.
acquire_lock() {
  local lock opid; lock="$(lock_dir)"
  if mkdir "$lock" 2>/dev/null; then echo $$ > "$lock/pid" 2>/dev/null; return 0; fi
  opid=$(cat "$lock/pid" 2>/dev/null)
  if [ -n "$opid" ] && ps -p "$opid" >/dev/null 2>&1; then
    return 1   # live holder → this run steps aside silently
  fi
  rm -rf "$lock" 2>/dev/null
  if mkdir "$lock" 2>/dev/null; then echo $$ > "$lock/pid" 2>/dev/null; return 0; fi
  return 1
}
release_lock() { rm -rf "$(lock_dir)" 2>/dev/null; }

# ---------- C4: the poke ----------
# Literal (regex-free) redaction of the standing-service secrets from a stderr
# tail before it reaches the audit log (C4 amendment defensive filter). Values
# are matched by exact substring — no ERE — so a token/topic with metacharacters
# can never mis-anchor or leak. Reads the env values at call time.
scrub_secrets() {  # stdin → stdout, secrets replaced with [REDACTED]
  awk -v tok="${CLAUDE_CODE_OAUTH_TOKEN:-}" -v top="${BIONIC_NTFY_TOPIC:-}" '
    function strip(line, s,   out, p) {
      if (s == "") return line
      out = ""
      while ((p = index(line, s)) > 0) {
        out = out substr(line, 1, p - 1) "[REDACTED]"
        line = substr(line, p + length(s))
      }
      return out line
    }
    { print strip(strip($0, tok), top) }'
}

# Resume the stalled session and hand it the fixed prompt via STDIN (a positional
# prompt after flags is swallowed, P1). Absolute binary (alias not inherited),
# cd-first (--resume is cwd/project-scoped, P2), no --model (the resumed turn does
# the goal's real work). Idempotent and leaf-agnostic. Echoes nothing; returns
# the resume exit code (a nonzero poke still counts against the cap). On rc≠0 the
# audit POKE line carries a truncated (~120 chars, single-line), secret-scrubbed
# trailing tail of the poke's COMBINED stdout+stderr (C4 amendment: the live
# failure — "Not logged in · Please run /login" — rides the `-p` result stream on
# STDOUT with stderr empty, so capturing stderr alone would still be blind); on
# rc=0 no tail (nothing to diagnose).
# Secret-scrubbed, single-line, trailing ~120 chars of a captured poke stream (the
# failure reason surfaces at the end); substr guards a short line.
poke_tail() {  # $1=outfile
  scrub_secrets < "$1" | tr '\n\r' '  ' \
    | awk '{ n=length($0); print (n>120 ? substr($0, n-119) : $0) }'
}

do_poke() {  # $1=goal-id [$2=prompt] ; uses REG_CWD, REG_SESSION_ID
  # $2 is the resume prompt; unset → the generic POKE_PROMPT (byte-identical to
  # the legacy one-arg call). The ladder's re-prompt rung (D-C3) passes a
  # baton-derived directive here through this same transport + timeout.
  local gid="$1" prompt="${2:-$POKE_PROMPT}" rc outf tail
  outf=$(mktemp 2>/dev/null) || outf=""
  # The poke runs under a wall-clock cap (C4 amendment B): a hung `claude --resume`
  # would otherwise hold the poker's OWN lock forever — every later poll sees a
  # live holder and exits — so one hung poke stalls the entire relay. There is no
  # `timeout` binary on this host, so `perl -e 'alarm shift; exec @ARGV'` sets a
  # SIGALRM timer that is preserved across the exec into the poke; on expiry the
  # child dies (rc 128+14 = 142). Killing our OWN timed-out child is process
  # hygiene, not the no-force verb (which protects TARGET sessions); the DAG makes
  # a killed poke turn resumable.
  ( cd "$REG_CWD" 2>/dev/null && printf '%s' "$prompt" \
      | perl -e 'alarm shift @ARGV; exec @ARGV' "$POKE_TIMEOUT" \
          "$POKE_CLAUDE_BIN" --resume "$REG_SESSION_ID" -p --dangerously-skip-permissions \
  ) >"${outf:-/dev/null}" 2>&1
  rc=$?
  if [ "$rc" -eq 142 ]; then
    # perl-alarm SIGALRM: the poke exceeded POKE_TIMEOUT. Counts toward the cap;
    # the audit carries the out: tail if the child produced any before the kill.
    if [ -n "$outf" ] && [ -s "$outf" ]; then
      tail=$(poke_tail "$outf")
      audit_line "$gid" POKE-TIMEOUT "resume $REG_SESSION_ID timed out after ${POKE_TIMEOUT}s out: $tail"
    else
      audit_line "$gid" POKE-TIMEOUT "resume $REG_SESSION_ID timed out after ${POKE_TIMEOUT}s"
    fi
  elif [ "$rc" -ne 0 ] && [ -n "$outf" ] && [ -s "$outf" ]; then
    tail=$(poke_tail "$outf")
    audit_line "$gid" POKE "resume $REG_SESSION_ID rc=$rc out: $tail"
  else
    audit_line "$gid" POKE "resume $REG_SESSION_ID rc=$rc"
  fi
  [ -n "$outf" ] && rm -f "$outf" 2>/dev/null
  return "$rc"
}

# ---------- C5: notification transport (ntfy) ----------
# One transition notification. The topic is a secret: it reaches curl only, never
# an audit line or status file (audit records the EVENT, not the topic). curl
# failure → NOTIFY-FAIL audit + nonzero return (the caller leaves the dedupe cache
# un-advanced so the next poll retries — notification retry rides the poll cadence,
# no inner loop). Returns 0 iff the POST succeeded.
do_notify() {  # $1=goal-id $2=event $3=body
  local gid="$1" event="$2" body="$3" topic rc
  topic="${BIONIC_NTFY_TOPIC:-}"
  if [ -z "$topic" ]; then
    audit_line "$gid" NOTIFY-FAIL "$event: no ntfy topic configured"
    return 1
  fi
  curl -fsS -m 10 -H "Title: $gid: $event" -d "$body" "https://ntfy.sh/$topic" >/dev/null 2>&1
  rc=$?
  if [ "$rc" -eq 0 ]; then
    audit_line "$gid" "$event" "notified"
    return 0
  fi
  audit_line "$gid" NOTIFY-FAIL "$event curl rc=$rc"
  return 1
}

# ---------- C4 retry-cap: failure-aware stall episodes ----------
# Per-goal poke-episode state: "<transcript-mtime> <poke-count> <pokefail-sent>
# <last-rc> <state>". Every poke increments the count. The episode resets (count
# + POKE-FAIL flag) only when:
#   - the goal's classification changed since the last poke (goal state change), OR
#   - the transcript moved AND the last poke SUCCEEDED (rc=0) — legitimate progress.
# A transcript move that follows a FAILED poke (rc≠0) is the failure's own turn
# write (e.g. a "Not logged in" reply) and must NEVER reset the episode — else a
# persistently-failing target is poked unboundedly and POKE-FAIL never fires
# (C4 amendment; observed live at 7 pokes/7 min, no cap). Cap exhaustion → a
# single POKE-FAIL notification, then park until the episode legitimately resets.
poke_state_file() { printf '%s/%s.poke' "$(state_dir)" "$1"; }

transcript_mtime_key() {  # uses REG_CWD, REG_SESSION_ID
  _resolve_transcript_memo
  [ -n "$_XSCRIPT_PATH" ] || { printf 'none'; return; }
  file_mtime "$_XSCRIPT_PATH" 2>/dev/null || printf 'none'
}

poke_capped() {  # $1=goal-id $2=classification
  local gid="$1" state="$2" pf mtime smtime scount sfail slastrc sstate
  pf="$(poke_state_file "$gid")"
  mtime=$(transcript_mtime_key)
  smtime=""; scount=0; sfail=0; slastrc=0; sstate=""
  if [ -f "$pf" ]; then
    read -r smtime scount sfail slastrc sstate < "$pf" 2>/dev/null || true
    [ -n "$scount" ]  || scount=0
    [ -n "$sfail" ]   || sfail=0
    [ -n "$slastrc" ] || slastrc=0
  fi
  if [ "$sstate" != "$state" ]; then
    scount=0; sfail=0                                  # goal state change → new episode
  elif [ "$mtime" != "$smtime" ] && [ "$slastrc" = "0" ]; then
    scount=0; sfail=0                                  # progress after a good poke → new episode
  fi                                                    # else: failed-poke move → same episode
  if [ "$scount" -ge "$POKE_CAP" ]; then
    if [ "$sfail" -ne 1 ]; then
      do_notify "$gid" POKE-FAIL "poke cap ($POKE_CAP) exhausted for $gid; parking until state change" \
        && sfail=1
    fi
    printf '%s %s %s %s %s\n' "$mtime" "$scount" "$sfail" "$slastrc" "$state" > "$pf" 2>/dev/null
    return 0
  fi
  do_poke "$gid"; slastrc=$?                            # counts regardless of exit
  scount=$((scount + 1))
  printf '%s %s %s %s %s\n' "$mtime" "$scount" "$sfail" "$slastrc" "$state" > "$pf" 2>/dev/null
}

# ---------- C3: action dispatch (the no-force table) ----------
# Read the previous classification (transition-dedupe substrate).
read_cache() { cat "$(state_dir)/$1" 2>/dev/null || true; }

# Notify only on a state transition, and advance the dedupe cache ONLY when the
# notification is delivered — a failed notify leaves the cache at the prior state
# so the next poll retries (C5).
notify_and_cache() {  # $1=gid $2=event $3=body $4=prev $5=state
  local gid="$1" event="$2" body="$3" prev="$4" state="$5"
  [ "$prev" = "$state" ] && return 0                    # already notified → dedupe
  do_notify "$gid" "$event" "$body" && cache_state "$gid" "$state"
}

# ---------- D-C1/D-C2/D-C3: revival ladder dispatcher (slice 4/4) ----------
# The poker's ledger-clocked revival ladder. For a DEAD/IDLE_STALLED/WEDGED goal
# WITH a parseable baton, the pure oracle sdlc_ladder_next (lib) decides the ONE
# next rung from the goal's ledger + the current transcript-mtime anchor; the
# poker EXECUTES at most that one action this poll, each through sdlc_effect_run
# under the pinned key `rung:<goal-id>:<rung-name>:<anchor>:<n>` (D-C2, minted by
# the lib's single-source _sdlc_rung_key). Rungs 1-3 (poke/re-prompt/observe) are
# this slice; `rollover`/`human` audit LADDER-DEFER and take no action (4/5's
# scope). Fail-closed throughout (D-C9/J1): a malformed baton, a bad anchor, an
# oracle defect, or a corrupt ledger → one audit line + skip of THIS goal; the
# poll continues to the next goal (one bad goal never starves supervision).

# Classifications the ladder governs (baton-bearing). Others keep legacy behavior.
ladder_applicable() {  # $1=classification
  case "$1" in DEAD|IDLE_STALLED|WEDGED) return 0 ;; *) return 1 ;; esac
}

# The rung action is the DISPATCH, not the child's exit: do_poke always audits
# its own resume rc, and a nonzero resume is a completed attempt (heritage: a
# failed poke still counts, C4). Returning 0 lets sdlc_effect_run journal the
# effect line so the attempt is recorded — the crash window (poker death between
# decision and effect) is the ONLY thing that must leave the effect unjournaled.
ladder_poke_child()     { do_poke "$1"; return 0; }        # generic poke prompt
ladder_reprompt_child() { do_poke "$1" "$2"; return 0; }   # baton-directed prompt

# Execute ONE rung's effect under the pinned key (D-C2). Called at most once per
# goal per poll (AS-C5). Journal-before-act via sdlc_effect_run.
ladder_rung_effect() {  # $1=gid $2=anchor $3=token(<rung>:<n>) $4=rung-name
  local gid="$1" anchor="$2" token="$3" rung="$4" n key prompt
  n="${token##*:}"
  key="$(_sdlc_rung_key "$gid" "$rung" "$anchor" "$n" 2>/dev/null)" || {
    audit_line "$gid" LADDER-DEFECT "cannot mint rung key for '$token' (anchor $anchor)"; return 0; }
  case "$rung" in
    poke)
      sdlc_effect_run "$gid" "$key" "ladder poke attempt $n (anchor $anchor)" -- \
        ladder_poke_child "$gid" \
        || audit_line "$gid" LADDER-DEFECT "effect-run failed for $key" ;;
    re-prompt)
      # BATON_NEXT_ACTION was set by ladder_dispatch's own baton_parse (the
      # oracle's parse ran in a subshell and cannot have clobbered it).
      prompt="$REPROMPT_PREAMBLE $BATON_NEXT_ACTION"
      sdlc_effect_run "$gid" "$key" "ladder re-prompt attempt $n (anchor $anchor)" -- \
        ladder_reprompt_child "$gid" "$prompt" \
        || audit_line "$gid" LADDER-DEFECT "effect-run failed for $key" ;;
    observe)
      # Journal-only observation: no child, no side effect. --replay-safe so a
      # crash-window re-drive re-runs the harmless `true` instead of parking.
      sdlc_effect_run "$gid" "$key" "ladder observe attempt $n (anchor $anchor)" --replay-safe -- true \
        || audit_line "$gid" LADDER-DEFECT "effect-run failed for $key" ;;
  esac
  return 0
}

# ---------- D-C4: rollover rung (slice 4/5) ----------
# The rollover rung hands the goal to the spine's refuse-first successor pipeline,
# consumed AS-IS (never reimplemented): sdlc_successor_spawn owns the gated/
# complete/owned/diverged refusals AND the exactly-once `spawn:<gid>:<written-at>`
# key (D-C4). The dir is the goal's REPO from the REGISTRATION (REG_CWD, trusted
# provenance — the git predicates in the spine's reconcile/complete stages run
# there). This poker NEVER re-keys a spawn or parks around the spine.
#
# Outcome map (the spine's contract is stdout+rc, its refuse lines on stderr):
#   rc 0, stdout a fresh sid                 → LADDER-ROLLOVER (a successor launched)
#   rc 0, stdout goal-complete/spawn-skipped → LADDER-ROLLOVER-REFUSED (benign, re-derive)
#   rc≠0, stderr goal-owned/goal-gated       → LADDER-ROLLOVER-REFUSED (a healthy owner /
#                                              an already-standing Wake Note; NO new park)
#   rc≠0, stderr EMPTY                        → LADDER-ROLLOVER-PARK: the spine PARKED GATED
#                                              (reconcile divergence / false-complete /
#                                              crash-window indeterminate) — it already
#                                              appended the Wake Note internally and its
#                                              defect stderr was captured there, so a clean
#                                              refusal surfaces nothing here. Audit + continue.
#   rc≠0, stderr other (park-failed, ...)     → LADDER-DEFECT: the park could not land
#                                              durable state — fail-closed, surfaced loud.
ladder_rollover() {  # $1=gid ; uses REG_CWD
  local gid="$1" errf out rc err
  errf=$(mktemp 2>/dev/null) || errf=""
  out="$(sdlc_successor_spawn "$gid" "$REG_CWD" 2>"${errf:-/dev/null}")"; rc=$?
  err=""; [ -n "$errf" ] && { err="$(cat "$errf" 2>/dev/null)"; rm -f "$errf"; }
  if [ "$rc" -eq 0 ]; then
    case "$out" in
      goal-complete|spawn-skipped*) audit_line "$gid" LADDER-ROLLOVER-REFUSED "spine refused: $out" ;;
      *)                            audit_line "$gid" LADDER-ROLLOVER "successor spawned sid=$out" ;;
    esac
    return 0
  fi
  case "$err" in
    goal-owned*|goal-gated*) audit_line "$gid" LADDER-ROLLOVER-REFUSED "spine refused (no park): $err" ;;
    '')                      audit_line "$gid" LADDER-ROLLOVER-PARK "spine parked GATED (see the plan's ## Wake Note)" ;;
    *)                       audit_line "$gid" LADDER-DEFECT "rollover spawn failed to park durable state (rc=$rc): $err" ;;
  esac
  return 0
}

# ---------- D-C5: terminal human rung (slice 4/5) ----------
# The ladder's terminal rung parks the goal GATED for a human. The plan path comes
# from the REGISTRATION only (REG_PLAN — trusted provenance, D-C5/AS-C11), NEVER
# the baton. sdlc_gate_park's own `park:<gid>:ladder-exhausted` effect key + first-
# park-wins belt make repeated polls idempotent (ONE Wake Note). Notification is
# NOT sent here — it rides the existing GATED-transition ntfy dedupe on the NEXT
# classification pass (the plan now carries a Wake Note → classify GATED), so park
# durability never depends on notify success.
ladder_human() {  # $1=gid $2=anchor $3=classification
  local gid="$1" anchor="$2" cls="$3"
  if sdlc_gate_park "$gid" "$REG_PLAN" ladder-exhausted \
       "revival ladder exhausted for $gid ($cls, episode anchor $anchor); automated rungs spent — human decision required" \
       >/dev/null 2>&1; then
    audit_line "$gid" LADDER-HUMAN "ladder-exhausted park ($cls, anchor $anchor)"
  else
    audit_line "$gid" LADDER-DEFECT "ladder-exhausted park failed to land for $gid ($cls)"
  fi
}

# ---------- D-C6: completion latch (slice 4/5) ----------
# On COMPLETE classification the poker becomes the cron consumer of the spine's
# completion latch. sdlc_complete_check (consumed AS-IS) verifies the terminal
# claim structurally against git reality: rc 0 latches `complete:<gid>` exactly-once
# ITSELF, then the poker fires the existing COMPLETE transition notify; rc 1 is a
# benign in-flight race (audit SKIP-RACE, nothing else — never a park); rc 2 is a
# refuted terminal claim (false-complete / structural defect) → park GATED on the
# REGISTRATION plan (trusted provenance, D-C5), no latch, no ladder. The check runs
# against the goal's REPO from the registration (REG_CWD).
complete_latch() {  # $1=gid $2=prev
  local gid="$1" prev="$2" ccf cc_err rc cls
  ccf=$(mktemp 2>/dev/null) || ccf=""
  sdlc_complete_check "$gid" "$REG_CWD" >/dev/null 2>"${ccf:-/dev/null}"; rc=$?
  cc_err=""; [ -n "$ccf" ] && { cc_err="$(cat "$ccf" 2>/dev/null)"; rm -f "$ccf"; }
  case "$rc" in
    0) notify_and_cache "$gid" COMPLETE "goal $gid complete (charter close / current:10)" "$prev" COMPLETE ;;
    1) audit_line "$gid" SKIP-RACE "completion check benign not-complete: $cc_err" ;;   # nothing else
    2) cls="$(_sdlc_spawn_defect_class "$cc_err")"; [ -n "$cls" ] || cls="false-complete"
       # Park-rc checked (5-axis F1): on a failed park, surface LADDER-DEFECT and
       # do NOT advance the dedupe cache — the next poll retries the park (loud,
       # self-healing) instead of silently re-parking with no defect audit.
       if sdlc_gate_park "$gid" "$REG_PLAN" "$cls" "$cc_err" >/dev/null 2>&1; then
         audit_line "$gid" COMPLETE-FALSE "false-complete parked GATED: $cc_err"
         cache_state "$gid" COMPLETE
       else
         audit_line "$gid" LADDER-DEFECT "false-complete park failed to land for $gid: $cc_err"
       fi ;;
  esac
}

# ladder_dispatch <gid> <classification> — the per-goal ladder step. The caller
# has already confirmed SDLC_LIB_OK, ladder_applicable, and a baton FILE present.
ladder_dispatch() {  # $1=gid $2=classification
  local gid="$1" state="$2" bpath anchor token rc
  bpath="$(baton_path "$gid")"
  # Parse-gate (fail-closed): a baton file that does not parse is a defect, not a
  # baton-less goal — skip the goal, never fall through to a legacy poke.
  if ! baton_parse "$bpath" 2>/dev/null; then
    audit_line "$gid" LADDER-SKIP "malformed baton: $bpath"
    return 0
  fi
  # Anchor = DURABLE-PROGRESS digest (D-C2 amendment, Step-6 critic F1): derived
  # from the goal's durable progress (plan current, branch tip, passenger-class
  # ledger tail, baton written-at) via sdlc_ladder_anchor — NEVER transcript
  # mtime, so a poke's own resume turn cannot reset the episode it is judged by.
  # Provenance is the REGISTRATION plan+cwd (trusted, D-C5). An anchor-derivation
  # defect (unreadable plan/cwd/ledger/baton) → LADDER-SKIP + fail-closed skip of
  # THIS goal; the poll continues to the next.
  local aef aerr arc
  aef=$(mktemp 2>/dev/null) || aef=""
  anchor="$(sdlc_ladder_anchor "$gid" "$REG_PLAN" "$REG_CWD" 2>"${aef:-/dev/null}")"; arc=$?
  aerr=""; [ -n "$aef" ] && { aerr="$(cat "$aef" 2>/dev/null)"; rm -f "$aef"; }
  if [ "$arc" -ne 0 ] || [ -z "$anchor" ]; then
    audit_line "$gid" LADDER-SKIP "durable-progress anchor derivation failed: ${aerr:-<no anchor>}"
    return 0
  fi
  local nef nerr
  nef=$(mktemp 2>/dev/null) || nef=""
  token="$(sdlc_ladder_next "$gid" "$state" "$anchor" 2>"${nef:-/dev/null}")"; rc=$?
  nerr=""; [ -n "$nef" ] && { nerr="$(cat "$nef" 2>/dev/null)"; rm -f "$nef"; }
  if [ "$rc" -ne 0 ]; then
    # Crash-window fail-closed (AC-C5): a journaled rung DECISION with no matching
    # effect is the spine's own `effect-indeterminate` posture — park GATED for a
    # human replay decision (REG_PLAN provenance, D-C5), never re-run the action.
    # Every OTHER oracle defect (corrupt ledger, bad anchor/cap) stays a
    # fail-closed skip + LADDER-DEFECT audit (one bad goal never starves the poll).
    case "$nerr" in
      *effect-indeterminate*)
        # Park-rc checked (5-axis F1): a failed park is surfaced as LADDER-DEFECT,
        # mirroring ladder_human — never a silent re-park with no defect audit.
        if sdlc_gate_park "$gid" "$REG_PLAN" effect-indeterminate "$nerr" >/dev/null 2>&1; then
          audit_line "$gid" LADDER-INDETERMINATE "$nerr"
        else
          audit_line "$gid" LADDER-DEFECT "effect-indeterminate park failed to land for $gid: $nerr"
        fi ;;
      *)
        audit_line "$gid" LADDER-DEFECT "sdlc_ladder_next rc=$rc ($state, anchor $anchor): $nerr" ;;
    esac
    return 0
  fi
  case "$token" in
    poke:*)          ladder_rung_effect "$gid" "$anchor" "$token" poke ;;
    re-prompt:*)     ladder_rung_effect "$gid" "$anchor" "$token" re-prompt ;;
    observe:*)       ladder_rung_effect "$gid" "$anchor" "$token" observe ;;
    rollover)        ladder_rollover "$gid" ;;                     # spine spawn (D-C4)
    human)           ladder_human "$gid" "$anchor" "$state" ;;     # terminal park (D-C5)
    none)            : ;;                                          # no ladder action this poll
    *)               audit_line "$gid" LADDER-DEFECT "unrecognized ladder token '$token'" ;;
  esac
  return 0
}

# Per the C3 table: COMPLETE/GATED/WEDGED notify-on-transition (never poke; gate
# and wedge supremacy); DEAD/IDLE_STALLED poke under the cap; BUSY logs SKIP-BUSY;
# IDLE is left alone. Non-notify states advance the cache directly so a later
# transition INTO a notify state is detected.
#
# 4/4 ladder pre-branch: a baton-bearing DEAD/IDLE_STALLED/WEDGED goal is owned
# by the revival ladder (ledger-clocked rungs), which supersedes the legacy
# poke_capped / WEDGE-notify path for that goal. Goals WITHOUT a baton — and
# every goal when the lib is unavailable — keep the legacy path byte-identical
# (AS-C4 grandfather). GATED/COMPLETE/BUSY/IDLE never ladder.
dispatch_actions() {  # $1=gid $2=state $3=prev
  local gid="$1" state="$2" prev="$3"
  if [ "$SDLC_LIB_OK" = "1" ] && ladder_applicable "$state" && [ -f "$(baton_path "$gid")" ]; then
    ladder_dispatch "$gid" "$state"
    cache_state "$gid" "$state"      # advance the dedupe cache (transition detection)
    return 0
  fi
  # D-C6 completion latch: a baton-bearing COMPLETE goal routes through the spine's
  # structural completion check (latch / benign race / false-complete park) instead
  # of the legacy notify-on-transition. Baton-less COMPLETE goals (and every goal
  # when the lib is unavailable) keep the legacy path below byte-identical.
  if [ "$state" = "COMPLETE" ] && [ "$SDLC_LIB_OK" = "1" ] && [ -f "$(baton_path "$gid")" ]; then
    complete_latch "$gid" "$prev"
    return 0
  fi
  case "$state" in
    COMPLETE)
      notify_and_cache "$gid" COMPLETE "goal $gid complete (charter close / current:10)" "$prev" "$state" ;;
    GATED)
      notify_and_cache "$gid" GATED "goal $gid gated — decision required; see the plan's ## Wake Note" "$prev" "$state" ;;
    WEDGED)
      notify_and_cache "$gid" WEDGE \
        "goal $gid WEDGED: driving but transcript quiet >${WEDGE_QUIET}s. recovery: $(recovery_cmd)" "$prev" "$state" ;;
    DEAD|IDLE_STALLED)
      poke_capped "$gid" "$state"; cache_state "$gid" "$state" ;;
    BUSY)
      audit_line "$gid" SKIP-BUSY "driving; left alone"; cache_state "$gid" "$state" ;;
    IDLE)
      cache_state "$gid" "$state" ;;                    # not stalled → leave alone this poll
    *)
      cache_state "$gid" "$state" ;;
  esac
}

# ---------- main loop ----------
process_goals() {
  local gdir f gid state prev reg_json reg_rc
  gdir="$(goals_dir)"
  [ -d "$gdir" ] || return 0
  # D-C8 e09 fold: ONE registry fetch per poll (was: one per goal via
  # classify_goal), threaded to every classify_goal call below as data.
  reg_json=$(${SDLC_REGISTRY_CMD:-claude agents --json} 2>/dev/null); reg_rc=$?
  for f in "$gdir"/*; do
    [ -f "$f" ] || continue           # empty dir → the literal glob, skipped
    gid=$(basename "$f")
    # C1 addendum: the goal-id (registration filename) reaches paths and
    # notification titles — validate it before trusting it anywhere.
    case "$gid" in
      *[!a-z0-9-]*|'')
        audit_line "$gid" MALFORMED-RECORD "invalid goal-id: must match ^[a-z0-9-]+"
        continue ;;
    esac
    if ! load_registration "$gid"; then
      audit_line "$gid" MALFORMED-RECORD "missing required key in registration"
      continue
    fi
    if [ ! -f "$REG_PLAN" ]; then
      audit_line "$gid" MALFORMED-RECORD "registered plan not readable: $REG_PLAN"
      continue
    fi
    is_armed "$gid" || continue       # keepalive-effective=false → audited SKIP-UNARMED, or MALFORMED-RECORD
    state=$(classify_goal "$gid" "$reg_json" "$reg_rc")
    [ -n "$state" ] || continue       # total-signal-loss degrade → already audited, skip
    prev=$(read_cache "$gid")         # previous classification (transition dedupe)
    write_status "$gid" "$state"
    dispatch_actions "$gid" "$state" "$prev"   # poke/notify per the C3 no-force table; caches state
  done
}

# C8 amendment: the poker SELF-SOURCES the standing-service env file so plain,
# non-exported KEY=value lines reach the poke child and the notify path regardless
# of how the cron entry sourced them (the C7 entry's `. cron.env` binds vars in the
# sh -c shell only; the poker child inherits nothing → "Not logged in" + "no ntfy
# topic configured", observed live). `set -a` exports every var the file defines;
# guarded on existence; the env path is overridable for the fixture suite.
env_self_source() {
  local envf; envf="${BIONIC_CRON_ENV:-$HOME/.claude/cron.env}"
  [ -f "$envf" ] || return 0
  set -a; . "$envf" 2>/dev/null; set +a
  return 0
}

main() {
  env_self_source
  mkdir -p "$(goals_dir)" "$(status_dir)" "$(state_dir)" 2>/dev/null
  acquire_lock || exit 0             # live overlap → silent, normal
  # D-C9 fail-closed degrade: no lib → no ladder for any goal (baton-less legacy
  # everywhere). Audit once per poll so the degrade is observable, never silent.
  [ "$SDLC_LIB_OK" = "1" ] || audit_line "-" LADDER-DEGRADE "sdlc-state-lib unavailable ($SDLC_STATE_LIB); baton-less legacy for all goals"
  process_goals
  release_lock
  exit 0
}

if [ "${SDLC_POKER_LIB:-0}" != "1" ]; then
  main "$@"
fi
