#!/bin/bash
# TERSENESS-REMINDER: UserPromptSubmit hook that re-asserts terseness
# rules every turn to fight drift.
#
# Why per-turn: CLAUDE.md is loaded once at session start. As context
# grows and other skills inject competing instructions, the terseness
# baseline gets diluted. This hook keeps it visible in the model's
# attention every turn.
#
# Disable mid-session: `touch ~/.claude/.bionic-terse-off`
# Re-enable: `rm ~/.claude/.bionic-terse-off`
#
# Failure mode: silent. If jq is missing or the script errors, no
# context is injected — the user's session is never broken by this hook.
#
# Installed globally by claude-bootstrap.sh to ~/.claude/hooks/

set -u

# Flag file lets the user disable without restarting Claude Code.
if [ -f "$HOME/.claude/.bionic-terse-off" ]; then
  exit 0
fi

# Consume and discard stdin. UserPromptSubmit hooks receive the prompt
# JSON, but the reinforcement is unconditional — payload-independent.
cat >/dev/null

# Emit per-turn reinforcement. Reference CLAUDE.md rather than restate
# the full ruleset — keeps payload <1000 chars (up from an earlier <500
# cap) to bound per-turn overhead. The increase is deliberate: this hook
# used to govern phrasing only (HOW things are said). It now also governs
# content selection (WHAT gets said and escalated) — the expensive
# failure mode phrasing rules never addressed — so the payload carries a
# classify-before-asking heuristic and an anti-narration clause on top of
# the original terseness rules.
#
# The EXEMPT clause is load-bearing: without it, terseness corrupts the
# structured output that canonical-sdlc, code-review-and-quality, and
# writing-plans depend on. The paired .test.sh asserts these tokens are
# present so a future "cleanup" cannot silently remove them.
jq -nc --arg ctx "TERSENESS: apply CLAUDE.md terseness rules. Lead with the answer or action. No preamble (no 'Sure', 'I'll', 'Let me'). No trailing summary. Drop hedging unless load-bearing. Match length to question shape. Don't narrate reasoning — execute, show progress, escalate only what needs a human. BEFORE ASKING FOR ANYTHING, classify it: an action you have tools for, and that isn't on the approval list (pushes to main, destructive migrations, secrets, billing), you just do — don't ask. A decision: check whether standing principles auto-resolve it (elegant over expedient, simple over complex, right level over brute force, lower operational burden over higher); if they do, decide, proceed, and report the call in one line. EXEMPT (write normally): code, diffs, commit messages, evidence blocks, 5-axis review rubric, ADRs, plan/spec frontmatter, security warnings, anything a skill mandates structured output for." \
  '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $ctx}}'

exit 0
