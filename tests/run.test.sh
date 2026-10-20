#!/bin/bash
# tests/run.test.sh — the test runner obeys the user's order.
#
# §ORDER. The user gives an order in words through the poker's `order` verb, which writes an
# `order:` line under the bound plan's SDLC State. While it stands, tests/run.sh asks the gate
# for it and refuses to start a suite, printing the user's words, whoever runs it: the session
# the run is bound to, and a shell with no session key at all. `order lift` ends it, and the
# same suite then runs. This one test is the only check of the order: it is enforced at the
# runner alone, so no other caller is driven.
#
# THE WORLD. A scratch project carrying this tree's runner, its framework and its payload
# libraries, one stub suite that counts its own runs in a file, and a plan bound to the session.
# The poker is this tree's. The gate's store, the share and every machine reading are pinned
# under this suite's own mktemp root, so no drive waits on, or writes, this machine's gate.
#
# FIXTURE FIDELITY. The runner, the framework, the libraries and the poker are this tree's own
# files, copied or run in place; the plan is the shared fixture plan, bound through the real
# bind writer. The stub suite is SYNTHESIZED: one green row and one line appended per run.
#
# ANTI-VACUITY. Each "never ran" count reads the same run log as the lifted run's count of one,
# and the plan's order: lines are read by one extractor that also finds the given line.
#
# Usage: bash tests/run.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"
. "$(dirname "$0")/lib/bound-marker.sh"
. "$(dirname "$0")/lib/plan-fixture.sh"

REPO="$BIONIC_SCRIPTS_DIR"
POKER="${RUN_POKER_UNDER_TEST:-${BIONIC_HOOKS_DIR}/session-poker.sh}"

TMPROOT="$(mktemp -d "${TMPDIR:-/tmp}/run-test.XXXXXX")"
TMPROOT="$(cd "$TMPROOT" && pwd -P)"
trap 'rm -rf "$TMPROOT"' EXIT

SID="5c1e7f20-3a4b-4c8d-9e0f-1a2b3c4d5e6f"
export BIONIC_PLUGINS_DIR="$TMPROOT/no-plugins"
mkdir -p "$BIONIC_PLUGINS_DIR" "$TMPROOT/config/bionic" "$TMPROOT/gate/cost"
printf '80\n' > "$TMPROOT/config/bionic/share"
printf '1:0.1:1:1700000000\n' > "$TMPROOT/gate/cost/seed"
RT_ENV=(-u BIONIC_GATE_ADMIT -u BIONIC_GATE_AGENT -u BIONIC_GATE_LANDING
  "CLAUDE_CONFIG_DIR=$TMPROOT/config" "BIONIC_GATE_DIR=$TMPROOT/gate" BIONIC_GATE_POLL=0.1
  "BIONIC_PRESSURE_RING=$TMPROOT/pressure.ring" BIONIC_PROBE_USED_PCT=10 BIONIC_PROBE_BUSY_CORES=0
  BIONIC_PROBE_BUSY_CORES_5M=0 BIONIC_PROBE_CORES=8 BIONIC_PROBE_TOTAL_MB=8192 BIONIC_PROBE_FREE_PCT=44
  BIONIC_PROBE_SWAP_PCT=0 BIONIC_PROBE_LOAD_1M=0.1 BIONIC_PROBE_FREE_MB=8192)

# ---------- the world ----------
W="$TMPROOT/world"
mkdir -p "$W/tests/lib" "$W/payload/scripts/lib" "$W/.bionic/tmp"
cp "$REPO/tests/run.sh" "$W/tests/run.sh"
cp "$REPO/tests/lib/resolve-roots.sh" "$REPO/tests/lib/assert.sh" "$W/tests/lib/"
cp "$REPO"/payload/scripts/lib/*.sh "$W/payload/scripts/lib/"
cat > "$W/tests/x.test.sh" <<'SUITE'
#!/bin/bash
set -uo pipefail
. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"
printf 'ran\n' >> "$(dirname "$0")/../ran.log"
expect_eq "x runs" "1" "1"
finish
SUITE
( cd "$W" && git init -q . && git config user.name "Dana Fixture" && git config user.email d@example.com \
  && printf '.bionic/\nran.log\n' > .gitignore && git add -A && git commit -qm world ) >/dev/null 2>&1
P="$(plan_fixture "$W/.bionic/docs/plans/epic-99-fixture/wave-01-fixture.plan.md" wave \
  "| T1 | 4 | build | the first build | implementor | — | — | 30 | REQ-1 | a.sh | — | — | pending |")"
bound_marker "$W" "$SID" "$P" >/dev/null 2>&1

rt_poke() {  # <args...> -> OUT, RC: the poker in the world, as the bound session
  OUT="$(cd "$W" && env "${RT_ENV[@]}" CLAUDE_CODE_SESSION_ID="$SID" bash "$POKER" "$@" 2>&1)"; RC=$?
}
rt_run() {  # [nokey] -> OUT, RC: the world's runner on its one suite; nokey drops the session key
  if [ "${1:-}" = nokey ]; then
    OUT="$(cd "$W" && env "${RT_ENV[@]}" -u CLAUDE_CODE_SESSION_ID bash tests/run.sh --only x.test.sh 2>&1)"; RC=$?
  else
    OUT="$(cd "$W" && env "${RT_ENV[@]}" CLAUDE_CODE_SESSION_ID="$SID" bash tests/run.sh --only x.test.sh 2>&1)"; RC=$?
  fi
}
rt_orders() {  # -> the plan's order: lines under its SDLC State
  awk '/^##[[:space:]]/ { s = ($0 ~ /^##[[:space:]]+SDLC State/); next } s && /^order:/' "$P"
}
rt_runs() { if [ -f "$W/ran.log" ]; then wc -l < "$W/ran.log" | tr -d ' '; else printf '0'; fi; }

# ============================================================
section "§ORDER: an order in words stops every suite at the runner, with the words, until it is lifted"
# ============================================================
expect_eq "O0 the world's plan is the session's bound run" "plan=$P" "$(grep '^plan=' "$W/.bionic/tmp/engaged-$SID.state")"
WORDS="no suites until I say"

rt_poke order "$WORDS"
expect_eq "O1 order '<words>' records the order (exit 0)" "0" "$RC"
expect_regex "O1b …as an order: line under the plan's SDLC State, with the time and the words" \
  "^order: given [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z \"$WORDS\"$" "$(rt_orders)"

rt_run
expect_eq "O2 with the order open, the runner refuses (exit 1)" "1" "$RC"
expect_contains "O2b …printing the user's words" "$WORDS" "$OUT"
expect_eq "O2c …and the suite never ran" "0" "$(rt_runs)"
rt_run nokey
expect_eq "O3 a shell with no session key is refused the same (exit 1)" "1" "$RC"
expect_contains "O3b …with the same words" "$WORDS" "$OUT"
expect_eq "O3c …and the suite never ran" "0" "$(rt_runs)"

rt_poke order lift
expect_eq "O4 order lift ends it (exit 0)" "0" "$RC"
expect_regex "O4b …as an order: line with the time and the words it lifted" \
  "^order: lifted [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z \"$WORDS\"$" "$(rt_orders | tail -n 1)"

rt_run
expect_eq "O5 lifted, the runner runs the suite (exit 0)" "0" "$RC"
expect_eq "O5b …and the suite ran once" "1" "$(rt_runs)"

finish
