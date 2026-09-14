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
# reads or writes the machine's real pressure ring.
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
    bash tests/run.sh ${mode:+"$mode"} 2>&1 )"
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
  bash tests/run.sh 2>&1 )"
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
  bash tests/run.sh --serial 2>&1 )"
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
  bash tests/run.sh --dry-run 2>&1 )"
expect_contains "8.9 --dry-run still prints the width" "JOBS=2" "$RR8_DRY_OUT"
expect_contains "8.10 …and lists the solo suite by name" "aaa-solo.test.sh" "$RR8_DRY_OUT"
expect_contains "8.11 …labelled solo, not folded silently into the width" "solo" "$RR8_DRY_OUT"
# PAIRED NEGATIVE: a plain sibling is not mislabelled solo.
expect_absent "8.12 …and an ordinary sibling is not listed as solo" "sib-a.test.sh" \
  "$(printf '%s\n' "$RR8_DRY_OUT" | grep -i solo)"

finish
