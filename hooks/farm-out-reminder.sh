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

# Normalized single-line form for matching + the scrubbed deny reason (CR translate).
FLAT=$(printf '%s' "$CMD" | awk '{ sub(/\r$/, ""); gsub(/\r/, "\n"); print }' | tr '\n' ' ' \
  | sed 's/[[:space:]]\{1,\}/ /g; s/^ //; s/ $//')

log_event() {  # $1=event $2=class
  # No command-derived text: `class=<c> mode=<m>` is the complete payload.
  # A length bound is not a sanitizer — incident 0001 leaked a live credential
  # through the former `cut -c1-120` excerpt of the raw command.
  local audit_dir="$PROJECT_DIR/.bionic/memory"
  local line="- $(date -u +%Y-%m-%dT%H:%M:%SZ) farm-out $1: class=$2 mode=$MODE"
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

# Pattern scrub for command-derived text (incident 0001). Two shapes:
# a hex run of 32+ (API keys, tokens, hashes) and an explicit
# KEY=/TOKEN=/SECRET= assignment. This is deliberately farm-out-local —
# no other hook in this repo interpolates raw command text.
scrub_secrets() {  # stdin → stdout
  sed -E -e 's/[A-Fa-f0-9]{32,}/[REDACTED]/g' \
         -e 's/([A-Za-z0-9_]*(KEY|TOKEN|SECRET)=)[^[:space:]]+/\1[REDACTED]/g'
}

deny_reason() {  # $1=class $2=role
  # Scrub BEFORE truncating: truncating first can split a hex run below the
  # 32-char threshold and leak a prefix.
  local safe; safe=$(printf '%s' "$FLAT" | scrub_secrets | cut -c1-120)
  printf '%s' "farm-out policy: this is a long-running $1-class command; it must not run on the orchestrator thread (a stuck orchestrator is unavailable and cannot process subagent completions — this protects your own context budget). Dispatch it instead: Agent(subagent_type: $2, prompt carrying the command from this tool call): $safe — scrubbed and truncated for the log; the agent returns the result summary. If this genuinely cannot be dispatched (needs this session's state), re-run prefixed FARM_OUT_ALLOW=1 — the override is sanctioned and audited."
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
  # Patterns match mid-command by design: the (^|[;&| ]) anchor and the
  # ([;&| ]|$) terminator let a tier-1 token be found after a separator
  # (`true ; npm install`, `bash test.sh; echo done`) while a substring
  # inside a word (`echo remake`) never matches. A short (<3-segment) chain
  # that carries a tier-1 token thus denies here on purpose; the ≥3-segment
  # &&-chain is a separate arm (class=chain) reached only when this one skips.
  if printf '%s' "$c" | grep -qE '(^|[;&| ])bash +([^ ]*/)?(test\.sh|tests/run\.sh)([;&| ]|$)|(^|[;&| ])bash +[^ ]+\.test\.sh([;&| ]|$)|^(npm|pnpm|yarn) +test([;&| ]|$)|^pytest([;&| ]|$)|^go +test([;&| ]|$)|^cargo +test([;&| ]|$)|^make +test([;&| ]|$)'; then
    CLASS="suite"; ROLE="test-runner"; return 0; fi
  # Command position only: start-of-command or after a real separator
  # (;|&), optionally via a bash/sh runner. A bare space is NOT a
  # separator here — `ls claude-bootstrap.sh` reads the script, it does
  # not run it (2026-07-22 false-positive fix).
  if printf '%s' "$c" | grep -qE '(^|[;&|] ?)(bash +|sh +)?([^ ]*/)?claude-(bootstrap|reset)\.sh([;&| ]|$)'; then
    CLASS="bootstrap"; ROLE="implementor"; return 0; fi
  if printf '%s' "$c" | grep -qE '(^|[;&| ])(npm|pnpm|yarn) +(install|add|ci)([;&| ]|$)|(^|[;&| ])pip3? +install([;&| ]|$)|(^|[;&| ])uv +(sync|pip)([;&| ]|$)|(^|[;&| ])brew +install([;&| ]|$)'; then
    CLASS="install"; ROLE="implementor"; return 0; fi
  # `make clean` is trivial → stays silent; `make test` already classified suite
  # above. Every other `make`/`make <target>` is tier-1 build. ERE has no negative
  # lookahead, so the clean exemption is a guard rather than baked into the pattern.
  case "$c" in "make clean"|"make clean "*) return 1 ;; esac
  if printf '%s' "$c" | grep -qE '(^|[;&| ])(npm|pnpm|yarn) +run +build([;&| ]|$)|(^|[;&| ])cargo +build([;&| ]|$)|(^|[;&| ])go +build([;&| ]|$)|(^|[;&| ])docker +build([;&| ]|$)|(^|[;&| ])make( +[^ ]+)?([;&| ]|$)'; then
    CLASS="build"; ROLE="implementor"; return 0; fi
  return 1
}

emit_tier1() {  # $1=class $2=role — deny, or downgrade to a nudge under advisory
  if [ "$MODE" = "advisory" ]; then
    log_event "deny-downgraded" "$1"; emit_nudge "$1" "$2"; exit 0
  fi
  log_event "deny" "$1"; emit_deny "$1" "$2"; exit 0
}

classify_tier2() {  # $1=flat cmd → sets CLASS ROLE, rc 0 on match
  local c="$1"
  if printf '%s' "$c" | grep -qE '^git +clone([;&| ]|$)'; then CLASS="clone"; ROLE="implementor"; return 0; fi
  if printf '%s' "$c" | grep -qE '^docker +(run|pull)([;&| ]|$)'; then CLASS="docker-run"; ROLE="implementor"; return 0; fi
  if printf '%s' "$c" | grep -qE '^(npx|uvx) +'; then CLASS="pkg-exec"; ROLE="implementor"; return 0; fi
  return 1
}

nudge_once() {  # $1=class $2=role — ONE nudge per (session, class); repeat = suppressed
  local state="$PROJECT_DIR/.bionic/tmp/farm-out.state"
  mkdir -p "$PROJECT_DIR/.bionic/tmp" 2>/dev/null
  if [ -f "$state" ] && grep -qF "$SESSION_ID	$1" "$state" 2>/dev/null; then
    log_event "suppressed" "$1"; return 0
  fi
  printf '%s\t%s\n' "$SESSION_ID" "$1" >> "$state" 2>/dev/null || true
  log_event "nudge" "$1"; emit_nudge "$1" "$2"; return 0
}

# ── main flow: override → unwrap → tier-1 deny → tier-2 nudge (single + chain) ──
case "$FLAT" in
  "FARM_OUT_ALLOW=1 "*|"env FARM_OUT_ALLOW=1 "*)
    log_event "override" "user-sanctioned"; exit 0 ;;
esac

TARGET=$(unwrap "$(strip_prefixes "$FLAT")")
CLASS=""; ROLE=""

# Chain segmentation (≥3 &&-joined segments) feeds both chain arms below;
# compute the segment list once. Empty/0 when no `&&` is present.
CHAIN_SEGS=""; CHAIN_COUNT=0
case "$FLAT" in
  *"&&"*)
    CHAIN_SEGS=$(printf '%s' "$FLAT" | awk '{ gsub(/&&/, "\n"); print }')
    CHAIN_COUNT=$(printf '%s\n' "$CHAIN_SEGS" | grep -cE '[^[:space:]]')
    ;;
esac

# Tier-1 single command → deny (advisory-downgrades to a nudge inside emit_tier1).
# A ≥3-segment && chain defers to the chain tier-1 arm below so it keeps its
# class=chain label: now that install/build share the suite/bootstrap segment
# anchoring, an unguarded single-command match would relabel those chains.
if [ "${CHAIN_COUNT:-0}" -lt 3 ] && classify_tier1 "$TARGET"; then
  emit_tier1 "$CLASS" "$ROLE"
fi

# Chain tier-1 arm: ANY stripped/unwrapped segment matches tier-1 → deny as
# class=chain, role taken from the matching segment.
if [ "${CHAIN_COUNT:-0}" -ge 3 ]; then
  CHAIN_ROLE=""
  while IFS= read -r _seg; do
    _seg=$(printf '%s' "$_seg" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    [ -n "$_seg" ] || continue
    if classify_tier1 "$(unwrap "$(strip_prefixes "$_seg")")"; then
      CHAIN_ROLE="$ROLE"; break
    fi
  done <<EOF
$CHAIN_SEGS
EOF
  [ -n "$CHAIN_ROLE" ] && emit_tier1 "chain" "$CHAIN_ROLE"
fi

# Tier-2 single command → nudge once per (session, class).
if classify_tier2 "$TARGET"; then
  nudge_once "$CLASS" "$ROLE"; exit 0
fi

# Chain tier-2 arm: ≥3 segments, NO tier-1 segment (the tier-1 arm above would
# have exited otherwise), ≥1 non-exempt segment → nudge as class=chain.
if [ "${CHAIN_COUNT:-0}" -ge 3 ]; then
  _has_nonexempt=""
  while IFS= read -r _seg; do
    _seg=$(printf '%s' "$_seg" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    [ -n "$_seg" ] || continue
    printf '%s' "$_seg" | grep -qE '^(git|ls|cat|head|tail|wc|grep|rg|find|awk|sed|mkdir|cp|mv|rm|touch|echo|printf|test|cd|pwd|which|command|true|false) ' \
      || { _has_nonexempt=1; break; }
  done <<EOF
$CHAIN_SEGS
EOF
  [ -n "$_has_nonexempt" ] && { nudge_once "chain" "implementor"; exit 0; }
fi

exit 0
