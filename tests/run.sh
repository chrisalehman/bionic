#!/usr/bin/env bash
#
# tests/run.sh — one-command test runner for bionic.
#
# No CI needed: just `bash tests/run.sh`. Runs every hermetic suite (no network,
# no auth) plus the Docker mock install e2e when docker is present.
#
#   GATING suites (set the exit code — must be green):
#     hooks/*.test.sh                  hook behavior
#     tests/scripts.test.sh            config well-formedness + hook/script structural checks
#     tests/installer-behavior.test.sh installer fns: gcloud cask, pnpm store, resilience
#     tests/bootstrap-e2e-docker.sh    whole bootstrap on a fresh OS (docker only)
#
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"
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
