#!/bin/bash
# Tests for protect-database.sh Claude Code hook.
# Verifies that destructive database operations are blocked
# while safe operations are allowed.
#
# Usage: bash tests/protect-database.test.sh

set -euo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"

# THE SEAM IS hooks/bash-walls.sh (epic-23 wave-11-lean-spine, T23). This wall is a
# FUNCTION now — `wall_protect_database` in payload/scripts/lib/walls.sh — registered through
# the one PreToolUse|Bash command object that carries all five. Every case below drives
# that process, which is what a Bash tool call actually starts; the wall's own verdict is
# unchanged and tests/bash-walls.test.sh owns the composition the process adds.
HOOK="${BIONIC_HOOKS_DIR}/bash-walls.sh"

# ---------- the engaged fixture (task-engaged-session, AC-20) ----------
#
# Since 2026-09-03 this wall only speaks in a session that invoked the canonical-sdlc
# skill (Chris: "Nothing should apply until bionic is triggered"). The marker that
# records the invocation is `.bionic/tmp/engaged-<sid>.state` under the payload's project
# root, so every arm below now runs from a repo that has one — the world in which the
# question "does this wall still block the destructive statements" is the question
# anyone means.
#
# The unengaged world is not left untested; §8 at the bottom is that world, on the same
# commands, and it is what the marker's absence is proved against.
SANDBOX="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/pdb.XXXXXX")" && pwd -P)"
trap 'rm -rf "$SANDBOX"' EXIT
SID="0f1e2d3c-4b5a-4968-8877-665544332211"
ENGAGED_REPO="$SANDBOX/engaged"
PLAIN_REPO="$SANDBOX/plain"
mkdir -p "$ENGAGED_REPO/.bionic/tmp" "$PLAIN_REPO/.bionic/tmp"
: > "$ENGAGED_REPO/.bionic/tmp/engaged-$SID.state"
export HOME="$SANDBOX/home"
mkdir -p "$HOME"

# ---------- helpers ----------

# THE ENVIRONMENT AGREES WITH THE PAYLOAD. lib/session.sh takes the env value as primary
# and the payload as a witness, so a driver that left the RUNNER's own session id in the
# environment would have the hook looking for a marker this fixture never wrote — and
# every row below would pass for the wrong reason.
pdb_payload() {  # <cwd> <command>
  jq -n --arg s "$SID" --arg c "$1" --arg cmd "$2" \
    '{session_id:$s, cwd:$c, hook_event_name:"PreToolUse", tool_name:"Bash",
      tool_input:{command:$cmd}}'
}

run_hook() {
  local cmd="$1"
  pdb_payload "$ENGAGED_REPO" "$cmd" \
    | env CLAUDE_CODE_SESSION_ID="$SID" CLAUDE_PROJECT_DIR= bash "$HOOK" 2>/dev/null
}

expect_block() {
  local label="$1" cmd="$2"
  if run_hook "$cmd"; then
    no "$label" "expected BLOCK, got ALLOW"
  else
    ok "$label"
  fi
}

expect_allow() {
  local label="$1" cmd="$2"
  if run_hook "$cmd"; then
    ok "$label"
  else
    no "$label" "expected ALLOW, got BLOCK"
  fi
}

# ============================================================
# SECTION 1: DROP operations (must be BLOCKED)
# ============================================================

section "Section 1: DROP operations (must be BLOCKED)"

expect_block "psql DROP TABLE"              "psql -c 'DROP TABLE users'"
expect_block "psql DROP DATABASE"           "psql -c 'DROP DATABASE mydb'"
expect_block "psql DROP SCHEMA"             "psql -c 'DROP SCHEMA public CASCADE'"
expect_block "psql DROP INDEX"              "psql -c 'DROP INDEX idx_users_email'"
expect_block "psql DROP VIEW"               "psql -c 'DROP VIEW user_stats'"
expect_block "psql DROP FUNCTION"           "psql -c 'DROP FUNCTION get_user()'"
expect_block "psql DROP TRIGGER"            "psql -c 'DROP TRIGGER update_timestamp'"
expect_block "psql DROP PROCEDURE"          "psql -c 'DROP PROCEDURE cleanup_old_data'"
expect_block "psql DROP SEQUENCE"           "psql -c 'DROP SEQUENCE user_id_seq'"
expect_block "psql DROP TYPE"               "psql -c 'DROP TYPE status_enum'"
expect_block "mysql DROP TABLE"             "mysql -e 'DROP TABLE users'"
expect_block "sqlite3 DROP TABLE"           "sqlite3 test.db 'DROP TABLE users'"
expect_block "lowercase drop table"         "psql -c 'drop table users'"
expect_block "mixed case Drop Table"        "psql -c 'Drop Table users'"

# ============================================================
# SECTION 2: TRUNCATE operations (must be BLOCKED)
# ============================================================

section "Section 2: TRUNCATE operations (must be BLOCKED)"

expect_block "psql TRUNCATE"                "psql -c 'TRUNCATE users'"
expect_block "psql TRUNCATE TABLE"          "psql -c 'TRUNCATE TABLE users'"
expect_block "mysql TRUNCATE"               "mysql -e 'TRUNCATE TABLE orders'"
expect_block "lowercase truncate"           "psql -c 'truncate users'"

# ============================================================
# SECTION 3: DELETE without WHERE (must be BLOCKED)
# ============================================================

section "Section 3: DELETE without WHERE (must be BLOCKED)"

expect_block "DELETE FROM no WHERE"         "psql -c 'DELETE FROM users'"
expect_block "DELETE FROM lowercase"        "psql -c 'delete from users'"
expect_block "multi-stmt DELETE bypass"     "psql -c 'DELETE FROM users WHERE id=1; DELETE FROM logs'"

# ============================================================
# SECTION 4: ALTER TABLE DROP (must be BLOCKED)
# ============================================================

section "Section 4: ALTER TABLE DROP (must be BLOCKED)"

expect_block "ALTER TABLE DROP COLUMN"      "psql -c 'ALTER TABLE users DROP COLUMN email'"
expect_block "ALTER TABLE DROP CONSTRAINT"  "psql -c 'ALTER TABLE orders DROP CONSTRAINT fk_user'"

# ============================================================
# SECTION 5: MongoDB destructive ops (must be BLOCKED)
# ============================================================

section "Section 5: MongoDB destructive operations (must be BLOCKED)"

expect_block "mongosh dropDatabase"         "mongosh --eval 'db.dropDatabase()'"
expect_block "mongosh collection drop"      "mongosh --eval 'db.users.drop()'"
expect_block "mongosh deleteMany empty"     "mongosh --eval 'db.users.deleteMany({})'"

# ============================================================
# SECTION 6: Piped SQL (must be BLOCKED)
# ============================================================

section "Section 6: Piped SQL (must be BLOCKED)"

expect_block "echo DROP piped to psql"      "echo 'DROP TABLE users' | psql"
expect_block "echo TRUNCATE piped to mysql"  "echo 'TRUNCATE users' | mysql"

# ============================================================
# SECTION 7: Safe operations (must be ALLOWED)
# ============================================================

section "Section 7: Safe operations (must be ALLOWED)"

expect_allow "psql SELECT"                  "psql -c 'SELECT * FROM users'"
expect_allow "psql INSERT"                  "psql -c INSERT INTO users id VALUES 1"
expect_allow "psql UPDATE with WHERE"       "psql -c UPDATE users SET name=x WHERE id=1"
expect_allow "psql DELETE with WHERE"       "psql -c 'DELETE FROM users WHERE id = 5'"
expect_allow "psql CREATE TABLE"            "psql -c 'CREATE TABLE logs (id serial)'"
expect_allow "psql ALTER TABLE ADD"         "psql -c 'ALTER TABLE users ADD COLUMN age int'"
expect_allow "mysql SELECT"                 "mysql -e 'SELECT 1'"
expect_allow "non-database command"         "ls -la"
expect_allow "echo with DROP in string"     "echo 'The table was dropped yesterday'"
expect_allow "git command"                  "git status"
expect_allow "npm install"                  "npm install express"

# ============================================================
# SECTION 8: the unengaged session — the wall is not there at all (AC-20)
# ============================================================
#
# THE PAIR, on the same fixture and the same commands sections 1-6 refuse. Chris,
# 2026-09-03: "all guardrails imposed by bionic should only apply when exercising
# bionic. Nothing should apply until bionic is triggered." A session that never invoked
# the skill leaves no `.bionic/tmp/engaged-<sid>.state`, and this wall is then silent —
# not quieter, absent: exit 0, nothing on stdout, nothing on stderr.
#
# Every assertion here sits beside its positive twin above, on the same hook and the same
# command text, so neither half can pass by being vacuous.

section "Section 8: no engagement marker — silent on the very commands 1-6 block"

unengaged() {  # <label> <command> — expect exit 0, empty stdout, empty stderr
  local label="$1" cmd="$2" out err st=0
  out=$(pdb_payload "$PLAIN_REPO" "$cmd" \
          | env CLAUDE_CODE_SESSION_ID="$SID" CLAUDE_PROJECT_DIR= bash "$HOOK" 2>"$SANDBOX/.err") || st=$?
  err=$(cat "$SANDBOX/.err")
  if [ "$st" = "0" ] && [ -z "$out" ] && [ -z "$err" ]; then
    ok "$label"
  else
    no "$label" "exit=$st stdout=[$out] stderr=[$err]"
  fi
}

unengaged "AC-20 the DROP arm of section 1 passes an unengaged session" "psql -c 'DROP TABLE users'"
unengaged "AC-20 ...the TRUNCATE arm of section 2 passes"               "psql -c 'TRUNCATE users'"
unengaged "AC-20 ...the unqualified DELETE arm of section 3 passes"     "psql -c 'DELETE FROM users'"
unengaged "AC-20 ...the ALTER arm of section 4 passes"                  "psql -c 'ALTER TABLE users DROP COLUMN age'"
unengaged "AC-20 ...the mongo arm of section 5 passes"                  "mongosh --eval 'db.dropDatabase()'"
unengaged "AC-20 ...the piped-SQL arm of section 6 passes"              "echo 'DROP TABLE users' | psql"

# A MARKER THAT IS A SYMLINK IS NOT A MARKER (lib/run.sh: `-L` is refused before it is
# followed). Planted here rather than reasoned about: it is the one shape something could
# create inside a repo to open every wall on the machine from outside it.
ln -s "$ENGAGED_REPO/.bionic/tmp/engaged-$SID.state" "$PLAIN_REPO/.bionic/tmp/engaged-$SID.state"
unengaged "AC-20 ...a SYMLINK at the marker path is not engagement" "psql -c 'DROP TABLE users'"
rm -f "$PLAIN_REPO/.bionic/tmp/engaged-$SID.state"

# A FOREIGN SESSION'S MARKER IS NOT THIS SESSION'S. The path interpolates the key, so
# that file is simply never looked at — asserted rather than assumed.
: > "$PLAIN_REPO/.bionic/tmp/engaged-11111111-2222-3333-4444-555555555555.state"
unengaged "AC-20 ...another session's marker is not engagement" "psql -c 'DROP TABLE users'"

# ============================================================
section "AC-E1.3/E1.5: every refusal is one line, in the criterion's shape"
# ============================================================
#
# fails-when: a refusal reaches the user as more than one VERDICT line, or in any
# shape but `bionic: <verb> refused — <fact> (<fix ≤ 40 cols>)`. All six of this
# wall's refusal sites are tripped for real and each is asserted against the
# criterion's own regex and then against the exact wording the ruled table gives it
# (s12-refusal-wording-draft.md §1 rows 5 through 10).
#
# AC-E1.3 IS ABOUT THE VERDICT, AND ADR-030 MADE THAT DISTINCTION VISIBLE (epic-23
# wave-16 T4/T19). `exit2`'s field 9 (`detail_to_user`) is `yes` now, so the pattern
# that matched — the value the one line had no room for — rides the same wire as the
# verdict, bounded, with no knob needed. Until that flip, "the user stream is one
# line" and "the verdict is one line" were the same measurement on `exit2`, and this
# helper took the cheaper one. What AC-E1.3 actually asks for — a sentence the reader
# is interrupted by, never wrapped — is the VERDICT, so that is what is counted and
# compared below; the detail is asserted present as well, with a POSITIVE beside the
# narrowed count, so a wall that went silent still fails a check that used to catch
# it (bash-walls.test.sh / protect-main.test.sh, T4, A-T4.9).

PDB_LINE_RE='^bionic: [a-z-]+ refused — .+ \(.{1,40}\)$'
pdb_stderr() {  # <command> -> the hook's stderr, verbatim
  pdb_payload "$ENGAGED_REPO" "$1" \
    | env CLAUDE_CODE_SESSION_ID="$SID" CLAUDE_PROJECT_DIR= bash "$HOOK" \
        2>"$SANDBOX/.err" >/dev/null || true
  cat "$SANDBOX/.err"
}

pdb_one_line() {  # <label> <command> <expected line>
  local _lbl="$1" _cmd="$2" _want="$3" _got _n _line _rest
  _got="$(pdb_stderr "$_cmd")"
  _n="$(/usr/bin/grep -c '^bionic: ' "$SANDBOX/.err" | tr -d ' ')"
  _line="$(/usr/bin/grep -m1 '^bionic: ' "$SANDBOX/.err")"
  # WHAT FOLLOWS THE VERDICT, if anything: the stream minus its rendered line(s).
  # Read here rather than asserted per caller, because every row below carries a
  # `detail` now and a row that stopped carrying one is the regression worth seeing.
  _rest="$(/usr/bin/grep -v '^bionic: ' "$SANDBOX/.err" | /usr/bin/grep -c . | tr -d ' ')"
  if [ "$_n" = "1" ]; then ok "$_lbl: exactly one VERDICT line on the user stream"
  else no "$_lbl: exactly one VERDICT line on the user stream" "got $_n lines"; fi
  if printf '%s' "$_line" | /usr/bin/grep -qE "$PDB_LINE_RE"; then
    ok "$_lbl: in AC-E1.3's shape"
  else
    no "$_lbl: in AC-E1.3's shape" "line=[$_line]"
  fi
  if [ "$_line" = "$_want" ]; then ok "$_lbl: and it is the table's own wording"
  else no "$_lbl: and it is the table's own wording" "want [$_want] got [$_line]"; fi
  # THE POSITIVE THAT KEEPS THE COUNT HONEST (ADR-030, A-T4.9): the verdict is one
  # line BECAUSE the detail is a separate thing beneath it, not because the wall
  # went quiet.
  if [ "$_rest" -ge 1 ]; then
    ok "$_lbl: with its detail beneath it, no knob set"
  else
    no "$_lbl: with its detail beneath it, no knob set" "nothing after the verdict"
  fi
}

pdb_one_line "row 5 (a dropped object)" "psql -c 'DROP TABLE users'" \
  "bionic: sql refused — this command DROPs a database object (run the migration yourself)"
pdb_one_line "row 6 (an emptied table)" "psql -c 'TRUNCATE users'" \
  "bionic: sql refused — this command TRUNCATEs a table (run the migration yourself)"
pdb_one_line "row 7 (an unbounded DELETE)" "psql -c 'DELETE FROM users'" \
  "bionic: sql refused — this DELETE has no WHERE clause (add a WHERE clause)"
pdb_one_line "row 8 (a dropped column)" "psql -c 'ALTER TABLE users DROP COLUMN age'" \
  "bionic: sql refused — this ALTER TABLE drops a column or key (run the migration yourself)"
pdb_one_line "row 9 (a wiped collection)" "mongosh --eval 'db.dropDatabase()'" \
  "bionic: sql refused — this drops or wipes a MongoDB collection (run it from your own terminal)"
# THE HEREDOC FORM, not the client pipe: a command naming a client reaches the arms
# above first (the outer guard matches the same client names), so the piped-SQL arm is
# reachable only through the `<< ` half of its own condition. Measured, not assumed --
# the client-pipe spelling renders row 5's line.
pdb_one_line "row 10 (statement hidden in a heredoc)" \
  "$(printf 'bash << %s\nDROP TABLE users\nEOF\n' "'EOF'")" \
  "bionic: sql refused — destructive SQL is piped to a db client (run the migration yourself)"

# AC-E1.5 end to end through this wall, re-authored by ADR-030 (T19, A-T4.10's
# precedent): the branch/pattern name is the value the one line had no room for. It
# used to live behind the knob and nowhere else; `exit2` carries it to the reader
# now, with no knob needed, so what this pair holds is the SPLIT rather than the
# absence — the verdict line is still the ruled sentence and carries no detail, and
# the detail sentence is on the stream beneath it, no knob set. Asserted on the line
# and on the stream separately, so neither half can pass over an empty capture.
PDB_OFF="$(pdb_stderr "psql -c 'TRUNCATE users'")"
PDB_OFF_LINE="$(/usr/bin/grep -m1 '^bionic: ' "$SANDBOX/.err")"
case "$PDB_OFF_LINE" in
  *"The matched pattern"*) no "AC-E1.5 the matched pattern is NOT on the verdict line" ;;
  *) ok "AC-E1.5 the matched pattern is NOT on the verdict line" ;;
esac
case "$PDB_OFF" in
  *"The matched pattern is TRUNCATE"*) ok "AC-E1.5 …and it is beneath it, with no knob set at all" ;;
  *) no "AC-E1.5 …and it is beneath it, with no knob set at all" "got=[$PDB_OFF]" ;;
esac
# BIONIC_WALL_VERBOSE=1 still ADDS NOTHING THIS SUITE CAN TELL APART (A-T19.1): field
# 9 already puts the bounded detail on the wire, and every detail this wall composes
# is one sentence, well under the twelve-line bound, so the knob's "whole detail"
# and the channel's "bounded detail" are byte-identical here. The row stays — it is
# still true, and a wall that dropped the knob-set path entirely would still pass it
# — but it no longer discriminates the knob from the default for THIS wall's
# messages; only a >12-line detail would, and this wall has none. Kept for parity
# with the fleet's shape rather than deleted, and flagged here rather than silently
# left to look like it proves something it cannot.
pdb_payload "$ENGAGED_REPO" "psql -c 'TRUNCATE users'" \
  | env CLAUDE_CODE_SESSION_ID="$SID" CLAUDE_PROJECT_DIR= BIONIC_WALL_VERBOSE=1 \
      bash "$HOOK" 2>"$SANDBOX/.errv" >/dev/null || true
PDB_ON="$(cat "$SANDBOX/.errv")"
case "$PDB_ON" in
  *"The matched pattern"*) ok "AC-E1.5 …and BIONIC_WALL_VERBOSE=1 puts it there too" ;;
  *) no "AC-E1.5 …and BIONIC_WALL_VERBOSE=1 puts it there too" "got=[$PDB_ON]" ;;
esac
if printf '%s' "$PDB_ON" | head -1 | /usr/bin/grep -qE "$PDB_LINE_RE"; then
  ok "AC-E1.5 …with the one line still first"
else
  no "AC-E1.5 …with the one line still first"
fi

finish
