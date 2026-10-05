#!/bin/bash
# tests/reader-exam/materialize.sh <sample dir> <dest> — the sample as a reader meets it.
#
# Makes <dest> a git repository whose first commit is the sample's tree/ and whose second is
# that tree with change.patch applied, and prints the range `<a>..<b>` on one line. <dest>
# also carries an empty `.bionic/`, git-excluded, so a session opened in it has a bionic root
# of its own (README step 3). The answer key (expect.txt) and the sample's name stay behind:
# a reader that sees `red-then-green` in its path has been told the answer, so a <dest> whose
# path names the sample, in any component and in any case, is refused, both as written and
# as the real path it resolves to (a symlink leads somewhere). A relative <dest> is read from
# where this is run.
#
# <dest> is resolved ONCE: its deepest part that exists, physically, links and `..` followed,
# and the parts that do not exist yet as written, which must be plain names (a `.` or `..`
# among them is refused). That real path is the one checked and the one built at. A <dest>
# inside any worktree of the repository this file lies in (`git worktree list`; "inside"
# means a physical ancestor IS that worktree, by device and inode, never by text) is refused
# too: a build there sits beside every answer key. A copy of this file that lies in no checkout
# cannot know where it is, so it does not refuse on that ground; one that lies in a checkout
# whose lookup fails refuses, saying so. A refusal writes nothing.
#
# It runs itself again at once under an environment it makes (`/usr/bin/env -i`, PATH
# /usr/bin:/bin, no CDPATH, no BASH_ENV, none of the caller's functions or aliases), so every
# step it takes runs a program from /usr/bin or /bin and nothing of the caller's.
main() {
  set -uo pipefail
  refuse() { printf 'materialize: refused — %s\n  %s\n' "$1" "$2" >&2; exit 2; }
  phys() { (cd -P -- "$1" 2>/dev/null && pwd -P); }
  inside() {
    local d="$1"
    while :; do
      [ "$d" -ef "$2" ] && return 0
      [ -n "$d" ] && [ "$d" != / ] || return 1
      d="${d%/*}"; d="${d:-/}"
    done
  }
  local src="${1:-}" dest="${2:-}" name abs up rest real part w
  [ -d "$src/tree" ] && [ -r "$src/change.patch" ] || {
    echo "materialize: $src has no tree/ and change.patch" >&2; exit 2; }
  [ -n "$dest" ] || { echo "materialize: <dest> must be a new path" >&2; exit 2; }
  src="$(phys "$src")" && [ -n "$src" ] || exit 2
  name="${src##*/}"
  case "$dest" in /*) abs="$dest" ;; *) abs="$PWD/$dest" ;; esac
  # The real path: the deepest part of <dest> that is a directory, resolved, and the rest as
  # written. The first part that is no directory must exist as nothing, not even as a link.
  up="$abs" rest=""
  while [ ! -d "$up" ]; do rest="/${up##*/}$rest"; up="${up%/*}"; up="${up:-/}"; done
  part="${rest#/}"; part="${part%%/*}"
  if [ -n "$rest" ] && { [ -e "$up/$part" ] || [ -L "$up/$part" ]; }; then
    echo "materialize: <dest> must be a new path" >&2; exit 2
  fi
  case "/$rest/" in */./*|*/../*)
    refuse "a part of <dest> that does not exist yet is . or .." "$dest" ;;
  esac
  real="$(phys "$up")" && [ -n "$real" ] || exit 2
  real="${real%/}$rest"
  local -a trees=()
  worktrees
  for w in ${trees[@]+"${trees[@]}"}; do
    inside "$real" "$w" && refuse "a build never sits inside the checkout that holds the answers" \
      "$dest is $real, inside the worktree $w"
  done
  [ -n "$rest" ] || { echo "materialize: <dest> must be a new path" >&2; exit 2; }
  lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
  local p
  for p in "$abs" "$real"; do
    case "$(lower "$p")" in
      *"$(lower "$name")"*) echo "materialize: $p names the sample $name — a reader given it is told the answer; choose a neutral path" >&2
                            exit 2 ;;
    esac
  done

  g() {
    GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
      git -C "$real" -c user.name=trellis -c user.email=trellis@example.invalid "$@"
  }
  local a b
  mkdir -p "$real" && cp -R "$src/tree/." "$real/" || exit 1
  g init -q && g add -A && g commit -q -m "base" || exit 1
  mkdir "$real/.bionic" && mkdir -p "$real/.git/info" && printf '.bionic/\n' >> "$real/.git/info/exclude" || exit 1
  a="$(g rev-parse HEAD)" || exit 1
  g apply --index "$src/change.patch" && g commit -q -m "change" || exit 1
  b="$(g rev-parse HEAD)" || exit 1
  printf '%s..%s\n' "$a" "$b"
}

# worktrees — sets `trees` to every worktree of the repository this file lies in, each by its
# physical path. A file with no `.git` above it lies in no checkout: no worktree, nothing said.
# One with a `.git` above it whose git cannot name its top and its worktrees is refused: an
# empty or many-lined answer is never read as "no checkout".
worktrees() {
  local here d git_at="" top line w listed
  case "${BASH_SOURCE[0]}" in */*) here="${BASH_SOURCE[0]%/*}" ;; *) here=. ;; esac
  here="$(phys "${here:-/}")"
  [ -n "$here" ] || refuse "the lookup of this file's checkout failed" "its own directory cannot be entered"
  d="$here"
  while :; do
    [ -e "$d/.git" ] && { git_at="$d"; break; }
    [ "$d" != / ] || break
    d="${d%/*}"; d="${d:-/}"
  done
  [ -n "$git_at" ] || return 0
  top="$(git -C "$here" rev-parse --show-toplevel 2>/dev/null)" || top=""
  case "$top" in
    ""|*$'\n'*) refuse "the lookup of this file's checkout failed" \
                  "$git_at/.git lies above it, and git on PATH=$PATH named no single top" ;;
  esac
  [ -d "$top" ] && inside "$here" "$top" || refuse "the lookup of this file's checkout failed" \
    "git named $top, which does not hold $here"
  # Each worktree's physical path on a line of its own; a path that holds a newline is a line
  # that does not open with `/`, and is refused rather than read as two.
  listed="$(git -C "$top" worktree list --porcelain -z 2>/dev/null | while IFS= read -r -d '' line; do
    case "$line" in
      (*$'\n'*) echo "a worktree's path holds a newline" ;;
      ("worktree "*) w="$(phys "${line#worktree }")"; [ -z "$w" ] || printf '%s\n' "$w" ;;
    esac
  done)"
  while IFS= read -r w; do
    case "$w" in
      /*) trees+=("$w") ;;
      ?*) refuse "the lookup of this file's checkout failed" "$w" ;;
    esac
  done <<<"$listed"
  for w in ${trees[@]+"${trees[@]}"}; do [ "$w" -ef "$top" ] && return 0; done
  refuse "the lookup of this file's checkout failed" "git did not list $top among its worktrees"
}

# The helper runs itself again under an environment made here, before any step of its own: from
# this line on, only an absolute path is run, which no function of the caller's can stand in for.
case "${MATERIALIZE_ENV-}" in
  made) main "$@" ;;
  *) /usr/bin/env -i MATERIALIZE_ENV=made PATH=/usr/bin:/bin LC_ALL=C \
       /bin/bash --noprofile --norc -- "${BASH_SOURCE:-$0}" "$@" ;;
esac
