#!/usr/bin/env bash
#
# tests/run.sh — one-command test runner for bionic.
#
# No CI needed: just `bash tests/run.sh`. Runs every hermetic suite (no network,
# no auth) plus the Docker mock install e2e when docker is present.
#
#   GATING suites (set the exit code — must be green):
#     hooks/*.test.sh                  every hook's behavior suite (globbed)
#     the hand-listed `run` lines below every suite outside hooks/ — the glob does
#                                      NOT reach them, so a new one is invisible
#                                      until its `run` line is added by name
#     tests/bootstrap-e2e-docker.sh    whole bootstrap on a fresh OS (docker only)
#
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

( . tests/lib/resolve-roots.sh
  printf 'Roots: hooks=%s skills=%s scripts=%s\n\n' \
    "$BIONIC_HOOKS_DIR" "$BIONIC_SKILLS_DIR" "$BIONIC_SCRIPTS_DIR" )

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0; skip=0; failed=""

run() {  # run <label> <cmd...>   — gating
  local label="$1"; shift
  printf '  %-36s ' "$label"
  if "$@" >"$TMP/out" 2>&1; then
    echo "✓ PASS"; pass=$((pass+1))
  else
    echo "✗ FAIL"; fail=$((fail+1)); failed="${failed}\n    - ${label}"
    echo "───── ${label}: captured output ─────"
    cat "$TMP/out"
    echo "───── end ${label} ─────"
  fi
}

echo "Gating suites:"
for t in hooks/*.test.sh; do
  [ -f "$t" ] || continue
  run "$(basename "$t")" bash "$t"
done
run "scripts.test.sh" bash tests/scripts.test.sh
run "installer-behavior.test.sh" bash tests/installer-behavior.test.sh
run "agent-roles.test.sh" bash tests/agent-roles.test.sh
run "interview-protocol.test.sh" bash tests/interview-protocol.test.sh
run "dispatch-spans.test.sh" bash tests/dispatch-spans.test.sh
# Cross-COMPONENT proofs (epic-15 W1R slice 4/6). They belong to no single hook,
# so they live here rather than under hooks/ — which also means they are invisible
# to the glob above and must stay hand-listed.
run "cross-gate-agreement.test.sh" bash tests/cross-gate-agreement.test.sh
run "fail-direction-table.test.sh" bash tests/fail-direction-table.test.sh
# Epic-17 wave-01 slice S1: bionic plugin manifest + marketplace manifest + LICENSE.
run "plugin-manifest.test.sh" bash tests/plugin-manifest.test.sh
# hooks/hooks.json (plugin-format manifest, epic-17 wave-01 slice 2) is also
# a cross-COMPONENT proof — it pins against claude-bootstrap.sh's
# MANAGED_HOOKS array, not any single hook script.
run "plugin-hooks.test.sh" bash tests/plugin-hooks.test.sh
# Harness-on-harness (epic-17 W1). Pins the assertion helpers every suite above
# hand-copies: under pipefail, `printf "$haystack" | grep -q` is a SIGPIPE race
# that reports a present needle as missing and an absent-check as green. Also
# hand-listed, same reason as the two lines above.
run "assert-helper-race.test.sh" bash tests/assert-helper-race.test.sh
# Cross-FILE proof (epic-17 W1 S3): the plugin-layout path rewrite, and the near-identical
# state paths it must not have touched. Spans SKILL.md, hooks/ and claude-bootstrap.sh, so
# like the two above it belongs to no single hook and must stay hand-listed.
run "plugin-paths.test.sh" bash tests/plugin-paths.test.sh
# Cross-FILE proof (epic-17 W1 S6): the payload boundary — what the plugin ships and, more
# to the point, what it must NOT. Pins marketplace.json's source field against the payload/
# link tree and the repo's single-owner layout, so it too is hand-listed.
run "plugin-payload.test.sh" bash tests/plugin-payload.test.sh
# Harness-on-harness (epic-17 W2 S1). Catch-proof for tests/lib/resolve-roots.sh, the
# path-resolution seam every suite sources: plants a doctored tree and proves the
# override binds in BOTH directions. Belongs to no single hook, so hand-listed.
run "seam-resolution.test.sh" bash tests/seam-resolution.test.sh
# Cross-FILE proof (epic-17 W2 S4): plugin.json is the single version owner
# (public semver + dependency ranges); the marketplace entry abstains; the
# SUPPORTED_SDLC_VERSION bridge pair is pinned against the plugin major. Spans
# payload/.claude-plugin/plugin.json, .claude-plugin/marketplace.json and two
# hooks, so like the others it belongs to no single hook and stays hand-listed.
run "version-ssot.test.sh" bash tests/version-ssot.test.sh
# Payload libraries (epic-17 W3 S1): the dependency SSoT table in
# payload/scripts/lib/deps.sh and the machine-fact functions in
# payload/scripts/lib/detect.sh, driven against fixture roots and a fixture
# PATH. Belongs to no single hook, so hand-listed like the rest.
run "plugin-lib.test.sh" bash tests/plugin-lib.test.sh
# The worktree contract (epic-17 W3 S2, spec AC-10 / D4): payload/scripts/spawn-worktree.sh
# driven against scratch git repositories, with its attestation line pinned byte-exactly
# because dispatchers quote that line into their ledger rows. Its own suite rather than a
# section of plugin-lib.test.sh — different subject, different fixture regime — and so,
# like every suite outside hooks/, hand-listed here or it never runs.
run "spawn-worktree.test.sh" bash tests/spawn-worktree.test.sh
# The permission pipeline (epic-17 W3 S5, spec AC-6 / D2-final): the shipped template in
# payload/permissions/ and payload/scripts/lib/profile.sh, driven against fixture settings
# files in a temp tree. Hand-listed like every suite outside hooks/.
run "profile.test.sh" bash tests/profile.test.sh
# Command-file conventions (epic-17 W3 S9, spec AC-1): globs payload/commands/*.md.
run "command-format.test.sh" bash tests/command-format.test.sh
# Footprint removal (epic-17 W3 S8, spec AC-4): payload/scripts/remove.sh driven
# against fixture machines — the never-list wall, the per-item consent gates, and
# the standalone door (the script alone, no payload libraries beside it).
# Hand-listed like every suite outside hooks/.
run "remove.test.sh" bash tests/remove.test.sh
# Adopted from the retired root ./test.sh (epic-11 W3). That runner hand-listed
# 8 suites and omitted agent-roles, installer-behavior and marker-verify — a
# false green — but it was the ONLY runner carrying lib/platform.test.sh, so
# retiring it without this line would have traded one blind spot for another.
run "platform.test.sh" bash lib/platform.test.sh
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  run "bootstrap-e2e-docker.sh (mock)" bash tests/bootstrap-e2e-docker.sh
else
  printf '  %-36s ' "bootstrap-e2e-docker.sh (mock)"; echo "⤼ SKIP (docker unavailable)"; skip=$((skip+1))
fi

echo "──────────────────────────────────────────────"
echo "Gating: ${pass} passed, ${fail} failed, ${skip} skipped"
if [ "$fail" -ne 0 ]; then
  echo -e "Failed:${failed}"
  exit 1
fi
echo "All gating suites green ✓"
