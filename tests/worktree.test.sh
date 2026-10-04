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
# and system git config are pointed at /dev/null. The session files some arms plant
# (to show that a session plays no part in D1) go to a fixture claude-home reached
# through BIONIC_CLAUDE_HOME — the knob payload/scripts/lib/patrol.sh already uses
# for exactly this directory, so there is one override chain and not two.
#
# THE SUITE-RUNNING ARMS START THEIR OWN PROCESSES. D1 (wave-20 T8c) refuses while a
# `tests/run.sh` process has its script path or its working directory in the project
# root or the land's target checkout. When this suite runs under tests/run.sh, that
# runner sits in the bionic checkout, outside every fixture, so it never answers for
# one. The arms start a stand-in `<dir>/tests/run.sh` that only sleeps, from a chosen
# working directory, and stop it to show the matching admission.
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

# An EMPTY fixture claude-home by default. D1 no longer reads it (T8c); the arms that
# plant a session file there show that a session changes nothing. No stand-in runner
# works inside any fixture outside Group 5 and Group 7, so every other land sees
# "no suite running" whatever the real machine is doing.
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
# Every worktree, its path and its branch, without the heads: what a land removes or keeps.
trees_of() { git -C "$1" worktree list --porcelain | grep -v '^HEAD '; }

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
# whether it names a directory or a symlink — and the link is deleted just
# before `git worktree remove` (wave-26 D19; §LAND-KEEP covers a project that
# does not ignore the symlink shape).

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
# D1 IS A FACT ABOUT PROCESSES AND DIRECTORIES (wave-20 T8c; review R2-1, R2-8; critic
# C2-1). The land refuses while a `tests/run.sh` process has its script path or its working
# directory inside the project root or inside the land's TARGET checkout. No session file is
# read. In-process teammates and Agent-tool subagents share their orchestrator's session and
# have no session file of their own, so a session can never tell the orchestrator from the
# floor it dispatched (T8b tried, and switched D1 off for exactly that floor).
#
# Every arm starts its own STAND-IN RUNNER: a script at `<dir>/tests/run.sh` that only
# sleeps, run as `bash <script>` from a chosen working directory. The real runner is never
# started. When this suite itself runs under tests/run.sh, that runner sits in the bionic
# checkout, outside every fixture here, so the answer is the same in both modes.

S="$(new_repo "$TMP/land-busy")"

RUNNER_PID=""
# <cwd> <script as invoked> -> RUNNER_PID. Returns once the process shows the command line
# the predicate matches, so no arm races the exec.
start_runner() {
  ( cd "$1" && exec bash "$2" ) >/dev/null 2>&1 &
  RUNNER_PID=$!
  local i=0
  while [ $i -lt 100 ]; do
    case "$(ps -o command= -p "$RUNNER_PID" 2>/dev/null)" in *tests/run.sh*) return 0 ;; esac
    i=$((i+1)); sleep 0.05
  done
  return 1
}
stop_runner() {
  [ -n "$RUNNER_PID" ] || return 0
  kill "$RUNNER_PID" 2>/dev/null; wait "$RUNNER_PID" 2>/dev/null
  RUNNER_PID=""
}
make_runner() {  # <dir> -> <dir>/tests/run.sh
  mkdir -p "$1/tests"
  printf '#!/bin/bash\nwhile :; do sleep 1; done\n' > "$1/tests/run.sh"
  chmod +x "$1/tests/run.sh"
}
trap 'stop_runner; rm -rf "$TMP"' EXIT

# Somewhere that is no repository at all, and ANOTHER repository (T12 F3's topology: the
# floor of one project and the land of another).
ELSE="$TMP/elsewhere"; make_runner "$ELSE"
OTHER="$(new_repo "$TMP/other-repo")"; make_runner "$OTHER"
make_runner "$S"

session_file() {  # <pid> <cwd> <status> <name>
  printf '{"pid":%s,"sessionId":"fixture-%s","cwd":"%s","status":"%s","name":"%s","kind":"interactive"}\n' \
    "$1" "$4" "$2" "$3" "$4" > "$CLAUDE_HOME/sessions/$1.json"
}

BT="$(new_tree "$S" busy-arm)"

# Arm 1 — a runner whose SCRIPT is in the project root, started from elsewhere: refused,
# naming the process. No session file exists anywhere in this fixture.
expect_true "a stand-in runner started (script in the root, cwd elsewhere)" \
  start_runner "$ELSE" "$S/tests/run.sh"
SREFS0="$(refs_of "$S")"
OUTB="$(worktree_land "$BT" wave/fixture)"; RCB=$?
expect_match "a runner whose script is in this project refuses the land" \
  "spawn-worktree: REFUSED reason=suite-running*" "$OUTB"
expect_match "and the refusal NAMES the process" "*pid=${RUNNER_PID}*" "$OUTB"
expect_match "and the script it runs" "*script=${S}/tests/run.sh*" "$OUTB"
expect_eq    "the refusal exits 2" "2" "$RCB"
expect_true  "the tree survives the refusal" test -d "$BT"
expect_eq    "no ref moved" "$SREFS0" "$(refs_of "$S")"

# Arm 2 — the same world once the runner has exited: the land goes through. A process that
# is gone is not a running suite.
stop_runner
expect_match "the same land goes through once the runner is gone (the arm discriminates)" \
  "spawn-worktree: LANDED *" "$(worktree_land "$BT" wave/fixture)"

# Arm 3 — a RELATIVE invocation, `bash tests/run.sh` from the root. The command line names
# no directory, so only the process's working directory places it.
BT3="$(new_tree "$S" relative-arm)"
expect_true "a stand-in runner started (relative, cwd the root)" start_runner "$S" "tests/run.sh"
OUTB3="$(worktree_land "$BT3" wave/fixture)"; RCB3=$?
expect_match "a relative runner whose working directory is the root refuses" \
  "spawn-worktree: REFUSED reason=suite-running*cwd=${S} *" "$OUTB3"
expect_eq    "that refusal exits 2" "2" "$RCB3"
stop_runner

# Arm 4 — a runner working inside a LINKED WORKTREE of this project counts as this project:
# that is where a writer running a suite sits. The script itself lives elsewhere.
BT4="$(new_tree "$S" from-a-tree)"
OT4="$(new_tree "$S" writers-tree)"
expect_true "a stand-in runner started (cwd a linked worktree)" start_runner "$OT4" "$ELSE/tests/run.sh"
expect_match "a runner working inside one of the project's own trees refuses" \
  "spawn-worktree: REFUSED reason=suite-running*cwd=${OT4} *" "$(worktree_land "$BT4" wave/fixture)"
stop_runner

# Arm 5 — T12 F3: a runner in ANOTHER repository never refuses this project's land, whether
# it was invoked relatively from that repository or by its absolute path.
expect_true "a stand-in runner started (relative, in another repository)" \
  start_runner "$OTHER" "tests/run.sh"
expect_match "a runner in a different repository does not refuse (T12 F3)" \
  "spawn-worktree: LANDED branch=from-a-tree *" "$(worktree_land "$BT4" wave/fixture)"
stop_runner
BT5="$(new_tree "$S" other-abs-arm)"
expect_true "a stand-in runner started (absolute, another repository's script, cwd elsewhere)" \
  start_runner "$ELSE" "$OTHER/tests/run.sh"
expect_match "…nor does one invoked by its absolute path" \
  "spawn-worktree: LANDED branch=other-abs-arm *" "$(worktree_land "$BT5" wave/fixture)"
stop_runner

# Arm 6 — THE TARGET CHECKOUT IS WHERE THE MERGE HAPPENS (T8, D1), so a runner working in it
# refuses even when that checkout lives OUTSIDE the project root, which
# `spawn-worktree.sh create` allows with an absolute parent. The check is widened to the
# target, never narrowed.
SWAVE="$TMP/outside-wave"
git -C "$S" worktree add --quiet -b wave/out "$SWAVE" wave/fixture >/dev/null 2>&1
SWAVE="$(cd "$SWAVE" && pwd -P)"
BT6="$(new_tree "$S" into-outside)"
expect_true "a stand-in runner started (cwd the outside target checkout)" \
  start_runner "$SWAVE" "$ELSE/tests/run.sh"
OUTB6="$(worktree_land "$BT6" wave/out)"; RCB6=$?
expect_match "a runner in the TARGET checkout, outside the root, refuses" \
  "spawn-worktree: REFUSED reason=suite-running*cwd=${SWAVE} *" "$OUTB6"
expect_eq    "that refusal exits 2" "2" "$RCB6"
stop_runner
expect_match "the same land goes through once that runner is gone (the arm discriminates)" \
  "spawn-worktree: LANDED branch=into-outside onto=wave/out checkout=${SWAVE} *" \
  "$(worktree_land "$BT6" wave/out)"

# Arm 7 — THE ORCHESTRATOR'S OWN FLOOR (T8c; review R2-1, critic C2-1). The real fleet
# shape: ONE session file, the orchestrator's, busy, its cwd the root; the floor it
# dispatched runs `<wave checkout>/tests/run.sh` in the wave checkout; the land goes onto
# the wave branch. Called with the lander's own session id (T8b's call shape, which still
# parses) and without it: both refuse, because who runs the suite plays no part.
SINNER="$S/.worktrees/inner"
git -C "$S" worktree add --quiet -b wave/inner "$SINNER" wave/fixture >/dev/null 2>&1
make_runner "$SINNER"
BT7="$(new_tree "$S" self-arm)"
session_file "$$" "$S" busy W-SELF
expect_true "a stand-in runner started (the floor: absolute script in the wave checkout)" \
  start_runner "$SINNER" "$SINNER/tests/run.sh"
OUTB7="$(worktree_land "$BT7" wave/inner "fixture-W-SELF")"; RCB7=$?
expect_match "(T8c: was \"the lander's OWN busy session does not refuse its own land\") the lander's own session's floor in the target checkout refuses" \
  "spawn-worktree: REFUSED reason=suite-running*script=${SINNER}/tests/run.sh*" "$OUTB7"
expect_eq    "that refusal exits 2" "2" "$RCB7"
expect_match "and the call without a session id refuses the same" \
  "spawn-worktree: REFUSED reason=suite-running*" "$(worktree_land "$BT7" wave/inner)"
expect_true  "the tree survives" test -d "$BT7"
stop_runner
expect_match "the same land goes through once the floor has finished (the arm discriminates)" \
  "spawn-worktree: LANDED branch=self-arm onto=wave/inner *" \
  "$(worktree_land "$BT7" wave/inner "fixture-W-SELF")"

# Arm 8 — a runner in this root refuses whoever's session started it: here a DIFFERENT
# session's file is the busy one, and the land still refuses.
BT8="$(new_tree "$S" other-session-arm)"
rm -f "$CLAUDE_HOME/sessions/$$.json"
session_file "$$" "$S" busy W-PEER2
expect_true "a stand-in runner started (relative, cwd the root)" start_runner "$S" "tests/run.sh"
OUTB8="$(worktree_land "$BT8" wave/fixture "some-other-session-id")"; RCB8=$?
expect_match "(T8c: was \"a different session's busy suite in this project still refuses\") a suite in this root refuses, from any session" \
  "spawn-worktree: REFUSED reason=suite-running*" "$OUTB8"
expect_eq    "that refusal exits 2" "2" "$RCB8"
stop_runner

# Arm 9 — THE SESSION PLAYS NO PART IN AN ADMISSION EITHER (T12 F3 as it was measured): the
# lander's session file busy at the root, the only runner in ANOTHER repository. The
# pre-T8b predicate refused this, naming the lander's own session. Both call shapes land.
rm -f "$CLAUDE_HOME/sessions/$$.json"
session_file "$$" "$S" busy W-SELF
expect_true "a stand-in runner started (relative, in another repository)" \
  start_runner "$OTHER" "tests/run.sh"
expect_match "(T8c: was \"no sid argument -> the busy session still refuses (unchanged default)\") a busy session with its only runner in another repository does not refuse" \
  "spawn-worktree: LANDED branch=other-session-arm *" "$(worktree_land "$BT8" wave/fixture)"
BT9="$(new_tree "$S" no-sid-arm)"
expect_match "…nor with the lander's session id" \
  "spawn-worktree: LANDED branch=no-sid-arm *" "$(worktree_land "$BT9" wave/fixture "fixture-W-SELF")"
stop_runner

rm -f "$CLAUDE_HOME/sessions/$$.json"

# Arm 10 — A COMMAND THAT ONLY MENTIONS THE RUNNER IS NOT THE RUNNER (T31, found live in
# wave 26). The harness runs every Bash call as `zsh -c '… <the whole command text>'`, so a
# wait loop or a progress note naming `tests/run.sh` is a process in the project whose command
# line holds that text. Only a process that RUNS the script counts: its interpreter's script
# word, or its argv[0], ends in `tests/run.sh`, and that path resolves to a file.
MENTION_PID=""
start_mention() {  # <cwd> <shell> <-c text> -> MENTION_PID, once ps shows the text
  ( cd "$1" && exec "$2" -c "$3" ) >/dev/null 2>&1 &
  MENTION_PID=$!
  local i=0
  while [ $i -lt 100 ]; do
    case "$(ps -o command= -p "$MENTION_PID" 2>/dev/null)" in *tests/run.sh*) return 0 ;; esac
    i=$((i+1)); sleep 0.05
  done
  return 1
}
stop_mention() {
  [ -n "$MENTION_PID" ] || return 0
  kill "$MENTION_PID" 2>/dev/null; wait "$MENTION_PID" 2>/dev/null
  MENTION_PID=""
}
trap 'stop_runner; stop_mention; rm -rf "$TMP"' EXIT
BT10="$(new_tree "$S" mention-arm)"
expect_true "a shell started in the root whose -c text names the runner bare" \
  start_mention "$S" bash 'while :; do sleep 1; done # bash tests/run.sh'
expect_match "a shell whose -c text names tests/run.sh does not refuse the land" \
  "spawn-worktree: LANDED branch=mention-arm *" "$(worktree_land "$BT10" wave/fixture)"
stop_mention
BT11="$(new_tree "$S" quoted-mention-arm)"
expect_true "a shell started in the root whose -c text quotes the runner, as the harness's wait loops do" \
  start_mention "$S" bash "while :; do sleep 1; done; until ! pgrep -f 'tests/run.sh'; do sleep 30; done"
expect_match "a quoted mention does not refuse either (it once printed script=unreadable)" \
  "spawn-worktree: LANDED branch=quoted-mention-arm *" "$(worktree_land "$BT11" wave/fixture)"
# The same world with the real runner started beside the mention: the runner refuses, and the
# refusal names the runner, not the mention.
BT12="$(new_tree "$S" mention-and-runner-arm)"
expect_true "the mention is still running" kill -0 "$MENTION_PID"
expect_true "a stand-in runner started beside it (relative, cwd the root)" start_runner "$S" "tests/run.sh"
OUTB12="$(worktree_land "$BT12" wave/fixture)"; RCB12=$?
expect_match "a real bash tests/run.sh in the root still refuses, naming the runner" \
  "spawn-worktree: REFUSED reason=suite-running pid=${RUNNER_PID} cwd=${S} script=${S}/tests/run.sh" "$OUTB12"
expect_eq    "that refusal exits 2" "2" "$RCB12"
stop_runner
stop_mention
# A -c string whose FIRST word is a runner path is still a command string: here bash tries a
# non-executable `tests/run.sh` in a directory of the root, fails, and loops.
mkdir -p "$S/sub/tests"; printf 'not a runner\n' > "$S/sub/tests/run.sh"
expect_true "a shell started whose -c string opens with a tests/run.sh that resolves in the root" \
  start_mention "$S/sub" bash 'tests/run.sh 2>/dev/null; while :; do sleep 1; done'
expect_match "a -c string is never a script, whatever its first word" \
  "spawn-worktree: LANDED branch=mention-and-runner-arm *" "$(worktree_land "$BT12" wave/fixture)"
stop_mention
rm -rf "$S/sub"
BT12="$(new_tree "$S" runner-shapes-arm)"
# An interpreter option before the script, and the script as argv[0], are runners too.
start_runner_argv() {  # <cwd> <glob> <argv>... -> RUNNER_PID, once ps shows a command matching <glob>
  local d="$1" g="$2"; shift 2
  ( cd "$d" && exec "$@" ) >/dev/null 2>&1 &
  RUNNER_PID=$!
  local i=0
  while [ $i -lt 100 ]; do
    [[ "$(ps -o command= -p "$RUNNER_PID" 2>/dev/null)" == $g ]] && return 0
    i=$((i+1)); sleep 0.05
  done
  return 1
}
expect_true "a stand-in runner started as bash -o pipefail tests/run.sh" \
  start_runner_argv "$S" "*bash -o pipefail tests/run.sh" bash -o pipefail tests/run.sh
expect_match "a runner behind an interpreter option refuses" \
  "spawn-worktree: REFUSED reason=suite-running pid=${RUNNER_PID} *script=${S}/tests/run.sh" \
  "$(worktree_land "$BT12" wave/fixture)"
stop_runner
# BUNDLED OPTIONS (review 7 F7). Each `o` or `O` in a cluster takes the next word, as bash reads
# it, so the common `bash -euo pipefail <runner>` is the runner, not `pipefail`.
expect_true "a stand-in runner started as bash -euo pipefail tests/run.sh" \
  start_runner_argv "$S" "*bash -euo pipefail tests/run.sh" bash -euo pipefail tests/run.sh
expect_match "a runner behind a bundled -euo pipefail refuses" \
  "spawn-worktree: REFUSED reason=suite-running pid=${RUNNER_PID} *script=${S}/tests/run.sh" \
  "$(worktree_land "$BT12" wave/fixture)"
stop_runner
# The walk itself, one argv per row, as `ps` would print it. Runners first, then the command
# strings and stdin the same walk must never take for a script.
for argv in "bash tests/run.sh" "bash -e tests/run.sh" "bash -o pipefail tests/run.sh" \
            "bash -euo pipefail tests/run.sh" "bash -eo pipefail tests/run.sh" \
            "bash +euo pipefail tests/run.sh" "bash -oo pipefail errexit tests/run.sh" \
            "bash -eO extglob tests/run.sh" "bash - tests/run.sh" "bash -- tests/run.sh" \
            "bash + tests/run.sh" "bash --rcfile /dev/null tests/run.sh" "zsh -euo pipefail tests/run.sh"; do
  # shellcheck disable=SC2086  # one argv word per word, as ps prints it
  expect_eq "the walk finds the runner in: ${argv}" "tests/run.sh" "$(_wt_runner_script $argv)"
done
for argv in "bash -c tests/run.sh" "bash -ec tests/run.sh" "bash -euo pipefail -c tests/run.sh" \
            "bash -co pipefail tests/run.sh" "bash +c tests/run.sh" "bash -s tests/run.sh" \
            "bash -o pipefail" "bash -euo"; do
  # shellcheck disable=SC2086
  expect_false "the walk finds no runner in: ${argv}" _wt_runner_script $argv
done
expect_true "a process started with the root's tests/run.sh as its argv[0]" \
  start_runner_argv "$ELSE" "$S/tests/run.sh 30" bash -c "exec -a '$S/tests/run.sh' sleep 30"
expect_match "a process whose argv[0] is the runner's script refuses" \
  "spawn-worktree: REFUSED reason=suite-running pid=${RUNNER_PID} *script=${S}/tests/run.sh" \
  "$(worktree_land "$BT12" wave/fixture)"
stop_runner
# A runner path that resolves to no file is not a runner: the directory is the root's, the
# script is not there.
mkdir -p "$S/empty/tests"
expect_true "a process started with a missing tests/run.sh in the root as its argv[0]" \
  start_runner_argv "$ELSE" "$S/empty/tests/run.sh 30" bash -c "exec -a '$S/empty/tests/run.sh' sleep 30"
expect_match "a runner path that resolves to no file does not refuse" \
  "spawn-worktree: LANDED branch=runner-shapes-arm *" "$(worktree_land "$BT12" wave/fixture)"
stop_runner
rmdir "$S/empty/tests" "$S/empty"

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

# T8c (review R2-1, critic C2-1) END TO END through the verb. The verb reads its session id
# off CLAUDE_CODE_SESSION_ID (`cmd_land`) and uses it for one thing: the target branch.
# The orchestrator's shape is one busy session file at the root; the floor it dispatched
# runs in the checkout the land merges into.
VELSE="$TMP/verb-else"; make_runner "$VELSE"
VOTHERREPO="$(new_repo "$TMP/verb-other-repo")"; make_runner "$VOTHERREPO"
VSELF="$(new_tree "$V" verb-self-busy)"
printf '{"pid":%s,"sessionId":"%s","cwd":"%s","status":"busy","name":"self"}\n' \
  "$$" "$VSID" "$V" > "$CLAUDE_HOME/sessions/$$.json"
expect_true "a stand-in runner started (cwd the verb's target checkout)" \
  start_runner "$V" "$VELSE/tests/run.sh"
VREFS0="$(refs_of "$V")"
OUTVS="$( cd "$V" && CLAUDE_CODE_SESSION_ID="$VSID" bash "$SPAWN" land "$VSELF" 2>/dev/null )"; RCVS=$?
expect_match "(T8c: was \"the verb's own busy suite does not refuse its own land\") the verb's own session's floor in the target checkout refuses its own land" \
  "spawn-worktree: REFUSED reason=suite-running*cwd=${V} *" "$OUTVS"
expect_eq   "that refusal exits 2" "2" "$RCVS"
expect_eq   "no ref moved" "$VREFS0" "$(refs_of "$V")"
stop_runner

# The same session, its only runner in another repository: the verb lands.
expect_true "a stand-in runner started (relative, in another repository)" \
  start_runner "$VOTHERREPO" "tests/run.sh"
expect_match "a runner in another repository does not refuse the verb's land" \
  "spawn-worktree: LANDED branch=verb-self-busy onto=wave/fixture *" \
  "$( cd "$V" && CLAUDE_CODE_SESSION_ID="$VSID" bash "$SPAWN" land "$VSELF" 2>/dev/null )"
stop_runner

# A runner in this root with NO session file at all (a human's terminal): still refused.
rm -f "$CLAUDE_HOME/sessions/$$.json"
VOTHER="$(new_tree "$V" verb-other-busy)"
expect_true "a stand-in runner started (cwd the root)" start_runner "$V" "$VELSE/tests/run.sh"
OUTVB="$( cd "$V" && CLAUDE_CODE_SESSION_ID="$VSID" bash "$SPAWN" land "$VOTHER" 2>/dev/null )"; RCVB=$?
expect_match "a suite in this root with no session file at all still refuses" \
  "spawn-worktree: REFUSED reason=suite-running*" "$OUTVB"
expect_eq   "that refusal exits 2" "2" "$RCVB"
stop_runner

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


section "Group 11: the workspace readers — one file, read by key, refused through a link (wave-25 T1, D3)"
#
# `workspace_for_name <root> <sid> <name>` and `workspaces_of_session <root> <sid>` read
# `<root>/.bionic/tmp/workspaces-<sid>.state`, the file `spawn-worktree.sh create --for`
# appends to (tests/spawn-worktree.test.sh §WS drives that writer end to end). These rows
# hand-build the file to reach the shapes a create never writes: another session's line, a
# foreign line, a line with no path or a relative one, a CRLF ending. rc 1 is "nothing
# recorded"; rc 2 is "refused", the file or a directory above it a symlink, or a session id
# no file can be named for.
#
# EVERY PATH IN THESE LINES IS A REAL LINKED WORKTREE of the fixture repository (wave-25 T18):
# a recorded path counts only when git lists it as one (Group 11b), so a row that wants the
# session filter, the schema filter or the CRLF handling to be the thing that decides must
# hand those filters a path the git rule would otherwise accept.

expect_true "workspace_for_name is defined"    declare -f workspace_for_name
expect_true "workspaces_of_session is defined" declare -f workspaces_of_session

# A linked worktree with no commit of its own, at <repo>/<parent>/<name>; echoes the path git
# lists for it (the repository's path is physical, and git records the physical path).
ws_tree() {  # <repo> <name> [parent dir, default .worktrees]
  local r="$1" p="${3:-$1/.worktrees}"
  git -C "$r" worktree add --quiet -b "ws/$2" "$p/$2" HEAD >/dev/null 2>&1
  printf '%s' "$(cd "$p/$2" && pwd -P)"
}

WK="$(new_repo "$TMP/ws-reader")"; mkdir -p "$WK/.bionic/tmp"
WKSID="reader-session-01"
WKF="$WK/.bionic/tmp/workspaces-${WKSID}.state"
WA1="$(ws_tree "$WK" a-1)"; WB1="$(ws_tree "$WK" b-1)"; WA2="$(ws_tree "$WK" a-2)"
WC1="$(ws_tree "$WK" c-1)"; WAF="$(ws_tree "$WK" a-foreign)"; WAR="$(ws_tree "$WK" a-roster)"
{
  printf 'workspace/v1|session=%s|name=a|path=%s|branch=wt/a|base=0|plan=none|at=2026-10-03T00:00:00Z\n' "$WKSID" "$WA1"
  printf 'workspace/v1|session=%s|name=b|path=%s|branch=wt/b|base=0|plan=none|at=2026-10-03T00:00:01Z\n' "$WKSID" "$WB1"
  printf 'workspace/v1|session=%s|name=a|path=%s|branch=wt/a2|base=0|plan=none|at=2026-10-03T00:00:02Z\n' "$WKSID" "$WA2"
  printf 'workspace/v1|session=someone-else|name=a|path=%s|branch=wt/x|base=0|plan=none|at=2026-10-03T00:00:03Z\n' "$WAF"
  # A line of ANOTHER schema naming `a` with a path, after a's last real line: a reader that
  # did not key on the schema would answer the a-roster tree below. Built by the roster writer
  # (tests/lib/roster-row.sh, as cross-gate §S17 requires) and given the path a workspace
  # line would carry.
  printf '%s|path=%s\n' "$(roster_row_fixture session="$WKSID" name=a)" "$WAR"
  printf 'workspace/v1|session=%s|name=e|branch=wt/e|base=0|plan=none|at=2026-10-03T00:00:04Z\n' "$WKSID"
  printf 'workspace/v1|session=%s|name=d|path=relative/d|branch=wt/d|base=0|plan=none|at=2026-10-03T00:00:05Z\n' "$WKSID"
  printf 'workspace/v1|session=%s|name=c|path=%s|branch=wt/c|base=0|plan=none|at=2026-10-03T00:00:06Z\r\n' "$WKSID" "$WC1"
} > "$WKF"

wk() { "$@"; echo "rc=$?"; }
expect_eq "fixture: every tree the lines name is one git lists" "6" \
  "$(git -C "$WK" worktree list --porcelain | /usr/bin/grep -c -E "^worktree ${WK}/\.worktrees/(a-1|b-1|a-2|c-1|a-foreign|a-roster)\$")"
expect_eq "fixture: the foreign-schema line naming a, with a path, is in the file" "1" \
  "$(/usr/bin/grep -c "^$(roster_row_schema)|.*|name=a|.*|path=${WAR}\$" "$WKF")"
expect_eq "the last line for a name answers"               "$(printf '%s\nrc=0' "$WA2")" "$(wk workspace_for_name "$WK" "$WKSID" a)"
expect_eq "another name answers its own"                   "$(printf '%s\nrc=0' "$WB1")" "$(wk workspace_for_name "$WK" "$WKSID" b)"
expect_eq "a CRLF line answers without the CR"             "$(printf '%s\nrc=0' "$WC1")" "$(wk workspace_for_name "$WK" "$WKSID" c)"
expect_eq "a relative path is not a recorded tree"         "rc=1" "$(wk workspace_for_name "$WK" "$WKSID" d)"
expect_eq "a line with no path is not a recorded tree"     "rc=1" "$(wk workspace_for_name "$WK" "$WKSID" e)"
expect_eq "a name nobody recorded has none"                "rc=1" "$(wk workspace_for_name "$WK" "$WKSID" z)"
expect_eq "an empty name has none"                        "rc=1" "$(wk workspace_for_name "$WK" "$WKSID" "")"
expect_eq "workspaces_of_session: this session's valid paths, in order" \
  "$(printf '%s\n%s\n%s\n%s\nrc=0' "$WA1" "$WB1" "$WA2" "$WC1")" "$(wk workspaces_of_session "$WK" "$WKSID")"
expect_eq "no file: workspace_for_name has none"           "rc=1" "$(wk workspace_for_name "$WK" no-file-session a)"
expect_eq "no file: workspaces_of_session has none"        "rc=1" "$(wk workspaces_of_session "$WK" no-file-session)"
expect_eq "a session id no file can be named for is refused" "rc=2" "$(wk workspace_for_name "$WK" "../tmp/x" a)"

# THE SYMLINK REFUSAL: the same bytes through a link are refused, not followed; the regular
# file above is the positive on the same reader.
WKL="$TMP/ws-reader-link"; mkdir -p "$WKL/.bionic/tmp"
cp "$WKF" "$TMP/ws-reader-target.state"
ln -s "$TMP/ws-reader-target.state" "$WKL/.bionic/tmp/workspaces-${WKSID}.state"
expect_eq "a symlinked workspace file is refused by workspace_for_name" "rc=2" "$(wk workspace_for_name "$WKL" "$WKSID" a)"
expect_eq "…and by workspaces_of_session" "rc=2" "$(wk workspaces_of_session "$WKL" "$WKSID")"
WKT="$TMP/ws-reader-tmplink"; mkdir -p "$WKT/.bionic"
ln -s "$WK/.bionic/tmp" "$WKT/.bionic/tmp"
expect_eq "a symlinked .bionic/tmp is refused" "rc=2" "$(wk workspace_for_name "$WKT" "$WKSID" a)"

section "Group 11b: a recorded path counts only when git lists it as a linked worktree (wave-25 T18, critic C1, A-orch-36)"
#
# The record file sits in `.bionic/tmp`, and a script the permission hook never sees can append
# to it (spec N7). A line naming the main checkout made `workspace_for_name` answer the main
# checkout, and the hook then granted a writer all of it. The rule is by place: a path counts
# only when `git worktree list` names it as a LINKED worktree of this repository, spelled as
# git spells it, and it resolves physically to that same spelling. Anything else is skipped,
# so an earlier true line for the name still answers. A yes is exact; the only error allowed
# is refusing something harmless (A-orch-29).
#
# THE PLANTED DEFECTS. The rule removed: every "skipped" row below answers the forged path.
# The rule by prefix (`<root>/.worktrees/`): the main checkout and its parent are still
# skipped, but the plain directory, the removed tree, the recreated directory, the symlink and
# the `..` spelling under `.worktrees/` answer, and the two trees under another parent are
# refused.

WG="$(new_repo "$TMP/ws-git")"; mkdir -p "$WG/.bionic/tmp"
WGSID="git-rule-session"
WGF="$WG/.bionic/tmp/workspaces-${WGSID}.state"
WGT="$(ws_tree "$WG" f-1)"
mkdir -p "$WG/trees" "$TMP/ws-elsewhere"
WGIN="$(ws_tree "$WG" g-1 "$WG/trees")"
WGOUT="$(ws_tree "$WG" g-2 "$TMP/ws-elsewhere")"
WGGONE="$(ws_tree "$WG" gone)"; git -C "$WG" worktree remove "$WGGONE" >/dev/null 2>&1
WGPRUNE="$(ws_tree "$WG" pruned)"; rm -rf "$WGPRUNE"; mkdir -p "$WGPRUNE"
WGSWAP="$(ws_tree "$WG" swapped)"; rm -rf "$WGSWAP"; ln -s "$WG" "$WGSWAP"
WGPLAIN="$WG/.worktrees/plain"; mkdir -p "$WGPLAIN"
WO="$(new_repo "$TMP/ws-other")"; WGFOREIGN="$(ws_tree "$WO" o-1)"
WGUPPER="$(printf '%s' "$WGT" | tr '[:lower:]' '[:upper:]')"

wg_line() {  # <name> <path> -> one workspace line of this session
  printf 'workspace/v1|session=%s|name=%s|path=%s|branch=wt/x|base=0|plan=none|at=2026-10-04T00:00:00Z\n' "$WGSID" "$1" "$2"
}

# The fixture, proven before it is read: git lists the true trees and the three it still
# carries (the recreated directory as prunable, the symlink as a live tree); it does not list
# the removed tree, the plain directory, the main checkout's parent or the other repository's.
WGLIST="$(git -C "$WG" worktree list --porcelain)"
expect_contains "fixture: git lists the true tree"                 "worktree $WGT"   "$WGLIST"
expect_contains "fixture: git lists the tree under trees/"         "worktree $WGIN"  "$WGLIST"
expect_contains "fixture: git lists the tree outside the root"     "worktree $WGOUT" "$WGLIST"
expect_contains "fixture: git still lists the recreated directory" "worktree $WGPRUNE" "$WGLIST"
expect_contains "fixture: …and calls it prunable"                  "prunable" "$WGLIST"
expect_contains "fixture: git still lists the symlinked tree"      "worktree $WGSWAP" "$WGLIST"
expect_absent   "fixture: git does not list the removed tree"      "worktree $WGGONE" "$WGLIST"
expect_absent   "fixture: git does not list the plain directory"   "worktree $WGPLAIN" "$WGLIST"
expect_absent   "fixture: git does not list the other repository's tree" "worktree $WGFOREIGN" "$WGLIST"
expect_true     "fixture: the removed tree's directory is gone"    test ! -e "$WGGONE"
expect_true     "fixture: the swapped tree is a symlink to main"   test -L "$WGSWAP"

# One forged line after one true line for the same name: the true tree still answers.
wg_skips() {  # <label> <forged path>
  { wg_line f "$WGT"; wg_line f "$2"; } > "$WGF"
  expect_eq "$1: skipped, the earlier true tree answers" "$(printf '%s\nrc=0' "$WGT")" "$(wk workspace_for_name "$WG" "$WGSID" f)"
}
wg_skips "a line naming the main checkout"                  "$WG"
wg_skips "a line naming the parent of the main checkout"    "${WG%/*}"
wg_skips "a line naming a real directory git does not list" "$WGPLAIN"
wg_skips "a line naming a tree that was removed"            "$WGGONE"
wg_skips "a line naming a removed tree's recreated directory (git: prunable)" "$WGPRUNE"
wg_skips "a line naming a symlink standing where a tree was" "$WGSWAP"
wg_skips "a line naming the true tree through .."           "$WGT/../f-1"
wg_skips "a line naming .worktrees itself"                  "$WGT/.."
wg_skips "a line naming the true tree in another letter case" "$WGUPPER"
wg_skips "a line naming the true tree with a trailing slash" "$WGT/"
wg_skips "a line naming another repository's linked worktree" "$WGFOREIGN"

# With only untrue lines the name has none: rc 1, never a path.
{ wg_line u "$WG"; wg_line u "${WG%/*}"; wg_line u "$WGPLAIN"; wg_line u "$WGSWAP"; } > "$WGF"
expect_eq "only untrue lines: the name has none (rc 1)" "rc=1" "$(wk workspace_for_name "$WG" "$WGSID" u)"
expect_eq "…and the session lists none (rc 1)" "rc=1" "$(wk workspaces_of_session "$WG" "$WGSID")"

# The positives that keep the rule from over-refusing: a tree under another parent counts,
# inside the root and outside it, each as git lists it.
{ wg_line g "$WGIN"; wg_line h "$WGOUT"; } > "$WGF"
expect_eq "a tree created under <root>/trees counts" "$(printf '%s\nrc=0' "$WGIN")" "$(wk workspace_for_name "$WG" "$WGSID" g)"
expect_eq "a tree created under a parent outside the root counts" "$(printf '%s\nrc=0' "$WGOUT")" "$(wk workspace_for_name "$WG" "$WGSID" h)"

# The lead's reader: only the true trees, in order.
{
  wg_line f "$WGT"; wg_line x "$WG"; wg_line g "$WGIN"; wg_line x "${WG%/*}"; wg_line x "$WGPLAIN"
  wg_line x "$WGGONE"; wg_line x "$WGPRUNE"; wg_line x "$WGSWAP"; wg_line x "$WGFOREIGN"
  wg_line x "$WGT/../f-1"; wg_line h "$WGOUT"
} > "$WGF"
expect_eq "workspaces_of_session lists only the trees git lists, in order" \
  "$(printf '%s\n%s\n%s\nrc=0' "$WGT" "$WGIN" "$WGOUT")" "$(wk workspaces_of_session "$WG" "$WGSID")"

# GIT IS ASKED ONCE PER ANSWER, never once per line, and not at all when no line could count.
# A `git` first on PATH counts its calls and runs the real one.
WGSHIM="$TMP/ws-git-shim"; mkdir -p "$WGSHIM"
printf '#!/bin/bash\nprintf x >> "%s"\nexec "%s" "$@"\n' "$WGSHIM/calls" "$(command -v git)" > "$WGSHIM/git"
chmod +x "$WGSHIM/git"
: > "$WGSHIM/calls"
WGOUT11="$(PATH="$WGSHIM:$PATH" wk workspaces_of_session "$WG" "$WGSID")"
expect_eq "through the counting git, the answer is the same three trees" \
  "$(printf '%s\n%s\n%s\nrc=0' "$WGT" "$WGIN" "$WGOUT")" "$WGOUT11"
expect_eq "…and git was asked once for eleven lines" "x" "$(cat "$WGSHIM/calls")"
: > "$WGSHIM/calls"
WGOUTZ="$(PATH="$WGSHIM:$PATH" wk workspace_for_name "$WG" "$WGSID" nobody)"
expect_eq "a name with no line has none" "rc=1" "$WGOUTZ"
expect_eq "…and asks git nothing" "" "$(cat "$WGSHIM/calls")"

# WHEN GIT CANNOT BE ASKED the reader never answers yes: the same line, naming a tree git does
# list for its own repository, under a root that is no repository, is refused (rc 2).
WGNR="$TMP/ws-no-repo"; mkdir -p "$WGNR/.bionic/tmp"
wg_line f "$WGT" > "$WGNR/.bionic/tmp/workspaces-${WGSID}.state"
{ wg_line f "$WGT"; } > "$WGF"
expect_eq "control: under its own repository the line answers" "$(printf '%s\nrc=0' "$WGT")" "$(wk workspace_for_name "$WG" "$WGSID" f)"
expect_eq "under a root git cannot read, workspace_for_name refuses (rc 2)" "rc=2" "$(wk workspace_for_name "$WGNR" "$WGSID" f)"
expect_eq "…and so does workspaces_of_session" "rc=2" "$(wk workspaces_of_session "$WGNR" "$WGSID")"
WGBROKEN="$TMP/ws-git-broken"; mkdir -p "$WGBROKEN"
printf '#!/bin/bash\nexit 1\n' > "$WGBROKEN/git"; chmod +x "$WGBROKEN/git"
expect_eq "with a git that fails, the reader refuses too (rc 2)" "rc=2" \
  "$(PATH="$WGBROKEN:$PATH" wk workspace_for_name "$WG" "$WGSID" f)"

# THE LAUNCH RECORDER'S READER (wave-26 T40). The launch recorder fills a plan row's worktree and
# base cells from this record, so it asks the same rule: the tree is the one workspace_for_name
# answers, and the base is the one on the last line naming that tree.
expect_true "workspace_record_for_name is defined" declare -F workspace_record_for_name
wg_line_b() {  # <name> <path> <base>
  printf 'workspace/v1|session=%s|name=%s|path=%s|branch=wt/x|base=%s|plan=none|at=2026-10-04T00:00:00Z\n' "$WGSID" "$1" "$2" "$3"
}
{ wg_line_b f "$WGT" aaaaaaaa; wg_line_b f "$WG" bbbbbbbb; } > "$WGF"
expect_eq "record: a forged line naming the main checkout is skipped, the true tree and its base answer" \
  "$(printf '%s\taaaaaaaa\nrc=0' "$WGT")" "$(wk workspace_record_for_name "$WG" "$WGSID" f)"
{ wg_line_b f "$WGIN" cccccccc; wg_line_b f "$WGT" dddddddd; } > "$WGF"
expect_eq "record: the last true line answers, with its own base" \
  "$(printf '%s\tdddddddd\nrc=0' "$WGT")" "$(wk workspace_record_for_name "$WG" "$WGSID" f)"
{ wg_line_b f "$WGT" eeeeeeee; wg_line_b g "$WGIN" ffffffff; wg_line_b f "$WGPLAIN" 99999999; } > "$WGF"
expect_eq "record: another name's line and an untrue line leave the true tree's base" \
  "$(printf '%s\teeeeeeee\nrc=0' "$WGT")" "$(wk workspace_record_for_name "$WG" "$WGSID" f)"
{ wg_line_b u "$WG" 11111111; wg_line_b u "$WGPLAIN" 22222222; } > "$WGF"
expect_eq "record: only untrue lines: none (rc 1)" "rc=1" "$(wk workspace_record_for_name "$WG" "$WGSID" u)"
expect_eq "record: under a root git cannot read, refused (rc 2)" "rc=2" "$(wk workspace_record_for_name "$WGNR" "$WGSID" f)"

# ---------------------------------------------------------------------------
# THE LANDING RULE (wave-26 T10, T31, D7, D19). A tree lands on its LAST stamped suite run when
# that run was green, on a clean tree, at its current head — and it must first contain what
# landed since only when that landed work touches a file the tree also changed (A-orch-26).
# The stamp is one line per suite-class run, appended to the tree's own git directory by the
# booking shim (T6); these arms write the lines by hand, in exactly the interface's shape.
stamp_file() { printf '%s/bionic-stamps' "$(git -C "$1" rev-parse --absolute-git-dir)"; }
stamp() {  # <tree> <head> <dirty> <rc>
  printf 'stamp/v1|head=%s|dirty=%s|rc=%s|at=2026-10-03T00:00:00Z|cmd=bash tests/one.test.sh\n' \
    "$2" "$3" "$4" >> "$(stamp_file "$1")"
}
green_stamp() { stamp "$1" "$(git -C "$1" rev-parse HEAD)" 0 0; }
# A file six lines long that two branches can each change on a different line and still merge
# cleanly, so what refuses an overlap is the landing rule and never a conflict.
shared_file() {  # <checkout> — commits shared.txt on the branch it sits on
  printf 'l1\nl2\nl3\nl4\nl5\nl6\n' > "$1/shared.txt"
  git -C "$1" add shared.txt && git -C "$1" commit --quiet -m "shared file"
}
set_line() {  # <checkout> <file> <line no> <text> — rewrites one line and commits it
  awk -v n="$3" -v t="$4" 'NR == n { $0 = t } { print }' "$1/$2" > "$1/$2.new" && mv "$1/$2.new" "$1/$2"
  git -C "$1" commit --quiet -am "$2 line $3"
}
# The record link resolves: a symlink at <tree>/.bionic that reaches the main root's state.
link_ok() { test -L "$1/.bionic" && test -f "$1/.bionic/docs/note.md"; }

section "§LAND-GREEN: a tree whose stamped run at its head is green lands, no full run asked (AC-3.1)"

LG="$(new_repo "$TMP/land-green")"
LGT="$(new_tree "$LG" green-arm)"
# The extractor is proved on real output before anything reads through it: the stamp file is
# the tree's PRIVATE git directory, not the shared one, and a written line reads back.
expect_match "the stamp file sits in the tree's own git directory" \
  "${LG}/.git/worktrees/green-arm/bionic-stamps" "$(stamp_file "$LGT")"
stamp "$LGT" "0000000000000000000000000000000000000000" 0 1
green_stamp "$LGT"
expect_match "the last stamp line reads back in the interface's shape" \
  "stamp/v1|head=$(git -C "$LGT" rev-parse HEAD)|dirty=0|rc=0|at=*|cmd=bash tests/one.test.sh" \
  "$(tail -n 1 "$(stamp_file "$LGT")")"
OUTLG="$(worktree_land "$LGT" wave/fixture)"; RCLG=$?
expect_match "a green run of one suite at the tree's head lands (an earlier red line is history)" \
  "spawn-worktree: LANDED branch=green-arm onto=wave/fixture *" "$OUTLG"
expect_eq "that land exits 0" "0" "$RCLG"

# A tree whose contract runs no suite has no stamp file at all, and needs none.
LGD="$(new_tree "$LG" docs-arm)"
expect_false "a docs-only tree has no stamp file" test -e "$(stamp_file "$LGD")"
expect_match "and it lands without one" \
  "spawn-worktree: LANDED branch=docs-arm onto=wave/fixture *" "$(worktree_land "$LGD" wave/fixture)"

section "§LAND-CURRENT: behind on a file it also changed is not-current, behind only on other files lands; a stale green run, stale-proof (AC-5.3)"

LC="$(new_repo "$TMP/land-current")"
shared_file "$LC"

# BEHIND ONLY ON OTHER FILES. Two trees side by side; the first's landing touches first.txt,
# which the second never changed, so the second lands on its own green run without merging.
LCA="$(new_tree "$LC" first)"
LCN="$(new_tree "$LC" apart)"
green_stamp "$LCA"; green_stamp "$LCN"
expect_match "the first of two side-by-side trees lands" \
  "spawn-worktree: LANDED branch=first *" "$(worktree_land "$LCA" wave/fixture)"
expect_eq "fixture: the second now lacks the head it lands onto" "1" \
  "$(git -C "$LCN" merge-base --is-ancestor wave/fixture HEAD; echo $?)"
OUTLN="$(worktree_land "$LCN" wave/fixture)"; RCLN=$?
expect_match "a tree lacking only a commit that touches other files lands" \
  "spawn-worktree: LANDED branch=apart onto=wave/fixture *" "$OUTLN"
expect_eq "that land exits 0" "0" "$RCLN"

# BEHIND ON A FILE IT ALSO CHANGED. Both trees change shared.txt, on lines far apart: the merge
# would go through cleanly and produce a shared.txt neither tree's green run ever saw.
LCC="$(new_tree "$LC" third)";  set_line "$LCC" shared.txt 1 "third"
LCB="$(new_tree "$LC" second)"; set_line "$LCB" shared.txt 6 "second"
green_stamp "$LCC"; green_stamp "$LCB"
expect_match "a tree changing shared.txt lands" \
  "spawn-worktree: LANDED branch=third *" "$(worktree_land "$LCC" wave/fixture)"
LCREFS="$(refs_of "$LC")"
OUTLC="$(worktree_land "$LCB" wave/fixture)"; RCLC=$?
expect_match "the second, green but lacking a landed commit on a file it changed, is refused not-current" \
  "spawn-worktree: REFUSED reason=not-current branch=second onto=wave/fixture *" "$OUTLC"
expect_match "the refusal names the file both changed" "* files=shared.txt *" "$OUTLC"
expect_no_match "and not the file only the tree changed" "*second.txt*" "$OUTLC"
expect_match "the refusal names the head it lacks" "*onto_head=$(git -C "$LC" rev-parse wave/fixture) *" "$OUTLC"
expect_match "and names the fix in one line" \
  "*merge wave/fixture into the tree, re-run its suites, land again" "$OUTLC"
expect_eq   "that refusal exits 2" "2" "$RCLC"
expect_eq   "no ref moved" "$LCREFS" "$(refs_of "$LC")"
expect_true "the tree survives" test -d "$LCB"

# The fix, step one: merge the landed branch in. The tree is now current, but its green run
# was on the head before the merge.
git -C "$LCB" merge --quiet --no-edit wave/fixture >/dev/null 2>&1
expect_eq "the tree now contains the branch it lands onto" "0" \
  "$(git -C "$LCB" merge-base --is-ancestor wave/fixture HEAD; echo $?)"
LCREFS="$(refs_of "$LC")"   # the merge moved the tree's own branch; nothing moves from here
OUTLH="$(worktree_land "$LCB" wave/fixture)"; RCLH=$?
expect_match "a green run on an earlier head is refused stale-proof, naming the head" \
  "spawn-worktree: REFUSED reason=stale-proof why=head *" "$OUTLH"
expect_match "naming both heads" \
  "*stamp_head=*head=$(git -C "$LCB" rev-parse HEAD)*" "$OUTLH"
expect_match "and the fix" "*re-run the tree's suites at its head, land again" "$OUTLH"
expect_eq   "that refusal exits 2" "2" "$RCLH"
expect_eq   "no ref moved" "$LCREFS" "$(refs_of "$LC")"

# On a dirty tree.
stamp "$LCB" "$(git -C "$LCB" rev-parse HEAD)" 2 0
expect_match "a green run at the head on a dirty tree is refused stale-proof, naming dirt" \
  "spawn-worktree: REFUSED reason=stale-proof why=dirty dirty=2 *" "$(worktree_land "$LCB" wave/fixture)"
# Red.
stamp "$LCB" "$(git -C "$LCB" rev-parse HEAD)" 0 1
expect_match "a red run at the head on a clean tree is refused stale-proof, naming red" \
  "spawn-worktree: REFUSED reason=stale-proof why=red rc=1 *" "$(worktree_land "$LCB" wave/fixture)"
# A last line that is not a stamp at all is not proof either.
printf 'garbage\n' >> "$(stamp_file "$LCB")"
expect_match "a last line that is no stamp is refused stale-proof, unreadable" \
  "spawn-worktree: REFUSED reason=stale-proof why=unreadable *" "$(worktree_land "$LCB" wave/fixture)"
: > "$(stamp_file "$LCB")"
expect_match "an empty stamp file is refused stale-proof, unreadable" \
  "spawn-worktree: REFUSED reason=stale-proof why=unreadable *" "$(worktree_land "$LCB" wave/fixture)"

# THE COMMAND'S TEXT NEVER SPEAKS FOR THE RUN (review 2 F2). `cmd=` is the last field and free
# text; the reader stops at it, whatever follows. The first line is the review's probe input.
LCH="$(git -C "$LCB" rev-parse HEAD)"
printf 'stamp/v1|head=%s|dirty=0|rc=1|at=t|cmd=a|rc=0\n' "$LCH" >> "$(stamp_file "$LCB")"
expect_eq "fixture: the last line carries rc=0 after cmd=" "cmd=a|rc=0" \
  "$(tail -n 1 "$(stamp_file "$LCB")" | sed 's/.*|cmd=/cmd=/')"
expect_match "a red run whose command text carries |rc=0 is refused stale-proof, red" \
  "spawn-worktree: REFUSED reason=stale-proof why=red rc=1 *" "$(worktree_land "$LCB" wave/fixture)"
printf 'stamp/v1|head=%s|dirty=3|rc=0|at=t|cmd=a|dirty=0\n' "$LCH" >> "$(stamp_file "$LCB")"
expect_match "a dirty run whose command text carries |dirty=0 is refused stale-proof, dirty" \
  "spawn-worktree: REFUSED reason=stale-proof why=dirty dirty=3 *" "$(worktree_land "$LCB" wave/fixture)"
printf 'stamp/v1|head=%s|dirty=0|rc=0|at=t|cmd=a|head=%s\n' "0000000000000000000000000000000000000000" "$LCH" \
  >> "$(stamp_file "$LCB")"
expect_match "a run on another head whose command text carries the tree's head is refused stale-proof, head" \
  "spawn-worktree: REFUSED reason=stale-proof why=head stamp_head=0000000000000000000000000000000000000000 *" \
  "$(worktree_land "$LCB" wave/fixture)"
# A key twice BEFORE cmd= is no line the shim writes: which one holds is not a guess to make.
printf 'stamp/v1|head=%s|dirty=0|rc=1|rc=0|at=t|cmd=a\n' "$LCH" >> "$(stamp_file "$LCB")"
expect_match "a key given twice before cmd= is refused stale-proof, unreadable" \
  "spawn-worktree: REFUSED reason=stale-proof why=unreadable *" "$(worktree_land "$LCB" wave/fixture)"
expect_eq   "no ref moved across all of them" "$LCREFS" "$(refs_of "$LC")"
# The fix, step two: re-run at the head, green, clean. The command text carries a red rc and a
# dirty count; the reader stopped at cmd=, so the run's own fields decide. The arm discriminates.
printf 'stamp/v1|head=%s|dirty=0|rc=0|at=t|cmd=bash tests/one.test.sh|rc=1|dirty=9\n' "$LCH" \
  >> "$(stamp_file "$LCB")"
expect_match "the same tree lands once its last run is green, clean, at its head" \
  "spawn-worktree: LANDED branch=second onto=wave/fixture *" "$(worktree_land "$LCB" wave/fixture)"

# A RENAME OR A DELETION COUNTS ITS OLD PATH (A-T31.1). The tree renames shared.txt; a landing
# edits it. Git's merge would carry the edit into the renamed file, untested by the tree.
LCR="$(new_tree "$LC" renamer)"
git -C "$LCR" mv shared.txt moved.txt; git -C "$LCR" commit --quiet -m "rename shared"
LCE="$(new_tree "$LC" editor)"; set_line "$LCE" shared.txt 3 "editor"
green_stamp "$LCR"; green_stamp "$LCE"
expect_match "a tree editing shared.txt lands" \
  "spawn-worktree: LANDED branch=editor *" "$(worktree_land "$LCE" wave/fixture)"
expect_match "a tree that renamed it away, lacking that landing, is refused not-current on the old path" \
  "spawn-worktree: REFUSED reason=not-current branch=renamer * files=shared.txt *" "$(worktree_land "$LCR" wave/fixture)"

# A LANDED CHANGE A LATER LANDING REVERTED IS NOT BROUGHT IN (A-T31.3). The merge leaves the
# tree's shared.txt as the tree tested it, so the tree lands without merging first.
LCV="$(new_tree "$LC" reverted)"; set_line "$LCV" shared.txt 2 "reverted"; green_stamp "$LCV"
set_line "$LC" shared.txt 4 "landed"; git -C "$LC" revert --quiet --no-edit HEAD >/dev/null 2>&1
expect_eq "fixture: the branch's last commit reverts a change to shared.txt" "shared.txt line 4" \
  "$(git -C "$LC" log -1 --format=%s 'wave/fixture^')"
expect_match "a tree lacking a change to its file that was reverted since lands" \
  "spawn-worktree: LANDED branch=reverted onto=wave/fixture *" "$(worktree_land "$LCV" wave/fixture)"

# THE HEAD MOVES BETWEEN THE READ AND THE MERGE (review 2 F7). The busy-suite scan is the last
# act before the merge; standing in for it, a landing onto the same branch arrives in that window.
LR="$(new_repo "$TMP/land-race")"
shared_file "$LR"
LRT="$(new_tree "$LR" racer)"; set_line "$LRT" shared.txt 1 "racer"; green_stamp "$LRT"
LRB="$(git -C "$LR" rev-parse wave/fixture)"
OUTLR="$(_wt_busy_suite() { set_line "$LR" shared.txt 6 "arrived"; return 1; }
         worktree_land "$LRT" wave/fixture)"; RCLR=$?
expect_ne "fixture: the branch moved inside the window" "$LRB" "$(git -C "$LR" rev-parse wave/fixture)"
expect_match "a head that moved onto a file the tree changed is refused not-current" \
  "spawn-worktree: REFUSED reason=not-current branch=racer * files=shared.txt *" "$OUTLR"
expect_match "naming the head it moved to" "*onto_head=$(git -C "$LR" rev-parse wave/fixture) *" "$OUTLR"
expect_eq   "that refusal exits 2" "2" "$RCLR"
expect_eq   "nothing merged: the tree's head is not in the branch" "1" \
  "$(git -C "$LR" merge-base --is-ancestor racer wave/fixture; echo $?)"
expect_true "the tree survives" test -d "$LRT"
# The other direction: a head that moves only on other files lands, onto the head it moved to.
LRO="$(new_tree "$LR" bystander)"; green_stamp "$LRO"
OUTLO="$(_wt_busy_suite() { set_line "$LR" shared.txt 3 "arrived again"; return 1; }
         worktree_land "$LRO" wave/fixture)"
expect_match "a head that moved only on other files still lands" \
  "spawn-worktree: LANDED branch=bystander onto=wave/fixture *" "$OUTLO"
expect_eq "the merge sits on the commit that arrived" "shared.txt line 3" \
  "$(git -C "$LR" log -1 --format=%s 'wave/fixture^1')"
# THE TREE'S OWN BRANCH MOVES AFTER ITS HEAD WAS JUDGED (review 7 F9). Landing the judged head
# and removing the tree would leave the newer commit unlanded on the branch with nothing said, so
# the merge is undone and the land refused, naming both heads; the tree, its commit and <onto>
# are as they were.
LRM="$(new_tree "$LR" mover)"; green_stamp "$LRM"; LRMH="$(git -C "$LRM" rev-parse HEAD)"
LRMO="$(git -C "$LR" rev-parse wave/fixture)"; LRMW="$(trees_of "$LR")"
OUTLM="$(_wt_busy_suite() { echo late > "$LRM/late.txt"; git -C "$LRM" add late.txt; git -C "$LRM" commit --quiet -m late; return 1; }
         worktree_land "$LRM" wave/fixture)"; RCLM=$?
LRMT="$(git -C "$LR" rev-parse mover)"
expect_ne "fixture: the tree's branch moved inside the window" "$LRMH" "$LRMT"
expect_match "a branch that moved past its judged head is refused branch-moved, naming both heads" \
  "spawn-worktree: REFUSED reason=branch-moved branch=mover judged=${LRMH} branch_head=${LRMT} — *" "$OUTLM"
expect_match "the refusal names its fix" "*re-run the tree's suites at its head, land again*" "$OUTLM"
expect_eq   "that refusal exits 2" "2" "$RCLM"
expect_eq   "the undo leaves the onto branch's head where it was" "$LRMO" "$(git -C "$LR" rev-parse wave/fixture)"
expect_true "the tree survives" test -d "$LRM"
expect_eq   "the tree's branch keeps its newer commit" "$LRMT" "$(git -C "$LR" rev-parse mover)"
expect_eq   "the worktree list is as it was" "$LRMW" "$(trees_of "$LR")"
expect_eq   "the onto checkout is clean" "" "$(git -C "$LR" status --porcelain --untracked-files=no)"
# The fix: a green run at the new head, then the same land goes through and takes that head.
green_stamp "$LRM"
expect_match "with a green run at its new head the tree lands" \
  "spawn-worktree: LANDED branch=mover onto=wave/fixture *" "$(worktree_land "$LRM" wave/fixture)"
expect_eq "and the merge took the newer commit" "$LRMT" "$(git -C "$LR" rev-parse 'wave/fixture^2')"

# THE HEAD MOVES AFTER ITS LAST READ, AS `git merge` STARTS (review 7 F8). A `git` function in the
# land's subshell commits onto the branch when the merge is called, which is after every read the
# land makes and before git's own. The merge commit's first parent is then not the head judged:
# the merge is undone and the land refused, and nothing else is changed.
land_with_arrival() {  # <tree> <line> <text> [on-top] — lands <tree>; run it inside $(…), it defines git()
  local arr_done="" arr_line="$2" arr_text="$3" arr_top="${4:-}"
  git() {
    if [ -z "$arr_done" ] && [ "${3:-}" = merge ] && [ "${4:-}" = --no-ff ]; then
      arr_done=1
      awk -v n="$arr_line" -v t="$arr_text" 'NR == n { $0 = t } { print }' "$LR/shared.txt" > "$LR/shared.new" \
        && mv "$LR/shared.new" "$LR/shared.txt" && command git -C "$LR" commit --quiet -am "arrived at merge"
      command git "$@" || return
      # With [on-top], another writer also commits on top of the merge before the land reads it.
      [ -z "$arr_top" ] || command git -C "$LR" commit --quiet --allow-empty -m "on top of the merge"
      return 0
    fi
    command git "$@"
  }
  worktree_land "$1" wave/fixture
}
LRF="$(new_tree "$LR" late-racer)"; set_line "$LRF" shared.txt 1 "late racer"; green_stamp "$LRF"
LRFJ="$(git -C "$LR" rev-parse wave/fixture)"; LRFB="$(git -C "$LR" rev-parse late-racer)"
LRFW="$(trees_of "$LR")"
OUTLF="$(land_with_arrival "$LRF" 6 "arrived at merge")"; RCLF=$?
LRFA="$(git -C "$LR" rev-parse wave/fixture)"
expect_eq "fixture: the arrival is the onto branch's head, one commit past the judged head" "$LRFJ" \
  "$(git -C "$LR" rev-parse 'wave/fixture^1')"
expect_match "a merge made onto a head that moved after the last read is refused onto-moved" \
  "spawn-worktree: REFUSED reason=onto-moved branch=late-racer onto=wave/fixture judged=${LRFJ} merged_onto=${LRFA} — *" "$OUTLF"
expect_match "the refusal names its fix" "*land again to judge the head wave/fixture holds now*" "$OUTLF"
expect_eq   "that refusal exits 2" "2" "$RCLF"
expect_eq   "the undo leaves the onto branch on the arrival, not on the merge" "arrived at merge" \
  "$(git -C "$LR" log -1 --format=%s wave/fixture)"
expect_true "the tree survives" test -d "$LRF"
expect_eq   "the tree's branch is where it was" "$LRFB" "$(git -C "$LR" rev-parse late-racer)"
expect_eq   "the worktree list is as it was" "$LRFW" "$(trees_of "$LR")"
expect_eq   "the onto checkout is clean" "" "$(git -C "$LR" status --porcelain --untracked-files=no)"
expect_eq   "and its shared.txt is the arrival's" "$(git -C "$LR" show wave/fixture:shared.txt)" "$(cat "$LR/shared.txt")"
# Landing again judges the head that arrived: it changed shared.txt, which the tree changed too.
expect_match "landing again judges the new head and refuses the overlap" \
  "spawn-worktree: REFUSED reason=not-current branch=late-racer onto=wave/fixture onto_head=${LRFA} files=shared.txt *" \
  "$(worktree_land "$LRF" wave/fixture)"
# An arrival on a file the tree never changed is refused the same way, and landing again lands.
LRG="$(new_tree "$LR" late-bystander)"; green_stamp "$LRG"
expect_match "a merge made onto an arrival on another file is refused onto-moved too" \
  "spawn-worktree: REFUSED reason=onto-moved branch=late-bystander *" "$(land_with_arrival "$LRG" 5 "arrived elsewhere")"
expect_match "landing again lands, onto the arrival" \
  "spawn-worktree: LANDED branch=late-bystander onto=wave/fixture *" "$(worktree_land "$LRG" wave/fixture)"
expect_eq "the merge sits on the commit that arrived" "arrived at merge" \
  "$(git -C "$LR" log -1 --format=%s 'wave/fixture^1')"
# AN UNDO GIT REFUSES IS SAID, never passed off as a refusal that changed nothing.
LRU="$(new_tree "$LR" undo-refused)"; green_stamp "$LRU"; LRUH="$(git -C "$LRU" rev-parse HEAD)"
OUTLU="$(_wt_undo_merge() { return 1; }; land_with_arrival "$LRU" 4 "arrived again")"; RCLU=$?
expect_match "an undo that fails says the merge stands and how to undo it" \
  "spawn-worktree: REFUSED reason=onto-moved branch=undo-refused * merge=$(git -C "$LR" rev-parse wave/fixture) undo=failed — the merge stands: reset wave/fixture to $(git -C "$LR" rev-parse 'wave/fixture^1') in ${LR} by hand, *" "$OUTLU"
expect_eq   "that refusal exits 2" "2" "$RCLU"
expect_eq   "and the merge it names is the tree's judged head" "$LRUH" "$(git -C "$LR" rev-parse 'wave/fixture^2')"
expect_true "the tree survives" test -d "$LRU"
# A COMMIT ON TOP OF THE MERGE IS NEVER RESET AWAY. The head the land reads back is then not its
# own merge, so the undo declines and says so; the other writer's commit stays the head.
LRP="$(new_tree "$LR" under-a-commit)"; green_stamp "$LRP"
OUTLP="$(land_with_arrival "$LRP" 2 "arrived under" on-top)"
expect_match "a land whose merge has a commit on top refuses, undo=failed" \
  "spawn-worktree: REFUSED reason=onto-moved branch=under-a-commit * undo=failed — *" "$OUTLP"
expect_eq "the commit on top is still the onto branch's head" "on top of the merge" \
  "$(git -C "$LR" log -1 --format=%s wave/fixture)"

section "§LAND-KEEP: after each refusal the tree's record link still resolves (AC-9.1)"
#
# The link is dropped only just before `git worktree remove`. Each arm proves the link
# resolves before the land, refuses, proves it still resolves, then lands the same tree.

LK="$(new_repo "$TMP/land-keep")"; shared_file "$LK"
keep_tree() {  # <branch> -> tree path, with its record link and a green stamp at its head
  local t; t="$(new_tree "$LK" "$1")"
  ln -s "${LK}/.bionic" "$t/.bionic"; green_stamp "$t"; printf '%s' "$t"
}

KD="$(keep_tree keep-dirty)"; echo scratch > "$KD/notes.txt"
expect_true "dirty-tree arm: the link resolves before the land" link_ok "$KD"
expect_match "dirty-tree is refused" "spawn-worktree: REFUSED reason=dirty-tree*" "$(worktree_land "$KD" wave/fixture)"
expect_true "after dirty-tree, the link still resolves" link_ok "$KD"
rm -f "$KD/notes.txt"

KN="$(keep_tree keep-nothing)"
git -C "$LK" merge --quiet --no-ff -m "already merged" keep-nothing
expect_true "nothing-to-land arm: the link resolves before the land" link_ok "$KN"
expect_match "nothing-to-land is refused" "spawn-worktree: REFUSED reason=nothing-to-land*" "$(worktree_land "$KN" wave/fixture)"
expect_true "after nothing-to-land, the link still resolves" link_ok "$KN"

KC="$(keep_tree keep-current)"; set_line "$KC" shared.txt 1 "keep"; green_stamp "$KC"
KCO="$(keep_tree keep-current-other)"; set_line "$KCO" shared.txt 6 "other"; green_stamp "$KCO"
worktree_land "$KCO" wave/fixture >/dev/null
expect_true "not-current arm: the link resolves before the land" link_ok "$KC"
expect_match "not-current is refused" "spawn-worktree: REFUSED reason=not-current*" "$(worktree_land "$KC" wave/fixture)"
expect_true "after not-current, the link still resolves" link_ok "$KC"
git -C "$KC" merge --quiet --no-edit wave/fixture >/dev/null 2>&1

expect_true "stale-proof arm: the link resolves before the land" link_ok "$KC"
expect_match "stale-proof is refused" "spawn-worktree: REFUSED reason=stale-proof*" "$(worktree_land "$KC" wave/fixture)"
expect_true "after stale-proof, the link still resolves" link_ok "$KC"
green_stamp "$KC"

KO="$(keep_tree keep-onto)"
echo "half-done" >> "$LK/file.txt"
expect_true "onto-checkout-dirty arm: the link resolves before the land" link_ok "$KO"
expect_match "onto-checkout-dirty is refused" "spawn-worktree: REFUSED reason=onto-checkout-dirty*" "$(worktree_land "$KO" wave/fixture)"
expect_true "after onto-checkout-dirty, the link still resolves" link_ok "$KO"
git -C "$LK" checkout --quiet -- file.txt

KS="$(keep_tree keep-suite)"
make_runner "$LK"
expect_true "a stand-in runner started in the keep fixture" start_runner "$LK" "tests/run.sh"
expect_true "suite-running arm: the link resolves before the land" link_ok "$KS"
expect_match "suite-running is refused" "spawn-worktree: REFUSED reason=suite-running*" "$(worktree_land "$KS" wave/fixture)"
expect_true "after suite-running, the link still resolves" link_ok "$KS"
stop_runner

# Every refused tree above lands once its cause is gone, and only then is its link dropped.
# None of them changed a file another landing touched, so each lands on its own green run
# without merging first (KC took the not-current fix above).
for t in "$KD" "$KC" "$KO" "$KS"; do
  expect_match "the refused tree ${t##*/} lands once its cause is gone" \
    "spawn-worktree: LANDED branch=${t##*/} *" "$(worktree_land "$t" wave/fixture)"
  expect_false "and its tree, link included, is gone" test -e "$t"
done
expect_true "the state the links pointed at survived every land" test -f "${LK}/.bionic/docs/note.md"

# WHY THE OLD DROP SAT BEFORE THE DIRTY CHECK. A project that ignores `.bionic/` (directory
# shape only), or not at all, sees the link as untracked work: `?? .bionic` in status, and
# `git worktree remove` refuses over it. The dirty check passes exactly that one entry; the
# drop just before the removal satisfies git.
LU="$(new_repo "$TMP/land-unignored")"
printf '.bionic/\n.worktrees/\n' > "$LU/.gitignore"
git -C "$LU" commit --quiet -am "ignore the directory shape only"
LUT="$(new_tree "$LU" unignored)"
ln -s "${LU}/.bionic" "$LUT/.bionic"; green_stamp "$LUT"
expect_eq "git reads the link as untracked work in this project" "?? .bionic" "$(git -C "$LUT" status --porcelain)"
echo scratch > "$LUT/notes.txt"
expect_match "another untracked file beside it is still dirty" \
  "spawn-worktree: REFUSED reason=dirty-tree*" "$(worktree_land "$LUT" wave/fixture)"
expect_true "and the link survives that refusal" link_ok "$LUT"
rm -f "$LUT/notes.txt"
expect_match "with only the link untracked, the tree lands" \
  "spawn-worktree: LANDED branch=unignored onto=wave/fixture *" "$(worktree_land "$LUT" wave/fixture)"
expect_false "and the tree is gone" test -e "$LUT"

# A removal git refuses after the merge leaves the tree alive: its link is put back.
LUL="$(new_tree "$LU" locked)"
ln -s "${LU}/.bionic" "$LUL/.bionic"; green_stamp "$LUL"
git -C "$LU" worktree lock "$LUL"
expect_match "a locked tree merges and then its removal is refused" \
  "spawn-worktree: REFUSED reason=worktree-remove-refused*" "$(worktree_land "$LUL" wave/fixture)"
expect_true "after worktree-remove-refused, the link resolves again" link_ok "$LUL"
git -C "$LU" worktree unlock "$LUL"

finish
