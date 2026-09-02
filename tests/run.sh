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
#   bash tests/run.sh              eight suites at a time (the default)
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
# first file (`.bionic/docs/record/epic-17-w7/s8b-isolation-delta.md`). Neither file
# covers the roster as it stands now: epic-18 wave-03 deleted nineteen of those
# suites on the reliability ruling (commit 8582861), one of the nineteen
# (fresh-home.test.sh) was later revived, rc-item.test.sh was added new, and
# epic-19 wave-01 added doctor-patrol.test.sh (F3) and command-relay.test.sh
# (F4), and bionic 1.3.2 added git-argv, cmd-class and patrol-marker — 31 `run` lines as of this writing (`grep -c '^run "' tests/run.sh`
# equals `ls tests/*.test.sh | wc -l`;
# a maintainer re-derives the count rather than trusting a number in a
# comment, this one included). Neither audit file re-covers what changed since
# it ran; a suite added or restored after S8b carries no isolation proof
# beyond its own file. A suite that writes outside its own mktemp root breaks this
# premise, which is the other reason the roster is hand-listed: adding a line is the
# moment to check — and to extend the audit, since neither existing file can cover
# a suite written after it.
#
# WHY EIGHT (FOUR AT MEASUREMENT TIME) AND NOT FORTY-FIVE. Measured, not guessed. When
# seven of these slices each ran a full suite concurrently on one machine, free memory
# fell to ~188 MB and the kernel SIGKILLed a suite mid-run (W7 assumption A4.2). Four was
# the width with headroom on that measurement; the default was raised to eight on
# 2026-08-22 (ef23f75, user's call) and BIONIC_TEST_JOBS is there for a machine with less
# or more.
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
run "dispatch-preflight.test.sh" bash tests/dispatch-preflight.test.sh
run "execution-recorder.test.sh" bash tests/execution-recorder.test.sh
run "landing-gate.test.sh" bash tests/landing-gate.test.sh
run "patrol-duties-gate.test.sh" bash tests/patrol-duties-gate.test.sh
run "patrol-revive.test.sh" bash tests/patrol-revive.test.sh
run "preflight-probe.test.sh" bash tests/preflight-probe.test.sh
run "protect-database.test.sh" bash tests/protect-database.test.sh
run "protect-main.test.sh" bash tests/protect-main.test.sh
run "session-poker.test.sh" bash tests/session-poker.test.sh
run "session-sweeper.test.sh" bash tests/session-sweeper.test.sh
run "stop-check.test.sh" bash tests/stop-check.test.sh
run "stop-guard.test.sh" bash tests/stop-guard.test.sh
run "stop-orders.test.sh" bash tests/stop-orders.test.sh
# agent-render.test.sh (the agent-file render pipeline, epic-17 W4 S2) and its terminal-
# disposition cross-file pin (epic-17 W4 S7) were deleted at 8582861 (epic-18 wave-03);
# nothing replaced either.
# Cross-COMPONENT proofs (epic-15 W1R slice 4/6). They belong to no single hook,
# so they live here rather than under hooks/ — which also means they are invisible
# to the glob above and must stay hand-listed.
run "cross-gate-agreement.test.sh" bash tests/cross-gate-agreement.test.sh
run "fail-direction-table.test.sh" bash tests/fail-direction-table.test.sh
# plugin-manifest.test.sh (epic-17 wave-01 S1), assert-helper-race.test.sh (epic-17 W1,
# the SIGPIPE-race lesson every suite above still cites), plugin-paths.test.sh (epic-17
# W1 S3, the plugin-layout path rewrite) and plugin-payload.test.sh (epic-17 W1 S6, the
# payload-boundary pin) were all deleted at 8582861 (epic-18 wave-03); nothing replaced
# any of them.
# Harness-on-harness (epic-17 W2 S1). Catch-proof for tests/lib/resolve-roots.sh, the
# path-resolution seam every suite sources: plants a doctored tree and proves the
# override binds in BOTH directions. Belongs to no single hook, so hand-listed.
run "seam-resolution.test.sh" bash tests/seam-resolution.test.sh
# version-ssot.test.sh (epic-17 W2 S4, the plugin.json version-owner pin) and
# plugin-lib.test.sh ("Payload libraries", epic-17 W3 S1 — the deps.sh SSoT table and
# detect.sh's machine-fact functions, driven against fixture roots and a fixture PATH)
# were both deleted at 8582861 (epic-18 wave-03); nothing replaced either.
# The read-only probes added at epic-17 W6 S2 (spec R5/AC-8, AC-9; R8/AC-13):
# detect_plugin_load_state and detect_plugin_duplicates, driven against the
# `claude plugin list` transcripts captured during W5's F12 measurement and a
# planted plugin registry. Its own suite rather than a group in plugin-lib.test.sh
# (deleted at 8582861, epic-18 wave-03) — different fixture regime (a captured CLI
# transcript, not a fixture tree) — and so, like every suite outside hooks/,
# hand-listed here or it never runs.
run "detect-probes.test.sh" bash tests/detect-probes.test.sh
# The worktree contract (epic-17 W3 S2, spec AC-10 / D4): payload/scripts/spawn-worktree.sh
# driven against scratch git repositories, with its attestation line pinned byte-exactly
# because dispatchers quote that line into their ledger rows. Its own suite rather than a
# section of plugin-lib.test.sh (deleted at 8582861, epic-18 wave-03) — different subject,
# different fixture regime — and so, like every suite outside hooks/, hand-listed here or
# it never runs.
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
# The session-id function (bionic 1.4.0 wave, spec AC-2, plan slice L-SESSION):
# payload/scripts/lib/session.sh's session_id — env is primary, a payload sid
# is a witness only; divergence prints once and env still wins. Hand-listed
# like every suite outside hooks/.
run "session.test.sh" bash tests/session.test.sh
# The rc item (epic-18 wave-03 slice 4/7, spec R6 / AC-5, AC-6): the `claude()`
# shell function as a setup-managed item — env.sh's roster and rc write/read/delete,
# the consented step in setup.sh, doctor's row, and remove.sh's strip through both
# of its doors, driven against sandbox HOMEs with a planted .zshrc and read back
# through a real `zsh -ic 'type claude'`. Hand-listed like every suite outside hooks/.
run "rc-item.test.sh" bash tests/rc-item.test.sh
# The pristine-install suite (epic-18 T6, spec AC-10/AC-7; revived and raised at
# wave-03 on Chris's D2): an empty $HOME through `setup --all` all-yes, `doctor`,
# and `remove --all`, asserted against a MANIFEST of bytes rather than against a
# report's own summary line. It is the only suite that starts from nothing and
# the only one that reads all three scripts in one machine's lifetime, which is
# also why it now carries the rc item — setup's newest write target, and the one
# that lands in a file the user already owned. Hand-listed like every suite here.
run "fresh-home.test.sh" bash tests/fresh-home.test.sh
# The PATROL section (F3, epic-19 wave-01, spec AC-F3): payload/scripts/doctor.sh's
# running-Patrols-or-nothing render, driven against a fixture claude-home (a real
# spawned process + a planted transcript) and a fixture repo's roster file — no
# doctor.test.sh existed before this suite (the broad one, epic-17 W3 S7, was
# deleted at 8582861 for fingerprinting the whole machine). Hand-listed like every
# suite outside hooks/.
run "doctor-patrol.test.sh" bash tests/doctor-patrol.test.sh
# The command-relay contract (F4, epic-19 wave-01, spec AC-F4): the shared
# voice-contract block (and every rendered command file it reaches) demands a
# fenced code block rather than the collapsible "one block", proven alongside
# `render.sh --check` so a template edit without a re-render goes red here too;
# and setup.sh's item()/plan-verb free-form fields — which routinely carry
# absolute paths with no bound — stay inside the same 100-column budget
# doctor.sh already holds itself to (AC-15). Hand-listed like every suite
# outside hooks/.
run "command-relay.test.sh" bash tests/command-relay.test.sh
# The installed-vs-latest version row (F5, epic-19 wave-01, spec AC-F5):
# doctor.sh's BIONIC NATIVE table gains a per-feed-kind `version` row — a git
# feed compares against the marketplace's cached clone and names the exact
# repair command on lag, a directory feed consumes the existing registry-sha
# lag/reconverge machinery instead of a meaningless self-compare, and an
# undeterminable feed kind degrades to an honest `unknown` line. Hand-listed
# like every suite outside hooks/.
run "doctor-version.test.sh" bash tests/doctor-version.test.sh
# bionic 1.3.2 (wave-01-dogfood-fixes, 2026-08-30) — three suites for the three shared-truth
# additions of that wave, each hand-listed like every suite outside hooks/:
#   - git-argv.test.sh: scripts/lib/git-argv.sh (the git-argv reading protect-main and the
#     evidence gate source), the fail-closed sourcing proof, and the in-tree `source` pin
#   - cmd-class.test.sh: scripts/lib/cmd-class.sh (the argv-positional suite-class reading
#     farm-out-reminder and background-suite-guard source), same fail-closed proof
#   - patrol-marker.test.sh: the `session-poker.sh tick` marker pinned across its three
#     spellings (lib/patrol.sh SSoT, patrol-duties-gate.sh, SKILL.md)
run "git-argv.test.sh" bash tests/git-argv.test.sh
run "cmd-class.test.sh" bash tests/cmd-class.test.sh
run "patrol-marker.test.sh" bash tests/patrol-marker.test.sh
# bionic 1.4.0 (wave-bionic-1.4.0-update, L-RUN slice, spec AC-8): the one library function
# `active_run` — docs_root, active_plan, active_run — that every always-on hook gates its
# own work behind. Hand-listed like every suite outside hooks/.
run "run-predicate.test.sh" bash tests/run-predicate.test.sh
# bionic 1.4.0 (wave-bionic-1.4.0-update, slice L-LOADER, spec AC-16) — the one loader
# idiom. payload/scripts/lib/loader.sh carries the canonical text between
# `# --- bionic-loader/v2 BEGIN` / `# --- bionic-loader/v2 END`; this suite pastes that
# text into throwaway hooks under its own mktemp root and drives the three candidate
# classes, the two fail policies and the four-command repair allowlist. Hermetic: HOME
# and BIONIC_PLUGINS_DIR are overridden per run, so the real ~/.claude is never read.
run "loader.test.sh" bash tests/loader.test.sh
# ── bionic 1.4.0, the library spine (wave-bionic-1.4.0-update) ────────────────
#   - root.test.sh: scripts/lib/root.sh — `project_root` / `project_root_candidates`,
#     seven real on-disk topologies (nested repo under a .bionic workspace, linked
#     worktree, phantom nested .bionic, symlinked .bionic, .bionic inside $HOME,
#     unrelated repo, no-git/no-.bionic) each paired with a differential control
run "root.test.sh" bash tests/root.test.sh
# bionic 1.4.0 (L-DETECT/4.4, spec AC-21): scripts/lib/shell.sh's shell_rc_file, the one
# rc-file resolver detect.sh's and remove.sh's shell-rc functions now both delegate to,
# pinned structurally (thin caller, no hand-rolled case split) and by cross-file agreement
# across zsh/bash/fish/unrecognized $SHELL.
run "shell-rc.test.sh" bash tests/shell-rc.test.sh
# bionic 1.4.0 (L-DETECT/4.2, spec AC-19): scripts/lib/detect.sh's version_compare, a
# semver-shaped three-int ordering primitive replacing the string-inequality compare in
# detect_plugin_latest, which gains a real `ahead` state for an installed build newer
# than the marketplace's cached clone.
run "version-compare.test.sh" bash tests/version-compare.test.sh
# bionic 1.4.0 (L-DETECT/4.5, spec AC-22): scripts/lib/patrol.sh's PATROL_STALE_MULTIPLIER,
# one exported staleness constant replacing the inline "twice the poker interval" literal in
# patrol_stamp_state's own reader (session-poker.sh and dispatch-preflight.sh switch to it in
# later slices).
run "patrol-stale.test.sh" bash tests/patrol-stale.test.sh
# bionic 1.4.0 (wave-bionic-1.4.0-update, 2026-09-02) — the library spine's unit suites, one
# per fact, hand-listed like every suite outside hooks/:
#   - resources.test.sh: scripts/lib/resources.sh (probe / budget / pressure — the parallel
#     budget as a function of the machine instead of a number a human guessed) and the
#     version-2 preflight attestation that records it. The kill datum this suite's memory
#     term is built on is the one written at :63-68 of this file.
run "resources.test.sh" bash tests/resources.test.sh
#   - docs-pins.test.sh: doc-text agreement pins with no other home. §1 (RELEASE, spec
#     AC-36) is the help version pair — replaces the coverage version-ssot.test.sh had
#     before it was deleted below; WALLS and SCHED append their own numbered sections
#     to this same file in later slices of this wave rather than each owning a suite.
run "docs-pins.test.sh" bash tests/docs-pins.test.sh
# The following suites were deleted at 8582861 (epic-18 wave-03, the MEDIUM/LOW-reliability
# ruling) and nothing replaced their coverage:
#   - command-format.test.sh (epic-17 W3 S9) — payload/commands/*.md conventions
#   - command-permissions.test.sh (epic-17 W6 S9b) — allowed-tools <-> fenced-command agreement
#   - diagrams.test.sh (epic-17 W4 S8) — the two composed-SVG diagram pins
#   - setup.test.sh (epic-17 W3 S6) — payload/scripts/setup.sh driven end to end
#   - doctor.test.sh (epic-17 W3 S7) — the read-only diagnosis, no-mutation wall
#   - remove.test.sh (epic-17 W3 S8) — footprint removal, the never-list wall, the
#     standalone door (this is the suite the epic-18 wave-03 citesweep started from)
#   - close-out.test.sh, agent-roles.test.sh — no live description survived in this file
# voice-contract.test.sh (epic-17 W6 S1, the presentation contract) and
# script-vocabulary.test.sh (epic-17 W6 S4, the same banned-vocabulary lint applied to
# setup.sh/doctor.sh/remove.sh's own print output) were deleted earlier still, in an
# unrelated purge, commit b959b5e.
# See `git show --stat 8582861 -- tests/` for the full list of nineteen deleted files.
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
# The suites run now, $JOBS at a time (eight by default), each in its own process
# writing its own files; then the queue is walked again IN ORDER so the report reads the same as
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
