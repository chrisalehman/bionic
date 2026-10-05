#!/bin/bash
# tests/lib/name-scan.sh <list path> — this project's release-time name scan (wave-27 D13).
#
# <list path> is a private list, one entry per line, kept OUTSIDE every git checkout (a list in
# a checkout would itself ship). Blank lines and lines starting with `#` are skipped but still
# counted, so an entry is named by its line number in the list. Each line is read as the scan
# will use it: a trailing space, tab or carriage return and a leading byte-order mark are
# stripped, and a line empty after that is skipped (counted, not an entry). Entries are fixed
# strings, matched case-insensitively. The scan runs in the checkout it is started from.
#
# WHAT IT READS is what a push would publish, never the working files:
#   - the files as committed at the head (`git grep` on the commit),
#   - the path names in the tree at the head (each file's full path, so a directory name too),
#   - the commit messages in base..head (`git log --grep`),
#   - the message of any annotated tag that points at the head.
# BIONIC_CHECK_BASE and BIONIC_CHECK_HEAD pick the range; the head defaults to HEAD and the
# base to the newest tag reachable from the head that does not point at the head itself, so a
# release already tagged is scanned as <previous tag>..<head> (no such tag: the whole history).
# A file it could not read as text (binary, a symlink) is named `UNREAD <path>`.
#
# A CLEAN RESULT MUST HAVE POWER. Before the real scan, the same four functions run over a
# throwaway repository whose one commit carries every entry in a file, in a file NAME, in its
# message and in an annotated tag message; an entry any of them cannot find there refuses the
# run (exit 2).
#
# NO ENTRY IS EVER PRINTED OR WRITTEN, and none is a word of any command line the scan runs
# (a pattern goes by file descriptor; the power check writes with builtins and reads the
# planted path from stdin). A hit is `HIT entry=<line number> at <where>`; a path
# that itself carries an entry is withheld, and a path hit is named `path #<n>`, the path's
# 1-based position in `git ls-tree -r --name-only` order. Every git trace variable is unset as
# a second line of defence. The throwaway lives in a temp directory removed on
# exit. Exit 0 clean (an empty list prints `entries=0`), 1 a hit, 2 a refusal.
#
# bash 3.2 (ADR-001). Not part of the shipped plugin.
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
# second line of defence: no entry is in any argv, but a trace file the caller's environment names
# would still record what git does see
for v in $(compgen -e); do case "$v" in GIT_TRACE*) unset "$v" ;; esac; done

refuse() { echo "name-scan: $*" >&2; exit 2; }

# ---- the four scan sites: each prints one <where> line per place <entry> is found -----------
#
# NO ENTRY IS A WORD OF ANY COMMAND LINE. A pattern reaches git by a file descriptor
# (`-f <(printf ...)`, printf being a builtin) and reaches awk the same way: the program reads
# its pattern from the first operand, a process substitution, before it reads the data on stdin.

# scan_files <repo> <head sha> <entry> -> `file <path>:<line>`
scan_files() {
  local repo="$1" head="$2" entry="$3" out rc rec path line
  # awk prints `<line>:<path>`: no control byte joins them, because bash 3.2 mishandles \001 in IFS
  out="$(set -o pipefail
    git -C "$repo" grep -n -z -i -F -I -f <(printf '%s\n' "$entry") "$head" -- 2>/dev/null \
      | tr '\0' '\001' | awk -F'\001' -v p="${#head}" '{ print $2 ":" substr($1, p + 2) }')"
  rc=$?
  [ "$rc" -le 1 ] || return 2
  [ -n "$out" ] || return 0
  while IFS= read -r rec; do
    line="${rec%%:*}"; path="${rec#*:}"
    printf 'file %s:%s\n' "$(path_label "$path")" "$line"
  done <<EOF
$out
EOF
}

# scan_paths <repo> <head sha> <entry> -> `path #<n>`: n is the 1-based position, in
# `git ls-tree -r --name-only` order, of each path that carries the entry. The path is never
# printed.
scan_paths() {
  local repo="$1" head="$2" entry="$3" out rc
  out="$(set -o pipefail
    git -C "$repo" ls-tree -r --name-only -z "$head" 2>/dev/null | tr '\0' '\001' \
      | awk 'BEGIN { getline e < ARGV[1]; close(ARGV[1]); ARGV[1] = ""; e = tolower(e); RS = "\001" }
             index(tolower($0), e) { print "path #" NR }' <(printf '%s\n' "$entry") -)"
  rc=$?
  [ "$rc" -eq 0 ] || return 2
  [ -z "$out" ] || printf '%s\n' "$out"
}

# scan_messages <repo> <base sha or ""> <head sha> <entry> -> `message <sha12>`
# Each commit is one NUL-terminated record, `<sha>\n<message>`; only the message is searched.
scan_messages() {
  local repo="$1" base="$2" head="$3" entry="$4" range="$3"
  [ -n "$base" ] && range="$base..$head"
  git -C "$repo" log -z --format='%H%n%B' "$range" 2>/dev/null | tr '\0' '\001' \
    | awk 'BEGIN { getline e < ARGV[1]; close(ARGV[1]); ARGV[1] = ""; e = tolower(e); RS = "\001" }
           { nl = index($0, "\n")
             if (nl && index(tolower(substr($0, nl + 1)), e)) print "message " substr($0, 1, 12) }' \
        <(printf '%s\n' "$entry") -
}

# scan_tags <repo> <head sha> <entry> -> `tag-message`, once per annotated tag at the head
scan_tags() {
  local repo="$1" head="$2" entry="$3" tag
  git -C "$repo" tag --points-at "$head" 2>/dev/null | while read -r tag; do
    [ "$(git -C "$repo" for-each-ref --format='%(objecttype)' "refs/tags/$tag" 2>/dev/null)" = tag ] || continue
    git -C "$repo" for-each-ref --format='%(contents)' "refs/tags/$tag" 2>/dev/null \
      | awk 'BEGIN { getline e < ARGV[1]; close(ARGV[1]); ARGV[1] = ""; e = tolower(e) }
             index(tolower($0), e) { f = 1 } END { exit f ? 0 : 1 }' <(printf '%s\n' "$entry") - \
      && echo "tag-message"
  done
}

# ---- paths are labels, not entries: one that carries an entry is withheld --------------------

path_label() {
  local lc i
  lc="$(printf '%s' "$1" | tr 'A-Z' 'a-z')"
  i=0
  while [ "$i" -lt "${#LC_ENTRIES[@]}" ]; do
    case "$lc" in *"${LC_ENTRIES[$i]}"*) printf '[path withheld]'; return 0 ;; esac
    i=$((i + 1))
  done
  printf '%s' "$1"
}

# ---- the throwaway: every entry in a file, a commit message and an annotated tag -------------

prove_power() {
  local tmp="$1" repo msg i head site found blob
  repo="$tmp/power"; msg="$tmp/power-msg"
  mkdir -p "$repo" || refuse "cannot build the power check under ${TMPDIR:-/tmp}"
  git -C "$repo" init -q --template= >/dev/null 2>&1 || refuse "cannot build the power check"
  : > "$msg"
  blob="$(git -C "$repo" hash-object -w --stdin </dev/null 2>/dev/null)" || refuse "cannot build the power check"
  i=0
  while [ "$i" -lt "${#ENTRIES[@]}" ]; do
    printf '%s\n' "${ENTRIES[$i]}" >> "$repo/entries.txt"
    printf '%s\n' "${ENTRIES[$i]}" >> "$msg"
    # the entry in a file NAME, planted in the index from stdin (a builtin printf), so it is no
    # word of a command line and the filesystem's naming rules do not apply
    printf '100644 %s\t%s\0' "$blob" "pn${NUMS[$i]}-${ENTRIES[$i]}-pn" \
        | git -C "$repo" update-index -z --index-info >/dev/null 2>&1 \
      || refuse "the entry on line ${NUMS[$i]} of the list cannot be planted in a path name; the path scan cannot be shown to have power"
    i=$((i + 1))
  done
  git -C "$repo" -c user.name=power -c user.email=power@example.invalid -c commit.gpgsign=false \
      -c core.hooksPath=/dev/null add entries.txt >/dev/null 2>&1 \
    && git -C "$repo" -c user.name=power -c user.email=power@example.invalid -c commit.gpgsign=false \
      -c core.hooksPath=/dev/null commit -q --cleanup=verbatim -F "$msg" >/dev/null 2>&1 \
    && git -C "$repo" -c user.name=power -c user.email=power@example.invalid -c tag.gpgsign=false \
      tag -a --cleanup=verbatim -F "$msg" power >/dev/null 2>&1 \
    || refuse "cannot build the power check"
  head="$(git -C "$repo" rev-parse --verify -q 'HEAD^{commit}')" || refuse "cannot build the power check"
  i=0
  while [ "$i" -lt "${#ENTRIES[@]}" ]; do
    for site in files paths messages tags; do
      case "$site" in
        files)    found="$(scan_files "$repo" "$head" "${ENTRIES[$i]}")" ;;
        paths)    found="$(scan_paths "$repo" "$head" "${ENTRIES[$i]}")" ;;
        messages) found="$(scan_messages "$repo" "" "$head" "${ENTRIES[$i]}")" ;;
        tags)     found="$(scan_tags "$repo" "$head" "${ENTRIES[$i]}")" ;;
      esac
      [ -n "$found" ] || refuse "the entry on line ${NUMS[$i]} of the list is not found by the $site scan in the throwaway commit; the scan has no power"
    done
    i=$((i + 1))
  done
}

# ---- main ------------------------------------------------------------------------------------

LIST="${1:-}"
[ -n "$LIST" ] || refuse "usage: name-scan.sh <list path> (a list kept outside every git checkout)"
[ -f "$LIST" ] && [ -r "$LIST" ] || refuse "the list is missing or unreadable"
LISTDIR="$(cd "$(dirname "$LIST")" 2>/dev/null && pwd -P)" || refuse "the list's directory cannot be read"
if git -C "$LISTDIR" rev-parse --show-toplevel >/dev/null 2>&1 || git -C "$LISTDIR" rev-parse --git-dir >/dev/null 2>&1; then
  refuse "the list is inside a git checkout; keep it outside every checkout"
fi

ENTRIES=(); LC_ENTRIES=(); NUMS=()
n=0
while IFS= read -r line || [ -n "$line" ]; do
  n=$((n + 1))
  line="${line#$'\357\273\277'}"
  while :; do
    case "$line" in *' '|*$'\t'|*$'\r') line="${line%?}" ;; *) break ;; esac
  done
  case "$line" in ''|'#'*) continue ;; esac
  ENTRIES[${#ENTRIES[@]}]="$line"
  LC_ENTRIES[${#LC_ENTRIES[@]}]="$(printf '%s' "$line" | tr 'A-Z' 'a-z')"
  NUMS[${#NUMS[@]}]="$n"
done < "$LIST"
if [ "${#ENTRIES[@]}" -eq 0 ]; then echo "entries=0"; exit 0; fi

REPO="$(git rev-parse --show-toplevel 2>/dev/null)" || refuse "not run inside a git checkout"
HEAD_SHA="$(git -C "$REPO" rev-parse --verify -q "${BIONIC_CHECK_HEAD:-HEAD}^{commit}")" \
  || refuse "the head does not resolve to a commit"
if [ -n "${BIONIC_CHECK_BASE:-}" ]; then
  BASE_SHA="$(git -C "$REPO" rev-parse --verify -q "${BIONIC_CHECK_BASE}^{commit}")" \
    || refuse "the base does not resolve to a commit"
else
  # the newest tag below the head: a tag that points at the head itself is the release being cut
  EXCL=()
  for t in $(git -C "$REPO" tag --points-at "$HEAD_SHA" 2>/dev/null); do EXCL[${#EXCL[@]}]="--exclude=$t"; done
  BASE_TAG="$(git -C "$REPO" describe --tags --abbrev=0 ${EXCL[@]+"${EXCL[@]}"} "$HEAD_SHA" 2>/dev/null)" || BASE_TAG=""
  BASE_SHA=""
  [ -z "$BASE_TAG" ] || BASE_SHA="$(git -C "$REPO" rev-parse --verify -q "refs/tags/$BASE_TAG^{commit}")"
fi

TMP_SCAN="$(mktemp -d "${TMPDIR:-/tmp}/name-scan.XXXXXX")" || refuse "cannot make a temp directory"
trap 'rm -rf "$TMP_SCAN"' EXIT

prove_power "$TMP_SCAN"

hits=0; i=0
while [ "$i" -lt "${#ENTRIES[@]}" ]; do
  where="$( { scan_files "$REPO" "$HEAD_SHA" "${ENTRIES[$i]}"; echo "rc=$?"; } )"
  case "$where" in *"rc=2") refuse "the file scan failed" ;; esac
  paths="$( { scan_paths "$REPO" "$HEAD_SHA" "${ENTRIES[$i]}"; echo "rc=$?"; } )"
  case "$paths" in *"rc=2") refuse "the path scan failed" ;; esac
  where="$(printf '%s\n%s\n' "$where" "$paths"
           scan_messages "$REPO" "$BASE_SHA" "$HEAD_SHA" "${ENTRIES[$i]}"
           scan_tags "$REPO" "$HEAD_SHA" "${ENTRIES[$i]}")"
  while IFS= read -r w; do
    case "$w" in ''|rc=*) continue ;; esac
    hits=$((hits + 1))
    printf 'HIT entry=%s at %s\n' "${NUMS[$i]}" "$w"
  done <<EOF
$where
EOF
  i=$((i + 1))
done

# files the text scan could not read: binary files and symlinks (an empty file has nothing to read)
unread=0
texts="$(git -C "$REPO" grep -I -l -z -e '' "$HEAD_SHA" -- 2>/dev/null | tr '\0' '\n' | cut -c$((${#HEAD_SHA} + 2))-)"
cands="$(git -C "$REPO" ls-tree -r -l -z "$HEAD_SHA" 2>/dev/null | tr '\0' '\n')"
unreadable="$({ printf '%s\n' "$texts" | sed 's/^/T /'; printf '%s\n' "$cands" | sed 's/^/C /'; } | awk '
  substr($0, 1, 2) == "T " { text[substr($0, 3)] = 1; next }
  substr($0, 1, 2) == "C " {
    rest = substr($0, 3); tab = index(rest, "\t"); if (!tab) next
    split(substr(rest, 1, tab - 1), m, " "); p = substr(rest, tab + 1)
    if (m[2] == "blob" && m[4] != 0 && !(p in text)) print p
  }')"
while IFS= read -r u; do
  [ -n "$u" ] || continue
  unread=$((unread + 1))
  printf 'UNREAD %s\n' "$(path_label "$u")"
done <<EOF
$unreadable
EOF

echo "entries=${#ENTRIES[@]} hits=$hits unread=$unread head=$(printf '%s' "$HEAD_SHA" | cut -c1-12) base=${BASE_SHA:-none}"
[ "$hits" -eq 0 ]
