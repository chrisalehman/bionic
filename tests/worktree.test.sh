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
  "spawn-worktree: LANDED branch=alpha onto=wave/fixture checkout=${H} merge=* removed=${HT} proofs=none" "$OUTH"
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
  "spawn-worktree: LANDED branch=withalias onto=wave/fixture checkout=${LA} merge=* removed=${LAT} proofs=none" "$OUTLA"
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
  "spawn-worktree: LANDED branch=wt/20-T1 onto=wave/20-demo checkout=${WWAVE} merge=* removed=${WT1} proofs=none" "$OUTW"
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
# THE LANDING RULE (wave-26 T10, T31, D7, D19, T61). A tree lands when, for every suite stamped at
# its current head, the NEWEST stamp of that suite is green on a clean tree — and it must first contain what
# landed since only when that landed work touches a file the tree also changed (A-orch-26).
# The stamp is one line per suite-class run, appended to the tree's own git directory by the
# booking shim (T6); these arms write the lines by hand, in exactly the interface's shape: since
# T61 the shim names the suite a run was for (`suites=`, before `cmd=`), and these lines stand for
# runs of one suite, tests/one.test.sh, so they name it as the shim now does. A line with no
# `suites=` (an older shim's) is §LAND-SUITES's row (g).
stamp_file() { printf '%s/bionic-stamps' "$(git -C "$1" rev-parse --absolute-git-dir)"; }
stamp() {  # <tree> <head> <dirty> <rc>
  printf 'stamp/v1|head=%s|dirty=%s|rc=%s|at=2026-10-03T00:00:00Z|suites=one.test.sh|cmd=bash tests/one.test.sh\n' \
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
  "stamp/v1|head=$(git -C "$LGT" rev-parse HEAD)|dirty=0|rc=0|at=*|suites=one.test.sh|cmd=bash tests/one.test.sh" \
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
printf 'stamp/v1|head=%s|dirty=0|rc=1|at=t|suites=one.test.sh|cmd=a|rc=0\n' "$LCH" >> "$(stamp_file "$LCB")"
expect_eq "fixture: the last line carries rc=0 after cmd=" "cmd=a|rc=0" \
  "$(tail -n 1 "$(stamp_file "$LCB")" | sed 's/.*|cmd=/cmd=/')"
expect_match "a red run whose command text carries |rc=0 is refused stale-proof, red" \
  "spawn-worktree: REFUSED reason=stale-proof why=red rc=1 *" "$(worktree_land "$LCB" wave/fixture)"
printf 'stamp/v1|head=%s|dirty=3|rc=0|at=t|suites=one.test.sh|cmd=a|dirty=0\n' "$LCH" >> "$(stamp_file "$LCB")"
expect_match "a dirty run whose command text carries |dirty=0 is refused stale-proof, dirty" \
  "spawn-worktree: REFUSED reason=stale-proof why=dirty dirty=3 *" "$(worktree_land "$LCB" wave/fixture)"
# Since T61 every line at the head is read, so this row needs a file holding none: a line on
# another head is history beside a line at the head, and only a file with NO line at the head is
# refused why=head.
: > "$(stamp_file "$LCB")"
printf 'stamp/v1|head=%s|dirty=0|rc=0|at=t|suites=one.test.sh|cmd=a|head=%s\n' "0000000000000000000000000000000000000000" "$LCH" \
  >> "$(stamp_file "$LCB")"
expect_match "a run on another head whose command text carries the tree's head is refused stale-proof, head" \
  "spawn-worktree: REFUSED reason=stale-proof why=head stamp_head=0000000000000000000000000000000000000000 *" \
  "$(worktree_land "$LCB" wave/fixture)"
# A key twice BEFORE cmd= is no line the shim writes: which one holds is not a guess to make.
printf 'stamp/v1|head=%s|dirty=0|rc=1|rc=0|at=t|suites=one.test.sh|cmd=a\n' "$LCH" >> "$(stamp_file "$LCB")"
expect_match "a key given twice before cmd= is refused stale-proof, unreadable" \
  "spawn-worktree: REFUSED reason=stale-proof why=unreadable *" "$(worktree_land "$LCB" wave/fixture)"
expect_eq   "no ref moved across all of them" "$LCREFS" "$(refs_of "$LC")"
# The fix, step two: re-run at the head, green, clean. The command text carries a red rc and a
# dirty count; the reader stopped at cmd=, so the run's own fields decide. The arm discriminates.
printf 'stamp/v1|head=%s|dirty=0|rc=0|at=t|suites=one.test.sh|cmd=bash tests/one.test.sh|rc=1|dirty=9\n' "$LCH" \
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

section "§LAND-UNDO: the undo never drops a commit it did not make, and the land names its own merge (review 11 B1, S1, N2)"

# Every land below runs in this repository, whose checkout <LU> holds wave/fixture. The seam is a
# `git` function in the land's subshell: an arrival commits onto the branch just before the land
# reads what its checkout holds for `git merge` (the onto-moved case; on a land that makes no such
# read, as `git merge` is called), then [action] runs once the merge has returned, then the
# [n]-th git call after that is preceded by another writer's commit, its sha kept in $FORCED; an
# [n] of `<subcommand>@<k>` picks the k-th call of that git subcommand instead. The calls are
# counted in files, since most of them run inside a command substitution's subshell. The
# switch actions move the checkout off wave/fixture: before the land's read (preswitch, onto
# ${LR_TO:-lu-side}; predetach; switchback, which also returns to wave/fixture once the merge is
# made), in the instant between that read and `git merge` (instant, onto lu-side), or after the
# merge (side: onto lu-side; detach; sidewt: onto lu-side, with wave/fixture then checked out in
# the worktree $LUWT). merged has someone else merge the tree's head onto wave/fixture before the
# read, instantmerged in the instant between the read and `git merge`.
LU="$(new_repo "$TMP/land-undo")"; shared_file "$LU"
FORCED="$TMP/land-undo-forced.sha"; CALLS="$TMP/land-undo-calls"; LUWT="$TMP/land-undo-other-wt"
land_raced() {  # <tree> <arrival text> [action: none|touch|ontop|stage|misread|preswitch|predetach|switchback|instant|instantmerged|merged|side|detach|sidewt] [n] — lands <tree>
  local lr_calls lr_sub lr_tree="$1" lr_text="$2" lr_act="${3:-none}" lr_n="${4:-0}"
  rm -f "$FORCED" "$CALLS.pre" "$CALLS.merged"; echo 0 > "$CALLS"; echo 0 > "$CALLS.sub"
  git() {
    if [ -e "$CALLS.merged" ]; then
      lr_calls=$(( $(cat "$CALLS") + 1 )); echo "$lr_calls" > "$CALLS"
      lr_sub=""
      if [ "${3:-}" = "${lr_n%@*}" ] && [ "$lr_n" != "${lr_n%@*}" ]; then
        lr_sub=$(( $(cat "$CALLS.sub") + 1 )); echo "$lr_sub" > "$CALLS.sub"
      fi
      if { [ "$lr_calls" = "$lr_n" ] && [ ! -e "$FORCED" ]; } || { [ "$lr_n" = gap ] && [ ! -e "$FORCED" ] \
          && { [ "${3:-}" = reset ] || [ "${3:-}" = update-ref ]; }; } \
          || { [ "$lr_sub" = "${lr_n#*@}" ] && [ ! -e "$FORCED" ]; }; then
        echo "$lr_calls" > "$LU/forced.txt"; command git -C "$LU" add forced.txt
        command git -C "$LU" commit --quiet -m "another writer's commit" && command git -C "$LU" rev-parse HEAD > "$FORCED"
      fi
      command git "$@"; return
    fi
    if [ ! -e "$CALLS.pre" ] && { { [ "${3:-}" = rev-parse ] && [ "${5:-}" = --symbolic-full-name ]; } \
        || { [ "${3:-}" = merge ] && [ "${4:-}" = --no-ff ]; }; }; then
      touch "$CALLS.pre"
      case "$lr_act" in
        misread|instant|instantmerged) : ;;
        preswitch|switchback) command git -C "$LU" checkout --quiet "${LR_TO:-lu-side}" ;;
        predetach) command git -C "$LU" checkout --quiet --detach ;;
        merged) command git -C "$LU" merge --quiet --no-ff -m "merge ${lr_tree##*/} (by someone else)" \
                  "$(command git -C "$lr_tree" rev-parse HEAD)" ;;
        *) awk -v t="$lr_text" 'NR == 4 { $0 = t } { print }' "$LU/shared.txt" > "$LU/shared.new" \
             && mv "$LU/shared.new" "$LU/shared.txt" && command git -C "$LU" commit --quiet -am "$lr_text" ;;
      esac
    fi
    if [ "${3:-}" = merge ] && [ "${4:-}" = --no-ff ]; then
      case "$lr_act" in
        instant) command git -C "$LU" checkout --quiet lu-side ;;
        instantmerged) command git -C "$LU" merge --quiet --no-ff -m "merge ${lr_tree##*/} (by someone else)" \
                         "$(command git -C "$lr_tree" rev-parse HEAD)" ;;
      esac
      command git "$@" || return
      touch "$CALLS.merged"
      case "$lr_act" in
        touch) echo "edited during the land" >> "$LU/${lr_tree##*/}.txt" ;;
        stage) echo "staged during the land" >> "$LU/file.txt"; command git -C "$LU" add file.txt ;;
        ontop|misread) command git -C "$LU" merge --quiet --no-ff -m "merge other (land)" other-land ;;
        side) command git -C "$LU" checkout --quiet lu-side ;;
        detach) command git -C "$LU" checkout --quiet --detach ;;
        switchback) command git -C "$LU" checkout --quiet wave/fixture ;;
        sidewt) command git -C "$LU" checkout --quiet lu-side
                command git -C "$LU" worktree add --quiet "$LUWT" wave/fixture >/dev/null 2>&1 ;;
      esac
      return 0
    fi
    command git "$@"
  }
  worktree_land "$lr_tree" wave/fixture
}
# The commits of <list> that no branch of <repo> reaches, one per line.
lost_commits() {  # <repo> <list>
  local all; all="$(git -C "$1" rev-list --branches)"
  printf '%s\n' "$2" | while read -r c; do
    [ -n "$c" ] && ! printf '%s\n' "$all" | grep -qx "$c" && printf '%s\n' "$c"
  done
  return 0
}
# Every branch of <repo> with the commit it holds, and the branches of such a list that no longer
# reach the commit they held: moved back past it, moved off it, or gone.
branch_tips() { git -C "$1" for-each-ref --format='%(refname) %(objectname)' refs/heads; }
branches_dropped() {  # <repo> <tips>
  printf '%s\n' "$2" | while read -r r c; do
    [ -n "$r" ] && ! git -C "$1" merge-base --is-ancestor "$c" "$r" 2>/dev/null && printf '%s\n' "$r"
  done
  return 0
}
# Back to a clean checkout on wave/fixture between arms; whatever a land left is read before this runs.
lu_clean() {
  git -C "$LU" reset --quiet --hard; git -C "$LU" clean --quiet -fd; git -C "$LU" checkout --quiet wave/fixture
}
# The branch the switch actions move the checkout to: wave/fixture plus one commit of its own.
lu_side() {
  git -C "$LU" branch -f lu-side "$(git -C "$LU" commit-tree -p wave/fixture -m "side work" \
    "$(git -C "$LU" rev-parse 'wave/fixture^{tree}')")"
}
# The tree another land merges in the instant after this one's merge: one commit, its own file.
lu_other() {  # <file> — branch other-land: wave/fixture plus <file>
  git -C "$LU" branch -f other-land "$(git -C "$LU" commit-tree -p wave/fixture -m "other work" \
    "$( { git -C "$LU" ls-tree wave/fixture
          printf '100644 blob %s\t%s\n' "$(echo other | git -C "$LU" hash-object -w --stdin)" "$1"; } \
        | git -C "$LU" mktree)")"
}

# The extractor is proved before anything reads an empty answer from it: a commit no branch holds
# is listed, and a branch head is not.
LUD="$(git -C "$LU" commit-tree -p wave/fixture -m dangling "$(git -C "$LU" rev-parse 'wave/fixture^{tree}')")"
expect_eq "lost_commits lists a commit no branch holds" "$LUD" "$(lost_commits "$LU" "$LUD")"
expect_eq "…and not one a branch holds" "" "$(lost_commits "$LU" "$(git -C "$LU" rev-parse wave/fixture)")"

# B1, THE OLD GAP. A commit lands in the checkout just before the undo moves the branch back: the
# undo must decline, and that commit stays the branch's head.
LUG="$(new_tree "$LU" gap-racer)"; green_stamp "$LUG"; LUGB="$(git -C "$LU" rev-list --branches)"
OUTLUG="$(land_raced "$LUG" "arrived before the gap" none gap)"
expect_true "fixture: the other writer's commit was made in the gap" test -s "$FORCED"
expect_eq   "that commit is still the onto branch's head" "$(cat "$FORCED" 2>/dev/null)" "$(git -C "$LU" rev-parse wave/fixture)"
expect_eq   "no commit is lost, that one included" "" "$(lost_commits "$LU" "$LUGB
$(cat "$FORCED" 2>/dev/null)")"
expect_match "and the land says the merge stands under it" \
  "spawn-worktree: REFUSED reason=onto-moved branch=gap-racer * undo=failed — the merge stands under a later commit: *" "$OUTLUG"
lu_clean

# AFTER ANY OUTCOME OF THE UNDO, NO COMMIT IS LOST. Another writer commits before the n-th git call
# the land makes after its merge, for every n the land reaches; the undo is done (the land made no
# n-th call), declined (the commit came first), or failed half-way (touch: a file the merge
# brought in is edited in the checkout, so the checkout cannot follow the branch back). Each time,
# every commit that existed before the land, and the other writer's, is reachable from a branch.
# AND THE LINE IS TRUE (review 15 F1): "undone" and "nothing to undo" are said only when the
# onto branch does not hold the tree's file, "stands" only when it does, and a commit that
# arrived during the undo is named only when the branch holds the file inside it.
LUOUT=""; LULOST=""; LUFIRED=0; LUFALSE=""
for lu_mode in none touch; do
  for lu_n in 1 2 3 4 5 6 7 8 9 10 11 12; do
    lu_t="$(new_tree "$LU" "any-${lu_mode}-${lu_n}")"; green_stamp "$lu_t"
    lu_before="$(git -C "$LU" rev-list --branches)"
    lu_out="$(land_raced "$lu_t" "arrived ${lu_mode} ${lu_n}" "$lu_mode" "$lu_n")"
    [ -s "$FORCED" ] && { LUFIRED=$((LUFIRED + 1)); lu_before="${lu_before}
$(cat "$FORCED")"; }
    LULOST="${LULOST}$(lost_commits "$LU" "$lu_before" | sed "s/^/${lu_mode}-${lu_n} lost /")"
    lu_has="$(git -C "$LU" ls-tree --name-only wave/fixture "any-${lu_mode}-${lu_n}.txt")"
    case "$lu_out" in
      *"during the undo"*) LUOUT="${LUOUT} ${lu_mode}:arrived"; lu_true="${lu_has:+yes}" ;;
      *"the merge stands"*) LUOUT="${LUOUT} ${lu_mode}:failed"; lu_true="${lu_has:+yes}" ;;
      *"nothing to undo"*) LUOUT="${LUOUT} ${lu_mode}:failed"; lu_true="${lu_has:-yes}" ;;
      *"the merge is undone"*) LUOUT="${LUOUT} ${lu_mode}:undone"; lu_true="${lu_has:-yes}" ;;
      *) LUOUT="${LUOUT} ${lu_mode}:other"; lu_true=yes ;;
    esac
    [ "$lu_true" = yes ] || LUFALSE="${LUFALSE} ${lu_mode}-${lu_n}"
    lu_clean
  done
done
expect_match "the undo was done in some arms" "* none:undone*" "$LUOUT"
expect_match "…declined in some" "* none:failed*" "$LUOUT"
expect_match "…and failed half-way in others" "* touch:failed*" "$LUOUT"
expect_match "…and in some a commit arrived during the undo and was named" "* none:arrived*" "$LUOUT"
expect_no_match "every arm ended in one of those four" "*:other*" "$LUOUT"
expect_ne "the other writer committed in some arms" "0" "$LUFIRED"
expect_eq "and no commit that existed is unreachable from a branch, after any of them" "" "$LULOST"
expect_eq "and no arm's line says something the onto branch contradicts" "" "$LUFALSE"

# THE UNDO THAT FAILS HALF-WAY puts the branch back on the merge, and the checkout with it: a file
# the merge brought in was edited during the land, so the checkout cannot follow the branch back.
LUT="$(new_tree "$LU" touched)"; green_stamp "$LUT"; LUTH="$(git -C "$LUT" rev-parse HEAD)"
OUTLUT="$(land_raced "$LUT" "arrived under an edit" touch)"
LUTM="$(git -C "$LU" rev-parse wave/fixture)"
expect_eq   "fixture: the onto branch holds the land's merge" "$LUTH" "$(git -C "$LU" rev-parse 'wave/fixture^2')"
expect_match "the land says the merge stands and how to undo it" \
  "spawn-worktree: REFUSED reason=onto-moved branch=touched * merge=${LUTM} undo=failed — the merge stands: reset wave/fixture to $(git -C "$LU" rev-parse "${LUTM}^1") in ${LU} by hand, *" "$OUTLUT"
expect_eq   "the checkout's index is the merge's" "" "$(git -C "$LU" diff --cached --name-only)"
expect_eq   "and the edit is kept, unstaged" " M touched.txt" "$(git -C "$LU" status --porcelain --untracked-files=no)"
lu_clean

# S1(a), THE LAND NAMES ITS OWN MERGE. Another land merges on top in the instant after this one's
# merge, before it is read back; this land was judged on the head it merged onto and lands, naming
# its merge, not the other's.
lu_other other-a.txt
LUM="$(new_tree "$LU" misread)"; green_stamp "$LUM"; LUMH="$(git -C "$LUM" rev-parse HEAD)"
OUTLUM="$(land_raced "$LUM" "" misread)"
LUMM="$(git -C "$LU" rev-parse 'wave/fixture^1')"
expect_eq "fixture: the other land's merge is the head, on top of this land's" "$LUMH" "$(git -C "$LU" rev-parse "${LUMM}^2")"
expect_match "the land lands and names its own merge" \
  "spawn-worktree: LANDED branch=misread onto=wave/fixture checkout=${LU} merge=${LUMM} *" "$OUTLUM"
expect_eq "the other land's merge is still the head" "merge other (land)" "$(git -C "$LU" log -1 --format=%s wave/fixture)"
lu_clean

# S1(b), THE FIX PRINTED WHEN A COMMIT SITS ON TOP. An arrival makes this land's merge onto-moved,
# and another land merges on top before the undo: the undo declines, and the line prints the
# revert, which keeps the other land; a reset to the first parent would drop it.
lu_other other-b.txt
LUP="$(new_tree "$LU" under-a-land)"; green_stamp "$LUP"; LUPH="$(git -C "$LUP" rev-parse HEAD)"
OUTLUP="$(land_raced "$LUP" "arrived under a land" ontop)"
LUPM="$(git -C "$LU" rev-parse 'wave/fixture^1')"; LUPO="$(git -C "$LU" rev-parse wave/fixture)"
expect_eq "fixture: this land's merge sits under the other land's" "$LUPH" "$(git -C "$LU" rev-parse "${LUPM}^2")"
expect_match "the line names this land's merge and prints the revert" \
  "spawn-worktree: REFUSED reason=onto-moved branch=under-a-land * merge=${LUPM} undo=failed — the merge stands under a later commit: git -C ${LU} revert -m 1 ${LUPM}, *" "$OUTLUP"
expect_no_match "and prints no reset" "*reset*" "$OUTLUP"
LUPFIX="$(printf '%s' "$OUTLUP" | sed -n 's/.*: \(git -C [^ ]* revert -m 1 [0-9a-f]*\),.*/\1/p')"
expect_eq "fixture: the printed fix reads back" "git -C ${LU} revert -m 1 ${LUPM}" "$LUPFIX"
# shellcheck disable=SC2086 # the printed command is run as an operator would type it
GIT_EDITOR=: command $LUPFIX >/dev/null 2>&1
expect_true "following it keeps the other land's merge" git -C "$LU" merge-base --is-ancestor "$LUPO" wave/fixture
expect_eq "…and takes this land's work off the branch" "" "$(git -C "$LU" ls-tree --name-only wave/fixture under-a-land.txt)"
expect_eq "…while the other land's work stays" "other-b.txt" "$(git -C "$LU" ls-tree --name-only wave/fixture other-b.txt)"
lu_clean

# N2, A CHANGE STAGED DURING THE LAND. A successful undo keeps it, staged.
LUS="$(new_tree "$LU" stager)"; green_stamp "$LUS"
OUTLUS="$(land_raced "$LUS" "arrived under a stage" stage)"
expect_match "fixture: the merge was undone" "spawn-worktree: REFUSED reason=onto-moved branch=stager * — the merge is undone and the tree kept; *" "$OUTLUS"
expect_eq "the onto branch is back on the arrival" "arrived under a stage" "$(git -C "$LU" log -1 --format=%s wave/fixture)"
expect_eq "the staged change is still staged" "M  file.txt" "$(git -C "$LU" status --porcelain --untracked-files=no)"
expect_eq "…with its content" "staged during the land" "$(tail -n 1 "$LU/file.txt")"
expect_false "and the tree's file left the checkout with the merge" test -e "$LU/stager.txt"
lu_clean

# REVIEW 15 F1, A COMMIT DURING THE UNDO. Another writer commits in the checkout after the swap
# moved the branch back and before the checkout follows: that commit sits on the first parent
# but was made from the merge's tree, so the task's file is on the branch inside it, unjudged.
# The land must say so, naming the commit, and never "undone".
LUB="$(new_tree "$LU" arrival-b)"; green_stamp "$LUB"; LUBB="$(git -C "$LU" rev-list --branches)"
OUTLUB="$(land_raced "$LUB" "arrived before the checkout follows" none update-index@1)"
LUBF="$(cat "$FORCED" 2>/dev/null)"
expect_true "fixture: the other writer's commit was made between the swap and the checkout" test -n "$LUBF"
expect_eq   "that commit is the onto branch's head" "$LUBF" "$(git -C "$LU" rev-parse wave/fixture)"
expect_eq   "fixture: and it carries the tree's file" "arrival-b.txt" "$(git -C "$LU" ls-tree --name-only wave/fixture arrival-b.txt)"
expect_match "the land refuses undo=failed and names the commit that arrived" \
  "spawn-worktree: REFUSED reason=onto-moved branch=arrival-b * undo=failed arrived=${LUBF} — commit ${LUBF} arrived on wave/fixture during the undo, made while ${LU} held merge * so it may carry the task's changes, unjudged; *" "$OUTLUB"
expect_no_match "and never says the merge is undone" "*the merge is undone*" "$OUTLUB"
expect_eq   "no commit is lost, that one included" "" "$(lost_commits "$LU" "$LUBB
${LUBF}")"
expect_eq   "the checkout has the tree's file taken out, staged, as the line says" "D  arrival-b.txt" \
  "$(git -C "$LU" status --porcelain --untracked-files=no)"
git -C "$LU" commit --quiet -m "take the unjudged task out"
expect_eq   "committing that takes the tree's file off the branch" "" "$(git -C "$LU" ls-tree --name-only wave/fixture arrival-b.txt)"
expect_eq   "…and keeps the other writer's" "forced.txt" "$(git -C "$LU" ls-tree --name-only wave/fixture forced.txt)"
expect_true "the tree survives" test -d "$LUB"
lu_clean

# A commit made after the checkout followed, from the first parent's tree, changes no file the
# merge changed: it carries nothing of the task, and the undo is said as done. The undo's re-read
# is the third rev-parse after the merge: the tree's tip, the merge's second parent, then it.
LUA="$(new_tree "$LU" arrival-after)"; green_stamp "$LUA"; LUAB="$(git -C "$LU" rev-list --branches)"
OUTLUA="$(land_raced "$LUA" "arrived before the re-read" none rev-parse@3)"
LUAF="$(cat "$FORCED" 2>/dev/null)"
expect_true "fixture: the other writer's commit was made after the checkout followed" test -n "$LUAF"
expect_eq   "that commit is the onto branch's head" "$LUAF" "$(git -C "$LU" rev-parse wave/fixture)"
expect_eq   "fixture: and it carries its own file" "forced.txt" "$(git -C "$LU" ls-tree --name-only wave/fixture forced.txt)"
expect_eq   "…and not the tree's" "" "$(git -C "$LU" ls-tree --name-only wave/fixture arrival-after.txt)"
expect_match "the land says the merge is undone" \
  "spawn-worktree: REFUSED reason=onto-moved branch=arrival-after * — the merge is undone and the tree kept; *" "$OUTLUA"
expect_eq   "no commit is lost, that one included" "" "$(lost_commits "$LU" "$LUAB
${LUAF}")"
lu_clean

# The same commit after the checkout refused to follow: the swap is not reversed, since the branch
# moved, and the line names the commit rather than "nothing to undo".
LUC="$(new_tree "$LU" arrival-c)"; green_stamp "$LUC"; LUCB="$(git -C "$LU" rev-list --branches)"
OUTLUC="$(land_raced "$LUC" "arrived before the reverse swap" touch update-ref@2)"
LUCF="$(cat "$FORCED" 2>/dev/null)"
expect_true "fixture: the other writer's commit was made before the reverse swap" test -n "$LUCF"
expect_eq   "that commit is the onto branch's head" "$LUCF" "$(git -C "$LU" rev-parse wave/fixture)"
expect_eq   "fixture: and it carries the tree's file" "arrival-c.txt" "$(git -C "$LU" ls-tree --name-only wave/fixture arrival-c.txt)"
expect_match "the land refuses undo=failed and names the commit that arrived" \
  "spawn-worktree: REFUSED reason=onto-moved branch=arrival-c * undo=failed arrived=${LUCF} — commit ${LUCF} arrived on wave/fixture during the undo, made while ${LU} held merge * so it may carry the task's changes, unjudged; *" "$OUTLUC"
expect_no_match "and never says there is nothing to undo" "*nothing to undo*" "$OUTLUC"
expect_eq   "no commit is lost, that one included" "" "$(lost_commits "$LU" "$LUCB
${LUCF}")"
expect_eq   "the edit made during the land is kept" " M arrival-c.txt" "$(git -C "$LU" status --porcelain --untracked-files=no)"
lu_clean

# REVIEW 15 F2 AND REVIEW 16 S1, THE CHECKOUT LEFT ONTO AFTER THE MERGE. The checkout is detached,
# or on another branch, when the undo runs. No checkout holds wave/fixture, so its tree is nobody's
# working files and the compare-and-swap alone undoes the land's merge; lu-side never moves.
lu_side; LUSS="$(git -C "$LU" rev-parse lu-side)"
for lu_where in side detach; do
  lu_t="$(new_tree "$LU" "left-${lu_where}")"; green_stamp "$lu_t"; lu_tips="$(branch_tips "$LU")"
  lu_out="$(land_raced "$lu_t" "arrived before a ${lu_where}" "$lu_where")"
  lu_m="$(git -C "$LU" log -g --grep="^merge left-${lu_where} (land)\$" --format=%H -1 HEAD)"
  expect_eq "${lu_where}: fixture: the land's merge was made" "$(git -C "$lu_t" rev-parse HEAD)" "$(git -C "$LU" rev-parse "${lu_m}^2")"
  expect_match "${lu_where}: the land says the merge is undone" \
    "spawn-worktree: REFUSED reason=onto-moved branch=left-${lu_where} * — the merge is undone and the tree kept; *" "$lu_out"
  expect_eq "${lu_where}: wave/fixture is back on the arrival, the merge's first parent" \
    "$(git -C "$LU" rev-parse "${lu_m}^1")" "$(git -C "$LU" rev-parse wave/fixture)"
  expect_eq "${lu_where}: …and lu-side is where it was" "$LUSS" "$(git -C "$LU" rev-parse lu-side)"
  expect_eq "${lu_where}: every branch still reaches the commit it held" "" "$(branches_dropped "$LU" "$lu_tips")"
  lu_clean
done

# REVIEW 15 F2, THE ADVICE WHEN THE UNDO CANNOT MOVE ONTO. The checkout went to lu-side after the
# merge and another worktree checked wave/fixture out: moving it would move that checkout's branch
# under its files, so the undo declines, and the advice moves wave/fixture itself, by
# compare-and-swap, never a reset typed in a checkout where it would move something else.
LUV="$(new_tree "$LU" left-sidewt)"; green_stamp "$LUV"
OUTLUV="$(land_raced "$LUV" "arrived before a sidewt" sidewt)"
LUVM="$(git -C "$LU" rev-parse wave/fixture)"; LUVP="$(git -C "$LU" rev-parse 'wave/fixture^1')"
expect_eq "fixture: the onto branch holds the land's merge" "$(git -C "$LUV" rev-parse HEAD)" "$(git -C "$LU" rev-parse 'wave/fixture^2')"
expect_eq "fixture: …and another worktree holds the onto branch" "refs/heads/wave/fixture" "$(git -C "$LUWT" symbolic-ref HEAD 2>/dev/null)"
expect_match "the advice names the checkout's state and moves wave/fixture by compare-and-swap" \
  "spawn-worktree: REFUSED reason=onto-moved branch=left-sidewt * merge=${LUVM} undo=failed — the merge stands and ${LU} is on lu-side, not on wave/fixture, so move the branch itself: git -C ${LU} update-ref refs/heads/wave/fixture ${LUVP} ${LUVM}, *" "$OUTLUV"
expect_no_match "and prints no reset" "*reset*" "$OUTLUV"
LUVFIX="$(printf '%s' "$OUTLUV" | sed -n 's/.*: \(git -C [^ ]* update-ref [^ ]* [0-9a-f]* [0-9a-f]*\),.*/\1/p')"
expect_eq "fixture: the printed fix reads back" "git -C ${LU} update-ref refs/heads/wave/fixture ${LUVP} ${LUVM}" "$LUVFIX"
# shellcheck disable=SC2086 # the printed command is run as an operator would type it
command $LUVFIX >/dev/null 2>&1
expect_eq "following it puts wave/fixture back on the first parent" "$LUVP" "$(git -C "$LU" rev-parse wave/fixture)"
expect_eq "…and leaves lu-side where it was" "$LUSS" "$(git -C "$LU" rev-parse lu-side)"
git -C "$LU" worktree remove --force "$LUWT" >/dev/null 2>&1
lu_clean

# REVIEW 15 F3, THE MERGE WENT ELSEWHERE. The checkout is switched to another branch just before
# `git merge`, so the merge lands there. The land finds it there, undoes it there by the same
# compare-and-swap, and says where it went; wave/fixture never moved.
lu_side; LUSS="$(git -C "$LU" rev-parse lu-side)"
LUH="$(new_tree "$LU" switched)"; green_stamp "$LUH"; LUHJ="$(git -C "$LU" rev-parse wave/fixture)"; lu_tips="$(branch_tips "$LU")"
OUTLUH="$(land_raced "$LUH" "" preswitch)"
LUHM="$(git -C "$LU" log -g --grep='^merge switched (land)$' --format=%H -1 lu-side)"
expect_eq   "fixture: the merge went onto lu-side" "$(git -C "$LUH" rev-parse HEAD)" "$(git -C "$LU" rev-parse "${LUHM}^2")"
expect_match "the land refuses onto-switched, naming where the merge went and that it is undone there" \
  "spawn-worktree: REFUSED reason=onto-switched branch=switched onto=wave/fixture checkout=${LU} merged_into=lu-side merge=${LUHM} — the merge is undone on lu-side and the tree kept; check out wave/fixture in ${LU}, land again" "$OUTLUH"
expect_eq   "lu-side is back where it was" "$LUSS" "$(git -C "$LU" rev-parse lu-side)"
expect_eq   "wave/fixture never moved" "$LUHJ" "$(git -C "$LU" rev-parse wave/fixture)"
expect_eq   "every branch still reaches the commit it held" "" "$(branches_dropped "$LU" "$lu_tips")"
expect_eq   "the checkout is clean" "" "$(git -C "$LU" status --porcelain --untracked-files=no)"
expect_true "the tree survives" test -d "$LUH"
lu_clean
expect_match "landing again from wave/fixture lands" \
  "spawn-worktree: LANDED branch=switched onto=wave/fixture *" "$(worktree_land "$LUH" wave/fixture)"

# REVIEW 16 B1, THE LAND UNDOES ONLY A MERGE IT MADE ITSELF. The checkout is switched, before the
# land's merge, to a branch that already holds a --no-ff merge of the same task head, made by
# someone else: `git merge` makes nothing ("Already up to date"), and the land must neither claim
# that older merge nor undo it, whether it sits at the branch's tip or deeper in its chain.
# The extractor first: a branch moved off the commit it held is listed, and one that kept it is not.
git -C "$LU" branch -f lu-probe wave/fixture; lu_tips="$(branch_tips "$LU")"
git -C "$LU" branch -f lu-probe "$(git -C "$LU" commit-tree -p wave/fixture -m other 'wave/fixture^{tree}')"
expect_eq "branches_dropped is silent for a branch that moved forward" "" "$(branches_dropped "$LU" "$lu_tips")"
git -C "$LU" branch -f lu-probe "$(git -C "$LU" commit-tree -m root 'wave/fixture^{tree}')"
expect_eq "…and lists one moved off the commit it held" "refs/heads/lu-probe" "$(branches_dropped "$LU" "$lu_tips")"
git -C "$LU" branch -D lu-probe >/dev/null
for lu_where in tip deep; do
  lu_t="$(new_tree "$LU" "older-${lu_where}")"; green_stamp "$lu_t"; lu_h="$(git -C "$lu_t" rev-parse HEAD)"
  lu_o="$(git -C "$LU" commit-tree -p wave/fixture -p "$lu_h" -m "merge older-${lu_where} (earlier, by someone else)" "${lu_h}^{tree}")"
  [ "$lu_where" = deep ] && lu_o="$(git -C "$LU" commit-tree -p "$lu_o" -m "on top of the earlier merge" "${lu_h}^{tree}")"
  git -C "$LU" branch -f lu-older "$lu_o"; lu_tips="$(branch_tips "$LU")"; lu_j="$(git -C "$LU" rev-parse wave/fixture)"
  lu_out="$(LR_TO=lu-older land_raced "$lu_t" "" preswitch)"
  expect_eq "${lu_where}: fixture: the checkout went to lu-older" "refs/heads/lu-older" "$(git -C "$LU" symbolic-ref HEAD)"
  expect_match "${lu_where}: the land says the checkout already held the head on lu-older, git merge made nothing, and nothing is undone" \
    "spawn-worktree: REFUSED reason=merge-unproven branch=older-${lu_where} onto=wave/fixture checkout=${LU} was_on=lu-older was_at=${lu_o} — ${LU}'s HEAD already held ${lu_h} when git merge ran, so it made no merge, and nothing is undone; check out wave/fixture in ${LU}, land again" "$lu_out"
  expect_eq "${lu_where}: lu-older still holds the earlier merge, at its tip" "$lu_o" "$(git -C "$LU" rev-parse lu-older)"
  expect_eq "${lu_where}: wave/fixture never moved" "$lu_j" "$(git -C "$LU" rev-parse wave/fixture)"
  expect_eq "${lu_where}: every branch still reaches the commit it held" "" "$(branches_dropped "$LU" "$lu_tips")"
  expect_true "${lu_where}: the tree survives" test -d "$lu_t"
  lu_clean
done

# The head merged onto wave/fixture itself by someone else, just before the land's merge: the
# land's `git merge` makes nothing, and the land must not take that merge for its own.
LUN="$(new_tree "$LU" noop-onto)"; green_stamp "$LUN"; LUNH="$(git -C "$LUN" rev-parse HEAD)"
OUTLUN="$(land_raced "$LUN" "" merged)"
LUNO="$(git -C "$LU" rev-parse wave/fixture)"; lu_tips="$(branch_tips "$LU")"
expect_eq "fixture: someone else's merge of the head is wave/fixture's head" "$LUNH" "$(git -C "$LU" rev-parse 'wave/fixture^2')"
expect_eq "fixture: …and its message is not the land's" "merge noop-onto (by someone else)" "$(git -C "$LU" log -1 --format=%s wave/fixture)"
expect_match "the land refuses: the checkout already held the head on wave/fixture, git merge made nothing, nothing is undone" \
  "spawn-worktree: REFUSED reason=merge-unproven branch=noop-onto onto=wave/fixture checkout=${LU} was_on=wave/fixture was_at=${LUNO} — ${LU}'s HEAD already held ${LUNH} when git merge ran, so it made no merge, and nothing is undone; land again" "$OUTLUN"
expect_true "the tree survives" test -d "$LUN"
expect_match "landing again says there is nothing to land" \
  "spawn-worktree: REFUSED reason=nothing-to-land branch=noop-onto *" "$(worktree_land "$LUN" wave/fixture)"
expect_eq "and wave/fixture still holds the other merge" "$LUNO" "$(git -C "$LU" rev-parse wave/fixture)"
expect_eq "every branch still reaches the commit it held" "" "$(branches_dropped "$LU" "$lu_tips")"
lu_clean

# REVIEW 16 S1, A DETACHED CHECKOUT. Detached before the land's merge, the merge is made on the
# detached HEAD, which no branch holds: there is no branch to move, so nothing is undone and the
# line says where the merge is and what to do.
LUF="$(new_tree "$LU" detached-pre)"; green_stamp "$LUF"; LUFJ="$(git -C "$LU" rev-parse wave/fixture)"; lu_tips="$(branch_tips "$LU")"
OUTLUF="$(land_raced "$LUF" "" predetach)"
LUFM="$(git -C "$LU" rev-parse HEAD)"
expect_false "fixture: the checkout is detached" git -C "$LU" symbolic-ref -q HEAD
expect_eq "fixture: …on the land's merge of the head onto wave/fixture" "$(git -C "$LUF" rev-parse HEAD) ${LUFJ}" \
  "$(git -C "$LU" rev-parse "${LUFM}^2") $(git -C "$LU" rev-parse "${LUFM}^1")"
expect_match "the land says the merge is on the detached HEAD, nothing is undone, and how to land" \
  "spawn-worktree: REFUSED reason=onto-detached branch=detached-pre onto=wave/fixture checkout=${LU} merge=${LUFM} — the merge is on ${LU}'s detached HEAD and no branch holds it, so nothing is undone; check out wave/fixture in ${LU} (the merge then belongs to no branch), land again" "$OUTLUF"
expect_eq "wave/fixture never moved" "$LUFJ" "$(git -C "$LU" rev-parse wave/fixture)"
expect_eq "every branch still reaches the commit it held" "" "$(branches_dropped "$LU" "$lu_tips")"
lu_clean
expect_match "checked out on wave/fixture again, the tree lands" \
  "spawn-worktree: LANDED branch=detached-pre onto=wave/fixture *" "$(worktree_land "$LUF" wave/fixture)"

# REVIEW 16 S1, SWITCHED AND BACK. The checkout is on lu-side for the merge and back on
# wave/fixture before the land reads it back: the merge stands on lu-side, which no checkout holds
# now, and the land undoes it there by compare-and-swap.
lu_side; LUSS="$(git -C "$LU" rev-parse lu-side)"
LUK="$(new_tree "$LU" switchback)"; green_stamp "$LUK"; LUKJ="$(git -C "$LU" rev-parse wave/fixture)"; lu_tips="$(branch_tips "$LU")"
OUTLUK="$(land_raced "$LUK" "" switchback)"
LUKM="$(git -C "$LU" log -g --grep='^merge switchback (land)$' --format=%H -1 lu-side)"
expect_eq "fixture: the merge went onto lu-side" "$(git -C "$LUK" rev-parse HEAD)" "$(git -C "$LU" rev-parse "${LUKM}^2")"
expect_eq "fixture: …and the checkout is back on wave/fixture" "refs/heads/wave/fixture" "$(git -C "$LU" symbolic-ref HEAD)"
expect_match "the land refuses onto-switched and says the merge is undone on lu-side" \
  "spawn-worktree: REFUSED reason=onto-switched branch=switchback onto=wave/fixture checkout=${LU} merged_into=lu-side merge=${LUKM} — the merge is undone on lu-side and the tree kept; check out wave/fixture in ${LU}, land again" "$OUTLUK"
expect_eq "lu-side is back where it was" "$LUSS" "$(git -C "$LU" rev-parse lu-side)"
expect_eq "wave/fixture never moved" "$LUKJ" "$(git -C "$LU" rev-parse wave/fixture)"
expect_eq "the checkout is clean" "" "$(git -C "$LU" status --porcelain --untracked-files=no)"
expect_eq "every branch still reaches the commit it held" "" "$(branches_dropped "$LU" "$lu_tips")"
lu_clean

# THE INSTANT BETWEEN THE LAND'S READ AND `git merge`. The checkout moves to lu-side after the land
# read it on wave/fixture: the merge git makes is not on the commit the land read, so it is not
# provably the land's. Nothing is undone, and the line names where the checkout is and that a
# merge of the head there is unjudged.
lu_side; LUSS="$(git -C "$LU" rev-parse lu-side)"
LUI="$(new_tree "$LU" instant)"; green_stamp "$LUI"; LUIH="$(git -C "$LUI" rev-parse HEAD)"
LUIJ="$(git -C "$LU" rev-parse wave/fixture)"; lu_tips="$(branch_tips "$LU")"
OUTLUI="$(land_raced "$LUI" "" instant)"
LUIM="$(git -C "$LU" rev-parse lu-side)"
expect_eq "fixture: git merge merged the head onto lu-side" "$LUIH $LUSS" \
  "$(git -C "$LU" rev-parse "${LUIM}^2") $(git -C "$LU" rev-parse "${LUIM}^1")"
expect_match "the land refuses merge-unproven, naming what it read, where the checkout is, and what is unjudged" \
  "spawn-worktree: REFUSED reason=merge-unproven branch=instant onto=wave/fixture checkout=${LU} was_on=wave/fixture was_at=${LUIJ} now_on=lu-side now_at=${LUIM} — wave/fixture holds no merge of ${LUIH} made past ${LUIJ}, where ${LU} stood just before git merge, so no merge git made is provably this land's, and nothing is undone; if ${LUIM} holds ${LUIH}, that merge is unjudged: take it out by hand, then check out wave/fixture in ${LU}, land again" "$OUTLUI"
expect_eq "wave/fixture never moved" "$LUIJ" "$(git -C "$LU" rev-parse wave/fixture)"
expect_eq "every branch still reaches the commit it held" "" "$(branches_dropped "$LU" "$lu_tips")"
expect_true "the tree survives" test -d "$LUI"
lu_clean

# THE SAME HEAD MERGED IN THAT INSTANT. Someone else merges the tree's head onto wave/fixture after
# the land read it and before `git merge` runs: `git merge` makes nothing, and the merge past the
# commit the land read is not the land's. Only git's own "Already up to date" tells the two apart.
LUJ="$(new_tree "$LU" instant-merged)"; green_stamp "$LUJ"; LUJH="$(git -C "$LUJ" rev-parse HEAD)"
LUJJ="$(git -C "$LU" rev-parse wave/fixture)"; lu_tips="$(branch_tips "$LU")"
OUTLUJ="$(land_raced "$LUJ" "" instantmerged)"
LUJO="$(git -C "$LU" rev-parse wave/fixture)"
expect_eq "fixture: someone else's merge of the head onto the commit the land read is wave/fixture's head" \
  "$LUJH $LUJJ merge instant-merged (by someone else)" \
  "$(git -C "$LU" rev-parse "${LUJO}^2") $(git -C "$LU" rev-parse "${LUJO}^1") $(git -C "$LU" log -1 --format=%s "$LUJO")"
expect_match "the land refuses: HEAD already held the head, git merge made nothing, nothing is undone" \
  "spawn-worktree: REFUSED reason=merge-unproven branch=instant-merged onto=wave/fixture checkout=${LU} was_on=wave/fixture was_at=${LUJJ} — ${LU}'s HEAD already held ${LUJH} when git merge ran, so it made no merge, and nothing is undone; land again" "$OUTLUJ"
expect_eq "wave/fixture still holds the other merge" "$LUJO" "$(git -C "$LU" rev-parse wave/fixture)"
expect_eq "every branch still reaches the commit it held" "" "$(branches_dropped "$LU" "$lu_tips")"
expect_true "the tree survives" test -d "$LUJ"
lu_clean

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

section "§LAND-SHIM: the real wall and the real shim, from the main checkout, into the land (wave-26 T56, final review B1, S3 row 6)"
#
# THE AGREEMENT THE ROWS ABOVE NEVER EXERCISE. Every stamp above is written by hand. Here the
# writer is the one that ships: the Bash wall (hooks/bash-walls.sh, the real hook, on a
# PreToolUse payload whose cwd is the MAIN checkout) hands back its wrapped command, the
# command runs from the main checkout the way the harness runs a Bash call
# (`<shell> -c 'eval <command> < /dev/null'`), and the land reads what the shim wrote. Before
# T56 the stamp went to the main checkout's git dir and every one of these red trees LANDED.
#
# The shapes are the doctrine's: the cwd guard `cd <tree> || exit 1` on the whole command,
# then either a bare suite or the evidence capture that keeps the suite's own exit code
# (`…; rc=$?; echo "rc=$rc" >> "$LOG"; exit $rc`). A capture that swallows the code (a bare
# trailing `echo "rc=$?"`) stamps rc=0 and is NOT pinned here: it lands, which is a limit
# recorded in the T56 record, not a behaviour to keep.
#
# BOUNDED: a private slots store, a suite that exits at once, a fake HOME, no plugins dir.
LS="$(new_repo "$TMP/land-shim")"
LS_SID="t56shim-0000-0000-0000-000000000000"
LS_HOOK="${REPO}/hooks/bash-walls.sh"
LS_LOG="$TMP/land-shim-suite.log"
mkdir -p "$LS/.bionic/tmp" "$TMP/land-shim-home"; : > "$LS/.bionic/tmp/engaged-${LS_SID}.state"
expect_true "the wall's hook is on disk" test -f "$LS_HOOK"
ls_wrap() {  # <command> — the command the real wall hands the harness, cwd = the main checkout
  jq -nc --arg s "$LS_SID" --arg c "$LS" --arg cmd "$1" \
    '{session_id:$s, transcript_path:"/irrelevant.jsonl", cwd:$c, permission_mode:"bypassPermissions",
      hook_event_name:"PreToolUse", tool_name:"Bash", tool_input:{command:$cmd, timeout:600000},
      tool_use_id:"toolu_t56shim", agent_id:"at56shim-0123456789abcdef", agent_type:"test-runner"}' |
    env HOME="$TMP/land-shim-home" CLAUDE_CONFIG_DIR="$TMP/land-shim-home/.claude" \
      CLAUDE_CODE_SESSION_ID="$LS_SID" CLAUDE_PROJECT_DIR= BIONIC_PLUGINS_DIR="$TMP/no-plugins" \
      SHELL=/bin/bash CLAUDE_CODE_SHELL= BASH_MAX_TIMEOUT_MS=600000 bash "$LS_HOOK" 2>/dev/null |
    jq -r '.hookSpecificOutput.updatedInput.command // ""' 2>/dev/null
}
ls_harness() {  # <command> — run as the harness runs a Bash call, standing in the main checkout
  local q="'\\''" s; s="${1//\'/$q}"
  ( cd "$LS" && env -u BIONIC_SLOT_HELD -u BIONIC_SLOT_QUIET -u BIONIC_QUIET \
      BIONIC_SLOTS_DIR="$TMP/land-shim-slots" BIONIC_SLOTS_N="${LS_SLOTS_N:-2}" BIONIC_SLOTS_MAX_WAIT="${LS_MAX_WAIT:-20}" BIONIC_SLOTS_POLL=0.1 \
      /bin/bash -c "eval '$s' < /dev/null" ) >/dev/null 2>&1
}
ls_tree() {  # <branch> <suite exit code> -> the tree, its suite committed, nothing else in it
  local t; t="$(new_tree "$LS" "$1")"
  mkdir -p "$t/tests"
  printf '#!/bin/bash\necho "suite %s"\nexit %s\n' "$1" "$2" > "$t/tests/a.test.sh"
  git -C "$t" add tests && git -C "$t" commit --quiet -m "$1 suite exits $2"
  printf '%s' "$t"
}
LS_CAPTURE='set -o pipefail; bash tests/a.test.sh 2>&1 | tee "'"$LS_LOG"'"; rc=$?; echo "rc=$rc" >> "'"$LS_LOG"'"; exit $rc'
ls_case() {  # <label> <branch> <suite rc> <command after the cd guard> <cd target as typed> <expected glob>
  local t c w
  t="$(ls_tree "$2" "$3")"
  c="cd $5 || exit 1; $4"
  w="$(ls_wrap "$c")"
  expect_match "$1: the wall wraps it in the shim with the tree as the stamp dir" \
    "bash *booked.sh --shell /bin/bash --max-wait 590 --stamp-dir $t --suites a.test.sh -- *" "$w"
  ls_harness "$w"
  expect_match "$1: the shim stamped the TREE's git dir, at its head, with the suite's own code" \
    "stamp/v1|head=$(git -C "$t" rev-parse HEAD)|dirty=0|rc=$3|*" "$(tail -n 1 "$(stamp_file "$t")" 2>/dev/null)"
  expect_false "$1: …and nothing in the main checkout's" test -e "$(stamp_file "$LS")"
  expect_match "$1: the land reads it" "$6" "$(worktree_land "$t" wave/fixture)"
}
ls_case "(i) cd <abs tree>, bare suite, red" shim-red-bare 1 'bash tests/a.test.sh' \
  "$LS/.worktrees/shim-red-bare" "spawn-worktree: REFUSED reason=stale-proof why=red rc=1 *"
ls_case "(ii) cd <rel tree>, the doctrine's capture, red" shim-red-capture 1 "$LS_CAPTURE" \
  ".worktrees/shim-red-capture" "spawn-worktree: REFUSED reason=stale-proof why=red rc=1 *"
expect_match "(ii) the capture logged the suite's own code" "*rc=1" "$(tail -n 1 "$LS_LOG" 2>/dev/null)"
ls_case "(iii) cd <abs tree>, bare suite, green" shim-green-bare 0 'bash tests/a.test.sh' \
  "$LS/.worktrees/shim-green-bare" "spawn-worktree: LANDED branch=shim-green-bare onto=wave/fixture *"
ls_case "(iii) cd <rel tree>, the doctrine's capture, green" shim-green-capture 0 "$LS_CAPTURE" \
  ".worktrees/shim-green-capture" "spawn-worktree: LANDED branch=shim-green-capture onto=wave/fixture *"

section "§LAND-SUITES: every suite stamped at the head, each by its newest stamp (wave-26 T61, critic F1)"
#
# The doctrine runs a brief's suites one call each, so each suite writes its own stamp line.
# Before T61 the land read only the LAST line: suite a red, then suite b green, at one head,
# LANDED. Now the wall names each run's suites (`--suites`, the basenames), the shim writes
# them as `suites=` before `cmd=`, and the land refuses unless, for EVERY suite stamped at the
# tree's head, the newest stamp of that suite is green on a clean tree. Every row here runs
# through the real wall (ls_wrap), the real shim from the main checkout (ls_harness) and the
# real land. A tree's two suites exit with the code in a file outside the tree, so one head
# can be run red and then green without a commit.
LSU_RC="$TMP/land-suites-rc"; mkdir -p "$LSU_RC"
lsu_tree() {  # <branch> -> a tree whose tests/a.test.sh and tests/b.test.sh are committed
  local t s; t="$(new_tree "$LS" "$1")"
  mkdir -p "$t/tests"
  for s in a b; do printf '#!/bin/bash\nexit "$(cat %s/%s.%s)"\n' "$LSU_RC" "$1" "$s" > "$t/tests/$s.test.sh"; done
  git -C "$t" add tests && git -C "$t" commit --quiet -m "$1 suites"
  printf '%s' "$t"
}
LSU_WRAP=""
lsu_run() {  # <tree> <a|b> <rc> [<command after the cd guard>] — the suite at <rc>, wall + shim
  echo "$3" > "$LSU_RC/${1##*/}.$2"
  LSU_WRAP="$(ls_wrap "cd $1 || exit 1; ${4:-bash tests/$2.test.sh}")"
  ls_harness "$LSU_WRAP"
}
lsu_stamps() {  # <tree> -> "<suites>:<rc>" per stamp line, oldest first, `-` for no suites=
  awk -F'|' '{ s = "-"; r = ""
    for (i = 2; i <= NF; i++) { if ($i ~ /^cmd=/) break
      if ($i ~ /^suites=/) s = substr($i, 8); if ($i ~ /^rc=/) r = substr($i, 4) }
    printf "%s%s:%s", (NR > 1 ? " " : ""), s, r }' "$(stamp_file "$1")" 2>/dev/null
}

# (a) THE CRITIC'S CASE: a red, then b green, at one head.
LSA="$(lsu_tree su-a-red-b-green)"
lsu_run "$LSA" a 1; lsu_run "$LSA" b 0
expect_eq "(a) the wall named each run's suite, the shim stamped it, in order" \
  "a.test.sh:1 b.test.sh:0" "$(lsu_stamps "$LSA")"
LSA_REFS="$(refs_of "$LS")"
OUTLSA="$(worktree_land "$LSA" wave/fixture)"; RCLSA=$?
expect_match "(a) a red then b green at one head is REFUSED, naming a" \
  "spawn-worktree: REFUSED reason=stale-proof why=red rc=1 suite=a.test.sh head=$(git -C "$LSA" rev-parse HEAD) *" "$OUTLSA"
expect_eq "(a) that refusal exits 2" "2" "$RCLSA"
expect_eq "(a) no ref moved" "$LSA_REFS" "$(refs_of "$LS")"

# (b) a red, then a green after a flake, at the same head: a's newest is green.
LSB="$(lsu_tree su-a-red-a-green)"
lsu_run "$LSB" a 1; lsu_run "$LSB" a 0
expect_eq "(b) two stamps of a, red then green" "a.test.sh:1 a.test.sh:0" "$(lsu_stamps "$LSB")"
expect_match "(b) a red then a green at the same head LANDS" \
  "spawn-worktree: LANDED branch=su-a-red-a-green onto=wave/fixture *" "$(worktree_land "$LSB" wave/fixture)"

# (c) the same suite typed two ways: plain behind an absolute cd, then the doctrine's capture
# behind a relative cd. One name, so the green capture is a's newest stamp.
LSC="$(lsu_tree su-typed-two-ways)"
lsu_run "$LSC" a 1
echo 0 > "$LSU_RC/su-typed-two-ways.a"
LSU_WRAP="$(ls_wrap "cd .worktrees/su-typed-two-ways || exit 1; set -o pipefail; bash tests/a.test.sh 2>&1 | tee \"$LS_LOG\"; rc=\$?; echo \"rc=\$rc\" >> \"$LS_LOG\"; exit \$rc")"
ls_harness "$LSU_WRAP"
expect_match "(c) the capture shape is wrapped with the tree and the one suite name" \
  "bash *booked.sh --shell /bin/bash --max-wait 590 --stamp-dir $LS/.worktrees/su-typed-two-ways --suites a.test.sh -- *" "$LSU_WRAP"
expect_eq "(c) both stamps name a.test.sh" "a.test.sh:1 a.test.sh:0" "$(lsu_stamps "$LSC")"
expect_match "(c) a red typed plainly, then a green in the capture shape, LANDS" \
  "spawn-worktree: LANDED branch=su-typed-two-ways onto=wave/fixture *" "$(worktree_land "$LSC" wave/fixture)"

# (d) both suites green.
LSD="$(lsu_tree su-both-green)"
lsu_run "$LSD" a 0; lsu_run "$LSD" b 0
expect_eq "(d) a green, b green" "a.test.sh:0 b.test.sh:0" "$(lsu_stamps "$LSD")"
expect_match "(d) a green and b green LAND" \
  "spawn-worktree: LANDED branch=su-both-green onto=wave/fixture *" "$(worktree_land "$LSD" wave/fixture)"

# (e) a red at an older head is history once the tree moves: a commit, then a green.
LSE="$(lsu_tree su-older-head)"
lsu_run "$LSE" a 1
echo e > "$LSE/e.txt"; git -C "$LSE" add e.txt; git -C "$LSE" commit --quiet -m "fix after red"
lsu_run "$LSE" a 0
expect_eq "(e) a red, then a green on the new head" "a.test.sh:1 a.test.sh:0" "$(lsu_stamps "$LSE")"
expect_match "(e) a red at an older head, then a green at the new head, LANDS" \
  "spawn-worktree: LANDED branch=su-older-head onto=wave/fixture *" "$(worktree_land "$LSE" wave/fixture)"

# (f) a green, then b red: today's behaviour, kept, and now the refusal names b.
LSF="$(lsu_tree su-a-green-b-red)"
lsu_run "$LSF" a 0; lsu_run "$LSF" b 1
expect_match "(f) a green then b red is REFUSED, naming b" \
  "spawn-worktree: REFUSED reason=stale-proof why=red rc=1 suite=b.test.sh *" "$(worktree_land "$LSF" wave/fixture)"

# (h) ONE COMMAND, TWO SUITES, ONE EXIT CODE. A red one marks both suites red (the land cannot
# tell which failed), so a later green of a alone still leaves b red.
LSH="$(lsu_tree su-two-in-one)"
echo 0 > "$LSU_RC/su-two-in-one.a"
lsu_run "$LSH" b 1 'bash tests/a.test.sh && bash tests/b.test.sh'
expect_match "(h) the two-suite command is wrapped naming both" \
  "bash *booked.sh --shell /bin/bash --max-wait 590 --stamp-dir $LSH --suites a.test.sh,b.test.sh -- *" "$LSU_WRAP"
lsu_run "$LSH" a 0
expect_eq "(h) one line names both, red; then a alone, green" \
  "a.test.sh,b.test.sh:1 a.test.sh:0" "$(lsu_stamps "$LSH")"
expect_match "(h) b's newest stamp is still the red two-suite run: REFUSED, naming b" \
  "spawn-worktree: REFUSED reason=stale-proof why=red rc=1 suite=b.test.sh *" "$(worktree_land "$LSH" wave/fixture)"
lsu_run "$LSH" b 0
expect_match "(h) …and once b runs green alone the tree LANDS" \
  "spawn-worktree: LANDED branch=su-two-in-one onto=wave/fixture *" "$(worktree_land "$LSH" wave/fixture)"

# (i) A SUITE THAT NEVER GOT A PLACE (critic 3 S5). a runs green; b waits for the one place, which
# another run holds, and gives up (69). Its line names b, so the land refuses on it; once b runs
# green the tree lands.
LSI="$(lsu_tree su-b-no-place)"
lsu_run "$LSI" a 0
sleep 60 & LSI_H=$!
mkdir -p "$TMP/land-shim-slots/place.1"; printf '%s\n' "$LSI_H" > "$TMP/land-shim-slots/place.1/pid"
export LS_SLOTS_N=1 LS_MAX_WAIT=1; lsu_run "$LSI" b 0; unset LS_SLOTS_N LS_MAX_WAIT
kill "$LSI_H" 2>/dev/null; wait "$LSI_H" 2>/dev/null
expect_eq "(i) a green, then b's no-place end stamped with its suite and 69" \
  "a.test.sh:0 b.test.sh:69" "$(lsu_stamps "$LSI")"
expect_match "(i) a green then b out of places at one head is REFUSED, naming b" \
  "spawn-worktree: REFUSED reason=stale-proof why=red rc=69 suite=b.test.sh *" "$(worktree_land "$LSI" wave/fixture)"
lsu_run "$LSI" b 0
expect_match "(i) …and once b runs green the tree LANDS" \
  "spawn-worktree: LANDED branch=su-b-no-place onto=wave/fixture *" "$(worktree_land "$LSI" wave/fixture)"

# (g) A LINE THAT NAMES NO SUITE: an older shim's (no `suites=`), or `?` for a run the wall could
# not name. It could be ANY suite, so no later run at that head can clear a red or dirty one;
# the fix is a commit, then the suites again. A green one asks nothing.
LSG="$(lsu_tree su-older-shim)"
echo 1 > "$LSU_RC/su-older-shim.a"
LSU_WRAP="$(ls_wrap "cd $LSG || exit 1; bash tests/a.test.sh")"
LSG_OLD="${LSU_WRAP/ --suites a.test.sh/}"
expect_ne "(g) fixture: the older wall's wrap is the real one without --suites" "$LSU_WRAP" "$LSG_OLD"
ls_harness "$LSG_OLD"
echo 0 > "$LSU_RC/su-older-shim.a"; ls_harness "$LSG_OLD"
lsu_run "$LSG" a 0
expect_eq "(g) two older-shim lines (red, green), then a named green" "-:1 -:0 a.test.sh:0" "$(lsu_stamps "$LSG")"
OUTLSG="$(worktree_land "$LSG" wave/fixture)"
expect_match "(g) an older-shim red line at the head is REFUSED, naming no suite, whatever ran after" \
  "spawn-worktree: REFUSED reason=stale-proof why=red rc=1 suite=? head=$(git -C "$LSG" rev-parse HEAD) — *" "$OUTLSG"
expect_match "(g) …and the fix is a commit, not a re-run" "*commit, then re-run the tree's suites at the new head, land again" "$OUTLSG"
echo g > "$LSG/g.txt"; git -C "$LSG" add g.txt; git -C "$LSG" commit --quiet -m "new head"
ls_harness "$LSG_OLD"
expect_match "(g) an older-shim GREEN line at the head LANDS: it asks nothing" \
  "spawn-worktree: LANDED branch=su-older-shim onto=wave/fixture *" "$(worktree_land "$LSG" wave/fixture)"
# The wall's own `?`: a suite named through a variable from the environment.
LSQ="$(lsu_tree su-unnamed)"
echo 1 > "$LSU_RC/su-unnamed.a"
LSU_WRAP="$(ls_wrap "cd $LSQ || exit 1; bash tests/\$LSU_X.test.sh")"
expect_match "(g) a suite the wall cannot name is wrapped as ?" "bash *booked.sh * --suites '?' -- *" "$LSU_WRAP"
export LSU_X=a; ls_harness "$LSU_WRAP"; unset LSU_X
lsu_run "$LSQ" a 0
expect_eq "(g) the unnamed red, then a named green" "?:1 a.test.sh:0" "$(lsu_stamps "$LSQ")"
expect_match "(g) the unnamed red run is REFUSED, naming ?" \
  "spawn-worktree: REFUSED reason=stale-proof why=red rc=1 suite=? *" "$(worktree_land "$LSQ" wave/fixture)"


section "§LAND-NAMES: a run is named by what it is — a runner by its text, a file by its place (wave-26 T63, critic K4-S1/N1/N2)"
#
# T61 named a suite FILE by its basename and everything else `?`, and a red `?` at the head is
# cleared only by a commit. So a project that runs its tests with a runner (`npm test`,
# `pytest`) had EVERY run named `?`: one red run, a run that never got a place, or an
# interrupted run, and the tree could not land until an empty commit. Now a runner is named by
# its own text (`npm_test`), a suite file by its basename only when it is this tree's own
# `tests/<basename>` (the budget's rule, cmd_claim_scope), any other file by its run, and two
# suite runs joined by anything but `&&` are `?`. Every row runs through the real wall, the
# real shim and the real land. The runners are stand-ins on a private PATH; nothing is
# installed. They exit with the code in a file outside the tree, as lsu_tree's suites do.
LSN_BIN="$TMP/land-names-bin"; mkdir -p "$LSN_BIN"
for _r in npm pytest; do
  printf '#!/bin/bash\nexit "$(cat %s/%s.rc)"\n' "$LSU_RC" "$_r" > "$LSN_BIN/$_r"; chmod +x "$LSN_BIN/$_r"
done
lsn_run() {  # <tree> <runner> <rc> [<command after the cd guard>] — the runner at <rc>, wall + shim
  echo "$3" > "$LSU_RC/$2.rc"
  LSU_WRAP="$(ls_wrap "cd $1 || exit 1; ${4:-$2 test}")"
  PATH="$LSN_BIN:$PATH" ls_harness "$LSU_WRAP"
}

# (n1) THE CRITIC'S CASE: npm test red, then npm test green, at one head.
LSN1="$(lsu_tree sn-npm-retry)"
lsn_run "$LSN1" npm 1
expect_match "(n1) npm test is wrapped naming its own text" \
  "bash *booked.sh --shell /bin/bash --max-wait 590 --stamp-dir $LSN1 --suites npm_test -- *" "$LSU_WRAP"
lsn_run "$LSN1" npm 0
expect_eq "(n1) two stamps of npm_test, red then green" "npm_test:1 npm_test:0" "$(lsu_stamps "$LSN1")"
expect_match "(n1) npm test red then npm test green at one head LANDS" \
  "spawn-worktree: LANDED branch=sn-npm-retry onto=wave/fixture *" "$(worktree_land "$LSN1" wave/fixture)"

# (n2) A different runner is a different suite: npm test red, then pytest green.
LSN2="$(lsu_tree sn-npm-then-pytest)"
lsn_run "$LSN2" npm 1; lsn_run "$LSN2" pytest 0 pytest
expect_eq "(n2) npm_test red, then pytest green" "npm_test:1 pytest:0" "$(lsu_stamps "$LSN2")"
OUTLSN2="$(worktree_land "$LSN2" wave/fixture)"
expect_match "(n2) npm test red then pytest green at one head is REFUSED, naming npm_test" \
  "spawn-worktree: REFUSED reason=stale-proof why=red rc=1 suite=npm_test head=$(git -C "$LSN2" rev-parse HEAD) — make the suites green, *" "$OUTLSN2"

# (n3) A runner that never got a place, then the same runner green.
LSN3="$(lsu_tree sn-npm-no-place)"
sleep 60 & LSN3_H=$!
mkdir -p "$TMP/land-shim-slots/place.1"; printf '%s\n' "$LSN3_H" > "$TMP/land-shim-slots/place.1/pid"
export LS_SLOTS_N=1 LS_MAX_WAIT=1; lsn_run "$LSN3" npm 0; unset LS_SLOTS_N LS_MAX_WAIT
kill "$LSN3_H" 2>/dev/null; wait "$LSN3_H" 2>/dev/null
lsn_run "$LSN3" npm 0
expect_eq "(n3) npm_test out of places (69), then npm_test green" "npm_test:69 npm_test:0" "$(lsu_stamps "$LSN3")"
expect_match "(n3) a runner that never got a place, then the same runner green, LANDS" \
  "spawn-worktree: LANDED branch=sn-npm-no-place onto=wave/fixture *" "$(worktree_land "$LSN3" wave/fixture)"

# (n4) A TRUE `?` STILL STICKS: a runner whose text the reading cannot resolve (a `$`).
LSN4="$(lsu_tree sn-unresolved)"
export LSN_ARG=x
lsn_run "$LSN4" pytest 1 'pytest "$LSN_ARG"'
expect_match "(n4) a runner with a \$ in its text is wrapped as ?" "bash *booked.sh * --suites '?' -- *" "$LSU_WRAP"
lsn_run "$LSN4" pytest 0 'pytest "$LSN_ARG"'
expect_eq "(n4) the unnamed red, then the unnamed green" "?:1 ?:0" "$(lsu_stamps "$LSN4")"
OUTLSN4="$(worktree_land "$LSN4" wave/fixture)"
expect_match "(n4) a red ? at the head is REFUSED whatever ran after, naming ?" \
  "spawn-worktree: REFUSED reason=stale-proof why=red rc=1 suite=? *" "$OUTLSN4"
expect_match "(n4) …and the fix is a commit, not a re-run" "*commit, then re-run the tree's suites at the new head, land again" "$OUTLSN4"
echo n4 > "$LSN4/n4.txt"; git -C "$LSN4" add n4.txt; git -C "$LSN4" commit --quiet -m "new head"
lsn_run "$LSN4" pytest 0 'pytest "$LSN_ARG"'
unset LSN_ARG
expect_match "(n4) …after a commit, the green ? LANDS" \
  "spawn-worktree: LANDED branch=sn-unresolved onto=wave/fixture *" "$(worktree_land "$LSN4" wave/fixture)"

# (n5) TWO FILES, TWO SUITES (K4-N2): tests/a.test.sh red, then other/a.test.sh green.
LSN5="$(lsu_tree sn-other-a)"
mkdir -p "$LSN5/other"; printf '#!/bin/bash\nexit 0\n' > "$LSN5/other/a.test.sh"
git -C "$LSN5" add other && git -C "$LSN5" commit --quiet -m "another a.test.sh"
lsu_run "$LSN5" a 1; lsu_run "$LSN5" a 0 'bash other/a.test.sh'
expect_eq "(n5) the suite of this tree is a.test.sh, the other file is named by its run" \
  "a.test.sh:1 bash_other_a.test.sh:0" "$(lsu_stamps "$LSN5")"
expect_match "(n5) tests/a red then other/a green at one head is REFUSED, naming a" \
  "spawn-worktree: REFUSED reason=stale-proof why=red rc=1 suite=a.test.sh *" "$(worktree_land "$LSN5" wave/fixture)"

# (n6) ONE FILE, FOUR SPELLINGS, ONE SUITE: relative, absolute, `./`, and inside the capture.
LSN6="$(lsu_tree sn-one-file)"
lsu_run "$LSN6" a 1
lsu_run "$LSN6" a 1 "bash $LSN6/tests/a.test.sh"
expect_match "(n6) the absolute path behind the cd is wrapped as a.test.sh" \
  "bash *booked.sh --shell /bin/bash --max-wait 590 --stamp-dir $LSN6 --suites a.test.sh -- *" "$LSU_WRAP"
lsu_run "$LSN6" a 1 'bash ./tests/a.test.sh'
lsu_run "$LSN6" a 0 "set -o pipefail; bash tests/a.test.sh 2>&1 | tee \"$LS_LOG\"; rc=\$?; echo \"rc=\$rc\" >> \"$LS_LOG\"; exit \$rc"
expect_eq "(n6) four stamps, one name" "a.test.sh:1 a.test.sh:1 a.test.sh:1 a.test.sh:0" "$(lsu_stamps "$LSN6")"
expect_match "(n6) red three ways, then green in the capture, LANDS" \
  "spawn-worktree: LANDED branch=sn-one-file onto=wave/fixture *" "$(worktree_land "$LSN6" wave/fixture)"

# (n7) A GREEN THAT DOES NOT SPEAK FOR EVERY SUITE (K4-N1): b red, then `a || b` with a green.
# b never ran, so the line is `?`, and its green asks nothing: b is still red.
LSN7="$(lsu_tree sn-or-short)"
lsu_run "$LSN7" b 1
echo 0 > "$LSU_RC/sn-or-short.a"
lsu_run "$LSN7" b 1 'bash tests/a.test.sh || bash tests/b.test.sh'
expect_match "(n7) a || b is wrapped as ?" "bash *booked.sh --shell /bin/bash --max-wait 590 --stamp-dir $LSN7 --suites '?' -- *" "$LSU_WRAP"
expect_eq "(n7) b red, then the a || b line green as ?" "b.test.sh:1 ?:0" "$(lsu_stamps "$LSN7")"
expect_match "(n7) b red then a || b green at one head is REFUSED, naming b" \
  "spawn-worktree: REFUSED reason=stale-proof why=red rc=1 suite=b.test.sh *" "$(worktree_land "$LSN7" wave/fixture)"

# (n8) A LINE THE EARLIER WALL WROTE IS READ BY ITS OWN GRAMMAR. Before this change the wall
# named npm test `?`; the stamp token is still stamp/v1 and the land reads that line as a `?`:
# red at the head, it sticks even after a green npm_test line.
LSN8="$(lsu_tree sn-earlier-wall)"
echo 1 > "$LSU_RC/npm.rc"
LSU_WRAP="$(ls_wrap "cd $LSN8 || exit 1; npm test")"
LSN8_Q="'?'"; LSN8_OLD="${LSU_WRAP/ --suites npm_test/ --suites $LSN8_Q}"
expect_ne "(n8) fixture: the earlier wall's wrap is the real one with --suites '?'" "$LSU_WRAP" "$LSN8_OLD"
PATH="$LSN_BIN:$PATH" ls_harness "$LSN8_OLD"
lsn_run "$LSN8" npm 0
expect_eq "(n8) the earlier wall's ? red, then a named green" "?:1 npm_test:0" "$(lsu_stamps "$LSN8")"
expect_match "(n8) the stamp is still stamp/v1" "stamp/v1|*" "$(head -n 1 "$(stamp_file "$LSN8")")"
expect_match "(n8) the earlier wall's red ? at the head is REFUSED, naming ?" \
  "spawn-worktree: REFUSED reason=stale-proof why=red rc=1 suite=? *" "$(worktree_land "$LSN8" wave/fixture)"

section "§LAND-RC: a project's declared release check runs over each landing's range (wave-27 T16; REQ-6 AC-6.2; D12)"
#
# `.bionic/config.yaml` may name `release-check: <command>`. When it does, `land` runs it before
# the merge, in the task's tree, with BIONIC_CHECK_BASE at the working branch's head and
# BIONIC_CHECK_HEAD at the task's head; a non-zero exit refuses the landing `why=release-check`
# and changes nothing: the tree, its branch, every ref and the record link are as they were.
# With no key the land runs nothing for it and prints nothing more.
#
# FIXTURE FIDELITY. The declared command is a script this section writes, never this repository's
# scan: it records the two variables and its directory, so a row reads the range it was given, and
# its exit is read from a file the rows set. Every tree is new_tree's, with its record link and a
# green stamp at its head (keep_tree's shape), so the release check is the only refusal in play.
LR="$(new_repo "$TMP/land-rc")"
LR_SEEN="$TMP/lr-seen"; LR_RCF="$TMP/lr-rc"; echo 0 > "$LR_RCF"
LR_CHK="$TMP/lr-check.sh"
cat > "$LR_CHK" <<LR_EOF
#!/bin/bash
printf 'base=%s head=%s cwd=%s\n' "\${BIONIC_CHECK_BASE:-}" "\${BIONIC_CHECK_HEAD:-}" "\$(pwd -P)" >> "$LR_SEEN"
rc="\$(cat "$LR_RCF")"
[ "\$rc" = 0 ] || echo 'HIT entry 2 in the landing range'
exit "\$rc"
LR_EOF
lr_runs() { [ -f "$LR_SEEN" ] && awk 'END { print NR + 0 }' "$LR_SEEN" || echo 0; }
rc_tree() {  # <branch> -> tree path, with its record link and a green stamp at its head
  local t; t="$(new_tree "$LR" "$1")"
  ln -s "${LR}/.bionic" "$t/.bionic"; green_stamp "$t"; printf '%s' "$t"
}

# NO KEY: the land is as before, and the command never runs.
LR1="$(rc_tree rc-nokey)"
OUTLR1="$(worktree_land "$LR1" wave/fixture 2>"$TMP/lr-err1")"
expect_match "(rc1) with no release-check: key the tree lands" "spawn-worktree: LANDED branch=rc-nokey onto=wave/fixture *" "$OUTLR1"
expect_eq "(rc1b) …printing the LANDED line alone" "1" "$(printf '%s\n' "$OUTLR1" | awk 'END { print NR }')"
expect_eq "(rc1c) …nothing on stderr" "" "$(cat "$TMP/lr-err1")"
expect_eq "(rc1d) …and the command never ran" "0" "$(lr_runs)"

# THE KEY SET, A PASSING COMMAND: it runs over the landing range, and the tree lands.
printf 'release-check: bash %s\n' "$LR_CHK" > "$LR/.bionic/config.yaml"
LR2="$(rc_tree rc-pass)"
LR2_HEAD="$(git -C "$LR2" rev-parse HEAD)"; LR2_BASE="$(git -C "$LR" rev-parse refs/heads/wave/fixture)"
LR2_CWD="$LR"   # the target checkout, which holds wave/fixture (review pass 22 B1): never the piece's tree
expect_match "(rc2) with the key set and a passing command the tree lands" \
  "spawn-worktree: LANDED branch=rc-pass onto=wave/fixture *" "$(worktree_land "$LR2" wave/fixture)"
expect_eq "(rc2b) …the command ran once, in the target checkout, from the working branch's head to the task's head" \
  "1 base=${LR2_BASE} head=${LR2_HEAD} cwd=${LR2_CWD}" "$(lr_runs) $(tail -n 1 "$LR_SEEN" 2>/dev/null)"

# THE KEY SET, A FAILING COMMAND: refused why=release-check, and nothing moved.
echo 1 > "$LR_RCF"
LR3="$(rc_tree rc-fail)"
LR3_HEAD="$(git -C "$LR3" rev-parse HEAD)"; LR3_BASE="$(git -C "$LR" rev-parse refs/heads/wave/fixture)"
LR3_REFS="$(refs_of "$LR")"; LR3_TREES="$(trees_of "$LR")"
expect_true "(rc3-pre) the link resolves before the land" link_ok "$LR3"
OUTLR3="$(worktree_land "$LR3" wave/fixture 2>"$TMP/lr-err3")"; RCLR3=$?
expect_match "(rc3) a failing declared command refuses the landing why=release-check" \
  "spawn-worktree: REFUSED reason=* why=release-check *" "$OUTLR3"
expect_eq "(rc3b) …exit 2" "2" "$RCLR3"
expect_eq "(rc3c) …it ran over the landing range" "base=${LR3_BASE} head=${LR3_HEAD}" \
  "$(tail -n 1 "$LR_SEEN" 2>/dev/null | awk '{ print $1, $2 }')"
expect_contains "(rc3d) …and its output is shown" "HIT entry 2 in the landing range" "$(cat "$TMP/lr-err3")"
expect_eq "(rc3e) every ref is as before the call: no merge, the branch where it was" "$LR3_REFS" "$(refs_of "$LR")"
expect_eq "(rc3f) every worktree is as before the call: the tree stands" "$LR3_TREES" "$(trees_of "$LR")"
expect_eq "(rc3g) the tree's head is the one judged, its status clean" "${LR3_HEAD}|" \
  "$(git -C "$LR3" rev-parse HEAD)|$(git -C "$LR3" status --porcelain)"
expect_true "(rc3h) the link to the record still resolves" link_ok "$LR3"
echo 0 > "$LR_RCF"
expect_match "(rc3i) the same tree lands once the command passes" \
  "spawn-worktree: LANDED branch=rc-fail onto=wave/fixture *" "$(worktree_land "$LR3" wave/fixture)"

# A PIECE NEVER REWRITES ITS JUDGE (review pass 22 B1; A-orch-75). The declared command runs in the
# TARGET checkout as it stands before the merge, never in the piece's tree, so a command that names
# its script relatively (`release-check: bash scan.sh`) runs the script as the target holds it. The
# range is unchanged: the piece's commits are in the same object store, so the scan reads them from
# there. FIXTURE FIDELITY: the review's p5 probe, as rows. scan.sh is TRACKED on the working branch
# and fails when any file at BIONIC_CHECK_HEAD holds the forbidden word; it records where it ran.
LS5="$(new_repo "$TMP/land-rc-self")"
LS5_SEEN="$TMP/ls5-seen"
cat > "$LS5/scan.sh" <<LS5_EOF
#!/bin/bash
pwd -P >> "$LS5_SEEN"
if git grep -q FORBIDDEN "\$BIONIC_CHECK_HEAD" -- . ':!scan.sh'; then echo HIT; exit 1; fi
exit 0
LS5_EOF
git -C "$LS5" add scan.sh && git -C "$LS5" commit --quiet -m "the project's scan"
printf 'release-check: bash scan.sh\n' > "$LS5/.bionic/config.yaml"
ls5_tree() {  # <branch> -> a tree a commit ahead, with its record link and a green stamp at its head
  local t; t="$(new_tree "$LS5" "$1")"; ln -s "${LS5}/.bionic" "$t/.bionic"; printf '%s' "$t"
}
ls5_commit() {  # <tree> <message> — commits what the row wrote, then stamps the head green
  git -C "$1" add -A >/dev/null 2>&1; git -C "$1" commit --quiet -m "$2"; green_stamp "$1"
}

# (rc4) PLANTS THE WORD AND REWRITES THE SCAN TO PASS: refused, and nothing moved.
LS5A="$(ls5_tree rc-self-rewrite)"
echo FORBIDDEN > "$LS5A/b.txt"; printf '#!/bin/bash\nexit 0\n' > "$LS5A/scan.sh"
ls5_commit "$LS5A" "plant and tidy the scan"
LS5A_TGT="$(git -C "$LS5" rev-parse refs/heads/wave/fixture)"; LS5A_TREES="$(trees_of "$LS5")"
LS5A_ST="$(cat "$(stamp_file "$LS5A")")"
OUTLS5A="$(worktree_land "$LS5A" wave/fixture 2>/dev/null)"; RCLS5A=$?
expect_match "(rc4) a piece that plants the word and rewrites scan.sh to exit 0 is refused why=release-check" \
  "spawn-worktree: REFUSED reason=check-failed why=release-check rc=1 branch=rc-self-rewrite *" "$OUTLS5A"
expect_eq "(rc4b) …exit 2" "2" "$RCLS5A"
expect_eq "(rc4c) …the scan ran in the target checkout, not the piece's tree" "$LS5" "$(tail -n 1 "$LS5_SEEN" 2>/dev/null)"
expect_eq "(rc4d) the target's head is as before" "$LS5A_TGT" "$(git -C "$LS5" rev-parse refs/heads/wave/fixture)"
expect_eq "(rc4e) every worktree is as before: the tree stands" "$LS5A_TREES" "$(trees_of "$LS5")"
expect_eq "(rc4f) the tree's stamps are as before" "$LS5A_ST" "$(cat "$(stamp_file "$LS5A")")"

# (rc6) PLANTS THE WORD AND LEAVES THE SCAN ALONE, THE TARGET HAVING TIGHTENED ITS SCAN SINCE THE
# PIECE WAS CUT (wave-27 T50, review pass 27 N8): refused. Against the scan the piece was cut from
# (which checks nothing) the plant would land; only the target's own, tighter scan refuses it, so
# this row is red on a land that runs the command in the piece's tree, by itself, with no rewrite
# of the scan in the piece to explain the difference.
LS6="$(new_repo "$TMP/land-rc-tightened")"
LS6_SEEN="$TMP/ls6-seen"
printf '#!/bin/bash\npwd -P >> "%s"\nexit 0\n' "$LS6_SEEN" > "$LS6/scan.sh"
git -C "$LS6" add scan.sh && git -C "$LS6" commit --quiet -m "a scan that checks nothing yet"
printf 'release-check: bash scan.sh\n' > "$LS6/.bionic/config.yaml"
LS6C="$(new_tree "$LS6" rc-self-plant)"; ln -s "${LS6}/.bionic" "$LS6C/.bionic"
cat > "$LS6/scan.sh" <<LS6_EOF
#!/bin/bash
pwd -P >> "$LS6_SEEN"
if git grep -q FORBIDDEN "\$BIONIC_CHECK_HEAD" -- . ':!scan.sh'; then echo HIT; exit 1; fi
exit 0
LS6_EOF
git -C "$LS6" commit --quiet -am "the target tightens its scan"
expect_eq "(rc6-pre) fixture: the piece still holds the scan it was cut from" "exit 0" \
  "$(sed -n '3p' "$LS6C/scan.sh")"
echo FORBIDDEN > "$LS6C/c.txt"; ls5_commit "$LS6C" "plant"
LS6C_TGT="$(git -C "$LS6" rev-parse refs/heads/wave/fixture)"
OUTLS6="$(worktree_land "$LS6C" wave/fixture 2>/dev/null)"; RCLS6=$?
expect_match "(rc6) a piece that plants the word and leaves scan.sh alone is refused by the target's scan, why=release-check" \
  "spawn-worktree: REFUSED reason=check-failed why=release-check rc=1 branch=rc-self-plant *" "$OUTLS6"
expect_eq "(rc6b) …the scan that ran is the target's" "$LS6" "$(tail -n 1 "$LS6_SEEN" 2>/dev/null)"
expect_eq "(rc6c) …and the target's head is as before" "$LS6C_TGT" "$(git -C "$LS6" rev-parse refs/heads/wave/fixture)"

# (rc5) CHANGES ONLY THE SCAN, PLANTS NOTHING: judged by the target's scan, and lands. The piece's
# scan exits 1 whatever it reads, so a landing here is the target's scan having judged.
LS5B="$(ls5_tree rc-self-improve)"
printf '#!/bin/bash\necho piece-scan-ran; exit 1\n' > "$LS5B/scan.sh"; ls5_commit "$LS5B" "a stricter scan"
OUTLS5B="$(worktree_land "$LS5B" wave/fixture 2>"$TMP/ls5-err")"
expect_match "(rc5) a piece that only changes scan.sh is judged by the target's scan and lands" \
  "spawn-worktree: LANDED branch=rc-self-improve onto=wave/fixture *" "$OUTLS5B"
expect_eq "(rc5b) …the scan ran in the target checkout" "$LS5" "$(tail -n 1 "$LS5_SEEN" 2>/dev/null)"
expect_absent "(rc5c) …and the piece's scan never ran" "piece-scan-ran" "$OUTLS5B$(cat "$TMP/ls5-err")"
expect_contains "(rc5d) …though the target now carries it" "piece-scan-ran" "$(cat "$LS5/scan.sh")"

section "§LAND-CHECK: what the declared check may do to the target, and what it is handed (wave-27 T50; review pass 27 S2, S3)"
#
# The declared command runs in the TARGET checkout. S2: it may not leave the target dirty. The
# target's clean test (tracked files only, the test `land` has always used) is taken again after
# the command has run, and a target the command dirtied refuses the landing `reason=check-dirtied
# why=release-check`, naming the paths, with nothing merged; `land` cleans nothing. An untracked
# file is not counted, by that same test. S3: the command is also handed BIONIC_CHECK_TREE, the
# absolute path of the piece's checkout, because its own working directory is the target.
#
# FIXTURE FIDELITY. The declared command is a script this section writes: it records what it was
# handed and where it ran, then does what the mode file says. Every tree is new_tree's with its
# record link and a green stamp at its head, so the check is the only refusal in play.
LD="$(new_repo "$TMP/land-check")"
LD_SEEN="$TMP/ld-seen"; LD_MODE="$TMP/ld-mode"; echo none > "$LD_MODE"
LD_CHK="$TMP/ld-check.sh"
cat > "$LD_CHK" <<LD_EOF
#!/bin/bash
printf 'tree=%s dir=%s cwd=%s\n' "\${BIONIC_CHECK_TREE:-}" "\$([ -d "\${BIONIC_CHECK_TREE:-/nonexistent}" ] && echo yes || echo no)" "\$(pwd -P)" >> "$LD_SEEN"
case "\$(cat "$LD_MODE")" in
  dirty-tracked) echo x >> file.txt ;;
  dirty-untracked) echo x > untracked.txt ;;
  marker) [ -f "\$BIONIC_CHECK_TREE/marker" ] || { echo "NO MARKER in \$BIONIC_CHECK_TREE"; exit 1; } ;;
esac
exit 0
LD_EOF
printf 'release-check: bash %s\n' "$LD_CHK" > "$LD/.bionic/config.yaml"
ld_tree() {  # <branch> [marker] -> tree path, with its record link and a green stamp at its head
  local t; t="$(new_tree "$LD" "$1")"; ln -s "${LD}/.bionic" "$t/.bionic"
  if [ -n "${2:-}" ]; then echo here > "$t/marker"; git -C "$t" add marker; git -C "$t" commit --quiet -m "marker"; fi
  green_stamp "$t"; printf '%s' "$t"
}

# (s2) A CHECK THAT WRITES A TRACKED FILE IN THE TARGET: refused, nothing merged, the target left
# as the check left it.
echo dirty-tracked > "$LD_MODE"
LD1="$(ld_tree chk-dirty)"
LD1_REFS="$(refs_of "$LD")"; LD1_TREES="$(trees_of "$LD")"; LD1_ST="$(cat "$(stamp_file "$LD1")")"
OUTLD1="$(worktree_land "$LD1" wave/fixture 2>/dev/null)"; RCLD1=$?
expect_match "(T50-s2) a check that writes a tracked file in the target refuses the landing, naming the path" \
  "spawn-worktree: REFUSED reason=check-dirtied why=release-check *paths=*file.txt*" "$OUTLD1"
expect_eq "(T50-s2b) …exit 2" "2" "$RCLD1"
expect_eq "(T50-s2c) …no ref moved: nothing is merged" "$LD1_REFS" "$(refs_of "$LD")"
expect_eq "(T50-s2d) …the tree stands, its stamps and its link as they were" \
  "$LD1_TREES|$LD1_ST" "$(trees_of "$LD")|$(cat "$(stamp_file "$LD1")")"
expect_true "(T50-s2e) …the link to the record still resolves" link_ok "$LD1"
expect_eq "(T50-s2f) …and the target is left as the check left it: land cleaned nothing" " M file.txt" \
  "$(git -C "$LD" status --porcelain --untracked-files=no)"
LD2="$(ld_tree chk-next)"
expect_match "(T50-s2g) the next landing is refused by the target's clean test until someone cleans it" \
  "spawn-worktree: REFUSED reason=onto-checkout-dirty *" "$(worktree_land "$LD2" wave/fixture 2>/dev/null)"
git -C "$LD" checkout --quiet -- file.txt
echo none > "$LD_MODE"
expect_match "(T50-s2h) the arm discriminates: the same tree lands once the target is clean and the check writes nothing" \
  "spawn-worktree: LANDED branch=chk-dirty onto=wave/fixture *" "$(worktree_land "$LD1" wave/fixture 2>/dev/null)"

# (s2u) A CHECK THAT WRITES AN UNTRACKED FILE: the clean test does not count untracked files (the
# `.bionic` alias and `.worktrees/` live there by design), so the landing stands.
echo dirty-untracked > "$LD_MODE"
expect_match "(T50-s2u) a check that writes an untracked file does not refuse the landing" \
  "spawn-worktree: LANDED branch=chk-next onto=wave/fixture *" "$(worktree_land "$LD2" wave/fixture 2>/dev/null)"
expect_true "(T50-s2v) …and the file is there, so the check did write one" test -f "$LD/untracked.txt"
rm -f "$LD/untracked.txt"

# (s3) THE CHECK IS HANDED THE PIECE'S CHECKOUT. The piece without the file is cut first: once the
# piece that adds it has landed, every later tree is cut from a target that holds it.
echo marker > "$LD_MODE"
LD4="$(ld_tree chk-nomarker)"
OUTLD4="$(worktree_land "$LD4" wave/fixture 2>"$TMP/ld-err4")"
expect_match "(T50-s3) a check that reads a file under BIONIC_CHECK_TREE refuses a piece without it, why=release-check" \
  "spawn-worktree: REFUSED reason=check-failed why=release-check rc=1 branch=chk-nomarker *" "$OUTLD4"
expect_contains "(T50-s3b) …and the check saw that piece's checkout" "NO MARKER in ${LD4}" "$(cat "$TMP/ld-err4")"
LD3="$(ld_tree chk-marker yes)"
OUTLD3="$(worktree_land "$LD3" wave/fixture 2>/dev/null)"
expect_match "(T50-s3c) the arm discriminates: the same check passes for a piece that adds the file" \
  "spawn-worktree: LANDED branch=chk-marker onto=wave/fixture *" "$OUTLD3"
expect_eq "(T50-s3d) …the variable was the piece's checkout, an existing directory, and the cwd the target's" \
  "tree=${LD3} dir=yes cwd=${LD}" "$(tail -n 1 "$LD_SEEN" 2>/dev/null)"

section "§LAND-PROOFS: a landing keeps the proof it read (wave-27 T44; REQ-2 AC-2.1, REQ-8; D15)"
#
# `land` appends to `<docs-root>/record/<the bound plan's name less .plan.md>/landing-proofs.log`
# one header line per landing, `landed: row=<id|—> branch=<b> head=<40-hex> merge=<40-hex>
# at=<ISO-UTC>`, and under it every stamp line at the landed head exactly as the stamp file holds
# it. The record is proved writable before the merge (`why=proofs-unwritable`, nothing changed),
# written after it and before the tree goes; the LANDED line names it as `proofs=<path>`, and a
# land with no bound plan prints `proofs=none`.
#
# FIXTURE FIDELITY. Every land here goes through `worktree_land_for_session`, the path both real
# callers take, over a plan bound the way bind_plan binds one, whose `## Tasks` table carries a
# `worktree` column. Stamp lines are written in the shim's shape, and the record is read back
# whole: each row compares the file, never a grep of it.
LP="$(new_repo "$TMP/land-proofs")"
LP_SID="land-proofs-session-01"
LP_PLAN="$LP/.bionic/docs/plans/epic-x/wave-lp.plan.md"
LP_LOG="$LP/.bionic/docs/record/wave-lp/landing-proofs.log"
lp_bind() {  # <table rows, one `| id | worktree |` pair per line> — binds LP_SID to LP_PLAN
  mkdir -p "${LP_PLAN%/*}" "$LP/.bionic/tmp"
  {
    printf -- '---\nworking-branch: wave/fixture\n---\n# fixture plan\n\n## SDLC State\n\ncurrent: 4\n\n## Tasks\n\n'
    printf '| id | step | kind | task | worktree | status |\n|---|---|---|---|---|---|\n'
    printf '%s\n' "$1"
    printf '\n## Task detail\n'
  } > "$LP_PLAN"
  printf 'plan=%s\nengaged_at=2026-09-23T00:00:00Z\n' "$LP_PLAN" > "$LP/.bionic/tmp/engaged-${LP_SID}.state"
}
lp_tree() {  # <branch> <dir under .worktrees> -> tree path, a commit ahead, its record link
  local d="$LP/.worktrees/$2"
  if git -C "$LP" show-ref --verify --quiet "refs/heads/$1"; then
    git -C "$LP" worktree add --quiet "$d" "$1" >/dev/null 2>&1
  else
    git -C "$LP" worktree add --quiet -b "$1" "$d" HEAD >/dev/null 2>&1
  fi
  echo "$RANDOM$RANDOM$RANDOM" >> "$d/$2.txt"; git -C "$d" add -A >/dev/null 2>&1; git -C "$d" commit --quiet -m "$1 work"
  ln -s "$LP/.bionic" "$d/.bionic"; printf '%s' "$d"
}
lp_stamp() {  # <tree> <head> <rc> <suites> <cmd> — one stamp line, the shim's shape
  printf 'stamp/v1|head=%s|dirty=0|rc=%s|at=2026-10-05T01:02:03Z|suites=%s|cmd=%s\n' "$2" "$3" "$4" "$5" \
    >> "$(stamp_file "$1")"
}
lp_at() { printf '%s' "$1" | sed -n 's/^landed: .* at=\([^ ]*\)$/\1/p' | tail -n 1; }
LP_ISO='[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z'
lp_bind '| T7 | 4 | build | seven | .worktrees/27-T7 | active |
| T8 | 4 | build | eight | .worktrees/27-T8 | active |
| T9 | 4 | build | nine | — | pending |'

# (p1) ONE SUITE, A NAMED TREE: the header names the row, and the one judged line follows it.
LP1="$(lp_tree wt/27-T7 27-T7)"; LP1_H="$(git -C "$LP1" rev-parse HEAD)"
lp_stamp "$LP1" "$LP1_H" 0 one.test.sh "bash tests/one.test.sh"
LP1_LINE="$(tail -n 1 "$(stamp_file "$LP1")")"
OUTLP1="$(worktree_land_for_session "$LP1" "$LP" "$LP_SID")"; RCLP1=$?
LP1_M="$(git -C "$LP" rev-parse refs/heads/wave/fixture)"
expect_eq "(p1) the land exits 0" "0" "$RCLP1"
expect_eq "(p1b) the LANDED line ends proofs=<the record's path>" \
  "spawn-worktree: LANDED branch=wt/27-T7 onto=wave/fixture checkout=${LP} merge=${LP1_M} removed=${LP1} proofs=${LP_LOG}" "$OUTLP1"
LP1_AT="$(lp_at "$(cat "$LP_LOG" 2>/dev/null)")"
expect_match "(p1c) at= is UTC, YYYY-MM-DDTHH:MM:SSZ" "$LP_ISO" "$LP1_AT"
expect_eq "(p1d) the record is the header and the one stamp line at the head, byte for byte" \
  "landed: row=T7 branch=wt/27-T7 head=${LP1_H} merge=${LP1_M} at=${LP1_AT}
${LP1_LINE}" "$(cat "$LP_LOG" 2>/dev/null)"
expect_eq "(p1e) merge= is the merge the land made: the target's head, whose second parent is head=" \
  "$LP1_H" "$(git -C "$LP" rev-parse "${LP1_M}^2")"

# (p2) THREE SUITES AT THE HEAD, ONE AT AN OLDER HEAD, A SECOND LANDING: the three lines are
# appended byte for byte, a `cmd=` holding `|` and quotes included; the older head's line is not
# copied; the first landing's block is kept above.
LP2="$(lp_tree wt/27-T8 27-T8)"; LP2_OLD="$(git -C "$LP2" rev-parse HEAD)"
lp_stamp "$LP2" "$LP2_OLD" 0 a.test.sh "bash tests/a.test.sh"
echo "$RANDOM$RANDOM$RANDOM" >> "$LP2/27-T8.txt"; git -C "$LP2" commit --quiet -am "T8 second"
LP2_H="$(git -C "$LP2" rev-parse HEAD)"
lp_stamp "$LP2" "$LP2_H" 0 a.test.sh "bash tests/a.test.sh"
lp_stamp "$LP2" "$LP2_H" 0 b.test.sh "LOG=x; set -o pipefail; bash tests/b.test.sh 2>&1 | tee \"\$LOG\"; echo 'rc'"
lp_stamp "$LP2" "$LP2_H" 0 c.test.sh "bash tests/c.test.sh|cat"
LP2_LINES="$(tail -n 3 "$(stamp_file "$LP2")")"
LP2_OLDLINE="$(head -n 1 "$(stamp_file "$LP2")")"
LP_BEFORE2="$(cat "$LP_LOG" 2>/dev/null)"
OUTLP2="$(worktree_land_for_session "$LP2" "$LP" "$LP_SID")"
LP2_M="$(git -C "$LP" rev-parse refs/heads/wave/fixture)"
expect_match "(p2) the second tree lands, naming the same record" "spawn-worktree: LANDED branch=wt/27-T8 * proofs=${LP_LOG}" "$OUTLP2"
LP2_AT="$(lp_at "$(cat "$LP_LOG" 2>/dev/null)")"
expect_eq "(p2b) the record is the first block, kept, then the new header and the three lines at the head" \
  "${LP_BEFORE2}
landed: row=T8 branch=wt/27-T8 head=${LP2_H} merge=${LP2_M} at=${LP2_AT}
${LP2_LINES}" "$(cat "$LP_LOG" 2>/dev/null)"
expect_contains "(p2c) fixture: the older head's line exists in the stamp file" "head=${LP2_OLD}|" "$LP2_OLDLINE"
expect_absent "(p2d) …and is not copied" "head=${LP2_OLD}|" "$(cat "$LP_LOG" 2>/dev/null)"
expect_contains "(p2e) the cmd= with | and quotes is kept whole" \
  "|cmd=LOG=x; set -o pipefail; bash tests/b.test.sh 2>&1 | tee \"\$LOG\"; echo 'rc'" "$(cat "$LP_LOG" 2>/dev/null)"

# (p3) A ROW LANDED TWICE: a second landing of the same branch from a new tree appends a second
# header for T7 and keeps the first.
LP3="$(lp_tree wt/27-T7 27-T7)"; LP3_H="$(git -C "$LP3" rev-parse HEAD)"
lp_stamp "$LP3" "$LP3_H" 0 one.test.sh "bash tests/one.test.sh"
expect_match "(p3) the same row's branch lands a second time" "spawn-worktree: LANDED branch=wt/27-T7 * proofs=${LP_LOG}" \
  "$(worktree_land_for_session "$LP3" "$LP" "$LP_SID")"
LP3_M="$(git -C "$LP" rev-parse refs/heads/wave/fixture)"
expect_eq "(p3b) two T7 headers, the first landing's and this one's, in order" \
  "landed: row=T7 branch=wt/27-T7 head=${LP1_H} merge=${LP1_M}
landed: row=T7 branch=wt/27-T7 head=${LP3_H} merge=${LP3_M}" \
  "$(grep '^landed: row=T7 ' "$LP_LOG" | sed 's/ at=.*//')"

# (p4) A TREE NO ROW NAMES: row=—.
LP4="$(lp_tree wt/27-T99 27-T99)"; green_stamp "$LP4"
expect_match "(p4) a tree no row names lands" "spawn-worktree: LANDED branch=wt/27-T99 * proofs=${LP_LOG}" \
  "$(worktree_land_for_session "$LP4" "$LP" "$LP_SID")"
expect_eq "(p4b) its header carries row=—" "landed: row=— branch=wt/27-T99" \
  "$(tail -n 2 "$LP_LOG" | head -n 1 | sed 's/ head=.*//')"

# (p5) TWO ROWS NAMING ONE TREE: the first in table order.
lp_bind '| T20 | 4 | build | twenty | .worktrees/27-T20 | active |
| T21 | 4 | build | twenty-one | .worktrees/27-T20 | active |'
LP5="$(lp_tree wt/27-T20 27-T20)"; green_stamp "$LP5"
worktree_land_for_session "$LP5" "$LP" "$LP_SID" >/dev/null
expect_eq "(p5) two rows name the tree: the header carries the first, T20" "landed: row=T20 branch=wt/27-T20" \
  "$(tail -n 2 "$LP_LOG" | head -n 1 | sed 's/ head=.*//')"
lp_bind '| T7 | 4 | build | seven | .worktrees/27-T7 | active |'

# (p6) THE RECORD CANNOT BE WRITTEN: refused why=proofs-unwritable before the merge, and the
# target's head, the tree and its stamp file are as they were. The arm discriminates: the same
# tree lands once the record can be written.
LP6="$(lp_tree wt/27-T7 27-T7)"; green_stamp "$LP6"
LP6_LOGB="$(cat "$LP_LOG")"; LP6_TGT="$(git -C "$LP" rev-parse refs/heads/wave/fixture)"
LP6_TREES="$(trees_of "$LP")"; LP6_ST="$(cat "$(stamp_file "$LP6")")"
chmod 444 "$LP_LOG"
OUTLP6="$(worktree_land_for_session "$LP6" "$LP" "$LP_SID")"; RCLP6=$?
chmod 644 "$LP_LOG"
expect_match "(p6) an unwritable record refuses the landing why=proofs-unwritable, naming it" \
  "spawn-worktree: REFUSED reason=record-unwritable why=proofs-unwritable path=${LP_LOG} branch=wt/27-T7 — *" "$OUTLP6"
expect_eq "(p6b) …exit 2" "2" "$RCLP6"
expect_eq "(p6c) the target branch's head is as before" "$LP6_TGT" "$(git -C "$LP" rev-parse refs/heads/wave/fixture)"
expect_eq "(p6d) every worktree is as before: the tree stands" "$LP6_TREES" "$(trees_of "$LP")"
expect_eq "(p6e) the stamp file is as before" "$LP6_ST" "$(cat "$(stamp_file "$LP6")")"
expect_eq "(p6f) the record is as before" "$LP6_LOGB" "$(cat "$LP_LOG")"
expect_true "(p6g) the link to the record still resolves" link_ok "$LP6"
expect_match "(p6h) the same tree lands once the record is writable" \
  "spawn-worktree: LANDED branch=wt/27-T7 * proofs=${LP_LOG}" "$(worktree_land_for_session "$LP6" "$LP" "$LP_SID")"

# (p7) THE APPEND FAILS AFTER THE MERGE: a post-merge hook makes the record read-only once the
# merge is made. The merge stands, the LANDED line says proofs=unwritten, and the tree and its
# stamp file are kept so the proof is not lost.
LP7="$(lp_tree wt/27-T7 27-T7)"; green_stamp "$LP7"
LP7_ST="$(cat "$(stamp_file "$LP7")")"; LP7_LOGB="$(cat "$LP_LOG")"
LP_HOOK="$(git -C "$LP" rev-parse --absolute-git-dir)/hooks/post-merge"   # LP is the main checkout: its git dir is the common one
expect_match "(p7-pre) fixture: the hook path is absolute, inside the fixture" "${LP}/.git/hooks/post-merge" "$LP_HOOK"
mkdir -p "${LP_HOOK%/*}"; printf '#!/bin/sh\nchmod 444 "%s"\n' "$LP_LOG" > "$LP_HOOK"; chmod +x "$LP_HOOK"
OUTLP7="$(worktree_land_for_session "$LP7" "$LP" "$LP_SID")"; RCLP7=$?
rm -f "$LP_HOOK"; chmod 644 "$LP_LOG"
LP7_M="$(git -C "$LP" rev-parse refs/heads/wave/fixture)"
expect_eq "(p7) fixture: the hook made the merge, then the record read-only" "$(git -C "$LP7" rev-parse HEAD)" \
  "$(git -C "$LP" rev-parse "${LP7_M}^2")"
expect_match "(p7b) the LANDED line says proofs=unwritten and keeps the tree" \
  "spawn-worktree: LANDED branch=wt/27-T7 onto=wave/fixture checkout=${LP} merge=${LP7_M} kept=${LP7} proofs=unwritten *" "$OUTLP7"
expect_eq "(p7c) …exit 0: the landing is made" "0" "$RCLP7"
expect_true "(p7d) the tree stands" test -d "$LP7"
expect_eq "(p7e) its stamp file is whole" "$LP7_ST" "$(cat "$(stamp_file "$LP7")")"
expect_eq "(p7f) the record is unchanged" "$LP7_LOGB" "$(cat "$LP_LOG")"
rm -f "$LP7/.bionic"; git -C "$LP" worktree remove "$LP7" >/dev/null 2>&1

# (p8) NO BOUND PLAN: `worktree_land` called with no plan prints proofs=none and writes no record.
LP8R="$(new_repo "$TMP/land-proofs-none")"
LP8="$(new_tree "$LP8R" wt/none)"; green_stamp "$LP8"
OUTLP8="$(worktree_land "$LP8" wave/fixture)"
expect_match "(p8) a landing with no bound plan prints proofs=none" \
  "spawn-worktree: LANDED branch=wt/none onto=wave/fixture checkout=${LP8R} merge=* removed=${LP8} proofs=none" "$OUTLP8"
expect_eq "(p8b) fixture: the finder sees the bound plan's record" "$LP_LOG" "$(find "$LP/.bionic" -name landing-proofs.log)"
expect_eq "(p8c) …and no landing record is written without a plan" "" "$(find "$LP8R/.bionic" -name landing-proofs.log)"

# (p9) THE why=head REFUSAL NAMES WHERE IT LOOKED: the stamp file's path and the head.
LP9="$(new_tree "$LP8R" wt/elsewhere)"
stamp "$LP9" 0000000000000000000000000000000000000000 0 0
LP9_H="$(git -C "$LP9" rev-parse HEAD)"
expect_match "(p9) why=head names the stamp file and the head it looked for" \
  "spawn-worktree: REFUSED reason=stale-proof why=head stamp_head=0000000000000000000000000000000000000000 head=${LP9_H} stamps=$(stamp_file "$LP9") — *" \
  "$(worktree_land "$LP9" wave/fixture)"

section "§LAND-RECORD-HARDENING: the record is appended under a lock and read as a regular file (wave-27 T50; review pass 27 S1, N1, N2, N4)"
#
# S1. Appends to the record are serialized by a lock directory beside it (`<record>.lock`, made
# with `mkdir`), so one landing's header and its stamp lines are contiguous. A lock it cannot take
# inside ten seconds is the `proofs=unwritten` case. A lock directory left by a killed landing is
# stale when its holder's pid is gone, or when it is older than sixty seconds, and is then taken
# over. N1, N2. The record path is a regular file or absent: a symlink, a FIFO, a device or a
# directory there refuses the landing before the merge and is never opened, and a record file the
# proof created is removed again when the landing is then refused. N4. A `worktree` cell is read
# after a leading `./` and trailing slashes are dropped; a row id holding a blank is written `—`.
expect_eq "(T50-s1-pre) the lock is waited for ten seconds by default" "10" \
  "$(bash -c '. "$1"; printf %s "$_WT_PROOFS_LOCK_WAIT"' _ "$LIB")"
expect_eq "(T50-s1-pre2) …and a lock directory is stale after sixty seconds" "60" \
  "$(bash -c '. "$1"; printf %s "$_WT_PROOFS_LOCK_STALE"' _ "$LIB")"

# (s1) TWO PROCESSES APPEND AT ONCE, a hundred times each, a header and twenty stamp lines per
# block: in the record every header is followed by exactly its own twenty lines, in order.
LK_REC="$TMP/lk-record.log"
cat > "$TMP/lk-child.sh" <<'LK_EOF'
. "$1" || exit 9
f="$2"; tag="$3"; lines=""
for i in $(seq 1 20); do
  lines="${lines}${lines:+
}stamp/v1|tag=${tag}|n=${i}|pad=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
done
for r in $(seq 1 100); do
  _wt_proofs_append "$f" "R${tag}" "br-${tag}" "$(printf '%040d' "$r")" "$(printf '%040d' "$r")" "$lines" || echo "FAILED ${tag} ${r}"
done
LK_EOF
bash "$TMP/lk-child.sh" "$LIB" "$LK_REC" A > "$TMP/lk-out-a" 2>&1 &
LK_PA=$!
bash "$TMP/lk-child.sh" "$LIB" "$LK_REC" B > "$TMP/lk-out-b" 2>&1 &
LK_PB=$!
wait "$LK_PA" "$LK_PB"
lk_verdict() {  # <record> -> "OK headers=<n> lines=<n>" or the first block that is not contiguous
  awk '
    /^landed: / { if (want) { bad = "short block before line " NR; exit } tag = $2; sub(/^row=R/, "", tag); want = 20; n = 0; hdr++; next }
    /^stamp\/v1/ {
      if (!want) { bad = "stamp line outside a block at line " NR; exit }
      split($0, f, "|"); t = f[2]; sub(/^tag=/, "", t); k = f[3]; sub(/^n=/, "", k)
      if (t != tag || k + 0 != n + 1) { bad = "line " NR " is " t "/" k " under " tag "/" n + 1; exit }
      n++; want--; lines++; next }
    END { if (bad) print "BAD " bad; else if (want) print "BAD last block short"; else print "OK headers=" hdr " lines=" lines }' "$1"
}
expect_eq "(T50-s1) 200 blocks from two writers: every header is followed by exactly its own twenty lines" \
  "OK headers=200 lines=4000" "$(lk_verdict "$LK_REC")"
expect_eq "(T50-s1b) …neither writer reported a failed append" "" "$(cat "$TMP/lk-out-a" "$TMP/lk-out-b")"
expect_false "(T50-s1c) …and no lock directory is left behind" test -e "${LK_REC}.lock"
printf 'landed: row=RX\nstamp/v1|tag=Y|n=1\n' > "$TMP/lk-bad.log"
expect_match "(T50-s1d) the verdict can fail: a block with a line under the wrong header is reported" "BAD *" "$(lk_verdict "$TMP/lk-bad.log")"

# (s1e) A LOCK HELD BY ANOTHER, LIVE PROCESS: the append waits, then fails; the record is untouched and
# the other's lock is not taken over. A lock older than the stale age, or whose holder is gone, is
# taken over and the append is made. The wait is shortened to one second for the rows.
LK_WAIT="${_WT_PROOFS_LOCK_WAIT:-10}"; _WT_PROOFS_LOCK_WAIT=1
LK_F="$TMP/lk-held.log"; echo "earlier" > "$LK_F"
sleep 120 & LK_LIVE=$!
mkdir "${LK_F}.lock"; echo "$LK_LIVE" > "${LK_F}.lock/pid"
LK_T0=$SECONDS
_wt_proofs_append "$LK_F" R9 br 1111111111111111111111111111111111111111 2222222222222222222222222222222222222222 "stamp/v1|x"; LK_RC=$?
LK_DT=$((SECONDS - LK_T0))
expect_true "(T50-s1e) a lock held by a live process, fresh: the append is not made" test "$LK_RC" -ne 0
expect_true "(T50-s1f) …it waited for the lock (took ${LK_DT}s of a 1s wait)" test "$LK_DT" -ge 1
expect_eq "(T50-s1g) …the record is untouched" "earlier" "$(cat "$LK_F")"
expect_true "(T50-s1h) …and the other's lock is still there" test -d "${LK_F}.lock"
touch -t 202001010000 "${LK_F}.lock"
_wt_proofs_append "$LK_F" R9 br 1111111111111111111111111111111111111111 2222222222222222222222222222222222222222 "stamp/v1|x"; LK_RC=$?
expect_eq "(T50-s1i) a lock older than the stale age is taken over: the append is made" "0|3" \
  "$LK_RC|$(awk 'END { print NR }' "$LK_F")"
expect_false "(T50-s1j) …and its lock is gone" test -e "${LK_F}.lock"
kill "$LK_LIVE" 2>/dev/null; wait "$LK_LIVE" 2>/dev/null
true & LK_DEAD=$!; wait "$LK_DEAD"
mkdir "${LK_F}.lock"; echo "$LK_DEAD" > "${LK_F}.lock/pid"
_wt_proofs_append "$LK_F" R9 br 1111111111111111111111111111111111111111 2222222222222222222222222222222222222222 "stamp/v1|x"; LK_RC=$?
expect_eq "(T50-s1k) a fresh lock whose holder is gone is taken over too" "0|5" "$LK_RC|$(awk 'END { print NR }' "$LK_F")"
chmod 444 "$LK_F"
_wt_proofs_append "$LK_F" R9 br 1111111111111111111111111111111111111111 2222222222222222222222222222222222222222 "stamp/v1|x"; LK_RC=$?
chmod 644 "$LK_F"
expect_true "(T50-s1l) a record that cannot be written fails the append" test "$LK_RC" -ne 0
expect_false "(T50-s1m) …and the lock is released on that path too" test -e "${LK_F}.lock"

# (s1n) THROUGH `land`: a lock another landing holds is the proofs=unwritten case; the merge stands,
# the tree and its stamps are kept, and the record is as it was.
lp_bind '| T7 | 4 | build | seven | .worktrees/27-T7 | active |'
LPK="$(lp_tree wt/27-T7 27-T7)"; green_stamp "$LPK"
LPK_ST="$(cat "$(stamp_file "$LPK")")"; LPK_LOGB="$(cat "$LP_LOG")"
sleep 120 & LK_LIVE=$!
mkdir "${LP_LOG}.lock"; echo "$LK_LIVE" > "${LP_LOG}.lock/pid"
OUTLPK="$(worktree_land_for_session "$LPK" "$LP" "$LP_SID")"; RCLPK=$?
LPK_M="$(git -C "$LP" rev-parse refs/heads/wave/fixture)"
expect_match "(T50-s1n) a record locked by another landing: the merge stands, proofs=unwritten, the tree is kept" \
  "spawn-worktree: LANDED branch=wt/27-T7 onto=wave/fixture checkout=${LP} merge=${LPK_M} kept=${LPK} proofs=unwritten *" "$OUTLPK"
expect_eq "(T50-s1o) …exit 0, the record as it was, the stamp file whole" "0|$LPK_LOGB|$LPK_ST" \
  "$RCLPK|$(cat "$LP_LOG")|$(cat "$(stamp_file "$LPK")")"
kill "$LK_LIVE" 2>/dev/null; wait "$LK_LIVE" 2>/dev/null
rm -rf "${LP_LOG}.lock"; _WT_PROOFS_LOCK_WAIT="$LK_WAIT"
rm -f "$LPK/.bionic"; git -C "$LP" worktree remove "$LPK" >/dev/null 2>&1

# (n1, n2) THE RECORD PATH IS A REGULAR FILE OR ABSENT. One tree, refused each time, then landed once
# the record is a regular file again (the arm discriminates). A FIFO is held open read-write by
# this suite, so a land that opened it would not block: it would land, and the row would fail.
LPN="$(lp_tree wt/27-T7 27-T7)"; green_stamp "$LPN"
mv "$LP_LOG" "${LP_LOG}.keep"
LPN_TGT="$(git -C "$LP" rev-parse refs/heads/wave/fixture)"; LPN_TREES="$(trees_of "$LP")"; LPN_ST="$(cat "$(stamp_file "$LPN")")"
lp_case() {  # <label> — lands LPN with the record as the caller left it; every refusal is the same
  local l="$1" out rc
  out="$(worktree_land_for_session "$LPN" "$LP" "$LP_SID" 2>&1)"; rc=$?
  expect_match "(T50-$l) refused why=proofs-unwritable, naming the record" \
    "spawn-worktree: REFUSED reason=record-unwritable why=proofs-unwritable path=${LP_LOG} branch=wt/27-T7 — *" "$out"
  expect_eq "(T50-$l-b) …exit 2, the target's head and every worktree as before, the stamp file whole" \
    "2|$LPN_TGT|$LPN_TREES|$LPN_ST" "$rc|$(git -C "$LP" rev-parse refs/heads/wave/fixture)|$(trees_of "$LP")|$(cat "$(stamp_file "$LPN")")"
}
LP_OUT="$TMP/lp-outside.log"; echo "outside" > "$LP_OUT"
ln -s /dev/null "$LP_LOG";  lp_case n2-devnull;  rm -f "$LP_LOG"
ln -s "$LP_OUT" "$LP_LOG";  lp_case n2-symlink;  rm -f "$LP_LOG"
expect_eq "(T50-n2-symlink-c) …and the file the link pointed at was never appended to" "outside" "$(cat "$LP_OUT")"
ln -s "$TMP/lp-nowhere" "$LP_LOG"; lp_case n2-dangling; rm -f "$LP_LOG"
expect_false "(T50-n2-dangling-c) …and the dangling link's target was not created" test -e "$TMP/lp-nowhere"
mkfifo "$LP_LOG"; exec 9<>"$LP_LOG"; lp_case n2-fifo; exec 9>&-; rm -f "$LP_LOG"
mkdir "$LP_LOG";  lp_case n1-directory; rmdir "$LP_LOG"
expect_true "(T50-n2-device-pre) the proof helper exists" declare -F _wt_proofs_prove
expect_false "(T50-n2-device) a device node is refused by the helper itself, before any open" _wt_proofs_prove /dev/null
mv "${LP_LOG}.keep" "$LP_LOG"
expect_match "(T50-n2-arm) the same tree lands once the record is a regular file" \
  "spawn-worktree: LANDED branch=wt/27-T7 * proofs=${LP_LOG}" "$(worktree_land_for_session "$LPN" "$LP" "$LP_SID")"

# (n1) A RECORD FILE THE PROOF CREATED IS REMOVED WHEN THE LANDING IS THEN REFUSED. A failing
# pre-merge-commit hook refuses the landing after the proof; with no record before, none after; with
# earlier landings in it, the record is untouched. A declared check refuses before the proof is
# taken, so it leaves no file either.
LPE="$(lp_tree wt/27-T7 27-T7)"; green_stamp "$LPE"
LP_PMC="$(git -C "$LP" rev-parse --absolute-git-dir)/hooks/pre-merge-commit"
mkdir -p "${LP_PMC%/*}"; printf '#!/bin/sh\nexit 1\n' > "$LP_PMC"; chmod +x "$LP_PMC"
mv "$LP_LOG" "${LP_LOG}.keep"
OUTLPE="$(worktree_land_for_session "$LPE" "$LP" "$LP_SID" 2>&1)"; RCLPE=$?
expect_match "(T50-n1) fixture: the landing is refused after the proof (merge-failed)" "spawn-worktree: REFUSED reason=merge-failed *" "$OUTLPE"
expect_false "(T50-n1b) the empty record the proof created is gone" test -e "$LP_LOG"
cp "${LP_LOG}.keep" "$LP_LOG"; LPE_B="$(cat "$LP_LOG")"
worktree_land_for_session "$LPE" "$LP" "$LP_SID" >/dev/null 2>&1
expect_eq "(T50-n1c) a record that already held landings is untouched by a refusal" "$LPE_B" "$(cat "$LP_LOG")"
: > "$LP_LOG"
worktree_land_for_session "$LPE" "$LP" "$LP_SID" >/dev/null 2>&1
expect_true "(T50-n1d) an empty record that was already there is not the proof's to remove" test -f "$LP_LOG"
rm -f "$LP_PMC"; rm -f "$LP_LOG"
printf 'release-check: sh -c false\n' > "$LP/.bionic/config.yaml"
OUTLPE2="$(worktree_land_for_session "$LPE" "$LP" "$LP_SID" 2>&1)"
expect_match "(T50-n1e) fixture: a declared check refuses the landing" "spawn-worktree: REFUSED reason=check-failed why=release-check *" "$OUTLPE2"
expect_false "(T50-n1f) …and leaves no record file" test -e "$LP_LOG"
rm -f "$LP/.bionic/config.yaml"
mv "${LP_LOG}.keep" "$LP_LOG"
worktree_land_for_session "$LPE" "$LP" "$LP_SID" >/dev/null 2>&1
test -d "$LPE" && { rm -f "$LPE/.bionic"; git -C "$LP" worktree remove "$LPE" >/dev/null 2>&1; }

# (n4) THE row= EDGES. A cell is read after a leading ./ and trailing slashes are dropped; a row id
# holding a blank is written as —. The helper is driven for the spellings, the landing for the id.
LP_T="$LP/.worktrees/27-T7"
for _cell in '.worktrees/27-T7' '.worktrees/27-T7/' './.worktrees/27-T7' '.worktrees/27-T7//' './.worktrees/27-T7//' "$LP_T/"; do
  lp_bind "| T7 | 4 | build | seven | ${_cell} | active |"
  expect_eq "(T50-n4) the cell '${_cell}' names the tree" "T7" "$(_wt_proofs_row "$LP" "$LP_PLAN" "$LP_T")"
done
lp_bind '| T7 | 4 | build | seven | .worktrees/27-T7/ | active |'
expect_eq "(T50-n4b) …and a tree no cell names has no row" "" "$(_wt_proofs_row "$LP" "$LP_PLAN" "$LP/.worktrees/27-T8")"
lp_bind '| T 7 | 4 | build | seven | .worktrees/27-T7 | active |'
LPB="$(lp_tree wt/27-T7 27-T7)"; green_stamp "$LPB"
worktree_land_for_session "$LPB" "$LP" "$LP_SID" >/dev/null 2>&1
expect_match "(T50-n4c) a row id holding a blank is written row=— in the header" "landed: row=— branch=wt/27-T7 head=*" \
  "$(tail -n 2 "$LP_LOG" | head -n 1)"
lp_bind '| T7 | 4 | build | seven | .worktrees/27-T7 | active |'
LPB2="$(lp_tree wt/27-T7 27-T7)"; green_stamp "$LPB2"
worktree_land_for_session "$LPB2" "$LP" "$LP_SID" >/dev/null 2>&1
expect_match "(T50-n4d) the arm discriminates: the same tree under an id without a blank is row=T7" "landed: row=T7 branch=wt/27-T7 head=*" \
  "$(tail -n 2 "$LP_LOG" | head -n 1)"

finish
