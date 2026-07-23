#!/bin/bash
# CONTEXT-SPEND: advisory Stop hook — appends ONE context-spend line per
# SDLC step boundary to $HOME/.claude/logs/<project-slug>/sdlc-v11-audit.md —
# outside every consuming project tree (incident 0001), via audit_path() —
# reusing the log_v11_finding() line format (source: context-spend).
#
# Mechanism (epic-08 A7 / Q2 spike): Stop = trigger + transcript_path;
# last assistant message.usage (TOP-LEVEL, never iterations[]) = occupancy
# (input + cache_creation + cache_read); the active plan's `current:` line
# = step attribution; .bionic/tmp/context-spend.state = boundary detector.
#
# Failure mode: silence. Missing jq/transcript/usage/plan/current →
# exit 0, nothing appended, state untouched. NEVER blocks, NEVER writes
# stdout (a Stop hook's stdout could carry a block payload).
#
# Installed globally by claude-bootstrap.sh to ~/.claude/hooks/

set -u

command -v jq >/dev/null 2>&1 || exit 0
INPUT=$(cat)

SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null) || SESSION_ID=""
[ -n "$SESSION_ID" ] || SESSION_ID="unknown"

TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null) || TRANSCRIPT=""
[ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] || exit 0

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-}"
if [ -z "$PROJECT_DIR" ]; then
  PROJECT_DIR=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null) || PROJECT_DIR=""
fi
[ -n "$PROJECT_DIR" ] && [ -d "$PROJECT_DIR" ] || exit 0

# Incident 0001: the audit stream must live where a consuming project cannot
# commit it, regardless of that project's .gitignore. $HOME-rooted, per-project,
# durable — mirroring hooks/sdlc-poker.sh:111's $HOME/.claude/ audit log.
# Slug = <basename>-<cksum of the absolute path>: readable, deterministic, and
# collision-resistant across same-named projects under different parents.
# cksum and basename are POSIX — no new dependency.
# Byte-identical to the copies in farm-out-reminder.sh,
# canonical-sdlc-governing-skill.sh and canonical-sdlc-evidence-gate.sh —
# divergence would give one project two audit files. Deliberate per-hook
# duplication (no shared lib).
audit_path() {  # $1=project root → absolute audit-file path; rc 1 if no $HOME
  [ -n "${HOME:-}" ] || return 1
  local base sum
  base=$(basename "$1" | sed 's/[^A-Za-z0-9._-]/-/g')
  sum=$(printf '%s' "$1" | cksum | cut -d' ' -f1)
  printf '%s/.claude/logs/%s-%s/sdlc-v11-audit.md' "$HOME" "$base" "$sum"
}

# docs-root: .bionic/config.yaml override, default .bionic/docs
DOCS_ROOT=".bionic/docs"
if [ -f "$PROJECT_DIR/.bionic/config.yaml" ]; then
  _cfg=$(grep -E '^docs-root:' "$PROJECT_DIR/.bionic/config.yaml" 2>/dev/null | head -1 | sed 's/^docs-root:[[:space:]]*//' | tr -d '\r' | sed 's/[[:space:]]*$//')
  [ -n "$_cfg" ] && DOCS_ROOT="$_cfg"
fi
PLANS_DIR="$PROJECT_DIR/$DOCS_ROOT/plans"
[ -d "$PLANS_DIR" ] || exit 0

# Newest plan, descending up to 2 levels (evidence-gate convention).
PLAN=$(ls -t "$PLANS_DIR"/*.plan.md "$PLANS_DIR"/*/*.plan.md "$PLANS_DIR"/*/*/*.plan.md 2>/dev/null | head -1)
[ -n "$PLAN" ] && [ -f "$PLAN" ] || exit 0

# current: from ## SDLC State — CR-normalized, fence-aware (the evidence-gate
# defect class: fenced skeletons quoting `current:` must stay invisible).
STEP=$(awk '{ sub(/\r$/, ""); gsub(/\r/, "\n"); print }' "$PLAN" | awk '
  /^```/ { fence = !fence; next }
  fence { next }
  /^## SDLC State/ { insec = 1; next }
  insec && /^## / { insec = 0 }
  insec && /^current:[[:space:]]*/ { sub(/^current:[[:space:]]*/, ""); sub(/[[:space:]]*$/, ""); print; exit }
')
[ -n "$STEP" ] || exit 0

# Last assistant entry with usage, from a bounded tail. fromjson? swallows
# malformed lines. Emits "model<TAB>occupied" for the last qualifying entry.
_row=$(tail -n 400 "$TRANSCRIPT" 2>/dev/null | jq -Rr '
  fromjson? | select(.type == "assistant") | .message | select(.usage != null) |
  [(.model // "unknown"),
   ((.usage.input_tokens // 0) + (.usage.cache_creation_input_tokens // 0) + (.usage.cache_read_input_tokens // 0))] | @tsv
' 2>/dev/null | tail -1) || _row=""
[ -n "$_row" ] || exit 0
MODEL=${_row%	*}
OCCUPIED=${_row##*	}
case "$OCCUPIED" in ''|*[!0-9]*) exit 0 ;; esac
[ "$OCCUPIED" -gt 0 ] || exit 0

# ============================================================
# CEILING TRIPWIRE (epic-10-never-die N1, R-C1/R-C2). Independent of the
# step-boundary emission below: context can cross a threshold WITHIN a single
# step, so this samples pct = occupied/ceiling(model) on every qualifying Stop
# and, transitions-only (D6), emits at most one advisory (>=50%) and one red
# (>=70%) audit line per upward crossing. While red it nags a MANDATE line
# until a baton fresher than the red transition exists. State is a SEPARATE
# marker file — the 4-field TSV session state below is untouched (AS-2). All
# failure is silent: any misstep here leaves the step-boundary logic and the
# hook's exit-0-always contract intact.
# ------------------------------------------------------------
# ceiling(model): BIONIC_CONTEXT_CEILING wins; else a per-model table; else the
# conservative 200000 default (D5). FAIL-CLOSED denominator (plan §Global
# constraints, binding): a ceiling must err toward the SMALLEST plausible window
# so the tripwire fires early, never the largest convenient one — an oversized
# denominator is the silent-death class this epic exists to kill. Rows are the
# smallest standard window consistent with observed telemetry
# ($HOME/.claude/logs/<project-slug>/sdlc-v11-audit.md): claude-fable-5 seen at occupied=524861 →
# rules out 500k, 1M is the smallest standard window that fits. Others default
# to 200000 until telemetry justifies raising them. Recalibrate UPWARD only on
# observed evidence (a too-small ceiling merely warns early; too-large stays silent).
_ceiling=""
case "${BIONIC_CONTEXT_CEILING:-}" in
  ''|*[!0-9]*) : ;;                       # unset/non-numeric → fall through to table
  *) _ceiling="$BIONIC_CONTEXT_CEILING" ;;
esac
if [ -z "$_ceiling" ]; then
  case "$MODEL" in
    *fable*)   _ceiling=1000000 ;;        # observed max 524861 → smallest fit is 1M
    *opus*)    _ceiling=200000 ;;         # no telemetry yet → conservative default
    *sonnet*)  _ceiling=200000 ;;         # no telemetry yet → conservative default
    *haiku*)   _ceiling=200000 ;;
    *)         _ceiling=200000 ;;         # conservative default for unknown models
  esac
fi
# Thresholds (percent) — overridable for accelerated tests (AS-4).
_adv_pct="${BIONIC_CONTEXT_ADVISORY_PCT:-50}"
_red_pct="${BIONIC_CONTEXT_RED_PCT:-70}"
case "$_adv_pct" in ''|*[!0-9]*) _adv_pct=50 ;; esac
case "$_red_pct" in ''|*[!0-9]*) _red_pct=70 ;; esac

if [ "$_ceiling" -gt 0 ] 2>/dev/null; then
  _pct=$(( OCCUPIED * 100 / _ceiling ))

  # goal-id: sanitized stem of the plan path the hook already tracks. No poker
  # function derives a goal-id from a plan (it validates ^[a-z0-9-]+$ on the
  # registration filename); this mirrors the in-repo sanitizer idiom
  # (canonical-sdlc-evidence-gate.sh: printf | sed | tr '[:upper:]' '[:lower:]')
  # so the output satisfies the poker's charset by construction.
  _goal_id=$(printf '%s' "$(basename "$PLAN" .plan.md)" | sed 's/[^A-Za-z0-9-]/-/g' | tr '[:upper:]' '[:lower:]')

  if [ -n "$_goal_id" ]; then
    _cdir="${SDLC_STATE_DIR:-$HOME/.claude/sdlc-state}/$_goal_id"
    _marker="$_cdir/ceiling"
    _baton="$_cdir/baton.md"

    # Marker: "adv_fired red_fired red_ts" (dedupe substrate). Absent → never
    # fired (context only grows, so a first sample already >= a threshold IS an
    # upward crossing and must fire).
    _adv=0; _red=0; _rts=""
    if [ -f "$_marker" ]; then
      read -r _adv _red _rts < "$_marker" 2>/dev/null || true
      case "$_adv" in ''|*[!0-9]*) _adv=0 ;; esac
      case "$_red" in ''|*[!0-9]*) _red=0 ;; esac
    fi

    _cline() {  # $1=kind $2=extra — one audit line in the hook's line convention.
      # Timestamp computed HERE (not hoisted above) so the common
      # below-threshold path — the vast majority of samples — forks no
      # extra `date` process for a line it will never emit.
      #
      # The mkdir lives HERE, not at the call sites. Pre-incident-0001 the
      # three call sites each did `mkdir -p "$AUDIT_DIR_C"` against the
      # project's .bionic/memory/, a directory that usually already existed.
      # The relocated $HOME/.claude/logs/<slug>/ never exists on first use, so
      # the create has to sit with the append or every ceiling line is dropped
      # silently. Unwritable destination → the line is dropped, no fallback.
      local _cts; _cts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
      local _f; _f=$(audit_path "$PROJECT_DIR") || return 0
      mkdir -p "$(dirname "$_f")" 2>/dev/null && \
        printf '%s\n' "- $_cts context-spend ceiling $1: goal=$_goal_id $2 model=$MODEL ($PLAN)" \
          >> "$_f" 2>/dev/null
      return 0
    }

    if [ "$_pct" -lt "$_adv_pct" ]; then
      # Below advisory → re-arm: drop the marker so a later re-crossing fires.
      [ -f "$_marker" ] && rm -f "$_marker" 2>/dev/null
    else
      mkdir -p "$_cdir" 2>/dev/null
      if [ "$_pct" -ge "$_red_pct" ]; then
        if [ "$_red" -eq 0 ]; then
          _cline red "pct=$_pct occupied=$OCCUPIED ceiling=$_ceiling"
          _red=1; _adv=1
          _rts=$(date +%s)                 # red-transition time (epoch, local)
        fi
        # Baton freshness: fresh iff it exists AND mtime strictly newer than the
        # red transition. Stale/absent → nag a MANDATE each red sample until a
        # fresh baton lands (a pre-red baton counts stale).
        _fresh=0
        if [ -f "$_baton" ]; then
          _bm=$(stat -f %m "$_baton" 2>/dev/null || stat -c %Y "$_baton" 2>/dev/null)
          case "$_bm" in ''|*[!0-9]*) _bm=0 ;; esac
          case "$_rts" in ''|*[!0-9]*) _rts=0 ;; esac
          [ "$_bm" -gt "$_rts" ] && _fresh=1
        fi
        if [ "$_fresh" -eq 0 ]; then
          _cline mandate "red pct=$_pct — no fresh baton; write a baton for $_goal_id"
        fi
      else
        # Advisory zone (adv <= pct < red).
        if [ "$_adv" -eq 0 ]; then
          _cline advisory "pct=$_pct occupied=$OCCUPIED ceiling=$_ceiling"
          _adv=1
        fi
        # Dropped out of red into advisory → re-arm the red crossing.
        if [ "$_red" -eq 1 ]; then _red=0; _rts=""; fi
      fi
      printf '%s %s %s\n' "$_adv" "$_red" "$_rts" > "$_marker" 2>/dev/null || true
    fi
  fi
fi

STATE_DIR="$PROJECT_DIR/.bionic/tmp"
STATE="$STATE_DIR/context-spend.state"
mkdir -p "$STATE_DIR" 2>/dev/null || exit 0

s_plan=""; s_sess=""; s_step=""; s_occ=""
if [ -f "$STATE" ]; then
  IFS='	' read -r s_plan s_sess s_step s_occ < "$STATE" 2>/dev/null || true
fi

# First-seen, plan switch, or session switch: seed silently. Two
# concurrent sessions on the same plan must never diff against each
# other's occupancy — a session change re-seeds, same as a plan change.
if [ "$s_plan" != "$PLAN" ] || [ "$s_sess" != "$SESSION_ID" ] || [ -z "$s_step" ]; then
  printf '%s\t%s\t%s\t%s\n' "$PLAN" "$SESSION_ID" "$STEP" "$OCCUPIED" > "$STATE" 2>/dev/null || true
  exit 0
fi

# Same step: nothing to do (state deliberately untouched — it records the
# occupancy at the step's START boundary, so delta spans the whole step).
[ "$s_step" = "$STEP" ] && exit 0

# Boundary: emit one line for the ENDED step.
case "$s_occ" in ''|*[!0-9]*) s_occ="$OCCUPIED" ;; esac
DELTA=$((OCCUPIED - s_occ))
if [ "$DELTA" -ge 0 ]; then DELTA="+$DELTA"; fi
LINE="- $(date -u +%Y-%m-%dT%H:%M:%SZ) context-spend step-$s_step: occupied=$OCCUPIED delta=$DELTA model=$MODEL ($PLAN)"
if AUDIT_FILE=$(audit_path "$PROJECT_DIR"); then
  mkdir -p "$(dirname "$AUDIT_FILE")" 2>/dev/null && printf '%s\n' "$LINE" >> "$AUDIT_FILE" 2>/dev/null
fi
printf '%s\t%s\t%s\t%s\n' "$PLAN" "$SESSION_ID" "$STEP" "$OCCUPIED" > "$STATE" 2>/dev/null || true
exit 0
