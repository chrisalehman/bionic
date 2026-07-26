#!/bin/bash
# Fixture hook: a blocking path with a marker that claims it.
# The push must not proceed. [WALL: tests/fixtures/markers/claimed-block.test.sh]
if [ "${1:-}" = "block" ]; then
  echo "BLOCKED" >&2
  exit 2
fi
exit 0
