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
# Adopted from the retired root ./test.sh (epic-11 W3). That runner hand-listed
# 8 suites and omitted agent-roles, installer-behavior and marker-verify — a
# false green — but it was the ONLY runner carrying lib/platform.test.sh, so
# retiring it without this line would have traded one blind spot for another.
run "platform.test.sh" bash lib/platform.test.sh
# The verifier's own behaviour gate, then its DEFAULT run over the real governed
# surfaces. The default run was deliberately unwired while slices 4/3–4/5 were
# still marking (a gate failing until then would have taken this suite red
# mid-wave); marking completed at unmarked=0, so it is wired now. Without it the
# floor could report green while the real instruction surface carried unmarked
# statements — a false green in the instrument that exists to catch false greens.
run "marker-verify.test.sh" bash tests/marker-verify.test.sh
run "marker-verify.sh (surfaces)" bash tests/marker-verify.sh
# Same for the mutation-and-restore harness: behaviour gate, then the default run
# proving every WALL/FORM pointer still goes RED when its enforcement is removed.
# A marker whose test stopped discriminating is a claim with a dead citation, and
# this is the only check that catches it.
run "marker-discriminates.test.sh" bash tests/marker-discriminates.test.sh
run "marker-discriminates.sh (pointers)" bash tests/marker-discriminates.sh
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
