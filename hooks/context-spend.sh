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
# durable — the same $HOME/.claude/ audit path the archived epic-10 poker used
# (that work is recoverable at tag archive/epic-10-never-die).
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
