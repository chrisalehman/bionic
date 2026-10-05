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
#   markers_check <file> <start> <end>              rc 2 and `line <n>: …` per fault
#   markers_only  <file> <start> <end>              rc 0 when the block is all the file holds
#   markers_writable <file>                         rc 1 when the user made it read-only
#   markers_regular  <file>                         rc 4, and what it is, when it is not text bionic can read
#   markers_regular_cell <what>                     the status cell for markers_regular's answer
#   markers_drop_lines <file> <predicate> <n>,<n>   those whole lines gone, every other byte kept
#
# THE WRITERS' EXIT CODES ARE THE REASON (wave-27 T40, review pass 9 findings 1,
# 2 and 8; T46). 0 written; 1 a write failed; 2 the markers do not pair up; 3 the
# file is read-only; 4 the path is not a regular text file bionic can read
# (`markers_regular` says which). On every non-zero the target is byte-identical
# to what it was.
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

# A FILE THE USER MADE READ-ONLY IS REFUSED, NEVER WRITTEN OVER (wave-27 T40,
# review pass 9 finding 8). The rename would replace it anyway — `mv` needs the
# directory writable, not the file — so the file's own bit is the user's only
# way to say "keep tools out", and it is honoured here. An absent file is
# writable: creating it is the caller's question, already asked.
markers_writable() {  # <file>
  local target
  target="$(bionic_link_target "$1")"
  [ ! -e "$target" ] || [ -w "$target" ]
}

# A TARGET IS A REGULAR FILE, A LINK TO ONE, OR NOTHING YET (wave-27 T46, review
# pass 14 finding 6). A directory at the path took the staged copy INTO itself
# on the rename and reported a write; a dangling link had its target created
# somewhere the user never named. Anything else is refused with rc 4 before a
# byte is staged, and this prints what the path is, for the line that says so —
# for a dangling link, where it points, which is what tells a user their
# dotfiles are not checked out (wave-27 T51, review pass 21 F3).
#
# AND THE FILE IS TEXT BIONIC CAN READ (T51, F4 and F5). Every walk here reads
# lines with bash `read`, and `/bin/bash` 3.2's `read` cuts a line at a NUL byte:
# `<end marker>\0mine` read as the end marker alone, the file as "the block and
# nothing else", and remove deleted it with the user's text in it. So a file
# holding a NUL is not text and is refused like a directory, the test made on the
# file's bytes by `tr`, which sees a NUL under any bash. A file the user cannot
# read read as "no block", and doctor sent them to a setup step that then failed;
# it is refused the same way, and called unreadable.
markers_regular() {  # <file>
  if [ -L "$1" ] && [ ! -e "$1" ]; then printf 'a link to %s, which does not exist\n' "$(bionic_link_target "$1")"; return 4; fi
  [ -e "$1" ] || return 0
  if [ -f "$1" ]; then
    if [ ! -r "$1" ]; then printf 'unreadable: bionic has no permission to read it\n'; return 4; fi
    if ! LC_ALL=C tr -d '\000' < "$1" | cmp -s - "$1"; then printf 'not text: it holds a NUL byte\n'; return 4; fi
    return 0
  fi
  if [ -d "$1" ] && [ -L "$1" ]; then printf 'a link to a directory\n'
  elif [ -d "$1" ]; then printf 'a directory\n'
  else printf 'not a regular file\n'; fi
  return 4
}

# The few words a status cell has room for, read off `markers_regular`'s answer,
# so setup's item and doctor's row name the same fault the same way.
markers_regular_cell() {  # <what markers_regular printed>
  case "$1" in
    "not text:"*)   printf 'not text\n' ;;
    "unreadable:"*) printf 'unreadable\n' ;;
    *)              printf 'not a file\n' ;;
  esac
}

# A BLOCK IS ONE START LINE, THEN ONE END LINE, ONCE (wave-27 T40, review pass 9
# finding 2). A start with no end after it, an end with no start before it, the
# two out of order, a start inside an open block, or a second block: the walk
# cannot tell which lines are bionic's, so it says what it found and where, one
# `line <n>: …` per fault, and every writer refuses with rc 2. A marker QUOTED in
# a line of prose is not a marker (whole-line equality, above); a whole marker
# line inside a code fence is, because a line is all the walk reads — so a quoted
# start with no end after it is a fault, and a whole pair inside a fence is a
# block like any other. An absent file has no markers and is well formed.
markers_check() {  # <file> <start> <end>
  local file="$1" start="$2" end="$3" line n=0 open=0 first=0 bad=0
  [ -f "$file" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    if [ "$line" = "$start" ]; then
      if [ "$open" != "0" ]; then
        printf 'line %s: a second start marker inside the block opened at line %s\n' "$n" "$open"; bad=1; continue
      fi
      if [ "$first" != "0" ]; then
        printf 'line %s: a second block (the first starts at line %s)\n' "$n" "$first"; bad=1
      else
        first="$n"
      fi
      open="$n"
    elif [ "$line" = "$end" ]; then
      if [ "$open" = "0" ]; then
        printf 'line %s: an end marker with no start marker before it\n' "$n"; bad=1; continue
      fi
      open=0
    fi
  done < "$file"
  if [ "$open" != "0" ]; then
    printf 'line %s: a start marker with no end marker after it\n' "$open"; bad=1
  fi
  [ "$bad" = "0" ] || return 2
  return 0
}

# The file holds one well-formed block and not one other line, blank lines
# included: what a file setup created and nobody else wrote into looks like.
markers_only() {  # <file> <start> <end>
  local file="$1" start="$2" end="$3" line inside=0 seen=1
  [ -f "$file" ] || return 1
  markers_check "$file" "$start" "$end" >/dev/null || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$line" = "$start" ]; then inside=1; seen=0; continue; fi
    if [ "$line" = "$end" ];   then inside=0; continue; fi
    [ "$inside" = "1" ] || return 1
  done < "$file"
  return "$seen"
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
#
# EVERY WRITE IS CHECKED, AND THE MARKERS FIRST (wave-27 T40). A walk that ignored
# a failed `printf` handed a truncated copy to the rename and the user's file was
# replaced by its first few kilobytes (review pass 9 finding 1); a walk that took
# an unpaired start to mean "the block runs to the end of the file" deleted the
# rest of it (finding 2). So: rc 2 before a byte is staged when the markers do not
# pair up, rc 1 the moment a write fails, and the caller publishes only on 0.
_markers_rewrite() {  # <file> <tmp> <start> <end> — <tmp> gets every line of <file> outside the block
  local file="$1" tmp="$2" start="$3" end="$4"
  local line inside=0 pending=0
  [ -r "$file" ] || return 1
  markers_check "$file" "$start" "$end" >/dev/null || return 2
  {
    while IFS= read -r line || [ -n "$line" ]; do
      if [ "$line" = "$start" ]; then inside=1; continue; fi
      if [ "$line" = "$end" ];   then inside=0; continue; fi
      [ "$inside" = "1" ] && continue
      # Outside the block, the file is reproduced line for line. Blank lines are
      # deferred so a run of them survives exactly as it was — the same shape
      # remove.sh's `_rm_strip_marker_block` holds to.
      if [ "$pending" = "1" ]; then printf '\n' || return 1; pending=0; fi
      if [ -z "$line" ]; then pending=1; continue; fi
      printf '%s\n' "$line" || return 1
    done < "$file"
    if [ "$pending" = "1" ]; then printf '\n' || return 1; fi
  } >> "$tmp" || return 1
  return 0
}

# The lines between the markers, in file order, each with its newline. More than
# one block (a hand-pasted second copy) prints every block's lines, which is what
# a caller comparing against one expected body needs to see as "not that body".
# rc 1 when the file is absent or holds no start marker, so "no block" and "an
# empty block" are two answers. rc 2, and nothing printed, when the markers do not
# pair up (`markers_check`): there is no block to read, and no answer to compare.
markers_get() {  # <file> <start> <end>
  local file="$1" start="$2" end="$3" line inside=0 seen=1
  [ -f "$file" ] || return 1
  markers_check "$file" "$start" "$end" >/dev/null || return 2
  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$line" = "$start" ]; then inside=1; seen=0; continue; fi
    if [ "$line" = "$end" ];   then inside=0; continue; fi
    if [ "$inside" = "1" ]; then printf '%s\n' "$line" || return 1; fi
  done < "$file"
  return "$seen"
}

# IDEMPOTENT BY CONSTRUCTION, not by a guard that could be wrong: the block is
# removed and rewritten whole on every call, at the end of the file, so a second
# run produces the same bytes and a block left half-written by an interrupted run
# is repaired rather than appended beside. An absent file is created, under the
# same 0600 staging: the caller has already asked whether it may be.
markers_set() {  # <file> <start> <end> <body file>
  local file="$1" start="$2" end="$3" body="$4" target tmp last rc
  [ -f "$body" ] || return 1
  markers_regular "$file" >/dev/null || return 4
  markers_writable "$file" || return 3
  target="$(bionic_link_target "$file")"
  tmp="${target}.bionic.tmp"
  _markers_stage_tmp "$tmp" || return 1
  if [ -f "$file" ]; then
    _markers_rewrite "$file" "$tmp" "$start" "$end"; rc=$?
    [ "$rc" = "0" ] || { rm -f "$tmp"; return "$rc"; }
  fi
  # A body whose last line has no newline would fuse with the end marker.
  last="$(tail -c 1 "$body" 2>/dev/null)"
  # One chain, so the status of EVERY write reaches the test, not just the last.
  {
    printf '%s\n' "$start" && cat "$body" && { [ -z "$last" ] || printf '\n'; } && printf '%s\n' "$end"
  } >> "$tmp" || { rm -f "$tmp"; return 1; }
  _markers_publish_tmp "$tmp" "$target" || { rm -f "$tmp"; return 1; }
  return 0
}

# LINES WITH NO MARKERS AROUND THEM, TAKEN OUT ONE BY ONE (wave-27 T55, review pass
# 32 F1). The retired bare alias has no block to address, so the caller names the
# lines by number — the ones it asked about — and a line goes only when it is one of
# those AND <predicate> still says it is bionic's; any difference between the two
# sets (the file changed since it was read) is rc 2 with nothing written. Every
# other byte is reproduced as it was: a line's own terminator stays with it, so a
# CR LF file keeps its CRs and a file with no final newline gets none added (the
# filter this replaced appended one). bionic_drop_lines_walk prints the lines that
# stay; remove.sh carries it under the same name, pinned by tests/rc-item.test.sh.
bionic_drop_lines_walk() {  # <file> <predicate> <n>,<n> — the lines that stay, to stdout; rc 2 when the sets differ
  local file="$1" pred="$2" want=",$3," line n=0 nl dropped=""
  while :; do
    nl=1
    IFS= read -r line || { [ -n "$line" ] || break; nl=0; }
    n=$((n + 1))
    if "$pred" "$line"; then
      case "$want" in *",${n},"*) dropped="${dropped}${dropped:+,}${n}"; continue ;; esac
    fi
    printf '%s' "$line" || return 1
    if [ "$nl" = "1" ]; then printf '\n' || return 1; fi
  done < "$file"
  [ ",${dropped}," = "$want" ] || return 2
  return 0
}

# The writer: 0 removed; 1 a write failed; 2 the lines are not the ones named;
# 3 read-only; 4 not a regular text file. On every non-zero the file is as it was.
markers_drop_lines() {  # <file> <predicate> <n>,<n>
  local file="$1" target tmp rc
  markers_regular "$file" >/dev/null || return 4
  [ -f "$file" ] || return 2
  markers_writable "$file" || return 3
  target="$(bionic_link_target "$file")"
  tmp="${target}.bionic.tmp"
  _markers_stage_tmp "$tmp" || return 1
  bionic_drop_lines_walk "$file" "$2" "$3" >> "$tmp"; rc=$?
  [ "$rc" = "0" ] || { rm -f "$tmp"; return "$rc"; }
  _markers_publish_tmp "$tmp" "$target" || { rm -f "$tmp"; return 1; }
  return 0
}

# Absent is success: a teardown that failed because there was nothing to tear
# down would make every second remove report a problem. The FILE is never
# deleted here, even if the block was all it held — whether an emptied file goes
# is the item's decision, not the walk's (the rc item keeps its rc; the
# principles item takes back a CLAUDE.md that held nothing else).
markers_strip() {  # <file> <start> <end>
  local file="$1" start="$2" end="$3" target tmp rc
  markers_regular "$file" >/dev/null || return 4
  [ -f "$file" ] || return 0
  markers_writable "$file" || return 3
  target="$(bionic_link_target "$file")"
  tmp="${target}.bionic.tmp"
  _markers_stage_tmp "$tmp" || return 1
  _markers_rewrite "$file" "$tmp" "$start" "$end"; rc=$?
  [ "$rc" = "0" ] || { rm -f "$tmp"; return "$rc"; }
  _markers_publish_tmp "$tmp" "$target" || { rm -f "$tmp"; return 1; }
  return 0
}
