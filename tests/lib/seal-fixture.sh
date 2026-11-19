# tests/lib/seal-fixture.sh — THE ONE CALL A TEST MAKES AFTER IT WRITES A RUN BY HAND
#
#     . "$(dirname "$0")/lib/resolve-roots.sh"      # first, so BIONIC_SCRIPTS_DIR is set
#     . "$(dirname "$0")/lib/seal-fixture.sh"
#     printf 'run/v1|ev=step|n=5|at=2026-10-04T00:05:00Z\n' >> "$log"
#     seal_fixture "$plan"
#
# WHY A FIXTURE SEALS. The product keeps a seal of each run's plan and log (payload/scripts/lib/seal.sh), and a
# run whose files no longer match it is a changed run. A test that writes a log line or a plan by hand writes
# around the tool, exactly the change the seal is there to catch; so every such write is followed by this call,
# which seals the run as the test now holds it. The seal is taken through the product's own library, never a
# copy of its format, so a fixture cannot drift from what the product reads.
#
# seal_fixture [--found] <plan> [<log>] -> seals <plan> and its run's log, clean, as they stand now: the
#   library's `seal_write --vouch run`, the form that is the author's word on the whole run, since a plain
#   seal_write would keep the hand write it was called to vouch for as a caught change. <log> defaults to the
#   log the reader joins to the plan (lib/reader.sh `reader_log`); a fixture that knows its log passes it and
#   spares that lookup. Call it after the LAST hand write of a step, and never after a write a test means the
#   product to catch: called there it would vouch for that change.
#   `--found` is for a fixture that writes neither file, such as one that binds a session: the plain
#   `seal_write`, which seals a run that has no seal as it is found and otherwise only checks it, keeping a
#   change it catches. So binding never vouches for a hand write made before it.
#
# HARMLESS BY CONTRACT. It prints nothing and returns 0 whatever the library answers, so a caller under
# `set -e`, inside `$( )` or in a `|| return 1` chain is unchanged by it: a plan in no git repository has no
# seal to write, and a plan that does not exist is not sealed. The library runs under neither `-e` nor `-u`,
# whatever the caller set, so a caller's options never cut a seal short. It runs in a subshell, so the library
# is never sourced into the test's own namespace (lib/root.sh defines names a test may stub, such as
# `project_root`), and with the caller's GIT_DIR and its kin unset, so the seal lands in the repository that
# holds the plan and never in the one a test or a git hook happens to point git at. A fixture world is its own
# git repository, so its seals stay in that world's common git directory.
seal_fixture() {  # [--found] <plan> [<log>]
  local found=""
  if [ "${1:-}" = --found ]; then found=1; shift; fi
  [ -n "${1:-}" ] || return 0
  (
    set +e +u
    unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
    lib="${BIONIC_SCRIPTS_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd -P)}/payload/scripts/lib"
    plan="$1" log="${2:-}"
    [ -f "$plan" ] || exit 0
    . "$lib/seal.sh" || exit 0
    if [ -z "$log" ]; then
      . "$lib/reader.sh" && log="$(reader_log "$plan")" || exit 0
    fi
    if [ -n "$found" ]; then seal_write "$plan" "$log"; else seal_write --vouch run "$plan" "$log"; fi
  ) >/dev/null 2>&1 || :
  return 0
}
