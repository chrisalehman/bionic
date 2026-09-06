# tests/lib/assert.sh — THE TEST FRAMEWORK. Sections, assertions, counters, the
# helper-presence derivation, and the tally (wave-01 verification-cannot-lie S1,
# spec AC-13/AC-14/AC-15; design ledger D1 "a suite is a client of one test
# framework").
#
#     . "$(dirname "$0")/lib/resolve-roots.sh"
#     . "$(dirname "$0")/lib/assert.sh"      # from tests/*.test.sh
#
# WHAT IT OWNS.
#
#   section <name>        opens a section that MUST assert something
#   setup_section <name>  opens a section exempt from that rule (fixture building)
#   ok <msg>              record a pass
#   no <msg> [detail]     record a fail
#   THE GENERIC ASSERTION FAMILY — the thirteen names below are the framework's
#   and no suite's (A-16, spec AC-12). Every one reports through ok/no, so the
#   counters and the section floor see it.
#
#   expect_eq <msg> <expected> <actual>          string equality
#   expect_ne <msg> <not-expected> <actual>      string inequality
#   expect_true <msg> <cmd>...                   command exits 0 (output silenced)
#   expect_false <msg> <cmd>...                  command exits non-zero (silenced)
#   expect_contains <msg> <needle> <haystack>    literal substring present
#   expect_absent <msg> <needle> <haystack>      literal substring absent
#   expect_match <msg> <glob> <actual>           GLOB match (not a regex)
#   expect_no_match <msg> <glob> <actual>        GLOB non-match
#   expect_regex <msg> <ERE> <actual>            ERE match, unanchored
#   expect_no_regex <msg> <ERE> <actual>         ERE non-match
#   expect_status <msg> <expected> <actual>      exit status equality
#   expect_empty <msg> <value>                   value is the empty string
#   expect_nonempty <msg> <value>                value is not the empty string
#   require_helpers <name>...   explicit presence guard (kept for the two suites
#                               that already call it)
#   finish                close the last section, fail every section that asserted
#                         nothing, print the tally, exit by FAIL
#
# THE COUNTERS AND ok/no ARE DEFINED HERE, UNCONDITIONALLY. This file is the ONE
# definition of PASS/FAIL/TOTAL and of what counts as a result (D1). A suite that
# still carries its own `PASS=0; FAIL=0; TOTAL=0` and its own `ok()`/`no()` — 49
# of them do, on the day this is written — overrides these after sourcing and
# keeps working exactly as before; migrating those suites is S5–S9's job and the
# runner's adoption wall (S10) is what makes a private definition an error. What
# changes here is that the framework no longer DEFERS: the definitions below are
# the tree's, not a fallback.
#
# ── THE GENERIC FAMILY: SEMANTICS, ARGUMENT ORDER, AND THE OLD SPELLINGS ─────
#
# Before this file owned them, 53 suites carried 37 distinct private `expect_*`
# spellings between them. Thirteen of those are GENERIC — they say nothing about
# bionic, only about strings, commands, patterns and exit statuses — and those
# thirteen are now defined here, once. Regex matching is on that list rather than
# left private (A-S1b-2, resolved by the orchestrator 2026-09-06 as option 2):
# eight suites need it, so leaving it out would have made the ownership boundary
# a loophole for exactly the duplication this wave removes. The other 24 are
# suite-specific (expect_finding,
# expect_audit_line, expect_block, expect_allow, …); they are built on ok/no,
# they stay local to the suite that needs them, and they stay legal.
#
# ARGUMENT ORDER is `<label> <expected> <actual>` throughout, which is what the
# tree already did unanimously: expected-side first for eq/ne/status, needle
# before haystack for contains/absent, pattern before subject for match/no_match.
# The two exceptions in the tree (live-agents and resources spell expect_match
# `<label> <actual> <ERE>`) are outvoted 11 to 2 and are migration work.
#
# SEMANTICS are the tree's most common definition of each name, measured:
#
#   expect_true / expect_false SILENCE the command they run (stdout AND stderr).
#     17 of 20 private definitions of expect_true do, and 6 of 9 of expect_false.
#     A command whose output you want to assert on should be captured into a
#     variable and asserted with expect_contains — not run through expect_true.
#
#   expect_contains / expect_absent take a LITERAL substring, implemented with a
#     quoted `case` glob rather than `grep -F`. The tree is split almost evenly
#     (10 `case` to 9 `grep -qF` for contains), and the two agree on every
#     single-line needle. `case` is chosen because it is exact substring
#     semantics: `grep -F` reads a newline in the needle as pattern alternation,
#     so a multi-line needle matches too eagerly under contains and, worse, too
#     eagerly under absent. It also keeps expect_absent the exact complement of
#     expect_contains, and it spawns nothing (no `grep -q` in a pipeline, which
#     exits 141 under pipefail on a large producer).
#
#   expect_match / expect_no_match take a GLOB, not a regex — `[[ $actual == $pat ]]`
#     with the pattern unquoted. 11 of 14 private definitions of expect_match are
#     this, and all 8 of expect_no_match are; between them they carry 266 call
#     sites against 75 for the regex spellings. Anchoring is implicit: the glob
#     must match the WHOLE value, so a substring test needs `*needle*`.
#
#   expect_regex / expect_no_regex take an EXTENDED regular expression and are
#     UNANCHORED: `needle` matches "a needle here" with no `.*` on either side.
#     This is the semantics of the tree's `expect_matches` (5 definitions, 25 call
#     sites), and it is a genuinely different matcher from expect_match — a glob
#     reads `[0-9]+` as a literal bracket expression followed by a literal plus.
#     Pick expect_regex when the pattern needs a quantifier, alternation or an
#     anchor; pick expect_match when a `*needle*` says it.
#
#     The value is matched with a HERESTRING, never `printf ... | grep -q`. Two
#     suites spell their private expect_matches as a pipeline, and under
#     `pipefail` that reports FAILURE on a value the pattern matches, as soon as
#     the value outgrows the 64 KiB pipe buffer: grep leaves early and the
#     producer takes EPIPE. The status is 141 when the producer dies by SIGPIPE
#     and 1 when bash reports the write error instead — it varies with the
#     producer, the size and whether a trap is installed, so only "non-zero" is
#     stable. Either way the assertion says FAIL and the code is fine.
#     framework.test.sh §10 pins both halves. Capture the value, then match it.
#
#   expect_status compares two exit statuses as strings, expected first.
#
# THE OLD SPELLINGS — `old -> canonical`. No aliases are defined here: the
# migration slices rename the call sites. S5-S8 quote this table.
#
#   expect_equal -> expect_eq — pure rename (stop-check, 4 call sites; its
#     failing arm also printed a diff, which is detail text, not semantics).
#   expect_differ -> expect_ne — pure rename (stop-check; defined, never called).
#   expect_not_contains -> expect_absent — pure rename, same `case` semantics
#     (command-relay, env, rc-item; 7 call sites).
#   expect_matches -> expect_regex — PURE rename, same ERE semantics, same
#     argument order (execution-recorder, interpreter-pin, session-sweeper,
#     stop-check, stop-guard; 25 call sites). The two pipeline spellings
#     (interpreter-pin, session-sweeper) lose their 141 exposure in the move.
#   expect_match, in the THREE suites where it is secretly an ERE -> expect_regex.
#     live-agents (8 sites) and resources (17) also REVERSE the arguments, spelling
#     it `<label> <actual> <ERE>`, so those 25 sites need the order corrected as
#     well as the name changed. This is the highest-risk rebinding in the
#     migration: their private definition wins today, so nothing is red now, and
#     the moment the adoption wall removes the shadow the calls bind to the glob
#     helper with the arguments the wrong way round and STILL nothing goes red.
#     preflight-probe (11 sites) is the third: its expect_match takes a FILE, so
#     each call site must grow a read of that file, and its sibling expect_nomatch
#     stays local — that suite ends up with a split idiom until someone routes
#     both together.
#   expect_nomatch -> NOT a rename: it takes a FILE rather than a string
#     (preflight-probe, 14 call sites). Stays local under its own name.
#   expect_absent_ug -> NOT a rename: it pins /usr/bin/grep on purpose, because
#     the shell `grep` on this machine skips hidden directories (cross-gate).
#
# ── ASSERTION DISCIPLINE ─────────────────────────────────────────────────────
#
# PAIRED POSITIVE. A negative assertion — "this string is absent", "this set is
# empty", "this file does not exist" — passes just as loudly when the mechanism
# under test never ran at all. Every negative assertion needs a positive one
# beside it, in the same section, over the same fixture: one row that proves the
# thing you are looking for CAN appear here, and one that proves it does not in
# this state. An assertion that cannot be made to fail by breaking the code it
# names is not an assertion.
#
# LOSSY RENDERS. An assertion about a render that truncates needs a second,
# unlossy source, and a whole-render glob is not an assertion. (Three assertions
# in the 1.4.4 fixit were misled by exactly this: doctor's verdict line is cut at
# 100 columns, so the text the assertion looked for was outside the frame and the
# row went green on a substring of the ellipsis.) Assert against the value the
# renderer was given, or against a non-truncating surface, and let the render
# assertion pin only the framing.
#
# ── HELPER DERIVATION (AC-14) ────────────────────────────────────────────────
#
# Every suite here runs under `set -uo pipefail` with NO `-e`, so a call to an
# assertion helper that was never defined is a silent `command not found` on
# stderr: the row asserts nothing, TOTAL never increments, and `tests/run.sh`
# discards a green suite's stderr (research-code-map §5.3–§5.4). That is how
# `expect_empty` at tests/cross-gate-agreement.test.sh:5960 has been asserting
# nothing.
#
# So the framework does not wait to be told which helpers a suite uses. At load
# it scans the suite's own source ($0) for call tokens matching
# `ok|no|expect_[a-z_]+|anchor` in command position, and exits 1 naming any name
# that neither this file defines nor the suite itself defines. The explicit
# `require_helpers a b c` form stays for the two suites that call it, and for
# names the derivation cannot see.

# ── counters: the ONE definition ─────────────────────────────────────────────
PASS=0
FAIL=0
TOTAL=0

# ── section state ────────────────────────────────────────────────────────────
_TF_SECTION=""        # name of the open section, empty when none
_TF_SECTION_KIND=""   # assert | setup
_TF_SECTION_ROWS=0    # assertions recorded since the section opened
_TF_SECTIONS=0        # asserting sections opened
_TF_SETUPS=0          # setup sections opened
_TF_EMPTY=""          # newline-separated names of sections that asserted nothing

_tf_close_section() {
  [ -n "$_TF_SECTION" ] || return 0
  if [ "$_TF_SECTION_KIND" = "assert" ] && [ "$_TF_SECTION_ROWS" -eq 0 ]; then
    _TF_EMPTY="${_TF_EMPTY}${_TF_SECTION}
"
  fi
  _TF_SECTION=""
  _TF_SECTION_KIND=""
  _TF_SECTION_ROWS=0
}

# section <name> — opens a section that must record at least one assertion.
section() {
  _tf_close_section
  _TF_SECTION="$1"
  _TF_SECTION_KIND="assert"
  _TF_SECTION_ROWS=0
  _TF_SECTIONS=$((_TF_SECTIONS + 1))
  echo ""
  echo "── $1"
}

# setup_section <name> — a section that builds fixtures and is EXEMPT from the
# no-section-without-an-assertion rule. It is exempt because it is named: a
# section that asserts nothing and does not say so is the defect.
setup_section() {
  _tf_close_section
  _TF_SECTION="$1"
  _TF_SECTION_KIND="setup"
  _TF_SECTION_ROWS=0
  _TF_SETUPS=$((_TF_SETUPS + 1))
  echo ""
  echo "── $1 (setup)"
}

# ── assertions ───────────────────────────────────────────────────────────────
ok() {
  TOTAL=$((TOTAL + 1)); PASS=$((PASS + 1))
  _TF_SECTION_ROWS=$((_TF_SECTION_ROWS + 1))
  echo "PASS: $1"
}

no() {
  TOTAL=$((TOTAL + 1)); FAIL=$((FAIL + 1))
  _TF_SECTION_ROWS=$((_TF_SECTION_ROWS + 1))
  echo "FAIL: $1"
  [ -n "${2:-}" ] && echo "      $2"
  return 0
}

# expect_eq <label> <expected> <actual>
expect_eq() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "expected '$2', got '$3'"; fi; }

# expect_ne <label> <not-expected> <actual>
expect_ne() { if [ "$2" != "$3" ]; then ok "$1"; else no "$1" "expected anything but '$2', got it"; fi; }

# expect_true <label> <cmd>... — the command's own output is silenced.
expect_true() {
  local _l="$1"; shift
  if "$@" >/dev/null 2>&1; then ok "$_l"; else no "$_l" "command failed: $*"; fi
}

# expect_false <label> <cmd>... — the command's own output is silenced.
expect_false() {
  local _l="$1"; shift
  if "$@" >/dev/null 2>&1; then no "$_l" "command unexpectedly succeeded: $*"; else ok "$_l"; fi
}

# expect_contains <label> <needle> <haystack> — literal substring.
expect_contains() {
  case "$3" in
    *"$2"*) ok "$1" ;;
    *)      no "$1" "missing '$2' in: $(printf '%.400s' "$3")" ;;
  esac
}

# expect_absent <label> <needle> <haystack> — the exact complement of
# expect_contains, and a NEGATIVE assertion: pair it with a positive one over the
# same fixture, or it passes when the producer never ran.
expect_absent() {
  case "$3" in
    *"$2"*) no "$1" "unexpectedly present: '$2' in: $(printf '%.400s' "$3")" ;;
    *)      ok "$1" ;;
  esac
}

# expect_match <label> <glob> <actual> — GLOB, not a regex, and it must match the
# whole value: a substring test is '*needle*'.
expect_match() {
  # shellcheck disable=SC2053  # RHS is a glob on purpose
  if [[ "$3" == $2 ]]; then ok "$1"; else no "$1" "no match for '$2' in: $(printf '%.400s' "$3")"; fi
}

# expect_no_match <label> <glob> <actual> — a NEGATIVE assertion; pair it.
expect_no_match() {
  # shellcheck disable=SC2053  # RHS is a glob on purpose
  if [[ "$3" == $2 ]]; then no "$1" "unexpected match for '$2' in: $(printf '%.400s' "$3")"; else ok "$1"; fi
}

# expect_regex <label> <ERE> <actual> — EXTENDED regular expression, unanchored.
# The value is matched through a herestring, not a pipeline: `printf | grep -q`
# exits 141 under pipefail on a large value and reports a false FAIL.
expect_regex() {
  if grep -qE -- "$2" <<<"$3"; then ok "$1"; else no "$1" "no match for /$2/ in: $(printf '%.400s' "$3")"; fi
}

# expect_no_regex <label> <ERE> <actual> — the exact complement of expect_regex,
# and a NEGATIVE assertion: pair it with a positive one over the same fixture.
expect_no_regex() {
  if grep -qE -- "$2" <<<"$3"; then no "$1" "unexpected match for /$2/ in: $(printf '%.400s' "$3")"; else ok "$1"; fi
}

# expect_status <label> <expected> <actual>
expect_status() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "expected exit $2, got $3"; fi; }

# expect_empty <label> <value> — a NEGATIVE assertion: pair it with a positive
# one over the same fixture, or it passes when the producer never ran.
expect_empty() { if [ -z "${2:-}" ]; then ok "$1"; else no "$1" "expected no output, got: $2"; fi; }

# expect_nonempty <label> <value>
expect_nonempty() { if [ -n "${2:-}" ]; then ok "$1"; else no "$1" "expected a non-empty value, got nothing"; fi; }

# ── the tally ────────────────────────────────────────────────────────────────
#
# finish — closes the open section, turns every section that asserted nothing
# into a named FAIL (AC-13), prints the tally with `sections=N setup=M`, and
# exits by FAIL. Call it as the last line of a suite instead of a hand-rolled
# `[ "$FAIL" -eq 0 ]`.
finish() {
  local name suite
  _tf_close_section
  if [ -n "$_TF_EMPTY" ]; then
    while IFS= read -r name; do
      [ -n "$name" ] || continue
      TOTAL=$((TOTAL + 1)); FAIL=$((FAIL + 1))
      echo "FAIL: section asserted nothing: $name"
    done <<TF_EMPTY_SECTIONS
$_TF_EMPTY
TF_EMPTY_SECTIONS
  fi
  suite="$(basename "${0:-suite}")"
  echo ""
  echo "──────────────────────────────────────────────"
  echo "${suite}: ${PASS}/${TOTAL} passed, ${FAIL} failed  sections=${_TF_SECTIONS} setup=${_TF_SETUPS}"
  [ "$FAIL" -eq 0 ] || exit 1
  exit 0
}

# ── helper presence ──────────────────────────────────────────────────────────

# require_helpers <name>... -> exit 1, naming every undefined one, if any name
# passed is not a defined shell function. Call it once, after every assertion
# helper the suite defines for itself has been defined.
require_helpers() {
  local missing="" name
  for name in "$@"; do
    type -t "$name" >/dev/null 2>&1 || missing="$missing $name"
  done
  if [ -n "$missing" ]; then
    echo "require_helpers: undefined:$missing" >&2
    exit 1
  fi
}

# _tf_scan <file> — prints `CALL <name>` for every call token in command
# position matching ok|no|expect_[a-z_]+|anchor, and `DEF <name>` for every
# function this file defines itself. Heredoc BODIES are skipped: a suite that
# writes a scratch suite with a planted undefined helper is not itself calling
# it. Full-line comments are skipped. Command position means: first word of a
# line, or the first word after ; & | ( ) { } or then/else/elif/do/if/while/
# until/!.
_tf_scan() {
  awk '
    hd != "" {
      if ($0 ~ ("^[ \t]*" hd "[ \t]*$")) hd = ""
      next
    }
    {
      line = $0
      if (line ~ /^[ \t]*#/) next

      # heredoc opener on this line? (herestrings <<< are not openers)
      hline = line
      gsub(/<<</, "   ", hline)
      pending = ""
      if (match(hline, /<<-?[ \t]*[^ \t<>;&|()]+/)) {
        w0 = substr(hline, RSTART, RLENGTH)
        sub(/^<<-?[ \t]*/, "", w0)
        gsub(/[^A-Za-z0-9_]/, "", w0)
        if (w0 != "") pending = w0
      }

      if (match(line, /^[ \t]*[A-Za-z_][A-Za-z0-9_]*[ \t]*\(\)/)) {
        d = substr(line, RSTART, RLENGTH)
        gsub(/[^A-Za-z0-9_]/, "", d)
        print "DEF " d
        hd = pending
        next
      }

      gsub(/[;()&|{}]/, " \001 ", line)
      n = split(line, w, /[ \t]+/)
      prev = "\001"
      for (i = 1; i <= n; i++) {
        t = w[i]
        if (t == "") continue
        if (prev == "\001" || prev == "then" || prev == "else" || prev == "elif" \
            || prev == "do" || prev == "if" || prev == "while" || prev == "until" || prev == "!") {
          if (t ~ /^(ok|no|expect_[a-z_]+|anchor)$/) print "CALL " t
        }
        prev = t
      }
      hd = pending
    }
  ' "$1"
}

# The load-time derivation (AC-14). Runs once, here, for whatever suite sourced
# this file. A suite the framework cannot read cannot be certified by it, so an
# unreadable $0 is an error and not a silent skip.
_tf_require_derived_helpers() {
  local src="$1" scan calls defs name missing=""
  if [ ! -f "$src" ] || [ ! -r "$src" ]; then
    echo "assert.sh: cannot read the suite source '$src' to derive its helper calls" >&2
    exit 1
  fi
  scan="$(_tf_scan "$src")"
  calls="$(echo "$scan" | sed -n 's/^CALL //p' | sort -u)"
  defs="$(echo "$scan" | sed -n 's/^DEF //p' | sort -u)"
  for name in $calls; do
    type -t "$name" >/dev/null 2>&1 && continue
    echo "$defs" | grep -qx -- "$name" && continue
    missing="$missing $name"
  done
  if [ -n "$missing" ]; then
    echo "assert.sh: helper called but never defined:$missing" >&2
    echo "assert.sh: derived from the calls in $src — define it in the suite, or fix the call." >&2
    exit 1
  fi
}

_tf_require_derived_helpers "${0:-}"
