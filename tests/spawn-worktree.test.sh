#!/bin/bash
# SPAWN-WORKTREE — epic-17 wave-03 slice S2 (spec AC-10, design ledger D4).
#
# WHAT THIS SUITE OWNS. One payload script:
#
#   payload/scripts/spawn-worktree.sh   the universal worktree contract
#
# WHY IT IS NOT IN tests/plugin-lib.test.sh. That suite's header names its
# subject: the two SOURCED libraries every command consumes, driven through a
# `lib_run` harness that sources a file and calls a function. This subject is an
# EXECUTED script whose whole behavior is mutation of a real git repository, and
# its fixture is a scratch repo rather than a fixture root plus a stubbed PATH.
# Sharing a file would mean two fixture regimes under one header; a second
# hand-listed `run` line in tests/run.sh is the cheaper half of that trade.
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
# Registered by name in tests/run.sh (tests/*.test.sh is NOT auto-globbed).

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"

REPO="${BIONIC_SCRIPTS_DIR}"
SPAWN="${REPO}/payload/scripts/spawn-worktree.sh"

PASS=0; FAIL=0; TOTAL=0
ok() { TOTAL=$((TOTAL + 1)); PASS=$((PASS + 1)); echo "PASS: $1"; }
no() { TOTAL=$((TOTAL + 1)); FAIL=$((FAIL + 1)); echo "FAIL: $1"; [ -n "${2:-}" ] && echo "      $2"; return 0; }

expect_eq() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "expected '$2', got '$3'"; fi; }
expect_true() { local label="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$label"; else no "$label"; fi; }
expect_false() { local label="$1"; shift; if "$@" >/dev/null 2>&1; then no "$label" "expected non-zero exit"; else ok "$label"; fi; }
# Pattern match without a pipe: `printf | grep -q` is a SIGPIPE race under
# pipefail (tests/assert-helper-race.test.sh pins that lesson).
expect_match() {
  local label="$1" pattern="$2" actual="$3"
  # shellcheck disable=SC2053  # RHS is a glob on purpose
  if [[ "$actual" == $pattern ]]; then ok "$label"; else no "$label" "'$actual' does not match '$pattern'"; fi
}

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
  printf '.bionic/\n.worktrees/\n' > "$d/.gitignore"
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

echo "=== Group 1: the script exists, is executable, and parses ==="

# (file-exists/executable fixture checks removed epic-18 W3 4/6: no production subject -- see ledger-spawn-worktree.md)
expect_true "spawn-worktree.sh passes bash -n"  bash -n "$SPAWN"

echo ""
echo "=== Group 2: create — the call succeeds ==="

R1="$(new_repo "$TMP/r1")"
SHA1="$(sha_of "$R1")"
spawn_out "$R1" create "$SHA1" feat-alpha >/dev/null

expect_eq "create exits 0" "0" "$(spawn_rc "$R1" create "$SHA1" feat-alpha-2)"

echo ""
echo "=== Group 3: create — what the line CLAIMS is what is on disk ==="
#
# An attestation is worth nothing if it is printed from the arguments rather
# than read back from the result. Each field is re-derived from the filesystem
# and from git, independently of the line.

expect_true "the worktree directory exists"            test -d "${R1}/.worktrees/feat-alpha"
expect_eq   "the worktree HEAD is the requested base"  "$SHA1" "$(sha_of "${R1}/.worktrees/feat-alpha")"
expect_eq   "the branch was created at the base"       "$SHA1" "$(git -C "$R1" rev-parse refs/heads/feat-alpha)"
expect_eq   "the worktree is ON that branch"           "feat-alpha" "$(git -C "${R1}/.worktrees/feat-alpha" rev-parse --abbrev-ref HEAD)"
expect_true "the .bionic entry is a symlink"           test -L "${R1}/.worktrees/feat-alpha/.bionic"
expect_eq   "the symlink resolves to the repo root's .bionic" \
  "${R1}/.bionic" "$( cd "${R1}/.worktrees/feat-alpha/.bionic" && pwd -P )"
expect_true "content written through the symlink lands in the repo root's .bionic" \
  test -f "${R1}/.worktrees/feat-alpha/.bionic/docs/note.md"
# The W1 ruling: ONE symlink, nothing else. No .claude/rules affordance.
expect_eq "the plant adds exactly one entry to the worktree tree" \
  ".bionic" "$(cd "${R1}/.worktrees/feat-alpha" && ls -A | grep -v -e '^\.git$' -e '^file.txt$' -e '^\.gitignore$')"

echo ""
echo "=== Group 4: create — base resolution and the older-commit arm ==="
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
echo ""
echo "=== Group 5: create — where the worktree lands ==="
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

echo ""
echo "=== Group 6: create — spawning from INSIDE a linked worktree ==="
#
# The nesting accident this repo actually suffered. A dispatcher running inside
# a worktree must produce a SIBLING under the main checkout, not a worktree
# inside a worktree, and its .bionic symlink must reach the main root's state
# directory rather than a worktree's own symlink.

R4="$(new_repo "$TMP/r4")"
SHA4="$(sha_of "$R4")"
spawn_out "$R4" create "$SHA4" first >/dev/null
OUT4="$(spawn_out "${R4}/.worktrees/first" create "$SHA4" second)"
expect_match "a worktree spawned from inside a worktree is a SIBLING" \
  "*path=${R4}/.worktrees/second *" "$OUT4"
expect_match "its .bionic symlink targets the MAIN root's state dir" \
  "*bionic-symlink=${R4}/.bionic" "$OUT4"
expect_false "no nested .worktrees directory was created" test -d "${R4}/.worktrees/first/.worktrees"

echo ""
echo "=== Group 7: create — refusals ==="
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
expect_false "that refusal left no worktree behind" test -e "${NB}/.worktrees/nostate"
mkdir -p "$NB/.bionic"
expect_match "the same repo is accepted once .bionic exists (the arm discriminates)" \
  "spawn-worktree: OK *" "$(spawn_out "$NB" create "$NBSHA" nostate)"

echo ""
echo "=== Group 8: create — failed self-verification cleans up completely ==="
#
# Triggered WITHOUT doctoring the script: a repo whose tracked tree already
# carries a `.bionic` path. `git worktree add` checks that content out, so the
# plant target is occupied by a real directory — and `ln -s` into a directory
# would silently create `.bionic/.bionic` and attest a link that leads
# somewhere else entirely. The contract says: verify, undo, refuse.

R6="$TMP/r6"; mkdir -p "$R6/.bionic"
git -C "$R6" init --quiet
git -C "$R6" symbolic-ref HEAD refs/heads/main
echo "tracked state" > "$R6/.bionic/tracked.md"   # tracked on purpose: no .gitignore
echo x > "$R6/f"
git -C "$R6" add .bionic/tracked.md f
git -C "$R6" commit --quiet -m "c1 with a tracked .bionic"
R6="$(cd "$R6" && pwd -P)"
SHA6="$(sha_of "$R6")"
OUT6="$(spawn_out "$R6" create "$SHA6" doomed)"
RC6="$(spawn_rc "$R6" create "$SHA6" doomed2)"

expect_match "an occupied plant target fails the attestation" "spawn-worktree: FAIL reason=*" "$OUT6"
expect_eq   "the failure exits nonzero" "1" "$RC6"
expect_false "the worktree directory was removed"  test -d "${R6}/.worktrees/doomed"
expect_false "the branch it created was deleted"   git -C "$R6" show-ref --verify --quiet refs/heads/doomed
expect_eq   "git's worktree registry is clean afterwards" "1" \
  "$(git -C "$R6" worktree list | grep -c .)"
expect_eq   "no OK line was printed alongside the failure" "0" \
  "$(printf '%s\n' "$OUT6" | grep -c 'OK')"

echo ""
echo "=== Group 9: remove — the companion verb ==="
#
# Teardown is never automatic and never deletes the branch: the merge decision
# belongs to the orchestrator (D4), so `remove` gives back a tree and keeps the
# work reachable.

R7="$(new_repo "$TMP/r7")"
SHA7="$(sha_of "$R7")"
spawn_out "$R7" create "$SHA7" temp-work >/dev/null
OUT7="$(spawn_out "$R7" remove "${R7}/.worktrees/temp-work")"

expect_match "remove reports success" "spawn-worktree: REMOVED *" "$OUT7"
expect_false "the worktree directory is gone" test -d "${R7}/.worktrees/temp-work"
expect_true  "the BRANCH survives removal" git -C "$R7" show-ref --verify --quiet refs/heads/temp-work
expect_eq    "the branch still points at the base it was created from" \
  "$SHA7" "$(git -C "$R7" rev-parse refs/heads/temp-work)"
expect_eq    "git's worktree registry no longer lists it" "1" \
  "$(git -C "$R7" worktree list | grep -c .)"
expect_true  "the repo root's .bionic survived (the symlink was followed, never chased)" \
  test -f "${R7}/.bionic/docs/note.md"

# Removal is a git operation with git's own safety: uncommitted work refuses.
spawn_out "$R7" create "$SHA7" dirty-work >/dev/null
echo "unsaved" >> "${R7}/.worktrees/dirty-work/file.txt"
expect_match "a worktree with uncommitted changes is refused" "spawn-worktree: FAIL reason=*" \
  "$(spawn_out "$R7" remove "${R7}/.worktrees/dirty-work")"
expect_true "the refused worktree is still there" test -d "${R7}/.worktrees/dirty-work"
expect_true "its .bionic symlink was put back after the refusal" \
  test -L "${R7}/.worktrees/dirty-work/.bionic"

expect_match "removing a path that is not a worktree is refused" "spawn-worktree: FAIL reason=*" \
  "$(spawn_out "$R7" remove "${R7}/.worktrees/never-existed")"
expect_match "removing the MAIN checkout is refused" "spawn-worktree: FAIL reason=*" \
  "$(spawn_out "$R7" remove "$R7")"
expect_true "the main checkout is untouched" test -f "${R7}/file.txt"
expect_match "remove with no path is refused" "spawn-worktree: FAIL reason=*" \
  "$(spawn_out "$R7" remove)"

echo ""
echo "=== Group 10: mutation and restore — do the pins above actually catch? ==="
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

# Mutation 2 — the symlink plant. A worktree with no `.bionic` link is a writer
# with no plan directory; the contract says such a tree is never attested.
verify_plant() {  # <script> -> planted | unplanted
  local script="$1"
  local rr; rr="$(new_repo "$TMP/mut2-$RANDOM")"
  local sha; sha="$(git -C "$rr" rev-parse HEAD)"
  local out; out="$(spawn_out_with "$script" "$rr" create "$sha" m2)"
  if [ -L "$rr/.worktrees/m2/.bionic" ] && [[ "$out" == "spawn-worktree: OK "* ]]; then
    echo "planted"
  else
    echo "unplanted"
  fi
}

# Mutation 3 — the cleanup on failed verification. Driven by the Group 8
# fixture (tracked `.bionic` occupies the plant target). With cleanup gone, an
# unattested worktree and its branch survive the refusal.
verify_cleanup() {  # <script> -> cleaned | residue
  local script="$1"
  local rr="$TMP/mut3-$RANDOM"; mkdir -p "$rr/.bionic"
  git -C "$rr" init --quiet 2>/dev/null
  echo s > "$rr/.bionic/tracked.md"; echo x > "$rr/f"
  git -C "$rr" add .bionic/tracked.md f; git -C "$rr" commit --quiet -m c1
  rr="$(cd "$rr" && pwd -P)"
  local sha; sha="$(git -C "$rr" rev-parse HEAD)"
  spawn_out_with "$script" "$rr" create "$sha" m3 >/dev/null
  if [ -d "$rr/.worktrees/m3" ] || git -C "$rr" show-ref --verify --quiet refs/heads/m3; then
    echo "residue"
  else
    echo "cleaned"
  fi
}

# Sanity first: against the REAL script every verifier reports the healthy
# verdict. Without this the mutation arms could be passing for the wrong reason.
expect_eq "live build: an unhonored base is refused"    "refused" "$(verify_head_check "$SPAWN")"
expect_eq "live build: the symlink is planted"          "planted" "$(verify_plant "$SPAWN")"
expect_eq "live build: a failed verification cleans up" "cleaned" "$(verify_cleanup "$SPAWN")"

mutate_check "mutation: head taken from the argument instead of the tree is caught" \
  's|head="$(git -C "$wt" rev-parse HEAD 2>/dev/null)"|head="$base_sha"|' \
  verify_head_check "attested-blindly"
mutate_check "mutation: the symlink plant removed is caught" \
  's|^  ln -s |  : ln -s |' \
  verify_plant "unplanted"
mutate_check "mutation: the cleanup on failed verification removed is caught" \
  's|^  cleanup_partial$|  :|' \
  verify_cleanup "residue"

echo ""
echo "=== Group 11: the suite is registered in tests/run.sh by name ==="
#
# tests/*.test.sh is NOT globbed by the runner — an unregistered suite is a
# silent false green (tests/run.sh records the last time that happened).

expect_true "tests/run.sh names spawn-worktree.test.sh" \
  grep -q 'run "spawn-worktree.test.sh" bash tests/spawn-worktree.test.sh' "${REPO}/tests/run.sh"

echo ""
echo "=== Group 12: the shipped skill is the payload's own copy ==="

expect_eq "the skill is the plugin payload's own copy (symlink, not a fork)" \
  "$(cd "${REPO}/payload/skills/canonical-sdlc" && pwd -P)" \
  "$(cd "${BIONIC_SKILLS_DIR}/canonical-sdlc" && pwd -P)"

echo ""
echo "========================================"
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
echo "========================================"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
