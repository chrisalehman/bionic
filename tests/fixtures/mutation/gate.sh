#!/bin/bash
# Fixture enforcer for the mutation harness: two blocking paths plus advisory
# output. The advisory line is what lets a non-discriminating test look green.
#
# The class marker claiming this enforcer lives in the fixture SURFACES
# (discriminating.md / nondiscriminating.md), not here — these fixtures exercise
# the harness and are not part of the governed surface set.
echo "gate v1"
if [ "${1:-}" = "block" ]; then
  echo "BLOCKED: gate" >&2
  exit 2
fi
if [ "${1:-}" = "force" ]; then
  echo "BLOCKED: force" >&2
  exit 2
fi
exit 0
