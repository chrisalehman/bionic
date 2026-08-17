#!/bin/bash
# ASSERTION-HELPER RACE — epic-17 wave-01 interstitial bugfix.
#
# WHAT BROKE. Every suite in this repo carries a hand-copied pair of assertion
# helpers shaped like:
#
#     expect_contains() { if printf '%s' "$3" | grep -qF -- "$2"; then ok; else no; fi; }
#
# and every one of those suites also runs under `set -o pipefail`. That
# combination is a race, not a style question:
#
#   * `grep -q` exits the instant it finds the needle — it does NOT drain stdin.
#   * When the haystack is larger than the kernel pipe buffer (64 KiB on macOS)
#     the bash `printf` builtin is still blocked mid-write when grep exits, so
#     it takes SIGPIPE and reports 141.
#   * `pipefail` makes the PIPELINE status the rightmost NON-ZERO status, i.e.
#     141 — even though grep itself exited 0 having FOUND the needle.
#   * `if` therefore takes the else branch: `expect_contains` reports
#     `FAIL: ... missing: <needle>` for a needle that is demonstrably present.
#
# Whether printf loses the race depends only on process scheduling, so the same
# suite passes 563/563 and then fails 558/563 in the same checkout with nothing
# changed between the runs. That is the whole of the "cross-gate flake"
# (.bionic/docs/record/epic-17-w1/crossgate-adjudication.md): it is an in-process
# pipeline race, NOT the inter-test state pollution that report hypothesised.
#
# `expect_absent` carries the same race in its dangerous direction: when the
# needle IS present (the case the assertion exists to catch) grep exits early,
# the pipeline reports 141, the `if` takes the else branch and the helper
# reports **PASS**. A silent false green, not a flake.
#
# WHAT THIS SUITE PINS. It extracts the REAL helper definitions out of every
# suite file that sets `pipefail`, evaluates them, and hammers them with a
# haystack far larger than the pipe buffer. A helper that pipes into `grep -q`
# goes red here deterministically; a helper that feeds grep without a pipe (or
# that does the containment test in-process) is green.
#
# HERMETIC. Reads suite sources, forks grep. No sandbox, no network, no hooks.
#
# Usage: bash tests/assert-helper-race.test.sh
# Registered by name in tests/run.sh (tests/*.test.sh is NOT auto-globbed).

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"

REPO_ROOT="${BIONIC_SCRIPTS_DIR}"
cd "$REPO_ROOT" || exit 1

PASS=0; FAIL=0; TOTAL=0
ok() { TOTAL=$((TOTAL + 1)); PASS=$((PASS + 1)); echo "PASS: $1"; }
no() { TOTAL=$((TOTAL + 1)); FAIL=$((FAIL + 1)); echo "FAIL: $1"; [ -n "${2:-}" ] && echo "      $2"; return 0; }
expect_eq() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "expected '$2', got '$3'"; fi; }

# Every suite file that sets `pipefail` AND defines expect_* helpers. Hand-listed
# on purpose: a new suite is invisible to this pin until it is added by name,
# same discipline tests/run.sh uses.
SUITES="
tests/cross-gate-agreement.test.sh
tests/fail-direction-table.test.sh
hooks/agent-context-guard.test.sh
hooks/dispatch-preflight.test.sh
hooks/execution-recorder.test.sh
hooks/landing-gate.test.sh
hooks/stop-check.test.sh
hooks/stop-guard.test.sh
hooks/stop-orders.test.sh
"
# tests/seam-resolution.test.sh also sets pipefail and defines expect_contains/
# expect_absent, but is pipe-free by construction (containment via `case`, never
# `printf | grep -q`) — nothing here to pin. Named rather than silently omitted
# so this list stays an enumeration, not a judgment call (epic-17-w2 S1 concern,
# resolved by S2).
# tests/plugin-hooks.test.sh also sets pipefail and defines expect_contains_lit/
# expect_absent_lit/expect_equal, but is pipe-free by construction (containment
# via `case`, never `printf | grep -q`) — nothing here to pin. Named rather than
# silently omitted so this list stays an enumeration, not a judgment call
# (epic-17-w2 S3 concern, resolved by S5).

# The haystack: 512 KiB, eight times the 64 KiB pipe buffer, with the needle in
# the FIRST line. Under the racy idiom grep matches on its first read() and
# exits with ~510 KiB still unwritten, so printf loses the race every time —
# this makes the RED deterministic rather than probabilistic.
# Regex-inert on purpose: the same literal is handed to -F helpers and to -E
# helpers, so it must mean itself under both.
NEEDLE='w17-race-marker'
BIG="$NEEDLE"
_pad="0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
while [ "${#BIG}" -lt 524288 ]; do BIG="$BIG"$'\n'"$_pad$_pad$_pad$_pad"; done
ITERS=40

echo "── haystack ─────────────────────────────────────────────────"
expect_eq "the probe haystack clears the 64 KiB pipe buffer by 8x" "yes" \
  "$([ "${#BIG}" -gt 524287 ] && echo yes || echo no)"
expect_eq "the needle sits in the haystack's first line" "yes" \
  "$(case "$BIG" in "$NEEDLE"*) echo yes;; *) echo no;; esac)"

# ---------------------------------------------------------------- extraction
#
# Pull a function definition out of a suite file without sourcing the suite
# (sourcing would RUN it). Start at the `name() {` line and keep appending lines
# until the accumulated text parses as a complete shell fragment — that lands on
# the closing brace for both the one-line and the multi-line helper shapes this
# repo uses, with no brace counting.
extract_fn() {  # <file> <fn-name>  -> definition text on stdout
  local file="$1" fn="$2" start acc line
  start="$(/usr/bin/grep -n "^${fn}() *{" "$file" | head -1 | cut -d: -f1)"
  [ -n "$start" ] || return 1
  acc=""
  while IFS= read -r line; do
    acc="$acc$line"$'\n'
    if bash -n <<<"$acc" 2>/dev/null; then printf '%s' "$acc"; return 0; fi
  done < <(tail -n +"$start" "$file")
  return 1
}

# Hammer one extracted helper ITERS times and report how many of its verdicts
# were the WRONG one. `ok`/`no` are shadowed so the helper's own verdict is
# counted instead of printed.
probe() {  # <definition-text> <fn-name> <expected-verdict: ok|no>  -> wrong count
  local def="$1" fn="$2" want="$3"
  (
    set -uo pipefail
    P_OK=0; P_NO=0
    ok() { P_OK=$((P_OK + 1)); }
    no() { P_NO=$((P_NO + 1)); return 0; }
    eval "$def"
    local i
    for i in $(seq 1 "$ITERS"); do "$fn" probe "$NEEDLE" "$BIG"; done
    if [ "$want" = ok ]; then echo "$P_NO"; else echo "$P_OK"; fi
  )
}

# ------------------------------------------------------- A. positive helpers
#
# The needle IS present. A correct helper says so every single time. The racy
# idiom reports "missing:" for a needle it just found.
echo
echo "── A. expect_contains / expect_matches never lose a present needle ──"
for _s in $SUITES; do
  for _fn in expect_contains expect_matches; do
    _def="$(extract_fn "$_s" "$_fn")" || continue
    expect_eq "$_s $_fn() finds a present needle in a 512 KiB haystack ($ITERS/$ITERS)" \
      "0" "$(probe "$_def" "$_fn" ok)"
  done
done

# ------------------------------------------------------- B. negative helpers
#
# The needle IS present, so expect_absent must FAIL. The racy idiom returns a
# false PASS here — the silent-false-green direction, worse than the flake.
echo
echo "── B. expect_absent never returns a false green on a present needle ──"
for _s in $SUITES; do
  _def="$(extract_fn "$_s" expect_absent)" || continue
  expect_eq "$_s expect_absent() catches a present needle in a 512 KiB haystack ($ITERS/$ITERS)" \
    "0" "$(probe "$_def" expect_absent no)"
done

# ------------------------------------------------------------- C. the idiom
#
# Behaviour is the pin; the source scan is the tripwire, so a future
# copy-paste of the banned shape is named at the line rather than diagnosed
# from a red that only appears under load.
echo
echo "── C. no suite pipes a haystack into an early-exiting grep ──"
for _s in $SUITES; do
  expect_eq "$_s does not pipe an assertion haystack into grep -q" "" \
    "$(/usr/bin/grep -nE "printf .*\\\$3.*\| *grep -q" "$_s" | tr '\n' ' ' | sed 's/ $//')"
done

echo
echo "──────────────────────────────────────────────"
echo "assert-helper-race: $PASS passed, $FAIL failed, $TOTAL total"
[ "$FAIL" -eq 0 ]
