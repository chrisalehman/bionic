#!/usr/bin/env bash
#
# tests/run.sh — one-command test runner for bionic.
#
# No CI needed: just `bash tests/run.sh`. Runs every hermetic suite (no network,
# no auth) plus the Docker mock install e2e when docker is present.
#
#   GATING suites (set the exit code — must be green):
#     the hand-listed `run` lines below, one per suite — nothing here is
#                                      globbed; a new suite is invisible until
#                                      its `run` line is added by name (epic-17
#                                      W4 S9: hooks/*.test.sh moved under tests/,
#                                      which retired the old hooks/*.test.sh glob
#                                      — hooks/ now holds only the hook scripts
#                                      themselves, and tests/ is not
#                                      hook-exclusive, so uniform hand-listing is
#                                      the only honest discovery left)
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
# Moved from hooks/*.test.sh (epic-17 W4 S9, spec AC-9 / D3 "move the tests"): one
# hook behavior suite per hook script, hand-listed like every suite below —
# hooks/ retains only the *.sh scripts themselves, so there is no longer a
# directory whose contents are safely globbable as "the hook tests".
run "agent-context-guard.test.sh" bash tests/agent-context-guard.test.sh
run "canonical-sdlc-evidence-gate.test.sh" bash tests/canonical-sdlc-evidence-gate.test.sh
run "canonical-sdlc-governing-skill.test.sh" bash tests/canonical-sdlc-governing-skill.test.sh
run "context-spend.test.sh" bash tests/context-spend.test.sh
run "dispatch-preflight.test.sh" bash tests/dispatch-preflight.test.sh
run "execution-recorder.test.sh" bash tests/execution-recorder.test.sh
run "farm-out-reminder.test.sh" bash tests/farm-out-reminder.test.sh
run "landing-gate.test.sh" bash tests/landing-gate.test.sh
run "preflight-probe.test.sh" bash tests/preflight-probe.test.sh
run "protect-database.test.sh" bash tests/protect-database.test.sh
run "protect-main.test.sh" bash tests/protect-main.test.sh
run "session-poker.test.sh" bash tests/session-poker.test.sh
run "session-sweeper.test.sh" bash tests/session-sweeper.test.sh
run "stop-check.test.sh" bash tests/stop-check.test.sh
run "stop-guard.test.sh" bash tests/stop-guard.test.sh
run "stop-orders.test.sh" bash tests/stop-orders.test.sh
run "scripts.test.sh" bash tests/scripts.test.sh
run "agent-roles.test.sh" bash tests/agent-roles.test.sh
# The agent-file render pipeline (epic-17 W4 S2, spec AC-2): agents-src/ blocks + templates
# + render.sh against the committed finals under agents/. Cross-FILE by nature — it spans a
# source tree and an output tree.
run "agent-render.test.sh" bash tests/agent-render.test.sh
run "interview-protocol.test.sh" bash tests/interview-protocol.test.sh
# Cross-FILE proof (epic-17 W4 S7, spec AC-5 / epic AC-11): the terminal-disposition
# rule's normative literal, pinned byte-identical between SKILL.md's Step 9 and
# operational-rules.md's close-out section, plus a count-scoped guard against a
# third, unpinned copy landing under skills/ or agents/. Same class as
# interview-protocol.test.sh above (a SKILL.md <-> operational-rules.md pin), kept
# in its own file because it is a distinct ownership-table concept.
run "close-out.test.sh" bash tests/close-out.test.sh
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
# The JIT / degradation contract (epic-17 W3 S10, spec AC-5): payload/scripts/lib/jit.sh's
# jit_check + jit_offer, driven against a fixture PATH, proving jit_offer calls install_dep
# BY NAME (the ownership-table agreement) and mutates nothing on decline. Hand-listed like
# every suite outside hooks/.
run "jit.test.sh" bash tests/jit.test.sh
# Command-file conventions (epic-17 W3 S9, spec AC-1): globs payload/commands/*.md.
run "command-format.test.sh" bash tests/command-format.test.sh
# The diagram pins (epic-17 W4 S8, spec AC-6 / design D4): the two composed-SVG diagrams
# under skills/canonical-sdlc/diagrams/ read as text and compared against what they draw —
# the hooks' SUPPORTED_SDLC_VERSION, hooks.json's six always-on entries, and SKILL.md's ten
# steps and frontmatter hook set. Spans hooks/, skills/ and the SVGs.
run "diagrams.test.sh" bash tests/diagrams.test.sh
# /bionic:setup (epic-17 W3 S6, spec AC-2 / AC-6): payload/scripts/setup.sh driven end to
# end against fixture trees and a stateful `claude` shim on a replaced PATH, with the
# fixture bytes as the evidence for every consented, declined and idempotent claim.
# Hand-listed like every suite outside hooks/.
run "setup.test.sh" bash tests/setup.test.sh
# The read-only diagnosis (epic-17 W3 S7, spec AC-3): payload/scripts/doctor.sh driven over
# whole fixture MACHINES — payload tree, plugin registry, settings, rc, caches — with a
# no-mutation wall (sha256 + path enumeration, before and after) as its axis test.
run "doctor.test.sh" bash tests/doctor.test.sh
# Footprint removal (epic-17 W3 S8, spec AC-4): payload/scripts/remove.sh driven
# against fixture machines — the never-list wall, the per-item consent gates, and
# the standalone door (the script alone, no payload libraries beside it).
# Hand-listed like every suite outside hooks/.
run "remove.test.sh" bash tests/remove.test.sh
# Adopted from the retired root ./test.sh (epic-11 W3). That runner hand-listed
# 8 suites and omitted agent-roles and marker-verify — a
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
