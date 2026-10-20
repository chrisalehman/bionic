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

# THE GATE'S STORE IS THIS SUITE'S OWN (wave-26 T8; the gate since wave-28 T12). Every run a
# runner starts asks the gate, so every drive below names a store under this suite's mktemp root, a short poll, and a low memory reading
# and an idle processor, pinned, so an admission never waits on what this machine is doing;
# none reads or writes the machine's real store under the home directory. The admission a
# caller may have inherited (a booked command or a runner around this suite exports
# BIONIC_GATE_ADMIT) is cleared, so each drive starts from no admission at all — §11 drives
# nesting itself.
RR_GATE_ENV=(-u BIONIC_GATE_ADMIT -u BIONIC_GATE_AGENT
  "BIONIC_GATE_DIR=$TMPROOT/gate" BIONIC_GATE_POLL=0.1 BIONIC_PROBE_USED_PCT=10
  BIONIC_PROBE_BUSY_CORES=0 BIONIC_PROBE_CORES=8 BIONIC_PROBE_TOTAL_MB=8192)
# THE STORE KNOWS A COST (wave-32 T1; D5). A store with no cost line anywhere admits a request
# only when nothing else is admitted, and under the pinned clock every drive's run is one of
# zero seconds, which the gate learns nothing from. This store's suites ran side by side only
# because such runs used to write cost lines; the machine's real store always carries some, so
# the fixture plants one small line, and every key this store has not seen is promised it.
mkdir -p "$TMPROOT/gate/cost"
printf '1:0.1:1:%s\n' "$RR_NOW" > "$TMPROOT/gate/cost/rr-seed"

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
# AC-6.1: the reader exam is a long sitting, not a gating suite. It lives under
# tests/exam/ and is run by name, so the roster glob must not reach it. The
# present-row is the paired positive: the file exists, so its absence from the
# glob is the move and not a missing file.
expect_eq "5.6 …the reader exam is outside the roster glob" "0" \
  "$(ls "$REPO"/tests/*.test.sh | grep -c 'reader-exam')"
expect_eq "5.7 …and the exam is shipped, to be run by name" "yes" \
  "$([ -f "$REPO/tests/exam/reader-exam.sh" ] && echo yes || echo no)"

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

# §8 (a `# runner: solo` suite held out of the parallel batch, T20) RETIRED BY WAVE-35 T2 (D11, AC-2.1):
# the marker is read by nobody, and tests/runner-width.test.sh §NO-VOID proves it ignored.

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
# makes the report's ROSTER-order contract falsifiable. §1.4 compares
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
# invocation and is no product of this knob; and the seconds of the whole run's `Wall:` line
# (wave-32 T2; D6), the run's own clock and landing order, which move between two drives. Everything else
# is compared as it was printed.
rr9_norm() { printf '%s\n' "$1" | sed -e 's|path=[^ ]*|path=PIN|g' -e 's/^Wall: .*/Wall: (masked)/'; }

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

# rr9_ends <file> — the file's SUITE-END lines only, `<UTC>TAB<label>TAB<rc>`. Since T8 (wave-30,
# Δ5a) a suite's own `section()` also appends `<UTC>TAB<label>TAB§<section>` to the same file while
# it runs (§PROGRESS below); the claims of this section are about the end lines, which still name
# only suites that finished.
rr9_ends() { LC_ALL=C awk -F'\t' '$3 ~ /^[0-9]+$/' "$1" 2>/dev/null; }

# rr9_prog_labels <file> — the labels the progress file's end lines recorded, sorted.
rr9_prog_labels() { rr9_ends "$1" | LC_ALL=C awk -F'\t' '{ print $2 }' | sort -u; }

# rr_labels_ordered <output> — the labels the runner printed, IN PRINTED ORDER.
# rr_labels sorts, which is what makes §1.4 a set comparison; the roster
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
# runner reports it KILLED. xargs abandons its queue when a child dies by signal,
# so the suite first waits, bounded, until both siblings' end lines are in the
# progress file: they have landed, and no launch is left to abandon. (Until
# wave-35 T2 it was marked `# runner: solo` and drained alone for the same reason.)
T9K="$TMPROOT/t9k"
rr_tree "$T9K"
for RR_N in k-one k-two; do rr_stub "$T9K" "$RR_N"; done
cat > "$T9K/tests/zzz-killed.test.sh" <<'RR9_KILLED'
#!/bin/bash
set -uo pipefail
. "$(dirname "$0")/lib/assert.sh"
i=0
while [ "$i" -lt 200 ] && [ "$(awk -F'\t' '$3 ~ /^[0-9]+$/ { n++ } END { print n + 0 }' "${_BIONIC_TEST_PROGRESS_FILE:-/dev/null}" 2>/dev/null)" -lt 2 ]; do
  i=$((i + 1)); sleep 0.1
done
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
expect_absent "9.16 …and never names the one that never finished in an end line" \
  "zzz-killed.test.sh" "$(rr9_ends "$P9K")"
# PAIRED: the killed suite IS in the report, so 9.16 is a missing progress line
# and not a suite the roster never carried.
expect_contains "9.18 …while the report still carries it, in roster order" \
  "zzz-killed.test.sh" "$RR9_OUT"

# ---- (d) a nested run does not pollute the outer watcher's file ------------
# FIXTURE FIDELITY (wave-32 T1; D5). The nested run is handed a store under this suite's own
# mktemp root (RR9_INNER_GATE), as §TIMING's is: the outer worker scrubs BIONIC_GATE_DIR from
# the suite it starts, so before this the inner run asked the machine's real store, under the
# pinned clock, with a scratch store's id in BIONIC_GATE_ADMIT, and left a request and a cost
# line there. What the fixture now pins: the nested run's request is in the scratch store
# (9.20a), and nothing in this section names the real store at all.
T9N_INNER="$TMPROOT/t9n-inner"
rr_tree "$T9N_INNER"
rr_stub "$T9N_INNER" "zin-inner"
export RR9_INNER="$T9N_INNER"
export RR9_INNER_GATE="$TMPROOT/gate-9n-inner"

T9N="$TMPROOT/t9n"
rr_tree "$T9N"
rr_stub "$T9N" "n-plain"
cat > "$T9N/tests/n-outer.test.sh" <<'RR9_NESTED'
#!/bin/bash
set -uo pipefail
. "$(dirname "$0")/lib/assert.sh"
: > "$RR_MARKS/n-outer.ran"
section "n-outer"
( cd "$RR9_INNER" && BIONIC_GATE_DIR="$RR9_INNER_GATE" bash tests/run.sh >/dev/null 2>&1 )
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
# PAIRED POSITIVE for the scratch store (wave-32 T1; D5): the nested run asked the store under
# this suite's mktemp root that n-outer handed it, so its request is there. RE-KEYED BY WAVE-32 T2
# (D1, AC-1.1; A-orch-8): the nested run is a whole run, so its one request is keyed by the runner.
expect_eq "9.20a the nested run's request is in the scratch store it was handed, keyed tests/run.sh" \
  "1" "$(grep -lx 'key=tests/run.sh' "$RR9_INNER_GATE"/requests/[0-9]* 2>/dev/null | wc -l | tr -d ' ')"
expect_eq "9.21 the outer file names the outer tree's two suites" \
  "$(printf 'n-outer.test.sh\nn-plain.test.sh\n')" "$(rr9_prog_labels "$P9N")"
expect_absent "9.22 …and carries no label from the nested tree" \
  "zin-inner.test.sh" "$(cat "$P9N")"

# ---- the report is in ROSTER order, and now that is falsifiable ------------
#
# The runner's drain comment says a reader comparing two runs is comparing
# rosters, not schedules. Until there was a progress file nothing in this repo
# could tell the two apart: §1.4 sorts both sides. Here the slow suite is
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
  "aaa-slow.test.sh" "$(rr9_ends "$P9O" | LC_ALL=C awk -F'\t' 'END { print $2 }')"
expect_eq "9.27 …while the report printed that same suite FIRST" \
  "aaa-slow.test.sh" "$(rr_labels_ordered "$RR9_OUT" | sed -n '1p')"


# ============================================================
section "§PROGRESS a section boundary inside a running suite writes a line (wave-30 T8; Δ5a, AC-3.8)"
# ============================================================
#
# WHAT IT COVERS. The runner captures each suite's output and prints it at the suite's end, so a
# run's log is silent for the length of its longest suite. The progress file is how a run is seen
# while it runs: with the knob set, `tests/lib/assert.sh` `section()` appends
# `<UTC>TAB<suite>TAB§<section>` to the file the runner hands its workers, AS the section opens.
# The probe suite opens a section, marks it, holds on a go-file, then opens a second one; the
# rows read the file WHILE it holds, so the line is proved to come before the suite's end, not
# merely before the file's.
#
# ANTI-VACUITY. PR.3, the absence of the probe's end line while it holds, sits beside PR.2, the
# §one line read from the same file at the same moment. PR.8 is the control: the same probe with
# the knob unset writes no file.
PRT="$TMPROOT/tpr"
rr_tree "$PRT"
rr_stub "$PRT" "pr-plain"
cat > "$PRT/tests/pr-probe.test.sh" <<'PR_PROBE'
#!/bin/bash
set -uo pipefail
. "$(dirname "$0")/lib/assert.sh"
section "one"
expect_eq "the first section ran" "x" "x"
: > "$RR_MARKS/pr-probe.one"
i=0; while [ ! -f "$RR_MARKS/pr-probe.go" ] && [ "$i" -lt 300 ]; do i=$((i+1)); sleep 0.05; done
section "two"
expect_eq "the second section ran" "x" "x"
finish
PR_PROBE
PRP="$TMPROOT/tpr.progress.tsv"
rm -f "$PRP" "$RR_MARKS/pr-probe.one" "$RR_MARKS/pr-probe.go"
printf '%s|44|0|0.1|2\n' "$RR_NOW" > "$RR9_RING"
( cd "$PRT" && RR_MARKS="$RR_MARKS" BIONIC_PRESSURE_RING="$RR9_RING" BIONIC_NOW_EPOCH="$RR_NOW" \
    BIONIC_TEST_JOBS_CEILING="2" BIONIC_PROBE_FREE_PCT="44" BIONIC_PROBE_SWAP_PCT="0" \
    BIONIC_PROBE_LOAD_1M="0.1" BIONIC_TEST_PROGRESS="$PRP" \
    env "${RR_GATE_ENV[@]}" bash tests/run.sh > "$TMPROOT/tpr.out" 2>&1; echo "$?" > "$TMPROOT/tpr.rc" ) &
PR_BG=$!
pr_i=0
while [ ! -f "$RR_MARKS/pr-probe.one" ] && [ "$pr_i" -lt 200 ]; do pr_i=$((pr_i + 1)); sleep 0.05; done
expect_true "PR.1 (fixture) the probe suite reached its first section and holds" test -f "$RR_MARKS/pr-probe.one"
PR_MID="$(cat "$PRP" 2>/dev/null)"
expect_regex "PR.2 while the suite runs, the file already holds its first section's line" \
  "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z	pr-probe[.]test[.]sh	§one\$" "$PR_MID"
expect_no_regex "PR.3 …and no end line for it yet" "	pr-probe[.]test[.]sh	[0-9]+\$" "$PR_MID"
: > "$RR_MARKS/pr-probe.go"
wait "$PR_BG"
expect_eq "PR.4 the run is green" "0" "$(cat "$TMPROOT/tpr.rc" 2>/dev/null)"
expect_eq "PR.5 the probe's lines, in order: §one, §two, then its end line" \
  "$(printf '§one\n§two\n0')" \
  "$(LC_ALL=C awk -F'\t' '$2 == "pr-probe.test.sh" { print $3 }' "$PRP" 2>/dev/null)"
expect_eq "PR.6 the other suite's section line names it, by its own file" "§pr-plain" \
  "$(LC_ALL=C awk -F'\t' '$2 == "pr-plain.test.sh" && $3 !~ /^[0-9]+$/ { print $3 }' "$PRP" 2>/dev/null)"
expect_absent "PR.7 the report itself is unchanged by the knob: no section line printed" \
  "	§one" "$(cat "$TMPROOT/tpr.out" 2>/dev/null)"
rm -f "$RR_MARKS/pr-probe.one"; : > "$RR_MARKS/pr-probe.go"
PRU="$TMPROOT/tpr-unset.progress.tsv"; rm -f "$PRU"
( cd "$PRT" && RR_MARKS="$RR_MARKS" BIONIC_PRESSURE_RING="$RR9_RING" BIONIC_NOW_EPOCH="$RR_NOW" \
    BIONIC_TEST_JOBS_CEILING="2" BIONIC_PROBE_FREE_PCT="44" BIONIC_PROBE_SWAP_PCT="0" \
    BIONIC_PROBE_LOAD_1M="0.1" env "${RR_GATE_ENV[@]}" bash tests/run.sh >/dev/null 2>&1 )
expect_true "PR.8a (control) the probe ran again with the knob unset" test -f "$RR_MARKS/pr-probe.one"
expect_false "PR.8 …and with the knob unset section() writes no file" test -e "$PRU"

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
section "§ASK a whole run asks the gate once; --serial asks per suite (T12; AC-2.12; wave-32 T2, D1, AC-1.1)"
# ============================================================
#
# THE CLAIM. Wave-28 T12 made every `--one` worker ask `gate_ask work <suite>` for itself and the
# runner hold nothing. WAVE-32 T2 (D1, AC-1.1; A-orch-8) REVERSES THAT FOR A WHOLE RUN BY DESIGN,
# and ASK.2-ASK.6 and ASK.11 were rewritten to pin the new shape — a chartered behaviour change
# rewriting its own pins, not a loosened assertion: the runner asks `whole tests/run.sh` once,
# every worker runs inside that one request (BIONIC_GATE_ADMIT names it), and
# the runner ends it with the run's code. --serial still asks per suite (ASK.7-ASK.9, unchanged),
# as does --only (§ONLY, §ONLY-UNCHANGED). The store is this section's own
# (BIONIC_GATE_DIR under the suite's mktemp root) and the memory reading is pinned low, so no
# drive reads or writes the machine's real gate.
TA="$TMPROOT/ask"; RA_GATE="$TMPROOT/ask-gate"
rr_tree "$TA"
ra_stub() {  # <name> — a green suite that records the admission it ran under
  { printf '#!/bin/bash\n'
    printf 'set -uo pipefail\n'
    printf '. "$(dirname "$0")/lib/assert.sh"\n'
    printf 'printf "%%s\\n" "${BIONIC_GATE_ADMIT:-none}" > "$RR_MARKS/%s.admit"\n' "$1"
    printf 'section "%s"\n' "$1"
    printf 'expect_eq "%s ran" "x" "x"\n' "$1"
    printf 'finish\n'
  } > "$TA/tests/$1.test.sh"
}
for _ra in ask-a ask-b ask-c; do ra_stub "$_ra"; done
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
expect_eq "ASK.2 one request for the run, keyed by the runner, whole, ended with the run's code (T2)" \
  "tests/run.sh whole 0" "$(ra_reqs)"
expect_absent "ASK.3 …and none keyed by a suite: no worker asked for itself (T2)" ".test.sh" "$(ra_reqs)"
expect_eq "ASK.4 the three batch suites all ran under that one request (T2)" "1 $(ra_id_of tests/run.sh)" \
  "$(for _ra in ask-a ask-b ask-c; do cat "$RR_MARKS/$_ra.admit" 2>/dev/null; done | sort -u | awk '{ n++; v = $0 } END { print n + 0, v }')"
expect_eq "ASK.5 ask-a ran under the run's request (T2)" "$(ra_id_of tests/run.sh)" \
  "$(cat "$RR_MARKS/ask-a.admit" 2>/dev/null)"
# ASK.6 (the solo suite ran under the run's request) RETIRED BY WAVE-35 T2 (D11): there is no solo suite.
rm -rf "$RA_GATE"; rm -f "$RR_MARKS"/*.admit
ra_drive --serial
expect_eq "ASK.7 --serial is green" "0" "$RR_RC"
expect_eq "ASK.8 --serial asks per suite too, each as work, each ended" \
  "ask-a.test.sh work 0
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
expect_eq "ASK.11 …the shim took no number, and the run asked once for itself (T2)" \
  "tests/run.sh whole 0" "$(ra_reqs)"

# ============================================================
section "§SCRUB a suite never sees the runner's store (wave-30 T9; REQ-4 AC-4.2; D8)"
# ============================================================
#
# THE CLAIM. A runner and its workers keep BIONIC_GATE_DIR for their own ask and end, but the SUITE
# PROCESS a worker starts loses it: a suite that reads the gate through the inherited variable read
# the run's store (the doctor-reads checks did), and a suite that wants a store makes its own fixture.
# Driven on a scratch tree carrying the shipped runner: a probe suite prints what it sees of the
# variable, in the parallel batch and under --serial, while the gate store the run named still
# holds the probe's own request (the ask is not scrubbed). Its second half, the timing marker
# (AC-4.1: the real roster's dry run listed the §EG-DERIVE suite as solo), RETIRED BY WAVE-35 T2
# (D11): nothing is solo, and tests/runner-width.test.sh §NO-VOID proves the marker ignored.
TS="$TMPROOT/scrub"; RS_GATE="$TMPROOT/scrub-gate"
rr_tree "$TS"
rs_probe() {  # <name> — a green suite that records the gate variable it sees
  { printf '#!/bin/bash\n'
    printf 'set -uo pipefail\n'
    printf '. "$(dirname "$0")/lib/assert.sh"\n'
    printf 'printf "%%s\\n" "BIONIC_GATE_DIR=${BIONIC_GATE_DIR:-unset}" > "$RR_MARKS/%s.seen"\n' "$1"
    printf 'section "%s"\n' "$1"
    printf 'expect_eq "%s ran" "x" "x"\n' "$1"
    printf 'finish\n'
  } > "$TS/tests/$1.test.sh"
}
rs_probe probe-a
rs_drive() {  # [mode] — the scratch runner started under a store of this section's own; RR_OUT, RR_RC
  RR_OUT="$( cd "$TS" && RR_MARKS="$RR_MARKS" BIONIC_PRESSURE_RING="$TMPROOT/scrub-ring" \
    BIONIC_NOW_EPOCH="$RR_NOW" BIONIC_TEST_JOBS_CEILING=2 BIONIC_PROBE_FREE_PCT=44 \
    BIONIC_PROBE_SWAP_PCT=0 BIONIC_PROBE_LOAD_1M=0.1 \
    env "${RR_GATE_ENV[@]}" BIONIC_GATE_DIR="$RS_GATE" bash tests/run.sh ${1:+"$1"} 2>&1 )"
  RR_RC=$?
}
rs_keys() {  # the keys of the requests in the store, each with its code, sorted
  local f
  for f in "$RS_GATE"/requests/[0-9]*; do
    [ -f "$f" ] || continue
    printf '%s %s\n' "$(sed -n 's/^key=//p' "$f" | tail -n 1)" "$(sed -n 's/^rc=//p' "$f" | tail -n 1)"
  done | sort
}
rm -rf "$RS_GATE"; rm -f "$RR_MARKS"/*.seen
rs_drive
expect_eq "SCRUB.1 the run is green" "0" "$RR_RC"
expect_eq "SCRUB.2 the probe in the batch saw no BIONIC_GATE_DIR, though the run was started under one" \
  "BIONIC_GATE_DIR=unset" "$(cat "$RR_MARKS/probe-a.seen" 2>/dev/null)"
# SCRUB.4 REWRITTEN BY WAVE-32 T2 (D1, AC-1.1; A-orch-8): a whole run's one ask is the runner's,
# so the store the run named holds that request; the behaviour change rewrites the pin.
expect_eq "SCRUB.4 …while the run's own ask landed in the run's store, ended with its code (the ask is not scrubbed)" \
  "tests/run.sh 0" "$(rs_keys)"
rm -rf "$RS_GATE"; rm -f "$RR_MARKS"/*.seen
rs_drive --serial
expect_eq "SCRUB.5 --serial is green" "0" "$RR_RC"
expect_eq "SCRUB.6 …and its probe saw no BIONIC_GATE_DIR either" "BIONIC_GATE_DIR=unset" "$(cat "$RR_MARKS/probe-a.seen" 2>/dev/null)"
expect_eq "SCRUB.7 …with the ask in the run's store as well" \
  "probe-a.test.sh 0" "$(rs_keys)"
# PAIRED CONTROL: the probe does print the variable when it is set (the readback is real output, not silence).
rm -f "$RR_MARKS/probe-a.seen"
BIONIC_GATE_DIR=control-store RR_MARKS="$RR_MARKS" bash "$TS/tests/probe-a.test.sh" >/dev/null 2>&1
expect_eq "SCRUB.8 the probe run by hand under a store reads it back" "BIONIC_GATE_DIR=control-store" \
  "$(cat "$RR_MARKS/probe-a.seen" 2>/dev/null)"

# ============================================================
finish
