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
#   markers_replace <file> <start> <end> <body file> the block's body, rewritten where it stands
#   markers_strip <file> <start> <end>              the block, markers and all, gone
#   markers_check <file> <start> <end>              rc 2 and `line <n>: …` per fault
#   markers_only  <file> <start> <end>              rc 0 when the block is all the file holds
#   markers_writable <file>                         rc 1 when the user made it read-only
#   markers_regular  <file>                         rc 4, and what it is, when it is not text bionic can read
#   markers_regular_cell <what>                     the status cell for markers_regular's answer
#   bionic_rc_lines <file> <predicate> <ere>        <predicate>'s lines outside a block, by number: never taken out
#   markers_block_alone <file> <start> <end>        whether a retired block is bionic's whole and may go
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
# `bionic_rc_shell` is shell.sh's — which shell reads an rc — for the parse checks
# below (wave-27 T66). The same soft source.
if ! declare -F bionic_rc_shell >/dev/null 2>&1; then
  # shellcheck source=/dev/null
  . "$(cd "$(_markers_self_dir)" && pwd -P)/shell.sh"
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
#
# WITH A <body file>, THE BLOCK STAYS WHERE IT STOOD (wave-27 T77, A-orch-193): its two
# marker lines are reproduced like every other line, and what stood between them is
# replaced by the body (a last line with no newline gets one, or it would fuse with the
# end marker). `markers_replace` is the one caller; without it the walk is unchanged.
_markers_rewrite() {  # <file> <tmp> <start> <end> [<body file>] — <tmp> gets every line of <file> outside the block
  local file="$1" tmp="$2" start="$3" end="$4" body="${5:-}"
  local line inside=0 nl last=""
  [ -r "$file" ] || return 1
  markers_check "$file" "$start" "$end" >/dev/null || return 2
  [ -z "$body" ] || last="$(tail -c 1 "$body" 2>/dev/null)"
  {
    while :; do
      nl=1
      IFS= read -r line || { [ -n "$line" ] || break; nl=0; }
      if [ "$line" = "$start" ]; then
        inside=1
        [ -n "$body" ] || continue
        { printf '%s\n' "$line" && cat "$body" && { [ -z "$last" ] || printf '\n'; }; } || return 1
        continue
      fi
      if [ "$line" = "$end" ]; then
        inside=0
        [ -n "$body" ] || continue
      fi
      [ "$inside" = "1" ] && continue
      # Outside the block, the file is reproduced line for line, each line with its
      # own terminator: a last line with no newline gets none added (wave-27 T75,
      # review pass 54 B4; the line walk below already held to it).
      printf '%s' "$line" || return 1
      if [ "$nl" = "1" ]; then printf '\n' || return 1; fi
    done < "$file"
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
  # A file whose last line has no newline would fuse with the start marker: the
  # block being written is a new line of the file, and gets one.
  if [ -s "$tmp" ] && [ -n "$(tail -c 1 "$tmp" 2>/dev/null)" ]; then printf '\n' >> "$tmp" || { rm -f "$tmp"; return 1; }; fi
  # A body whose last line has no newline would fuse with the end marker.
  last="$(tail -c 1 "$body" 2>/dev/null)"
  # One chain, so the status of EVERY write reaches the test, not just the last.
  {
    printf '%s\n' "$start" && cat "$body" && { [ -z "$last" ] || printf '\n'; } && printf '%s\n' "$end"
  } >> "$tmp" || { rm -f "$tmp"; return 1; }
  _markers_publish_tmp "$tmp" "$target" || { rm -f "$tmp"; return 1; }
  return 0
}

# THE BLOCK'S BODY REWRITTEN WHERE IT STANDS (wave-27 T77, A-orch-193). `markers_set`
# takes the block out and appends it at the end of the file, so a block that was not
# the file's last lines would move past the owner's lines below it. This writes <body>
# between the markers at the place the block stood: the file is the old file with
# exactly the block's body replaced, and no other byte or line order changes. The same
# walk, staging, refusals and exit codes as `markers_set`; markers that do not pair up,
# or a second block, are rc 2, and a file with no block is rc 1 with nothing written
# (appending one is `markers_set`'s).
markers_replace() {  # <file> <start> <end> <body file>
  local file="$1" start="$2" end="$3" body="$4" target tmp rc
  [ -f "$body" ] || return 1
  markers_regular "$file" >/dev/null || return 4
  markers_writable "$file" || return 3
  markers_check "$file" "$start" "$end" >/dev/null || return 2
  markers_get "$file" "$start" "$end" >/dev/null || return 1
  target="$(bionic_link_target "$file")"
  tmp="${target}.bionic.tmp"
  _markers_stage_tmp "$tmp" || return 1
  _markers_rewrite "$file" "$tmp" "$start" "$end" "$body"; rc=$?
  [ "$rc" = "0" ] || { rm -f "$tmp"; return "$rc"; }
  _markers_publish_tmp "$tmp" "$target" || { rm -f "$tmp"; return 1; }
  return 0
}

# THE MARKERS ARE THE WHOLE RULE (wave-27 T75, A-orch-162; review pass 54 B1 to B4).
# Everything bionic writes into an rc stands between a marker pair, and so did the two
# retired blocks; the one thing it ever wrote with no markers is the retired bare alias
# line. Four rows (T7, T51, T55, T66) tried to say from the TEXT around that line when
# taking it out was safe, and each review found text they did not cover: after `&& # a
# comment` the user's next line became the right side of their `&&`. So no line outside
# a marker pair is ever taken out, by any door. `bionic_rc_lines` names <predicate>'s
# lines (`bound`, `why=hand`: bionic's old line, for the user's hand) and the lines the
# loose <ere> matches that are not bionic's (`theirs`), each by number and never by its
# text; `ours`, the lines a door may take out, is always empty and stays in the answer
# only so every reader of it reads one shape. Lines from a <start> marker to its <end>
# are a marked block's and are not read as bare lines.
# A MARKED BLOCK IS BIONIC'S BY ITS BODY, AND GOES WHEREVER IT STANDS, WITH ONE VETO:
# `markers_block_alone` asks detect.sh `bionic_block_body` for the one body bionic wrote
# between those markers and answers `why=changed` for any other (B3); for bionic's own
# body `bionic_rc_block_alone` asks the rc's own shell (shell.sh `bionic_rc_shell`), with
# `-n` on copies staged in a private directory (`bionic_rc_staged`), whether the rc
# parses before and still parses with the block's lines gone. If it did not parse before,
# or does not after, or its shell is not on the PATH, the block is left and named. That
# veto can only turn a removal into a leave. Nothing of the rc is ever run or sourced:
# the shell gets `-n`, `-f` for zsh, an emptied BASH_ENV and ENV, and a staged copy only.
# THE KNOWN LIMIT: an intact block the user moved to stand right after their own line
# ending in `&&`, `||`, `|` or a backslash, or inside their own here-document or string,
# is removed when the result parses, and their surrounding code then reads differently.
# bionic only ever appended its block at the end of the file. remove.sh carries these
# functions under the same names, pinned by tests/rc-item.test.sh §T66 and §T75.
bionic_rc_candidates() {  # <file> <predicate> <ere> [<start> <end>] — `cand=<n>,<n> theirs=<n>,<n>`
  local LC_ALL=C file="$1" pred="$2" ere="$3" start="${4:-}" end="${5:-}" line n=0 cand="" theirs="" inside=0
  if [ -f "$file" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      n=$((n + 1))
      if [ -n "$start" ]; then
        if [ "$line" = "$start" ]; then inside=1; continue; fi
        if [ "$line" = "$end" ]; then inside=0; continue; fi
        [ "$inside" = "1" ] && continue
      fi
      if "$pred" "$line"; then cand="${cand}${cand:+,}${n}"
      elif [ -n "$ere" ] && [[ "$line" =~ $ere ]]; then theirs="${theirs}${theirs:+,}${n}"; fi
    done < "$file"
  fi
  printf 'cand=%s theirs=%s\n' "$cand" "$theirs"
}

bionic_rc_lines() {  # <file> <predicate> <ere> [<start> <end>] — `ours= bound=<n>,<n> why=hand theirs=<n>,<n>`
  local scan cand
  scan="$(bionic_rc_candidates "$1" "$2" "$3" "${4:-}" "${5:-}")"
  cand="${scan#cand=}"; cand="${cand%% *}"
  printf 'ours= bound=%s why=hand theirs=%s\n' "$cand" "${scan#* theirs=}"
}

# THE STAGED COPIES ARE PRIVATE AND DO NOT OUTLIVE THE DECISION (T75, review pass 54
# S1). <command> runs in a subshell with BIONIC_RC_DIR a fresh directory of mode 0700
# whose copies are 0600 (umask 077), removed on every exit a trap can see: a normal
# return, EXIT, HUP, INT and TERM. A KILL cannot be trapped, and leaves it. rc 3, and
# <command> not run, when no directory can be made.
bionic_rc_staged() {  # <command...>
  (
    umask 077
    BIONIC_RC_DIR="$(mktemp -d "${TMPDIR:-/tmp}/bionic-rc.XXXXXX" 2>/dev/null)" || exit 3
    [ -n "$BIONIC_RC_DIR" ] && [ -d "$BIONIC_RC_DIR" ] || exit 3
    trap 'rm -rf "$BIONIC_RC_DIR"' EXIT
    trap 'exit 129' HUP; trap 'exit 130' INT; trap 'exit 143' TERM
    "$@"
  )
}

bionic_rc_block_alone() {  # <file> <first> <last> — `alone=<yes|no> why=<ok|no-shell|no-parse|no-stage>`
  local file="$1" bin
  bin="$(command -v "$(bionic_rc_shell "$file")" 2>/dev/null)" || bin=""
  if [ -z "$bin" ]; then printf 'alone=no why=no-shell\n'; return 0; fi
  bionic_rc_staged bionic_rc_block_staged "$bin" "$file" "$2" "$3" \
    || printf 'alone=no why=no-stage\n'
}

bionic_rc_block_staged() {  # <shell> <file> <first> <last> — bionic_rc_block_alone's decision, inside bionic_rc_staged
  local bin="$1" file="$2" st="$BIONIC_RC_DIR/rc" n="$3" lines="" alone=no
  if ! bionic_rc_try "$bin" "$file" "$st" ""; then printf 'alone=no why=no-parse\n'; return 0; fi
  while [ "$n" -le "$4" ]; do lines="${lines}${lines:+,}${n}"; n=$((n + 1)); done
  bionic_rc_try "$bin" "$file" "$st" "$lines" && alone=yes
  printf 'alone=%s why=ok\n' "$alone"
}

# The block between <start> and <end> (the first pair; a caller has already refused
# markers that do not pair up) and its answer: `why=changed` when what sits between the
# markers is not, byte for byte, the body bionic wrote there (detect.sh
# `bionic_block_body`, the one place its spellings are listed; T75, review pass 54 B3),
# else `bionic_rc_block_alone`'s. The one function the retired alias block and the
# retired env block are both decided by (A-orch-119 (3)). `alone=<yes|no> why=<…>
# first=<n> last=<n>`. remove.sh's `_rm_block_alone` is this body, pinned by
# tests/rc-item.test.sh §T66.
markers_block_alone() {  # <file> <start> <end>
  local line n=0 first="" last="" body="" want=""
  if declare -F bionic_block_body >/dev/null 2>&1; then want="$(bionic_block_body "$2")"; fi
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    if [ -z "$first" ] && [ "$line" = "$2" ]; then first="$n"
    elif [ -n "$first" ] && [ -z "$last" ] && [ "$line" = "$3" ]; then last="$n"
    elif [ -n "$first" ] && [ -z "$last" ]; then body="${body}${line}"$'\n'; fi
  done < "$1"
  if [ -z "$first" ] || [ -z "$last" ]; then printf 'alone=no why=ok first= last=\n'; return 0; fi
  if [ -z "$want" ] || [ "$body" != "${want}"$'\n' ]; then
    printf 'alone=no why=changed first=%s last=%s\n' "$first" "$last"; return 0
  fi
  printf '%s first=%s last=%s\n' "$(bionic_rc_block_alone "$1" "$first" "$last")" "$first" "$last"
}

# One staged copy of <file>, the lines <drop> names left out, and whether <shell>
# parses it. Never the user's file, never run.
bionic_rc_try() {  # <shell> <file> <staged> <drop n,n> — rc 0 when the copy parses
  LC_ALL=C awk -v drop=",$4," '
    index(drop, "," NR ",") { next }
    { print }' "$2" > "$3" 2>/dev/null || return 2
  bionic_rc_parses "$1" "$3"
}

# A STAGED COPY PARSES when the shell's `-n` writes nothing on stderr and exits 0 —
# for zsh, 0 or 1: under `-n` zsh leaves 1 after a script whose last pipeline is
# negated (`! cmd`), with nothing on stderr, and a parse error always says so there
# (T75, review pass 54 S3). So the answer never depends on what the rc's last command
# would return.
bionic_rc_parses() {  # <shell> <staged>
  local err rc
  case "${1##*/}" in
    zsh) err="$(BASH_ENV= ENV= "$1" -f -n "$2" 2>&1 >/dev/null </dev/null)"; rc=$?; [ "$rc" -le 1 ] || return 1 ;;
    *)   err="$(BASH_ENV= ENV= "$1" -n "$2" 2>&1 >/dev/null </dev/null)" || return 1 ;;
  esac
  [ -z "$err" ]
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
