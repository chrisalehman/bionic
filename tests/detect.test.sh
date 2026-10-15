#!/bin/bash
# Tests for the loaded-root reader in payload/scripts/lib/detect.sh (wave-36 T1, spec D7, ADR-055;
# AC-1.2). §LOADED.
#
# THE FACT UNDER TEST. A session started with `--plugin-dir <checkout>/payload` runs the checkout,
# and hooks/session-start.sh writes what it loaded to `.bionic/tmp/loaded-<sid>.state`. The verdict
# `detect_checkout_verdict` reads a LIVE session's record before the registry: a record naming a
# checkout commit is `in place`, and `detect_loaded_line` renders the one line version and doctor
# print. Live is the CLI's own session registry (`<claude-home>/sessions/<pid>.json`, pid alive),
# read through patrol.sh's one reader — so a suite pointing BIONIC_CLAUDE_HOME at a fixture never
# sees the session that launched it, whatever CLAUDE_CODE_SESSION_ID it inherited.
#
# Usage: bash tests/detect.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"

DETECT_SH="${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/detect.sh"
[ -f "$DETECT_SH" ] || { echo "detect: no library at $DETECT_SH — suite refuses to run"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "detect: jq absent — suite cannot run"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"

LIVE_SID="11111111-2222-3333-4444-555555555555"
LIVE2_SID="22222222-3333-4444-5555-666666666666"
DEAD_SID="99999999-8888-7777-6666-555555555555"
# A pid that was alive and is not: a child reaped before any row reads it.
sh -c 'exit 0' & DEAD_PID=$!; wait "$DEAD_PID" 2>/dev/null

# A checkout of the plugin, shaped as this repository is: payload/.claude-plugin/plugin.json names it.
CO="$TMP/checkout"
mkdir -p "$CO/payload/.claude-plugin"
printf '{"name":"bionic","version":"9.9.9"}\n' > "$CO/payload/.claude-plugin/plugin.json"
git -C "$CO" init -q && git -C "$CO" add -A && git -C "$CO" -c user.email=t@t -c user.name=t commit -qm co
CO_HEAD="$(git -C "$CO" rev-parse HEAD)"
CO_ROOT="$CO/payload"

# A claude-home: an empty registry (so the registry verdict is `unregistered`) and the live sessions.
H="$TMP/home"; mkdir -p "$H/plugins" "$H/sessions"
printf '{}' > "$H/plugins/known_marketplaces.json"
printf '{"plugins":{}}' > "$H/plugins/installed_plugins.json"
live_session() {  # <home> <pid> <sid> <cwd>
  printf '{"pid":%s,"sessionId":"%s","cwd":"%s","startedAt":0}\n' "$2" "$3" "$4" > "$1/sessions/$2.json"
}
P="$TMP/proj"; mkdir -p "$P/.bionic/tmp"
live_session "$H" "$$" "$LIVE_SID" "$P"
live_session "$H" "$DEAD_PID" "$DEAD_SID" "$P"

record() {  # <project> <sid> <root> [<commit>]
  { printf 'root=%s\n' "$3"; [ -n "${4:-}" ] && printf 'commit=%s\n' "$4"; printf 'started=2026-10-13T20:00:00Z\n'; } \
    > "$1/.bionic/tmp/loaded-$2.state"
}

# d <sid|-> <function> [args] — one library call in a fresh bash; `-` runs with no session id.
d() {
  local sid="$1"; shift
  if [ "$sid" = "-" ]; then
    env -u CLAUDE_CODE_SESSION_ID BIONIC_CLAUDE_HOME="$H" bash -c '. "$1"; shift; "$@"' _ "$DETECT_SH" "$@" 2>/dev/null
  else
    CLAUDE_CODE_SESSION_ID="$sid" BIONIC_CLAUDE_HOME="$H" bash -c '. "$1"; shift; "$@"' _ "$DETECT_SH" "$@" 2>/dev/null
  fi
}

section "LOADED — a live session's record is read before the registry"
record "$P" "$LIVE_SID" "$CO_ROOT" "$CO_HEAD"
expect_eq "L1 the asking session's record, when that session is live" \
  "$P/.bionic/tmp/loaded-$LIVE_SID.state" "$(d "$LIVE_SID" detect_loaded_record "$P")"
expect_eq "L2 the verdict reads it first: in place" "in place" "$(d "$LIVE_SID" detect_checkout_verdict "$TMP/elsewhere" "$P")"
expect_eq "L3 the line: version from the recorded root, commit's eight, the root" \
  "bionic 9.9.9 (in place) · ${CO_HEAD:0:8} · $CO_ROOT" "$(d "$LIVE_SID" detect_loaded_line "$P")"
expect_eq "L4 no project root: the registry's verdict, as before" "unregistered" "$(d "$LIVE_SID" detect_checkout_verdict "$TMP/elsewhere")"

section "LOADED — a record is not a live session's"
record "$P" "$DEAD_SID" "$CO_ROOT" "$CO_HEAD"
expect_empty "L5 a dead session's record is not read (positive: L1)" "$(d "$DEAD_SID" detect_loaded_record "$P")"
expect_eq "L6 …and the verdict falls to the registry" "unregistered" "$(d "$DEAD_SID" detect_checkout_verdict "$TMP/elsewhere" "$P")"
H_EMPTY="$TMP/home-empty"; mkdir -p "$H_EMPTY/plugins"
printf '{}' > "$H_EMPTY/plugins/known_marketplaces.json"
expect_empty "L7 a claude-home that lists no live session: nothing, whatever the inherited id" \
  "$(CLAUDE_CODE_SESSION_ID="$LIVE_SID" BIONIC_CLAUDE_HOME="$H_EMPTY" bash -c '. "$1"; detect_loaded_record "$2"' _ "$DETECT_SH" "$P" 2>/dev/null)"
live_session "$H" "$PPID" "$LIVE2_SID" "$P"   # a second live session: the suite's parent
expect_empty "L8 a live session with no record of its own reads none, not a neighbour's (positive: L1)" \
  "$(d "$LIVE2_SID" detect_loaded_record "$P")"
expect_eq "L9 …and its verdict is the registry's" "unregistered" "$(d "$LIVE2_SID" detect_checkout_verdict "$TMP/elsewhere" "$P")"

section "LOADED — no session id: the newest live record"
P2="$TMP/proj2"; mkdir -p "$P2/.bionic/tmp"
record "$P2" "$DEAD_SID" "$CO_ROOT" "$CO_HEAD"
record "$P2" "$LIVE_SID" "$CO_ROOT" "$CO_HEAD"
expect_eq "L10 from a terminal: the live session's record, never the dead one's" \
  "$P2/.bionic/tmp/loaded-$LIVE_SID.state" "$(d - detect_loaded_record "$P2")"

section "LOADED — only a checkout is in place"
P3="$TMP/proj3"; mkdir -p "$P3/.bionic/tmp"
record "$P3" "$LIVE_SID" "$TMP/cache/bionic/1.18.0"
expect_eq "L11 a record with no commit (the cache) is read" "$P3/.bionic/tmp/loaded-$LIVE_SID.state" "$(d "$LIVE_SID" detect_loaded_record "$P3")"
expect_eq "L12 …but is not in place: the registry speaks" "unregistered" "$(d "$LIVE_SID" detect_checkout_verdict "$TMP/elsewhere" "$P3")"
expect_empty "L13 …and there is no in-place line" "$(d "$LIVE_SID" detect_loaded_line "$P3")"

section "LOADED — a link is no record"
P4="$TMP/proj4"; mkdir -p "$P4/.bionic/tmp"
cp "$P/.bionic/tmp/loaded-$LIVE_SID.state" "$TMP/elsewhere.state"
ln -s "$TMP/elsewhere.state" "$P4/.bionic/tmp/loaded-$LIVE_SID.state"
expect_empty "L14 a link at the record path is not followed (positive: L1)" "$(d "$LIVE_SID" detect_loaded_record "$P4")"

section "LOADED — the field reader"
expect_eq "L15 detect_loaded_field reads a key" "$CO_HEAD" "$(d "$LIVE_SID" detect_loaded_field "$P/.bionic/tmp/loaded-$LIVE_SID.state" commit)"
expect_empty "L16 …and an absent key is empty (positive: L15)" "$(d "$LIVE_SID" detect_loaded_field "$P3/.bionic/tmp/loaded-$LIVE_SID.state" commit)"

finish
