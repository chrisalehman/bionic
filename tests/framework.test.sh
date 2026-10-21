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
#   §6b the head docblock describes the tree it heads
#   §9  the thirteen generic expect_* helpers are the framework's, each in a
#       passing and a failing arm (AC-12)
#   §10 expect_regex is an ERE and is not a pipeline (the 141 false FAIL)
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

# THE ROW GUARD (wave-27 T80). A suite that cannot trust a row's fixture names a guard in
# TF_ROW_GUARD; while the guard prints a reason, ok() records the row as a named fail carrying
# it, so an expect_* row that would have passed on a fixture never made fails by its own name.
# Unset, naming no function, or silent, ok() is what it always was. The planted suite runs a
# silent guard, a speaking guard under ok and under expect_eq, a guard that names no function,
# and the unset twin with the same LOST value set.
cat > "$SB/tests/p-guard.test.sh" <<'PLANT_GUARD'
#!/bin/bash
set -uo pipefail
. "$(dirname "$0")/lib/assert.sh"
lost_guard() { [ -z "${LOST:-}" ] || printf 'fixture lost: %s' "$LOST"; }

section "a row guard"
TF_ROW_GUARD=lost_guard
ok "a row while nothing is lost"
LOST=repo1
ok "a row while repo1 is lost"
expect_eq "an expect_eq row while repo1 is lost" same same
TF_ROW_GUARD=no_such_function
ok "a row under a guard that names no function"
unset TF_ROW_GUARD
ok "a row with repo1 lost and no guard"

finish
PLANT_GUARD

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
expect_regex     "regex"     'need[a-z]+' "a needle here"
expect_no_regex  "no_regex"  'straw[0-9]+' "a needle here"

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
expect_regex     "regex"     'straw[0-9]+' "a needle here"
expect_no_regex  "no_regex"  'need[a-z]+' "a needle here"

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

# --- §11's plants (S19, AC-29/AC-31). The fixture lives beside the planted
# suites so a quoted heredoc can name it without expanding anything here.
cat > "$SB/anchor-fx.txt" <<'PLANT_ANCHOR_FX'
a needle here
line 1
line 2
PLANT_ANCHOR_FX

cat > "$SB/tests/p-anchor.test.sh" <<'PLANT_ANCHOR'
#!/bin/bash
set -uo pipefail
. "$(dirname "$0")/lib/assert.sh"

FX="$(dirname "$0")/../anchor-fx.txt"

section "anchor, both arms"
anchor    "$FX" 'needle' 1
anchor -E "$FX" '^line [0-9]+$' 2
anchor    "$FX" '^line [0-9]+$' 2
anchor    "$FX" 'needle' 2
anchor    "$FX" 'moved-away' 1
anchor    "$(dirname "$0")/../no-such-fixture.txt" 'needle' 1
anchor    "$FX" 'line' 2

finish
PLANT_ANCHOR

# The ORDER plant (AC-29: the anchor fails BEFORE the doctoring step). The
# mutation here is a bare echo standing in for the `grep -v`/`sed` that would
# follow it in a real suite; the row must already be on stdout when it runs.
cat > "$SB/tests/p-anchor-order.test.sh" <<'PLANT_ANCHOR_ORDER'
#!/bin/bash
set -uo pipefail
. "$(dirname "$0")/lib/assert.sh"

FX="$(dirname "$0")/../anchor-fx.txt"

section "the anchor precedes the mutation"
anchor "$FX" 'moved-away' 1
echo "MUTATION-RAN"
ok "the suite kept going after the red anchor"

finish
PLANT_ANCHOR_ORDER

# THE ANCHOR STRENGTH PLANT (A-35a, S19c). The drift fixture is anchor-fx.txt
# with ONE leading space on the anchored line — the shape 61b8ca8 produced by
# reindenting a call. A fixed-string anchor is a SUBSTRING test and still matches
# it; a whole-line mutation does not touch it. The -E form, given the mutation's
# own ^…$, is the one that says so.
cat > "$SB/anchor-drift.txt" <<'PLANT_ANCHOR_DRIFT'
a needle here
 line 1
line 2
PLANT_ANCHOR_DRIFT

cat > "$SB/tests/p-anchor-strength.test.sh" <<'PLANT_ANCHOR_STRENGTH'
#!/bin/bash
set -uo pipefail
. "$(dirname "$0")/lib/assert.sh"

FX="$(dirname "$0")/../anchor-drift.txt"

section "an anchor must match at least as strictly as its mutation"
# THE WEAK ANCHOR: fixed-string, and it is GREEN over the drifted line.
anchor "$FX" 'line 1' 1
# THE STRONG ONE: the mutation's own whole-line ERE, and it is RED.
anchor -E "$FX" '^line 1$' 1
# What the mutation itself does to that file, so the row above is not a claim
# about grep but about the mutant: a whole-line sed no-ops.
MUT="$(sed 's/^line 1$/MUTATED/' "$FX")"
if [ "$MUT" = "$(cat "$FX")" ]; then
  ok "the whole-line mutation is a no-op on the drifted file"
else
  no "the whole-line mutation is a no-op on the drifted file" "it changed something"
fi

finish
PLANT_ANCHOR_STRENGTH

# ============================================================
section "1: a section that asserts nothing fails by name (AC-13)"
# ============================================================

plant_run p-empty.test.sh
expect_eq "1: the planted suite exits 1" "1" "$P_RC"
# PAIRED POSITIVE for the negative row below: the second section is present in
# the run, so its absence from the failure list is a discrimination and not an
# artefact of the section never having opened.
expect_eq "1: …and the section that DID assert ran" \
  "yes" "$(contains "$P_OUT" "PASS: a real row")"
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

# --- THE BOUNDARY THE DOCBLOCK NOW STATES (Step-5 audit §5.1) --------------
# The derivation sees the framework's own name family and nothing else, so a
# vanished helper under another name is caught at RUNTIME by the runner's
# stderr-strict arm and not at load. Demonstrated, not asserted from the
# docblock: the same undefined call under a derived name is red at load, and
# under a name outside the family is not.
cat > "$SB/tests/p-outside-family.test.sh" <<'PLANT_OUTSIDE'
#!/bin/bash
set -uo pipefail
. "$(dirname "$0")/lib/assert.sh"
section "a vanished helper outside the derived name family"
ok "the suite loaded and got this far"
walk_vanished_helper "gone"
finish
PLANT_OUTSIDE
plant_run p-outside-family.test.sh
expect_eq "3: a call outside the derived family does not stop the load" "0" "$P_RC"
expect_eq "3: …and the suite reports a clean tally in spite of it" "yes"   "$(contains "$P_OUT" "1/1 passed, 0 failed")"
expect_eq "3: …with the diagnostic only on stderr, which is the runner's half" "yes"   "$(contains "$P_OUT" "command not found")"
# PAIRED: the SAME shape under a derived name IS red at load.
cat > "$SB/tests/p-inside-family.test.sh" <<'PLANT_INSIDE'
#!/bin/bash
set -uo pipefail
. "$(dirname "$0")/lib/assert.sh"
section "a vanished helper inside the derived name family"
expect_vanished_helper "gone"
finish
PLANT_INSIDE
plant_run p-inside-family.test.sh
expect_eq "3: the same call under a DERIVED name is red at load" "1" "$P_RC"
expect_eq "3: …naming the helper" "yes"   "$(contains "$P_OUT" "helper called but never defined: expect_vanished_helper")"
# and the docblock says so, with a discriminating pin.
FAMDOC="$(tr '\n' ' ' < "$FRAMEWORK" | sed 's/#//g' | tr -s ' ')"
FAMDOC_STRIPPED="$(grep -v 'INTERPRETER PARITY, NOT VERDICT PARITY' "$FRAMEWORK" | tr '\n' ' ' | sed 's/#//g' | tr -s ' ')"

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

for _fn in section setup_section ok no advise finish require_helpers \
          expect_eq expect_ne expect_true expect_false expect_contains expect_absent \
          expect_match expect_no_match expect_status expect_empty expect_nonempty \
          expect_regex expect_no_regex; do
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

plant_run p-guard.test.sh
expect_eq "6g: …and the tally counts the two guarded rows as failures, the three others as passes" \
  "p-guard.test.sh: 3/5 passed, 2 failed  sections=1 setup=0" \
  "$(printf '%s\n' "$P_OUT" | sed -n 's/^\(p-guard\.test\.sh: .*\)$/\1/p')"

# ============================================================
section "6b: the head docblock describes the tree it heads (review-c C-1/C-2)"
# ============================================================
#
# It is the first paragraph an author writing suite 56 reads about ownership, and
# it said a private `ok()` was tolerated and that the wall was S10's future work.
# Both had been false since S10 landed. A docblock is not testable prose here —
# every claim below is re-derived from the shipped tree in the same run.

C1_DOC="$(tr '\n' ' ' < "$FRAMEWORK" | sed 's/#//g' | tr -s ' ')"
C1_REFUSED=0
C1_SUITES=0
for c1_f in "$REPO"/tests/*.test.sh; do
  C1_SUITES=$((C1_SUITES + 1))
  [ -n "$(_tf_adoption_refusal "$c1_f")" ] && C1_REFUSED=$((C1_REFUSED + 1))
done
# THE COUNT PIN IS RETIRED (fixit 1.5.1, D-1). The roster is tests/*.test.sh read
# at run time, so a suite count is stale the moment anyone adds a file, and a row
# pinning one tests the calendar. What is still worth holding is that the scan
# below read a real tree. The docblock's own "All 55" sentence was stale prose for
# the same reason; T4 corrected it, together with the needle two rows down, which
# quotes it.
expect_eq "6b: the docblock scan read the whole tree (not vacuous)" "yes" \
  "$([ "$C1_SUITES" -ge 40 ] && echo yes || echo no)"
expect_eq "6b: …and none of them carries a private definition" "0" "$C1_REFUSED"
expect_eq "6b: …and that it does not DEFER to a private one" "yes" \
  "$(contains "$C1_DOC" "It does not DEFER")"
expect_eq "6b: …and the stale claim that migration is still S5-S9's job is gone" "no" \
  "$(contains "$C1_DOC" "migrating those suites is S5")"
# C-2: the two expect_match exceptions were migrated, so the docblock stops
# calling them migration work — re-derived from the two files it names.
# The needle is SINGLE-quoted: the docblock spells the helper in backticks, and
# in a double-quoted needle bash would run it as a command substitution.
expect_eq "6b: …and the docblock records that S9b renamed them" "yes" \
  "$(contains "$C1_DOC" 'were renamed onto `expect_regex` by S9b')"

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
expect_regex    "9: expect_regex passes on a matching ERE"            'need[a-z]+' "a needle here"
expect_no_regex "9: expect_no_regex passes on a non-matching ERE"     'straw[0-9]+' "a needle here"

# --- the passing arms move the PASS counter and satisfy the section floor
plant_run p-family-pass.test.sh
expect_eq "9: thirteen passing arms are thirteen PASS rows in one section" \
  "p-family-pass.test.sh: 13/13 passed, 0 failed  sections=1 setup=0" \
  "$(printf '%s\n' "$P_OUT" | sed -n 's/^\(p-family-pass\.test\.sh: .*\)$/\1/p')"
expect_eq "9: …so the section floor does not name that section empty" "no" \
  "$(contains "$P_OUT" "section asserted nothing")"
expect_eq "9: …and the passing suite exits 0" "0" "$P_RC"

# --- the failing arms move the FAIL counter: each helper calls no()
plant_run p-family-fail.test.sh
expect_eq "9: thirteen failing arms are thirteen FAIL rows" \
  "p-family-fail.test.sh: 0/13 passed, 13 failed  sections=1 setup=0" \
  "$(printf '%s\n' "$P_OUT" | sed -n 's/^\(p-family-fail\.test\.sh: .*\)$/\1/p')"
expect_eq "9: …and the failing suite exits 1" "1" "$P_RC"
for _fn in eq ne true false contains absent match no_match status empty nonempty regex no_regex; do
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
expect_eq "9: …including the ERE spelling, now a pure rename onto expect_regex" "yes" \
  "$(contains "$FAMDOC" "expect_matches -> expect_regex")"
expect_eq "9: …and the entry that is still NOT a rename (it takes a file)" "yes" \
  "$(contains "$FAMDOC" "expect_nomatch -> NOT a rename")"
FAMDOC_STRIPPED="$(grep -v 'expect_equal ->' "$FRAMEWORK" | tr '\n' ' ' | sed 's/#//g' | tr -s ' ')"
expect_eq "9: …and the pin discriminates on a copy with the row removed" "no" \
  "$(contains "$FAMDOC_STRIPPED" "expect_equal -> expect_eq")"

# ============================================================
section "10: expect_regex is an ERE, and it is not a pipeline (S1b phase 2)"
# ============================================================
#
# A-S1b-2 resolved as option 2: regex matching is generic, so the framework owns
# it rather than leaving eight suites to keep a private copy. Two things have to
# be true of it and are not true of expect_match, so they are asserted here and
# not inferred: it is a REGEX, and it does not run grep in a pipeline.

# --- it is an ERE, not a glob: quantifiers and alternation mean what they say
expect_regex    "10: a quantifier is a quantifier"        'mtime=[0-9]+' "target=x|mtime=1234"
expect_regex    "10: alternation and anchors work"        '(^|\|)v1(\||$)' "v1|target=x"
expect_no_regex "10: …and a non-matching ERE does not fire" 'mtime=[a-z]+' "target=x|mtime=1234"
# PAIRED NEGATIVE, the discriminating one: the glob helper reads the same pattern
# literally, so what expect_regex matches, expect_match must NOT.
expect_no_match "10: expect_match reads that same pattern as a literal glob" \
  'mtime=[0-9]+' "target=x|mtime=1234"

# --- it is unanchored: a substring ERE matches without needing .* on either side
expect_regex "10: the ERE is unanchored (no leading .* required)" 'needle' "a needle here"
expect_match "10: …whereas the glob helper needs the stars" '*needle*' "a needle here"

# --- it is not a pipeline. `producer | grep -q` exits 141 under pipefail once
# the producer outstrips the 64 KiB pipe buffer, because grep leaves early and
# the producer takes SIGPIPE. That is a FALSE FAIL, and it is how two suites
# spell their private expect_matches today.
BIG="$(yes abcdefghij | head -20000)"
expect_regex "10: a large value still matches (no SIGPIPE in the framework's form)" \
  'abcdefghij' "$BIG"
# The paired halves of the defect: the SAME pipeline, the SAME pattern, one small
# value and one large one. Small is correct; large reports failure on a value the
# pattern matches. The exact status is not pinned — it is 141 when printf dies by
# SIGPIPE and 1 when bash reports the write error instead, which varies with the
# producer, the size and whether a trap is installed (measured all three ways on
# this machine). What is stable, and what makes it a lie, is non-zero.
printf '%s\n' "abcdefghij" 2>/dev/null | grep -qE -- 'abcdefghij'
PIPE_SMALL=$?
printf '%s\n' "$BIG" 2>/dev/null | grep -qE -- 'abcdefghij'
PIPE_BIG=$?
expect_eq "10: the pipeline spelling is right on a small value" "0" "$PIPE_SMALL"
expect_ne "10: …and wrong on a large one, non-zero though the pattern matches" \
  "0" "$PIPE_BIG"

# --- AND NOWHERE ELSE IN THE FILE (review-a A-6) ----------------------------
# The ban is stated twice in the framework's own docblocks and was broken in the
# framework's own load path — `echo "$defs" | grep -qx` inside the AC-14
# derivation, on the path every suite crosses. A census, so a new one added
# tomorrow fails here rather than the day a producer outgrows the pipe buffer.
# The pattern is built at runtime so this row does not match itself.
# Comment lines are excluded because the ban is STATED in three of them; the
# census is about code. `grep -c` is not `grep -q`, so it reads to EOF and takes
# no SIGPIPE of its own.
F10_BANNED="$(printf '| %s -q' grep)"
F10_CODE="$(grep -v '^[[:space:]]*#' "$FRAMEWORK")"
expect_eq "10: no producer-into-grep -q in the framework's code" "0" \
  "$(printf '%s\n' "$F10_CODE" | grep -c -- "$F10_BANNED" | tr -d ' ')"
# f10_stated <file> -> yes when the file states the ban at least once. The code census above
# is vacuous over a file that never names the idiom; this row says the ban is still written
# down. How many comment lines say it is not asked.
f10_stated() {
  [ "$(grep -c -- "$F10_BANNED" "$1" | tr -d ' ')" -ge 1 ] && echo yes || echo no
}
# f10_code_hits <file> -> the number of banned spellings in the file's non-comment lines
f10_code_hits() {
  grep -v '^[[:space:]]*#' "$1" | grep -c -- "$F10_BANNED" | tr -d ' '
}
expect_eq "10: …and the census can see one in code when there is one (not vacuous)" "1" \
  "$(printf 'echo "$x" %s -- "$y"\n' "$F10_BANNED" | grep -v '^[[:space:]]*#' | grep -c -- "$F10_BANNED" | tr -d ' ')"

# ============================================================
finish
