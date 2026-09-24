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

# Refused first: no session id means no binding, so no target — and nothing moves.
LREFS0="$(git -C "$LR" for-each-ref --format='%(refname) %(objectname)')"
LNOSID="$( cd "$LR" && env -u CLAUDE_CODE_SESSION_ID bash "$SPAWN" land "$LTREE" 2>/dev/null )"; LNOSID_RC=$?
expect_match "land with no session id is refused, naming why" \
  "spawn-worktree: REFUSED reason=no-session*" "$LNOSID"
expect_eq "that refusal exits 2" "2" "$LNOSID_RC"
expect_eq "no ref moved" "$LREFS0" "$(git -C "$LR" for-each-ref --format='%(refname) %(objectname)')"
expect_true "the tree survives" test -d "$LTREE"

LOUT="$( cd "$LR" && CLAUDE_CODE_SESSION_ID="$LSID" bash "$SPAWN" land "$LTREE" 2>/dev/null )"; LRC=$?
expect_match "land from the bound session names the working branch and its checkout" \
  "spawn-worktree: LANDED branch=wt/20-T1 onto=wave/20-demo checkout=${LWAVE} merge=* removed=${LTREE}" "$LOUT"
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
LOUT2="$( cd "$LR" && CLAUDE_CODE_SESSION_ID="$LSID" bash "$SPAWN" land "$LTREE2" 2>/dev/null )"; LRC2=$?
expect_match "(T8c: was \"the verb's own busy suite does not refuse its own land\") the verb's own session's floor in the wave checkout refuses its own land" \
  "spawn-worktree: REFUSED reason=suite-running*script=${LWAVE}/tests/run.sh*" "$LOUT2"
expect_eq   "that refusal exits 2" "2" "$LRC2"
expect_eq   "no ref moved" "$LREFS2" "$(git -C "$LR" for-each-ref --format='%(refname) %(objectname)')"
expect_true "the tree survives" test -d "$LTREE2"
ld1_stop
LOUT2B="$( cd "$LR" && CLAUDE_CODE_SESSION_ID="$LSID" bash "$SPAWN" land "$LTREE2" 2>/dev/null )"; LRC2B=$?
expect_match "the same land goes through once the floor has finished (the arm discriminates)" \
  "spawn-worktree: LANDED branch=wt/20-T2 onto=wave/20-demo *" "$LOUT2B"
expect_eq   "it exits 0" "0" "$LRC2B"

# A suite in this root refuses from any session: the busy file now names a different
# session, and the runner's script lives outside every repository. Only its working
# directory, the main checkout, places it.
LTREE3_OUT="$(spawn_out "$LR" create "$(sha_of "$LR" wave/20-demo)" wt/20-T3)"
LTREE3="$(printf '%s\n' "$LTREE3_OUT" | tr ' ' '\n' | sed -n 's/^path=//p')"
echo work3 > "$LTREE3/t3.txt"
git -C "$LTREE3" add t3.txt
git -C "$LTREE3" commit --quiet -m "T3 work"
printf '{"pid":%s,"sessionId":"%s","cwd":"%s","status":"busy","name":"peer"}\n' \
  "$$" "verb-peer-session" "$LR" > "$LD1/sessions/$$.json"
LRREAL="$(cd "$LR" && pwd -P)"
expect_true "a stand-in runner started (cwd the main checkout)" ld1_start "$LR" "$LD1ELSE/tests/run.sh"
LOUT3="$( cd "$LR" && CLAUDE_CODE_SESSION_ID="$LSID" bash "$SPAWN" land "$LTREE3" 2>/dev/null )"; LRC3=$?
expect_match "(T8c: was \"a different session's busy suite in this project still refuses\") a suite in this root refuses, from any session" \
  "spawn-worktree: REFUSED reason=suite-running*cwd=${LRREAL} *" "$LOUT3"
expect_eq   "that refusal exits 2" "2" "$LRC3"
ld1_stop

# T12 F3: the only runner is in ANOTHER repository, the lander's own session busy at the
# root. The pre-T8b predicate refused this, naming the lander's own session. It lands.
printf '{"pid":%s,"sessionId":"%s","cwd":"%s","status":"busy","name":"self"}\n' \
  "$$" "$LSID" "$LR" > "$LD1/sessions/$$.json"
expect_true "a stand-in runner started (relative, in another repository)" \
  ld1_start "$LD1OTHER" "tests/run.sh"
LOUT4="$( cd "$LR" && CLAUDE_CODE_SESSION_ID="$LSID" bash "$SPAWN" land "$LTREE3" 2>/dev/null )"; LRC4=$?
expect_match "a runner in another repository does not refuse the verb's land (T12 F3)" \
  "spawn-worktree: LANDED branch=wt/20-T3 onto=wave/20-demo *" "$LOUT4"
expect_eq   "it exits 0" "0" "$LRC4"
ld1_stop
unset BIONIC_CLAUDE_HOME

finish
