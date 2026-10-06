# tests/lib/world.sh — the model world (wave-28 T1, D23): a planted machine, a movable clock,
# a planted cost record, a fixture repository with row trees, suites that end as told, and a
# verb log. The gate and the landing line are proved in it, never on this machine's own state.
#
#     . "$(dirname "$0")/lib/resolve-roots.sh"      # first, so BIONIC_SCRIPTS_DIR is set
#     trap cleanup EXIT                              # the suite's own trap, if it has one
#     . "$(dirname "$0")/lib/world.sh"               # after it: the world chains onto it
#
# THE SEVEN VERBS (the plan's interface row, verbatim in shape):
#
#   world_machine <cores> <total_mb> <used_pct> <busy_cores>   exports the readers' pins
#   world_clock <epoch>                                        plants the clock file
#   world_tick <seconds>                                       moves it forward
#   world_cost <key> <mem_pct> <cores> <seconds>               appends to cost/<key>
#   world_repo                                                 prints a fixture repo's root
#   world_suite <name> <green|red|none|kill>                   writes tests/<name>.test.sh
#   world_verbs                                                prints the verb log's path
#
# ONE DIRECTORY, MADE AT SOURCE TIME, REMOVED ON EXIT. `WORLD_ROOT` is a `mktemp -d` outside
# every checkout (refused if git finds a repository around it), and everything the world
# makes lives under it. It is made when this file is sourced, in the suite's own shell,
# because `world_repo` and `world_verbs` print paths and so run inside `$( )`: a directory
# or a trap made there would belong to that subshell and die with it. The EXIT trap is
# CHAINED onto the one the suite already set, never put in its place; a suite that sets its
# trap after sourcing this file calls `_world_cleanup` from it.
#
# THE ENVIRONMENT IT OWNS. Sourcing exports BIONIC_GATE_DIR (the world's gate store, so no
# ask or cost ever reaches the real home's), BIONIC_VERB_LOG and WORLD_SID (the session id
# the fixture repository's marker and roster are written under). A suite may override any of
# them after sourcing.
#
# bash 3.2 (ADR-001): no associative arrays, no `mapfile`, no BASHPID.

if [ -z "${BIONIC_SCRIPTS_DIR:-}" ]; then
  echo "world.sh: BIONIC_SCRIPTS_DIR is unset — source tests/lib/resolve-roots.sh first" >&2
  return 1 2>/dev/null || exit 1
fi
if ! type -t _res_now >/dev/null 2>&1; then
  # shellcheck source=/dev/null
  . "${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/resources.sh" || return 1
fi

WORLD_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/world.XXXXXX" 2>/dev/null)" \
  && WORLD_ROOT="$(cd "$WORLD_ROOT" && pwd -P)" || WORLD_ROOT=''
if [ -z "$WORLD_ROOT" ] || [ ! -d "$WORLD_ROOT" ]; then
  echo "world.sh: could not make the world's directory under ${TMPDIR:-/tmp}" >&2
  return 1 2>/dev/null || exit 1
fi
# A world inside a checkout would let a fixture's git act on a real repository (rule 12).
if git -C "$WORLD_ROOT" rev-parse --show-toplevel >/dev/null 2>&1; then
  echo "world.sh: $WORLD_ROOT lies inside a git checkout — set TMPDIR outside every checkout" >&2
  rm -rf "$WORLD_ROOT"
  return 1 2>/dev/null || exit 1
fi
export WORLD_ROOT
export WORLD_SID="11111111-2222-4333-8444-555555555555"
export BIONIC_GATE_DIR="$WORLD_ROOT/gate"
export BIONIC_VERB_LOG="$WORLD_ROOT/verbs.log"

_world_cleanup() {
  [ -n "${WORLD_ROOT:-}" ] || return 0
  case "$WORLD_ROOT" in
    */world.*) chmod -R u+rwX "$WORLD_ROOT" 2>/dev/null; rm -rf "$WORLD_ROOT" ;;
  esac
}

# Chain onto the suite's EXIT trap. `trap -p` is read through a file, not `$( )`, so the
# answer is this shell's own trap on every bash this runs under.
_world_chain_trap() {
  local f="$WORLD_ROOT/.trap" prev=''
  trap -p EXIT > "$f" 2>/dev/null
  if [ -s "$f" ]; then
    eval "set -- $(cat "$f")"
    prev="${3:-}"
  fi
  rm -f "$f"
  if [ -n "$prev" ]; then
    # shellcheck disable=SC2064  # the previous trap is expanded now, on purpose
    trap "_world_cleanup; $prev" EXIT
  else
    trap _world_cleanup EXIT
  fi
}
_world_chain_trap

_world_is_num() {  # a non-negative decimal: 3, 1.5
  case "${1:-}" in
    ''|.|*.*.*|*[!0-9.]*) return 1 ;;
    *) return 0 ;;
  esac
}

_world_refuse() {  # <verb> <message> -> rc 2
  printf '%s: %s\n' "$1" "$2" >&2
  return 2
}

# world_machine <cores> <total_mb> <used_pct> <busy_cores> — plants the machine every reader
# in payload/scripts/lib/resources.sh answers for. The four new pins carry the arguments; the
# older readers are planted to the SAME machine (free % = 100 − used, free MB = that share of
# total, load = busy cores, swap 0), so no reader in the world disagrees with another.
world_machine() {
  local cores="${1:-}" total="${2:-}" used="${3:-}" busy="${4:-}"
  _res_is_uint "$cores" && [ "$cores" -ge 1 ] \
    || { _world_refuse world_machine "cores must be a whole number ≥ 1, got '$cores'"; return 2; }
  _res_is_uint "$total" && [ "$total" -ge 1 ] \
    || { _world_refuse world_machine "total_mb must be a whole number ≥ 1, got '$total'"; return 2; }
  _res_is_uint "$used" && [ "$used" -le 100 ] \
    || { _world_refuse world_machine "used_pct must be 0 to 100, got '$used'"; return 2; }
  _world_is_num "$busy" \
    || { _world_refuse world_machine "busy_cores must be a decimal ≥ 0, got '$busy'"; return 2; }
  export BIONIC_PROBE_CORES="$cores" BIONIC_PROBE_TOTAL_MB="$total"
  export BIONIC_PROBE_USED_PCT="$used" BIONIC_PROBE_BUSY_CORES="$busy"
  export BIONIC_PROBE_FREE_PCT="$(( 100 - used ))"
  export BIONIC_PROBE_FREE_MB="$(( total * (100 - used) / 100 ))"
  export BIONIC_PROBE_LOAD_1M="$busy" BIONIC_PROBE_SWAP_PCT=0
}

# world_clock <epoch> — writes the clock file and points BIONIC_NOW_FILE at it. Every
# process started after this reads the same file, so `world_tick` moves them all.
world_clock() {
  _res_is_uint "${1:-}" || { _world_refuse world_clock "epoch must be a whole number, got '${1:-}'"; return 2; }
  printf '%s\n' "$1" > "$WORLD_ROOT/clock"
  export BIONIC_NOW_FILE="$WORLD_ROOT/clock"
}

# world_tick <seconds> — moves the planted clock forward. Refused with no clock planted: a
# tick on the real clock would be a sleep nobody asked for.
world_tick() {
  local now
  _res_is_uint "${1:-}" || { _world_refuse world_tick "seconds must be a whole number, got '${1:-}'"; return 2; }
  now="$(awk 'NR == 1 { print $1; exit }' "${BIONIC_NOW_FILE:-/nonexistent}" 2>/dev/null)"
  _res_is_uint "$now" || { _world_refuse world_tick "no clock is planted — call world_clock first"; return 2; }
  printf '%s\n' "$(( now + $1 ))" > "$BIONIC_NOW_FILE"
}

# world_cost <key> <mem_pct> <cores> <seconds> — appends `<mem>:<cores>:<seconds>:<epoch>` to
# the gate store's `cost/<key>`, the epoch read from `_res_now`, and keeps the newest three
# lines (the plan's cost row). The key is the file's name, so it may not hold a slash.
world_cost() {
  local key="${1:-}" f
  case "$key" in
    ''|*/*) _world_refuse world_cost "key must be a file name, got '$key'"; return 2 ;;
  esac
  _world_is_num "${2:-}" && _world_is_num "${3:-}" && _world_is_num "${4:-}" \
    || { _world_refuse world_cost "mem_pct, cores and seconds must be decimals ≥ 0"; return 2; }
  mkdir -p "$BIONIC_GATE_DIR/cost" || return 1
  f="$BIONIC_GATE_DIR/cost/$key"
  printf '%s:%s:%s:%s\n' "$2" "$3" "$4" "$(_res_now)" >> "$f"
  tail -n 3 "$f" > "$f.tmp" && mv "$f.tmp" "$f"
}

# world_suite <name> <green|red|none|kill> — writes `tests/<name>.test.sh` under the CURRENT
# directory (a fixture checkout or a row tree; `cd` there first) and prints its absolute path.
# The suite prints `PASS:` lines and the framework's verdict line, `<file>: <p>/<t> passed,
# <f> failed  sections=1 setup=0`, without sourcing tests/lib/assert.sh:
#   green  one PASS, the verdict line, rc 0
#   red    one PASS and one `FAIL:` line, the verdict line, rc 1
#   none   one PASS, then exit 0 BEFORE the verdict line
#   kill   one PASS, then `kill -9` on itself (rc 137)
world_suite() (
  name="${1:-}"; name="${name%.test.sh}"; ending="${2:-}"
  case "$name" in
    ''|*/*) _world_refuse world_suite "name must be a bare suite name, got '${1:-}'"; exit 2 ;;
  esac
  file="$name.test.sh"
  case "$ending" in
    green) tail="echo; echo \"$file: 1/1 passed, 0 failed  sections=1 setup=0\"; exit 0" ;;
    red)   tail="echo \"FAIL: $name planted red\"; echo; echo \"$file: 1/2 passed, 1 failed  sections=1 setup=0\"; exit 1" ;;
    none)  tail="exit 0" ;;
    kill)  tail="kill -9 \$\$" ;;
    *) _world_refuse world_suite "ending must be green, red, none or kill, got '$ending'"; exit 2 ;;
  esac
  mkdir -p tests || exit 1
  printf '#!/bin/bash\n# world suite: ends %s (tests/lib/world.sh)\necho "PASS: %s ran"\n%s\n' \
    "$ending" "$name" "$tail" > "tests/$file" || exit 1
  chmod +x "tests/$file"
  printf '%s/tests/%s' "$(pwd -P)" "$file"
)

# world_verbs — prints the verb log's path (BIONIC_VERB_LOG), creating the file. What a
# command under test appends there, one verb per line, is the landing line's to decide.
world_verbs() {
  : >> "$BIONIC_VERB_LOG" || return 1
  printf '%s' "$BIONIC_VERB_LOG"
}

# world_repo — prints the root of a new fixture repository under WORLD_ROOT, built with real
# git: `main` with tests/a.test.sh and tests/b.test.sh (both green); the working branch
# `wave/x` checked out; the bound plan .bionic/docs/plans/epic-x/wave-x.plan.md
# (`working-branch: wave/x`, open at step 4, rows T1 and T2) with WORLD_SID's engaged marker;
# a roster at .bionic/tmp/roster-<WORLD_SID>.state with rows wx-T1 and wx-T2; and two row trees,
# .worktrees/T1 on `wt/T1` and .worktrees/T2 on `wt/T2`, each cut from wave/x with one
# commit of its own (T1.txt, T2.txt) and a .bionic link to the root's, as spawn-worktree
# plants it. `.bionic` and `.worktrees/` are ignored, so every checkout reads clean.
world_repo() (
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
  root="$(mktemp -d "$WORLD_ROOT/repo.XXXXXX")" && root="$(cd "$root" && pwd -P)" || exit 1
  [ -n "$root" ] || exit 1
  git -C "$root" init --quiet || exit 1
  # Rule 12: nothing writes until git agrees the repository is the one just made.
  [ "$(git -C "$root" rev-parse --show-toplevel 2>/dev/null)" = "$root" ] \
    || { echo "world_repo: git's toplevel is not $root — refusing" >&2; exit 1; }
  git -C "$root" symbolic-ref HEAD refs/heads/main
  git -C "$root" config user.name "world"
  git -C "$root" config user.email "world@example.invalid"
  git -C "$root" config commit.gpgsign false
  printf '.bionic\n.bionic/\n.worktrees/\n' > "$root/.gitignore"
  ( cd "$root" && world_suite a green >/dev/null && world_suite b green >/dev/null ) || exit 1
  git -C "$root" add .gitignore tests/a.test.sh tests/b.test.sh
  git -C "$root" commit --quiet -m "world: base" || exit 1
  git -C "$root" checkout --quiet -b wave/x || exit 1

  plan="$root/.bionic/docs/plans/epic-x/wave-x.plan.md"
  mkdir -p "${plan%/*}" "$root/.bionic/tmp"
  cat > "$plan" <<'PLAN'
---
working-branch: wave/x
---
# fixture plan (tests/lib/world.sh)

## SDLC State

current: 4

## Tasks

| id | step | kind | task | agent | deps | reads | size | serves | Files | worktree | base | status |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| T1 | 4 | build | row one | wx-T1 | — | | 10 | REQ-1 | T1.txt | .worktrees/T1 | | active |
| T2 | 4 | build | row two | wx-T2 | — | | 10 | REQ-1 | T2.txt | .worktrees/T2 | | active |
PLAN
  if ! type -t bound_marker >/dev/null 2>&1; then
    # shellcheck source=/dev/null
    . "${BIONIC_SCRIPTS_DIR}/tests/lib/bound-marker.sh" || exit 1
  fi
  bound_marker "$root" "$WORLD_SID" "$plan" || exit 1
  if ! type -t roster_row_fixture >/dev/null 2>&1; then
    # shellcheck source=/dev/null
    . "${BIONIC_SCRIPTS_DIR}/tests/lib/roster-row.sh" || exit 1
  fi
  for t in T1 T2; do
    git -C "$root" worktree add --quiet -b "wt/$t" "$root/.worktrees/$t" wave/x >/dev/null 2>&1 || exit 1
    ln -s "$root/.bionic" "$root/.worktrees/$t/.bionic"
    printf '%s\n' "$t work" > "$root/.worktrees/$t/$t.txt"
    git -C "$root/.worktrees/$t" add "$t.txt"
    git -C "$root/.worktrees/$t" commit --quiet -m "$t: one commit" || exit 1
    roster_row_fixture session="$WORLD_SID" name="wx-$t" agent_id="a00$t" plan="$plan" \
      >> "$root/.bionic/tmp/roster-$WORLD_SID.state" || exit 1
  done
  printf '%s' "$root"
)
