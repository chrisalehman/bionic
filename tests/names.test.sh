#!/bin/bash
# tests/names.test.sh — two processes that make a name at once never make one name.
#
# WHY IT EXISTS. A subshell shares its parent's $$, and under bash 3.2 the children of a subshell that has drawn
# $RANDOM each draw the same next value: `( x=$RANDOM; ( echo $$.$RANDOM ) & ( echo $$.$RANDOM ) & wait )` prints
# one line twice. A counter is copied by the fork with the rest, so it collides the same way. lib/root.sh holds the
# two makers every shipped name goes through: `bionic_new`, an exclusive create (a file under noclobber, or a
# directory by mkdir) that draws again while the name is held, and `bionic_id`, an id that carries the asking
# process's own pid, read from a child it starts, since bash 3.2 has no $BASHPID.
#
# SECTIONS.
#   §SIBLINGS   under /bin/bash 3.2, two children of a subshell that drew $RANDOM each make a name with each maker, and the names differ
#   §SITES      no shipped shell file but the maker draws $RANDOM for a name
#
# HERMETIC. Each round runs in a directory of its own under this suite's temporary folder, and the makers write
# nowhere else. The shell is /bin/bash, the one the hooks run under on macOS; the control round shows the old shape
# collides under it, so a pass is the makers' and not a shell that happens to reseed its children.
#
# ANTI-VACUITY. Every round asserts both names were made (each a file, a directory or an id, non-empty) beside the
# assertion that they differ, and each maker has a mutant (the exclusive create made plain, the pid read as $$) that
# still makes names, which the same round then reads as one name.
#
# Usage: bash tests/names.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"

NM_LIB="$BIONIC_SCRIPTS_DIR/payload/scripts/lib"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# nm_round <lib dir> <kind> <dir> -> `<first>|<second>`, the names two sibling children of one subshell made, each
# made after the subshell drew $RANDOM. <kind>: file, dir, id, or old (the shape the makers replace).
nm_round() {
  mkdir -p "$3" || return 1
  /bin/bash -c '
    . "$1/root.sh" || exit 2
    k="$2"; d="$3"
    nm_make() {
      case "$k" in
        file) bionic_new "$d/n" && printf "%s\n" "$BIONIC_NEW" ;;
        dir)  bionic_new "$d/n" dir && printf "%s\n" "$BIONIC_NEW" ;;
        id)   bionic_id && printf "%s\n" "$BIONIC_ID" ;;
        old)  printf "%s\n" "$d/n.$$.$RANDOM" ;;
      esac
    }
    ( x=$RANDOM
      ( nm_make > "$d/a" ) &
      ( nm_make > "$d/b" ) &
      wait )
    printf "%s|%s\n" "$(cat "$d/a")" "$(cat "$d/b")"' _ "$1" "$2" "$3" 2>/dev/null
}
# nm_judge <kind> <a|b> -> `made` when both names are there (a file, a directory, or a non-empty id), then `|differ`
# or `|same`
nm_judge() {
  local a="${2%%|*}" b="${2#*|}" made=made
  case "$1" in
    file) [ -f "$a" ] && [ -f "$b" ] || made=missing ;;
    dir)  [ -d "$a" ] && [ -d "$b" ] || made=missing ;;
    *)    [ -n "$a" ] && [ -n "$b" ] || made=missing ;;
  esac
  if [ "$a" = "$b" ]; then echo "$made|same"; else echo "$made|differ"; fi
}
# nm_rounds <lib dir> <kind> <tag> -> one judgment per round, five rounds, space-separated
nm_rounds() {
  local r out=""
  for r in 1 2 3 4 5; do out="$out${out:+ }$(nm_judge "$2" "$(nm_round "$1" "$2" "$TMP/$3/$r")")"; done
  printf '%s' "$out"
}
NM_FIVE_DIFFER="made|differ made|differ made|differ made|differ made|differ"

section "§SIBLINGS: two sibling children of a subshell that drew \$RANDOM make two names with each maker"
NM_VER="$(/bin/bash -c 'echo "${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}"')"
expect_eq "precondition: /bin/bash is bash 3.2, the shell the collision is shown under" "3.2" "$NM_VER"
expect_eq "control: the old shape, \$\$ and \$RANDOM, gives the two siblings one name in every round" \
  "made|same made|same made|same made|same made|same" "$(nm_rounds "$NM_LIB" old old)"
expect_eq "bionic_new makes two files, one for each sibling, in every round" "$NM_FIVE_DIFFER" "$(nm_rounds "$NM_LIB" file file)"
expect_eq "bionic_new dir makes two directories, one for each sibling, in every round" "$NM_FIVE_DIFFER" "$(nm_rounds "$NM_LIB" dir dir)"
expect_eq "bionic_id makes two ids, one for each sibling, in every round" "$NM_FIVE_DIFFER" "$(nm_rounds "$NM_LIB" id id)"
NM_ONE="$(nm_round "$NM_LIB" id "$TMP/id-shape")"
expect_regex "…and an id is the sibling's own pid, a draw and its count: digits joined by dots" \
  '^[0-9]+\.[0-9]+\.[0-9]+\|[0-9]+\.[0-9]+\.[0-9]+$' "$NM_ONE"
expect_eq "…and the two ids differ in their pids, which are not the subshell's \$\$" "differ" \
  "$([ "${NM_ONE%%.*}" != "$(printf '%s' "${NM_ONE#*|}" | cut -d. -f1)" ] && echo differ || echo same)"
NM_TWICE="$(/bin/bash -c '. "$1/root.sh" && bionic_id && a="$BIONIC_ID" && bionic_id && echo "$a|$BIONIC_ID"' _ "$NM_LIB")"
expect_eq "two ids one process makes differ by their count" "1|2" \
  "$(printf '%s' "$NM_TWICE" | awk -F'|' '{ split($1, a, "."); split($2, b, "."); if (a[1] == b[1]) print a[3] "|" b[3] }')"
NM_NONE="$(/bin/bash -c '. "$1/root.sh"; bionic_new "$2/no-such-folder/n"; echo "$?|$BIONIC_NEW"' _ "$NM_LIB" "$TMP")"
expect_eq "bionic_new in a folder that is not there makes nothing and says so (rc 1, the name empty)" "1|" "$NM_NONE"
# The mutants: the exclusive create made a plain one, and the pid read as $$. Each still makes names, and the round
# reads the two siblings' names as one.
NM_MUT="$TMP/mut"; mkdir -p "$NM_MUT"; cp "$NM_LIB"/*.sh "$NM_MUT/"
anchor "$NM_LIB/root.sh" '      set -C' 1
sed -i.bak 's/^      set -C$/      set +C/' "$NM_MUT/root.sh"
expect_true "mutant: the plain create still parses" /bin/bash -n "$NM_MUT/root.sh"
expect_eq "MUTATION: with the create made plain, the siblings' two files are one file in every round" \
  "made|same made|same made|same made|same made|same" "$(nm_rounds "$NM_MUT" file mut-file)"
cp "$NM_LIB/root.sh" "$NM_MUT/root.sh"
anchor "$NM_LIB/root.sh" "  [ -n \"\$p\" ] || p=\"\$(exec /bin/sh -c 'echo \"\$PPID\"')\"" 1
sed -i.bak "s/^  \[ -n \"\$p\" \] || p=\"\$(exec \/bin\/sh -c 'echo \"\$PPID\"')\"$/  [ -n \"\$p\" ] || p=\$\$/" "$NM_MUT/root.sh"
expect_true "mutant: the pid read as \$\$ still parses" /bin/bash -n "$NM_MUT/root.sh"
expect_eq "MUTATION: with the pid read as \$\$, the siblings' two ids are one id in every round" \
  "made|same made|same made|same made|same made|same" "$(nm_rounds "$NM_MUT" id mut-id)"

section "§SITES: no shipped shell file but the maker draws \$RANDOM for a name"
# nm_draws -> each line of a shipped shell file that draws $RANDOM, comments out, as <file>:<line>:<text>
nm_draws() {
  ( cd "$BIONIC_SCRIPTS_DIR" && /usr/bin/grep -rn 'RANDOM' --include='*.sh' payload/scripts hooks ) \
    | /usr/bin/grep -v '^[^:]*:[0-9]*:[[:space:]]*#' || true
}
NM_DRAWS="$(nm_draws)"
expect_eq "the maker's own draw is read by the scan: lib/root.sh draws \$RANDOM at least once" "yes" \
  "$([ "$(printf '%s\n' "$NM_DRAWS" | /usr/bin/grep -c '^payload/scripts/lib/root\.sh:')" -ge 1 ] && echo yes || echo no)"
expect_eq "…and no other shipped shell file draws it" "" \
  "$(printf '%s\n' "$NM_DRAWS" | /usr/bin/grep -v '^payload/scripts/lib/root\.sh:' | /usr/bin/grep . || true)"

finish
