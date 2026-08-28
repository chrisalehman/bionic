#!/bin/bash
# tests/doctor-version.test.sh — doctor.sh's installed-vs-latest version row
# (F5, epic-19 wave-01, spec AC-F5; design ledger
# .bionic/docs/record/epic-19/step2-design-ledger.md, T4 "OK"; grounding
# .bionic/docs/record/epic-19/step1-fixes-grounding.md item 5).
#
# THE CONTRACT UNDER TEST. Doctor's BIONIC NATIVE table carries a `version`
# row, answered per feed kind (payload/scripts/lib/detect.sh:detect_
# marketplace_feed_kind):
#   - git feed: compares the installed plugin.json against the marketplace's
#     CACHED CLONE (known_marketplaces.json's `installLocation`) — current is
#     one quiet ✓ line, lag names the exact repair command and also earns a
#     FIX_LINES_OTHER verdict line (`claude plugin update bionic@bionic`).
#   - directory feed: a remote-latest compare is meaningless there (the CLI
#     already runs that tree) — the row instead reuses the EXISTING registry-
#     sha/reconverge machinery (detect_registry_sha_lag +
#     detect_reconverge_hint), consumed rather than duplicated.
#   - feed kind unknown (no registry, no jq, no bionic entry): an honest
#     `unknown` line, never a guessed verdict.
#
# EXECUTED, NOT SOURCED — same posture as tests/doctor-patrol.test.sh: this
# drives the real payload/scripts/doctor.sh through the seams detect.sh
# already offers every caller (BIONIC_CLAUDE_HOME, BIONIC_PLUGIN_ROOT), with
# fixture `plugins/known_marketplaces.json` / `plugins/installed_plugins.json`
# files under a fixture claude-home rather than any mock of detect.sh itself.
#
# WHY THE DIRECTORY-FEED CASE FORCES ITS OWN PWD. detect_registry_sha_lag()
# compares `installed_plugins.json`'s recorded gitCommitSha against `git
# rev-parse HEAD` **of the caller's own $PWD** (doctor.sh calls it with no
# argument) — so that one case runs doctor from an explicit `(cd "$REPO" &&
# ...)` subshell rather than trusting how this suite itself was invoked.
#
# ASSERTION-HELPER RACE. No `printf | grep -q` anywhere below (tests/
# assert-helper-race.test.sh): containment is bash `[[ == * ]]` in-process,
# and the one awk extraction below (like doctor-patrol.test.sh's) reads to
# EOF rather than closing early.
#
# Usage: bash tests/doctor-version.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"

REPO="${BIONIC_SCRIPTS_DIR}"
PAYLOAD="${REPO}/payload"
DOCTOR_SH="${PAYLOAD}/scripts/doctor.sh"

command -v jq >/dev/null 2>&1 || { echo "doctor-version.test.sh: jq is required"; exit 1; }
command -v git >/dev/null 2>&1 || { echo "doctor-version.test.sh: git is required"; exit 1; }

PASS=0; FAIL=0; TOTAL=0
ok() { TOTAL=$((TOTAL + 1)); PASS=$((PASS + 1)); echo "PASS: $1"; }
no() { TOTAL=$((TOTAL + 1)); FAIL=$((FAIL + 1)); echo "FAIL: $1"; [ -n "${2:-}" ] && echo "      $2"; return 0; }

expect_true()  { local label="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$label"; else no "$label"; fi; }
expect_match() {
  local label="$1" pattern="$2" actual="$3"
  # shellcheck disable=SC2053  # RHS is a glob on purpose
  if [[ "$actual" == $pattern ]]; then ok "$label"; else no "$label" "no match for '$pattern' in: $(printf '%.400s' "$actual")"; fi
}
expect_no_match() {
  local label="$1" pattern="$2" actual="$3"
  # shellcheck disable=SC2053  # RHS is a glob on purpose
  if [[ "$actual" == $pattern ]]; then no "$label" "unexpected match for '$pattern'"; else ok "$label"; fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

expect_true "payload/scripts/doctor.sh exists" test -f "$DOCTOR_SH"

REAL_VERSION="$(jq -r '.version // empty' "${PAYLOAD}/.claude-plugin/plugin.json")"
expect_true "the real payload plugin.json carries a version" test -n "$REAL_VERSION"

# ---------- fixture builders ----------

# A claude-home carrying only the two registry files detect.sh's marketplace
# facts read (`_detect_known_marketplaces_file` / `_detect_installed_plugins_file`'s
# defaults, both under `<claude-home>/plugins/`).
make_registry_home() {  # -> claude-home dir on stdout
  local dir
  dir="$(mktemp -d -p "$TMP")"
  mkdir -p "$dir/plugins"
  printf '%s' "$dir"
}

write_known_marketplaces() {  # <claude-home> <source-json> <installLocation>
  jq -nc --argjson src "$2" --arg loc "$3" \
    '{bionic:{source:$src, installLocation:$loc, lastUpdated:"2026-08-27T00:00:00Z"}}' \
    > "$1/plugins/known_marketplaces.json"
}

write_empty_known_marketplaces() {  # <claude-home> — no bionic entry at all
  printf '{}' > "$1/plugins/known_marketplaces.json"
}

write_installed_plugins_sha() {  # <claude-home> <installPath> <gitCommitSha>
  jq -nc --arg path "$2" --arg sha "$3" \
    '{plugins:{"bionic@bionic":[{installPath:$path, gitCommitSha:$sha}]}}' \
    > "$1/plugins/installed_plugins.json"
}

# A git-feed marketplace's cached clone: `.claude-plugin/marketplace.json`
# naming bionic's plugin source (bionic ships this as the plain relative path
# "./payload" — .claude-plugin/marketplace.json in this very repo does the
# same), plus the plugin.json that source resolves to.
make_git_marketplace_clone() {  # <version> -> clone dir on stdout
  local version="$1" dir
  dir="$(mktemp -d -p "$TMP")"
  mkdir -p "$dir/.claude-plugin" "$dir/payload/.claude-plugin"
  jq -nc '{plugins:[{name:"bionic", source:"./payload"}]}' \
    > "$dir/.claude-plugin/marketplace.json"
  jq -nc --arg v "$version" '{name:"bionic", version:$v}' \
    > "$dir/payload/.claude-plugin/plugin.json"
  printf '%s' "$dir"
}

# ---------- driving doctor ----------

# `(cd "$REPO" && ...)` UNCONDITIONALLY, not only for the directory-feed case:
# it costs nothing for the git-feed/unknown cases and removes any dependence
# on how this suite itself was invoked, matching REPO's `git rev-parse HEAD`
# to what a run through tests/run.sh (which itself `cd`s to $REPO) would see.
run_doctor() {  # <claude-home>
  ( cd "$REPO" && BIONIC_CLAUDE_HOME="$1" BIONIC_PLUGIN_ROOT="$PAYLOAD" BIONIC_DOCTOR_PROBE_SECONDS=3 \
      bash "$DOCTOR_SH" < /dev/null 2>&1 )
}

# The version row alone — the one line in BIONIC NATIVE beginning with one of
# the three status glyphs followed by "version". Read to EOF (no `grep -q`
# early close, per assert-helper-race.test.sh).
version_row() {  # <full-output>
  printf '%s\n' "$1" | awk '/^  . version /'
}

echo "=== Section 1: git feed, installed == marketplace latest ==="

CLONE1="$(make_git_marketplace_clone "$REAL_VERSION")"
HOME1="$(make_registry_home)"
write_known_marketplaces "$HOME1" '{"source":"github","repo":"example/bionic"}' "$CLONE1"

OUT1="$(run_doctor "$HOME1")"
ROW1="$(version_row "$OUT1")"

expect_match "1: the row is a quiet checkmark" "*✓ version*${REAL_VERSION}*up to date*" "$ROW1"
expect_no_match "2: no update command rides the row when current" "*claude plugin update*" "$ROW1"
expect_no_match "3: no update-command verdict line prints when current" \
  "*claude plugin update bionic@bionic*" "$OUT1"

echo ""
echo "=== Section 2: git feed, installed lags the marketplace ==="

CLONE2="$(make_git_marketplace_clone "9.9.9")"
HOME2="$(make_registry_home)"
write_known_marketplaces "$HOME2" '{"source":"github","repo":"example/bionic"}' "$CLONE2"

OUT2="$(run_doctor "$HOME2")"
ROW2="$(version_row "$OUT2")"

expect_match "4: the row names installed and the exact update command" \
  "*✗ version*${REAL_VERSION}*9.9.9 available*claude plugin update bionic@bionic*" "$ROW2"
expect_match "5: the verdict area carries a matching fix line" \
  "*bionic ${REAL_VERSION} installed, 9.9.9 available*claude plugin update bionic@bionic*" "$OUT2"

echo ""
echo "=== Section 3: directory feed — reconverge integration, not a remote compare ==="

HOME3="$(make_registry_home)"
write_known_marketplaces "$HOME3" '{"source":"directory","path":"'"$REPO"'"}' "$REPO"
REPO_HEAD="$(git -C "$REPO" rev-parse HEAD)"
write_installed_plugins_sha "$HOME3" "$REPO" "$REPO_HEAD"

OUT3="$(run_doctor "$HOME3")"
ROW3="$(version_row "$OUT3")"

expect_match "6: a directory feed at the registered sha reads as a match, not a compare" \
  "*✓ version*${REAL_VERSION}*tree matches the registered cache*" "$ROW3"
expect_no_match "7: no marketplace-latest language leaks into the directory-feed row" \
  "*available*claude plugin update*" "$ROW3"

echo ""
echo "=== Section 4: feed kind cannot be determined — honest unknown, never a guess ==="

HOME4="$(make_registry_home)"
write_empty_known_marketplaces "$HOME4"

OUT4="$(run_doctor "$HOME4")"
ROW4="$(version_row "$OUT4")"

expect_match "8: the degraded case reads unknown with a stated cause" \
  "*– version*unknown —*" "$ROW4"
expect_no_match "9: a degraded feed kind never claims current or lag" \
  "*up to date*" "$ROW4"
expect_no_match "10: a degraded feed kind never prints an update command" \
  "*claude plugin update*" "$ROW4"

echo ""
echo "=== Section 5: registration ==="

# THE SUITE IS REGISTERED. tests/*.test.sh is NOT globbed by the runner
# (tests/run.sh hand-lists every suite by name) — see
# tests/doctor-patrol.test.sh's own registration case for the prior instance
# of this lesson.
expect_true "11: tests/run.sh names doctor-version.test.sh" \
  grep -q 'run "doctor-version.test.sh" bash tests/doctor-version.test.sh' "${BIONIC_SCRIPTS_DIR}/tests/run.sh"

echo ""
echo "========================================"
echo "doctor-version: $PASS/$TOTAL passed"
echo "========================================"

[ "$FAIL" -eq 0 ] || exit 1
