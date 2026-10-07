#!/bin/bash
# SPAWN-WORKTREE — epic-17 wave-03 task S2 (spec AC-10, design ledger D4).
#
# WHAT THIS SUITE OWNS. One payload script:
#
#   payload/scripts/spawn-worktree.sh   the universal worktree contract
#
# WHY IT IS NOT IN tests/plugin-lib.test.sh (deleted at 8582861, epic-18 wave-03;
# the rationale below is historical). That suite's header named its
# subject: the two SOURCED libraries every command consumes, driven through a
# `lib_run` harness that sources a file and calls a function. This subject is an
# EXECUTED script whose whole behavior is mutation of a real git repository, and
# its fixture is a scratch repo rather than a fixture root plus a stubbed PATH.
# Sharing a file would mean two fixture regimes under one header, so a second
# file of its own — free to add since fixit 1.5.1 — is the cheaper half of that trade.
#
# WHAT THE CONTRACT IS. D4 (ratified 2026-08-17 with Chris's universality
# amendment): parallel writers work in worktrees a DISPATCHER created, creation
# authority following dispatch authority at every level. The mechanism is this
# script. What this suite asserts is the RESULT — the worktree, the branch, the
# base it sits at, the symlink, and the refusals — read back from git and the
# filesystem rather than from the line the script prints. (The byte-exact pins on
# that line retired at epic-18 W1 T14: no program parses it.)
#
# HERMETIC. No network, no `claude` CLI, no ~/.claude, and — the one that
# matters here — no contact with the bionic checkout this suite is running
# inside. Every git command is either `-C <fixture>` or inside a subshell that
# has already cd'd into one. Global and system git config are pointed at
# /dev/null so a machine-local `init.defaultBranch`, hook template or gpgsign
# setting cannot change what the fixtures look like.
#
# BOTH ARMS, ALWAYS. Every refusal is asserted against the matching acceptance:
# a script that refused everything would pass an all-negative suite.
#
# MUTATION AND RESTORE. Three of the assertions below are only worth their line
# count if they would go red when the behavior they name disappears. RED
# evidence dies at green and cannot be audited afterwards, so the proof is taken
# HERE: a copy of the script is doctored, the assertion is re-run against the
# doctored copy, and the suite records that the doctored build failed. The
# production file is never touched.
#
# Usage: bash tests/spawn-worktree.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"

REPO="${BIONIC_SCRIPTS_DIR}"
SPAWN="${REPO}/payload/scripts/spawn-worktree.sh"

# expect_true, expect_false, expect_match are the framework's (tests/lib/assert.sh)
# — S9b removed the private shadows here (AC-12); expect_match's glob semantics
# and argument order (`<label> <glob> <actual>`) were already identical, so
# every call site below binds unchanged.

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# Git isolation. GIT_CONFIG_GLOBAL/SYSTEM at /dev/null means no machine-local
# config reaches a fixture; the identity vars mean `commit` works even though
# there is no config to read one from.
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null
export GIT_CONFIG_NOSYSTEM=1
export GIT_TERMINAL_PROMPT=0
export GIT_AUTHOR_NAME="Bionic Test" GIT_AUTHOR_EMAIL="test@example.invalid"
export GIT_COMMITTER_NAME="Bionic Test" GIT_COMMITTER_EMAIL="test@example.invalid"
unset GIT_DIR GIT_WORK_TREE 2>/dev/null || true

# ---------------------------------------------------------------------------
# Fixture builders
# ---------------------------------------------------------------------------

# A scratch repository shaped like a bionic-governed checkout: two commits, a
# `.bionic/` state directory, and a .gitignore that keeps `.bionic/` and
# `.worktrees/` untracked — exactly the arrangement the contract assumes.
#
# `abs` is taken with `pwd -P`: on macOS $TMPDIR is reached through a symlink
# (/var -> /private/var), and the script resolves its own paths physically. A
# logical path here would fail a byte-exact comparison for a reason that has
# nothing to do with the behavior under test.
new_repo() {  # <dir> -> echoes the physical absolute path
  local d="$1"
  mkdir -p "$d"
  git -C "$d" init --quiet 2>/dev/null
  git -C "$d" symbolic-ref HEAD refs/heads/main
  mkdir -p "$d/.bionic/docs"
  echo "state" > "$d/.bionic/docs/note.md"
  printf '.bionic\n.bionic/\n.worktrees/\n' > "$d/.gitignore"
  echo "one" > "$d/file.txt"
  git -C "$d" add .gitignore file.txt
  git -C "$d" commit --quiet -m "c1"
  echo "two" >> "$d/file.txt"
  git -C "$d" commit --quiet -am "c2"
  ( cd "$d" && pwd -P )
}

sha_of() { git -C "$1" rev-parse "${2:-HEAD}"; }

# Run the script with a controlled cwd. Contract lines (OK / FAIL / REMOVED)
# are the script's product, so stdout is captured alone: a helper that merged
# stderr would let a diagnostic masquerade as an attestation.
spawn_out() {  # <cwd> <args...>
  local cwd="$1"; shift
  ( cd "$cwd" && bash "$SPAWN" "$@" 2>/dev/null )
}
spawn_rc() {  # <cwd> <args...>
  local cwd="$1"; shift
  ( cd "$cwd" && bash "$SPAWN" "$@" >/dev/null 2>&1 ); echo $?
}
# Same, against an arbitrary copy of the script (mutation arms).
spawn_out_with() {  # <script> <cwd> <args...>
  local script="$1" cwd="$2"; shift 2
  ( cd "$cwd" && bash "$script" "$@" 2>/dev/null )
}

section "Group 1: the script exists, is executable, and parses"

# (file-exists/executable fixture checks removed epic-18 W3 4/6: no production subject -- see ledger-spawn-worktree.md)
expect_true "spawn-worktree.sh passes bash -n"  bash -n "$SPAWN"

section "Group 2: create — the call succeeds"

R1="$(new_repo "$TMP/r1")"
SHA1="$(sha_of "$R1")"
spawn_out "$R1" create "$SHA1" feat-alpha >/dev/null

expect_eq "create exits 0" "0" "$(spawn_rc "$R1" create "$SHA1" feat-alpha-2)"

section "Group 3: create — what the line CLAIMS is what is on disk"
#
# An attestation is worth nothing if it is printed from the arguments rather
# than read back from the result. Each field is re-derived from the filesystem
# and from git, independently of the line.

expect_true "the worktree directory exists"            test -d "${R1}/.worktrees/feat-alpha"
expect_eq   "the worktree HEAD is the requested base"  "$SHA1" "$(sha_of "${R1}/.worktrees/feat-alpha")"
expect_eq   "the branch was created at the base"       "$SHA1" "$(git -C "$R1" rev-parse refs/heads/feat-alpha)"
expect_eq   "the worktree is ON that branch"           "feat-alpha" "$(git -C "${R1}/.worktrees/feat-alpha" rev-parse --abbrev-ref HEAD)"
# D7 (wave-13, reopens C2): the `.bionic` alias is PLANTED again. A writer in
# a spawned tree still reaches the state directory through project_root's
# git-common-dir mapping for every HOOK read — that is unchanged — but a
# plain relative shell write now also lands there, through the link.
expect_true "a .bionic symlink IS planted"              test -L "${R1}/.worktrees/feat-alpha/.bionic"
expect_eq   "…and it resolves to the main checkout's .bionic" \
  "${R1}/.bionic" "$(cd "${R1}/.worktrees/feat-alpha/.bionic" && pwd -P)"
expect_eq "create adds NOTHING to the worktree tree beyond the checkout and the alias" \
  "" "$(cd "${R1}/.worktrees/feat-alpha" && ls -A | grep -v -e '^\.git$' -e '^file.txt$' -e '^\.gitignore$' -e '^\.bionic$')"
expect_match "the attestation carries an alias= field naming the resolved target" \
  "*alias=${R1}/.bionic" "$(spawn_out "$R1" create "$SHA1" feat-alpha-3)"
# A relative write from INSIDE the worktree, exactly as a dispatched writer
# makes it, must land through the alias in the MAIN checkout — this is the
# whole point of D7 (AC-7.1).
( cd "${R1}/.worktrees/feat-alpha" && mkdir -p .bionic/docs/record/w7 && printf 'evidence\n' > .bionic/docs/record/w7/x.md )
expect_eq "a relative record write from the worktree lands in the main tree" \
  "evidence" "$(cat "${R1}/.bionic/docs/record/w7/x.md" 2>/dev/null)"

section "Group 4: create — base resolution and the older-commit arm"
#
# `base` is not decoration: a worktree at HEAD when an older SHA was asked for
# is the exact defect the pin+verify-HEAD interim discipline existed to catch.

R2="$(new_repo "$TMP/r2")"
OLD2="$(sha_of "$R2" 'HEAD~1')"
HEAD2="$(sha_of "$R2")"
spawn_out "$R2" create "$OLD2" older >/dev/null
expect_eq   "the worktree really is at the older sha" "$OLD2" "$(sha_of "${R2}/.worktrees/older")"
expect_true "the older sha is not HEAD (the arm discriminates)" test "$OLD2" != "$HEAD2"
# (fixture self-check removed epic-18 W3 4/6: not testing the script -- see ledger-spawn-worktree.md)
section "Group 5: create — where the worktree lands"
#
# `git worktree add` resolves a relative path against pwd, not the repo root
# (.claude/rules/git-worktree-docs.md records the nested-worktree accident that
# taught this repo the lesson). Two arms: the default parent, and a relative
# parent given from a cwd that is NOT the repo root.

R3="$(new_repo "$TMP/r3")"
SHA3="$(sha_of "$R3")"
# The repository is identified by cwd, so the caller stands inside it; what
# varies here is where the tree is asked to LAND. An absolute parent is taken
# as given, even outside the checkout.
EXT="$TMP/external-trees"; mkdir -p "$EXT"; EXT="$(cd "$EXT" && pwd -P)"
spawn_out "$R3" create "$SHA3" from-away "$EXT" >/dev/null
expect_true "an absolute parent outside the repo is honored — the worktree lands there" \
  test -d "${EXT}/from-away"
mkdir -p "$TMP/elsewhere"
expect_match "running from a cwd outside any repository is refused" "spawn-worktree: FAIL reason=*" \
  "$(spawn_out "$TMP/elsewhere" create "$SHA3" from-nowhere "$EXT")"

# The trap arm proper: cwd is a subdirectory of the repo, parent is relative.
mkdir -p "$R3/sub"
OUT3B="$(spawn_out "$R3/sub" create "$SHA3" rel-parent "custom-trees")"
expect_match "a relative parent resolves against the repo root, never pwd" \
  "*path=${R3}/custom-trees/rel-parent *" "$OUT3B"
expect_false "no worktree was created under the caller's cwd" test -d "$R3/sub/custom-trees"

# A branch name with slashes is the normal case in this repo (wave/17-03-...).
OUT3C="$(spawn_out "$R3" create "$SHA3" wave/17-99-demo)"
expect_match "a slashed branch name yields a flat directory named for its last component" \
  "*path=${R3}/.worktrees/17-99-demo branch=wave/17-99-demo *" "$OUT3C"
expect_true "the slashed branch exists" git -C "$R3" show-ref --verify --quiet refs/heads/wave/17-99-demo

section "Group 6: create — spawning from INSIDE a linked worktree"
#
# The nesting accident this repo actually suffered. A dispatcher running inside
# a worktree must produce a SIBLING under the main checkout, not a worktree
# inside a worktree. `main_root` is resolved via --git-common-dir regardless of
# cwd, so the sibling's alias points at the MAIN checkout's `.bionic`, same as
# if it had been spawned from the main checkout directly (D7).

R4="$(new_repo "$TMP/r4")"
SHA4="$(sha_of "$R4")"
spawn_out "$R4" create "$SHA4" first >/dev/null
OUT4="$(spawn_out "${R4}/.worktrees/first" create "$SHA4" second)"
expect_match "a worktree spawned from inside a worktree is a SIBLING" \
  "*path=${R4}/.worktrees/second *" "$OUT4"
expect_true "the sibling carries the alias too" \
  test -L "${R4}/.worktrees/second/.bionic"
expect_eq "…resolving to the MAIN checkout's .bionic, not the parent worktree's" \
  "${R4}/.bionic" "$(cd "${R4}/.worktrees/second/.bionic" && pwd -P)"
expect_false "no nested .worktrees directory was created" test -d "${R4}/.worktrees/first/.worktrees"

section "Group 7: create — refusals"
#
# Each refusal is paired with the acceptance it discriminates against, and each
# one is asserted to leave NOTHING behind: a refusal that half-creates is worse
# than no refusal at all.

R5="$(new_repo "$TMP/r5")"
SHA5="$(sha_of "$R5")"
BOGUS="0000000000000000000000000000000000000000"

expect_match "a base that is not a commit is refused" "spawn-worktree: FAIL reason=*" \
  "$(spawn_out "$R5" create "$BOGUS" nope)"
expect_false "the refused base left no worktree behind" test -e "${R5}/.worktrees/nope"
expect_false "the refused base left no branch behind" \
  git -C "$R5" show-ref --verify --quiet refs/heads/nope

spawn_out "$R5" create "$SHA5" taken >/dev/null
expect_match "an existing branch is refused" "spawn-worktree: FAIL reason=*" \
  "$(spawn_out "$R5" create "$SHA5" taken)"
expect_eq "the existing branch still points where it did" \
  "$SHA5" "$(git -C "$R5" rev-parse refs/heads/taken)"

mkdir -p "${R5}/.worktrees/occupied"
expect_match "an existing target path is refused" "spawn-worktree: FAIL reason=*" \
  "$(spawn_out "$R5" create "$SHA5" occupied)"
expect_false "the refused path did not become a branch" \
  git -C "$R5" show-ref --verify --quiet refs/heads/occupied
expect_eq "the occupied directory was not disturbed" "" "$(ls -A "${R5}/.worktrees/occupied")"

expect_match "a .. component in the parent is refused" "spawn-worktree: FAIL reason=*" \
  "$(spawn_out "$R5" create "$SHA5" escapee "../outside")"
expect_false "the traversal attempt created nothing outside the repo" test -d "$TMP/outside"
# ..and the near-miss: a directory whose NAME merely contains dots is fine.
expect_match "a parent whose name merely contains dots is accepted" "spawn-worktree: OK *" \
  "$(spawn_out "$R5" create "$SHA5" dotty "my..trees")"

expect_match "a missing branch argument is refused" "spawn-worktree: FAIL reason=*" \
  "$(spawn_out "$R5" create "$SHA5")"
expect_match "no arguments at all is refused" "spawn-worktree: FAIL reason=*" \
  "$(spawn_out "$R5")"
expect_match "an unknown verb is refused" "spawn-worktree: FAIL reason=*" \
  "$(spawn_out "$R5" summon "$SHA5" x)"
mkdir -p "$TMP/not-a-repo"
expect_match "running outside a git repository is refused" "spawn-worktree: FAIL reason=*" \
  "$(spawn_out "$TMP/not-a-repo" create "$SHA5" orphan)"

# The .bionic precondition. A repo with no state directory cannot be given a
# symlink to one, and planting a dangling link would produce an attestation
# whose last field names a path that is not there.
NB="$TMP/nobionic"; mkdir -p "$NB"; git -C "$NB" init --quiet
echo x > "$NB/f"; git -C "$NB" add f; git -C "$NB" commit --quiet -m c1
NBSHA="$(sha_of "$NB")"
expect_match "a repo with no .bionic directory is refused" "spawn-worktree: FAIL reason=*" \
  "$(spawn_out "$NB" create "$NBSHA" nostate)"
mkdir -p "$NB/.bionic"
expect_match "the same repo is accepted once .bionic exists (the arm discriminates)" \
  "spawn-worktree: OK *" "$(spawn_out "$NB" create "$NBSHA" nostate)"

section "§DISK: create refuses when free disk is under the largest tree (wave-28 T9; D15, REQ-2)"
#
# The dispatch wall's worktrees ceiling went with the probe's budget line (D15). What it stood
# for is asked where a tree is made: `create` refuses when the project's volume has less free
# space than the largest tree already there, naming both figures in KB. The figures are planted
# (BIONIC_PROBE_DISK_FREE_KB, BIONIC_PROBE_TREE_KB); a disk is never filled. DISK.4 plants only
# the free figure and lets the script measure the real tree, so the measuring path is driven.
# fails-when: a create under the largest tree's size is admitted, or one at or over it refused,
# or the refusal names a figure it was not given.
RD="$(new_repo "$TMP/rd")"
SHAD="$(sha_of "$RD")"
OUTD1="$( cd "$RD" && BIONIC_PROBE_DISK_FREE_KB=5 BIONIC_PROBE_TREE_KB=9 bash "$SPAWN" create "$SHAD" d-low 2>/dev/null )"
expect_eq "DISK.1 free 5 KB under a largest tree of 9 KB is refused, naming both figures" \
  "spawn-worktree: FAIL reason=disk-low free_kb=5 largest_tree_kb=9" "$OUTD1"
expect_false "DISK.1b …leaving no worktree behind" test -e "${RD}/.worktrees/d-low"
expect_false "DISK.1c …and no branch" git -C "$RD" show-ref --verify --quiet refs/heads/d-low
expect_eq "DISK.1d …exiting 2, a refusal" "2" \
  "$( cd "$RD" && BIONIC_PROBE_DISK_FREE_KB=5 BIONIC_PROBE_TREE_KB=9 bash "$SPAWN" create "$SHAD" d-low-rc >/dev/null 2>&1; echo $? )"
OUTD2="$( cd "$RD" && BIONIC_PROBE_DISK_FREE_KB=9 BIONIC_PROBE_TREE_KB=9 bash "$SPAWN" create "$SHAD" d-even 2>/dev/null )"
expect_match "DISK.2 free equal to the largest tree is admitted" "spawn-worktree: OK path=${RD}/.worktrees/d-even *" "$OUTD2"
OUTD3="$( cd "$RD" && BIONIC_PROBE_DISK_FREE_KB=1 BIONIC_PROBE_TREE_KB=0 bash "$SPAWN" create "$SHAD" d-none 2>/dev/null )"
expect_match "DISK.3 with no tree's size to meet, a small free figure is admitted" "spawn-worktree: OK path=${RD}/.worktrees/d-none *" "$OUTD3"
DSZ="$(du -sk "${RD}/.worktrees/d-even" | awk '{ print $1 }')"
expect_true "DISK.4 meta: a real tree stands and du reads it above 1 KB (${DSZ})" test "${DSZ:-0}" -gt 1
OUTD4="$( cd "$RD" && BIONIC_PROBE_DISK_FREE_KB=1 bash "$SPAWN" create "$SHAD" d-meas 2>/dev/null )"
expect_match "DISK.4 free 1 KB against the measured trees is refused, naming the largest it measured" \
  "spawn-worktree: FAIL reason=disk-low free_kb=1 largest_tree_kb=[0-9]*" "$OUTD4"
expect_false "DISK.4b …and nothing was made" test -e "${RD}/.worktrees/d-meas"
OUTD5="$( cd "$RD" && bash "$SPAWN" create "$SHAD" d-real 2>/dev/null )"
expect_match "DISK.5 control: the real disk has room for a tree this small" "spawn-worktree: OK path=${RD}/.worktrees/d-real *" "$OUTD5"

section "Group 8: create — a tracked .bionic in the branch is left alone, no alias planted"
#
# Until C2 this fixture was the self-verification failure: `git worktree add`
# checks the tracked `.bionic` out, the plant target is occupied, and the
# contract verified-undid-refused. D7 (wave-13) restores the plant, but the
# same precedent still governs: a branch that already tracks something at
# `.bionic` owns that path, so `create` leaves it exactly alone rather than
# clobbering it with the alias — the OK line carries no `alias=` field for
# this tree. The cleanup-on-failure behaviour that fixture used to drive is
# proven by Group 10's mutation 3 instead.

R6="$TMP/r6"; mkdir -p "$R6/.bionic"
git -C "$R6" init --quiet
git -C "$R6" symbolic-ref HEAD refs/heads/main
echo "tracked state" > "$R6/.bionic/tracked.md"   # tracked on purpose: no .gitignore
echo x > "$R6/f"
git -C "$R6" add .bionic/tracked.md f
git -C "$R6" commit --quiet -m "c1 with a tracked .bionic"
R6="$(cd "$R6" && pwd -P)"
SHA6="$(sha_of "$R6")"
OUT6="$(spawn_out "$R6" create "$SHA6" tracked-state)"

expect_match "a branch carrying a tracked .bionic is attested" "spawn-worktree: OK *" "$OUT6"
expect_true  "the worktree exists"       test -d "${R6}/.worktrees/tracked-state"
expect_true  "its .bionic is the branch's own DIRECTORY, not a link" \
  test -d "${R6}/.worktrees/tracked-state/.bionic"
expect_false "and it is not a symlink"   test -L "${R6}/.worktrees/tracked-state/.bionic"
expect_eq    "the branch's own state file is what is there" "tracked state" \
  "$(cat "${R6}/.worktrees/tracked-state/.bionic/tracked.md")"
expect_eq    "the attestation carries no alias= field for this tree" "0" \
  "$(printf '%s\n' "$OUT6" | grep -c 'alias=')"

# The near-miss: a branch tracking `.bionic` as a SYMLINK (pointing anywhere,
# even elsewhere) is the same case as a tracked directory — the branch's own
# content, left exactly alone. `create` never overwrites a pre-existing
# `.bionic` of any shape.
R6B="$TMP/r6b"; mkdir -p "$R6B"
git -C "$R6B" init --quiet
git -C "$R6B" symbolic-ref HEAD refs/heads/main
mkdir -p "$TMP/elsewhere-target"; echo elsewhere > "$TMP/elsewhere-target/note.md"
ln -s "$TMP/elsewhere-target" "$R6B/.bionic"
echo x > "$R6B/f"
git -C "$R6B" add .bionic f
git -C "$R6B" commit --quiet -m "c1, .bionic TRACKED as a symlink"
R6B="$(cd "$R6B" && pwd -P)"
SHA6B="$(sha_of "$R6B")"
OUT6B="$(spawn_out "$R6B" create "$SHA6B" mispointed)"
expect_match "create still succeeds" "spawn-worktree: OK *" "$OUT6B"
expect_true "a pre-existing symlink at .bionic is left exactly alone" \
  test -L "${R6B}/.worktrees/mispointed/.bionic"
expect_eq "…still resolving where it always did, not to the main checkout" \
  "$(cd "$TMP/elsewhere-target" && pwd -P)" \
  "$(cd "${R6B}/.worktrees/mispointed/.bionic" && pwd -P)"
expect_eq "the attestation carries no alias= field here either" "0" \
  "$(printf '%s\n' "$OUT6B" | grep -c 'alias=')"

section "Group 9: remove — the companion verb"
#
# Teardown is never automatic and never deletes the branch: the merge decision
# belongs to the orchestrator (D4), so `remove` gives back a tree and keeps the
# work reachable.

R7="$(new_repo "$TMP/r7")"
SHA7="$(sha_of "$R7")"
spawn_out "$R7" create "$SHA7" temp-work >/dev/null
# D7: create planted a real alias — prove it is there before remove takes it,
# so the assertions below show something real was torn down.
expect_true "the alias exists before remove" test -L "${R7}/.worktrees/temp-work/.bionic"
OUT7="$(spawn_out "$R7" remove "${R7}/.worktrees/temp-work")"

expect_match "remove reports success" "spawn-worktree: REMOVED *" "$OUT7"
expect_false "the worktree directory is gone" test -d "${R7}/.worktrees/temp-work"
expect_true  "the BRANCH survives removal" git -C "$R7" show-ref --verify --quiet refs/heads/temp-work
expect_eq    "the branch still points at the base it was created from" \
  "$SHA7" "$(git -C "$R7" rev-parse refs/heads/temp-work)"
expect_eq    "git's worktree registry no longer lists it" "1" \
  "$(git -C "$R7" worktree list | grep -c .)"
expect_true  "the repo root's .bionic survived" test -f "${R7}/.bionic/docs/note.md"

# C2's teardown clause: `remove` deletes a LEGACY link — one an older bionic
# planted — rather than leaving git to refuse the removal over it. The link is
# removed by the verb, and what it pointed at is untouched.
spawn_out "$R7" create "$SHA7" legacy-work >/dev/null
ln -s "${R7}/.bionic" "${R7}/.worktrees/legacy-work/.bionic"
OUT7L="$(spawn_out "$R7" remove "${R7}/.worktrees/legacy-work")"
expect_match "remove succeeds over a legacy link" "spawn-worktree: REMOVED *" "$OUT7L"
expect_false "the tree carrying a legacy link is gone" test -d "${R7}/.worktrees/legacy-work"
expect_true  "the state directory the legacy link pointed at is intact" \
  test -f "${R7}/.bionic/docs/note.md"

# Removal is a git operation with git's own safety: uncommitted work refuses.
spawn_out "$R7" create "$SHA7" dirty-work >/dev/null
echo "unsaved" >> "${R7}/.worktrees/dirty-work/file.txt"
expect_match "a worktree with uncommitted changes is refused" "spawn-worktree: FAIL reason=*" \
  "$(spawn_out "$R7" remove "${R7}/.worktrees/dirty-work")"
expect_true "the refused worktree is still there" test -d "${R7}/.worktrees/dirty-work"


expect_match "removing a path that is not a worktree is refused" "spawn-worktree: FAIL reason=*" \
  "$(spawn_out "$R7" remove "${R7}/.worktrees/never-existed")"
expect_match "removing the MAIN checkout is refused" "spawn-worktree: FAIL reason=*" \
  "$(spawn_out "$R7" remove "$R7")"
expect_match "remove with no path is refused" "spawn-worktree: FAIL reason=*" \
  "$(spawn_out "$R7" remove)"

section "Group 10: mutation and restore — do the pins above actually catch?"
#
# RED evidence is perishable: once the script is written the assertions are
# green forever and nothing records that they discriminate. Each arm below
# doctors a COPY, runs the same assertion against it, and requires the doctored
# build to fail. The production file is never modified.

# mutate_check doctors a copy, runs the named verifier against it, and requires
# the verdict to be the UNHEALTHY one. A sed expression that matched nothing is
# itself a failure — a vacuous mutation is how a mutation suite goes green
# while proving nothing.
mutate_check() {  # <label> <sed-expr> <verifier-fn> <expected-mutant-verdict>
  local label="$1" expr="$2" fn="$3" want="$4"
  local copy="$TMP/mutant.sh"
  cp "$SPAWN" "$copy"
  # THE LIBRARY SHIPS BESIDE THE SCRIPT, so the copy gets it too (epic-22 wave-01, N1).
  # spawn-worktree.sh resolves the main checkout through lib/roots.sh's `worktree_root`
  # now — one resolver for a question three files used to answer separately — and it
  # refuses at the top when it cannot load it. A mutant alone in a temp directory would
  # take that refusal on every verb, and all three arms below would go green against a
  # failure the mutation did not cause.
  mkdir -p "$TMP/lib"
  cp "$(dirname "$SPAWN")/lib"/*.sh "$TMP/lib/" 2>/dev/null
  sed -i.bak "$expr" "$copy" && rm -f "${copy}.bak"
  if cmp -s "$SPAWN" "$copy"; then
    no "$label" "the sed expression changed nothing — the mutation is vacuous"
  else
    expect_eq "$label" "$want" "$("$fn" "$copy")"
  fi
  rm -f "$copy"
}

# Mutation 1 — the HEAD self-verification. Proving this one needs a world in
# which the worktree's HEAD is NOT the requested base, and git will not produce
# that on its own. So the arm injects a git that does not honor the pin: a
# passthrough wrapper that rewrites `worktree add`'s final argument to HEAD.
# That is fault injection on the environment, not a seam standing in for the
# value under test — the script still runs a real `git`, and still reads a real
# worktree back. A build that verifies refuses; a build that prints the base it
# was handed attests a head it never looked at.
FAKEBIN="$TMP/fakebin"; mkdir -p "$FAKEBIN"
REAL_GIT="$(command -v git)"
cat > "$FAKEBIN/git" <<FAKE
#!/bin/bash
# A git that ignores the requested base for \`worktree add\`.
args=("\$@")
for ((i=0; i<\${#args[@]}; i++)); do
  if [ "\${args[i]}" = "worktree" ] && [ "\${args[i+1]:-}" = "add" ]; then
    args[\${#args[@]}-1]="HEAD"
    break
  fi
done
exec "${REAL_GIT}" "\${args[@]}"
FAKE
chmod +x "$FAKEBIN/git"

verify_head_check() {  # <script> -> refused | attested-blindly
  local script="$1"
  local rr; rr="$(new_repo "$TMP/mut1-$RANDOM")"
  local old; old="$(git -C "$rr" rev-parse HEAD~1)"
  local out
  out="$( cd "$rr" && PATH="${FAKEBIN}:$PATH" bash "$script" create "$old" m1 2>/dev/null )"
  case "$out" in
    "spawn-worktree: FAIL"*) echo "refused" ;;
    *)                       echo "attested-blindly" ;;
  esac
}

# Mutation 2 — the legacy-link deletion in `remove`. C2 retired the plant, so
# what is left to prove is the teardown half: a tree an OLDER bionic left a link
# in must still come away cleanly, and the link must not survive the verb.
# The link must be UNTRACKED for this arm to discriminate: git's own removal
# refuses over an untracked file, which is why the verb takes the link away
# first. A fixture that gitignores `.bionic` would let `git worktree remove`
# delete the whole tree regardless, and the mutation would prove nothing.
verify_legacy_removal() {  # <script> -> deleted | survived
  local script="$1"
  local rr; rr="$(new_repo "$TMP/mut2-$RANDOM")"
  printf '.worktrees/\n' > "$rr/.gitignore"
  git -C "$rr" commit --quiet -am "no .bionic ignore"
  local sha; sha="$(git -C "$rr" rev-parse HEAD)"
  spawn_out_with "$script" "$rr" create "$sha" m2 >/dev/null
  # An older bionic wrote no `/.bionic` exclude line (wave-27 T79 does), and that line would
  # ignore the link: take it out again, so the link stays untracked as the arm needs.
  grep -vxF -- "/.bionic" "$rr/.git/info/exclude" > "$rr/.git/info/exclude.t79"
  mv "$rr/.git/info/exclude.t79" "$rr/.git/info/exclude"
  ln -s "$rr/.bionic" "$rr/.worktrees/m2/.bionic"
  spawn_out_with "$script" "$rr" remove "$rr/.worktrees/m2" >/dev/null
  if [ -d "$rr/.worktrees/m2" ] || [ -L "$rr/.worktrees/m2/.bionic" ]; then
    echo "survived"
  else
    echo "deleted"
  fi
}

# Mutation 3 — the cleanup on failed verification. Its old driver (a tracked
# `.bionic` occupying the plant target) died with the plant, so the failure is
# induced the way mutation 1 induces one: the fake git that ignores the
# requested base, which fails the HEAD readback and takes the abort path. With
# cleanup gone, an unattested worktree and its branch survive the refusal.
verify_cleanup() {  # <script> -> cleaned | residue
  local script="$1"
  local rr; rr="$(new_repo "$TMP/mut3-$RANDOM")"
  echo "three" >> "$rr/file.txt"; git -C "$rr" commit --quiet -am c2
  local old; old="$(git -C "$rr" rev-parse HEAD~1)"
  ( cd "$rr" && PATH="${FAKEBIN}:$PATH" bash "$script" create "$old" m3 >/dev/null 2>&1 )
  if [ -d "$rr/.worktrees/m3" ] || git -C "$rr" show-ref --verify --quiet refs/heads/m3; then
    echo "residue"
  else
    echo "cleaned"
  fi
}

# Sanity first: against the REAL script every verifier reports the healthy
# verdict. Without this the mutation arms could be passing for the wrong reason.
expect_eq "live build: an unhonored base is refused"    "refused" "$(verify_head_check "$SPAWN")"
expect_eq "live build: a legacy link is deleted by remove" "deleted" "$(verify_legacy_removal "$SPAWN")"
expect_eq "live build: a failed verification cleans up" "cleaned" "$(verify_cleanup "$SPAWN")"

mutate_check "mutation: head taken from the argument instead of the tree is caught" \
  's|head="$(git -C "$wt" rev-parse HEAD 2>/dev/null)"|head="$base_sha"|' \
  verify_head_check "attested-blindly"
mutate_check "mutation: the legacy-link deletion removed is caught" \
  's|^    rm -f "${wt_abs}/.bionic"$|    :|' \
  verify_legacy_removal "survived"
mutate_check "mutation: the cleanup on failed verification removed is caught" \
  's|^  cleanup_partial$|  :|' \
  verify_cleanup "residue"

# The old "Group 12: the shipped skill is the payload's own copy" banner (git
# HEAD:490-492) named no subject and carried zero assertions — the
# pre-framework harness never noticed. The framework's section floor DOES
# (captured to record/wave-verification-cannot-lie/s9-planted.log); S9 is a
# mechanical migration and does not author new assertions, so the dead banner
# is dropped rather than given content (S9 W+1 candidate 1).

section "Group 11: the tree<->branch contract close-out relies on (epic-23 wave-17 T5, D5, ADR-032, A6)"
#
# close-out.sh's wt_branches() (REQ-6) trusts this contract instead of re-deriving
# it: a registered `## Tasks` row names a tree's BASENAME, and the branch it maps to
# is `wt/<basename>` — exactly the OK line's own `path=`/`branch=` relationship. This
# pins the two fields against EACH OTHER, not against a literal branch name, so it
# catches either side drifting from the other rather than one specific value.

# verify_wt_contract <script> -> held | broken — held iff the OK line's path=
# basename equals branch='s last path segment.
verify_wt_contract() {
  local script="$1"
  local rr; rr="$(new_repo "$TMP/contract-$RANDOM")"
  local sha; sha="$(sha_of "$rr")"
  local out p b
  out="$(cd "$rr" && bash "$script" create "$sha" wt/17-contract 2>/dev/null)"
  p="$(printf '%s\n' "$out" | tr ' ' '\n' | sed -n 's/^path=//p')"
  b="$(printf '%s\n' "$out" | tr ' ' '\n' | sed -n 's/^branch=//p')"
  if [ -n "$p" ] && [ -n "$b" ] && [ "${p##*/}" = "${b##*/}" ]; then
    echo held
  else
    echo broken
  fi
}

expect_eq "live build: the OK line's path= basename equals branch='s last segment" \
  "held" "$(verify_wt_contract "$SPAWN")"

mutate_check "mutation: a path built from something other than the branch's last segment is caught" \
  's|^  wt="${parent_abs}/${branch##\*/}"$|  wt="${parent_abs}/renamed-tree"|' \
  verify_wt_contract "broken"


section "Group 12: land — the verb lands onto the bound plan's working branch, in the checkout that holds it (wave-20 T8, REQ-1, D1)"
#
# END TO END THROUGH THIS SCRIPT'S OWN VERBS. `create` makes the wave checkout and the task
# tree exactly as a wave does; the main checkout then moves to a FEATURE branch a human is
# working on, which is the topology the reported defect came from (report #9). `land` reads
# its target off the session's bound plan — the verb takes no target of its own — so the
# merge goes into the wave checkout and the feature branch does not move. The library's own
# arms are tests/worktree.test.sh Groups 9-10; this pins the verb's wiring and its session.

LR="$(new_repo "$TMP/land-topology")"
LSID="spawn-land-session-01"
LBASE="$(sha_of "$LR")"
LWAVE_OUT="$(spawn_out "$LR" create "$LBASE" wave/20-demo)"
LWAVE="$(printf '%s\n' "$LWAVE_OUT" | tr ' ' '\n' | sed -n 's/^path=//p')"
LTREE_OUT="$(spawn_out "$LR" create "$LBASE" wt/20-T1)"
LTREE="$(printf '%s\n' "$LTREE_OUT" | tr ' ' '\n' | sed -n 's/^path=//p')"
echo work > "$LTREE/t1.txt"
git -C "$LTREE" add t1.txt
git -C "$LTREE" commit --quiet -m "T1 work"
git -C "$LR" checkout --quiet -b feature/human
LFEAT0="$(sha_of "$LR" feature/human)"
mkdir -p "$LR/.bionic/docs/plans/epic-x" "$LR/.bionic/tmp"
LPLAN="$LR/.bionic/docs/plans/epic-x/wave-x.plan.md"
printf -- '---\nworking-branch: wave/20-demo\n---\n# plan\n\n## SDLC State\n\ncurrent: 4\n' > "$LPLAN"
printf 'plan=%s\nengaged_at=2026-09-23T00:00:00Z\n' "$LPLAN" > "$LR/.bionic/tmp/engaged-${LSID}.state"

# A BARE `land` (wave-28 T3, D9): the line lands a row with `ready`, and a person lands one with
# `--by-hand --reason`; the bare verb names both, exits non-zero and moves nothing.
LREFSB="$(git -C "$LR" for-each-ref --format='%(refname) %(objectname)')"
LBARE="$( cd "$LR" && CLAUDE_CODE_SESSION_ID="$LSID" bash "$SPAWN" land "$LTREE" 2>&1 )"; LBARE_RC=$?
expect_eq "a bare land prints the line naming ready and --by-hand, exactly" \
  "land: the line lands a row with \"ready\"; a person lands one with \"land <tree> --by-hand --reason '<why>'\"" "$LBARE"
expect_ne "…and exits non-zero" "0" "$LBARE_RC"
expect_eq "…and no ref moved" "$LREFSB" "$(git -C "$LR" for-each-ref --format='%(refname) %(objectname)')"

# Refused first: no session id means no binding, so no target — and nothing moves.
LREFS0="$(git -C "$LR" for-each-ref --format='%(refname) %(objectname)')"
LNOSID="$( cd "$LR" && env -u CLAUDE_CODE_SESSION_ID bash "$SPAWN" land "$LTREE" --by-hand --reason r 2>/dev/null )"; LNOSID_RC=$?
expect_match "land with no session id is refused, naming why" \
  "spawn-worktree: REFUSED reason=no-session*" "$LNOSID"
expect_eq "that refusal exits 2" "2" "$LNOSID_RC"
expect_eq "no ref moved" "$LREFS0" "$(git -C "$LR" for-each-ref --format='%(refname) %(objectname)')"
expect_true "the tree survives" test -d "$LTREE"

LOUT="$( cd "$LR" && CLAUDE_CODE_SESSION_ID="$LSID" bash "$SPAWN" land "$LTREE" --by-hand --reason r 2>/dev/null )"; LRC=$?
expect_match "land from the bound session names the working branch and its checkout" \
  "spawn-worktree: LANDED branch=wt/20-T1 onto=wave/20-demo checkout=${LWAVE} merge=* removed=${LTREE} proofs=${LR}/.bionic/docs/record/wave-x/landing-proofs.log" "$LOUT"
expect_eq   "it exits 0" "0" "$LRC"
expect_eq   "the feature branch did not move" "$LFEAT0" "$(sha_of "$LR" feature/human)"
expect_eq   "the main checkout is still on the feature branch" "feature/human" \
  "$(git -C "$LR" rev-parse --abbrev-ref HEAD)"
expect_eq   "wt/20-T1's work is in the wave branch" "0" "$(git -C "$LR" rev-list --count wave/20-demo..wt/20-T1)"
expect_true "and in the wave checkout's working tree" test -f "$LWAVE/t1.txt"
expect_false "the task tree is gone" test -d "$LTREE"

# D1 THROUGH THE VERB (wave-20 T8c; review R2-1, R2-8; critic C2-1). `land` refuses while a
# `tests/run.sh` process has its script path or its working directory in the project root
# or in the checkout the land merges into. The session plays no part: in-process teammates
# and Agent-tool subagents share their orchestrator's session and have no session file of
# their own, so T8b's "the lander's own session never counts" switched D1 off for the
# orchestrator's own floor. The fixture below is that fleet shape: ONE session file, the
# lander's, busy at the root, and a stand-in runner (a script that only sleeps, never the
# real runner) working in the wave checkout. `BIONIC_CLAUDE_HOME` is the override
# `payload/scripts/lib/patrol.sh` and `tests/worktree.test.sh` already use for a fixture
# claude-home; this suite otherwise has none, per its header ("no contact with
# ~/.claude"), so it is scoped to these arms and unset right after.
LD1="$TMP/land-d1"
mkdir -p "$LD1/sessions"
LD1_PID=""
ld1_start() {  # <cwd> <script as invoked> -> LD1_PID, once the command line is visible
  ( cd "$1" && exec bash "$2" ) >/dev/null 2>&1 &
  LD1_PID=$!
  local i=0
  while [ $i -lt 100 ]; do
    case "$(ps -o command= -p "$LD1_PID" 2>/dev/null)" in *tests/run.sh*) return 0 ;; esac
    i=$((i+1)); sleep 0.05
  done
  return 1
}
ld1_stop() {
  [ -n "$LD1_PID" ] || return 0
  kill "$LD1_PID" 2>/dev/null; wait "$LD1_PID" 2>/dev/null
  LD1_PID=""
}
ld1_runner() {  # <dir> -> <dir>/tests/run.sh
  mkdir -p "$1/tests"
  printf '#!/bin/bash\nwhile :; do sleep 1; done\n' > "$1/tests/run.sh"
  chmod +x "$1/tests/run.sh"
}
# Folded into the ONE exit trap (never a second `trap ... EXIT`, which would replace
# rather than add to the first and leak $TMP on an early exit).
trap 'ld1_stop; rm -rf "$TMP"' EXIT
LD1ELSE="$TMP/land-d1-else"; ld1_runner "$LD1ELSE"
LD1OTHER="$(new_repo "$TMP/land-d1-other-repo")"; ld1_runner "$LD1OTHER"
ld1_runner "$LWAVE"

LTREE2_OUT="$(spawn_out "$LR" create "$(sha_of "$LR" wave/20-demo)" wt/20-T2)"
LTREE2="$(printf '%s\n' "$LTREE2_OUT" | tr ' ' '\n' | sed -n 's/^path=//p')"
echo work2 > "$LTREE2/t2.txt"
git -C "$LTREE2" add t2.txt
git -C "$LTREE2" commit --quiet -m "T2 work"
printf '{"pid":%s,"sessionId":"%s","cwd":"%s","status":"busy","name":"self"}\n' \
  "$$" "$LSID" "$LR" > "$LD1/sessions/$$.json"
export BIONIC_CLAUDE_HOME="$LD1"
expect_true "a stand-in runner started (the floor: absolute script in the wave checkout)" \
  ld1_start "$LWAVE" "$LWAVE/tests/run.sh"
LREFS2="$(git -C "$LR" for-each-ref --format='%(refname) %(objectname)')"
LOUT2="$( cd "$LR" && CLAUDE_CODE_SESSION_ID="$LSID" bash "$SPAWN" land "$LTREE2" --by-hand --reason r 2>/dev/null )"; LRC2=$?
expect_match "(T8c: was \"the verb's own busy suite does not refuse its own land\") the verb's own session's floor in the wave checkout holds its own landing (wave-28 T3: HELD)" \
  "*HELD wt/20-T2 — pid=*script=${LWAVE}/tests/run.sh*" "$LOUT2"
expect_eq   "that refusal exits 2" "2" "$LRC2"
expect_eq   "no ref moved" "$LREFS2" "$(git -C "$LR" for-each-ref --format='%(refname) %(objectname)')"
expect_true "the tree survives" test -d "$LTREE2"
ld1_stop
LOUT2B="$( cd "$LR" && CLAUDE_CODE_SESSION_ID="$LSID" bash "$SPAWN" land "$LTREE2" --by-hand --reason r 2>/dev/null )"; LRC2B=$?
expect_match "the same land goes through once the floor has finished (the arm discriminates)" \
  "spawn-worktree: LANDED branch=wt/20-T2 onto=wave/20-demo *" "$LOUT2B"
expect_eq   "it exits 0" "0" "$LRC2B"

# A suite in the main checkout, which is not where the working branch is checked out, holds
# nothing (wave-28 T3, D6: the publish is held by a run in the checkout that holds the branch,
# and the main checkout here holds the human's feature branch). Until 1.12.0 a runner anywhere
# under the root refused the land.
LTREE3_OUT="$(spawn_out "$LR" create "$(sha_of "$LR" wave/20-demo)" wt/20-T3)"
LTREE3="$(printf '%s\n' "$LTREE3_OUT" | tr ' ' '\n' | sed -n 's/^path=//p')"
echo work3 > "$LTREE3/t3.txt"
git -C "$LTREE3" add t3.txt
git -C "$LTREE3" commit --quiet -m "T3 work"
printf '{"pid":%s,"sessionId":"%s","cwd":"%s","status":"busy","name":"peer"}\n' \
  "$$" "verb-peer-session" "$LR" > "$LD1/sessions/$$.json"
LRREAL="$(cd "$LR" && pwd -P)"
expect_true "a stand-in runner started (cwd the main checkout)" ld1_start "$LR" "$LD1ELSE/tests/run.sh"
LOUT3="$( cd "$LR" && CLAUDE_CODE_SESSION_ID="$LSID" bash "$SPAWN" land "$LTREE3" --by-hand --reason r 2>/dev/null )"; LRC3=$?
expect_match "(wave-28 T3: was \"a suite in this root refuses, from any session\") a suite in the main checkout, where the branch is not, holds nothing: it lands" \
  "spawn-worktree: LANDED branch=wt/20-T3 onto=wave/20-demo *" "$LOUT3"
expect_eq   "it exits 0" "0" "$LRC3"
ld1_stop
LTREE3_OUT="$(spawn_out "$LR" create "$(sha_of "$LR" wave/20-demo)" wt/20-T4)"
LTREE3="$(printf '%s\n' "$LTREE3_OUT" | tr ' ' '\n' | sed -n 's/^path=//p')"
echo work4 > "$LTREE3/t4.txt"
git -C "$LTREE3" add t4.txt
git -C "$LTREE3" commit --quiet -m "T4 work"

# T12 F3: the only runner is in ANOTHER repository, the lander's own session busy at the
# root. The pre-T8b predicate refused this, naming the lander's own session. It lands.
printf '{"pid":%s,"sessionId":"%s","cwd":"%s","status":"busy","name":"self"}\n' \
  "$$" "$LSID" "$LR" > "$LD1/sessions/$$.json"
expect_true "a stand-in runner started (relative, in another repository)" \
  ld1_start "$LD1OTHER" "tests/run.sh"
LOUT4="$( cd "$LR" && CLAUDE_CODE_SESSION_ID="$LSID" bash "$SPAWN" land "$LTREE3" --by-hand --reason r 2>/dev/null )"; LRC4=$?
expect_match "a runner in another repository does not refuse the verb's land (T12 F3)" \
  "spawn-worktree: LANDED branch=wt/20-T4 onto=wave/20-demo *" "$LOUT4"
expect_eq   "it exits 0" "0" "$LRC4"
ld1_stop
unset BIONIC_CLAUDE_HOME


section "§WS: a named create records whose tree it is (wave-25 T1, REQ-2, AC-2.1 hermetic, D3)"
#
# THE ACT THAT MAKES THE TREE RECORDS IT. `create … --for <name>` appends one
# `workspace/v1` line to `<main-root>/.bionic/tmp/workspaces-<sid>.state` after the tree
# is verified; `create` without it appends nothing and prints the same attestation it
# always has. The readers are lib/worktree.sh's `workspace_for_name` and
# `workspaces_of_session`, and they answer from that file alone: a name nothing recorded
# has no tree, whatever `.worktrees/` happens to hold (no `worktree_for_row` naming
# fallback). The session is the one `land` already reads, CLAUDE_CODE_SESSION_ID through
# lib/session.sh, set per call here so the suite's own session never leaks in.
#
# THE PLANTED DEFECT (matrix AC-2.1, T1 row): `create` records nothing, or the reader
# falls back to the naming pattern. The first makes every line-count and reader row red;
# the second makes the `.worktrees/25-t2` row red: that tree exists, unrecorded, at exactly
# the path `worktree_for_row` spells for the roster name `W-25-T2`, on any filesystem.

WSLIB="${REPO}/payload/scripts/lib/worktree.sh"
ws_read() {  # <fn> <args...> -> the reader's stdout, then `rc=<n>` on its own line
  ( . "$WSLIB" 2>/dev/null || exit 9; "$@"; echo "rc=$?" )
}
ws_create() {  # <sid or -> <repo> <args...> -> stdout of create, then `rc=<n>`
  local sid="$1" cwd="$2"; shift 2
  if [ "$sid" = "-" ]; then
    ( cd "$cwd" && env -u CLAUDE_CODE_SESSION_ID bash "$SPAWN" create "$@" 2>/dev/null; echo "rc=$?" )
  else
    ( cd "$cwd" && CLAUDE_CODE_SESSION_ID="$sid" bash "$SPAWN" create "$@" 2>/dev/null; echo "rc=$?" )
  fi
}
ws_path() { printf '%s\n' "$1" | tr ' ' '\n' | sed -n 's/^path=//p'; }
ws_lines() { if [ -f "$1" ]; then grep -c '' "$1"; else echo 0; fi; }

WR="$(new_repo "$TMP/ws")"
WSID="ws-session-01"
WBASE="$(sha_of "$WR")"
WSF="${WR}/.bionic/tmp/workspaces-${WSID}.state"
mkdir -p "$WR/.bionic/docs/plans/epic-x" "$WR/.bionic/tmp"
WPLAN="$WR/.bionic/docs/plans/epic-x/wave-x.plan.md"
printf -- '---\nworking-branch: wave/25-demo\n---\n# plan\n\n## SDLC State\n\ncurrent: 4\n' > "$WPLAN"
printf 'plan=%s\nengaged_at=2026-10-03T00:00:00Z\n' "$WPLAN" > "$WR/.bionic/tmp/engaged-${WSID}.state"

# A named create: one line, all eight fields, the attestation unchanged.
WOUT="$(ws_create "$WSID" "$WR" "$WBASE" wt/25-T1 --for w25-T1)"
W1="$(ws_path "$WOUT")"
expect_eq "a named create exits 0" "rc=0" "$(printf '%s\n' "$WOUT" | tail -n1)"
expect_eq "the OK line names the tree (the extractor reads real output)" "${WR}/.worktrees/25-T1" "$W1"
expect_eq "the attestation is byte-identical to an unnamed create's shape" \
  "spawn-worktree: OK path=${WR}/.worktrees/25-T1 branch=wt/25-T1 head=${WBASE} base=${WBASE} alias=${WR}/.bionic" \
  "$(printf '%s\n' "$WOUT" | sed -n 1p)"
expect_eq "the attestation is the ONLY stdout line" "2" "$(printf '%s\n' "$WOUT" | grep -c '')"
expect_eq "a named create appends exactly one workspace line" "1" "$(ws_lines "$WSF")"
WLINE="$(sed -n 1p "$WSF" 2>/dev/null)"
expect_match "the line carries all eight fields, in the interface's order" \
  "workspace/v1|session=${WSID}|name=w25-T1|path=${W1}|branch=wt/25-T1|base=${WBASE}|plan=${WPLAN}|at=*" "$WLINE"
expect_regex "at= is an ISO-UTC stamp and closes the line" \
  '\|at=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' "$WLINE"

# An unnamed create, same session, same root: nothing appended, attestation as before.
WOUT2="$(ws_create "$WSID" "$WR" "$WBASE" wt/25-t2)"
expect_eq "an unnamed create exits 0" "rc=0" "$(printf '%s\n' "$WOUT2" | tail -n1)"
expect_eq "an unnamed create's tree exists (it ran)" "${WR}/.worktrees/25-t2" "$(ws_path "$WOUT2")"
expect_eq "an unnamed create appends nothing (the named one's line is still the only one)" \
  "1" "$(ws_lines "$WSF")"
expect_eq "…and writes no other workspace file" "1" \
  "$(ls "$WR/.bionic/tmp" | grep -c '^workspaces-')"

# The reader: the tree recorded for the name, and nothing for any other.
expect_eq "workspace_for_name returns the tree recorded for the name" \
  "$(printf '%s\nrc=0' "$W1")" "$(ws_read workspace_for_name "$WR" "$WSID" w25-T1)"
expect_eq "another name has no tree: empty, rc 1" \
  "rc=1" "$(ws_read workspace_for_name "$WR" "$WSID" w25-T9)"
expect_eq "an unrecorded name whose tree exists by the naming pattern still has none (no fallback)" \
  "rc=1" "$(ws_read workspace_for_name "$WR" "$WSID" w25-T2)"
expect_eq "…nor under its roster spelling" \
  "rc=1" "$(ws_read workspace_for_name "$WR" "$WSID" W-25-T2)"
expect_eq "the same name under another session has no tree" \
  "rc=1" "$(ws_read workspace_for_name "$WR" ws-session-other w25-T1)"

# A second create for the same name: the later tree answers; the session lists both.
WOUT3="$(ws_create "$WSID" "$WR" "$WBASE" wt/25-T1-retry --for w25-T1)"
W3="$(ws_path "$WOUT3")"
expect_eq "the second named create exits 0" "rc=0" "$(printf '%s\n' "$WOUT3" | tail -n1)"
expect_eq "it appends its own line" "2" "$(ws_lines "$WSF")"
expect_eq "workspace_for_name returns the LATER tree" \
  "$(printf '%s\nrc=0' "$W3")" "$(ws_read workspace_for_name "$WR" "$WSID" w25-T1)"
expect_eq "workspaces_of_session lists every recorded tree, in order" \
  "$(printf '%s\n%s\nrc=0' "$W1" "$W3")" "$(ws_read workspaces_of_session "$WR" "$WSID")"

# The flag is position-free and the positional form is untouched: flag first, with a
# relative parent directory as the third positional.
WOUT4="$(ws_create "$WSID" "$WR" --for w25-T4 "$WBASE" wt/25-T4 trees)"
expect_eq "--for before the positionals, with a parent dir, exits 0" "rc=0" "$(printf '%s\n' "$WOUT4" | tail -n1)"
expect_eq "the parent positional still places the tree" "${WR}/trees/25-T4" "$(ws_path "$WOUT4")"
expect_eq "and the record names that tree" \
  "$(printf '%s\nrc=0' "${WR}/trees/25-T4")" "$(ws_read workspace_for_name "$WR" "$WSID" w25-T4)"

# An unbound session records plan=none (the fallback run is never this session's).
WSID2="ws-session-unbound"
WOUT5="$(ws_create "$WSID2" "$WR" "$WBASE" wt/25-T5 --for w25-T5)"
expect_eq "a named create in an unbound session exits 0" "rc=0" "$(printf '%s\n' "$WOUT5" | tail -n1)"
expect_match "its line says plan=none" "workspace/v1|session=${WSID2}|name=w25-T5|*|plan=none|at=*" \
  "$(sed -n 1p "${WR}/.bionic/tmp/workspaces-${WSID2}.state" 2>/dev/null)"

# Refusals: each before anything is created, each beside the acceptance above.
WREFS0="$(git -C "$WR" for-each-ref --format='%(refname) %(objectname)')"
WOUT6="$(ws_create - "$WR" "$WBASE" wt/25-T6 --for w25-T6)"
expect_eq "a named create with no session id is refused, naming why" \
  "$(printf 'spawn-worktree: FAIL reason=no-session\nrc=2')" "$WOUT6"
WOUT7="$(ws_create "$WSID" "$WR" "$WBASE" wt/25-T7 --for 'w25|T7')"
expect_eq "a name that would break the line is refused" \
  "$(printf 'spawn-worktree: FAIL reason=invalid-name\nrc=2')" "$WOUT7"
WOUT8="$(ws_create "$WSID" "$WR" "$WBASE" wt/25-T8 --for)"
expect_eq "--for with no name is a usage refusal" \
  "$(printf 'spawn-worktree: FAIL reason=usage\nrc=2')" "$WOUT8"
expect_eq "no refused named create made a branch" "$WREFS0" \
  "$(git -C "$WR" for-each-ref --format='%(refname) %(objectname)')"
expect_true  "(the tree probe sees a recorded tree)" test -d "${WR}/.worktrees/25-T1"
expect_false "…or a tree" test -e "${WR}/.worktrees/25-T6"

# THE SYMLINK REFUSAL the roster files have: a symlinked workspace file (or a symlinked
# `.bionic/tmp`) is refused, never followed, and the tree is not made.
WSID3="ws-session-link"
printf 'outside\n' > "$TMP/ws-outside.state"
ln -s "$TMP/ws-outside.state" "${WR}/.bionic/tmp/workspaces-${WSID3}.state"
WOUT9="$(ws_create "$WSID3" "$WR" "$WBASE" wt/25-T9 --for w25-T9)"
expect_eq "a symlinked workspace file is refused, naming why" \
  "$(printf 'spawn-worktree: FAIL reason=workspace-file-symlinked\nrc=2')" "$WOUT9"
expect_eq "the link's target is not written through" "outside" "$(cat "$TMP/ws-outside.state")"
expect_false "no tree was made" test -e "${WR}/.worktrees/25-T9"
rm -f "${WR}/.bionic/tmp/workspaces-${WSID3}.state"
WOUT10="$(ws_create "$WSID3" "$WR" "$WBASE" wt/25-T9 --for w25-T9)"
expect_eq "the same create goes through once the link is gone (the arm discriminates)" \
  "rc=0" "$(printf '%s\n' "$WOUT10" | tail -n1)"
expect_eq "…and records its line in a regular file" "1" "$(ws_lines "${WR}/.bionic/tmp/workspaces-${WSID3}.state")"
expect_true "…and makes its tree" test -d "${WR}/.worktrees/25-T9"

WRL="$(new_repo "$TMP/ws-tmplink")"
mkdir -p "$TMP/ws-elsewhere-tmp"
ln -s "$TMP/ws-elsewhere-tmp" "${WRL}/.bionic/tmp"
WOUT11="$(ws_create "$WSID" "$WRL" "$(sha_of "$WRL")" wt/25-T11 --for w25-T11)"
expect_eq "a symlinked .bionic/tmp is refused too" \
  "$(printf 'spawn-worktree: FAIL reason=workspace-file-symlinked\nrc=2')" "$WOUT11"


section "§XC: create keeps the main checkout clean without touching the project's ignore files (wave-26 T60)"
#
# FIXTURE FIDELITY. Every other fixture in this suite (new_repo above) plants an ignore line
# for `.worktrees/`, which is exactly the condition under which the defect cannot show: git
# already hides the tree directory. The fixtures below are built WITHOUT that line, the shape
# of a project whose .gitignore never heard of the directory. xc_repo is SYNTHESIZED from the
# measured case (a clone with no ignore rule: `git status --porcelain` printed
# `?? .worktrees/` after one create).
#
# ANTI-VACUITY. Each "stays untouched" row sits beside a positive row on the same fixture
# family, and the first row proves the status extractor can see the dirt at all: the same
# repository, one create with the exclude line removed again, reads dirty.
xc_repo() {  # <dir> [gitignore-content] -> physical path; NO ignore rule for .worktrees/ by default
  local d="$1" gi="${2-.bionic
.bionic/
}"
  mkdir -p "$d"
  git -C "$d" init --quiet 2>/dev/null
  git -C "$d" symbolic-ref HEAD refs/heads/main
  mkdir -p "$d/.bionic/docs"
  echo "state" > "$d/.bionic/docs/note.md"
  printf '%s' "$gi" > "$d/.gitignore"
  echo "one" > "$d/file.txt"
  git -C "$d" add .gitignore file.txt
  git -C "$d" commit --quiet -m "c1"
  ( cd "$d" && pwd -P )
}
# The exclude file's text, and that text with one line appended, compared as $(…) reads them.
xc_text() { if [ -f "$1/.git/info/exclude" ]; then cat "$1/.git/info/exclude"; fi; }
xc_plus() { if [ -n "$1" ]; then printf '%s\n%s' "$1" "$2"; else printf '%s' "$2"; fi; }
xc_lines() {  # <repo> <line> -> how many times the exclude file holds exactly that line
  local f="$1/.git/info/exclude"
  if [ -f "$f" ]; then grep -cxF -- "$2" "$f" || true; else echo 0; fi
}

XC1="$(xc_repo "$TMP/xc1")"
XC1_SHA="$(sha_of "$XC1")"
XC1_OUT="$(spawn_out "$XC1" create "$XC1_SHA" xc-a)"
expect_match "(the create under test succeeded)" "spawn-worktree: OK path=*" "$XC1_OUT"
expect_true  "(the tree exists)" test -d "${XC1}/.worktrees/xc-a"
expect_empty "after create, the main checkout reads clean" "$(git -C "$XC1" status --porcelain)"
expect_eq    "info/exclude holds the anchored parent line once" "1" "$(xc_lines "$XC1" "/.worktrees/")"
expect_eq    "the project's .gitignore is untouched" ".bionic
.bionic/" "$(cat "$XC1/.gitignore")"
expect_empty "no tracked file changed" "$(git -C "$XC1" status --porcelain --untracked-files=no)"
XC1_OUT2="$(spawn_out "$XC1" create "$XC1_SHA" xc-b)"
expect_match "(the second create succeeded)" "spawn-worktree: OK path=*" "$XC1_OUT2"
expect_eq    "a second create adds nothing: still once" "1" "$(xc_lines "$XC1" "/.worktrees/")"
expect_empty "…and the checkout still reads clean with two trees" "$(git -C "$XC1" status --porcelain)"
# the extractor can see the dirt: take the line away again and the same repository reads dirty
: > "$XC1/.git/info/exclude"
expect_eq    "(control) without the exclude line the same checkout reads dirty" "?? .worktrees/" "$(git -C "$XC1" status --porcelain)"
# remove and land leave the line: a later tree needs it
spawn_out "$XC1" create "$XC1_SHA" xc-c >/dev/null
expect_eq    "(control) a create restores the line" "1" "$(xc_lines "$XC1" "/.worktrees/")"
spawn_out "$XC1" remove "${XC1}/.worktrees/xc-c" >/dev/null
expect_false "(the removed tree is gone)" test -e "${XC1}/.worktrees/xc-c"
expect_eq    "remove leaves the exclude line in place" "1" "$(xc_lines "$XC1" "/.worktrees/")"

# a parent already ignored by the project's own rule: the exclude file is not touched
XC2="$(xc_repo "$TMP/xc2" ".bionic
.worktrees/
")"
XC2_WAS="$(xc_text "$XC2")"
XC2_OUT="$(spawn_out "$XC2" create "$(sha_of "$XC2")" xc-d)"
expect_match "(ignored-parent create succeeded)" "spawn-worktree: OK path=*" "$XC2_OUT"
expect_true  "(…and its tree exists)" test -d "${XC2}/.worktrees/xc-d"
expect_eq    "a parent already ignored adds no exclude line" "0" "$(xc_lines "$XC2" "/.worktrees/")"
expect_eq    "…and the exclude file gained only the record link's line (T79)" "$(xc_plus "$XC2_WAS" /.bionic)" "$(xc_text "$XC2")"

# a parent already ignored by the exclude file itself under another spelling
XC3="$(xc_repo "$TMP/xc3")"
mkdir -p "$XC3/.git/info"; printf '.worktrees\n' > "$XC3/.git/info/exclude"
spawn_out "$XC3" create "$(sha_of "$XC3")" xc-e >/dev/null
expect_true  "(exclude-spelled create made its tree)" test -d "${XC3}/.worktrees/xc-e"
expect_eq    "a parent the exclude file already ignores is left alone (only the link's line follows it, T79)" ".worktrees
/.bionic" "$(cat "$XC3/.git/info/exclude")"

# a parent outside the checkout: nothing to exclude
XC4="$(xc_repo "$TMP/xc4")"
mkdir -p "$TMP/xc4-outside"
XC4_WAS="$(xc_text "$XC4")"
XC4_OUT="$(spawn_out "$XC4" create "$(sha_of "$XC4")" xc-f "$TMP/xc4-outside")"
expect_match "(outside-parent create succeeded)" "spawn-worktree: OK path=*" "$XC4_OUT"
expect_true  "(…and its tree is outside the checkout)" test -d "$TMP/xc4-outside/xc-f"
expect_eq    "an outside parent adds no exclude line" "0" "$(xc_lines "$XC4" "/xc4-outside/")"
expect_eq    "…and the exclude file gained only the record link's line (T79)" "$(xc_plus "$XC4_WAS" /.bionic)" "$(xc_text "$XC4")"

# a custom relative parent inside the checkout gets its own anchored line
XC5="$(xc_repo "$TMP/xc5")"
spawn_out "$XC5" create "$(sha_of "$XC5")" xc-g trees/here >/dev/null
expect_true  "(custom-parent tree exists)" test -d "${XC5}/trees/here/xc-g"
expect_eq    "a custom inside parent is excluded, anchored to the root" "1" "$(xc_lines "$XC5" "/trees/here/")"
expect_empty "…and that checkout reads clean" "$(git -C "$XC5" status --porcelain)"

# an unwritable info/ directory: the create still succeeds, stderr says the checkout reads dirty
XC6="$(xc_repo "$TMP/xc6")"
mkdir -p "$XC6/.git/info"; chmod 444 "$XC6/.git/info/exclude" 2>/dev/null; chmod 555 "$XC6/.git/info"
XC6_ERR="$TMP/xc6.err"
XC6_OUT="$( cd "$XC6" && bash "$SPAWN" create "$(sha_of "$XC6")" xc-h 2>"$XC6_ERR" )"; XC6_RC=$?
chmod 755 "$XC6/.git/info"; chmod 644 "$XC6/.git/info/exclude" 2>/dev/null
expect_eq    "an unwritable info/ does not fail the create" "0" "$XC6_RC"
expect_match "…and the attestation is still printed" "spawn-worktree: OK path=*" "$XC6_OUT"
expect_true  "…and the tree exists" test -d "${XC6}/.worktrees/xc-h"
expect_eq    "…and stderr carries exactly one line" "1" "$(wc -l < "$XC6_ERR" | tr -d ' ')"
expect_contains "…saying the checkout will read as dirty" "dirty" "$(cat "$XC6_ERR")"
expect_contains "…and naming the line to ignore by hand" "/.worktrees/" "$(cat "$XC6_ERR")"
expect_contains "…and the record link's line in that same one line (T79)" "/.bionic" "$(cat "$XC6_ERR")"
# the success path is silent on stderr (the warning above is not noise that always appears)
XC7_ERR="$TMP/xc7.err"
( cd "$XC1" && bash "$SPAWN" create "$XC1_SHA" xc-i >/dev/null 2>"$XC7_ERR" )
expect_empty "a create that excludes cleanly says nothing on stderr" "$(cat "$XC7_ERR")"

# a parent whose name carries a space and a glob character: the line means that directory only
XC8="$(xc_repo "$TMP/xc8")"
spawn_out "$XC8" create "$(sha_of "$XC8")" xc-j 'my trees[1]' >/dev/null
expect_true  "(odd-name tree exists)" test -d "${XC8}/my trees[1]/xc-j"
expect_eq    "an odd directory name is escaped in the line" "1" "$(xc_lines "$XC8" '/my\ trees\[1\]/')"
expect_empty "…and that checkout reads clean" "$(git -C "$XC8" status --porcelain)"

# mutation: the exclude call removed. The verifier reports the checkout's status after a create.
verify_clean_checkout() {  # <script> -> clean | dirty
  local script="$1" rr; rr="$(xc_repo "$TMP/xcm-$RANDOM")"
  spawn_out_with "$script" "$rr" create "$(sha_of "$rr")" xcm >/dev/null
  if [ -z "$(git -C "$rr" status --porcelain)" ]; then echo clean; else echo dirty; fi
}
expect_eq "live build: the checkout reads clean after a create" "clean" "$(verify_clean_checkout "$SPAWN")"
mutate_check "mutation: the exclude call removed is caught" \
  's|"\$(tree_parent_line "\$main_root" "\$parent_abs" "\$wt")"|""|' \
  verify_clean_checkout "dirty"

section "§XB: create keeps the record link out of every index (wave-27 T79, the walk's W2)"
#
# THE LOSS THIS STOPS. A project whose .gitignore does not list `.bionic` (the walk's listed
# only `.worktrees/`) let a writer's `git add -A` commit the link `create` plants; `land` merged
# it, and git replaced the main checkout's `.bionic` directory with a link to itself. So
# `create` writes `/.bionic` to the repository's info/exclude beside the parent's line, and
# `git add -A` in any tree of the repository never stages the link.
#
# ANTI-VACUITY. The status reader is shown seeing the link: take the line away and the same
# repository's tree stages `.bionic`.
XB1="$(xc_repo "$TMP/xb1" ".worktrees/
")"
XB1_OUT="$(spawn_out "$XB1" create "$(sha_of "$XB1")" xb-a)"
expect_match "(the create under test succeeded and planted its link)" "spawn-worktree: OK path=* alias=*" "$XB1_OUT"
XB1T="${XB1}/.worktrees/xb-a"
expect_true  "(the link is in the tree)" test -L "${XB1T}/.bionic"
echo work > "${XB1T}/a.txt"
expect_eq    "git add -A in the tree stages the work and never the link" "A  a.txt" \
  "$(git -C "$XB1T" add -A && git -C "$XB1T" status --porcelain)"
expect_eq    "info/exclude holds the anchored .bionic line once" "1" "$(xc_lines "$XB1" "/.bionic")"
expect_eq    "the project's .gitignore is untouched" ".worktrees/" "$(cat "$XB1/.gitignore")"
spawn_out "$XB1" create "$(sha_of "$XB1")" xb-b >/dev/null
expect_true  "(the second tree exists)" test -L "${XB1}/.worktrees/xb-b/.bionic"
expect_eq    "a second create adds nothing: still once" "1" "$(xc_lines "$XB1" "/.bionic")"
grep -vxF -- "/.bionic" "$XB1/.git/info/exclude" > "$TMP/xb1.exclude"; cp "$TMP/xb1.exclude" "$XB1/.git/info/exclude"
expect_eq    "(control) without the line, git add -A in that tree stages the link" "A  .bionic" \
  "$(git -C "${XB1}/.worktrees/xb-b" add -A && git -C "${XB1}/.worktrees/xb-b" status --porcelain)"
git -C "${XB1}/.worktrees/xb-b" reset --quiet

# a project whose .gitignore already lists .bionic gets the line too: idempotent and harmless
XB2="$(xc_repo "$TMP/xb2")"
XB2_OUT="$(spawn_out "$XB2" create "$(sha_of "$XB2")" xb-c)"
expect_match "(the create in a project that ignores .bionic succeeded)" "spawn-worktree: OK path=* alias=*" "$XB2_OUT"
expect_eq    "a project that already ignores .bionic still gets the line, once" "1" "$(xc_lines "$XB2" "/.bionic")"

# a branch that tracks its own .bionic gets no link, and so no line
XB3="$TMP/xb3"; mkdir -p "$XB3/.bionic"
git -C "$XB3" init --quiet; git -C "$XB3" symbolic-ref HEAD refs/heads/main
echo "tracked state" > "$XB3/.bionic/tracked.md"
git -C "$XB3" add .bionic/tracked.md; git -C "$XB3" commit --quiet -m "a tracked .bionic"
XB3="$(cd "$XB3" && pwd -P)"
XB3_OUT="$(spawn_out "$XB3" create "$(sha_of "$XB3")" xb-d)"
expect_match "(the create on a branch tracking .bionic succeeded)" "spawn-worktree: OK path=*" "$XB3_OUT"
expect_true  "(…its .bionic is the branch's own directory)" test -f "${XB3}/.worktrees/xb-d/.bionic/tracked.md"
expect_eq    "no link planted, so no .bionic line" "0" "$(xc_lines "$XB3" "/.bionic")"
expect_eq    "…while the parent's line is written as before" "1" "$(xc_lines "$XB3" "/.worktrees/")"

# mutation: the .bionic line dropped from the call. The verifier stages everything in a fresh tree.
verify_link_unstaged() {  # <script> -> unstaged | staged
  local script="$1" rr; rr="$(xc_repo "$TMP/xbm-$RANDOM" ".worktrees/
")"
  spawn_out_with "$script" "$rr" create "$(sha_of "$rr")" xbm >/dev/null
  [ -L "$rr/.worktrees/xbm/.bionic" ] || { echo "no-link"; return; }
  git -C "$rr/.worktrees/xbm" add -A
  case "$(git -C "$rr/.worktrees/xbm" status --porcelain)" in *.bionic*) echo staged ;; *) echo unstaged ;; esac
}
expect_eq "live build: a fresh tree's git add -A leaves the link unstaged" "unstaged" "$(verify_link_unstaged "$SPAWN")"
mutate_check "mutation: the .bionic line dropped from the exclude call is caught" \
  's|"\${alias_field:+/.bionic}"|""|' \
  verify_link_unstaged "staged"

section "§READY: the writer's landing — its tree refusals and the WAITING line (wave-28 T4, D3)"
#
# `ready` runs from the row's own tree in the model world (tests/lib/world.sh): the bound plan's
# working branch `wave/x`, row trees T1 and T2, and T1's launch line on the roster naming the suite
# it lands on. A tree that is detached, dirty or not ahead is refused (exit 2) before anything is
# appended to the line; a suite whose promised seconds exceed the time left is never started.
. "$(dirname "$0")/lib/world.sh"
. "${REPO}/payload/scripts/lib/roster.sh"
. "$(dirname "$0")/lib/roster-row.sh"
export CLAUDE_CONFIG_DIR="$WORLD_ROOT/home"
mkdir -p "$CLAUDE_CONFIG_DIR/bionic"; printf '80\n' > "$CLAUDE_CONFIG_DIR/bionic/share"
world_machine 8 8192 40 0.5
world_clock 1000
rd_world() {  # -> a world root with T1's launch line naming a.test.sh
  local r
  r="$(world_repo)" || return 1
  [ -n "$r" ] && [ "$(git -C "$r" rev-parse --show-toplevel 2>/dev/null)" = "$r" ] || return 1
  # THE PLAN THE REAL COMMIT GATE ADMITS (wave-28 T9, after T6): `ready` now writes the row's own
  # line through `row-landed`, whose dry commit runs the real gate over the world's plan, so the
  # plan carries what landing-line's ll_world gives it: the version, the approval and the rows' lines.
  awk '{ print }
    /^working-branch: / { print "canonical_sdlc_version: 14" }
    /^current: 4$/ { print "approved-by: fixture 2026-10-04T00:00Z \"approved\""; print "- Step 4: started"; print "- T1: active"; print "- T2: active" }' \
    "$r/.bionic/docs/plans/epic-x/wave-x.plan.md" > "$r/.bionic/docs/plans/epic-x/wave-x.plan.md.n" \
    && mv "$r/.bionic/docs/plans/epic-x/wave-x.plan.md.n" "$r/.bionic/docs/plans/epic-x/wave-x.plan.md"
  printf '%s|row=T1|lands_on=a.test.sh\n' "$(roster_row_fixture status=intended session="$WORLD_SID" name=wx-T1 \
    agent_id=b00T1 plan="$r/.bionic/docs/plans/epic-x/wave-x.plan.md")" >> "$r/.bionic/tmp/roster-$WORLD_SID.state"
  printf '%s' "$r"
}
rd_ready() {  # <tree> [args] -> RD_OUT, RD_RC
  local t="$1"; shift
  RD_OUT="$( cd "$t" && CLAUDE_CODE_SESSION_ID="$WORLD_SID" BIONIC_GATE_POLL=0.1 BIONIC_LINE_POLL=0.2 bash "$SPAWN" ready "$@" 2>&1 )"; RD_RC=$?
}
rd_rec() { printf '%s/.bionic/docs/record/wave-x/landing-proofs.log' "$1"; }
RDA="$(rd_world)"
expect_nonempty "(fixture) the world repository was made" "$RDA"
git -C "$RDA/.worktrees/T1" checkout -q --detach
rd_ready "$RDA/.worktrees/T1"
expect_eq "ready from a detached tree is refused (exit 2)" "2" "$RD_RC"
expect_match "…naming why" "spawn-worktree: REFUSED reason=detached path=*/.worktrees/T1 — *" "$RD_OUT"
git -C "$RDA/.worktrees/T1" checkout -q wt/T1
echo dirt >> "$RDA/.worktrees/T1/T1.txt"
rd_ready "$RDA/.worktrees/T1"
expect_eq "ready from a dirty tree is refused (exit 2)" "2" "$RD_RC"
expect_match "…naming why" "spawn-worktree: REFUSED reason=dirty-tree path=*/.worktrees/T1 branch=wt/T1" "$RD_OUT"
git -C "$RDA/.worktrees/T1" checkout -q -- T1.txt
git -C "$RDA" merge -q --no-ff -m "T1 by hand" wt/T1
rd_ready "$RDA/.worktrees/T1"
expect_eq "ready from a tree not ahead of the working branch is refused (exit 2)" "2" "$RD_RC"
expect_eq "…naming why" "spawn-worktree: REFUSED reason=nothing-to-land branch=wt/T1 onto=wave/x" "$RD_OUT"
expect_false "…and none of the three appended anything to the line" test -e "$(rd_rec "$RDA")"
expect_false "…or took a landing tree" test -e "$RDA/.bionic/tmp/landing"
rd_ready "$RDA/.worktrees/T1" --within soon
expect_eq "--within takes whole seconds (exit 2)" "2" "$RD_RC"
expect_match "…saying so" "spawn-worktree: REFUSED reason=usage within=soon — *" "$RD_OUT"

RDB="$(rd_world)"
world_cost a.test.sh 5 0.5 600
rd_ready "$RDB/.worktrees/T1" --within 60
expect_eq "a suite promising more seconds than are left: exit 75" "75" "$RD_RC"
expect_eq "…printing WAITING and the same command, exactly" \
  "WAITING T1 — run again: bash ${SPAWN} ready --within 60" "$RD_OUT"
expect_contains "…the entry kept on the line" "|ev=ready|row=T1|" "$(cat "$(rd_rec "$RDB")" 2>/dev/null)"
expect_absent "…and no suite run" "ev=verdict" "$(cat "$(rd_rec "$RDB")" 2>/dev/null)"
rd_ready "$RDB/.worktrees/T1" --within 900
expect_eq "the same command with the time: LANDED (exit 0)" "0" "$RD_RC"
expect_match "…printing LANDED, then the owed line" \
  "LANDED T1 *
landed T1 * — owed: complete task T1, then stop wx-T1" "$RD_OUT"
expect_eq "…and the working branch moved to the landed commit" \
  "$(git -C "$RDB" rev-parse wave/x)" "$(printf '%s\n' "$RD_OUT" | sed -n 's/^LANDED T1 //p')"

section "§UPGRADE: a run open at upgrade continues — a 1.12.0 plan lands by ready, its stamp is never read, a bare land names the new verbs (wave-28 T21; D26, REQ-2 AC-2.11, REQ-7 AC-7.2)"
#
# The fixture is a plan AS 1.12.0 WROTE IT (tests/fixtures/upgrade-1.12.0): the `source=probe` budget line, rows
# with no `Lands-on:` label, and roster launch rows carrying `suites_allowed=` and neither `row=` nor `lands_on=`.
# T1's tree holds a stamp, in the bare form 1.12.0's land read, that says RED for a.test.sh at T1's head. `ready`
# lands the row on a green run of its own and reads no stamp.
. "$(dirname "$0")/fixtures/upgrade-1.12.0/install.sh"
world_cost a.test.sh 5 0.5 5
up_world() {  # [<T1 suites_allowed>] -> a world root holding the 1.12.0 fixture (its own launch rows, not rd_world's)
  local r
  r="$(world_repo)" || return 1
  [ -n "$r" ] && [ "$(git -C "$r" rev-parse --show-toplevel 2>/dev/null)" = "$r" ] || return 1
  up_install "$r" "$@" || return 1
  printf '%s' "$r"
}
up_rec() { printf '%s/.bionic/docs/record/wave-x/landing-proofs.log' "$1"; }
UPA="$(up_world)"
UPA_T1="$UPA/.worktrees/T1"
UPA_HEAD="$(git -C "$UPA_T1" rev-parse HEAD)"
UPA_STAMPS="$(git -C "$UPA_T1" rev-parse --absolute-git-dir)/bionic-stamps"
UPA_WHY="$(bash -c '. "$1" 2>/dev/null; _wt_stale_proof "$2" "$3"' _ "${REPO}/payload/scripts/lib/worktree.sh" "$UPA_T1" "$UPA_HEAD" 2>&1)"
expect_match "(up1-pre) the planted stamp is a RED to 1.12.0's own reader: the land judges the tree's runs stale" "why=*" "$UPA_WHY"
UPA_STAMP_BYTES="$(cat "$UPA_STAMPS")"
rd_ready "$UPA_T1"
expect_eq "(up1) ready on the 1.12.0 fixture lands the row (exit 0)" "0" "$RD_RC"
expect_match "(up1) …printing LANDED, then the owed line" "LANDED T1 *
landed T1 * — owed: complete task T1, then stop wx-T1" "$RD_OUT"
UPA_C="$(printf '%s\n' "$RD_OUT" | sed -n 's/^LANDED T1 //p')"
expect_eq "(up1) …and the working branch moved to the landed commit" "$UPA_C" "$(git -C "$UPA" rev-parse wave/x)"
expect_contains "(up2) the suite that decided it ran on the candidate and was green, whatever the stamp said" \
  "|ev=verdict|row=T1|commit=${UPA_C}|suite=a.test.sh|result=green|" "$(cat "$(up_rec "$UPA")" 2>/dev/null)"
expect_eq "(up2) …and the stamp is exactly as it was planted (ready neither read nor wrote it)" "$UPA_STAMP_BYTES" "$(cat "$UPA_STAMPS")"

# THE MUTATION ARM: a copy of the scripts whose `ready` judges the tree's stamps as 1.12.0's land did. It runs in a
# directory made outside every checkout; the tracked file is never touched.
UPM_DIR="$(mktemp -d "${TMPDIR:-/tmp}/up-mutant.XXXXXX")"
cp -R "${REPO}/payload/scripts" "$UPM_DIR/scripts" 2>/dev/null
awk '/^  # THE ROSTER.S LAUNCH LINE \(labels, D4\)/ && !d { print "  why=\"$(_wt_stale_proof \"$wt\" \"$head\")\" && { _wt_refuse \"stale-proof ${why}\"; return 2; }"; d = 1 }
  { print }' "${REPO}/payload/scripts/lib/line.sh" > "$UPM_DIR/scripts/lib/line.sh"
expect_eq "(up3-pre) the mutant differs from line.sh by the one stamp-reading line" "1" \
  "$(diff "${REPO}/payload/scripts/lib/line.sh" "$UPM_DIR/scripts/lib/line.sh" | /usr/bin/grep -c '^>')"
UPM="$(up_world)"
UPM_OUT="$( cd "$UPM/.worktrees/T1" && CLAUDE_CODE_SESSION_ID="$WORLD_SID" BIONIC_GATE_POLL=0.1 BIONIC_LINE_POLL=0.2 bash "$UPM_DIR/scripts/spawn-worktree.sh" ready 2>&1 )"; UPM_RC=$?
expect_eq "(up3) the mutant that reads the stamp refuses the row (exit 2), so (up1) goes red against it" "2" "$UPM_RC"
expect_contains "(up3) …saying the proof was stale" "REFUSED reason=stale-proof" "$UPM_OUT"
rm -rf "$UPM_DIR"

# A 1.12.0 ROW THAT NAMES NO SUITE: one line, naming the person's landing, and nothing appended to the line.
UPB="$(up_world -)"
UPB_T1="$UPB/.worktrees/T1"
rd_ready "$UPB_T1"
expect_eq "(up4) a launch row naming no suite is refused (exit 2)" "2" "$RD_RC"
expect_eq "(up4) …in one line" "1" "$(printf '%s\n' "$RD_OUT" | awk 'END { print NR }')"
expect_contains "(up4) …naming the row and its writer" "REFUSED reason=no-lands-on row=T1 name=wx-T1" "$RD_OUT"
expect_contains "(up4) …and the hand landing, with its reason" "land ${UPB_T1} --by-hand --reason '<why>'" "$RD_OUT"
expect_false "(up4) …and nothing was appended to the line" test -e "$(up_rec "$UPB")"
printf '%s|row=T1|lands_on=a.test.sh\n' "$(roster_row_fixture status=intended session="$WORLD_SID" name=wx-T1 agent_id=b00T1 plan="$UPB/.bionic/docs/plans/epic-x/wave-x.plan.md")" \
  >> "$UPB/.bionic/tmp/roster-$WORLD_SID.state"
rd_ready "$UPB_T1"
expect_eq "(up4-control) the same tree lands once the launch row names a suite, and the line then holds its entry" "0 yes" \
  "$RD_RC $(test -s "$(up_rec "$UPB")" && echo yes || echo no)"
UPC="$(up_world)"
UPC_T2="$UPC/.worktrees/T2"
rd_ready "$UPC_T2"
expect_eq "(up5) a row whose brief waived every suite (suites_allowed=none) is refused the same way (exit 2)" "2" "$RD_RC"
expect_contains "(up5) …naming the hand landing" "land ${UPC_T2} --by-hand --reason '<why>'" "$RD_OUT"

# A BARE `land` ON THE FIXTURE: the old verb names both new ones, and moves nothing.
UPD="$(up_world)"
UPD_REFS="$(git -C "$UPD" for-each-ref --format='%(refname) %(objectname)')"
UPD_PLAN="$(cat "$UPD/.bionic/docs/plans/epic-x/wave-x.plan.md")"
UPD_OUT="$( cd "$UPD" && CLAUDE_CODE_SESSION_ID="$WORLD_SID" bash "$SPAWN" land "$UPD/.worktrees/T1" 2>&1 )"; UPD_RC=$?
expect_eq "(up6) a bare land on the fixture prints the line naming ready and --by-hand, exactly" \
  "land: the line lands a row with \"ready\"; a person lands one with \"land <tree> --by-hand --reason '<why>'\"" "$UPD_OUT"
expect_eq "(up6) …and exits 2" "2" "$UPD_RC"
expect_nonempty "(up6-pre) the refs read back" "$UPD_REFS"
expect_eq "(up6) …and no ref moved" "$UPD_REFS" "$(git -C "$UPD" for-each-ref --format='%(refname) %(objectname)')"
expect_eq "(up6) …and the plan is as it was" "$UPD_PLAN" "$(cat "$UPD/.bionic/docs/plans/epic-x/wave-x.plan.md")"

finish
