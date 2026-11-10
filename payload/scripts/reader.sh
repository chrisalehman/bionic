#!/bin/bash
# reader.sh — `reader <plan> <question> [args]`: the one program that reads a run's log and answers.
#
# A yes or no question answers by exit code alone (0 yes, 1 no); a value question prints `key=value`
# lines; a list question prints one `run/v1` line per item. An unknown question exits 2 and prints the
# list. The fold, the forms and the question table are lib/reader.sh's; this file only runs them.
#
# Executed, never sourced:  bash ${CLAUDE_PLUGIN_ROOT}/scripts/reader.sh <plan> <question> [args]

set -uo pipefail

case "${BASH_SOURCE[0]}" in */*) _reader_dir="${BASH_SOURCE[0]%/*}" ;; *) _reader_dir="." ;; esac
# shellcheck source=/dev/null
. "$(cd "$_reader_dir" && pwd -P)/lib/reader.sh" || exit 2
reader_main "$@"
