#!/usr/bin/env bash
#
# tests/run.sh — one-command test runner for bionic.
#
# No CI needed: just `bash tests/run.sh`. Every gating suite is hermetic — no
# network, no auth, no daemon — and every one of them runs on every invocation.
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
#
# There is no conditional suite and no skip category. The last one was
# tests/bootstrap-e2e-docker.sh, which ran the whole of claude-bootstrap.sh in a
# container; the installer was deleted in epic-17 W5 (4/6) and the suite went
# with it (W5 audit F-3) — it had been green only because the Docker daemon was
# down, and would have gone red the moment a contributor ran it daemon-up.
#
# ── TWO MODES, ONE ROSTER (epic-17 W7 S10, spec AC-16) ───────────────────────
#
#   bash tests/run.sh              four suites at a time (the default)
#   bash tests/run.sh --serial     one at a time, in roster order
#   BIONIC_TEST_JOBS=8 bash tests/run.sh      a different width
#   BIONIC_TEST_TIMING=t.tsv bash tests/run.sh   also write <label>TAB<seconds>
#
# The `run` lines below are the roster in BOTH modes — they are the only place a
# suite is named, and neither mode has a list of its own. In --serial each line
# runs where it stands; by default each line enqueues, the queue drains through
# xargs -P, and the results print afterwards in roster order. Same labels, same
# captured-output blocks, same `Gating:` line, same exit status: a mode is a
# scheduling choice and nothing else.
#
# WHY IT IS SAFE TO RUN THEM AT ONCE. Not by assumption — by audit. Epic-17 W7 S8
# read every suite in this roster for fixture root, every write outside it and every
# read of machine state another suite could mutate, and found no shared write, no
# shared lock, no fixed port and no fixed /tmp name: every suite that touches disk
# does so under its own `mktemp -d`, and the one place many of them read concurrently
# (this checkout, via tests/lib/resolve-roots.sh) has no writer in the roster at all.
# THE AUDIT IS TWO FILES, and a maintainer needs both: S8 read the 44 suites that
# existed when it ran (`.bionic/docs/record/epic-17-w7/s8-isolation-audit.md`), and
# S8b read the one the same wave added, env.test.sh, which appears nowhere in the
# first file (`.bionic/docs/record/epic-17-w7/s8b-isolation-delta.md`). The roster
# below is 45. A new suite that writes outside its own mktemp root breaks this
# premise, which is the other reason the roster is hand-listed: adding a line is the
# moment to check — and to extend the audit, since neither existing file can cover
# a suite written after it.
#
# WHY FOUR AND NOT FORTY-FIVE. Measured, not guessed. When seven of these slices
# each ran a full suite concurrently on one machine, free memory fell to ~188 MB
# and the kernel SIGKILLed a suite mid-run (W7 assumption A4.2). Four was the width
# with headroom on that measurement; the default was raised to eight on 2026-08-22
# (ef23f75, user's call) and BIONIC_TEST_JOBS is there for a machine with less or more.
#
# WHY A SIGNAL DEATH IS NOT A FAILED ASSERTION. That same kill was reported as a
# plain ✗ FAIL, which reads as "this suite's assertions failed" and sends the
# reader hunting a defect that is not there. A suite that dies by signal now says
# so and names the signal. It still counts as failed and still fails the run —
# what changed is that the report is true.
#
set -uo pipefail
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

# ── one suite, in its own process ────────────────────────────────────────────
# `run.sh --one <label>` is not a mode anyone types: it is what xargs forks for
# each queued suite. It looks its command up in the queue by label, captures the
# suite's output to <label>.out and leaves the exit status in <label>.rc and the
# elapsed seconds in <label>.sec beside it.
#
# IT ALWAYS EXITS 0. A suite's verdict travels in its .rc file, never in this
# process's status — xargs abandons a queue when a child exits nonzero, so a
# worker that forwarded a red suite's status would stop the run at the first red
# suite and leave the rest unreported.
if [ "${1:-}" = "--one" ]; then
  _one_label="${2:?run.sh --one needs a suite label}"
  _one_queue="${BIONIC_TEST_QUEUE:?run.sh --one is an internal mode}"
  _one_work="${BIONIC_TEST_WORK:?run.sh --one is an internal mode}"
  _one_cmd="$(awk -F'\t' -v l="$_one_label" '$1 == l { print $2; exit }' "$_one_queue")"
  _one_start="$(date +%s)"
  # Deliberately unquoted. The queued string is a roster line's own words
  # (`bash tests/foo.test.sh`), written in this file — never outside input.
  # shellcheck disable=SC2086
  $_one_cmd >"$_one_work/${_one_label}.out" 2>&1
  _one_rc=$?
  printf '%s\n' "$_one_rc" >"$_one_work/${_one_label}.rc"
  printf '%s\n' "$(( $(date +%s) - _one_start ))" >"$_one_work/${_one_label}.sec"
  exit 0
fi

# ── argv ─────────────────────────────────────────────────────────────────────
# Refused, not ignored. Before this slice the runner read no argv at all, so
# `bash tests/run.sh --serial` ran the whole roster and looked like it had
# honoured a flag it had never heard of.
SERIAL=0
while [ $# -gt 0 ]; do
  case "$1" in
    --serial) SERIAL=1 ;;
    -h|--help)
      echo "usage: bash tests/run.sh [--serial]"
      echo "  --serial            one suite at a time, in roster order"
      echo "  BIONIC_TEST_JOBS    how many at a time otherwise (default 8)"
      echo "  BIONIC_TEST_TIMING  a file to append <label>TAB<seconds> to"
      exit 0
      ;;
    *)
      echo "tests/run.sh: unknown option: $1" >&2
      echo "usage: bash tests/run.sh [--serial]" >&2
      exit 2
      ;;
  esac
  shift
done
JOBS="${BIONIC_TEST_JOBS:-8}"

( . tests/lib/resolve-roots.sh
  printf 'Roots: hooks=%s skills=%s scripts=%s\n\n' \
    "$BIONIC_HOOKS_DIR" "$BIONIC_SKILLS_DIR" "$BIONIC_SCRIPTS_DIR" )

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
QUEUE="$TMP/queue"; : >"$QUEUE"
export BIONIC_TEST_QUEUE="$QUEUE" BIONIC_TEST_WORK="$TMP"

pass=0; fail=0; failed=""

# Opt-in, and opt-in on purpose: no per-suite timing has ever existed (W7 S8
# finding (c) had to answer "which suite is the long pole" with a line-count
# proxy), and a gating run's output must not change just because someone wanted
# the numbers.
_timing() {  # _timing <label> <seconds>
  [ -n "${BIONIC_TEST_TIMING:-}" ] || return 0
  printf '%s\t%s\n' "$1" "$2" >>"$BIONIC_TEST_TIMING"
}

_label() { printf '  %-36s ' "$1"; }

# _verdict <label> <exit-status-or-empty> <captured-output-file>
# The one place a result is judged and printed, so the two modes cannot drift.
_verdict() {
  local label="$1" rc="$2" out="$3" sig=""
  if [ "$rc" = "0" ]; then
    echo "✓ PASS"; pass=$((pass+1)); return
  fi
  fail=$((fail+1))
  if [ -z "$rc" ]; then
    # No .rc file: the worker itself did not survive to write one.
    echo "✗ KILLED (no exit status recorded)"
    failed="${failed}\n    - ${label} (killed, no exit status)"
  elif [ "$rc" -gt 128 ] 2>/dev/null && sig="$(kill -l $((rc - 128)) 2>/dev/null)" && [ -n "$sig" ]; then
    echo "✗ KILLED (SIG${sig})"
    failed="${failed}\n    - ${label} (killed by SIG${sig})"
  else
    echo "✗ FAIL"
    failed="${failed}\n    - ${label}"
  fi
  echo "───── ${label}: captured output ─────"
  [ -f "$out" ] && cat "$out"
  echo "───── end ${label} ─────"
}

run() {  # run <label> <cmd...>   — gating
  local label="$1"; shift
  if [ "$SERIAL" -eq 1 ]; then
    local start rc
    _label "$label"
    start="$(date +%s)"
    "$@" >"$TMP/${label}.out" 2>&1
    rc=$?
    _timing "$label" "$(( $(date +%s) - start ))"
    _verdict "$label" "$rc" "$TMP/${label}.out"
  else
    printf '%s\t%s\n' "$label" "$*" >>"$QUEUE"
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
# Cross-FILE proof (epic-17 W4 S7, spec AC-5 / epic AC-11): the terminal-disposition
# rule's normative literal, pinned byte-identical between SKILL.md's Step 9 and
# operational-rules.md's close-out section, plus a count-scoped guard against a
# third, unpinned copy landing under skills/ or agents/. Same class as
# interview-protocol.test.sh above (a SKILL.md <-> operational-rules.md pin), kept
# in its own file because it is a distinct ownership-table concept.
run "close-out.test.sh" bash tests/close-out.test.sh
# Cross-COMPONENT proofs (epic-15 W1R slice 4/6). They belong to no single hook,
# so they live here rather than under hooks/ — which also means they are invisible
# to the glob above and must stay hand-listed.
run "cross-gate-agreement.test.sh" bash tests/cross-gate-agreement.test.sh
run "fail-direction-table.test.sh" bash tests/fail-direction-table.test.sh
# Epic-17 wave-01 slice S1: bionic plugin manifest + marketplace manifest + LICENSE.
run "plugin-manifest.test.sh" bash tests/plugin-manifest.test.sh
# Harness-on-harness (epic-17 W1). Pins the assertion helpers every suite above
# hand-copies: under pipefail, `printf "$haystack" | grep -q` is a SIGPIPE race
# that reports a present needle as missing and an absent-check as green. Also
# hand-listed, same reason as the two lines above.
run "assert-helper-race.test.sh" bash tests/assert-helper-race.test.sh
# Cross-FILE proof (epic-17 W1 S3): the plugin-layout path rewrite, and the near-identical
# state paths it must not have touched. Spans SKILL.md, hooks/ and the payload's own
# registration surfaces, so like the two above it belongs to no single hook and must stay
# hand-listed.
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
# The read-only probes added at epic-17 W6 S2 (spec R5/AC-8, AC-9; R8/AC-13):
# detect_plugin_load_state and detect_plugin_duplicates, driven against the
# `claude plugin list` transcripts captured during W5's F12 measurement and a
# planted plugin registry. Its own suite rather than a group in plugin-lib —
# different fixture regime (a captured CLI transcript, not a fixture tree) — and
# so, like every suite outside hooks/, hand-listed here or it never runs.
run "detect-probes.test.sh" bash tests/detect-probes.test.sh
# The worktree contract (epic-17 W3 S2, spec AC-10 / D4): payload/scripts/spawn-worktree.sh
# driven against scratch git repositories, with its attestation line pinned byte-exactly
# because dispatchers quote that line into their ledger rows. Its own suite rather than a
# section of plugin-lib.test.sh — different subject, different fixture regime — and so,
# like every suite outside hooks/, hand-listed here or it never runs.
run "spawn-worktree.test.sh" bash tests/spawn-worktree.test.sh
# The JIT / degradation contract (epic-17 W3 S10, spec AC-5): payload/scripts/lib/jit.sh's
# jit_check + jit_offer, driven against a fixture PATH, proving jit_offer calls install_dep
# BY NAME (the ownership-table agreement) and mutates nothing on decline. Hand-listed like
# every suite outside hooks/.
run "jit.test.sh" bash tests/jit.test.sh
# The environment settings (epic-17 W7 S4, spec R4 / AC-5..AC-7):
# payload/scripts/lib/env.sh — the `env` object in settings.json, the merge that adds one
# name without touching the rest of the file, and the difference between a value the FILE
# carries and a value THIS PROCESS has. Hand-listed like every suite outside hooks/.
run "env.test.sh" bash tests/env.test.sh
# Command-file conventions (epic-17 W3 S9, spec AC-1): globs payload/commands/*.md.
run "command-format.test.sh" bash tests/command-format.test.sh
# Command PERMISSIONS (epic-17 W6 S9b, walk finding W-1 / plan A-5.4): the byte-for-byte
# agreement between each command file's own `allowed-tools` rule prefix and every fenced
# `bash` invocation in that same file. A permission rule prefix-matches the literal command string, so one quote
# character in a body silently un-authorizes it — which is what walled bionic's own
# commands. Hand-listed like every suite outside hooks/.
run "command-permissions.test.sh" bash tests/command-permissions.test.sh
# The end-user README (epic-17 W6 S8, spec AC-4): README.md's "## Installation
# (30-second setup)" section pinned to the ratified reference shape — two
# `claude plugin` command lines, the in-session twin, the `claude plugin list`
# fallback, zero mechanism words. Hand-listed like every suite outside hooks/.
# The presentation contract (epic-17 W6 S1, spec R3 / AC-5 / AC-6): the one voice block at
# agents-src/blocks/voice-contract.md, its byte-identical presence in all four shipped
# command files, help.md's render-in-full instruction, and the banned-display-vocabulary
# lint over the command surface. Staleness of the render itself belongs to
# agent-render.test.sh; this suite owns presence and content. Hand-listed like every suite
# outside hooks/.
# The other half of AC-6 (epic-17 W6 S4): every line setup.sh, doctor.sh and remove.sh PRINT
# judged against the same one banned-vocabulary list voice-contract.test.sh reads — display
# verbs, prompts, and the self-appending accumulators the action and degradation lines are
# built in. Hand-listed like every suite outside hooks/.
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
# The pristine-install suite (epic-18 T6, spec AC-10/AC-7): empty $HOME through
# setup --all, doctor, remove --all, asserted against a manifest of bytes rather
# than a report's own summary line. Registered at T10 per its own header — it was
# deliberately kept out of the roster while the two arms it exercises
# (ccstatusline's layout copy, notebooklm's skill install) were still unmerged,
# so it would not sit red in a gating run. Hand-listed like every suite outside
# hooks/.
run "fresh-home.test.sh" bash tests/fresh-home.test.sh
# lib/platform.test.sh RETIRED at epic-17 W5 (Step-6 review). The library it
# covered exported OS, BREW_PREFIX, SHELL_RC, PLAYWRIGHT_CACHE and sed_inplace
# for exactly two consumers — claude-bootstrap.sh and claude-reset.sh — and 4/6
# deleted both. Nothing in the payload ever sourced it, so from that commit its
# own suite was its only consumer and the pair was a closed loop testing itself.
# Where the facts went, so this is a move and not a loss: the shell rc lives in
# detect.sh (_detect_shell_rc) and remove.sh (_rm_shell_rc), the Playwright cache
# in the dep table's BIONIC_PLAYWRIGHT_CACHE probe, and the payload does its own
# rewriting in bash rather than sed, so sed_inplace has no successor because it
# has no question left to answer.


# ── drain the queue, then report in roster order ─────────────────────────────
# Nothing above printed a result in the default mode; every `run` line enqueued.
# The suites run now, four at a time, each in its own process writing its own
# files; then the queue is walked again IN ORDER so the report reads the same as
# a serial one — a reader comparing two runs is comparing rosters, not schedules.
if [ "$SERIAL" -eq 0 ]; then
  cut -f1 "$QUEUE" | xargs -P "$JOBS" -n1 bash "$SELF" --one
  while IFS="$(printf '\t')" read -r label _queued_cmd; do
    [ -n "$label" ] || continue
    _label "$label"
    rc=""
    [ -f "$TMP/${label}.rc" ] && rc="$(cat "$TMP/${label}.rc")"
    [ -f "$TMP/${label}.sec" ] && _timing "$label" "$(cat "$TMP/${label}.sec")"
    _verdict "$label" "$rc" "$TMP/${label}.out"
  done <"$QUEUE"
fi

echo "──────────────────────────────────────────────"
echo "Gating: ${pass} passed, ${fail} failed"
if [ "$fail" -ne 0 ]; then
  echo -e "Failed:${failed}"
  exit 1
fi
echo "All gating suites green ✓"
