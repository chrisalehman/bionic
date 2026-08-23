#!/bin/bash
# hooks.sh — the legacy managed-hook channel's STRIP (epic-17 wave-03).
#
# WHAT THIS FILE OWNS. One mutation: deleting the user settings.json
# managed-hook entries whose command names the pre-plugin `~/.claude/hooks/`
# directory. Nothing else — no counting, no prompting, no reporting.
#
# WHY THE CHANNEL'S TWO HALVES LIVE IN TWO FILES. The COUNT is
# `detect_legacy_channel_hooks`, and detect.sh is read-only by contract — a
# fingerprint wall used to enforce it (tests/plugin-lib.test.sh Group 15,
# deleted at 8582861, epic-18 wave-03; nothing replaced the wall). A rewrite
# cannot live there. So the read half stays in detect.sh, the write half is
# here, and what joins them is the predicate substring both spell — no test
# pins this two-ended agreement since tests/remove.test.sh was deleted at
# 8582861.
#
# WHY THIS FILE EXISTS AT ALL. The rewrite used to be inline in setup.sh, while
# remove.sh carried its own structurally different spelling of the same
# operation (setup nested both `with_entries` passes inside one `.hooks |=`;
# remove chained three top-level steps). Only the SUBSTRING was pinned between
# them, never the rewrite: fix one file's group-collapse behaviour and the other
# silently keeps the old one. setup.sh has no excuse for a second copy — it
# refuses to run at all without the libraries beside it. remove.sh does have
# one: its standalone door (design D5a) must work on a machine where this file
# is already gone, so remove.sh keeps an inline copy and the two programs are
# pinned against each other.
#
# THE REWRITE'S SHAPE, and why it is not simply `del`. The filter reaches INSIDE
# each matcher group rather than dropping the group: a group can hold a bionic
# hook and a foreign one, and dropping it whole would remove somebody else's
# hook. Groups left empty by the filter are collapsed afterwards, and a `hooks`
# object left empty is deleted — the same shape claude-reset.sh produced, so a
# machine cleaned by either route ends up with the same file.
#
# NO `dirname`/`basename`, for the reason detect.sh gives at length: a library
# that cannot be sourced without coreutils dies on the machine it is most needed
# on.
#
# Sourced, never executed:  . "${CLAUDE_PLUGIN_ROOT}/scripts/lib/hooks.sh"

# THE SYMLINK RESOLVER, one of four byte-identical copies (critic delta 2 N1).
# Every writer in this payload resolves the path it is about to rewrite to the
# final target of its symlink chain and publishes onto THAT, so a `~/.zshrc` or
# `~/.claude/settings.json` symlinked into a dotfiles repo is REWRITTEN rather
# than replaced by a detached regular file while the repo keeps the old content.
# lib/deps.sh carries the full reasoning, the portability note (no `realpath`, no
# `readlink -f`) and the degradation contract.
#
# THE ABSENT CASE IS NOT NEUTRAL (critic delta 3 F5). Absent `readlink`, the write
# lands on the link's path as given, which replaces a symlink with a regular
# file — the pre-S15 behaviour. `readlink` lives beside `stat` on both platforms
# this payload targets, so the risk is negligible; it is recorded here because the
# consequence, not just the mechanism, is what a reader of this comment needs.
#
# WHY A COPY AND NOT A SOURCE. This file is sourced on its own — by the suites,
# and by callers that load no other library — so it cannot assume deps.sh came
# first; and remove.sh's standalone door runs where scripts/lib/ is already gone.
# A `. deps.sh` here would also break every mutation arm that runs a doctored
# COPY of this file from a scratch directory. The four copies used to be
# pinned byte-identical in tests/remove.test.sh, the same wall the settings
# writer's two copies stood behind; that suite was deleted at 8582861 and
# nothing replaced either wall.
bionic_link_target() {  # <path> — the final target of a symlink chain, else <path>
  local p="${1:-}" link dir n=0
  while [ -L "$p" ] && [ "$n" -lt 40 ]; do
    link="$(readlink "$p" 2>/dev/null)" || break
    [ -n "$link" ] || break
    case "$link" in
      /*) p="$link" ;;
      *)  dir="${p%/*}"; [ "$dir" = "$p" ] && dir="."; p="${dir}/${link}" ;;
    esac
    n=$((n + 1))
  done
  printf '%s\n' "$p"
}

# The substring that puts a managed-hook entry on the legacy settings channel.
# detect.sh spells it inside its own count program; remove.sh spells it in its
# standalone copy. All three must agree or a machine gets counted under one
# predicate and rewritten under another.
BIONIC_LEGACY_HOOK_SUBSTR='.claude/hooks/'

# Byte-identical to remove.sh's RM_LEGACY_HOOK_STRIP_JQ apart from the name of
# the variable interpolated into it. tests/remove.test.sh Group 8 used to
# extract both and compare them, which made "remove.sh keeps a copy" a
# decision rather than a drift; that suite was deleted at 8582861 and nothing
# replaced the check.
BIONIC_LEGACY_HOOK_STRIP_JQ='
  if (.hooks | type) != "object" then .
  else
      .hooks |= with_entries(
        .value |= ( map( .hooks |= map(select(((.command? // "") | contains("'"${BIONIC_LEGACY_HOOK_SUBSTR}"'")) | not)) )
                    | map(select((.hooks | length) > 0)) )
      )
    | .hooks |= with_entries(select((.value | length) > 0))
    | if (.hooks | length) == 0 then del(.hooks) else . end
  end
'

# Rewrite <settings-file> in place with every legacy-channel managed-hook entry
# removed. Exit 0 only when the file was rewritten; non-zero means it was left
# exactly as it was found, which is what lets a caller report an honest failure
# instead of a silent no-op. The temp file is removed on every failure path, so
# a refusal leaves no debris beside the user's settings.
#
# CONSENT IS THE CALLER'S, as it is everywhere else in this payload: this
# function never prompts and never asks whether it should. It is handed a path
# and it writes.
#
# THE FILE'S MODE SURVIVES THE REWRITE. `mv` replaces the inode, so without the
# capture-and-reapply below this function would hand settings.json the umask's
# mode instead of its own — widening a file that routinely holds an `env` block
# with tokens from 0600 to 0644 as a side effect of a hook cleanup. `stat` is
# spelled both ways because BSD and GNU take different flags and neither accepts
# the other's; an absent `stat` leaves `mode` empty and the rewrite still lands,
# which is the same honest degradation this file already practises for `jq`.
#
# AND IT IS THE TARGET'S MODE, NOT THE LINK'S (S14). A settings.json symlinked
# into a dotfiles repo is the commonest way people manage it, and a bare `stat`
# on a symlink reports the LINK's own mode — 755 — never the file's. `-L` makes
# the capture mean the file.
#
# THE ORDER IS THE FIX. `umask 077` and the `chmod` both come BEFORE the `mv`, so
# the rename publishes an already-correct inode. Repairing the mode afterwards —
# the obvious spelling — leaves the tmp holding the tokens at 0644 under a
# predictable name, and makes the widening PERMANENT if the process dies in the
# window between the two. Do not move either below the rename. remove.sh's
# `_rm_write` carries the same ordering; no test pins the shape across both
# writers since tests/remove.test.sh was deleted at 8582861.
#
# THE STALE TMP IS REMOVED, NOT TRUNCATED. `>` on an existing file keeps that
# file's mode, so a tmp left behind by an earlier interrupted run would carry
# ITS width through the write until the chmod line below caught up.
hooks_strip_legacy_channel() {  # <settings-file>
  local settings="${1:-}"
  local tmp mode
  [ -n "$settings" ] || return 1
  [ -f "$settings" ] || return 1
  command -v jq >/dev/null 2>&1 || return 1

  settings="$(bionic_link_target "$settings")"
  tmp="${settings}.bionic.tmp"
  mode="$(stat -L -f '%Lp' "$settings" 2>/dev/null || stat -L -c '%a' "$settings" 2>/dev/null)"
  [ -e "$settings" ] || mode=""
  rm -f "$tmp"
  if (umask 077; jq "$BIONIC_LEGACY_HOOK_STRIP_JQ" "$settings" > "$tmp") \
     && { [ -z "$mode" ] || chmod "$mode" "$tmp"; } \
     && mv "$tmp" "$settings"; then
    return 0
  fi
  rm -f "$tmp"
  return 1
}
