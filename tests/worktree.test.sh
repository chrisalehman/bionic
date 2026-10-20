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
. "$(dirname "$0")/lib/wait.sh"
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
  wait_ticks 100 0.05 runner_shows_run_sh
}
holder_gone() { ! kill -0 "${1:-}" 2>/dev/null; }
runner_shows_run_sh() {
  case "$(ps -o command= -p "$RUNNER_PID" 2>/dev/null)" in *tests/run.sh*) return 0 ;; esac
  return 1
}
stop_runner() {
  [ -n "$RUNNER_PID" ] || return 0
  kill "$RUNNER_PID" 2>/dev/null; wait "$RUNNER_PID" 2>/dev/null
  RUNNER_PID=""
}
make_runner() {  # <dir> -> <dir>/tests/run.sh
  mkdir -p "$1/tests"
  # the stand-in runner idles until the arm kills it (`sleep 1` is its heartbeat); no wait can observe a process that is meant to stay alive
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
  wait_ticks 100 0.05 mention_shows_run_sh
}
mention_shows_run_sh() {
  case "$(ps -o command= -p "$MENTION_PID" 2>/dev/null)" in *tests/run.sh*) return 0 ;; esac
  return 1
}
stop_mention() {
  [ -n "$MENTION_PID" ] || return 0
  kill "$MENTION_PID" 2>/dev/null; wait "$MENTION_PID" 2>/dev/null
  MENTION_PID=""
}
trap 'stop_runner; stop_mention; rm -rf "$TMP"' EXIT
BT10="$(new_tree "$S" mention-arm)"
# the `sleep 1` in each mention body below keeps the shell alive until stop_mention kills it; no wait can observe that
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
  runner_matches() { [[ "$(ps -o command= -p "$RUNNER_PID" 2>/dev/null)" == $g ]]; }
  wait_ticks 100 0.05 runner_matches
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
# the `sleep 30` below is a process named as the runner that stays alive until stop_runner; no wait can observe it
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
  # the holder must stay alive for the whole arm and is killed by it; no wait can observe a process meant to outlive its reader
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
wait_ticks 100 0.05 holder_gone "$GB_HOLD"
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
# The glob is expanded on every poll, inside the function: handed to wait_ticks as an argument it would be
# expanded once, before the request exists.
gb_has_admitted() { grep -qs '^admitted=' "$BIONIC_GATE_DIR"/requests/*; }
gb_admitted() {  # rc 0 once a request in the store carries an admitted line
  wait_ticks 200 0.05 gb_has_admitted
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
expect_false "(h1) …and nothing is recorded" test -e "$BHREC"
OUTBHB="$(bh_land "$BHT")"; RCBHB=$?
expect_ne    "(h2) a bare land exits non-zero" "0" "$RCBHB"
expect_eq    "(h2) …and no ref moved" "$BH_REFS0" "$(refs_of "$BH")"
OUTBH="$(bh_land "$BHT" --by-hand --reason "the person's why")"; RCBH=$?
expect_eq    "(h3) a hand landing with a reason exits 0" "0" "$RCBH"
expect_match "(h3) …on land's own LANDED line" "*spawn-worktree: LANDED branch=wt/bh-T1 onto=wave/fixture checkout=${BH} merge=* removed=${BHT} proofs=${BHREC}*" "$OUTBH"
BH_PUB="$(grep '^line/v1|ev=published|' "$BHREC" 2>/dev/null)"
expect_regex "(h4) the record's published line carries the user, the time and the reason" \
  "^line/v1\\|ev=published\\|row=T1\\|commit=$(git -C "$BH" rev-parse wave/fixture)\\|kind=hand\\|by=Hand Lander\\|why=the person's why\\|at=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$" "$BH_PUB"
BH_AT="${BH_PUB##*|at=}"
expect_eq    "(h5) the row's - T1: line gains who, when and why" \
  "- T1: active landed-by-hand: Hand Lander ${BH_AT} \"the person's why\"" "$(grep '^- T1:' "$BHP")"

section "§HAND: a hand landing lands a row whose suite is red, writes the person's words on its line, and runs nothing"
#
# A second row of the same plan commits a suite that fails and logs each run of it, and its launch line names that suite
# as the one it lands on. The hand landing merges it all the same: running a suite is no part of it, and none is wanted.
# What the person says of the writer's run (its suites, the commit they were green at, its log) is recorded as verdicts.
printf '| T2 | 4 | build | row two | bh-T2 | — | | 10 | REQ-1 | bh-T2.txt | .worktrees/bh-T2 | | active |\n' >> "$BHP"
awk '{ print } /^- T1:/ { print "- T2: active" }' "$BHP" > "$BHP.n" && mv "$BHP.n" "$BHP"
BHT2="$(new_tree "$BH" wt/bh-T2)"; mkdir -p "$BHT2/tests"
printf '#!/bin/bash\necho run >> "%s"\necho "FAIL: planted"; echo; echo "r.test.sh: 0/1 passed, 1 failed  sections=1 setup=0"; exit 1\n' \
  "$TMP/hand-runs" > "$BHT2/tests/r.test.sh"
git -C "$BHT2" add tests && git -C "$BHT2" commit -qm "T2: a red suite"
printf '%s|row=T2|lands_on=r.test.sh\n' "$(roster_row_fixture status=intended session="$BHSID" name=bh-T2 agent_id=b00T2 plan="$BHP")" \
  >> "$BH/.bionic/tmp/roster-${BHSID}.state"
expect_eq    "(hd0-pre) the planted suite fails, and its run is logged" "1 1" \
  "$( cd "$BHT2" && bash tests/r.test.sh >/dev/null; echo "$? $(awk 'END { print NR }' "$TMP/hand-runs")" )"
: > "$TMP/hand-runs"
BHC2="$(git -C "$BHT2" rev-parse HEAD)"; BH_REFS2="$(refs_of "$BH")"
OUTHD0="$(bh_land "$BHT2" --by-hand --reason "landed on the report" --suites r.test.sh)"; RCHD0=$?
OUTHD="$(bh_land "$BHT2" --by-hand --reason "landed on the report" --suites r.test.sh --green-at "$BHC2" --log /logs/T2-green.log)"; RCHD=$?
expect_eq    "(hd1) the hand landing of a row whose suite is red exits 0, the row's commit on the working branch" "0 yes" \
  "$RCHD $(git -C "$BH" merge-base --is-ancestor "$BHC2" wave/fixture && echo yes)"
expect_contains "(hd2) …and its - T2: line carries the person's words" '"landed on the report"' "$(grep '^- T2:' "$BHP")"
expect_eq    "(hd3) …no suite ran, and the record holds the person's verdict, keyed by the commit it was green at" \
  "0|line/v1|ev=verdict|row=T2|commit=${BHC2}|suite=r.test.sh|result=green|log=/logs/T2-green.log|admitted=-|width=-|promised=-|actual=-" \
  "$(awk 'END { print NR }' "$TMP/hand-runs")|$(grep '|ev=verdict|' "$BHREC" | sed 's/|at=[^|]*$//')"
expect_eq    "(hd3b) …and it built one candidate for its row, on the head before it" "$(git -C "$BH" rev-parse wave/fixture^1)" "$(grep '|ev=candidate|row=T2|' "$BHREC" | sed 's/.*|base=\([^|]*\)|.*/\1/' | paste -sd' ' -)"

# A hand landing that names its suites leaves a ready line that names them too, so the judge and the door read one
# row's suites; with none named, the ready line says none.
printf '| T3 | 4 | build | row three | bh-T3 | — | | 10 | REQ-1 | bh-T3.txt | .worktrees/bh-T3 | | active |\n' >> "$BHP"
awk '{ print } /^- T2:/ { print "- T3: active" }' "$BHP" > "$BHP.n" && mv "$BHP.n" "$BHP"
BHT3="$(new_tree "$BH" wt/bh-T3)"; printf 'three\n' > "$BHT3/three.txt"; git -C "$BHT3" add three.txt && git -C "$BHT3" commit -qm "T3: a row"
printf '%s|row=T3|lands_on=a.test.sh,b.test.sh\n' "$(roster_row_fixture status=intended session="$BHSID" name=bh-T3 agent_id=b00T3 plan="$BHP")" \
  >> "$BH/.bionic/tmp/roster-${BHSID}.state"
BHC3="$(git -C "$BHT3" rev-parse HEAD)"
bh_land "$BHT3" --by-hand --reason "landed on the report" --suites a.test.sh,b.test.sh --green-at "$BHC3" --log /logs/T3-green.log >/dev/null
expect_eq    "(hd4) …and its ready line names the suites the person named, where a landing that named none says none" \
  "a.test.sh,b.test.sh|none" \
  "$(grep '|ev=ready|row=T3|' "$BHREC" | sed 's/.*|suites=\([^|]*\)|.*/\1/')|$(grep '|ev=ready|row=T1|' "$BHREC" | sed 's/.*|suites=\([^|]*\)|.*/\1/')"

BHT4="$(new_tree "$BH" wt/bh-T4)"; mkdir -p "$BHT4/tests"; printf '# the wave-40 run said so\n' > "$BHT4/tests/cited.sh"; git -C "$BHT4" add tests && git -C "$BHT4" commit -qm "T4: a cited comment"; BH_REFS4="$(refs_of "$BH")"
OUTHL="$(bh_land "$BHT4" --by-hand --reason "landed on the report")"; RCHL=$?
expect_eq    "(hl1) a hand landing whose added comment cites the run exits 2 with ready's LINT line, and no ref moved" "2|LINT wt/bh-T4 tests/cited.sh:1 wave|same" "$RCHL|$(printf '%s\n' "$OUTHL" | grep '^LINT ')|$([ "$BH_REFS4" = "$(refs_of "$BH")" ] && echo same)"
finish
