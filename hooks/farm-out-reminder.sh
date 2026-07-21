#!/bin/bash
# FARM-OUT: tiered PreToolUse(Bash) enforcement — long-running main-thread
# commands DENY with a redirect to the right role; fuzzy production-shaped
# commands get ONE additionalContext nudge per class per session; every
# tier-1/tier-2 event logs one line to .bionic/memory/sdlc-v11-audit.md
# (log_finding() shape, own copy — deliberate per-hook duplication).
#
# Exit 0 on EVERY path. Enforcement lives in stdout JSON only:
#   deny  → hookSpecificOutput.permissionDecision "deny" + redirect reason
#   nudge → hookSpecificOutput.additionalContext
# Never "allow", never updatedInput, never exit 2 (epic-08 wave-04 ADR-002;
# amends D14 per user ratification 2026-07-20).
#
# Thread discrimination (epic-08 Q1 spike + hooks docs): agent_type
# non-empty → subagent → silent. Missing keys classify as MAIN THREAD.
# Installed globally by claude-bootstrap.sh to ~/.claude/hooks/

set -u

command -v jq >/dev/null 2>&1 || exit 0
INPUT=$(cat) || exit 0
[ -n "$INPUT" ] || exit 0

_jq() { printf '%s' "$INPUT" | jq -r "$1 // empty" 2>/dev/null || printf ''; }

AGENT_TYPE=$(_jq '.agent_type');   [ -n "$AGENT_TYPE" ] && exit 0
TOOL_NAME=$(_jq '.tool_name');     [ "$TOOL_NAME" = "Bash" ] || exit 0
CMD=$(_jq '.tool_input.command');  [ -n "$CMD" ] || exit 0
SESSION_ID=$(_jq '.session_id');   [ -n "$SESSION_ID" ] || SESSION_ID="unknown"

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-}"
[ -n "$PROJECT_DIR" ] || PROJECT_DIR=$(_jq '.cwd')
[ -n "$PROJECT_DIR" ] && [ -d "$PROJECT_DIR" ] || exit 0

MODE="block"
if [ -f "$PROJECT_DIR/.bionic/config.yaml" ]; then
  _cfg=$(grep -E '^farm-out-mode:' "$PROJECT_DIR/.bionic/config.yaml" 2>/dev/null | head -1 \
    | sed 's/^farm-out-mode:[[:space:]]*//' | tr -d '\r' | sed 's/[[:space:]]*$//')
  case "$_cfg" in block|advisory|off) MODE="$_cfg" ;; esac
fi
[ "$MODE" = "off" ] && exit 0

# Normalized single-line form for matching + audit excerpts (CR translate).
FLAT=$(printf '%s' "$CMD" | awk '{ sub(/\r$/, ""); gsub(/\r/, "\n"); print }' | tr '\n' ' ' \
  | sed 's/[[:space:]]\{1,\}/ /g; s/^ //; s/ $//')

log_event() {  # $1=event $2=class
  local audit_dir="$PROJECT_DIR/.bionic/memory"
  local excerpt; excerpt=$(printf '%s' "$FLAT" | cut -c1-120)
  local line="- $(date -u +%Y-%m-%dT%H:%M:%SZ) farm-out $1: class=$2 mode=$MODE ($excerpt)"
  mkdir -p "$audit_dir" 2>/dev/null && printf '%s\n' "$line" >> "$audit_dir/sdlc-v11-audit.md" 2>/dev/null
  echo "farm-out [$1] class=$2" >&2
  return 0
}

emit_deny() {  # $1=class $2=role
  jq -n --arg r "$(deny_reason "$1" "$2")" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}' 2>/dev/null
  return 0
}

emit_nudge() {  # $1=class $2=role
  jq -n --arg c "farm-out reminder: $1-class command on the main thread — production-shaped work belongs in a subagent (subagent_type: $2). This protects your own context budget; a stuck orchestrator cannot process completions. Advisory only." \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$c}}' 2>/dev/null
  return 0
}

deny_reason() {  # $1=class $2=role
  printf '%s' "farm-out policy: this is a long-running $1-class command; it must not run on the orchestrator thread (a stuck orchestrator is unavailable and cannot process subagent completions — this protects your own context budget). Dispatch it instead: Agent(subagent_type: $2, prompt carrying this exact command): $FLAT — the agent returns the result summary. If this genuinely cannot be dispatched (needs this session's state), re-run prefixed FARM_OUT_ALLOW=1 — the override is sanctioned and audited."
}

# ── classification (4/2 tier-1; classify_tier2 lands in 4/3) ─────────────
# override check + wrapper unwrap precede classify_tier1.

strip_prefixes() {  # env / FARM_OUT_*= / nohup / timeout wrappers → stripped form
  printf '%s' "$1" | sed -E 's/^(env +)?(FARM_OUT_[A-Z_]+=[^ ]+ +)?(nohup +)?(timeout +[0-9]+[smh]? +)?//'
}

unwrap() {  # one level of sh -c / bash -c / eval / bash <(...) → inner command
  local c="$1"
  case "$c" in
    "sh -c "*|"bash -c "*)
      printf '%s' "$c" | sed -E "s/^(sh|bash) -c +//; s/^'(.*)'\$/\1/; s/^\"(.*)\"\$/\1/" ;;
    "eval "*) printf '%s' "${c#eval }" ;;
    "bash <("*)
      # bash <(cat FILE) ≡ bash FILE (process substitution feeding a reader);
      # collapse to the executed script so the workaround closes onto the
      # tier-1 matcher — the inner `cat test.sh` alone would not match.
      printf '%s' "$c" | sed -E 's/^bash <\((cat|tac) +//; s/^bash <\(//; s/\)$//; s/^/bash /' ;;
    *) printf '%s' "$c" ;;
  esac
}

classify_tier1() {  # $1=flat cmd → sets CLASS ROLE, rc 0 on match
  local c="$1"
  if printf '%s' "$c" | grep -qE '(^|[;&| ])bash +([^ ]*/)?(test\.sh|tests/run\.sh)( |$)|(^|[;&| ])bash +[^ ]+\.test\.sh( |$)|^(npm|pnpm|yarn) +test( |$)|^pytest( |$)|^go +test( |$)|^cargo +test( |$)|^make +test( |$)'; then
    CLASS="suite"; ROLE="test-runner"; return 0; fi
  if printf '%s' "$c" | grep -qE '(^|[;&| ])\.?/?([^ ]*/)?claude-(bootstrap|reset)\.sh( |$)'; then
    CLASS="bootstrap"; ROLE="implementor"; return 0; fi
  if printf '%s' "$c" | grep -qE '^(npm|pnpm|yarn) +(install|add|ci)( |$)|^pip3? +install( |$)|^uv +(sync|pip)( |$)|^brew +install( |$)'; then
    CLASS="install"; ROLE="implementor"; return 0; fi
  if printf '%s' "$c" | grep -qE '^(npm|pnpm|yarn) +run +build( |$)|^cargo +build( |$)|^go +build( |$)|^docker +build( |$)|^make$'; then
    CLASS="build"; ROLE="implementor"; return 0; fi
  return 1
}

emit_tier1() {  # $1=class $2=role — deny, or downgrade to a nudge under advisory
  if [ "$MODE" = "advisory" ]; then
    log_event "deny-downgraded" "$1"; emit_nudge "$1" "$2"; exit 0
  fi
  log_event "deny" "$1"; emit_deny "$1" "$2"; exit 0
}

# ── main flow: override → wrapper-unwrap → tier-1 deny → chain (tier-1 arm) ──
case "$FLAT" in
  "FARM_OUT_ALLOW=1 "*|"env FARM_OUT_ALLOW=1 "*)
    log_event "override" "user-sanctioned"; exit 0 ;;
esac

TARGET=$(unwrap "$(strip_prefixes "$FLAT")")
CLASS=""; ROLE=""

if classify_tier1 "$TARGET"; then
  emit_tier1 "$CLASS" "$ROLE"
fi

# Chain rule (tier-1 arm; the tier-2 arm lands in 4/3): ≥3 &&-joined segments
# where ANY stripped/unwrapped segment matches tier-1 → deny as class=chain,
# role taken from the matching segment.
case "$FLAT" in
  *"&&"*)
    _flat_nl=$(printf '%s' "$FLAT" | awk '{ gsub(/&&/, "\n"); print }')
    _seg_count=$(printf '%s\n' "$_flat_nl" | grep -cE '[^[:space:]]')
    if [ "${_seg_count:-0}" -ge 3 ]; then
      CHAIN_ROLE=""
      while IFS= read -r _seg; do
        _seg=$(printf '%s' "$_seg" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
        [ -n "$_seg" ] || continue
        if classify_tier1 "$(unwrap "$(strip_prefixes "$_seg")")"; then
          CHAIN_ROLE="$ROLE"; break
        fi
      done <<EOF
$_flat_nl
EOF
      [ -n "$CHAIN_ROLE" ] && emit_tier1 "chain" "$CHAIN_ROLE"
    fi
    ;;
esac

exit 0
