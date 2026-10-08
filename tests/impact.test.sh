#!/bin/bash
# tests/impact.test.sh — the impacted-suite derivation, and its planted-edit proof.
# wave-01-verification-cannot-lie task S12; spec AC-18 (the derivation) and
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
# an assertion nobody can re-derive by hand is a pin, not a test
# (.claude/rules/test-harness.md, "Good tests"). So each edge kind is proved over a MINIATURE tree this
# suite builds and owns, where the whole dependency graph fits on a screen — and
# every positive is paired with a MUTATION that removes the edge and re-proves
# the same call goes empty (.claude/rules/test-harness.md, "Anti-vacuity": a positive
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
# (RED evidence is perishable: the red counts die at green, the mutation-and-restore
# log does not).
#
# Usage: bash tests/impact.test.sh
#   BIONIC_IMPACT_PLANTED=1 bash tests/impact.test.sh    # + the §F proof
#   BIONIC_IMPACT_PLANTED_LOG=<path>                     # where §F writes

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"

REPO="${BIONIC_SCRIPTS_DIR}"
IMPACT="${REPO}/tests/lib/impact.sh"

# NO PRIVATE ASSERTION NAMES HERE (review-b B-6, folded in at Step 6). This suite
# once carried `pass`/`fail` wrappers over ok/no and `expect_has`/`expect_lacks`,
# which were argument-for-argument the framework's `expect_contains` and
# `expect_absent`. The adoption wall did not refuse them — it refuses only the
# exact names the framework OWNS — so the wave that removed 37 private spellings
# from 53 suites added four back in its own new suite. Worse, `_tf_scan` derives
# call tokens matching `ok|no|expect_[a-z_]+|anchor`: `pass` and `fail` are
# outside that set, so an undefined one would have slipped past the load-time
# derivation (AC-14) and surfaced only through the runner's stderr-strict arm.

# ── §0 the subject exists and parses ────────────────────────────────────────
# Nothing below can mean anything if the derivation is missing: an absent
# program makes every `$(... | grep ...)` empty, which is indistinguishable
# from a correct empty answer. Prove the subject first, and stop if it is gone.
section "§0 the subject"

if [ -f "$IMPACT" ]; then
  ok "tests/lib/impact.sh exists"
else
  no "tests/lib/impact.sh exists" "$IMPACT"
  finish
fi

if bash -n "$IMPACT" 2>/dev/null; then
  ok "tests/lib/impact.sh parses under bash -n"
else
  no "tests/lib/impact.sh parses under bash -n" "$(bash -n "$IMPACT" 2>&1)"
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
#   tests/h.test.sh   runs hooks/h3.sh, which sources
#                     payload/scripts/lib/hooklib.sh        → transitive-hook
#   payload/hooks is a symlink to ../hooks, as in the real tree.
mk_fixture() { # mk_fixture <dir>
  local fx="$1"
  mkdir -p "$fx/tests/lib" "$fx/hooks" "$fx/payload/scripts/lib"
  ln -s ../hooks "$fx/payload/hooks"

  printf '#!/bin/bash\necho h1\n' >"$fx/hooks/h1.sh"
  printf '#!/bin/bash\necho h2\n' >"$fx/hooks/h2.sh"
  printf '#!/bin/bash\necho width\n' >"$fx/payload/scripts/lib/width.sh"
  printf '#!/bin/bash\necho run\n' >"$fx/payload/scripts/lib/run.sh"
  printf '#!/bin/bash\necho hooklib\n' >"$fx/payload/scripts/lib/hooklib.sh"
  # h3 is the hook with a library of its own — the transitive-hook edge. It is a
  # SEPARATE hook from h1 and h2 so that adding it moves no set another row pins.
  printf '#!/bin/bash\nHOOK_LIB="$(dirname "$0")/../payload/scripts/lib"\n. "${HOOK_LIB}/hooklib.sh"\n' \
    >"$fx/hooks/h3.sh"
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
  printf '#!/bin/bash\n. "$(dirname "$0")/lib/resolve-roots.sh"\nbash "$BIONIC_HOOKS_DIR/h3.sh"\n' >"$fx/tests/h.test.sh"

  {
    printf '#!/bin/bash\n'
    for s in a b c d e f g h; do
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

# self, not-yet-existing (REQ-4 AC-4.1/4.2, D6). A writer's brief names a suite
# it has not created yet: impact.sh:601 built the self edge exclusively from
# `ls tests/*.test.sh` at graph-build time, so a not-yet-existing path derived
# nothing and the writer creating it was refused permission to run it (wave-14
# A-orch-62; research row 4a, proven live: `bash tests/lib/impact.sh
# tests/brand-new-thing.test.sh` on the real tree prints three dir-ref lines and
# no self edge). The self edge is a fact about the ARGUMENT's shape — does it
# look like tests/<x>.test.sh — not about whether `ls` found it at graph-build
# time, so it has to fire at query time, whether or not the file exists.
expect_eq "self: a not-yet-existing tests/*.test.sh path still derives itself" \
  "brand-new.test.sh" "$(suites "$FX" tests/brand-new.test.sh)"
expect_eq "self: the reason for the not-yet-existing path is self, not absent" \
  "self" "$(reason_for "$FX" brand-new.test.sh tests/brand-new.test.sh | cut -d: -f1)"
# PAIRED: this does not widen to every path that merely looks like it belongs
# under tests/ — a non-.test.sh file under tests/lib, or any path outside
# tests/ altogether, still derives no self edge and no suite at all.
expect_eq "self: a non-suite path under tests/lib gains no self edge" \
  "" "$(suites "$FX" tests/lib/brand-new.sh)"
expect_eq "self: a non-suite path outside tests/ gains no self edge" \
  "" "$(suites "$FX" lib/brand-new.sh)"
# PAIRED: an EXISTING suite's own self edge is unmoved by this — still exactly
# one line, still reason self, not doubled by a synthesized edge alongside the
# graph's real one.
expect_eq "self: an existing suite still derives exactly one line, not doubled" \
  "1" "$(BIONIC_IMPACT_ROOT="$FX" bash "$IMPACT" tests/a.test.sh 2>/dev/null | grep -c .)"

# source — b sources tests/lib/helper.sh; nothing else does.
expect_eq "source: the sourcing suite, and only it" \
  "b.test.sh" "$(suites "$FX" tests/lib/helper.sh)"
expect_eq "source: the reason is named" \
  "source" "$(reason_for "$FX" b.test.sh tests/lib/helper.sh | cut -d: -f1)"

# transitive-lib — helper.sh reads payload/scripts/lib/run.sh, so b reads it
# without naming it. The suite-level grep the code map warns about (§3.5) misses
# exactly this edge, which is why it has its own kind.
expect_contains "transitive-lib: the sourcing suite inherits its helper's reads" \
  "b.test.sh" "$(oneline "$FX" payload/scripts/lib/run.sh)"
expect_eq "transitive-lib: the reason is named" \
  "transitive-lib" "$(reason_for "$FX" b.test.sh payload/scripts/lib/run.sh | cut -d: -f1)"

# transitive-doctor — doctor.sh sources lib/width.sh; e runs doctor.sh and never
# names width.sh. This is the FIX_LINES_OTHER edge from code map §3.5.
expect_contains "transitive-doctor: a doctor.sh runner inherits doctor.sh's libs" \
  "e.test.sh" "$(oneline "$FX" payload/scripts/lib/width.sh)"
expect_eq "transitive-doctor: the reason is named" \
  "transitive-doctor" "$(reason_for "$FX" e.test.sh payload/scripts/lib/width.sh | cut -d: -f1)"

# payload-copy — c names the payload root, so every file under payload/ reaches
# it, including files reached only through payload/hooks' symlink.
expect_contains "payload-copy: a payload-root namer reads a file under payload/" \
  "c.test.sh" "$(oneline "$FX" payload/scripts/lib/run.sh)"
expect_contains "payload-copy: …and a file reached only through payload/hooks" \
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
expect_contains "dir-ref: a directory glob reaches every file under it" \
  "g.test.sh" "$(oneline "$FX" hooks/h2.sh)"
expect_eq "dir-ref: the reason is named" \
  "dir-ref" "$(reason_for "$FX" g.test.sh hooks/h2.sh | cut -d: -f1)"

# transitive-hook — h runs hooks/h3.sh and never names hooklib.sh. S12 added this
# edge kind AFTER the planted proof revealed that hooks were not owners, and it is
# the one kind §B never had a mutation row for: the Step-5 revert arm meant to fill
# that hole was VOID after two attempts (step5-audit.md §6), so the hole was open
# at the head this fold-in started from.
expect_contains "transitive-hook: a suite that runs a hook inherits the hook's libs" \
  "h.test.sh" "$(oneline "$FX" payload/scripts/lib/hooklib.sh)"
expect_eq "transitive-hook: the reason is named" \
  "transitive-hook" "$(reason_for "$FX" h.test.sh payload/scripts/lib/hooklib.sh | cut -d: -f1)"

# tests/run.sh — f pins it. This is the 33-suite registration-pin edge (§1.4).
expect_contains "pin: a tests/run.sh registration pin is an edge" \
  "f.test.sh" "$(oneline "$FX" tests/run.sh)"

# A DIRECTORY ARGUMENT COVERS ITS FILES (review-a A-3). The rule the docblock
# states for what a SUITE names was not applied to what the CALLER asks about,
# so `Files: tests/lib` — a legal declaration that reaches this program — derived
# only the suites naming that directory literally: 2 in the real tree, against 55
# for the union of its files. AC-18/AC-19 are SOUNDNESS claims, and that is an
# under-approximation, the one direction this file may not fail in.
# payload/scripts/lib is the directory to ask about: no fixture suite NAMES it,
# so every suite in the answer got there through a file beneath it.
# The file list is pinned, so a file added to the fixture later fails HERE by
# name instead of moving the union row's expectation out from under it.
expect_eq "dir-arg: the fixture directory holds exactly the files this row unions" \
  "payload/scripts/lib/hooklib.sh payload/scripts/lib/run.sh payload/scripts/lib/width.sh" \
  "$( cd "$FX" && find -L payload/scripts/lib -type f | sort | tr '\n' ' ' | sed 's/ $//' )"
DA_UNION="$(suites "$FX" payload/scripts/lib/hooklib.sh payload/scripts/lib/run.sh payload/scripts/lib/width.sh)"
expect_nonempty "dir-arg: the union of the directory's files is not empty (not vacuous)" \
  "$DA_UNION"
expect_eq "dir-arg: a directory query answers the union of its files' queries" \
  "$DA_UNION" "$(suites "$FX" payload/scripts/lib)"
expect_contains "dir-arg: …so it carries a suite only a FILE under it reaches (transitive-lib)" \
  "b.test.sh" "$(oneline "$FX" payload/scripts/lib)"
expect_contains "dir-arg: …and one only another file under it reaches (transitive-doctor)" \
  "e.test.sh" "$(oneline "$FX" payload/scripts/lib)"
# PAIRED: a FILE argument is untouched — the rule is scoped to directories, and a
# derivation that simply answered everything would pass the row above.
expect_eq "dir-arg: a file argument still answers only for that file" \
  "b.test.sh" "$(suites "$FX" tests/lib/helper.sh)"
expect_eq "dir-arg: …and a file under a directory does not drag in the directory" \
  "a.test.sh" "$(suites "$FX" tests/a.test.sh)"

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
expect_absent "transitive-lib: emptying the helper drops the suite" \
  "b.test.sh" "$(oneline "$M" payload/scripts/lib/run.sh)"

M="$(mut transdoctor)"
printf '#!/bin/bash\necho nothing\n' >"$M/payload/scripts/doctor.sh"
expect_absent "transitive-doctor: a doctor.sh that sources nothing drops the suite" \
  "e.test.sh" "$(oneline "$M" payload/scripts/lib/width.sh)"

M="$(mut payloadcopy)"
printf '#!/bin/bash\n. "$(dirname "$0")/lib/resolve-roots.sh"\necho no payload here\n' >"$M/tests/c.test.sh"
expect_absent "payload-copy: dropping the payload-root reference drops the suite" \
  "c.test.sh" "$(oneline "$M" payload/scripts/lib/run.sh)"

M="$(mut symlink)"
rm "$M/payload/hooks"
mkdir -p "$M/payload/hooks"
expect_absent "payload-copy: with payload/hooks no longer a symlink, hooks/h1.sh is outside payload" \
  "c.test.sh" "$(oneline "$M" hooks/h1.sh)"

M="$(mut dirref)"
printf '#!/bin/bash\n. "$(dirname "$0")/lib/resolve-roots.sh"\necho no directory here\n' >"$M/tests/g.test.sh"
expect_absent "dir-ref: dropping the directory reference drops the suite" \
  "g.test.sh" "$(oneline "$M" hooks/h2.sh)"

# THE ARM THE STEP-5 REVERT PASS COULD NOT LAND. Both of its attempts stubbed the
# label and the loop rather than the filter, so the derivation answered nothing at
# all and every section screamed — a broken script's red, not a removed edge's.
# Here the derivation is untouched and the FIXTURE loses the edge: h3.sh sources
# nothing, so h.test.sh has no path to hooklib.sh. The paired row is what tells a
# removed edge from a broken program — c.test.sh reaches the same file by
# payload-copy and must STAY.
M="$(mut transhook)"
printf '#!/bin/bash\necho nothing\n' >"$M/hooks/h3.sh"
expect_absent "transitive-hook: a hook that sources nothing drops the suite that runs it" \
  "h.test.sh" "$(oneline "$M" payload/scripts/lib/hooklib.sh)"
expect_contains "transitive-hook: …while the payload copier still reaches the same file" \
  "c.test.sh" "$(oneline "$M" payload/scripts/lib/hooklib.sh)"

M="$(mut dirarg)"
printf '#!/bin/bash\necho nothing\n' >"$M/tests/lib/helper.sh"
expect_absent "dir-arg: a directory answer loses the suite whose only edge to a file under it went away" \
  "b.test.sh" "$(oneline "$M" payload/scripts/lib)"
expect_contains "dir-arg: …while the suites reaching it another way stay" \
  "e.test.sh" "$(oneline "$M" payload/scripts/lib)"

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
# THE ROSTER IS THE DIRECTORY (fixit 1.5.1). This used to count tests/run.sh's
# `run` lines against this number; the runner hand-lists nothing now, so the
# reference set is the directory itself — which is also what
# tests/lib/impact.sh:437 has always globbed, so what this row holds is one
# derivation against the tree it derives from.
RT_ROSTER="$(ls "$REPO"/tests/*.test.sh | grep -c . | tr -d ' ')"
# code map §3.5: resolve-roots.sh is sourced by every suite in the tree.
expect_eq "real: resolve-roots.sh reaches every suite in tests/" \
  "$RT_ROSTER" "$RT_ALL"

# code map §1.2 rows 5–6: docs-pins doctors hooks/session-poker.sh.
RT_POKER="$(oneline "$REPO" hooks/session-poker.sh)"
expect_contains "real: docs-pins reads hooks/session-poker.sh" "docs-pins.test.sh" "$RT_POKER"
expect_contains "real: session-poker's own suite reads it" "session-poker.test.sh" "$RT_POKER"
expect_eq "real: docs-pins' reason for session-poker.sh is an anchor" \
  "anchor" "$(reason_for "$REPO" docs-pins.test.sh hooks/session-poker.sh | cut -d: -f1)"

# code map §1.4: the ten named suites copy the whole payload tree, so a file
# under payload/ that none of them names still reaches all ten.
RT_WIDTH="$(oneline "$REPO" payload/scripts/lib/width.sh)"
for s in doctor-fleet doctor-patrol doctor-reads doctor-restart doctor-version \
         doctor-walls fresh-home loader patrol-marker command-relay; do
  expect_contains "real: $s.test.sh reads payload/scripts/lib/width.sh" \
    "$s.test.sh" "$RT_WIDTH"
done

# AC-7.3 — `payload/scripts/close-out.sh` derives `tests/close-out.test.sh`.
# A REGRESSION PIN THAT IS GREEN THE DAY IT IS WRITTEN, and that is the honest
# description of it: the wave-14 seed recorded this mapping as MISSING, and R2
# finding 4 established why it no longer is — tests/close-out.test.sh did not
# exist when the seed was written (wave-13 T4 created it), and a suite that does
# not exist cannot be derived. So there is nothing to fix here; there is
# something to HOLD, and what it holds is the STRENGTH of the edge. close-out's
# own suite names the script's path, which is a `path-ref`; every whole-payload
# copier reaches the same file two ranks weaker. A silent drop to `payload-copy`
# would mean the suite stopped naming what it tests and started reaching it only
# by copying the tree — the same invisibility the seed complained about.
RT_CLOSEOUT="$(oneline "$REPO" payload/scripts/close-out.sh)"
expect_contains "real: close-out.sh derives tests/close-out.test.sh (AC-7.3)" \
  "close-out.test.sh" "$RT_CLOSEOUT"
expect_eq "real: …by NAMING the path, not merely by copying the payload" \
  "path-ref" "$(reason_for "$REPO" close-out.test.sh payload/scripts/close-out.sh | cut -d: -f1)"
# NOT VACUOUS. The row above would pass against a program that reported one
# constant reason for this suite, so the complement is asserted over the same
# suite: a payload file close-out.test.sh does NOT name answers `payload-copy`.
# The example is a data file, not a script: a script can come to be reached
# transitively as the tree grows (lib/width.sh did, through close-out.sh's
# wave-28 reads), while a file nothing sources keeps only the copier's edge.
expect_eq "real: …while a payload file that suite does NOT name is only a payload-copy" \
  "payload-copy" "$(reason_for "$REPO" close-out.test.sh payload/ccstatusline/settings.json | cut -d: -f1)"

# REQ-4 AC-4.1 (D6) on the real tree — the exact fixture research row 4a proved
# live at main @ c0e2c18: `bash tests/lib/impact.sh tests/brand-new-thing.test.sh`
# printed three dir-ref lines and no self edge there. Here it must carry its own
# self edge, with nothing on disk for it to.
expect_contains "real: a not-yet-existing suite still derives itself" \
  "brand-new-thing.test.sh" "$(oneline "$REPO" tests/brand-new-thing.test.sh)"
expect_eq "real: …and the reason is self" \
  "self" "$(reason_for "$REPO" brand-new-thing.test.sh tests/brand-new-thing.test.sh | cut -d: -f1)"
# PAIRED: a Files: path outside tests/ — the AC-4.2 non-suite case — still
# gains no self edge on the real tree either (there is no top-level lib/, and
# nothing reads it).
expect_eq "real: a non-suite path outside tests/ gains no self edge (AC-4.2)" \
  "" "$(suites "$REPO" lib/x.sh)"

# THE REGISTRATION-PIN CENSUS IS GONE (fixit 1.5.1, D-3). It derived the set of
# suites asserting their own `run "<self>"` line in tests/run.sh and required
# impact.sh to reach every one of them FROM tests/run.sh. Both halves ceased to
# exist together: the runner hand-lists nothing, so there are no registration
# pins left to census — twenty-two were deleted in the same commit — and
# "reachable from tests/run.sh" is no longer how a suite comes to be run. The
# property that replaced it is proved once, where the runner lives:
# tests/runner-roster.test.sh.

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
expect_contains "…while a not-yet-created file under a copied directory still derives its readers" \
  "c.test.sh" "$(oneline "$FX" hooks/not-created-yet.sh)"

BIONIC_IMPACT_ROOT="$FX" bash "$IMPACT" >"$TMP/usage.out" 2>"$TMP/usage.err"
U_RC=$?
expect_eq "no arguments is a usage error, not an empty answer" "2" "$U_RC"
expect_eq "…and the usage goes to stderr, leaving stdout clean" "" "$(cat "$TMP/usage.out")"
expect_contains "…and the usage names the program" "impact.sh" "$(cat "$TMP/usage.err")"

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
#
# §F IS A SECTION ONLY WHEN IT RUNS (A-S5c-k, orchestrator ruling 2026-09-06). An
# opt-in proof that opens a section unconditionally and then skips would be exactly
# the vacuous-section lie the floor exists to catch; a section that "asserts" its
# own skip condition is that same lie wearing an assertion. So `section` is called
# only inside the BIONIC_IMPACT_PLANTED=1 branch, where the proof actually asserts;
# the default path prints its SKIP line with no open section at all, and the
# suite's tally reads sections=N without §F on an ordinary run, sections=N+1 when
# the proof runs.
if [ "${BIONIC_IMPACT_PLANTED:-0}" != "1" ]; then
  echo "SKIP: §F the planted-edit proof — not requested (BIONIC_IMPACT_PLANTED=1 to run it; the"
  echo "      authoring-time record is committed at .bionic/docs/record/"
  echo "      wave-verification-cannot-lie/s12-planted-edits.log)"
else
  section "§F the planted-edit proof"
  PLOG="${BIONIC_IMPACT_PLANTED_LOG:-$TMP/planted-edits.log}"

  # WIDTH IS READ, NOT SET — the same rule tests/run.sh:211 follows, and the
  # same ceiling. Six whole-roster runs at width one would take the better part
  # of an hour; the roster's own isolation audit is what makes running them at
  # once safe (tests/run.sh:54-72).
  PJOBS=8
  if [ -f "$REPO/payload/scripts/lib/resources.sh" ]; then
    # shellcheck source=/dev/null
    . "$REPO/payload/scripts/lib/resources.sh" 2>/dev/null || :
    if command -v pressure_level >/dev/null 2>&1; then
      PJOBS="$(pressure_level "${BIONIC_TEST_JOBS_CEILING:-8}" 2>/dev/null)"
    fi
  fi
  case "$PJOBS" in ''|*[!0-9]*) PJOBS=8 ;; esac

  : >"$PLOG"
  {
    echo "planted-edit proof — spec AC-19"
    echo "when:        $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo "repo:        $REPO"
    echo "commit:      $(cd "$REPO" && git rev-parse --short HEAD 2>/dev/null || echo unknown)"
    echo "interpreter: $(bash --version | head -1)"
    echo "width:       $PJOBS"
    echo
    echo "METHOD. A scratch copy of the checkout is made once. For each file"
    echo "class the derived set is recorded, one maximal edit is planted, the"
    echo "WHOLE roster is run against the mutated tree, and the file is"
    echo "restored. The claim under test is derived ⊇ red: its falsifier is a"
    echo "suite that goes red and is not in the derived set, so the complement"
    echo "is run in full rather than sampled. A control run over the unmutated"
    echo "tree comes first, and any suite red there is discounted everywhere —"
    echo "a suite that cannot pass on its own proves nothing about impact."
  } >>"$PLOG"

  SCRATCH="$TMP/scratch"
  mkdir -p "$SCRATCH"
  ( cd "$REPO" && tar cf - --exclude=.git --exclude=.worktrees --exclude=.bionic . ) \
    | ( cd "$SCRATCH" && tar xf - )

  ROSTER="$(/usr/bin/grep -oE '^run "[^"]+"' "$SCRATCH/tests/run.sh" | sed 's/^run "//; s/"$//' | sort)"
  printf '%s\n' "$ROSTER" >"$TMP/roster"
  echo "roster:      $(grep -c . "$TMP/roster") suites" >>"$PLOG"

  # the parallel arm — one label in, one <label>.rc out. §F's own suite is
  # skipped inside the scratch tree: it would recurse into another whole proof.
  cat >"$TMP/arm.sh" <<'ARM'
#!/bin/bash
# THE SEAM HAS TO BE CLOSED BEFORE THE SUITE STARTS. This suite sourced
# tests/lib/resolve-roots.sh at its top, which EXPORTS BIONIC_HOOKS_DIR,
# BIONIC_SKILLS_DIR and BIONIC_SCRIPTS_DIR pointing at the real checkout —
# and resolve-roots takes an existing export verbatim. Inherited, those three
# send every suite in the scratch tree to read the REAL files, so the planted
# edit is never seen and the proof reports a clean superset while testing
# nothing (.claude/rules/test-harness.md, "Seam blindness": a seam that substitutes the value
# under test leaves the production path unverified). Unset them and each suite
# re-derives its roots from its own location, which is the scratch tree.
unset BIONIC_HOOKS_DIR BIONIC_SKILLS_DIR BIONIC_SCRIPTS_DIR
unset BIONIC_IMPACT_ROOT BIONIC_IMPACT_PLANTED BIONIC_IMPACT_PLANTED_LOG
label="$1"
# impact.test.sh's own §F would recurse into another whole proof from inside
# this one; the outer run is what covers it.
if [ "$label" = "impact.test.sh" ]; then echo 0 >"$RESDIR/$label.rc"; exit 0; fi
( cd "$SCRATCHDIR" && bash "tests/$label" ) >"$RESDIR/$label.out" 2>&1
echo $? >"$RESDIR/$label.rc"
ARM

  # list_run <resdir> <list-file> — runs the named suites against $SCRATCH at
  # width $PJOBS, prints the red ones.
  list_run() {
    local rd="$1" list="$2"
    rm -rf "$rd"; mkdir -p "$rd"
    SCRATCHDIR="$SCRATCH" RESDIR="$rd" \
      xargs -P "$PJOBS" -n1 bash "$TMP/arm.sh" <"$list" >/dev/null 2>&1
    while IFS= read -r l; do
      [ -n "$l" ] || continue
      [ -f "$rd/$l.rc" ] || { echo "$l"; continue; }
      [ "$(cat "$rd/$l.rc")" = "0" ] || echo "$l"
    done <"$list"
  }

  # PROVE THE SEAM IS CLOSED before trusting a single result below. A suite
  # launched by the arm must resolve its roots to the SCRATCH tree; if it
  # resolves to the real checkout the whole proof is vacuous, so this is checked
  # rather than assumed, and checked the way the suites themselves do it.
  cat >"$TMP/seam-probe.sh" <<'PROBE'
#!/bin/bash
unset BIONIC_HOOKS_DIR BIONIC_SKILLS_DIR BIONIC_SCRIPTS_DIR
. "$(dirname "$0")/lib/resolve-roots.sh"
printf '%s\n' "$BIONIC_SCRIPTS_DIR"
PROBE
  cp "$TMP/seam-probe.sh" "$SCRATCH/tests/seam-probe.sh"
  SEAM_SAW="$( ( cd "$SCRATCH" && bash tests/seam-probe.sh ) 2>/dev/null )"
  rm -f "$SCRATCH/tests/seam-probe.sh"
  # Compared PHYSICALLY. resolve-roots.sh reports `pwd -P`, and mktemp hands out
  # a path under /var, which is a symlink to /private/var here — so the two
  # spellings of the same directory differ textually and only textually.
  SCRATCH_P="$(cd "$SCRATCH" && pwd -P)"
  {
    echo
    echo "SEAM CHECK — the root a suite in the scratch tree resolves to"
    echo "  scratch:   $SCRATCH_P"
    echo "  suite saw: $SEAM_SAW"
  } >>"$PLOG"
  if [ "$SEAM_SAW" = "$SCRATCH_P" ]; then
    ok "planted seam: a suite in the scratch tree resolves to the scratch tree"
  else
    no "planted seam: a suite in the scratch tree resolves to the scratch tree" \
      "saw [$SEAM_SAW] — every result below would be about the real checkout"
  fi

  # the control. Anything red here is red for its own reasons.
  BASE_RED="$(list_run "$TMP/res-base" "$TMP/roster")"
  {
    echo
    echo "CONTROL (no edit planted)"
    echo "  red: ${BASE_RED:-none}"
  } >>"$PLOG"
  if [ -z "$BASE_RED" ]; then
    ok "planted control: the unmutated scratch tree is wholly green"
  else
    ok "planted control: $(printf '%s\n' "$BASE_RED" | grep -c .) suite(s) red before any edit, discounted below"
  fi

  # plant <class> <file> <how> <witness>
  #
  # WHAT IS RUN, AND WHY NOT EVERYTHING. The claim is derived ⊇ red. Its only
  # falsifier is a suite red OUTSIDE the derived set, so the COMPLEMENT is run in
  # full — never sampled, because a sampled complement proves a sampled claim.
  # Inside the derived set nothing needs proving except that the edit is not
  # inert, and one named witness settles that: the suite whose whole subject is
  # the mutated file. Running the other twenty-odd derived suites would add half
  # again to a proof already measured in roster-runs and answer no question.
  plant() {
    local class="$1" file="$2" how="$3" wit="$4"
    local derived red witness="" outside="" n_out=0 wit_red

    derived="$(BIONIC_IMPACT_ROOT="$SCRATCH" bash "$IMPACT" "$file" | cut -f1 | sort -u)"
    printf '%s\n' "$derived" | grep . >"$TMP/derived" || : >"$TMP/derived"

    cp "$SCRATCH/$file" "$TMP/restore.bak"
    case "$how" in
      early-exit) printf 'exit 99\n' | cat - "$TMP/restore.bak" >"$SCRATCH/$file" ;;
      syntax)     printf '\nif then fi(((\n' >>"$SCRATCH/$file" ;;
      # a file read as TEXT — a roster, an SSoT a pin greps — is not broken by
      # an appended line or an early exit; only losing its content breaks it.
      wipe)       printf '#!/bin/bash\n# BIONIC_IMPACT_PLANTED_WIPE\n' >"$SCRATCH/$file" ;;
    esac

    comm -23 "$TMP/roster" "$TMP/derived" >"$TMP/complement"
    printf '%s\n' "$wit" >"$TMP/witlist"
    wit_red="$(list_run "$TMP/res-wit" "$TMP/witlist")"
    red="$(list_run "$TMP/res-comp" "$TMP/complement")"
    cp "$TMP/restore.bak" "$SCRATCH/$file"

    # discount the control's own reds, then split by the derived set
    printf '%s\n' "$red" | grep . >"$TMP/red" || : >"$TMP/red"
    printf '%s\n' "$BASE_RED" | grep . >"$TMP/basered" || : >"$TMP/basered"
    sort -u "$TMP/red" -o "$TMP/red"
    sort -u "$TMP/basered" -o "$TMP/basered"
    comm -23 "$TMP/red" "$TMP/basered" >"$TMP/outside"
    outside="$(tr '\n' ' ' <"$TMP/outside")"
    n_out="$(grep -c . "$TMP/outside")"
    case "$BASE_RED" in *"$wit"*) witness="" ;; *) witness="$wit_red" ;; esac

    {
      echo
      echo "════════════════════════════════════════════════════════════════"
      echo "class:            $class"
      echo "file:             $file"
      echo "edit:             $how"
      echo "derived ($(grep -c . "$TMP/derived")): $(tr '\n' ' ' <"$TMP/derived")"
      echo "witness (derived, run to prove the edit bites): $wit -> ${wit_red:+RED}${wit_red:-green}"
      echo "complement run in full: $(grep -c . "$TMP/complement") suites"
      echo "red OUTSIDE the derived set, control discounted: ${outside:-none}"
    } >>"$PLOG"

    if [ -n "$witness" ]; then
      ok "planted [$class]: the edit really bites — $witness went red"
    else
      no "planted [$class]: the edit really bites" \
        "no derived suite went red; the planted edit is inert and the superset claim is vacuous"
    fi
    if [ "$n_out" -eq 0 ]; then
      ok "planted [$class]: derived ⊇ red, over the whole roster"
    else
      no "planted [$class]: derived ⊇ red, over the whole roster" \
        "$n_out suite(s) red outside the derived set: $outside"
    fi
  }

  # The five classes AC-19 names, each with the suite whose whole subject is the
  # mutated file, and a maximal edit: a small edit makes a small red set and a
  # correspondingly weak superset claim.
  plant "a hook"                      "hooks/bash-walls.sh"           early-exit bash-walls.test.sh
  plant "a lib the doctor sources"    "payload/scripts/lib/width.sh"  early-exit width.test.sh
  plant "a tests/lib helper"          "tests/lib/bound-marker.sh"     wipe       session-start.test.sh
  plant "tests/run.sh"                "tests/run.sh"                  wipe       version-compare.test.sh
  plant "a whole-payload-copied file" "payload/scripts/lib/patrol.sh" wipe       patrol-marker.test.sh

  echo
  echo "planted-edit log: $PLOG"
fi


# ── §G the derivation cache ─────────────────────────────────────────────────
# REQ-7 / spec D4: the edge graph is a pure function of the tree, so it is built
# once per TREE STATE and reused. What this section has to prove is not that a
# cache exists — that is trivially visible — but that it CANNOT LIE. Three
# properties, and the middle one is the whole point:
#
#   1. a hit is cheap                (the reason REQ-7 exists at all)
#   2. a hit answers what a miss answers, byte for byte, INCLUDING for an
#      argument the cached run never saw (the graph is argument-independent;
#      R2 Q8 measured that independence at 13 ms across two different queries)
#   3. a tree that changed is not answered from the old graph
#
# (2) is the soundness claim. This derivation is the single owner of "which
# suites read this change" for three consumers (the dispatch wall, the writer
# budget guard, the landing reconcile), so a stale or wrong hit is a missed
# regression in all three at once — which is why the answer is compared against
# a deliberately UNCACHED run rather than against itself.
#
# WHY THE REAL TREE FOR THE TIMING ROWS. The fixture is eleven files and derives
# in a fraction of a second with no cache at all, so a fixture timing row would
# pass against a program that cached nothing. The cost REQ-7 removes is the real
# repo's — R2 Q8 measured 4.2 s at quiet load, argument-independent — and that is
# what the cold/warm pair below is measured over, with the cache pointed at this
# suite's own temp directory so the pair is one this section created itself.
section "§G the derivation cache"

G_CACHE="$TMP/impact-cache"
rm -rf "$G_CACHE"

# timed_ms <outfile> <cmd>… — run the command with stdout captured to <outfile>;
# print its wall time in whole milliseconds. python3 for the reason
# tests/bench/hook-latency.sh gives: macOS ships no `date +%s%N`, and bash's
# `time` writes to a tty rather than to a variable.
timed_ms() {
  python3 -c '
import subprocess, sys, time
with open(sys.argv[1], "wb") as f:
    t = time.time()
    subprocess.run(sys.argv[2:], stdout=f, stderr=subprocess.DEVNULL)
    ms = int((time.time() - t) * 1000)
print(ms)
' "$@"
}

# python3 is a floor dependency already (nine gating suites call it). If it were
# gone `timed_ms` would answer nothing, the `:-` default below would read
# 999999, and the timing row would FAIL rather than quietly pass — which is the
# direction a missing instrument has to fail in.
G_COLD_MS="$(timed_ms "$TMP/g.cold" env BIONIC_IMPACT_CACHE_DIR="$G_CACHE" \
  bash "$IMPACT" payload/scripts/close-out.sh)"
G_WARM_MS="$(timed_ms "$TMP/g.warm" env BIONIC_IMPACT_CACHE_DIR="$G_CACHE" \
  bash "$IMPACT" payload/scripts/close-out.sh)"

# NOT VACUOUS: a program that printed nothing would satisfy "identical" below.
expect_nonempty "cache: the cold call answers at all" "$(cat "$TMP/g.cold")"
expect_eq "cache: the warm answer is byte-identical to the cold one" \
  "$(cat "$TMP/g.cold")" "$(cat "$TMP/g.warm")"

if [ "${G_WARM_MS:-999999}" -le 500 ]; then
  ok "cache: a second derivation at the same tree state costs <= 500 ms (cold ${G_COLD_MS} ms, warm ${G_WARM_MS} ms)"
else
  no "cache: a second derivation at the same tree state costs <= 500 ms" \
     "cold ${G_COLD_MS} ms, warm ${G_WARM_MS} ms — the edge graph is still being rebuilt per call"
fi

expect_true "cache: the cold call left a keyed entry under the cache directory" \
  bash -c '[ -d "$0" ] && [ -n "$(ls -A "$0" 2>/dev/null)" ]' "$G_CACHE"

# THE SOUNDNESS ROW. A different argument against the same cached graph — the
# cache was written by a close-out.sh query and is now asked about width.sh —
# must answer exactly what a run with no cache at all answers.
G_OTHER_UNCACHED="$(BIONIC_IMPACT_CACHE_DIR="" bash "$IMPACT" payload/scripts/lib/width.sh 2>/dev/null)"
G_OTHER_CACHED="$(BIONIC_IMPACT_CACHE_DIR="$G_CACHE" bash "$IMPACT" payload/scripts/lib/width.sh 2>/dev/null)"
expect_nonempty "cache: the uncached control answers at all" "$G_OTHER_UNCACHED"
expect_eq "cache: an argument the cached run never saw answers what an UNCACHED run answers" \
  "$G_OTHER_UNCACHED" "$G_OTHER_CACHED"
expect_eq "cache: …and turning the cache off changes nothing about the first answer" \
  "$(cat "$TMP/g.cold")" "$(BIONIC_IMPACT_CACHE_DIR="" bash "$IMPACT" payload/scripts/close-out.sh 2>/dev/null)"

# INVALIDATION, over the fixture, because it needs a tree that may be written to.
# `tests/i.test.sh` is new and pins hooks/h2.sh by name; before it exists nothing
# in the fixture names h2 at all (c and g reach it only through a directory).
G_FXC="$TMP/impact-cache-fx"
rm -rf "$G_FXC"
G_H2_BEFORE="$(BIONIC_IMPACT_CACHE_DIR="$G_FXC" BIONIC_IMPACT_ROOT="$FX" \
  bash "$IMPACT" hooks/h2.sh 2>/dev/null | cut -f1 | tr '\n' ' ')"
printf '#!/bin/bash\n. "$(dirname "$0")/lib/resolve-roots.sh"\ngrep -q hello "${BIONIC_HOOKS_DIR}/h2.sh"\n' \
  >"$FX/tests/i.test.sh"
G_H2_AFTER="$(BIONIC_IMPACT_CACHE_DIR="$G_FXC" BIONIC_IMPACT_ROOT="$FX" \
  bash "$IMPACT" hooks/h2.sh 2>/dev/null | cut -f1 | tr '\n' ' ')"
rm -f "$FX/tests/i.test.sh"
expect_nonempty "cache: the fixture answers for hooks/h2.sh before the edit" "$G_H2_BEFORE"
expect_absent "cache: …and no suite reads it BY NAME yet" "i.test.sh" "$G_H2_BEFORE"
expect_contains "cache: a tree change invalidates — the new reader is derived" \
  "i.test.sh" "$G_H2_AFTER"

# ── §H the template/block → rendered-target edge (REQ-10, D11) ──────────────
# WHY. No suite reads `agents-src/templates/**` or `agents-src/blocks/**`
# directly — `agents-src/render.sh` reads them and a suite reads what it
# WRITES — so a query for a source has to resolve to that source's rendered
# target(s) before any of §A's edge kinds can answer for it. AC-10.1's own
# fails-when is the exact regression that motivated this: at a525e0c,
# `steps/5.md.tmpl` answered `docs-pins` and `render` only, never
# `jit.test.sh`, even though `jit.test.sh` pins the rendered `steps/5.md`
# four times over.
#
# §H1 walks EVERY real `.md.tmpl` render.sh's own `RENDER_UNITS` table
# reaches — not a hand-picked few — so AC-10.2 ("a mapped template has no row
# in impact.test.sh") cannot pass silently: a template render.sh adds
# tomorrow gets a row the next time this suite runs, with no edit here. Each
# row's oracle is impact.sh's OWN answer for the rendered file, asked
# directly — never a hand-kept suite list — so this is a completeness check
# on the RESOLUTION, not a second copy of §A's edge-kind logic.
section "§H the template/block → rendered target edge (REQ-10, D11)"

H_RENDER_SH="$REPO/agents-src/render.sh"
H_UNITS="$(awk '
  /^RENDER_UNITS="$/ { grab = 1; next }
  grab && /^"$/       { grab = 0; next }
  grab && NF           { print }
' "$H_RENDER_SH")"
expect_nonempty "real: agents-src/render.sh declares at least one render unit" "$H_UNITS"

H_TARGETS="$TMP/h-targets"   # tmpl_path<TAB>target_path, every real template
: >"$H_TARGETS"
printf '%s\n' "$H_UNITS" | while IFS='|' read -r tmpl_dir out_dir; do
  [ -n "$tmpl_dir" ] && [ -n "$out_dir" ] || continue
  [ -d "$REPO/$tmpl_dir" ] || continue
  for tmpl in "$REPO/$tmpl_dir"/*.md.tmpl; do
    [ -f "$tmpl" ] || continue
    base="$(basename "$tmpl")"; base="${base%.md.tmpl}"
    printf '%s/%s.md.tmpl\t%s/%s.md\n' "$tmpl_dir" "$base" "$out_dir" "$base" >>"$H_TARGETS"
  done
done
H_ROWS="$(grep -c . "$H_TARGETS" 2>/dev/null || echo 0)"
expect_true "real: at least one template maps to a target (the roster this section covers is non-empty)" \
  bash -c '[ "$0" -gt 0 ]' "$H_ROWS"

# one row per mapped template (AC-10.2): the derived answer for the SOURCE
# must be a superset of the derived answer for its own rendered TARGET.
while IFS="$(printf '\t')" read -r h_tmpl h_target; do
  [ -n "$h_tmpl" ] || continue
  [ -f "$REPO/$h_target" ] || continue
  h_want="$(oneline "$REPO" "$h_target")"
  h_got="$(oneline "$REPO" "$h_tmpl")"
  h_missing=""
  for w in $h_want; do
    case " $h_got " in
      *" $w "*) ;;
      *) h_missing="$h_missing $w" ;;
    esac
  done
  if [ -z "$h_missing" ]; then
    ok "real: $h_tmpl reaches every suite its rendered target ($h_target) reaches"
  else
    no "real: $h_tmpl reaches every suite its rendered target ($h_target) reaches" \
       "missing:$h_missing"
  fi
done <"$H_TARGETS"

# THE NAMED CASE (AC-10.1's fails-when, and the plan's own worked example):
# steps/5.md.tmpl must reach jit.test.sh through its rendered target, by a PIN
# (jit.test.sh greps the rendered steps/5.md four times — R4 Q1), not merely
# by the pre-existing directory reference every suite naming agents-src gets.
expect_contains "real: steps/5.md.tmpl reaches jit.test.sh through its rendered target (AC-10.1)" \
  "jit.test.sh" "$(oneline "$REPO" agents-src/templates/skills/canonical-sdlc/steps/5.md.tmpl)"
expect_eq "real: …and the reason is a pin on the rendered file, not a directory reference" \
  "pin" "$(reason_for "$REPO" jit.test.sh agents-src/templates/skills/canonical-sdlc/steps/5.md.tmpl | cut -d: -f1)"

# §H2 A BLOCK FANS OUT TO SEVERAL TARGETS. `report-contract` is injected by six
# role templates (all but nothing shares it with a skill-unit file), so its
# query must reach suites that only a role file — not the block's own
# directory reference — would surface. jit.test.sh dir-refs agents/*.md but
# never names report-contract.md itself, so this is a real fan-out proof, not
# a restatement of render.test.sh's own dir-ref.
H_RC_TEMPLATES="$(grep -rl '<!-- INJECT: report-contract -->' "$REPO/agents-src/templates" 2>/dev/null | wc -l | tr -d ' ')"
expect_true "real: agents-src/blocks/report-contract.md injects into more than one template (fan-out exists to prove)" \
  bash -c '[ "$0" -gt 1 ]' "$H_RC_TEMPLATES"
expect_contains "real: agents-src/blocks/report-contract.md fans out to a suite that reads a role file it injects" \
  "jit.test.sh" "$(oneline "$REPO" agents-src/blocks/report-contract.md)"

# §H3 THE PLANTED PAIR (AC-10.3): a sandbox root with its OWN render.sh and
# its own `x.md.tmpl -> skills/x.md` mapping — nothing this repo's real
# render.sh declares — is followed exactly like the real one, proving the
# derivation reads the mapping from the tree rather than naming this repo's
# paths.
FXR="$TMP/fx-render"
mkdir -p "$FXR/tests/lib" "$FXR/agents-src/templates" "$FXR/skills"
cat >"$FXR/agents-src/render.sh" <<'EOF'
#!/usr/bin/env bash
# a minimal stand-in — only the RENDER_UNITS shape impact.sh reads matters.
RENDER_UNITS="
agents-src/templates|skills
"
EOF
: >"$FXR/agents-src/templates/x.md.tmpl"
: >"$FXR/skills/x.md"
printf '#!/bin/bash\n. "$(dirname "$0")/lib/resolve-roots.sh"\ngrep -q anything "${BIONIC_SCRIPTS_DIR}/skills/x.md"\n' \
  >"$FXR/tests/j.test.sh"
printf '#!/bin/bash\n. "$(dirname "$0")/lib/resolve-roots.sh"\n' >"$FXR/tests/lib/resolve-roots.sh"
{
  printf '#!/bin/bash\n'
  printf 'run "j.test.sh" bash tests/j.test.sh\n'
} >"$FXR/tests/run.sh"

expect_contains "planted: a sandbox x.tmpl -> skills/x.md pair is followed (AC-10.3)" \
  "j.test.sh" "$(oneline "$FXR" agents-src/templates/x.md.tmpl)"
# NOT VACUOUS: a root with no render.sh at all resolves nothing for the same
# path shape — proving the row above answers from the PLANTED render.sh, not
# from some universal template-name guess.
expect_eq "planted: …while the base fixture (no render.sh) resolves nothing for the same shape" \
  "" "$(suites "$FX" agents-src/templates/x.md.tmpl)"

# ── §NEST a root that holds nested worktrees and sandbox records ────────────
# WHY (wave-24 T19, AC-5.5). At the main checkout, which holds ten nested
# worktrees under `.worktrees/` and a `.bionic/docs/record` tree of sandbox
# copies, one call ran past 190 s; inside a worktree with none it took 5 s. Two
# walks were to blame, and only one of them was the one the first reading named:
#   - the `.git` / `.worktrees` exclusions were `-not -path`, which filters the
#     RESULTS and still descends; `-prune` does not descend at all.
#   - the symlink walk never excluded `.bionic` at all, so every symlink in a
#     sandbox record became a root alias, and each alias is another pass of the
#     de-aliasing loop for every edge the derivation resolves. That one is the
#     bulk of the minutes: `find` over all of `.worktrees` costs ~10 ms.
# The fixture reproduces both at a scale where the unfixed program is slow
# enough to measure and the fixed one is not: sixty suites (edges to resolve),
# ten nested worktree copies, and 400 symlinks under `.bionic`.
NEST_BUDGET_MS=10000

# mk_nest_root <dir> <1|0> — sixty suites each pinning one hook and one library;
# with <1>, ten nested worktree copies and 400 sandbox-record symlinks beside them.
mk_nest_root() {
  local r="$1" noise="$2" i k w
  mkdir -p "$r/tests/lib" "$r/hooks" "$r/payload/scripts/lib"
  ln -s ../hooks "$r/payload/hooks"
  printf '#!/bin/bash\n. "$(dirname "$0")/lib/resolve-roots.sh"\n' >"$r/tests/lib/resolve-roots.sh"
  : >"$r/tests/run.sh"
  for i in $(seq 1 60); do
    printf '#!/bin/bash\n. "$(dirname "$0")/lib/resolve-roots.sh"\ngrep -q x "${BIONIC_SCRIPTS_DIR}/hooks/h%s.sh"\ngrep -q x "${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/l%s.sh"\n' \
      "$i" "$i" >"$r/tests/s$i.test.sh"
    printf '#!/bin/bash\necho h%s\n' "$i" >"$r/hooks/h$i.sh"
    printf '#!/bin/bash\necho l%s\n' "$i" >"$r/payload/scripts/lib/l$i.sh"
    printf 'run "s%s.test.sh" bash tests/s%s.test.sh\n' "$i" "$i" >>"$r/tests/run.sh"
  done
  [ "$noise" = 1 ] || return 0
  mkdir -p "$r/.bionic/docs/record/x"
  for k in $(seq 1 400); do ln -s ../../../../hooks "$r/.bionic/docs/record/x/lnk$k"; done
  for w in 1 2 3 4 5 6 7 8 9 10; do
    mkdir -p "$r/.worktrees/w$w"
    cp -R "$r/tests" "$r/hooks" "$r/payload" "$r/.worktrees/w$w/"
  done
}

NEST_QUIET="$TMP/nest-quiet"
NEST_NOISY="$TMP/nest-noisy"
mk_nest_root "$NEST_QUIET" 0
mk_nest_root "$NEST_NOISY" 1

NEST_QUIET_MS="$(timed_ms "$TMP/nest.quiet" env BIONIC_IMPACT_CACHE_DIR="" \
  BIONIC_IMPACT_ROOT="$NEST_QUIET" bash "$IMPACT" hooks/h7.sh payload/scripts/lib/l9.sh)"
NEST_NOISY_MS="$(timed_ms "$TMP/nest.noisy" env BIONIC_IMPACT_CACHE_DIR="" \
  BIONIC_IMPACT_ROOT="$NEST_NOISY" bash "$IMPACT" hooks/h7.sh payload/scripts/lib/l9.sh)"

# NOT VACUOUS: an empty answer would be "identical" to an empty answer, and a
# failed timing instrument reads as the slowest possible time below.
expect_nonempty "nest: the quiet root answers at all" "$(cat "$TMP/nest.quiet")"
expect_contains "nest: …and names the suite that pins hooks/h7.sh" "s7.test.sh" "$(cat "$TMP/nest.quiet")"
expect_eq "nest: nested worktrees and sandbox-record symlinks change no line of the answer"   "$(cat "$TMP/nest.quiet")" "$(cat "$TMP/nest.noisy")"
if [ "${NEST_NOISY_MS:-999999}" -lt "$NEST_BUDGET_MS" ]; then
  ok "nest: a root with ten nested worktrees answers in < ${NEST_BUDGET_MS} ms (${NEST_NOISY_MS} ms; quiet ${NEST_QUIET_MS} ms)"
else
  no "nest: a root with ten nested worktrees answers in < ${NEST_BUDGET_MS} ms" \
     "${NEST_NOISY_MS:-no timing} ms (quiet root ${NEST_QUIET_MS:-no timing} ms) — the walks still pay for what they exclude"
fi

# ── §NEST-LIB sandbox beds under .bionic are not library directories ────────
# WHY (wave-24 T21, AC-5.5). With T19's prunes in, the main checkout still took
# 17.7 s cold against 5.3 s at a clean worktree, and 13.1 s of it was settling the
# `source?` candidates. The library-directory walk pruned `.git` and `.worktrees`
# but not `.bionic`, where critic and review beds hold whole copies of `tests/lib`
# and `payload/scripts/lib`: eight extra library directories, so every source line
# offered four times the candidates, and every candidate a bed copy satisfied
# became a real `source` edge, each settled by a forked de-alias. The fixture
# reproduces it: hooks that source their library through `$BIONIC_LIB` (no static
# reading resolves it, so every library directory is a candidate) and forty beds
# that copy `tests/` and `payload/` under `.bionic/docs/record`.
mk_bed_root() { # mk_bed_root <dir> <beds>
  local r="$1" n="$2" i b
  mk_nest_root "$r" 0
  for i in $(seq 1 60); do
    printf '#!/bin/bash\n. "$BIONIC_LIB/l%s.sh"\necho h%s\n' "$i" "$i" >"$r/hooks/h$i.sh"
  done
  for b in $(seq 1 "$n"); do
    mkdir -p "$r/.bionic/docs/record/beds/b$b"
    cp -R "$r/tests" "$r/payload" "$r/.bionic/docs/record/beds/b$b/"
  done
}
BED_QUIET="$TMP/bed-quiet"
BED_NOISY="$TMP/bed-noisy"
mk_bed_root "$BED_QUIET" 0
mk_bed_root "$BED_NOISY" 40

BED_QUIET_MS="$(timed_ms "$TMP/bed.quiet" env BIONIC_IMPACT_CACHE_DIR="" \
  BIONIC_IMPACT_ROOT="$BED_QUIET" bash "$IMPACT" hooks/h7.sh payload/scripts/lib/l9.sh)"
BED_NOISY_MS="$(timed_ms "$TMP/bed.noisy" env BIONIC_IMPACT_CACHE_DIR="" \
  BIONIC_IMPACT_ROOT="$BED_NOISY" bash "$IMPACT" hooks/h7.sh payload/scripts/lib/l9.sh)"

expect_contains "nest-lib: the quiet root names the suite that pins payload/scripts/lib/l9.sh" \
  "s9.test.sh" "$(cat "$TMP/bed.quiet")"
expect_eq "nest-lib: forty sandbox beds change no line of the answer" \
  "$(cat "$TMP/bed.quiet")" "$(cat "$TMP/bed.noisy")"
# The hook's `$BIONIC_LIB` source resolves to the real library — and only to it.
expect_contains "nest-lib: a hook's \$BIONIC_LIB source reaches the real library (s7 via h7)" \
  "s7.test.sh" "$(oneline "$BED_NOISY" payload/scripts/lib/l7.sh)"
expect_eq "nest-lib: …and never a bed's copy of it, which no suite reads" \
  "" "$(suites "$BED_NOISY" .bionic/docs/record/beds/b1/payload/scripts/lib/l7.sh)"
if [ "${BED_NOISY_MS:-999999}" -lt "$NEST_BUDGET_MS" ]; then
  ok "nest-lib: a root holding forty sandbox beds answers in < ${NEST_BUDGET_MS} ms (${BED_NOISY_MS} ms; quiet ${BED_QUIET_MS} ms)"
else
  no "nest-lib: a root holding forty sandbox beds answers in < ${NEST_BUDGET_MS} ms" \
     "${BED_NOISY_MS:-no timing} ms (quiet root ${BED_QUIET_MS:-no timing} ms) — the library walk still enters .bionic"
fi

# ── §SAMPLE-LIB a reader-exam sample's lib/ is not a library directory ───────
# WHY (wave-27 T36, review pass 7 note 8). The reader exam's samples are small made-up
# projects under tests/reader-exam/samples/<name>/tree/, each with its own lib/. Nothing
# bionic runs sources them, but the `$BIONIC_LIB` candidate walk offered every lib/ in the
# tree, so a sample library sharing a basename with a real one became a `source` edge of
# every suite whose hook sources the real one. The fixture is the bed root with no beds and
# one sample whose lib/l7.sh shares the real payload/scripts/lib/l7.sh's name.
SAMPLE_ROOT="$TMP/sample-lib"
mk_bed_root "$SAMPLE_ROOT" 0
mkdir -p "$SAMPLE_ROOT/tests/reader-exam/samples/s/tree/lib"
printf '#!/bin/bash\necho sample\n' >"$SAMPLE_ROOT/tests/reader-exam/samples/s/tree/lib/l7.sh"
expect_contains "sample-lib: the real payload/scripts/lib/l7.sh still reaches s7 through h7" \
  "s7.test.sh" "$(BIONIC_IMPACT_CACHE_DIR="" oneline "$SAMPLE_ROOT" payload/scripts/lib/l7.sh)"
expect_eq "sample-lib: a sample's lib/l7.sh, same name, pulls no suite" \
  "" "$(BIONIC_IMPACT_CACHE_DIR="" suites "$SAMPLE_ROOT" tests/reader-exam/samples/s/tree/lib/l7.sh)"

# ── §LOCATES locating is not reading (wave-30 T7, AC-4.5, design-ledger Δ4/D5) ──
# THE SEAM NAMES ROOTS, IT DOES NOT READ THEM. tests/lib/resolve-roots.sh sets
# BIONIC_HOOKS_DIR and BIONIC_SKILLS_DIR, and every suite sources it, so while the
# map expanded those two lines like any directory edge every hook and every skill
# file answered the whole roster. Those lines carry `# impact: locates` now, and a
# located directory is an edge on the directory ITSELF, never on the files beneath
# it. Narrowing a sound map is safe only if every real reader is still seen, so the
# fixture holds each way a suite was measured reading a hook in the real tree
# without the seam: naming it through the seam variable, globbing the directory,
# spelling it root-relative after a command substitution (session-start.test.sh:304),
# running a hook that runs it, and naming it as the sibling of a variable that a
# one-line `SAVED="$H"; H=…` swap once left unparseable (stop.test.sh:624).
section "§LOCATES locating is not reading"

mk_locates_root() { # mk_locates_root <dir>
  local r="$1"
  mkdir -p "$r/tests/lib" "$r/hooks"
  printf '#!/bin/bash\n_r="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"\nBIONIC_HOOKS_DIR="${BIONIC_HOOKS_DIR:-${_r}/hooks}" # impact: locates\nexport BIONIC_HOOKS_DIR\n' \
    >"$r/tests/lib/resolve-roots.sh"
  printf '#!/bin/bash\necho h1\n' >"$r/hooks/h1.sh"
  printf '#!/bin/bash\nbash "$(dirname "$0")/h1.sh"\n' >"$r/hooks/h2.sh"
  printf '#!/bin/bash\necho h3\n' >"$r/hooks/h3.sh"
  printf '#!/bin/bash\necho nobody-names-me\n' >"$r/hooks/h9.sh"
  local pre='#!/bin/bash\n. "$(dirname "$0")/lib/resolve-roots.sh"\n'
  printf "$pre"'bash "$BIONIC_HOOKS_DIR/h1.sh"\n' >"$r/tests/lreader.test.sh"
  printf "$pre"'echo only the seam\n' >"$r/tests/lseam.test.sh"
  printf "$pre"'for f in "$BIONIC_HOOKS_DIR"/*.sh; do bash -n "$f"; done\n' >"$r/tests/lglob.test.sh"
  printf "$pre"'HK="$BIONIC_HOOKS_DIR/h1.sh"\nH3="$(cd "$(dirname "$HK")/.." && pwd -P)/hooks/h3.sh"\nbash "$H3"\n' >"$r/tests/lsubst.test.sh"
  printf "$pre"'bash "$BIONIC_HOOKS_DIR/h2.sh"\n' >"$r/tests/lrunner.test.sh"
  printf "$pre"'H="$BIONIC_HOOKS_DIR/h2.sh"\nSAVED="$H"; H="$TMP/other/h2.sh"\nH="$SAVED"\nbash "$(dirname "$H")/h3.sh"\n' >"$r/tests/lswap.test.sh"
}
LROOT="$TMP/locates"
mk_locates_root "$LROOT"
# has_suite <suite> <root> <file>... → 1 when the map names that suite, 0 when not
has_suite() { local w="$1"; shift; BIONIC_IMPACT_CACHE_DIR="" suites "$@" | grep -cx "$w"; }

expect_eq "locates: a suite that runs the hook through the seam variable reads it" \
  "1" "$(has_suite lreader.test.sh "$LROOT" hooks/h1.sh)"
expect_eq "locates: …a suite that only sources the seam does not" \
  "0" "$(has_suite lseam.test.sh "$LROOT" hooks/h1.sh)"
expect_eq "locates: …and its edge is on the directory itself, so moving hooks/ still reaches it" \
  "1" "$(has_suite lseam.test.sh "$LROOT" hooks)"
expect_eq "locates: …with the reason locates" \
  "locates" "$(BIONIC_IMPACT_CACHE_DIR="" reason_for "$LROOT" lseam.test.sh hooks | cut -d: -f1)"
expect_eq "locates: a suite that globs the hooks directory itself still reads every hook" \
  "1" "$(has_suite lglob.test.sh "$LROOT" hooks/h3.sh)"
expect_eq "locates: a root-relative spelling after a command substitution is a read" \
  "1" "$(has_suite lsubst.test.sh "$LROOT" hooks/h3.sh)"
expect_eq "locates: a suite that runs a hook reads the hook that hook runs" \
  "1" "$(has_suite lrunner.test.sh "$LROOT" hooks/h1.sh)"
expect_eq "locates: …and not a hook it never runs" \
  "0" "$(has_suite lrunner.test.sh "$LROOT" hooks/h3.sh)"
expect_eq "locates: a one-line SAVED=…; H=… swap leaves H a path, so its sibling is read" \
  "1" "$(has_suite lswap.test.sh "$LROOT" hooks/h3.sh)"
expect_eq "locates: a hook beneath a located root that nothing names answers no suite" \
  "" "$(BIONIC_IMPACT_CACHE_DIR="" suites "$LROOT" hooks/h9.sh | grep -v '^lglob\.test\.sh$')"
expect_eq "locates: …except the suite that globs the whole directory" \
  "lglob.test.sh" "$(BIONIC_IMPACT_CACHE_DIR="" suites "$LROOT" hooks/h9.sh)"

# The real seam carries the annotation on both root lines, and the real hook
# answers the suites that read it, not the roster.
expect_eq "locates (real): resolve-roots.sh annotates its hooks and skills root lines" \
  "2" "$(grep -cE '^BIONIC_(HOOKS|SKILLS)_DIR=.*# impact: locates$' "$REPO/tests/lib/resolve-roots.sh")"
LR_POKER="$(suites "$REPO" hooks/session-poker.sh)"
LR_N="$(printf '%s\n' "$LR_POKER" | grep -c .)"
if [ "$LR_N" -gt 0 ] && [ "$LR_N" -lt "$RT_ROSTER" ]; then
  ok "locates (real): hooks/session-poker.sh answers $LR_N of $RT_ROSTER suites, not the roster"
else
  no "locates (real): hooks/session-poker.sh answers fewer than the roster" "$LR_N of $RT_ROSTER"
fi
for s in docs-pins.test.sh session-start.test.sh roster.test.sh patrol-stale.test.sh; do
  expect_eq "locates (real): $s, which names session-poker.sh, is still answered" \
    "1" "$(printf '%s\n' "$LR_POKER" | grep -cx "$s")"
done
expect_eq "locates (real): stop.test.sh reads stop-orders.sh as the sibling of its HOOK" \
  "1" "$(suites "$REPO" hooks/stop-orders.sh | grep -cx stop.test.sh)"
# The release-shaped files stay bounded: answered, and short of the roster.
for f in payload/.claude-plugin/plugin.json CHANGELOG.md payload/integrity/rendered.sha256 payload/commands/help.md; do
  n="$(suites "$REPO" "$f" | grep -c .)"
  if [ "$n" -gt 0 ] && [ "$n" -lt "$RT_ROSTER" ]; then
    ok "locates (real): $f stays bounded ($n of $RT_ROSTER)"
  else
    no "locates (real): $f stays bounded" "$n of $RT_ROSTER"
  fi
done

# ── §SWEEP a planted edit in every hook and skill file is reached ───────────
# THE GUARD ON THE NARROWING (D5). With the seam no longer an edge on every file,
# a hook or skill file is answered only by suites that name, copy, glob, pin or
# source it. The residual risk is a reader the map cannot see. This sweep lists
# every file under hooks/ and skills/ at test time, plants an edit in each one in a
# scratch copy of the tree, and asks the map about each planted file there, on the
# tree a change would actually present. Every plant must be reached by a suite the
# map names, and a hook must be reached short of the whole roster, and by at least
# one suite that reads that hook itself rather than only copying or globbing its
# directory.
#
# WHY STRUCTURAL AND NOT A RUN PER FILE. AC-19's §F runs real suites against the
# whole complement, and is opt-in for its cost. One witness run per planted file
# was measured at authoring time and its green control alone overran thirty minutes
# (T7-locates.md), so the gating form asks the map, not the suites. A file the map
# answers with no suite is not a silent pass: proof_state reads "no suite" as a
# full run (payload/scripts/lib/proof.sh, "the map answers %s with no suite").
section "§SWEEP every hook and skill file is reached"

SW_ROOT="$TMP/sweep"
mkdir -p "$SW_ROOT"
( cd "$REPO" && tar cf - --exclude=.git --exclude=.worktrees --exclude=.bionic . ) \
  | ( cd "$SW_ROOT" && tar xf - )
( cd "$SW_ROOT" && find hooks skills -type f | LC_ALL=C sort ) >"$TMP/sweep.files"
SW_N="$(grep -c . "$TMP/sweep.files")"
expect_eq "sweep: the file listing holds hooks/session-poker.sh" \
  "1" "$(grep -cx hooks/session-poker.sh "$TMP/sweep.files")"
expect_eq "sweep: …and skills/canonical-sdlc/SKILL.md" \
  "1" "$(grep -cx skills/canonical-sdlc/SKILL.md "$TMP/sweep.files")"
while IFS= read -r f; do
  printf '\n# BIONIC_IMPACT_SWEEP_PLANT\n' >>"$SW_ROOT/$f"
done <"$TMP/sweep.files"
expect_eq "sweep: an edit is planted in every listed file ($SW_N)" \
  "$SW_N" "$( ( cd "$SW_ROOT" && grep -l BIONIC_IMPACT_SWEEP_PLANT $(cat "$TMP/sweep.files") ) | grep -c .)"

SW_CACHE="$TMP/sweep-cache"
while IFS= read -r f; do
  ans="$(BIONIC_IMPACT_ROOT="$SW_ROOT" BIONIC_IMPACT_CACHE_DIR="$SW_CACHE" bash "$IMPACT" "$f" 2>/dev/null)"
  n="$(printf '%s\n' "$ans" | grep -c .)"
  if [ "$n" -gt 0 ]; then
    ok "sweep: the plant in $f is reached by $n named suite(s)"
  else
    no "sweep: the plant in $f is reached by a named suite" "the map names no suite"
  fi
  case "$f" in
    hooks/*)
      if [ "$n" -lt "$RT_ROSTER" ]; then
        ok "sweep: $f answers short of the roster ($n of $RT_ROSTER)"
      else
        no "sweep: $f answers short of the roster" "$n of $RT_ROSTER — the seam is still read as every hook"
      fi
      own="$(printf '%s\n' "$ans" | awk -F'\t' '{ k = $2; sub(/:.*/, "", k) }
        k != "payload-copy" && k != "dir-ref" && k != "locates" && k != "" { print $1 }' | head -1)"
      if [ -n "$own" ]; then
        ok "sweep: $f is read by a suite that reads the hook itself ($own)"
      else
        no "sweep: $f is read by a suite that reads the hook itself" \
          "only whole-directory readers answer it"
      fi
      ;;
  esac
done <"$TMP/sweep.files"


# ── §PRELUDE a suite's sibling prelude is a hop, like a tests/lib helper ────
# THE SHARDED SUITES (wave-30 T1; ruling A-orch-23). A long suite is split into
# shards that each source `tests/<suite>.prelude.sh`, which holds the fixtures,
# the code-under-test paths and the helpers the shards share. A shard reads every
# file its prelude names, so the map follows a `tests/*.prelude.sh` a suite
# sources exactly as it follows a tests/lib helper. The prelude stays OUTSIDE
# tests/lib on purpose: an edit to it reaches its own shards and no more, where an
# edit under tests/lib owes a full run (payload/scripts/lib/proof.sh, R2).
#
# fails-when: a shard is not answered for a file only its prelude names (the gate
# its prelude runs, or a library that gate sources); a suite that never sources
# the prelude is answered through it; a prelude is named as a suite; a prelude
# edit reaches beyond the suites that source it.
section "§PRELUDE a sibling prelude a suite sources is followed"

mk_prelude_root() { # mk_prelude_root <dir> <shard-2 sources the prelude: 1|0>
  local r="$1" src2="$2"
  mkdir -p "$r/tests/lib" "$r/hooks" "$r/payload/scripts/lib"
  printf '#!/bin/bash\n_r="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"\nBIONIC_HOOKS_DIR="${BIONIC_HOOKS_DIR:-${_r}/hooks}" # impact: locates\nexport BIONIC_HOOKS_DIR\n' \
    >"$r/tests/lib/resolve-roots.sh"
  printf '#!/bin/bash\nBIONIC_LIB="$(dirname "$0")/../payload/scripts/lib"\n. "$BIONIC_LIB/pl.sh"\necho h1\n' >"$r/hooks/h1.sh"
  printf '#!/bin/bash\npl() { :; }\n' >"$r/payload/scripts/lib/pl.sh"
  printf '#!/bin/bash\necho h2\n' >"$r/hooks/h2.sh"
  printf '# sourced by the s shards\nP_GATE="$BIONIC_HOOKS_DIR/h1.sh"\nrun_p() { bash "$P_GATE"; }\n' >"$r/tests/s.prelude.sh"
  local pre='#!/bin/bash\n. "$(dirname "$0")/lib/resolve-roots.sh"\n'
  printf "$pre"'. "$(dirname "$0")/s.prelude.sh"\nrun_p\n' >"$r/tests/s.test.sh"
  if [ "$src2" = 1 ]; then
    printf "$pre"'. "$(dirname "$0")/s.prelude.sh"\nrun_p\n' >"$r/tests/s-2.test.sh"
  else
    printf "$pre"'run_p\n' >"$r/tests/s-2.test.sh"
  fi
  printf "$pre"'bash "$BIONIC_HOOKS_DIR/h2.sh"\n' >"$r/tests/q.test.sh"
}
PROOT="$TMP/prelude"
mk_prelude_root "$PROOT" 1
P_H1="$(BIONIC_IMPACT_CACHE_DIR="" suites "$PROOT" hooks/h1.sh)"
expect_eq "prelude: the gate only the prelude names answers the shard that sources it" \
  "1" "$(printf '%s\n' "$P_H1" | grep -cx s.test.sh)"
expect_eq "prelude: …and the second shard" "1" "$(printf '%s\n' "$P_H1" | grep -cx s-2.test.sh)"
expect_eq "prelude: …and not the suite that never sources it" \
  "0" "$(printf '%s\n' "$P_H1" | grep -cx q.test.sh)"
expect_eq "prelude: …and never names the prelude itself as a suite" \
  "0" "$(printf '%s\n' "$P_H1" | grep -c 'prelude')"
expect_eq "prelude: the reason is the transitive hop, as for a tests/lib helper" \
  "transitive-lib" "$(BIONIC_IMPACT_CACHE_DIR="" reason_for "$PROOT" s.test.sh hooks/h1.sh | cut -d: -f1)"
P_PL="$(BIONIC_IMPACT_CACHE_DIR="" suites "$PROOT" payload/scripts/lib/pl.sh)"
expect_eq "prelude: a library the prelude's gate sources answers the shard too" \
  "1" "$(printf '%s\n' "$P_PL" | grep -cx s.test.sh)"
expect_eq "prelude: …and not the suite that never sources the prelude" \
  "0" "$(printf '%s\n' "$P_PL" | grep -cx q.test.sh)"
P_H2="$(BIONIC_IMPACT_CACHE_DIR="" suites "$PROOT" hooks/h2.sh)"
expect_eq "prelude: a hook the other suite names answers that suite" \
  "1" "$(printf '%s\n' "$P_H2" | grep -cx q.test.sh)"
expect_eq "prelude: …and not a shard whose prelude never names it" \
  "0" "$(printf '%s\n' "$P_H2" | grep -cx s.test.sh)"
expect_eq "prelude: an edit to the prelude reaches its shards and no more" \
  "s-2.test.sh s.test.sh" "$(BIONIC_IMPACT_CACHE_DIR="" suites "$PROOT" tests/s.prelude.sh | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')"

# THE HOP IS THE EDGE: the same tree with the second shard's source line removed
# loses that shard, and only that one.
PROOT_M="$TMP/prelude-mut"
mk_prelude_root "$PROOT_M" 0
anchor "$PROOT_M/tests/s-2.test.sh" 'run_p' 1
P_H1_M="$(BIONIC_IMPACT_CACHE_DIR="" suites "$PROOT_M" hooks/h1.sh)"
expect_eq "prelude (mutant): the shard that still sources the prelude is still answered" \
  "1" "$(printf '%s\n' "$P_H1_M" | grep -cx s.test.sh)"
expect_eq "prelude (mutant): …the shard that stopped sourcing it is not" \
  "0" "$(printf '%s\n' "$P_H1_M" | grep -cx s-2.test.sh)"

# THE REAL TREE. The gate the dispatch-preflight prelude names is read by each of
# its four shards, by a kind stronger than a whole-directory read, and the
# libraries the unsplit suite reached only through its prelude reach the shard
# that holds S1 … S22.
P_DP="$(suites "$REPO" hooks/dispatch-preflight.sh)"
P_DP_R="$(BIONIC_IMPACT_ROOT="$REPO" bash "$IMPACT" hooks/dispatch-preflight.sh 2>/dev/null)"
for s in dispatch-preflight.test.sh dispatch-preflight-2.test.sh dispatch-preflight-3.test.sh dispatch-preflight-4.test.sh; do
  expect_eq "prelude (real): hooks/dispatch-preflight.sh answers $s" \
    "1" "$(printf '%s\n' "$P_DP" | grep -cx "$s")"
  k="$(printf '%s\n' "$P_DP_R" | awk -F'\t' -v w="$s" '$1 == w { k = $2; sub(/:.*/, "", k); print k }')"
  expect_true "prelude (real): …by a read of the gate itself, not a directory (${k:-none})" \
    test -n "$k" -a "$k" != dir-ref -a "$k" != payload-copy -a "$k" != locates
done
for f in payload/scripts/lib/width.sh payload/scripts/lib/bounds.sh payload/scripts/lib/roots.sh \
         payload/scripts/lib/walls.sh payload/scripts/lib/git-argv.sh; do
  expect_eq "prelude (real): $f answers dispatch-preflight-2.test.sh" \
    "1" "$(suites "$REPO" "$f" | grep -cx dispatch-preflight-2.test.sh)"
done

finish
