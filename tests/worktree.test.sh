#!/bin/bash
# WORKTREE — bionic 1.4.0 wave, task WORKTREE (spec AC-11, AC-28; design ledger
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

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"
. "$(dirname "$0")/lib/roster-row.sh"

REPO="${BIONIC_SCRIPTS_DIR}"
LIB="${REPO}/payload/scripts/lib/worktree.sh"
SPAWN="${REPO}/payload/scripts/spawn-worktree.sh"

# expect_true, expect_false, expect_match are the framework's (tests/lib/assert.sh)
# — S9b removed the private shadows here (AC-12); expect_match's glob semantics
# and argument order (`<label> <glob> <actual>`) were already identical, so
# every call site below binds unchanged.

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

# The fixture is a repository that HAS a `main` — so a test can check it out and
# watch the wall refuse — but that is not SITTING on it. A wave's main checkout
# sits on the wave branch, which since F1 is the only state in which a land is
# allowed at all; a fixture left on `main` would be a fixture in a permanently
# refused state and every landing assertion below would pass for the wrong
# reason.
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
  git -C "$d" checkout --quiet -b wave/fixture
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

# A BOUND PLAN (wave-20 T8, REQ-1, D1). The engaged marker names a plan, in the shape
# payload/scripts/lib/binding.sh writes it, and the plan's frontmatter carries
# `working-branch:` — or does not, when <working-branch> is empty. The plan is an OPEN run
# (`## SDLC State`, `current: 4`) under the docs root, so the same file doubles as the root's
# newest open run for the unbound `fallback` arm.
bind_plan() {  # <repo> <sid> <working-branch or empty> -> echoes the plan path
  local r="$1" sid="$2" wb="$3" p
  p="$r/.bionic/docs/plans/epic-x/wave-x.plan.md"
  mkdir -p "${p%/*}" "$r/.bionic/tmp"
  {
    printf -- '---\n'
    if [ -n "$wb" ]; then printf 'working-branch: %s\n' "$wb"; fi
    printf -- '---\n# fixture plan\n\n## SDLC State\n\ncurrent: 4\n'
  } > "$p"
  printf 'plan=%s\nengaged_at=2026-09-23T00:00:00Z\n' "$p" > "$r/.bionic/tmp/engaged-${sid}.state"
  printf '%s' "$p"
}

# Every ref and its object, one line each: a refused land changes NONE of them, which is
# "no merge commit anywhere" read off git rather than off the refusal line.
refs_of() { git -C "$1" for-each-ref --format='%(refname) %(objectname)'; }

# shellcheck source=/dev/null
. "$LIB" 2>/dev/null || { echo "FAIL: the library does not source ($LIB)"; exit 1; }

section "Group 1: the library exists and parses"

expect_true "worktree.sh passes bash -n" bash -n "$LIB"
expect_true "worktree_legacy_links is defined"    declare -f worktree_legacy_links
expect_true "worktree_land is defined"            declare -f worktree_land
expect_true "worktree_land_for_session is defined" declare -f worktree_land_for_session
expect_true "worktree_checkout_of is defined"     declare -f worktree_checkout_of
expect_true "worktree_lease_overruns is defined"  declare -f worktree_lease_overruns

section "Group 2: worktree_legacy_links — D7: only a MIS-POINTED link is listed"
#
# D7 (wave-13-fixit-180, reopens C2): `create` plants
# `<wt>/.bionic -> <main-root>/.bionic` again. A link resolving there is the
# expected, constructive state and is never listed; only a link some other
# bionic version — or some other hand — pointed SOMEWHERE ELSE is stale.

L1="$(new_repo "$TMP/legacy")"
T1="$(new_tree "$L1" alpha)"
T2="$(new_tree "$L1" beta)"
expect_eq "a tree farm with no links lists nothing" "" "$(worktree_legacy_links "$L1")"

# A CORRECTLY-POINTING alias — exactly what create plants — is never listed.
ln -s "${L1}/.bionic" "${T1}/.bionic"
expect_eq "a link resolving to the main root's .bionic is not listed" \
  "" "$(worktree_legacy_links "$L1")"

# A MIS-POINTED link — pointing anywhere else — IS listed.
MISDIR="$TMP/elsewhere-legacy"; mkdir -p "$MISDIR"
ln -s "$MISDIR" "${T2}/.bionic"
expect_eq "a link pointing elsewhere is listed by absolute path" \
  "${T2}/.bionic" "$(worktree_legacy_links "$L1")"

# A BROKEN link (target does not exist) certainly does not resolve to the
# main root's .bionic either, so it is listed too.
T3="$(new_tree "$L1" gamma)"
ln -s "${L1}/.bionic-does-not-exist" "${T3}/.bionic"
expect_eq "the correctly-pointing alias plus two stale/broken links: two listed" \
  "2" "$(worktree_legacy_links "$L1" | grep -c .)"

# A real `.bionic` DIRECTORY in a tree is not a legacy link and must never be
# offered up for deletion: the difference between `rm -f <link>` and losing a
# writer's state directory is this test.
mkdir -p "${L1}/.worktrees/beta-dir/.bionic"
expect_eq "a real .bionic directory is not listed as a legacy link" \
  "2" "$(worktree_legacy_links "$L1" | grep -c .)"
expect_eq "a repo with no .worktrees at all lists nothing" "" \
  "$(worktree_legacy_links "$(new_repo "$TMP/nofarm")")"

section "Group 3: worktree_land — the happy path is ONE act"
#
# C1: the lease ends with a merge, a removal and a prune, and a land that did
# two of the three is a lease half-ended. Every field of the LANDED line is
# re-derived from git rather than read off the line.

H="$(new_repo "$TMP/land-ok")"
HT="$(new_tree "$H" alpha)"
HBEFORE="$(git -C "$H" rev-parse HEAD)"
OUTH="$(worktree_land "$HT" wave/fixture)"
RCH=$?

expect_match "land reports LANDED with branch, target, checkout, merge and path" \
  "spawn-worktree: LANDED branch=alpha onto=wave/fixture checkout=${H} merge=* removed=${HT}" "$OUTH"
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
# The landing goes onto the branch NAMED, in the checkout that holds it (T8, D1).
git -C "$H" checkout --quiet -b other-line
HT2="$(new_tree "$H" beta)"
worktree_land "$HT2" other-line >/dev/null
expect_eq "the landing went onto the named branch, which the main checkout holds" "other-line" \
  "$(git -C "$H" rev-parse --abbrev-ref HEAD)"
expect_eq "and beta is an ancestor of it" "0" "$(git -C "$H" rev-list --count HEAD..beta)"

section "Group 3b: worktree_land — §land-with-alias (D7)"
#
# D7 plants the alias `create` now leaves in every spawned tree. A tree whose
# ONLY untracked entry is that alias must land exactly as it always did — the
# dirty-tree check reads `.gitignore:43`'s `.bionic` entry, unaffected by
# whether it names a directory or a symlink — and `_wt_drop_legacy_link`
# already deletes the link on the way in, before the dirty check runs.

LA="$(new_repo "$TMP/land-alias")"
LAT="$(new_tree "$LA" withalias)"
ln -s "${LA}/.bionic" "${LAT}/.bionic"
expect_true "the alias is present before land, and IS a symlink" test -L "${LAT}/.bionic"
expect_eq "the tree is clean despite the alias (gitignored either shape)" \
  "" "$(git -C "$LAT" status --porcelain)"
OUTLA="$(worktree_land "$LAT" wave/fixture)"
expect_match "a tree whose only untracked entry is the alias lands" \
  "spawn-worktree: LANDED branch=withalias onto=wave/fixture checkout=${LA} merge=* removed=${LAT}" "$OUTLA"
expect_false "the tree — alias included — is gone after landing" test -e "$LAT"
expect_true "the state directory the alias pointed at survived" \
  test -f "${LA}/.bionic/docs/note.md"

section "Group 4: worktree_land — the refusals, each naming why"
#
# BOTH ARMS. Every refusal below is asserted against a world where the same
# call lands, so a land that refused everything could not pass this group.

D="$(new_repo "$TMP/land-refuse")"

# Dirty. git's own refusal to discard uncommitted work is the feature; the
# lease never forces.
DT="$(new_tree "$D" dirty)"
echo "unsaved" >> "${DT}/file.txt"
OUTD="$(worktree_land "$DT" wave/fixture)"; RCD=$?
expect_match "a dirty tree is refused, naming dirtiness" "spawn-worktree: REFUSED reason=dirty-tree*" "$OUTD"
expect_eq   "the refusal exits 2"              "2" "$RCD"
expect_true "the refused tree is still there"  test -d "$DT"
expect_eq   "nothing was merged"               "1" "$(git -C "$D" rev-list --count HEAD..dirty)"
git -C "$DT" checkout --quiet -- file.txt
expect_match "the same tree lands once it is clean (the arm discriminates)" \
  "spawn-worktree: LANDED *" "$(worktree_land "$DT" wave/fixture)"

# An UNTRACKED file is uncommitted work too, and losing it to a lease is the
# accident this refusal exists for.
UT="$(new_tree "$D" untracked)"
echo scratch > "${UT}/notes.txt"
expect_match "an untracked file counts as dirty" "spawn-worktree: REFUSED reason=dirty-tree*" \
  "$(worktree_land "$UT" wave/fixture)"

# Nothing to land. A tree whose branch is not ahead of the main checkout has no
# work to merge, and a --no-ff merge of it would be a lie in the history.
NT="$(new_tree "$D" nothing)"
git -C "$D" merge --quiet --no-ff -m "already merged" nothing
OUTN="$(worktree_land "$NT" wave/fixture)"; RCN=$?
expect_match "an already-merged branch is refused" "spawn-worktree: REFUSED reason=nothing-to-land*" "$OUTN"
expect_eq   "that refusal exits 2"   "2" "$RCN"
expect_true "its tree is still there" test -d "$NT"
NT2="$(new_tree "$D" fresh-only)"
expect_match "a branch with a commit of its own lands (the arm discriminates)" \
  "spawn-worktree: LANDED *" "$(worktree_land "$NT2" wave/fixture)"

# Not a linked worktree. Being handed the MAIN checkout to land is the mistake
# with the worst outcome, so it is refused on the same `.git`-is-a-file test
# `remove` uses.
expect_match "the main checkout is refused" "spawn-worktree: REFUSED reason=not-a-linked-worktree*" \
  "$(worktree_land "$D" wave/fixture)"
expect_match "a path that is no worktree at all is refused" "spawn-worktree: REFUSED reason=no-such-worktree*" \
  "$(worktree_land "${D}/.worktrees/never-existed" wave/fixture)"
expect_match "no path at all is refused" "spawn-worktree: REFUSED reason=no-such-worktree*" \
  "$(worktree_land)"

# NO TARGET, NO LAND (T8, D1). The branch merged into is the caller's to NAME — the plan's
# working branch, through worktree_land_for_session — and never read off whatever the main
# checkout happens to sit on. A land with no target refuses before anything is touched.
OT="$(new_tree "$D" no-onto)"
OBEFORE="$(refs_of "$D")"
OUTO="$(worktree_land "$OT")"; RCO=$?
expect_match "a land naming no target is refused, naming why" \
  "spawn-worktree: REFUSED reason=onto-missing*" "$OUTO"
expect_eq   "that refusal exits 2"            "2" "$RCO"
expect_true "the tree survives"               test -d "$OT"
expect_eq   "no ref moved"                    "$OBEFORE" "$(refs_of "$D")"
expect_match "the same tree lands once a target is named (the arm discriminates)" \
  "spawn-worktree: LANDED branch=no-onto onto=wave/fixture *" "$(worktree_land "$OT" wave/fixture)"

section "Group 4b: worktree_land — the two SCOPE refusals (security F1)"
#
# `land` merges into whatever branch the main checkout is on and removes
# whatever linked worktree it is handed. Two facts bound that power, and both
# are checked BEFORE anything is touched — before even the legacy-link deletion
# Group 6 covers, which is the one mutation the refusal order otherwise lets
# through.
#
#   1. The branch merged INTO is never a protected branch. hooks/protect-main.sh
#      reads `git push` argv and never sees a merge, so a land onto `main` was
#      the one way unreviewed work reached that branch with no wall in the path.
#   2. The tree landed is under `<main-root>/.worktrees/`. That is the only
#      place this lease ever hands one out, so any other linked worktree of the
#      same repository is somebody else's and is refused rather than merged and
#      deleted.

P="$(new_repo "$TMP/land-scope")"

# --- 1. the protected branch ---------------------------------------------
PT="$(new_tree "$P" onto-main)"
git -C "$P" checkout --quiet main
PBEFORE="$(git -C "$P" rev-parse HEAD)"
OUTP="$(worktree_land "$PT" main)"; RCP=$?
expect_match "landing while the main checkout is on main is refused, naming the branch" \
  "spawn-worktree: REFUSED reason=protected-branch branch=main*" "$OUTP"
expect_eq   "that refusal exits 2"          "2" "$RCP"
expect_true "the tree survives the refusal" test -d "$PT"
expect_eq   "main did not move"             "$PBEFORE" "$(git -C "$P" rev-parse HEAD)"
expect_eq   "nothing was merged"            "1" "$(git -C "$P" rev-list --count HEAD..onto-main)"
# `main` here is still the fixture's root commit, so a parent count of 0 is
# both "it did not move" said a second way and "it is not a merge commit".
expect_eq   "the protected branch's HEAD is not a merge commit" "0" \
  "$(git -C "$P" rev-list --parents -n1 HEAD | wc -w | tr -d ' ' | awk '{print $1-1}')"

# master is the same branch under its other name.
git -C "$P" checkout --quiet -b master
expect_match "master is refused too" "spawn-worktree: REFUSED reason=protected-branch branch=master*" \
  "$(worktree_land "$PT" master)"

# THE ARM DISCRIMINATES: the same tree, the same call, a wave branch checked out.
git -C "$P" checkout --quiet wave/fixture
expect_match "the same tree lands once the checkout is off the protected branch" \
  "spawn-worktree: LANDED branch=onto-main *" "$(worktree_land "$PT" wave/fixture)"

# A branch whose NAME merely contains the word is its own branch and is landable:
# the list is matched whole, exactly as hooks/protect-main.sh matches it.
git -C "$P" checkout --quiet -b topic/main
PT2="$(new_tree "$P" near-miss)"
expect_match "a branch named topic/main is not protected" "spawn-worktree: LANDED branch=near-miss *" \
  "$(worktree_land "$PT2" topic/main)"
git -C "$P" checkout --quiet wave/fixture

# --- 2. the tree outside .worktrees/ --------------------------------------
# A linked worktree of the SAME repository, parked somewhere else entirely —
# which `spawn-worktree.sh create` will make when handed an absolute parent, and
# which the lease never hands out.
OUTSIDE="$TMP/outside-trees"; mkdir -p "$OUTSIDE"; OUTSIDE="$(cd "$OUTSIDE" && pwd -P)"
git -C "$P" worktree add --quiet -b stranger "${OUTSIDE}/stranger" HEAD >/dev/null 2>&1
echo work > "${OUTSIDE}/stranger/stranger.txt"
git -C "${OUTSIDE}/stranger" add -A >/dev/null 2>&1
git -C "${OUTSIDE}/stranger" commit --quiet -m "stranger work"

XBEFORE="$(git -C "$P" rev-parse HEAD)"
OUTX="$(worktree_land "${OUTSIDE}/stranger" wave/fixture)"; RCX=$?
expect_match "a tree outside <root>/.worktrees/ is refused, naming the path and the root" \
  "spawn-worktree: REFUSED reason=outside-worktrees path=${OUTSIDE}/stranger root=${P}" "$OUTX"
expect_eq   "that refusal exits 2"             "2" "$RCX"
expect_true "the outside tree survives"        test -d "${OUTSIDE}/stranger"
expect_eq   "the main checkout did not move"   "$XBEFORE" "$(git -C "$P" rev-parse HEAD)"
expect_eq   "its branch was not merged"        "1" "$(git -C "$P" rev-list --count HEAD..stranger)"

# THE ARM DISCRIMINATES: an otherwise identical tree, under .worktrees/.
PT3="$(new_tree "$P" insider)"
expect_match "the same shape of tree lands when it is under .worktrees/" \
  "spawn-worktree: LANDED branch=insider *" "$(worktree_land "$PT3" wave/fixture)"

# A directory whose name merely STARTS with the farm's is a sibling, not a tree
# of the lease: the test is on the path SEGMENT, not on the prefix string.
mkdir -p "${P}/.worktrees-decoy"
git -C "$P" worktree add --quiet -b decoy "${P}/.worktrees-decoy/decoy" HEAD >/dev/null 2>&1
echo d > "${P}/.worktrees-decoy/decoy/d.txt"
git -C "${P}/.worktrees-decoy/decoy" add -A >/dev/null 2>&1
git -C "${P}/.worktrees-decoy/decoy" commit --quiet -m "decoy work"
expect_match "a sibling directory sharing the prefix is outside too" \
  "spawn-worktree: REFUSED reason=outside-worktrees*" "$(worktree_land "${P}/.worktrees-decoy/decoy" wave/fixture)"

# The scope refusal comes BEFORE the legacy-link deletion, so a refused land
# leaves an out-of-scope tree exactly as it found it — link included.
ln -s "${P}/.bionic" "${OUTSIDE}/stranger/.bionic"
worktree_land "${OUTSIDE}/stranger" wave/fixture >/dev/null
expect_true "a refused out-of-scope land does not even drop the legacy link" \
  test -L "${OUTSIDE}/stranger/.bionic"

section "Group 5: worktree_land — D1, never land under a running suite"
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
OUTB="$(worktree_land "$BT" wave/fixture)"; RCB=$?
expect_match "a busy session in this project refuses the land" \
  "spawn-worktree: REFUSED reason=suite-running*" "$OUTB"
expect_match "and the refusal NAMES the session" "*session=W-PEER*" "$OUTB"
expect_match "and its pid" "*pid=${SUITE_PID}*" "$OUTB"
expect_eq    "the refusal exits 2" "2" "$RCB"
expect_true  "the tree survives the refusal" test -d "$BT"

# Arm 2 — the same world with the session IDLE: the conjunction is false.
session_file "$SUITE_PID" "$S" idle W-PEER
expect_match "an idle session does not refuse (the status half discriminates)" \
  "spawn-worktree: LANDED *" "$(worktree_land "$BT" wave/fixture)"

# Arm 3 — busy again, but the session is working in ANOTHER project.
BT3="$(new_tree "$S" other-project)"
session_file "$SUITE_PID" "$TMP/somewhere-else" busy W-STRANGER
expect_match "a busy session in a different project does not refuse" \
  "spawn-worktree: LANDED *" "$(worktree_land "$BT3" wave/fixture)"

# Arm 4 — a busy session in a LINKED WORKTREE of this project counts as this
# project: that is where a writer running a suite actually sits.
BT4="$(new_tree "$S" from-a-tree)"
session_file "$SUITE_PID" "$BT4" busy W-INTREE
expect_match "a busy session inside one of the project's own trees refuses" \
  "spawn-worktree: REFUSED reason=suite-running*" "$(worktree_land "$BT4" wave/fixture)"

# Arm 5 — a busy session whose PROCESS IS GONE is not a running suite. A stale
# session file outlives its process routinely, and a lease that could never end
# on a machine carrying one is worse than no lease.
DEADPID=$(bash -c 'echo $$')
while kill -0 "$DEADPID" 2>/dev/null; do :; done
rm -f "$CLAUDE_HOME/sessions/${SUITE_PID}.json"
session_file "$DEADPID" "$S" busy W-GHOST
expect_match "a busy session whose process is dead does not refuse" \
  "spawn-worktree: LANDED *" "$(worktree_land "$BT4" wave/fixture)"
rm -f "$CLAUDE_HOME/sessions/${DEADPID}.json"

# Arm 6 — THE TARGET CHECKOUT IS WHERE THE MERGE HAPPENS (T8, D1), so a busy session sitting
# in it refuses even when that checkout lives OUTSIDE the project root, which
# `spawn-worktree.sh create` allows with an absolute parent. The check is widened to the
# target, never narrowed.
SWAVE="$TMP/outside-wave"
git -C "$S" worktree add --quiet -b wave/out "$SWAVE" wave/fixture >/dev/null 2>&1
SWAVE="$(cd "$SWAVE" && pwd -P)"
BT6="$(new_tree "$S" into-outside)"
session_file "$SUITE_PID" "$SWAVE" busy W-OUTWAVE
OUTB6="$(worktree_land "$BT6" wave/out)"; RCB6=$?
expect_match "a busy session in the TARGET checkout, outside the root, refuses" \
  "spawn-worktree: REFUSED reason=suite-running*session=W-OUTWAVE*" "$OUTB6"
expect_eq    "that refusal exits 2" "2" "$RCB6"
session_file "$SUITE_PID" "$SWAVE" idle W-OUTWAVE
expect_match "the same land goes through once that session is idle (the arm discriminates)" \
  "spawn-worktree: LANDED branch=into-outside onto=wave/out checkout=${SWAVE} *" \
  "$(worktree_land "$BT6" wave/out)"

# Arm 7 — THE LANDING SESSION NEVER COUNTS AGAINST ITSELF (wave-20 T8b, review R8/F3). D1
# used to be `busy session in project` AND `a live tests/run.sh`, full stop — and the
# session running the land is always busy and always in-project, so the conjunction
# collapsed to "any tests/run.sh anywhere" (T12's live bed named the drive's OWN session in
# a refusal). `worktree_land` takes the caller's own session id as an optional third
# argument (threaded from `worktree_land_for_session`'s `sid`, Group 7 below); a busy
# session file whose `sessionId` equals it is excluded from the predicate — the refusal for
# a suite this project has running under ANY OTHER session is unchanged (Arm 8).
BT7="$(new_tree "$S" self-arm)"
session_file "$SUITE_PID" "$S" busy W-SELF
expect_match "the lander's OWN busy session does not refuse its own land" \
  "spawn-worktree: LANDED *" "$(worktree_land "$BT7" wave/fixture "fixture-W-SELF")"

# Arm 8 — a DIFFERENT session's busy suite in this project still refuses: the exclusion is
# scoped to the caller's own identity, never a blanket suppression, because this refusal is
# the reason D1 exists in the first place.
BT8="$(new_tree "$S" other-session-arm)"
session_file "$SUITE_PID" "$S" busy W-PEER2
OUTB8="$(worktree_land "$BT8" wave/fixture "some-other-session-id")"; RCB8=$?
expect_match "a different session's busy suite in this project still refuses" \
  "spawn-worktree: REFUSED reason=suite-running*" "$OUTB8"
expect_eq    "that refusal exits 2" "2" "$RCB8"

# Arm 9 — no sid argument at all (the pre-T8b call shape, still valid): behaves exactly as
# before, refusing on any busy in-project session. Backward compatible on purpose — every
# existing 2-argument call site above (Arms 1-6) already proves this, this one just says so
# beside the arm that changed.
BT9="$(new_tree "$S" no-sid-arm)"
OUTB9="$(worktree_land "$BT9" wave/fixture)"; RCB9=$?
expect_match "no sid argument -> the busy session still refuses (unchanged default)" \
  "spawn-worktree: REFUSED reason=suite-running*" "$OUTB9"
expect_eq    "that refusal exits 2" "2" "$RCB9"

rm -f "$CLAUDE_HOME/sessions/${SUITE_PID}.json"

section "Group 6: worktree_land — the legacy link, and the branch, and prune"

G="$(new_repo "$TMP/land-legacy")"
GT="$(new_tree "$G" legacy-arm)"
ln -s "${G}/.bionic" "${GT}/.bionic"
OUTG="$(worktree_land "$GT" wave/fixture)"
expect_match "a tree carrying a legacy link still lands" "spawn-worktree: LANDED *" "$OUTG"
expect_false "the tree is gone"  test -d "$GT"
expect_true  "the state directory the link pointed at is intact" \
  test -f "${G}/.bionic/docs/note.md"
# Prune: git keeps administrative files under .git/worktrees until pruned, and
# a lease that left them behind would keep counting a slot nobody holds.
expect_eq "no stale administrative entry survives the landing" "0" \
  "$(ls "${G}/.git/worktrees" 2>/dev/null | grep -c .)"

section "Group 7: the land VERB — spawn-worktree.sh land <path>"
#
# The verb is a call site, not a second implementation: what is asserted here
# is the wiring and the exit codes a caller reads.

# THE VERB NAMES NO TARGET (T8, D1): the session's bound plan does, through
# worktree_land_for_session — the one path standdown calls too. So the verb runs with a
# session id, and that session is bound to a plan whose working branch the fixture holds.
V="$(new_repo "$TMP/verb")"
VSID="verb-session-0001"
bind_plan "$V" "$VSID" wave/fixture >/dev/null
VT="$(new_tree "$V" verb-arm)"
OUTV="$( cd "$V" && CLAUDE_CODE_SESSION_ID="$VSID" bash "$SPAWN" land "$VT" 2>/dev/null )"
expect_match "the verb lands onto the bound plan's working branch, naming it" \
  "spawn-worktree: LANDED branch=verb-arm onto=wave/fixture checkout=${V} *" "$OUTV"
expect_false "the tree is gone" test -d "$VT"

VD="$(new_tree "$V" verb-dirty)"
echo x >> "${VD}/file.txt"
RCV="$( cd "$V" && CLAUDE_CODE_SESSION_ID="$VSID" bash "$SPAWN" land "$VD" >/dev/null 2>&1; echo $? )"
expect_eq "a refused land exits 2" "2" "$RCV"
expect_match "land with no path is refused" "spawn-worktree: REFUSED *" \
  "$( cd "$V" && CLAUDE_CODE_SESSION_ID="$VSID" bash "$SPAWN" land 2>/dev/null )"

# No session id at all: there is no binding to read, so there is no target.
git -C "$VD" checkout --quiet -- file.txt
VBEFORE="$(refs_of "$V")"
OUTVN="$( cd "$V" && env -u CLAUDE_CODE_SESSION_ID bash "$SPAWN" land "$VD" 2>/dev/null )"; RCVN=$?
expect_match "the verb with no session id is refused, naming why" \
  "spawn-worktree: REFUSED reason=no-session*" "$OUTVN"
expect_eq   "that refusal exits 2" "2" "$RCVN"
expect_eq   "no ref moved" "$VBEFORE" "$(refs_of "$V")"
# A session that is not bound: the root's newest open run is somebody's, not this one's.
OUTVU="$( cd "$V" && CLAUDE_CODE_SESSION_ID="verb-unbound-0002" bash "$SPAWN" land "$VD" 2>/dev/null )"
expect_match "the verb from an unbound session is refused, naming the fallback" \
  "spawn-worktree: REFUSED reason=no-bound-plan state=fallback*" "$OUTVU"
expect_eq   "no ref moved" "$VBEFORE" "$(refs_of "$V")"
expect_match "the same tree lands from the bound session (the arm discriminates)" \
  "spawn-worktree: LANDED branch=verb-dirty onto=wave/fixture *" \
  "$( cd "$V" && CLAUDE_CODE_SESSION_ID="$VSID" bash "$SPAWN" land "$VD" 2>/dev/null )"
expect_true "the usage text names the land verb" \
  grep -q 'spawn-worktree.sh land' "$SPAWN"

# T8b (review R8/F3) END TO END: the verb reads its own session id off
# CLAUDE_CODE_SESSION_ID (`cmd_land`) and now threads it through to `_wt_busy_suite`, so a
# busy `tests/run.sh` recorded under the CALLING session's own session file never refuses
# its own land — the exact topology T12's live bed hit (its first head attempt was refused
# `session=<its own session>`, F3).
VSUITE="$TMP/verb-suite/tests"; mkdir -p "$VSUITE"
printf '#!/bin/bash\nsleep 120\n' > "$VSUITE/run.sh"; chmod +x "$VSUITE/run.sh"
bash "$VSUITE/run.sh" >/dev/null 2>&1 & VSUITE_PID=$!
# Folded into the ONE exit trap (never a second `trap ... EXIT`, which would replace
# rather than add to the first and leak $TMP and $SUITE_PID on an early exit).
trap 'kill "$SUITE_PID" 2>/dev/null; kill "$VSUITE_PID" 2>/dev/null; rm -rf "$TMP"' EXIT
i=0; while [ $i -lt 50 ] && ! pgrep -f 'tests/run.sh' >/dev/null 2>&1; do i=$((i+1)); done

VSELF="$(new_tree "$V" verb-self-busy)"
printf '{"pid":%s,"sessionId":"%s","cwd":"%s","status":"busy","name":"self"}\n' \
  "$VSUITE_PID" "$VSID" "$V" > "$CLAUDE_HOME/sessions/${VSUITE_PID}.json"
expect_match "the verb's own busy suite does not refuse its own land" \
  "spawn-worktree: LANDED branch=verb-self-busy onto=wave/fixture *" \
  "$( cd "$V" && CLAUDE_CODE_SESSION_ID="$VSID" bash "$SPAWN" land "$VSELF" 2>/dev/null )"

# The same running suite, recorded under a DIFFERENT session's file: still refused.
VOTHER="$(new_tree "$V" verb-other-busy)"
printf '{"pid":%s,"sessionId":"%s","cwd":"%s","status":"busy","name":"peer"}\n' \
  "$VSUITE_PID" "verb-peer-session" "$V" > "$CLAUDE_HOME/sessions/${VSUITE_PID}.json"
OUTVB="$( cd "$V" && CLAUDE_CODE_SESSION_ID="$VSID" bash "$SPAWN" land "$VOTHER" 2>/dev/null )"; RCVB=$?
expect_match "a different session's busy suite in this project still refuses" \
  "spawn-worktree: REFUSED reason=suite-running*" "$OUTVB"
expect_eq   "that refusal exits 2" "2" "$RCVB"

kill "$VSUITE_PID" 2>/dev/null
rm -f "$CLAUDE_HOME/sessions/${VSUITE_PID}.json"

section "Group 8: worktree_lease_overruns — a tree outliving its row"
#
# C1's tick finding. The lease ends when the row is fact-discharged; a tree
# still standing after that is a slot counted against the worktree budget that
# nobody holds, and saying so is the whole of this function's job — it lands
# nothing and removes nothing.
#
# THE MAPPING IS BY CONVENTION, because the roster carries no worktree field: a
# tree at `.worktrees/<dir>` belongs to the row named `W-<DIR>` uppercased, the
# spelling every wave in this repo has used. The walk starts from the TREES, so
# a row with no tree is silent and a tree with no discharged row is silent.

O="$(new_repo "$TMP/overrun")"
new_tree "$O" l-root      >/dev/null
new_tree "$O" adopt       >/dev/null
new_tree "$O" still-going >/dev/null
VERDICTS="$TMP/verdicts.txt"

: > "$VERDICTS"
expect_eq "no discharged rows, no overruns" "" "$(worktree_lease_overruns "$O" "$VERDICTS")"

cat > "$VERDICTS" <<'V'
landing-verdict/v1|at=2026-09-02T00:00:00Z|session=s|name=W-L-ROOT|state=MET|acked=no|detail=x
landing-verdict/v1|at=2026-09-02T00:00:00Z|session=s|name=W-STILL-GOING|state=UNMET|acked=no|detail=x
V
expect_eq "a MET row whose tree still stands is one overrun line" \
  "${O}/.worktrees/l-root	W-L-ROOT" "$(worktree_lease_overruns "$O" "$VERDICTS")"
expect_eq "the line is path TAB row-id" "2" \
  "$(worktree_lease_overruns "$O" "$VERDICTS" | awk -F'\t' '{print NF}')"
expect_eq "an UNMET row's tree is NOT an overrun (the arm discriminates)" "0" \
  "$(worktree_lease_overruns "$O" "$VERDICTS" | grep -c 'still-going')"

# The other two spellings of discharge, each on its own.
cat > "$VERDICTS" <<'V'
landing-verdict/v1|at=2026-09-02T00:00:00Z|session=s|name=W-ADOPT|state=UNMET|acked=yes|detail=x
V
expect_eq "an ACKED row discharges too" "${O}/.worktrees/adopt	W-ADOPT" \
  "$(worktree_lease_overruns "$O" "$VERDICTS")"
roster_row_fixture status=CLOSED session=s name=W-ADOPT deliverable=x > "$VERDICTS"
expect_eq "a CLOSED roster row discharges too" "${O}/.worktrees/adopt	W-ADOPT" \
  "$(worktree_lease_overruns "$O" "$VERDICTS")"

# Two at once, and a discharged row whose tree is already gone stays silent —
# that row's lease ended correctly and has nothing to report.
cat > "$VERDICTS" <<'V'
landing-verdict/v1|at=2026-09-02T00:00:00Z|session=s|name=W-L-ROOT|state=MET|acked=no|detail=x
landing-verdict/v1|at=2026-09-02T00:00:00Z|session=s|name=W-ADOPT|state=WAIVED|acked=no|detail=x
landing-verdict/v1|at=2026-09-02T00:00:00Z|session=s|name=W-LONG-GONE|state=MET|acked=no|detail=x
V
expect_eq "two standing trees, two lines" "2" "$(worktree_lease_overruns "$O" "$VERDICTS" | grep -c .)"
expect_eq "a discharged row with no tree reports nothing" "0" \
  "$(worktree_lease_overruns "$O" "$VERDICTS" | grep -c 'long-gone')"
expect_eq "a missing verdict file is not an error, just silence" "" \
  "$(worktree_lease_overruns "$O" "$TMP/no-such-file")"
expect_eq "the function removes nothing" "3" \
  "$(ls "${O}/.worktrees" | grep -c .)"


section "Group 9: the two-checkout topology — a land merges into the working branch, in the checkout that holds it (T8, REQ-1, AC-1.1)"
#
# THE REPORTED DEFECT (report #9; triage-C M1). The main checkout sits on a FEATURE branch a
# human is working on; the wave's integration branch is checked out in its own tree under
# .worktrees/. Before T8, land merged into the main checkout's HEAD — the feature branch —
# and left the wave branch unmerged. Now the target is named, and the merge runs in the
# checkout that holds it. Every fact below is read back from git, not from the line.

W="$(new_repo "$TMP/topology")"
git -C "$W" checkout --quiet -b feature/human
git -C "$W" worktree add --quiet -b wave/20-demo "$W/.worktrees/20-demo" main >/dev/null 2>&1
WWAVE="$(cd "$W/.worktrees/20-demo" && pwd -P)"
task_tree() {  # <repo> <branch> <base> -> echoes the tree path, one commit ahead of <base>
  local r="$1" b="$2" base="$3" d="$1/.worktrees/${2##*/}"
  git -C "$r" worktree add --quiet -b "$b" "$d" "$base" >/dev/null 2>&1
  echo "$b" > "$d/${b##*/}.txt"
  git -C "$d" add -A >/dev/null 2>&1
  git -C "$d" commit --quiet -m "$b work"
  printf '%s' "$d"
}
WT1="$(task_tree "$W" wt/20-T1 wave/20-demo)"
FEAT0="$(git -C "$W" rev-parse feature/human)"
WAVE0="$(git -C "$W" rev-parse wave/20-demo)"

OUTW="$(worktree_land "$WT1" wave/20-demo)"; RCW=$?
expect_match "the land names the target and the checkout that holds it" \
  "spawn-worktree: LANDED branch=wt/20-T1 onto=wave/20-demo checkout=${WWAVE} merge=* removed=${WT1}" "$OUTW"
expect_eq   "it exits 0" "0" "$RCW"
expect_eq   "the feature branch did not move" "$FEAT0" "$(git -C "$W" rev-parse feature/human)"
expect_eq   "the main checkout is still on the feature branch" "feature/human" \
  "$(git -C "$W" rev-parse --abbrev-ref HEAD)"
expect_eq   "wt/20-T1 is NOT in the feature branch" "1" "$(git -C "$W" rev-list --count feature/human..wt/20-T1)"
expect_eq   "wt/20-T1 IS in the wave branch" "0" "$(git -C "$W" rev-list --count wave/20-demo..wt/20-T1)"
expect_eq   "the wave branch's new head is a --no-ff merge whose first parent is its old head" \
  "$WAVE0" "$(git -C "$W" rev-parse wave/20-demo^1)"
expect_eq   "the merge= field is the wave branch's head" "$(git -C "$W" rev-parse wave/20-demo)" \
  "$(printf '%s' "$OUTW" | tr ' ' '\n' | sed -n 's/^merge=//p')"
expect_true "the wave checkout's working tree carries the landed file" test -f "$WWAVE/20-T1.txt"
expect_eq   "and the wave checkout is clean after the merge" "" "$(git -C "$WWAVE" status --porcelain --untracked-files=no)"
expect_false "the task tree is gone" test -d "$WT1"

# THROUGH THE SESSION: the same act, the target read off the bound plan's working-branch.
TSID="topology-session-01"
bind_plan "$W" "$TSID" wave/20-demo >/dev/null
WT2="$(task_tree "$W" wt/20-T2 wave/20-demo)"
FEAT1="$(git -C "$W" rev-parse feature/human)"
OUTW2="$(worktree_land_for_session "$WT2" "$W" "$TSID")"; RCW2=$?
expect_match "worktree_land_for_session lands onto the plan's working branch" \
  "spawn-worktree: LANDED branch=wt/20-T2 onto=wave/20-demo checkout=${WWAVE} *" "$OUTW2"
expect_eq   "it exits 0" "0" "$RCW2"
expect_eq   "the feature branch did not move" "$FEAT1" "$(git -C "$W" rev-parse feature/human)"
expect_eq   "wt/20-T2 is in the wave branch" "0" "$(git -C "$W" rev-list --count wave/20-demo..wt/20-T2)"

section "Group 10: the refusals — no bound plan, no working branch, a branch checked out nowhere (T8, REQ-1, AC-1.2)"
#
# EVERY REFUSAL LEAVES EVERY REF WHERE IT WAS. Each arm snapshots `for-each-ref` before and
# compares after, so "no merge commit anywhere" is read off git, and the tree must survive.
# The arms run in the one fixture, and the last one is the positive arm that lands the tree.

F="$(new_repo "$TMP/refusals")"
FT="$(new_tree "$F" wt/refused)"
FSID="refusal-session-01"
refused_arm() {  # <label> <glob> <tree> <sid> — the call, its exit, the tree, every ref
  local label="$1" glob="$2" tree="$3" sid="$4" before out rc
  before="$(refs_of "$F")"
  out="$(worktree_land_for_session "$tree" "$F" "$sid")"; rc=$?
  expect_match "$label" "$glob" "$out"
  expect_eq    "$label: exits 2" "2" "$rc"
  expect_true  "$label: the tree survives" test -d "$tree"
  expect_eq    "$label: no ref moved" "$before" "$(refs_of "$F")"
}

refused_arm "no session id is refused" \
  "spawn-worktree: REFUSED reason=no-session*" "$FT" ""
refused_arm "an unbound session in a root with no open run is refused (none)" \
  "spawn-worktree: REFUSED reason=no-bound-plan state=none*" "$FT" "$FSID"
FP="$(bind_plan "$F" "other-session-01" wave/fixture)"
refused_arm "an unbound session in a root WITH an open run is refused (fallback), never landed there" \
  "spawn-worktree: REFUSED reason=no-bound-plan state=fallback*" "$FT" "$FSID"
FP="$(bind_plan "$F" "$FSID" "")"
refused_arm "a bound plan with no working-branch: line is refused, naming the plan" \
  "spawn-worktree: REFUSED reason=no-working-branch plan=${FP}*" "$FT" "$FSID"
FP="$(bind_plan "$F" "$FSID" wave/fixture)"
chmod 000 "$FP"
refused_arm "a bound plan that exists and cannot be read is refused (bound-unreadable), naming it" \
  "spawn-worktree: REFUSED reason=bound-unreadable plan=${FP}*" "$FT" "$FSID"
chmod 644 "$FP"
rm -f "$FP"
refused_arm "a bound plan that is gone is refused: there is no working branch to read" \
  "spawn-worktree: REFUSED reason=no-working-branch plan=${FP}*" "$FT" "$FSID"
git -C "$F" branch --quiet wave/parked main
FP="$(bind_plan "$F" "$FSID" wave/parked)"
refused_arm "a working branch that is checked out nowhere is refused, naming it" \
  "spawn-worktree: REFUSED reason=onto-not-checked-out branch=wave/parked*" "$FT" "$FSID"
FP="$(bind_plan "$F" "$FSID" wave/never-made)"
refused_arm "a working branch that is not a branch at all is refused, naming it" \
  "spawn-worktree: REFUSED reason=onto-unknown branch=wave/never-made*" "$FT" "$FSID"

# TWO CHECKOUTS HOLD THE TARGET (`worktree add --force`): which one to merge in is not this
# function's guess to make.
git -C "$F" worktree add --quiet --force "$TMP/second-fixture-co" wave/fixture >/dev/null 2>&1
FP="$(bind_plan "$F" "$FSID" wave/fixture)"
refused_arm "a working branch checked out in two places is refused as ambiguous" \
  "spawn-worktree: REFUSED reason=onto-ambiguous branch=wave/fixture*" "$FT" "$FSID"
git -C "$F" worktree remove --force "$TMP/second-fixture-co" >/dev/null 2>&1

# THE TARGET CHECKOUT HAS UNCOMMITTED TRACKED CHANGES: a merge there would mix them in.
echo "half-typed" >> "$F/file.txt"
refused_arm "a target checkout with uncommitted tracked changes is refused" \
  "spawn-worktree: REFUSED reason=onto-checkout-dirty checkout=${F}*" "$FT" "$FSID"
git -C "$F" checkout --quiet -- file.txt

# THE ARM DISCRIMINATES: the same tree, the same session, a plan that names a branch held in
# one clean checkout — it lands.
OUTF="$(worktree_land_for_session "$FT" "$F" "$FSID")"; RCF=$?
expect_match "the same tree lands once every refusal is lifted" \
  "spawn-worktree: LANDED branch=wt/refused onto=wave/fixture checkout=${F} *" "$OUTF"
expect_eq   "it exits 0" "0" "$RCF"

finish
