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
# tests/lib/assert.sh. `tests/run.sh` is not a suite: it builds the pin for its
# whole run, with this file's `bionic_interpreter_pin` below and its own temp
# root, and hands it to its children, so every suite it launches finds the pin
# already first on PATH. The runner itself keeps whatever interpreter the
# caller typed, and must — it sources this seam part-way through its own run,
# so re-executing it there would start the run again from the top.
# Before Step 6 the exported marker happened to cover this; now that the marker
# no longer decides, the exemption has to be said out loud.
#
# WHAT IT WILL NOT DO. `$0` must be a readable file: sourced into an interactive shell
# there is nothing to re-execute, and guessing would exec the shell's own name. `/bin/bash`
# must exist and be executable — on a host where it does not, the shebang every payload
# script carries is unrunnable and this seam is not the place that discovers it.
#
# ── THE INTERPRETER PIN: ONE FUNCTION, OWNED HERE (wave-27 T81; ADR-001) ─────
#
# The re-exec above gives the SUITE /bin/bash. It used to give nothing to what the suite starts:
# a suite typed at a prompt ran under 3.2 while every `bash "$HOOK"` it spawned took PATH's
# 5.3, and tests/run.sh, which put `bash -> /bin/bash` first on PATH for its whole run, never
# showed that world. A 5.x-only `case` arm in a shipped hook was green at every hand-run for
# weeks and red only in the full run. Two pins were two worlds, so there is one, here, and
# tests/run.sh calls it for its run instead of carrying its own.
#
# bionic_interpreter_pin <root> builds <root>/pin holding one entry, `bash -> /bin/bash`, puts
# it first on PATH and exports PATH and the record marker. The REST of PATH is the caller's
# own, so `jq`, `git` and `claude` resolve exactly where they did. The runner's root is its
# run's temp root. A hand-run suite has none yet when it sources this file, so its root is one
# directory per user under the temp directory, made once and reused, never removed: it holds a
# symlink and nothing else, and removing it while another suite's children resolve `bash`
# through it would be the race. An entry already there is never replaced, for the same reason.
#
# THE PATH ITSELF IS JUDGED, NEVER WHAT A LINK POINTS AT (wave-27 T87; review pass 75). That
# per-user root is a predictable name, and under a shared /tmp anyone can plant it first. `-O`
# and `-d` follow a link, so a link planted there to any directory this user owns once passed,
# PATH carried the link's path, and the planter could repoint it mid-run to put their own `bash`
# under every child. So each of the root and <root>/pin is refused when it IS a symlink (tested
# first, right after the one mkdir, which never creates through a link), is not a directory, is
# not this user's, or is writable by group or others. A root made here is mode 0700. A refusal
# returns non-zero, pins nothing, leaves PATH alone and prints this seam's line once, naming the
# check; the caller adds nothing to it. The reason is also left in _BIONIC_PIN_WHY (empty when
# the pin was built), for the hand-run path below, which prints its own line instead.
#
# THE PARENT IS JUDGED TOO (wave-28 T36; AC-10.6; Chris "D3: 1"). Whoever can write the root's
# parent directory can rename the root away and make their own in its place, between this check
# and a child's `bash`. So a parent that group or others can write is refused unless it carries
# the sticky bit, which is what keeps a shared /tmp safe: there only a file's owner may rename it. The
# parent is read THROUGH a symlink (`ls -ldL`, wave-28 T54): a link's own mode is always open, so a
# parent reached through one is judged by the directory it leads to.
#
# EVERY LINK ON THE PARENT'S PATH IS JUDGED BY THE DIRECTORY THAT HOLDS IT (wave-28 T56; AC-10.6).
# Where a link leads says nothing about who may replace the link: whoever can write the directory
# holding it repoints it mid-run and supplies the `bash` every child resolves. So the walk goes
# down the path one component at a time; each link is refused when its holder is open by the
# parent's own rule (group or others can write it, no sticky bit), and then the link's target is
# walked the same way, so a chain of links, and a holder that is itself a link, are covered. A
# holder is read through links like the parent: it is the directory the link really sits in.
_bionic_pin_judge() {  # _bionic_pin_judge <path> — prints why <path> cannot hold the pin; nothing when it can
  if [ ! -d "$1" ]; then echo "$1 is not a directory"
  elif [ ! -O "$1" ]; then echo "$1 is not owned by this user"
  else
    case "$(ls -ldL "$1" 2>/dev/null)" in
      ?????w*|????????w*) echo "$1 is writable by group or others" ;;
    esac
  fi
}
_bionic_pin_open() {  # _bionic_pin_open <dir> — succeeds when group or others can write <dir> and it has no sticky bit
  case "$(ls -ldL "$1" 2>/dev/null)" in
    ?????????[tT]*) return 1 ;;
    ?????w*|????????w*) return 0 ;;
  esac
  return 1
}
_bionic_pin_links() {  # _bionic_pin_links <path> <depth> [<top>] — prints why a link on <path> can be replaced; nothing when none can
  local rest="$1" cur="" holder part target why=""
  case "$1" in /*) ;; *) cur="." ;; esac
  [ "$2" -le 16 ] || { echo "${3:-$1} leads through more than 16 links"; return; }
  while [ -n "$rest" ] && [ -z "$why" ]; do
    part="${rest%%/*}"
    if [ "$part" = "$rest" ]; then rest=""; else rest="${rest#*/}"; fi
    [ -n "$part" ] || { [ -z "$cur" ] || cur="$cur/"; continue; }  # a doubled slash stays as the caller spelled it
    holder="${cur:-/}"
    cur="$cur/$part"
    [ -L "$cur" ] || continue
    if _bionic_pin_open "$holder"; then
      why="$cur is a symlink held in $holder, which is writable by group or others and has no sticky bit"
    else
      target="$(readlink "$cur")"
      case "$target" in /*) ;; *) target="$holder/$target" ;; esac
      why="$(_bionic_pin_links "$target" $(($2 + 1)) "${3:-$1}")"
    fi
  done
  [ -z "$why" ] || echo "$why"
}
_bionic_pin_parent() {  # _bionic_pin_parent <root> — prints why <root>'s parent is open; nothing when it is not
  local parent="${1%/*}" why=""
  [ "$parent" != "$1" ] || parent="."
  [ -n "$parent" ] || parent="/"
  why="$(_bionic_pin_links "$parent" 0)"
  if [ -n "$why" ]; then echo "$why"
  elif _bionic_pin_open "$parent"; then echo "$parent is writable by group or others and has no sticky bit"
  fi
}
_BIONIC_PIN_WHY=""
bionic_interpreter_pin() {
  local root="${1:-}" dir why=""
  [ -n "$root" ] || why="no root was given"
  [ -n "$why" ] || why="$(_bionic_pin_parent "$root")"
  dir="$root/pin"
  [ -n "$why" ] || [ -e "$root" ] || [ -L "$root" ] || mkdir -m 0700 "$root" 2>/dev/null
  [ ! -L "$root" ] || why="$root is a symlink"
  [ -n "$why" ] || why="$(_bionic_pin_judge "$root")"
  [ -n "$why" ] || [ -e "$dir" ] || [ -L "$dir" ] || mkdir -m 0700 "$dir" 2>/dev/null
  [ -n "$why" ] || [ ! -L "$dir" ] || why="$dir is a symlink"
  [ -n "$why" ] || why="$(_bionic_pin_judge "$dir")"
  [ -n "$why" ] || [ -L "$dir/bash" ] || ln -s /bin/bash "$dir/bash" 2>/dev/null
  [ -n "$why" ] || [ "$(readlink "$dir/bash" 2>/dev/null)" = "/bin/bash" ] \
    || why="$dir/bash is not a link to /bin/bash"
  _BIONIC_PIN_WHY="$why"
  if [ -n "$why" ]; then
    echo "resolve-roots.sh: cannot build the interpreter pin under $root — $why, so nothing is pinned" >&2
    return 1
  fi
  PATH="$dir:$PATH"
  export PATH
  BIONIC_TEST_INTERPRETER_PINNED=1
  export BIONIC_TEST_INTERPRETER_PINNED
}

# THE HAND-RUN PATH. The seam calls the function right after its re-exec — in the /bin/bash copy,
# or in a suite started under /bin/bash in the first place — unless the first PATH entry is
# already a pin (a suite tests/run.sh launched, or one this seam already pinned). The test is
# the directory, not the marker, for the reason the re-exec's test is the interpreter (K-4).
#
# A REFUSED PIN STOPS THE RUN, AS THE RUNNER STOPS (wave-28 T36; AC-10.5; wave-27 review pass 75).
# This path used to end `|| :`, so a refused pin printed its line and the suite ran on unpinned —
# the world a full run never gives it, which is the whole thing the pin exists to prevent. Now
# the suite runs no check: it prints one line naming the pin's path and the reason, unsets the
# marker (nothing was pinned) and exits 2, the runner's own code for "nothing was run".
if [ "${0##*/}" != "run.sh" ] \
   && [ -x "/bin/bash" ] \
   && [ -f "$0" ] && [ -r "$0" ]; then
  if [ "${BASH:-}" != "/bin/bash" ]; then
    if [ "$(/bin/bash -c 'printf %s "$BASH"' 2>/dev/null)" = "/bin/bash" ]; then
      BIONIC_TEST_INTERPRETER_PINNED=1
      export BIONIC_TEST_INTERPRETER_PINNED
      exec /bin/bash "$0" "$@"
    else
      echo "resolve-roots.sh: /bin/bash does not report itself as /bin/bash — not re-executing, so this run is under ${BASH:-an unknown shell} and the pin is OFF" >&2
    fi
  elif [ "$(readlink "${PATH%%:*}/bash" 2>/dev/null)" != "/bin/bash" ]; then
    _bionic_pin_root="${TMPDIR:-/tmp}"
    _bionic_pin_root="${_bionic_pin_root%/}/bionic-interpreter-pin.${UID}"
    if ! bionic_interpreter_pin "$_bionic_pin_root" 2>/dev/null; then
      echo "resolve-roots.sh: no interpreter pin at $_bionic_pin_root — ${_BIONIC_PIN_WHY}; remove $_bionic_pin_root or set TMPDIR, then run again" >&2
      unset BIONIC_TEST_INTERPRETER_PINNED
      exit 2
    fi
    unset _bionic_pin_root
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

# THE AUTHOR'S GUARD (wave-27 T47). Under `1` an over-wide refusal line refuses the call instead of
# being cut, so a literal an author typed too long is found at test time. Every suite sources this
# seam, so it is on for a suite run alone and for one run by tests/run.sh; a hook a real session runs
# never has it. payload/scripts/lib/refuse.sh is its only reader and nothing under hooks/ or payload/ sets it.
BIONIC_REFUSE_STRICT="${BIONIC_REFUSE_STRICT:-1}"; export BIONIC_REFUSE_STRICT

unset _bionic_seam_repo
