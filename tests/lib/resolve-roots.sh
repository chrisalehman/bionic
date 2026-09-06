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

# ── HAND-RUN PARITY: ONE INTERPRETER, HOWEVER THE SUITE WAS STARTED ──────────
# (wave-01 verification-cannot-lie S2, spec AC-2; ADR-001 "one interpreter".)
#
# Every payload script and hook pins `#!/bin/bash` — 3.2 on a Mac — and the CLI runs a hook
# by path, so the shebang picks the interpreter. A suite, though, is typed: `bash
# tests/x.test.sh` takes whatever `bash` is first on PATH, which on a machine with Homebrew
# bash is 5.3. `tests/run.sh` pins its children to `/bin/bash` for a whole run; this is the
# same guarantee for the OTHER way a suite starts — one typed at a prompt, or one a debugger
# re-runs by hand — and it rides here because sourcing this seam is the one thing every
# suite in the tree already does.
#
# EXACTLY ONCE, AND IT CANNOT LOOP. The marker is exported before the exec, so the
# re-executed copy — and every child it starts — sees it and falls straight through. It is
# the same marker `tests/run.sh` exports when it builds the pin, so a suite the runner
# launched (already `/bin/bash`) never re-execs either.
#
# WHAT IT WILL NOT DO. `$0` must be a readable file: sourced into an interactive shell
# there is nothing to re-execute, and guessing would exec the shell's own name. `/bin/bash`
# must exist and be executable — on a host where it does not, the shebang every payload
# script carries is unrunnable and this seam is not the place that discovers it.
if [ -z "${BIONIC_TEST_INTERPRETER_PINNED:-}" ] \
   && [ "${BASH:-}" != "/bin/bash" ] \
   && [ -x "/bin/bash" ] \
   && [ -f "$0" ] && [ -r "$0" ]; then
  BIONIC_TEST_INTERPRETER_PINNED=1
  export BIONIC_TEST_INTERPRETER_PINNED
  exec /bin/bash "$0" "$@"
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
