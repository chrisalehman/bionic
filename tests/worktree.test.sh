#!/bin/bash
# WORKTREE — bionic 1.4.0 wave, slice WORKTREE (spec AC-11, AC-28; design ledger
# C1 "worktree lease", C2 ".bionic symlink retired").
#
# WHAT THIS SUITE OWNS. One payload library:
#
#   payload/scripts/lib/worktree.sh   the lease: land, legacy links, overruns
#
# WHY A LIBRARY AND NOT THE SCRIPT. Three callers need the same three answers —
# `spawn-worktree.sh land`, `hooks/stop-orders.sh standdown`, and the Patrol
# tick's lease-overrun line. A copy in each is three definitions of "discharged"
# and three definitions of "a suite is running", which is the divergence class
# this repo keeps paying for. The verb in spawn-worktree.sh is a two-line call
# site; the behaviour is here, and so are its tests.
#
# HERMETIC. No network, no `claude` CLI, no contact with the bionic checkout
# this suite runs inside beyond sourcing the library under test. Every git
# command is `-C <fixture>` or inside a subshell that has cd'd into one; global
# and system git config are pointed at /dev/null. The session files the D1
# predicate reads come from a fixture claude-home reached through
# BIONIC_CLAUDE_HOME — the knob payload/scripts/lib/patrol.sh already uses for
# exactly this directory, so there is one override chain and not two.
#
# THE SUITE-RUNNING ARM STARTS ITS OWN PROCESS. D1 is a conjunction: a busy
# session in this project AND a live `tests/run.sh`. This suite is itself run BY
# tests/run.sh, so the process half is ambient-true there and ambient-false
# standalone. A test that relied on the ambient answer would pass for a
# different reason in each mode, so the positive arm spawns a real script at
# <fixture>/tests/run.sh and the negative arms turn the session half off.
#
# BOTH ARMS, ALWAYS. Every refusal is asserted against the matching acceptance.
#
# Usage: bash tests/worktree.test.sh
# Registered by name in tests/run.sh (tests/*.test.sh is NOT auto-globbed).

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"

REPO="${BIONIC_SCRIPTS_DIR}"
LIB="${REPO}/payload/scripts/lib/worktree.sh"
SPAWN="${REPO}/payload/scripts/spawn-worktree.sh"

PASS=0; FAIL=0; TOTAL=0
ok() { TOTAL=$((TOTAL + 1)); PASS=$((PASS + 1)); echo "PASS: $1"; }
no() { TOTAL=$((TOTAL + 1)); FAIL=$((FAIL + 1)); echo "FAIL: $1"; [ -n "${2:-}" ] && echo "      $2"; return 0; }

expect_eq() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "expected '$2', got '$3'"; fi; }
expect_true() { local label="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$label"; else no "$label"; fi; }
expect_false() { local label="$1"; shift; if "$@" >/dev/null 2>&1; then no "$label" "expected non-zero exit"; else ok "$label"; fi; }
# No `printf | grep -q`: that is a SIGPIPE race under pipefail.
expect_match() {
  local label="$1" pattern="$2" actual="$3"
  # shellcheck disable=SC2053  # RHS is a glob on purpose
  if [[ "$actual" == $pattern ]]; then ok "$label"; else no "$label" "'$actual' does not match '$pattern'"; fi
}

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null
export GIT_CONFIG_NOSYSTEM=1
export GIT_TERMINAL_PROMPT=0
export GIT_AUTHOR_NAME="Bionic Test" GIT_AUTHOR_EMAIL="test@example.invalid"
export GIT_COMMITTER_NAME="Bionic Test" GIT_COMMITTER_EMAIL="test@example.invalid"
unset GIT_DIR GIT_WORK_TREE 2>/dev/null || true

# An EMPTY fixture claude-home by default: no session file means the D1
# predicate's session half is false, so every test that is not about D1 gets a
# deterministic "no suite running" regardless of what the real machine is doing.
CLAUDE_HOME="$TMP/claude-home"; mkdir -p "$CLAUDE_HOME/sessions"
export BIONIC_CLAUDE_HOME="$CLAUDE_HOME"

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
  ( cd "$d" && pwd -P )
}

# A tree with one commit of its own beyond the main checkout's branch, which is
# what "there is something to land" means.
new_tree() {  # <repo> <branch> [content] -> echoes the worktree path
  local r="$1" b="$2" c="${3:-work}"
  git -C "$r" worktree add --quiet -b "$b" "$r/.worktrees/${b##*/}" HEAD >/dev/null 2>&1
  echo "$c" > "$r/.worktrees/${b##*/}/${b##*/}.txt"
  git -C "$r/.worktrees/${b##*/}" add -A >/dev/null 2>&1
  git -C "$r/.worktrees/${b##*/}" commit --quiet -m "$b work"
  printf '%s' "$r/.worktrees/${b##*/}"
}

# shellcheck source=/dev/null
. "$LIB" 2>/dev/null || { echo "FAIL: the library does not source ($LIB)"; exit 1; }

echo "=== Group 1: the library exists and parses ==="

expect_true "worktree.sh passes bash -n" bash -n "$LIB"
expect_true "worktree_legacy_links is defined"    declare -f worktree_legacy_links
expect_true "worktree_land is defined"            declare -f worktree_land

echo ""
echo "=== Group 2: worktree_legacy_links — what C2 retired, listed ==="
#
# The link is gone from `create`, so the only ones left on a machine are the
# ones an older bionic planted. Listing them is how doctor and the SessionStart
# block report a footprint this version no longer makes.

L1="$(new_repo "$TMP/legacy")"
T1="$(new_tree "$L1" alpha)"
T2="$(new_tree "$L1" beta)"
expect_eq "a tree farm with no links lists nothing" "" "$(worktree_legacy_links "$L1")"
ln -s "${L1}/.bionic" "${T1}/.bionic"
expect_eq "one planted link is listed by absolute path" "${T1}/.bionic" "$(worktree_legacy_links "$L1")"
ln -s "${L1}/.bionic" "${T2}/.bionic"
expect_eq "two links are listed, one per line" "2" "$(worktree_legacy_links "$L1" | grep -c .)"
# A real `.bionic` DIRECTORY in a tree is not a legacy link and must never be
# offered up for deletion: the difference between `rm -f <link>` and losing a
# writer's state directory is this test.
mkdir -p "${L1}/.worktrees/beta-dir/.bionic"
expect_eq "a real .bionic directory is not listed as a legacy link" \
  "2" "$(worktree_legacy_links "$L1" | grep -c .)"
expect_eq "a repo with no .worktrees at all lists nothing" "" \
  "$(worktree_legacy_links "$(new_repo "$TMP/nofarm")")"

echo ""
echo "=== Group 3: worktree_land — the happy path is ONE act ==="
#
# C1: the lease ends with a merge, a removal and a prune, and a land that did
# two of the three is a lease half-ended. Every field of the LANDED line is
# re-derived from git rather than read off the line.

H="$(new_repo "$TMP/land-ok")"
HT="$(new_tree "$H" alpha)"
HBEFORE="$(git -C "$H" rev-parse HEAD)"
OUTH="$(worktree_land "$HT")"
RCH=$?

expect_match "land reports LANDED with branch, merge and path" \
  "spawn-worktree: LANDED branch=alpha merge=* removed=${HT}" "$OUTH"
expect_eq   "land exits 0"                       "0" "$RCH"
expect_false "the worktree directory is gone"    test -d "$HT"
expect_eq   "git's registry no longer lists it"  "1" "$(git -C "$H" worktree list | grep -c .)"
expect_true "the BRANCH survives the landing"    git -C "$H" show-ref --verify --quiet refs/heads/alpha
expect_eq   "the main checkout moved"            "1" \
  "$([ "$(git -C "$H" rev-parse HEAD)" != "$HBEFORE" ] && echo 1 || echo 0)"
expect_eq   "the merge is a --no-ff merge commit (two parents)" "2" \
  "$(git -C "$H" rev-list --parents -n1 HEAD | wc -w | tr -d ' ' | awk '{print $1-1}')"
expect_eq   "the merge message names the branch and the verb" "merge alpha (land)" \
  "$(git -C "$H" log -1 --pretty=%s)"
expect_eq   "the branch is now an ancestor of the main checkout" "0" \
  "$(git -C "$H" rev-list --count HEAD..alpha)"
expect_eq   "the merge= field is the commit git actually made" \
  "$(git -C "$H" rev-parse HEAD)" "$(printf '%s' "$OUTH" | tr ' ' '\n' | grep '^merge=' | cut -d= -f2)"
# The landing goes onto the main checkout's CURRENT branch, whatever that is.
git -C "$H" checkout --quiet -b other-line
HT2="$(new_tree "$H" beta)"
worktree_land "$HT2" >/dev/null
expect_eq "the landing went onto the branch the main checkout was on" "other-line" \
  "$(git -C "$H" rev-parse --abbrev-ref HEAD)"
expect_eq "and beta is an ancestor of it" "0" "$(git -C "$H" rev-list --count HEAD..beta)"

echo ""
echo "=== Group 4: worktree_land — the refusals, each naming why ==="
#
# BOTH ARMS. Every refusal below is asserted against a world where the same
# call lands, so a land that refused everything could not pass this group.

D="$(new_repo "$TMP/land-refuse")"

# Dirty. git's own refusal to discard uncommitted work is the feature; the
# lease never forces.
DT="$(new_tree "$D" dirty)"
echo "unsaved" >> "${DT}/file.txt"
OUTD="$(worktree_land "$DT")"; RCD=$?
expect_match "a dirty tree is refused, naming dirtiness" "spawn-worktree: REFUSED reason=dirty-tree*" "$OUTD"
expect_eq   "the refusal exits 2"              "2" "$RCD"
expect_true "the refused tree is still there"  test -d "$DT"
expect_eq   "nothing was merged"               "1" "$(git -C "$D" rev-list --count HEAD..dirty)"
git -C "$DT" checkout --quiet -- file.txt
expect_match "the same tree lands once it is clean (the arm discriminates)" \
  "spawn-worktree: LANDED *" "$(worktree_land "$DT")"

# An UNTRACKED file is uncommitted work too, and losing it to a lease is the
# accident this refusal exists for.
UT="$(new_tree "$D" untracked)"
echo scratch > "${UT}/notes.txt"
expect_match "an untracked file counts as dirty" "spawn-worktree: REFUSED reason=dirty-tree*" \
  "$(worktree_land "$UT")"

# Nothing to land. A tree whose branch is not ahead of the main checkout has no
# work to merge, and a --no-ff merge of it would be a lie in the history.
NT="$(new_tree "$D" nothing)"
git -C "$D" merge --quiet --no-ff -m "already merged" nothing
OUTN="$(worktree_land "$NT")"; RCN=$?
expect_match "an already-merged branch is refused" "spawn-worktree: REFUSED reason=nothing-to-land*" "$OUTN"
expect_eq   "that refusal exits 2"   "2" "$RCN"
expect_true "its tree is still there" test -d "$NT"
NT2="$(new_tree "$D" fresh-only)"
expect_match "a branch with a commit of its own lands (the arm discriminates)" \
  "spawn-worktree: LANDED *" "$(worktree_land "$NT2")"

# Not a linked worktree. Being handed the MAIN checkout to land is the mistake
# with the worst outcome, so it is refused on the same `.git`-is-a-file test
# `remove` uses.
expect_match "the main checkout is refused" "spawn-worktree: REFUSED reason=not-a-linked-worktree*" \
  "$(worktree_land "$D")"
expect_match "a path that is no worktree at all is refused" "spawn-worktree: REFUSED reason=no-such-worktree*" \
  "$(worktree_land "${D}/.worktrees/never-existed")"
expect_match "no path at all is refused" "spawn-worktree: REFUSED reason=no-such-worktree*" \
  "$(worktree_land)"

echo ""
echo "=== Group 5: worktree_land — D1, never land under a running suite ==="
#
# D1 is a CONJUNCTION: a `busy` session whose cwd is this project or a linked
# worktree of it, AND a live `tests/run.sh`. This suite is itself run by
# tests/run.sh, so the process half is ambient-true there and ambient-false
# standalone; the arms below spawn their own so the answer is the same in both
# modes, and turn the SESSION half on and off to discriminate.

S="$(new_repo "$TMP/land-busy")"
FAKESUITE="$TMP/fakeproj/tests"; mkdir -p "$FAKESUITE"
printf '#!/bin/bash\nsleep 120\n' > "$FAKESUITE/run.sh"; chmod +x "$FAKESUITE/run.sh"
bash "$FAKESUITE/run.sh" >/dev/null 2>&1 & SUITE_PID=$!
trap 'kill "$SUITE_PID" 2>/dev/null; rm -rf "$TMP"' EXIT
# Give the process a moment to be visible to pgrep before anything asks.
i=0; while [ $i -lt 50 ] && ! pgrep -f 'tests/run.sh' >/dev/null 2>&1; do i=$((i+1)); done

session_file() {  # <pid> <cwd> <status> <name>
  printf '{"pid":%s,"sessionId":"fixture-%s","cwd":"%s","status":"%s","name":"%s","kind":"interactive"}\n' \
    "$1" "$4" "$2" "$3" "$4" > "$CLAUDE_HOME/sessions/$1.json"
}

BT="$(new_tree "$S" busy-arm)"

# Arm 1 — a busy session in the project, suite alive: refused, naming it.
session_file "$SUITE_PID" "$S" busy W-PEER
OUTB="$(worktree_land "$BT")"; RCB=$?
expect_match "a busy session in this project refuses the land" \
  "spawn-worktree: REFUSED reason=suite-running*" "$OUTB"
expect_match "and the refusal NAMES the session" "*session=W-PEER*" "$OUTB"
expect_match "and its pid" "*pid=${SUITE_PID}*" "$OUTB"
expect_eq    "the refusal exits 2" "2" "$RCB"
expect_true  "the tree survives the refusal" test -d "$BT"

# Arm 2 — the same world with the session IDLE: the conjunction is false.
session_file "$SUITE_PID" "$S" idle W-PEER
expect_match "an idle session does not refuse (the status half discriminates)" \
  "spawn-worktree: LANDED *" "$(worktree_land "$BT")"

# Arm 3 — busy again, but the session is working in ANOTHER project.
BT3="$(new_tree "$S" other-project)"
session_file "$SUITE_PID" "$TMP/somewhere-else" busy W-STRANGER
expect_match "a busy session in a different project does not refuse" \
  "spawn-worktree: LANDED *" "$(worktree_land "$BT3")"

# Arm 4 — a busy session in a LINKED WORKTREE of this project counts as this
# project: that is where a writer running a suite actually sits.
BT4="$(new_tree "$S" from-a-tree)"
session_file "$SUITE_PID" "$BT4" busy W-INTREE
expect_match "a busy session inside one of the project's own trees refuses" \
  "spawn-worktree: REFUSED reason=suite-running*" "$(worktree_land "$BT4")"

# Arm 5 — a busy session whose PROCESS IS GONE is not a running suite. A stale
# session file outlives its process routinely, and a lease that could never end
# on a machine carrying one is worse than no lease.
DEADPID=$(bash -c 'echo $$')
while kill -0 "$DEADPID" 2>/dev/null; do :; done
rm -f "$CLAUDE_HOME/sessions/${SUITE_PID}.json"
session_file "$DEADPID" "$S" busy W-GHOST
expect_match "a busy session whose process is dead does not refuse" \
  "spawn-worktree: LANDED *" "$(worktree_land "$BT4")"
rm -f "$CLAUDE_HOME/sessions/${DEADPID}.json"

echo ""
echo "=== Group 6: worktree_land — the legacy link, and the branch, and prune ==="

G="$(new_repo "$TMP/land-legacy")"
GT="$(new_tree "$G" legacy-arm)"
ln -s "${G}/.bionic" "${GT}/.bionic"
OUTG="$(worktree_land "$GT")"
expect_match "a tree carrying a legacy link still lands" "spawn-worktree: LANDED *" "$OUTG"
expect_false "the tree is gone"  test -d "$GT"
expect_true  "the state directory the link pointed at is intact" \
  test -f "${G}/.bionic/docs/note.md"
# Prune: git keeps administrative files under .git/worktrees until pruned, and
# a lease that left them behind would keep counting a slot nobody holds.
expect_eq "no stale administrative entry survives the landing" "0" \
  "$(ls "${G}/.git/worktrees" 2>/dev/null | grep -c .)"

echo ""
echo "=== Group 7: the land VERB — spawn-worktree.sh land <path> ==="
#
# The verb is a call site, not a second implementation: what is asserted here
# is the wiring and the exit codes a caller reads.

V="$(new_repo "$TMP/verb")"
VT="$(new_tree "$V" verb-arm)"
OUTV="$( cd "$V" && bash "$SPAWN" land "$VT" 2>/dev/null )"
expect_match "the verb prints the LANDED line" "spawn-worktree: LANDED branch=verb-arm *" "$OUTV"
expect_false "the tree is gone" test -d "$VT"

VD="$(new_tree "$V" verb-dirty)"
echo x >> "${VD}/file.txt"
RCV="$( cd "$V" && bash "$SPAWN" land "$VD" >/dev/null 2>&1; echo $? )"
expect_eq "a refused land exits 2" "2" "$RCV"
expect_match "land with no path is refused" "spawn-worktree: REFUSED *" \
  "$( cd "$V" && bash "$SPAWN" land 2>/dev/null )"
expect_true "the usage text names the land verb" \
  grep -q 'spawn-worktree.sh land' "$SPAWN"

echo ""
echo "========================================"
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
echo "========================================"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
