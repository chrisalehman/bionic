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

finish
