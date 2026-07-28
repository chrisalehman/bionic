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

# Occurrence count, NOT line count. `grep -c` counts matching LINES and
# silently overrides -o, so a line carrying three matches reports one. Every
# metric whose unit is "occurrences"/"refs" must route through here.
# (Audit finding, epic-11 W1: the same bug was fixed once at the normative
# counters and left standing at the bootstrap counters, understating W7's
# relocation baseline by 5.)
count() { grep -oE "$1" "$2" 2>/dev/null | wc -l | tr -d ' '; }

# Line count where LINES are genuinely the unit. Never pair with `|| echo 0`:
# `grep -c` prints 0 AND exits 1 on no-match, so the fallback fires too and
# emits a malformed two-line record. (Audit finding, epic-11 W1 — dormant only
# because the heading still existed; it would have fired in W2.)
count_lines() { grep -cE "$1" "$2" 2>/dev/null; }

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
# ENABLEMENT is the metric that matters, not disk presence. A plugin's cache
# directory can persist long after the plugin is uninstalled — orphaned bytes
# cost zero context. Measuring the cache is a PROXY that cannot see the thing
# this wave claims: whether the descriptions still load into the system prompt.
# (Found the hard way, epic-11 W1: after a real uninstall the cache-based
# metrics still reported 108/101/20464 for packs that were already gone.)
SETTINGS="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
if [ -f "$SETTINGS" ]; then
  emit voltagent.enabled_plugins \
    "$(grep -o '"voltagent-[a-z-]*@[^"]*": *true' "$SETTINGS" 2>/dev/null | wc -l | tr -d ' ')" plugins
else
  emit voltagent.enabled_plugins n/a plugins
fi

# Cache-on-disk, retained ONLY as a housekeeping signal. These are NOT the
# context cost — an enabled_plugins of 0 means zero tokens regardless of what
# these report. Never cite them as evidence of a context reduction.
if [ -d "$VOLT" ]; then
  emit voltagent.cached_md_files "$(find "$VOLT" -name '*.md' | wc -l | tr -d ' ')" files
  emit voltagent.cached_agent_definitions \
    "$(find "$VOLT" -name '*.md' -exec grep -l '^description:' {} \; | wc -l | tr -d ' ')" agents
  emit voltagent.cached_description_chars \
    "$(find "$VOLT" -name '*.md' -exec awk '/^description:/{sub(/^description:[[:space:]]*/,""); print; exit}' {} \; | wc -c | tr -d ' ')" chars
else
  emit voltagent.cached_md_files           n/a files
  emit voltagent.cached_agent_definitions  n/a agents
  emit voltagent.cached_description_chars  n/a chars
fi

# Config-declared install surface (what bootstrap would install).
if [ -f claude-config.txt ]; then
  emit config.plugins      "$(count_lines '^plugin[[:space:]]*\|' claude-config.txt)" entries
  emit config.marketplaces "$(count_lines '^marketplace[[:space:]]*\|' claude-config.txt)" entries
  emit config.mcp_servers  "$(count_lines '^mcp-server[[:space:]]*\|' claude-config.txt)" entries
else
  emit config.plugins      n/a entries
  emit config.marketplaces n/a entries
  emit config.mcp_servers  n/a entries
fi

# Dangling references to machinery that no longer exists.
emit dangling.sdlc_poker_refs \
  "$(grep -rl 'sdlc-poker\.sh' hooks/ 2>/dev/null | wc -l | tr -d ' ')" files

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
else
  emit skill.canonical_sdlc.words n/a words
  emit skill.norm.never     n/a occurrences
  emit skill.norm.must      n/a occurrences
  emit skill.norm.always    n/a occurrences
  emit skill.norm.mandatory n/a occurrences
  emit skill.norm.total     n/a occurrences
fi

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
  # OCCURRENCES, not lines — this is W7's relocation baseline. A line carrying
  # two `~/.claude` refs is two refs of work, not one.
  emit bootstrap.hardcoded_claude_home \
    "$(count '~/\.claude|\$HOME/\.claude' claude-bootstrap.sh)" refs
  emit bootstrap.config_dir_aware \
    "$(count 'CLAUDE_CONFIG_DIR' claude-bootstrap.sh)" refs
else
  emit bootstrap.hardcoded_claude_home n/a refs
  emit bootstrap.config_dir_aware      n/a refs
fi
