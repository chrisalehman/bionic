#!/bin/bash
# tests/suite-reads.test.sh — payload/scripts/lib/anchors.sh `reads_index`, the one file-to-suite
# fact (wave-36 T5; D12, REQ-6 AC-6.1; ADR-056).
#
# WHAT THIS SUITE OWNS. For every file a suite reads, `reads_index` prints
# `<file> TAB <suite>[,<suite>]`, files sorted, each file's suites sorted and unique. A suite
# (tests/*.test.sh) reads a file when
#   - its text names the file's path or basename outside a comment (the name scan),
#   - it names a file carrying a `BIONIC_LIB_WANT=` line, which reads each library listed there,
#   - it is the file itself,
#   - or the anchor index (`anchors_index`) says it declares an anchor on the file (folded in).
# `--at <commit>` reads the commit out of git's objects; without it the tree as it stands.
#
#   §INDEX  fixture suites that grep, anchor and run a hook listing walls.sh → all three named;
#           a comment, a longer name, an ignored suite and a library list that is not literal
#           name nothing; a qualified path
#           names only the file it qualifies; --at reads the commit, not the tree
#   §PRELUDE  a tests/*.prelude.sh or tests/lib/*.sh the suite names is scanned as its own text, one hop
#           (wave-37 T3; D4): the hook a prelude runs, its libraries, a helper's grep; not a second prelude's
#   §DIR    `find <dir>` and `<dir>/*glob`, one $VAR hop resolved in the same text, read every file under
#           the directory, the glob filtering by basename; a commented walk reads nothing
#   §AGREE  `reads_suites`, the brief's reader and the wall's reader (lifted from the shipped hooks) and
#           reads_index answer one set over one fixture; a mutant dropping the hop's stream is red
#
# FIXTURE FIDELITY: the tree under $F is SYNTHESIZED, each file placed for one arm. Nothing
# here is run: the index reads text.
#
# ANTI-VACUITY: the whole index at the commit is pinned by equality, so a skipped file or an empty
# extractor is red there first; each absence (the comment, the ignored suite) sits beside a positive
# read off the same row of the same index.
#
# Usage: bash tests/run.sh --only suite-reads.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"

REPO="${BIONIC_SCRIPTS_DIR}"
ANCHORS="$REPO/payload/scripts/lib/anchors.sh"

SB="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/suite-reads-test.XXXXXX")" && pwd)"
trap 'rm -rf "$SB"' EXIT
F="$SB/tree"
TAB="$(printf '\t')"

# ------------------------------------------------------------
setup_section "plant the fixture tree and commit it"
# ------------------------------------------------------------
mkdir -p "$F/payload/scripts/lib" "$F/hooks" "$F/tests" "$F/tools"
printf 'needle-line\n' > "$F/payload/scripts/lib/walls.sh"
printf 'root_fn() {\n  echo needle\n}\n' > "$F/payload/scripts/lib/root.sh"
printf 'echo lib-run\n' > "$F/payload/scripts/lib/run.sh"
printf 'echo runner\n' > "$F/tests/run.sh"
printf 'tests/s-ign.test.sh\n' > "$F/.gitignore"
cat > "$F/hooks/h.sh" <<'PLANT_HOOK'
#!/bin/bash
BIONIC_LIB_WANT="root.sh walls.sh"
echo hook
PLANT_HOOK
cat > "$F/hooks/g.sh" <<'PLANT_HOOK_G'
#!/bin/bash
BIONIC_LIB_WANT="${2:-}"
PLANT_HOOK_G
cat > "$F/tests/s-grep.test.sh" <<'PLANT_GREP'
#!/bin/bash
ROOT="$1"
grep -c needle-line "$ROOT/payload/scripts/lib/walls.sh"
PLANT_GREP
cat > "$F/tests/s-anchor.test.sh" <<'PLANT_ANCHOR'
#!/bin/bash
anchor file payload/scripts/lib/walls.sh 'needle-line'
PLANT_ANCHOR
cat > "$F/tests/s-hook.test.sh" <<'PLANT_HOOKRUN'
#!/bin/bash
bash "$ROOT/hooks/h.sh" tick
bash "$ROOT/hooks/g.sh" tick
PLANT_HOOKRUN
cat > "$F/tests/s-comment.test.sh" <<'PLANT_COMMENT'
#!/bin/bash
# walls.sh is named only in comments here
echo "a # inside quotes is no comment: lib/root.sh"   # a trailing comment names walls.sh
cat bash-walls.sh walls.sh.bak
PLANT_COMMENT
cat > "$F/tests/s-runner.test.sh" <<'PLANT_RUNNER'
#!/bin/bash
bash tests/run.sh --only x.test.sh
PLANT_RUNNER
cat > "$F/tests/s-bare.test.sh" <<'PLANT_BARE'
#!/bin/bash
. "$BIONIC_LIB/run.sh"
PLANT_BARE
cat > "$F/tools/check.sh" <<'PLANT_TOOL'
#!/bin/bash
anchor fn payload/scripts/lib/root.sh 'echo needle' root_fn
PLANT_TOOL
git -C "$F" init -q
git -C "$F" add -A
git -C "$F" -c user.email=t@t -c user.name=t commit -q -m fixture
C1="$(git -C "$F" rev-parse HEAD)"
# The tree moves on from the commit: s-grep stops naming walls.sh, an untracked suite names it, and an
# ignored one names it too.
printf '#!/bin/bash\ngrep -c needle-line "$1"\n' > "$F/tests/s-grep.test.sh"
printf '#!/bin/bash\ncat payload/scripts/lib/walls.sh\n' > "$F/tests/s-new.test.sh"
printf '#!/bin/bash\ncat payload/scripts/lib/walls.sh\n' > "$F/tests/s-ign.test.sh"
ok "the fixture is planted and committed at ${C1:-?}"

walls_row() {  # walls_row <index text> -> the suites on payload/scripts/lib/walls.sh's line
  printf '%s\n' "$1" | awk -F'\t' '$1 == "payload/scripts/lib/walls.sh" { print $2 }'
}

# ------------------------------------------------------------
section "INDEX: grep, anchor and a hook listing walls.sh each name a suite (AC-6.1)"
# ------------------------------------------------------------
AT_IDX="$(bash "$ANCHORS" reads_index "$F" --at "$C1" 2>&1)"; AT_RC=$?
expect_eq "INDEX: reads_index --at exits 0" "0" "$AT_RC"
expect_eq "INDEX: walls.sh is read by the suite that greps it, the one that anchors it and the one that runs a hook listing it" \
  "tests/s-anchor.test.sh,tests/s-grep.test.sh,tests/s-hook.test.sh" "$(walls_row "$AT_IDX")"
expect_eq "INDEX: the whole index at the commit, files sorted, each file's suites sorted and unique" \
  "$(printf '%s\n' \
    "hooks/g.sh${TAB}tests/s-hook.test.sh" \
    "hooks/h.sh${TAB}tests/s-hook.test.sh" \
    "payload/scripts/lib/root.sh${TAB}tests/s-comment.test.sh,tests/s-hook.test.sh,tools/check.sh" \
    "payload/scripts/lib/run.sh${TAB}tests/s-bare.test.sh" \
    "payload/scripts/lib/walls.sh${TAB}tests/s-anchor.test.sh,tests/s-grep.test.sh,tests/s-hook.test.sh" \
    "tests/run.sh${TAB}tests/s-bare.test.sh,tests/s-runner.test.sh" \
    "tests/s-anchor.test.sh${TAB}tests/s-anchor.test.sh" \
    "tests/s-bare.test.sh${TAB}tests/s-bare.test.sh" \
    "tests/s-comment.test.sh${TAB}tests/s-comment.test.sh" \
    "tests/s-grep.test.sh${TAB}tests/s-grep.test.sh" \
    "tests/s-hook.test.sh${TAB}tests/s-hook.test.sh" \
    "tests/s-runner.test.sh${TAB}tests/s-runner.test.sh")" "$AT_IDX"
# The paired positive for the comment arm: s-comment IS scanned (it reads root.sh through a quoted
# string holding a #), so its absence from walls.sh's row is the comment rule, not a skipped file.
expect_contains "INDEX: a # inside quotes starts no comment, so s-comment reads root.sh" \
  "tests/s-comment.test.sh" "$(printf '%s\n' "$AT_IDX" | awk -F'\t' '$1 == "payload/scripts/lib/root.sh" { print $2 }')"
expect_absent "INDEX: …and walls.sh named in a comment, whole-line or trailing, or inside a longer name, is no read" \
  "s-comment" "$(walls_row "$AT_IDX")"
expect_eq "INDEX: a qualified tests/run.sh names that file alone, a bare run.sh under a variable names both" \
  "tests/s-bare.test.sh" "$(printf '%s\n' "$AT_IDX" | awk -F'\t' '$1 == "payload/scripts/lib/run.sh" { print $2 }')"
expect_contains "INDEX: the anchor index is folded in — a declaring suite outside tests/ is named by its anchor alone" \
  "payload/scripts/lib/root.sh${TAB}tests/s-comment.test.sh,tests/s-hook.test.sh,tools/check.sh" "$AT_IDX"

# ------------------------------------------------------------
section "INDEX: without --at the tree as it stands; --at reads the commit"
# ------------------------------------------------------------
TR_IDX="$(bash "$ANCHORS" reads_index "$F" 2>&1)"; TR_RC=$?
expect_eq "INDEX: reads_index on the tree exits 0" "0" "$TR_RC"
expect_eq "INDEX: on the tree, s-grep no longer reads walls.sh, the untracked s-new does, the ignored s-ign does not" \
  "tests/s-anchor.test.sh,tests/s-hook.test.sh,tests/s-new.test.sh" "$(walls_row "$TR_IDX")"
expect_eq "INDEX: the sourced function and the command print the same index" "$TR_IDX" \
  "$(bash -c '. "$1"; reads_index "$2" -' _ "$ANCHORS" "$F" 2>&1)"
NG="$SB/nogit"; mkdir -p "$NG"; ( cd "$F" && tar cf - --exclude .git . ) | ( cd "$NG" && tar xf - )
expect_eq "INDEX: a root outside git reads every file under it, the ignore list unread" \
  "tests/s-anchor.test.sh,tests/s-hook.test.sh,tests/s-ign.test.sh,tests/s-new.test.sh" \
  "$(walls_row "$(bash "$ANCHORS" reads_index "$NG" 2>&1)")"
BAD_OUT="$(bash "$ANCHORS" reads_index "$F" --at 0000000000000000000000000000000000000000 2>&1)"; BAD_RC=$?
expect_eq "INDEX: --at a commit the root does not hold exits 2" "2" "$BAD_RC"
expect_contains "INDEX: …naming the commit" "no commit 0000000000000000000000000000000000000000" "$BAD_OUT"


# ------------------------------------------------------------
setup_section "plant the second fixture: a prelude, a tests/lib helper, a find and a glob (wave-37 T3; D4)"
# ------------------------------------------------------------
# A second tree, so §INDEX's whole-index pin stands untouched. Each file is placed for one arm of D4:
# s-pre sources x.prelude.sh (which runs hooks/hp.sh and sources y.prelude.sh) and lib/helper.sh (which
# greps tools/near.sh); y.prelude.sh greps tools/far.sh, a second hop. s-find walks $LIB with find and
# -name '*.sh'; s-glob loops over "$LIB"/*.sh; both set LIB once in their own text. s-plain names the same
# walk only in a comment.
G="$SB/pre"
mkdir -p "$G/payload/scripts/lib/sub" "$G/hooks" "$G/tests/lib" "$G/tools"
for x in pw a b; do printf 'echo %s\n' "$x" > "$G/payload/scripts/lib/$x.sh"; done
printf 'echo c\n' > "$G/payload/scripts/lib/sub/c.sh"
printf 'notes\n' > "$G/payload/scripts/lib/notes.txt"
printf 'echo near\n' > "$G/tools/near.sh"; printf 'echo far\n' > "$G/tools/far.sh"
cat > "$G/hooks/hp.sh" <<'PLANT_HP'
#!/bin/bash
BIONIC_LIB_WANT="pw.sh"
PLANT_HP
cat > "$G/tests/x.prelude.sh" <<'PLANT_XP'
# the shared prelude: runs the hook and sources the second prelude
HOOK="${ROOT}/hooks/hp.sh"
bash "$ROOT/hooks/hp.sh" tick
. "$(dirname "${BASH_SOURCE[0]}")/y.prelude.sh"
PLANT_XP
cat > "$G/tests/y.prelude.sh" <<'PLANT_YP'
grep -c far "$ROOT/tools/far.sh"
PLANT_YP
cat > "$G/tests/lib/helper.sh" <<'PLANT_HELPER'
grep -c near "$ROOT/tools/near.sh"
PLANT_HELPER
cat > "$G/tests/s-pre.test.sh" <<'PLANT_SPRE'
#!/bin/bash
. "$(dirname "$0")/lib/helper.sh"
. "$(dirname "$0")/x.prelude.sh"
PLANT_SPRE
cat > "$G/tests/s-find.test.sh" <<'PLANT_SFIND'
#!/bin/bash
LIB="${REPO}/payload/scripts/lib"
for f in $(find "$LIB" -name '*.sh' -type f); do bash -n "$f"; done
PLANT_SFIND
cat > "$G/tests/s-glob.test.sh" <<'PLANT_SGLOB'
#!/bin/bash
LIB="$REPO/payload/scripts/lib"
for f in "$LIB"/*.sh; do bash -n "$f"; done
PLANT_SGLOB
cat > "$G/tests/s-plain.test.sh" <<'PLANT_SPLAIN'
#!/bin/bash
LIB="$REPO/payload/scripts/lib"
# for f in $(find "$LIB" -name '*.sh'); do bash -n "$f"; done
echo plain
PLANT_SPLAIN
git -C "$G" init -q
git -C "$G" add -A
git -C "$G" -c user.email=t@t -c user.name=t commit -q -m fixture2
G1="$(git -C "$G" rev-parse HEAD)"
G_IDX="$(bash "$ANCHORS" reads_index "$G" --at "$G1" 2>&1)"; G_RC=$?
ok "the second fixture is planted at ${G1:-?} and indexed (rc ${G_RC})"

row_of() {  # row_of <file> <index text> -> the suites on <file>'s line
  printf '%s\n' "$2" | awk -F'\t' -v f="$1" '$1 == f { print $2 }'
}

# ------------------------------------------------------------
section "PRELUDE: a prelude or tests/lib helper a suite names is scanned as the suite's own text, one hop (wave-37 T3; D4, AC-3.1)"
# ------------------------------------------------------------
# fails-when: a suite that reaches a hook only through its prelude is not indexed to it (dispatch-preflight-3's
# miss at 1.19.0), or the hop follows a second prelude.
expect_eq "PRELUDE: reads_index over the second fixture exits 0" "0" "$G_RC"
expect_eq "PRELUDE: the suite names x.prelude.sh, so it reads it (the name scan, unchanged)" \
  "tests/s-pre.test.sh" "$(row_of tests/x.prelude.sh "$G_IDX")"
expect_eq "PRELUDE: x.prelude.sh runs hooks/hp.sh, so the suite sourcing it reads hp.sh" \
  "tests/s-pre.test.sh" "$(row_of hooks/hp.sh "$G_IDX")"
expect_eq "PRELUDE: …and the library hp.sh's BIONIC_LIB_WANT lists (the fan-out follows the hop), beside the walks" \
  "tests/s-find.test.sh,tests/s-glob.test.sh,tests/s-pre.test.sh" "$(row_of payload/scripts/lib/pw.sh "$G_IDX")"
expect_eq "PRELUDE: a tests/lib helper the suite sources is a hop too: helper.sh greps tools/near.sh" \
  "tests/s-pre.test.sh" "$(row_of tools/near.sh "$G_IDX")"
expect_eq "PRELUDE: one hop: the file x.prelude.sh names (y.prelude.sh) is read by the suite…" \
  "tests/s-pre.test.sh" "$(row_of tests/y.prelude.sh "$G_IDX")"
expect_eq "PRELUDE: …and what y.prelude.sh names (tools/far.sh) is not: no line for it" \
  "" "$(row_of tools/far.sh "$G_IDX")"
expect_absent "PRELUDE: a prelude is not a suite: no line names x.prelude.sh as a reader" \
  "tests/x.prelude.sh" "$(printf '%s\n' "$G_IDX" | cut -f2)"
expect_eq "PRELUDE: the hop reads the tree as it stands too (git grep --untracked)" \
  "tests/s-pre.test.sh" "$(row_of hooks/hp.sh "$(bash "$ANCHORS" reads_index "$G" 2>&1)")"
GNG="$SB/pre-nogit"; mkdir -p "$GNG"; ( cd "$G" && tar cf - --exclude .git . ) | ( cd "$GNG" && tar xf - )
expect_eq "PRELUDE: …and a root outside git (find over tests/ and tests/lib/)" \
  "tests/s-pre.test.sh" "$(row_of tools/near.sh "$(bash "$ANCHORS" reads_index "$GNG" 2>&1)")"

# ------------------------------------------------------------
section "DIR: find <dir> or <dir>/*glob reads every tracked file under the directory, the glob filtering (wave-37 T3; D4, AC-3.1)"
# ------------------------------------------------------------
# fails-when: shell-lint's `find "$LIB_DIR" -name '*.sh'` or a "$LIB"/*.sh loop reads none of the libraries
# (1.19.0: 0 of 44), or the glob lets a .txt in, or a commented walk reads.
expect_eq "DIR: find \"\$LIB\" -name '*.sh' and \"\$LIB\"/*.sh, \$LIB set once in the suite, read a.sh" \
  "tests/s-find.test.sh,tests/s-glob.test.sh" "$(row_of payload/scripts/lib/a.sh "$G_IDX")"
expect_eq "DIR: …and b.sh" "tests/s-find.test.sh,tests/s-glob.test.sh" "$(row_of payload/scripts/lib/b.sh "$G_IDX")"
expect_eq "DIR: …and sub/c.sh, every file under the directory" \
  "tests/s-find.test.sh,tests/s-glob.test.sh" "$(row_of payload/scripts/lib/sub/c.sh "$G_IDX")"
expect_eq "DIR: the glob filters by basename: notes.txt has no line" "" "$(row_of payload/scripts/lib/notes.txt "$G_IDX")"
expect_absent "DIR: the same walk in a comment reads nothing: s-plain is on a.sh's row nowhere" \
  "s-plain" "$(row_of payload/scripts/lib/a.sh "$G_IDX")"
expect_eq "DIR: …while s-plain is indexed (it reads itself)" "tests/s-plain.test.sh" "$(row_of tests/s-plain.test.sh "$G_IDX")"

# ------------------------------------------------------------
section "AGREE: the brief's reader, the wall's reader and reads_index agree over one fixture; a mutant dropping the hop is red (wave-37 T3; D4, AC-3.1)"
# ------------------------------------------------------------
# One `reads_suites <root> <at> <cell>` in lib/anchors.sh serves session-poker.sh `poker_brief_index_suites` and
# dispatch-preflight.sh `dp_lands_index_suites`, carrying the wall's <root>/ prefix strip. Each hook's function is
# lifted out of the shipped hook text and run beside the library, so the readers judged are the shipped ones.
# fails-when: either hook carries its own copy of the reading, the two disagree, or the hop can be dropped green.
SP_HOOK="$REPO/hooks/session-poker.sh"; DP_HOOK="$REPO/hooks/dispatch-preflight.sh"
fn_body() {  # fn_body <file> <function> -> the function's definition, through its first closing `}` line
  awk -v f="$2" 'index($0, f "() {") == 1 { on = 1 } on { print } on && /^}/ { exit }' "$1"
}
SP_FN="$(fn_body "$SP_HOOK" poker_brief_index_suites)"; DP_FN="$(fn_body "$DP_HOOK" dp_lands_index_suites)"
expect_contains "AGREE: the brief's reader is lifted out of session-poker.sh" "poker_brief_index_suites() {" "$SP_FN"
expect_contains "AGREE: the wall's reader is lifted out of dispatch-preflight.sh" "dp_lands_index_suites() {" "$DP_FN"
expect_contains "AGREE: the brief's reader calls reads_suites" "reads_suites " "$SP_FN"
expect_contains "AGREE: the wall's reader calls reads_suites" "reads_suites " "$DP_FN"
expect_absent "AGREE: …and neither reads the index itself (one reading, not two)" "reads_index \"" "$SP_FN$DP_FN"
AG_CELL="hooks/hp.sh, payload/scripts/lib/pw.sh"
agree_run() {  # agree_run <anchors.sh> <which: brief|wall|lib> <cell> -> that reader's answer over the second fixture
  bash -c '. "$1/payload/scripts/lib/units.sh"; . "$2"; eval "$3"; eval "$4"
    case "$5" in brief) poker_brief_index_suites "$6" "$7" "$8" ;; wall) dp_lands_index_suites "$6" "$7" "$8" ;;
      lib) reads_suites "$6" "$7" "$8" ;; esac' _ "$REPO" "$1" "$SP_FN" "$DP_FN" "$2" "$G" "$G1" "$3" 2>&1
}
AG_WANT="$(printf '%s\n' s-find.test.sh s-glob.test.sh s-pre.test.sh)"
AG_IDX_SET="$(printf '%s\n' "$G_IDX" | awk -F'\t' '$1 == "hooks/hp.sh" || $1 == "payload/scripts/lib/pw.sh" { n = split($2, s, ","); for (i = 1; i <= n; i++) { b = s[i]; sub(/.*\//, "", b); print b } }' | LC_ALL=C sort -u)"
expect_eq "AGREE: reads_index names s-find, s-glob and s-pre for hp.sh and pw.sh" "$AG_WANT" "$AG_IDX_SET"
expect_eq "AGREE: reads_suites answers that set, one per line" "$AG_WANT" "$(agree_run "$ANCHORS" lib "$AG_CELL")"
expect_eq "AGREE: the wall's reader answers the same" "$AG_WANT" "$(agree_run "$ANCHORS" wall "$AG_CELL")"
expect_eq "AGREE: the brief's reader answers the same, comma-joined" \
  "s-find.test.sh, s-glob.test.sh, s-pre.test.sh" "$(agree_run "$ANCHORS" brief "$AG_CELL")"
expect_eq "AGREE: a cell spelled from the root reads the same through the brief's reader (the strip is shared)" \
  "s-find.test.sh, s-glob.test.sh, s-pre.test.sh" "$(agree_run "$ANCHORS" brief "$G/hooks/hp.sh, $G/payload/scripts/lib/pw.sh")"
MUT="$SB/mut-anchors.sh"
sed '/_rd_grep "\$root" "\$at" H /d' "$ANCHORS" > "$MUT"
expect_eq "AGREE: the mutant drops the prelude hop's H stream (the mutation applied)" "1" \
  "$(cmp -s "$ANCHORS" "$MUT"; echo $?)"
expect_eq "AGREE: the mutant still runs: reads_suites names the walks for a.sh" \
  "$(printf '%s\n' s-find.test.sh s-glob.test.sh)" "$(agree_run "$MUT" lib payload/scripts/lib/a.sh)"
expect_eq "AGREE: …and loses s-pre for hooks/hp.sh, so the hop is what reads it" "" "$(agree_run "$MUT" lib hooks/hp.sh)"
expect_eq "AGREE: …where the shipped library names it" "s-pre.test.sh" "$(agree_run "$ANCHORS" lib hooks/hp.sh)"

finish
