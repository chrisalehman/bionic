#!/bin/bash
# Fixture enforcer using the SECOND blocking mechanism: a permissionDecision
# deny payload rather than exit 2. Both mechanisms must be mutable, or the
# harness proves nothing about the hooks that use this one.
if [ "${1:-}" = "block" ]; then
  printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"fixture"}}'
  exit 0
fi
exit 0
