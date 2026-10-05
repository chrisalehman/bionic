#!/bin/bash
# tests/reader-exam/materialize.sh <sample dir> <dest> — the sample as a reader meets it.
#
# Makes <dest> a git repository whose first commit is the sample's tree/ and whose second is
# that tree with change.patch applied, and prints the range `<a>..<b>` on one line. <dest>
# also carries an empty `.bionic/`, git-excluded, so a session opened in it has a bionic root
# of its own (README step 3). The answer key (expect.txt) and the sample's name stay behind:
# a reader that sees `red-then-green` in its path has been told the answer, so a <dest> whose
# path names the sample, in any component and in any case, is refused, both as written and
# as the real path its existing part resolves to (a symlink leads somewhere). A relative
# <dest> is read from where this is run, as the reader will see it. A refusal writes nothing.
set -uo pipefail

src="${1:-}" dest="${2:-}"
[ -d "$src/tree" ] && [ -r "$src/change.patch" ] || {
  echo "materialize: $src has no tree/ and change.patch" >&2; exit 2; }
[ -n "$dest" ] && [ ! -e "$dest" ] || { echo "materialize: <dest> must be a new path" >&2; exit 2; }
src="$(cd "$src" && pwd -P)" || exit 2
name="$(basename "$src")"
case "$dest" in /*) abs="$dest" ;; *) abs="$PWD/$dest" ;; esac
# The real path: the deepest part of <dest> that exists, resolved, and the rest as written.
up="$abs" rest=""
while [ ! -d "$up" ]; do rest="/${up##*/}$rest"; up="${up%/*}"; up="${up:-/}"; done
real="$(cd "$up" && pwd -P)$rest" || exit 2
lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
for p in "$abs" "$real"; do
  case "$(lower "$p")" in
    *"$(lower "$name")"*) echo "materialize: $p names the sample $name — a reader given it is told the answer; choose a neutral path" >&2
                          exit 2 ;;
  esac
done

g() {
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
    git -C "$dest" -c user.name=trellis -c user.email=trellis@example.invalid "$@"
}
mkdir -p "$dest" && cp -R "$src/tree/." "$dest/" || exit 1
g init -q && g add -A && g commit -q -m "base" || exit 1
mkdir "$dest/.bionic" && mkdir -p "$dest/.git/info" && printf '.bionic/\n' >> "$dest/.git/info/exclude" || exit 1
a="$(g rev-parse HEAD)" || exit 1
g apply --index "$src/change.patch" && g commit -q -m "change" || exit 1
b="$(g rev-parse HEAD)" || exit 1
printf '%s..%s\n' "$a" "$b"
