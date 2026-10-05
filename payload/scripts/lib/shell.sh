#!/bin/bash
# shell.sh — the ONE home for "which rc file does bionic write to" (L-DETECT/4.4,
# spec AC-21).
#
# THE DUPLICATION THIS CLOSES. `_detect_shell_rc` (detect.sh) and `_rm_shell_rc`
# (remove.sh) were two copies of the identical case statement — same
# BIONIC_SHELL_RC override, same zsh/bashrc split, same fallback for anything
# else. Two owners of one answer drift the first time either one changes and
# the other does not; this file is the single answer, and both callers become
# thin wrappers around it.
#
# THE FALLBACK IS ".bashrc", DELIBERATELY, FOR ANY SHELL THAT IS NOT ZSH. This
# preserves the exact behavior both prior copies already had — fish, ksh, an
# unset $SHELL, all resolve to "$HOME/.bashrc" — rather than introducing a new
# refusal path. `env.sh`'s `rc_file` is a separate, pre-existing resolver with
# its own, stricter posture (it REFUSES for a shell it does not recognize) and
# is out of scope here: it is not one of the two functions this task was asked
# to unify, and giving it a third behavior on top of two would be a second,
# uncoordinated change to a fact this file does not own.
#
# Sourced, never executed:  . "${CLAUDE_PLUGIN_ROOT}/scripts/lib/shell.sh"

shell_rc_file() {
  if [ -n "${BIONIC_SHELL_RC:-}" ]; then echo "$BIONIC_SHELL_RC"; return; fi
  local shell_name="${SHELL:-/bin/bash}"
  case "${shell_name##*/}" in
    zsh) echo "$HOME/.zshrc" ;;
    *)   echo "$HOME/.bashrc" ;;
  esac
}

# THE SHELL THAT READS AN RC, the one `shell_rc_file` chose the file for (wave-27
# T66): a `.zshrc` is zsh's and a `.bashrc` bash's, and any other name (the
# BIONIC_SHELL_RC override) goes by $SHELL exactly as the resolver above does. It
# is the shell asked, with `-n` on a staged copy, whether the rc still parses when
# bionic takes a line out (markers.sh `bionic_rc_alone`). remove.sh carries it
# under the same name, pinned by tests/rc-item.test.sh §T66.
bionic_rc_shell() {  # <rc> — zsh or bash
  local shell_name="${SHELL:-/bin/bash}"
  case "${1##*/}" in
    .zshrc)  echo zsh ;;
    .bashrc) echo bash ;;
    *) case "${shell_name##*/}" in zsh) echo zsh ;; *) echo bash ;; esac ;;
  esac
}
