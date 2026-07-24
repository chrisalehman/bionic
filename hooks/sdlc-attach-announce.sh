#!/bin/bash
# ATTACH-ANNOUNCE: SessionStart(resume) hook — wave-keepalive S10
# (spec R12/AC-13, design KA-R15). On resume of a session whose cwd belongs
# to a watchdog-armed goal, injects additionalContext instructing the
# session to open with the hand-off announcement: the human has the conn
# while attached, and autopilot resumes ~3 minutes after they exit.
#
# Match rule (per goal registration whose CWD equals this session's cwd):
# this session's SESSION_ID equals the record's SESSION_ID (the literal
# armed session reattaching), OR the record's PLAN resolves
# watchdog-effective=on (a successor/poked session carries a fresh session
# id but the same armed plan — KA-R16 fallback table). Silent (no stdout)
# when nothing matches.
#
# The KA-R16 fallback-table resolution is mirrored LOCALLY rather than
# sourcing sdlc-state-lib.sh: that lib is under concurrent edit elsewhere
# in this wave, and this is a read-only advisory path — a self-contained
# reader is the safer seam. goals_dir has no env override today (mirrors
# sdlc-poker.sh:goals_dir byte-for-byte — no SDLC_GOALS_DIR seam exists).
#
# Exit 0 on EVERY path — never blocks session start. set -u-safe, CR/CRLF
# -safe (normalize_nl mirrors sdlc-poker.sh's plan_frontmatter reader),
# BSD-portable.
#
# Installed globally by claude-bootstrap.sh to ~/.claude/hooks/
# (SessionStart|resume).

set -u

command -v jq >/dev/null 2>&1 || exit 0
INPUT=$(cat) || exit 0
[ -n "$INPUT" ] || exit 0

_jq() { printf '%s' "$INPUT" | jq -r "$1 // empty" 2>/dev/null || printf ''; }

SESSION_ID=$(_jq '.session_id')
CWD=$(_jq '.cwd')
[ -n "$CWD" ] || exit 0

GOALS_DIR="$HOME/.claude/sdlc-goals"
[ -d "$GOALS_DIR" ] || exit 0

# CR/CRLF-normalized line stream — byte-equivalent to
# sdlc-poker.sh:normalize_nl / sdlc-state-lib.sh:_sdlc_plan_fm's translate
# step. Handles CR-only (old-Mac) records too: gsub turns every embedded
# \r into \n so a CR-only file still splits into real lines downstream.
_normalize_nl() { awk '{ sub(/\r$/, ""); gsub(/\r/, "\n"); print }' "$1" 2>/dev/null; }

# KEY=VALUE lookup in a goal registration record (CR/CRLF-safe).
_reg_val() {  # $1=file $2=key
  _normalize_nl "$1" | grep -E "^$2=" | head -1 | sed -E "s/^$2=//"
}

# Top-frontmatter value — byte-equivalent to sdlc-poker.sh:plan_frontmatter
# / sdlc-state-lib.sh:_sdlc_plan_fm. Fence-blind by design: frontmatter
# keys only, never the fenced ## SDLC State body (not needed here).
_fm() {  # $1=plan $2=key
  _normalize_nl "$1" | awk 'NR==1 && $0=="---"{f=1; next} f && $0=="---"{exit} f' \
    | grep -E "^[[:space:]]*$2[[:space:]]*:" | head -1 \
    | sed -E "s/^[[:space:]]*$2[[:space:]]*:[[:space:]]*//" \
    | sed -E 's/[[:space:]]+$//' | sed -E "s/^['\"]//;s/['\"]\$//"
}

# Effective watchdog on/off — KA-R16 fallback table (explicit flag wins;
# absent → scale-keyed: continuous->on, else off). Unreadable/malformed
# plan never guesses armed (rc 1 = not on).
_watchdog_on() {  # $1=plan
  local plan="$1" v
  [ -n "$plan" ] && [ -f "$plan" ] && [ -r "$plan" ] || return 1
  v="$(_fm "$plan" watchdog)"
  case "$v" in
    on)  return 0 ;;
    off) return 1 ;;
    '')  [ "$(_fm "$plan" scale)" = "continuous" ] ;;
    *)   return 1 ;;
  esac
}

# Effective pilot manual|auto for the status line only; empty on
# unreadable/malformed plan (never fabricate a value).
_pilot_value() {  # $1=plan
  local plan="$1" v
  [ -n "$plan" ] && [ -f "$plan" ] && [ -r "$plan" ] || { printf ''; return; }
  v="$(_fm "$plan" pilot)"
  case "$v" in
    manual|auto) printf '%s' "$v" ;;
    '') if [ "$(_fm "$plan" scale)" = "continuous" ]; then printf auto; else printf manual; fi ;;
    *)  printf '' ;;
  esac
}

MATCH_GID="" MATCH_PLAN="" MATCH_PILOT=""
for f in "$GOALS_DIR"/*; do
  [ -f "$f" ] || continue
  rcwd=$(_reg_val "$f" CWD)
  [ -n "$rcwd" ] && [ "$rcwd" = "$CWD" ] || continue
  rplan=$(_reg_val "$f" PLAN)
  [ -n "$rplan" ] || continue
  rsid=$(_reg_val "$f" SESSION_ID)

  same_session=1
  [ -n "$SESSION_ID" ] && [ "$rsid" = "$SESSION_ID" ] && same_session=0

  if [ "$same_session" -eq 0 ] || _watchdog_on "$rplan"; then
    MATCH_GID="$(basename "$f")"
    MATCH_PLAN="$rplan"
    MATCH_PILOT="$(_pilot_value "$rplan")"
    break
  fi
done

[ -n "$MATCH_GID" ] || exit 0

CONTEXT="Autopilot paused — you have the conn while attached. Exit, and autopilot resumes within ~3 minutes.
Goal: ${MATCH_GID} | Plan: ${MATCH_PLAN} | Pilot: ${MATCH_PILOT:-unknown}"

jq -n --arg ctx "$CONTEXT" '{
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: $ctx
  }
}'
exit 0
