#!/bin/bash
# tests/impact.test.sh — the impacted-suite derivation, and its planted-edit proof.
# wave-01-verification-cannot-lie slice S12; spec AC-18 (the derivation) and
# AC-19 (completeness by planted edit).
#
# WHAT IS UNDER TEST. `tests/lib/impact.sh <file>...` prints the gating suites
# that read those files — one line per suite, `suite<TAB>reason`, sorted, no
# duplicates. It is the ONE owner of "this change affects that" (design ledger
# D2, "the tree owns impact"): the dispatch wall, the writer-side budget guard
# and the landing reconcile all ask this one question of this one program.
#
# THE EDGE KINDS, and where each comes from in the tree:
#
#   self              the file IS the suite
#   source            the suite sources the file (`. "$(dirname "$0")/lib/x.sh"`)
#   anchor            the suite doctors the file (`grep -v` / `sed` against it)
#   pin               the suite pins the file's text (`grep -q` / `has_pin`)
#   path-ref          the suite names the path, over the root aliases
#   payload-copy      the suite names the payload ROOT, so it reads every file
#                     under it (the ten whole-payload copiers, code map §1.4)
#   dir-ref           the suite names some other directory, same expansion
#   transitive-lib    the suite sources a tests/lib helper that reads the file
#   transitive-doctor payload/scripts/doctor.sh sources the file, and the suite
#                     reads doctor.sh (code map §3.5: one hop from the suite)
#   transitive-script the same rule for the other payload/scripts/*.sh
#
# WHY A FIXTURE TREE FOR THE EDGE KINDS (§A–§C). Asserting edge kinds against
# the real tree would pin this suite to whatever 51 suites happen to reference
# today: every unrelated edit to any suite would rewrite the expected sets, and
# an assertion nobody can re-derive by hand is a pin, not a test (memory
# "good-tests-doctrine"). So each edge kind is proved over a MINIATURE tree this
# suite builds and owns, where the whole dependency graph fits on a screen — and
# every positive is paired with a MUTATION that removes the edge and re-proves
# the same call goes empty (memory "no-vacuous-tests-at-authoring": a positive
# assertion alone cannot tell a real derivation from a program that prints
# everything).
#
# WHAT THE REAL TREE IS STILL ASKED (§D). Only facts a reader can re-derive from
# the code map by hand: docs-pins doctors session-poker.sh (§1.2 rows 5–6), all
# 51 suites source tests/lib/resolve-roots.sh (§3.5), the ten named suites read
# the whole payload (§1.4). Those are properties of the tree, cited to their
# measurement, not a snapshot of this program's output.
#
# THE PLANTED-EDIT PROOF (§F, opt-in). AC-19 asks for a completeness criterion
# that runs REAL suites against a mutated scratch tree and checks that the
# derived set is a superset of the suites that actually go red. That costs
# whole-roster runs — minutes, not the sub-second every other section takes — so
# it does not run in the gating roster. `BIONIC_IMPACT_PLANTED=1` runs it, and
# its authoring-time output is committed as the durable record at
# .bionic/docs/record/wave-verification-cannot-lie/s12-planted-edits.log
# (memory "red-evidence-is-perishable": the red counts die at green, the
# mutation-and-restore log does not).
#
# Usage: bash tests/impact.test.sh
#   BIONIC_IMPACT_PLANTED=1 bash tests/impact.test.sh    # + the §F proof
#   BIONIC_IMPACT_PLANTED_LOG=<path>                     # where §F writes

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"

REPO="${BIONIC_SCRIPTS_DIR}"
IMPACT="${REPO}/tests/lib/impact.sh"

PASS=0; FAIL=0
pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; [ -n "${2:-}" ] && echo "  $2"; FAIL=$((FAIL + 1)); }
section() { echo; echo "── $1 ─────────────────────────────────────────"; }

expect_eq() { # expect_eq <name> <expected> <actual>
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "expected [$2] got [$3]"; fi
}
expect_has() { # expect_has <name> <needle> <haystack>
  case "$3" in
    *"$2"*) pass "$1" ;;
    *) fail "$1" "[$2] not found in [$3]" ;;
  esac
}
expect_lacks() { # expect_lacks <name> <needle> <haystack>
  case "$3" in
    *"$2"*) fail "$1" "[$2] unexpectedly present in [$3]" ;;
    *) pass "$1" ;;
  esac
}

# ── §0 the subject exists and parses ────────────────────────────────────────
# Nothing below can mean anything if the derivation is missing: an absent
# program makes every `$(... | grep ...)` empty, which is indistinguishable
# from a correct empty answer. Prove the subject first, and stop if it is gone.
section "§0 the subject"

if [ -f "$IMPACT" ]; then
  pass "tests/lib/impact.sh exists"
else
  fail "tests/lib/impact.sh exists" "$IMPACT"
  echo
  echo "Gating: $PASS passed, $FAIL failed"
  exit 1
fi

if bash -n "$IMPACT" 2>/dev/null; then
  pass "tests/lib/impact.sh parses under bash -n"
else
  fail "tests/lib/impact.sh parses under bash -n" "$(bash -n "$IMPACT" 2>&1)"
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# suites() <root> <file>...   → the suite column, sorted, newline-separated
suites() {
  local root="$1"; shift
  BIONIC_IMPACT_ROOT="$root" bash "$IMPACT" "$@" 2>/dev/null | cut -f1
}
# reason_for() <root> <suite> <file>...   → the reason column for one suite
reason_for() {
  local root="$1" want="$2"; shift 2
  BIONIC_IMPACT_ROOT="$root" bash "$IMPACT" "$@" 2>/dev/null \
    | awk -F'\t' -v w="$want" '$1==w{print $2}'
}
# oneline() — the suite column as a single space-joined string, for expect_has
oneline() { suites "$@" | tr '\n' ' '; }

# ── the fixture tree ────────────────────────────────────────────────────────
# A whole repo in eleven files. Every edge kind the derivation claims is
# expressed exactly once here, so the expected sets below are readable off this
# block rather than off the program's output.
#
#   tests/a.test.sh   pins hooks/h1.sh                       → pin
#   tests/b.test.sh   sources tests/lib/helper.sh            → source
#                     …and helper.sh reads lib/run.sh        → transitive-lib
#   tests/c.test.sh   names the payload ROOT                 → payload-copy
#   tests/d.test.sh   doctors hooks/h1.sh via grep -v        → anchor
#   tests/e.test.sh   runs payload/scripts/doctor.sh         → transitive-doctor
#   tests/f.test.sh   pins tests/run.sh                      → pin
#   tests/g.test.sh   names the hooks DIRECTORY              → dir-ref
#   payload/hooks is a symlink to ../hooks, as in the real tree.
mk_fixture() { # mk_fixture <dir>
  local fx="$1"
  mkdir -p "$fx/tests/lib" "$fx/hooks" "$fx/payload/scripts/lib"
  ln -s ../hooks "$fx/payload/hooks"

  printf '#!/bin/bash\necho h1\n' >"$fx/hooks/h1.sh"
  printf '#!/bin/bash\necho h2\n' >"$fx/hooks/h2.sh"
  printf '#!/bin/bash\necho width\n' >"$fx/payload/scripts/lib/width.sh"
  printf '#!/bin/bash\necho run\n' >"$fx/payload/scripts/lib/run.sh"
  printf '#!/bin/bash\nDOCTOR_LIB="$(dirname "$0")/lib"\n. "${DOCTOR_LIB}/width.sh"\n' \
    >"$fx/payload/scripts/doctor.sh"

  printf '#!/bin/bash\n. "$(dirname "$0")/lib/resolve-roots.sh"\n' >"$fx/tests/lib/resolve-roots.sh"
  printf '#!/bin/bash\n. "${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/run.sh"\n' \
    >"$fx/tests/lib/helper.sh"

  printf '#!/bin/bash\n. "$(dirname "$0")/lib/resolve-roots.sh"\nREPO="${BIONIC_SCRIPTS_DIR}"\ngrep -q hello "${REPO}/hooks/h1.sh"\n' >"$fx/tests/a.test.sh"
  printf '#!/bin/bash\n. "$(dirname "$0")/lib/resolve-roots.sh"\n. "$(dirname "$0")/lib/helper.sh"\n' >"$fx/tests/b.test.sh"
  printf '#!/bin/bash\n. "$(dirname "$0")/lib/resolve-roots.sh"\nREPO="${BIONIC_SCRIPTS_DIR}"\nPAYLOAD="${REPO}/payload"\ncp -R "$PAYLOAD" "$TMP/p"\n' >"$fx/tests/c.test.sh"
  printf '#!/bin/bash\n. "$(dirname "$0")/lib/resolve-roots.sh"\ngrep -v drop "$BIONIC_HOOKS_DIR/h1.sh" >mutant\n' >"$fx/tests/d.test.sh"
  printf '#!/bin/bash\n. "$(dirname "$0")/lib/resolve-roots.sh"\nREPO="${BIONIC_SCRIPTS_DIR}"\nbash "${REPO}/payload/scripts/doctor.sh"\n' >"$fx/tests/e.test.sh"
  printf '#!/bin/bash\n. "$(dirname "$0")/lib/resolve-roots.sh"\ngrep -q pressure "${BIONIC_SCRIPTS_DIR}/tests/run.sh"\n' >"$fx/tests/f.test.sh"
  printf '#!/bin/bash\n. "$(dirname "$0")/lib/resolve-roots.sh"\nREPO="${BIONIC_SCRIPTS_DIR}"\nfor f in "$REPO/hooks"/*.sh; do echo "$f"; done\n' >"$fx/tests/g.test.sh"

  {
    printf '#!/bin/bash\n'
    for s in a b c d e f g; do
      printf 'run "%s.test.sh" bash tests/%s.test.sh\n' "$s" "$s"
    done
  } >"$fx/tests/run.sh"
}

FX="$TMP/fx"
mk_fixture "$FX"

# ── §A one edge kind at a time ──────────────────────────────────────────────
section "§A the edge kinds"

# self — a change to a suite reaches that suite, and no other. Without this the
# wall would let a writer edit a suite and never run it.
expect_eq "self: editing a suite derives that suite" \
  "a.test.sh" "$(suites "$FX" tests/a.test.sh)"

# source — b sources tests/lib/helper.sh; nothing else does.
expect_eq "source: the sourcing suite, and only it" \
  "b.test.sh" "$(suites "$FX" tests/lib/helper.sh)"
expect_eq "source: the reason is named" \
  "source" "$(reason_for "$FX" b.test.sh tests/lib/helper.sh | cut -d: -f1)"

# transitive-lib — helper.sh reads payload/scripts/lib/run.sh, so b reads it
# without naming it. The suite-level grep the code map warns about (§3.5) misses
# exactly this edge, which is why it has its own kind.
expect_has "transitive-lib: the sourcing suite inherits its helper's reads" \
  "b.test.sh" "$(oneline "$FX" payload/scripts/lib/run.sh)"
expect_eq "transitive-lib: the reason is named" \
  "transitive-lib" "$(reason_for "$FX" b.test.sh payload/scripts/lib/run.sh | cut -d: -f1)"

# transitive-doctor — doctor.sh sources lib/width.sh; e runs doctor.sh and never
# names width.sh. This is the FIX_LINES_OTHER edge from code map §3.5.
expect_has "transitive-doctor: a doctor.sh runner inherits doctor.sh's libs" \
  "e.test.sh" "$(oneline "$FX" payload/scripts/lib/width.sh)"
expect_eq "transitive-doctor: the reason is named" \
  "transitive-doctor" "$(reason_for "$FX" e.test.sh payload/scripts/lib/width.sh | cut -d: -f1)"

# payload-copy — c names the payload root, so every file under payload/ reaches
# it, including files reached only through payload/hooks' symlink.
expect_has "payload-copy: a payload-root namer reads a file under payload/" \
  "c.test.sh" "$(oneline "$FX" payload/scripts/lib/run.sh)"
expect_has "payload-copy: …and a file reached only through payload/hooks" \
  "c.test.sh" "$(oneline "$FX" hooks/h1.sh)"
expect_eq "payload-copy: the reason is named" \
  "payload-copy" "$(reason_for "$FX" c.test.sh hooks/h1.sh | cut -d: -f1)"

# anchor and pin — both are path references; the reason column separates them,
# because a moved anchor fails silently and a moved pin fails loudly (§1.1).
expect_eq "anchor: a grep -v doctoring is reported as an anchor" \
  "anchor" "$(reason_for "$FX" d.test.sh hooks/h1.sh | cut -d: -f1)"
expect_eq "pin: a grep -q is reported as a pin" \
  "pin" "$(reason_for "$FX" a.test.sh hooks/h1.sh | cut -d: -f1)"

# dir-ref — g globs the hooks directory. A per-file grep sees no filename here
# (code map §3.4 calls it "a glob, not a path"), so the directory expansion is
# the only thing that finds the edge.
expect_has "dir-ref: a directory glob reaches every file under it" \
  "g.test.sh" "$(oneline "$FX" hooks/h2.sh)"
expect_eq "dir-ref: the reason is named" \
  "dir-ref" "$(reason_for "$FX" g.test.sh hooks/h2.sh | cut -d: -f1)"

# tests/run.sh — f pins it. This is the 33-suite registration-pin edge (§1.4).
expect_has "pin: a tests/run.sh registration pin is an edge" \
  "f.test.sh" "$(oneline "$FX" tests/run.sh)"

# ── §B every edge kind can go away ──────────────────────────────────────────
# The mutation half. Each positive above is re-run against a fixture with that
# one edge deleted; the suite must DISAPPEAR from the answer. A derivation that
# printed every suite unconditionally would pass §A entirely and fail here.
section "§B the mutation half — remove the edge, lose the suite"

mut() { # mut <name> — a fresh fixture copy to mutate
  local d="$TMP/mut-$1"
  rm -rf "$d"; mkdir -p "$d"
  ( cd "$FX" && tar cf - . ) | ( cd "$d" && tar xf - )
  echo "$d"
}

M="$(mut source)"
printf '#!/bin/bash\n. "$(dirname "$0")/lib/resolve-roots.sh"\n' >"$M/tests/b.test.sh"
expect_eq "source: dropping the source line empties the answer" \
  "" "$(suites "$M" tests/lib/helper.sh)"

M="$(mut translib)"
printf '#!/bin/bash\necho nothing\n' >"$M/tests/lib/helper.sh"
expect_lacks "transitive-lib: emptying the helper drops the suite" \
  "b.test.sh" "$(oneline "$M" payload/scripts/lib/run.sh)"

M="$(mut transdoctor)"
printf '#!/bin/bash\necho nothing\n' >"$M/payload/scripts/doctor.sh"
expect_lacks "transitive-doctor: a doctor.sh that sources nothing drops the suite" \
  "e.test.sh" "$(oneline "$M" payload/scripts/lib/width.sh)"

M="$(mut payloadcopy)"
printf '#!/bin/bash\n. "$(dirname "$0")/lib/resolve-roots.sh"\necho no payload here\n' >"$M/tests/c.test.sh"
expect_lacks "payload-copy: dropping the payload-root reference drops the suite" \
  "c.test.sh" "$(oneline "$M" payload/scripts/lib/run.sh)"

M="$(mut symlink)"
rm "$M/payload/hooks"
mkdir -p "$M/payload/hooks"
expect_lacks "payload-copy: with payload/hooks no longer a symlink, hooks/h1.sh is outside payload" \
  "c.test.sh" "$(oneline "$M" hooks/h1.sh)"

M="$(mut dirref)"
printf '#!/bin/bash\n. "$(dirname "$0")/lib/resolve-roots.sh"\necho no directory here\n' >"$M/tests/g.test.sh"
expect_lacks "dir-ref: dropping the directory reference drops the suite" \
  "g.test.sh" "$(oneline "$M" hooks/h2.sh)"

M="$(mut pathref)"
printf '#!/bin/bash\n. "$(dirname "$0")/lib/resolve-roots.sh"\necho nothing\n' >"$M/tests/a.test.sh"
printf '#!/bin/bash\n. "$(dirname "$0")/lib/resolve-roots.sh"\necho nothing\n' >"$M/tests/d.test.sh"
printf '#!/bin/bash\n. "$(dirname "$0")/lib/resolve-roots.sh"\necho nothing\n' >"$M/tests/c.test.sh"
printf '#!/bin/bash\n. "$(dirname "$0")/lib/resolve-roots.sh"\necho nothing\n' >"$M/tests/g.test.sh"
expect_eq "path-ref: with every reader rewritten, hooks/h1.sh reaches nobody" \
  "" "$(suites "$M" hooks/h1.sh)"

# ── §C the four root aliases are one file ───────────────────────────────────
# Code map's layout note: hooks/X, payload/hooks/X, $BIONIC_HOOKS_DIR/X and
# $BIONIC_HOOKS_DIR/../payload/hooks/X are four spellings of ONE file. A
# derivation that does not canonicalise them under-counts readers — the exact
# failure the note warns about.
section "§C the root aliases"

A_CANON="$(suites "$FX" hooks/h1.sh)"
expect_eq "alias: payload/hooks/h1.sh derives the same set as hooks/h1.sh" \
  "$A_CANON" "$(suites "$FX" payload/hooks/h1.sh)"
expect_eq "alias: an absolute path derives the same set" \
  "$A_CANON" "$(suites "$FX" "$FX/hooks/h1.sh")"
expect_eq "alias: a path through .. derives the same set" \
  "$A_CANON" "$(suites "$FX" payload/hooks/../hooks/h1.sh)"

# The four SPELLINGS inside a suite must all be found. One fixture suite per
# alias, each naming h2.sh a different way; all four must be derived.
M="$(mut aliases)"
printf '#!/bin/bash\nREPO="${BIONIC_SCRIPTS_DIR}"\ngrep -q x "${REPO}/hooks/h2.sh"\n' >"$M/tests/a.test.sh"
printf '#!/bin/bash\ngrep -q x "$BIONIC_HOOKS_DIR/h2.sh"\n' >"$M/tests/b.test.sh"
printf '#!/bin/bash\nREPO_ROOT="${BIONIC_SCRIPTS_DIR}"\ngrep -q x "$REPO_ROOT/payload/hooks/h2.sh"\n' >"$M/tests/c.test.sh"
printf '#!/bin/bash\ngrep -q x "$BIONIC_HOOKS_DIR/../payload/hooks/h2.sh"\n' >"$M/tests/d.test.sh"
printf '#!/bin/bash\necho nothing\n' >"$M/tests/e.test.sh"
printf '#!/bin/bash\necho nothing\n' >"$M/tests/f.test.sh"
printf '#!/bin/bash\necho nothing\n' >"$M/tests/g.test.sh"
expect_eq "alias: all four in-suite spellings of one file are found" \
  "a.test.sh b.test.sh c.test.sh d.test.sh" "$(suites "$M" hooks/h2.sh | tr '\n' ' ' | sed 's/ $//')"

# ── §D the real tree, on facts the code map measured ────────────────────────
# Only claims a reader can re-derive by hand from
# .bionic/docs/record/wave-verification-cannot-lie/research-code-map.md.
section "§D the real tree"

RT_ROOTS="$(oneline "$REPO" tests/lib/resolve-roots.sh)"
RT_ALL="$(suites "$REPO" tests/lib/resolve-roots.sh | wc -l | tr -d ' ')"
RT_ROSTER="$(/usr/bin/grep -c '^run "' "$REPO/tests/run.sh" 2>/dev/null || grep -c '^run "' "$REPO/tests/run.sh")"
# code map §3.5: resolve-roots.sh is sourced by every suite in the roster.
expect_eq "real: resolve-roots.sh reaches every suite in the roster" \
  "$RT_ROSTER" "$RT_ALL"

# code map §1.2 rows 5–6: docs-pins doctors hooks/session-poker.sh.
RT_POKER="$(oneline "$REPO" hooks/session-poker.sh)"
expect_has "real: docs-pins reads hooks/session-poker.sh" "docs-pins.test.sh" "$RT_POKER"
expect_has "real: session-poker's own suite reads it" "session-poker.test.sh" "$RT_POKER"
expect_eq "real: docs-pins' reason for session-poker.sh is an anchor" \
  "anchor" "$(reason_for "$REPO" docs-pins.test.sh hooks/session-poker.sh | cut -d: -f1)"

# code map §1.4: the ten named suites copy the whole payload tree, so a file
# under payload/ that none of them names still reaches all ten.
RT_WIDTH="$(oneline "$REPO" payload/scripts/lib/width.sh)"
for s in doctor-fleet doctor-patrol doctor-reads doctor-restart doctor-version \
         doctor-walls fresh-home loader patrol-marker command-relay; do
  expect_has "real: $s.test.sh reads payload/scripts/lib/width.sh" \
    "$s.test.sh" "$RT_WIDTH"
done

# tests/run.sh's readers. Code map §1.4 puts them at 33, from
# `grep -l 'tests/run\.sh' tests/*.test.sh`. That count is an UPPER BOUND and
# this suite must not assert it: ten of the thirty-four files that grep finds
# today mention the runner in a comment or hand its name to a classifier as a
# string literal (`case_is suite 'bash tests/run.sh'`, cmd-class.test.sh:107),
# and neither is a read. What IS a read, and what a reader can check by hand, is
# the registration pin — a suite asserting its own `run "<self>"` line is present
# in the roster. Every suite carrying one must be derived; the set is computed
# from the tree here rather than written down, so it cannot go stale.
RT_PINNED=""
RT_MISSED=""
RT_RUNSH_SET="$(suites "$REPO" tests/run.sh)"
for f in "$REPO"/tests/*.test.sh; do
  b="$(basename "$f")"
  /usr/bin/grep -q "run \"$b\"" "$f" 2>/dev/null || continue
  RT_PINNED="$RT_PINNED $b"
  case "$RT_RUNSH_SET" in
    *"$b"*) : ;;
    *) RT_MISSED="$RT_MISSED $b" ;;
  esac
done
RT_NPIN="$(printf '%s\n' $RT_PINNED | grep -c .)"
if [ "$RT_NPIN" -lt 10 ]; then
  fail "real: the registration-pin census found suites to check" "found $RT_NPIN"
elif [ -n "$RT_MISSED" ]; then
  fail "real: every registration-pinned suite is derived from tests/run.sh" \
    "missing:$RT_MISSED"
else
  pass "real: all $RT_NPIN registration-pinned suites are derived from tests/run.sh"
fi

# ── §E the output contract ──────────────────────────────────────────────────
# S13's wall does `cut -f1` on this and writes the result to a roster row, so
# the shape is a contract, not a convenience.
section "§E the output contract"

E_OUT="$(BIONIC_IMPACT_ROOT="$FX" bash "$IMPACT" hooks/h1.sh 2>/dev/null)"
E_LINES="$(printf '%s\n' "$E_OUT" | grep -c .)"
E_UNIQ="$(printf '%s\n' "$E_OUT" | cut -f1 | sort -u | grep -c .)"
expect_eq "one line per suite — no duplicate suite column" "$E_LINES" "$E_UNIQ"
expect_eq "the suite column is sorted" \
  "$(printf '%s\n' "$E_OUT" | cut -f1)" "$(printf '%s\n' "$E_OUT" | cut -f1 | sort)"
expect_eq "every line has exactly two tab-separated fields" \
  "" "$(printf '%s\n' "$E_OUT" | awk -F'\t' 'NF!=2{print NR}')"
expect_eq "every reason carries the file it came from" \
  "" "$(printf '%s\n' "$E_OUT" | awk -F'\t' '$2 !~ /:hooks\/h1\.sh$/{print $2}')"

# A file nobody reads derives nobody. The path has to sit outside every directory
# any fixture suite names: `hooks/anything.sh` would legitimately derive the
# payload copier and the hooks globber, because if that file existed they WOULD
# read it — a directory reference is a claim about the directory, not about the
# files in it on the day the question is asked, which is also what lets a DELETED
# file still derive its readers.
BIONIC_IMPACT_ROOT="$FX" bash "$IMPACT" design/nobody-reads-this.md >"$TMP/none.out" 2>/dev/null
N_RC=$?
expect_eq "a file no suite reads derives nothing" "" "$(cat "$TMP/none.out")"
expect_eq "…and says so with exit 0, not an error" "0" "$N_RC"
expect_has "…while a not-yet-created file under a copied directory still derives its readers" \
  "c.test.sh" "$(oneline "$FX" hooks/not-created-yet.sh)"

BIONIC_IMPACT_ROOT="$FX" bash "$IMPACT" >"$TMP/usage.out" 2>"$TMP/usage.err"
U_RC=$?
expect_eq "no arguments is a usage error, not an empty answer" "2" "$U_RC"
expect_eq "…and the usage goes to stderr, leaving stdout clean" "" "$(cat "$TMP/usage.out")"
expect_has "…and the usage names the program" "impact.sh" "$(cat "$TMP/usage.err")"

expect_eq "several files in one call answer as their union" \
  "$(printf '%s\n%s\n' "$(suites "$FX" hooks/h1.sh)" "$(suites "$FX" tests/lib/helper.sh)" | sort -u | grep -c .)" \
  "$(suites "$FX" hooks/h1.sh tests/lib/helper.sh | grep -c .)"

# ── §F the planted-edit proof (opt-in) ──────────────────────────────────────
# AC-19. For one planted edit in each file class, the derived set ⊇ the suites
# that actually go RED when that edit is applied to a scratch tree.
#
# HOW ⊇ IS FALSIFIED, and therefore what has to run: a suite that goes red and
# is NOT in the derived set. Suites INSIDE the derived set can prove only that
# the edit bites at all. So each class runs the derived set's witness (one suite,
# to show the mutation is real) plus THE WHOLE COMPLEMENT — every roster suite
# outside the derived set — because that is where a counterexample would live.
#
# The planted edits are maximal breakage on purpose (an unconditional early exit,
# a syntax error): a small edit makes a small red set and a weak superset claim.
section "§F the planted-edit proof"

if [ "${BIONIC_IMPACT_PLANTED:-0}" != "1" ]; then
  echo "SKIP: §F not requested (BIONIC_IMPACT_PLANTED=1 to run it; the"
  echo "      authoring-time record is committed at .bionic/docs/record/"
  echo "      wave-verification-cannot-lie/s12-planted-edits.log)"
else
  PLOG="${BIONIC_IMPACT_PLANTED_LOG:-$TMP/planted-edits.log}"
  : >"$PLOG"
  echo "planted-edit proof — $(date -u '+%Y-%m-%dT%H:%M:%SZ')" >>"$PLOG"
  echo "repo: $REPO" >>"$PLOG"
  echo "interpreter: $(bash --version | head -1)" >>"$PLOG"

  SCRATCH="$TMP/scratch"
  mkdir -p "$SCRATCH"
  ( cd "$REPO" && tar cf - --exclude=.git --exclude=.worktrees --exclude=.bionic . ) \
    | ( cd "$SCRATCH" && tar xf - )
  echo "scratch tree: a copy of the checkout, .git/.worktrees/.bionic excluded" >>"$PLOG"

  # run_suite <tree> <label> → prints "pass" or "fail"; never fixes anything.
  run_suite() {
    local tree="$1" label="$2" rc
    ( cd "$tree" && bash "tests/${label}" ) >"$TMP/rs.out" 2>&1
    rc=$?
    [ "$rc" -eq 0 ] && echo pass || echo fail
  }

  ROSTER="$(/usr/bin/grep -oE '^run "[^"]+"' "$SCRATCH/tests/run.sh" | sed 's/^run "//; s/"$//')"

  # plant <class> <file> <how>   — mutate, derive, run the complement, restore.
  plant() {
    local class="$1" file="$2" how="$3"
    local derived complement red_out=0 witness="" n_comp=0 n_red_outside=0

    derived="$(BIONIC_IMPACT_ROOT="$SCRATCH" bash "$IMPACT" "$file" | cut -f1 | sort -u)"
    {
      echo
      echo "════════════════════════════════════════════════════════════════"
      echo "class:   $class"
      echo "file:    $file"
      echo "edit:    $how"
      echo "derived: $(printf '%s ' $derived)"
      echo "derived count: $(printf '%s\n' "$derived" | grep -c .)"
    } >>"$PLOG"

    cp "$SCRATCH/$file" "$TMP/restore.bak"
    case "$how" in
      early-exit) printf '%s\n' 'exit 99' | cat - "$SCRATCH/$file" >"$TMP/m" && mv "$TMP/m" "$SCRATCH/$file" ;;
      syntax)     printf '\nif then fi(((\n' >>"$SCRATCH/$file" ;;
      corrupt)    printf '\nBIONIC_IMPACT_PLANTED_CORRUPTION\n' >>"$SCRATCH/$file" ;;
    esac

    # the witness: one derived suite must actually go red, or the edit is inert
    # and the whole superset claim is vacuous for this class.
    for w in $derived; do
      if [ "$(run_suite "$SCRATCH" "$w")" = "fail" ]; then witness="$w"; break; fi
    done

    complement="$(printf '%s\n' $ROSTER | sort -u | comm -23 - <(printf '%s\n' "$derived" | sort -u))"
    for c in $complement; do
      n_comp=$((n_comp + 1))
      if [ "$(run_suite "$SCRATCH" "$c")" = "fail" ]; then
        n_red_outside=$((n_red_outside + 1))
        echo "  RED OUTSIDE THE DERIVED SET: $c" >>"$PLOG"
      fi
    done

    mv "$TMP/restore.bak" "$SCRATCH/$file"

    {
      echo "witness (a derived suite that went red): ${witness:-NONE}"
      echo "complement run: $n_comp suites"
      echo "red outside the derived set: $n_red_outside"
    } >>"$PLOG"

    if [ -z "$witness" ]; then
      fail "planted [$class]: the edit makes at least one derived suite red" \
        "no derived suite failed — the planted edit is inert"
    else
      pass "planted [$class]: the edit makes at least one derived suite red ($witness)"
    fi
    if [ "$n_red_outside" -eq 0 ]; then
      pass "planted [$class]: derived ⊇ red — $n_comp complement suites, none red"
    else
      fail "planted [$class]: derived ⊇ red" \
        "$n_red_outside of $n_comp complement suites went red; see $PLOG"
    fi
  }

  plant "a hook"                     "hooks/protect-main.sh"           early-exit
  plant "a lib the doctor sources"   "payload/scripts/lib/width.sh"    early-exit
  plant "a tests/lib helper"         "tests/lib/bound-marker.sh"       syntax
  plant "tests/run.sh"               "tests/run.sh"                    corrupt
  plant "a whole-payload-copied file" "payload/scripts/lib/patrol.sh"  early-exit

  echo
  echo "planted-edit log: $PLOG"
fi

echo
echo "──────────────────────────────────────────────"
echo "Gating: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
