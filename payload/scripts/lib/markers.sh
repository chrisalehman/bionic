#!/bin/bash
# markers.sh — the ONE marker-block library (wave-27 T7, spec D16).
#
# WHAT THIS FILE OWNS. A block of lines bionic writes into a file somebody else
# owns, addressed by a start line and an end line and by nothing else: reading
# it, writing it, and taking it out again. Two items use it today — the shell-rc
# item (env.sh `rc_set`/`rc_unset`, markers `# ─── bionic:rc:… ───`) and the
# working-principles item (env.sh `principles_*`, markers
# `<!-- bionic:principles:… -->`). The walk lived in env.sh as `_rc_rewrite`
# until the second item needed it; it moved here whole, unchanged, so the two
# items cannot come to disagree about what a block is.
#
#   markers_get   <file> <start> <end>              the lines inside, rc 1 if no block
#   markers_set   <file> <start> <end> <body file>  the block, rewritten whole
#   markers_strip <file> <start> <end>              the block, markers and all, gone
#
# THE MARKERS ARE THE ONLY THING MATCHED. Whole-line equality, in bash, never a
# pattern — the rc markers carry box-drawing dashes, and a fuzzy match would be a
# rewrite rule for lines nobody wrote. A line that equals a marker is a marker;
# everything else outside a block is the owner's and is reproduced line for line.
#
# THE MODE TRAVELS WITH THE CONTENT. Staged beside the target under `umask 077`,
# widened to the target's mode only at the instant of publication, and renamed
# over the RESOLVED target rather than a symlink — setup.sh's `_setup_stage_tmp`
# / `_setup_publish_tmp` pair and remove.sh's `_rm_stage_tmp` / `_rm_publish_tmp`
# pair, spelled the same way here so a reader of any one of the three finds the
# same shape — a convention, not a wall: nothing tests the three against each
# other (env.sh's header logs that debt). A shell rc is where people put
# `export …_API_KEY=`, and `mv` replaces the inode, so without this a file a user
# deliberately kept at 0600 comes back at whatever the umask says.
#
# Sourced, never executed:  . "${CLAUDE_PLUGIN_ROOT}/scripts/lib/markers.sh"

_markers_self_dir() {
  local self="${BASH_SOURCE[0]}"
  case "$self" in */*) echo "${self%/*}" ;; *) echo "." ;; esac
}

# `bionic_link_target` is deps.sh's — the one symlink resolver the writers share.
# The same soft source env.sh uses: a caller that already has it does not load it
# twice.
if ! declare -F bionic_link_target >/dev/null 2>&1; then
  # shellcheck source=/dev/null
  . "$(cd "$(_markers_self_dir)" && pwd -P)/deps.sh"
fi

_markers_file_mode() {  # <file> — the mode of what <file> RESOLVES to, empty if unknowable
  local mode
  mode="$(stat -L -f '%Lp' "$1" 2>/dev/null || stat -L -c '%a' "$1" 2>/dev/null)"
  [ -e "$1" ] || mode=""
  printf '%s' "$mode"
}

_markers_stage_tmp() {  # <tmp> — created empty at 0600; the caller writes, then publishes
  local tmp="$1"
  rm -f "$tmp"
  (umask 077; : > "$tmp") || return 1
  return 0
}

_markers_publish_tmp() {  # <tmp> <file> — <file> is the resolved target
  local tmp="$1" file="$2" mode
  mode="$(_markers_file_mode "$file")"
  [ -n "$mode" ] && chmod "$mode" "$tmp"
  mv "$tmp" "$file"
}

# Everything the file holds EXCEPT the block. One walk, so `markers_set` and
# `markers_strip` cannot come to disagree about what the block is.
#
# THE BLOCK IS REBUILT WHOLESALE, NEVER FILTERED. Whatever sits between the
# markers goes — an older payload's text, a line somebody hand-edited in there,
# the half of a block an interrupted run left behind. `markers_set` then writes
# the block back as exactly its body file and `markers_strip` writes no block at
# all, so what the markers hold is always a function of the caller's body and
# never of what was found on disk. Carrying unrecognised in-block lines forward
# was tried and deleted: it round-tripped the block body out through a command
# substitution, which strips the trailing newline, so a surviving line fused
# with whatever was printed after it and the user's rc came back syntactically
# invalid (epic-18 wave-03, critic F1/F2). A caller that must not discard an
# edit inside the block asks first — the principles item shows the difference
# and takes a second yes — and only then calls the writer.
_markers_rewrite() {  # <file> <tmp> <start> <end> — <tmp> gets every line of <file> outside the block
  local file="$1" tmp="$2" start="$3" end="$4"
  local line inside=0 pending=0
  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$line" = "$start" ]; then inside=1; continue; fi
    if [ "$line" = "$end" ];   then inside=0; continue; fi
    [ "$inside" = "1" ] && continue
    # Outside the block, the file is reproduced line for line. Blank lines are
    # deferred so a run of them survives exactly as it was — the same shape
    # remove.sh's `_rm_strip_marker_block` holds to.
    if [ "$pending" = "1" ]; then printf '\n' >> "$tmp"; pending=0; fi
    if [ -z "$line" ]; then pending=1; continue; fi
    printf '%s\n' "$line" >> "$tmp"
  done < "$file"
  [ "$pending" = "1" ] && printf '\n' >> "$tmp"
  return 0
}

# The lines between the markers, in file order, each with its newline. More than
# one block (a hand-pasted second copy) prints every block's lines, which is what
# a caller comparing against one expected body needs to see as "not that body".
# rc 1 when the file is absent or holds no start marker, so "no block" and "an
# empty block" are two answers.
markers_get() {  # <file> <start> <end>
  local file="$1" start="$2" end="$3" line inside=0 seen=1
  [ -f "$file" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$line" = "$start" ]; then inside=1; seen=0; continue; fi
    if [ "$line" = "$end" ];   then inside=0; continue; fi
    [ "$inside" = "1" ] && printf '%s\n' "$line"
  done < "$file"
  return "$seen"
}

# IDEMPOTENT BY CONSTRUCTION, not by a guard that could be wrong: the block is
# removed and rewritten whole on every call, at the end of the file, so a second
# run produces the same bytes and a block left half-written by an interrupted run
# is repaired rather than appended beside. An absent file is created, under the
# same 0600 staging: the caller has already asked whether it may be.
markers_set() {  # <file> <start> <end> <body file>
  local file="$1" start="$2" end="$3" body="$4" target tmp last
  [ -f "$body" ] || return 1
  target="$(bionic_link_target "$file")"
  tmp="${target}.bionic.tmp"
  _markers_stage_tmp "$tmp" || return 1
  if [ -f "$file" ]; then
    _markers_rewrite "$file" "$tmp" "$start" "$end" || { rm -f "$tmp"; return 1; }
  fi
  {
    printf '%s\n' "$start"
    cat "$body"
    # A body whose last line has no newline would fuse with the end marker.
    last="$(tail -c 1 "$body" 2>/dev/null)"
    [ -z "$last" ] || printf '\n'
    printf '%s\n' "$end"
  } >> "$tmp" || { rm -f "$tmp"; return 1; }
  _markers_publish_tmp "$tmp" "$target" || { rm -f "$tmp"; return 1; }
  return 0
}

# Absent is success: a teardown that failed because there was nothing to tear
# down would make every second remove report a problem. The FILE is never
# deleted here, even if the block was all it held — whether an emptied file goes
# is the item's decision, not the walk's (the rc item keeps its rc; the
# principles item takes back a CLAUDE.md that held nothing else).
markers_strip() {  # <file> <start> <end>
  local file="$1" start="$2" end="$3" target tmp
  [ -f "$file" ] || return 0
  target="$(bionic_link_target "$file")"
  tmp="${target}.bionic.tmp"
  _markers_stage_tmp "$tmp" || return 1
  _markers_rewrite "$file" "$tmp" "$start" "$end" || { rm -f "$tmp"; return 1; }
  _markers_publish_tmp "$tmp" "$target" || { rm -f "$tmp"; return 1; }
  return 0
}
