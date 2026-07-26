#!/bin/bash
# Fixture hook: a blocking path that no marker claims.
if [ "${1:-}" = "block" ]; then
  echo "BLOCKED" >&2
  exit 2
fi
exit 0
