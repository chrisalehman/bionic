#!/bin/bash
# Tests for protect-database.sh Claude Code hook.
# Verifies that destructive database operations are blocked
# while safe operations are allowed.
#
# Usage: bash hooks/protect-database.test.sh

set -euo pipefail

HOOK="$(cd "$(dirname "$0")" && pwd)/protect-database.sh"
PASS=0
FAIL=0
TOTAL=0

# ---------- helpers ----------

run_hook() {
  local cmd="$1"
  echo "{\"tool_input\":{\"command\":\"$cmd\"}}" | bash "$HOOK" 2>/dev/null
}

expect_block() {
  local label="$1" cmd="$2"
  TOTAL=$((TOTAL + 1))
  if run_hook "$cmd"; then
    echo "FAIL (expected BLOCK): $label"
    FAIL=$((FAIL + 1))
  else
    echo "PASS: $label"
    PASS=$((PASS + 1))
  fi
}

expect_allow() {
  local label="$1" cmd="$2"
  TOTAL=$((TOTAL + 1))
  if run_hook "$cmd"; then
    echo "PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL (expected ALLOW): $label"
    FAIL=$((FAIL + 1))
  fi
}

# ============================================================
# SECTION 1: DROP operations (must be BLOCKED)
# ============================================================

echo ""
echo "=== Section 1: DROP operations (must be BLOCKED) ==="

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

echo ""
echo "=== Section 2: TRUNCATE operations (must be BLOCKED) ==="

expect_block "psql TRUNCATE"                "psql -c 'TRUNCATE users'"
expect_block "psql TRUNCATE TABLE"          "psql -c 'TRUNCATE TABLE users'"
expect_block "mysql TRUNCATE"               "mysql -e 'TRUNCATE TABLE orders'"
expect_block "lowercase truncate"           "psql -c 'truncate users'"

# ============================================================
# SECTION 3: DELETE without WHERE (must be BLOCKED)
# ============================================================

echo ""
echo "=== Section 3: DELETE without WHERE (must be BLOCKED) ==="

expect_block "DELETE FROM no WHERE"         "psql -c 'DELETE FROM users'"
expect_block "DELETE FROM lowercase"        "psql -c 'delete from users'"
expect_block "multi-stmt DELETE bypass"     "psql -c 'DELETE FROM users WHERE id=1; DELETE FROM logs'"

# ============================================================
# SECTION 4: ALTER TABLE DROP (must be BLOCKED)
# ============================================================

echo ""
echo "=== Section 4: ALTER TABLE DROP (must be BLOCKED) ==="

expect_block "ALTER TABLE DROP COLUMN"      "psql -c 'ALTER TABLE users DROP COLUMN email'"
expect_block "ALTER TABLE DROP CONSTRAINT"  "psql -c 'ALTER TABLE orders DROP CONSTRAINT fk_user'"

# ============================================================
# SECTION 5: MongoDB destructive ops (must be BLOCKED)
# ============================================================

echo ""
echo "=== Section 5: MongoDB destructive operations (must be BLOCKED) ==="

expect_block "mongosh dropDatabase"         "mongosh --eval 'db.dropDatabase()'"
expect_block "mongosh collection drop"      "mongosh --eval 'db.users.drop()'"
expect_block "mongosh deleteMany empty"     "mongosh --eval 'db.users.deleteMany({})'"

# ============================================================
# SECTION 6: Piped SQL (must be BLOCKED)
# ============================================================

echo ""
echo "=== Section 6: Piped SQL (must be BLOCKED) ==="

expect_block "echo DROP piped to psql"      "echo 'DROP TABLE users' | psql"
expect_block "echo TRUNCATE piped to mysql"  "echo 'TRUNCATE users' | mysql"

# ============================================================
# SECTION 7: Safe operations (must be ALLOWED)
# ============================================================

echo ""
echo "=== Section 7: Safe operations (must be ALLOWED) ==="

expect_allow "psql SELECT"                  "psql -c 'SELECT * FROM users'"
expect_allow "psql INSERT"                  "psql -c 'INSERT INTO users (name) VALUES ('"'"'test'"'"')'"
expect_allow "psql UPDATE with WHERE"       "psql -c 'UPDATE users SET name='"'"'x'"'"' WHERE id=1'"
expect_allow "psql DELETE with WHERE"       "psql -c 'DELETE FROM users WHERE id = 5'"
expect_allow "psql CREATE TABLE"            "psql -c 'CREATE TABLE logs (id serial)'"
expect_allow "psql ALTER TABLE ADD"         "psql -c 'ALTER TABLE users ADD COLUMN age int'"
expect_allow "mysql SELECT"                 "mysql -e 'SELECT 1'"
expect_allow "non-database command"         "ls -la"
expect_allow "echo with DROP in string"     "echo 'The table was dropped yesterday'"
expect_allow "git command"                  "git status"
expect_allow "npm install"                  "npm install express"

# ============================================================
# Results
# ============================================================

echo ""
echo "========================================"
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
echo "========================================"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
