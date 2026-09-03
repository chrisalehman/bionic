#!/bin/bash
# tests/doctor-walls.test.sh — doctor's `walls` row (bionic 1.4.0,
# wave-bionic-1.4.0-update slice DOCTOR handoff 3.1, spec AC-15).
#
# THE CONTRACT UNDER TEST. AC-15: "Doctor verifies every fail-closed wall's
# library resolves and prints a row with a repair-phrased FIX line before the
# first refusal; intact → clean."
#
# The four walls are the four hooks the loader idiom replaced
# (payload/scripts/lib/loader.sh's header names them): protect-main and
# canonical-sdlc-evidence-gate, which refuse when they cannot read a command,
# and farm-out-reminder and background-suite-guard, which classify one. Each
# names the library basenames it sources; doctor resolves those THROUGH THE
# IDIOM ITSELF — `bionic_loader_pin` driven with `$0` set to the hook's own
# path — so this row can never disagree with what the hook will do at fire time.
#
# WHY THE FIXTURE IS A COPIED TREE. The row is about a DAMAGED install, and the
# only honest way to produce one is to damage a real one: the payload is copied
# with `cp -RL` (payload/hooks is a symlink to the top-level hooks/, so the copy
# must dereference), one library is deleted, and doctor is pointed at the copy
# through BIONIC_PLUGIN_ROOT. Nothing under the repo is touched.
#
# HERMETIC. HOME and BIONIC_PLUGINS_DIR are both overridden per run, so the
# loader's candidate (2) and (3) — the marketplace source tree and the plugin
# cache — resolve against an empty fixture registry instead of this machine's
# real ~/.claude, which would otherwise HEAL the damage and turn the row green.
#
# ASSERTION-HELPER RACE. No `printf | grep -q` anywhere below
# (tests/assert-helper-race.test.sh): containment is bash `[[ == * ]]`.
#
# Usage: bash tests/doctor-walls.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"

REPO="${BIONIC_SCRIPTS_DIR}"
PAYLOAD="${REPO}/payload"
DOCTOR_SH="${PAYLOAD}/scripts/doctor.sh"

PASS=0; FAIL=0; TOTAL=0
ok() { TOTAL=$((TOTAL + 1)); PASS=$((PASS + 1)); echo "PASS: $1"; }
no() { TOTAL=$((TOTAL + 1)); FAIL=$((FAIL + 1)); echo "FAIL: $1"; [ -n "${2:-}" ] && echo "      $2"; return 0; }
expect_true()  { local label="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$label"; else no "$label"; fi; }
expect_match() {
  local label="$1" pattern="$2" actual="$3"
  # shellcheck disable=SC2053  # RHS is a glob on purpose
  if [[ "$actual" == $pattern ]]; then ok "$label"; else no "$label" "no match for '$pattern' in: $(printf '%.600s' "$actual")"; fi
}
expect_no_match() {
  local label="$1" pattern="$2" actual="$3"
  # shellcheck disable=SC2053  # RHS is a glob on purpose
  if [[ "$actual" == $pattern ]]; then no "$label" "unexpected match for '$pattern'"; else ok "$label"; fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

expect_true "payload/scripts/doctor.sh exists" test -f "$DOCTOR_SH"

# ---------- the fixture plugin tree ----------
#
# `cp -RL`: payload/hooks is a symlink into the repo's top-level hooks/, and a
# copy that preserved the link would leave the fixture's walls pointing at the
# repo — where deleting a library would damage the checkout rather than the
# fixture.
PLUG="${TMP}/plug"
mkdir -p "$PLUG"
cp -RL "${PAYLOAD}/." "$PLUG/" 2>/dev/null

expect_true "the fixture tree carries the four wall hooks" \
  test -f "$PLUG/hooks/protect-main.sh" -a -f "$PLUG/hooks/background-suite-guard.sh"
expect_true "the fixture tree carries its own library" test -f "$PLUG/scripts/lib/git-argv.sh"

# An empty registry: no installed_plugins.json, no known_marketplaces.json, no
# cache. The loader's healing candidates therefore find nothing, which is what
# makes a deleted library actually missing rather than merely misplaced.
EMPTY_PLUGINS="${TMP}/no-plugins"
mkdir -p "$EMPTY_PLUGINS"

FIXTURE_RC="${TMP}/dot.zshrc"
: > "$FIXTURE_RC"

run_doctor() {  # -> doctor's whole output
  ( cd "$REPO" && HOME="$TMP" BIONIC_SHELL_RC="$FIXTURE_RC" \
      BIONIC_CLAUDE_HOME="$TMP/claude-home" BIONIC_PLUGIN_ROOT="$PLUG" \
      BIONIC_PLUGINS_DIR="$EMPTY_PLUGINS" BIONIC_DOCTOR_PROBE_SECONDS=3 \
      bash "$DOCTOR_SH" < /dev/null 2>&1 )
}
mkdir -p "$TMP/claude-home/plugins"

# LOCALE-SAFE BY CONSTRUCTION. The glyph that opens every row is three BYTES and
# one column, and awk's `.` matches a CHARACTER only under a UTF-8 locale. Under
# `LC_ALL=C` — the locale scripts/lib/width.sh exists for, and the one a stripped
# environment hands a hook — `/^  . wall/` matched nothing, this function returned
# the empty string, and all seven row assertions below failed as "no match … in: ''"
# while the FIX-line assertions kept passing. `[^ ]+` counts bytes or characters
# indifferently, so the filter now says the same thing in either locale.
walls_rows() {  # <full-output> -> the walls summary row and any per-wall rows
  printf '%s\n' "$1" | awk '/^  [^ ]+ wall/'
}

echo "=== Section 1: an intact tree — every wall's library resolves ==="

OUT1="$(run_doctor)"
ROWS1="$(walls_rows "$OUT1")"

expect_match "1: the walls row is a checkmark at four of four" "*✓ walls*4/4*" "$ROWS1"
expect_no_match "2: no per-wall failure row prints on an intact tree" "*cannot load*" "$ROWS1"
expect_no_match "3: no wall reaches the FIX section on an intact tree" \
  "*wall cannot load*" "$OUT1"

echo ""
echo "=== Section 2: one library deleted — the two walls that want it go red ==="

rm -f "$PLUG/scripts/lib/git-argv.sh"

OUT2="$(run_doctor)"
ROWS2="$(walls_rows "$OUT2")"

expect_match "4: the summary row drops to two of four and is a cross" "*✗ walls*2/4*" "$ROWS2"
expect_match "5: protect-main is named with the library it wanted" \
  "*protect-main*git-argv.sh*" "$ROWS2"
expect_match "6: the evidence gate is named with the library it wanted" \
  "*canonical-sdlc-evidence-gate*git-argv.sh*" "$ROWS2"
expect_no_match "7: a wall whose library is intact is not named" \
  "*background-suite-guard*" "$ROWS2"

expect_match "8: the FIX section carries the repair-phrased line" \
  "*protect-main*cannot load*git-argv.sh*→ run /bionic:setup — repair*" "$OUT2"

echo ""
echo "=== Section 3: the second library deleted — all four go red ==="

rm -f "$PLUG/scripts/lib/cmd-class.sh"

OUT3="$(run_doctor)"
ROWS3="$(walls_rows "$OUT3")"

expect_match "9: no wall resolves" "*✗ walls*0/4*" "$ROWS3"
expect_match "10: farm-out-reminder is named with cmd-class.sh" \
  "*farm-out-reminder*cmd-class.sh*" "$ROWS3"
expect_match "11: background-suite-guard is named with cmd-class.sh" \
  "*background-suite-guard*cmd-class.sh*" "$ROWS3"

echo ""
echo "=== Section 4: every line this report printed fits the column budget ==="

# lib/width.sh's rule, measured in COLUMNS: the glyph set is substituted away
# before the length is taken, exactly as bionic_cols does it.
too_wide() {  # <output> -> the offending lines, if any
  printf '%s\n' "$1" | awk '
    { s = $0
      gsub(/✓|✗|–|—|≥|…|·|→/, ".", s)
      if (length(s) > 100) print length(s) ": " $0 }'
}

for _n in 1 2 3; do
  eval "_out=\$OUT${_n}"
  _over="$(too_wide "$_out")"
  if [ -z "$_over" ]; then ok "12.${_n}: every line of run ${_n} fits 100 columns"
  else no "12.${_n}: a line of run ${_n} exceeds 100 columns" "$_over"; fi
done

echo ""
echo "walls: ${PASS}/${TOTAL} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ]
