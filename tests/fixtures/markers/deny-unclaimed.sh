#!/bin/bash
# Fixture hook: the JSON deny mechanism, with no marker claiming it.
jq -n '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:"fixture"}}'
exit 0
