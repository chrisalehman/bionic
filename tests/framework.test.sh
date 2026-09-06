#!/bin/bash
# tests/framework.test.sh — the test framework's own suite (wave-01
# verification-cannot-lie S1; spec AC-13, AC-14, AC-15).
#
# WHAT IT COVERS. tests/lib/assert.sh is the one thing in this tree that decides
# whether a result exists at all, so it is the one thing that cannot be certified
# by the same mechanism it certifies. Every row here plants a scratch suite in a
# sandbox, runs it under the real framework, and reads the verdict the framework
# produced:
#
#   §1  a section that closes with zero assertions FAILS naming that section,
#       and a section that asserted is NOT named (AC-13)
#   §2  setup_section is exempt, and the tally counts it separately (AC-13)
#   §3  a called-but-undefined helper is red AT LOAD, naming it — the r24e shape,
#       which the pre-framework harness reported as a green suite (AC-14)
#   §4  the derivation does not over-fire: a helper the suite defines for itself
#       is exempt, and a helper name inside a heredoc body is not a call site
#   §5  finish exits by FAIL, and the tally line carries sections=N setup=M
#   §6  the counters and the assertion helpers are defined by the framework
#   §7  the assertion-discipline docblock carries its two obligations
#   §8  tests/run.sh registers this suite
#
# HERMETIC. Every planted suite is written into a mktemp'd sandbox holding a COPY
# of the real tests/lib/assert.sh and is run as a child process; nothing here
# edits the repo, and no row reads a live install.
#
# Usage: bash tests/framework.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"

REPO="${BIONIC_SCRIPTS_DIR}"
FRAMEWORK="${REPO}/tests/lib/assert.sh"

SB="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/framework-test.XXXXXX")" && pwd)"
trap 'rm -rf "$SB"' EXIT
mkdir -p "$SB/tests/lib"
cp "$FRAMEWORK" "$SB/tests/lib/assert.sh"

# ---------- local, non-assertion helpers ----------
#
# This suite deliberately defines NO ok/no/expect_* of its own: it is the
# framework's first pure client, and the shape S5-S9 migrate the other suites
# into. `contains` and `plant_run` are plumbing, not assertions.

contains() {  # contains <haystack> <needle> -> yes|no
  case "$1" in
    *"$2"*) echo yes ;;
    *)      echo "no" ;;
  esac
}

P_OUT=""
P_RC=""
plant_run() {  # plant_run <suite-basename> -> sets P_OUT / P_RC
  P_OUT="$(cd "$SB" && bash "tests/$1" 2>&1)"
  P_RC=$?
}

# ---------- planted suites ----------
#
# Written through heredocs. §4 asserts that the framework's own derivation does
# NOT read a heredoc body as a call site — which is what lets this file mention
# an undefined helper by name without dying at its own load.
#
# Declared as a setup section, which is also this suite's own use of the
# exemption §2 tests: a block that builds fixtures and asserts nothing says so.

setup_section "plant the scratch suites"

cat > "$SB/tests/p-empty.test.sh" <<'PLANT_EMPTY'
#!/bin/bash
set -uo pipefail
. "$(dirname "$0")/lib/assert.sh"

section "the probe fires"
:

section "the probe records"
ok "a real row"

finish
PLANT_EMPTY

cat > "$SB/tests/p-setup.test.sh" <<'PLANT_SETUP'
#!/bin/bash
set -uo pipefail
. "$(dirname "$0")/lib/assert.sh"

setup_section "build the fixture"
:

section "the fixture answers"
ok "a real row"

finish
PLANT_SETUP

cat > "$SB/tests/p-undefined.test.sh" <<'PLANT_UNDEFINED'
#!/bin/bash
# The r24e shape, verbatim: a suite in the pre-framework idiom (its own counters,
# its own ok/no, no -e) calling an assertion helper that is defined nowhere.
set -uo pipefail
. "$(dirname "$0")/lib/assert.sh"

PASS=0
FAIL=0
TOTAL=0
ok() { TOTAL=$((TOTAL + 1)); PASS=$((PASS + 1)); echo "PASS: $1"; }
no() { TOTAL=$((TOTAL + 1)); FAIL=$((FAIL + 1)); echo "FAIL: $1"; return 0; }

ok "a real row"
expect_nope "the row that asserts nothing" ""
ok "another real row"

echo "TOTAL=$TOTAL PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
PLANT_UNDEFINED

cat > "$SB/tests/p-selfdef.test.sh" <<'PLANT_SELFDEF'
#!/bin/bash
# A helper the suite defines for ITSELF, below the source line — the shape
# tests/dispatch-preflight.test.sh and tests/stop-guard.test.sh are in today.
set -uo pipefail
. "$(dirname "$0")/lib/assert.sh"

expect_mine() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "mismatch"; fi; }

section "a self-defined helper loads"
expect_mine "the row runs" a a

finish
PLANT_SELFDEF

cat > "$SB/tests/p-heredoc.test.sh" <<'PLANT_HEREDOC'
#!/bin/bash
set -uo pipefail
. "$(dirname "$0")/lib/assert.sh"

cat > /dev/null <<'INNER'
expect_never_defined "this is content, not a call" ""
INNER

section "a heredoc body is not a call site"
ok "the suite loaded"

finish
PLANT_HEREDOC

cat > "$SB/tests/p-fail.test.sh" <<'PLANT_FAIL'
#!/bin/bash
set -uo pipefail
. "$(dirname "$0")/lib/assert.sh"

section "a section with a real failure"
ok "one that passes"
no "one that fails"

finish
PLANT_FAIL

cat > "$SB/tests/p-nosection.test.sh" <<'PLANT_NOSECTION'
#!/bin/bash
set -uo pipefail
. "$(dirname "$0")/lib/assert.sh"

ok "an assertion outside any section still counts"
expect_eq "expect_eq passes on equal values" x x
expect_empty "expect_empty passes on an empty value" ""

finish
PLANT_NOSECTION

cat > "$SB/tests/p-counters.test.sh" <<'PLANT_COUNTERS'
#!/bin/bash
# Defines no counters of its own; `set -u` makes an undefined one an abort.
set -uo pipefail
. "$(dirname "$0")/lib/assert.sh"

echo "COUNTERS PASS=$PASS FAIL=$FAIL TOTAL=$TOTAL"

section "the framework's counters move"
ok "a real row"

finish
PLANT_COUNTERS

cat > "$SB/tests/p-negatives.test.sh" <<'PLANT_NEGATIVES'
#!/bin/bash
set -uo pipefail
. "$(dirname "$0")/lib/assert.sh"

section "the negative arms of the two framework assertions"
expect_eq "expect_eq fails on unequal values" wanted got
expect_empty "expect_empty fails on a non-empty value" "something"

finish
PLANT_NEGATIVES

# The generic family (S1b): one planted suite whose ONLY assertions are the
# eleven canonical helpers in their PASSING form, and one whose only assertions
# are the same eleven in their FAILING form. Together they prove each helper
# reports through ok/no — the tallies move, and the section floor sees the rows.

cat > "$SB/tests/p-family-pass.test.sh" <<'PLANT_FAMILY_PASS'
#!/bin/bash
set -uo pipefail
. "$(dirname "$0")/lib/assert.sh"

section "the eleven generic helpers, passing arms"
expect_eq        "eq"        same same
expect_ne        "ne"        wanted other
expect_true      "true"      test 1 -eq 1
expect_false     "false"     test 1 -eq 2
expect_contains  "contains"  "need" "a needle here"
expect_absent    "absent"    "haystalk" "a needle here"
expect_match     "match"     '*need*'  "a needle here"
expect_no_match  "no_match"  '*straw*' "a needle here"
expect_status    "status"    0 0
expect_empty     "empty"     ""
expect_nonempty  "nonempty"  "x"

finish
PLANT_FAMILY_PASS

cat > "$SB/tests/p-family-fail.test.sh" <<'PLANT_FAMILY_FAIL'
#!/bin/bash
set -uo pipefail
. "$(dirname "$0")/lib/assert.sh"

section "the eleven generic helpers, failing arms"
expect_eq        "eq"        wanted got
expect_ne        "ne"        same same
expect_true      "true"      test 1 -eq 2
expect_false     "false"     test 1 -eq 1
expect_contains  "contains"  "straw" "a needle here"
expect_absent    "absent"    "need"  "a needle here"
expect_match     "match"     '*straw*' "a needle here"
expect_no_match  "no_match"  '*need*'  "a needle here"
expect_status    "status"    0 1
expect_empty     "empty"     "loud"
expect_nonempty  "nonempty"  ""

finish
PLANT_FAMILY_FAIL

# expect_true/expect_false SILENCE the command they run (the tree's majority, 17
# of 20 and 6 of 9). This plant proves that: the command writes to stdout and to
# stderr, and neither reaches the suite's output.
cat > "$SB/tests/p-family-silent.test.sh" <<'PLANT_FAMILY_SILENT'
#!/bin/bash
set -uo pipefail
. "$(dirname "$0")/lib/assert.sh"

noisy() { echo "NOISE-ON-STDOUT"; echo "NOISE-ON-STDERR" >&2; return "$1"; }

section "the command's own output does not reach the suite"
expect_true  "true silences a noisy success" noisy 0
expect_false "false silences a noisy failure" noisy 1

finish
PLANT_FAMILY_SILENT

# ============================================================
section "1: a section that asserts nothing fails by name (AC-13)"
# ============================================================

plant_run p-empty.test.sh
expect_eq "1: the planted suite exits 1" "1" "$P_RC"
expect_eq "1: …naming the section that asserted nothing" \
  "yes" "$(contains "$P_OUT" "FAIL: section asserted nothing: the probe fires")"
# PAIRED POSITIVE for the negative row below: the second section is present in
# the run, so its absence from the failure list is a discrimination and not an
# artefact of the section never having opened.
expect_eq "1: …and the section that DID assert ran" \
  "yes" "$(contains "$P_OUT" "PASS: a real row")"
expect_eq "1: …and is not itself named as empty" \
  "no" "$(contains "$P_OUT" "FAIL: section asserted nothing: the probe records")"
expect_eq "1: the tally counts both sections and the planted failure" \
  "p-empty.test.sh: 1/2 passed, 1 failed  sections=2 setup=0" \
  "$(printf '%s\n' "$P_OUT" | sed -n 's/^\(p-empty\.test\.sh: .*\)$/\1/p')"

# ============================================================
section "2: setup_section is exempt and is counted apart (AC-13)"
# ============================================================

plant_run p-setup.test.sh
expect_eq "2: the planted suite exits 0" "0" "$P_RC"
expect_eq "2: no section is reported as empty" \
  "no" "$(contains "$P_OUT" "section asserted nothing")"
expect_eq "2: …and the setup section did run" \
  "yes" "$(contains "$P_OUT" "── build the fixture (setup)")"
expect_eq "2: the tally separates sections from setup sections" \
  "p-setup.test.sh: 1/1 passed, 0 failed  sections=1 setup=1" \
  "$(printf '%s\n' "$P_OUT" | sed -n 's/^\(p-setup\.test\.sh: .*\)$/\1/p')"

# ============================================================
section "3: a called-but-undefined helper is red at load (AC-14)"
# ============================================================

plant_run p-undefined.test.sh
expect_eq "3: the planted suite exits 1" "1" "$P_RC"
expect_eq "3: …naming the helper it calls and nobody defines" \
  "yes" "$(contains "$P_OUT" "helper called but never defined: expect_nope")"
expect_eq "3: …and naming where the derivation read it from" \
  "yes" "$(contains "$P_OUT" "derived from the calls in tests/p-undefined.test.sh")"
# THE LIE THIS CLOSES: before the framework, this same file ran to completion —
# the undefined call was a stderr line, the rows around it passed, and the suite
# exited 0 (research-code-map §5.3). The refusal must happen at LOAD, before any
# row is recorded, or the suite still prints a tally nobody should trust.
expect_eq "3: …before a single row is recorded" \
  "no" "$(contains "$P_OUT" "PASS: a real row")"
expect_eq "3: …and before the suite prints its own tally" \
  "no" "$(contains "$P_OUT" "TOTAL=")"

# ============================================================
section "4: the derivation does not over-fire"
# ============================================================

plant_run p-selfdef.test.sh
expect_eq "4: a helper the suite defines for itself is exempt (exit 0)" "0" "$P_RC"
expect_eq "4: …and its row ran" "yes" "$(contains "$P_OUT" "PASS: the row runs")"

plant_run p-heredoc.test.sh
expect_eq "4: a helper name inside a heredoc body is not a call site (exit 0)" "0" "$P_RC"
expect_eq "4: …and the suite below the heredoc ran" \
  "yes" "$(contains "$P_OUT" "PASS: the suite loaded")"
# PAIRED POSITIVE: the exemptions above are worth nothing unless the derivation
# still fires on this very sandbox for a name nobody defines. §3 proved the
# refusal; this proves the two exemptions are not the derivation being off.
expect_eq "4: …while an undefined name in the same sandbox still refuses" \
  "1" "$(cd "$SB" && bash tests/p-undefined.test.sh >/dev/null 2>&1; echo $?)"

# ============================================================
section "5: finish exits by FAIL and prints the tally"
# ============================================================

plant_run p-fail.test.sh
expect_eq "5: a suite with one failing row exits 1" "1" "$P_RC"
expect_eq "5: …and the tally reports it" \
  "p-fail.test.sh: 1/2 passed, 1 failed  sections=1 setup=0" \
  "$(printf '%s\n' "$P_OUT" | sed -n 's/^\(p-fail\.test\.sh: .*\)$/\1/p')"

plant_run p-nosection.test.sh
expect_eq "5: a suite with no sections at all exits 0" "0" "$P_RC"
expect_eq "5: …and its tally reports zero sections" \
  "p-nosection.test.sh: 3/3 passed, 0 failed  sections=0 setup=0" \
  "$(printf '%s\n' "$P_OUT" | sed -n 's/^\(p-nosection\.test\.sh: .*\)$/\1/p')"

plant_run p-negatives.test.sh
expect_eq "5: the negative arm of expect_eq and expect_empty fails (exit 1)" "1" "$P_RC"
expect_eq "5: …expect_eq names what it wanted and what it got" \
  "yes" "$(contains "$P_OUT" "expected 'wanted', got 'got'")"
expect_eq "5: …expect_empty names the value it was handed" \
  "yes" "$(contains "$P_OUT" "expected no output, got: something")"
expect_eq "5: …and both rows are counted as failures" \
  "p-negatives.test.sh: 0/2 passed, 2 failed  sections=1 setup=0" \
  "$(printf '%s\n' "$P_OUT" | sed -n 's/^\(p-negatives\.test\.sh: .*\)$/\1/p')"

# ============================================================
section "6: the framework owns the counters and the helpers"
# ============================================================

for _fn in section setup_section ok no finish require_helpers \
          expect_eq expect_ne expect_true expect_false expect_contains expect_absent \
          expect_match expect_no_match expect_status expect_empty expect_nonempty; do
  expect_eq "6: the framework defines ${_fn}" "function" "$(type -t "$_fn")"
done
# The counters: a planted suite that defines none of its own reads all three
# under `set -u`, so an undefined counter would abort it rather than print.
plant_run p-counters.test.sh
expect_eq "6: the counters exist and start at zero without the suite defining them" \
  "yes" "$(contains "$P_OUT" "COUNTERS PASS=0 FAIL=0 TOTAL=0")"
expect_eq "6: …and the framework's ok() is what moves them" \
  "p-counters.test.sh: 1/1 passed, 0 failed  sections=1 setup=0" \
  "$(printf '%s\n' "$P_OUT" | sed -n 's/^\(p-counters\.test\.sh: .*\)$/\1/p')"

# ============================================================
section "7: the assertion-discipline docblock carries its obligations"
# ============================================================
#
# Two obligations the wave put in writing (A-9, the lossy-verdict class). They
# are pinned here because the docblock is where a suite author meets them: the
# framework file is what every migrated suite sources and reads.

# The docblock is comment-wrapped, so the pin reads it de-wrapped: comment marks
# dropped, newlines folded to spaces, runs of spaces squeezed. The pin is on the
# SENTENCE, not on where the wrap happens to fall.
DOC="$(tr '\n' ' ' < "$FRAMEWORK" | sed 's/#//g' | tr -s ' ')"
expect_eq "7: the lossy-render rule is stated" "yes" \
  "$(contains "$DOC" "assertion about a render that truncates needs a second, unlossy source, and a whole-render glob is not an assertion")"
expect_eq "7: the paired-positive rule is stated" "yes" \
  "$(contains "$DOC" "Every negative assertion needs a positive one")"
# PAIRED NEGATIVE: the two pins above discriminate — a framework file with the
# sentence taken out does not satisfy them.
DOC_STRIPPED="$(grep -v 'unlossy source' "$FRAMEWORK" | tr '\n' ' ' | sed 's/#//g' | tr -s ' ')"
expect_eq "7: …and the pin fails on a copy with the rule removed" "no" \
  "$(contains "$DOC_STRIPPED" "assertion about a render that truncates needs a second, unlossy source")"

# ============================================================
section "8: tests/run.sh registers this suite"
# ============================================================
#
# tests/*.test.sh is NOT auto-globbed — an unregistered suite never runs.

RUNSH="$(cat "${REPO}/tests/run.sh")"
expect_eq "8: tests/run.sh names framework.test.sh" "yes" \
  "$(contains "$RUNSH" 'run "framework.test.sh" bash tests/framework.test.sh')"
RUNSH_STRIPPED="$(printf '%s\n' "$RUNSH" | grep -v 'run "framework.test.sh"')"
expect_eq "8: …and the check discriminates (a copy without the line fails it)" "no" \
  "$(contains "$RUNSH_STRIPPED" 'run "framework.test.sh" bash tests/framework.test.sh')"

# ============================================================
section "9: the generic expect family is the framework's (AC-12, S1b)"
# ============================================================
#
# A-16's decision: the framework OWNS the eleven generic assertion names, and a
# suite-specific helper under a name the framework does NOT own stays local. The
# rows below are the framework half. The wall that refuses a suite for shadowing
# an owned name is S10's, and is not asserted here.
#
# PAIRED, BY CONSTRUCTION. Every helper appears twice: once directly in this
# suite where its passing arm must produce a PASS row, and once inside a planted
# suite where its failing arm must produce a FAIL row. A helper that silently did
# nothing would move neither tally.

# --- passing arms, called directly: each of these adds one PASS to THIS suite
expect_eq       "9: expect_eq passes on equal values"              same     same
expect_ne       "9: expect_ne passes on differing values"          wanted   other
expect_true     "9: expect_true passes on a zero-exit command"     test 1 -eq 1
expect_false    "9: expect_false passes on a non-zero command"     test 1 -eq 2
expect_contains "9: expect_contains passes on a present substring" "need"   "a needle here"
expect_absent   "9: expect_absent passes on an absent substring"   "straw"  "a needle here"
expect_match    "9: expect_match passes on a matching glob"        '*need*' "a needle here"
expect_no_match "9: expect_no_match passes on a non-matching glob" '*straw*' "a needle here"
expect_status   "9: expect_status passes on the expected status"   0        0
expect_empty    "9: expect_empty passes on an empty value"         ""
expect_nonempty "9: expect_nonempty passes on a non-empty value"   "x"

# --- the passing arms move the PASS counter and satisfy the section floor
plant_run p-family-pass.test.sh
expect_eq "9: eleven passing arms are eleven PASS rows in one section" \
  "p-family-pass.test.sh: 11/11 passed, 0 failed  sections=1 setup=0" \
  "$(printf '%s\n' "$P_OUT" | sed -n 's/^\(p-family-pass\.test\.sh: .*\)$/\1/p')"
expect_eq "9: …so the section floor does not name that section empty" "no" \
  "$(contains "$P_OUT" "section asserted nothing")"
expect_eq "9: …and the passing suite exits 0" "0" "$P_RC"

# --- the failing arms move the FAIL counter: each helper calls no()
plant_run p-family-fail.test.sh
expect_eq "9: eleven failing arms are eleven FAIL rows" \
  "p-family-fail.test.sh: 0/11 passed, 11 failed  sections=1 setup=0" \
  "$(printf '%s\n' "$P_OUT" | sed -n 's/^\(p-family-fail\.test\.sh: .*\)$/\1/p')"
expect_eq "9: …and the failing suite exits 1" "1" "$P_RC"
for _fn in eq ne true false contains absent match no_match status empty nonempty; do
  expect_eq "9: expect_${_fn}'s failing arm printed its FAIL row by label" "yes" \
    "$(contains "$P_OUT" "FAIL: ${_fn}")"
done

# --- expect_true/expect_false silence the command they run
plant_run p-family-silent.test.sh
expect_eq "9: a noisy command under expect_true/expect_false still passes and fails" \
  "p-family-silent.test.sh: 2/2 passed, 0 failed  sections=1 setup=0" \
  "$(printf '%s\n' "$P_OUT" | sed -n 's/^\(p-family-silent\.test\.sh: .*\)$/\1/p')"
expect_eq "9: …and the command's stdout never reaches the suite output" "no" \
  "$(contains "$P_OUT" "NOISE-ON-STDOUT")"
expect_eq "9: …nor its stderr" "no" \
  "$(contains "$P_OUT" "NOISE-ON-STDERR")"

# --- the mapping table is IN the framework, because S5-S8 quote it from there
FAMDOC="$(tr '\n' ' ' < "$FRAMEWORK" | sed 's/#//g' | tr -s ' ')"
expect_eq "9: the docblock carries the old-spelling mapping table" "yes" \
  "$(contains "$FAMDOC" "expect_equal -> expect_eq")"
expect_eq "9: …including the entry that is NOT a rename (ERE vs glob)" "yes" \
  "$(contains "$FAMDOC" "expect_matches -> NOT a rename")"
FAMDOC_STRIPPED="$(grep -v 'expect_equal ->' "$FRAMEWORK" | tr '\n' ' ' | sed 's/#//g' | tr -s ' ')"
expect_eq "9: …and the pin discriminates on a copy with the row removed" "no" \
  "$(contains "$FAMDOC_STRIPPED" "expect_equal -> expect_eq")"

finish
