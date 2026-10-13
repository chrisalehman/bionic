#!/bin/bash
# Tests for what /bionic:version and /bionic:doctor say runs (wave-36 T1, spec D7, ADR-055; AC-1.2).
# §LOADED.
#
# THE FACT UNDER TEST. A session started in a checkout through bionic's rc line runs the checkout
# (`--plugin-dir <root>/payload`), and the registry still names the installed release. The start
# hook records what was loaded; version.sh and doctor read a LIVE session's record before the
# registry, and print `bionic <v> (in place) · <commit> · <root>`. With no record, the registry's
# line, as before. Liveness is the fixture claude-home's own sessions directory, so nothing here
# reads the session that runs the suite.
#
# Usage: bash tests/doctor.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"

REPO="${BIONIC_SCRIPTS_DIR}"
PAYLOAD="${REPO}/payload"
VERSION_SH="${PAYLOAD}/scripts/version.sh"
DOCTOR_SH="${PAYLOAD}/scripts/doctor.sh"
[ -f "$VERSION_SH" ] && [ -f "$DOCTOR_SH" ] || { echo "doctor: version.sh or doctor.sh missing — suite refuses to run"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "doctor: jq absent — suite cannot run"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"
SID="11111111-2222-3333-4444-555555555555"

# THE TOOL DIRECTORY IS THE FIXTURE'S (the doctor-version.test.sh discipline): PATH is replaced, every
# program doctor runs is linked from the real one, `claude` is a stub that answers nothing, so no row
# reaches this machine's CLI.
BIN="$TMP/bin"; mkdir -p "$BIN"
for t in bash sh env cat grep sed awk mkdir rm cp mv chmod stat readlink ls tr head tail sort uniq wc cut \
         jq mktemp find xargs shasum uname date touch diff cmp printf true false sleep dirname basename \
         realpath id ps df sysctl vm_stat git strings; do
  p="$(command -v "$t" 2>/dev/null)" && ln -sf "$p" "$BIN/$t"
done
printf '#!/bin/sh\nexit 1\n' > "$BIN/claude"; chmod +x "$BIN/claude"
RC_FILE="$TMP/dot.zshrc"; : > "$RC_FILE"

# A checkout of the plugin at commit C.
CO="$TMP/checkout"; mkdir -p "$CO/payload/.claude-plugin"
printf '{"name":"bionic","version":"9.9.9"}\n' > "$CO/payload/.claude-plugin/plugin.json"
git -C "$CO" init -q && git -C "$CO" add -A && git -C "$CO" -c user.email=t@t -c user.name=t commit -qm co
C="$(git -C "$CO" rev-parse HEAD)"; R="$CO/payload"

# The registry: a GitHub install whose recorded sha is R_SHA, at a cache path that is not R.
REG_SHA="0123456789abcdef0123456789abcdef01234567"
H="$TMP/home"; mkdir -p "$H/plugins" "$H/sessions" "$TMP/cache"
jq -nc '{bionic:{source:{source:"github",repo:"example/bionic"},installLocation:"/nowhere"}}' > "$H/plugins/known_marketplaces.json"
jq -nc --arg p "$TMP/cache" --arg s "$REG_SHA" '{plugins:{"bionic@bionic":[{installPath:$p,gitCommitSha:$s}]}}' > "$H/plugins/installed_plugins.json"

P="$TMP/proj"; mkdir -p "$P/.bionic/tmp"
printf '{"pid":%s,"sessionId":"%s","cwd":"%s","startedAt":0}\n' "$$" "$SID" "$P" > "$H/sessions/$$.json"
record() {  # <sid> [<commit>]
  { printf 'root=%s\n' "$R"; [ -n "${2:-}" ] && printf 'commit=%s\n' "$2"; printf 'started=2026-10-13T20:00:00Z\n'; } \
    > "$P/.bionic/tmp/loaded-$1.state"
}

run_version() {  # [sid]
  ( cd "$P" && HOME="$TMP" PATH="$BIN" BIONIC_CLAUDE_HOME="$H" CLAUDE_CODE_SESSION_ID="${1:-$SID}" \
      BIONIC_SHELL_RC="$RC_FILE" bash "$VERSION_SH" 2>/dev/null )
}
run_doctor() {  # [sid]
  ( cd "$P" && HOME="$TMP" PATH="$BIN" BIONIC_CLAUDE_HOME="$H" CLAUDE_CODE_SESSION_ID="${1:-$SID}" \
      BIONIC_SHELL_RC="$RC_FILE" BIONIC_DOCTOR_PROBE_SECONDS=15 bash "$DOCTOR_SH" < /dev/null 2>/dev/null )
}

section "LOADED — no record: the registry's line"
V0="$(run_version)"
expect_match "LV1 version.sh: the installed line, the registry's sha" "bionic * (installed) · 01234567 · *" "$V0"
expect_no_match "LV2 …and not in place (positive: LV1)" "*in place*" "$V0"
D0="$(run_doctor | awk 'NR==1')"
expect_match "LD1 doctor's header: the payload and the registry's sha" "Bionic Doctor — payload * @ 01234567" "$D0"

section "LOADED — a live session's record naming root R at commit C"
record "$SID" "$C"
expect_eq "LV3 version.sh prints (in place) · C · R" "bionic 9.9.9 (in place) · ${C:0:8} · $R" "$(run_version)"
expect_no_match "LV4 …and the registry's sha is not on it" "*01234567*" "$(run_version)"
D1="$(run_doctor)"
expect_eq "LD2 doctor's header is the same line" "Bionic Doctor — bionic 9.9.9 (in place) · ${C:0:8} · $R" "$(printf '%s\n' "$D1" | awk 'NR==1')"
expect_match "LD3 …and the registration row says the install is not what runs" \
  "plugin source: *installed — not what this session runs*" "$(printf '%s\n' "$D1" | grep '^plugin source:')"

section "LOADED — a record that is not a live session's, or names no checkout"
DEAD="99999999-8888-7777-6666-555555555555"
record "$DEAD" "$C"
expect_match "LV5 another id's record, its session not live: the registry's line" "bionic * (installed) · 01234567 · *" "$(run_version "$DEAD")"
record "$SID"
expect_match "LV6 the live record names no commit (the cache): the registry's line" "bionic * (installed) · 01234567 · *" "$(run_version)"
D2="$(run_doctor | awk 'NR==1')"
expect_match "LD4 …and doctor's header is the registry's" "Bionic Doctor — payload * @ 01234567" "$D2"

finish
