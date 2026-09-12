#!/bin/bash
# HARD BLOCK: Prevents AI from running destructive database operations.
# [WALL: tests/protect-database.test.sh]
# Exit code 2 = block the tool call entirely in Claude Code hooks.
# Catches DROP, TRUNCATE, DELETE without WHERE, and ALTER TABLE...DROP
# via psql, mysql, sqlite3, and other common DB CLIs.
# Registered always-on in hooks/hooks.json; runs from the mounted plugin payload.

BIONIC_INPUT=$(cat)
COMMAND=$(echo "$BIONIC_INPUT" | jq -r '.tool_input.command // empty')

# Only check Bash commands
[ -z "$COMMAND" ] && exit 0

# ---------- the library, and the one question that scopes this wall ----------
#
# FAIL OPEN (task-engaged-session, 2026-09-03). This wall carried no library at all
# until now, so a missing one could never have silenced it; what it gains here is the
# engagement predicate, and that predicate cannot be evaluated without the library.
# Refusing every database command in every project on the machine because one file is
# missing would arm this wall in exactly the sessions Chris's ruling takes it out of.
# The direction is chosen by the cost of the mistake: a destructive command that slips
# through a broken plugin is one command, and the plugin being broken is loud.
BIONIC_LIB_WANT="context.sh refuse.sh root.sh run.sh session.sh"
# --- bionic-loader/v2 BEGIN
# Find the bionic library — pasted BYTE-IDENTICALLY into all 22 carriers, because a library
# cannot load itself. payload/scripts/lib/loader.sh owns this text and its header holds the
# long form; §N.1 of tests/cross-gate-agreement.test.sh pins and caps every copy, and
# tests/loader.test.sh drives the behaviour. BIONIC_LIB_WANT, set on the line above, names
# the basenames this hook sources; afterwards exactly one of BIONIC_LIB (a directory holding
# all of them) and BIONIC_LIB_MISSING is non-empty. CANDIDATES, each class reached only when
# the earlier one fails: (1) beside the hook in BOTH spellings, since `..` resolves after the
# payload/hooks symlink; (2) the marketplace source tree, read from the registry and never
# assumed; (3) the newest version in that marketplace's cache, by THREE-INTEGER compare —
# 1.10.0 beats 1.3.2, which a lexical sort gets backwards. (2) and (3) heal a partly damaged
# install, so one broken location cannot lock the user out of the repair (R-1 §(5)).
BIONIC_LIB=""; BIONIC_LIB_MISSING=""; BIONIC_LIB_CANDS=""
_bl_dir="$(dirname "$0")"; _bl_want="${BIONIC_LIB_WANT:-}"
_bl_try() {
  [ -n "${1:-}" ] || return 1
  if [ -z "$BIONIC_LIB_CANDS" ]; then BIONIC_LIB_CANDS="$1"; else BIONIC_LIB_CANDS="$BIONIC_LIB_CANDS, $1"; fi
  [ -d "$1" ] || return 1
  for _bl_f in $_bl_want; do [ -r "$1/$_bl_f" ] || return 1; done
  BIONIC_LIB="$1"
}
if ! _bl_try "$_bl_dir/../scripts/lib" && ! _bl_try "$_bl_dir/../payload/scripts/lib"; then
  _bl_pd="${BIONIC_PLUGINS_DIR:-${HOME:-/nonexistent}/.claude/plugins}"; _bl_mk=""
  if [ -r "$_bl_pd/installed_plugins.json" ]; then
    _bl_keys="$(jq -r '(.plugins // {}) | keys[] | select(startswith("bionic@"))' "$_bl_pd/installed_plugins.json" 2>/dev/null)"
    _bl_mk="${_bl_keys%%
*}"
    _bl_mk="${_bl_mk#bionic@}"
  fi
  if [ -n "$_bl_mk" ]; then
    _bl_src=""
    if [ -r "$_bl_pd/known_marketplaces.json" ]; then
      _bl_src="$(jq -r --arg mk "$_bl_mk" '.[$mk].source.path // empty' "$_bl_pd/known_marketplaces.json" 2>/dev/null)"
    fi
    if [ -n "$_bl_src" ]; then _bl_try "$_bl_src/payload/scripts/lib" || :; fi
    if [ -z "$BIONIC_LIB" ]; then
      _bl_best=""; _bl_bestk=""
      for _bl_v in "$_bl_pd/cache/$_bl_mk/bionic"/*; do
        [ -d "$_bl_v" ] || continue
        _bl_n="${_bl_v##*/}"
        case "$_bl_n" in ''|*[!0-9.]*) continue ;; esac
        _bl_x1=""; _bl_x2=""; _bl_x3=""
        IFS=. read -r _bl_x1 _bl_x2 _bl_x3 _bl_rest <<BIONIC_LOADER_VER
$_bl_n
BIONIC_LOADER_VER
        _bl_k="$(printf '%05d%05d%05d' "$((10#${_bl_x1:-0}))" "$((10#${_bl_x2:-0}))" "$((10#${_bl_x3:-0}))" 2>/dev/null)" || continue
        if [ -z "$_bl_bestk" ] || [ "$_bl_k" \> "$_bl_bestk" ]; then _bl_bestk="$_bl_k"; _bl_best="$_bl_n"; fi
      done
      if [ -n "$_bl_best" ]; then _bl_try "$_bl_pd/cache/$_bl_mk/bionic/$_bl_best/scripts/lib" || :; fi
    fi
  fi
fi
if [ -z "$BIONIC_LIB" ]; then
  BIONIC_LIB_MISSING="${_bl_want%% *}"
  [ -n "$BIONIC_LIB_MISSING" ] || BIONIC_LIB_MISSING="scripts/lib"
fi
loader_fail_open() {
  echo "$1: library ${BIONIC_LIB_MISSING:-the bionic library} not found at ${BIONIC_LIB_CANDS:-(no candidate)} — hook stepping aside; run /bionic:doctor" >&2
  exit 0
}
loader_fail_closed() {
  _bl_root="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd -P)" || _bl_root=""
  [ -n "$_bl_root" ] || _bl_root="$(dirname "$0")/.."
  case "${2:-}" in
    "claude plugin update bionic@bionic"|\
    "claude plugin install bionic@bionic"|\
    "bash $_bl_root/scripts/doctor.sh"|\
    "bash $_bl_root/scripts/setup.sh") exit 0 ;;
  esac
  _bl_who="${1:-a bionic hook}"
  if [ "${#_bl_who}" -gt 25 ]; then _bl_who="${_bl_who:0:24}…"; fi
  printf 'bionic: load refused — %s cannot load the bionic library (run /bionic:doctor)\n' "$_bl_who" >&2
  if [ "${BIONIC_WALL_VERBOSE:-}" = "1" ]; then
    cat >&2 <<BIONIC_LOADER_REFUSE
A wall that cannot read a command refuses it rather than waving it through.

Wanted: ${BIONIC_LIB_MISSING:-the bionic library}
Looked in: ${BIONIC_LIB_CANDS:-(no candidate)}

Until the plugin is whole again this wall permits exactly four commands, each matched
as a whole string:

    claude plugin update bionic@bionic
    claude plugin install bionic@bionic
    bash $_bl_root/scripts/doctor.sh
    bash $_bl_root/scripts/setup.sh

Anything else is refused, including one of those four with another command chained
after it. Run one of them, or act from your own terminal.
BIONIC_LOADER_REFUSE
  fi
  exit 2
}
# --- bionic-loader/v2 END
if [ -n "$BIONIC_LIB_MISSING" ]; then loader_fail_open "protect-database"; fi
# shellcheck source=/dev/null
. "$BIONIC_LIB/context.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/refuse.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/root.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/run.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/session.sh"

# ---------- THE ENGAGEMENT GUARD (AC-20): is this session bionic's at all? ----------
#
# FIRST, above every other question this hook asks. Chris, 2026-09-03: "all guardrails
# imposed by bionic should only apply when exercising bionic. Nothing should apply until
# bionic is triggered" — and the trigger is the canonical-sdlc skill, which writes
# `.bionic/tmp/engaged-<sid>.state` at the instant it is invoked. A session that never
# invoked it is one this wall has nothing to say to, and it says nothing: exit 0, no
# stdout, no stderr.
#
# EVERY UNREADABLE STATE READS AS NOT ENGAGED — absent marker, a symlink at the path, a
# foreign or unshaped session key, no key at all. The marker is the one artifact whose
# PRESENCE opens a wall, so the fail direction is inverted here on purpose: the arming
# partition is the consent boundary (1.3.2 close-out), and a wall that binds a session
# which never consented is the defect this guard exists to remove.
# [WALL: tests/protect-database.test.sh]
#
# THE CONTEXT IS ONE CALL (REQ-1f, lib/context.sh). It adopts the BIONIC_INPUT read
# above, resolves the cwd by the one ladder, the root, and the session id past the
# one shape guard, and returns 1 when it cannot identify the session at all.
bionic_context 2>/dev/null || exit 0
[ "$BIONIC_ENGAGED" = 1 ] || exit 0


# Uppercase for case-insensitive matching
CMD_UPPER=$(echo "$COMMAND" | tr '[:lower:]' '[:upper:]')

# Check if this involves a database CLI
if echo "$COMMAND" | grep -qEi '(psql|mysql|sqlite3|mongosh|mongo |clickhouse-client|cqlsh|cockroach sql|pg_|mariadb)\b'; then

  # DROP TABLE / DATABASE / SCHEMA / INDEX / COLLECTION / VIEW / FUNCTION / TRIGGER / PROCEDURE / SEQUENCE / TYPE
  # [WALL: tests/protect-database.test.sh]
  if echo "$CMD_UPPER" | grep -qE 'DROP\s+(TABLE|DATABASE|SCHEMA|INDEX|COLLECTION|VIEW|FUNCTION|TRIGGER|PROCEDURE|SEQUENCE|TYPE)'; then
    refuse exit2 sql "this command DROPs a database object" "run the migration yourself" \
      "The matched pattern is a DROP of a table, database, schema, index, collection, view, function, trigger, procedure, sequence or type. A migration run from your own terminal is the route."
  fi

  # TRUNCATE [WALL: tests/protect-database.test.sh]
  if echo "$CMD_UPPER" | grep -qE 'TRUNCATE\s'; then
    refuse exit2 sql "this command TRUNCATEs a table" "run the migration yourself" \
      "The matched pattern is TRUNCATE. A migration run from your own terminal is the route."
  fi

  # DELETE without WHERE (mass delete) — check per-statement to avoid multi-statement bypass
  # [WALL: tests/protect-database.test.sh]
  while IFS= read -r stmt; do
    stmt_upper=$(echo "$stmt" | tr '[:lower:]' '[:upper:]')
    if echo "$stmt_upper" | grep -qE 'DELETE\s+FROM\s' && ! echo "$stmt_upper" | grep -qE 'DELETE\s+FROM\s+\S+\s+WHERE\s'; then
      refuse exit2 sql "this DELETE has no WHERE clause" "add a WHERE clause" \
        "The matched pattern is a DELETE FROM with no WHERE in the same statement. An unbounded DELETE empties the table."
    fi
  done <<< "$(echo "$CMD_UPPER" | tr ';' '\n')"

  # ALTER TABLE ... DROP COLUMN [WALL: tests/protect-database.test.sh]
  if echo "$CMD_UPPER" | grep -qE 'ALTER\s+TABLE\s+.*DROP\s'; then
    refuse exit2 sql "this ALTER TABLE drops a column or key" "run the migration yourself" \
      "The matched pattern is an ALTER TABLE that DROPs. A migration run from your own terminal is the route."
  fi

  # MongoDB destructive operations (JavaScript method calls)
  # [WALL: tests/protect-database.test.sh]
  if echo "$COMMAND" | grep -qEi '(\.drop\(\)|\.dropDatabase\(\)|\.deleteMany\(\s*\{\s*\}\s*\))'; then
    refuse exit2 sql "this drops or wipes a MongoDB collection" "run it from your own terminal" \
      "The matched pattern is a collection drop, a database drop, or an unfiltered many-document delete. Run it from your own terminal if you mean it."
  fi
fi

# Also catch raw SQL piped or passed inline (e.g., echo "DROP TABLE..." | psql)
# [WALL: tests/protect-database.test.sh]
if echo "$CMD_UPPER" | grep -qE '(DROP\s+(TABLE|DATABASE|SCHEMA|VIEW|FUNCTION|TRIGGER|PROCEDURE)|TRUNCATE\s)' && echo "$COMMAND" | grep -qEi '(\|\s*(psql|mysql|sqlite3|mongosh)|<< )'; then
  refuse exit2 sql "destructive SQL is piped to a db client" "run the migration yourself" \
    "The matched pattern is a DROP or TRUNCATE piped or heredoc-fed into psql, mysql, sqlite3 or mongosh. Piping hides the statement from the argv check."
fi

exit 0
