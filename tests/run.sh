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
run "decision-baseline.test.sh" bash tests/decision-baseline.test.sh
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  run "bootstrap-e2e-docker.sh (mock)" bash tests/bootstrap-e2e-docker.sh
else
  printf '  %-36s ' "bootstrap-e2e-docker.sh (mock)"; echo "⤼ SKIP (docker unavailable)"; skip=$((skip+1))
fi

# ── Instruments: MEASURED, never gating ────────────────────────────────────
# These are measurement instruments, not gates. They must never set the exit
# code — a metric that can fail the suite becomes a number people tune instead
# of a number they read. They run here so the instruments cannot become orphan
# scripts that rot unnoticed: before this, tests/metrics.sh was reachable only
# by hand, which is how an "add a metric" task ends up measuring nothing.
echo ""
echo "Instruments (measured, never gating):"
instrument() {  # instrument <label> <cmd...>
  local label="$1"; shift
  printf '  %-36s ' "$label"
  if "$@" >"$TMP/inst" 2>&1; then
    echo "✓ $(grep -c . "$TMP/inst" | tr -d ' ') rows"
  else
    echo "⤼ unavailable (not a failure)"
  fi
}
instrument "metrics.sh" bash tests/metrics.sh
instrument "decision-baseline.sh" bash tests/decision-baseline.sh
# The headline decision-quality rows, surfaced so the instrument is read rather
# than merely executed. The corpus is live, so these drift slightly run to run;
# BIONIC_CORPUS_DIR pins a frozen corpus when a number must be reproduced.
grep -E '^decision\.(turns|request_turn_pct|ac3_agreement_dedup_pct|ac3_verdict|uncorrected_fire_pct)\b' \
  "$TMP/inst" 2>/dev/null | sed 's/^/      /' || true

echo "──────────────────────────────────────────────"
echo "Gating: ${pass} passed, ${fail} failed, ${skip} skipped"
if [ "$fail" -ne 0 ]; then
  echo -e "Failed:${failed}"
  exit 1
fi
echo "All gating suites green ✓"
