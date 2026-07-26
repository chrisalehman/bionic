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
# The verifier's own behaviour gate. The verifier's DEFAULT run (over the real
# governed surfaces) is deliberately not wired here yet: the surfaces are marked
# in slices 4/3–4/5, and a gate that fails until then would take this suite red
# mid-wave. adr-005's prose → data → hook-with-log-only-first pattern.
run "marker-verify.test.sh" bash tests/marker-verify.test.sh
# Same for the mutation-and-restore harness: its behaviour gate runs here, its
# default run over the real surfaces does not. With no markers applied yet the
# default run reports E-NO-POINTERS — correctly, since nothing has been proven.
run "marker-discriminates.test.sh" bash tests/marker-discriminates.test.sh
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
