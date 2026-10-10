#!/bin/bash
# Tests for tests/lib/release-check.sh — this repo's `release-check:` command (wave-31 T1; spec
# D1, REQ-3 AC-3.5).
#
# THE CONTRACT THE DELETED PIN SUITE HELD THAT NO OTHER SUITE HOLDS: the CHANGELOG's newest
# heading equals `.version` in payload/.claude-plugin/plugin.json. The release check runs the
# name scan AND that pair, both read from the tree at BIONIC_CHECK_HEAD (default HEAD) with
# `git show`, so a check run in a dirty working tree judges what a push would publish.
#
#   §VERSION-PAIR   an agreeing pair passes; a doctored CHANGELOG heading and a doctored
#                   plugin.json version each fail with ONE line naming both versions; the check
#                   reads the HEAD tree, never the working files; BIONIC_CHECK_HEAD picks the tree.
#   §REFUSE         no list path, and a pair that cannot be read, are one-line refusals.
#   §SCAN           the name scan still runs under it: a listed entry planted in a committed
#                   file fails the check, beside the clean run on the same repository.
#
# FIXTURE FIDELITY: every repository is a real `git init` under a mktemp directory with real
# commits; nothing is a mock of git. The list file lives outside every checkout and holds one
# made-up entry. The real tree is never written. SYNTHESIZED: the versions and the entry.
#
# Usage: bash tests/release-check.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"

CHECK="${BIONIC_SCRIPTS_DIR}/tests/lib/release-check.sh"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/release-check-test.XXXXXX")" || exit 1
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid
export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
mkdir -p "$TMP/lists"

ENTRY="zq-alpha-7731"
LIST="$TMP/lists/names.list"
printf '%s\n' "$ENTRY" > "$LIST"

setup_section "fixtures"

[ -r "$CHECK" ] || { echo "FAIL: $CHECK is not readable"; exit 1; }
expect_false "setup: the list directory is outside every checkout" git -C "$TMP/lists" rev-parse --show-toplevel

# fx_changelog <version> — a CHANGELOG whose newest heading is <version>, older one below it
fx_changelog() {
  printf '# Changelog\n\n## %s — 2026-01-02\n\n- a change\n\n## 0.0.1 — 2026-01-01\n\n- first\n' "$1"
}
# fx_plugin <version>
fx_plugin() { printf '{\n  "name": "fixture",\n  "version": "%s"\n}\n' "$1"; }
# fx_repo <dir> <changelog version> <plugin version> — a committed pair
fx_repo() {
  mkdir -p "$1/payload/.claude-plugin" &&
  git -C "$1" init -q --template= &&
  git -C "$1" config commit.gpgsign false &&
  fx_changelog "$2" > "$1/CHANGELOG.md" && fx_plugin "$3" > "$1/payload/.claude-plugin/plugin.json" &&
  printf 'base\n' > "$1/a.txt" &&
  git -C "$1" add -A && git -C "$1" commit -q -m "first"
}
# run_check <repo> [args...] — sets OUT (stdout+stderr) and RC; the list is the default argument
run_check() {
  local repo="$1"; shift
  [ "$#" -gt 0 ] || set -- "$LIST"
  OUT="$(cd "$repo" && env -u BIONIC_CHECK_BASE -u BIONIC_CHECK_HEAD bash "$CHECK" "$@" 2>&1)"; RC=$?
}
# lines_of <text> — the number of non-empty lines
lines_of() { printf '%s\n' "$1" | awk 'NF { n++ } END { print n + 0 }'; }

section "§VERSION-PAIR — the newest CHANGELOG heading equals plugin.json's version, read from the HEAD tree"

R="$TMP/agree"; fx_repo "$R" 2.3.4 2.3.4
run_check "$R"
expect_status "(i) an agreeing pair, a clean scan: the check passes" 0 "$RC"
AGREE_OUT="$OUT"

R="$TMP/chg"; fx_repo "$R" 2.3.4 2.3.4
fx_changelog 2.3.5 > "$R/CHANGELOG.md"; git -C "$R" commit -q -am "doctor the heading"
run_check "$R"
expect_status "(ii) a doctored CHANGELOG heading: the check fails" 1 "$RC"
expect_contains "(ii) …and the line names the CHANGELOG's version" "2.3.5" "$OUT"
expect_contains "(ii) …and the line names the plugin's version" "2.3.4" "$OUT"
expect_eq "(ii) …in one line" "1" "$(lines_of "$OUT")"

R="$TMP/plg"; fx_repo "$R" 2.3.4 2.3.4
fx_plugin 2.3.9 > "$R/payload/.claude-plugin/plugin.json"; git -C "$R" commit -q -am "doctor the version"
run_check "$R"
expect_status "(iii) a doctored plugin.json version: the check fails" 1 "$RC"
expect_contains "(iii) …and the line names the plugin's version" "2.3.9" "$OUT"
expect_contains "(iii) …and the CHANGELOG's" "2.3.4" "$OUT"
expect_eq "(iii) …in one line" "1" "$(lines_of "$OUT")"

# (iv) the HEAD tree, not the working file: the working CHANGELOG disagrees, nothing is committed.
R="$TMP/dirty"; fx_repo "$R" 2.3.4 2.3.4
fx_changelog 7.7.7 > "$R/CHANGELOG.md"
expect_contains "(iv) setup: the working CHANGELOG really does disagree with the committed one" \
  "7.7.7" "$(cat "$R/CHANGELOG.md")"
expect_nonempty "(iv) setup: the repository really is dirty" "$(git -C "$R" status --porcelain)"
run_check "$R"
expect_status "(iv) a working CHANGELOG edited and not committed: the check still passes (HEAD is read)" 0 "$RC"
expect_eq "(iv) …and prints what the agreeing run prints" "$AGREE_OUT" "$OUT"

# BIONIC_CHECK_HEAD picks the tree: the bad commit is HEAD, the good one is HEAD~1.
R="$TMP/pick"; fx_repo "$R" 2.3.4 2.3.4
fx_changelog 2.3.5 > "$R/CHANGELOG.md"; git -C "$R" commit -q -am "doctor the heading"
run_check "$R"
expect_status "(v) the doctored HEAD fails" 1 "$RC"
OUT="$(cd "$R" && env -u BIONIC_CHECK_BASE BIONIC_CHECK_HEAD='HEAD~1' bash "$CHECK" "$LIST" 2>&1)"; RC=$?
expect_status "(v) …and BIONIC_CHECK_HEAD=HEAD~1 reads the agreeing tree and passes" 0 "$RC"

section "§REFUSE — no list path, and a pair that cannot be read, are one-line refusals"

R="$TMP/refuse"; fx_repo "$R" 2.3.4 2.3.4
OUT="$(cd "$R" && env -u BIONIC_CHECK_BASE -u BIONIC_CHECK_HEAD bash "$CHECK" 2>&1)"; RC=$?
expect_ne "(a) no list path: non-zero" "0" "$RC"
expect_eq "(a) …in one line" "1" "$(lines_of "$OUT")"
run_check "$R" "$TMP/lists/does-not-exist.list"
expect_ne "(b) a list path that is not there: non-zero" "0" "$RC"
expect_eq "(b) …in one line" "1" "$(lines_of "$OUT")"

R="$TMP/nohead"; fx_repo "$R" 2.3.4 2.3.4
printf '# Changelog\n\nno release heading here\n' > "$R/CHANGELOG.md"; git -C "$R" commit -q -am "no heading"
run_check "$R"
expect_ne "(c) a CHANGELOG with no release heading: non-zero" "0" "$RC"
expect_eq "(c) …in one line" "1" "$(lines_of "$OUT")"

R="$TMP/nover"; fx_repo "$R" 2.3.4 2.3.4
printf '{ "name": "fixture" }\n' > "$R/payload/.claude-plugin/plugin.json"; git -C "$R" commit -q -am "no version"
run_check "$R"
expect_ne "(d) a plugin.json with no version: non-zero" "0" "$RC"
expect_eq "(d) …in one line" "1" "$(lines_of "$OUT")"

section "§SCAN — the name scan still runs under the release check"

R="$TMP/scan"; fx_repo "$R" 2.3.4 2.3.4
run_check "$R"
expect_status "(e) setup: the clean repository passes" 0 "$RC"
printf 'a line holding %s in the middle\n' "$ENTRY" > "$R/b.txt"; git -C "$R" add -A; git -C "$R" commit -q -m "plant"
run_check "$R"
expect_status "(e) a listed entry planted in a committed file: the check fails" 1 "$RC"
expect_contains "(e) …and the scan's hit line is in the output" "HIT entry=1" "$OUT"
expect_absent "(e) …and the entry itself is never printed" "$ENTRY" "$OUT"

finish
