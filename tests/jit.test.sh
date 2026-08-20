#!/bin/bash
# JIT / DEGRADATION — epic-17 wave-03 slice S10 (spec AC-5).
#
# WHAT THIS SUITE OWNS. payload/scripts/lib/jit.sh: the route-facing
# degradation contract — jit_check (presence + named fix) and jit_offer
# (states the offer, asks ONE consented question via deps.sh's install_dep,
# degrades cleanly on decline).
#
# THE OWNERSHIP-TABLE AGREEMENT (wave-03 spec §Design, "per-dep install" row):
# jit_offer must not grow a private second installer. It has to call install_dep
# BY NAME so the setup loop and a route's JIT offer always reach the identical
# function. Group 3 below proves that dynamically: it OVERRIDES install_dep
# with a recorder stub AFTER sourcing jit.sh and BEFORE calling jit_offer —
# bash resolves a function call by name at call time, so if jit_offer's "yes"
# path lands in the override, jit_offer contains no private copy of the
# install logic.
#
# HERMETIC, same regime as tests/plugin-lib.test.sh: no network, no live
# ~/.claude, PATH replaced outright with a controlled bin dir (real coreutils
# symlinked in, everything else a recorder stub).
#
# Usage: bash tests/jit.test.sh
# Registered by name in tests/run.sh (tests/*.test.sh is NOT auto-globbed).

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"

REPO="${BIONIC_SCRIPTS_DIR}"
JIT_SH="${REPO}/payload/scripts/lib/jit.sh"
DEPS_SH="${REPO}/payload/scripts/lib/deps.sh"

PASS=0; FAIL=0; TOTAL=0
ok() { TOTAL=$((TOTAL + 1)); PASS=$((PASS + 1)); echo "PASS: $1"; }
no() { TOTAL=$((TOTAL + 1)); FAIL=$((FAIL + 1)); echo "FAIL: $1"; [ -n "${2:-}" ] && echo "      $2"; return 0; }

expect_eq() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "expected '$2', got '$3'"; fi; }
expect_true() { local label="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$label"; else no "$label"; fi; }
expect_false() { local label="$1"; shift; if "$@" >/dev/null 2>&1; then no "$label" "expected non-zero exit"; else ok "$label"; fi; }
# Pattern match without a pipe: `printf | grep -q` is a SIGPIPE race under
# pipefail (tests/assert-helper-race.test.sh pins that lesson).
expect_match() {
  local label="$1" pattern="$2" actual="$3"
  # shellcheck disable=SC2053  # RHS is a glob on purpose
  if [[ "$actual" == $pattern ]]; then ok "$label"; else no "$label" "'$actual' does not match '$pattern'"; fi
}
expect_empty() { local label="$1" actual="$2"; if [ -z "$actual" ]; then ok "$label"; else no "$label" "expected empty, got '$actual'"; fi; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------------------
# Fixture builders (mirrors tests/plugin-lib.test.sh)
# ---------------------------------------------------------------------------

make_stub() {  # <bindir> <name> [exit-code]
  local bindir="$1" name="$2" rc="${3:-0}"
  mkdir -p "$bindir"
  cat > "${bindir}/${name}" <<STUB
#!/bin/bash
echo "${name} \$*" >> "\$BIONIC_TEST_CALLS"
exit ${rc}
STUB
  chmod +x "${bindir}/${name}"
}

BASE_BIN="$TMP/base-bin"
mkdir -p "$BASE_BIN"
for real in bash sh env cat grep sed awk mkdir rm cp mv chmod ls dirname basename tr head tail sort uniq wc jq python3; do
  p="$(command -v "$real" 2>/dev/null)" && ln -sf "$p" "${BASE_BIN}/${real}" 2>/dev/null
done

mkdir -p "$TMP/home"
CALLS="$TMP/calls.log"; : > "$CALLS"

# jit_run <env-assignments...> -- <function> [args]   — sources jit.sh (which
# sources deps.sh itself), then runs one function in a fresh bash.
jit_run() {
  local -a envs=()
  while [ $# -gt 0 ] && [ "$1" != "--" ]; do envs+=("$1"); shift; done
  shift  # drop --
  env -i \
    HOME="$TMP/home" \
    PATH="$BASE_BIN" \
    BIONIC_TEST_CALLS="$CALLS" \
    "${envs[@]}" \
    bash -c '. "$1"; shift; "$@"' _ "$JIT_SH" "$@" 2>&1
}

PRESENT_BIN="$TMP/present-bin"
cp -R "$BASE_BIN/." "$PRESENT_BIN/" 2>/dev/null || { mkdir -p "$PRESENT_BIN"; cp -R "$BASE_BIN/." "$PRESENT_BIN/"; }
make_stub "$PRESENT_BIN" rg
make_stub "$PRESENT_BIN" npm
make_stub "$PRESENT_BIN" brew

echo "=== Group 1: jit.sh exists, sources cleanly, passes bash -n ==="

expect_true "jit.sh exists" test -f "$JIT_SH"
expect_true "jit.sh sources without error" bash -c '. "$1"' _ "$JIT_SH"
expect_true "jit.sh passes bash -n" bash -n "$JIT_SH"
expect_true "jit.sh sourcing defines jit_check" \
  bash -c '. "$1"; declare -F jit_check' _ "$JIT_SH"
expect_true "jit.sh sourcing defines jit_offer" \
  bash -c '. "$1"; declare -F jit_offer' _ "$JIT_SH"
expect_true "sourcing jit.sh also pulls in deps.sh's check_dep (self-source guard)" \
  bash -c '. "$1"; declare -F check_dep' _ "$JIT_SH"

echo ""
echo "=== Group 2: jit_check — both arms ==="

expect_true "jit_check rg: present on PATH -> exit 0" \
  bash -c 'env -i HOME="$1" PATH="$2" bash -c ". \"\$1\"; jit_check rg" _ "$3"' _ "$TMP/home" "$PRESENT_BIN" "$JIT_SH"

ABSENT_OUT="$(jit_run PATH="$BASE_BIN" -- jit_check rg)"; ABSENT_RC=$?
expect_true "jit_check rg: absent from PATH -> exit 1" test "$ABSENT_RC" -ne 0
expect_match "jit_check rg absent: names the dependency" "*rg*" "$ABSENT_OUT"
expect_match "jit_check rg absent: names a fix (brew install ripgrep)" "*brew install ripgrep*" "$ABSENT_OUT"

PRESENT_OUT="$(env -i HOME="$TMP/home" PATH="$PRESENT_BIN" bash -c '. "$1"; jit_check rg' _ "$JIT_SH" 2>&1)"
expect_eq "jit_check rg present: prints nothing (no fix needed)" "" "$PRESENT_OUT"

expect_false "jit_check on an unknown dep exits non-zero" \
  bash -c '. "$1"; jit_check no-such-dep' _ "$JIT_SH"

echo ""
echo "=== Group 3: the ownership-table agreement — jit_offer calls install_dep BY NAME ==="
#
# Override install_dep AFTER sourcing jit.sh, BEFORE calling jit_offer. If
# jit_offer's "yes" path reaches the override, it has no private installer —
# it dispatches to whatever function is bound to that name, which in
# production is deps.sh's own single mutating entry point.

TRACE="$TMP/install-dep-trace.log"; : > "$TRACE"
env -i HOME="$TMP/home" PATH="$BASE_BIN" BIONIC_TEST_TRACE="$TRACE" \
  bash -c '
    . "$1"
    install_dep() { echo "install_dep-override $*" >> "$BIONIC_TEST_TRACE"; return 0; }
    echo y | jit_offer rg some-route "a capability" "it degrades"
  ' _ "$JIT_SH" >/dev/null 2>&1
expect_match "jit_offer(yes) reaches the function literally named install_dep" \
  "*install_dep-override rg*" "$(cat "$TRACE")"

echo ""
echo "=== Group 4: jit_offer — consent path invokes the real install_dep (production behavior) ==="

: > "$CALLS"
env -i HOME="$TMP/home" PATH="$PRESENT_BIN" BIONIC_TEST_CALLS="$CALLS" \
  bash -c 'echo y | { . "$1"; jit_offer rg some-route "fast search" "grep is used instead"; }' \
  _ "$JIT_SH" >/dev/null 2>&1
expect_match "jit_offer(yes) drives the real brew install (via install_dep)" \
  "*brew install ripgrep*" "$(cat "$CALLS")"

OFFER_YES_OUT="$(env -i HOME="$TMP/home" PATH="$PRESENT_BIN" BIONIC_TEST_CALLS="$CALLS" \
  bash -c 'echo y | { . "$1"; jit_offer rg some-route "fast search" "grep is used instead"; }' _ "$JIT_SH" 2>&1)"
expect_match "jit_offer(yes) states what is missing and what it enables" "*rg*" "$OFFER_YES_OUT"
expect_false "jit_offer(yes) does NOT print the degradation line on success" \
  bash -c '[[ "$1" == *"continues without"* ]]' _ "$OFFER_YES_OUT"

echo ""
echo "=== Group 5: jit_offer — declined path (AC-5's clean-degrade half) ==="

: > "$CALLS"
DECLINE_OUT="$(env -i HOME="$TMP/home" PATH="$PRESENT_BIN" BIONIC_TEST_CALLS="$CALLS" \
  bash -c '. "$1"; jit_offer rg some-route "fast search" "grep is used instead" </dev/null' _ "$JIT_SH")"
DECLINE_ERR="$(env -i HOME="$TMP/home" PATH="$PRESENT_BIN" BIONIC_TEST_CALLS="$CALLS" \
  bash -c '. "$1"; jit_offer rg some-route "fast search" "grep is used instead" </dev/null' _ "$JIT_SH" 2>&1 1>/dev/null)"
: > "$CALLS"
DECLINE_RC="$(env -i HOME="$TMP/home" PATH="$PRESENT_BIN" BIONIC_TEST_CALLS="$CALLS" \
  bash -c '. "$1"; jit_offer rg some-route "fast search" "grep is used instead" </dev/null; echo $?' _ "$JIT_SH" 2>/dev/null | tail -1)"

expect_true "jit_offer(decline, no stdin answer) returns non-zero" test "$DECLINE_RC" -ne 0
expect_match "jit_offer(decline) prints the contracted degradation line: <route> continues without <capability>: <what changes>" \
  "*some-route continues without fast search: grep is used instead*" "$DECLINE_OUT"
expect_empty "jit_offer(decline) writes nothing to stderr (no cryptic failure)" "$DECLINE_ERR"
expect_eq "jit_offer(decline) ran nothing (recorder empty — no mutation)" "0" \
  "$(grep -c . "$CALLS" | tr -d ' ')"

# Explicit "n" — the other spelling of decline.
: > "$CALLS"
DECLINE_N_OUT="$(env -i HOME="$TMP/home" PATH="$PRESENT_BIN" BIONIC_TEST_CALLS="$CALLS" \
  bash -c 'echo n | { . "$1"; jit_offer rg some-route "fast search" "grep is used instead"; }' _ "$JIT_SH" 2>&1)"
expect_match "jit_offer(explicit n) also prints the degradation line" \
  "*some-route continues without fast search: grep is used instead*" "$DECLINE_N_OUT"
expect_eq "jit_offer(explicit n) ran nothing" "0" "$(grep -c . "$CALLS" | tr -d ' ')"

echo ""
echo "=== Group 6: no assume-yes knob (S1-8 stands) ==="
#
# jit.sh must not grow an env-var bypass around consent — the same rule
# tests/plugin-lib.test.sh pins for install_dep itself.

# Matches an actual env-var-shaped bypass token (BIONIC_..._YES, ASSUME_YES=,
# etc.) — not this file's own prose ("no assume-yes knob"), which is
# lowercase-hyphenated and would false-positive a looser pattern.
expect_true "jit.sh source carries no assume-yes / auto-yes env-var bypass" \
  bash -c '! grep -qE "[A-Z_]*_(ASSUME|AUTO)_?YES|(ASSUME|AUTO)_?YES[A-Z_]*=" "$1"' _ "$JIT_SH"
expect_true "jit.sh reads stdin only through install_dep (no private read of its own)" \
  bash -c '! grep -qE "^[[:space:]]*read " "$1"' _ "$JIT_SH"

echo ""
echo "=== Group 7: mutation-and-restore — decline mutates NOTHING, proven twice, two mechanisms ==="
#
# Two independent fixture roots, two different install mechanisms (brew-dep
# and npm-global), fingerprinted before/after a decline each. A single proof
# could coincidentally hold for one mechanism's code path and not the other.

fingerprint() { find "$1" -type f -exec ls -l {} \; 2>/dev/null | awk '{print $5, $9}' | sort; }

# Mutation-and-restore #1: rg (brew-dep).
FP1_ROOT="$TMP/fp1"; mkdir -p "$FP1_ROOT"; cp -R "$PRESENT_BIN/." "$FP1_ROOT/bin/" 2>/dev/null || { mkdir -p "$FP1_ROOT/bin"; cp -R "$PRESENT_BIN/." "$FP1_ROOT/bin/"; }
: > "$CALLS"
FP1_BEFORE="$(fingerprint "$FP1_ROOT")"
env -i HOME="$TMP/home" PATH="$FP1_ROOT/bin" BIONIC_TEST_CALLS="$CALLS" \
  bash -c '. "$1"; jit_offer rg some-route "fast search" "grep is used instead" </dev/null' _ "$JIT_SH" >/dev/null 2>&1
FP1_AFTER="$(fingerprint "$FP1_ROOT")"
expect_eq "mutation-and-restore #1 (rg / brew-dep): fixture byte-identical after decline" "$FP1_BEFORE" "$FP1_AFTER"
expect_eq "mutation-and-restore #1: recorder log still empty" "0" "$(grep -c . "$CALLS" | tr -d ' ')"

# Mutation-and-restore #2: @playwright/cli (npm-global) — the canonical
# environment-class dep this slice was scoped around.
FP2_ROOT="$TMP/fp2"; mkdir -p "$FP2_ROOT"; cp -R "$PRESENT_BIN/." "$FP2_ROOT/bin/" 2>/dev/null || { mkdir -p "$FP2_ROOT/bin"; cp -R "$PRESENT_BIN/." "$FP2_ROOT/bin/"; }
: > "$CALLS"
FP2_BEFORE="$(fingerprint "$FP2_ROOT")"
env -i HOME="$TMP/home" PATH="$FP2_ROOT/bin" BIONIC_TEST_CALLS="$CALLS" \
  bash -c '. "$1"; jit_offer @playwright/cli browser-verify "browser driving" "T2/T3 rows are blocked, not silently skipped" </dev/null' \
  _ "$JIT_SH" >/dev/null 2>&1
FP2_AFTER="$(fingerprint "$FP2_ROOT")"
expect_eq "mutation-and-restore #2 (@playwright/cli / npm-global): fixture byte-identical after decline" "$FP2_BEFORE" "$FP2_AFTER"
expect_eq "mutation-and-restore #2: recorder log still empty" "0" "$(grep -c . "$CALLS" | tr -d ' ')"

echo ""
echo "=== Group 8: jit_check absence-vs-presence, driven against @playwright/cli too ==="

expect_true "jit_check @playwright/cli: present -> exit 0" \
  bash -c 'env -i HOME="$1" PATH="$2" BIONIC_TEST_CALLS="$3" bash -c ". \"\$1\"; jit_check @playwright/cli" _ "$4"' \
  _ "$TMP/home" "$PRESENT_BIN" "$CALLS" "$JIT_SH"
PW_ABSENT_OUT="$(jit_run PATH="$BASE_BIN" -- jit_check @playwright/cli)"; PW_ABSENT_RC=$?
expect_true "jit_check @playwright/cli: absent -> exit 1" test "$PW_ABSENT_RC" -ne 0
expect_match "jit_check @playwright/cli absent: names a fix (npm install -g)" \
  "*npm install -g @playwright/cli*" "$PW_ABSENT_OUT"

echo ""
echo "=== Group 9: route wiring — the two owner SKILL.md files name the contract ==="
#
# S2's dispatch-paragraph precedent: name the contract, let the script bind —
# no restated mechanics. One sentence each, at the point an environment-class
# dependency is assumed.

CANONICAL_SKILL="${REPO}/skills/canonical-sdlc/SKILL.md"
BROWSER_SKILL="${REPO}/skills/browser-verify/SKILL.md"
EXCALIDRAW_SKILL="${REPO}/skills/excalidraw-diagram/SKILL.md"

expect_true "canonical-sdlc SKILL.md names jit_check" grep -q 'jit_check' "$CANONICAL_SKILL"
expect_true "canonical-sdlc SKILL.md names jit_offer" grep -q 'jit_offer' "$CANONICAL_SKILL"
expect_true "browser-verify SKILL.md names jit_check" grep -q 'jit_check' "$BROWSER_SKILL"
expect_true "browser-verify SKILL.md names jit_offer" grep -q 'jit_offer' "$BROWSER_SKILL"
expect_true "excalidraw-diagram SKILL.md names jit_check" grep -q 'jit_check' "$EXCALIDRAW_SKILL"
expect_true "excalidraw-diagram SKILL.md names jit_offer" grep -q 'jit_offer' "$EXCALIDRAW_SKILL"

echo ""
echo "=== Group 10: the suite is registered in tests/run.sh by name ==="

expect_true "tests/run.sh names jit.test.sh" \
  grep -q 'run "jit.test.sh" bash tests/jit.test.sh' "${REPO}/tests/run.sh"

echo ""
echo "=== Group 11: excalidraw-diagram route fixes (epic-17 w4 S10, AC-10) ==="
#
# AC-10: the skill is a default-off opt-in (out of the payload since W1); its
# hardcoded ~/.claude/skills/ literal (a bootstrap-era assumption — that path
# is only where a manually-dropped personal skill happens to land, and hardcoding
# it ignores CLAUDE_CONFIG_DIR the same way deps.sh's roots section guards
# against) is replaced with the config-dir-aware form deps.sh already
# establishes; uv and playwright-chromium are its two dependency-table rows and both
# get the same one-sentence JIT-naming treatment as Group 9's two skills
# (proven above); the skill states its own default-off/opt-in status so the
# AC's language is traceable in the shipped doc, not just in this suite.

EXCALIDRAW_README="${REPO}/skills/excalidraw-diagram/README.md"

expect_true "excalidraw-diagram SKILL.md names uv's dependency-table row" grep -q '\buv\b' "$EXCALIDRAW_SKILL"
expect_true "excalidraw-diagram SKILL.md names playwright-chromium" grep -q 'playwright-chromium' "$EXCALIDRAW_SKILL"

expect_false "excalidraw-diagram SKILL.md carries no hardcoded ~/.claude/skills/ literal" \
  grep -q '~/\.claude/skills/' "$EXCALIDRAW_SKILL"
expect_false "excalidraw-diagram README.md carries no hardcoded ~/.claude/skills/ literal" \
  grep -q '~/\.claude/skills/' "$EXCALIDRAW_README"

expect_true "excalidraw-diagram SKILL.md uses the config-dir-aware path idiom" \
  grep -q 'CLAUDE_CONFIG_DIR' "$EXCALIDRAW_SKILL"
expect_true "excalidraw-diagram README.md uses the config-dir-aware path idiom" \
  grep -q 'CLAUDE_CONFIG_DIR' "$EXCALIDRAW_README"

expect_true "excalidraw-diagram SKILL.md states its default-off/opt-in status" \
  grep -qi 'default-off' "$EXCALIDRAW_SKILL"

echo ""
echo "========================================"
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
echo "========================================"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
