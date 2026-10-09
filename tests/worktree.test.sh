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
# The landing line (wave-28 T3): `land --by-hand` and §LAND-BIONIC's drive. Sourced when present, so
# a tree without it reads every row that needs it red rather than stopping here.
LINE_LIB="${REPO}/payload/scripts/lib/line.sh"
# shellcheck source=/dev/null
[ -r "$LINE_LIB" ] && . "$LINE_LIB" 2>/dev/null
export BIONIC_GATE_DIR="$TMP/gate"

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

section "§LAND-BUSY-GATE: the busy check reads the gate's requests (wave-28 T12; D10)"
#
# A RUN THE GATE ADMITTED IS A RUN (T12). Every suite now asks the gate, the runner's included,
# each for itself, and the request records the tree it runs in (`tree=`, git's toplevel where
# it asked). So the land refuses while an admitted, unfinished request whose holder is alive
# names the project's main checkout or the land's target checkout as its tree. A request in a
# writer's own tree does not refuse (a writer's suite would otherwise refuse every land of the
# wave, the reason D1 once counted only the runner); a waiting request has run nothing; an
# ended or killed one runs nothing. The store is this suite's own.
export BIONIC_GATE_DIR="$TMP/gate"
GB="$(new_repo "$TMP/busy-gate")"
GB_HOLD=""
gb_holder() {  # -> GB_HOLD, a live process that is not this shell's child (no zombie)
  GB_HOLD="$( ( sleep 60 >/dev/null 2>&1 & printf '%s' "$!" ) )"
}
gb_plant() {  # <id> <tree> <holder pid> [admitted|waiting|ended] — one request file
  local st
  st="$(LC_ALL=C TZ=UTC0 ps -o lstart= -p "$3" 2>/dev/null | awk '{ $1 = $1; print }')"
  mkdir -p "$BIONIC_GATE_DIR/requests"
  { printf 'key=x.test.sh\nkind=work\nwho=fixture:w\ntree=%s\nasked=1000\nholder=%s:%s\n' "$2" "$3" "$st"
    case "${4:-admitted}" in
      admitted) printf 'admitted=1001\npromise=1:0.5:10\n' ;;
      ended) printf 'admitted=1001\npromise=1:0.5:10\nended=1002\nrc=0\n' ;;
    esac
  } > "$BIONIC_GATE_DIR/requests/$1"
}
gb_clear() { rm -rf "$BIONIC_GATE_DIR"; [ -z "$GB_HOLD" ] || kill "$GB_HOLD" 2>/dev/null; GB_HOLD=""; }
trap 'gb_clear; stop_runner; stop_mention; rm -rf "$TMP"' EXIT

GBT1="$(new_tree "$GB" gate-root)"
gb_holder; gb_plant 7 "$GB" "$GB_HOLD"
GBREFS0="$(refs_of "$GB")"
OUTG1="$(worktree_land "$GBT1" wave/fixture)"; RCG1=$?
expect_match "an admitted run in the main checkout refuses the land" \
  "spawn-worktree: REFUSED reason=suite-running*" "$OUTG1"
expect_match "…naming the request, its key and its tree" "*request=7 key=x.test.sh tree=${GB} *" "$OUTG1"
expect_match "…and its holder" "*holder=${GB_HOLD}*" "$OUTG1"
expect_eq    "the refusal exits 2" "2" "$RCG1"
expect_eq    "no ref moved" "$GBREFS0" "$(refs_of "$GB")"
gb_plant 7 "$GB" "$GB_HOLD" waiting
expect_match "a request that is only waiting has run nothing: the land goes through" \
  "spawn-worktree: LANDED branch=gate-root *" "$(worktree_land "$GBT1" wave/fixture)"
gb_clear

GBT2="$(new_tree "$GB" gate-ended)"
gb_holder; gb_plant 8 "$GB" "$GB_HOLD" ended
expect_match "an ended request does not refuse" \
  "spawn-worktree: LANDED branch=gate-ended *" "$(worktree_land "$GBT2" wave/fixture)"
gb_clear

GBT3="$(new_tree "$GB" gate-dead)"
gb_holder; gb_plant 9 "$GB" "$GB_HOLD"; kill "$GB_HOLD" 2>/dev/null
i=0; while kill -0 "$GB_HOLD" 2>/dev/null && [ "$i" -lt 100 ]; do i=$((i + 1)); sleep 0.05; done
GB_HOLD=""
expect_match "an admitted request whose holder is dead (killed) does not refuse" \
  "spawn-worktree: LANDED branch=gate-dead *" "$(worktree_land "$GBT3" wave/fixture)"
gb_clear

GBT4="$(new_tree "$GB" gate-writer)"
GBW="$(new_tree "$GB" gate-writers-own)"
gb_holder; gb_plant 10 "$GBW" "$GB_HOLD"
expect_match "a run in a writer's own tree does not refuse another tree's land" \
  "spawn-worktree: LANDED branch=gate-writer *" "$(worktree_land "$GBT4" wave/fixture)"
gb_clear

GBO="$(new_repo "$TMP/busy-gate-other")"
GBT5="$(new_tree "$GB" gate-other)"
gb_holder; gb_plant 11 "$GBO" "$GB_HOLD"
expect_match "a run in another repository does not refuse" \
  "spawn-worktree: LANDED branch=gate-other *" "$(worktree_land "$GBT5" wave/fixture)"
gb_clear

GBWAVE="$TMP/busy-gate-outside-wave"
git -C "$GB" worktree add --quiet -b wave/gout "$GBWAVE" wave/fixture >/dev/null 2>&1
GBWAVE="$(cd "$GBWAVE" && pwd -P)"
GBT6="$(new_tree "$GB" gate-into-outside)"
gb_holder; gb_plant 12 "$GBWAVE" "$GB_HOLD"
OUTG6="$(worktree_land "$GBT6" wave/gout)"; RCG6=$?
expect_match "an admitted run in the TARGET checkout, outside the root, refuses" \
  "spawn-worktree: REFUSED reason=suite-running request=12 *tree=${GBWAVE} *" "$OUTG6"
expect_eq    "that refusal exits 2" "2" "$RCG6"
gb_clear
expect_match "the same land goes through once that run is gone" \
  "spawn-worktree: LANDED branch=gate-into-outside onto=wave/gout *" "$(worktree_land "$GBT6" wave/gout)"

# THE REAL SHIM, NOT A PLANTED FILE (wave-28 T36; ruling A-orch-55/56). The rows above write their
# request files by hand, which is how no suite saw the shim name its own cwd as the tree: the
# doctrine's `cd <row tree> || exit 1; bash tests/x.test.sh`, wrapped from the main checkout with
# `--stamp-dir <row tree>`, wrote `tree=<main checkout>` and refused every land as suite-running.
# These rows drive payload/scripts/booked.sh itself, from the main checkout, holding mid-run.
GB_SHIM="${REPO}/payload/scripts/booked.sh"
gb_shim_bg() {  # <stamp dir or ""> <command> — the real shim, started in the main checkout; GB_SHIM_PID
  ( cd "$GB" && BIONIC_PROBE_USED_PCT=10 BIONIC_PROBE_BUSY_CORES=0 BIONIC_PROBE_BUSY_CORES_5M=0 \
      BIONIC_PROBE_CORES=8 BIONIC_PROBE_TOTAL_MB=8192 BIONIC_GATE_POLL=0.1 \
      bash "$GB_SHIM" --agent w-own --max-wait 60 ${1:+--stamp-dir "$1"} --suites x.test.sh -- "$2" \
      >/dev/null 2>&1 ) &
  GB_SHIM_PID=$!
}
gb_admitted() {  # rc 0 once a request in the store carries an admitted line
  local i=0
  while [ "$i" -lt 200 ]; do
    grep -qs '^admitted=' "$BIONIC_GATE_DIR"/requests/* && return 0
    i=$((i + 1)); sleep 0.05
  done
  return 1
}
gb_shim_end() {  # <go file> — let the held command end, and wait for the shim
  touch "$1"; wait "$GB_SHIM_PID" 2>/dev/null; GB_SHIM_PID=""
}
GBW7="$(new_tree "$GB" gate-shim-own)"
GBT7="$(new_tree "$GB" gate-shim-land)"
gb_clear
gb_shim_bg "" "while [ ! -f '$TMP/gb7a.go' ]; do sleep 0.05; done"
expect_true "the real shim, run in the main checkout, is admitted" gb_admitted
expect_match "…and its run makes the main checkout busy: the land refuses (the positive for the row below)" \
  "spawn-worktree: REFUSED reason=suite-running request=* tree=${GB} *" "$(worktree_land "$GBT7" wave/fixture)"
gb_shim_end "$TMP/gb7a.go"
gb_clear
gb_shim_bg "$GBW7" "cd '$GBW7' || exit 1; while [ ! -f '$TMP/gb7b.go' ]; do sleep 0.05; done"
expect_true "a writer's suite run from the main checkout (cd <tree>, --stamp-dir <tree>) is admitted" gb_admitted
expect_eq "…its request names the writer's tree, the stamp's tree" "$(cd "$GBW7" && pwd -P)" \
  "$(sed -n 's/^tree=//p' "$BIONIC_GATE_DIR"/requests/* 2>/dev/null | tail -n 1)"
expect_match "…and it does not make the main checkout busy: another tree lands" \
  "spawn-worktree: LANDED branch=gate-shim-land *" "$(worktree_land "$GBT7" wave/fixture)"
gb_shim_end "$TMP/gb7b.go"
gb_clear

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

section "Group 7: the land VERB — spawn-worktree.sh land <path> --by-hand --reason <why>"
#
# The verb is a call site, not a second implementation: what is asserted here
# is the wiring and the exit codes a caller reads. Since wave-28 T3 (D9) a person lands a row with
# `--by-hand --reason`, through the line's one publish; a bare `land` refuses (§BY-HAND).

# THE VERB NAMES NO TARGET (T8, D1): the session's bound plan does, through
# worktree_land_for_session — the one path standdown calls too. So the verb runs with a
# session id, and that session is bound to a plan whose working branch the fixture holds.
V="$(new_repo "$TMP/verb")"
VSID="verb-session-0001"
bind_plan "$V" "$VSID" wave/fixture >/dev/null
VT="$(new_tree "$V" verb-arm)"
OUTV="$( cd "$V" && CLAUDE_CODE_SESSION_ID="$VSID" bash "$SPAWN" land "$VT" --by-hand --reason r 2>/dev/null )"
expect_match "the verb lands onto the bound plan's working branch, naming it" \
  "spawn-worktree: LANDED branch=verb-arm onto=wave/fixture checkout=${V} *" "$OUTV"
expect_false "the tree is gone" test -d "$VT"

VD="$(new_tree "$V" verb-dirty)"
echo x >> "${VD}/file.txt"
RCV="$( cd "$V" && CLAUDE_CODE_SESSION_ID="$VSID" bash "$SPAWN" land "$VD" --by-hand --reason r >/dev/null 2>&1; echo $? )"
expect_eq "a refused land exits 2" "2" "$RCV"
expect_match "land with no path is refused" "spawn-worktree: REFUSED *" \
  "$( cd "$V" && CLAUDE_CODE_SESSION_ID="$VSID" bash "$SPAWN" land --by-hand --reason r 2>/dev/null )"

# No session id at all: there is no binding to read, so there is no target.
git -C "$VD" checkout --quiet -- file.txt
VBEFORE="$(refs_of "$V")"
OUTVN="$( cd "$V" && env -u CLAUDE_CODE_SESSION_ID bash "$SPAWN" land "$VD" --by-hand --reason r 2>/dev/null )"; RCVN=$?
expect_match "the verb with no session id is refused, naming why" \
  "spawn-worktree: REFUSED reason=no-session*" "$OUTVN"
expect_eq   "that refusal exits 2" "2" "$RCVN"
expect_eq   "no ref moved" "$VBEFORE" "$(refs_of "$V")"
# A session that is not bound: the root's newest open run is somebody's, not this one's.
OUTVU="$( cd "$V" && CLAUDE_CODE_SESSION_ID="verb-unbound-0002" bash "$SPAWN" land "$VD" --by-hand --reason r 2>/dev/null )"
expect_match "the verb from an unbound session is refused, naming the fallback" \
  "spawn-worktree: REFUSED reason=no-bound-plan state=fallback*" "$OUTVU"
expect_eq   "no ref moved" "$VBEFORE" "$(refs_of "$V")"
expect_match "the same tree lands from the bound session (the arm discriminates)" \
  "spawn-worktree: LANDED branch=verb-dirty onto=wave/fixture *" \
  "$( cd "$V" && CLAUDE_CODE_SESSION_ID="$VSID" bash "$SPAWN" land "$VD" --by-hand --reason r 2>/dev/null )"
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
OUTVS="$( cd "$V" && CLAUDE_CODE_SESSION_ID="$VSID" bash "$SPAWN" land "$VSELF" --by-hand --reason r 2>/dev/null )"; RCVS=$?
expect_match "(T8c: was \"the verb's own busy suite does not refuse its own land\") the verb's own session's floor in the target checkout holds its own landing (wave-28 T3: HELD, D6)" \
  "*HELD verb-self-busy — pid=*cwd=${V} *" "$OUTVS"
expect_eq   "that refusal exits 2" "2" "$RCVS"
expect_eq   "no ref moved" "$VREFS0" "$(refs_of "$V")"
stop_runner

# The same session, its only runner in another repository: the verb lands.
expect_true "a stand-in runner started (relative, in another repository)" \
  start_runner "$VOTHERREPO" "tests/run.sh"
expect_match "a runner in another repository does not refuse the verb's land" \
  "spawn-worktree: LANDED branch=verb-self-busy onto=wave/fixture *" \
  "$( cd "$V" && CLAUDE_CODE_SESSION_ID="$VSID" bash "$SPAWN" land "$VSELF" --by-hand --reason r 2>/dev/null )"
stop_runner

# A runner in this root with NO session file at all (a human's terminal): still refused.
rm -f "$CLAUDE_HOME/sessions/$$.json"
VOTHER="$(new_tree "$V" verb-other-busy)"
expect_true "a stand-in runner started (cwd the root)" start_runner "$V" "$VELSE/tests/run.sh"
OUTVB="$( cd "$V" && CLAUDE_CODE_SESSION_ID="$VSID" bash "$SPAWN" land "$VOTHER" --by-hand --reason r 2>/dev/null )"; RCVB=$?
expect_match "a suite in the checkout that holds the branch, with no session file at all, still holds it" \
  "*HELD verb-other-busy — pid=*" "$OUTVB"
expect_eq   "that refusal exits 2" "2" "$RCVB"
stop_runner

section "§BY-HAND: a hand landing records who, when and why; a bare land names both ways (wave-28 T3; REQ-5 AC-5.1, D9)"
#
# `land <tree> --by-hand --reason '<why>'` builds the candidate, runs nothing, and publishes under the
# line's one lock (lib/line.sh `line_land_by_hand`). The `published kind=hand` event carries the git
# user, the time and the reason, and the row's `- T<n>:` line gains the same, written through the
# plan's one transaction. No reason is refused before anything is read; a bare `land` refuses with
# the line naming both ways.
BH="$(new_repo "$TMP/by-hand")"; git -C "$BH" config user.name "Hand Lander"
BHSID="by-hand-session-01"
BHT="$(new_tree "$BH" wt/bh-T1)"
BHP="$BH/.bionic/docs/plans/epic-x/wave-x.plan.md"; mkdir -p "${BHP%/*}" "$BH/.bionic/tmp"
cat > "$BHP" <<'BHPLAN'
---
working-branch: wave/fixture
canonical_sdlc_version: 14
---
# fixture plan (§BY-HAND)

## SDLC State

current: 4
approved-by: fixture 2026-10-04T00:00Z "approved"
- Step 4: started
- T1: active

## Tasks

| id | step | kind | task | agent | deps | reads | size | serves | Files | worktree | base | status |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| T1 | 4 | build | row one | bh-T1 | — | | 10 | REQ-1 | bh-T1.txt | .worktrees/bh-T1 | | active |
BHPLAN
printf 'plan=%s\nengaged_at=2026-09-23T00:00:00Z\n' "$BHP" > "$BH/.bionic/tmp/engaged-${BHSID}.state"
BHREC="$BH/.bionic/docs/record/wave-x/landing-proofs.log"
BH_REFS0="$(refs_of "$BH")"
bh_land() { ( cd "$BH" && CLAUDE_CODE_SESSION_ID="$BHSID" bash "$SPAWN" land "$@" 2>&1 ); }
OUTBH0="$(bh_land "$BHT" --by-hand)"; RCBH0=$?
expect_eq    "(h1) a hand landing with no --reason is refused (exit 2)" "2" "$RCBH0"
expect_match "(h1) …naming why" "spawn-worktree: REFUSED reason=no-reason *" "$OUTBH0"
OUTBH1="$(bh_land "$BHT" --by-hand --reason '')"; RCBH1=$?
expect_eq    "(h1) …and with an empty one" "2" "$RCBH1"
expect_eq    "(h1) …no ref moved" "$BH_REFS0" "$(refs_of "$BH")"
expect_false "(h1) …and nothing is recorded" test -e "$BHREC"
OUTBHB="$(bh_land "$BHT")"; RCBHB=$?
expect_ne    "(h2) a bare land exits non-zero" "0" "$RCBHB"
expect_eq    "(h2) …printing the line that names both ways, exactly" \
  "land: the line lands a row with \"ready\"; a person lands one with \"land <tree> --by-hand --reason '<why>'\"" "$OUTBHB"
expect_eq    "(h2) …and no ref moved" "$BH_REFS0" "$(refs_of "$BH")"
BHC="$(git -C "$BHT" rev-parse HEAD)"
OUTBH="$(bh_land "$BHT" --by-hand --reason "the person's why")"; RCBH=$?
expect_eq    "(h3) a hand landing with a reason exits 0" "0" "$RCBH"
expect_match "(h3) …on land's own LANDED line" "*spawn-worktree: LANDED branch=wt/bh-T1 onto=wave/fixture checkout=${BH} merge=* removed=${BHT} proofs=${BHREC}*" "$OUTBH"
expect_true  "(h3) the row's commit is on the working branch" git -C "$BH" merge-base --is-ancestor "$BHC" wave/fixture
BH_PUB="$(grep '^line/v1|ev=published|' "$BHREC" 2>/dev/null)"
expect_regex "(h4) the record's published line carries the user, the time and the reason" \
  "^line/v1\\|ev=published\\|row=T1\\|commit=$(git -C "$BH" rev-parse wave/fixture)\\|kind=hand\\|by=Hand Lander\\|why=the person's why\\|at=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$" "$BH_PUB"
BH_AT="${BH_PUB##*|at=}"
expect_eq    "(h5) the row's - T1: line gains who, when and why" \
  "- T1: active landed-by-hand: Hand Lander ${BH_AT} \"the person's why\"" "$(grep '^- T1:' "$BHP")"

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
gb_holder; gb_plant 31 "$LK" "$GB_HOLD"
expect_true "suite-running arm: the link resolves before the land" link_ok "$KS"
expect_match "suite-running is refused" "spawn-worktree: REFUSED reason=suite-running*" "$(worktree_land "$KS" wave/fixture)"
expect_true "after suite-running, the link still resolves" link_ok "$KS"
gb_clear

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
# BOUNDED: a private gate store, a suite that exits at once, a fake HOME, no plugins dir.
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
  # LS_SHORT=1: the wall's wrap as a SHORT call, its --kill-after arm, which stays in the foreground
  # (wave-30 T12, A-T12.11): a detached wrap waits at the gate until admitted, so a run the gate never
  # admits in time is a short call's.
  local q="'\\''" s="$1"
  [ "${LS_SHORT:-}" != 1 ] || s="${s/ --detach / --kill-after 30 }"
  s="${s//\'/$q}"
  ( cd "$LS" && env -u BIONIC_GATE_ADMIT -u BIONIC_GATE_AGENT -u BIONIC_QUIET -u BIONIC_NOW_EPOCH \
      BIONIC_GATE_DIR="$TMP/land-shim-gate" BIONIC_GATE_POLL=0.1 BIONIC_RUN_POLL=0.1 BIONIC_PROBE_BUSY_CORES=0 \
      BIONIC_PROBE_USED_PCT="${LS_USED:-10}" BIONIC_NOW_FILE="${LS_NOW_FILE:-}" \
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
    "bash *booked.sh --shell /bin/bash --agent at56shim-0123456789abcdef --detach --stamp-dir $t --suites a.test.sh -- *" "$w"
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
  "bash *booked.sh --shell /bin/bash --agent at56shim-0123456789abcdef --detach --stamp-dir $LS/.worktrees/su-typed-two-ways --suites a.test.sh -- *" "$LSU_WRAP"
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
  "bash *booked.sh --shell /bin/bash --agent at56shim-0123456789abcdef --detach --stamp-dir $LSH --suites a.test.sh,b.test.sh -- *" "$LSU_WRAP"
lsu_run "$LSH" a 0
expect_eq "(h) one line names both, red; then a alone, green" \
  "a.test.sh,b.test.sh:1 a.test.sh:0" "$(lsu_stamps "$LSH")"
expect_match "(h) b's newest stamp is still the red two-suite run: REFUSED, naming b" \
  "spawn-worktree: REFUSED reason=stale-proof why=red rc=1 suite=b.test.sh *" "$(worktree_land "$LSH" wave/fixture)"
lsu_run "$LSH" b 0
expect_match "(h) …and once b runs green alone the tree LANDS" \
  "spawn-worktree: LANDED branch=su-two-in-one onto=wave/fixture *" "$(worktree_land "$LSH" wave/fixture)"

# (i) A SUITE THE GATE NEVER ADMITTED (critic 3 S5; the gate since wave-28 T12). a runs green; b
# asks the gate on a machine planted over the share, and its call's limit runs out on a planted
# clock that jumps past it (75, nothing ran). Its line names b, so the land refuses on it; once b
# runs green the tree lands. Since wave-30 T12 the wall's wrap is detached and its run waits at the
# gate until admitted, so ls_waits runs the wall's own wrap as a SHORT call (--kill-after, LS_SHORT),
# the arm that still ends 75 when the gate does not admit it within its limit.
ls_waits() {  # <run function> <tree> <suite or runner> — one run the gate does not admit in time
  local tk i=0
  printf '1000\n' > "$TMP/ls-clock"
  # The clock moves a thousand seconds a second, so the call's limit runs out whenever it began.
  ( while [ "$i" -lt 60 ]; do i=$((i + 1)); sleep 1
      printf '%s\n' "$((1000 + i * 1000))" > "$TMP/ls-clock.tmp" && mv -f "$TMP/ls-clock.tmp" "$TMP/ls-clock"
    done ) &
  tk=$!
  LS_SHORT=1 LS_USED=95 LS_NOW_FILE="$TMP/ls-clock" "$@"
  kill "$tk" 2>/dev/null; wait "$tk" 2>/dev/null
}
LSI="$(lsu_tree su-b-no-place)"
lsu_run "$LSI" a 0
ls_waits lsu_run "$LSI" b 0
expect_eq "(i) a green, then b's unadmitted end stamped with its suite and 75" \
  "a.test.sh:0 b.test.sh:75" "$(lsu_stamps "$LSI")"
expect_match "(i) a green then b never admitted at one head is REFUSED, naming b" \
  "spawn-worktree: REFUSED reason=stale-proof why=red rc=75 suite=b.test.sh *" "$(worktree_land "$LSI" wave/fixture)"
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
  "bash *booked.sh --shell /bin/bash --agent at56shim-0123456789abcdef --detach --stamp-dir $LSN1 --suites npm_test -- *" "$LSU_WRAP"
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

# (n3) A runner the gate never admitted, then the same runner green.
LSN3="$(lsu_tree sn-npm-no-place)"
ls_waits lsn_run "$LSN3" npm 0
lsn_run "$LSN3" npm 0
expect_eq "(n3) npm_test never admitted (75), then npm_test green" "npm_test:75 npm_test:0" "$(lsu_stamps "$LSN3")"
expect_match "(n3) a runner the gate never admitted, then the same runner green, LANDS" \
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
  "bash *booked.sh --shell /bin/bash --agent at56shim-0123456789abcdef --detach --stamp-dir $LSN6 --suites a.test.sh -- *" "$LSU_WRAP"
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
expect_match "(n7) a || b is wrapped as ?" "bash *booked.sh --shell /bin/bash --agent at56shim-0123456789abcdef --detach --stamp-dir $LSN7 --suites '?' -- *" "$LSU_WRAP"
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

section "§LAND-RED: a row that declared its red at dispatch lands with exactly that suite red (wave-27 T31; REQ-14 AC-14.1; D23)"
#
# A brief may declare `Lands-red: <suite> until <token>` with `Red-evidence: <path>`; the dispatch
# wall records both on the launch row (`lands_red=`, `red_evidence=`). In `land`'s stale-proof rule a
# red newest run at the head is then accepted for EXACTLY that suite, when the evidence file exists
# and holds a line `head: <the tree's head>` and every other suite stamped at the head is green. The
# LANDED line carries `landed-red=<suite>` after `removed=` and before `proofs=`, and the landing
# record copies the red stamp line like any other.
#
# FIXTURE FIDELITY. Every land goes through `worktree_land_for_session`, the path both real callers
# take, on a plan bound as bind_plan binds one. The tree's owner is written by the production writer
# of the workspace record (`worktree_record_workspace`), its roster rows by the production writer of
# the row (`roster_row`, through roster_row_fixture), and its stamps in the shim's shape (lp_stamp).
LR="$(new_repo "$TMP/land-red")"
LR_SID="land-red-session-01"
LR_PLAN="$LR/.bionic/docs/plans/epic-x/wave-lr.plan.md"
LR_EV="$LR/.bionic/docs/record/wave-lr/T9-red.md"
mkdir -p "${LR_PLAN%/*}" "$LR/.bionic/tmp" "${LR_EV%/*}"
printf -- '---\nworking-branch: wave/fixture\n---\n# fixture plan\n\n## SDLC State\n\ncurrent: 4\n\n## Tasks\n\n| id | step | kind | task | worktree | status |\n|---|---|---|---|---|---|\n| T9 | 4 | build | nine | .worktrees/27-T9 | active |\n' > "$LR_PLAN"
printf 'plan=%s\nengaged_at=2026-09-23T00:00:00Z\n' "$LR_PLAN" > "$LR/.bionic/tmp/engaged-${LR_SID}.state"
LR_ROSTER="$LR/.bionic/tmp/roster-${LR_SID}.state"
lr_tree() {  # <branch> <dir> <agent name> -> a tree a commit ahead, its owner recorded, its record link
  local d="$LR/.worktrees/$2"
  git -C "$LR" worktree add --quiet -b "$1" "$d" HEAD >/dev/null 2>&1
  echo "$RANDOM$RANDOM" >> "$d/$2.txt"; git -C "$d" add -A >/dev/null 2>&1; git -C "$d" commit --quiet -m "$1 work"
  ln -s "$LR/.bionic" "$d/.bionic"
  worktree_record_workspace "$LR" "$LR_SID" "$3" "$(cd "$d" && pwd -P)" "$1" "$(git -C "$LR" rev-parse HEAD)" >/dev/null
  printf '%s' "$(cd "$d" && pwd -P)"
}
lr_launch() {  # <agent name> [<extra key=value>...] — the dispatch wall's launch row
  local n="$1"; shift
  roster_row_fixture status=intended "session=${LR_SID}" "name=$n" agent_id= subagent_type=bionic:implementor \
    "suites_allowed=widget.test.sh other.test.sh" "$@" >> "$LR_ROSTER"
}
lr_stamp() {  # <tree> <rc> <suite> — one stamp line at the tree's head, the shim's shape
  printf 'stamp/v1|head=%s|dirty=0|rc=%s|at=2026-10-05T01:02:03Z|suites=%s|cmd=bash tests/%s\n' \
    "$(git -C "$1" rev-parse HEAD)" "$2" "$3" "$3" >> "$(stamp_file "$1")"
}
LR_DECL=("lands_red=widget.test.sh until approval:release" "red_evidence=.bionic/docs/record/wave-lr/T9-red.md")

# (r1) THE WORKED ANSWER: widget red, other green, evidence naming the head -> LANDED, landed-red=.
LR1="$(lr_tree wt/27-T9 27-T9 w27-T9)"; LR1_H="$(git -C "$LR1" rev-parse HEAD)"
lr_launch w27-T9 "${LR_DECL[@]}"
lr_stamp "$LR1" 1 widget.test.sh; lr_stamp "$LR1" 0 other.test.sh
printf '# why T9 is red\nhead: %s\nthe owner step is outside the run\n' "$LR1_H" > "$LR_EV"
expect_eq "(r1) fixture: the workspace record answers the tree for its agent" "$LR1" "$(workspace_for_name "$LR" "$LR_SID" w27-T9)"
OUTLR1="$(worktree_land_for_session "$LR1" "$LR" "$LR_SID")"; RCLR1=$?
LR1_M="$(git -C "$LR" rev-parse refs/heads/wave/fixture)"
LR1_AT="$(printf '%s' "$OUTLR1" | sed -n 's/.* landed-red-at=\([^ ]*\) .*/\1/p')"
expect_match "(r1a) the LANDED line's landed-red-at= is UTC, YYYY-MM-DDTHH:MM:SSZ" "$LP_ISO" "$LR1_AT"
expect_eq "(r1b) AC-14.1 the declared red lands: the LANDED line carries landed-red= and landed-red-at= after removed= and before proofs=" \
  "spawn-worktree: LANDED branch=wt/27-T9 onto=wave/fixture checkout=${LR} merge=${LR1_M} removed=${LR1} landed-red=widget.test.sh landed-red-at=${LR1_AT} proofs=${LR}/.bionic/docs/record/wave-lr/landing-proofs.log" "$OUTLR1"
expect_contains "(r1b2) …the same instant the landing record's header carries in at=" \
  "landed: row=T9 branch=wt/27-T9 head=${LR1_H} merge=${LR1_M} at=${LR1_AT}" "$(cat "$LR/.bionic/docs/record/wave-lr/landing-proofs.log" 2>/dev/null)"
expect_eq "(r1c) …exit 0" "0" "$RCLR1"
expect_contains "(r1d) …and the landing record copies the red stamp line like any other" \
  "|rc=1|at=2026-10-05T01:02:03Z|suites=widget.test.sh|" "$(cat "$LR/.bionic/docs/record/wave-lr/landing-proofs.log" 2>/dev/null)"

section "§LAND-RED-NO: an undeclared red, a second red, or a declaration not carried from dispatch is refused (wave-27 T31; REQ-14 AC-14.2; D23)"
#
# The same fixture. A second suite red at the head is refused as an undeclared red is today
# (`stale-proof why=red`); evidence that is missing or names another head is refused, naming the file
# and the head it wanted; a row whose launch line carries no declaration is refused as today, and so
# is one whose keys reached the roster on a later row (by amend, which cannot write them, or by hand):
# the dispatch wall is the keys' one writer, and land reads the launch line alone.
lr_refused() {  # <label> <tree> <want, a glob> — the land refuses, the target does not move, the tree stays
  local before out rc; before="$(refs_of "$LR")"
  out="$(worktree_land_for_session "$2" "$LR" "$LR_SID")"; rc=$?
  expect_match "$1" "$3" "$out"
  expect_eq "$1 — …exit 2, no ref moved, the tree stands" "2 yes yes" \
    "$rc $([ "$(refs_of "$LR")" = "$before" ] && echo yes || echo no) $([ -d "$2" ] && echo yes || echo no)"
}
# (n1) a SECOND suite red at the head.
LN1="$(lr_tree wt/27-N1 27-N1 w27-N1)"; LN1_H="$(git -C "$LN1" rev-parse HEAD)"
lr_launch w27-N1 "${LR_DECL[@]}"
lr_stamp "$LN1" 1 widget.test.sh; lr_stamp "$LN1" 1 other.test.sh
printf 'head: %s\n' "$LN1_H" > "$LR_EV"
lr_refused "(n1) AC-14.2 a second suite also red is refused as an undeclared red, naming it" "$LN1" \
  "spawn-worktree: REFUSED reason=stale-proof why=red rc=1 suite=other.test.sh head=${LN1_H} — *"
# (n2) the evidence file missing.
LN2="$(lr_tree wt/27-N2 27-N2 w27-N2)"; LN2_H="$(git -C "$LN2" rev-parse HEAD)"
lr_launch w27-N2 "${LR_DECL[@]}"
lr_stamp "$LN2" 1 widget.test.sh; lr_stamp "$LN2" 0 other.test.sh
rm -f "$LR_EV"
lr_refused "(n2) the evidence file missing is refused, naming the file and the head it wanted" "$LN2" \
  "spawn-worktree: REFUSED reason=stale-proof why=red-evidence suite=widget.test.sh head=${LN2_H} evidence=${LR_EV} — *missing*"
# (n3) the evidence naming another commit.
printf 'head: %s\n' "$LR1_H" > "$LR_EV"
lr_refused "(n3) evidence whose head: names another commit is refused, naming the file, the head it wanted and the one it found" "$LN2" \
  "spawn-worktree: REFUSED reason=stale-proof why=red-evidence suite=widget.test.sh head=${LN2_H} evidence=${LR_EV} found=${LR1_H} — *"
printf 'head: %s\n' "$LN2_H" > "$LR_EV"
expect_match "(n3b) control: the same tree with the evidence naming its head lands" \
  "spawn-worktree: LANDED branch=wt/27-N2 * landed-red=widget.test.sh landed-red-at=* proofs=*" "$(worktree_land_for_session "$LN2" "$LR" "$LR_SID")"
# (n4) the same tree shape with NO declaration on its launch row.
LN4="$(lr_tree wt/27-N4 27-N4 w27-N4)"; LN4_H="$(git -C "$LN4" rev-parse HEAD)"
lr_launch w27-N4
lr_stamp "$LN4" 1 widget.test.sh; lr_stamp "$LN4" 0 other.test.sh
printf 'head: %s\n' "$LN4_H" > "$LR_EV"
lr_refused "(n4) AC-14.2 no declaration on the launch row: refused as today" "$LN4" \
  "spawn-worktree: REFUSED reason=stale-proof why=red rc=1 suite=widget.test.sh head=${LN4_H} — *"
# (n5) the keys on a row written after the launch: an amended copy, then a later started row.
lr_launch w27-N4 "amended=2026-10-05T00:00:00Z widen" "${LR_DECL[@]}"
roster_row_fixture status=identified "session=${LR_SID}" name=w27-N4 agent_id=a-n4 "${LR_DECL[@]}" >> "$LR_ROSTER"
lr_refused "(n5) AC-14.2 a declaration that reached the roster after the launch line is not honoured" "$LN4" \
  "spawn-worktree: REFUSED reason=stale-proof why=red rc=1 suite=widget.test.sh head=${LN4_H} — *"
expect_contains "(n5b) fixture: the roster does carry the keys, on the later rows" \
  "|name=w27-N4|" "$(grep -F 'lands_red=widget.test.sh' "$LR_ROSTER")"

section "§LAND-JUDGED: no landing after the run was judged for integration (wave-27 T31; review pass 25 F3)"
#
# `current 8` judges the working head; a landing after it would move the working branch past the
# head that was judged, with nothing judging it again. So `land` refuses while the bound plan's
# `current:` is 8 or later, its letter dropped: `reason=past-judgment why=current-<value>`, nothing
# merged, nothing removed. At `current: 7` it lands; with no bound plan it lands as today.
# FIXTURE FIDELITY: §LAND-RED's repository and bound plan, its `current:` line rewritten in place.
lj_current() { sed "s/^current: .*/current: $1/" "$LR_PLAN" > "$LR_PLAN.tmp" && mv "$LR_PLAN.tmp" "$LR_PLAN"; }
LJ1="$(lr_tree wt/27-J1 27-J1 w27-J1)"; lr_launch w27-J1; lr_stamp "$LJ1" 0 widget.test.sh
for lj in 8 8a 8b; do
  lj_current "$lj"
  lr_refused "(j-$lj) F3 at current: $lj a ready tree is refused past-judgment" "$LJ1" \
    "spawn-worktree: REFUSED reason=past-judgment why=current-${lj} * — *judged for integration*"
done
lj_current 7
expect_match "(j-7) …at current: 7 the same tree lands" \
  "spawn-worktree: LANDED branch=wt/27-J1 onto=wave/fixture *" "$(worktree_land_for_session "$LJ1" "$LR" "$LR_SID")"
lj_current 8
LJ2="$(lr_tree wt/27-J2 27-J2 w27-J2)"; lr_stamp "$LJ2" 0 widget.test.sh
expect_match "(j-none) …and a land with no bound plan lands as today, whatever a plan on disk says" \
  "spawn-worktree: LANDED branch=wt/27-J2 onto=wave/fixture * proofs=none" "$(worktree_land "$LJ2" wave/fixture)"
lj_current 4
section "§LAND-DEBT: ready writes the declared debt to the landing record before the fast-forward (wave-27 T67, re-pointed at ready by wave-28 T5; REQ-9 AC-9.4; D8; A-orch-120)"
#
# A debt is owed because the landing WROTE it: for a row whose launch line declares `lands_red=<suite>
# until <token>`, a red on exactly that suite publishes, and `line_publish` appends one line
# `debt: id=<id> row=<row> branch=<b> head=<the row's 40-hex> suite=<s> token=<t> at=<the publish's time>`
# to the landing record, by the one write a block is, inside the publish lock and BEFORE the
# fast-forward. The red is the tool's own run on the candidate (no stamp, no evidence file). A line that
# cannot be written refuses the publish with nothing published; a fast-forward that then fails is
# followed by `void: id=<id> … why=publish-failed`; a void that cannot be written leaves the debt
# standing, and the refusal says so. A red on the debt suite and on another suite returns the row; the
# full-suite runner is never a declared debt.
# Re-pointed from `land` (wave-27's §LAND-DEBT: 21 rows) at `ready` (wave-28 T5), keeping every check.
# FIXTURE FIDELITY: the model world (tests/lib/world.sh): a real repository whose root checkout holds
# the working branch `wave/x`, a bound plan, the row tree T1, its launch line on the session's roster as
# the dispatch wall writes one (`roster_row_fixture` plus `row=`/`lands_on=`, the keys T7 lifts from
# the brief), suites run through the real gate on a planted machine. `ready` runs in a driver process
# of its own (`ld_ready`), the verb's own call; a failing writer is a stand-in defined in that process
# only, and the fast-forward is made to fail by git's own index lock, planted at the publish's pause
# seam, after the debt was written.
LD_GATE_WAS="${BIONIC_GATE_DIR:-}"
. "$(dirname "$0")/lib/world.sh"
LD_HOME="$WORLD_ROOT/home"; mkdir -p "$LD_HOME/bionic"; printf '80\n' > "$LD_HOME/bionic/share"
world_machine 8 8192 40 0.5
world_clock 1000
world_cost a.test.sh 5 0.5 5; world_cost b.test.sh 5 0.5 5
LD_RD="$WORLD_ROOT/ld-driver.sh"
cat > "$LD_RD" <<'RD'
#!/bin/bash
# <lib dir>: `ready` as spawn-worktree.sh calls it, in a process of its own. LD_STANDIN=debt-write
# stands a failing writer in for the debt's one writer; LL_MUTANT is a sed over LL_MUTANT_FN.
. "$1/worktree.sh" && . "$1/session.sh" && . "$1/line.sh" || exit 99
if [ "${LD_STANDIN:-}" = debt-write ]; then _wt_debt_write() { return 1; }; fi
if [ -n "${LL_MUTANT:-}" ]; then eval "$(declare -f "$LL_MUTANT_FN" | sed "$LL_MUTANT")"; fi
tree="$(git rev-parse --show-toplevel)"
line_ready "$tree" "$(worktree_root "$tree")" "$(session_id)" "" "again"
RD
ld_world() {  # <lands_on> <lands_red> [<suite> red]... -> a world root; T1's launch line declares the red
  local r l="$1" d="$2"
  shift 2
  # The world binds its plan through the production `bind_plan` (lib/binding.sh), which this suite
  # shadows with a fixture of its own (above): the world is made where the production one is back.
  r="$( . "${REPO}/payload/scripts/lib/run.sh" && . "${REPO}/payload/scripts/lib/binding.sh" && world_repo )" || return 1
  [ -n "$r" ] && [ "$(git -C "$r" rev-parse --show-toplevel 2>/dev/null)" = "$r" ] || return 1
  printf '%s|row=T1|lands_on=%s\n' "$(roster_row_fixture status=intended session="$WORLD_SID" name=wx-T1 agent_id=b00T1 \
    plan="$r/.bionic/docs/plans/epic-x/wave-x.plan.md" "lands_red=$d" "red_evidence=record/wave-x/T1-red.md")" "$l" \
    >> "$r/.bionic/tmp/roster-$WORLD_SID.state"
  while [ "$#" -ge 2 ]; do
    ( cd "$r/.worktrees/T1" && world_suite "$1" "$2" >/dev/null ) || return 1
    shift 2
  done
  git -C "$r/.worktrees/T1" commit -qam "T1: its suites as planted" || return 1
  printf '%s' "$r"
}
ld_ready() {  # <root> [VAR=value]... -> LD_OUT, LD_RC: ready from T1's tree
  local r="$1"
  shift
  LD_OUT="$( cd "$r/.worktrees/T1" && env CLAUDE_CONFIG_DIR="$LD_HOME" CLAUDE_CODE_SESSION_ID="$WORLD_SID" \
    BIONIC_GATE_POLL=0.1 BIONIC_LINE_POLL=0.2 "$@" bash "$LD_RD" "${LIB%/*}" 2>&1 )"; LD_RC=$?
}
ld_ready_bg() {  # <root> <out file> [VAR=value]... — the same, in the background; rc in <out>.rc
  local r="$1" o="$2"
  shift 2
  ( cd "$r/.worktrees/T1" && env CLAUDE_CONFIG_DIR="$LD_HOME" CLAUDE_CODE_SESSION_ID="$WORLD_SID" \
    BIONIC_GATE_POLL=0.1 BIONIC_LINE_POLL=0.2 "$@" bash "$LD_RD" "${LIB%/*}" > "$o" 2>&1; echo $? > "$o.rc" ) &
}
ld_rec() { printf '%s/.bionic/docs/record/wave-x/landing-proofs.log' "$1"; }
ld_head() { git -C "$1" rev-parse --verify -q refs/heads/wave/x; }
ld_wait() {  # <file> -> 0 once it exists (30 s at most)
  local i=0
  while [ "$i" -lt 300 ]; do [ -e "$1" ] && return 0; i=$((i + 1)); sleep 0.1; done
  return 1
}
ld_refused() {  # <label> <root> <want, a glob> — exit 2, nothing published, the tree stands
  local before; before="$(ld_head "$2")"
  expect_match "$1" "$3" "$LD_OUT"
  expect_eq "$1 — …exit 2, nothing published, the tree stands" "2 yes yes" \
    "$LD_RC $([ "$(ld_head "$2")" = "$before" ] && [ -z "$(grep '^line/v1|ev=published|' "$(ld_rec "$2")" 2>/dev/null)" ] && echo yes || echo no) $([ -d "$2/.worktrees/T1" ] && echo yes || echo no)"
}
LD_DECL="a.test.sh until ext:vendor-key"

# (d1) THE WORKED ANSWER: a red on the declared suite alone publishes, the debt line written before the
# `published` event, at the publish's own instant.
LD1="$(ld_world a,b "$LD_DECL" a red)"; LD1_H="$(git -C "$LD1/.worktrees/T1" rev-parse HEAD)"
ld_ready "$LD1"
LD1_PUB="$(grep '^line/v1|ev=published|row=T1|' "$(ld_rec "$LD1")" 2>/dev/null)"
LD1_AT="$(printf '%s' "$LD1_PUB" | sed -n 's/.*|at=\([^|]*\)$/\1/p')"
expect_match "(d1) precondition: the declared red publishes (exit 0), saying it lands red and owes the debt" \
  "0|DEBT T1 a.test.sh — published red*LANDED T1 $(ld_head "$LD1")*" "$LD_RC|$LD_OUT"
expect_match "(d1a) B3 the publish wrote the debt: the row, its branch and head, the suite, the token, the publish's time" \
  "debt: id=?* row=T1 branch=wt/T1 head=${LD1_H} suite=a.test.sh token=ext:vendor-key at=${LD1_AT}" \
  "$(grep '^debt: ' "$(ld_rec "$LD1")" 2>/dev/null)"
expect_eq "(d1b) …one line, written before the published event" "1 before" \
  "$(awk '/^debt: / { n++; d = NR } /^line\/v1\|ev=published\|/ { h = NR } END { print n + 0, (d && h && d < h ? "before" : "after") }' "$(ld_rec "$LD1")" 2>/dev/null)"
expect_eq "(d1c) …and no void line names it" "" "$(grep '^void: ' "$(ld_rec "$LD1")" 2>/dev/null)"
# (d2r) THE RECORD CANNOT BE WRITTEN: its directory read-only is refused before anything is appended.
LD2="$(ld_world a,b "$LD_DECL" a red)"
mkdir -p "$(dirname "$(ld_rec "$LD2")")"; chmod 555 "$(dirname "$(ld_rec "$LD2")")"
ld_ready "$LD2"
ld_refused "(d2r) the record's directory read-only: refused, nothing published" "$LD2" \
  "spawn-worktree: REFUSED reason=record-unwritable why=proofs-unwritable * — *nothing is published*"
chmod 755 "$(dirname "$(ld_rec "$LD2")")"
# (d2) THE DEBT CANNOT BE WRITTEN: the writer itself failing, after the record proved writable, is
# driven through a stand-in for the one writer, in the driver's process only.
ld_ready "$LD2" LD_STANDIN=debt-write
ld_refused "(d2) B3 a debt the writer cannot write refuses the publish, before the fast-forward" "$LD2" \
  "spawn-worktree: REFUSED reason=debt-unwritten why=proofs-unwritable suite=a.test.sh * — *nothing is published*"
expect_eq "(d2b) …the record holds the row's red verdict and no debt line" "1 0" \
  "$(grep -c '^line/v1|ev=verdict|row=T1|.*|suite=a.test.sh|result=red|' "$(ld_rec "$LD2")") $(grep -c '^debt: ' "$(ld_rec "$LD2")")"
ld_ready "$LD2"
expect_match "(d2c) control: the same tree, the real writer back, publishes red" "0|*DEBT T1 a.test.sh *LANDED T1 *" "$LD_RC|$LD_OUT"
# (d3) THE FAST-FORWARD FAILS AFTER THE DEBT WAS WRITTEN: a void line naming its id follows it.
LD_PAUSE="$WORLD_ROOT/ld-pause"; mkdir -p "$LD_PAUSE"
LD3="$(ld_world a,b "$LD_DECL" a red)"; LD3_HB="$(ld_head "$LD3")"
ld_ready_bg "$LD3" "$WORLD_ROOT/ld3.out" BIONIC_LINE_PAUSE_BEFORE_PUBLISH="$LD_PAUSE"
ld_wait "$LD_PAUSE/T1.at-publish"
expect_eq "(d3-pre) at the fast-forward the debt is written and the branch has not moved" "1 $LD3_HB" \
  "$(grep -c '^debt: ' "$(ld_rec "$LD3")" 2>/dev/null) $(ld_head "$LD3")"
: > "$LD3/.git/index.lock"; touch "$LD_PAUSE/T1.go"
ld_wait "$WORLD_ROOT/ld3.out.rc"; rm -f "$LD3/.git/index.lock" "$LD_PAUSE/T1.go" "$LD_PAUSE/T1.at-publish"
LD_OUT="$(cat "$WORLD_ROOT/ld3.out" 2>/dev/null)"; LD_RC="$(cat "$WORLD_ROOT/ld3.out.rc" 2>/dev/null)"
ld_refused "(d3) a fast-forward that fails after the debt was written is refused publish-failed" "$LD3" \
  "spawn-worktree: REFUSED reason=publish-failed row=T1 branch=wave/x *"
LD3_ID="$(sed -n 's/^debt: id=\([^ ]*\) .*/\1/p' "$(ld_rec "$LD3")")"
expect_regex "(d3a) …the debt line was written first" '^[^ ]+$' "$LD3_ID"
expect_match "(d3b) …and a void line names its id" "void: id=${LD3_ID} branch=wt/T1 at=* why=publish-failed" \
  "$(grep "^void: id=${LD3_ID} " "$(ld_rec "$LD3")" 2>/dev/null)"
# (d4) THE VOID CANNOT BE WRITTEN: at the pause a directory takes the record's path and the index is
# locked, so the fast-forward fails and the void's append answers unwritten. The debt stands, and the
# refusal says it was written and not voided, and what clears it. The record is put back after.
LD4="$(ld_world a,b "$LD_DECL" a red)"; LD4_REC="$(ld_rec "$LD4")"
ld_ready_bg "$LD4" "$WORLD_ROOT/ld4.out" BIONIC_LINE_PAUSE_BEFORE_PUBLISH="$LD_PAUSE"
ld_wait "$LD_PAUSE/T1.at-publish"
mv "$LD4_REC" "$LD4_REC.aside" && mkdir "$LD4_REC"; : > "$LD4/.git/index.lock"; touch "$LD_PAUSE/T1.go"
ld_wait "$WORLD_ROOT/ld4.out.rc"; rm -f "$LD4/.git/index.lock" "$LD_PAUSE/T1.go" "$LD_PAUSE/T1.at-publish"
rmdir "$LD4_REC" 2>/dev/null; mv "$LD4_REC.aside" "$LD4_REC" 2>/dev/null
LD_OUT="$(cat "$WORLD_ROOT/ld4.out" 2>/dev/null)"; LD_RC="$(cat "$WORLD_ROOT/ld4.out.rc" 2>/dev/null)"
ld_refused "(d4) a void that cannot be written: the debt stands, and the refusal says so and how to clear it" "$LD4" \
  "spawn-worktree: REFUSED reason=publish-failed row=T1 * debt=unvoided * — *was written and not voided*green run of a.test.sh*"
LD4_ID="$(sed -n 's/^debt: id=\([^ ]*\) .*/\1/p' "$LD4_REC")"
expect_eq "(d4b) …the debt line is there and no void names it" "1|0" \
  "$([ -n "$LD4_ID" ] && echo 1 || echo 0)|$(grep -c "^void: id=${LD4_ID:-none} " "$LD4_REC")"
# (d5) B4 THE RUNNER IS NEVER A DECLARED RED: a launch line naming run.sh carries no debt, and a red is
# the row's.
LD5="$(ld_world a "run.sh until ext:x" a red)"
ld_ready "$LD5"
expect_eq "(d5) B4 the full-suite runner handed to ready as the declared red: no debt on the entry, the red returns the row (exit 1)" \
  "1|-|RED T1 a.test.sh" \
  "$LD_RC|$(grep '^line/v1|ev=ready|' "$(ld_rec "$LD5")" | sed -n 's/.*|debt=\([^|]*\)|.*/\1/p')|$(printf '%s\n' "$LD_OUT" | cut -d' ' -f1-3)"
expect_eq "(d5b) …and no debt line is written" "0" "$(grep -c '^debt: ' "$(ld_rec "$LD5")")"
# (d6) NO BOUND PLAN, NO RECORD: a declared red with nowhere to write its debt is refused.
LD6="$(ld_world a "$LD_DECL" a red)"
ld_ready "$LD6" CLAUDE_CODE_SESSION_ID=no-such-session
ld_refused "(d6) a declared red with no bound plan is refused: its debt has no record to go in" "$LD6" \
  "spawn-worktree: REFUSED reason=no-bound-plan *"
# (d7) A RED ON THE DEBT SUITE AND ON ANOTHER returns the row: nothing published, no debt written.
LD7="$(ld_world a,b "$LD_DECL" a red b red)"; LD7_HB="$(ld_head "$LD7")"
ld_ready "$LD7"
expect_match "(d7) AC-9.4 the declared suite red and a second suite red: the row returns on the second (exit 1)" \
  "1|RED T1 b.test.sh *" "$LD_RC|$LD_OUT"
expect_eq "(d7b) …returned why=red, nothing published, no debt line" "1|$LD7_HB|0" \
  "$(grep -c '^line/v1|ev=returned|row=T1|why=red|' "$(ld_rec "$LD7")")|$(ld_head "$LD7")|$(grep -c '^debt: ' "$(ld_rec "$LD7")")"
# (d8m) MUTANT: the debt write skipped. The declared red publishes with no debt line.
LD8="$(ld_world a,b "$LD_DECL" a red)"
ld_ready "$LD8" LL_MUTANT='s/_line_debt_write "\$rec"/true "$rec"/' LL_MUTANT_FN=line_publish
expect_eq "(d8m-pre) the mutant ran: the row is published" "0" "$LD_RC"
expect_eq "(d8m) MUTANT debt write skipped: published with no debt line (the rows can fail)" "0" "$(grep -c '^debt: ' "$(ld_rec "$LD8")")"
# The world's machine and clock pins end with the section; the suite's own gate store comes back.
unset BIONIC_PROBE_CORES BIONIC_PROBE_TOTAL_MB BIONIC_PROBE_USED_PCT BIONIC_PROBE_BUSY_CORES BIONIC_PROBE_FREE_PCT \
  BIONIC_PROBE_FREE_MB BIONIC_PROBE_LOAD_1M BIONIC_PROBE_SWAP_PCT BIONIC_NOW_FILE
[ -z "$LD_GATE_WAS" ] || export BIONIC_GATE_DIR="$LD_GATE_WAS"

section "§LAND-RECORD-HARDENING: the record is appended by one write and read as a regular file (wave-27 T50, T69; review pass 27 S1, N1, N2, N4; review pass 48)"
#
# S1, as T69 rebuilt it. A landing's block is written whole to a private file beside the record and
# appended by ONE write on a descriptor the shell opened for append (`dd bs=1048576 >> <record>`).
# A local filesystem puts each such write at the end of the file whole, so two appends never
# interleave and neither is lost, with no lock. A block over one mebibyte is not appended, and a
# short write is seen by comparing dd's count with the block's size: either is `proofs=unwritten`.
# A `<record>.lock` left by an older version is ignored. N1, N2. The record path is a regular file
# or absent: a symlink, a FIFO, a device or a directory there refuses the landing before the merge
# and is never opened; the proof creates nothing at the record's path, so a refused landing leaves
# none. N4. A `worktree` cell is read after a leading `./` and trailing slashes are dropped; a row
# id holding a blank is written `—`.
#
# FIXTURE FIDELITY. The concurrency rows run the real `_wt_proofs_append` in child shells, under
# /bin/bash and under the PATH's bash, and two real landings through `worktree_land_for_session`.
# They are OUTCOMES, asserted on every run: the kernel orders the writes, so no row is a trial
# that usually passes. The kill rows force each act of the append by a stub of the one external
# command at that act (`mktemp`, `wc`, `dd`, `rm`); the stub sends the signal to the appending shell
# itself, so no row depends on timing.
lk_verdict() {  # <record> <lines per block> -> "OK headers=<n> lines=<n>" or the first block that is not contiguous
  awk -v per="$2" '
    /^landed: / { if (want) { bad = "short block before line " NR; exit } tag = $2; sub(/^row=R/, "", tag); want = per; n = 0; hdr++; next }
    /^stamp\/v1/ {
      if (!want) { bad = "stamp line outside a block at line " NR; exit }
      split($0, f, "|"); t = f[2]; sub(/^tag=/, "", t); k = f[3]; sub(/^n=/, "", k)
      if (t != tag || k + 0 != n + 1) { bad = "line " NR " is " t "/" k " under " tag "/" n + 1; exit }
      n++; want--; lines++; next }
    /^$/ { if (want) { bad = "a blank line inside a block at line " NR; exit } next }
    { bad = "a line that is neither at line " NR; exit }
    END { if (bad) print "BAD " bad; else if (want) print "BAD last block short"; else print "OK headers=" hdr " lines=" lines }' "$1"
}

# (c8) EIGHT PROCESSES AT ONCE, each 150 appends of a block of twenty kilobytes (a header and twenty
# stamp lines of a thousand bytes each): 1,200 blocks, every header followed by exactly its own
# twenty lines, none lost, no append failed, nothing left beside the record. Under each bash.
cat > "$TMP/c8-child.sh" <<'C8_EOF'
. "$1" || exit 9
f="$2"; tag="$3"; pad="$(printf '%01000d' 0)"; lines=""
for i in $(seq 1 20); do
  lines="${lines}${lines:+
}stamp/v1|tag=${tag}|n=${i}|pad=${pad}"
done
for r in $(seq 1 150); do
  _wt_proofs_append "$f" "R${tag}" "br-${tag}" "$(printf '%040d' "$r")" "$(printf '%040d' "$r")" "$lines" || echo "FAILED ${tag} ${r}"
done
C8_EOF
c8_run() {  # <bash> <record> -> verdict|failures|what is beside the record
  local sh="$1" rec="$2" t pids=""
  mkdir -p "${rec%/*}"; rm -f "$rec"
  for t in A B C D E F G H; do "$sh" "$TMP/c8-child.sh" "$LIB" "$rec" "$t" > "$TMP/c8-out-$t" 2>&1 & pids="$pids $!"; done
  # shellcheck disable=SC2086
  wait $pids
  printf '%s|%s|%s' "$(lk_verdict "$rec" 20)" "$(cat "$TMP"/c8-out-? | head -n 3)" "$(ls -A "${rec%/*}")"
}
C8_SYS="$(/bin/bash -c 'printf %s "$BASH_VERSION"')"; C8_PATH="$(bash -c 'printf %s "$BASH_VERSION"')"
expect_eq "(T69-c8) /bin/bash ${C8_SYS}: eight writers, 1,200 blocks of 20 KB, each whole, none lost, none failed, nothing left" \
  "OK headers=1200 lines=24000||landing-proofs.log" "$(c8_run /bin/bash "$TMP/c8-sys/landing-proofs.log")"
expect_eq "(T69-c8b) the PATH's bash ${C8_PATH}: the same" \
  "OK headers=1200 lines=24000||landing-proofs.log" "$(c8_run bash "$TMP/c8-path/landing-proofs.log")"
expect_true "(T69-c8-pre) fixture: each block is over twenty thousand bytes (blank lines between blocks, from the cut-line look: $(cat "$TMP"/c8-*/landing-proofs.log | grep -c '^$'))" \
  test "$(awk 'NR <= 21' "$TMP/c8-sys/landing-proofs.log" | wc -c)" -gt 20000
printf 'landed: row=RX\nstamp/v1|tag=Y|n=1\n' > "$TMP/lk-bad.log"
expect_match "(T50-s1d) the verdict can fail: a block with a line under the wrong header is reported" "BAD *" "$(lk_verdict "$TMP/lk-bad.log" 1)"

# (s1l) A RECORD THAT CANNOT BE WRITTEN fails the append; nothing is left beside it. The arm: writable, it appends.
LK_F="$TMP/lk-held/landing-proofs.log"; mkdir -p "${LK_F%/*}"; echo "earlier" > "$LK_F"
chmod 444 "$LK_F"
_wt_proofs_append "$LK_F" R9 br 1111111111111111111111111111111111111111 2222222222222222222222222222222222222222 "stamp/v1|x"; LK_RC=$?
chmod 644 "$LK_F"
expect_true "(T50-s1l) a record that cannot be written fails the append" test "$LK_RC" -ne 0
expect_eq "(T50-s1m) …the record untouched, and nothing left beside it" "earlier|landing-proofs.log" "$(cat "$LK_F")|$(ls -A "${LK_F%/*}")"
_wt_proofs_append "$LK_F" R9 br 1111111111111111111111111111111111111111 2222222222222222222222222222222222222222 "stamp/v1|x"; LK_RC=$?
expect_eq "(T50-s1m-arm) the arm: writable, the same append is made" "0|3" "$LK_RC|$(awk 'END { print NR }' "$LK_F")"

# (old-lock) A LOCK AN OLDER VERSION LEFT is ignored: a `<record>.lock` holding a LIVE holder's line,
# and its `.taking`, beside the record. The append is made at once, never waited on, and neither is
# removed or changed.
OL="$TMP/old-lock/landing-proofs.log"; mkdir -p "${OL%/*}"; echo "earlier" > "$OL"
sleep 120 & OL_LIVE=$!
mkdir "$OL.lock" "$OL.lock.taking"; echo "$OL_LIVE $OL_LIVE" > "$OL.lock/pid"; : > "$OL.lock.taking/h.$OL_LIVE"
OL_T0=$SECONDS
_wt_proofs_append "$OL" T1 wt/o 1111111111111111111111111111111111111111 2222222222222222222222222222222222222222 "stamp/v1|o"; OL_RC=$?
OL_DT=$((SECONDS - OL_T0))
expect_eq "(T69-old-lock) a live holder's lock from an older version: the append is made" "0|3" "$OL_RC|$(awk 'END { print NR }' "$OL")"
expect_true "(T69-old-lock-b) …at once, never waited on (took ${OL_DT}s)" test "$OL_DT" -le 1
expect_eq "(T69-old-lock-c) …and the lock, its line and its .taking are as they were" "$OL_LIVE $OL_LIVE|yes" \
  "$(cat "$OL.lock/pid" 2>/dev/null)|$([ -e "$OL.lock.taking/h.$OL_LIVE" ] && echo yes)"
kill "$OL_LIVE" 2>/dev/null; wait "$OL_LIVE" 2>/dev/null

# (prove) THE PROOF CREATES NOTHING AT THE RECORD'S PATH. An absent record in an absent directory: the
# proof passes, the directory is made, and nothing is in it (the file it made to prove the directory
# is gone). A record that is there is proved without being changed.
PV="$TMP/prove/sub/landing-proofs.log"
_wt_proofs_prove "$PV"; PV_RC=$?
expect_eq "(T69-prove) an absent record: proved, the directory made, nothing created in it" "0|dir|absent|" \
  "$PV_RC|$([ -d "${PV%/*}" ] && echo dir)|$([ -e "$PV" ] && echo present || echo absent)|$(ls -A "${PV%/*}")"
printf 'one\n' > "$PV"; touch -t 202001010000 "$PV"; PV_LS="$(ls -l "$PV")"
_wt_proofs_prove "$PV"; PV_RC=$?
expect_eq "(T69-prove-b) a record that is there: proved, its bytes and its time unchanged, nothing beside it" \
  "0|one|${PV_LS}|landing-proofs.log" "$PV_RC|$(cat "$PV")|$(ls -l "$PV")|$(ls -A "${PV%/*}")"

# (big) A BLOCK OVER ONE MEBIBYTE is not appended: the append fails, the record untouched, nothing
# left. The arm: a block of a million bytes is appended whole.
BG="$TMP/big/landing-proofs.log"; mkdir -p "${BG%/*}"; echo "earlier" > "$BG"
BG_LINES="$(head -c 1100000 /dev/zero | tr '\0' x)"
_wt_proofs_append "$BG" T1 wt/b bbbb mmmm "$BG_LINES"; BG_RC=$?
expect_eq "(T69-big) a block of 1,100,000 bytes: not appended, the record untouched, nothing beside it" "1|earlier|landing-proofs.log" \
  "$BG_RC|$(cat "$BG")|$(ls -A "${BG%/*}")"
expect_match "(T69-big-saw) …and what it saw is said, for the proofs=unwritten line" "the block is * bytes, over the one write of 1048576" "${_WT_PROOFS_SAW:-}"
BG_LINES="$(head -c 1000000 /dev/zero | tr '\0' x)"
_wt_proofs_append "$BG" T1 wt/b bbbb mmmm "$BG_LINES" 2026-01-01T00:00:00Z; BG_RC=$?
expect_eq "(T69-big-b) the arm: a block of a million bytes is appended whole" "0|$(printf 'earlier\nlanded: row=T1 branch=wt/b head=bbbb merge=mmmm at=2026-01-01T00:00:00Z\n%s\n' "$BG_LINES" | cksum)" \
  "$BG_RC|$(cksum < "$BG")"

# (short) A SHORT WRITE (a full disk) is seen: a dd that writes ten bytes of the block and reports
# nothing fails the append (`proofs=unwritten` through `land`), the private file removed. The ten
# bytes stay: the record is never truncated. The arm: the real dd, the same block, appended.
SW="$TMP/short/landing-proofs.log"; mkdir -p "${SW%/*}"; echo "earlier" > "$SW"
SW_RC="$( dd() { head -c 10 "${1#if=}"; }; _wt_proofs_append "$SW" T1 wt/s ssss mmmm "stamp/v1|s" 2026-01-01T00:00:00Z; echo "$?|${_WT_PROOFS_SAW:-}")"
expect_eq "(T69-short) a short write fails the append, the ten bytes kept, nothing beside the record" \
  "1|dd: |$(printf 'earlier\nlanded: ro')|landing-proofs.log" "$SW_RC|$(cat "$SW")|$(ls -A "${SW%/*}")"
SW_RC="$( dd() { command dd "$@" 2>/dev/null; printf '0+2 records in\n0+2 records out\n%s bytes transferred\n' "$(( $(wc -c < "${1#if=}") ))" >&2; }
  _wt_proofs_append "$SW" T1 wt/s ssss mmmm "stamp/v1|s"; echo "$?|${_WT_PROOFS_SAW:-}")"
expect_match "(T69-short-c) a dd that reports two records out (two writes) fails, saying what dd printed" \
  "1|dd: 0+2 records in; 0+2 records out; * bytes transferred" "$SW_RC"
SW_RC="$( dd() { command dd "$@"; return 1; }; _wt_proofs_append "$SW" T1 wt/s ssss mmmm "stamp/v1|s"; echo "$?|${_WT_PROOFS_SAW:-}")"
expect_match "(T69-short-e) a dd that reports the whole block but exits 1 fails, saying so" "1|dd exit 1: *records out*" "$SW_RC"
SW_B="$(cat "$SW")"
SW_RC="$( dd() { printf '0+1 records in\n0+1 records out\n%s bytes transferred\n' "$(( $(wc -c < "${1#if=}") ))" >&2; }
  _wt_proofs_append "$SW" T1 wt/s ssss mmmm "stamp/v1|s"; echo "$?|${_WT_PROOFS_SAW:-}")"
expect_match "(T69-short-d) a dd that reports the whole block but left the record no longer fails: the record must grow by it" \
  "1|the record is * bytes after the append, short of * plus the block's * bytes|${SW_B}" "$SW_RC|$(cat "$SW")"

# (fragment) THE NEXT BLOCK IS READ WHOLE after a fragment. The record ends in half a block, its stamp
# line cut with no line break (as a write a full disk cut short leaves it); a landing's append then
# puts its header on a line of its own, and the reader the judge uses (`units_landings`) reads its row
# and merge. The arm: the same header written straight after the fragment, on its line, is not read.
FR="$TMP/fragment/landing-proofs.log"; mkdir -p "${FR%/*}"
FR_CUT="landed: row=T8 branch=wt/x head=$(printf '%040d' 2) merge=$(printf '%040d' 8) at=2026-01-01T00:00:00Z
stamp/v1|head=00000"
printf '%s' "$FR_CUT" > "$FR"
FR_M="$(printf '%040d' 7)"; FR_HDR="landed: row=T7 branch=wt/27-T7 head=$(printf '%040d' 1) merge=${FR_M} at=2026-01-01T00:00:00Z"
_wt_proofs_append "$FR" T7 wt/27-T7 "$(printf '%040d' 1)" "$FR_M" "stamp/v1|a" 2026-01-01T00:00:00Z; FR_RC=$?
. "${LIB%/*}/units.sh"
expect_eq "(T69-fragment) after half a block with no line break, the landing's block is read whole by units_landings" \
  "0|T7	${FR_M}	-" "$FR_RC|$(units_landings "$LP_PLAN" "$FR" | grep '^T7	')"
expect_eq "(T69-fragment-b) …the fragment, kept, then the block on lines of its own" \
  "${FR_CUT}
${FR_HDR}
stamp/v1|a" "$(cat "$FR")"
printf '%s%s\nstamp/v1|a\n' "$FR_CUT" "$FR_HDR" > "$FR.joined"
expect_eq "(T69-fragment-c) the arm: the header written on the fragment's line is not read for T7" \
  "" "$(units_landings "$LP_PLAN" "$FR.joined" | grep '^T7	')"
echo "earlier" > "$SW"
_wt_proofs_append "$SW" T1 wt/s ssss mmmm "stamp/v1|s" 2026-01-01T00:00:00Z; SW_RC=$?
expect_eq "(T69-short-b) the arm: the real dd appends the block" \
  "0|$(printf 'earlier\nlanded: row=T1 branch=wt/s head=ssss merge=mmmm at=2026-01-01T00:00:00Z\nstamp/v1|s')" "$SW_RC|$(cat "$SW")"

# (kill) A PROCESS KILLED AT EACH ACT OF THE APPEND, by TERM and by KILL: before the private file is
# made, once it is made, once the block is in it, after the record's type is tested, after the one
# write, before the private file is removed. The record holds the block whole (killed after the
# write) or not at all (before it); nothing but private files `.landing-proofs.log.<pid>.<random>`
# is left beside it; and the next append is made and ignores them.
KL="$TMP/kill/landing-proofs.log"; KL_MARK="$TMP/kill-reached"
cat > "$TMP/kill-child.sh" <<'KL_EOF'
. "$1" || exit 9
REC="$2"; AT="$3"; SIG="$4"; MARK="$5"; ME=$$
k_at() { [ "$AT" = "$1" ] || return 0; echo "$1" > "$MARK"; kill -"$SIG" "$ME"; sleep 2; exit 0; }
mktemp() { k_at mktemp-before; command mktemp "$@"; local rc=$?; k_at mktemp-after; return "$rc"; }
wc() { k_at block-written; command wc "$@"; }
dd() { k_at type-tested; command dd "$@"; local rc=$?; k_at written; return "$rc"; }
rm() { k_at removing; command rm "$@"; }
_wt_proofs_append "$REC" T9 wt/k kkkk mmmm "stamp/v1|k" 2026-01-01T00:00:00Z
echo "survived rc=$?"
KL_EOF
KL_BLOCK="landed: row=T9 branch=wt/k head=kkkk merge=mmmm at=2026-01-01T00:00:00Z
stamp/v1|k"
KL_NEXT="landed: row=T10 branch=wt/n head=nnnn merge=mmmm at=2026-01-01T00:00:01Z
stamp/v1|n"
KL_BAD=""
for _sig in TERM KILL; do
  for _at in mktemp-before mktemp-after block-written type-tested written removing; do
    rm -rf "${KL%/*}" "$KL_MARK"; mkdir -p "${KL%/*}"; echo "earlier" > "$KL"
    # The shell's own "Terminated"/"Killed" report goes to /dev/null with the subshell's stderr.
    _rc="$(exec 2>/dev/null; bash "$TMP/kill-child.sh" "$LIB" "$KL" "$_at" "$_sig" "$KL_MARK" > "$TMP/kill-out" 2>&1; echo "$?")"
    _want="earlier"; case "$_at" in written|removing) _want="earlier
${KL_BLOCK}" ;; esac
    _beside="$(ls -A "${KL%/*}" | grep -vxF landing-proofs.log | grep -v '^\.landing-proofs\.log\.[0-9][0-9]*\.[A-Za-z0-9]*$')"
    [ "$(cat "$KL_MARK" 2>/dev/null)|$_rc" = "$_at|$([ "$_sig" = TERM ] && echo 143 || echo 137)" ] || KL_BAD="${KL_BAD} ${_sig}/${_at}:not-killed-there($(cat "$KL_MARK" 2>/dev/null)|$_rc)"
    [ "$(cat "$KL")" = "$_want" ] || KL_BAD="${KL_BAD} ${_sig}/${_at}:record"
    [ -z "$_beside" ] || KL_BAD="${KL_BAD} ${_sig}/${_at}:left(${_beside})"
    _wt_proofs_append "$KL" T10 wt/n nnnn mmmm "stamp/v1|n" 2026-01-01T00:00:01Z || KL_BAD="${KL_BAD} ${_sig}/${_at}:next-failed"
    [ "$(cat "$KL")" = "${_want}
${KL_NEXT}" ] || KL_BAD="${KL_BAD} ${_sig}/${_at}:next-record"
  done
done
expect_eq "(T69-kill) killed by TERM and by KILL at each of six acts: no block or a whole one, only private files left, the next append made" \
  "" "$KL_BAD"
expect_eq "(T69-kill-pre) fixture: killed after the write, a private file is what is left, and the record holds the block once" \
  "1|1" "$(ls -A "${KL%/*}" | grep -c '^\.landing-proofs\.log\.')|$(grep -c '^landed: row=T9 ' "$KL")"

# (pairs) TWO WHOLE LANDINGS AT ONCE INTO ONE BRANCH, eighty pairs, each pair in a repository of its
# own (two landings into one checkout at once can leave that checkout dirty for the next pair; that
# is not the record's, and a fresh repository keeps every pair's question the record's). Each tree
# carries eight stamp lines of its own. Every LANDED line names the record and its branch has exactly
# one header there, followed by exactly its own eight lines; a refused landing (one of a pair usually
# is; now and then both are, which is `land`'s answer to two merges in one checkout, not the record's)
# has no header; no landing ends proofs=unwritten.
pr_repo() {  # <dir> -> a repository with LP's bound plan shape, bound to LP_SID; echoes its path
  local r p; r="$(new_repo "$1")"; p="$r/.bionic/docs/plans/epic-x/wave-lp.plan.md"
  mkdir -p "${p%/*}" "$r/.bionic/tmp"
  printf -- '---\nworking-branch: wave/fixture\n---\n# fixture plan\n\n## SDLC State\n\ncurrent: 4\n\n## Tasks\n\n| id | step | kind | task | worktree | status |\n|---|---|---|---|---|---|\n\n## Task detail\n' > "$p"
  printf 'plan=%s\nengaged_at=2026-09-23T00:00:00Z\n' "$p" > "$r/.bionic/tmp/engaged-${LP_SID}.state"
  printf '%s' "$r"
}
pr_tree() {  # <repo> <name> -> a tree a commit ahead, its record link, eight stamp lines of its own
  local t="$1/.worktrees/$2" h i
  git -C "$1" worktree add --quiet -b "wt/$2" "$t" HEAD >/dev/null 2>&1
  echo "$2" > "$t/$2.txt"; git -C "$t" add -A >/dev/null 2>&1; git -C "$t" commit --quiet -m "$2 work"
  ln -s "$1/.bionic" "$t/.bionic"; h="$(git -C "$t" rev-parse HEAD)"
  for i in 1 2 3 4 5 6 7 8; do lp_stamp "$t" "$h" 0 "s${i}.test.sh" "bash tests/s${i}.test.sh tag=$2"; done
  printf '%s' "$t"
}
PR_LANDED=0; PR_REFUSED=0; PR_BAD=""; PR_STRAY=""
for _k in $(seq 1 80); do
  _r="$(pr_repo "$TMP/pairs/r${_k}")"; _log="$_r/.bionic/docs/record/wave-lp/landing-proofs.log"
  _a="$(pr_tree "$_r" a)"; _b="$(pr_tree "$_r" b)"
  ( worktree_land_for_session "$_a" "$_r" "$LP_SID" > "$TMP/pr-a" 2>&1 ) & _pa=$!
  ( worktree_land_for_session "$_b" "$_r" "$LP_SID" > "$TMP/pr-b" 2>&1 ) & _pb=$!
  wait "$_pa" "$_pb"
  for _x in a b; do
    _line="$(grep 'spawn-worktree:' "$TMP/pr-${_x}" | head -n 1)"
    _n="$(grep -c "^landed: row=[^ ]* branch=wt/${_x} " "$_log" 2>/dev/null)"
    _own="$(awk -v b="wt/${_x}" '/^landed: /{on=($0 ~ (" branch=" b " "))} on && !/^landed: /' "$_log" 2>/dev/null | grep -c "tag=${_x}$")"
    _all="$(awk -v b="wt/${_x}" '/^landed: /{on=($0 ~ (" branch=" b " "))} on && !/^landed: /' "$_log" 2>/dev/null | grep -c .)"
    case "$_line" in
      *"LANDED branch=wt/${_x} "*"proofs=${_log}")
        PR_LANDED=$((PR_LANDED + 1)); [ "$_n|$_own|$_all" = "1|8|8" ] || PR_BAD="${PR_BAD} ${_k}${_x}:${_n}|${_own}|${_all}" ;;
      *"REFUSED"*) PR_REFUSED=$((PR_REFUSED + 1)); [ "${_n:-0}" = 0 ] || PR_BAD="${PR_BAD} ${_k}${_x}:refused-but-recorded" ;;
      *) PR_BAD="${PR_BAD} ${_k}${_x}:other(${_line})" ;;
    esac
  done
  [ -z "$(grep -v '^landed: \|^stamp/v1|' "$_log" 2>/dev/null)" ] || PR_BAD="${PR_BAD} ${_k}:a-line-neither"
  PR_STRAY="${PR_STRAY}$(ls -A "${_log%/*}" | grep -vxF landing-proofs.log)"
  rm -rf "$TMP/pairs/r${_k}"
done
expect_eq "(T69-pairs) eighty pairs of landings at once: every landed block whole and its own, no refused one recorded, none unwritten" "" "$PR_BAD"
expect_true "(T69-pairs-b) …and the row read landings: ${PR_LANDED} landed, ${PR_REFUSED} refused, of 160" \
  test "$PR_LANDED" -gt 0 -a "$((PR_LANDED + PR_REFUSED))" -eq 160
expect_eq "(T69-pairs-c) …and nothing is left beside any pair's record" "" "$PR_STRAY"

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

# (n1) A LANDING REFUSED AFTER ITS PROOF LEAVES NO RECORD WHERE THERE WAS NONE: the proof creates
# nothing there (T69), and nothing in `land` removes a record. A failing pre-merge-commit hook
# refuses the landing after the proof; with no record before, none after; with
# earlier landings in it, the record is untouched. A declared check refuses before the proof is
# taken, so it leaves no file either.
LPE="$(lp_tree wt/27-T7 27-T7)"; green_stamp "$LPE"
LP_PMC="$(git -C "$LP" rev-parse --absolute-git-dir)/hooks/pre-merge-commit"
mkdir -p "${LP_PMC%/*}"; printf '#!/bin/sh\nexit 1\n' > "$LP_PMC"; chmod +x "$LP_PMC"
mv "$LP_LOG" "${LP_LOG}.keep"
OUTLPE="$(worktree_land_for_session "$LPE" "$LP" "$LP_SID" 2>&1)"; RCLPE=$?
expect_match "(T50-n1) fixture: the landing is refused after the proof (merge-failed)" "spawn-worktree: REFUSED reason=merge-failed *" "$OUTLPE"
expect_false "(T50-n1b) no record file is left: the proof created none" test -e "$LP_LOG"
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

section "§LAND-RECORD-LOCK: a refused landing never loses another's block; the proof covers the directory; a check leaves nothing it changed (wave-27 T58, T69; review pass 34)"
#
# B1. A refused landing beside an appending one: the appended block is there. Since T69 nothing in
# `land` removes or truncates the record, so there is no cleanup to race. S2. The proof covers the
# record's directory: one that cannot be written refuses before the merge. A `<record>.lock` left by
# an older version is no refusal and is never removed. N4. The record's type is tested immediately
# before the append: a FIFO swapped in after the proof is never opened. N5. After the declared check
# the target's HEAD is where it was and the piece's checkout is as clean as it was, or the landing
# is refused `check-dirtied`; a check that fails and dirties names the dirt on its `check-failed`
# refusal. The rows for the lock's wait and for a cleanup under the lock went with the lock (T69).
#
# FIXTURE FIDELITY. The race row is two real acts at once: a whole landing through
# `worktree_land_for_session`, refused after its proof by a failing pre-merge-commit hook, and the real
# `_wt_proofs_append` (review pass 34 `p3-wrap.sh`, its stub `_wt_land` gone with the cleanup it
# wrapped). Every other row is a whole landing through `worktree_land_for_session` or `worktree_land`,
# over the fixtures above.

# (b1) THE REVIEW'S SHAPE: landing A proves the record and is refused 30 ms later (its pre-merge-commit
# hook marks the moment and fails); B appends its block 20 to 60 ms after the mark. B's block is in the
# record afterwards, in every one of 300.
T58_R="$(pr_repo "$TMP/t58-race")"; T58_REC="$T58_R/.bionic/docs/record/wave-lp/landing-proofs.log"
T58_A="$(pr_tree "$T58_R" a)"; T58_MARK="$TMP/t58-proved"
T58_PMC="$(git -C "$T58_R" rev-parse --absolute-git-dir)/hooks/pre-merge-commit"
mkdir -p "${T58_PMC%/*}"; printf '#!/bin/sh\n: > "%s"; sleep 0.03; exit 1\n' "$T58_MARK" > "$T58_PMC"; chmod +x "$T58_PMC"
T58_LOST=0; T58_KEPT=0; T58_REF=0; T58_BFAIL=0
for _k in $(seq 1 300); do
  rm -f "$T58_REC" "$T58_MARK"
  _d="$(printf '0.%03d' $((20 + RANDOM % 41)))"
  ( worktree_land_for_session "$T58_A" "$T58_R" "$LP_SID" > "$TMP/t58-a.out" 2>&1 ) & _pa=$!
  ( _w=0; while [ ! -e "$T58_MARK" ] && [ "$_w" -lt 5000 ]; do sleep 0.002; _w=$((_w + 1)); done
    sleep "$_d"; _wt_proofs_append "$T58_REC" T2 wt/b bbbb mmmm "stamp/v1|head=bbbb|rc=0" || echo FAILED ) > "$TMP/t58-b.out" 2>&1 & _pb=$!
  wait "$_pa" "$_pb"
  case "$(head -n 1 "$TMP/t58-a.out")" in "spawn-worktree: REFUSED reason=merge-failed "*) T58_REF=$((T58_REF + 1)) ;; esac
  [ -s "$TMP/t58-b.out" ] && T58_BFAIL=$((T58_BFAIL + 1))
  if [ -f "$T58_REC" ] && grep -q '^landed: row=T2 ' "$T58_REC"; then T58_KEPT=$((T58_KEPT + 1)); else T58_LOST=$((T58_LOST + 1)); fi
done
rm -f "$T58_PMC"
expect_eq "(T58-b1-pre) fixture: landing A was refused merge-failed after its proof in every trial, and B never failed its append" "300|0" "$T58_REF|$T58_BFAIL"
expect_eq "(T58-b1) 300 trials of a refused landing beside an append: B's block is kept in every one" \
  "kept=300 lost=0" "kept=$T58_KEPT lost=$T58_LOST"

# (s2) THE PROOF COVERS THE DIRECTORY. A read-only record directory holding a writable record refuses
# BEFORE the merge. A lock directory an older version left (its holder gone) does not: the landing
# records, and the lock is left where it was.
lp_bind '| T7 | 4 | build | seven | .worktrees/27-T7 | active |'
T58_T="$(lp_tree wt/27-T7 27-T7)"; green_stamp "$T58_T"
T58_LOGB="$(cat "$LP_LOG")"
t58_refused() {  # <label> — lands T58_T with the record as the caller left it: refused before the merge
  local l="$1" out rc tgt trees st
  tgt="$(git -C "$LP" rev-parse refs/heads/wave/fixture)"; trees="$(trees_of "$LP")"; st="$(cat "$(stamp_file "$T58_T")")"
  out="$(worktree_land_for_session "$T58_T" "$LP" "$LP_SID" 2>&1)"; rc=$?
  expect_match "(T58-$l) refused why=proofs-unwritable before the merge, naming the record" \
    "spawn-worktree: REFUSED reason=record-unwritable why=proofs-unwritable path=${LP_LOG} branch=wt/27-T7 — *" "$out"
  expect_eq "(T58-$l-b) …exit 2, the target's head, every worktree and the stamp file as before" \
    "2|$tgt|$trees|$st" "$rc|$(git -C "$LP" rev-parse refs/heads/wave/fixture)|$(trees_of "$LP")|$(cat "$(stamp_file "$T58_T")")"
}
expect_true "(T58-s2-pre) fixture: the record is a writable regular file" test -f "$LP_LOG" -a -w "$LP_LOG"
chmod 555 "${LP_LOG%/*}"; t58_refused s2-readonly-dir; chmod 755 "${LP_LOG%/*}"
true & T58_DEAD=$!; wait "$T58_DEAD"
mkdir "${LP_LOG}.lock"; echo "$T58_DEAD" > "${LP_LOG}.lock/pid"
expect_match "(T69-s2-old-lock) an older version's lock directory is no refusal: the landing records" \
  "spawn-worktree: LANDED branch=wt/27-T7 * removed=${T58_T} proofs=${LP_LOG}" "$(worktree_land_for_session "$T58_T" "$LP" "$LP_SID" 2>&1)"
expect_eq "(T69-s2-old-lock-b) …and the lock is left as it was" "$T58_DEAD" "$(cat "${LP_LOG}.lock/pid" 2>/dev/null)"
expect_eq "(T58-s2-stale-c) …and its block follows the record as it was" "$T58_LOGB" "$(head -n "$(printf '%s\n' "$T58_LOGB" | awk 'END { print NR }')" "$LP_LOG")"
rm -rf "${LP_LOG}.lock"

# (n4) A FIFO SWAPPED IN BY A POST-MERGE HOOK, after the proof and before the append. Nothing reads
# it, so an open would block for good: the landing returns inside twenty seconds, proofs=unwritten,
# the tree kept, the FIFO still there.
T58_T="$(lp_tree wt/27-T7 27-T7)"; green_stamp "$T58_T"
cp "$LP_LOG" "$TMP/t58-log.keep"
LP_HOOK="$(git -C "$LP" rev-parse --absolute-git-dir)/hooks/post-merge"
mkdir -p "${LP_HOOK%/*}"; printf '#!/bin/sh\nrm -f "%s"; mkfifo "%s"\n' "$LP_LOG" "$LP_LOG" > "$LP_HOOK"; chmod +x "$LP_HOOK"
( worktree_land_for_session "$T58_T" "$LP" "$LP_SID" > "$TMP/t58-fifo.out" 2>&1; echo "rc=$?" >> "$TMP/t58-fifo.out" ) &
T58_P=$!; T58_T0=$SECONDS
while kill -0 "$T58_P" 2>/dev/null && [ $((SECONDS - T58_T0)) -lt 20 ]; do sleep 0.1; done
T58_HUNG=no
if kill -0 "$T58_P" 2>/dev/null; then T58_HUNG=yes; kill -KILL "$T58_P" 2>/dev/null; fi
wait "$T58_P" 2>/dev/null
T58_ISFIFO=no; [ -p "$LP_LOG" ] && T58_ISFIFO=yes
rm -f "$LP_HOOK" "$LP_LOG"; cp "$TMP/t58-log.keep" "$LP_LOG"
T58_FM="$(git -C "$LP" rev-parse refs/heads/wave/fixture)"
expect_eq "(T58-n4) the landing returns inside twenty seconds: the FIFO was never opened" "no" "$T58_HUNG"
expect_match "(T58-n4b) …LANDED, the merge standing, proofs=unwritten, the tree kept" \
  "spawn-worktree: LANDED branch=wt/27-T7 onto=wave/fixture checkout=${LP} merge=${T58_FM} kept=${T58_T} proofs=unwritten *" \
  "$(head -n 1 "$TMP/t58-fifo.out")"
expect_eq "(T58-n4c) …exit 0" "rc=0" "$(tail -n 1 "$TMP/t58-fifo.out")"
expect_eq "(T58-n4d) …the hook did swap a FIFO in" "yes" "$T58_ISFIFO"
rm -f "$T58_T/.bionic"; git -C "$LP" worktree remove --force "$T58_T" >/dev/null 2>&1

# (n5) WHAT THE DECLARED CHECK MAY LEAVE. A check that commits on the target, one that writes a
# tracked file in the piece's checkout, and one that fails and writes a tracked file in the target.
LN="$(new_repo "$TMP/land-n5")"
LN_MODE="$TMP/ln-mode"; echo none > "$LN_MODE"
cat > "$TMP/ln-check.sh" <<LN_EOF
#!/bin/bash
case "\$(cat "$LN_MODE")" in
  commit) echo c >> file.txt; git commit --quiet -am "made by the check" ;;
  piece) echo w >> "\$BIONIC_CHECK_TREE/file.txt" ;;
  fail-dirty) echo x >> file.txt; exit 1 ;;
esac
exit 0
LN_EOF
printf 'release-check: bash %s\n' "$TMP/ln-check.sh" > "$LN/.bionic/config.yaml"
ln_tree() {  # <branch> -> tree path, with its record link and a green stamp at its head
  local t; t="$(new_tree "$LN" "$1")"; ln -s "${LN}/.bionic" "$t/.bionic"; green_stamp "$t"; printf '%s' "$t"
}

echo commit > "$LN_MODE"
LN1="$(ln_tree chk-commit)"; LN1_H="$(git -C "$LN1" rev-parse HEAD)"
LN1_WAS="$(git -C "$LN" rev-parse --short HEAD)"; LN1_ST="$(cat "$(stamp_file "$LN1")")"
OUTLN1="$(worktree_land "$LN1" wave/fixture 2>/dev/null)"; RCLN1=$?
LN1_NOW="$(git -C "$LN" rev-parse --short HEAD)"
expect_eq "(T58-n5-pre) fixture: the check made a commit on the target" "made by the check" "$(git -C "$LN" log -1 --format=%s)"
expect_match "(T58-n5) a check that commits on the target refuses the landing check-dirtied, naming both short ids" \
  "spawn-worktree: REFUSED reason=check-dirtied why=release-check checkout=${LN} head_was=${LN1_WAS} head_now=${LN1_NOW} branch=chk-commit — the target checkout's HEAD moved from ${LN1_WAS} to ${LN1_NOW} while the project's declared release-check (*) ran, by the check or by another landing into wave/fixture *" "$OUTLN1"
expect_eq "(T58-n5b) …exit 2" "2" "$RCLN1"
expect_false "(T58-n5c) …nothing is merged: the tree's head is not on the target" \
  git -C "$LN" merge-base --is-ancestor "$LN1_H" refs/heads/wave/fixture
expect_eq "(T58-n5d) …the target left as the check left it, the tree and its stamps kept" \
  "made by the check|yes|$LN1_ST" "$(git -C "$LN" log -1 --format=%s)|$([ -d "$LN1" ] && echo yes)|$(cat "$(stamp_file "$LN1")")"
git -C "$LN" reset --quiet --hard HEAD~1

echo piece > "$LN_MODE"
LN2="$(ln_tree chk-piece)"; LN2_REFS="$(refs_of "$LN")"
OUTLN2="$(worktree_land "$LN2" wave/fixture 2>/dev/null)"; RCLN2=$?
expect_match "(T58-n5e) a check that writes a tracked file in the piece's checkout refuses check-dirtied, naming the path" \
  "spawn-worktree: REFUSED reason=check-dirtied why=release-check checkout=${LN} piece_paths=file.txt branch=chk-piece — *changed the piece's checkout ${LN2}*" "$OUTLN2"
expect_eq "(T58-n5f) …exit 2, no ref moved" "2|$LN2_REFS" "$RCLN2|$(refs_of "$LN")"
expect_eq "(T58-n5g) …the piece left as the check left it, the tree standing" " M file.txt|yes" \
  "$(git -C "$LN2" status --porcelain --untracked-files=no)|$([ -d "$LN2" ] && echo yes)"

echo fail-dirty > "$LN_MODE"
LN3="$(ln_tree chk-faildirty)"; LN3_REFS="$(refs_of "$LN")"
OUTLN3="$(worktree_land "$LN3" wave/fixture 2>/dev/null)"; RCLN3=$?
expect_match "(T58-n5h) a check that fails and dirties the target is refused for the failure, naming the path" \
  "spawn-worktree: REFUSED reason=check-failed why=release-check rc=1 branch=chk-faildirty base=* head=* paths=file.txt — *" "$OUTLN3"
expect_eq "(T58-n5i) …exit 2, no ref moved, the target left as the check left it" "2|$LN3_REFS| M file.txt" \
  "$RCLN3|$(refs_of "$LN")|$(git -C "$LN" status --porcelain --untracked-files=no)"
git -C "$LN" checkout --quiet -- file.txt

echo none > "$LN_MODE"
git -C "$LN2" checkout --quiet -- file.txt
expect_match "(T58-n5j) the arm discriminates: the piece lands once it is clean and the check changes nothing" \
  "spawn-worktree: LANDED branch=chk-piece onto=wave/fixture *" "$(worktree_land "$LN2" wave/fixture 2>/dev/null)"

section "§LAND-HEAD-MOVED: a moved head is not blamed on the check (wave-27 T63; review pass 43 S1)"
#
# S1. A head moved while the check ran is reported as that, by the check or by another landing,
# with nothing merged and "land again". The rows T63 added for the record's lock (B1, B2: the
# takeover, `.taking`, the cleanup, the proof's second look at the lock's path) went with the lock
# (wave-27 T69; review pass 48).
#
# FIXTURE FIDELITY. Two whole landings through `worktree_land` into one target (review pass 43
# `q6-two.sh`).

# (s1) WHO MOVED THE HEAD. Landing A's check takes three seconds; landing B lands into the same target
# meanwhile. A is refused check-dirtied with the line the rule gives: the head moved while the check
# ran, by the check or by another landing, both short ids, nothing merged, land again, and no "put
# back what it changed". Run again, A lands.
echo slow > "$LN_MODE"
cat > "$TMP/ln-check.sh" <<LN_EOF
#!/bin/bash
case "\$(cat "$LN_MODE")" in
  commit) echo c >> file.txt; git commit --quiet -am "made by the check" ;;
  piece) echo w >> "\$BIONIC_CHECK_TREE/file.txt" ;;
  fail-dirty) echo x >> file.txt; exit 1 ;;
  slow) case "\$BIONIC_CHECK_TREE" in */chk-slow) sleep 3 ;; esac ;;
esac
exit 0
LN_EOF
LN4="$(ln_tree chk-slow)"; LN5="$(ln_tree chk-fast)"; LN4_H="$(git -C "$LN4" rev-parse HEAD)"
LN4_WAS="$(git -C "$LN" rev-parse --short HEAD)"
( worktree_land "$LN4" wave/fixture > "$TMP/ln4.out" 2>/dev/null; echo "rc=$?" >> "$TMP/ln4.out" ) & T63_PA=$!
sleep 1
OUTLN5="$(worktree_land "$LN5" wave/fixture 2>/dev/null)"
wait "$T63_PA"
LN4_NOW="$(git -C "$LN" rev-parse --short HEAD)"; OUTLN4="$(head -n 1 "$TMP/ln4.out")"
expect_match "(T63-s1-pre) fixture: landing B landed into the target while A's check ran" "spawn-worktree: LANDED branch=chk-fast onto=wave/fixture *" "$OUTLN5"
expect_match "(T63-s1) A is refused: the head moved while the check ran, by the check or by another landing; nothing merged; land again" \
  "spawn-worktree: REFUSED reason=check-dirtied why=release-check checkout=${LN} head_was=${LN4_WAS} head_now=${LN4_NOW} branch=chk-slow — the target checkout's HEAD moved from ${LN4_WAS} to ${LN4_NOW} while the project's declared release-check (bash ${TMP}/ln-check.sh) ran, by the check or by another landing into wave/fixture (git -C ${LN} reflog -2), and nothing is merged; if the move is another landing's merge, land again*" "$OUTLN4"
expect_eq "(T63-s1b) …exit 2, and the line does not say to put back what it changed" "rc=2|0" "$(tail -n 1 "$TMP/ln4.out")|$(printf '%s' "$OUTLN4" | grep -c 'put back what it changed')"
expect_match "(T63-s1c) the arm: A run again lands" "spawn-worktree: LANDED branch=chk-slow onto=wave/fixture *" "$(worktree_land "$LN4" wave/fixture 2>/dev/null)"
expect_true "(T63-s1d) …and its head is now on the target" git -C "$LN" merge-base --is-ancestor "$LN4_H" refs/heads/wave/fixture
echo none > "$LN_MODE"

section "§LAND-BIONIC: a committed .bionic never reaches the project's .bionic directory (wave-27 T79; the walk's W2)"
#
# THE LOSS. In a project whose .gitignore does not list `.bionic`, a writer's `git add -A`
# committed the link `create` plants; the land merged it into the main checkout, whose `.bionic`
# is a real directory every file of which its own `.gitignore` (`*`) ignores, and git replaced
# the directory with the link: a link to itself, the plan, record and marker gone. So `land`
# refuses, before any merge, a range whose difference names `.bionic` or a path under it, unless
# the target already tracks `.bionic` (an older project's own content).
#
# FIXTURE FIDELITY. lb_repo is the walk's project as measured (record: walk.md W2): .gitignore
# lists only `.worktrees/`, `.bionic/.gitignore` is `*`, the plan, a record and the engagement
# marker untracked inside it. The link is committed with `git add -f`, so the arm holds whether
# or not `create`'s exclude line is present.
#
# ANTI-VACUITY. The refused arms sit beside the same tree landing once its remedy is taken, and
# beside a target that tracks `.bionic` landing a change under it.
lb_repo() {  # <dir> -> physical path, on wave/fixture, its .bionic a real untracked directory
  local d="$1"
  mkdir -p "$d"
  git -C "$d" init --quiet 2>/dev/null
  git -C "$d" symbolic-ref HEAD refs/heads/main
  printf '.worktrees/\n' > "$d/.gitignore"
  echo "one" > "$d/file.txt"
  git -C "$d" add .gitignore file.txt
  git -C "$d" commit --quiet -m "c1"
  git -C "$d" checkout --quiet -b wave/fixture
  mkdir -p "$d/.bionic/docs/plans" "$d/.bionic/docs/record" "$d/.bionic/tmp"
  printf '*\n' > "$d/.bionic/.gitignore"
  echo "plan" > "$d/.bionic/docs/plans/w.plan.md"
  echo "record" > "$d/.bionic/docs/record/r.md"
  echo "marker" > "$d/.bionic/tmp/engaged-x.state"
  bind_plan "$d" "$LB_SID" wave/fixture >/dev/null
  ( cd "$d" && pwd -P )
}
# The project's own files under .bionic: the landing's own record directory (`record/wave-x/`, the
# bound plan's: the line's events and the publish lock) and its landing trees (`tmp/landing/`) are
# the tool's writes, not the project's, and are left out (wave-28 T3, A-T3.6).
lb_sums() {  # <repo> -> one checksum line per file under its .bionic, sorted
  ( cd "$1/.bionic" && find . -type f -not -path './tmp/landing/*' -not -path './docs/record/wave-x/*' \
      | LC_ALL=C sort | while IFS= read -r f; do printf '%s ' "$f"; cksum < "$f"; done )
}
# THE DRIVE IS THE HAND LANDING (wave-28 T3; REQ-14 AC-14.1, D31): every row of this section once
# called `worktree_land` (or the stand-down's `worktree_land_for_session`); each now lands through
# `line_land_by_hand`, the library `spawn-worktree.sh land --by-hand` calls, in this shell so the
# rows' mutants (a function redefined in a subshell) still reach it. The repository's session is
# bound by lb_repo, so the working branch is read off the plan as the verb reads it; (b0) drives the
# verb itself.
LB_SID="land-bionic-hand-01"
lb_land() {  # <tree> -> the hand landing's lines, as `land <tree> --by-hand` prints them
  local r
  r="$(worktree_root "$1" 2>/dev/null)" || r=""
  WORKTREE_CONTRACT_PROG=spawn-worktree line_land_by_hand "$1" "$r" "$LB_SID" "a section-LAND-BIONIC drive"
}
lb_tree() {  # <repo> <branch> -> a tree a commit ahead, then a second commit adding its link with add -f
  local r="$1" t; t="$(new_tree "$r" "$2")"
  ln -s "${r}/.bionic" "$t/.bionic"
  git -C "$t" add -f .bionic && git -C "$t" commit --quiet -m "$2 the link, committed"
  green_stamp "$t"; printf '%s' "$t"
}
lb_first() { printf '%s\n' "$1" | sed -n 1p; }

LB="$(lb_repo "$TMP/land-bionic")"
LBT="$(lb_tree "$LB" wt/linked)"
LBC="$(git -C "$LBT" rev-parse HEAD)"
expect_eq   "(fixture) the tree's branch tracks the link" "120000" \
  "$(git -C "$LBT" ls-tree HEAD .bionic | awk '{ print $1 }')"
expect_true "(fixture) the project's .bionic holds its plan" test -f "$LB/.bionic/docs/plans/w.plan.md"
LB_SUMS="$(lb_sums "$LB")"; LB_REFS="$(refs_of "$LB")"; LB_STAMPS="$(cat "$(stamp_file "$LBT")")"
expect_true "(fixture) the checksum reader reads the directory" test -n "$LB_SUMS"
OUTLB="$(lb_land "$LBT")"; RCLB=$?
LB_LINE="$(lb_first "$OUTLB")"
expect_match "(b1) a range that commits .bionic is refused on land's contract line: the path, the commit that added it, the remedy" \
  "spawn-worktree: REFUSED reason=bionic-committed path=.bionic commit=${LBC:0:12} branch=wt/linked onto=wave/fixture fix='git -C ${LBT} rm -r --cached .bionic, commit, say ready again' — *" "$LB_LINE"
expect_eq   "(b1) …exit 2" "2" "$RCLB"
expect_eq   "(b1) …one line, as its siblings print" "1" "$(printf '%s\n' "$OUTLB" | awk 'END { print NR }')"
expect_contains "(b1) …saying nothing is merged and the tree is kept, and nothing of stamps" \
  "nothing is merged, the tree is kept" "$LB_LINE"
expect_absent   "(b1) …and nothing of stamps" "stamps" "$LB_LINE"
expect_true  "(b1) the project's .bionic is still a directory" test -d "$LB/.bionic"
expect_false "(b1) …and not a link" test -L "$LB/.bionic"
expect_eq    "(b1) …its files byte for byte" "$LB_SUMS" "$(lb_sums "$LB")"
expect_eq    "(b1) no ref moved" "$LB_REFS" "$(refs_of "$LB")"
expect_true  "(b1) the tree is kept" test -d "$LBT"
expect_eq    "(b1) …and its stamps" "$LB_STAMPS" "$(cat "$(stamp_file "$LBT")")"

# A DEEP PATH: a file far under .bionic, committed. The line names that path; the remedy
# is the same.
LBD="$(new_tree "$LB" wt/deep)"
LBD_P=".bionic/docs/record/$(printf 'very-long-directory-name-%s/' 1 2 3 4 5 6)$(printf 'x%.0s' $(seq 1 120)).md"
mkdir -p "$LBD/${LBD_P%/*}"; echo deep > "$LBD/$LBD_P"
git -C "$LBD" add -f "$LBD_P" && git -C "$LBD" commit --quiet -m "deep path"; green_stamp "$LBD"
LBD_C="$(git -C "$LBD" rev-parse HEAD)"
OUTLBD="$(lb_land "$LBD")"
expect_match "(b2) a deep path under .bionic is refused, naming that path and its commit" \
  "spawn-worktree: REFUSED reason=bionic-committed path=${LBD_P} commit=${LBD_C:0:12} branch=wt/deep *" "$(lb_first "$OUTLBD")"
expect_eq    "(b2) …the project's .bionic files byte for byte" "$LB_SUMS" "$(lb_sums "$LB")"

# THE REMEDY, TAKEN: the link out of the index, committed; the same tree lands and the directory stands.
git -C "$LBT" rm -r --cached --quiet .bionic && git -C "$LBT" commit --quiet -m "the link out of the index"
green_stamp "$LBT"
expect_match "(b3) after git rm -r --cached .bionic and a commit, the tree lands" \
  "spawn-worktree: LANDED branch=wt/linked onto=wave/fixture *" "$(lb_land "$LBT")"
expect_false "(b3) …the project's .bionic is not a link" test -L "$LB/.bionic"
expect_eq    "(b3) …and its files byte for byte" "$LB_SUMS" "$(lb_sums "$LB")"

# THE STAND-DOWN PATH: the one the standdown calls, the target read off the bound plan.
LBS_SID="land-bionic-session-01"
bind_plan "$LB" "$LBS_SID" wave/fixture >/dev/null
LBS="$(lb_tree "$LB" wt/standdown)"; LBS_C="$(git -C "$LBS" rev-parse HEAD)"
LBS_SUMS="$(lb_sums "$LB")"; LBS_REFS="$(refs_of "$LB")"
OUTLBS="$(lb_land "$LBS")"; RCLBS=$?
expect_match "(b4) the stand-down path refuses the same range on the same line" \
  "spawn-worktree: REFUSED reason=bionic-committed path=.bionic commit=${LBS_C:0:12} branch=wt/standdown onto=wave/fixture *" "$(lb_first "$OUTLBS")"
expect_eq   "(b4) …exit 2" "2" "$RCLBS"
expect_eq   "(b4) …no ref moved" "$LBS_REFS" "$(refs_of "$LB")"
expect_eq   "(b4) …the project's .bionic files byte for byte" "$LBS_SUMS" "$(lb_sums "$LB")"
expect_true "(b4) …the tree is kept" test -d "$LBS"
git -C "$LBS" rm -r --cached --quiet .bionic && git -C "$LBS" commit --quiet -m "the link out of the index"
green_stamp "$LBS"
expect_match "(b4) …and lands through it once the remedy is taken" \
  "spawn-worktree: LANDED branch=wt/standdown onto=wave/fixture *" "$(lb_land "$LBS")"
expect_false "(b4) …the project's .bionic is not a link" test -L "$LB/.bionic"

# THE ONE EXCEPTION: a target that already tracks something at .bionic lands a change under it as before.
LE="$(lb_repo "$TMP/land-bionic-tracked")"
echo "tracked" > "$LE/.bionic/docs/tracked.md"
git -C "$LE" add -f .bionic/docs/tracked.md && git -C "$LE" commit --quiet -m "the target tracks .bionic"
LET="$(new_tree "$LE" wt/tracked)"
echo "changed on the branch" > "$LET/.bionic/docs/tracked.md"
git -C "$LET" commit --quiet -am "a change under the tracked .bionic"; green_stamp "$LET"
expect_eq    "(b5-pre) the range's difference names a path under .bionic" ".bionic/docs/tracked.md" \
  "$(git -C "$LE" diff --name-only wave/fixture wt/tracked -- .bionic)"
expect_match "(b5) a target that tracks .bionic lands a change under it as before" \
  "spawn-worktree: LANDED branch=wt/tracked onto=wave/fixture *" "$(lb_land "$LET")"
expect_eq    "(b5) …and the change is in the target checkout" "changed on the branch" "$(cat "$LE/.bionic/docs/tracked.md")"
expect_true  "(b5) …whose .bionic is still a directory" test -f "$LE/.bionic/docs/plans/w.plan.md"

# THE KIND OF .bionic (wave-27 T84; review pass 68 on T79). The exception exempts CONTENT UNDER a
# `.bionic` directory the target tracks; it never exempts a change of `.bionic`'s own kind. A
# tree that `git rm -r .bionic`s the tracked content and commits a link there LANDED under the
# exception, and the main checkout's `.bionic` became a link to itself. And a range that ADDED a
# file under the tracked directory overwrote the project's untracked file at that path, git being
# free to overwrite ignored files (A-orch-227). So the rule is per path: a range may change or
# delete paths at or under `.bionic` that the target tracks; it may add nothing there; and
# `.bionic`'s own kind never changes. The kind test runs first and names `.bionic` and the first
# commit that changed the kind; an add names the first added path and the commit that added it.
# A range that deletes every tracked path (nothing left at `.bionic`) lands.
#
# FIXTURE FIDELITY. lk_repo is lb_repo whose target also tracks `.bionic/keep.md` and
# `.bionic/also.md` (an older project's own content), the plan, record and marker still untracked
# beside them; ll_repo is lb_repo whose own history tracks `.bionic` as a link to an untracked
# `.bionic-state` directory. Each refused row has its own repository, so a range the old code
# landed cannot change the next row's target.
#
# ANTI-VACUITY. Each refused arm sits beside a landing arm in a target that tracks the same
# directory, and the mutant (b13) cuts the kind test out and lands b6's range.
lk_repo() {  # <dir> -> lb_repo whose target tracks .bionic as a directory: keep.md and also.md
  local d; d="$(lb_repo "$1")"
  echo "keep" > "$d/.bionic/keep.md"; echo "also" > "$d/.bionic/also.md"
  git -C "$d" add -f .bionic/keep.md .bionic/also.md
  git -C "$d" commit --quiet -m "the target tracks .bionic as a directory"
  printf '%s' "$d"
}
lk_replace() {  # <repo> <branch> link|file -> a tree: a commit changing keep.md, then one replacing .bionic
  local r="$1" t; t="$(new_tree "$r" "$2")"; [ -n "$t" ] || return 1
  echo "changed first" > "$t/.bionic/keep.md"
  git -C "$t" commit --quiet -am "$2 a change under .bionic"
  git -C "$t" rm -r --quiet .bionic && rm -rf "$t/.bionic"
  case "$3" in link) ln -s "${r}/.bionic" "$t/.bionic" ;; *) echo "a file" > "$t/.bionic" ;; esac
  git -C "$t" add -f .bionic && git -C "$t" commit --quiet -m "$2 .bionic replaced by a $3"
  green_stamp "$t"; printf '%s' "$t"
}
lk_kind() { git -C "$1" ls-tree "$2" .bionic | awk '{ print $1 }'; }  # <repo> <rev> -> .bionic's mode
lk_commit() {  # <tree> <message> [path...] — stages the paths named (with -f), commits what is staged, stamps
  local t="$1" m="$2"; shift 2
  if [ "$#" -gt 0 ]; then git -C "$t" add -f -- "$@"; fi
  git -C "$t" commit --quiet -m "$m"; green_stamp "$t"
}

# (b6) THE LOSS REVIEW PASS 68 DROVE: the tracked content removed, a link committed in its place.
LK="$(lk_repo "$TMP/land-kind-link")"
LKT="$(lk_replace "$LK" wt/kind-link link)"
LKT_C="$(git -C "$LKT" rev-parse HEAD)"; LKT_C1="$(git -C "$LKT" rev-parse HEAD^)"
expect_eq   "(b6-pre) the target tracks .bionic as a directory" "040000" "$(lk_kind "$LK" wave/fixture)"
expect_eq   "(b6-pre) …the tree's branch a link there" "120000" "$(lk_kind "$LKT" HEAD)"
expect_eq   "(b6-pre) …and the range's first commit under .bionic is the one before, a change of content" \
  "$LKT_C1" "$(git -C "$LK" log --reverse --format=%H wave/fixture..wt/kind-link -- .bionic | sed -n 1p)"
expect_true "(b6-pre) the project's .bionic holds its tracked file" test -f "$LK/.bionic/keep.md"
LK_SUMS="$(lb_sums "$LK")"; LK_REFS="$(refs_of "$LK")"; LK_STAMPS="$(cat "$(stamp_file "$LKT")")"
OUTLK="$(lb_land "$LKT")"; RCLK=$?
expect_match "(b6) a target tracking .bionic as a directory refuses a range that makes it a link, naming the commit that changed its kind" \
  "spawn-worktree: REFUSED reason=bionic-committed path=.bionic commit=${LKT_C:0:12} branch=wt/kind-link onto=wave/fixture fix='git -C ${LKT} rm -r --cached .bionic, commit, say ready again' — *" "$(lb_first "$OUTLK")"
expect_eq    "(b6) …exit 2" "2" "$RCLK"
expect_true  "(b6) the project's .bionic is still a directory" test -d "$LK/.bionic"
expect_false "(b6) …and not a link" test -L "$LK/.bionic"
expect_eq    "(b6) …its files byte for byte" "$LK_SUMS" "$(lb_sums "$LK")"
expect_eq    "(b6) no ref moved" "$LK_REFS" "$(refs_of "$LK")"
expect_true  "(b6) the tree is kept" test -d "$LKT"
expect_eq    "(b6) …and its stamps" "$LK_STAMPS" "$(cat "$(stamp_file "$LKT")")"

# (b7) THE SAME WITH A REGULAR FILE at .bionic.
LKF="$(lk_repo "$TMP/land-kind-file")"
LKFT="$(lk_replace "$LKF" wt/kind-file file)"; LKFT_C="$(git -C "$LKFT" rev-parse HEAD)"
expect_eq "(b7-pre) the tree's branch a regular file at .bionic" "100644" "$(lk_kind "$LKFT" HEAD)"
LKF_SUMS="$(lb_sums "$LKF")"; LKF_REFS="$(refs_of "$LKF")"
OUTLKF="$(lb_land "$LKFT")"; RCLKF=$?
expect_match "(b7) …and a range that makes it a regular file, on the same line" \
  "spawn-worktree: REFUSED reason=bionic-committed path=.bionic commit=${LKFT_C:0:12} branch=wt/kind-file onto=wave/fixture *" "$(lb_first "$OUTLKF")"
expect_eq   "(b7) …exit 2" "2" "$RCLKF"
expect_true "(b7) the project's .bionic is still a directory" test -d "$LKF/.bionic"
expect_eq   "(b7) …its files byte for byte" "$LKF_SUMS" "$(lb_sums "$LKF")"
expect_eq   "(b7) no ref moved" "$LKF_REFS" "$(refs_of "$LKF")"
expect_true "(b7) the tree is kept" test -d "$LKFT"

# (b8) CONTENT UNDER THE TRACKED DIRECTORY lands as before: changed, added, one file removed. Each
# tree is cut from the target after the last landing, so none is behind on a file it changes.
LC="$(lk_repo "$TMP/land-kind-content")"
LCT="$(new_tree "$LC" wt/kind-change)"; echo "changed on the branch" > "$LCT/.bionic/keep.md"
lk_commit "$LCT" "a change under the tracked .bionic" .bionic/keep.md
expect_match "(b8) a range that changes a file under the tracked .bionic directory lands" \
  "spawn-worktree: LANDED branch=wt/kind-change onto=wave/fixture *" "$(lb_land "$LCT")"
expect_eq    "(b8) …the change is in the target checkout" "changed on the branch" "$(cat "$LC/.bionic/keep.md")"
expect_eq    "(b8) …which still tracks .bionic as a directory" "040000" "$(lk_kind "$LC" wave/fixture)"
expect_true  "(b8) …and holds its plan" test -f "$LC/.bionic/docs/plans/w.plan.md"
LCM="$(new_tree "$LC" wt/kind-more)"; echo "more" > "$LCM/.bionic/more.md"
lk_commit "$LCM" "a file added under the tracked .bionic" .bionic/more.md; LCM_C="$(git -C "$LCM" rev-parse HEAD)"
LC_SUMS="$(lb_sums "$LC")"
expect_match "(b8b) a range that ADDS a file under the tracked directory is refused, naming that path (A-orch-227)" \
  "spawn-worktree: REFUSED reason=bionic-committed path=.bionic/more.md commit=${LCM_C:0:12} branch=wt/kind-more onto=wave/fixture fix='git -C ${LCM} rm --cached .bionic/more.md, move .bionic/more.md out of the tree, commit, say ready again' — *" \
  "$(lb_first "$(lb_land "$LCM")")"
expect_eq    "(b8b) …the project's .bionic files byte for byte" "$LC_SUMS" "$(lb_sums "$LC")"
LCK="$(new_tree "$LC" wt/kind-rm-keep)"; git -C "$LCK" rm --quiet .bionic/keep.md
lk_commit "$LCK" "keep.md removed, the directory left"
expect_match "(b8c) a range that removes one file and leaves the directory lands" \
  "spawn-worktree: LANDED branch=wt/kind-rm-keep onto=wave/fixture *" "$(lb_land "$LCK")"
expect_true  "(b8c) …its sibling is still in the target checkout" test -f "$LC/.bionic/also.md"
expect_false "(b8c) …and the removed file is not" test -e "$LC/.bionic/keep.md"

# (b9) THE TRACKED .bionic REMOVED ENTIRELY lands: nothing is put where the directory was.
LCR="$(new_tree "$LC" wt/kind-rm-all)"; git -C "$LCR" rm -r --quiet .bionic
lk_commit "$LCR" "the tracked .bionic removed"
expect_eq    "(b9-pre) the tree's branch has nothing at .bionic" "" "$(lk_kind "$LCR" HEAD)"
expect_match "(b9) a range that removes the tracked .bionic entirely lands" \
  "spawn-worktree: LANDED branch=wt/kind-rm-all onto=wave/fixture *" "$(lb_land "$LCR")"
expect_true  "(b9) …the project's .bionic is still a directory holding its plan" test -f "$LC/.bionic/docs/plans/w.plan.md"
expect_false "(b9) …and not a link" test -L "$LC/.bionic"

# (b10) A TARGET WHOSE OWN HISTORY TRACKS .bionic AS A LINK: the kind kept lands; a directory in
# its place lands (a directory never destroys a directory).
ll_repo() {  # <dir> -> lb_repo whose target tracks .bionic as a link to an untracked .bionic-state
  local d; d="$(lb_repo "$1")"
  mv "$d/.bionic" "$d/.bionic-state" && ln -s .bionic-state "$d/.bionic"
  printf '.worktrees/\n.bionic-state/\n' > "$d/.gitignore"
  git -C "$d" add -f .gitignore .bionic && git -C "$d" commit --quiet -m "the target tracks .bionic as a link"
  printf '%s' "$d"
}
LL="$(ll_repo "$TMP/land-kind-linked")"
expect_eq    "(b10-pre) the target tracks .bionic as a link" "120000" "$(lk_kind "$LL" wave/fixture)"
LLT="$(new_tree "$LL" wt/kind-keep-link)"; green_stamp "$LLT"; LLT_H="$(git -C "$LLT" rev-parse HEAD)"
# The guard admits this range and the merge is made. The line that follows is the removal's own
# (`worktree-remove-refused … merged=`): land drops the tree's `.bionic` link before `git worktree
# remove`, and in a project that tracks that link the drop leaves the tree dirty. That removal is
# older than the guard and not this row's (record A-T84.2), so the row reads the merge, not the word.
OUTLLT="$(lb_land "$LLT")"
expect_match "(b10) a range that keeps the target's link is merged" "spawn-worktree: * merge*=*" "$(lb_first "$OUTLLT")"
expect_true  "(b10) …the tree's head is on the target" git -C "$LL" merge-base --is-ancestor "$LLT_H" refs/heads/wave/fixture
expect_true  "(b10) …the target's .bionic is still its link" test -L "$LL/.bionic"
expect_true  "(b10) …reaching its plan" test -f "$LL/.bionic/docs/plans/w.plan.md"
LLD="$(new_tree "$LL" wt/kind-link-dir)"; git -C "$LLD" rm --quiet .bionic
mkdir -p "$LLD/.bionic"; echo "a directory now" > "$LLD/.bionic/dir.md"
lk_commit "$LLD" "the link replaced by a directory" .bionic/dir.md
expect_eq    "(b10b-pre) the tree's branch a directory at .bionic" "040000" "$(lk_kind "$LLD" HEAD)"
LLD_C="$(git -C "$LLD" rev-parse HEAD)"; LL_REFS="$(refs_of "$LL")"
expect_match "(b10b) a range that replaces the target's link with a directory is refused: the kind changed (A-orch-227)" \
  "spawn-worktree: REFUSED reason=bionic-committed path=.bionic commit=${LLD_C:0:12} branch=wt/kind-link-dir onto=wave/fixture *" \
  "$(lb_first "$(lb_land "$LLD")")"
expect_eq    "(b10b) …no ref moved" "$LL_REFS" "$(refs_of "$LL")"
expect_true  "(b10b) …the target's .bionic is still its link" test -L "$LL/.bionic"
expect_true  "(b10b) …and the directory the link reaches keeps its plan" test -f "$LL/.bionic-state/docs/plans/w.plan.md"

# (b14) THE E5 SHAPE (A-orch-227): the target tracks keep.md; a range ADDS a file at the path where
# the main checkout holds the project's untracked plan. Merged, git would overwrite the plan.
LA="$(lk_repo "$TMP/land-kind-add")"
LAT="$(new_tree "$LA" wt/kind-add)"; mkdir -p "$LAT/.bionic/docs/plans"; echo "the branch's plan" > "$LAT/.bionic/docs/plans/w.plan.md"
lk_commit "$LAT" "a file added where the project keeps its plan" .bionic/docs/plans/w.plan.md; LAT_C="$(git -C "$LAT" rev-parse HEAD)"
expect_eq    "(b14-pre) the main checkout holds an untracked plan at that path" "plan" "$(cat "$LA/.bionic/docs/plans/w.plan.md")"
LA_SUMS="$(lb_sums "$LA")"; LA_REFS="$(refs_of "$LA")"
OUTLA="$(lb_land "$LAT")"; RCLA=$?
expect_match "(b14) a range that adds a file over the project's untracked plan is refused, naming the added path" \
  "spawn-worktree: REFUSED reason=bionic-committed path=.bionic/docs/plans/w.plan.md commit=${LAT_C:0:12} branch=wt/kind-add onto=wave/fixture fix='git -C ${LAT} rm --cached .bionic/docs/plans/w.plan.md, move .bionic/docs/plans/w.plan.md out of the tree, commit, say ready again' — *" "$(lb_first "$OUTLA")"
expect_eq    "(b14) …exit 2" "2" "$RCLA"
expect_eq    "(b14) …the untracked plan byte for byte, and every file beside it" "$LA_SUMS" "$(lb_sums "$LA")"
expect_eq    "(b14) …no ref moved" "$LA_REFS" "$(refs_of "$LA")"
expect_true  "(b14) …the tree is kept" test -d "$LAT"
# THE REMEDY THE LINE NAMES, followed (A-orch-231, A-orch-238): the added path alone out of the index,
# the file moved out of the tree (kept, not lost), a commit, the suites run (a green stamp), land again.
# The project's keep.md stays tracked and its plan untouched.
git -C "$LAT" rm --cached --quiet .bionic/docs/plans/w.plan.md
mv "$LAT/.bionic/docs/plans/w.plan.md" "$TMP/kind-add-moved.md"
git -C "$LAT" commit --quiet -m "the added plan out of the index"
green_stamp "$LAT"
expect_match "(b14r) following the line's own remedy, the tree lands" \
  "spawn-worktree: LANDED branch=wt/kind-add onto=wave/fixture *" "$(lb_first "$(lb_land "$LAT")")"
expect_eq    "(b14r) …keep.md is still tracked by the target" "100644" "$(git -C "$LA" ls-tree wave/fixture .bionic/keep.md | awk '{ print $1 }')"
expect_eq    "(b14r) …and intact in the checkout" "keep" "$(cat "$LA/.bionic/keep.md")"
expect_eq    "(b14r) …and the project's plan untouched" "plan" "$(cat "$LA/.bionic/docs/plans/w.plan.md")"
expect_eq    "(b14r) …and the writer's file kept where it was moved" "the branch's plan" "$(cat "$TMP/kind-add-moved.md")"
# …and in the same target a change to the tracked keep.md lands (the deletion arm is b8c's).
LAK="$(new_tree "$LA" wt/kind-add-change)"; echo "changed" > "$LAK/.bionic/keep.md"
lk_commit "$LAK" "a change to the tracked keep.md" .bionic/keep.md
expect_match "(b14b) …while a change to a path it tracks lands" \
  "spawn-worktree: LANDED branch=wt/kind-add-change onto=wave/fixture *" "$(lb_land "$LAK")"
expect_eq    "(b14b) …and the untracked plan is untouched" "plan" "$(cat "$LA/.bionic/docs/plans/w.plan.md")"

# (b15) A TARGET THAT STOPPED TRACKING .bionic after the tree branched (A-orch-227 P2-2, a known
# limit): the tree's tracked files are adds against the target, no commit of the range made them,
# and the line names the tree's head.
LP="$(lk_repo "$TMP/land-kind-stopped")"
LPT="$(new_tree "$LP" wt/kind-stopped)"; green_stamp "$LPT"; LPT_H="$(git -C "$LPT" rev-parse HEAD)"
git -C "$LP" rm -r --quiet --cached .bionic/keep.md .bionic/also.md && git -C "$LP" commit --quiet -m "the target stops tracking .bionic"
expect_match "(b15) a tree branched before its target stopped tracking .bionic is refused, naming the tree's head" \
  "spawn-worktree: REFUSED reason=bionic-committed path=.bionic/also.md commit=${LPT_H:0:12} branch=wt/kind-stopped onto=wave/fixture fix='git -C ${LPT} merge wave/fixture, say ready again' — *" \
  "$(lb_first "$(lb_land "$LPT")")"

# (b11) THE STAND-DOWN PATH reaches the same verdicts: b6's range refused, b8's landed.
LS="$(lk_repo "$TMP/land-kind-standdown")"; LS_SID="land-kind-session-01"
bind_plan "$LS" "$LS_SID" wave/fixture >/dev/null
LST="$(lk_replace "$LS" wt/kind-sd-link link)"; LST_C="$(git -C "$LST" rev-parse HEAD)"
LS_SUMS="$(lb_sums "$LS")"; LS_REFS="$(refs_of "$LS")"
OUTLS="$(lb_land "$LST")"; RCLS=$?
expect_match "(b11) the stand-down path refuses a link in place of the tracked directory on the same line" \
  "spawn-worktree: REFUSED reason=bionic-committed path=.bionic commit=${LST_C:0:12} branch=wt/kind-sd-link onto=wave/fixture *" "$(lb_first "$OUTLS")"
expect_eq    "(b11) …exit 2" "2" "$RCLS"
expect_false "(b11) …the project's .bionic is not a link" test -L "$LS/.bionic"
expect_eq    "(b11) …its files byte for byte" "$LS_SUMS" "$(lb_sums "$LS")"
expect_eq    "(b11) …no ref moved" "$LS_REFS" "$(refs_of "$LS")"
expect_true  "(b11) …the tree is kept" test -d "$LST"
LSC="$(new_tree "$LS" wt/kind-sd-change)"; echo "changed through the stand-down" > "$LSC/.bionic/keep.md"
lk_commit "$LSC" "a change under the tracked .bionic" .bionic/keep.md
expect_match "(b11b) …and lands a change under the tracked directory" \
  "spawn-worktree: LANDED branch=wt/kind-sd-change onto=wave/fixture *" "$(lb_land "$LSC")"
expect_eq    "(b11b) …the change is in the target checkout" "changed through the stand-down" "$(cat "$LS/.bionic/keep.md")"

# (b12) A TARGET WITH NOTHING AT .bionic refuses a regular file there, as it refuses the link (b1).
LN0="$(lb_repo "$TMP/land-kind-absent")"
LN0T="$(new_tree "$LN0" wt/kind-absent-file)"; echo "a file" > "$LN0T/.bionic"
lk_commit "$LN0T" "a regular file at .bionic" .bionic; LN0T_C="$(git -C "$LN0T" rev-parse HEAD)"
LN0_SUMS="$(lb_sums "$LN0")"
expect_match "(b12) a target with nothing at .bionic refuses a range that puts a regular file there" \
  "spawn-worktree: REFUSED reason=bionic-committed path=.bionic commit=${LN0T_C:0:12} branch=wt/kind-absent-file onto=wave/fixture *" \
  "$(lb_first "$(lb_land "$LN0T")")"
expect_eq    "(b12) …the project's .bionic files byte for byte" "$LN0_SUMS" "$(lb_sums "$LN0")"

# (b13) THE MUTANT: the kind test cut out (stubbed to answer "no change"), b6's range is merged and
# the loss comes back, so the kind test is what refuses it. (The line after the merge is the
# removal's, as in b10: the tree tracks the link land drops.)
expect_true  "(b13-pre) the library defines the kind test" declare -F _wt_bionic_kind_changed
LM="$(lk_repo "$TMP/land-kind-mutant")"; LMT="$(lk_replace "$LM" wt/kind-mutant link)"
expect_false "(b13-pre) …and the project's .bionic is a directory, not a link" test -L "$LM/.bionic"
expect_true  "(b13-pre) …holding its plan" test -f "$LM/.bionic/docs/plans/w.plan.md"
expect_match "(b13) with the kind test cut out, a link in place of the tracked directory is merged" \
  "spawn-worktree: * merge*=*" \
  "$( _wt_bionic_kind_changed() { return 1; }; lb_land "$LMT" 2>/dev/null | sed -n 1p )"
expect_true  "(b13) …and the project's .bionic is a link: the loss b6 refuses" test -L "$LM/.bionic"

# THE GUARD READS GIT, NEVER QUOTED TEXT (wave-27 T86; review pass 71). The guard read one spelling
# (`:(literal).bionic`, `ls-tree -- .bionic`) and filtered `--name-only` lines with a pattern. On a
# case-insensitive disk a tree that committed create's link as `.BIONIC` landed and the project's
# `.bionic` became a link to itself; and a name git C-quotes (`"`, `\`, a control character) never
# matched the pattern, so a range adding only such a name under `.bionic` overwrote the project's
# untracked file there. Now every name is read from git's NUL-separated streams, and a root entry
# IS `.bionic` when its name case-folds to `.bionic`, on every disk: `.BIONIC`, `.Bionic` and
# `.bionic` are one path to the guard. `path=` carries the range's spelling, C-quoted as git
# prints it when the name holds `"`, `\` or a control character, so the line stays one line.
#
# FIXTURE FIDELITY. The spellings are made the way pass 71 made them: create's link renamed and
# added with -f, and an index entry under a second spelling written by `update-index` (`git add` on
# a case-insensitive disk folds a new path into the directory's existing spelling). Each file is
# written at the range's spelling, so the tree is clean on either kind of disk. The refusals hold
# on every disk, since the fold is the guard's own; what the old code did to the project (the loss)
# is this disk's, and the red log says which disk that was.
#
# ANTI-VACUITY. A target tracking `.BIONIC/keep.md` lands a change to it (c6a) beside the refusal of
# an add under the other spelling (c6b); the git oracle prints the quoted names (c7-pre) before any
# row reads them; the two mutants (c11, c12) land the ranges their rows refuse.
cs_stage() {  # <tree> <path, in the range's spelling> <content> — writes it there and indexes exactly that name
  local t="$1" p="$2" b
  case "$p" in */*) mkdir -p "$t/${p%/*}" ;; esac
  printf '%s\n' "$3" > "$t/$p"
  b="$(git -C "$t" hash-object -w -- "$t/$p")" && git -C "$t" update-index --add --cacheinfo "100644,${b},${p}"
  git -C "$t" update-index -q --refresh >/dev/null 2>&1; :
}
cs_link_as() {  # <repo> <branch> <spelling> [rm] -> a tree committing create's link under <spelling>; rm: the tracked .bionic removed first
  local r="$1" t; t="$(new_tree "$r" "$2")"; [ -n "$t" ] || return 1
  if [ "${4:-}" = rm ]; then git -C "$t" rm -r --quiet .bionic && rm -rf "$t/.bionic"; fi
  ln -s "${r}/.bionic" "$t/.bionic-moving" && mv "$t/.bionic-moving" "$t/$3"
  git -C "$t" add -f -- "$3" && git -C "$t" commit --quiet -m "$2 the link, as $3"
  green_stamp "$t"; printf '%s' "$t"
}
cs_roots() { git -C "$1" ls-tree --name-only "$2" | grep -i '^\.bionic$' | tr '\n' ' '; }  # <repo> <rev> -> its root entries folding to .bionic
cs_fix() { printf "fix='git -C %s %s, commit, say ready again' — " "$1" "$2"; }  # <tree> <remedy> -> the line's fix field

# (c1) NOTHING TRACKED AT .bionic; THE LINK COMMITTED AS .BIONIC (pass 71's G2a: the W2 loss through a second spelling).
CA="$(lb_repo "$TMP/land-case-link")"
CAT="$(cs_link_as "$CA" wt/case-link .BIONIC)"; CAT_C="$(git -C "$CAT" rev-parse HEAD)"
expect_eq   "(c1-pre) the tree's head holds the link at .BIONIC and nothing at .bionic" ".BIONIC " "$(cs_roots "$CAT" HEAD)"
expect_eq   "(c1-pre) …a link" "120000" "$(git -C "$CAT" ls-tree HEAD .BIONIC | awk '{ print $1 }')"
CA_SUMS="$(lb_sums "$CA")"; CA_REFS="$(refs_of "$CA")"; CA_STAMPS="$(cat "$(stamp_file "$CAT")")"
OUTCA="$(lb_land "$CAT")"; RCCA=$?
expect_match "(c1) a range that commits the link as .BIONIC is refused, naming the range's spelling" \
  "spawn-worktree: REFUSED reason=bionic-committed path=.BIONIC commit=${CAT_C:0:12} branch=wt/case-link onto=wave/fixture $(cs_fix "$CAT" "rm -r --cached .BIONIC, move .BIONIC out of the tree")*" "$(lb_first "$OUTCA")"
expect_eq    "(c1) …exit 2" "2" "$RCCA"
expect_true  "(c1) the project's .bionic is still a directory" test -d "$CA/.bionic"
expect_false "(c1) …and not a link" test -L "$CA/.bionic"
expect_eq    "(c1) …its files byte for byte" "$CA_SUMS" "$(lb_sums "$CA")"
expect_eq    "(c1) no ref moved" "$CA_REFS" "$(refs_of "$CA")"
expect_true  "(c1) the tree is kept" test -d "$CAT"
expect_eq    "(c1) …and its stamps" "$CA_STAMPS" "$(cat "$(stamp_file "$CAT")")"

# (c2) .bionic/keep.md TRACKED; THE RANGE REMOVES IT AND COMMITS THE LINK AS .BIONIC: a change of kind.
CK="$(lk_repo "$TMP/land-case-kind")"
CKT="$(cs_link_as "$CK" wt/case-kind .BIONIC rm)"; CKT_C="$(git -C "$CKT" rev-parse HEAD)"
expect_eq   "(c2-pre) the tree's head holds the link at .BIONIC alone" ".BIONIC " "$(cs_roots "$CKT" HEAD)"
CK_SUMS="$(lb_sums "$CK")"; CK_REFS="$(refs_of "$CK")"; CK_STAMPS="$(cat "$(stamp_file "$CKT")")"
OUTCK="$(lb_land "$CKT")"; RCCK=$?
expect_match "(c2) a range that makes the tracked directory a link at .BIONIC is refused as a change of kind" \
  "spawn-worktree: REFUSED reason=bionic-committed path=.BIONIC commit=${CKT_C:0:12} branch=wt/case-kind onto=wave/fixture $(cs_fix "$CKT" "rm -r --cached .BIONIC, move .BIONIC out of the tree")*" "$(lb_first "$OUTCK")"
expect_eq    "(c2) …exit 2" "2" "$RCCK"
expect_false "(c2) the project's .bionic is not a link" test -L "$CK/.bionic"
expect_eq    "(c2) …its files byte for byte" "$CK_SUMS" "$(lb_sums "$CK")"
expect_eq    "(c2) no ref moved" "$CK_REFS" "$(refs_of "$CK")"
expect_true  "(c2) the tree is kept" test -d "$CKT"
expect_eq    "(c2) …and its stamps" "$CK_STAMPS" "$(cat "$(stamp_file "$CKT")")"

# (c3) A REGULAR FILE AT .Bionic, nothing tracked.
CF="$(lb_repo "$TMP/land-case-file")"
CFT="$(new_tree "$CF" wt/case-file)"; echo "a file" > "$CFT/.Bionic"
lk_commit "$CFT" "a regular file at .Bionic" .Bionic; CFT_C="$(git -C "$CFT" rev-parse HEAD)"
expect_eq   "(c3-pre) the tree's head holds a file at .Bionic" "100644" "$(git -C "$CFT" ls-tree HEAD .Bionic | awk '{ print $1 }')"
CF_SUMS="$(lb_sums "$CF")"; CF_REFS="$(refs_of "$CF")"
OUTCF="$(lb_land "$CFT")"; RCCF=$?
expect_match "(c3) a range that puts a regular file at .Bionic is refused, naming .Bionic" \
  "spawn-worktree: REFUSED reason=bionic-committed path=.Bionic commit=${CFT_C:0:12} branch=wt/case-file onto=wave/fixture $(cs_fix "$CFT" "rm -r --cached .Bionic, move .Bionic out of the tree")*" "$(lb_first "$OUTCF")"
expect_eq    "(c3) …exit 2" "2" "$RCCF"
expect_eq    "(c3) …the project's .bionic files byte for byte" "$CF_SUMS" "$(lb_sums "$CF")"
expect_eq    "(c3) …no ref moved" "$CF_REFS" "$(refs_of "$CF")"
expect_true  "(c3) …the tree is kept" test -d "$CFT"

# (c4) A DIRECTORY WITH FILES AT .Bionic, nothing tracked: the first added path, the whole entry out.
CD="$(lb_repo "$TMP/land-case-dir")"
CDT="$(new_tree "$CD" wt/case-dir)"; mkdir -p "$CDT/.Bionic/docs"; echo "the writer's" > "$CDT/.Bionic/docs/x.md"
lk_commit "$CDT" "a directory at .Bionic" .Bionic/docs/x.md; CDT_C="$(git -C "$CDT" rev-parse HEAD)"
expect_eq   "(c4-pre) the tree's head holds a directory at .Bionic" "040000" "$(git -C "$CDT" ls-tree HEAD .Bionic | awk '{ print $1 }')"
CD_SUMS="$(lb_sums "$CD")"; CD_REFS="$(refs_of "$CD")"
OUTCD="$(lb_land "$CDT")"; RCCD=$?
expect_match "(c4) a range that adds a directory at .Bionic is refused, naming its first path and the entry's remedy" \
  "spawn-worktree: REFUSED reason=bionic-committed path=.Bionic/docs/x.md commit=${CDT_C:0:12} branch=wt/case-dir onto=wave/fixture $(cs_fix "$CDT" "rm -r --cached .Bionic, move .Bionic out of the tree")*" "$(lb_first "$OUTCD")"
expect_eq    "(c4) …exit 2" "2" "$RCCD"
expect_eq    "(c4) …the project's .bionic files byte for byte" "$CD_SUMS" "$(lb_sums "$CD")"
expect_eq    "(c4) …no ref moved" "$CD_REFS" "$(refs_of "$CD")"
expect_true  "(c4) …the tree is kept" test -d "$CDT"

# (c5) .bionic/keep.md TRACKED; THE RANGE ADDS .BIONIC/x.md (pass 71's G2b) over the project's untracked x.md.
CU="$(lk_repo "$TMP/land-case-add")"; echo "the project's own" > "$CU/.bionic/x.md"
CUT="$(new_tree "$CU" wt/case-add)"; cs_stage "$CUT" .BIONIC/x.md "the writer's"
lk_commit "$CUT" "x.md added as .BIONIC/x.md"; CUT_C="$(git -C "$CUT" rev-parse HEAD)"
expect_eq   "(c5-pre) the tree's head holds both spellings at the root" ".BIONIC .bionic " "$(cs_roots "$CUT" HEAD)"
expect_eq   "(c5-pre) …and the tree is clean" "" "$(git -C "$CUT" status --porcelain)"
CU_SUMS="$(lb_sums "$CU")"; CU_REFS="$(refs_of "$CU")"
OUTCU="$(lb_land "$CUT")"; RCCU=$?
expect_match "(c5) a range that adds .BIONIC/x.md under the tracked .bionic is refused, naming the added path" \
  "spawn-worktree: REFUSED reason=bionic-committed path=.BIONIC/x.md commit=${CUT_C:0:12} branch=wt/case-add onto=wave/fixture $(cs_fix "$CUT" "rm --cached .BIONIC/x.md, move .BIONIC/x.md out of the tree")*" "$(lb_first "$OUTCU")"
expect_eq    "(c5) …exit 2" "2" "$RCCU"
expect_eq    "(c5) …the project's untracked x.md byte for byte, and every file beside it" "$CU_SUMS" "$(lb_sums "$CU")"
expect_eq    "(c5) …no ref moved" "$CU_REFS" "$(refs_of "$CU")"
expect_true  "(c5) …the tree is kept" test -d "$CUT"

# (c6) A TARGET TRACKING .BIONIC/keep.md (made on a case-sensitive disk, or by hand) tracks .bionic's directory.
CV="$(lb_repo "$TMP/land-case-upper")"; cs_stage "$CV" .BIONIC/keep.md "keep"
git -C "$CV" commit --quiet -m "the target tracks .BIONIC/keep.md"
expect_eq   "(c6-pre) the target tracks .BIONIC as a directory, and nothing spelled .bionic" ".BIONIC " "$(cs_roots "$CV" wave/fixture)"
CVC="$(new_tree "$CV" wt/case-upper-change)"; echo "changed on the branch" > "$CVC/.BIONIC/keep.md"
lk_commit "$CVC" "a change to the tracked .BIONIC/keep.md" .BIONIC/keep.md
expect_match "(c6a) a range that changes the tracked .BIONIC/keep.md lands" \
  "spawn-worktree: LANDED branch=wt/case-upper-change onto=wave/fixture *" "$(lb_first "$(lb_land "$CVC")")"
expect_eq    "(c6a) …the change is in the target checkout" "changed on the branch" "$(cat "$CV/.BIONIC/keep.md")"
expect_true  "(c6a) …whose .bionic still holds its plan" test -f "$CV/.bionic/docs/plans/w.plan.md"
CVA="$(new_tree "$CV" wt/case-upper-add)"; cs_stage "$CVA" .bionic/new.md "the writer's"
lk_commit "$CVA" "new.md added as .bionic/new.md"; CVA_C="$(git -C "$CVA" rev-parse HEAD)"
expect_eq   "(c6b-pre) the tree's head holds both spellings at the root" ".BIONIC .bionic " "$(cs_roots "$CVA" HEAD)"
CV_SUMS="$(lb_sums "$CV")"; CV_REFS="$(refs_of "$CV")"
expect_match "(c6b) …and refuses a range that adds .bionic/new.md: an add under the folded path, the path alone out" \
  "spawn-worktree: REFUSED reason=bionic-committed path=.bionic/new.md commit=${CVA_C:0:12} branch=wt/case-upper-add onto=wave/fixture $(cs_fix "$CVA" "rm --cached .bionic/new.md, move .bionic/new.md out of the tree")*" \
  "$(lb_first "$(lb_land "$CVA")")"
expect_eq    "(c6b) …the project's .bionic files byte for byte" "$CV_SUMS" "$(lb_sums "$CV")"
expect_eq    "(c6b) …no ref moved" "$CV_REFS" "$(refs_of "$CV")"

# (c13) A FILE AT .BIONIC BESIDE THE TARGET'S TRACKED LINK at .bionic: not a directory, so not an add
# under the entry; refused as a change of kind, in its spelling. The entry is written to the index
# alone (no disk holds both spellings at once on a case-insensitive disk) and marked unchanged, so
# the tree reads clean.
CB="$(ll_repo "$TMP/land-case-beside")"
CBT="$(new_tree "$CB" wt/case-beside)"
CB_B="$(printf 'a file\n' | git -C "$CBT" hash-object -w --stdin)"
git -C "$CBT" update-index --add --cacheinfo "100644,${CB_B},.BIONIC" && git -C "$CBT" update-index --assume-unchanged .BIONIC
git -C "$CBT" commit --quiet -m "a file at .BIONIC beside the link"; green_stamp "$CBT"; CBT_C="$(git -C "$CBT" rev-parse HEAD)"
expect_eq   "(c13-pre) the tree's head holds both spellings at the root" ".BIONIC .bionic " "$(cs_roots "$CBT" HEAD)"
expect_eq   "(c13-pre) …and the tree reads clean" "" "$(git -C "$CBT" status --porcelain)"
CB_REFS="$(refs_of "$CB")"
expect_match "(c13) a file at .BIONIC beside the tracked link is refused as a change of kind, in its spelling" \
  "spawn-worktree: REFUSED reason=bionic-committed path=.BIONIC commit=${CBT_C:0:12} branch=wt/case-beside onto=wave/fixture $(cs_fix "$CBT" "rm -r --cached .BIONIC, move .BIONIC out of the tree")*" \
  "$(lb_first "$(lb_land "$CBT")")"
expect_eq    "(c13) …no ref moved" "$CB_REFS" "$(refs_of "$CB")"
expect_true  "(c13) …the target's .bionic is still its link" test -L "$CB/.bionic"

# (c7) NAMES GIT C-QUOTES, added under the tracked .bionic, each over the project's untracked file
# of that name (pass 71's G1b). The quoted form is git's own (c7-pre, the oracle).
CQ_N1='.bionic/"quoted".md'; CQ_N2='.bionic/back\slash.md'; CQ_N3=$'.bionic/tab\tname.md'
CQ_Q1='".bionic/\"quoted\".md"'; CQ_Q2='".bionic/back\\slash.md"'; CQ_Q3='".bionic/tab\tname.md"'
CQ_S1="'.bionic/\"quoted\".md'"  # the first name quoted for the shell, as the remedy prints it (wave-28 T39)
cq_own() { local f; for f in "$CQ_N1" "$CQ_N2" "$CQ_N3"; do echo "the project's own" > "$1/$f"; done; }  # <repo>
cq_tree() {  # <repo> <branch> <name>... -> a tree whose one commit adds each name under .bionic
  local r="$1" b="$2" t f; shift 2; t="$(new_tree "$r" "$b")"; [ -n "$t" ] || return 1
  mkdir -p "$t/.bionic"; for f in "$@"; do echo "the writer's" > "$t/$f"; done
  git -C "$t" add -f -- "$@" && git -C "$t" commit --quiet -m "$b quoted names"
  green_stamp "$t"; printf '%s' "$t"
}
CQ="$(lk_repo "$TMP/land-quoted")"; cq_own "$CQ"
CQT="$(cq_tree "$CQ" wt/quoted "$CQ_N1" "$CQ_N2" "$CQ_N3")"; CQT_C="$(git -C "$CQT" rev-parse HEAD)"
expect_eq   "(c7-pre) git prints the three added names C-quoted, so" "${CQ_Q1}|${CQ_Q2}|${CQ_Q3}|" \
  "$(git -C "$CQ" -c core.quotePath=true diff --name-only --diff-filter=A wave/fixture wt/quoted -- .bionic | tr '\n' '|')"
CQ_SUMS="$(lb_sums "$CQ")"; CQ_REFS="$(refs_of "$CQ")"
expect_true "(c7-pre) the project holds its own file at each of the three paths" \
  test -f "$CQ/$CQ_N1" -a -f "$CQ/$CQ_N2" -a -f "$CQ/$CQ_N3"
OUTCQ="$(lb_land "$CQT")"; RCCQ=$?
expect_match "(c7) a range adding three names git quotes under the tracked .bionic is refused" \
  "spawn-worktree: REFUSED reason=bionic-committed path=*" "$(lb_first "$OUTCQ")"
expect_contains "(c7) …naming the first added path as git quotes it, and in the remedy quoted for the shell (T39)" \
  "path=${CQ_Q1} commit=${CQT_C:0:12} branch=wt/quoted onto=wave/fixture $(cs_fix "$CQT" "rm --cached ${CQ_S1}, move ${CQ_S1} out of the tree")" "$OUTCQ"
expect_eq    "(c7) …exit 2" "2" "$RCCQ"
expect_eq    "(c7) …on one line" "1" "$(printf '%s\n' "$OUTCQ" | awk 'END { print NR }')"
expect_eq    "(c7) …the project's three untracked files byte for byte, and every file beside them" "$CQ_SUMS" "$(lb_sums "$CQ")"
expect_eq    "(c7) …no ref moved" "$CQ_REFS" "$(refs_of "$CQ")"
expect_true  "(c7) …the tree is kept" test -d "$CQT"
CQ2="$(lk_repo "$TMP/land-quoted-back")"; cq_own "$CQ2"
CQB="$(cq_tree "$CQ2" wt/quoted-back "$CQ_N2")"; CQB_C="$(git -C "$CQB" rev-parse HEAD)"; CQ2_SUMS="$(lb_sums "$CQ2")"
expect_contains "(c7b) a range adding only the backslash name is refused, naming it as git quotes it" \
  "REFUSED reason=bionic-committed path=${CQ_Q2} commit=${CQB_C:0:12} branch=wt/quoted-back " "$(lb_land "$CQB")"
expect_eq    "(c7b) …the project's .bionic files byte for byte" "$CQ2_SUMS" "$(lb_sums "$CQ2")"
CQ3="$(lk_repo "$TMP/land-quoted-tab")"; cq_own "$CQ3"
CQC="$(cq_tree "$CQ3" wt/quoted-tab "$CQ_N3")"; CQC_C="$(git -C "$CQC" rev-parse HEAD)"; CQ3_SUMS="$(lb_sums "$CQ3")"
OUTCQC="$(lb_land "$CQC")"
expect_contains "(c7c) a range adding only the name holding a tab is refused, naming it as git quotes it" \
  "REFUSED reason=bionic-committed path=${CQ_Q3} commit=${CQC_C:0:12} branch=wt/quoted-tab " "$OUTCQC"
expect_eq    "(c7c) …on one line" "1" "$(printf '%s\n' "$OUTCQC" | awk 'END { print NR }')"
expect_eq    "(c7c) …the project's .bionic files byte for byte" "$CQ3_SUMS" "$(lb_sums "$CQ3")"

# (c8) THE SAME ADDS IN A PROJECT TRACKING NOTHING AT .bionic (pass 71's G1a; the rule before T84).
CN="$(lb_repo "$TMP/land-quoted-none")"; cq_own "$CN"
CNT="$(cq_tree "$CN" wt/quoted-none "$CQ_N1" "$CQ_N2" "$CQ_N3")"; CNT_C="$(git -C "$CNT" rev-parse HEAD)"
CN_SUMS="$(lb_sums "$CN")"; CN_REFS="$(refs_of "$CN")"
OUTCN="$(lb_land "$CNT")"; RCCN=$?
expect_contains "(c8) a project tracking nothing at .bionic refuses the same adds, the whole entry out" \
  "REFUSED reason=bionic-committed path=${CQ_Q1} commit=${CNT_C:0:12} branch=wt/quoted-none onto=wave/fixture $(cs_fix "$CNT" "rm -r --cached .bionic, move .bionic out of the tree")" "$OUTCN"
expect_eq    "(c8) …exit 2" "2" "$RCCN"
expect_eq    "(c8) …the project's untracked files byte for byte" "$CN_SUMS" "$(lb_sums "$CN")"
expect_eq    "(c8) …no ref moved" "$CN_REFS" "$(refs_of "$CN")"

# (c9, c10) THE STAND-DOWN PATH reaches the same verdicts: c1's link as .BIONIC, c7's quoted add.
CS="$(lk_repo "$TMP/land-case-standdown")"; CS_SID="land-case-session-01"
bind_plan "$CS" "$CS_SID" wave/fixture >/dev/null
CST="$(cs_link_as "$CS" wt/case-sd-link .BIONIC rm)"; CST_C="$(git -C "$CST" rev-parse HEAD)"
CS_SUMS="$(lb_sums "$CS")"; CS_REFS="$(refs_of "$CS")"
OUTCS="$(lb_land "$CST")"; RCCS=$?
expect_match "(c9) the stand-down path refuses the link committed as .BIONIC on the same line" \
  "spawn-worktree: REFUSED reason=bionic-committed path=.BIONIC commit=${CST_C:0:12} branch=wt/case-sd-link onto=wave/fixture *" "$(lb_first "$OUTCS")"
expect_eq    "(c9) …exit 2" "2" "$RCCS"
expect_false "(c9) …the project's .bionic is not a link" test -L "$CS/.bionic"
expect_eq    "(c9) …its files byte for byte" "$CS_SUMS" "$(lb_sums "$CS")"
expect_eq    "(c9) …no ref moved" "$CS_REFS" "$(refs_of "$CS")"
CR="$(lk_repo "$TMP/land-quoted-standdown")"; CR_SID="land-quoted-session-01"
bind_plan "$CR" "$CR_SID" wave/fixture >/dev/null; cq_own "$CR"
CSQ="$(cq_tree "$CR" wt/case-sd-quoted "$CQ_N1")"; CSQ_C="$(git -C "$CSQ" rev-parse HEAD)"
CR_SUMS="$(lb_sums "$CR")"; CR_REFS="$(refs_of "$CR")"
OUTCSQ="$(lb_land "$CSQ")"; RCCSQ=$?
expect_contains "(c10) …and the quoted add, naming it as git quotes it" \
  "REFUSED reason=bionic-committed path=${CQ_Q1} commit=${CSQ_C:0:12} branch=wt/case-sd-quoted onto=wave/fixture " "$OUTCSQ"
expect_eq    "(c10) …exit 2" "2" "$RCCSQ"
expect_eq    "(c10) …the project's untracked files byte for byte" "$CR_SUMS" "$(lb_sums "$CR")"
expect_eq    "(c10) …no ref moved" "$CR_REFS" "$(refs_of "$CR")"

# (c14) THE TARGET'S TRACKED LINK RENAMED TO .BIONIC: link to link, the kind kept, the spelling not; an
# add at the folded entry (A-orch-243), refused in the range's spelling.
CL="$(ll_repo "$TMP/land-case-rename")"
CLT="$(new_tree "$CL" wt/case-rename)"; mv "$CLT/.bionic" "$CLT/.bionic-moving" && mv "$CLT/.bionic-moving" "$CLT/.BIONIC"
git -C "$CLT" rm --cached --quiet .bionic && lk_commit "$CLT" "the tracked link renamed to .BIONIC" .BIONIC; CLT_C="$(git -C "$CLT" rev-parse HEAD)"
expect_eq   "(c14-pre) the tree's head holds the link at .BIONIC alone" ".BIONIC " "$(cs_roots "$CLT" HEAD)"
expect_eq   "(c14-pre) …a link, as the target's" "120000 120000" "$(git -C "$CLT" ls-tree HEAD .BIONIC | awk '{ print $1 }') $(lk_kind "$CL" wave/fixture)"
CL_REFS="$(refs_of "$CL")"
expect_match "(c14) a range that renames the target's tracked link to .BIONIC is refused, in its spelling" \
  "spawn-worktree: REFUSED reason=bionic-committed path=.BIONIC commit=${CLT_C:0:12} branch=wt/case-rename onto=wave/fixture $(cs_fix "$CLT" "rm -r --cached .BIONIC, move .BIONIC out of the tree")*" \
  "$(lb_first "$(lb_land "$CLT")")"
expect_eq    "(c14) …no ref moved" "$CL_REFS" "$(refs_of "$CL")"
expect_true  "(c14) …the target's .bionic is still its link" test -L "$CL/.bionic"

# (r1-r3) EVERY PRINTED FIX LANDS WHEN FOLLOWED LITERALLY (wave-27 T86; A-orch-244, pass 71's P2-1).
# The whole-path remedy left the entry in the tree, untracked; where nothing ignores it (no exclude
# line, not the record link land passes over) the next land was refused dirty-tree. The fix now also
# says to move the entry out of the tree. Each row follows the line it was given, word for word:
# the git command it names, the move it names (into $TMP, kept), a commit, and ready again (here, the hand landing).
lb_follow() {  # <tree> <refusal line> -> 0 once the line's fix is followed as printed, nothing added
  # As a shell would (wave-28 T39, D31): the fix's text is read into words by the shell itself, so a
  # path printed quoted for it reaches git and mv as one name. The first clause, up to the word that
  # ends in a comma, is the git command, run as printed (its own `git -C <tree>`); a `move <path> out
  # of the tree` clause moves that path (into $TMP, kept); a closing `commit` commits.
  local t="$1" fix w cmd=() mv="" clause=cmd
  fix="${2#*" fix='"}"; fix="${fix%%", say ready again' — "*}"
  [ "$fix" != "$2" ] || return 1
  eval "set -- $fix" || return 1
  for w in "$@"; do
    case "$clause" in
      cmd) case "$w" in *,) cmd+=("${w%,}"); clause=next ;; *) cmd+=("$w") ;; esac ;;
      next) case "$w" in move) clause=move ;; commit) clause=commit ;; *) return 1 ;; esac ;;
      move) mv="$w"; clause=out ;;
      out) case "$w" in tree,) clause=next ;; out|of|the) : ;; *) return 1 ;; esac ;;
      *) return 1 ;;
    esac
  done
  [ "${cmd[0]:-}" = git ] || return 1
  "${cmd[@]}" >/dev/null 2>&1 || return 1
  case "$clause" in
    cmd) [ "${cmd[3]:-}" = merge ] || return 1; green_stamp "$t"; return 0 ;;
    commit) : ;;
    *) return 1 ;;
  esac
  if [ -n "$mv" ]; then mv "$t/$mv" "$TMP/followed-${t##*/}" || return 1; fi
  git -C "$t" commit --quiet -m "the printed fix, followed"; green_stamp "$t"
}
# (r1) THE KIND CHANGED TO A REGULAR FILE where the target tracks a directory (pass 71's A2).
RF="$(lk_repo "$TMP/land-follow-file")"; RFT="$(lk_replace "$RF" wt/follow-file file)"
RF_LINE="$(lb_first "$(lb_land "$RFT")")"
expect_contains "(r1-pre) the range is refused, naming .bionic" "REFUSED reason=bionic-committed path=.bionic " "$RF_LINE"
expect_true  "(r1) its printed fix can be followed as printed" lb_follow "$RFT" "$RF_LINE"
expect_match "(r1) …and the tree then lands" "spawn-worktree: LANDED branch=wt/follow-file onto=wave/fixture *" \
  "$(lb_first "$(lb_land "$RFT")")"
expect_false "(r1) …the project's .bionic is not a file or a link" test -L "$RF/.bionic"
expect_eq    "(r1) …and holds its plan and record" "plan|record" "$(cat "$RF/.bionic/docs/plans/w.plan.md")|$(cat "$RF/.bionic/docs/record/r.md")"
expect_eq    "(r1) …and the writer's file is kept where the fix moved it" "a file" "$(cat "$TMP/followed-follow-file")"
# (r2) THE KNOWN LIMIT: the target stopped tracking .bionic after the tree branched (b15's shape; pass 71's F3).
# Its fix is the merge of the target (A-orch-256): taking the paths out of the tree's index too would
# have both sides delete them, which land refuses not-current.
RL="$(lk_repo "$TMP/land-follow-stopped")"; RLT="$(new_tree "$RL" wt/follow-stopped)"; green_stamp "$RLT"
git -C "$RL" rm -r --quiet --cached .bionic/keep.md .bionic/also.md && git -C "$RL" commit --quiet -m "the target stops tracking .bionic"
RL_LINE="$(lb_first "$(lb_land "$RLT")")"
expect_contains "(r2-pre) the tree is refused, naming a path the target no longer tracks, and the merge" \
  "REFUSED reason=bionic-committed path=.bionic/also.md commit=$(git -C "$RLT" rev-parse --short=12 HEAD) branch=wt/follow-stopped onto=wave/fixture fix='git -C ${RLT} merge wave/fixture, say ready again' — " "$RL_LINE"
expect_true  "(r2) its printed fix can be followed as printed" lb_follow "$RLT" "$RL_LINE"
expect_match "(r2) …and the tree then lands" "spawn-worktree: LANDED branch=wt/follow-stopped onto=wave/fixture *" \
  "$(lb_first "$(lb_land "$RLT")")"
expect_eq    "(r2) …the project's own keep.md, also.md and plan are untouched" "keep|also|plan" \
  "$(cat "$RL/.bionic/keep.md")|$(cat "$RL/.bionic/also.md")|$(cat "$RL/.bionic/docs/plans/w.plan.md")"
# (r3) THE LINK COMMITTED AS .BIONIC, nothing tracked (c1's shape).
RC="$(lb_repo "$TMP/land-follow-case")"; RCT="$(cs_link_as "$RC" wt/follow-case .BIONIC)"
RC_LINE="$(lb_first "$(lb_land "$RCT")")"
expect_contains "(r3-pre) the range is refused, naming .BIONIC" "REFUSED reason=bionic-committed path=.BIONIC " "$RC_LINE"
expect_true  "(r3) its printed fix can be followed as printed" lb_follow "$RCT" "$RC_LINE"
expect_match "(r3) …and the tree then lands" "spawn-worktree: LANDED branch=wt/follow-case onto=wave/fixture *" \
  "$(lb_first "$(lb_land "$RCT")")"
expect_true  "(r3) …the project's .bionic is a directory, not a link" test -d "$RC/.bionic" -a ! -L "$RC/.bionic"
expect_eq    "(r3) …holding its plan and record" "plan|record" "$(cat "$RC/.bionic/docs/plans/w.plan.md")|$(cat "$RC/.bionic/docs/record/r.md")"

# (s1) A SUBMODULE LINK UNDER THE TRACKED .bionic, UNDER A CONFIG THAT HIDES SUBMODULES (wave-28 T39, D31,
# AC-14.2; wave-27 critic P3-1). `diff.ignoreSubmodules=all`, which a user may set in any config, took
# a gitlink out of `git diff`'s answer, so the add test saw nothing and the range landed a gitlink at
# `.bionic/docs` over the project's untracked plan directory. The guard's difference call now carries
# `--ignore-submodules=none`: its answer is git's own, whatever the configuration. The link names a
# commit of another repository, absent here, as a real submodule's does.
SM="$(lk_repo "$TMP/land-submodule")"; git -C "$SM" config diff.ignoreSubmodules all
SMT="$(new_tree "$SM" wt/submodule)"; mkdir -p "$SMT/.bionic/docs"
git -C "$SMT" update-index --add --cacheinfo "160000,1234567890123456789012345678901234567890,.bionic/docs"
lk_commit "$SMT" "a submodule link at .bionic/docs"; SMT_C="$(git -C "$SMT" rev-parse HEAD)"
expect_eq   "(s1-pre) the tree's head holds a gitlink at .bionic/docs" "160000" "$(git -C "$SMT" ls-tree HEAD .bionic/docs | awk '{ print $1 }')"
expect_eq   "(s1-pre) …which the fixture's config hides from git diff" "" \
  "$(git -C "$SM" diff --no-renames --diff-filter=A --name-only wave/fixture wt/submodule -- .bionic)"
expect_eq   "(s1-pre) …and the tree reads clean" "" "$(git -C "$SMT" status --porcelain)"
SM_SUMS="$(lb_sums "$SM")"; SM_REFS="$(refs_of "$SM")"
OUTSM="$(lb_land "$SMT")"; RCSM=$?
expect_contains "(s1) a submodule link added under the tracked .bionic is refused under diff.ignoreSubmodules=all, naming it" \
  "spawn-worktree: REFUSED reason=bionic-committed path=.bionic/docs commit=${SMT_C:0:12} branch=wt/submodule onto=wave/fixture " "$(lb_first "$OUTSM")"
expect_eq    "(s1) …exit 2" "2" "$RCSM"
expect_eq    "(s1) …the project's .bionic files byte for byte" "$SM_SUMS" "$(lb_sums "$SM")"
expect_eq    "(s1) …no ref moved" "$SM_REFS" "$(refs_of "$SM")"
expect_true  "(s1) …the project's plan directory is still a directory" test -f "$SM/.bionic/docs/plans/w.plan.md"
# (s1) FOLLOWED (wave-28 T3, ruling A-orch-14): a submodule link names a commit of another repository,
# so the guard's commit lookup asks for the tree ENTRY (`rev-parse --verify <c>:<path>`), never the
# object. Asked for the object, it found no commit adding the link, named the range's head as a path
# the target dropped, and printed `merge wave/fixture`: a merge that changes nothing, the refusal standing.
SM_LINE="$(lb_first "$OUTSM")"
expect_contains "(s1) …its fix takes the link out of the index, never a merge" \
  "fix='git -C ${SMT} rm --cached .bionic/docs, move .bionic/docs out of the tree, commit, say ready again' — " "$SM_LINE"
expect_true  "(s1) its printed fix can be followed as printed" lb_follow "$SMT" "$SM_LINE"
expect_match "(s1) …and the guard is then satisfied: the tree lands" "spawn-worktree: LANDED branch=wt/submodule onto=wave/fixture *" \
  "$(lb_first "$(lb_land "$SMT")")"
expect_true  "(s1) …the project's plan directory is still a directory" test -f "$SM/.bionic/docs/plans/w.plan.md"
# (s1b) THE LOOKUP'S OTHER SHAPES ARE UNCHANGED: an ordinary file and a directory added under .bionic
# are named by the commit that added them, as before the lookup asked for the entry.
SF="$(lk_repo "$TMP/land-added-by")"; SFT="$(new_tree "$SF" wt/added-by)"
mkdir -p "$SFT/.bionic/sub"; echo f > "$SFT/.bionic/sub/f.md"; echo p > "$SFT/.bionic/plain.md"
lk_commit "$SFT" "a file and a directory under .bionic" .bionic/sub/f.md .bionic/plain.md; SF_C="$(git -C "$SFT" rev-parse HEAD)"
echo later > "$SFT/later.txt"; lk_commit "$SFT" "a later commit" later.txt
expect_eq "(s1b) an ordinary file is named by the commit that added it" "$SF_C" \
  "$(_wt_bionic_added_by "$SF" wave/fixture wt/added-by .bionic/plain.md)"
expect_eq "(s1b) …and a directory too" "$SF_C" "$(_wt_bionic_added_by "$SF" wave/fixture wt/added-by .bionic/sub)"

# (q1-q5) THE PRINTED FIX IS QUOTED FOR THE SHELL (wave-28 T39, D31, AC-14.3; review pass 74's P2-1). The
# per-path remedy printed the name bare or C-quoted, so a space split it, a tab or a line break reached
# git as a backslash and a letter, and a glob character un-tracked the target's own file beside it.
# Each row adds one such name under the tracked .bionic, over the project's own untracked file there,
# follows the printed fix as a shell reads it (lb_follow), and lands: the name alone left the index.
# `.bionic/k*.md` is a glob that matches the target's tracked keep.md, so the row sees a fix that
# reaches another path.
lq_row() {  # <label> <tree base> <name> <expected remedy> — one row, the name over the project's own file
  local id="$1" r t c line
  r="$(lk_repo "$TMP/land-shq-$2")"; echo "the project's own" > "$r/$3"
  t="$(cq_tree "$r" "wt/shq-$2" "$3")"; c="$(git -C "$t" rev-parse HEAD)"
  line="$(lb_first "$(lb_land "$t")")"
  expect_contains "($id) a range adding $2 under the tracked .bionic is refused, its remedy quoted for the shell" \
    "REFUSED reason=bionic-committed path=$(_wt_cquote "$3") commit=${c:0:12} branch=wt/shq-$2 onto=wave/fixture $(cs_fix "$t" "$4")" "$line"
  expect_eq    "($id) …on one line" "1" "$(printf '%s\n' "$line" | awk 'END { print NR }')"
  expect_true  "($id) …its printed fix can be followed as printed" lb_follow "$t" "$line"
  expect_match "($id) …and the tree then lands" "spawn-worktree: LANDED branch=wt/shq-$2 onto=wave/fixture *" \
    "$(lb_first "$(lb_land "$t")")"
  expect_eq    "($id) …the fix acted on that path alone: the landed branch tracks keep.md and also.md, and not the name" \
    ".bionic/also.md|.bionic/keep.md|" "$(git -C "$r" ls-tree -r --name-only "wt/shq-$2" -- .bionic | LC_ALL=C sort | tr '\n' '|')"
  expect_eq    "($id) …and so does the target, once landed" \
    ".bionic/also.md|.bionic/keep.md|" "$(git -C "$r" ls-files -- .bionic | LC_ALL=C sort | tr '\n' '|')"
  expect_eq    "($id) …and the project's own file at the name is untouched" "the project's own" "$(cat "$r/$3")"
  expect_eq    "($id) …and the writer's file is kept where the fix moved it" "the writer's" "$(cat "$TMP/followed-shq-$2")"
}
lq_row q1 space ".bionic/my notes.md" "rm --cached '.bionic/my notes.md', move '.bionic/my notes.md' out of the tree"
lq_row q2 tab $'.bionic/a\tb.md' "rm --cached \$'.bionic/a\\tb.md', move \$'.bionic/a\\tb.md' out of the tree"
lq_row q3 newline $'.bionic/new\nline.md' "rm --cached \$'.bionic/new\\nline.md', move \$'.bionic/new\\nline.md' out of the tree"
lq_row q4 glob '.bionic/k*.md' "rm --cached ':(literal).bionic/k*.md', move '.bionic/k*.md' out of the tree"
lq_row q5 quote ".bionic/it's.md" "rm --cached \$'.bionic/it\\'s.md', move \$'.bionic/it\\'s.md' out of the tree"

# (q6) THE TREE'S OWN PATH is a path the fix prints too: a project under a directory holding a space.
QT="$(lk_repo "$TMP/land shq root")"; QTT="$(lk_replace "$QT" wt/shq-root file)"
QT_LINE="$(lb_first "$(lb_land "$QTT")")"
expect_contains "(q6) a tree whose path holds a space is named in the fix quoted for the shell" \
  "fix='git -C '${QTT}' rm -r --cached .bionic, move .bionic out of the tree, commit, say ready again' — " "$QT_LINE"
expect_true  "(q6) …its printed fix can be followed as printed" lb_follow "$QTT" "$QT_LINE"
expect_match "(q6) …and the tree then lands" "spawn-worktree: LANDED branch=wt/shq-root onto=wave/fixture *" \
  "$(lb_first "$(lb_land "$QTT")")"

# (q7, s2) THE MUTANTS. The quoting cut out (the name printed bare): q1's fix splits the name and cannot
# be followed. The flag cut out of the difference call: s1's submodule link is merged.
expect_true  "(q7-pre) the library defines the shell quoting" declare -F _wt_shquote
QM="$(lk_repo "$TMP/land-shq-mutant")"; QMT="$(cq_tree "$QM" wt/shq-mutant ".bionic/my notes.md")"
QM_LINE="$( _wt_shquote() { printf '%s' "$1"; }; lb_land "$QMT" 2>/dev/null | sed -n 1p )"
expect_contains "(q7-pre) …the mutant still refuses, printing the name bare" "rm --cached .bionic/my notes.md, " "$QM_LINE"
expect_false "(q7) with the quoting cut out, the printed fix cannot be followed" lb_follow "$QMT" "$QM_LINE"
SN="$(lk_repo "$TMP/land-submodule-mutant")"; git -C "$SN" config diff.ignoreSubmodules all
SNT="$(new_tree "$SN" wt/submodule-mutant)"; mkdir -p "$SNT/.bionic/docs"
git -C "$SNT" update-index --add --cacheinfo "160000,1234567890123456789012345678901234567890,.bionic/docs"
lk_commit "$SNT" "a submodule link at .bionic/docs"
expect_match "(s2) with the flag cut out of the difference call, the submodule link is merged" "spawn-worktree: * merge*=*" \
  "$( _wt_bionic_adds() { git -C "$1" diff --no-renames --diff-filter=A --name-only -z "$2" "$3" 2>/dev/null; }
      lb_land "$SNT" 2>/dev/null | sed -n 1p )"

# (c11, c12) THE MUTANTS. The fold cut out (a root entry is `.bionic` only byte for byte): c1's range
# is merged. The NUL stream cut out (the adds read as git's text lines): c7's quoted add is merged.
expect_true  "(c11-pre) the library defines the fold and the add stream" declare -F _wt_bionic_named _wt_bionic_adds
CM="$(lb_repo "$TMP/land-case-mutant")"; CMT="$(cs_link_as "$CM" wt/case-mutant .BIONIC)"
expect_match "(c11) with the fold cut out, the link committed as .BIONIC is merged" "spawn-worktree: * merge*=*" \
  "$( _wt_bionic_named() { [ "$1" = .bionic ]; }; lb_land "$CMT" 2>/dev/null | sed -n 1p )"
CZ="$(lk_repo "$TMP/land-quoted-mutant")"; cq_own "$CZ"; CZT="$(cq_tree "$CZ" wt/quoted-mutant "$CQ_N1")"
expect_match "(c12) with the NUL stream cut out, the quoted add is merged" "spawn-worktree: * merge*=*" \
  "$( _wt_bionic_adds() { git -C "$1" diff --no-renames --diff-filter=A --name-only "$2" "$3" | tr '\n' '\0'; }
      lb_land "$CZT" 2>/dev/null | sed -n 1p )"
expect_eq    "(c12) …and the project's untracked file is overwritten: the loss c7 refuses" "the writer's" "$(cat "$CZ/$CQ_N1")"

finish
