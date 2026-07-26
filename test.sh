#!/usr/bin/env bash
#
# test.sh — convenience entry point. The real runner is tests/run.sh.
#
# Until epic-11 W3 this file hand-listed 8 suites and silently omitted
# agent-roles, installer-behavior, marker-verify and marker-discriminates: it
# reported "All suites passed" while never running a third of the floor. Two
# runners for one quantity, disagreeing. Now there is one, and this delegates
# to it so `./test.sh` cannot drift out of sync again.
#
# Usage: ./test.sh
#
set -euo pipefail

exec bash "$(cd "$(dirname "$0")" && pwd)/tests/run.sh" "$@"
