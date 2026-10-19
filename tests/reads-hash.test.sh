#!/bin/bash
# tests/reads-hash.test.sh — payload/scripts/lib/anchors.sh, the read set a landing proof is keyed by
# (wave-39; D5, D6, D8; REQ-1, REQ-2; T3 the narrowing, T1 the key).
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
# THE KEY (wave-39 T1; D5, D8, A-orch-3; REQ-1 AC-1.3). `reads_set <root> <at> <suite>` is the suite's read set
# at a commit: what `reads_index` derives for it at file grain, closed over the scripts in it (what each names,
# its BIONIC_LIB_WANT list, so a library loaded by a library is read), plus the suite file and its prelude.
# `reads_hash <root> <at> <suite>` is sha256 over the set's sorted `<path> <blob>` lines; a suite whose closure
# holds a load whose file name is computed (`. "$d/$name"`) is keyed by the whole tree, `tree:<tree id>`.
#
#   §TREE     a suite loading a computed file name: `tree:<tree id>`, and two differing trees give two keys
#             (AC-1.3); a literal suite's key is a sha256 and survives a change outside its read set
#   §CLOSURE  a hook's WANT library loading another library by a variable: the second library is read, and a
#             change to it changes the key; `reads_index` itself does not close
#   §CLOSED-INDEX  `reads_index_closed` (`bash anchors.sh reads_index --closed`, wave-39 T40 for T24's judge) is
#             the file-to-suites index over the closed sets the key reads, in reads_index's shape, a narrowed pair
#             as `<file>#<name>`, each tree-keyed suite on a trailing `! TAB <suite>` line; at HEAD it names
#             session-poker.test.sh for lib/line.sh, which the plain index does not
#   §KEY      the key is sha256 over the sorted `<path> <blob>` lines, the suite file and its prelude among them
#   §AT       the commit is read, never the working tree
#   §LIVE     this repository at HEAD: the closure reaches payload/scripts/lib/line.sh from
#             tests/session-poker.test.sh, which runs hooks/session-poker.sh, and keys it by content
#
# ONE KEY SPACE (wave-39 T40; D5, D6, A-orch-13; REQ-2 AC-2.1, AC-2.2). `reads_hashes` is the one derivation: a
# declared `reads <file> fn|section <name>` whose every declaration on that file `reads_declared` locates contributes
# `<file>#<kind>:<name> <sha256 of the span's lines>` in place of `<file> <blob>`. The landing (lib/line.sh), the owed
# set and the regression facts all key through it; line.sh derives no key of its own.
#
#   §ONE      line.sh's key and anchors.sh's are one key on one fixture, a declaring suite among it (a mutant keying
#             line.sh through a second copy of the derivation flips it); a declared suite's key moves with its span
#             and not with another function in the file; an undeclared suite's, or one with a refused declaration
#             on the file, moves either way; line.sh holds no derivation
#
# THE VERB KIND (wave-39 T43; D6, A-orch-22; AC-2.1, AC-2.4). `reads <file> verb <name>` declares a case arm: every
# arm of the file's top-level case blocks whose label (alone or in a `a|b` list) is <name>, each from its label line
# to the `;;` at the label's indentation; the key reads the union of those spans.
#
#   §VERB     a verb with a parse arm and an exec arm (a nested case inside it) is keyed by both spans and by
#             neither of another verb's arms; a name no arm bears is refused `noverb`; a mutant taking the first
#             arm only flips
#
# FIXTURE FIDELITY: the trees under $N and $F are SYNTHESIZED, each file placed for one arm. Nothing here is run:
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


F="$SB/tree"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0

rh_set() { ( . "$ANCHORS" && reads_set "$@" ) 2>/dev/null; }      # <root> <at> <suite>
rh_hash() { ( . "$ANCHORS" && reads_hash "$@" ) 2>/dev/null; }    # <root> <at> <suite>
rh_index() { ( . "$ANCHORS" && reads_index "$@" ) 2>/dev/null; }  # <root> <at>
rh_closed() { ( . "$ANCHORS" && reads_index_closed "$@" ) 2>/dev/null; }  # <root> <at>
rh_commit() { git -C "$F" add -A && git -C "$F" commit -qm "$1" && git -C "$F" rev-parse HEAD; }   # <message> -> the commit
rh_sha() { if command -v shasum >/dev/null 2>&1; then shasum -a 256; else sha256sum; fi | awk '{ print $1 }'; }

# ------------------------------------------------------------
setup_section "plant the fixture tree and commit it"
# ------------------------------------------------------------
mkdir -p "$F/payload/scripts/lib" "$F/hooks" "$F/tests"
git -C "$F" init -q && git -C "$F" config user.email t@t && git -C "$F" config user.name t && git -C "$F" config commit.gpgsign false
# a.sh loads b.sh by a variable, the way lib/worktree.sh loads lib/line.sh: a library loaded by a library.
cat > "$F/payload/scripts/lib/a.sh" <<'PLANT'
lib="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/b.sh"
[ -r "$lib" ] && . "$lib"
PLANT
printf 'echo b\n' > "$F/payload/scripts/lib/b.sh"
printf 'echo c, read by no suite\n' > "$F/payload/scripts/lib/c.sh"
cat > "$F/hooks/h.sh" <<'PLANT'
#!/bin/bash
BIONIC_LIB_WANT="a.sh"
. "$BIONIC_LIB/a.sh"
PLANT
cat > "$F/tests/s-hook.test.sh" <<'PLANT'
#!/bin/bash
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
bash "$ROOT/hooks/h.sh"
PLANT
# A file name built at run time: no text names what it loads.
cat > "$F/tests/s-var.test.sh" <<'PLANT'
#!/bin/bash
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
name="$(ls "$ROOT/payload/scripts/lib" | head -1)"
. "$ROOT/payload/scripts/lib/$name"
PLANT
# A loop over literal names is resolved: each name is spelled.
cat > "$F/tests/s-loop.test.sh" <<'PLANT'
#!/bin/bash
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
for f in b.sh; do . "$ROOT/payload/scripts/lib/$f"; done
PLANT
# A suite that never names its prelude still reads it (D8).
printf '#!/bin/bash\necho pre\n' > "$F/tests/s-pre.test.sh"
printf 'echo prelude\n' > "$F/tests/s-pre.prelude.sh"
C1="$(rh_commit one)"
expect_nonempty "(fixture) the first commit" "$C1"

# ------------------------------------------------------------
section "§TREE: a suite loading a computed file name is keyed by the whole tree; two trees, two keys (AC-1.3)"
# ------------------------------------------------------------
T1="$(git -C "$F" rev-parse "$C1^{tree}")"
K1="$(rh_hash "$F" "$C1" tests/s-var.test.sh)"
expect_eq "TREE: s-var, which loads \"\$ROOT/…/\$name\", is keyed tree:<the commit's tree>" "tree:$T1" "$K1"
expect_contains "TREE: …and reads_set says why, naming the load" "tree " "$(rh_set "$F" "$C1" tests/s-var.test.sh)"
printf 'echo c, changed\n' > "$F/payload/scripts/lib/c.sh"
C2="$(rh_commit two)"
K2="$(rh_hash "$F" "$C2" tests/s-var.test.sh)"
expect_eq "TREE: at a second commit it is keyed by that tree" "tree:$(git -C "$F" rev-parse "$C2^{tree}")" "$K2"
expect_ne "TREE: …so two trees that differ give two keys: no reuse across them" "$K1" "$K2"
H1="$(rh_hash "$F" "$C1" tests/s-hook.test.sh)"
expect_regex "TREE: a suite whose loads all resolve is keyed by a sha256 of its reads, not the tree" '^[0-9a-f]{64}$' "$H1"
expect_eq "TREE: …which a change outside its read set (c.sh) leaves alone" "$H1" "$(rh_hash "$F" "$C2" tests/s-hook.test.sh)"
expect_regex "TREE: a loop over spelled names (for f in b.sh) resolves: a sha256" '^[0-9a-f]{64}$' "$(rh_hash "$F" "$C1" tests/s-loop.test.sh)"
expect_contains "TREE: …and reads what it names" "payload/scripts/lib/b.sh" "$(rh_set "$F" "$C1" tests/s-loop.test.sh)"
expect_eq "TREE: a suite the commit lacks is keyed by the tree" "tree:$T1" "$(rh_hash "$F" "$C1" tests/nope.test.sh)"

# ------------------------------------------------------------
section "§CLOSURE: the read set closes over a library loaded by a library (A-orch-3)"
# ------------------------------------------------------------
expect_eq "CLOSURE: s-hook reads the hook, its WANT library a.sh, the library a.sh loads (b.sh) and itself" \
  "$(printf '%s\n' hooks/h.sh payload/scripts/lib/a.sh payload/scripts/lib/b.sh tests/s-hook.test.sh)" \
  "$(rh_set "$F" "$C1" tests/s-hook.test.sh)"
printf 'echo b, changed\n' > "$F/payload/scripts/lib/b.sh"
C3="$(rh_commit three)"
expect_ne "CLOSURE: a change to b.sh changes s-hook's key" "$H1" "$(rh_hash "$F" "$C3" tests/s-hook.test.sh)"
IX="$(rh_index "$F" "$C1")"
expect_contains "CLOSURE: reads_index itself still names s-hook for a.sh (rule 2)" "$(printf 'payload/scripts/lib/a.sh\ttests/s-hook.test.sh')" "$IX"
expect_no_match "CLOSURE: …and is unchanged by the closure: nothing names s-hook for b.sh there" "payload/scripts/lib/b\\.sh.*s-hook" "$IX"

# ------------------------------------------------------------
section "§CLOSED-INDEX: the file-to-suites index over the closed sets, the one the owed set's judge joins on (wave-39 T40; D5, A-orch-3)"
# ------------------------------------------------------------
# fails-when: a suite reaching a file only through the closure is missing from the file's row (ci1, ci4), a tree-keyed
# suite is not marked (ci2), or the shape is not reads_index's (ci3).
CX="$(rh_closed "$F" "$C1")"
expect_eq "(ci1) the closed index names s-hook for b.sh, the library a.sh loads (closure only), beside s-loop, which names it" \
  "tests/s-hook.test.sh,tests/s-loop.test.sh" "$(row_of payload/scripts/lib/b.sh "$CX")"
expect_eq "(ci1) …and for a.sh, as the plain index does" "$(row_of payload/scripts/lib/a.sh "$IX")" "$(row_of payload/scripts/lib/a.sh "$CX")"
expect_eq "(ci2) s-var, keyed by the tree, is marked on a trailing ! line, as reads_hashes keys it" \
  "$(printf '!\ttests/s-var.test.sh')" "$(printf '%s\n' "$CX" | grep '^!')"
expect_eq "(ci2) …the ! lines come last" "!" "$(printf '%s\n' "$CX" | tail -n 1 | cut -c1)"
expect_eq "(ci3) every other line is reads_index's shape: <file> TAB <suite>[,<suite>]" "0" \
  "$(printf '%s\n' "$CX" | grep -v '^!' | grep -cv "^[^$TAB]*${TAB}tests/[^$TAB]*\$")"
expect_eq "(ci3) …from the command line too: bash anchors.sh reads_index --closed <root> --at <commit>" "$CX" \
  "$(bash "$ANCHORS" reads_index --closed "$F" --at "$C1" 2>/dev/null)"

# ------------------------------------------------------------
section "§KEY: sha256 over the sorted <path> <blob> lines, the suite file and its prelude among them (D8)"
# ------------------------------------------------------------
PS="$(rh_set "$F" "$C1" tests/s-pre.test.sh)"
expect_eq "KEY: s-pre's set is the suite and its prelude, which it never names" \
  "$(printf '%s\n' tests/s-pre.prelude.sh tests/s-pre.test.sh)" "$PS"
WANT="$(git -C "$F" ls-tree -r "$C1" -- hooks/h.sh payload/scripts/lib/a.sh payload/scripts/lib/b.sh tests/s-hook.test.sh \
  | awk -F'\t' '{ split($1, m, " "); print $2 " " m[3] }' | LC_ALL=C sort | rh_sha)"
expect_eq "KEY: s-hook's key is sha256 of its four sorted '<path> <blob>' lines" "$WANT" "$H1"

# ------------------------------------------------------------
section "§AT: the commit is read, never the working tree"
# ------------------------------------------------------------
K3="$(rh_hash "$F" "$C3" tests/s-hook.test.sh)"
expect_regex "(at) s-hook's key at the third commit" '^[0-9a-f]{64}$' "$K3"
printf 'echo b, uncommitted\n' > "$F/payload/scripts/lib/b.sh"
expect_contains "(at) …the edit is there to be read: the working tree differs from the commit" "payload/scripts/lib/b.sh" "$(git -C "$F" status --porcelain)"
expect_eq "AT: an uncommitted edit to b.sh leaves the key at the commit as it was" "$K3" "$(rh_hash "$F" "$C3" tests/s-hook.test.sh)"

# ------------------------------------------------------------
section "§LIVE: this repository at HEAD — the closure reaches lib/line.sh from a suite that runs hooks/session-poker.sh"
# ------------------------------------------------------------
LH="$(git -C "$REPO" rev-parse --verify -q HEAD)"
expect_nonempty "(live) the repository under test has a HEAD" "$LH"
LS="$(rh_set "$REPO" "$LH" tests/session-poker.test.sh)"
expect_contains "LIVE: session-poker.test.sh reads hooks/session-poker.sh" "hooks/session-poker.sh" "$LS"
expect_contains "LIVE: …and, through the closure, payload/scripts/lib/line.sh" "payload/scripts/lib/line.sh" "$LS"
expect_regex "LIVE: …and its key is a sha256 of its reads, not the tree" '^[0-9a-f]{64}$' "$(rh_hash "$REPO" "$LH" tests/session-poker.test.sh)"
LIX="$(rh_index "$REPO" "$LH")"; LCX="$(rh_closed "$REPO" "$LH")"
expect_contains "(ci4-pre) the plain index has a row for lib/line.sh: landing-line.test.sh names it" "tests/landing-line.test.sh" "$(row_of payload/scripts/lib/line.sh "$LIX")"
expect_no_match "(ci4) …which does not name session-poker.test.sh: it reaches line.sh only through hooks/session-poker.sh's loads" \
  'tests/session-poker\.test\.sh' "$(row_of payload/scripts/lib/line.sh "$LIX")"
expect_contains "(ci4) the closed index's row for lib/line.sh names session-poker.test.sh" "tests/session-poker.test.sh" "$(row_of payload/scripts/lib/line.sh "$LCX")"
expect_contains "(ci4) …and landing-line.test.sh, as the plain one does" "tests/landing-line.test.sh" "$(row_of payload/scripts/lib/line.sh "$LCX")"

# ------------------------------------------------------------
setup_section "plant the one-key fixture: calc.sh's one() and two(), a suite declaring one(), one declaring nothing, one refused"
# ------------------------------------------------------------
O="$SB/one"
mkdir -p "$O/payload/scripts/lib" "$O/tests"
git -C "$O" init -q && git -C "$O" config user.email t@t && git -C "$O" config user.name t && git -C "$O" config commit.gpgsign false
one_calc() { printf '#!/bin/bash\none() {\n  echo %s\n}\ntwo() {\n  echo %s\n}\n' "$1" "$2" > "$O/payload/scripts/lib/calc.sh"; }   # <one's word> <two's word>
one_commit() { git -C "$O" add -A && git -C "$O" commit -qm "$1" && git -C "$O" rev-parse HEAD; }   # <message> -> the commit
one_calc 1 2
cat > "$O/tests/s-a.test.sh" <<'PLANT'
#!/bin/bash
reads payload/scripts/lib/calc.sh fn one
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
. "$ROOT/payload/scripts/lib/calc.sh"; one
PLANT
cat > "$O/tests/s-c.test.sh" <<'PLANT'
#!/bin/bash
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
. "$ROOT/payload/scripts/lib/calc.sh"; one; two
PLANT
cat > "$O/tests/s-r.test.sh" <<'PLANT'
#!/bin/bash
reads payload/scripts/lib/calc.sh fn one
reads payload/scripts/lib/calc.sh fn nope
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
. "$ROOT/payload/scripts/lib/calc.sh"; one
PLANT
O1="$(one_commit one)"
expect_nonempty "(one) the fixture's first commit" "$O1"
LINE="$REPO/payload/scripts/lib/line.sh"
one_line() { ( . "$LINE" && _LINE_RH="" && _LINE_RH_SUITES="" && _line_reads "$@" ) 2>/dev/null; }   # <root> <at> <suite> -> the landing's key

# ------------------------------------------------------------
section "§ONE: line.sh and anchors.sh give one key; a declared suite's key moves with its span only (wave-39 T40; D5, D6, AC-2.1, AC-2.2)"
# ------------------------------------------------------------
# fails-when: line.sh keys a suite another way than anchors.sh (one1, one6m), the narrowing lives anywhere but
# reads_hashes (one2, one5), or a declared suite's key moves on a change outside its span (one3).
A1="$(rh_hash "$O" "$O1" tests/s-a.test.sh)"
expect_regex "(one1-pre) s-a's key at the first commit is a sha256" '^[0-9a-f]{64}$' "$A1"
expect_eq "(one1) the landing (line.sh _line_reads) and anchors.sh reads_hash give s-a, which declares one(), one key" \
  "$A1" "$(one_line "$O" "$O1" s-a.test.sh)"
expect_eq "(one1) …and s-c, which declares nothing" "$(rh_hash "$O" "$O1" tests/s-c.test.sh)" "$(one_line "$O" "$O1" s-c.test.sh)"
expect_eq "(one1) …and s-r, whose second declaration is refused" "$(rh_hash "$O" "$O1" tests/s-r.test.sh)" "$(one_line "$O" "$O1" s-r.test.sh)"
SPAN="$(git -C "$O" show "$O1:payload/scripts/lib/calc.sh" | sed -n 2,4p | rh_sha)"
SUITE_BLOB="$(git -C "$O" rev-parse "$O1:tests/s-a.test.sh")"
expect_eq "(one2) s-a's key is sha256 of its sorted lines, the declared function's span sha256 in place of calc.sh's blob" \
  "$(printf '%s\n' "payload/scripts/lib/calc.sh#fn:one $SPAN" "tests/s-a.test.sh $SUITE_BLOB" | LC_ALL=C sort | rh_sha)" "$A1"
C1K="$(rh_hash "$O" "$O1" tests/s-c.test.sh)"; R1K="$(rh_hash "$O" "$O1" tests/s-r.test.sh)"
one_calc 1 22
O2="$(one_commit "two() changes")"
expect_ne "(one3-pre) the second commit changes calc.sh's blob: a file s-a reads, outside its span" \
  "$(git -C "$O" rev-parse "$O1:payload/scripts/lib/calc.sh")" "$(git -C "$O" rev-parse "$O2:payload/scripts/lib/calc.sh")"
expect_eq "(one3) a change to two() leaves s-a's key alone: it declares one()" "$A1" "$(rh_hash "$O" "$O2" tests/s-a.test.sh)"
expect_eq "(one3) …and the landing reads the same key there" "$A1" "$(one_line "$O" "$O2" s-a.test.sh)"
expect_ne "(one4) …while s-c's moves: it declares nothing, so it reads the whole file" "$C1K" "$(rh_hash "$O" "$O2" tests/s-c.test.sh)"
expect_ne "(one4) …and s-r's: a refused declaration on the file keys the pair whole" "$R1K" "$(rh_hash "$O" "$O2" tests/s-r.test.sh)"
C2K="$(rh_hash "$O" "$O2" tests/s-c.test.sh)"
one_calc 11 22
O3="$(one_commit "one() changes")"
A3="$(rh_hash "$O" "$O3" tests/s-a.test.sh)"
expect_regex "(one5-pre) s-a's key at the third commit is a sha256" '^[0-9a-f]{64}$' "$A3"
expect_ne "(one5) a change to one() moves s-a's key: its span changed" "$A1" "$A3"
expect_ne "(one5) …and s-c's, either way" "$C2K" "$(rh_hash "$O" "$O3" tests/s-c.test.sh)"
expect_eq "(one5) …the landing reads s-a's new key" "$A3" "$(one_line "$O" "$O3" s-a.test.sh)"
expect_eq "(ci5) the closed index narrows as reads_index does: s-a on calc.sh#one, s-c and s-r on calc.sh" \
  "tests/s-a.test.sh|tests/s-c.test.sh,tests/s-r.test.sh" \
  "$(CO="$(rh_closed "$O" "$O3")"; printf '%s|%s' "$(row_of 'payload/scripts/lib/calc.sh#one' "$CO")" "$(row_of payload/scripts/lib/calc.sh "$CO")")"
expect_eq "(one6) line.sh keys through anchors.sh reads_hashes" "1" "$(grep -c 'got="$(reads_hashes ' "$LINE")"
expect_eq "(one6) …and derives no key of its own: no narrowing, no closure read, no sha256 there" "0" \
  "$(grep -c -e '_line_reads_keys' -e '_rd_closed' -e '_rd_sha256' -e 'reads_declared' "$LINE")"
# MUTANT: the key computed twice. line.sh keys through a second copy of the derivation, one whose narrowing has
# drifted (ignored): s-c still agrees, so the mutant ran; s-a's two keys part.
anchor fn payload/scripts/lib/anchors.sh 'narrow="$(_rd_narrowed "$root" "$at")"' reads_hashes 'narrow=""'
ONE_DRIFT="$ANCHOR_SED"
anchor fn payload/scripts/lib/line.sh 'got="$(reads_hashes "$1" "$2" $want 2>/dev/null)"' _line_reads_fill \
  'got="$(_line_own_keys "$1" "$2" $want 2>/dev/null)"'
ONE_TWICE="$ANCHOR_SED"
one_twice() {  # <root> <at> <suite> -> the landing's key under the mutant
  ( . "$LINE" && _line_load_anchors \
      && eval "$(declare -f reads_hashes | sed "1s/^reads_hashes/_line_own_keys/; $ONE_DRIFT")" \
      && eval "$(declare -f _line_reads_fill | sed "$ONE_TWICE")" \
      && _LINE_RH="" && _LINE_RH_SUITES="" && _line_reads "$@" ) 2>/dev/null
}
expect_eq "(one6m-pre) the mutant runs: s-c, which declares nothing, keys as before under it" \
  "$(rh_hash "$O" "$O3" tests/s-c.test.sh)" "$(one_twice "$O" "$O3" s-c.test.sh)"
expect_ne "(one6m) MUTANT key computed twice: s-a's landing key parts from anchors.sh's" "$A3" "$(one_twice "$O" "$O3" s-a.test.sh)"


# ------------------------------------------------------------
setup_section "plant the verb fixture: v.sh's parse case and exec case, go's arm in each (a nested case in the exec arm), stay's arm in each"
# ------------------------------------------------------------
V="$SB/verb"
mkdir -p "$V/payload/scripts/lib" "$V/tests"
git -C "$V" init -q && git -C "$V" config user.email t@t && git -C "$V" config user.name t && git -C "$V" config commit.gpgsign false
# The four words are go's parse arm, go's exec arm (inside its nested case), stay's parse arm, stay's exec arm.
# Lines: go's arms run 5-7 (the alias list go|went) and 16-26; stay's 8-10 and 28-35; a nested `go)` at 30 sits
# inside stay's exec arm, deeper than the case's own arms, so it is no arm of go.
verb_plant() {  # <go parse> <go exec> <stay parse> <stay exec>
  sed -e "s/@GP@/$1/" -e "s/@GX@/$2/" -e "s/@SP@/$3/" -e "s/@SX@/$4/" > "$V/payload/scripts/lib/v.sh" <<'PLANT_V'
#!/bin/bash
VERB="${1:-}"; shift
# ---------------------------------------------------------------- parse
case "$VERB" in
  go|went)
    GO_ARG="${1:-@GP@}"
    ;;
  stay)
    STAY_ARG="${1:-@SP@}"
    ;;
  *) echo "unknown verb" >&2; exit 2 ;;
esac
# ---------------------------------------------------------------- exec
case "$VERB" in

  go)
    case "$GO_ARG" in
      fast)
        echo go-fast
        ;;
      *)
        echo @GX@
        ;;
    esac
    exit 0
    ;;

  stay)
    case "$STAY_ARG" in
      go)
        echo @SX@
        ;;
    esac
    exit 0
    ;;
esac
PLANT_V
}
verb_commit() { git -C "$V" add -A && git -C "$V" commit -qm "$1" && git -C "$V" rev-parse HEAD; }   # <message> -> the commit
verb_plant p1 x1 sp1 sx1
cat > "$V/tests/s-verb.test.sh" <<'PLANT'
#!/bin/bash
reads payload/scripts/lib/v.sh verb go
bash "$ROOT/payload/scripts/lib/v.sh" go fast
PLANT
cat > "$V/tests/s-plain.test.sh" <<'PLANT'
#!/bin/bash
bash "$ROOT/payload/scripts/lib/v.sh" stay
PLANT
cat > "$V/tests/s-none.test.sh" <<'PLANT'
#!/bin/bash
reads payload/scripts/lib/v.sh verb nothere
bash "$ROOT/payload/scripts/lib/v.sh" go
PLANT
V1="$(verb_commit one)"
expect_nonempty "(verb) the fixture's first commit" "$V1"
expect_eq "(verb) the plant took: go's exec arm holds its word at line 22" "        echo x1" \
  "$(git -C "$V" show "$V1:payload/scripts/lib/v.sh" | sed -n 22p)"

# ------------------------------------------------------------
section "§VERB: reads <file> verb <name> locates every case arm bearing the name; the key moves with either arm only (wave-39 T43; D6, AC-2.1, AC-2.4, A-orch-22)"
# ------------------------------------------------------------
# fails-when: a verb declaration is not read (v1), an arm is missed or a nested case's arm is taken (v1, v4), a
# name no arm bears is not refused (v1, v2), or the key does not move with either arm (v5, v6) or moves with
# another verb's (v4); the mutant taking the first arm only flips v6.
VD="$(bash -c '. "$1"; reads_declared "$2" "$3"' _ "$ANCHORS" "$V" "$V1" 2>&1)"
expect_eq "(v1) reads_declared prints one ok line per arm of go, parse then exec, and noverb for a name no arm bears" \
  "tests/s-none.test.sh${TAB}2${TAB}verb${TAB}payload/scripts/lib/v.sh${TAB}nothere${TAB}noverb${TAB}-${TAB}-
tests/s-verb.test.sh${TAB}2${TAB}verb${TAB}payload/scripts/lib/v.sh${TAB}go${TAB}ok${TAB}5${TAB}7
tests/s-verb.test.sh${TAB}2${TAB}verb${TAB}payload/scripts/lib/v.sh${TAB}go${TAB}ok${TAB}16${TAB}26" "$VD"
VI="$(bash "$ANCHORS" reads_index "$V" --at "$V1" 2>"$SB/v.err")"; VI_RC=$?
expect_eq "(v2) reads_index exits 1: the noverb declaration is refused" "1" "$VI_RC"
expect_eq "(v2) …naming the suite, the line and why" \
  "anchors: reads_index refused tests/s-none.test.sh:2: reads payload/scripts/lib/v.sh verb nothere — no case arm nothere in payload/scripts/lib/v.sh (at $V1)" \
  "$(cat "$SB/v.err")"
expect_eq "(v2) the declaring suite is indexed as v.sh#go" "tests/s-verb.test.sh" "$(row_of 'payload/scripts/lib/v.sh#go' "$VI")"
expect_eq "(v2) …and the refused one reads the whole v.sh, beside the undeclared one" \
  "tests/s-none.test.sh,tests/s-plain.test.sh" "$(row_of payload/scripts/lib/v.sh "$VI")"
expect_eq "(v3) the closed index narrows the verb as reads_index does" "tests/s-verb.test.sh" \
  "$(row_of 'payload/scripts/lib/v.sh#go' "$(rh_closed "$V" "$V1")")"
K1="$(rh_hash "$V" "$V1" tests/s-verb.test.sh)"
expect_regex "(v3-pre) s-verb's key at the first commit is a sha256" '^[0-9a-f]{64}$' "$K1"
VA="$(git -C "$V" show "$V1:payload/scripts/lib/v.sh" | sed -n 5,7p | rh_sha)"
VB="$(git -C "$V" show "$V1:payload/scripts/lib/v.sh" | sed -n 16,26p | rh_sha)"
expect_eq "(v3) s-verb's key is sha256 of its sorted lines, each arm's span sha256 under v.sh#verb:go, in place of v.sh's blob" \
  "$(printf '%s\n' "payload/scripts/lib/v.sh#verb:go $VA" "payload/scripts/lib/v.sh#verb:go $VB" \
       "tests/s-verb.test.sh $(git -C "$V" rev-parse "$V1:tests/s-verb.test.sh")" | LC_ALL=C sort | rh_sha)" "$K1"
P1="$(rh_hash "$V" "$V1" tests/s-plain.test.sh)"
verb_plant p1 x1 sp2 sx2
V2="$(verb_commit "stay's arms change")"
expect_ne "(v4-pre) the change to stay's arms reaches a file s-plain reads whole: its key moves" "$P1" "$(rh_hash "$V" "$V2" tests/s-plain.test.sh)"
expect_eq "(v4) a change to stay's two arms, the nested go) among them, leaves s-verb's key alone" "$K1" "$(rh_hash "$V" "$V2" tests/s-verb.test.sh)"
verb_plant p2 x1 sp2 sx2
V3="$(verb_commit "go's parse arm changes")"
K3="$(rh_hash "$V" "$V3" tests/s-verb.test.sh)"
expect_regex "(v5-pre) s-verb's key at the third commit is a sha256" '^[0-9a-f]{64}$' "$K3"
expect_ne "(v5) a change to go's parse arm moves s-verb's key" "$K1" "$K3"
verb_plant p2 x2 sp2 sx2
V4="$(verb_commit "go's exec arm changes, inside its nested case")"
expect_ne "(v6) a change to go's exec arm, inside its nested case, moves s-verb's key" "$K3" "$(rh_hash "$V" "$V4" tests/s-verb.test.sh)"
# MUTANT: the finder takes the first arm only. It still runs (the parse arm alone is declared); the exec arm's
# change then leaves the key alone.
anchor file payload/scripts/lib/anchors.sh 'j <= c[i]; j++' 'j <= 1 && j <= c[i]; j++' "$SB/anchors-first.sh"
vm_hash() { ( . "$SB/anchors-first.sh" && reads_hash "$@" ) 2>/dev/null; }   # <root> <at> <suite> under the mutant
expect_eq "(v6m-pre) the mutant runs: reads_declared under it prints go's parse arm alone" \
  "tests/s-verb.test.sh${TAB}2${TAB}verb${TAB}payload/scripts/lib/v.sh${TAB}go${TAB}ok${TAB}5${TAB}7" \
  "$(bash -c '. "$1"; reads_declared "$2" "$3"' _ "$SB/anchors-first.sh" "$V" "$V3" 2>&1 | awk -F'\t' '$1 == "tests/s-verb.test.sh"')"
expect_regex "(v6m-pre) …and keys s-verb by a sha256 at the exec arm's change" '^[0-9a-f]{64}$' "$(vm_hash "$V" "$V4" tests/s-verb.test.sh)"
expect_eq "(v6m) MUTANT first arm only: go's exec arm changes and the key does not move" \
  "$(vm_hash "$V" "$V3" tests/s-verb.test.sh)" "$(vm_hash "$V" "$V4" tests/s-verb.test.sh)"


finish
