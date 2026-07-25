#!/usr/bin/env bash
#
# tests/metrics.sh — re-runnable harness-weight measurement.
#
# Emits one TSV row per metric: <key>\t<value>\t<unit>. Designed to be run at
# any point in epic-11 so waves compare like with like: the SCRIPT is the
# durable artifact, snapshots are reproducible rather than trusted.
#
#   bash tests/metrics.sh                 # human/TSV to stdout
#   bash tests/metrics.sh > before.tsv    # snapshot for a before/after diff
#   diff before.tsv <(bash tests/metrics.sh)
#
# Every metric is bound to the epic-11 acceptance criterion that consumes it
# (see .bionic/docs/specs/epic-11-harness-fitness/epic.spec.md). Metrics that
# cannot be measured on this machine emit `n/a` rather than 0 — a missing
# plugin cache must never read as "already subtracted".
#
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

emit() { printf '%s\t%s\t%s\n' "$1" "$2" "$3"; }

# Bytes/lines/words of a file, or n/a when absent.
measure_file() { # $1=key-prefix $2=path
  if [ -f "$2" ]; then
    emit "$1.bytes" "$(wc -c <"$2" | tr -d ' ')" bytes
    emit "$1.lines" "$(wc -l <"$2" | tr -d ' ')" lines
  else
    emit "$1.bytes" n/a bytes
    emit "$1.lines" n/a lines
  fi
}

# ── AC-2: always-on session context ────────────────────────────────────────
# VoltAgent subagent descriptions load into every session's system prompt.
VOLT="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/cache/voltagent-subagents"
if [ -d "$VOLT" ]; then
  emit voltagent.agent_files "$(find "$VOLT" -name '*.md' | wc -l | tr -d ' ')" files
  emit voltagent.description_chars \
    "$(find "$VOLT" -name '*.md' -exec awk '/^description:/{print; exit}' {} \; | wc -c | tr -d ' ')" chars
else
  emit voltagent.agent_files n/a files
  emit voltagent.description_chars n/a chars
fi

# Config-declared install surface (what bootstrap would install).
if [ -f claude-config.txt ]; then
  emit config.plugins     "$(grep -cE '^plugin[[:space:]]*\|' claude-config.txt)" entries
  emit config.marketplaces "$(grep -cE '^marketplace[[:space:]]*\|' claude-config.txt)" entries
  emit config.mcp_servers "$(grep -cE '^mcp-server[[:space:]]*\|' claude-config.txt)" entries
fi

# Terseness duplication: the same rules in standing context AND per-turn hook.
emit terseness.in_global_memory \
  "$(grep -c '^## Terseness' claude-global.md 2>/dev/null || echo 0)" sections
emit terseness.hook_present \
  "$([ -f hooks/terseness-reminder.sh ] && echo 1 || echo 0)" bool

# Dangling references to machinery that no longer exists.
emit dangling.sdlc_poker_refs \
  "$(grep -rl 'sdlc-poker\.sh' hooks/ 2>/dev/null | wc -l | tr -d ' ')" files

# ── AC-4: memory footprint ─────────────────────────────────────────────────
measure_file memory.index   .bionic/memory/INDEX.md
measure_file memory.context .bionic/memory/context.md
if [ -f .bionic/memory/INDEX.md ]; then
  emit memory.index_bullets "$(grep -cE '^- ' .bionic/memory/INDEX.md)" bullets
fi
if [ -d .bionic/memory ]; then
  emit memory.topical_files "$(find .bionic/memory -name '*.md' | wc -l | tr -d ' ')" files
  emit memory.total_bytes "$(find .bionic/memory -name '*.md' -exec cat {} + | wc -c | tr -d ' ')" bytes
fi

# ── AC-5: canonical-sdlc prose weight and normative density ────────────────
SKILL=skills/canonical-sdlc/SKILL.md
measure_file skill.canonical_sdlc "$SKILL"
if [ -f "$SKILL" ]; then
  emit skill.canonical_sdlc.words "$(wc -w <"$SKILL" | tr -d ' ')" words
  # Normative statements: the conversion candidates for W4.
  # NOTE: `grep -c` counts matching LINES and silently overrides -o. These are
  # true occurrence counts (grep -o | wc -l), case-insensitive, so a line
  # carrying three NEVERs counts three. Getting this wrong understates the
  # conversion surface by an order of magnitude.
  norm() { grep -oiE "$1" "$SKILL" | wc -l | tr -d ' '; }
  emit skill.norm.never     "$(norm '\bnever\b')" occurrences
  emit skill.norm.must      "$(norm '\bmust\b')" occurrences
  emit skill.norm.always    "$(norm '\balways\b')" occurrences
  emit skill.norm.mandatory "$(norm '\bmandator(y|ily)\b')" occurrences
  emit skill.norm.total     "$(norm '\b(never|must|always|mandator(y|ily))\b')" occurrences
fi
measure_file skill.canonical_sdlc_readme skills/canonical-sdlc/README.md

# ── Hook implementation weight (the enforcement surface W4 extends) ────────
hook_total=0
for h in hooks/*.sh; do
  [ -f "$h" ] || continue
  case "$h" in *.test.sh) continue ;; esac
  n=$(wc -l <"$h" | tr -d ' ')
  emit "hook.$(basename "$h" .sh).lines" "$n" lines
  hook_total=$((hook_total + n))
done
emit hook.total_lines "$hook_total" lines

# ── Bootstrap containment (AC-8: what W7 must relocate) ────────────────────
if [ -f claude-bootstrap.sh ]; then
  emit bootstrap.hardcoded_claude_home \
    "$(grep -cE '~/\.claude|\$HOME/\.claude' claude-bootstrap.sh)" refs
  emit bootstrap.config_dir_aware \
    "$(grep -c 'CLAUDE_CONFIG_DIR' claude-bootstrap.sh)" refs
fi
