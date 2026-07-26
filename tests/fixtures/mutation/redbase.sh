#!/bin/bash
# Fixture enforcer whose pointed-at test is already failing. It blocks, so there
# is something to mutate; the defect is on the test side.
if [ "${1:-}" = "block" ]; then
  exit 2
fi
exit 0
