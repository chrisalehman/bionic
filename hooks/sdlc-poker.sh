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

# Absolute claude binary for the POKE (C4: alias not inherited). The registry
# READ uses PATH-resolved bare `claude` (AS-7a); only the poke is pinned. Kept
# overridable exactly as the thresholds are, so the fixture suite points it at a
# stub — the default literal is the fixture-asserted contract value.
POKE_CLAUDE_BIN="${POKE_CLAUDE_BIN:-/opt/homebrew/bin/claude}"

# Fixed poke prompt (C4, fixture-asserted): resume-and-continue with the gate
# escape hatch, carrying NO approval vocabulary (banned-token list, C4). Single-
# quoted so the backticked markers stay literal (no command substitution).
POKE_PROMPT='continue per the plan'"'"'s `## SDLC State`; if blocked on a decision, write a `## Wake Note` and stop'

# Registration globals — bound unconditionally so set -u never trips on a path
# that reads them before load_registration runs (hooks-rules.md).
REG_PLAN=""; REG_CWD=""; REG_SESSION_ID=""; REG_PID=""; REG_ARMED_AT=""

# ---------- path helpers (read $HOME at call time) ----------
goals_dir()   { printf '%s/.claude/sdlc-goals' "$HOME"; }
status_dir()  { printf '%s/.claude/sdlc-status' "$HOME"; }
state_dir()   { printf '%s/.claude/sdlc-status/.state' "$HOME"; }
audit_log()   { printf '%s/.claude/sdlc-poker-audit.log' "$HOME"; }
lock_dir()    { printf '%s/.claude/sdlc-poker.lock' "$HOME"; }

# Transcript project directory for a cwd. Claude Code keys project dirs by cwd,
# replacing every '/' and '.' with '-' (verified live on 2.1.216:
# /Users/admin/workspace/personal/bionic/.bionic/tmp/p3 →
# -Users-admin-workspace-personal-bionic--bionic-tmp-p3). Transcripts are
# cwd-keyed, NOT repo-keyed (P3), so the poker must know each target's cwd.
project_dir_for_cwd() {
  printf '%s/.claude/projects/%s' "$HOME" "$(printf '%s' "$1" | sed 's#[/.]#-#g')"
}

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

# Armed = registration present (loaded) AND the plan declares scale: continuous.
# The plan-readability half is checked by the caller (unreadable plan is
# MALFORMED, not merely unarmed); here we test only the scale declaration.
is_armed_scale() {  # uses REG_PLAN
  [ "$(plan_frontmatter "$REG_PLAN" scale)" = "continuous" ]
}

# ---------- transcript signals ----------
# Newest transcript for the registered session: prefer <sid>.jsonl, else the
# newest *.jsonl in the cwd-keyed project dir. Echoes a path or nothing.
resolve_transcript() {  # uses REG_CWD, REG_SESSION_ID
  local pdir t
  pdir=$(project_dir_for_cwd "$REG_CWD")
  t="$pdir/$REG_SESSION_ID.jsonl"
  if [ -f "$t" ]; then printf '%s' "$t"; return; fi
  t=$(ls -t "$pdir"/*.jsonl 2>/dev/null | head -1)
  [ -n "$t" ] && [ -f "$t" ] && printf '%s' "$t"
}

# Transcript quiet in seconds (now - mtime). No transcript → 0 (recently-active
# assumption: mtime is a suspect flag only and must never manufacture a stall).
transcript_quiet() {
  local t mt now
  t=$(resolve_transcript)
  [ -n "$t" ] || { echo 0; return; }
  mt=$(file_mtime "$t" 2>/dev/null) || mt=""
  [ -n "$mt" ] || { echo 0; return; }
  now=$(date +%s)
  echo $(( now - mt ))
}

# Last-event grammar (degrade fallback): dangling tool_use → busy;
# last-prompt (user) marker → idle; otherwise unknown.
transcript_grammar() {
  local t last
  t=$(resolve_transcript)
  [ -n "$t" ] || { echo unknown; return; }
  last=$(tail -n 1 "$t" 2>/dev/null)
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

# classify_goal <goal-id> → one of COMPLETE|GATED|DEAD|IDLE_STALLED|IDLE|BUSY|WEDGED
# (or "" on total-signal-loss degrade). Loads the registration itself so it is
# callable directly on a planted goal. Plan state first, session liveness second.
classify_goal() {  # $1=goal-id
  local gid="$1"
  load_registration "$gid" || { echo ""; return; }

  # 1. PLAN state (charter close / gate take precedence over liveness).
  [ "$(plan_current "$REG_PLAN")" = "10" ] && { echo COMPLETE; return; }
  plan_has_wake_note "$REG_PLAN" && { echo GATED; return; }

  # 2. SESSION liveness — `claude agents --json`, by SESSION_ID only (never
  #    enumeration). Registry unavailable/unparseable → degrade.
  local json rc present status
  json=$(claude agents --json 2>/dev/null); rc=$?
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
  local gid="$1" state="$2" dir t iso cur
  dir="$(status_dir)"; mkdir -p "$dir" 2>/dev/null
  cur=$(plan_current "$REG_PLAN"); [ -n "$cur" ] || cur="unknown"
  t=$(resolve_transcript)
  if [ -n "$t" ]; then iso=$(iso_of_mtime "$t"); else iso="unknown"; fi
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
# Resume the stalled session and hand it the fixed prompt via STDIN (a positional
# prompt after flags is swallowed, P1). Absolute binary (alias not inherited),
# cd-first (--resume is cwd/project-scoped, P2), no --model (the resumed turn does
# the goal's real work). Idempotent and leaf-agnostic. Echoes nothing; returns
# the resume exit code (a nonzero poke still counts against the cap).
do_poke() {  # $1=goal-id ; uses REG_CWD, REG_SESSION_ID
  local gid="$1" rc
  ( cd "$REG_CWD" 2>/dev/null && printf '%s' "$POKE_PROMPT" \
      | "$POKE_CLAUDE_BIN" --resume "$REG_SESSION_ID" -p --dangerously-skip-permissions \
  ) >/dev/null 2>&1
  rc=$?
  audit_line "$gid" POKE "resume $REG_SESSION_ID rc=$rc"
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

# ---------- C4 retry-cap: stall episodes ----------
# Per-goal poke-episode state: "<transcript-mtime> <poke-count> <pokefail-sent>".
# The episode is keyed by transcript mtime; any movement resets count + the
# POKE-FAIL flag. A dead session's poke does not move the transcript, so repeated
# stalls stay one episode and the cap bites.
poke_state_file() { printf '%s/%s.poke' "$(state_dir)" "$1"; }

transcript_mtime_key() {  # uses REG_CWD, REG_SESSION_ID
  local t; t=$(resolve_transcript)
  [ -n "$t" ] || { printf 'none'; return; }
  file_mtime "$t" 2>/dev/null || printf 'none'
}

# Poke a stalled goal, honoring the per-episode cap. On cap exhaustion emit a
# single POKE-FAIL notification and park (until the episode resets on movement).
poke_capped() {  # $1=goal-id
  local gid="$1" pf mtime smtime scount sfail
  pf="$(poke_state_file "$gid")"
  mtime=$(transcript_mtime_key)
  smtime=""; scount=0; sfail=0
  if [ -f "$pf" ]; then
    read -r smtime scount sfail < "$pf" 2>/dev/null || true
    [ -n "$scount" ] || scount=0
    [ -n "$sfail" ] || sfail=0
  fi
  [ "$mtime" = "$smtime" ] || { scount=0; sfail=0; }   # movement → new episode
  if [ "$scount" -ge "$POKE_CAP" ]; then
    if [ "$sfail" -ne 1 ]; then
      do_notify "$gid" POKE-FAIL "poke cap ($POKE_CAP) exhausted for $gid; parking until state change" \
        && sfail=1
    fi
    printf '%s %s %s\n' "$mtime" "$scount" "$sfail" > "$pf" 2>/dev/null
    return 0
  fi
  do_poke "$gid"                                        # counts regardless of exit
  scount=$((scount + 1))
  printf '%s %s %s\n' "$mtime" "$scount" "$sfail" > "$pf" 2>/dev/null
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

# Per the C3 table: COMPLETE/GATED/WEDGED notify-on-transition (never poke; gate
# and wedge supremacy); DEAD/IDLE_STALLED poke under the cap; BUSY logs SKIP-BUSY;
# IDLE is left alone. Non-notify states advance the cache directly so a later
# transition INTO a notify state is detected.
dispatch_actions() {  # $1=gid $2=state $3=prev
  local gid="$1" state="$2" prev="$3"
  case "$state" in
    COMPLETE)
      notify_and_cache "$gid" COMPLETE "goal $gid complete (charter close / current:10)" "$prev" "$state" ;;
    GATED)
      notify_and_cache "$gid" GATED "goal $gid gated — decision required; see the plan's ## Wake Note" "$prev" "$state" ;;
    WEDGED)
      notify_and_cache "$gid" WEDGE \
        "goal $gid WEDGED: driving but transcript quiet >${WEDGE_QUIET}s. recovery: $(recovery_cmd)" "$prev" "$state" ;;
    DEAD|IDLE_STALLED)
      poke_capped "$gid"; cache_state "$gid" "$state" ;;
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
  local gdir f gid state prev
  gdir="$(goals_dir)"
  [ -d "$gdir" ] || return 0
  for f in "$gdir"/*; do
    [ -f "$f" ] || continue           # empty dir → the literal glob, skipped
    gid=$(basename "$f")
    if ! load_registration "$gid"; then
      audit_line "$gid" MALFORMED-RECORD "missing required key in registration"
      continue
    fi
    if [ ! -f "$REG_PLAN" ]; then
      audit_line "$gid" MALFORMED-RECORD "registered plan not readable: $REG_PLAN"
      continue
    fi
    is_armed_scale || continue        # scale != continuous → unarmed/disarm, silent skip
    state=$(classify_goal "$gid")
    [ -n "$state" ] || continue       # total-signal-loss degrade → already audited, skip
    prev=$(read_cache "$gid")         # previous classification (transition dedupe)
    write_status "$gid" "$state"
    dispatch_actions "$gid" "$state" "$prev"   # poke/notify per the C3 no-force table; caches state
  done
}

main() {
  mkdir -p "$(goals_dir)" "$(status_dir)" "$(state_dir)" 2>/dev/null
  acquire_lock || exit 0             # live overlap → silent, normal
  process_goals
  release_lock
  exit 0
}

if [ "${SDLC_POKER_LIB:-0}" != "1" ]; then
  main "$@"
fi
