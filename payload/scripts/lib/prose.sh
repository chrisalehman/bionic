#!/bin/bash
# payload/scripts/lib/prose.sh — THE PROSE LIST, the one answer to "is this path prose".
#
# A commit whose every path is prose owes no reading and no suite: the regression floor excuses it, every
# review chain covers it, and the dispatch wall admits a row that lands on no suite only when its files are
# prose. Those readers ask this file and hold no list of their own, so one path never reads prose at one of
# them and code at another.
#
#   prose_list <tree>         the list: the built-in paths, then the project's `prose:` entries, one per line
#   prose_path <path> <list>  0 when <path> is prose by <list>, 1 otherwise
#
# THE BUILT-IN PATHS are the project's record and its notes, which no suite executes: CHANGELOG.md,
# README.md and CLAUDE.md at the root, anything under .bionic/ or .claude/rules/, and the runner's timing table
# tests/timing.tsv. They are never skills/ or agents/ prose, which agents execute, and never a payload/ file; a
# README or CHANGELOG deeper than the root is not in them either. Nothing else under tests/ is: tests/run.sh and
# tests/lib/ are code the suites execute.
#
# THE PROJECT'S ENTRIES are the `prose:` line of <tree>/.bionic/config.yaml, a comma list on one line (the
# config reader reads one scalar per key), each an exact repo-relative path or a `dir/` prefix. An entry is
# taken as written: one that names a code path excuses that path from its suites, and the whole run at the
# release head stands behind it, as it does for CHANGELOG.md.
#
# READ THE LIST ONCE PER WALK. `prose_list` forks the config reader; `prose_path` forks nothing, so a walk
# reads the list before its loop and asks the predicate per path.
#
# Its one dependency is lib/roots.sh's `config_value`, sourced beside this file when a caller has not loaded it,
# so the file loads on its own. FUNCTIONS ONLY — nothing runs at source time and nothing here prints on load.
#
# [WALL: tests/bash-walls-egd.test.sh]

prose_list() {
  local tree="${1:-.}" raw e d
  printf '%s\n' CHANGELOG.md README.md CLAUDE.md '.bionic/*' '.claude/rules/*' tests/timing.tsv
  if ! declare -F config_value >/dev/null 2>&1; then
    d="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P)"
    # shellcheck source=/dev/null
    . "$d/roots.sh" >/dev/null 2>&1
  fi
  declare -F config_value >/dev/null 2>&1 || return 0
  raw="$(config_value "$tree" prose "")"
  while [ -n "$raw" ]; do
    e="${raw%%,*}"
    if [ "$e" = "$raw" ]; then raw=""; else raw="${raw#*,}"; fi
    e="${e#"${e%%[![:space:]]*}"}"; e="${e%"${e##*[![:space:]]}"}"
    [ -z "$e" ] || printf '%s\n' "$e"
  done
}

# An entry ending in `/` is a directory prefix; any other matches its exact path, and one holding a glob character is
# also a pattern (the built-in `.bionic/*`, whose `*` spans directories as a case pattern does). Pure parameter
# expansion, so a walk pays no fork per path.
prose_path() {
  local p="$1" rest="${2:-}" e
  [ -n "$p" ] || return 1
  while [ -n "$rest" ]; do
    e="${rest%%$'\n'*}"
    if [ "$e" = "$rest" ]; then rest=""; else rest="${rest#*$'\n'}"; fi
    case "$e" in
      '') ;;
      */) [ "${p#"$e"}" = "$p" ] || return 0 ;;
      *)
        [ "$p" != "$e" ] || return 0
        case "$e" in
          *[*?[]*)
            # shellcheck disable=SC2254
            case "$p" in $e) return 0 ;; esac ;;
        esac ;;
    esac
  done
  return 1
}
