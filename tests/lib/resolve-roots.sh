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
# THE TEST IS THE INTERPRETER, NOT A MARKER (critic K-4). This guard used to
# re-exec only while `BIONIC_TEST_INTERPRETER_PINNED` was empty — a variable that
# ASSERTS the conclusion, with nothing checking that the interpreter actually is
# `/bin/bash`. `tests/run.sh` exports it to every descendant of a run, so any
# hand-run started from inside a suite, a debugger, or a shell that had once run
# the runner inherited it and reported bash 5.3 while saying nothing:
#
#   $ BIONIC_TEST_INTERPRETER_PINNED=1 /opt/homebrew/bin/bash tests/probe.sh
#   interpreter: 5.3.15(1)-release          <- pin skipped, silently
#
# That is this repository's own fail-closed-constants doctrine inverted: a
# fixture going inert on an inherited env pin. The condition now reads the
# running interpreter and nothing else; the marker is still exported, and
# `tests/run.sh` still exports it, as a RECORD that a run built the pin — but it
# no longer decides.
#
# EXACTLY ONCE, AND IT CANNOT LOOP. After `exec /bin/bash "$0"`, `$BASH` is the
# path the shell was invoked by — `/bin/bash` — so the condition is false in the
# re-executed copy and the pin fires once. The one host on which that would not
# hold is one where `/bin/bash` is a wrapper for some other shell, and there the
# old marker would have hidden an infinite loop; so the target is ASKED, once,
# on the re-exec path only, and a `/bin/bash` that does not report itself is
# announced on stderr instead of exec'd.
#
# THE RUNNER IS THE ONE EXEMPTION, recognised by its own name — the same
# convention, for the same reason, as the derivation's exemption in
# tests/lib/assert.sh. `tests/run.sh` is not a suite: it BUILDS the pin (a
# directory with one `bash` in it, first on PATH) and hands it to its children,
# so every suite it launches is already `/bin/bash` and needs nothing from here.
# The runner itself keeps whatever interpreter the caller typed, and must — it
# sources this seam in a subshell AFTER printing the environment stamp, so
# re-executing it there would re-run the whole roster inside that subshell.
# Before Step 6 the exported marker happened to cover this; now that the marker
# no longer decides, the exemption has to be said out loud.
#
# WHAT IT WILL NOT DO. `$0` must be a readable file: sourced into an interactive shell
# there is nothing to re-execute, and guessing would exec the shell's own name. `/bin/bash`
# must exist and be executable — on a host where it does not, the shebang every payload
# script carries is unrunnable and this seam is not the place that discovers it.
if [ "${BASH:-}" != "/bin/bash" ] \
   && [ "${0##*/}" != "run.sh" ] \
   && [ -x "/bin/bash" ] \
   && [ -f "$0" ] && [ -r "$0" ]; then
  if [ "$(/bin/bash -c 'printf %s "$BASH"' 2>/dev/null)" = "/bin/bash" ]; then
    BIONIC_TEST_INTERPRETER_PINNED=1
    export BIONIC_TEST_INTERPRETER_PINNED
    exec /bin/bash "$0" "$@"
  else
    echo "resolve-roots.sh: /bin/bash does not report itself as /bin/bash — not re-executing, so this run is under ${BASH:-an unknown shell} and the pin is OFF" >&2
  fi
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
