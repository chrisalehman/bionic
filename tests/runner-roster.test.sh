#!/bin/bash
# tests/runner-roster.test.sh — the gating roster IS the tests/ directory
# (fixit 1.5.1, plan AC-3/AC-4/AC-5, design D-1/D-3).
#
# WHAT IT COVERS. tests/run.sh used to name every suite by hand: fifty-five `run`
# lines, one per file, and a suite the list forgot never ran at all. The roster is
# now the sorted `tests/*.test.sh` listing, read at run time, and this file is the
# one place that property is proved. D-3: THE HARNESS PROVES ITSELF, ONCE — no
# other suite asserts its own membership, because membership is no longer a thing
# a suite can be missing from.
#
# THE FOUR CLAIMS, each driven against a scratch tree carrying the shipped
# tests/run.sh byte for byte:
#
#   (a) a suite dropped into tests/ is run on the very next invocation, with no
#       edit anywhere — observed through the labels the runner already prints,
#       paired against the run before the drop, where the same label is absent.
#   (b) a file in the glob that is not a suite makes the runner REFUSE: non-zero,
#       naming the file, before any suite runs. Both halves of the shape are
#       driven — a wrong shebang and a file that never sources the framework —
#       and each is paired with the same tree, unplanted, going green.
#   (c) an empty tests/ refuses too, non-zero, rather than reporting a green run
#       over nothing.
#   (d) the roster the runner uses equals the glob, as a SET and not as a count:
#       every file in the scratch tests/ appears as a label, and no label appears
#       that has no file.
#
# WHY A SCRATCH TREE AND NOT THIS REPO. Driving the real runner here would launch
# the whole roster — including this suite — from inside a run. Every drive below
# is a COPY of the shipped tests/run.sh in its own mktemp root, with its own
# stub suites; the real tests/ directory is read (for the byte-for-byte
# comparison) and never written.
#
# FIXTURE DISCIPLINE. `BIONIC_PRESSURE_RING` points under this suite's own
# mktemp root on every drive and `BIONIC_NOW_EPOCH` pins the clock, so no drive
# reads or writes the machine's real pressure ring. Every non-dry `bash
# tests/run.sh` drive also pins `BIONIC_PROBE_FREE_PCT` / `BIONIC_PROBE_SWAP_PCT`
# / `BIONIC_PROBE_LOAD_1M` to the same calm reading §8.9's ring is seeded with
# (44/0/0.1, resources.sh's `_res_free_pct` / `_res_swap_pct` / `_res_load_1m`
# overrides): `tests/run.sh` samples the machine's LIVE pressure into that ring
# on every non-dry invocation (tests/run.sh:363), so an unpinned drive on a
# loaded machine appends a real sample and can move a later `pressure_level`
# read off the fixture's own band (floor-e199431 §8.9, T28).
#
# Usage: bash tests/runner-roster.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"

REPO="$BIONIC_SCRIPTS_DIR"
RUNNER="$REPO/tests/run.sh"

TMPROOT="$(mktemp -d "${TMPDIR:-/tmp}/runner-roster-test.XXXXXX")"
trap 'rm -rf "$TMPROOT"' EXIT

RR_NOW=1700000000

# THE GATE'S STORE IS THIS SUITE'S OWN (wave-26 T8; the gate since wave-28 T12). Every suite a
# runner starts asks the gate, and a solo suite asks it for the whole machine, so every drive
# below names a store under this suite's mktemp root, a short poll, and a low memory reading
# and an idle processor, pinned, so an admission never waits on what this machine is doing;
# none reads or writes the machine's real store under the home directory. The admission a
# caller may have inherited (a booked command or a runner around this suite exports
# BIONIC_GATE_ADMIT) is cleared, so each drive starts from no admission at all — §11 drives
# nesting itself.
RR_GATE_ENV=(-u BIONIC_GATE_ADMIT -u BIONIC_GATE_AGENT -u BIONIC_QUIET -u BIONIC_LOAD_NOW_FILE
  "BIONIC_GATE_DIR=$TMPROOT/gate" BIONIC_GATE_POLL=0.1 BIONIC_PROBE_USED_PCT=10
  BIONIC_PROBE_BUSY_CORES=0 BIONIC_PROBE_CORES=8 BIONIC_PROBE_TOTAL_MB=8192)

# rr_tree <dir> — a scratch tree the shipped runner resolves against: the runner
# itself byte for byte, the seam every suite sources, the real framework (so the
# shape wall has a framework to ask about), and the payload libraries the runner
# sources for its width.
rr_tree() {
  local dir="$1"
  mkdir -p "$dir/tests/lib" "$dir/payload/scripts/lib"
  cp "$RUNNER" "$dir/tests/run.sh"
  cp "$REPO/tests/lib/resolve-roots.sh" "$dir/tests/lib/resolve-roots.sh"
  cp "$REPO/tests/lib/assert.sh" "$dir/tests/lib/assert.sh"
  cp "$REPO"/payload/scripts/lib/*.sh "$dir/payload/scripts/lib/" 2>/dev/null
}

# rr_stub <dir> <basename-without-suffix> — a real, green, framework-adopting
# suite: it is what a maintainer dropping a new file into tests/ writes.
rr_stub() {
  local dir="$1" name="$2"
  { printf '#!/bin/bash\n'
    printf 'set -uo pipefail\n'
    printf '. "$(dirname "$0")/lib/assert.sh"\n'
    printf ': > "$RR_MARKS/%s.ran"\n' "$name"
    printf 'section "%s"\n' "$name"
    printf 'expect_eq "%s ran" "x" "x"\n' "$name"
    printf 'finish\n'
  } > "$dir/tests/$name.test.sh"
}

# rr_drive <dir> [mode] — run the scratch runner, leaving RR_OUT and RR_RC.
RR_OUT=""; RR_RC=0
rr_drive() {
  local dir="$1" mode="${2:-}"
  RR_OUT="$( cd "$dir" && \
    RR_MARKS="$RR_MARKS" \
    BIONIC_PRESSURE_RING="$TMPROOT/ring" \
    BIONIC_NOW_EPOCH="$RR_NOW" \
    BIONIC_TEST_JOBS_CEILING="2" \
    BIONIC_PROBE_FREE_PCT="44" \
    BIONIC_PROBE_SWAP_PCT="0" \
    BIONIC_PROBE_LOAD_1M="0.1" \
    env "${RR_GATE_ENV[@]}" bash tests/run.sh ${mode:+"$mode"} 2>&1 )"
  RR_RC=$?
}

# rr_labels <output> — the suite labels the runner printed, sorted. The label
# column is the runner's own `_label` format: two spaces, then the label padded
# to 36 columns, then a verdict.
rr_labels() {
  printf '%s\n' "$1" | sed -n 's/^  \([A-Za-z0-9_.-]*\.test\.sh\) .*/\1/p' | sort -u
}

# rr_glob <dir> — the sorted basenames of <dir>/tests/*.test.sh, or nothing.
rr_glob() {
  ls "$1"/tests/*.test.sh 2>/dev/null | sed 's|.*/||' | sort
}

RR_MARKS="$TMPROOT/marks"
mkdir -p "$RR_MARKS"

# ============================================================
section "§1 the roster is the directory: every file in tests/ is a label (d)"
# ============================================================
#
# NOT VACUOUS: the runner under drive is the shipped file, byte for byte — the
# roster it reads is the one this repo ships, not a fixture of this suite's own.

T1="$TMPROOT/t1"
rr_tree "$T1"
expect_eq "1.1 the scratch runner is the shipped one, byte for byte" "yes" \
  "$(cmp -s "$RUNNER" "$T1/tests/run.sh" && echo yes || echo no)"

for RR_N in alpha bravo charlie; do rr_stub "$T1" "$RR_N"; done
rr_drive "$T1"

expect_eq "1.2 the run is green over the three suites in the directory" "0" "$RR_RC"
expect_contains "1.3 …and the tally counts three" "Gating: 3 passed, 0 failed" "$RR_OUT"
expect_eq "1.4 the labels the runner printed ARE the glob, as a set" \
  "$(rr_glob "$T1")" "$(rr_labels "$RR_OUT")"
# PAIRED POSITIVE for 1.4: the set is not empty, so an equality of two empty
# strings cannot be what passed it.
expect_eq "1.5 …and that set has the three files in it (not two empty sets)" "3" \
  "$(rr_labels "$RR_OUT" | grep -c .)"
# Each suite really ran: a label is printed for a refused suite too, so the
# markers are what separate "listed" from "launched".
expect_eq "1.6 each of the three actually ran (its own marker)" "3" \
  "$(ls "$RR_MARKS" 2>/dev/null | grep -c '\.ran$')"

# ============================================================
section "§2 a suite dropped into tests/ gates on the next invocation (a)"
# ============================================================
#
# THE PAIR IS THE POINT. The same tree, the same runner, driven twice with one
# new file in between and no edit anywhere: absent in the first run, present and
# run in the second. Under the hand list the second run looked exactly like the
# first, which is the silent false green this suite exists to close.

expect_absent "2.1 before the drop, the new suite is not in the roster" \
  "delta.test.sh" "$RR_OUT"

rm -f "$RR_MARKS"/*.ran
rr_stub "$T1" "delta"
rr_drive "$T1"

expect_contains "2.2 after the drop, the runner names it — no edit anywhere" \
  "delta.test.sh" "$RR_OUT"
expect_eq "2.3 …and it actually ran (its own marker)" "yes" \
  "$([ -f "$RR_MARKS/delta.ran" ] && echo yes || echo no)"
expect_contains "2.4 …and it is counted in the tally" "Gating: 4 passed, 0 failed" "$RR_OUT"
expect_eq "2.5 …and the roster is still exactly the glob" \
  "$(rr_glob "$T1")" "$(rr_labels "$RR_OUT")"

# --- ONE ROSTER, BOTH MODES -------------------------------------------------
# A mode is a scheduling choice and nothing else (the runner's own header), so
# --serial reads the same derived roster.
rm -f "$RR_MARKS"/*.ran
rr_drive "$T1" "--serial"
expect_eq "2.6 --serial reads the same derived roster" \
  "$(rr_glob "$T1")" "$(rr_labels "$RR_OUT")"
expect_contains "2.7 …and reaches the same tally" "Gating: 4 passed, 0 failed" "$RR_OUT"
expect_eq "2.8 …and the same exit status" "0" "$RR_RC"

# ============================================================
section "§3 a file in the glob that is not a suite is REFUSED, by name (b)"
# ============================================================
#
# THE SHAPE ALL FIFTY-FIVE SUITES SHARE, measured 2026-09-06: first line
# `#!/bin/bash`, and a line sourcing the framework. A file in tests/ that has
# neither is not a suite, and a runner that treats it as one either reports a
# failure that is really a misplaced file, or — worse — runs it. Both halves are
# driven, each against a tree that is green without the plant.

T3="$TMPROOT/t3"
rr_tree "$T3"
rr_stub "$T3" "keeper"
rm -f "$RR_MARKS"/*.ran
rr_drive "$T3"
expect_eq "3.1 the unplanted tree is green (the control)" "0" "$RR_RC"
expect_eq "3.2 …and its one suite ran" "yes" \
  "$([ -f "$RR_MARKS/keeper.ran" ] && echo yes || echo no)"

# --- (i) a file that never sources the framework ----------------------------
{ printf '#!/bin/bash\n'
  printf 'echo "a helper someone dropped in tests/, not a suite"\n'
  printf ': > "$RR_MARKS/stray.ran"\n'
} > "$T3/tests/stray.test.sh"
rm -f "$RR_MARKS"/*.ran
rr_drive "$T3"
expect_eq "3.3 a file that adopts no framework makes the run refuse" "2" "$RR_RC"
expect_contains "3.4 …naming the file" "tests/stray.test.sh" "$RR_OUT"
expect_contains "3.5 …and saying what the shape is" "does not source the framework" "$RR_OUT"
expect_eq "3.6 …before any suite runs: nothing ran at all" "0" \
  "$(ls "$RR_MARKS" 2>/dev/null | grep -c '\.ran$')"
# PAIRED: the good suite beside it is not named as the offender.
expect_absent "3.7 …and the suite that IS a suite is not named as the offender" \
  "tests/keeper.test.sh does not" "$RR_OUT"
rm -f "$T3/tests/stray.test.sh"

# --- (ii) a file whose first line is not the pinned shebang ------------------
{ printf '#!/usr/bin/env bash\n'
  printf 'set -uo pipefail\n'
  printf '. "$(dirname "$0")/lib/assert.sh"\n'
  printf 'section "wrong shebang"\n'
  printf 'expect_eq "x" "x" "x"\n'
  printf 'finish\n'
} > "$T3/tests/wrongbang.test.sh"
rm -f "$RR_MARKS"/*.ran
rr_drive "$T3"
expect_eq "3.8 a file whose first line is not #!/bin/bash makes the run refuse" "2" "$RR_RC"
expect_contains "3.9 …naming the file" "tests/wrongbang.test.sh" "$RR_OUT"
expect_contains "3.10 …and saying which half of the shape it failed" \
  "first line is not #!/bin/bash" "$RR_OUT"
expect_eq "3.11 …before any suite runs: nothing ran at all" "0" \
  "$(ls "$RR_MARKS" 2>/dev/null | grep -c '\.ran$')"
rm -f "$T3/tests/wrongbang.test.sh"

# --- the tree recovers: the refusal was the plant's doing --------------------
rm -f "$RR_MARKS"/*.ran
rr_drive "$T3"
expect_eq "3.12 with both plants removed the same tree is green again" "0" "$RR_RC"
expect_eq "3.13 …and its suite ran" "yes" \
  "$([ -f "$RR_MARKS/keeper.ran" ] && echo yes || echo no)"

# --- NO FRAMEWORK, NO FRAMEWORK HALF ----------------------------------------
# The rule is "a line sourcing the framework THIS TREE owns", so a tree with no
# framework owns nothing to source and can ask nothing about it — the same
# honest reading the runner's older per-suite wall already ships, and the state
# the runner-mechanics suites (interpreter-pin, runner-width, cross-gate §RG)
# drive their scratch trees in. The shebang half still binds there.
T3B="$TMPROOT/t3b"
rr_tree "$T3B"
rm -f "$T3B/tests/lib/assert.sh"
{ printf '#!/bin/bash\n'
  printf ': > "$RR_MARKS/probe.ran"\n'
  printf 'exit 0\n'
} > "$T3B/tests/probe.test.sh"
rm -f "$RR_MARKS"/*.ran
rr_drive "$T3B"
expect_eq "3.14 a framework-less tree runs its raw probe rather than refusing it" "0" "$RR_RC"
expect_eq "3.15 …and the probe really ran" "yes" \
  "$([ -f "$RR_MARKS/probe.ran" ] && echo yes || echo no)"
# PAIRED: the shebang half is NOT relaxed by a missing framework.
{ printf '#!/usr/bin/env bash\n'
  printf 'exit 0\n'
} > "$T3B/tests/probe2.test.sh"
rm -f "$RR_MARKS"/*.ran
rr_drive "$T3B"
expect_eq "3.16 …but a wrong shebang is still refused with no framework present" "2" "$RR_RC"
expect_contains "3.17 …naming that file" "tests/probe2.test.sh" "$RR_OUT"

# ============================================================
section "§4 an empty tests/ refuses rather than reporting green over nothing (c)"
# ============================================================

T4="$TMPROOT/t4"
rr_tree "$T4"
rr_drive "$T4"
expect_eq "4.1 a tree with no suites at all exits non-zero" "2" "$RR_RC"
expect_contains "4.2 …saying so in words" "no suites under tests/" "$RR_OUT"
expect_absent "4.3 …and does not report a green run" "All gating suites green" "$RR_OUT"

# --serial takes the same refusal — one roster, both modes.
rr_drive "$T4" "--serial"
expect_eq "4.4 --serial refuses the same way" "2" "$RR_RC"
expect_contains "4.5 …in the same words" "no suites under tests/" "$RR_OUT"

# --dry-run reads the same roster, so it refuses too: a width to run nothing at
# is a number with no run behind it.
rr_drive "$T4" "--dry-run"
expect_eq "4.6 --dry-run refuses the same way" "2" "$RR_RC"
expect_contains "4.7 …in the same words" "no suites under tests/" "$RR_OUT"
# PAIRED POSITIVE: --dry-run over a tree that HAS a suite still prints the width
# and runs nothing.
rm -f "$RR_MARKS"/*.ran
rr_drive "$T1" "--dry-run"
expect_eq "4.8 …while --dry-run over a populated tree still exits 0" "0" "$RR_RC"
expect_contains "4.9 …printing the width" "JOBS=" "$RR_OUT"
expect_eq "4.10 …and running nothing" "0" \
  "$(ls "$RR_MARKS" 2>/dev/null | grep -c '\.ran$')"

# ============================================================
section "§5 the shipped tree: the roster the real runner reads is the real glob"
# ============================================================
#
# The set-vs-set census (AC-6), taken on this repo without launching it: the
# runner names no suite by hand any more, so the only thing that can disagree
# with the directory is the derivation itself.

expect_eq "5.1 the shipped runner hand-lists no suite by name" "0" \
  "$(grep -c '^run "' "$RUNNER" | tr -d ' ')"
expect_eq "5.2 …and every file in tests/ satisfies the shape it demands" "0" \
  "$(RR_BAD=0
     for RR_F in "$REPO"/tests/*.test.sh; do
       [ "$(head -1 "$RR_F")" = '#!/bin/bash' ] || RR_BAD=$((RR_BAD + 1))
       grep -qE '^[[:space:]]*(\.|source)[[:space:]].*assert\.sh' "$RR_F" || RR_BAD=$((RR_BAD + 1))
     done
     echo "$RR_BAD")"
# PAIRED POSITIVE: the loop above really read the tree.
expect_eq "5.3 …over a directory with suites in it (not vacuous)" "yes" \
  "$([ "$(ls "$REPO"/tests/*.test.sh | grep -c .)" -ge 40 ] && echo yes || echo no)"
# The two arms §6 adds, asked of the shipped tree: every match is a REGULAR file
# (no symlink, no directory) and every name is spelled in the characters the
# queue and the parallel launcher can carry.
expect_eq "5.4 …every glob match in the shipped tree is a regular file, not a link" "0" \
  "$(RR_BAD=0
     for RR_F in "$REPO"/tests/*.test.sh; do
       { [ -f "$RR_F" ] && [ ! -L "$RR_F" ]; } || RR_BAD=$((RR_BAD + 1))
     done
     echo "$RR_BAD")"
# A `)` closing a case pattern inside `$( )` is what bash 3.2 mis-parses as the
# end of the substitution, so the pattern opens with `(` — the same spelling the
# runner's own wall uses for the same reason.
expect_eq "5.5 …and every name is inside [A-Za-z0-9._-]" "0" \
  "$(RR_BAD=0
     for RR_F in "$REPO"/tests/*.test.sh; do
       case "${RR_F##*/}" in (*[!A-Za-z0-9._-]*) RR_BAD=$((RR_BAD + 1)) ;; esac
     done
     echo "$RR_BAD")"

# ============================================================
section "§6 a glob match that is not a plain, plainly-named file is REFUSED"
# ============================================================
#
# THE GLOB MATCHES MORE THAN FILES, and the wall's two shape halves read right
# through the difference. A symlink is followed by both `read` and `grep`, so the
# TARGET's shebang and framework line are what pass the wall while the body that
# runs lives somewhere else entirely (Step-6 review A-7 / walk F-10: a link to a
# suite outside the tree was executed and counted a green gating suite). A
# directory matching the glob is read too, which is where `read error: Is a
# directory` came from before the refusal (walk F-12). And a name carrying a
# space or a quote survives the wall and then breaks the QUEUE: the launch file
# is line-delimited and xargs re-splits on whitespace and honours quotes, so the
# default mode reported every suite KILLED while --serial reported them all green
# (review A-3) — two modes, two verdicts, from one filename.
#
# So the wall asks three questions before it asks about shape, and the name is
# the first of them: a refusal that names the file cannot itself be a file the
# refusal machinery mis-splits.

T6="$TMPROOT/t6"
rr_tree "$T6"
rr_stub "$T6" "keeper"
rm -f "$RR_MARKS"/*.ran
rr_drive "$T6"
expect_eq "6.1 the unplanted tree is green (the control)" "0" "$RR_RC"
expect_eq "6.2 …and its one suite ran" "yes" \
  "$([ -f "$RR_MARKS/keeper.ran" ] && echo yes || echo no)"

# --- (i) a symlink, whose body lives outside the tree the reviewer read -------
{ printf '#!/bin/bash\n'
  printf 'set -uo pipefail\n'
  printf '. "$(dirname "$0")/lib/assert.sh"\n'
  printf ': > "$RR_MARKS/outside.ran"\n'
  printf 'section "outside"\n'
  printf 'expect_eq "outside ran" "x" "x"\n'
  printf 'finish\n'
} > "$TMPROOT/outside-the-tree.sh"
ln -sf "$TMPROOT/outside-the-tree.sh" "$T6/tests/linked.test.sh"
rm -f "$RR_MARKS"/*.ran
rr_drive "$T6"
expect_eq "6.3 a symlink matching the glob makes the run refuse" "2" "$RR_RC"
expect_contains "6.4 …naming the file" "tests/linked.test.sh" "$RR_OUT"
expect_contains "6.5 …and saying it is not a regular file" "not a regular file" "$RR_OUT"
expect_eq "6.6 …with the body it points at never executed" "no" \
  "$([ -f "$RR_MARKS/outside.ran" ] && echo yes || echo no)"
expect_eq "6.7 …and nothing else run either" "0" \
  "$(ls "$RR_MARKS" 2>/dev/null | grep -c '\.ran$')"
expect_absent "6.8 …and no green verdict is printed" "All gating suites green" "$RR_OUT"
rm -f "$T6/tests/linked.test.sh"

# --- (ii) a DIRECTORY matching the glob --------------------------------------
# The verdict was already right; what was wrong is that the first line a reader
# saw was the shell's own `read error: Is a directory`, from the wall reading a
# thing it had not asked whether it could read.
mkdir -p "$T6/tests/adir.test.sh"
rm -f "$RR_MARKS"/*.ran
rr_drive "$T6"
expect_eq "6.9 a directory matching the glob makes the run refuse" "2" "$RR_RC"
expect_contains "6.10 …naming it" "tests/adir.test.sh" "$RR_OUT"
expect_absent "6.11 …without a read error in front of the refusal" "read error" "$RR_OUT"
expect_absent "6.12 …and without the interpreter's own words for it" "Is a directory" "$RR_OUT"
rmdir "$T6/tests/adir.test.sh"

# --- (iii) a name carrying a space, and one carrying a quote ------------------
# Both are refused BY NAME before either mode runs, which is what keeps the two
# modes from disagreeing: the parallel launcher never sees the name at all.
{ printf '#!/bin/bash\n'
  printf 'set -uo pipefail\n'
  printf '. "$(dirname "$0")/lib/assert.sh"\n'
  printf ': > "$RR_MARKS/spaced.ran"\n'
  printf 'section "spaced"\n'
  printf 'expect_eq "spaced ran" "x" "x"\n'
  printf 'finish\n'
} > "$T6/tests/bad name.test.sh"
rm -f "$RR_MARKS"/*.ran
rr_drive "$T6"
expect_eq "6.13 a name with a space in it makes the run refuse" "2" "$RR_RC"
expect_contains "6.14 …naming it" "bad name.test.sh" "$RR_OUT"
expect_contains "6.15 …and saying the name is what is wrong" "the file name" "$RR_OUT"
expect_eq "6.16 …before anything ran" "0" \
  "$(ls "$RR_MARKS" 2>/dev/null | grep -c '\.ran$')"
# THE TWO MODES AGREE, which is the point of refusing at the name: --serial ran
# such a file happily while the default mode killed every suite in the queue.
rr_drive "$T6" "--serial"
expect_eq "6.17 …and --serial refuses it the same way" "2" "$RR_RC"
expect_contains "6.18 …in the same words" "the file name" "$RR_OUT"
rm -f "$T6/tests/bad name.test.sh"

printf '#!/bin/bash\n. "$(dirname "$0")/lib/assert.sh"\nfinish\n' > "$T6/tests/'quoted.test.sh"
rm -f "$RR_MARKS"/*.ran
rr_drive "$T6"
expect_eq "6.19 a name carrying a quote makes the run refuse" "2" "$RR_RC"
expect_contains "6.20 …naming it" "quoted.test.sh" "$RR_OUT"
expect_absent "6.21 …and the launcher never sees it (no unterminated quote)" \
  "unterminated quote" "$RR_OUT"
rm -f "$T6/tests/'quoted.test.sh"

# --- the tree recovers: every refusal above was the plant's doing -------------
rm -f "$RR_MARKS"/*.ran
rr_drive "$T6"
expect_eq "6.22 with every plant removed the same tree is green again" "0" "$RR_RC"
expect_eq "6.23 …and its suite ran" "yes" \
  "$([ -f "$RR_MARKS/keeper.ran" ] && echo yes || echo no)"

# ============================================================
section "§7 the runner refuses when its own width oracle is absent (walk F-9)"
# ============================================================
#
# THE HARNESS PROVES ITS OWN PRECONDITIONS (design D-3). The width comes from
# `pressure_level` in payload/scripts/lib/resources.sh, sourced by the runner. A
# tree where that library is missing used to print two lines on the runner's OWN
# stderr — the failed source and `pressure_level: command not found` — fall back
# to JOBS=8 and finish with `All gating suites green ✓`. The runner's lost-command
# reader only reads a SUITE's captured output, so nothing read those two lines,
# and a run whose width oracle never answered still called itself green.

T7="$TMPROOT/t7"
rr_tree "$T7"
rr_stub "$T7" "keeper"
rm -f "$RR_MARKS"/*.ran
rr_drive "$T7"
expect_eq "7.1 the intact tree is green (the control)" "0" "$RR_RC"
expect_contains "7.2 …and it says so" "All gating suites green" "$RR_OUT"

rm -f "$T7/payload/scripts/lib/resources.sh"
rm -f "$RR_MARKS"/*.ran
rr_drive "$T7"
expect_eq "7.3 with the width library gone the run refuses" "2" "$RR_RC"
expect_contains "7.4 …naming the library it could not load" "resources.sh" "$RR_OUT"
expect_contains "7.5 …and the function that answers the width" "pressure_level" "$RR_OUT"
expect_absent "7.6 …and never reports a green run" "All gating suites green" "$RR_OUT"
expect_eq "7.7 …with nothing run at all" "0" \
  "$(ls "$RR_MARKS" 2>/dev/null | grep -c '\.ran$')"
# --dry-run reads the same width, so it takes the same refusal rather than
# printing a number nothing answered for.
rr_drive "$T7" "--dry-run"
expect_eq "7.8 --dry-run refuses too" "2" "$RR_RC"
expect_absent "7.9 …and prints no width" "JOBS=" "$RR_OUT"

# ============================================================
section "§8 a suite marked \`# runner: solo\` is held out of the parallel batch (T20, A-orch-28)"
# ============================================================
#
# THE DEFECT (why-session-start-slow.md, floor-057caa2-run2.txt): tests/run.sh drains its
# roster through `xargs -P "$JOBS"`, up to eight-wide, and a suite bounding wall-clock
# seconds of ONE drive is dilated by however many siblings share the CPU with it — measured
# 1.270s alone, 3.395s inside an eight-wide batch on a quiet machine, same tree. A suite that
# declares itself timing-bound with a `# runner: solo` header comment (within its first 30
# lines) must run ALONE, after the rest of the batch has fully drained, so its own bound
# measures its own drive rather than a batch it happens to share.
#
# THE FIXTURE. Three trivial siblings each claim a marker under $RR8_MARKS/running/ for the
# full second they sleep, then remove it. One suite — named "aaa-solo" so the roster's
# alphabetical order puts it FIRST, guaranteeing xargs bundles it into the very first
# concurrent round under the OLD scheduler — polls for 1.2s (24 x 0.05s) and records whether
# it EVER saw a sibling's marker. Under the unfixed runner all four suites launch together at
# width 2, so aaa-solo's poll window (1.2s) overlaps the siblings' 1s sleep and it fails its
# own assertion — RED. Fixed, aaa-solo is excluded from the parallel batch entirely and only
# launched once the batch (and every sibling's cleanup) has finished, so it observes nothing —
# GREEN. This is a real concurrency observation, not a timing guess: no wall clock is bounded
# here, only "was a sibling ever alive while I ran".

T8="$TMPROOT/t8"
rr_tree "$T8"
RR8_RING="$TMPROOT/t8-ring"
mkdir -p "$(dirname "$RR8_RING")"
# A CLEAR reading (band 0) at ceiling 2 -> JOBS=2, so the first round is two-wide and the
# alphabetically-first suite (aaa-solo, under the unfixed runner) is bundled with a sibling.
printf '%s|44|0|0.1|2\n' "$RR_NOW" > "$RR8_RING"

RR8_MARKS="$TMPROOT/t8-marks"
mkdir -p "$RR8_MARKS/running"

# rr8_sibling <name> — claims $RR8_MARKS/running/<name> for a full second, a marker any
# concurrently-running suite can observe, then a trivial green assertion.
rr8_sibling() {
  local dir="$1" name="$2"
  { printf '#!/bin/bash\n'
    printf 'set -uo pipefail\n'
    printf '. "$(dirname "$0")/lib/assert.sh"\n'
    printf ': > "$RR8_MARKS/running/%s"\n' "$name"
    printf 'sleep 1\n'
    printf 'rm -f "$RR8_MARKS/running/%s"\n' "$name"
    printf 'section "%s"\n' "$name"
    printf 'expect_eq "%s ran" "x" "x"\n' "$name"
    printf 'finish\n'
  } > "$dir/tests/$name.test.sh"
}
for RR8_N in sib-a sib-b sib-c; do rr8_sibling "$T8" "$RR8_N"; done

# THE SOLO SUITE ITSELF — declares itself with the marker convention verbatim, then polls.
{ printf '#!/bin/bash\n'
  printf '# runner: solo\n'
  printf 'set -uo pipefail\n'
  printf '. "$(dirname "$0")/lib/assert.sh"\n'
  printf 'SEEN=no\n'
  printf 'RR8_I=0\n'
  printf 'while [ "$RR8_I" -lt 24 ]; do\n'
  printf '  if ls "$RR8_MARKS"/running/* >/dev/null 2>&1; then SEEN=yes; fi\n'
  printf '  sleep 0.05\n'
  printf '  RR8_I=$((RR8_I + 1))\n'
  printf 'done\n'
  printf ': > "$RR8_MARKS/solo.ran"\n'
  printf 'section "aaa-solo"\n'
  printf 'expect_eq "aaa-solo never observed a live sibling drive" "no" "$SEEN"\n'
  printf 'finish\n'
} > "$T8/tests/aaa-solo.test.sh"
expect_contains "8.1 the solo suite really carries the marker convention verbatim" \
  "# runner: solo" "$(cat "$T8/tests/aaa-solo.test.sh")"

rm -f "$RR8_MARKS"/solo.ran
RR8_OUT="$( cd "$T8" && \
  RR8_MARKS="$RR8_MARKS" \
  BIONIC_PRESSURE_RING="$RR8_RING" \
  BIONIC_NOW_EPOCH="$RR_NOW" \
  BIONIC_TEST_JOBS_CEILING="2" \
  BIONIC_PROBE_FREE_PCT="44" \
  BIONIC_PROBE_SWAP_PCT="0" \
  BIONIC_PROBE_LOAD_1M="0.1" \
  env "${RR_GATE_ENV[@]}" bash tests/run.sh 2>&1 )"
RR8_RC=$?

expect_eq "8.2 the solo suite really ran (its own marker exists)" "yes" \
  "$([ -f "$RR8_MARKS/solo.ran" ] && echo yes || echo no)"
expect_eq "8.3 the run is green: aaa-solo never shared the CPU with a live sibling" "0" "$RR8_RC"
expect_absent "8.4 …and its own assertion did not fail" \
  "FAIL: aaa-solo never observed a live sibling drive" "$RR8_OUT"
expect_contains "8.5 …the whole tally is four passed, none failed" \
  "Gating: 4 passed, 0 failed" "$RR8_OUT"
# THE ROSTER-ORDER PRINTING IS UNCHANGED (must keep working unchanged): the printed labels
# are still exactly the glob, as a set, solo suite included.
expect_eq "8.6 the printed labels are still exactly the glob (solo suite included)" \
  "$(rr_glob "$T8")" "$(rr_labels "$RR8_OUT")"

# --serial ALREADY runs one at a time in roster order, so the marker changes nothing there —
# proved rather than assumed: the same tree under --serial is green too, aaa-solo included.
rm -f "$RR8_MARKS"/solo.ran
RR8_SERIAL_OUT="$( cd "$T8" && \
  RR8_MARKS="$RR8_MARKS" \
  BIONIC_PRESSURE_RING="$RR8_RING" \
  BIONIC_NOW_EPOCH="$RR_NOW" \
  BIONIC_TEST_JOBS_CEILING="2" \
  BIONIC_PROBE_FREE_PCT="44" \
  BIONIC_PROBE_SWAP_PCT="0" \
  BIONIC_PROBE_LOAD_1M="0.1" \
  env "${RR_GATE_ENV[@]}" bash tests/run.sh --serial 2>&1 )"
RR8_SERIAL_RC=$?
expect_eq "8.7 --serial is unaffected by the marker: still green" "0" "$RR8_SERIAL_RC"
expect_eq "8.8 …and the solo suite still ran under --serial" "yes" \
  "$([ -f "$RR8_MARKS/solo.ran" ] && echo yes || echo no)"

# --dry-run lists a solo suite as such, rather than folding it silently into the width line.
RR8_DRY_OUT="$( cd "$T8" && \
  RR8_MARKS="$RR8_MARKS" \
  BIONIC_PRESSURE_RING="$RR8_RING" \
  BIONIC_NOW_EPOCH="$RR_NOW" \
  BIONIC_TEST_JOBS_CEILING="2" \
  BIONIC_PROBE_FREE_PCT="44" \
  BIONIC_PROBE_SWAP_PCT="0" \
  BIONIC_PROBE_LOAD_1M="0.1" \
  env "${RR_GATE_ENV[@]}" bash tests/run.sh --dry-run 2>&1 )"
expect_contains "8.9 --dry-run still prints the width" "JOBS=2" "$RR8_DRY_OUT"
expect_contains "8.10 …and lists the solo suite by name" "aaa-solo.test.sh" "$RR8_DRY_OUT"
expect_contains "8.11 …labelled solo, not folded silently into the width" "solo" "$RR8_DRY_OUT"
# PAIRED NEGATIVE: a plain sibling is not mislabelled solo.
expect_absent "8.12 …and an ordinary sibling is not listed as solo" "sib-a.test.sh" \
  "$(printf '%s\n' "$RR8_DRY_OUT" | grep -i solo)"

# ============================================================
section "§9 the progress knob: one line per suite as it lands (T7, REQ-9)"
# ============================================================
#
# WHAT IT COVERS. Nothing in a default run prints a verdict until the whole queue
# has drained (tests/run.sh's own drain comment), so a floor run that takes an
# hour is a silent hour: a watcher cannot tell a run that is working from a run
# that is wedged, and a run killed mid-drain leaves nothing behind that names the
# suites that did land. `BIONIC_TEST_PROGRESS` is the opt-in answer, written to
# the same rule `BIONIC_TEST_TIMING` was: a gating run's OUTPUT must not change
# because someone wanted to watch it.
#
# THE FOUR CLAIMS:
#   (a) knob set -> one TAB line per suite, `<UTC>TAB<label>TAB<rc>`, as it lands.
#   (b) a suite whose worker is killed before it writes its verdict contributes no
#       line, while its siblings' lines are all there — the file never names a
#       suite that never finished.
#   (c) knob unset -> not one byte of the report moves, and no file is created.
#   (d) a NESTED `bash tests/run.sh` (four suites in this repo drive one) does not
#       append its scratch labels to the outer watcher's file.
#
# …and one more, which is not about the knob at all: the progress file is the
# first thing in this repo that records COMPLETION order, so it is what finally
# makes the report's ROSTER-order contract falsifiable. §1.4 and §8.6 compare
# sorted sets and would pass an implementation that printed in completion order.

RR9_RING="$TMPROOT/t9-ring"

# rr9_drive <dir> <progress-file-or-empty> — a drive with its own freshly seeded
# pressure ring, so two drives of one tree print the same `samples=` reading and
# can be compared byte for byte. An empty second argument means the knob is not
# in the environment at all, which is the control §9 rests on.
RR9_OUT=""; RR9_RC=0
rr9_drive() {
  local dir="$1" prog="${2:-}"
  printf '%s|44|0|0.1|2\n' "$RR_NOW" > "$RR9_RING"
  if [ -n "$prog" ]; then
    RR9_OUT="$( cd "$dir" && \
      RR_MARKS="$RR_MARKS" \
      BIONIC_PRESSURE_RING="$RR9_RING" \
      BIONIC_NOW_EPOCH="$RR_NOW" \
      BIONIC_TEST_JOBS_CEILING="2" \
      BIONIC_PROBE_FREE_PCT="44" \
      BIONIC_PROBE_SWAP_PCT="0" \
      BIONIC_PROBE_LOAD_1M="0.1" \
      BIONIC_TEST_PROGRESS="$prog" \
      env "${RR_GATE_ENV[@]}" bash tests/run.sh 2>&1 )"
  else
    RR9_OUT="$( cd "$dir" && \
      RR_MARKS="$RR_MARKS" \
      BIONIC_PRESSURE_RING="$RR9_RING" \
      BIONIC_NOW_EPOCH="$RR_NOW" \
      BIONIC_TEST_JOBS_CEILING="2" \
      BIONIC_PROBE_FREE_PCT="44" \
      BIONIC_PROBE_SWAP_PCT="0" \
      BIONIC_PROBE_LOAD_1M="0.1" \
      env "${RR_GATE_ENV[@]}" bash tests/run.sh 2>&1 )"
  fi
  RR9_RC=$?
}

# rr9_norm <report> — the report with its one per-run nonce masked: the
# interpreter pin's own `mktemp -d` path, which is a fresh directory on every
# invocation and is no product of this knob. Everything else is compared as it
# was printed.
rr9_norm() { printf '%s\n' "$1" | sed -e 's|path=[^ ]*|path=PIN|g'; }

# rr9_shaped <file> — how many of the file's lines carry the pinned progress
# shape: exactly three TAB fields, a UTC stamp, a suite label, a numeric rc.
rr9_shaped() {
  LC_ALL=C awk -F'\t' '
    NF == 3 &&
    $1 ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z$/ &&
    $2 ~ /\.test\.sh$/ &&
    $3 ~ /^[0-9]+$/ { n++ }
    END { print n+0 }' "$1" 2>/dev/null
}

# rr9_prog_labels <file> — the labels the progress file recorded, sorted.
rr9_prog_labels() { LC_ALL=C awk -F'\t' '{ print $2 }' "$1" 2>/dev/null | sort -u; }

# rr_labels_ordered <output> — the labels the runner printed, IN PRINTED ORDER.
# rr_labels sorts, which is what makes §1.4 and §8.6 set comparisons; the roster
# -order claim needs the sequence.
rr_labels_ordered() {
  printf '%s\n' "$1" | sed -n 's/^  \([A-Za-z0-9_.-]*\.test\.sh\) .*/\1/p'
}

# ---- (a) the knob set: one shaped line per suite ---------------------------
T9="$TMPROOT/t9"
rr_tree "$T9"
for RR_N in alpha bravo charlie; do rr_stub "$T9" "$RR_N"; done
P9="$TMPROOT/t9.progress.tsv"
rm -f "$P9"
rr9_drive "$T9" "$P9"

expect_eq "9.1 the run is green over the three suites" "0" "$RR9_RC"
expect_eq "9.2 the knob created the progress file" "yes" \
  "$([ -f "$P9" ] && echo yes || echo no)"
expect_eq "9.3 it holds one line per suite, no more" "3" \
  "$(LC_ALL=C awk 'END { print NR+0 }' "$P9")"
expect_eq "9.4 …and every one of those lines carries the pinned shape" "3" \
  "$(rr9_shaped "$P9")"
expect_eq "9.5 …naming exactly the suites in the glob, as a set" \
  "$(rr_glob "$T9")" "$(rr9_prog_labels "$P9")"
expect_eq "9.6 …each with the rc its suite actually exited with (all green)" "3" \
  "$(LC_ALL=C awk -F'\t' '$3 == "0" { n++ } END { print n+0 }' "$P9")"
# PAIRED NEGATIVE for 9.4: the shape check counts zero over a file that holds a
# line of the wrong shape, so 9.4's three is three shaped lines and not three
# lines of anything at all.
printf 'not a progress line\n' > "$TMPROOT/t9-bogus.tsv"
expect_eq "9.7 …and that shape check is not vacuous (a malformed file counts zero)" "0" \
  "$(rr9_shaped "$TMPROOT/t9-bogus.tsv")"

# ---- (c) the knob unset: no file, and not one byte of the report -----------
P9U="$TMPROOT/t9-unset.progress.tsv"
rm -f "$P9U"
RR9_WITH="$RR9_OUT"
rr9_drive "$T9" ""
expect_eq "9.8 the unset run is green too" "0" "$RR9_RC"
expect_eq "9.9 …and wrote no progress file anywhere" "no" \
  "$([ -f "$P9U" ] && echo yes || echo no)"
expect_eq "9.10 …and its report is the watched run's, byte for byte" \
  "$(rr9_norm "$RR9_WITH")" "$(rr9_norm "$RR9_OUT")"
# PAIRED POSITIVE for 9.10: the thing compared is a real report, not two empties.
expect_contains "9.11 …and that report is a real one (the tally is in it)" \
  "Gating: 3 passed, 0 failed" "$RR9_OUT"
expect_absent "9.12 …and no run of either kind prints a progress path" \
  "$P9" "$RR9_WITH"

# ---- (b) a suite whose worker dies contributes no line ---------------------
#
# The shape that matters is a verdict that never reached disk, which is the
# worker dying — not the suite exiting non-zero. The planted suite kills its own
# parent (the `--one` worker) with SIGKILL, so no `.rc` is ever written and the
# runner reports it KILLED. It is marked `# runner: solo` so it drains through
# the solo loop rather than under xargs, which abandons a queue when a child dies
# by signal and would take its siblings' evidence with it.
T9K="$TMPROOT/t9k"
rr_tree "$T9K"
for RR_N in k-one k-two; do rr_stub "$T9K" "$RR_N"; done
cat > "$T9K/tests/zzz-killed.test.sh" <<'RR9_KILLED'
#!/bin/bash
# runner: solo
set -uo pipefail
. "$(dirname "$0")/lib/assert.sh"
kill -9 "$PPID"
sleep 0.5
section "zzz-killed"
expect_eq "unreachable: the worker died before this suite could finish" "x" "x"
finish
RR9_KILLED
P9K="$TMPROOT/t9k.progress.tsv"
rm -f "$P9K"
rr9_drive "$T9K" "$P9K"

expect_contains "9.13 the runner reports the suite whose worker died as KILLED" \
  "✗ KILLED (no exit status recorded)" "$RR9_OUT"
expect_eq "9.14 …and the run is red, as it must be" "1" "$RR9_RC"
expect_eq "9.15 the progress file names the two suites that DID land" \
  "$(printf 'k-one.test.sh\nk-two.test.sh\n')" "$(rr9_prog_labels "$P9K")"
expect_absent "9.16 …and never names the one that never finished" \
  "zzz-killed.test.sh" "$(cat "$P9K")"
expect_eq "9.17 …so the file holds two lines, not three" "2" \
  "$(LC_ALL=C awk 'END { print NR+0 }' "$P9K")"
# PAIRED: the killed suite IS in the report, so 9.16 is a missing progress line
# and not a suite the roster never carried.
expect_contains "9.18 …while the report still carries it, in roster order" \
  "zzz-killed.test.sh" "$RR9_OUT"

# ---- (d) a nested run does not pollute the outer watcher's file ------------
T9N_INNER="$TMPROOT/t9n-inner"
rr_tree "$T9N_INNER"
rr_stub "$T9N_INNER" "zin-inner"
export RR9_INNER="$T9N_INNER"

T9N="$TMPROOT/t9n"
rr_tree "$T9N"
rr_stub "$T9N" "n-plain"
cat > "$T9N/tests/n-outer.test.sh" <<'RR9_NESTED'
#!/bin/bash
set -uo pipefail
. "$(dirname "$0")/lib/assert.sh"
: > "$RR_MARKS/n-outer.ran"
section "n-outer"
( cd "$RR9_INNER" && bash tests/run.sh >/dev/null 2>&1 )
expect_eq "the nested run over the inner tree is green" "0" "$?"
finish
RR9_NESTED
P9N="$TMPROOT/t9n.progress.tsv"
rm -f "$P9N" "$RR_MARKS/zin-inner.ran"
rr9_drive "$T9N" "$P9N"

expect_eq "9.19 the outer run is green, nested drive and all" "0" "$RR9_RC"
# PAIRED POSITIVE, and the whole point of it: the inner suite really ran. Its
# absence from the outer file below is a knob that did not leak, not a nested run
# that never happened.
expect_eq "9.20 the nested run really ran its own suite" "yes" \
  "$([ -f "$RR_MARKS/zin-inner.ran" ] && echo yes || echo no)"
expect_eq "9.21 the outer file names the outer tree's two suites" \
  "$(printf 'n-outer.test.sh\nn-plain.test.sh\n')" "$(rr9_prog_labels "$P9N")"
expect_absent "9.22 …and carries no label from the nested tree" \
  "zin-inner.test.sh" "$(cat "$P9N")"
expect_eq "9.23 …so it holds two lines, not three" "2" \
  "$(LC_ALL=C awk 'END { print NR+0 }' "$P9N")"

# ---- the report is in ROSTER order, and now that is falsifiable ------------
#
# The runner's drain comment says a reader comparing two runs is comparing
# rosters, not schedules. Until there was a progress file nothing in this repo
# could tell the two apart: §1.4 and §8.6 sort both sides. Here the slow suite is
# alphabetically FIRST and lands LAST, so the two orders genuinely disagree and
# the report has to pick the roster's.
T9O="$TMPROOT/t9o"
rr_tree "$T9O"
for RR_N in mmm-mid zzz-fast; do rr_stub "$T9O" "$RR_N"; done
{ printf '#!/bin/bash\n'
  printf 'set -uo pipefail\n'
  printf '. "$(dirname "$0")/lib/assert.sh"\n'
  printf 'sleep 2\n'
  printf 'section "aaa-slow"\n'
  printf 'expect_eq "aaa-slow ran" "x" "x"\n'
  printf 'finish\n'
} > "$T9O/tests/aaa-slow.test.sh"
P9O="$TMPROOT/t9o.progress.tsv"
rm -f "$P9O"
rr9_drive "$T9O" "$P9O"

expect_eq "9.24 the run is green over the three" "0" "$RR9_RC"
expect_eq "9.25 the report prints the roster's ORDER, not a sorted set of it" \
  "$(rr_glob "$T9O")" "$(rr_labels_ordered "$RR9_OUT")"
expect_eq "9.26 …and completion order really did disagree: the slow suite landed LAST" \
  "aaa-slow.test.sh" "$(LC_ALL=C awk -F'\t' 'END { print $2 }' "$P9O")"
expect_eq "9.27 …while the report printed that same suite FIRST" \
  "aaa-slow.test.sh" "$(rr_labels_ordered "$RR9_OUT" | sed -n '1p')"


# ============================================================
section "§10 the header names the head and the dirt of the tree under test (wave-26 T4; D5)"
# ============================================================
#
# A run's verdict is a claim about one state of the code, so the header says which:
# `head=<40-hex> dirty=<porcelain lines>` for the tree the runner cd's into. The scratch tree
# is made a repository with one commit and then dirtied by a file it does not track; the
# expected values are git's own answers for that tree, taken by this suite, not counts
# written down here. A tree that is no repository says so rather than inventing a head.
T10="$TMPROOT/t10"
rr_tree "$T10"
rr_stub "$T10" "h-one"
( cd "$T10" && git init -q . && git add -A \
  && git -c user.name=fixture -c user.email=fixture@example.invalid -c commit.gpgsign=false \
       -c core.hooksPath=/dev/null commit -q -m tree ) >/dev/null 2>&1
printf 'untracked\n' > "$T10/dirt.txt"
T10_HEAD="$(git -C "$T10" rev-parse HEAD 2>/dev/null)"
T10_DIRTY="$(git -C "$T10" status --porcelain 2>/dev/null | awk 'END { print NR+0 }')"
expect_regex "10.0 precondition: the scratch tree has a 40-hex head" '^[0-9a-f]{40}$' "$T10_HEAD"
expect_true "10.0b precondition: …and git counts it dirty" test "$T10_DIRTY" -gt 0
rr_drive "$T10"
expect_eq "10.1 the run over the scratch tree is green" "0" "$RR_RC"
expect_eq "10.2 the header carries one head= line, naming that tree's head and dirt" \
  "head=${T10_HEAD} dirty=${T10_DIRTY}" "$(printf '%s\n' "$RR_OUT" | /usr/bin/grep '^head=')"
expect_true "10.3 …and it sits in the header, before the first suite's verdict" \
  test "$(printf '%s\n' "$RR_OUT" | awk '/^head=/ { print NR; exit }')" -lt \
       "$(printf '%s\n' "$RR_OUT" | awk '/h-one\.test\.sh/ { print NR; exit }')"
T10N="$TMPROOT/t10n"
rr_tree "$T10N"
rr_stub "$T10N" "h-two"
rr_drive "$T10N"
expect_eq "10.4 a tree that is no repository names no head" "head=none dirty=none" \
  "$(printf '%s\n' "$RR_OUT" | /usr/bin/grep '^head=')"

# ============================================================
section "§ASK each suite of a run asks the gate for itself; the runner holds nothing (T12; AC-2.12 runner half, D13)"
# ============================================================
#
# THE CLAIM. Before wave-28 a run started through the Bash tool held ONE booking for the whole
# run and handed it to every worker, so up to eight suites ran on one place. Now the runner
# asks nothing for itself: each `--one` worker asks `gate_ask work <suite file name>` for its
# own suite, runs it with BIONIC_GATE_ADMIT naming that request, and ends it with the suite's
# code; a solo suite asks `whole`; --serial asks per suite too. The store is this section's own
# (BIONIC_GATE_DIR under the suite's mktemp root) and the memory reading is pinned low, so no
# drive reads or writes the machine's real gate.
TA="$TMPROOT/ask"; RA_GATE="$TMPROOT/ask-gate"
rr_tree "$TA"
ra_stub() {  # <name> <solo yes|no> — a green suite that records the admission it ran under
  { printf '#!/bin/bash\n'
    [ "$2" = yes ] && printf '# runner: solo\n'
    printf 'set -uo pipefail\n'
    printf '. "$(dirname "$0")/lib/assert.sh"\n'
    printf 'printf "%%s\\n" "${BIONIC_GATE_ADMIT:-none}" > "$RR_MARKS/%s.admit"\n' "$1"
    printf 'section "%s"\n' "$1"
    printf 'expect_eq "%s ran" "x" "x"\n' "$1"
    printf 'finish\n'
  } > "$TA/tests/$1.test.sh"
}
for _ra in ask-a ask-b ask-c; do ra_stub "$_ra" no; done
ra_stub aaa-ask-solo yes
ra_drive() {  # [mode] — the scratch runner on this section's own store; RR_OUT, RR_RC
  RR_OUT="$( cd "$TA" && RR_MARKS="$RR_MARKS" BIONIC_PRESSURE_RING="$TMPROOT/ask-ring" \
    BIONIC_NOW_EPOCH="$RR_NOW" BIONIC_TEST_JOBS_CEILING=2 BIONIC_PROBE_FREE_PCT=44 \
    BIONIC_PROBE_SWAP_PCT=0 BIONIC_PROBE_LOAD_1M=0.1 \
    env "${RR_GATE_ENV[@]}" BIONIC_GATE_DIR="$RA_GATE" bash tests/run.sh ${1:+"$1"} 2>&1 )"
  RR_RC=$?
}
ra_reqs() {  # one line per request in the store: <key> <kind> <rc>, sorted
  local f
  for f in "$RA_GATE"/requests/[0-9]*; do
    [ -f "$f" ] || continue
    printf '%s %s %s\n' "$(sed -n 's/^key=//p' "$f" | tail -n 1)" "$(sed -n 's/^kind=//p' "$f" | tail -n 1)" \
      "$(sed -n 's/^rc=//p' "$f" | tail -n 1)"
  done | sort
}
ra_id_of() {  # <key> — the id of the request with that key
  grep -l "^key=$1\$" "$RA_GATE"/requests/[0-9]* 2>/dev/null | head -n 1 | sed 's#.*/##'
}
rm -rf "$RA_GATE"; rm -f "$RR_MARKS"/*.admit
ra_drive
expect_eq "ASK.1 the run is green" "0" "$RR_RC"
expect_eq "ASK.2 one request per suite, keyed by the suite's file name, each ended with its code" \
  "aaa-ask-solo.test.sh whole 0
ask-a.test.sh work 0
ask-b.test.sh work 0
ask-c.test.sh work 0" "$(ra_reqs)"
expect_absent "ASK.3 …and none keyed by the runner: the runner holds nothing" "run.sh" "$(ra_reqs)"
expect_eq "ASK.4 the three batch suites were held by three different workers" "3" \
  "$(for _ra in ask-a ask-b ask-c; do sed -n 's/^holder=\([0-9]*\):.*/\1/p' "$RA_GATE/requests/$(ra_id_of "$_ra.test.sh")" 2>/dev/null | tail -n 1; done | sort -u | grep -c .)"
expect_eq "ASK.5 each suite ran under its own request (ask-a)" "$(ra_id_of ask-a.test.sh)" \
  "$(cat "$RR_MARKS/ask-a.admit" 2>/dev/null)"
expect_eq "ASK.6 …(the solo suite, under its whole request)" "$(ra_id_of aaa-ask-solo.test.sh)" \
  "$(cat "$RR_MARKS/aaa-ask-solo.admit" 2>/dev/null)"
rm -rf "$RA_GATE"; rm -f "$RR_MARKS"/*.admit
ra_drive --serial
expect_eq "ASK.7 --serial is green" "0" "$RR_RC"
expect_eq "ASK.8 --serial asks per suite too, each as work, each ended" \
  "aaa-ask-solo.test.sh work 0
ask-a.test.sh work 0
ask-b.test.sh work 0
ask-c.test.sh work 0" "$(ra_reqs)"
expect_eq "ASK.9 …and each suite ran under its own request (ask-b)" "$(ra_id_of ask-b.test.sh)" \
  "$(cat "$RR_MARKS/ask-b.admit" 2>/dev/null)"
# Through the shim, as the wall runs it: the shim takes no number for the runner.
rm -rf "$RA_GATE"; rm -f "$RR_MARKS"/*.admit
RR_OUT="$( cd "$TA" && RR_MARKS="$RR_MARKS" BIONIC_PRESSURE_RING="$TMPROOT/ask-ring" \
  BIONIC_NOW_EPOCH="$RR_NOW" BIONIC_TEST_JOBS_CEILING=2 BIONIC_PROBE_FREE_PCT=44 \
  BIONIC_PROBE_SWAP_PCT=0 BIONIC_PROBE_LOAD_1M=0.1 \
  env "${RR_GATE_ENV[@]}" BIONIC_GATE_DIR="$RA_GATE" \
  bash "$REPO/payload/scripts/booked.sh" --agent ask --max-wait 60 --suites run.sh -- 'bash tests/run.sh' 2>&1 )"
RR_RC=$?
expect_eq "ASK.10 a run wrapped in the shim is green" "0" "$RR_RC"
expect_eq "ASK.11 …the shim took no number, and each suite asked for itself" \
  "aaa-ask-solo.test.sh whole 0
ask-a.test.sh work 0
ask-b.test.sh work 0
ask-c.test.sh work 0" "$(ra_reqs)"

# ============================================================
section "§11 NESTED — a solo suite asks for the whole machine; a nested run never waits on its parent (wave-26 T8, AC-6.4; the gate since wave-28 T12)"
# ============================================================
#
# WHAT IT COVERS. A `# runner: solo` suite used to be held out of the run's own batch and
# nothing more: any other run on the machine could share its drive. The runner now asks the
# gate for the whole machine before each solo suite (`gate_ask whole <suite>`, admitted only
# while nothing else admitted is unfinished, and nothing else admitted while it holds), waits
# for a settled load, and ends the request after. The claims, each against this suite's store:
#
#   (a) NESTED. An outer run inside a booked command completes, and so do the two nested runs
#       it drives: one from inside its solo suite, which runs under the outer suite's whole
#       admission (the gate believes it for a descendant of its holder) with the load raised,
#       and so neither settles nor voids; and one from its batch, whose solo suite runs under
#       the batch suite's work admission. Neither takes a number of its own.
#   (b) the mutation control: the same fixture with the runner's nested-whole check removed
#       makes the inner run settle on the raised load until its ceiling, and void.
#   (c) the ask really waits: a foreign admitted run delays the solo suite until its holder
#       is gone, and the gate says the request waits.
#   (d) VOID: a run during which the load rose is re-run; still disturbed after two
#       retries, a suite that passed is reported void, never failed. One disturbed run
#       followed by a clean one is an ordinary pass.
#   (e) ITS OWN ADMISSION: a solo suite runs with BIONIC_GATE_ADMIT naming its whole request,
#       admitted and unfinished while it runs, booked run or not; and two booked runs that
#       each reach their solo suite together both complete, the second waiting for the first.
#   (f) ONE CEILING (wave-26 T26; review 4 F3): the settle and every retry of one solo suite
#       give up at one deadline, counted from the admission; a retry the ceiling has no room
#       for is not run at all.
#   (g) OWN LOAD (review 4 F4): the check after the run leaves out the suite's own share of
#       the load, measured from the CPU its worker used; its own load alone never voids it.
#   (h) A STORE THAT CANNOT BE WRITTEN (review 4 F5): the suite is reported VOID at once,
#       and the reason names the store.
#   (i) A VOID SUITE THAT FAILED IS A FAILURE (wave-26 T43; review 8 F1): on every path that
#       can void a suite, a suite whose last run failed fails the run, is counted once in the
#       fail tally, and carries its void reason on its failure line.
#   (j) A VOID SUITE LEAVES NO TIMING ROW (wave-26 T48; review 11 N1): the file the timing knob
#       names holds measurements only, so a suite whose timing was not measured, passed or
#       failed, has no row in it, and a suite timed in the same run still does.

RRN_BOOKED="$REPO/payload/scripts/booked.sh"
expect_true "11.0 the shim the outer run is booked through exists" test -f "$RRN_BOOKED"

RRN="$TMPROOT/n"
RRN_MARKS="$RRN/marks"; RRN_GATE="$RRN/gate"; RRN_LOAD="$RRN/load"
mkdir -p "$RRN_MARKS"
printf '0\n' > "$RRN_LOAD"

# rrn_suite — a suite file: the solo marker verbatim when asked for, the framework, the
# body given, one trivial row.
rrn_suite() {  # <file> <solo yes|no> <name> <body>
  { printf '#!/bin/bash\n'
    [ "$2" = yes ] && printf '# runner: solo\n'
    printf 'set -uo pipefail\n'
    printf '. "$(dirname "$0")/lib/assert.sh"\n'
    printf '%s\n' "$4"
    printf 'section "%s"\n' "$3"
    printf 'expect_eq "%s ran" "x" "x"\n' "$3"
    printf 'finish\n'
  } > "$1"
}

# What a suite records about the admission it runs under: the request's kind and key
# (`none` when it inherited none), and its id with `held` while that request is admitted and
# unfinished.
RRN_RECORD='a="${BIONIC_GATE_ADMIT:-}"; w=none; f="$RRN_GATE/requests/$a"
[ -n "$a" ] && [ -f "$f" ] && w="$(sed -n "s/^kind=//p" "$f" | tail -n 1) $(sed -n "s/^key=//p" "$f" | tail -n 1)"
printf "%s\n" "$w" > "$RRN_MARKS/$RRN_WHO.what"
h=gone; [ -n "$a" ] && grep -q "^admitted=" "$f" 2>/dev/null && ! grep -q "^ended=" "$f" 2>/dev/null && h=held
printf "%s %s\n" "$a" "$h" > "$RRN_MARKS/$RRN_WHO.place"'

# The inner tree: one solo suite, recording under the name its caller hands down.
TNI="$RRN/inner"
rr_tree "$TNI"
rrn_suite "$TNI/tests/aaa-inner.test.sh" yes aaa-inner "RRN_WHO=\"inner-\$RRN_TAG\"
$RRN_RECORD"

# The outer tree: a solo suite that records its hold and drives the inner run, and a batch
# suite that drives the inner run too.
rrn_outer_tree() {  # <dir>
  rr_tree "$1"
  rrn_suite "$1/tests/aaa-nest.test.sh" yes aaa-nest "RRN_WHO=outer
$RRN_RECORD
printf '99\n' > \"\$RRN_LOAD\"
( cd \"\$RRN_INNER\" && RRN_TAG=solo bash tests/run.sh ) > \"\$RRN_MARKS/inner-solo.out\" 2>&1
printf '%s\n' \"\$?\" > \"\$RRN_MARKS/inner-solo.rc\"
printf '0\n' > \"\$RRN_LOAD\""
  rrn_suite "$1/tests/n-batch.test.sh" no n-batch \
"( cd \"\$RRN_INNER\" && RRN_TAG=batch bash tests/run.sh ) > \"\$RRN_MARKS/inner-batch.out\" 2>&1
printf '%s\n' \"\$?\" > \"\$RRN_MARKS/inner-batch.rc\""
}
TNO="$RRN/outer"
rrn_outer_tree "$TNO"

# rrn_drive <dir> <ceiling> <command...> — the drive, with this section's store, a short poll,
# the settle's ceiling, the load reading this section controls, and no inherited admission.
RRN_OUT=""; RRN_RC=0
rrn_drive() {
  local dir="$1" max="$2"; shift 2
  RRN_OUT="$( cd "$dir" && \
    RR_MARKS="$RR_MARKS" RRN_MARKS="$RRN_MARKS" RRN_GATE="$RRN_GATE" RRN_INNER="${RRN_INNER_TREE:-$TNI}" \
    RRN_LOAD="$RRN_LOAD" RRN_FOREIGN="${RRN_FOREIGN:-}" RRN_VOID="${RRN_VOID:-}" \
    BIONIC_PRESSURE_RING="$TMPROOT/n-ring" \
    BIONIC_NOW_EPOCH="$RR_NOW" \
    BIONIC_TEST_JOBS_CEILING="2" \
    BIONIC_PROBE_FREE_PCT="44" \
    BIONIC_PROBE_SWAP_PCT="0" \
    BIONIC_PROBE_LOAD_1M="0.1" \
    env "${RR_GATE_ENV[@]}" BIONIC_GATE_DIR="$RRN_GATE" BIONIC_SETTLE_MAX_WAIT="$max" \
      BIONIC_LOAD_NOW_FILE="$RRN_LOAD" "$@" 2>&1 )"
  RRN_RC=$?
}
# rrn_plant <id> <holder pid> — a foreign run the gate admitted, held by a live process
rrn_plant() {
  local st
  st="$(LC_ALL=C TZ=UTC0 ps -o lstart= -p "$2" 2>/dev/null | awk '{ $1 = $1; print }')"
  mkdir -p "$RRN_GATE/requests"
  printf 'key=foreign.test.sh\nkind=work\nwho=foreign:w\ntree=/\nasked=1\nholder=%s:%s\nadmitted=1\npromise=1:0.1:10\n' \
    "$2" "$st" > "$RRN_GATE/requests/$1"
}
rrn_unended() {  # the requests admitted and not ended, by file name
  local f
  for f in "$RRN_GATE"/requests/[0-9]*; do
    [ -f "$f" ] || continue
    grep -q '^admitted=' "$f" && ! grep -q '^ended=' "$f" && printf '%s ' "${f##*/}"
  done
}
rrn_ids_of() {  # <key> — the ids of the requests with that key
  grep -l "^key=$1\$" "$RRN_GATE"/requests/[0-9]* 2>/dev/null | sed 's#.*/##' | tr '\n' ' '
}
rrn_read() { cat "$RRN_MARKS/$1" 2>/dev/null; }

# ---- (a) the outer run inside a booked command -----------------------------
# The shim is handed `--suites run.sh`, as the wall names a runner: it asks nothing for it.
rm -f "$RRN_MARKS"/*; rm -rf "$RRN_GATE"; printf '0\n' > "$RRN_LOAD"
rrn_drive "$TNO" 4 bash "$RRN_BOOKED" --suites run.sh -- 'bash tests/run.sh'
expect_eq "11.1 the booked outer run completes green" "0" "$RRN_RC"
expect_eq "11.2 its solo suite ran under its own whole request" \
  "whole aaa-nest.test.sh" "$(rrn_read outer.what)"
expect_eq "11.3 the run nested in the solo suite completes green" "0" "$(rrn_read inner-solo.rc)"
expect_contains "11.4 …with a real tally (the nested run happened)" "Gating:" "$(rrn_read inner-solo.out)"
expect_absent "11.5 …and it never waited at the gate" "waits for its turn" "$(rrn_read inner-solo.out)"
expect_absent "11.6 …nor reported a void, though the load was raised while it ran" "VOID" "$(rrn_read inner-solo.out)"
expect_eq "11.7 the nested run's solo suite ran under the outer suite's whole admission" \
  "whole aaa-nest.test.sh" "$(rrn_read inner-solo.what)"
expect_eq "11.8 …and took no number of its own: no request names the inner suite" "" \
  "$(rrn_ids_of aaa-inner.test.sh)"
expect_eq "11.9 the run nested in the batch completes green" "0" "$(rrn_read inner-batch.rc)"
expect_contains "11.10 …with a real tally" "Gating:" "$(rrn_read inner-batch.out)"
expect_absent "11.11 …and it never waited at the gate" "waits for its turn" "$(rrn_read inner-batch.out)"
expect_eq "11.12 …its solo suite ran under the batch suite's work admission it was started from" \
  "work n-batch.test.sh" "$(rrn_read inner-batch.what)"
expect_nonempty "11.13 the store was used: the outer suites' own requests are there" \
  "$(rrn_ids_of aaa-nest.test.sh)$(rrn_ids_of n-batch.test.sh)"
expect_eq "11.14 …and every request was ended" "" "$(rrn_unended)"

# ---- (b) the mutation control: no nested-whole check -----------------------
# The check lives in the NESTED runner, the one whose solo suite inherits the whole admission:
# the inner tree's runner is the doctored copy, the outer run is the shipped one.
TNIM="$RRN/inner-mut"
rr_tree "$TNIM"
cp "$TNI/tests/aaa-inner.test.sh" "$TNIM/tests/aaa-inner.test.sh"
RRN_ANCHOR='2>/dev/null | tail -n 1)" = whole ]; then'
sed 's/2>\/dev\/null | tail -n 1)" = whole \]; then/2>\/dev\/null | tail -n 1)" = never ]; then/' \
  "$RUNNER" > "$TNIM/tests/run.sh"
expect_eq "11.15 meta: the shipped runner carries the nested-whole check once" "1" \
  "$(grep -cF "$RRN_ANCHOR" "$RUNNER")"
expect_eq "11.16 meta: …and the doctored copy does not" "0" \
  "$(grep -cF "$RRN_ANCHOR" "$TNIM/tests/run.sh")"
expect_true "11.17 meta: the doctored copy still parses" bash -n "$TNIM/tests/run.sh"
rm -f "$RRN_MARKS"/*; rm -rf "$RRN_GATE"; printf '0\n' > "$RRN_LOAD"
RRN_INNER_TREE="$TNIM" rrn_drive "$TNO" 2 bash "$RRN_BOOKED" --suites run.sh -- 'bash tests/run.sh'
expect_eq "11.17b the doctored drive still completes (its outer suites ran)" "0" "$(rrn_read inner-solo.rc)"
expect_contains "11.18 without the check the nested solo suite settles on the raised load and voids" \
  "VOID" "$(rrn_read inner-solo.out)"
expect_contains "11.19 …because the load never settled: the check is the rule" \
  "never settled" "$(rrn_read inner-solo.out)"

# ---- (c) a foreign admitted run delays the solo suite ----------------------
TNF="$RRN/foreign"
rr_tree "$TNF"
rrn_suite "$TNF/tests/aaa-timed.test.sh" yes aaa-timed \
'if kill -0 "$RRN_FOREIGN" 2>/dev/null; then s=alive; else s=gone; fi
printf "%s\n" "$s" > "$RRN_MARKS/foreign.state"'
rm -f "$RRN_MARKS"/*; rm -rf "$RRN_GATE"; printf '0\n' > "$RRN_LOAD"
# THE HOLDER IS NOT THIS SHELL'S CHILD: a killed child stays a zombie until it is reaped, and
# `kill -0` reads a zombie as alive. Started from a subshell that exits at once, it is
# reparented and reaped by the system the moment it dies.
RRN_FPID="$( ( sleep 30 >/dev/null 2>&1 & printf '%s' "$!" ) )"
rrn_plant 900 "$RRN_FPID"
( sleep 4; kill "$RRN_FPID" 2>/dev/null ) &
RRN_KILLER=$!
RRN_FOREIGN="$RRN_FPID"
rrn_drive "$TNF" 15 bash tests/run.sh
RRN_FOREIGN=""
kill "$RRN_FPID" "$RRN_KILLER" 2>/dev/null; wait "$RRN_KILLER" 2>/dev/null
expect_eq "11.20 the run with a foreign admitted run completes green" "0" "$RRN_RC"
expect_eq "11.21 the solo suite started only once the foreign holder was gone" "gone" \
  "$(rrn_read foreign.state)"
expect_contains "11.22 …and the gate said its whole request waited" \
  "(whole aaa-timed.test.sh) waits for its turn and room" "$RRN_OUT"

# ---- (d) VOID: the load rose during the timing run -------------------------
# The suite raises the load reading during its run and a background line lowers it three
# seconds later, so the check after the run sees the rise and the next try settles within
# the ten-second wait. One second was too short on a loaded machine: the reading was back
# down before the check, and the retry never happened.
TNV="$RRN/void"
rr_tree "$TNV"
rr_stub "$TNV" "v-plain"
rrn_suite "$TNV/tests/aaa-void.test.sh" yes aaa-void \
'printf "run\n" >> "$RRN_MARKS/void.runs"
n="$(awk "END { print NR + 0 }" "$RRN_MARKS/void.runs")"
if [ "$RRN_VOID" = stuck ]; then
  printf "99\n" > "$RRN_LOAD"
elif [ "$RRN_VOID" = always ] || [ "$n" -eq 1 ]; then
  printf "99\n" > "$RRN_LOAD"
  ( sleep 3; printf "0\n" > "$RRN_LOAD" ) >/dev/null 2>&1 &
fi'
rrn_void_runs() { awk 'END { print NR + 0 }' "$RRN_MARKS/void.runs" 2>/dev/null || echo 0; }
rrn_line() { printf '%s\n' "$RRN_OUT" | grep -F "  $1 "; }

rm -f "$RRN_MARKS"/*; rm -rf "$RRN_GATE"; printf '0\n' > "$RRN_LOAD"
RRN_VOID=always; rrn_drive "$TNV" 10 bash tests/run.sh
RRN_VOID_ALWAYS_OUT="$RRN_OUT"
expect_eq "11.23 a suite disturbed on every try does not fail the run" "0" "$RRN_RC"
expect_true "11.24 …it was re-run" test "$(rrn_void_runs)" -ge 2
expect_true "11.25 …and the retries stop (at most the first run and two more)" test "$(rrn_void_runs)" -le 3
expect_contains "11.26 its verdict line reads VOID" "VOID" "$(rrn_line aaa-void.test.sh)"
expect_absent "11.27 …not FAIL" "FAIL" "$(rrn_line aaa-void.test.sh)"
expect_contains "11.28 the summary names it under Void:" "aaa-void.test.sh" \
  "$(printf '%s\n' "$RRN_OUT" | sed -n '/^Void:/,$p')"
expect_absent "11.29 …and nothing is listed under Failed:" "Failed:" "$RRN_OUT"
expect_absent "11.30 …and the run does not call itself all green" "All gating suites green" "$RRN_OUT"

rm -f "$RRN_MARKS"/*; rm -rf "$RRN_GATE"; printf '0\n' > "$RRN_LOAD"
RRN_VOID=once; rrn_drive "$TNV" 10 bash tests/run.sh
expect_eq "11.31 a suite disturbed once and clean on the retry: the run is green" "0" "$RRN_RC"
expect_true "11.32 …it was re-run" test "$(rrn_void_runs)" -ge 2
expect_contains "11.33 …and its verdict line reads PASS" "PASS" "$(rrn_line aaa-void.test.sh)"
expect_absent "11.34 …with no Void: summary" "Void:" "$RRN_OUT"
expect_contains "11.35 …and the retry was said on the way" "aaa-void.test.sh: the load rose" "$RRN_OUT"
expect_contains "11.35b …as a retry, not a give-up" "retrying (1 of 2)" "$RRN_OUT"
expect_contains "11.36 the always-disturbed run printed a Void: summary (11.34 is not vacuous)" \
  "Void:" "$RRN_VOID_ALWAYS_OUT"

# ---- (e) its own admission --------------------------------------------------
# The solo launch hands its suite BIONIC_GATE_ADMIT naming the whole request the runner holds,
# whether the run was booked or not.
rm -f "$RRN_MARKS"/*; rm -rf "$RRN_GATE"; printf '0\n' > "$RRN_LOAD"
rrn_drive "$TNO" 4 bash tests/run.sh
expect_eq "11.37 an unbooked run completes green" "0" "$RRN_RC"
expect_eq "11.38 …its solo suite ran under a whole request for it" "whole aaa-nest.test.sh" "$(rrn_read outer.what)"
expect_eq "11.39 …named in BIONIC_GATE_ADMIT, admitted and unfinished while the suite ran" \
  "$(rrn_ids_of aaa-nest.test.sh | tr -d ' ')held" "$(rrn_read outer.place | tr -d ' ')"
rm -f "$RRN_MARKS"/*; rm -rf "$RRN_GATE"
rrn_drive "$TNO" 4 bash "$RRN_BOOKED" --suites run.sh -- 'bash tests/run.sh'
expect_eq "11.40 a booked run completes green" "0" "$RRN_RC"
expect_eq "11.41 …and its solo suite ran under its own whole request too" \
  "$(rrn_ids_of aaa-nest.test.sh | tr -d ' ')held" "$(rrn_read outer.place | tr -d ' ')"

# Two booked runs, each with a solo suite that holds the machine for three seconds: the second
# whole request waits for the first to end, and both complete.
rrn_pair_tree() {  # <dir> <who>
  rr_tree "$1"
  rrn_suite "$1/tests/aaa-pair.test.sh" yes aaa-pair "RRN_WHO=$2
$RRN_RECORD
sleep 3"
}
rrn_pair_tree "$RRN/pair-a" pair-a
rrn_pair_tree "$RRN/pair-b" pair-b
rm -f "$RRN_MARKS"/*; rm -rf "$RRN_GATE"
for _w in a b; do
  ( rrn_drive "$RRN/pair-$_w" 20 bash "$RRN_BOOKED" --agent "pair-$_w" --suites run.sh -- 'bash tests/run.sh'
    printf '%s\n' "$RRN_OUT" > "$RRN_MARKS/pair-$_w.out"
    printf '%s\n' "$RRN_RC" > "$RRN_MARKS/pair-$_w.rc" ) &
done
wait
expect_eq "11.42 two booked runs asking for the whole machine together: the first completes green" \
  "0" "$(rrn_read pair-a.rc)"
expect_eq "11.43 …and so does the second" "0" "$(rrn_read pair-b.rc)"
expect_absent "11.44 …neither voided" "VOID" "$(rrn_read pair-a.out; rrn_read pair-b.out)"
expect_contains "11.45 …and they really met: one whole request waited for the other" \
  "waits for its turn and room" "$(rrn_read pair-a.out; rrn_read pair-b.out)"
expect_contains "11.46 each solo suite ran under its own held whole request (a)" " held" "$(rrn_read pair-a.place)"
expect_contains "11.47 …(b)" " held" "$(rrn_read pair-b.place)"
expect_ne "11.47b …two requests, not one" "$(rrn_read pair-a.place)" "$(rrn_read pair-b.place)"
expect_eq "11.48 …and every request was ended" "" "$(rrn_unended)"

# ---- (f) ONE CEILING: the settle and the retries share one deadline ---------
# A foreign admitted run is killed RRN_CD seconds into the drive, so the whole request waits for
# it; the load stays above the line throughout. The ceiling counts from the admission, not from
# the drive: the settle gives up RRN_CMW seconds after the request is admitted, and the suite
# then runs once and is void. The gap is read between two stamps of this fixture (a watcher
# records the admission, the suite records its start), not off the drive's wall time.
TNC="$RRN/ceiling"
rr_tree "$TNC"
rr_stub "$TNC" "c-plain"
rrn_suite "$TNC/tests/aaa-ceil.test.sh" yes aaa-ceil \
'date +%s > "$RRN_MARKS/ceil.start"
if kill -0 "$RRN_FOREIGN" 2>/dev/null; then s=alive; else s=gone; fi
printf "%s\n" "$s" > "$RRN_MARKS/ceil.foreign"'
RRN_CMW=6; RRN_CD=4
rm -f "$RRN_MARKS"/*; rm -rf "$RRN_GATE"
printf '99\n' > "$RRN_LOAD"
RRN_FPID="$( ( sleep 60 >/dev/null 2>&1 & printf '%s' "$!" ) )"
rrn_plant 900 "$RRN_FPID"
( i=0
  while [ "$i" -lt 600 ]; do
    f="$(grep -l '^key=aaa-ceil.test.sh$' "$RRN_GATE"/requests/[0-9]* 2>/dev/null | head -n 1)"
    [ -n "$f" ] && grep -q '^admitted=' "$f" && break
    sleep 0.1; i=$((i + 1))
  done
  date +%s > "$RRN_MARKS/ceil.take" ) >/dev/null 2>&1 &
RRN_WATCHER=$!
( sleep "$RRN_CD"; kill "$RRN_FPID" ) >/dev/null 2>&1 &
RRN_KILLER=$!
RRN_FOREIGN="$RRN_FPID"
rrn_drive "$TNC" "$RRN_CMW" bash tests/run.sh
RRN_FOREIGN=""
kill "$RRN_FPID" "$RRN_WATCHER" "$RRN_KILLER" 2>/dev/null; wait "$RRN_WATCHER" "$RRN_KILLER" 2>/dev/null
RRN_CT="$(rrn_read ceil.take)"; RRN_CS="$(rrn_read ceil.start)"
expect_eq "11.49 one ceiling: the void does not fail the run" "0" "$RRN_RC"
expect_regex "11.50 …the watcher saw the whole request admitted" '^[0-9]+$' "$RRN_CT"
expect_regex "11.51 …and the suite recorded its start" '^[0-9]+$' "$RRN_CS"
expect_eq "11.52 …the request was admitted only once the foreign holder was gone" "gone" \
  "$(rrn_read ceil.foreign)"
expect_contains "11.53 …so the void is the settle's" "never settled" \
  "$(rrn_line aaa-ceil.test.sh)"
expect_true "11.54 the settle gave up at the ceiling counted from the admission: the suite started within ${RRN_CMW}s + 2 of it (took $(( ${RRN_CS:-0} - ${RRN_CT:-0} ))s)" \
  test "$(( ${RRN_CS:-999} - ${RRN_CT:-0} ))" -le $((RRN_CMW + 2))
expect_true "11.54b …and not before it: at least ${RRN_CMW}s - 1 after the admission" \
  test "$(( ${RRN_CS:-0} - ${RRN_CT:-999} ))" -ge $((RRN_CMW - 1))

# A run voided by a load that never comes down: the retry's settle meets the same ceiling, so
# the retry never starts, and the suite is not run a second time either — its one disturbed
# run already left its output to read.
rm -f "$RRN_MARKS"/*; rm -rf "$RRN_GATE"; printf '0\n' > "$RRN_LOAD"
RRN_VOID=stuck; rrn_drive "$TNV" 3 bash tests/run.sh; RRN_VOID=""
expect_eq "11.55 a disturbance that outlasts the ceiling: the run is not failed" "0" "$RRN_RC"
expect_contains "11.56 …its verdict line reads VOID" "VOID" "$(rrn_line aaa-void.test.sh)"
expect_contains "11.57 …because the ceiling ran out before a retry could start" \
  "ran out before a retry could start" "$(rrn_line aaa-void.test.sh)"
expect_eq "11.58 …so it ran once: no retry without room, and no run after it" "1" \
  "$(rrn_void_runs)"

# ---- (g) OWN LOAD: the suite's own share of the load is not a disturbance ---
# The suite burns CPU for two seconds, then sets the load reading to the settled line plus
# HALF of its own share of the one-minute average, computed from its own `times`. Anything
# above its own share would be someone else's; its own load alone must not void it. The line
# is read the way the runner reads it, in the fixture tree.
TNL="$RRN/own"
rr_tree "$TNL"
rr_stub "$TNL" "o-plain"
RRN_OLINE="$( cd "$TNL" && . payload/scripts/lib/resources.sh && resources_settled_line "$(_res_cores)" )"
expect_regex "11.59 the settled line is read" '^[0-9]+\.[0-9]+$' "$RRN_OLINE"
cat > "$RRN/burn.sh" <<'RRN_BURN'
s=$SECONDS; while [ $((SECONDS - s)) -lt 2 ]; do :; done
w=$((SECONDS - s)); times > "$1/own.t"
awk -v line="$2" -v w="$w" '
  function sec(x, a) { sub(/s$/, "", x); gsub(",", ".", x); split(x, a, "m"); return a[1] * 60 + a[2] }
  NR == 1 { cpu = sec($1) + sec($2); own = (cpu / w) * (1 - exp(-w / 60)); printf "%.6f\n", line + own / 2 }
' "$1/own.t" > "$1/own.after"
cat "$1/own.after" > "$3"
RRN_BURN
rrn_suite "$TNL/tests/aaa-own.test.sh" yes aaa-own \
"echo run >> \"\$RRN_MARKS/own.runs\"
bash \"$RRN/burn.sh\" \"\$RRN_MARKS\" $RRN_OLINE \"\$RRN_LOAD\""
rm -f "$RRN_MARKS"/*; rm -rf "$RRN_GATE"; printf '0\n' > "$RRN_LOAD"
rrn_drive "$TNL" 10 bash tests/run.sh
RRN_OAFTER="$(rrn_read own.after)"
expect_true "11.60 the load after the run is above the settled line (${RRN_OAFTER:-?} > $RRN_OLINE)" \
  awk -v a="${RRN_OAFTER:-0}" -v l="$RRN_OLINE" 'BEGIN { exit !(a + 0 > l + 0) }'
expect_eq "11.61 …yet the run is green" "0" "$RRN_RC"
expect_contains "11.62 …and the suite's verdict line reads PASS: its own load is not a disturbance" \
  "PASS" "$(rrn_line aaa-own.test.sh)"
expect_eq "11.63 …and it ran once" "1" \
  "$(awk 'END { print NR + 0 }' "$RRN_MARKS/own.runs" 2>/dev/null)"

# ---- (h) A STORE THAT CANNOT BE WRITTEN: VOID at once, saying so ------------
TNS="$RRN/store"
rr_tree "$TNS"
rr_stub "$TNS" "s-plain"
rrn_suite "$TNS/tests/aaa-store.test.sh" yes aaa-store 'echo run >> "$RRN_MARKS/store.runs"'
RRN_RO="$RRN/ro-store"
rm -f "$RRN_MARKS"/*; rm -rf "$RRN_RO"; mkdir -p "$RRN_RO"; chmod 555 "$RRN_RO"
expect_true "11.64 precondition: the store cannot be written" test ! -w "$RRN_RO"
RRN_SAVE="$RRN_GATE"; RRN_GATE="$RRN_RO"
RRN_T0=$SECONDS
rrn_drive "$TNS" 30 bash tests/run.sh
RRN_SDT=$((SECONDS - RRN_T0))
RRN_GATE="$RRN_SAVE"
chmod 755 "$RRN_RO"
expect_eq "11.65 a store that cannot be written: the run is not failed" "0" "$RRN_RC"
expect_contains "11.66 …the suite's verdict line reads VOID" "VOID" "$(rrn_line aaa-store.test.sh)"
expect_contains "11.67 …and says the store could not be written, naming it" \
  "the store $RRN_RO could not be written" "$(rrn_line aaa-store.test.sh)"
expect_absent "11.68 …not that places did not drain" "drain" "$(rrn_line aaa-store.test.sh)"
expect_eq "11.69 …the suite still ran once, so its output is there to read" "1" \
  "$(awk 'END { print NR + 0 }' "$RRN_MARKS/store.runs" 2>/dev/null)"
expect_true "11.70 …at once, not after the maximum wait (took ${RRN_SDT}s, wait 30s)" \
  test "$RRN_SDT" -le 15

# ---- (i) A VOID SUITE THAT FAILED IS A FAILURE ------------------------------
# A void says the suite's timing was not measured; it says nothing about its rows. Until T43
# the runner judged a void before it judged the exit status, so a solo suite that failed on
# a busy machine was counted in neither tally and the run exited 0. The suite here reads a
# plan, one word per try (the last word repeats): `<outcome>:<load>`. The outcome is pass,
# fail (a planted row that fails) or lost (a call to a helper that does not exist, which
# exits 0); the load is clean, void (raised, and lowered three seconds later, as (d) does)
# or stuck (raised for good). Each drive has an id, and a lowering happens only while its
# own drive is the current one, so a late one cannot lower a later drive's raised load.
TNX="$RRN/void-fail"
rr_tree "$TNX"
rr_stub "$TNX" "x-plain"
cat > "$TNX/tests/aaa-vfail.test.sh" <<'RRX_SUITE'
#!/bin/bash
# runner: solo
set -uo pipefail
. "$(dirname "$0")/lib/assert.sh"
section "aaa-vfail"
printf "run\n" >> "$RRN_MARKS/vf.runs"
n="$(awk 'END { print NR + 0 }' "$RRN_MARKS/vf.runs")"
step="$(awk -v n="$n" '{ print (n <= NF ? $n : $NF) }' "$RRN_MARKS/vf.plan")"
id="$(cat "$RRN_MARKS/vf.id")"
case "$step" in
  *:void)
    printf "99\n" > "$RRN_LOAD"
    ( sleep 3; [ "$(cat "$RRN_MARKS/vf.id" 2>/dev/null)" = "$id" ] && printf "0\n" > "$RRN_LOAD" ) >/dev/null 2>&1 & ;;
  *:stuck) printf "99\n" > "$RRN_LOAD" ;;
esac
case "$step" in
  fail:*) expect_eq "the planted row" "pass" "fail" ;;
  lost:*) rrx_helper_that_does_not_exist ;;
  killw:*) sleep 1; kill -9 "$PPID"; sleep 1 ;;
esac
expect_eq "aaa-vfail ran" "x" "x"
finish
RRX_SUITE
RRX_ID=0
rrx_prep() {  # <plan> <load at start> — a fresh drive: no marks, no store, a new id
  rm -f "$RRN_MARKS"/*; rm -rf "$RRN_GATE"; printf '%s\n' "$2" > "$RRN_LOAD"
  RRX_ID=$((RRX_ID + 1)); printf '%s\n' "$RRX_ID" > "$RRN_MARKS/vf.id"
  printf '%s\n' "$1" > "$RRN_MARKS/vf.plan"
}
rrx_runs() { awk 'END { print NR + 0 }' "$RRN_MARKS/vf.runs" 2>/dev/null || echo 0; }
rrx_gating() { printf '%s\n' "$RRN_OUT" | grep '^Gating: '; }
rrx_sum() { rrx_gating | awk '{ print $2 + $4 }'; }  # passed + failed
# The entries of one summary block: its heading line and the `    - ` lines under it.
rrx_block() { printf '%s\n' "$RRN_OUT" | awk -v h="^$1:" '$0 ~ h { on = 1; print; next } on && /^    - / { print; next } { on = 0 }'; }
RRX_SUITES="$(rr_glob "$TNX" | awk 'END { print NR + 0 }')"
expect_eq "11.71 precondition: the fixture tree holds two suites, one solo" "2 1" \
  "$RRX_SUITES $(grep -l '^# runner: solo' "$TNX"/tests/*.test.sh | awk 'END { print NR + 0 }')"

# A suite that failed on every try, and every try disturbed: the defect itself.
rrx_prep "fail:void" 0
rrn_drive "$TNX" 20 bash tests/run.sh
expect_eq "11.72 a solo suite that failed and was void fails the run" "1" "$RRN_RC"
expect_true "11.73 …every try was disturbed: it was re-run" test "$(rrx_runs)" -ge 2
expect_contains "11.74 …its verdict line reads FAIL" "✗ FAIL" "$(rrn_line aaa-vfail.test.sh)"
expect_contains "11.75 …with its void reason beside it: its timing was not measured either" \
  "VOID (timing not measured: the load rose" "$(rrn_line aaa-vfail.test.sh)"
expect_eq "11.76 the Gating line counts it failed" "Gating: 1 passed, 1 failed" "$(rrx_gating)"
expect_eq "11.77 …so the tallies add up to the suites run" "$RRX_SUITES" "$(rrx_sum)"
expect_contains "11.78 it is listed under Failed:" "- aaa-vfail.test.sh" "$(rrx_block Failed)"
expect_contains "11.79 …with its void reason" "timing not measured" "$(rrx_block Failed)"
expect_eq "11.80 …and not also under Void: (counted once; 11.87 is the positive)" "" "$(rrx_block Void)"
expect_absent "11.81 …and the run does not say no gating suite failed (11.88 is the positive)" \
  "No gating suite failed" "$RRN_OUT"

# A suite that passed on every try, every try disturbed: void, as before T43.
rrx_prep "pass:void" 0
rrn_drive "$TNX" 20 bash tests/run.sh
expect_eq "11.82 a solo suite that passed and was void does not fail the run" "0" "$RRN_RC"
expect_true "11.83 …every try was disturbed: it was re-run" test "$(rrx_runs)" -ge 2
expect_contains "11.84 …its verdict line reads VOID" "~ VOID (timing not measured" "$(rrn_line aaa-vfail.test.sh)"
expect_absent "11.85 …not FAIL" "FAIL" "$(rrn_line aaa-vfail.test.sh)"
expect_eq "11.86 the Gating line counts it in neither tally" "Gating: 1 passed, 0 failed" "$(rrx_gating)"
expect_contains "11.87 …it is listed under Void:" "- aaa-vfail.test.sh" "$(rrx_block Void)"
expect_contains "11.88 …the run says no gating suite failed, and one is void" \
  "No gating suite failed; 1 void" "$RRN_OUT"
expect_eq "11.89 …so the tallies and the void list add up to the suites run" "$RRX_SUITES" \
  "$(( $(rrx_sum) + $(rrx_block Void | grep -c '^    - ') ))"
expect_eq "11.90 …and nothing is listed under Failed: (11.78 is the positive)" "" "$(rrx_block Failed)"

# A suite that failed and was never disturbed: a plain failure, as before T43.
rrx_prep "fail:clean" 0
rrn_drive "$TNX" 20 bash tests/run.sh
expect_eq "11.91 a solo suite that failed undisturbed fails the run" "1" "$RRN_RC"
expect_eq "11.92 …it ran once" "1" "$(rrx_runs)"
expect_contains "11.93 …its verdict line reads FAIL" "✗ FAIL" "$(rrn_line aaa-vfail.test.sh)"
expect_absent "11.94 …with no void reason" "VOID" "$(rrn_line aaa-vfail.test.sh)"
expect_eq "11.95 …and the Gating line counts it failed" "Gating: 1 passed, 1 failed" "$(rrx_gating)"

# THE RETRY: the last try's result stands, because each try rewrites the suite's capture.
rrx_prep "fail:void pass:clean" 0
rrn_drive "$TNX" 20 bash tests/run.sh
expect_eq "11.96 failed and disturbed, then passed undisturbed: the run is green" "0" "$RRN_RC"
expect_eq "11.97 …it ran twice" "2" "$(rrx_runs)"
expect_contains "11.98 …and its verdict line reads PASS" "✓ PASS" "$(rrn_line aaa-vfail.test.sh)"
rrx_prep "pass:void fail:clean" 0
rrn_drive "$TNX" 20 bash tests/run.sh
expect_eq "11.99 passed and disturbed, then failed undisturbed: the run fails" "1" "$RRN_RC"
expect_eq "11.100 …it ran twice" "2" "$(rrx_runs)"
expect_contains "11.101 …its verdict line reads FAIL" "✗ FAIL" "$(rrn_line aaa-vfail.test.sh)"
expect_absent "11.102 …and the measured try carries no void reason" "VOID" "$(rrn_line aaa-vfail.test.sh)"

# THE CEILING RAN OUT BEFORE A RETRY: the one disturbed run's failure stands.
rrx_prep "fail:stuck" 0
rrn_drive "$TNX" 3 bash tests/run.sh
expect_eq "11.103 failed, disturbed, and no room for a retry: the run fails" "1" "$RRN_RC"
expect_eq "11.104 …it ran once" "1" "$(rrx_runs)"
expect_contains "11.105 …its verdict line reads FAIL" "✗ FAIL" "$(rrn_line aaa-vfail.test.sh)"
expect_contains "11.106 …saying the ceiling ran out" "ran out before a retry could start" \
  "$(rrn_line aaa-vfail.test.sh)"

# THE SETTLE GAVE UP ON THE FIRST TRY: the suite ran once, unbooked, and failed.
rrx_prep "fail:clean" 99
rrn_drive "$TNX" 2 bash tests/run.sh
expect_eq "11.107 failed after a settle that gave up: the run fails" "1" "$RRN_RC"
expect_eq "11.108 …it ran once" "1" "$(rrx_runs)"
expect_contains "11.109 …its verdict line reads FAIL" "✗ FAIL" "$(rrn_line aaa-vfail.test.sh)"
expect_contains "11.110 …saying the load never settled" "never settled" "$(rrn_line aaa-vfail.test.sh)"

# A STORE THAT CANNOT BE WRITTEN: the suite ran once, unbooked, and failed.
rrx_prep "fail:clean" 0
rm -rf "$RRN_RO"; mkdir -p "$RRN_RO"; chmod 555 "$RRN_RO"
RRN_SAVE="$RRN_GATE"; RRN_GATE="$RRN_RO"
rrn_drive "$TNX" 30 bash tests/run.sh
RRN_GATE="$RRN_SAVE"
chmod 755 "$RRN_RO"
expect_eq "11.111 failed with a store that cannot be written: the run fails" "1" "$RRN_RC"
expect_eq "11.112 …it ran once" "1" "$(rrx_runs)"
expect_contains "11.113 …its verdict line reads FAIL" "✗ FAIL" "$(rrn_line aaa-vfail.test.sh)"
expect_contains "11.114 …naming the store" "the store $RRN_RO could not be written" \
  "$(rrn_line aaa-vfail.test.sh)"

# EXITED 0 OVER A COMMAND THAT WAS NOT FOUND, every try disturbed: a failure too.
rrx_prep "lost:void" 0
rrn_drive "$TNX" 20 bash tests/run.sh
expect_eq "11.115 exited 0 but lost a command, and void: the run fails" "1" "$RRN_RC"
expect_contains "11.116 …its verdict line names the lost command" "a command it called was not found" \
  "$(rrn_line aaa-vfail.test.sh)"
expect_contains "11.117 …and its void reason" "VOID (timing not measured" "$(rrn_line aaa-vfail.test.sh)"
expect_eq "11.118 …and the Gating line counts it failed" "Gating: 1 passed, 1 failed" "$(rrx_gating)"

# --serial takes nothing and voids nothing: a disturbed failure is a plain failure there.
rrx_prep "fail:void" 0
rrn_drive "$TNX" 20 bash tests/run.sh --serial
expect_eq "11.119 --serial: a solo suite that failed fails the run" "1" "$RRN_RC"
expect_contains "11.120 --serial: …its verdict line reads FAIL" "✗ FAIL" "$(rrn_line aaa-vfail.test.sh)"
expect_absent "11.121 --serial: …with no void reason, since nothing was checked" "VOID" \
  "$(rrn_line aaa-vfail.test.sh)"
expect_eq "11.122 --serial: …and the Gating line counts it failed" "Gating: 1 passed, 1 failed" "$(rrx_gating)"

# THE TIMING FILE HOLDS MEASUREMENTS ONLY (wave-26 T48; review 11 N1): the file the timing knob
# names gets one `<label>TAB<seconds>` row per suite that was timed. A suite reported VOID has
# its seconds disturbed, so it gets no row; a reader of the file then cannot take them for a
# measurement. The companion rows keep the fix honest: the suite that was not void in the same
# run still has its row, so writing nothing at all would fail them.
rrx_trows() {  # <file> <label> — how many rows the file holds for the label
  LC_ALL=C awk -F'\t' -v l="$2" '$1 == l { n++ } END { print n + 0 }' "$1" 2>/dev/null
}
rrx_tshaped() {  # <file> <label> — how many of them are `<label>TAB<whole seconds>`
  LC_ALL=C awk -F'\t' -v l="$2" 'NF == 2 && $1 == l && $2 ~ /^[0-9]+$/ { n++ } END { print n + 0 }' "$1" 2>/dev/null
}
RRX_TF="$TMPROOT/void-timing.tsv"

# CONTROL: nothing void. Both suites are timed, the solo one included.
rrx_prep "pass:clean" 0
rm -f "$RRX_TF"
rrn_drive "$TNX" 20 env BIONIC_TEST_TIMING="$RRX_TF" bash tests/run.sh
expect_eq "11.123 a solo suite that passed undisturbed: the run is green" "0" "$RRN_RC"
expect_contains "11.124 …its verdict line reads PASS, so it was timed" "✓ PASS" "$(rrn_line aaa-vfail.test.sh)"
expect_eq "11.125 …and the timing file holds one shaped row for it" "1" "$(rrx_tshaped "$RRX_TF" aaa-vfail.test.sh)"
expect_eq "11.126 …and one for the plain suite" "1" "$(rrx_tshaped "$RRX_TF" x-plain.test.sh)"

# VOID AND PASSED, every try disturbed.
rrx_prep "pass:void" 0
rm -f "$RRX_TF"
rrn_drive "$TNX" 20 env BIONIC_TEST_TIMING="$RRX_TF" bash tests/run.sh
expect_contains "11.127 a solo suite that passed and was void: its line says its timing was not measured" \
  "~ VOID (timing not measured" "$(rrn_line aaa-vfail.test.sh)"
expect_eq "11.128 …the timing file holds no row for it" "0" "$(rrx_trows "$RRX_TF" aaa-vfail.test.sh)"
expect_eq "11.129 …while the plain suite of the same run has its shaped row" "1" \
  "$(rrx_tshaped "$RRX_TF" x-plain.test.sh)"

# VOID AND FAILED, every try disturbed: counted a failure, and still not a measurement.
rrx_prep "fail:void" 0
rm -f "$RRX_TF"
rrn_drive "$TNX" 20 env BIONIC_TEST_TIMING="$RRX_TF" bash tests/run.sh
expect_contains "11.130 a solo suite that failed and was void: its line carries the void reason" \
  "also VOID (timing not measured" "$(rrn_line aaa-vfail.test.sh)"
expect_eq "11.131 …the timing file holds no row for it" "0" "$(rrx_trows "$RRX_TF" aaa-vfail.test.sh)"
expect_eq "11.132 …while the plain suite of the same run has its shaped row" "1" \
  "$(rrx_tshaped "$RRX_TF" x-plain.test.sh)"

# VOID ON THE FIRST TRY, MEASURED ON THE RETRY: the suite was timed, so the row stays.
rrx_prep "pass:void pass:clean" 0
rm -f "$RRX_TF"
rrn_drive "$TNX" 20 env BIONIC_TEST_TIMING="$RRX_TF" bash tests/run.sh
expect_contains "11.133 a solo suite disturbed once and clean on the retry: it passed" "✓ PASS" \
  "$(rrn_line aaa-vfail.test.sh)"
expect_eq "11.134 …its undisturbed try is a measurement, so the file holds its one shaped row" "1" \
  "$(rrx_tshaped "$RRX_TF" aaa-vfail.test.sh)"

# A TRY THAT WRITES NOTHING READS AS NOTHING (wave-26 T49; review 12 F1). A worker writes its
# exit code and its seconds only after its suite ends, so a worker killed on a retry left the
# EARLIER try's files in place and the runner judged the retry by them. `killw` kills the
# suite's own worker with SIGKILL: no exit code, no seconds, no progress line.
rrx_prep "pass:void killw:clean" 0
rm -f "$RRX_TF"
rrn_drive "$TNX" 20 env BIONIC_TEST_TIMING="$RRX_TF" bash tests/run.sh
expect_eq "11.135 precondition: a passing disturbed try, then a retry whose worker was killed, ran twice" "2" \
  "$(rrx_runs)"
expect_contains "11.136 …the suite is reported killed with no exit status, not passed" \
  "✗ KILLED (no exit status recorded)" "$(rrn_line aaa-vfail.test.sh)"
expect_eq "11.137 …the run exits non-zero" "1" "$RRN_RC"
expect_eq "11.138 …the Gating line counts it failed" "Gating: 1 passed, 1 failed" "$(rrx_gating)"
expect_contains "11.139 …it is listed under Failed:" "- aaa-vfail.test.sh" "$(rrx_block Failed)"
expect_absent "11.140 …and the run does not call itself all green" "All gating suites green" "$RRN_OUT"
expect_eq "11.141 …the timing file holds no row for it: the earlier try's seconds are not read" "0" \
  "$(rrx_trows "$RRX_TF" aaa-vfail.test.sh)"
expect_eq "11.142 …while the plain suite of the same run has its shaped row" "1" \
  "$(rrx_tshaped "$RRX_TF" x-plain.test.sh)"

# The same hole from the failing side: the earlier try's FAILURE must not be read as the retry's.
rrx_prep "fail:void killw:clean" 0
rm -f "$RRX_TF"
rrn_drive "$TNX" 20 env BIONIC_TEST_TIMING="$RRX_TF" bash tests/run.sh
expect_contains "11.143 failed and disturbed, then the retry's worker killed: the line says no exit status, not a stale FAIL" \
  "✗ KILLED (no exit status recorded)" "$(rrn_line aaa-vfail.test.sh)"
expect_eq "11.144 …the run exits non-zero" "1" "$RRN_RC"
expect_eq "11.145 …and the timing file holds no row for it" "0" "$(rrx_trows "$RRX_TF" aaa-vfail.test.sh)"

# CONTROL for the two above: the retry's worker survives. The earlier try's failure is not read
# and its seconds are not written; the last try's result stands, and it is a timed measurement.
rrx_prep "fail:void pass:clean" 0
rm -f "$RRX_TF"
rrn_drive "$TNX" 20 env BIONIC_TEST_TIMING="$RRX_TF" bash tests/run.sh
expect_eq "11.146 failed and disturbed, then passed on a clean retry: the run is green" "0" "$RRN_RC"
expect_contains "11.147 …its verdict line reads PASS" "✓ PASS" "$(rrn_line aaa-vfail.test.sh)"
expect_eq "11.148 …and the timing file holds its one shaped row, from the retry" "1" \
  "$(rrx_tshaped "$RRX_TF" aaa-vfail.test.sh)"

# ============================================================
section "§TIMING a nested run writes no rows into the outer run's timing file (wave-26 T26; D20, AC-10.2)"
# ============================================================
#
# `BIONIC_TEST_TIMING` names a file a full run appends one `<label>TAB<seconds>` row to per
# suite. Four suites in this repo drive a nested runner over a scratch tree, and a nested run
# that inherited the knob wrote ITS fixture labels into the real run's file: 60 of 135 rows of
# one floor run (research R4 §B1). The fixture is that shape at its smallest: an outer tree
# whose one suite drives a nested run over an inner tree, with the knob set on the outer run.
TT_INNER="$TMPROOT/tt-inner"
rr_tree "$TT_INNER"
rr_stub "$TT_INNER" "zin-timed"
TT="$TMPROOT/tt"
rr_tree "$TT"
rr_stub "$TT" "t-plain"
cat > "$TT/tests/t-outer.test.sh" <<'RRT_NESTED'
#!/bin/bash
set -uo pipefail
. "$(dirname "$0")/lib/assert.sh"
section "t-outer"
( cd "$RRT_INNER" && bash tests/run.sh >/dev/null 2>&1 )
expect_eq "the nested run over the inner tree is green" "0" "$?"
finish
RRT_NESTED

rrt_drive() {  # <dir> <timing-file> [mode] — leaves RR_OUT and RR_RC
  local dir="$1" tf="$2" mode="${3:-}"
  RR_OUT="$( cd "$dir" && \
    RR_MARKS="$RR_MARKS" RRT_INNER="$TT_INNER" \
    BIONIC_PRESSURE_RING="$TMPROOT/ring" \
    BIONIC_NOW_EPOCH="$RR_NOW" \
    BIONIC_TEST_JOBS_CEILING="2" \
    BIONIC_PROBE_FREE_PCT="44" \
    BIONIC_PROBE_SWAP_PCT="0" \
    BIONIC_PROBE_LOAD_1M="0.1" \
    BIONIC_TEST_TIMING="$tf" \
    env "${RR_GATE_ENV[@]}" bash tests/run.sh ${mode:+"$mode"} 2>&1 )"
  RR_RC=$?
}
rrt_labels() { LC_ALL=C awk -F'\t' '{ print $1 }' "$1" 2>/dev/null | sort -u; }
rrt_shaped() {  # <file> — how many lines are `<label>.test.sh TAB <whole seconds>`
  LC_ALL=C awk -F'\t' 'NF == 2 && $1 ~ /\.test\.sh$/ && $2 ~ /^[0-9]+$/ { n++ } END { print n+0 }' "$1" 2>/dev/null
}

TTF="$TMPROOT/tt.timing.tsv"
rm -f "$TTF" "$RR_MARKS/zin-timed.ran"
rrt_drive "$TT" "$TTF"
expect_eq "T.1 the outer run is green, nested drive and all" "0" "$RR_RC"
# PAIRED POSITIVE: the nested run happened, so a row missing below is a knob that did not
# leak, not a nested run that never ran.
expect_eq "T.2 the nested run really ran its own suite" "yes" \
  "$([ -f "$RR_MARKS/zin-timed.ran" ] && echo yes || echo no)"
expect_eq "T.3 the timing file names the outer tree's suites, as a set" \
  "$(rr_glob "$TT")" "$(rrt_labels "$TTF")"
expect_absent "T.4 …and carries no row for the nested run's fixture suite" \
  "zin-timed.test.sh" "$(cat "$TTF" 2>/dev/null)"
expect_eq "T.5 …one shaped row per real suite: two lines, both shaped" "2 2" \
  "$(LC_ALL=C awk 'END { print NR+0 }' "$TTF" 2>/dev/null) $(rrt_shaped "$TTF")"

# --serial writes each row as its suite lands, from the same parent; the nested run is the same.
TTS="$TMPROOT/tt.timing-serial.tsv"
rm -f "$TTS" "$RR_MARKS/zin-timed.ran"
rrt_drive "$TT" "$TTS" --serial
expect_eq "T.6 --serial: the outer run is green" "0" "$RR_RC"
expect_eq "T.7 --serial: …the nested run really ran" "yes" \
  "$([ -f "$RR_MARKS/zin-timed.ran" ] && echo yes || echo no)"
expect_eq "T.8 --serial: …and the timing file names the outer tree's suites only" \
  "$(rr_glob "$TT")" "$(rrt_labels "$TTS")"

# ============================================================
section "§ONLY the named suites, and no other, in the runner's world (wave-28 T36; D27, AC-10.2)"
# ============================================================
#
# THE CLAIM. `tests/run.sh --only <suite>[ <suite>…]` is the one door a dispatched agent runs a
# suite through. It runs exactly the named suites, and each one gets what a full run gives it:
# the interpreter pin (bash -> /bin/bash first on PATH), the environment stamp, the roster wall
# and the adoption wall, and one gate ask per suite. A name the roster does not hold is refused
# by name and nothing runs; a suite nobody named never runs.
TO="$TMPROOT/only"; RO_GATE="$TMPROOT/only-gate"
rr_tree "$TO"
ro_stub() {  # <name> — a green suite recording the interpreter and the admission it ran under
  { printf '#!/bin/bash\n'
    printf 'set -uo pipefail\n'
    printf '. "$(dirname "$0")/lib/assert.sh"\n'
    printf ': > "$RR_MARKS/%s.ran"\n' "$1"
    printf 'printf "%%s\\n" "$BASH_VERSION" > "$RR_MARKS/%s.ver"\n' "$1"
    printf 'printf "%%s\\n" "$(readlink "${PATH%%%%:*}/bash")" > "$RR_MARKS/%s.pin"\n' "$1"
    printf 'printf "%%s\\n" "${BIONIC_GATE_ADMIT:-none}" > "$RR_MARKS/%s.admit"\n' "$1"
    printf 'section "%s"\n' "$1"
    printf 'expect_eq "%s ran" "x" "x"\n' "$1"
    printf 'finish\n'
  } > "${2:-$TO}/tests/$1.test.sh"
}
ro_stub only-a; ro_stub only-b
# A suite that does not adopt the framework (no `finish`): the adoption wall's to refuse.
{ printf '#!/bin/bash\n. "$(dirname "$0")/lib/assert.sh"\n: > "$RR_MARKS/only-c.ran"\nexit 0\n'; } > "$TO/tests/only-c.test.sh"
ro_drive() {  # <runner args…> — the scratch runner on this section's own store; RR_OUT, RR_RC
  rm -rf "$RO_GATE"; rm -f "$RR_MARKS"/only-*
  RR_OUT="$( cd "${RO_DIR:-$TO}" && RR_MARKS="$RR_MARKS" BIONIC_PRESSURE_RING="$TMPROOT/only-ring" \
    BIONIC_NOW_EPOCH="$RR_NOW" BIONIC_TEST_JOBS_CEILING=2 BIONIC_PROBE_FREE_PCT=44 \
    BIONIC_PROBE_SWAP_PCT=0 BIONIC_PROBE_LOAD_1M=0.1 \
    env "${RR_GATE_ENV[@]}" BIONIC_GATE_DIR="$RO_GATE" bash tests/run.sh "$@" 2>&1 )"
  RR_RC=$?
}
ro_ran() { [ -f "$RR_MARKS/$1.ran" ] && echo yes || echo no; }
ro_reqs() {  # one line per request: <key> <kind> <rc>, sorted
  local f
  for f in "$RO_GATE"/requests/[0-9]*; do
    [ -f "$f" ] || continue
    printf '%s %s %s\n' "$(sed -n 's/^key=//p' "$f" | tail -n 1)" "$(sed -n 's/^kind=//p' "$f" | tail -n 1)" \
      "$(sed -n 's/^rc=//p' "$f" | tail -n 1)"
  done | sort
}
RO_SYS_VER="$(/bin/bash -c 'echo "$BASH_VERSION"')"

ro_drive --only only-a.test.sh
expect_eq "ONLY.1 --only only-a.test.sh is green" "0" "$RR_RC"
expect_eq "ONLY.2 …the named suite ran (the mark extractor reads it)" "yes" "$(ro_ran only-a)"
expect_eq "ONLY.3 …and the suite nobody named did not" "no" "$(ro_ran only-b)"
expect_eq "ONLY.4 the run printed the named suite's label and no other" "only-a.test.sh" "$(rr_labels "$RR_OUT")"
expect_contains "ONLY.5 …and tallied one suite" "Gating: 1 passed, 0 failed" "$RR_OUT"
expect_eq "ONLY.6 it ran under the interpreter the full run uses: /bin/bash's version" \
  "$RO_SYS_VER" "$(cat "$RR_MARKS/only-a.ver" 2>/dev/null)"
expect_eq "ONLY.7 …through the pin, first on PATH: bash -> /bin/bash" "/bin/bash" "$(cat "$RR_MARKS/only-a.pin" 2>/dev/null)"
expect_regex "ONLY.8 the environment stamp is printed, as for a full run" '^env: os=[a-z]+ bash=' "$RR_OUT"
expect_eq "ONLY.9 one gate ask for the suite, keyed by its file name, ended with its code" \
  "only-a.test.sh work 0" "$(ro_reqs)"
expect_eq "ONLY.10 …and the suite ran under that request" \
  "$(grep -l '^key=only-a.test.sh$' "$RO_GATE"/requests/[0-9]* 2>/dev/null | head -n 1 | sed 's#.*/##')" \
  "$(cat "$RR_MARKS/only-a.admit" 2>/dev/null)"

ro_drive --only only-b.test.sh only-a.test.sh
expect_eq "ONLY.11 two names: green" "0" "$RR_RC"
expect_eq "ONLY.12 …both ran" "yes yes" "$(ro_ran only-a) $(ro_ran only-b)"
expect_eq "ONLY.13 …in roster order, whatever order they were named in" "only-a.test.sh
only-b.test.sh" "$(rr_labels "$RR_OUT")"
expect_eq "ONLY.14 …one ask per suite" "only-a.test.sh work 0
only-b.test.sh work 0" "$(ro_reqs)"
expect_eq "ONLY.15 …and the unnamed suite still did not run" "no" "$(ro_ran only-c)"

ro_drive --serial --only only-b.test.sh
expect_eq "ONLY.16 --serial --only: green" "0" "$RR_RC"
expect_eq "ONLY.17 …the named suite alone ran" "yes no" "$(ro_ran only-b) $(ro_ran only-a)"
expect_eq "ONLY.18 …with its one ask" "only-b.test.sh work 0" "$(ro_reqs)"

ro_drive --only only-c.test.sh
expect_eq "ONLY.19 the adoption wall holds for a named suite: the run fails" "1" "$RR_RC"
expect_contains "ONLY.20 …refused by the wall, by name" "REFUSED (the adoption wall)" "$RR_OUT"
expect_eq "ONLY.21 …and it never ran" "no" "$(ro_ran only-c)"

ro_drive --only nope.test.sh
expect_eq "ONLY.22 a name the roster does not hold is refused: exit 2" "2" "$RR_RC"
expect_contains "ONLY.23 …naming it" "tests/run.sh: --only names nope.test.sh, which is not a suite under tests/" "$RR_OUT"
expect_eq "ONLY.24 …and nothing ran" "no no" "$(ro_ran only-a) $(ro_ran only-b)"
ro_drive --only only-a.test.sh nope.test.sh
expect_eq "ONLY.25 one bad name among good ones refuses the whole call: exit 2, nothing ran" "2 no" \
  "$RR_RC $(ro_ran only-a)"
ro_drive --only tests/only-a.test.sh
expect_eq "ONLY.26 a path, not a file name, is refused: exit 2" "2" "$RR_RC"
expect_contains "ONLY.27 …saying what to type" "name a suite by its file name" "$RR_OUT"
ro_drive --only
expect_eq "ONLY.28 --only with no name is usage: exit 2" "2" "$RR_RC"
expect_contains "ONLY.29 …and the usage names the door" "--only <suite>" "$RR_OUT"
ro_drive --only only-a.test.sh --dry-run
expect_eq "ONLY.30 --dry-run still runs nothing" "0 no" "$RR_RC $(ro_ran only-a)"

# THE MUTANT: a runner copy whose --only filter is gone (the roster is not narrowed). The rows
# above that read "the unnamed suite did not run" must move: under it, only-b runs.
TOM="$TMPROOT/only-mut"
rr_tree "$TOM"; ro_stub only-a "$TOM"; ro_stub only-b "$TOM"
anchor "$TOM/tests/run.sh" '  set -- ${_only_files+"${_only_files[@]}"}' 1
grep -vF '  set -- ${_only_files+"${_only_files[@]}"}' "$RUNNER" > "$TOM/tests/run.sh"
expect_eq "ONLY.31 the mutant runner parses" "0" "$(bash -n "$TOM/tests/run.sh" >/dev/null 2>&1; echo $?)"
RO_DIR="$TOM" ro_drive --only only-a.test.sh
expect_eq "ONLY.32 …and still runs the named suite (not vacuous)" "yes" "$(ro_ran only-a)"
expect_eq "ONLY.33 under the mutant the unnamed suite runs (the defect ONLY.3 guards)" "yes" "$(ro_ran only-b)"

finish
