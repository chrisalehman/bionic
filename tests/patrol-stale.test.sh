#!/bin/bash
# THE SESSION-KEYED STATE CLASSES AND THEIR ONE OWNER RULE (payload/scripts/lib/patrol.sh
# PATROL_STATE_CLASSES): every class's file names its session up to the first dot, and the
# sweep and close-out's wipe read that owner the same way.
#
# SOURCED, DIRECTLY (patrol.sh's own header: "Sourced, never executed" — no
# top-level code runs on source, only assignments and function definitions,
# so this is safe the same way tests/detect-probes.test.sh sources detect.sh).
#
# Usage: bash tests/patrol-stale.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"

REPO="${BIONIC_SCRIPTS_DIR}"
PATROL_SH="${REPO}/payload/scripts/lib/patrol.sh"

# expect_eq, expect_true are the framework's (tests/lib/assert.sh) — identical
# semantics to the private definitions this suite carried (S7, AC-12).
expect_true "payload/scripts/lib/patrol.sh exists" test -f "$PATROL_SH"
expect_true "patrol.sh passes bash -n" bash -n "$PATROL_SH"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
REPO_FIX="$TMP/repo"
mkdir -p "$REPO_FIX"

sourced() {  # <fn-or-expr...> — run against a clean copy of patrol.sh's globals
  bash -c '. "$1"; shift; "$@"' _ "$PATROL_SH" "$@" 2>/dev/null
}

section "Section 4: one owner rule for every class: the name up to its first dot (wave-27 T68; review pass 47 S1, A-orch-137)"

# THE PER-START CLOCK FILE IS A CLASS (start-clock-<sid>.<agent id>.state). A session id holds no
# dot (lib/context.sh), an agent id may, so for every class a file's owner is the name after
# `<class>-` up to its first dot. patrol.sh reads it so (the sweep and doctor), and close-out's
# wipe (Step 8) reads it so: the classes come from PATROL_STATE_CLASSES, never from this file.
# fails-when: a class's files parse to another owner than before, the clock class is not a class,
# or close-out reads a clock file's owner as `<sid>.<id>` and spares it for ever.
CO_SH="${REPO}/payload/scripts/close-out.sh"
OW_SID="1a2b3c4d-1111-4e05-9f21-7d0c5a8e6b44"
OW_CLASSES="$(sed -n 's/^PATROL_STATE_CLASSES="\(.*\)"$/\1/p' "$PATROL_SH")"
expect_nonempty "OW0 PATROL_STATE_CLASSES is read off patrol.sh (the extractor works)" "$OW_CLASSES"
expect_contains "OW1 start-clock is one of the classes" " start-clock " " $OW_CLASSES "
expect_contains "OW1b owed is one of the classes (the person's ledger, T11/T12: a live neighbour's open items are spared by close-out's wipe)" " owed " " $OW_CLASSES "
expect_contains "OW1c tick-run is one of the classes (a running tick's record: close-out's wipe spares a live session's)" " tick-run " " $OW_CLASSES "
expect_contains "OW1d watch is one of the classes (the watch record: close-out's wipe spares a live session's)" " watch " " $OW_CLASSES "
OW_CO_FN="$(sed -n '/^_co_tmp_owner() {/,/^}/p' "$CO_SH")"
expect_nonempty "OW2 close-out's owner reader is read off close-out.sh (the extractor works)" "$OW_CO_FN"
OW_BAD_P=""; OW_BAD_C=""; OW_SEEN=0
for _ow_c in $OW_CLASSES; do
  for _ow_n in "$_ow_c-$OW_SID.state" "$_ow_c-$OW_SID.state.armed" "$_ow_c-$OW_SID.a1b2c3d4.state" "$_ow_c-$OW_SID.a.b@c.state"; do
    rm -rf "$REPO_FIX/.bionic"; mkdir -p "$REPO_FIX/.bionic/tmp"; : > "$REPO_FIX/.bionic/tmp/$_ow_n"
    _ow_p="$(sourced patrol_state_session_ids "$REPO_FIX")"
    _ow_o="$(bash -c 'PATROL_STATE_CLASSES="$1"; PATROL_STATE_ARMED_SUFFIX=.armed; eval "$2"; _co_tmp_owner "$3"' _ \
      "$OW_CLASSES" "$OW_CO_FN" "$_ow_n")"
    [ "$_ow_p" = "$OW_SID" ] || OW_BAD_P="$OW_BAD_P $_ow_n=[$_ow_p]"
    [ "$_ow_o" = "$OW_SID" ] || OW_BAD_C="$OW_BAD_C $_ow_n=[$_ow_o]"
    OW_SEEN=$((OW_SEEN + 1))
  done
done
expect_eq "OW3 every class's file, a per-start one too, parses to its session in patrol.sh" "" "$OW_BAD_P"
expect_eq "OW4 …and in close-out's wipe" "" "$OW_BAD_C"
rm -rf "$REPO_FIX/.bionic"; mkdir -p "$REPO_FIX/.bionic/tmp"
: > "$REPO_FIX/.bionic/tmp/start-clock-$OW_SID.a1b2.state"; : > "$REPO_FIX/.bionic/tmp/start-clock-$OW_SID.a9.state"
: > "$REPO_FIX/.bionic/tmp/roster-$OW_SID.state"; : > "$REPO_FIX/.bionic/tmp/start-clock-other.a1.state"
expect_eq "OW6 one session's files are its exact names and its per-start clock files" \
  "roster-$OW_SID.state start-clock-$OW_SID.a1b2.state start-clock-$OW_SID.a9.state" \
  "$(sourced patrol_session_state_files "$REPO_FIX" "$OW_SID" | sed 's|.*/||' | sort | tr '\n' ' ' | sed 's/ $//')"
mkdir "$REPO_FIX/.bionic/tmp/start-clock-$OW_SID.adir.state"
ln -s "$TMP/nowhere" "$REPO_FIX/.bionic/tmp/start-clock-$OW_SID.alink.state"
expect_eq "OW7 a directory or a link with a clock file's name is not one of them" \
  "roster-$OW_SID.state start-clock-$OW_SID.a1b2.state start-clock-$OW_SID.a9.state" \
  "$(sourced patrol_session_state_files "$REPO_FIX" "$OW_SID" | sed 's|.*/||' | sort | tr '\n' ' ' | sed 's/ $//')"

rm -rf "$REPO_FIX/.bionic"; mkdir -p "$REPO_FIX/.bionic/tmp"
: > "$REPO_FIX/.bionic/tmp/owed-$OW_SID.state"; : > "$REPO_FIX/.bionic/tmp/owed-other.state"
expect_eq "OW8 a session's owed store is one of its state files (the class list reaches it)" \
  "owed-$OW_SID.state" \
  "$(sourced patrol_session_state_files "$REPO_FIX" "$OW_SID" | sed 's|.*/||' | sort | tr '\n' ' ' | sed 's/ $//')"
expect_eq "OW8b …and close-out's wipe reads its owner as that session" "$OW_SID" \
  "$(bash -c 'PATROL_STATE_CLASSES="$1"; PATROL_STATE_ARMED_SUFFIX=.armed; eval "$2"; _co_tmp_owner "$3"' _ "$OW_CLASSES" "$OW_CO_FN" "owed-$OW_SID.state")"

finish
