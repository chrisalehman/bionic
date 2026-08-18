#!/bin/bash
# PLUGIN LIB — epic-17 wave-03 slice S1 (spec AC-8, AC-3, AC-5).
#
# WHAT THIS SUITE OWNS. The two payload libraries that every later command
# consumes:
#
#   payload/scripts/lib/deps.sh    the dependency SSoT table + per-dep functions
#   payload/scripts/lib/detect.sh  the machine-fact functions (read-only)
#
# WHY THEY ARE PINNED HERE AND NOT IN A COMMAND SUITE. The ownership table
# (wave-03 spec §Design) makes deps.sh the single owner of the dependency set
# and detect.sh the single owner of machine facts; plugin.json and
# marketplace.json are RENDERINGS of the lane-3a rows. A rendering can only be
# pinned against a table whose own shape is already proven, so the table's
# shape is proven first, here, and the two manifest-agreement pins land on top
# of it (slice S3).
#
# HERMETIC — AND THE MEANING OF THAT WORD HERE. No network, no `claude` CLI, no
# live ~/.claude, no brew/npm/uv. Every fact-reading function is driven against
# a FIXTURE root planted in a temp dir and handed over by env var; every
# presence probe is driven against a FIXTURE PATH holding recorder stubs. The
# stubs are not a seam that substitutes the value under test: they are the
# real `command -v` / `npm list` / `claude` lookups, resolved against a
# directory this suite controls. install_dep's mutation therefore reaches a
# real execution, and its consent gate is proven by whether the recorder file
# appears — not by a dry-run flag the production path would never set.
#
# BOTH ARMS, ALWAYS. Every detect function is asserted present AND absent. An
# absence-only readback proves nothing: a function that always prints
# `present=no` would pass it.
#
# FIXTURE FIDELITY. Version strings and JSON shapes are copied from real
# command output captured on this machine (2026-08-17); the capture command is
# quoted in a comment beside each fixture.
#
# Usage: bash tests/plugin-lib.test.sh
# Registered by name in tests/run.sh (tests/*.test.sh is NOT auto-globbed).

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"

REPO="${BIONIC_SCRIPTS_DIR}"
DEPS_SH="${REPO}/payload/scripts/lib/deps.sh"
DETECT_SH="${REPO}/payload/scripts/lib/detect.sh"
# profile.sh is tests/profile.test.sh's subject; it is named here only for the
# one arm that needs doctor's load-out — both libraries sourced together — to
# reach detect_half_uninstalled's fourth term (Group 14, R-2).
PROFILE_SH="${REPO}/payload/scripts/lib/profile.sh"
PLUGIN_JSON="${REPO}/payload/.claude-plugin/plugin.json"
MARKETPLACE_JSON="${REPO}/.claude-plugin/marketplace.json"

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

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------------------
# Fixture builders
# ---------------------------------------------------------------------------

# A recorder stub: an executable that appends its own argv to $TMP/calls.log
# and exits 0. Used both as a presence probe target (`command -v rg`) and as
# the proof that install_dep did or did not reach a mutation.
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

# A bin dir carrying only what a hermetic run legitimately needs. PATH is
# replaced outright (not prefixed) so a real brew/npm on this machine can
# never be reached by accident.
BASE_BIN="$TMP/base-bin"
mkdir -p "$BASE_BIN"
for real in bash sh env cat grep sed awk mkdir rm cp mv chmod ls dirname basename tr head tail sort uniq wc jq python3; do
  p="$(command -v "$real" 2>/dev/null)" && ln -sf "$p" "${BASE_BIN}/${real}" 2>/dev/null
done

CALLS="$TMP/calls.log"; : > "$CALLS"

# lib_run <lib> <env-assignments...> -- <function> [args]
# Runs one library function in a fresh bash with a controlled environment.
lib_run() {
  local lib="$1"; shift
  local -a envs=()
  while [ $# -gt 0 ] && [ "$1" != "--" ]; do envs+=("$1"); shift; done
  shift  # drop --
  env -i \
    HOME="$TMP/home" \
    PATH="$BASE_BIN" \
    BIONIC_TEST_CALLS="$CALLS" \
    "${envs[@]}" \
    bash -c '. "$1"; shift; "$@"' _ "$lib" "$@" 2>&1
}

deps_run()   { lib_run "$DEPS_SH" "$@"; }
detect_run() { lib_run "$DETECT_SH" "$@"; }

mkdir -p "$TMP/home"

echo "=== Group 1: the library files exist and source cleanly ==="

expect_true "deps.sh exists" test -f "$DEPS_SH"
expect_true "detect.sh exists" test -f "$DETECT_SH"
expect_true "deps.sh sources without error" bash -c '. "$1"' _ "$DEPS_SH"
expect_true "detect.sh sources without error" bash -c '. "$1"' _ "$DETECT_SH"
expect_true "deps.sh passes bash -n" bash -n "$DEPS_SH"
expect_true "detect.sh passes bash -n" bash -n "$DETECT_SH"

echo ""
echo "=== Group 2: table parse + field access ==="

NAMES="$(deps_run -- dep_names)"
NAME_COUNT="$(printf '%s\n' "$NAMES" | grep -c .)"
expect_true "dep_names returns at least 20 rows (got ${NAME_COUNT})" test "$NAME_COUNT" -ge 20
expect_true "dep_names has no duplicates" \
  bash -c 'test "$(printf "%s\n" "$1" | sort | uniq -d | wc -l | tr -d " ")" = 0' _ "$NAMES"

# Every row carries exactly the six declared fields, in order.
FIELD_REPORT="$(deps_run -- dep_table_field_count_report)"
expect_eq "every table row has exactly 6 pipe-separated fields" "" "$FIELD_REPORT"

expect_eq "dep_field superpowers lane" "3a" "$(deps_run -- dep_field superpowers lane)"
expect_eq "dep_field superpowers source_url" "https://github.com/obra/superpowers.git" \
  "$(deps_run -- dep_field superpowers source_url)"
expect_eq "dep_field superpowers constraint" "^6.3.0" "$(deps_run -- dep_field superpowers constraint)"
expect_eq "dep_field superpowers install_fn_or_check" "native" \
  "$(deps_run -- dep_field superpowers install_fn_or_check)"
expect_eq "dep_field superpowers removal_behavior" "native-uninstall-offer" \
  "$(deps_run -- dep_field superpowers removal_behavior)"
expect_eq "dep_field rg source_url" "brew:ripgrep" "$(deps_run -- dep_field rg source_url)"
expect_eq "dep_field rg install_fn_or_check" "brew-dep" "$(deps_run -- dep_field rg install_fn_or_check)"

expect_false "dep_field on an unknown dep exits non-zero" \
  bash -c '. "$1"; dep_field no-such-dep lane' _ "$DEPS_SH"
expect_false "dep_field with an unknown field name exits non-zero" \
  bash -c '. "$1"; dep_field superpowers no_such_field' _ "$DEPS_SH"

expect_eq "dep_names_lane 3a returns exactly the two plugin-shaped deps" \
  "agent-skills superpowers" "$(deps_run -- dep_names_lane 3a | sort | tr '\n' ' ' | sed 's/ $//')"

echo ""
echo "=== Group 3: lane-3a rows are byte-exact (the manifest renderings pin here) ==="
#
# These two literals are the wave's ratified D1 values. agent-skills is ^0.6.0:
# the ^1.0.0 that plugin.json carries today is stale and D3 ratified the
# correction. Slice S3 renders plugin.json and marketplace.json FROM these
# rows, so a silent edit here would silently move both manifests.

expect_eq "lane-3a row: superpowers (byte-exact)" \
  "superpowers|3a|https://github.com/obra/superpowers.git|^6.3.0|native|native-uninstall-offer" \
  "$(deps_run -- dep_row superpowers)"
expect_eq "lane-3a row: agent-skills (byte-exact, ^0.6.0 not ^1.0.0)" \
  "agent-skills|3a|https://github.com/addyosmani/agent-skills.git|^0.6.0|native|native-uninstall-offer" \
  "$(deps_run -- dep_row agent-skills)"

echo ""
echo "=== Group 4: constraint-verdict logic (pure, fixture versions) ==="
#
# Fixture versions are real: 6.3.0 is superpowers' installed version on this
# machine — captured with
#   jq -r '.plugins["superpowers@claude-plugins-official"][0].version' \
#      ~/.claude/plugins/installed_plugins.json   ->  6.3.0

v() { deps_run -- dep_constraint_verdict "$1" "$2"; }

expect_eq "^6.3.0 vs 6.3.0 -> ok"        "ok"        "$(v '^6.3.0' 6.3.0)"
expect_eq "^6.3.0 vs 6.4.1 -> ok"        "ok"        "$(v '^6.3.0' 6.4.1)"
expect_eq "^6.3.0 vs 6.2.9 -> violation" "violation" "$(v '^6.3.0' 6.2.9)"
expect_eq "^6.3.0 vs 7.0.0 -> violation" "violation" "$(v '^6.3.0' 7.0.0)"
# The 0.x caret rule is not a corner case here — agent-skills IS a 0.x dep.
expect_eq "^0.6.0 vs 0.6.0 -> ok"        "ok"        "$(v '^0.6.0' 0.6.0)"
expect_eq "^0.6.0 vs 0.6.9 -> ok"        "ok"        "$(v '^0.6.0' 0.6.9)"
expect_eq "^0.6.0 vs 0.7.0 -> violation" "violation" "$(v '^0.6.0' 0.7.0)"
expect_eq "^0.6.0 vs 0.5.9 -> violation" "violation" "$(v '^0.6.0' 0.5.9)"
expect_eq "^0.6.0 vs 1.0.0 -> violation" "violation" "$(v '^0.6.0' 1.0.0)"
expect_eq "~1.2.3 vs 1.2.9 -> ok"        "ok"        "$(v '~1.2.3' 1.2.9)"
expect_eq "~1.2.3 vs 1.3.0 -> violation" "violation" "$(v '~1.2.3' 1.3.0)"
expect_eq ">=1.0.0 vs 2.0.0 -> ok"       "ok"        "$(v '>=1.0.0' 2.0.0)"
expect_eq ">=1.0.0 vs 0.9.0 -> violation" "violation" "$(v '>=1.0.0' 0.9.0)"
expect_eq "6.3.0 (exact) vs 6.3.0 -> ok" "ok"        "$(v '6.3.0' 6.3.0)"
expect_eq "6.3.0 (exact) vs 6.3.1 -> violation" "violation" "$(v '6.3.0' 6.3.1)"
expect_eq "any vs 0.0.1 -> ok"           "ok"        "$(v any 0.0.1)"
# `any` is a declaration that nothing is pinned, so it survives an unreadable
# version: there is no range left for that version to violate.
expect_eq "any vs unknown -> ok"         "ok"        "$(v any unknown)"
expect_eq "^6.3.0 vs unknown -> unknown" "unknown"   "$(v '^6.3.0' unknown)"
expect_eq "prerelease tag tolerated: ^6.3.0 vs 6.4.0-beta.1 -> ok" "ok" "$(v '^6.3.0' 6.4.0-beta.1)"
expect_eq "unparseable constraint -> unknown" "unknown" "$(v 'not-a-range' 1.0.0)"

echo ""
echo "=== Group 5: check_dep, lane-3a, against a fixture installed_plugins.json ==="
#
# Fixture shape copied from the real file, trimmed to one entry — captured with
#   jq '.plugins["superpowers@claude-plugins-official"]' \
#      ~/.claude/plugins/installed_plugins.json

plant_installed_plugins() {  # <dir> <key> <version>
  local dir="$1" key="$2" ver="$3"
  mkdir -p "${dir}/plugins"
  cat > "${dir}/plugins/installed_plugins.json" <<JSON
{
  "version": 2,
  "plugins": {
    "${key}": [
      {
        "scope": "user",
        "installPath": "/fixture/plugins/cache/${key}/${ver}",
        "version": "${ver}",
        "installedAt": "2026-07-25T23:09:41.851Z",
        "lastUpdated": "2026-08-15T03:09:39.671Z",
        "gitCommitSha": "3dcbd5c4b48e02263fbf4a3c01e3fe4f81d584d9"
      }
    ]
  }
}
JSON
}

CH_OK="$TMP/ch-ok"; plant_installed_plugins "$CH_OK" "superpowers@claude-plugins-official" "6.3.0"
CH_BAD="$TMP/ch-bad"; plant_installed_plugins "$CH_BAD" "superpowers@claude-plugins-official" "5.0.0"
CH_EMPTY="$TMP/ch-empty"; mkdir -p "$CH_EMPTY/plugins"
echo '{"version":2,"plugins":{}}' > "$CH_EMPTY/plugins/installed_plugins.json"

expect_eq "check_dep superpowers, installed at 6.3.0 -> present/ok" \
  "present=yes|version=6.3.0|verdict=ok" \
  "$(deps_run BIONIC_CLAUDE_HOME="$CH_OK" -- check_dep superpowers)"
expect_eq "check_dep superpowers, installed at 5.0.0 -> present/violation" \
  "present=yes|version=5.0.0|verdict=violation" \
  "$(deps_run BIONIC_CLAUDE_HOME="$CH_BAD" -- check_dep superpowers)"
expect_eq "check_dep superpowers, not installed -> absent/unknown" \
  "present=no|version=unknown|verdict=unknown" \
  "$(deps_run BIONIC_CLAUDE_HOME="$CH_EMPTY" -- check_dep superpowers)"

# The lane-3a probe must be marketplace-agnostic: slice S3 re-points both deps
# at bionic's own marketplace, which rewrites the key's right-hand side.
CH_REPOINTED="$TMP/ch-repointed"; plant_installed_plugins "$CH_REPOINTED" "superpowers@bionic" "6.3.0"
expect_eq "check_dep superpowers finds it under a DIFFERENT marketplace key" \
  "present=yes|version=6.3.0|verdict=ok" \
  "$(deps_run BIONIC_CLAUDE_HOME="$CH_REPOINTED" -- check_dep superpowers)"

# jq is itself a table row, so a machine can legitimately lack it. The fact
# must degrade to `unknown`, never to a confident wrong answer.
NOJQ_BIN="$TMP/nojq-bin"; mkdir -p "$NOJQ_BIN"
for real in bash sh env cat grep sed awk head tr; do
  p="$(command -v "$real" 2>/dev/null)" && ln -sf "$p" "${NOJQ_BIN}/${real}" 2>/dev/null
done
expect_eq "check_dep superpowers with no jq on PATH -> version unknown, verdict unknown" \
  "present=unknown|version=unknown|verdict=unknown" \
  "$(env -i HOME="$TMP/home" PATH="$NOJQ_BIN" BIONIC_CLAUDE_HOME="$CH_OK" \
      bash -c '. "$1"; check_dep superpowers' _ "$DEPS_SH" 2>&1)"

echo ""
echo "=== Group 6: check_dep, lane-3b, against a fixture PATH ==="

PRESENT_BIN="$TMP/present-bin"
cp -R "$BASE_BIN/." "$PRESENT_BIN/" 2>/dev/null || { mkdir -p "$PRESENT_BIN"; cp -R "$BASE_BIN/." "$PRESENT_BIN/"; }
make_stub "$PRESENT_BIN" rg
make_stub "$PRESENT_BIN" npm
make_stub "$PRESENT_BIN" claude
make_stub "$PRESENT_BIN" brew
make_stub "$PRESENT_BIN" uv

expect_eq "check_dep rg with rg on PATH -> present, constraint 'any' -> ok" \
  "present=yes|version=unknown|verdict=ok" \
  "$(env -i HOME="$TMP/home" PATH="$PRESENT_BIN" BIONIC_TEST_CALLS="$CALLS" \
      bash -c '. "$1"; check_dep rg' _ "$DEPS_SH" 2>&1)"
expect_eq "check_dep rg with rg absent from PATH -> absent" \
  "present=no|version=unknown|verdict=unknown" \
  "$(deps_run -- check_dep rg)"

# A version-bearing probe: the brew-dep mechanism parses `<binary> --version`.
# Fixture output copied from the real `rg --version` on this machine:
#   ripgrep 15.2.0
VER_BIN="$TMP/ver-bin"; mkdir -p "$VER_BIN"; cp -R "$BASE_BIN/." "$VER_BIN/"
cat > "${VER_BIN}/rg" <<'STUB'
#!/bin/bash
echo "ripgrep 15.2.0"
STUB
chmod +x "${VER_BIN}/rg"
expect_eq "check_dep rg reads a version out of the probe's --version output" \
  "present=yes|version=15.2.0|verdict=ok" \
  "$(env -i HOME="$TMP/home" PATH="$VER_BIN" bash -c '. "$1"; check_dep rg' _ "$DEPS_SH" 2>&1)"

# The npm-global mechanism probes the PACKAGE, not a binary name.
expect_eq "check_dep @playwright/cli with a succeeding npm -> present" \
  "present=yes|version=unknown|verdict=ok" \
  "$(env -i HOME="$TMP/home" PATH="$PRESENT_BIN" BIONIC_TEST_CALLS="$CALLS" \
      bash -c '. "$1"; check_dep @playwright/cli' _ "$DEPS_SH" 2>&1)"

# The pnpm-store mechanism has NO presence surface (bootstrap never checks it,
# it re-warms unconditionally). Saying `no` on a warm machine would be a lie;
# the honest value is `unknown`.
expect_eq "check_dep motion (pnpm store) -> presence honestly unknown" \
  "present=unknown|version=unknown|verdict=unknown" \
  "$(deps_run -- check_dep motion)"

expect_false "check_dep on an unknown dep exits non-zero" \
  bash -c '. "$1"; check_dep no-such-dep' _ "$DEPS_SH"

echo ""
echo "=== Group 7: install_dep — consent gates every mutation ==="
#
# No dry-run seam: the stub `brew` on the fixture PATH is what install_dep
# really invokes, and the recorder file is the only evidence considered.

: > "$CALLS"
DECLINE_OUT="$(env -i HOME="$TMP/home" PATH="$PRESENT_BIN" BIONIC_TEST_CALLS="$CALLS" \
  bash -c '. "$1"; install_dep rg </dev/null' _ "$DEPS_SH" 2>&1)"
DECLINE_RC=$?
expect_true "install_dep with no answer on stdin exits non-zero (declined)" test "$DECLINE_RC" -ne 0
expect_eq "install_dep with no answer ran NOTHING (recorder empty)" "0" \
  "$(grep -c . "$CALLS" | tr -d ' ')"
expect_match "install_dep names what it would run before asking" "*brew install ripgrep*" "$DECLINE_OUT"

: > "$CALLS"
env -i HOME="$TMP/home" PATH="$PRESENT_BIN" BIONIC_TEST_CALLS="$CALLS" \
  bash -c 'echo y | { . "$1"; install_dep rg; }' _ "$DEPS_SH" >/dev/null 2>&1
expect_match "install_dep with an explicit y DOES invoke brew" "*brew install ripgrep*" "$(cat "$CALLS")"

: > "$CALLS"
env -i HOME="$TMP/home" PATH="$PRESENT_BIN" BIONIC_TEST_CALLS="$CALLS" \
  bash -c 'echo n | { . "$1"; install_dep rg; }' _ "$DEPS_SH" >/dev/null 2>&1
expect_eq "install_dep with an explicit n ran nothing" "0" "$(grep -c . "$CALLS" | tr -d ' ')"

# Lane-3a is the native mechanism's job — install_dep must refuse to grow a
# second installer for it (that is exactly the D1 kludge the wave rejected).
: > "$CALLS"
expect_false "install_dep refuses lane-3a rows (native mechanism owns them)" \
  bash -c 'echo y | { . "$1"; install_dep superpowers; }' _ "$DEPS_SH"

expect_false "install_dep on an unknown dep exits non-zero" \
  bash -c 'echo y | { . "$1"; install_dep no-such-dep; }' _ "$DEPS_SH"

echo ""
echo "=== Group 8: remove_dep — consent-wrapped, policy-bounded ==="

: > "$CALLS"
env -i HOME="$TMP/home" PATH="$PRESENT_BIN" BIONIC_TEST_CALLS="$CALLS" \
  bash -c '. "$1"; remove_dep @playwright/cli </dev/null' _ "$DEPS_SH" >/dev/null 2>&1
expect_eq "remove_dep with no answer removed nothing" "0" "$(grep -c . "$CALLS" | tr -d ' ')"

: > "$CALLS"
env -i HOME="$TMP/home" PATH="$PRESENT_BIN" BIONIC_TEST_CALLS="$CALLS" \
  bash -c 'echo y | { . "$1"; remove_dep @playwright/cli; }' _ "$DEPS_SH" >/dev/null 2>&1
expect_match "remove_dep with consent uninstalls an own-install row" "*npm uninstall -g @playwright/cli*" "$(cat "$CALLS")"

# Shared foundation binaries are the reset charter's named exclusion: bionic
# ensured them, it does not own them, and pulling `git` off a machine because
# bionic is leaving is not a removal anyone consented to.
: > "$CALLS"
KEEP_OUT="$(env -i HOME="$TMP/home" PATH="$PRESENT_BIN" BIONIC_TEST_CALLS="$CALLS" \
  bash -c 'echo y | { . "$1"; remove_dep git; }' _ "$DEPS_SH" 2>&1)"
expect_eq "remove_dep git (keep-shared) removes nothing even with consent" "0" \
  "$(grep -c . "$CALLS" | tr -d ' ')"
expect_match "remove_dep git says why it is keeping the binary" "*keep-shared*" "$KEEP_OUT"

echo ""
echo "=== Group 9: detect_plugin_integrity — all three hook states ==="

plant_hook_scripts() {  # <root> <name>...
  local root="$1"; shift
  local name
  for name in "$@"; do
    printf '#!/bin/bash\nexit 0\n' > "${root}/hooks/${name}"
    chmod +x "${root}/hooks/${name}"
  done
}

plant_plugin() {  # <root> <version|-> <hooks: ok|degraded|chained-gap|absent>
  local root="$1" ver="$2" hooks="$3"
  mkdir -p "${root}/.claude-plugin" "${root}/hooks"
  if [ "$ver" != "-" ]; then
    cat > "${root}/.claude-plugin/plugin.json" <<JSON
{ "name": "bionic", "version": "${ver}" }
JSON
  fi
  case "$hooks" in
    absent) rm -f "${root}/hooks/hooks.json" ;;
    *)
      # Fixture-faithful to the shipped payload/hooks/hooks.json that S4
      # re-derived in this same wave: one plain entry plus a CHAINED one
      # ("agent-context-guard.sh <inner>"). Four of the six shipped entries
      # chain, so a fixture carrying only the plain shape cannot reach the
      # state that matters most — a payload where the OUTER script is there
      # and an inner one is not. That is the `chained-gap` arm below.
      cat > "${root}/hooks/hooks.json" <<'JSON'
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash",
        "hooks": [ { "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/hooks/protect-main.sh", "timeout": 10 } ] }
    ],
    "PreCompact": [
      { "matcher": "",
        "hooks": [ { "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/hooks/agent-context-guard.sh ${CLAUDE_PLUGIN_ROOT}/hooks/dispatch-preflight.sh", "timeout": 10 } ] }
    ]
  }
}
JSON
      case "$hooks" in
        ok)          plant_hook_scripts "$root" protect-main.sh agent-context-guard.sh dispatch-preflight.sh ;;
        chained-gap) plant_hook_scripts "$root" protect-main.sh agent-context-guard.sh ;;
        degraded)    : ;;   # nothing planted — even the FIRST token is missing
      esac
      ;;
  esac
}

PL_OK="$TMP/pl-ok";        plant_plugin "$PL_OK" 0.1.0 ok
PL_DEG="$TMP/pl-degraded"; plant_plugin "$PL_DEG" 0.1.0 degraded
PL_CHAIN="$TMP/pl-chain";  plant_plugin "$PL_CHAIN" 0.1.0 chained-gap
PL_ABS="$TMP/pl-absent";   plant_plugin "$PL_ABS" 0.1.0 absent
PL_NOVER="$TMP/pl-nover";  plant_plugin "$PL_NOVER" - ok

expect_eq "detect_plugin_integrity: intact payload" "plugin: version=0.1.0 hooks=ok" \
  "$(detect_run BIONIC_PLUGIN_ROOT="$PL_OK" -- detect_plugin_integrity)"
expect_eq "detect_plugin_integrity: hooks.json references a missing script" \
  "plugin: version=0.1.0 hooks=degraded" \
  "$(detect_run BIONIC_PLUGIN_ROOT="$PL_DEG" -- detect_plugin_integrity)"
# R-1. The outer script of a chained command is present, the INNER one is not.
# Reading only the first whitespace token calls this payload healthy while half
# its hooks are missing files — a half-copied install that lost the evidence
# gate, the governing-skill gate and the landing gate reports clean.
expect_eq "detect_plugin_integrity: a CHAINED command's second script is missing" \
  "plugin: version=0.1.0 hooks=degraded" \
  "$(detect_run BIONIC_PLUGIN_ROOT="$PL_CHAIN" -- detect_plugin_integrity)"
expect_eq "detect_plugin_integrity: no hooks.json at all" "plugin: version=0.1.0 hooks=absent" \
  "$(detect_run BIONIC_PLUGIN_ROOT="$PL_ABS" -- detect_plugin_integrity)"
expect_eq "detect_plugin_integrity: unreadable plugin.json -> version=unknown" \
  "plugin: version=unknown hooks=ok" \
  "$(detect_run BIONIC_PLUGIN_ROOT="$PL_NOVER" -- detect_plugin_integrity)"

echo ""
echo "=== Group 10: detect_dep renders one line per dep, both arms ==="

expect_eq "detect_dep superpowers (present)" \
  "dep:superpowers lane=3a present=yes version=6.3.0 constraint=^6.3.0 verdict=ok" \
  "$(detect_run BIONIC_CLAUDE_HOME="$CH_OK" -- detect_dep superpowers)"
expect_eq "detect_dep superpowers (absent)" \
  "dep:superpowers lane=3a present=no version=unknown constraint=^6.3.0 verdict=unknown" \
  "$(detect_run BIONIC_CLAUDE_HOME="$CH_EMPTY" -- detect_dep superpowers)"
expect_eq "detect_dep rg (present, lane 3b)" \
  "dep:rg lane=3b present=yes version=15.2.0 constraint=any verdict=ok" \
  "$(env -i HOME="$TMP/home" PATH="$VER_BIN" bash -c '. "$1"; detect_dep rg' _ "$DETECT_SH" 2>&1)"
expect_eq "detect_dep rg (absent, lane 3b)" \
  "dep:rg lane=3b present=no version=unknown constraint=any verdict=unknown" \
  "$(detect_run -- detect_dep rg)"
expect_false "detect_dep on an unknown dep exits non-zero" \
  bash -c '. "$1"; detect_dep no-such-dep' _ "$DETECT_SH"

echo ""
echo "=== Group 11: detect_env_todo_tools — both arms ==="

RC_WITH="$TMP/rc-with";  printf 'export PATH="$HOME/bin:$PATH"\nexport CLAUDE_CODE_ENABLE_TODO_TOOLS=1\n' > "$RC_WITH"
RC_WITHOUT="$TMP/rc-without"; printf 'export PATH="$HOME/bin:$PATH"\n' > "$RC_WITHOUT"
RC_COMMENTED="$TMP/rc-commented"; printf '# export CLAUDE_CODE_ENABLE_TODO_TOOLS=1\n' > "$RC_COMMENTED"

expect_eq "detect_env_todo_tools: export present" "env:todo-tools present=yes" \
  "$(detect_run BIONIC_SHELL_RC="$RC_WITH" -- detect_env_todo_tools)"
expect_eq "detect_env_todo_tools: export absent" "env:todo-tools present=no" \
  "$(detect_run BIONIC_SHELL_RC="$RC_WITHOUT" -- detect_env_todo_tools)"
expect_eq "detect_env_todo_tools: a COMMENTED export does not count" "env:todo-tools present=no" \
  "$(detect_run BIONIC_SHELL_RC="$RC_COMMENTED" -- detect_env_todo_tools)"
expect_eq "detect_env_todo_tools: rc file missing entirely" "env:todo-tools present=no" \
  "$(detect_run BIONIC_SHELL_RC="$TMP/rc-nonexistent" -- detect_env_todo_tools)"

echo ""
echo "=== Group 12: detect_zshrc_legacy_block — both arms ==="
#
# Marker literals copied verbatim from claude-bootstrap.sh's ALIAS_START /
# ALIAS_END (the box-drawing dashes are part of the marker).

RC_LEGACY="$TMP/rc-legacy"
cat > "$RC_LEGACY" <<'RC'
export PATH="$HOME/bin:$PATH"
# ─── bionic:start ───
alias claude='claude --dangerously-skip-permissions'
# ─── bionic:end ───
RC

expect_eq "detect_zshrc_legacy_block: block present" "env:zshrc-legacy present=yes" \
  "$(detect_run BIONIC_SHELL_RC="$RC_LEGACY" -- detect_zshrc_legacy_block)"
expect_eq "detect_zshrc_legacy_block: block absent" "env:zshrc-legacy present=no" \
  "$(detect_run BIONIC_SHELL_RC="$RC_WITHOUT" -- detect_zshrc_legacy_block)"
expect_eq "detect_zshrc_legacy_block: rc file missing entirely" "env:zshrc-legacy present=no" \
  "$(detect_run BIONIC_SHELL_RC="$TMP/rc-nonexistent" -- detect_zshrc_legacy_block)"

echo ""
echo "=== Group 13: detect_legacy_channel_hooks — counts, both arms ==="
#
# Fixture shape copied from the real user settings.json hook block written by
# claude-bootstrap.sh's wire_managed_hooks (MANAGED_HOOKS, :1772-1779).

SET_STALE="$TMP/settings-stale.json"
cat > "$SET_STALE" <<'JSON'
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash",
        "hooks": [ { "type": "command", "command": "~/.claude/hooks/protect-main.sh" },
                   { "type": "command", "command": "~/.claude/hooks/protect-database.sh" } ] }
    ],
    "SubagentStop": [
      { "hooks": [ { "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/hooks/landing-gate.sh" } ] }
    ]
  }
}
JSON

SET_CLEAN="$TMP/settings-clean.json"
cat > "$SET_CLEAN" <<'JSON'
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash",
        "hooks": [ { "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/hooks/protect-main.sh" } ] }
    ]
  }
}
JSON

SET_NOHOOKS="$TMP/settings-nohooks.json"; echo '{"model":"opus"}' > "$SET_NOHOOKS"

expect_eq "detect_legacy_channel_hooks: two legacy entries counted, plugin entry not" \
  "env:legacy-channel-hooks count=2" \
  "$(detect_run BIONIC_SETTINGS_FILE="$SET_STALE" -- detect_legacy_channel_hooks)"
expect_eq "detect_legacy_channel_hooks: a clean plugin-channel settings file counts 0" \
  "env:legacy-channel-hooks count=0" \
  "$(detect_run BIONIC_SETTINGS_FILE="$SET_CLEAN" -- detect_legacy_channel_hooks)"
expect_eq "detect_legacy_channel_hooks: settings with no hooks key counts 0" \
  "env:legacy-channel-hooks count=0" \
  "$(detect_run BIONIC_SETTINGS_FILE="$SET_NOHOOKS" -- detect_legacy_channel_hooks)"
expect_eq "detect_legacy_channel_hooks: missing settings file counts 0" \
  "env:legacy-channel-hooks count=0" \
  "$(detect_run BIONIC_SETTINGS_FILE="$TMP/settings-nonexistent.json" -- detect_legacy_channel_hooks)"
expect_eq "detect_legacy_channel_hooks: no jq on PATH -> count=unknown, never a false 0" \
  "env:legacy-channel-hooks count=unknown" \
  "$(env -i HOME="$TMP/home" PATH="$NOJQ_BIN" BIONIC_SETTINGS_FILE="$SET_STALE" \
      bash -c '. "$1"; detect_legacy_channel_hooks' _ "$DETECT_SH" 2>&1)"

echo ""
echo "=== Group 14: detect_half_uninstalled — both arms ==="
#
# Half-uninstalled = the plugin is no longer registered, but bionic's machine
# footprint is still there. It is the fact the standalone remove.sh door (AC-4)
# exists to serve, so it must NOT be answered by asking whether this file's own
# payload tree exists — that tree is gone in exactly the case being detected.

expect_eq "detect_half_uninstalled: plugin gone + legacy .zshrc block left behind" \
  "state:half-uninstalled=yes" \
  "$(detect_run BIONIC_CLAUDE_HOME="$CH_EMPTY" BIONIC_SHELL_RC="$RC_LEGACY" \
      BIONIC_SETTINGS_FILE="$SET_CLEAN" -- detect_half_uninstalled)"
expect_eq "detect_half_uninstalled: plugin gone + stale settings entries left behind" \
  "state:half-uninstalled=yes" \
  "$(detect_run BIONIC_CLAUDE_HOME="$CH_EMPTY" BIONIC_SHELL_RC="$RC_WITHOUT" \
      BIONIC_SETTINGS_FILE="$SET_STALE" -- detect_half_uninstalled)"
expect_eq "detect_half_uninstalled: plugin gone and no footprint at all -> no" \
  "state:half-uninstalled=no" \
  "$(detect_run BIONIC_CLAUDE_HOME="$CH_EMPTY" BIONIC_SHELL_RC="$RC_WITHOUT" \
      BIONIC_SETTINGS_FILE="$SET_CLEAN" -- detect_half_uninstalled)"
# The discriminating arm: identical footprint, only the registration differs.
# Without it the function could return `yes` on the footprint alone and still
# pass every case above.
CH_BIONIC="$TMP/ch-bionic"; plant_installed_plugins "$CH_BIONIC" "bionic@bionic" "0.1.0"
expect_eq "detect_half_uninstalled: plugin still installed, same footprint -> no" \
  "state:half-uninstalled=no" \
  "$(detect_run BIONIC_CLAUDE_HOME="$CH_BIONIC" BIONIC_SHELL_RC="$RC_LEGACY" \
      BIONIC_SETTINGS_FILE="$SET_STALE" -- detect_half_uninstalled)"

# R-2 — the FOURTH term. detect.sh owns three pieces of footprint; the applied
# permission block is profile.sh's, and it is reachable on its own: a user who
# runs /bionic:remove, declines the permission-block question and accepts the
# uninstall lands with the block as the only leftover. Both files' headers said
# the disjunction joined there and neither joined it, so doctor read
# half-uninstalled=no and withheld the one fix that machine has.
#
# The consult is SOFT — `declare -F` — because detect.sh must stay sourceable
# alone. That is not a nicety here: the standalone remove.sh door exists for
# exactly the machine where the payload (and so profile.sh) is gone. Hence two
# arms on one machine state, differing only in which libraries are loaded.
SET_PROFILE_ONLY="$TMP/settings-profile-only.json"
cat > "$SET_PROFILE_ONLY" <<'JSON'
{
  "permissions": {
    "allow": [
      "Bash(: bionic-profile-begin version=0.1.0)",
      "Bash(bash /Users/nobody/.claude/plugins/bionic/scripts/doctor.sh:*)",
      "Bash(: bionic-profile-end)"
    ]
  }
}
JSON

detect_and_profile_run() {  # <env-assignments...> -- <function> [args]
  local -a envs=()
  while [ $# -gt 0 ] && [ "$1" != "--" ]; do envs+=("$1"); shift; done
  shift
  env -i HOME="$TMP/home" PATH="$BASE_BIN" BIONIC_TEST_CALLS="$CALLS" "${envs[@]}" \
    bash -c '. "$1"; . "$2"; shift 2; "$@"' _ "$DETECT_SH" "$PROFILE_SH" "$@" 2>&1
}

expect_eq "detect_half_uninstalled: doctor's load-out (detect+profile) sees the permission block as footprint" \
  "state:half-uninstalled=yes" \
  "$(detect_and_profile_run BIONIC_CLAUDE_HOME="$CH_EMPTY" BIONIC_SHELL_RC="$RC_WITHOUT" \
      BIONIC_SETTINGS_FILE="$SET_PROFILE_ONLY" -- detect_half_uninstalled)"
expect_eq "detect_half_uninstalled: detect.sh ALONE degrades to its own three terms, same machine" \
  "state:half-uninstalled=no" \
  "$(detect_run BIONIC_CLAUDE_HOME="$CH_EMPTY" BIONIC_SHELL_RC="$RC_WITHOUT" \
      BIONIC_SETTINGS_FILE="$SET_PROFILE_ONLY" -- detect_half_uninstalled)"
expect_eq "detect_half_uninstalled: detect+profile, plugin still registered -> still no" \
  "state:half-uninstalled=no" \
  "$(detect_and_profile_run BIONIC_CLAUDE_HOME="$CH_BIONIC" BIONIC_SHELL_RC="$RC_WITHOUT" \
      BIONIC_SETTINGS_FILE="$SET_PROFILE_ONLY" -- detect_half_uninstalled)"

# C-2 — REGISTRATION AS A FACT OF ITS OWN. The registration probe above was
# computed inside detect_half_uninstalled and reachable nowhere else, so setup's
# step 6 could not consult it and told every user the plugin registers a
# replacement for the hooks it was about to delete — false on every machine
# before the W5 cutover. A machine fact that only one caller can see is a fact
# with one caller by accident, not by design; this exposes it the way every
# other line here is exposed, and detect_half_uninstalled now reads it rather
# than recomputing it.

expect_eq "detect_plugin_registered: bionic in installed_plugins.json -> yes" \
  "plugin:registered=yes" \
  "$(detect_run BIONIC_CLAUDE_HOME="$CH_BIONIC" -- detect_plugin_registered)"
expect_eq "detect_plugin_registered: a registry with no bionic entry -> no" \
  "plugin:registered=no" \
  "$(detect_run BIONIC_CLAUDE_HOME="$CH_EMPTY" -- detect_plugin_registered)"
expect_eq "detect_plugin_registered: another marketplace's plugin is not bionic" \
  "plugin:registered=no" \
  "$(detect_run BIONIC_CLAUDE_HOME="$CH_OK" -- detect_plugin_registered)"
expect_eq "detect_plugin_registered: no registry file at all -> no (nothing is installed)" \
  "plugin:registered=no" \
  "$(detect_run BIONIC_CLAUDE_HOME="$TMP/ch-absent" -- detect_plugin_registered)"

# The honest unknown, in the one case where guessing would be a lie: the file is
# there and jq cannot parse it. Answering `no` would tell setup to promise the
# user nothing replaces their hooks; answering `yes` would promise that
# something does. Neither is known.
CH_MALFORMED="$TMP/ch-malformed"; mkdir -p "$CH_MALFORMED/plugins"
printf '%s' '{"plugins": {' > "$CH_MALFORMED/plugins/installed_plugins.json"
expect_eq "detect_plugin_registered: unparseable registry -> unknown, never a guess" \
  "plugin:registered=unknown" \
  "$(detect_run BIONIC_CLAUDE_HOME="$CH_MALFORMED" -- detect_plugin_registered)"

# No jq: the grep fallback the half-uninstalled probe already carried. It is a
# real answer, not an unknown — the key is a literal string in the file.
expect_eq "detect_plugin_registered: no jq on PATH still reads the registry -> yes" \
  "plugin:registered=yes" \
  "$(env -i HOME="$TMP/home" PATH="$NOJQ_BIN" BIONIC_CLAUDE_HOME="$CH_BIONIC" \
      bash -c '. "$1"; detect_plugin_registered' _ "$DETECT_SH" 2>&1)"
expect_eq "detect_plugin_registered: no jq, no bionic entry -> no" \
  "plugin:registered=no" \
  "$(env -i HOME="$TMP/home" PATH="$NOJQ_BIN" BIONIC_CLAUDE_HOME="$CH_EMPTY" \
      bash -c '. "$1"; detect_plugin_registered' _ "$DETECT_SH" 2>&1)"

# The extraction did not move the half-uninstalled verdict. An `unknown`
# registration must not be reported as half-uninstalled: that verdict tells the
# user their machine is broken and points them at the standalone remove door.
expect_eq "detect_half_uninstalled: an unparseable registry is not a half-uninstall claim" \
  "state:half-uninstalled=no" \
  "$(detect_run BIONIC_CLAUDE_HOME="$CH_MALFORMED" BIONIC_SHELL_RC="$RC_LEGACY" \
      BIONIC_SETTINGS_FILE="$SET_STALE" -- detect_half_uninstalled)"

echo ""
echo "=== Group 15: read-only contract — no detect function mutates ==="
#
# The design's own words: doctor mutates nothing, and every doctor line comes
# from detect.sh. A fingerprint of the whole fixture tree taken before and
# after a full detect sweep is the cheapest honest proof of that.

FP_ROOT="$TMP/fp"; mkdir -p "$FP_ROOT"
cp "$RC_LEGACY" "$FP_ROOT/rc"; cp "$SET_STALE" "$FP_ROOT/settings.json"
cp -R "$PL_OK" "$FP_ROOT/plugin"; cp -R "$CH_OK" "$FP_ROOT/claude-home"
fingerprint() { find "$FP_ROOT" -type f -exec ls -l {} \; 2>/dev/null | awk '{print $5, $9}' | sort; }
FP_BEFORE="$(fingerprint)"
: > "$CALLS"
detect_run BIONIC_PLUGIN_ROOT="$FP_ROOT/plugin" BIONIC_CLAUDE_HOME="$FP_ROOT/claude-home" \
  BIONIC_SHELL_RC="$FP_ROOT/rc" BIONIC_SETTINGS_FILE="$FP_ROOT/settings.json" \
  -- detect_all >/dev/null 2>&1
FP_AFTER="$(fingerprint)"
expect_eq "a full detect_all sweep leaves every fixture file byte-identical" "$FP_BEFORE" "$FP_AFTER"

DETECT_ALL="$(detect_run BIONIC_PLUGIN_ROOT="$PL_OK" BIONIC_CLAUDE_HOME="$CH_OK" \
  BIONIC_SHELL_RC="$RC_LEGACY" BIONIC_SETTINGS_FILE="$SET_STALE" -- detect_all)"
expect_match "detect_all emits the plugin line"        "*plugin: version=*"          "$DETECT_ALL"
expect_match "detect_all emits the todo-tools line"    "*env:todo-tools present=*"   "$DETECT_ALL"
expect_match "detect_all emits the zshrc-legacy line"  "*env:zshrc-legacy present=*" "$DETECT_ALL"
expect_match "detect_all emits the stale-hooks line"   "*env:legacy-channel-hooks count=*" "$DETECT_ALL"
expect_match "detect_all emits the registration line"  "*plugin:registered=*"        "$DETECT_ALL"
expect_match "detect_all emits the half-uninstalled line" "*state:half-uninstalled=*" "$DETECT_ALL"
expect_match "detect_all emits a dep line per row"     "*dep:superpowers lane=3a*"   "$DETECT_ALL"

echo ""
echo "=== Group 16: every detect function prints exactly one line and exits 0 ==="

for fn in detect_plugin_integrity detect_env_todo_tools detect_zshrc_legacy_block \
          detect_legacy_channel_hooks detect_plugin_registered detect_half_uninstalled; do
  out="$(detect_run BIONIC_PLUGIN_ROOT="$PL_OK" BIONIC_CLAUDE_HOME="$CH_OK" \
    BIONIC_SHELL_RC="$RC_LEGACY" BIONIC_SETTINGS_FILE="$SET_STALE" -- "$fn")"
  rc=$?
  expect_eq "${fn} exits 0" "0" "$rc"
  expect_eq "${fn} prints exactly one line" "1" "$(printf '%s\n' "$out" | grep -c .)"
done
out="$(detect_run BIONIC_CLAUDE_HOME="$CH_OK" -- detect_dep superpowers)"; rc=$?
expect_eq "detect_dep exits 0" "0" "$rc"
expect_eq "detect_dep prints exactly one line" "1" "$(printf '%s\n' "$out" | grep -c .)"

echo ""
echo "=== Group 18: manifest agreement — deps.sh table <-> plugin.json <-> marketplace.json (AC-8) ==="
#
# The dep table is the SSoT for lane-3a dependencies. plugin.json's
# `dependencies` array and marketplace.json's url-sourced entries are
# RENDERINGS of those rows, never independent authorities (ownership table,
# wave-03 spec §Design). Version constraints are deliberately ABSENT from
# plugin.json: the CLI cannot resolve a same-marketplace, version-constrained
# dependency — reproduced on a fresh scratch config with a confirmed-existing
# matching upstream tag (record/epic-17-w3/probe-ac6-marketplace-entry.md) — so
# the constraint lives ONLY in this table; a version key reappearing in
# plugin.json is a silent regression to the broken shape, not a harmless
# duplicate.
#
# manifest_agreement_report prints one problem line per disagreement, either
# direction, or nothing when the three parties agree. It is driven against the
# real manifests for the golden case and against a mutated TMP copy for the
# mutation-and-restore proof below — the real files are never written to.

MANIFEST_JSON_HELPER="$TMP/manifest_agreement.py"
cat > "$MANIFEST_JSON_HELPER" <<'PYEOF'
import json, sys

plugin_path, marketplace_path, table_json = sys.argv[1], sys.argv[2], sys.argv[3]
table = json.loads(table_json)  # {name: source_url}
plugin = json.load(open(plugin_path))
mkt = json.load(open(marketplace_path))

problems = []

deps = {d.get('name'): d for d in plugin.get('dependencies', []) if isinstance(d, dict)}
for name in table:
    if name not in deps:
        problems.append("plugin.json missing dependency: %s" % name)
for name, d in deps.items():
    if name not in table:
        problems.append("plugin.json has dependency with no table row: %s" % name)
        continue
    if d.get('marketplace') != 'bionic':
        problems.append("plugin.json %s marketplace != bionic: %r" % (name, d.get('marketplace')))
    if 'version' in d:
        problems.append("plugin.json %s carries a version key: %r" % (name, d.get('version')))

entries = {p.get('name'): p for p in mkt.get('plugins', [])}
for name, url in table.items():
    if name not in entries:
        problems.append("marketplace.json missing entry: %s" % name)
        continue
    src = entries[name].get('source', {})
    entry_url = src.get('url', '') if isinstance(src, dict) else ''
    if entry_url != url:
        problems.append("marketplace.json %s source_url mismatch: table=%r entry=%r" % (name, url, entry_url))
    # Every url-sourced entry carries a commit pin. This is the supply-chain
    # claim — "the code installed is the code that was reviewed" — and it is
    # NOT the version constraint the table owns; an unpinned entry tracks
    # whatever HEAD the default branch is at install time, and these
    # dependencies ship skills and agents whose text Claude reads and acts on.
    # Pinning one and not the other is the shape this asserts away.
    if not str(src.get('sha', '') if isinstance(src, dict) else '').strip():
        problems.append("marketplace.json %s is url-sourced with no sha pin" % name)
for name, p in entries.items():
    if name != 'bionic' and name not in table and isinstance(p.get('source'), dict):
        problems.append("marketplace.json has url-sourced entry with no table row: %s" % name)

print('\n'.join(problems))
PYEOF

LANE3A_NAMES="$(deps_run -- dep_names_lane 3a | sort)"
TABLE_JSON="$(python3 -c "
import json, sys
names = sys.argv[1].split()
print(json.dumps({n: sys.argv[2 + i] for i, n in enumerate(names)}))
" "$LANE3A_NAMES" $(while IFS= read -r n; do [ -n "$n" ] && deps_run -- dep_field "$n" source_url; done <<< "$LANE3A_NAMES"))"

manifest_agreement_report() {  # <plugin.json path> <marketplace.json path>
  python3 "$MANIFEST_JSON_HELPER" "$1" "$2" "$TABLE_JSON"
}

expect_eq "table, plugin.json, and marketplace.json agree in both directions (golden case)" \
  "" "$(manifest_agreement_report "$PLUGIN_JSON" "$MARKETPLACE_JSON")"

echo ""
echo "=== Group 19: mutation-and-restore — both agreement pins actually discriminate ==="
#
# A pin that stays green on a mutated copy proves nothing (fixtures-can-pin-
# away-the-test). Mutations are applied to TMP copies; the shipped manifests
# are checksummed before and after and asserted byte-identical at the end.

MANIFEST_CKSUM_BEFORE="$(shasum "$PLUGIN_JSON" "$MARKETPLACE_JSON" 2>/dev/null)"

# Mutation 1: break a source_url in a marketplace.json copy.
MUT_MKT="$TMP/marketplace.mutant.json"
python3 -c "
import json
d = json.load(open('$MARKETPLACE_JSON'))
for p in d['plugins']:
    if p.get('name') == 'superpowers':
        p['source']['url'] = 'https://example.invalid/not-superpowers.git'
json.dump(d, open('$MUT_MKT', 'w'))
"
MUT1_REPORT="$(manifest_agreement_report "$PLUGIN_JSON" "$MUT_MKT")"
expect_true "mutation 1 (broken source_url) makes the agreement pin non-empty" test -n "$MUT1_REPORT"
expect_match "mutation 1 is reported as a source_url mismatch on superpowers" \
  "*superpowers source_url mismatch*" "$MUT1_REPORT"

# Mutation 2: re-add a version key in a plugin.json copy.
MUT_PLUGIN="$TMP/plugin.mutant.json"
python3 -c "
import json
d = json.load(open('$PLUGIN_JSON'))
for dep in d['dependencies']:
    if dep.get('name') == 'superpowers':
        dep['version'] = '^6.3.0'
json.dump(d, open('$MUT_PLUGIN', 'w'))
"
MUT2_REPORT="$(manifest_agreement_report "$MUT_PLUGIN" "$MARKETPLACE_JSON")"
expect_true "mutation 2 (reintroduced version key) makes the agreement pin non-empty" test -n "$MUT2_REPORT"
expect_match "mutation 2 is reported as a version key on superpowers" \
  "*superpowers carries a version key*" "$MUT2_REPORT"

# Mutation 3: drop a sha pin in a marketplace.json copy. The asymmetry this
# catches is the one that actually shipped — superpowers pinned, agent-skills
# tracking the default branch's HEAD — so the pin has to be proven able to see
# an ABSENT sha, not merely a wrong one.
MUT_MKT_NOSHA="$TMP/marketplace.nosha.json"
python3 -c "
import json
d = json.load(open('$MARKETPLACE_JSON'))
for p in d['plugins']:
    if p.get('name') == 'agent-skills':
        p['source'].pop('sha', None)
json.dump(d, open('$MUT_MKT_NOSHA', 'w'))
"
MUT3_REPORT="$(manifest_agreement_report "$PLUGIN_JSON" "$MUT_MKT_NOSHA")"
expect_true "mutation 3 (sha pin removed) makes the agreement pin non-empty" test -n "$MUT3_REPORT"
expect_match "mutation 3 is reported as a missing sha pin on agent-skills" \
  "*agent-skills is url-sourced with no sha pin*" "$MUT3_REPORT"

expect_eq "the shipped plugin.json and marketplace.json are byte-identical to before the mutations" \
  "$MANIFEST_CKSUM_BEFORE" "$(shasum "$PLUGIN_JSON" "$MARKETPLACE_JSON" 2>/dev/null)"

echo ""
echo "=== Group 20: the sha ACTUATES the version the constraint JUDGES (C-4) ==="
#
# marketplace.json's `sha` and the table's version constraint were treated as
# answering different questions on different clocks. They do not. The sha is
# HONOURED by the CLI — measured, not assumed: an isolated-config install of a
# marketplace entry pinned to superpowers v6.2.0 (3dcbd5c…) landed 6.2.0 and not
# HEAD's 6.3.0 (record/epic-17-w3/critic-report.md, C-3). So the sha DETERMINES
# the version that arrives through bionic's marketplace, and the table's
# constraint JUDGES that same version, and doctor renders the verdict. They are
# an actuator and a judge on one quantity, and nothing joined them: a future sha
# bump could ship a dependency that bionic's own doctor immediately reports as
# violating bionic's own constraint, with this suite green.
#
# WHAT THIS PIN IS, HONESTLY. It is a TRIPWIRE, not a resolver. Resolving a sha
# to a version means reaching the network, which this suite must not do, so the
# known pairs live below as fixture data with their provenance. The pin has two
# halves and the first is what does the work: every sha in marketplace.json must
# appear in the table. Bump a sha and the fixture goes stale, which fails, which
# forces a human to re-derive the pair — and re-deriving it is what runs the
# constraint check on the new version. The tripwire cannot catch a bump; it can
# only make one impossible to land silently.
#
# PROVENANCE of each pair, from the critic's measurements:
#   b36e082 -> superpowers 6.3.0   `git ls-remote https://github.com/obra/superpowers.git HEAD`
#                                  + cache path ~/.claude/plugins/cache/bionic/superpowers/6.3.0
#   df1edb2 -> agent-skills 0.6.7  `git ls-remote https://github.com/addyosmani/agent-skills.git HEAD`
#                                  + cache path ~/.claude/plugins/cache/bionic/agent-skills/0.6.7
#   3dcbd5c -> superpowers 6.2.0   the discriminating install under an isolated
#                                  CLAUDE_CONFIG_DIR; installed_plugins.json read back
#                                  {"version":"6.2.0","gitCommitSha":"3dcbd5c…"}
SHA_VERSION_PAIRS='superpowers|b36e0829c6d0140e93cfef2ca599b1b07d4a7797|6.3.0
agent-skills|df1edb2e05487d0aa6d93c747141e0aed1187f25|0.6.7
superpowers|3dcbd5c4b48e02263fbf4a3c01e3fe4f81d584d9|6.2.0'

sha_to_version() {  # <plugin> <sha> -> the known version, or empty
  local want="$1|$2" row
  while IFS= read -r row; do
    case "$row" in "${want}|"*) printf '%s' "${row##*|}"; return 0 ;; esac
  done <<< "$SHA_VERSION_PAIRS"
  return 1
}

while IFS= read -r dep_name; do
  [ -n "$dep_name" ] || continue
  MKT_SHA="$(jq -r --arg n "$dep_name" \
    '[.plugins[] | select(.name == $n) | .source.sha // ""] | first // ""' "$MARKETPLACE_JSON")"
  KNOWN_VERSION="$(sha_to_version "$dep_name" "$MKT_SHA" || true)"
  DEP_CONSTRAINT="$(deps_run -- dep_field "$dep_name" constraint)"

  expect_true "${dep_name}: marketplace.json's sha is one this suite has a version for" \
    test -n "$KNOWN_VERSION"
  expect_eq "${dep_name}: the version that sha installs satisfies the table's ${DEP_CONSTRAINT}" \
    "ok" "$(deps_run -- dep_constraint_verdict "$DEP_CONSTRAINT" "${KNOWN_VERSION:-0.0.0}")"
done <<< "$(deps_run -- dep_names_lane 3a)"

# The judge is live, not decorative: the third fixture pair is a REAL sha that
# installs a version the table would reject. Without this arm, a pair table
# whose versions all happened to satisfy everything would look identical to one
# that was never checked.
expect_eq "a sha that installs superpowers 6.2.0 would be caught (the check discriminates)" \
  "violation" \
  "$(deps_run -- dep_constraint_verdict "$(deps_run -- dep_field superpowers constraint)" \
      "$(sha_to_version superpowers 3dcbd5c4b48e02263fbf4a3c01e3fe4f81d584d9)")"

# And the first half is non-vacuous: an unknown sha must fail the lookup rather
# than fall through to some default.
expect_false "an unrecorded sha has no version, so a bump cannot pass silently" \
  sha_to_version superpowers 0000000000000000000000000000000000000000

echo ""
echo "=== Group 21: the suite is registered in tests/run.sh by name ==="
#
# tests/*.test.sh is NOT globbed by the runner — an unregistered suite is a
# silent false green (tests/run.sh:39-42 records the last time that happened).

expect_true "tests/run.sh names plugin-lib.test.sh" \
  grep -q 'run "plugin-lib.test.sh" bash tests/plugin-lib.test.sh' "${REPO}/tests/run.sh"

echo ""
echo "========================================"
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
echo "========================================"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
