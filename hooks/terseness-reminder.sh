#!/bin/bash
# TERSENESS-REMINDER: UserPromptSubmit hook that re-asserts terseness
# rules every turn to fight drift.
#
# Class: [UNENFORCED]. It injects context and exits 0 — no `exit 2`, no
# deny payload, and nothing downstream reads the model's output back, so
# compliance is never checked. This hook nags; it does not bind.
#
# Why per-turn: CLAUDE.md is loaded once at session start. As context
# grows and other skills inject competing instructions, the terseness
# baseline gets diluted. This hook keeps it visible in the model's
# attention every turn.
#
# Scope: the payload compresses the `## Terseness` section of CLAUDE.md and
# nothing else — every other rule in that file lives there once. (epic-11 W2:
# a deployed-but-uncommitted payload had carried a copy of `## Before asking
# me for anything`; 89a26f9 replaced that section and the copy went stale.)
# The paired .test.sh pins this, but a unit test is not a wall: [UNENFORCED]
#
# Disable mid-session: `touch ~/.claude/.bionic-terse-off`
# Re-enable: `rm ~/.claude/.bionic-terse-off`
#
# Failure mode: silent. If jq is missing or the script errors, no
# context is injected — the user's session is never broken by this hook.
# True by construction (unconditional `exit 0`, no `set -e`), asserted for
# the default and disabled paths only, not under jq absence: [UNENFORCED]
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
# the full ruleset — keeps payload <500 chars to bound per-turn overhead.
#
# The EXEMPT clause is load-bearing: without it, terseness corrupts the
# structured output that canonical-sdlc, code-review-and-quality, and
# writing-plans depend on. The paired .test.sh asserts these tokens are
# present — token by token, and against claude-global.md's own exemption
# line — so neither a "cleanup" here nor a new exemption there can put the
# two out of step without going red. [UNENFORCED]
jq -nc --arg ctx "TERSENESS: apply CLAUDE.md terseness rules. Lead with the answer or action. No preamble (no 'Sure', 'I'll', 'Let me'). No trailing summary. Drop hedging unless load-bearing. Match length to question shape. EXEMPT (write normally): code, diffs, commit messages, evidence blocks, 5-axis review rubric, ADRs, plan/spec frontmatter, security warnings, anything a skill mandates structured output for." \
  '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $ctx}}'

exit 0
