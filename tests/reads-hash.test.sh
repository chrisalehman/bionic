#!/bin/bash
# tests/reads-hash.test.sh — payload/scripts/lib/anchors.sh, the read set a landing proof is keyed by
# (wave-39; D5, D6, D8; REQ-1, REQ-2).
#
# WHAT THIS SUITE OWNS. A suite's read set is what `reads_index` derives from its text at file grain,
# each file optionally narrowed by one declared line in the anchor grammar (D6):
#
#   reads <file> fn <function>        the suite reads only <function>'s body in <file>
#   reads <file> section <label>      …only the section of <file> under the banner `# ----- <label>`
#
# `reads_index` prints `<file>#<name> TAB <suite>` for a declaring suite and `<file> TAB <suite>` for
# an undeclared one; a declaration naming what the anchor finder cannot locate at the commit (or the
# tree) is refused at index time, naming the suite and the line, and the suite falls back to the whole
# file.
#
#   §NARROW          a fixture suite declaring `reads <file> fn <name>` and `section <label>` is indexed as
#                    `<file>#<name>`; an undeclared suite as `<file>`; a declaration in a heredoc body is
#                    fixture text; `--at` reads the commit, not the tree; `reads_suites` still routes the
#                    file to the narrowed suite (AC-2.1)
#   §NARROW-REFUSED  a declaration naming a function, section or file absent from the tree, a function
#                    defined twice, or a non-literal line is refused naming the suite and the line; rc 1;
#                    the suite reads the whole file (AC-2.1)
#
# FIXTURE FIDELITY: the tree under $F is SYNTHESIZED, each file placed for one arm. Nothing here is run:
# the index reads text.
#
# ANTI-VACUITY: the whole index at the commit is pinned by equality, so a skipped declaration or an empty
# extractor is red there first; each absence sits beside a positive read off the same index.
#
# Usage: bash tests/run.sh --only reads-hash.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"

REPO="${BIONIC_SCRIPTS_DIR}"
ANCHORS="$REPO/payload/scripts/lib/anchors.sh"

SB="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/reads-hash-test.XXXXXX")" && pwd)"
trap 'rm -rf "$SB"' EXIT
TAB="$(printf '\t')"

row_of() {  # row_of <file> <index text> -> the suites on <file>'s line
  printf '%s\n' "$2" | awk -F'\t' -v f="$1" '$1 == f { print $2 }'
}

# ------------------------------------------------------------
setup_section "plant the narrowing fixture and commit it"
# ------------------------------------------------------------
N="$SB/narrow"
mkdir -p "$N/payload/scripts/lib" "$N/tests"
cat > "$N/payload/scripts/lib/x.sh" <<'PLANT_X'
#!/bin/bash
alpha() {
  echo alpha-body
}
beta() { echo beta-body; }
dup() { echo one; }
dup() { echo two; }
# ---------------------------------------------------------------- the tail
tail_fn() {
  echo tail-body
}
PLANT_X
cat > "$N/tests/s-narrow.test.sh" <<'PLANT_NARROW'
#!/bin/bash
reads payload/scripts/lib/x.sh fn alpha
reads payload/scripts/lib/x.sh section 'the tail'
bash -c '. "$1/payload/scripts/lib/x.sh"; alpha' _ "$ROOT"
cat <<'FIXTURE'
reads payload/scripts/lib/x.sh fn beta
FIXTURE
PLANT_NARROW
cat > "$N/tests/s-whole.test.sh" <<'PLANT_WHOLE'
#!/bin/bash
grep -c alpha-body "$ROOT/payload/scripts/lib/x.sh"
PLANT_WHOLE
git -C "$N" init -q 2>/dev/null
git -C "$N" -c user.email=t@t -c user.name=t add -A
git -C "$N" -c user.email=t@t -c user.name=t commit -q -m one
N1="$(git -C "$N" rev-parse HEAD)"

# ------------------------------------------------------------
section "NARROW: a declaring suite is indexed as <file>#<name>, an undeclared suite as <file> (wave-39 T3; D6, AC-2.1)"
# ------------------------------------------------------------
# fails-when: the declaring suite is indexed as the whole file.
NW_IDX="$(bash "$ANCHORS" reads_index "$N" --at "$N1" 2>"$SB/nw.err")"; NW_RC=$?
expect_eq "NARROW: reads_index --at exits 0 over sound declarations" "0" "$NW_RC"
expect_eq "NARROW: …and refuses nothing" "" "$(cat "$SB/nw.err")"
NW_WANT="payload/scripts/lib/x.sh${TAB}tests/s-whole.test.sh
payload/scripts/lib/x.sh#alpha${TAB}tests/s-narrow.test.sh
payload/scripts/lib/x.sh#the tail${TAB}tests/s-narrow.test.sh
tests/s-narrow.test.sh${TAB}tests/s-narrow.test.sh
tests/s-whole.test.sh${TAB}tests/s-whole.test.sh"
expect_eq "NARROW: the whole index at the commit, pinned" "$NW_WANT" "$NW_IDX"
expect_eq "NARROW: the declaring suite reads x.sh#alpha" "tests/s-narrow.test.sh" "$(row_of 'payload/scripts/lib/x.sh#alpha' "$NW_IDX")"
expect_eq "NARROW: …and the section it names, x.sh#the tail" "tests/s-narrow.test.sh" "$(row_of 'payload/scripts/lib/x.sh#the tail' "$NW_IDX")"
expect_eq "NARROW: the undeclared suite alone reads the whole x.sh (the declaring one is not on that row)" \
  "tests/s-whole.test.sh" "$(row_of payload/scripts/lib/x.sh "$NW_IDX")"
expect_eq "NARROW: a declaration in a heredoc body is fixture text: no x.sh#beta row" "" \
  "$(row_of 'payload/scripts/lib/x.sh#beta' "$NW_IDX")"
NT_IDX="$(bash -c '. "$1"; reads_index "$2" -' _ "$ANCHORS" "$N" 2>&1)"
expect_eq "NARROW: the sourced form over the tree as it stands gives the same index" "$NW_WANT" "$NT_IDX"
# reads_declared is the declarations' own reader, with each located span (the landing intersects it with a diff).
expect_eq "NARROW: reads_declared names each declaration with the span the finder located" \
  "tests/s-narrow.test.sh${TAB}2${TAB}fn${TAB}payload/scripts/lib/x.sh${TAB}alpha${TAB}ok${TAB}2${TAB}4
tests/s-narrow.test.sh${TAB}3${TAB}section${TAB}payload/scripts/lib/x.sh${TAB}the tail${TAB}ok${TAB}8${TAB}11" \
  "$(bash -c '. "$1"; reads_declared "$2" "$3"' _ "$ANCHORS" "$N" "$N1" 2>&1)"
# The brief's and the wall's reader routes by file: a narrowed suite still lands on a row touching x.sh.
expect_eq "NARROW: reads_suites routes x.sh to both suites, the narrowed one included" \
  "s-narrow.test.sh
s-whole.test.sh" "$(bash -c '. "$1"; reads_suites "$2" "$3" payload/scripts/lib/x.sh' _ "$ANCHORS" "$N" "$N1" 2>&1)"
# --at reads the commit, never the tree: rename alpha in the tree only.
sed 's/^alpha()/alpha2()/' "$N/payload/scripts/lib/x.sh" > "$SB/x.sh" && cp "$SB/x.sh" "$N/payload/scripts/lib/x.sh"
expect_contains "NARROW: the tree's x.sh no longer defines alpha (the plant took)" "alpha2()" "$(cat "$N/payload/scripts/lib/x.sh")"
AT_IDX="$(bash "$ANCHORS" reads_index "$N" --at "$N1" 2>&1)"; AT_RC=$?
expect_eq "NARROW: --at the commit still exits 0 with the tree's alpha gone" "0" "$AT_RC"
expect_eq "NARROW: …and prints the commit's index, unchanged" "$NW_WANT" "$AT_IDX"
TR_ERR="$(bash "$ANCHORS" reads_index "$N" 2>&1 >/dev/null)"; TR_RC=$?
expect_eq "NARROW: the tree as it stands refuses the declaration it no longer holds" "1" "$TR_RC"
expect_contains "NARROW: …naming the suite and line, in the tree" \
  "tests/s-narrow.test.sh:2: reads payload/scripts/lib/x.sh fn alpha — no function alpha in payload/scripts/lib/x.sh (in the tree)" "$TR_ERR"
git -C "$N" checkout -q -- payload/scripts/lib/x.sh

# ------------------------------------------------------------
setup_section "plant a suite whose declarations the tree cannot hold, and commit it"
# ------------------------------------------------------------
cat > "$N/tests/s-gone.test.sh" <<'PLANT_GONE'
#!/bin/bash
reads payload/scripts/lib/x.sh fn alpha
reads payload/scripts/lib/x.sh fn gone
reads payload/scripts/lib/x.sh section 'no such banner'
reads payload/scripts/lib/nofile.sh fn alpha
reads "$ROOT/payload/scripts/lib/x.sh" fn alpha
reads payload/scripts/lib/x.sh fn dup
PLANT_GONE
git -C "$N" -c user.email=t@t -c user.name=t add -A
git -C "$N" -c user.email=t@t -c user.name=t commit -q -m two
N2="$(git -C "$N" rev-parse HEAD)"

# ------------------------------------------------------------
section "NARROW-REFUSED: a declaration naming what the tree does not hold is refused naming the suite and line (wave-39 T3; D6, AC-2.1)"
# ------------------------------------------------------------
# fails-when: a declaration naming a function absent from the tree is indexed, or refused without its line.
RF_IDX="$(bash "$ANCHORS" reads_index "$N" --at "$N2" 2>"$SB/rf.err")"; RF_RC=$?
RF_ERR="$(cat "$SB/rf.err")"
expect_eq "NARROW-REFUSED: reads_index exits 1 when a declaration is refused" "1" "$RF_RC"
expect_eq "NARROW-REFUSED: one refusal per bad line, each naming the suite, the line and why" \
  "anchors: reads_index refused tests/s-gone.test.sh:3: reads payload/scripts/lib/x.sh fn gone — no function gone in payload/scripts/lib/x.sh (at $N2)
anchors: reads_index refused tests/s-gone.test.sh:4: reads payload/scripts/lib/x.sh section no such banner — no section 'no such banner' in payload/scripts/lib/x.sh (at $N2)
anchors: reads_index refused tests/s-gone.test.sh:5: reads payload/scripts/lib/nofile.sh fn alpha — no file payload/scripts/lib/nofile.sh (at $N2)
anchors: reads_index refused tests/s-gone.test.sh:6: not a literal \`reads <file> fn <function>\` or \`reads <file> section <label>\` line (at $N2)
anchors: reads_index refused tests/s-gone.test.sh:7: reads payload/scripts/lib/x.sh fn dup — 2 functions dup in payload/scripts/lib/x.sh, one is needed (at $N2)" \
  "$RF_ERR"
expect_absent "NARROW-REFUSED: the sound declaration on line 2 is not refused" "s-gone.test.sh:2:" "$RF_ERR"
# A refused declaration narrows nothing: the suite reads the whole file it names (the undeclared default).
expect_eq "NARROW-REFUSED: the refusing suite reads the whole x.sh, beside the undeclared one" \
  "tests/s-gone.test.sh,tests/s-whole.test.sh" "$(row_of payload/scripts/lib/x.sh "$RF_IDX")"
expect_eq "NARROW-REFUSED: …and is not on x.sh#alpha, which the sound suite still holds" \
  "tests/s-narrow.test.sh" "$(row_of 'payload/scripts/lib/x.sh#alpha' "$RF_IDX")"
expect_eq "NARROW-REFUSED: no row for the file the tree does not hold" "" \
  "$(printf '%s\n' "$RF_IDX" | awk -F'\t' 'index($1, "nofile.sh")')"
expect_eq "NARROW-REFUSED: the earlier commit, with no such suite, still exits 0" "0" \
  "$(bash "$ANCHORS" reads_index "$N" --at "$N1" >/dev/null 2>&1; echo $?)"

finish
