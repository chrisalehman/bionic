#!/bin/bash
# tests/lib/name-scan.sh <list path> — this project's release-time name scan (wave-27 D13).
#
# <list path> is a private list, one entry per line, kept OUTSIDE every git checkout (a list in
# a checkout would itself ship). Blank lines and lines starting with `#` are skipped but still
# counted, so an entry is named by its line number in the list. Entries are fixed strings,
# matched case-insensitively. The scan runs in the checkout it is started from.
#
# WHAT IT READS is what a push would publish, never the working files:
#   - the files as committed at the head (`git grep` on the commit),
#   - the commit messages in base..head (`git log --grep`),
#   - the message of any annotated tag that points at the head.
# BIONIC_CHECK_BASE and BIONIC_CHECK_HEAD pick the range; the head defaults to HEAD and the
# base to the newest tag reachable from the head (no tag at all: the whole history).
# A file it could not read as text (binary, a symlink) is named `UNREAD <path>`.
#
# A CLEAN RESULT MUST HAVE POWER. Before the real scan, the same three functions run over a
# throwaway repository whose one commit carries every entry in a file, in its message and in
# an annotated tag message; an entry any of them cannot find there refuses the run (exit 2).
#
# NO ENTRY IS EVER PRINTED OR WRITTEN. A hit is `HIT entry=<line number> at <where>`; a path
# that itself carries an entry is withheld. The throwaway lives in a temp directory removed on
# exit. Exit 0 clean (an empty list prints `entries=0`), 1 a hit, 2 a refusal.
#
# bash 3.2 (ADR-001). Not part of the shipped plugin.
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE

refuse() { echo "name-scan: $*" >&2; exit 2; }

# ---- the three scan sites: each prints one <where> line per place <entry> is found ----------

# scan_files <repo> <head sha> <entry> -> `file <path>:<line>`
scan_files() {
  local repo="$1" head="$2" entry="$3" out rc path line
  out="$(set -o pipefail
    git -C "$repo" grep -n -z -i -F -I -e "$entry" "$head" -- 2>/dev/null \
      | tr '\0' '\001' | awk -F'\001' -v p="${#head}" '{ print substr($1, p + 2) "\001" $2 }')"
  rc=$?
  [ "$rc" -le 1 ] || return 2
  [ -n "$out" ] || return 0
  while IFS=$'\001' read -r path line; do
    printf 'file %s:%s\n' "$(path_label "$path")" "$line"
  done <<EOF
$out
EOF
}

# scan_messages <repo> <base sha or ""> <head sha> <entry> -> `message <sha12>`
scan_messages() {
  local repo="$1" base="$2" head="$3" entry="$4" range="$3" sha
  [ -n "$base" ] && range="$base..$head"
  git -C "$repo" log -i -F --grep="$entry" --format=%H "$range" 2>/dev/null | while read -r sha; do
    printf 'message %s\n' "$(printf '%s' "$sha" | cut -c1-12)"
  done
}

# scan_tags <repo> <head sha> <entry> -> `tag-message`, once per annotated tag at the head
scan_tags() {
  local repo="$1" head="$2" entry="$3" tag
  git -C "$repo" tag --points-at "$head" 2>/dev/null | while read -r tag; do
    [ "$(git -C "$repo" for-each-ref --format='%(objecttype)' "refs/tags/$tag" 2>/dev/null)" = tag ] || continue
    git -C "$repo" for-each-ref --format='%(contents)' "refs/tags/$tag" 2>/dev/null \
      | grep -q -i -F -e "$entry" && echo "tag-message"
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
  local tmp="$1" repo msg i head site found
  repo="$tmp/power"; msg="$tmp/power-msg"
  mkdir -p "$repo" || refuse "cannot build the power check under ${TMPDIR:-/tmp}"
  git -C "$repo" init -q --template= >/dev/null 2>&1 || refuse "cannot build the power check"
  : > "$msg"
  i=0
  while [ "$i" -lt "${#ENTRIES[@]}" ]; do
    printf '%s\n' "${ENTRIES[$i]}" >> "$repo/entries.txt"
    printf '%s\n' "${ENTRIES[$i]}" >> "$msg"
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
    for site in files messages tags; do
      case "$site" in
        files)    found="$(scan_files "$repo" "$head" "${ENTRIES[$i]}")" ;;
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
  line="${line%$'\r'}"
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
  BASE_TAG="$(git -C "$REPO" describe --tags --abbrev=0 "$HEAD_SHA" 2>/dev/null)" || BASE_TAG=""
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
  where="$(printf '%s\n' "$where"
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
