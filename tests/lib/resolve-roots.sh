# tests/lib/resolve-roots.sh — the path-resolution seam (epic-17 wave-02, spec AC-3).
#
# WHAT IT OWNS. One question, for the whole suite: where do the scripts under test
# live. Source this instead of computing a private offset to hooks/ or skills/.
#
#     . "$(dirname "$0")/lib/resolve-roots.sh"      # from tests/*.test.sh
#     . "$(dirname "$0")/../tests/lib/resolve-roots.sh"   # from hooks/ or lib/
#
# WHAT IT EXPORTS. Three per-class roots, each env-overridable, each defaulting
# into this repo checkout:
#
#     BIONIC_HOOKS_DIR    <repo>/hooks     hook scripts
#     BIONIC_SKILLS_DIR   <repo>/skills    skill trees (canonical-sdlc, ...)
#     BIONIC_SCRIPTS_DIR  <repo>           root scripts (claude-bootstrap.sh, ...)
#
# MECHANISM-AGNOSTIC, deliberately. These name DIRECTORIES. How a directory came
# to exist — repo checkout, `claude plugin install`, the bootstrap's manual copy —
# is the installer tests' subject, never this file's. That is what lets the SAME
# suite run against the repo copy and an installed copy without being rewritten.
#
# <repo> IS DERIVED FROM THIS FILE, NOT FROM THE CALLER. `$0` inside a sourced
# file is the CALLER's path and $(pwd) is wherever the runner happened to be, so
# both are wrong the moment a suite is invoked from another directory. This uses
# ${BASH_SOURCE[0]} — this file's own path — and walks up two levels
# (tests/lib -> tests -> repo). Callers may source it by absolute or relative
# reference, from any cwd. bash only: if BASH_SOURCE is unavailable there is no
# honest way to locate ourselves, so we fail loudly rather than guess.
#
# OVERRIDES ARE TAKEN VERBATIM. Whatever you export is what consumers read — no
# absolutising, no existence check, no normalisation. Pass an absolute path: a
# relative override would silently follow any consumer that cd's. An override set
# to the empty string counts as unset (the default applies), matching how every
# other env knob in this repo reads.
#
# Sourcing twice is harmless: the second pass sees the exported value from the
# first and keeps it.

if [ -z "${BASH_SOURCE[0]:-}" ]; then
  echo "resolve-roots.sh: BASH_SOURCE unavailable — source this from bash" >&2
  # shellcheck disable=SC2317  # reached when this file is executed, not sourced
  return 1 2>/dev/null || exit 1
fi

_bionic_seam_repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)" || {
  echo "resolve-roots.sh: cannot resolve repo root from ${BASH_SOURCE[0]}" >&2
  # shellcheck disable=SC2317  # reached when this file is executed, not sourced
  return 1 2>/dev/null || exit 1
}

BIONIC_HOOKS_DIR="${BIONIC_HOOKS_DIR:-${_bionic_seam_repo}/hooks}"
BIONIC_SKILLS_DIR="${BIONIC_SKILLS_DIR:-${_bionic_seam_repo}/skills}"
BIONIC_SCRIPTS_DIR="${BIONIC_SCRIPTS_DIR:-${_bionic_seam_repo}}"
export BIONIC_HOOKS_DIR BIONIC_SKILLS_DIR BIONIC_SCRIPTS_DIR

unset _bionic_seam_repo
