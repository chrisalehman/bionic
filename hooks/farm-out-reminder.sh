#!/bin/bash
# FARM-OUT: tiered PreToolUse(Bash) enforcement — long-running main-thread
# commands DENY with a redirect to the right role; fuzzy production-shaped
# commands get ONE additionalContext nudge per class per session; every
# tier-1/tier-2 event logs one line to
# $HOME/.claude/logs/<project-slug>/sdlc-audit.md — outside every consuming
# project tree (incident 0001) — via audit_path() (log_finding() shape, own
# copy — deliberate per-hook duplication).
#
# Exit 0 on EVERY path. Enforcement lives in stdout JSON only:
#   deny  → hookSpecificOutput.permissionDecision "deny" + redirect reason
#   nudge → hookSpecificOutput.additionalContext
# Never "allow", never updatedInput, never exit 2 (epic-08 wave-04 ADR-002;
# amends D14 per user ratification 2026-07-20).
# [UNENFORCED]
#
# Thread discrimination (epic-08 Q1 spike + hooks docs): agent_type
# non-empty → subagent → silent. Missing keys classify as MAIN THREAD.
# Registered in skills/canonical-sdlc/SKILL.md frontmatter; live only while that skill is armed.

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

# Incident 0001: the audit stream must live where a consuming project cannot
# commit it, regardless of that project's .gitignore. $HOME-rooted, per-project,
# durable — the same $HOME/.claude/ audit path the archived epic-10 poker used
# (that work is recoverable at tag archive/epic-10-never-die).
# Slug = <basename>-<cksum of the absolute path>: readable, deterministic, and
# collision-resistant across same-named projects under different parents.
# cksum and basename are POSIX — no new dependency.
# [INSTRUMENT]
audit_path() {  # $1=project root → absolute audit-file path; rc 1 if no $HOME
  [ -n "${HOME:-}" ] || return 1
  local base sum
  base=$(basename "$1" | sed 's/[^A-Za-z0-9._-]/-/g')
  sum=$(printf '%s' "$1" | cksum | cut -d' ' -f1)
  printf '%s/.claude/logs/%s-%s/sdlc-audit.md' "$HOME" "$base" "$sum"
}

log_event() {  # $1=event $2=class
  # No command-derived text: `class=<c> mode=<m>` is the complete payload.
  # A length bound is not a sanitizer — incident 0001 leaked a live credential
  # through the former `cut -c1-120` excerpt of the raw command.
  local f
  if f=$(audit_path "$PROJECT_DIR"); then
    local line="- $(date -u +%Y-%m-%dT%H:%M:%SZ) farm-out $1: class=$2 mode=$MODE"
    mkdir -p "$(dirname "$f")" 2>/dev/null && printf '%s\n' "$line" >> "$f" 2>/dev/null
  fi
  echo "farm-out [$1] class=$2" >&2
  return 0
}

# [WALL: tests/farm-out-reminder.test.sh]
emit_deny() {  # $1=class $2=role
  jq -n --arg r "$(deny_reason "$1" "$2")" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}' 2>/dev/null
  return 0
}

emit_nudge() {  # $1=class $2=role
  jq -n --arg c "farm-out checkpoint: $1-class command on the main thread — production-shaped work belongs in a subagent. Fix: dispatch via Agent(subagent_type: $2) when you can. This protects your own context budget; a stuck orchestrator cannot process completions. Advisory only." \
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
  printf '%s' "farm-out checkpoint: this $1-class command doesn't belong on the orchestrator thread (a stuck orchestrator is unavailable and cannot process subagent completions — this protects your own context budget). Fix: dispatch it — Agent(subagent_type: $2, prompt carrying the command from this tool call): $safe — scrubbed and truncated for the log; the agent returns the result summary. If this genuinely cannot be dispatched (needs this session's state), re-run prefixed FARM_OUT_ALLOW=1 — the override is sanctioned and audited."
}

# ── classification (B-5: argv positions, read by scripts/lib/cmd-class.sh) ───────
# override check + wrapper unwrap precede classification.

# The sed twins that used to live here — strip_prefixes() and unwrap() — are
# GONE (review-b B-4a). They were hand-rolled copies of the library's
# strip_leading()/unwrap_runner() with their own smaller rule set: the prefix
# strip knew only `env`, `FARM_OUT_*=`, `nohup` and `timeout <n>`, so a `sudo`,
# a `time`, an `xargs` or an ordinary `FOO=1` left the wrapper sitting at
# argv[0] and the tier-2 matcher below never fired. Tier-2 now reads
# cmd_unwrap_head, which is the same reduction cmd_class itself performs — one
# reader, one set of rules, and the R-12 superset applies to the nudge tier too.
# [WALL: tests/cmd-class.test.sh]

role_for_class() {  # $1=class → the role a redirect names
  case "$1" in suite) printf 'test-runner' ;; *) printf 'implementor' ;; esac
}

classify_tier1() {  # $1=command text → sets CLASS ROLE, rc 0 on match
  # ONE READER, argv-positional (payload/scripts/lib/cmd-class.sh). The regex classifier
  # this replaced matched mid-string after any space, so `make( +[^ ]+)?` denied
  # `git commit -m "make the row green"` as class=build and a heredoc body carrying
  # `bash tests/run.sh` denied as class=suite — both measured, research-b3 §2. Prose,
  # quoted strings and heredoc bodies are never argv[0], so they no longer classify.
  # A short (<3-segment) chain that carries a tier-1 command still denies here on
  # purpose; the ≥3-segment chain is a separate arm (class=chain) reached only when
  # this one skips.
  # [WALL: tests/cmd-class.test.sh]
  local c
  c=$(cmd_class "$1")
  [ "$c" = "none" ] && return 1
  CLASS="$c"; ROLE=$(role_for_class "$c")
  return 0
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
# Chain-aware: the override token is honored ANYWHERE in the invocation —
# leading, after a separator (;/&/|), or as an env-prefix mid-chain
# (`cd x && FARM_OUT_ALLOW=1 bash tests/run.sh`) — not only in leading
# position. W4's false fire was exactly this shape: a 2-segment &&-chain hit
# the single-command tier-1 arm before the old leading-only case ever ran.
if printf '%s' "$FLAT" | grep -qE '(^|[;&| ])FARM_OUT_ALLOW=1([;&| ]|$)'; then
  log_event "override" "user-sanctioned"; exit 0
fi

# ── the command reader, sourced FAIL-CLOSED (design D1, Chris 2026-08-30) ────────
#
# A wall that cannot classify REFUSES; it never waves work through. The sanctioned
# bypass is checked above this line and still works, because the override is a human
# saying "I know" and must not depend on a file being present.
#
# TWO SPELLINGS OF ONE DIRECTORY. payload/hooks is a symlink to <repo>/hooks and `$0`
# is textual, so "../scripts/lib" resolves only when the harness reached this file
# through ${CLAUDE_PLUGIN_ROOT}/hooks/. The repo spelling is the second candidate.
# Both land on payload/scripts/lib/cmd-class.sh — tests/cmd-class.test.sh §C6 pins it.
CMD_CLASS_LIB_WANT="$(dirname "$0")/../scripts/lib/cmd-class.sh"
CMD_CLASS_LIB=""
for _cand in "$CMD_CLASS_LIB_WANT" "$(dirname "$0")/../payload/scripts/lib/cmd-class.sh"; do
  # -r, not -f (review-b B-4c): readability is what predicts whether `.` succeeds.
  [ -r "$_cand" ] && { CMD_CLASS_LIB="$_cand"; break; }
done
if [ -z "$CMD_CLASS_LIB" ] || ! . "$CMD_CLASS_LIB"; then
  _unreadable="farm-out checkpoint: this wall cannot read commands — its classifier failed to load ($CMD_CLASS_LIB_WANT). A wall that cannot classify refuses rather than waving work through. Fix: restore payload/scripts/lib/cmd-class.sh or re-install the plugin; if you must proceed now, re-run prefixed FARM_OUT_ALLOW=1 — the override is sanctioned and audited."
  log_event "deny" "unreadable"
  if [ "$MODE" = "advisory" ]; then
    jq -n --arg c "$_unreadable" \
      '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$c}}' 2>/dev/null
  else
    jq -n --arg r "$_unreadable" \
      '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}' 2>/dev/null
  fi
  exit 0
fi

# The heredoc-free form of the command. Chain segmentation and the tier-2 matcher read
# it rather than FLAT, so a `&&` or an `npx` inside a heredoc body cannot reshape the
# decision any more than it can classify.
SAFE_FLAT=$(cmd_strip_heredocs "$CMD" \
  | awk '{ sub(/\r$/, ""); gsub(/\r/, "\n"); print }' | tr '\n' ' ' \
  | sed 's/[[:space:]]\{1,\}/ /g; s/^ //; s/ $//')

TARGET=$(cmd_unwrap_head "$SAFE_FLAT")
CLASS=""; ROLE=""

# Chain segmentation (≥3 &&-joined segments) feeds both chain arms below;
# compute the segment list once. Empty/0 when no `&&` is present.
CHAIN_SEGS=""; CHAIN_COUNT=0
case "$SAFE_FLAT" in
  *"&&"*)
    CHAIN_SEGS=$(printf '%s' "$SAFE_FLAT" | awk '{ gsub(/&&/, "\n"); print }')
    CHAIN_COUNT=$(printf '%s\n' "$CHAIN_SEGS" | grep -cE '[^[:space:]]')
    ;;
esac

# Tier-1 single command → deny (advisory-downgrades to a nudge inside emit_tier1).
# A ≥3-segment && chain defers to the chain tier-1 arm below so it keeps its
# class=chain label: now that install/build share the suite/bootstrap segment
# anchoring, an unguarded single-command match would relabel those chains.
if [ "${CHAIN_COUNT:-0}" -lt 3 ] && classify_tier1 "$CMD"; then
  emit_tier1 "$CLASS" "$ROLE"
fi

# Chain tier-1 arm: ANY stripped/unwrapped segment matches tier-1 → deny as
# class=chain, role taken from the matching segment.
if [ "${CHAIN_COUNT:-0}" -ge 3 ]; then
  CHAIN_ROLE=""
  while IFS= read -r _seg; do
    _seg=$(printf '%s' "$_seg" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    [ -n "$_seg" ] || continue
    if classify_tier1 "$_seg"; then
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
